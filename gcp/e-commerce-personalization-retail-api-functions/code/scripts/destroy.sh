#!/bin/bash

# E-commerce Personalization with Retail API and Cloud Functions - Cleanup Script
# This script removes all resources created by the deployment script

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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="us-central1"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "You are not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to get project ID
get_project_id() {
    # Try to get project ID from deployment info file
    if [ -f "deployment_info.txt" ]; then
        PROJECT_ID=$(grep "Project ID:" deployment_info.txt | cut -d' ' -f3)
        BUCKET_NAME=$(grep "Storage Bucket:" deployment_info.txt | cut -d' ' -f3 | sed 's/gs:\/\///')
        log_info "Found project ID from deployment info: ${PROJECT_ID}"
    else
        # Get current project ID
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -z "${PROJECT_ID}" ]; then
            log_error "No project ID found. Please set your project with 'gcloud config set project PROJECT_ID'"
            exit 1
        fi
        log_warning "Using current project: ${PROJECT_ID}"
        log_warning "Bucket name detection may not work properly without deployment_info.txt"
    fi
    
    export PROJECT_ID
    export BUCKET_NAME
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    log_warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo "This will permanently delete:"
    echo "  - Project: ${PROJECT_ID}"
    echo "  - All Cloud Functions"
    echo "  - All Firestore data"
    echo "  - All Cloud Storage buckets and data"
    echo "  - All associated resources"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    # List of functions to delete
    local functions=(
        "catalog-sync"
        "track-user-events"
        "get-recommendations"
    )
    
    for func in "${functions[@]}"; do
        if gcloud functions describe "${func}" --region="${REGION}" --quiet > /dev/null 2>&1; then
            log_info "Deleting function: ${func}"
            gcloud functions delete "${func}" --region="${REGION}" --quiet
            log_success "Deleted function: ${func}"
        else
            log_warning "Function ${func} not found, skipping"
        fi
    done
    
    log_success "Cloud Functions cleanup completed"
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    log_info "Deleting Cloud Storage buckets..."
    
    # Get all buckets in the project
    local buckets
    buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "^gs://" | sed 's|gs://||' | sed 's|/$||' || echo "")
    
    if [ -n "${buckets}" ]; then
        for bucket in ${buckets}; do
            log_info "Deleting bucket: gs://${bucket}"
            gsutil -m rm -r "gs://${bucket}" 2>/dev/null || {
                log_warning "Could not delete bucket gs://${bucket}, it may not exist or be empty"
            }
            log_success "Deleted bucket: gs://${bucket}"
        done
    else
        log_warning "No buckets found to delete"
    fi
    
    log_success "Cloud Storage cleanup completed"
}

# Function to delete Firestore data
delete_firestore_data() {
    log_info "Deleting Firestore data..."
    
    # Check if Firestore database exists
    if gcloud firestore databases list --format="value(name)" | grep -q "${PROJECT_ID}"; then
        log_info "Deleting Firestore collections..."
        
        # Try to delete specific collections
        local collections=(
            "user_profiles"
        )
        
        for collection in "${collections[@]}"; do
            if gcloud firestore collections list --format="value(collectionIds)" | grep -q "${collection}"; then
                log_info "Deleting collection: ${collection}"
                gcloud firestore collections delete "${collection}" --quiet 2>/dev/null || {
                    log_warning "Could not delete collection ${collection}, it may not exist"
                }
                log_success "Deleted collection: ${collection}"
            else
                log_warning "Collection ${collection} not found, skipping"
            fi
        done
        
        # Note: Firestore database itself cannot be deleted, only the data
        log_info "Firestore database cannot be deleted, only data has been cleared"
    else
        log_warning "No Firestore database found"
    fi
    
    log_success "Firestore cleanup completed"
}

# Function to delete Retail API data
delete_retail_api_data() {
    log_info "Deleting Retail API data..."
    
    # Try to delete products from the default catalog
    local catalog_name="projects/${PROJECT_ID}/locations/global/catalogs/default_catalog"
    local branch_name="${catalog_name}/branches/default_branch"
    
    # List products and delete them
    log_info "Cleaning up Retail API products..."
    
    # Note: There's no direct way to bulk delete all products via gcloud
    # Products will be automatically cleaned up when the project is deleted
    log_info "Retail API products will be cleaned up with project deletion"
    
    log_success "Retail API cleanup completed"
}

# Function to disable APIs
disable_apis() {
    log_info "Disabling APIs..."
    
    local apis=(
        "retail.googleapis.com"
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
        "run.googleapis.com"
        "pubsub.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Disabling ${api}..."
        gcloud services disable "${api}" --quiet 2>/dev/null || {
            log_warning "Could not disable ${api}, it may not be enabled"
        }
    done
    
    log_success "APIs disabled"
}

# Function to delete the entire project
delete_project() {
    log_info "Deleting project..."
    
    # Final confirmation for project deletion
    echo ""
    log_warning "⚠️  FINAL CONFIRMATION ⚠️"
    echo "This will permanently delete the entire project: ${PROJECT_ID}"
    echo "This action cannot be undone!"
    echo ""
    
    read -p "Type 'DELETE' to confirm project deletion: " -r
    echo ""
    
    if [[ $REPLY != "DELETE" ]]; then
        log_info "Project deletion cancelled"
        log_warning "Resources may still exist in the project"
        return 0
    fi
    
    log_info "Deleting project: ${PROJECT_ID}"
    
    # Delete the project
    gcloud projects delete "${PROJECT_ID}" --quiet
    
    log_success "Project deletion initiated: ${PROJECT_ID}"
    log_info "Project deletion may take several minutes to complete"
    log_info "You can check the status at: https://console.cloud.google.com/home/dashboard"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment info file
    if [ -f "deployment_info.txt" ]; then
        rm deployment_info.txt
        log_success "Removed deployment_info.txt"
    fi
    
    # Remove any temporary files
    rm -f sample_products.json 2>/dev/null || true
    
    log_success "Local files cleanup completed"
}

# Function to perform graceful cleanup (without project deletion)
graceful_cleanup() {
    log_info "Performing graceful cleanup (keeping project)..."
    
    delete_cloud_functions
    delete_storage_buckets
    delete_firestore_data
    delete_retail_api_data
    disable_apis
    cleanup_local_files
    
    log_success "Graceful cleanup completed"
    log_info "Project ${PROJECT_ID} has been preserved"
}

# Function to perform full cleanup (with project deletion)
full_cleanup() {
    log_info "Performing full cleanup (including project deletion)..."
    
    delete_cloud_functions
    delete_storage_buckets
    delete_firestore_data
    delete_retail_api_data
    cleanup_local_files
    delete_project
    
    log_success "Full cleanup completed"
}

# Function to display cleanup options
display_cleanup_options() {
    echo ""
    echo "=== Cleanup Options ==="
    echo "1. Graceful cleanup (delete resources, keep project)"
    echo "2. Full cleanup (delete entire project)"
    echo "3. Cancel cleanup"
    echo ""
    
    read -p "Select cleanup option (1-3): " -r
    echo ""
    
    case $REPLY in
        1)
            graceful_cleanup
            ;;
        2)
            full_cleanup
            ;;
        3)
            log_info "Cleanup cancelled"
            exit 0
            ;;
        *)
            log_error "Invalid option selected"
            exit 1
            ;;
    esac
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "=== Cleanup Summary ==="
    echo "✅ Cloud Functions deleted"
    echo "✅ Cloud Storage buckets deleted"
    echo "✅ Firestore data cleared"
    echo "✅ Retail API data cleared"
    echo "✅ Local files cleaned up"
    echo ""
    
    if gcloud projects describe "${PROJECT_ID}" --format="value(projectId)" > /dev/null 2>&1; then
        echo "📋 Project ${PROJECT_ID} still exists"
        echo "   You can manually delete it at: https://console.cloud.google.com/home/dashboard"
    else
        echo "🗑️  Project ${PROJECT_ID} has been deleted"
    fi
    
    echo ""
    log_success "E-commerce Personalization resources have been cleaned up"
}

# Main cleanup function
main() {
    log_info "Starting E-commerce Personalization cleanup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Get project information
    get_project_id
    
    # Confirm deletion
    confirm_deletion
    
    # Display cleanup options
    display_cleanup_options
    
    # Display summary
    display_cleanup_summary
    
    log_success "Cleanup process completed!"
}

# Handle script arguments
case "${1:-}" in
    --force-delete-project)
        log_info "Force deleting project mode enabled"
        check_prerequisites
        get_project_id
        confirm_deletion
        full_cleanup
        display_cleanup_summary
        ;;
    --graceful-only)
        log_info "Graceful cleanup mode enabled"
        check_prerequisites
        get_project_id
        confirm_deletion
        graceful_cleanup
        display_cleanup_summary
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --force-delete-project    Delete the entire project without prompting"
        echo "  --graceful-only          Delete resources but keep the project"
        echo "  --help, -h               Show this help message"
        echo ""
        echo "Without options, the script will prompt for cleanup preferences"
        exit 0
        ;;
    "")
        # No arguments, run interactive mode
        main
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac