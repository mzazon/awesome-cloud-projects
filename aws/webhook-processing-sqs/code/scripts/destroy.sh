#!/bin/bash

# AWS Webhook Processing Systems Cleanup Script
# This script destroys all resources created by the webhook processing system

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warning "Running in DRY-RUN mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            warning "Running in FORCE mode - skipping confirmation prompts"
            shift
            ;;
        --help)
            echo "Usage: $0 [--dry-run] [--force] [--help]"
            echo "  --dry-run: Show what would be deleted without actually deleting"
            echo "  --force: Skip confirmation prompts"
            echo "  --help: Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN: $description"
        log "Command: $cmd"
        return 0
    else
        log "$description"
        if [[ "$ignore_errors" == "true" ]]; then
            eval "$cmd" || true
        else
            eval "$cmd"
        fi
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it for JSON parsing."
        exit 1
    fi
    
    # Check AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        error "Unable to determine AWS Account ID"
        exit 1
    fi
    
    # Check AWS region
    AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region is not configured"
        exit 1
    fi
    
    success "Prerequisites check passed"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "AWS Region: $AWS_REGION"
}

# Function to load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [[ -f "webhook-deployment-info.json" ]]; then
        # Load from deployment info file
        export RANDOM_SUFFIX=$(jq -r '.random_suffix' webhook-deployment-info.json)
        export WEBHOOK_QUEUE_NAME=$(jq -r '.resources.sqs_queue_name' webhook-deployment-info.json)
        export WEBHOOK_DLQ_NAME=$(jq -r '.resources.sqs_dlq_name' webhook-deployment-info.json)
        export WEBHOOK_FUNCTION_NAME=$(jq -r '.resources.lambda_function_name' webhook-deployment-info.json)
        export WEBHOOK_API_NAME=$(jq -r '.resources.api_gateway_name' webhook-deployment-info.json)
        export WEBHOOK_TABLE_NAME=$(jq -r '.resources.dynamodb_table_name' webhook-deployment-info.json)
        export API_ID=$(jq -r '.resources.api_gateway_id' webhook-deployment-info.json)
        export QUEUE_URL=$(jq -r '.resources.queue_url' webhook-deployment-info.json)
        export DLQ_URL=$(jq -r '.resources.dlq_url' webhook-deployment-info.json)
        
        success "Deployment information loaded from webhook-deployment-info.json"
    else
        warning "No deployment info file found. You will need to specify resource names manually."
        
        # Prompt for resource suffix if not in force mode
        if [[ "$FORCE_DELETE" == "false" ]]; then
            read -p "Enter the resource suffix (6 characters): " RANDOM_SUFFIX
            if [[ -z "$RANDOM_SUFFIX" ]]; then
                error "Resource suffix is required for cleanup"
                exit 1
            fi
        else
            error "Resource suffix is required for cleanup when using --force"
            exit 1
        fi
        
        # Construct resource names
        export WEBHOOK_QUEUE_NAME="webhook-processing-queue-${RANDOM_SUFFIX}"
        export WEBHOOK_DLQ_NAME="webhook-dlq-${RANDOM_SUFFIX}"
        export WEBHOOK_FUNCTION_NAME="webhook-processor-${RANDOM_SUFFIX}"
        export WEBHOOK_API_NAME="webhook-api-${RANDOM_SUFFIX}"
        export WEBHOOK_TABLE_NAME="webhook-history-${RANDOM_SUFFIX}"
    fi
    
    log "Resources to be deleted:"
    log "- SQS Queue: ${WEBHOOK_QUEUE_NAME}"
    log "- SQS DLQ: ${WEBHOOK_DLQ_NAME}"
    log "- Lambda Function: ${WEBHOOK_FUNCTION_NAME}"
    log "- API Gateway: ${WEBHOOK_API_NAME}"
    log "- DynamoDB Table: ${WEBHOOK_TABLE_NAME}"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warning "⚠️  This will permanently delete all webhook processing resources!"
    warning "This action cannot be undone."
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Deletion cancelled by user."
        exit 0
    fi
    
    success "Deletion confirmed. Proceeding with cleanup..."
}

# Function to find and delete API Gateway
delete_api_gateway() {
    log "Deleting API Gateway..."
    
    # Find API ID if not already known
    if [[ -z "${API_ID:-}" ]] || [[ "$API_ID" == "null" ]]; then
        API_ID=$(aws apigateway get-rest-apis \
            --query "items[?name=='${WEBHOOK_API_NAME}'].id" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -n "$API_ID" ]] && [[ "$API_ID" != "null" ]]; then
        execute_command "aws apigateway delete-rest-api --rest-api-id ${API_ID}" \
            "Deleting API Gateway: ${API_ID}" true
        success "API Gateway deleted"
    else
        warning "API Gateway not found or already deleted"
    fi
}

# Function to delete Lambda function and event source mappings
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    # Delete event source mappings first
    log "Deleting event source mappings..."
    EVENT_SOURCE_MAPPINGS=$(aws lambda list-event-source-mappings \
        --function-name ${WEBHOOK_FUNCTION_NAME} \
        --query 'EventSourceMappings[].UUID' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$EVENT_SOURCE_MAPPINGS" ]]; then
        for uuid in $EVENT_SOURCE_MAPPINGS; do
            execute_command "aws lambda delete-event-source-mapping --uuid ${uuid}" \
                "Deleting event source mapping: ${uuid}" true
        done
        success "Event source mappings deleted"
    else
        warning "No event source mappings found"
    fi
    
    # Delete Lambda function
    execute_command "aws lambda delete-function --function-name ${WEBHOOK_FUNCTION_NAME}" \
        "Deleting Lambda function: ${WEBHOOK_FUNCTION_NAME}" true
    success "Lambda function deleted"
}

# Function to delete SQS queues
delete_sqs_queues() {
    log "Deleting SQS queues..."
    
    # Get queue URLs if not already known
    if [[ -z "${QUEUE_URL:-}" ]] || [[ "$QUEUE_URL" == "null" ]]; then
        QUEUE_URL=$(aws sqs get-queue-url \
            --queue-name ${WEBHOOK_QUEUE_NAME} \
            --query QueueUrl --output text 2>/dev/null || echo "")
    fi
    
    if [[ -z "${DLQ_URL:-}" ]] || [[ "$DLQ_URL" == "null" ]]; then
        DLQ_URL=$(aws sqs get-queue-url \
            --queue-name ${WEBHOOK_DLQ_NAME} \
            --query QueueUrl --output text 2>/dev/null || echo "")
    fi
    
    # Delete primary queue
    if [[ -n "$QUEUE_URL" ]] && [[ "$QUEUE_URL" != "null" ]]; then
        execute_command "aws sqs delete-queue --queue-url ${QUEUE_URL}" \
            "Deleting primary SQS queue: ${WEBHOOK_QUEUE_NAME}" true
        success "Primary SQS queue deleted"
    else
        warning "Primary SQS queue not found or already deleted"
    fi
    
    # Delete dead letter queue
    if [[ -n "$DLQ_URL" ]] && [[ "$DLQ_URL" != "null" ]]; then
        execute_command "aws sqs delete-queue --queue-url ${DLQ_URL}" \
            "Deleting dead letter queue: ${WEBHOOK_DLQ_NAME}" true
        success "Dead letter queue deleted"
    else
        warning "Dead letter queue not found or already deleted"
    fi
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    log "Deleting DynamoDB table..."
    
    execute_command "aws dynamodb delete-table --table-name ${WEBHOOK_TABLE_NAME}" \
        "Deleting DynamoDB table: ${WEBHOOK_TABLE_NAME}" true
    success "DynamoDB table deleted"
}

# Function to delete IAM roles and policies
delete_iam_roles() {
    log "Deleting IAM roles and policies..."
    
    # Delete API Gateway role
    log "Deleting API Gateway IAM role..."
    execute_command "aws iam delete-role-policy \
        --role-name webhook-apigw-sqs-role-${RANDOM_SUFFIX} \
        --policy-name SQSAccessPolicy" \
        "Deleting API Gateway role policy" true
    
    execute_command "aws iam delete-role \
        --role-name webhook-apigw-sqs-role-${RANDOM_SUFFIX}" \
        "Deleting API Gateway role" true
    
    # Delete Lambda role
    log "Deleting Lambda IAM role..."
    execute_command "aws iam delete-role-policy \
        --role-name webhook-lambda-role-${RANDOM_SUFFIX} \
        --policy-name DynamoDBAccessPolicy" \
        "Deleting Lambda role DynamoDB policy" true
    
    execute_command "aws iam detach-role-policy \
        --role-name webhook-lambda-role-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        "Detaching Lambda basic execution policy" true
    
    execute_command "aws iam delete-role \
        --role-name webhook-lambda-role-${RANDOM_SUFFIX}" \
        "Deleting Lambda role" true
    
    success "IAM roles and policies deleted"
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    execute_command "aws cloudwatch delete-alarms \
        --alarm-names 'webhook-dlq-messages-${RANDOM_SUFFIX}' \
                     'webhook-lambda-errors-${RANDOM_SUFFIX}'" \
        "Deleting CloudWatch alarms" true
    
    success "CloudWatch alarms deleted"
}

# Function to verify resource cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Cleanup verification skipped"
        return 0
    fi
    
    local errors=0
    
    # Check API Gateway
    if aws apigateway get-rest-apis --query "items[?name=='${WEBHOOK_API_NAME}'].id" --output text 2>/dev/null | grep -q .; then
        error "API Gateway still exists"
        ((errors++))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name ${WEBHOOK_FUNCTION_NAME} &>/dev/null; then
        error "Lambda function still exists"
        ((errors++))
    fi
    
    # Check SQS queues
    if aws sqs get-queue-url --queue-name ${WEBHOOK_QUEUE_NAME} &>/dev/null; then
        error "Primary SQS queue still exists"
        ((errors++))
    fi
    
    if aws sqs get-queue-url --queue-name ${WEBHOOK_DLQ_NAME} &>/dev/null; then
        error "Dead letter queue still exists"
        ((errors++))
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name ${WEBHOOK_TABLE_NAME} &>/dev/null; then
        error "DynamoDB table still exists"
        ((errors++))
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name webhook-apigw-sqs-role-${RANDOM_SUFFIX} &>/dev/null; then
        error "API Gateway IAM role still exists"
        ((errors++))
    fi
    
    if aws iam get-role --role-name webhook-lambda-role-${RANDOM_SUFFIX} &>/dev/null; then
        error "Lambda IAM role still exists"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        success "All resources successfully cleaned up"
    else
        warning "Some resources may still exist. Please check AWS console."
    fi
}

# Function to clean up deployment info file
cleanup_deployment_info() {
    log "Cleaning up deployment information..."
    
    if [[ -f "webhook-deployment-info.json" ]]; then
        if [[ "$DRY_RUN" == "false" ]]; then
            rm -f webhook-deployment-info.json
            success "Deployment info file deleted"
        else
            log "DRY-RUN: Would delete webhook-deployment-info.json"
        fi
    else
        log "No deployment info file found"
    fi
}

# Function to display final summary
display_summary() {
    echo ""
    success "Webhook processing system cleanup completed!"
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Cleanup Summary:"
        log "================"
        log "✅ API Gateway deleted"
        log "✅ Lambda function and event source mappings deleted"
        log "✅ SQS queues deleted"
        log "✅ DynamoDB table deleted"
        log "✅ IAM roles and policies deleted"
        log "✅ CloudWatch alarms deleted"
        log "✅ Deployment info file cleaned up"
        echo ""
        log "All webhook processing resources have been removed."
        log "Please verify in AWS console that all resources are gone."
    else
        log "DRY-RUN Summary:"
        log "================"
        log "This was a dry-run. No resources were actually deleted."
        log "Run without --dry-run to perform actual cleanup."
    fi
}

# Main cleanup function
main() {
    log "Starting webhook processing system cleanup..."
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_info
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_api_gateway
    delete_lambda_function
    delete_sqs_queues
    delete_dynamodb_table
    delete_iam_roles
    delete_cloudwatch_alarms
    
    # Verify cleanup and clean up local files
    verify_cleanup
    cleanup_deployment_info
    
    # Display summary
    display_summary
}

# Handle script interruption
trap 'echo ""; warning "Script interrupted. Some resources may not be cleaned up."; exit 1' INT TERM

# Run main function
main "$@"