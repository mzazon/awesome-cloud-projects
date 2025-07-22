#!/bin/bash

# AWS S3 Multi-Part Upload Strategies - Cleanup Script
# Removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Logging function
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$TIMESTAMP] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${RED}"
    echo "=========================================="
    echo "    AWS S3 Multi-Part Upload Cleanup"
    echo "=========================================="
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Get user confirmation for destruction
get_user_confirmation() {
    echo
    print_warning "This script will permanently delete the following resources:"
    echo "  - S3 buckets with 'multipart-upload-demo-' prefix and ALL their contents"
    echo "  - CloudWatch dashboards with 'S3-MultipartUpload-' prefix"
    echo "  - Local test files and configuration files"
    echo "  - AWS CLI S3 multipart upload configuration"
    echo
    print_error "THIS ACTION CANNOT BE UNDONE!"
    echo
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    echo
    if [[ ! $REPLY == "yes" ]]; then
        log "Cleanup cancelled by user"
        print_info "Cleanup cancelled. No resources were deleted."
        exit 0
    fi
}

# Set environment variables from previous deployment
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        print_error "AWS region not configured. Please set it with 'aws configure'"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    
    print_success "Environment variables set"
}

# Find and cleanup S3 buckets
cleanup_s3_buckets() {
    log "Finding S3 buckets with 'multipart-upload-demo-' prefix..."
    
    # Get list of buckets matching our pattern
    local buckets=$(aws s3api list-buckets \
        --query "Buckets[?starts_with(Name, 'multipart-upload-demo-')].Name" \
        --output text)
    
    if [[ -z "$buckets" ]]; then
        print_info "No S3 buckets found with 'multipart-upload-demo-' prefix"
        return 0
    fi
    
    echo "Found the following buckets to delete:"
    for bucket in $buckets; do
        echo "  - $bucket"
    done
    echo
    
    # Process each bucket
    for bucket in $buckets; do
        log "Processing bucket: $bucket"
        
        # Check if bucket exists (it might have been deleted in a previous run)
        if ! aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
            print_warning "Bucket $bucket does not exist or is not accessible"
            continue
        fi
        
        # Abort all incomplete multipart uploads
        log "Aborting incomplete multipart uploads in $bucket..."
        local incomplete_uploads=$(aws s3api list-multipart-uploads \
            --bucket "$bucket" \
            --query 'Uploads[*].[Key,UploadId]' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$incomplete_uploads" ]]; then
            echo "$incomplete_uploads" | while read -r key upload_id; do
                if [[ -n "$key" && -n "$upload_id" ]]; then
                    aws s3api abort-multipart-upload \
                        --bucket "$bucket" \
                        --key "$key" \
                        --upload-id "$upload_id" 2>/dev/null || true
                    log "Aborted upload: $key ($upload_id)"
                fi
            done
            print_success "Aborted incomplete multipart uploads in $bucket"
        else
            print_info "No incomplete multipart uploads found in $bucket"
        fi
        
        # Delete all object versions (including delete markers)
        log "Deleting all objects and versions in $bucket..."
        aws s3api list-object-versions \
            --bucket "$bucket" \
            --output json \
            --query 'Versions[*].[Key,VersionId]' | \
        jq -r '.[] | @tsv' | while IFS=$'\t' read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" && "$version_id" != "null" ]]; then
                aws s3api delete-object \
                    --bucket "$bucket" \
                    --key "$key" \
                    --version-id "$version_id" >/dev/null 2>&1 || true
            fi
        done
        
        # Delete all delete markers
        aws s3api list-object-versions \
            --bucket "$bucket" \
            --output json \
            --query 'DeleteMarkers[*].[Key,VersionId]' | \
        jq -r '.[] | @tsv' | while IFS=$'\t' read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" && "$version_id" != "null" ]]; then
                aws s3api delete-object \
                    --bucket "$bucket" \
                    --key "$key" \
                    --version-id "$version_id" >/dev/null 2>&1 || true
            fi
        done
        
        # Use S3 sync to ensure all objects are deleted
        aws s3 rm "s3://$bucket" --recursive --quiet 2>/dev/null || true
        
        # Wait a moment for eventual consistency
        sleep 2
        
        # Delete the bucket
        log "Deleting bucket: $bucket"
        if aws s3api delete-bucket --bucket "$bucket" 2>/dev/null; then
            print_success "Deleted bucket: $bucket"
        else
            print_warning "Failed to delete bucket: $bucket (may require manual cleanup)"
        fi
    done
}

# Cleanup CloudWatch dashboards
cleanup_cloudwatch_dashboards() {
    log "Finding CloudWatch dashboards with 'S3-MultipartUpload-' prefix..."
    
    # Get list of dashboards matching our pattern
    local dashboards=$(aws cloudwatch list-dashboards \
        --query "DashboardEntries[?starts_with(DashboardName, 'S3-MultipartUpload-')].DashboardName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$dashboards" ]]; then
        print_info "No CloudWatch dashboards found with 'S3-MultipartUpload-' prefix"
        return 0
    fi
    
    echo "Found the following dashboards to delete:"
    for dashboard in $dashboards; do
        echo "  - $dashboard"
    done
    echo
    
    # Delete dashboards
    for dashboard in $dashboards; do
        log "Deleting CloudWatch dashboard: $dashboard"
        if aws cloudwatch delete-dashboards --dashboard-names "$dashboard" 2>/dev/null; then
            print_success "Deleted CloudWatch dashboard: $dashboard"
        else
            print_warning "Failed to delete CloudWatch dashboard: $dashboard"
        fi
    done
}

# Cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "large-test-file.bin"
        "downloaded-large-test-file.bin"
        "parts-manifest.json"
        "lifecycle-policy.json"
        "dashboard-config.json"
        "part-*"
    )
    
    local removed_count=0
    for file_pattern in "${files_to_remove[@]}"; do
        if ls $file_pattern 1> /dev/null 2>&1; then
            rm -f $file_pattern
            log "Removed: $file_pattern"
            ((removed_count++))
        fi
    done
    
    if [[ $removed_count -gt 0 ]]; then
        print_success "Removed $removed_count local file(s)"
    else
        print_info "No local files found to remove"
    fi
}

# Reset AWS CLI S3 configuration
reset_aws_cli_config() {
    log "Resetting AWS CLI S3 configuration to defaults..."
    
    # Reset S3 configuration to AWS CLI defaults
    aws configure set default.s3.multipart_threshold 8MB
    aws configure set default.s3.multipart_chunksize 8MB
    aws configure set default.s3.max_concurrent_requests 10
    aws configure set default.s3.max_bandwidth ""
    
    print_success "AWS CLI S3 configuration reset to defaults"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check for remaining buckets
    local remaining_buckets=$(aws s3api list-buckets \
        --query "Buckets[?starts_with(Name, 'multipart-upload-demo-')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_buckets" ]]; then
        print_warning "Some S3 buckets may still exist: $remaining_buckets"
        ((cleanup_issues++))
    fi
    
    # Check for remaining dashboards
    local remaining_dashboards=$(aws cloudwatch list-dashboards \
        --query "DashboardEntries[?starts_with(DashboardName, 'S3-MultipartUpload-')].DashboardName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_dashboards" ]]; then
        print_warning "Some CloudWatch dashboards may still exist: $remaining_dashboards"
        ((cleanup_issues++))
    fi
    
    # Check for remaining local files
    local remaining_files=$(ls large-test-file.bin downloaded-* parts-manifest.json lifecycle-policy.json dashboard-config.json part-* 2>/dev/null || echo "")
    
    if [[ -n "$remaining_files" ]]; then
        print_warning "Some local files may still exist: $remaining_files"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        print_success "Cleanup verification passed - no remaining resources found"
    else
        print_warning "Cleanup verification found $cleanup_issues potential issue(s)"
        echo "Please review the warnings above and manually clean up any remaining resources if needed."
    fi
}

# Generate cleanup summary
generate_summary() {
    echo
    echo -e "${BLUE}=========================================="
    echo "          Cleanup Summary"
    echo -e "==========================================${NC}"
    echo
    print_success "S3 buckets with 'multipart-upload-demo-' prefix: Deleted"
    print_success "CloudWatch dashboards with 'S3-MultipartUpload-' prefix: Deleted"
    print_success "Local test files and configuration: Removed"
    print_success "AWS CLI S3 configuration: Reset to defaults"
    echo
    print_info "Cleanup completed. All resources should be removed."
    echo
    echo "If you see any warnings above, you may need to manually clean up those resources."
    echo "You can check the AWS Console to verify all resources have been removed:"
    echo "• S3 Console: https://s3.console.aws.amazon.com/s3/buckets"
    echo "• CloudWatch Console: https://$AWS_REGION.console.aws.amazon.com/cloudwatch/home?region=$AWS_REGION#dashboards:"
    echo
}

# Handle cleanup errors gracefully
handle_cleanup_errors() {
    log_error "Cleanup encountered errors. Some resources may not have been deleted."
    echo
    print_error "Cleanup completed with errors. Please check the log file: $LOG_FILE"
    echo
    echo "You may need to manually clean up remaining resources:"
    echo "1. Check S3 Console for buckets starting with 'multipart-upload-demo-'"
    echo "2. Check CloudWatch Console for dashboards starting with 'S3-MultipartUpload-'"
    echo "3. Remove any remaining local files (large-test-file.bin, etc.)"
    echo
    exit 1
}

# Main cleanup function
main() {
    print_header
    log "Starting AWS S3 Multi-Part Upload cleanup at $TIMESTAMP"
    
    # Set up error handling
    trap handle_cleanup_errors ERR
    
    check_prerequisites
    get_user_confirmation
    setup_environment
    cleanup_s3_buckets
    cleanup_cloudwatch_dashboards
    cleanup_local_files
    reset_aws_cli_config
    verify_cleanup
    generate_summary
    
    log "Cleanup completed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
    print_success "AWS S3 Multi-Part Upload cleanup completed successfully!"
}

# Run main function
main "$@"