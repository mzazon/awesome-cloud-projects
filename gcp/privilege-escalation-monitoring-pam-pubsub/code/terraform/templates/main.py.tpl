import json
import base64
import logging
import os
from datetime import datetime
from google.cloud import storage
from google.cloud import monitoring_v3

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_privilege_alert(event, context):
    """Process privilege escalation events from Pub/Sub"""
    try:
        # Decode Pub/Sub message
        pubsub_message = base64.b64decode(event['data']).decode('utf-8')
        log_entry = json.loads(pubsub_message)
        
        # Extract audit log details
        proto_payload = log_entry.get('protoPayload', {})
        method_name = proto_payload.get('methodName', '')
        service_name = proto_payload.get('serviceName', '')
        principal_email = proto_payload.get('authenticationInfo', {}).get('principalEmail', 'Unknown')
        resource_name = proto_payload.get('resourceName', '')
        
        # Determine alert severity based on method and service
        severity = determine_severity(method_name, service_name, proto_payload)
        
        # Create alert object
        alert = {
            'timestamp': datetime.utcnow().isoformat(),
            'severity': severity,
            'principal': principal_email,
            'method': method_name,
            'service': service_name,
            'resource': resource_name,
            'raw_log': log_entry
        }
        
        # Log alert for monitoring
        logger.info(f"Privilege escalation detected: {severity} - {principal_email} - {method_name}")
        
        # Store alert in Cloud Storage
        store_alert(alert)
        
        # Send to Cloud Monitoring if high severity
        if severity in ['HIGH', 'CRITICAL']:
            send_monitoring_alert(alert)
            
        return 'Alert processed successfully'
        
    except Exception as e:
        logger.error(f"Error processing alert: {str(e)}")
        raise

def determine_severity(method_name, service_name, proto_payload):
    """Determine alert severity based on the method, service, and context"""
    # Critical PAM operations
    critical_pam_methods = [
        'createGrant', 'CreateGrant', 'createEntitlement', 'CreateEntitlement'
    ]
    
    # High-risk IAM methods
    high_risk_methods = [
        'CreateRole', 'UpdateRole', 'DeleteRole',
        'CreateServiceAccount', 'SetIamPolicy'
    ]
    
    # Check for PAM-related activities
    if service_name == 'privilegedaccessmanager.googleapis.com':
        if any(method in method_name for method in critical_pam_methods):
            return 'CRITICAL'
        else:
            return 'HIGH'
    
    # Check for high-risk IAM operations
    if any(method in method_name for method in high_risk_methods):
        return 'HIGH'
    elif 'setIamPolicy' in method_name:
        return 'MEDIUM'
    else:
        return 'LOW'

def store_alert(alert):
    """Store alert in Cloud Storage for audit trail"""
    try:
        client = storage.Client()
        bucket_name = "${bucket_name}"
        bucket = client.bucket(bucket_name)
        
        # Create filename with timestamp
        filename = f"alerts/{alert['timestamp'][:10]}/{alert['timestamp']}.json"
        blob = bucket.blob(filename)
        blob.upload_from_string(json.dumps(alert, indent=2))
        
    except Exception as e:
        logger.error(f"Failed to store alert: {str(e)}")

def send_monitoring_alert(alert):
    """Send high-severity alerts to Cloud Monitoring"""
    try:
        client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/${project_id}"
        
        # Create custom metric for privilege escalation
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/security/privilege_escalation"
        series.resource.type = "global"
        
        point = series.points.add()
        point.value.int64_value = 1
        point.interval.end_time.seconds = int(datetime.utcnow().timestamp())
        
        client.create_time_series(name=project_name, time_series=[series])
        
    except Exception as e:
        logger.error(f"Failed to send monitoring alert: {str(e)}")