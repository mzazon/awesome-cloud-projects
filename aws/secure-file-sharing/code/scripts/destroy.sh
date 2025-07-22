#!/bin/bash

# Destroy script for File Sharing Solutions with S3 Presigned URLs
# This script safely removes all resources created by the deployment script
# with confirmation prompts and proper error handling

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
}

# Force flag for non-interactive cleanup
FORCE_CLEANUP=false

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_CLEANUP=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  -f, --force    Skip confirmation prompts"
                echo "  -h, --help     Show this help message"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# Load environment variables
load_environment() {
    log "Loading environment configuration..."
    
    if [ -f ".env" ]; then
        source .env
        success "Environment variables loaded from .env file"
    else
        warning "No .env file found, attempting to use current environment"
        
        # Try to detect resources to clean up
        if [ -z "${BUCKET_NAME:-}" ]; then
            log "Searching for file-sharing-demo buckets..."
            DEMO_BUCKETS=$(aws s3api list-buckets \
                --query 'Buckets[?contains(Name, `file-sharing-demo`)].Name' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$DEMO_BUCKETS" ]; then
                echo "Found potential buckets to clean up:"
                echo "$DEMO_BUCKETS"
                
                if [ "$FORCE_CLEANUP" = false ]; then
                    echo ""
                    read -p "Enter bucket name to delete (or press Enter to abort): " BUCKET_NAME
                    if [ -z "$BUCKET_NAME" ]; then
                        log "No bucket specified, aborting cleanup"
                        exit 0
                    fi
                fi
            else
                log "No file-sharing-demo buckets found"
                exit 0
            fi
        fi
    fi
    
    # Validate bucket exists
    if [ -n "${BUCKET_NAME:-}" ]; then
        if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
            warning "Bucket $BUCKET_NAME does not exist or is not accessible"
            BUCKET_NAME=""
        fi
    fi
}

# Confirm destruction
confirm_destruction() {
    if [ "$FORCE_CLEANUP" = true ]; then
        log "Force cleanup enabled, skipping confirmation"
        return 0
    fi
    
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete:"
    
    if [ -n "${BUCKET_NAME:-}" ]; then
        echo "  • S3 Bucket: $BUCKET_NAME"
        echo "  • All objects and versions in the bucket"
        echo "  • Bucket configurations and policies"
    fi
    
    echo "  • Local utility scripts and test files"
    echo "  • Environment configuration files"
    echo ""
    echo "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed, proceeding with cleanup"
}

# Delete all objects from bucket
delete_bucket_objects() {
    if [ -z "${BUCKET_NAME:-}" ]; then
        warning "No bucket specified, skipping object deletion"
        return 0
    fi
    
    log "Deleting all objects from bucket: $BUCKET_NAME"
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        warning "Bucket $BUCKET_NAME does not exist, skipping object deletion"
        return 0
    fi
    
    # Delete all object versions (including delete markers)
    log "Removing all object versions and delete markers..."
    aws s3api list-object-versions \
        --bucket "$BUCKET_NAME" \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' \
        --output text | \
    while read -r key version_id; do
        if [ -n "$key" ] && [ "$key" != "None" ]; then
            aws s3api delete-object \
                --bucket "$BUCKET_NAME" \
                --key "$key" \
                --version-id "$version_id" >/dev/null 2>&1 || true
        fi
    done
    
    # Delete delete markers
    aws s3api list-object-versions \
        --bucket "$BUCKET_NAME" \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
        --output text | \
    while read -r key version_id; do
        if [ -n "$key" ] && [ "$key" != "None" ]; then
            aws s3api delete-object \
                --bucket "$BUCKET_NAME" \
                --key "$key" \
                --version-id "$version_id" >/dev/null 2>&1 || true
        fi
    done
    
    # Force delete any remaining objects
    aws s3 rm s3://"$BUCKET_NAME" --recursive --quiet 2>/dev/null || true
    
    success "All objects deleted from bucket"
}

# Delete incomplete multipart uploads
cleanup_multipart_uploads() {
    if [ -z "${BUCKET_NAME:-}" ]; then
        warning "No bucket specified, skipping multipart upload cleanup"
        return 0
    fi
    
    log "Cleaning up incomplete multipart uploads..."
    
    # List and abort incomplete multipart uploads
    aws s3api list-multipart-uploads \
        --bucket "$BUCKET_NAME" \
        --query 'Uploads[].{Key:Key,UploadId:UploadId}' \
        --output text 2>/dev/null | \
    while read -r key upload_id; do
        if [ -n "$key" ] && [ "$key" != "None" ]; then
            aws s3api abort-multipart-upload \
                --bucket "$BUCKET_NAME" \
                --key "$key" \
                --upload-id "$upload_id" >/dev/null 2>&1 || true
        fi
    done
    
    success "Multipart uploads cleaned up"
}

# Delete S3 bucket
delete_bucket() {
    if [ -z "${BUCKET_NAME:-}" ]; then
        warning "No bucket specified, skipping bucket deletion"
        return 0
    fi
    
    log "Deleting S3 bucket: $BUCKET_NAME"
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        warning "Bucket $BUCKET_NAME does not exist, skipping deletion"
        return 0
    fi
    
    # Remove bucket policy if it exists
    aws s3api delete-bucket-policy --bucket "$BUCKET_NAME" 2>/dev/null || true
    
    # Remove bucket encryption
    aws s3api delete-bucket-encryption --bucket "$BUCKET_NAME" 2>/dev/null || true
    
    # Remove bucket lifecycle configuration
    aws s3api delete-bucket-lifecycle --bucket "$BUCKET_NAME" 2>/dev/null || true
    
    # Remove bucket versioning (can't be disabled, but we can stop new versions)
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Suspended 2>/dev/null || true
    
    # Delete the bucket
    aws s3api delete-bucket --bucket "$BUCKET_NAME"
    
    success "S3 bucket deleted successfully"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files and scripts..."
    
    # Remove sample files
    rm -f sample-document.txt
    rm -f downloaded_sample.txt
    rm -f test-upload.txt
    rm -f downloaded-upload.txt
    rm -f test.txt
    
    # Remove generated files
    rm -f presigned_urls.txt
    rm -f download_url.txt
    rm -f upload_url.txt
    
    # Remove utility scripts
    rm -f generate_presigned_urls.sh
    rm -f check_url_expiry.py
    
    # Remove environment file
    rm -f .env
    
    success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check if bucket still exists
    if [ -n "${BUCKET_NAME:-}" ]; then
        if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
            error "Bucket $BUCKET_NAME still exists"
            cleanup_errors=$((cleanup_errors + 1))
        else
            success "Bucket $BUCKET_NAME successfully deleted"
        fi
    fi
    
    # Check for remaining local files
    local remaining_files=(
        "sample-document.txt"
        "presigned_urls.txt"
        "generate_presigned_urls.sh"
        "check_url_expiry.py"
        ".env"
    )
    
    for file in "${remaining_files[@]}"; do
        if [ -f "$file" ]; then
            warning "Local file still exists: $file"
            cleanup_errors=$((cleanup_errors + 1))
        fi
    done
    
    if [ $cleanup_errors -eq 0 ]; then
        success "Cleanup verification passed"
        return 0
    else
        error "Cleanup verification failed with $cleanup_errors errors"
        return 1
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    echo ""
    log "🧹 Cleanup Summary:"
    
    if [ -n "${BUCKET_NAME:-}" ]; then
        echo "  • S3 Bucket: $BUCKET_NAME - DELETED"
        echo "  • All objects and versions - REMOVED"
        echo "  • Bucket configurations - REMOVED"
    fi
    
    echo "  • Local utility scripts - REMOVED"
    echo "  • Test files and URLs - REMOVED"
    echo "  • Environment configuration - REMOVED"
    echo ""
    
    success "File Sharing Solution cleanup completed successfully!"
    echo ""
    log "💡 Resources have been cleaned up. No ongoing charges will occur."
    echo "   To redeploy the solution, run deploy.sh again."
}

# Main cleanup function
main() {
    log "Starting cleanup of File Sharing Solution with S3 Presigned URLs"
    
    parse_arguments "$@"
    load_environment
    confirm_destruction
    
    # Perform cleanup in proper order
    delete_bucket_objects
    cleanup_multipart_uploads
    delete_bucket
    cleanup_local_files
    
    # Verify and summarize
    if verify_cleanup; then
        show_cleanup_summary
    else
        error "Cleanup completed with some issues. Please review the warnings above."
        exit 1
    fi
}

# Run main function with all arguments
main "$@"