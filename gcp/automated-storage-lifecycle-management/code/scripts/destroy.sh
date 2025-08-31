#!/bin/bash

# Destroy script for Automated Storage Lifecycle Management with Cloud Storage
# This script safely removes all resources created by the deploy script

set -euo pipefail

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

# Function to load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ -f ".deployment_state" ]]; then
        # Source the deployment state file
        source .deployment_state
        log_success "Loaded deployment state from .deployment_state"
        log_info "  PROJECT_ID: ${PROJECT_ID}"
        log_info "  REGION: ${REGION}"
        log_info "  BUCKET_NAME: ${BUCKET_NAME}"
        log_info "  JOB_NAME: ${JOB_NAME}"
    else
        log_warning "No .deployment_state file found. Using environment variables or defaults."
        
        # Use environment variables or set defaults
        export PROJECT_ID="${PROJECT_ID:-}"
        export REGION="${REGION:-us-central1}"
        export BUCKET_NAME="${BUCKET_NAME:-}"
        export JOB_NAME="${JOB_NAME:-}"
        
        if [[ -z "${PROJECT_ID}" ]] || [[ -z "${BUCKET_NAME}" ]] || [[ -z "${JOB_NAME}" ]]; then
            log_error "Missing required variables. Please set PROJECT_ID, BUCKET_NAME, and JOB_NAME environment variables."
            log_error "Or run this script from the same directory where deploy.sh was executed."
            exit 1
        fi
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | grep -q "."; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Set the project
    gcloud config set project "${PROJECT_ID}"
    
    log_success "Prerequisites check completed"
}

# Function to confirm destruction
confirm_destruction() {
    echo
    log_warning "=== RESOURCE DESTRUCTION WARNING ==="
    log_warning "This script will permanently delete the following resources:"
    log_warning "  • Storage Bucket: gs://${BUCKET_NAME} (and all contents)"
    log_warning "  • Logs Bucket: gs://${BUCKET_NAME}-logs (and all contents)"
    log_warning "  • Scheduler Job: ${JOB_NAME}"
    log_warning "  • Logging Sink: storage-lifecycle-sink"
    
    if [[ "${PROJECT_ID}" == *"lifecycle-demo-"* ]]; then
        log_warning "  • Project: ${PROJECT_ID} (demo project - will be deleted)"
    else
        log_info "  • Project: ${PROJECT_ID} (will NOT be deleted - not a demo project)"
    fi
    
    echo
    log_warning "THIS ACTION CANNOT BE UNDONE!"
    echo
    
    # Skip confirmation if FORCE_DESTROY is set
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        log_warning "FORCE_DESTROY is set, skipping confirmation..."
        return 0
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
    
    log_info "Confirmation received. Proceeding with resource destruction..."
}

# Function to remove Cloud Scheduler job
remove_scheduler_job() {
    log_info "Removing Cloud Scheduler job..."
    
    if gcloud scheduler jobs describe "${JOB_NAME}" --location="${REGION}" >/dev/null 2>&1; then
        if gcloud scheduler jobs delete "${JOB_NAME}" \
            --location="${REGION}" \
            --quiet; then
            log_success "Deleted scheduler job: ${JOB_NAME}"
        else
            log_error "Failed to delete scheduler job: ${JOB_NAME}"
            return 1
        fi
    else
        log_warning "Scheduler job ${JOB_NAME} not found, skipping deletion"
    fi
}

# Function to remove logging sink
remove_logging_sink() {
    log_info "Removing logging sink..."
    
    local sink_name="storage-lifecycle-sink"
    
    if gcloud logging sinks describe "${sink_name}" >/dev/null 2>&1; then
        if gcloud logging sinks delete "${sink_name}" --quiet; then
            log_success "Deleted logging sink: ${sink_name}"
        else
            log_error "Failed to delete logging sink: ${sink_name}"
            return 1
        fi
    else
        log_warning "Logging sink ${sink_name} not found, skipping deletion"
    fi
}

# Function to remove storage buckets
remove_storage_buckets() {
    log_info "Removing storage buckets and all contents..."
    
    local buckets=("gs://${BUCKET_NAME}" "gs://${BUCKET_NAME}-logs")
    
    for bucket in "${buckets[@]}"; do
        if gcloud storage buckets describe "${bucket}" >/dev/null 2>&1; then
            log_info "Removing all objects from ${bucket}..."
            
            # First, remove all objects (including versioned objects)
            if gcloud storage rm -r "${bucket}" --quiet; then
                log_success "Deleted storage bucket: ${bucket}"
            else
                log_error "Failed to delete storage bucket: ${bucket}"
                
                # Try alternative method for stubborn buckets
                log_info "Attempting alternative deletion method..."
                if gcloud storage rm "${bucket}/**" --recursive --quiet 2>/dev/null || true; then
                    if gcloud storage buckets delete "${bucket}" --quiet; then
                        log_success "Deleted storage bucket using alternative method: ${bucket}"
                    else
                        log_error "Failed to delete bucket even with alternative method: ${bucket}"
                    fi
                fi
            fi
        else
            log_warning "Storage bucket ${bucket} not found, skipping deletion"
        fi
    done
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    local files=(
        ".deployment_state"
        "lifecycle-config.json"
        "critical-data.txt"
        "monthly-report.txt"
        "archived-logs.txt"
        "backup-data.txt"
    )
    
    for file in "${files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_success "Removed local file: ${file}"
        fi
    done
}

# Function to disable APIs (optional)
disable_apis() {
    if [[ "${DISABLE_APIS:-false}" == "true" ]]; then
        log_info "Disabling APIs (DISABLE_APIS=true)..."
        
        local apis=(
            "cloudscheduler.googleapis.com"
            "cloudfunctions.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log_info "Disabling ${api}..."
            if gcloud services disable "${api}" --quiet; then
                log_success "Disabled ${api}"
            else
                log_warning "Failed to disable ${api} (may be in use by other resources)"
            fi
        done
        
        log_info "Note: storage.googleapis.com and logging.googleapis.com are not disabled as they may be used by other resources"
    else
        log_info "Skipping API disabling (set DISABLE_APIS=true to disable APIs)"
    fi
}

# Function to delete project (if it's a demo project)
delete_project() {
    # Only delete projects that match the demo pattern
    if [[ "${PROJECT_ID}" == *"lifecycle-demo-"* ]]; then
        log_info "Detected demo project. Initiating project deletion..."
        
        if [[ "${DELETE_PROJECT:-true}" == "true" ]]; then
            log_warning "Deleting entire project: ${PROJECT_ID}"
            log_warning "This will remove ALL resources in the project, not just those created by this recipe."
            
            # Additional confirmation for project deletion
            if [[ "${FORCE_DESTROY:-false}" != "true" ]]; then
                echo
                read -p "Are you sure you want to delete the entire project ${PROJECT_ID}? (type 'DELETE' to confirm): " project_confirmation
                
                if [[ "${project_confirmation}" != "DELETE" ]]; then
                    log_info "Project deletion cancelled. Resources within the project have been cleaned up."
                    return 0
                fi
            fi
            
            if gcloud projects delete "${PROJECT_ID}" --quiet; then
                log_success "Project deletion initiated: ${PROJECT_ID}"
                log_info "Note: Project deletion may take several minutes to complete"
            else
                log_error "Failed to delete project: ${PROJECT_ID}"
                return 1
            fi
        else
            log_info "Skipping project deletion (set DELETE_PROJECT=true to delete demo project)"
        fi
    else
        log_info "Project ${PROJECT_ID} is not a demo project, skipping deletion"
        log_info "Use DELETE_PROJECT=true if you want to force project deletion"
    fi
}

# Function to validate cleanup
validate_cleanup() {
    log_info "Validating resource cleanup..."
    
    local cleanup_errors=0
    
    # Check if buckets still exist
    for bucket in "gs://${BUCKET_NAME}" "gs://${BUCKET_NAME}-logs"; do
        if gcloud storage buckets describe "${bucket}" >/dev/null 2>&1; then
            log_error "✗ Storage bucket still exists: ${bucket}"
            ((cleanup_errors++))
        else
            log_success "✓ Storage bucket deleted: ${bucket}"
        fi
    done
    
    # Check if scheduler job still exists
    if gcloud scheduler jobs describe "${JOB_NAME}" --location="${REGION}" >/dev/null 2>&1; then
        log_error "✗ Scheduler job still exists: ${JOB_NAME}"
        ((cleanup_errors++))
    else
        log_success "✓ Scheduler job deleted: ${JOB_NAME}"
    fi
    
    # Check if logging sink still exists
    if gcloud logging sinks describe "storage-lifecycle-sink" >/dev/null 2>&1; then
        log_error "✗ Logging sink still exists: storage-lifecycle-sink"
        ((cleanup_errors++))
    else
        log_success "✓ Logging sink deleted: storage-lifecycle-sink"
    fi
    
    if [[ ${cleanup_errors} -eq 0 ]]; then
        log_success "All resources cleaned up successfully!"
    else
        log_error "Cleanup completed with ${cleanup_errors} errors. Some resources may need manual deletion."
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "=== Cleanup Summary ==="
    echo
    log_info "Resources Removed:"
    log_info "  • Storage Bucket: gs://${BUCKET_NAME}"
    log_info "  • Logs Bucket: gs://${BUCKET_NAME}-logs"
    log_info "  • Scheduler Job: ${JOB_NAME}"
    log_info "  • Logging Sink: storage-lifecycle-sink"
    
    if [[ "${PROJECT_ID}" == *"lifecycle-demo-"* ]] && [[ "${DELETE_PROJECT:-true}" == "true" ]]; then
        log_info "  • Project: ${PROJECT_ID} (deletion initiated)"
    fi
    
    echo
    log_info "Local Files Cleaned:"
    log_info "  • .deployment_state"
    log_info "  • Temporary configuration files"
    echo
    log_success "Automated Storage Lifecycle Management resources successfully destroyed!"
}

# Main cleanup function
main() {
    echo "=== Automated Storage Lifecycle Management Cleanup ==="
    echo
    
    # Run cleanup steps
    load_deployment_state
    check_prerequisites
    confirm_destruction
    
    log_info "Starting resource cleanup..."
    
    # Remove resources in reverse order of creation
    remove_scheduler_job
    remove_logging_sink
    remove_storage_buckets
    disable_apis
    delete_project
    cleanup_local_files
    
    # Validate and summarize
    if ! validate_cleanup; then
        log_warning "Some cleanup errors occurred. Please check the output above."
        exit 1
    fi
    
    display_cleanup_summary
    log_success "Cleanup completed successfully!"
}

# Handle script interruption
cleanup_on_error() {
    log_error "Cleanup interrupted. Some resources may not have been deleted."
    log_error "You may need to manually clean up remaining resources in the Google Cloud Console."
    exit 1
}

# Set trap for cleanup on script interruption
trap cleanup_on_error INT TERM

# Check for help flag
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [options]"
    echo
    echo "Environment Variables:"
    echo "  FORCE_DESTROY=true    Skip confirmation prompts"
    echo "  DELETE_PROJECT=false  Skip project deletion (for demo projects)"
    echo "  DISABLE_APIS=true     Disable APIs after cleanup"
    echo
    echo "Examples:"
    echo "  $0                           # Interactive cleanup"
    echo "  FORCE_DESTROY=true $0        # Skip confirmations"
    echo "  DELETE_PROJECT=false $0      # Keep demo project"
    echo "  DISABLE_APIS=true $0         # Also disable APIs"
    echo
    exit 0
fi

# Run main function
main "$@"