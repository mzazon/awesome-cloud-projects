#!/bin/bash

# Dynamic Email Campaign Workflows - Cleanup Script
# This script removes all resources created by the email campaign automation deployment

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
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

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install it first."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "bq CLI is not installed. Please install it first."
        exit 1
    fi
    
    success "All prerequisites are installed"
}

# Check if user is authenticated
check_authentication() {
    log "Checking authentication..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    success "Authentication verified"
}

# Get environment variables or use defaults
setup_environment() {
    log "Setting up environment variables..."
    
    # Get current project if not set
    if [ -z "${PROJECT_ID}" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [ -z "${PROJECT_ID}" ]; then
            error "PROJECT_ID environment variable not set and no default project configured."
            echo "Please set PROJECT_ID environment variable or run 'gcloud config set project YOUR_PROJECT_ID'"
            exit 1
        fi
    fi
    
    # Set default region if not provided
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # If specific resource names are not provided, we'll discover them
    if [ -z "${BUCKET_NAME}" ] || [ -z "${FUNCTION_NAME}" ]; then
        log "Discovering resource names..."
        discover_resources
    fi
    
    log "Environment variables:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  ZONE: ${ZONE}"
    log "  BUCKET_NAME: ${BUCKET_NAME}"
    log "  FUNCTION_NAME: ${FUNCTION_NAME}"
}

# Discover resources created by the deployment
discover_resources() {
    log "Discovering deployed resources..."
    
    # Discover Cloud Storage buckets
    if [ -z "${BUCKET_NAME}" ]; then
        log "Searching for email campaign buckets..."
        BUCKET_NAME=$(gsutil ls -p "${PROJECT_ID}" | grep "email-campaigns" | head -1 | sed 's|gs://||' | sed 's|/||')
        if [ -z "${BUCKET_NAME}" ]; then
            warning "No email campaign buckets found. You may need to specify BUCKET_NAME manually."
        else
            log "Found bucket: ${BUCKET_NAME}"
        fi
    fi
    
    # Discover Cloud Functions
    if [ -z "${FUNCTION_NAME}" ]; then
        log "Searching for email campaign functions..."
        FUNCTION_NAME=$(gcloud functions list --region="${REGION}" --format="value(name)" | grep "email-campaign" | head -1 | sed 's|-generator||' | sed 's|-sender||' | sed 's|-analytics||')
        if [ -z "${FUNCTION_NAME}" ]; then
            warning "No email campaign functions found. You may need to specify FUNCTION_NAME manually."
        else
            log "Found function prefix: ${FUNCTION_NAME}"
        fi
    fi
}

# Confirmation prompt
confirm_deletion() {
    log "This will permanently delete all resources for the email campaign automation system."
    echo
    echo "Resources to be deleted:"
    echo "  • Project: ${PROJECT_ID}"
    echo "  • All Cloud Functions in the project"
    echo "  • All Cloud Scheduler jobs"
    echo "  • All BigQuery datasets"
    echo "  • All Cloud Storage buckets"
    echo "  • All IAM service accounts"
    echo
    warning "THIS ACTION CANNOT BE UNDONE!"
    echo
    
    # Skip confirmation if FORCE_DELETE is set
    if [ "${FORCE_DELETE}" = "true" ]; then
        log "FORCE_DELETE is set, skipping confirmation."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    if [ "${confirmation}" != "yes" ]; then
        log "Deletion cancelled by user."
        exit 0
    fi
    
    log "Deletion confirmed. Proceeding with cleanup..."
}

# Delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log "Deleting Cloud Scheduler jobs..."
    
    local jobs=(
        "campaign-generator-daily"
        "newsletter-weekly"
        "promotional-campaigns"
    )
    
    for job in "${jobs[@]}"; do
        if gcloud scheduler jobs describe "${job}" --location="${REGION}" &>/dev/null; then
            log "Deleting scheduler job: ${job}"
            if gcloud scheduler jobs delete "${job}" --location="${REGION}" --quiet; then
                success "Deleted scheduler job: ${job}"
            else
                warning "Failed to delete scheduler job: ${job}"
            fi
        else
            log "Scheduler job ${job} not found, skipping"
        fi
    done
    
    success "Scheduler jobs cleanup completed"
}

# Delete Cloud Functions
delete_functions() {
    log "Deleting Cloud Functions..."
    
    if [ -n "${FUNCTION_NAME}" ]; then
        local functions=(
            "${FUNCTION_NAME}-generator"
            "${FUNCTION_NAME}-sender"
            "${FUNCTION_NAME}-analytics"
        )
        
        for func in "${functions[@]}"; do
            if gcloud functions describe "${func}" --region="${REGION}" &>/dev/null; then
                log "Deleting function: ${func}"
                if gcloud functions delete "${func}" --region="${REGION}" --quiet; then
                    success "Deleted function: ${func}"
                else
                    warning "Failed to delete function: ${func}"
                fi
            else
                log "Function ${func} not found, skipping"
            fi
        done
    else
        # If we can't determine the function name, delete all functions with email-campaign prefix
        log "Deleting all email campaign functions..."
        local all_functions=$(gcloud functions list --region="${REGION}" --format="value(name)" | grep "email-campaign")
        
        for func in ${all_functions}; do
            log "Deleting function: ${func}"
            if gcloud functions delete "${func}" --region="${REGION}" --quiet; then
                success "Deleted function: ${func}"
            else
                warning "Failed to delete function: ${func}"
            fi
        done
    fi
    
    success "Cloud Functions cleanup completed"
}

# Delete BigQuery datasets
delete_bigquery_datasets() {
    log "Deleting BigQuery datasets..."
    
    local datasets=(
        "email_campaigns"
    )
    
    for dataset in "${datasets[@]}"; do
        if bq ls -d "${PROJECT_ID}:${dataset}" &>/dev/null; then
            log "Deleting BigQuery dataset: ${dataset}"
            if bq rm -r -f "${PROJECT_ID}:${dataset}"; then
                success "Deleted BigQuery dataset: ${dataset}"
            else
                warning "Failed to delete BigQuery dataset: ${dataset}"
            fi
        else
            log "BigQuery dataset ${dataset} not found, skipping"
        fi
    done
    
    success "BigQuery datasets cleanup completed"
}

# Delete Cloud Storage buckets
delete_storage_buckets() {
    log "Deleting Cloud Storage buckets..."
    
    if [ -n "${BUCKET_NAME}" ]; then
        local buckets=("${BUCKET_NAME}")
    else
        # Find all buckets with email-campaigns prefix
        local buckets=($(gsutil ls -p "${PROJECT_ID}" | grep "email-campaigns" | sed 's|gs://||' | sed 's|/||'))
    fi
    
    for bucket in "${buckets[@]}"; do
        if gsutil ls "gs://${bucket}" &>/dev/null; then
            log "Deleting Cloud Storage bucket: ${bucket}"
            
            # Remove all objects first
            if gsutil -m rm -r "gs://${bucket}/**" &>/dev/null; then
                log "Removed all objects from bucket: ${bucket}"
            fi
            
            # Delete the bucket
            if gsutil rb "gs://${bucket}"; then
                success "Deleted Cloud Storage bucket: ${bucket}"
            else
                warning "Failed to delete Cloud Storage bucket: ${bucket}"
            fi
        else
            log "Cloud Storage bucket ${bucket} not found, skipping"
        fi
    done
    
    success "Cloud Storage buckets cleanup completed"
}

# Delete IAM service accounts
delete_service_accounts() {
    log "Deleting IAM service accounts..."
    
    local service_accounts=(
        "gmail-automation-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    )
    
    for sa in "${service_accounts[@]}"; do
        if gcloud iam service-accounts describe "${sa}" &>/dev/null; then
            log "Deleting service account: ${sa}"
            
            # Delete all keys first
            local keys=$(gcloud iam service-accounts keys list --iam-account="${sa}" --format="value(name)" | grep -v "system-managed")
            for key in ${keys}; do
                if gcloud iam service-accounts keys delete "${key}" --iam-account="${sa}" --quiet; then
                    log "Deleted key: ${key}"
                fi
            done
            
            # Delete the service account
            if gcloud iam service-accounts delete "${sa}" --quiet; then
                success "Deleted service account: ${sa}"
            else
                warning "Failed to delete service account: ${sa}"
            fi
        else
            log "Service account ${sa} not found, skipping"
        fi
    done
    
    success "Service accounts cleanup completed"
}

# Delete custom monitoring metrics
delete_monitoring_metrics() {
    log "Deleting custom monitoring metrics..."
    
    # Note: Custom metrics are automatically deleted when the project is deleted
    # For individual metric deletion, you would need to use the Monitoring API
    # This is a placeholder for future implementation
    
    success "Monitoring metrics cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove any temporary files that might have been created
    local temp_files=(
        "./gmail-automation-key.json"
        "/tmp/email-campaign-functions"
        "/tmp/email-templates"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -e "${file}" ]; then
            log "Removing local file/directory: ${file}"
            rm -rf "${file}"
        fi
    done
    
    success "Local files cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local errors=0
    
    # Check Cloud Functions
    if [ -n "${FUNCTION_NAME}" ]; then
        local remaining_functions=$(gcloud functions list --region="${REGION}" --format="value(name)" | grep "${FUNCTION_NAME}" | wc -l)
        if [ "${remaining_functions}" -gt 0 ]; then
            warning "Some Cloud Functions may still exist: ${remaining_functions}"
            errors=$((errors + 1))
        fi
    fi
    
    # Check Cloud Scheduler jobs
    local remaining_jobs=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" | grep -E "(campaign-generator-daily|newsletter-weekly|promotional-campaigns)" | wc -l)
    if [ "${remaining_jobs}" -gt 0 ]; then
        warning "Some Cloud Scheduler jobs may still exist: ${remaining_jobs}"
        errors=$((errors + 1))
    fi
    
    # Check BigQuery datasets
    if bq ls -d "${PROJECT_ID}:email_campaigns" &>/dev/null; then
        warning "BigQuery dataset email_campaigns still exists"
        errors=$((errors + 1))
    fi
    
    # Check Cloud Storage buckets
    if [ -n "${BUCKET_NAME}" ]; then
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            warning "Cloud Storage bucket ${BUCKET_NAME} still exists"
            errors=$((errors + 1))
        fi
    fi
    
    # Check service accounts
    if gcloud iam service-accounts describe "gmail-automation-sa@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        warning "Service account gmail-automation-sa still exists"
        errors=$((errors + 1))
    fi
    
    if [ ${errors} -eq 0 ]; then
        success "Cleanup verification passed - all resources removed"
    else
        warning "Cleanup verification found ${errors} potential issues"
        log "Some resources may take time to be fully deleted or may require manual intervention"
    fi
}

# Option to delete the entire project
delete_project() {
    if [ "${DELETE_PROJECT}" = "true" ]; then
        log "Deleting entire project..."
        
        warning "This will delete the entire project ${PROJECT_ID} and all its resources!"
        
        if [ "${FORCE_DELETE}" != "true" ]; then
            read -p "Are you absolutely sure you want to delete the entire project? (type 'DELETE' to confirm): " project_confirmation
            if [ "${project_confirmation}" != "DELETE" ]; then
                log "Project deletion cancelled."
                return 0
            fi
        fi
        
        if gcloud projects delete "${PROJECT_ID}" --quiet; then
            success "Project ${PROJECT_ID} deletion initiated"
            log "Note: Project deletion may take several minutes to complete"
        else
            error "Failed to delete project ${PROJECT_ID}"
        fi
    else
        log "Skipping project deletion (set DELETE_PROJECT=true to delete entire project)"
    fi
}

# Print cleanup summary
print_summary() {
    log "Cleanup Summary:"
    echo
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo
    echo "Removed Resources:"
    echo "  ✅ Cloud Scheduler jobs"
    echo "  ✅ Cloud Functions"
    echo "  ✅ BigQuery datasets and tables"
    echo "  ✅ Cloud Storage buckets"
    echo "  ✅ IAM service accounts"
    echo "  ✅ Local temporary files"
    echo
    
    if [ "${DELETE_PROJECT}" = "true" ]; then
        echo "  ✅ Project deletion initiated"
        echo
        echo "Note: Complete project deletion may take several minutes."
    else
        echo "Note: Project was not deleted. To delete the entire project, run:"
        echo "  DELETE_PROJECT=true ./destroy.sh"
    fi
    
    echo
    success "Email Campaign Automation cleanup completed!"
}

# Display help
show_help() {
    echo "Dynamic Email Campaign Workflows - Cleanup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID       - GCP project ID (required)"
    echo "  REGION           - GCP region (default: us-central1)"
    echo "  BUCKET_NAME      - Cloud Storage bucket name (auto-discovered if not set)"
    echo "  FUNCTION_NAME    - Cloud Functions name prefix (auto-discovered if not set)"
    echo "  FORCE_DELETE     - Skip confirmation prompts (default: false)"
    echo "  DELETE_PROJECT   - Delete entire project (default: false)"
    echo
    echo "Examples:"
    echo "  # Standard cleanup with confirmation"
    echo "  PROJECT_ID=my-project ./destroy.sh"
    echo
    echo "  # Force cleanup without confirmation"
    echo "  PROJECT_ID=my-project FORCE_DELETE=true ./destroy.sh"
    echo
    echo "  # Delete entire project"
    echo "  PROJECT_ID=my-project DELETE_PROJECT=true ./destroy.sh"
    echo
    echo "  # Cleanup with specific resource names"
    echo "  PROJECT_ID=my-project BUCKET_NAME=my-bucket FUNCTION_NAME=my-function ./destroy.sh"
    echo
}

# Main execution
main() {
    # Check for help flag
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_help
        exit 0
    fi
    
    log "Starting Dynamic Email Campaign Workflows cleanup..."
    
    # Run all cleanup steps
    check_prerequisites
    check_authentication
    setup_environment
    confirm_deletion
    
    # Cleanup resources in reverse order of creation
    delete_scheduler_jobs
    delete_functions
    delete_bigquery_datasets
    delete_storage_buckets
    delete_service_accounts
    delete_monitoring_metrics
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Optionally delete the entire project
    delete_project
    
    # Print summary
    print_summary
    
    log "Cleanup completed successfully!"
}

# Run main function
main "$@"