#!/bin/bash

# Legal Document Analysis with Gemini Fine-Tuning and Document AI - Cleanup Script
# Recipe: f3a7b8c2
# Version: 1.1
# Updated: 2025-01-22

set -euo pipefail

# Colors for output
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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to load environment variables
load_environment() {
    if [[ -f .env ]]; then
        log_info "Loading environment variables from .env file..."
        source .env
        log_success "Environment variables loaded"
    else
        log_warning "No .env file found. Using default values or prompting for input."
        
        # Try to get current project from gcloud config
        local current_project
        current_project=$(gcloud config get-value project 2>/dev/null || true)
        
        if [[ -n "$current_project" ]]; then
            export PROJECT_ID="${PROJECT_ID:-$current_project}"
        else
            log_error "No project configured. Please set PROJECT_ID environment variable or run gcloud config set project PROJECT_ID"
            exit 1
        fi
        
        export REGION="${REGION:-us-central1}"
        export ZONE="${ZONE:-us-central1-a}"
    fi
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    log_warning "This will permanently delete the following resources:"
    echo "  - Project: ${PROJECT_ID:-[Not Set]}"
    echo "  - Cloud Functions: ${FUNCTION_NAME:-legal-document-processor}, legal-dashboard-generator"
    echo "  - Document AI Processor: ${DOCAI_PROCESSOR_ID:-[Not Set]}"
    echo "  - Storage Buckets: ${BUCKET_DOCS:-[Not Set]}, ${BUCKET_TRAINING:-[Not Set]}, ${BUCKET_RESULTS:-[Not Set]}"
    echo "  - Fine-tuning Jobs and Models"
    echo "  - Local files and directories"
    echo ""
    
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        log_warning "FORCE_DELETE is set to true. Skipping confirmation."
        return 0
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    # Additional confirmation for project deletion
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        echo ""
        log_warning "You have requested to delete the entire project: ${PROJECT_ID}"
        log_warning "This will delete ALL resources in the project, not just the ones created by this recipe!"
        echo ""
        read -p "Are you absolutely sure you want to delete the entire project? (type 'DELETE PROJECT' to confirm): " project_confirmation
        
        if [[ "$project_confirmation" != "DELETE PROJECT" ]]; then
            log_info "Project deletion cancelled. Will only delete specific resources."
            export DELETE_PROJECT="false"
        fi
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud SDK (gcloud) is not installed or not in PATH"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        log_error "gsutil is not installed or not in PATH"
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 >/dev/null 2>&1; then
        log_error "No active Google Cloud authentication found"
        log_info "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    # Delete document processor function
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log_info "Deleting function: ${FUNCTION_NAME}"
        if gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" >/dev/null 2>&1; then
            if gcloud functions delete "${FUNCTION_NAME}" --gen2 --region="${REGION}" --quiet; then
                log_success "Deleted function: ${FUNCTION_NAME}"
            else
                log_warning "Failed to delete function: ${FUNCTION_NAME}"
            fi
        else
            log_info "Function ${FUNCTION_NAME} not found or already deleted"
        fi
    fi
    
    # Delete dashboard function
    log_info "Deleting function: legal-dashboard-generator"
    if gcloud functions describe legal-dashboard-generator --gen2 --region="${REGION}" >/dev/null 2>&1; then
        if gcloud functions delete legal-dashboard-generator --gen2 --region="${REGION}" --quiet; then
            log_success "Deleted function: legal-dashboard-generator"
        else
            log_warning "Failed to delete function: legal-dashboard-generator"
        fi
    else
        log_info "Function legal-dashboard-generator not found or already deleted"
    fi
    
    log_success "Cloud Functions cleanup completed"
}

# Function to delete Document AI processor
delete_document_ai_processor() {
    log_info "Deleting Document AI processor..."
    
    if [[ -n "${DOCAI_PROCESSOR_ID:-}" ]]; then
        log_info "Deleting Document AI processor: ${DOCAI_PROCESSOR_ID}"
        if gcloud documentai processors delete "${DOCAI_PROCESSOR_ID}" --location="${REGION}" --quiet; then
            log_success "Deleted Document AI processor: ${DOCAI_PROCESSOR_ID}"
        else
            log_warning "Failed to delete Document AI processor: ${DOCAI_PROCESSOR_ID}"
        fi
    else
        log_info "No Document AI processor ID found, checking for processors by name..."
        
        # Try to find processor by display name
        local processor_id
        processor_id=$(gcloud documentai processors list \
            --location="${REGION}" \
            --filter="displayName='Legal Document Processor'" \
            --format="value(name.basename())" \
            --limit=1 2>/dev/null || true)
        
        if [[ -n "$processor_id" ]]; then
            log_info "Found processor by name: $processor_id"
            if gcloud documentai processors delete "$processor_id" --location="${REGION}" --quiet; then
                log_success "Deleted Document AI processor: $processor_id"
            else
                log_warning "Failed to delete Document AI processor: $processor_id"
            fi
        else
            log_info "No Document AI processor found with name 'Legal Document Processor'"
        fi
    fi
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    log_info "Deleting Cloud Storage buckets..."
    
    local buckets=()
    if [[ -n "${BUCKET_DOCS:-}" ]]; then
        buckets+=("gs://${BUCKET_DOCS}")
    fi
    if [[ -n "${BUCKET_TRAINING:-}" ]]; then
        buckets+=("gs://${BUCKET_TRAINING}")
    fi
    if [[ -n "${BUCKET_RESULTS:-}" ]]; then
        buckets+=("gs://${BUCKET_RESULTS}")
    fi
    
    # If no buckets from env, try to find them by pattern
    if [[ ${#buckets[@]} -eq 0 ]]; then
        log_info "No bucket names in environment, searching for buckets with legal- prefix..."
        local found_buckets
        found_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "gs://legal-(docs|training|results)-" || true)
        
        if [[ -n "$found_buckets" ]]; then
            while IFS= read -r bucket; do
                buckets+=("$bucket")
            done <<< "$found_buckets"
        fi
    fi
    
    # Delete buckets
    for bucket in "${buckets[@]}"; do
        if [[ -n "$bucket" ]]; then
            log_info "Deleting bucket: $bucket"
            if gsutil ls "$bucket" >/dev/null 2>&1; then
                if gsutil -m rm -r "$bucket"; then
                    log_success "Deleted bucket: $bucket"
                else
                    log_warning "Failed to delete bucket: $bucket"
                fi
            else
                log_info "Bucket not found or already deleted: $bucket"
            fi
        fi
    done
    
    log_success "Storage buckets cleanup completed"
}

# Function to delete fine-tuning jobs and models
delete_fine_tuning_resources() {
    log_info "Deleting fine-tuning jobs and models..."
    
    # Delete specific tuning job if ID is available
    if [[ -n "${TUNING_JOB_ID:-}" ]]; then
        log_info "Checking tuning job: ${TUNING_JOB_ID}"
        
        # Note: Tuning jobs typically cannot be deleted, only cancelled if running
        local job_status
        job_status=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
            "https://${REGION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/tuningJobs/${TUNING_JOB_ID}" \
            | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('state', 'UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
        
        log_info "Tuning job ${TUNING_JOB_ID} status: $job_status"
        
        if [[ "$job_status" == "JOB_STATE_RUNNING" || "$job_status" == "JOB_STATE_PENDING" ]]; then
            log_warning "Cannot cancel tuning jobs via API. Job will complete or timeout naturally."
        fi
    fi
    
    # List and potentially delete models created by tuning jobs
    log_info "Checking for tuned models..."
    local tuned_models
    tuned_models=$(gcloud ai models list --region="${REGION}" --filter="displayName~'legal-gemini-tuning'" --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$tuned_models" ]]; then
        while IFS= read -r model; do
            if [[ -n "$model" ]]; then
                log_info "Found tuned model: $model"
                if gcloud ai models delete "$model" --region="${REGION}" --quiet 2>/dev/null; then
                    log_success "Deleted tuned model: $model"
                else
                    log_warning "Failed to delete tuned model: $model (may not be deletable)"
                fi
            fi
        done <<< "$tuned_models"
    else
        log_info "No tuned models found with prefix 'legal-gemini-tuning'"
    fi
    
    log_success "Fine-tuning resources cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files and directories..."
    
    local files_to_remove=(
        "legal_processor_function"
        "legal_dashboard_function"
        "legal_training_data"
        "sample_contract.txt"
        "legal_dashboard.html"
        "tuning_request.json"
        ".env"
    )
    
    for item in "${files_to_remove[@]}"; do
        if [[ -e "$item" ]]; then
            log_info "Removing: $item"
            rm -rf "$item"
            log_success "Removed: $item"
        fi
    done
    
    log_success "Local files cleanup completed"
}

# Function to delete the entire project
delete_project() {
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        log_warning "Deleting entire project: ${PROJECT_ID}"
        
        # Final confirmation
        echo ""
        log_warning "FINAL WARNING: This will delete the ENTIRE project and ALL its resources!"
        read -p "Type the project ID '${PROJECT_ID}' to confirm project deletion: " final_confirmation
        
        if [[ "$final_confirmation" == "${PROJECT_ID}" ]]; then
            log_info "Deleting project: ${PROJECT_ID}"
            if gcloud projects delete "${PROJECT_ID}" --quiet; then
                log_success "Project deleted: ${PROJECT_ID}"
                return 0
            else
                log_error "Failed to delete project: ${PROJECT_ID}"
                exit 1
            fi
        else
            log_info "Project deletion cancelled - confirmation did not match"
            return 1
        fi
    fi
    
    return 1
}

# Function to disable APIs (if not deleting project)
disable_apis() {
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        return 0  # Skip if project is being deleted
    fi
    
    log_info "Disabling APIs to reduce costs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "documentai.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
        "run.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Disabling API: $api"
        if gcloud services disable "$api" --force --quiet 2>/dev/null; then
            log_success "Disabled API: $api"
        else
            log_warning "Failed to disable API: $api (may still have dependent resources)"
        fi
    done
    
    log_success "API cleanup completed"
}

# Function to clear gcloud configuration
clear_gcloud_config() {
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        log_info "Clearing gcloud configuration..."
        
        # Unset project configuration
        gcloud config unset project 2>/dev/null || true
        gcloud config unset compute/region 2>/dev/null || true
        gcloud config unset compute/zone 2>/dev/null || true
        
        log_success "gcloud configuration cleared"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "Legal Document Analysis System cleanup completed!"
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        echo "✅ Project deleted: ${PROJECT_ID}"
        echo "✅ All resources in project removed"
    else
        echo "✅ Cloud Functions removed"
        echo "✅ Document AI processor removed"
        echo "✅ Storage buckets removed"
        echo "✅ Fine-tuning resources cleaned up"
        echo "✅ APIs disabled"
    fi
    
    echo "✅ Local files cleaned up"
    echo ""
    echo "=== COST SAVINGS ==="
    echo "- No more storage costs"
    echo "- No more function execution costs"
    echo "- No more API usage costs"
    
    if [[ "${DELETE_PROJECT:-false}" != "true" ]]; then
        echo ""
        echo "=== REMAINING RESOURCES ==="
        echo "- Project: ${PROJECT_ID} (retained)"
        echo "- Some APIs may still be enabled"
        echo ""
        log_info "To completely remove the project, run: gcloud projects delete ${PROJECT_ID}"
    fi
    
    echo ""
    log_success "Cleanup completed successfully!"
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    log_error "An error occurred during cleanup"
    log_warning "Some resources may not have been deleted completely"
    log_info "You may need to manually check and clean up remaining resources in the Google Cloud Console"
    log_info "Project: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    exit 1
}

# Main cleanup function
main() {
    echo "========================================"
    echo "Legal Document Analysis System Cleanup"
    echo "Recipe: f3a7b8c2"
    echo "========================================"
    echo ""
    
    load_environment
    check_prerequisites
    confirm_destruction
    
    # Set error handler
    trap handle_cleanup_error ERR
    
    # Try to delete project first if requested
    if ! delete_project; then
        # If not deleting project, clean up individual resources
        delete_cloud_functions
        delete_document_ai_processor
        delete_storage_buckets
        delete_fine_tuning_resources
        disable_apis
    fi
    
    clear_gcloud_config
    cleanup_local_files
    display_cleanup_summary
}

# Handle script interruption
trap 'log_error "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Help function
show_help() {
    echo "Legal Document Analysis System Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force              Skip confirmation prompts"
    echo "  --delete-project     Delete the entire project (WARNING: Deletes ALL resources)"
    echo "  --help               Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID          Google Cloud project ID"
    echo "  REGION              Google Cloud region (default: us-central1)"
    echo "  FORCE_DELETE        Set to 'true' to skip confirmations"
    echo "  DELETE_PROJECT      Set to 'true' to delete entire project"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup"
    echo "  $0 --force                           # Skip confirmations"
    echo "  $0 --delete-project                  # Delete entire project (with confirmation)"
    echo "  FORCE_DELETE=true $0 --delete-project  # Delete project without confirmation"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DELETE="true"
            shift
            ;;
        --delete-project)
            export DELETE_PROJECT="true"
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