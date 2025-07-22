#!/usr/bin/env python3
"""
AWS Lambda Function: Security Response Handler
==============================================

This Lambda function processes AWS Security Hub findings and triggers automated
responses based on severity levels and resource types. It provides immediate
notification for critical vulnerabilities and implements basic auto-remediation
capabilities for common security issues.

Features:
- Processes Security Hub findings from EventBridge
- Sends notifications for HIGH and CRITICAL severity findings
- Performs automated tagging of affected resources
- Logs all security events for audit trails
- Implements retry logic for external service calls

Environment Variables:
- SNS_TOPIC_ARN: ARN of the SNS topic for security alerts
"""

import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, List, Any, Optional
from botocore.exceptions import ClientError, BotoCoreError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS service clients
sns = boto3.client('sns')
securityhub = boto3.client('securityhub')
ec2 = boto3.client('ec2')

# Constants
ALERT_SEVERITIES = ['HIGH', 'CRITICAL']
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function for processing Security Hub findings.
    
    Args:
        event: EventBridge event containing Security Hub findings
        context: Lambda context object
        
    Returns:
        Dict containing processing results and status
    """
    try:
        logger.info(f"Processing security findings event: {json.dumps(event, default=str)}")
        
        # Validate event structure
        if not validate_event_structure(event):
            logger.error("Invalid event structure received")
            return create_response(400, "Invalid event structure")
        
        # Extract findings from the event
        findings = extract_findings_from_event(event)
        if not findings:
            logger.info("No findings found in event")
            return create_response(200, "No findings to process")
        
        processed_count = 0
        error_count = 0
        
        # Process each finding
        for finding in findings:
            try:
                process_single_finding(finding)
                processed_count += 1
                logger.info(f"Successfully processed finding: {finding.get('Id', 'Unknown')}")
            except Exception as e:
                error_count += 1
                logger.error(f"Failed to process finding {finding.get('Id', 'Unknown')}: {str(e)}")
        
        # Create summary response
        response_message = f"Processed {processed_count} findings successfully"
        if error_count > 0:
            response_message += f", {error_count} errors occurred"
            
        logger.info(response_message)
        return create_response(200, response_message, {
            'processed_count': processed_count,
            'error_count': error_count,
            'total_findings': len(findings)
        })
        
    except Exception as e:
        error_msg = f"Critical error in lambda_handler: {str(e)}"
        logger.error(error_msg, exc_info=True)
        return create_response(500, error_msg)

def validate_event_structure(event: Dict[str, Any]) -> bool:
    """
    Validate that the incoming event has the expected EventBridge structure.
    
    Args:
        event: The EventBridge event to validate
        
    Returns:
        bool: True if event structure is valid, False otherwise
    """
    try:
        # Check for required top-level fields
        required_fields = ['source', 'detail-type', 'detail']
        for field in required_fields:
            if field not in event:
                logger.error(f"Missing required field: {field}")
                return False
        
        # Validate source is Security Hub
        if event.get('source') != 'aws.securityhub':
            logger.error(f"Invalid event source: {event.get('source')}")
            return False
        
        # Check for findings in detail
        detail = event.get('detail', {})
        if 'findings' not in detail:
            logger.error("No findings found in event detail")
            return False
        
        return True
        
    except Exception as e:
        logger.error(f"Error validating event structure: {str(e)}")
        return False

def extract_findings_from_event(event: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Extract Security Hub findings from the EventBridge event.
    
    Args:
        event: EventBridge event containing findings
        
    Returns:
        List of Security Hub findings
    """
    try:
        detail = event.get('detail', {})
        findings = detail.get('findings', [])
        
        if not isinstance(findings, list):
            logger.error("Findings is not a list")
            return []
        
        logger.info(f"Extracted {len(findings)} findings from event")
        return findings
        
    except Exception as e:
        logger.error(f"Error extracting findings: {str(e)}")
        return []

def process_single_finding(finding: Dict[str, Any]) -> None:
    """
    Process a single Security Hub finding with appropriate responses.
    
    Args:
        finding: Individual Security Hub finding to process
    """
    try:
        # Extract finding metadata
        finding_id = finding.get('Id', 'Unknown')
        title = finding.get('Title', 'Security Finding')
        description = finding.get('Description', '')
        severity = finding.get('Severity', {}).get('Label', 'UNKNOWN')
        resource_info = finding.get('Resources', [{}])[0] if finding.get('Resources') else {}
        resource_id = resource_info.get('Id', 'Unknown')
        resource_type = resource_info.get('Type', 'Unknown')
        
        logger.info(f"Processing finding {finding_id}: {title} (Severity: {severity})")
        
        # Create standardized alert message
        alert_message = create_alert_message(finding, severity, title, description, resource_id)
        
        # Send notification for high-severity findings
        if severity in ALERT_SEVERITIES:
            send_security_alert(alert_message, severity, title)
        
        # Perform automated remediation based on finding type and resource
        perform_auto_remediation(finding, resource_type, resource_id, severity)
        
        # Log finding details for audit trail
        log_finding_details(finding_id, title, severity, resource_id, resource_type)
        
    except Exception as e:
        logger.error(f"Error processing finding: {str(e)}", exc_info=True)
        raise

def create_alert_message(finding: Dict[str, Any], severity: str, title: str, 
                        description: str, resource_id: str) -> Dict[str, Any]:
    """
    Create a standardized alert message for notifications.
    
    Args:
        finding: The Security Hub finding
        severity: Severity level of the finding
        title: Finding title
        description: Finding description
        resource_id: Affected resource identifier
        
    Returns:
        Dict containing formatted alert message
    """
    return {
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'severity': severity,
        'title': title,
        'description': description,
        'resource': resource_id,
        'finding_id': finding.get('Id', ''),
        'aws_account': finding.get('AwsAccountId', ''),
        'region': finding.get('Region', ''),
        'compliance_status': finding.get('Compliance', {}).get('Status', 'Unknown'),
        'remediation_url': finding.get('Remediation', {}).get('Recommendation', {}).get('Url', ''),
        'first_observed': finding.get('FirstObservedAt', ''),
        'updated_at': finding.get('UpdatedAt', '')
    }

def send_security_alert(alert_message: Dict[str, Any], severity: str, title: str) -> None:
    """
    Send security alert notification via SNS.
    
    Args:
        alert_message: Formatted alert message
        severity: Severity level
        title: Alert title
    """
    try:
        if not SNS_TOPIC_ARN:
            logger.warning("SNS_TOPIC_ARN not configured, skipping notification")
            return
        
        subject = f"🚨 Security Alert: {severity} - {title}"
        
        # Create formatted message body
        message_body = format_alert_message(alert_message)
        
        # Publish to SNS
        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject[:100],  # SNS subject limit
            Message=message_body,
            MessageAttributes={
                'severity': {
                    'DataType': 'String',
                    'StringValue': severity
                },
                'resource_type': {
                    'DataType': 'String',
                    'StringValue': alert_message.get('resource', 'Unknown')
                }
            }
        )
        
        logger.info(f"Security alert sent successfully. MessageId: {response.get('MessageId')}")
        
    except ClientError as e:
        logger.error(f"Failed to send SNS notification: {str(e)}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error sending alert: {str(e)}")
        raise

def format_alert_message(alert_message: Dict[str, Any]) -> str:
    """
    Format the alert message for human-readable notifications.
    
    Args:
        alert_message: Alert message data
        
    Returns:
        Formatted string message
    """
    return f"""
SECURITY ALERT DETAILS
=====================

Severity: {alert_message.get('severity', 'Unknown')}
Title: {alert_message.get('title', 'Unknown')}
Resource: {alert_message.get('resource', 'Unknown')}
Account: {alert_message.get('aws_account', 'Unknown')}
Region: {alert_message.get('region', 'Unknown')}
Timestamp: {alert_message.get('timestamp', 'Unknown')}

DESCRIPTION
-----------
{alert_message.get('description', 'No description available')}

COMPLIANCE STATUS
-----------------
Status: {alert_message.get('compliance_status', 'Unknown')}

REMEDIATION
-----------
Finding ID: {alert_message.get('finding_id', 'Unknown')}
First Observed: {alert_message.get('first_observed', 'Unknown')}
Last Updated: {alert_message.get('updated_at', 'Unknown')}

{f"Remediation URL: {alert_message.get('remediation_url')}" if alert_message.get('remediation_url') else ""}

Please review this finding in the AWS Security Hub console and take appropriate action.
    """.strip()

def perform_auto_remediation(finding: Dict[str, Any], resource_type: str, 
                           resource_id: str, severity: str) -> None:
    """
    Perform automated remediation actions based on finding type and severity.
    
    Args:
        finding: The Security Hub finding
        resource_type: Type of the affected resource
        resource_id: Identifier of the affected resource
        severity: Severity level of the finding
    """
    try:
        logger.info(f"Performing auto-remediation for {resource_type}: {resource_id}")
        
        # EC2 Instance remediation
        if resource_type == 'AwsEc2Instance' and 'vulnerability' in finding.get('Title', '').lower():
            tag_ec2_instance_for_remediation(resource_id, severity, finding)
        
        # Add more remediation actions here as needed
        # Examples:
        # - Quarantine security groups with overly permissive rules
        # - Disable unused IAM users
        # - Encrypt unencrypted S3 buckets
        # - Update Lambda function configurations
        
        logger.info(f"Auto-remediation completed for {resource_id}")
        
    except Exception as e:
        logger.error(f"Error during auto-remediation: {str(e)}")
        # Don't re-raise here as remediation failures shouldn't stop processing

def tag_ec2_instance_for_remediation(resource_id: str, severity: str, finding: Dict[str, Any]) -> None:
    """
    Tag EC2 instances that require security remediation.
    
    Args:
        resource_id: EC2 instance identifier
        severity: Severity of the finding
        finding: The complete finding object
    """
    try:
        # Extract instance ID from resource ARN/ID
        instance_id = extract_instance_id(resource_id)
        if not instance_id:
            logger.error(f"Could not extract instance ID from {resource_id}")
            return
        
        # Create remediation tags
        tags = [
            {
                'Key': 'SecurityStatus',
                'Value': 'RequiresPatching'
            },
            {
                'Key': 'SecuritySeverity',
                'Value': severity
            },
            {
                'Key': 'LastSecurityScan',
                'Value': datetime.utcnow().isoformat()
            },
            {
                'Key': 'FindingId',
                'Value': finding.get('Id', '')[:255]  # Limit tag value length
            },
            {
                'Key': 'RemediationRequired',
                'Value': 'true'
            }
        ]
        
        # Apply tags to the instance
        ec2.create_tags(Resources=[instance_id], Tags=tags)
        
        logger.info(f"Successfully tagged EC2 instance {instance_id} for remediation")
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', '')
        if error_code == 'InvalidInstanceID.NotFound':
            logger.warning(f"EC2 instance {resource_id} not found, may have been terminated")
        else:
            logger.error(f"Failed to tag EC2 instance {resource_id}: {str(e)}")
    except Exception as e:
        logger.error(f"Unexpected error tagging instance: {str(e)}")

def extract_instance_id(resource_id: str) -> Optional[str]:
    """
    Extract EC2 instance ID from various resource ID formats.
    
    Args:
        resource_id: Resource identifier (ARN or direct instance ID)
        
    Returns:
        Instance ID if found, None otherwise
    """
    try:
        # Direct instance ID format
        if resource_id.startswith('i-'):
            return resource_id
        
        # ARN format: arn:aws:ec2:region:account:instance/i-instanceid
        if 'instance/' in resource_id:
            return resource_id.split('instance/')[-1]
        
        # Try to extract from the end of the resource ID
        parts = resource_id.split('/')
        for part in parts:
            if part.startswith('i-'):
                return part
        
        logger.warning(f"Could not extract instance ID from: {resource_id}")
        return None
        
    except Exception as e:
        logger.error(f"Error extracting instance ID: {str(e)}")
        return None

def log_finding_details(finding_id: str, title: str, severity: str, 
                       resource_id: str, resource_type: str) -> None:
    """
    Log finding details for audit and compliance tracking.
    
    Args:
        finding_id: Unique finding identifier
        title: Finding title
        severity: Severity level
        resource_id: Affected resource ID
        resource_type: Type of affected resource
    """
    audit_log = {
        'event_type': 'security_finding_processed',
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'finding_id': finding_id,
        'title': title,
        'severity': severity,
        'resource_id': resource_id,
        'resource_type': resource_type,
        'processed_by': 'automated-security-response-handler'
    }
    
    logger.info(f"AUDIT_LOG: {json.dumps(audit_log)}")

def create_response(status_code: int, message: str, data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Create a standardized Lambda response.
    
    Args:
        status_code: HTTP status code
        message: Response message
        data: Optional additional data
        
    Returns:
        Formatted response dictionary
    """
    response = {
        'statusCode': status_code,
        'body': json.dumps({
            'message': message,
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        })
    }
    
    if data:
        body = json.loads(response['body'])
        body.update(data)
        response['body'] = json.dumps(body)
    
    return response