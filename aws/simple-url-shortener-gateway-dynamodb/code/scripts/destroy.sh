#!/bin/bash

# AWS Simple URL Shortener Cleanup Script
# Removes all resources created by the deployment script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging configuration
LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Command '$1' is required but not installed."
        exit 1
    fi
}

# Function to validate AWS credentials
validate_aws_credentials() {
    log_info "Validating AWS credentials..."
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    log_success "AWS credentials validated"
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "$resource_type" in
        "table")
            aws dynamodb describe-table --table-name "$resource_name" &>/dev/null
            ;;
        "role")
            aws iam get-role --role-name "$resource_name" &>/dev/null
            ;;
        "function")
            aws lambda get-function --function-name "$resource_name" &>/dev/null
            ;;
        "api")
            aws apigateway get-rest-api --rest-api-id "$resource_name" &>/dev/null
            ;;
        "policy")
            aws iam get-policy --policy-arn "$resource_name" &>/dev/null
            ;;
    esac
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for $resource_type '$resource_name' to be deleted..."
    
    while [ $attempt -le $max_attempts ]; do
        if ! resource_exists "$resource_type" "$resource_name"; then
            log_success "$resource_type '$resource_name' has been deleted"
            return 0
        fi
        
        log_info "Attempt $attempt/$max_attempts: $resource_type still exists, waiting..."
        sleep 10
        ((attempt++))
    done
    
    log_warning "$resource_type '$resource_name' may still exist after cleanup attempt"
    return 1
}

# Function to load deployment information
load_deployment_info() {
    if [[ -f "deployment-info.json" ]]; then
        log_info "Loading deployment information from deployment-info.json..."
        
        # Extract values from JSON using grep and sed (more portable than jq)
        export AWS_REGION=$(grep '"region"' deployment-info.json | sed 's/.*": "\([^"]*\)".*/\1/')
        export AWS_ACCOUNT_ID=$(grep '"accountId"' deployment-info.json | sed 's/.*": "\([^"]*\)".*/\1/')
        export TABLE_NAME=$(grep '"tableName"' deployment-info.json | sed 's/.*": "\([^"]*\)".*/\1/')
        export ROLE_NAME=$(grep '"roleName"' deployment-info.json | sed 's/.*": "\([^"]*\)".*/\1/')
        export CREATE_FUNCTION_NAME=$(grep '"createFunctionName"' deployment-info.json | sed 's/.*": "\([^"]*\)".*/\1/')
        export REDIRECT_FUNCTION_NAME=$(grep '"redirectFunctionName"' deployment-info.json | sed 's/.*": "\([^"]*\)".*/\1/')
        export API_NAME=$(grep '"apiName"' deployment-info.json | sed 's/.*": "\([^"]*\)".*/\1/')
        export API_ID=$(grep '"apiId"' deployment-info.json | sed 's/.*": "\([^"]*\)".*/\1/')
        
        log_success "Deployment information loaded successfully"
        return 0
    else
        log_warning "deployment-info.json not found. You'll need to provide resource names manually."
        return 1
    fi
}

# Function to prompt for manual resource names
prompt_for_resources() {
    log_info "Please provide the resource names to delete:"
    
    read -p "AWS Region: " AWS_REGION
    export AWS_REGION
    
    read -p "DynamoDB Table Name: " TABLE_NAME
    export TABLE_NAME
    
    read -p "IAM Role Name: " ROLE_NAME
    export ROLE_NAME
    
    read -p "Create Lambda Function Name: " CREATE_FUNCTION_NAME
    export CREATE_FUNCTION_NAME
    
    read -p "Redirect Lambda Function Name: " REDIRECT_FUNCTION_NAME
    export REDIRECT_FUNCTION_NAME
    
    read -p "API Gateway API ID: " API_ID
    export API_ID
    
    # Set account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
}

# Function to confirm destructive actions
confirm_deletion() {
    log_warning "This will permanently delete the following resources:"
    log_warning "- DynamoDB Table: ${TABLE_NAME}"
    log_warning "- Lambda Functions: ${CREATE_FUNCTION_NAME}, ${REDIRECT_FUNCTION_NAME}"
    log_warning "- IAM Role: ${ROLE_NAME}"
    log_warning "- API Gateway: ${API_ID}"
    log_warning "- Associated IAM Policies"
    log_warning ""
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to delete API Gateway
delete_api_gateway() {
    if [[ -n "${API_ID:-}" ]] && resource_exists "api" "${API_ID}"; then
        log_info "Step 1: Deleting API Gateway REST API..."
        
        if aws apigateway delete-rest-api --rest-api-id "${API_ID}"; then
            log_success "API Gateway ${API_ID} deletion initiated"
        else
            log_error "Failed to delete API Gateway ${API_ID}"
        fi
    else
        log_warning "API Gateway ${API_ID:-unknown} not found or already deleted"
    fi
}

# Function to delete Lambda functions
delete_lambda_functions() {
    # Delete create function
    if [[ -n "${CREATE_FUNCTION_NAME:-}" ]] && resource_exists "function" "${CREATE_FUNCTION_NAME}"; then
        log_info "Step 2: Deleting Lambda function for URL creation..."
        
        if aws lambda delete-function --function-name "${CREATE_FUNCTION_NAME}"; then
            log_success "Lambda function ${CREATE_FUNCTION_NAME} deleted"
        else
            log_error "Failed to delete Lambda function ${CREATE_FUNCTION_NAME}"
        fi
    else
        log_warning "Lambda function ${CREATE_FUNCTION_NAME:-unknown} not found or already deleted"
    fi
    
    # Delete redirect function
    if [[ -n "${REDIRECT_FUNCTION_NAME:-}" ]] && resource_exists "function" "${REDIRECT_FUNCTION_NAME}"; then
        log_info "Step 3: Deleting Lambda function for URL redirection..."
        
        if aws lambda delete-function --function-name "${REDIRECT_FUNCTION_NAME}"; then
            log_success "Lambda function ${REDIRECT_FUNCTION_NAME} deleted"
        else
            log_error "Failed to delete Lambda function ${REDIRECT_FUNCTION_NAME}"
        fi
    else
        log_warning "Lambda function ${REDIRECT_FUNCTION_NAME:-unknown} not found or already deleted"
    fi
}

# Function to delete IAM role and policies
delete_iam_resources() {
    if [[ -n "${ROLE_NAME:-}" ]] && resource_exists "role" "${ROLE_NAME}"; then
        log_info "Step 4: Deleting IAM role and policies..."
        
        # Detach basic Lambda execution policy
        log_info "Detaching AWS managed policy from role..."
        aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || log_warning "Basic execution policy already detached or not found"
        
        # Detach custom DynamoDB policy
        local dynamodb_policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-dynamodb-policy"
        if resource_exists "policy" "${dynamodb_policy_arn}"; then
            log_info "Detaching custom DynamoDB policy from role..."
            aws iam detach-role-policy \
                --role-name "${ROLE_NAME}" \
                --policy-arn "${dynamodb_policy_arn}" 2>/dev/null || log_warning "DynamoDB policy already detached"
        
            # Delete custom policy
            log_info "Deleting custom DynamoDB policy..."
            if aws iam delete-policy --policy-arn "${dynamodb_policy_arn}"; then
                log_success "Custom policy ${ROLE_NAME}-dynamodb-policy deleted"
            else
                log_error "Failed to delete custom policy ${ROLE_NAME}-dynamodb-policy"
            fi
        else
            log_warning "Custom DynamoDB policy not found or already deleted"
        fi
        
        # Delete IAM role
        log_info "Deleting IAM role..."
        if aws iam delete-role --role-name "${ROLE_NAME}"; then
            log_success "IAM role ${ROLE_NAME} deleted"
        else
            log_error "Failed to delete IAM role ${ROLE_NAME}"
        fi
    else
        log_warning "IAM role ${ROLE_NAME:-unknown} not found or already deleted"
    fi
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    if [[ -n "${TABLE_NAME:-}" ]] && resource_exists "table" "${TABLE_NAME}"; then
        log_info "Step 5: Deleting DynamoDB table..."
        
        if aws dynamodb delete-table --table-name "${TABLE_NAME}"; then
            log_success "DynamoDB table ${TABLE_NAME} deletion initiated"
            wait_for_deletion "table" "${TABLE_NAME}"
        else
            log_error "Failed to delete DynamoDB table ${TABLE_NAME}"
        fi
    else
        log_warning "DynamoDB table ${TABLE_NAME:-unknown} not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Step 6: Cleaning up local files..."
    
    # Remove temporary files that might be left over
    local files_to_remove=(
        "trust-policy.json"
        "dynamodb-policy.json"
        "create-function.py"
        "redirect-function.py"
        "create-function.zip"
        "redirect-function.zip"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Removed temporary file: $file"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Step 7: Verifying cleanup..."
    local cleanup_success=true
    
    # Check API Gateway
    if [[ -n "${API_ID:-}" ]] && resource_exists "api" "${API_ID}"; then
        log_error "API Gateway ${API_ID} still exists"
        cleanup_success=false
    fi
    
    # Check Lambda functions
    if [[ -n "${CREATE_FUNCTION_NAME:-}" ]] && resource_exists "function" "${CREATE_FUNCTION_NAME}"; then
        log_error "Lambda function ${CREATE_FUNCTION_NAME} still exists"
        cleanup_success=false
    fi
    
    if [[ -n "${REDIRECT_FUNCTION_NAME:-}" ]] && resource_exists "function" "${REDIRECT_FUNCTION_NAME}"; then
        log_error "Lambda function ${REDIRECT_FUNCTION_NAME} still exists"
        cleanup_success=false
    fi
    
    # Check IAM role
    if [[ -n "${ROLE_NAME:-}" ]] && resource_exists "role" "${ROLE_NAME}"; then
        log_error "IAM role ${ROLE_NAME} still exists"
        cleanup_success=false
    fi
    
    # Check DynamoDB table
    if [[ -n "${TABLE_NAME:-}" ]] && resource_exists "table" "${TABLE_NAME}"; then
        log_error "DynamoDB table ${TABLE_NAME} still exists"
        cleanup_success=false
    fi
    
    if [[ "$cleanup_success" == true ]]; then
        log_success "All resources have been successfully cleaned up"
    else
        log_warning "Some resources may still exist. Please check manually."
    fi
}

# Function to remove deployment info file
cleanup_deployment_info() {
    if [[ -f "deployment-info.json" ]]; then
        log_info "Removing deployment information file..."
        rm -f deployment-info.json
        log_success "deployment-info.json removed"
    fi
}

# Main cleanup function
main() {
    log_info "Starting AWS Simple URL Shortener cleanup..."
    log_info "Cleanup log: ${LOG_FILE}"
    
    # Prerequisites check
    log_info "Checking prerequisites..."
    check_command "aws"
    validate_aws_credentials
    
    # Load deployment information or prompt for manual input
    if ! load_deployment_info; then
        log_info "Attempting to load resource information manually..."
        prompt_for_resources
    fi
    
    # Validate that we have the necessary information
    if [[ -z "${TABLE_NAME:-}" ]] || [[ -z "${ROLE_NAME:-}" ]] || [[ -z "${CREATE_FUNCTION_NAME:-}" ]] || [[ -z "${REDIRECT_FUNCTION_NAME:-}" ]] || [[ -z "${API_ID:-}" ]]; then
        log_error "Missing required resource information. Cannot proceed with cleanup."
        exit 1
    fi
    
    log_info "Resource information:"
    log_info "- AWS Region: ${AWS_REGION}"
    log_info "- AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "- DynamoDB Table: ${TABLE_NAME}"
    log_info "- IAM Role: ${ROLE_NAME}"
    log_info "- Create Function: ${CREATE_FUNCTION_NAME}"
    log_info "- Redirect Function: ${REDIRECT_FUNCTION_NAME}"
    log_info "- API Gateway ID: ${API_ID}"
    
    # Confirm destructive actions
    confirm_deletion
    
    # Perform cleanup in reverse order of creation
    delete_api_gateway
    delete_lambda_functions
    delete_iam_resources
    delete_dynamodb_table
    cleanup_local_files
    verify_cleanup
    cleanup_deployment_info
    
    # Display cleanup summary
    log_success "============================================"
    log_success "AWS Simple URL Shortener Cleanup Complete!"
    log_success "============================================"
    log_success "All resources have been removed from your AWS account."
    log_success "Cleanup log saved to: ${LOG_FILE}"
    log_success ""
    log_success "If you need to re-deploy, run the deploy.sh script again."
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warning "Cleanup interrupted by user"
    log_info "Some resources may still exist in your AWS account"
    log_info "You can run this script again to complete the cleanup"
    exit 130
}

trap cleanup_on_interrupt SIGINT SIGTERM

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi