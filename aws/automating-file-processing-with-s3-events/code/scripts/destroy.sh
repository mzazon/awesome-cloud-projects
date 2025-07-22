#!/bin/bash

# S3 Event Notifications Automated Processing - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
FORCE_CLEANUP=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/deployment_state.env"

# Logging functions
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_CLEANUP=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Function to show help
show_help() {
    echo "S3 Event Notifications Cleanup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --force     Skip confirmation prompts and force cleanup"
    echo "  -h, --help  Show this help message"
    echo
    echo "This script will remove all AWS resources created by the deployment script."
    echo "Make sure you have the deployment state file or valid environment variables."
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed"
        error "Please install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
        exit 1
    fi
    
    # Check AWS authentication
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured or credentials are invalid"
        error "Please run 'aws configure' or set up your credentials"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    
    if [ -z "$region" ]; then
        error "AWS region is not configured"
        error "Please run 'aws configure set region <your-region>'"
        exit 1
    fi
    
    success "Prerequisites verified (Account: $account_id, Region: $region)"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    # First, try to load from the state file
    if [ -f "$STATE_FILE" ]; then
        log "Loading state from: $STATE_FILE"
        source "$STATE_FILE"
        success "Deployment state loaded from file"
        return 0
    fi
    
    # If no state file, try to load from environment variables
    if [ -n "${BUCKET_NAME:-}" ] && [ -n "${SNS_TOPIC_ARN:-}" ]; then
        log "Using existing environment variables"
        success "Deployment state loaded from environment"
        return 0
    fi
    
    # If no state available, try to prompt user
    warning "No deployment state found"
    
    if [ "$FORCE_CLEANUP" = true ]; then
        error "Cannot proceed with --force without deployment state"
        exit 1
    fi
    
    echo
    echo "No deployment state file found. You can either:"
    echo "1. Provide resource names manually"
    echo "2. Exit and locate the deployment state file"
    echo
    read -p "Do you want to provide resource names manually? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled"
        exit 0
    fi
    
    prompt_for_resources
}

# Function to prompt for resource information
prompt_for_resources() {
    log "Please provide the resource information to clean up..."
    
    read -p "AWS Region: " AWS_REGION
    read -p "S3 Bucket Name: " BUCKET_NAME
    read -p "SNS Topic Name: " SNS_TOPIC_NAME
    read -p "SQS Queue Name: " SQS_QUEUE_NAME
    read -p "Lambda Function Name: " LAMBDA_FUNCTION_NAME
    
    # Derive other values
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    export LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_FUNCTION_NAME}-role"
    
    # Try to get SQS queue URL
    export SQS_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" --query QueueUrl --output text 2>/dev/null || echo "")
    if [ -n "$SQS_QUEUE_URL" ]; then
        export SQS_QUEUE_ARN=$(aws sqs get-queue-attributes \
            --queue-url "$SQS_QUEUE_URL" \
            --attribute-names QueueArn \
            --query 'Attributes.QueueArn' --output text 2>/dev/null || echo "")
    fi
    
    success "Resource information collected"
}

# Function to confirm cleanup
confirm_cleanup() {
    if [ "$FORCE_CLEANUP" = true ]; then
        warning "Force cleanup enabled - skipping confirmation"
        return 0
    fi
    
    echo
    echo "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "======================================"
    echo
    echo "The following AWS resources will be PERMANENTLY DELETED:"
    echo
    [ -n "${BUCKET_NAME:-}" ] && echo "• S3 Bucket: $BUCKET_NAME (including ALL contents)"
    [ -n "${SNS_TOPIC_ARN:-}" ] && echo "• SNS Topic: $SNS_TOPIC_ARN"
    [ -n "${SQS_QUEUE_URL:-}" ] && echo "• SQS Queue: $SQS_QUEUE_URL"
    [ -n "${LAMBDA_FUNCTION_NAME:-}" ] && echo "• Lambda Function: $LAMBDA_FUNCTION_NAME"
    [ -n "${LAMBDA_FUNCTION_NAME:-}" ] && echo "• IAM Role: ${LAMBDA_FUNCTION_NAME}-role"
    [ -n "${LAMBDA_FUNCTION_NAME:-}" ] && echo "• CloudWatch Log Group: /aws/lambda/${LAMBDA_FUNCTION_NAME}"
    echo
    echo "💰 This will stop all charges associated with these resources."
    echo "📊 All data and logs will be permanently lost."
    echo
    
    read -p "Are you absolutely sure you want to proceed? (type 'DELETE' to confirm): " -r
    echo
    
    if [ "$REPLY" != "DELETE" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Cleanup confirmed - proceeding with resource deletion"
}

# Function to remove S3 event notifications
remove_s3_notifications() {
    if [ -z "${BUCKET_NAME:-}" ]; then
        warning "No S3 bucket name provided, skipping notification cleanup"
        return 0
    fi
    
    log "Removing S3 event notification configuration..."
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        warning "S3 bucket $BUCKET_NAME does not exist or is not accessible"
        return 0
    fi
    
    # Remove notification configuration
    aws s3api put-bucket-notification-configuration \
        --bucket "$BUCKET_NAME" \
        --notification-configuration '{}' || warning "Failed to remove S3 notifications"
    
    success "S3 event notifications removed"
}

# Function to delete Lambda function and role
delete_lambda_resources() {
    if [ -z "${LAMBDA_FUNCTION_NAME:-}" ]; then
        warning "No Lambda function name provided, skipping Lambda cleanup"
        return 0
    fi
    
    log "Deleting Lambda function: $LAMBDA_FUNCTION_NAME..."
    
    # Remove Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
        success "Lambda function deleted: $LAMBDA_FUNCTION_NAME"
    else
        warning "Lambda function $LAMBDA_FUNCTION_NAME not found"
    fi
    
    # Delete IAM role
    local role_name="${LAMBDA_FUNCTION_NAME}-role"
    log "Deleting IAM role: $role_name..."
    
    if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
        # Detach policies first
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        # Delete the role
        aws iam delete-role --role-name "$role_name"
        success "IAM role deleted: $role_name"
    else
        warning "IAM role $role_name not found"
    fi
}

# Function to delete SQS queue
delete_sqs_queue() {
    if [ -z "${SQS_QUEUE_URL:-}" ] && [ -z "${SQS_QUEUE_NAME:-}" ]; then
        warning "No SQS queue information provided, skipping SQS cleanup"
        return 0
    fi
    
    log "Deleting SQS queue..."
    
    # Get queue URL if we only have the name
    if [ -z "${SQS_QUEUE_URL:-}" ] && [ -n "${SQS_QUEUE_NAME:-}" ]; then
        SQS_QUEUE_URL=$(aws sqs get-queue-url --queue-name "$SQS_QUEUE_NAME" --query QueueUrl --output text 2>/dev/null || echo "")
    fi
    
    if [ -n "${SQS_QUEUE_URL:-}" ]; then
        # Purge queue first (optional)
        log "Purging SQS queue messages..."
        aws sqs purge-queue --queue-url "$SQS_QUEUE_URL" 2>/dev/null || warning "Failed to purge queue"
        
        # Wait a moment for purge to complete
        sleep 2
        
        # Delete queue
        aws sqs delete-queue --queue-url "$SQS_QUEUE_URL"
        success "SQS queue deleted: $SQS_QUEUE_URL"
    else
        warning "SQS queue not found or not accessible"
    fi
}

# Function to delete SNS topic
delete_sns_topic() {
    if [ -z "${SNS_TOPIC_ARN:-}" ] && [ -z "${SNS_TOPIC_NAME:-}" ]; then
        warning "No SNS topic information provided, skipping SNS cleanup"
        return 0
    fi
    
    log "Deleting SNS topic..."
    
    # Construct topic ARN if we only have the name
    if [ -z "${SNS_TOPIC_ARN:-}" ] && [ -n "${SNS_TOPIC_NAME:-}" ]; then
        local aws_region=${AWS_REGION:-$(aws configure get region)}
        local aws_account=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
        SNS_TOPIC_ARN="arn:aws:sns:${aws_region}:${aws_account}:${SNS_TOPIC_NAME}"
    fi
    
    if [ -n "${SNS_TOPIC_ARN:-}" ]; then
        # List and delete all subscriptions first
        log "Removing SNS topic subscriptions..."
        local subscriptions=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$SNS_TOPIC_ARN" \
            --query 'Subscriptions[].SubscriptionArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$subscriptions" ] && [ "$subscriptions" != "None" ]; then
            for sub_arn in $subscriptions; do
                if [ "$sub_arn" != "PendingConfirmation" ]; then
                    aws sns unsubscribe --subscription-arn "$sub_arn" 2>/dev/null || warning "Failed to unsubscribe $sub_arn"
                fi
            done
        fi
        
        # Delete topic
        aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN"
        success "SNS topic deleted: $SNS_TOPIC_ARN"
    else
        warning "SNS topic not found or not accessible"
    fi
}

# Function to delete S3 bucket and contents
delete_s3_bucket() {
    if [ -z "${BUCKET_NAME:-}" ]; then
        warning "No S3 bucket name provided, skipping S3 cleanup"
        return 0
    fi
    
    log "Deleting S3 bucket: $BUCKET_NAME..."
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        warning "S3 bucket $BUCKET_NAME does not exist or is not accessible"
        return 0
    fi
    
    # List objects to see what we're deleting
    local object_count=$(aws s3api list-objects-v2 --bucket "$BUCKET_NAME" --query 'length(Contents)' --output text 2>/dev/null || echo "0")
    if [ "$object_count" != "0" ] && [ "$object_count" != "None" ]; then
        log "Found $object_count objects in bucket, deleting all contents..."
    fi
    
    # Delete all objects and versions (including delete markers)
    log "Removing all objects from bucket..."
    aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>/dev/null || warning "Some objects may not have been deleted"
    
    # Delete any versioned objects if versioning is enabled
    log "Checking for versioned objects..."
    local versions=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --query 'length(Versions)' --output text 2>/dev/null || echo "0")
    if [ "$versions" != "0" ] && [ "$versions" != "None" ]; then
        log "Found versioned objects, removing all versions..."
        aws s3api list-object-versions --bucket "$BUCKET_NAME" --output json | \
        jq -r '.Versions[]? | [.Key, .VersionId] | @tsv' | \
        while IFS=$'\t' read -r key version; do
            aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version" 2>/dev/null || true
        done 2>/dev/null || warning "Failed to delete some versioned objects"
    fi
    
    # Delete any delete markers
    local delete_markers=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --query 'length(DeleteMarkers)' --output text 2>/dev/null || echo "0")
    if [ "$delete_markers" != "0" ] && [ "$delete_markers" != "None" ]; then
        log "Found delete markers, removing them..."
        aws s3api list-object-versions --bucket "$BUCKET_NAME" --output json | \
        jq -r '.DeleteMarkers[]? | [.Key, .VersionId] | @tsv' | \
        while IFS=$'\t' read -r key version; do
            aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version" 2>/dev/null || true
        done 2>/dev/null || warning "Failed to delete some delete markers"
    fi
    
    # Wait for eventual consistency
    log "Waiting for eventual consistency..."
    sleep 3
    
    # Delete the bucket
    aws s3 rb "s3://${BUCKET_NAME}" --force
    success "S3 bucket deleted: $BUCKET_NAME"
}

# Function to delete CloudWatch log group
delete_cloudwatch_logs() {
    if [ -z "${LAMBDA_FUNCTION_NAME:-}" ]; then
        warning "No Lambda function name provided, skipping CloudWatch logs cleanup"
        return 0
    fi
    
    local log_group_name="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
    
    log "Deleting CloudWatch log group: $log_group_name..."
    
    # Check if log group exists
    if aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --query 'logGroups[?logGroupName==`'$log_group_name'`]' --output text | grep -q "$log_group_name"; then
        aws logs delete-log-group --log-group-name "$log_group_name"
        success "CloudWatch log group deleted: $log_group_name"
    else
        warning "CloudWatch log group $log_group_name not found"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_errors=0
    
    # Check S3 bucket
    if [ -n "${BUCKET_NAME:-}" ]; then
        if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
            error "✗ S3 bucket $BUCKET_NAME still exists"
            cleanup_errors=$((cleanup_errors + 1))
        else
            success "✓ S3 bucket $BUCKET_NAME successfully deleted"
        fi
    fi
    
    # Check SNS topic
    if [ -n "${SNS_TOPIC_ARN:-}" ]; then
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" >/dev/null 2>&1; then
            error "✗ SNS topic $SNS_TOPIC_ARN still exists"
            cleanup_errors=$((cleanup_errors + 1))
        else
            success "✓ SNS topic successfully deleted"
        fi
    fi
    
    # Check SQS queue
    if [ -n "${SQS_QUEUE_URL:-}" ]; then
        if aws sqs get-queue-attributes --queue-url "$SQS_QUEUE_URL" >/dev/null 2>&1; then
            error "✗ SQS queue $SQS_QUEUE_URL still exists"
            cleanup_errors=$((cleanup_errors + 1))
        else
            success "✓ SQS queue successfully deleted"
        fi
    fi
    
    # Check Lambda function
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
            error "✗ Lambda function $LAMBDA_FUNCTION_NAME still exists"
            cleanup_errors=$((cleanup_errors + 1))
        else
            success "✓ Lambda function successfully deleted"
        fi
        
        # Check IAM role
        local role_name="${LAMBDA_FUNCTION_NAME}-role"
        if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
            error "✗ IAM role $role_name still exists"
            cleanup_errors=$((cleanup_errors + 1))
        else
            success "✓ IAM role successfully deleted"
        fi
    fi
    
    if [ $cleanup_errors -eq 0 ]; then
        success "All resources verified as deleted!"
    else
        warning "$cleanup_errors resources may not have been fully deleted"
        warning "Please check the AWS console and manually remove any remaining resources"
    fi
    
    return $cleanup_errors
}

# Function to clean up deployment state
cleanup_deployment_state() {
    log "Cleaning up deployment state..."
    
    # Remove state file
    if [ -f "$STATE_FILE" ]; then
        rm -f "$STATE_FILE"
        success "Deployment state file removed"
    fi
    
    # Clean up temporary directory if it exists
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        success "Temporary directory cleaned up"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo
    echo "🧹 Cleanup Summary"
    echo "=================="
    echo
    echo "✅ S3 Event Notifications Architecture Cleanup Completed!"
    echo
    echo "🗑️  Resources Removed:"
    [ -n "${BUCKET_NAME:-}" ] && echo "  • S3 Bucket: $BUCKET_NAME (and all contents)"
    [ -n "${SNS_TOPIC_ARN:-}" ] && echo "  • SNS Topic: $SNS_TOPIC_ARN"
    [ -n "${SQS_QUEUE_URL:-}" ] && echo "  • SQS Queue: $SQS_QUEUE_URL"
    [ -n "${LAMBDA_FUNCTION_NAME:-}" ] && echo "  • Lambda Function: $LAMBDA_FUNCTION_NAME"
    [ -n "${LAMBDA_FUNCTION_NAME:-}" ] && echo "  • IAM Role: ${LAMBDA_FUNCTION_NAME}-role"
    [ -n "${LAMBDA_FUNCTION_NAME:-}" ] && echo "  • CloudWatch Log Group: /aws/lambda/${LAMBDA_FUNCTION_NAME}"
    echo
    echo "💰 All associated AWS charges have been stopped."
    echo "📊 All data and configuration has been permanently removed."
    echo
    echo "🎯 Next Steps:"
    echo "  • Verify in AWS Console that all resources are removed"
    echo "  • Check your AWS bill to confirm charges have stopped"
    echo "  • Save any important data before running future deployments"
    echo
}

# Main cleanup function
main() {
    echo "🧹 Starting S3 Event Notifications Cleanup"
    echo "==========================================="
    echo
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment state
    load_deployment_state
    
    # Confirm cleanup
    confirm_cleanup
    
    # Perform cleanup in reverse order of creation
    log "Starting resource cleanup..."
    
    # Remove S3 event notifications first
    remove_s3_notifications
    
    # Delete compute resources
    delete_lambda_resources
    
    # Delete messaging resources
    delete_sqs_queue
    delete_sns_topic
    
    # Delete storage resources (S3 bucket last as it contains data)
    delete_s3_bucket
    
    # Delete monitoring resources
    delete_cloudwatch_logs
    
    # Verify cleanup
    verify_cleanup
    
    # Clean up deployment state
    cleanup_deployment_state
    
    # Display summary
    display_cleanup_summary
    
    success "🎉 Cleanup completed successfully!"
}

# Run main function with all arguments
main "$@"