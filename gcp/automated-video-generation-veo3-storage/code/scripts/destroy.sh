#!/bin/bash

# Automated Video Generation with Veo 3 and Storage - Cleanup Script
# This script removes all resources created by the deployment script
# Version: 1.0
# Last Updated: 2025-07-12

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CLEANUP_LOG="${SCRIPT_DIR}/cleanup.log"
readonly RESOURCE_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC}  ${message}" | tee -a "$CLEANUP_LOG" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC}  ${message}" | tee -a "$CLEANUP_LOG" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "$CLEANUP_LOG" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} ${message}" | tee -a "$CLEANUP_LOG" ;;
    esac
}

# Error handler
error_exit() {
    local line_number="$1"
    local error_code="$2"
    log "ERROR" "Script failed at line ${line_number} with exit code ${error_code}"
    log "ERROR" "Check cleanup log: ${CLEANUP_LOG}"
    exit "${error_code}"
}

trap 'error_exit ${LINENO} $?' ERR

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Remove all resources created by the Automated Video Generation deployment.

OPTIONS:
    -p, --project PROJECT_ID    GCP Project ID (required if not using state file)
    -r, --region REGION         GCP region (default: from state file or us-central1)
    -s, --state-file FILE       Path to deployment state file (default: .deployment_state)
    -f, --force                 Skip confirmation prompts
    -q, --quiet                 Suppress non-critical output
    -d, --dry-run               Show what would be deleted without actually deleting
    -k, --keep-buckets          Keep storage buckets and their contents
    -v, --verbose               Enable verbose logging
    -h, --help                  Show this help message

EXAMPLES:
    $0                                    # Use state file for resource info
    $0 --project my-video-project --force # Force cleanup for specific project
    $0 --dry-run --verbose               # See what would be deleted
    $0 --keep-buckets                    # Delete everything except storage

SAFETY FEATURES:
    - Confirmation prompts before destructive actions
    - Dry-run mode to preview deletions
    - Option to preserve storage buckets
    - Detailed logging of all operations
    - Graceful handling of missing resources

WARNING:
    This script will permanently delete:
    - Cloud Functions and their source code
    - Cloud Scheduler jobs
    - Storage buckets and ALL their contents (unless --keep-buckets is used)
    - Service accounts and IAM bindings
    - Monitoring resources
    
    This action cannot be undone!

EOF
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
            -s|--state-file)
                RESOURCE_STATE_FILE="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_CLEANUP=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -k|--keep-buckets)
                KEEP_BUCKETS=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
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

# Initialize default values
PROJECT_ID=""
REGION="us-central1"
FORCE_CLEANUP=false
QUIET=false
DRY_RUN=false
KEEP_BUCKETS=false
VERBOSE=false

# Load deployment state
load_deployment_state() {
    log "INFO" "Loading deployment state..."
    
    if [[ ! -f "$RESOURCE_STATE_FILE" ]]; then
        if [[ -z "$PROJECT_ID" ]]; then
            log "ERROR" "No state file found and no project ID provided"
            log "INFO" "Use --project option or ensure deployment state file exists"
            exit 1
        fi
        
        log "WARN" "No state file found, will attempt cleanup using provided project ID"
        return 0
    fi
    
    # Source the state file to load variables
    source "$RESOURCE_STATE_FILE"
    
    # Validate required variables
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log "ERROR" "Invalid state file: PROJECT_ID not found"
        exit 1
    fi
    
    log "INFO" "Loaded deployment state from: $RESOURCE_STATE_FILE"
    [[ "$VERBOSE" == "true" ]] && log "DEBUG" "Project: $PROJECT_ID, Region: ${REGION:-us-central1}"
}

# Validate prerequisites
validate_prerequisites() {
    log "INFO" "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log "ERROR" "Google Cloud CLI is not installed"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 > /dev/null; then
        log "ERROR" "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log "ERROR" "Project '$PROJECT_ID' does not exist or is not accessible"
        exit 1
    fi
    
    # Set default project
    gcloud config set project "$PROJECT_ID" --quiet
    
    log "INFO" "Prerequisites validation completed"
}

# Confirm deletion with user
confirm_deletion() {
    if [[ "$FORCE_CLEANUP" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    echo -e "${RED}⚠️  WARNING: DESTRUCTIVE OPERATION${NC}"
    echo "==============================================="
    echo "This will permanently delete the following resources:"
    echo "• Project: $PROJECT_ID"
    echo "• Region: ${REGION:-us-central1}"
    
    if [[ -n "${INPUT_BUCKET:-}" ]]; then
        echo "• Input Bucket: gs://${INPUT_BUCKET} (and all contents)"
    fi
    
    if [[ -n "${OUTPUT_BUCKET:-}" ]]; then
        echo "• Output Bucket: gs://${OUTPUT_BUCKET} (and all contents)"
    fi
    
    if [[ -n "${VIDEO_FUNCTION_NAME:-}" ]]; then
        echo "• Video Generation Function: ${VIDEO_FUNCTION_NAME}"
    fi
    
    if [[ -n "${ORCHESTRATOR_FUNCTION_NAME:-}" ]]; then
        echo "• Orchestrator Function: ${ORCHESTRATOR_FUNCTION_NAME}"
    fi
    
    if [[ -n "${SERVICE_ACCOUNT:-}" ]]; then
        echo "• Service Account: ${SERVICE_ACCOUNT}"
    fi
    
    echo "• All scheduler jobs, monitoring resources, and IAM bindings"
    echo
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    echo
    
    read -p "Are you absolutely sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "INFO" "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    log "INFO" "User confirmed deletion, proceeding with cleanup..."
}

# Delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log "INFO" "Deleting Cloud Scheduler jobs..."
    
    local jobs_to_delete=()
    
    # Add jobs from state file if available
    if [[ -n "${SCHEDULED_JOB_NAME:-}" ]]; then
        jobs_to_delete+=("$SCHEDULED_JOB_NAME")
    fi
    
    if [[ -n "${ONDEMAND_JOB_NAME:-}" ]]; then
        jobs_to_delete+=("$ONDEMAND_JOB_NAME")
    fi
    
    # If no jobs in state file, try to find jobs by pattern
    if [[ ${#jobs_to_delete[@]} -eq 0 ]]; then
        log "INFO" "No scheduler jobs in state file, searching for video generation jobs..."
        
        while IFS= read -r job_name; do
            if [[ "$job_name" =~ (automated-video-generation|on-demand-video-generation) ]]; then
                jobs_to_delete+=("$job_name")
            fi
        done < <(gcloud scheduler jobs list --location="${REGION:-us-central1}" --format="value(name)" 2>/dev/null | grep -E "(automated-video-generation|on-demand-video-generation)" || true)
    fi
    
    if [[ ${#jobs_to_delete[@]} -eq 0 ]]; then
        log "INFO" "No scheduler jobs found to delete"
        return 0
    fi
    
    for job_name in "${jobs_to_delete[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would delete scheduler job: $job_name"
            continue
        fi
        
        log "INFO" "Deleting scheduler job: $job_name"
        if gcloud scheduler jobs delete "$job_name" \
            --location="${REGION:-us-central1}" \
            --quiet &>/dev/null; then
            log "INFO" "✅ Deleted scheduler job: $job_name"
        else
            log "WARN" "Failed to delete scheduler job: $job_name (may not exist)"
        fi
    done
}

# Delete Cloud Functions
delete_cloud_functions() {
    log "INFO" "Deleting Cloud Functions..."
    
    local functions_to_delete=()
    
    # Add functions from state file if available
    if [[ -n "${VIDEO_FUNCTION_NAME:-}" ]]; then
        functions_to_delete+=("$VIDEO_FUNCTION_NAME")
    fi
    
    if [[ -n "${ORCHESTRATOR_FUNCTION_NAME:-}" ]]; then
        functions_to_delete+=("$ORCHESTRATOR_FUNCTION_NAME")
    fi
    
    # If no functions in state file, try to find functions by pattern
    if [[ ${#functions_to_delete[@]} -eq 0 ]]; then
        log "INFO" "No functions in state file, searching for video generation functions..."
        
        while IFS= read -r function_name; do
            if [[ "$function_name" =~ (video-generation|video-orchestrator) ]]; then
                functions_to_delete+=("$function_name")
            fi
        done < <(gcloud functions list --regions="${REGION:-us-central1}" --gen2 --format="value(name)" 2>/dev/null | grep -E "(video-generation|video-orchestrator)" || true)
    fi
    
    if [[ ${#functions_to_delete[@]} -eq 0 ]]; then
        log "INFO" "No Cloud Functions found to delete"
        return 0
    fi
    
    for function_name in "${functions_to_delete[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would delete function: $function_name"
            continue
        fi
        
        log "INFO" "Deleting Cloud Function: $function_name"
        if gcloud functions delete "$function_name" \
            --region="${REGION:-us-central1}" \
            --gen2 \
            --quiet &>/dev/null; then
            log "INFO" "✅ Deleted Cloud Function: $function_name"
        else
            log "WARN" "Failed to delete function: $function_name (may not exist)"
        fi
    done
}

# Delete storage buckets and contents
delete_storage_buckets() {
    if [[ "$KEEP_BUCKETS" == "true" ]]; then
        log "INFO" "Skipping storage bucket deletion (--keep-buckets specified)"
        return 0
    fi
    
    log "INFO" "Deleting storage buckets and contents..."
    
    local buckets_to_delete=()
    
    # Add buckets from state file if available
    if [[ -n "${INPUT_BUCKET:-}" ]]; then
        buckets_to_delete+=("$INPUT_BUCKET")
    fi
    
    if [[ -n "${OUTPUT_BUCKET:-}" ]]; then
        buckets_to_delete+=("$OUTPUT_BUCKET")
    fi
    
    # If no buckets in state file, try to find buckets by pattern
    if [[ ${#buckets_to_delete[@]} -eq 0 ]]; then
        log "INFO" "No buckets in state file, searching for video generation buckets..."
        
        while IFS= read -r bucket_name; do
            if [[ "$bucket_name" =~ (video-briefs|generated-videos) ]]; then
                buckets_to_delete+=("$bucket_name")
            fi
        done < <(gsutil ls -p "$PROJECT_ID" 2>/dev/null | sed 's|gs://||' | sed 's|/||' | grep -E "(video-briefs|generated-videos)" || true)
    fi
    
    if [[ ${#buckets_to_delete[@]} -eq 0 ]]; then
        log "INFO" "No storage buckets found to delete"
        return 0
    fi
    
    for bucket_name in "${buckets_to_delete[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would delete bucket and contents: gs://$bucket_name"
            continue
        fi
        
        log "INFO" "Deleting bucket and all contents: gs://$bucket_name"
        
        # Check if bucket exists
        if ! gsutil ls "gs://$bucket_name" &>/dev/null; then
            log "WARN" "Bucket does not exist: gs://$bucket_name"
            continue
        fi
        
        # Delete all objects and versions in the bucket
        if gsutil -m rm -r "gs://$bucket_name" &>/dev/null; then
            log "INFO" "✅ Deleted bucket and contents: gs://$bucket_name"
        else
            log "WARN" "Failed to delete bucket: gs://$bucket_name"
        fi
    done
}

# Delete service account and IAM bindings
delete_service_account() {
    log "INFO" "Deleting service account and IAM bindings..."
    
    local service_accounts_to_delete=()
    
    # Add service account from state file if available
    if [[ -n "${SERVICE_ACCOUNT:-}" ]]; then
        service_accounts_to_delete+=("$SERVICE_ACCOUNT")
    fi
    
    # If no service account in state file, try to find by pattern
    if [[ ${#service_accounts_to_delete[@]} -eq 0 ]]; then
        log "INFO" "No service account in state file, searching for video generation service accounts..."
        
        while IFS= read -r sa_email; do
            local sa_name
            sa_name=$(echo "$sa_email" | cut -d'@' -f1)
            if [[ "$sa_name" =~ video-gen-sa ]]; then
                service_accounts_to_delete+=("$sa_name")
            fi
        done < <(gcloud iam service-accounts list --format="value(email)" 2>/dev/null | grep -E "video-gen-sa" || true)
    fi
    
    if [[ ${#service_accounts_to_delete[@]} -eq 0 ]]; then
        log "INFO" "No service accounts found to delete"
        return 0
    fi
    
    for service_account in "${service_accounts_to_delete[@]}"; do
        local sa_email="${service_account}@${PROJECT_ID}.iam.gserviceaccount.com"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY RUN] Would delete service account: $sa_email"
            log "INFO" "[DRY RUN] Would remove IAM bindings for: $sa_email"
            continue
        fi
        
        # Remove IAM policy bindings
        local roles=(
            "roles/aiplatform.user"
            "roles/storage.admin"
            "roles/logging.logWriter"
            "roles/monitoring.metricWriter"
        )
        
        for role in "${roles[@]}"; do
            log "INFO" "Removing IAM binding: $role for $sa_email"
            if gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$sa_email" \
                --role="$role" \
                --quiet &>/dev/null; then
                [[ "$VERBOSE" == "true" ]] && log "DEBUG" "✅ Removed IAM binding: $role"
            else
                [[ "$VERBOSE" == "true" ]] && log "DEBUG" "IAM binding not found or already removed: $role"
            fi
        done
        
        # Delete service account
        log "INFO" "Deleting service account: $sa_email"
        if gcloud iam service-accounts delete "$sa_email" \
            --quiet &>/dev/null; then
            log "INFO" "✅ Deleted service account: $sa_email"
        else
            log "WARN" "Failed to delete service account: $sa_email (may not exist)"
        fi
    done
}

# Delete monitoring and alerting resources
delete_monitoring_resources() {
    log "INFO" "Deleting monitoring and alerting resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete monitoring policies and notification channels"
        return 0
    fi
    
    # Delete alert policies related to video generation
    local policies_deleted=0
    while IFS= read -r policy_name; do
        if [[ "$policy_name" =~ (Video.*Generation|video.*generation) ]]; then
            log "INFO" "Deleting alert policy: $policy_name"
            if gcloud alpha monitoring policies delete "$policy_name" --quiet &>/dev/null; then
                ((policies_deleted++))
                [[ "$VERBOSE" == "true" ]] && log "DEBUG" "✅ Deleted alert policy: $policy_name"
            else
                [[ "$VERBOSE" == "true" ]] && log "DEBUG" "Failed to delete alert policy: $policy_name"
            fi
        fi
    done < <(gcloud alpha monitoring policies list --format="value(name)" 2>/dev/null || true)
    
    # Delete notification channels related to video generation
    local channels_deleted=0
    while IFS= read -r channel_name; do
        if [[ "$channel_name" =~ (Video.*Generation|video.*generation) ]]; then
            log "INFO" "Deleting notification channel: $channel_name"
            if gcloud alpha monitoring channels delete "$channel_name" --quiet &>/dev/null; then
                ((channels_deleted++))
                [[ "$VERBOSE" == "true" ]] && log "DEBUG" "✅ Deleted notification channel: $channel_name"
            else
                [[ "$VERBOSE" == "true" ]] && log "DEBUG" "Failed to delete notification channel: $channel_name"
            fi
        fi
    done < <(gcloud alpha monitoring channels list --format="value(name)" 2>/dev/null || true)
    
    if [[ $policies_deleted -gt 0 || $channels_deleted -gt 0 ]]; then
        log "INFO" "✅ Deleted $policies_deleted alert policies and $channels_deleted notification channels"
    else
        log "INFO" "No monitoring resources found to delete"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    local files_to_remove=(
        "$RESOURCE_STATE_FILE"
        "${SCRIPT_DIR}/sample_brief.json"
        "${SCRIPT_DIR}/lifestyle_brief.json"
        "${SCRIPT_DIR}/alert_policy.yaml"
    )
    
    local files_removed=0
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log "INFO" "[DRY RUN] Would remove file: $file"
            else
                rm -f "$file"
                ((files_removed++))
                [[ "$VERBOSE" == "true" ]] && log "DEBUG" "✅ Removed file: $file"
            fi
        fi
    done
    
    # Clean up any temporary directories created by functions
    local temp_dirs=(
        "${SCRIPT_DIR}/video-generation-function"
        "${SCRIPT_DIR}/orchestrator-function"
    )
    
    for dir in "${temp_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log "INFO" "[DRY RUN] Would remove directory: $dir"
            else
                rm -rf "$dir"
                ((files_removed++))
                [[ "$VERBOSE" == "true" ]] && log "DEBUG" "✅ Removed directory: $dir"
            fi
        fi
    done
    
    if [[ $files_removed -gt 0 ]]; then
        log "INFO" "✅ Cleaned up $files_removed local files and directories"
    else
        log "INFO" "No local files found to clean up"
    fi
}

# Display cleanup summary
display_summary() {
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "$DRY_RUN" == "true" ]]; then
        cat << EOF

${BLUE}================================================================================
🔍 DRY RUN COMPLETED
================================================================================${NC}

This was a dry run. No resources were actually deleted.
Review the output above to see what would be removed.

To perform the actual cleanup, run this script without the --dry-run flag.

EOF
        return 0
    fi
    
    cat << EOF

${GREEN}================================================================================
✅ CLEANUP COMPLETED SUCCESSFULLY
================================================================================${NC}

📋 CLEANUP SUMMARY:
   Project ID:       ${PROJECT_ID}
   Region:           ${REGION:-us-central1}
   Completion Time:  ${end_time}
   
🗑️  RESOURCES REMOVED:
   ✅ Cloud Scheduler jobs
   ✅ Cloud Functions
EOF

    if [[ "$KEEP_BUCKETS" == "false" ]]; then
        echo "   ✅ Storage buckets and contents"
    else
        echo "   ⏭️  Storage buckets (preserved)"
    fi
    
    cat << EOF
   ✅ Service accounts and IAM bindings
   ✅ Monitoring and alerting resources
   ✅ Local files and state

💡 CLEANUP VERIFICATION:
   Run these commands to verify removal:
   • gcloud functions list --regions=${REGION:-us-central1} --gen2
   • gcloud scheduler jobs list --location=${REGION:-us-central1}
   • gsutil ls -p ${PROJECT_ID}
   • gcloud iam service-accounts list

📄 CLEANUP LOG: ${CLEANUP_LOG}

EOF

    if [[ "$KEEP_BUCKETS" == "true" ]]; then
        cat << EOF
${YELLOW}⚠️  STORAGE BUCKETS PRESERVED${NC}
The following buckets were not deleted (--keep-buckets specified):
EOF
        if [[ -n "${INPUT_BUCKET:-}" ]]; then
            echo "   • gs://${INPUT_BUCKET}"
        fi
        if [[ -n "${OUTPUT_BUCKET:-}" ]]; then
            echo "   • gs://${OUTPUT_BUCKET}"
        fi
        echo "   To delete them later: gsutil -m rm -r gs://bucket-name"
        echo
    fi
}

# Main cleanup function
main() {
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log "INFO" "Starting Automated Video Generation cleanup at ${start_time}"
    log "INFO" "Script version: 1.0"
    log "INFO" "Cleanup log: ${CLEANUP_LOG}"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Load deployment state
    load_deployment_state
    
    # Validate prerequisites
    validate_prerequisites
    
    # Confirm deletion with user
    confirm_deletion
    
    # Perform cleanup in reverse order of creation
    delete_scheduler_jobs
    delete_cloud_functions
    delete_storage_buckets
    delete_service_account
    delete_monitoring_resources
    cleanup_local_files
    
    # Display summary
    display_summary
    
    log "INFO" "Cleanup completed successfully"
}

# Run main function
main "$@"

exit 0