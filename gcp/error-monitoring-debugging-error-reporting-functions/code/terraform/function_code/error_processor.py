import json
import logging
import os
from datetime import datetime, timedelta
from google.cloud import error_reporting
from google.cloud import monitoring_v3
from google.cloud import firestore
from google.cloud import pubsub_v1
import base64
import functions_framework

# Initialize clients
error_client = error_reporting.Client()
monitoring_client = monitoring_v3.MetricServiceClient()
firestore_client = firestore.Client()
publisher = pubsub_v1.PublisherClient()

PROJECT_ID = "${project_id}"
ALERT_TOPIC = "${alert_topic}"
DEBUG_TOPIC = "${debug_topic}"

@functions_framework.cloud_event
def process_error(cloud_event):
    """Process error events from Cloud Error Reporting"""
    try:
        # Decode the Pub/Sub message
        message_data = base64.b64decode(cloud_event.data['message']['data'])
        error_data = json.loads(message_data.decode('utf-8'))
        
        # Extract error details
        error_info = {
            'timestamp': datetime.now().isoformat(),
            'service': error_data.get('serviceContext', {}).get('service', 'unknown'),
            'version': error_data.get('serviceContext', {}).get('version', 'unknown'),
            'message': error_data.get('message', ''),
            'location': error_data.get('sourceLocation', {}),
            'user': error_data.get('context', {}).get('user', 'anonymous'),
            'severity': classify_error_severity(error_data)
        }
        
        # Store error in Firestore for tracking
        store_error_record(error_info)
        
        # Check for error patterns
        pattern_detected = analyze_error_patterns(error_info)
        
        # Route based on severity and patterns
        if error_info['severity'] == 'CRITICAL' or pattern_detected:
            send_immediate_alert(error_info, pattern_detected)
            trigger_debug_automation(error_info)
        else:
            aggregate_for_batch_processing(error_info)
            
        logging.info(f"Processed error: {error_info['message'][:100]}")
        
    except Exception as e:
        logging.error(f"Error processing event: {str(e)}")
        raise

def classify_error_severity(error_data):
    """Classify error severity based on content and context"""
    message = error_data.get('message', '').lower()
    
    # Critical patterns
    critical_patterns = [
        'outofmemoryerror', 'database connection failed', 
        'payment processing error', 'authentication failed',
        'security violation', 'data corruption'
    ]
    
    # High severity patterns
    high_patterns = [
        'timeout', 'nullpointerexception', 'http 500',
        'service unavailable', 'connection refused'
    ]
    
    if any(pattern in message for pattern in critical_patterns):
        return 'CRITICAL'
    elif any(pattern in message for pattern in high_patterns):
        return 'HIGH'
    else:
        return 'MEDIUM'

def store_error_record(error_info):
    """Store error information in Firestore"""
    doc_ref = firestore_client.collection('errors').document()
    doc_ref.set({
        **error_info,
        'processed_at': datetime.now(),
        'acknowledged': False
    })

def analyze_error_patterns(error_info):
    """Analyze recent errors for patterns"""
    # Query recent errors from the same service
    recent_errors = firestore_client.collection('errors')\
        .where('service', '==', error_info['service'])\
        .where('timestamp', '>', (datetime.now() - timedelta(minutes=15)).isoformat())\
        .limit(10)\
        .stream()
    
    error_count = len(list(recent_errors))
    return error_count >= 5  # Pattern detected if 5+ errors in 15 minutes

def send_immediate_alert(error_info, pattern_detected):
    """Send immediate alert for critical errors"""
    alert_message = {
        'type': 'IMMEDIATE_ALERT',
        'error_info': error_info,
        'pattern_detected': pattern_detected,
        'timestamp': datetime.now().isoformat()
    }
    
    # Publish to alert topic
    future = publisher.publish(
        f"projects/{PROJECT_ID}/topics/{ALERT_TOPIC}",
        json.dumps(alert_message).encode('utf-8')
    )
    future.result()

def trigger_debug_automation(error_info):
    """Trigger debug automation for critical errors"""
    debug_message = {
        'type': 'DEBUG_REQUEST',
        'error_info': error_info,
        'timestamp': datetime.now().isoformat()
    }
    
    # Publish to debug topic
    future = publisher.publish(
        f"projects/{PROJECT_ID}/topics/{DEBUG_TOPIC}",
        json.dumps(debug_message).encode('utf-8')
    )
    future.result()

def aggregate_for_batch_processing(error_info):
    """Aggregate errors for batch processing"""
    # Update aggregation counters
    doc_ref = firestore_client.collection('error_aggregates')\
        .document(f"{error_info['service']}-{datetime.now().strftime('%Y%m%d%H')}")
    
    doc_ref.set({
        'service': error_info['service'],
        'hour': datetime.now().strftime('%Y%m%d%H'),
        'count': firestore.Increment(1),
        'last_updated': datetime.now()
    }, merge=True)