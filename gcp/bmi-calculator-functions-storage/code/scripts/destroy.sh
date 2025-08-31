#!/bin/bash

# BMI Calculator API with Cloud Functions - Cleanup Script
# This script safely removes all resources created by the BMI calculator deployment
# Generated for recipe: bmi-calculator-functions-storage

set -euo pipefail

# Color codes for output formatting
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

# Script directory and deployment state
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"
FUNCTION_SOURCE_DIR="${SCRIPT_DIR}/../function"

# Default values if state file doesn't exist
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
FUNCTION_NAME="${FUNCTION_NAME:-bmi-calculator}"
BUCKET_NAME="${BUCKET_NAME:-}"

# Load deployment state if available
load_deployment_state() {
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        log_info "Loading deployment state from previous deployment..."
        source "${DEPLOYMENT_STATE_FILE}"
        log_info "Loaded state - Project: ${PROJECT_ID}, Function: ${FUNCTION_NAME}, Bucket: ${BUCKET_NAME}"
    else
        log_warning "No deployment state file found. Using environment variables or defaults."
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "PROJECT_ID not set and no deployment state found."
            log_error "Please set PROJECT_ID environment variable or ensure .deployment_state file exists."
            exit 1
        fi
        if [[ -z "${BUCKET_NAME}" ]]; then
            log_error "BUCKET_NAME not set and no deployment state found."
            log_error "Please set BUCKET_NAME environment variable or ensure .deployment_state file exists."
            exit 1
        fi
    fi
}

# Confirmation prompt for destructive actions
confirm_destruction() {
    echo ""
    log_warning "This will permanently delete the following resources:"
    log_warning "- Project: ${PROJECT_ID} (if you choose complete project deletion)"
    log_warning "- Cloud Function: ${FUNCTION_NAME}"
    log_warning "- Cloud Storage Bucket: ${BUCKET_NAME} (and all stored calculation data)"
    log_warning "- Generated function source code"
    echo ""
    
    # Offer different cleanup options
    echo "Cleanup options:"
    echo "1. Clean up resources only (keep project)"
    echo "2. Delete entire project (recommended for demo/test deployments)"
    echo "3. Cancel cleanup"
    echo ""
    
    read -p "Choose an option (1-3): " -n 1 -r
    echo ""
    
    case $REPLY in
        1)
            log_info "Selected: Clean up resources only"
            return 0
            ;;
        2)
            log_info "Selected: Delete entire project"
            DELETE_PROJECT=true
            return 0
            ;;
        3)
            log_info "Cleanup cancelled by user"
            exit 0
            ;;
        *)
            log_error "Invalid option. Cleanup cancelled."
            exit 1
            ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Cannot proceed with storage cleanup."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active Google Cloud authentication found. Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set project context
set_project_context() {
    log_info "Setting project context..."
    
    # Verify project exists
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project ${PROJECT_ID} not found or not accessible"
        exit 1
    fi
    
    # Set current project
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set functions/region "${REGION}"
    
    log_success "Project context set to: ${PROJECT_ID}"
}

# Delete Cloud Function
delete_cloud_function() {
    log_info "Deleting Cloud Function: ${FUNCTION_NAME}..."
    
    # Check if function exists
    if gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" &> /dev/null; then
        # Delete the function
        gcloud functions delete "${FUNCTION_NAME}" \
            --gen2 \
            --region="${REGION}" \
            --quiet || {
            log_error "Failed to delete Cloud Function: ${FUNCTION_NAME}"
            return 1
        }
        log_success "Cloud Function deleted: ${FUNCTION_NAME}"
    else
        log_warning "Cloud Function ${FUNCTION_NAME} not found (may have been already deleted)"
    fi
}

# Delete Cloud Storage bucket and all contents
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket: ${BUCKET_NAME}..."
    
    # Check if bucket exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        # List contents before deletion for logging
        local object_count
        object_count=$(gsutil ls -r "gs://${BUCKET_NAME}" 2>/dev/null | wc -l || echo "0")
        
        if [[ "${object_count}" -gt 0 ]]; then
            log_warning "Bucket contains ${object_count} objects. All will be deleted permanently."
        fi
        
        # Delete all objects and the bucket itself
        gsutil -m rm -r "gs://${BUCKET_NAME}" || {
            log_error "Failed to delete Cloud Storage bucket: ${BUCKET_NAME}"
            return 1
        }
        log_success "Cloud Storage bucket deleted: ${BUCKET_NAME}"
    else
        log_warning "Cloud Storage bucket ${BUCKET_NAME} not found (may have been already deleted)"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove function source directory
    if [[ -d "${FUNCTION_SOURCE_DIR}" ]]; then
        rm -rf "${FUNCTION_SOURCE_DIR}" || {
            log_warning "Failed to remove function source directory: ${FUNCTION_SOURCE_DIR}"
        }
        log_success "Function source directory removed"
    else
        log_warning "Function source directory not found: ${FUNCTION_SOURCE_DIR}"
    fi
    
    # Remove deployment state file
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        rm -f "${DEPLOYMENT_STATE_FILE}" || {
            log_warning "Failed to remove deployment state file: ${DEPLOYMENT_STATE_FILE}"
        }
        log_success "Deployment state file removed"
    else
        log_warning "Deployment state file not found: ${DEPLOYMENT_STATE_FILE}"
    fi
}

# Delete entire project
delete_project() {
    log_info "Deleting entire project: ${PROJECT_ID}..."
    
    log_warning "This will permanently delete the project and ALL resources within it."
    read -p "Are you absolutely sure? Type 'yes' to confirm: " -r
    echo ""
    
    if [[ $REPLY == "yes" ]]; then
        gcloud projects delete "${PROJECT_ID}" --quiet || {
            log_error "Failed to delete project: ${PROJECT_ID}"
            log_error "You may need to check the project status in the Google Cloud Console"
            return 1
        }
        log_success "Project deletion initiated: ${PROJECT_ID}"
        log_info "Note: Project deletion may take several minutes to complete"
        log_info "The project will be scheduled for deletion and removed after a grace period"
    else
        log_warning "Project deletion cancelled"
        return 1
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        log_info "Project deletion was initiated. Resources will be cleaned up automatically."
        return 0
    fi
    
    # Check if function still exists
    if gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" &> /dev/null; then
        log_warning "Cloud Function ${FUNCTION_NAME} still exists"
    else
        log_success "Confirmed: Cloud Function ${FUNCTION_NAME} deleted"
    fi
    
    # Check if bucket still exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        log_warning "Cloud Storage bucket ${BUCKET_NAME} still exists"
    else
        log_success "Confirmed: Cloud Storage bucket ${BUCKET_NAME} deleted"
    fi
    
    # Check local files
    if [[ -d "${FUNCTION_SOURCE_DIR}" ]] || [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        log_warning "Some local files still exist"
    else
        log_success "Confirmed: Local files cleaned up"
    fi
}

# Display cleanup summary
cleanup_summary() {
    echo ""
    log_success "Cleanup Summary:"
    
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        log_info "✓ Project ${PROJECT_ID} deletion initiated"
        log_info "✓ All project resources will be automatically cleaned up"
    else
        log_info "✓ Cloud Function ${FUNCTION_NAME} deleted"
        log_info "✓ Cloud Storage bucket ${BUCKET_NAME} deleted"
        log_info "✓ Local function source code removed"
        log_info "✓ Deployment state file removed"
    fi
    
    echo ""
    log_info "BMI Calculator API cleanup completed successfully!"
    
    if [[ "${DELETE_PROJECT:-false}" != "true" ]]; then
        log_warning "Note: The Google Cloud project ${PROJECT_ID} still exists."
        log_warning "If you no longer need it, you can delete it manually with:"
        log_warning "gcloud projects delete ${PROJECT_ID}"
    fi
}

# Error handling for partial cleanup
handle_cleanup_error() {
    log_error "Cleanup process encountered an error at line $1"
    log_warning "Some resources may not have been cleaned up completely."
    log_info "You may need to manually clean up remaining resources in the Google Cloud Console."
    exit 1
}

trap 'handle_cleanup_error $LINENO' ERR

# Main cleanup function
main() {
    log_info "Starting BMI Calculator API cleanup..."
    
    load_deployment_state
    check_prerequisites
    set_project_context
    confirm_destruction
    
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        delete_project
        cleanup_local_files
    else
        delete_cloud_function
        delete_storage_bucket
        cleanup_local_files
        verify_cleanup
    fi
    
    cleanup_summary
}

# Handle script interruption gracefully
handle_interrupt() {
    log_warning ""
    log_warning "Cleanup interrupted by user"
    log_warning "Some resources may not have been cleaned up completely."
    log_info "You can run this script again to continue cleanup or manually remove resources."
    exit 130
}

trap handle_interrupt SIGINT SIGTERM

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi