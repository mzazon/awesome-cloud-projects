#!/bin/bash

# destroy.sh - Cleanup script for Intelligent Document Classification with Cloud Functions and Vertex AI
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
    fi
    
    success "Prerequisites check passed"
}

# Function to load deployment configuration
load_config() {
    log "Loading deployment configuration..."
    
    if [[ -f ".deploy_config" ]]; then
        # Source the configuration file
        source .deploy_config
        log "Configuration loaded from .deploy_config"
        log "Project ID: ${PROJECT_ID}"
        log "Region: ${REGION}"
        log "Inbox Bucket: ${INBOX_BUCKET}"
        log "Classified Bucket: ${CLASSIFIED_BUCKET}"
    else
        warning "No .deploy_config file found. Using environment variables or prompting for input."
        
        # Try to get from environment or prompt
        if [[ -z "${PROJECT_ID:-}" ]]; then
            read -p "Enter Project ID to clean up: " PROJECT_ID
            if [[ -z "${PROJECT_ID}" ]]; then
                error "Project ID is required for cleanup"
            fi
        fi
        
        if [[ -z "${REGION:-}" ]]; then
            export REGION="us-central1"
            warning "REGION not set, using default: ${REGION}"
        fi
        
        if [[ -z "${INBOX_BUCKET:-}" ]]; then
            warning "INBOX_BUCKET not set. Will attempt to find buckets with doc-inbox prefix."
        fi
        
        if [[ -z "${CLASSIFIED_BUCKET:-}" ]]; then
            warning "CLASSIFIED_BUCKET not set. Will attempt to find buckets with doc-classified prefix."
        fi
    fi
    
    # Set project context
    gcloud config set project "${PROJECT_ID}" 2>/dev/null || warning "Could not set project context"
    
    success "Configuration loaded"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "   • Project: ${PROJECT_ID}"
    echo "   • All Cloud Storage buckets and their contents"
    echo "   • Cloud Function: classify-documents"
    echo "   • Service Account: doc-classifier-sa"
    echo "   • All associated logs and monitoring data"
    echo ""
    echo "💾 This action cannot be undone!"
    echo ""
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        warning "Force delete mode enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Deletion confirmed"
}

# Function to delete Cloud Function
delete_cloud_function() {
    log "Deleting Cloud Function..."
    
    # Check if function exists before attempting deletion
    if gcloud functions describe classify-documents --gen2 --region="${REGION}" &>/dev/null; then
        log "Deleting Cloud Function: classify-documents"
        gcloud functions delete classify-documents \
            --gen2 \
            --region="${REGION}" \
            --quiet || warning "Failed to delete Cloud Function (may not exist)"
        success "Cloud Function deleted"
    else
        warning "Cloud Function classify-documents not found, skipping deletion"
    fi
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    log "Deleting Cloud Storage buckets..."
    
    # Function to safely delete a bucket
    delete_bucket_safely() {
        local bucket_name="$1"
        if gsutil ls "gs://${bucket_name}" &>/dev/null; then
            log "Deleting bucket and all contents: gs://${bucket_name}"
            gsutil -m rm -r "gs://${bucket_name}" || warning "Failed to delete bucket: ${bucket_name}"
            success "Bucket deleted: gs://${bucket_name}"
        else
            warning "Bucket not found: gs://${bucket_name}"
        fi
    }
    
    # Delete specific buckets if known
    if [[ -n "${INBOX_BUCKET:-}" ]]; then
        delete_bucket_safely "${INBOX_BUCKET}"
    fi
    
    if [[ -n "${CLASSIFIED_BUCKET:-}" ]]; then
        delete_bucket_safely "${CLASSIFIED_BUCKET}"
    fi
    
    # If bucket names unknown, try to find and delete doc-related buckets
    if [[ -z "${INBOX_BUCKET:-}" ]] || [[ -z "${CLASSIFIED_BUCKET:-}" ]]; then
        log "Searching for document classifier buckets in project..."
        local doc_buckets
        doc_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "(doc-inbox|doc-classified)" | sed 's|gs://||g' | sed 's|/||g' || true)
        
        if [[ -n "${doc_buckets}" ]]; then
            while IFS= read -r bucket; do
                if [[ -n "${bucket}" ]]; then
                    delete_bucket_safely "${bucket}"
                fi
            done <<< "${doc_buckets}"
        else
            log "No document classifier buckets found"
        fi
    fi
}

# Function to delete service account
delete_service_account() {
    log "Deleting service account..."
    
    local service_account_email="doc-classifier-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "${service_account_email}" &>/dev/null; then
        log "Deleting service account: ${service_account_email}"
        
        # Remove IAM policy bindings first
        log "Removing IAM policy bindings..."
        gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account_email}" \
            --role="roles/aiplatform.user" &>/dev/null || warning "Failed to remove aiplatform.user binding"
        
        gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account_email}" \
            --role="roles/storage.objectAdmin" &>/dev/null || warning "Failed to remove storage.objectAdmin binding"
        
        gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account_email}" \
            --role="roles/logging.logWriter" &>/dev/null || warning "Failed to remove logging.logWriter binding"
        
        # Delete service account
        gcloud iam service-accounts delete "${service_account_email}" \
            --quiet || warning "Failed to delete service account"
        
        success "Service account deleted"
    else
        warning "Service account not found: ${service_account_email}"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove function code directory
    if [[ -d "doc-classifier-function" ]]; then
        rm -rf doc-classifier-function
        success "Removed doc-classifier-function directory"
    fi
    
    # Remove sample documents
    local sample_files=("sample_contract.txt" "sample_invoice.txt" "sample_report.txt" "invalid_doc.txt")
    for file in "${sample_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log "Removed ${file}"
        fi
    done
    
    # Remove deployment configuration
    if [[ -f ".deploy_config" ]]; then
        rm -f ".deploy_config"
        success "Removed deployment configuration file"
    fi
    
    success "Local files cleaned up"
}

# Function to disable APIs (optional)
disable_apis() {
    if [[ "${DISABLE_APIS:-}" == "true" ]]; then
        log "Disabling APIs..."
        
        local apis=(
            "cloudfunctions.googleapis.com"
            "aiplatform.googleapis.com"
            "logging.googleapis.com"
            "monitoring.googleapis.com"
            "cloudbuild.googleapis.com"
            "eventarc.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log "Disabling ${api}..."
            gcloud services disable "${api}" --quiet &>/dev/null || warning "Failed to disable ${api}"
        done
        
        success "APIs disabled"
    else
        log "Skipping API disabling (set DISABLE_APIS=true to disable)"
    fi
}

# Function to delete project (optional)
delete_project() {
    if [[ "${DELETE_PROJECT:-}" == "true" ]]; then
        warning "Deleting entire project: ${PROJECT_ID}"
        echo ""
        echo "⚠️  PROJECT DELETION WARNING ⚠️"
        echo "This will permanently delete the entire project and ALL resources within it!"
        echo "This includes resources not created by this script."
        echo ""
        
        if [[ "${FORCE_DELETE:-}" != "true" ]]; then
            read -p "Type the project ID '${PROJECT_ID}' to confirm project deletion: " confirm_project
            if [[ "${confirm_project}" != "${PROJECT_ID}" ]]; then
                log "Project deletion cancelled"
                return
            fi
        fi
        
        gcloud projects delete "${PROJECT_ID}" --quiet || error "Failed to delete project"
        success "Project deleted: ${PROJECT_ID}"
    else
        log "Skipping project deletion (set DELETE_PROJECT=true to delete entire project)"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_success=true
    
    # Check if Cloud Function still exists
    if gcloud functions describe classify-documents --gen2 --region="${REGION}" &>/dev/null; then
        warning "Cloud Function still exists"
        cleanup_success=false
    fi
    
    # Check if buckets still exist
    if [[ -n "${INBOX_BUCKET:-}" ]] && gsutil ls "gs://${INBOX_BUCKET}" &>/dev/null; then
        warning "Inbox bucket still exists: gs://${INBOX_BUCKET}"
        cleanup_success=false
    fi
    
    if [[ -n "${CLASSIFIED_BUCKET:-}" ]] && gsutil ls "gs://${CLASSIFIED_BUCKET}" &>/dev/null; then
        warning "Classified bucket still exists: gs://${CLASSIFIED_BUCKET}"
        cleanup_success=false
    fi
    
    # Check if service account still exists
    local service_account_email="doc-classifier-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "${service_account_email}" &>/dev/null; then
        warning "Service account still exists: ${service_account_email}"
        cleanup_success=false
    fi
    
    if [[ "${cleanup_success}" == "true" ]]; then
        success "Cleanup verification passed"
    else
        warning "Some resources may still exist. You may need to clean them up manually."
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary:"
    echo ""
    echo "🧹 Intelligent Document Classification System Cleanup Completed"
    echo ""
    echo "📋 Resources Removed:"
    echo "   • Cloud Function: classify-documents"
    echo "   • Storage Buckets: ${INBOX_BUCKET:-unknown}, ${CLASSIFIED_BUCKET:-unknown}"
    echo "   • Service Account: doc-classifier-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "   • Local files and configuration"
    echo ""
    echo "💰 Cost Impact:"
    echo "   • No ongoing charges from these resources"
    echo "   • Vertex AI usage billed separately (if any)"
    echo ""
    
    if [[ "${DELETE_PROJECT:-}" == "true" ]]; then
        echo "🗑️  Project ${PROJECT_ID} was completely deleted"
    else
        echo "📦 Project ${PROJECT_ID} remains active"
        echo "   • To delete the entire project: DELETE_PROJECT=true ./destroy.sh"
    fi
    
    echo ""
    success "Cleanup process completed!"
}

# Main cleanup function
main() {
    log "Starting cleanup of Intelligent Document Classification system..."
    
    check_prerequisites
    load_config
    confirm_deletion
    delete_cloud_function
    delete_storage_buckets
    delete_service_account
    cleanup_local_files
    disable_apis
    delete_project
    verify_cleanup
    display_summary
    
    log "Cleanup process completed!"
}

# Handle script interruption
cleanup_on_exit() {
    warning "Script interrupted. Some resources may not have been cleaned up."
    exit 1
}

trap cleanup_on_exit INT TERM

# Show usage if help requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Clean up Intelligent Document Classification infrastructure"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID       Google Cloud Project ID (required if no .deploy_config)"
    echo "  REGION          GCP Region (default: us-central1)"
    echo "  INBOX_BUCKET    Inbox bucket name (auto-detected if not set)"
    echo "  CLASSIFIED_BUCKET Classified bucket name (auto-detected if not set)"
    echo "  FORCE_DELETE    Skip confirmation prompts (default: false)"
    echo "  DELETE_PROJECT  Delete entire project (default: false)"
    echo "  DISABLE_APIS    Disable APIs after cleanup (default: false)"
    echo ""
    echo "Options:"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./destroy.sh                                    # Interactive cleanup"
    echo "  FORCE_DELETE=true ./destroy.sh                 # Skip confirmations"
    echo "  DELETE_PROJECT=true ./destroy.sh               # Delete entire project"
    echo "  PROJECT_ID=my-project ./destroy.sh             # Cleanup specific project"
    echo "  DISABLE_APIS=true DELETE_PROJECT=true ./destroy.sh  # Complete cleanup"
    echo ""
    echo "Safety Features:"
    echo "  • Requires explicit confirmation for destructive operations"
    echo "  • Loads configuration from .deploy_config if available"
    echo "  • Verifies cleanup completion"
    echo "  • Provides detailed logging of all operations"
    exit 0
fi

# Run main cleanup
main