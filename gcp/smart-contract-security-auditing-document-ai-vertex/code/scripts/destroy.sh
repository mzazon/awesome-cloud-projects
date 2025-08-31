#!/bin/bash

#################################################################################
# Smart Contract Security Auditing Cleanup Script
# 
# This script safely removes all resources created by the smart contract 
# security auditing solution to prevent ongoing costs and clean up the 
# Google Cloud environment.
#
# Resources removed:
# - Cloud Function and related triggers
# - Document AI processor
# - Cloud Storage bucket and all contents
# - Local files and environment variables
#
# Prerequisites:
# - Google Cloud CLI installed and authenticated
# - Deployment state file from previous deployment
#################################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active Google Cloud authentication found. Run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed or not in PATH"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ ! -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        log_warning "Deployment state file not found. Will attempt cleanup with user-provided values."
        
        # Prompt for required values if state file doesn't exist
        read -p "Enter Project ID: " PROJECT_ID
        read -p "Enter Region [us-central1]: " REGION
        REGION=${REGION:-us-central1}
        read -p "Enter Bucket Name: " BUCKET_NAME
        read -p "Enter Function Name [contract-security-analyzer]: " FUNCTION_NAME
        FUNCTION_NAME=${FUNCTION_NAME:-contract-security-analyzer}
        read -p "Enter Processor ID (optional): " PROCESSOR_ID
        
        export PROJECT_ID REGION BUCKET_NAME FUNCTION_NAME PROCESSOR_ID
        
        # Set zone based on region
        export ZONE="${REGION}-a"
        
        log_warning "Using user-provided values for cleanup"
    else
        # Load variables from deployment state
        source "${DEPLOYMENT_STATE_FILE}"
        export PROJECT_ID REGION ZONE BUCKET_NAME FUNCTION_NAME PROCESSOR_ID
        
        log_success "Deployment state loaded from ${DEPLOYMENT_STATE_FILE}"
        log_info "Project: ${PROJECT_ID}, Region: ${REGION}"
    fi
    
    # Verify required variables are set
    if [[ -z "${PROJECT_ID:-}" ]] || [[ -z "${REGION:-}" ]] || [[ -z "${BUCKET_NAME:-}" ]]; then
        log_error "Required variables not set. Cannot proceed with cleanup."
        exit 1
    fi
}

# Confirm cleanup action
confirm_cleanup() {
    echo ""
    log_warning "This will permanently delete the following resources:"
    echo "  - Project: ${PROJECT_ID}"
    echo "  - Cloud Function: ${FUNCTION_NAME}"
    echo "  - Storage Bucket: gs://${BUCKET_NAME} (all contents will be lost)"
    if [[ -n "${PROCESSOR_ID:-}" ]]; then
        echo "  - Document AI Processor: ${PROCESSOR_ID}"
    fi
    echo "  - Local files and deployment state"
    echo ""
    
    # Interactive confirmation
    if [[ "${FORCE_CLEANUP:-}" != "true" ]]; then
        read -p "Are you sure you want to proceed? (yes/no): " confirm
        if [[ "${confirm}" != "yes" ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    log_info "Proceeding with cleanup..."
}

# Remove Cloud Function
remove_cloud_function() {
    log_info "Removing Cloud Function..."
    
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        log_warning "Function name not specified, skipping Cloud Function cleanup"
        return 0
    fi
    
    # Check if function exists
    if ! gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
        log_warning "Cloud Function ${FUNCTION_NAME} not found, skipping removal"
        return 0
    fi
    
    # Delete Cloud Function
    log_info "Deleting Cloud Function: ${FUNCTION_NAME}"
    if gcloud functions delete "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" \
        --quiet 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Cloud Function deleted successfully"
    else
        log_error "Failed to delete Cloud Function, continuing with cleanup..."
    fi
}

# Remove Document AI Processor
remove_document_ai_processor() {
    log_info "Removing Document AI processor..."
    
    if [[ -z "${PROCESSOR_ID:-}" ]]; then
        log_warning "Processor ID not specified, attempting to find processor by name..."
        
        # Try to find processor by display name
        PROCESSOR_PATH=$(gcloud documentai processors list \
            --location="${REGION}" \
            --project="${PROJECT_ID}" \
            --filter="displayName:'Smart Contract Security Parser'" \
            --format="value(name)" 2>/dev/null | head -n1 || echo "")
        
        if [[ -z "${PROCESSOR_PATH}" ]]; then
            log_warning "Document AI processor not found, skipping removal"
            return 0
        fi
    else
        PROCESSOR_PATH="projects/${PROJECT_ID}/locations/${REGION}/processors/${PROCESSOR_ID}"
    fi
    
    # Check if processor exists
    if ! gcloud documentai processors describe "${PROCESSOR_PATH}" >/dev/null 2>&1; then
        log_warning "Document AI processor not found, skipping removal"
        return 0
    fi
    
    # Delete Document AI processor
    log_info "Deleting Document AI processor: ${PROCESSOR_PATH}"
    if gcloud documentai processors delete "${PROCESSOR_PATH}" \
        --project="${PROJECT_ID}" \
        --quiet 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Document AI processor deleted successfully"
    else
        log_error "Failed to delete Document AI processor, continuing with cleanup..."
    fi
}

# Remove Cloud Storage bucket
remove_storage_bucket() {
    log_info "Removing Cloud Storage bucket and contents..."
    
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_warning "Bucket name not specified, skipping bucket cleanup"
        return 0
    fi
    
    # Check if bucket exists
    if ! gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "Storage bucket gs://${BUCKET_NAME} not found, skipping removal"
        return 0
    fi
    
    # List bucket contents for verification
    log_info "Bucket contents to be deleted:"
    gsutil ls -r "gs://${BUCKET_NAME}" 2>&1 | tee -a "${LOG_FILE}" || true
    
    # Delete all objects and bucket
    log_info "Deleting bucket contents and bucket: gs://${BUCKET_NAME}"
    if gsutil -m rm -r "gs://${BUCKET_NAME}" 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "Storage bucket deleted successfully"
    else
        log_error "Failed to delete storage bucket, continuing with cleanup..."
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove function source directory
    if [[ -d "${SCRIPT_DIR}/contract-security-function" ]]; then
        rm -rf "${SCRIPT_DIR}/contract-security-function"
        log_info "Removed Cloud Function source directory"
    fi
    
    # Remove sample files
    local files_to_remove=(
        "sample_vulnerable_contract.sol"
        "contract_security_spec.md"
        "lifecycle.json"
        "sample_vulnerable_contract_security_audit.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
            rm -f "${SCRIPT_DIR}/${file}"
            log_info "Removed ${file}"
        fi
    done
    
    # Remove deployment state file
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        rm -f "${DEPLOYMENT_STATE_FILE}"
        log_info "Removed deployment state file"
    fi
    
    log_success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check if function still exists
    if [[ -n "${FUNCTION_NAME:-}" ]] && gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
        log_warning "Cloud Function ${FUNCTION_NAME} still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check if bucket still exists
    if [[ -n "${BUCKET_NAME:-}" ]] && gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "Storage bucket gs://${BUCKET_NAME} still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check if processor still exists
    if [[ -n "${PROCESSOR_ID:-}" ]]; then
        PROCESSOR_PATH="projects/${PROJECT_ID}/locations/${REGION}/processors/${PROCESSOR_ID}"
        if gcloud documentai processors describe "${PROCESSOR_PATH}" >/dev/null 2>&1; then
            log_warning "Document AI processor ${PROCESSOR_ID} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [[ ${cleanup_issues} -eq 0 ]]; then
        log_success "All resources cleaned up successfully"
    else
        log_warning "${cleanup_issues} resource(s) may not have been fully cleaned up"
        log_info "You may need to manually remove remaining resources from the Google Cloud Console"
    fi
}

# Display cleanup summary
display_summary() {
    log_success "Smart Contract Security Auditing Solution Cleanup Complete!"
    echo ""
    log_info "Cleanup Summary:"
    echo "  - Cloud Function: ${FUNCTION_NAME:-N/A}"
    echo "  - Storage Bucket: ${BUCKET_NAME:-N/A}"
    echo "  - Document AI Processor: ${PROCESSOR_ID:-N/A}"
    echo "  - Local files and deployment state"
    echo ""
    log_info "All resources have been removed to prevent ongoing charges"
    echo ""
    log_info "Check the Google Cloud Console to verify complete cleanup:"
    echo "  - Cloud Functions: https://console.cloud.google.com/functions"
    echo "  - Cloud Storage: https://console.cloud.google.com/storage"
    echo "  - Document AI: https://console.cloud.google.com/ai/document-ai"
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warning "Cleanup interrupted by user"
    log_info "Some resources may not have been cleaned up completely"
    log_info "Re-run this script or manually remove resources from Google Cloud Console"
    exit 1
}

trap cleanup_on_interrupt SIGINT SIGTERM

# Main cleanup flow
main() {
    echo "========================================="
    echo "Smart Contract Security Auditing Cleanup"
    echo "========================================="
    echo ""
    
    # Initialize log file
    echo "Cleanup started at $(date)" > "${LOG_FILE}"
    
    check_prerequisites
    load_deployment_state
    confirm_cleanup
    remove_cloud_function
    remove_document_ai_processor
    remove_storage_bucket
    cleanup_local_files
    verify_cleanup
    display_summary
    
    log_success "Cleanup completed successfully at $(date)"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_CLEANUP="true"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force] [--help]"
            echo ""
            echo "Options:"
            echo "  --force    Skip confirmation prompts and force cleanup"
            echo "  --help     Show this help message"
            echo ""
            echo "This script removes all resources created by the smart contract"
            echo "security auditing deployment to prevent ongoing charges."
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi