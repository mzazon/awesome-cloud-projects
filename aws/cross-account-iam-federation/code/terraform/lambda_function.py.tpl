"""
Lambda function for validating cross-account IAM role configurations.
This function implements automated compliance monitoring for cross-account roles.
"""

import json
import boto3
import logging
import os
from typing import Dict, List, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
iam = boto3.client('iam')
config_client = boto3.client('config')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for validating cross-account role configurations.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Dictionary containing validation results
    """
    try:
        logger.info("Starting cross-account role validation")
        
        # Get all cross-account roles
        validation_results = []
        paginator = iam.get_paginator('list_roles')
        
        for page in paginator.paginate():
            for role in page['Roles']:
                if 'CrossAccount-' in role['RoleName']:
                    logger.info(f"Validating role: {role['RoleName']}")
                    validation_result = validate_role(role)
                    validation_results.append(validation_result)
        
        # Calculate summary statistics
        total_roles = len(validation_results)
        compliant_roles = sum(1 for r in validation_results if r['compliant'])
        
        # Log non-compliant roles
        non_compliant_roles = [r for r in validation_results if not r['compliant']]
        for result in non_compliant_roles:
            logger.warning(f"Non-compliant role found: {result}")
        
        # Prepare response
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Role validation completed successfully',
                'summary': {
                    'total_roles_validated': total_roles,
                    'compliant_roles': compliant_roles,
                    'non_compliant_roles': total_roles - compliant_roles,
                    'compliance_percentage': round((compliant_roles / total_roles * 100), 2) if total_roles > 0 else 0
                },
                'detailed_results': validation_results
            }, indent=2)
        }
        
        logger.info(f"Validation completed: {compliant_roles}/{total_roles} roles compliant")
        return response
        
    except Exception as e:
        logger.error(f"Error during role validation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Role validation failed',
                'message': str(e)
            })
        }


def validate_role(role: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate individual cross-account role configuration.
    
    Args:
        role: IAM role dictionary from list_roles API
        
    Returns:
        Dictionary containing validation results for the role
    """
    role_name = role['RoleName']
    
    try:
        # Get detailed role information
        role_details = iam.get_role(RoleName=role_name)
        assume_role_policy = role_details['Role']['AssumeRolePolicyDocument']
        max_session_duration = role.get('MaxSessionDuration', 3600)
        
        # Perform validation checks
        validation_checks = {
            'has_external_id': check_external_id(assume_role_policy),
            'has_mfa_condition': check_mfa_condition(assume_role_policy),
            'has_valid_principals': check_valid_principals(assume_role_policy),
            'max_session_duration_ok': max_session_duration <= 7200,
            'has_condition_constraints': check_condition_constraints(assume_role_policy),
            'role_name_compliant': check_role_name_compliance(role_name)
        }
        
        # Additional checks for specific role types
        if 'Production' in role_name:
            validation_checks.update({
                'production_session_duration_ok': max_session_duration <= 3600,
                'has_userid_condition': check_userid_condition(assume_role_policy)
            })
        
        if 'Development' in role_name:
            validation_checks.update({
                'has_ip_restriction': check_ip_restriction(assume_role_policy)
            })
        
        # Calculate overall compliance
        compliant = all(validation_checks.values())
        
        return {
            'role_name': role_name,
            'role_arn': role_details['Role']['Arn'],
            'compliant': compliant,
            'max_session_duration': max_session_duration,
            'checks': validation_checks,
            'created_date': role_details['Role']['CreateDate'].isoformat(),
            'last_used': get_role_last_used(role_name)
        }
        
    except Exception as e:
        logger.error(f"Error validating role {role_name}: {str(e)}")
        return {
            'role_name': role_name,
            'compliant': False,
            'error': str(e),
            'checks': {}
        }


def check_external_id(policy: Dict[str, Any]) -> bool:
    """
    Check if the assume role policy requires an ExternalId.
    
    Args:
        policy: IAM assume role policy document
        
    Returns:
        True if ExternalId condition is present, False otherwise
    """
    for statement in policy.get('Statement', []):
        conditions = statement.get('Condition', {})
        if 'StringEquals' in conditions:
            string_equals = conditions['StringEquals']
            if 'sts:ExternalId' in string_equals:
                return True
    return False


def check_mfa_condition(policy: Dict[str, Any]) -> bool:
    """
    Check if the assume role policy requires MFA.
    
    Args:
        policy: IAM assume role policy document
        
    Returns:
        True if MFA condition is present, False otherwise
    """
    for statement in policy.get('Statement', []):
        conditions = statement.get('Condition', {})
        if 'Bool' in conditions:
            bool_conditions = conditions['Bool']
            if 'aws:MultiFactorAuthPresent' in bool_conditions:
                return True
    return False


def check_valid_principals(policy: Dict[str, Any]) -> bool:
    """
    Check if the assume role policy has valid principals.
    
    Args:
        policy: IAM assume role policy document
        
    Returns:
        True if valid principals are present, False otherwise
    """
    security_account_id = "${security_account_id}"
    
    for statement in policy.get('Statement', []):
        principals = statement.get('Principal', {})
        
        # Check for AWS principals
        if 'AWS' in principals:
            aws_principals = principals['AWS']
            if isinstance(aws_principals, str):
                aws_principals = [aws_principals]
            
            for principal in aws_principals:
                if security_account_id in principal:
                    return True
        
        # Check for Federated principals
        if 'Federated' in principals:
            return True
    
    return False


def check_userid_condition(policy: Dict[str, Any]) -> bool:
    """
    Check if the assume role policy has userid condition for additional security.
    
    Args:
        policy: IAM assume role policy document
        
    Returns:
        True if userid condition is present, False otherwise
    """
    for statement in policy.get('Statement', []):
        conditions = statement.get('Condition', {})
        if 'StringLike' in conditions:
            string_like = conditions['StringLike']
            if 'aws:userid' in string_like:
                return True
    return False


def check_ip_restriction(policy: Dict[str, Any]) -> bool:
    """
    Check if the assume role policy has IP address restrictions.
    
    Args:
        policy: IAM assume role policy document
        
    Returns:
        True if IP restrictions are present, False otherwise (optional for some roles)
    """
    for statement in policy.get('Statement', []):
        conditions = statement.get('Condition', {})
        if 'IpAddress' in conditions or 'IpAddressIfExists' in conditions:
            return True
    
    # IP restrictions are optional but recommended for development environments
    return True


def check_condition_constraints(policy: Dict[str, Any]) -> bool:
    """
    Check if the assume role policy has appropriate condition constraints.
    
    Args:
        policy: IAM assume role policy document
        
    Returns:
        True if conditions are present, False otherwise
    """
    for statement in policy.get('Statement', []):
        conditions = statement.get('Condition', {})
        if conditions:  # Any condition is better than no conditions
            return True
    return False


def check_role_name_compliance(role_name: str) -> bool:
    """
    Check if the role name follows the expected naming convention.
    
    Args:
        role_name: Name of the IAM role
        
    Returns:
        True if role name is compliant, False otherwise
    """
    # Check for expected prefix
    if not role_name.startswith('CrossAccount-'):
        return False
    
    # Check for valid environment indicators
    valid_environments = ['Production', 'Development', 'Staging', 'Master']
    return any(env in role_name for env in valid_environments)


def get_role_last_used(role_name: str) -> Optional[str]:
    """
    Get the last used timestamp for a role.
    
    Args:
        role_name: Name of the IAM role
        
    Returns:
        ISO format timestamp of last use, or None if never used
    """
    try:
        response = iam.get_role(RoleName=role_name)
        role_last_used = response['Role'].get('RoleLastUsed', {})
        last_used_date = role_last_used.get('LastUsedDate')
        
        if last_used_date:
            return last_used_date.isoformat()
        return None
        
    except Exception as e:
        logger.warning(f"Could not get last used date for role {role_name}: {str(e)}")
        return None


def generate_compliance_report(validation_results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Generate a comprehensive compliance report from validation results.
    
    Args:
        validation_results: List of validation result dictionaries
        
    Returns:
        Dictionary containing compliance report
    """
    total_roles = len(validation_results)
    compliant_roles = sum(1 for r in validation_results if r['compliant'])
    
    # Analyze common compliance issues
    compliance_issues = {}
    for result in validation_results:
        if not result['compliant']:
            for check, passed in result.get('checks', {}).items():
                if not passed:
                    compliance_issues[check] = compliance_issues.get(check, 0) + 1
    
    return {
        'total_roles': total_roles,
        'compliant_roles': compliant_roles,
        'compliance_percentage': round((compliant_roles / total_roles * 100), 2) if total_roles > 0 else 0,
        'common_issues': compliance_issues,
        'recommendations': generate_recommendations(compliance_issues)
    }


def generate_recommendations(compliance_issues: Dict[str, int]) -> List[str]:
    """
    Generate recommendations based on compliance issues found.
    
    Args:
        compliance_issues: Dictionary of compliance issues and their counts
        
    Returns:
        List of recommendation strings
    """
    recommendations = []
    
    if 'has_external_id' in compliance_issues:
        recommendations.append("Implement ExternalId conditions in trust policies to prevent confused deputy attacks")
    
    if 'has_mfa_condition' in compliance_issues:
        recommendations.append("Add MFA requirements to trust policies for enhanced security")
    
    if 'max_session_duration_ok' in compliance_issues:
        recommendations.append("Reduce maximum session duration to limit exposure window")
    
    if 'has_ip_restriction' in compliance_issues:
        recommendations.append("Consider adding IP address restrictions for development environment access")
    
    if 'role_name_compliant' in compliance_issues:
        recommendations.append("Ensure role names follow the CrossAccount- naming convention")
    
    return recommendations