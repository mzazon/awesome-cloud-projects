#!/bin/bash

# Destroy script for Time Series Forecasting with TimesFM and BigQuery DataCanvas
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "BigQuery CLI (bq) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Check if PROJECT_ID is provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        # Try to get current project
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            error "PROJECT_ID environment variable is not set and no default project found."
            error "Please set PROJECT_ID or run 'gcloud config set project YOUR_PROJECT_ID'"
            exit 1
        fi
    fi
    
    # Set default values
    export REGION="${REGION:-us-central1}"
    export DATASET_NAME="${DATASET_NAME:-financial_forecasting}"
    export BUCKET_NAME="${BUCKET_NAME:-timesfm-data-${PROJECT_ID}}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" 2>/dev/null || true
    gcloud config set compute/region "${REGION}" 2>/dev/null || true
    
    success "Environment variables configured"
    log "PROJECT_ID: ${PROJECT_ID}"
    log "REGION: ${REGION}"
    log "DATASET_NAME: ${DATASET_NAME}"
}

# Function to get user confirmation
confirm_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}WARNING: About to delete ${resource_type}: ${resource_name}${NC}"
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Skipping deletion of ${resource_type}: ${resource_name}"
        return 1
    fi
    return 0
}

# Function to list and delete Cloud Scheduler jobs
cleanup_scheduler_jobs() {
    log "Cleaning up Cloud Scheduler jobs..."
    
    # List all scheduler jobs in the region that might be related to forecasting
    local jobs
    jobs=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" --filter="name~forecast" 2>/dev/null || echo "")
    
    if [[ -n "${jobs}" ]]; then
        while IFS= read -r job; do
            if [[ -n "${job}" ]]; then
                local job_name=$(basename "${job}")
                if confirm_deletion "Cloud Scheduler job" "${job_name}"; then
                    log "Deleting Cloud Scheduler job: ${job_name}..."
                    if gcloud scheduler jobs delete "${job_name}" --location="${REGION}" --quiet 2>/dev/null; then
                        success "Deleted Cloud Scheduler job: ${job_name}"
                    else
                        warning "Failed to delete Cloud Scheduler job: ${job_name} (may not exist)"
                    fi
                fi
            fi
        done <<< "${jobs}"
    else
        log "No forecasting-related Cloud Scheduler jobs found"
    fi
    
    # Try to delete jobs with common patterns
    local common_patterns=("daily-forecast-" "forecast-monitor-" "forecast-processor-")
    for pattern in "${common_patterns[@]}"; do
        local pattern_jobs
        pattern_jobs=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" --filter="name~${pattern}" 2>/dev/null || echo "")
        
        if [[ -n "${pattern_jobs}" ]]; then
            while IFS= read -r job; do
                if [[ -n "${job}" ]]; then
                    local job_name=$(basename "${job}")
                    if confirm_deletion "Cloud Scheduler job" "${job_name}"; then
                        log "Deleting Cloud Scheduler job: ${job_name}..."
                        if gcloud scheduler jobs delete "${job_name}" --location="${REGION}" --quiet 2>/dev/null; then
                            success "Deleted Cloud Scheduler job: ${job_name}"
                        else
                            warning "Failed to delete Cloud Scheduler job: ${job_name}"
                        fi
                    fi
                fi
            done <<< "${pattern_jobs}"
        fi
    done
    
    success "Cloud Scheduler cleanup completed"
}

# Function to list and delete Cloud Functions
cleanup_cloud_functions() {
    log "Cleaning up Cloud Functions..."
    
    # List all functions in the region that might be related to forecasting
    local functions
    functions=$(gcloud functions list --regions="${REGION}" --format="value(name)" --filter="name~forecast" 2>/dev/null || echo "")
    
    if [[ -n "${functions}" ]]; then
        while IFS= read -r func; do
            if [[ -n "${func}" ]]; then
                local func_name=$(basename "${func}")
                if confirm_deletion "Cloud Function" "${func_name}"; then
                    log "Deleting Cloud Function: ${func_name}..."
                    if gcloud functions delete "${func_name}" --region="${REGION}" --quiet 2>/dev/null; then
                        success "Deleted Cloud Function: ${func_name}"
                    else
                        warning "Failed to delete Cloud Function: ${func_name} (may not exist)"
                    fi
                fi
            fi
        done <<< "${functions}"
    else
        log "No forecasting-related Cloud Functions found"
    fi
    
    # Try to delete functions with common patterns
    local common_patterns=("forecast-processor-" "financial-processor-" "timesfm-")
    for pattern in "${common_patterns[@]}"; do
        local pattern_functions
        pattern_functions=$(gcloud functions list --regions="${REGION}" --format="value(name)" --filter="name~${pattern}" 2>/dev/null || echo "")
        
        if [[ -n "${pattern_functions}" ]]; then
            while IFS= read -r func; do
                if [[ -n "${func}" ]]; then
                    local func_name=$(basename "${func}")
                    if confirm_deletion "Cloud Function" "${func_name}"; then
                        log "Deleting Cloud Function: ${func_name}..."
                        if gcloud functions delete "${func_name}" --region="${REGION}" --quiet 2>/dev/null; then
                            success "Deleted Cloud Function: ${func_name}"
                        else
                            warning "Failed to delete Cloud Function: ${func_name}"
                        fi
                    fi
                fi
            done <<< "${pattern_functions}"
        fi
    done
    
    success "Cloud Functions cleanup completed"
}

# Function to delete BigQuery resources
cleanup_bigquery() {
    log "Cleaning up BigQuery resources..."
    
    # Check if dataset exists
    if bq ls "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        if confirm_deletion "BigQuery dataset" "${DATASET_NAME}"; then
            log "Deleting BigQuery dataset: ${DATASET_NAME}..."
            
            # First, try to delete individual tables to get better error messages
            local tables
            tables=$(bq ls -n 1000 "${PROJECT_ID}:${DATASET_NAME}" 2>/dev/null | tail -n +3 | awk '{print $1}' || echo "")
            
            if [[ -n "${tables}" ]]; then
                while IFS= read -r table; do
                    if [[ -n "${table}" && "${table}" != "TABLE_ID" ]]; then
                        log "Deleting table: ${table}..."
                        bq rm -f -t "${PROJECT_ID}:${DATASET_NAME}.${table}" 2>/dev/null || \
                            warning "Failed to delete table: ${table}"
                    fi
                done <<< "${tables}"
            fi
            
            # Delete views
            local views
            views=$(bq ls -n 1000 "${PROJECT_ID}:${DATASET_NAME}" 2>/dev/null | grep VIEW | awk '{print $1}' || echo "")
            
            if [[ -n "${views}" ]]; then
                while IFS= read -r view; do
                    if [[ -n "${view}" ]]; then
                        log "Deleting view: ${view}..."
                        bq rm -f -t "${PROJECT_ID}:${DATASET_NAME}.${view}" 2>/dev/null || \
                            warning "Failed to delete view: ${view}"
                    fi
                done <<< "${views}"
            fi
            
            # Delete the dataset
            log "Deleting dataset: ${DATASET_NAME}..."
            if bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" 2>/dev/null; then
                success "Deleted BigQuery dataset: ${DATASET_NAME}"
            else
                error "Failed to delete BigQuery dataset: ${DATASET_NAME}"
            fi
        fi
    else
        log "BigQuery dataset ${DATASET_NAME} not found (may already be deleted)"
    fi
    
    success "BigQuery cleanup completed"
}

# Function to clean up Cloud Storage buckets
cleanup_storage() {
    log "Cleaning up Cloud Storage resources..."
    
    # Check if bucket exists
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        if confirm_deletion "Cloud Storage bucket" "${BUCKET_NAME}"; then
            log "Deleting Cloud Storage bucket: ${BUCKET_NAME}..."
            
            # Remove all objects in bucket first
            if gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null; then
                log "Removed all objects from bucket"
            else
                log "Bucket appears to be empty or objects already removed"
            fi
            
            # Delete the bucket
            if gsutil rb "gs://${BUCKET_NAME}" 2>/dev/null; then
                success "Deleted Cloud Storage bucket: ${BUCKET_NAME}"
            else
                warning "Failed to delete Cloud Storage bucket: ${BUCKET_NAME} (may not exist)"
            fi
        fi
    else
        log "Cloud Storage bucket ${BUCKET_NAME} not found (may not exist)"
    fi
    
    success "Cloud Storage cleanup completed"
}

# Function to clean up IAM resources (if any custom ones were created)
cleanup_iam() {
    log "Cleaning up IAM resources..."
    
    # List service accounts that might be related to forecasting
    local service_accounts
    service_accounts=$(gcloud iam service-accounts list --format="value(email)" --filter="email~forecast OR email~timesfm" 2>/dev/null || echo "")
    
    if [[ -n "${service_accounts}" ]]; then
        while IFS= read -r sa; do
            if [[ -n "${sa}" ]]; then
                if confirm_deletion "Service Account" "${sa}"; then
                    log "Deleting service account: ${sa}..."
                    if gcloud iam service-accounts delete "${sa}" --quiet 2>/dev/null; then
                        success "Deleted service account: ${sa}"
                    else
                        warning "Failed to delete service account: ${sa}"
                    fi
                fi
            fi
        done <<< "${service_accounts}"
    else
        log "No forecasting-related service accounts found"
    fi
    
    success "IAM cleanup completed"
}

# Function to disable APIs (optional)
disable_apis() {
    if [[ "${DISABLE_APIS:-false}" == "true" ]]; then
        log "Disabling APIs..."
        
        local apis=(
            "aiplatform.googleapis.com"
            "cloudfunctions.googleapis.com"
            "cloudscheduler.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            if confirm_deletion "API" "${api}"; then
                log "Disabling ${api}..."
                if gcloud services disable "${api}" --quiet 2>/dev/null; then
                    success "Disabled ${api}"
                else
                    warning "Failed to disable ${api} (may have dependent resources)"
                fi
            fi
        done
    else
        log "Skipping API disabling (set DISABLE_APIS=true to disable APIs)"
    fi
}

# Function to clean up local environment
cleanup_environment() {
    log "Cleaning up local environment..."
    
    # Remove temporary directories if they exist
    rm -rf /tmp/forecast-function-* 2>/dev/null || true
    
    # Optionally unset environment variables
    if [[ "${CLEANUP_ENV_VARS:-false}" == "true" ]]; then
        unset PROJECT_ID REGION DATASET_NAME BUCKET_NAME
        unset FUNCTION_NAME JOB_NAME RANDOM_SUFFIX FUNCTION_URL
        log "Environment variables cleaned up"
    fi
    
    success "Local environment cleanup completed"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local cleanup_issues=0
    
    # Check BigQuery dataset
    if bq ls "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        warning "BigQuery dataset ${DATASET_NAME} still exists"
        ((cleanup_issues++))
    fi
    
    # Check for remaining Cloud Functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --regions="${REGION}" --format="value(name)" --filter="name~forecast" 2>/dev/null | wc -l)
    if [[ "${remaining_functions}" -gt 0 ]]; then
        warning "${remaining_functions} forecasting-related Cloud Functions still exist"
        ((cleanup_issues++))
    fi
    
    # Check for remaining Cloud Scheduler jobs
    local remaining_jobs
    remaining_jobs=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" --filter="name~forecast" 2>/dev/null | wc -l)
    if [[ "${remaining_jobs}" -gt 0 ]]; then
        warning "${remaining_jobs} forecasting-related Cloud Scheduler jobs still exist"
        ((cleanup_issues++))
    fi
    
    # Check Cloud Storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        warning "Cloud Storage bucket ${BUCKET_NAME} still exists"
        ((cleanup_issues++))
    fi
    
    if [[ ${cleanup_issues} -eq 0 ]]; then
        success "Cleanup validation completed successfully"
    else
        warning "Cleanup validation found ${cleanup_issues} remaining resources"
        warning "You may need to manually clean up these resources"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Dataset: ${DATASET_NAME}"
    echo ""
    echo "Resources cleaned up:"
    echo "- BigQuery dataset: ${DATASET_NAME}"
    echo "- Cloud Functions (forecast-related)"
    echo "- Cloud Scheduler jobs (forecast-related)"
    echo "- Cloud Storage bucket: ${BUCKET_NAME}"
    echo "- IAM service accounts (forecast-related)"
    echo ""
    if [[ "${DISABLE_APIS:-false}" == "true" ]]; then
        echo "APIs disabled: AI Platform, Cloud Functions, Cloud Scheduler"
    else
        echo "APIs left enabled (use DISABLE_APIS=true to disable)"
    fi
    echo ""
    success "Cleanup completed!"
}

# Main cleanup function
main() {
    log "Starting Time Series Forecasting infrastructure cleanup..."
    
    # Check for force deletion flag
    if [[ "${1:-}" == "--force" || "${FORCE_DELETE:-}" == "true" ]]; then
        export FORCE_DELETE="true"
        warning "Force deletion mode enabled - no confirmation prompts"
    fi
    
    # Run cleanup steps
    check_prerequisites
    setup_environment
    
    echo -e "${YELLOW}WARNING: This will delete all resources created by the forecasting deployment${NC}"
    if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
        read -p "Are you sure you want to continue with cleanup? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    cleanup_scheduler_jobs
    cleanup_cloud_functions
    cleanup_bigquery
    cleanup_storage
    cleanup_iam
    disable_apis
    cleanup_environment
    validate_cleanup
    display_summary
    
    success "All cleanup steps completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup interrupted"; exit 1' INT TERM

# Show usage information
show_usage() {
    echo "Usage: $0 [--force]"
    echo ""
    echo "Environment variables:"
    echo "  PROJECT_ID           - GCP Project ID (required)"
    echo "  REGION              - GCP Region (default: us-central1)"
    echo "  DATASET_NAME        - BigQuery dataset name (default: financial_forecasting)"
    echo "  BUCKET_NAME         - Storage bucket name (default: timesfm-data-\$PROJECT_ID)"
    echo "  FORCE_DELETE        - Skip confirmation prompts (default: false)"
    echo "  DISABLE_APIS        - Disable APIs after cleanup (default: false)"
    echo "  CLEANUP_ENV_VARS    - Unset environment variables (default: false)"
    echo ""
    echo "Options:"
    echo "  --force             - Skip all confirmation prompts"
    echo "  --help              - Show this help message"
}

# Check for help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_usage
    exit 0
fi

# Run main function
main "$@"