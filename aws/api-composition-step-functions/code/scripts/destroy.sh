#!/bin/bash

# AWS API Composition with Step Functions and API Gateway - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Script metadata
SCRIPT_NAME="destroy.sh"
SCRIPT_VERSION="1.0"
RECIPE_NAME="api-composition-step-functions-api-gateway"

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

log_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}================================${NC}"
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local region="${3:-$AWS_REGION}"
    
    case "$resource_type" in
        "dynamodb-table")
            aws dynamodb describe-table --table-name "$resource_name" --region "$region" &> /dev/null
            ;;
        "lambda-function")
            aws lambda get-function --function-name "$resource_name" --region "$region" &> /dev/null
            ;;
        "step-function")
            aws stepfunctions describe-state-machine --state-machine-arn "$resource_name" --region "$region" &> /dev/null
            ;;
        "api-gateway")
            aws apigateway get-rest-api --rest-api-id "$resource_name" --region "$region" &> /dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to wait for resource deletion
wait_for_resource_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local max_attempts="${3:-30}"
    local attempt=0
    
    log_info "Waiting for $resource_type deletion to complete..."
    
    while [[ $attempt -lt $max_attempts ]]; do
        if ! resource_exists "$resource_type" "$resource_name"; then
            log_success "$resource_type deleted successfully"
            return 0
        fi
        
        ((attempt++))
        echo -n "."
        sleep 5
    done
    
    echo
    log_warning "$resource_type deletion may have failed or is taking longer than expected"
    return 1
}

# Load environment variables from deployment
load_environment() {
    log_header "Loading Environment"
    
    if [[ ! -f .deployment_env ]]; then
        log_error "Deployment environment file (.deployment_env) not found."
        log_error "This script requires the environment file created during deployment."
        
        # Prompt user for manual cleanup if env file is missing
        echo
        log_warning "Would you like to attempt manual cleanup? (requires manual input of resource names)"
        read -p "Continue with manual cleanup? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
        
        manual_cleanup
        exit $?
    fi
    
    # Source the environment file
    source .deployment_env
    
    log_info "Loaded environment variables:"
    log_info "  AWS Region: ${AWS_REGION:-Not set}"
    log_info "  AWS Account ID: ${AWS_ACCOUNT_ID:-Not set}"
    log_info "  Project Name: ${PROJECT_NAME:-Not set}"
    log_info "  Random Suffix: ${RANDOM_SUFFIX:-Not set}"
    
    # Validate required variables
    if [[ -z "${AWS_REGION:-}" || -z "${AWS_ACCOUNT_ID:-}" || -z "${PROJECT_NAME:-}" ]]; then
        log_error "Required environment variables are missing from .deployment_env"
        exit 1
    fi
    
    log_success "Environment loaded successfully"
}

# Manual cleanup function when env file is missing
manual_cleanup() {
    log_header "Manual Cleanup Mode"
    
    log_warning "In manual mode, you'll need to provide resource names or patterns."
    log_warning "This mode will attempt to find and delete resources based on your input."
    
    read -p "Enter the project name pattern (e.g., api-composition): " PROJECT_PATTERN
    read -p "Enter the AWS region: " AWS_REGION
    
    if [[ -z "$PROJECT_PATTERN" || -z "$AWS_REGION" ]]; then
        log_error "Project pattern and region are required for manual cleanup"
        exit 1
    fi
    
    export AWS_REGION
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        log_error "Cannot retrieve AWS account ID. Check your credentials."
        exit 1
    fi
    
    log_info "Searching for resources with pattern: $PROJECT_PATTERN"
    
    # Find and delete DynamoDB tables
    log_info "Searching for DynamoDB tables..."
    TABLES=$(aws dynamodb list-tables --region "$AWS_REGION" --query "TableNames[?starts_with(@, '${PROJECT_PATTERN}')]" --output text 2>/dev/null || echo "")
    if [[ -n "$TABLES" ]]; then
        for table in $TABLES; do
            log_info "Found table: $table"
            delete_dynamodb_table "$table"
        done
    fi
    
    # Find and delete Lambda functions
    log_info "Searching for Lambda functions..."
    FUNCTIONS=$(aws lambda list-functions --region "$AWS_REGION" --query "Functions[?starts_with(FunctionName, '${PROJECT_PATTERN}')].FunctionName" --output text 2>/dev/null || echo "")
    if [[ -n "$FUNCTIONS" ]]; then
        for function in $FUNCTIONS; do
            log_info "Found function: $function"
            delete_lambda_function "$function"
        done
    fi
    
    # Find and delete Step Functions
    log_info "Searching for Step Functions..."
    STATE_MACHINES=$(aws stepfunctions list-state-machines --region "$AWS_REGION" --query "stateMachines[?contains(name, '${PROJECT_PATTERN}')].stateMachineArn" --output text 2>/dev/null || echo "")
    if [[ -n "$STATE_MACHINES" ]]; then
        for sm in $STATE_MACHINES; do
            log_info "Found state machine: $sm"
            delete_state_machine "$sm"
        done
    fi
    
    # Find and delete API Gateways
    log_info "Searching for API Gateways..."
    APIS=$(aws apigateway get-rest-apis --region "$AWS_REGION" --query "items[?contains(name, '${PROJECT_PATTERN}')].id" --output text 2>/dev/null || echo "")
    if [[ -n "$APIS" ]]; then
        for api in $APIS; do
            log_info "Found API: $api"
            delete_api_gateway "$api"
        done
    fi
    
    log_warning "Manual cleanup completed. Please verify all resources have been deleted."
}

# Delete API Gateway
delete_api_gateway() {
    local api_id="${1:-$API_ID}"
    
    if [[ -z "$api_id" ]]; then
        log_warning "No API Gateway ID provided, skipping"
        return 0
    fi
    
    log_header "Deleting API Gateway"
    
    if resource_exists "api-gateway" "$api_id"; then
        log_info "Deleting API Gateway: $api_id"
        
        if aws apigateway delete-rest-api \
            --rest-api-id "$api_id" \
            --region "$AWS_REGION" 2>/dev/null; then
            log_success "API Gateway deletion initiated"
        else
            log_warning "Failed to delete API Gateway or it may not exist"
        fi
    else
        log_info "API Gateway $api_id does not exist or was already deleted"
    fi
}

# Delete Step Functions State Machine
delete_state_machine() {
    local state_machine_arn="${1:-$STATE_MACHINE_ARN}"
    
    if [[ -z "$state_machine_arn" ]]; then
        # Try to construct ARN if not provided
        if [[ -n "${STATE_MACHINE_NAME:-}" ]]; then
            state_machine_arn="arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}"
        else
            log_warning "No Step Functions State Machine ARN provided, skipping"
            return 0
        fi
    fi
    
    log_header "Deleting Step Functions State Machine"
    
    if resource_exists "step-function" "$state_machine_arn"; then
        log_info "Deleting Step Functions state machine: $state_machine_arn"
        
        # First, stop any running executions
        log_info "Checking for running executions..."
        RUNNING_EXECUTIONS=$(aws stepfunctions list-executions \
            --state-machine-arn "$state_machine_arn" \
            --status-filter RUNNING \
            --region "$AWS_REGION" \
            --query 'executions[].executionArn' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$RUNNING_EXECUTIONS" ]]; then
            log_info "Stopping running executions..."
            for execution in $RUNNING_EXECUTIONS; do
                aws stepfunctions stop-execution \
                    --execution-arn "$execution" \
                    --region "$AWS_REGION" 2>/dev/null || log_warning "Failed to stop execution: $execution"
            done
            sleep 5
        fi
        
        if aws stepfunctions delete-state-machine \
            --state-machine-arn "$state_machine_arn" \
            --region "$AWS_REGION" 2>/dev/null; then
            log_success "Step Functions state machine deletion initiated"
        else
            log_warning "Failed to delete Step Functions state machine or it may not exist"
        fi
    else
        log_info "Step Functions state machine does not exist or was already deleted"
    fi
}

# Delete Lambda Functions
delete_lambda_functions() {
    log_header "Deleting Lambda Functions"
    
    local functions=(
        "${PROJECT_NAME}-user-service"
        "${PROJECT_NAME}-inventory-service"
    )
    
    for function_name in "${functions[@]}"; do
        delete_lambda_function "$function_name"
    done
}

delete_lambda_function() {
    local function_name="$1"
    
    if resource_exists "lambda-function" "$function_name"; then
        log_info "Deleting Lambda function: $function_name"
        
        if aws lambda delete-function \
            --function-name "$function_name" \
            --region "$AWS_REGION" 2>/dev/null; then
            log_success "Lambda function $function_name deleted"
        else
            log_warning "Failed to delete Lambda function: $function_name"
        fi
    else
        log_info "Lambda function $function_name does not exist or was already deleted"
    fi
}

# Delete DynamoDB Tables
delete_dynamodb_tables() {
    log_header "Deleting DynamoDB Tables"
    
    local tables=(
        "${PROJECT_NAME}-orders"
        "${PROJECT_NAME}-audit"
    )
    
    for table_name in "${tables[@]}"; do
        delete_dynamodb_table "$table_name"
    done
}

delete_dynamodb_table() {
    local table_name="$1"
    
    if resource_exists "dynamodb-table" "$table_name"; then
        log_info "Deleting DynamoDB table: $table_name"
        
        if aws dynamodb delete-table \
            --table-name "$table_name" \
            --region "$AWS_REGION" > /dev/null 2>&1; then
            log_success "DynamoDB table $table_name deletion initiated"
            wait_for_resource_deletion "dynamodb-table" "$table_name" 60
        else
            log_warning "Failed to delete DynamoDB table: $table_name"
        fi
    else
        log_info "DynamoDB table $table_name does not exist or was already deleted"
    fi
}

# Delete IAM Roles
delete_iam_roles() {
    log_header "Deleting IAM Roles"
    
    local roles=(
        "${ROLE_NAME:-StepFunctionsCompositionRole-${RANDOM_SUFFIX}}"
        "APIGatewayStepFunctionsRole-${RANDOM_SUFFIX}"
        "lambda-execution-role"
    )
    
    for role_name in "${roles[@]}"; do
        delete_iam_role "$role_name"
    done
}

delete_iam_role() {
    local role_name="$1"
    
    if [[ -z "$role_name" ]]; then
        log_warning "No IAM role name provided, skipping"
        return 0
    fi
    
    if resource_exists "iam-role" "$role_name"; then
        log_info "Deleting IAM role: $role_name"
        
        # Detach all managed policies
        log_info "Detaching managed policies from role: $role_name"
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        for policy_arn in $ATTACHED_POLICIES; do
            if [[ -n "$policy_arn" ]]; then
                aws iam detach-role-policy \
                    --role-name "$role_name" \
                    --policy-arn "$policy_arn" 2>/dev/null || log_warning "Failed to detach policy: $policy_arn"
            fi
        done
        
        # Delete all inline policies
        log_info "Deleting inline policies from role: $role_name"
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$role_name" \
            --query 'PolicyNames' \
            --output text 2>/dev/null || echo "")
        
        for policy_name in $INLINE_POLICIES; do
            if [[ -n "$policy_name" && "$policy_name" != "None" ]]; then
                aws iam delete-role-policy \
                    --role-name "$role_name" \
                    --policy-name "$policy_name" 2>/dev/null || log_warning "Failed to delete inline policy: $policy_name"
            fi
        done
        
        # Delete the role
        if aws iam delete-role --role-name "$role_name" 2>/dev/null; then
            log_success "IAM role $role_name deleted"
        else
            log_warning "Failed to delete IAM role: $role_name"
        fi
    else
        log_info "IAM role $role_name does not exist or was already deleted"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_header "Cleaning Up Local Files"
    
    local files_to_remove=(
        ".deployment_env"
        "trust-policy.json"
        "composition-policy.json"
        "apigw-trust-policy.json"
        "lambda-trust-policy.json"
        "state-machine-definition.json"
        "enhanced-state-machine.json"
        "user-service.py"
        "inventory-service.py"
        "user-service.zip"
        "inventory-service.zip"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "Removing file: $file"
            rm -f "$file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log_header "Verifying Cleanup"
    
    local issues=0
    
    # Check if any resources still exist
    if [[ -n "${PROJECT_NAME:-}" ]]; then
        # Check DynamoDB tables
        REMAINING_TABLES=$(aws dynamodb list-tables \
            --region "$AWS_REGION" \
            --query "TableNames[?starts_with(@, '${PROJECT_NAME}')]" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$REMAINING_TABLES" ]]; then
            log_warning "Remaining DynamoDB tables found: $REMAINING_TABLES"
            ((issues++))
        fi
        
        # Check Lambda functions
        REMAINING_FUNCTIONS=$(aws lambda list-functions \
            --region "$AWS_REGION" \
            --query "Functions[?starts_with(FunctionName, '${PROJECT_NAME}')].FunctionName" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$REMAINING_FUNCTIONS" ]]; then
            log_warning "Remaining Lambda functions found: $REMAINING_FUNCTIONS"
            ((issues++))
        fi
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_success "Cleanup verification completed - no remaining resources detected"
    else
        log_warning "Cleanup verification found $issues potential issues"
        log_warning "Please check the AWS console to manually remove any remaining resources"
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    log_header "Cleanup Summary"
    
    echo -e "${GREEN}✅ Cleanup completed!${NC}"
    echo
    echo "Resources removed:"
    echo "  • API Gateway and related resources"
    echo "  • Step Functions state machine"
    echo "  • Lambda functions (user-service, inventory-service)"
    echo "  • DynamoDB tables (orders, audit)"
    echo "  • IAM roles and policies"
    echo "  • Local temporary files"
    echo
    echo "Please verify in the AWS console that all resources have been removed."
    echo "Some resources may take a few minutes to fully delete."
    echo
    log_info "If you encounter any issues, you can manually delete resources using the AWS console."
}

# Confirmation prompt
confirm_destruction() {
    log_header "AWS API Composition Cleanup - $SCRIPT_VERSION"
    
    echo -e "${RED}⚠️  WARNING: This will permanently delete ALL resources created by the deployment script.${NC}"
    echo
    echo "Resources to be deleted:"
    echo "  • API Gateway: ${API_NAME:-Unknown}"
    echo "  • Step Functions: ${STATE_MACHINE_NAME:-Unknown}"
    echo "  • Lambda Functions: ${PROJECT_NAME:-Unknown}-user-service, ${PROJECT_NAME:-Unknown}-inventory-service"
    echo "  • DynamoDB Tables: ${PROJECT_NAME:-Unknown}-orders, ${PROJECT_NAME:-Unknown}-audit"
    echo "  • IAM Roles and Policies"
    echo
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    echo
    
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Type 'DELETE' to confirm: " confirm
    if [[ "$confirm" != "DELETE" ]]; then
        log_info "Cleanup cancelled - confirmation not received"
        exit 0
    fi
}

# Check prerequisites
check_prerequisites() {
    log_header "Checking Prerequisites"
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Main cleanup function
main() {
    check_prerequisites
    load_environment
    confirm_destruction
    
    log_info "Starting resource cleanup..."
    
    # Delete resources in reverse order of creation
    delete_api_gateway
    delete_state_machine
    delete_lambda_functions
    delete_dynamodb_tables
    delete_iam_roles
    cleanup_local_files
    verify_cleanup
    show_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi