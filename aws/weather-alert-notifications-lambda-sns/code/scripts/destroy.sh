#!/bin/bash

# Weather Alert Notifications Cleanup Script
# This script removes all AWS resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ -f "weather-resources.env" ]; then
        source weather-resources.env
        success "Environment variables loaded from weather-resources.env"
        log "Resources to be deleted:"
        log "  Function: ${FUNCTION_NAME:-Not found}"
        log "  SNS Topic: ${SNS_TOPIC_NAME:-Not found}"
        log "  IAM Role: ${ROLE_NAME:-Not found}"
        log "  EventBridge Rule: ${RULE_NAME:-Not found}"
    else
        warning "weather-resources.env file not found"
        echo
        log "Manual resource identification required..."
        
        # Try to find resources by pattern
        echo -n "Enter Lambda function name (or press Enter to skip): "
        read FUNCTION_NAME
        
        echo -n "Enter SNS topic name (or press Enter to skip): "
        read SNS_TOPIC_NAME
        
        echo -n "Enter IAM role name (or press Enter to skip): "
        read ROLE_NAME
        
        echo -n "Enter EventBridge rule name (or press Enter to skip): "
        read RULE_NAME
        
        # Set AWS region if not already set
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION=$(aws configure get region)
            if [ -z "$AWS_REGION" ]; then
                export AWS_REGION="us-east-1"
                warning "AWS region not configured, defaulting to us-east-1"
            fi
        fi
    fi
}

# Function to confirm deletion
confirm_deletion() {
    echo
    warning "⚠️  DESTRUCTIVE OPERATION ⚠️"
    echo
    log "This script will permanently delete the following resources:"
    
    if [ -n "$FUNCTION_NAME" ]; then
        echo "  • Lambda Function: ${FUNCTION_NAME}"
    fi
    
    if [ -n "$SNS_TOPIC_NAME" ]; then
        echo "  • SNS Topic: ${SNS_TOPIC_NAME} (and all subscriptions)"
    fi
    
    if [ -n "$ROLE_NAME" ]; then
        echo "  • IAM Role: ${ROLE_NAME} (and attached policies)"
    fi
    
    if [ -n "$RULE_NAME" ]; then
        echo "  • EventBridge Rule: ${RULE_NAME}"
    fi
    
    echo
    echo -n "Are you sure you want to proceed? (type 'yes' to confirm): "
    read confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource cleanup..."
}

# Function to remove EventBridge rule and targets
remove_eventbridge_rule() {
    if [ -z "$RULE_NAME" ]; then
        warning "EventBridge rule name not provided, skipping"
        return
    fi
    
    log "Removing EventBridge rule and targets..."
    
    # Check if rule exists
    if ! aws events describe-rule --name "${RULE_NAME}" &> /dev/null; then
        warning "EventBridge rule ${RULE_NAME} not found, skipping"
        return
    fi
    
    # Remove Lambda target from rule
    log "Removing targets from EventBridge rule..."
    aws events remove-targets \
        --rule "${RULE_NAME}" \
        --ids 1 2>/dev/null || warning "Failed to remove targets or no targets found"
    
    # Delete EventBridge rule
    log "Deleting EventBridge rule..."
    aws events delete-rule --name "${RULE_NAME}"
    
    success "EventBridge rule deleted: ${RULE_NAME}"
}

# Function to delete Lambda function
delete_lambda_function() {
    if [ -z "$FUNCTION_NAME" ]; then
        warning "Lambda function name not provided, skipping"
        return
    fi
    
    log "Deleting Lambda function..."
    
    # Check if function exists
    if ! aws lambda get-function --function-name "${FUNCTION_NAME}" &> /dev/null; then
        warning "Lambda function ${FUNCTION_NAME} not found, skipping"
        return
    fi
    
    # Delete Lambda function
    aws lambda delete-function --function-name "${FUNCTION_NAME}"
    
    success "Lambda function deleted: ${FUNCTION_NAME}"
}

# Function to remove SNS resources
remove_sns_resources() {
    if [ -z "$SNS_TOPIC_NAME" ]; then
        warning "SNS topic name not provided, skipping"
        return
    fi
    
    log "Removing SNS resources..."
    
    # Get SNS topic ARN
    SNS_TOPIC_ARN=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
        --output text 2>/dev/null)
    
    if [ -z "$SNS_TOPIC_ARN" ]; then
        warning "SNS topic ${SNS_TOPIC_NAME} not found, skipping"
        return
    fi
    
    # List subscriptions for information
    log "Checking SNS subscriptions..."
    SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --query 'Subscriptions[].Endpoint' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$SUBSCRIPTIONS" ]; then
        log "Found subscriptions: ${SUBSCRIPTIONS}"
        log "All subscriptions will be deleted with the topic"
    fi
    
    # Delete SNS topic (this also removes all subscriptions)
    aws sns delete-topic --topic-arn "${SNS_TOPIC_ARN}"
    
    success "SNS topic and subscriptions deleted: ${SNS_TOPIC_NAME}"
}

# Function to clean up IAM role and policies
cleanup_iam_role() {
    if [ -z "$ROLE_NAME" ]; then
        warning "IAM role name not provided, skipping"
        return
    fi
    
    log "Cleaning up IAM role and policies..."
    
    # Check if role exists
    if ! aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
        warning "IAM role ${ROLE_NAME} not found, skipping"
        return
    fi
    
    # Remove inline policies
    log "Removing inline policies..."
    INLINE_POLICIES=$(aws iam list-role-policies \
        --role-name "${ROLE_NAME}" \
        --query 'PolicyNames' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$INLINE_POLICIES" ]; then
        for policy in $INLINE_POLICIES; do
            log "Deleting inline policy: ${policy}"
            aws iam delete-role-policy \
                --role-name "${ROLE_NAME}" \
                --policy-name "${policy}"
        done
    fi
    
    # Detach managed policies
    log "Detaching managed policies..."
    MANAGED_POLICIES=$(aws iam list-attached-role-policies \
        --role-name "${ROLE_NAME}" \
        --query 'AttachedPolicies[].PolicyArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$MANAGED_POLICIES" ]; then
        for policy_arn in $MANAGED_POLICIES; do
            log "Detaching managed policy: ${policy_arn}"
            aws iam detach-role-policy \
                --role-name "${ROLE_NAME}" \
                --policy-arn "${policy_arn}"
        done
    fi
    
    # Delete IAM role
    log "Deleting IAM role..."
    aws iam delete-role --role-name "${ROLE_NAME}"
    
    success "IAM role and policies deleted: ${ROLE_NAME}"
}

# Function to clean up CloudWatch logs
cleanup_cloudwatch_logs() {
    if [ -z "$FUNCTION_NAME" ]; then
        warning "Lambda function name not provided, skipping log cleanup"
        return
    fi
    
    log "Cleaning up CloudWatch log groups..."
    
    LOG_GROUP="/aws/lambda/${FUNCTION_NAME}"
    
    # Check if log group exists
    if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP}" \
        --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${LOG_GROUP}"; then
        
        log "Deleting CloudWatch log group: ${LOG_GROUP}"
        aws logs delete-log-group --log-group-name "${LOG_GROUP}"
        success "CloudWatch log group deleted"
    else
        warning "CloudWatch log group ${LOG_GROUP} not found, skipping"
    fi
}

# Function to remove local files
remove_local_files() {
    log "Cleaning up local files..."
    
    # Remove resource environment file
    if [ -f "weather-resources.env" ]; then
        log "Removing weather-resources.env file..."
        rm -f weather-resources.env
        success "Local environment file removed"
    fi
    
    # Remove any temporary files
    rm -f response.json trust-policy.json sns-policy.json 2>/dev/null || true
    
    success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check Lambda function
    if [ -n "$FUNCTION_NAME" ]; then
        if aws lambda get-function --function-name "${FUNCTION_NAME}" &> /dev/null; then
            error "Lambda function ${FUNCTION_NAME} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check EventBridge rule
    if [ -n "$RULE_NAME" ]; then
        if aws events describe-rule --name "${RULE_NAME}" &> /dev/null; then
            error "EventBridge rule ${RULE_NAME} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check IAM role
    if [ -n "$ROLE_NAME" ]; then
        if aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
            error "IAM role ${ROLE_NAME} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check SNS topic
    if [ -n "$SNS_TOPIC_NAME" ]; then
        if aws sns list-topics --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')]" \
            --output text 2>/dev/null | grep -q "${SNS_TOPIC_NAME}"; then
            error "SNS topic ${SNS_TOPIC_NAME} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        success "All resources successfully cleaned up"
    else
        error "Some resources may not have been cleaned up properly"
        warning "Please check the AWS console and remove any remaining resources manually"
        return 1
    fi
}

# Function to display cleanup summary
display_summary() {
    echo
    echo "=================================="
    success "CLEANUP COMPLETED"
    echo "=================================="
    echo
    log "Deleted Resources:"
    
    if [ -n "$FUNCTION_NAME" ]; then
        echo "  ✅ Lambda Function: ${FUNCTION_NAME}"
    fi
    
    if [ -n "$RULE_NAME" ]; then
        echo "  ✅ EventBridge Rule: ${RULE_NAME}"
    fi
    
    if [ -n "$SNS_TOPIC_NAME" ]; then
        echo "  ✅ SNS Topic: ${SNS_TOPIC_NAME}"
    fi
    
    if [ -n "$ROLE_NAME" ]; then
        echo "  ✅ IAM Role: ${ROLE_NAME}"
    fi
    
    echo "  ✅ CloudWatch Log Groups"
    echo "  ✅ Local Files"
    echo
    log "All weather alert notification resources have been removed"
    warning "If you had email subscriptions, you may still receive a final unsubscribe notification"
    echo
}

# Function to handle partial cleanup on error
cleanup_on_error() {
    error "Cleanup process encountered an error"
    warning "Some resources may not have been deleted"
    log "Please check the AWS console and remove any remaining resources manually"
    
    if [ -f "weather-resources.env" ]; then
        log "Resource information is still available in weather-resources.env"
        log "You can re-run this script to attempt cleanup again"
    fi
    
    exit 1
}

# Main cleanup function
main() {
    log "Starting Weather Alert Notifications cleanup..."
    echo
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_deletion
    
    echo
    log "Beginning resource cleanup..."
    
    # Clean up resources in reverse order of creation
    remove_eventbridge_rule
    delete_lambda_function
    remove_sns_resources
    cleanup_iam_role
    cleanup_cloudwatch_logs
    remove_local_files
    
    # Verify cleanup
    sleep 5  # Wait a moment for AWS eventual consistency
    verify_cleanup
    
    display_summary
    log "Cleanup process completed!"
}

# Handle script interruption
trap 'cleanup_on_error' INT TERM ERR

# Run main function
main "$@"