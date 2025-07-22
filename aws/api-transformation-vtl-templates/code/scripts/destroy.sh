#!/bin/bash

# Destroy script for Request/Response Transformation with VTL Templates and Custom Models
# This script safely removes all AWS resources created by the deployment

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_CONFIG="${SCRIPT_DIR}/deployment.config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Colored output functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it and try again."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load deployment configuration
load_deployment_config() {
    info "Loading deployment configuration..."
    
    if [ ! -f "${DEPLOYMENT_CONFIG}" ]; then
        error "Deployment configuration file not found: ${DEPLOYMENT_CONFIG}"
        error "Please ensure you've run ./deploy.sh first or the deployment was successful."
        exit 1
    fi
    
    # Source the configuration file
    source "${DEPLOYMENT_CONFIG}"
    
    # Verify required variables are set
    if [ -z "${API_ID:-}" ] || [ -z "${FUNCTION_NAME:-}" ] || [ -z "${BUCKET_NAME:-}" ] || [ -z "${LAMBDA_ROLE_NAME:-}" ]; then
        error "Missing required configuration variables. Please check ${DEPLOYMENT_CONFIG}"
        exit 1
    fi
    
    success "Deployment configuration loaded"
    info "API ID: ${API_ID}"
    info "Function Name: ${FUNCTION_NAME}"
    info "Bucket Name: ${BUCKET_NAME}"
    info "IAM Role: ${LAMBDA_ROLE_NAME}"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo -e "${YELLOW}WARNING: This will permanently delete the following resources:${NC}"
    echo "  - API Gateway: ${API_ID}"
    echo "  - Lambda Function: ${FUNCTION_NAME}"
    echo "  - S3 Bucket: ${BUCKET_NAME} (and all contents)"
    echo "  - IAM Role: ${LAMBDA_ROLE_NAME}"
    echo ""
    
    if [ "${1:-}" = "--force" ]; then
        warning "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    info "Destruction confirmed, proceeding..."
}

# Function to delete API Gateway
delete_api_gateway() {
    info "Deleting API Gateway..."
    
    if [ -z "${API_ID:-}" ]; then
        warning "API_ID not found in configuration, skipping API Gateway deletion"
        return 0
    fi
    
    # Check if API exists
    if aws apigateway get-rest-api --rest-api-id "${API_ID}" &>/dev/null; then
        # Delete API Gateway
        aws apigateway delete-rest-api --rest-api-id "${API_ID}"
        success "Deleted API Gateway: ${API_ID}"
        
        # Wait for deletion to complete
        info "Waiting for API Gateway deletion to complete..."
        local count=0
        while aws apigateway get-rest-api --rest-api-id "${API_ID}" &>/dev/null; do
            sleep 2
            count=$((count + 1))
            if [ $count -gt 30 ]; then
                warning "API Gateway deletion taking longer than expected"
                break
            fi
        done
        
        success "API Gateway deletion completed"
    else
        warning "API Gateway ${API_ID} not found or already deleted"
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    info "Deleting Lambda function..."
    
    if [ -z "${FUNCTION_NAME:-}" ]; then
        warning "FUNCTION_NAME not found in configuration, skipping Lambda deletion"
        return 0
    fi
    
    # Check if function exists
    if aws lambda get-function --function-name "${FUNCTION_NAME}" &>/dev/null; then
        # Remove API Gateway permission first
        aws lambda remove-permission \
            --function-name "${FUNCTION_NAME}" \
            --statement-id "api-gateway-transform-${RANDOM_SUFFIX}" \
            --output table 2>/dev/null || warning "Permission may not exist"
        
        # Delete Lambda function
        aws lambda delete-function --function-name "${FUNCTION_NAME}"
        success "Deleted Lambda function: ${FUNCTION_NAME}"
        
        # Wait for deletion to complete
        info "Waiting for Lambda function deletion to complete..."
        local count=0
        while aws lambda get-function --function-name "${FUNCTION_NAME}" &>/dev/null; do
            sleep 2
            count=$((count + 1))
            if [ $count -gt 30 ]; then
                warning "Lambda function deletion taking longer than expected"
                break
            fi
        done
        
        success "Lambda function deletion completed"
    else
        warning "Lambda function ${FUNCTION_NAME} not found or already deleted"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    info "Deleting S3 bucket..."
    
    if [ -z "${BUCKET_NAME:-}" ]; then
        warning "BUCKET_NAME not found in configuration, skipping S3 bucket deletion"
        return 0
    fi
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        # Delete all objects and versions in the bucket
        info "Removing all objects from bucket..."
        aws s3 rm s3://"${BUCKET_NAME}" --recursive 2>/dev/null || warning "No objects to delete"
        
        # Delete all object versions (if versioning is enabled)
        info "Removing all object versions..."
        aws s3api delete-objects --bucket "${BUCKET_NAME}" \
            --delete "$(aws s3api list-object-versions --bucket "${BUCKET_NAME}" \
                --output json --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" \
            2>/dev/null || warning "No versions to delete"
        
        # Delete all delete markers
        aws s3api delete-objects --bucket "${BUCKET_NAME}" \
            --delete "$(aws s3api list-object-versions --bucket "${BUCKET_NAME}" \
                --output json --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" \
            2>/dev/null || warning "No delete markers to remove"
        
        # Delete the bucket
        aws s3api delete-bucket --bucket "${BUCKET_NAME}"
        success "Deleted S3 bucket: ${BUCKET_NAME}"
        
        # Wait for deletion to complete
        info "Waiting for S3 bucket deletion to complete..."
        local count=0
        while aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; do
            sleep 2
            count=$((count + 1))
            if [ $count -gt 30 ]; then
                warning "S3 bucket deletion taking longer than expected"
                break
            fi
        done
        
        success "S3 bucket deletion completed"
    else
        warning "S3 bucket ${BUCKET_NAME} not found or already deleted"
    fi
}

# Function to delete IAM role
delete_iam_role() {
    info "Deleting IAM role..."
    
    if [ -z "${LAMBDA_ROLE_NAME:-}" ]; then
        warning "LAMBDA_ROLE_NAME not found in configuration, skipping IAM role deletion"
        return 0
    fi
    
    # Check if role exists
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &>/dev/null; then
        # Detach all policies from the role
        info "Detaching policies from IAM role..."
        
        # Get attached policies
        local attached_policies=$(aws iam list-attached-role-policies \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text)
        
        if [ ! -z "$attached_policies" ]; then
            for policy_arn in $attached_policies; do
                aws iam detach-role-policy \
                    --role-name "${LAMBDA_ROLE_NAME}" \
                    --policy-arn "$policy_arn"
                info "Detached policy: $policy_arn"
            done
        fi
        
        # Delete inline policies if any
        local inline_policies=$(aws iam list-role-policies \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --query 'PolicyNames' \
            --output text)
        
        if [ ! -z "$inline_policies" ]; then
            for policy_name in $inline_policies; do
                aws iam delete-role-policy \
                    --role-name "${LAMBDA_ROLE_NAME}" \
                    --policy-name "$policy_name"
                info "Deleted inline policy: $policy_name"
            done
        fi
        
        # Wait for policy detachment to propagate
        info "Waiting for policy detachment to propagate..."
        sleep 10
        
        # Delete the role
        aws iam delete-role --role-name "${LAMBDA_ROLE_NAME}"
        success "Deleted IAM role: ${LAMBDA_ROLE_NAME}"
        
        # Wait for deletion to complete
        info "Waiting for IAM role deletion to complete..."
        local count=0
        while aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &>/dev/null; do
            sleep 2
            count=$((count + 1))
            if [ $count -gt 30 ]; then
                warning "IAM role deletion taking longer than expected"
                break
            fi
        done
        
        success "IAM role deletion completed"
    else
        warning "IAM role ${LAMBDA_ROLE_NAME} not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # List of files to remove
    local files_to_remove=(
        "data-processor.py"
        "data-processor.zip"
        "request_template.vtl"
        "response_template.vtl"
        "error_template.vtl"
        "get_request_template.vtl"
        "validation_error_template.vtl"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "${SCRIPT_DIR}/${file}" ]; then
            rm -f "${SCRIPT_DIR}/${file}"
            info "Removed: ${file}"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to remove configuration files
remove_configuration_files() {
    info "Removing configuration files..."
    
    # Confirm removal of configuration files
    read -p "Remove deployment configuration file (${DEPLOYMENT_CONFIG})? [y/N]: " remove_config
    
    if [[ "$remove_config" =~ ^[Yy]$ ]]; then
        rm -f "${DEPLOYMENT_CONFIG}"
        info "Removed deployment configuration file"
    else
        info "Keeping deployment configuration file"
    fi
    
    # Ask about log file
    read -p "Remove deployment log file (${LOG_FILE})? [y/N]: " remove_log
    
    if [[ "$remove_log" =~ ^[Yy]$ ]]; then
        # Don't remove the current log file we're writing to
        info "Log file will be kept as it's currently in use"
    else
        info "Keeping deployment log file"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    info "Verifying cleanup..."
    
    local errors=0
    
    # Check API Gateway
    if [ ! -z "${API_ID:-}" ]; then
        if aws apigateway get-rest-api --rest-api-id "${API_ID}" &>/dev/null; then
            error "API Gateway ${API_ID} still exists"
            errors=$((errors + 1))
        else
            success "API Gateway ${API_ID} successfully deleted"
        fi
    fi
    
    # Check Lambda function
    if [ ! -z "${FUNCTION_NAME:-}" ]; then
        if aws lambda get-function --function-name "${FUNCTION_NAME}" &>/dev/null; then
            error "Lambda function ${FUNCTION_NAME} still exists"
            errors=$((errors + 1))
        else
            success "Lambda function ${FUNCTION_NAME} successfully deleted"
        fi
    fi
    
    # Check S3 bucket
    if [ ! -z "${BUCKET_NAME:-}" ]; then
        if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
            error "S3 bucket ${BUCKET_NAME} still exists"
            errors=$((errors + 1))
        else
            success "S3 bucket ${BUCKET_NAME} successfully deleted"
        fi
    fi
    
    # Check IAM role
    if [ ! -z "${LAMBDA_ROLE_NAME:-}" ]; then
        if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &>/dev/null; then
            error "IAM role ${LAMBDA_ROLE_NAME} still exists"
            errors=$((errors + 1))
        else
            success "IAM role ${LAMBDA_ROLE_NAME} successfully deleted"
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        success "All resources have been successfully cleaned up"
    else
        error "Some resources may still exist. Please check manually."
        return 1
    fi
}

# Function to display destruction summary
display_summary() {
    info "Destruction Summary:"
    echo "=========================================="
    echo "Resources Removed:"
    echo "  - API Gateway: ${API_ID:-N/A}"
    echo "  - Lambda Function: ${FUNCTION_NAME:-N/A}"
    echo "  - S3 Bucket: ${BUCKET_NAME:-N/A}"
    echo "  - IAM Role: ${LAMBDA_ROLE_NAME:-N/A}"
    echo "=========================================="
    echo ""
    echo "Cleanup completed successfully!"
    echo "All AWS resources have been removed."
    echo ""
    echo "Destruction log saved to: ${LOG_FILE}"
}

# Main destruction function
main() {
    info "Starting destruction of Request/Response Transformation API resources..."
    
    # Initialize log file
    echo "Destruction started at $(date)" > "${LOG_FILE}"
    
    # Parse command line arguments
    local force_mode=false
    if [ "${1:-}" = "--force" ]; then
        force_mode=true
    fi
    
    # Run destruction steps
    check_prerequisites
    load_deployment_config
    
    if [ "$force_mode" = true ]; then
        confirm_destruction --force
    else
        confirm_destruction
    fi
    
    # Delete resources in reverse order of creation
    delete_api_gateway
    delete_lambda_function
    delete_s3_bucket
    delete_iam_role
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Remove configuration files (with user confirmation)
    if [ "$force_mode" = false ]; then
        remove_configuration_files
    fi
    
    success "Destruction completed successfully!"
    display_summary
}

# Handle script interruption
cleanup_on_interrupt() {
    error "Script interrupted by user"
    error "Some resources may still exist. Please run the script again to complete cleanup."
    exit 1
}

trap cleanup_on_interrupt SIGINT SIGTERM

# Run main function
main "$@"