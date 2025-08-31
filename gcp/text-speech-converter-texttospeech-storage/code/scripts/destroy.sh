#!/bin/bash

# Text-to-Speech Converter Cleanup Script
# GCP Text-to-Speech with Cloud Storage Integration
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Configuration and environment variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "${LOG_FILE}"
}

# Error handling
handle_error() {
    log_error "Cleanup failed on line $1"
    log_error "Check ${LOG_FILE} for detailed error information"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Text-to-Speech Converter resources

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -b, --bucket-name BUCKET       Storage bucket name to delete
    -d, --dry-run                  Show what would be deleted without executing
    -f, --force                    Skip confirmation prompts
    --delete-project               Delete the entire GCP project (DESTRUCTIVE)
    --keep-bucket                  Keep the storage bucket and its contents
    --keep-files                   Keep local files and virtual environment
    -h, --help                     Show this help message

EXAMPLES:
    $0 --project-id my-tts-project
    $0 --project-id my-project --bucket-name my-audio-bucket
    $0 --project-id my-project --dry-run
    $0 --project-id my-project --force --delete-project

EOF
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -b|--bucket-name)
                BUCKET_NAME="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_CLEANUP=true
                shift
                ;;
            --delete-project)
                DELETE_PROJECT=true
                shift
                ;;
            --keep-bucket)
                KEEP_BUCKET=true
                shift
                ;;
            --keep-files)
                KEEP_FILES=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Set defaults
    DRY_RUN="${DRY_RUN:-false}"
    FORCE_CLEANUP="${FORCE_CLEANUP:-false}"
    DELETE_PROJECT="${DELETE_PROJECT:-false}"
    KEEP_BUCKET="${KEEP_BUCKET:-false}"
    KEEP_FILES="${KEEP_FILES:-false}"

    # Validate required parameters
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "Project ID is required. Use --project-id option."
        usage
    fi
}

# Load configuration from deployment
load_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        log "Loading configuration from ${CONFIG_FILE}..."
        source "${CONFIG_FILE}"
        
        # Override with command line arguments if provided
        if [[ -z "${BUCKET_NAME:-}" ]] && [[ -n "${BUCKET_NAME:-}" ]]; then
            BUCKET_NAME="${BUCKET_NAME}"
        fi
        
        log_success "Configuration loaded successfully"
        log "Deployment Project ID: ${PROJECT_ID}"
        log "Deployment Region: ${REGION:-unknown}"
        log "Deployment Bucket: ${BUCKET_NAME:-unknown}"
    else
        log_warning "No deployment configuration found at ${CONFIG_FILE}"
        log_warning "Some resources may need to be cleaned up manually"
        
        # If bucket name not provided via CLI, try to auto-detect
        if [[ -z "${BUCKET_NAME:-}" ]]; then
            log "Attempting to auto-detect bucket name..."
            local detected_buckets
            if detected_buckets=$(gcloud storage ls --project="${PROJECT_ID}" 2>/dev/null | grep "tts-audio-" | head -1); then
                BUCKET_NAME=$(basename "${detected_buckets}")
                log_success "Auto-detected bucket: ${BUCKET_NAME}"
            else
                log_warning "Could not auto-detect bucket name. Use --bucket-name option if cleanup fails."
            fi
        fi
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."

    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi

    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi

    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project '${PROJECT_ID}' does not exist or you don't have access to it."
        exit 1
    fi

    log_success "Prerequisites check completed"
}

# Confirmation prompt
confirm_cleanup() {
    if [[ "${FORCE_CLEANUP}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi

    echo
    log_warning "This will delete the following resources:"
    echo "  • Project: ${PROJECT_ID}"
    if [[ -n "${BUCKET_NAME:-}" ]] && [[ "${KEEP_BUCKET}" != "true" ]]; then
        echo "  • Storage Bucket: gs://${BUCKET_NAME}"
        echo "  • All audio files in the bucket"
    fi
    if [[ "${KEEP_FILES}" != "true" ]]; then
        echo "  • Local Python virtual environment"
        echo "  • Local converter script"
        echo "  • Local configuration files"
    fi
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo "  • THE ENTIRE GCP PROJECT (IRREVERSIBLE)"
    fi
    echo

    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# List and delete storage bucket contents
cleanup_storage_bucket() {
    if [[ "${KEEP_BUCKET}" == "true" ]] || [[ -z "${BUCKET_NAME:-}" ]]; then
        log "Skipping bucket cleanup (keep-bucket flag or no bucket name)"
        return
    fi

    log "Cleaning up Cloud Storage bucket..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete all objects in bucket: gs://${BUCKET_NAME}"
        log "[DRY RUN] Would delete bucket: gs://${BUCKET_NAME}"
        return
    fi

    # Check if bucket exists
    if ! gcloud storage ls "gs://${BUCKET_NAME}" &> /dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} does not exist or is not accessible"
        return
    fi

    # List bucket contents before deletion
    log "Listing bucket contents..."
    local file_count
    if file_count=$(gcloud storage ls "gs://${BUCKET_NAME}/**" 2>/dev/null | wc -l); then
        if [[ ${file_count} -gt 0 ]]; then
            log "Found ${file_count} files in bucket"
            
            # Show files to be deleted
            log "Files to be deleted:"
            gcloud storage ls "gs://${BUCKET_NAME}/**" 2>/dev/null | head -10 | while read -r file; do
                log "  • ${file}"
            done
            
            if [[ ${file_count} -gt 10 ]]; then
                log "  • ... and $((file_count - 10)) more files"
            fi
        else
            log "Bucket is empty"
        fi
    fi

    # Delete all objects in the bucket
    log "Deleting all objects from bucket..."
    if gcloud storage rm -r "gs://${BUCKET_NAME}/**" >> "${LOG_FILE}" 2>&1; then
        log_success "All objects deleted from bucket"
    else
        log_warning "Some objects may have failed to delete (bucket might be empty)"
    fi

    # Delete the bucket itself
    log "Deleting storage bucket..."
    if gcloud storage buckets delete "gs://${BUCKET_NAME}" --quiet >> "${LOG_FILE}" 2>&1; then
        log_success "Storage bucket deleted: gs://${BUCKET_NAME}"
    else
        log_error "Failed to delete storage bucket. It may not be empty or may not exist."
    fi
}

# Clean up local files
cleanup_local_files() {
    if [[ "${KEEP_FILES}" == "true" ]]; then
        log "Skipping local file cleanup (keep-files flag)"
        return
    fi

    log "Cleaning up local files..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete local Python virtual environment"
        log "[DRY RUN] Would delete converter script"
        log "[DRY RUN] Would delete configuration files"
        log "[DRY RUN] Would delete local audio files"
        return
    fi

    # Remove Python virtual environment
    if [[ -d "${SCRIPT_DIR}/venv" ]]; then
        log "Removing Python virtual environment..."
        rm -rf "${SCRIPT_DIR}/venv"
        log_success "Python virtual environment removed"
    fi

    # Remove converter script
    if [[ -f "${SCRIPT_DIR}/text_to_speech_converter.py" ]]; then
        log "Removing converter script..."
        rm -f "${SCRIPT_DIR}/text_to_speech_converter.py"
        log_success "Converter script removed"
    fi

    # Remove configuration file
    if [[ -f "${CONFIG_FILE}" ]]; then
        log "Removing configuration file..."
        rm -f "${CONFIG_FILE}"
        log_success "Configuration file removed"
    fi

    # Remove any local audio files
    local audio_files
    if audio_files=$(find "${SCRIPT_DIR}" -name "*.mp3" 2>/dev/null); then
        if [[ -n "${audio_files}" ]]; then
            log "Removing local audio files..."
            echo "${audio_files}" | xargs rm -f
            log_success "Local audio files removed"
        fi
    fi

    # Clean up log files (except current one)
    find "${SCRIPT_DIR}" -name "*.log" -not -name "$(basename "${LOG_FILE}")" -delete 2>/dev/null || true
}

# Disable APIs (optional - usually not necessary)
disable_apis() {
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        log "Skipping API disable (project will be deleted)"
        return
    fi

    log "APIs will remain enabled (they don't incur charges when unused)"
    log "To manually disable APIs later, run:"
    log "  gcloud services disable texttospeech.googleapis.com --project=${PROJECT_ID}"
    log "  gcloud services disable storage.googleapis.com --project=${PROJECT_ID}"
}

# Delete the entire project (optional)
delete_project() {
    if [[ "${DELETE_PROJECT}" != "true" ]]; then
        return
    fi

    log_warning "Deleting entire GCP project..."
    log_warning "This action is IRREVERSIBLE and will delete ALL resources in the project!"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete project: ${PROJECT_ID}"
        return
    fi

    # Final confirmation for project deletion
    if [[ "${FORCE_CLEANUP}" != "true" ]]; then
        echo
        log_warning "FINAL WARNING: You are about to delete the ENTIRE project '${PROJECT_ID}'"
        log_warning "This will delete ALL resources, data, and configurations in this project!"
        read -p "Type 'DELETE' in capital letters to confirm: " -r
        if [[ "${REPLY}" != "DELETE" ]]; then
            log "Project deletion cancelled"
            return
        fi
    fi

    log "Deleting project ${PROJECT_ID}..."
    if gcloud projects delete "${PROJECT_ID}" --quiet >> "${LOG_FILE}" 2>&1; then
        log_success "Project deleted: ${PROJECT_ID}"
        log_warning "Project deletion may take several minutes to complete"
    else
        log_error "Failed to delete project. It may be protected or you may lack permissions."
    fi
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Verification skipped in dry-run mode"
        return
    fi

    log "Verifying cleanup completion..."

    # Check if project still exists (unless we deleted it)
    if [[ "${DELETE_PROJECT}" != "true" ]]; then
        if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
            log_success "Project still exists: ${PROJECT_ID}"
        else
            log_warning "Project no longer accessible or doesn't exist"
        fi
    fi

    # Check if bucket still exists (unless we kept it or deleted the project)
    if [[ "${KEEP_BUCKET}" != "true" ]] && [[ "${DELETE_PROJECT}" != "true" ]] && [[ -n "${BUCKET_NAME:-}" ]]; then
        if gcloud storage ls "gs://${BUCKET_NAME}" &> /dev/null; then
            log_warning "Bucket still exists: gs://${BUCKET_NAME}"
        else
            log_success "Bucket successfully removed: gs://${BUCKET_NAME}"
        fi
    fi

    # Check local files
    if [[ "${KEEP_FILES}" != "true" ]]; then
        local remaining_files=()
        [[ -d "${SCRIPT_DIR}/venv" ]] && remaining_files+=("Python virtual environment")
        [[ -f "${SCRIPT_DIR}/text_to_speech_converter.py" ]] && remaining_files+=("Converter script")
        [[ -f "${CONFIG_FILE}" ]] && remaining_files+=("Configuration file")

        if [[ ${#remaining_files[@]} -gt 0 ]]; then
            log_warning "Some local files still exist: ${remaining_files[*]}"
        else
            log_success "All local files successfully removed"
        fi
    fi

    log_success "Cleanup verification completed"
}

# Display cleanup summary
show_cleanup_summary() {
    log_success "=== Cleanup Summary ==="
    log_success "Project: ${PROJECT_ID}"
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        log_success "Action: Entire project deleted"
    else
        if [[ "${KEEP_BUCKET}" == "true" ]]; then
            log_success "Storage Bucket: Kept (gs://${BUCKET_NAME:-unknown})"
        else
            log_success "Storage Bucket: Deleted (gs://${BUCKET_NAME:-unknown})"
        fi
        
        if [[ "${KEEP_FILES}" == "true" ]]; then
            log_success "Local Files: Kept"
        else
            log_success "Local Files: Removed"
        fi
    fi

    echo
    if [[ "${DELETE_PROJECT}" != "true" ]]; then
        log_success "=== Manual Cleanup (if needed) ==="
        echo "To manually clean up any remaining resources:"
        echo "1. Check for remaining storage buckets:"
        echo "   gcloud storage ls --project=${PROJECT_ID}"
        echo
        echo "2. Disable APIs if desired:"
        echo "   gcloud services disable texttospeech.googleapis.com --project=${PROJECT_ID}"
        echo "   gcloud services disable storage.googleapis.com --project=${PROJECT_ID}"
        echo
        echo "3. Delete the project entirely:"
        echo "   gcloud projects delete ${PROJECT_ID}"
    fi
}

# Main cleanup function
main() {
    echo "🧹 Text-to-Speech Converter Cleanup Script"
    echo "=========================================="
    echo

    # Initialize log file
    echo "Cleanup started at $(date)" > "${LOG_FILE}"

    # Parse command line arguments
    parse_args "$@"

    # Load deployment configuration
    load_config

    # Show what will be cleaned up
    log "Cleanup Configuration:"
    log "Project ID: ${PROJECT_ID}"
    log "Bucket Name: ${BUCKET_NAME:-auto-detect}"
    log "Dry Run: ${DRY_RUN}"
    log "Force Cleanup: ${FORCE_CLEANUP}"
    log "Delete Project: ${DELETE_PROJECT}"
    log "Keep Bucket: ${KEEP_BUCKET}"
    log "Keep Files: ${KEEP_FILES}"
    echo

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No actual resources will be deleted"
        echo
    fi

    # Execute cleanup steps
    check_prerequisites
    confirm_cleanup
    cleanup_storage_bucket
    cleanup_local_files
    disable_apis
    delete_project
    verify_cleanup
    show_cleanup_summary

    log_success "Cleanup completed successfully!"
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warning "Cleanup interrupted by user"
    exit 130
}

trap cleanup_on_interrupt SIGINT SIGTERM

# Execute main function with all arguments
main "$@"