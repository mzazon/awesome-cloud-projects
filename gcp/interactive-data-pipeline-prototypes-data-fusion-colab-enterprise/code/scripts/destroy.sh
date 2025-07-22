#!/bin/bash

# Destroy Script for Interactive Data Pipeline Prototypes with Cloud Data Fusion and Colab Enterprise
# This script safely removes all infrastructure created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit if any command in a pipeline fails

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 is required but not installed. Please install $1 and try again."
    fi
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "You are not authenticated with gcloud. Please run 'gcloud auth login' first."
    fi
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo "========================================="
    echo "         RESOURCE DESTRUCTION           "
    echo "========================================="
    echo ""
    warning "This script will permanently delete the following resources:"
    echo "  - Cloud Data Fusion instance: ${INSTANCE_NAME}"
    echo "  - Cloud Storage buckets: ${BUCKET_NAME}, ${BUCKET_NAME}-staging"
    echo "  - BigQuery dataset: ${DATASET_NAME} (including all tables)"
    echo "  - All sample data and notebook templates"
    echo ""
    warning "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Proceeding with resource destruction..."
}

# Function to delete Cloud Data Fusion instance
delete_data_fusion() {
    local instance_name="$1"
    local region="$2"
    local project_id="$3"
    
    log "Deleting Cloud Data Fusion instance..."
    
    # Check if instance exists
    if ! gcloud data-fusion instances describe "${instance_name}" --location="${region}" --project="${project_id}" &>/dev/null; then
        warning "Data Fusion instance ${instance_name} does not exist or is already deleted"
        return 0
    fi
    
    # Delete the instance
    log "Deleting Data Fusion instance (this may take 10-15 minutes)..."
    if gcloud data-fusion instances delete "${instance_name}" \
        --location="${region}" \
        --project="${project_id}" \
        --quiet; then
        success "Data Fusion instance deletion initiated"
    else
        error "Failed to delete Data Fusion instance"
    fi
    
    # Wait for deletion to complete
    log "Waiting for Data Fusion instance deletion to complete..."
    local timeout=900  # 15 minutes
    local elapsed=0
    local interval=30
    
    while [[ $elapsed -lt $timeout ]]; do
        if ! gcloud data-fusion instances describe "${instance_name}" --location="${region}" --project="${project_id}" &>/dev/null; then
            success "Data Fusion instance deleted successfully"
            return 0
        fi
        
        log "Still deleting... (${elapsed}s elapsed)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    warning "Data Fusion instance deletion is still in progress after ${timeout}s"
    info "The instance will continue deleting in the background"
}

# Function to delete BigQuery dataset
delete_bigquery_dataset() {
    local dataset_name="$1"
    local project_id="$2"
    
    log "Deleting BigQuery dataset..."
    
    # Check if dataset exists
    if ! bq ls -d "${project_id}:${dataset_name}" &>/dev/null; then
        warning "BigQuery dataset ${dataset_name} does not exist or is already deleted"
        return 0
    fi
    
    # List tables in the dataset
    local tables
    tables=$(bq ls -n 1000 "${project_id}:${dataset_name}" 2>/dev/null | grep -v "tableId" | awk '{print $1}' | grep -v "^$" || true)
    
    if [[ -n "$tables" ]]; then
        info "Dataset contains the following tables:"
        echo "$tables" | while read -r table; do
            echo "  - $table"
        done
    fi
    
    # Delete the dataset and all tables
    if bq rm -r -f "${project_id}:${dataset_name}"; then
        success "BigQuery dataset and all tables deleted"
    else
        error "Failed to delete BigQuery dataset"
    fi
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    local bucket_name="$1"
    
    log "Deleting Cloud Storage buckets..."
    
    # Delete primary bucket
    if gsutil ls "gs://${bucket_name}" &>/dev/null; then
        log "Deleting bucket contents: gs://${bucket_name}"
        if gsutil -m rm -r "gs://${bucket_name}"; then
            success "Deleted bucket: gs://${bucket_name}"
        else
            error "Failed to delete bucket: gs://${bucket_name}"
        fi
    else
        warning "Bucket gs://${bucket_name} does not exist or is already deleted"
    fi
    
    # Delete staging bucket
    if gsutil ls "gs://${bucket_name}-staging" &>/dev/null; then
        log "Deleting bucket contents: gs://${bucket_name}-staging"
        if gsutil -m rm -r "gs://${bucket_name}-staging"; then
            success "Deleted bucket: gs://${bucket_name}-staging"
        else
            error "Failed to delete bucket: gs://${bucket_name}-staging"
        fi
    else
        warning "Bucket gs://${bucket_name}-staging does not exist or is already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local temporary files..."
    
    # Remove any temporary files that might have been created
    local temp_files=(
        "customer_data.csv"
        "transaction_data.json"
        "pipeline_prototype.ipynb"
        "pipeline_template.json"
        "runtime_config.yaml"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            success "Removed local file: $file"
        fi
    done
}

# Function to check for remaining resources
check_remaining_resources() {
    local project_id="$1"
    local instance_name="$2"
    local bucket_name="$3"
    local dataset_name="$4"
    local region="$5"
    
    log "Checking for any remaining resources..."
    
    local remaining_resources=()
    
    # Check Data Fusion instance
    if gcloud data-fusion instances describe "${instance_name}" --location="${region}" --project="${project_id}" &>/dev/null; then
        remaining_resources+=("Data Fusion instance: ${instance_name}")
    fi
    
    # Check storage buckets
    if gsutil ls "gs://${bucket_name}" &>/dev/null; then
        remaining_resources+=("Storage bucket: gs://${bucket_name}")
    fi
    
    if gsutil ls "gs://${bucket_name}-staging" &>/dev/null; then
        remaining_resources+=("Storage bucket: gs://${bucket_name}-staging")
    fi
    
    # Check BigQuery dataset
    if bq ls -d "${project_id}:${dataset_name}" &>/dev/null; then
        remaining_resources+=("BigQuery dataset: ${dataset_name}")
    fi
    
    if [[ ${#remaining_resources[@]} -gt 0 ]]; then
        warning "The following resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            echo "  - $resource"
        done
        echo ""
        info "Some resources may take additional time to be fully deleted"
        info "Please check the Google Cloud Console to verify complete removal"
    else
        success "All resources have been successfully removed"
    fi
}

# Function to display cost savings information
display_cost_info() {
    echo ""
    echo "========================================="
    echo "           COST INFORMATION            "
    echo "========================================="
    echo ""
    info "Resource deletion will stop the following charges:"
    echo "  - Cloud Data Fusion Developer edition: ~\$0.20/hour"
    echo "  - Cloud Storage: Storage and operation costs"
    echo "  - BigQuery: Storage costs (queries are pay-per-use)"
    echo ""
    info "To avoid future charges:"
    echo "  - Verify all resources are deleted in the Cloud Console"
    echo "  - Check billing reports for any unexpected usage"
    echo "  - Consider setting up billing alerts for the project"
    echo ""
}

# Function to provide cleanup verification steps
display_verification_steps() {
    local project_id="$1"
    
    echo ""
    echo "========================================="
    echo "         VERIFICATION STEPS            "
    echo "========================================="
    echo ""
    info "To verify complete cleanup, check the following:"
    echo ""
    echo "1. Cloud Data Fusion:"
    echo "   gcloud data-fusion instances list --project=${project_id}"
    echo ""
    echo "2. Cloud Storage:"
    echo "   gsutil ls -p ${project_id}"
    echo ""
    echo "3. BigQuery:"
    echo "   bq ls --project_id=${project_id}"
    echo ""
    echo "4. All resources in Cloud Console:"
    echo "   https://console.cloud.google.com/home/dashboard?project=${project_id}"
    echo ""
}

# Main destruction function
main() {
    log "Starting destruction of Interactive Data Pipeline Prototypes infrastructure..."
    
    # Check prerequisites
    log "Checking prerequisites..."
    check_command "gcloud"
    check_command "gsutil"
    check_command "bq"
    check_gcloud_auth
    
    # Get resource identifiers from environment or prompt user
    if [[ -z "${PROJECT_ID}" ]]; then
        read -p "Enter PROJECT_ID: " PROJECT_ID
    fi
    
    if [[ -z "${INSTANCE_NAME}" ]]; then
        read -p "Enter Data Fusion INSTANCE_NAME: " INSTANCE_NAME
    fi
    
    if [[ -z "${BUCKET_NAME}" ]]; then
        read -p "Enter storage BUCKET_NAME (without gs:// prefix): " BUCKET_NAME
    fi
    
    if [[ -z "${DATASET_NAME}" ]]; then
        read -p "Enter BigQuery DATASET_NAME: " DATASET_NAME
    fi
    
    export REGION="${REGION:-us-central1}"
    
    # Validate project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        error "Project ${PROJECT_ID} does not exist or you don't have access to it"
    fi
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    success "Configured gcloud defaults"
    
    # Confirm destruction
    confirm_destruction
    
    # Delete resources in reverse order of creation
    # (Delete most expensive/time-consuming resources first)
    delete_data_fusion "${INSTANCE_NAME}" "${REGION}" "${PROJECT_ID}"
    delete_bigquery_dataset "${DATASET_NAME}" "${PROJECT_ID}"
    delete_storage_buckets "${BUCKET_NAME}"
    cleanup_local_files
    
    # Verify cleanup
    check_remaining_resources "${PROJECT_ID}" "${INSTANCE_NAME}" "${BUCKET_NAME}" "${DATASET_NAME}" "${REGION}"
    
    # Display information
    display_cost_info
    display_verification_steps "${PROJECT_ID}"
    
    echo ""
    success "Destruction process completed!"
    echo ""
    info "Please allow a few minutes for all deletions to fully propagate"
    info "Check the Google Cloud Console to confirm all resources are removed"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "This script destroys all resources created by the deploy.sh script."
        echo ""
        echo "Environment variables (optional):"
        echo "  PROJECT_ID      - Google Cloud project ID"
        echo "  INSTANCE_NAME   - Data Fusion instance name"
        echo "  BUCKET_NAME     - Cloud Storage bucket name"
        echo "  DATASET_NAME    - BigQuery dataset name"
        echo "  REGION          - Google Cloud region (default: us-central1)"
        echo ""
        echo "Example:"
        echo "  PROJECT_ID=my-project INSTANCE_NAME=my-instance $0"
        echo ""
        exit 0
        ;;
    --force|-f)
        # Skip confirmation when --force is used
        confirm_destruction() {
            warning "Force mode enabled - skipping confirmation"
            log "Proceeding with resource destruction..."
        }
        main
        ;;
    *)
        main
        ;;
esac