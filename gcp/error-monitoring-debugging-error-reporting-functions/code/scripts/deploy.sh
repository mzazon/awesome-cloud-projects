#!/bin/bash

# Error Monitoring and Debugging with Cloud Error Reporting and Cloud Functions
# Deployment Script for GCP Recipe
# 
# This script deploys an intelligent error monitoring system that automatically
# detects, categorizes, and responds to application errors using Cloud Error
# Reporting integrated with Cloud Functions for automated debugging workflows.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy error monitoring and debugging system with Cloud Error Reporting and Cloud Functions.

OPTIONS:
    -p, --project-id PROJECT_ID     GCP Project ID (required)
    -r, --region REGION             GCP region (default: ${DEFAULT_REGION})
    -z, --zone ZONE                 GCP zone (default: ${DEFAULT_ZONE})
    -s, --suffix SUFFIX             Resource suffix for uniqueness (auto-generated if not provided)
    --slack-webhook URL             Slack webhook URL for notifications (optional)
    --dry-run                       Show what would be deployed without making changes
    -h, --help                      Display this help message

EXAMPLES:
    $0 --project-id my-project-123
    $0 --project-id my-project-123 --region us-east1 --suffix dev
    $0 --project-id my-project-123 --slack-webhook https://hooks.slack.com/...

EOF
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_info "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed or not in PATH"
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if openssl is installed for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed or not in PATH"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active gcloud authentication found"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate project and permissions
validate_project() {
    log_info "Validating project and permissions..."
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' not found or not accessible"
        exit 1
    fi
    
    # Set the project
    gcloud config set project "$PROJECT_ID" --quiet
    log_success "Project validated: $PROJECT_ID"
    
    # Check billing status
    if ! gcloud billing projects describe "$PROJECT_ID" &> /dev/null; then
        log_warning "Unable to verify billing status. Ensure billing is enabled for this project."
    fi
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "clouderrorreporting.googleapis.com"
        "cloudfunctions.googleapis.com" 
        "cloudmonitoring.googleapis.com"
        "logging.googleapis.com"
        "pubsub.googleapis.com"
        "storage.googleapis.com"
        "firestore.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log_success "Enabled $api"
        else
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    log_success "All APIs enabled successfully"
}

# Function to set environment variables
set_environment_variables() {
    log_info "Setting environment variables..."
    
    # Generate unique suffix if not provided
    if [[ -z "${RESOURCE_SUFFIX:-}" ]]; then
        RESOURCE_SUFFIX=$(openssl rand -hex 3)
        log_info "Generated resource suffix: $RESOURCE_SUFFIX"
    fi
    
    # Export variables
    export PROJECT_ID="$PROJECT_ID"
    export REGION="$REGION"
    export ZONE="$ZONE"
    export FUNCTION_NAME="error-processor-${RESOURCE_SUFFIX}"
    export PUBSUB_TOPIC="error-notifications-${RESOURCE_SUFFIX}"
    export STORAGE_BUCKET="${PROJECT_ID}-error-debug-data-${RESOURCE_SUFFIX}"
    
    # Set gcloud defaults
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
    
    log_success "Environment variables configured"
    log_info "Function Name: $FUNCTION_NAME"
    log_info "Pub/Sub Topic: $PUBSUB_TOPIC"
    log_info "Storage Bucket: $STORAGE_BUCKET"
}

# Function to create Pub/Sub topics
create_pubsub_topics() {
    log_info "Creating Pub/Sub topics..."
    
    local topics=(
        "$PUBSUB_TOPIC"
        "${PUBSUB_TOPIC}-alerts"
        "${PUBSUB_TOPIC}-debug"
    )
    
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe "$topic" &> /dev/null; then
            log_warning "Topic '$topic' already exists, skipping creation"
        else
            log_info "Creating topic: $topic"
            gcloud pubsub topics create "$topic" --quiet
            log_success "Created topic: $topic"
        fi
    done
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    if gsutil ls "gs://${STORAGE_BUCKET}" &> /dev/null; then
        log_warning "Bucket 'gs://${STORAGE_BUCKET}' already exists, skipping creation"
    else
        log_info "Creating bucket: gs://${STORAGE_BUCKET}"
        gsutil mb -p "$PROJECT_ID" \
            -c STANDARD \
            -l "$REGION" \
            "gs://${STORAGE_BUCKET}"
        log_success "Created bucket: gs://${STORAGE_BUCKET}"
    fi
}

# Function to initialize Firestore
initialize_firestore() {
    log_info "Initializing Firestore..."
    
    # Check if Firestore is already initialized
    if gcloud firestore databases describe --region="$REGION" &> /dev/null; then
        log_warning "Firestore database already exists, skipping initialization"
    else
        log_info "Creating Firestore database in region: $REGION"
        gcloud firestore databases create --region="$REGION" --quiet
        log_success "Firestore database initialized"
    fi
}

# Function to create Cloud Function source code
create_function_source() {
    log_info "Creating Cloud Function source code..."
    
    local source_dir="${PROJECT_ROOT}/functions"
    mkdir -p "$source_dir"
    
    # Create main error processor function
    cat > "$source_dir/main.py" << 'EOF'
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

PROJECT_ID = os.environ.get('GCP_PROJECT')
ALERT_TOPIC = os.environ.get('ALERT_TOPIC')

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
EOF

    # Create requirements.txt
    cat > "$source_dir/requirements.txt" << 'EOF'
google-cloud-error-reporting>=1.9.0
google-cloud-monitoring>=2.15.0
google-cloud-firestore>=2.11.0
google-cloud-pubsub>=2.18.0
functions-framework>=3.4.0
EOF

    # Create alert router function
    cat > "$source_dir/alert_router.py" << 'EOF'
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

PROJECT_ID = os.environ.get('GCP_PROJECT')
SLACK_WEBHOOK = os.environ.get('SLACK_WEBHOOK', '')

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
    if SLACK_WEBHOOK:
        send_slack_notification(message, '#critical-alerts')
    
    # Create incident record
    create_incident_record(error_info)

def send_high_priority_notifications(error_info):
    """Send high priority error notifications"""
    message = format_high_priority_message(error_info)
    
    if SLACK_WEBHOOK:
        send_slack_notification(message, '#error-alerts')

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
    if not SLACK_WEBHOOK:
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
EOF

    # Create requirements for alert router
    cat > "$source_dir/requirements_alert.txt" << 'EOF'
google-cloud-monitoring>=2.15.0
google-cloud-firestore>=2.11.0
functions-framework>=3.4.0
requests>=2.28.0
EOF

    # Create debug automation function
    cat > "$source_dir/debug_automation.py" << 'EOF'
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

PROJECT_ID = os.environ.get('GCP_PROJECT')
DEBUG_BUCKET = os.environ.get('DEBUG_BUCKET')

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
        
        filter_str = f'''
        resource.type="gae_app"
        resource.labels.module_id="{service}"
        timestamp>="{start_time.isoformat()}Z"
        timestamp<="{end_time.isoformat()}Z"
        '''
        
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
EOF

    # Create requirements for debug automation
    cat > "$source_dir/requirements_debug.txt" << 'EOF'
google-cloud-logging>=3.8.0
google-cloud-monitoring>=2.15.0
google-cloud-firestore>=2.11.0
google-cloud-storage>=2.10.0
functions-framework>=3.4.0
EOF

    # Create sample application
    cat > "$source_dir/sample_app.py" << 'EOF'
import json
import random
import time
from datetime import datetime
from google.cloud import error_reporting
from google.cloud import logging as cloud_logging
from flask import Flask, request, jsonify
import functions_framework

# Initialize error reporting client
error_client = error_reporting.Client()
logging_client = cloud_logging.Client()

app = Flask(__name__)

@functions_framework.http
def sample_app(request):
    """Sample application that generates various errors"""
    try:
        # Parse request
        request_json = request.get_json(silent=True)
        error_type = request_json.get('error_type', 'none') if request_json else 'none'
        
        # Generate different types of errors based on request
        if error_type == 'critical':
            simulate_critical_error()
        elif error_type == 'database':
            simulate_database_error()
        elif error_type == 'timeout':
            simulate_timeout_error()
        elif error_type == 'null_pointer':
            simulate_null_pointer_error()
        elif error_type == 'memory':
            simulate_memory_error()
        elif error_type == 'random':
            simulate_random_error()
        else:
            return jsonify({'status': 'success', 'message': 'No error generated'})
            
    except Exception as e:
        # Report error to Cloud Error Reporting
        error_client.report_exception()
        return jsonify({'status': 'error', 'message': str(e)}), 500

def simulate_critical_error():
    """Simulate a critical system error"""
    error_client.report(
        "CRITICAL: Payment processing system failure - Unable to process transactions",
        service="payment-service",
        version="1.2.0",
        user="user123"
    )
    raise Exception("Payment processing system failure")

def simulate_database_error():
    """Simulate a database connection error"""
    error_client.report(
        "Database connection failed: Connection timeout to primary database",
        service="user-service",
        version="2.1.0",
        user="system"
    )
    raise Exception("Database connection failed")

def simulate_timeout_error():
    """Simulate a timeout error"""
    error_client.report(
        "Request timeout: External API call exceeded 30 second timeout",
        service="api-gateway",
        version="1.0.5",
        user="anonymous"
    )
    raise Exception("Request timeout")

def simulate_null_pointer_error():
    """Simulate a null pointer error"""
    error_client.report(
        "NullPointerException: User object is null in session management",
        service="session-service",
        version="3.0.1",
        user="user456"
    )
    raise Exception("NullPointerException")

def simulate_memory_error():
    """Simulate a memory error"""
    error_client.report(
        "OutOfMemoryError: Java heap space exceeded during data processing",
        service="data-processor",
        version="2.3.0",
        user="system"
    )
    raise Exception("OutOfMemoryError")

def simulate_random_error():
    """Simulate a random error"""
    error_types = [
        ("Service temporarily unavailable", "load-balancer"),
        ("Invalid input format", "validation-service"),
        ("Authentication token expired", "auth-service"),
        ("File not found", "file-service"),
        ("Network connection lost", "network-service")
    ]
    
    error_msg, service = random.choice(error_types)
    error_client.report(
        error_msg,
        service=service,
        version="1.0.0",
        user=f"user{random.randint(100, 999)}"
    )
    raise Exception(error_msg)
EOF

    # Create requirements for sample app
    cat > "$source_dir/requirements_sample.txt" << 'EOF'
google-cloud-error-reporting>=1.9.0
google-cloud-logging>=3.8.0
flask>=2.3.0
functions-framework>=3.4.0
EOF
    
    log_success "Cloud Function source code created"
}

# Function to deploy Cloud Functions
deploy_cloud_functions() {
    log_info "Deploying Cloud Functions..."
    
    local source_dir="${PROJECT_ROOT}/functions"
    cd "$source_dir"
    
    # Deploy error processor function
    log_info "Deploying error processor function..."
    gcloud functions deploy "$FUNCTION_NAME" \
        --runtime=python39 \
        --trigger-topic="$PUBSUB_TOPIC" \
        --source=. \
        --entry-point=process_error \
        --set-env-vars="ALERT_TOPIC=${PUBSUB_TOPIC}-alerts" \
        --memory=256MB \
        --timeout=60s \
        --region="$REGION" \
        --quiet
    
    log_success "Error processor function deployed: $FUNCTION_NAME"
    
    # Deploy alert router function
    log_info "Deploying alert router function..."
    cp requirements_alert.txt requirements.txt
    gcloud functions deploy "${FUNCTION_NAME}-router" \
        --runtime=python39 \
        --trigger-topic="${PUBSUB_TOPIC}-alerts" \
        --source=. \
        --entry-point=route_alerts \
        --requirements-file=requirements_alert.txt \
        --set-env-vars="SLACK_WEBHOOK=${SLACK_WEBHOOK:-}" \
        --memory=256MB \
        --timeout=60s \
        --region="$REGION" \
        --quiet
    
    log_success "Alert router function deployed: ${FUNCTION_NAME}-router"
    
    # Deploy debug automation function
    log_info "Deploying debug automation function..."
    cp requirements_debug.txt requirements.txt
    gcloud functions deploy "${FUNCTION_NAME}-debug" \
        --runtime=python39 \
        --trigger-topic="${PUBSUB_TOPIC}-debug" \
        --source=. \
        --entry-point=automate_debugging \
        --requirements-file=requirements_debug.txt \
        --set-env-vars="DEBUG_BUCKET=${STORAGE_BUCKET}" \
        --memory=512MB \
        --timeout=120s \
        --region="$REGION" \
        --quiet
    
    log_success "Debug automation function deployed: ${FUNCTION_NAME}-debug"
    
    # Deploy sample application
    log_info "Deploying sample application..."
    cp requirements_sample.txt requirements.txt
    gcloud functions deploy sample-error-app \
        --runtime=python39 \
        --trigger-http \
        --source=. \
        --entry-point=sample_app \
        --requirements-file=requirements_sample.txt \
        --memory=128MB \
        --timeout=60s \
        --region="$REGION" \
        --allow-unauthenticated \
        --quiet
    
    log_success "Sample application deployed: sample-error-app"
    
    cd "$SCRIPT_DIR"
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    log_info "Creating monitoring dashboard..."
    
    local dashboard_config="${PROJECT_ROOT}/dashboard_config.json"
    
    cat > "$dashboard_config" << EOF
{
  "displayName": "Error Monitoring Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Error Rate by Service",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gae_app\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM",
                      "groupByFields": ["resource.label.module_id"]
                    }
                  }
                }
              }
            ],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "Errors per minute",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Error Processing Functions",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_function\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE",
                      "crossSeriesReducer": "REDUCE_SUM",
                      "groupByFields": ["resource.label.function_name"]
                    }
                  }
                }
              }
            ],
            "yAxis": {
              "label": "Executions per minute",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "width": 12,
        "height": 4,
        "yPos": 4,
        "widget": {
          "title": "Critical Error Alerts",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"global\"",
                "aggregation": {
                  "alignmentPeriod": "300s",
                  "perSeriesAligner": "ALIGN_SUM",
                  "crossSeriesReducer": "REDUCE_SUM"
                }
              }
            },
            "sparkChartView": {
              "sparkChartType": "SPARK_LINE"
            }
          }
        }
      }
    ]
  }
}
EOF
    
    gcloud monitoring dashboards create \
        --config-from-file="$dashboard_config" \
        --quiet
    
    log_success "Monitoring dashboard created"
}

# Function to set up log sink
setup_log_sink() {
    log_info "Setting up log sink for error notifications..."
    
    # Create log sink for error events
    gcloud logging sinks create error-notification-sink \
        "pubsub.googleapis.com/projects/${PROJECT_ID}/topics/${PUBSUB_TOPIC}" \
        --log-filter='protoPayload.serviceName="clouderrorreporting.googleapis.com"' \
        --quiet
    
    # Grant the sink permission to publish to Pub/Sub
    local sink_service_account
    sink_service_account=$(gcloud logging sinks describe error-notification-sink \
        --format="value(writerIdentity)")
    
    gcloud pubsub topics add-iam-policy-binding "$PUBSUB_TOPIC" \
        --member="$sink_service_account" \
        --role="roles/pubsub.publisher" \
        --quiet
    
    log_success "Log sink configured for error notifications"
}

# Function to run deployment validation
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check if functions are deployed
    local functions=(
        "$FUNCTION_NAME"
        "${FUNCTION_NAME}-router"
        "${FUNCTION_NAME}-debug"
        "sample-error-app"
    )
    
    for function in "${functions[@]}"; do
        if gcloud functions describe "$function" --region="$REGION" &> /dev/null; then
            log_success "Function validated: $function"
        else
            log_error "Function not found: $function"
            return 1
        fi
    done
    
    # Check if Pub/Sub topics exist
    local topics=(
        "$PUBSUB_TOPIC"
        "${PUBSUB_TOPIC}-alerts"
        "${PUBSUB_TOPIC}-debug"
    )
    
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe "$topic" &> /dev/null; then
            log_success "Topic validated: $topic"
        else
            log_error "Topic not found: $topic"
            return 1
        fi
    done
    
    # Check if storage bucket exists
    if gsutil ls "gs://${STORAGE_BUCKET}" &> /dev/null; then
        log_success "Bucket validated: gs://${STORAGE_BUCKET}"
    else
        log_error "Bucket not found: gs://${STORAGE_BUCKET}"
        return 1
    fi
    
    log_success "Deployment validation completed successfully"
}

# Function to display deployment summary
display_summary() {
    log_success "Error Monitoring System Deployment Complete!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Resource Suffix: $RESOURCE_SUFFIX"
    echo
    echo "=== DEPLOYED RESOURCES ==="
    echo "Cloud Functions:"
    echo "  - Error Processor: $FUNCTION_NAME"
    echo "  - Alert Router: ${FUNCTION_NAME}-router"
    echo "  - Debug Automation: ${FUNCTION_NAME}-debug"
    echo "  - Sample App: sample-error-app"
    echo
    echo "Pub/Sub Topics:"
    echo "  - Main Topic: $PUBSUB_TOPIC"
    echo "  - Alerts Topic: ${PUBSUB_TOPIC}-alerts"
    echo "  - Debug Topic: ${PUBSUB_TOPIC}-debug"
    echo
    echo "Storage:"
    echo "  - Debug Bucket: gs://${STORAGE_BUCKET}"
    echo "  - Firestore Database: Initialized"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Test the system by generating errors:"
    local sample_app_url
    sample_app_url=$(gcloud functions describe sample-error-app --region="$REGION" --format="value(httpsTrigger.url)")
    echo "   curl -X POST \"$sample_app_url\" -H \"Content-Type: application/json\" -d '{\"error_type\": \"critical\"}'"
    echo
    echo "2. Monitor errors in the Cloud Console:"
    echo "   https://console.cloud.google.com/errors?project=$PROJECT_ID"
    echo
    echo "3. View monitoring dashboard:"
    echo "   https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID"
    echo
    echo "4. Check Firestore for error records:"
    echo "   https://console.cloud.google.com/firestore?project=$PROJECT_ID"
    echo
    if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
        echo "5. Slack notifications configured for critical alerts"
    else
        echo "5. Configure Slack webhook URL for notifications (optional)"
    fi
    echo
    echo "To clean up resources, run: ./destroy.sh --project-id $PROJECT_ID"
}

# Main deployment function
main() {
    local project_id=""
    local region="$DEFAULT_REGION"
    local zone="$DEFAULT_ZONE"
    local resource_suffix=""
    local slack_webhook=""
    local dry_run=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                project_id="$2"
                shift 2
                ;;
            -r|--region)
                region="$2"
                shift 2
                ;;
            -z|--zone)
                zone="$2"
                shift 2
                ;;
            -s|--suffix)
                resource_suffix="$2"
                shift 2
                ;;
            --slack-webhook)
                slack_webhook="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$project_id" ]]; then
        log_error "Project ID is required. Use --project-id or -p option."
        usage
        exit 1
    fi
    
    # Set global variables
    PROJECT_ID="$project_id"
    REGION="$region"
    ZONE="$zone"
    RESOURCE_SUFFIX="$resource_suffix"
    SLACK_WEBHOOK="$slack_webhook"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        log_info "Would deploy error monitoring system with:"
        log_info "  Project ID: $PROJECT_ID"
        log_info "  Region: $REGION"
        log_info "  Zone: $ZONE"
        log_info "  Resource Suffix: ${RESOURCE_SUFFIX:-auto-generated}"
        log_info "  Slack Webhook: ${SLACK_WEBHOOK:-not configured}"
        exit 0
    fi
    
    log_info "Starting deployment of Error Monitoring System..."
    log_info "Project: $PROJECT_ID"
    log_info "Region: $REGION"
    
    # Execute deployment steps
    check_prerequisites
    validate_project
    enable_apis
    set_environment_variables
    create_pubsub_topics
    create_storage_bucket
    initialize_firestore
    create_function_source
    deploy_cloud_functions
    create_monitoring_dashboard
    setup_log_sink
    validate_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function with all arguments
main "$@"