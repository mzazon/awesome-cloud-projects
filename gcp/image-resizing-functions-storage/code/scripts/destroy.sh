#!/bin/bash

# Automatic Image Resizing with Cloud Functions and Storage - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
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

# Check if running in interactive mode
check_interactive() {
    if [[ -t 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Confirmation prompt
confirm() {
    if check_interactive; then
        echo -e "${RED}$1${NC}"
        read -p "Are you sure? Type 'yes' to confirm: " -r
        echo
        if [[ ! $REPLY == "yes" ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    else
        log_warning "Running in non-interactive mode - proceeding with cleanup"
        log_warning "This will delete ALL resources associated with this deployment"
        sleep 5
    fi
}

# Print banner
echo "=================================================="
echo "  GCP Image Resizing Infrastructure Cleanup"
echo "=================================================="
echo

# Check prerequisites
log_info "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
    exit 1
fi

# Check if gsutil is available
if ! command -v gsutil &> /dev/null; then
    log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed"
    exit 1
fi

log_success "Prerequisites check completed"

# Get current project ID if not set
if [[ -z "${PROJECT_ID:-}" ]]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "PROJECT_ID environment variable not set and no default project configured"
        log_error "Please set PROJECT_ID or run 'gcloud config set project YOUR_PROJECT_ID'"
        exit 1
    fi
    log_info "Using current project: ${PROJECT_ID}"
fi

# Set default values for environment variables if not provided
export REGION="${REGION:-us-central1}"
export FUNCTION_NAME="${FUNCTION_NAME:-resize-image-function}"

# Display current configuration
echo "Cleanup Configuration:"
echo "======================"
echo "Project ID: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo "Function Name: ${FUNCTION_NAME}"
echo

# Check if project exists and is accessible
log_info "Verifying project access..."
if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
    log_error "Cannot access project '${PROJECT_ID}'. Please check:"
    log_error "1. Project ID is correct"
    log_error "2. You have appropriate permissions"
    log_error "3. You are authenticated (run 'gcloud auth login')"
    exit 1
fi

log_success "Project access verified"

# Set gcloud project
gcloud config set project "${PROJECT_ID}" >/dev/null 2>&1

# Find all resources related to this deployment
log_info "Discovering resources to delete..."

# Find Cloud Functions
FUNCTIONS=($(gcloud functions list --gen2 --region="${REGION}" --filter="name:resize-image-function OR name:*resize*" --format="value(name)" 2>/dev/null || true))

# Find Storage buckets related to image resizing
BUCKETS=($(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "(original-images|resized-images)" || true))

# Display resources to be deleted
echo
echo "Resources to be deleted:"
echo "========================"

if [[ ${#FUNCTIONS[@]} -gt 0 ]]; then
    echo "Cloud Functions:"
    for func in "${FUNCTIONS[@]}"; do
        echo "  - ${func}"
    done
fi

if [[ ${#BUCKETS[@]} -gt 0 ]]; then
    echo "Storage Buckets:"
    for bucket in "${BUCKETS[@]}"; do
        echo "  - ${bucket}"
    done
fi

if [[ ${#FUNCTIONS[@]} -eq 0 && ${#BUCKETS[@]} -eq 0 ]]; then
    log_warning "No resources found to delete"
    log_info "The infrastructure may have already been cleaned up"
    exit 0
fi

echo

# Confirm deletion
confirm "This will permanently delete all the resources listed above and ALL their data."

# Start cleanup process
log_info "Starting cleanup process..."

# Remove Cloud Functions
if [[ ${#FUNCTIONS[@]} -gt 0 ]]; then
    log_info "Removing Cloud Functions..."
    
    for func in "${FUNCTIONS[@]}"; do
        log_info "Deleting function: ${func}"
        if gcloud functions delete "${func}" --gen2 --region="${REGION}" --quiet 2>/dev/null; then
            log_success "Function ${func} deleted successfully"
        else
            log_warning "Failed to delete function ${func} or it doesn't exist"
        fi
    done
else
    log_info "No Cloud Functions found to delete"
fi

# Wait for function deletion to complete
if [[ ${#FUNCTIONS[@]} -gt 0 ]]; then
    log_info "Waiting for function deletion to complete..."
    sleep 10
fi

# Remove Storage Buckets
if [[ ${#BUCKETS[@]} -gt 0 ]]; then
    log_info "Removing Storage Buckets and all their contents..."
    
    for bucket in "${BUCKETS[@]}"; do
        log_info "Deleting bucket: ${bucket}"
        
        # First, try to list objects to see if bucket has content
        OBJECT_COUNT=$(gsutil ls "${bucket}" 2>/dev/null | wc -l || echo "0")
        
        if [[ ${OBJECT_COUNT} -gt 0 ]]; then
            log_info "Bucket contains ${OBJECT_COUNT} objects, removing all contents..."
        fi
        
        # Delete bucket and all contents
        if gsutil -m rm -r "${bucket}" 2>/dev/null; then
            log_success "Bucket ${bucket} and all contents deleted successfully"
        else
            log_warning "Failed to delete bucket ${bucket} or it doesn't exist"
        fi
    done
else
    log_info "No Storage Buckets found to delete"
fi

# Clean up any local files that might have been created
log_info "Cleaning up local files..."

# Remove function directory if it exists
if [[ -d "cloud-function-resize" ]]; then
    rm -rf cloud-function-resize
    log_success "Removed local function directory"
fi

# Remove test images if they exist
for test_file in test-image.jpg test-image.png; do
    if [[ -f "${test_file}" ]]; then
        rm -f "${test_file}"
        log_success "Removed local test file: ${test_file}"
    fi
done

# Verify cleanup
log_info "Verifying cleanup completion..."

# Check if functions still exist
REMAINING_FUNCTIONS=$(gcloud functions list --gen2 --region="${REGION}" --filter="name:resize-image-function OR name:*resize*" --format="value(name)" 2>/dev/null | wc -l || echo "0")

# Check if buckets still exist
REMAINING_BUCKETS=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "(original-images|resized-images)" | wc -l || echo "0")

if [[ ${REMAINING_FUNCTIONS} -eq 0 && ${REMAINING_BUCKETS} -eq 0 ]]; then
    log_success "Cleanup verification successful - all resources removed"
else
    log_warning "Some resources may still exist:"
    if [[ ${REMAINING_FUNCTIONS} -gt 0 ]]; then
        log_warning "  - ${REMAINING_FUNCTIONS} Cloud Functions still found"
    fi
    if [[ ${REMAINING_BUCKETS} -gt 0 ]]; then
        log_warning "  - ${REMAINING_BUCKETS} Storage Buckets still found"
    fi
    log_info "Resources may take a few minutes to fully propagate deletion"
fi

# Print cleanup summary
echo
echo "=================================================="
echo "         Cleanup Summary"
echo "=================================================="
echo -e "Status: ${GREEN}COMPLETED${NC}"
echo "Project ID: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo
echo "Cleanup Actions Performed:"
echo "- Deleted Cloud Functions: ${#FUNCTIONS[@]}"
echo "- Deleted Storage Buckets: ${#BUCKETS[@]}"
echo "- Cleaned up local files"
echo
echo "Note: Some resources may take a few minutes to fully"
echo "      propagate deletion in Google Cloud Platform."
echo
echo "To verify complete cleanup, you can check:"
echo "  gcloud functions list --gen2 --region=${REGION}"
echo "  gsutil ls -p ${PROJECT_ID}"
echo "=================================================="

log_success "Cleanup completed successfully!"

# Final warning about billing
if check_interactive; then
    echo
    log_info "Remember to check your Google Cloud Console billing"
    log_info "to ensure all resources have been properly deleted"
    log_info "and no unexpected charges will occur."
fi