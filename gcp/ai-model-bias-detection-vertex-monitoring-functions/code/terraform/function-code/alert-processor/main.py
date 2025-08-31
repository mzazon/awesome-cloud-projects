import json
import logging
import time
from google.cloud import logging as cloud_logging
from google.cloud import pubsub_v1
import functions_framework
import os

# Initialize logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

@functions_framework.http
def process_bias_alerts(request):
    """Process and route bias alerts based on severity."""
    try:
        request_json = request.get_json()
        logger.info(f"Processing alert: {request_json}")
        
        bias_score = request_json.get('bias_score', 0.0)
        violations = request_json.get('fairness_violations', [])
        model_name = request_json.get('model_name', 'unknown')
        
        # Determine alert severity
        severity = determine_severity(bias_score, violations)
        
        # Create structured alert
        alert = {
            'severity': severity,
            'model_name': model_name,
            'bias_score': bias_score,
            'violations': violations,
            'timestamp': request_json.get('timestamp'),
            'alert_id': f"bias-{model_name}-{int(time.time())}"
        }
        
        # Route alert based on severity
        route_alert(alert)
        
        # Log for compliance
        log_compliance_event(alert)
        
        return {"status": "success", "severity": severity, "alert_id": alert['alert_id']}
        
    except Exception as e:
        logger.error(f"Error processing alert: {str(e)}")
        return {"status": "error", "message": str(e)}, 500

def determine_severity(bias_score, violations):
    """Determine alert severity based on bias metrics."""
    if bias_score > 0.15 or len(violations) > 2:
        return "CRITICAL"
    elif bias_score > 0.1 or len(violations) > 0:
        return "HIGH"
    elif bias_score > 0.05:
        return "MEDIUM"
    else:
        return "LOW"

def route_alert(alert):
    """Route alerts to appropriate channels based on severity."""
    if alert['severity'] in ['CRITICAL', 'HIGH']:
        send_immediate_notification(alert)
    
    # Always log to structured logging for audit trails
    logger.warning(f"BIAS_ALERT: {json.dumps(alert)}")

def send_immediate_notification(alert):
    """Send immediate notifications for critical bias issues."""
    # In production, integrate with email, Slack, or PagerDuty
    logger.critical(f"IMMEDIATE_ACTION_REQUIRED: {alert['model_name']} has {alert['severity']} bias violations")

def log_compliance_event(alert):
    """Log compliance event for regulatory reporting."""
    compliance_log = {
        'event_type': 'BIAS_DETECTION',
        'severity': alert['severity'],
        'model_name': alert['model_name'],
        'bias_score': alert['bias_score'],
        'violations_count': len(alert['violations']),
        'timestamp': alert['timestamp'],
        'alert_id': alert['alert_id']
    }
    
    logger.info(f"COMPLIANCE_EVENT: {json.dumps(compliance_log)}")