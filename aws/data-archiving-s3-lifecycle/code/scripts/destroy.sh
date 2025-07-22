#!/bin/bash

# Data Archiving Solutions with S3 Lifecycle Policies - Cleanup Script
# This script removes all resources created by the deployment script
# Based on the recipe: "Data Archiving Solutions with S3 Lifecycle"

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ✅ $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ⚠️ $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ❌ $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured or invalid."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to load from saved environment file first
    if [ -f ".lifecycle-demo-env" ]; then
        source .lifecycle-demo-env
        success "Loaded environment variables from .lifecycle-demo-env"
    else
        warning "Environment file not found, attempting to discover resources..."
        
        # Set basic environment
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            warning "AWS region not configured, using default: $AWS_REGION"
        fi
        
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Try to find bucket with our naming pattern
        BUCKET_NAME=$(aws s3api list-buckets --query 'Buckets[?starts_with(Name, `data-archiving-demo-`)].Name' --output text | head -1)
        if [ -z "$BUCKET_NAME" ]; then
            error "No S3 bucket found with pattern 'data-archiving-demo-*'"
            warning "You may need to manually specify the bucket name"
            read -p "Enter the bucket name to clean up (or press Enter to skip): " BUCKET_NAME
            if [ -z "$BUCKET_NAME" ]; then
                warning "No bucket specified, skipping S3 cleanup"
            fi
        fi
        
        export BUCKET_NAME="${BUCKET_NAME:-}"
        export POLICY_NAME="DataArchivingPolicy"
        export ROLE_NAME="S3LifecycleRole"
    fi
    
    if [ -n "${BUCKET_NAME:-}" ]; then
        log "Target bucket: $BUCKET_NAME"
    fi
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo ""
    if [ -n "${BUCKET_NAME:-}" ]; then
        echo "🗂️  S3 Bucket: ${BUCKET_NAME} (and ALL its contents)"
        echo "📋 All lifecycle policies on the bucket"
        echo "🤖 Intelligent tiering configurations"
        echo "📊 S3 Analytics configurations"
        echo "📋 S3 Inventory configurations"
    fi
    echo "⏰ CloudWatch alarms: S3-Storage-Cost-${BUCKET_NAME:-*} and S3-Object-Count-${BUCKET_NAME:-*}"
    echo "👤 IAM Role: ${ROLE_NAME}"
    echo "📄 IAM Policy: ${POLICY_NAME}"
    echo "🗃️  All local temporary files"
    echo ""
    warning "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource cleanup..."
}

# Function to remove lifecycle policies
remove_lifecycle_policies() {
    if [ -z "${BUCKET_NAME:-}" ]; then
        warning "No bucket specified, skipping lifecycle policy removal"
        return 0
    fi
    
    log "Removing lifecycle policies..."
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket ${BUCKET_NAME} 2>/dev/null; then
        warning "Bucket ${BUCKET_NAME} does not exist or is not accessible"
        return 0
    fi
    
    # Delete lifecycle configuration
    aws s3api delete-bucket-lifecycle \
        --bucket ${BUCKET_NAME} 2>/dev/null || \
        warning "No lifecycle configuration found or already deleted"
    
    success "Removed lifecycle policies"
}

# Function to remove intelligent tiering configuration
remove_intelligent_tiering() {
    if [ -z "${BUCKET_NAME:-}" ]; then
        warning "No bucket specified, skipping intelligent tiering removal"
        return 0
    fi
    
    log "Removing intelligent tiering configuration..."
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket ${BUCKET_NAME} 2>/dev/null; then
        warning "Bucket ${BUCKET_NAME} does not exist or is not accessible"
        return 0
    fi
    
    # Delete intelligent tiering configuration
    aws s3api delete-bucket-intelligent-tiering-configuration \
        --bucket ${BUCKET_NAME} \
        --id MediaIntelligentTieringConfig 2>/dev/null || \
        warning "No intelligent tiering configuration found or already deleted"
    
    success "Removed intelligent tiering configuration"
}

# Function to remove analytics and inventory configurations
remove_analytics_inventory() {
    if [ -z "${BUCKET_NAME:-}" ]; then
        warning "No bucket specified, skipping analytics/inventory removal"
        return 0
    fi
    
    log "Removing analytics and inventory configurations..."
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket ${BUCKET_NAME} 2>/dev/null; then
        warning "Bucket ${BUCKET_NAME} does not exist or is not accessible"
        return 0
    fi
    
    # Delete analytics configuration
    aws s3api delete-bucket-analytics-configuration \
        --bucket ${BUCKET_NAME} \
        --id DocumentAnalytics 2>/dev/null || \
        warning "No analytics configuration found or already deleted"
    
    # Delete inventory configuration
    aws s3api delete-bucket-inventory-configuration \
        --bucket ${BUCKET_NAME} \
        --id StorageInventoryConfig 2>/dev/null || \
        warning "No inventory configuration found or already deleted"
    
    success "Removed analytics and inventory configurations"
}

# Function to remove CloudWatch alarms
remove_cloudwatch_alarms() {
    log "Removing CloudWatch alarms..."
    
    # Prepare alarm names
    COST_ALARM="S3-Storage-Cost-${BUCKET_NAME:-*}"
    COUNT_ALARM="S3-Object-Count-${BUCKET_NAME:-*}"
    
    # If bucket name is not set, try to find existing alarms
    if [ -z "${BUCKET_NAME:-}" ]; then
        log "Searching for S3-related CloudWatch alarms..."
        EXISTING_ALARMS=$(aws cloudwatch describe-alarms \
            --alarm-name-prefix "S3-Storage-Cost-data-archiving-demo-" \
            --query 'MetricAlarms[].AlarmName' --output text 2>/dev/null || echo "")
        EXISTING_ALARMS+=" "
        EXISTING_ALARMS+=$(aws cloudwatch describe-alarms \
            --alarm-name-prefix "S3-Object-Count-data-archiving-demo-" \
            --query 'MetricAlarms[].AlarmName' --output text 2>/dev/null || echo "")
        
        if [ -n "$EXISTING_ALARMS" ] && [ "$EXISTING_ALARMS" != " " ]; then
            log "Found existing alarms: $EXISTING_ALARMS"
            aws cloudwatch delete-alarms --alarm-names $EXISTING_ALARMS || \
                warning "Could not delete some CloudWatch alarms"
        else
            warning "No matching CloudWatch alarms found"
        fi
    else
        # Delete specific alarms
        aws cloudwatch delete-alarms \
            --alarm-names "$COST_ALARM" "$COUNT_ALARM" 2>/dev/null || \
            warning "Some CloudWatch alarms may not exist or already deleted"
    fi
    
    success "Removed CloudWatch alarms"
}

# Function to remove IAM resources
remove_iam_resources() {
    log "Removing IAM resources..."
    
    # Detach and delete IAM policy
    aws iam detach-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" 2>/dev/null || \
        warning "Policy may not be attached or already detached"
    
    aws iam delete-policy \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" 2>/dev/null || \
        warning "IAM policy may not exist or already deleted"
    
    # Delete IAM role
    aws iam delete-role \
        --role-name ${ROLE_NAME} 2>/dev/null || \
        warning "IAM role may not exist or already deleted"
    
    success "Removed IAM role and policy"
}

# Function to remove S3 bucket and all objects
remove_s3_bucket() {
    if [ -z "${BUCKET_NAME:-}" ]; then
        warning "No bucket specified, skipping S3 bucket removal"
        return 0
    fi
    
    log "Removing S3 bucket and all objects..."
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket ${BUCKET_NAME} 2>/dev/null; then
        warning "Bucket ${BUCKET_NAME} does not exist or is not accessible"
        return 0
    fi
    
    # Delete all objects in bucket (including versions and delete markers)
    log "Deleting all objects and versions from bucket..."
    aws s3api delete-objects \
        --bucket ${BUCKET_NAME} \
        --delete "$(aws s3api list-object-versions \
            --bucket ${BUCKET_NAME} \
            --output json \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' 2>/dev/null || echo '{}')" 2>/dev/null || \
        warning "Could not delete object versions"
    
    aws s3api delete-objects \
        --bucket ${BUCKET_NAME} \
        --delete "$(aws s3api list-object-versions \
            --bucket ${BUCKET_NAME} \
            --output json \
            --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' 2>/dev/null || echo '{}')" 2>/dev/null || \
        warning "Could not delete delete markers"
    
    # Delete all objects using s3 rm (backup method)
    aws s3 rm s3://${BUCKET_NAME} --recursive 2>/dev/null || \
        warning "Could not remove some objects with s3 rm"
    
    # Delete bucket
    aws s3 rb s3://${BUCKET_NAME} 2>/dev/null || \
        error "Could not delete bucket ${BUCKET_NAME}. It may still contain objects or have a bucket policy."
    
    success "Removed S3 bucket and all objects"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove local demo data directory
    rm -rf lifecycle-demo-data/ 2>/dev/null || true
    
    # Remove JSON configuration files
    rm -f *.json 2>/dev/null || true
    
    # Remove environment file
    rm -f .lifecycle-demo-env 2>/dev/null || true
    
    # Remove any backup files
    rm -f *.bak 2>/dev/null || true
    
    success "Cleaned up local files"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local cleanup_errors=0
    
    # Check if bucket still exists
    if [ -n "${BUCKET_NAME:-}" ]; then
        if aws s3api head-bucket --bucket ${BUCKET_NAME} 2>/dev/null; then
            error "S3 bucket ${BUCKET_NAME} still exists"
            cleanup_errors=$((cleanup_errors + 1))
        else
            success "S3 bucket successfully removed"
        fi
    fi
    
    # Check if IAM role still exists
    if aws iam get-role --role-name ${ROLE_NAME} 2>/dev/null; then
        error "IAM role ${ROLE_NAME} still exists"
        cleanup_errors=$((cleanup_errors + 1))
    else
        success "IAM role successfully removed"
    fi
    
    # Check if IAM policy still exists
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" 2>/dev/null; then
        error "IAM policy ${POLICY_NAME} still exists"
        cleanup_errors=$((cleanup_errors + 1))
    else
        success "IAM policy successfully removed"
    fi
    
    if [ $cleanup_errors -eq 0 ]; then
        success "Cleanup validation completed successfully"
    else
        warning "Cleanup validation found $cleanup_errors issues"
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo ""
    echo "🗑️  Resources removed:"
    if [ -n "${BUCKET_NAME:-}" ]; then
        echo "   🗂️  S3 Bucket: ${BUCKET_NAME}"
        echo "   📋 All lifecycle policies"
        echo "   🤖 Intelligent tiering configurations"
        echo "   📊 S3 Analytics configurations"
        echo "   📋 S3 Inventory configurations"
    else
        echo "   🗂️  S3 Bucket: (none specified)"
    fi
    echo "   ⏰ CloudWatch alarms"
    echo "   👤 IAM Role: ${ROLE_NAME}"
    echo "   📄 IAM Policy: ${POLICY_NAME}"
    echo "   🗃️  Local temporary files"
    echo ""
    success "All resources have been cleaned up"
    echo ""
    warning "Note: Some AWS services may have a delay before resources are fully removed"
    warning "Check AWS Console to confirm all resources are deleted"
}

# Function to handle script interruption
cleanup_on_error() {
    error "Script interrupted or failed during cleanup"
    warning "Some resources may not have been cleaned up"
    warning "Please check AWS Console manually"
    exit 1
}

# Trap for handling interruptions
trap cleanup_on_error INT TERM ERR

# Main cleanup function
main() {
    echo ""
    echo "🧹 Starting Data Archiving Solutions Cleanup"
    echo "============================================"
    echo ""
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    echo ""
    log "Beginning resource cleanup..."
    
    remove_lifecycle_policies
    remove_intelligent_tiering
    remove_analytics_inventory
    remove_cloudwatch_alarms
    remove_iam_resources
    remove_s3_bucket
    cleanup_local_files
    
    echo ""
    if validate_cleanup; then
        echo ""
        echo "🎉 Cleanup completed successfully!"
        echo "================================="
        display_cleanup_summary
    else
        echo ""
        warning "⚠️  Cleanup completed with some issues"
        echo "======================================"
        warning "Please check AWS Console for any remaining resources"
    fi
    
    success "Cleanup script completed"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi