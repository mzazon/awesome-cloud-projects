#!/bin/bash

# Medical Imaging Analysis with Cloud Healthcare API and Vision AI - Cleanup Script
# This script removes all resources created by the medical imaging analysis pipeline

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

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling function
handle_error() {
    log_error "Cleanup failed at line $1"
    log_error "Some resources may not have been deleted. Please check manually."
    exit 1
}

trap 'handle_error $LINENO' ERR

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
        log_error "Google Cloud Storage utility (gsutil) is not installed."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Setup environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # If no project is set, try to get it from current gcloud config
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "PROJECT_ID not set and no default project configured"
            log_error "Please set PROJECT_ID environment variable or run 'gcloud config set project YOUR_PROJECT_ID'"
            exit 1
        fi
    fi
    
    # Project configuration
    export PROJECT_ID="${PROJECT_ID}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Healthcare API resources
    export DATASET_ID="${DATASET_ID:-medical-imaging-dataset}"
    export DICOM_STORE_ID="${DICOM_STORE_ID:-medical-dicom-store}"
    export FHIR_STORE_ID="${FHIR_STORE_ID:-medical-fhir-store}"
    
    # Other resources - we'll discover these if not provided
    export FUNCTION_NAME="${FUNCTION_NAME:-medical-image-processor}"
    export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-medical-imaging-sa}"
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Environment variables configured"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
}

# Discover bucket names if not provided
discover_resources() {
    log_info "Discovering resources to delete..."
    
    # Find bucket names if not provided
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_info "Discovering storage buckets..."
        local buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "medical-imaging-bucket" || echo "")
        if [[ -n "$buckets" ]]; then
            BUCKET_NAME=$(echo "$buckets" | head -1 | sed 's|gs://||' | sed 's|/||')
            log_info "Found bucket: ${BUCKET_NAME}"
        else
            log_warn "No medical imaging buckets found"
            BUCKET_NAME=""
        fi
    fi
    
    log_success "Resource discovery completed"
}

# Confirmation prompt
confirm_deletion() {
    log_warn "=== RESOURCE DELETION CONFIRMATION ==="
    echo
    log_warn "This script will DELETE the following resources:"
    echo "  - Project: ${PROJECT_ID}"
    echo "  - Healthcare Dataset: ${DATASET_ID}"
    echo "  - DICOM Store: ${DICOM_STORE_ID}"
    echo "  - FHIR Store: ${FHIR_STORE_ID}"
    echo "  - Cloud Function: ${FUNCTION_NAME}"
    echo "  - Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        echo "  - Storage Bucket: gs://${BUCKET_NAME}"
    fi
    echo "  - Pub/Sub Topic: medical-image-processing"
    echo "  - Pub/Sub Subscription: medical-image-processor-sub"
    echo "  - Log-based metrics and monitoring resources"
    echo
    log_error "THIS ACTION CANNOT BE UNDONE!"
    echo
    
    # Get user confirmation
    read -p "Are you sure you want to delete these resources? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_warn "Proceeding with resource deletion..."
}

# Delete Cloud Function and related resources
delete_cloud_function() {
    log_info "Deleting Cloud Function and related resources..."
    
    # Delete Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --gen2 &>/dev/null; then
        log_info "Deleting Cloud Function: ${FUNCTION_NAME}"
        if gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --gen2 \
            --quiet; then
            log_success "Cloud Function deleted successfully"
        else
            log_warn "Failed to delete Cloud Function or it may not exist"
        fi
    else
        log_info "Cloud Function ${FUNCTION_NAME} not found, skipping"
    fi
    
    log_success "Cloud Function cleanup completed"
}

# Delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    # Delete Pub/Sub subscription
    if gcloud pubsub subscriptions describe medical-image-processor-sub &>/dev/null; then
        log_info "Deleting Pub/Sub subscription: medical-image-processor-sub"
        if gcloud pubsub subscriptions delete medical-image-processor-sub --quiet; then
            log_success "Pub/Sub subscription deleted successfully"
        else
            log_warn "Failed to delete Pub/Sub subscription"
        fi
    else
        log_info "Pub/Sub subscription not found, skipping"
    fi
    
    # Delete Pub/Sub topic
    if gcloud pubsub topics describe medical-image-processing &>/dev/null; then
        log_info "Deleting Pub/Sub topic: medical-image-processing"
        if gcloud pubsub topics delete medical-image-processing --quiet; then
            log_success "Pub/Sub topic deleted successfully"
        else
            log_warn "Failed to delete Pub/Sub topic"
        fi
    else
        log_info "Pub/Sub topic not found, skipping"
    fi
    
    log_success "Pub/Sub resources cleanup completed"
}

# Delete Healthcare API resources
delete_healthcare_resources() {
    log_info "Deleting Healthcare API resources..."
    
    # Delete DICOM store
    if gcloud healthcare dicom-stores describe "${DICOM_STORE_ID}" \
        --dataset="${DATASET_ID}" \
        --location="${REGION}" &>/dev/null; then
        log_info "Deleting DICOM store: ${DICOM_STORE_ID}"
        if gcloud healthcare dicom-stores delete "${DICOM_STORE_ID}" \
            --dataset="${DATASET_ID}" \
            --location="${REGION}" \
            --quiet; then
            log_success "DICOM store deleted successfully"
        else
            log_warn "Failed to delete DICOM store"
        fi
    else
        log_info "DICOM store not found, skipping"
    fi
    
    # Delete FHIR store
    if gcloud healthcare fhir-stores describe "${FHIR_STORE_ID}" \
        --dataset="${DATASET_ID}" \
        --location="${REGION}" &>/dev/null; then
        log_info "Deleting FHIR store: ${FHIR_STORE_ID}"
        if gcloud healthcare fhir-stores delete "${FHIR_STORE_ID}" \
            --dataset="${DATASET_ID}" \
            --location="${REGION}" \
            --quiet; then
            log_success "FHIR store deleted successfully"
        else
            log_warn "Failed to delete FHIR store"
        fi
    else
        log_info "FHIR store not found, skipping"
    fi
    
    # Delete healthcare dataset
    if gcloud healthcare datasets describe "${DATASET_ID}" \
        --location="${REGION}" &>/dev/null; then
        log_info "Deleting healthcare dataset: ${DATASET_ID}"
        if gcloud healthcare datasets delete "${DATASET_ID}" \
            --location="${REGION}" \
            --quiet; then
            log_success "Healthcare dataset deleted successfully"
        else
            log_warn "Failed to delete healthcare dataset"
        fi
    else
        log_info "Healthcare dataset not found, skipping"
    fi
    
    log_success "Healthcare API resources cleanup completed"
}

# Delete Cloud Storage bucket
delete_storage_bucket() {
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log_info "Deleting Cloud Storage bucket..."
        
        # Check if bucket exists
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            log_info "Deleting bucket contents and bucket: gs://${BUCKET_NAME}"
            
            # Delete all objects in bucket (including versioned objects)
            log_info "Removing all objects from bucket..."
            gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true
            
            # Remove bucket
            if gsutil rb "gs://${BUCKET_NAME}"; then
                log_success "Storage bucket deleted successfully"
            else
                log_warn "Failed to delete storage bucket"
            fi
        else
            log_info "Storage bucket not found, skipping"
        fi
    else
        log_info "No bucket name provided, skipping storage cleanup"
    fi
    
    log_success "Storage cleanup completed"
}

# Delete service account and IAM bindings
delete_service_account() {
    log_info "Deleting service account and IAM bindings..."
    
    local service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "${service_account_email}" &>/dev/null; then
        log_info "Removing IAM policy bindings..."
        
        # Remove IAM policy bindings (non-fatal if they fail)
        local roles=(
            "roles/healthcare.datasetAdmin"
            "roles/ml.developer"
            "roles/storage.objectAdmin"
            "roles/cloudfunctions.developer"
            "roles/pubsub.editor"
        )
        
        for role in "${roles[@]}"; do
            log_info "Removing role: ${role}"
            gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${service_account_email}" \
                --role="${role}" \
                --quiet 2>/dev/null || log_warn "Failed to remove role ${role} or it may not exist"
        done
        
        # Delete service account
        log_info "Deleting service account: ${service_account_email}"
        if gcloud iam service-accounts delete "${service_account_email}" --quiet; then
            log_success "Service account deleted successfully"
        else
            log_warn "Failed to delete service account"
        fi
    else
        log_info "Service account not found, skipping"
    fi
    
    log_success "Service account cleanup completed"
}

# Delete monitoring and logging resources
delete_monitoring_resources() {
    log_info "Deleting monitoring and logging resources..."
    
    # Delete log-based metrics
    if gcloud logging metrics describe medical_image_processing_success &>/dev/null; then
        log_info "Deleting log-based metric: medical_image_processing_success"
        if gcloud logging metrics delete medical_image_processing_success --quiet; then
            log_success "Log-based metric deleted successfully"
        else
            log_warn "Failed to delete log-based metric"
        fi
    else
        log_info "Log-based metric not found, skipping"
    fi
    
    log_success "Monitoring resources cleanup completed"
}

# Delete the entire project (optional)
delete_project() {
    local delete_project_flag="${DELETE_PROJECT:-false}"
    
    if [[ "$delete_project_flag" == "true" ]]; then
        log_warn "Deleting entire project: ${PROJECT_ID}"
        echo
        log_error "THIS WILL DELETE THE ENTIRE PROJECT AND ALL ITS RESOURCES!"
        read -p "Are you absolutely sure you want to delete the entire project? (type 'DELETE_PROJECT' to confirm): " project_confirmation
        
        if [[ "$project_confirmation" == "DELETE_PROJECT" ]]; then
            log_info "Deleting project: ${PROJECT_ID}"
            if gcloud projects delete "${PROJECT_ID}" --quiet; then
                log_success "Project deleted successfully"
                log_info "All resources have been removed"
                return 0
            else
                log_error "Failed to delete project"
                exit 1
            fi
        else
            log_info "Project deletion cancelled"
        fi
    else
        log_info "Project deletion skipped (set DELETE_PROJECT=true to delete entire project)"
    fi
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local cleanup_success=true
    
    # Check healthcare dataset
    if gcloud healthcare datasets describe "${DATASET_ID}" --location="${REGION}" &>/dev/null; then
        log_warn "Healthcare dataset still exists"
        cleanup_success=false
    else
        log_success "Healthcare dataset successfully removed"
    fi
    
    # Check Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --gen2 &>/dev/null; then
        log_warn "Cloud Function still exists"
        cleanup_success=false
    else
        log_success "Cloud Function successfully removed"
    fi
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe medical-image-processing &>/dev/null; then
        log_warn "Pub/Sub topic still exists"
        cleanup_success=false
    else
        log_success "Pub/Sub topic successfully removed"
    fi
    
    # Check storage bucket
    if [[ -n "${BUCKET_NAME:-}" ]] && gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warn "Storage bucket still exists"
        cleanup_success=false
    else
        log_success "Storage bucket successfully removed"
    fi
    
    # Check service account
    local service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "${service_account_email}" &>/dev/null; then
        log_warn "Service account still exists"
        cleanup_success=false
    else
        log_success "Service account successfully removed"
    fi
    
    if [[ "$cleanup_success" == "true" ]]; then
        log_success "All resources successfully cleaned up"
    else
        log_warn "Some resources may still exist. Please check manually in the Google Cloud Console."
    fi
}

# Display cleanup summary
display_summary() {
    log_success "=== CLEANUP COMPLETED ==="
    echo
    log_info "Medical Imaging Analysis Pipeline Cleanup Summary:"
    echo "  - Healthcare API resources: Removed"
    echo "  - Cloud Function: Removed"
    echo "  - Pub/Sub resources: Removed"
    echo "  - Storage bucket: Removed"
    echo "  - Service account: Removed"
    echo "  - Monitoring resources: Removed"
    echo
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        log_info "Project ${PROJECT_ID} has been deleted"
    else
        log_info "Project ${PROJECT_ID} has been preserved"
        log_info "To delete the entire project, run: DELETE_PROJECT=true $0"
    fi
    echo
    log_success "Cleanup process completed!"
}

# Main cleanup function
main() {
    log_info "Starting Medical Imaging Analysis Pipeline Cleanup"
    echo "======================================================="
    
    check_prerequisites
    setup_environment
    discover_resources
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_cloud_function
    delete_pubsub_resources
    delete_service_account
    delete_storage_bucket
    delete_healthcare_resources
    delete_monitoring_resources
    
    # Optional project deletion
    delete_project
    
    verify_cleanup
    display_summary
    
    log_success "Cleanup completed successfully!"
}

# Handle script arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$#" -eq 1 && "$1" == "--help" ]]; then
        echo "Usage: $0 [--help]"
        echo
        echo "Delete Medical Imaging Analysis Pipeline resources from Google Cloud Platform"
        echo
        echo "Environment Variables (optional):"
        echo "  PROJECT_ID          - GCP project ID (default: current gcloud project)"
        echo "  REGION             - GCP region (default: us-central1)"
        echo "  DATASET_ID         - Healthcare dataset ID (default: medical-imaging-dataset)"
        echo "  BUCKET_NAME        - Storage bucket name (default: auto-discover)"
        echo "  DELETE_PROJECT     - Delete entire project (default: false)"
        echo
        echo "Examples:"
        echo "  # Delete resources but keep project"
        echo "  export PROJECT_ID=my-medical-project"
        echo "  $0"
        echo
        echo "  # Delete entire project and all resources"
        echo "  export PROJECT_ID=my-medical-project"
        echo "  export DELETE_PROJECT=true"
        echo "  $0"
        echo
        echo "WARNING: This operation is irreversible!"
        exit 0
    fi
    
    main "$@"
fi