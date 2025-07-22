#!/bin/bash

# Destroy script for Asynchronous API Patterns with API Gateway and SQS
# This script safely removes all infrastructure components

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
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

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command '$1' not found. Please install it and try again."
        exit 1
    fi
}

# Function to check AWS CLI configuration
check_aws_config() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI not configured or credentials invalid. Please run 'aws configure' first."
        exit 1
    fi
}

# Function to confirm destructive action
confirm_destruction() {
    echo
    log_warning "⚠️  WARNING: This will delete ALL resources created by the async API deployment!"
    log_warning "This action cannot be undone and will permanently delete:"
    log_warning "- API Gateway and all endpoints"
    log_warning "- Lambda functions and their code"
    log_warning "- SQS queues and all messages"
    log_warning "- DynamoDB table and all data"
    log_warning "- S3 bucket and all stored results"
    log_warning "- IAM roles and policies"
    echo
    
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        log_info "Force destroy enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " confirm
    if [[ $confirm != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
}

# Function to load deployment info
load_deployment_info() {
    if [[ -f "deployment-info.txt" ]]; then
        log_info "Loading deployment information from deployment-info.txt..."
        source deployment-info.txt
    else
        log_warning "deployment-info.txt not found. You'll need to provide resource names manually."
        
        read -p "Enter project name (e.g., async-api-123456): " PROJECT_NAME
        if [[ -z "$PROJECT_NAME" ]]; then
            log_error "Project name is required"
            exit 1
        fi
        
        # Set derived names
        export MAIN_QUEUE_NAME="${PROJECT_NAME}-main-queue"
        export DLQ_NAME="${PROJECT_NAME}-dlq"
        export JOBS_TABLE_NAME="${PROJECT_NAME}-jobs"
        export RESULTS_BUCKET_NAME="${PROJECT_NAME}-results"
        export API_NAME="${PROJECT_NAME}-api"
    fi
    
    # Set AWS region and account if not already set
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
    
    log_info "Destroying resources for project: $PROJECT_NAME"
}

# Function to safely delete a resource with error handling
safe_delete() {
    local resource_type="$1"
    local delete_command="$2"
    local resource_name="$3"
    
    if eval "$delete_command" 2>/dev/null; then
        log_success "Deleted $resource_type: $resource_name"
    else
        log_warning "Failed to delete $resource_type: $resource_name (may not exist)"
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local check_command="$2"
    local resource_name="$3"
    local max_attempts="${4:-30}"
    local attempt=1
    
    log_info "Waiting for $resource_type '$resource_name' to be deleted..."
    
    while [ $attempt -le $max_attempts ]; do
        if ! eval "$check_command" &>/dev/null; then
            log_success "$resource_type '$resource_name' deleted successfully"
            return 0
        fi
        
        echo -n "."
        sleep 5
        ((attempt++))
    done
    
    log_warning "Timeout waiting for $resource_type '$resource_name' deletion"
    return 1
}

# Function to delete API Gateway
delete_api_gateway() {
    log_info "Deleting API Gateway..."
    
    if [[ -n "${API_ID}" ]]; then
        safe_delete "API Gateway" "aws apigateway delete-rest-api --rest-api-id ${API_ID}" "${API_ID}"
    else
        # Try to find API by name if ID not available
        local api_id=$(aws apigateway get-rest-apis --query "items[?name=='${API_NAME}'].id" --output text 2>/dev/null)
        if [[ -n "$api_id" && "$api_id" != "None" ]]; then
            safe_delete "API Gateway" "aws apigateway delete-rest-api --rest-api-id ${api_id}" "${api_id}"
        else
            log_warning "API Gateway not found or already deleted"
        fi
    fi
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log_info "Deleting Lambda functions..."
    
    # Delete job processor function
    safe_delete "Lambda function" \
        "aws lambda delete-function --function-name ${PROJECT_NAME}-job-processor" \
        "${PROJECT_NAME}-job-processor"
    
    # Delete status checker function
    safe_delete "Lambda function" \
        "aws lambda delete-function --function-name ${PROJECT_NAME}-status-checker" \
        "${PROJECT_NAME}-status-checker"
}

# Function to delete SQS queues
delete_sqs_queues() {
    log_info "Deleting SQS queues..."
    
    # Get queue URLs if not already available
    if [[ -z "${MAIN_QUEUE_URL}" ]]; then
        MAIN_QUEUE_URL=$(aws sqs get-queue-url --queue-name "${MAIN_QUEUE_NAME}" --query QueueUrl --output text 2>/dev/null || echo "")
    fi
    
    if [[ -z "${DLQ_URL}" ]]; then
        DLQ_URL=$(aws sqs get-queue-url --queue-name "${DLQ_NAME}" --query QueueUrl --output text 2>/dev/null || echo "")
    fi
    
    # Delete main queue
    if [[ -n "${MAIN_QUEUE_URL}" ]]; then
        safe_delete "SQS queue" "aws sqs delete-queue --queue-url ${MAIN_QUEUE_URL}" "${MAIN_QUEUE_NAME}"
    else
        log_warning "Main queue URL not found"
    fi
    
    # Delete dead letter queue
    if [[ -n "${DLQ_URL}" ]]; then
        safe_delete "SQS queue" "aws sqs delete-queue --queue-url ${DLQ_URL}" "${DLQ_NAME}"
    else
        log_warning "Dead letter queue URL not found"
    fi
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    log_info "Deleting DynamoDB table..."
    
    safe_delete "DynamoDB table" \
        "aws dynamodb delete-table --table-name ${JOBS_TABLE_NAME}" \
        "${JOBS_TABLE_NAME}"
    
    # Wait for table deletion
    if aws dynamodb describe-table --table-name "${JOBS_TABLE_NAME}" &>/dev/null; then
        wait_for_deletion "DynamoDB table" \
            "aws dynamodb describe-table --table-name ${JOBS_TABLE_NAME}" \
            "${JOBS_TABLE_NAME}" 60
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log_info "Deleting S3 bucket and contents..."
    
    # Check if bucket exists
    if aws s3 ls "s3://${RESULTS_BUCKET_NAME}" &>/dev/null; then
        log_info "Emptying S3 bucket: ${RESULTS_BUCKET_NAME}"
        aws s3 rm "s3://${RESULTS_BUCKET_NAME}" --recursive 2>/dev/null || log_warning "Failed to empty bucket contents"
        
        safe_delete "S3 bucket" \
            "aws s3 rb s3://${RESULTS_BUCKET_NAME}" \
            "${RESULTS_BUCKET_NAME}"
    else
        log_warning "S3 bucket not found or already deleted: ${RESULTS_BUCKET_NAME}"
    fi
}

# Function to delete IAM roles
delete_iam_roles() {
    log_info "Deleting IAM roles and policies..."
    
    # Delete API Gateway role
    log_info "Deleting API Gateway IAM role..."
    safe_delete "IAM role policy" \
        "aws iam delete-role-policy --role-name ${PROJECT_NAME}-api-gateway-role --policy-name SQSAccessPolicy" \
        "SQSAccessPolicy"
    
    safe_delete "IAM role" \
        "aws iam delete-role --role-name ${PROJECT_NAME}-api-gateway-role" \
        "${PROJECT_NAME}-api-gateway-role"
    
    # Delete Lambda role
    log_info "Deleting Lambda IAM role..."
    safe_delete "IAM role policy" \
        "aws iam delete-role-policy --role-name ${PROJECT_NAME}-lambda-role --policy-name LambdaAccessPolicy" \
        "LambdaAccessPolicy"
    
    safe_delete "IAM managed policy attachment" \
        "aws iam detach-role-policy --role-name ${PROJECT_NAME}-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "AWSLambdaBasicExecutionRole"
    
    safe_delete "IAM role" \
        "aws iam delete-role --role-name ${PROJECT_NAME}-lambda-role" \
        "${PROJECT_NAME}-lambda-role"
}

# Function to clean up deployment files
cleanup_deployment_files() {
    log_info "Cleaning up deployment files..."
    
    if [[ -f "deployment-info.txt" ]]; then
        rm -f deployment-info.txt
        log_success "Removed deployment-info.txt"
    fi
    
    # Remove any temporary files that might be left over
    if [[ -d "/tmp" ]]; then
        rm -f /tmp/job-processor.py /tmp/status-checker.py /tmp/job-processor.zip /tmp/status-checker.zip
        rm -f /tmp/api-gateway-trust-policy.json /tmp/lambda-trust-policy.json
        rm -f /tmp/sqs-policy.json /tmp/lambda-policy.json
        log_success "Cleaned up temporary files"
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local remaining_resources=0
    
    # Check API Gateway
    if aws apigateway get-rest-apis --query "items[?name=='${API_NAME}'].id" --output text 2>/dev/null | grep -q "."; then
        log_warning "API Gateway still exists"
        ((remaining_resources++))
    fi
    
    # Check Lambda functions
    if aws lambda get-function --function-name "${PROJECT_NAME}-job-processor" &>/dev/null; then
        log_warning "Job processor Lambda function still exists"
        ((remaining_resources++))
    fi
    
    if aws lambda get-function --function-name "${PROJECT_NAME}-status-checker" &>/dev/null; then
        log_warning "Status checker Lambda function still exists"
        ((remaining_resources++))
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "${JOBS_TABLE_NAME}" &>/dev/null; then
        log_warning "DynamoDB table still exists"
        ((remaining_resources++))
    fi
    
    # Check S3 bucket
    if aws s3 ls "s3://${RESULTS_BUCKET_NAME}" &>/dev/null; then
        log_warning "S3 bucket still exists"
        ((remaining_resources++))
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name "${PROJECT_NAME}-api-gateway-role" &>/dev/null; then
        log_warning "API Gateway IAM role still exists"
        ((remaining_resources++))
    fi
    
    if aws iam get-role --role-name "${PROJECT_NAME}-lambda-role" &>/dev/null; then
        log_warning "Lambda IAM role still exists"
        ((remaining_resources++))
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        log_success "All resources successfully deleted"
    else
        log_warning "$remaining_resources resources may still exist. Manual cleanup may be required."
        log_info "Please check the AWS console to verify all resources are deleted."
    fi
}

# Main destruction function
main() {
    log_info "Starting destruction of Asynchronous API Patterns infrastructure"
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    check_command "aws"
    check_aws_config
    
    # Load deployment information
    load_deployment_info
    
    # Confirm destruction
    confirm_destruction
    
    log_info "Beginning resource deletion..."
    echo
    
    # Delete resources in reverse order of creation to handle dependencies
    # 1. Delete API Gateway (stops new requests)
    delete_api_gateway
    
    # 2. Delete Lambda functions (stops processing)
    delete_lambda_functions
    
    # 3. Delete SQS queues (removes pending messages)
    delete_sqs_queues
    
    # 4. Delete DynamoDB table (removes job data)
    delete_dynamodb_table
    
    # 5. Delete S3 bucket (removes stored results)
    delete_s3_bucket
    
    # 6. Delete IAM roles (removes permissions)
    delete_iam_roles
    
    # 7. Clean up deployment files
    cleanup_deployment_files
    
    # 8. Verify cleanup
    verify_cleanup
    
    echo
    log_success "🗑️  Destruction completed!"
    log_info "All resources for project '${PROJECT_NAME}' have been removed."
    log_info "You should no longer incur charges for these resources."
    echo
    log_info "To verify complete cleanup, you can check the AWS console or run:"
    log_info "  aws apigateway get-rest-apis"
    log_info "  aws lambda list-functions"
    log_info "  aws sqs list-queues"
    log_info "  aws dynamodb list-tables"
    log_info "  aws s3 ls"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --force         Skip confirmation prompt (use with caution)"
    echo "  --help, -h      Show this help message"
    echo
    echo "Environment Variables:"
    echo "  FORCE_DESTROY   Set to 'true' to skip confirmation (same as --force)"
    echo
    echo "Examples:"
    echo "  $0                    # Interactive destruction with confirmation"
    echo "  $0 --force            # Automatic destruction without confirmation"
    echo "  FORCE_DESTROY=true $0 # Same as --force using environment variable"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi