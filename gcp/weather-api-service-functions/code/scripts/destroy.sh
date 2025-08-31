#!/bin/bash

# destroy.sh - Clean up Weather API Service with Cloud Functions
# This script removes all resources created by the Weather API Service deployment
# Based on recipe: Weather API Service with Cloud Functions

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

# Global variables for cleanup tracking
RESOURCES_FOUND=0
RESOURCES_DELETED=0
ERRORS_ENCOUNTERED=0

# Configuration validation
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_error "Please install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please install Google Cloud SDK"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &>/dev/null; then
        log_error "No active Google Cloud authentication found"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Load deployment configuration
load_deployment_config() {
    log_info "Loading deployment configuration..."
    
    # Try to load from deployment file first
    local deployment_file="./weather-api-deployment.json"
    if [[ -f "${deployment_file}" ]]; then
        log_info "Found deployment configuration file: ${deployment_file}"
        
        # Extract values from deployment file using jq if available
        if command -v jq &> /dev/null; then
            export PROJECT_ID=$(jq -r '.project_id // empty' "${deployment_file}")
            export REGION=$(jq -r '.region // empty' "${deployment_file}")
            export FUNCTION_NAME=$(jq -r '.function_name // empty' "${deployment_file}")
            export BUCKET_NAME=$(jq -r '.bucket_name // empty' "${deployment_file}")
            log_success "Configuration loaded from deployment file"
        else
            log_warning "jq not available. Please set environment variables manually."
        fi
    else
        log_warning "No deployment configuration file found: ${deployment_file}"
        log_info "Will use environment variables or defaults"
    fi
    
    # Set defaults if not provided
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
    export REGION="${REGION:-us-central1}"
    export FUNCTION_NAME="${FUNCTION_NAME:-weather-api}"
    
    # If BUCKET_NAME is not set, we'll try to find it later
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_warning "Bucket name not specified. Will attempt to find weather-cache-* buckets."
    fi
    
    # Validate required settings
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "PROJECT_ID is required. Please set it as an environment variable or ensure deployment file exists."
        exit 1
    fi
    
    # Set gcloud configuration
    gcloud config set project "${PROJECT_ID}" &>/dev/null
    gcloud config set compute/region "${REGION}" &>/dev/null
    gcloud config set functions/region "${REGION}" &>/dev/null
    
    log_info "Configuration summary:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Function Name: ${FUNCTION_NAME}"
    log_info "  Bucket Name: ${BUCKET_NAME:-<will auto-detect>}"
}

# Interactive confirmation
confirm_deletion() {
    log_warning "========================================"
    log_warning "DESTRUCTIVE OPERATION WARNING"
    log_warning "========================================"
    log_warning "This script will permanently delete the following resources:"
    log_warning "  - Cloud Function: ${FUNCTION_NAME}"
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log_warning "  - Storage Bucket: ${BUCKET_NAME} (and all contents)"
    else
        log_warning "  - Storage Buckets: weather-cache-* (and all contents)"
    fi
    log_warning "  - IAM Policy Bindings: storage access for function service account"
    log_warning "  - Local Files: deployment configuration"
    log_warning ""
    log_warning "Project: ${PROJECT_ID}"
    log_warning "Region: ${REGION}"
    log_warning ""
    
    # Skip confirmation in non-interactive mode
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        log_info "Force delete enabled. Skipping confirmation."
        return 0
    fi
    
    # Interactive confirmation
    echo -n "Do you want to continue? (type 'yes' to confirm): "
    read -r confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    log_info "Deletion confirmed. Proceeding with cleanup..."
}

# Find weather cache buckets if not specified
find_weather_buckets() {
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        return 0
    fi
    
    log_info "Searching for weather cache buckets in project ${PROJECT_ID}..."
    
    local buckets
    buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "gs://weather-cache-" | sed 's|gs://||' | sed 's|/||' || echo "")
    
    if [[ -n "${buckets}" ]]; then
        log_info "Found weather cache buckets:"
        echo "${buckets}" | while read -r bucket; do
            log_info "  - ${bucket}"
        done
        export WEATHER_BUCKETS="${buckets}"
    else
        log_warning "No weather-cache-* buckets found in project ${PROJECT_ID}"
        export WEATHER_BUCKETS=""
    fi
}

# Remove Cloud Function
remove_cloud_function() {
    log_info "Removing Cloud Function: ${FUNCTION_NAME}..."
    
    # Check if function exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        RESOURCES_FOUND=$((RESOURCES_FOUND + 1))
        log_info "Found Cloud Function: ${FUNCTION_NAME}"
        
        # Delete the function
        if gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --quiet; then
            log_success "Cloud Function deleted: ${FUNCTION_NAME}"
            RESOURCES_DELETED=$((RESOURCES_DELETED + 1))
        else
            log_error "Failed to delete Cloud Function: ${FUNCTION_NAME}"
            ERRORS_ENCOUNTERED=$((ERRORS_ENCOUNTERED + 1))
        fi
    else
        log_warning "Cloud Function not found: ${FUNCTION_NAME}"
    fi
}

# Remove storage buckets and contents
remove_storage_buckets() {
    log_info "Removing Cloud Storage buckets..."
    
    # Handle specific bucket
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            RESOURCES_FOUND=$((RESOURCES_FOUND + 1))
            log_info "Found storage bucket: ${BUCKET_NAME}"
            
            # Show bucket contents before deletion
            local object_count
            object_count=$(gsutil ls "gs://${BUCKET_NAME}/**" 2>/dev/null | wc -l || echo "0")
            if [[ "${object_count}" -gt 0 ]]; then
                log_info "Bucket contains ${object_count} objects"
            fi
            
            # Delete bucket and all contents
            if gsutil -m rm -r "gs://${BUCKET_NAME}"; then
                log_success "Storage bucket deleted: ${BUCKET_NAME}"
                RESOURCES_DELETED=$((RESOURCES_DELETED + 1))
            else
                log_error "Failed to delete storage bucket: ${BUCKET_NAME}"
                ERRORS_ENCOUNTERED=$((ERRORS_ENCOUNTERED + 1))
            fi
        else
            log_warning "Storage bucket not found: ${BUCKET_NAME}"
        fi
    fi
    
    # Handle auto-detected buckets
    if [[ -n "${WEATHER_BUCKETS:-}" ]]; then
        echo "${WEATHER_BUCKETS}" | while read -r bucket; do
            if [[ -n "${bucket}" ]]; then
                RESOURCES_FOUND=$((RESOURCES_FOUND + 1))
                log_info "Found weather cache bucket: ${bucket}"
                
                # Show bucket contents
                local object_count
                object_count=$(gsutil ls "gs://${bucket}/**" 2>/dev/null | wc -l || echo "0")
                if [[ "${object_count}" -gt 0 ]]; then
                    log_info "Bucket contains ${object_count} objects"
                fi
                
                # Delete bucket and all contents
                if gsutil -m rm -r "gs://${bucket}"; then
                    log_success "Storage bucket deleted: ${bucket}"
                    RESOURCES_DELETED=$((RESOURCES_DELETED + 1))
                else
                    log_error "Failed to delete storage bucket: ${bucket}"
                    ERRORS_ENCOUNTERED=$((ERRORS_ENCOUNTERED + 1))
                fi
            fi
        done
    fi
}

# Remove IAM policy bindings
remove_iam_policies() {
    log_info "Removing IAM policy bindings..."
    
    # Get the default compute service account
    local compute_sa="${PROJECT_ID}-compute@developer.gserviceaccount.com"
    
    # Get current IAM policy
    local policy_file="/tmp/iam-policy-$$.json"
    if gcloud projects get-iam-policy "${PROJECT_ID}" --format=json > "${policy_file}"; then
        
        # Check if there are any storage.objectAdmin bindings for the service account
        if grep -q "roles/storage.objectAdmin" "${policy_file}" && grep -q "${compute_sa}" "${policy_file}"; then
            log_info "Found IAM policy bindings for ${compute_sa}"
            
            # Attempt to remove storage admin binding
            # Note: This removes ALL storage.objectAdmin bindings for the service account
            # In production, you might want to be more selective
            if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${compute_sa}" \
                --role="roles/storage.objectAdmin" \
                --quiet 2>/dev/null; then
                log_success "Removed storage.objectAdmin role binding for ${compute_sa}"
                RESOURCES_DELETED=$((RESOURCES_DELETED + 1))
            else
                log_warning "Could not remove storage.objectAdmin role binding (may not exist or have conditions)"
            fi
        else
            log_info "No storage.objectAdmin policy bindings found for ${compute_sa}"
        fi
    else
        log_warning "Could not retrieve IAM policy for project ${PROJECT_ID}"
    fi
    
    # Clean up temporary file
    rm -f "${policy_file}"
}

# Clean up local files
clean_local_files() {
    log_info "Cleaning up local files..."
    
    local files_cleaned=0
    
    # Remove deployment configuration file
    local deployment_file="./weather-api-deployment.json"
    if [[ -f "${deployment_file}" ]]; then
        if rm "${deployment_file}"; then
            log_success "Removed deployment configuration: ${deployment_file}"
            files_cleaned=$((files_cleaned + 1))
        else
            log_error "Failed to remove: ${deployment_file}"
            ERRORS_ENCOUNTERED=$((ERRORS_ENCOUNTERED + 1))
        fi
    fi
    
    # Remove any temporary lifecycle files that might exist
    if [[ -f "/tmp/lifecycle.json" ]]; then
        rm -f "/tmp/lifecycle.json"
        log_info "Removed temporary lifecycle policy file"
        files_cleaned=$((files_cleaned + 1))
    fi
    
    # Remove any temporary function directories
    local temp_dirs
    temp_dirs=$(find /tmp -name "weather-function-*" -type d 2>/dev/null || echo "")
    if [[ -n "${temp_dirs}" ]]; then
        echo "${temp_dirs}" | while read -r temp_dir; do
            if [[ -d "${temp_dir}" ]]; then
                rm -rf "${temp_dir}"
                log_info "Removed temporary function directory: ${temp_dir}"
                files_cleaned=$((files_cleaned + 1))
            fi
        done
    fi
    
    if [[ ${files_cleaned} -eq 0 ]]; then
        log_info "No local files found to clean up"
    else
        log_success "Cleaned up ${files_cleaned} local files"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local verification_errors=0
    
    # Check if Cloud Function still exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        log_error "Cloud Function still exists: ${FUNCTION_NAME}"
        verification_errors=$((verification_errors + 1))
    else
        log_success "Verified: Cloud Function removed"
    fi
    
    # Check if buckets still exist
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            log_error "Storage bucket still exists: ${BUCKET_NAME}"
            verification_errors=$((verification_errors + 1))
        else
            log_success "Verified: Storage bucket removed"
        fi
    fi
    
    # Check for any remaining weather cache buckets
    local remaining_buckets
    remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "gs://weather-cache-" | wc -l || echo "0")
    if [[ "${remaining_buckets}" -gt 0 ]]; then
        log_warning "Found ${remaining_buckets} remaining weather-cache-* buckets"
    else
        log_success "Verified: No weather cache buckets remaining"
    fi
    
    if [[ ${verification_errors} -eq 0 ]]; then
        log_success "Cleanup verification passed"
    else
        log_error "Cleanup verification found ${verification_errors} issues"
        ERRORS_ENCOUNTERED=$((ERRORS_ENCOUNTERED + verification_errors))
    fi
}

# Generate cleanup summary
generate_summary() {
    log_info "========================================"
    log_info "CLEANUP SUMMARY"
    log_info "========================================"
    log_info "Resources found: ${RESOURCES_FOUND}"
    log_info "Resources deleted: ${RESOURCES_DELETED}"
    log_info "Errors encountered: ${ERRORS_ENCOUNTERED}"
    log_info ""
    
    if [[ ${ERRORS_ENCOUNTERED} -eq 0 ]]; then
        log_success "Weather API Service cleanup completed successfully!"
        log_info ""
        log_info "The following resources have been removed:"
        log_info "  ✅ Cloud Function: ${FUNCTION_NAME}"
        if [[ -n "${BUCKET_NAME:-}" ]]; then
            log_info "  ✅ Storage Bucket: ${BUCKET_NAME}"
        else
            log_info "  ✅ Storage Buckets: weather-cache-*"
        fi
        log_info "  ✅ IAM Policy Bindings: storage access permissions"
        log_info "  ✅ Local Files: deployment configuration"
        log_info ""
        log_info "Your Google Cloud project is now clean of Weather API Service resources."
    else
        log_error "Cleanup completed with ${ERRORS_ENCOUNTERED} errors"
        log_warning "Some resources may still exist. Please review the errors above."
        log_warning "You may need to manually clean up remaining resources."
        exit 1
    fi
}

# Show help information
show_help() {
    echo "Weather API Service Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --force           Force deletion without interactive confirmation"
    echo "  -p, --project PROJECT Set the Google Cloud project ID"
    echo "  -r, --region REGION   Set the deployment region (default: us-central1)"
    echo "  -n, --function NAME   Set the function name (default: weather-api)"
    echo "  -b, --bucket BUCKET   Set the specific bucket name to delete"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID           Google Cloud project ID"
    echo "  REGION              Deployment region"
    echo "  FUNCTION_NAME       Cloud Function name"
    echo "  BUCKET_NAME         Storage bucket name"
    echo "  FORCE_DELETE        Set to 'true' to skip confirmation"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup using defaults"
    echo "  $0 --force                           # Non-interactive cleanup"
    echo "  $0 -p my-project -f                  # Force cleanup for specific project"
    echo "  $0 -b weather-cache-abc123           # Clean up specific bucket"
    echo ""
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                export FORCE_DELETE="true"
                shift
                ;;
            -p|--project)
                export PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                export REGION="$2"
                shift 2
                ;;
            -n|--function)
                export FUNCTION_NAME="$2"
                shift 2
                ;;
            -b|--bucket)
                export BUCKET_NAME="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main execution
main() {
    log_info "Starting Weather API Service cleanup..."
    log_info "========================================"
    
    parse_arguments "$@"
    validate_prerequisites
    load_deployment_config
    find_weather_buckets
    confirm_deletion
    
    log_info "Beginning resource cleanup..."
    remove_cloud_function
    remove_storage_buckets
    remove_iam_policies
    clean_local_files
    verify_cleanup
    generate_summary
}

# Run main function with all arguments
main "$@"