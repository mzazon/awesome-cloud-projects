#!/bin/bash

# Website Screenshot API Cleanup Script
# This script removes all resources created by the screenshot API deployment
# Based on the website-screenshot-api-functions-storage recipe

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
FORCE_DELETE=${FORCE_DELETE:-false}

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Running in DRY-RUN mode - no resources will be deleted"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    log_info "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
    else
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || log_warning "Command failed but continuing..."
        else
            eval "$cmd"
        fi
    fi
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will DELETE ALL resources created by the screenshot API deployment"
    log_warning "This action is IRREVERSIBLE and will:"
    echo "  - Delete the Cloud Function and all its code"
    echo "  - Delete the Cloud Storage bucket and ALL screenshots"
    echo "  - Optionally delete the entire Google Cloud project"
    echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        read -p "Are you sure you want to continue? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    fi
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Try to load from deployment vars file first
    if [[ -f ".deployment_vars" ]]; then
        source .deployment_vars
        log_info "Loaded variables from .deployment_vars"
    fi
    
    # Set default values or use existing environment variables
    export PROJECT_ID="${PROJECT_ID:-}"
    export REGION="${REGION:-us-central1}"
    export FUNCTION_NAME="${FUNCTION_NAME:-screenshot-generator}"
    export BUCKET_NAME="${BUCKET_NAME:-}"
    
    # If no project ID is set, try to get current project
    if [[ -z "$PROJECT_ID" ]]; then
        if command -v gcloud &> /dev/null; then
            PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        fi
    fi
    
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID not found. Please set it as an environment variable or ensure .deployment_vars exists"
        log_info "You can find your project ID with: gcloud projects list"
        exit 1
    fi
    
    log_info "Environment variables:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  REGION: ${REGION}"
    log_info "  FUNCTION_NAME: ${FUNCTION_NAME}"
    log_info "  BUCKET_NAME: ${BUCKET_NAME}"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites satisfied"
}

# Function to set project context
set_project_context() {
    log_info "Setting project context..."
    
    # Verify project exists
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
            log_error "Project ${PROJECT_ID} does not exist or is not accessible"
            exit 1
        fi
    fi
    
    execute_command "gcloud config set project ${PROJECT_ID}" \
        "Setting active project to ${PROJECT_ID}"
    
    execute_command "gcloud config set functions/region ${REGION}" \
        "Setting functions region to ${REGION}"
}

# Function to delete Cloud Function
delete_function() {
    log_info "Deleting Cloud Function..."
    
    # Check if function exists
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" &> /dev/null; then
            log_warning "Function ${FUNCTION_NAME} not found, skipping deletion"
            return 0
        fi
    fi
    
    execute_command "gcloud functions delete ${FUNCTION_NAME} --gen2 --region=${REGION} --quiet" \
        "Deleting Cloud Function: ${FUNCTION_NAME}"
    
    log_success "Cloud Function deleted"
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket..."
    
    if [[ -z "$BUCKET_NAME" ]]; then
        log_warning "BUCKET_NAME not set, attempting to find bucket..."
        
        if [[ "$DRY_RUN" != "true" ]]; then
            # Try to find buckets with screenshot prefix
            local buckets
            buckets=$(gcloud storage buckets list --filter="name:screenshots-*" --format="value(name)" 2>/dev/null || echo "")
            
            if [[ -n "$buckets" ]]; then
                log_info "Found potential screenshot buckets:"
                echo "$buckets"
                if [[ "$FORCE_DELETE" != "true" ]]; then
                    echo ""
                    read -p "Enter the bucket name to delete (or press Enter to skip): " -r
                    BUCKET_NAME="$REPLY"
                fi
            fi
        fi
        
        if [[ -z "$BUCKET_NAME" ]]; then
            log_warning "No bucket name provided, skipping bucket deletion"
            return 0
        fi
    fi
    
    # Check if bucket exists
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" &> /dev/null; then
            log_warning "Bucket gs://${BUCKET_NAME} not found, skipping deletion"
            return 0
        fi
        
        # Check bucket contents
        local object_count
        object_count=$(gcloud storage ls "gs://${BUCKET_NAME}" 2>/dev/null | wc -l || echo "0")
        if [[ "$object_count" -gt 0 ]]; then
            log_warning "Bucket contains ${object_count} objects that will be deleted"
        fi
    fi
    
    # Delete all objects in bucket first
    execute_command "gcloud storage rm gs://${BUCKET_NAME}/** --recursive --quiet" \
        "Deleting all objects in bucket" \
        true
    
    # Delete the bucket
    execute_command "gcloud storage buckets delete gs://${BUCKET_NAME} --quiet" \
        "Deleting storage bucket: gs://${BUCKET_NAME}"
    
    log_success "Storage bucket deleted"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "screenshot-function"
        ".deployment_vars"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            execute_command "rm -rf $file" \
                "Removing local file/directory: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to optionally delete project
delete_project() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY-RUN: Would prompt for project deletion"
        return
    fi
    
    echo ""
    log_warning "Do you want to delete the entire project '${PROJECT_ID}'?"
    log_warning "This will delete ALL resources in the project, not just the screenshot API"
    
    if [[ "$FORCE_DELETE" != "true" ]]; then
        read -p "Delete entire project? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Project deletion skipped"
            return 0
        fi
    fi
    
    execute_command "gcloud projects delete ${PROJECT_ID} --quiet" \
        "Deleting project: ${PROJECT_ID}"
    
    log_success "Project deletion initiated (may take several minutes to complete)"
}

# Function to verify cleanup
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY-RUN: Would verify resource deletion"
        return
    fi
    
    log_info "Verifying cleanup..."
    
    # Check if function still exists
    if gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" &> /dev/null; then
        log_warning "Function ${FUNCTION_NAME} still exists"
    else
        log_success "Function successfully deleted"
    fi
    
    # Check if bucket still exists
    if [[ -n "$BUCKET_NAME" ]]; then
        if gcloud storage buckets describe "gs://${BUCKET_NAME}" &> /dev/null; then
            log_warning "Bucket gs://${BUCKET_NAME} still exists"
        else
            log_success "Bucket successfully deleted"
        fi
    fi
    
    log_success "Cleanup verification completed"
}

# Function to display cleanup summary
display_summary() {
    log_info "Cleanup Summary"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Function Name: ${FUNCTION_NAME}"
    echo "Storage Bucket: ${BUCKET_NAME:-<not specified>}"
    echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log_success "Cleanup completed successfully!"
        log_info "All screenshot API resources have been removed"
        log_info "If you deleted the project, it may take several minutes to complete"
    else
        log_info "This was a dry-run. No resources were actually deleted."
    fi
}

# Function to handle errors
handle_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code ${exit_code}"
    log_info "Some resources may not have been deleted. Check the logs above."
    log_info "You can run this script again to attempt cleanup of remaining resources"
    exit $exit_code
}

# Main cleanup function
main() {
    log_info "Starting Website Screenshot API cleanup..."
    
    # Set up error handling
    trap handle_error ERR
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_deletion
    set_project_context
    delete_function
    delete_storage_bucket
    cleanup_local_files
    
    # Ask about project deletion
    if [[ "$DRY_RUN" != "true" ]]; then
        delete_project
    fi
    
    verify_cleanup
    display_summary
}

# Handle command line arguments
case "${1:-}" in
    --dry-run)
        export DRY_RUN=true
        log_info "Dry-run mode enabled"
        ;;
    --force)
        export FORCE_DELETE=true
        log_warning "Force delete mode enabled - will skip confirmation prompts"
        ;;
    --help|-h)
        echo "Website Screenshot API Cleanup Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --dry-run    Show what would be deleted without removing resources"
        echo "  --force      Skip confirmation prompts (use with caution)"
        echo "  --help, -h   Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  PROJECT_ID    GCP project ID"
        echo "  REGION        GCP region (default: us-central1)"
        echo "  FUNCTION_NAME Function name (default: screenshot-generator)"
        echo "  BUCKET_NAME   Storage bucket name"
        echo ""
        echo "Examples:"
        echo "  $0                    # Interactive cleanup"
        echo "  $0 --dry-run          # Preview what would be deleted"
        echo "  $0 --force            # Delete without prompts"
        echo "  PROJECT_ID=my-proj $0 # Cleanup specific project"
        exit 0
        ;;
    "")
        # No arguments, proceed with cleanup
        ;;
    *)
        log_error "Unknown argument: $1"
        log_info "Use --help for usage information"
        exit 1
        ;;
esac

# Run main function
main