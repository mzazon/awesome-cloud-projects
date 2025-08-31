#!/bin/bash

# Age Calculator API with Cloud Run and Storage - Cleanup Script
# This script removes all resources created by the deploy.sh script
# Based on recipe: age-calculator-api-run-storage

set -euo pipefail

# Colors for output
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

# Function to prompt for confirmation
confirm_action() {
    local message="$1"
    local response
    
    echo -e "${YELLOW}[CONFIRM]${NC} ${message}"
    read -p "Are you sure? (yes/no): " response
    
    case "${response}" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            log_info "Operation cancelled by user"
            return 1
            ;;
    esac
}

# Load deployment information
load_deployment_info() {
    local info_file="deployment-info.txt"
    
    if [[ -f "${info_file}" ]]; then
        log_info "Loading deployment information from ${info_file}..."
        # shellcheck disable=SC1090
        source "${info_file}"
        
        log_info "Loaded deployment info:"
        log_info "  PROJECT_ID: ${PROJECT_ID:-not set}"
        log_info "  REGION: ${REGION:-not set}"
        log_info "  SERVICE_NAME: ${SERVICE_NAME:-not set}"
        log_info "  BUCKET_NAME: ${BUCKET_NAME:-not set}"
    else
        log_warning "Deployment info file not found. Will use environment variables or prompt for input."
    fi
}

# Get deployment parameters from user if not available
get_deployment_parameters() {
    log_info "Gathering deployment parameters..."
    
    # PROJECT_ID
    if [[ -z "${PROJECT_ID:-}" ]]; then
        echo -n "Enter PROJECT_ID: "
        read -r PROJECT_ID
        export PROJECT_ID
    fi
    
    # REGION
    if [[ -z "${REGION:-}" ]]; then
        REGION="us-central1"
        log_info "Using default REGION: ${REGION}"
        export REGION
    fi
    
    # SERVICE_NAME
    if [[ -z "${SERVICE_NAME:-}" ]]; then
        SERVICE_NAME="age-calculator-api"
        log_info "Using default SERVICE_NAME: ${SERVICE_NAME}"
        export SERVICE_NAME
    fi
    
    # BUCKET_NAME - try to find it if not provided
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_info "Searching for storage buckets with 'age-calc-logs' prefix..."
        local buckets
        buckets=$(gsutil ls -p "${PROJECT_ID}" | grep "age-calc-logs" || echo "")
        
        if [[ -n "${buckets}" ]]; then
            # Extract bucket name from first match
            BUCKET_NAME=$(echo "${buckets}" | head -n1 | sed 's|gs://||' | sed 's|/||')
            log_info "Found bucket: ${BUCKET_NAME}"
        else
            echo -n "Enter BUCKET_NAME (without gs:// prefix): "
            read -r BUCKET_NAME
        fi
        export BUCKET_NAME
    fi
    
    log_success "Deployment parameters gathered"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active Google Cloud authentication found"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    # Verify project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Project ${PROJECT_ID} does not exist or you don't have access"
        exit 1
    fi
    
    # Set project context
    gcloud config set project "${PROJECT_ID}"
    
    log_success "Prerequisites check completed"
}

# Delete Cloud Run service
delete_cloud_run_service() {
    log_info "Checking for Cloud Run service: ${SERVICE_NAME}"
    
    # Check if service exists
    if gcloud run services describe "${SERVICE_NAME}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        
        if confirm_action "Delete Cloud Run service '${SERVICE_NAME}' in region '${REGION}'?"; then
            log_info "Deleting Cloud Run service..."
            gcloud run services delete "${SERVICE_NAME}" \
                --region="${REGION}" \
                --project="${PROJECT_ID}" \
                --quiet
            
            log_success "Cloud Run service deleted"
        else
            log_warning "Skipping Cloud Run service deletion"
            return 1
        fi
    else
        log_warning "Cloud Run service '${SERVICE_NAME}' not found in region '${REGION}'"
    fi
}

# Delete Cloud Storage bucket
delete_storage_bucket() {
    log_info "Checking for Cloud Storage bucket: gs://${BUCKET_NAME}"
    
    # Check if bucket exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        # Get bucket size for confirmation
        local bucket_info
        bucket_info=$(gsutil du -sh "gs://${BUCKET_NAME}" 2>/dev/null || echo "Size unknown")
        
        if confirm_action "Delete Cloud Storage bucket 'gs://${BUCKET_NAME}' and ALL its contents? ${bucket_info}"; then
            log_info "Deleting all objects in bucket..."
            # Use -m for parallel processing and -r for recursive
            gsutil -m rm -r "gs://${BUCKET_NAME}" || {
                log_warning "Some objects may not have been deleted. Attempting to remove bucket..."
                gsutil rb "gs://${BUCKET_NAME}" 2>/dev/null || log_warning "Bucket deletion failed"
            }
            
            log_success "Storage bucket deleted"
        else
            log_warning "Skipping storage bucket deletion"
            return 1
        fi
    else
        log_warning "Storage bucket 'gs://${BUCKET_NAME}' not found"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "age-calculator-app"
        "deployment-info.txt"
        "lifecycle.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "${file}" ]]; then
            if confirm_action "Remove local file/directory '${file}'?"; then
                rm -rf "${file}"
                log_success "Removed ${file}"
            else
                log_warning "Skipping removal of ${file}"
            fi
        fi
    done
}

# Delete entire project (optional)
delete_project() {
    if confirm_action "DELETE THE ENTIRE PROJECT '${PROJECT_ID}' (This will remove ALL resources in the project)?"; then
        log_warning "This is a destructive operation that will delete the entire project!"
        log_warning "The project will be scheduled for deletion and cannot be recovered after 30 days."
        
        if confirm_action "Are you absolutely sure you want to delete project '${PROJECT_ID}'?"; then
            log_info "Deleting project '${PROJECT_ID}'..."
            gcloud projects delete "${PROJECT_ID}" --quiet
            
            log_success "Project deletion initiated"
            log_info "Note: Project deletion may take several minutes to complete"
            log_info "The project will be recoverable for 30 days from the deletion date"
        else
            log_info "Project deletion cancelled"
            return 1
        fi
    else
        log_info "Keeping project '${PROJECT_ID}'"
        return 1
    fi
}

# Display cleanup summary
display_cleanup_summary() {
    log_info ""
    log_info "=== Cleanup Summary ==="
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Service Name: ${SERVICE_NAME}"
    log_info "Bucket Name: ${BUCKET_NAME}"
    log_info ""
    
    # Check remaining resources
    log_info "Checking for remaining resources..."
    
    # Check Cloud Run services
    local run_services
    run_services=$(gcloud run services list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null | wc -l)
    log_info "Cloud Run services remaining: ${run_services}"
    
    # Check Storage buckets
    local storage_buckets
    storage_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | wc -l)
    log_info "Storage buckets remaining: ${storage_buckets}"
    
    if [[ "${run_services}" -eq 0 && "${storage_buckets}" -eq 0 ]]; then
        log_success "All resources have been cleaned up successfully!"
    else
        log_warning "Some resources may still exist. Check the Google Cloud Console for details."
    fi
}

# Main cleanup function
main() {
    log_info "Starting Age Calculator API cleanup..."
    
    # Handle script arguments
    local skip_confirmation=false
    local delete_project_flag=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --yes|-y)
                skip_confirmation=true
                shift
                ;;
            --delete-project)
                delete_project_flag=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --yes, -y           Skip confirmation prompts"
                echo "  --delete-project    Delete the entire project"
                echo "  --help, -h          Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Override confirmation function if --yes flag is used
    if [[ "${skip_confirmation}" == true ]]; then
        confirm_action() {
            log_info "Auto-confirming: $1"
            return 0
        }
    fi
    
    load_deployment_info
    get_deployment_parameters
    check_prerequisites
    
    log_warning "This script will delete cloud resources which may incur costs if not removed"
    
    # Individual resource cleanup
    local cleanup_success=true
    
    delete_cloud_run_service || cleanup_success=false
    delete_storage_bucket || cleanup_success=false
    cleanup_local_files || cleanup_success=false
    
    # Optional project deletion
    if [[ "${delete_project_flag}" == true ]]; then
        delete_project || cleanup_success=false
    else
        log_info "To delete the entire project, run: $0 --delete-project"
    fi
    
    display_cleanup_summary
    
    if [[ "${cleanup_success}" == true ]]; then
        log_success "Cleanup completed successfully!"
    else
        log_warning "Cleanup completed with some warnings or errors"
        log_info "Check the output above for details"
        exit 1
    fi
}

# Run main function
main "$@"