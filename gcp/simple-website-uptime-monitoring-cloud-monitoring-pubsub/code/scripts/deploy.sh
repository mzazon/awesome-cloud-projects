#!/bin/bash
set -euo pipefail

# Simple Website Uptime Monitoring with Cloud Monitoring and Pub/Sub - Deployment Script
# This script deploys the complete uptime monitoring solution on Google Cloud Platform

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
    fi
}

# Function to validate email format
validate_email() {
    local email=$1
    if [[ ! $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid email format: $email"
    fi
}

# Function to generate random suffix
generate_suffix() {
    openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)"
}

# Function to check if API is enabled
check_api_enabled() {
    local api=$1
    local project=$2
    if gcloud services list --project="$project" --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
        return 0
    else
        return 1
    fi
}

# Function to enable API with retry
enable_api() {
    local api=$1
    local project=$2
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Enabling $api API (attempt $attempt/$max_attempts)..."
        if gcloud services enable "$api" --project="$project" 2>/dev/null; then
            success "$api API enabled"
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            error "Failed to enable $api API after $max_attempts attempts"
        fi
        
        warning "Failed to enable $api API, retrying in 10 seconds..."
        sleep 10
        ((attempt++))
    done
}

# Function to wait for API to be fully enabled
wait_for_api() {
    local api=$1
    local project=$2
    local timeout=300  # 5 minutes
    local elapsed=0
    
    log "Waiting for $api API to be fully available..."
    while [ $elapsed -lt $timeout ]; do
        if check_api_enabled "$api" "$project"; then
            success "$api API is ready"
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    error "$api API did not become available within ${timeout}s"
}

# Main deployment function
main() {
    log "Starting deployment of Simple Website Uptime Monitoring solution..."
    
    # Check prerequisites
    log "Checking prerequisites..."
    
    if ! command_exists gcloud; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK first."
    fi
    
    if ! command_exists openssl; then
        warning "openssl not found, using date-based random suffix"
    fi
    
    check_gcloud_auth
    
    # Set default configuration or prompt for input
    if [ -z "${PROJECT_ID:-}" ]; then
        read -p "Enter Google Cloud Project ID (or press Enter to create new): " PROJECT_ID
        if [ -z "$PROJECT_ID" ]; then
            PROJECT_ID="uptime-monitor-$(date +%s)"
            log "Creating new project: $PROJECT_ID"
            if ! gcloud projects create "$PROJECT_ID" 2>/dev/null; then
                error "Failed to create project: $PROJECT_ID"
            fi
        fi
    fi
    
    if [ -z "${REGION:-}" ]; then
        REGION="${REGION:-us-central1}"
    fi
    
    if [ -z "${ZONE:-}" ]; then
        ZONE="${ZONE:-us-central1-a}"
    fi
    
    if [ -z "${NOTIFICATION_EMAIL:-}" ]; then
        read -p "Enter notification email address: " NOTIFICATION_EMAIL
        validate_email "$NOTIFICATION_EMAIL"
    fi
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(generate_suffix)
    TOPIC_NAME="uptime-alerts-${RANDOM_SUFFIX}"
    FUNCTION_NAME="uptime-processor-${RANDOM_SUFFIX}"
    
    # Export variables
    export PROJECT_ID REGION ZONE NOTIFICATION_EMAIL RANDOM_SUFFIX TOPIC_NAME FUNCTION_NAME
    
    log "Configuration:"
    log "  Project ID: $PROJECT_ID"
    log "  Region: $REGION"
    log "  Zone: $ZONE"
    log "  Notification Email: $NOTIFICATION_EMAIL"
    log "  Resource Suffix: $RANDOM_SUFFIX"
    
    # Set gcloud configuration
    log "Configuring gcloud..."
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    # Enable required APIs
    log "Enabling required APIs..."
    REQUIRED_APIS=(
        "monitoring.googleapis.com"
        "pubsub.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${REQUIRED_APIS[@]}"; do
        if ! check_api_enabled "$api" "$PROJECT_ID"; then
            enable_api "$api" "$PROJECT_ID"
            wait_for_api "$api" "$PROJECT_ID"
        else
            success "$api API already enabled"
        fi
    done
    
    # Wait a bit for APIs to propagate
    log "Waiting for APIs to fully propagate..."
    sleep 30
    
    # Step 1: Create Pub/Sub Topic
    log "Creating Pub/Sub topic for alert distribution..."
    if ! gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
        gcloud pubsub topics create "$TOPIC_NAME" --project="$PROJECT_ID"
        success "Pub/Sub topic created: $TOPIC_NAME"
    else
        warning "Pub/Sub topic already exists: $TOPIC_NAME"
    fi
    
    # Step 2: Create Cloud Function source code
    log "Creating Cloud Function source code..."
    FUNCTION_DIR="uptime-function"
    mkdir -p "$FUNCTION_DIR"
    
    cat > "$FUNCTION_DIR/main.py" << 'EOF'
import json
import base64
import os
from datetime import datetime
import functions_framework
from google.cloud import logging

# Initialize Cloud Logging client
logging_client = logging.Client()
logging_client.setup_logging()

@functions_framework.cloud_event
def process_uptime_alert(cloud_event):
    """Process uptime monitoring alerts from Pub/Sub."""
    
    try:
        # Parse the Pub/Sub message
        message_data = cloud_event.data.get("message", {})
        
        # Decode base64 message data
        if "data" in message_data:
            decoded_data = base64.b64decode(message_data["data"]).decode("utf-8")
            alert_data = json.loads(decoded_data)
        else:
            alert_data = {}
        
        # Extract alert information from Cloud Monitoring format
        incident = alert_data.get("incident", {})
        policy_name = incident.get("policy_name", 
                     alert_data.get("policy", {}).get("displayName", "Unknown Policy"))
        condition_name = incident.get("condition_name", 
                        alert_data.get("condition", {}).get("displayName", "Unknown Condition"))
        state = incident.get("state", alert_data.get("state", "UNKNOWN"))
        started_at = incident.get("started_at", 
                    alert_data.get("startedAt", ""))
        url = incident.get("url", 
              alert_data.get("resource", {}).get("labels", {}).get("host", "Unknown URL"))
        
        # Format alert message
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")
        
        if state == "OPEN" or state == "FIRING":
            subject = f"🚨 Website Down Alert: {url}"
            status_emoji = "🚨"
            status_text = "DOWN"
            action_text = "Please investigate immediately"
        else:
            subject = f"✅ Website Restored: {url}"
            status_emoji = "✅"
            status_text = "RESTORED"
            action_text = "Service has been restored"
        
        # Create detailed message body
        message_body = f"""
Website Uptime Alert

{status_emoji} Status: {status_text}
🌐 Website: {url}
📋 Policy: {policy_name}
🔍 Condition: {condition_name}
⏰ Alert Time: {timestamp}
🕐 Started At: {started_at}

{action_text}

This alert was generated by Google Cloud Monitoring.
        """
        
        # Log alert details for debugging
        print(f"Processing alert for {url}: {state}")
        print(f"Subject: {subject}")
        print(f"Message body: {message_body}")
        
        # In production, integrate with your notification system here
        # Examples: send_email(), send_slack_message(), call_pagerduty()
        
        return {"status": "processed", "url": url, "state": state}
        
    except Exception as e:
        print(f"Error processing alert: {str(e)}")
        print(f"Raw cloud event data: {cloud_event.data}")
        return {"status": "error", "error": str(e)}
EOF
    
    cat > "$FUNCTION_DIR/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-logging>=3.8.0
EOF
    
    success "Cloud Function source code created"
    
    # Step 3: Deploy Cloud Function
    log "Deploying Cloud Function with Pub/Sub trigger..."
    gcloud functions deploy "$FUNCTION_NAME" \
        --gen2 \
        --runtime python312 \
        --trigger-topic "$TOPIC_NAME" \
        --source "$FUNCTION_DIR/" \
        --entry-point process_uptime_alert \
        --memory 256Mi \
        --timeout 60s \
        --max-instances 10 \
        --region "$REGION" \
        --project="$PROJECT_ID"
    
    success "Cloud Function deployed: $FUNCTION_NAME"
    
    # Step 4: Create notification channel
    log "Creating Pub/Sub notification channel..."
    
    cat > notification-channel.json << EOF
{
  "type": "pubsub",
  "displayName": "Uptime Alerts Pub/Sub Channel",
  "description": "Delivers uptime monitoring alerts to Pub/Sub topic",
  "labels": {
    "topic": "projects/${PROJECT_ID}/topics/${TOPIC_NAME}"
  }
}
EOF
    
    CHANNEL_ID=$(gcloud alpha monitoring channels create \
        --channel-content-from-file=notification-channel.json \
        --project="$PROJECT_ID" \
        --format="value(name)")
    
    success "Notification channel created: $CHANNEL_ID"
    
    # Step 5: Create uptime checks
    log "Creating uptime checks for websites..."
    
    WEBSITES=(
        "https://www.google.com"
        "https://www.github.com"
        "https://www.stackoverflow.com"
    )
    
    for WEBSITE in "${WEBSITES[@]}"; do
        HOSTNAME=$(echo "$WEBSITE" | sed 's|https\?://||' | sed 's|/.*||')
        CHECK_NAME="uptime-check-${HOSTNAME}-${RANDOM_SUFFIX}"
        
        log "Creating uptime check for: $WEBSITE"
        gcloud monitoring uptime create "$CHECK_NAME" \
            --resource-type=uptime-url \
            --resource-labels="host=${HOSTNAME},project_id=${PROJECT_ID}" \
            --protocol=https \
            --port=443 \
            --path=/ \
            --request-method=get \
            --validate-ssl=true \
            --status-codes=200 \
            --period=60 \
            --timeout=10 \
            --checker-regions=us-central1,europe-west1,asia-east1 \
            --project="$PROJECT_ID"
        
        success "Uptime check created for: $WEBSITE"
    done
    
    # Step 6: Create alerting policy
    log "Creating alerting policy for uptime failures..."
    
    cat > alerting-policy.json << EOF
{
  "displayName": "Website Uptime Alert Policy",
  "documentation": {
    "content": "Alert when websites fail uptime checks from multiple regions",
    "mimeType": "text/markdown"
  },
  "conditions": [
    {
      "displayName": "Uptime check failures",
      "conditionThreshold": {
        "filter": "resource.type=\"uptime_url\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 1,
        "duration": "60s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_NEXT_OLDER",
            "crossSeriesReducer": "REDUCE_COUNT_FALSE",
            "groupByFields": [
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
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": [
    "${CHANNEL_ID}"
  ]
}
EOF
    
    POLICY_ID=$(gcloud alpha monitoring policies create \
        --policy-from-file=alerting-policy.json \
        --project="$PROJECT_ID" \
        --format="value(name)")
    
    success "Alerting policy created: $POLICY_ID"
    
    # Save deployment state
    cat > deployment-state.env << EOF
PROJECT_ID=$PROJECT_ID
REGION=$REGION
ZONE=$ZONE
NOTIFICATION_EMAIL=$NOTIFICATION_EMAIL
RANDOM_SUFFIX=$RANDOM_SUFFIX
TOPIC_NAME=$TOPIC_NAME
FUNCTION_NAME=$FUNCTION_NAME
CHANNEL_ID=$CHANNEL_ID
POLICY_ID=$POLICY_ID
EOF
    
    success "Deployment state saved to deployment-state.env"
    
    # Final validation
    log "Performing final validation..."
    
    # Check uptime checks
    UPTIME_COUNT=$(gcloud monitoring uptime list \
        --project="$PROJECT_ID" \
        --filter="displayName:uptime-check-*-${RANDOM_SUFFIX}" \
        --format="value(displayName)" | wc -l)
    
    if [ "$UPTIME_COUNT" -eq 3 ]; then
        success "All 3 uptime checks created successfully"
    else
        warning "Expected 3 uptime checks, found $UPTIME_COUNT"
    fi
    
    # Check function status
    FUNCTION_STATUS=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$FUNCTION_STATUS" = "ACTIVE" ]; then
        success "Cloud Function is active and ready"
    else
        warning "Cloud Function status: $FUNCTION_STATUS"
    fi
    
    log ""
    success "🎉 Deployment completed successfully!"
    log ""
    log "Resources created:"
    log "  • Pub/Sub Topic: $TOPIC_NAME"
    log "  • Cloud Function: $FUNCTION_NAME"
    log "  • Notification Channel: $CHANNEL_ID"
    log "  • Alerting Policy: $POLICY_ID"
    log "  • Uptime Checks: 3 websites (google.com, github.com, stackoverflow.com)"
    log ""
    log "Next steps:"
    log "  1. Test the monitoring by publishing a test message to the Pub/Sub topic"
    log "  2. View uptime check results in Cloud Monitoring console"
    log "  3. Customize notification channels and alerting policies as needed"
    log ""
    log "To test alert processing:"
    log "  gcloud pubsub topics publish $TOPIC_NAME --message='{\"test\": \"alert\"}'"
    log ""
    log "To clean up resources, run:"
    log "  ./destroy.sh"
}

# Check if running in dry-run mode
if [ "${DRY_RUN:-}" = "true" ]; then
    log "Running in dry-run mode - no resources will be created"
    exit 0
fi

# Run main function
main "$@"