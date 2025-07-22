#!/bin/bash

# Cleanup script for Saga Patterns with Step Functions for Distributed Transactions
# This script removes all resources created by the deployment script

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    warning "Running in DRY-RUN mode - no resources will be deleted"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local continue_on_error="${3:-false}"
    
    log "$description"
    
    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY-RUN: $cmd"
        return 0
    fi
    
    if ! eval "$cmd"; then
        if [ "$continue_on_error" = "true" ]; then
            warning "Command failed but continuing: $cmd"
            return 0
        else
            error "Failed to execute: $cmd"
            return 1
        fi
    fi
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case $resource_type in
        "dynamodb-table")
            aws dynamodb describe-table --table-name "$resource_name" &>/dev/null
            ;;
        "lambda-function")
            aws lambda get-function --function-name "$resource_name" &>/dev/null
            ;;
        "stepfunctions-state-machine")
            aws stepfunctions describe-state-machine --state-machine-arn "$resource_name" &>/dev/null
            ;;
        "apigateway-rest-api")
            aws apigateway get-rest-api --rest-api-id "$resource_name" &>/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" &>/dev/null
            ;;
        "sns-topic")
            aws sns get-topic-attributes --topic-arn "$resource_name" &>/dev/null
            ;;
        "logs-log-group")
            aws logs describe-log-groups --log-group-name-prefix "$resource_name" --query 'logGroups[0]' --output text &>/dev/null
            ;;
    esac
}

# Function to wait for resource deletion
wait_for_resource_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local max_attempts=30
    local attempt=0
    
    log "Waiting for $resource_type deletion: $resource_name"
    
    while [ $attempt -lt $max_attempts ]; do
        if ! resource_exists "$resource_type" "$resource_name"; then
            success "$resource_type $resource_name has been deleted"
            return 0
        fi
        
        attempt=$((attempt + 1))
        sleep 10
    done
    
    warning "Timeout waiting for $resource_type deletion: $resource_name"
    return 1
}

# Function to confirm destructive action
confirm_destroy() {
    if [ "$FORCE_DESTROY" = "true" ]; then
        return 0
    fi
    
    echo ""
    warning "This will permanently delete all Saga Pattern resources!"
    echo ""
    if [ -f "$ENV_FILE" ]; then
        echo "Resources to be deleted:"
        echo "======================"
        source "$ENV_FILE"
        echo "- DynamoDB Tables: $ORDER_TABLE_NAME, $INVENTORY_TABLE_NAME, $PAYMENT_TABLE_NAME"
        echo "- SNS Topic: $SAGA_TOPIC_NAME"
        echo "- Step Functions State Machine: $SAGA_STATE_MACHINE_NAME"
        echo "- Lambda Functions: 7 functions"
        echo "- API Gateway: ${API_ID:-Not found}"
        echo "- IAM Roles: 3 roles"
        echo "- CloudWatch Log Groups: 1 group"
        echo ""
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ ! -f "$ENV_FILE" ]; then
        error "Environment file not found: $ENV_FILE"
        echo "Please ensure the deployment script was run successfully or provide the environment file manually."
        exit 1
    fi
    
    source "$ENV_FILE"
    
    # Verify required variables
    local required_vars=(
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "RANDOM_SUFFIX"
        "ORDER_TABLE_NAME"
        "INVENTORY_TABLE_NAME"
        "PAYMENT_TABLE_NAME"
        "SAGA_TOPIC_NAME"
        "SAGA_STATE_MACHINE_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    success "Environment variables loaded successfully"
    log "Deployment suffix: $RANDOM_SUFFIX"
}

# Function to delete API Gateway
delete_api_gateway() {
    log "Deleting API Gateway..."
    
    if [ -n "$API_ID" ]; then
        if resource_exists "apigateway-rest-api" "$API_ID"; then
            execute_cmd "aws apigateway delete-rest-api --rest-api-id $API_ID" \
                "Deleting API Gateway REST API" true
        else
            log "API Gateway REST API not found: $API_ID"
        fi
    else
        log "API Gateway ID not found in environment"
    fi
    
    success "API Gateway cleanup completed"
}

# Function to delete Step Functions state machine
delete_step_functions() {
    log "Deleting Step Functions state machine..."
    
    if [ -n "$SAGA_STATE_MACHINE_ARN" ]; then
        if resource_exists "stepfunctions-state-machine" "$SAGA_STATE_MACHINE_ARN"; then
            execute_cmd "aws stepfunctions delete-state-machine --state-machine-arn $SAGA_STATE_MACHINE_ARN" \
                "Deleting Step Functions state machine" true
        else
            log "Step Functions state machine not found: $SAGA_STATE_MACHINE_ARN"
        fi
    else
        log "Step Functions state machine ARN not found in environment"
    fi
    
    success "Step Functions cleanup completed"
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    local functions=(
        "saga-order-service-${RANDOM_SUFFIX}"
        "saga-inventory-service-${RANDOM_SUFFIX}"
        "saga-payment-service-${RANDOM_SUFFIX}"
        "saga-notification-service-${RANDOM_SUFFIX}"
        "saga-cancel-order-${RANDOM_SUFFIX}"
        "saga-revert-inventory-${RANDOM_SUFFIX}"
        "saga-refund-payment-${RANDOM_SUFFIX}"
    )
    
    for function_name in "${functions[@]}"; do
        if resource_exists "lambda-function" "$function_name"; then
            execute_cmd "aws lambda delete-function --function-name $function_name" \
                "Deleting Lambda function: $function_name" true
        else
            log "Lambda function not found: $function_name"
        fi
    done
    
    success "Lambda functions cleanup completed"
}

# Function to delete DynamoDB tables
delete_dynamodb_tables() {
    log "Deleting DynamoDB tables..."
    
    local tables=(
        "$ORDER_TABLE_NAME"
        "$INVENTORY_TABLE_NAME"
        "$PAYMENT_TABLE_NAME"
    )
    
    for table_name in "${tables[@]}"; do
        if resource_exists "dynamodb-table" "$table_name"; then
            execute_cmd "aws dynamodb delete-table --table-name $table_name" \
                "Deleting DynamoDB table: $table_name" true
            
            if [ "$DRY_RUN" = "false" ]; then
                wait_for_resource_deletion "dynamodb-table" "$table_name"
            fi
        else
            log "DynamoDB table not found: $table_name"
        fi
    done
    
    success "DynamoDB tables cleanup completed"
}

# Function to delete SNS topic
delete_sns_topic() {
    log "Deleting SNS topic..."
    
    if [ -n "$SAGA_TOPIC_ARN" ]; then
        if resource_exists "sns-topic" "$SAGA_TOPIC_ARN"; then
            execute_cmd "aws sns delete-topic --topic-arn $SAGA_TOPIC_ARN" \
                "Deleting SNS topic: $SAGA_TOPIC_ARN" true
        else
            log "SNS topic not found: $SAGA_TOPIC_ARN"
        fi
    else
        log "SNS topic ARN not found in environment"
    fi
    
    success "SNS topic cleanup completed"
}

# Function to delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    local roles=(
        "saga-orchestrator-role-${RANDOM_SUFFIX}"
        "saga-lambda-role-${RANDOM_SUFFIX}"
        "saga-api-gateway-role-${RANDOM_SUFFIX}"
    )
    
    for role_name in "${roles[@]}"; do
        if resource_exists "iam-role" "$role_name"; then
            # Delete attached policies first
            log "Deleting policies for role: $role_name"
            
            # Get attached managed policies
            local attached_policies
            attached_policies=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            
            for policy_arn in $attached_policies; do
                execute_cmd "aws iam detach-role-policy --role-name $role_name --policy-arn $policy_arn" \
                    "Detaching policy $policy_arn from role $role_name" true
            done
            
            # Get inline policies
            local inline_policies
            inline_policies=$(aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
            
            for policy_name in $inline_policies; do
                execute_cmd "aws iam delete-role-policy --role-name $role_name --policy-name $policy_name" \
                    "Deleting inline policy $policy_name from role $role_name" true
            done
            
            # Delete the role
            execute_cmd "aws iam delete-role --role-name $role_name" \
                "Deleting IAM role: $role_name" true
        else
            log "IAM role not found: $role_name"
        fi
    done
    
    success "IAM roles cleanup completed"
}

# Function to delete CloudWatch log groups
delete_cloudwatch_logs() {
    log "Deleting CloudWatch log groups..."
    
    local log_group_name="/aws/stepfunctions/saga-logs-${RANDOM_SUFFIX}"
    
    if resource_exists "logs-log-group" "$log_group_name"; then
        execute_cmd "aws logs delete-log-group --log-group-name $log_group_name" \
            "Deleting CloudWatch log group: $log_group_name" true
    else
        log "CloudWatch log group not found: $log_group_name"
    fi
    
    success "CloudWatch logs cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "$ENV_FILE"
        "$SCRIPT_DIR/.code_complete"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            execute_cmd "rm -f $file" "Removing local file: $file" true
        fi
    done
    
    success "Local files cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=false
    
    # Check DynamoDB tables
    local tables=("$ORDER_TABLE_NAME" "$INVENTORY_TABLE_NAME" "$PAYMENT_TABLE_NAME")
    for table in "${tables[@]}"; do
        if resource_exists "dynamodb-table" "$table"; then
            error "DynamoDB table still exists: $table"
            cleanup_issues=true
        fi
    done
    
    # Check Lambda functions
    local functions=(
        "saga-order-service-${RANDOM_SUFFIX}"
        "saga-inventory-service-${RANDOM_SUFFIX}"
        "saga-payment-service-${RANDOM_SUFFIX}"
        "saga-notification-service-${RANDOM_SUFFIX}"
        "saga-cancel-order-${RANDOM_SUFFIX}"
        "saga-revert-inventory-${RANDOM_SUFFIX}"
        "saga-refund-payment-${RANDOM_SUFFIX}"
    )
    
    for function in "${functions[@]}"; do
        if resource_exists "lambda-function" "$function"; then
            error "Lambda function still exists: $function"
            cleanup_issues=true
        fi
    done
    
    # Check Step Functions state machine
    if [ -n "$SAGA_STATE_MACHINE_ARN" ] && resource_exists "stepfunctions-state-machine" "$SAGA_STATE_MACHINE_ARN"; then
        error "Step Functions state machine still exists: $SAGA_STATE_MACHINE_ARN"
        cleanup_issues=true
    fi
    
    # Check API Gateway
    if [ -n "$API_ID" ] && resource_exists "apigateway-rest-api" "$API_ID"; then
        error "API Gateway still exists: $API_ID"
        cleanup_issues=true
    fi
    
    # Check SNS topic
    if [ -n "$SAGA_TOPIC_ARN" ] && resource_exists "sns-topic" "$SAGA_TOPIC_ARN"; then
        error "SNS topic still exists: $SAGA_TOPIC_ARN"
        cleanup_issues=true
    fi
    
    # Check IAM roles
    local roles=(
        "saga-orchestrator-role-${RANDOM_SUFFIX}"
        "saga-lambda-role-${RANDOM_SUFFIX}"
        "saga-api-gateway-role-${RANDOM_SUFFIX}"
    )
    
    for role in "${roles[@]}"; do
        if resource_exists "iam-role" "$role"; then
            error "IAM role still exists: $role"
            cleanup_issues=true
        fi
    done
    
    if [ "$cleanup_issues" = "true" ]; then
        error "Some resources were not successfully deleted. Please check the AWS console and delete manually if needed."
        return 1
    else
        success "All resources have been successfully deleted"
        return 0
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "Region: $AWS_REGION"
    echo "Account: $AWS_ACCOUNT_ID"
    echo "Deployment Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Deleted Resources:"
    echo "- DynamoDB Tables: $ORDER_TABLE_NAME, $INVENTORY_TABLE_NAME, $PAYMENT_TABLE_NAME"
    echo "- SNS Topic: $SAGA_TOPIC_NAME"
    echo "- Step Functions State Machine: $SAGA_STATE_MACHINE_NAME"
    echo "- Lambda Functions: 7 functions"
    echo "- API Gateway: ${API_ID:-Not found}"
    echo "- IAM Roles: 3 roles"
    echo "- CloudWatch Log Groups: 1 group"
    echo "- Local Files: .env and .code_complete"
    echo ""
    echo "Cleanup completed successfully!"
}

# Function to handle script interruption
cleanup_on_interrupt() {
    echo ""
    warning "Script interrupted. Some resources may not have been deleted."
    echo "You can re-run this script or manually delete remaining resources."
    exit 1
}

# Main cleanup function
main() {
    log "Starting Saga Pattern cleanup..."
    
    # Set up interrupt handler
    trap cleanup_on_interrupt INT TERM
    
    load_environment
    confirm_destroy
    
    # Delete resources in reverse order of creation
    delete_api_gateway
    delete_step_functions
    delete_lambda_functions
    delete_dynamodb_tables
    delete_sns_topic
    delete_iam_roles
    delete_cloudwatch_logs
    
    # Verify cleanup
    if [ "$DRY_RUN" = "false" ]; then
        verify_cleanup
    fi
    
    cleanup_local_files
    
    success "Cleanup completed successfully!"
    display_summary
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DESTROY=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run    Show what would be deleted without actually deleting resources"
            echo "  --force      Skip confirmation prompts"
            echo "  --help       Show this help message"
            echo ""
            echo "This script will delete all resources created by the Saga Pattern deployment."
            echo "Make sure you have the .env file from the deployment in the same directory."
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"