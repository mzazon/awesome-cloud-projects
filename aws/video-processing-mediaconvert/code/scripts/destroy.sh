#!/bin/bash

# AWS Video Processing Workflows Cleanup Script
# This script destroys all resources created by the video processing pipeline

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS CLI configuration
validate_aws_cli() {
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ ! -f .env ]; then
        error "Environment file .env not found. Please run deploy.sh first or provide environment variables manually."
        exit 1
    fi

    # Load environment variables from .env file
    source .env

    # Validate required variables
    required_vars=("AWS_REGION" "AWS_ACCOUNT_ID" "S3_SOURCE_BUCKET" "S3_OUTPUT_BUCKET" "LAMBDA_FUNCTION_NAME" "MEDIACONVERT_ROLE_NAME" "LAMBDA_ROLE_NAME" "COMPLETION_HANDLER_NAME" "EVENTBRIDGE_RULE_NAME" "RANDOM_SUFFIX")
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            error "Required environment variable $var is not set"
            exit 1
        fi
    done

    log "✅ Environment variables loaded successfully"
    info "Resource suffix: ${RANDOM_SUFFIX}"
}

# Function to confirm deletion
confirm_deletion() {
    log "About to delete the following resources:"
    info "- S3 buckets: ${S3_SOURCE_BUCKET}, ${S3_OUTPUT_BUCKET}"
    info "- Lambda functions: ${LAMBDA_FUNCTION_NAME}, ${COMPLETION_HANDLER_NAME}"
    info "- IAM roles: ${MEDIACONVERT_ROLE_NAME}, ${LAMBDA_ROLE_NAME}"
    info "- EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
    info "- CloudFront distribution (if exists)"
    
    read -p "Are you sure you want to delete all these resources? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource deletion..."
}

# Function to delete CloudFront distribution
delete_cloudfront_distribution() {
    log "Deleting CloudFront distribution..."
    
    if [ -n "${DISTRIBUTION_ID:-}" ]; then
        # Get distribution configuration
        if aws cloudfront get-distribution --id "${DISTRIBUTION_ID}" >/dev/null 2>&1; then
            warn "CloudFront distribution ${DISTRIBUTION_ID} found"
            
            # Get current ETag
            ETAG=$(aws cloudfront get-distribution-config \
                --id "${DISTRIBUTION_ID}" \
                --query 'ETag' --output text 2>/dev/null)
            
            if [ -n "${ETAG}" ]; then
                # Get current config and disable distribution
                aws cloudfront get-distribution-config \
                    --id "${DISTRIBUTION_ID}" \
                    --query 'DistributionConfig' > /tmp/distribution-config.json
                
                # Update enabled status to false
                jq '.Enabled = false' /tmp/distribution-config.json > /tmp/distribution-config-disabled.json
                
                # Update distribution to disable it
                aws cloudfront update-distribution \
                    --id "${DISTRIBUTION_ID}" \
                    --distribution-config file:///tmp/distribution-config-disabled.json \
                    --if-match "${ETAG}" >/dev/null 2>&1
                
                warn "CloudFront distribution ${DISTRIBUTION_ID} has been disabled"
                warn "CloudFront distributions must be fully propagated before deletion"
                warn "Please wait 15-20 minutes and then manually delete the distribution"
                warn "Use: aws cloudfront delete-distribution --id ${DISTRIBUTION_ID} --if-match <new-etag>"
            else
                warn "Could not get ETag for distribution ${DISTRIBUTION_ID}"
            fi
        else
            info "CloudFront distribution ${DISTRIBUTION_ID} not found or already deleted"
        fi
    else
        info "No CloudFront distribution ID found in environment"
    fi
    
    # Clean up temp files
    rm -f /tmp/distribution-config.json /tmp/distribution-config-disabled.json
    
    log "✅ CloudFront distribution processing completed"
}

# Function to delete EventBridge rule
delete_eventbridge_rule() {
    log "Deleting EventBridge rule..."
    
    # Check if rule exists
    if aws events describe-rule --name "${EVENTBRIDGE_RULE_NAME}" >/dev/null 2>&1; then
        # Remove targets first
        aws events remove-targets \
            --rule "${EVENTBRIDGE_RULE_NAME}" \
            --ids "1" 2>/dev/null || warn "Failed to remove targets from rule"
        
        # Delete rule
        aws events delete-rule \
            --name "${EVENTBRIDGE_RULE_NAME}" 2>/dev/null || warn "Failed to delete EventBridge rule"
        
        log "✅ Deleted EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
    else
        info "EventBridge rule ${EVENTBRIDGE_RULE_NAME} not found"
    fi
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    # Delete video processor function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1; then
        aws lambda delete-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" 2>/dev/null || warn "Failed to delete Lambda function"
        
        log "✅ Deleted Lambda function: ${LAMBDA_FUNCTION_NAME}"
    else
        info "Lambda function ${LAMBDA_FUNCTION_NAME} not found"
    fi
    
    # Delete completion handler function
    if aws lambda get-function --function-name "${COMPLETION_HANDLER_NAME}" >/dev/null 2>&1; then
        aws lambda delete-function \
            --function-name "${COMPLETION_HANDLER_NAME}" 2>/dev/null || warn "Failed to delete completion handler"
        
        log "✅ Deleted completion handler: ${COMPLETION_HANDLER_NAME}"
    else
        info "Completion handler ${COMPLETION_HANDLER_NAME} not found"
    fi
}

# Function to delete S3 buckets
delete_s3_buckets() {
    log "Deleting S3 buckets and contents..."
    
    # Delete source bucket
    if aws s3api head-bucket --bucket "${S3_SOURCE_BUCKET}" 2>/dev/null; then
        # Empty bucket first
        aws s3 rm "s3://${S3_SOURCE_BUCKET}" --recursive 2>/dev/null || warn "Failed to empty source bucket"
        
        # Delete all object versions and delete markers
        aws s3api delete-objects \
            --bucket "${S3_SOURCE_BUCKET}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${S3_SOURCE_BUCKET}" \
                --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' \
                --output json 2>/dev/null || echo '{}')" 2>/dev/null || warn "Failed to delete object versions"
        
        aws s3api delete-objects \
            --bucket "${S3_SOURCE_BUCKET}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${S3_SOURCE_BUCKET}" \
                --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' \
                --output json 2>/dev/null || echo '{}')" 2>/dev/null || warn "Failed to delete delete markers"
        
        # Remove bucket notification configuration
        aws s3api put-bucket-notification-configuration \
            --bucket "${S3_SOURCE_BUCKET}" \
            --notification-configuration '{}' 2>/dev/null || warn "Failed to remove bucket notification"
        
        # Delete bucket
        aws s3 rb "s3://${S3_SOURCE_BUCKET}" --force 2>/dev/null || warn "Failed to delete source bucket"
        
        log "✅ Deleted source bucket: ${S3_SOURCE_BUCKET}"
    else
        info "Source bucket ${S3_SOURCE_BUCKET} not found"
    fi
    
    # Delete output bucket
    if aws s3api head-bucket --bucket "${S3_OUTPUT_BUCKET}" 2>/dev/null; then
        # Empty bucket first
        aws s3 rm "s3://${S3_OUTPUT_BUCKET}" --recursive 2>/dev/null || warn "Failed to empty output bucket"
        
        # Delete all object versions and delete markers
        aws s3api delete-objects \
            --bucket "${S3_OUTPUT_BUCKET}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${S3_OUTPUT_BUCKET}" \
                --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' \
                --output json 2>/dev/null || echo '{}')" 2>/dev/null || warn "Failed to delete object versions"
        
        aws s3api delete-objects \
            --bucket "${S3_OUTPUT_BUCKET}" \
            --delete "$(aws s3api list-object-versions \
                --bucket "${S3_OUTPUT_BUCKET}" \
                --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' \
                --output json 2>/dev/null || echo '{}')" 2>/dev/null || warn "Failed to delete delete markers"
        
        # Delete bucket
        aws s3 rb "s3://${S3_OUTPUT_BUCKET}" --force 2>/dev/null || warn "Failed to delete output bucket"
        
        log "✅ Deleted output bucket: ${S3_OUTPUT_BUCKET}"
    else
        info "Output bucket ${S3_OUTPUT_BUCKET} not found"
    fi
}

# Function to delete IAM roles and policies
delete_iam_resources() {
    log "Deleting IAM roles and policies..."
    
    # Delete MediaConvert role
    if aws iam get-role --role-name "${MEDIACONVERT_ROLE_NAME}" >/dev/null 2>&1; then
        # Detach policies
        aws iam detach-role-policy \
            --role-name "${MEDIACONVERT_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess 2>/dev/null || warn "Failed to detach S3 read policy"
        
        aws iam detach-role-policy \
            --role-name "${MEDIACONVERT_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess 2>/dev/null || warn "Failed to detach S3 full policy"
        
        # Delete role
        aws iam delete-role \
            --role-name "${MEDIACONVERT_ROLE_NAME}" 2>/dev/null || warn "Failed to delete MediaConvert role"
        
        log "✅ Deleted MediaConvert role: ${MEDIACONVERT_ROLE_NAME}"
    else
        info "MediaConvert role ${MEDIACONVERT_ROLE_NAME} not found"
    fi
    
    # Delete Lambda role
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" >/dev/null 2>&1; then
        # Detach basic execution policy
        aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || warn "Failed to detach Lambda basic execution policy"
        
        # Detach custom policy
        LAMBDA_POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/LambdaMediaConvertPolicy-${RANDOM_SUFFIX}"
        aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn "${LAMBDA_POLICY_ARN}" 2>/dev/null || warn "Failed to detach custom Lambda policy"
        
        # Delete custom policy
        aws iam delete-policy \
            --policy-arn "${LAMBDA_POLICY_ARN}" 2>/dev/null || warn "Failed to delete custom Lambda policy"
        
        # Delete role
        aws iam delete-role \
            --role-name "${LAMBDA_ROLE_NAME}" 2>/dev/null || warn "Failed to delete Lambda role"
        
        log "✅ Deleted Lambda role: ${LAMBDA_ROLE_NAME}"
    else
        info "Lambda role ${LAMBDA_ROLE_NAME} not found"
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    log "Waiting for resources to be fully deleted..."
    
    # Wait for Lambda functions to be deleted
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ! aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1 && \
           ! aws lambda get-function --function-name "${COMPLETION_HANDLER_NAME}" >/dev/null 2>&1; then
            break
        fi
        
        info "Waiting for Lambda functions to be deleted... (attempt ${attempt}/${max_attempts})"
        sleep 5
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        warn "Timeout waiting for Lambda functions to be deleted"
    else
        log "✅ Lambda functions confirmed deleted"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_success=true
    
    # Check S3 buckets
    if aws s3api head-bucket --bucket "${S3_SOURCE_BUCKET}" 2>/dev/null; then
        warn "Source bucket ${S3_SOURCE_BUCKET} still exists"
        cleanup_success=false
    fi
    
    if aws s3api head-bucket --bucket "${S3_OUTPUT_BUCKET}" 2>/dev/null; then
        warn "Output bucket ${S3_OUTPUT_BUCKET} still exists"
        cleanup_success=false
    fi
    
    # Check Lambda functions
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1; then
        warn "Lambda function ${LAMBDA_FUNCTION_NAME} still exists"
        cleanup_success=false
    fi
    
    if aws lambda get-function --function-name "${COMPLETION_HANDLER_NAME}" >/dev/null 2>&1; then
        warn "Completion handler ${COMPLETION_HANDLER_NAME} still exists"
        cleanup_success=false
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name "${MEDIACONVERT_ROLE_NAME}" >/dev/null 2>&1; then
        warn "MediaConvert role ${MEDIACONVERT_ROLE_NAME} still exists"
        cleanup_success=false
    fi
    
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" >/dev/null 2>&1; then
        warn "Lambda role ${LAMBDA_ROLE_NAME} still exists"
        cleanup_success=false
    fi
    
    # Check EventBridge rule
    if aws events describe-rule --name "${EVENTBRIDGE_RULE_NAME}" >/dev/null 2>&1; then
        warn "EventBridge rule ${EVENTBRIDGE_RULE_NAME} still exists"
        cleanup_success=false
    fi
    
    if $cleanup_success; then
        log "✅ Cleanup verification completed successfully"
    else
        warn "Some resources may still exist. Please check manually."
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [ -f .env ]; then
        rm -f .env
        log "✅ Removed .env file"
    fi
    
    # Remove any temporary files that might still exist
    rm -f /tmp/distribution-config.json
    rm -f /tmp/distribution-config-disabled.json
    
    log "✅ Local files cleaned up"
}

# Function to display final summary
display_summary() {
    log "Cleanup Summary:"
    info "✅ S3 buckets deleted"
    info "✅ Lambda functions deleted"
    info "✅ IAM roles and policies deleted"
    info "✅ EventBridge rule deleted"
    info "⚠️  CloudFront distribution disabled (manual deletion required)"
    info "✅ Environment file removed"
    
    if [ -n "${DISTRIBUTION_ID:-}" ]; then
        warn "IMPORTANT: CloudFront distribution ${DISTRIBUTION_ID} has been disabled"
        warn "You must manually delete it after 15-20 minutes using:"
        warn "aws cloudfront delete-distribution --id ${DISTRIBUTION_ID} --if-match <new-etag>"
    fi
}

# Main cleanup function
main() {
    log "Starting AWS Video Processing Workflows cleanup..."
    
    # Check prerequisites
    validate_aws_cli
    
    # Load environment
    load_environment
    
    # Confirm deletion
    confirm_deletion
    
    # Delete resources in reverse order
    delete_cloudfront_distribution
    delete_eventbridge_rule
    delete_lambda_functions
    delete_s3_buckets
    delete_iam_resources
    
    # Wait for resources to be fully deleted
    wait_for_deletion
    
    # Verify cleanup
    verify_cleanup
    
    # Clean up local files
    cleanup_local_files
    
    # Display summary
    display_summary
    
    log "🎉 Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup interrupted"; exit 1' INT TERM

# Check for dry run option
if [[ "${1:-}" == "--dry-run" ]]; then
    log "DRY RUN MODE: No resources will be deleted"
    validate_aws_cli
    load_environment
    log "Would delete the following resources:"
    info "- S3 buckets: ${S3_SOURCE_BUCKET}, ${S3_OUTPUT_BUCKET}"
    info "- Lambda functions: ${LAMBDA_FUNCTION_NAME}, ${COMPLETION_HANDLER_NAME}"
    info "- IAM roles: ${MEDIACONVERT_ROLE_NAME}, ${LAMBDA_ROLE_NAME}"
    info "- EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
    info "- CloudFront distribution (if exists)"
    log "Run without --dry-run to perform actual deletion"
    exit 0
fi

# Run main function
main "$@"