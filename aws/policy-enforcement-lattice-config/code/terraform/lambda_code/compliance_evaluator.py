"""
VPC Lattice Compliance Evaluator Lambda Function

This function evaluates VPC Lattice resources for compliance with organizational
security policies. It is triggered by AWS Config when VPC Lattice resources
change and determines whether they meet security requirements.
"""

import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, Tuple, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for evaluating VPC Lattice resource compliance.
    
    Args:
        event: AWS Config rule invocation event
        context: Lambda context object
        
    Returns:
        Dict with status code and response body
    """
    
    config_client = boto3.client('config')
    lattice_client = boto3.client('vpc-lattice')
    sns_client = boto3.client('sns')
    
    # Parse Config rule invocation
    configuration_item = event['configurationItem']
    rule_parameters = json.loads(event.get('ruleParameters', '{}'))
    
    compliance_type = 'COMPLIANT'
    annotation = 'Resource is compliant with security policies'
    
    try:
        resource_type = configuration_item['resourceType']
        resource_id = configuration_item['resourceId']
        
        logger.info(f"Evaluating {resource_type} resource: {resource_id}")
        
        if resource_type == 'AWS::VpcLattice::ServiceNetwork':
            compliance_type, annotation = evaluate_service_network(
                lattice_client, resource_id, rule_parameters
            )
        elif resource_type == 'AWS::VpcLattice::Service':
            compliance_type, annotation = evaluate_service(
                lattice_client, resource_id, rule_parameters
            )
        else:
            compliance_type = 'NOT_APPLICABLE'
            annotation = f"Resource type {resource_type} not supported"
        
        logger.info(f"Evaluation result: {compliance_type} - {annotation}")
        
        # Send notification if non-compliant
        if compliance_type == 'NON_COMPLIANT':
            send_compliance_notification(sns_client, resource_id, annotation)
            
    except Exception as e:
        logger.error(f"Error evaluating compliance: {str(e)}")
        compliance_type = 'NOT_APPLICABLE'
        annotation = f"Error during evaluation: {str(e)}"
    
    # Return evaluation result to Config
    try:
        config_client.put_evaluations(
            Evaluations=[
                {
                    'ComplianceResourceType': configuration_item['resourceType'],
                    'ComplianceResourceId': configuration_item['resourceId'],
                    'ComplianceType': compliance_type,
                    'Annotation': annotation[:256],  # Config has 256 char limit
                    'OrderingTimestamp': configuration_item['configurationItemCaptureTime']
                }
            ],
            ResultToken=event['resultToken']
        )
        logger.info("Successfully submitted evaluation to AWS Config")
    except Exception as e:
        logger.error(f"Failed to submit evaluation to Config: {str(e)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Evaluation complete: {compliance_type}')
    }

def evaluate_service_network(client: Any, network_id: str, parameters: Dict[str, str]) -> Tuple[str, str]:
    """
    Evaluate VPC Lattice service network compliance.
    
    Args:
        client: VPC Lattice boto3 client
        network_id: Service network identifier
        parameters: Rule parameters from AWS Config
        
    Returns:
        Tuple of (compliance_type, annotation)
    """
    try:
        # Get service network details
        response = client.get_service_network(serviceNetworkIdentifier=network_id)
        network = response['serviceNetwork']
        
        logger.info(f"Evaluating service network: {network.get('name', 'Unknown')}")
        
        # Check for auth policy requirement
        require_auth_policy = parameters.get('requireAuthPolicy', 'true').lower() == 'true'
        if require_auth_policy:
            try:
                client.get_auth_policy(resourceIdentifier=network_id)
                logger.info("Auth policy found for service network")
            except client.exceptions.ResourceNotFoundException:
                return 'NON_COMPLIANT', 'Service network missing required auth policy'
            except Exception as e:
                logger.warning(f"Unable to check auth policy: {str(e)}")
        
        # Check network name compliance
        name_prefix = parameters.get('namePrefix', 'secure-')
        if name_prefix and not network['name'].startswith(name_prefix):
            return 'NON_COMPLIANT', f"Service network name must start with '{name_prefix}'"
        
        # Check auth type
        if network.get('authType') == 'NONE':
            return 'NON_COMPLIANT', 'Service network must have authentication enabled'
        
        return 'COMPLIANT', 'Service network meets all security requirements'
        
    except client.exceptions.ResourceNotFoundException:
        return 'NOT_APPLICABLE', 'Service network not found'
    except Exception as e:
        logger.error(f"Error evaluating service network: {str(e)}")
        return 'NOT_APPLICABLE', f"Unable to evaluate service network: {str(e)}"

def evaluate_service(client: Any, service_id: str, parameters: Dict[str, str]) -> Tuple[str, str]:
    """
    Evaluate VPC Lattice service compliance.
    
    Args:
        client: VPC Lattice boto3 client
        service_id: Service identifier
        parameters: Rule parameters from AWS Config
        
    Returns:
        Tuple of (compliance_type, annotation)
    """
    try:
        response = client.get_service(serviceIdentifier=service_id)
        service = response['service']
        
        logger.info(f"Evaluating service: {service.get('name', 'Unknown')}")
        
        # Check auth type requirement
        require_auth = parameters.get('requireAuth', 'true').lower() == 'true'
        if require_auth and service.get('authType') == 'NONE':
            return 'NON_COMPLIANT', 'Service must have authentication enabled'
        
        # Check service name compliance (if applicable)
        name_prefix = parameters.get('serviceNamePrefix', '')
        if name_prefix and not service['name'].startswith(name_prefix):
            return 'NON_COMPLIANT', f"Service name must start with '{name_prefix}'"
        
        return 'COMPLIANT', 'Service meets security requirements'
        
    except client.exceptions.ResourceNotFoundException:
        return 'NOT_APPLICABLE', 'Service not found'
    except Exception as e:
        logger.error(f"Error evaluating service: {str(e)}")
        return 'NOT_APPLICABLE', f"Unable to evaluate service: {str(e)}"

def send_compliance_notification(sns_client: Any, resource_id: str, message: str) -> None:
    """
    Send SNS notification for compliance violations.
    
    Args:
        sns_client: SNS boto3 client
        resource_id: ID of the non-compliant resource
        message: Compliance violation message
    """
    try:
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        if not sns_topic_arn:
            logger.error("SNS_TOPIC_ARN environment variable not set")
            return
        
        notification_message = f"""
VPC Lattice Compliance Violation Detected

Resource ID: {resource_id}
Issue: {message}
Timestamp: {datetime.utcnow().isoformat()}
AWS Region: {os.environ.get('AWS_REGION', 'Unknown')}

Action Required:
Please review and remediate this resource immediately to ensure compliance
with organizational security policies.

Automatic remediation: {"Enabled" if os.environ.get('AUTO_REMEDIATION', 'false').lower() == 'true' else "Disabled"}
        """.strip()
        
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Subject='VPC Lattice Compliance Violation Detected',
            Message=notification_message
        )
        logger.info(f"Sent compliance notification for resource: {resource_id}")
        
    except Exception as e:
        logger.error(f"Failed to send SNS notification: {str(e)}")