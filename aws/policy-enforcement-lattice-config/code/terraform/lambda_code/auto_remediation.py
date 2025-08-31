"""
VPC Lattice Auto-Remediation Lambda Function

This function automatically remediates VPC Lattice compliance violations
by applying corrective actions when non-compliant resources are detected.
It is triggered by SNS notifications from the compliance evaluator.
"""

import json
import boto3
import logging
import os
import re
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for automatically remediating VPC Lattice compliance violations.
    
    Args:
        event: SNS message event containing compliance violation details
        context: Lambda context object
        
    Returns:
        Dict with status code and response body
    """
    
    lattice_client = boto3.client('vpc-lattice')
    config_client = boto3.client('config')
    
    try:
        # Parse SNS message
        if 'Records' not in event or not event['Records']:
            logger.error("No SNS records found in event")
            return {'statusCode': 400, 'body': 'Invalid event format'}
        
        sns_record = event['Records'][0]
        if sns_record.get('EventSource') != 'aws:sns':
            logger.error("Event is not from SNS")
            return {'statusCode': 400, 'body': 'Event not from SNS'}
        
        message = sns_record['Sns']['Message']
        logger.info(f"Processing SNS message: {message}")
        
        # Extract resource information from the message
        resource_info = parse_compliance_message(message)
        if not resource_info:
            logger.error("Unable to extract resource information from message")
            return {'statusCode': 400, 'body': 'Unable to parse message'}
        
        resource_id = resource_info['resource_id']
        issue = resource_info['issue']
        
        logger.info(f"Attempting remediation for resource: {resource_id}")
        
        # Attempt remediation based on resource type and issue
        remediation_result = perform_remediation(lattice_client, resource_id, issue)
        
        if remediation_result['success']:
            logger.info(f"Remediation successful for {resource_id}: {remediation_result['action']}")
            
            # Trigger Config re-evaluation after remediation
            config_rule_name = os.environ.get('CONFIG_RULE_NAME')
            if config_rule_name:
                try:
                    config_client.start_config_rules_evaluation(
                        ConfigRuleNames=[config_rule_name]
                    )
                    logger.info(f"Triggered re-evaluation of Config rule: {config_rule_name}")
                except Exception as e:
                    logger.warning(f"Failed to trigger Config re-evaluation: {str(e)}")
        else:
            logger.warning(f"Remediation failed for {resource_id}: {remediation_result['reason']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'resource_id': resource_id,
                'remediation_success': remediation_result['success'],
                'action_taken': remediation_result.get('action', 'None'),
                'reason': remediation_result.get('reason', 'Success')
            })
        }
        
    except Exception as e:
        logger.error(f"Remediation failed with error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Remediation failed: {str(e)}')
        }

def parse_compliance_message(message: str) -> Optional[Dict[str, str]]:
    """
    Parse compliance violation message to extract resource information.
    
    Args:
        message: SNS message containing compliance violation details
        
    Returns:
        Dict containing resource_id and issue, or None if parsing fails
    """
    try:
        # Extract resource ID using regex
        resource_id_match = re.search(r'Resource ID:\s*(\S+)', message)
        if not resource_id_match:
            logger.error("Could not find Resource ID in message")
            return None
        
        resource_id = resource_id_match.group(1)
        
        # Extract issue description
        issue_match = re.search(r'Issue:\s*(.+?)(?:\n|$)', message)
        issue = issue_match.group(1) if issue_match else "Unknown issue"
        
        return {
            'resource_id': resource_id,
            'issue': issue.strip()
        }
        
    except Exception as e:
        logger.error(f"Error parsing compliance message: {str(e)}")
        return None

def perform_remediation(client: Any, resource_id: str, issue: str) -> Dict[str, Any]:
    """
    Perform remediation actions based on the compliance violation.
    
    Args:
        client: VPC Lattice boto3 client
        resource_id: ID of the non-compliant resource
        issue: Description of the compliance issue
        
    Returns:
        Dict with remediation results
    """
    try:
        # Determine resource type from ID or issue description
        if 'service-network' in resource_id or 'service network' in issue.lower():
            return remediate_service_network(client, resource_id, issue)
        elif 'service' in resource_id or 'service' in issue.lower():
            return remediate_service(client, resource_id, issue)
        else:
            return {
                'success': False,
                'reason': f"Unknown resource type for ID: {resource_id}"
            }
            
    except Exception as e:
        logger.error(f"Error during remediation: {str(e)}")
        return {
            'success': False,
            'reason': f"Remediation error: {str(e)}"
        }

def remediate_service_network(client: Any, network_id: str, issue: str) -> Dict[str, Any]:
    """
    Apply remediation to VPC Lattice service network.
    
    Args:
        client: VPC Lattice boto3 client
        network_id: Service network identifier
        issue: Description of the compliance issue
        
    Returns:
        Dict with remediation results
    """
    try:
        # Check if service network exists
        try:
            response = client.get_service_network(serviceNetworkIdentifier=network_id)
            network = response['serviceNetwork']
        except client.exceptions.ResourceNotFoundException:
            return {
                'success': False,
                'reason': 'Service network not found'
            }
        
        actions_taken = []
        
        # Remediate missing auth policy
        if 'missing required auth policy' in issue.lower():
            auth_policy_result = apply_default_auth_policy(client, network_id)
            if auth_policy_result['success']:
                actions_taken.append('Applied default auth policy')
            else:
                return auth_policy_result
        
        # Remediate authentication issues
        if 'authentication' in issue.lower() and network.get('authType') == 'NONE':
            try:
                client.update_service_network(
                    serviceNetworkIdentifier=network_id,
                    authType='AWS_IAM'
                )
                actions_taken.append('Enabled AWS_IAM authentication')
            except Exception as e:
                logger.error(f"Failed to update service network auth type: {str(e)}")
                return {
                    'success': False,
                    'reason': f"Failed to update auth type: {str(e)}"
                }
        
        if actions_taken:
            return {
                'success': True,
                'action': '; '.join(actions_taken)
            }
        else:
            return {
                'success': False,
                'reason': f"No remediation action available for issue: {issue}"
            }
            
    except Exception as e:
        logger.error(f"Failed to remediate service network {network_id}: {str(e)}")
        return {
            'success': False,
            'reason': f"Service network remediation failed: {str(e)}"
        }

def remediate_service(client: Any, service_id: str, issue: str) -> Dict[str, Any]:
    """
    Apply remediation to VPC Lattice service.
    
    Args:
        client: VPC Lattice boto3 client
        service_id: Service identifier
        issue: Description of the compliance issue
        
    Returns:
        Dict with remediation results
    """
    try:
        # Check if service exists
        try:
            response = client.get_service(serviceIdentifier=service_id)
            service = response['service']
        except client.exceptions.ResourceNotFoundException:
            return {
                'success': False,
                'reason': 'Service not found'
            }
        
        # Remediate authentication issues
        if 'authentication' in issue.lower() and service.get('authType') == 'NONE':
            try:
                client.update_service(
                    serviceIdentifier=service_id,
                    authType='AWS_IAM'
                )
                logger.info(f"Updated service authentication for: {service_id}")
                return {
                    'success': True,
                    'action': 'Enabled AWS_IAM authentication for service'
                }
            except Exception as e:
                logger.error(f"Failed to update service auth type: {str(e)}")
                return {
                    'success': False,
                    'reason': f"Failed to update service auth: {str(e)}"
                }
        
        return {
            'success': False,
            'reason': f"No remediation action available for issue: {issue}"
        }
        
    except Exception as e:
        logger.error(f"Failed to remediate service {service_id}: {str(e)}")
        return {
            'success': False,
            'reason': f"Service remediation failed: {str(e)}"
        }

def apply_default_auth_policy(client: Any, network_id: str) -> Dict[str, Any]:
    """
    Apply a default auth policy to a VPC Lattice service network.
    
    Args:
        client: VPC Lattice boto3 client
        network_id: Service network identifier
        
    Returns:
        Dict with operation results
    """
    try:
        # Create a basic auth policy that allows access from the same AWS account
        account_id = os.environ.get('AWS_ACCOUNT_ID')
        if not account_id:
            return {
                'success': False,
                'reason': 'AWS_ACCOUNT_ID environment variable not set'
            }
        
        auth_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": "*",
                    "Action": "vpc-lattice-svcs:*",
                    "Resource": "*",
                    "Condition": {
                        "StringEquals": {
                            "aws:PrincipalAccount": account_id
                        }
                    }
                }
            ]
        }
        
        client.put_auth_policy(
            resourceIdentifier=network_id,
            policy=json.dumps(auth_policy)
        )
        
        logger.info(f"Applied default auth policy to service network: {network_id}")
        return {
            'success': True,
            'action': 'Applied default auth policy'
        }
        
    except Exception as e:
        logger.error(f"Failed to apply auth policy to {network_id}: {str(e)}")
        return {
            'success': False,
            'reason': f"Failed to apply auth policy: {str(e)}"
        }