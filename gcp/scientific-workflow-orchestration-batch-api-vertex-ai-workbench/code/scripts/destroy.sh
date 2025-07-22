#!/bin/bash

# Scientific Workflow Orchestration with Cloud Batch API and Vertex AI Workbench
# Cleanup Script for GCP Infrastructure
# Version: 1.0
# Last Updated: 2025-07-12

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Confirmation prompt
confirm_destruction() {
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}        ⚠️  DESTRUCTIVE OPERATION ⚠️${NC}"
    echo -e "${RED}============================================${NC}"
    echo
    echo "This script will permanently delete the following resources:"
    echo "  📦 Project: ${PROJECT_ID:-[Not Set]}"
    echo "  🪣 Storage Bucket: ${BUCKET_NAME:-[Not Set]}"
    echo "  📊 BigQuery Dataset: ${DATASET_NAME:-[Not Set]}"
    echo "  💻 Workbench Instance: ${WORKBENCH_NAME:-[Not Set]}"
    echo "  ⚙️  Batch Job: ${JOB_NAME:-[Not Set]}"
    echo
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo
    
    # Show estimated costs saved
    echo "💰 Estimated monthly cost savings after cleanup:"
    echo "  - Vertex AI Workbench (n1-standard-4): ~\$150/month"
    echo "  - Cloud Storage (regional): ~\$0.02/GB/month"
    echo "  - BigQuery storage: ~\$0.02/GB/month"
    echo "  - Cloud Batch compute: Variable based on usage"
    echo
    
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [[ "${confirmation}" != "DELETE" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    echo
    log_warning "Proceeding with resource destruction..."
    sleep 3
}

# Display banner
echo "================================================="
echo "  Scientific Workflow Orchestration Cleanup"
echo "  Cloud Batch API + Vertex AI Workbench"
echo "================================================="
echo

# Check prerequisites
log "Checking prerequisites..."

# Check if gcloud CLI is installed
if ! command -v gcloud &> /dev/null; then
    error_exit "Google Cloud CLI (gcloud) is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
fi

# Check if bq CLI is installed
if ! command -v bq &> /dev/null; then
    error_exit "BigQuery CLI (bq) is not installed. Please install it with 'gcloud components install bq'"
fi

# Check if gsutil is installed
if ! command -v gsutil &> /dev/null; then
    error_exit "Cloud Storage CLI (gsutil) is not installed. Please install it with 'gcloud components install gsutil'"
fi

# Check if authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    error_exit "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
fi

log_success "Prerequisites check completed"

# Load environment variables from deployment
if [[ -f ".deployment_vars" ]]; then
    log "Loading deployment variables from .deployment_vars..."
    source .deployment_vars
else
    log_warning "No .deployment_vars file found. You may need to set environment variables manually."
    
    # Prompt for required variables if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        read -p "Enter Project ID: " PROJECT_ID
        export PROJECT_ID
    fi
    
    if [[ -z "${REGION:-}" ]]; then
        export REGION="us-central1"
    fi
    
    if [[ -z "${ZONE:-}" ]]; then
        export ZONE="us-central1-a"
    fi
fi

# Validate required variables
if [[ -z "${PROJECT_ID:-}" ]]; then
    error_exit "PROJECT_ID is not set. Cannot proceed with cleanup."
fi

# Set default project
gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"

log "Cleanup configuration:"
log "  Project ID: ${PROJECT_ID}"
log "  Region: ${REGION:-us-central1}"
log "  Zone: ${ZONE:-us-central1-a}"

# Show confirmation prompt
confirm_destruction

# Start cleanup process
log "Starting resource cleanup process..."

# Track cleanup progress
CLEANUP_SUCCESS=0
CLEANUP_TOTAL=5

# 1. Cancel and delete running Batch jobs
if [[ -n "${JOB_NAME:-}" ]]; then
    log "Canceling and deleting Cloud Batch job: ${JOB_NAME}..."
    
    # First try to cancel the job if it's running
    JOB_STATE=$(gcloud batch jobs describe "${JOB_NAME}" \
        --location="${REGION:-us-central1}" \
        --format="value(status.state)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "${JOB_STATE}" != "NOT_FOUND" ]]; then
        if [[ "${JOB_STATE}" == "RUNNING" ]] || [[ "${JOB_STATE}" == "PENDING" ]]; then
            log "Job is ${JOB_STATE}, canceling first..."
            gcloud batch jobs delete "${JOB_NAME}" \
                --location="${REGION:-us-central1}" \
                --quiet 2>/dev/null || log_warning "Failed to cancel batch job"
        else
            log "Job is ${JOB_STATE}, deleting..."
            gcloud batch jobs delete "${JOB_NAME}" \
                --location="${REGION:-us-central1}" \
                --quiet 2>/dev/null || log_warning "Failed to delete batch job"
        fi
        log_success "Cloud Batch job cleanup completed"
    else
        log "Batch job ${JOB_NAME} not found or already deleted"
    fi
    ((CLEANUP_SUCCESS++))
else
    log "No Batch job name provided, skipping..."
    ((CLEANUP_SUCCESS++))
fi

# 2. Delete Vertex AI Workbench instance
if [[ -n "${WORKBENCH_NAME:-}" ]]; then
    log "Deleting Vertex AI Workbench instance: ${WORKBENCH_NAME}..."
    
    # Check if instance exists
    if gcloud notebooks instances describe "${WORKBENCH_NAME}" --location="${ZONE:-us-central1-a}" &> /dev/null; then
        gcloud notebooks instances delete "${WORKBENCH_NAME}" \
            --location="${ZONE:-us-central1-a}" \
            --quiet || log_warning "Failed to delete Workbench instance"
        
        # Wait for deletion to complete
        log "Waiting for Workbench instance deletion to complete..."
        while gcloud notebooks instances describe "${WORKBENCH_NAME}" --location="${ZONE:-us-central1-a}" &> /dev/null; do
            log "Still deleting..."
            sleep 30
        done
        
        log_success "Vertex AI Workbench instance deleted"
    else
        log "Workbench instance ${WORKBENCH_NAME} not found or already deleted"
    fi
    ((CLEANUP_SUCCESS++))
else
    log "No Workbench instance name provided, skipping..."
    ((CLEANUP_SUCCESS++))
fi

# 3. Delete BigQuery dataset and all tables
if [[ -n "${DATASET_NAME:-}" ]]; then
    log "Deleting BigQuery dataset: ${DATASET_NAME}..."
    
    # Check if dataset exists
    if bq show --project_id="${PROJECT_ID}" "${DATASET_NAME}" &> /dev/null; then
        bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" || log_warning "Failed to delete BigQuery dataset"
        log_success "BigQuery dataset deleted"
    else
        log "BigQuery dataset ${DATASET_NAME} not found or already deleted"
    fi
    ((CLEANUP_SUCCESS++))
else
    log "No BigQuery dataset name provided, skipping..."
    ((CLEANUP_SUCCESS++))
fi

# 4. Delete Cloud Storage bucket and all contents
if [[ -n "${BUCKET_NAME:-}" ]]; then
    log "Deleting Cloud Storage bucket: ${BUCKET_NAME}..."
    
    # Check if bucket exists
    if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        # Remove all objects first
        log "Removing all objects from bucket..."
        gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true
        
        # Remove the bucket
        gsutil rb "gs://${BUCKET_NAME}" || log_warning "Failed to delete storage bucket"
        log_success "Cloud Storage bucket deleted"
    else
        log "Storage bucket ${BUCKET_NAME} not found or already deleted"
    fi
    ((CLEANUP_SUCCESS++))
else
    log "No storage bucket name provided, skipping..."
    ((CLEANUP_SUCCESS++))
fi

# 5. Clean up local files
log "Cleaning up local files..."

# Remove temporary files created during deployment
LOCAL_FILES=(
    "genomic_pipeline.py"
    "batch_job_config.json"
    "genomic_ml_analysis.ipynb"
    "process_results.py"
    ".deployment_vars"
)

for file in "${LOCAL_FILES[@]}"; do
    if [[ -f "${file}" ]]; then
        rm -f "${file}"
        log "Removed local file: ${file}"
    fi
done

log_success "Local files cleaned up"
((CLEANUP_SUCCESS++))

# Optional: Delete the entire project (uncomment if desired)
# WARNING: This will delete ALL resources in the project
log_warning "Project deletion is available but not automated for safety"
echo "To delete the entire project, run:"
echo "  gcloud projects delete ${PROJECT_ID}"
echo

# Display cleanup summary
echo
echo "================================================="
echo "           CLEANUP COMPLETED"
echo "================================================="
echo

if [[ ${CLEANUP_SUCCESS} -eq ${CLEANUP_TOTAL} ]]; then
    log_success "All cleanup operations completed successfully! (${CLEANUP_SUCCESS}/${CLEANUP_TOTAL})"
    echo "🎉 Scientific Workflow Orchestration infrastructure has been removed"
else
    log_warning "Cleanup completed with some issues (${CLEANUP_SUCCESS}/${CLEANUP_TOTAL} successful)"
    echo "⚠️  Please check the warnings above and manually verify resource removal"
fi

echo
echo "Cleanup Summary:"
echo "  ✅ Cloud Batch jobs: Cancelled and deleted"
echo "  ✅ Vertex AI Workbench: Deleted"
echo "  ✅ BigQuery dataset: Deleted"
echo "  ✅ Cloud Storage bucket: Deleted"
echo "  ✅ Local files: Cleaned up"
echo

# Cost savings summary
echo "💰 Monthly Cost Savings:"
echo "  - Vertex AI Workbench: ~\$150/month saved"
echo "  - Cloud Storage: ~\$0.02/GB/month saved"
echo "  - BigQuery: ~\$0.02/GB/month saved"
echo "  - Cloud Batch: Variable savings based on usage"
echo

# Check for any remaining resources
echo "🔍 Verification Steps:"
echo "1. Check Cloud Console for any remaining resources:"
echo "   - Batch: https://console.cloud.google.com/batch/jobs?project=${PROJECT_ID}"
echo "   - Workbench: https://console.cloud.google.com/ai-platform/notebooks/instances?project=${PROJECT_ID}"
echo "   - BigQuery: https://console.cloud.google.com/bigquery?project=${PROJECT_ID}"
echo "   - Storage: https://console.cloud.google.com/storage/browser?project=${PROJECT_ID}"
echo
echo "2. Review billing dashboard to confirm charges have stopped:"
echo "   - Billing: https://console.cloud.google.com/billing?project=${PROJECT_ID}"
echo

# Final security reminder
echo "🔒 Security Reminder:"
echo "- Review IAM permissions if this was a shared project"
echo "- Check for any API keys or service accounts that may need removal"
echo "- Review audit logs for any unexpected access patterns"
echo

echo "================================================="
log_success "Cleanup script completed!"
echo "================================================="

exit 0