import json
import logging
import os
from datetime import datetime, timedelta
from google.cloud import logging as cloud_logging
from google.cloud import monitoring_v3
from google.cloud import firestore
from google.cloud import storage
import functions_framework
import base64

# Initialize clients
logging_client = cloud_logging.Client()
monitoring_client = monitoring_v3.MetricServiceClient()
firestore_client = firestore.Client()
storage_client = storage.Client()

PROJECT_ID = "${project_id}"
DEBUG_BUCKET = "${debug_bucket}"

@functions_framework.cloud_event
def automate_debugging(cloud_event):
    """Automate debugging process for errors"""
    try:
        # Decode the message
        message_data = base64.b64decode(cloud_event.data['message']['data'])
        error_data = json.loads(message_data.decode('utf-8'))
        
        error_info = error_data['error_info']
        
        # Collect debugging context
        debug_context = collect_debug_context(error_info)
        
        # Analyze error patterns
        pattern_analysis = analyze_error_patterns_detailed(error_info)
        
        # Generate debugging report
        debug_report = generate_debug_report(error_info, debug_context, pattern_analysis)
        
        # Store debug report
        store_debug_report(debug_report)
        
        # Generate recommendations
        recommendations = generate_recommendations(error_info, pattern_analysis)
        
        # Update error record with debug info
        update_error_with_debug_info(error_info, debug_report, recommendations)
        
        logging.info(f"Debug automation completed for {error_info['service']}")
        
    except Exception as e:
        logging.error(f"Error in debug automation: {str(e)}")
        raise

def collect_debug_context(error_info):
    """Collect relevant debugging context"""
    service = error_info['service']
    timestamp = datetime.fromisoformat(error_info['timestamp'])
    
    # Collect logs around the error time
    logs = collect_related_logs(service, timestamp)
    
    # Collect metrics
    metrics = collect_service_metrics(service, timestamp)
    
    # Collect system information
    system_info = collect_system_info(service, timestamp)
    
    return {
        'logs': logs,
        'metrics': metrics,
        'system_info': system_info,
        'collected_at': datetime.now().isoformat()
    }

def collect_related_logs(service, timestamp):
    """Collect logs related to the error"""
    try:
        # Query logs around the error time
        start_time = timestamp - timedelta(minutes=5)
        end_time = timestamp + timedelta(minutes=5)
        
        filter_str = f"""
        resource.type="gae_app"
        resource.labels.module_id="{service}"
        timestamp>="{start_time.isoformat()}Z"
        timestamp<="{end_time.isoformat()}Z"
        """
        
        entries = logging_client.list_entries(
            filter_=filter_str,
            order_by=cloud_logging.ASCENDING,
            max_results=100
        )
        
        logs = []
        for entry in entries:
            logs.append({
                'timestamp': entry.timestamp.isoformat(),
                'severity': entry.severity,
                'message': str(entry.payload)[:500],
                'labels': dict(entry.labels) if entry.labels else {}
            })
        
        return logs[:50]  # Limit to 50 entries
        
    except Exception as e:
        logging.error(f"Error collecting logs: {str(e)}")
        return []

def collect_service_metrics(service, timestamp):
    """Collect service metrics around error time"""
    try:
        project_name = f"projects/{PROJECT_ID}"
        
        # Define time interval
        interval = monitoring_v3.TimeInterval()
        interval.end_time.seconds = int(timestamp.timestamp())
        interval.start_time.seconds = int((timestamp - timedelta(minutes=10)).timestamp())
        
        # Request metrics
        filter_str = f'resource.type="gae_app" AND resource.label.module_id="{service}"'
        
        request = monitoring_v3.ListTimeSeriesRequest()
        request.name = project_name
        request.filter = filter_str
        request.interval = interval
        request.view = monitoring_v3.ListTimeSeriesRequest.TimeSeriesView.FULL
        
        results = monitoring_client.list_time_series(request=request)
        
        metrics_data = []
        for result in results:
            metrics_data.append({
                'metric_type': result.metric.type,
                'points': len(result.points),
                'latest_value': result.points[0].value if result.points else None
            })
        
        return metrics_data[:20]  # Limit to 20 metrics
        
    except Exception as e:
        logging.error(f"Error collecting metrics: {str(e)}")
        return []

def collect_system_info(service, timestamp):
    """Collect system information"""
    return {
        'service': service,
        'timestamp': timestamp.isoformat(),
        'environment': 'production',  # This could be dynamic
        'region': os.environ.get('FUNCTION_REGION', 'us-central1')
    }

def analyze_error_patterns_detailed(error_info):
    """Perform detailed error pattern analysis"""
    service = error_info['service']
    
    # Query similar errors from the past week
    week_ago = datetime.now() - timedelta(days=7)
    
    similar_errors = firestore_client.collection('errors')\
        .where('service', '==', service)\
        .where('timestamp', '>', week_ago.isoformat())\
        .limit(100)\
        .stream()
    
    error_patterns = []
    message_patterns = {}
    
    for error in similar_errors:
        error_data = error.to_dict()
        message = error_data.get('message', '')
        
        # Count message patterns
        if message in message_patterns:
            message_patterns[message] += 1
        else:
            message_patterns[message] = 1
    
    # Identify frequent patterns
    for message, count in message_patterns.items():
        if count > 3:  # Appears more than 3 times
            error_patterns.append({
                'pattern': message[:200],
                'frequency': count,
                'type': 'recurring_message'
            })
    
    return {
        'patterns': error_patterns,
        'total_similar_errors': len(list(similar_errors)),
        'analyzed_at': datetime.now().isoformat()
    }

def generate_debug_report(error_info, debug_context, pattern_analysis):
    """Generate comprehensive debug report"""
    report = {
        'error_info': error_info,
        'debug_context': debug_context,
        'pattern_analysis': pattern_analysis,
        'generated_at': datetime.now().isoformat(),
        'report_id': f"debug_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    }
    
    return report

def store_debug_report(debug_report):
    """Store debug report in Cloud Storage"""
    try:
        bucket = storage_client.bucket(DEBUG_BUCKET)
        blob_name = f"debug_reports/{debug_report['report_id']}.json"
        blob = bucket.blob(blob_name)
        
        blob.upload_from_string(
            json.dumps(debug_report, indent=2),
            content_type='application/json'
        )
        
        logging.info(f"Debug report stored: {blob_name}")
        
    except Exception as e:
        logging.error(f"Error storing debug report: {str(e)}")

def generate_recommendations(error_info, pattern_analysis):
    """Generate debugging recommendations"""
    recommendations = []
    
    # Check for common patterns
    if pattern_analysis['patterns']:
        recommendations.append({
            'type': 'pattern_detected',
            'message': f"Found {len(pattern_analysis['patterns'])} recurring error patterns",
            'action': 'Review error patterns and implement fixes for recurring issues'
        })
    
    # Severity-based recommendations
    if error_info['severity'] == 'CRITICAL':
        recommendations.append({
            'type': 'critical_error',
            'message': 'Critical error requires immediate attention',
            'action': 'Escalate to on-call engineer and investigate immediately'
        })
    
    # Service-specific recommendations
    if error_info['service'] == 'payment-service':
        recommendations.append({
            'type': 'service_specific',
            'message': 'Payment service error detected',
            'action': 'Check payment gateway status and database connections'
        })
    
    return recommendations

def update_error_with_debug_info(error_info, debug_report, recommendations):
    """Update error record with debug information"""
    # Find the error record
    errors_ref = firestore_client.collection('errors')
    query = errors_ref.where('service', '==', error_info['service'])\
                     .where('timestamp', '==', error_info['timestamp'])\
                     .limit(1)
    
    docs = query.stream()
    for doc in docs:
        doc.reference.update({
            'debug_report_id': debug_report['report_id'],
            'recommendations': recommendations,
            'debug_processed': True,
            'debug_processed_at': datetime.now()
        })
        break