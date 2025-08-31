#!/bin/bash

# Destroy script for Automated File Backup with Storage and Scheduler
# This script safely removes all resources created by the deployment script

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Cannot proceed with cleanup."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
    fi
    
    success "Prerequisites validated for cleanup"
}

# Function to load deployment configuration
load_configuration() {
    log "Loading deployment configuration..."
    
    if [[ ! -f ".deployment-config" ]]; then
        error "Deployment configuration file not found. Cannot determine resources to clean up."
    fi
    
    # Source the configuration file
    source .deployment-config
    
    # Verify required variables are set
    if [[ -z "${PROJECT_ID:-}" ]] || [[ -z "${REGION:-}" ]]; then
        error "Invalid deployment configuration. Missing required variables."
    fi
    
    # Set current project context
    gcloud config set project "${PROJECT_ID}" || error "Failed to set project context"
    
    success "Configuration loaded successfully"
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Resources to clean up:"
    log "  - Primary Bucket: ${PRIMARY_BUCKET:-unknown}"
    log "  - Backup Bucket: ${BACKUP_BUCKET:-unknown}"
    log "  - Function: ${FUNCTION_NAME:-unknown}"
    log "  - Scheduler Job: ${SCHEDULER_JOB_NAME:-unknown}"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo "⚠️  WARNING: This will permanently delete all backup resources!"
    echo ""
    echo "Resources to be deleted:"
    echo "  - Cloud Scheduler Job: ${SCHEDULER_JOB_NAME:-unknown}"
    echo "  - Cloud Function: ${FUNCTION_NAME:-unknown}"
    echo "  - Storage Bucket: gs://${BACKUP_BUCKET:-unknown} (and all contents)"
    echo "  - Storage Bucket: gs://${PRIMARY_BUCKET:-unknown} (and all contents)"
    echo ""
    echo "This action CANNOT be undone!"
    echo ""
    
    # Check for --force flag to skip confirmation
    if [[ "${1:-}" == "--force" ]]; then
        warning "Force flag detected. Skipping confirmation prompt."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    echo
    
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    log "Proceeding with resource cleanup..."
}

# Function to delete Cloud Scheduler job
delete_scheduler_job() {
    log "Deleting Cloud Scheduler job..."
    
    if [[ -z "${SCHEDULER_JOB_NAME:-}" ]]; then
        warning "Scheduler job name not found in configuration. Skipping."
        return 0
    fi
    
    # Check if job exists before attempting deletion
    if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" \
        --location="${REGION}" &> /dev/null; then
        
        log "Deleting scheduler job: ${SCHEDULER_JOB_NAME}"
        gcloud scheduler jobs delete "${SCHEDULER_JOB_NAME}" \
            --location="${REGION}" \
            --quiet || warning "Failed to delete scheduler job"
        
        success "Cloud Scheduler job deleted"
    else
        warning "Scheduler job '${SCHEDULER_JOB_NAME}' not found. May have been deleted already."
    fi
}

# Function to delete Cloud Function
delete_cloud_function() {
    log "Deleting Cloud Function..."
    
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        warning "Function name not found in configuration. Skipping."
        return 0
    fi
    
    # Check if function exists before attempting deletion
    if gcloud functions describe "${FUNCTION_NAME}" \
        --gen2 \
        --region="${REGION}" &> /dev/null; then
        
        log "Deleting Cloud Function: ${FUNCTION_NAME}"
        gcloud functions delete "${FUNCTION_NAME}" \
            --gen2 \
            --region="${REGION}" \
            --quiet || warning "Failed to delete Cloud Function"
        
        success "Cloud Function deleted"
    else
        warning "Cloud Function '${FUNCTION_NAME}' not found. May have been deleted already."
    fi
}

# Function to delete storage buckets
delete_storage_buckets() {
    log "Deleting storage buckets and all contents..."
    
    # Delete backup bucket
    if [[ -n "${BACKUP_BUCKET:-}" ]]; then
        if gcloud storage buckets describe "gs://${BACKUP_BUCKET}" &> /dev/null; then
            log "Deleting backup bucket: gs://${BACKUP_BUCKET}"
            
            # List contents before deletion for logging
            log "Backup bucket contents before deletion:"
            gcloud storage ls -r "gs://${BACKUP_BUCKET}/" || warning "Could not list backup bucket contents"
            
            # Delete bucket and all contents
            gcloud storage rm -r "gs://${BACKUP_BUCKET}" || warning "Failed to delete backup bucket"
            success "Backup bucket deleted"
        else
            warning "Backup bucket 'gs://${BACKUP_BUCKET}' not found. May have been deleted already."
        fi
    else
        warning "Backup bucket name not found in configuration. Skipping."
    fi
    
    # Delete primary bucket
    if [[ -n "${PRIMARY_BUCKET:-}" ]]; then
        if gcloud storage buckets describe "gs://${PRIMARY_BUCKET}" &> /dev/null; then
            log "Deleting primary bucket: gs://${PRIMARY_BUCKET}"
            
            # List contents before deletion for logging
            log "Primary bucket contents before deletion:"
            gcloud storage ls -r "gs://${PRIMARY_BUCKET}/" || warning "Could not list primary bucket contents"
            
            # Delete bucket and all contents
            gcloud storage rm -r "gs://${PRIMARY_BUCKET}" || warning "Failed to delete primary bucket"
            success "Primary bucket deleted"
        else
            warning "Primary bucket 'gs://${PRIMARY_BUCKET}' not found. May have been deleted already."
        fi
    else
        warning "Primary bucket name not found in configuration. Skipping."
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files and configuration..."
    
    # Remove deployment configuration file
    if [[ -f ".deployment-config" ]]; then
        rm -f .deployment-config
        success "Deployment configuration file removed"
    fi
    
    # Remove any leftover temporary directories
    if [[ -d "backup-demo" ]]; then
        rm -rf backup-demo
        log "Removed backup-demo directory"
    fi
    
    if [[ -d "backup-function" ]]; then
        rm -rf backup-function
        log "Removed backup-function directory"
    fi
    
    success "Local cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_success=true
    
    # Check if scheduler job still exists
    if [[ -n "${SCHEDULER_JOB_NAME:-}" ]]; then
        if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" \
            --location="${REGION}" &> /dev/null; then
            warning "Scheduler job still exists: ${SCHEDULER_JOB_NAME}"
            cleanup_success=false
        fi
    fi
    
    # Check if function still exists
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" \
            --gen2 \
            --region="${REGION}" &> /dev/null; then
            warning "Cloud Function still exists: ${FUNCTION_NAME}"
            cleanup_success=false
        fi
    fi
    
    # Check if buckets still exist
    if [[ -n "${PRIMARY_BUCKET:-}" ]]; then
        if gcloud storage buckets describe "gs://${PRIMARY_BUCKET}" &> /dev/null; then
            warning "Primary bucket still exists: gs://${PRIMARY_BUCKET}"
            cleanup_success=false
        fi
    fi
    
    if [[ -n "${BACKUP_BUCKET:-}" ]]; then
        if gcloud storage buckets describe "gs://${BACKUP_BUCKET}" &> /dev/null; then
            warning "Backup bucket still exists: gs://${BACKUP_BUCKET}"
            cleanup_success=false
        fi
    fi
    
    if [[ "$cleanup_success" == true ]]; then
        success "All resources have been successfully cleaned up"
    else
        warning "Some resources may still exist. Please check manually in the Google Cloud Console."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "===================="
    echo "The following resources have been deleted:"
    echo "  ✅ Cloud Scheduler Job: ${SCHEDULER_JOB_NAME:-unknown}"
    echo "  ✅ Cloud Function: ${FUNCTION_NAME:-unknown}"
    echo "  ✅ Primary Storage Bucket: gs://${PRIMARY_BUCKET:-unknown}"
    echo "  ✅ Backup Storage Bucket: gs://${BACKUP_BUCKET:-unknown}"
    echo "  ✅ Local configuration files"
    echo ""
    echo "⚠️  Note: The following resources were NOT deleted and may incur charges:"
    echo "  - Google Cloud Project: ${PROJECT_ID}"
    echo "  - Enabled APIs (they remain enabled)"
    echo "  - Cloud Function logs (retained based on log retention policies)"
    echo ""
    echo "If you want to delete the entire project, run:"
    echo "  gcloud projects delete ${PROJECT_ID}"
    echo ""
    echo "Cleanup completed on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo "===================="
}

# Function to handle script interruption
cleanup_on_interrupt() {
    error "Cleanup interrupted. Some resources may still exist and require manual deletion."
    exit 1
}

# Set trap for script interruption
trap cleanup_on_interrupt INT TERM

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force    Skip confirmation prompt and proceed with cleanup"
    echo "  --help     Show this usage information"
    echo ""
    echo "This script will delete all resources created by the deploy.sh script."
    echo "Make sure you have backed up any important data before running this script."
}

# Main cleanup function
main() {
    # Check for help flag
    if [[ "${1:-}" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    echo "🗑️  Starting GCP Automated File Backup Cleanup"
    echo "=============================================="
    
    check_prerequisites
    load_configuration
    confirm_destruction "$@"
    
    log "Beginning resource cleanup process..."
    
    # Delete resources in reverse order of creation
    delete_scheduler_job
    delete_cloud_function
    delete_storage_buckets
    cleanup_local_files
    
    # Verify cleanup was successful
    verify_cleanup
    display_cleanup_summary
    
    success "🎉 Cleanup completed successfully!"
}

# Run main function with all arguments
main "$@"