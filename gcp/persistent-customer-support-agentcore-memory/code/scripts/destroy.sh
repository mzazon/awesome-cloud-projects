#!/bin/bash

# Cleanup script for Persistent AI Customer Support with Agent Engine Memory
# This script removes all infrastructure components including Cloud Functions and Firestore

set -e
set -u
set -o pipefail

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "You are not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    local deployment_file="${PWD}/deployment-info.txt"
    
    if [[ -f "${deployment_file}" ]]; then
        # Source the deployment info file
        source "${deployment_file}"
        log_success "Deployment information loaded from ${deployment_file}"
        
        # Display loaded information
        log_info "Loaded configuration:"
        log_info "  Project ID: ${PROJECT_ID:-not set}"
        log_info "  Region: ${REGION:-not set}"
        log_info "  Function Name: ${FUNCTION_NAME:-not set}"
        log_info "  Memory Function Name: ${MEMORY_FUNCTION_NAME:-not set}"
    else
        log_warning "Deployment info file not found at ${deployment_file}"
        log_info "You will need to provide configuration manually"
        return 1
    fi
}

# Function to setup environment variables manually
setup_environment_manual() {
    log_info "Setting up environment variables manually..."
    
    # Use provided values or defaults
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
    export REGION="${REGION:-us-central1}"
    
    # If still no project ID, ask user
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "No project ID found. Please specify with --project-id or set PROJECT_ID environment variable"
        exit 1
    fi
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set functions/region "${REGION}" --quiet
    
    log_success "Environment configured for project: ${PROJECT_ID}"
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "${FORCE:-false}" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo
    echo "=================================================================="
    echo "⚠️  WARNING: DESTRUCTIVE OPERATION"
    echo "=================================================================="
    echo "This will permanently delete the following resources:"
    echo "  • Project: ${PROJECT_ID}"
    echo "  • Region: ${REGION}"
    echo "  • All Cloud Functions in the project"
    echo "  • Firestore database and all conversation data"
    echo "  • Any other resources created during deployment"
    echo
    echo "This action cannot be undone!"
    echo "=================================================================="
    echo
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource destruction..."
}

# Function to list Cloud Functions
list_cloud_functions() {
    log_info "Listing Cloud Functions in project ${PROJECT_ID}..."
    
    local functions=$(gcloud functions list --filter="name:projects/${PROJECT_ID}/locations/${REGION}/functions/*" --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${functions}" ]]; then
        log_info "Found Cloud Functions:"
        echo "${functions}" | while read -r function; do
            if [[ -n "${function}" ]]; then
                log_info "  • ${function##*/}"
            fi
        done
        return 0
    else
        log_info "No Cloud Functions found in region ${REGION}"
        return 1
    fi
}

# Function to delete specific Cloud Functions
delete_specific_functions() {
    log_info "Deleting specific Cloud Functions..."
    
    local functions_deleted=0
    
    # Delete main chat function if name is known
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log_info "Deleting chat function: ${FUNCTION_NAME}"
        if gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet 2>/dev/null; then
            log_success "Deleted function: ${FUNCTION_NAME}"
            ((functions_deleted++))
        else
            log_warning "Failed to delete function: ${FUNCTION_NAME} (may not exist)"
        fi
    fi
    
    # Delete memory retrieval function if name is known
    if [[ -n "${MEMORY_FUNCTION_NAME:-}" ]]; then
        log_info "Deleting memory retrieval function: ${MEMORY_FUNCTION_NAME}"
        if gcloud functions delete "${MEMORY_FUNCTION_NAME}" --region="${REGION}" --quiet 2>/dev/null; then
            log_success "Deleted function: ${MEMORY_FUNCTION_NAME}"
            ((functions_deleted++))
        else
            log_warning "Failed to delete function: ${MEMORY_FUNCTION_NAME} (may not exist)"
        fi
    fi
    
    log_info "Deleted ${functions_deleted} specific functions"
}

# Function to delete all Cloud Functions in the region
delete_all_functions() {
    log_info "Deleting all Cloud Functions in region ${REGION}..."
    
    local functions=$(gcloud functions list --filter="name:projects/${PROJECT_ID}/locations/${REGION}/functions/*" --format="value(name)" 2>/dev/null || true)
    local functions_deleted=0
    
    if [[ -n "${functions}" ]]; then
        echo "${functions}" | while read -r function; do
            if [[ -n "${function}" ]]; then
                local function_name="${function##*/}"
                log_info "Deleting function: ${function_name}"
                if gcloud functions delete "${function_name}" --region="${REGION}" --quiet 2>/dev/null; then
                    log_success "Deleted function: ${function_name}"
                    ((functions_deleted++))
                else
                    log_warning "Failed to delete function: ${function_name}"
                fi
            fi
        done
    else
        log_info "No Cloud Functions found to delete"
    fi
    
    # Wait for functions to be fully deleted
    log_info "Waiting for functions to be fully deleted..."
    sleep 30
}

# Function to delete Firestore database
delete_firestore() {
    log_info "Deleting Firestore database..."
    
    # Check if Firestore database exists
    if gcloud firestore databases list --filter="name:projects/${PROJECT_ID}/databases/(default)" --format="value(name)" | grep -q .; then
        log_info "Found Firestore database, deleting..."
        
        # Delete all collections first (optional but cleaner)
        log_info "Attempting to delete collections..."
        if command_exists gcloud && gcloud version --format="value(Google Cloud SDK)" | grep -q alpha; then
            # Try to delete conversations collection if it exists
            gcloud alpha firestore collections delete conversations --recursive --quiet 2>/dev/null || log_warning "Could not delete conversations collection"
        fi
        
        # Delete the database
        if gcloud firestore databases delete --database='(default)' --quiet 2>/dev/null; then
            log_success "Firestore database deleted successfully"
        else
            log_warning "Failed to delete Firestore database (may require manual cleanup)"
        fi
    else
        log_info "No Firestore database found"
    fi
}

# Function to clean up IAM roles and service accounts
cleanup_iam() {
    log_info "Cleaning up IAM roles and service accounts..."
    
    # List and clean up any custom service accounts created for this deployment
    local service_accounts=$(gcloud iam service-accounts list --filter="email:*support-chat*" --format="value(email)" 2>/dev/null || true)
    
    if [[ -n "${service_accounts}" ]]; then
        echo "${service_accounts}" | while read -r sa; do
            if [[ -n "${sa}" ]]; then
                log_info "Deleting service account: ${sa}"
                if gcloud iam service-accounts delete "${sa}" --quiet 2>/dev/null; then
                    log_success "Deleted service account: ${sa}"
                else
                    log_warning "Failed to delete service account: ${sa}"
                fi
            fi
        done
    else
        log_info "No custom service accounts found"
    fi
}

# Function to disable APIs
disable_apis() {
    if [[ "${DISABLE_APIS:-false}" == "true" ]]; then
        log_info "Disabling APIs..."
        
        local apis=(
            "cloudfunctions.googleapis.com"
            "firestore.googleapis.com"
            "aiplatform.googleapis.com"
            "cloudbuild.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log_info "Disabling ${api}..."
            if gcloud services disable "${api}" --force --quiet 2>/dev/null; then
                log_success "${api} disabled"
            else
                log_warning "Failed to disable ${api}"
            fi
        done
    else
        log_info "Skipping API disabling (use --disable-apis to enable)"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-info.txt"
        "function-urls.txt"
        ".deployment-state"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            log_info "Removing ${file}..."
            rm -f "${file}"
            log_success "Removed ${file}"
        fi
    done
    
    # Clean up any temporary directories
    if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR}" ]]; then
        log_info "Removing temporary directory: ${TEMP_DIR}"
        rm -rf "${TEMP_DIR}"
        log_success "Temporary directory cleaned up"
    fi
}

# Function to delete project
delete_project() {
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        log_warning "Deleting entire project: ${PROJECT_ID}"
        log_warning "This will delete ALL resources in the project!"
        
        if [[ "${FORCE:-false}" != "true" ]]; then
            read -p "Are you absolutely sure? Type the project ID to confirm: " project_confirmation
            if [[ "${project_confirmation}" != "${PROJECT_ID}" ]]; then
                log_info "Project deletion cancelled"
                return 0
            fi
        fi
        
        log_info "Deleting project ${PROJECT_ID}..."
        if gcloud projects delete "${PROJECT_ID}" --quiet; then
            log_success "Project deletion initiated"
            log_info "Note: Project deletion may take several minutes to complete"
        else
            log_error "Failed to delete project"
        fi
    else
        log_info "Skipping project deletion (use --delete-project to enable)"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    # Check for remaining Cloud Functions
    local remaining_functions=$(gcloud functions list --filter="name:projects/${PROJECT_ID}/locations/${REGION}/functions/*" --format="value(name)" 2>/dev/null | wc -l)
    if [[ "${remaining_functions}" -eq 0 ]]; then
        log_success "All Cloud Functions have been removed"
    else
        log_warning "${remaining_functions} Cloud Functions still exist"
    fi
    
    # Check for Firestore database
    if gcloud firestore databases list --filter="name:projects/${PROJECT_ID}/databases/(default)" --format="value(name)" | grep -q .; then
        log_warning "Firestore database still exists"
    else
        log_success "Firestore database has been removed"
    fi
    
    log_success "Cleanup verification completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo
    echo "=================================================================="
    echo "🧹 Cleanup Summary"
    echo "=================================================================="
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo
    echo "✅ Resources cleaned up:"
    echo "   • Cloud Functions deleted"
    echo "   • Firestore database removed"
    echo "   • Local files cleaned up"
    
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        echo "   • Project deletion initiated"
    fi
    
    echo
    echo "⚠️  Note: Some resources may take a few minutes to be fully removed"
    echo "⚠️  Check the Google Cloud Console to verify all resources are deleted"
    echo
    echo "=================================================================="
}

# Function to handle cleanup errors
handle_cleanup_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code ${exit_code}"
    log_info "Some resources may not have been cleaned up properly"
    log_info "Please check the Google Cloud Console and clean up manually if needed"
    exit ${exit_code}
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Persistent AI Customer Support infrastructure..."
    
    # Set error handler
    trap handle_cleanup_error ERR
    
    # Check if running in dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "Running in dry-run mode - no resources will be deleted"
        check_prerequisites
        if load_deployment_info || setup_environment_manual; then
            list_cloud_functions
            log_info "Dry-run: Would delete Cloud Functions and Firestore database"
            log_info "Dry-run: Would clean up local files"
            log_success "Dry-run completed successfully"
        fi
        return 0
    fi
    
    # Execute cleanup steps
    check_prerequisites
    
    # Try to load deployment info, fall back to manual setup
    if ! load_deployment_info; then
        setup_environment_manual
    fi
    
    confirm_destruction
    delete_specific_functions
    delete_all_functions
    delete_firestore
    cleanup_iam
    disable_apis
    cleanup_local_files
    delete_project
    verify_cleanup
    display_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --delete-project)
            DELETE_PROJECT="true"
            shift
            ;;
        --disable-apis)
            DISABLE_APIS="true"
            shift
            ;;
        --force)
            FORCE="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --project-id PROJECT_ID      Specify GCP project ID"
            echo "  --region REGION              Specify GCP region (default: us-central1)"
            echo "  --delete-project             Delete the entire project"
            echo "  --disable-apis               Disable APIs used by the solution"
            echo "  --force                      Skip confirmation prompts"
            echo "  --dry-run                    Show what would be deleted without deleting"
            echo "  --help                       Show this help message"
            echo
            echo "Environment variables:"
            echo "  PROJECT_ID                   GCP project ID"
            echo "  REGION                       GCP region"
            echo "  DELETE_PROJECT               Set to 'true' to delete project"
            echo "  DISABLE_APIS                 Set to 'true' to disable APIs"
            echo "  FORCE                        Set to 'true' to skip confirmations"
            echo
            echo "Examples:"
            echo "  $0                          # Interactive cleanup"
            echo "  $0 --force                  # Skip confirmations"
            echo "  $0 --delete-project --force # Delete entire project"
            echo "  $0 --dry-run               # Show what would be deleted"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"