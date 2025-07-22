#!/bin/bash

# Infrastructure Anomaly Detection with Cloud Monitoring and Gemini - Deployment Script
# This script deploys the complete infrastructure for AI-powered anomaly detection

set -e  # Exit on any error
set -o pipefail  # Exit on any pipe failure

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if curl is available for external dependencies
    if ! command_exists curl; then
        log_error "curl is required but not installed."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command_exists openssl; then
        log_error "openssl is required but not installed."
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set project ID (try to get from current config if not set)
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [ -z "$PROJECT_ID" ]; then
            log_error "PROJECT_ID not set and cannot detect from gcloud config. Please set PROJECT_ID environment variable."
            exit 1
        fi
    fi
    
    # Set default values if not provided
    export PROJECT_ID=${PROJECT_ID}
    export REGION=${REGION:-"us-central1"}
    export ZONE=${ZONE:-"us-central1-a"}
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export FUNCTION_NAME="anomaly-detector-${RANDOM_SUFFIX}"
    export TOPIC_NAME="monitoring-events-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_NAME="anomaly-analysis-${RANDOM_SUFFIX}"
    export INSTANCE_NAME="test-instance-${RANDOM_SUFFIX}"
    
    log_info "Using PROJECT_ID: $PROJECT_ID"
    log_info "Using REGION: $REGION"
    log_info "Using ZONE: $ZONE"
    log_info "Resource suffix: $RANDOM_SUFFIX"
    
    # Set gcloud defaults
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "Environment setup completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "monitoring.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "cloudbuild.googleapis.com"
        "compute.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" --quiet
    done
    
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs have been enabled"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topic and subscription..."
    
    # Create Pub/Sub topic
    if ! gcloud pubsub topics describe "$TOPIC_NAME" >/dev/null 2>&1; then
        gcloud pubsub topics create "$TOPIC_NAME"
        log_success "Pub/Sub topic '$TOPIC_NAME' created"
    else
        log_warning "Pub/Sub topic '$TOPIC_NAME' already exists"
    fi
    
    # Create subscription
    if ! gcloud pubsub subscriptions describe "$SUBSCRIPTION_NAME" >/dev/null 2>&1; then
        gcloud pubsub subscriptions create "$SUBSCRIPTION_NAME" \
            --topic="$TOPIC_NAME" \
            --ack-deadline=600
        log_success "Pub/Sub subscription '$SUBSCRIPTION_NAME' created"
    else
        log_warning "Pub/Sub subscription '$SUBSCRIPTION_NAME' already exists"
    fi
}

# Function to deploy test infrastructure
deploy_test_infrastructure() {
    log_info "Deploying test compute infrastructure..."
    
    # Create VM instance if it doesn't exist
    if ! gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" >/dev/null 2>&1; then
        gcloud compute instances create "$INSTANCE_NAME" \
            --zone="$ZONE" \
            --machine-type=e2-medium \
            --image-family=ubuntu-2004-lts \
            --image-project=ubuntu-os-cloud \
            --metadata=enable-oslogin=true \
            --tags=monitoring-test \
            --scopes=https://www.googleapis.com/auth/cloud-platform
        
        log_success "Test VM instance '$INSTANCE_NAME' created"
        
        # Wait for instance to be ready
        log_info "Waiting for instance to be ready..."
        sleep 60
        
        # Install Ops Agent
        log_info "Installing Ops Agent on test instance..."
        gcloud compute ssh "$INSTANCE_NAME" \
            --zone="$ZONE" \
            --command="curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh && sudo bash add-google-cloud-ops-agent-repo.sh --also-install" \
            --ssh-flag="-o StrictHostKeyChecking=no" \
            --quiet || log_warning "Ops Agent installation may have failed - continuing anyway"
        
        log_success "Test infrastructure deployed"
    else
        log_warning "Test VM instance '$INSTANCE_NAME' already exists"
    fi
}

# Function to create and deploy Cloud Function
deploy_cloud_function() {
    log_info "Creating and deploying Cloud Function..."
    
    # Create temporary directory for function source
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Create main.py
    cat > main.py << 'EOF'
import functions_framework
import json
import base64
from google.cloud import aiplatform
from google.cloud import monitoring_v3
from datetime import datetime, timedelta
import logging
import os

# Initialize Vertex AI
PROJECT_ID = os.environ.get('GCP_PROJECT')
REGION = 'us-central1'
aiplatform.init(project=PROJECT_ID, location=REGION)

@functions_framework.cloud_event
def analyze_anomaly(cloud_event):
    """Analyze monitoring data for anomalies using Gemini AI"""
    
    try:
        # Decode Pub/Sub message
        message_data = base64.b64decode(cloud_event.data["message"]["data"]).decode()
        monitoring_data = json.loads(message_data)
        
        # Extract metric information
        metric_name = monitoring_data.get('metric_name', 'unknown')
        metric_value = monitoring_data.get('value', 0)
        resource_name = monitoring_data.get('resource', 'unknown')
        timestamp = monitoring_data.get('timestamp', datetime.now().isoformat())
        
        # Get historical data for context
        historical_context = get_historical_metrics(metric_name, resource_name)
        
        # Prepare prompt for Gemini analysis
        analysis_prompt = f"""
        Analyze this infrastructure monitoring data for anomalies:
        
        Current Metric: {metric_name}
        Current Value: {metric_value}
        Resource: {resource_name}
        Timestamp: {timestamp}
        
        Historical Context: {historical_context}
        
        Please analyze if this represents an anomaly and provide:
        1. Anomaly probability (0-100%)
        2. Severity level (Low/Medium/High/Critical)
        3. Potential root causes
        4. Recommended actions
        5. Business impact assessment
        
        Respond in JSON format.
        """
        
        # Call Gemini for analysis
        from vertexai.generative_models import GenerativeModel
        model = GenerativeModel("gemini-2.0-flash-exp")
        
        response = model.generate_content(analysis_prompt)
        analysis_result = response.text
        
        # Log analysis for monitoring
        logging.info(f"Anomaly analysis completed for {metric_name}: {analysis_result}")
        
        # Parse AI response and trigger alerts if needed
        try:
            ai_analysis = json.loads(analysis_result)
            anomaly_probability = ai_analysis.get('anomaly_probability', 0)
            
            if anomaly_probability > 70:  # High confidence anomaly
                send_alert(ai_analysis, monitoring_data)
                
        except json.JSONDecodeError:
            logging.warning("Could not parse AI response as JSON")
        
        return {"status": "success", "analysis": analysis_result}
        
    except Exception as e:
        logging.error(f"Error in anomaly analysis: {str(e)}")
        return {"status": "error", "message": str(e)}

def get_historical_metrics(metric_name, resource_name):
    """Retrieve historical metric data for context"""
    client = monitoring_v3.MetricServiceClient()
    project_name = f"projects/{PROJECT_ID}"
    
    # Define time range (last 24 hours)
    end_time = datetime.now()
    start_time = end_time - timedelta(hours=24)
    
    # This is a simplified example - in production, implement proper metric querying
    return f"Historical data for {metric_name} on {resource_name} over last 24 hours"

def send_alert(ai_analysis, monitoring_data):
    """Send alert based on AI analysis"""
    severity = ai_analysis.get('severity', 'Medium')
    
    alert_message = {
        "severity": severity,
        "metric": monitoring_data.get('metric_name'),
        "resource": monitoring_data.get('resource'),
        "ai_analysis": ai_analysis,
        "timestamp": datetime.now().isoformat()
    }
    
    logging.info(f"ALERT: {severity} anomaly detected - {alert_message}")
    # In production, integrate with notification systems
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.*
google-cloud-aiplatform==1.70.0
google-cloud-monitoring==2.22.0
google-cloud-pubsub==2.25.0
vertexai==1.70.0
EOF
    
    # Deploy Cloud Function
    log_info "Deploying Cloud Function '$FUNCTION_NAME'..."
    gcloud functions deploy "$FUNCTION_NAME" \
        --gen2 \
        --runtime=python311 \
        --region="$REGION" \
        --source=. \
        --entry-point=analyze_anomaly \
        --trigger-topic="$TOPIC_NAME" \
        --memory=1Gi \
        --timeout=540s \
        --max-instances=10 \
        --set-env-vars="GCP_PROJECT=$PROJECT_ID" \
        --service-account="$PROJECT_ID@appspot.gserviceaccount.com" \
        --quiet
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    log_success "Cloud Function '$FUNCTION_NAME' deployed successfully"
}

# Function to set up IAM permissions
setup_iam_permissions() {
    log_info "Setting up IAM permissions..."
    
    # Grant necessary IAM permissions for AI Platform access
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$PROJECT_ID@appspot.gserviceaccount.com" \
        --role="roles/aiplatform.user" \
        --quiet
    
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$PROJECT_ID@appspot.gserviceaccount.com" \
        --role="roles/monitoring.viewer" \
        --quiet
    
    log_success "IAM permissions configured"
}

# Function to create monitoring policies
create_monitoring_policies() {
    log_info "Creating monitoring alert policies..."
    
    # Create temporary file for alert policy
    local temp_policy=$(mktemp)
    cat > "$temp_policy" << EOF
{
  "displayName": "AI-Powered CPU Anomaly Detection",
  "conditions": [
    {
      "displayName": "CPU utilization anomaly",
      "conditionThreshold": {
        "filter": "resource.type=\"gce_instance\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0.8,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ]
      }
    }
  ],
  "enabled": true,
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF
    
    # Create alert policy
    gcloud alpha monitoring policies create --policy-from-file="$temp_policy" --quiet || log_warning "Alert policy creation failed - may already exist"
    
    # Create custom metric for anomaly scores
    gcloud logging metrics create anomaly_score \
        --description="AI-generated anomaly detection scores" \
        --log-filter='resource.type="cloud_function" AND textPayload:"ALERT:"' \
        --quiet || log_warning "Custom metric creation failed - may already exist"
    
    # Clean up temporary file
    rm -f "$temp_policy"
    
    log_success "Monitoring policies created"
}

# Function to create notification channels
create_notification_channels() {
    log_info "Creating notification channels..."
    
    # Create temporary file for notification channel
    local temp_channel=$(mktemp)
    cat > "$temp_channel" << EOF
{
  "type": "email",
  "displayName": "AI Anomaly Alerts",
  "description": "Email notifications for AI-detected infrastructure anomalies",
  "labels": {
    "email_address": "admin@example.com"
  },
  "enabled": true
}
EOF
    
    # Create notification channel
    local notification_channel
    notification_channel=$(gcloud alpha monitoring channels create \
        --channel-content-from-file="$temp_channel" \
        --format="value(name)" \
        --quiet) || log_warning "Notification channel creation failed - may already exist"
    
    # Clean up temporary file
    rm -f "$temp_channel"
    
    log_success "Notification channels created"
}

# Function to create dashboard
create_dashboard() {
    log_info "Creating monitoring dashboard..."
    
    # Create temporary file for dashboard
    local temp_dashboard=$(mktemp)
    cat > "$temp_dashboard" << EOF
{
  "displayName": "AI-Powered Infrastructure Anomaly Detection",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Anomaly Detection Scores",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_function\" AND metric.type=\"logging.googleapis.com/user/anomaly_score\""
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
EOF
    
    # Create dashboard
    gcloud monitoring dashboards create --config-from-file="$temp_dashboard" --quiet || log_warning "Dashboard creation failed - may already exist"
    
    # Clean up temporary file
    rm -f "$temp_dashboard"
    
    log_success "Dashboard created"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing deployment with synthetic load..."
    
    # Generate CPU load to trigger anomaly detection
    gcloud compute ssh "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --command="nohup stress --cpu 4 --timeout 300s > /dev/null 2>&1 &" \
        --ssh-flag="-o StrictHostKeyChecking=no" \
        --quiet || log_warning "Stress test failed - continuing anyway"
    
    # Create test message
    local test_message=$(mktemp)
    cat > "$test_message" << EOF
{
  "metric_name": "compute.googleapis.com/instance/cpu/utilization",
  "value": 0.95,
  "resource": "$INSTANCE_NAME",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "alert_context": "Synthetic load test for anomaly detection validation"
}
EOF
    
    # Send test message to Pub/Sub
    gcloud pubsub topics publish "$TOPIC_NAME" \
        --message="$(cat "$test_message")" \
        --quiet
    
    # Clean up temporary file
    rm -f "$test_message"
    
    log_success "Test deployment completed"
    log_info "Monitor function logs with: gcloud functions logs read $FUNCTION_NAME --region=$REGION"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "=========================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo "=========================="
    echo "Resources Created:"
    echo "- Pub/Sub Topic: $TOPIC_NAME"
    echo "- Pub/Sub Subscription: $SUBSCRIPTION_NAME"
    echo "- Cloud Function: $FUNCTION_NAME"
    echo "- Test VM Instance: $INSTANCE_NAME"
    echo "- Monitoring Policies: AI-Powered CPU Anomaly Detection"
    echo "- Custom Metrics: anomaly_score"
    echo "- Dashboard: AI-Powered Infrastructure Anomaly Detection"
    echo "=========================="
    echo "Access URLs:"
    echo "- Cloud Console: https://console.cloud.google.com/functions/details/$REGION/$FUNCTION_NAME?project=$PROJECT_ID"
    echo "- Monitoring Dashboard: https://console.cloud.google.com/monitoring/dashboards"
    echo "- Pub/Sub Console: https://console.cloud.google.com/cloudpubsub/topic/detail/$TOPIC_NAME?project=$PROJECT_ID"
    echo "=========================="
    
    log_success "Infrastructure Anomaly Detection deployment completed successfully!"
}

# Main execution
main() {
    log_info "Starting Infrastructure Anomaly Detection deployment..."
    
    validate_prerequisites
    setup_environment
    enable_apis
    create_pubsub_resources
    deploy_test_infrastructure
    deploy_cloud_function
    setup_iam_permissions
    create_monitoring_policies
    create_notification_channels
    create_dashboard
    test_deployment
    display_summary
    
    log_success "All deployment steps completed successfully!"
}

# Execute main function
main "$@"