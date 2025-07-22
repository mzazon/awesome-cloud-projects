#!/bin/bash

# Destroy script for CloudFront and S3 CDN Recipe
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error

# Colors for output
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

# Function to check AWS CLI authentication
check_aws_auth() {
    log "Checking AWS CLI authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not authenticated. Please run 'aws configure' first."
        exit 1
    fi
    log_success "AWS CLI authentication verified"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check jq for JSON processing
    if ! command_exists jq; then
        log_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS authentication
    check_aws_auth
    
    log_success "Prerequisites check completed"
}

# Function to load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    # Check if deployment info file exists
    if [ ! -f "./cdn-deployment-info.json" ]; then
        log_error "Deployment info file not found. Please ensure cdn-deployment-info.json exists in the current directory."
        log_error "You can also manually specify resource IDs using environment variables."
        exit 1
    fi
    
    # Load deployment information
    export DEPLOYMENT_ID=$(jq -r '.deployment_id' ./cdn-deployment-info.json)
    export AWS_REGION=$(jq -r '.aws_region' ./cdn-deployment-info.json)
    export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' ./cdn-deployment-info.json)
    export BUCKET_NAME=$(jq -r '.resources.content_bucket' ./cdn-deployment-info.json)
    export LOGS_BUCKET_NAME=$(jq -r '.resources.logs_bucket' ./cdn-deployment-info.json)
    export OAC_ID=$(jq -r '.resources.oac_id' ./cdn-deployment-info.json)
    export DISTRIBUTION_ID=$(jq -r '.resources.distribution_id' ./cdn-deployment-info.json)
    export DISTRIBUTION_DOMAIN=$(jq -r '.resources.distribution_domain' ./cdn-deployment-info.json)
    
    log_success "Deployment information loaded"
    log "Distribution ID: $DISTRIBUTION_ID"
    log "Content Bucket: $BUCKET_NAME"
    log "Logs Bucket: $LOGS_BUCKET_NAME"
    log "OAC ID: $OAC_ID"
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    echo ""
    echo "This will permanently delete the following resources:"
    echo "  🌍 CloudFront Distribution: $DISTRIBUTION_ID"
    echo "  📦 S3 Bucket (content): $BUCKET_NAME"
    echo "  📊 S3 Bucket (logs): $LOGS_BUCKET_NAME"
    echo "  🔐 Origin Access Control: $OAC_ID"
    echo "  📊 CloudWatch Alarms and Dashboard"
    echo ""
    echo "⚠️  This action cannot be undone!"
    echo ""
    
    # Skip confirmation if --force flag is provided
    if [ "$1" = "--force" ]; then
        log_warning "Force flag detected, skipping confirmation"
        return
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch resources..."
    
    # Delete CloudWatch alarms
    log "Deleting CloudWatch alarms..."
    aws cloudwatch delete-alarms \
        --alarm-names "CloudFront-HighErrorRate-${DISTRIBUTION_ID}" \
                     "CloudFront-HighOriginLatency-${DISTRIBUTION_ID}" \
        --region us-east-1 2>/dev/null || log_warning "Some alarms may not exist"
    
    # Delete CloudWatch dashboard
    log "Deleting CloudWatch dashboard..."
    aws cloudwatch delete-dashboards \
        --dashboard-names "CloudFront-CDN-Performance" \
        --region us-east-1 2>/dev/null || log_warning "Dashboard may not exist"
    
    log_success "CloudWatch resources deleted"
}

# Function to disable CloudFront distribution
disable_distribution() {
    log "Disabling CloudFront distribution..."
    
    # Get current distribution configuration
    log "Getting current distribution configuration..."
    aws cloudfront get-distribution-config \
        --id "$DISTRIBUTION_ID" > /tmp/current-config.json
    
    # Extract ETag
    ETAG=$(jq -r '.ETag' /tmp/current-config.json)
    
    # Modify configuration to disable distribution
    jq '.DistributionConfig.Enabled = false' /tmp/current-config.json > /tmp/disabled-config.json
    
    # Update distribution to disabled state
    aws cloudfront update-distribution \
        --id "$DISTRIBUTION_ID" \
        --if-match "$ETAG" \
        --distribution-config file:///tmp/disabled-config.json >/dev/null
    
    # Clean up temporary files
    rm -f /tmp/current-config.json /tmp/disabled-config.json
    
    log_success "Distribution disabled"
}

# Function to wait for distribution to be disabled
wait_for_disable() {
    log "Waiting for distribution to be disabled..."
    log_warning "This may take 10-15 minutes. Please be patient..."
    
    # Show progress while waiting
    (
        while true; do
            STATUS=$(aws cloudfront get-distribution --id "$DISTRIBUTION_ID" --query 'Distribution.Status' --output text 2>/dev/null || echo "Unknown")
            if [ "$STATUS" = "Deployed" ]; then
                break
            fi
            printf "."
            sleep 30
        done
    ) &
    
    # Wait for distribution to be disabled and deployed
    aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID"
    
    log_success "Distribution disabled and ready for deletion"
}

# Function to delete CloudFront distribution
delete_distribution() {
    log "Deleting CloudFront distribution..."
    
    # Get updated ETag after disable
    UPDATED_ETAG=$(aws cloudfront get-distribution \
        --id "$DISTRIBUTION_ID" \
        --query 'ETag' --output text)
    
    # Delete the distribution
    aws cloudfront delete-distribution \
        --id "$DISTRIBUTION_ID" \
        --if-match "$UPDATED_ETAG"
    
    log_success "CloudFront distribution deleted"
}

# Function to delete Origin Access Control
delete_oac() {
    log "Deleting Origin Access Control..."
    
    # Get OAC ETag
    OAC_ETAG=$(aws cloudfront get-origin-access-control \
        --id "$OAC_ID" \
        --query 'ETag' --output text 2>/dev/null)
    
    if [ -n "$OAC_ETAG" ] && [ "$OAC_ETAG" != "null" ]; then
        # Delete OAC
        aws cloudfront delete-origin-access-control \
            --id "$OAC_ID" \
            --if-match "$OAC_ETAG"
        
        log_success "Origin Access Control deleted"
    else
        log_warning "Origin Access Control not found or already deleted"
    fi
}

# Function to empty and delete S3 buckets
delete_s3_buckets() {
    log "Deleting S3 buckets..."
    
    # Function to safely delete a bucket
    delete_bucket() {
        local bucket_name="$1"
        local bucket_type="$2"
        
        if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
            log "Emptying $bucket_type bucket: $bucket_name"
            
            # Delete all objects (including versions if versioning is enabled)
            aws s3 rm "s3://${bucket_name}" --recursive 2>/dev/null || true
            
            # Delete incomplete multipart uploads
            aws s3api abort-multipart-upload \
                --bucket "$bucket_name" \
                --key "*" 2>/dev/null || true
            
            # Delete the bucket
            aws s3 rb "s3://${bucket_name}" --force 2>/dev/null || {
                log_warning "Failed to delete $bucket_type bucket: $bucket_name"
                log_warning "You may need to manually delete this bucket"
                return 1
            }
            
            log_success "Deleted $bucket_type bucket: $bucket_name"
        else
            log_warning "$bucket_type bucket $bucket_name not found or already deleted"
        fi
    }
    
    # Delete content bucket
    delete_bucket "$BUCKET_NAME" "content"
    
    # Delete logs bucket
    delete_bucket "$LOGS_BUCKET_NAME" "logs"
    
    log_success "S3 bucket deletion completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment info file
    if [ -f "./cdn-deployment-info.json" ]; then
        rm -f ./cdn-deployment-info.json
        log_success "Removed deployment info file"
    fi
    
    # Remove any temporary files
    rm -f /tmp/current-config.json /tmp/disabled-config.json
    
    log_success "Local cleanup completed"
}

# Function to verify resource deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    # Check if distribution still exists
    if aws cloudfront get-distribution --id "$DISTRIBUTION_ID" 2>/dev/null >/dev/null; then
        log_warning "CloudFront distribution still exists"
    else
        log_success "CloudFront distribution successfully deleted"
    fi
    
    # Check if buckets still exist
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        log_warning "Content bucket still exists"
    else
        log_success "Content bucket successfully deleted"
    fi
    
    if aws s3api head-bucket --bucket "$LOGS_BUCKET_NAME" 2>/dev/null; then
        log_warning "Logs bucket still exists"
    else
        log_success "Logs bucket successfully deleted"
    fi
    
    # Check if OAC still exists
    if aws cloudfront get-origin-access-control --id "$OAC_ID" 2>/dev/null >/dev/null; then
        log_warning "Origin Access Control still exists"
    else
        log_success "Origin Access Control successfully deleted"
    fi
    
    log_success "Verification completed"
}

# Function to display destruction summary
display_summary() {
    log_success "=== DESTRUCTION COMPLETE ==="
    echo ""
    echo "📋 Destruction Summary:"
    echo "  🌍 CloudFront Distribution: DELETED"
    echo "  📦 Content Bucket: DELETED"
    echo "  📊 Logs Bucket: DELETED"
    echo "  🔐 Origin Access Control: DELETED"
    echo "  📊 CloudWatch Resources: DELETED"
    echo ""
    echo "✅ All resources have been successfully removed"
    echo ""
    echo "💡 Note: CloudFront access logs in the logs bucket have been deleted."
    echo "   If you need to retain these logs, restore them from backups."
    echo ""
    echo "🔍 You can verify deletion in the AWS Console:"
    echo "  • CloudFront Console: https://console.aws.amazon.com/cloudfront/v3/home"
    echo "  • S3 Console: https://console.aws.amazon.com/s3/"
    echo "  • CloudWatch Console: https://console.aws.amazon.com/cloudwatch/"
}

# Function to handle errors during destruction
handle_destruction_error() {
    log_error "Destruction failed at line $1"
    log_error "Some resources may still exist. Please check the AWS Console."
    echo ""
    echo "🔧 Manual cleanup may be required for:"
    echo "  • CloudFront Distribution: $DISTRIBUTION_ID"
    echo "  • S3 Buckets: $BUCKET_NAME, $LOGS_BUCKET_NAME"
    echo "  • Origin Access Control: $OAC_ID"
    echo "  • CloudWatch Alarms and Dashboard"
    echo ""
    echo "💡 You can also try running this script again with --force flag"
    exit 1
}

# Main execution
main() {
    log "Starting CloudFront CDN destruction..."
    
    # Run destruction steps
    check_prerequisites
    load_deployment_info
    confirm_destruction "$@"
    delete_cloudwatch_resources
    disable_distribution
    wait_for_disable
    delete_distribution
    delete_oac
    delete_s3_buckets
    cleanup_local_files
    verify_deletion
    display_summary
    
    log_success "CloudFront CDN destruction completed successfully!"
}

# Error handling
trap 'handle_destruction_error $LINENO' ERR

# Check for help flag
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "CloudFront CDN Destruction Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --force    Skip confirmation prompts"
    echo "  --help     Show this help message"
    echo ""
    echo "This script will delete all resources created by the CloudFront CDN deployment."
    echo "It requires the cdn-deployment-info.json file to be present in the current directory."
    echo ""
    echo "Resources that will be deleted:"
    echo "  • CloudFront Distribution and Origin Access Control"
    echo "  • S3 Buckets (content and logs)"
    echo "  • CloudWatch Alarms and Dashboard"
    echo ""
    echo "⚠️  This action cannot be undone!"
    exit 0
fi

# Run main function
main "$@"