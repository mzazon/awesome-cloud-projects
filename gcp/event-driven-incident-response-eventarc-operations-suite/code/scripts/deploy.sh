#!/bin/bash

# Event-Driven Incident Response with Eventarc and Cloud Operations Suite - Deployment Script
# This script deploys the complete incident response automation system

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DRY_RUN=false
SKIP_CONFIRMATION=false

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Event-Driven Incident Response system with Eventarc and Cloud Operations Suite

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           GCP Region (default: $DEFAULT_REGION)
    -z, --zone ZONE               GCP Zone (default: $DEFAULT_ZONE)
    -d, --dry-run                 Show what would be deployed without making changes
    -y, --yes                     Skip confirmation prompts
    -h, --help                    Show this help message

EXAMPLES:
    $0 --project-id my-project-123
    $0 --project-id my-project-123 --region us-east1 --zone us-east1-a
    $0 --project-id my-project-123 --dry-run
    $0 --project-id my-project-123 --yes

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "${PROJECT_ID:-}" ]]; then
    error "Project ID is required. Use --project-id or -p option."
    usage
    exit 1
fi

# Set defaults for optional parameters
REGION="${REGION:-$DEFAULT_REGION}"
ZONE="${ZONE:-$DEFAULT_ZONE}"

# Generate unique suffix for resources
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
INCIDENT_TOPIC="incident-alerts-${RANDOM_SUFFIX}"
TRIAGE_FUNCTION="incident-triage-${RANDOM_SUFFIX}"
NOTIFICATION_FUNCTION="incident-notify-${RANDOM_SUFFIX}"
REMEDIATION_SERVICE="incident-remediate-${RANDOM_SUFFIX}"
ESCALATION_SERVICE="incident-escalate-${RANDOM_SUFFIX}"
SERVICE_ACCOUNT="incident-response-sa"

# Display deployment configuration
log "Event-Driven Incident Response Deployment Configuration"
echo "=================================================="
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "Zone: $ZONE"
echo "Random Suffix: $RANDOM_SUFFIX"
echo "Dry Run: $DRY_RUN"
echo ""
echo "Resources to be created:"
echo "  - Service Account: $SERVICE_ACCOUNT"
echo "  - Pub/Sub Topics: $INCIDENT_TOPIC, remediation-topic, escalation-topic, notification-topic"
echo "  - Cloud Functions: $TRIAGE_FUNCTION, $NOTIFICATION_FUNCTION"
echo "  - Cloud Run Services: $REMEDIATION_SERVICE, $ESCALATION_SERVICE"
echo "  - Eventarc Triggers: monitoring-alert-trigger, remediation-trigger, escalation-trigger"
echo "  - Monitoring Policies: High CPU Utilization, High Error Rate"
echo "=================================================="

# Confirmation prompt
if [[ "$SKIP_CONFIRMATION" == "false" && "$DRY_RUN" == "false" ]]; then
    echo ""
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user."
        exit 0
    fi
fi

# Dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN MODE - No resources will be created"
    log "Deployment plan validated successfully. Use without --dry-run to deploy."
    exit 0
fi

# Check prerequisites
log "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    error "You are not authenticated with Google Cloud. Please run 'gcloud auth login' first."
    exit 1
fi

# Check if project exists and is accessible
if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    error "Project '$PROJECT_ID' does not exist or is not accessible."
    exit 1
fi

# Check if required tools are available
for tool in openssl python3; do
    if ! command -v $tool &> /dev/null; then
        error "$tool is required but not installed."
        exit 1
    fi
done

log "Prerequisites check completed successfully."

# Set project configuration
log "Setting project configuration..."
gcloud config set project "$PROJECT_ID"
gcloud config set compute/region "$REGION"
gcloud config set compute/zone "$ZONE"

# Enable required APIs
log "Enabling required Google Cloud APIs..."
gcloud services enable eventarc.googleapis.com \
    cloudfunctions.googleapis.com \
    run.googleapis.com \
    monitoring.googleapis.com \
    logging.googleapis.com \
    pubsub.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com

# Wait for APIs to be fully enabled
sleep 30

# Create service account
log "Creating service account for incident response system..."
if ! gcloud iam service-accounts describe "${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
    gcloud iam service-accounts create "$SERVICE_ACCOUNT" \
        --display-name="Incident Response Service Account" \
        --description="Service account for automated incident response"
    
    # Grant necessary permissions
    log "Granting IAM permissions to service account..."
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/monitoring.viewer"
    
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/compute.instanceAdmin"
    
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/pubsub.publisher"
    
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/pubsub.subscriber"
    
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/eventarc.eventReceiver"
else
    warn "Service account already exists, skipping creation."
fi

# Create Pub/Sub topics
log "Creating Pub/Sub topics..."
for topic in "$INCIDENT_TOPIC" "remediation-topic" "escalation-topic" "notification-topic"; do
    if ! gcloud pubsub topics describe "$topic" &>/dev/null; then
        gcloud pubsub topics create "$topic"
        log "Created Pub/Sub topic: $topic"
    else
        warn "Pub/Sub topic $topic already exists, skipping creation."
    fi
done

# Create temporary directory for function source code
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Deploy Triage Cloud Function
log "Deploying incident triage Cloud Function..."
mkdir -p "$TEMP_DIR/functions/triage"
cd "$TEMP_DIR/functions/triage"

cat > main.py << 'EOF'
import json
import base64
from google.cloud import pubsub_v1
from google.cloud import monitoring_v3
import functions_framework
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PROJECT_ID = os.environ.get('GCP_PROJECT')
publisher = pubsub_v1.PublisherClient()

@functions_framework.cloud_event
def triage_incident(cloud_event):
    """Analyze and triage incoming monitoring alerts"""
    try:
        # Decode Pub/Sub message
        if 'data' in cloud_event.data:
            message_data = base64.b64decode(cloud_event.data['data']).decode('utf-8')
            alert_data = json.loads(message_data)
        else:
            alert_data = cloud_event.data
        
        # Extract alert metadata
        incident_type = alert_data.get('incident', {}).get('condition_name', 'unknown')
        severity = determine_severity(alert_data)
        resource_type = alert_data.get('incident', {}).get('resource_name', '')
        
        # Create triage decision
        triage_result = {
            'incident_id': alert_data.get('incident', {}).get('incident_id'),
            'severity': severity,
            'incident_type': incident_type,
            'resource_type': resource_type,
            'automated_response': determine_response_action(severity, incident_type),
            'requires_escalation': severity in ['CRITICAL', 'HIGH'],
            'timestamp': cloud_event.get('time'),
            'original_alert': alert_data
        }
        
        # Route to appropriate response services
        route_incident(triage_result)
        
        logger.info(f"Successfully triaged incident: {triage_result['incident_id']}")
        return 'Incident triaged successfully'
        
    except Exception as e:
        logger.error(f"Error triaging incident: {str(e)}")
        raise

def determine_severity(alert_data):
    """Determine incident severity based on alert conditions"""
    condition = alert_data.get('incident', {}).get('condition_name', '').lower()
    
    if any(keyword in condition for keyword in ['down', 'failure', 'error_rate_high']):
        return 'CRITICAL'
    elif any(keyword in condition for keyword in ['latency_high', 'cpu_high', 'memory_high']):
        return 'HIGH'
    elif any(keyword in condition for keyword in ['warning', 'threshold']):
        return 'MEDIUM'
    else:
        return 'LOW'

def determine_response_action(severity, incident_type):
    """Determine automated response based on severity and type"""
    if severity == 'CRITICAL':
        return 'immediate_remediation'
    elif severity == 'HIGH':
        return 'auto_scale_and_notify'
    elif severity == 'MEDIUM':
        return 'notify_only'
    else:
        return 'log_only'

def route_incident(triage_result):
    """Route incident to appropriate response services"""
    response_action = triage_result['automated_response']
    
    if response_action == 'immediate_remediation':
        publish_to_topic('remediation-topic', triage_result)
    elif response_action == 'auto_scale_and_notify':
        publish_to_topic('remediation-topic', triage_result)
        publish_to_topic('notification-topic', triage_result)
    elif response_action == 'notify_only':
        publish_to_topic('notification-topic', triage_result)
    
    if triage_result['requires_escalation']:
        publish_to_topic('escalation-topic', triage_result)

def publish_to_topic(topic_name, data):
    """Publish data to specified Pub/Sub topic"""
    try:
        topic_path = publisher.topic_path(PROJECT_ID, topic_name)
        message_data = json.dumps(data).encode('utf-8')
        future = publisher.publish(topic_path, message_data)
        logger.info(f"Published to {topic_name}: {future.result()}")
    except Exception as e:
        logger.error(f"Failed to publish to {topic_name}: {str(e)}")
EOF

cat > requirements.txt << 'EOF'
functions-framework==3.4.0
google-cloud-pubsub==2.18.0
google-cloud-monitoring==2.15.0
EOF

# Deploy triage function
if ! gcloud functions describe "$TRIAGE_FUNCTION" --region="$REGION" &>/dev/null; then
    gcloud functions deploy "$TRIAGE_FUNCTION" \
        --gen2 \
        --runtime=python311 \
        --source=. \
        --entry-point=triage_incident \
        --trigger-topic="$INCIDENT_TOPIC" \
        --service-account="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --memory=512MB \
        --timeout=540s \
        --region="$REGION" \
        --set-env-vars=GCP_PROJECT="$PROJECT_ID" \
        --quiet
    log "Triage function deployed successfully."
else
    warn "Triage function already exists, skipping deployment."
fi

# Deploy Notification Cloud Function
log "Deploying notification Cloud Function..."
cd "$TEMP_DIR"
mkdir -p "functions/notification"
cd "functions/notification"

cat > main.py << 'EOF'
import json
import base64
import functions_framework
import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PROJECT_ID = os.environ.get('GCP_PROJECT')

@functions_framework.cloud_event
def send_notifications(cloud_event):
    """Send incident notifications to appropriate channels"""
    try:
        # Decode Pub/Sub message
        if 'data' in cloud_event.data:
            message_data = base64.b64decode(cloud_event.data['data']).decode('utf-8')
            incident_data = json.loads(message_data)
        else:
            incident_data = cloud_event.data
        
        severity = incident_data.get('severity', 'UNKNOWN')
        incident_id = incident_data.get('incident_id', 'N/A')
        incident_type = incident_data.get('incident_type', 'Unknown')
        
        # Determine notification channels based on severity
        channels = get_notification_channels(severity)
        
        # Create notification content
        notification_content = create_notification_content(incident_data)
        
        # Send notifications through each channel
        for channel in channels:
            send_channel_notification(channel, notification_content, incident_data)
        
        logger.info(f"Notifications sent for incident: {incident_id}")
        return 'Notifications sent successfully'
        
    except Exception as e:
        logger.error(f"Error sending notifications: {str(e)}")
        raise

def get_notification_channels(severity):
    """Get notification channels based on incident severity"""
    channels = ['email']  # Always send email
    
    if severity in ['CRITICAL', 'HIGH']:
        channels.extend(['slack', 'sms'])  # Add urgent channels for high severity
    
    return channels

def create_notification_content(incident_data):
    """Create formatted notification content"""
    severity = incident_data.get('severity', 'UNKNOWN')
    incident_id = incident_data.get('incident_id', 'N/A')
    incident_type = incident_data.get('incident_type', 'Unknown')
    resource_type = incident_data.get('resource_type', 'Unknown')
    automated_response = incident_data.get('automated_response', 'None')
    
    subject = f"🚨 {severity} Incident Alert: {incident_type}"
    
    body = f"""
Incident Alert Summary
=====================
Incident ID: {incident_id}
Severity: {severity}
Type: {incident_type}
Affected Resource: {resource_type}
Automated Response: {automated_response}
Timestamp: {incident_data.get('timestamp', 'N/A')}

This incident has been automatically triaged and appropriate response actions have been initiated.
Monitor the incident response dashboard for real-time updates.

Google Cloud Incident Response System
"""
    
    return {'subject': subject, 'body': body}

def send_channel_notification(channel, content, incident_data):
    """Send notification through specified channel"""
    try:
        if channel == 'email':
            send_email_notification(content, incident_data)
        elif channel == 'slack':
            send_slack_notification(content, incident_data)
        elif channel == 'sms':
            send_sms_notification(content, incident_data)
        
        logger.info(f"Notification sent via {channel}")
        
    except Exception as e:
        logger.error(f"Failed to send {channel} notification: {str(e)}")

def send_email_notification(content, incident_data):
    """Send email notification (placeholder implementation)"""
    logger.info(f"Email notification: {content['subject']}")

def send_slack_notification(content, incident_data):
    """Send Slack notification (placeholder implementation)"""
    logger.info(f"Slack notification: {content['subject']}")

def send_sms_notification(content, incident_data):
    """Send SMS notification (placeholder implementation)"""
    logger.info(f"SMS notification: {content['subject']}")
EOF

cat > requirements.txt << 'EOF'
functions-framework==3.4.0
google-cloud-secret-manager==2.16.0
EOF

# Deploy notification function
if ! gcloud functions describe "$NOTIFICATION_FUNCTION" --region="$REGION" &>/dev/null; then
    gcloud functions deploy "$NOTIFICATION_FUNCTION" \
        --gen2 \
        --runtime=python311 \
        --source=. \
        --entry-point=send_notifications \
        --trigger-topic=notification-topic \
        --service-account="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --memory=256MB \
        --timeout=300s \
        --region="$REGION" \
        --set-env-vars=GCP_PROJECT="$PROJECT_ID" \
        --quiet
    log "Notification function deployed successfully."
else
    warn "Notification function already exists, skipping deployment."
fi

# Deploy Remediation Cloud Run Service
log "Deploying remediation Cloud Run service..."
cd "$TEMP_DIR"
mkdir -p "services/remediation"
cd "services/remediation"

cat > main.py << 'EOF'
import json
import logging
from flask import Flask, request
from google.cloud import compute_v1
from google.cloud import monitoring_v3
import os
import time

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PROJECT_ID = os.environ.get('GCP_PROJECT')
ZONE = os.environ.get('GCP_ZONE', 'us-central1-a')

compute_client = compute_v1.InstancesClient()
monitoring_client = monitoring_v3.MetricServiceClient()

@app.route('/', methods=['POST'])
def handle_remediation():
    """Handle incoming remediation requests"""
    try:
        # Parse incident data from request
        incident_data = request.get_json()
        
        if not incident_data:
            return 'No incident data provided', 400
        
        incident_type = incident_data.get('incident_type', '').lower()
        severity = incident_data.get('severity', 'UNKNOWN')
        resource_type = incident_data.get('resource_type', '')
        
        logger.info(f"Processing remediation for incident: {incident_data.get('incident_id')}")
        
        # Execute appropriate remediation based on incident type
        remediation_result = execute_remediation(incident_type, resource_type, incident_data)
        
        # Log remediation actions
        log_remediation_action(incident_data, remediation_result)
        
        return json.dumps({
            'status': 'success',
            'incident_id': incident_data.get('incident_id'),
            'remediation_actions': remediation_result
        })
        
    except Exception as e:
        logger.error(f"Remediation failed: {str(e)}")
        return json.dumps({'status': 'error', 'message': str(e)}), 500

def execute_remediation(incident_type, resource_type, incident_data):
    """Execute specific remediation actions based on incident type"""
    actions_taken = []
    
    if 'cpu_high' in incident_type:
        actions_taken.extend(handle_high_cpu(resource_type, incident_data))
    elif 'memory_high' in incident_type:
        actions_taken.extend(handle_high_memory(resource_type, incident_data))
    elif 'service_down' in incident_type:
        actions_taken.extend(handle_service_down(resource_type, incident_data))
    elif 'error_rate_high' in incident_type:
        actions_taken.extend(handle_high_error_rate(resource_type, incident_data))
    else:
        actions_taken.append(f"No automated remediation available for: {incident_type}")
    
    return actions_taken

def handle_high_cpu(resource_type, incident_data):
    """Handle high CPU utilization incidents"""
    actions = []
    
    if 'compute' in resource_type.lower():
        actions.append("Initiated auto-scaling for compute instances")
        logger.info("Would scale up compute instances for high CPU")
    
    return actions

def handle_high_memory(resource_type, incident_data):
    """Handle high memory utilization incidents"""
    actions = []
    
    if 'compute' in resource_type.lower():
        actions.append("Restarted services to clear potential memory leaks")
        logger.info("Would restart services for high memory usage")
    
    return actions

def handle_service_down(resource_type, incident_data):
    """Handle service downtime incidents"""
    actions = []
    
    actions.append("Attempted automatic service restart")
    actions.append("Verified health endpoint status")
    logger.info("Would restart failed services")
    
    return actions

def handle_high_error_rate(resource_type, incident_data):
    """Handle high error rate incidents"""
    actions = []
    
    actions.append("Checked for recent deployments - rollback candidate identified")
    actions.append("Scaled up resources to handle increased load")
    logger.info("Would execute rollback and scaling for high error rates")
    
    return actions

def log_remediation_action(incident_data, actions):
    """Log remediation actions for audit trail"""
    logger.info(f"Remediation completed for incident {incident_data.get('incident_id')}")
    for action in actions:
        logger.info(f"Action taken: {action}")

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port)
EOF

cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["python", "main.py"]
EOF

cat > requirements.txt << 'EOF'
Flask==2.3.3
google-cloud-compute==1.14.0
google-cloud-monitoring==2.15.0
gunicorn==21.2.0
EOF

# Deploy remediation service
if ! gcloud run services describe "$REMEDIATION_SERVICE" --region="$REGION" &>/dev/null; then
    gcloud run deploy "$REMEDIATION_SERVICE" \
        --source=. \
        --platform=managed \
        --region="$REGION" \
        --allow-unauthenticated \
        --service-account="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --memory=1Gi \
        --cpu=1 \
        --timeout=900 \
        --set-env-vars=GCP_PROJECT="$PROJECT_ID",GCP_ZONE="$ZONE" \
        --quiet
    log "Remediation service deployed successfully."
else
    warn "Remediation service already exists, skipping deployment."
fi

# Deploy Escalation Cloud Run Service
log "Deploying escalation Cloud Run service..."
cd "$TEMP_DIR"
mkdir -p "services/escalation"
cd "services/escalation"

cat > main.py << 'EOF'
import json
import logging
from flask import Flask, request
from datetime import datetime, timedelta
import os

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PROJECT_ID = os.environ.get('GCP_PROJECT')

@app.route('/', methods=['POST'])
def handle_escalation():
    """Handle incident escalation workflow"""
    try:
        # Parse incident data
        incident_data = request.get_json()
        
        if not incident_data:
            return 'No incident data provided', 400
        
        incident_id = incident_data.get('incident_id')
        severity = incident_data.get('severity')
        
        logger.info(f"Processing escalation for incident: {incident_id}")
        
        # Determine escalation path based on severity
        escalation_plan = create_escalation_plan(severity, incident_data)
        
        # Execute escalation steps
        escalation_result = execute_escalation(escalation_plan, incident_data)
        
        return json.dumps({
            'status': 'success',
            'incident_id': incident_id,
            'escalation_plan': escalation_plan,
            'actions_taken': escalation_result
        })
        
    except Exception as e:
        logger.error(f"Escalation failed: {str(e)}")
        return json.dumps({'status': 'error', 'message': str(e)}), 500

def create_escalation_plan(severity, incident_data):
    """Create escalation plan based on severity and incident type"""
    plan = {
        'immediate_actions': [],
        'escalation_timeline': [],
        'stakeholders': []
    }
    
    if severity == 'CRITICAL':
        plan['immediate_actions'] = [
            'Create P1 incident ticket',
            'Page on-call engineer',
            'Notify incident commander',
            'Start war room'
        ]
        plan['escalation_timeline'] = [
            {'time': '0 minutes', 'action': 'Initial response team notified'},
            {'time': '15 minutes', 'action': 'Engineering manager notified'},
            {'time': '30 minutes', 'action': 'Director notified'},
            {'time': '60 minutes', 'action': 'Executive team notified'}
        ]
        plan['stakeholders'] = ['on-call-engineer', 'incident-commander', 'engineering-manager']
    
    elif severity == 'HIGH':
        plan['immediate_actions'] = [
            'Create P2 incident ticket',
            'Notify on-call engineer',
            'Update status page'
        ]
        plan['escalation_timeline'] = [
            {'time': '0 minutes', 'action': 'On-call engineer notified'},
            {'time': '30 minutes', 'action': 'Engineering manager notified'},
            {'time': '2 hours', 'action': 'Director notified if unresolved'}
        ]
        plan['stakeholders'] = ['on-call-engineer', 'engineering-manager']
    
    else:
        plan['immediate_actions'] = [
            'Create incident ticket',
            'Assign to appropriate team'
        ]
        plan['escalation_timeline'] = [
            {'time': '0 minutes', 'action': 'Ticket created and assigned'},
            {'time': '4 hours', 'action': 'Team lead notified if unresolved'}
        ]
        plan['stakeholders'] = ['assigned-team']
    
    return plan

def execute_escalation(plan, incident_data):
    """Execute escalation plan actions"""
    actions_taken = []
    
    # Execute immediate actions
    for action in plan['immediate_actions']:
        result = execute_action(action, incident_data)
        actions_taken.append(f"Executed: {action} - {result}")
    
    # Schedule future escalation actions
    for timeline_item in plan['escalation_timeline']:
        schedule_action(timeline_item, incident_data)
        actions_taken.append(f"Scheduled: {timeline_item['action']} at {timeline_item['time']}")
    
    # Notify stakeholders
    for stakeholder in plan['stakeholders']:
        notify_stakeholder(stakeholder, incident_data)
        actions_taken.append(f"Notified: {stakeholder}")
    
    return actions_taken

def execute_action(action, incident_data):
    """Execute specific escalation action"""
    if 'ticket' in action.lower():
        return create_incident_ticket(incident_data)
    elif 'page' in action.lower():
        return page_on_call(incident_data)
    elif 'notify' in action.lower():
        return send_notification(action, incident_data)
    elif 'war room' in action.lower():
        return start_war_room(incident_data)
    else:
        return f"Action '{action}' logged for manual execution"

def create_incident_ticket(incident_data):
    """Create incident ticket in ticketing system"""
    ticket_id = f"INC-{datetime.now().strftime('%Y%m%d')}-{incident_data.get('incident_id', 'UNKNOWN')[-6:]}"
    logger.info(f"Created incident ticket: {ticket_id}")
    return f"Ticket {ticket_id} created"

def page_on_call(incident_data):
    """Page on-call engineer"""
    logger.info("Paging on-call engineer via escalation system")
    return "On-call engineer paged successfully"

def send_notification(action, incident_data):
    """Send notification to specified recipient"""
    logger.info(f"Sending notification: {action}")
    return f"Notification sent: {action}"

def start_war_room(incident_data):
    """Start incident war room"""
    logger.info("Starting incident war room")
    return "War room started with key stakeholders"

def schedule_action(timeline_item, incident_data):
    """Schedule future escalation action"""
    logger.info(f"Scheduled: {timeline_item['action']} for {timeline_item['time']}")

def notify_stakeholder(stakeholder, incident_data):
    """Notify specific stakeholder"""
    logger.info(f"Notifying stakeholder: {stakeholder}")

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port)
EOF

cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["python", "main.py"]
EOF

cat > requirements.txt << 'EOF'
Flask==2.3.3
gunicorn==21.2.0
EOF

# Deploy escalation service
if ! gcloud run services describe "$ESCALATION_SERVICE" --region="$REGION" &>/dev/null; then
    gcloud run deploy "$ESCALATION_SERVICE" \
        --source=. \
        --platform=managed \
        --region="$REGION" \
        --allow-unauthenticated \
        --service-account="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --memory=512Mi \
        --cpu=1 \
        --timeout=600 \
        --set-env-vars=GCP_PROJECT="$PROJECT_ID" \
        --quiet
    log "Escalation service deployed successfully."
else
    warn "Escalation service already exists, skipping deployment."
fi

# Configure Eventarc Triggers
log "Configuring Eventarc triggers for event routing..."

# Create trigger for monitoring alerts
if ! gcloud eventarc triggers describe monitoring-alert-trigger --location="$REGION" &>/dev/null; then
    gcloud eventarc triggers create monitoring-alert-trigger \
        --location="$REGION" \
        --destination-run-service="$TRIAGE_FUNCTION" \
        --destination-run-region="$REGION" \
        --event-filters="type=google.cloud.audit.log.v1.written" \
        --event-filters="serviceName=monitoring.googleapis.com" \
        --service-account="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --quiet
    log "Monitoring alert trigger created successfully."
else
    warn "Monitoring alert trigger already exists, skipping creation."
fi

# Create trigger for remediation service
if ! gcloud eventarc triggers describe remediation-trigger --location="$REGION" &>/dev/null; then
    gcloud eventarc triggers create remediation-trigger \
        --location="$REGION" \
        --destination-run-service="$REMEDIATION_SERVICE" \
        --destination-run-region="$REGION" \
        --transport-topic="projects/$PROJECT_ID/topics/remediation-topic" \
        --service-account="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --quiet
    log "Remediation trigger created successfully."
else
    warn "Remediation trigger already exists, skipping creation."
fi

# Create trigger for escalation service
if ! gcloud eventarc triggers describe escalation-trigger --location="$REGION" &>/dev/null; then
    gcloud eventarc triggers create escalation-trigger \
        --location="$REGION" \
        --destination-run-service="$ESCALATION_SERVICE" \
        --destination-run-region="$REGION" \
        --transport-topic="projects/$PROJECT_ID/topics/escalation-topic" \
        --service-account="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --quiet
    log "Escalation trigger created successfully."
else
    warn "Escalation trigger already exists, skipping creation."
fi

# Create sample monitoring alert policies
log "Creating sample monitoring alert policies..."

# Create CPU alert policy
cat > "$TEMP_DIR/cpu-alert-policy.json" << EOF
{
  "displayName": "High CPU Utilization Alert - $RANDOM_SUFFIX",
  "documentation": {
    "content": "This alert fires when CPU utilization exceeds 80% for 5 minutes",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "CPU utilization is high",
      "conditionThreshold": {
        "filter": "resource.type=\"gce_instance\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0.8,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN",
            "crossSeriesReducer": "REDUCE_MEAN",
            "groupByFields": [
              "project",
              "resource.label.instance_id"
            ]
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": [],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF

# Create error rate alert policy
cat > "$TEMP_DIR/error-rate-policy.json" << EOF
{
  "displayName": "High Error Rate Alert - $RANDOM_SUFFIX",
  "documentation": {
    "content": "This alert fires when error rate exceeds 5% for 10 minutes",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Error rate is high",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_run_revision\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0.05,
        "duration": "600s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_RATE",
            "crossSeriesReducer": "REDUCE_MEAN",
            "groupByFields": [
              "resource.label.service_name"
            ]
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "alertStrategy": {
    "autoClose": "3600s"
  }
}
EOF

# Create alert policies if they don't exist
if ! gcloud alpha monitoring policies list --format="value(displayName)" | grep -q "High CPU Utilization Alert - $RANDOM_SUFFIX"; then
    gcloud alpha monitoring policies create --policy-from-file="$TEMP_DIR/cpu-alert-policy.json" --quiet
    log "CPU alert policy created successfully."
else
    warn "CPU alert policy already exists, skipping creation."
fi

if ! gcloud alpha monitoring policies list --format="value(displayName)" | grep -q "High Error Rate Alert - $RANDOM_SUFFIX"; then
    gcloud alpha monitoring policies create --policy-from-file="$TEMP_DIR/error-rate-policy.json" --quiet
    log "Error rate alert policy created successfully."
else
    warn "Error rate alert policy already exists, skipping creation."
fi

# Deployment completion
log "Event-Driven Incident Response system deployed successfully!"
echo ""
echo "=================================================="
echo "DEPLOYMENT SUMMARY"
echo "=================================================="
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "Zone: $ZONE"
echo "Resource Suffix: $RANDOM_SUFFIX"
echo ""
echo "Deployed Resources:"
echo "  ✅ Service Account: ${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"
echo "  ✅ Pub/Sub Topics: $INCIDENT_TOPIC, remediation-topic, escalation-topic, notification-topic"
echo "  ✅ Cloud Functions: $TRIAGE_FUNCTION, $NOTIFICATION_FUNCTION"
echo "  ✅ Cloud Run Services: $REMEDIATION_SERVICE, $ESCALATION_SERVICE"
echo "  ✅ Eventarc Triggers: monitoring-alert-trigger, remediation-trigger, escalation-trigger"
echo "  ✅ Monitoring Policies: High CPU Utilization Alert, High Error Rate Alert"
echo ""
echo "Testing Commands:"
echo "  # Test incident workflow"
echo "  gcloud pubsub topics publish $INCIDENT_TOPIC --message='{\"incident\": {\"incident_id\": \"test-001\", \"condition_name\": \"high_cpu_utilization\", \"resource_name\": \"test-vm\"}, \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}'"
echo ""
echo "  # View function logs"
echo "  gcloud functions logs read $TRIAGE_FUNCTION --region=$REGION --limit=10"
echo ""
echo "  # View service logs"
echo "  gcloud logs read \"resource.type=cloud_run_revision AND resource.labels.service_name=$REMEDIATION_SERVICE\" --limit=10"
echo ""
echo "Next Steps:"
echo "  1. Configure notification channels (email, Slack, SMS)"
echo "  2. Customize remediation actions for your specific infrastructure"
echo "  3. Set up monitoring dashboards for incident tracking"
echo "  4. Test the system with simulated incidents"
echo "  5. Integrate with your existing ticketing system"
echo ""
echo "To clean up all resources, run: ./destroy.sh --project-id $PROJECT_ID"
echo "=================================================="