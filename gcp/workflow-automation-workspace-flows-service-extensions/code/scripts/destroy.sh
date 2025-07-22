#!/bin/bash

# Workflow Automation with Google Workspace Flows and Service Extensions - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

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

# Global variables for resource tracking
declare -a FAILED_DELETIONS=()

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ -f "deployment-info.txt" ]]; then
        # Extract resource information from deployment-info.txt
        export PROJECT_ID=$(grep "Project ID:" deployment-info.txt | cut -d' ' -f3)
        export REGION=$(grep "Region:" deployment-info.txt | cut -d' ' -f2)
        
        # Extract resource names
        export BUCKET_NAME=$(grep "Storage Bucket:" deployment-info.txt | sed 's/.*gs:\/\///' | sed 's/$//')
        export TOPIC_NAME=$(grep "Pub/Sub Topic:" deployment-info.txt | cut -d' ' -f4)
        export SUBSCRIPTION_NAME=$(grep "Pub/Sub Subscription:" deployment-info.txt | cut -d' ' -f4)
        
        # Extract function names
        export FUNCTION_NAME=$(grep "Document Processor:" deployment-info.txt | cut -d' ' -f5)
        export APPROVAL_WEBHOOK=$(grep "Approval Webhook:" deployment-info.txt | cut -d' ' -f5)
        export CHAT_NOTIFICATIONS=$(grep "Chat Notifications:" deployment-info.txt | cut -d' ' -f5)
        export ANALYTICS_COLLECTOR=$(grep "Analytics Collector:" deployment-info.txt | cut -d' ' -f5)
        
        log_success "Loaded deployment information from deployment-info.txt"
    else
        log_warning "deployment-info.txt not found. Attempting to discover resources..."
        discover_resources
    fi
    
    # Set gcloud configuration
    if [[ -n "${PROJECT_ID:-}" ]]; then
        gcloud config set project "${PROJECT_ID}"
        if [[ -n "${REGION:-}" ]]; then
            gcloud config set compute/region "${REGION}"
        fi
        log_info "Using project: ${PROJECT_ID}"
    else
        log_error "Could not determine project ID. Please ensure deployment-info.txt exists or set PROJECT_ID manually."
        exit 1
    fi
}

# Discover resources if deployment info is not available
discover_resources() {
    log_info "Discovering workflow automation resources..."
    
    # Get current project
    export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    export REGION="${REGION:-us-central1}"
    
    if [[ -z "$PROJECT_ID" ]]; then
        read -p "Enter your Google Cloud Project ID: " PROJECT_ID
        export PROJECT_ID
        gcloud config set project "${PROJECT_ID}"
    fi
    
    # Discover Cloud Functions
    log_info "Discovering Cloud Functions..."
    local functions=$(gcloud functions list --regions="${REGION}" --format="value(name)" --filter="name~doc-processor OR name~approval-webhook OR name~chat-notifications OR name~analytics-collector" 2>/dev/null || echo "")
    
    if [[ -n "$functions" ]]; then
        while IFS= read -r func; do
            if [[ "$func" =~ doc-processor ]]; then
                export FUNCTION_NAME="$func"
            elif [[ "$func" =~ approval-webhook ]]; then
                export APPROVAL_WEBHOOK="$func"
            elif [[ "$func" =~ chat-notifications ]]; then
                export CHAT_NOTIFICATIONS="$func"
            elif [[ "$func" =~ analytics-collector ]]; then
                export ANALYTICS_COLLECTOR="$func"
            fi
        done <<< "$functions"
    fi
    
    # Discover Pub/Sub topics
    log_info "Discovering Pub/Sub topics..."
    local topics=$(gcloud pubsub topics list --format="value(name)" --filter="name~document-events" 2>/dev/null || echo "")
    if [[ -n "$topics" ]]; then
        export TOPIC_NAME=$(echo "$topics" | head -n1 | sed 's|projects/.*/topics/||')
        export SUBSCRIPTION_NAME="doc-processing-sub-$(echo "$TOPIC_NAME" | sed 's/document-events-//')"
    fi
    
    # Discover Storage buckets
    log_info "Discovering Storage buckets..."
    local buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "workflow-docs" || echo "")
    if [[ -n "$buckets" ]]; then
        export BUCKET_NAME=$(echo "$buckets" | head -n1 | sed 's|gs://||' | sed 's|/||')
    fi
    
    log_success "Resource discovery completed"
}

# Confirmation prompt
confirm_deletion() {
    log_warning "This will permanently delete the following resources:"
    echo ""
    
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        echo "  - Cloud Function: ${FUNCTION_NAME}"
    fi
    if [[ -n "${APPROVAL_WEBHOOK:-}" ]]; then
        echo "  - Cloud Function: ${APPROVAL_WEBHOOK}"
    fi
    if [[ -n "${CHAT_NOTIFICATIONS:-}" ]]; then
        echo "  - Cloud Function: ${CHAT_NOTIFICATIONS}"
    fi
    if [[ -n "${ANALYTICS_COLLECTOR:-}" ]]; then
        echo "  - Cloud Function: ${ANALYTICS_COLLECTOR}"
    fi
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        echo "  - Pub/Sub Topic: ${TOPIC_NAME}"
        echo "  - Pub/Sub Topic: ${TOPIC_NAME}-deadletter"
    fi
    if [[ -n "${SUBSCRIPTION_NAME:-}" ]]; then
        echo "  - Pub/Sub Subscription: ${SUBSCRIPTION_NAME}"
        echo "  - Pub/Sub Subscription: ${SUBSCRIPTION_NAME}-deadletter"
    fi
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        echo "  - Storage Bucket: gs://${BUCKET_NAME} (including all contents)"
    fi
    
    echo "  - Local directories: cloud-functions/, service-extensions/, workspace-flows/, monitoring/"
    echo ""
    
    # Check for --force flag
    if [[ "${1:-}" == "--force" ]]; then
        log_warning "Force flag detected. Proceeding without confirmation..."
        return 0
    fi
    
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    case $confirmation in
        [Yy][Ee][Ss]|[Yy])
            log_info "Proceeding with resource deletion..."
            ;;
        *)
            log_info "Deletion cancelled by user."
            exit 0
            ;;
    esac
}

# Delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    local functions=(
        "${FUNCTION_NAME:-}"
        "${APPROVAL_WEBHOOK:-}"
        "${CHAT_NOTIFICATIONS:-}"
        "${ANALYTICS_COLLECTOR:-}"
    )
    
    for func in "${functions[@]}"; do
        if [[ -n "$func" ]]; then
            log_info "Deleting function: $func"
            if gcloud functions delete "$func" --region="${REGION}" --quiet 2>/dev/null; then
                log_success "Deleted function: $func"
            else
                log_error "Failed to delete function: $func"
                FAILED_DELETIONS+=("Cloud Function: $func")
            fi
        fi
    done
    
    # Wait for function deletions to complete
    log_info "Waiting for function deletions to complete..."
    sleep 10
}

# Delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    # Delete subscriptions first
    local subscriptions=(
        "${SUBSCRIPTION_NAME:-}"
        "${SUBSCRIPTION_NAME:-}-deadletter"
    )
    
    for subscription in "${subscriptions[@]}"; do
        if [[ -n "$subscription" ]]; then
            log_info "Deleting subscription: $subscription"
            if gcloud pubsub subscriptions delete "$subscription" --quiet 2>/dev/null; then
                log_success "Deleted subscription: $subscription"
            else
                log_warning "Failed to delete subscription: $subscription (may not exist)"
            fi
        fi
    done
    
    # Delete topics
    local topics=(
        "${TOPIC_NAME:-}"
        "${TOPIC_NAME:-}-deadletter"
    )
    
    for topic in "${topics[@]}"; do
        if [[ -n "$topic" ]]; then
            log_info "Deleting topic: $topic"
            if gcloud pubsub topics delete "$topic" --quiet 2>/dev/null; then
                log_success "Deleted topic: $topic"
            else
                log_warning "Failed to delete topic: $topic (may not exist)"
            fi
        fi
    done
}

# Delete Storage bucket
delete_storage_bucket() {
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log_info "Deleting Storage bucket: gs://${BUCKET_NAME}"
        
        # First, remove all objects in the bucket (including versions)
        log_info "Removing all objects from bucket..."
        if gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null; then
            log_success "Removed all objects from bucket"
        else
            log_warning "No objects found in bucket or bucket does not exist"
        fi
        
        # Remove the bucket itself
        if gsutil rb "gs://${BUCKET_NAME}" 2>/dev/null; then
            log_success "Deleted bucket: gs://${BUCKET_NAME}"
        else
            log_error "Failed to delete bucket: gs://${BUCKET_NAME}"
            FAILED_DELETIONS+=("Storage Bucket: gs://${BUCKET_NAME}")
        fi
    else
        log_warning "No bucket name found to delete"
    fi
}

# Clean up local files and directories
cleanup_local_files() {
    log_info "Cleaning up local files and directories..."
    
    local directories=(
        "cloud-functions"
        "service-extensions"
        "workspace-flows"
        "monitoring"
    )
    
    for dir in "${directories[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "Removing directory: $dir"
            rm -rf "$dir"
            log_success "Removed directory: $dir"
        fi
    done
    
    # Clean up temporary files
    local files=(
        "lifecycle-policy.json"
        "deployment-info.txt"
    )
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing file: $file"
            rm -f "$file"
            log_success "Removed file: $file"
        fi
    done
}

# Verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local verification_failed=false
    
    # Check Cloud Functions
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
            log_error "Function still exists: ${FUNCTION_NAME}"
            verification_failed=true
        fi
    fi
    
    # Check Pub/Sub topics
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
            log_error "Topic still exists: ${TOPIC_NAME}"
            verification_failed=true
        fi
    fi
    
    # Check Storage bucket
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            log_error "Bucket still exists: gs://${BUCKET_NAME}"
            verification_failed=true
        fi
    fi
    
    if [[ "$verification_failed" == "false" ]]; then
        log_success "All resources successfully deleted"
    else
        log_warning "Some resources may still exist. Please check manually."
    fi
}

# Display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "================"
    
    if [[ ${#FAILED_DELETIONS[@]} -eq 0 ]]; then
        log_success "All resources were successfully deleted!"
    else
        log_warning "The following resources could not be deleted:"
        for resource in "${FAILED_DELETIONS[@]}"; do
            echo "  - $resource"
        done
        echo ""
        log_info "Please check these resources manually in the Google Cloud Console."
    fi
    
    echo ""
    log_info "Manual cleanup may still be required for:"
    echo "  - Google Workspace Flows configuration"
    echo "  - Google Sheets tracking spreadsheets"
    echo "  - Google Chat spaces and bot configurations"
    echo "  - Custom monitoring dashboards"
    echo ""
    
    if [[ ${#FAILED_DELETIONS[@]} -eq 0 ]]; then
        log_success "🎉 Cleanup completed successfully!"
    else
        log_warning "⚠️  Cleanup completed with some issues. Please review the failed deletions above."
    fi
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warning "Cleanup interrupted by user. Some resources may still exist."
    display_cleanup_summary
    exit 1
}

trap cleanup_on_interrupt SIGINT SIGTERM

# Main cleanup function
main() {
    log_info "Starting Workflow Automation cleanup..."
    
    check_prerequisites
    load_deployment_info
    confirm_deletion "$@"
    
    delete_cloud_functions
    delete_pubsub_resources
    delete_storage_bucket
    cleanup_local_files
    verify_deletion
    display_cleanup_summary
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force     Skip confirmation prompt and proceed with deletion"
    echo "  --help      Show this help message"
    echo ""
    echo "This script will delete all resources created by the workflow automation deployment."
    echo "Make sure you have the deployment-info.txt file in the current directory for"
    echo "accurate resource identification."
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        show_usage
        exit 0
        ;;
    --force)
        main --force
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac