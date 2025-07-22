import json
import logging
import os
from datetime import datetime
from google.cloud import monitoring_v3
from google.cloud import firestore
import functions_framework
import requests
import base64

# Initialize clients
monitoring_client = monitoring_v3.MetricServiceClient()
firestore_client = firestore.Client()

PROJECT_ID = "${project_id}"
SLACK_WEBHOOK = "${slack_webhook_url}"

@functions_framework.cloud_event
def route_alerts(cloud_event):
    """Route alerts to appropriate channels"""
    try:
        # Decode alert message
        message_data = base64.b64decode(cloud_event.data['message']['data'])
        alert_data = json.loads(message_data.decode('utf-8'))
        
        error_info = alert_data['error_info']
        pattern_detected = alert_data.get('pattern_detected', False)
        
        # Create monitoring alert policy
        create_monitoring_alert(error_info)
        
        # Send notifications based on severity
        if error_info['severity'] == 'CRITICAL':
            send_critical_notifications(error_info, pattern_detected)
        elif error_info['severity'] == 'HIGH':
            send_high_priority_notifications(error_info)
        
        # Log routing decision
        log_alert_routing(error_info, pattern_detected)
        
    except Exception as e:
        logging.error(f"Error routing alert: {str(e)}")
        raise

def create_monitoring_alert(error_info):
    """Create Cloud Monitoring alert policy"""
    alert_policy = {
        "display_name": f"Error Alert - {error_info['service']}",
        "conditions": [{
            "display_name": "Error rate condition",
            "condition_threshold": {
                "filter": f'resource.type="gae_app" AND resource.label.module_id="{error_info["service"]}"',
                "comparison": "COMPARISON_GREATER_THAN",
                "threshold_value": 5,
                "duration": "300s"
            }
        }],
        "enabled": True,
        "alert_strategy": {
            "auto_close": "1800s"
        }
    }
    
    # Create the alert policy
    project_name = f"projects/{PROJECT_ID}"
    try:
        policy = monitoring_client.create_alert_policy(
            name=project_name,
            alert_policy=alert_policy
        )
        logging.info(f"Created alert policy: {policy.name}")
    except Exception as e:
        logging.warning(f"Failed to create alert policy: {str(e)}")

def send_critical_notifications(error_info, pattern_detected):
    """Send critical error notifications"""
    # Prepare notification message
    message = format_critical_message(error_info, pattern_detected)
    
    # Send to Slack if webhook configured
    if SLACK_WEBHOOK and SLACK_WEBHOOK != "":
        send_slack_notification(message, '#critical-alerts')
    
    # Send email notification (placeholder)
    send_email_notification(message, 'critical')
    
    # Create incident record
    create_incident_record(error_info)

def send_high_priority_notifications(error_info):
    """Send high priority error notifications"""
    message = format_high_priority_message(error_info)
    
    if SLACK_WEBHOOK and SLACK_WEBHOOK != "":
        send_slack_notification(message, '#error-alerts')
    
    send_email_notification(message, 'high')

def format_critical_message(error_info, pattern_detected):
    """Format critical error message"""
    pattern_text = " 🔄 PATTERN DETECTED" if pattern_detected else ""
    
    return {
        "text": f"🚨 CRITICAL ERROR{pattern_text}",
        "attachments": [{
            "color": "danger",
            "fields": [
                {"title": "Service", "value": error_info['service'], "short": True},
                {"title": "Severity", "value": error_info['severity'], "short": True},
                {"title": "Message", "value": error_info['message'][:500], "short": False},
                {"title": "User", "value": error_info['user'], "short": True},
                {"title": "Timestamp", "value": error_info['timestamp'], "short": True}
            ]
        }]
    }

def format_high_priority_message(error_info):
    """Format high priority error message"""
    return {
        "text": f"⚠️ High Priority Error in {error_info['service']}",
        "attachments": [{
            "color": "warning",
            "fields": [
                {"title": "Message", "value": error_info['message'][:300], "short": False},
                {"title": "Timestamp", "value": error_info['timestamp'], "short": True}
            ]
        }]
    }

def send_slack_notification(message, channel):
    """Send notification to Slack"""
    if not SLACK_WEBHOOK or SLACK_WEBHOOK == "":
        logging.info("Slack webhook not configured, skipping Slack notification")
        return
        
    payload = {
        **message,
        "channel": channel,
        "username": "Error Monitor Bot",
        "icon_emoji": ":warning:"
    }
    
    try:
        response = requests.post(SLACK_WEBHOOK, json=payload)
        response.raise_for_status()
        logging.info(f"Slack notification sent to {channel}")
    except Exception as e:
        logging.error(f"Failed to send Slack notification: {str(e)}")

def send_email_notification(message, priority):
    """Send email notification (placeholder)"""
    # In production, integrate with SendGrid, SES, or Gmail API
    logging.info(f"Email notification would be sent for {priority} priority")

def create_incident_record(error_info):
    """Create incident record in Firestore"""
    incident_ref = firestore_client.collection('incidents').document()
    incident_ref.set({
        'error_info': error_info,
        'status': 'OPEN',
        'created_at': datetime.now(),
        'assigned_to': None,
        'escalation_level': 1
    })

def log_alert_routing(error_info, pattern_detected):
    """Log alert routing decision"""
    routing_log = {
        'service': error_info['service'],
        'severity': error_info['severity'],
        'pattern_detected': pattern_detected,
        'routed_at': datetime.now(),
        'channels': ['slack', 'email', 'monitoring']
    }
    
    firestore_client.collection('alert_routing_log').add(routing_log)