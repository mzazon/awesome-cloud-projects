#!/bin/bash

# AWS Markdown to HTML Converter - Cleanup Script
# This script removes all resources created by the deployment script
# 
# Prerequisites:
# - AWS CLI installed and configured
# - Deployment configuration file (.deployment-config) from deploy.sh
# - Appropriate AWS permissions for Lambda, S3, and IAM

set -e  # Exit on error
set -u  # Exit on undefined variable

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

# Check if script is run from correct directory
check_directory() {
    if [[ ! -f "../../markdown-html-converter-lambda-s3.md" ]]; then
        log_error "Please run this script from the aws/markdown-html-converter-lambda-s3/code/scripts/ directory"
        exit 1
    fi
}

# Load deployment configuration
load_configuration() {
    if [[ ! -f ".deployment-config" ]]; then
        log_error "Deployment configuration file not found!"
        log_error "Please ensure deploy.sh was run successfully first."
        log_info "You can also set environment variables manually:"
        log_info "  export AWS_REGION=us-east-1"
        log_info "  export AWS_ACCOUNT_ID=123456789012"
        log_info "  export INPUT_BUCKET_NAME=your-input-bucket"
        log_info "  export OUTPUT_BUCKET_NAME=your-output-bucket"
        log_info "  export FUNCTION_NAME=markdown-to-html-converter"
        log_info "  export ROLE_NAME=lambda-markdown-converter-role"
        
        # Try to get default values if not in config
        if [[ -z "${AWS_REGION:-}" ]]; then
            export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        fi
        if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
            export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        fi
        if [[ -z "${FUNCTION_NAME:-}" ]]; then
            export FUNCTION_NAME="markdown-to-html-converter"
        fi
        if [[ -z "${ROLE_NAME:-}" ]]; then
            export ROLE_NAME="lambda-markdown-converter-role"
        fi
        
        if [[ -z "${INPUT_BUCKET_NAME:-}" || -z "${OUTPUT_BUCKET_NAME:-}" ]]; then
            log_error "Cannot determine bucket names. Please set environment variables manually."
            exit 1
        fi
    else
        log_info "Loading deployment configuration..."
        source .deployment-config
        log_success "Configuration loaded successfully"
    fi
    
    log_info "Resources to be deleted:"
    log_info "  • AWS Region: $AWS_REGION"
    log_info "  • Input S3 Bucket: $INPUT_BUCKET_NAME"
    log_info "  • Output S3 Bucket: $OUTPUT_BUCKET_NAME"
    log_info "  • Lambda Function: $FUNCTION_NAME"
    log_info "  • IAM Role: $ROLE_NAME"
}

# Confirmation prompt
confirm_deletion() {
    echo
    log_warning "⚠️  WARNING: This will permanently delete ALL resources and data!"
    log_warning "This action cannot be undone."
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    log_info "Proceeding with resource cleanup..."
}

# Remove S3 event notification
remove_s3_trigger() {
    log_info "Removing S3 event notification..."
    
    if aws s3api head-bucket --bucket "$INPUT_BUCKET_NAME" 2>/dev/null; then
        # Remove notification configuration
        aws s3api put-bucket-notification-configuration \
            --bucket "$INPUT_BUCKET_NAME" \
            --notification-configuration '{}' 2>/dev/null || true
        
        log_success "S3 event notifications removed"
    else
        log_warning "Input bucket $INPUT_BUCKET_NAME not found or already deleted"
    fi
}

# Remove Lambda permission and function
remove_lambda_function() {
    log_info "Removing Lambda function and permissions..."
    
    # Remove Lambda permission for S3
    aws lambda remove-permission \
        --function-name "$FUNCTION_NAME" \
        --statement-id s3-trigger-permission \
        2>/dev/null || log_warning "Lambda permission not found or already removed"
    
    # Delete Lambda function
    if aws lambda get-function --function-name "$FUNCTION_NAME" &>/dev/null; then
        aws lambda delete-function --function-name "$FUNCTION_NAME"
        log_success "Lambda function $FUNCTION_NAME deleted"
    else
        log_warning "Lambda function $FUNCTION_NAME not found or already deleted"
    fi
}

# Empty and delete S3 buckets
remove_s3_buckets() {
    log_info "Removing S3 buckets and all contents..."
    
    # Remove input bucket
    if aws s3api head-bucket --bucket "$INPUT_BUCKET_NAME" 2>/dev/null; then
        log_info "Emptying input bucket $INPUT_BUCKET_NAME..."
        
        # Delete all objects including versions
        aws s3api list-object-versions \
            --bucket "$INPUT_BUCKET_NAME" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output text | while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object \
                    --bucket "$INPUT_BUCKET_NAME" \
                    --key "$key" \
                    --version-id "$version_id" >/dev/null 2>&1 || true
            fi
        done
        
        # Delete delete markers
        aws s3api list-object-versions \
            --bucket "$INPUT_BUCKET_NAME" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output text | while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object \
                    --bucket "$INPUT_BUCKET_NAME" \
                    --key "$key" \
                    --version-id "$version_id" >/dev/null 2>&1 || true
            fi
        done
        
        # Force delete any remaining objects
        aws s3 rm "s3://$INPUT_BUCKET_NAME" --recursive --quiet 2>/dev/null || true
        
        # Delete bucket
        aws s3 rb "s3://$INPUT_BUCKET_NAME" --force 2>/dev/null || true
        log_success "Input bucket $INPUT_BUCKET_NAME deleted"
    else
        log_warning "Input bucket $INPUT_BUCKET_NAME not found or already deleted"
    fi
    
    # Remove output bucket
    if aws s3api head-bucket --bucket "$OUTPUT_BUCKET_NAME" 2>/dev/null; then
        log_info "Emptying output bucket $OUTPUT_BUCKET_NAME..."
        
        # Delete all objects including versions
        aws s3api list-object-versions \
            --bucket "$OUTPUT_BUCKET_NAME" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output text | while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object \
                    --bucket "$OUTPUT_BUCKET_NAME" \
                    --key "$key" \
                    --version-id "$version_id" >/dev/null 2>&1 || true
            fi
        done
        
        # Delete delete markers
        aws s3api list-object-versions \
            --bucket "$OUTPUT_BUCKET_NAME" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output text | while read -r key version_id; do
            if [[ -n "$key" && -n "$version_id" ]]; then
                aws s3api delete-object \
                    --bucket "$OUTPUT_BUCKET_NAME" \
                    --key "$key" \
                    --version-id "$version_id" >/dev/null 2>&1 || true
            fi
        done
        
        # Force delete any remaining objects
        aws s3 rm "s3://$OUTPUT_BUCKET_NAME" --recursive --quiet 2>/dev/null || true
        
        # Delete bucket
        aws s3 rb "s3://$OUTPUT_BUCKET_NAME" --force 2>/dev/null || true
        log_success "Output bucket $OUTPUT_BUCKET_NAME deleted"
    else
        log_warning "Output bucket $OUTPUT_BUCKET_NAME not found or already deleted"
    fi
}

# Remove IAM role and policies
remove_iam_resources() {
    log_info "Removing IAM role and policies..."
    
    POLICY_NAME="lambda-s3-access-policy"
    POLICY_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME"
    
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        # Detach managed policy
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
            2>/dev/null || log_warning "Basic execution policy not attached or already detached"
        
        # Detach custom policy
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn "$POLICY_ARN" \
            2>/dev/null || log_warning "Custom S3 policy not attached or already detached"
        
        # Delete role
        aws iam delete-role --role-name "$ROLE_NAME"
        log_success "IAM role $ROLE_NAME deleted"
    else
        log_warning "IAM role $ROLE_NAME not found or already deleted"
    fi
    
    # Delete custom policy
    if aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
        aws iam delete-policy --policy-arn "$POLICY_ARN"
        log_success "Custom policy $POLICY_NAME deleted"
    else
        log_warning "Custom policy $POLICY_NAME not found or already deleted"
    fi
}

# Remove CloudWatch logs
remove_cloudwatch_logs() {
    log_info "Removing CloudWatch log groups..."
    
    LOG_GROUP_NAME="/aws/lambda/$FUNCTION_NAME"
    
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
        aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME"
        log_success "CloudWatch log group $LOG_GROUP_NAME deleted"
    else
        log_warning "CloudWatch log group $LOG_GROUP_NAME not found or already deleted"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment configuration
    if [[ -f ".deployment-config" ]]; then
        rm -f .deployment-config
        log_success "Deployment configuration file removed"
    fi
    
    # Remove any temporary files that might still exist
    rm -f trust-policy.json s3-access-policy.json notification-config.json
    rm -f sample-test.md test-output.html
    rm -rf lambda-function-temp/ lambda-function.zip
    
    log_success "Local cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check S3 buckets
    if aws s3api head-bucket --bucket "$INPUT_BUCKET_NAME" 2>/dev/null; then
        log_error "Input bucket $INPUT_BUCKET_NAME still exists"
        ((cleanup_errors++))
    fi
    
    if aws s3api head-bucket --bucket "$OUTPUT_BUCKET_NAME" 2>/dev/null; then
        log_error "Output bucket $OUTPUT_BUCKET_NAME still exists"
        ((cleanup_errors++))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$FUNCTION_NAME" &>/dev/null; then
        log_error "Lambda function $FUNCTION_NAME still exists"
        ((cleanup_errors++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        log_error "IAM role $ROLE_NAME still exists"
        ((cleanup_errors++))
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        log_success "✅ All resources successfully removed"
        return 0
    else
        log_error "❌ $cleanup_errors resource(s) failed to delete"
        log_info "You may need to manually remove remaining resources"
        return 1
    fi
}

# Display cleanup summary
display_summary() {
    echo
    log_info "🧹 Cleanup Summary"
    log_info "=================="
    log_info "✅ S3 event notifications removed"
    log_info "✅ Lambda function deleted"
    log_info "✅ S3 buckets and contents deleted"
    log_info "✅ IAM role and policies deleted"
    log_info "✅ CloudWatch log groups deleted"
    log_info "✅ Local files cleaned up"
    echo
    log_success "🎉 All resources have been successfully removed!"
    echo
    log_info "If you want to redeploy, run: ./deploy.sh"
}

# Handle script interruption
cleanup_on_exit() {
    log_warning "Script interrupted. Some resources may still exist."
    log_info "You can run this script again to complete the cleanup."
    exit 1
}

# Main cleanup function
main() {
    # Set up trap for script interruption
    trap cleanup_on_exit INT TERM
    
    log_info "Starting AWS Markdown to HTML Converter cleanup..."
    
    check_directory
    load_configuration
    confirm_deletion
    
    # Perform cleanup in reverse order of creation
    remove_s3_trigger
    remove_lambda_function
    remove_s3_buckets
    remove_iam_resources
    remove_cloudwatch_logs
    cleanup_local_files
    
    # Verify and display results
    if verify_cleanup; then
        display_summary
    else
        log_error "Cleanup completed with errors. Please check the output above."
        exit 1
    fi
}

# Run main function
main "$@"