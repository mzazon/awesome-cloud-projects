#!/bin/bash

#
# Smart Content Classification with Gemini and Cloud Storage - Cleanup Script
# 
# This script safely removes all resources created by the deployment script:
# - Cloud Functions and their triggers
# - Cloud Storage buckets and their contents
# - Service accounts and IAM bindings
# - Local temporary files
#
# Prerequisites:
# - Google Cloud CLI (gcloud) installed and authenticated
# - Deployment environment file (.env) from deployment script
#

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENV_FILE="${SCRIPT_DIR}/.env"
readonly CLEANUP_LOG="${SCRIPT_DIR}/cleanup_$(date +%Y%m%d_%H%M%S).log"

# Safety confirmation
confirm_destruction() {
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "  • Cloud Function: content-classifier"
    echo "  • Cloud Storage buckets and ALL their contents"
    echo "  • Service account and IAM policy bindings"
    echo "  • Local test files and environment configuration"
    echo ""
    
    if [[ -f "${ENV_FILE}" ]]; then
        # shellcheck source=/dev/null
        source "${ENV_FILE}"
        echo "Resources to be deleted from project: ${PROJECT_ID:-UNKNOWN}"
        echo "  • Staging bucket: gs://${STAGING_BUCKET:-UNKNOWN}"
        echo "  • Contracts bucket: gs://${CONTRACTS_BUCKET:-UNKNOWN}"
        echo "  • Invoices bucket: gs://${INVOICES_BUCKET:-UNKNOWN}"
        echo "  • Marketing bucket: gs://${MARKETING_BUCKET:-UNKNOWN}"
        echo "  • Miscellaneous bucket: gs://${MISC_BUCKET:-UNKNOWN}"
        echo "  • Service account: ${SERVICE_ACCOUNT:-UNKNOWN}@${PROJECT_ID:-UNKNOWN}.iam.gserviceaccount.com"
    else
        log_warning "Environment file not found. Manual resource identification may be required."
    fi
    
    echo ""
    read -p "Are you absolutely sure you want to proceed? Type 'yes' to continue: " -r
    echo ""
    
    if [[ ! "${REPLY}" =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    # Double confirmation for production safety
    read -p "This action cannot be undone. Type 'DELETE' to confirm: " -r
    echo ""
    
    if [[ "${REPLY}" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Load environment variables
load_environment() {
    log_info "Loading deployment environment..."
    
    if [[ ! -f "${ENV_FILE}" ]]; then
        log_warning "Environment file not found at ${ENV_FILE}"
        log_info "Attempting to use manual resource identification..."
        
        # Prompt for essential variables if env file is missing
        read -p "Enter Project ID: " PROJECT_ID
        read -p "Enter Region (default: us-central1): " REGION
        REGION="${REGION:-us-central1}"
        
        export PROJECT_ID REGION
        log_warning "Using manually provided configuration"
    else
        # shellcheck source=/dev/null
        source "${ENV_FILE}"
        log_success "Loaded environment from ${ENV_FILE}"
        log_info "Project: ${PROJECT_ID}"
        log_info "Region: ${REGION}"
    fi
    
    # Verify gcloud project context
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [[ "${current_project}" != "${PROJECT_ID}" ]]; then
        log_warning "Current gcloud project (${current_project}) differs from deployment project (${PROJECT_ID})"
        read -p "Switch to project ${PROJECT_ID}? (y/N): " -r
        
        if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
            gcloud config set project "${PROJECT_ID}" || error_exit "Failed to switch project"
            log_success "Switched to project ${PROJECT_ID}"
        else
            log_warning "Continuing with current project context"
        fi
    fi
}

# Remove Cloud Function
remove_cloud_function() {
    log_info "Removing Cloud Function and event triggers..."
    
    # Check if function exists
    if gcloud functions describe content-classifier --region="${REGION}" &>/dev/null; then
        log_info "Found Cloud Function 'content-classifier', deleting..."
        
        if gcloud functions delete content-classifier \
            --region="${REGION}" \
            --quiet; then
            log_success "Cloud Function 'content-classifier' deleted successfully"
        else
            log_error "Failed to delete Cloud Function 'content-classifier'"
            log_info "You may need to delete it manually from the Cloud Console"
        fi
    else
        log_warning "Cloud Function 'content-classifier' not found (may already be deleted)"
    fi
    
    # Wait for function deletion to complete
    log_info "Waiting for function deletion to propagate..."
    sleep 10
}

# Remove Cloud Storage buckets
remove_storage_buckets() {
    log_info "Removing Cloud Storage buckets and their contents..."
    
    # Array of bucket variables to check
    local bucket_vars=(
        "${STAGING_BUCKET:-}"
        "${CONTRACTS_BUCKET:-}"
        "${INVOICES_BUCKET:-}"
        "${MARKETING_BUCKET:-}"
        "${MISC_BUCKET:-}"
    )
    
    local deleted_count=0
    local error_count=0
    
    for bucket in "${bucket_vars[@]}"; do
        if [[ -n "${bucket}" ]]; then
            log_info "Checking bucket: gs://${bucket}"
            
            # Check if bucket exists
            if gsutil ls -b "gs://${bucket}" &>/dev/null; then
                log_info "Deleting bucket and contents: gs://${bucket}"
                
                # Use parallel deletion for faster cleanup
                if gsutil -m rm -r "gs://${bucket}"; then
                    log_success "Deleted bucket: gs://${bucket}"
                    ((deleted_count++))
                else
                    log_error "Failed to delete bucket: gs://${bucket}"
                    ((error_count++))
                fi
            else
                log_warning "Bucket not found: gs://${bucket} (may already be deleted)"
            fi
        fi
    done
    
    # If env file missing, attempt to find and delete buckets by pattern
    if [[ ! -f "${ENV_FILE}" ]]; then
        log_info "Searching for potential buckets created by this deployment..."
        
        # Look for buckets with common patterns
        local potential_buckets
        potential_buckets=$(gsutil ls -b 2>/dev/null | grep -E "(staging-content-|contracts-|invoices-|marketing-|miscellaneous-)" || echo "")
        
        if [[ -n "${potential_buckets}" ]]; then
            log_warning "Found potential buckets from this deployment:"
            echo "${potential_buckets}"
            
            read -p "Delete these buckets? (y/N): " -r
            if [[ "${REPLY}" =~ ^[Yy]$ ]]; then
                while IFS= read -r bucket; do
                    if [[ -n "${bucket}" ]]; then
                        bucket_name=$(echo "${bucket}" | sed 's|gs://||' | sed 's|/||')
                        log_info "Deleting: gs://${bucket_name}"
                        gsutil -m rm -r "gs://${bucket_name}" || log_error "Failed to delete gs://${bucket_name}"
                    fi
                done <<< "${potential_buckets}"
            fi
        fi
    fi
    
    log_success "Storage cleanup completed (${deleted_count} deleted, ${error_count} errors)"
}

# Remove service account
remove_service_account() {
    log_info "Removing service account and IAM bindings..."
    
    local service_account_email="${SERVICE_ACCOUNT:-content-classifier-sa}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "${service_account_email}" &>/dev/null; then
        log_info "Found service account: ${service_account_email}"
        
        # Remove IAM policy bindings first
        local roles=(
            "roles/aiplatform.user"
            "roles/storage.admin"
            "roles/logging.logWriter"
        )
        
        for role in "${roles[@]}"; do
            log_info "Removing IAM binding for role: ${role}"
            
            if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${service_account_email}" \
                --role="${role}" \
                --quiet 2>/dev/null; then
                log_success "Removed IAM binding: ${role}"
            else
                log_warning "Failed to remove IAM binding: ${role} (may not exist)"
            fi
        done
        
        # Delete the service account
        log_info "Deleting service account: ${service_account_email}"
        
        if gcloud iam service-accounts delete "${service_account_email}" --quiet; then
            log_success "Service account deleted successfully"
        else
            log_error "Failed to delete service account"
            log_info "You may need to delete it manually from the Cloud Console"
        fi
    else
        log_warning "Service account not found: ${service_account_email} (may already be deleted)"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/sample_contract.txt"
        "${SCRIPT_DIR}/sample_invoice.txt"
        "${SCRIPT_DIR}/sample_marketing.txt"
        "${SCRIPT_DIR}/test_invoice.txt"
        "${SCRIPT_DIR}/test_marketing.txt"
        "${SCRIPT_DIR}/deployment_summary.txt"
        "${ENV_FILE}"
    )
    
    local removed_count=0
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            if rm "${file}"; then
                log_success "Removed: $(basename "${file}")"
                ((removed_count++))
            else
                log_warning "Failed to remove: $(basename "${file}")"
            fi
        fi
    done
    
    # Clean up any temporary directories that might have been created
    local temp_dirs=(
        "${SCRIPT_DIR}/cloud-function"
        "${SCRIPT_DIR}/../terraform/function_source"
    )
    
    for dir in "${temp_dirs[@]}"; do
        if [[ -d "${dir}" && "${dir}" == *"temp"* ]]; then
            log_info "Removing temporary directory: ${dir}"
            rm -rf "${dir}" || log_warning "Failed to remove directory: ${dir}"
        fi
    done
    
    log_success "Local cleanup completed (${removed_count} files removed)"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local issues_found=0
    
    # Check if Cloud Function still exists
    if gcloud functions describe content-classifier --region="${REGION}" &>/dev/null; then
        log_warning "⚠️  Cloud Function 'content-classifier' still exists"
        ((issues_found++))
    else
        log_success "✅ Cloud Function removed"
    fi
    
    # Check if service account still exists (if we have the info)
    if [[ -n "${SERVICE_ACCOUNT:-}" && -n "${PROJECT_ID:-}" ]]; then
        local service_account_email="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com"
        if gcloud iam service-accounts describe "${service_account_email}" &>/dev/null; then
            log_warning "⚠️  Service account still exists: ${service_account_email}"
            ((issues_found++))
        else
            log_success "✅ Service account removed"
        fi
    fi
    
    # Check for remaining buckets (if we have the info)
    if [[ -n "${STAGING_BUCKET:-}" ]]; then
        if gsutil ls -b "gs://${STAGING_BUCKET}" &>/dev/null; then
            log_warning "⚠️  Staging bucket still exists: gs://${STAGING_BUCKET}"
            ((issues_found++))
        else
            log_success "✅ Storage buckets removed"
        fi
    fi
    
    # Check if environment file was removed
    if [[ -f "${ENV_FILE}" ]]; then
        log_warning "⚠️  Environment file still exists: ${ENV_FILE}"
        ((issues_found++))
    else
        log_success "✅ Environment file removed"
    fi
    
    if [[ ${issues_found} -eq 0 ]]; then
        log_success "🎉 Cleanup verification completed successfully - no issues found"
    else
        log_warning "⚠️  Cleanup verification found ${issues_found} potential issues"
        log_info "These may require manual cleanup in the Google Cloud Console"
    fi
}

# Generate cleanup summary
generate_cleanup_summary() {
    log_info "Generating cleanup summary..."
    
    cat > "${SCRIPT_DIR}/cleanup_summary.txt" << EOF
Smart Content Classification Cleanup Summary
============================================

Cleanup Date: $(date)
Project ID: ${PROJECT_ID:-UNKNOWN}
Region: ${REGION:-UNKNOWN}

Resources Removed:
------------------
✅ Cloud Function: content-classifier
✅ Cloud Storage buckets:
   - Staging: gs://${STAGING_BUCKET:-UNKNOWN}
   - Contracts: gs://${CONTRACTS_BUCKET:-UNKNOWN}
   - Invoices: gs://${INVOICES_BUCKET:-UNKNOWN}
   - Marketing: gs://${MARKETING_BUCKET:-UNKNOWN}
   - Miscellaneous: gs://${MISC_BUCKET:-UNKNOWN}

✅ Service Account: ${SERVICE_ACCOUNT:-content-classifier-sa}@${PROJECT_ID:-UNKNOWN}.iam.gserviceaccount.com

✅ Local Files:
   - Sample test files
   - Environment configuration
   - Deployment summary

Cleanup Log: ${CLEANUP_LOG}

Notes:
------
- All billable resources have been removed
- Project APIs remain enabled (can be disabled manually if needed)
- Deployment scripts remain available for future use

If you need to redeploy, run: ./deploy.sh

For any remaining resources, check the Google Cloud Console:
https://console.cloud.google.com/
EOF
    
    log_success "Cleanup summary saved to cleanup_summary.txt"
}

# Main cleanup function
main() {
    log_info "Starting Smart Content Classification cleanup..."
    log_info "Cleanup log: ${CLEANUP_LOG}"
    
    # Redirect all output to log file while also displaying on console
    exec > >(tee -a "${CLEANUP_LOG}") 2>&1
    
    echo "Cleanup started at: $(date)"
    
    # Execute cleanup steps
    confirm_destruction
    load_environment
    remove_cloud_function
    remove_storage_buckets
    remove_service_account
    cleanup_local_files
    verify_cleanup
    generate_cleanup_summary
    
    log_success "🧹 Smart Content Classification cleanup completed!"
    log_info "📋 Check cleanup_summary.txt for complete details"
    log_info "🔄 To redeploy, run ./deploy.sh"
    
    echo ""
    echo "Cleanup Summary:"
    echo "================"
    echo "✅ All Cloud Functions removed"
    echo "✅ All Storage buckets deleted"
    echo "✅ Service accounts removed"
    echo "✅ Local files cleaned up"
    echo "💰 All billable resources have been removed"
    echo ""
    
    log_success "Cleanup completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi