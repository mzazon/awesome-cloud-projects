#!/bin/bash

# Simple Image Metadata Extractor with Lambda and S3 - Cleanup Script
# This script removes all resources created by the deployment script

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
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [ ! -f "./deployment-info.json" ]; then
        log_error "deployment-info.json not found in current directory"
        log_error "This file is created during deployment and contains resource identifiers"
        log_error "Please run this script from the same directory where you ran deploy.sh"
        exit 1
    fi
    
    # Extract values from deployment info JSON
    export AWS_REGION=$(python3 -c "import json; print(json.load(open('deployment-info.json'))['aws_region'])" 2>/dev/null || echo "")
    export AWS_ACCOUNT_ID=$(python3 -c "import json; print(json.load(open('deployment-info.json'))['aws_account_id'])" 2>/dev/null || echo "")
    export BUCKET_NAME=$(python3 -c "import json; print(json.load(open('deployment-info.json'))['bucket_name'])" 2>/dev/null || echo "")
    export FUNCTION_NAME=$(python3 -c "import json; print(json.load(open('deployment-info.json'))['function_name'])" 2>/dev/null || echo "")
    export ROLE_NAME=$(python3 -c "import json; print(json.load(open('deployment-info.json'))['role_name'])" 2>/dev/null || echo "")
    export LAYER_NAME=$(python3 -c "import json; print(json.load(open('deployment-info.json'))['layer_name'])" 2>/dev/null || echo "")
    export LAYER_ARN=$(python3 -c "import json; print(json.load(open('deployment-info.json'))['layer_arn'])" 2>/dev/null || echo "")
    
    # Validate that we have the required information
    if [ -z "$BUCKET_NAME" ] || [ -z "$FUNCTION_NAME" ] || [ -z "$ROLE_NAME" ]; then
        log_error "Unable to load required deployment information from deployment-info.json"
        exit 1
    fi
    
    log_success "Deployment information loaded"
    log_info "Bucket: ${BUCKET_NAME}"
    log_info "Function: ${FUNCTION_NAME}"
    log_info "Role: ${ROLE_NAME}"
    if [ -n "$LAYER_NAME" ]; then
        log_info "Layer: ${LAYER_NAME}"
    fi
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "===== RESOURCE DESTRUCTION WARNING ====="
    log_warning "This script will PERMANENTLY DELETE the following resources:"
    log_warning "  • S3 Bucket: ${BUCKET_NAME} (and ALL its contents)"
    log_warning "  • Lambda Function: ${FUNCTION_NAME}"
    log_warning "  • IAM Role: ${ROLE_NAME}"
    if [ -n "$LAYER_NAME" ]; then
        log_warning "  • Lambda Layer: ${LAYER_NAME}"
    fi
    log_warning ""
    log_warning "This action CANNOT be undone!"
    log_warning "============================================="
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    echo
    if [[ ! $REPLY == "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Function to remove S3 event trigger
remove_s3_trigger() {
    log_info "Removing S3 event trigger configuration..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket ${BUCKET_NAME} 2>/dev/null; then
        # Remove S3 notification configuration
        aws s3api put-bucket-notification-configuration \
            --bucket ${BUCKET_NAME} \
            --notification-configuration '{}' || {
            log_warning "Failed to remove S3 notification configuration (may not exist)"
        }
        log_success "S3 event trigger configuration removed"
    else
        log_warning "Bucket ${BUCKET_NAME} does not exist or is not accessible"
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    log_info "Deleting Lambda function: ${FUNCTION_NAME}"
    
    # Check if function exists
    if aws lambda get-function --function-name ${FUNCTION_NAME} &>/dev/null; then
        # Remove Lambda permission for S3 (if it exists)
        aws lambda remove-permission \
            --function-name ${FUNCTION_NAME} \
            --statement-id s3-trigger-permission 2>/dev/null || {
            log_warning "Lambda permission for S3 not found (may have been removed already)"
        }
        
        # Delete Lambda function
        aws lambda delete-function --function-name ${FUNCTION_NAME}
        log_success "Lambda function deleted: ${FUNCTION_NAME}"
    else
        log_warning "Lambda function ${FUNCTION_NAME} does not exist"
    fi
}

# Function to delete Lambda layer
delete_lambda_layer() {
    if [ -n "$LAYER_ARN" ] && [ -n "$LAYER_NAME" ]; then
        log_info "Deleting Lambda layer: ${LAYER_NAME}"
        
        # Extract layer version from ARN
        LAYER_VERSION=$(echo ${LAYER_ARN} | cut -d: -f8)
        
        if [ -n "$LAYER_VERSION" ] && [ "$LAYER_VERSION" != "" ]; then
            # Check if layer version exists
            if aws lambda get-layer-version --layer-name ${LAYER_NAME} --version-number ${LAYER_VERSION} &>/dev/null; then
                aws lambda delete-layer-version \
                    --layer-name ${LAYER_NAME} \
                    --version-number ${LAYER_VERSION}
                log_success "Lambda layer deleted: ${LAYER_NAME} (version ${LAYER_VERSION})"
            else
                log_warning "Lambda layer version ${LAYER_VERSION} does not exist"
            fi
        else
            log_warning "Could not extract layer version from ARN: ${LAYER_ARN}"
        fi
    else
        log_warning "Layer information not available, skipping layer deletion"
    fi
}

# Function to delete IAM role and policies
delete_iam_role() {
    log_info "Deleting IAM role and policies: ${ROLE_NAME}"
    
    # Check if role exists
    if aws iam get-role --role-name ${ROLE_NAME} &>/dev/null; then
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name ${ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || {
            log_warning "Failed to detach AWSLambdaBasicExecutionRole (may not be attached)"
        }
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name ${ROLE_NAME} \
            --policy-name S3ReadPolicy 2>/dev/null || {
            log_warning "Failed to delete S3ReadPolicy (may not exist)"
        }
        
        # Delete IAM role
        aws iam delete-role --role-name ${ROLE_NAME}
        log_success "IAM role and policies deleted: ${ROLE_NAME}"
    else
        log_warning "IAM role ${ROLE_NAME} does not exist"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log_info "Deleting S3 bucket: ${BUCKET_NAME}"
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket ${BUCKET_NAME} 2>/dev/null; then
        # First, remove all objects from the bucket (including versions)
        log_info "Removing all objects from bucket..."
        
        # Remove all object versions and delete markers
        aws s3api list-object-versions --bucket ${BUCKET_NAME} --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text | while read key version; do
            if [ -n "$key" ] && [ -n "$version" ]; then
                aws s3api delete-object --bucket ${BUCKET_NAME} --key "$key" --version-id "$version" &>/dev/null || true
            fi
        done
        
        aws s3api list-object-versions --bucket ${BUCKET_NAME} --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text | while read key version; do
            if [ -n "$key" ] && [ -n "$version" ]; then
                aws s3api delete-object --bucket ${BUCKET_NAME} --key "$key" --version-id "$version" &>/dev/null || true
            fi
        done
        
        # Remove any remaining objects (fallback)
        aws s3 rm s3://${BUCKET_NAME} --recursive &>/dev/null || true
        
        # Delete the bucket
        aws s3 rb s3://${BUCKET_NAME}
        log_success "S3 bucket deleted: ${BUCKET_NAME}"
    else
        log_warning "S3 bucket ${BUCKET_NAME} does not exist or is not accessible"
    fi
}

# Function to clean up deployment info file
cleanup_deployment_info() {
    log_info "Cleaning up deployment information file..."
    
    if [ -f "./deployment-info.json" ]; then
        rm -f ./deployment-info.json
        log_success "Deployment information file removed"
    fi
}

# Function to verify resource deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local errors=0
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket ${BUCKET_NAME} 2>/dev/null; then
        log_error "S3 bucket ${BUCKET_NAME} still exists"
        ((errors++))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name ${FUNCTION_NAME} &>/dev/null; then
        log_error "Lambda function ${FUNCTION_NAME} still exists"
        ((errors++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name ${ROLE_NAME} &>/dev/null; then
        log_error "IAM role ${ROLE_NAME} still exists"
        ((errors++))
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "All resources have been successfully deleted"
        return 0
    else
        log_error "Some resources may not have been deleted properly"
        log_error "Please check the AWS console and manually remove any remaining resources"
        return 1
    fi
}

# Function to display cleanup summary
display_summary() {
    log_success "===== CLEANUP COMPLETE ====="
    log_info "Resources removed:"
    log_info "  • S3 Bucket: ${BUCKET_NAME}"
    log_info "  • Lambda Function: ${FUNCTION_NAME}"
    log_info "  • IAM Role: ${ROLE_NAME}"
    if [ -n "$LAYER_NAME" ]; then
        log_info "  • Lambda Layer: ${LAYER_NAME}"
    fi
    log_info "  • Deployment information file"
    log_info ""
    log_info "All resources have been successfully removed."
    log_info "You will no longer be charged for these resources."
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Simple Image Metadata Extractor resources"
    log_info "============================================================"
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_info
    confirm_destruction
    
    # Remove resources in reverse order of creation
    remove_s3_trigger
    delete_lambda_function
    delete_lambda_layer
    delete_iam_role
    delete_s3_bucket
    cleanup_deployment_info
    
    # Verify cleanup
    if verify_deletion; then
        display_summary
        log_success "Cleanup completed successfully!"
    else
        log_error "Cleanup completed with some errors. Please check the output above."
        exit 1
    fi
}

# Handle script interruption
trap 'log_error "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"