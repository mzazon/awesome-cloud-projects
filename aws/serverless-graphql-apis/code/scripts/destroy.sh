#!/bin/bash

# Destroy script for Serverless GraphQL APIs with AWS AppSync and EventBridge Scheduler
# This script removes all infrastructure created by the deploy script
# Author: AWS Recipe Generator v1.3
# Last Updated: 2025-07-12

set -u  # Exit on undefined variables

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

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Check for deployment info file in current directory
    if [ -f "deployment-info.env" ]; then
        source deployment-info.env
        log_success "Loaded deployment info from current directory"
    elif [ -f "../deployment-info.env" ]; then
        source ../deployment-info.env
        log_success "Loaded deployment info from parent directory"
    else
        # Try to find deployment info files
        local info_files=$(find . -name "deployment-info.env" -type f 2>/dev/null | head -5)
        if [ -n "$info_files" ]; then
            echo "Found deployment info files:"
            echo "$info_files"
            read -p "Enter the path to the deployment-info.env file: " info_file
            if [ -f "$info_file" ]; then
                source "$info_file"
                log_success "Loaded deployment info from specified file"
            else
                log_error "File not found: $info_file"
                exit 1
            fi
        else
            log_error "No deployment-info.env file found"
            log_info "Please run this script from the directory containing deployment-info.env"
            log_info "Or provide the deployment information manually"
            exit 1
        fi
    fi
    
    # Validate required variables
    local required_vars=("AWS_REGION" "AWS_ACCOUNT_ID" "API_NAME" "TABLE_NAME" "FUNCTION_NAME" "SCHEDULER_ROLE" "APPSYNC_ROLE" "LAMBDA_ROLE")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            log_error "Required variable $var not found in deployment info"
            exit 1
        fi
    done
    
    log_success "Deployment information loaded successfully"
}

# Function to confirm destruction
confirm_destruction() {
    echo
    echo "=== DESTRUCTION CONFIRMATION ==="
    echo "This will permanently delete the following resources:"
    echo "- AppSync API: ${API_NAME} (${API_ID:-unknown})"
    echo "- DynamoDB Table: ${TABLE_NAME}"
    echo "- Lambda Function: ${FUNCTION_NAME}"
    echo "- IAM Roles: ${APPSYNC_ROLE}, ${LAMBDA_ROLE}, ${SCHEDULER_ROLE}"
    echo "- EventBridge Schedules (any created)"
    echo "- Region: ${AWS_REGION}"
    echo
    echo "⚠️  WARNING: This action is IRREVERSIBLE!"
    echo "⚠️  All data in the DynamoDB table will be permanently lost!"
    echo
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    # Double confirmation for safety
    echo
    read -p "Type 'DELETE' to confirm permanent deletion: " double_confirmation
    if [ "$double_confirmation" != "DELETE" ]; then
        log_info "Destruction cancelled - confirmation not matched"
        exit 0
    fi
    
    log_warning "Destruction confirmed - proceeding with resource deletion"
}

# Function to check AWS credentials
check_aws_credentials() {
    log_info "Checking AWS credentials..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or expired"
        exit 1
    fi
    
    local current_account=$(aws sts get-caller-identity --query Account --output text)
    if [ "$current_account" != "$AWS_ACCOUNT_ID" ]; then
        log_error "AWS account mismatch"
        log_error "Expected: $AWS_ACCOUNT_ID, Current: $current_account"
        exit 1
    fi
    
    local current_region=$(aws configure get region)
    if [ "$current_region" != "$AWS_REGION" ]; then
        log_warning "AWS region mismatch"
        log_warning "Expected: $AWS_REGION, Current: $current_region"
        log_info "Setting AWS_REGION for this session"
        export AWS_REGION
    fi
    
    log_success "AWS credentials validated"
}

# Function to delete EventBridge schedules
delete_eventbridge_schedules() {
    log_info "Deleting EventBridge schedules..."
    
    # List schedules with TaskReminder prefix
    local schedules=$(aws scheduler list-schedules \
        --name-prefix TaskReminder \
        --query 'Schedules[].Name' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$schedules" ]; then
        for schedule in $schedules; do
            log_info "Deleting schedule: $schedule"
            aws scheduler delete-schedule \
                --name "$schedule" \
                --output text &>/dev/null || log_warning "Failed to delete schedule: $schedule"
        done
        log_success "EventBridge schedules deleted"
    else
        log_info "No EventBridge schedules found to delete"
    fi
}

# Function to delete AppSync API
delete_appsync_api() {
    log_info "Deleting AppSync API..."
    
    if [ -n "${API_ID:-}" ]; then
        # Check if API exists
        if aws appsync get-graphql-api --api-id "${API_ID}" &>/dev/null; then
            aws appsync delete-graphql-api \
                --api-id "${API_ID}" \
                --output text &>/dev/null
            log_success "AppSync API deleted: ${API_ID}"
        else
            log_info "AppSync API not found or already deleted: ${API_ID}"
        fi
    else
        # Try to find API by name
        local api_id=$(aws appsync list-graphql-apis \
            --query "graphqlApis[?name=='${API_NAME}'].apiId" \
            --output text 2>/dev/null)
        
        if [ -n "$api_id" ] && [ "$api_id" != "None" ]; then
            aws appsync delete-graphql-api \
                --api-id "$api_id" \
                --output text &>/dev/null
            log_success "AppSync API deleted by name: ${API_NAME}"
        else
            log_info "AppSync API not found: ${API_NAME}"
        fi
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    log_info "Deleting Lambda function..."
    
    if aws lambda get-function --function-name "${FUNCTION_NAME}" &>/dev/null; then
        aws lambda delete-function \
            --function-name "${FUNCTION_NAME}" \
            --output text &>/dev/null
        log_success "Lambda function deleted: ${FUNCTION_NAME}"
    else
        log_info "Lambda function not found: ${FUNCTION_NAME}"
    fi
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    log_info "Deleting DynamoDB table..."
    
    if aws dynamodb describe-table --table-name "${TABLE_NAME}" &>/dev/null; then
        aws dynamodb delete-table \
            --table-name "${TABLE_NAME}" \
            --output text &>/dev/null
        
        log_info "Waiting for DynamoDB table deletion to complete..."
        # Wait for table to be deleted (with timeout)
        local max_attempts=30
        local attempt=0
        while [ $attempt -lt $max_attempts ]; do
            if ! aws dynamodb describe-table --table-name "${TABLE_NAME}" &>/dev/null; then
                log_success "DynamoDB table deleted: ${TABLE_NAME}"
                break
            fi
            sleep 10
            ((attempt++))
            log_info "Waiting for table deletion... (attempt $attempt/$max_attempts)"
        done
        
        if [ $attempt -eq $max_attempts ]; then
            log_warning "Table deletion timeout - table may still be deleting"
        fi
    else
        log_info "DynamoDB table not found: ${TABLE_NAME}"
    fi
}

# Function to delete IAM roles
delete_iam_roles() {
    log_info "Deleting IAM roles..."
    
    # Delete AppSync role
    if aws iam get-role --role-name "${APPSYNC_ROLE}" &>/dev/null; then
        # Delete inline policies first
        aws iam delete-role-policy \
            --role-name "${APPSYNC_ROLE}" \
            --policy-name DynamoDBAccess &>/dev/null || true
        
        # Delete role
        aws iam delete-role \
            --role-name "${APPSYNC_ROLE}" &>/dev/null
        log_success "AppSync IAM role deleted: ${APPSYNC_ROLE}"
    else
        log_info "AppSync IAM role not found: ${APPSYNC_ROLE}"
    fi
    
    # Delete Lambda role
    if aws iam get-role --role-name "${LAMBDA_ROLE}" &>/dev/null; then
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole &>/dev/null || true
        
        # Delete role
        aws iam delete-role \
            --role-name "${LAMBDA_ROLE}" &>/dev/null
        log_success "Lambda IAM role deleted: ${LAMBDA_ROLE}"
    else
        log_info "Lambda IAM role not found: ${LAMBDA_ROLE}"
    fi
    
    # Delete Scheduler role
    if aws iam get-role --role-name "${SCHEDULER_ROLE}" &>/dev/null; then
        # Delete inline policies first
        aws iam delete-role-policy \
            --role-name "${SCHEDULER_ROLE}" \
            --policy-name AppSyncAccess &>/dev/null || true
        
        # Delete role
        aws iam delete-role \
            --role-name "${SCHEDULER_ROLE}" &>/dev/null
        log_success "Scheduler IAM role deleted: ${SCHEDULER_ROLE}"
    else
        log_info "Scheduler IAM role not found: ${SCHEDULER_ROLE}"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Clean up current directory files
    local files_to_remove=(
        "deployment-info.env"
        "appsync-trust-policy.json"
        "appsync-policy.json"
        "lambda-trust-policy.json"
        "scheduler-trust-policy.json"
        "scheduler-policy.json"
        "schema.graphql"
        "create-task-request.vtl"
        "response.vtl"
        "lambda_function.py"
        "function.zip"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_info "Removed file: $file"
        fi
    done
    
    # Clean up working directory if specified and empty
    if [ -n "${WORK_DIR:-}" ] && [ -d "${WORK_DIR}" ]; then
        # Check if directory is empty (except hidden files)
        if [ -z "$(ls -A "${WORK_DIR}" 2>/dev/null | grep -v '^\.')" ]; then
            rmdir "${WORK_DIR}" 2>/dev/null || true
            log_info "Removed empty working directory: ${WORK_DIR}"
        else
            log_warning "Working directory not empty, skipping removal: ${WORK_DIR}"
        fi
    fi
    
    log_success "Local file cleanup completed"
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local issues=0
    
    # Check AppSync API
    if [ -n "${API_ID:-}" ] && aws appsync get-graphql-api --api-id "${API_ID}" &>/dev/null; then
        log_warning "AppSync API still exists: ${API_ID}"
        ((issues++))
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "${TABLE_NAME}" &>/dev/null; then
        log_warning "DynamoDB table still exists: ${TABLE_NAME}"
        ((issues++))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "${FUNCTION_NAME}" &>/dev/null; then
        log_warning "Lambda function still exists: ${FUNCTION_NAME}"
        ((issues++))
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name "${APPSYNC_ROLE}" &>/dev/null; then
        log_warning "AppSync IAM role still exists: ${APPSYNC_ROLE}"
        ((issues++))
    fi
    
    if aws iam get-role --role-name "${LAMBDA_ROLE}" &>/dev/null; then
        log_warning "Lambda IAM role still exists: ${LAMBDA_ROLE}"
        ((issues++))
    fi
    
    if aws iam get-role --role-name "${SCHEDULER_ROLE}" &>/dev/null; then
        log_warning "Scheduler IAM role still exists: ${SCHEDULER_ROLE}"
        ((issues++))
    fi
    
    if [ $issues -eq 0 ]; then
        log_success "All resources successfully deleted"
    else
        log_warning "Some resources may still exist ($issues issues found)"
        log_info "These resources may be in deletion state or require manual cleanup"
    fi
}

# Function to show destruction summary
show_destruction_summary() {
    echo
    echo "=== Destruction Summary ==="
    echo "✅ EventBridge schedules removed"
    echo "✅ AppSync API deleted: ${API_NAME}"
    echo "✅ Lambda function deleted: ${FUNCTION_NAME}"
    echo "✅ DynamoDB table deleted: ${TABLE_NAME}"
    echo "✅ IAM roles deleted"
    echo "✅ Local files cleaned up"
    echo
    echo "=== Important Notes ==="
    echo "• Some resources may take a few minutes to fully delete"
    echo "• Check the AWS console to verify complete removal"
    echo "• DynamoDB table deletion is permanent and cannot be undone"
    echo "• IAM role deletion may be delayed due to AWS propagation"
    echo
    log_success "Infrastructure destruction completed!"
}

# Main destruction function
main() {
    log_info "Starting destruction of Serverless GraphQL APIs infrastructure"
    
    load_deployment_info
    check_aws_credentials
    confirm_destruction
    
    log_warning "Beginning resource deletion..."
    
    delete_eventbridge_schedules
    delete_appsync_api
    delete_lambda_function
    delete_dynamodb_table
    delete_iam_roles
    cleanup_local_files
    verify_deletion
    show_destruction_summary
    
    log_success "Destruction script completed!"
}

# Handle script interruption
cleanup_on_error() {
    log_error "Destruction interrupted"
    log_warning "Some resources may have been partially deleted"
    log_info "Check the AWS console and re-run this script to complete cleanup"
    exit 1
}

# Set trap for error handling
trap cleanup_on_error INT TERM

# Run main function
main "$@"