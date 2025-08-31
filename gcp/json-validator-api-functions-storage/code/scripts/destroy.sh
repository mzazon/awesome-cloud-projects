#!/bin/bash

# JSON Validator API with Cloud Functions - Cleanup Script
# This script removes all resources created by the deployment script to avoid ongoing charges
# Recipe: json-validator-api-functions-storage

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if user is authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [[ ! -f .env ]]; then
        log_error "Environment file .env not found. Cannot determine resources to clean up."
        log_info "Please provide environment variables manually or ensure you're in the correct directory."
        exit 1
    fi
    
    # Source environment variables
    source .env
    
    # Validate required variables
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID not found in .env file"
        exit 1
    fi
    
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        log_error "FUNCTION_NAME not found in .env file"
        exit 1
    fi
    
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_error "BUCKET_NAME not found in .env file"
        exit 1
    fi
    
    if [[ -z "${REGION:-}" ]]; then
        log_error "REGION not found in .env file"
        exit 1
    fi
    
    log_info "Environment variables loaded:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Function Name: ${FUNCTION_NAME}"
    log_info "  Bucket Name: ${BUCKET_NAME}"
    log_info "  Region: ${REGION}"
    
    log_success "Environment configuration loaded"
}

# Function to prompt for confirmation
confirm_destruction() {
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        log_warning "FORCE_DELETE is set. Skipping confirmation prompt."
        return 0
    fi
    
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log_warning "This script will permanently delete the following resources:"
    log_warning "  • Cloud Function: ${FUNCTION_NAME}"
    log_warning "  • Cloud Storage Bucket: gs://${BUCKET_NAME} (and all contents)"
    log_warning "  • GCP Project: ${PROJECT_ID} (optional)"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "Confirmation received. Proceeding with resource cleanup..."
}

# Function to set active project
set_active_project() {
    log_info "Setting active project..."
    
    # Check if project exists
    if ! gcloud projects list --filter="projectId:${PROJECT_ID}" --format="value(projectId)" | grep -q "${PROJECT_ID}"; then
        log_warning "Project ${PROJECT_ID} not found. It may have already been deleted."
        return 0
    fi
    
    # Set active project
    gcloud config set project ${PROJECT_ID} || {
        log_error "Failed to set active project"
        exit 1
    }
    
    log_success "Active project set to ${PROJECT_ID}"
}

# Function to delete Cloud Function
delete_cloud_function() {
    log_info "Deleting Cloud Function..."
    
    # Check if function exists
    if ! gcloud functions list --filter="name:${FUNCTION_NAME}" --format="value(name)" | grep -q "${FUNCTION_NAME}"; then
        log_warning "Cloud Function ${FUNCTION_NAME} not found. It may have already been deleted."
        return 0
    fi
    
    # Delete the function
    gcloud functions delete ${FUNCTION_NAME} \
        --region=${REGION} \
        --quiet || {
        log_error "Failed to delete Cloud Function"
        exit 1
    }
    
    log_success "Cloud Function ${FUNCTION_NAME} deleted"
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket..."
    
    # Check if bucket exists
    if ! gsutil ls -b gs://${BUCKET_NAME} >/dev/null 2>&1; then
        log_warning "Storage bucket gs://${BUCKET_NAME} not found. It may have already been deleted."
        return 0
    fi
    
    # List bucket contents for confirmation
    log_info "Bucket contents to be deleted:"
    gsutil ls -la gs://${BUCKET_NAME}/ || log_warning "Unable to list bucket contents"
    
    # Delete all objects and bucket
    log_info "Removing all objects from bucket..."
    gsutil -m rm -r gs://${BUCKET_NAME} || {
        # Try alternative deletion method if the first fails
        log_warning "Standard deletion failed. Trying alternative method..."
        gsutil rm gs://${BUCKET_NAME}/* || log_warning "Some objects may not have been deleted"
        gsutil rb gs://${BUCKET_NAME} || {
            log_error "Failed to delete storage bucket"
            exit 1
        }
    }
    
    log_success "Storage bucket gs://${BUCKET_NAME} deleted"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove function directory if it exists
    if [[ -d "json-validator-function" ]]; then
        rm -rf json-validator-function
        log_success "Removed local function directory"
    fi
    
    # Remove test files if they exist
    for file in sample-valid.json sample-invalid.json; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_success "Removed local file: ${file}"
        fi
    done
    
    log_success "Local file cleanup completed"
}

# Function to disable APIs (optional)
disable_apis() {
    if [[ "${DISABLE_APIS:-false}" != "true" ]]; then
        log_info "Skipping API disabling (set DISABLE_APIS=true to disable APIs)"
        return 0
    fi
    
    log_info "Disabling Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Disabling ${api}..."
        gcloud services disable ${api} --force --quiet || {
            log_warning "Failed to disable ${api} (may already be disabled)"
        }
    done
    
    log_success "APIs disabled"
}

# Function to delete entire project
delete_project() {
    if [[ "${DELETE_PROJECT:-false}" != "true" ]]; then
        log_info "Skipping project deletion (set DELETE_PROJECT=true to delete entire project)"
        return 0
    fi
    
    log_warning "Deleting entire project ${PROJECT_ID}..."
    
    # Additional confirmation for project deletion
    echo
    log_warning "⚠️  PROJECT DELETION WARNING ⚠️"
    log_warning "You are about to delete the ENTIRE project: ${PROJECT_ID}"
    log_warning "This will remove ALL resources in the project, not just the ones created by this recipe."
    echo
    
    if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
        read -p "Type the project ID '${PROJECT_ID}' to confirm project deletion: " project_confirmation
        
        if [[ "${project_confirmation}" != "${PROJECT_ID}" ]]; then
            log_info "Project deletion cancelled."
            return 0
        fi
    fi
    
    # Delete the project
    gcloud projects delete ${PROJECT_ID} --quiet || {
        log_error "Failed to delete project"
        exit 1
    }
    
    log_success "Project ${PROJECT_ID} deletion initiated (may take several minutes)"
    log_info "Note: Billing for deleted resources stops immediately"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    # Verify function deletion
    if gcloud functions list --filter="name:${FUNCTION_NAME}" --format="value(name)" | grep -q "${FUNCTION_NAME}"; then
        log_warning "Cloud Function ${FUNCTION_NAME} still exists"
    else
        log_success "Cloud Function ${FUNCTION_NAME} confirmed deleted"
    fi
    
    # Verify bucket deletion
    if gsutil ls -b gs://${BUCKET_NAME} >/dev/null 2>&1; then
        log_warning "Storage bucket gs://${BUCKET_NAME} still exists"
    else
        log_success "Storage bucket gs://${BUCKET_NAME} confirmed deleted"
    fi
    
    # Verify project status if not deleted
    if [[ "${DELETE_PROJECT:-false}" != "true" ]]; then
        if gcloud projects list --filter="projectId:${PROJECT_ID}" --format="value(projectId)" | grep -q "${PROJECT_ID}"; then
            log_success "Project ${PROJECT_ID} still exists (as expected)"
        else
            log_warning "Project ${PROJECT_ID} not found (may have been deleted)"
        fi
    fi
    
    log_success "Cleanup verification completed"
}

# Function to remove environment file
cleanup_environment_file() {
    log_info "Cleaning up environment file..."
    
    if [[ -f .env ]]; then
        rm -f .env
        log_success "Environment file .env removed"
    fi
    
    # Also remove any backup environment files
    for env_file in .env.bak .env.backup; do
        if [[ -f "${env_file}" ]]; then
            rm -f "${env_file}"
            log_success "Backup environment file ${env_file} removed"
        fi
    done
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "=== CLEANUP COMPLETED SUCCESSFULLY ==="
    echo
    log_info "Cleanup Summary:"
    log_info "  ✅ Cloud Function deleted: ${FUNCTION_NAME}"
    log_info "  ✅ Storage bucket deleted: gs://${BUCKET_NAME}"
    log_info "  ✅ Local files cleaned up"
    log_info "  ✅ Environment file removed"
    
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        log_info "  ✅ Project deletion initiated: ${PROJECT_ID}"
    else
        log_info "  ⏭️  Project preserved: ${PROJECT_ID}"
    fi
    
    if [[ "${DISABLE_APIS:-false}" == "true" ]]; then
        log_info "  ✅ APIs disabled"
    else
        log_info "  ⏭️  APIs preserved"
    fi
    
    echo
    log_success "All resources have been cleaned up. No further charges should be incurred."
    
    if [[ "${DELETE_PROJECT:-false}" != "true" ]]; then
        log_info "Project ${PROJECT_ID} was preserved. You can manually delete it from the GCP Console if needed."
    fi
    
    echo
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    local exit_code=$?
    log_error "Cleanup process failed with exit code ${exit_code}"
    log_warning "Some resources may not have been fully cleaned up."
    log_info "Please check the Google Cloud Console to verify resource status."
    log_info "You may need to manually delete remaining resources to avoid charges."
    exit ${exit_code}
}

# Main cleanup function
main() {
    log_info "Starting JSON Validator API cleanup..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_DELETE=true
                log_info "Force delete mode enabled"
                shift
                ;;
            --delete-project)
                export DELETE_PROJECT=true
                log_info "Project deletion enabled"
                shift
                ;;
            --disable-apis)
                export DISABLE_APIS=true
                log_info "API disabling enabled"
                shift
                ;;
            --dry-run)
                log_info "DRY RUN MODE - No resources will be deleted"
                export DRY_RUN=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --force              Skip confirmation prompts"
                echo "  --delete-project     Delete the entire GCP project"
                echo "  --disable-apis       Disable the enabled APIs"
                echo "  --dry-run           Show what would be deleted without deleting"
                echo "  --help              Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Check if dry run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "DRY RUN MODE - Showing what would be deleted:"
        load_environment
        log_info "Would delete:"
        log_info "  - Cloud Function: ${FUNCTION_NAME}"
        log_info "  - Storage Bucket: gs://${BUCKET_NAME}"
        log_info "  - Local files and directories"
        if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
            log_info "  - Entire project: ${PROJECT_ID}"
        fi
        return 0
    fi
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_destruction
    set_active_project
    delete_cloud_function
    delete_storage_bucket
    cleanup_local_files
    disable_apis
    delete_project
    verify_cleanup
    cleanup_environment_file
    display_cleanup_summary
}

# Handle script interruption and errors
trap handle_cleanup_error ERR
trap 'log_error "Cleanup interrupted by user"; exit 1' INT TERM

# Run main function with all arguments
main "$@"