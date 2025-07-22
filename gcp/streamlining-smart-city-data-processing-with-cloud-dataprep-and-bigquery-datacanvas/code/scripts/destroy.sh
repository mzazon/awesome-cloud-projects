#!/bin/bash

# destroy.sh - Cleanup script for Smart City Data Processing with Cloud Dataprep and BigQuery DataCanvas
# This script safely removes all resources created by the deployment script

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

# Default configuration (these should match deploy.sh values)
DATASET_NAME="smart_city_analytics"
PUBSUB_TOPIC_TRAFFIC="traffic-sensor-data"
PUBSUB_TOPIC_AIR="air-quality-data"
PUBSUB_TOPIC_ENERGY="energy-consumption-data"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not available."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "Cloud Storage CLI (gsutil) is not available."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to get current project settings
get_project_settings() {
    log "Retrieving current project settings..."
    
    # Get current project
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "No active project found. Please set a project with 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    # Get current region
    REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
    
    log "Current settings:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  DATASET: ${DATASET_NAME}"
}

# Function to confirm destructive action
confirm_destruction() {
    if [[ "${FORCE:-false}" != "true" ]]; then
        echo ""
        log_warning "This will permanently delete all smart city data processing resources in project: ${PROJECT_ID}"
        echo ""
        echo "Resources to be deleted:"
        echo "  - BigQuery dataset: ${DATASET_NAME} (and all tables)"
        echo "  - Cloud Storage buckets starting with: smart-city-data-lake-*"
        echo "  - Pub/Sub topics and subscriptions"
        echo "  - Service accounts: dataprep-service-account"
        echo "  - Log-based metrics"
        echo "  - Any running Dataflow jobs"
        echo ""
        log_warning "This action cannot be undone!"
        echo ""
        
        read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
        if [[ "${confirmation}" != "yes" ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
        
        echo ""
        log "Proceeding with resource cleanup..."
    else
        log "FORCE mode enabled - skipping confirmation"
    fi
}

# Function to list existing resources
list_resources() {
    log "Discovering existing resources to clean up..."
    
    # Find smart city data lake buckets
    log "Scanning for smart city data lake buckets..."
    mapfile -t BUCKETS < <(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "smart-city-data-lake-" | sed 's|gs://||' | sed 's|/||' || true)
    
    if [[ ${#BUCKETS[@]} -gt 0 ]]; then
        log "Found ${#BUCKETS[@]} data lake bucket(s):"
        for bucket in "${BUCKETS[@]}"; do
            log "  - gs://${bucket}"
        done
    else
        log "No smart city data lake buckets found"
    fi
    
    # Check for BigQuery dataset
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        log "Found BigQuery dataset: ${PROJECT_ID}:${DATASET_NAME}"
        DATASET_EXISTS=true
    else
        log "BigQuery dataset not found: ${PROJECT_ID}:${DATASET_NAME}"
        DATASET_EXISTS=false
    fi
    
    # Check for Pub/Sub topics
    EXISTING_TOPICS=()
    local topics=("${PUBSUB_TOPIC_TRAFFIC}" "${PUBSUB_TOPIC_AIR}" "${PUBSUB_TOPIC_ENERGY}")
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe "${topic}" &> /dev/null; then
            EXISTING_TOPICS+=("${topic}")
        fi
    done
    
    if [[ ${#EXISTING_TOPICS[@]} -gt 0 ]]; then
        log "Found ${#EXISTING_TOPICS[@]} Pub/Sub topic(s):"
        for topic in "${EXISTING_TOPICS[@]}"; do
            log "  - ${topic}"
        done
    else
        log "No smart city Pub/Sub topics found"
    fi
}

# Function to stop running Dataflow jobs
stop_dataflow_jobs() {
    log "Checking for running Dataflow jobs..."
    
    # List and stop any running smart city related Dataflow jobs
    local jobs
    jobs=$(gcloud dataflow jobs list --region="${REGION}" --filter="name:smart-city-streaming" --format="value(id)" 2>/dev/null || true)
    
    if [[ -n "${jobs}" ]]; then
        log "Found running Dataflow jobs, stopping them..."
        for job_id in ${jobs}; do
            log "Stopping Dataflow job: ${job_id}"
            if gcloud dataflow jobs cancel "${job_id}" --region="${REGION}" --quiet; then
                log_success "Stopped Dataflow job: ${job_id}"
            else
                log_warning "Failed to stop Dataflow job: ${job_id}"
            fi
        done
        
        # Wait for jobs to stop
        log "Waiting for Dataflow jobs to stop completely..."
        sleep 60
    else
        log "No running smart city Dataflow jobs found"
    fi
    
    log_success "Dataflow jobs cleanup completed"
}

# Function to remove BigQuery resources
cleanup_bigquery() {
    log "Cleaning up BigQuery resources..."
    
    if [[ "${DATASET_EXISTS}" == "true" ]]; then
        # List tables before deletion for logging
        log "Tables in dataset ${DATASET_NAME}:"
        bq ls "${PROJECT_ID}:${DATASET_NAME}" --format="table" 2>/dev/null || true
        
        # Delete the entire dataset (including all tables and views)
        if bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}"; then
            log_success "Deleted BigQuery dataset: ${DATASET_NAME}"
        else
            log_error "Failed to delete BigQuery dataset: ${DATASET_NAME}"
        fi
    else
        log "No BigQuery dataset to clean up"
    fi
    
    log_success "BigQuery cleanup completed"
}

# Function to remove Pub/Sub resources
cleanup_pubsub() {
    log "Cleaning up Pub/Sub resources..."
    
    if [[ ${#EXISTING_TOPICS[@]} -gt 0 ]]; then
        # Delete subscriptions first (to avoid orphaned subscriptions)
        log "Deleting Pub/Sub subscriptions..."
        local subscriptions=("traffic-processing-sub" "air-quality-processing-sub" "energy-processing-sub")
        
        for subscription in "${subscriptions[@]}"; do
            if gcloud pubsub subscriptions describe "${subscription}" &> /dev/null; then
                if gcloud pubsub subscriptions delete "${subscription}" --quiet; then
                    log_success "Deleted subscription: ${subscription}"
                else
                    log_warning "Failed to delete subscription: ${subscription}"
                fi
            fi
        done
        
        # Delete topics
        log "Deleting Pub/Sub topics..."
        for topic in "${EXISTING_TOPICS[@]}"; do
            if gcloud pubsub topics delete "${topic}" --quiet; then
                log_success "Deleted topic: ${topic}"
            else
                log_warning "Failed to delete topic: ${topic}"
            fi
        done
    else
        log "No Pub/Sub resources to clean up"
    fi
    
    log_success "Pub/Sub cleanup completed"
}

# Function to remove Cloud Storage resources
cleanup_storage() {
    log "Cleaning up Cloud Storage resources..."
    
    if [[ ${#BUCKETS[@]} -gt 0 ]]; then
        for bucket in "${BUCKETS[@]}"; do
            log "Deleting bucket and all contents: gs://${bucket}"
            
            # First, remove all objects including versions
            if gsutil -m rm -r "gs://${bucket}/**" 2>/dev/null || true; then
                log "Deleted all objects from bucket: ${bucket}"
            fi
            
            # Remove all object versions (if versioning was enabled)
            if gsutil -m rm -a "gs://${bucket}/**" 2>/dev/null || true; then
                log "Deleted all object versions from bucket: ${bucket}"
            fi
            
            # Delete the bucket itself
            if gsutil rb "gs://${bucket}"; then
                log_success "Deleted bucket: gs://${bucket}"
            else
                log_error "Failed to delete bucket: gs://${bucket}"
            fi
        done
    else
        log "No Cloud Storage buckets to clean up"
    fi
    
    log_success "Cloud Storage cleanup completed"
}

# Function to remove IAM and service accounts
cleanup_iam() {
    log "Cleaning up IAM resources..."
    
    local service_account="dataprep-service-account@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "${service_account}" &> /dev/null; then
        log "Removing IAM policy bindings for service account..."
        
        # Remove IAM policy bindings (ignore errors as they may not exist)
        gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account}" \
            --role="roles/storage.admin" \
            --quiet &> /dev/null || true
        
        gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account}" \
            --role="roles/bigquery.dataEditor" \
            --quiet &> /dev/null || true
        
        gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account}" \
            --role="roles/dataflow.admin" \
            --quiet &> /dev/null || true
        
        # Delete service account
        if gcloud iam service-accounts delete "${service_account}" --quiet; then
            log_success "Deleted service account: ${service_account}"
        else
            log_warning "Failed to delete service account: ${service_account}"
        fi
    else
        log "Service account does not exist: ${service_account}"
    fi
    
    log_success "IAM cleanup completed"
}

# Function to remove monitoring and logging resources
cleanup_monitoring() {
    log "Cleaning up monitoring and logging resources..."
    
    # Remove log-based metrics
    local metrics=("data_quality_errors" "bigquery_job_failures")
    
    for metric in "${metrics[@]}"; do
        if gcloud logging metrics describe "${metric}" &> /dev/null; then
            if gcloud logging metrics delete "${metric}" --quiet; then
                log_success "Deleted log-based metric: ${metric}"
            else
                log_warning "Failed to delete log-based metric: ${metric}"
            fi
        fi
    done
    
    log_success "Monitoring cleanup completed"
}

# Function to clean up any remaining transfer jobs or scheduled queries
cleanup_scheduled_jobs() {
    log "Cleaning up scheduled queries and transfer jobs..."
    
    # List and clean up any BigQuery scheduled queries related to smart city
    local scheduled_queries
    scheduled_queries=$(bq ls --transfer_config --project_id="${PROJECT_ID}" --format="value(name)" 2>/dev/null | grep -i "city\|smart" || true)
    
    if [[ -n "${scheduled_queries}" ]]; then
        log "Found scheduled queries to clean up:"
        echo "${scheduled_queries}"
        
        # Note: Cleanup would require transfer job IDs which are complex to extract
        # For now, just log them for manual cleanup
        log_warning "Please manually review and delete scheduled queries in the BigQuery console if needed"
    else
        log "No scheduled queries found"
    fi
    
    log_success "Scheduled jobs cleanup completed"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup completion..."
    
    local errors=0
    
    # Check if BigQuery dataset still exists
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        log_error "BigQuery dataset still exists: ${DATASET_NAME}"
        ((errors++))
    fi
    
    # Check if any smart city buckets still exist
    local remaining_buckets
    remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "smart-city-data-lake-" || true)
    if [[ -n "${remaining_buckets}" ]]; then
        log_error "Some Cloud Storage buckets still exist:"
        echo "${remaining_buckets}"
        ((errors++))
    fi
    
    # Check if Pub/Sub topics still exist
    for topic in "${PUBSUB_TOPIC_TRAFFIC}" "${PUBSUB_TOPIC_AIR}" "${PUBSUB_TOPIC_ENERGY}"; do
        if gcloud pubsub topics describe "${topic}" &> /dev/null; then
            log_error "Pub/Sub topic still exists: ${topic}"
            ((errors++))
        fi
    done
    
    if [[ ${errors} -eq 0 ]]; then
        log_success "Cleanup validation passed - all resources successfully removed"
        return 0
    else
        log_error "Cleanup validation failed - ${errors} resource(s) still exist"
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "Resources cleaned up:"
    echo "✅ BigQuery dataset and all tables"
    echo "✅ Cloud Storage buckets and contents"
    echo "✅ Pub/Sub topics and subscriptions"
    echo "✅ Service accounts and IAM bindings"
    echo "✅ Log-based metrics"
    echo "✅ Dataflow jobs (if any were running)"
    echo ""
    echo "Manual cleanup may be needed for:"
    echo "⚠️  Scheduled queries (check BigQuery console)"
    echo "⚠️  Cloud Dataprep flows (check Dataprep console)"
    echo "⚠️  Custom dashboards (check Cloud Monitoring console)"
    echo ""
    log_success "Smart city data processing infrastructure cleanup completed!"
}

# Main cleanup function
main() {
    echo "=================================================="
    echo "Smart City Data Processing Pipeline Cleanup"
    echo "=================================================="
    echo ""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --project-id PROJECT_ID   GCP project ID to clean up (optional, uses current project)"
                echo "  --force                   Skip confirmation prompts"
                echo "  --dry-run                 Show what would be deleted without executing"
                echo "  --help, -h                Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                        # Interactive cleanup of current project"
                echo "  $0 --force                # Cleanup without confirmation"
                echo "  $0 --dry-run              # Show what would be deleted"
                echo "  $0 --project-id my-proj  # Cleanup specific project"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Set project if provided
    if [[ -n "${PROJECT_ID:-}" ]]; then
        gcloud config set project "${PROJECT_ID}" --quiet
    fi
    
    # Execute cleanup steps
    check_prerequisites
    get_project_settings
    list_resources
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "DRY RUN MODE - No resources will be deleted"
        echo ""
        echo "Would delete the following resources from project: ${PROJECT_ID}"
        echo ""
        
        if [[ ${#BUCKETS[@]} -gt 0 ]]; then
            echo "Cloud Storage buckets:"
            for bucket in "${BUCKETS[@]}"; do
                echo "  - gs://${bucket}"
            done
        fi
        
        if [[ "${DATASET_EXISTS}" == "true" ]]; then
            echo "BigQuery dataset:"
            echo "  - ${PROJECT_ID}:${DATASET_NAME}"
        fi
        
        if [[ ${#EXISTING_TOPICS[@]} -gt 0 ]]; then
            echo "Pub/Sub topics:"
            for topic in "${EXISTING_TOPICS[@]}"; do
                echo "  - ${topic}"
            done
        fi
        
        echo ""
        echo "Additional resources:"
        echo "  - Service account: dataprep-service-account"
        echo "  - Log-based metrics: data_quality_errors, bigquery_job_failures"
        echo "  - Any running Dataflow jobs"
        echo ""
        exit 0
    fi
    
    confirm_destruction
    
    # Execute cleanup in proper order
    stop_dataflow_jobs
    cleanup_bigquery
    cleanup_pubsub
    cleanup_storage
    cleanup_iam
    cleanup_monitoring
    cleanup_scheduled_jobs
    
    # Validate and summarize
    if validate_cleanup; then
        display_cleanup_summary
        log_success "Cleanup script completed successfully!"
        exit 0
    else
        log_error "Cleanup completed with some issues. Please review the output above."
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"