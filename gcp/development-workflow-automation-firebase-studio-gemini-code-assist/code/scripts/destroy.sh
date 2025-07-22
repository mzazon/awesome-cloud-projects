#!/bin/bash

# Development Workflow Automation with Firebase Studio and Gemini Code Assist - Cleanup Script
# This script removes all infrastructure created for AI-powered development workflow automation

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_LOG="${SCRIPT_DIR}/destroy.log"
CONFIG_FILE="${SCRIPT_DIR}/deployment-config.env"

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Remove AI-powered development workflow automation infrastructure.

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required if no config file)
    -r, --region REGION           Deployment region (default: ${DEFAULT_REGION})
    -z, --zone ZONE               Deployment zone (default: ${DEFAULT_ZONE})
    -f, --force                   Force cleanup without confirmation
    -c, --config CONFIG_FILE      Use specific deployment config file
    -k, --keep-project           Keep the Google Cloud project (don't delete it)
    -d, --dry-run                Show what would be destroyed without making changes
    -h, --help                   Show this help message

EXAMPLES:
    $0 --project-id my-ai-dev-project
    $0 -p my-project -f
    $0 --config ./custom-config.env
    $0 --project-id my-project --dry-run

EOF
}

# Parse command line arguments
FORCE=false
DRY_RUN=false
KEEP_PROJECT=false
PROJECT_ID=""
REGION="${DEFAULT_REGION}"
ZONE="${DEFAULT_ZONE}"
CUSTOM_CONFIG=""

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
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -c|--config)
            CUSTOM_CONFIG="$2"
            shift 2
            ;;
        -k|--keep-project)
            KEEP_PROJECT=true
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

# Load deployment configuration
load_deployment_config() {
    local config_to_load="${CUSTOM_CONFIG:-$CONFIG_FILE}"
    
    if [[ -f "${config_to_load}" ]]; then
        log_info "Loading deployment configuration from: ${config_to_load}"
        source "${config_to_load}"
        
        # Override with command line arguments if provided
        PROJECT_ID="${PROJECT_ID:-$PROJECT_ID}"
        REGION="${REGION:-$DEFAULT_REGION}"
        ZONE="${ZONE:-$DEFAULT_ZONE}"
        
        log_info "Configuration loaded:"
        log_info "  Project ID: ${PROJECT_ID}"
        log_info "  Region: ${REGION}"
        log_info "  Bucket: ${BUCKET_NAME:-not set}"
        log_info "  Function: ${FUNCTION_NAME:-not set}"
        log_info "  Topic: ${TOPIC_NAME:-not set}"
        log_info "  Trigger: ${TRIGGER_NAME:-not set}"
    else
        log_warning "Configuration file not found: ${config_to_load}"
        
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "Project ID is required when no configuration file is available."
            exit 1
        fi
        
        log_warning "Will attempt to discover resources in project: ${PROJECT_ID}"
    fi
}

# Validation functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if firebase is installed
    if ! command -v firebase &> /dev/null; then
        log_error "Firebase CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Validate project ID
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "Project ID is required. Use -p or --project-id option."
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project '${PROJECT_ID}' does not exist or you don't have access to it."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set up environment
setup_environment() {
    log_info "Setting up environment..."
    
    # Set project and region
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log_success "Environment configured for project: ${PROJECT_ID}"
}

# Discover resources if not loaded from config
discover_resources() {
    if [[ -n "${BUCKET_NAME:-}" && -n "${FUNCTION_NAME:-}" ]]; then
        log_info "Using resources from configuration file"
        return 0
    fi
    
    log_info "Discovering resources in project: ${PROJECT_ID}"
    
    # Discover Cloud Storage buckets
    local buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "dev-artifacts-" | head -1 || true)
    if [[ -n "${buckets}" ]]; then
        BUCKET_NAME=$(basename "${buckets%/}")
        log_info "Discovered bucket: ${BUCKET_NAME}"
    fi
    
    # Discover Cloud Functions
    local functions=$(gcloud functions list --filter="name~code-review-automation" --format="value(name)" --region="${REGION}" 2>/dev/null || true)
    if [[ -n "${functions}" ]]; then
        FUNCTION_NAME=$(basename "${functions}")
        log_info "Discovered function: ${FUNCTION_NAME}"
    fi
    
    # Discover Pub/Sub topics
    local topics=$(gcloud pubsub topics list --filter="name~code-events" --format="value(name)" 2>/dev/null || true)
    if [[ -n "${topics}" ]]; then
        TOPIC_NAME=$(basename "${topics}")
        log_info "Discovered topic: ${TOPIC_NAME}"
    fi
    
    # Discover Eventarc triggers
    local triggers=$(gcloud eventarc triggers list --location="${REGION}" --filter="name~code-review-trigger" --format="value(name)" 2>/dev/null || true)
    if [[ -n "${triggers}" ]]; then
        TRIGGER_NAME=$(basename "${triggers}")
        log_info "Discovered trigger: ${TRIGGER_NAME}"
    fi
}

# Remove Eventarc triggers
remove_eventarc_triggers() {
    log_info "Removing Eventarc triggers..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would remove Eventarc triggers"
        return 0
    fi
    
    # Remove specific trigger if known
    if [[ -n "${TRIGGER_NAME:-}" ]]; then
        log_info "Removing Eventarc trigger: ${TRIGGER_NAME}"
        if gcloud eventarc triggers delete "${TRIGGER_NAME}" \
            --location="${REGION}" \
            --quiet 2>/dev/null; then
            log_success "Removed Eventarc trigger: ${TRIGGER_NAME}"
        else
            log_warning "Failed to remove Eventarc trigger: ${TRIGGER_NAME}"
        fi
    fi
    
    # Remove any remaining code-review triggers
    local triggers=$(gcloud eventarc triggers list --location="${REGION}" --filter="name~code-review" --format="value(name)" 2>/dev/null || true)
    for trigger in ${triggers}; do
        local trigger_name=$(basename "${trigger}")
        log_info "Removing discovered trigger: ${trigger_name}"
        if gcloud eventarc triggers delete "${trigger_name}" \
            --location="${REGION}" \
            --quiet 2>/dev/null; then
            log_success "Removed trigger: ${trigger_name}"
        else
            log_warning "Failed to remove trigger: ${trigger_name}"
        fi
    done
}

# Remove Cloud Functions
remove_cloud_functions() {
    log_info "Removing Cloud Functions..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would remove Cloud Functions"
        return 0
    fi
    
    # Remove specific function if known
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log_info "Removing Cloud Function: ${FUNCTION_NAME}"
        if gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --quiet 2>/dev/null; then
            log_success "Removed Cloud Function: ${FUNCTION_NAME}"
        else
            log_warning "Failed to remove Cloud Function: ${FUNCTION_NAME}"
        fi
    fi
    
    # Remove any remaining code-review functions
    local functions=$(gcloud functions list --filter="name~code-review-automation" --format="value(name)" --region="${REGION}" 2>/dev/null || true)
    for function_path in ${functions}; do
        local function_name=$(basename "${function_path}")
        log_info "Removing discovered function: ${function_name}"
        if gcloud functions delete "${function_name}" \
            --region="${REGION}" \
            --quiet 2>/dev/null; then
            log_success "Removed function: ${function_name}"
        else
            log_warning "Failed to remove function: ${function_name}"
        fi
    done
}

# Remove Pub/Sub resources
remove_pubsub_resources() {
    log_info "Removing Pub/Sub resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would remove Pub/Sub resources"
        return 0
    fi
    
    # Remove specific resources if known
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        # Remove subscription first
        local subscription_name="${TOPIC_NAME}-sub"
        log_info "Removing Pub/Sub subscription: ${subscription_name}"
        if gcloud pubsub subscriptions delete "${subscription_name}" \
            --quiet 2>/dev/null; then
            log_success "Removed subscription: ${subscription_name}"
        else
            log_warning "Failed to remove subscription: ${subscription_name}"
        fi
        
        # Remove topic
        log_info "Removing Pub/Sub topic: ${TOPIC_NAME}"
        if gcloud pubsub topics delete "${TOPIC_NAME}" \
            --quiet 2>/dev/null; then
            log_success "Removed topic: ${TOPIC_NAME}"
        else
            log_warning "Failed to remove topic: ${TOPIC_NAME}"
        fi
    fi
    
    # Remove any remaining code-events resources
    local topics=$(gcloud pubsub topics list --filter="name~code-events" --format="value(name)" 2>/dev/null || true)
    for topic_path in ${topics}; do
        local topic_name=$(basename "${topic_path}")
        local subscription_name="${topic_name}-sub"
        
        # Remove subscription
        log_info "Removing discovered subscription: ${subscription_name}"
        gcloud pubsub subscriptions delete "${subscription_name}" --quiet 2>/dev/null || true
        
        # Remove topic
        log_info "Removing discovered topic: ${topic_name}"
        if gcloud pubsub topics delete "${topic_name}" --quiet 2>/dev/null; then
            log_success "Removed topic: ${topic_name}"
        else
            log_warning "Failed to remove topic: ${topic_name}"
        fi
    done
}

# Remove Cloud Storage buckets
remove_storage_buckets() {
    log_info "Removing Cloud Storage buckets..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would remove Cloud Storage buckets"
        return 0
    fi
    
    # Remove specific bucket if known
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log_info "Removing Storage bucket: gs://${BUCKET_NAME}"
        if gsutil -m rm -r "gs://${BUCKET_NAME}" 2>/dev/null; then
            log_success "Removed bucket: gs://${BUCKET_NAME}"
        else
            log_warning "Failed to remove bucket: gs://${BUCKET_NAME}"
        fi
    fi
    
    # Remove any remaining dev-artifacts buckets
    local buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "dev-artifacts-" || true)
    for bucket_path in ${buckets}; do
        local bucket_name=$(basename "${bucket_path%/}")
        log_info "Removing discovered bucket: gs://${bucket_name}"
        if gsutil -m rm -r "${bucket_path}" 2>/dev/null; then
            log_success "Removed bucket: gs://${bucket_name}"
        else
            log_warning "Failed to remove bucket: gs://${bucket_name}"
        fi
    done
}

# Remove Firebase project resources
remove_firebase_resources() {
    log_info "Removing Firebase project resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would remove Firebase resources"
        return 0
    fi
    
    # Note: We don't delete the Firebase project itself as it's the same as the GCP project
    # Just ensure Firebase is no longer actively used
    log_info "Firebase resources are part of the GCP project and will be removed with project deletion"
}

# Remove local workspace files
remove_local_files() {
    log_info "Removing local workspace files..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would remove local workspace files"
        return 0
    fi
    
    local workspace_dir="${SCRIPT_DIR}/../workspace"
    local functions_dir="${SCRIPT_DIR}/../functions"
    local monitoring_dir="${SCRIPT_DIR}/../monitoring"
    
    # Remove workspace directory
    if [[ -d "${workspace_dir}" ]]; then
        log_info "Removing workspace directory: ${workspace_dir}"
        if rm -rf "${workspace_dir}"; then
            log_success "Removed workspace directory"
        else
            log_warning "Failed to remove workspace directory"
        fi
    fi
    
    # Remove functions directory
    if [[ -d "${functions_dir}" ]]; then
        log_info "Removing functions directory: ${functions_dir}"
        if rm -rf "${functions_dir}"; then
            log_success "Removed functions directory"
        else
            log_warning "Failed to remove functions directory"
        fi
    fi
    
    # Remove monitoring directory
    if [[ -d "${monitoring_dir}" ]]; then
        log_info "Removing monitoring directory: ${monitoring_dir}"
        if rm -rf "${monitoring_dir}"; then
            log_success "Removed monitoring directory"
        else
            log_warning "Failed to remove monitoring directory"
        fi
    fi
    
    # Remove deployment config file
    if [[ -f "${CONFIG_FILE}" ]]; then
        log_info "Removing deployment config: ${CONFIG_FILE}"
        if rm -f "${CONFIG_FILE}"; then
            log_success "Removed deployment configuration"
        else
            log_warning "Failed to remove deployment configuration"
        fi
    fi
}

# Delete the entire project (optional)
delete_project() {
    if [[ "${KEEP_PROJECT}" == "true" ]]; then
        log_info "Keeping Google Cloud project as requested"
        return 0
    fi
    
    log_info "Preparing to delete Google Cloud project: ${PROJECT_ID}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would delete project: ${PROJECT_ID}"
        return 0
    fi
    
    # Final confirmation for project deletion
    if [[ "${FORCE}" != "true" ]]; then
        echo
        log_warning "⚠️  DANGER: This will permanently delete the entire project!"
        log_warning "   Project ID: ${PROJECT_ID}"
        log_warning "   This action cannot be undone!"
        echo
        read -p "Type 'DELETE' to confirm project deletion, or anything else to cancel: " -r
        if [[ "$REPLY" != "DELETE" ]]; then
            log_info "Project deletion cancelled"
            return 0
        fi
    fi
    
    log_info "Deleting Google Cloud project: ${PROJECT_ID}"
    if gcloud projects delete "${PROJECT_ID}" --quiet 2>/dev/null; then
        log_success "Project deletion initiated: ${PROJECT_ID}"
        log_info "Note: Project deletion may take several minutes to complete"
    else
        log_error "Failed to delete project: ${PROJECT_ID}"
        log_info "You may need to delete it manually from the Cloud Console"
    fi
}

# Verification function
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local remaining_resources=0
    
    # Check for remaining buckets
    local buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "dev-artifacts-" || true)
    if [[ -n "${buckets}" ]]; then
        log_warning "Found remaining buckets: ${buckets}"
        ((remaining_resources++))
    fi
    
    # Check for remaining functions
    local functions=$(gcloud functions list --filter="name~code-review-automation" --format="value(name)" --region="${REGION}" 2>/dev/null || true)
    if [[ -n "${functions}" ]]; then
        log_warning "Found remaining functions: ${functions}"
        ((remaining_resources++))
    fi
    
    # Check for remaining topics
    local topics=$(gcloud pubsub topics list --filter="name~code-events" --format="value(name)" 2>/dev/null || true)
    if [[ -n "${topics}" ]]; then
        log_warning "Found remaining topics: ${topics}"
        ((remaining_resources++))
    fi
    
    # Check for remaining triggers
    local triggers=$(gcloud eventarc triggers list --location="${REGION}" --filter="name~code-review" --format="value(name)" 2>/dev/null || true)
    if [[ -n "${triggers}" ]]; then
        log_warning "Found remaining triggers: ${triggers}"
        ((remaining_resources++))
    fi
    
    if [[ ${remaining_resources} -eq 0 ]]; then
        log_success "All resources successfully removed!"
        return 0
    else
        log_warning "Cleanup completed with ${remaining_resources} remaining resources"
        log_info "Some resources may need manual cleanup in the Cloud Console"
        return 1
    fi
}

# Confirmation prompt
confirm_cleanup() {
    if [[ "${FORCE}" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "⚠️  This will permanently delete the following resources:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log_info "  Storage Bucket: ${BUCKET_NAME}"
    fi
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log_info "  Cloud Function: ${FUNCTION_NAME}"
    fi
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        log_info "  Pub/Sub Topic: ${TOPIC_NAME}"
    fi
    if [[ -n "${TRIGGER_NAME:-}" ]]; then
        log_info "  Eventarc Trigger: ${TRIGGER_NAME}"
    fi
    if [[ "${KEEP_PROJECT}" != "true" ]]; then
        log_warning "  🔥 ENTIRE PROJECT will be deleted!"
    fi
    echo
    
    read -p "Do you want to proceed with cleanup? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Main cleanup function
main() {
    log_info "Starting AI Development Workflow Automation cleanup..."
    echo "Cleanup started at: $(date)" > "${CLEANUP_LOG}"
    
    # Run all cleanup steps
    load_deployment_config
    check_prerequisites
    setup_environment
    discover_resources
    confirm_cleanup
    
    # Remove resources in reverse order of creation
    remove_eventarc_triggers
    remove_cloud_functions
    remove_pubsub_resources
    remove_storage_buckets
    remove_firebase_resources
    remove_local_files
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        verify_cleanup
    fi
    
    # Optionally delete the entire project
    delete_project
    
    echo
    log_success "🧹 AI Development Workflow Automation cleanup completed!"
    
    if [[ "${KEEP_PROJECT}" == "true" ]]; then
        log_info "Google Cloud project preserved: ${PROJECT_ID}"
    elif [[ "${DRY_RUN}" == "false" ]]; then
        log_info "Project deletion initiated (if requested)"
    fi
    
    echo "Cleanup completed at: $(date)" >> "${CLEANUP_LOG}"
}

# Execute main function
main "$@"