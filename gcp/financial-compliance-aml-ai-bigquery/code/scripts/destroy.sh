#!/bin/bash

# Financial Compliance AML AI BigQuery - Cleanup Script
# This script removes all resources created by the AML compliance monitoring solution

set -euo pipefail

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found"
        echo "Please run: gcloud auth login"
        exit 1
    fi
}

# Function to confirm destructive actions
confirm_destruction() {
    local resource_type=$1
    local resource_name=$2
    
    echo -e "${YELLOW}WARNING: You are about to delete ${resource_type}: ${resource_name}${NC}"
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    
    if [ "${FORCE_DELETE:-false}" != "true" ]; then
        read -p "Are you sure you want to continue? (yes/no): " confirmation
        if [ "$confirmation" != "yes" ]; then
            log "Operation cancelled by user"
            return 1
        fi
    else
        log "Force delete enabled, skipping confirmation"
    fi
    
    return 0
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        error "Google Cloud CLI (gcloud) is not installed"
        echo "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if other required tools are available
    for tool in bq gsutil; do
        if ! command_exists $tool; then
            error "$tool is not installed or not in PATH"
            exit 1
        fi
    done
    
    # Check gcloud authentication
    check_gcloud_auth
    
    success "Prerequisites check completed"
}

# Configuration setup
setup_configuration() {
    log "Setting up configuration for cleanup..."
    
    # Use existing project configuration
    if [ -z "${PROJECT_ID:-}" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [ -z "$PROJECT_ID" ]; then
            error "PROJECT_ID not set and no default project configured"
            echo "Please set PROJECT_ID environment variable or run: gcloud config set project YOUR_PROJECT_ID"
            exit 1
        fi
    fi
    
    # Set default values
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Set resource names (these should match the deployment script)
    export DATASET_NAME="aml_compliance_data"
    export TABLE_NAME="transactions"
    export MODEL_NAME="aml_detection_model"
    export TOPIC_NAME="aml-alerts"
    export FUNCTION_NAME="process-aml-alerts"
    export SCHEDULER_JOB="daily-compliance-report"
    
    # Set gcloud configuration
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log "Configuration completed:"
    log "  Project ID: $PROJECT_ID"
    log "  Region: $REGION"
    log "  Zone: $ZONE"
    
    success "Configuration setup completed"
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log "Deleting Cloud Scheduler jobs..."
    
    # Check if the job exists and delete it
    if gcloud scheduler jobs describe "${SCHEDULER_JOB}" >/dev/null 2>&1; then
        if confirm_destruction "Cloud Scheduler job" "${SCHEDULER_JOB}"; then
            if gcloud scheduler jobs delete "${SCHEDULER_JOB}" --quiet; then
                success "Deleted Cloud Scheduler job: ${SCHEDULER_JOB}"
            else
                warning "Failed to delete Cloud Scheduler job: ${SCHEDULER_JOB}"
            fi
        fi
    else
        log "Cloud Scheduler job not found: ${SCHEDULER_JOB}"
    fi
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    local functions=("${FUNCTION_NAME}" "compliance-report-generator")
    
    for func in "${functions[@]}"; do
        # Check if function exists in Gen2
        if gcloud functions describe "$func" --gen2 --region="${REGION}" >/dev/null 2>&1; then
            if confirm_destruction "Cloud Function (Gen2)" "$func"; then
                log "Deleting Cloud Function (Gen2): $func"
                if gcloud functions delete "$func" --gen2 --region="${REGION}" --quiet; then
                    success "Deleted Cloud Function: $func"
                else
                    warning "Failed to delete Cloud Function: $func"
                fi
            fi
        # Check if function exists in Gen1
        elif gcloud functions describe "$func" --region="${REGION}" >/dev/null 2>&1; then
            if confirm_destruction "Cloud Function (Gen1)" "$func"; then
                log "Deleting Cloud Function (Gen1): $func"
                if gcloud functions delete "$func" --region="${REGION}" --quiet; then
                    success "Deleted Cloud Function: $func"
                else
                    warning "Failed to delete Cloud Function: $func"
                fi
            fi
        else
            log "Cloud Function not found: $func"
        fi
    done
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log "Deleting Pub/Sub resources..."
    
    # Delete subscription first
    if gcloud pubsub subscriptions describe "${TOPIC_NAME}-subscription" >/dev/null 2>&1; then
        if confirm_destruction "Pub/Sub subscription" "${TOPIC_NAME}-subscription"; then
            if gcloud pubsub subscriptions delete "${TOPIC_NAME}-subscription" --quiet; then
                success "Deleted Pub/Sub subscription: ${TOPIC_NAME}-subscription"
            else
                warning "Failed to delete Pub/Sub subscription: ${TOPIC_NAME}-subscription"
            fi
        fi
    else
        log "Pub/Sub subscription not found: ${TOPIC_NAME}-subscription"
    fi
    
    # Delete topic
    if gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        if confirm_destruction "Pub/Sub topic" "${TOPIC_NAME}"; then
            if gcloud pubsub topics delete "${TOPIC_NAME}" --quiet; then
                success "Deleted Pub/Sub topic: ${TOPIC_NAME}"
            else
                warning "Failed to delete Pub/Sub topic: ${TOPIC_NAME}"
            fi
        fi
    else
        log "Pub/Sub topic not found: ${TOPIC_NAME}"
    fi
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    log "Deleting Cloud Storage buckets..."
    
    # List all buckets that match our naming pattern
    local buckets=$(gsutil ls -p "${PROJECT_ID}" | grep "gs://aml-reports-" | sed 's|gs://||' | sed 's|/||' || true)
    
    if [ -n "$buckets" ]; then
        for bucket in $buckets; do
            if confirm_destruction "Cloud Storage bucket" "$bucket"; then
                log "Deleting Cloud Storage bucket: $bucket"
                
                # Remove all objects in the bucket first
                if gsutil -m rm -r "gs://$bucket/**" 2>/dev/null || true; then
                    log "Removed all objects from bucket: $bucket"
                fi
                
                # Delete the bucket
                if gsutil rb "gs://$bucket"; then
                    success "Deleted Cloud Storage bucket: $bucket"
                else
                    warning "Failed to delete Cloud Storage bucket: $bucket"
                fi
            fi
        done
    else
        log "No Cloud Storage buckets found matching pattern: aml-reports-*"
    fi
}

# Function to delete BigQuery resources
delete_bigquery_resources() {
    log "Deleting BigQuery resources..."
    
    # Check if dataset exists
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        # List all tables and models in the dataset
        local resources=$(bq ls "${PROJECT_ID}:${DATASET_NAME}" --format="value(tableId)" 2>/dev/null || true)
        
        if [ -n "$resources" ]; then
            log "Found BigQuery resources in dataset: $resources"
        fi
        
        if confirm_destruction "BigQuery dataset (including all tables and models)" "${PROJECT_ID}:${DATASET_NAME}"; then
            # Delete the entire dataset with all its contents
            if bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}"; then
                success "Deleted BigQuery dataset: ${PROJECT_ID}:${DATASET_NAME}"
            else
                warning "Failed to delete BigQuery dataset: ${PROJECT_ID}:${DATASET_NAME}"
            fi
        fi
    else
        log "BigQuery dataset not found: ${PROJECT_ID}:${DATASET_NAME}"
    fi
}

# Function to check for remaining resources
check_remaining_resources() {
    log "Checking for any remaining resources..."
    
    local remaining_found=false
    
    # Check Cloud Functions
    local functions=$(gcloud functions list --filter="name~aml OR name~compliance" --format="value(name)" 2>/dev/null || true)
    if [ -n "$functions" ]; then
        warning "Remaining Cloud Functions found: $functions"
        remaining_found=true
    fi
    
    # Check Pub/Sub topics
    local topics=$(gcloud pubsub topics list --filter="name~aml" --format="value(name)" 2>/dev/null || true)
    if [ -n "$topics" ]; then
        warning "Remaining Pub/Sub topics found: $topics"
        remaining_found=true
    fi
    
    # Check Cloud Scheduler jobs
    local jobs=$(gcloud scheduler jobs list --filter="name~aml OR name~compliance" --format="value(name)" 2>/dev/null || true)
    if [ -n "$jobs" ]; then
        warning "Remaining Cloud Scheduler jobs found: $jobs"
        remaining_found=true
    fi
    
    # Check Cloud Storage buckets
    local buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "aml-reports" || true)
    if [ -n "$buckets" ]; then
        warning "Remaining Cloud Storage buckets found: $buckets"
        remaining_found=true
    fi
    
    # Check BigQuery datasets
    local datasets=$(bq ls --filter="datasetId~aml" --format="value(datasetId)" 2>/dev/null || true)
    if [ -n "$datasets" ]; then
        warning "Remaining BigQuery datasets found: $datasets"
        remaining_found=true
    fi
    
    if [ "$remaining_found" = false ]; then
        success "No remaining AML compliance resources found"
    else
        warning "Some resources may still exist. Please review and delete manually if needed."
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove any temporary files that might have been created
    local files_to_remove=(
        "sample_transactions.json"
        "aml-alert-function"
        "compliance-report-function"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -e "$file" ]; then
            if rm -rf "$file" 2>/dev/null; then
                log "Removed local file/directory: $file"
            else
                warning "Failed to remove local file/directory: $file"
            fi
        fi
    done
    
    success "Local file cleanup completed"
}

# Print cleanup summary
print_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo ""
    echo "The following resources have been processed for deletion:"
    echo "- Cloud Scheduler jobs"
    echo "- Cloud Functions (Gen1 and Gen2)"
    echo "- Pub/Sub topics and subscriptions"
    echo "- Cloud Storage buckets"
    echo "- BigQuery datasets, tables, and ML models"
    echo "- Local temporary files"
    echo ""
    echo "Note: Some resources may have been skipped if they didn't exist"
    echo "or if you chose not to delete them during confirmation prompts."
    echo ""
    echo "To verify cleanup completion, you can:"
    echo "1. Check the Google Cloud Console"
    echo "2. Run: gcloud functions list"
    echo "3. Run: gcloud pubsub topics list"
    echo "4. Run: gsutil ls -p ${PROJECT_ID}"
    echo "5. Run: bq ls"
}

# Main cleanup function
main() {
    log "Starting Financial Compliance AML AI BigQuery cleanup..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_DELETE=true
                log "Force delete mode enabled"
                shift
                ;;
            --project)
                export PROJECT_ID="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --force          Skip confirmation prompts"
                echo "  --project ID     Set the Google Cloud project ID"
                echo "  --help, -h       Show this help message"
                echo ""
                echo "Environment Variables:"
                echo "  PROJECT_ID       Google Cloud project ID"
                echo "  REGION           Google Cloud region (default: us-central1)"
                echo "  ZONE             Google Cloud zone (default: us-central1-a)"
                echo "  FORCE_DELETE     Skip confirmations (true/false)"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Trap to handle script interruption
    trap 'error "Cleanup interrupted"; exit 1' INT TERM
    
    # Run cleanup steps in reverse order of creation
    check_prerequisites
    setup_configuration
    
    # Warn user about destructive actions
    echo ""
    warning "This script will delete all resources created by the AML compliance solution!"
    warning "This includes BigQuery datasets, Cloud Functions, storage buckets, and other resources."
    echo ""
    
    if [ "${FORCE_DELETE:-false}" != "true" ]; then
        read -p "Are you sure you want to continue with the cleanup? (yes/no): " final_confirmation
        if [ "$final_confirmation" != "yes" ]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute cleanup steps
    delete_scheduler_jobs
    delete_cloud_functions
    delete_pubsub_resources
    delete_storage_buckets
    delete_bigquery_resources
    cleanup_local_files
    check_remaining_resources
    print_cleanup_summary
    
    success "Financial Compliance AML AI BigQuery cleanup completed!"
    log "Total cleanup time: $SECONDS seconds"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi