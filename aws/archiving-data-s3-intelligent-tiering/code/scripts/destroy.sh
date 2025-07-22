#!/bin/bash

# Cleanup script for Sustainable Data Archiving with S3 Intelligent-Tiering
# This script safely removes all resources created by the deployment script

set -e

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    print_success "Prerequisites check completed"
}

# Function to load deployment information
load_deployment_info() {
    print_status "Loading deployment information..."
    
    if [ -f "sustainable-archive-deployment.json" ]; then
        # Extract values from deployment file
        export AWS_REGION=$(jq -r '.aws_region' sustainable-archive-deployment.json)
        export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' sustainable-archive-deployment.json)
        export ARCHIVE_BUCKET=$(jq -r '.archive_bucket' sustainable-archive-deployment.json)
        export ANALYTICS_BUCKET=$(jq -r '.analytics_bucket' sustainable-archive-deployment.json)
        export LAMBDA_FUNCTION_ARN=$(jq -r '.lambda_function_arn' sustainable-archive-deployment.json)
        export LAMBDA_ROLE_ARN=$(jq -r '.lambda_role_arn' sustainable-archive-deployment.json)
        
        print_success "Deployment information loaded from sustainable-archive-deployment.json"
        echo "  AWS Region: $AWS_REGION"
        echo "  Archive Bucket: $ARCHIVE_BUCKET"
        echo "  Analytics Bucket: $ANALYTICS_BUCKET"
    else
        print_warning "Deployment file not found. Attempting to discover resources..."
        
        # Try to get current AWS region and account
        export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            print_warning "Could not determine AWS region, defaulting to us-east-1"
        fi
        
        print_status "Manual resource discovery mode enabled"
        print_warning "You may need to manually specify bucket names if auto-discovery fails"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    print_warning "=========================================="
    print_warning "  DESTRUCTIVE OPERATION WARNING"
    print_warning "=========================================="
    echo ""
    print_warning "This script will permanently delete the following resources:"
    
    if [ ! -z "$ARCHIVE_BUCKET" ]; then
        echo "  • S3 Bucket: $ARCHIVE_BUCKET (and ALL contents)"
    fi
    if [ ! -z "$ANALYTICS_BUCKET" ]; then
        echo "  • S3 Bucket: $ANALYTICS_BUCKET (and ALL contents)"
    fi
    echo "  • Lambda Function: sustainability-archive-monitor"
    echo "  • IAM Role: SustainabilityMonitorRole"
    echo "  • EventBridge Rule: sustainability-daily-check"
    echo "  • CloudWatch Dashboard: SustainableArchive"
    echo "  • S3 Storage Lens Configuration: SustainabilityMetrics"
    echo ""
    
    # Force mode check
    if [ "$1" = "--force" ]; then
        print_warning "Force mode enabled, skipping confirmation prompts"
        return 0
    fi
    
    # Interactive confirmation
    read -p "Are you sure you want to proceed? (Type 'DELETE' to confirm): " confirmation
    if [ "$confirmation" != "DELETE" ]; then
        print_status "Cleanup cancelled by user"
        exit 0
    fi
    
    # Secondary confirmation for buckets with data
    if [ ! -z "$ARCHIVE_BUCKET" ]; then
        OBJECT_COUNT=$(aws s3api list-objects-v2 --bucket $ARCHIVE_BUCKET --query 'length(Contents)' --output text 2>/dev/null || echo "0")
        if [ "$OBJECT_COUNT" != "0" ] && [ "$OBJECT_COUNT" != "None" ]; then
            echo ""
            print_warning "Archive bucket contains $OBJECT_COUNT objects that will be permanently deleted!"
            read -p "Confirm deletion of all bucket contents? (Type 'YES' to confirm): " bucket_confirmation
            if [ "$bucket_confirmation" != "YES" ]; then
                print_status "Cleanup cancelled by user"
                exit 0
            fi
        fi
    fi
    
    print_status "Proceeding with cleanup..."
}

# Function to remove EventBridge resources
cleanup_eventbridge() {
    print_status "Cleaning up EventBridge resources..."
    
    # Remove Lambda target from EventBridge rule
    if aws events describe-rule --name sustainability-daily-check &>/dev/null; then
        aws events remove-targets --rule sustainability-daily-check --ids "1" 2>/dev/null || true
        print_success "Removed Lambda target from EventBridge rule"
        
        # Delete EventBridge rule
        aws events delete-rule --name sustainability-daily-check 2>/dev/null || true
        print_success "Deleted EventBridge rule: sustainability-daily-check"
    else
        print_warning "EventBridge rule sustainability-daily-check not found"
    fi
}

# Function to remove Lambda function
cleanup_lambda() {
    print_status "Cleaning up Lambda function..."
    
    # Remove Lambda permission for EventBridge
    aws lambda remove-permission \
        --function-name sustainability-archive-monitor \
        --statement-id allow-eventbridge-daily \
        2>/dev/null || print_warning "Lambda permission already removed or doesn't exist"
    
    # Delete Lambda function
    if aws lambda get-function --function-name sustainability-archive-monitor &>/dev/null; then
        aws lambda delete-function --function-name sustainability-archive-monitor
        print_success "Deleted Lambda function: sustainability-archive-monitor"
    else
        print_warning "Lambda function sustainability-archive-monitor not found"
    fi
}

# Function to remove IAM resources
cleanup_iam() {
    print_status "Cleaning up IAM resources..."
    
    # Delete IAM role policy
    if aws iam get-role --role-name SustainabilityMonitorRole &>/dev/null; then
        aws iam delete-role-policy \
            --role-name SustainabilityMonitorRole \
            --policy-name SustainabilityPermissions \
            2>/dev/null || print_warning "IAM policy already removed"
        
        # Delete IAM role
        aws iam delete-role --role-name SustainabilityMonitorRole
        print_success "Deleted IAM role: SustainabilityMonitorRole"
    else
        print_warning "IAM role SustainabilityMonitorRole not found"
    fi
}

# Function to remove S3 Storage Lens configuration
cleanup_storage_lens() {
    print_status "Cleaning up S3 Storage Lens configuration..."
    
    # Delete Storage Lens configuration
    if aws s3control get-storage-lens-configuration \
        --account-id $AWS_ACCOUNT_ID \
        --config-id SustainabilityMetrics &>/dev/null; then
        aws s3control delete-storage-lens-configuration \
            --account-id $AWS_ACCOUNT_ID \
            --config-id SustainabilityMetrics
        print_success "Deleted S3 Storage Lens configuration: SustainabilityMetrics"
    else
        print_warning "S3 Storage Lens configuration SustainabilityMetrics not found"
    fi
}

# Function to empty and delete S3 bucket
empty_and_delete_bucket() {
    local bucket_name=$1
    local bucket_description=$2
    
    if aws s3api head-bucket --bucket $bucket_name 2>/dev/null; then
        print_status "Emptying $bucket_description: $bucket_name"
        
        # Empty the bucket (including all versions and delete markers)
        aws s3api list-object-versions --bucket $bucket_name --output json | \
        jq -r '.Versions[]?, .DeleteMarkers[]? | "\(.Key)\t\(.VersionId)"' | \
        while IFS=$'\t' read -r key version_id; do
            if [ ! -z "$key" ] && [ ! -z "$version_id" ]; then
                aws s3api delete-object --bucket $bucket_name --key "$key" --version-id "$version_id" &>/dev/null || true
            fi
        done 2>/dev/null || true
        
        # Additional cleanup using aws s3 rm for any remaining objects
        aws s3 rm s3://$bucket_name --recursive --quiet 2>/dev/null || true
        
        print_success "$bucket_description emptied"
        
        # Delete bucket
        aws s3api delete-bucket --bucket $bucket_name
        print_success "Deleted $bucket_description: $bucket_name"
    else
        print_warning "$bucket_description $bucket_name not found or already deleted"
    fi
}

# Function to remove S3 resources
cleanup_s3() {
    print_status "Cleaning up S3 resources..."
    
    # Empty and delete analytics bucket first (no versioning)
    if [ ! -z "$ANALYTICS_BUCKET" ]; then
        empty_and_delete_bucket "$ANALYTICS_BUCKET" "analytics bucket"
    fi
    
    # Empty and delete archive bucket (with versioning)
    if [ ! -z "$ARCHIVE_BUCKET" ]; then
        empty_and_delete_bucket "$ARCHIVE_BUCKET" "archive bucket"
    fi
    
    # If deployment file wasn't found, attempt to discover and clean up sustainable-archive-* buckets
    if [ -z "$ARCHIVE_BUCKET" ] || [ -z "$ANALYTICS_BUCKET" ]; then
        print_status "Attempting to discover sustainable-archive-* buckets..."
        
        # List all buckets and filter for sustainable-archive-*
        DISCOVERED_BUCKETS=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `sustainable-archive-`) || starts_with(Name, `archive-analytics-`)].Name' --output text)
        
        if [ ! -z "$DISCOVERED_BUCKETS" ]; then
            print_warning "Found potentially related buckets:"
            for bucket in $DISCOVERED_BUCKETS; do
                echo "  • $bucket"
            done
            
            if [ "$1" != "--force" ]; then
                read -p "Delete these buckets? (y/N): " delete_discovered
                if [ "$delete_discovered" = "y" ] || [ "$delete_discovered" = "Y" ]; then
                    for bucket in $DISCOVERED_BUCKETS; do
                        empty_and_delete_bucket "$bucket" "discovered bucket"
                    done
                fi
            else
                for bucket in $DISCOVERED_BUCKETS; do
                    empty_and_delete_bucket "$bucket" "discovered bucket"
                done
            fi
        else
            print_status "No sustainable-archive-* buckets found"
        fi
    fi
}

# Function to remove CloudWatch resources
cleanup_cloudwatch() {
    print_status "Cleaning up CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name "SustainableArchive" &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "SustainableArchive"
        print_success "Deleted CloudWatch dashboard: SustainableArchive"
    else
        print_warning "CloudWatch dashboard SustainableArchive not found"
    fi
    
    # Note: CloudWatch metrics data will naturally expire, no need to delete manually
    print_status "CloudWatch metrics in namespace 'SustainableArchive' will expire naturally"
}

# Function to clean up local files
cleanup_local_files() {
    print_status "Cleaning up local files..."
    
    # Remove deployment information file
    if [ -f "sustainable-archive-deployment.json" ]; then
        rm -f sustainable-archive-deployment.json
        print_success "Removed local deployment file"
    fi
    
    # Remove any temporary files that might be left over
    rm -f /tmp/lifecycle-policy.json /tmp/storage-lens-config.json /tmp/lambda-trust-policy.json
    rm -f /tmp/lambda-permissions.json /tmp/dashboard-config.json /tmp/sustainability-monitor.zip
    rm -f /tmp/sustainability_monitor.py /tmp/sustainability-response.json
    rm -rf /tmp/test-data
    
    print_success "Cleaned up temporary files"
}

# Function to verify cleanup completion
verify_cleanup() {
    print_status "Verifying cleanup completion..."
    
    local issues_found=0
    
    # Check if buckets still exist
    if [ ! -z "$ARCHIVE_BUCKET" ] && aws s3api head-bucket --bucket $ARCHIVE_BUCKET 2>/dev/null; then
        print_error "Archive bucket $ARCHIVE_BUCKET still exists"
        issues_found=1
    fi
    
    if [ ! -z "$ANALYTICS_BUCKET" ] && aws s3api head-bucket --bucket $ANALYTICS_BUCKET 2>/dev/null; then
        print_error "Analytics bucket $ANALYTICS_BUCKET still exists"
        issues_found=1
    fi
    
    # Check if Lambda function still exists
    if aws lambda get-function --function-name sustainability-archive-monitor &>/dev/null; then
        print_error "Lambda function sustainability-archive-monitor still exists"
        issues_found=1
    fi
    
    # Check if IAM role still exists
    if aws iam get-role --role-name SustainabilityMonitorRole &>/dev/null; then
        print_error "IAM role SustainabilityMonitorRole still exists"
        issues_found=1
    fi
    
    # Check if EventBridge rule still exists
    if aws events describe-rule --name sustainability-daily-check &>/dev/null; then
        print_error "EventBridge rule sustainability-daily-check still exists"
        issues_found=1
    fi
    
    if [ $issues_found -eq 0 ]; then
        print_success "All resources successfully cleaned up"
        return 0
    else
        print_warning "Some resources may still exist. Manual cleanup may be required."
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    print_success "=========================================="
    print_success "  Cleanup Summary"
    print_success "=========================================="
    echo ""
    
    echo "The following resources have been removed:"
    echo "  ✓ S3 Buckets and all contents"
    echo "  ✓ Lambda Function: sustainability-archive-monitor"
    echo "  ✓ IAM Role: SustainabilityMonitorRole"
    echo "  ✓ EventBridge Rule: sustainability-daily-check"
    echo "  ✓ CloudWatch Dashboard: SustainableArchive"
    echo "  ✓ S3 Storage Lens Configuration"
    echo "  ✓ Local deployment files"
    echo ""
    
    print_status "Notes:"
    echo "  • CloudWatch metrics data will expire naturally"
    echo "  • CloudWatch logs will be retained based on log group retention settings"
    echo "  • Any data uploaded to the buckets has been permanently deleted"
    echo ""
    
    print_warning "If you need to re-deploy the solution, run the deploy.sh script again."
}

# Function to handle manual resource cleanup
manual_cleanup_mode() {
    print_status "Manual cleanup mode"
    echo ""
    print_status "Please provide the resource names to clean up:"
    
    read -p "Archive bucket name (press Enter to skip): " manual_archive_bucket
    read -p "Analytics bucket name (press Enter to skip): " manual_analytics_bucket
    
    if [ ! -z "$manual_archive_bucket" ]; then
        export ARCHIVE_BUCKET="$manual_archive_bucket"
    fi
    
    if [ ! -z "$manual_analytics_bucket" ]; then
        export ANALYTICS_BUCKET="$manual_analytics_bucket"
    fi
}

# Main cleanup function
main() {
    echo "=========================================="
    echo "  Sustainable Data Archiving Cleanup"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    load_deployment_info
    
    # If no deployment info found and no manual input, offer manual mode
    if [ -z "$ARCHIVE_BUCKET" ] && [ -z "$ANALYTICS_BUCKET" ] && [ "$1" != "--force" ]; then
        manual_cleanup_mode
    fi
    
    confirm_deletion "$1"
    
    echo ""
    print_status "Starting cleanup process..."
    echo ""
    
    # Cleanup in reverse order of creation
    cleanup_eventbridge
    cleanup_lambda
    cleanup_iam
    cleanup_storage_lens
    cleanup_s3 "$1"
    cleanup_cloudwatch
    cleanup_local_files
    
    echo ""
    if verify_cleanup; then
        display_cleanup_summary
    else
        print_warning "Cleanup completed with some issues. Please review the output above."
    fi
}

# Print usage information
print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force    Skip confirmation prompts and automatically clean up discovered resources"
    echo "  --help     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                 # Interactive cleanup with confirmations"
    echo "  $0 --force         # Automated cleanup without confirmations"
    echo ""
}

# Handle command line arguments
case "$1" in
    --help)
        print_usage
        exit 0
        ;;
    *)
        # Error handling
        trap 'print_error "Cleanup failed. Check the output above for details."; exit 1' ERR
        
        # Run main cleanup
        main "$@"
        ;;
esac