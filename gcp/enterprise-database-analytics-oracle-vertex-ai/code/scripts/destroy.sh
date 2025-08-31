#!/bin/bash

# Destroy script for Enterprise Database Analytics with Oracle and Vertex AI
# This script safely removes all infrastructure created by the deploy script
# Includes confirmation prompts and comprehensive cleanup verification

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
readonly VARS_FILE="${SCRIPT_DIR}/deployment_vars.env"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - ${1}" | tee -a "${ERROR_LOG}"
}

# Initialize log files
echo "Destruction started at $(date)" > "${LOG_FILE}"
echo "Destruction errors for $(date)" > "${ERROR_LOG}"

# Load environment variables from deployment
load_environment() {
    log_info "Loading deployment environment variables..."
    
    if [[ -f "${VARS_FILE}" ]]; then
        # shellcheck source=/dev/null
        source "${VARS_FILE}"
        log_success "Environment variables loaded from ${VARS_FILE}"
    else
        log_warning "Deployment variables file not found: ${VARS_FILE}"
        log_info "You may need to set environment variables manually or provide them as arguments"
        
        # Try to get current gcloud project if available
        if command -v gcloud &> /dev/null && gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
            export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
            export REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null || echo 'us-central1')}"
            export ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || echo 'us-central1-a')}"
            
            if [[ -n "${PROJECT_ID}" ]]; then
                log_info "Using current gcloud project: ${PROJECT_ID}"
            else
                log_error "No project ID available. Please set PROJECT_ID environment variable or run deploy script first."
                exit 1
            fi
        else
            log_error "Cannot determine deployment configuration. Please ensure gcloud is authenticated and configured."
            exit 1
        fi
    fi
    
    # Validate required variables
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID is required but not set"
        exit 1
    fi
    
    log_info "Using project: ${PROJECT_ID}"
    log_info "Using region: ${REGION:-us-central1}"
}

# Confirmation prompt
confirm_destruction() {
    log_warning "This will permanently delete all Oracle Database Analytics infrastructure!"
    log_warning "The following resources will be removed:"
    
    if [[ -n "${ORACLE_INSTANCE_NAME:-}" ]]; then
        log_warning "- Oracle Cloud Exadata Infrastructure: ${ORACLE_INSTANCE_NAME}"
    fi
    if [[ -n "${ADB_NAME:-}" ]]; then
        log_warning "- Autonomous Database: ${ADB_NAME}"
    fi
    if [[ -n "${VERTEX_ENDPOINT_NAME:-}" ]]; then
        log_warning "- Vertex AI Endpoint: ${VERTEX_ENDPOINT_NAME}"
    fi
    if [[ -n "${BQ_DATASET_NAME:-}" ]]; then
        log_warning "- BigQuery Dataset: ${BQ_DATASET_NAME}"
    fi
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log_warning "- Cloud Function: ${FUNCTION_NAME}"
    fi
    if [[ -n "${STAGING_BUCKET:-}" ]]; then
        log_warning "- Storage Bucket: gs://${STAGING_BUCKET}"
    fi
    
    log_warning ""
    log_warning "Estimated cost savings after cleanup: \$500-1500/month"
    log_warning ""
    
    # Skip confirmation if --yes flag is provided
    if [[ "${1:-}" == "--yes" || "${SKIP_CONFIRMATION:-false}" == "true" ]]; then
        log_info "Confirmation skipped due to --yes flag or SKIP_CONFIRMATION=true"
        return 0
    fi
    
    echo -n "Are you sure you want to proceed? (type 'yes' to confirm): "
    read -r confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_info "Destruction confirmed by user"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for destruction..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed. Cannot cleanup BigQuery resources."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Cannot cleanup storage resources."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Set gcloud project
    if [[ -n "${PROJECT_ID}" ]]; then
        gcloud config set project "${PROJECT_ID}"
        log_success "gcloud project set to: ${PROJECT_ID}"
    fi
    
    log_success "Prerequisites check completed"
}

# Remove Cloud Functions and Scheduler
remove_pipeline_components() {
    log_info "Removing data pipeline components..."
    
    # Remove Cloud Scheduler job
    if [[ -n "${SCHEDULER_JOB:-}" ]]; then
        log_info "Removing Cloud Scheduler job: ${SCHEDULER_JOB}"
        if gcloud scheduler jobs describe "${SCHEDULER_JOB}" \
            --location="${REGION:-us-central1}" &>/dev/null; then
            
            if gcloud scheduler jobs delete "${SCHEDULER_JOB}" \
                --location="${REGION:-us-central1}" \
                --quiet 2>>"${ERROR_LOG}"; then
                log_success "Cloud Scheduler job removed: ${SCHEDULER_JOB}"
            else
                log_error "Failed to remove Cloud Scheduler job: ${SCHEDULER_JOB}"
            fi
        else
            log_info "Cloud Scheduler job not found: ${SCHEDULER_JOB}"
        fi
    fi
    
    # Remove Cloud Function
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log_info "Removing Cloud Function: ${FUNCTION_NAME}"
        if gcloud functions describe "${FUNCTION_NAME}" \
            --region="${REGION:-us-central1}" &>/dev/null; then
            
            if gcloud functions delete "${FUNCTION_NAME}" \
                --region="${REGION:-us-central1}" \
                --quiet 2>>"${ERROR_LOG}"; then
                log_success "Cloud Function removed: ${FUNCTION_NAME}"
            else
                log_error "Failed to remove Cloud Function: ${FUNCTION_NAME}"
            fi
        else
            log_info "Cloud Function not found: ${FUNCTION_NAME}"
        fi
    fi
    
    log_success "Pipeline components cleanup completed"
}

# Remove Vertex AI resources
remove_vertex_ai_resources() {
    log_info "Removing Vertex AI resources..."
    
    # Remove Vertex AI endpoint
    if [[ -n "${ENDPOINT_ID:-}" && -n "${VERTEX_ENDPOINT_NAME:-}" ]]; then
        log_info "Removing Vertex AI endpoint: ${VERTEX_ENDPOINT_NAME}"
        if gcloud ai endpoints describe "${ENDPOINT_ID}" \
            --region="${REGION:-us-central1}" &>/dev/null; then
            
            if gcloud ai endpoints delete "${ENDPOINT_ID}" \
                --region="${REGION:-us-central1}" \
                --quiet 2>>"${ERROR_LOG}"; then
                log_success "Vertex AI endpoint removed: ${VERTEX_ENDPOINT_NAME}"
            else
                log_error "Failed to remove Vertex AI endpoint: ${VERTEX_ENDPOINT_NAME}"
            fi
        else
            log_info "Vertex AI endpoint not found: ${VERTEX_ENDPOINT_NAME}"
        fi
    fi
    
    # Remove Vertex AI Workbench instance
    if [[ -n "${WORKBENCH_INSTANCE:-}" ]]; then
        log_info "Removing Vertex AI Workbench instance: ${WORKBENCH_INSTANCE}"
        if gcloud notebooks instances describe "${WORKBENCH_INSTANCE}" \
            --location="${ZONE:-us-central1-a}" &>/dev/null; then
            
            if gcloud notebooks instances delete "${WORKBENCH_INSTANCE}" \
                --location="${ZONE:-us-central1-a}" \
                --quiet 2>>"${ERROR_LOG}"; then
                log_success "Vertex AI Workbench instance removed: ${WORKBENCH_INSTANCE}"
            else
                log_error "Failed to remove Vertex AI Workbench instance: ${WORKBENCH_INSTANCE}"
            fi
        else
            log_info "Vertex AI Workbench instance not found: ${WORKBENCH_INSTANCE}"
        fi
    fi
    
    # Remove Vertex AI datasets (if any)
    if [[ -n "${DATASET_ID:-}" ]]; then
        log_info "Removing Vertex AI dataset: ${DATASET_ID}"
        if gcloud ai datasets delete "${DATASET_ID}" \
            --region="${REGION:-us-central1}" \
            --quiet 2>>"${ERROR_LOG}"; then
            log_success "Vertex AI dataset removed: ${DATASET_ID}"
        else
            log_warning "Failed to remove Vertex AI dataset or dataset not found: ${DATASET_ID}"
        fi
    fi
    
    # Remove staging bucket
    if [[ -n "${STAGING_BUCKET:-}" ]]; then
        log_info "Removing staging bucket: gs://${STAGING_BUCKET}"
        if gsutil ls "gs://${STAGING_BUCKET}" &>/dev/null; then
            if gsutil -m rm -r "gs://${STAGING_BUCKET}" 2>>"${ERROR_LOG}"; then
                log_success "Staging bucket removed: gs://${STAGING_BUCKET}"
            else
                log_error "Failed to remove staging bucket: gs://${STAGING_BUCKET}"
            fi
        else
            log_info "Staging bucket not found: gs://${STAGING_BUCKET}"
        fi
    fi
    
    log_success "Vertex AI resources cleanup completed"
}

# Remove BigQuery resources
remove_bigquery_resources() {
    log_info "Removing BigQuery resources..."
    
    # Remove external connection (if exists)
    if [[ -n "${ORACLE_CONNECTION_ID:-}" ]]; then
        log_info "Removing BigQuery external connection: ${ORACLE_CONNECTION_ID}"
        if bq rm --connection \
            --location="${REGION:-us-central1}" \
            "${ORACLE_CONNECTION_ID}" 2>>"${ERROR_LOG}"; then
            log_success "BigQuery external connection removed: ${ORACLE_CONNECTION_ID}"
        else
            log_warning "Failed to remove BigQuery external connection or connection not found: ${ORACLE_CONNECTION_ID}"
        fi
    fi
    
    # Remove BigQuery dataset and all tables
    if [[ -n "${BQ_DATASET_NAME:-}" ]]; then
        log_info "Removing BigQuery dataset: ${BQ_DATASET_NAME}"
        if bq ls "${PROJECT_ID}:${BQ_DATASET_NAME}" &>/dev/null; then
            if bq rm -r -f "${PROJECT_ID}:${BQ_DATASET_NAME}" 2>>"${ERROR_LOG}"; then
                log_success "BigQuery dataset removed: ${BQ_DATASET_NAME}"
            else
                log_error "Failed to remove BigQuery dataset: ${BQ_DATASET_NAME}"
            fi
        else
            log_info "BigQuery dataset not found: ${BQ_DATASET_NAME}"
        fi
    fi
    
    log_success "BigQuery resources cleanup completed"
}

# Remove Oracle Database resources
remove_oracle_resources() {
    log_info "Removing Oracle Database@Google Cloud resources..."
    log_warning "Oracle resource deletion may take 30-45 minutes to complete"
    
    # Remove Autonomous Database first
    if [[ -n "${ADB_NAME:-}" ]]; then
        log_info "Removing Autonomous Database: ${ADB_NAME}"
        if gcloud oracle-database autonomous-databases describe "${ADB_NAME}" \
            --location="${REGION:-us-central1}" &>/dev/null; then
            
            if gcloud oracle-database autonomous-databases delete "${ADB_NAME}" \
                --location="${REGION:-us-central1}" \
                --quiet 2>>"${ERROR_LOG}"; then
                log_success "Autonomous Database deletion initiated: ${ADB_NAME}"
                
                # Monitor deletion progress
                log_info "Monitoring Autonomous Database deletion..."
                local max_attempts=60
                local attempt=0
                while [[ ${attempt} -lt ${max_attempts} ]]; do
                    if ! gcloud oracle-database autonomous-databases describe "${ADB_NAME}" \
                        --location="${REGION:-us-central1}" &>/dev/null; then
                        log_success "Autonomous Database successfully deleted: ${ADB_NAME}"
                        break
                    fi
                    
                    log_info "Database deletion in progress (attempt ${attempt}/${max_attempts})"
                    sleep 30
                    ((attempt++))
                done
                
                if [[ ${attempt} -eq ${max_attempts} ]]; then
                    log_warning "Database deletion taking longer than expected. Continuing with infrastructure cleanup..."
                fi
            else
                log_error "Failed to initiate Autonomous Database deletion: ${ADB_NAME}"
            fi
        else
            log_info "Autonomous Database not found: ${ADB_NAME}"
        fi
    fi
    
    # Remove Oracle Cloud Exadata Infrastructure
    if [[ -n "${ORACLE_INSTANCE_NAME:-}" ]]; then
        log_info "Removing Oracle Cloud Exadata Infrastructure: ${ORACLE_INSTANCE_NAME}"
        if gcloud oracle-database cloud-exadata-infrastructures describe "${ORACLE_INSTANCE_NAME}" \
            --location="${REGION:-us-central1}" &>/dev/null; then
            
            if gcloud oracle-database cloud-exadata-infrastructures delete "${ORACLE_INSTANCE_NAME}" \
                --location="${REGION:-us-central1}" \
                --quiet 2>>"${ERROR_LOG}"; then
                log_success "Oracle Cloud Exadata infrastructure deletion initiated: ${ORACLE_INSTANCE_NAME}"
                log_warning "Infrastructure deletion will continue in the background and may take 30-45 minutes"
            else
                log_error "Failed to initiate Oracle infrastructure deletion: ${ORACLE_INSTANCE_NAME}"
            fi
        else
            log_info "Oracle Cloud Exadata infrastructure not found: ${ORACLE_INSTANCE_NAME}"
        fi
    fi
    
    log_success "Oracle Database resources cleanup completed"
}

# Remove monitoring policies
remove_monitoring_policies() {
    log_info "Removing Cloud Monitoring policies..."
    
    # List and remove monitoring policies created for this deployment
    local policies
    policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:(Oracle Database Performance Alert OR Vertex AI Model Performance Alert)" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${policies}" ]]; then
        while IFS= read -r policy; do
            if [[ -n "${policy}" ]]; then
                log_info "Removing monitoring policy: ${policy}"
                if gcloud alpha monitoring policies delete "${policy}" --quiet 2>>"${ERROR_LOG}"; then
                    log_success "Monitoring policy removed: ${policy}"
                else
                    log_warning "Failed to remove monitoring policy: ${policy}"
                fi
            fi
        done <<< "${policies}"
    else
        log_info "No monitoring policies found to remove"
    fi
    
    log_success "Monitoring policies cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local remaining_resources=0
    
    # Check Oracle infrastructure
    if [[ -n "${ORACLE_INSTANCE_NAME:-}" ]]; then
        if gcloud oracle-database cloud-exadata-infrastructures describe "${ORACLE_INSTANCE_NAME}" \
            --location="${REGION:-us-central1}" &>/dev/null; then
            log_info "Oracle infrastructure still exists (deletion in progress): ${ORACLE_INSTANCE_NAME}"
        else
            log_success "Oracle infrastructure confirmed deleted: ${ORACLE_INSTANCE_NAME}"
        fi
    fi
    
    # Check Autonomous Database
    if [[ -n "${ADB_NAME:-}" ]]; then
        if gcloud oracle-database autonomous-databases describe "${ADB_NAME}" \
            --location="${REGION:-us-central1}" &>/dev/null; then
            log_warning "Autonomous Database still exists: ${ADB_NAME}"
            ((remaining_resources++))
        else
            log_success "Autonomous Database confirmed deleted: ${ADB_NAME}"
        fi
    fi
    
    # Check Vertex AI endpoint
    if [[ -n "${ENDPOINT_ID:-}" ]]; then
        if gcloud ai endpoints describe "${ENDPOINT_ID}" \
            --region="${REGION:-us-central1}" &>/dev/null; then
            log_warning "Vertex AI endpoint still exists: ${ENDPOINT_ID}"
            ((remaining_resources++))
        else
            log_success "Vertex AI endpoint confirmed deleted: ${ENDPOINT_ID}"
        fi
    fi
    
    # Check BigQuery dataset
    if [[ -n "${BQ_DATASET_NAME:-}" ]]; then
        if bq ls "${PROJECT_ID}:${BQ_DATASET_NAME}" &>/dev/null; then
            log_warning "BigQuery dataset still exists: ${BQ_DATASET_NAME}"
            ((remaining_resources++))
        else
            log_success "BigQuery dataset confirmed deleted: ${BQ_DATASET_NAME}"
        fi
    fi
    
    # Check Cloud Function
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" \
            --region="${REGION:-us-central1}" &>/dev/null; then
            log_warning "Cloud Function still exists: ${FUNCTION_NAME}"
            ((remaining_resources++))
        else
            log_success "Cloud Function confirmed deleted: ${FUNCTION_NAME}"
        fi
    fi
    
    # Check staging bucket
    if [[ -n "${STAGING_BUCKET:-}" ]]; then
        if gsutil ls "gs://${STAGING_BUCKET}" &>/dev/null; then
            log_warning "Staging bucket still exists: gs://${STAGING_BUCKET}"
            ((remaining_resources++))
        else
            log_success "Staging bucket confirmed deleted: gs://${STAGING_BUCKET}"
        fi
    fi
    
    if [[ ${remaining_resources} -eq 0 ]]; then
        log_success "All resources successfully cleaned up!"
        return 0
    else
        log_warning "Some resources may still exist (${remaining_resources} remaining)"
        log_info "This may be normal for Oracle infrastructure which takes time to fully delete"
        return 1
    fi
}

# Clean up environment files
cleanup_environment_files() {
    log_info "Cleaning up environment and log files..."
    
    # Remove temporary files created during deployment
    local files_to_remove=(
        "${SCRIPT_DIR}/temp_function"
        "${SCRIPT_DIR}/deployment_vars.env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "${file}" ]]; then
            if rm -rf "${file}" 2>>"${ERROR_LOG}"; then
                log_success "Removed: ${file}"
            else
                log_warning "Failed to remove: ${file}"
            fi
        fi
    done
    
    log_success "Environment cleanup completed"
}

# Print cleanup summary
print_summary() {
    log_info "Cleanup Summary"
    log_info "==============="
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION:-us-central1}"
    log_info ""
    log_info "Cleanup Actions Performed:"
    log_info "- Removed Cloud Functions and Scheduler jobs"
    log_info "- Deleted Vertex AI endpoints and workbench instances"
    log_info "- Removed BigQuery datasets and connections"
    log_info "- Initiated Oracle Database and infrastructure deletion"
    log_info "- Cleaned up monitoring policies"
    log_info "- Removed storage buckets"
    log_info ""
    log_success "Estimated monthly cost savings: \$500-1500"
    log_info ""
    log_warning "Important Notes:"
    log_warning "- Oracle infrastructure deletion may take 30-45 minutes to complete fully"
    log_warning "- Monitor the Google Cloud Console to verify all resources are deleted"
    log_warning "- If you encounter billing charges after cleanup, check for orphaned resources"
    log_info ""
    log_info "Cleanup logs saved to: ${LOG_FILE}"
    if [[ -s "${ERROR_LOG}" ]]; then
        log_warning "Errors encountered during cleanup. Check: ${ERROR_LOG}"
    fi
}

# Main execution
main() {
    log_info "Starting Enterprise Database Analytics cleanup..."
    log_info "Script location: ${SCRIPT_DIR}"
    
    load_environment
    confirm_destruction "$@"
    check_prerequisites
    remove_pipeline_components
    remove_vertex_ai_resources
    remove_bigquery_resources
    remove_oracle_resources
    remove_monitoring_policies
    verify_cleanup
    cleanup_environment_files
    print_summary
    
    log_success "Cleanup completed successfully!"
    log_info "Total cleanup time: $((SECONDS / 60)) minutes"
}

# Handle script arguments
if [[ $# -gt 0 && "$1" == "--help" ]]; then
    echo "Usage: $0 [--yes]"
    echo ""
    echo "Options:"
    echo "  --yes    Skip confirmation prompt and proceed with cleanup"
    echo "  --help   Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  SKIP_CONFIRMATION=true    Skip confirmation prompt"
    echo "  PROJECT_ID               Override project ID"
    echo "  REGION                   Override region"
    exit 0
fi

# Execute main function with all arguments
main "$@"