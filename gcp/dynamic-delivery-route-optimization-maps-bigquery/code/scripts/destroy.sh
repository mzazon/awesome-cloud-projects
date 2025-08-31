#!/bin/bash

# Dynamic Delivery Route Optimization Cleanup Script
# This script removes all resources created by the deployment script:
# - Google Cloud Project and all associated resources
# - Cloud Functions
# - BigQuery datasets and tables
# - Cloud Storage buckets
# - Cloud Scheduler jobs
# - IAM roles and service accounts

set -euo pipefail

# Colors for output
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

# Error handling
error_exit() {
    log_error "Error on line $1"
    log_error "Some resources may not have been deleted. Please check manually."
    exit 1
}

trap 'error_exit $LINENO' ERR

# Configuration
DRY_RUN=${DRY_RUN:-false}
FORCE_DELETE=${FORCE_DELETE:-false}
KEEP_PROJECT=${KEEP_PROJECT:-false}
LOG_FILE="./cleanup_$(date +%Y%m%d_%H%M%S).log"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load deployment info
load_deployment_info() {
    log "Loading deployment information..."
    
    if [[ -f "deployment_info.json" ]]; then
        # Extract info from deployment_info.json
        PROJECT_ID=$(grep -o '"project_id": "[^"]*"' deployment_info.json | cut -d'"' -f4)
        REGION=$(grep -o '"region": "[^"]*"' deployment_info.json | cut -d'"' -f4)
        FUNCTION_NAME=$(grep -o '"function_name": "[^"]*"' deployment_info.json | cut -d'"' -f4)
        BUCKET_NAME=$(grep -o '"bucket_name": "[^"]*"' deployment_info.json | cut -d'"' -f4)
        DATASET_NAME=$(grep -o '"dataset_name": "[^"]*"' deployment_info.json | cut -d'"' -f4)
        
        log_success "Loaded deployment info from deployment_info.json"
        echo "Project ID: ${PROJECT_ID}"
        echo "Region: ${REGION}"
        echo "Function: ${FUNCTION_NAME}"
        echo "Bucket: ${BUCKET_NAME}"
        echo "Dataset: ${DATASET_NAME}"
    else
        log_warning "deployment_info.json not found. Manual input required."
        get_manual_input
    fi
}

# Function to get manual input if deployment_info.json is missing
get_manual_input() {
    log "Please provide the deployment information:"
    
    read -p "Enter Project ID: " PROJECT_ID
    read -p "Enter Region [us-central1]: " REGION
    REGION=${REGION:-us-central1}
    read -p "Enter Function Name (or leave empty to search): " FUNCTION_NAME
    read -p "Enter Bucket Name (or leave empty to search): " BUCKET_NAME
    read -p "Enter Dataset Name [delivery_analytics]: " DATASET_NAME
    DATASET_NAME=${DATASET_NAME:-delivery_analytics}
    
    # If function name not provided, try to find it
    if [[ -z "$FUNCTION_NAME" ]]; then
        log "Searching for route optimization functions..."
        FUNCTION_NAME=$(gcloud functions list --project="${PROJECT_ID}" --format="value(name)" | grep -i "route\|optimizer" | head -1 || echo "")
        if [[ -n "$FUNCTION_NAME" ]]; then
            log "Found function: ${FUNCTION_NAME}"
        else
            log_warning "No route optimization function found"
        fi
    fi
    
    # If bucket name not provided, try to find it
    if [[ -z "$BUCKET_NAME" ]]; then
        log "Searching for delivery data buckets..."
        BUCKET_NAME=$(gsutil ls -p "${PROJECT_ID}" | grep -i "delivery\|route" | head -1 | sed 's|gs://||' | sed 's|/||' || echo "")
        if [[ -n "$BUCKET_NAME" ]]; then
            log "Found bucket: ${BUCKET_NAME}"
        else
            log_warning "No delivery data bucket found"
        fi
    fi
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    echo "=========================================="
    echo "⚠️  DESTRUCTIVE OPERATION WARNING"
    echo "=========================================="
    echo ""
    echo "This will permanently delete the following resources:"
    echo "• Project: ${PROJECT_ID}"
    echo "• All Cloud Functions in the project"
    echo "• All BigQuery datasets and tables"
    echo "• All Cloud Storage buckets and data"
    echo "• All Cloud Scheduler jobs"
    echo "• All IAM roles and service accounts"
    echo ""
    
    if [[ "$FORCE_DELETE" != "true" ]]; then
        echo "Type 'DELETE' to confirm permanent deletion:"
        read -r confirmation
        if [[ "$confirmation" != "DELETE" ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    if [[ "$KEEP_PROJECT" == "true" ]]; then
        log_warning "Project will be kept, only resources within will be deleted"
    else
        echo ""
        echo "Final confirmation - Type 'YES' to delete the entire project:"
        if [[ "$FORCE_DELETE" != "true" ]]; then
            read -r final_confirmation
            if [[ "$final_confirmation" != "YES" ]]; then
                log "Cleanup cancelled by user"
                exit 0
            fi
        fi
    fi
    
    log "Proceeding with cleanup..."
}

# Function to set project context
set_project_context() {
    log "Setting project context..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would set project to ${PROJECT_ID}"
        return 0
    fi
    
    # Set default project
    gcloud config set project "${PROJECT_ID}"
    
    # Verify project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Project ${PROJECT_ID} does not exist or you don't have access"
        exit 1
    fi
    
    log_success "Project context set to ${PROJECT_ID}"
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log "Deleting Cloud Scheduler jobs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete scheduler jobs"
        return 0
    fi
    
    # List and delete all scheduler jobs in the region
    local jobs=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$jobs" ]]; then
        echo "$jobs" | while read -r job; do
            if [[ -n "$job" ]]; then
                log "Deleting scheduler job: $(basename "$job")"
                gcloud scheduler jobs delete "$(basename "$job")" \
                    --location="${REGION}" \
                    --quiet || log_warning "Failed to delete job: $(basename "$job")"
            fi
        done
        log_success "Scheduler jobs deleted"
    else
        log "No scheduler jobs found to delete"
    fi
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete Cloud Functions"
        return 0
    fi
    
    # Delete specific function if name is known
    if [[ -n "$FUNCTION_NAME" ]]; then
        log "Deleting function: ${FUNCTION_NAME}"
        gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --quiet || log_warning "Failed to delete function: ${FUNCTION_NAME}"
    fi
    
    # Delete all functions in the region (as backup)
    local functions=$(gcloud functions list --regions="${REGION}" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$functions" ]]; then
        echo "$functions" | while read -r func; do
            if [[ -n "$func" ]]; then
                log "Deleting function: $(basename "$func")"
                gcloud functions delete "$(basename "$func")" \
                    --region="${REGION}" \
                    --quiet || log_warning "Failed to delete function: $(basename "$func")"
            fi
        done
        log_success "Cloud Functions deleted"
    else
        log "No Cloud Functions found to delete"
    fi
}

# Function to delete BigQuery resources
delete_bigquery_resources() {
    log "Deleting BigQuery resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete BigQuery dataset: ${DATASET_NAME}"
        return 0
    fi
    
    # Delete the dataset and all tables/views
    if [[ -n "$DATASET_NAME" ]]; then
        log "Deleting BigQuery dataset: ${DATASET_NAME}"
        bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" || log_warning "Failed to delete dataset: ${DATASET_NAME}"
        log_success "BigQuery dataset deleted"
    else
        log_warning "No dataset name provided, skipping BigQuery cleanup"
    fi
    
    # Search for and delete any remaining datasets with delivery/route keywords
    local datasets=$(bq ls --format="value(datasetId)" 2>/dev/null | grep -E "(delivery|route|analytics)" || echo "")
    
    if [[ -n "$datasets" ]]; then
        echo "$datasets" | while read -r dataset; do
            if [[ -n "$dataset" ]]; then
                log "Deleting additional dataset: ${dataset}"
                bq rm -r -f "${PROJECT_ID}:${dataset}" || log_warning "Failed to delete dataset: ${dataset}"
            fi
        done
    fi
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    log "Deleting Cloud Storage buckets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete bucket: ${BUCKET_NAME}"
        return 0
    fi
    
    # Delete specific bucket if name is known
    if [[ -n "$BUCKET_NAME" ]]; then
        log "Deleting bucket: ${BUCKET_NAME}"
        gsutil -m rm -r "gs://${BUCKET_NAME}" || log_warning "Failed to delete bucket: ${BUCKET_NAME}"
    fi
    
    # Search for and delete buckets with project prefix
    local buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | sed 's|gs://||' | sed 's|/||' || echo "")
    
    if [[ -n "$buckets" ]]; then
        echo "$buckets" | while read -r bucket; do
            if [[ -n "$bucket" && "$bucket" == *"$PROJECT_ID"* ]]; then
                log "Deleting project bucket: ${bucket}"
                gsutil -m rm -r "gs://${bucket}" || log_warning "Failed to delete bucket: ${bucket}"
            fi
        done
        log_success "Cloud Storage buckets deleted"
    else
        log "No Cloud Storage buckets found to delete"
    fi
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete IAM resources"
        return 0
    fi
    
    # Delete custom IAM roles (if any were created)
    local custom_roles=$(gcloud iam roles list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$custom_roles" ]]; then
        echo "$custom_roles" | while read -r role; do
            if [[ -n "$role" ]]; then
                log "Deleting custom IAM role: $(basename "$role")"
                gcloud iam roles delete "$(basename "$role")" \
                    --project="${PROJECT_ID}" \
                    --quiet || log_warning "Failed to delete role: $(basename "$role")"
            fi
        done
    fi
    
    # Delete service accounts (excluding default ones)
    local service_accounts=$(gcloud iam service-accounts list --format="value(email)" 2>/dev/null | grep -v "compute@\|appspot@" || echo "")
    
    if [[ -n "$service_accounts" ]]; then
        echo "$service_accounts" | while read -r sa; do
            if [[ -n "$sa" ]]; then
                log "Deleting service account: ${sa}"
                gcloud iam service-accounts delete "${sa}" \
                    --quiet || log_warning "Failed to delete service account: ${sa}"
            fi
        done
        log_success "IAM resources deleted"
    else
        log "No custom IAM resources found to delete"
    fi
}

# Function to delete the entire project
delete_project() {
    if [[ "$KEEP_PROJECT" == "true" ]]; then
        log "Keeping project as requested"
        return 0
    fi
    
    log "Deleting entire project..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete project: ${PROJECT_ID}"
        return 0
    fi
    
    # Delete the project
    log "Deleting project: ${PROJECT_ID}"
    gcloud projects delete "${PROJECT_ID}" --quiet
    
    log_success "Project deletion initiated (may take several minutes to complete)"
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment_info.json"
        "function_url.txt"
        "sample_deliveries.csv"
        "route_request.json"
        "lifecycle.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log "DRY RUN: Would remove file: ${file}"
            else
                rm -f "$file"
                log "Removed file: ${file}"
            fi
        fi
    done
    
    # Remove function directory if it exists
    if [[ -d "route-optimizer-function" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY RUN: Would remove directory: route-optimizer-function"
        else
            rm -rf "route-optimizer-function"
            log "Removed directory: route-optimizer-function"
        fi
    fi
    
    log_success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would verify cleanup"
        return 0
    fi
    
    if [[ "$KEEP_PROJECT" == "true" ]]; then
        log "Verifying resource cleanup within project..."
        
        # Check for remaining functions
        local remaining_functions=$(gcloud functions list --format="value(name)" 2>/dev/null | wc -l)
        log "Remaining Cloud Functions: ${remaining_functions}"
        
        # Check for remaining datasets
        local remaining_datasets=$(bq ls --format="value(datasetId)" 2>/dev/null | wc -l)
        log "Remaining BigQuery datasets: ${remaining_datasets}"
        
        # Check for remaining buckets
        local remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | wc -l)
        log "Remaining Cloud Storage buckets: ${remaining_buckets}"
        
        if [[ "$remaining_functions" -eq 0 && "$remaining_datasets" -eq 0 && "$remaining_buckets" -eq 0 ]]; then
            log_success "All resources successfully cleaned up"
        else
            log_warning "Some resources may still exist. Please check manually."
        fi
    else
        log "Project deletion initiated. Full cleanup will complete in a few minutes."
    fi
}

# Function to generate cleanup report
generate_cleanup_report() {
    log "Generating cleanup report..."
    
    cat > cleanup_report.txt << EOF
Route Optimization Cleanup Report
Generated: $(date)
Project ID: ${PROJECT_ID}
Region: ${REGION}

Resources Processed:
- Cloud Scheduler Jobs: Deleted
- Cloud Functions: Deleted
- BigQuery Datasets: Deleted
- Cloud Storage Buckets: Deleted
- IAM Resources: Deleted
- Project: $(if [[ "$KEEP_PROJECT" == "true" ]]; then echo "Kept"; else echo "Deleted"; fi)

Status: $(if [[ "$DRY_RUN" == "true" ]]; then echo "DRY RUN - No actual changes made"; else echo "Cleanup completed"; fi)

Log File: ${LOG_FILE}
EOF
    
    log_success "Cleanup report saved to cleanup_report.txt"
}

# Main cleanup function
main() {
    echo "=========================================="
    echo "Dynamic Delivery Route Optimization"
    echo "GCP Cleanup Script"
    echo "=========================================="
    echo ""
    
    # Start logging
    exec > >(tee -a "${LOG_FILE}")
    exec 2>&1
    
    log "Starting cleanup at $(date)"
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_info
    confirm_deletion
    set_project_context
    delete_scheduler_jobs
    delete_cloud_functions
    delete_bigquery_resources
    delete_storage_buckets
    delete_iam_resources
    delete_project
    cleanup_local_files
    verify_cleanup
    generate_cleanup_report
    
    echo ""
    echo "=========================================="
    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "Dry run completed - no resources were actually deleted"
    else
        log_success "Cleanup completed successfully!"
    fi
    echo "=========================================="
    echo ""
    
    if [[ "$KEEP_PROJECT" != "true" ]]; then
        echo "Note: Project deletion may take several minutes to complete fully."
        echo "You can verify deletion status with: gcloud projects describe ${PROJECT_ID}"
    fi
    
    echo ""
    log "Cleanup log saved to: ${LOG_FILE}"
    log "Cleanup report saved to: cleanup_report.txt"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

This script cleans up all resources created by the route optimization deployment.

Options:
  --dry-run              Show what would be deleted without making changes
  --force-delete         Skip confirmation prompts
  --keep-project         Delete resources but keep the GCP project
  --help                 Show this help message

Examples:
  $0                     # Interactive cleanup with confirmations
  $0 --dry-run           # See what would be deleted
  $0 --force-delete      # Delete everything without prompts
  $0 --keep-project      # Delete resources but keep project

Environment Variables:
  DRY_RUN=true           # Same as --dry-run
  FORCE_DELETE=true      # Same as --force-delete
  KEEP_PROJECT=true      # Same as --keep-project

Warning: This script will permanently delete resources. Make sure you have
backups of any important data before proceeding.
EOF
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force-delete)
            FORCE_DELETE=true
            shift
            ;;
        --keep-project)
            KEEP_PROJECT=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main "$@"