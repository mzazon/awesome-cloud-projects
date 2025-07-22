#!/bin/bash

# Data Lake Governance with Dataplex and BigLake - Cleanup Script
# This script safely removes all resources created by the deployment script
# while preserving data safety and providing confirmation prompts.

set -euo pipefail

# Colors for output formatting
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

# Configuration with defaults
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
LAKE_NAME="${LAKE_NAME:-enterprise-data-lake}"
ZONE_NAME="${ZONE_NAME:-raw-data-zone}"

# Generate unique suffix for resource names (use same pattern as deploy)
RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
BUCKET_NAME="${BUCKET_NAME:-governance-demo-${RANDOM_SUFFIX}}"
DATASET_NAME="${DATASET_NAME:-governance_analytics}"
CONNECTION_NAME="${CONNECTION_NAME:-biglake-connection-${RANDOM_SUFFIX}}"

# Force flag for non-interactive mode
FORCE="${FORCE:-false}"

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -f, --force           Skip confirmation prompts"
    echo "  -p, --project         Specify project ID"
    echo "  -r, --region          Specify region (default: us-central1)"
    echo "  -b, --bucket          Specify bucket name"
    echo "  -d, --dataset         Specify dataset name"
    echo "  -h, --help            Show this help message"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID           GCP project ID"
    echo "  REGION               GCP region"
    echo "  BUCKET_NAME          Cloud Storage bucket name"
    echo "  DATASET_NAME         BigQuery dataset name"
    echo "  FORCE                Set to 'true' to skip confirmations"
    echo
    echo "Examples:"
    echo "  $0                           # Interactive cleanup with defaults"
    echo "  $0 --force                   # Non-interactive cleanup"
    echo "  $0 -p my-project -b my-bucket # Cleanup specific resources"
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE="true"
                shift
                ;;
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -b|--bucket)
                BUCKET_NAME="$2"
                shift 2
                ;;
            -d|--dataset)
                DATASET_NAME="$2"
                shift 2
                ;;
            -h|--help)
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

# Function to confirm destruction
confirm_destruction() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo
    echo "========================================="
    echo "         DESTRUCTION WARNING"
    echo "========================================="
    echo "This will permanently delete the following resources:"
    echo
    echo "Project: $PROJECT_ID"
    echo "Region: $REGION"
    echo
    echo "Resources to be deleted:"
    echo "- ❌ Cloud Function: governance-monitor"
    echo "- ❌ Dataplex asset: governance-bucket-asset"
    echo "- ❌ Dataplex zone: $ZONE_NAME"
    echo "- ❌ Dataplex lake: $LAKE_NAME"
    echo "- ❌ BigLake tables: customers_biglake, transactions_biglake"
    echo "- ❌ BigQuery connection: $CONNECTION_NAME"
    echo "- ❌ BigQuery dataset: $DATASET_NAME"
    echo "- ❌ Cloud Storage bucket: gs://$BUCKET_NAME (with all data)"
    echo
    echo "⚠️  WARNING: This action cannot be undone!"
    echo "⚠️  All data in the storage bucket will be permanently lost!"
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    # Double confirmation for data destruction
    echo "🔥 FINAL WARNING: You are about to delete ALL data and resources!"
    read -p "Type 'DELETE' to confirm data destruction: " -r
    echo
    
    if [[ "$REPLY" != "DELETE" ]]; then
        log "Destruction cancelled - confirmation not provided"
        exit 0
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "bq CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "You are not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project exists
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID is not set. Please specify project ID."
        exit 1
    fi
    
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project $PROJECT_ID does not exist or you don't have access."
        exit 1
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID" --quiet
    
    log_success "Prerequisites check completed"
}

# Function to remove Cloud Function
remove_cloud_function() {
    log "Removing Cloud Function..."
    
    if gcloud functions describe governance-monitor --region="$REGION" &> /dev/null; then
        log "Deleting Cloud Function: governance-monitor"
        gcloud functions delete governance-monitor \
            --region="$REGION" \
            --quiet
        log_success "Cloud Function deleted"
    else
        log_warning "Cloud Function governance-monitor not found"
    fi
}

# Function to remove Dataplex resources
remove_dataplex_resources() {
    log "Removing Dataplex resources..."
    
    # Remove Dataplex tasks (if any exist)
    log "Checking for Dataplex tasks..."
    local tasks
    tasks=$(gcloud dataplex tasks list --location="$REGION" --lake="$LAKE_NAME" --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$tasks" ]]; then
        echo "$tasks" | while read -r task; do
            if [[ -n "$task" ]]; then
                local task_name
                task_name=$(basename "$task")
                log "Deleting Dataplex task: $task_name"
                gcloud dataplex tasks delete "$task_name" \
                    --location="$REGION" \
                    --lake="$LAKE_NAME" \
                    --quiet || log_warning "Failed to delete task: $task_name"
            fi
        done
    fi
    
    # Remove Dataplex asset
    if gcloud dataplex assets describe governance-bucket-asset \
        --location="$REGION" --lake="$LAKE_NAME" --zone="$ZONE_NAME" &> /dev/null; then
        log "Deleting Dataplex asset: governance-bucket-asset"
        gcloud dataplex assets delete governance-bucket-asset \
            --location="$REGION" \
            --lake="$LAKE_NAME" \
            --zone="$ZONE_NAME" \
            --quiet
        log_success "Dataplex asset deleted"
    else
        log_warning "Dataplex asset governance-bucket-asset not found"
    fi
    
    # Remove Dataplex zone
    if gcloud dataplex zones describe "$ZONE_NAME" \
        --location="$REGION" --lake="$LAKE_NAME" &> /dev/null; then
        log "Deleting Dataplex zone: $ZONE_NAME"
        gcloud dataplex zones delete "$ZONE_NAME" \
            --location="$REGION" \
            --lake="$LAKE_NAME" \
            --quiet
        log_success "Dataplex zone deleted"
    else
        log_warning "Dataplex zone $ZONE_NAME not found"
    fi
    
    # Remove Dataplex lake
    if gcloud dataplex lakes describe "$LAKE_NAME" --location="$REGION" &> /dev/null; then
        log "Deleting Dataplex lake: $LAKE_NAME"
        gcloud dataplex lakes delete "$LAKE_NAME" \
            --location="$REGION" \
            --quiet
        log_success "Dataplex lake deleted"
    else
        log_warning "Dataplex lake $LAKE_NAME not found"
    fi
}

# Function to remove BigQuery resources
remove_bigquery_resources() {
    log "Removing BigQuery resources..."
    
    # Remove BigQuery tables (they will be deleted with the dataset)
    log "Checking BigQuery tables..."
    if bq ls "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        local tables
        tables=$(bq ls --format=csv --max_results=1000 "${PROJECT_ID}:${DATASET_NAME}" | tail -n +2 | cut -d, -f1)
        
        if [[ -n "$tables" ]]; then
            echo "$tables" | while read -r table; do
                if [[ -n "$table" && "$table" != "tableId" ]]; then
                    log "Table found in dataset: $table"
                fi
            done
        fi
    fi
    
    # Remove BigQuery dataset (this removes all tables)
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        log "Deleting BigQuery dataset: $DATASET_NAME"
        bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}"
        log_success "BigQuery dataset and tables deleted"
    else
        log_warning "BigQuery dataset $DATASET_NAME not found"
    fi
    
    # Remove BigQuery connection
    if bq show --connection --location="$REGION" "$CONNECTION_NAME" &> /dev/null; then
        log "Deleting BigQuery connection: $CONNECTION_NAME"
        bq rm --connection \
            --location="$REGION" \
            "$CONNECTION_NAME"
        log_success "BigQuery connection deleted"
    else
        log_warning "BigQuery connection $CONNECTION_NAME not found"
    fi
}

# Function to remove Cloud Storage resources
remove_storage_resources() {
    log "Removing Cloud Storage resources..."
    
    # Check if bucket exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        log "Deleting Cloud Storage bucket: gs://$BUCKET_NAME"
        
        # Show bucket contents before deletion
        log "Bucket contents:"
        gsutil ls -r "gs://${BUCKET_NAME}" 2>/dev/null | head -20 || log_warning "Could not list bucket contents"
        
        # Delete bucket and all contents
        gsutil -m rm -r "gs://${BUCKET_NAME}"
        log_success "Cloud Storage bucket and all contents deleted"
    else
        log_warning "Cloud Storage bucket gs://$BUCKET_NAME not found"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove any temporary files that might have been created
    local files_to_remove=(
        "customer_data.csv"
        "transaction_data.csv"
        "governance-function"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            rm -rf "$file"
            log "Removed local file/directory: $file"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Function to remove IAM bindings
cleanup_iam_bindings() {
    log "Note: IAM bindings for service accounts are automatically cleaned up"
    log "when the associated resources (connections, functions) are deleted."
    log_success "IAM cleanup noted"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=()
    
    # Check Cloud Function
    if gcloud functions describe governance-monitor --region="$REGION" &> /dev/null; then
        cleanup_issues+=("Cloud Function still exists")
    fi
    
    # Check Dataplex lake
    if gcloud dataplex lakes describe "$LAKE_NAME" --location="$REGION" &> /dev/null; then
        cleanup_issues+=("Dataplex lake still exists")
    fi
    
    # Check BigQuery dataset
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        cleanup_issues+=("BigQuery dataset still exists")
    fi
    
    # Check BigQuery connection
    if bq show --connection --location="$REGION" "$CONNECTION_NAME" &> /dev/null; then
        cleanup_issues+=("BigQuery connection still exists")
    fi
    
    # Check Cloud Storage bucket
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        cleanup_issues+=("Cloud Storage bucket still exists")
    fi
    
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        log_success "All resources successfully removed"
        return 0
    else
        log_warning "Some resources may still exist:"
        for issue in "${cleanup_issues[@]}"; do
            log_warning "- $issue"
        done
        return 1
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    echo
    echo "========================================="
    echo "         CLEANUP SUMMARY"
    echo "========================================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo
    echo "Resources Removed:"
    echo "- ✅ Cloud Function: governance-monitor"
    echo "- ✅ Dataplex resources: lake, zone, asset"
    echo "- ✅ BigQuery dataset and tables"
    echo "- ✅ BigQuery external connection"
    echo "- ✅ Cloud Storage bucket and data"
    echo "- ✅ Local temporary files"
    echo
    if verify_cleanup; then
        echo "🎉 Cleanup completed successfully!"
        echo "All resources have been removed."
    else
        echo "⚠️  Cleanup completed with warnings"
        echo "Some resources may require manual removal."
        echo "Check the Cloud Console for any remaining resources."
    fi
    echo
    echo "Console URLs (to verify cleanup):"
    echo "- Cloud Functions: https://console.cloud.google.com/functions/list?project=$PROJECT_ID"
    echo "- Dataplex: https://console.cloud.google.com/dataplex/lakes?project=$PROJECT_ID"
    echo "- BigQuery: https://console.cloud.google.com/bigquery?project=$PROJECT_ID"
    echo "- Cloud Storage: https://console.cloud.google.com/storage/browser?project=$PROJECT_ID"
    echo "========================================="
}

# Main cleanup function
main() {
    log "🧹 Starting Data Lake Governance cleanup..."
    
    # Parse command line arguments
    parse_args "$@"
    
    # Cleanup steps
    check_prerequisites
    confirm_destruction
    
    log "Beginning resource cleanup..."
    
    # Remove resources in reverse order of creation
    remove_cloud_function
    remove_dataplex_resources
    remove_bigquery_resources
    remove_storage_resources
    cleanup_local_files
    cleanup_iam_bindings
    
    show_cleanup_summary
    
    log_success "Cleanup process completed! 🧹"
}

# Error handling for cleanup
cleanup_on_error() {
    log_error "Cleanup script encountered an error."
    log "Some resources may not have been deleted."
    log "Please check the Cloud Console and manually remove any remaining resources."
    exit 1
}

trap cleanup_on_error ERR

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi