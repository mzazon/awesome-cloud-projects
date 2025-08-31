#!/bin/bash

#
# Cleanup script for Unit Converter API with Cloud Functions and Storage
# This script removes all resources created by the deployment script
# Recipe: unit-converter-api-functions-storage
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly FUNCTION_SOURCE_DIR="${PROJECT_ROOT}/function-source"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Configuration
FUNCTION_NAME="unit-converter"
REGION="us-central1"
DRY_RUN=false
FORCE=false
KEEP_HISTORY=false

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

# Error handling
handle_error() {
    log_error "Cleanup encountered an error. Check ${LOG_FILE} for details."
    log "Some resources may not have been cleaned up completely."
    exit 1
}

trap handle_error ERR

# Help function
show_help() {
    cat << EOF
Cleanup Unit Converter API with Cloud Functions and Storage

Usage: $0 [OPTIONS]

Options:
    -p, --project PROJECT_ID    GCP project ID (required)
    -r, --region REGION         Deployment region (default: us-central1)
    -f, --function-name NAME    Cloud Function name (default: unit-converter)
    -b, --bucket-name NAME      Storage bucket name (auto-detected if not specified)
    --keep-history              Keep conversion history in storage bucket
    --force                     Skip confirmation prompts
    -d, --dry-run               Show what would be deleted without executing
    -h, --help                  Show this help message

Examples:
    $0 --project my-gcp-project
    $0 --project my-project --region us-east1 --force
    $0 --project my-project --keep-history --dry-run

Environment Variables:
    GOOGLE_CLOUD_PROJECT        GCP project ID (overridden by --project)
    GOOGLE_CLOUD_REGION         Deployment region (overridden by --region)

Warning: This script will permanently delete resources and data!
Make sure to backup any important conversion history data before running.

EOF
}

# Parse command line arguments
parse_args() {
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
            -f|--function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            -b|--bucket-name)
                BUCKET_NAME="$2"
                shift 2
                ;;
            --keep-history)
                KEEP_HISTORY=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
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

    # Set project from environment if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-}"
    fi

    # Set region from environment if not provided
    if [[ -n "${GOOGLE_CLOUD_REGION:-}" && "${REGION}" == "us-central1" ]]; then
        REGION="${GOOGLE_CLOUD_REGION}"
    fi

    # Validate required parameters
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "Project ID is required. Use --project or set GOOGLE_CLOUD_PROJECT environment variable."
        show_help
        exit 1
    fi
}

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."

    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi

    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi

    # Validate project access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Cannot access project '${PROJECT_ID}'. Check project ID and permissions."
        exit 1
    fi

    log_success "Prerequisites validated"
}

# Set project configuration
configure_project() {
    log "Configuring gcloud for project ${PROJECT_ID}..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would set project to: ${PROJECT_ID}"
        log "[DRY RUN] Would set region to: ${REGION}"
        return 0
    fi

    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set functions/region "${REGION}" --quiet

    log_success "Project configuration complete"
}

# Discover resources
discover_resources() {
    log "Discovering deployed resources..."

    # Find Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
        FUNCTION_EXISTS=true
        FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --format="value(httpsTrigger.url)" 2>/dev/null || echo "Unknown")
        log "Found Cloud Function: ${FUNCTION_NAME}"
    else
        FUNCTION_EXISTS=false
        log_warning "Cloud Function '${FUNCTION_NAME}' not found in region '${REGION}'"
    fi

    # Auto-discover storage bucket if not specified
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log "Auto-discovering storage bucket..."
        local buckets
        buckets=$(gcloud storage buckets list --filter="name:${PROJECT_ID}-conversion-history" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${buckets}" ]]; then
            # Take the first matching bucket
            BUCKET_NAME=$(echo "${buckets}" | head -n1)
            log "Auto-discovered bucket: ${BUCKET_NAME}"
        else
            log_warning "No conversion history bucket found for project ${PROJECT_ID}"
            BUCKET_EXISTS=false
            return 0
        fi
    fi

    # Check if bucket exists
    if [[ -n "${BUCKET_NAME:-}" ]] && gcloud storage buckets describe "gs://${BUCKET_NAME}" &> /dev/null; then
        BUCKET_EXISTS=true
        
        # Count conversion history files
        local history_count
        history_count=$(gcloud storage ls "gs://${BUCKET_NAME}/conversions/" 2>/dev/null | wc -l || echo "0")
        log "Found bucket: gs://${BUCKET_NAME} (${history_count} history files)"
    else
        BUCKET_EXISTS=false
        if [[ -n "${BUCKET_NAME:-}" ]]; then
            log_warning "Storage bucket 'gs://${BUCKET_NAME}' not found"
        fi
    fi

    log_success "Resource discovery complete"
}

# Confirm deletion
confirm_deletion() {
    if [[ "${FORCE}" == "true" || "${DRY_RUN}" == "true" ]]; then
        return 0
    fi

    echo
    log_warning "=== DELETION CONFIRMATION ==="
    log "You are about to delete the following resources:"
    echo

    if [[ "${FUNCTION_EXISTS}" == "true" ]]; then
        echo "  • Cloud Function: ${FUNCTION_NAME} (${REGION})"
        echo "    URL: ${FUNCTION_URL}"
    fi

    if [[ "${BUCKET_EXISTS}" == "true" ]]; then
        if [[ "${KEEP_HISTORY}" == "true" ]]; then
            echo "  • Storage Bucket: gs://${BUCKET_NAME} (KEPT - conversion history preserved)"
        else
            echo "  • Storage Bucket: gs://${BUCKET_NAME} (ALL DATA WILL BE PERMANENTLY DELETED)"
        fi
    fi

    if [[ -d "${FUNCTION_SOURCE_DIR}" ]]; then
        echo "  • Function source directory: ${FUNCTION_SOURCE_DIR}"
    fi

    echo
    log_warning "This action cannot be undone!"
    echo

    read -p "Are you sure you want to continue? (yes/no): " -r response
    case "${response}" in
        [yY][eE][sS])
            log "Deletion confirmed by user"
            ;;
        *)
            log "Deletion cancelled by user"
            exit 0
            ;;
    esac
}

# Delete Cloud Function
delete_function() {
    if [[ "${FUNCTION_EXISTS}" != "true" ]]; then
        log "Skipping function deletion - function does not exist"
        return 0
    fi

    log "Deleting Cloud Function: ${FUNCTION_NAME}..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete function: ${FUNCTION_NAME} in region ${REGION}"
        return 0
    fi

    if gcloud functions delete "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --quiet; then
        log_success "Cloud Function deleted successfully"
    else
        log_error "Failed to delete Cloud Function"
        return 1
    fi
}

# Delete storage bucket
delete_storage_bucket() {
    if [[ "${BUCKET_EXISTS}" != "true" ]]; then
        log "Skipping bucket deletion - bucket does not exist"
        return 0
    fi

    if [[ "${KEEP_HISTORY}" == "true" ]]; then
        log "Keeping storage bucket as requested: gs://${BUCKET_NAME}"
        log_warning "Remember to delete the bucket manually when no longer needed"
        return 0
    fi

    log "Deleting storage bucket: gs://${BUCKET_NAME}..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete bucket: gs://${BUCKET_NAME} and all contents"
        return 0
    fi

    # Delete all objects first, then bucket
    if gcloud storage rm -r "gs://${BUCKET_NAME}" --quiet; then
        log_success "Storage bucket and all contents deleted successfully"
    else
        log_error "Failed to delete storage bucket"
        return 1
    fi
}

# Clean up local files
cleanup_local_files() {
    if [[ ! -d "${FUNCTION_SOURCE_DIR}" ]]; then
        log "Skipping local cleanup - source directory does not exist"
        return 0
    fi

    log "Cleaning up local function source files..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete directory: ${FUNCTION_SOURCE_DIR}"
        return 0
    fi

    if rm -rf "${FUNCTION_SOURCE_DIR}"; then
        log_success "Local function source files deleted"
    else
        log_warning "Failed to delete local source files"
    fi
}

# Check for remaining resources
check_remaining_resources() {
    log "Checking for any remaining resources..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would check for remaining resources"
        return 0
    fi

    local remaining_functions
    remaining_functions=$(gcloud functions list --filter="name:${FUNCTION_NAME}" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${remaining_functions}" ]]; then
        log_warning "Some functions may still exist: ${remaining_functions}"
    fi

    # Check for related buckets
    local remaining_buckets
    remaining_buckets=$(gcloud storage buckets list --filter="name:${PROJECT_ID}-conversion-history" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${remaining_buckets}" ]]; then
        if [[ "${KEEP_HISTORY}" == "true" ]]; then
            log "Conversion history buckets preserved as requested: ${remaining_buckets}"
        else
            log_warning "Some buckets may still exist: ${remaining_buckets}"
        fi
    fi

    log_success "Resource check complete"
}

# Generate cleanup summary
generate_summary() {
    log "Generating cleanup summary..."

    cat << EOF | tee -a "${LOG_FILE}"

================================================================================
CLEANUP SUMMARY
================================================================================

Project ID:       ${PROJECT_ID}
Region:           ${REGION}
Function Name:    ${FUNCTION_NAME}
Bucket Name:      ${BUCKET_NAME:-"Not found"}

Resources Processed:
- Cloud Function: $(if [[ "${FUNCTION_EXISTS}" == "true" ]]; then echo "DELETED"; else echo "NOT FOUND"; fi)
- Storage Bucket: $(if [[ "${BUCKET_EXISTS}" == "true" ]]; then 
    if [[ "${KEEP_HISTORY}" == "true" ]]; then echo "PRESERVED"; else echo "DELETED"; fi
  else echo "NOT FOUND"; fi)
- Local Files:    $(if [[ -d "${FUNCTION_SOURCE_DIR}" ]] || [[ "${DRY_RUN}" == "true" ]]; then echo "DELETED"; else echo "NOT FOUND"; fi)

$(if [[ "${KEEP_HISTORY}" == "true" && "${BUCKET_EXISTS}" == "true" ]]; then
echo "Conversion History: PRESERVED in gs://${BUCKET_NAME}"
echo "To delete history later: gcloud storage rm -r gs://${BUCKET_NAME}"
echo
fi)Cost Impact:
- Cloud Functions billing will stop immediately
- Storage costs will continue if bucket was preserved
- No further charges will be incurred for deleted resources

Notes:
- It may take a few minutes for billing to reflect the changes
- DNS entries for the function URL may take up to 24 hours to clear
- Any cached responses may persist until cache expiration

$(if [[ "${DRY_RUN}" == "true" ]]; then
echo "DRY RUN COMPLETED - No resources were actually deleted"
else
echo "CLEANUP COMPLETED SUCCESSFULLY"
fi)

================================================================================
EOF

    if [[ "${DRY_RUN}" == "false" ]]; then
        log_success "Cleanup completed successfully!"
        log "All specified resources have been removed."
    else
        log_success "Dry-run completed successfully!"
        log "No resources were actually deleted."
    fi
}

# Main execution
main() {
    log "Starting Unit Converter API cleanup..."
    log "Log file: ${LOG_FILE}"

    parse_args "$@"
    validate_prerequisites
    configure_project
    discover_resources
    confirm_deletion
    delete_function
    delete_storage_bucket
    cleanup_local_files
    check_remaining_resources
    generate_summary

    log_success "Cleanup script completed successfully!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi