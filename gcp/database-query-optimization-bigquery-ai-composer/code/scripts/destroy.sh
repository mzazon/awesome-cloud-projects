#!/bin/bash

# Database Query Optimization with BigQuery AI and Cloud Composer - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to confirm deletion
confirm_deletion() {
    local resource_name="$1"
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will permanently delete $resource_name and ALL associated data."
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deletion cancelled by user."
        exit 0
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check for required tools
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command_exists bq; then
        log_error "BigQuery CLI (bq) is not installed. Please install it first."
        exit 1
    fi
    
    if ! command_exists gsutil; then
        log_error "gsutil is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get current project if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "PROJECT_ID is not set and no default project found. Please set PROJECT_ID or run 'gcloud config set project YOUR_PROJECT_ID'"
            exit 1
        fi
    fi
    
    # Set default values if not provided
    export REGION="${REGION:-us-central1}"
    export COMPOSER_ENV_NAME="${COMPOSER_ENV_NAME:-query-optimizer}"
    
    # Try to get resource names from environment or use defaults
    export DATASET_NAME="${DATASET_NAME:-}"
    export BUCKET_NAME="${BUCKET_NAME:-}"
    
    log_info "Using PROJECT_ID: $PROJECT_ID"
    log_info "Using REGION: $REGION"
    log_info "Using COMPOSER_ENV_NAME: $COMPOSER_ENV_NAME"
    
    if [[ -n "$DATASET_NAME" ]]; then
        log_info "Using DATASET_NAME: $DATASET_NAME"
    fi
    
    if [[ -n "$BUCKET_NAME" ]]; then
        log_info "Using BUCKET_NAME: $BUCKET_NAME"
    fi
}

# Function to discover and list resources
discover_resources() {
    log_info "Discovering resources to delete..."
    
    # Discover BigQuery datasets
    if [[ -z "$DATASET_NAME" ]]; then
        log_info "Searching for optimization datasets..."
        FOUND_DATASETS=$(bq ls --filter="labels.purpose:optimization OR datasetId:optimization_analytics*" \
            --format="value(datasetId)" 2>/dev/null || echo "")
        
        if [[ -n "$FOUND_DATASETS" ]]; then
            log_info "Found BigQuery datasets: $FOUND_DATASETS"
            # Use the first found dataset
            export DATASET_NAME=$(echo "$FOUND_DATASETS" | head -n1)
        fi
    fi
    
    # Discover Cloud Storage buckets
    if [[ -z "$BUCKET_NAME" ]]; then
        log_info "Searching for optimization storage buckets..."
        FOUND_BUCKETS=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | \
            grep -E "query-optimization|optimization-analytics" | \
            sed 's|gs://||g' | sed 's|/||g' || echo "")
        
        if [[ -n "$FOUND_BUCKETS" ]]; then
            log_info "Found storage buckets: $FOUND_BUCKETS"
            # Use the first found bucket
            export BUCKET_NAME=$(echo "$FOUND_BUCKETS" | head -n1)
        fi
    fi
    
    # List all resources to be deleted
    echo
    echo "====================================================="
    echo "RESOURCES TO BE DELETED"
    echo "====================================================="
    echo "Cloud Composer Environment: $COMPOSER_ENV_NAME (in $REGION)"
    [[ -n "$DATASET_NAME" ]] && echo "BigQuery Dataset: $DATASET_NAME"
    [[ -n "$BUCKET_NAME" ]] && echo "Storage Bucket: gs://$BUCKET_NAME"
    echo "Monitoring Dashboards: BigQuery Query Optimization Dashboard"
    echo "Alert Policies: Query Optimization Failures"
    echo "====================================================="
}

# Function to delete Cloud Composer environment
delete_composer_environment() {
    log_info "Deleting Cloud Composer environment..."
    
    # Check if environment exists
    if ! gcloud composer environments describe "$COMPOSER_ENV_NAME" \
        --location="$REGION" >/dev/null 2>&1; then
        log_warning "Composer environment $COMPOSER_ENV_NAME not found, skipping deletion"
        return 0
    fi
    
    confirm_deletion "Cloud Composer environment $COMPOSER_ENV_NAME"
    
    log_info "Deleting Composer environment (this may take 10-15 minutes)..."
    if gcloud composer environments delete "$COMPOSER_ENV_NAME" \
        --location="$REGION" \
        --quiet; then
        log_success "Cloud Composer environment deletion initiated"
    else
        log_error "Failed to delete Cloud Composer environment"
        return 1
    fi
}

# Function to delete BigQuery resources
delete_bigquery_resources() {
    if [[ -z "$DATASET_NAME" ]]; then
        log_warning "No BigQuery dataset name specified, skipping BigQuery cleanup"
        return 0
    fi
    
    log_info "Deleting BigQuery dataset and tables..."
    
    # Check if dataset exists
    if ! bq ls "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        log_warning "BigQuery dataset $DATASET_NAME not found, skipping deletion"
        return 0
    fi
    
    confirm_deletion "BigQuery dataset $DATASET_NAME and all its tables"
    
    # Delete BigQuery dataset and all tables
    if bq rm -r -f "$DATASET_NAME"; then
        log_success "BigQuery dataset $DATASET_NAME deleted"
    else
        log_error "Failed to delete BigQuery dataset"
        return 1
    fi
}

# Function to delete Cloud Storage resources
delete_storage_resources() {
    if [[ -z "$BUCKET_NAME" ]]; then
        log_warning "No storage bucket name specified, skipping storage cleanup"
        return 0
    fi
    
    log_info "Deleting Cloud Storage bucket and contents..."
    
    # Check if bucket exists
    if ! gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "Storage bucket gs://$BUCKET_NAME not found, skipping deletion"
        return 0
    fi
    
    confirm_deletion "Cloud Storage bucket gs://$BUCKET_NAME and all its contents"
    
    # Delete Cloud Storage bucket and contents
    if gsutil -m rm -r "gs://${BUCKET_NAME}"; then
        log_success "Storage bucket gs://$BUCKET_NAME deleted"
    else
        log_error "Failed to delete storage bucket"
        return 1
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log_info "Deleting monitoring dashboards and alert policies..."
    
    # Delete monitoring dashboards
    log_info "Searching for BigQuery optimization dashboards..."
    DASHBOARD_IDS=$(gcloud monitoring dashboards list \
        --filter="displayName:'BigQuery Query Optimization Dashboard'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$DASHBOARD_IDS" ]]; then
        confirm_deletion "monitoring dashboards"
        
        echo "$DASHBOARD_IDS" | while read -r dashboard_id; do
            if [[ -n "$dashboard_id" ]]; then
                log_info "Deleting dashboard: $dashboard_id"
                if gcloud monitoring dashboards delete "$dashboard_id" --quiet; then
                    log_success "Dashboard deleted: $dashboard_id"
                else
                    log_warning "Failed to delete dashboard: $dashboard_id"
                fi
            fi
        done
    else
        log_warning "No BigQuery optimization dashboards found"
    fi
    
    # Delete alert policies
    log_info "Searching for optimization alert policies..."
    POLICY_IDS=$(gcloud alpha monitoring policies list \
        --filter="displayName:'Query Optimization Failures'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$POLICY_IDS" ]]; then
        confirm_deletion "alert policies"
        
        echo "$POLICY_IDS" | while read -r policy_id; do
            if [[ -n "$policy_id" ]]; then
                log_info "Deleting alert policy: $policy_id"
                if gcloud alpha monitoring policies delete "$policy_id" --quiet; then
                    log_success "Alert policy deleted: $policy_id"
                else
                    log_warning "Failed to delete alert policy: $policy_id"
                fi
            fi
        done
    else
        log_warning "No optimization alert policies found"
    fi
    
    log_success "Monitoring resources cleanup completed"
}

# Function to delete Vertex AI resources
delete_vertex_ai_resources() {
    log_info "Cleaning up Vertex AI resources..."
    
    # List and delete custom training jobs
    log_info "Searching for query optimization training jobs..."
    TRAINING_JOBS=$(gcloud ai custom-jobs list \
        --region="$REGION" \
        --filter="displayName:query-optimization-training" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$TRAINING_JOBS" ]]; then
        log_info "Found training jobs to clean up"
        echo "$TRAINING_JOBS" | while read -r job_name; do
            if [[ -n "$job_name" ]]; then
                log_info "Training job found: $job_name (jobs are automatically cleaned up by Google Cloud)"
            fi
        done
    else
        log_info "No training jobs found for cleanup"
    fi
    
    log_success "Vertex AI resources cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local cleanup_complete=true
    
    # Check Composer environment
    if gcloud composer environments describe "$COMPOSER_ENV_NAME" \
        --location="$REGION" >/dev/null 2>&1; then
        log_warning "Cloud Composer environment still exists (deletion may be in progress)"
        cleanup_complete=false
    fi
    
    # Check BigQuery dataset
    if [[ -n "$DATASET_NAME" ]] && bq ls "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        log_warning "BigQuery dataset still exists"
        cleanup_complete=false
    fi
    
    # Check storage bucket
    if [[ -n "$BUCKET_NAME" ]] && gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "Storage bucket still exists"
        cleanup_complete=false
    fi
    
    if [[ "$cleanup_complete" == "true" ]]; then
        log_success "All resources have been successfully deleted"
    else
        log_warning "Some resources may still be in the process of being deleted"
        log_info "Cloud Composer environments can take 10-15 minutes to fully delete"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo
    echo "====================================================="
    echo "CLEANUP SUMMARY"
    echo "====================================================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo
    echo "Resources cleaned up:"
    echo "✓ Cloud Composer Environment: $COMPOSER_ENV_NAME"
    [[ -n "$DATASET_NAME" ]] && echo "✓ BigQuery Dataset: $DATASET_NAME"
    [[ -n "$BUCKET_NAME" ]] && echo "✓ Storage Bucket: gs://$BUCKET_NAME"
    echo "✓ Monitoring Dashboards and Alerts"
    echo "✓ Vertex AI Training Jobs (auto-cleaned)"
    echo
    echo "====================================================="
    echo "CLEANUP COMPLETED"
    echo "====================================================="
    echo "Note: Cloud Composer environment deletion may take"
    echo "additional time to complete in the background."
    echo "====================================================="
}

# Function to handle script interruption
cleanup_on_interrupt() {
    log_warning "Script interrupted. Cleanup may be incomplete."
    log_info "You can rerun this script to continue cleanup."
    exit 1
}

# Set up signal handlers
trap cleanup_on_interrupt SIGINT SIGTERM

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --force, -f          Skip confirmation prompts"
    echo "  --project PROJECT_ID Set the Google Cloud project ID"
    echo "  --region REGION      Set the Google Cloud region (default: us-central1)"
    echo "  --dataset DATASET    Set the BigQuery dataset name to delete"
    echo "  --bucket BUCKET      Set the storage bucket name to delete"
    echo "  --composer-env NAME  Set the Composer environment name (default: query-optimizer)"
    echo "  --help, -h           Show this help message"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID           Google Cloud project ID"
    echo "  REGION              Google Cloud region"
    echo "  DATASET_NAME        BigQuery dataset name"
    echo "  BUCKET_NAME         Cloud Storage bucket name"
    echo "  COMPOSER_ENV_NAME   Cloud Composer environment name"
    echo "  FORCE_DELETE        Set to 'true' to skip confirmations"
    echo
    echo "Examples:"
    echo "  $0 --force --project my-project"
    echo "  $0 --dataset optimization_analytics_abc123"
    echo "  FORCE_DELETE=true $0"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force|-f)
                export FORCE_DELETE="true"
                shift
                ;;
            --project)
                export PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                export REGION="$2"
                shift 2
                ;;
            --dataset)
                export DATASET_NAME="$2"
                shift 2
                ;;
            --bucket)
                export BUCKET_NAME="$2"
                shift 2
                ;;
            --composer-env)
                export COMPOSER_ENV_NAME="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main cleanup function
main() {
    log_info "Starting BigQuery Query Optimization cleanup..."
    
    parse_arguments "$@"
    check_prerequisites
    setup_environment
    discover_resources
    
    # Perform cleanup operations
    delete_composer_environment
    delete_bigquery_resources
    delete_storage_resources
    delete_monitoring_resources
    delete_vertex_ai_resources
    
    verify_cleanup
    display_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Execute main function
main "$@"