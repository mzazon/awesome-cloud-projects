"""
Security Notification Lambda Function

This function sends comprehensive notifications for security incidents through
multiple channels including SNS, email, and optionally Slack. It creates
rich, contextual alerts with actionable information for security teams.

Environment Variables:
- SNS_TOPIC_ARN: ARN of the SNS topic for notifications
- ENVIRONMENT: Deployment environment (dev, staging, prod)
- PROJECT: Project name for tagging and identification
- SLACK_WEBHOOK: Optional Slack webhook URL for notifications
- ENABLE_SLACK: Enable/disable Slack notifications
"""

import json
import boto3
import logging
import os
import urllib3
from datetime import datetime
from typing import Dict, Any, List, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
sns = boto3.client('sns')

# Environment configuration
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '${sns_topic_arn}')
ENVIRONMENT = os.environ.get('ENVIRONMENT', '${environment}')
PROJECT = os.environ.get('PROJECT', '${project}')
AWS_REGION = os.environ.get('AWS_DEFAULT_REGION', '${aws_region}')
AWS_ACCOUNT_ID = os.environ.get('AWS_ACCOUNT_ID', '${aws_account_id}')
SLACK_WEBHOOK = os.environ.get('SLACK_WEBHOOK', '')
ENABLE_SLACK = os.environ.get('ENABLE_SLACK', 'false').lower() == 'true'

# Initialize HTTP client for Slack notifications
http = urllib3.PoolManager()

# Severity emoji mapping for visual indicators
SEVERITY_EMOJIS = {
    'CRITICAL': '🔴',
    'HIGH': '🟠', 
    'MEDIUM': '🟡',
    'LOW': '🟢',
    'INFORMATIONAL': '🔵'
}

# Risk level colors for Slack
SEVERITY_COLORS = {
    'CRITICAL': '#FF0000',
    'HIGH': '#FF8C00',
    'MEDIUM': '#FFD700',
    'LOW': '#32CD32',
    'INFORMATIONAL': '#1E90FF'
}


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for security incident notifications.
    
    Args:
        event: EventBridge event containing Security Hub finding
        context: Lambda context object
        
    Returns:
        Dict containing notification results and status
    """
    try:
        logger.info(f"Processing notification event in {ENVIRONMENT} environment")
        
        # Extract finding details from EventBridge event
        finding = event['detail']['findings'][0]
        
        finding_id = finding['Id']
        severity = finding['Severity']['Label']
        title = finding['Title']
        description = finding['Description']
        account_id = finding['AwsAccountId']
        region = finding['Resources'][0]['Region'] if finding['Resources'] else AWS_REGION
        
        logger.info(f"Creating notification for finding: {finding_id}, Severity: {severity}")
        
        # Determine notification urgency and channels
        notification_config = get_notification_config(severity)
        
        # Create comprehensive notification message
        email_message = create_email_notification(finding, severity, title, description, account_id, region)
        slack_message = create_slack_notification(finding, severity, title, description, account_id, region)
        
        # Send SNS notification (email)
        sns_response = send_sns_notification(email_message, severity, title)
        
        # Send Slack notification if enabled
        slack_response = None
        if ENABLE_SLACK and SLACK_WEBHOOK and notification_config['send_to_slack']:
            slack_response = send_slack_notification(slack_message)
        
        # Compile response
        response_data = {
            'findingId': finding_id,
            'severity': severity,
            'notifications_sent': {
                'sns': sns_response is not None,
                'slack': slack_response is not None
            },
            'environment': ENVIRONMENT,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        if sns_response:
            response_data['sns_message_id'] = sns_response['MessageId']
        
        logger.info(f"Notifications sent successfully for finding {finding_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(response_data)
        }
        
    except Exception as e:
        logger.error(f"Error sending notifications: {str(e)}")
        logger.error(f"Event details: {json.dumps(event, default=str)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'environment': ENVIRONMENT,
                'timestamp': datetime.utcnow().isoformat()
            })
        }


def get_notification_config(severity: str) -> Dict[str, Any]:
    """
    Get notification configuration based on finding severity.
    
    Args:
        severity: Finding severity level
        
    Returns:
        Dict containing notification configuration
    """
    config = {
        'CRITICAL': {
            'send_to_slack': True,
            'urgency': 'IMMEDIATE',
            'escalate': True,
            'response_time': '15 minutes'
        },
        'HIGH': {
            'send_to_slack': True,
            'urgency': 'HIGH',
            'escalate': False,
            'response_time': '1 hour'
        },
        'MEDIUM': {
            'send_to_slack': False,
            'urgency': 'MEDIUM',
            'escalate': False,
            'response_time': '4 hours'
        },
        'LOW': {
            'send_to_slack': False,
            'urgency': 'LOW',
            'escalate': False,
            'response_time': '24 hours'
        },
        'INFORMATIONAL': {
            'send_to_slack': False,
            'urgency': 'INFO',
            'escalate': False,
            'response_time': '7 days'
        }
    }
    
    return config.get(severity, config['MEDIUM'])


def create_email_notification(finding: Dict[str, Any], severity: str, title: str, 
                            description: str, account_id: str, region: str) -> str:
    """
    Create comprehensive email notification message.
    
    Args:
        finding: Security Hub finding object
        severity: Finding severity
        title: Finding title
        description: Finding description
        account_id: AWS account ID
        region: AWS region
        
    Returns:
        Formatted email message
    """
    # Get notification configuration
    config = get_notification_config(severity)
    
    # Determine escalation level
    escalation_level = f"{SEVERITY_EMOJIS.get(severity, '⚪')} {severity}"
    if config['escalate']:
        escalation_level += " - ESCALATION REQUIRED"
    
    # Extract resource information
    resources = format_resources_for_email(finding.get('Resources', []))
    
    # Get compliance information
    compliance_info = get_compliance_info(finding)
    
    # Create finding metadata
    metadata = extract_finding_metadata(finding)
    
    # Create comprehensive message
    message = f"""
{escalation_level} SECURITY INCIDENT ALERT

======================================
INCIDENT SUMMARY
======================================

Finding ID: {finding['Id']}
Severity: {severity}
Title: {title}
Environment: {ENVIRONMENT}
Project: {PROJECT}

AWS Account: {account_id}
Region: {region}
Detected: {finding.get('FirstObservedAt', 'Unknown')}
Last Updated: {finding.get('UpdatedAt', 'Unknown')}
Timestamp: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC

======================================
INCIDENT DETAILS
======================================

Description:
{description}

Finding Types:
{chr(10).join(['- ' + ftype for ftype in finding.get('Types', ['Unknown'])])}

Workflow State: {finding.get('WorkflowState', 'NEW')}
Record State: {finding.get('RecordState', 'ACTIVE')}

======================================
AFFECTED RESOURCES
======================================

{resources}

======================================
COMPLIANCE STATUS
======================================

{compliance_info}

======================================
RESPONSE REQUIREMENTS
======================================

Urgency Level: {config['urgency']}
Expected Response Time: {config['response_time']}
Escalation Required: {'Yes' if config['escalate'] else 'No'}

Immediate Actions Required:
1. Acknowledge this incident in Security Hub
2. Review the affected resources and assess impact
3. Implement temporary containment measures if needed
4. Begin investigation and evidence collection
{'5. Escalate to senior security team immediately' if config['escalate'] else '5. Follow standard incident response procedures'}

======================================
USEFUL LINKS
======================================

Security Hub Finding:
https://console.aws.amazon.com/securityhub/home?region={region}#/findings?search=Id%3D{finding['Id'].replace(':', '%3A').replace('/', '%2F')}

Security Hub Dashboard:
https://console.aws.amazon.com/securityhub/home?region={region}#/summary

CloudTrail Events:
https://console.aws.amazon.com/cloudtrail/home?region={region}#/events

======================================
INVESTIGATION GUIDANCE
======================================

{get_investigation_guidance(title, severity)}

======================================
METADATA
======================================

Generator: {finding.get('GeneratorId', 'Unknown')}
Product: {finding.get('ProductName', 'AWS Security Hub')}
Company: {finding.get('CompanyName', 'Amazon')}
{metadata}

======================================
AUTOMATED RESPONSE STATUS
======================================

{get_automation_status(finding)}

This is an automated alert from the {PROJECT} Security Incident Response System.
For questions or issues with this alert, contact the security team.

Environment: {ENVIRONMENT}
Generated: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC
"""

    return message


def create_slack_notification(finding: Dict[str, Any], severity: str, title: str,
                            description: str, account_id: str, region: str) -> Dict[str, Any]:
    """
    Create Slack notification message with rich formatting.
    
    Args:
        finding: Security Hub finding object
        severity: Finding severity
        title: Finding title
        description: Finding description
        account_id: AWS account ID
        region: AWS region
        
    Returns:
        Slack message payload
    """
    config = get_notification_config(severity)
    color = SEVERITY_COLORS.get(severity, '#808080')
    emoji = SEVERITY_EMOJIS.get(severity, '⚪')
    
    # Create resource list for Slack
    resources_text = format_resources_for_slack(finding.get('Resources', []))
    
    # Create Slack message
    slack_message = {
        "username": "AWS Security Hub",
        "icon_emoji": ":shield:",
        "attachments": [
            {
                "color": color,
                "title": f"{emoji} {severity} Security Alert",
                "title_link": f"https://console.aws.amazon.com/securityhub/home?region={region}#/findings?search=Id%3D{finding['Id'].replace(':', '%3A').replace('/', '%2F')}",
                "text": f"*{title}*",
                "fields": [
                    {
                        "title": "Account",
                        "value": account_id,
                        "short": True
                    },
                    {
                        "title": "Region",
                        "value": region,
                        "short": True
                    },
                    {
                        "title": "Environment",
                        "value": ENVIRONMENT,
                        "short": True
                    },
                    {
                        "title": "Urgency",
                        "value": config['urgency'],
                        "short": True
                    },
                    {
                        "title": "Response Time",
                        "value": config['response_time'],
                        "short": True
                    },
                    {
                        "title": "Escalation",
                        "value": "Required" if config['escalate'] else "Standard",
                        "short": True
                    },
                    {
                        "title": "Affected Resources",
                        "value": resources_text,
                        "short": False
                    },
                    {
                        "title": "Description",
                        "value": description[:500] + ("..." if len(description) > 500 else ""),
                        "short": False
                    }
                ],
                "footer": f"{PROJECT} Security Response",
                "footer_icon": "https://aws.amazon.com/favicon.ico",
                "ts": int(datetime.utcnow().timestamp())
            }
        ]
    }
    
    # Add escalation warning for critical findings
    if config['escalate']:
        slack_message["attachments"].append({
            "color": "#FF0000",
            "title": "🚨 IMMEDIATE ESCALATION REQUIRED",
            "text": "This critical security finding requires immediate attention from the senior security team.",
            "fields": [
                {
                    "title": "Next Steps",
                    "value": "• Acknowledge in Security Hub\n• Contact security lead immediately\n• Begin incident response procedures\n• Document all actions taken",
                    "short": False
                }
            ]
        })
    
    return slack_message


def format_resources_for_email(resources: List[Dict]) -> str:
    """Format resource list for email notifications."""
    if not resources:
        return "No specific resources identified"
    
    formatted_resources = []
    for resource in resources:
        resource_type = resource.get('Type', 'Unknown')
        resource_id = resource.get('Id', 'Unknown')
        region = resource.get('Region', 'Unknown')
        
        formatted_resources.append(f"- {resource_type}")
        formatted_resources.append(f"  ID: {resource_id}")
        formatted_resources.append(f"  Region: {region}")
        formatted_resources.append("")
    
    return "\n".join(formatted_resources)


def format_resources_for_slack(resources: List[Dict]) -> str:
    """Format resource list for Slack notifications."""
    if not resources:
        return "No specific resources identified"
    
    resource_list = []
    for resource in resources[:5]:  # Limit to 5 resources for Slack
        resource_type = resource.get('Type', 'Unknown')
        resource_id = resource.get('Id', 'Unknown').split('/')[-1]  # Get last part of ARN
        resource_list.append(f"• {resource_type}: `{resource_id}`")
    
    if len(resources) > 5:
        resource_list.append(f"• ... and {len(resources) - 5} more resources")
    
    return "\n".join(resource_list)


def get_compliance_info(finding: Dict[str, Any]) -> str:
    """Extract compliance information from finding."""
    compliance = finding.get('Compliance', {})
    
    if not compliance:
        return "No compliance information available"
    
    status = compliance.get('Status', 'UNKNOWN')
    related_requirements = compliance.get('RelatedRequirements', [])
    status_reasons = compliance.get('StatusReasons', [])
    
    info_lines = [f"Status: {status}"]
    
    if related_requirements:
        info_lines.append("Related Requirements:")
        for req in related_requirements[:3]:  # Limit to first 3
            info_lines.append(f"- {req}")
    
    if status_reasons:
        info_lines.append("Status Reasons:")
        for reason in status_reasons[:3]:  # Limit to first 3
            reason_text = reason.get('ReasonCode', 'Unknown')
            info_lines.append(f"- {reason_text}")
    
    return "\n".join(info_lines)


def extract_finding_metadata(finding: Dict[str, Any]) -> str:
    """Extract additional metadata from finding."""
    metadata_lines = []
    
    # Network information
    network = finding.get('Network', {})
    if network:
        if network.get('Direction'):
            metadata_lines.append(f"Network Direction: {network['Direction']}")
        if network.get('Protocol'):
            metadata_lines.append(f"Network Protocol: {network['Protocol']}")
    
    # Process information
    process = finding.get('Process', {})
    if process:
        if process.get('Name'):
            metadata_lines.append(f"Process: {process['Name']}")
    
    # Malware information
    malware = finding.get('Malware', [])
    if malware:
        metadata_lines.append(f"Malware Detected: {len(malware)} instances")
    
    # Threat intel indicators
    threat_intel = finding.get('ThreatIntelIndicators', [])
    if threat_intel:
        metadata_lines.append(f"Threat Intel Indicators: {len(threat_intel)}")
    
    return "\n".join(metadata_lines) if metadata_lines else "No additional metadata available"


def get_investigation_guidance(title: str, severity: str) -> str:
    """Provide investigation guidance based on finding type."""
    title_lower = title.lower()
    
    if 'security group' in title_lower:
        return """1. Review security group rules and identify the source of open access
2. Check CloudTrail logs for recent security group modifications
3. Verify if the open access is required for business operations
4. Implement least privilege access principles
5. Consider using AWS Systems Manager Session Manager instead of direct SSH/RDP"""
    
    elif 's3' in title_lower and 'public' in title_lower:
        return """1. Review S3 bucket policy and Access Control Lists (ACLs)
2. Check CloudTrail logs for bucket policy changes
3. Verify if public access is required for business operations
4. Implement S3 bucket public access block if appropriate
5. Consider using CloudFront for public content distribution"""
    
    elif 'iam' in title_lower:
        return """1. Review IAM policies and identify overly permissive permissions
2. Check CloudTrail logs for recent IAM policy changes
3. Apply principle of least privilege
4. Consider using IAM Access Analyzer for policy analysis
5. Implement regular IAM access reviews"""
    
    elif severity == 'CRITICAL':
        return """1. Immediately assess the scope and impact of the finding
2. Consider implementing temporary containment measures
3. Preserve evidence for forensic analysis
4. Escalate to incident response team if necessary
5. Follow your organization's critical incident response procedures"""
    
    else:
        return """1. Review the finding details and affected resources
2. Check CloudTrail logs for related activities
3. Assess business impact and security risk
4. Plan and implement appropriate remediation
5. Document lessons learned and update security policies"""


def get_automation_status(finding: Dict[str, Any]) -> str:
    """Get status of automated response actions."""
    user_fields = finding.get('UserDefinedFields', {})
    
    status_lines = []
    
    # Classification status
    classification = user_fields.get('AutoClassification')
    if classification:
        status_lines.append(f"Classification: {classification}")
    
    # Remediation status
    remediation_status = user_fields.get('RemediationStatus')
    if remediation_status:
        status_lines.append(f"Remediation Status: {remediation_status}")
        
        remediation_action = user_fields.get('RemediationAction')
        if remediation_action:
            status_lines.append(f"Remediation Action: {remediation_action}")
    
    # Processing timestamp
    processed_at = user_fields.get('ProcessedAt')
    if processed_at:
        status_lines.append(f"Last Processed: {processed_at}")
    
    return "\n".join(status_lines) if status_lines else "No automated actions performed yet"


def send_sns_notification(message: str, severity: str, title: str) -> Optional[Dict[str, Any]]:
    """
    Send notification via SNS.
    
    Args:
        message: Email message content
        severity: Finding severity
        title: Finding title
        
    Returns:
        SNS response or None if failed
    """
    try:
        subject = f"Security Alert: {severity} - {title[:50]}{'...' if len(title) > 50 else ''}"
        
        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=message,
            Subject=subject,
            MessageAttributes={
                'severity': {
                    'DataType': 'String',
                    'StringValue': severity
                },
                'environment': {
                    'DataType': 'String',
                    'StringValue': ENVIRONMENT
                },
                'project': {
                    'DataType': 'String',
                    'StringValue': PROJECT
                }
            }
        )
        
        logger.info(f"SNS notification sent: {response['MessageId']}")
        return response
        
    except Exception as e:
        logger.error(f"Failed to send SNS notification: {str(e)}")
        return None


def send_slack_notification(slack_message: Dict[str, Any]) -> Optional[bool]:
    """
    Send notification to Slack via webhook.
    
    Args:
        slack_message: Slack message payload
        
    Returns:
        True if successful, None if failed
    """
    if not SLACK_WEBHOOK:
        logger.info("Slack webhook not configured, skipping Slack notification")
        return None
    
    try:
        response = http.request(
            'POST',
            SLACK_WEBHOOK,
            body=json.dumps(slack_message).encode('utf-8'),
            headers={'Content-Type': 'application/json'}
        )
        
        if response.status == 200:
            logger.info("Slack notification sent successfully")
            return True
        else:
            logger.error(f"Slack notification failed with status {response.status}: {response.data}")
            return None
            
    except Exception as e:
        logger.error(f"Failed to send Slack notification: {str(e)}")
        return None