#!/bin/bash

# Multi-Tenant Resource Scheduling Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
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

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it first."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install it first."
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "gcloud is not authenticated. Please run 'gcloud auth login' first."
    fi
    
    # Check if project is set
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "${PROJECT_ID}" ]]; then
        error_exit "No GCP project is set. Please run 'gcloud config set project PROJECT_ID' first."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load deployment info
load_deployment_info() {
    local info_file="deployment-info.json"
    
    if [[ -f "${info_file}" ]]; then
        log_info "Loading deployment information from ${info_file}..."
        
        export PROJECT_ID=$(jq -r '.project_id' "${info_file}")
        export REGION=$(jq -r '.region' "${info_file}")
        export ZONE=$(jq -r '.zone' "${info_file}")
        export RESOURCE_SUFFIX=$(jq -r '.resource_suffix' "${info_file}")
        export FILESTORE_NAME=$(jq -r '.filestore_name' "${info_file}")
        export FUNCTION_NAME=$(jq -r '.function_name' "${info_file}")
        
        # Load scheduler jobs
        local jobs_json=$(jq -r '.scheduler_jobs[]' "${info_file}")
        SCHEDULER_JOBS=()
        while IFS= read -r job; do
            SCHEDULER_JOBS+=("$job")
        done <<< "$jobs_json"
        
        log_success "Deployment info loaded successfully"
        log_info "Project ID: ${PROJECT_ID}"
        log_info "Region: ${REGION}"
        log_info "Zone: ${ZONE}"
        log_info "Resource suffix: ${RESOURCE_SUFFIX}"
    else
        log_warning "Deployment info file not found. Will attempt manual discovery..."
        prompt_for_resources
    fi
}

# Function to prompt for resource information if deployment info is missing
prompt_for_resources() {
    log_info "Manual resource discovery mode..."
    
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Prompt for resource suffix
    echo -n "Enter resource suffix (e.g., mt-abc123): "
    read -r RESOURCE_SUFFIX
    
    if [[ -z "${RESOURCE_SUFFIX}" ]]; then
        error_exit "Resource suffix is required for cleanup"
    fi
    
    export FILESTORE_NAME="tenant-data-${RESOURCE_SUFFIX}"
    export FUNCTION_NAME="resource-scheduler-${RESOURCE_SUFFIX}"
    
    # Scheduler job names
    SCHEDULER_JOBS=(
        "tenant-cleanup-${RESOURCE_SUFFIX}"
        "quota-monitor-${RESOURCE_SUFFIX}"
        "tenant-a-processing-${RESOURCE_SUFFIX}"
    )
    
    log_success "Manual resource configuration completed"
}

# Function to confirm deletion
confirm_deletion() {
    log_warning "This will permanently delete the following resources:"
    echo "  - Cloud Filestore instance: ${FILESTORE_NAME}"
    echo "  - Cloud Function: ${FUNCTION_NAME}"
    echo "  - Cloud Scheduler jobs: ${SCHEDULER_JOBS[*]}"
    echo "  - Cloud Monitoring alert policies and dashboards"
    echo "  - Temporary files and directories"
    echo
    
    while true; do
        read -p "Are you sure you want to proceed? (yes/no): " yn
        case $yn in
            [Yy]es ) log_info "Proceeding with resource deletion..."; break;;
            [Nn]o ) log_info "Deletion cancelled."; exit 0;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log_info "Deleting Cloud Scheduler jobs..."
    
    local deleted_count=0
    for job in "${SCHEDULER_JOBS[@]}"; do
        log_info "Deleting scheduler job: ${job}..."
        
        if gcloud scheduler jobs describe "${job}" &>/dev/null; then
            if gcloud scheduler jobs delete "${job}" --quiet; then
                log_success "Deleted scheduler job: ${job}"
                ((deleted_count++))
            else
                log_error "Failed to delete scheduler job: ${job}"
            fi
        else
            log_warning "Scheduler job not found: ${job}"
        fi
    done
    
    log_success "Deleted ${deleted_count} scheduler jobs"
}

# Function to delete Cloud Function
delete_function() {
    log_info "Deleting Cloud Function: ${FUNCTION_NAME}..."
    
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        if gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet; then
            log_success "Deleted Cloud Function: ${FUNCTION_NAME}"
        else
            log_error "Failed to delete Cloud Function: ${FUNCTION_NAME}"
        fi
    else
        log_warning "Cloud Function not found: ${FUNCTION_NAME}"
    fi
}

# Function to delete Cloud Filestore instance
delete_filestore() {
    log_info "Deleting Cloud Filestore instance: ${FILESTORE_NAME}..."
    
    if gcloud filestore instances describe "${FILESTORE_NAME}" --zone="${ZONE}" &>/dev/null; then
        log_info "Filestore instance found. Initiating deletion..."
        
        # Filestore deletion can take several minutes
        if gcloud filestore instances delete "${FILESTORE_NAME}" --zone="${ZONE}" --quiet; then
            log_success "Filestore deletion initiated successfully"
            log_info "Note: Filestore deletion may take several minutes to complete"
        else
            log_error "Failed to delete Filestore instance: ${FILESTORE_NAME}"
        fi
    else
        log_warning "Filestore instance not found: ${FILESTORE_NAME}"
    fi
}

# Function to clean up monitoring resources
cleanup_monitoring() {
    log_info "Cleaning up Cloud Monitoring resources..."
    
    # List and delete alert policies with specific display name
    log_info "Searching for tenant quota alert policies..."
    local alert_policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:'Tenant Quota Violation Alert'" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${alert_policies}" ]]; then
        while IFS= read -r policy; do
            if [[ -n "${policy}" ]]; then
                log_info "Deleting alert policy: ${policy}..."
                if gcloud alpha monitoring policies delete "${policy}" --quiet; then
                    log_success "Deleted alert policy"
                else
                    log_warning "Failed to delete alert policy: ${policy}"
                fi
            fi
        done <<< "${alert_policies}"
    else
        log_warning "No tenant quota alert policies found"
    fi
    
    # List and delete dashboards with specific display name
    log_info "Searching for multi-tenant dashboards..."
    local dashboards=$(gcloud monitoring dashboards list \
        --filter="displayName:'Multi-Tenant Resource Dashboard'" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${dashboards}" ]]; then
        while IFS= read -r dashboard; do
            if [[ -n "${dashboard}" ]]; then
                log_info "Deleting dashboard: ${dashboard}..."
                if gcloud monitoring dashboards delete "${dashboard}" --quiet; then
                    log_success "Deleted dashboard"
                else
                    log_warning "Failed to delete dashboard: ${dashboard}"
                fi
            fi
        done <<< "${dashboards}"
    else
        log_warning "No multi-tenant dashboards found"
    fi
    
    log_success "Monitoring cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files and directories..."
    
    local files_to_remove=(
        "cloud-function-source"
        "quota-alert-policy.yaml"
        "tenant-dashboard.json"
        "deployment-info.json"
    )
    
    for item in "${files_to_remove[@]}"; do
        if [[ -e "${item}" ]]; then
            log_info "Removing: ${item}"
            rm -rf "${item}"
            log_success "Removed: ${item}"
        else
            log_warning "File/directory not found: ${item}"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local errors=0
    
    # Check Filestore instance
    if gcloud filestore instances describe "${FILESTORE_NAME}" --zone="${ZONE}" &>/dev/null; then
        log_warning "Filestore instance still exists (may be in deletion process)"
    else
        log_success "Filestore instance cleanup verified"
    fi
    
    # Check Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        log_error "Cloud Function still exists: ${FUNCTION_NAME}"
        ((errors++))
    else
        log_success "Cloud Function cleanup verified"
    fi
    
    # Check Scheduler jobs
    for job in "${SCHEDULER_JOBS[@]}"; do
        if gcloud scheduler jobs describe "${job}" &>/dev/null; then
            log_error "Scheduler job still exists: ${job}"
            ((errors++))
        fi
    done
    
    if [[ ${errors} -eq 0 ]]; then
        log_success "All resources cleaned up successfully"
    else
        log_warning "${errors} resources may still exist. Please check manually."
    fi
}

# Function to display cleanup summary
display_summary() {
    log_success "Cleanup process completed!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Resource Suffix: ${RESOURCE_SUFFIX}"
    echo
    echo "=== RESOURCES REMOVED ==="
    echo "✓ Cloud Scheduler jobs"
    echo "✓ Cloud Function: ${FUNCTION_NAME}"
    echo "✓ Cloud Filestore instance: ${FILESTORE_NAME} (deletion in progress)"
    echo "✓ Cloud Monitoring alert policies and dashboards"
    echo "✓ Local files and directories"
    echo
    echo "=== NOTES ==="
    echo "- Filestore deletion may take several minutes to complete"
    echo "- Some monitoring resources may need manual deletion via Console"
    echo "- Check the Google Cloud Console to verify complete cleanup"
    echo
    echo "=== VERIFICATION ==="
    echo "To verify all resources are deleted, check:"
    echo "1. Cloud Functions: https://console.cloud.google.com/functions"
    echo "2. Cloud Scheduler: https://console.cloud.google.com/cloudscheduler"
    echo "3. Cloud Filestore: https://console.cloud.google.com/filestore"
    echo "4. Cloud Monitoring: https://console.cloud.google.com/monitoring"
}

# Function to handle cleanup errors gracefully
handle_cleanup_errors() {
    log_warning "Some cleanup operations may have failed."
    log_info "Please manually check and delete any remaining resources:"
    echo
    echo "Resources to check:"
    echo "- Cloud Function: ${FUNCTION_NAME}"
    echo "- Filestore instance: ${FILESTORE_NAME}"
    echo "- Scheduler jobs: ${SCHEDULER_JOBS[*]}"
    echo "- Monitoring alert policies and dashboards"
    echo
    echo "Use the Google Cloud Console or gcloud commands to remove any remaining resources."
}

# Function to ask for force cleanup without confirmation
parse_arguments() {
    local force_cleanup=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force_cleanup=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --force    Skip confirmation prompt"
                echo "  --help     Show this help message"
                exit 0
                ;;
            *)
                log_warning "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    if [[ "${force_cleanup}" == true ]]; then
        log_info "Force cleanup mode enabled - skipping confirmation"
        export SKIP_CONFIRMATION=true
    fi
}

# Main cleanup function
main() {
    log_info "Starting Multi-Tenant Resource Scheduling cleanup..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Set error handler
    trap handle_cleanup_errors ERR
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_info
    
    # Confirm deletion unless force mode is enabled
    if [[ "${SKIP_CONFIRMATION:-false}" != true ]]; then
        confirm_deletion
    fi
    
    # Perform cleanup in reverse order of creation
    delete_scheduler_jobs
    delete_function
    delete_filestore
    cleanup_monitoring
    cleanup_local_files
    verify_cleanup
    display_summary
    
    log_success "Cleanup process completed successfully!"
}

# Run main function with all arguments
main "$@"