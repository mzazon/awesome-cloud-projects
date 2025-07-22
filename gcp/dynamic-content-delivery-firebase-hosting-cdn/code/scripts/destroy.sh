#!/bin/bash

set -euo pipefail

# Dynamic Content Delivery with Firebase Hosting and Cloud CDN - Cleanup Script
# This script removes all resources created by the deployment script
# to avoid ongoing charges and clean up the Google Cloud environment

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Check for environment file from deployment
    ENV_FILE=""
    if [ -f ".env" ]; then
        ENV_FILE=".env"
    elif [ -f "/tmp/.env" ]; then
        ENV_FILE="/tmp/.env"
    elif [ -n "${DEPLOY_DIR:-}" ] && [ -f "${DEPLOY_DIR}/.env" ]; then
        ENV_FILE="${DEPLOY_DIR}/.env"
    fi
    
    if [ -n "${ENV_FILE}" ]; then
        log "Loading environment from ${ENV_FILE}"
        # shellcheck source=/dev/null
        source "${ENV_FILE}"
        success "Environment variables loaded from deployment"
    else
        warning "No environment file found. Using manual input or environment variables."
    fi
    
    # Prompt for missing required variables
    if [ -z "${PROJECT_ID:-}" ]; then
        read -p "Enter Project ID to clean up: " PROJECT_ID
        export PROJECT_ID
    fi
    
    if [ -z "${REGION:-}" ]; then
        export REGION="us-central1"
        log "Using default region: ${REGION}"
    fi
    
    if [ -z "${SITE_ID:-}" ]; then
        read -p "Enter Firebase Site ID (or press Enter to skip): " SITE_ID
        export SITE_ID
    fi
    
    if [ -z "${STORAGE_BUCKET:-}" ]; then
        export STORAGE_BUCKET="${PROJECT_ID}-media"
        log "Using default storage bucket: ${STORAGE_BUCKET}"
    fi
    
    log "Cleanup will target:"
    log "  Project ID: ${PROJECT_ID}"
    log "  Region: ${REGION}"
    log "  Site ID: ${SITE_ID:-'Not specified'}"
    log "  Storage Bucket: ${STORAGE_BUCKET}"
}

# Function to confirm destructive action
confirm_cleanup() {
    log "This script will permanently delete the following resources:"
    echo "  - Google Cloud Project: ${PROJECT_ID}"
    echo "  - Firebase Hosting Site: ${SITE_ID:-'All sites in project'}"
    echo "  - Cloud Storage Bucket: gs://${STORAGE_BUCKET}"
    echo "  - Cloud Functions"
    echo "  - Load Balancer and CDN components"
    echo "  - All associated data and configurations"
    echo ""
    
    warning "This action CANNOT be undone!"
    echo ""
    
    # Require explicit confirmation
    read -p "Type 'DELETE' to confirm resource deletion: " CONFIRMATION
    
    if [ "${CONFIRMATION}" != "DELETE" ]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    success "Cleanup confirmed. Proceeding with resource deletion..."
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Cannot proceed with cleanup."
    fi
    
    # Check if Firebase CLI is installed
    if ! command -v firebase &> /dev/null; then
        warning "Firebase CLI is not installed. Firebase-specific cleanup will be skipped."
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available. Cannot clean up storage resources."
    fi
    
    success "Prerequisites verified"
}

# Function to authenticate
authenticate() {
    log "Checking authentication..."
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log "Authenticating with Google Cloud..."
        gcloud auth login
    fi
    
    # Check Firebase authentication (if CLI is available)
    if command -v firebase &> /dev/null; then
        if ! firebase projects:list &> /dev/null; then
            log "Authenticating with Firebase..."
            firebase login
        fi
    fi
    
    success "Authentication verified"
}

# Function to set project context
set_project_context() {
    log "Setting project context..."
    
    # Verify project exists
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        warning "Project ${PROJECT_ID} does not exist or is not accessible."
        read -p "Continue anyway? (y/N): " CONTINUE
        if [ "${CONTINUE,,}" != "y" ]; then
            log "Cleanup cancelled."
            exit 0
        fi
    fi
    
    # Set current project
    gcloud config set project "${PROJECT_ID}" || \
        warning "Failed to set project context"
    
    gcloud config set compute/region "${REGION}" || \
        warning "Failed to set region context"
    
    success "Project context configured"
}

# Function to delete Firebase Hosting site
delete_firebase_hosting() {
    log "Deleting Firebase Hosting resources..."
    
    if ! command -v firebase &> /dev/null; then
        warning "Firebase CLI not available. Skipping Firebase hosting cleanup."
        return
    fi
    
    if [ -n "${SITE_ID:-}" ]; then
        log "Deleting Firebase hosting site: ${SITE_ID}"
        if firebase hosting:sites:delete "${SITE_ID}" --project="${PROJECT_ID}" --force; then
            success "Firebase hosting site deleted: ${SITE_ID}"
        else
            warning "Failed to delete Firebase hosting site or site doesn't exist"
        fi
    else
        warning "No Firebase site ID specified. Skipping hosting site deletion."
    fi
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    # List and delete all functions in the project
    FUNCTIONS=$(gcloud functions list --format="value(name)" --filter="region:${REGION}" 2>/dev/null || echo "")
    
    if [ -n "${FUNCTIONS}" ]; then
        echo "${FUNCTIONS}" | while read -r function_name; do
            if [ -n "${function_name}" ]; then
                log "Deleting function: ${function_name}"
                if gcloud functions delete "${function_name}" --region="${REGION}" --quiet; then
                    success "Deleted function: ${function_name}"
                else
                    warning "Failed to delete function: ${function_name}"
                fi
            fi
        done
    else
        log "No Cloud Functions found in region ${REGION}"
    fi
    
    # Also try to delete specific functions by name if they exist
    KNOWN_FUNCTIONS=("getProducts" "getRecommendations")
    for func in "${KNOWN_FUNCTIONS[@]}"; do
        if gcloud functions describe "${func}" --region="${REGION}" &> /dev/null; then
            log "Deleting known function: ${func}"
            gcloud functions delete "${func}" --region="${REGION}" --quiet || \
                warning "Failed to delete function: ${func}"
        fi
    done
    
    success "Cloud Functions cleanup completed"
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log "Deleting Cloud Storage bucket..."
    
    # Check if bucket exists
    if gsutil ls "gs://${STORAGE_BUCKET}" &> /dev/null; then
        log "Deleting bucket contents: gs://${STORAGE_BUCKET}"
        
        # Delete all objects in the bucket (including versioned objects)
        if gsutil -m rm -r "gs://${STORAGE_BUCKET}/**" 2>/dev/null; then
            log "Bucket contents deleted"
        else
            log "No contents to delete or deletion failed"
        fi
        
        # Delete the bucket itself
        log "Deleting bucket: gs://${STORAGE_BUCKET}"
        if gsutil rb "gs://${STORAGE_BUCKET}"; then
            success "Storage bucket deleted: gs://${STORAGE_BUCKET}"
        else
            warning "Failed to delete storage bucket"
        fi
    else
        log "Storage bucket gs://${STORAGE_BUCKET} does not exist"
    fi
}

# Function to delete Load Balancer and CDN components
delete_load_balancer() {
    log "Deleting Load Balancer and CDN components..."
    
    # Delete forwarding rule
    if gcloud compute forwarding-rules describe cdn-forwarding-rule --global &> /dev/null; then
        log "Deleting forwarding rule: cdn-forwarding-rule"
        if gcloud compute forwarding-rules delete cdn-forwarding-rule --global --quiet; then
            success "Forwarding rule deleted"
        else
            warning "Failed to delete forwarding rule"
        fi
    fi
    
    # Delete target HTTP proxy
    if gcloud compute target-http-proxies describe cdn-http-proxy &> /dev/null; then
        log "Deleting target HTTP proxy: cdn-http-proxy"
        if gcloud compute target-http-proxies delete cdn-http-proxy --quiet; then
            success "Target HTTP proxy deleted"
        else
            warning "Failed to delete target HTTP proxy"
        fi
    fi
    
    # Delete URL map
    if gcloud compute url-maps describe cdn-url-map &> /dev/null; then
        log "Deleting URL map: cdn-url-map"
        if gcloud compute url-maps delete cdn-url-map --quiet; then
            success "URL map deleted"
        else
            warning "Failed to delete URL map"
        fi
    fi
    
    # Delete backend bucket
    BACKEND_BUCKET="${STORAGE_BUCKET}-backend"
    if gcloud compute backend-buckets describe "${BACKEND_BUCKET}" &> /dev/null; then
        log "Deleting backend bucket: ${BACKEND_BUCKET}"
        if gcloud compute backend-buckets delete "${BACKEND_BUCKET}" --quiet; then
            success "Backend bucket deleted"
        else
            warning "Failed to delete backend bucket"
        fi
    fi
    
    success "Load Balancer and CDN cleanup completed"
}

# Function to clean up IAM roles and permissions
cleanup_iam() {
    log "Cleaning up IAM roles and permissions..."
    
    # Remove public access from storage bucket (if it still exists)
    if gsutil ls "gs://${STORAGE_BUCKET}" &> /dev/null; then
        log "Removing public access from storage bucket"
        gsutil iam ch -d allUsers:objectViewer "gs://${STORAGE_BUCKET}" || \
            warning "Failed to remove public access or already removed"
    fi
    
    success "IAM cleanup completed"
}

# Function to disable APIs (optional)
disable_apis() {
    log "Disabling APIs (optional step)..."
    
    read -p "Disable APIs to prevent future charges? (y/N): " DISABLE_APIS_CHOICE
    
    if [ "${DISABLE_APIS_CHOICE,,}" = "y" ]; then
        APIS_TO_DISABLE=(
            "cloudfunctions.googleapis.com"
            "storage.googleapis.com"
            "compute.googleapis.com"
            "firebase.googleapis.com"
        )
        
        for api in "${APIS_TO_DISABLE[@]}"; do
            log "Disabling ${api}..."
            if gcloud services disable "${api}" --force --quiet; then
                success "Disabled ${api}"
            else
                warning "Failed to disable ${api}"
            fi
        done
    else
        log "Skipping API disabling"
    fi
}

# Function to delete the entire project
delete_project() {
    log "Project deletion options..."
    
    echo "Choose an option:"
    echo "1. Delete entire project (recommended for demo/test projects)"
    echo "2. Keep project and only delete specific resources"
    echo "3. Skip project deletion"
    
    read -p "Enter choice (1-3): " DELETE_CHOICE
    
    case "${DELETE_CHOICE}" in
        1)
            warning "This will delete the entire project: ${PROJECT_ID}"
            read -p "Type 'DELETE-PROJECT' to confirm: " PROJECT_CONFIRMATION
            
            if [ "${PROJECT_CONFIRMATION}" = "DELETE-PROJECT" ]; then
                log "Deleting project: ${PROJECT_ID}"
                if gcloud projects delete "${PROJECT_ID}" --quiet; then
                    success "Project ${PROJECT_ID} scheduled for deletion"
                    log "Project deletion will complete within 30 days"
                    log "All resources and data will be permanently removed"
                else
                    error "Failed to delete project"
                fi
            else
                log "Project deletion cancelled"
            fi
            ;;
        2)
            log "Project will be kept. Only specific resources have been deleted."
            disable_apis
            ;;
        3)
            log "Skipping project deletion"
            ;;
        *)
            warning "Invalid choice. Skipping project deletion."
            ;;
    esac
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local deployment files..."
    
    if [ -n "${DEPLOY_DIR:-}" ] && [ -d "${DEPLOY_DIR}" ]; then
        read -p "Delete local deployment directory ${DEPLOY_DIR}? (y/N): " DELETE_LOCAL
        if [ "${DELETE_LOCAL,,}" = "y" ]; then
            if rm -rf "${DEPLOY_DIR}"; then
                success "Local deployment directory deleted"
            else
                warning "Failed to delete local deployment directory"
            fi
        fi
    fi
    
    # Clean up environment file
    if [ -f ".env" ]; then
        read -p "Delete local .env file? (y/N): " DELETE_ENV
        if [ "${DELETE_ENV,,}" = "y" ]; then
            rm -f .env
            success "Local .env file deleted"
        fi
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "The following resources have been processed for deletion:"
    echo "✅ Firebase Hosting Site: ${SITE_ID:-'N/A'}"
    echo "✅ Cloud Functions"
    echo "✅ Cloud Storage Bucket: gs://${STORAGE_BUCKET}"
    echo "✅ Load Balancer and CDN components"
    echo "✅ IAM permissions"
    
    if [ "${DELETE_CHOICE:-}" = "1" ]; then
        echo "✅ Google Cloud Project: ${PROJECT_ID} (scheduled for deletion)"
    else
        echo "⚠️  Google Cloud Project: ${PROJECT_ID} (preserved)"
    fi
    
    echo ""
    echo "Notes:"
    echo "- Project deletion (if chosen) completes within 30 days"
    echo "- Some resources may take time to fully delete"
    echo "- Check Google Cloud Console to verify complete cleanup"
    echo "- Monitor billing to ensure no unexpected charges"
    
    success "Cleanup process completed!"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check if functions still exist
    REMAINING_FUNCTIONS=$(gcloud functions list --filter="region:${REGION}" --format="value(name)" 2>/dev/null | wc -l)
    log "Remaining Cloud Functions: ${REMAINING_FUNCTIONS}"
    
    # Check if storage bucket still exists
    if gsutil ls "gs://${STORAGE_BUCKET}" &> /dev/null; then
        warning "Storage bucket still exists: gs://${STORAGE_BUCKET}"
    else
        log "Storage bucket successfully removed"
    fi
    
    # Check load balancer components
    LB_COMPONENTS=$(gcloud compute forwarding-rules list --global --format="value(name)" | grep -c "cdn-" || echo "0")
    log "Remaining CDN components: ${LB_COMPONENTS}"
    
    success "Cleanup verification completed"
}

# Main cleanup function
main() {
    log "Starting Dynamic Content Delivery cleanup..."
    
    load_environment
    confirm_cleanup
    check_prerequisites
    authenticate
    set_project_context
    
    # Perform cleanup in reverse order of creation
    delete_firebase_hosting
    delete_cloud_functions
    cleanup_iam
    delete_load_balancer
    delete_storage_bucket
    
    verify_cleanup
    delete_project
    cleanup_local_files
    display_cleanup_summary
}

# Handle script interruption
cleanup_on_interrupt() {
    warning "Cleanup interrupted by user"
    log "Some resources may still exist and require manual cleanup"
    log "Check Google Cloud Console: https://console.cloud.google.com/"
    exit 1
}

trap cleanup_on_interrupt INT TERM

# Run main function
main "$@"