"""
Security Remediation Lambda Function

This function performs automated remediation of security findings based on
classification and severity. It implements safe, reversible remediation actions
for common security issues while maintaining audit trails.

Environment Variables:
- ENVIRONMENT: Deployment environment (dev, staging, prod)
- PROJECT: Project name for tagging and identification
- AUTO_REMEDIATION_ENABLED: Enable/disable automatic remediation
- SEVERITY_THRESHOLD: Minimum severity level for auto-remediation
"""

import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, Any, List, Optional
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ec2 = boto3.client('ec2')
iam = boto3.client('iam')
s3 = boto3.client('s3')
securityhub = boto3.client('securityhub')

# Environment configuration
ENVIRONMENT = os.environ.get('ENVIRONMENT', '${environment}')
PROJECT = os.environ.get('PROJECT', '${project}')
AUTO_REMEDIATION_ENABLED = os.environ.get('AUTO_REMEDIATION_ENABLED', '${auto_remediation_enabled}').lower() == 'true'
SEVERITY_THRESHOLD = os.environ.get('SEVERITY_THRESHOLD', '${severity_threshold}')

# Severity level mapping for comparison
SEVERITY_LEVELS = {
    'CRITICAL': 4,
    'HIGH': 3,
    'MEDIUM': 2,
    'LOW': 1,
    'INFORMATIONAL': 0
}


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for security finding remediation.
    
    Args:
        event: EventBridge event containing Security Hub finding
        context: Lambda context object
        
    Returns:
        Dict containing remediation results and status
    """
    try:
        logger.info(f"Processing remediation event in {ENVIRONMENT} environment")
        logger.info(f"Auto-remediation enabled: {AUTO_REMEDIATION_ENABLED}, Threshold: {SEVERITY_THRESHOLD}")
        
        # Extract finding details
        finding = event['detail']['findings'][0]
        finding_id = finding['Id']
        product_arn = finding['ProductArn']
        severity = finding['Severity']['Label']
        title = finding['Title']
        resources = finding.get('Resources', [])
        
        logger.info(f"Processing finding: {finding_id}, Severity: {severity}, Title: {title}")
        
        # Check if auto-remediation should proceed
        if not should_auto_remediate(severity, finding):
            logger.info(f"Skipping auto-remediation for finding {finding_id}")
            return create_response('SKIPPED', 'Auto-remediation not enabled or severity below threshold', finding_id)
        
        # Determine and perform remediation action
        remediation_result = perform_remediation(finding, resources)
        
        # Update Security Hub finding with remediation status
        update_finding_status(finding_id, product_arn, remediation_result)
        
        logger.info(f"Remediation completed for finding {finding_id}: {remediation_result['status']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                **remediation_result,
                'findingId': finding_id,
                'environment': ENVIRONMENT,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error in remediation processing: {str(e)}")
        logger.error(f"Event details: {json.dumps(event, default=str)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'environment': ENVIRONMENT,
                'timestamp': datetime.utcnow().isoformat()
            })
        }


def should_auto_remediate(severity: str, finding: Dict[str, Any]) -> bool:
    """
    Determine if auto-remediation should proceed based on configuration and finding details.
    
    Args:
        severity: Finding severity level
        finding: Security Hub finding object
        
    Returns:
        Boolean indicating if auto-remediation should proceed
    """
    if not AUTO_REMEDIATION_ENABLED:
        logger.info("Auto-remediation is disabled")
        return False
    
    # Check severity threshold
    finding_severity_level = SEVERITY_LEVELS.get(severity, 0)
    threshold_level = SEVERITY_LEVELS.get(SEVERITY_THRESHOLD, 3)
    
    if finding_severity_level < threshold_level:
        logger.info(f"Finding severity {severity} below threshold {SEVERITY_THRESHOLD}")
        return False
    
    # Check for production environment restrictions
    if ENVIRONMENT == 'prod':
        # Additional safety checks for production
        workflow_state = finding.get('WorkflowState', 'NEW')
        if workflow_state != 'NEW':
            logger.info(f"Skipping remediation for non-NEW finding in production: {workflow_state}")
            return False
    
    return True


def perform_remediation(finding: Dict[str, Any], resources: List[Dict]) -> Dict[str, Any]:
    """
    Perform automated remediation based on finding type and content.
    
    Args:
        finding: Security Hub finding object
        resources: List of affected resources
        
    Returns:
        Dict containing remediation results
    """
    title = finding['Title'].lower()
    description = finding.get('Description', '').lower()
    finding_types = finding.get('Types', [])
    
    logger.info(f"Analyzing remediation options for: {title}")
    
    try:
        # Security Group remediation
        if 'security group' in title and any(keyword in title for keyword in ['open', 'exposed', 'internet']):
            return remediate_security_group(finding, resources)
        
        # S3 bucket security remediation
        elif 's3' in title and any(keyword in title for keyword in ['public', 'exposed', 'open']):
            return remediate_s3_bucket(finding, resources)
        
        # IAM policy remediation (requires manual review)
        elif any(keyword in title for keyword in ['iam', 'policy', 'permission']) and 'overly permissive' in title:
            return remediate_iam_policy(finding, resources)
        
        # Encryption remediation
        elif any(keyword in title for keyword in ['encryption', 'encrypted', 'ssl', 'tls']):
            return remediate_encryption_issue(finding, resources)
        
        # CloudTrail logging remediation
        elif 'cloudtrail' in title or 'logging' in title:
            return remediate_logging_issue(finding, resources)
        
        # Default action for other findings
        else:
            return {
                'action': 'MANUAL_REVIEW_REQUIRED',
                'status': 'PENDING',
                'message': f'Finding type requires manual investigation: {title}',
                'remediation_applied': False,
                'next_steps': 'Security team review required'
            }
            
    except Exception as e:
        logger.error(f"Remediation failed: {str(e)}")
        return {
            'action': 'REMEDIATION_FAILED',
            'status': 'ERROR',
            'message': str(e),
            'remediation_applied': False,
            'next_steps': 'Manual intervention required'
        }


def remediate_security_group(finding: Dict[str, Any], resources: List[Dict]) -> Dict[str, Any]:
    """
    Remediate overly permissive security group rules.
    
    This function identifies and restricts security groups that allow
    unrestricted access from the internet (0.0.0.0/0).
    """
    logger.info("Starting security group remediation")
    
    for resource in resources:
        if resource['Type'] == 'AwsEc2SecurityGroup':
            sg_id = resource['Id'].split('/')[-1]
            
            try:
                # Get security group details
                response = ec2.describe_security_groups(GroupIds=[sg_id])
                sg = response['SecurityGroups'][0]
                
                logger.info(f"Analyzing security group {sg_id}")
                
                remediation_actions = []
                
                # Check ingress rules for overly permissive access
                for rule in sg.get('IpPermissions', []):
                    for ip_range in rule.get('IpRanges', []):
                        if ip_range.get('CidrIp') == '0.0.0.0/0':
                            # Create backup tag before modification
                            create_security_group_backup_tag(sg_id, rule)
                            
                            # Remove overly permissive rule
                            ec2.revoke_security_group_ingress(
                                GroupId=sg_id,
                                IpPermissions=[rule]
                            )
                            
                            # Add more restrictive rule based on port
                            restricted_rule = create_restricted_rule(rule)
                            if restricted_rule:
                                ec2.authorize_security_group_ingress(
                                    GroupId=sg_id,
                                    IpPermissions=[restricted_rule]
                                )
                                
                                remediation_actions.append(f"Restricted port {rule.get('FromPort', 'all')} to internal networks")
                            else:
                                remediation_actions.append(f"Removed unrestricted access for port {rule.get('FromPort', 'all')}")
                
                if remediation_actions:
                    return {
                        'action': 'SECURITY_GROUP_RESTRICTED',
                        'status': 'SUCCESS',
                        'message': f'Successfully restricted security group {sg_id}',
                        'remediation_applied': True,
                        'details': remediation_actions,
                        'reversible': True,
                        'backup_info': f'Original rules tagged for recovery'
                    }
                else:
                    return {
                        'action': 'NO_REMEDIATION_NEEDED',
                        'status': 'SUCCESS',
                        'message': f'Security group {sg_id} does not require remediation',
                        'remediation_applied': False
                    }
                    
            except ClientError as e:
                error_code = e.response['Error']['Code']
                if error_code == 'InvalidGroupId.NotFound':
                    return {
                        'action': 'RESOURCE_NOT_FOUND',
                        'status': 'SKIPPED',
                        'message': f'Security group {sg_id} not found',
                        'remediation_applied': False
                    }
                else:
                    raise e
    
    return {
        'action': 'NO_SECURITY_GROUP_FOUND',
        'status': 'SKIPPED',
        'message': 'No security group resource found in finding',
        'remediation_applied': False
    }


def remediate_s3_bucket(finding: Dict[str, Any], resources: List[Dict]) -> Dict[str, Any]:
    """
    Remediate public S3 bucket access by applying secure bucket policies
    and enabling public access block settings.
    """
    logger.info("Starting S3 bucket remediation")
    
    for resource in resources:
        if resource['Type'] == 'AwsS3Bucket':
            bucket_name = resource['Id'].split('/')[-1]
            
            try:
                # Enable S3 public access block
                s3.put_public_access_block(
                    Bucket=bucket_name,
                    PublicAccessBlockConfiguration={
                        'BlockPublicAcls': True,
                        'IgnorePublicAcls': True,
                        'BlockPublicPolicy': True,
                        'RestrictPublicBuckets': True
                    }
                )
                
                # Apply restrictive bucket policy
                restrictive_policy = create_secure_bucket_policy(bucket_name)
                s3.put_bucket_policy(
                    Bucket=bucket_name,
                    Policy=json.dumps(restrictive_policy)
                )
                
                return {
                    'action': 'S3_BUCKET_SECURED',
                    'status': 'SUCCESS',
                    'message': f'Applied security controls to bucket {bucket_name}',
                    'remediation_applied': True,
                    'details': [
                        'Enabled public access block',
                        'Applied restrictive bucket policy',
                        'Enforced HTTPS-only access'
                    ],
                    'reversible': True
                }
                
            except ClientError as e:
                error_code = e.response['Error']['Code']
                if error_code == 'NoSuchBucket':
                    return {
                        'action': 'RESOURCE_NOT_FOUND',
                        'status': 'SKIPPED',
                        'message': f'S3 bucket {bucket_name} not found',
                        'remediation_applied': False
                    }
                else:
                    logger.error(f"S3 remediation failed: {str(e)}")
                    return {
                        'action': 'S3_BUCKET_REMEDIATION_FAILED',
                        'status': 'ERROR',
                        'message': f'Failed to secure bucket {bucket_name}: {str(e)}',
                        'remediation_applied': False
                    }
    
    return {
        'action': 'NO_S3_BUCKET_FOUND',
        'status': 'SKIPPED',
        'message': 'No S3 bucket resource found in finding',
        'remediation_applied': False
    }


def remediate_iam_policy(finding: Dict[str, Any], resources: List[Dict]) -> Dict[str, Any]:
    """
    Handle IAM policy remediation (requires manual review for security).
    
    IAM policy changes are sensitive and require human review to prevent
    service disruption or security issues.
    """
    logger.info("IAM policy finding detected - manual review required")
    
    return {
        'action': 'IAM_POLICY_REVIEW_REQUIRED',
        'status': 'PENDING',
        'message': 'IAM policy changes require manual security review',
        'remediation_applied': False,
        'next_steps': [
            'Review IAM policy permissions',
            'Apply principle of least privilege',
            'Test policy changes in non-production environment',
            'Document business justification for permissions'
        ],
        'manual_review_required': True
    }


def remediate_encryption_issue(finding: Dict[str, Any], resources: List[Dict]) -> Dict[str, Any]:
    """
    Remediate encryption-related security findings.
    """
    logger.info("Starting encryption remediation")
    
    # This is a placeholder for encryption remediation
    # Actual implementation would depend on the specific resource type
    return {
        'action': 'ENCRYPTION_REVIEW_REQUIRED',
        'status': 'PENDING',
        'message': 'Encryption configuration requires manual review',
        'remediation_applied': False,
        'next_steps': [
            'Review encryption settings for affected resources',
            'Enable encryption at rest and in transit',
            'Configure appropriate KMS key policies',
            'Validate encryption compliance'
        ]
    }


def remediate_logging_issue(finding: Dict[str, Any], resources: List[Dict]) -> Dict[str, Any]:
    """
    Remediate logging and monitoring related findings.
    """
    logger.info("Starting logging remediation")
    
    return {
        'action': 'LOGGING_CONFIGURATION_REQUIRED',
        'status': 'PENDING',
        'message': 'Logging configuration requires manual setup',
        'remediation_applied': False,
        'next_steps': [
            'Enable CloudTrail logging',
            'Configure appropriate log retention',
            'Set up log monitoring and alerting',
            'Ensure log integrity and access controls'
        ]
    }


def create_restricted_rule(original_rule: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Create a more restrictive version of a security group rule.
    
    Args:
        original_rule: Original security group rule
        
    Returns:
        Modified rule with restricted access or None if rule should be removed
    """
    port = original_rule.get('FromPort')
    protocol = original_rule.get('IpProtocol', 'tcp')
    
    # Define safe internal CIDR ranges
    internal_cidrs = ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16']
    
    # For common services, allow restricted access
    if port in [80, 443]:  # HTTP/HTTPS
        restricted_rule = original_rule.copy()
        restricted_rule['IpRanges'] = [
            {'CidrIp': '10.0.0.0/8', 'Description': 'Internal network access only'}
        ]
        return restricted_rule
    elif port == 22:  # SSH
        restricted_rule = original_rule.copy()
        restricted_rule['IpRanges'] = [
            {'CidrIp': '10.0.0.0/8', 'Description': 'Internal SSH access only'}
        ]
        return restricted_rule
    elif port == 3389:  # RDP
        restricted_rule = original_rule.copy()
        restricted_rule['IpRanges'] = [
            {'CidrIp': '10.0.0.0/8', 'Description': 'Internal RDP access only'}
        ]
        return restricted_rule
    
    # For other ports, remove public access entirely
    return None


def create_secure_bucket_policy(bucket_name: str) -> Dict[str, Any]:
    """
    Create a secure S3 bucket policy that enforces HTTPS and restricts access.
    
    Args:
        bucket_name: Name of the S3 bucket
        
    Returns:
        Secure bucket policy document
    """
    return {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "DenyInsecureConnections",
                "Effect": "Deny",
                "Principal": "*",
                "Action": "s3:*",
                "Resource": [
                    f"arn:aws:s3:::{bucket_name}",
                    f"arn:aws:s3:::{bucket_name}/*"
                ],
                "Condition": {
                    "Bool": {
                        "aws:SecureTransport": "false"
                    }
                }
            },
            {
                "Sid": "DenyUnSecuredObjectUploads",
                "Effect": "Deny",
                "Principal": "*",
                "Action": "s3:PutObject",
                "Resource": f"arn:aws:s3:::{bucket_name}/*",
                "Condition": {
                    "StringNotEquals": {
                        "s3:x-amz-server-side-encryption": "AES256"
                    }
                }
            }
        ]
    }


def create_security_group_backup_tag(sg_id: str, rule: Dict[str, Any]) -> None:
    """
    Create a backup tag with original rule information for recovery purposes.
    
    Args:
        sg_id: Security group ID
        rule: Original security group rule
    """
    try:
        timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
        tag_value = json.dumps(rule, default=str)[:255]  # AWS tag value limit
        
        ec2.create_tags(
            Resources=[sg_id],
            Tags=[
                {
                    'Key': f'SecurityResponse-Backup-{timestamp}',
                    'Value': tag_value
                },
                {
                    'Key': 'SecurityResponse-ModifiedBy',
                    'Value': f'{PROJECT}-remediation-function'
                }
            ]
        )
        logger.info(f"Created backup tag for security group {sg_id}")
    except Exception as e:
        logger.warning(f"Failed to create backup tag: {str(e)}")


def update_finding_status(finding_id: str, product_arn: str, remediation_result: Dict[str, Any]) -> None:
    """
    Update Security Hub finding with remediation status and details.
    
    Args:
        finding_id: Security Hub finding ID
        product_arn: Product ARN for the finding
        remediation_result: Results from remediation attempt
    """
    try:
        workflow_status = 'RESOLVED' if remediation_result['status'] == 'SUCCESS' and remediation_result.get('remediation_applied') else 'NEW'
        
        securityhub.batch_update_findings(
            FindingIdentifiers=[
                {
                    'Id': finding_id,
                    'ProductArn': product_arn
                }
            ],
            Note={
                'Text': f'Auto-remediation: {remediation_result["action"]} - {remediation_result["status"]} (Environment: {ENVIRONMENT})',
                'UpdatedBy': f'SecurityIncidentResponse-{PROJECT}'
            },
            UserDefinedFields={
                'RemediationAction': remediation_result['action'],
                'RemediationStatus': remediation_result['status'],
                'RemediationTimestamp': datetime.utcnow().isoformat(),
                'RemediationApplied': str(remediation_result.get('remediation_applied', False)).lower(),
                'RemediationReversible': str(remediation_result.get('reversible', False)).lower(),
                'ProcessedBy': f'{PROJECT}-remediation-function',
                'Environment': ENVIRONMENT
            },
            Workflow={
                'Status': workflow_status
            }
        )
        logger.info(f"Updated finding {finding_id} with remediation status")
    except Exception as e:
        logger.error(f"Failed to update finding status: {str(e)}")


def create_response(status: str, message: str, finding_id: str = None) -> Dict[str, Any]:
    """
    Create a standardized response object.
    
    Args:
        status: Response status
        message: Response message
        finding_id: Optional finding ID
        
    Returns:
        Standardized response dictionary
    """
    return {
        'statusCode': 200,
        'body': json.dumps({
            'status': status,
            'message': message,
            'findingId': finding_id,
            'environment': ENVIRONMENT,
            'timestamp': datetime.utcnow().isoformat()
        })
    }