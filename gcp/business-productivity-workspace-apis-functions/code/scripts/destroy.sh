#!/bin/bash

# Business Productivity Workflows with Google Workspace APIs and Cloud Functions
# Cleanup/Destroy Script
#
# This script safely removes all resources created by the deployment script
# including Cloud Functions, Cloud SQL instances, and Cloud Scheduler jobs.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ -f "deployment_info.json" ]]; then
        # Extract values from deployment_info.json
        export PROJECT_ID=$(grep -o '"project_id": *"[^"]*"' deployment_info.json | grep -o '"[^"]*"$' | tr -d '"')
        export REGION=$(grep -o '"region": *"[^"]*"' deployment_info.json | grep -o '"[^"]*"$' | tr -d '"')
        export INSTANCE_NAME=$(grep -o '"database_instance": *"[^"]*"' deployment_info.json | grep -o '"[^"]*"$' | tr -d '"')
        export DATABASE_NAME=$(grep -o '"database_name": *"[^"]*"' deployment_info.json | grep -o '"[^"]*"$' | tr -d '"')
        export FUNCTION_PREFIX=$(grep -o '"function_prefix": *"[^"]*"' deployment_info.json | grep -o '"[^"]*"$' | tr -d '"')
        
        log_info "Loaded deployment info from deployment_info.json"
        log_info "Project ID: ${PROJECT_ID}"
        log_info "Region: ${REGION}"
        log_info "Function Prefix: ${FUNCTION_PREFIX}"
    else
        log_warning "deployment_info.json not found. Using environment variables or defaults."
        
        # Fallback to environment variables or defaults
        export PROJECT_ID="${PROJECT_ID:-}"
        export REGION="${REGION:-us-central1}"
        export INSTANCE_NAME="${INSTANCE_NAME:-productivity-instance}"
        export DATABASE_NAME="${DATABASE_NAME:-productivity_db}"
        export FUNCTION_PREFIX="${FUNCTION_PREFIX:-productivity}"
        
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "PROJECT_ID not found. Please set it as an environment variable or ensure deployment_info.json exists."
            exit 1
        fi
    fi
    
    # Set gcloud project
    gcloud config set project "${PROJECT_ID}" >/dev/null 2>&1
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "⚠️  WARNING: This will permanently delete the following resources:"
    echo "  - Cloud Functions (${FUNCTION_PREFIX}-*)"
    echo "  - Cloud SQL instance (${INSTANCE_NAME})"
    echo "  - Cloud Scheduler jobs"
    echo "  - Service account and credentials"
    echo "  - All data in the productivity database"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_info "User confirmed destruction. Proceeding..."
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log_info "Deleting Cloud Scheduler jobs..."
    
    local jobs=(
        "email-processing-job"
        "meeting-automation-job"
        "document-organization-job"
        "productivity-metrics-job"
    )
    
    for job in "${jobs[@]}"; do
        if gcloud scheduler jobs describe "${job}" >/dev/null 2>&1; then
            log_info "Deleting scheduler job: ${job}"
            gcloud scheduler jobs delete "${job}" --quiet
            log_success "Deleted job: ${job}"
        else
            log_warning "Scheduler job ${job} not found, skipping"
        fi
    done
    
    log_success "Cloud Scheduler jobs cleanup completed"
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    local functions=(
        "${FUNCTION_PREFIX}-email-processor"
        "${FUNCTION_PREFIX}-meeting-automation"
        "${FUNCTION_PREFIX}-document-organization"
        "${FUNCTION_PREFIX}-productivity-metrics"
    )
    
    for func in "${functions[@]}"; do
        if gcloud functions describe "${func}" --region="${REGION}" >/dev/null 2>&1; then
            log_info "Deleting function: ${func}"
            gcloud functions delete "${func}" --region="${REGION}" --quiet
            log_success "Deleted function: ${func}"
        else
            log_warning "Function ${func} not found in region ${REGION}, skipping"
        fi
    done
    
    log_success "Cloud Functions cleanup completed"
}

# Function to delete Cloud SQL instance
delete_cloud_sql() {
    log_info "Deleting Cloud SQL instance..."
    
    if gcloud sql instances describe "${INSTANCE_NAME}" >/dev/null 2>&1; then
        log_warning "Deleting Cloud SQL instance: ${INSTANCE_NAME}"
        log_warning "This will permanently delete all data in the instance!"
        
        # Additional confirmation for Cloud SQL deletion
        read -p "Are you sure you want to delete the Cloud SQL instance? (type 'delete' to confirm): " sql_confirmation
        
        if [[ "${sql_confirmation}" != "delete" ]]; then
            log_warning "Skipping Cloud SQL instance deletion"
        else
            gcloud sql instances delete "${INSTANCE_NAME}" --quiet
            log_success "Deleted Cloud SQL instance: ${INSTANCE_NAME}"
        fi
    else
        log_warning "Cloud SQL instance ${INSTANCE_NAME} not found, skipping"
    fi
    
    log_success "Cloud SQL cleanup completed"
}

# Function to delete service account
delete_service_account() {
    log_info "Deleting service account..."
    
    local service_account_name="workspace-automation"
    local service_account_email="${service_account_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "${service_account_email}" >/dev/null 2>&1; then
        log_info "Deleting service account: ${service_account_name}"
        gcloud iam service-accounts delete "${service_account_email}" --quiet
        log_success "Deleted service account: ${service_account_name}"
    else
        log_warning "Service account ${service_account_name} not found, skipping"
    fi
    
    log_success "Service account cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # List of files and directories to clean up
    local cleanup_items=(
        "credentials.json"
        ".db_password"
        "deployment_info.json"
        "email-processor/"
        "meeting-automation/"
        "document-organization/"
        "productivity-metrics/"
    )
    
    for item in "${cleanup_items[@]}"; do
        if [[ -e "${item}" ]]; then
            log_info "Removing: ${item}"
            rm -rf "${item}"
            log_success "Removed: ${item}"
        else
            log_warning "File/directory ${item} not found, skipping"
        fi
    done
    
    log_success "Local files cleanup completed"
}

# Function to disable APIs (optional)
disable_apis() {
    log_info "Checking if APIs should be disabled..."
    
    read -p "Do you want to disable the Google Cloud APIs? (y/N): " disable_confirmation
    
    if [[ "${disable_confirmation}" =~ ^[Yy]$ ]]; then
        log_info "Disabling Google Cloud APIs..."
        
        local apis=(
            "cloudfunctions.googleapis.com"
            "cloudscheduler.googleapis.com"
            "sqladmin.googleapis.com"
            "gmail.googleapis.com"
            "calendar.googleapis.com"
            "drive.googleapis.com"
            "cloudbuild.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log_info "Disabling ${api}..."
            gcloud services disable "${api}" --quiet || log_warning "Failed to disable ${api}"
        done
        
        log_success "APIs disabled"
    else
        log_info "Skipping API disabling"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local cleanup_errors=0
    
    # Check if Cloud Functions still exist
    local functions=(
        "${FUNCTION_PREFIX}-email-processor"
        "${FUNCTION_PREFIX}-meeting-automation"
        "${FUNCTION_PREFIX}-document-organization"
        "${FUNCTION_PREFIX}-productivity-metrics"
    )
    
    for func in "${functions[@]}"; do
        if gcloud functions describe "${func}" --region="${REGION}" >/dev/null 2>&1; then
            log_error "Function ${func} still exists"
            ((cleanup_errors++))
        fi
    done
    
    # Check if Cloud SQL instance still exists
    if gcloud sql instances describe "${INSTANCE_NAME}" >/dev/null 2>&1; then
        log_warning "Cloud SQL instance ${INSTANCE_NAME} still exists (may have been skipped)"
    fi
    
    # Check if scheduler jobs still exist
    local jobs=(
        "email-processing-job"
        "meeting-automation-job"
        "document-organization-job"
        "productivity-metrics-job"
    )
    
    for job in "${jobs[@]}"; do
        if gcloud scheduler jobs describe "${job}" >/dev/null 2>&1; then
            log_error "Scheduler job ${job} still exists"
            ((cleanup_errors++))
        fi
    done
    
    # Check if service account still exists
    local service_account_email="workspace-automation@${PROJECT_ID}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "${service_account_email}" >/dev/null 2>&1; then
        log_error "Service account ${service_account_email} still exists"
        ((cleanup_errors++))
    fi
    
    if [[ ${cleanup_errors} -eq 0 ]]; then
        log_success "Cleanup verification completed successfully"
    else
        log_error "Cleanup verification found ${cleanup_errors} errors"
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary:"
    echo "  ✅ Cloud Scheduler jobs deleted"
    echo "  ✅ Cloud Functions deleted"
    echo "  ✅ Cloud SQL instance deleted (if confirmed)"
    echo "  ✅ Service account deleted"
    echo "  ✅ Local files cleaned up"
    echo ""
    log_info "Resources that may still exist:"
    echo "  - Project (${PROJECT_ID}) - if you want to delete the entire project, do so manually"
    echo "  - Enabled APIs - if you chose not to disable them"
    echo "  - Cloud SQL instance - if you chose not to delete it"
    echo ""
    log_success "🎉 Business Productivity Workflows cleanup completed!"
}

# Function to handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Script interrupted or failed with exit code ${exit_code}"
        log_info "You may need to manually clean up remaining resources"
    fi
}

# Set trap for cleanup on exit
trap cleanup_on_exit EXIT

# Main cleanup function
main() {
    log_info "Starting Business Productivity Workflows cleanup..."
    
    # Validate prerequisites
    validate_prerequisites
    
    # Load deployment information
    load_deployment_info
    
    # Confirm destruction
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_scheduler_jobs
    
    delete_cloud_functions
    
    delete_cloud_sql
    
    delete_service_account
    
    cleanup_local_files
    
    # Optional: disable APIs
    disable_apis
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_cleanup_summary
}

# Handle dry-run mode
if [[ "${1:-}" == "--dry-run" ]]; then
    log_info "DRY RUN MODE: No resources will actually be deleted"
    echo ""
    echo "The following resources would be deleted:"
    echo "  - Cloud Scheduler jobs"
    echo "  - Cloud Functions with prefix: ${FUNCTION_PREFIX:-productivity}"
    echo "  - Cloud SQL instance: ${INSTANCE_NAME:-productivity-instance}"
    echo "  - Service account: workspace-automation"
    echo "  - Local files and directories"
    echo ""
    echo "Run without --dry-run to actually perform the cleanup"
    exit 0
fi

# Handle help
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deleted without actually deleting"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID        Google Cloud Project ID (auto-detected from deployment_info.json)"
    echo "  REGION           Google Cloud Region (default: us-central1)"
    echo "  INSTANCE_NAME    Cloud SQL instance name (default: productivity-instance)"
    echo "  FUNCTION_PREFIX  Cloud Functions prefix (auto-detected from deployment_info.json)"
    echo ""
    echo "This script will:"
    echo "1. Delete all Cloud Scheduler jobs"
    echo "2. Delete all Cloud Functions"
    echo "3. Delete the Cloud SQL instance (with confirmation)"
    echo "4. Delete the service account"
    echo "5. Clean up local files"
    echo "6. Optionally disable APIs"
    exit 0
fi

# Run main function
main "$@"