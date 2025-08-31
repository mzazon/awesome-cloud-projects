#!/bin/bash

# Educational Content Generation with Gemini and Text-to-Speech - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/edu-content-destroy-$(date +%Y%m%d_%H%M%S).log"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO: $*"
}

log_warn() {
    log "WARNING: $*"
}

log_error() {
    log "ERROR: $*"
}

log_success() {
    log "SUCCESS: $*"
}

# Error handling for cleanup
cleanup_error() {
    local exit_code=$?
    log_error "Cleanup script encountered an error (exit code: ${exit_code})"
    log_error "Some resources may not have been deleted. Check manually in the Google Cloud Console."
    log_error "Log file: ${LOG_FILE}"
    exit ${exit_code}
}

trap cleanup_error ERR

# Confirmation prompt
confirm_destruction() {
    log_warn "This script will DELETE the following resources:"
    log_warn "  • Cloud Function: ${FUNCTION_NAME:-content-generator-*}"
    log_warn "  • Storage Bucket: ${BUCKET_NAME:-edu-audio-content-*} (including all files)"
    log_warn "  • Firestore documents in collection: ${FIRESTORE_COLLECTION:-educational_content}"
    log_warn "  • Local function code and temporary files"
    
    if [[ "${FORCE_DESTROY:-false}" != "true" ]]; then
        echo
        read -p "Are you sure you want to proceed? (yes/no): " -r
        if [[ ! "${REPLY}" =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Validation functions
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud SDK (gcloud) is not installed"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_error "Run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

setup_environment() {
    log_info "Setting up environment variables for cleanup..."
    
    # Try to load environment variables from deployment
    if [[ -z "${PROJECT_ID:-}" ]]; then
        # Try to get from gcloud config
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "PROJECT_ID is not set and cannot be determined from gcloud config"
            log_error "Set it with: export PROJECT_ID=your-project-id"
            exit 1
        fi
    fi
    
    # Set defaults for other variables if not provided
    export PROJECT_ID="${PROJECT_ID}"
    export REGION="${REGION:-us-central1}"
    export FUNCTION_NAME="${FUNCTION_NAME:-}"
    export BUCKET_NAME="${BUCKET_NAME:-}"
    export FIRESTORE_COLLECTION="${FIRESTORE_COLLECTION:-educational_content}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" &> /dev/null
    gcloud config set compute/region "${REGION}" &> /dev/null
    gcloud config set functions/region "${REGION}" &> /dev/null
    
    log_info "Cleanup environment configured for project: ${PROJECT_ID}"
}

# Resource discovery functions
discover_resources() {
    log_info "Discovering resources to clean up..."
    
    # Discover Cloud Functions with the pattern
    if [[ -z "${FUNCTION_NAME}" ]]; then
        log_info "Searching for Cloud Functions with pattern 'content-generator-*'..."
        local functions
        functions=$(gcloud functions list --filter="name:content-generator-" \
            --format="value(name)" --region="${REGION}" 2>/dev/null || echo "")
        
        if [[ -n "${functions}" ]]; then
            log_info "Found Cloud Functions:"
            echo "${functions}" | while read -r func; do
                log_info "  • ${func}"
            done
            FUNCTION_NAME=$(echo "${functions}" | head -1)
        else
            log_warn "No Cloud Functions found with pattern 'content-generator-*'"
        fi
    fi
    
    # Discover Storage Buckets with the pattern
    if [[ -z "${BUCKET_NAME}" ]]; then
        log_info "Searching for Storage Buckets with pattern 'edu-audio-content-*'..."
        local buckets
        buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | \
            grep "gs://edu-audio-content-" | sed 's|gs://||' | sed 's|/||' || echo "")
        
        if [[ -n "${buckets}" ]]; then
            log_info "Found Storage Buckets:"
            echo "${buckets}" | while read -r bucket; do
                log_info "  • ${bucket}"
            done
            BUCKET_NAME=$(echo "${buckets}" | head -1)
        else
            log_warn "No Storage Buckets found with pattern 'edu-audio-content-*'"
        fi
    fi
}

# Cleanup functions
delete_cloud_function() {
    if [[ -z "${FUNCTION_NAME}" ]]; then
        log_warn "No Cloud Function specified for deletion"
        return 0
    fi
    
    log_info "Deleting Cloud Function: ${FUNCTION_NAME}"
    
    # Check if function exists
    if ! gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
        log_warn "Cloud Function '${FUNCTION_NAME}' does not exist or already deleted"
        return 0
    fi
    
    # Delete the function
    if gcloud functions delete "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --quiet &> /dev/null; then
        log_success "Cloud Function deleted: ${FUNCTION_NAME}"
    else
        log_error "Failed to delete Cloud Function: ${FUNCTION_NAME}"
        return 1
    fi
}

delete_storage_bucket() {
    if [[ -z "${BUCKET_NAME}" ]]; then
        log_warn "No Storage Bucket specified for deletion"
        return 0
    fi
    
    log_info "Deleting Storage Bucket and all contents: ${BUCKET_NAME}"
    
    # Check if bucket exists
    if ! gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        log_warn "Storage Bucket 'gs://${BUCKET_NAME}' does not exist or already deleted"
        return 0
    fi
    
    # Delete bucket and all contents
    if gsutil -m rm -r "gs://${BUCKET_NAME}" &> /dev/null; then
        log_success "Storage Bucket deleted: ${BUCKET_NAME}"
    else
        log_error "Failed to delete Storage Bucket: ${BUCKET_NAME}"
        return 1
    fi
}

cleanup_firestore_data() {
    log_info "Cleaning up Firestore data in collection: ${FIRESTORE_COLLECTION}"
    
    # Note: Firestore deletion requires individual document deletion
    # This is a simplified approach - in production, consider using a more robust method
    log_warn "Firestore documents must be manually deleted from the collection '${FIRESTORE_COLLECTION}'"
    log_warn "Use the Google Cloud Console or a custom script to delete documents:"
    log_warn "  1. Go to https://console.cloud.google.com/firestore/data"
    log_warn "  2. Navigate to the '${FIRESTORE_COLLECTION}' collection"
    log_warn "  3. Delete documents individually or use bulk operations"
    
    # Alternative: Provide a simple deletion script suggestion
    cat > "${SCRIPT_DIR}/../cleanup_firestore.py" << EOF
#!/usr/bin/env python3
"""
Simple script to delete all documents in the educational_content collection.
Install dependencies: pip install google-cloud-firestore
Run: python3 cleanup_firestore.py
"""

from google.cloud import firestore

def delete_collection(collection_name, batch_size=100):
    db = firestore.Client()
    coll_ref = db.collection(collection_name)
    
    docs = coll_ref.limit(batch_size).stream()
    deleted = 0
    
    for doc in docs:
        print(f'Deleting doc {doc.id}')
        doc.reference.delete()
        deleted += 1
    
    if deleted >= batch_size:
        return delete_collection(collection_name, batch_size)
    
    return deleted

if __name__ == '__main__':
    total_deleted = delete_collection('${FIRESTORE_COLLECTION}')
    print(f'Total documents deleted: {total_deleted}')
EOF
    
    chmod +x "${SCRIPT_DIR}/../cleanup_firestore.py"
    log_info "Created Firestore cleanup script: ${SCRIPT_DIR}/../cleanup_firestore.py"
}

cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove function directory
    local function_dir="${SCRIPT_DIR}/../function"
    if [[ -d "${function_dir}" ]]; then
        rm -rf "${function_dir}"
        log_success "Removed function directory: ${function_dir}"
    fi
    
    # Remove function URL file
    local url_file="${SCRIPT_DIR}/../function_url.txt"
    if [[ -f "${url_file}" ]]; then
        rm -f "${url_file}"
        log_success "Removed function URL file: ${url_file}"
    fi
    
    # Remove any generated files
    local files_to_remove=(
        "${SCRIPT_DIR}/../sample_request.json"
        "${SCRIPT_DIR}/../advanced_request.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_info "Removed file: ${file}"
        fi
    done
}

# Verification functions
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local cleanup_success=true
    
    # Verify Cloud Function deletion
    if [[ -n "${FUNCTION_NAME}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
            log_error "Cloud Function still exists: ${FUNCTION_NAME}"
            cleanup_success=false
        else
            log_success "Cloud Function cleanup verified: ${FUNCTION_NAME}"
        fi
    fi
    
    # Verify Storage Bucket deletion
    if [[ -n "${BUCKET_NAME}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
            log_error "Storage Bucket still exists: ${BUCKET_NAME}"
            cleanup_success=false
        else
            log_success "Storage Bucket cleanup verified: ${BUCKET_NAME}"
        fi
    fi
    
    # Check for any remaining resources
    log_info "Checking for any remaining resources..."
    
    local remaining_functions
    remaining_functions=$(gcloud functions list --filter="name:content-generator-" \
        --format="value(name)" --region="${REGION}" 2>/dev/null || echo "")
    
    if [[ -n "${remaining_functions}" ]]; then
        log_warn "Found remaining Cloud Functions:"
        echo "${remaining_functions}" | while read -r func; do
            log_warn "  • ${func}"
        done
        cleanup_success=false
    fi
    
    local remaining_buckets
    remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | \
        grep "gs://edu-audio-content-" || echo "")
    
    if [[ -n "${remaining_buckets}" ]]; then
        log_warn "Found remaining Storage Buckets:"
        echo "${remaining_buckets}" | while read -r bucket; do
            log_warn "  • ${bucket}"
        done
        cleanup_success=false
    fi
    
    if [[ "${cleanup_success}" == "true" ]]; then
        log_success "Resource cleanup verification completed successfully"
    else
        log_warn "Some resources may still exist. Check manually in Google Cloud Console."
    fi
}

# Cost impact warning
show_cost_impact() {
    log_info "Cost impact of cleanup:"
    log_info "  • Cloud Functions: Billing stops immediately after deletion"
    log_info "  • Storage Buckets: No charges after deletion (data permanently lost)"
    log_info "  • Firestore: Minimal ongoing costs if documents remain"
    log_info "  • API Usage: Past usage already billed, no future charges"
    log_info "  Note: Some log data in Cloud Logging may remain and incur minimal charges"
}

# Main cleanup flow
main() {
    log_info "Starting Educational Content Generation cleanup..."
    log_info "Log file: ${LOG_FILE}"
    
    # Prerequisites and validation
    check_prerequisites
    setup_environment
    
    # Resource discovery
    discover_resources
    
    # Confirmation
    confirm_destruction
    
    # Cleanup operations
    log_info "Beginning resource cleanup..."
    
    # Track cleanup results
    local cleanup_errors=0
    
    # Delete resources in reverse order of creation
    if ! delete_cloud_function; then
        ((cleanup_errors++))
    fi
    
    if ! delete_storage_bucket; then
        ((cleanup_errors++))
    fi
    
    cleanup_firestore_data
    cleanup_local_files
    
    # Verification
    verify_cleanup
    
    # Summary
    if [[ ${cleanup_errors} -eq 0 ]]; then
        log_success "Cleanup completed successfully!"
    else
        log_warn "Cleanup completed with ${cleanup_errors} error(s)"
    fi
    
    log_info "Resources cleaned up:"
    log_info "  • Project: ${PROJECT_ID}"
    if [[ -n "${FUNCTION_NAME}" ]]; then
        log_info "  • Cloud Function: ${FUNCTION_NAME}"
    fi
    if [[ -n "${BUCKET_NAME}" ]]; then
        log_info "  • Storage Bucket: ${BUCKET_NAME}"
    fi
    log_info "  • Local files and directories"
    
    show_cost_impact
    
    if [[ -f "${SCRIPT_DIR}/../cleanup_firestore.py" ]]; then
        log_info "To clean up Firestore documents, run:"
        log_info "  cd ${SCRIPT_DIR}/.."
        log_info "  pip install google-cloud-firestore"
        log_info "  python3 cleanup_firestore.py"
    fi
    
    log_info "Cleanup log saved to: ${LOG_FILE}"
    log_success "Cleanup script completed"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi