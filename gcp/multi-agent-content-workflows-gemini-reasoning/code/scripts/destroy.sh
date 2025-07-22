#!/bin/bash

# Multi-Agent Content Workflows with Gemini 2.5 Reasoning - Cleanup Script
# This script safely removes all infrastructure created for the content intelligence system
# including Cloud Workflows, Cloud Functions, Storage buckets, and service accounts

set -euo pipefail

# Color codes for output formatting
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

# Error handling function
handle_error() {
    log_error "Cleanup failed at line $1. Exit code: $2"
    log_warning "Some resources may not have been deleted. Please check manually."
    exit 1
}

# Set error trap
trap 'handle_error ${LINENO} $?' ERR

# Configuration variables - must match deployment script
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
RANDOM_SUFFIX="${RANDOM_SUFFIX:-}"
BUCKET_NAME="${BUCKET_NAME:-}"
WORKFLOW_NAME="${WORKFLOW_NAME:-content-analysis-workflow}"
FUNCTION_NAME="${FUNCTION_NAME:-}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-content-intelligence-sa}"
FORCE_DELETE="${FORCE_DELETE:-false}"
DRY_RUN="${DRY_RUN:-false}"
DELETE_PROJECT="${DELETE_PROJECT:-false}"

# Function to detect configuration from existing resources
detect_configuration() {
    log_info "Detecting existing configuration..."
    
    # Get current project if not set
    if [[ -z "${PROJECT_ID}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "No project ID specified and no default project set"
            log_error "Please set PROJECT_ID environment variable or run 'gcloud config set project YOUR_PROJECT_ID'"
            exit 1
        fi
    fi
    
    # Auto-detect bucket name if not provided
    if [[ -z "${BUCKET_NAME}" ]]; then
        log_info "Auto-detecting bucket name..."
        BUCKET_NAME=$(gsutil ls -p "${PROJECT_ID}" | grep "content-intelligence-" | head -1 | sed 's|gs://||g' | sed 's|/||g' || echo "")
        if [[ -n "${BUCKET_NAME}" ]]; then
            log_info "Found bucket: ${BUCKET_NAME}"
        else
            log_warning "No content intelligence bucket found"
        fi
    fi
    
    # Auto-detect function name if not provided
    if [[ -z "${FUNCTION_NAME}" ]]; then
        log_info "Auto-detecting function name..."
        FUNCTION_NAME=$(gcloud functions list --filter="name:content-trigger" --format="value(name)" 2>/dev/null | head -1 || echo "")
        if [[ -n "${FUNCTION_NAME}" ]]; then
            # Extract just the function name from the full path
            FUNCTION_NAME=$(basename "${FUNCTION_NAME}")
            log_info "Found function: ${FUNCTION_NAME}"
        else
            log_warning "No content trigger function found"
        fi
    fi
    
    log_success "Configuration detection completed"
}

# Function to display configuration
display_configuration() {
    log_info "Cleanup Configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Bucket Name: ${BUCKET_NAME:-not found}"
    echo "  Workflow Name: ${WORKFLOW_NAME}"
    echo "  Function Name: ${FUNCTION_NAME:-not found}"
    echo "  Service Account: ${SERVICE_ACCOUNT_NAME}"
    echo "  Force Delete: ${FORCE_DELETE}"
    echo "  Dry Run: ${DRY_RUN}"
    echo "  Delete Project: ${DELETE_PROJECT}"
    echo ""
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        return 0
    fi
    
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log_warning "FORCE DELETE mode enabled - skipping confirmation"
        return 0
    fi
    
    log_warning "This will permanently delete all content intelligence infrastructure!"
    echo "Resources to be deleted:"
    echo "  - Cloud Functions: ${FUNCTION_NAME:-none}"
    echo "  - Cloud Workflows: ${WORKFLOW_NAME}"
    echo "  - Storage Bucket: ${BUCKET_NAME:-none} (and ALL contents)"
    echo "  - Service Account: ${SERVICE_ACCOUNT_NAME}"
    echo "  - IAM Role Bindings"
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo "  - ENTIRE PROJECT: ${PROJECT_ID}"
    fi
    
    echo ""
    read -p "Are you absolutely sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "Starting destructive cleanup in 5 seconds... (Ctrl+C to abort)"
    sleep 5
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "You are not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available"
        exit 1
    fi
    
    # Set the project context
    gcloud config set project "${PROJECT_ID}"
    
    log_success "Prerequisites check completed"
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cloud Function: ${FUNCTION_NAME:-none}"
        return 0
    fi
    
    if [[ -z "${FUNCTION_NAME}" ]]; then
        log_info "No Cloud Function to delete"
        return 0
    fi
    
    # Check if function exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --gen2 &>/dev/null; then
        log_info "Deleting Cloud Function: ${FUNCTION_NAME}"
        if gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --gen2 \
            --quiet; then
            log_success "Deleted Cloud Function: ${FUNCTION_NAME}"
        else
            log_warning "Failed to delete Cloud Function: ${FUNCTION_NAME}"
        fi
    else
        log_info "Cloud Function ${FUNCTION_NAME} not found or already deleted"
    fi
}

# Function to delete Cloud Workflows
delete_workflows() {
    log_info "Deleting Cloud Workflows..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete workflow: ${WORKFLOW_NAME}"
        return 0
    fi
    
    # Check if workflow exists
    if gcloud workflows describe "${WORKFLOW_NAME}" --location="${REGION}" &>/dev/null; then
        log_info "Deleting workflow: ${WORKFLOW_NAME}"
        if gcloud workflows delete "${WORKFLOW_NAME}" \
            --location="${REGION}" \
            --quiet; then
            log_success "Deleted workflow: ${WORKFLOW_NAME}"
        else
            log_warning "Failed to delete workflow: ${WORKFLOW_NAME}"
        fi
    else
        log_info "Workflow ${WORKFLOW_NAME} not found or already deleted"
    fi
}

# Function to delete Storage bucket and contents
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket and contents..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete bucket: gs://${BUCKET_NAME:-none}"
        return 0
    fi
    
    if [[ -z "${BUCKET_NAME}" ]]; then
        log_info "No storage bucket to delete"
        return 0
    fi
    
    # Check if bucket exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warning "Deleting ALL contents in bucket: gs://${BUCKET_NAME}"
        
        # List some contents for confirmation (limited output)
        log_info "Bucket contents preview:"
        gsutil ls "gs://${BUCKET_NAME}/**" | head -10 || echo "  (empty or inaccessible)"
        
        # Delete bucket and all contents
        if gsutil -m rm -r "gs://${BUCKET_NAME}"; then
            log_success "Deleted bucket and all contents: gs://${BUCKET_NAME}"
        else
            log_warning "Failed to delete bucket: gs://${BUCKET_NAME}"
        fi
    else
        log_info "Bucket gs://${BUCKET_NAME} not found or already deleted"
    fi
}

# Function to delete service account and IAM bindings
delete_service_account() {
    log_info "Deleting service account and IAM bindings..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete service account: ${SERVICE_ACCOUNT_NAME}"
        return 0
    fi
    
    local service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "${service_account_email}" &>/dev/null; then
        
        # Remove IAM policy bindings first
        log_info "Removing IAM policy bindings..."
        local roles=(
            "roles/aiplatform.user"
            "roles/workflows.invoker"
            "roles/storage.objectAdmin"
            "roles/speech.editor"
            "roles/vision.editor"
            "roles/cloudfunctions.invoker"
            "roles/eventarc.eventReceiver"
        )
        
        for role in "${roles[@]}"; do
            log_info "Removing role binding: ${role}"
            gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${service_account_email}" \
                --role="${role}" \
                --quiet 2>/dev/null || log_warning "Failed to remove role ${role}"
        done
        
        # Delete the service account
        log_info "Deleting service account: ${service_account_email}"
        if gcloud iam service-accounts delete "${service_account_email}" --quiet; then
            log_success "Deleted service account: ${service_account_email}"
        else
            log_warning "Failed to delete service account: ${service_account_email}"
        fi
    else
        log_info "Service account ${service_account_email} not found or already deleted"
    fi
}

# Function to disable APIs (optional)
disable_apis() {
    log_info "Optionally disabling APIs to prevent charges..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would disable expensive APIs"
        return 0
    fi
    
    # Only disable expensive APIs that could incur charges
    local expensive_apis=(
        "aiplatform.googleapis.com"
        "speech.googleapis.com"
        "vision.googleapis.com"
    )
    
    echo "Do you want to disable expensive APIs to prevent accidental charges? (y/N): "
    read -r disable_apis_choice
    
    if [[ $disable_apis_choice =~ ^[Yy]$ ]]; then
        for api in "${expensive_apis[@]}"; do
            log_info "Disabling API: ${api}"
            if gcloud services disable "${api}" --force --quiet; then
                log_success "Disabled ${api}"
            else
                log_warning "Failed to disable ${api}"
            fi
        done
    else
        log_info "Keeping APIs enabled"
    fi
}

# Function to delete entire project
delete_project() {
    if [[ "${DELETE_PROJECT}" != "true" ]]; then
        return 0
    fi
    
    log_warning "Deleting entire project: ${PROJECT_ID}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete project: ${PROJECT_ID}"
        return 0
    fi
    
    echo ""
    log_warning "⚠️  FINAL WARNING: You are about to delete the ENTIRE PROJECT!"
    log_warning "⚠️  This action is IRREVERSIBLE and will delete ALL resources in the project!"
    echo ""
    read -p "Type the project ID to confirm deletion: " -r confirm_project
    
    if [[ "${confirm_project}" != "${PROJECT_ID}" ]]; then
        log_error "Project ID confirmation failed. Aborting project deletion."
        return 1
    fi
    
    log_warning "Deleting project in 10 seconds... (Ctrl+C to abort)"
    sleep 10
    
    if gcloud projects delete "${PROJECT_ID}" --quiet; then
        log_success "Project ${PROJECT_ID} deletion initiated"
        log_info "Project deletion may take several minutes to complete"
    else
        log_error "Failed to delete project ${PROJECT_ID}"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local temporary files..."
    
    # Remove any temporary files that might have been created
    local temp_files=(
        "/tmp/content-analysis-workflow.yaml"
        "/tmp/gemini-config.json"
        "/tmp/test-document.txt"
        "/tmp/cloud-function-trigger"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -e "${file}" ]]; then
            rm -rf "${file}"
            log_info "Removed: ${file}"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Function to verify deletion
verify_deletion() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would verify resource deletion"
        return 0
    fi
    
    log_info "Verifying resource deletion..."
    
    local resources_remaining=false
    
    # Check Cloud Function
    if [[ -n "${FUNCTION_NAME}" ]] && gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --gen2 &>/dev/null; then
        log_warning "Cloud Function still exists: ${FUNCTION_NAME}"
        resources_remaining=true
    fi
    
    # Check Workflow
    if gcloud workflows describe "${WORKFLOW_NAME}" --location="${REGION}" &>/dev/null; then
        log_warning "Workflow still exists: ${WORKFLOW_NAME}"
        resources_remaining=true
    fi
    
    # Check Storage bucket
    if [[ -n "${BUCKET_NAME}" ]] && gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warning "Storage bucket still exists: gs://${BUCKET_NAME}"
        resources_remaining=true
    fi
    
    # Check Service Account
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        log_warning "Service account still exists: ${SERVICE_ACCOUNT_NAME}"
        resources_remaining=true
    fi
    
    if [[ "${resources_remaining}" == "true" ]]; then
        log_warning "Some resources may still exist. Check Google Cloud Console for manual cleanup."
    else
        log_success "All resources appear to have been deleted successfully"
    fi
}

# Function to display cleanup summary
display_summary() {
    log_success "Cleanup process completed!"
    echo ""
    echo "=== Cleanup Summary ==="
    echo "Project ID: ${PROJECT_ID}"
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo "Action: Entire project deletion initiated"
        echo "Note: Project deletion may take several minutes to complete"
    else
        echo "Resources cleaned up:"
        echo "  ✓ Cloud Function: ${FUNCTION_NAME:-none}"
        echo "  ✓ Cloud Workflow: ${WORKFLOW_NAME}"
        echo "  ✓ Storage Bucket: ${BUCKET_NAME:-none}"
        echo "  ✓ Service Account: ${SERVICE_ACCOUNT_NAME}"
        echo "  ✓ IAM Role Bindings"
    fi
    
    echo ""
    echo "=== Next Steps ==="
    echo "1. Verify deletion in Google Cloud Console"
    echo "2. Check for any remaining charges in billing"
    echo "3. Review audit logs if needed"
    
    if [[ "${DELETE_PROJECT}" != "true" ]]; then
        echo "4. Consider disabling unused APIs to prevent accidental charges"
        echo "5. Project ${PROJECT_ID} remains active with other resources"
    fi
    
    echo ""
}

# Main cleanup function
main() {
    log_info "Starting Multi-Agent Content Workflows cleanup..."
    
    detect_configuration
    check_prerequisites
    display_configuration
    confirm_destruction
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        delete_project
    else
        delete_cloud_functions
        delete_workflows
        delete_storage_bucket
        delete_service_account
        disable_apis
        verify_deletion
    fi
    
    cleanup_local_files
    display_summary
}

# Script usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --project-id PROJECT_ID     Specify the Google Cloud project ID"
    echo "  --bucket-name BUCKET_NAME   Specify the storage bucket name"
    echo "  --function-name FUNC_NAME   Specify the Cloud Function name"
    echo "  --force                     Skip confirmation prompts"
    echo "  --dry-run                   Show what would be deleted without doing it"
    echo "  --delete-project            Delete the entire project (DANGEROUS)"
    echo "  --help                      Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID                  Google Cloud project ID"
    echo "  BUCKET_NAME                 Storage bucket name"
    echo "  FUNCTION_NAME               Cloud Function name"
    echo "  FORCE_DELETE                Set to 'true' to skip confirmations"
    echo "  DRY_RUN                     Set to 'true' for dry run mode"
    echo "  DELETE_PROJECT              Set to 'true' to delete entire project"
    echo ""
    echo "Examples:"
    echo "  $0                          # Interactive cleanup with auto-detection"
    echo "  $0 --dry-run                # Preview what would be deleted"
    echo "  $0 --force                  # Skip confirmations"
    echo "  $0 --delete-project         # Delete entire project"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        --function-name)
            FUNCTION_NAME="$2"
            shift 2
            ;;
        --force)
            FORCE_DELETE="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --delete-project)
            DELETE_PROJECT="true"
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi