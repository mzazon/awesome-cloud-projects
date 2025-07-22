#!/bin/bash
set -euo pipefail

# Data Pipeline Automation with BigQuery Continuous Queries and Cloud KMS
# Cleanup/Destroy Script
# 
# This script removes all resources created by the deployment script.
# CAUTION: This will permanently delete all data and configurations.

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if bq CLI is installed
    if ! command -v bq &> /dev/null; then
        error "BigQuery CLI (bq) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "Google Cloud Storage CLI (gsutil) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 > /dev/null; then
        error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    success "All prerequisites satisfied"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to get current project from gcloud config
    if [ -z "${PROJECT_ID:-}" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [ -z "${PROJECT_ID}" ]; then
            error "PROJECT_ID not set and cannot get from gcloud config. Please set PROJECT_ID environment variable."
            exit 1
        fi
    fi
    
    # Set default values for other variables
    export REGION="${REGION:-us-central1}"
    export DATASET_ID="${DATASET_ID:-streaming_analytics}"
    export KEYRING_NAME="${KEYRING_NAME:-pipeline-keyring}"
    export KEY_NAME="${KEY_NAME:-data-encryption-key}"
    
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Dataset ID: ${DATASET_ID}"
    log "KMS Key Ring: ${KEYRING_NAME}"
    log "KMS Key: ${KEY_NAME}"
    
    # Set project context
    gcloud config set project "${PROJECT_ID}" || {
        error "Failed to set project ${PROJECT_ID}"
        exit 1
    }
    
    success "Environment variables loaded"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warning "⚠️  DANGER: This will permanently delete ALL resources created by the data pipeline deployment!"
    echo ""
    echo "This includes:"
    echo "- BigQuery datasets and all data"
    echo "- Cloud KMS keys (scheduled for destruction)"
    echo "- Cloud Storage buckets and all contents"
    echo "- Pub/Sub topics and subscriptions"
    echo "- Cloud Functions"
    echo "- Cloud Scheduler jobs"
    echo "- Logging metrics and sinks"
    echo ""
    warning "This action CANNOT be undone!"
    echo ""
    
    if [ "${FORCE_DELETE:-}" = "true" ]; then
        warning "FORCE_DELETE is set to true. Proceeding without confirmation..."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    if [ "${confirmation}" != "DELETE" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    warning "Proceeding with resource deletion..."
}

# Function to stop and remove continuous queries
stop_continuous_queries() {
    log "Stopping BigQuery continuous queries..."
    
    # List all jobs with the pattern and cancel them
    local jobs
    jobs=$(bq ls -j --max_results=1000 --format=csv | grep -E "real-time-processor-[a-f0-9]{6}" | cut -d',' -f1 || true)
    
    if [ -n "${jobs}" ]; then
        for job in ${jobs}; do
            log "Cancelling continuous query job: ${job}"
            if bq cancel "${job}" 2>/dev/null; then
                success "Cancelled job: ${job}"
            else
                warning "Failed to cancel job: ${job} (may already be completed)"
            fi
        done
    else
        log "No continuous query jobs found to cancel"
    fi
    
    # Try to cancel specific job if CONTINUOUS_QUERY_JOB is set
    if [ -n "${CONTINUOUS_QUERY_JOB:-}" ]; then
        log "Attempting to cancel specific job: ${CONTINUOUS_QUERY_JOB}"
        if bq cancel "${CONTINUOUS_QUERY_JOB}" 2>/dev/null; then
            success "Cancelled continuous query: ${CONTINUOUS_QUERY_JOB}"
        else
            warning "Job ${CONTINUOUS_QUERY_JOB} not found or already completed"
        fi
    fi
    
    success "Continuous queries stopped"
}

# Function to remove BigQuery resources
remove_bigquery_resources() {
    log "Removing BigQuery resources..."
    
    # Remove dataset and all tables
    if bq show "${PROJECT_ID}:${DATASET_ID}" &> /dev/null; then
        log "Deleting BigQuery dataset: ${DATASET_ID}"
        if bq rm -r -f "${PROJECT_ID}:${DATASET_ID}"; then
            success "Deleted BigQuery dataset: ${DATASET_ID}"
        else
            error "Failed to delete BigQuery dataset: ${DATASET_ID}"
        fi
    else
        log "BigQuery dataset ${DATASET_ID} not found, skipping"
    fi
    
    success "BigQuery resources removed"
}

# Function to remove Cloud Functions
remove_cloud_functions() {
    log "Removing Cloud Functions..."
    
    local functions=("security-audit" "encrypt-sensitive-data")
    
    for func in "${functions[@]}"; do
        if gcloud functions describe "${func}" --region="${REGION}" &> /dev/null; then
            log "Deleting Cloud Function: ${func}"
            if gcloud functions delete "${func}" --region="${REGION}" --quiet; then
                success "Deleted Cloud Function: ${func}"
            else
                error "Failed to delete Cloud Function: ${func}"
            fi
        else
            log "Cloud Function ${func} not found, skipping"
        fi
    done
    
    success "Cloud Functions removed"
}

# Function to remove Cloud Scheduler jobs
remove_scheduler_jobs() {
    log "Removing Cloud Scheduler jobs..."
    
    local jobs=("security-audit-daily")
    
    for job in "${jobs[@]}"; do
        if gcloud scheduler jobs describe "${job}" --location="${REGION}" &> /dev/null; then
            log "Deleting Cloud Scheduler job: ${job}"
            if gcloud scheduler jobs delete "${job}" --location="${REGION}" --quiet; then
                success "Deleted Cloud Scheduler job: ${job}"
            else
                error "Failed to delete Cloud Scheduler job: ${job}"
            fi
        else
            log "Cloud Scheduler job ${job} not found, skipping"
        fi
    done
    
    success "Cloud Scheduler jobs removed"
}

# Function to remove Pub/Sub resources
remove_pubsub_resources() {
    log "Removing Pub/Sub resources..."
    
    # Find topics with the pattern
    local topics
    topics=$(gcloud pubsub topics list --format="value(name)" | grep -E "streaming-events-[a-f0-9]{6}" || true)
    
    # Add DLQ topics
    local dlq_topics
    dlq_topics=$(gcloud pubsub topics list --format="value(name)" | grep -E "streaming-events-[a-f0-9]{6}-dlq" || true)
    
    # Combine all topics
    local all_topics="${topics} ${dlq_topics}"
    
    # Remove subscriptions first
    for topic in ${all_topics}; do
        if [ -n "${topic}" ]; then
            local topic_name
            topic_name=$(basename "${topic}")
            
            # List and delete subscriptions for this topic
            local subscriptions
            subscriptions=$(gcloud pubsub subscriptions list --format="value(name)" | grep "${topic_name}" || true)
            
            for sub in ${subscriptions}; do
                if [ -n "${sub}" ]; then
                    local sub_name
                    sub_name=$(basename "${sub}")
                    log "Deleting Pub/Sub subscription: ${sub_name}"
                    if gcloud pubsub subscriptions delete "${sub_name}" --quiet; then
                        success "Deleted subscription: ${sub_name}"
                    else
                        error "Failed to delete subscription: ${sub_name}"
                    fi
                fi
            done
        fi
    done
    
    # Remove topics
    for topic in ${all_topics}; do
        if [ -n "${topic}" ]; then
            local topic_name
            topic_name=$(basename "${topic}")
            log "Deleting Pub/Sub topic: ${topic_name}"
            if gcloud pubsub topics delete "${topic_name}" --quiet; then
                success "Deleted topic: ${topic_name}"
            else
                error "Failed to delete topic: ${topic_name}"
            fi
        fi
    done
    
    # Try to delete specific topics if environment variables are set
    if [ -n "${PUBSUB_TOPIC:-}" ]; then
        # Delete subscription first
        local sub_name="${PUBSUB_TOPIC}-bq-sub"
        if gcloud pubsub subscriptions describe "${sub_name}" &> /dev/null; then
            log "Deleting specific subscription: ${sub_name}"
            gcloud pubsub subscriptions delete "${sub_name}" --quiet || true
        fi
        
        # Delete main topic
        if gcloud pubsub topics describe "${PUBSUB_TOPIC}" &> /dev/null; then
            log "Deleting specific topic: ${PUBSUB_TOPIC}"
            gcloud pubsub topics delete "${PUBSUB_TOPIC}" --quiet || true
        fi
        
        # Delete DLQ topic
        local dlq_topic="${PUBSUB_TOPIC}-dlq"
        if gcloud pubsub topics describe "${dlq_topic}" &> /dev/null; then
            log "Deleting DLQ topic: ${dlq_topic}"
            gcloud pubsub topics delete "${dlq_topic}" --quiet || true
        fi
    fi
    
    success "Pub/Sub resources removed"
}

# Function to remove Cloud Storage buckets
remove_storage_buckets() {
    log "Removing Cloud Storage buckets..."
    
    # Find buckets with the pattern
    local buckets
    buckets=$(gsutil ls -p "${PROJECT_ID}" | grep -E "gs://pipeline-data-[a-f0-9]{6}/" || true)
    
    for bucket in ${buckets}; do
        if [ -n "${bucket}" ]; then
            local bucket_name
            bucket_name=$(echo "${bucket}" | sed 's|gs://||' | sed 's|/||')
            log "Deleting Cloud Storage bucket: ${bucket_name}"
            if gsutil -m rm -r "gs://${bucket_name}"; then
                success "Deleted bucket: ${bucket_name}"
            else
                error "Failed to delete bucket: ${bucket_name}"
            fi
        fi
    done
    
    # Try to delete specific bucket if environment variable is set
    if [ -n "${BUCKET_NAME:-}" ]; then
        if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
            log "Deleting specific bucket: ${BUCKET_NAME}"
            if gsutil -m rm -r "gs://${BUCKET_NAME}"; then
                success "Deleted specific bucket: ${BUCKET_NAME}"
            else
                error "Failed to delete specific bucket: ${BUCKET_NAME}"
            fi
        fi
    fi
    
    success "Cloud Storage buckets removed"
}

# Function to remove monitoring resources
remove_monitoring_resources() {
    log "Removing monitoring resources..."
    
    # Remove log-based metrics
    local metrics=("kms_key_usage" "continuous_query_performance")
    
    for metric in "${metrics[@]}"; do
        if gcloud logging metrics describe "${metric}" &> /dev/null; then
            log "Deleting logging metric: ${metric}"
            if gcloud logging metrics delete "${metric}" --quiet; then
                success "Deleted metric: ${metric}"
            else
                error "Failed to delete metric: ${metric}"
            fi
        else
            log "Logging metric ${metric} not found, skipping"
        fi
    done
    
    # Remove log sinks
    local sinks=("security-audit-sink")
    
    for sink in "${sinks[@]}"; do
        if gcloud logging sinks describe "${sink}" &> /dev/null; then
            log "Deleting logging sink: ${sink}"
            if gcloud logging sinks delete "${sink}" --quiet; then
                success "Deleted sink: ${sink}"
            else
                error "Failed to delete sink: ${sink}"
            fi
        else
            log "Logging sink ${sink} not found, skipping"
        fi
    done
    
    success "Monitoring resources removed"
}

# Function to schedule KMS key deletion
schedule_kms_deletion() {
    log "Scheduling KMS keys for deletion..."
    
    # KMS keys cannot be immediately deleted; they must be scheduled for destruction
    local keys=("${KEY_NAME}" "${KEY_NAME}-column")
    
    for key in "${keys[@]}"; do
        if gcloud kms keys describe "${key}" --location="${REGION}" --keyring="${KEYRING_NAME}" &> /dev/null; then
            log "Scheduling key for deletion: ${key}"
            
            # Get all key versions and destroy them
            local versions
            versions=$(gcloud kms keys versions list --key="${key}" --location="${REGION}" --keyring="${KEYRING_NAME}" --format="value(name)" | grep -o '[0-9]*$' || true)
            
            for version in ${versions}; do
                if [ -n "${version}" ]; then
                    log "Destroying key version: ${key}/versions/${version}"
                    if gcloud kms keys versions destroy "${version}" \
                        --location="${REGION}" \
                        --keyring="${KEYRING_NAME}" \
                        --key="${key}" \
                        --quiet; then
                        success "Scheduled destruction for key version: ${key}/versions/${version}"
                    else
                        warning "Failed to schedule destruction for key version: ${key}/versions/${version}"
                    fi
                fi
            done
        else
            log "KMS key ${key} not found, skipping"
        fi
    done
    
    warning "KMS keys have been scheduled for deletion. They will be permanently destroyed after the retention period."
    warning "Note: KMS key rings cannot be deleted and will remain (they don't incur charges)."
    
    success "KMS key deletion scheduled"
}

# Function to remove local files
remove_local_files() {
    log "Removing local temporary files..."
    
    local files=(
        "continuous_query.sql"
        "alert_policy.yaml"
    )
    
    local dirs=(
        "security-audit-function"
        "encryption-function"
    )
    
    # Remove files
    for file in "${files[@]}"; do
        if [ -f "${file}" ]; then
            log "Removing file: ${file}"
            rm -f "${file}"
            success "Removed file: ${file}"
        fi
    done
    
    # Remove directories
    for dir in "${dirs[@]}"; do
        if [ -d "${dir}" ]; then
            log "Removing directory: ${dir}"
            rm -rf "${dir}"
            success "Removed directory: ${dir}"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check BigQuery dataset
    if bq show "${PROJECT_ID}:${DATASET_ID}" &> /dev/null; then
        error "BigQuery dataset ${DATASET_ID} still exists"
        ((cleanup_errors++))
    fi
    
    # Check Cloud Functions
    local functions=("security-audit" "encrypt-sensitive-data")
    for func in "${functions[@]}"; do
        if gcloud functions describe "${func}" --region="${REGION}" &> /dev/null; then
            error "Cloud Function ${func} still exists"
            ((cleanup_errors++))
        fi
    done
    
    # Check Cloud Scheduler jobs
    if gcloud scheduler jobs describe security-audit-daily --location="${REGION}" &> /dev/null; then
        error "Cloud Scheduler job security-audit-daily still exists"
        ((cleanup_errors++))
    fi
    
    # Check monitoring metrics
    local metrics=("kms_key_usage" "continuous_query_performance")
    for metric in "${metrics[@]}"; do
        if gcloud logging metrics describe "${metric}" &> /dev/null; then
            error "Logging metric ${metric} still exists"
            ((cleanup_errors++))
        fi
    done
    
    if [ ${cleanup_errors} -eq 0 ]; then
        success "Cleanup verification passed - all resources removed successfully"
    else
        error "Cleanup verification found ${cleanup_errors} remaining resources"
        warning "Some resources may need manual cleanup"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo ""
    echo "✅ Removed Resources:"
    echo "   - BigQuery dataset and tables"
    echo "   - Cloud Functions"
    echo "   - Cloud Scheduler jobs"
    echo "   - Pub/Sub topics and subscriptions"
    echo "   - Cloud Storage buckets"
    echo "   - Logging metrics and sinks"
    echo "   - Local temporary files"
    echo ""
    echo "⏳ Scheduled for Deletion:"
    echo "   - KMS keys (will be destroyed after retention period)"
    echo ""
    echo "ℹ️  Remaining Resources:"
    echo "   - KMS key ring (cannot be deleted, no charges)"
    echo "   - Enabled APIs (left enabled for other resources)"
    echo ""
    warning "Important Notes:"
    echo "1. KMS keys are scheduled for destruction and will be permanently deleted after the retention period"
    echo "2. The KMS key ring cannot be deleted but does not incur charges"
    echo "3. If you need to recreate resources, you may need to use different names for some resources"
    echo ""
    success "Data pipeline cleanup completed!"
}

# Main cleanup function
main() {
    log "Starting Data Pipeline Automation cleanup..."
    
    check_prerequisites
    load_environment
    confirm_deletion
    stop_continuous_queries
    remove_bigquery_resources
    remove_cloud_functions
    remove_scheduler_jobs
    remove_pubsub_resources
    remove_storage_buckets
    remove_monitoring_resources
    schedule_kms_deletion
    remove_local_files
    verify_cleanup
    display_cleanup_summary
    
    success "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup interrupted"; exit 1' INT TERM

# Run main function
main "$@"