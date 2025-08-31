#!/bin/bash

# Destroy script for Daily System Status Reports with Cloud Scheduler and Gmail
# This script removes all GCP resources created for the automated daily status reporting system

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message function
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error_exit "No active gcloud authentication found. Run 'gcloud auth login' first."
    fi
    
    # Check if project is set
    if [ -z "${PROJECT_ID:-}" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -z "$PROJECT_ID" ]; then
            error_exit "No GCP project set. Set PROJECT_ID environment variable or run 'gcloud config set project PROJECT_ID'"
        fi
    fi
    
    success "Prerequisites check completed"
}

# Function to set default values
set_defaults() {
    info "Setting default configuration..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
    export REGION="${REGION:-us-central1}"
    export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-status-reporter}"
    
    # If function name and job name are not provided, attempt to discover them
    if [ -z "${FUNCTION_NAME:-}" ] || [ -z "${JOB_NAME:-}" ]; then
        info "Resource names not provided, attempting to discover existing resources..."
        
        # Try to find existing functions with our pattern
        DISCOVERED_FUNCTIONS=$(gcloud functions list --regions="$REGION" --project="$PROJECT_ID" --format="value(name)" --filter="name:daily-status-report-*" 2>/dev/null || echo "")
        
        # Try to find existing scheduler jobs with our pattern
        DISCOVERED_JOBS=$(gcloud scheduler jobs list --location="$REGION" --project="$PROJECT_ID" --format="value(name)" --filter="name:daily-report-trigger-*" 2>/dev/null || echo "")
        
        if [ -n "$DISCOVERED_FUNCTIONS" ] || [ -n "$DISCOVERED_JOBS" ]; then
            info "Found existing resources:"
            [ -n "$DISCOVERED_FUNCTIONS" ] && echo "  Functions: $DISCOVERED_FUNCTIONS"
            [ -n "$DISCOVERED_JOBS" ] && echo "  Jobs: $DISCOVERED_JOBS"
            echo ""
            echo "Please set environment variables for the resources you want to delete:"
            echo "  export FUNCTION_NAME='function-name'"
            echo "  export JOB_NAME='job-name'"
            echo ""
            read -p "Do you want to delete ALL discovered resources? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                FUNCTIONS_TO_DELETE="$DISCOVERED_FUNCTIONS"
                JOBS_TO_DELETE="$DISCOVERED_JOBS"
            else
                error_exit "Please set FUNCTION_NAME and JOB_NAME environment variables"
            fi
        else
            error_exit "No resources found and no names provided. Set FUNCTION_NAME and JOB_NAME environment variables."
        fi
    fi
    
    success "Configuration set - Project: $PROJECT_ID, Region: $REGION"
}

# Function to confirm destructive actions
confirm_destruction() {
    echo ""
    echo "=========================================="
    echo "  DESTRUCTION CONFIRMATION"
    echo "=========================================="
    echo "This will permanently delete the following resources:"
    echo ""
    
    if [ -n "${FUNCTION_NAME:-}" ]; then
        echo "• Cloud Function: $FUNCTION_NAME"
    fi
    
    if [ -n "${FUNCTIONS_TO_DELETE:-}" ]; then
        for func in $FUNCTIONS_TO_DELETE; do
            echo "• Cloud Function: $func"
        done
    fi
    
    if [ -n "${JOB_NAME:-}" ]; then
        echo "• Cloud Scheduler Job: $JOB_NAME"
    fi
    
    if [ -n "${JOBS_TO_DELETE:-}" ]; then
        for job in $JOBS_TO_DELETE; do
            echo "• Cloud Scheduler Job: $job"
        done
    fi
    
    echo "• Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "• Function source code directory"
    echo ""
    echo "Project: $PROJECT_ID"
    echo "Region: $REGION"
    echo "=========================================="
    echo ""
    
    # Double confirmation for destructive action
    read -p "Are you sure you want to delete these resources? This cannot be undone. (type 'yes' to confirm): " confirmation
    if [ "$confirmation" != "yes" ]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Final confirmation - Delete ALL resources? (type 'DELETE' to confirm): " final_confirmation
    if [ "$final_confirmation" != "DELETE" ]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed - proceeding with resource cleanup"
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    info "Deleting Cloud Scheduler jobs..."
    
    local jobs_deleted=0
    
    # Delete specific job if provided
    if [ -n "${JOB_NAME:-}" ]; then
        if gcloud scheduler jobs describe "$JOB_NAME" --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
            info "Deleting scheduler job: $JOB_NAME"
            if gcloud scheduler jobs delete "$JOB_NAME" \
                --location="$REGION" \
                --project="$PROJECT_ID" \
                --quiet 2>&1 | tee -a "$LOG_FILE"; then
                success "Deleted scheduler job: $JOB_NAME"
                ((jobs_deleted++))
            else
                warning "Failed to delete scheduler job: $JOB_NAME"
            fi
        else
            warning "Scheduler job not found: $JOB_NAME"
        fi
    fi
    
    # Delete discovered jobs
    if [ -n "${JOBS_TO_DELETE:-}" ]; then
        for job in $JOBS_TO_DELETE; do
            if gcloud scheduler jobs describe "$job" --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
                info "Deleting scheduler job: $job"
                if gcloud scheduler jobs delete "$job" \
                    --location="$REGION" \
                    --project="$PROJECT_ID" \
                    --quiet 2>&1 | tee -a "$LOG_FILE"; then
                    success "Deleted scheduler job: $job"
                    ((jobs_deleted++))
                else
                    warning "Failed to delete scheduler job: $job"
                fi
            else
                warning "Scheduler job not found: $job"
            fi
        done
    fi
    
    if [ $jobs_deleted -gt 0 ]; then
        success "Deleted $jobs_deleted scheduler job(s)"
    else
        warning "No scheduler jobs were deleted"
    fi
}

# Function to delete Cloud Functions
delete_functions() {
    info "Deleting Cloud Functions..."
    
    local functions_deleted=0
    
    # Delete specific function if provided
    if [ -n "${FUNCTION_NAME:-}" ]; then
        if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
            info "Deleting function: $FUNCTION_NAME"
            if gcloud functions delete "$FUNCTION_NAME" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --quiet 2>&1 | tee -a "$LOG_FILE"; then
                success "Deleted function: $FUNCTION_NAME"
                ((functions_deleted++))
            else
                warning "Failed to delete function: $FUNCTION_NAME"
            fi
        else
            warning "Function not found: $FUNCTION_NAME"
        fi
    fi
    
    # Delete discovered functions
    if [ -n "${FUNCTIONS_TO_DELETE:-}" ]; then
        for func in $FUNCTIONS_TO_DELETE; do
            if gcloud functions describe "$func" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
                info "Deleting function: $func"
                if gcloud functions delete "$func" \
                    --region="$REGION" \
                    --project="$PROJECT_ID" \
                    --quiet 2>&1 | tee -a "$LOG_FILE"; then
                    success "Deleted function: $func"
                    ((functions_deleted++))
                else
                    warning "Failed to delete function: $func"
                fi
            else
                warning "Function not found: $func"
            fi
        done
    fi
    
    if [ $functions_deleted -gt 0 ]; then
        success "Deleted $functions_deleted function(s)"
    else
        warning "No functions were deleted"
    fi
}

# Function to delete service account
delete_service_account() {
    info "Deleting service account and removing IAM bindings..."
    
    local service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "$service_account_email" --project="$PROJECT_ID" &>/dev/null; then
        
        # Remove IAM policy binding first
        info "Removing IAM policy binding for monitoring viewer role..."
        if gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$service_account_email" \
            --role="roles/monitoring.viewer" \
            --quiet 2>&1 | tee -a "$LOG_FILE"; then
            success "Removed IAM policy binding"
        else
            warning "Failed to remove IAM policy binding or binding doesn't exist"
        fi
        
        # Delete service account
        info "Deleting service account: $service_account_email"
        if gcloud iam service-accounts delete "$service_account_email" \
            --project="$PROJECT_ID" \
            --quiet 2>&1 | tee -a "$LOG_FILE"; then
            success "Deleted service account: $service_account_email"
        else
            warning "Failed to delete service account: $service_account_email"
        fi
    else
        warning "Service account not found: $service_account_email"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    local function_dir="${SCRIPT_DIR}/../function"
    local logs_cleaned=0
    local dirs_cleaned=0
    
    # Remove function directory
    if [ -d "$function_dir" ]; then
        info "Removing function directory: $function_dir"
        if rm -rf "$function_dir"; then
            success "Removed function directory"
            ((dirs_cleaned++))
        else
            warning "Failed to remove function directory"
        fi
    fi
    
    # Clean up log files (but keep the current destroy log)
    if [ -f "${SCRIPT_DIR}/deploy.log" ]; then
        info "Removing deploy log file"
        if rm -f "${SCRIPT_DIR}/deploy.log"; then
            success "Removed deploy log file"
            ((logs_cleaned++))
        else
            warning "Failed to remove deploy log file"
        fi
    fi
    
    if [ $dirs_cleaned -gt 0 ] || [ $logs_cleaned -gt 0 ]; then
        success "Cleaned up local files"
    else
        info "No local files to clean up"
    fi
}

# Function to verify resource deletion
verify_deletion() {
    info "Verifying resource deletion..."
    
    local verification_errors=0
    
    # Check functions
    if [ -n "${FUNCTION_NAME:-}" ]; then
        if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
            warning "Function still exists: $FUNCTION_NAME"
            ((verification_errors++))
        fi
    fi
    
    # Check scheduler jobs
    if [ -n "${JOB_NAME:-}" ]; then
        if gcloud scheduler jobs describe "$JOB_NAME" --location="$REGION" --project="$PROJECT_ID" &>/dev/null; then
            warning "Scheduler job still exists: $JOB_NAME"
            ((verification_errors++))
        fi
    fi
    
    # Check service account
    local service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "$service_account_email" --project="$PROJECT_ID" &>/dev/null; then
        warning "Service account still exists: $service_account_email"
        ((verification_errors++))
    fi
    
    if [ $verification_errors -eq 0 ]; then
        success "All resources have been successfully deleted"
    else
        warning "$verification_errors resource(s) may still exist - manual cleanup may be required"
    fi
}

# Function to display destruction summary
show_summary() {
    echo ""
    echo "=========================================="
    echo "  DESTRUCTION SUMMARY"
    echo "=========================================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo ""
    echo "Resources processed for deletion:"
    
    if [ -n "${FUNCTION_NAME:-}" ]; then
        echo "• Cloud Function: $FUNCTION_NAME"
    fi
    
    if [ -n "${FUNCTIONS_TO_DELETE:-}" ]; then
        for func in $FUNCTIONS_TO_DELETE; do
            echo "• Cloud Function: $func"
        done
    fi
    
    if [ -n "${JOB_NAME:-}" ]; then
        echo "• Cloud Scheduler Job: $JOB_NAME"
    fi
    
    if [ -n "${JOBS_TO_DELETE:-}" ]; then
        for job in $JOBS_TO_DELETE; do
            echo "• Cloud Scheduler Job: $job"
        done
    fi
    
    echo "• Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "• Local function files"
    echo ""
    echo "Note: Google Cloud APIs remain enabled and can be used by other resources."
    echo "If you want to disable APIs, run:"
    echo "  gcloud services disable cloudfunctions.googleapis.com --project=$PROJECT_ID"
    echo "  gcloud services disable cloudscheduler.googleapis.com --project=$PROJECT_ID"
    echo "  gcloud services disable monitoring.googleapis.com --project=$PROJECT_ID"
    echo ""
    echo "Cleanup completed. Check the log file for details: $LOG_FILE"
    echo "=========================================="
}

# Main destruction function
main() {
    log "Starting destruction of Daily Status Reports system"
    
    check_prerequisites
    set_defaults
    confirm_destruction
    
    # Start cleanup process
    info "Beginning resource cleanup process..."
    
    delete_scheduler_jobs
    delete_functions
    delete_service_account
    cleanup_local_files
    verify_deletion
    show_summary
    
    success "Destruction process completed!"
    log "Destruction process completed"
}

# Handle script interruption
trap 'error_exit "Script interrupted by user"' INT TERM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --force      Skip confirmation prompts (use with caution)"
            echo "  --keep-logs  Keep log files after cleanup"
            echo "  --help       Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  PROJECT_ID             GCP project ID"
            echo "  REGION                 GCP region (default: us-central1)"
            echo "  FUNCTION_NAME          Name of Cloud Function to delete"
            echo "  JOB_NAME              Name of Cloud Scheduler job to delete"
            echo "  SERVICE_ACCOUNT_NAME   Name of service account to delete (default: status-reporter)"
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Override confirmation if force flag is set
if [ "${FORCE_DELETE:-}" = "true" ]; then
    confirm_destruction() {
        warning "Force delete enabled - skipping confirmation prompts"
        success "Proceeding with resource cleanup"
    }
fi

# Run main function
main "$@"