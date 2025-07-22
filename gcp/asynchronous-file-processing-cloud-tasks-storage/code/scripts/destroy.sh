#!/bin/bash

# Asynchronous File Processing with Cloud Tasks and Cloud Storage - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
CONFIG_FILE="${SCRIPT_DIR}/deployment_config.env"

# Default values
FORCE_DELETE="false"
SKIP_CONFIRMATION="false"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE="true"
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "  --force    Force deletion without additional confirmations"
            echo "  --yes      Skip confirmation prompts"
            echo "  --help     Show this help message"
            echo ""
            echo "This script will remove all resources created by deploy.sh"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load configuration from deployment
load_configuration() {
    log_info "Loading deployment configuration..."
    
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log_success "Configuration loaded from $CONFIG_FILE"
        echo "  - Project ID: $PROJECT_ID"
        echo "  - Region: $REGION"
        echo "  - Upload Bucket: $UPLOAD_BUCKET"
        echo "  - Results Bucket: $RESULTS_BUCKET"
        echo "  - Pub/Sub Topic: $PUBSUB_TOPIC"
        echo "  - Task Queue: $TASK_QUEUE"
    else
        log_error "Configuration file not found: $CONFIG_FILE"
        echo "Please ensure deploy.sh has been run successfully first."
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "Google Cloud SDK (gsutil) is not installed."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Google Cloud CLI is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    
    log_success "Prerequisites check passed"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "⚠️  WARNING: This will delete all resources created by the deployment script!"
    echo ""
    echo "Resources to be deleted:"
    echo "  - Cloud Run services (upload-service, processing-service)"
    echo "  - Cloud Storage buckets and all contents ($UPLOAD_BUCKET, $RESULTS_BUCKET)"
    echo "  - Cloud Tasks queue ($TASK_QUEUE)"
    echo "  - Pub/Sub topic and subscription ($PUBSUB_TOPIC)"
    echo "  - Service accounts and IAM bindings"
    echo "  - Container images in Container Registry"
    echo ""
    echo "Project: $PROJECT_ID"
    echo "Region: $REGION"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    if [[ "$FORCE_DELETE" == "false" ]]; then
        echo ""
        read -p "This action cannot be undone. Type 'DELETE' to confirm: " -r
        if [[ ! $REPLY == "DELETE" ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    log_info "Proceeding with resource deletion..."
}

# Remove Cloud Run services
remove_cloud_run_services() {
    log_info "Removing Cloud Run services..."
    
    # Delete upload service
    log_info "Deleting upload service..."
    if gcloud run services delete upload-service \
        --region "$REGION" \
        --quiet &>/dev/null; then
        log_success "Upload service deleted"
    else
        log_warning "Upload service may not exist or already deleted"
    fi
    
    # Delete processing service
    log_info "Deleting processing service..."
    if gcloud run services delete processing-service \
        --region "$REGION" \
        --quiet &>/dev/null; then
        log_success "Processing service deleted"
    else
        log_warning "Processing service may not exist or already deleted"
    fi
    
    log_success "Cloud Run services cleanup completed"
}

# Remove Cloud Tasks queue
remove_task_queue() {
    log_info "Removing Cloud Tasks queue..."
    
    # Delete task queue
    if gcloud tasks queues delete "$TASK_QUEUE" \
        --location "$REGION" \
        --quiet &>/dev/null; then
        log_success "Task queue deleted: $TASK_QUEUE"
    else
        log_warning "Task queue may not exist or already deleted"
    fi
    
    log_success "Cloud Tasks queue cleanup completed"
}

# Remove Cloud Storage resources
remove_storage_resources() {
    log_info "Removing Cloud Storage resources..."
    
    # Remove upload bucket
    log_info "Removing upload bucket and contents: $UPLOAD_BUCKET"
    if gsutil ls -b "gs://${UPLOAD_BUCKET}" &>/dev/null; then
        # Remove all objects including versions
        gsutil -m rm -r "gs://${UPLOAD_BUCKET}/**" &>/dev/null || true
        # Remove bucket
        if gsutil rb "gs://${UPLOAD_BUCKET}" &>/dev/null; then
            log_success "Upload bucket deleted: $UPLOAD_BUCKET"
        else
            log_warning "Failed to delete upload bucket, may contain objects"
        fi
    else
        log_warning "Upload bucket does not exist or already deleted"
    fi
    
    # Remove results bucket
    log_info "Removing results bucket and contents: $RESULTS_BUCKET"
    if gsutil ls -b "gs://${RESULTS_BUCKET}" &>/dev/null; then
        # Remove all objects including versions
        gsutil -m rm -r "gs://${RESULTS_BUCKET}/**" &>/dev/null || true
        # Remove bucket
        if gsutil rb "gs://${RESULTS_BUCKET}" &>/dev/null; then
            log_success "Results bucket deleted: $RESULTS_BUCKET"
        else
            log_warning "Failed to delete results bucket, may contain objects"
        fi
    else
        log_warning "Results bucket does not exist or already deleted"
    fi
    
    log_success "Cloud Storage resources cleanup completed"
}

# Remove Pub/Sub resources
remove_pubsub_resources() {
    log_info "Removing Pub/Sub resources..."
    
    # Delete subscription first
    log_info "Deleting Pub/Sub subscription: ${PUBSUB_TOPIC}-subscription"
    if gcloud pubsub subscriptions delete "${PUBSUB_TOPIC}-subscription" \
        --quiet &>/dev/null; then
        log_success "Pub/Sub subscription deleted"
    else
        log_warning "Pub/Sub subscription may not exist or already deleted"
    fi
    
    # Delete topic
    log_info "Deleting Pub/Sub topic: $PUBSUB_TOPIC"
    if gcloud pubsub topics delete "$PUBSUB_TOPIC" \
        --quiet &>/dev/null; then
        log_success "Pub/Sub topic deleted"
    else
        log_warning "Pub/Sub topic may not exist or already deleted"
    fi
    
    log_success "Pub/Sub resources cleanup completed"
}

# Remove service accounts and IAM bindings
remove_service_accounts() {
    log_info "Removing service accounts and IAM bindings..."
    
    # Remove IAM bindings for upload service
    log_info "Removing IAM bindings for upload service..."
    gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:upload-service-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/storage.objectAdmin" \
        --quiet &>/dev/null || true
    
    gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:upload-service-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/cloudtasks.enqueuer" \
        --quiet &>/dev/null || true
    
    # Remove IAM bindings for processing service
    log_info "Removing IAM bindings for processing service..."
    gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:processing-service-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/storage.objectAdmin" \
        --quiet &>/dev/null || true
    
    # Remove IAM binding for Cloud Storage service account
    log_info "Removing IAM binding for Cloud Storage service account..."
    GCS_SERVICE_ACCOUNT=$(gsutil kms serviceaccount -p "$PROJECT_ID" 2>/dev/null || echo "")
    if [[ -n "$GCS_SERVICE_ACCOUNT" ]]; then
        gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:${GCS_SERVICE_ACCOUNT}" \
            --role="roles/pubsub.publisher" \
            --quiet &>/dev/null || true
    fi
    
    # Delete service accounts
    log_info "Deleting upload service account..."
    if gcloud iam service-accounts delete \
        "upload-service-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --quiet &>/dev/null; then
        log_success "Upload service account deleted"
    else
        log_warning "Upload service account may not exist or already deleted"
    fi
    
    log_info "Deleting processing service account..."
    if gcloud iam service-accounts delete \
        "processing-service-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --quiet &>/dev/null; then
        log_success "Processing service account deleted"
    else
        log_warning "Processing service account may not exist or already deleted"
    fi
    
    log_success "Service accounts and IAM bindings cleanup completed"
}

# Remove container images
remove_container_images() {
    log_info "Removing container images..."
    
    # Delete upload service image
    log_info "Deleting upload service container image..."
    if gcloud container images delete "gcr.io/${PROJECT_ID}/upload-service" \
        --quiet &>/dev/null; then
        log_success "Upload service container image deleted"
    else
        log_warning "Upload service container image may not exist or already deleted"
    fi
    
    # Delete processing service image
    log_info "Deleting processing service container image..."
    if gcloud container images delete "gcr.io/${PROJECT_ID}/processing-service" \
        --quiet &>/dev/null; then
        log_success "Processing service container image deleted"
    else
        log_warning "Processing service container image may not exist or already deleted"
    fi
    
    log_success "Container images cleanup completed"
}

# Remove local files
remove_local_files() {
    log_info "Removing local files..."
    
    # Remove service directories
    if [[ -d "${PROJECT_ROOT}/upload-service" ]]; then
        rm -rf "${PROJECT_ROOT}/upload-service"
        log_success "Upload service directory removed"
    fi
    
    if [[ -d "${PROJECT_ROOT}/processing-service" ]]; then
        rm -rf "${PROJECT_ROOT}/processing-service"
        log_success "Processing service directory removed"
    fi
    
    # Remove configuration file
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
        log_success "Configuration file removed"
    fi
    
    # Remove any test files
    local test_files=("test-image.jpg" "invalid-file.txt")
    for file in "${test_files[@]}"; do
        if [[ -f "${PROJECT_ROOT}/$file" ]]; then
            rm -f "${PROJECT_ROOT}/$file"
            log_success "Test file removed: $file"
        fi
    done
    
    log_success "Local files cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local failed_checks=0
    
    # Check Cloud Run services
    if gcloud run services describe upload-service --region "$REGION" &>/dev/null; then
        log_warning "Upload service still exists"
        ((failed_checks++))
    fi
    
    if gcloud run services describe processing-service --region "$REGION" &>/dev/null; then
        log_warning "Processing service still exists"
        ((failed_checks++))
    fi
    
    # Check Cloud Storage buckets
    if gsutil ls -b "gs://${UPLOAD_BUCKET}" &>/dev/null; then
        log_warning "Upload bucket still exists"
        ((failed_checks++))
    fi
    
    if gsutil ls -b "gs://${RESULTS_BUCKET}" &>/dev/null; then
        log_warning "Results bucket still exists"
        ((failed_checks++))
    fi
    
    # Check Pub/Sub resources
    if gcloud pubsub topics describe "$PUBSUB_TOPIC" &>/dev/null; then
        log_warning "Pub/Sub topic still exists"
        ((failed_checks++))
    fi
    
    # Check Cloud Tasks queue
    if gcloud tasks queues describe "$TASK_QUEUE" --location "$REGION" &>/dev/null; then
        log_warning "Task queue still exists"
        ((failed_checks++))
    fi
    
    # Check service accounts
    if gcloud iam service-accounts describe "upload-service-sa@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        log_warning "Upload service account still exists"
        ((failed_checks++))
    fi
    
    if gcloud iam service-accounts describe "processing-service-sa@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        log_warning "Processing service account still exists"
        ((failed_checks++))
    fi
    
    if [[ $failed_checks -eq 0 ]]; then
        log_success "All resources have been successfully removed"
    else
        log_warning "$failed_checks resources may still exist or require manual cleanup"
    fi
    
    log_success "Cleanup verification completed"
}

# Display cleanup summary
display_summary() {
    log_success "Cleanup completed!"
    echo ""
    echo "=================================================="
    echo "CLEANUP SUMMARY"
    echo "=================================================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo ""
    echo "Resources Removed:"
    echo "  ✅ Cloud Run services (upload-service, processing-service)"
    echo "  ✅ Cloud Storage buckets ($UPLOAD_BUCKET, $RESULTS_BUCKET)"
    echo "  ✅ Cloud Tasks queue ($TASK_QUEUE)"
    echo "  ✅ Pub/Sub topic and subscription ($PUBSUB_TOPIC)"
    echo "  ✅ Service accounts and IAM bindings"
    echo "  ✅ Container images"
    echo "  ✅ Local files and directories"
    echo ""
    echo "Notes:"
    echo "  - Google Cloud APIs remain enabled"
    echo "  - Some IAM bindings may take time to propagate"
    echo "  - Check Cloud Console for any remaining resources"
    echo ""
    echo "To verify no charges are incurred, review:"
    echo "  - Cloud Console Billing dashboard"
    echo "  - Cloud Console Resource Manager"
    echo "=================================================="
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Asynchronous File Processing system..."
    echo ""
    
    # Load configuration and check prerequisites
    load_configuration
    check_prerequisites
    
    # Confirm deletion
    confirm_deletion
    
    # Execute cleanup steps
    remove_cloud_run_services
    remove_task_queue
    remove_storage_resources
    remove_pubsub_resources
    remove_service_accounts
    remove_container_images
    remove_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_summary
    
    log_success "Cleanup completed successfully!"
}

# Error handling
trap 'log_error "An error occurred during cleanup. Some resources may still exist."; exit 1' ERR

# Run main function
main "$@"