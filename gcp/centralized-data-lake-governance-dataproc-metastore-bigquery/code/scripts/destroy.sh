#!/bin/bash

# GCP Centralized Data Lake Governance Cleanup Script
# This script removes all infrastructure created by the deployment script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed."
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "BigQuery CLI (bq) is not installed."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "Google Cloud Storage CLI (gsutil) is not installed."
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 &> /dev/null; then
        error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
    fi
    
    success "Prerequisites check passed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ -f .env ]]; then
        # Load environment variables from file
        set -a  # automatically export all variables
        source .env
        set +a  # turn off automatic export
        
        success "Environment variables loaded from .env file"
        log "Project ID: ${PROJECT_ID}"
        log "Region: ${REGION}"
        log "Resources to be deleted:"
        log "  - Bucket: ${BUCKET_NAME}"
        log "  - Metastore: ${METASTORE_NAME}"
        log "  - Dataproc Cluster: ${DATAPROC_CLUSTER}"
        log "  - BigQuery Dataset: ${BIGQUERY_DATASET}"
    else
        warning ".env file not found. Please provide environment variables manually."
        
        read -p "Enter PROJECT_ID: " PROJECT_ID
        read -p "Enter REGION (default: us-central1): " REGION
        REGION=${REGION:-us-central1}
        read -p "Enter BUCKET_NAME: " BUCKET_NAME
        read -p "Enter METASTORE_NAME: " METASTORE_NAME
        read -p "Enter DATAPROC_CLUSTER: " DATAPROC_CLUSTER
        read -p "Enter BIGQUERY_DATASET: " BIGQUERY_DATASET
        
        export PROJECT_ID REGION BUCKET_NAME METASTORE_NAME DATAPROC_CLUSTER BIGQUERY_DATASET
    fi
    
    # Set project context
    gcloud config set project "${PROJECT_ID}" || error "Failed to set project"
    gcloud config set compute/region "${REGION}" || error "Failed to set region"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warning "This will delete ALL resources created by the deployment script."
    warning "This action is IRREVERSIBLE and will result in data loss."
    echo ""
    echo "Resources to be deleted:"
    echo "  - Project: ${PROJECT_ID}"
    echo "  - Cloud Storage Bucket: gs://${BUCKET_NAME} (and ALL contents)"
    echo "  - BigLake Metastore: ${METASTORE_NAME}"
    echo "  - Dataproc Cluster: ${DATAPROC_CLUSTER}"
    echo "  - BigQuery Dataset: ${BIGQUERY_DATASET} (and ALL tables/views)"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    success "Cleanup confirmed. Proceeding with resource deletion..."
}

# Function to delete Dataproc cluster
delete_dataproc_cluster() {
    log "Deleting Dataproc cluster..."
    
    # Check if cluster exists
    if gcloud dataproc clusters describe "${DATAPROC_CLUSTER}" \
        --region="${REGION}" &> /dev/null; then
        
        log "Deleting Dataproc cluster: ${DATAPROC_CLUSTER}"
        if gcloud dataproc clusters delete "${DATAPROC_CLUSTER}" \
            --region="${REGION}" \
            --quiet; then
            success "Dataproc cluster deleted successfully"
        else
            error "Failed to delete Dataproc cluster"
        fi
    else
        warning "Dataproc cluster ${DATAPROC_CLUSTER} not found or already deleted"
    fi
}

# Function to delete BigQuery dataset
delete_bigquery_dataset() {
    log "Deleting BigQuery dataset and all tables..."
    
    # Check if dataset exists
    if bq ls -d "${PROJECT_ID}:${BIGQUERY_DATASET}" &> /dev/null; then
        log "Deleting BigQuery dataset: ${BIGQUERY_DATASET}"
        if bq rm -r -f "${PROJECT_ID}:${BIGQUERY_DATASET}"; then
            success "BigQuery dataset and all tables deleted successfully"
        else
            error "Failed to delete BigQuery dataset"
        fi
    else
        warning "BigQuery dataset ${BIGQUERY_DATASET} not found or already deleted"
    fi
}

# Function to delete BigLake Metastore
delete_metastore() {
    log "Deleting BigLake Metastore service..."
    
    # Check if metastore exists
    if gcloud metastore services describe "${METASTORE_NAME}" \
        --location="${REGION}" &> /dev/null; then
        
        log "Deleting metastore: ${METASTORE_NAME} (this may take 5-10 minutes)"
        if gcloud metastore services delete "${METASTORE_NAME}" \
            --location="${REGION}" \
            --quiet; then
            
            # Wait for deletion to complete
            log "Waiting for metastore deletion to complete..."
            local max_attempts=60
            local attempt=0
            
            while [[ ${attempt} -lt ${max_attempts} ]]; do
                if ! gcloud metastore services describe "${METASTORE_NAME}" \
                    --location="${REGION}" &> /dev/null; then
                    success "BigLake Metastore deleted successfully"
                    return 0
                fi
                
                sleep 10
                ((attempt++))
                log "Still waiting for metastore deletion... (attempt ${attempt}/${max_attempts})"
            done
            
            warning "Metastore deletion may still be in progress. Check the console for status."
        else
            error "Failed to delete BigLake Metastore"
        fi
    else
        warning "BigLake Metastore ${METASTORE_NAME} not found or already deleted"
    fi
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log "Deleting Cloud Storage bucket and all contents..."
    
    # Check if bucket exists
    if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        log "Deleting bucket: gs://${BUCKET_NAME}"
        
        # Remove all objects and versions first
        log "Removing all objects and versions from bucket..."
        if gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true; then
            log "Bucket contents removed"
        fi
        
        # Delete the bucket
        if gsutil rb "gs://${BUCKET_NAME}"; then
            success "Cloud Storage bucket deleted successfully"
        else
            error "Failed to delete Cloud Storage bucket"
        fi
    else
        warning "Cloud Storage bucket gs://${BUCKET_NAME} not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local configuration files..."
    
    local files_to_remove=(
        ".env"
        "sample_retail_data.csv"
        "external_table_def.json"
        "governance-policies.sql"
        "populate_table.py"
        "notebook-config.json"
        "metastore-demo.ipynb"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log "Removed local file: ${file}"
        fi
    done
    
    success "Local configuration files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_success=true
    
    # Check Dataproc cluster
    if gcloud dataproc clusters describe "${DATAPROC_CLUSTER}" \
        --region="${REGION}" &> /dev/null; then
        warning "Dataproc cluster still exists: ${DATAPROC_CLUSTER}"
        cleanup_success=false
    fi
    
    # Check BigQuery dataset
    if bq ls -d "${PROJECT_ID}:${BIGQUERY_DATASET}" &> /dev/null; then
        warning "BigQuery dataset still exists: ${BIGQUERY_DATASET}"
        cleanup_success=false
    fi
    
    # Check metastore
    if gcloud metastore services describe "${METASTORE_NAME}" \
        --location="${REGION}" &> /dev/null; then
        warning "Metastore still exists: ${METASTORE_NAME}"
        cleanup_success=false
    fi
    
    # Check Cloud Storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        warning "Cloud Storage bucket still exists: gs://${BUCKET_NAME}"
        cleanup_success=false
    fi
    
    if [[ "${cleanup_success}" == "true" ]]; then
        success "All resources cleaned up successfully"
    else
        warning "Some resources may still exist. Check the Google Cloud Console."
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "Resources Removed:"
    echo "- Cloud Storage Bucket: gs://${BUCKET_NAME}"
    echo "- BigLake Metastore: ${METASTORE_NAME}"
    echo "- Dataproc Cluster: ${DATAPROC_CLUSTER}"
    echo "- BigQuery Dataset: ${BIGQUERY_DATASET}"
    echo "- Local configuration files"
    echo ""
    echo "Note: If you created a project specifically for this demo, you can delete it entirely:"
    echo "gcloud projects delete ${PROJECT_ID} --quiet"
    echo ""
    success "Centralized Data Lake Governance infrastructure cleanup completed!"
}

# Function to handle partial cleanup
handle_partial_cleanup() {
    warning "Some resources could not be deleted automatically."
    echo ""
    echo "Manual cleanup steps:"
    echo ""
    echo "1. Check Google Cloud Console for any remaining resources:"
    echo "   - Dataproc: https://console.cloud.google.com/dataproc"
    echo "   - BigQuery: https://console.cloud.google.com/bigquery"
    echo "   - Metastore: https://console.cloud.google.com/dataproc/metastore"
    echo "   - Storage: https://console.cloud.google.com/storage"
    echo ""
    echo "2. If you created a project specifically for this demo:"
    echo "   gcloud projects delete ${PROJECT_ID} --quiet"
    echo ""
    echo "3. Check for any additional charges in the billing console:"
    echo "   https://console.cloud.google.com/billing"
}

# Main cleanup function
main() {
    log "Starting GCP Centralized Data Lake Governance cleanup..."
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_dataproc_cluster
    delete_bigquery_dataset
    delete_metastore
    delete_storage_bucket
    cleanup_local_files
    verify_cleanup
    display_summary
    
    success "Cleanup completed!"
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may still exist."' INT TERM

# Check for force flag to skip confirmation
if [[ "${1:-}" == "--force" ]]; then
    export SKIP_CONFIRMATION=true
fi

# Override confirmation function if force flag is used
if [[ "${SKIP_CONFIRMATION:-false}" == "true" ]]; then
    confirm_deletion() {
        warning "Force flag detected. Skipping confirmation."
        log "Proceeding with resource deletion..."
    }
fi

# Run main function
main "$@"