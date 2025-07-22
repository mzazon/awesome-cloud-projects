#!/bin/bash

# Business Process Automation with Step Functions - Cleanup Script
# This script removes all AWS resources created for the business process automation workflow

set -e  # Exit on any error

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

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [ -f "deployment-info.txt" ]; then
        source deployment-info.txt
        log_success "Loaded deployment information from deployment-info.txt"
    else
        log_warning "deployment-info.txt not found. Attempting to discover resources..."
        discover_resources
    fi
}

# Function to discover resources if deployment info is not available
discover_resources() {
    log_info "Discovering resources to cleanup..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "No region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Try to find resources by pattern
    echo ""
    echo "Please provide the resource prefix used during deployment (e.g., business-process-abc123):"
    read -p "Resource prefix: " BUSINESS_PROCESS_PREFIX
    
    if [ -z "$BUSINESS_PROCESS_PREFIX" ]; then
        log_error "Resource prefix is required for cleanup. Exiting."
        exit 1
    fi
    
    # Set resource names based on prefix
    export STATE_MACHINE_NAME="${BUSINESS_PROCESS_PREFIX}-workflow"
    export LAMBDA_FUNCTION_NAME="${BUSINESS_PROCESS_PREFIX}-processor"
    export SQS_QUEUE_NAME="${BUSINESS_PROCESS_PREFIX}-queue"
    export SNS_TOPIC_NAME="${BUSINESS_PROCESS_PREFIX}-notifications"
    export LAMBDA_ROLE_NAME="${BUSINESS_PROCESS_PREFIX}-lambda-role"
    export STEPFUNCTIONS_ROLE_NAME="${BUSINESS_PROCESS_PREFIX}-stepfunctions-role"
    export API_NAME="${BUSINESS_PROCESS_PREFIX}-approval-api"
    
    log_success "Resource names configured for cleanup"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo "=== WARNING: DESTRUCTIVE OPERATION ==="
    echo "This script will permanently delete the following resources:"
    echo "- Step Functions state machine: ${STATE_MACHINE_NAME}"
    echo "- Lambda function: ${LAMBDA_FUNCTION_NAME}"
    echo "- SQS queue: ${SQS_QUEUE_NAME}"
    echo "- SNS topic: ${SNS_TOPIC_NAME}"
    echo "- API Gateway: ${API_NAME}"
    echo "- IAM roles: ${LAMBDA_ROLE_NAME}, ${STEPFUNCTIONS_ROLE_NAME}"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " CONFIRMATION
    
    if [ "$CONFIRMATION" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource cleanup..."
}

# Function to stop all running executions
stop_running_executions() {
    log_info "Stopping any running Step Functions executions..."
    
    # Get state machine ARN
    STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
        --query "stateMachines[?name=='${STATE_MACHINE_NAME}'].stateMachineArn" \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$STATE_MACHINE_ARN" ] && [ "$STATE_MACHINE_ARN" != "None" ]; then
        # List running executions
        RUNNING_EXECUTIONS=$(aws stepfunctions list-executions \
            --state-machine-arn ${STATE_MACHINE_ARN} \
            --status-filter RUNNING \
            --query 'executions[].executionArn' \
            --output text 2>/dev/null || echo "")
        
        if [ ! -z "$RUNNING_EXECUTIONS" ] && [ "$RUNNING_EXECUTIONS" != "None" ]; then
            log_warning "Found running executions. Stopping them..."
            for execution_arn in $RUNNING_EXECUTIONS; do
                aws stepfunctions stop-execution --execution-arn $execution_arn 2>/dev/null || true
                log_info "Stopped execution: $execution_arn"
            done
        else
            log_info "No running executions found"
        fi
    else
        log_warning "State machine not found or already deleted"
    fi
}

# Function to delete Step Functions state machine
delete_state_machine() {
    log_info "Deleting Step Functions state machine..."
    
    # Get state machine ARN if not already set
    if [ -z "$STATE_MACHINE_ARN" ]; then
        STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
            --query "stateMachines[?name=='${STATE_MACHINE_NAME}'].stateMachineArn" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [ ! -z "$STATE_MACHINE_ARN" ] && [ "$STATE_MACHINE_ARN" != "None" ]; then
        aws stepfunctions delete-state-machine \
            --state-machine-arn ${STATE_MACHINE_ARN} 2>/dev/null || true
        log_success "Step Functions state machine deleted: ${STATE_MACHINE_NAME}"
    else
        log_warning "Step Functions state machine not found: ${STATE_MACHINE_NAME}"
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    log_info "Deleting Lambda function..."
    
    if aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME} &> /dev/null; then
        aws lambda delete-function --function-name ${LAMBDA_FUNCTION_NAME}
        log_success "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}"
    else
        log_warning "Lambda function not found: ${LAMBDA_FUNCTION_NAME}"
    fi
}

# Function to delete SQS queue
delete_sqs_queue() {
    log_info "Deleting SQS queue..."
    
    # Get queue URL
    SQS_QUEUE_URL=$(aws sqs get-queue-url \
        --queue-name ${SQS_QUEUE_NAME} \
        --query 'QueueUrl' --output text 2>/dev/null || echo "")
    
    if [ ! -z "$SQS_QUEUE_URL" ] && [ "$SQS_QUEUE_URL" != "None" ]; then
        aws sqs delete-queue --queue-url ${SQS_QUEUE_URL}
        log_success "SQS queue deleted: ${SQS_QUEUE_NAME}"
    else
        log_warning "SQS queue not found: ${SQS_QUEUE_NAME}"
    fi
}

# Function to delete SNS topic
delete_sns_topic() {
    log_info "Deleting SNS topic..."
    
    # Get topic ARN
    SNS_TOPIC_ARN=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$SNS_TOPIC_ARN" ] && [ "$SNS_TOPIC_ARN" != "None" ]; then
        aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN}
        log_success "SNS topic deleted: ${SNS_TOPIC_NAME}"
    else
        log_warning "SNS topic not found: ${SNS_TOPIC_NAME}"
    fi
}

# Function to delete API Gateway
delete_api_gateway() {
    log_info "Deleting API Gateway..."
    
    # Get API ID
    API_ID=$(aws apigateway get-rest-apis \
        --query "items[?name=='${API_NAME}'].id" \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$API_ID" ] && [ "$API_ID" != "None" ]; then
        aws apigateway delete-rest-api --rest-api-id ${API_ID}
        log_success "API Gateway deleted: ${API_NAME}"
    else
        log_warning "API Gateway not found: ${API_NAME}"
    fi
}

# Function to delete IAM roles and policies
delete_iam_roles() {
    log_info "Deleting IAM roles and policies..."
    
    # Delete Step Functions role
    if aws iam get-role --role-name ${STEPFUNCTIONS_ROLE_NAME} &> /dev/null; then
        # Delete inline policies first
        aws iam delete-role-policy \
            --role-name ${STEPFUNCTIONS_ROLE_NAME} \
            --policy-name StepFunctionsExecutionPolicy 2>/dev/null || true
        
        # Delete the role
        aws iam delete-role --role-name ${STEPFUNCTIONS_ROLE_NAME}
        log_success "Step Functions IAM role deleted: ${STEPFUNCTIONS_ROLE_NAME}"
    else
        log_warning "Step Functions IAM role not found: ${STEPFUNCTIONS_ROLE_NAME}"
    fi
    
    # Delete Lambda role
    if aws iam get-role --role-name ${LAMBDA_ROLE_NAME} &> /dev/null; then
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name ${LAMBDA_ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        # Delete the role
        aws iam delete-role --role-name ${LAMBDA_ROLE_NAME}
        log_success "Lambda IAM role deleted: ${LAMBDA_ROLE_NAME}"
    else
        log_warning "Lambda IAM role not found: ${LAMBDA_ROLE_NAME}"
    fi
}

# Function to clean up CloudWatch logs
cleanup_cloudwatch_logs() {
    log_info "Cleaning up CloudWatch log groups..."
    
    # Delete Lambda log group
    aws logs delete-log-group \
        --log-group-name "/aws/lambda/${LAMBDA_FUNCTION_NAME}" 2>/dev/null || true
    
    # Delete Step Functions log group if it exists
    aws logs delete-log-group \
        --log-group-name "/aws/stepfunctions/${STATE_MACHINE_NAME}" 2>/dev/null || true
    
    log_success "CloudWatch log groups cleaned up"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment info file
    if [ -f "deployment-info.txt" ]; then
        rm -f deployment-info.txt
        log_success "Removed deployment-info.txt"
    fi
    
    # Remove any temporary files that might exist
    rm -f /tmp/lambda-trust-policy.json 2>/dev/null || true
    rm -f /tmp/stepfunctions-trust-policy.json 2>/dev/null || true
    rm -f /tmp/business-processor.py 2>/dev/null || true
    rm -f /tmp/business-processor.zip 2>/dev/null || true
    rm -f /tmp/stepfunctions-execution-policy.json 2>/dev/null || true
    rm -f /tmp/business-process-state-machine.json 2>/dev/null || true
    rm -f /tmp/test-input.json 2>/dev/null || true
    
    log_success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check Step Functions state machine
    if aws stepfunctions describe-state-machine \
        --state-machine-arn "arn:aws:states:${AWS_REGION}:${AWS_ACCOUNT_ID}:stateMachine:${STATE_MACHINE_NAME}" &> /dev/null; then
        log_warning "Step Functions state machine still exists: ${STATE_MACHINE_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME} &> /dev/null; then
        log_warning "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check SQS queue
    if aws sqs get-queue-url --queue-name ${SQS_QUEUE_NAME} &> /dev/null; then
        log_warning "SQS queue still exists: ${SQS_QUEUE_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check SNS topic
    SNS_TOPIC_CHECK=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
        --output text 2>/dev/null || echo "")
    if [ ! -z "$SNS_TOPIC_CHECK" ] && [ "$SNS_TOPIC_CHECK" != "None" ]; then
        log_warning "SNS topic still exists: ${SNS_TOPIC_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check API Gateway
    API_CHECK=$(aws apigateway get-rest-apis \
        --query "items[?name=='${API_NAME}'].id" \
        --output text 2>/dev/null || echo "")
    if [ ! -z "$API_CHECK" ] && [ "$API_CHECK" != "None" ]; then
        log_warning "API Gateway still exists: ${API_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name ${LAMBDA_ROLE_NAME} &> /dev/null; then
        log_warning "Lambda IAM role still exists: ${LAMBDA_ROLE_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if aws iam get-role --role-name ${STEPFUNCTIONS_ROLE_NAME} &> /dev/null; then
        log_warning "Step Functions IAM role still exists: ${STEPFUNCTIONS_ROLE_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log_success "All resources have been successfully removed"
    else
        log_warning "Found $cleanup_issues resources that may still exist"
        log_info "Some resources may take time to fully delete or may require manual removal"
    fi
}

# Function to display final cleanup report
display_cleanup_report() {
    echo ""
    echo "=== Cleanup Report ==="
    echo "AWS Region: ${AWS_REGION}"
    echo "Resource Prefix: ${BUSINESS_PROCESS_PREFIX}"
    echo ""
    echo "=== Resources Processed ==="
    echo "✓ Step Functions state machine: ${STATE_MACHINE_NAME}"
    echo "✓ Lambda function: ${LAMBDA_FUNCTION_NAME}"
    echo "✓ SQS queue: ${SQS_QUEUE_NAME}"
    echo "✓ SNS topic: ${SNS_TOPIC_NAME}"
    echo "✓ API Gateway: ${API_NAME}"
    echo "✓ IAM roles: ${LAMBDA_ROLE_NAME}, ${STEPFUNCTIONS_ROLE_NAME}"
    echo "✓ CloudWatch log groups"
    echo "✓ Local files"
    echo ""
    echo "=== Important Notes ==="
    echo "• Some AWS resources may take a few minutes to fully delete"
    echo "• Check your AWS console to verify all resources are removed"
    echo "• CloudWatch logs are typically deleted but may persist briefly"
    echo "• Any email subscriptions to SNS topics should be automatically removed"
    echo ""
    log_success "Cleanup completed!"
}

# Main cleanup function
main() {
    echo "=== Business Process Automation - Resource Cleanup ==="
    echo ""
    
    # Check prerequisites
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    load_deployment_info
    confirm_destruction
    
    log_info "Starting cleanup process..."
    
    stop_running_executions
    delete_state_machine
    delete_lambda_function
    delete_sqs_queue
    delete_sns_topic
    delete_api_gateway
    delete_iam_roles
    cleanup_cloudwatch_logs
    cleanup_local_files
    
    log_info "Waiting for resources to fully delete..."
    sleep 10
    
    verify_cleanup
    display_cleanup_report
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi