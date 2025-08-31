#!/bin/bash

# Destroy Smart Document Review Workflow with ADK and Storage
# This script safely removes all infrastructure created for the smart document review system

set -euo pipefail

# Colors for output formatting
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

# Error handler
handle_error() {
    log_error "Script failed at line $1"
    log_error "Cleanup may be incomplete. Please check the error above."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Function to load environment variables
load_environment() {
    if [ -f "${ENV_FILE}" ]; then
        log_info "Loading environment variables from previous deployment..."
        source "${ENV_FILE}"
        
        log_info "Loaded configuration:"
        echo "  Project ID: ${PROJECT_ID:-'Not set'}"
        echo "  Region: ${REGION:-'Not set'}"
        echo "  Bucket Name: ${BUCKET_NAME:-'Not set'}"
        echo "  Function Name: ${FUNCTION_NAME:-'Not set'}"
    else
        log_error "Environment file not found: ${ENV_FILE}"
        log_error "Cannot determine resources to clean up."
        log_info "You may need to manually clean up resources from the Google Cloud Console."
        exit 1
    fi
}

# Function to confirm destruction
confirm_destruction() {
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "This will permanently delete the following resources:"
    echo "  - Google Cloud Project: ${PROJECT_ID}"
    echo "  - All storage buckets and their contents"
    echo "  - Cloud Functions and associated code"
    echo "  - All Vertex AI usage data"
    echo "  - Local development files"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Function to delete Cloud Function
delete_cloud_function() {
    log_info "Deleting Cloud Function..."
    
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        log_info "Deleting function: ${FUNCTION_NAME}"
        gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --quiet
        
        log_success "Cloud Function deleted"
    else
        log_warning "Cloud Function ${FUNCTION_NAME} not found, skipping deletion"
    fi
}

# Function to delete storage buckets
delete_storage_buckets() {
    log_info "Deleting Cloud Storage buckets and contents..."
    
    # Delete input bucket and contents
    if gsutil ls -b "gs://${BUCKET_NAME}-input" &>/dev/null; then
        log_info "Deleting input bucket: gs://${BUCKET_NAME}-input"
        gsutil -m rm -r "gs://${BUCKET_NAME}-input" || {
            log_warning "Failed to delete input bucket, trying to remove contents first..."
            gsutil -m rm -r "gs://${BUCKET_NAME}-input/**" 2>/dev/null || true
            gsutil rb "gs://${BUCKET_NAME}-input" || log_warning "Failed to delete input bucket"
        }
        log_success "Input bucket deleted"
    else
        log_warning "Input bucket gs://${BUCKET_NAME}-input not found, skipping"
    fi
    
    # Delete results bucket and contents
    if gsutil ls -b "gs://${BUCKET_NAME}-results" &>/dev/null; then
        log_info "Deleting results bucket: gs://${BUCKET_NAME}-results"
        gsutil -m rm -r "gs://${BUCKET_NAME}-results" || {
            log_warning "Failed to delete results bucket, trying to remove contents first..."
            gsutil -m rm -r "gs://${BUCKET_NAME}-results/**" 2>/dev/null || true
            gsutil rb "gs://${BUCKET_NAME}-results" || log_warning "Failed to delete results bucket"
        }
        log_success "Results bucket deleted"
    else
        log_warning "Results bucket gs://${BUCKET_NAME}-results not found, skipping"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local development files..."
    
    local dev_dir="${SCRIPT_DIR}/../document-review-agents"
    local sample_files=(
        "${SCRIPT_DIR}/sample_document.txt"
        "${SCRIPT_DIR}/review_sample_document.txt.json"
    )
    
    # Remove development directory
    if [ -d "${dev_dir}" ]; then
        log_info "Removing development directory: ${dev_dir}"
        rm -rf "${dev_dir}"
        log_success "Development directory removed"
    else
        log_warning "Development directory not found, skipping"
    fi
    
    # Remove sample files
    for file in "${sample_files[@]}"; do
        if [ -f "${file}" ]; then
            log_info "Removing file: $(basename "${file}")"
            rm -f "${file}"
        fi
    done
    
    # Remove environment file
    if [ -f "${ENV_FILE}" ]; then
        log_info "Removing environment file"
        rm -f "${ENV_FILE}"
    fi
    
    log_success "Local files cleaned up"
}

# Function to disable APIs (optional - saves costs)
disable_apis() {
    log_info "Disabling Google Cloud APIs to prevent further charges..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
        "eventarc.googleapis.com"
        "run.googleapis.com"
        "pubsub.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Disabling ${api}..."
        gcloud services disable "${api}" --force --quiet 2>/dev/null || {
            log_warning "Failed to disable ${api} (may not be enabled)"
        }
    done
    
    log_success "APIs disabled"
}

# Function to delete project (optional but thorough)
delete_project() {
    echo
    log_warning "🗑️  PROJECT DELETION OPTION"
    echo "You can optionally delete the entire Google Cloud project."
    echo "This ensures complete cleanup but is irreversible."
    echo
    echo "Project to delete: ${PROJECT_ID}"
    echo
    
    read -p "Delete the entire project? Type 'delete-project' to confirm: " -r
    echo
    
    if [[ $REPLY == "delete-project" ]]; then
        log_info "Deleting Google Cloud project: ${PROJECT_ID}"
        
        # First check if project exists
        if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
            gcloud projects delete "${PROJECT_ID}" --quiet
            log_success "Project deletion initiated (may take several minutes to complete)"
            log_info "All resources in the project will be permanently deleted"
        else
            log_warning "Project ${PROJECT_ID} not found or already deleted"
        fi
    else
        log_info "Project deletion skipped"
        log_warning "Note: The project ${PROJECT_ID} still exists and may incur minimal charges"
        log_info "You can delete it manually later with: gcloud projects delete ${PROJECT_ID}"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_complete=true
    
    # Check if Cloud Function still exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        log_warning "Cloud Function ${FUNCTION_NAME} still exists"
        cleanup_complete=false
    fi
    
    # Check if buckets still exist
    if gsutil ls -b "gs://${BUCKET_NAME}-input" &>/dev/null; then
        log_warning "Input bucket gs://${BUCKET_NAME}-input still exists"
        cleanup_complete=false
    fi
    
    if gsutil ls -b "gs://${BUCKET_NAME}-results" &>/dev/null; then
        log_warning "Results bucket gs://${BUCKET_NAME}-results still exists"
        cleanup_complete=false
    fi
    
    # Check if local files still exist
    if [ -d "${SCRIPT_DIR}/../document-review-agents" ]; then
        log_warning "Local development directory still exists"
        cleanup_complete=false
    fi
    
    if [ "$cleanup_complete" = true ]; then
        log_success "Cleanup verification passed - all resources removed"
    else
        log_warning "Some resources may still exist - check manually if needed"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "Smart Document Review Workflow cleanup completed!"
    echo
    echo "🧹 Cleanup Summary:"
    echo "  ✅ Cloud Function deleted"
    echo "  ✅ Storage buckets and contents removed"
    echo "  ✅ Local development files cleaned up"
    echo "  ✅ APIs disabled to prevent charges"
    echo
    
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        echo "📋 Remaining Resources:"
        echo "  - Project: ${PROJECT_ID} (still exists)"
        echo "  - You can delete it manually with: gcloud projects delete ${PROJECT_ID}"
        echo
        echo "💰 Billing Information:"
        echo "  - Most billable resources have been removed"
        echo "  - The project may still exist with minimal or no charges"
        echo "  - Delete the project completely to ensure zero charges"
    else
        echo "✅ Project completely removed - no further charges expected"
    fi
    
    echo
    echo "🔍 Manual Verification:"
    echo "  - Check Google Cloud Console: https://console.cloud.google.com"
    echo "  - Verify billing: https://console.cloud.google.com/billing"
    echo "  - Check storage: https://console.cloud.google.com/storage"
}

# Function to handle interrupted cleanup
cleanup_interrupted() {
    log_warning "Cleanup was interrupted!"
    echo
    echo "To manually complete cleanup:"
    echo "1. Delete Cloud Function: gcloud functions delete ${FUNCTION_NAME} --region=${REGION}"
    echo "2. Delete input bucket: gsutil -m rm -r gs://${BUCKET_NAME}-input"
    echo "3. Delete results bucket: gsutil -m rm -r gs://${BUCKET_NAME}-results"
    echo "4. Delete project: gcloud projects delete ${PROJECT_ID}"
    echo "5. Remove local files: rm -rf ${SCRIPT_DIR}/../document-review-agents"
}

# Set up cleanup handler for interruptions
trap cleanup_interrupted SIGINT SIGTERM

# Main execution
main() {
    log_info "Starting Smart Document Review Workflow cleanup..."
    echo "==============================================================="
    
    load_environment
    confirm_destruction
    
    # Perform cleanup steps
    delete_cloud_function
    delete_storage_buckets
    cleanup_local_files
    disable_apis
    delete_project
    verify_cleanup
    display_cleanup_summary
    
    log_success "Cleanup completed successfully! 🎉"
}

# Function to handle dry-run mode
dry_run() {
    log_info "DRY RUN MODE - No resources will be deleted"
    echo "==============================================================="
    
    load_environment
    
    echo
    log_info "Resources that would be deleted:"
    echo "  - Cloud Function: ${FUNCTION_NAME} (region: ${REGION})"
    echo "  - Storage bucket: gs://${BUCKET_NAME}-input"
    echo "  - Storage bucket: gs://${BUCKET_NAME}-results"
    echo "  - Local directory: ${SCRIPT_DIR}/../document-review-agents"
    echo "  - Environment file: ${ENV_FILE}"
    echo "  - Project (optional): ${PROJECT_ID}"
    echo
    
    log_info "To perform actual cleanup, run: ./destroy.sh"
    log_info "To cleanup specific resources only, edit this script as needed"
}

# Handle command line arguments
if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run
    exit 0
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Smart Document Review Workflow Cleanup Script"
    echo
    echo "Usage:"
    echo "  ./destroy.sh              - Perform cleanup with confirmation"
    echo "  ./destroy.sh --dry-run    - Show what would be deleted (safe)"
    echo "  ./destroy.sh --help       - Show this help message"
    echo
    echo "This script will remove all resources created by deploy.sh"
    echo "Make sure you have backed up any important data before running."
    exit 0
fi

# Allow script to be sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi