#!/bin/bash

# Destroy script for Secure Content Delivery with CloudFront WAF
# This script safely removes all resources created by the deploy script

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured or invalid."
        exit 1
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to find environment file in different locations
    local env_file=""
    
    if [ -f "cloudfront-waf-deploy/environment.sh" ]; then
        env_file="cloudfront-waf-deploy/environment.sh"
    elif [ -f "environment.sh" ]; then
        env_file="environment.sh"
    elif [ -f "../environment.sh" ]; then
        env_file="../environment.sh"
    fi
    
    if [ -n "$env_file" ] && [ -f "$env_file" ]; then
        log "Loading environment from: $env_file"
        source "$env_file"
        success "Environment variables loaded successfully"
    else
        warning "Environment file not found. You may need to provide resource names manually."
        
        # Prompt for essential information
        read -p "Enter S3 bucket name (or press Enter to skip): " BUCKET_NAME
        read -p "Enter WAF Web ACL name (or press Enter to skip): " WAF_WEB_ACL_NAME
        read -p "Enter CloudFront Distribution ID (or press Enter to skip): " DISTRIBUTION_ID
        read -p "Enter Origin Access Control ID (or press Enter to skip): " OAC_ID
        
        # Set defaults for AWS region and account
        export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        export AWS_REGION=${AWS_REGION:-"us-east-1"}
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        export WORK_DIR=${WORK_DIR:-"$(pwd)/cloudfront-waf-cleanup"}
        mkdir -p "$WORK_DIR"
    fi
    
    log "Current configuration:"
    log "  AWS_REGION: ${AWS_REGION:-'Not set'}"
    log "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID:-'Not set'}"
    log "  BUCKET_NAME: ${BUCKET_NAME:-'Not set'}"
    log "  WAF_WEB_ACL_NAME: ${WAF_WEB_ACL_NAME:-'Not set'}"
    log "  DISTRIBUTION_ID: ${DISTRIBUTION_ID:-'Not set'}"
    log "  OAC_ID: ${OAC_ID:-'Not set'}"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo ""
    [ -n "${BUCKET_NAME:-}" ] && echo "   🗑️  S3 Bucket: $BUCKET_NAME (and all contents)"
    [ -n "${WAF_WEB_ACL_NAME:-}" ] && echo "   🗑️  WAF Web ACL: $WAF_WEB_ACL_NAME"
    [ -n "${DISTRIBUTION_ID:-}" ] && echo "   🗑️  CloudFront Distribution: $DISTRIBUTION_ID"
    [ -n "${OAC_ID:-}" ] && echo "   🗑️  Origin Access Control: $OAC_ID"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    success "Destruction confirmed. Proceeding with cleanup..."
}

# Function to disable and delete CloudFront distribution
remove_cloudfront_distribution() {
    if [ -z "${DISTRIBUTION_ID:-}" ]; then
        warning "CloudFront Distribution ID not provided, skipping CloudFront cleanup"
        return 0
    fi
    
    log "Removing CloudFront distribution: $DISTRIBUTION_ID"
    
    # Check if distribution exists
    if ! aws cloudfront get-distribution --id "$DISTRIBUTION_ID" &>/dev/null; then
        warning "CloudFront distribution $DISTRIBUTION_ID not found, may already be deleted"
        return 0
    fi
    
    # Get current distribution status
    local status=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query "Distribution.Status" --output text)
    
    log "Current distribution status: $status"
    
    # If distribution is enabled, disable it first
    if aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" \
        --query "DistributionConfig.Enabled" --output text | grep -q "True"; then
        
        log "Disabling CloudFront distribution..."
        
        # Get current configuration
        aws cloudfront get-distribution-config \
            --id "$DISTRIBUTION_ID" \
            --query "DistributionConfig" > "$WORK_DIR/current-distribution-config.json"
        
        # Update configuration to disable
        jq '.Enabled = false' "$WORK_DIR/current-distribution-config.json" > "$WORK_DIR/disabled-distribution-config.json"
        
        # Get current ETag
        local etag=$(aws cloudfront get-distribution-config \
            --id "$DISTRIBUTION_ID" \
            --query "ETag" --output text)
        
        # Update distribution to disable it
        aws cloudfront update-distribution \
            --id "$DISTRIBUTION_ID" \
            --distribution-config file://"$WORK_DIR/disabled-distribution-config.json" \
            --if-match "$etag"
        
        success "Distribution disabled, waiting for deployment..."
        
        # Wait for distribution to be disabled and deployed
        local timeout=1800  # 30 minutes
        local elapsed=0
        local interval=30   # Check every 30 seconds
        
        while [ $elapsed -lt $timeout ]; do
            local current_status=$(aws cloudfront get-distribution \
                --id "$DISTRIBUTION_ID" \
                --query "Distribution.Status" --output text)
            
            if [ "$current_status" = "Deployed" ]; then
                success "Distribution is now disabled and deployed"
                break
            fi
            
            log "Waiting for distribution to be deployed (status: $current_status, waited ${elapsed}s/${timeout}s)"
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        if [ $elapsed -ge $timeout ]; then
            error "Timeout waiting for distribution to be deployed. Please check AWS console and try again later."
            return 1
        fi
    fi
    
    # Delete the distribution
    log "Deleting CloudFront distribution..."
    local final_etag=$(aws cloudfront get-distribution-config \
        --id "$DISTRIBUTION_ID" \
        --query "ETag" --output text)
    
    aws cloudfront delete-distribution \
        --id "$DISTRIBUTION_ID" \
        --if-match "$final_etag"
    
    success "CloudFront distribution $DISTRIBUTION_ID deleted successfully"
}

# Function to remove Origin Access Control
remove_origin_access_control() {
    if [ -z "${OAC_ID:-}" ]; then
        warning "Origin Access Control ID not provided, skipping OAC cleanup"
        return 0
    fi
    
    log "Removing Origin Access Control: $OAC_ID"
    
    # Check if OAC exists
    if ! aws cloudfront get-origin-access-control --id "$OAC_ID" &>/dev/null; then
        warning "Origin Access Control $OAC_ID not found, may already be deleted"
        return 0
    fi
    
    # Get ETag for deletion
    local etag=$(aws cloudfront get-origin-access-control \
        --id "$OAC_ID" \
        --query "ETag" --output text)
    
    # Delete Origin Access Control
    aws cloudfront delete-origin-access-control \
        --id "$OAC_ID" \
        --if-match "$etag"
    
    success "Origin Access Control $OAC_ID deleted successfully"
}

# Function to remove WAF Web ACL
remove_waf_web_acl() {
    if [ -z "${WAF_WEB_ACL_NAME:-}" ]; then
        warning "WAF Web ACL name not provided, skipping WAF cleanup"
        return 0
    fi
    
    log "Removing WAF Web ACL: $WAF_WEB_ACL_NAME"
    
    # Get WAF Web ACL ID
    local web_acl_id=$(aws wafv2 list-web-acls \
        --scope CLOUDFRONT \
        --region us-east-1 \
        --query "WebACLs[?Name=='$WAF_WEB_ACL_NAME'].Id" \
        --output text)
    
    if [ -z "$web_acl_id" ]; then
        warning "WAF Web ACL $WAF_WEB_ACL_NAME not found, may already be deleted"
        return 0
    fi
    
    # Get lock token for deletion
    local lock_token=$(aws wafv2 get-web-acl \
        --scope CLOUDFRONT \
        --region us-east-1 \
        --id "$web_acl_id" \
        --query "LockToken" --output text)
    
    # Delete WAF Web ACL
    aws wafv2 delete-web-acl \
        --scope CLOUDFRONT \
        --region us-east-1 \
        --id "$web_acl_id" \
        --lock-token "$lock_token"
    
    success "WAF Web ACL $WAF_WEB_ACL_NAME deleted successfully"
}

# Function to remove S3 bucket and contents
remove_s3_bucket() {
    if [ -z "${BUCKET_NAME:-}" ]; then
        warning "S3 bucket name not provided, skipping S3 cleanup"
        return 0
    fi
    
    log "Removing S3 bucket and contents: $BUCKET_NAME"
    
    # Check if bucket exists
    if ! aws s3 ls "s3://$BUCKET_NAME" &>/dev/null; then
        warning "S3 bucket $BUCKET_NAME not found, may already be deleted"
        return 0
    fi
    
    # Remove all objects from bucket (including versioned objects)
    log "Deleting all objects from bucket..."
    aws s3 rm "s3://$BUCKET_NAME" --recursive
    
    # Check for versioned objects and delete them
    local versions=$(aws s3api list-object-versions \
        --bucket "$BUCKET_NAME" \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$versions" ]; then
        log "Deleting versioned objects..."
        echo "$versions" | while read key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id"
            fi
        done
    fi
    
    # Check for delete markers and remove them
    local delete_markers=$(aws s3api list-object-versions \
        --bucket "$BUCKET_NAME" \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$delete_markers" ]; then
        log "Deleting delete markers..."
        echo "$delete_markers" | while read key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id"
            fi
        done
    fi
    
    # Delete the bucket
    aws s3 rb "s3://$BUCKET_NAME"
    
    success "S3 bucket $BUCKET_NAME deleted successfully"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local temporary files..."
    
    # Remove working directory if it exists
    if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
        success "Temporary files cleaned up: $WORK_DIR"
    fi
    
    # Remove other potential temporary files
    local temp_files=("*.json" "*.txt" "*.html" "environment.sh")
    for pattern in "${temp_files[@]}"; do
        if ls $pattern 1> /dev/null 2>&1; then
            rm -f $pattern
            log "Removed temporary files matching: $pattern"
        fi
    done
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check S3 bucket
    if [ -n "${BUCKET_NAME:-}" ]; then
        if aws s3 ls "s3://$BUCKET_NAME" &>/dev/null; then
            error "S3 bucket $BUCKET_NAME still exists"
            cleanup_issues=$((cleanup_issues + 1))
        else
            success "S3 bucket cleanup verified"
        fi
    fi
    
    # Check WAF Web ACL
    if [ -n "${WAF_WEB_ACL_NAME:-}" ]; then
        local web_acl_count=$(aws wafv2 list-web-acls \
            --scope CLOUDFRONT \
            --region us-east-1 \
            --query "WebACLs[?Name=='$WAF_WEB_ACL_NAME']" \
            --output text | wc -l)
        
        if [ "$web_acl_count" -gt 0 ]; then
            error "WAF Web ACL $WAF_WEB_ACL_NAME still exists"
            cleanup_issues=$((cleanup_issues + 1))
        else
            success "WAF Web ACL cleanup verified"
        fi
    fi
    
    # Check CloudFront distribution
    if [ -n "${DISTRIBUTION_ID:-}" ]; then
        if aws cloudfront get-distribution --id "$DISTRIBUTION_ID" &>/dev/null; then
            error "CloudFront distribution $DISTRIBUTION_ID still exists"
            cleanup_issues=$((cleanup_issues + 1))
        else
            success "CloudFront distribution cleanup verified"
        fi
    fi
    
    # Check Origin Access Control
    if [ -n "${OAC_ID:-}" ]; then
        if aws cloudfront get-origin-access-control --id "$OAC_ID" &>/dev/null; then
            error "Origin Access Control $OAC_ID still exists"
            cleanup_issues=$((cleanup_issues + 1))
        else
            success "Origin Access Control cleanup verified"
        fi
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        success "All resources have been successfully cleaned up"
    else
        warning "$cleanup_issues cleanup issues detected. Some resources may still exist."
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "================"
    echo ""
    echo "🗑️  Resources Removed:"
    [ -n "${BUCKET_NAME:-}" ] && echo "   ✅ S3 Bucket: $BUCKET_NAME"
    [ -n "${WAF_WEB_ACL_NAME:-}" ] && echo "   ✅ WAF Web ACL: $WAF_WEB_ACL_NAME"
    [ -n "${DISTRIBUTION_ID:-}" ] && echo "   ✅ CloudFront Distribution: $DISTRIBUTION_ID"
    [ -n "${OAC_ID:-}" ] && echo "   ✅ Origin Access Control: $OAC_ID"
    echo "   ✅ Temporary files and directories"
    echo ""
    echo "💰 Cost Impact:"
    echo "   - All AWS resources have been removed"
    echo "   - No further charges will be incurred for these resources"
    echo "   - Final charges may appear on your next bill for usage up to deletion time"
    echo ""
    echo "🔍 Verification:"
    echo "   - Check your AWS console to confirm resource deletion"
    echo "   - Monitor your next AWS bill to ensure charges have stopped"
    echo ""
    success "Cleanup completed successfully!"
}

# Function to handle cleanup errors
cleanup_error_handler() {
    local exit_code=$?
    error "Cleanup process encountered an error (exit code: $exit_code)"
    echo ""
    echo "⚠️  Some resources may not have been deleted completely."
    echo "Please check your AWS console and delete any remaining resources manually:"
    echo ""
    echo "1. CloudFront Console: https://console.aws.amazon.com/cloudfront/"
    echo "2. WAF Console: https://console.aws.amazon.com/wafv2/"
    echo "3. S3 Console: https://console.aws.amazon.com/s3/"
    echo ""
    echo "This will help avoid unexpected charges."
    exit $exit_code
}

# Main cleanup function
main() {
    echo "=============================================="
    echo "🗑️  AWS CloudFront + WAF Cleanup Script"
    echo "=============================================="
    echo ""
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    echo ""
    log "Starting cleanup process..."
    
    # Remove resources in reverse order of creation
    # CloudFront must be removed before WAF (due to association)
    remove_cloudfront_distribution
    remove_origin_access_control
    remove_waf_web_acl
    remove_s3_bucket
    cleanup_local_files
    
    echo ""
    verify_cleanup
    display_summary
}

# Set up error handling
trap cleanup_error_handler ERR

# Run main function
main "$@"