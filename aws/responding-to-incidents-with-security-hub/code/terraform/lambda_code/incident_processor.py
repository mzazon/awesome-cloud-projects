#!/usr/bin/env python3
"""
AWS Security Hub Incident Processor Lambda Function

This function processes Security Hub findings and automates incident response workflows.
It analyzes security findings, determines appropriate response actions, and sends 
notifications through SNS for integration with external ticketing systems.

Features:
- Intelligent severity-based triage
- Automated incident classification
- SNS notification with structured payloads
- Security Hub finding workflow updates
- Comprehensive error handling and logging

Environment Variables:
- SNS_TOPIC_ARN: ARN of the SNS topic for notifications
- AWS_REGION: AWS region for API calls
"""

import json
import boto3
import os
import logging
from datetime import datetime
from typing import Dict, Any, List, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
sns = boto3.client('sns')
securityhub = boto3.client('securityhub')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing Security Hub findings.
    
    Args:
        event: EventBridge event containing Security Hub finding
        context: Lambda runtime context
        
    Returns:
        Dict containing processing results
    """
    try:
        logger.info(f"Processing Security Hub event: {json.dumps(event, default=str)}")
        
        # Extract finding from event
        finding = extract_finding_from_event(event)
        if not finding:
            logger.error("No valid finding found in event")
            return create_error_response("No valid finding found in event")
        
        # Extract key information from finding
        finding_info = extract_finding_information(finding)
        logger.info(f"Processing finding: {finding_info['finding_id']} with severity {finding_info['severity']}")
        
        # Determine response action based on severity and context
        response_action = determine_response_action(finding_info)
        
        # Create incident payload for notifications
        incident_payload = create_incident_payload(finding_info, response_action)
        
        # Send notification to SNS
        notification_result = send_incident_notification(incident_payload)
        
        # Update finding workflow status in Security Hub
        workflow_result = update_finding_workflow(finding_info, response_action)
        
        # Create success response
        response = create_success_response(finding_info, response_action, notification_result)
        logger.info(f"Successfully processed incident: {response}")
        
        return response
        
    except Exception as e:
        logger.error(f"Error processing Security Hub incident: {str(e)}", exc_info=True)
        return create_error_response(str(e))

def extract_finding_from_event(event: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Extract Security Hub finding from EventBridge event.
    
    Args:
        event: EventBridge event
        
    Returns:
        Security Hub finding dictionary or None
    """
    try:
        # Handle different event types
        if 'detail' in event and 'findings' in event['detail']:
            findings = event['detail']['findings']
            if isinstance(findings, list) and len(findings) > 0:
                return findings[0]
        
        # Handle custom action events
        if 'detail' in event and 'finding' in event['detail']:
            return event['detail']['finding']
            
        return None
        
    except (KeyError, IndexError, TypeError) as e:
        logger.error(f"Error extracting finding from event: {str(e)}")
        return None

def extract_finding_information(finding: Dict[str, Any]) -> Dict[str, Any]:
    """
    Extract and normalize key information from Security Hub finding.
    
    Args:
        finding: Security Hub finding dictionary
        
    Returns:
        Normalized finding information
    """
    return {
        'finding_id': finding.get('Id', 'Unknown'),
        'product_arn': finding.get('ProductArn', ''),
        'severity': finding.get('Severity', {}).get('Label', 'UNKNOWN'),
        'normalized_severity': finding.get('Severity', {}).get('Normalized', 0),
        'title': finding.get('Title', 'Unknown Security Finding'),
        'description': finding.get('Description', 'No description available'),
        'account_id': finding.get('AwsAccountId', 'Unknown'),
        'region': finding.get('Region', 'Unknown'),
        'generator_id': finding.get('GeneratorId', 'Unknown'),
        'types': finding.get('Types', []),
        'resources': finding.get('Resources', []),
        'created_at': finding.get('CreatedAt', ''),
        'updated_at': finding.get('UpdatedAt', ''),
        'workflow_status': finding.get('Workflow', {}).get('Status', 'NEW'),
        'record_state': finding.get('RecordState', 'ACTIVE'),
        'compliance_status': finding.get('Compliance', {}).get('Status', 'NOT_AVAILABLE')
    }

def determine_response_action(finding_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Determine appropriate response action based on finding characteristics.
    
    Args:
        finding_info: Normalized finding information
        
    Returns:
        Response action configuration
    """
    severity = finding_info['severity']
    normalized_severity = finding_info['normalized_severity']
    finding_types = finding_info['types']
    
    # Determine base response level
    if severity == 'CRITICAL':
        response_level = 'immediate_response'
        priority = 'P1'
        sla_minutes = 15
        escalation_required = True
    elif severity == 'HIGH':
        response_level = 'escalated_response'
        priority = 'P2'
        sla_minutes = 60
        escalation_required = True
    elif severity == 'MEDIUM':
        response_level = 'standard_response'
        priority = 'P3'
        sla_minutes = 240
        escalation_required = False
    elif severity == 'LOW':
        response_level = 'low_priority_response'
        priority = 'P4'
        sla_minutes = 1440  # 24 hours
        escalation_required = False
    else:
        response_level = 'informational'
        priority = 'P5'
        sla_minutes = 2880  # 48 hours
        escalation_required = False
    
    # Adjust based on finding types
    high_priority_types = [
        'Data Exfiltration',
        'Backdoor',
        'Cryptocurrency Mining',
        'Malware',
        'Trojan'
    ]
    
    if any(high_risk_type in str(finding_types) for high_risk_type in high_priority_types):
        if priority in ['P3', 'P4', 'P5']:
            priority = 'P2'
            response_level = 'escalated_response'
            escalation_required = True
    
    return {
        'action': response_level,
        'priority': priority,
        'sla_minutes': sla_minutes,
        'escalation_required': escalation_required,
        'automated_actions': get_automated_actions(severity, finding_types),
        'notification_channels': get_notification_channels(priority),
        'response_team': get_response_team(priority)
    }

def get_automated_actions(severity: str, finding_types: List[str]) -> List[str]:
    """
    Determine automated actions based on severity and finding types.
    
    Args:
        severity: Finding severity level
        finding_types: List of finding types
        
    Returns:
        List of automated actions to perform
    """
    actions = []
    
    if severity in ['CRITICAL', 'HIGH']:
        actions.extend([
            'create_incident_ticket',
            'notify_soc_team',
            'capture_forensic_snapshot'
        ])
    
    if severity == 'CRITICAL':
        actions.extend([
            'notify_executive_team',
            'activate_incident_response_team',
            'initiate_containment_procedures'
        ])
    
    # Add type-specific actions
    if any('Malware' in str(ftype) for ftype in finding_types):
        actions.append('isolate_affected_resources')
    
    if any('Data Exfiltration' in str(ftype) for ftype in finding_types):
        actions.append('block_suspicious_network_traffic')
    
    return actions

def get_notification_channels(priority: str) -> List[str]:
    """
    Get notification channels based on priority level.
    
    Args:
        priority: Incident priority (P1-P5)
        
    Returns:
        List of notification channels
    """
    channels = ['sns', 'sqs']  # Always use SNS and SQS
    
    if priority in ['P1', 'P2']:
        channels.extend(['slack_urgent', 'pagerduty'])
    elif priority == 'P3':
        channels.append('slack_standard')
    
    return channels

def get_response_team(priority: str) -> str:
    """
    Determine the appropriate response team based on priority.
    
    Args:
        priority: Incident priority (P1-P5)
        
    Returns:
        Response team identifier
    """
    team_mapping = {
        'P1': 'incident_response_team',
        'P2': 'security_operations_center',
        'P3': 'security_analysts',
        'P4': 'security_analysts',
        'P5': 'security_monitoring'
    }
    
    return team_mapping.get(priority, 'security_monitoring')

def create_incident_payload(finding_info: Dict[str, Any], response_action: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create structured incident payload for notifications.
    
    Args:
        finding_info: Normalized finding information
        response_action: Response action configuration
        
    Returns:
        Structured incident payload
    """
    return {
        'incident_metadata': {
            'incident_id': f"SEC-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}-{finding_info['finding_id'][-8:]}",
            'source': 'AWS Security Hub',
            'timestamp': datetime.utcnow().isoformat(),
            'version': '1.0'
        },
        'finding_details': {
            'id': finding_info['finding_id'],
            'title': finding_info['title'],
            'description': finding_info['description'],
            'severity': finding_info['severity'],
            'normalized_severity': finding_info['normalized_severity'],
            'types': finding_info['types'],
            'account_id': finding_info['account_id'],
            'region': finding_info['region'],
            'generator_id': finding_info['generator_id'],
            'workflow_status': finding_info['workflow_status'],
            'compliance_status': finding_info['compliance_status']
        },
        'affected_resources': [
            {
                'id': resource.get('Id', ''),
                'type': resource.get('Type', ''),
                'region': resource.get('Region', ''),
                'partition': resource.get('Partition', 'aws'),
                'details': resource.get('Details', {})
            }
            for resource in finding_info['resources']
        ],
        'response_plan': {
            'action': response_action['action'],
            'priority': response_action['priority'],
            'sla_minutes': response_action['sla_minutes'],
            'escalation_required': response_action['escalation_required'],
            'automated_actions': response_action['automated_actions'],
            'notification_channels': response_action['notification_channels'],
            'response_team': response_action['response_team']
        },
        'integration_context': {
            'jira_project': 'SEC',
            'slack_channel': '#security-incidents',
            'pagerduty_service': 'security-team',
            'servicenow_category': 'Security Incident',
            'tags': {
                'severity': finding_info['severity'],
                'account': finding_info['account_id'],
                'region': finding_info['region'],
                'source': 'security-hub'
            }
        },
        'remediation_guidance': generate_remediation_guidance(finding_info, response_action)
    }

def generate_remediation_guidance(finding_info: Dict[str, Any], response_action: Dict[str, Any]) -> Dict[str, Any]:
    """
    Generate remediation guidance based on finding characteristics.
    
    Args:
        finding_info: Normalized finding information
        response_action: Response action configuration
        
    Returns:
        Remediation guidance
    """
    guidance = {
        'immediate_steps': [],
        'investigation_steps': [],
        'containment_steps': [],
        'recovery_steps': []
    }
    
    severity = finding_info['severity']
    finding_types = finding_info['types']
    
    # Add severity-based guidance
    if severity in ['CRITICAL', 'HIGH']:
        guidance['immediate_steps'].extend([
            'Activate incident response procedures',
            'Notify security team and management',
            'Begin evidence collection and preservation'
        ])
    
    # Add type-specific guidance
    if any('Malware' in str(ftype) for ftype in finding_types):
        guidance['containment_steps'].extend([
            'Isolate affected systems from network',
            'Preserve system state for forensic analysis',
            'Run malware scans on related systems'
        ])
    
    if any('Configuration' in str(ftype) for ftype in finding_types):
        guidance['recovery_steps'].extend([
            'Review and correct security configuration',
            'Implement additional monitoring controls',
            'Update security policies and procedures'
        ])
    
    return guidance

def send_incident_notification(incident_payload: Dict[str, Any]) -> Dict[str, Any]:
    """
    Send incident notification through SNS.
    
    Args:
        incident_payload: Structured incident information
        
    Returns:
        Notification result
    """
    try:
        # Create formatted message for human readability
        message = {
            'default': json.dumps(incident_payload, indent=2),
            'email': format_email_message(incident_payload),
            'sqs': json.dumps(incident_payload)
        }
        
        # Create subject line
        finding_details = incident_payload['finding_details']
        subject = f"Security Incident [{incident_payload['response_plan']['priority']}]: {finding_details['severity']} - {finding_details['title'][:50]}..."
        
        # Message attributes for filtering
        message_attributes = {
            'severity': {
                'DataType': 'String',
                'StringValue': finding_details['severity']
            },
            'priority': {
                'DataType': 'String',
                'StringValue': incident_payload['response_plan']['priority']
            },
            'account_id': {
                'DataType': 'String',
                'StringValue': finding_details['account_id']
            },
            'incident_id': {
                'DataType': 'String',
                'StringValue': incident_payload['incident_metadata']['incident_id']
            }
        }
        
        # Publish to SNS
        response = sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=json.dumps(message),
            Subject=subject,
            MessageStructure='json',
            MessageAttributes=message_attributes
        )
        
        logger.info(f"SNS notification sent successfully: {response['MessageId']}")
        
        return {
            'success': True,
            'message_id': response['MessageId'],
            'topic_arn': os.environ['SNS_TOPIC_ARN']
        }
        
    except Exception as e:
        logger.error(f"Error sending SNS notification: {str(e)}")
        return {
            'success': False,
            'error': str(e)
        }

def format_email_message(incident_payload: Dict[str, Any]) -> str:
    """
    Format incident payload for email notifications.
    
    Args:
        incident_payload: Structured incident information
        
    Returns:
        Formatted email message
    """
    finding = incident_payload['finding_details']
    response = incident_payload['response_plan']
    
    message = f"""
SECURITY INCIDENT ALERT
========================

Incident ID: {incident_payload['incident_metadata']['incident_id']}
Priority: {response['priority']}
Severity: {finding['severity']}
SLA: {response['sla_minutes']} minutes

FINDING DETAILS
---------------
Title: {finding['title']}
Description: {finding['description']}
Account: {finding['account_id']}
Region: {finding['region']}
Generator: {finding['generator_id']}

RESPONSE PLAN
-------------
Action: {response['action']}
Team: {response['response_team']}
Escalation Required: {response['escalation_required']}

AUTOMATED ACTIONS
-----------------
{chr(10).join(f"- {action}" for action in response['automated_actions'])}

AFFECTED RESOURCES
------------------
{chr(10).join(f"- {resource['type']}: {resource['id']}" for resource in incident_payload['affected_resources'])}

NEXT STEPS
----------
1. Review the finding in AWS Security Hub console
2. Follow your organization's incident response procedures
3. Escalate to {response['response_team']} if required
4. Update the incident status in your ticketing system

AWS Security Hub Console: https://console.aws.amazon.com/securityhub/
Finding ID: {finding['id']}

This is an automated message from AWS Security Hub Incident Response System.
"""
    return message.strip()

def update_finding_workflow(finding_info: Dict[str, Any], response_action: Dict[str, Any]) -> Dict[str, Any]:
    """
    Update Security Hub finding workflow status.
    
    Args:
        finding_info: Normalized finding information
        response_action: Response action configuration
        
    Returns:
        Update result
    """
    try:
        # Create note text based on response action
        note_text = f"Automated incident response initiated: {response_action['action']}. " \
                   f"Priority: {response_action['priority']}, " \
                   f"SLA: {response_action['sla_minutes']} minutes. " \
                   f"Incident ID: SEC-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}-{finding_info['finding_id'][-8:]}"
        
        # Update finding
        response = securityhub.batch_update_findings(
            FindingIdentifiers=[{
                'Id': finding_info['finding_id'],
                'ProductArn': finding_info['product_arn']
            }],
            Note={
                'Text': note_text,
                'UpdatedBy': 'SecurityHubAutomation'
            },
            Workflow={
                'Status': 'NOTIFIED'
            },
            UserDefinedFields={
                'IncidentPriority': response_action['priority'],
                'ResponseAction': response_action['action'],
                'AutomationTimestamp': datetime.utcnow().isoformat()
            }
        )
        
        logger.info(f"Finding workflow updated successfully: {finding_info['finding_id']}")
        
        return {
            'success': True,
            'finding_id': finding_info['finding_id'],
            'workflow_status': 'NOTIFIED'
        }
        
    except Exception as e:
        logger.error(f"Error updating finding workflow: {str(e)}")
        return {
            'success': False,
            'error': str(e)
        }

def create_success_response(finding_info: Dict[str, Any], response_action: Dict[str, Any], notification_result: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create success response for Lambda function.
    
    Args:
        finding_info: Normalized finding information
        response_action: Response action configuration
        notification_result: SNS notification result
        
    Returns:
        Success response dictionary
    """
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Security incident processed successfully',
            'incident_details': {
                'finding_id': finding_info['finding_id'],
                'severity': finding_info['severity'],
                'priority': response_action['priority'],
                'response_action': response_action['action'],
                'sla_minutes': response_action['sla_minutes']
            },
            'notification': {
                'success': notification_result['success'],
                'message_id': notification_result.get('message_id')
            },
            'timestamp': datetime.utcnow().isoformat()
        })
    }

def create_error_response(error_message: str) -> Dict[str, Any]:
    """
    Create error response for Lambda function.
    
    Args:
        error_message: Error description
        
    Returns:
        Error response dictionary
    """
    return {
        'statusCode': 500,
        'body': json.dumps({
            'error': error_message,
            'timestamp': datetime.utcnow().isoformat()
        })
    }