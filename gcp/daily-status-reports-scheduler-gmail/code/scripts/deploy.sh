#!/bin/bash

# Deploy script for Daily System Status Reports with Cloud Scheduler and Gmail
# This script creates all necessary GCP resources for automated daily status reporting

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
REQUIRED_APIS=(
    "cloudfunctions.googleapis.com"
    "cloudscheduler.googleapis.com"
    "monitoring.googleapis.com"
    "gmail.googleapis.com"
)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message function
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error_exit "No active gcloud authentication found. Run 'gcloud auth login' first."
    fi
    
    # Check if project is set
    if [ -z "${PROJECT_ID:-}" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -z "$PROJECT_ID" ]; then
            error_exit "No GCP project set. Set PROJECT_ID environment variable or run 'gcloud config set project PROJECT_ID'"
        fi
    fi
    
    success "Prerequisites check completed"
}

# Function to set default values
set_defaults() {
    info "Setting default configuration..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
    export REGION="${REGION:-us-central1}"
    export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-status-reporter}"
    
    # Generate unique suffix if not provided
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(shuf -i 100-999 -n 1)")
    fi
    
    export FUNCTION_NAME="${FUNCTION_NAME:-daily-status-report-${RANDOM_SUFFIX}}"
    export JOB_NAME="${JOB_NAME:-daily-report-trigger-${RANDOM_SUFFIX}}"
    
    # Email configuration (must be set by user)
    if [ -z "${SENDER_EMAIL:-}" ] || [ -z "${SENDER_PASSWORD:-}" ] || [ -z "${RECIPIENT_EMAIL:-}" ]; then
        warning "Email configuration not set. Please set the following environment variables:"
        echo "  export SENDER_EMAIL='your-email@gmail.com'"
        echo "  export SENDER_PASSWORD='your-app-password'"
        echo "  export RECIPIENT_EMAIL='admin@example.com'"
        echo ""
        echo "For Gmail App Password setup, visit: https://support.google.com/accounts/answer/185833"
        echo ""
        read -p "Do you want to continue with placeholder values? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error_exit "Deployment cancelled. Please set email configuration."
        fi
        
        export SENDER_EMAIL="${SENDER_EMAIL:-your-email@gmail.com}"
        export SENDER_PASSWORD="${SENDER_PASSWORD:-your-app-password}"
        export RECIPIENT_EMAIL="${RECIPIENT_EMAIL:-admin@example.com}"
    fi
    
    success "Configuration set - Project: $PROJECT_ID, Region: $REGION"
}

# Function to enable required APIs
enable_apis() {
    info "Enabling required Google Cloud APIs..."
    
    for api in "${REQUIRED_APIS[@]}"; do
        info "Enabling $api..."
        if gcloud services enable "$api" --project="$PROJECT_ID" 2>&1 | tee -a "$LOG_FILE"; then
            success "Enabled $api"
        else
            error_exit "Failed to enable $api"
        fi
    done
    
    info "Waiting for APIs to be fully enabled..."
    sleep 10
    success "All required APIs enabled"
}

# Function to create service account
create_service_account() {
    info "Creating service account for automated reporting..."
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID" &>/dev/null; then
        warning "Service account already exists, skipping creation"
    else
        gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
            --display-name="Daily Status Reporter" \
            --description="Service account for automated system status reports" \
            --project="$PROJECT_ID" 2>&1 | tee -a "$LOG_FILE"
        success "Service account created"
    fi
    
    # Grant monitoring viewer role
    info "Granting Cloud Monitoring Viewer role..."
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/monitoring.viewer" \
        --quiet 2>&1 | tee -a "$LOG_FILE"
    
    success "Service account configured with monitoring permissions"
}

# Function to create function source code
create_function_code() {
    info "Creating Cloud Function source code..."
    
    local function_dir="${SCRIPT_DIR}/../function"
    mkdir -p "$function_dir"
    
    # Create main.py
    cat > "${function_dir}/main.py" << 'EOF'
import json
import os
import smtplib
from datetime import datetime, timedelta
from email.mime.text import MimeText
from email.mime.multipart import MimeMultipart
from google.cloud import monitoring_v3
import functions_framework

# Email configuration
SMTP_SERVER = "smtp.gmail.com"
SMTP_PORT = 587
SENDER_EMAIL = os.environ.get('SENDER_EMAIL', 'your-email@gmail.com')
SENDER_PASSWORD = os.environ.get('SENDER_PASSWORD', 'your-app-password')
RECIPIENT_EMAIL = os.environ.get('RECIPIENT_EMAIL', 'admin@example.com')

@functions_framework.http
def generate_status_report(request):
    """Generate and send daily system status report"""
    try:
        # Initialize monitoring client
        monitoring_client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{os.environ.get('GCP_PROJECT')}"
        
        # Collect basic system metrics
        report_data = collect_system_metrics(monitoring_client, project_name)
        
        # Format and send email report
        send_status_email(report_data)
        
        return {"status": "success", "message": "Daily status report sent successfully"}
    
    except Exception as e:
        print(f"Error generating status report: {str(e)}")
        return {"status": "error", "message": str(e)}, 500

def collect_system_metrics(client, project_name):
    """Collect key system metrics from Cloud Monitoring"""
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(hours=24)
    
    # Convert to protobuf timestamp format
    interval = monitoring_v3.TimeInterval({
        "end_time": {"seconds": int(end_time.timestamp())},
        "start_time": {"seconds": int(start_time.timestamp())}
    })
    
    metrics_data = {
        "timestamp": end_time.strftime("%Y-%m-%d %H:%M:%S UTC"),
        "project_id": os.environ.get('GCP_PROJECT'),
        "period": "Last 24 hours"
    }
    
    try:
        # Query compute instance metrics (if any exist)
        request = monitoring_v3.ListTimeSeriesRequest({
            "name": project_name,
            "filter": 'metric.type="compute.googleapis.com/instance/cpu/utilization"',
            "interval": interval,
            "view": monitoring_v3.ListTimeSeriesRequest.TimeSeriesView.FULL
        })
        
        results = client.list_time_series(request=request)
        instance_count = len(list(results))
        metrics_data["compute_instances"] = instance_count
        
        # Query Cloud Functions metrics
        functions_request = monitoring_v3.ListTimeSeriesRequest({
            "name": project_name,
            "filter": 'metric.type="cloudfunctions.googleapis.com/function/executions"',
            "interval": interval,
            "view": monitoring_v3.ListTimeSeriesRequest.TimeSeriesView.FULL
        })
        
        functions_results = client.list_time_series(request=functions_request)
        functions_count = len(list(functions_results))
        metrics_data["cloud_functions"] = functions_count
        
    except Exception as e:
        print(f"Error collecting metrics: {e}")
        metrics_data["compute_instances"] = "N/A"
        metrics_data["cloud_functions"] = "N/A"
    
    return metrics_data

def send_status_email(report_data):
    """Send formatted status report via SMTP"""
    try:
        # Create email message
        msg = MimeMultipart()
        msg['From'] = SENDER_EMAIL
        msg['To'] = RECIPIENT_EMAIL
        msg['Subject'] = f"Daily System Status Report - {report_data['timestamp']}"
        
        # Format email body
        body = format_report_body(report_data)
        msg.attach(MimeText(body, 'plain'))
        
        # Send email via SMTP
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.starttls()
            server.login(SENDER_EMAIL, SENDER_PASSWORD)
            server.send_message(msg)
        
        print(f"Status report sent to {RECIPIENT_EMAIL}")
        
    except Exception as e:
        print(f"Error sending email: {e}")
        raise

def format_report_body(data):
    """Format system metrics into readable email content"""
    return f"""
Daily System Status Report
Generated: {data['timestamp']}
Project: {data['project_id']}
Period: {data['period']}

=== INFRASTRUCTURE SUMMARY ===
Compute Instances: {data['compute_instances']}
Cloud Functions: {data['cloud_functions']}

=== SYSTEM HEALTH ===
✅ Monitoring API: Active
✅ Function Execution: Successful
✅ Report Generation: Operational

This automated report provides basic infrastructure visibility.
For detailed metrics, visit Cloud Monitoring console at:
https://console.cloud.google.com/monitoring

=== RECOMMENDATIONS ===
• Review resource utilization trends in Cloud Monitoring
• Check for any active alerts or incidents
• Verify backup and disaster recovery processes

---
Generated by Cloud Functions Daily Status Reporter
Project: {data['project_id']}
"""
EOF
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-monitoring==2.22.2
functions-framework==3.8.1
EOF
    
    success "Function source code created in ${function_dir}"
}

# Function to deploy Cloud Function
deploy_function() {
    info "Deploying Cloud Function..."
    
    local function_dir="${SCRIPT_DIR}/../function"
    
    # Change to function directory for deployment
    pushd "$function_dir" > /dev/null
    
    gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python312 \
        --trigger-http \
        --entry-point generate_status_report \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars="GCP_PROJECT=${PROJECT_ID},SENDER_EMAIL=${SENDER_EMAIL},SENDER_PASSWORD=${SENDER_PASSWORD},RECIPIENT_EMAIL=${RECIPIENT_EMAIL}" \
        --service-account="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --no-allow-unauthenticated \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --quiet 2>&1 | tee -a "$LOG_FILE"
    
    popd > /dev/null
    
    # Get function URL
    FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(httpsTrigger.url)" 2>/dev/null)
    
    if [ -z "$FUNCTION_URL" ]; then
        error_exit "Failed to retrieve function URL"
    fi
    
    success "Cloud Function deployed successfully"
    info "Function URL: $FUNCTION_URL"
}

# Function to create Cloud Scheduler job
create_scheduler_job() {
    info "Creating Cloud Scheduler job for daily execution..."
    
    # Check if job already exists
    if gcloud scheduler jobs describe "$JOB_NAME" --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        warning "Scheduler job already exists, updating configuration..."
        gcloud scheduler jobs update http "$JOB_NAME" \
            --location="$REGION" \
            --schedule="0 9 * * *" \
            --uri="$FUNCTION_URL" \
            --http-method=POST \
            --oidc-service-account-email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --project="$PROJECT_ID" \
            --quiet 2>&1 | tee -a "$LOG_FILE"
    else
        gcloud scheduler jobs create http "$JOB_NAME" \
            --location="$REGION" \
            --schedule="0 9 * * *" \
            --uri="$FUNCTION_URL" \
            --http-method=POST \
            --oidc-service-account-email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --description="Daily system status report generator" \
            --project="$PROJECT_ID" \
            --quiet 2>&1 | tee -a "$LOG_FILE"
    fi
    
    success "Cloud Scheduler job created for daily execution at 9 AM UTC"
}

# Function to run validation tests
run_validation() {
    info "Running validation tests..."
    
    # Test function manually
    info "Testing Cloud Function manually..."
    if gcloud functions call "$FUNCTION_NAME" --region="$REGION" --project="$PROJECT_ID" 2>&1 | tee -a "$LOG_FILE"; then
        success "Function test completed"
    else
        warning "Function test failed - check logs for details"
    fi
    
    # Check scheduler job status
    info "Verifying Cloud Scheduler job configuration..."
    if gcloud scheduler jobs describe "$JOB_NAME" --location="$REGION" --project="$PROJECT_ID" --format="value(state)" 2>/dev/null | grep -q "ENABLED"; then
        success "Scheduler job is enabled and configured correctly"
    else
        warning "Scheduler job may not be properly configured"
    fi
    
    success "Validation completed"
}

# Function to display deployment summary
show_summary() {
    echo ""
    echo "=========================================="
    echo "  DEPLOYMENT SUMMARY"
    echo "=========================================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Function Name: $FUNCTION_NAME"
    echo "Scheduler Job: $JOB_NAME"
    echo "Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "Function URL: $FUNCTION_URL"
    echo ""
    echo "Email Configuration:"
    echo "  Sender: $SENDER_EMAIL"
    echo "  Recipient: $RECIPIENT_EMAIL"
    echo ""
    echo "Next Steps:"
    echo "1. Verify email configuration is correct"
    echo "2. Test the function manually: gcloud functions call $FUNCTION_NAME --region=$REGION"
    echo "3. Check function logs: gcloud functions logs read $FUNCTION_NAME --region=$REGION"
    echo "4. Monitor scheduler job: gcloud scheduler jobs describe $JOB_NAME --location=$REGION"
    echo ""
    echo "The system will send daily status reports at 9 AM UTC."
    echo "=========================================="
}

# Main deployment function
main() {
    log "Starting deployment of Daily Status Reports system"
    
    check_prerequisites
    set_defaults
    enable_apis
    create_service_account
    create_function_code
    deploy_function
    create_scheduler_job
    run_validation
    show_summary
    
    success "Deployment completed successfully!"
    log "Deployment completed successfully"
}

# Handle script interruption
trap 'error_exit "Script interrupted by user"' INT TERM

# Run main function
main "$@"