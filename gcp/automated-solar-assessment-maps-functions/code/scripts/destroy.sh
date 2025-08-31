#!/bin/bash

# Automated Solar Assessment with Solar API and Functions - Cleanup Script
# This script safely removes all infrastructure created by the deployment script
# including Cloud Functions, Cloud Storage buckets, and API keys

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "ERROR" "$1"
    echo -e "${RED}Cleanup failed. Check ${LOG_FILE} for details.${NC}"
    exit 1
}

# Success message function
success() {
    log "INFO" "$1"
    echo -e "${GREEN}✅ $1${NC}"
}

# Info message function
info() {
    log "INFO" "$1"
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Warning message function
warning() {
    log "WARN" "$1"
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    info "Validating cleanup prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        error_exit "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "@"; then
        error_exit "Not authenticated with Google Cloud. Please run: gcloud auth login"
    fi
    
    # Check if project is set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            error_exit "Google Cloud project not set. Please run: gcloud config set project YOUR_PROJECT_ID"
        fi
    fi
    
    success "Prerequisites validation completed"
}

# Set up environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # Use existing PROJECT_ID or get from gcloud config
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    fi
    
    # Set default region if not provided
    export REGION="${REGION:-us-central1}"
    
    # If resource names are not provided as environment variables, we'll try to discover them
    if [[ -z "${FUNCTION_NAME:-}" ]] || [[ -z "${INPUT_BUCKET:-}" ]] || [[ -z "${OUTPUT_BUCKET:-}" ]] || [[ -z "${API_KEY_NAME:-}" ]]; then
        warning "Resource names not provided as environment variables"
        info "Will attempt to discover solar assessment resources..."
        
        # Discover resources by pattern matching
        DISCOVERED_FUNCTIONS=$(gcloud functions list --filter="name~solar-processor" --format="value(name)" --region="${REGION}" 2>/dev/null || echo "")
        DISCOVERED_BUCKETS=$(gsutil ls -b | grep -E "(solar-input|solar-results)" || echo "")
        DISCOVERED_API_KEYS=$(gcloud services api-keys list --filter="displayName~solar-assessment" --format="value(displayName)" 2>/dev/null || echo "")
        
        info "Discovered resources:"
        echo "  Functions: ${DISCOVERED_FUNCTIONS:-None}"
        echo "  Buckets: ${DISCOVERED_BUCKETS:-None}"
        echo "  API Keys: ${DISCOVERED_API_KEYS:-None}"
    fi
    
    # Display configuration
    info "Cleanup configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        echo "  Function Name: ${FUNCTION_NAME}"
    fi
    if [[ -n "${INPUT_BUCKET:-}" ]]; then
        echo "  Input Bucket: gs://${INPUT_BUCKET}"
    fi
    if [[ -n "${OUTPUT_BUCKET:-}" ]]; then
        echo "  Output Bucket: gs://${OUTPUT_BUCKET}"
    fi
    if [[ -n "${API_KEY_NAME:-}" ]]; then
        echo "  API Key Name: ${API_KEY_NAME}"
    fi
    
    success "Environment setup completed"
}

# Confirm cleanup with user
confirm_cleanup() {
    echo
    echo "=========================================="
    echo "⚠️  RESOURCE CLEANUP WARNING"
    echo "=========================================="
    echo
    echo "This script will PERMANENTLY DELETE the following resources:"
    echo
    
    # List Cloud Functions to be deleted
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        echo "  🔧 Cloud Functions:"
        echo "     - ${FUNCTION_NAME}"
    elif [[ -n "${DISCOVERED_FUNCTIONS:-}" ]]; then
        echo "  🔧 Cloud Functions:"
        while IFS= read -r func; do
            echo "     - ${func}"
        done <<< "${DISCOVERED_FUNCTIONS}"
    fi
    
    # List Cloud Storage buckets to be deleted
    if [[ -n "${INPUT_BUCKET:-}" ]] && [[ -n "${OUTPUT_BUCKET:-}" ]]; then
        echo "  🗂️  Cloud Storage Buckets:"
        echo "     - gs://${INPUT_BUCKET} (including all files)"
        echo "     - gs://${OUTPUT_BUCKET} (including all files)"
    elif [[ -n "${DISCOVERED_BUCKETS:-}" ]]; then
        echo "  🗂️  Cloud Storage Buckets:"
        while IFS= read -r bucket; do
            echo "     - ${bucket} (including all files)"
        done <<< "${DISCOVERED_BUCKETS}"
    fi
    
    # List API keys to be deleted
    if [[ -n "${API_KEY_NAME:-}" ]]; then
        echo "  🔑 API Keys:"
        echo "     - ${API_KEY_NAME}"
    elif [[ -n "${DISCOVERED_API_KEYS:-}" ]]; then
        echo "  🔑 API Keys:"
        while IFS= read -r key; do
            echo "     - ${key}"
        done <<< "${DISCOVERED_API_KEYS}"
    fi
    
    echo
    warning "This action cannot be undone!"
    echo
    
    if [[ "${FORCE_CLEANUP:-false}" == "true" ]]; then
        warning "Force cleanup enabled, proceeding without confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    info "Proceeding with resource cleanup..."
}

# Delete Cloud Functions
delete_functions() {
    info "Deleting Cloud Functions..."
    
    local functions_to_delete=""
    
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        functions_to_delete="${FUNCTION_NAME}"
    elif [[ -n "${DISCOVERED_FUNCTIONS:-}" ]]; then
        functions_to_delete="${DISCOVERED_FUNCTIONS}"
    fi
    
    if [[ -z "${functions_to_delete}" ]]; then
        warning "No Cloud Functions found to delete"
        return 0
    fi
    
    while IFS= read -r func_name; do
        if [[ -n "${func_name}" ]]; then
            info "Deleting Cloud Function: ${func_name}"
            if gcloud functions delete "${func_name}" --region="${REGION}" --quiet 2>>"${LOG_FILE}"; then
                success "Deleted Cloud Function: ${func_name}"
            else
                warning "Failed to delete Cloud Function: ${func_name}"
            fi
        fi
    done <<< "${functions_to_delete}"
    
    success "Cloud Functions cleanup completed"
}

# Delete Cloud Storage buckets
delete_storage_buckets() {
    info "Deleting Cloud Storage buckets..."
    
    local buckets_to_delete=""
    
    if [[ -n "${INPUT_BUCKET:-}" ]] && [[ -n "${OUTPUT_BUCKET:-}" ]]; then
        buckets_to_delete="gs://${INPUT_BUCKET}
gs://${OUTPUT_BUCKET}"
    elif [[ -n "${DISCOVERED_BUCKETS:-}" ]]; then
        buckets_to_delete="${DISCOVERED_BUCKETS}"
    fi
    
    if [[ -z "${buckets_to_delete}" ]]; then
        warning "No Cloud Storage buckets found to delete"
        return 0
    fi
    
    while IFS= read -r bucket; do
        if [[ -n "${bucket}" ]]; then
            # Remove gs:// prefix if present
            bucket_name=$(echo "${bucket}" | sed 's|gs://||')
            
            info "Deleting bucket and all contents: gs://${bucket_name}"
            
            # Check if bucket exists
            if gsutil ls -b "gs://${bucket_name}" >/dev/null 2>&1; then
                # Delete all objects first, then the bucket
                if gsutil -m rm -r "gs://${bucket_name}/**" 2>>"${LOG_FILE}" || true; then
                    info "Deleted all objects in gs://${bucket_name}"
                fi
                
                if gsutil rb "gs://${bucket_name}" 2>>"${LOG_FILE}"; then
                    success "Deleted bucket: gs://${bucket_name}"
                else
                    warning "Failed to delete bucket: gs://${bucket_name}"
                fi
            else
                warning "Bucket not found: gs://${bucket_name}"
            fi
        fi
    done <<< "${buckets_to_delete}"
    
    success "Cloud Storage buckets cleanup completed"
}

# Delete API keys
delete_api_keys() {
    info "Deleting Google Maps Platform API keys..."
    
    local keys_to_delete=""
    
    if [[ -n "${API_KEY_NAME:-}" ]]; then
        keys_to_delete="${API_KEY_NAME}"
    elif [[ -n "${DISCOVERED_API_KEYS:-}" ]]; then
        keys_to_delete="${DISCOVERED_API_KEYS}"
    fi
    
    if [[ -z "${keys_to_delete}" ]]; then
        warning "No API keys found to delete"
        return 0
    fi
    
    while IFS= read -r key_name; do
        if [[ -n "${key_name}" ]]; then
            info "Deleting API key: ${key_name}"
            if gcloud services api-keys delete "${key_name}" --location=global --quiet 2>>"${LOG_FILE}"; then
                success "Deleted API key: ${key_name}"
            else
                warning "Failed to delete API key: ${key_name}"
            fi
        fi
    done <<< "${keys_to_delete}"
    
    success "API keys cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/../function-source"
        "${SCRIPT_DIR}/sample_properties.csv"
        "${SCRIPT_DIR}/solar_results.csv"
    )
    
    for file_path in "${files_to_remove[@]}"; do
        if [[ -e "${file_path}" ]]; then
            info "Removing: ${file_path}"
            if rm -rf "${file_path}" 2>>"${LOG_FILE}"; then
                success "Removed: ${file_path}"
            else
                warning "Failed to remove: ${file_path}"
            fi
        fi
    done
    
    success "Local files cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check if functions still exist
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
            warning "Cloud Function still exists: ${FUNCTION_NAME}"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if buckets still exist
    if [[ -n "${INPUT_BUCKET:-}" ]]; then
        if gsutil ls -b "gs://${INPUT_BUCKET}" >/dev/null 2>&1; then
            warning "Input bucket still exists: gs://${INPUT_BUCKET}"
            ((cleanup_issues++))
        fi
    fi
    
    if [[ -n "${OUTPUT_BUCKET:-}" ]]; then
        if gsutil ls -b "gs://${OUTPUT_BUCKET}" >/dev/null 2>&1; then
            warning "Output bucket still exists: gs://${OUTPUT_BUCKET}"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if API keys still exist
    if [[ -n "${API_KEY_NAME:-}" ]]; then
        if gcloud services api-keys list --filter="displayName:${API_KEY_NAME}" --format="value(name)" | grep -q "${API_KEY_NAME}"; then
            warning "API key still exists: ${API_KEY_NAME}"
            ((cleanup_issues++))
        fi
    fi
    
    if [[ ${cleanup_issues} -eq 0 ]]; then
        success "Cleanup verification completed - all resources removed"
    else
        warning "Cleanup verification found ${cleanup_issues} remaining resources"
        info "Some resources may take time to be fully deleted or may require manual removal"
    fi
}

# Display cleanup summary
display_summary() {
    echo
    echo "=========================================="
    echo "🧹 CLEANUP COMPLETED"
    echo "=========================================="
    echo
    echo "📋 Cleanup Summary:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Timestamp: $(date)"
    echo
    echo "✅ Completed cleanup tasks:"
    echo "  - Cloud Functions deleted"
    echo "  - Cloud Storage buckets deleted"
    echo "  - API keys deleted"
    echo "  - Local files cleaned up"
    echo
    echo "📝 Cleanup log: ${LOG_FILE}"
    echo
    info "Note: Some resources may take a few minutes to be fully removed from the Google Cloud Console"
    echo
    success "Solar assessment infrastructure cleanup completed successfully!"
}

# Main cleanup function
main() {
    echo "Starting automated solar assessment infrastructure cleanup..."
    echo "Log file: ${LOG_FILE}"
    echo
    
    # Initialize log file
    echo "Cleanup started at $(date)" > "${LOG_FILE}"
    
    # Execute cleanup steps
    validate_prerequisites
    setup_environment
    confirm_cleanup
    delete_functions
    delete_storage_buckets
    delete_api_keys
    cleanup_local_files
    verify_cleanup
    display_summary
    
    success "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error_exit "Cleanup interrupted by user"' INT TERM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_CLEANUP=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --force    Skip confirmation prompts and force cleanup"
            echo "  --help     Show this help message"
            echo
            echo "Environment Variables:"
            echo "  PROJECT_ID     Google Cloud project ID"
            echo "  REGION         Google Cloud region (default: us-central1)"
            echo "  FUNCTION_NAME  Cloud Function name to delete"
            echo "  INPUT_BUCKET   Input bucket name to delete"
            echo "  OUTPUT_BUCKET  Output bucket name to delete"
            echo "  API_KEY_NAME   API key name to delete"
            echo
            exit 0
            ;;
        *)
            warning "Unknown option: $1"
            shift
            ;;
    esac
done

# Execute main function
main "$@"