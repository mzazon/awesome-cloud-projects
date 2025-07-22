#!/bin/bash

# Destroy Visual Document Processing with Cloud Filestore and Vision AI
# This script safely removes all infrastructure created for the document processing solution
# including Cloud Functions, Filestore, Pub/Sub, Storage, and Compute instances

set -euo pipefail

# Color codes for output formatting
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

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code $exit_code"
    log_warning "Some resources may still exist. Please check manually."
    exit $exit_code
}

trap cleanup_on_error ERR

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ ! -f .deployment_state ]]; then
        log_warning "No deployment state file found (.deployment_state)"
        log_warning "You may need to specify resource names manually"
        
        # Try to use environment variables or defaults
        export PROJECT_ID="${PROJECT_ID:-}"
        export REGION="${REGION:-us-central1}"
        export ZONE="${ZONE:-us-central1-a}"
        export FILESTORE_INSTANCE="${FILESTORE_INSTANCE:-}"
        export MONITOR_FUNCTION="${MONITOR_FUNCTION:-}"
        export PROCESSOR_FUNCTION="${PROCESSOR_FUNCTION:-}"
        export PUBSUB_TOPIC="${PUBSUB_TOPIC:-}"
        export RESULTS_TOPIC="${RESULTS_TOPIC:-}"
        export STORAGE_BUCKET="${STORAGE_BUCKET:-}"
        
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "PROJECT_ID not found. Please set it or provide deployment state file."
            exit 1
        fi
        
        return 0
    fi
    
    # Source the deployment state file
    source .deployment_state
    
    log_success "Loaded deployment state for project: $PROJECT_ID"
    log_info "Deployment time: ${DEPLOYMENT_TIME:-unknown}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available"
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_error "Run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Configure Google Cloud project
configure_project() {
    log_info "Configuring Google Cloud project..."
    
    # Set default project and region
    gcloud config set project ${PROJECT_ID} || {
        log_error "Failed to set project. Make sure project exists and you have access."
        exit 1
    }
    gcloud config set compute/region ${REGION}
    gcloud config set compute/zone ${ZONE}
    
    log_success "Project configuration completed"
}

# Confirmation prompt
confirm_destruction() {
    echo
    log_warning "This will permanently delete the following resources:"
    echo "- Project: $PROJECT_ID"
    echo "- Filestore Instance: ${FILESTORE_INSTANCE:-unknown}"
    echo "- Cloud Functions: ${MONITOR_FUNCTION:-unknown}, ${PROCESSOR_FUNCTION:-unknown}"
    echo "- Pub/Sub Topics: ${PUBSUB_TOPIC:-unknown}, ${RESULTS_TOPIC:-unknown}"
    echo "- Storage Bucket: ${STORAGE_BUCKET:-unknown}"
    echo "- Compute Instance: filestore-client"
    echo
    
    # Check for force flag
    if [[ "${1:-}" == "--force" || "${FORCE_DESTROY:-}" == "true" ]]; then
        log_warning "Force flag detected, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Delete Cloud Functions
delete_functions() {
    log_info "Deleting Cloud Functions..."
    
    # Delete monitor function
    if [[ -n "${MONITOR_FUNCTION:-}" ]]; then
        if gcloud functions describe ${MONITOR_FUNCTION} --region=${REGION} &>/dev/null; then
            log_info "Deleting function: $MONITOR_FUNCTION"
            gcloud functions delete ${MONITOR_FUNCTION} \
                --region=${REGION} \
                --quiet
            log_success "Function $MONITOR_FUNCTION deleted"
        else
            log_warning "Function $MONITOR_FUNCTION not found"
        fi
    else
        log_warning "Monitor function name not specified"
    fi
    
    # Delete processor function
    if [[ -n "${PROCESSOR_FUNCTION:-}" ]]; then
        if gcloud functions describe ${PROCESSOR_FUNCTION} --region=${REGION} &>/dev/null; then
            log_info "Deleting function: $PROCESSOR_FUNCTION"
            gcloud functions delete ${PROCESSOR_FUNCTION} \
                --region=${REGION} \
                --quiet
            log_success "Function $PROCESSOR_FUNCTION deleted"
        else
            log_warning "Function $PROCESSOR_FUNCTION not found"
        fi
    else
        log_warning "Processor function name not specified"
    fi
    
    log_success "Cloud Functions cleanup completed"
}

# Delete Pub/Sub resources
delete_pubsub() {
    log_info "Deleting Pub/Sub topics and subscriptions..."
    
    # Delete subscriptions first
    local subscriptions=("document-processing-sub" "results-sub")
    for sub in "${subscriptions[@]}"; do
        if gcloud pubsub subscriptions describe $sub &>/dev/null; then
            log_info "Deleting subscription: $sub"
            gcloud pubsub subscriptions delete $sub --quiet
            log_success "Subscription $sub deleted"
        else
            log_warning "Subscription $sub not found"
        fi
    done
    
    # Delete topics
    for topic in "${PUBSUB_TOPIC:-}" "${RESULTS_TOPIC:-}"; do
        if [[ -n "$topic" ]]; then
            if gcloud pubsub topics describe $topic &>/dev/null; then
                log_info "Deleting topic: $topic"
                gcloud pubsub topics delete $topic --quiet
                log_success "Topic $topic deleted"
            else
                log_warning "Topic $topic not found"
            fi
        fi
    done
    
    log_success "Pub/Sub resources cleanup completed"
}

# Delete Compute Engine instance
delete_compute_instance() {
    log_info "Deleting Compute Engine instances..."
    
    # Delete filestore client instance
    if gcloud compute instances describe filestore-client --zone=${ZONE} &>/dev/null; then
        log_info "Deleting instance: filestore-client"
        gcloud compute instances delete filestore-client \
            --zone=${ZONE} \
            --quiet
        log_success "Instance filestore-client deleted"
    else
        log_warning "Instance filestore-client not found"
    fi
    
    log_success "Compute Engine instances cleanup completed"
}

# Delete Filestore instance
delete_filestore() {
    log_info "Deleting Cloud Filestore instance..."
    
    if [[ -n "${FILESTORE_INSTANCE:-}" ]]; then
        if gcloud filestore instances describe ${FILESTORE_INSTANCE} --zone=${ZONE} &>/dev/null; then
            log_info "Deleting Filestore instance: $FILESTORE_INSTANCE"
            gcloud filestore instances delete ${FILESTORE_INSTANCE} \
                --zone=${ZONE} \
                --quiet
            
            # Wait for deletion to complete
            log_info "Waiting for Filestore deletion to complete..."
            while gcloud filestore instances describe ${FILESTORE_INSTANCE} --zone=${ZONE} &>/dev/null; do
                sleep 30
                echo -n "."
            done
            echo
            
            log_success "Filestore instance $FILESTORE_INSTANCE deleted"
        else
            log_warning "Filestore instance $FILESTORE_INSTANCE not found"
        fi
    else
        log_warning "Filestore instance name not specified"
    fi
    
    log_success "Filestore cleanup completed"
}

# Delete Cloud Storage bucket
delete_storage() {
    log_info "Deleting Cloud Storage bucket..."
    
    if [[ -n "${STORAGE_BUCKET:-}" ]]; then
        if gsutil ls gs://${STORAGE_BUCKET} &>/dev/null; then
            log_info "Deleting storage bucket: $STORAGE_BUCKET"
            
            # Delete all objects first (including versions)
            gsutil -m rm -r gs://${STORAGE_BUCKET}/** 2>/dev/null || true
            
            # Delete the bucket
            gsutil rb gs://${STORAGE_BUCKET}
            
            log_success "Storage bucket $STORAGE_BUCKET deleted"
        else
            log_warning "Storage bucket $STORAGE_BUCKET not found"
        fi
    else
        log_warning "Storage bucket name not specified"
    fi
    
    log_success "Cloud Storage cleanup completed"
}

# Interactive resource discovery
discover_resources() {
    log_info "Discovering resources for cleanup..."
    
    # Try to find resources by pattern if not specified
    if [[ -z "${FILESTORE_INSTANCE:-}" ]]; then
        log_info "Searching for Filestore instances..."
        local instances=$(gcloud filestore instances list --filter="name~docs-filestore-" --format="value(name)" 2>/dev/null)
        if [[ -n "$instances" ]]; then
            echo "Found Filestore instances:"
            echo "$instances"
            read -p "Enter Filestore instance name to delete (or press Enter to skip): " FILESTORE_INSTANCE
        fi
    fi
    
    if [[ -z "${MONITOR_FUNCTION:-}" ]]; then
        log_info "Searching for Cloud Functions..."
        local functions=$(gcloud functions list --filter="name~file-monitor-" --format="value(name)" 2>/dev/null)
        if [[ -n "$functions" ]]; then
            echo "Found monitor functions:"
            echo "$functions"
            read -p "Enter monitor function name to delete (or press Enter to skip): " MONITOR_FUNCTION
        fi
    fi
    
    if [[ -z "${PROCESSOR_FUNCTION:-}" ]]; then
        local functions=$(gcloud functions list --filter="name~vision-processor-" --format="value(name)" 2>/dev/null)
        if [[ -n "$functions" ]]; then
            echo "Found processor functions:"
            echo "$functions"
            read -p "Enter processor function name to delete (or press Enter to skip): " PROCESSOR_FUNCTION
        fi
    fi
    
    if [[ -z "${PUBSUB_TOPIC:-}" ]]; then
        log_info "Searching for Pub/Sub topics..."
        local topics=$(gcloud pubsub topics list --filter="name~document-processing-" --format="value(name)" 2>/dev/null)
        if [[ -n "$topics" ]]; then
            echo "Found Pub/Sub topics:"
            echo "$topics"
            read -p "Enter primary topic name to delete (or press Enter to skip): " PUBSUB_TOPIC
        fi
    fi
    
    if [[ -z "${STORAGE_BUCKET:-}" ]]; then
        log_info "Searching for storage buckets..."
        local buckets=$(gsutil ls | grep "processed-docs" 2>/dev/null)
        if [[ -n "$buckets" ]]; then
            echo "Found storage buckets:"
            echo "$buckets"
            read -p "Enter bucket name to delete (without gs://, or press Enter to skip): " STORAGE_BUCKET
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment state file
    if [[ -f .deployment_state ]]; then
        rm .deployment_state
        log_success "Removed deployment state file"
    fi
    
    # Remove any temporary files
    rm -f /tmp/lifecycle.json 2>/dev/null || true
    
    log_success "Local files cleanup completed"
}

# Display destruction summary
display_summary() {
    log_success "Resource destruction completed!"
    
    echo
    echo "=== DESTRUCTION SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo
    echo "Resources Deleted:"
    echo "- Filestore Instance: ${FILESTORE_INSTANCE:-not specified}"
    echo "- Cloud Functions: ${MONITOR_FUNCTION:-not specified}, ${PROCESSOR_FUNCTION:-not specified}"
    echo "- Pub/Sub Topics: ${PUBSUB_TOPIC:-not specified}, ${RESULTS_TOPIC:-not specified}"
    echo "- Storage Bucket: ${STORAGE_BUCKET:-not specified}"
    echo "- Compute Instance: filestore-client"
    echo "- Local deployment state file"
    echo
    echo "All resources have been successfully removed."
    echo "You may want to check the Google Cloud Console to verify complete cleanup."
}

# Main destruction function
main() {
    echo "=== Visual Document Processing Destruction ==="
    echo "Starting cleanup of Filestore and Vision AI infrastructure..."
    echo
    
    # Load state and check prerequisites
    load_deployment_state
    check_prerequisites
    configure_project
    
    # If no deployment state found, try to discover resources
    if [[ ! -f .deployment_state ]]; then
        discover_resources
    fi
    
    # Confirm destruction
    confirm_destruction "$@"
    
    # Execute destruction steps in reverse order of creation
    delete_functions
    delete_pubsub
    delete_compute_instance
    delete_filestore
    delete_storage
    cleanup_local_files
    display_summary
    
    log_success "All destruction steps completed successfully!"
}

# Run main function with all arguments
main "$@"