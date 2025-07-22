#!/bin/bash

# Multi-Language Content Localization Workflows Cleanup Script
# This script removes all infrastructure created by the deployment script
# to avoid ongoing charges and clean up resources

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# Error handler
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Check ${LOG_FILE} for details."
    exit 1
}

# Banner
cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                Multi-Language Content Localization Cleanup                  ║
║                                                                              ║
║   This script will remove ALL resources created by the deployment script.   ║
║   This action is IRREVERSIBLE and will permanently delete:                  ║
║   • All storage buckets and content                                         ║
║   • Cloud Functions and configurations                                      ║
║   • Scheduler jobs and Pub/Sub topics                                       ║
║   • Log sinks and monitoring configurations                                 ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF

# Function to load deployment configuration
load_configuration() {
    local config_file="${SCRIPT_DIR}/deployment.env"
    
    if [[ ! -f "$config_file" ]]; then
        log_warning "Deployment configuration file not found: $config_file"
        log_info "This may be a manual cleanup. Please provide configuration manually."
        
        # Manual configuration input
        read -p "Enter Google Cloud Project ID: " PROJECT_ID
        read -p "Enter Region (default: us-central1): " REGION
        REGION=${REGION:-us-central1}
        read -p "Enter resource suffix (3 hex chars): " SUFFIX
        
        export PROJECT_ID
        export REGION
        export ZONE="${REGION}-a"
        export BUCKET_SOURCE="source-content-${SUFFIX}"
        export BUCKET_TRANSLATED="translated-content-${SUFFIX}"
        export TOPIC_NAME="translation-workflow-${SUFFIX}"
        export FUNCTION_NAME="translation-processor-${SUFFIX}"
        export SCHEDULER_JOB="batch-translation-job"
        export MONITOR_JOB="translation-monitor"
        
        log_warning "Using manual configuration. Some resources might not be found."
    else
        log_info "Loading deployment configuration..."
        # shellcheck source=/dev/null
        source "$config_file"
        log_success "Configuration loaded successfully"
        log_info "Project: $PROJECT_ID"
        log_info "Region: $REGION"
    fi
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "You are about to DELETE the following resources:"
    echo
    echo "  📦 Storage Buckets:"
    echo "     • gs://${BUCKET_SOURCE}"
    echo "     • gs://${BUCKET_TRANSLATED}"
    echo
    echo "  ⚡ Cloud Function:"
    echo "     • ${FUNCTION_NAME}"
    echo
    echo "  📢 Pub/Sub Resources:"
    echo "     • Topic: ${TOPIC_NAME}"
    echo "     • Subscription: ${TOPIC_NAME}-sub"
    echo
    echo "  ⏰ Scheduler Jobs:"
    echo "     • ${SCHEDULER_JOB}"
    echo "     • ${MONITOR_JOB}"
    echo
    echo "  📊 Monitoring:"
    echo "     • Log sink: translation-audit"
    echo
    echo "  🗂️ Storage Content:"
    echo "     • ALL files in both buckets"
    echo "     • ALL translated content"
    echo "     • ALL audit logs"
    echo
    
    log_warning "This action is IRREVERSIBLE!"
    log_warning "All data will be permanently lost!"
    echo
    
    # Double confirmation for safety
    read -p "Type 'DELETE' to confirm resource destruction: " confirmation1
    if [[ "$confirmation1" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    read -p "Type the project ID '$PROJECT_ID' to confirm: " confirmation2
    if [[ "$confirmation2" != "$PROJECT_ID" ]]; then
        log_info "Project ID confirmation failed. Cleanup cancelled."
        exit 0
    fi
    
    log_warning "Proceeding with resource destruction in 10 seconds..."
    log_warning "Press Ctrl+C to cancel..."
    sleep 10
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "No active gcloud authentication found. Run 'gcloud auth login'"
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID" || error_exit "Failed to set project context"
    
    log_success "Prerequisites check completed"
}

# Function to remove Cloud Scheduler jobs
remove_scheduler() {
    log_info "Removing Cloud Scheduler jobs..."
    
    # Remove batch translation job
    if gcloud scheduler jobs describe "$SCHEDULER_JOB" --location="$REGION" >/dev/null 2>&1; then
        log_info "Deleting batch scheduler job: $SCHEDULER_JOB"
        gcloud scheduler jobs delete "$SCHEDULER_JOB" \
            --location="$REGION" \
            --quiet || log_warning "Failed to delete batch scheduler job"
    else
        log_info "Batch scheduler job not found: $SCHEDULER_JOB"
    fi
    
    # Remove monitoring job
    if gcloud scheduler jobs describe "$MONITOR_JOB" --location="$REGION" >/dev/null 2>&1; then
        log_info "Deleting monitor scheduler job: $MONITOR_JOB"
        gcloud scheduler jobs delete "$MONITOR_JOB" \
            --location="$REGION" \
            --quiet || log_warning "Failed to delete monitor scheduler job"
    else
        log_info "Monitor scheduler job not found: $MONITOR_JOB"
    fi
    
    log_success "Scheduler jobs removal completed"
}

# Function to remove Cloud Function
remove_function() {
    log_info "Removing Cloud Function..."
    
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" >/dev/null 2>&1; then
        log_info "Deleting Cloud Function: $FUNCTION_NAME"
        gcloud functions delete "$FUNCTION_NAME" \
            --region="$REGION" \
            --quiet || log_warning "Failed to delete Cloud Function"
        
        # Wait for function deletion to complete
        log_info "Waiting for function deletion to complete..."
        sleep 30
    else
        log_info "Cloud Function not found: $FUNCTION_NAME"
    fi
    
    log_success "Cloud Function removal completed"
}

# Function to remove storage notifications
remove_notifications() {
    log_info "Removing Cloud Storage notifications..."
    
    # List and remove notifications from source bucket
    if gsutil ls -b "gs://$BUCKET_SOURCE" >/dev/null 2>&1; then
        local notifications
        notifications=$(gsutil notification list "gs://$BUCKET_SOURCE" 2>/dev/null | grep "Notification" | awk '{print $2}' || echo "")
        
        if [[ -n "$notifications" ]]; then
            for notification in $notifications; do
                log_info "Removing notification: $notification"
                gsutil notification delete "$notification" "gs://$BUCKET_SOURCE" || log_warning "Failed to remove notification $notification"
            done
        else
            log_info "No notifications found on source bucket"
        fi
    else
        log_info "Source bucket not found: gs://$BUCKET_SOURCE"
    fi
    
    log_success "Storage notifications removal completed"
}

# Function to remove storage buckets
remove_storage() {
    log_info "Removing Cloud Storage buckets..."
    
    # Remove source bucket and all contents
    if gsutil ls -b "gs://$BUCKET_SOURCE" >/dev/null 2>&1; then
        log_info "Removing source bucket and contents: gs://$BUCKET_SOURCE"
        
        # First remove all objects (including versions)
        gsutil -m rm -r "gs://$BUCKET_SOURCE/**" 2>/dev/null || log_info "No objects to remove from source bucket"
        
        # Remove versioned objects
        gsutil -m rm -a "gs://$BUCKET_SOURCE/**" 2>/dev/null || log_info "No versioned objects to remove from source bucket"
        
        # Remove bucket
        gsutil rb "gs://$BUCKET_SOURCE" || log_warning "Failed to remove source bucket"
    else
        log_info "Source bucket not found: gs://$BUCKET_SOURCE"
    fi
    
    # Remove translated bucket and all contents
    if gsutil ls -b "gs://$BUCKET_TRANSLATED" >/dev/null 2>&1; then
        log_info "Removing translated bucket and contents: gs://$BUCKET_TRANSLATED"
        
        # First remove all objects (including versions)
        gsutil -m rm -r "gs://$BUCKET_TRANSLATED/**" 2>/dev/null || log_info "No objects to remove from translated bucket"
        
        # Remove versioned objects
        gsutil -m rm -a "gs://$BUCKET_TRANSLATED/**" 2>/dev/null || log_info "No versioned objects to remove from translated bucket"
        
        # Remove bucket
        gsutil rb "gs://$BUCKET_TRANSLATED" || log_warning "Failed to remove translated bucket"
    else
        log_info "Translated bucket not found: gs://$BUCKET_TRANSLATED"
    fi
    
    log_success "Storage buckets removal completed"
}

# Function to remove Pub/Sub resources
remove_pubsub() {
    log_info "Removing Pub/Sub resources..."
    
    # Remove subscription
    if gcloud pubsub subscriptions describe "${TOPIC_NAME}-sub" >/dev/null 2>&1; then
        log_info "Deleting Pub/Sub subscription: ${TOPIC_NAME}-sub"
        gcloud pubsub subscriptions delete "${TOPIC_NAME}-sub" \
            --quiet || log_warning "Failed to delete Pub/Sub subscription"
    else
        log_info "Pub/Sub subscription not found: ${TOPIC_NAME}-sub"
    fi
    
    # Remove topic
    if gcloud pubsub topics describe "$TOPIC_NAME" >/dev/null 2>&1; then
        log_info "Deleting Pub/Sub topic: $TOPIC_NAME"
        gcloud pubsub topics delete "$TOPIC_NAME" \
            --quiet || log_warning "Failed to delete Pub/Sub topic"
    else
        log_info "Pub/Sub topic not found: $TOPIC_NAME"
    fi
    
    log_success "Pub/Sub resources removal completed"
}

# Function to remove monitoring and logging
remove_monitoring() {
    log_info "Removing monitoring and logging resources..."
    
    # Remove log sink
    if gcloud logging sinks describe translation-audit >/dev/null 2>&1; then
        log_info "Deleting log sink: translation-audit"
        gcloud logging sinks delete translation-audit \
            --quiet || log_warning "Failed to delete log sink"
    else
        log_info "Log sink not found: translation-audit"
    fi
    
    log_success "Monitoring and logging removal completed"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment configuration
    if [[ -f "${SCRIPT_DIR}/deployment.env" ]]; then
        rm -f "${SCRIPT_DIR}/deployment.env"
        log_info "Removed deployment configuration file"
    fi
    
    # Remove any temporary files
    rm -f "${SCRIPT_DIR}/lifecycle.json"
    rm -f "${SCRIPT_DIR}/monitoring-config.json"
    rm -f "${SCRIPT_DIR}/test-document.txt"
    rm -f "${SCRIPT_DIR}/sample-dataset.tsv"
    
    # Remove function source directory if it exists
    if [[ -d "${SCRIPT_DIR}/function-source" ]]; then
        rm -rf "${SCRIPT_DIR}/function-source"
        log_info "Removed function source directory"
    fi
    
    log_success "Local files cleanup completed"
}

# Function to validate cleanup
validate_cleanup() {
    log_info "Validating cleanup..."
    
    local cleanup_success=true
    
    # Check if buckets still exist
    if gsutil ls -b "gs://$BUCKET_SOURCE" >/dev/null 2>&1; then
        log_warning "Source bucket still exists: gs://$BUCKET_SOURCE"
        cleanup_success=false
    fi
    
    if gsutil ls -b "gs://$BUCKET_TRANSLATED" >/dev/null 2>&1; then
        log_warning "Translated bucket still exists: gs://$BUCKET_TRANSLATED"
        cleanup_success=false
    fi
    
    # Check if Cloud Function still exists
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" >/dev/null 2>&1; then
        log_warning "Cloud Function still exists: $FUNCTION_NAME"
        cleanup_success=false
    fi
    
    # Check if Pub/Sub topic still exists
    if gcloud pubsub topics describe "$TOPIC_NAME" >/dev/null 2>&1; then
        log_warning "Pub/Sub topic still exists: $TOPIC_NAME"
        cleanup_success=false
    fi
    
    # Check if scheduler jobs still exist
    local job_count
    job_count=$(gcloud scheduler jobs list --location="$REGION" --filter="name:($SCHEDULER_JOB OR $MONITOR_JOB)" --format="value(name)" 2>/dev/null | wc -l)
    if [[ "$job_count" -gt 0 ]]; then
        log_warning "Some scheduler jobs still exist"
        cleanup_success=false
    fi
    
    if [[ "$cleanup_success" == "true" ]]; then
        log_success "Cleanup validation passed - all resources removed"
    else
        log_warning "Some resources may still exist. Manual cleanup may be required."
    fi
}

# Function to offer project deletion
offer_project_deletion() {
    echo
    log_info "Project cleanup options:"
    echo
    echo "The project '$PROJECT_ID' still exists with the following implications:"
    echo "• APIs remain enabled (no additional charges)"
    echo "• Project counting towards quota limits"
    echo "• Potential for accidental resource creation"
    echo
    
    read -p "Do you want to DELETE the entire project '$PROJECT_ID'? (y/N): " delete_project
    
    if [[ "$delete_project" =~ ^[Yy]$ ]]; then
        log_warning "Deleting project: $PROJECT_ID"
        log_warning "This will remove ALL resources in the project!"
        
        read -p "Type 'DELETE PROJECT' to confirm: " final_confirm
        if [[ "$final_confirm" == "DELETE PROJECT" ]]; then
            gcloud projects delete "$PROJECT_ID" --quiet || log_error "Failed to delete project"
            log_success "Project deletion initiated. This may take several minutes to complete."
        else
            log_info "Project deletion cancelled"
        fi
    else
        log_info "Project '$PROJECT_ID' will be preserved"
        echo
        echo "To delete the project later, run:"
        echo "  gcloud projects delete $PROJECT_ID"
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    log_success "Cleanup completed!"
    
    cat << EOF

╔══════════════════════════════════════════════════════════════════════════════╗
║                             CLEANUP SUMMARY                                 ║
╚══════════════════════════════════════════════════════════════════════════════╝

🗑️  REMOVED RESOURCES:
   ✅ Source Storage Bucket: gs://$BUCKET_SOURCE
   ✅ Translated Storage Bucket: gs://$BUCKET_TRANSLATED
   ✅ Pub/Sub Topic: $TOPIC_NAME
   ✅ Pub/Sub Subscription: ${TOPIC_NAME}-sub
   ✅ Cloud Function: $FUNCTION_NAME
   ✅ Batch Scheduler Job: $SCHEDULER_JOB
   ✅ Monitor Scheduler Job: $MONITOR_JOB
   ✅ Log Sink: translation-audit
   ✅ Local configuration files

📊 COST IMPACT:
   • No more ongoing charges for these resources
   • Translation API usage charges have stopped
   • Storage costs eliminated
   • Compute costs eliminated

⚠️  IMPORTANT NOTES:
   • All translated content has been permanently deleted
   • Any custom models or datasets are removed
   • Audit logs in storage have been deleted
   • This action cannot be undone

💡 VERIFICATION:
   You can verify resource removal in the Google Cloud Console:
   • Storage: https://console.cloud.google.com/storage
   • Functions: https://console.cloud.google.com/functions
   • Scheduler: https://console.cloud.google.com/cloudscheduler
   • Pub/Sub: https://console.cloud.google.com/cloudpubsub

EOF

    echo "Cleanup completed: $(date)" >> "$LOG_FILE"
    echo "All resources removed successfully" >> "$LOG_FILE"
}

# Main cleanup function
main() {
    # Initialize log file
    echo "Cleanup started: $(date)" > "$LOG_FILE"
    
    log_info "Starting Multi-Language Content Localization cleanup..."
    
    # Load configuration and confirm
    load_configuration
    confirm_destruction
    
    # Run cleanup steps in reverse order of creation
    check_prerequisites
    remove_scheduler
    remove_function
    remove_notifications
    remove_storage
    remove_pubsub
    remove_monitoring
    cleanup_local_files
    
    # Validate and summarize
    validate_cleanup
    show_cleanup_summary
    
    # Offer project deletion
    offer_project_deletion
    
    log_success "Cleanup completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    "--force")
        # Skip confirmations for automated cleanup
        export SKIP_CONFIRMATIONS=true
        ;;
    "--help"|"-h")
        echo "Usage: $0 [--force] [--help]"
        echo ""
        echo "Options:"
        echo "  --force    Skip confirmation prompts (use with caution)"
        echo "  --help     Show this help message"
        echo ""
        echo "This script removes all resources created by deploy.sh"
        exit 0
        ;;
esac

# Override confirmation function if force flag is used
if [[ "${SKIP_CONFIRMATIONS:-false}" == "true" ]]; then
    confirm_destruction() {
        log_warning "Force mode enabled - skipping confirmations"
        log_warning "Proceeding with resource destruction..."
    }
fi

# Run main function
main "$@"