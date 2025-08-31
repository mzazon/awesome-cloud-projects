#!/bin/bash

# Smart Invoice Processing with Document AI and Workflows - Deployment Script
# This script deploys the complete GCP infrastructure for automated invoice processing

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
readonly LOG_FILE="/tmp/gcp-invoice-processing-deploy-$(date +%Y%m%d-%H%M%S).log"

# Default configuration
DRY_RUN=false
SKIP_PREREQUISITES=false
AUTO_APPROVE=false
CLEANUP_ON_FAILURE=true

# Infrastructure configuration
PROJECT_ID=""
REGION="us-central1"
ZONE="us-central1-a"

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo "[$timestamp] $level: $message" >> "$LOG_FILE"
            ;;
    esac
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking deployment prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log "ERROR" "Google Cloud CLI (gcloud) is not installed"
        log "INFO" "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check gcloud version
    local gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null)
    log "INFO" "Google Cloud SDK version: $gcloud_version"
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log "ERROR" "curl is required but not installed"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log "ERROR" "openssl is required but not installed"
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -1 &> /dev/null; then
        log "ERROR" "Not authenticated with Google Cloud"
        log "INFO" "Run: gcloud auth login"
        exit 1
    fi
    
    local active_account=$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -1)
    log "INFO" "Authenticated as: $active_account"
    
    log "SUCCESS" "All prerequisites check passed"
}

# Function to validate and set project configuration
configure_project() {
    log "INFO" "Configuring project settings..."
    
    # Get or create project ID
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID="invoice-processing-$(date +%s)"
        log "INFO" "Generated project ID: $PROJECT_ID"
    fi
    
    # Check if project exists, create if needed
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        if [ "$AUTO_APPROVE" = false ]; then
            echo -n "Project $PROJECT_ID does not exist. Create it? (y/N): "
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                log "ERROR" "Project creation cancelled"
                exit 1
            fi
        fi
        
        log "INFO" "Creating project: $PROJECT_ID"
        if ! gcloud projects create "$PROJECT_ID" 2>> "$LOG_FILE"; then
            log "ERROR" "Failed to create project"
            exit 1
        fi
        
        # Link billing account if available
        local billing_account=$(gcloud billing accounts list --filter="open:true" --format="value(name)" | head -1)
        if [ -n "$billing_account" ]; then
            log "INFO" "Linking billing account: $billing_account"
            gcloud billing projects link "$PROJECT_ID" --billing-account="$billing_account" 2>> "$LOG_FILE"
        else
            log "WARNING" "No billing account found. Manual billing setup may be required"
        fi
    fi
    
    # Set project configuration
    gcloud config set project "$PROJECT_ID" 2>> "$LOG_FILE"
    gcloud config set compute/region "$REGION" 2>> "$LOG_FILE"
    gcloud config set compute/zone "$ZONE" 2>> "$LOG_FILE"
    
    log "SUCCESS" "Project configured: $PROJECT_ID in region $REGION"
}

# Function to enable required APIs
enable_apis() {
    log "INFO" "Enabling required Google Cloud APIs..."
    
    local apis=(
        "documentai.googleapis.com"
        "workflows.googleapis.com"
        "cloudtasks.googleapis.com"
        "gmail.googleapis.com"
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "eventarc.googleapis.com"
        "pubsub.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "INFO" "Enabling API: $api"
        if ! gcloud services enable "$api" 2>> "$LOG_FILE"; then
            log "ERROR" "Failed to enable API: $api"
            exit 1
        fi
    done
    
    # Wait for API propagation
    log "INFO" "Waiting for API propagation (30 seconds)..."
    sleep 30
    
    log "SUCCESS" "All required APIs enabled"
}

# Function to generate unique resource names
generate_resource_names() {
    log "INFO" "Generating unique resource names..."
    
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="invoice-processing-${RANDOM_SUFFIX}"
    export PROCESSOR_NAME="invoice-parser-${RANDOM_SUFFIX}"
    export WORKFLOW_NAME="invoice-workflow-${RANDOM_SUFFIX}"
    export TASK_QUEUE_NAME="approval-queue-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="send-approval-notification-${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT_NAME="invoice-processor-${RANDOM_SUFFIX}"
    
    log "INFO" "Resource names generated with suffix: $RANDOM_SUFFIX"
    log "INFO" "Bucket: $BUCKET_NAME"
    log "INFO" "Processor: $PROCESSOR_NAME"
    log "INFO" "Workflow: $WORKFLOW_NAME"
    log "INFO" "Task Queue: $TASK_QUEUE_NAME"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "INFO" "Creating Cloud Storage bucket: $BUCKET_NAME"
    
    # Create bucket with appropriate settings
    if ! gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME" 2>> "$LOG_FILE"; then
        log "ERROR" "Failed to create storage bucket"
        exit 1
    fi
    
    # Enable versioning for audit trail
    gsutil versioning set on "gs://$BUCKET_NAME" 2>> "$LOG_FILE"
    
    # Create folder structure
    echo "" | gsutil cp - "gs://$BUCKET_NAME/incoming/" 2>> "$LOG_FILE"
    echo "" | gsutil cp - "gs://$BUCKET_NAME/processed/" 2>> "$LOG_FILE"
    echo "" | gsutil cp - "gs://$BUCKET_NAME/failed/" 2>> "$LOG_FILE"
    
    log "SUCCESS" "Storage bucket created with organized folder structure"
}

# Function to create Document AI processor
create_document_ai_processor() {
    log "INFO" "Creating Document AI Invoice Parser processor..."
    
    # Create processor using REST API
    local processor_response
    processor_response=$(curl -s -X POST \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json; charset=utf-8" \
        -d "{
          \"type\": \"INVOICE_PROCESSOR\",
          \"displayName\": \"$PROCESSOR_NAME\"
        }" \
        "https://${REGION}-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/processors" 2>> "$LOG_FILE")
    
    if [ $? -ne 0 ] || [ -z "$processor_response" ]; then
        log "ERROR" "Failed to create Document AI processor"
        exit 1
    fi
    
    # Extract processor ID
    export PROCESSOR_ID=$(echo "$processor_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['name'].split('/')[-1])
except:
    sys.exit(1)
" 2>> "$LOG_FILE")
    
    if [ -z "$PROCESSOR_ID" ]; then
        log "ERROR" "Failed to extract processor ID from response"
        exit 1
    fi
    
    log "SUCCESS" "Document AI processor created: $PROCESSOR_ID"
}

# Function to create service account
create_service_account() {
    log "INFO" "Creating service account for workflow execution..."
    
    # Create service account
    if ! gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
        --display-name="Invoice Processing Service Account" \
        --description="Service account for automated invoice processing" 2>> "$LOG_FILE"; then
        log "ERROR" "Failed to create service account"
        exit 1
    fi
    
    export SERVICE_ACCOUNT="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Grant necessary permissions
    local roles=(
        "roles/documentai.apiUser"
        "roles/storage.objectAdmin"
        "roles/cloudtasks.enqueuer"
        "roles/workflows.invoker"
        "roles/cloudfunctions.invoker"
        "roles/pubsub.publisher"
        "roles/logging.logWriter"
    )
    
    for role in "${roles[@]}"; do
        log "INFO" "Granting role: $role"
        if ! gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$SERVICE_ACCOUNT" \
            --role="$role" 2>> "$LOG_FILE"; then
            log "WARNING" "Failed to grant role: $role"
        fi
    done
    
    log "SUCCESS" "Service account created with appropriate permissions"
}

# Function to create Cloud Tasks queue
create_task_queue() {
    log "INFO" "Creating Cloud Tasks queue: $TASK_QUEUE_NAME"
    
    if ! gcloud tasks queues create "$TASK_QUEUE_NAME" \
        --location="$REGION" \
        --max-dispatches-per-second=10 \
        --max-concurrent-dispatches=5 \
        --max-attempts=3 2>> "$LOG_FILE"; then
        log "ERROR" "Failed to create task queue"
        exit 1
    fi
    
    log "SUCCESS" "Cloud Tasks queue created with retry configuration"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log "INFO" "Deploying Cloud Function for notifications..."
    
    # Create temporary directory for function source
    local temp_dir=$(mktemp -d)
    local function_dir="$temp_dir/notification-function"
    mkdir -p "$function_dir"
    
    # Create function source code
    cat > "$function_dir/main.py" << 'EOF'
import json
import base64
from google.cloud import tasks_v2
from googleapiclient.discovery import build
from google.oauth2 import service_account
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def send_approval_notification(request):
    """Cloud Function to send invoice approval notifications"""
    try:
        # Parse request data
        request_json = request.get_json()
        if not request_json:
            logger.error("No JSON data in request")
            return {'status': 'error', 'message': 'No JSON data provided'}, 400
            
        invoice_data = request_json.get('invoice_data', {})
        approval_amount = float(invoice_data.get('total_amount', 0))
        vendor_name = invoice_data.get('supplier_name', 'Unknown Vendor')
        invoice_number = invoice_data.get('invoice_id', 'N/A')
        
        # Determine approver based on amount
        approver_email = get_approver_email(approval_amount)
        
        # Log notification details
        logger.info(f"Processing approval notification for invoice {invoice_number}")
        logger.info(f"Vendor: {vendor_name}, Amount: ${approval_amount}")
        logger.info(f"Assigned approver: {approver_email}")
        
        # Send notification email (simplified for demo)
        send_email_notification(
            approver_email,
            invoice_data,
            vendor_name,
            invoice_number,
            approval_amount
        )
        
        return {'status': 'success', 'approver': approver_email}
    
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500

def get_approver_email(amount):
    """Determine approver based on invoice amount"""
    if amount < 1000:
        return "manager@company.com"
    elif amount < 5000:
        return "director@company.com"
    else:
        return "cfo@company.com"

def send_email_notification(to_email, invoice_data, vendor, invoice_id, amount):
    """Send email notification (simplified implementation)"""
    subject = f"Invoice Approval Required: {vendor} - ${amount}"
    body = f"""
    Invoice requiring approval:
    
    Vendor: {vendor}
    Invoice ID: {invoice_id}
    Amount: ${amount}
    Due Date: {invoice_data.get('invoice_date', 'N/A')}
    
    Please review and approve in the system.
    """
    
    logger.info(f"Email notification prepared for {to_email}")
    logger.info(f"Subject: {subject}")
    logger.info("Body content prepared successfully")
    
    # In production, implement actual email sending via Gmail API or SendGrid
    return True
EOF

    cat > "$function_dir/requirements.txt" << 'EOF'
google-cloud-tasks==2.16.0
google-auth==2.28.1
google-api-python-client==2.116.0
google-auth-oauthlib==1.2.0
google-auth-httplib2==0.2.0
functions-framework==3.5.0
EOF

    # Deploy the function
    cd "$function_dir"
    if ! gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --memory 256MB \
        --timeout 60s \
        --region "$REGION" \
        --service-account "$SERVICE_ACCOUNT" 2>> "$LOG_FILE"; then
        log "ERROR" "Failed to deploy Cloud Function"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    log "SUCCESS" "Cloud Function deployed successfully"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log "INFO" "Creating Pub/Sub resources for storage events..."
    
    # Create topic
    if ! gcloud pubsub topics create invoice-uploads 2>> "$LOG_FILE"; then
        log "ERROR" "Failed to create Pub/Sub topic"
        exit 1
    fi
    
    # Create subscription
    if ! gcloud pubsub subscriptions create invoice-processing-sub \
        --topic=invoice-uploads 2>> "$LOG_FILE"; then
        log "ERROR" "Failed to create Pub/Sub subscription"
        exit 1
    fi
    
    # Configure storage notification
    if ! gsutil notification create \
        -t invoice-uploads \
        -f json \
        -e OBJECT_FINALIZE \
        "gs://$BUCKET_NAME/incoming/" 2>> "$LOG_FILE"; then
        log "ERROR" "Failed to configure storage notification"
        exit 1
    fi
    
    log "SUCCESS" "Pub/Sub resources created for event handling"
}

# Function to deploy workflow
deploy_workflow() {
    log "INFO" "Deploying Cloud Workflow for invoice processing..."
    
    # Create temporary workflow file
    local temp_workflow="/tmp/invoice-workflow-${RANDOM_SUFFIX}.yaml"
    
    # Generate workflow definition with substituted variables
    cat > "$temp_workflow" << EOF
main:
  params: [event]
  steps:
    - init:
        assign:
          - project_id: "${PROJECT_ID}"
          - location: "${REGION}"
          - processor_id: "${PROCESSOR_ID}"
          - bucket_name: "${BUCKET_NAME}"
          - file_path: \${event.data.name}
          - invoice_data: {}
          - processing_errors: []
    
    - log_start:
        call: sys.log
        args:
          text: \${"Starting invoice processing for file: " + file_path}
          severity: "INFO"
    
    - extract_invoice_data:
        try:
          call: googleapis.documentai.v1.projects.locations.processors.process
          args:
            name: \${"projects/" + project_id + "/locations/" + location + "/processors/" + processor_id}
            body:
              inputDocuments:
                gcsPrefix:
                  gcsUriPrefix: \${"gs://" + bucket_name + "/" + file_path}
              documentOutputConfig:
                gcsOutputConfig:
                  gcsUri: \${"gs://" + bucket_name + "/processed/"}
          result: docai_response
        except:
          as: e
          steps:
            - log_extraction_error:
                call: sys.log
                args:
                  text: \${"Document AI processing failed: " + e.message}
                  severity: "ERROR"
            - move_to_failed:
                call: move_failed_document
                args:
                  source_path: \${file_path}
                  bucket_name: \${bucket_name}
            - return_error:
                return: {"status": "failed", "error": "document_extraction_failed"}
    
    - parse_invoice_fields:
        assign:
          - invoice_data:
              supplier_name: \${default(docai_response.document.entities[0].mentionText, "Unknown")}
              total_amount: \${default(docai_response.document.entities[1].mentionText, "0")}
              invoice_date: \${default(docai_response.document.entities[2].mentionText, "")}
              invoice_id: \${default(docai_response.document.entities[3].mentionText, "")}
              due_date: \${default(docai_response.document.entities[4].mentionText, "")}
    
    - validate_invoice_data:
        switch:
          - condition: \${invoice_data.total_amount == "0" or invoice_data.supplier_name == "Unknown"}
            steps:
              - log_validation_error:
                  call: sys.log
                  args:
                    text: "Invoice validation failed - missing critical data"
                    severity: "WARNING"
              - move_to_failed:
                  call: move_failed_document
                  args:
                    source_path: \${file_path}
                    bucket_name: \${bucket_name}
              - return_validation_error:
                  return: {"status": "failed", "error": "validation_failed"}
    
    - determine_approval_routing:
        assign:
          - amount_float: \${double(invoice_data.total_amount)}
          - approval_level: \${"manager"}
        switch:
          - condition: \${amount_float >= 5000}
            assign:
              - approval_level: "executive"
          - condition: \${amount_float >= 1000}
            assign:
              - approval_level: "director"
    
    - create_approval_task:
        call: googleapis.cloudtasks.v2.projects.locations.queues.tasks.create
        args:
          parent: \${"projects/" + project_id + "/locations/" + location + "/queues/${TASK_QUEUE_NAME}"}
          body:
            task:
              httpRequest:
                httpMethod: "POST"
                url: \${"https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}"}
                headers:
                  Content-Type: "application/json"
                body: \${base64.encode(json.encode({
                  "invoice_data": invoice_data,
                  "approval_level": approval_level,
                  "file_path": file_path
                }))}
              scheduleTime: \${time.format(time.now())}
        result: task_response
    
    - log_completion:
        call: sys.log
        args:
          text: \${"Invoice processing completed successfully for: " + file_path}
          severity: "INFO"
    
    - return_success:
        return:
          status: "success"
          invoice_data: \${invoice_data}
          approval_level: \${approval_level}
          task_id: \${task_response.name}

move_failed_document:
  params: [source_path, bucket_name]
  steps:
    - move_file:
        call: googleapis.storage.v1.objects.copy
        args:
          sourceBucket: \${bucket_name}
          sourceObject: \${source_path}
          destinationBucket: \${bucket_name}
          destinationObject: \${"failed/" + source_path}
    - delete_original:
        call: googleapis.storage.v1.objects.delete
        args:
          bucket: \${bucket_name}
          object: \${source_path}
EOF

    # Deploy workflow
    if ! gcloud workflows deploy "$WORKFLOW_NAME" \
        --source="$temp_workflow" \
        --location="$REGION" \
        --service-account="$SERVICE_ACCOUNT" 2>> "$LOG_FILE"; then
        log "ERROR" "Failed to deploy workflow"
        rm -f "$temp_workflow"
        exit 1
    fi
    
    # Clean up temporary file
    rm -f "$temp_workflow"
    
    log "SUCCESS" "Workflow deployed with error handling and routing logic"
}

# Function to create Eventarc trigger
create_eventarc_trigger() {
    log "INFO" "Creating Eventarc trigger for automatic processing..."
    
    if ! gcloud eventarc triggers create invoice-trigger \
        --location="$REGION" \
        --destination-workflow="$WORKFLOW_NAME" \
        --destination-workflow-location="$REGION" \
        --event-filters="type=google.cloud.pubsub.topic.v1.messagePublished" \
        --event-filters="source=//pubsub.googleapis.com/projects/${PROJECT_ID}/topics/invoice-uploads" \
        --service-account="$SERVICE_ACCOUNT" 2>> "$LOG_FILE"; then
        log "ERROR" "Failed to create Eventarc trigger"
        exit 1
    fi
    
    log "SUCCESS" "Automatic processing trigger configured"
}

# Function to run deployment validation
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    # Check bucket exists
    if ! gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
        log "ERROR" "Storage bucket validation failed"
        return 1
    fi
    
    # Check workflow exists
    if ! gcloud workflows describe "$WORKFLOW_NAME" --location="$REGION" &> /dev/null; then
        log "ERROR" "Workflow validation failed"
        return 1
    fi
    
    # Check function exists
    if ! gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &> /dev/null; then
        log "ERROR" "Cloud Function validation failed"
        return 1
    fi
    
    # Check task queue exists
    if ! gcloud tasks queues describe "$TASK_QUEUE_NAME" --location="$REGION" &> /dev/null; then
        log "ERROR" "Task queue validation failed"
        return 1
    fi
    
    log "SUCCESS" "All components validated successfully"
    return 0
}

# Function to save deployment information
save_deployment_info() {
    log "INFO" "Saving deployment information..."
    
    local deployment_file="$PROJECT_ROOT/deployment-info.json"
    
    cat > "$deployment_file" << EOF
{
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "bucket_name": "$BUCKET_NAME",
  "processor_id": "$PROCESSOR_ID",
  "workflow_name": "$WORKFLOW_NAME",
  "function_name": "$FUNCTION_NAME",
  "task_queue_name": "$TASK_QUEUE_NAME",
  "service_account": "$SERVICE_ACCOUNT",
  "random_suffix": "$RANDOM_SUFFIX"
}
EOF
    
    log "SUCCESS" "Deployment information saved to: $deployment_file"
}

# Function to display deployment summary
display_summary() {
    log "SUCCESS" "🎉 Deployment completed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Storage Bucket: gs://$BUCKET_NAME"
    echo "Document AI Processor: $PROCESSOR_ID"
    echo "Workflow: $WORKFLOW_NAME"
    echo "Cloud Function: $FUNCTION_NAME"
    echo "Task Queue: $TASK_QUEUE_NAME"
    echo "Service Account: $SERVICE_ACCOUNT"
    echo
    echo "=== Next Steps ==="
    echo "1. Upload a PDF invoice to: gs://$BUCKET_NAME/incoming/"
    echo "2. Monitor workflow execution in the Google Cloud Console"
    echo "3. Check Cloud Function logs for notification delivery"
    echo "4. Review processed files in: gs://$BUCKET_NAME/processed/"
    echo
    echo "=== Cleanup ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo
    echo "Log file: $LOG_FILE"
}

# Function to cleanup on failure
cleanup_on_failure() {
    if [ "$CLEANUP_ON_FAILURE" = true ]; then
        log "WARNING" "Deployment failed. Cleaning up resources..."
        bash "$SCRIPT_DIR/destroy.sh" --auto-approve --project-id "$PROJECT_ID" || true
    fi
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy GCP Smart Invoice Processing infrastructure.

OPTIONS:
    --project-id PROJECT_ID     Use specific project ID (default: auto-generated)
    --region REGION             Deploy to specific region (default: us-central1)
    --dry-run                   Show what would be deployed without making changes
    --skip-prerequisites        Skip prerequisite checks
    --auto-approve              Skip interactive prompts
    --no-cleanup-on-failure     Don't cleanup resources if deployment fails
    --help                      Show this help message

EXAMPLES:
    $0                          # Deploy with default settings
    $0 --project-id my-project  # Deploy to specific project
    $0 --dry-run               # Show deployment plan
    $0 --auto-approve          # Deploy without prompts

EOF
}

# Main deployment function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                ZONE="${REGION}-a"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-prerequisites)
                SKIP_PREREQUISITES=true
                shift
                ;;
            --auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            --no-cleanup-on-failure)
                CLEANUP_ON_FAILURE=false
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set trap for cleanup on failure
    trap cleanup_on_failure ERR
    
    # Start deployment
    log "INFO" "Starting GCP Smart Invoice Processing deployment..."
    log "INFO" "Log file: $LOG_FILE"
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN MODE - No resources will be created"
        echo "Would deploy:"
        echo "- Project: ${PROJECT_ID:-auto-generated}"
        echo "- Region: $REGION"
        echo "- Cloud Storage bucket for invoice processing"
        echo "- Document AI Invoice Parser processor"
        echo "- Cloud Workflow for orchestration"
        echo "- Cloud Function for notifications"
        echo "- Cloud Tasks queue for approval management"
        echo "- Pub/Sub topic and subscription"
        echo "- Eventarc trigger for automation"
        echo "- IAM service account with required permissions"
        exit 0
    fi
    
    # Run deployment steps
    if [ "$SKIP_PREREQUISITES" = false ]; then
        check_prerequisites
    fi
    
    configure_project
    enable_apis
    generate_resource_names
    create_storage_bucket
    create_document_ai_processor
    create_service_account
    create_task_queue
    deploy_cloud_function
    create_pubsub_resources
    deploy_workflow
    create_eventarc_trigger
    
    # Validate deployment
    if ! validate_deployment; then
        log "ERROR" "Deployment validation failed"
        exit 1
    fi
    
    # Save deployment information
    save_deployment_info
    
    # Display summary
    display_summary
    
    log "SUCCESS" "Deployment completed successfully"
}

# Run main function
main "$@"