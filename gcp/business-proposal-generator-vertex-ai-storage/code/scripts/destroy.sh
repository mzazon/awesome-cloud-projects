#!/bin/bash

# Business Proposal Generator Cleanup Script
# This script safely removes all resources created by the deployment script
# including Cloud Functions, Cloud Storage buckets, and associated data

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        log_error "gsutil is not available."
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if current project is set
    local project_id
    project_id=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$project_id" ]]; then
        log_error "No GCP project is set. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    log_success "Prerequisites validated"
    log "Current project: $project_id"
}

# Function to load environment variables
load_environment() {
    log "Loading deployment environment..."
    
    # Try to load from environment file created by deploy script
    if [[ -f ".env.deployment" ]]; then
        log "Found deployment environment file"
        # Source the environment file
        set -a
        source .env.deployment
        set +a
        log_success "Loaded environment from .env.deployment"
    else
        log_warning "No deployment environment file found (.env.deployment)"
        log "Attempting to discover resources automatically..."
        
        # Set basic environment
        export PROJECT_ID=$(gcloud config get-value project)
        export REGION="${REGION:-us-central1}"
        
        # Try to discover resources by pattern
        discover_resources
    fi
    
    log "Environment loaded:"
    log "  Project: ${PROJECT_ID:-not set}"
    log "  Region: ${REGION:-not set}"
    log "  Function: ${FUNCTION_NAME:-not set}"
}

# Function to discover existing resources
discover_resources() {
    log "Discovering deployed resources..."
    
    local project_id
    project_id=$(gcloud config get-value project)
    
    # Discover Cloud Functions
    log "Searching for proposal generator functions..."
    local functions
    functions=$(gcloud functions list --filter="name~proposal-generator" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$functions" ]]; then
        # Use the first found function
        export FUNCTION_NAME=$(echo "$functions" | head -1 | sed 's|.*/||')
        log_success "Found function: $FUNCTION_NAME"
    else
        log_warning "No proposal generator functions found"
    fi
    
    # Discover Storage Buckets
    log "Searching for related storage buckets..."
    local buckets
    buckets=$(gsutil ls -p "$project_id" 2>/dev/null | grep -E "(templates|client-data|generated-proposals)" || echo "")
    
    if [[ -n "$buckets" ]]; then
        echo "$buckets" | while read -r bucket; do
            bucket_name=$(echo "$bucket" | sed 's|gs://||' | sed 's|/||')
            if [[ "$bucket_name" == *"templates"* ]]; then
                export TEMPLATES_BUCKET="$bucket_name"
            elif [[ "$bucket_name" == *"client-data"* ]]; then
                export CLIENT_DATA_BUCKET="$bucket_name"
            elif [[ "$bucket_name" == *"generated-proposals"* ]]; then
                export OUTPUT_BUCKET="$bucket_name"
            fi
        done
        log_success "Found related storage buckets"
    else
        log_warning "No related storage buckets found"
    fi
}

# Function to confirm destruction
confirm_destruction() {
    echo
    echo "=============================================="
    echo "⚠️  RESOURCE DESTRUCTION WARNING ⚠️"
    echo "=============================================="
    echo "This script will PERMANENTLY DELETE the following resources:"
    echo
    
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        echo "🔧 Cloud Function:"
        echo "  • $FUNCTION_NAME (in region: ${REGION:-us-central1})"
    fi
    
    if [[ -n "${TEMPLATES_BUCKET:-}" || -n "${CLIENT_DATA_BUCKET:-}" || -n "${OUTPUT_BUCKET:-}" ]]; then
        echo
        echo "📦 Storage Buckets:"
        [[ -n "${TEMPLATES_BUCKET:-}" ]] && echo "  • gs://$TEMPLATES_BUCKET (includes proposal templates)"
        [[ -n "${CLIENT_DATA_BUCKET:-}" ]] && echo "  • gs://$CLIENT_DATA_BUCKET (includes client data)"
        [[ -n "${OUTPUT_BUCKET:-}" ]] && echo "  • gs://$OUTPUT_BUCKET (includes generated proposals)"
    fi
    
    echo
    echo "📄 Local Files:"
    echo "  • .env.deployment (deployment environment file)"
    echo
    echo "💰 This action will:"
    echo "  • Stop all billing for these resources"
    echo "  • Remove all stored data permanently"
    echo "  • Cannot be undone"
    echo
    echo "=============================================="
    
    # Interactive confirmation
    if [[ "${FORCE_DESTROY:-}" != "true" ]]; then
        echo -n "Are you sure you want to continue? (yes/no): "
        read -r confirmation
        
        if [[ "$confirmation" != "yes" && "$confirmation" != "y" ]]; then
            log "Destruction cancelled by user"
            exit 0
        fi
        
        echo -n "Please type 'DELETE' to confirm permanent deletion: "
        read -r final_confirmation
        
        if [[ "$final_confirmation" != "DELETE" ]]; then
            log "Destruction cancelled - confirmation text did not match"
            exit 0
        fi
    fi
    
    log "Destruction confirmed. Proceeding with cleanup..."
}

# Function to delete Cloud Function
delete_cloud_function() {
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        log_warning "No Cloud Function name specified, skipping function deletion"
        return 0
    fi
    
    log "Deleting Cloud Function: $FUNCTION_NAME"
    
    # Check if function exists
    if gcloud functions describe "$FUNCTION_NAME" --region "${REGION:-us-central1}" >/dev/null 2>&1; then
        if gcloud functions delete "$FUNCTION_NAME" \
            --region "${REGION:-us-central1}" \
            --quiet; then
            log_success "Deleted Cloud Function: $FUNCTION_NAME"
        else
            log_error "Failed to delete Cloud Function: $FUNCTION_NAME"
            return 1
        fi
    else
        log_warning "Cloud Function $FUNCTION_NAME not found or already deleted"
    fi
}

# Function to delete storage bucket
delete_storage_bucket() {
    local bucket_name="$1"
    local bucket_description="$2"
    
    if [[ -z "$bucket_name" ]]; then
        log_warning "No $bucket_description bucket name specified, skipping"
        return 0
    fi
    
    log "Deleting $bucket_description bucket: gs://$bucket_name"
    
    # Check if bucket exists
    if gsutil ls "gs://$bucket_name" >/dev/null 2>&1; then
        # Get object count for confirmation
        local object_count
        object_count=$(gsutil ls "gs://$bucket_name/**" 2>/dev/null | wc -l || echo "0")
        
        if [[ $object_count -gt 0 ]]; then
            log "Bucket contains $object_count objects"
        fi
        
        # Delete bucket and all contents
        if gsutil -m rm -r "gs://$bucket_name" 2>/dev/null; then
            log_success "Deleted $bucket_description bucket: gs://$bucket_name"
        else
            log_error "Failed to delete $bucket_description bucket: gs://$bucket_name"
            return 1
        fi
    else
        log_warning "$bucket_description bucket gs://$bucket_name not found or already deleted"
    fi
}

# Function to delete all storage buckets
delete_storage_buckets() {
    log "Deleting storage buckets..."
    
    # Delete buckets in order (output first, then client data, then templates)
    delete_storage_bucket "${OUTPUT_BUCKET:-}" "generated proposals"
    delete_storage_bucket "${CLIENT_DATA_BUCKET:-}" "client data"
    delete_storage_bucket "${TEMPLATES_BUCKET:-}" "templates"
    
    log_success "Storage bucket deletion completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        ".env.deployment"
        "proposal-template.txt"
        "client-data.json"
        "test-client-2.json"
        "generated-proposal.txt"
    )
    
    local removed_count=0
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed local file: $file"
            ((removed_count++))
        fi
    done
    
    # Remove any leftover function directories
    if [[ -d "proposal-function" ]]; then
        rm -rf "proposal-function"
        log "Removed function directory: proposal-function"
        ((removed_count++))
    fi
    
    if [[ $removed_count -gt 0 ]]; then
        log_success "Cleaned up $removed_count local files/directories"
    else
        log "No local files to clean up"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check if function still exists
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "$FUNCTION_NAME" --region "${REGION:-us-central1}" >/dev/null 2>&1; then
            log_warning "Cloud Function $FUNCTION_NAME still exists"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if buckets still exist
    local buckets_to_check=("${TEMPLATES_BUCKET:-}" "${CLIENT_DATA_BUCKET:-}" "${OUTPUT_BUCKET:-}")
    for bucket in "${buckets_to_check[@]}"; do
        if [[ -n "$bucket" ]] && gsutil ls "gs://$bucket" >/dev/null 2>&1; then
            log_warning "Bucket gs://$bucket still exists"
            ((cleanup_issues++))
        fi
    done
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "All resources successfully cleaned up"
    else
        log_warning "Found $cleanup_issues potential cleanup issues"
        log "You may need to manually remove remaining resources"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo
    echo "=============================================="
    echo "🧹 CLEANUP COMPLETED"
    echo "=============================================="
    
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        echo "✅ Cloud Function: $FUNCTION_NAME"
    fi
    
    if [[ -n "${TEMPLATES_BUCKET:-}" || -n "${CLIENT_DATA_BUCKET:-}" || -n "${OUTPUT_BUCKET:-}" ]]; then
        echo "✅ Storage Buckets:"
        [[ -n "${TEMPLATES_BUCKET:-}" ]] && echo "   • gs://$TEMPLATES_BUCKET"
        [[ -n "${CLIENT_DATA_BUCKET:-}" ]] && echo "   • gs://$CLIENT_DATA_BUCKET"
        [[ -n "${OUTPUT_BUCKET:-}" ]] && echo "   • gs://$OUTPUT_BUCKET"
    fi
    
    echo "✅ Local deployment files"
    echo
    echo "💰 Billing for these resources has stopped"
    echo "📊 Check your billing dashboard to confirm"
    echo
    echo "🔍 To verify cleanup manually:"
    echo "   gcloud functions list --filter=\"name~proposal-generator\""
    echo "   gsutil ls | grep -E \"(templates|client-data|proposals)\""
    echo "=============================================="
}

# Function to handle cleanup errors
handle_cleanup_error() {
    local exit_code=$?
    log_error "Cleanup encountered an error (exit code: $exit_code)"
    echo
    echo "⚠️  PARTIAL CLEANUP WARNING ⚠️"
    echo "Some resources may not have been deleted."
    echo "Please check the Google Cloud Console and manually remove:"
    echo "  • Any remaining Cloud Functions with 'proposal-generator' in the name"
    echo "  • Any remaining storage buckets with 'templates', 'client-data', or 'proposals' in the name"
    echo
    exit $exit_code
}

# Main cleanup function
main() {
    log "🧹 Starting Business Proposal Generator cleanup..."
    
    # Validate prerequisites
    validate_prerequisites
    
    # Load environment
    load_environment
    
    # Confirm destruction
    confirm_destruction
    
    # Delete Cloud Function
    delete_cloud_function
    
    # Delete storage buckets
    delete_storage_buckets
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_cleanup_summary
    
    log_success "🎉 Business Proposal Generator cleanup completed successfully!"
}

# Error handling
trap 'handle_cleanup_error' ERR

# Support force mode for non-interactive use
if [[ "${1:-}" == "--force" || "${1:-}" == "-f" ]]; then
    export FORCE_DESTROY="true"
    log "Running in force mode (non-interactive)"
fi

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi