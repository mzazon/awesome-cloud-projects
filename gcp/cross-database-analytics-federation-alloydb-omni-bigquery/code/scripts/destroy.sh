#!/bin/bash

# Cross-Database Analytics Federation with AlloyDB Omni and BigQuery - Cleanup Script
# This script removes all resources created by the deployment script
# Recipe: cross-database-analytics-federation-alloydb-omni-bigquery

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "Google Cloud CLI (gcloud) is not installed"
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not installed"
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error_exit "BigQuery CLI (bq) is not installed"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error_exit "Not authenticated with Google Cloud. Run 'gcloud auth login'"
    fi
    
    log_success "Prerequisites check completed"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ -f "deployment_info.txt" ]]; then
        # Extract values from deployment info file
        export PROJECT_ID=$(grep "Project ID:" deployment_info.txt | cut -d: -f2 | xargs)
        export REGION=$(grep "Region:" deployment_info.txt | cut -d: -f2 | xargs)
        export ZONE=$(grep "Zone:" deployment_info.txt | cut -d: -f2 | xargs)
        export RANDOM_SUFFIX=$(grep "Random Suffix:" deployment_info.txt | cut -d: -f2 | xargs)
        export SERVICE_ACCOUNT=$(grep "Service Account:" deployment_info.txt | cut -d: -f2 | xargs)
        export BUCKET_NAME=$(grep "Cloud Storage Bucket:" deployment_info.txt | cut -d: -f2 | xargs | sed 's|gs://||')
        export ALLOYDB_INSTANCE=$(grep "AlloyDB Instance:" deployment_info.txt | cut -d: -f2 | xargs)
        export CONNECTION_ID=$(grep "BigQuery Connection:" deployment_info.txt | cut -d: -f2 | xargs)
        export LAKE_ID=$(grep "Dataplex Lake:" deployment_info.txt | cut -d: -f2 | xargs)
        
        log_success "Deployment information loaded"
        log_info "PROJECT_ID: ${PROJECT_ID}"
        log_info "REGION: ${REGION}"
    else
        log_warning "deployment_info.txt not found. Attempting to use environment variables..."
        
        # Check if critical environment variables are set
        if [[ -z "${PROJECT_ID:-}" ]]; then
            log_error "PROJECT_ID not found. Please set it manually or ensure deployment_info.txt exists"
            echo "Usage: PROJECT_ID=your-project-id ./destroy.sh"
            exit 1
        fi
        
        # Set defaults for other variables if not provided
        export REGION="${REGION:-us-central1}"
        export ZONE="${ZONE:-us-central1-a}"
        
        # Try to derive resource names if RANDOM_SUFFIX is available
        if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
            export SERVICE_ACCOUNT="federation-sa-${RANDOM_SUFFIX}@${PROJECT_ID}.iam.gserviceaccount.com"
            export BUCKET_NAME="analytics-lake-${RANDOM_SUFFIX}"
            export ALLOYDB_INSTANCE="alloydb-omni-sim-${RANDOM_SUFFIX}"
            export CONNECTION_ID="alloydb-federation-${RANDOM_SUFFIX}"
            export LAKE_ID="analytics-federation-lake-${RANDOM_SUFFIX}"
        else
            log_warning "RANDOM_SUFFIX not available. Some resources may not be found for cleanup."
        fi
    fi
    
    # Set current project
    gcloud config set project "${PROJECT_ID}" 2>/dev/null || true
}

# Confirmation prompt
confirm_destruction() {
    log_warning "This will destroy ALL resources for the Analytics Federation deployment"
    log_warning "Project: ${PROJECT_ID}"
    log_warning "This action CANNOT be undone!"
    echo
    read -p "Are you sure you want to continue? (Type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Starting resource cleanup..."
}

# Remove Dataplex resources
cleanup_dataplex() {
    log_info "Cleaning up Dataplex resources..."
    
    if [[ -n "${LAKE_ID:-}" ]]; then
        # Delete Dataplex assets (if they exist)
        if gcloud dataplex assets describe bigquery-analytics-asset \
            --location="${REGION}" --lake="${LAKE_ID}" &>/dev/null; then
            log_info "Deleting BigQuery analytics asset..."
            gcloud dataplex assets delete bigquery-analytics-asset \
                --location="${REGION}" \
                --lake="${LAKE_ID}" \
                --quiet || log_warning "Failed to delete BigQuery analytics asset"
        fi
        
        if gcloud dataplex assets describe storage-lake-asset \
            --location="${REGION}" --lake="${LAKE_ID}" &>/dev/null; then
            log_info "Deleting storage lake asset..."
            gcloud dataplex assets delete storage-lake-asset \
                --location="${REGION}" \
                --lake="${LAKE_ID}" \
                --quiet || log_warning "Failed to delete storage lake asset"
        fi
        
        # Delete zones
        if gcloud dataplex zones describe analytics-zone \
            --location="${REGION}" --lake="${LAKE_ID}" &>/dev/null; then
            log_info "Deleting analytics zone..."
            gcloud dataplex zones delete analytics-zone \
                --location="${REGION}" \
                --lake="${LAKE_ID}" \
                --quiet || log_warning "Failed to delete analytics zone"
        fi
        
        # Delete lake
        if gcloud dataplex lakes describe "${LAKE_ID}" --location="${REGION}" &>/dev/null; then
            log_info "Deleting Dataplex lake..."
            gcloud dataplex lakes delete "${LAKE_ID}" \
                --location="${REGION}" \
                --quiet || log_warning "Failed to delete Dataplex lake"
        fi
        
        log_success "Dataplex resources cleanup completed"
    else
        log_warning "LAKE_ID not available, skipping Dataplex cleanup"
    fi
}

# Remove Cloud Functions
cleanup_cloud_functions() {
    log_info "Cleaning up Cloud Functions..."
    
    # Delete federation metadata sync function
    if gcloud functions describe federation-metadata-sync --region="${REGION}" &>/dev/null; then
        log_info "Deleting federation-metadata-sync function..."
        gcloud functions delete federation-metadata-sync \
            --region="${REGION}" \
            --quiet || log_warning "Failed to delete Cloud Function"
    fi
    
    log_success "Cloud Functions cleanup completed"
}

# Remove BigQuery resources
cleanup_bigquery() {
    log_info "Cleaning up BigQuery resources..."
    
    # Remove BigQuery connection
    if [[ -n "${CONNECTION_ID:-}" ]]; then
        if bq show --connection --location="${REGION}" "${PROJECT_ID}.${REGION}.${CONNECTION_ID}" &>/dev/null; then
            log_info "Deleting BigQuery connection..."
            bq rm --connection \
                --location="${REGION}" \
                "${PROJECT_ID}.${REGION}.${CONNECTION_ID}" || log_warning "Failed to delete BigQuery connection"
        fi
    fi
    
    # Delete BigQuery datasets
    if bq ls -d "${PROJECT_ID}:analytics_federation" &>/dev/null; then
        log_info "Deleting analytics_federation dataset..."
        bq rm -r -f "${PROJECT_ID}:analytics_federation" || log_warning "Failed to delete analytics_federation dataset"
    fi
    
    if bq ls -d "${PROJECT_ID}:cloud_analytics" &>/dev/null; then
        log_info "Deleting cloud_analytics dataset..."
        bq rm -r -f "${PROJECT_ID}:cloud_analytics" || log_warning "Failed to delete cloud_analytics dataset"
    fi
    
    log_success "BigQuery resources cleanup completed"
}

# Remove AlloyDB Omni simulation (Cloud SQL)
cleanup_alloydb() {
    log_info "Cleaning up AlloyDB Omni simulation (Cloud SQL)..."
    
    if [[ -n "${ALLOYDB_INSTANCE:-}" ]]; then
        if gcloud sql instances describe "${ALLOYDB_INSTANCE}" &>/dev/null; then
            log_info "Deleting Cloud SQL instance (this may take 5-10 minutes)..."
            gcloud sql instances delete "${ALLOYDB_INSTANCE}" \
                --quiet || log_warning "Failed to delete Cloud SQL instance"
            
            # Wait for deletion to complete
            log_info "Waiting for instance deletion to complete..."
            while gcloud sql instances describe "${ALLOYDB_INSTANCE}" &>/dev/null; do
                log_info "Instance still exists, waiting..."
                sleep 30
            done
        fi
    else
        log_warning "ALLOYDB_INSTANCE not available, skipping Cloud SQL cleanup"
    fi
    
    log_success "AlloyDB simulation cleanup completed"
}

# Remove Cloud Storage resources
cleanup_storage() {
    log_info "Cleaning up Cloud Storage resources..."
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            log_info "Deleting Cloud Storage bucket and contents..."
            gsutil -m rm -r "gs://${BUCKET_NAME}" || log_warning "Failed to delete storage bucket"
        fi
    else
        log_warning "BUCKET_NAME not available, skipping storage cleanup"
    fi
    
    log_success "Cloud Storage cleanup completed"
}

# Remove IAM resources
cleanup_iam() {
    log_info "Cleaning up IAM resources..."
    
    if [[ -n "${SERVICE_ACCOUNT:-}" ]]; then
        if gcloud iam service-accounts describe "${SERVICE_ACCOUNT}" &>/dev/null; then
            log_info "Deleting service account..."
            gcloud iam service-accounts delete "${SERVICE_ACCOUNT}" \
                --quiet || log_warning "Failed to delete service account"
        fi
    else
        log_warning "SERVICE_ACCOUNT not available, skipping IAM cleanup"
    fi
    
    log_success "IAM resources cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment info file
    if [[ -f "deployment_info.txt" ]]; then
        rm -f deployment_info.txt
        log_info "Removed deployment_info.txt"
    fi
    
    # Remove any temporary files that might have been left
    rm -f /tmp/connection_config.json
    rm -f /tmp/create_sample_data.sql
    rm -f /tmp/federated_analytics_query.sql
    rm -rf /tmp/federation-functions
    
    log_success "Local files cleanup completed"
}

# Optionally delete the entire project
delete_project() {
    echo
    log_warning "Do you want to delete the entire project '${PROJECT_ID}'?"
    log_warning "This will remove ALL resources in the project, including any unrelated resources!"
    read -p "Delete project? (Type 'DELETE' to confirm): " delete_confirmation
    
    if [[ "${delete_confirmation}" == "DELETE" ]]; then
        log_info "Deleting project ${PROJECT_ID}..."
        gcloud projects delete "${PROJECT_ID}" --quiet || log_warning "Failed to delete project"
        log_success "Project deletion initiated. It may take several minutes to complete."
    else
        log_info "Project deletion skipped"
    fi
}

# Display cleanup summary
display_summary() {
    log_success "=========================================="
    log_success "Analytics Federation cleanup completed!"
    log_success "=========================================="
    log_info "Resources that were cleaned up:"
    log_info "✅ Dataplex lakes, zones, and assets"
    log_info "✅ Cloud Functions"
    log_info "✅ BigQuery datasets and connections"
    log_info "✅ Cloud SQL instance (AlloyDB simulation)"
    log_info "✅ Cloud Storage buckets"
    log_info "✅ IAM service accounts"
    log_info "✅ Local files"
    echo
    log_warning "Please verify in the Google Cloud Console that all resources were removed"
    log_warning "Some resources may take additional time to be fully deleted"
}

# Main cleanup function
main() {
    log_info "Starting Cross-Database Analytics Federation cleanup..."
    
    check_prerequisites
    load_deployment_info
    confirm_destruction
    
    # Clean up resources in reverse order of creation
    cleanup_dataplex
    cleanup_cloud_functions
    cleanup_bigquery
    cleanup_alloydb
    cleanup_storage
    cleanup_iam
    cleanup_local_files
    
    # Optional project deletion
    delete_project
    
    display_summary
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warning "Cleanup interrupted by user"
    log_info "Some resources may not have been cleaned up"
    log_info "Run this script again to continue cleanup"
    exit 1
}

# Set trap for interruption
trap cleanup_on_interrupt INT TERM

# Run main function
main "$@"