#!/bin/bash

# Dead Letter Queue Processing with SQS - Cleanup Script
# This script removes all resources created by the deploy.sh script
# Based on recipe: dead-letter-queue-processing-sqs-lambda

set -e

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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Script information
log "Starting cleanup of Dead Letter Queue Processing infrastructure"
log "This script will remove: SQS queues, Lambda functions, IAM roles, and CloudWatch alarms"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [ -f "deployment-info.json" ]; then
        log "Found deployment-info.json, loading resource information..."
        
        # Extract information from deployment file
        export RANDOM_SUFFIX=$(cat deployment-info.json | grep -o '"randomSuffix": "[^"]*"' | cut -d'"' -f4)
        export AWS_REGION=$(cat deployment-info.json | grep -o '"region": "[^"]*"' | cut -d'"' -f4)
        export AWS_ACCOUNT_ID=$(cat deployment-info.json | grep -o '"accountId": "[^"]*"' | cut -d'"' -f4)
        
        # Resource names
        export QUEUE_NAME="order-processing-${RANDOM_SUFFIX}"
        export DLQ_NAME="order-processing-dlq-${RANDOM_SUFFIX}"
        export LAMBDA_ROLE_NAME="dlq-processing-role-${RANDOM_SUFFIX}"
        export MAIN_PROCESSOR_NAME="order-processor-${RANDOM_SUFFIX}"
        export DLQ_MONITOR_NAME="dlq-monitor-${RANDOM_SUFFIX}"
        
        log "Loaded deployment info for suffix: ${RANDOM_SUFFIX}"
        success "Deployment information loaded successfully"
    else
        warning "deployment-info.json not found. You'll need to provide resource information manually."
        prompt_for_info
    fi
}

# Prompt for manual input if deployment info is not available
prompt_for_info() {
    log "Please provide the resource information for cleanup:"
    
    echo -n "Enter the random suffix used during deployment: "
    read RANDOM_SUFFIX
    
    if [ -z "$RANDOM_SUFFIX" ]; then
        error "Random suffix is required for cleanup"
        exit 1
    fi
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not set, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Resource names
    export QUEUE_NAME="order-processing-${RANDOM_SUFFIX}"
    export DLQ_NAME="order-processing-dlq-${RANDOM_SUFFIX}"
    export LAMBDA_ROLE_NAME="dlq-processing-role-${RANDOM_SUFFIX}"
    export MAIN_PROCESSOR_NAME="order-processor-${RANDOM_SUFFIX}"
    export DLQ_MONITOR_NAME="dlq-monitor-${RANDOM_SUFFIX}"
    
    log "Using suffix: ${RANDOM_SUFFIX}"
}

# Confirmation prompt
confirm_destruction() {
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "  • Lambda Functions: ${MAIN_PROCESSOR_NAME}, ${DLQ_MONITOR_NAME}"
    echo "  • SQS Queues: ${QUEUE_NAME}, ${DLQ_NAME}"
    echo "  • IAM Role: ${LAMBDA_ROLE_NAME}"
    echo "  • CloudWatch Alarms: DLQ-Messages-${RANDOM_SUFFIX}, DLQ-ErrorRate-${RANDOM_SUFFIX}"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    read -p "Do you want to continue with the cleanup? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Cleanup confirmed. Proceeding with resource deletion..."
}

# Delete Lambda event source mappings
delete_event_source_mappings() {
    log "Deleting Lambda event source mappings..."
    
    # Get event source mappings for main processor
    log "Looking for event source mappings for ${MAIN_PROCESSOR_NAME}..."
    MAIN_ESM_UUIDS=$(aws lambda list-event-source-mappings \
        --function-name ${MAIN_PROCESSOR_NAME} \
        --query 'EventSourceMappings[].UUID' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$MAIN_ESM_UUIDS" ]; then
        for uuid in $MAIN_ESM_UUIDS; do
            log "Deleting event source mapping: ${uuid}"
            aws lambda delete-event-source-mapping --uuid ${uuid} > /dev/null 2>&1 || warning "Failed to delete event source mapping ${uuid}"
        done
        success "Main processor event source mappings deleted"
    else
        warning "No event source mappings found for ${MAIN_PROCESSOR_NAME}"
    fi
    
    # Get event source mappings for DLQ monitor
    log "Looking for event source mappings for ${DLQ_MONITOR_NAME}..."
    DLQ_ESM_UUIDS=$(aws lambda list-event-source-mappings \
        --function-name ${DLQ_MONITOR_NAME} \
        --query 'EventSourceMappings[].UUID' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$DLQ_ESM_UUIDS" ]; then
        for uuid in $DLQ_ESM_UUIDS; do
            log "Deleting event source mapping: ${uuid}"
            aws lambda delete-event-source-mapping --uuid ${uuid} > /dev/null 2>&1 || warning "Failed to delete event source mapping ${uuid}"
        done
        success "DLQ monitor event source mappings deleted"
    else
        warning "No event source mappings found for ${DLQ_MONITOR_NAME}"
    fi
    
    # Wait for event source mappings to be fully deleted
    log "Waiting for event source mappings to be deleted..."
    sleep 15
}

# Delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    # Delete main processor Lambda
    log "Deleting main processor Lambda function: ${MAIN_PROCESSOR_NAME}"
    if aws lambda get-function --function-name ${MAIN_PROCESSOR_NAME} &> /dev/null; then
        aws lambda delete-function --function-name ${MAIN_PROCESSOR_NAME}
        if [ $? -eq 0 ]; then
            success "Main processor Lambda function deleted: ${MAIN_PROCESSOR_NAME}"
        else
            warning "Failed to delete main processor Lambda function"
        fi
    else
        warning "Main processor Lambda function ${MAIN_PROCESSOR_NAME} not found"
    fi
    
    # Delete DLQ monitor Lambda
    log "Deleting DLQ monitor Lambda function: ${DLQ_MONITOR_NAME}"
    if aws lambda get-function --function-name ${DLQ_MONITOR_NAME} &> /dev/null; then
        aws lambda delete-function --function-name ${DLQ_MONITOR_NAME}
        if [ $? -eq 0 ]; then
            success "DLQ monitor Lambda function deleted: ${DLQ_MONITOR_NAME}"
        else
            warning "Failed to delete DLQ monitor Lambda function"
        fi
    else
        warning "DLQ monitor Lambda function ${DLQ_MONITOR_NAME} not found"
    fi
}

# Delete SQS queues
delete_sqs_queues() {
    log "Deleting SQS queues..."
    
    # Get queue URLs
    MAIN_QUEUE_URL=$(aws sqs get-queue-url --queue-name ${QUEUE_NAME} --query 'QueueUrl' --output text 2>/dev/null || echo "")
    DLQ_URL=$(aws sqs get-queue-url --queue-name ${DLQ_NAME} --query 'QueueUrl' --output text 2>/dev/null || echo "")
    
    # Delete main queue
    if [ ! -z "$MAIN_QUEUE_URL" ]; then
        log "Deleting main queue: ${QUEUE_NAME}"
        aws sqs delete-queue --queue-url ${MAIN_QUEUE_URL}
        if [ $? -eq 0 ]; then
            success "Main queue deleted: ${QUEUE_NAME}"
        else
            warning "Failed to delete main queue"
        fi
    else
        warning "Main queue ${QUEUE_NAME} not found"
    fi
    
    # Delete dead letter queue
    if [ ! -z "$DLQ_URL" ]; then
        log "Deleting dead letter queue: ${DLQ_NAME}"
        aws sqs delete-queue --queue-url ${DLQ_URL}
        if [ $? -eq 0 ]; then
            success "Dead letter queue deleted: ${DLQ_NAME}"
        else
            warning "Failed to delete dead letter queue"
        fi
    else
        warning "Dead letter queue ${DLQ_NAME} not found"
    fi
}

# Delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    # List of alarm names to delete
    ALARM_NAMES=(
        "DLQ-Messages-${RANDOM_SUFFIX}"
        "DLQ-ErrorRate-${RANDOM_SUFFIX}"
    )
    
    for alarm_name in "${ALARM_NAMES[@]}"; do
        log "Deleting CloudWatch alarm: ${alarm_name}"
        if aws cloudwatch describe-alarms --alarm-names ${alarm_name} --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "${alarm_name}"; then
            aws cloudwatch delete-alarms --alarm-names ${alarm_name}
            if [ $? -eq 0 ]; then
                success "CloudWatch alarm deleted: ${alarm_name}"
            else
                warning "Failed to delete CloudWatch alarm: ${alarm_name}"
            fi
        else
            warning "CloudWatch alarm ${alarm_name} not found"
        fi
    done
}

# Delete CloudWatch log groups
delete_cloudwatch_logs() {
    log "Deleting CloudWatch log groups..."
    
    # Log group names for Lambda functions
    LOG_GROUPS=(
        "/aws/lambda/${MAIN_PROCESSOR_NAME}"
        "/aws/lambda/${DLQ_MONITOR_NAME}"
    )
    
    for log_group in "${LOG_GROUPS[@]}"; do
        log "Deleting CloudWatch log group: ${log_group}"
        if aws logs describe-log-groups --log-group-name-prefix "${log_group}" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${log_group}"; then
            aws logs delete-log-group --log-group-name ${log_group}
            if [ $? -eq 0 ]; then
                success "CloudWatch log group deleted: ${log_group}"
            else
                warning "Failed to delete CloudWatch log group: ${log_group}"
            fi
        else
            warning "CloudWatch log group ${log_group} not found"
        fi
    done
}

# Delete IAM role
delete_iam_role() {
    log "Deleting IAM role..."
    
    # Check if role exists
    if aws iam get-role --role-name ${LAMBDA_ROLE_NAME} &> /dev/null; then
        log "Detaching policies from IAM role: ${LAMBDA_ROLE_NAME}"
        
        # Detach managed policies
        MANAGED_POLICIES=(
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
            "arn:aws:iam::aws:policy/CloudWatchFullAccess"
        )
        
        for policy_arn in "${MANAGED_POLICIES[@]}"; do
            log "Detaching policy: ${policy_arn}"
            aws iam detach-role-policy \
                --role-name ${LAMBDA_ROLE_NAME} \
                --policy-arn ${policy_arn} 2>/dev/null || warning "Failed to detach policy ${policy_arn}"
        done
        
        # List and delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies --role-name ${LAMBDA_ROLE_NAME} --query 'PolicyNames' --output text 2>/dev/null || echo "")
        if [ ! -z "$INLINE_POLICIES" ]; then
            for policy_name in $INLINE_POLICIES; do
                log "Deleting inline policy: ${policy_name}"
                aws iam delete-role-policy --role-name ${LAMBDA_ROLE_NAME} --policy-name ${policy_name}
            done
        fi
        
        # Delete the role
        log "Deleting IAM role: ${LAMBDA_ROLE_NAME}"
        aws iam delete-role --role-name ${LAMBDA_ROLE_NAME}
        if [ $? -eq 0 ]; then
            success "IAM role deleted: ${LAMBDA_ROLE_NAME}"
        else
            warning "Failed to delete IAM role"
        fi
    else
        warning "IAM role ${LAMBDA_ROLE_NAME} not found"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment info file
    if [ -f "deployment-info.json" ]; then
        rm -f deployment-info.json
        success "Removed deployment-info.json"
    fi
    
    # Remove any temporary files that might still exist
    if [ -f "main_processor.zip" ]; then
        rm -f main_processor.zip
        success "Removed main_processor.zip"
    fi
    
    if [ -f "dlq_monitor.zip" ]; then
        rm -f dlq_monitor.zip
        success "Removed dlq_monitor.zip"
    fi
    
    success "Local cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check Lambda functions
    if aws lambda get-function --function-name ${MAIN_PROCESSOR_NAME} &> /dev/null; then
        warning "Main processor Lambda still exists: ${MAIN_PROCESSOR_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if aws lambda get-function --function-name ${DLQ_MONITOR_NAME} &> /dev/null; then
        warning "DLQ monitor Lambda still exists: ${DLQ_MONITOR_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check SQS queues
    if aws sqs get-queue-url --queue-name ${QUEUE_NAME} &> /dev/null; then
        warning "Main queue still exists: ${QUEUE_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if aws sqs get-queue-url --queue-name ${DLQ_NAME} &> /dev/null; then
        warning "Dead letter queue still exists: ${DLQ_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name ${LAMBDA_ROLE_NAME} &> /dev/null; then
        warning "IAM role still exists: ${LAMBDA_ROLE_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        success "All resources have been successfully cleaned up"
    else
        warning "${cleanup_issues} resources may still exist. Please check manually."
    fi
    
    return $cleanup_issues
}

# Display cleanup summary
display_summary() {
    echo ""
    if [ $1 -eq 0 ]; then
        echo "🎉 Cleanup completed successfully!"
        echo ""
        echo "✅ All Dead Letter Queue Processing resources have been removed:"
        echo "  • Lambda Functions: ${MAIN_PROCESSOR_NAME}, ${DLQ_MONITOR_NAME}"
        echo "  • SQS Queues: ${QUEUE_NAME}, ${DLQ_NAME}"
        echo "  • IAM Role: ${LAMBDA_ROLE_NAME}"
        echo "  • CloudWatch Alarms and Log Groups"
        echo "  • Local deployment files"
    else
        echo "⚠️ Cleanup completed with warnings"
        echo ""
        echo "Some resources may still exist. Please check the warnings above and:"
        echo "  1. Verify resources in the AWS Console"
        echo "  2. Manually delete any remaining resources if needed"
        echo "  3. Check your AWS billing for any remaining charges"
    fi
    echo ""
    echo "💰 Cost Impact:"
    echo "  All billable resources should now be removed"
    echo "  Monitor your AWS billing to confirm no ongoing charges"
    echo ""
}

# Main execution
main() {
    check_prerequisites
    load_deployment_info
    confirm_destruction
    delete_event_source_mappings
    delete_lambda_functions
    delete_sqs_queues
    delete_cloudwatch_alarms
    delete_cloudwatch_logs
    delete_iam_role
    cleanup_local_files
    verify_cleanup
    local verification_result=$?
    display_summary $verification_result
    exit $verification_result
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may not have been cleaned up."; exit 1' INT TERM

# Execute main function
main "$@"