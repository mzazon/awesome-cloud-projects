#!/bin/bash

set -euo pipefail

# Simple File Sharing with Cloud Storage and Functions - Cleanup Script
# This script safely removes all resources created by the deployment script

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.json"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warn() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup failed. Check ${LOG_FILE} for details."
    log_warn "Some resources may still exist and incur charges."
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely remove all resources created by the file sharing deployment.

OPTIONS:
    -p, --project       Google Cloud project ID (required if no deployment info)
    -r, --region        Deployment region (required if no deployment info)
    -n, --name          Resource name suffix (required if no deployment info)
    -f, --force         Skip confirmation prompts (dangerous!)
    -y, --yes           Automatically answer yes to prompts
    --dry-run           Show what would be deleted without actually deleting
    --keep-project      Don't delete the project (useful for shared projects)
    -h, --help          Show this help message

EXAMPLES:
    $0                                      # Use deployment-info.json
    $0 --project my-project-123 --region us-central1 --name abc123
    $0 --dry-run                           # Preview deletions
    $0 --force --keep-project              # Skip confirmations, keep project

NOTES:
    - This script will attempt to read deployment-info.json first
    - If deployment info is not found, you must provide project, region, and name
    - Use --dry-run to preview what will be deleted
    - Use --keep-project for shared projects to avoid accidental deletion

EOF
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        log_info "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    if [[ -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        log_info "Loading deployment information from ${DEPLOYMENT_INFO_FILE}"
        
        # Use jq if available, otherwise use basic parsing
        if command -v jq &> /dev/null; then
            PROJECT_ID=$(jq -r '.project_id' "${DEPLOYMENT_INFO_FILE}")
            REGION=$(jq -r '.region' "${DEPLOYMENT_INFO_FILE}")
            ZONE=$(jq -r '.zone' "${DEPLOYMENT_INFO_FILE}")
            NAME_SUFFIX=$(jq -r '.name_suffix' "${DEPLOYMENT_INFO_FILE}")
            BUCKET_NAME=$(jq -r '.bucket_name' "${DEPLOYMENT_INFO_FILE}")
            UPLOAD_FUNCTION_NAME=$(jq -r '.upload_function_name' "${DEPLOYMENT_INFO_FILE}")
            LINK_FUNCTION_NAME=$(jq -r '.link_function_name' "${DEPLOYMENT_INFO_FILE}")
        else
            # Basic parsing without jq
            PROJECT_ID=$(grep '"project_id"' "${DEPLOYMENT_INFO_FILE}" | cut -d'"' -f4)
            REGION=$(grep '"region"' "${DEPLOYMENT_INFO_FILE}" | cut -d'"' -f4)
            ZONE=$(grep '"zone"' "${DEPLOYMENT_INFO_FILE}" | cut -d'"' -f4)
            NAME_SUFFIX=$(grep '"name_suffix"' "${DEPLOYMENT_INFO_FILE}" | cut -d'"' -f4)
            BUCKET_NAME=$(grep '"bucket_name"' "${DEPLOYMENT_INFO_FILE}" | cut -d'"' -f4)
            UPLOAD_FUNCTION_NAME=$(grep '"upload_function_name"' "${DEPLOYMENT_INFO_FILE}" | cut -d'"' -f4)
            LINK_FUNCTION_NAME=$(grep '"link_function_name"' "${DEPLOYMENT_INFO_FILE}" | cut -d'"' -f4)
        fi
        
        log_success "Deployment information loaded successfully"
        return 0
    else
        log_warn "Deployment info file not found: ${DEPLOYMENT_INFO_FILE}"
        return 1
    fi
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -n|--name)
                NAME_SUFFIX="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -y|--yes)
                YES=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --keep-project)
                KEEP_PROJECT=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Try to load deployment info if not provided via command line
    if [[ -z "${PROJECT_ID:-}" ]] || [[ -z "${REGION:-}" ]] || [[ -z "${NAME_SUFFIX:-}" ]]; then
        if ! load_deployment_info; then
            log_error "Missing required parameters and no deployment info found."
            log_error "Please provide --project, --region, and --name parameters."
            show_help
            exit 1
        fi
    fi
    
    # Validate required parameters
    if [[ -z "${PROJECT_ID:-}" ]] || [[ -z "${REGION:-}" ]] || [[ -z "${NAME_SUFFIX:-}" ]]; then
        log_error "Missing required parameters: project, region, and name suffix are required."
        show_help
        exit 1
    fi
    
    # Set resource names if not already set
    BUCKET_NAME="${BUCKET_NAME:-file-share-bucket-${NAME_SUFFIX}}"
    UPLOAD_FUNCTION_NAME="${UPLOAD_FUNCTION_NAME:-upload-file-${NAME_SUFFIX}}"
    LINK_FUNCTION_NAME="${LINK_FUNCTION_NAME:-generate-link-${NAME_SUFFIX}}"
}

# Validate project access
validate_project() {
    log_info "Validating project access: ${PROJECT_ID}"
    
    # Check if project exists and user has access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project '${PROJECT_ID}' not found or no access"
        exit 1
    fi
    
    # Set project configuration
    gcloud config set project "${PROJECT_ID}"
    
    log_success "Project access validated"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "${FORCE:-false}" == "true" ]] || [[ "${YES:-false}" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warn "=== RESOURCES TO BE DELETED ==="
    log_warn "Project: ${PROJECT_ID}"
    log_warn "Region: ${REGION}"
    log_warn "Bucket: gs://${BUCKET_NAME} (and all contents)"
    log_warn "Upload Function: ${UPLOAD_FUNCTION_NAME}"
    log_warn "Link Function: ${LINK_FUNCTION_NAME}"
    
    if [[ "${KEEP_PROJECT:-false}" != "true" ]]; then
        log_warn "Project: ${PROJECT_ID} (ENTIRE PROJECT WILL BE DELETED)"
    fi
    
    echo
    log_error "WARNING: This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    if [[ "${KEEP_PROJECT:-false}" != "true" ]]; then
        echo
        log_error "FINAL WARNING: The entire project '${PROJECT_ID}' will be deleted!"
        read -p "Type the project ID to confirm project deletion: " project_confirmation
        if [[ "$project_confirmation" != "$PROJECT_ID" ]]; then
            log_error "Project ID confirmation failed. Cleanup cancelled."
            exit 1
        fi
    fi
}

# Delete Cloud Functions
delete_functions() {
    log_info "Deleting Cloud Functions..."
    
    local functions=("${UPLOAD_FUNCTION_NAME}" "${LINK_FUNCTION_NAME}")
    
    for function_name in "${functions[@]}"; do
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_info "[DRY RUN] Would delete function: ${function_name}"
            continue
        fi
        
        # Check if function exists
        if gcloud functions describe "${function_name}" --region "${REGION}" &> /dev/null; then
            log_info "Deleting function: ${function_name}"
            gcloud functions delete "${function_name}" \
                --region "${REGION}" \
                --quiet
            log_success "Function deleted: ${function_name}"
        else
            log_warn "Function not found: ${function_name}"
        fi
    done
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        log_success "Cloud Functions cleanup completed"
    fi
}

# Delete Cloud Storage bucket
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket: ${BUCKET_NAME}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would delete bucket: gs://${BUCKET_NAME} and all contents"
        return
    fi
    
    # Check if bucket exists
    if gcloud storage buckets describe "gs://${BUCKET_NAME}" &> /dev/null; then
        log_info "Deleting bucket and all contents: gs://${BUCKET_NAME}"
        
        # List files for logging (optional)
        local file_count
        file_count=$(gcloud storage ls "gs://${BUCKET_NAME}/**" 2>/dev/null | wc -l) || file_count=0
        if [[ $file_count -gt 0 ]]; then
            log_warn "Deleting ${file_count} files from bucket"
        fi
        
        # Delete bucket and all contents
        gcloud storage rm -r "gs://${BUCKET_NAME}"
        log_success "Bucket deleted: gs://${BUCKET_NAME}"
    else
        log_warn "Bucket not found: gs://${BUCKET_NAME}"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_delete=(
        "${SCRIPT_DIR}/../upload-function"
        "${SCRIPT_DIR}/../link-function"
        "${SCRIPT_DIR}/../file-share-interface.html"
        "${SCRIPT_DIR}/cors.json"
        "${DEPLOYMENT_INFO_FILE}"
    )
    
    for file_path in "${files_to_delete[@]}"; do
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            if [[ -e "${file_path}" ]]; then
                log_info "[DRY RUN] Would delete: ${file_path}"
            fi
            continue
        fi
        
        if [[ -e "${file_path}" ]]; then
            log_info "Deleting: ${file_path}"
            rm -rf "${file_path}"
            log_success "Deleted: ${file_path}"
        fi
    done
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        log_success "Local files cleanup completed"
    fi
}

# Delete project (optional)
delete_project() {
    if [[ "${KEEP_PROJECT:-false}" == "true" ]]; then
        log_info "Keeping project as requested: ${PROJECT_ID}"
        return
    fi
    
    log_info "Deleting project: ${PROJECT_ID}"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would delete project: ${PROJECT_ID}"
        return
    fi
    
    # Delete the project
    gcloud projects delete "${PROJECT_ID}" --quiet
    
    log_success "Project deletion initiated: ${PROJECT_ID}"
    log_info "Note: Project deletion may take several minutes to complete"
}

# Verify cleanup
verify_cleanup() {
    if [[ "${DRY_RUN:-false}" == "true" ]] || [[ "${KEEP_PROJECT:-false}" != "true" ]]; then
        return
    fi
    
    log_info "Verifying resource cleanup..."
    
    # Check functions
    local remaining_functions=0
    if gcloud functions describe "${UPLOAD_FUNCTION_NAME}" --region "${REGION}" &> /dev/null; then
        log_warn "Function still exists: ${UPLOAD_FUNCTION_NAME}"
        ((remaining_functions++))
    fi
    
    if gcloud functions describe "${LINK_FUNCTION_NAME}" --region "${REGION}" &> /dev/null; then
        log_warn "Function still exists: ${LINK_FUNCTION_NAME}"
        ((remaining_functions++))
    fi
    
    # Check bucket
    local bucket_exists=false
    if gcloud storage buckets describe "gs://${BUCKET_NAME}" &> /dev/null; then
        log_warn "Bucket still exists: gs://${BUCKET_NAME}"
        bucket_exists=true
    fi
    
    if [[ $remaining_functions -eq 0 ]] && [[ "$bucket_exists" == false ]]; then
        log_success "All resources successfully cleaned up"
    else
        log_warn "Some resources may still exist. Manual cleanup may be required."
    fi
}

# Print cleanup summary
print_summary() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "=== DRY RUN SUMMARY ==="
        log_info "No resources were actually deleted"
        log_info "Run without --dry-run to perform actual cleanup"
        return
    fi
    
    log_success "Cleanup completed!"
    echo
    log_info "=== CLEANUP SUMMARY ==="
    log_info "Project: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Bucket: gs://${BUCKET_NAME} - DELETED"
    log_info "Upload Function: ${UPLOAD_FUNCTION_NAME} - DELETED"
    log_info "Link Function: ${LINK_FUNCTION_NAME} - DELETED"
    log_info "Local Files: CLEANED UP"
    
    if [[ "${KEEP_PROJECT:-false}" == "true" ]]; then
        log_info "Project: ${PROJECT_ID} - KEPT (as requested)"
    else
        log_info "Project: ${PROJECT_ID} - DELETION INITIATED"
    fi
    
    echo
    log_info "=== NEXT STEPS ==="
    if [[ "${KEEP_PROJECT:-false}" != "true" ]]; then
        log_info "1. Project deletion may take several minutes"
        log_info "2. Monitor deletion status in Cloud Console"
        log_info "3. Verify no unexpected charges appear"
    else
        log_info "1. Verify all resources are cleaned up in Cloud Console"
        log_info "2. Check for any remaining billable resources"
        log_info "3. Consider disabling APIs if no longer needed"
    fi
    
    echo
    log_success "File sharing portal resources have been cleaned up!"
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Simple File Sharing Portal"
    log_info "Log file: ${LOG_FILE}"
    
    parse_arguments "$@"
    check_prerequisites
    validate_project
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        confirm_deletion
    fi
    
    delete_functions
    delete_storage_bucket
    cleanup_local_files
    
    if [[ "${KEEP_PROJECT:-false}" != "true" ]]; then
        delete_project
    fi
    
    verify_cleanup
    print_summary
    
    log_success "Cleanup script completed successfully!"
}

# Run main function with all arguments
main "$@"