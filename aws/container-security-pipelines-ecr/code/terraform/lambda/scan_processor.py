import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function to process security scan results from Amazon Inspector
    and integrate with AWS Security Hub and SNS notifications.
    """
    print("Processing security scan results...")
    
    # Parse ECR scan results from EventBridge
    detail = event.get('detail', {})
    repository_name = detail.get('repository-name', '')
    image_digest = detail.get('image-digest', '')
    finding_counts = detail.get('finding-severity-counts', {})
    
    # Create consolidated security report
    security_report = {
        'timestamp': datetime.utcnow().isoformat(),
        'repository': repository_name,
        'image_digest': image_digest,
        'scan_results': {
            'ecr_enhanced': finding_counts,
            'total_vulnerabilities': finding_counts.get('TOTAL', 0),
            'critical_vulnerabilities': finding_counts.get('CRITICAL', 0),
            'high_vulnerabilities': finding_counts.get('HIGH', 0),
            'medium_vulnerabilities': finding_counts.get('MEDIUM', 0),
            'low_vulnerabilities': finding_counts.get('LOW', 0)
        }
    }
    
    # Determine risk level and actions based on vulnerability counts
    critical_count = finding_counts.get('CRITICAL', 0)
    high_count = finding_counts.get('HIGH', 0)
    medium_count = finding_counts.get('MEDIUM', 0)
    
    # Risk assessment logic
    if critical_count > 0:
        risk_level = 'CRITICAL'
        action_required = 'IMMEDIATE_BLOCK'
        compliance_status = 'FAIL'
    elif high_count > 5:
        risk_level = 'HIGH'
        action_required = 'REVIEW_REQUIRED'
        compliance_status = 'FAIL'
    elif high_count > 0 or medium_count > 10:
        risk_level = 'MEDIUM'
        action_required = 'MONITOR'
        compliance_status = 'PASS'
    else:
        risk_level = 'LOW'
        action_required = 'MONITOR'
        compliance_status = 'PASS'
    
    security_report['risk_assessment'] = {
        'risk_level': risk_level,
        'action_required': action_required,
        'compliance_status': compliance_status,
        'recommendation': get_recommendation(critical_count, high_count, medium_count)
    }
    
    # Send findings to Security Hub
    try:
        send_to_security_hub(security_report, repository_name, image_digest, risk_level)
        print("✅ Successfully sent findings to Security Hub")
    except Exception as e:
        print(f"❌ Error sending to Security Hub: {e}")
    
    # Trigger notifications based on risk level
    if risk_level in ['CRITICAL', 'HIGH']:
        try:
            send_notification(security_report, risk_level)
            print(f"✅ Notification sent for {risk_level} risk level")
        except Exception as e:
            print(f"❌ Error sending notification: {e}")
    
    # Log security report for audit purposes
    print(f"Security Report: {json.dumps(security_report, indent=2)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps(security_report),
        'headers': {
            'Content-Type': 'application/json'
        }
    }

def get_recommendation(critical_count, high_count, medium_count):
    """
    Provide actionable recommendations based on vulnerability counts.
    """
    recommendations = []
    
    if critical_count > 0:
        recommendations.append("IMMEDIATE ACTION: Block deployment until critical vulnerabilities are resolved")
        recommendations.append("Review and update base images to latest patched versions")
    
    if high_count > 5:
        recommendations.append("HIGH PRIORITY: Review and remediate high-severity vulnerabilities")
        recommendations.append("Consider implementing automated patching for known vulnerabilities")
    
    if medium_count > 10:
        recommendations.append("MEDIUM PRIORITY: Schedule remediation for medium-severity vulnerabilities")
        recommendations.append("Implement dependency scanning in CI/CD pipeline")
    
    if not recommendations:
        recommendations.append("Continue monitoring for new vulnerabilities")
        recommendations.append("Maintain current security posture")
    
    return recommendations

def send_to_security_hub(security_report, repository_name, image_digest, risk_level):
    """
    Send security findings to AWS Security Hub.
    """
    securityhub = boto3.client('securityhub')
    
    # Map risk level to Security Hub severity
    severity_mapping = {
        'CRITICAL': 'CRITICAL',
        'HIGH': 'HIGH',
        'MEDIUM': 'MEDIUM',
        'LOW': 'LOW'
    }
    
    # Create Security Hub finding
    finding = {
        'SchemaVersion': '2018-10-08',
        'Id': f"{repository_name}-{image_digest}-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}",
        'ProductArn': f"arn:aws:securityhub:{os.environ['AWS_REGION']}:{os.environ['AWS_ACCOUNT_ID']}:product/custom/container-security-scanner",
        'GeneratorId': 'container-security-pipeline',
        'AwsAccountId': os.environ['AWS_ACCOUNT_ID'],
        'Types': ['Vulnerabilities/CVE'],
        'Title': f"Container Security Scan Results - {repository_name}",
        'Description': f"Enhanced security scan completed for container image {repository_name}. Found {security_report['scan_results']['critical_vulnerabilities']} critical, {security_report['scan_results']['high_vulnerabilities']} high, and {security_report['scan_results']['medium_vulnerabilities']} medium vulnerabilities.",
        'Severity': {
            'Label': severity_mapping.get(risk_level, 'INFORMATIONAL'),
            'Normalized': get_normalized_severity(risk_level)
        },
        'Resources': [{
            'Type': 'AwsEcrContainerImage',
            'Id': f"arn:aws:ecr:{os.environ['AWS_REGION']}:{os.environ['AWS_ACCOUNT_ID']}:repository/{repository_name}",
            'Region': os.environ['AWS_REGION'],
            'Details': {
                'AwsEcrContainerImage': {
                    'Name': repository_name,
                    'ImageId': image_digest
                }
            }
        }],
        'Compliance': {
            'Status': security_report['risk_assessment']['compliance_status']
        },
        'RecordState': 'ACTIVE',
        'WorkflowState': 'NEW' if risk_level in ['CRITICAL', 'HIGH'] else 'NOTIFIED',
        'CreatedAt': security_report['timestamp'],
        'UpdatedAt': security_report['timestamp']
    }
    
    # Add vulnerability details to finding
    if security_report['scan_results']['total_vulnerabilities'] > 0:
        finding['Note'] = {
            'Text': f"Vulnerability breakdown: {json.dumps(security_report['scan_results']['ecr_enhanced'], indent=2)}",
            'UpdatedBy': 'container-security-scanner'
        }
    
    # Send finding to Security Hub
    response = securityhub.batch_import_findings(Findings=[finding])
    print(f"Security Hub response: {response}")
    
    return response

def get_normalized_severity(risk_level):
    """
    Convert risk level to normalized severity score (0-100).
    """
    severity_scores = {
        'CRITICAL': 90,
        'HIGH': 70,
        'MEDIUM': 50,
        'LOW': 30
    }
    return severity_scores.get(risk_level, 0)

def send_notification(security_report, risk_level):
    """
    Send notification to SNS topic for high-priority security findings.
    """
    sns = boto3.client('sns')
    
    # Create notification message
    message = {
        'alert_type': 'CONTAINER_SECURITY_ALERT',
        'severity': risk_level,
        'timestamp': security_report['timestamp'],
        'repository': security_report['repository'],
        'image_digest': security_report['image_digest'],
        'vulnerability_summary': security_report['scan_results'],
        'risk_assessment': security_report['risk_assessment'],
        'aws_account': os.environ['AWS_ACCOUNT_ID'],
        'aws_region': os.environ['AWS_REGION']
    }
    
    # Create human-readable subject
    subject = f"🚨 Container Security Alert - {risk_level} Risk Detected in {security_report['repository']}"
    
    # Create formatted message body
    message_body = f"""
CONTAINER SECURITY ALERT
========================

Severity: {risk_level}
Repository: {security_report['repository']}
Image Digest: {security_report['image_digest'][:12]}...
Scan Time: {security_report['timestamp']}

VULNERABILITY SUMMARY:
- Critical: {security_report['scan_results']['critical_vulnerabilities']}
- High: {security_report['scan_results']['high_vulnerabilities']}
- Medium: {security_report['scan_results']['medium_vulnerabilities']}
- Low: {security_report['scan_results']['low_vulnerabilities']}
- Total: {security_report['scan_results']['total_vulnerabilities']}

RISK ASSESSMENT:
- Risk Level: {security_report['risk_assessment']['risk_level']}
- Action Required: {security_report['risk_assessment']['action_required']}
- Compliance Status: {security_report['risk_assessment']['compliance_status']}

RECOMMENDATIONS:
{chr(10).join(f"• {rec}" for rec in security_report['risk_assessment']['recommendation'])}

AWS Account: {os.environ['AWS_ACCOUNT_ID']}
Region: {os.environ['AWS_REGION']}

---
This alert was generated by the Container Security Scanning Pipeline.
Check AWS Security Hub for detailed findings and remediation guidance.
"""
    
    # Send to SNS topic
    response = sns.publish(
        TopicArn=os.environ['SNS_TOPIC_ARN'],
        Message=message_body,
        Subject=subject,
        MessageAttributes={
            'severity': {
                'DataType': 'String',
                'StringValue': risk_level
            },
            'repository': {
                'DataType': 'String',
                'StringValue': security_report['repository']
            },
            'alert_type': {
                'DataType': 'String',
                'StringValue': 'CONTAINER_SECURITY'
            }
        }
    )
    
    print(f"SNS notification sent: {response['MessageId']}")
    return response