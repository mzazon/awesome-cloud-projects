#!/bin/bash

# GCP Task Queue System Cleanup Script
# This script removes all resources created by the task queue system deployment
# Author: Generated from GCP Recipe
# Version: 1.0

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="/tmp/gcp-task-queue-destroy-$(date +%Y%m%d-%H%M%S).log"

# Configuration variables
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
QUEUE_NAME="${QUEUE_NAME:-background-tasks}"
FUNCTION_NAME="${FUNCTION_NAME:-task-processor}"
BUCKET_NAME="${BUCKET_NAME:-}"
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"
INTERACTIVE="${INTERACTIVE:-true}"

# Function to log messages with timestamp
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
    esac
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
}

# Function to display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup GCP Task Queue System resources

OPTIONS:
    -p, --project-id       GCP Project ID (required)
    -r, --region          GCP Region (default: us-central1)
    -q, --queue-name      Cloud Tasks queue name (default: background-tasks)
    -f, --function-name   Cloud Function name (default: task-processor)
    -b, --bucket-name     Storage bucket name (auto-detected if not provided)
    -d, --dry-run         Show what would be deleted without executing
    -F, --force           Skip confirmation prompts
    -y, --yes             Assume yes to all prompts (non-interactive mode)
    -h, --help            Show this help message
    -v, --verbose         Enable verbose logging

ENVIRONMENT VARIABLES:
    PROJECT_ID            GCP Project ID
    REGION               GCP Region
    FORCE                Skip confirmation prompts (true/false)
    DRY_RUN              Show actions without executing (true/false)

EXAMPLES:
    $0 -p my-project-123
    $0 --project-id my-project-123 --force
    DRY_RUN=true $0 -p my-project-123
    $0 -p my-project-123 --bucket-name my-custom-bucket

WARNING: This script will permanently delete resources and data.
         Make sure to backup any important data before running.

EOF
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -q|--queue-name)
                QUEUE_NAME="$2"
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
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -F|--force)
                FORCE=true
                INTERACTIVE=false
                shift
                ;;
            -y|--yes)
                INTERACTIVE=false
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Function to validate prerequisites
validate_prerequisites() {
    log "INFO" "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud >/dev/null 2>&1; then
        log "ERROR" "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log "ERROR" "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Validate project ID
    if [[ -z "$PROJECT_ID" ]]; then
        # Try to get from gcloud config or environment
        PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null || echo '')}"
        if [[ -z "$PROJECT_ID" ]]; then
            log "ERROR" "Project ID is required. Use -p flag or set PROJECT_ID environment variable."
            exit 1
        fi
    fi
    
    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log "ERROR" "Project '$PROJECT_ID' does not exist or is not accessible."
        exit 1
    fi
    
    log "INFO" "Prerequisites validation completed successfully"
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "$INTERACTIVE" == "false" ]] || [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo
    log "WARN" "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log "WARN" "This will permanently delete the following resources:"
    log "WARN" "  • Cloud Function: $FUNCTION_NAME"
    log "WARN" "  • Cloud Tasks Queue: $QUEUE_NAME"
    log "WARN" "  • Storage Bucket: ${BUCKET_NAME:-[auto-detected]}"
    log "WARN" "  • All data in the storage bucket"
    echo
    
    read -p "Are you sure you want to continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Operation cancelled by user"
        exit 0
    fi
    
    read -p "Type 'DELETE' to confirm permanent deletion: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log "INFO" "Operation cancelled - confirmation phrase not matched"
        exit 0
    fi
    
    log "INFO" "Destruction confirmed by user"
}

# Function to discover bucket name if not provided
discover_bucket_name() {
    if [[ -n "$BUCKET_NAME" ]]; then
        log "INFO" "Using provided bucket name: $BUCKET_NAME"
        return 0
    fi
    
    log "INFO" "Auto-discovering storage bucket..."
    
    # Try to get bucket name from function environment variables
    local function_bucket
    function_bucket=$(gcloud functions describe "$FUNCTION_NAME" \
        --gen2 \
        --region="$REGION" \
        --format="value(serviceConfig.environmentVariables.STORAGE_BUCKET)" 2>/dev/null || echo "")
    
    if [[ -n "$function_bucket" ]]; then
        BUCKET_NAME="$function_bucket"
        log "INFO" "Discovered bucket from function config: $BUCKET_NAME"
        return 0
    fi
    
    # Try common naming patterns
    local pattern_buckets=(
        "${PROJECT_ID}-task-results"
        "${PROJECT_ID}-task-results-*"
    )
    
    for pattern in "${pattern_buckets[@]}"; do
        local found_bucket
        found_bucket=$(gsutil ls "gs://${pattern}" 2>/dev/null | head -1 | sed 's|gs://||' | sed 's|/||' || echo "")
        if [[ -n "$found_bucket" ]]; then
            BUCKET_NAME="$found_bucket"
            log "INFO" "Discovered bucket by pattern: $BUCKET_NAME"
            return 0
        fi
    done
    
    log "WARN" "Could not auto-discover bucket name. Use -b flag to specify manually."
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local additional_args="${3:-}"
    
    case $resource_type in
        "function")
            gcloud functions describe "$resource_name" \
                --gen2 \
                --region="$REGION" \
                >/dev/null 2>&1
            ;;
        "queue")
            gcloud tasks queues describe "$resource_name" \
                --location="$REGION" \
                >/dev/null 2>&1
            ;;
        "bucket")
            gsutil ls "gs://$resource_name" >/dev/null 2>&1
            ;;
        *)
            log "ERROR" "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

# Function to delete Cloud Function
delete_function() {
    log "INFO" "Deleting Cloud Function: $FUNCTION_NAME"
    
    if ! resource_exists "function" "$FUNCTION_NAME"; then
        log "WARN" "Function '$FUNCTION_NAME' does not exist, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete function '$FUNCTION_NAME'"
        return 0
    fi
    
    # Delete the function
    if gcloud functions delete "$FUNCTION_NAME" \
        --gen2 \
        --region="$REGION" \
        --quiet; then
        log "INFO" "✅ Cloud Function '$FUNCTION_NAME' deleted successfully"
        
        # Wait for deletion to complete
        local attempts=0
        while resource_exists "function" "$FUNCTION_NAME" && [[ $attempts -lt 30 ]]; do
            log "DEBUG" "Waiting for function deletion to complete..."
            sleep 5
            ((attempts++))
        done
        
        if resource_exists "function" "$FUNCTION_NAME"; then
            log "WARN" "Function may still be in deletion process"
        fi
    else
        log "ERROR" "Failed to delete Cloud Function '$FUNCTION_NAME'"
        return 1
    fi
}

# Function to delete Cloud Tasks queue
delete_queue() {
    log "INFO" "Deleting Cloud Tasks queue: $QUEUE_NAME"
    
    if ! resource_exists "queue" "$QUEUE_NAME"; then
        log "WARN" "Queue '$QUEUE_NAME' does not exist, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete queue '$QUEUE_NAME'"
        return 0
    fi
    
    # Check for pending tasks
    local task_count
    task_count=$(gcloud tasks list \
        --queue="$QUEUE_NAME" \
        --location="$REGION" \
        --format="value(name)" 2>/dev/null | wc -l || echo "0")
    
    if [[ "$task_count" -gt 0 ]]; then
        log "WARN" "Queue has $task_count pending tasks. They will be lost."
        if [[ "$INTERACTIVE" == "true" ]] && [[ "$FORCE" == "false" ]]; then
            read -p "Continue with queue deletion? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "INFO" "Queue deletion cancelled by user"
                return 0
            fi
        fi
    fi
    
    # Delete the queue
    if gcloud tasks queues delete "$QUEUE_NAME" \
        --location="$REGION" \
        --quiet; then
        log "INFO" "✅ Cloud Tasks queue '$QUEUE_NAME' deleted successfully"
    else
        log "ERROR" "Failed to delete Cloud Tasks queue '$QUEUE_NAME'"
        return 1
    fi
}

# Function to delete storage bucket
delete_bucket() {
    if [[ -z "$BUCKET_NAME" ]]; then
        log "WARN" "No bucket name provided or discovered, skipping bucket deletion"
        return 0
    fi
    
    log "INFO" "Deleting storage bucket: $BUCKET_NAME"
    
    if ! resource_exists "bucket" "$BUCKET_NAME"; then
        log "WARN" "Bucket '$BUCKET_NAME' does not exist, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete bucket '$BUCKET_NAME' and all contents"
        return 0
    fi
    
    # Check bucket contents
    local object_count
    object_count=$(gsutil ls -r "gs://$BUCKET_NAME" 2>/dev/null | grep -v "/$" | wc -l || echo "0")
    
    if [[ "$object_count" -gt 0 ]]; then
        log "WARN" "Bucket contains $object_count objects. All data will be permanently lost."
        if [[ "$INTERACTIVE" == "true" ]] && [[ "$FORCE" == "false" ]]; then
            read -p "Continue with bucket deletion? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "INFO" "Bucket deletion cancelled by user"
                return 0
            fi
        fi
    fi
    
    # Delete bucket and all contents
    if gsutil -m rm -r "gs://$BUCKET_NAME"; then
        log "INFO" "✅ Storage bucket '$BUCKET_NAME' deleted successfully"
    else
        log "ERROR" "Failed to delete storage bucket '$BUCKET_NAME'"
        return 1
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local files_to_clean=(
        "${script_dir}/create_task.py"
        "${script_dir}/../function_code"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would clean up local files: ${files_to_clean[*]}"
        return 0
    fi
    
    for file_path in "${files_to_clean[@]}"; do
        if [[ -e "$file_path" ]]; then
            if [[ -f "$file_path" ]]; then
                rm -f "$file_path"
                log "INFO" "Removed file: $file_path"
            elif [[ -d "$file_path" ]]; then
                rm -rf "$file_path"
                log "INFO" "Removed directory: $file_path"
            fi
        else
            log "DEBUG" "File/directory does not exist: $file_path"
        fi
    done
}

# Function to verify cleanup completion
verify_cleanup() {
    log "INFO" "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check function
    if resource_exists "function" "$FUNCTION_NAME"; then
        log "ERROR" "Function '$FUNCTION_NAME' still exists"
        ((cleanup_errors++))
    else
        log "INFO" "✅ Function cleanup verified"
    fi
    
    # Check queue
    if resource_exists "queue" "$QUEUE_NAME"; then
        log "ERROR" "Queue '$QUEUE_NAME' still exists"
        ((cleanup_errors++))
    else
        log "INFO" "✅ Queue cleanup verified"
    fi
    
    # Check bucket
    if [[ -n "$BUCKET_NAME" ]] && resource_exists "bucket" "$BUCKET_NAME"; then
        log "ERROR" "Bucket '$BUCKET_NAME' still exists"
        ((cleanup_errors++))
    else
        log "INFO" "✅ Bucket cleanup verified"
    fi
    
    if [[ $cleanup_errors -gt 0 ]]; then
        log "ERROR" "Cleanup verification failed with $cleanup_errors errors"
        return 1
    else
        log "INFO" "✅ All resources successfully cleaned up"
        return 0
    fi
}

# Function to display cleanup summary
display_summary() {
    log "INFO" "Cleanup Summary:"
    log "INFO" "==============="
    log "INFO" "Project ID: $PROJECT_ID"
    log "INFO" "Region: $REGION"
    log "INFO" "Resources cleaned:"
    log "INFO" "  ✅ Cloud Function: $FUNCTION_NAME"
    log "INFO" "  ✅ Cloud Tasks Queue: $QUEUE_NAME"
    log "INFO" "  ✅ Storage Bucket: ${BUCKET_NAME:-[none]}"
    log "INFO" "Log File: $LOG_FILE"
    log "INFO" ""
    log "INFO" "Note: APIs remain enabled and can be disabled manually if no longer needed:"
    log "INFO" "  • cloudfunctions.googleapis.com"
    log "INFO" "  • cloudtasks.googleapis.com"
    log "INFO" "  • cloudbuild.googleapis.com"
    log "INFO" "  • storage.googleapis.com"
    log "INFO" "  • logging.googleapis.com"
}

# Function to handle cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Cleanup failed with exit code $exit_code"
        log "INFO" "Check the log file for details: $LOG_FILE"
        log "INFO" "Some resources may still exist and require manual cleanup"
    fi
    exit $exit_code
}

# Main cleanup function
main() {
    log "INFO" "Starting GCP Task Queue System cleanup..."
    log "INFO" "Log file: $LOG_FILE"
    
    # Set up signal handlers
    trap cleanup_on_exit EXIT
    trap 'log "ERROR" "Cleanup interrupted by user"; exit 130' INT TERM
    
    # Parse command line arguments
    parse_args "$@"
    
    # Validate prerequisites
    validate_prerequisites
    
    # Set project context
    gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
    
    # Discover bucket name if not provided
    discover_bucket_name
    
    # Confirm destruction if interactive
    confirm_destruction
    
    # Delete resources in reverse order of creation
    log "INFO" "Starting resource deletion..."
    
    # Delete Cloud Function first (to stop processing tasks)
    delete_function
    
    # Delete Cloud Tasks queue
    delete_queue
    
    # Delete storage bucket
    delete_bucket
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup completion
    verify_cleanup
    
    # Display summary
    display_summary
    
    log "INFO" "✅ GCP Task Queue System cleanup completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi