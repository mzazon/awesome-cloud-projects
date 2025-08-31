#!/bin/bash

# Content Performance Optimization with Gemini and Analytics - Cleanup Script
# This script removes all resources created by the deployment script
# to avoid ongoing charges and clean up the Google Cloud project

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to load deployment info
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Try to load from local file first
    if [[ -f "./deployment_info.json" ]]; then
        log_info "Found local deployment_info.json"
        DEPLOYMENT_INFO_FILE="./deployment_info.json"
    elif [[ -n "${BUCKET_NAME:-}" ]] && gsutil -q stat "gs://${BUCKET_NAME}/deployment_info.json"; then
        log_info "Found deployment info in Cloud Storage"
        gsutil cp "gs://${BUCKET_NAME}/deployment_info.json" /tmp/deployment_info.json
        DEPLOYMENT_INFO_FILE="/tmp/deployment_info.json"
    else
        log_warning "No deployment info found. Using environment variables or prompting for values."
        return 1
    fi
    
    # Extract values from deployment info
    if command_exists jq; then
        export PROJECT_ID=$(jq -r '.project_id' "${DEPLOYMENT_INFO_FILE}")
        export REGION=$(jq -r '.region' "${DEPLOYMENT_INFO_FILE}")
        export DATASET_NAME=$(jq -r '.dataset_name' "${DEPLOYMENT_INFO_FILE}")
        export FUNCTION_NAME=$(jq -r '.function_name' "${DEPLOYMENT_INFO_FILE}")
        export BUCKET_NAME=$(jq -r '.bucket_name' "${DEPLOYMENT_INFO_FILE}")
        export TABLE_NAME=$(jq -r '.table_name' "${DEPLOYMENT_INFO_FILE}")
        log_success "Deployment info loaded from ${DEPLOYMENT_INFO_FILE}"
        return 0
    else
        log_warning "jq not available. Please set environment variables manually."
        return 1
    fi
}

# Function to prompt for required values if not available
prompt_for_values() {
    log_info "Some required values are missing. Please provide them:"
    
    if [[ -z "${PROJECT_ID:-}" ]]; then
        read -p "Enter Project ID: " PROJECT_ID
        export PROJECT_ID
    fi
    
    if [[ -z "${REGION:-}" ]]; then
        read -p "Enter Region [us-central1]: " REGION
        export REGION="${REGION:-us-central1}"
    fi
    
    if [[ -z "${DATASET_NAME:-}" ]]; then
        read -p "Enter BigQuery Dataset Name: " DATASET_NAME
        export DATASET_NAME
    fi
    
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        read -p "Enter Cloud Function Name: " FUNCTION_NAME
        export FUNCTION_NAME
    fi
    
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        read -p "Enter Cloud Storage Bucket Name: " BUCKET_NAME
        export BUCKET_NAME
    fi
    
    export TABLE_NAME="${TABLE_NAME:-performance_data}"
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "This will permanently delete the following resources:"
    log_warning "  Project: ${PROJECT_ID}"
    log_warning "  BigQuery Dataset: ${DATASET_NAME} (including all tables and views)"
    log_warning "  Cloud Function: ${FUNCTION_NAME}"
    log_warning "  Storage Bucket: ${BUCKET_NAME} (including all files)"
    log_warning ""
    log_warning "This action cannot be undone!"
    
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed and authenticated
    if ! command_exists gcloud; then
        error_exit "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        error_exit "Not authenticated with gcloud. Please run 'gcloud auth login'"
    fi
    
    # Check if bq is available
    if ! command_exists bq; then
        error_exit "BigQuery CLI (bq) is not available. Please install Google Cloud SDK"
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        error_exit "Cloud Storage CLI (gsutil) is not available. Please install Google Cloud SDK"
    fi
    
    log_success "All prerequisites met"
}

# Function to configure project
configure_project() {
    log_info "Configuring Google Cloud project..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
    
    log_success "Project configuration completed"
}

# Function to delete Cloud Function
delete_cloud_function() {
    log_info "Deleting Cloud Function: ${FUNCTION_NAME}..."
    
    # Check if function exists
    if gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" >/dev/null 2>&1; then
        # Delete Cloud Function
        gcloud functions delete "${FUNCTION_NAME}" \
            --gen2 \
            --region="${REGION}" \
            --quiet || log_error "Failed to delete Cloud Function: ${FUNCTION_NAME}"
        
        # Wait for deletion to complete
        local max_wait=180
        local waited=0
        
        log_info "Waiting for Cloud Function deletion to complete..."
        while gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" >/dev/null 2>&1 && [ $waited -lt $max_wait ]; do
            sleep 10
            waited=$((waited + 10))
            echo -n "."
        done
        echo
        
        if [ $waited -ge $max_wait ]; then
            log_warning "Timeout waiting for Cloud Function deletion, but continuing..."
        else
            log_success "Cloud Function deleted: ${FUNCTION_NAME}"
        fi
    else
        log_warning "Cloud Function not found: ${FUNCTION_NAME}"
    fi
}

# Function to delete BigQuery dataset
delete_bigquery_dataset() {
    log_info "Deleting BigQuery dataset: ${DATASET_NAME}..."
    
    # Check if dataset exists
    if bq ls "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        # Delete BigQuery dataset (this removes all tables and views)
        bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" || log_error "Failed to delete BigQuery dataset: ${DATASET_NAME}"
        log_success "BigQuery dataset deleted: ${DATASET_NAME}"
    else
        log_warning "BigQuery dataset not found: ${DATASET_NAME}"
    fi
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket: ${BUCKET_NAME}..."
    
    # Check if bucket exists
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        # Delete all objects in bucket (including versioned objects)
        log_info "Removing all objects from bucket..."
        gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true
        
        # Remove bucket versioning (helps with deletion)
        gsutil versioning set off "gs://${BUCKET_NAME}" 2>/dev/null || true
        
        # Delete the bucket itself
        gsutil rb "gs://${BUCKET_NAME}" || log_error "Failed to delete Cloud Storage bucket: ${BUCKET_NAME}"
        log_success "Cloud Storage bucket deleted: ${BUCKET_NAME}"
    else
        log_warning "Cloud Storage bucket not found: ${BUCKET_NAME}"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment info file
    if [[ -f "./deployment_info.json" ]]; then
        rm -f "./deployment_info.json"
        log_success "Removed local deployment_info.json"
    fi
    
    # Remove any temporary files
    rm -f /tmp/deployment_info.json
    rm -f /tmp/schema.json
    rm -f /tmp/sample_data.json
    
    # Remove any temporary directories
    rm -rf /tmp/content-analyzer-*
    
    log_success "Local cleanup completed"
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local errors=0
    
    # Check Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" >/dev/null 2>&1; then
        log_error "Cloud Function still exists: ${FUNCTION_NAME}"
        errors=$((errors + 1))
    else
        log_success "Cloud Function deletion verified: ${FUNCTION_NAME}"
    fi
    
    # Check BigQuery dataset
    if bq ls "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
        log_error "BigQuery dataset still exists: ${DATASET_NAME}"
        errors=$((errors + 1))
    else
        log_success "BigQuery dataset deletion verified: ${DATASET_NAME}"
    fi
    
    # Check Cloud Storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_error "Cloud Storage bucket still exists: ${BUCKET_NAME}"
        errors=$((errors + 1))
    else
        log_success "Cloud Storage bucket deletion verified: ${BUCKET_NAME}"
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "All resources successfully deleted"
    else
        log_warning "${errors} resource(s) may still exist. Please check manually in Google Cloud Console."
    fi
    
    return $errors
}

# Function to display cost savings information
display_cost_savings() {
    log_info "Cost savings information:"
    log_info "The following resources have been deleted to avoid ongoing charges:"
    log_info "  ✓ Cloud Function (Gen2) - Pay-per-invocation billing stopped"
    log_info "  ✓ Vertex AI Gemini usage - No more per-token charges"
    log_info "  ✓ BigQuery dataset - Storage and query costs eliminated"
    log_info "  ✓ Cloud Storage bucket - Storage costs eliminated"
    log_info ""
    log_info "Note: Some minimal costs may still apply for:"
    log_info "  - API calls made during deployment (one-time charges)"
    log_info "  - Any logs retained in Cloud Logging (minimal cost)"
    log_info ""
    log_info "Monitor your billing in Google Cloud Console to confirm all charges have stopped."
}

# Function to list remaining resources (optional check)
list_remaining_resources() {
    log_info "Checking for any remaining related resources..."
    
    # Check for any remaining functions with similar names
    remaining_functions=$(gcloud functions list --filter="name~content-analyzer" --format="value(name)" 2>/dev/null || true)
    if [[ -n "${remaining_functions}" ]]; then
        log_warning "Found remaining Cloud Functions:"
        echo "${remaining_functions}"
    fi
    
    # Check for any remaining BigQuery datasets with similar names
    remaining_datasets=$(bq ls --filter="datasetId~content_analytics" --format="value(datasetId)" 2>/dev/null || true)
    if [[ -n "${remaining_datasets}" ]]; then
        log_warning "Found remaining BigQuery datasets:"
        echo "${remaining_datasets}"
    fi
    
    # Check for any remaining storage buckets with similar names
    remaining_buckets=$(gsutil ls | grep "content-optimization" || true)
    if [[ -n "${remaining_buckets}" ]]; then
        log_warning "Found remaining Cloud Storage buckets:"
        echo "${remaining_buckets}"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Content Performance Optimization cleanup..."
    log_info "This will delete all resources created by the deployment script"
    
    # Check prerequisites
    check_prerequisites
    
    # Try to load deployment info, fall back to prompting
    if ! load_deployment_info; then
        prompt_for_values
    fi
    
    # Validate required variables
    if [[ -z "${PROJECT_ID}" ]] || [[ -z "${DATASET_NAME}" ]] || [[ -z "${FUNCTION_NAME}" ]] || [[ -z "${BUCKET_NAME}" ]]; then
        error_exit "Missing required information. Cannot proceed with cleanup."
    fi
    
    # Confirm destruction
    confirm_destruction
    
    # Configure project
    configure_project
    
    # Start cleanup process
    log_info "Starting resource deletion process..."
    
    # Delete resources in reverse order of creation
    delete_cloud_function
    delete_bigquery_dataset
    delete_storage_bucket
    cleanup_local_files
    
    # Verify deletion
    verify_deletion
    
    # Check for remaining resources
    list_remaining_resources
    
    # Display cost savings info
    display_cost_savings
    
    log_success "=== Cleanup completed successfully! ==="
    log_info "All Content Performance Optimization resources have been removed."
    log_info "You should no longer incur charges for these resources."
    log_info ""
    log_info "If you need to redeploy, run the deploy.sh script again."
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi