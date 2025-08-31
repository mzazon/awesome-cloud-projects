#!/bin/bash

# Deploy script for Simple Application Health Monitoring with Cloud Monitoring
# This script deploys a complete monitoring solution using Cloud Monitoring and Cloud Functions

set -euo pipefail

# Colors for output
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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it first."
        log_info "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null | head -n1)
    log_info "Using gcloud CLI version: ${gcloud_version}"
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        log_error "No authenticated gcloud account found. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command_exists openssl; then
        log_error "openssl is not available. Please install openssl for random string generation."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-monitoring-demo-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    # Set resource names
    export TOPIC_NAME="monitoring-alerts-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="alert-notifier-${RANDOM_SUFFIX}"
    
    # Create temporary directory for function source
    export FUNCTION_SOURCE_DIR="/tmp/alert-function-${RANDOM_SUFFIX}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
    log_info "Random suffix: ${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured"
}

# Function to create or validate project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log_warning "Project ${PROJECT_ID} does not exist."
        read -p "Do you want to create it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Creating project ${PROJECT_ID}..."
            gcloud projects create "${PROJECT_ID}"
            log_success "Project ${PROJECT_ID} created"
        else
            log_error "Project is required for deployment. Exiting."
            exit 1
        fi
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "monitoring.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "${api} enabled successfully"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create Pub/Sub topic
create_pubsub_topic() {
    log_info "Creating Pub/Sub topic: ${TOPIC_NAME}..."
    
    # Check if topic already exists
    if gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        log_info "Pub/Sub topic ${TOPIC_NAME} already exists"
    else
        if gcloud pubsub topics create "${TOPIC_NAME}"; then
            log_success "Pub/Sub topic ${TOPIC_NAME} created successfully"
        else
            log_error "Failed to create Pub/Sub topic"
            exit 1
        fi
    fi
}

# Function to create Cloud Function source code
create_function_source() {
    log_info "Creating Cloud Function source code..."
    
    # Create function source directory
    mkdir -p "${FUNCTION_SOURCE_DIR}"
    cd "${FUNCTION_SOURCE_DIR}"
    
    # Create main.py with email notification logic
    cat > main.py << 'EOF'
import json
import base64
import functions_framework
import logging
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.cloud_event
def send_alert_email(cloud_event):
    """Send email notification for monitoring alerts."""
    try:
        # Decode Pub/Sub message data
        if cloud_event.data and 'message' in cloud_event.data:
            message_data = cloud_event.data['message']['data']
            pubsub_message = base64.b64decode(message_data).decode('utf-8')
            alert_data = json.loads(pubsub_message)
        else:
            logger.error("No message data found in cloud event")
            return "Error: No message data"
        
        # Extract alert information with proper error handling
        incident = alert_data.get('incident', {})
        policy_name = incident.get('policy_name', 'Unknown Policy')
        state = incident.get('state', 'UNKNOWN')
        started_at = incident.get('started_at', 'Unknown')
        
        # Log alert details for monitoring
        alert_summary = {
            'policy_name': policy_name,
            'state': state,
            'timestamp': datetime.utcnow().isoformat(),
            'started_at': started_at
        }
        
        logger.info(f"Processing alert: {json.dumps(alert_summary)}")
        
        # In a production environment, you would integrate with an email service
        # such as SendGrid, Mailgun, or Gmail API here
        if state == 'OPEN':
            logger.warning(f"ALERT: {policy_name} is DOWN as of {started_at}")
        elif state == 'CLOSED':
            logger.info(f"RESOLVED: {policy_name} is back UP as of {started_at}")
        
        return f"Alert notification processed for {policy_name} - {state}"
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to decode JSON message: {str(e)}")
        return f"JSON decode error: {str(e)}"
    except Exception as e:
        logger.error(f"Error processing alert: {str(e)}")
        return f"Error: {str(e)}"
EOF
    
    # Create requirements.txt with current versions
    cat > requirements.txt << 'EOF'
functions-framework==3.*
google-cloud-logging==3.*
EOF
    
    log_success "Cloud Function source code created in ${FUNCTION_SOURCE_DIR}"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying Cloud Function: ${FUNCTION_NAME}..."
    
    cd "${FUNCTION_SOURCE_DIR}"
    
    # Deploy Cloud Function with Pub/Sub trigger
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python312 \
        --trigger-topic "${TOPIC_NAME}" \
        --source . \
        --entry-point send_alert_email \
        --memory 256MB \
        --timeout 60s \
        --region "${REGION}" \
        --max-instances 10 \
        --quiet; then
        log_success "Cloud Function ${FUNCTION_NAME} deployed successfully"
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
}

# Function to create notification channel
create_notification_channel() {
    log_info "Creating notification channel..."
    
    # Create notification channel configuration
    cat > /tmp/notification-channel-${RANDOM_SUFFIX}.json << EOF
{
  "type": "pubsub",
  "displayName": "Custom Alert Notifications ${RANDOM_SUFFIX}",
  "description": "Pub/Sub channel for custom email notifications",
  "labels": {
    "topic": "projects/${PROJECT_ID}/topics/${TOPIC_NAME}"
  }
}
EOF
    
    # Create notification channel
    if gcloud alpha monitoring channels create \
        --channel-content-from-file="/tmp/notification-channel-${RANDOM_SUFFIX}.json"; then
        log_success "Notification channel created successfully"
    else
        log_error "Failed to create notification channel"
        exit 1
    fi
    
    # Get channel ID for later use
    CHANNEL_ID=$(gcloud alpha monitoring channels list \
        --filter="displayName:Custom Alert Notifications ${RANDOM_SUFFIX}" \
        --format="value(name)" | head -1)
    export CHANNEL_ID
    
    if [[ -n "${CHANNEL_ID}" ]]; then
        log_info "Notification channel ID: ${CHANNEL_ID}"
    else
        log_error "Failed to retrieve notification channel ID"
        exit 1
    fi
}

# Function to create uptime check
create_uptime_check() {
    log_info "Creating uptime check..."
    
    # Create uptime check configuration
    cat > /tmp/uptime-check-${RANDOM_SUFFIX}.json << EOF
{
  "displayName": "Sample Website Health Check ${RANDOM_SUFFIX}",
  "httpCheck": {
    "requestMethod": "GET",
    "useSsl": true,
    "path": "/",
    "port": 443,
    "validateSsl": true
  },
  "monitoredResource": {
    "type": "uptime_url",
    "labels": {
      "project_id": "${PROJECT_ID}",
      "host": "www.google.com"
    }
  },
  "timeout": "10s",
  "period": "60s",
  "checkerType": "STATIC_IP_CHECKERS"
}
EOF
    
    # Create uptime check
    if gcloud alpha monitoring uptime create \
        --uptime-check-config-from-file="/tmp/uptime-check-${RANDOM_SUFFIX}.json"; then
        log_success "Uptime check created successfully"
    else
        log_error "Failed to create uptime check"
        exit 1
    fi
    
    # Get uptime check ID
    UPTIME_CHECK_ID=$(gcloud alpha monitoring uptime list \
        --filter="displayName:Sample Website Health Check ${RANDOM_SUFFIX}" \
        --format="value(name)" | head -1)
    export UPTIME_CHECK_ID
    
    if [[ -n "${UPTIME_CHECK_ID}" ]]; then
        log_info "Uptime check ID: ${UPTIME_CHECK_ID}"
    else
        log_error "Failed to retrieve uptime check ID"
        exit 1
    fi
}

# Function to create alert policy
create_alert_policy() {
    log_info "Creating alert policy..."
    
    # Create alert policy configuration
    cat > /tmp/alert-policy-${RANDOM_SUFFIX}.json << EOF
{
  "displayName": "Website Uptime Alert ${RANDOM_SUFFIX}",
  "conditions": [
    {
      "displayName": "Uptime check failure",
      "conditionThreshold": {
        "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\"",
        "comparison": "COMPARISON_EQUAL",
        "thresholdValue": 0,
        "duration": "120s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_FRACTION_TRUE",
            "crossSeriesReducer": "REDUCE_MEAN",
            "groupByFields": [
              "resource.label.project_id",
              "resource.label.host"
            ]
          }
        ],
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": [
    "${CHANNEL_ID}"
  ]
}
EOF
    
    # Create alert policy
    if gcloud alpha monitoring policies create \
        --policy-from-file="/tmp/alert-policy-${RANDOM_SUFFIX}.json"; then
        log_success "Alert policy created successfully"
    else
        log_error "Failed to create alert policy"
        exit 1
    fi
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local info_file="/tmp/monitoring-deployment-${RANDOM_SUFFIX}.txt"
    
    cat > "${info_file}" << EOF
# Simple Health Monitoring Deployment Information
# Generated on $(date)

PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
TOPIC_NAME=${TOPIC_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
CHANNEL_ID=${CHANNEL_ID}
UPTIME_CHECK_ID=${UPTIME_CHECK_ID}
FUNCTION_SOURCE_DIR=${FUNCTION_SOURCE_DIR}

# Cleanup command:
# ./destroy.sh
EOF
    
    log_success "Deployment information saved to: ${info_file}"
    log_info "Please save this file for cleanup purposes"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        log_success "✅ Pub/Sub topic is active"
    else
        log_error "❌ Pub/Sub topic validation failed"
    fi
    
    # Check Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        log_success "✅ Cloud Function is deployed"
    else
        log_error "❌ Cloud Function validation failed"
    fi
    
    # Check notification channel
    if [[ -n "${CHANNEL_ID}" ]] && gcloud alpha monitoring channels describe "${CHANNEL_ID}" >/dev/null 2>&1; then
        log_success "✅ Notification channel is configured"
    else
        log_error "❌ Notification channel validation failed"
    fi
    
    # Check uptime check
    if [[ -n "${UPTIME_CHECK_ID}" ]] && gcloud alpha monitoring uptime describe "${UPTIME_CHECK_ID}" >/dev/null 2>&1; then
        log_success "✅ Uptime check is active"
    else
        log_error "❌ Uptime check validation failed"
    fi
    
    log_success "Deployment validation completed"
}

# Function to display next steps
display_next_steps() {
    log_success "🎉 Deployment completed successfully!"
    echo
    log_info "Your monitoring solution is now active with the following components:"
    echo "  • Pub/Sub Topic: ${TOPIC_NAME}"
    echo "  • Cloud Function: ${FUNCTION_NAME}"
    echo "  • Uptime Check: monitoring www.google.com"
    echo "  • Alert Policy: triggers on uptime failures"
    echo
    log_info "Next steps:"
    echo "  1. Customize the uptime check to monitor your application"
    echo "  2. Modify the Cloud Function to send actual email notifications"
    echo "  3. Test the alerting by temporarily blocking the monitored URL"
    echo "  4. Set up additional monitoring for your specific needs"
    echo
    log_info "To test the function manually:"
    echo "  gcloud pubsub messages publish ${TOPIC_NAME} --message='{\"incident\":{\"policy_name\":\"Test Alert\",\"state\":\"OPEN\",\"started_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}}'"
    echo
    log_warning "Remember to run ./destroy.sh when you're done to avoid ongoing charges"
}

# Function to cleanup on error
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    
    # Clean up temporary files
    rm -f /tmp/notification-channel-${RANDOM_SUFFIX}.json
    rm -f /tmp/uptime-check-${RANDOM_SUFFIX}.json
    rm -f /tmp/alert-policy-${RANDOM_SUFFIX}.json
    rm -rf "${FUNCTION_SOURCE_DIR}"
    
    log_info "Partial cleanup completed. You may need to manually remove any created resources."
}

# Trap to handle errors
trap cleanup_on_error ERR

# Main execution
main() {
    log_info "Starting deployment of Simple Application Health Monitoring..."
    echo
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_pubsub_topic
    create_function_source
    deploy_cloud_function
    create_notification_channel
    create_uptime_check
    create_alert_policy
    save_deployment_info
    validate_deployment
    display_next_steps
    
    # Clean up temporary files
    rm -f /tmp/notification-channel-${RANDOM_SUFFIX}.json
    rm -f /tmp/uptime-check-${RANDOM_SUFFIX}.json
    rm -f /tmp/alert-policy-${RANDOM_SUFFIX}.json
    
    log_success "Deployment completed successfully! 🚀"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi