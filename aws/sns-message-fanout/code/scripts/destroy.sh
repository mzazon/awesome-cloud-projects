#!/bin/bash

# Destroy script for SNS-SQS Message Fan-out Recipe
# This script safely removes all resources created by the deployment

set -e  # Exit on any error

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
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
    
    success "Prerequisites check passed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to load from saved environment file
    if [ -f "/tmp/sns-fanout-env.sh" ]; then
        source /tmp/sns-fanout-env.sh
        log "Environment variables loaded from saved file"
    else
        warning "Saved environment file not found. Please provide resource identifiers manually."
        
        # Prompt for essential variables if not found
        if [ -z "$RANDOM_SUFFIX" ]; then
            read -p "Enter the random suffix used during deployment: " RANDOM_SUFFIX
            export RANDOM_SUFFIX
        fi
        
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION=$(aws configure get region)
            if [ -z "$AWS_REGION" ]; then
                export AWS_REGION="us-east-1"
            fi
        fi
        
        if [ -z "$AWS_ACCOUNT_ID" ]; then
            export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        fi
        
        # Reconstruct resource names
        export TOPIC_NAME="order-events-${RANDOM_SUFFIX}"
        export INVENTORY_QUEUE_NAME="inventory-processing-${RANDOM_SUFFIX}"
        export PAYMENT_QUEUE_NAME="payment-processing-${RANDOM_SUFFIX}"
        export SHIPPING_QUEUE_NAME="shipping-notifications-${RANDOM_SUFFIX}"
        export ANALYTICS_QUEUE_NAME="analytics-reporting-${RANDOM_SUFFIX}"
        export SNS_ROLE_NAME="sns-sqs-fanout-role-${RANDOM_SUFFIX}"
        export TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${TOPIC_NAME}"
    fi
    
    log "Environment variables configured for cleanup"
}

# Function to confirm destruction
confirm_destruction() {
    echo "=========================================="
    echo "RESOURCE DESTRUCTION CONFIRMATION"
    echo "=========================================="
    echo "This will permanently delete the following resources:"
    echo "- SNS Topic: ${TOPIC_NAME}"
    echo "- SQS Queues: ${INVENTORY_QUEUE_NAME}, ${PAYMENT_QUEUE_NAME}, ${SHIPPING_QUEUE_NAME}, ${ANALYTICS_QUEUE_NAME}"
    echo "- Dead Letter Queues: inventory-dlq-${RANDOM_SUFFIX}, payment-dlq-${RANDOM_SUFFIX}, shipping-dlq-${RANDOM_SUFFIX}, analytics-dlq-${RANDOM_SUFFIX}"
    echo "- IAM Role: ${SNS_ROLE_NAME}"
    echo "- CloudWatch Alarms and Dashboard"
    echo "=========================================="
    
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed. Proceeding with cleanup..."
}

# Function to delete SNS subscriptions and topic
delete_sns_resources() {
    log "Deleting SNS subscriptions and topic..."
    
    # Check if topic exists
    if aws sns get-topic-attributes --topic-arn "$TOPIC_ARN" &> /dev/null; then
        # List and delete all subscriptions
        SUBSCRIPTION_ARNS=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$TOPIC_ARN" \
            --query 'Subscriptions[].SubscriptionArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$SUBSCRIPTION_ARNS" ]; then
            for SUB_ARN in $SUBSCRIPTION_ARNS; do
                if [ "$SUB_ARN" != "None" ] && [ "$SUB_ARN" != "" ]; then
                    aws sns unsubscribe --subscription-arn "$SUB_ARN" 2>/dev/null || true
                fi
            done
            log "SNS subscriptions deleted"
        fi
        
        # Delete SNS topic
        aws sns delete-topic --topic-arn "$TOPIC_ARN" 2>/dev/null || true
        success "SNS topic deleted: ${TOPIC_NAME}"
    else
        warning "SNS topic not found or already deleted: ${TOPIC_NAME}"
    fi
}

# Function to delete SQS queues
delete_sqs_queues() {
    log "Deleting SQS queues..."
    
    # Get queue URLs (if they exist)
    INVENTORY_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$INVENTORY_QUEUE_NAME" --query QueueUrl --output text 2>/dev/null || echo "")
    PAYMENT_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$PAYMENT_QUEUE_NAME" --query QueueUrl --output text 2>/dev/null || echo "")
    SHIPPING_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$SHIPPING_QUEUE_NAME" --query QueueUrl --output text 2>/dev/null || echo "")
    ANALYTICS_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$ANALYTICS_QUEUE_NAME" --query QueueUrl --output text 2>/dev/null || echo "")
    
    # Delete primary queues
    for queue_url in "$INVENTORY_QUEUE_URL" "$PAYMENT_QUEUE_URL" "$SHIPPING_QUEUE_URL" "$ANALYTICS_QUEUE_URL"; do
        if [ -n "$queue_url" ] && [ "$queue_url" != "None" ]; then
            aws sqs delete-queue --queue-url "$queue_url" 2>/dev/null || true
        fi
    done
    
    # Get DLQ URLs (if they exist)
    INVENTORY_DLQ_URL=$(aws sqs get-queue-url --queue-name "inventory-dlq-${RANDOM_SUFFIX}" --query QueueUrl --output text 2>/dev/null || echo "")
    PAYMENT_DLQ_URL=$(aws sqs get-queue-url --queue-name "payment-dlq-${RANDOM_SUFFIX}" --query QueueUrl --output text 2>/dev/null || echo "")
    SHIPPING_DLQ_URL=$(aws sqs get-queue-url --queue-name "shipping-dlq-${RANDOM_SUFFIX}" --query QueueUrl --output text 2>/dev/null || echo "")
    ANALYTICS_DLQ_URL=$(aws sqs get-queue-url --queue-name "analytics-dlq-${RANDOM_SUFFIX}" --query QueueUrl --output text 2>/dev/null || echo "")
    
    # Delete dead letter queues
    for dlq_url in "$INVENTORY_DLQ_URL" "$PAYMENT_DLQ_URL" "$SHIPPING_DLQ_URL" "$ANALYTICS_DLQ_URL"; do
        if [ -n "$dlq_url" ] && [ "$dlq_url" != "None" ]; then
            aws sqs delete-queue --queue-url "$dlq_url" 2>/dev/null || true
        fi
    done
    
    success "SQS queues and dead letter queues deleted"
}

# Function to delete CloudWatch resources
delete_cloudwatch_resources() {
    log "Deleting CloudWatch alarms and dashboard..."
    
    # Delete CloudWatch alarms
    aws cloudwatch delete-alarms \
        --alarm-names \
        "inventory-queue-depth-${RANDOM_SUFFIX}" \
        "payment-queue-depth-${RANDOM_SUFFIX}" \
        "sns-failed-deliveries-${RANDOM_SUFFIX}" \
        2>/dev/null || true
    
    # Delete CloudWatch dashboard
    aws cloudwatch delete-dashboards \
        --dashboard-names "sns-fanout-dashboard-${RANDOM_SUFFIX}" \
        2>/dev/null || true
    
    success "CloudWatch resources deleted"
}

# Function to delete IAM role
delete_iam_role() {
    log "Deleting IAM role..."
    
    # Check if role exists before attempting deletion
    if aws iam get-role --role-name "$SNS_ROLE_NAME" &> /dev/null; then
        # Detach any attached policies first
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$SNS_ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        
        if [ -n "$ATTACHED_POLICIES" ]; then
            for policy_arn in $ATTACHED_POLICIES; do
                aws iam detach-role-policy --role-name "$SNS_ROLE_NAME" --policy-arn "$policy_arn" 2>/dev/null || true
            done
        fi
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies --role-name "$SNS_ROLE_NAME" --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
        
        if [ -n "$INLINE_POLICIES" ]; then
            for policy_name in $INLINE_POLICIES; do
                aws iam delete-role-policy --role-name "$SNS_ROLE_NAME" --policy-name "$policy_name" 2>/dev/null || true
            done
        fi
        
        # Delete the role
        aws iam delete-role --role-name "$SNS_ROLE_NAME" 2>/dev/null || true
        success "IAM role deleted: ${SNS_ROLE_NAME}"
    else
        warning "IAM role not found or already deleted: ${SNS_ROLE_NAME}"
    fi
}

# Function to clean up environment files
cleanup_environment() {
    log "Cleaning up environment variables and temporary files..."
    
    # Remove temporary environment file
    if [ -f "/tmp/sns-fanout-env.sh" ]; then
        rm -f /tmp/sns-fanout-env.sh
        log "Temporary environment file removed"
    fi
    
    # Unset environment variables
    unset AWS_REGION AWS_ACCOUNT_ID RANDOM_SUFFIX
    unset TOPIC_NAME TOPIC_ARN SNS_ROLE_NAME
    unset INVENTORY_QUEUE_NAME INVENTORY_QUEUE_URL INVENTORY_QUEUE_ARN
    unset PAYMENT_QUEUE_NAME PAYMENT_QUEUE_URL PAYMENT_QUEUE_ARN
    unset SHIPPING_QUEUE_NAME SHIPPING_QUEUE_URL SHIPPING_QUEUE_ARN
    unset ANALYTICS_QUEUE_NAME ANALYTICS_QUEUE_URL ANALYTICS_QUEUE_ARN
    unset INVENTORY_DLQ_URL INVENTORY_DLQ_ARN
    unset PAYMENT_DLQ_URL PAYMENT_DLQ_ARN
    unset SHIPPING_DLQ_URL SHIPPING_DLQ_ARN
    unset ANALYTICS_DLQ_URL ANALYTICS_DLQ_ARN
    
    success "Environment cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    # Check if SNS topic still exists
    if aws sns get-topic-attributes --topic-arn "$TOPIC_ARN" &> /dev/null; then
        warning "SNS topic still exists: ${TOPIC_NAME}"
    else
        success "SNS topic successfully deleted"
    fi
    
    # Check if any SQS queues still exist
    REMAINING_QUEUES=$(aws sqs list-queues --queue-name-prefix "inventory-processing-${RANDOM_SUFFIX}" --query 'QueueUrls' --output text 2>/dev/null || echo "")
    REMAINING_QUEUES="${REMAINING_QUEUES} $(aws sqs list-queues --queue-name-prefix "payment-processing-${RANDOM_SUFFIX}" --query 'QueueUrls' --output text 2>/dev/null || echo "")"
    REMAINING_QUEUES="${REMAINING_QUEUES} $(aws sqs list-queues --queue-name-prefix "shipping-notifications-${RANDOM_SUFFIX}" --query 'QueueUrls' --output text 2>/dev/null || echo "")"
    REMAINING_QUEUES="${REMAINING_QUEUES} $(aws sqs list-queues --queue-name-prefix "analytics-reporting-${RANDOM_SUFFIX}" --query 'QueueUrls' --output text 2>/dev/null || echo "")"
    
    if [ -n "$REMAINING_QUEUES" ] && [ "$REMAINING_QUEUES" != "None" ]; then
        warning "Some SQS queues may still exist"
    else
        success "All SQS queues successfully deleted"
    fi
    
    # Check if IAM role still exists
    if aws iam get-role --role-name "$SNS_ROLE_NAME" &> /dev/null; then
        warning "IAM role still exists: ${SNS_ROLE_NAME}"
    else
        success "IAM role successfully deleted"
    fi
    
    log "Cleanup verification completed"
}

# Function to display destruction summary
display_summary() {
    log "Destruction Summary:"
    echo "======================================"
    echo "The following resources have been removed:"
    echo "- SNS Topic: ${TOPIC_NAME}"
    echo "- SQS Queues: ${INVENTORY_QUEUE_NAME}, ${PAYMENT_QUEUE_NAME}, ${SHIPPING_QUEUE_NAME}, ${ANALYTICS_QUEUE_NAME}"
    echo "- Dead Letter Queues: inventory-dlq-${RANDOM_SUFFIX}, payment-dlq-${RANDOM_SUFFIX}, shipping-dlq-${RANDOM_SUFFIX}, analytics-dlq-${RANDOM_SUFFIX}"
    echo "- IAM Role: ${SNS_ROLE_NAME}"
    echo "- CloudWatch Alarms: inventory-queue-depth-${RANDOM_SUFFIX}, payment-queue-depth-${RANDOM_SUFFIX}, sns-failed-deliveries-${RANDOM_SUFFIX}"
    echo "- CloudWatch Dashboard: sns-fanout-dashboard-${RANDOM_SUFFIX}"
    echo "======================================"
    echo "All resources have been successfully cleaned up."
    echo "No further charges will be incurred for these resources."
}

# Function to handle partial cleanup
handle_partial_cleanup() {
    log "Attempting partial cleanup in case of errors..."
    
    # Try to delete resources that might still exist
    delete_sns_resources
    delete_sqs_queues
    delete_cloudwatch_resources
    delete_iam_role
    
    warning "Partial cleanup completed. Some resources may still exist."
    warning "Please check the AWS console to verify all resources have been removed."
}

# Main destruction function
main() {
    echo "=========================================="
    echo "SNS-SQS Message Fan-out Destruction Script"
    echo "=========================================="
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    # Attempt cleanup with error handling
    if ! delete_sns_resources; then
        error "Failed to delete SNS resources"
    fi
    
    if ! delete_sqs_queues; then
        error "Failed to delete SQS queues"
    fi
    
    if ! delete_cloudwatch_resources; then
        error "Failed to delete CloudWatch resources"
    fi
    
    if ! delete_iam_role; then
        error "Failed to delete IAM role"
    fi
    
    cleanup_environment
    verify_cleanup
    display_summary
    
    success "Destruction completed successfully!"
}

# Handle script interruption
trap 'error "Destruction interrupted. Some resources may still exist."; handle_partial_cleanup; exit 1' INT

# Run main function
main "$@"