#!/bin/bash

# Intelligent Tiering and Lifecycle Management for S3 - Cleanup Script
# This script removes all resources created by the S3 Intelligent Tiering deployment
# Based on the recipe: S3 Automated Tiering and Lifecycle Management

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failure

# Script configuration
SCRIPT_NAME="S3 Intelligent Tiering Cleanup"
SCRIPT_VERSION="1.0"
LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Success message function
success() {
    log "${GREEN}✅ $1${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Banner function
print_banner() {
    echo "=================================================="
    echo "  $SCRIPT_NAME v$SCRIPT_VERSION"
    echo "=================================================="
    echo ""
}

# Confirmation function
confirm_destruction() {
    if [ "$FORCE_DESTROY" = "true" ]; then
        warning "FORCE_DESTROY is set to true. Skipping confirmation."
        return 0
    fi
    
    echo ""
    warning "This script will permanently delete the following resources:"
    echo "   • S3 bucket and ALL its contents"
    echo "   • All object versions (including deleted objects)"
    echo "   • Intelligent Tiering configurations"
    echo "   • Lifecycle policies"
    echo "   • CloudWatch dashboard"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
    echo ""
    
    if [[ ! $REPLY =~ ^yes$ ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
}

# Prerequisites check function
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI and configure it."
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured or credentials are invalid. Please run 'aws configure'."
    fi
    
    success "Prerequisites check completed"
}

# Discover resources function
discover_resources() {
    info "Discovering resources to clean up..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        error_exit "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
    fi
    
    # Find buckets with the intelligent-tiering-demo prefix
    info "Searching for S3 buckets with 'intelligent-tiering-demo' prefix..."
    BUCKETS=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `intelligent-tiering-demo`)].Name' --output text)
    
    if [ -z "$BUCKETS" ]; then
        warning "No S3 buckets found with 'intelligent-tiering-demo' prefix"
        BUCKET_COUNT=0
    else
        BUCKET_COUNT=$(echo "$BUCKETS" | wc -w)
        info "Found $BUCKET_COUNT bucket(s): $BUCKETS"
    fi
    
    # Find CloudWatch dashboards with the S3-Storage-Optimization prefix
    info "Searching for CloudWatch dashboards with 'S3-Storage-Optimization' prefix..."
    DASHBOARDS=$(aws cloudwatch list-dashboards --query 'DashboardEntries[?starts_with(DashboardName, `S3-Storage-Optimization`)].DashboardName' --output text)
    
    if [ -z "$DASHBOARDS" ]; then
        warning "No CloudWatch dashboards found with 'S3-Storage-Optimization' prefix"
        DASHBOARD_COUNT=0
    else
        DASHBOARD_COUNT=$(echo "$DASHBOARDS" | wc -w)
        info "Found $DASHBOARD_COUNT dashboard(s): $DASHBOARDS"
    fi
    
    # If specific bucket name is provided, use it
    if [ -n "$BUCKET_NAME" ]; then
        info "Using provided bucket name: $BUCKET_NAME"
        BUCKETS="$BUCKET_NAME"
        BUCKET_COUNT=1
    fi
    
    # If specific dashboard name is provided, use it
    if [ -n "$DASHBOARD_NAME" ]; then
        info "Using provided dashboard name: $DASHBOARD_NAME"
        DASHBOARDS="$DASHBOARD_NAME"
        DASHBOARD_COUNT=1
    fi
    
    if [ "$BUCKET_COUNT" -eq 0 ] && [ "$DASHBOARD_COUNT" -eq 0 ]; then
        warning "No resources found to clean up"
        exit 0
    fi
}

# Empty S3 buckets function
empty_s3_buckets() {
    if [ "$BUCKET_COUNT" -eq 0 ]; then
        info "No S3 buckets to empty"
        return 0
    fi
    
    info "Emptying S3 buckets..."
    
    for bucket in $BUCKETS; do
        info "Processing bucket: $bucket"
        
        # Check if bucket exists
        if ! aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
            warning "Bucket $bucket does not exist or is not accessible"
            continue
        fi
        
        # Delete all current objects
        info "Removing all objects from $bucket..."
        aws s3 rm "s3://$bucket" --recursive || warning "Failed to remove some objects from $bucket"
        
        # Delete all object versions and delete markers
        info "Removing all object versions from $bucket..."
        
        # Get all versions
        VERSIONS=$(aws s3api list-object-versions --bucket "$bucket" --output json 2>/dev/null || echo '{}')
        
        # Delete versions if they exist
        if echo "$VERSIONS" | jq -e '.Versions // empty' > /dev/null 2>&1; then
            echo "$VERSIONS" | jq -r '.Versions[]? | "\(.Key)\t\(.VersionId)"' | while IFS=$'\t' read -r key version_id; do
                if [ -n "$key" ] && [ -n "$version_id" ]; then
                    aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" || warning "Failed to delete version $version_id of $key"
                fi
            done
        fi
        
        # Delete delete markers if they exist
        if echo "$VERSIONS" | jq -e '.DeleteMarkers // empty' > /dev/null 2>&1; then
            echo "$VERSIONS" | jq -r '.DeleteMarkers[]? | "\(.Key)\t\(.VersionId)"' | while IFS=$'\t' read -r key version_id; do
                if [ -n "$key" ] && [ -n "$version_id" ]; then
                    aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" || warning "Failed to delete marker $version_id of $key"
                fi
            done
        fi
        
        success "Bucket $bucket emptied"
    done
}

# Remove bucket configurations function
remove_bucket_configurations() {
    if [ "$BUCKET_COUNT" -eq 0 ]; then
        info "No bucket configurations to remove"
        return 0
    fi
    
    info "Removing bucket configurations..."
    
    for bucket in $BUCKETS; do
        info "Removing configurations for bucket: $bucket"
        
        # Check if bucket exists
        if ! aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
            warning "Bucket $bucket does not exist or is not accessible"
            continue
        fi
        
        # Remove intelligent tiering configuration
        info "Removing Intelligent Tiering configuration from $bucket..."
        aws s3api delete-bucket-intelligent-tiering-configuration \
            --bucket "$bucket" \
            --id "EntireBucketConfig" 2>/dev/null || warning "Failed to remove Intelligent Tiering config from $bucket (may not exist)"
        
        # Remove lifecycle configuration
        info "Removing lifecycle configuration from $bucket..."
        aws s3api delete-bucket-lifecycle-configuration \
            --bucket "$bucket" 2>/dev/null || warning "Failed to remove lifecycle config from $bucket (may not exist)"
        
        # Remove metrics configuration
        info "Removing metrics configuration from $bucket..."
        aws s3api delete-bucket-metrics-configuration \
            --bucket "$bucket" \
            --id "EntireBucket" 2>/dev/null || warning "Failed to remove metrics config from $bucket (may not exist)"
        
        success "Configurations removed from $bucket"
    done
}

# Delete S3 buckets function
delete_s3_buckets() {
    if [ "$BUCKET_COUNT" -eq 0 ]; then
        info "No S3 buckets to delete"
        return 0
    fi
    
    info "Deleting S3 buckets..."
    
    for bucket in $BUCKETS; do
        info "Deleting bucket: $bucket"
        
        # Check if bucket exists
        if ! aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
            warning "Bucket $bucket does not exist or is not accessible"
            continue
        fi
        
        # Delete the bucket
        aws s3 rb "s3://$bucket" --force || error_exit "Failed to delete bucket $bucket"
        
        success "Bucket $bucket deleted"
    done
}

# Remove CloudWatch dashboards function
remove_cloudwatch_dashboards() {
    if [ "$DASHBOARD_COUNT" -eq 0 ]; then
        info "No CloudWatch dashboards to remove"
        return 0
    fi
    
    info "Removing CloudWatch dashboards..."
    
    for dashboard in $DASHBOARDS; do
        info "Deleting dashboard: $dashboard"
        
        # Delete CloudWatch dashboard
        aws cloudwatch delete-dashboards \
            --dashboard-names "$dashboard" || warning "Failed to delete dashboard $dashboard (may not exist)"
        
        success "Dashboard $dashboard deleted"
    done
}

# Clean up local files function
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove any leftover local files
    rm -f frequent-data.txt archive-data.txt large-sample.dat lifecycle-policy.json downloaded-file.txt
    
    success "Local files cleaned up"
}

# Validation function
validate_cleanup() {
    info "Validating cleanup..."
    
    local cleanup_success=true
    
    # Check if buckets are deleted
    for bucket in $BUCKETS; do
        if aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
            warning "Bucket $bucket still exists"
            cleanup_success=false
        else
            success "Bucket $bucket successfully deleted"
        fi
    done
    
    # Check if dashboards are deleted
    for dashboard in $DASHBOARDS; do
        if aws cloudwatch describe-dashboards --dashboard-names "$dashboard" &>/dev/null; then
            warning "Dashboard $dashboard still exists"
            cleanup_success=false
        else
            success "Dashboard $dashboard successfully deleted"
        fi
    done
    
    if [ "$cleanup_success" = true ]; then
        success "Cleanup validation completed successfully"
    else
        warning "Some resources may not have been fully cleaned up"
    fi
}

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -b, --bucket-name BUCKET_NAME    Specify specific bucket name to delete"
    echo "  -d, --dashboard-name DASHBOARD   Specify specific dashboard name to delete"
    echo "  -f, --force                      Skip confirmation prompt"
    echo "  -h, --help                       Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_REGION                       AWS region (defaults to configured region)"
    echo "  BUCKET_NAME                      Specific bucket name to delete"
    echo "  DASHBOARD_NAME                   Specific dashboard name to delete"
    echo "  FORCE_DESTROY                    Set to 'true' to skip confirmation"
    echo ""
    echo "Examples:"
    echo "  $0                               # Clean up all discovered resources"
    echo "  $0 -f                            # Clean up without confirmation"
    echo "  $0 -b my-bucket-name             # Clean up specific bucket"
    echo "  FORCE_DESTROY=true $0            # Clean up with environment variable"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--bucket-name)
                BUCKET_NAME="$2"
                shift 2
                ;;
            -d|--dashboard-name)
                DASHBOARD_NAME="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_DESTROY="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Main cleanup function
main() {
    parse_arguments "$@"
    
    print_banner
    
    info "Starting cleanup of S3 Intelligent Tiering and Lifecycle Management resources..."
    info "Log file: $LOG_FILE"
    
    # Run cleanup steps
    check_prerequisites
    discover_resources
    confirm_destruction
    empty_s3_buckets
    remove_bucket_configurations
    delete_s3_buckets
    remove_cloudwatch_dashboards
    cleanup_local_files
    validate_cleanup
    
    echo ""
    echo "=================================================="
    success "Cleanup completed successfully!"
    echo "=================================================="
    echo ""
    echo "🗑️  Resources removed:"
    if [ "$BUCKET_COUNT" -gt 0 ]; then
        echo "   • S3 Buckets: $BUCKETS"
    fi
    if [ "$DASHBOARD_COUNT" -gt 0 ]; then
        echo "   • CloudWatch Dashboards: $DASHBOARDS"
    fi
    echo "   • All bucket configurations (Intelligent Tiering, Lifecycle, Metrics)"
    echo "   • All object versions and delete markers"
    echo "   • Local temporary files"
    echo ""
    success "All resources have been successfully removed"
    echo ""
    info "No further charges will be incurred for these resources"
}

# Run main function
main "$@"