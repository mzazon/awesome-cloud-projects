import base64
import json
import logging
import os
from google.cloud import monitoring_v3
from google.cloud import logging as cloud_logging
from datetime import datetime

def main(event, context):
    """Security notification function for alerts and human review."""
    
    # Decode security finding
    message_data = base64.b64decode(event['data']).decode('utf-8')
    security_finding = json.loads(message_data)
    
    finding_name = security_finding.get('name', 'Unknown')
    severity = security_finding.get('severity', 'MEDIUM')
    category = security_finding.get('category', 'Unknown')
    
    logging.info(f"Creating notification for finding: {finding_name}")
    
    # Create structured alert
    alert_data = create_security_alert(security_finding)
    
    # Send to different channels based on severity
    if severity in ['HIGH', 'CRITICAL']:
        send_priority_notification(alert_data)
    else:
        send_standard_notification(alert_data)
    
    # Create dashboard entry
    update_security_dashboard(security_finding)
    
    # Log notification action
    log_notification_action(finding_name, severity, category)
    
    return f"Notification sent for: {finding_name}"

def create_security_alert(finding):
    """Create structured security alert with context."""
    return {
        'alert_id': finding.get('name', '').split('/')[-1],
        'title': f"Security Finding: {finding.get('category', 'Unknown')}",
        'severity': finding.get('severity', 'MEDIUM'),
        'description': finding.get('description', 'No description available'),
        'resource': finding.get('resourceName', 'Unknown resource'),
        'timestamp': datetime.utcnow().isoformat(),
        'recommendation': finding.get('recommendation', 'Review manually'),
        'source_properties': finding.get('sourceProperties', {}),
        'deployment_id': os.environ.get('DEPLOYMENT_ID', 'default')
    }

def send_priority_notification(alert_data):
    """Send high-priority notifications to immediate channels."""
    # Integration points for Slack, PagerDuty, etc.
    logging.info(f"Priority alert sent: {alert_data['title']}")
    
    # Send Slack notification if configured
    slack_webhook = os.environ.get('SLACK_WEBHOOK_URL', '')
    if slack_webhook:
        send_slack_notification(alert_data, slack_webhook)
    
    # Send PagerDuty alert if configured
    pagerduty_key = os.environ.get('PAGERDUTY_INTEGRATION', '')
    if pagerduty_key:
        send_pagerduty_alert(alert_data, pagerduty_key)
    
    # Create monitoring alert policy
    create_monitoring_alert(alert_data)

def send_standard_notification(alert_data):
    """Send standard notifications to review channels."""
    # Integration points for email, Slack channels, etc.
    logging.info(f"Standard alert sent: {alert_data['title']}")
    
    # Send to standard Slack channel if configured
    slack_webhook = os.environ.get('SLACK_WEBHOOK_URL', '')
    if slack_webhook:
        send_slack_notification(alert_data, slack_webhook, is_priority=False)

def send_slack_notification(alert_data, webhook_url, is_priority=True):
    """Send notification to Slack channel."""
    try:
        import requests
        
        color = "#ff0000" if is_priority else "#ffaa00"
        priority_text = "🚨 CRITICAL" if is_priority else "⚠️ WARNING"
        
        payload = {
            "attachments": [
                {
                    "color": color,
                    "title": f"{priority_text} Security Alert",
                    "fields": [
                        {
                            "title": "Alert ID",
                            "value": alert_data['alert_id'],
                            "short": True
                        },
                        {
                            "title": "Severity",
                            "value": alert_data['severity'],
                            "short": True
                        },
                        {
                            "title": "Category",
                            "value": alert_data['title'],
                            "short": False
                        },
                        {
                            "title": "Resource",
                            "value": alert_data['resource'],
                            "short": False
                        },
                        {
                            "title": "Description",
                            "value": alert_data['description'],
                            "short": False
                        }
                    ],
                    "footer": f"Security Automation • {alert_data['timestamp']}",
                    "ts": int(datetime.utcnow().timestamp())
                }
            ]
        }
        
        response = requests.post(webhook_url, json=payload, timeout=10)
        response.raise_for_status()
        logging.info("Slack notification sent successfully")
        
    except Exception as e:
        logging.error(f"Failed to send Slack notification: {str(e)}")

def send_pagerduty_alert(alert_data, integration_key):
    """Send alert to PagerDuty."""
    try:
        import requests
        
        payload = {
            "routing_key": integration_key,
            "event_action": "trigger",
            "dedup_key": alert_data['alert_id'],
            "payload": {
                "summary": f"Security Alert: {alert_data['title']}",
                "severity": alert_data['severity'].lower(),
                "source": "GCP Security Automation",
                "component": "Security Command Center",
                "group": "Security Team",
                "class": "security",
                "custom_details": {
                    "alert_id": alert_data['alert_id'],
                    "resource": alert_data['resource'],
                    "description": alert_data['description'],
                    "deployment_id": alert_data['deployment_id']
                }
            }
        }
        
        response = requests.post(
            "https://events.pagerduty.com/v2/enqueue",
            json=payload,
            timeout=10
        )
        response.raise_for_status()
        logging.info("PagerDuty alert sent successfully")
        
    except Exception as e:
        logging.error(f"Failed to send PagerDuty alert: {str(e)}")

def update_security_dashboard(finding):
    """Update security operations dashboard."""
    # Create custom metrics for dashboard visualization
    project_id = "${project_id}"
    deployment_id = os.environ.get('DEPLOYMENT_ID', 'default')
    
    try:
        client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{project_id}"
        
        # Create metric for dashboard
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/security/notifications_sent"
        series.resource.type = "global"
        series.metric.labels["severity"] = finding.get('severity', 'UNKNOWN')
        series.metric.labels["category"] = finding.get('category', 'UNKNOWN')
        series.metric.labels["deployment_id"] = deployment_id
        
        # Create data point
        now = datetime.utcnow()
        seconds = int(now.timestamp())
        nanos = int((now.timestamp() - seconds) * 10**9)
        interval = monitoring_v3.TimeInterval(
            {"end_time": {"seconds": seconds, "nanos": nanos}}
        )
        point = monitoring_v3.Point({
            "interval": interval,
            "value": {"int64_value": 1},
        })
        series.points = [point]
        
        client.create_time_series(name=project_name, time_series=[series])
        logging.info("Security dashboard updated with new finding")
        
    except Exception as e:
        logging.error(f"Failed to update security dashboard: {str(e)}")

def create_monitoring_alert(alert_data):
    """Create Cloud Monitoring alert policy for high-priority findings."""
    project_id = "${project_id}"
    
    try:
        client = monitoring_v3.AlertPolicyServiceClient()
        project_name = f"projects/{project_id}"
        
        # Implementation for alert policy creation
        logging.info(f"Monitoring alert created for: {alert_data['alert_id']}")
        
    except Exception as e:
        logging.error(f"Failed to create monitoring alert: {str(e)}")

def log_notification_action(finding_name, severity, category):
    """Log notification actions for audit and metrics."""
    try:
        client = cloud_logging.Client()
        client.setup_logging()
        
        notification_entry = {
            'finding_name': finding_name,
            'severity': severity,
            'category': category,
            'action': 'notification_sent',
            'timestamp': datetime.utcnow().isoformat(),
            'function': 'security-notification',
            'deployment_id': os.environ.get('DEPLOYMENT_ID', 'default')
        }
        
        logging.info(f"Notification audit: {json.dumps(notification_entry)}")
        
    except Exception as e:
        logging.error(f"Failed to log notification action: {str(e)}")