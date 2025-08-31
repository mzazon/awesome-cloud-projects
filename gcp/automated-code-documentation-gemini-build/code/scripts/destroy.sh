#!/bin/bash

# Automated Code Documentation with Gemini and Cloud Build - Cleanup Script
# This script safely removes all deployed infrastructure and resources

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/gemini-docs-destroy-$(date +%Y%m%d_%H%M%S).log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}" | tee -a "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" | tee -a "${LOG_FILE}" >&2
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $*${NC}" | tee -a "${LOG_FILE}"
    fi
}

# Usage information
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Safely remove all automated code documentation infrastructure.

Options:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           Deployment region (default: us-central1)
    -s, --suffix SUFFIX           Resource name suffix
    -f, --force                   Skip confirmation prompts
    -d, --debug                   Enable debug logging
    -h, --help                    Show this help message
    --dry-run                     Show what would be deleted without making changes
    --keep-storage               Keep storage bucket and contents (backup mode)
    --load-config                Load configuration from deployment config file

Environment Variables:
    GOOGLE_CLOUD_PROJECT         Google Cloud Project ID
    GOOGLE_CLOUD_REGION          Default region for resources
    DEBUG                        Enable debug mode (true/false)

Examples:
    ${SCRIPT_NAME} --project-id my-project
    ${SCRIPT_NAME} -p my-project -r us-west1 --force
    ${SCRIPT_NAME} --load-config --dry-run
    ${SCRIPT_NAME} --project-id my-project --keep-storage

EOF
}

# Default values
PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-}"
REGION="${GOOGLE_CLOUD_REGION:-us-central1}"
FORCE="false"
DRY_RUN="false"
KEEP_STORAGE="false"
LOAD_CONFIG="false"
SUFFIX=""

# Parse command line arguments
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
        -s|--suffix)
            SUFFIX="$2"
            shift 2
            ;;
        -f|--force)
            FORCE="true"
            shift
            ;;
        -d|--debug)
            DEBUG="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --keep-storage)
            KEEP_STORAGE="true"
            shift
            ;;
        --load-config)
            LOAD_CONFIG="true"
            shift
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Load configuration from deployment
load_deployment_config() {
    local config_file="${SCRIPT_DIR}/.deployment-config"
    
    if [[ "${LOAD_CONFIG}" == "true" ]]; then
        if [[ -f "${config_file}" ]]; then
            log "Loading deployment configuration from: ${config_file}"
            # shellcheck source=/dev/null
            source "${config_file}"
            log "Configuration loaded successfully"
        else
            error "Deployment configuration file not found: ${config_file}"
            error "Run deployment first or specify parameters manually"
            exit 1
        fi
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Validate project ID
    if [[ -z "${PROJECT_ID}" ]]; then
        error "Project ID is required. Use --project-id or set GOOGLE_CLOUD_PROJECT environment variable."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi
    
    # Check if project exists and user has access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        error "Cannot access project '${PROJECT_ID}'. Check project ID and permissions."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Initialize environment and determine resource names
initialize_environment() {
    log "Initializing cleanup environment..."
    
    # Set environment variables
    export PROJECT_ID
    export REGION
    
    # Set default project and region
    if [[ "${DRY_RUN}" == "false" ]]; then
        gcloud config set project "${PROJECT_ID}" --quiet
        gcloud config set compute/region "${REGION}" --quiet
    fi
    
    # If no suffix provided and not loading config, try to detect existing resources
    if [[ -z "${SUFFIX}" && "${LOAD_CONFIG}" == "false" ]]; then
        log "No suffix provided, attempting to detect existing resources..."
        
        # Try to find Cloud Functions with our naming pattern
        local functions
        functions=$(gcloud functions list --regions="${REGION}" --filter="name:doc-processor-*" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${functions}" ]]; then
            # Extract suffix from first function found
            local function_name
            function_name=$(echo "${functions}" | head -1)
            SUFFIX="${function_name##*-}"
            log "Detected suffix from existing resources: ${SUFFIX}"
        else
            error "No suffix provided and could not detect existing resources"
            error "Please specify suffix with --suffix or use --load-config"
            exit 1
        fi
    fi
    
    # Set resource names (either from config or computed)
    if [[ "${LOAD_CONFIG}" == "false" ]]; then
        export BUCKET_NAME="code-docs-${SUFFIX}"
        export FUNCTION_NAME="doc-processor-${SUFFIX}"
        export BUILD_TRIGGER_NAME="doc-automation-${SUFFIX}"
        export SERVICE_ACCOUNT_NAME="doc-automation-sa"
        export NOTIFICATION_FUNCTION_NAME="doc-notifier-${SUFFIX}"
    fi
    
    log "Cleanup environment initialized:"
    log "  Project ID: ${PROJECT_ID}"
    log "  Region: ${REGION}"
    log "  Suffix: ${SUFFIX}"
    log "  Bucket Name: ${BUCKET_NAME:-not set}"
    log "  Function Name: ${FUNCTION_NAME:-not set}"
    log "  Build Trigger Name: ${BUILD_TRIGGER_NAME:-not set}"
    log "  Service Account: ${SERVICE_ACCOUNT_NAME:-not set}"
    log "  Notification Function: ${NOTIFICATION_FUNCTION_NAME:-not set}"
}

# Confirm destruction with user
confirm_destruction() {
    if [[ "${FORCE}" == "true" ]]; then
        log "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "Dry run mode enabled, skipping confirmation"
        return 0
    fi
    
    echo ""
    warn "⚠️  WARNING: This will permanently delete the following resources:"
    echo "  - Cloud Functions: ${FUNCTION_NAME}, ${NOTIFICATION_FUNCTION_NAME}"
    echo "  - Cloud Build Trigger: ${BUILD_TRIGGER_NAME}-manual"
    if [[ "${KEEP_STORAGE}" == "false" ]]; then
        echo "  - Storage Bucket: gs://${BUCKET_NAME} (including all documentation)"
    fi
    echo "  - Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "  - Local files and configuration"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Type 'DELETE' to confirm permanent deletion: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log "Cleanup cancelled - confirmation text did not match"
        exit 0
    fi
    
    log "User confirmed destruction, proceeding with cleanup..."
}

# Remove Cloud Functions
remove_cloud_functions() {
    log "Removing Cloud Functions..."
    
    local functions_to_delete=(
        "${FUNCTION_NAME}"
        "${NOTIFICATION_FUNCTION_NAME}"
    )
    
    for function in "${functions_to_delete[@]}"; do
        if [[ "${DRY_RUN}" == "false" ]]; then
            if gcloud functions describe "${function}" --region="${REGION}" &> /dev/null; then
                log "Deleting function: ${function}"
                if gcloud functions delete "${function}" --region="${REGION}" --quiet; then
                    log "✅ Function ${function} deleted successfully"
                else
                    error "Failed to delete function: ${function}"
                fi
            else
                warn "Function ${function} not found, skipping"
            fi
        else
            log "DRY RUN: Would delete function ${function}"
        fi
    done
}

# Remove build triggers
remove_build_triggers() {
    log "Removing Cloud Build triggers..."
    
    local trigger_name="${BUILD_TRIGGER_NAME}-manual"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        if gcloud builds triggers describe "${trigger_name}" &> /dev/null; then
            log "Deleting build trigger: ${trigger_name}"
            if gcloud builds triggers delete "${trigger_name}" --quiet; then
                log "✅ Build trigger ${trigger_name} deleted successfully"
            else
                error "Failed to delete build trigger: ${trigger_name}"
            fi
        else
            warn "Build trigger ${trigger_name} not found, skipping"
        fi
    else
        log "DRY RUN: Would delete build trigger ${trigger_name}"
    fi
}

# Remove storage resources
remove_storage_resources() {
    if [[ "${KEEP_STORAGE}" == "true" ]]; then
        log "Keeping storage bucket as requested: gs://${BUCKET_NAME}"
        return 0
    fi
    
    log "Removing storage resources..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
            log "Deleting storage bucket and all contents: gs://${BUCKET_NAME}"
            
            # First try to remove versioned objects
            warn "Removing versioned objects (this may take a few minutes)..."
            gsutil -m rm -r "gs://${BUCKET_NAME}/**" || true
            
            # Remove the bucket itself
            if gsutil rb "gs://${BUCKET_NAME}"; then
                log "✅ Storage bucket gs://${BUCKET_NAME} deleted successfully"
            else
                error "Failed to delete storage bucket: gs://${BUCKET_NAME}"
            fi
        else
            warn "Storage bucket gs://${BUCKET_NAME} not found, skipping"
        fi
    else
        log "DRY RUN: Would delete storage bucket gs://${BUCKET_NAME}"
    fi
}

# Remove service account
remove_service_account() {
    log "Removing service account..."
    
    local service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        if gcloud iam service-accounts describe "${service_account_email}" &> /dev/null; then
            log "Deleting service account: ${service_account_email}"
            
            # Remove IAM policy bindings first
            local roles=(
                "roles/aiplatform.user"
                "roles/storage.objectAdmin"
                "roles/cloudfunctions.invoker"
            )
            
            for role in "${roles[@]}"; do
                debug "Removing role ${role} from service account..."
                gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                    --member="serviceAccount:${service_account_email}" \
                    --role="${role}" \
                    --quiet 2>/dev/null || true
            done
            
            # Delete the service account
            if gcloud iam service-accounts delete "${service_account_email}" --quiet; then
                log "✅ Service account ${service_account_email} deleted successfully"
            else
                error "Failed to delete service account: ${service_account_email}"
            fi
        else
            warn "Service account ${service_account_email} not found, skipping"
        fi
    else
        log "DRY RUN: Would delete service account ${service_account_email}"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_clean=(
        "${SCRIPT_DIR}/../functions"
        "${SCRIPT_DIR}/../build"
        "${SCRIPT_DIR}/../website"
        "${SCRIPT_DIR}/.deployment-config"
    )
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        for file_path in "${files_to_clean[@]}"; do
            if [[ -e "${file_path}" ]]; then
                log "Removing: ${file_path}"
                rm -rf "${file_path}"
            else
                debug "File not found, skipping: ${file_path}"
            fi
        done
        
        log "✅ Local files cleaned up successfully"
    else
        log "DRY RUN: Would remove local files: ${files_to_clean[*]}"
    fi
}

# Verify complete removal
verify_cleanup() {
    log "Verifying complete removal of resources..."
    
    local verification_failed=false
    
    # Check Cloud Functions
    if gcloud functions list --regions="${REGION}" --filter="name:${FUNCTION_NAME} OR name:${NOTIFICATION_FUNCTION_NAME}" --format="value(name)" | grep -q .; then
        error "Some Cloud Functions still exist"
        verification_failed=true
    fi
    
    # Check Build Triggers
    if gcloud builds triggers list --filter="name:${BUILD_TRIGGER_NAME}-manual" --format="value(name)" | grep -q .; then
        error "Build trigger still exists"
        verification_failed=true
    fi
    
    # Check Storage Bucket (only if not keeping it)
    if [[ "${KEEP_STORAGE}" == "false" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
            error "Storage bucket still exists"
            verification_failed=true
        fi
    fi
    
    # Check Service Account
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" &> /dev/null; then
        error "Service account still exists"
        verification_failed=true
    fi
    
    if [[ "${verification_failed}" == "true" ]]; then
        error "Some resources were not properly removed. Check the logs and try manual cleanup."
        return 1
    else
        log "✅ All resources successfully removed"
        return 0
    fi
}

# Display cost savings information
show_cost_savings() {
    log "💰 Cost Savings Information:"
    log "  The following resources have been removed, stopping associated charges:"
    log "  - Vertex AI API calls (Gemini model usage)"
    log "  - Cloud Functions execution time and requests"
    log "  - Cloud Build pipeline executions"
    if [[ "${KEEP_STORAGE}" == "false" ]]; then
        log "  - Cloud Storage bucket and data storage"
    else
        log "  - Cloud Storage bucket retained (continuing to incur charges)"
    fi
    log "  - Eventarc triggers"
    log ""
    log "  Estimated monthly savings: \$5-15 (depending on usage)"
}

# Generate cleanup report
generate_cleanup_report() {
    local report_file="${SCRIPT_DIR}/cleanup-report-$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "${report_file}" << EOF
# Automated Code Documentation Cleanup Report

Generated: $(date)
Project ID: ${PROJECT_ID}
Region: ${REGION}

## Resources Removed:
- Cloud Functions:
  - ${FUNCTION_NAME}
  - ${NOTIFICATION_FUNCTION_NAME}
- Cloud Build Trigger: ${BUILD_TRIGGER_NAME}-manual
- Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com
$(if [[ "${KEEP_STORAGE}" == "false" ]]; then
    echo "- Storage Bucket: gs://${BUCKET_NAME}"
else
    echo "- Storage Bucket: gs://${BUCKET_NAME} (RETAINED)"
fi)

## Cleanup Status:
$(if verify_cleanup &>/dev/null; then
    echo "✅ All resources successfully removed"
else
    echo "⚠️  Some resources may still exist - manual verification required"
fi)

## Cost Impact:
- Estimated monthly savings: \$5-15
- All AI processing charges stopped
- Build pipeline charges stopped
$(if [[ "${KEEP_STORAGE}" == "false" ]]; then
    echo "- Storage charges stopped"
else
    echo "- Storage charges continue (bucket retained)"
fi)

## Log Files:
- Cleanup log: ${LOG_FILE}
- Cleanup report: ${report_file}
EOF
    
    log "Cleanup report generated: ${report_file}"
}

# Main cleanup function
main() {
    log "Starting cleanup of Automated Code Documentation infrastructure"
    log "Log file: ${LOG_FILE}"
    
    load_deployment_config
    check_prerequisites
    initialize_environment
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN MODE - No actual resources will be deleted"
    fi
    
    confirm_destruction
    
    log "Beginning resource cleanup..."
    
    remove_cloud_functions
    remove_build_triggers
    remove_storage_resources
    remove_service_account
    cleanup_local_files
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        if verify_cleanup; then
            log "🎉 Cleanup completed successfully!"
            show_cost_savings
            generate_cleanup_report
        else
            error "Cleanup completed with some issues. Check the verification results above."
            exit 1
        fi
    else
        log "DRY RUN completed - no actual changes made"
    fi
    
    log ""
    log "📋 Cleanup Summary:"
    log "  Project ID: ${PROJECT_ID}"
    log "  Region: ${REGION}"
    log "  Resources removed: Cloud Functions, Build Triggers, Service Account"
    if [[ "${KEEP_STORAGE}" == "false" ]]; then
        log "  Storage: Bucket and all contents deleted"
    else
        log "  Storage: Bucket retained with all documentation"
    fi
    log ""
    log "🔒 Security: All service accounts and IAM bindings removed"
    log "💰 Cost: All associated charges stopped"
    log ""
    log "Log file saved: ${LOG_FILE}"
}

# Run main function
main "$@"