#!/bin/bash
# =============================================================================
# Smart Document Summarization with Vertex AI and Cloud Functions - Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script
# including Cloud Storage buckets, Cloud Functions, and IAM configurations.
#
# Usage: ./destroy.sh [OPTIONS]
# Options:
#   --project-id PROJECT_ID    Use specific project ID (required)
#   --bucket-name BUCKET_NAME  Use specific bucket name (required)
#   --function-name NAME       Use specific function name (default: summarize-document)
#   --region REGION           Use specific region (default: us-central1)
#   --force                   Skip confirmation prompts
#   --dry-run                 Show what would be deleted without executing
#   --help                    Show this help message
#
# Prerequisites:
# - gcloud CLI installed and configured
# - Access to the GCP project where resources were deployed
# =============================================================================

set -euo pipefail

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly DEFAULT_REGION="us-central1"
readonly DEFAULT_FUNCTION_NAME="summarize-document"

# Global variables
PROJECT_ID=""
BUCKET_NAME=""
FUNCTION_NAME="$DEFAULT_FUNCTION_NAME"
REGION="$DEFAULT_REGION"
FORCE=false
DRY_RUN=false

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $*" >&2
}

# Help function
show_help() {
    cat << EOF
Smart Document Summarization Cleanup Script

This script safely removes all resources created by the deployment including:
- Cloud Storage buckets and all contained objects
- Cloud Functions and associated triggers
- IAM policy bindings (automatic cleanup)
- Local temporary files and directories

Usage: $0 [OPTIONS]

Options:
  --project-id PROJECT_ID    Use specific project ID (required)
  --bucket-name BUCKET_NAME  Use specific bucket name (required)
  --function-name NAME       Use specific function name (default: $DEFAULT_FUNCTION_NAME)
  --region REGION           Use specific region (default: $DEFAULT_REGION)
  --force                   Skip confirmation prompts
  --dry-run                 Show what would be deleted without executing
  --help                    Show this help message

Examples:
  $0 --project-id my-project --bucket-name doc-summarizer-abc123
  $0 --project-id my-project --bucket-name doc-summarizer-abc123 --force
  $0 --project-id my-project --bucket-name doc-summarizer-abc123 --dry-run

EOF
}

# Parse command line arguments
parse_args() {
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
            --region)
                REGION="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
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
}

# Validation functions
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id option."
        exit 1
    fi
    
    if [[ -z "$BUCKET_NAME" ]]; then
        log_error "Bucket name is required. Use --bucket-name option."
        exit 1
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Project '$PROJECT_ID' not found or not accessible."
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Set project configuration
configure_project() {
    log_info "Configuring gcloud project settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would set project: $PROJECT_ID"
        log_info "[DRY-RUN] Would set region: $REGION"
        return
    fi
    
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set functions/region "$REGION"
    
    log_success "Project configuration completed"
}

# Confirm deletion with user
confirm_deletion() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return
    fi
    
    echo ""
    log_warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "This will permanently delete the following resources:"
    echo ""
    echo "📁 Cloud Storage Bucket: gs://$BUCKET_NAME"
    echo "   └── All objects and versions will be permanently deleted"
    echo ""
    echo "⚡ Cloud Function: $FUNCTION_NAME (in $REGION)"
    echo "   └── Function code, configuration, and triggers will be removed"
    echo ""
    echo "🔐 IAM Policy Bindings"
    echo "   └── Service account permissions will be automatically cleaned up"
    echo ""
    echo "💾 Local Files"
    echo "   └── Temporary function source directory will be removed"
    echo ""
    
    # Get estimated costs for information
    local bucket_size
    bucket_size=$(gsutil du -s gs://"$BUCKET_NAME" 2>/dev/null | awk '{print $1}' || echo "unknown")
    if [[ "$bucket_size" != "unknown" && "$bucket_size" -gt 0 ]]; then
        echo "💰 Storage cost savings: ~\$$(echo "scale=2; $bucket_size / 1024 / 1024 / 1024 * 0.020" | bc -l 2>/dev/null || echo "0.02")/month"
    fi
    
    echo ""
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Check resource existence
check_resource_existence() {
    log_info "Checking resource existence..."
    
    local bucket_exists=false
    local function_exists=false
    
    # Check if bucket exists
    if gsutil ls -b gs://"$BUCKET_NAME" &>/dev/null; then
        bucket_exists=true
        local object_count
        object_count=$(gsutil ls gs://"$BUCKET_NAME"/** 2>/dev/null | wc -l || echo "0")
        log_info "Bucket gs://$BUCKET_NAME exists with $object_count objects"
    else
        log_warn "Bucket gs://$BUCKET_NAME does not exist"
    fi
    
    # Check if function exists
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --gen2 &>/dev/null; then
        function_exists=true
        local function_state
        function_state=$(gcloud functions describe "$FUNCTION_NAME" \
            --region="$REGION" \
            --gen2 \
            --format="value(state)" 2>/dev/null || echo "unknown")
        log_info "Function $FUNCTION_NAME exists with state: $function_state"
    else
        log_warn "Function $FUNCTION_NAME does not exist in region $REGION"
    fi
    
    if [[ "$bucket_exists" == "false" && "$function_exists" == "false" ]]; then
        log_warn "No resources found to clean up"
        if [[ "$FORCE" != "true" ]]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 0
            fi
        fi
    fi
}

# Delete Cloud Function
delete_cloud_function() {
    log_info "Deleting Cloud Function..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete function: $FUNCTION_NAME"
        return
    fi
    
    # Check if function exists before attempting deletion
    if ! gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --gen2 &>/dev/null; then
        log_warn "Function $FUNCTION_NAME does not exist, skipping deletion"
        return
    fi
    
    # Store service account for IAM cleanup
    local function_sa
    function_sa=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --gen2 \
        --format="value(serviceConfig.serviceAccountEmail)" 2>/dev/null || echo "")
    
    # Delete the function
    gcloud functions delete "$FUNCTION_NAME" \
        --region="$REGION" \
        --gen2 \
        --quiet
    
    log_success "Cloud Function deleted: $FUNCTION_NAME"
    
    # IAM cleanup (note: service account is automatically deleted with function)
    if [[ -n "$function_sa" ]]; then
        log_info "Service account $function_sa was automatically cleaned up with function deletion"
    fi
}

# Delete Cloud Storage bucket
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket and all contents..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete bucket: gs://$BUCKET_NAME"
        return
    fi
    
    # Check if bucket exists
    if ! gsutil ls -b gs://"$BUCKET_NAME" &>/dev/null; then
        log_warn "Bucket gs://$BUCKET_NAME does not exist, skipping deletion"
        return
    fi
    
    # Get object count for logging
    local object_count
    object_count=$(gsutil ls -r gs://"$BUCKET_NAME" 2>/dev/null | grep -v "/$" | wc -l || echo "0")
    
    if [[ "$object_count" -gt 0 ]]; then
        log_info "Deleting $object_count objects from bucket..."
    fi
    
    # Remove all objects and the bucket (parallel for faster deletion)
    gsutil -m rm -r gs://"$BUCKET_NAME"
    
    log_success "Storage bucket deleted: gs://$BUCKET_NAME"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local temporary files..."
    
    local function_dir="$PROJECT_DIR/function-source"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would clean up local directory: $function_dir"
        return
    fi
    
    # Remove function source directory if it exists
    if [[ -d "$function_dir" ]]; then
        rm -rf "$function_dir"
        log_success "Removed local function directory: $function_dir"
    else
        log_info "No local function directory found to clean up"
    fi
    
    # Remove any sample files in the current directory
    local cleanup_files=("sample_report.txt" "api_documentation.txt" "test_binary.bin")
    local cleaned_count=0
    
    for file in "${cleanup_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            ((cleaned_count++))
        fi
    done
    
    if [[ "$cleaned_count" -gt 0 ]]; then
        log_success "Removed $cleaned_count sample files from current directory"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local issues_found=false
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would verify cleanup completion"
        return
    fi
    
    # Check if bucket still exists
    if gsutil ls -b gs://"$BUCKET_NAME" &>/dev/null; then
        log_error "Bucket gs://$BUCKET_NAME still exists"
        issues_found=true
    fi
    
    # Check if function still exists
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --gen2 &>/dev/null; then
        log_error "Function $FUNCTION_NAME still exists"
        issues_found=true
    fi
    
    if [[ "$issues_found" == "true" ]]; then
        log_error "Cleanup verification failed. Some resources may still exist."
        exit 1
    fi
    
    log_success "Cleanup verification completed successfully"
}

# Show cleanup summary
show_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo ""
    echo "Resources Removed:"
    echo "✅ Cloud Storage Bucket: gs://$BUCKET_NAME"
    echo "✅ Cloud Function: $FUNCTION_NAME"
    echo "✅ IAM Policy Bindings (automatic)"
    echo "✅ Local temporary files"
    echo ""
    echo "💰 Cost Impact:"
    echo "- Storage costs: Eliminated"
    echo "- Function execution costs: Eliminated"
    echo "- Vertex AI model usage: Will stop (no new requests)"
    echo ""
    echo "ℹ️  Note: Vertex AI usage charges may still apply for requests made before cleanup."
    echo "Check your billing dashboard for any remaining charges."
}

# Main execution function
main() {
    log_info "Starting Smart Document Summarization cleanup"
    
    parse_args "$@"
    validate_prerequisites
    configure_project
    check_resource_existence
    confirm_deletion
    delete_cloud_function
    delete_storage_bucket
    cleanup_local_files
    verify_cleanup
    
    log_success "Cleanup completed successfully!"
    show_cleanup_summary
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi