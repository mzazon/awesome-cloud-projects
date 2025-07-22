#!/bin/bash

# Infrastructure Cost Optimization with Cloud Batch and Cloud Monitoring - Cleanup Script
# This script removes all resources created by the cost optimization deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# Load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ -f .env ]]; then
        source .env
        success "Environment variables loaded from .env file"
        log "  PROJECT_ID: ${PROJECT_ID:-not set}"
        log "  REGION: ${REGION:-not set}"
        log "  BUCKET_NAME: ${BUCKET_NAME:-not set}"
        log "  DATASET_NAME: ${DATASET_NAME:-not set}"
    else
        warn ".env file not found. Using environment variables or prompting for input..."
        
        # Prompt for essential variables if not set
        if [[ -z "${PROJECT_ID:-}" ]]; then
            read -p "Enter PROJECT_ID: " PROJECT_ID
            export PROJECT_ID
        fi
        
        if [[ -z "${REGION:-}" ]]; then
            export REGION="us-central1"
            log "Using default region: ${REGION}"
        fi
        
        if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
            warn "RANDOM_SUFFIX not found. Some resources may not be cleaned up properly."
            export RANDOM_SUFFIX=""
        fi
        
        # Set resource names with suffix if available
        export BUCKET_NAME="${BUCKET_NAME:-cost-optimization-${RANDOM_SUFFIX}}"
        export DATASET_NAME="${DATASET_NAME:-cost_analytics_${RANDOM_SUFFIX//-/_}}"
        export BATCH_JOB_NAME="${BATCH_JOB_NAME:-infra-analysis-${RANDOM_SUFFIX}}"
        export FUNCTION_NAME="${FUNCTION_NAME:-cost-optimizer-${RANDOM_SUFFIX}}"
    fi
}

# Confirmation prompt
confirm_deletion() {
    log "This will delete the following resources:"
    log "  - Project: ${PROJECT_ID}"
    log "  - Storage Bucket: gs://${BUCKET_NAME}"
    log "  - BigQuery Dataset: ${DATASET_NAME}"
    log "  - Cloud Function: ${FUNCTION_NAME}"
    log "  - Batch Job: ${BATCH_JOB_NAME}"
    log "  - Pub/Sub topics and subscriptions"
    log "  - Cloud Scheduler jobs"
    log "  - Monitoring alert policies"
    
    warn "This action cannot be undone!"
    
    read -p "Are you sure you want to delete all resources? (yes/no): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Cleanup confirmed. Proceeding with resource deletion..."
}

# Set gcloud project
set_gcloud_project() {
    log "Setting gcloud project context..."
    
    if gcloud config set project "${PROJECT_ID}"; then
        success "gcloud project set to ${PROJECT_ID}"
    else
        error "Failed to set gcloud project. Please check PROJECT_ID: ${PROJECT_ID}"
    fi
    
    # Set region if available
    if [[ -n "${REGION}" ]]; then
        gcloud config set compute/region "${REGION}"
    fi
}

# Delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log "Deleting Cloud Scheduler jobs..."
    
    local jobs_deleted=0
    
    # Try to delete the specific job if RANDOM_SUFFIX is available
    if [[ -n "${RANDOM_SUFFIX}" ]]; then
        local job_name="cost-optimization-schedule-${RANDOM_SUFFIX}"
        if gcloud scheduler jobs delete "${job_name}" --location="${REGION}" --quiet 2>/dev/null; then
            success "Deleted scheduler job: ${job_name}"
            jobs_deleted=$((jobs_deleted + 1))
        else
            warn "Failed to delete scheduler job: ${job_name} (may not exist)"
        fi
    else
        # List and delete all matching jobs
        log "Searching for cost optimization scheduler jobs..."
        local jobs
        jobs=$(gcloud scheduler jobs list --location="${REGION}" --filter="name:cost-optimization-schedule" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${jobs}" ]]; then
            while IFS= read -r job; do
                if [[ -n "${job}" ]]; then
                    local job_id
                    job_id=$(basename "${job}")
                    if gcloud scheduler jobs delete "${job_id}" --location="${REGION}" --quiet; then
                        success "Deleted scheduler job: ${job_id}"
                        jobs_deleted=$((jobs_deleted + 1))
                    else
                        warn "Failed to delete scheduler job: ${job_id}"
                    fi
                fi
            done <<< "${jobs}"
        fi
    fi
    
    if [[ $jobs_deleted -gt 0 ]]; then
        success "Deleted ${jobs_deleted} scheduler job(s)"
    else
        warn "No scheduler jobs found or deleted"
    fi
}

# Delete Cloud Batch jobs
delete_batch_jobs() {
    log "Deleting Cloud Batch jobs..."
    
    local jobs_deleted=0
    
    # Try to delete the specific batch job
    if [[ -n "${BATCH_JOB_NAME}" ]]; then
        if gcloud batch jobs delete "${BATCH_JOB_NAME}" --location="${REGION}" --quiet 2>/dev/null; then
            success "Deleted batch job: ${BATCH_JOB_NAME}"
            jobs_deleted=$((jobs_deleted + 1))
        else
            warn "Failed to delete batch job: ${BATCH_JOB_NAME} (may not exist or already completed)"
        fi
    fi
    
    # List and delete any remaining batch jobs with matching pattern
    log "Searching for remaining infrastructure analysis batch jobs..."
    local jobs
    jobs=$(gcloud batch jobs list --location="${REGION}" --filter="name:infra-analysis" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${jobs}" ]]; then
        while IFS= read -r job; do
            if [[ -n "${job}" ]]; then
                local job_id
                job_id=$(basename "${job}")
                if gcloud batch jobs delete "${job_id}" --location="${REGION}" --quiet; then
                    success "Deleted batch job: ${job_id}"
                    jobs_deleted=$((jobs_deleted + 1))
                else
                    warn "Failed to delete batch job: ${job_id}"
                fi
            fi
        done <<< "${jobs}"
    fi
    
    if [[ $jobs_deleted -gt 0 ]]; then
        success "Deleted ${jobs_deleted} batch job(s)"
    else
        log "No batch jobs found to delete"
    fi
}

# Delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    local functions_deleted=0
    
    # Try to delete the specific function
    if [[ -n "${FUNCTION_NAME}" ]]; then
        if gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet 2>/dev/null; then
            success "Deleted Cloud Function: ${FUNCTION_NAME}"
            functions_deleted=$((functions_deleted + 1))
        else
            warn "Failed to delete Cloud Function: ${FUNCTION_NAME} (may not exist)"
        fi
    fi
    
    # List and delete any remaining cost optimizer functions
    log "Searching for remaining cost optimizer functions..."
    local functions
    functions=$(gcloud functions list --regions="${REGION}" --filter="name:cost-optimizer" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${functions}" ]]; then
        while IFS= read -r func; do
            if [[ -n "${func}" ]]; then
                local func_name
                func_name=$(basename "${func}")
                if gcloud functions delete "${func_name}" --region="${REGION}" --quiet; then
                    success "Deleted Cloud Function: ${func_name}"
                    functions_deleted=$((functions_deleted + 1))
                else
                    warn "Failed to delete Cloud Function: ${func_name}"
                fi
            fi
        done <<< "${functions}"
    fi
    
    if [[ $functions_deleted -gt 0 ]]; then
        success "Deleted ${functions_deleted} Cloud Function(s)"
    else
        log "No Cloud Functions found to delete"
    fi
}

# Delete Pub/Sub resources
delete_pubsub_resources() {
    log "Deleting Pub/Sub resources..."
    
    local resources_deleted=0
    
    # Delete subscriptions first
    local subscriptions=(
        "cost-optimization-processor"
        "batch-completion-handler"
    )
    
    for subscription in "${subscriptions[@]}"; do
        if gcloud pubsub subscriptions delete "${subscription}" --quiet 2>/dev/null; then
            success "Deleted Pub/Sub subscription: ${subscription}"
            resources_deleted=$((resources_deleted + 1))
        else
            warn "Failed to delete Pub/Sub subscription: ${subscription} (may not exist)"
        fi
    done
    
    # Delete topics
    local topics=(
        "cost-optimization-events"
        "batch-job-notifications"
    )
    
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics delete "${topic}" --quiet 2>/dev/null; then
            success "Deleted Pub/Sub topic: ${topic}"
            resources_deleted=$((resources_deleted + 1))
        else
            warn "Failed to delete Pub/Sub topic: ${topic} (may not exist)"
        fi
    done
    
    if [[ $resources_deleted -gt 0 ]]; then
        success "Deleted ${resources_deleted} Pub/Sub resource(s)"
    else
        warn "No Pub/Sub resources found or deleted"
    fi
}

# Delete monitoring alert policies
delete_monitoring_policies() {
    log "Deleting Cloud Monitoring alert policies..."
    
    local policies_deleted=0
    
    # List and delete matching alert policies
    local policies
    policies=$(gcloud alpha monitoring policies list --filter="displayName:'High Infrastructure Costs Alert'" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${policies}" ]]; then
        while IFS= read -r policy; do
            if [[ -n "${policy}" ]]; then
                if gcloud alpha monitoring policies delete "${policy}" --quiet; then
                    success "Deleted monitoring policy: $(basename ${policy})"
                    policies_deleted=$((policies_deleted + 1))
                else
                    warn "Failed to delete monitoring policy: $(basename ${policy})"
                fi
            fi
        done <<< "${policies}"
    fi
    
    if [[ $policies_deleted -gt 0 ]]; then
        success "Deleted ${policies_deleted} monitoring polic(ies)"
    else
        log "No monitoring policies found to delete"
    fi
}

# Delete BigQuery resources
delete_bigquery_resources() {
    log "Deleting BigQuery resources..."
    
    if [[ -n "${DATASET_NAME}" ]]; then
        if bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" 2>/dev/null; then
            success "Deleted BigQuery dataset: ${DATASET_NAME}"
        else
            warn "Failed to delete BigQuery dataset: ${DATASET_NAME} (may not exist)"
        fi
    else
        log "DATASET_NAME not set, searching for cost analytics datasets..."
        
        # List and delete matching datasets
        local datasets
        datasets=$(bq ls --format=csv --max_results=1000 | grep "cost_analytics" | cut -d',' -f1 || echo "")
        
        if [[ -n "${datasets}" ]]; then
            while IFS= read -r dataset; do
                if [[ -n "${dataset}" && "${dataset}" != "datasetId" ]]; then
                    if bq rm -r -f "${PROJECT_ID}:${dataset}"; then
                        success "Deleted BigQuery dataset: ${dataset}"
                    else
                        warn "Failed to delete BigQuery dataset: ${dataset}"
                    fi
                fi
            done <<< "${datasets}"
        else
            log "No matching BigQuery datasets found"
        fi
    fi
}

# Delete Cloud Storage resources
delete_storage_resources() {
    log "Deleting Cloud Storage resources..."
    
    if [[ -n "${BUCKET_NAME}" ]]; then
        if gsutil -m rm -r "gs://${BUCKET_NAME}" 2>/dev/null; then
            success "Deleted Cloud Storage bucket: gs://${BUCKET_NAME}"
        else
            warn "Failed to delete Cloud Storage bucket: gs://${BUCKET_NAME} (may not exist)"
        fi
    else
        log "BUCKET_NAME not set, searching for cost optimization buckets..."
        
        # List and delete matching buckets
        local buckets
        buckets=$(gsutil ls | grep "cost-optimization" || echo "")
        
        if [[ -n "${buckets}" ]]; then
            while IFS= read -r bucket; do
                if [[ -n "${bucket}" ]]; then
                    if gsutil -m rm -r "${bucket}"; then
                        success "Deleted Cloud Storage bucket: ${bucket}"
                    else
                        warn "Failed to delete Cloud Storage bucket: ${bucket}"
                    fi
                fi
            done <<< "${buckets}"
        else
            log "No matching Cloud Storage buckets found"
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_deleted=0
    
    # Remove function directory
    if [[ -d "cost-optimizer-function" ]]; then
        rm -rf cost-optimizer-function
        success "Removed cost-optimizer-function directory"
        files_deleted=$((files_deleted + 1))
    fi
    
    # Remove batch configs directory
    if [[ -d "batch-configs" ]]; then
        rm -rf batch-configs
        success "Removed batch-configs directory"
        files_deleted=$((files_deleted + 1))
    fi
    
    # Remove temporary files
    local temp_files=(
        "lifecycle.json"
        "alert-policy.json"
        ".env"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            success "Removed temporary file: ${file}"
            files_deleted=$((files_deleted + 1))
        fi
    done
    
    if [[ $files_deleted -gt 0 ]]; then
        success "Cleaned up ${files_deleted} local file(s)/director(ies)"
    else
        log "No local files found to clean up"
    fi
}

# Verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local remaining_resources=0
    
    # Check Cloud Functions
    if [[ -n "${FUNCTION_NAME}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
            warn "Cloud Function still exists: ${FUNCTION_NAME}"
            remaining_resources=$((remaining_resources + 1))
        fi
    fi
    
    # Check Storage bucket
    if [[ -n "${BUCKET_NAME}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            warn "Storage bucket still exists: gs://${BUCKET_NAME}"
            remaining_resources=$((remaining_resources + 1))
        fi
    fi
    
    # Check BigQuery dataset
    if [[ -n "${DATASET_NAME}" ]]; then
        if bq ls "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
            warn "BigQuery dataset still exists: ${DATASET_NAME}"
            remaining_resources=$((remaining_resources + 1))
        fi
    fi
    
    # Check Pub/Sub topics
    if gcloud pubsub topics describe cost-optimization-events &>/dev/null; then
        warn "Pub/Sub topic still exists: cost-optimization-events"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        success "All resources have been successfully cleaned up"
    else
        warn "${remaining_resources} resource(s) may still exist - manual cleanup may be required"
    fi
}

# Main cleanup function
main() {
    log "Starting Infrastructure Cost Optimization cleanup..."
    
    load_environment
    confirm_deletion
    set_gcloud_project
    
    # Delete resources in reverse order of creation
    delete_scheduler_jobs
    delete_monitoring_policies
    delete_batch_jobs
    delete_cloud_functions
    delete_pubsub_resources
    delete_bigquery_resources
    delete_storage_resources
    cleanup_local_files
    
    verify_cleanup
    
    success "Infrastructure Cost Optimization cleanup completed!"
    
    log "Cleanup Summary:"
    log "  - Cloud Scheduler jobs removed"
    log "  - Cloud Batch jobs removed"
    log "  - Cloud Functions removed"
    log "  - Pub/Sub resources removed"
    log "  - BigQuery datasets removed"
    log "  - Cloud Storage buckets removed"
    log "  - Local files cleaned up"
    
    warn "Note: Some monitoring policies may require manual deletion through the console"
    warn "Verify in the Google Cloud Console that all resources have been removed"
    
    log "If you need to check for any remaining resources:"
    log "  gcloud projects list --filter='projectId:cost-opt-*'"
    log "  gcloud functions list --regions=${REGION}"
    log "  gsutil ls | grep cost-optimization"
    log "  bq ls | grep cost_analytics"
}

# Handle script interruption
trap 'warn "Cleanup script interrupted. Some resources may not have been deleted."' INT TERM

# Run main function
main "$@"