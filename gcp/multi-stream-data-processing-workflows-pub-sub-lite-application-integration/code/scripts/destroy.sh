#!/bin/bash

# Multi-Stream Data Processing Workflows with Pub/Sub Lite and Application Integration
# Cleanup/Destroy Script for GCP
# This script removes all resources created by the deployment script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "gcloud is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
}

# Function to prompt for confirmation
confirm_destruction() {
    echo -e "${YELLOW}WARNING: This will permanently delete all resources created by the deployment script.${NC}"
    echo -e "${YELLOW}This action cannot be undone.${NC}"
    echo ""
    echo "Resources to be deleted:"
    echo "  - Pub/Sub Lite topics and subscriptions"
    echo "  - BigQuery dataset and all tables"
    echo "  - Cloud Storage bucket and all contents"
    echo "  - Service account and IAM bindings"
    echo "  - Monitoring dashboards and alerting policies"
    echo "  - Application Integration configurations"
    echo ""
    
    if [ "${FORCE_DESTROY:-false}" = "true" ]; then
        warn "FORCE_DESTROY is set to true, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if required commands exist
    local required_commands=("gcloud" "bq" "gsutil")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            error "Required command '$cmd' not found. Please install it first."
            exit 1
        fi
    done
    
    # Check gcloud authentication
    check_gcloud_auth
    
    log "Prerequisites check completed successfully"
}

# Function to load environment variables
load_environment() {
    info "Loading environment variables..."
    
    # Check if .env file exists
    if [ -f ".env" ]; then
        info "Loading environment variables from .env file..."
        source .env
    else
        warn ".env file not found. Trying to use environment variables..."
    fi
    
    # Check if required environment variables are set
    local required_vars=("PROJECT_ID" "REGION" "RANDOM_SUFFIX")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            error "Required environment variable $var is not set"
            error "Please ensure the deployment was completed successfully or set the variable manually"
            exit 1
        fi
    done
    
    # Set derived variables if not already set
    export LITE_TOPIC_1="${LITE_TOPIC_1:-iot-data-stream-${RANDOM_SUFFIX}}"
    export LITE_TOPIC_2="${LITE_TOPIC_2:-app-events-stream-${RANDOM_SUFFIX}}"
    export LITE_TOPIC_3="${LITE_TOPIC_3:-system-logs-stream-${RANDOM_SUFFIX}}"
    export SUBSCRIPTION_PREFIX="${SUBSCRIPTION_PREFIX:-analytics-sub-${RANDOM_SUFFIX}}"
    export DATASET_NAME="${DATASET_NAME:-streaming_analytics_${RANDOM_SUFFIX}}"
    export BUCKET_NAME="${BUCKET_NAME:-data-lake-${PROJECT_ID}-${RANDOM_SUFFIX}}"
    export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-app-integration-sa-${RANDOM_SUFFIX}}"
    
    # Set gcloud defaults
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    
    info "Environment variables loaded:"
    info "  PROJECT_ID: $PROJECT_ID"
    info "  REGION: $REGION"
    info "  RANDOM_SUFFIX: $RANDOM_SUFFIX"
    
    log "Environment setup completed"
}

# Function to stop any running Dataflow jobs
stop_dataflow_jobs() {
    info "Stopping any running Dataflow jobs..."
    
    # List and stop running jobs
    local running_jobs
    running_jobs=$(gcloud dataflow jobs list \
        --region="$REGION" \
        --status=running \
        --format="value(id)" \
        --filter="name:*${RANDOM_SUFFIX}*" 2>/dev/null || true)
    
    if [ -n "$running_jobs" ]; then
        info "Found running Dataflow jobs, stopping them..."
        for job_id in $running_jobs; do
            info "Stopping Dataflow job: $job_id"
            gcloud dataflow jobs cancel "$job_id" --region="$REGION" || warn "Failed to stop job $job_id"
        done
        
        # Wait for jobs to stop
        info "Waiting for Dataflow jobs to stop..."
        sleep 60
    else
        info "No running Dataflow jobs found"
    fi
    
    log "Dataflow jobs stopped"
}

# Function to delete Pub/Sub Lite subscriptions
delete_pubsub_lite_subscriptions() {
    info "Deleting Pub/Sub Lite subscriptions..."
    
    local subscriptions=(
        "${SUBSCRIPTION_PREFIX}-analytics-1"
        "${SUBSCRIPTION_PREFIX}-analytics-2"
        "${SUBSCRIPTION_PREFIX}-analytics-3"
        "${SUBSCRIPTION_PREFIX}-workflow-1"
        "${SUBSCRIPTION_PREFIX}-workflow-2"
    )
    
    for sub in "${subscriptions[@]}"; do
        info "Deleting subscription: $sub"
        if gcloud pubsub lite-subscriptions delete "$sub" --location="$REGION" --quiet; then
            log "Deleted subscription: $sub"
        else
            warn "Failed to delete subscription: $sub (may not exist)"
        fi
    done
    
    log "Pub/Sub Lite subscriptions deletion completed"
}

# Function to delete Pub/Sub Lite topics
delete_pubsub_lite_topics() {
    info "Deleting Pub/Sub Lite topics..."
    
    local topics=("$LITE_TOPIC_1" "$LITE_TOPIC_2" "$LITE_TOPIC_3")
    
    for topic in "${topics[@]}"; do
        info "Deleting topic: $topic"
        if gcloud pubsub lite-topics delete "$topic" --location="$REGION" --quiet; then
            log "Deleted topic: $topic"
        else
            warn "Failed to delete topic: $topic (may not exist)"
        fi
    done
    
    log "Pub/Sub Lite topics deletion completed"
}

# Function to delete BigQuery dataset
delete_bigquery_dataset() {
    info "Deleting BigQuery dataset: $DATASET_NAME"
    
    # Check if dataset exists
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        info "Dataset exists, deleting with all tables..."
        if bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}"; then
            log "Deleted BigQuery dataset: $DATASET_NAME"
        else
            error "Failed to delete BigQuery dataset: $DATASET_NAME"
            exit 1
        fi
    else
        warn "BigQuery dataset $DATASET_NAME does not exist, skipping deletion"
    fi
    
    log "BigQuery dataset deletion completed"
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    info "Deleting Cloud Storage bucket: $BUCKET_NAME"
    
    # Check if bucket exists
    if gsutil ls "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        info "Bucket exists, deleting with all contents..."
        if gsutil -m rm -r "gs://$BUCKET_NAME"; then
            log "Deleted Cloud Storage bucket: $BUCKET_NAME"
        else
            error "Failed to delete Cloud Storage bucket: $BUCKET_NAME"
            exit 1
        fi
    else
        warn "Cloud Storage bucket $BUCKET_NAME does not exist, skipping deletion"
    fi
    
    log "Cloud Storage bucket deletion completed"
}

# Function to delete service account and IAM bindings
delete_service_account() {
    info "Deleting service account and IAM bindings..."
    
    local service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "$service_account_email" >/dev/null 2>&1; then
        info "Service account exists, removing IAM bindings..."
        
        # Remove IAM bindings
        local roles=(
            "roles/pubsublite.editor"
            "roles/bigquery.dataEditor"
            "roles/storage.objectAdmin"
            "roles/dataflow.developer"
            "roles/monitoring.metricWriter"
            "roles/logging.logWriter"
        )
        
        for role in "${roles[@]}"; do
            info "Removing IAM binding for role: $role"
            gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$service_account_email" \
                --role="$role" || warn "Failed to remove IAM binding for role: $role"
        done
        
        # Delete service account
        info "Deleting service account: $SERVICE_ACCOUNT_NAME"
        if gcloud iam service-accounts delete "$service_account_email" --quiet; then
            log "Deleted service account: $SERVICE_ACCOUNT_NAME"
        else
            error "Failed to delete service account: $SERVICE_ACCOUNT_NAME"
            exit 1
        fi
    else
        warn "Service account $SERVICE_ACCOUNT_NAME does not exist, skipping deletion"
    fi
    
    log "Service account deletion completed"
}

# Function to delete monitoring dashboards
delete_monitoring_dashboards() {
    info "Deleting monitoring dashboards..."
    
    # List and delete dashboards with our naming pattern
    local dashboards
    dashboards=$(gcloud monitoring dashboards list \
        --format="value(name)" \
        --filter="displayName:*Multi-Stream Data Processing*" 2>/dev/null || true)
    
    if [ -n "$dashboards" ]; then
        for dashboard in $dashboards; do
            info "Deleting dashboard: $dashboard"
            gcloud monitoring dashboards delete "$dashboard" --quiet || warn "Failed to delete dashboard: $dashboard"
        done
        log "Monitoring dashboards deleted"
    else
        info "No monitoring dashboards found to delete"
    fi
    
    log "Monitoring dashboards deletion completed"
}

# Function to delete alerting policies
delete_alerting_policies() {
    info "Deleting alerting policies..."
    
    # List and delete alerting policies with our naming pattern
    local policies
    policies=$(gcloud alpha monitoring policies list \
        --format="value(name)" \
        --filter="displayName:*Pub/Sub Lite*" 2>/dev/null || true)
    
    if [ -n "$policies" ]; then
        for policy in $policies; do
            info "Deleting alerting policy: $policy"
            gcloud alpha monitoring policies delete "$policy" --quiet || warn "Failed to delete alerting policy: $policy"
        done
        log "Alerting policies deleted"
    else
        info "No alerting policies found to delete"
    fi
    
    log "Alerting policies deletion completed"
}

# Function to clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        ".env"
        "generate-test-data.py"
        "monitoring-dashboard.json"
        "alerting-policy.json"
        "pubsub-lite-to-bigquery-template.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            info "Removing file: $file"
            rm -f "$file"
        fi
    done
    
    log "Local files cleanup completed"
}

# Function to verify resource deletion
verify_resource_deletion() {
    info "Verifying resource deletion..."
    
    local verification_errors=0
    
    # Check Pub/Sub Lite topics
    info "Checking Pub/Sub Lite topics..."
    for topic in "$LITE_TOPIC_1" "$LITE_TOPIC_2" "$LITE_TOPIC_3"; do
        if gcloud pubsub lite-topics describe "$topic" --location="$REGION" >/dev/null 2>&1; then
            warn "Pub/Sub Lite topic $topic still exists"
            verification_errors=$((verification_errors + 1))
        fi
    done
    
    # Check BigQuery dataset
    info "Checking BigQuery dataset..."
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        warn "BigQuery dataset $DATASET_NAME still exists"
        verification_errors=$((verification_errors + 1))
    fi
    
    # Check Cloud Storage bucket
    info "Checking Cloud Storage bucket..."
    if gsutil ls "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        warn "Cloud Storage bucket $BUCKET_NAME still exists"
        verification_errors=$((verification_errors + 1))
    fi
    
    # Check service account
    info "Checking service account..."
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" >/dev/null 2>&1; then
        warn "Service account $SERVICE_ACCOUNT_NAME still exists"
        verification_errors=$((verification_errors + 1))
    fi
    
    if [ $verification_errors -eq 0 ]; then
        log "All resources have been successfully deleted"
    else
        warn "$verification_errors resource(s) may still exist. Please check manually."
    fi
    
    log "Resource deletion verification completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    info "Cleanup Summary:"
    echo "==========================================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Deleted Resources:"
    echo "  ✓ Pub/Sub Lite topics and subscriptions"
    echo "  ✓ BigQuery dataset and tables"
    echo "  ✓ Cloud Storage bucket and contents"
    echo "  ✓ Service account and IAM bindings"
    echo "  ✓ Monitoring dashboards and alerting policies"
    echo "  ✓ Local configuration files"
    echo ""
    echo "Cleanup completed successfully!"
    echo ""
    echo "Note: If you created a dedicated project for this recipe,"
    echo "you may want to delete the entire project to ensure"
    echo "all resources and billing are completely removed:"
    echo "  gcloud projects delete $PROJECT_ID"
    echo "==========================================="
}

# Function to handle script interruption
handle_interruption() {
    warn "Cleanup interrupted by user"
    echo ""
    warn "Some resources may not have been deleted."
    warn "Please run the script again to complete cleanup."
    exit 1
}

# Main cleanup function
main() {
    log "Starting Multi-Stream Data Processing Workflows cleanup..."
    
    # Set up signal handlers
    trap handle_interruption INT TERM
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_destruction
    
    info "Beginning resource cleanup..."
    
    # Stop any running jobs first
    stop_dataflow_jobs
    
    # Delete resources in reverse order of creation
    delete_pubsub_lite_subscriptions
    delete_pubsub_lite_topics
    delete_bigquery_dataset
    delete_storage_bucket
    delete_service_account
    delete_monitoring_dashboards
    delete_alerting_policies
    cleanup_local_files
    
    # Verify cleanup
    verify_resource_deletion
    
    log "Cleanup completed successfully!"
    display_cleanup_summary
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --force    Skip confirmation prompts"
            echo "  --help     Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  PROJECT_ID       GCP project ID (required)"
            echo "  REGION          GCP region (default: us-central1)"
            echo "  RANDOM_SUFFIX   Resource suffix (loaded from .env)"
            echo ""
            echo "Examples:"
            echo "  $0              # Interactive cleanup"
            echo "  $0 --force      # Automated cleanup"
            echo ""
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"