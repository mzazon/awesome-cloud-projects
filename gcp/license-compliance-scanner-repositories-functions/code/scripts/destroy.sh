#!/bin/bash

# License Compliance Scanner with Source Repositories and Functions - Cleanup Script
# This script safely removes all resources created by the deployment script
# Based on recipe: license-compliance-scanner-repositories-functions

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$ERROR_LOG"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

# Initialize log files
echo "=== License Compliance Scanner Cleanup Started at $(date) ===" > "$LOG_FILE"
echo "=== Error Log for License Compliance Scanner Cleanup ===" > "$ERROR_LOG"

log "Starting cleanup of License Compliance Scanner infrastructure"

# Load deployment variables
load_deployment_vars() {
    log "Loading deployment variables..."
    
    if [[ -f "${SCRIPT_DIR}/.deployment_vars" ]]; then
        source "${SCRIPT_DIR}/.deployment_vars"
        success "Loaded deployment variables from previous deployment"
        log "  PROJECT_ID: ${PROJECT_ID:-not set}"
        log "  REGION: ${REGION:-not set}"
        log "  BUCKET_NAME: ${BUCKET_NAME:-not set}"
        log "  REPO_NAME: ${REPO_NAME:-not set}"
        log "  FUNCTION_NAME: ${FUNCTION_NAME:-not set}"
    else
        warn "Deployment variables file not found. You may need to set variables manually."
        
        # Prompt for required variables if not set
        if [[ -z "${PROJECT_ID:-}" ]]; then
            read -p "Enter PROJECT_ID: " PROJECT_ID
            export PROJECT_ID
        fi
        
        if [[ -z "${REGION:-}" ]]; then
            export REGION="${REGION:-us-central1}"
        fi
        
        if [[ -z "${BUCKET_NAME:-}" ]]; then
            read -p "Enter BUCKET_NAME: " BUCKET_NAME
            export BUCKET_NAME
        fi
        
        if [[ -z "${REPO_NAME:-}" ]]; then
            read -p "Enter REPO_NAME: " REPO_NAME
            export REPO_NAME
        fi
        
        if [[ -z "${FUNCTION_NAME:-}" ]]; then
            read -p "Enter FUNCTION_NAME: " FUNCTION_NAME
            export FUNCTION_NAME
        fi
    fi
}

# Confirmation prompt
confirm_destruction() {
    echo
    warn "This will permanently delete the following resources:"
    echo "  - Project: ${PROJECT_ID}"
    echo "  - Storage Bucket: gs://${BUCKET_NAME} (and all contents)"
    echo "  - Source Repository: ${REPO_NAME}"
    echo "  - Cloud Function: ${FUNCTION_NAME}"
    echo "  - Cloud Scheduler Jobs: license-scan-daily, license-scan-weekly"
    echo
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        warn "FORCE_DESTROY is set, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "User confirmed destruction, proceeding with cleanup"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Set the project
    if ! gcloud config set project "${PROJECT_ID}"; then
        error "Failed to set project: ${PROJECT_ID}"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Remove Cloud Scheduler jobs
remove_scheduler_jobs() {
    log "Removing Cloud Scheduler jobs..."
    
    # List of jobs to remove
    local jobs=("license-scan-daily" "license-scan-weekly")
    
    for job in "${jobs[@]}"; do
        log "Removing scheduler job: ${job}"
        
        if gcloud scheduler jobs describe "${job}" \
            --location="${REGION}" \
            --project="${PROJECT_ID}" &>/dev/null; then
            
            if gcloud scheduler jobs delete "${job}" \
                --location="${REGION}" \
                --project="${PROJECT_ID}" \
                --quiet; then
                success "Removed scheduler job: ${job}"
            else
                error "Failed to remove scheduler job: ${job}"
            fi
        else
            warn "Scheduler job not found: ${job}"
        fi
    done
}

# Remove Cloud Function
remove_cloud_function() {
    log "Removing Cloud Function..."
    
    if gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        
        log "Deleting Cloud Function: ${FUNCTION_NAME}"
        if gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --project="${PROJECT_ID}" \
            --quiet; then
            success "Cloud Function deleted: ${FUNCTION_NAME}"
        else
            error "Failed to delete Cloud Function: ${FUNCTION_NAME}"
        fi
    else
        warn "Cloud Function not found: ${FUNCTION_NAME}"
    fi
}

# Remove Cloud Storage bucket
remove_storage_bucket() {
    log "Removing Cloud Storage bucket..."
    
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        # List contents before deletion for logging
        log "Bucket contents before deletion:"
        gsutil ls -r "gs://${BUCKET_NAME}" || warn "Could not list bucket contents"
        
        log "Deleting all objects and bucket: ${BUCKET_NAME}"
        if gsutil -m rm -r "gs://${BUCKET_NAME}"; then
            success "Storage bucket and all contents deleted: ${BUCKET_NAME}"
        else
            error "Failed to delete storage bucket: ${BUCKET_NAME}"
        fi
    else
        warn "Storage bucket not found: ${BUCKET_NAME}"
    fi
}

# Remove Cloud Source Repository
remove_source_repository() {
    log "Removing Cloud Source Repository..."
    
    if gcloud source repos describe "${REPO_NAME}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        
        log "Deleting Source Repository: ${REPO_NAME}"
        if gcloud source repos delete "${REPO_NAME}" \
            --project="${PROJECT_ID}" \
            --quiet; then
            success "Source Repository deleted: ${REPO_NAME}"
        else
            error "Failed to delete Source Repository: ${REPO_NAME}"
        fi
    else
        warn "Source Repository not found: ${REPO_NAME}"
    fi
}

# Clean up local temporary files
cleanup_local_files() {
    log "Cleaning up local temporary files..."
    
    # Remove deployment variables file
    if [[ -f "${SCRIPT_DIR}/.deployment_vars" ]]; then
        rm -f "${SCRIPT_DIR}/.deployment_vars"
        log "Removed deployment variables file"
    fi
    
    # Remove any temporary directories that might still exist
    local temp_dirs=(
        "${SCRIPT_DIR}/temp_repo_"*
        "${SCRIPT_DIR}/temp_function_"*
    )
    
    for pattern in "${temp_dirs[@]}"; do
        for dir in ${pattern}; do
            if [[ -d "${dir}" ]]; then
                rm -rf "${dir}"
                log "Removed temporary directory: ${dir}"
            fi
        done
    done
    
    success "Local cleanup completed"
}

# Optional: Disable APIs (commented out by default to avoid affecting other resources)
disable_apis() {
    if [[ "${DISABLE_APIS:-}" == "true" ]]; then
        log "Disabling GCP APIs (DISABLE_APIS=true)..."
        
        local apis=(
            "cloudscheduler.googleapis.com"
            "cloudfunctions.googleapis.com"
            "sourcerepo.googleapis.com"
            "cloudbuild.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log "Disabling API: ${api}"
            if gcloud services disable "${api}" \
                --project="${PROJECT_ID}" \
                --force \
                --quiet; then
                success "Disabled API: ${api}"
            else
                warn "Failed to disable API: ${api} (may be used by other resources)"
            fi
        done
    else
        log "Skipping API disabling (set DISABLE_APIS=true to enable)"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check if Cloud Function still exists
    if gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        error "Cloud Function still exists: ${FUNCTION_NAME}"
        ((cleanup_errors++))
    fi
    
    # Check if storage bucket still exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        error "Storage bucket still exists: ${BUCKET_NAME}"
        ((cleanup_errors++))
    fi
    
    # Check if source repository still exists
    if gcloud source repos describe "${REPO_NAME}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        error "Source Repository still exists: ${REPO_NAME}"
        ((cleanup_errors++))
    fi
    
    # Check scheduler jobs
    for job in "license-scan-daily" "license-scan-weekly"; do
        if gcloud scheduler jobs describe "${job}" \
            --location="${REGION}" \
            --project="${PROJECT_ID}" &>/dev/null; then
            error "Scheduler job still exists: ${job}"
            ((cleanup_errors++))
        fi
    done
    
    if [[ ${cleanup_errors} -eq 0 ]]; then
        success "Cleanup verification passed - all resources removed"
    else
        error "Cleanup verification failed - ${cleanup_errors} resources still exist"
        warn "You may need to manually remove remaining resources"
    fi
}

# Display cleanup summary
display_summary() {
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Resources removed:"
    echo "  ✓ Cloud Scheduler Jobs (license-scan-daily, license-scan-weekly)"
    echo "  ✓ Cloud Function (${FUNCTION_NAME})"
    echo "  ✓ Cloud Storage Bucket (${BUCKET_NAME})"
    echo "  ✓ Cloud Source Repository (${REPO_NAME})"
    echo "  ✓ Local temporary files"
    echo
    
    if [[ "${DISABLE_APIS:-}" == "true" ]]; then
        echo "  ✓ GCP APIs disabled"
    else
        echo "  - GCP APIs left enabled (set DISABLE_APIS=true to disable)"
    fi
    
    echo
    log "Cleanup completed successfully!"
    
    # Check if this was a dedicated project
    if [[ "${PROJECT_ID}" =~ license-scanner-.* ]]; then
        echo
        warn "This appears to be a dedicated project for the license scanner."
        warn "You may also want to delete the entire project:"
        warn "  gcloud projects delete ${PROJECT_ID}"
        echo
    fi
    
    success "License Compliance Scanner cleanup completed successfully"
}

# Error handling for partial cleanup
handle_partial_cleanup() {
    warn "Some resources may not have been fully cleaned up."
    warn "Please check the following manually:"
    echo
    echo "1. Cloud Console - Functions: https://console.cloud.google.com/functions"
    echo "2. Cloud Console - Storage: https://console.cloud.google.com/storage"
    echo "3. Cloud Console - Source Repositories: https://console.cloud.google.com/source/repos"
    echo "4. Cloud Console - Cloud Scheduler: https://console.cloud.google.com/cloudscheduler"
    echo
    warn "Check the error log for details: ${ERROR_LOG}"
}

# Main cleanup function
main() {
    log "=== Starting License Compliance Scanner Cleanup ==="
    
    load_deployment_vars
    confirm_destruction
    check_prerequisites
    
    # Perform cleanup in reverse order of creation
    remove_scheduler_jobs
    remove_cloud_function
    remove_storage_bucket
    remove_source_repository
    cleanup_local_files
    disable_apis
    verify_cleanup
    display_summary
    
    success "=== Cleanup completed successfully ==="
}

# Handle interruption gracefully
trap 'error "Cleanup interrupted"; handle_partial_cleanup; exit 1' INT TERM

# Check for force mode
if [[ "${1:-}" == "--force" ]]; then
    export FORCE_DESTROY="true"
    log "Running in force mode (no confirmation prompts)"
fi

# Check for API disable mode
if [[ "${1:-}" == "--disable-apis" ]] || [[ "${2:-}" == "--disable-apis" ]]; then
    export DISABLE_APIS="true"
    log "Will disable APIs after cleanup"
fi

# Run main function
main "$@"