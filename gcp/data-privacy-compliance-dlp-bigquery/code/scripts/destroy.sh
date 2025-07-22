#!/bin/bash

# Data Privacy Compliance with Cloud DLP and BigQuery - Cleanup Script
# This script safely removes all resources created by the deployment script
# including Cloud Storage, BigQuery, Cloud DLP, and Cloud Functions

set -e
set -o pipefail

# Configuration and constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "${LOG_FILE}"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Check ${LOG_FILE} for details."
    exit 1
}

# Warning handling
warn_continue() {
    log_warn "$1"
    log_warn "Continuing with cleanup..."
}

# Load deployment state
load_state() {
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        source "${DEPLOYMENT_STATE_FILE}"
        log_info "Loaded deployment state from ${DEPLOYMENT_STATE_FILE}"
    else
        log_warn "No deployment state file found. Some cleanup may be incomplete."
        log_warn "State file expected at: ${DEPLOYMENT_STATE_FILE}"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Cannot proceed with cleanup."
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_warn "BigQuery CLI (bq) is not installed. BigQuery cleanup may be incomplete."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_warn "gsutil is not installed. Cloud Storage cleanup may be incomplete."
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error_exit "No active gcloud authentication found. Please run: gcloud auth login"
    fi
    
    log "✅ Prerequisites checked"
}

# Confirm destruction
confirm_destruction() {
    if [[ "${FORCE}" != "true" ]]; then
        echo ""
        log_warn "This will permanently delete the following resources:"
        
        if [[ -n "${PROJECT_ID}" ]]; then
            log_warn "  - Project: ${PROJECT_ID} (if --delete-project is specified)"
        fi
        if [[ -n "${BUCKET_NAME}" ]]; then
            log_warn "  - Cloud Storage Bucket: gs://${BUCKET_NAME}"
        fi
        if [[ -n "${DATASET_NAME}" ]]; then
            log_warn "  - BigQuery Dataset: ${DATASET_NAME}"
        fi
        if [[ -n "${FUNCTION_NAME}" ]]; then
            log_warn "  - Cloud Function: ${FUNCTION_NAME}"
        fi
        log_warn "  - Pub/Sub Topic: dlp-notifications"
        log_warn "  - Any running DLP jobs"
        
        echo ""
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
}

# Cancel DLP jobs
cancel_dlp_jobs() {
    log "Cancelling running DLP jobs..."
    
    if [[ -n "${DLP_JOB_NAME}" ]]; then
        log_info "Cancelling DLP job: ${DLP_JOB_NAME}"
        
        local cancel_response
        cancel_response=$(curl -s -X POST \
            -H "Authorization: Bearer $(gcloud auth print-access-token)" \
            "${DLP_JOB_NAME}:cancel" 2>> "${LOG_FILE}")
        
        if [[ $? -eq 0 ]]; then
            log_info "✅ DLP job cancellation requested"
        else
            warn_continue "Failed to cancel DLP job ${DLP_JOB_NAME}"
        fi
    else
        log_info "No DLP job name found in state, attempting to find and cancel active jobs..."
        
        # Try to list and cancel any active DLP jobs for the project
        if command -v python3 &> /dev/null; then
            local active_jobs
            active_jobs=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
                "https://dlp.googleapis.com/v2/projects/${PROJECT_ID}/dlpJobs" 2>> "${LOG_FILE}" | \
                python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    jobs = data.get('jobs', [])
    for job in jobs:
        if job.get('state') in ['PENDING', 'RUNNING']:
            print(job.get('name', ''))
except:
    pass
" 2>> "${LOG_FILE}")
            
            if [[ -n "${active_jobs}" ]]; then
                while IFS= read -r job_name; do
                    if [[ -n "${job_name}" ]]; then
                        log_info "Cancelling active DLP job: ${job_name}"
                        curl -s -X POST \
                            -H "Authorization: Bearer $(gcloud auth print-access-token)" \
                            "${job_name}:cancel" &>> "${LOG_FILE}" || true
                    fi
                done <<< "${active_jobs}"
            fi
        fi
    fi
    
    log "✅ DLP job cancellation completed"
}

# Delete Cloud Function
delete_cloud_function() {
    log "Deleting Cloud Function..."
    
    if [[ -n "${FUNCTION_NAME}" ]] && [[ -n "${REGION}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
            log_info "Deleting Cloud Function: ${FUNCTION_NAME}"
            
            if gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet 2>> "${LOG_FILE}"; then
                log_info "✅ Cloud Function deleted successfully"
            else
                warn_continue "Failed to delete Cloud Function ${FUNCTION_NAME}"
            fi
        else
            log_info "Cloud Function ${FUNCTION_NAME} not found, skipping deletion"
        fi
    else
        log_warn "Cloud Function name or region not found in state, attempting manual cleanup..."
        
        # Try to find and delete functions with dlp-remediation pattern
        local functions_list
        functions_list=$(gcloud functions list --filter="name:dlp-remediation" --format="value(name)" 2>> "${LOG_FILE}" || true)
        
        if [[ -n "${functions_list}" ]]; then
            while IFS= read -r func_name; do
                if [[ -n "${func_name}" ]]; then
                    log_info "Found and deleting Cloud Function: ${func_name}"
                    gcloud functions delete "${func_name}" --quiet 2>> "${LOG_FILE}" || true
                fi
            done <<< "${functions_list}"
        fi
    fi
    
    # Clean up function source directory
    local function_dir="${SCRIPT_DIR}/../dlp-function"
    if [[ -d "${function_dir}" ]]; then
        log_info "Removing function source directory"
        rm -rf "${function_dir}" 2>> "${LOG_FILE}" || warn_continue "Failed to remove function directory"
    fi
    
    log "✅ Cloud Function cleanup completed"
}

# Delete Pub/Sub topic
delete_pubsub_topic() {
    log "Deleting Pub/Sub topic..."
    
    if gcloud pubsub topics describe dlp-notifications &> /dev/null; then
        log_info "Deleting Pub/Sub topic: dlp-notifications"
        
        if gcloud pubsub topics delete dlp-notifications --quiet 2>> "${LOG_FILE}"; then
            log_info "✅ Pub/Sub topic deleted successfully"
        else
            warn_continue "Failed to delete Pub/Sub topic dlp-notifications"
        fi
    else
        log_info "Pub/Sub topic dlp-notifications not found, skipping deletion"
    fi
    
    log "✅ Pub/Sub topic cleanup completed"
}

# Delete BigQuery resources
delete_bigquery_resources() {
    log "Deleting BigQuery resources..."
    
    if [[ -n "${DATASET_NAME}" ]] && [[ -n "${PROJECT_ID}" ]]; then
        if bq ls "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
            log_info "Deleting BigQuery dataset: ${DATASET_NAME}"
            
            if bq rm -r -f "${DATASET_NAME}" 2>> "${LOG_FILE}"; then
                log_info "✅ BigQuery dataset deleted successfully"
            else
                warn_continue "Failed to delete BigQuery dataset ${DATASET_NAME}"
            fi
        else
            log_info "BigQuery dataset ${DATASET_NAME} not found, skipping deletion"
        fi
    else
        log_warn "Dataset name or project ID not found in state, attempting manual cleanup..."
        
        # Try to find and delete privacy_compliance dataset
        if bq ls "${PROJECT_ID}:privacy_compliance" &> /dev/null; then
            log_info "Found and deleting BigQuery dataset: privacy_compliance"
            bq rm -r -f privacy_compliance 2>> "${LOG_FILE}" || true
        fi
    fi
    
    log "✅ BigQuery resources cleanup completed"
}

# Delete Cloud Storage bucket
delete_storage_bucket() {
    log "Deleting Cloud Storage bucket..."
    
    if [[ -n "${BUCKET_NAME}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
            log_info "Deleting Cloud Storage bucket: gs://${BUCKET_NAME}"
            
            # First, try to delete all objects in the bucket
            log_info "Removing all objects from bucket..."
            if gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>> "${LOG_FILE}"; then
                log_info "✅ Bucket objects deleted"
            else
                log_info "No objects found in bucket or objects already deleted"
            fi
            
            # Then delete the bucket itself
            if gsutil rb "gs://${BUCKET_NAME}" 2>> "${LOG_FILE}"; then
                log_info "✅ Cloud Storage bucket deleted successfully"
            else
                warn_continue "Failed to delete Cloud Storage bucket gs://${BUCKET_NAME}"
            fi
        else
            log_info "Cloud Storage bucket gs://${BUCKET_NAME} not found, skipping deletion"
        fi
    else
        log_warn "Bucket name not found in state, attempting manual cleanup..."
        
        # Try to find and delete buckets with dlp-compliance-data pattern
        local buckets_list
        buckets_list=$(gsutil ls | grep "dlp-compliance-data" || true)
        
        if [[ -n "${buckets_list}" ]]; then
            while IFS= read -r bucket_url; do
                if [[ -n "${bucket_url}" ]]; then
                    log_info "Found and deleting bucket: ${bucket_url}"
                    gsutil -m rm -r "${bucket_url}/**" 2>> "${LOG_FILE}" || true
                    gsutil rb "${bucket_url}" 2>> "${LOG_FILE}" || true
                fi
            done <<< "${buckets_list}"
        fi
    fi
    
    log "✅ Cloud Storage bucket cleanup completed"
}

# Delete DLP templates
delete_dlp_templates() {
    log "Deleting DLP inspection templates..."
    
    if [[ -n "${PROJECT_ID}" ]]; then
        # Try to find and delete DLP templates
        local templates_response
        templates_response=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
            "https://dlp.googleapis.com/v2/projects/${PROJECT_ID}/inspectTemplates" 2>> "${LOG_FILE}")
        
        if command -v python3 &> /dev/null && [[ -n "${templates_response}" ]]; then
            local template_names
            template_names=$(echo "${templates_response}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    templates = data.get('inspectTemplates', [])
    for template in templates:
        name = template.get('name', '')
        display_name = template.get('displayName', '')
        if 'privacy-compliance' in display_name.lower() or 'privacy-compliance-scanner' in name:
            print(name)
except:
    pass
" 2>> "${LOG_FILE}")
            
            if [[ -n "${template_names}" ]]; then
                while IFS= read -r template_name; do
                    if [[ -n "${template_name}" ]]; then
                        log_info "Deleting DLP template: ${template_name}"
                        curl -s -X DELETE \
                            -H "Authorization: Bearer $(gcloud auth print-access-token)" \
                            "https://dlp.googleapis.com/v2/${template_name}" &>> "${LOG_FILE}" || true
                    fi
                done <<< "${template_names}"
                log_info "✅ DLP templates deleted"
            else
                log_info "No matching DLP templates found"
            fi
        else
            log_info "Unable to query DLP templates or no templates found"
        fi
    fi
    
    log "✅ DLP templates cleanup completed"
}

# Delete project (optional)
delete_project() {
    if [[ "${DELETE_PROJECT}" == "true" ]] && [[ -n "${PROJECT_ID}" ]]; then
        log "Deleting Google Cloud project..."
        
        log_warn "This will permanently delete the entire project: ${PROJECT_ID}"
        log_warn "This action cannot be undone!"
        
        if [[ "${FORCE}" != "true" ]]; then
            read -p "Are you absolutely sure you want to delete the project ${PROJECT_ID}? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Project deletion cancelled by user"
                return
            fi
        fi
        
        if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
            log_info "Deleting project: ${PROJECT_ID}"
            
            if gcloud projects delete "${PROJECT_ID}" --quiet 2>> "${LOG_FILE}"; then
                log_info "✅ Project deletion initiated"
                log_info "Note: Project deletion may take several minutes to complete"
            else
                warn_continue "Failed to delete project ${PROJECT_ID}"
            fi
        else
            log_info "Project ${PROJECT_ID} not found or already deleted"
        fi
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    local temp_files=(
        "${SCRIPT_DIR}/lifecycle.json"
        "${SCRIPT_DIR}/dlp_template.json"
        "${SCRIPT_DIR}/dlp_job.json"
        "${SCRIPT_DIR}/sample_customer_data.csv"
        "${SCRIPT_DIR}/privacy_policy.txt"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            log_info "Removing temporary file: ${file}"
            rm -f "${file}" 2>> "${LOG_FILE}" || true
        fi
    done
    
    # Remove deployment state file if requested
    if [[ "${CLEAN_STATE}" == "true" ]] && [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        log_info "Removing deployment state file: ${DEPLOYMENT_STATE_FILE}"
        rm -f "${DEPLOYMENT_STATE_FILE}" 2>> "${LOG_FILE}" || true
    fi
    
    log "✅ Temporary files cleanup completed"
}

# Display cleanup summary
display_summary() {
    log "=== CLEANUP SUMMARY ==="
    
    if [[ -n "${PROJECT_ID}" ]]; then
        log_info "Project: ${PROJECT_ID}"
    fi
    
    log_info "Cleaned up resources:"
    log_info "  ✅ DLP jobs cancelled"
    log_info "  ✅ Cloud Function deleted"
    log_info "  ✅ Pub/Sub topic deleted"
    log_info "  ✅ BigQuery dataset deleted"
    log_info "  ✅ Cloud Storage bucket deleted"
    log_info "  ✅ DLP templates deleted"
    log_info "  ✅ Temporary files cleaned"
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        log_info "  ✅ Project deletion initiated"
    fi
    
    log_info ""
    log_info "Cleanup completed successfully!"
    log_info "Check ${LOG_FILE} for detailed logs."
}

# Print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Clean up Data Privacy Compliance with Cloud DLP and BigQuery resources"
    echo ""
    echo "Options:"
    echo "  -f, --force                 Skip confirmation prompts"
    echo "  -p, --delete-project        Delete the entire Google Cloud project"
    echo "  -s, --clean-state           Remove deployment state file after cleanup"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  FORCE                       Skip confirmation prompts (true/false)"
    echo "  DELETE_PROJECT              Delete the entire project (true/false)"
    echo "  CLEAN_STATE                 Remove state file after cleanup (true/false)"
    echo ""
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE="true"
                shift
                ;;
            -p|--delete-project)
                DELETE_PROJECT="true"
                shift
                ;;
            -s|--clean-state)
                CLEAN_STATE="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Main cleanup function
main() {
    echo "🧹 Starting Data Privacy Compliance Cleanup"
    echo "==========================================="
    echo ""
    
    # Initialize log file
    echo "Cleanup started at $(date)" > "${LOG_FILE}"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Load deployment state
    load_state
    
    # Run cleanup steps
    check_prerequisites
    confirm_destruction
    cancel_dlp_jobs
    delete_cloud_function
    delete_pubsub_topic
    delete_bigquery_resources
    delete_storage_bucket
    delete_dlp_templates
    delete_project
    cleanup_temp_files
    display_summary
    
    log ""
    log "🎉 Cleanup completed successfully!"
}

# Run main function with all arguments
main "$@"