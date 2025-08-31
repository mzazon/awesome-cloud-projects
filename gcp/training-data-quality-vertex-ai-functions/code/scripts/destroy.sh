#!/bin/bash

# Training Data Quality Assessment with Vertex AI and Functions - Cleanup Script
# This script safely removes all resources created by the deployment script

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

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
}

# Function to load deployment info
load_deployment_info() {
    if [[ -f .deployment_info ]]; then
        log_info "Loading deployment information from .deployment_info file..."
        source .deployment_info
        log_success "Deployment info loaded"
    else
        log_warning "No .deployment_info file found. You'll need to provide resource details manually."
        
        # Get project info from gcloud if available
        if command_exists gcloud; then
            DEFAULT_PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
            DEFAULT_REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
        else
            DEFAULT_PROJECT_ID=""
            DEFAULT_REGION="us-central1"
        fi
        
        # Prompt for required information
        read -p "Enter your GCP Project ID [${DEFAULT_PROJECT_ID}]: " PROJECT_ID
        PROJECT_ID=${PROJECT_ID:-$DEFAULT_PROJECT_ID}
        
        read -p "Enter the region [${DEFAULT_REGION}]: " REGION
        REGION=${REGION:-$DEFAULT_REGION}
        
        read -p "Enter the Cloud Storage bucket name (training-data-quality-*): " BUCKET_NAME
        
        if [[ -z "$PROJECT_ID" || -z "$BUCKET_NAME" ]]; then
            log_error "Project ID and bucket name are required for cleanup."
            exit 1
        fi
        
        export PROJECT_ID REGION BUCKET_NAME
    fi
}

# Function to confirm destructive actions
confirm_destruction() {
    echo
    log_warning "=== RESOURCE DELETION CONFIRMATION ==="
    log_warning "This script will delete the following resources:"
    log_warning "  • Cloud Function: data-quality-analyzer"
    log_warning "  • Service Account: data-quality-function-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    log_warning "  • Storage Bucket: gs://${BUCKET_NAME} (and ALL contents)"
    log_warning "  • IAM Policy Bindings"
    echo
    log_error "⚠️  THIS ACTION CANNOT BE UNDONE ⚠️"
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "Proceeding with resource deletion..."
}

# Function to delete Cloud Function
delete_cloud_function() {
    log_info "Checking for Cloud Function: data-quality-analyzer..."
    
    if gcloud functions describe data-quality-analyzer --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_info "Deleting Cloud Function: data-quality-analyzer..."
        
        if gcloud functions delete data-quality-analyzer \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --quiet; then
            log_success "Cloud Function deleted successfully"
        else
            log_error "Failed to delete Cloud Function"
            return 1
        fi
    else
        log_warning "Cloud Function 'data-quality-analyzer' not found or already deleted"
    fi
}

# Function to remove IAM policy bindings
remove_iam_policies() {
    local service_account="data-quality-function-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    log_info "Removing IAM policy bindings..."
    
    # Remove Vertex AI permissions
    if gcloud projects get-iam-policy "$PROJECT_ID" --format="value(bindings.members)" | grep -q "$service_account"; then
        log_info "Removing aiplatform.user role..."
        gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:${service_account}" \
            --role="roles/aiplatform.user" \
            --quiet || log_warning "Failed to remove aiplatform.user role (may not exist)"
        
        log_info "Removing storage.objectAdmin role..."
        gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:${service_account}" \
            --role="roles/storage.objectAdmin" \
            --quiet || log_warning "Failed to remove storage.objectAdmin role (may not exist)"
        
        log_success "IAM policy bindings removed"
    else
        log_warning "No IAM policy bindings found for service account"
    fi
}

# Function to delete service account
delete_service_account() {
    local service_account="data-quality-function-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    log_info "Checking for service account: $service_account..."
    
    if gcloud iam service-accounts describe "$service_account" --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_info "Deleting service account: $service_account..."
        
        if gcloud iam service-accounts delete "$service_account" \
            --project="$PROJECT_ID" \
            --quiet; then
            log_success "Service account deleted successfully"
        else
            log_error "Failed to delete service account"
            return 1
        fi
    else
        log_warning "Service account not found or already deleted"
    fi
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log_info "Checking for Cloud Storage bucket: gs://${BUCKET_NAME}..."
    
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_info "Listing bucket contents..."
        gsutil ls -r "gs://${BUCKET_NAME}" || log_warning "Could not list bucket contents"
        
        log_info "Deleting Cloud Storage bucket and all contents: gs://${BUCKET_NAME}..."
        
        # Use parallel deletion for faster cleanup
        if gsutil -m rm -r "gs://${BUCKET_NAME}"; then
            log_success "Storage bucket deleted successfully"
        else
            log_error "Failed to delete storage bucket"
            return 1
        fi
    else
        log_warning "Storage bucket not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        ".deployment_info"
        "sample_training_data.json"
        "analysis_request.json"
        "latest_quality_report.json"
    )
    
    local directories_to_remove=(
        "data-quality-function"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed local file: $file"
        fi
    done
    
    for dir in "${directories_to_remove[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            log_info "Removed local directory: $dir"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_success=true
    
    # Check Cloud Function
    if gcloud functions describe data-quality-analyzer --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_error "Cloud Function still exists"
        cleanup_success=false
    else
        log_success "Cloud Function successfully removed"
    fi
    
    # Check service account
    if gcloud iam service-accounts describe "data-quality-function-sa@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_error "Service account still exists"
        cleanup_success=false
    else
        log_success "Service account successfully removed"
    fi
    
    # Check storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_error "Storage bucket still exists"
        cleanup_success=false
    else
        log_success "Storage bucket successfully removed"
    fi
    
    if [[ "$cleanup_success" == "true" ]]; then
        log_success "All resources have been successfully cleaned up!"
    else
        log_warning "Some resources may still exist. Please check manually."
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo
    log_success "=== CLEANUP COMPLETED ==="
    log_info "The following resources have been removed:"
    log_info "  ✅ Cloud Function: data-quality-analyzer"
    log_info "  ✅ Service Account: data-quality-function-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    log_info "  ✅ Storage Bucket: gs://${BUCKET_NAME}"
    log_info "  ✅ IAM Policy Bindings"
    log_info "  ✅ Local files and directories"
    echo
    log_info "=== COST IMPACT ==="
    log_info "• Cloud Function executions and storage: Stopped"
    log_info "• Cloud Storage costs: Eliminated"
    log_info "• Vertex AI API usage: No longer incurred"
    echo
    log_info "=== NEXT STEPS ==="
    log_info "• The enabled APIs remain active but unused"
    log_info "• No ongoing costs should be incurred"
    log_info "• You can re-deploy using ./deploy.sh if needed"
    echo
    log_success "Cleanup process completed successfully!"
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Training Data Quality Assessment system..."
    
    # Prerequisites check
    log_info "Checking prerequisites..."
    
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command_exists gsutil; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    check_gcloud_auth
    
    # Load deployment configuration
    load_deployment_info
    
    # Set gcloud project context
    gcloud config set project "$PROJECT_ID"
    if [[ -n "${REGION:-}" ]]; then
        gcloud config set compute/region "$REGION"
    fi
    
    # Confirm destructive actions
    confirm_destruction
    
    # Perform cleanup in safe order
    log_info "Beginning resource cleanup..."
    
    # 1. Delete Cloud Function first (stops ongoing executions)
    delete_cloud_function || log_warning "Cloud Function deletion failed, continuing..."
    
    # 2. Remove IAM policy bindings
    remove_iam_policies || log_warning "IAM policy removal failed, continuing..."
    
    # 3. Delete service account
    delete_service_account || log_warning "Service account deletion failed, continuing..."
    
    # 4. Delete storage bucket (last to preserve any final logs)
    delete_storage_bucket || log_warning "Storage bucket deletion failed, continuing..."
    
    # 5. Clean up local files
    cleanup_local_files
    
    # 6. Verify cleanup
    verify_cleanup || log_warning "Some cleanup verification failed"
    
    # 7. Display summary
    display_cleanup_summary
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warning "Cleanup interrupted by user. Some resources may still exist."
    log_info "Run this script again to complete the cleanup process."
    exit 130
}

# Trap to handle Ctrl+C gracefully
trap cleanup_on_interrupt SIGINT

# Run main function
main "$@"