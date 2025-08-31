#!/bin/bash

# Simple JSON to CSV Converter with Lambda and S3 - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail  # Exit on error, undefined variables, or pipe failures

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

# Script metadata
SCRIPT_NAME="JSON to CSV Converter Cleanup"
SCRIPT_VERSION="1.0"
CLEANUP_START_TIME=$(date)

log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
log_info "Cleanup started at: $CLEANUP_START_TIME"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ -f "deployment-info.json" ]]; then
        export INPUT_BUCKET_NAME=$(grep -o '"input_bucket_name": "[^"]*"' deployment-info.json | cut -d'"' -f4)
        export OUTPUT_BUCKET_NAME=$(grep -o '"output_bucket_name": "[^"]*"' deployment-info.json | cut -d'"' -f4)
        export LAMBDA_FUNCTION_NAME=$(grep -o '"lambda_function_name": "[^"]*"' deployment-info.json | cut -d'"' -f4)
        export LAMBDA_ROLE_NAME=$(grep -o '"lambda_role_name": "[^"]*"' deployment-info.json | cut -d'"' -f4)
        
        log_success "Deployment information loaded from deployment-info.json"
        log_info "Resources to be deleted:"
        log_info "  - Input Bucket: ${INPUT_BUCKET_NAME}"
        log_info "  - Output Bucket: ${OUTPUT_BUCKET_NAME}"
        log_info "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
        log_info "  - IAM Role: ${LAMBDA_ROLE_NAME}"
    else
        log_warning "deployment-info.json not found. Manual resource specification required."
        prompt_for_resources
    fi
}

# Function to prompt for resource names if deployment info is not available
prompt_for_resources() {
    log_info "Please provide the resource names to delete:"
    
    read -p "Input S3 bucket name (json-input-*): " INPUT_BUCKET_NAME
    read -p "Output S3 bucket name (csv-output-*): " OUTPUT_BUCKET_NAME
    read -p "Lambda function name (json-csv-converter-*): " LAMBDA_FUNCTION_NAME
    read -p "IAM role name (json-csv-converter-role-*): " LAMBDA_ROLE_NAME
    
    export INPUT_BUCKET_NAME OUTPUT_BUCKET_NAME LAMBDA_FUNCTION_NAME LAMBDA_ROLE_NAME
    
    log_info "Resources to be deleted:"
    log_info "  - Input Bucket: ${INPUT_BUCKET_NAME}"
    log_info "  - Output Bucket: ${OUTPUT_BUCKET_NAME}"
    log_info "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    log_info "  - IAM Role: ${LAMBDA_ROLE_NAME}"
}

# Function to confirm destructive action
confirm_deletion() {
    log_warning "========================================="
    log_warning "WARNING: This will permanently delete:"
    log_warning "  - S3 buckets and all their contents"
    log_warning "  - Lambda function"
    log_warning "  - IAM role and policies"
    log_warning "========================================="
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Function to remove S3 bucket contents and buckets
cleanup_s3_buckets() {
    log_info "Cleaning up S3 buckets..."
    
    # Remove input bucket and contents
    if [[ -n "${INPUT_BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket ${INPUT_BUCKET_NAME} >/dev/null 2>&1; then
            # List bucket contents for user awareness
            OBJECT_COUNT=$(aws s3 ls s3://${INPUT_BUCKET_NAME} --recursive | wc -l || echo "0")
            if [[ "$OBJECT_COUNT" -gt 0 ]]; then
                log_info "Removing $OBJECT_COUNT objects from input bucket..."
                aws s3 rm s3://${INPUT_BUCKET_NAME} --recursive
            fi
            
            # Delete all versions (if versioning was enabled)
            aws s3api delete-objects \
                --bucket ${INPUT_BUCKET_NAME} \
                --delete "$(aws s3api list-object-versions \
                    --bucket ${INPUT_BUCKET_NAME} \
                    --output json \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
            
            # Delete delete markers (if any)
            aws s3api delete-objects \
                --bucket ${INPUT_BUCKET_NAME} \
                --delete "$(aws s3api list-object-versions \
                    --bucket ${INPUT_BUCKET_NAME} \
                    --output json \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
            
            # Delete the bucket
            aws s3 rb s3://${INPUT_BUCKET_NAME}
            log_success "Input bucket ${INPUT_BUCKET_NAME} deleted"
        else
            log_warning "Input bucket ${INPUT_BUCKET_NAME} not found or already deleted"
        fi
    fi
    
    # Remove output bucket and contents
    if [[ -n "${OUTPUT_BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket ${OUTPUT_BUCKET_NAME} >/dev/null 2>&1; then
            # List bucket contents for user awareness
            OBJECT_COUNT=$(aws s3 ls s3://${OUTPUT_BUCKET_NAME} --recursive | wc -l || echo "0")
            if [[ "$OBJECT_COUNT" -gt 0 ]]; then
                log_info "Removing $OBJECT_COUNT objects from output bucket..."
                aws s3 rm s3://${OUTPUT_BUCKET_NAME} --recursive
            fi
            
            # Delete all versions (if versioning was enabled)
            aws s3api delete-objects \
                --bucket ${OUTPUT_BUCKET_NAME} \
                --delete "$(aws s3api list-object-versions \
                    --bucket ${OUTPUT_BUCKET_NAME} \
                    --output json \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
            
            # Delete delete markers (if any)
            aws s3api delete-objects \
                --bucket ${OUTPUT_BUCKET_NAME} \
                --delete "$(aws s3api list-object-versions \
                    --bucket ${OUTPUT_BUCKET_NAME} \
                    --output json \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
            
            # Delete the bucket
            aws s3 rb s3://${OUTPUT_BUCKET_NAME}
            log_success "Output bucket ${OUTPUT_BUCKET_NAME} deleted"
        else
            log_warning "Output bucket ${OUTPUT_BUCKET_NAME} not found or already deleted"
        fi
    fi
}

# Function to delete Lambda function
cleanup_lambda_function() {
    log_info "Cleaning up Lambda function..."
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME} >/dev/null 2>&1; then
            # Remove S3 trigger permission first
            aws lambda remove-permission \
                --function-name ${LAMBDA_FUNCTION_NAME} \
                --statement-id s3-trigger-permission 2>/dev/null || true
            
            # Delete Lambda function
            aws lambda delete-function --function-name ${LAMBDA_FUNCTION_NAME}
            log_success "Lambda function ${LAMBDA_FUNCTION_NAME} deleted"
        else
            log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} not found or already deleted"
        fi
    fi
}

# Function to remove IAM role and policies
cleanup_iam_role() {
    log_info "Cleaning up IAM role and policies..."
    
    if [[ -n "${LAMBDA_ROLE_NAME:-}" ]]; then
        if aws iam get-role --role-name ${LAMBDA_ROLE_NAME} >/dev/null 2>&1; then
            # Detach managed policies
            aws iam detach-role-policy \
                --role-name ${LAMBDA_ROLE_NAME} \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
            
            # Delete inline policies
            INLINE_POLICIES=$(aws iam list-role-policies \
                --role-name ${LAMBDA_ROLE_NAME} \
                --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
            
            for policy in $INLINE_POLICIES; do
                if [[ -n "$policy" ]]; then
                    aws iam delete-role-policy \
                        --role-name ${LAMBDA_ROLE_NAME} \
                        --policy-name "$policy"
                    log_info "Deleted inline policy: $policy"
                fi
            done
            
            # Delete IAM role
            aws iam delete-role --role-name ${LAMBDA_ROLE_NAME}
            log_success "IAM role ${LAMBDA_ROLE_NAME} deleted"
        else
            log_warning "IAM role ${LAMBDA_ROLE_NAME} not found or already deleted"
        fi
    fi
}

# Function to clean up CloudWatch logs
cleanup_cloudwatch_logs() {
    log_info "Cleaning up CloudWatch logs..."
    
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        LOG_GROUP_NAME="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
        
        if aws logs describe-log-groups --log-group-name-prefix ${LOG_GROUP_NAME} --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q ${LOG_GROUP_NAME}; then
            aws logs delete-log-group --log-group-name ${LOG_GROUP_NAME}
            log_success "CloudWatch log group ${LOG_GROUP_NAME} deleted"
        else
            log_warning "CloudWatch log group ${LOG_GROUP_NAME} not found or already deleted"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-info.json"
        "trust-policy.json"
        "s3-policy.json"
        "lambda_function.py"
        "lambda-deployment.zip"
        "notification-config.json"
        "sample-data.json"
        "sample-data.csv"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed local file: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check S3 buckets
    if [[ -n "${INPUT_BUCKET_NAME:-}" ]] && aws s3api head-bucket --bucket ${INPUT_BUCKET_NAME} >/dev/null 2>&1; then
        log_error "Input bucket ${INPUT_BUCKET_NAME} still exists"
        ((cleanup_errors++))
    fi
    
    if [[ -n "${OUTPUT_BUCKET_NAME:-}" ]] && aws s3api head-bucket --bucket ${OUTPUT_BUCKET_NAME} >/dev/null 2>&1; then
        log_error "Output bucket ${OUTPUT_BUCKET_NAME} still exists"
        ((cleanup_errors++))
    fi
    
    # Check Lambda function
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]] && aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME} >/dev/null 2>&1; then
        log_error "Lambda function ${LAMBDA_FUNCTION_NAME} still exists"
        ((cleanup_errors++))
    fi
    
    # Check IAM role
    if [[ -n "${LAMBDA_ROLE_NAME:-}" ]] && aws iam get-role --role-name ${LAMBDA_ROLE_NAME} >/dev/null 2>&1; then
        log_error "IAM role ${LAMBDA_ROLE_NAME} still exists"
        ((cleanup_errors++))
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        log_success "All resources successfully cleaned up"
    else
        log_error "$cleanup_errors resources still exist. Manual cleanup may be required."
        return 1
    fi
}

# Function to display final summary
display_summary() {
    local cleanup_status=$1
    CLEANUP_END_TIME=$(date)
    
    log_info "========================================="
    if [[ $cleanup_status -eq 0 ]]; then
        log_success "Cleanup completed successfully!"
    else
        log_error "Cleanup completed with errors!"
    fi
    log_info "Started:  $CLEANUP_START_TIME"
    log_info "Finished: $CLEANUP_END_TIME"
    log_info "========================================="
    
    if [[ $cleanup_status -eq 0 ]]; then
        log_info ""
        log_info "All resources have been successfully removed:"
        log_info "  ✅ S3 buckets and contents deleted"
        log_info "  ✅ Lambda function deleted"
        log_info "  ✅ IAM role and policies deleted"
        log_info "  ✅ CloudWatch logs deleted"
        log_info "  ✅ Local files cleaned up"
        log_info ""
        log_info "Your AWS account has been restored to its previous state."
    else
        log_warning ""
        log_warning "Some resources may still exist. Please check your AWS console"
        log_warning "and manually delete any remaining resources to avoid charges."
    fi
}

# Main cleanup function
main() {
    log_info "========================================="
    log_info "JSON to CSV Converter Cleanup Script"
    log_info "========================================="
    
    check_prerequisites
    load_deployment_info
    confirm_deletion
    
    cleanup_s3_buckets
    cleanup_lambda_function
    cleanup_iam_role
    cleanup_cloudwatch_logs
    cleanup_local_files
    
    # Verify cleanup and capture status
    if verify_cleanup; then
        cleanup_status=0
    else
        cleanup_status=1
    fi
    
    display_summary $cleanup_status
    
    exit $cleanup_status
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi