#!/bin/bash
set -euo pipefail

# Document Validation Workflows with Document AI and Cloud Workflows - Cleanup Script
# This script removes all resources created by the deployment script

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Command '$1' not found. Please install it before running this script."
        exit 1
    fi
}

# Function to check if user is authenticated
check_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active Google Cloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
}

# Function to load environment variables
load_env_vars() {
    local env_files=("bucket_names.env" "processor_ids.env" "dataset_name.env" "workflow_name.env" "trigger_name.env" "service_account.env")
    
    for env_file in "${env_files[@]}"; do
        if [[ -f "$env_file" ]]; then
            source "$env_file"
            info "Loaded environment variables from $env_file"
        else
            warn "Environment file $env_file not found - some resources may not be cleaned up"
        fi
    done
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    warn "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "  • Document AI processors and processed documents"
    echo "  • Cloud Storage buckets and all contents"
    echo "  • Cloud Workflows and execution history"
    echo "  • BigQuery dataset and all data"
    echo "  • Eventarc triggers and configurations"
    echo "  • IAM service accounts and permissions"
    echo ""
    echo "💰 This action will stop all ongoing charges."
    echo ""
    
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        warn "FORCE_DESTROY is set to true, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    read -p "Type 'DELETE' to confirm permanent deletion: " -r
    echo ""
    
    if [[ "$REPLY" != "DELETE" ]]; then
        info "Destruction cancelled - incorrect confirmation"
        exit 0
    fi
    
    log "Destruction confirmed, proceeding with cleanup..."
}

# Function to delete Eventarc trigger
delete_eventarc_trigger() {
    if [[ -n "${TRIGGER_NAME:-}" ]]; then
        log "Deleting Eventarc trigger: ${TRIGGER_NAME}"
        
        if gcloud eventarc triggers delete "${TRIGGER_NAME}" \
            --location="${REGION}" \
            --quiet &> /dev/null; then
            log "✅ Eventarc trigger deleted successfully"
        else
            warn "Failed to delete Eventarc trigger or it may not exist"
        fi
    else
        warn "TRIGGER_NAME not set, skipping Eventarc trigger deletion"
    fi
}

# Function to delete service account
delete_service_account() {
    if [[ -n "${EVENTARC_SA_EMAIL:-}" ]]; then
        log "Deleting service account: ${EVENTARC_SA_EMAIL}"
        
        if gcloud iam service-accounts delete "${EVENTARC_SA_EMAIL}" \
            --quiet &> /dev/null; then
            log "✅ Service account deleted successfully"
        else
            warn "Failed to delete service account or it may not exist"
        fi
    else
        warn "EVENTARC_SA_EMAIL not set, skipping service account deletion"
    fi
}

# Function to delete Cloud Workflows
delete_workflow() {
    if [[ -n "${WORKFLOW_NAME:-}" ]]; then
        log "Deleting Cloud Workflow: ${WORKFLOW_NAME}"
        
        if gcloud workflows delete "${WORKFLOW_NAME}" \
            --location="${REGION}" \
            --quiet &> /dev/null; then
            log "✅ Cloud Workflow deleted successfully"
        else
            warn "Failed to delete workflow or it may not exist"
        fi
    else
        warn "WORKFLOW_NAME not set, skipping workflow deletion"
    fi
}

# Function to delete Document AI processors
delete_processors() {
    if [[ -n "${FORM_PROCESSOR_ID:-}" ]]; then
        log "Deleting Form Parser processor: ${FORM_PROCESSOR_ID}"
        
        if gcloud documentai processors delete "${FORM_PROCESSOR_ID}" \
            --location="${REGION}" \
            --quiet &> /dev/null; then
            log "✅ Form Parser processor deleted successfully"
        else
            warn "Failed to delete Form Parser processor or it may not exist"
        fi
    else
        warn "FORM_PROCESSOR_ID not set, skipping Form Parser deletion"
    fi
    
    if [[ -n "${INVOICE_PROCESSOR_ID:-}" ]]; then
        log "Deleting Invoice Parser processor: ${INVOICE_PROCESSOR_ID}"
        
        if gcloud documentai processors delete "${INVOICE_PROCESSOR_ID}" \
            --location="${REGION}" \
            --quiet &> /dev/null; then
            log "✅ Invoice Parser processor deleted successfully"
        else
            warn "Failed to delete Invoice Parser processor or it may not exist"
        fi
    else
        warn "INVOICE_PROCESSOR_ID not set, skipping Invoice Parser deletion"
    fi
}

# Function to delete storage buckets
delete_buckets() {
    local buckets=("${INPUT_BUCKET:-}" "${VALID_BUCKET:-}" "${INVALID_BUCKET:-}" "${REVIEW_BUCKET:-}")
    
    for bucket in "${buckets[@]}"; do
        if [[ -n "$bucket" ]]; then
            log "Deleting storage bucket: gs://${bucket}"
            
            # First, try to delete all objects in the bucket
            if gsutil -m rm -r "gs://${bucket}/*" &> /dev/null; then
                info "Deleted all objects in gs://${bucket}"
            else
                info "No objects to delete in gs://${bucket} or bucket is empty"
            fi
            
            # Then delete the bucket itself
            if gsutil rb "gs://${bucket}" &> /dev/null; then
                log "✅ Storage bucket gs://${bucket} deleted successfully"
            else
                warn "Failed to delete storage bucket gs://${bucket} or it may not exist"
            fi
        else
            warn "Bucket name not set, skipping bucket deletion"
        fi
    done
}

# Function to delete BigQuery dataset
delete_bigquery_dataset() {
    if [[ -n "${DATASET_NAME:-}" ]]; then
        log "Deleting BigQuery dataset: ${DATASET_NAME}"
        
        if bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
            log "✅ BigQuery dataset deleted successfully"
        else
            warn "Failed to delete BigQuery dataset or it may not exist"
        fi
    else
        warn "DATASET_NAME not set, skipping BigQuery dataset deletion"
    fi
}

# Function to remove IAM policy bindings
remove_iam_bindings() {
    log "Removing IAM policy bindings..."
    
    # Remove bindings from Compute Engine default service account
    if [[ -n "${PROJECT_ID:-}" ]]; then
        local compute_sa="${PROJECT_ID}-compute@developer.gserviceaccount.com"
        local compute_roles=(
            "roles/documentai.apiUser"
            "roles/storage.objectAdmin"
            "roles/bigquery.dataEditor"
            "roles/bigquery.jobUser"
        )
        
        for role in "${compute_roles[@]}"; do
            info "Removing ${role} from Compute Engine service account..."
            if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${compute_sa}" \
                --role="${role}" \
                --quiet &> /dev/null; then
                log "✅ Role ${role} removed successfully"
            else
                warn "Failed to remove role ${role} or it may not exist"
            fi
        done
    fi
    
    # Note: Service account IAM bindings are automatically removed when the service account is deleted
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "bucket_names.env"
        "processor_ids.env"
        "dataset_name.env"
        "workflow_name.env"
        "trigger_name.env"
        "service_account.env"
        "document-validation-workflow.yaml"
        "sample_invoice.txt"
        "sample_form.txt"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            info "Removed local file: $file"
        fi
    done
    
    log "✅ Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check if any Document AI processors remain
    if [[ -n "${FORM_PROCESSOR_ID:-}" || -n "${INVOICE_PROCESSOR_ID:-}" ]]; then
        local remaining_processors
        remaining_processors=$(gcloud documentai processors list \
            --location="${REGION}" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$remaining_processors" ]]; then
            info "Some Document AI processors may still exist (normal if shared)"
        fi
    fi
    
    # Check if workflow exists
    if [[ -n "${WORKFLOW_NAME:-}" ]]; then
        if gcloud workflows describe "${WORKFLOW_NAME}" \
            --location="${REGION}" &> /dev/null; then
            warn "Workflow ${WORKFLOW_NAME} still exists"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if BigQuery dataset exists
    if [[ -n "${DATASET_NAME:-}" ]]; then
        if bq show "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
            warn "BigQuery dataset ${DATASET_NAME} still exists"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if buckets exist
    local buckets=("${INPUT_BUCKET:-}" "${VALID_BUCKET:-}" "${INVALID_BUCKET:-}" "${REVIEW_BUCKET:-}")
    for bucket in "${buckets[@]}"; do
        if [[ -n "$bucket" ]]; then
            if gsutil ls "gs://${bucket}" &> /dev/null; then
                warn "Storage bucket gs://${bucket} still exists"
                ((cleanup_issues++))
            fi
        fi
    done
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log "✅ All resources cleaned up successfully"
        return 0
    else
        warn "Some resources may not have been fully cleaned up"
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "=================================="
    echo "🧹 Cleanup Actions Completed:"
    echo "  • Deleted Eventarc trigger"
    echo "  • Removed service account"
    echo "  • Deleted Cloud Workflows"
    echo "  • Deleted Document AI processors"
    echo "  • Removed storage buckets and contents"
    echo "  • Deleted BigQuery dataset"
    echo "  • Removed IAM policy bindings"
    echo "  • Cleaned up local configuration files"
    echo ""
    echo "💰 Cost Impact:"
    echo "  • All billable resources have been removed"
    echo "  • No ongoing charges will be incurred"
    echo "  • Historical usage charges may still appear on your bill"
    echo ""
    echo "🔧 Next Steps:"
    echo "  • Verify no unexpected charges appear on your bill"
    echo "  • Check Google Cloud Console to confirm resource deletion"
    echo "  • Review any remaining resources in your project"
}

# Function to handle cleanup with retry logic
cleanup_with_retry() {
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        log "Cleanup attempt $((retry_count + 1)) of $max_retries"
        
        # Delete resources in reverse order of creation
        delete_eventarc_trigger
        delete_service_account
        delete_workflow
        delete_processors
        delete_buckets
        delete_bigquery_dataset
        remove_iam_bindings
        
        # Wait for deletions to propagate
        info "Waiting for deletions to propagate..."
        sleep 30
        
        # Verify cleanup
        if verify_cleanup; then
            log "✅ Cleanup completed successfully"
            break
        else
            ((retry_count++))
            if [[ $retry_count -lt $max_retries ]]; then
                warn "Some resources remain, retrying cleanup..."
                sleep 60
            else
                warn "Maximum retry attempts reached, some resources may remain"
            fi
        fi
    done
}

# Main cleanup function
main() {
    log "Starting Document Validation Workflows cleanup..."
    
    # Check prerequisites
    info "Checking prerequisites..."
    check_command "gcloud"
    check_command "gsutil"
    check_command "bq"
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo '')}"
    export REGION="${REGION:-us-central1}"
    
    # Check authentication
    check_auth
    
    # Configure gcloud
    if [[ -n "${PROJECT_ID}" ]]; then
        gcloud config set project "${PROJECT_ID}"
        gcloud config set compute/region "${REGION}"
        info "Using project: ${PROJECT_ID}"
    else
        error "PROJECT_ID not set and cannot be determined from gcloud config"
        exit 1
    fi
    
    # Load environment variables from previous deployment
    load_env_vars
    
    # Confirm destruction
    confirm_destruction
    
    # Perform cleanup with retry logic
    cleanup_with_retry
    
    # Clean up local files
    cleanup_local_files
    
    # Display summary
    display_cleanup_summary
    
    log "🎉 Document Validation Workflows cleanup completed!"
    log "💰 All billable resources have been removed to prevent ongoing charges."
}

# Handle script arguments
case "${1:-}" in
    --force)
        export FORCE_DESTROY=true
        ;;
    --help)
        echo "Usage: $0 [--force] [--help]"
        echo ""
        echo "Options:"
        echo "  --force    Skip confirmation prompts"
        echo "  --help     Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  PROJECT_ID    Google Cloud project ID"
        echo "  REGION        Google Cloud region (default: us-central1)"
        echo ""
        exit 0
        ;;
    "")
        # No arguments, proceed normally
        ;;
    *)
        error "Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main function
main "$@"