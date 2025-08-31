#!/bin/bash

# Simple Password Generator with Lambda and S3 - Cleanup Script
# This script removes all resources created by the deployment script
# Author: AWS Recipe Generator
# Version: 1.1

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI and configure it."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid. Please run 'aws configure'."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Try to load from deployment environment file
    if [[ -f "${PWD}/.deploy_env" ]]; then
        log_info "Loading environment from deployment file..."
        source "${PWD}/.deploy_env"
        log_success "Environment loaded from deployment file"
        return 0
    fi
    
    # If no deployment file, try to use current environment
    if [[ -n "${BUCKET_NAME:-}" && -n "${LAMBDA_FUNCTION_NAME:-}" && -n "${IAM_ROLE_NAME:-}" ]]; then
        log_info "Using current environment variables"
        return 0
    fi
    
    # If no environment variables, prompt user for resource names
    log_warning "No deployment environment found. Please provide resource names manually."
    read -p "Enter S3 bucket name (password-generator-XXXXXX): " BUCKET_NAME
    read -p "Enter Lambda function name (password-generator-XXXXXX): " LAMBDA_FUNCTION_NAME
    read -p "Enter IAM role name (lambda-password-generator-role-XXXXXX): " IAM_ROLE_NAME
    
    # Set default AWS region if not set
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
    
    # Validate inputs
    if [[ -z "${BUCKET_NAME}" || -z "${LAMBDA_FUNCTION_NAME}" || -z "${IAM_ROLE_NAME}" ]]; then
        log_error "All resource names are required for cleanup"
        exit 1
    fi
    
    log_info "Using provided resource names for cleanup"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "${1:-}" == "--force" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo
    log_warning "This will permanently delete the following resources:"
    echo "  - S3 Bucket: ${BUCKET_NAME} (and all contents)"
    echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  - IAM Role: ${IAM_ROLE_NAME}"
    echo "  - CloudWatch Log Groups: /aws/lambda/${LAMBDA_FUNCTION_NAME}"
    echo
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [[ "${confirmation,,}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    log_info "Deleting Lambda function..."
    
    # Check if function exists
    if ! aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} does not exist. Skipping."
        return 0
    fi
    
    # Delete Lambda function
    if aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        log_success "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}"
    else
        log_error "Failed to delete Lambda function: ${LAMBDA_FUNCTION_NAME}"
        return 1
    fi
    
    # Delete CloudWatch log group (may not exist, so don't fail if it doesn't)
    local log_group_name="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
    if aws logs describe-log-groups --log-group-name-prefix "${log_group_name}" --query 'logGroups[0]' --output text | grep -q "${log_group_name}"; then
        if aws logs delete-log-group --log-group-name "${log_group_name}" &> /dev/null; then
            log_success "CloudWatch log group deleted: ${log_group_name}"
        else
            log_warning "Failed to delete CloudWatch log group: ${log_group_name}"
        fi
    else
        log_info "CloudWatch log group does not exist: ${log_group_name}"
    fi
}

# Function to empty and delete S3 bucket
delete_s3_bucket() {
    log_info "Deleting S3 bucket and all contents..."
    
    # Check if bucket exists
    if ! aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
        log_warning "S3 bucket ${BUCKET_NAME} does not exist. Skipping."
        return 0
    fi
    
    # Delete all objects in bucket (including versions)
    log_info "Emptying S3 bucket contents..."
    if aws s3 rm "s3://${BUCKET_NAME}" --recursive &> /dev/null; then
        log_success "S3 bucket contents deleted"
    else
        log_warning "Failed to delete some S3 bucket contents"
    fi
    
    # Delete all object versions (if versioning is enabled)
    log_info "Deleting all object versions..."
    local versions_output
    versions_output=$(aws s3api list-object-versions --bucket "${BUCKET_NAME}" --output json 2>/dev/null || echo '{}')
    
    # Delete versions
    if echo "${versions_output}" | grep -q '"Versions"'; then
        echo "${versions_output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for version in data.get('Versions', []):
    print(f\"aws s3api delete-object --bucket ${BUCKET_NAME} --key '{version['Key']}' --version-id '{version['VersionId']}'\")
" | while read -r cmd; do
            if [[ -n "${cmd}" ]]; then
                eval "${cmd}" &> /dev/null || true
            fi
        done
        log_success "Object versions deleted"
    fi
    
    # Delete delete markers
    if echo "${versions_output}" | grep -q '"DeleteMarkers"'; then
        echo "${versions_output}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for marker in data.get('DeleteMarkers', []):
    print(f\"aws s3api delete-object --bucket ${BUCKET_NAME} --key '{marker['Key']}' --version-id '{marker['VersionId']}'\")
" | while read -r cmd; do
            if [[ -n "${cmd}" ]]; then
                eval "${cmd}" &> /dev/null || true
            fi
        done
        log_success "Delete markers removed"
    fi
    
    # Delete bucket
    if aws s3 rb "s3://${BUCKET_NAME}" &> /dev/null; then
        log_success "S3 bucket deleted: ${BUCKET_NAME}"
    else
        log_error "Failed to delete S3 bucket: ${BUCKET_NAME}"
        log_info "You may need to manually delete the bucket if it still contains objects"
        return 1
    fi
}

# Function to delete IAM role and policies
delete_iam_role() {
    log_info "Deleting IAM role and policies..."
    
    # Check if role exists
    if ! aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        log_warning "IAM role ${IAM_ROLE_NAME} does not exist. Skipping."
        return 0
    fi
    
    # Delete inline policies
    local policies
    policies=$(aws iam list-role-policies --role-name "${IAM_ROLE_NAME}" --query 'PolicyNames' --output text 2>/dev/null || echo "")
    
    if [[ -n "${policies}" && "${policies}" != "None" ]]; then
        for policy in ${policies}; do
            if aws iam delete-role-policy --role-name "${IAM_ROLE_NAME}" --policy-name "${policy}" &> /dev/null; then
                log_success "Inline policy deleted: ${policy}"
            else
                log_warning "Failed to delete inline policy: ${policy}"
            fi
        done
    fi
    
    # Detach managed policies
    local attached_policies
    attached_policies=$(aws iam list-attached-role-policies --role-name "${IAM_ROLE_NAME}" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    
    if [[ -n "${attached_policies}" && "${attached_policies}" != "None" ]]; then
        for policy_arn in ${attached_policies}; do
            if aws iam detach-role-policy --role-name "${IAM_ROLE_NAME}" --policy-arn "${policy_arn}" &> /dev/null; then
                log_success "Managed policy detached: ${policy_arn}"
            else
                log_warning "Failed to detach managed policy: ${policy_arn}"
            fi
        done
    fi
    
    # Delete IAM role
    if aws iam delete-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        log_success "IAM role deleted: ${IAM_ROLE_NAME}"
    else
        log_error "Failed to delete IAM role: ${IAM_ROLE_NAME}"
        return 1
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "trust-policy.json"
        "lambda-policy.json" 
        "lambda_function.py"
        "lambda-function.zip"
        "response.json"
        "response2.json"
        "password.json"
        ".deploy_env"
    )
    
    local removed_count=0
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            removed_count=$((removed_count + 1))
        fi
    done
    
    if [[ ${removed_count} -gt 0 ]]; then
        log_success "Local files cleaned up (${removed_count} files removed)"
    else
        log_info "No local files to clean up"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_failed=false
    
    # Check Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        log_error "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
        cleanup_failed=true
    fi
    
    # Check S3 bucket
    if aws s3 ls "s3://${BUCKET_NAME}" &> /dev/null; then
        log_error "S3 bucket still exists: ${BUCKET_NAME}"
        cleanup_failed=true
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &> /dev/null; then
        log_error "IAM role still exists: ${IAM_ROLE_NAME}"
        cleanup_failed=true
    fi
    
    if [[ "${cleanup_failed}" == "true" ]]; then
        log_error "Cleanup verification failed. Some resources may still exist."
        return 1
    fi
    
    log_success "Cleanup verification passed. All resources have been removed."
}

# Function to display cleanup summary
display_summary() {
    log_success "Cleanup completed!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "The following resources have been removed:"
    echo "  ✅ S3 Bucket: ${BUCKET_NAME}"
    echo "  ✅ Lambda Function: ${LAMBDA_FUNCTION_NAME}" 
    echo "  ✅ IAM Role: ${IAM_ROLE_NAME}"
    echo "  ✅ CloudWatch Log Groups"
    echo "  ✅ Local temporary files"
    echo
    echo "All resources from the Simple Password Generator deployment have been successfully removed."
    echo
}

# Main execution
main() {
    log_info "Starting cleanup of Simple Password Generator with Lambda and S3"
    echo
    
    # Check if dry run is requested
    if [[ "${1:-}" == "--dry-run" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        load_environment
        echo
        echo "Resources that would be deleted:"
        echo "  - S3 Bucket: ${BUCKET_NAME}"
        echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
        echo "  - IAM Role: ${IAM_ROLE_NAME}"
        echo "  - CloudWatch Log Groups"
        echo "  - Local temporary files"
        return 0
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_environment
    confirm_deletion "$@"
    
    echo
    log_info "Starting resource cleanup..."
    
    # Delete resources in reverse order of creation
    delete_lambda_function
    delete_s3_bucket
    delete_iam_role
    cleanup_local_files
    verify_cleanup
    display_summary
    
    log_success "All resources have been successfully removed!"
}

# Handle script interruption
trap 'log_error "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function with all arguments
main "$@"