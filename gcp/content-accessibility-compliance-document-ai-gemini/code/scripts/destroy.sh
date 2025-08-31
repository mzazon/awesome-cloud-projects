#!/bin/bash

# Content Accessibility Compliance Cleanup Script
# Remove all resources created by the accessibility compliance deployment

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        error "Please install gcloud CLI: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed or not in PATH"
        error "Please install Google Cloud SDK with gsutil"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | grep -q "."; then
        error "No active gcloud authentication found"
        error "Please run: gcloud auth login"
        exit 1
    fi
    
    success "All prerequisites met"
}

# Function to validate project access
validate_project_access() {
    log "Validating project access..."
    
    local project_id="$1"
    
    # Check if project exists and user has access
    if ! gcloud projects describe "$project_id" &> /dev/null; then
        error "Cannot access project: $project_id"
        error "Please verify the project ID and your permissions"
        exit 1
    fi
    
    success "Project access validated"
}

# Function to get confirmation for destructive operations
confirm_destruction() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        return 0
    fi
    
    warning "This will permanently delete the following ${resource_type}:"
    echo "  ${resource_name}"
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    case "$confirmation" in
        yes|YES|y|Y)
            return 0
            ;;
        *)
            log "Operation cancelled by user"
            return 1
            ;;
    esac
}

# Function to list and confirm resource deletion
list_resources() {
    log "Scanning for accessibility compliance resources..."
    
    local project_id="$1"
    local region="${2:-us-central1}"
    
    echo ""
    echo "Found the following resources to delete:"
    echo "======================================"
    
    # List Cloud Functions
    echo ""
    echo "Cloud Functions (Gen 2):"
    local functions=$(gcloud functions list --regions="${region}" --format="value(name)" --filter="name:accessibility-analyzer" 2>/dev/null || true)
    if [[ -n "$functions" ]]; then
        echo "$functions" | while read -r function; do
            echo "  - $function"
        done
    else
        echo "  - No matching Cloud Functions found"
    fi
    
    # List Document AI processors
    echo ""
    echo "Document AI Processors:"
    local processors=$(gcloud documentai processors list --location="${region}" --format="value(displayName)" --filter="displayName:accessibility-processor" 2>/dev/null || true)
    if [[ -n "$processors" ]]; then
        echo "$processors" | while read -r processor; do
            echo "  - $processor"
        done
    else
        echo "  - No matching Document AI processors found"
    fi
    
    # List Storage Buckets
    echo ""
    echo "Cloud Storage Buckets:"
    local buckets=$(gsutil ls -p "${project_id}" 2>/dev/null | grep "accessibility-docs" || true)
    if [[ -n "$buckets" ]]; then
        echo "$buckets" | while read -r bucket; do
            echo "  - $bucket"
        done
    else
        echo "  - No matching storage buckets found"
    fi
    
    echo ""
    echo "======================================"
    echo ""
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    local region="$1"
    
    # Get list of accessibility-related functions
    local functions=$(gcloud functions list --regions="${region}" --format="value(name)" --filter="name:accessibility-analyzer" 2>/dev/null || true)
    
    if [[ -z "$functions" ]]; then
        warning "No Cloud Functions found to delete"
        return 0
    fi
    
    echo "$functions" | while read -r function_full_name; do
        if [[ -n "$function_full_name" ]]; then
            local function_name=$(basename "$function_full_name")
            
            if confirm_destruction "Cloud Function" "$function_name"; then
                log "Deleting Cloud Function: $function_name"
                if gcloud functions delete "$function_name" --region="${region}" --quiet 2>/dev/null; then
                    success "Deleted Cloud Function: $function_name"
                else
                    error "Failed to delete Cloud Function: $function_name"
                fi
            else
                log "Skipping Cloud Function: $function_name"
            fi
        fi
    done
}

# Function to delete Document AI processors
delete_document_ai_processors() {
    log "Deleting Document AI processors..."
    
    local region="$1"
    
    # Get list of accessibility-related processors
    local processors=$(gcloud documentai processors list --location="${region}" --format="value(name,displayName)" --filter="displayName:accessibility-processor" 2>/dev/null || true)
    
    if [[ -z "$processors" ]]; then
        warning "No Document AI processors found to delete"
        return 0
    fi
    
    echo "$processors" | while IFS=$'\t' read -r processor_path display_name; do
        if [[ -n "$processor_path" && -n "$display_name" ]]; then
            local processor_id=$(basename "$processor_path")
            
            if confirm_destruction "Document AI Processor" "$display_name ($processor_id)"; then
                log "Deleting Document AI processor: $display_name"
                if gcloud documentai processors delete "$processor_id" --location="${region}" --quiet 2>/dev/null; then
                    success "Deleted Document AI processor: $display_name"
                else
                    error "Failed to delete Document AI processor: $display_name"
                fi
            else
                log "Skipping Document AI processor: $display_name"
            fi
        fi
    done
}

# Function to delete storage buckets
delete_storage_buckets() {
    log "Deleting Cloud Storage buckets..."
    
    local project_id="$1"
    
    # Get list of accessibility-related buckets
    local buckets=$(gsutil ls -p "${project_id}" 2>/dev/null | grep "accessibility-docs" || true)
    
    if [[ -z "$buckets" ]]; then
        warning "No Cloud Storage buckets found to delete"
        return 0
    fi
    
    echo "$buckets" | while read -r bucket_url; do
        if [[ -n "$bucket_url" ]]; then
            local bucket_name=$(echo "$bucket_url" | sed 's|gs://||' | sed 's|/||')
            
            if confirm_destruction "Cloud Storage Bucket" "$bucket_name"; then
                log "Deleting Cloud Storage bucket: $bucket_name"
                
                # First, try to list bucket contents to check if it exists and is accessible
                if gsutil ls -b "gs://${bucket_name}" &> /dev/null; then
                    # Get object count for user awareness
                    local object_count=$(gsutil du -s "gs://${bucket_name}" 2>/dev/null | awk '{print $3}' || echo "unknown")
                    log "Bucket contains objects: $object_count"
                    
                    # Delete all objects and then the bucket
                    if gsutil -m rm -r "gs://${bucket_name}" 2>/dev/null; then
                        success "Deleted Cloud Storage bucket: $bucket_name"
                    else
                        error "Failed to delete Cloud Storage bucket: $bucket_name"
                    fi
                else
                    warning "Bucket gs://${bucket_name} not accessible or already deleted"
                fi
            else
                log "Skipping Cloud Storage bucket: $bucket_name"
            fi
        fi
    done
}

# Function to clean up local environment
cleanup_local_environment() {
    log "Cleaning up local environment..."
    
    # List of environment variables to unset
    local env_vars=(
        "PROJECT_ID"
        "REGION"
        "ZONE"
        "BUCKET_NAME"
        "FUNCTION_NAME"
        "PROCESSOR_NAME"
        "PROCESSOR_ID"
        "RANDOM_SUFFIX"
    )
    
    for var in "${env_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            unset "$var"
            log "Unset environment variable: $var"
        fi
    done
    
    # Remove any temporary files that might have been created
    local temp_files=(
        "/tmp/accessibility-function-*"
        "./accessibility-function"
        "./sample.txt"
        "./test_document.html"
    )
    
    for pattern in "${temp_files[@]}"; do
        if ls $pattern 2>/dev/null; then
            rm -rf $pattern
            log "Removed temporary files: $pattern"
        fi
    done
    
    success "Local environment cleaned up"
}

# Function to verify resource deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local project_id="$1"
    local region="$2"
    local failed_deletions=()
    
    # Check Cloud Functions
    local remaining_functions=$(gcloud functions list --regions="${region}" --format="value(name)" --filter="name:accessibility-analyzer" 2>/dev/null || true)
    if [[ -n "$remaining_functions" ]]; then
        failed_deletions+=("Cloud Functions: $remaining_functions")
    fi
    
    # Check Document AI processors
    local remaining_processors=$(gcloud documentai processors list --location="${region}" --format="value(displayName)" --filter="displayName:accessibility-processor" 2>/dev/null || true)
    if [[ -n "$remaining_processors" ]]; then
        failed_deletions+=("Document AI processors: $remaining_processors")
    fi
    
    # Check Storage buckets
    local remaining_buckets=$(gsutil ls -p "${project_id}" 2>/dev/null | grep "accessibility-docs" || true)
    if [[ -n "$remaining_buckets" ]]; then
        failed_deletions+=("Storage buckets: $remaining_buckets")
    fi
    
    if [[ ${#failed_deletions[@]} -eq 0 ]]; then
        success "All resources successfully deleted"
        return 0
    else
        warning "Some resources may still exist:"
        for resource in "${failed_deletions[@]}"; do
            echo "  - $resource"
        done
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo ""
    echo "The following operations were performed:"
    echo "1. Cloud Functions deleted"
    echo "2. Document AI processors deleted"
    echo "3. Cloud Storage buckets and contents deleted"
    echo "4. Local environment variables cleared"
    echo "5. Temporary files removed"
    echo ""
    
    if verify_deletion "$PROJECT_ID" "$REGION"; then
        success "All accessibility compliance resources have been successfully removed"
    else
        warning "Some resources may require manual cleanup"
        echo ""
        echo "To manually verify remaining resources:"
        echo "1. Check Cloud Functions: gcloud functions list --regions=$REGION"
        echo "2. Check Document AI: gcloud documentai processors list --location=$REGION"
        echo "3. Check Storage: gsutil ls -p $PROJECT_ID"
    fi
    
    echo ""
    log "Cleanup completed"
}

# Function to handle batch deletion mode
batch_delete_mode() {
    log "Running in batch deletion mode..."
    
    local project_id="$1"
    local region="$2"
    
    # Delete all resources without individual confirmation
    FORCE_DELETE=true
    
    delete_cloud_functions "$region"
    delete_document_ai_processors "$region"
    delete_storage_buckets "$project_id"
    cleanup_local_environment
    
    success "Batch deletion completed"
}

# Main cleanup function
main() {
    log "Starting Content Accessibility Compliance cleanup..."
    
    # Parse command line arguments
    local batch_mode=false
    local show_help=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --batch|--force)
                batch_mode=true
                shift
                ;;
            --help|-h)
                show_help=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help=true
                shift
                ;;
        esac
    done
    
    if [[ "$show_help" == "true" ]]; then
        echo "Content Accessibility Compliance Cleanup Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --batch, --force    Delete all resources without individual confirmation"
        echo "  --help, -h          Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  PROJECT_ID          GCP Project ID (will prompt if not set)"
        echo "  REGION              GCP Region (default: us-central1)"
        echo ""
        exit 0
    fi
    
    # Set environment variables with defaults or prompts
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
    if [[ -z "$PROJECT_ID" ]]; then
        read -p "Enter GCP Project ID: " PROJECT_ID
        export PROJECT_ID
    fi
    
    export REGION="${REGION:-us-central1}"
    
    # Check prerequisites
    check_prerequisites
    
    # Validate project access
    validate_project_access "$PROJECT_ID"
    
    if [[ "$batch_mode" == "true" ]]; then
        # Batch deletion mode
        warning "Running in batch deletion mode - all resources will be deleted without confirmation"
        sleep 3
        batch_delete_mode "$PROJECT_ID" "$REGION"
    else
        # Interactive mode
        list_resources "$PROJECT_ID" "$REGION"
        
        echo ""
        warning "This operation will permanently delete resources and cannot be undone!"
        echo ""
        read -p "Do you want to proceed with the cleanup? (yes/no): " proceed_confirmation
        
        case "$proceed_confirmation" in
            yes|YES|y|Y)
                log "Proceeding with cleanup..."
                ;;
            *)
                log "Cleanup cancelled by user"
                exit 0
                ;;
        esac
        
        # Delete resources with individual confirmations
        delete_cloud_functions "$REGION"
        delete_document_ai_processors "$REGION"
        delete_storage_buckets "$PROJECT_ID"
        cleanup_local_environment
    fi
    
    # Display cleanup summary
    display_cleanup_summary
}

# Handle script interruption
trap 'error "Cleanup interrupted"; exit 1' INT TERM

# Run main function
main "$@"