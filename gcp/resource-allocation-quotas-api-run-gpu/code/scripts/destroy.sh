#!/bin/bash

# Resource Allocation with Cloud Quotas API and Cloud Run GPU - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ -f ".deployment_info" ]]; then
        source .deployment_info
        log_info "Loaded deployment info from .deployment_info"
        log_info "Project: ${PROJECT_ID}, Region: ${REGION}, Suffix: ${RANDOM_SUFFIX}"
    else
        log_warning "No .deployment_info file found. Attempting to gather information..."
        
        # Try to get project from gcloud config
        export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "No project ID available. Cannot proceed with cleanup."
            exit 1
        fi
        
        export REGION="${REGION:-us-central1}"
        
        log_warning "Will attempt to clean up resources with partial information."
        log_warning "Some resources may not be found if they were created with different names."
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "This script will delete the following resources:"
    echo "- Cloud Scheduler Jobs (if they exist)"
    echo "- Cloud Run Services (if they exist)"
    echo "- Container Images (if they exist)"
    echo "- Cloud Functions (if they exist)"
    echo "- Cloud Storage Buckets and contents (if they exist)"
    echo "- Temporary local directories and files"
    echo ""
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    
    if [[ -n "${FUNCTION_NAME}" ]]; then
        echo "Function: ${FUNCTION_NAME}"
    fi
    if [[ -n "${SERVICE_NAME}" ]]; then
        echo "Service: ${SERVICE_NAME}"
    fi
    if [[ -n "${BUCKET_NAME}" ]]; then
        echo "Bucket: ${BUCKET_NAME}"
    fi
    
    echo ""
    log_warning "Firestore database will NOT be deleted automatically for safety."
    echo ""
    
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log_info "Deleting Cloud Scheduler jobs..."
    
    # Delete jobs by pattern if names are known
    if [[ -n "${JOB_NAME}" ]]; then
        log_info "Deleting job: ${JOB_NAME}"
        if gcloud scheduler jobs delete "${JOB_NAME}" --location="${REGION}" --quiet 2>/dev/null; then
            log_success "Deleted job: ${JOB_NAME}"
        else
            log_warning "Job ${JOB_NAME} not found or already deleted"
        fi
    fi
    
    if [[ -n "${PEAK_JOB_NAME}" ]]; then
        log_info "Deleting job: ${PEAK_JOB_NAME}"
        if gcloud scheduler jobs delete "${PEAK_JOB_NAME}" --location="${REGION}" --quiet 2>/dev/null; then
            log_success "Deleted job: ${PEAK_JOB_NAME}"
        else
            log_warning "Job ${PEAK_JOB_NAME} not found or already deleted"
        fi
    fi
    
    # Delete any jobs with quota-analysis pattern
    log_info "Searching for quota analysis jobs..."
    local jobs=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" --filter="name:quota-analysis" 2>/dev/null || echo "")
    
    if [[ -n "$jobs" ]]; then
        while IFS= read -r job; do
            if [[ -n "$job" ]]; then
                local job_name=$(basename "$job")
                log_info "Deleting job: ${job_name}"
                if gcloud scheduler jobs delete "${job_name}" --location="${REGION}" --quiet 2>/dev/null; then
                    log_success "Deleted job: ${job_name}"
                else
                    log_warning "Failed to delete job: ${job_name}"
                fi
            fi
        done <<< "$jobs"
    fi
    
    # Delete any jobs with peak-analysis pattern
    local peak_jobs=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" --filter="name:peak-analysis" 2>/dev/null || echo "")
    
    if [[ -n "$peak_jobs" ]]; then
        while IFS= read -r job; do
            if [[ -n "$job" ]]; then
                local job_name=$(basename "$job")
                log_info "Deleting job: ${job_name}"
                if gcloud scheduler jobs delete "${job_name}" --location="${REGION}" --quiet 2>/dev/null; then
                    log_success "Deleted job: ${job_name}"
                else
                    log_warning "Failed to delete job: ${job_name}"
                fi
            fi
        done <<< "$peak_jobs"
    fi
    
    log_success "Cloud Scheduler jobs cleanup completed"
}

# Function to delete Cloud Run services
delete_cloud_run_services() {
    log_info "Deleting Cloud Run services..."
    
    # Delete service by name if known
    if [[ -n "${SERVICE_NAME}" ]]; then
        log_info "Deleting service: ${SERVICE_NAME}"
        if gcloud run services delete "${SERVICE_NAME}" --region="${REGION}" --quiet 2>/dev/null; then
            log_success "Deleted service: ${SERVICE_NAME}"
        else
            log_warning "Service ${SERVICE_NAME} not found or already deleted"
        fi
    fi
    
    # Delete any services with ai-inference pattern
    log_info "Searching for AI inference services..."
    local services=$(gcloud run services list --region="${REGION}" --format="value(metadata.name)" --filter="metadata.name:ai-inference" 2>/dev/null || echo "")
    
    if [[ -n "$services" ]]; then
        while IFS= read -r service; do
            if [[ -n "$service" ]]; then
                log_info "Deleting service: ${service}"
                if gcloud run services delete "${service}" --region="${REGION}" --quiet 2>/dev/null; then
                    log_success "Deleted service: ${service}"
                else
                    log_warning "Failed to delete service: ${service}"
                fi
            fi
        done <<< "$services"
    fi
    
    log_success "Cloud Run services cleanup completed"
}

# Function to delete container images
delete_container_images() {
    log_info "Deleting container images..."
    
    # Delete image by name if known
    if [[ -n "${SERVICE_NAME}" ]]; then
        local image_url="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"
        log_info "Deleting image: ${image_url}"
        if gcloud container images delete "${image_url}" --quiet --force-delete-tags 2>/dev/null; then
            log_success "Deleted image: ${image_url}"
        else
            log_warning "Image ${image_url} not found or already deleted"
        fi
    fi
    
    # Delete any images with ai-inference pattern
    log_info "Searching for AI inference images..."
    local images=$(gcloud container images list --repository="gcr.io/${PROJECT_ID}" --format="value(name)" --filter="name:ai-inference" 2>/dev/null || echo "")
    
    if [[ -n "$images" ]]; then
        while IFS= read -r image; do
            if [[ -n "$image" ]]; then
                log_info "Deleting image: ${image}"
                if gcloud container images delete "${image}" --quiet --force-delete-tags 2>/dev/null; then
                    log_success "Deleted image: ${image}"
                else
                    log_warning "Failed to delete image: ${image}"
                fi
            fi
        done <<< "$images"
    fi
    
    log_success "Container images cleanup completed"
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    # Delete function by name if known
    if [[ -n "${FUNCTION_NAME}" ]]; then
        log_info "Deleting function: ${FUNCTION_NAME}"
        if gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet 2>/dev/null; then
            log_success "Deleted function: ${FUNCTION_NAME}"
        else
            log_warning "Function ${FUNCTION_NAME} not found or already deleted"
        fi
    fi
    
    # Delete any functions with quota-manager pattern
    log_info "Searching for quota manager functions..."
    local functions=$(gcloud functions list --regions="${REGION}" --format="value(name)" --filter="name:quota-manager" 2>/dev/null || echo "")
    
    if [[ -n "$functions" ]]; then
        while IFS= read -r func; do
            if [[ -n "$func" ]]; then
                local func_name=$(basename "$func")
                log_info "Deleting function: ${func_name}"
                if gcloud functions delete "${func_name}" --region="${REGION}" --quiet 2>/dev/null; then
                    log_success "Deleted function: ${func_name}"
                else
                    log_warning "Failed to delete function: ${func_name}"
                fi
            fi
        done <<< "$functions"
    fi
    
    log_success "Cloud Functions cleanup completed"
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    log_info "Deleting Cloud Storage buckets..."
    
    # Delete bucket by name if known
    if [[ -n "${BUCKET_NAME}" ]]; then
        log_info "Deleting bucket: gs://${BUCKET_NAME}"
        if gsutil -m rm -r "gs://${BUCKET_NAME}" 2>/dev/null; then
            log_success "Deleted bucket: gs://${BUCKET_NAME}"
        else
            log_warning "Bucket gs://${BUCKET_NAME} not found or already deleted"
        fi
    fi
    
    # Delete any buckets with quota-policies pattern
    log_info "Searching for quota policy buckets..."
    local buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "quota-policies" || echo "")
    
    if [[ -n "$buckets" ]]; then
        while IFS= read -r bucket; do
            if [[ -n "$bucket" && "$bucket" =~ gs:// ]]; then
                log_info "Deleting bucket: ${bucket}"
                if gsutil -m rm -r "${bucket}" 2>/dev/null; then
                    log_success "Deleted bucket: ${bucket}"
                else
                    log_warning "Failed to delete bucket: ${bucket}"
                fi
            fi
        done <<< "$buckets"
    fi
    
    log_success "Cloud Storage buckets cleanup completed"
}

# Function to clean up local files and directories
cleanup_local_files() {
    log_info "Cleaning up local files and directories..."
    
    # Remove local function directory
    if [[ -d "quota-manager-function" ]]; then
        log_info "Removing quota-manager-function directory"
        rm -rf quota-manager-function
        log_success "Removed quota-manager-function directory"
    fi
    
    # Remove local service directory
    if [[ -d "ai-inference-service" ]]; then
        log_info "Removing ai-inference-service directory"
        rm -rf ai-inference-service
        log_success "Removed ai-inference-service directory"
    fi
    
    # Remove temporary files
    local temp_files=(
        "quota-policy.json"
        "firestore-init.json"
        "dashboard-config.json"
        "alert-policy.json"
        ".deployment_info"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing temporary file: $file"
            rm -f "$file"
            log_success "Removed file: $file"
        fi
    done
    
    log_success "Local files cleanup completed"
}

# Function to provide Firestore cleanup instructions
firestore_cleanup_instructions() {
    log_info "Firestore Database Cleanup Instructions"
    echo "========================================"
    log_warning "The Firestore database was NOT automatically deleted for safety reasons."
    echo ""
    echo "If you want to delete the Firestore database and all its data:"
    echo ""
    echo "1. Go to the Google Cloud Console:"
    echo "   https://console.cloud.google.com/firestore/databases?project=${PROJECT_ID}"
    echo ""
    echo "2. Select your Firestore database"
    echo "3. Click 'Delete database' and follow the confirmation steps"
    echo ""
    echo "Alternatively, you can delete specific collections:"
    echo "1. Go to the Firestore Data tab:"
    echo "   https://console.cloud.google.com/firestore/data?project=${PROJECT_ID}"
    echo "2. Delete the 'quota_history' collection if it exists"
    echo ""
    log_warning "Note: Deleting the Firestore database is irreversible!"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "==============="
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "Resources cleaned up:"
    echo "✅ Cloud Scheduler Jobs"
    echo "✅ Cloud Run Services"
    echo "✅ Container Images"
    echo "✅ Cloud Functions"
    echo "✅ Cloud Storage Buckets"
    echo "✅ Local files and directories"
    echo ""
    log_warning "⚠️  Firestore database NOT deleted (requires manual action)"
    echo ""
    log_success "Cleanup completed successfully!"
    echo ""
    log_info "Note: Some Google Cloud APIs remain enabled."
    log_info "If you want to disable them, you can do so manually in the Cloud Console."
}

# Function to handle errors gracefully
error_handler() {
    local line_number=$1
    log_error "An error occurred on line $line_number"
    log_warning "Cleanup may be incomplete. You may need to manually remove some resources."
    
    log_info "You can check for remaining resources using:"
    echo "- gcloud scheduler jobs list --location=${REGION}"
    echo "- gcloud run services list --region=${REGION}"
    echo "- gcloud functions list --regions=${REGION}"
    echo "- gsutil ls -p ${PROJECT_ID}"
    
    exit 1
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Resource Allocation with Cloud Quotas API and Cloud Run GPU"
    
    load_deployment_info
    check_prerequisites
    confirm_destruction
    
    # Perform cleanup in reverse order of creation
    delete_scheduler_jobs
    delete_cloud_run_services
    delete_container_images
    delete_cloud_functions
    delete_storage_buckets
    cleanup_local_files
    
    firestore_cleanup_instructions
    display_cleanup_summary
    
    log_success "All cleanup steps completed successfully!"
}

# Set up error handling
trap 'error_handler $LINENO' ERR

# Handle script interruption
trap 'log_warning "Cleanup interrupted. Some resources may not have been deleted."; exit 1' INT TERM

# Run main function
main "$@"