#!/bin/bash

# Simple File Validation with S3 and Lambda - Cleanup Script
# This script removes all AWS resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output formatting
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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log_info "Checking AWS authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not authenticated. Please run 'aws configure' first."
        exit 1
    fi
    log_success "AWS authentication verified"
}

# Function to validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS authentication
    check_aws_auth
    
    log_success "All prerequisites validated"
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Check if .env file exists
    if [[ ! -f .env ]]; then
        log_error ".env file not found. Please run deploy.sh first or provide resource names manually."
        log_info "Creating .env file template..."
        cat > .env << 'EOF'
# Fill in your resource names from the deployment
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=123456789012
UPLOAD_BUCKET_NAME=file-upload-xxxxxx
VALID_BUCKET_NAME=valid-files-xxxxxx
QUARANTINE_BUCKET_NAME=quarantine-files-xxxxxx
LAMBDA_FUNCTION_NAME=file-validator-xxxxxx
EOF
        log_error "Please update .env file with your actual resource names and run this script again."
        exit 1
    fi
    
    # Source environment variables
    source .env
    
    # Validate required variables
    if [[ -z "$AWS_REGION" || -z "$AWS_ACCOUNT_ID" || -z "$UPLOAD_BUCKET_NAME" || 
          -z "$VALID_BUCKET_NAME" || -z "$QUARANTINE_BUCKET_NAME" || -z "$LAMBDA_FUNCTION_NAME" ]]; then
        log_error "Missing required environment variables in .env file"
        exit 1
    fi
    
    log_success "Environment variables loaded:"
    log_info "  Region: ${AWS_REGION}"
    log_info "  Account ID: ${AWS_ACCOUNT_ID}"
    log_info "  Upload bucket: ${UPLOAD_BUCKET_NAME}"
    log_info "  Valid bucket: ${VALID_BUCKET_NAME}"
    log_info "  Quarantine bucket: ${QUARANTINE_BUCKET_NAME}"
    log_info "  Lambda function: ${LAMBDA_FUNCTION_NAME}"
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "This will permanently delete the following AWS resources:"
    echo "  - S3 Bucket: ${UPLOAD_BUCKET_NAME} (and all contents)"
    echo "  - S3 Bucket: ${VALID_BUCKET_NAME} (and all contents)"
    echo "  - S3 Bucket: ${QUARANTINE_BUCKET_NAME} (and all contents)"
    echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  - IAM Role: ${LAMBDA_FUNCTION_NAME}-role"
    echo "  - IAM Policy: ${LAMBDA_FUNCTION_NAME}-s3-policy"
    echo
    
    # Interactive confirmation
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Function to remove S3 event notification
remove_s3_events() {
    log_info "Removing S3 event notifications..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "${UPLOAD_BUCKET_NAME}" >/dev/null 2>&1; then
        # Remove event notification configuration
        aws s3api put-bucket-notification-configuration \
            --bucket "${UPLOAD_BUCKET_NAME}" \
            --notification-configuration '{}' || \
        log_warning "Failed to remove S3 event notification or notification doesn't exist"
        
        log_success "S3 event notification removed"
    else
        log_warning "Upload bucket ${UPLOAD_BUCKET_NAME} does not exist"
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    log_info "Deleting Lambda function..."
    
    # Check if function exists
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1; then
        # Remove Lambda permission for S3 (if it exists)
        aws lambda remove-permission \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --statement-id s3-trigger-permission 2>/dev/null || \
        log_warning "Lambda permission not found or already removed"
        
        # Delete Lambda function
        aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}"
        log_success "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}"
    else
        log_warning "Lambda function ${LAMBDA_FUNCTION_NAME} does not exist"
    fi
}

# Function to remove IAM resources
remove_iam_resources() {
    log_info "Removing IAM resources..."
    
    # Get IAM role name
    ROLE_NAME="${LAMBDA_FUNCTION_NAME}-role"
    POLICY_NAME="${LAMBDA_FUNCTION_NAME}-s3-policy"
    POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    
    # Check if role exists
    if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
        # Detach AWS managed policy
        aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || \
        log_warning "Failed to detach basic execution policy or policy not attached"
        
        # Detach custom S3 policy
        aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn "${POLICY_ARN}" 2>/dev/null || \
        log_warning "Failed to detach S3 policy or policy not attached"
        
        # Delete IAM role
        aws iam delete-role --role-name "${ROLE_NAME}"
        log_success "IAM role deleted: ${ROLE_NAME}"
    else
        log_warning "IAM role ${ROLE_NAME} does not exist"
    fi
    
    # Check if custom policy exists and delete it
    if aws iam get-policy --policy-arn "${POLICY_ARN}" >/dev/null 2>&1; then
        aws iam delete-policy --policy-arn "${POLICY_ARN}"
        log_success "IAM policy deleted: ${POLICY_NAME}"
    else
        log_warning "IAM policy ${POLICY_NAME} does not exist"
    fi
}

# Function to empty and delete S3 buckets
delete_s3_buckets() {
    log_info "Deleting S3 buckets and contents..."
    
    # Function to empty and delete a bucket
    delete_bucket() {
        local bucket_name=$1
        
        if aws s3api head-bucket --bucket "${bucket_name}" >/dev/null 2>&1; then
            log_info "Emptying bucket: ${bucket_name}"
            
            # Remove all object versions and delete markers (for versioned buckets)
            aws s3api list-object-versions --bucket "${bucket_name}" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --output text | while read key version_id; do
                if [[ -n "$key" && -n "$version_id" ]]; then
                    aws s3api delete-object --bucket "${bucket_name}" --key "$key" --version-id "$version_id" >/dev/null
                fi
            done 2>/dev/null || log_warning "No object versions found in ${bucket_name}"
            
            # Remove delete markers
            aws s3api list-object-versions --bucket "${bucket_name}" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --output text | while read key version_id; do
                if [[ -n "$key" && -n "$version_id" ]]; then
                    aws s3api delete-object --bucket "${bucket_name}" --key "$key" --version-id "$version_id" >/dev/null
                fi
            done 2>/dev/null || log_warning "No delete markers found in ${bucket_name}"
            
            # Remove any remaining objects (for non-versioned objects)
            aws s3 rm "s3://${bucket_name}" --recursive >/dev/null 2>&1 || log_warning "No objects to remove from ${bucket_name}"
            
            # Delete the bucket
            aws s3 rb "s3://${bucket_name}"
            log_success "Bucket deleted: ${bucket_name}"
        else
            log_warning "Bucket ${bucket_name} does not exist"
        fi
    }
    
    # Delete all buckets
    delete_bucket "${UPLOAD_BUCKET_NAME}"
    delete_bucket "${VALID_BUCKET_NAME}"
    delete_bucket "${QUARANTINE_BUCKET_NAME}"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        "lambda-trust-policy.json"
        "s3-access-policy.json"
        "event-notification.json"
        "policy-arn.txt"
        "function.zip"
        "test-valid.txt"
        "test-invalid.exe"
        ".env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed: $file"
        fi
    done
    
    # Remove lambda function directory
    if [[ -d "lambda-function" ]]; then
        rm -rf "lambda-function"
        log_info "Removed: lambda-function directory"
    fi
    
    log_success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local cleanup_errors=0
    
    # Check Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" >/dev/null 2>&1; then
        log_error "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
        ((cleanup_errors++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${LAMBDA_FUNCTION_NAME}-role" >/dev/null 2>&1; then
        log_error "IAM role still exists: ${LAMBDA_FUNCTION_NAME}-role"
        ((cleanup_errors++))
    fi
    
    # Check IAM policy
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_FUNCTION_NAME}-s3-policy" >/dev/null 2>&1; then
        log_error "IAM policy still exists: ${LAMBDA_FUNCTION_NAME}-s3-policy"
        ((cleanup_errors++))
    fi
    
    # Check S3 buckets
    for bucket in "${UPLOAD_BUCKET_NAME}" "${VALID_BUCKET_NAME}" "${QUARANTINE_BUCKET_NAME}"; do
        if aws s3api head-bucket --bucket "${bucket}" >/dev/null 2>&1; then
            log_error "S3 bucket still exists: ${bucket}"
            ((cleanup_errors++))
        fi
    done
    
    if [[ $cleanup_errors -eq 0 ]]; then
        log_success "All resources have been successfully cleaned up"
    else
        log_error "Some resources may still exist. Please check manually."
        return 1
    fi
}

# Function to display cleanup summary
display_summary() {
    log_success "Cleanup completed!"
    echo
    log_info "Cleanup Summary:"
    log_info "  ✅ Lambda function removed"
    log_info "  ✅ IAM role and policies removed"
    log_info "  ✅ S3 buckets and contents removed"
    log_info "  ✅ S3 event notifications removed"
    log_info "  ✅ Local files cleaned up"
    echo
    log_info "All AWS resources for the Simple File Validation system have been removed."
    log_info "You can safely delete this directory if no longer needed."
    echo
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    log_error "An error occurred during cleanup. Some resources may still exist."
    log_info "Please check the AWS console manually and remove any remaining resources:"
    log_info "  - Lambda functions starting with '${LAMBDA_FUNCTION_NAME}'"
    log_info "  - IAM roles starting with '${LAMBDA_FUNCTION_NAME}'"
    log_info "  - S3 buckets: ${UPLOAD_BUCKET_NAME}, ${VALID_BUCKET_NAME}, ${QUARANTINE_BUCKET_NAME}"
    echo
    log_info "You can also re-run this script to attempt cleanup again."
}

# Main cleanup function
main() {
    log_info "Starting Simple File Validation cleanup..."
    
    # Set up error handling
    trap handle_cleanup_error ERR
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_destruction
    remove_s3_events
    delete_lambda_function
    remove_iam_resources
    delete_s3_buckets
    cleanup_local_files
    verify_cleanup
    display_summary
    
    log_success "Cleanup script completed successfully!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi