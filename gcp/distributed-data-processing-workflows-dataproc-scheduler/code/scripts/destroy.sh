#!/bin/bash

# Destroy script for Distributed Data Processing Workflows with Cloud Dataproc and Cloud Scheduler
# This script safely removes all resources created by the deployment

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Configuration validation
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "Prerequisites validated successfully"
}

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Use existing environment variables or prompt for required values
    if [[ -z "${PROJECT_ID:-}" ]]; then
        read -p "Enter Project ID: " PROJECT_ID
        export PROJECT_ID
    fi
    
    if [[ -z "${REGION:-}" ]]; then
        export REGION="${REGION:-us-central1}"
    fi
    
    if [[ -z "${ZONE:-}" ]]; then
        export ZONE="${ZONE:-us-central1-a}"
    fi
    
    # Set default resource names (can be overridden by environment variables)
    export BUCKET_NAME="${BUCKET_NAME:-}"
    export STAGING_BUCKET="${STAGING_BUCKET:-}"
    export DATASET_NAME="${DATASET_NAME:-analytics_results}"
    export WORKFLOW_NAME="${WORKFLOW_NAME:-sales-analytics-workflow}"
    export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-dataproc-scheduler}"
    export SCHEDULER_JOB_NAME="${SCHEDULER_JOB_NAME:-sales-analytics-daily}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_success "Environment loaded successfully"
}

# Discover bucket names if not provided
discover_buckets() {
    if [[ -z "${BUCKET_NAME}" || -z "${STAGING_BUCKET}" ]]; then
        log_info "Discovering bucket names..."
        
        # List buckets and try to identify dataproc-related buckets
        local buckets=($(gsutil ls | grep -E "gs://dataproc-(data|staging)-" | sed 's|gs://||' | sed 's|/||' || true))
        
        if [[ ${#buckets[@]} -gt 0 ]]; then
            log_info "Found potential buckets:"
            for bucket in "${buckets[@]}"; do
                log_info "  - ${bucket}"
            done
            
            # Try to match patterns
            for bucket in "${buckets[@]}"; do
                if [[ "${bucket}" =~ dataproc-data- ]]; then
                    export BUCKET_NAME="${bucket}"
                    log_info "Identified data bucket: ${BUCKET_NAME}"
                elif [[ "${bucket}" =~ dataproc-staging- ]]; then
                    export STAGING_BUCKET="${bucket}"
                    log_info "Identified staging bucket: ${STAGING_BUCKET}"
                fi
            done
        else
            log_warning "No dataproc-related buckets found"
        fi
    fi
}

# User confirmation with detailed resource list
confirm_destruction() {
    log_warning "================================================"
    log_warning "DESTRUCTIVE ACTION - RESOURCE DELETION"
    log_warning "================================================"
    log_warning ""
    log_warning "This script will permanently delete the following resources:"
    log_warning "- Cloud Scheduler Job: ${SCHEDULER_JOB_NAME}"
    log_warning "- Dataproc Workflow Template: ${WORKFLOW_NAME}"
    log_warning "- Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    log_warning "- BigQuery Dataset: ${DATASET_NAME} (and all tables)"
    
    if [[ -n "${BUCKET_NAME}" ]]; then
        log_warning "- Cloud Storage Bucket: gs://${BUCKET_NAME} (and all objects)"
    fi
    
    if [[ -n "${STAGING_BUCKET}" ]]; then
        log_warning "- Cloud Storage Bucket: gs://${STAGING_BUCKET} (and all objects)"
    fi
    
    log_warning ""
    log_warning "Any running Dataproc workflows will be cancelled."
    log_warning "This action cannot be undone!"
    log_warning ""
    
    # Prompt for confirmation
    read -p "Do you want to proceed with resource deletion? (yes/no): " confirm
    
    if [[ "${confirm}" != "yes" ]]; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
    
    log_info "User confirmed destruction. Proceeding..."
}

# Cancel any running workflows
cancel_running_workflows() {
    log_info "Checking for running workflows..."
    
    # List and cancel any running workflow instances
    local running_workflows=$(gcloud dataproc operations list \
        --region="${REGION}" \
        --filter="state:RUNNING" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${running_workflows}" ]]; then
        log_warning "Found running workflows. Cancelling them..."
        while IFS= read -r operation; do
            if [[ -n "${operation}" ]]; then
                log_info "Cancelling operation: ${operation}"
                gcloud dataproc operations cancel "${operation}" --region="${REGION}" --quiet || log_warning "Failed to cancel ${operation}"
            fi
        done <<< "${running_workflows}"
        
        log_info "Waiting for operations to fully cancel (30 seconds)..."
        sleep 30
    else
        log_info "No running workflows found"
    fi
    
    log_success "Workflow cancellation completed"
}

# Delete Cloud Scheduler job
delete_scheduler_job() {
    log_info "Deleting Cloud Scheduler job..."
    
    if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" --location="${REGION}" &>/dev/null; then
        if gcloud scheduler jobs delete "${SCHEDULER_JOB_NAME}" --location="${REGION}" --quiet; then
            log_success "Deleted Cloud Scheduler job: ${SCHEDULER_JOB_NAME}"
        else
            log_error "Failed to delete Cloud Scheduler job: ${SCHEDULER_JOB_NAME}"
        fi
    else
        log_warning "Cloud Scheduler job not found: ${SCHEDULER_JOB_NAME}"
    fi
}

# Delete Dataproc workflow template
delete_workflow_template() {
    log_info "Deleting Dataproc workflow template..."
    
    if gcloud dataproc workflow-templates describe "${WORKFLOW_NAME}" --region="${REGION}" &>/dev/null; then
        if gcloud dataproc workflow-templates delete "${WORKFLOW_NAME}" --region="${REGION}" --quiet; then
            log_success "Deleted workflow template: ${WORKFLOW_NAME}"
        else
            log_error "Failed to delete workflow template: ${WORKFLOW_NAME}"
        fi
    else
        log_warning "Workflow template not found: ${WORKFLOW_NAME}"
    fi
}

# Delete service account and IAM bindings
delete_service_account() {
    log_info "Deleting service account and IAM bindings..."
    
    local sa_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "${sa_email}" &>/dev/null; then
        # Remove IAM policy bindings first
        local roles=(
            "roles/dataproc.editor"
            "roles/storage.objectViewer"
            "roles/bigquery.dataEditor"
        )
        
        for role in "${roles[@]}"; do
            log_info "Removing IAM binding for ${role}..."
            if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${sa_email}" \
                --role="${role}" --quiet &>/dev/null; then
                log_success "Removed IAM binding: ${role}"
            else
                log_warning "Failed to remove or binding doesn't exist: ${role}"
            fi
        done
        
        # Delete service account
        if gcloud iam service-accounts delete "${sa_email}" --quiet; then
            log_success "Deleted service account: ${sa_email}"
        else
            log_error "Failed to delete service account: ${sa_email}"
        fi
    else
        log_warning "Service account not found: ${sa_email}"
    fi
}

# Delete BigQuery dataset
delete_bigquery_dataset() {
    log_info "Deleting BigQuery dataset..."
    
    if bq ls -d "${DATASET_NAME}" &>/dev/null; then
        if bq rm -r -f "${DATASET_NAME}"; then
            log_success "Deleted BigQuery dataset: ${DATASET_NAME}"
        else
            log_error "Failed to delete BigQuery dataset: ${DATASET_NAME}"
        fi
    else
        log_warning "BigQuery dataset not found: ${DATASET_NAME}"
    fi
}

# Delete Cloud Storage buckets
delete_storage_buckets() {
    log_info "Deleting Cloud Storage buckets..."
    
    # Delete data bucket
    if [[ -n "${BUCKET_NAME}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            log_info "Deleting data bucket contents and bucket: gs://${BUCKET_NAME}"
            if gsutil -m rm -r "gs://${BUCKET_NAME}"; then
                log_success "Deleted data bucket: gs://${BUCKET_NAME}"
            else
                log_error "Failed to delete data bucket: gs://${BUCKET_NAME}"
            fi
        else
            log_warning "Data bucket not found: gs://${BUCKET_NAME}"
        fi
    else
        log_warning "Data bucket name not specified"
    fi
    
    # Delete staging bucket
    if [[ -n "${STAGING_BUCKET}" ]]; then
        if gsutil ls "gs://${STAGING_BUCKET}" &>/dev/null; then
            log_info "Deleting staging bucket contents and bucket: gs://${STAGING_BUCKET}"
            if gsutil -m rm -r "gs://${STAGING_BUCKET}"; then
                log_success "Deleted staging bucket: gs://${STAGING_BUCKET}"
            else
                log_error "Failed to delete staging bucket: gs://${STAGING_BUCKET}"
            fi
        else
            log_warning "Staging bucket not found: gs://${STAGING_BUCKET}"
        fi
    else
        log_warning "Staging bucket name not specified"
    fi
}

# Clean up any orphaned Dataproc clusters
cleanup_orphaned_clusters() {
    log_info "Checking for orphaned Dataproc clusters..."
    
    local clusters=$(gcloud dataproc clusters list \
        --region="${REGION}" \
        --filter="clusterName:sales-analytics-cluster" \
        --format="value(clusterName)" 2>/dev/null || true)
    
    if [[ -n "${clusters}" ]]; then
        log_warning "Found orphaned clusters. Deleting them..."
        while IFS= read -r cluster; do
            if [[ -n "${cluster}" ]]; then
                log_info "Deleting cluster: ${cluster}"
                gcloud dataproc clusters delete "${cluster}" --region="${REGION}" --quiet || log_warning "Failed to delete cluster ${cluster}"
            fi
        done <<< "${clusters}"
    else
        log_info "No orphaned clusters found"
    fi
}

# Verification of deletion
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local errors=0
    
    # Check Cloud Scheduler job
    if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" --location="${REGION}" &>/dev/null; then
        log_error "Cloud Scheduler job still exists: ${SCHEDULER_JOB_NAME}"
        ((errors++))
    else
        log_success "Verified: Cloud Scheduler job deleted"
    fi
    
    # Check workflow template
    if gcloud dataproc workflow-templates describe "${WORKFLOW_NAME}" --region="${REGION}" &>/dev/null; then
        log_error "Workflow template still exists: ${WORKFLOW_NAME}"
        ((errors++))
    else
        log_success "Verified: Workflow template deleted"
    fi
    
    # Check service account
    local sa_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "${sa_email}" &>/dev/null; then
        log_error "Service account still exists: ${sa_email}"
        ((errors++))
    else
        log_success "Verified: Service account deleted"
    fi
    
    # Check BigQuery dataset
    if bq ls -d "${DATASET_NAME}" &>/dev/null; then
        log_error "BigQuery dataset still exists: ${DATASET_NAME}"
        ((errors++))
    else
        log_success "Verified: BigQuery dataset deleted"
    fi
    
    # Check buckets
    if [[ -n "${BUCKET_NAME}" ]] && gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_error "Data bucket still exists: gs://${BUCKET_NAME}"
        ((errors++))
    elif [[ -n "${BUCKET_NAME}" ]]; then
        log_success "Verified: Data bucket deleted"
    fi
    
    if [[ -n "${STAGING_BUCKET}" ]] && gsutil ls "gs://${STAGING_BUCKET}" &>/dev/null; then
        log_error "Staging bucket still exists: gs://${STAGING_BUCKET}"
        ((errors++))
    elif [[ -n "${STAGING_BUCKET}" ]]; then
        log_success "Verified: Staging bucket deleted"
    fi
    
    return ${errors}
}

# Main destruction function
main() {
    log_info "Starting destruction of Distributed Data Processing Workflows..."
    log_info "================================================"
    
    validate_prerequisites
    load_environment
    discover_buckets
    confirm_destruction
    
    log_info "Beginning resource cleanup..."
    
    cancel_running_workflows
    delete_scheduler_job
    delete_workflow_template
    delete_service_account
    delete_bigquery_dataset
    delete_storage_buckets
    cleanup_orphaned_clusters
    
    log_info "Verifying cleanup..."
    if verify_cleanup; then
        log_success "================================================"
        log_success "All resources successfully deleted!"
        log_info ""
        log_info "Cleanup completed for:"
        log_info "- Project ID: ${PROJECT_ID}"
        log_info "- Region: ${REGION}"
        log_info ""
        log_info "Your Google Cloud project is now clean of recipe resources."
    else
        log_warning "================================================"
        log_warning "Cleanup completed with some issues!"
        log_warning "Some resources may still exist. Please check manually:"
        log_warning "- Google Cloud Console: https://console.cloud.google.com"
        log_warning "- Check Dataproc, Cloud Scheduler, BigQuery, and Storage"
    fi
}

# Run main function
main "$@"