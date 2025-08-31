#!/bin/bash

# Smart Invoice Processing with Document AI and Workflows - Cleanup Script
# This script safely removes all GCP infrastructure created by the deployment script

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
readonly LOG_FILE="/tmp/gcp-invoice-processing-destroy-$(date +%Y%m%d-%H%M%S).log"

# Default configuration
DRY_RUN=false
AUTO_APPROVE=false
SKIP_CONFIRMATION=false
DELETE_PROJECT=false

# Infrastructure configuration
PROJECT_ID=""
REGION="us-central1"

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
    log "INFO" "Checking cleanup prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log "ERROR" "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log "ERROR" "gsutil is required but not installed"
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
    
    log "SUCCESS" "Prerequisites check passed"
}

# Function to load deployment information
load_deployment_info() {
    log "INFO" "Loading deployment information..."
    
    local deployment_file="$PROJECT_ROOT/deployment-info.json"
    
    if [ -f "$deployment_file" ]; then
        log "INFO" "Found deployment info file: $deployment_file"
        
        # Extract deployment information using python
        if command -v python3 &> /dev/null; then
            eval $(python3 -c "
import json
import sys
try:
    with open('$deployment_file', 'r') as f:
        data = json.load(f)
    for key, value in data.items():
        print(f'export {key.upper()}=\"{value}\"')
except Exception as e:
    sys.exit(1)
" 2>> "$LOG_FILE")
            
            # Set variables from deployment info
            PROJECT_ID="${PROJECT_ID:-$PROJECT_ID}"
            REGION="${REGION:-$REGION}"
            BUCKET_NAME="${BUCKET_NAME}"
            PROCESSOR_ID="${PROCESSOR_ID}"
            WORKFLOW_NAME="${WORKFLOW_NAME}"
            FUNCTION_NAME="${FUNCTION_NAME}"
            TASK_QUEUE_NAME="${TASK_QUEUE_NAME}"
            SERVICE_ACCOUNT="${SERVICE_ACCOUNT}"
            RANDOM_SUFFIX="${RANDOM_SUFFIX}"
            
            log "SUCCESS" "Deployment information loaded"
        else
            log "WARNING" "Python3 not found, deployment info cannot be parsed automatically"
        fi
    else
        log "WARNING" "No deployment info file found. Resource names must be provided manually."
    fi
}

# Function to discover resources if deployment info is missing
discover_resources() {
    if [ -z "$PROJECT_ID" ]; then
        log "ERROR" "Project ID must be specified with --project-id"
        exit 1
    fi
    
    log "INFO" "Discovering resources in project: $PROJECT_ID"
    
    # Set project context
    gcloud config set project "$PROJECT_ID" 2>> "$LOG_FILE"
    
    # Discover buckets with invoice processing pattern
    local buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "invoice-processing" || true)
    if [ -n "$buckets" ]; then
        BUCKET_NAME=$(echo "$buckets" | head -1 | sed 's|gs://||' | sed 's|/||')
        log "INFO" "Found bucket: $BUCKET_NAME"
    fi
    
    # Discover workflows
    local workflows=$(gcloud workflows list --filter="name~invoice-workflow" --format="value(name)" 2>/dev/null || true)
    if [ -n "$workflows" ]; then
        WORKFLOW_NAME=$(basename "$workflows" | head -1)
        log "INFO" "Found workflow: $WORKFLOW_NAME"
    fi
    
    # Discover functions
    local functions=$(gcloud functions list --filter="name~approval-notification" --format="value(name)" 2>/dev/null || true)
    if [ -n "$functions" ]; then
        FUNCTION_NAME=$(basename "$functions" | head -1)
        log "INFO" "Found function: $FUNCTION_NAME"
    fi
    
    # Discover task queues
    local queues=$(gcloud tasks queues list --filter="name~approval-queue" --format="value(name)" 2>/dev/null || true)
    if [ -n "$queues" ]; then
        TASK_QUEUE_NAME=$(basename "$queues" | head -1)
        log "INFO" "Found task queue: $TASK_QUEUE_NAME"
    fi
    
    # Discover service accounts
    local accounts=$(gcloud iam service-accounts list --filter="email~invoice-processor" --format="value(email)" 2>/dev/null || true)
    if [ -n "$accounts" ]; then
        SERVICE_ACCOUNT=$(echo "$accounts" | head -1)
        log "INFO" "Found service account: $SERVICE_ACCOUNT"
    fi
}

# Function to confirm destructive actions
confirm_destruction() {
    if [ "$SKIP_CONFIRMATION" = true ] || [ "$AUTO_APPROVE" = true ]; then
        return 0
    fi
    
    echo
    echo -e "${RED}WARNING: This will delete the following resources:${NC}"
    echo "Project: $PROJECT_ID"
    [ -n "$BUCKET_NAME" ] && echo "Storage Bucket: $BUCKET_NAME (and all contents)"
    [ -n "$WORKFLOW_NAME" ] && echo "Workflow: $WORKFLOW_NAME"
    [ -n "$FUNCTION_NAME" ] && echo "Cloud Function: $FUNCTION_NAME"
    [ -n "$TASK_QUEUE_NAME" ] && echo "Task Queue: $TASK_QUEUE_NAME"
    [ -n "$SERVICE_ACCOUNT" ] && echo "Service Account: $SERVICE_ACCOUNT"
    [ -n "$PROCESSOR_ID" ] && echo "Document AI Processor: $PROCESSOR_ID"
    echo "Pub/Sub topics and subscriptions"
    echo "Eventarc triggers"
    echo
    
    if [ "$DELETE_PROJECT" = true ]; then
        echo -e "${RED}DANGER: The entire project will be deleted!${NC}"
        echo
    fi
    
    echo -n "Are you sure you want to proceed? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log "INFO" "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to delete Eventarc trigger
delete_eventarc_trigger() {
    log "INFO" "Deleting Eventarc trigger..."
    
    local triggers=$(gcloud eventarc triggers list --location="$REGION" --filter="name~invoice-trigger" --format="value(name)" 2>/dev/null || true)
    
    for trigger in $triggers; do
        local trigger_name=$(basename "$trigger")
        log "INFO" "Deleting trigger: $trigger_name"
        if ! gcloud eventarc triggers delete "$trigger_name" \
            --location="$REGION" \
            --quiet 2>> "$LOG_FILE"; then
            log "WARNING" "Failed to delete trigger: $trigger_name"
        else
            log "SUCCESS" "Trigger deleted: $trigger_name"
        fi
    done
}

# Function to delete Cloud Workflow
delete_workflow() {
    if [ -z "$WORKFLOW_NAME" ]; then
        log "INFO" "No workflow name specified, skipping"
        return 0
    fi
    
    log "INFO" "Deleting Cloud Workflow: $WORKFLOW_NAME"
    
    if ! gcloud workflows delete "$WORKFLOW_NAME" \
        --location="$REGION" \
        --quiet 2>> "$LOG_FILE"; then
        log "WARNING" "Failed to delete workflow: $WORKFLOW_NAME"
    else
        log "SUCCESS" "Workflow deleted: $WORKFLOW_NAME"
    fi
}

# Function to delete Cloud Function
delete_cloud_function() {
    if [ -z "$FUNCTION_NAME" ]; then
        log "INFO" "No function name specified, skipping"
        return 0
    fi
    
    log "INFO" "Deleting Cloud Function: $FUNCTION_NAME"
    
    if ! gcloud functions delete "$FUNCTION_NAME" \
        --region="$REGION" \
        --quiet 2>> "$LOG_FILE"; then
        log "WARNING" "Failed to delete function: $FUNCTION_NAME"
    else
        log "SUCCESS" "Function deleted: $FUNCTION_NAME"
    fi
}

# Function to delete Cloud Tasks queue
delete_task_queue() {
    if [ -z "$TASK_QUEUE_NAME" ]; then
        log "INFO" "No task queue name specified, skipping"
        return 0
    fi
    
    log "INFO" "Deleting Cloud Tasks queue: $TASK_QUEUE_NAME"
    
    # First, purge all tasks
    if gcloud tasks queues describe "$TASK_QUEUE_NAME" --location="$REGION" &> /dev/null; then
        log "INFO" "Purging tasks from queue..."
        gcloud tasks queues purge "$TASK_QUEUE_NAME" \
            --location="$REGION" \
            --quiet 2>> "$LOG_FILE" || true
        
        # Wait a moment for purge to complete
        sleep 5
        
        # Delete the queue
        if ! gcloud tasks queues delete "$TASK_QUEUE_NAME" \
            --location="$REGION" \
            --quiet 2>> "$LOG_FILE"; then
            log "WARNING" "Failed to delete task queue: $TASK_QUEUE_NAME"
        else
            log "SUCCESS" "Task queue deleted: $TASK_QUEUE_NAME"
        fi
    else
        log "INFO" "Task queue not found: $TASK_QUEUE_NAME"
    fi
}

# Function to delete Document AI processor
delete_document_ai_processor() {
    if [ -z "$PROCESSOR_ID" ]; then
        log "INFO" "No processor ID specified, skipping"
        return 0
    fi
    
    log "INFO" "Deleting Document AI processor: $PROCESSOR_ID"
    
    # Delete using REST API
    local response_code=$(curl -s -w "%{http_code}" -o /dev/null -X DELETE \
        -H "Authorization: Bearer $(gcloud auth print-access-token 2>/dev/null)" \
        "https://${REGION}-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/processors/${PROCESSOR_ID}" 2>> "$LOG_FILE")
    
    if [ "$response_code" = "200" ] || [ "$response_code" = "204" ]; then
        log "SUCCESS" "Document AI processor deleted: $PROCESSOR_ID"
    elif [ "$response_code" = "404" ]; then
        log "INFO" "Document AI processor not found: $PROCESSOR_ID"
    else
        log "WARNING" "Failed to delete Document AI processor: $PROCESSOR_ID (HTTP $response_code)"
    fi
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    if [ -z "$BUCKET_NAME" ]; then
        log "INFO" "No bucket name specified, skipping"
        return 0
    fi
    
    log "INFO" "Deleting Cloud Storage bucket: $BUCKET_NAME"
    
    # Check if bucket exists
    if gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
        # Remove all objects including versions
        log "INFO" "Removing all objects from bucket..."
        if ! gsutil -m rm -r "gs://$BUCKET_NAME/**" 2>> "$LOG_FILE"; then
            log "WARNING" "Some objects may not have been deleted"
        fi
        
        # Remove bucket
        if ! gsutil rb "gs://$BUCKET_NAME" 2>> "$LOG_FILE"; then
            log "WARNING" "Failed to delete bucket: $BUCKET_NAME"
        else
            log "SUCCESS" "Storage bucket deleted: $BUCKET_NAME"
        fi
    else
        log "INFO" "Storage bucket not found: $BUCKET_NAME"
    fi
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log "INFO" "Deleting Pub/Sub resources..."
    
    # Delete subscription
    if gcloud pubsub subscriptions describe invoice-processing-sub &> /dev/null; then
        if ! gcloud pubsub subscriptions delete invoice-processing-sub --quiet 2>> "$LOG_FILE"; then
            log "WARNING" "Failed to delete Pub/Sub subscription"
        else
            log "SUCCESS" "Pub/Sub subscription deleted"
        fi
    fi
    
    # Delete topic
    if gcloud pubsub topics describe invoice-uploads &> /dev/null; then
        if ! gcloud pubsub topics delete invoice-uploads --quiet 2>> "$LOG_FILE"; then
            log "WARNING" "Failed to delete Pub/Sub topic"
        else
            log "SUCCESS" "Pub/Sub topic deleted"
        fi
    fi
}

# Function to delete service account
delete_service_account() {
    if [ -z "$SERVICE_ACCOUNT" ]; then
        log "INFO" "No service account specified, skipping"
        return 0
    fi
    
    log "INFO" "Deleting service account: $SERVICE_ACCOUNT"
    
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT" &> /dev/null; then
        if ! gcloud iam service-accounts delete "$SERVICE_ACCOUNT" --quiet 2>> "$LOG_FILE"; then
            log "WARNING" "Failed to delete service account: $SERVICE_ACCOUNT"
        else
            log "SUCCESS" "Service account deleted: $SERVICE_ACCOUNT"
        fi
    else
        log "INFO" "Service account not found: $SERVICE_ACCOUNT"
    fi
}

# Function to clean up remaining resources
cleanup_remaining_resources() {
    log "INFO" "Cleaning up any remaining resources..."
    
    # Clean up any remaining storage notifications
    if [ -n "$BUCKET_NAME" ] && gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
        gsutil notification list "gs://$BUCKET_NAME" 2>/dev/null | \
        grep "Cloud Pub/Sub topic:" | \
        while read -r line; do
            local topic=$(echo "$line" | cut -d' ' -f4)
            gsutil notification delete "$topic" "gs://$BUCKET_NAME" 2>> "$LOG_FILE" || true
        done
    fi
    
    # Clean up any remaining triggers
    local remaining_triggers=$(gcloud eventarc triggers list --location="$REGION" --filter="name~invoice" --format="value(name)" 2>/dev/null || true)
    for trigger in $remaining_triggers; do
        local trigger_name=$(basename "$trigger")
        gcloud eventarc triggers delete "$trigger_name" --location="$REGION" --quiet 2>> "$LOG_FILE" || true
    done
    
    log "INFO" "Remaining resources cleanup completed"
}

# Function to delete entire project
delete_project() {
    if [ "$DELETE_PROJECT" != true ]; then
        return 0
    fi
    
    log "WARNING" "Deleting entire project: $PROJECT_ID"
    
    if ! gcloud projects delete "$PROJECT_ID" --quiet 2>> "$LOG_FILE"; then
        log "ERROR" "Failed to delete project: $PROJECT_ID"
        exit 1
    fi
    
    log "SUCCESS" "Project deleted: $PROJECT_ID"
}

# Function to remove deployment info file
remove_deployment_info() {
    local deployment_file="$PROJECT_ROOT/deployment-info.json"
    
    if [ -f "$deployment_file" ]; then
        rm -f "$deployment_file"
        log "SUCCESS" "Deployment info file removed"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "SUCCESS" "🧹 Cleanup completed!"
    echo
    echo "=== Cleanup Summary ==="
    echo "Project: $PROJECT_ID"
    [ -n "$BUCKET_NAME" ] && echo "✅ Storage Bucket: $BUCKET_NAME"
    [ -n "$WORKFLOW_NAME" ] && echo "✅ Workflow: $WORKFLOW_NAME"
    [ -n "$FUNCTION_NAME" ] && echo "✅ Cloud Function: $FUNCTION_NAME"
    [ -n "$TASK_QUEUE_NAME" ] && echo "✅ Task Queue: $TASK_QUEUE_NAME"
    [ -n "$SERVICE_ACCOUNT" ] && echo "✅ Service Account: $SERVICE_ACCOUNT"
    [ -n "$PROCESSOR_ID" ] && echo "✅ Document AI Processor: $PROCESSOR_ID"
    echo "✅ Pub/Sub resources"
    echo "✅ Eventarc triggers"
    echo
    
    if [ "$DELETE_PROJECT" = true ]; then
        echo "✅ Entire project deleted"
    else
        echo "ℹ️  Project preserved: $PROJECT_ID"
        echo "   To delete the project: gcloud projects delete $PROJECT_ID"
    fi
    
    echo
    echo "Log file: $LOG_FILE"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up GCP Smart Invoice Processing infrastructure.

OPTIONS:
    --project-id PROJECT_ID     Specify project ID to clean up
    --region REGION             Specify region (default: us-central1)
    --dry-run                   Show what would be deleted without making changes
    --auto-approve              Skip confirmation prompts
    --delete-project            Delete the entire project (DANGEROUS)
    --skip-confirmation         Skip all confirmation prompts
    --help                      Show this help message

EXAMPLES:
    $0                          # Clean up using deployment info file
    $0 --project-id my-project  # Clean up specific project
    $0 --dry-run               # Show cleanup plan
    $0 --auto-approve          # Clean up without prompts
    $0 --delete-project        # Delete entire project

SAFETY:
    This script will ask for confirmation before deleting resources.
    Use --auto-approve or --skip-confirmation to skip prompts.
    Use --delete-project to delete the entire project (DANGEROUS).

EOF
}

# Main cleanup function
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
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --auto-approve)
                AUTO_APPROVE=true
                shift
                ;;
            --delete-project)
                DELETE_PROJECT=true
                shift
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION=true
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
    
    # Start cleanup
    log "INFO" "Starting GCP Smart Invoice Processing cleanup..."
    log "INFO" "Log file: $LOG_FILE"
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment information
    load_deployment_info
    
    # Discover resources if needed
    if [ -z "$BUCKET_NAME" ] && [ -z "$WORKFLOW_NAME" ]; then
        discover_resources
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log "INFO" "DRY RUN MODE - No resources will be deleted"
        echo "Would delete:"
        echo "- Project: ${PROJECT_ID:-not specified}"
        [ -n "$BUCKET_NAME" ] && echo "- Storage Bucket: $BUCKET_NAME"
        [ -n "$WORKFLOW_NAME" ] && echo "- Workflow: $WORKFLOW_NAME"
        [ -n "$FUNCTION_NAME" ] && echo "- Cloud Function: $FUNCTION_NAME"
        [ -n "$TASK_QUEUE_NAME" ] && echo "- Task Queue: $TASK_QUEUE_NAME"
        [ -n "$SERVICE_ACCOUNT" ] && echo "- Service Account: $SERVICE_ACCOUNT"
        [ -n "$PROCESSOR_ID" ] && echo "- Document AI Processor: $PROCESSOR_ID"
        echo "- Pub/Sub topics and subscriptions"
        echo "- Eventarc triggers"
        if [ "$DELETE_PROJECT" = true ]; then
            echo "- ENTIRE PROJECT"
        fi
        exit 0
    fi
    
    # Confirm destructive actions
    confirm_destruction
    
    # Perform cleanup in reverse order of creation
    log "INFO" "Beginning resource cleanup..."
    
    delete_eventarc_trigger
    delete_workflow
    delete_cloud_function
    delete_task_queue
    delete_document_ai_processor
    delete_pubsub_resources
    delete_storage_bucket
    delete_service_account
    cleanup_remaining_resources
    
    # Delete project if requested
    if [ "$DELETE_PROJECT" = true ]; then
        delete_project
    fi
    
    # Remove deployment info
    remove_deployment_info
    
    # Display summary
    display_summary
    
    log "SUCCESS" "Cleanup completed successfully"
}

# Run main function
main "$@"