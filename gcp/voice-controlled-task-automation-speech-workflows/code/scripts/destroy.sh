#!/bin/bash

# Voice-Controlled Task Automation Cleanup Script
# This script removes all resources created by the deployment script:
# - Cloud Functions (voice processor and task processor)
# - Cloud Workflows
# - Cloud Tasks queue
# - Cloud Storage bucket
# - IAM policy bindings

set -e  # Exit on any error

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Check if .env file exists
    if [ -f ".env" ]; then
        # Source environment variables from .env file
        set -a  # Automatically export all variables
        source .env
        set +a  # Turn off automatic export
        success "Environment variables loaded from .env file"
    else
        warning ".env file not found. Checking for manual environment variables..."
        
        # Check if required variables are set manually
        if [ -z "$PROJECT_ID" ] || [ -z "$REGION" ] || [ -z "$FUNCTION_NAME" ] || \
           [ -z "$WORKFLOW_NAME" ] || [ -z "$BUCKET_NAME" ] || [ -z "$QUEUE_NAME" ] || \
           [ -z "$TASK_PROCESSOR_NAME" ]; then
            error "Required environment variables not found."
            error "Please ensure the deployment script was run successfully or set variables manually:"
            echo "  export PROJECT_ID=\"your-project-id\""
            echo "  export REGION=\"your-region\""
            echo "  export FUNCTION_NAME=\"your-function-name\""
            echo "  export WORKFLOW_NAME=\"your-workflow-name\""
            echo "  export BUCKET_NAME=\"your-bucket-name\""
            echo "  export QUEUE_NAME=\"your-queue-name\""
            echo "  export TASK_PROCESSOR_NAME=\"your-task-processor-name\""
            exit 1
        else
            success "Environment variables found"
        fi
    fi
    
    log "Project ID: $PROJECT_ID"
    log "Region: $REGION"
    log "Resources to be deleted:"
    log "  - Function: $FUNCTION_NAME"
    log "  - Task Processor: $TASK_PROCESSOR_NAME"
    log "  - Workflow: $WORKFLOW_NAME"
    log "  - Queue: $QUEUE_NAME"
    log "  - Bucket: gs://$BUCKET_NAME"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warning "This will permanently delete the following resources:"
    echo "  • Cloud Functions: $FUNCTION_NAME, $TASK_PROCESSOR_NAME"
    echo "  • Cloud Workflow: $WORKFLOW_NAME"
    echo "  • Cloud Tasks Queue: $QUEUE_NAME"
    echo "  • Storage Bucket: gs://$BUCKET_NAME (and all contents)"
    echo "  • IAM policy bindings"
    echo ""
    
    # Check for force flag
    if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
        warning "Force flag detected. Skipping confirmation."
        return 0
    fi
    
    # Interactive confirmation
    read -p "Are you sure you want to delete all these resources? (yes/no): " confirm
    case $confirm in
        [Yy]es|[Yy]|YES)
            log "Proceeding with resource deletion..."
            ;;
        *)
            log "Deletion cancelled by user."
            exit 0
            ;;
    esac
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Set gcloud project
    gcloud config set project ${PROJECT_ID} --quiet
    
    success "Prerequisites check completed"
}

# Function to get service accounts for IAM cleanup
get_service_accounts() {
    log "Retrieving service accounts for IAM cleanup..."
    
    # Get function service account (if function exists)
    if gcloud functions describe ${FUNCTION_NAME} --region=${REGION} &>/dev/null; then
        FUNCTION_SA=$(gcloud functions describe ${FUNCTION_NAME} \
            --region=${REGION} \
            --format="value(serviceAccountEmail)" 2>/dev/null)
        if [ -n "$FUNCTION_SA" ]; then
            log "Found function service account: $FUNCTION_SA"
        fi
    fi
    
    # Workflows service account (standard format)
    WORKFLOWS_SA="${PROJECT_ID}@appspot.gserviceaccount.com"
    log "Using workflows service account: $WORKFLOWS_SA"
}

# Function to remove IAM policy bindings
cleanup_iam_policies() {
    log "Cleaning up IAM policy bindings..."
    
    # Remove Workflows Invoker role from function service account
    if [ -n "$FUNCTION_SA" ]; then
        if gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
            --member="serviceAccount:${FUNCTION_SA}" \
            --role="roles/workflows.invoker" \
            --quiet 2>/dev/null; then
            log "Removed Workflows Invoker role from function service account"
        else
            warning "Failed to remove Workflows Invoker role (may not exist)"
        fi
        
        # Remove Speech-to-Text Client role from function service account
        if gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
            --member="serviceAccount:${FUNCTION_SA}" \
            --role="roles/speech.client" \
            --quiet 2>/dev/null; then
            log "Removed Speech-to-Text Client role from function service account"
        else
            warning "Failed to remove Speech-to-Text Client role (may not exist)"
        fi
    fi
    
    # Remove Cloud Tasks Admin role from Workflows service account
    if gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${WORKFLOWS_SA}" \
        --role="roles/cloudtasks.admin" \
        --quiet 2>/dev/null; then
        log "Removed Cloud Tasks Admin role from Workflows service account"
    else
        warning "Failed to remove Cloud Tasks Admin role (may not exist)"
    fi
    
    success "IAM policy cleanup completed"
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    # Delete voice processing function
    if gcloud functions describe ${FUNCTION_NAME} --region=${REGION} &>/dev/null; then
        if gcloud functions delete ${FUNCTION_NAME} \
            --region=${REGION} \
            --quiet; then
            success "Deleted voice processing function: ${FUNCTION_NAME}"
        else
            error "Failed to delete voice processing function"
        fi
    else
        warning "Voice processing function ${FUNCTION_NAME} not found"
    fi
    
    # Delete task processing function
    if gcloud functions describe ${TASK_PROCESSOR_NAME} --region=${REGION} &>/dev/null; then
        if gcloud functions delete ${TASK_PROCESSOR_NAME} \
            --region=${REGION} \
            --quiet; then
            success "Deleted task processing function: ${TASK_PROCESSOR_NAME}"
        else
            error "Failed to delete task processing function"
        fi
    else
        warning "Task processing function ${TASK_PROCESSOR_NAME} not found"
    fi
}

# Function to delete Cloud Workflow
delete_workflow() {
    log "Deleting Cloud Workflow..."
    
    if gcloud workflows describe ${WORKFLOW_NAME} --location=${REGION} &>/dev/null; then
        if gcloud workflows delete ${WORKFLOW_NAME} \
            --location=${REGION} \
            --quiet; then
            success "Deleted Cloud Workflow: ${WORKFLOW_NAME}"
        else
            error "Failed to delete Cloud Workflow"
        fi
    else
        warning "Cloud Workflow ${WORKFLOW_NAME} not found"
    fi
}

# Function to delete Cloud Tasks queue
delete_task_queue() {
    log "Deleting Cloud Tasks queue..."
    
    if gcloud tasks queues describe ${QUEUE_NAME} --location=${REGION} &>/dev/null; then
        # Purge queue first to remove any pending tasks
        if gcloud tasks queues purge ${QUEUE_NAME} \
            --location=${REGION} \
            --quiet 2>/dev/null; then
            log "Purged tasks from queue"
        fi
        
        # Delete the queue
        if gcloud tasks queues delete ${QUEUE_NAME} \
            --location=${REGION} \
            --quiet; then
            success "Deleted Cloud Tasks queue: ${QUEUE_NAME}"
        else
            error "Failed to delete Cloud Tasks queue"
        fi
    else
        warning "Cloud Tasks queue ${QUEUE_NAME} not found"
    fi
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log "Deleting Cloud Storage bucket..."
    
    if gsutil ls -b gs://${BUCKET_NAME} &>/dev/null; then
        # Remove all objects in the bucket first
        if gsutil -m rm -r gs://${BUCKET_NAME}/* 2>/dev/null || true; then
            log "Removed all objects from bucket"
        fi
        
        # Remove the bucket
        if gsutil rb gs://${BUCKET_NAME}; then
            success "Deleted Cloud Storage bucket: gs://${BUCKET_NAME}"
        else
            error "Failed to delete Cloud Storage bucket"
        fi
    else
        warning "Cloud Storage bucket gs://${BUCKET_NAME} not found"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary directories created during deployment
    if [ -d "voice-function" ]; then
        rm -rf voice-function
        log "Removed voice-function directory"
    fi
    
    if [ -d "task-processor" ]; then
        rm -rf task-processor
        log "Removed task-processor directory"
    fi
    
    # Remove temporary workflow file
    if [ -f "task-automation-workflow.yaml" ]; then
        rm -f task-automation-workflow.yaml
        log "Removed workflow definition file"
    fi
    
    # Remove lifecycle configuration file
    if [ -f "lifecycle.json" ]; then
        rm -f lifecycle.json
        log "Removed lifecycle configuration file"
    fi
    
    # Ask user if they want to remove the .env file
    if [ -f ".env" ]; then
        read -p "Remove .env file with stored variables? (y/n): " remove_env
        case $remove_env in
            [Yy]|[Yy]es)
                rm -f .env
                log "Removed .env file"
                ;;
            *)
                log "Keeping .env file"
                ;;
        esac
    fi
    
    success "Local file cleanup completed"
}

# Function to verify resource deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local failed_deletions=0
    
    # Check if functions still exist
    if gcloud functions describe ${FUNCTION_NAME} --region=${REGION} &>/dev/null; then
        error "Voice processing function still exists"
        ((failed_deletions++))
    else
        log "✓ Voice processing function deleted"
    fi
    
    if gcloud functions describe ${TASK_PROCESSOR_NAME} --region=${REGION} &>/dev/null; then
        error "Task processing function still exists"
        ((failed_deletions++))
    else
        log "✓ Task processing function deleted"
    fi
    
    # Check if workflow still exists
    if gcloud workflows describe ${WORKFLOW_NAME} --location=${REGION} &>/dev/null; then
        error "Cloud Workflow still exists"
        ((failed_deletions++))
    else
        log "✓ Cloud Workflow deleted"
    fi
    
    # Check if task queue still exists
    if gcloud tasks queues describe ${QUEUE_NAME} --location=${REGION} &>/dev/null; then
        error "Cloud Tasks queue still exists"
        ((failed_deletions++))
    else
        log "✓ Cloud Tasks queue deleted"
    fi
    
    # Check if storage bucket still exists
    if gsutil ls -b gs://${BUCKET_NAME} &>/dev/null; then
        error "Cloud Storage bucket still exists"
        ((failed_deletions++))
    else
        log "✓ Cloud Storage bucket deleted"
    fi
    
    if [ $failed_deletions -eq 0 ]; then
        success "All resources successfully deleted"
        return 0
    else
        error "$failed_deletions resource(s) failed to delete properly"
        return 1
    fi
}

# Function to display final summary
display_summary() {
    echo ""
    echo "==============================================="
    echo "  Voice-Controlled Task Automation Cleanup"
    echo "==============================================="
    echo ""
    
    if [ $1 -eq 0 ]; then
        success "Cleanup completed successfully!"
        echo ""
        echo "All resources have been removed:"
        echo "  ✓ Cloud Functions deleted"
        echo "  ✓ Cloud Workflow deleted"
        echo "  ✓ Cloud Tasks queue deleted"
        echo "  ✓ Cloud Storage bucket deleted"
        echo "  ✓ IAM policies cleaned up"
        echo "  ✓ Local files cleaned up"
        echo ""
        log "The voice-controlled task automation system has been completely removed."
    else
        error "Cleanup completed with some failures!"
        echo ""
        warning "Some resources may not have been deleted completely."
        warning "Please check the Google Cloud Console to verify all resources are removed."
        warning "You may need to manually delete any remaining resources to avoid charges."
    fi
}

# Main cleanup function
main() {
    echo "================================================================"
    echo "  GCP Voice-Controlled Task Automation Cleanup Script"
    echo "================================================================"
    echo ""
    
    # Load environment and confirm deletion
    load_environment
    confirm_deletion "$1"
    check_prerequisites
    get_service_accounts
    
    # Perform cleanup operations
    log "Starting resource cleanup..."
    cleanup_iam_policies
    delete_cloud_functions
    delete_workflow
    delete_task_queue
    delete_storage_bucket
    cleanup_local_files
    
    # Verify deletion and display summary
    if verify_deletion; then
        display_summary 0
        exit 0
    else
        display_summary 1
        exit 1
    fi
}

# Handle script interruption
trap 'error "Cleanup interrupted"; exit 1' INT TERM

# Show help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Cleanup script for GCP Voice-Controlled Task Automation"
    echo ""
    echo "Options:"
    echo "  -f, --force    Skip confirmation prompts"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "The script will read configuration from .env file created during deployment."
    echo "If .env file is not found, ensure the following environment variables are set:"
    echo "  PROJECT_ID, REGION, FUNCTION_NAME, WORKFLOW_NAME, BUCKET_NAME, QUEUE_NAME, TASK_PROCESSOR_NAME"
}

# Parse command line arguments
case "$1" in
    -h|--help)
        show_help
        exit 0
        ;;
    -f|--force)
        main --force
        ;;
    "")
        main
        ;;
    *)
        error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac