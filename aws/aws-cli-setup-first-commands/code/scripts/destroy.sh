#!/bin/bash

# AWS CLI Setup and First Commands - Cleanup Script
# This script removes all resources created by the deploy.sh script
# Recipe: aws-cli-setup-first-commands

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
WORKING_DIR="${HOME}/aws-cli-tutorial"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Success message
success() {
    log "${GREEN}✅ $1${NC}"
}

# Warning message  
warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Info message
info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        warning "AWS CLI not found. Some cleanup operations may be skipped."
        return 0
    fi
    
    # Check if AWS CLI is configured
    if ! aws configure list | grep -q "access_key" || [[ "$(aws configure get aws_access_key_id)" == "None" ]]; then
        warning "AWS CLI not configured. Some AWS resources may not be cleaned up."
        return 0
    fi
    
    # Test AWS authentication
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        warning "AWS authentication failed. Some AWS resources may not be cleaned up."
        return 0
    fi
    
    success "Prerequisites check completed"
}

# Load environment variables
load_environment() {
    info "Loading environment variables..."
    
    if [[ -f "${WORKING_DIR}/.env" ]]; then
        source "${WORKING_DIR}/.env"
        info "Loaded environment variables from ${WORKING_DIR}/.env"
        info "  AWS Region: ${AWS_REGION:-N/A}"
        info "  Account ID: ${AWS_ACCOUNT_ID:-N/A}"
        info "  Bucket Name: ${BUCKET_NAME:-N/A}"
        success "Environment variables loaded"
    else
        warning "Environment file not found: ${WORKING_DIR}/.env"
        warning "Will attempt to find resources using AWS CLI..."
        
        # Try to get current AWS configuration
        if command_exists aws && aws configure list | grep -q "access_key"; then
            export AWS_REGION=$(aws configure get region)
            export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
            info "  AWS Region: ${AWS_REGION:-N/A}"
            info "  Account ID: ${AWS_ACCOUNT_ID:-N/A}"
        fi
    fi
}

# Find and clean up S3 resources
cleanup_s3_resources() {
    info "Cleaning up S3 resources..."
    
    if ! command_exists aws; then
        warning "AWS CLI not available, skipping S3 cleanup"
        return 0
    fi
    
    # If we have the bucket name from environment, use it
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        cleanup_specific_bucket "$BUCKET_NAME"
    else
        # Try to find tutorial buckets by pattern
        info "Searching for tutorial buckets..."
        local buckets
        if buckets=$(aws s3 ls | grep "my-first-cli-bucket-" | awk '{print $3}' 2>/dev/null); then
            if [[ -n "$buckets" ]]; then
                info "Found tutorial buckets:"
                echo "$buckets" | while read -r bucket; do
                    info "  - $bucket"
                done
                
                echo -n "Do you want to delete these buckets? (y/N): "
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    echo "$buckets" | while read -r bucket; do
                        cleanup_specific_bucket "$bucket"
                    done
                else
                    warning "Skipping S3 bucket cleanup"
                fi
            else
                info "No tutorial buckets found matching pattern 'my-first-cli-bucket-*'"
            fi
        else
            warning "Could not list S3 buckets. You may need to clean them up manually."
        fi
    fi
}

# Clean up a specific S3 bucket
cleanup_specific_bucket() {
    local bucket_name="$1"
    
    info "Cleaning up S3 bucket: $bucket_name"
    
    # Check if bucket exists
    if ! aws s3 ls "s3://$bucket_name" >/dev/null 2>&1; then
        warning "Bucket $bucket_name not found or already deleted"
        return 0
    fi
    
    # Check if bucket has objects
    local object_count
    object_count=$(aws s3 ls "s3://$bucket_name" --recursive | wc -l)
    
    if [[ "$object_count" -gt 0 ]]; then
        info "Deleting $object_count objects from bucket..."
        aws s3 rm "s3://$bucket_name" --recursive
        success "Deleted all objects from bucket: $bucket_name"
    else
        info "Bucket is already empty"
    fi
    
    # Delete the bucket
    info "Deleting bucket: $bucket_name"
    aws s3 rb "s3://$bucket_name"
    
    # Verify bucket deletion
    if aws s3 ls | grep -q "$bucket_name"; then
        error_exit "Failed to delete bucket: $bucket_name"
    else
        success "Deleted bucket: $bucket_name"
    fi
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    if [[ -d "$WORKING_DIR" ]]; then
        info "Removing working directory: $WORKING_DIR"
        
        # Show what will be deleted
        info "Files to be deleted:"
        find "$WORKING_DIR" -type f | while read -r file; do
            info "  - $file"
        done
        
        echo -n "Do you want to delete the working directory and all files? (y/N): "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -rf "$WORKING_DIR"
            success "Deleted working directory: $WORKING_DIR"
        else
            warning "Keeping working directory: $WORKING_DIR"
            info "You can manually delete it later with: rm -rf $WORKING_DIR"
        fi
    else
        info "Working directory not found: $WORKING_DIR"
    fi
}

# Clean up environment variables
cleanup_environment_variables() {
    info "Cleaning up environment variables..."
    
    # Unset variables in current session
    unset BUCKET_NAME TIMESTAMP AWS_REGION AWS_ACCOUNT_ID 2>/dev/null || true
    
    success "Environment variables cleared from current session"
}

# Show remaining resources (if any)
show_remaining_resources() {
    info "Checking for any remaining AWS resources..."
    
    if ! command_exists aws; then
        warning "AWS CLI not available, cannot check for remaining resources"
        return 0
    fi
    
    # Check for any remaining S3 buckets with tutorial pattern
    local remaining_buckets
    if remaining_buckets=$(aws s3 ls | grep "my-first-cli-bucket-" 2>/dev/null); then
        warning "Found remaining tutorial buckets:"
        echo "$remaining_buckets" | while read -r line; do
            warning "  - $line"
        done
        info "You may want to manually clean these up"
    else
        success "No remaining tutorial buckets found"
    fi
}

# Create cleanup summary
create_cleanup_summary() {
    info "Creating cleanup summary..."
    
    local summary_file="${SCRIPT_DIR}/cleanup-summary.txt"
    
    cat > "$summary_file" << EOF
AWS CLI Setup and First Commands - Cleanup Summary
=================================================

Cleanup Date: $(date)
Working Directory: ${WORKING_DIR}

Cleanup Actions Performed:
- Searched for and removed S3 buckets matching 'my-first-cli-bucket-*' pattern
- Removed working directory: ${WORKING_DIR} (if confirmed by user)
- Cleared environment variables from current session

Notes:
- AWS CLI installation was NOT removed (it can be used for other projects)
- AWS CLI configuration was NOT removed (it can be used for other projects)
- If you want to completely remove AWS CLI v2, use your system's package manager

Manual Cleanup (if needed):
- Remove AWS CLI: Follow uninstallation guide for your OS
- Remove AWS configuration: rm -rf ~/.aws/
- Check for any remaining S3 buckets: aws s3 ls

Log Files:
- Deployment log: ${SCRIPT_DIR}/deploy.log
- Cleanup log: ${SCRIPT_DIR}/destroy.log
EOF
    
    success "Cleanup summary created: $summary_file"
}

# Confirmation prompt
confirm_cleanup() {
    echo
    warning "This script will clean up resources created by the AWS CLI tutorial."
    warning "This includes:"
    warning "  - S3 buckets created during the tutorial"
    warning "  - Local files in ${WORKING_DIR}"
    warning "  - Environment variables"
    echo
    info "This will NOT remove:"
    info "  - AWS CLI installation"
    info "  - AWS CLI configuration (~/.aws/)"
    echo
    
    echo -n "Do you want to proceed with cleanup? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    info "Starting cleanup process..."
}

# Main cleanup function
main() {
    log "${BLUE}Starting AWS CLI Setup and First Commands cleanup...${NC}"
    
    # Initialize log file
    echo "AWS CLI Setup Cleanup Log - $(date)" > "${LOG_FILE}"
    
    # Confirmation before proceeding
    confirm_cleanup
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    cleanup_s3_resources
    cleanup_local_files
    cleanup_environment_variables
    show_remaining_resources
    create_cleanup_summary
    
    log "${GREEN}🧹 Cleanup completed successfully!${NC}"
    echo
    info "Summary:"
    info "- AWS resources cleaned up"
    info "- Local files removed (if confirmed)"
    info "- Environment variables cleared"
    echo
    info "AWS CLI and configuration remain available for future use"
    info "Check the cleanup summary: ${SCRIPT_DIR}/cleanup-summary.txt"
    echo
}

# Handle script interruption
interrupt_handler() {
    echo
    warning "Cleanup interrupted by user"
    info "Some resources may not have been cleaned up"
    info "You can run this script again or clean up manually"
    exit 130
}

trap interrupt_handler INT TERM

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi