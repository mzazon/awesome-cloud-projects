#!/bin/bash

# Recipe Generation and Meal Planning with Gemini and Storage - Cleanup Script
# This script safely removes all resources created by the deployment script
# to avoid ongoing charges

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check for required tools
    if ! command_exists gcloud; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    if ! command_exists gsutil; then
        error_exit "gsutil is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        error_exit "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
    fi
    
    log_success "Prerequisites validated successfully"
}

# Get or set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Check if project ID is provided as argument or environment variable
    if [[ "${1:-}" ]]; then
        export PROJECT_ID="$1"
    elif [[ "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="${PROJECT_ID}"
    else
        # Try to get current project
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "No PROJECT_ID provided and no default project set"
            log_info "Usage: $0 PROJECT_ID"
            log_info "Or set PROJECT_ID environment variable"
            exit 1
        fi
        export PROJECT_ID
        log_warning "Using current project: ${PROJECT_ID}"
    fi
    
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Set resource names (these should match deploy.sh)
    export FUNCTION_NAME_GEN="recipe-generator"
    export FUNCTION_NAME_GET="recipe-retriever"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_success "Environment variables configured"
}

# Confirm destruction with user
confirm_destruction() {
    log_warning "=== RESOURCE DESTRUCTION CONFIRMATION ==="
    log_warning "This will permanently delete ALL resources in project: ${PROJECT_ID}"
    echo
    log_info "Resources to be deleted:"
    echo "  - Cloud Functions: ${FUNCTION_NAME_GEN}, ${FUNCTION_NAME_GET}"
    echo "  - Cloud Storage buckets starting with 'recipe-storage-'"
    echo "  - All associated data and configurations"
    echo
    log_warning "This action CANNOT be undone!"
    echo
    
    # Option to delete entire project
    read -p "Do you want to delete the entire project? This is recommended for cleanup. (y/N): " delete_project
    if [[ "${delete_project,,}" == "y" ]]; then
        export DELETE_PROJECT=true
        log_warning "Will delete entire project: ${PROJECT_ID}"
        echo
        read -p "Are you absolutely sure you want to delete project ${PROJECT_ID}? Type 'DELETE' to confirm: " confirm
        if [[ "${confirm}" != "DELETE" ]]; then
            log_info "Project deletion cancelled"
            export DELETE_PROJECT=false
        fi
    else
        export DELETE_PROJECT=false
        log_info "Will delete individual resources only"
        echo
        read -p "Continue with resource deletion? (y/N): " continue_destroy
        if [[ "${continue_destroy,,}" != "y" ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    echo
    log_info "Starting cleanup process..."
}

# Delete Cloud Functions
delete_functions() {
    log_info "Deleting Cloud Functions..."
    
    # Set project context
    gcloud config set project "${PROJECT_ID}"
    
    # Delete recipe generation function
    if gcloud functions describe "${FUNCTION_NAME_GEN}" >/dev/null 2>&1; then
        log_info "Deleting function: ${FUNCTION_NAME_GEN}"
        if gcloud functions delete "${FUNCTION_NAME_GEN}" --quiet; then
            log_success "Deleted function: ${FUNCTION_NAME_GEN}"
        else
            log_error "Failed to delete function: ${FUNCTION_NAME_GEN}"
        fi
    else
        log_info "Function ${FUNCTION_NAME_GEN} not found or already deleted"
    fi
    
    # Delete recipe retrieval function
    if gcloud functions describe "${FUNCTION_NAME_GET}" >/dev/null 2>&1; then
        log_info "Deleting function: ${FUNCTION_NAME_GET}"
        if gcloud functions delete "${FUNCTION_NAME_GET}" --quiet; then
            log_success "Deleted function: ${FUNCTION_NAME_GET}"
        else
            log_error "Failed to delete function: ${FUNCTION_NAME_GET}"
        fi
    else
        log_info "Function ${FUNCTION_NAME_GET} not found or already deleted"
    fi
    
    log_success "Cloud Functions cleanup completed"
}

# Delete Cloud Storage buckets
delete_storage() {
    log_info "Deleting Cloud Storage buckets..."
    
    # Find all buckets starting with 'recipe-storage-'
    local buckets
    buckets=$(gsutil ls -p "${PROJECT_ID}" | grep "gs://recipe-storage-" || echo "")
    
    if [[ -n "${buckets}" ]]; then
        while IFS= read -r bucket; do
            if [[ -n "${bucket}" ]]; then
                log_info "Deleting bucket: ${bucket}"
                # First delete all objects, then the bucket
                if gsutil -m rm -r "${bucket}"; then
                    log_success "Deleted bucket: ${bucket}"
                else
                    log_error "Failed to delete bucket: ${bucket}"
                fi
            fi
        done <<< "${buckets}"
    else
        log_info "No recipe storage buckets found"
    fi
    
    log_success "Cloud Storage cleanup completed"
}

# Remove IAM policy bindings
cleanup_iam() {
    log_info "Cleaning up IAM policy bindings..."
    
    # Get the default Cloud Functions service account
    local functions_sa="${PROJECT_ID}@appspot.gserviceaccount.com"
    
    # Remove Vertex AI User role
    if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${functions_sa}" \
        --role="roles/aiplatform.user" >/dev/null 2>&1; then
        log_success "Removed Vertex AI User role"
    else
        log_info "Vertex AI User role not found or already removed"
    fi
    
    # Remove Storage Object Admin role
    if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${functions_sa}" \
        --role="roles/storage.objectAdmin" >/dev/null 2>&1; then
        log_success "Removed Storage Object Admin role"
    else
        log_info "Storage Object Admin role not found or already removed"
    fi
    
    log_success "IAM cleanup completed"
}

# Delete entire project
delete_project() {
    log_info "Deleting entire project: ${PROJECT_ID}"
    
    if gcloud projects delete "${PROJECT_ID}" --quiet; then
        log_success "Project ${PROJECT_ID} deletion initiated"
        log_info "Note: Project deletion may take several minutes to complete"
        log_info "You can monitor progress in the Google Cloud Console"
    else
        log_error "Failed to delete project: ${PROJECT_ID}"
        log_info "You may need to delete it manually in the Google Cloud Console"
    fi
}

# Verify resource deletion
verify_cleanup() {
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        log_info "Project deletion initiated - skipping individual resource verification"
        return
    fi
    
    log_info "Verifying resource deletion..."
    
    # Check Cloud Functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --filter="name:(${FUNCTION_NAME_GEN} OR ${FUNCTION_NAME_GET})" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${remaining_functions}" ]]; then
        log_warning "Some functions may still exist:"
        echo "${remaining_functions}"
    else
        log_success "All Cloud Functions deleted successfully"
    fi
    
    # Check Storage buckets
    local remaining_buckets
    remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" | grep "gs://recipe-storage-" || echo "")
    
    if [[ -n "${remaining_buckets}" ]]; then
        log_warning "Some storage buckets may still exist:"
        echo "${remaining_buckets}"
    else
        log_success "All recipe storage buckets deleted successfully"
    fi
    
    log_success "Resource verification completed"
}

# Display cleanup summary
show_summary() {
    log_success "=== CLEANUP COMPLETED ==="
    echo
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        log_info "Project Deletion:"
        echo "  - Project ${PROJECT_ID} deletion has been initiated"
        echo "  - This may take several minutes to complete"
        echo "  - Monitor progress in the Google Cloud Console"
        echo "  - All billing will stop once deletion is complete"
    else
        log_info "Resources Cleaned Up:"
        echo "  - Cloud Functions: ${FUNCTION_NAME_GEN}, ${FUNCTION_NAME_GET}"
        echo "  - Cloud Storage buckets with recipe data"
        echo "  - IAM policy bindings for service accounts"
        echo
        log_info "Remaining Resources:"
        echo "  - Project ${PROJECT_ID} (still exists)"
        echo "  - Enabled APIs (still active)"
        echo "  - Any other resources not created by this recipe"
    fi
    
    echo
    log_info "Cost Impact:"
    echo "  - Cloud Functions: No charges (deleted)"
    echo "  - Cloud Storage: No charges (deleted)"
    echo "  - Vertex AI: No charges (no active models)"
    echo
    
    if [[ "${DELETE_PROJECT}" == "false" ]]; then
        log_warning "Note: To completely eliminate all charges, consider deleting the project:"
        echo "  gcloud projects delete ${PROJECT_ID}"
    fi
    
    log_success "Cleanup process completed successfully!"
}

# Handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_warning "Cleanup script was interrupted"
        log_info "Some resources may still exist and continue to incur charges"
        log_info "You may need to manually clean up remaining resources"
    fi
    exit ${exit_code}
}

# Main cleanup function
main() {
    log_info "Starting Recipe Generation and Meal Planning cleanup..."
    
    # Set trap for cleanup on exit
    trap cleanup_on_exit EXIT INT TERM
    
    validate_prerequisites
    setup_environment "$@"
    confirm_destruction
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        delete_project
    else
        delete_functions
        delete_storage
        cleanup_iam
        verify_cleanup
    fi
    
    show_summary
    
    log_success "Cleanup completed successfully!"
}

# Display help information
show_help() {
    echo "Recipe Generation and Meal Planning - Cleanup Script"
    echo
    echo "Usage: $0 [PROJECT_ID]"
    echo
    echo "Arguments:"
    echo "  PROJECT_ID    Google Cloud Project ID (optional if set in environment)"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID    Google Cloud Project ID"
    echo "  REGION        Google Cloud Region (default: us-central1)"
    echo
    echo "Examples:"
    echo "  $0 my-recipe-project"
    echo "  PROJECT_ID=my-recipe-project $0"
    echo
    echo "This script will:"
    echo "  1. Delete Cloud Functions (recipe-generator, recipe-retriever)"
    echo "  2. Delete Cloud Storage buckets containing recipe data"
    echo "  3. Remove IAM policy bindings"
    echo "  4. Optionally delete the entire project"
    echo
    echo "Safety Features:"
    echo "  - Requires explicit confirmation before deletion"
    echo "  - Validates prerequisites before proceeding"
    echo "  - Provides detailed logging and error handling"
    echo "  - Verifies resource deletion"
}

# Check for help flag
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi