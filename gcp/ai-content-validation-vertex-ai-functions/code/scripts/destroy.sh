#!/bin/bash

# AI Content Validation with Vertex AI and Functions - Cleanup Script
# This script removes all infrastructure resources created for the content validation solution
# to avoid ongoing charges and clean up the environment

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi
    
    success "Prerequisites check completed"
}

# Discover existing resources
discover_resources() {
    info "Discovering existing resources..."
    
    # Get current project
    export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "${PROJECT_ID}" ]]; then
        error_exit "No active project set. Run 'gcloud config set project PROJECT_ID' first."
    fi
    
    # Get current region
    export REGION=$(gcloud config get-value compute/region 2>/dev/null)
    if [[ -z "${REGION}" ]]; then
        export REGION="us-central1"
        warning "No region set, using default: ${REGION}"
    fi
    
    info "Current configuration:"
    info "  Project ID: ${PROJECT_ID}"
    info "  Region: ${REGION}"
    
    # Look for content validation buckets
    info "Searching for content validation buckets..."
    local content_buckets=$(gsutil ls -p "${PROJECT_ID}" | grep -E "content-input-[a-f0-9]{6}" || true)
    local results_buckets=$(gsutil ls -p "${PROJECT_ID}" | grep -E "validation-results-[a-f0-9]{6}" || true)
    
    if [[ -n "${content_buckets}" ]]; then
        export CONTENT_BUCKETS="${content_buckets}"
        info "Found content buckets: ${CONTENT_BUCKETS}"
    else
        warning "No content validation buckets found"
        export CONTENT_BUCKETS=""
    fi
    
    if [[ -n "${results_buckets}" ]]; then
        export RESULTS_BUCKETS="${results_buckets}"
        info "Found results buckets: ${RESULTS_BUCKETS}"
    else
        warning "No results buckets found"
        export RESULTS_BUCKETS=""
    fi
    
    # Look for content validator functions
    info "Searching for content validator functions..."
    local functions=$(gcloud functions list --regions="${REGION}" --filter="name:content-validator" --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${functions}" ]]; then
        export VALIDATOR_FUNCTIONS="${functions}"
        info "Found validator functions: ${VALIDATOR_FUNCTIONS}"
    else
        warning "No content validator functions found"
        export VALIDATOR_FUNCTIONS=""
    fi
}

# Confirm destruction
confirm_destruction() {
    echo
    echo -e "${RED}🗑️  DESTRUCTIVE OPERATION WARNING${NC}"
    echo
    echo "This will permanently delete the following resources:"
    echo
    
    if [[ -n "${VALIDATOR_FUNCTIONS}" ]]; then
        echo "Cloud Functions:"
        echo "${VALIDATOR_FUNCTIONS}" | while IFS= read -r func; do
            echo "  - ${func}"
        done
        echo
    fi
    
    if [[ -n "${CONTENT_BUCKETS}" ]]; then
        echo "Content Storage Buckets (and all contents):"
        echo "${CONTENT_BUCKETS}" | while IFS= read -r bucket; do
            echo "  - ${bucket}"
        done
        echo
    fi
    
    if [[ -n "${RESULTS_BUCKETS}" ]]; then
        echo "Results Storage Buckets (and all contents):"
        echo "${RESULTS_BUCKETS}" | while IFS= read -r bucket; do
            echo "  - ${bucket}"
        done
        echo
    fi
    
    # Local directories
    local function_dir="${SCRIPT_DIR}/../function"
    local test_dir="${SCRIPT_DIR}/../test-content"
    
    if [[ -d "${function_dir}" ]] || [[ -d "${test_dir}" ]]; then
        echo "Local directories:"
        [[ -d "${function_dir}" ]] && echo "  - ${function_dir}"
        [[ -d "${test_dir}" ]] && echo "  - ${test_dir}"
        echo
    fi
    
    if [[ -z "${VALIDATOR_FUNCTIONS}" && -z "${CONTENT_BUCKETS}" && -z "${RESULTS_BUCKETS}" ]]; then
        info "No cloud resources found to delete."
        return 0
    fi
    
    echo -e "${RED}This action cannot be undone!${NC}"
    echo
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    echo
    
    if [[ "${REPLY}" != "yes" ]]; then
        info "Destruction cancelled by user."
        exit 0
    fi
}

# Delete Cloud Functions
delete_functions() {
    if [[ -z "${VALIDATOR_FUNCTIONS}" ]]; then
        info "No Cloud Functions to delete"
        return 0
    fi
    
    info "Deleting Cloud Functions..."
    
    echo "${VALIDATOR_FUNCTIONS}" | while IFS= read -r func; do
        if [[ -n "${func}" ]]; then
            info "Deleting function: ${func}"
            if gcloud functions delete "${func}" --region="${REGION}" --quiet 2>/dev/null; then
                success "Deleted function: ${func}"
            else
                warning "Failed to delete function: ${func} (may already be deleted)"
            fi
        fi
    done
    
    # Wait for function deletion to complete
    info "Waiting for function deletion to complete..."
    sleep 10
    
    success "Cloud Functions deletion completed"
}

# Delete Storage Buckets
delete_storage_buckets() {
    info "Deleting Cloud Storage buckets..."
    
    # Delete content buckets
    if [[ -n "${CONTENT_BUCKETS}" ]]; then
        echo "${CONTENT_BUCKETS}" | while IFS= read -r bucket; do
            if [[ -n "${bucket}" ]]; then
                local bucket_name=$(echo "${bucket}" | sed 's|gs://||' | sed 's|/||')
                info "Deleting content bucket: ${bucket_name}"
                
                # Delete all objects first
                if gsutil -m rm -r "${bucket}**" 2>/dev/null; then
                    info "Deleted all objects from ${bucket_name}"
                else
                    warning "No objects to delete in ${bucket_name} or already empty"
                fi
                
                # Delete bucket
                if gsutil rb "${bucket}" 2>/dev/null; then
                    success "Deleted bucket: ${bucket_name}"
                else
                    warning "Failed to delete bucket: ${bucket_name} (may already be deleted)"
                fi
            fi
        done
    fi
    
    # Delete results buckets
    if [[ -n "${RESULTS_BUCKETS}" ]]; then
        echo "${RESULTS_BUCKETS}" | while IFS= read -r bucket; do
            if [[ -n "${bucket}" ]]; then
                local bucket_name=$(echo "${bucket}" | sed 's|gs://||' | sed 's|/||')
                info "Deleting results bucket: ${bucket_name}"
                
                # Delete all objects first
                if gsutil -m rm -r "${bucket}**" 2>/dev/null; then
                    info "Deleted all objects from ${bucket_name}"
                else
                    warning "No objects to delete in ${bucket_name} or already empty"
                fi
                
                # Delete bucket
                if gsutil rb "${bucket}" 2>/dev/null; then
                    success "Deleted bucket: ${bucket_name}"
                else
                    warning "Failed to delete bucket: ${bucket_name} (may already be deleted)"
                fi
            fi
        done
    fi
    
    if [[ -z "${CONTENT_BUCKETS}" && -z "${RESULTS_BUCKETS}" ]]; then
        info "No storage buckets to delete"
    else
        success "Storage buckets deletion completed"
    fi
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files and directories..."
    
    local function_dir="${SCRIPT_DIR}/../function"
    local test_dir="${SCRIPT_DIR}/../test-content"
    
    # Remove function directory
    if [[ -d "${function_dir}" ]]; then
        info "Removing function directory: ${function_dir}"
        rm -rf "${function_dir}"
        success "Removed function directory"
    fi
    
    # Remove test content directory
    if [[ -d "${test_dir}" ]]; then
        info "Removing test content directory: ${test_dir}"
        rm -rf "${test_dir}"
        success "Removed test content directory"
    fi
    
    # Remove any downloaded results files
    local script_parent="${SCRIPT_DIR}/.."
    if find "${script_parent}" -name "*_results.json" -type f | grep -q .; then
        info "Removing downloaded result files..."
        find "${script_parent}" -name "*_results.json" -type f -delete
        success "Removed result files"
    fi
    
    success "Local cleanup completed"
}

# Disable APIs (optional)
disable_apis() {
    info "Checking for API usage before disabling..."
    
    # Check if there are other resources using these APIs
    local apis_to_check=(
        "cloudfunctions.googleapis.com"
        "aiplatform.googleapis.com"
        "eventarc.googleapis.com"
    )
    
    local can_disable_apis=true
    
    # Check for other Cloud Functions
    local other_functions=$(gcloud functions list --format="value(name)" 2>/dev/null | wc -l)
    if [[ "${other_functions}" -gt 0 ]]; then
        warning "Other Cloud Functions exist, keeping Cloud Functions API enabled"
        can_disable_apis=false
    fi
    
    # Check for other Vertex AI resources
    local vertex_endpoints=$(gcloud ai endpoints list --region="${REGION}" --format="value(name)" 2>/dev/null | wc -l)
    if [[ "${vertex_endpoints}" -gt 0 ]]; then
        warning "Other Vertex AI resources exist, keeping AI Platform API enabled"
        can_disable_apis=false
    fi
    
    if [[ "${can_disable_apis}" == "true" ]]; then
        read -p "Do you want to disable APIs? This may affect other services. (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            info "Disabling APIs..."
            for api in "${apis_to_check[@]}"; do
                info "Disabling ${api}..."
                if gcloud services disable "${api}" --quiet 2>/dev/null; then
                    success "Disabled ${api}"
                else
                    warning "Failed to disable ${api} (may have dependent services)"
                fi
            done
        else
            info "Skipping API disabling"
        fi
    else
        info "Skipping API disabling due to existing resources"
    fi
}

# Verify cleanup
verify_cleanup() {
    info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check for remaining functions
    local remaining_functions=$(gcloud functions list --regions="${REGION}" --filter="name:content-validator" --format="value(name)" 2>/dev/null || true)
    if [[ -n "${remaining_functions}" ]]; then
        warning "Some functions still exist: ${remaining_functions}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check for remaining buckets
    local remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "(content-input|validation-results)-[a-f0-9]{6}" || true)
    if [[ -n "${remaining_buckets}" ]]; then
        warning "Some buckets still exist: ${remaining_buckets}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [[ "${cleanup_issues}" -eq 0 ]]; then
        success "Cleanup verification passed - all resources removed"
    else
        warning "Cleanup verification found ${cleanup_issues} issues - manual review may be needed"
    fi
}

# Print cleanup summary
print_summary() {
    echo
    echo -e "${GREEN}🧹 Cleanup completed!${NC}"
    echo
    echo "Resources removed:"
    echo "  ✅ Cloud Functions"
    echo "  ✅ Cloud Storage buckets and contents"
    echo "  ✅ Local function code and test files"
    echo
    echo "Next steps:"
    echo "  - Review your Google Cloud Console to confirm all resources are deleted"
    echo "  - Check billing to ensure no ongoing charges"
    echo "  - Consider disabling unused APIs if no other services need them"
    echo
    echo "To redeploy the solution:"
    echo "  ./deploy.sh"
    echo
}

# Main cleanup function
main() {
    echo -e "${RED}🗑️  Starting AI Content Validation Cleanup${NC}"
    echo "Log file: ${LOG_FILE}"
    echo
    
    log "Starting cleanup at $(date)"
    
    check_prerequisites
    discover_resources
    confirm_destruction
    delete_functions
    delete_storage_buckets
    cleanup_local_files
    disable_apis
    verify_cleanup
    print_summary
    
    log "Cleanup completed successfully at $(date)"
}

# Run main function
main "$@"