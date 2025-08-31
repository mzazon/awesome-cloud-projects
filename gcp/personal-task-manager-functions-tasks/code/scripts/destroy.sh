#!/bin/bash

# Destroy script for Personal Task Manager with Cloud Functions and Google Tasks
# This script safely removes all resources created by the deployment

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"
readonly DEPLOYMENT_INFO_FILE="${PROJECT_DIR}/deployment_info.json"

# Default values (can be overridden by environment variables or deployment info)
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
FUNCTION_NAME="${FUNCTION_NAME:-task-manager}"

# Function to load deployment information
load_deployment_info() {
    if [[ -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        log_info "Loading deployment information from ${DEPLOYMENT_INFO_FILE}"
        
        # Extract values from JSON using basic text processing
        PROJECT_ID=$(grep '"project_id"' "${DEPLOYMENT_INFO_FILE}" | sed 's/.*": "\([^"]*\)".*/\1/')
        REGION=$(grep '"region"' "${DEPLOYMENT_INFO_FILE}" | sed 's/.*": "\([^"]*\)".*/\1/')
        FUNCTION_NAME=$(grep '"function_name"' "${DEPLOYMENT_INFO_FILE}" | sed 's/.*": "\([^"]*\)".*/\1/')
        
        log_info "Loaded from deployment info - Project: ${PROJECT_ID}, Region: ${REGION}, Function: ${FUNCTION_NAME}"
    else
        log_warning "Deployment info file not found. Using environment variables or defaults."
        
        # Check if PROJECT_ID is set
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "PROJECT_ID must be set either in environment or in deployment_info.json"
            log_info "Set PROJECT_ID environment variable: export PROJECT_ID=your-project-id"
            exit 1
        fi
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found."
        log_info "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project ${PROJECT_ID} does not exist or is not accessible."
        exit 1
    fi
    
    log_success "Prerequisites check completed successfully"
}

# Function to confirm deletion
confirm_deletion() {
    local force_delete="${1:-false}"
    
    if [[ "${force_delete}" == "true" ]]; then
        log_warning "Force delete mode enabled. Skipping confirmation."
        return 0
    fi
    
    echo
    log_warning "=== DELETION CONFIRMATION ==="
    log_warning "This will delete the following resources:"
    echo "  • Cloud Function: ${FUNCTION_NAME} (in ${REGION})"
    echo "  • Service Account: task-manager-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "  • Service Account Keys"
    echo "  • Local files: credentials.json, function code, deployment info"
    echo
    log_warning "Project ${PROJECT_ID} will NOT be deleted (use --delete-project for that)"
    echo
    
    while true; do
        read -p "Are you sure you want to proceed? (yes/no): " yn
        case $yn in
            [Yy]es|[Yy])
                log_info "Proceeding with deletion..."
                break
                ;;
            [Nn]o|[Nn])
                log_info "Deletion cancelled by user."
                exit 0
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Function to delete Cloud Function
delete_function() {
    log_info "Deleting Cloud Function: ${FUNCTION_NAME}"
    
    # Set project context
    gcloud config set project "${PROJECT_ID}"
    
    # Check if function exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
        log_info "Found function ${FUNCTION_NAME} in region ${REGION}"
        
        if gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --quiet; then
            log_success "Cloud Function deleted successfully"
        else
            log_error "Failed to delete Cloud Function"
            return 1
        fi
    else
        log_warning "Cloud Function ${FUNCTION_NAME} not found in region ${REGION}"
    fi
}

# Function to delete service account
delete_service_account() {
    log_info "Deleting service account and keys..."
    
    local sa_name="task-manager-sa"
    local sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "${sa_email}" &> /dev/null; then
        log_info "Found service account: ${sa_email}"
        
        # List and delete all keys first
        log_info "Deleting service account keys..."
        local key_ids
        key_ids=$(gcloud iam service-accounts keys list \
            --iam-account="${sa_email}" \
            --filter="keyType:USER_MANAGED" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${key_ids}" ]]; then
            while IFS= read -r key_id; do
                if [[ -n "${key_id}" ]]; then
                    log_info "Deleting key: ${key_id}"
                    gcloud iam service-accounts keys delete "${key_id}" \
                        --iam-account="${sa_email}" \
                        --quiet || log_warning "Failed to delete key ${key_id}"
                fi
            done <<< "${key_ids}"
        else
            log_info "No user-managed keys found for service account"
        fi
        
        # Delete the service account
        log_info "Deleting service account: ${sa_email}"
        if gcloud iam service-accounts delete "${sa_email}" --quiet; then
            log_success "Service account deleted successfully"
        else
            log_error "Failed to delete service account"
            return 1
        fi
    else
        log_warning "Service account ${sa_email} not found"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_delete=(
        "${PROJECT_DIR}/function/credentials.json"
        "${PROJECT_DIR}/function/main.py"
        "${PROJECT_DIR}/function/requirements.txt"
        "${PROJECT_DIR}/function_url.txt"
        "${PROJECT_DIR}/temp/credentials.json"
    )
    
    local dirs_to_delete=(
        "${PROJECT_DIR}/function"
        "${PROJECT_DIR}/temp"
    )
    
    # Delete files
    for file in "${files_to_delete[@]}"; do
        if [[ -f "${file}" ]]; then
            log_info "Removing file: ${file}"
            rm -f "${file}"
        fi
    done
    
    # Delete directories if empty
    for dir in "${dirs_to_delete[@]}"; do
        if [[ -d "${dir}" ]]; then
            log_info "Removing directory: ${dir}"
            rmdir "${dir}" 2>/dev/null || log_warning "Directory ${dir} not empty, leaving it"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to delete project (optional)
delete_project() {
    log_warning "=== PROJECT DELETION WARNING ==="
    log_warning "You have requested to delete the entire project: ${PROJECT_ID}"
    log_warning "This will:"
    echo "  • Delete ALL resources in the project"
    echo "  • Remove ALL data permanently"
    echo "  • This action CANNOT be undone"
    echo
    
    while true; do
        read -p "Are you absolutely sure you want to DELETE THE ENTIRE PROJECT? (DELETE/cancel): " response
        case $response in
            DELETE)
                log_warning "Proceeding with project deletion..."
                break
                ;;
            cancel|Cancel|CANCEL)
                log_info "Project deletion cancelled."
                return 0
                ;;
            *)
                echo "Please type 'DELETE' to confirm or 'cancel' to abort."
                ;;
        esac
    done
    
    log_info "Deleting project: ${PROJECT_ID}"
    if gcloud projects delete "${PROJECT_ID}" --quiet; then
        log_success "Project deleted successfully"
        log_warning "Note: Project deletion can take several minutes to complete"
    else
        log_error "Failed to delete project"
        return 1
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local verification_failed=false
    
    # Check if function still exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
        log_error "Cloud Function ${FUNCTION_NAME} still exists"
        verification_failed=true
    else
        log_success "Cloud Function successfully removed"
    fi
    
    # Check if service account still exists
    local sa_email="task-manager-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "${sa_email}" &> /dev/null; then
        log_error "Service account ${sa_email} still exists"
        verification_failed=true
    else
        log_success "Service account successfully removed"
    fi
    
    # Check local files
    if [[ -f "${PROJECT_DIR}/function/credentials.json" ]]; then
        log_error "Credentials file still exists locally"
        verification_failed=true
    else
        log_success "Local credentials cleaned up"
    fi
    
    if [[ "${verification_failed}" == "true" ]]; then
        log_error "Cleanup verification failed. Some resources may still exist."
        log_info "You may need to manually remove remaining resources."
        return 1
    else
        log_success "Cleanup verification passed successfully"
    fi
}

# Function to delete deployment info
delete_deployment_info() {
    if [[ -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        log_info "Removing deployment info file"
        rm -f "${DEPLOYMENT_INFO_FILE}"
        log_success "Deployment info file removed"
    fi
}

# Function to display summary
display_summary() {
    log_success "=== CLEANUP SUMMARY ==="
    echo
    log_info "The following resources have been removed:"
    echo "  ✓ Cloud Function: ${FUNCTION_NAME}"
    echo "  ✓ Service Account: task-manager-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "  ✓ Service Account Keys"
    echo "  ✓ Local files and directories"
    echo "  ✓ Deployment information"
    echo
    
    log_info "Project ${PROJECT_ID} has been retained (APIs may still be enabled)"
    log_info "To disable APIs, run:"
    echo "  gcloud services disable cloudfunctions.googleapis.com tasks.googleapis.com --project=${PROJECT_ID}"
    echo
    log_success "Cleanup completed successfully!"
}

# Function to handle cleanup on script exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Cleanup failed with exit code ${exit_code}"
        log_info "Some resources may still exist and require manual cleanup"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Destroy Personal Task Manager resources"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID     Google Cloud Project ID (can be loaded from deployment_info.json)"
    echo "  REGION         Deployment region (default: us-central1)"
    echo "  FUNCTION_NAME  Cloud Function name (default: task-manager)"
    echo
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -f, --force          Skip confirmation prompts"
    echo "  --delete-project     Also delete the entire Google Cloud project"
    echo "  --dry-run            Show what would be deleted without actually doing it"
    echo
    echo "Examples:"
    echo "  $0                                # Interactive cleanup"
    echo "  $0 --force                        # Skip confirmations"
    echo "  $0 --delete-project               # Also delete the project"
    echo "  PROJECT_ID=my-project $0          # Cleanup specific project"
    echo "  $0 --dry-run                      # Preview cleanup actions"
}

# Function to perform dry run
dry_run() {
    log_info "=== DRY RUN MODE ==="
    log_info "The following actions would be performed:"
    echo
    
    # Check what would be deleted
    gcloud config set project "${PROJECT_ID}"
    
    echo "Resources that would be deleted:"
    
    # Check function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
        echo "  ✓ Cloud Function: ${FUNCTION_NAME} (in ${REGION})"
    else
        echo "  - Cloud Function: ${FUNCTION_NAME} (not found)"
    fi
    
    # Check service account
    local sa_email="task-manager-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "${sa_email}" &> /dev/null; then
        echo "  ✓ Service Account: ${sa_email}"
        
        # Check keys
        local key_count
        key_count=$(gcloud iam service-accounts keys list \
            --iam-account="${sa_email}" \
            --filter="keyType:USER_MANAGED" \
            --format="value(name)" 2>/dev/null | wc -l || echo "0")
        echo "  ✓ Service Account Keys: ${key_count} user-managed keys"
    else
        echo "  - Service Account: ${sa_email} (not found)"
    fi
    
    # Check local files
    local local_files=(
        "${PROJECT_DIR}/function/credentials.json"
        "${PROJECT_DIR}/function/main.py"
        "${PROJECT_DIR}/function/requirements.txt"
        "${PROJECT_DIR}/function_url.txt"
        "${DEPLOYMENT_INFO_FILE}"
    )
    
    echo "  Local files that would be removed:"
    for file in "${local_files[@]}"; do
        if [[ -f "${file}" ]]; then
            echo "    ✓ ${file}"
        else
            echo "    - ${file} (not found)"
        fi
    done
    
    echo
    log_info "No actual changes were made (dry run mode)"
}

# Main execution function
main() {
    local force_delete=false
    local delete_project_flag=false
    local dry_run_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -f|--force)
                force_delete=true
                shift
                ;;
            --delete-project)
                delete_project_flag=true
                shift
                ;;
            --dry-run)
                dry_run_mode=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set up exit trap
    trap cleanup_on_exit EXIT
    
    log_info "Starting cleanup of Personal Task Manager resources..."
    
    # Load deployment information
    load_deployment_info
    
    # Check prerequisites
    check_prerequisites
    
    log_info "Target Project: ${PROJECT_ID}"
    log_info "Target Region: ${REGION}"
    log_info "Target Function: ${FUNCTION_NAME}"
    echo
    
    if [[ "${dry_run_mode}" == "true" ]]; then
        dry_run
        exit 0
    fi
    
    # Confirm deletion
    confirm_deletion "${force_delete}"
    
    # Execute cleanup steps
    delete_function
    delete_service_account
    cleanup_local_files
    
    # Verify cleanup
    if verify_cleanup; then
        delete_deployment_info
        
        # Delete project if requested
        if [[ "${delete_project_flag}" == "true" ]]; then
            delete_project
        fi
        
        display_summary
        log_success "All resources cleaned up successfully!"
    else
        log_error "Cleanup verification failed"
        exit 1
    fi
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi