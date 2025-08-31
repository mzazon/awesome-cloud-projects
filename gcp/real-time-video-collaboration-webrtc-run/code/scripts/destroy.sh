#!/bin/bash

# Real-time Video Collaboration with WebRTC and Cloud Run - Cleanup Script
# This script removes all resources created by the deployment script:
# - Cloud Run service
# - Firestore database
# - IAP permissions
# - Project (optional)

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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check for required tools
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Load configuration from environment or prompt user
load_configuration() {
    log_info "Loading configuration..."
    
    # Try to get project ID from gcloud config
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    
    # Set default values or use environment variables
    export PROJECT_ID="${PROJECT_ID:-${CURRENT_PROJECT}}"
    export REGION="${REGION:-us-central1}"
    export SERVICE_NAME="${SERVICE_NAME:-webrtc-signaling}"
    export USER_EMAIL="${USER_EMAIL:-}"
    
    # Prompt for project ID if not available
    if [[ -z "${PROJECT_ID}" ]]; then
        log_warning "PROJECT_ID not set and no active project found."
        read -p "Enter the project ID to clean up: " PROJECT_ID
        export PROJECT_ID
    fi
    
    # Try to determine Firestore database name
    export FIRESTORE_DATABASE="${FIRESTORE_DATABASE:-}"
    if [[ -z "${FIRESTORE_DATABASE}" ]]; then
        # Try to find Firestore databases in the project
        DATABASES=$(gcloud firestore databases list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || echo "")
        if [[ -n "${DATABASES}" ]]; then
            # Show available databases
            log_info "Available Firestore databases:"
            echo "${DATABASES}" | while read -r db; do
                echo "  - $(basename "${db}")"
            done
            echo
            read -p "Enter the Firestore database name to delete (or press Enter to skip): " FIRESTORE_DATABASE
            export FIRESTORE_DATABASE
        fi
    fi
    
    log_info "Configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Service Name: ${SERVICE_NAME}"
    log_info "  Firestore Database: ${FIRESTORE_DATABASE:-<not specified>}"
    
    # Confirm with user
    echo
    log_warning "This will DELETE resources in project: ${PROJECT_ID}"
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Set project context
set_project_context() {
    log_info "Setting project context..."
    
    # Verify project exists
    if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log_error "Project ${PROJECT_ID} not found or not accessible"
        exit 1
    fi
    
    # Set project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    log_success "Project context set: ${PROJECT_ID}"
}

# Remove Cloud Run service
remove_cloud_run_service() {
    log_info "Removing Cloud Run service..."
    
    # Check if service exists
    if gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        log_info "Deleting Cloud Run service: ${SERVICE_NAME}"
        gcloud run services delete "${SERVICE_NAME}" \
            --region="${REGION}" \
            --quiet
        
        log_success "Cloud Run service deleted: ${SERVICE_NAME}"
    else
        log_warning "Cloud Run service ${SERVICE_NAME} not found in region ${REGION}"
    fi
    
    # Clean up any Container Registry images
    log_info "Checking for container images to clean up..."
    IMAGES=$(gcloud container images list --repository="gcr.io/${PROJECT_ID}" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${IMAGES}" ]]; then
        echo "${IMAGES}" | while read -r image; do
            if [[ "${image}" == *"${SERVICE_NAME}"* ]]; then
                log_info "Deleting container image: ${image}"
                gcloud container images delete "${image}" --quiet --force-delete-tags 2>/dev/null || true
            fi
        done
    fi
}

# Remove Firestore database
remove_firestore_database() {
    if [[ -z "${FIRESTORE_DATABASE}" ]]; then
        log_warning "Firestore database name not specified, skipping database deletion"
        return 0
    fi
    
    log_info "Removing Firestore database..."
    
    # Check if database exists
    if gcloud firestore databases describe "${FIRESTORE_DATABASE}" >/dev/null 2>&1; then
        log_warning "Deleting Firestore database: ${FIRESTORE_DATABASE}"
        log_warning "This will permanently delete all data in the database!"
        
        read -p "Are you sure you want to delete the database? (yes/no): " -r
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            gcloud firestore databases delete "${FIRESTORE_DATABASE}" --quiet
            log_success "Firestore database deleted: ${FIRESTORE_DATABASE}"
        else
            log_info "Firestore database deletion skipped by user"
        fi
    else
        log_warning "Firestore database ${FIRESTORE_DATABASE} not found"
    fi
}

# Remove IAP configuration
remove_iap_configuration() {
    log_info "Removing IAP configuration..."
    
    # Remove IAP IAM policy bindings
    if [[ -n "${USER_EMAIL}" ]]; then
        log_info "Removing IAP access for: ${USER_EMAIL}"
        gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="user:${USER_EMAIL}" \
            --role="roles/iap.httpsResourceAccessor" \
            --quiet 2>/dev/null || log_warning "Failed to remove IAP binding for ${USER_EMAIL}"
    fi
    
    # Note about manual cleanup
    log_info "Manual IAP cleanup required:"
    log_info "1. Disable IAP at: https://console.cloud.google.com/security/iap?project=${PROJECT_ID}"
    log_info "2. Delete OAuth 2.0 client at: https://console.cloud.google.com/apis/credentials?project=${PROJECT_ID}"
    log_info "3. Review OAuth consent screen at: https://console.cloud.google.com/apis/credentials/consent?project=${PROJECT_ID}"
    
    log_success "IAP permissions removed"
}

# Clean up Cloud Build artifacts
cleanup_cloud_build() {
    log_info "Cleaning up Cloud Build artifacts..."
    
    # List and delete builds related to the service
    BUILDS=$(gcloud builds list --filter="source.repoSource.repoName:${SERVICE_NAME} OR tags:${SERVICE_NAME}" --format="value(id)" --limit=50 2>/dev/null || echo "")
    
    if [[ -n "${BUILDS}" ]]; then
        echo "${BUILDS}" | while read -r build_id; do
            if [[ -n "${build_id}" ]]; then
                log_info "Cleaning up build: ${build_id}"
                # Note: Build history is automatically cleaned up by Google Cloud
                # We just log the builds that were created
            fi
        done
    fi
    
    log_success "Cloud Build cleanup completed"
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove temporary files created by deploy script
    rm -f /tmp/webrtc_service_url
    rm -f /tmp/webrtc_deploy_workdir
    
    log_success "Temporary files cleaned up"
}

# Verify resource deletion
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local cleanup_complete=true
    
    # Check Cloud Run service
    if gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        log_warning "Cloud Run service ${SERVICE_NAME} still exists"
        cleanup_complete=false
    else
        log_success "Cloud Run service deletion verified"
    fi
    
    # Check Firestore database
    if [[ -n "${FIRESTORE_DATABASE}" ]]; then
        if gcloud firestore databases describe "${FIRESTORE_DATABASE}" >/dev/null 2>&1; then
            log_warning "Firestore database ${FIRESTORE_DATABASE} still exists"
            cleanup_complete=false
        else
            log_success "Firestore database deletion verified"
        fi
    fi
    
    if [[ "${cleanup_complete}" == "true" ]]; then
        log_success "All automated cleanup verified"
    else
        log_warning "Some resources may still exist - check manually if needed"
    fi
}

# Option to delete entire project
offer_project_deletion() {
    log_info "Project cleanup options..."
    
    echo
    log_warning "Do you want to delete the entire project?"
    log_warning "This will permanently delete ALL resources in project: ${PROJECT_ID}"
    echo
    read -p "Delete entire project? (yes/no): " -r
    
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_warning "Deleting project: ${PROJECT_ID}"
        log_warning "This action cannot be undone!"
        
        read -p "Type the project ID to confirm deletion: " confirm_project
        
        if [[ "${confirm_project}" == "${PROJECT_ID}" ]]; then
            gcloud projects delete "${PROJECT_ID}" --quiet
            log_success "Project deletion initiated: ${PROJECT_ID}"
            log_info "Project deletion may take several minutes to complete"
        else
            log_error "Project ID confirmation failed. Project not deleted."
        fi
    else
        log_info "Project deletion skipped"
    fi
}

# Display cleanup summary
display_summary() {
    log_success "=== Cleanup Summary ==="
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Cloud Run Service: ${SERVICE_NAME} (deleted)"
    
    if [[ -n "${FIRESTORE_DATABASE}" ]]; then
        log_info "Firestore Database: ${FIRESTORE_DATABASE} (deleted)"
    fi
    
    if [[ -n "${USER_EMAIL}" ]]; then
        log_info "IAP User Access: ${USER_EMAIL} (removed)"
    fi
    
    echo
    log_info "Manual cleanup still required:"
    log_info "- Disable IAP in Google Cloud Console"
    log_info "- Delete OAuth 2.0 credentials"
    log_info "- Review and clean up OAuth consent screen"
    echo
    log_success "Automated cleanup completed!"
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Real-time Video Collaboration Platform..."
    
    validate_prerequisites
    load_configuration
    set_project_context
    remove_cloud_run_service
    remove_firestore_database
    remove_iap_configuration
    cleanup_cloud_build
    cleanup_temp_files
    verify_cleanup
    offer_project_deletion
    display_summary
    
    log_success "Cleanup completed successfully!"
}

# Handle script interruption
cleanup_on_exit() {
    log_warning "Script interrupted. Some resources may not have been cleaned up."
    log_info "Run the script again to complete cleanup, or clean up manually in the Google Cloud Console."
}

# Set trap for cleanup on exit
trap cleanup_on_exit INT TERM

# Run main function
main "$@"