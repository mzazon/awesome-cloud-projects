#!/bin/bash

# QR Code Generator with Cloud Run and Storage - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
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

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CLEANUP_TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Configuration with defaults (can be overridden by environment variables)
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-qr-code-api}"
BUCKET_NAME="${BUCKET_NAME:-}"
FORCE_DELETE="${FORCE_DELETE:-false}"
DRY_RUN="${DRY_RUN:-false}"
DELETE_PROJECT="${DELETE_PROJECT:-false}"

# Application directory
readonly APP_DIR="${SCRIPT_DIR}/../app"

# Cleanup log file
readonly LOG_FILE="${SCRIPT_DIR}/destroy-${CLEANUP_TIMESTAMP}.log"

# Arrays to track what was actually deleted
declare -a DELETED_RESOURCES=()
declare -a FAILED_DELETIONS=()

# Cleanup function for script exit
cleanup() {
    local exit_code=$?
    
    if [[ ${#DELETED_RESOURCES[@]} -gt 0 ]]; then
        log_info "Successfully deleted resources:"
        printf '  - %s\n' "${DELETED_RESOURCES[@]}"
    fi
    
    if [[ ${#FAILED_DELETIONS[@]} -gt 0 ]]; then
        log_warn "Failed to delete resources:"
        printf '  - %s\n' "${FAILED_DELETIONS[@]}"
    fi
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Cleanup completed with errors. Check logs at: ${LOG_FILE}"
    else
        log_success "Cleanup completed successfully"
    fi
    
    return $exit_code
}

trap cleanup EXIT

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    local missing_deps=()
    
    # Check required commands
    if ! command_exists gcloud; then
        missing_deps+=("Google Cloud CLI (gcloud)")
    fi
    
    if ! command_exists gsutil; then
        missing_deps+=("Google Cloud Storage utilities (gsutil)")
    fi
    
    # Check if user is authenticated
    if ! gcloud auth application-default print-access-token &>/dev/null; then
        missing_deps+=("Google Cloud authentication - run 'gcloud auth application-default login'")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing prerequisites:"
        printf '%s\n' "${missing_deps[@]}" | sed 's/^/  - /'
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to auto-detect resources if not specified
auto_detect_resources() {
    log_info "Auto-detecting resources to clean up..."
    
    # Try to get current project if not specified
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null) || {
            log_error "No PROJECT_ID specified and unable to detect current project"
            log_info "Please set PROJECT_ID environment variable or use --project flag"
            exit 1
        }
        log_info "Detected project: ${PROJECT_ID}"
    fi
    
    # Try to detect bucket name from Cloud Run service if not specified
    if [[ -z "$BUCKET_NAME" ]] && gcloud run services describe "${SERVICE_NAME}" \
        --platform managed --region "${REGION}" &>/dev/null; then
        
        BUCKET_NAME=$(gcloud run services describe "${SERVICE_NAME}" \
            --platform managed \
            --region "${REGION}" \
            --format 'value(spec.template.spec.template.spec.containers[0].env[].value)' 2>/dev/null | head -1)
        
        if [[ -n "$BUCKET_NAME" ]]; then
            log_info "Detected bucket from Cloud Run service: ${BUCKET_NAME}"
        else
            log_warn "Could not auto-detect bucket name from Cloud Run service"
        fi
    fi
    
    # List current resources for confirmation
    log_info "Current resources in project ${PROJECT_ID}:"
    
    # Check Cloud Run services
    local run_services
    run_services=$(gcloud run services list --platform managed --region "${REGION}" \
        --filter="metadata.name:${SERVICE_NAME}" --format="value(metadata.name)" 2>/dev/null) || true
    
    if [[ -n "$run_services" ]]; then
        echo "  Cloud Run Services:"
        echo "    - ${SERVICE_NAME} (region: ${REGION})"
    fi
    
    # Check Storage buckets
    if [[ -n "$BUCKET_NAME" ]] && gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        local object_count
        object_count=$(gsutil ls "gs://${BUCKET_NAME}/**" 2>/dev/null | wc -l) || object_count=0
        echo "  Storage Buckets:"
        echo "    - ${BUCKET_NAME} (${object_count} objects)"
    fi
}

# Function to confirm deletion with user
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warn "This will permanently delete the following resources:"
    echo "  - Project: ${PROJECT_ID}"
    echo "  - Cloud Run Service: ${SERVICE_NAME} (region: ${REGION})"
    if [[ -n "$BUCKET_NAME" ]]; then
        echo "  - Storage Bucket: ${BUCKET_NAME} (including all objects)"
    fi
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo "  - Entire Project: ${PROJECT_ID} (THIS CANNOT BE UNDONE)"
    fi
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to delete Cloud Run service
delete_cloud_run_service() {
    log_info "Deleting Cloud Run service: ${SERVICE_NAME}"
    
    # Check if service exists
    if ! gcloud run services describe "${SERVICE_NAME}" \
        --platform managed --region "${REGION}" &>/dev/null; then
        log_warn "Cloud Run service ${SERVICE_NAME} not found or already deleted"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cloud Run service: ${SERVICE_NAME}"
        return 0
    fi
    
    # Delete the service
    gcloud run services delete "${SERVICE_NAME}" \
        --platform managed \
        --region "${REGION}" \
        --quiet 2>&1 | tee -a "${LOG_FILE}"
    
    local exit_code=${PIPESTATUS[0]}
    if [[ $exit_code -eq 0 ]]; then
        DELETED_RESOURCES+=("Cloud Run service: ${SERVICE_NAME}")
        log_success "Cloud Run service deleted successfully"
    else
        FAILED_DELETIONS+=("Cloud Run service: ${SERVICE_NAME}")
        log_error "Failed to delete Cloud Run service"
        return 1
    fi
}

# Function to delete Storage bucket and contents
delete_storage_bucket() {
    if [[ -z "$BUCKET_NAME" ]]; then
        log_warn "No bucket name specified, skipping bucket deletion"
        return 0
    fi
    
    log_info "Deleting Storage bucket: ${BUCKET_NAME}"
    
    # Check if bucket exists
    if ! gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warn "Storage bucket ${BUCKET_NAME} not found or already deleted"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete bucket: gs://${BUCKET_NAME} (including all objects)"
        return 0
    fi
    
    # Count objects before deletion
    local object_count
    object_count=$(gsutil ls "gs://${BUCKET_NAME}/**" 2>/dev/null | wc -l) || object_count=0
    
    if [[ $object_count -gt 0 ]]; then
        log_info "Deleting ${object_count} objects from bucket..."
        # Delete all objects in the bucket (parallel for better performance)
        gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>&1 | tee -a "${LOG_FILE}" || {
            log_warn "Some objects may have failed to delete, continuing with bucket deletion"
        }
    fi
    
    # Delete the bucket itself
    gsutil rb "gs://${BUCKET_NAME}" 2>&1 | tee -a "${LOG_FILE}"
    
    local exit_code=${PIPESTATUS[0]}
    if [[ $exit_code -eq 0 ]]; then
        DELETED_RESOURCES+=("Storage bucket: ${BUCKET_NAME} (${object_count} objects)")
        log_success "Storage bucket deleted successfully"
    else
        FAILED_DELETIONS+=("Storage bucket: ${BUCKET_NAME}")
        log_error "Failed to delete storage bucket"
        return 1
    fi
}

# Function to clean up local application files
cleanup_local_files() {
    log_info "Cleaning up local application files..."
    
    if [[ ! -d "$APP_DIR" ]]; then
        log_info "No local application directory found"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete local directory: ${APP_DIR}"
        return 0
    fi
    
    # Remove the application directory
    rm -rf "${APP_DIR}" 2>&1 | tee -a "${LOG_FILE}"
    
    if [[ ! -d "$APP_DIR" ]]; then
        DELETED_RESOURCES+=("Local application files: ${APP_DIR}")
        log_success "Local application files cleaned up"
    else
        FAILED_DELETIONS+=("Local application files: ${APP_DIR}")
        log_error "Failed to clean up local application files"
        return 1
    fi
}

# Function to delete the entire project (optional)
delete_project() {
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        return 0
    fi
    
    log_warn "Deleting entire project: ${PROJECT_ID}"
    log_warn "THIS WILL DELETE ALL RESOURCES IN THE PROJECT AND CANNOT BE UNDONE!"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete project: ${PROJECT_ID}"
        return 0
    fi
    
    # Additional confirmation for project deletion
    if [[ "$FORCE_DELETE" != "true" ]]; then
        echo ""
        read -p "Type the project ID '${PROJECT_ID}' to confirm project deletion: " -r
        if [[ "$REPLY" != "$PROJECT_ID" ]]; then
            log_info "Project deletion cancelled - project ID did not match"
            return 0
        fi
    fi
    
    # Shut down the project
    gcloud projects delete "${PROJECT_ID}" --quiet 2>&1 | tee -a "${LOG_FILE}"
    
    local exit_code=${PIPESTATUS[0]}
    if [[ $exit_code -eq 0 ]]; then
        DELETED_RESOURCES+=("Project: ${PROJECT_ID}")
        log_success "Project deletion initiated (may take several minutes to complete)"
    else
        FAILED_DELETIONS+=("Project: ${PROJECT_ID}")
        log_error "Failed to delete project"
        return 1
    fi
}

# Function to clean up deployment logs (optional)
cleanup_logs() {
    log_info "Cleaning up old deployment logs..."
    
    local log_pattern="${SCRIPT_DIR}/deploy-*.log"
    local log_files=()
    
    # Find old log files (older than 7 days)
    while IFS= read -r -d '' file; do
        if [[ -f "$file" ]] && [[ $(find "$file" -mtime +7 2>/dev/null) ]]; then
            log_files+=("$file")
        fi
    done < <(find "${SCRIPT_DIR}" -name "deploy-*.log" -print0 2>/dev/null)
    
    if [[ ${#log_files[@]} -eq 0 ]]; then
        log_info "No old log files found"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete ${#log_files[@]} old log files"
        return 0
    fi
    
    for log_file in "${log_files[@]}"; do
        rm -f "$log_file" && \
            DELETED_RESOURCES+=("Log file: $(basename "$log_file")") || \
            FAILED_DELETIONS+=("Log file: $(basename "$log_file")")
    done
    
    log_success "Cleaned up ${#log_files[@]} old log files"
}

# Function to display cleanup summary
display_summary() {
    log_info "Cleanup Summary"
    echo "=========================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Service Name: ${SERVICE_NAME}"
    echo "Bucket Name: ${BUCKET_NAME:-<not specified>}"
    echo "Cleanup Timestamp: ${CLEANUP_TIMESTAMP}"
    echo ""
    
    if [[ ${#DELETED_RESOURCES[@]} -gt 0 ]]; then
        echo "✅ Successfully deleted:"
        printf '  - %s\n' "${DELETED_RESOURCES[@]}"
        echo ""
    fi
    
    if [[ ${#FAILED_DELETIONS[@]} -gt 0 ]]; then
        echo "❌ Failed to delete:"
        printf '  - %s\n' "${FAILED_DELETIONS[@]}"
        echo ""
        echo "You may need to manually clean up these resources."
        echo ""
    fi
    
    echo "=========================="
    echo "Cleanup logs saved to: ${LOG_FILE}"
    
    if [[ "$DELETE_PROJECT" == "true" ]] && [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "Note: Project deletion may take several minutes to complete."
        echo "You can check the status with: gcloud projects describe ${PROJECT_ID}"
    fi
}

# Function to display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up resources created by the QR Code Generator deployment

OPTIONS:
    -p, --project           Google Cloud Project ID
    -r, --region           GCP region (default: us-central1)
    -s, --service          Cloud Run service name (default: qr-code-api)
    -b, --bucket           Storage bucket name
    -f, --force            Skip confirmation prompts
    -d, --dry-run          Show what would be deleted without making changes
    --delete-project       Delete the entire project (DESTRUCTIVE)
    -h, --help             Show this help message
    
ENVIRONMENT VARIABLES:
    PROJECT_ID             Override default project ID
    REGION                 Override default region
    SERVICE_NAME           Override default service name
    BUCKET_NAME            Override default bucket name
    FORCE_DELETE           Set to 'true' to skip confirmations
    DRY_RUN                Set to 'true' for dry run mode
    DELETE_PROJECT         Set to 'true' to delete entire project

EXAMPLES:
    $0                                      # Interactive cleanup with auto-detection
    $0 -p my-project -b my-bucket           # Clean up specific resources
    $0 --dry-run                            # Show what would be deleted
    $0 --force --delete-project             # Delete everything including project
    FORCE_DELETE=true $0                    # Non-interactive cleanup

SAFETY FEATURES:
    - Auto-detection of resources when possible
    - Confirmation prompts for destructive operations
    - Dry run mode to preview changes
    - Detailed logging of all operations
    - Graceful handling of already-deleted resources

EOF
}

# Main cleanup function
main() {
    log_info "Starting QR Code Generator cleanup..."
    log_info "Cleanup ID: ${CLEANUP_TIMESTAMP}"
    
    # Parse command line arguments
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
            -s|--service)
                SERVICE_NAME="$2"
                shift 2
                ;;
            -b|--bucket)
                BUCKET_NAME="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_DELETE="true"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            --delete-project)
                DELETE_PROJECT="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Start logging
    {
        echo "Cleanup started at: $(date)"
        echo "Script: $0"
        echo "Arguments: $*"
        echo "PROJECT_ID=${PROJECT_ID}"
        echo "REGION=${REGION}"
        echo "SERVICE_NAME=${SERVICE_NAME}"
        echo "BUCKET_NAME=${BUCKET_NAME}"
        echo "FORCE_DELETE=${FORCE_DELETE}"
        echo "DRY_RUN=${DRY_RUN}"
        echo "DELETE_PROJECT=${DELETE_PROJECT}"
        echo "=========================="
    } > "${LOG_FILE}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Execute cleanup steps
    check_prerequisites
    auto_detect_resources
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_cloud_run_service
    delete_storage_bucket
    cleanup_local_files
    cleanup_logs
    delete_project  # This should be last as it deletes everything
    
    display_summary
    
    log_success "Cleanup process completed!"
    
    if [[ "$DRY_RUN" == "false" ]] && [[ ${#FAILED_DELETIONS[@]} -eq 0 ]]; then
        echo ""
        echo "All QR Code Generator resources have been successfully removed."
        if [[ "$DELETE_PROJECT" != "true" ]]; then
            echo "The project ${PROJECT_ID} remains active for other resources."
        fi
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi