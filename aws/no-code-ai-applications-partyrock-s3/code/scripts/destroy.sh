#!/bin/bash

# AWS PartyRock and S3 Infrastructure Cleanup Script
# This script safely removes all AWS resources created by the deploy.sh script
# including S3 buckets, CloudFront distributions, and associated configurations

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Color codes for output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    log_info "Checking AWS CLI configuration..."
    
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install AWS CLI version 2.0 or later."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set AWS environment variables."
        exit 1
    fi
    
    # Get AWS account info
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region not configured. Please set a default region with 'aws configure' or export AWS_DEFAULT_REGION."
        exit 1
    fi
    
    log_success "AWS CLI configured. Account: $AWS_ACCOUNT_ID, Region: $AWS_REGION"
}

# Function to load deployment info
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [ -f "deployment-info.txt" ]; then
        # Source the deployment info file
        source deployment-info.txt
        log_success "Loaded deployment info from deployment-info.txt"
        log_info "  Distribution ID: ${DISTRIBUTION_ID:-Not found}"
        log_info "  Bucket Name: ${BUCKET_NAME:-Not found}"
        log_info "  CloudFront Domain: ${CLOUDFRONT_DOMAIN:-Not found}"
    else
        log_warning "deployment-info.txt not found. Will attempt to discover resources..."
        DISTRIBUTION_ID=""
        BUCKET_NAME=""
        CLOUDFRONT_DOMAIN=""
    fi
}

# Function to discover resources if deployment-info.txt is missing
discover_resources() {
    if [ -z "${BUCKET_NAME:-}" ]; then
        log_info "Discovering S3 buckets with partyrock-app prefix..."
        
        # List buckets and find those with partyrock-app prefix
        BUCKETS=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `partyrock-app-`)].Name' --output text)
        
        if [ -n "$BUCKETS" ]; then
            log_info "Found potential buckets:"
            for bucket in $BUCKETS; do
                log_info "  - $bucket"
            done
            
            # If only one bucket found, use it
            BUCKET_COUNT=$(echo "$BUCKETS" | wc -w)
            if [ "$BUCKET_COUNT" -eq 1 ]; then
                BUCKET_NAME="$BUCKETS"
                log_info "Using bucket: $BUCKET_NAME"
            else
                log_warning "Multiple buckets found. Please specify which one to delete."
                log_info "Usage: $0 --bucket-name <bucket-name>"
                return 1
            fi
        else
            log_warning "No partyrock-app buckets found"
        fi
    fi
    
    if [ -z "${DISTRIBUTION_ID:-}" ] && [ -n "${BUCKET_NAME:-}" ]; then
        log_info "Discovering CloudFront distributions for bucket: $BUCKET_NAME..."
        
        # Find CloudFront distributions that use this S3 bucket as origin
        DISTRIBUTIONS=$(aws cloudfront list-distributions --query "DistributionList.Items[?Origins.Items[?DomainName=='$BUCKET_NAME.s3.$AWS_REGION.amazonaws.com']].Id" --output text)
        
        if [ -n "$DISTRIBUTIONS" ]; then
            DISTRIBUTION_ID="$DISTRIBUTIONS"
            log_info "Found CloudFront distribution: $DISTRIBUTION_ID"
        else
            log_warning "No CloudFront distribution found for bucket: $BUCKET_NAME"
        fi
    fi
}

# Function to prompt for confirmation
confirm_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [ "${FORCE_DELETE:-false}" = "true" ]; then
        return 0
    fi
    
    echo
    log_warning "You are about to delete the following $resource_type:"
    log_warning "  $resource_name"
    echo
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    case $confirm in
        [Yy][Ee][Ss])
            return 0
            ;;
        *)
            log_info "Deletion cancelled by user"
            return 1
            ;;
    esac
}

# Function to disable and delete CloudFront distribution
delete_cloudfront_distribution() {
    if [ -z "${DISTRIBUTION_ID:-}" ]; then
        log_info "No CloudFront distribution to delete"
        return 0
    fi
    
    log_info "Processing CloudFront distribution: $DISTRIBUTION_ID"
    
    # Check if distribution exists
    if ! aws cloudfront get-distribution --id "$DISTRIBUTION_ID" >/dev/null 2>&1; then
        log_warning "CloudFront distribution $DISTRIBUTION_ID not found or already deleted"
        return 0
    fi
    
    # Get current distribution status
    STATUS=$(aws cloudfront get-distribution --id "$DISTRIBUTION_ID" --query 'Distribution.Status' --output text)
    ENABLED=$(aws cloudfront get-distribution --id "$DISTRIBUTION_ID" --query 'Distribution.DistributionConfig.Enabled' --output text)
    
    log_info "Distribution status: $STATUS, Enabled: $ENABLED"
    
    if [ "$ENABLED" = "true" ]; then
        log_info "Disabling CloudFront distribution..."
        
        # Get distribution configuration
        aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" > dist-config-full.json
        
        # Extract the configuration and ETag
        jq '.DistributionConfig' dist-config-full.json > dist-config.json
        ETAG=$(jq -r '.ETag' dist-config-full.json)
        
        # Set enabled to false
        jq '.Enabled = false' dist-config.json > dist-config-updated.json
        
        # Update distribution
        aws cloudfront update-distribution \
            --id "$DISTRIBUTION_ID" \
            --distribution-config file://dist-config-updated.json \
            --if-match "$ETAG" >/dev/null
        
        log_success "CloudFront distribution disabled"
        
        # Wait for deployment to complete
        log_info "Waiting for distribution to be disabled (this may take several minutes)..."
        aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID"
        log_success "Distribution successfully disabled"
        
        # Clean up temp files
        rm -f dist-config-full.json dist-config.json dist-config-updated.json
    fi
    
    # Confirm deletion
    if ! confirm_deletion "CloudFront distribution" "$DISTRIBUTION_ID"; then
        log_info "Skipping CloudFront distribution deletion"
        return 0
    fi
    
    # Get new ETag after disable operation
    ETAG=$(aws cloudfront get-distribution --id "$DISTRIBUTION_ID" --query 'ETag' --output text)
    
    # Delete distribution
    log_info "Deleting CloudFront distribution..."
    aws cloudfront delete-distribution --id "$DISTRIBUTION_ID" --if-match "$ETAG"
    
    log_success "CloudFront distribution deletion initiated: $DISTRIBUTION_ID"
}

# Function to empty and delete S3 bucket
delete_s3_bucket() {
    if [ -z "${BUCKET_NAME:-}" ]; then
        log_info "No S3 bucket to delete"
        return 0
    fi
    
    log_info "Processing S3 bucket: $BUCKET_NAME"
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        log_warning "S3 bucket $BUCKET_NAME not found or already deleted"
        return 0
    fi
    
    # Confirm deletion
    if ! confirm_deletion "S3 bucket and all its contents" "$BUCKET_NAME"; then
        log_info "Skipping S3 bucket deletion"
        return 0
    fi
    
    # Remove all objects and versions from bucket
    log_info "Removing all objects from bucket..."
    
    # Delete all object versions and delete markers
    aws s3api list-object-versions --bucket "$BUCKET_NAME" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output json > versions.json 2>/dev/null || echo "[]" > versions.json
    aws s3api list-object-versions --bucket "$BUCKET_NAME" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output json > delete-markers.json 2>/dev/null || echo "[]" > delete-markers.json
    
    # Delete all versions
    if [ -s versions.json ] && [ "$(cat versions.json)" != "[]" ]; then
        log_info "Deleting object versions..."
        aws s3api delete-objects --bucket "$BUCKET_NAME" --delete "Objects=$(cat versions.json),Quiet=true" >/dev/null
    fi
    
    # Delete all delete markers
    if [ -s delete-markers.json ] && [ "$(cat delete-markers.json)" != "[]" ]; then
        log_info "Deleting delete markers..."
        aws s3api delete-objects --bucket "$BUCKET_NAME" --delete "Objects=$(cat delete-markers.json),Quiet=true" >/dev/null
    fi
    
    # Remove any remaining objects (fallback)
    aws s3 rm s3://"$BUCKET_NAME" --recursive >/dev/null 2>&1 || true
    
    # Clean up temp files
    rm -f versions.json delete-markers.json
    
    # Delete bucket policy if it exists
    log_info "Removing bucket policy..."
    aws s3api delete-bucket-policy --bucket "$BUCKET_NAME" 2>/dev/null || true
    
    # Delete bucket
    log_info "Deleting S3 bucket..."
    aws s3 rb s3://"$BUCKET_NAME" --force
    
    log_success "S3 bucket deleted: $BUCKET_NAME"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-info.txt"
        "bucket-policy.json"
        "cloudfront-config.json"
        "dist-config.json"
        "dist-config-updated.json"
        "dist-config-full.json"
        "versions.json"
        "delete-markers.json"
        "index.html"
        "error.html"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_info "Removed: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local all_deleted=true
    
    # Check CloudFront distribution
    if [ -n "${DISTRIBUTION_ID:-}" ]; then
        if aws cloudfront get-distribution --id "$DISTRIBUTION_ID" >/dev/null 2>&1; then
            log_warning "CloudFront distribution $DISTRIBUTION_ID still exists"
            all_deleted=false
        else
            log_success "CloudFront distribution $DISTRIBUTION_ID successfully deleted"
        fi
    fi
    
    # Check S3 bucket
    if [ -n "${BUCKET_NAME:-}" ]; then
        if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
            log_warning "S3 bucket $BUCKET_NAME still exists"
            all_deleted=false
        else
            log_success "S3 bucket $BUCKET_NAME successfully deleted"
        fi
    fi
    
    if [ "$all_deleted" = true ]; then
        log_success "All resources successfully deleted"
    else
        log_warning "Some resources may still exist. Check AWS console for manual cleanup."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo
    log_success "Cleanup operation completed!"
    echo
    log_info "=== Cleanup Summary ==="
    [ -n "${DISTRIBUTION_ID:-}" ] && log_info "CloudFront Distribution: ${DISTRIBUTION_ID} - Processed"
    [ -n "${BUCKET_NAME:-}" ] && log_info "S3 Bucket: ${BUCKET_NAME} - Processed"
    log_info "Local files: Cleaned up"
    echo
    log_info "=== Cost Impact ==="
    log_info "- S3 storage charges will stop immediately"
    log_info "- CloudFront data transfer charges will stop after distribution deletion"
    log_info "- No additional charges should be incurred after cleanup"
    echo
    log_warning "Note: It may take a few minutes for AWS console to reflect all changes"
}

# Function to list resources without deleting (dry run)
dry_run() {
    log_info "DRY RUN MODE - Resources that would be deleted:"
    echo
    
    load_deployment_info
    discover_resources
    
    if [ -n "${DISTRIBUTION_ID:-}" ]; then
        log_info "CloudFront Distribution:"
        log_info "  - ID: $DISTRIBUTION_ID"
        if [ -n "${CLOUDFRONT_DOMAIN:-}" ]; then
            log_info "  - Domain: $CLOUDFRONT_DOMAIN"
        fi
    else
        log_info "CloudFront Distribution: None found"
    fi
    
    if [ -n "${BUCKET_NAME:-}" ]; then
        log_info "S3 Bucket:"
        log_info "  - Name: $BUCKET_NAME"
        log_info "  - All objects and versions would be deleted"
    else
        log_info "S3 Bucket: None found"
    fi
    
    local files_to_remove=(
        "deployment-info.txt"
        "bucket-policy.json"
        "cloudfront-config.json"
        "index.html"
        "error.html"
    )
    
    log_info "Local files that would be removed:"
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            log_info "  - $file"
        fi
    done
    
    echo
    log_info "Run without --dry-run to actually delete these resources."
}

# Main cleanup function
main() {
    log_info "Starting AWS PartyRock and S3 infrastructure cleanup..."
    echo
    
    # Load deployment information
    load_deployment_info
    
    # Try to discover resources if not loaded
    if [ -z "${BUCKET_NAME:-}" ] && [ -z "${DISTRIBUTION_ID:-}" ]; then
        discover_resources
    fi
    
    # Check if any resources found
    if [ -z "${BUCKET_NAME:-}" ] && [ -z "${DISTRIBUTION_ID:-}" ]; then
        log_warning "No resources found to delete. Either they were already deleted or deployment-info.txt is missing."
        log_info "If you have resources to delete, use --bucket-name parameter or ensure deployment-info.txt exists."
        exit 0
    fi
    
    # Perform cleanup
    delete_cloudfront_distribution
    delete_s3_bucket
    cleanup_local_files
    verify_deletion
    display_cleanup_summary
    
    log_success "Cleanup script completed successfully!"
}

# Handle script interruption
trap 'log_error "Cleanup interrupted. Some resources may not have been deleted. Re-run the script to continue cleanup."; exit 1' INT TERM

# Parse command line arguments
FORCE_DELETE=false
DRY_RUN=false
SPECIFIC_BUCKET=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --bucket-name)
            SPECIFIC_BUCKET="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force              Delete resources without confirmation prompts"
            echo "  --dry-run           Show what would be deleted without actually deleting"
            echo "  --bucket-name NAME  Specify specific bucket name to delete"
            echo "  --help              Show this help message"
            echo
            echo "Examples:"
            echo "  $0                           # Interactive cleanup using deployment-info.txt"
            echo "  $0 --force                   # Delete all resources without confirmation"
            echo "  $0 --dry-run                 # Show what would be deleted"
            echo "  $0 --bucket-name my-bucket   # Delete specific bucket and related resources"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            log_info "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Override bucket name if specified
if [ -n "$SPECIFIC_BUCKET" ]; then
    BUCKET_NAME="$SPECIFIC_BUCKET"
fi

# Check AWS configuration first
check_aws_config

# Execute main function or dry run
if [ "$DRY_RUN" = "true" ]; then
    dry_run
else
    main
fi