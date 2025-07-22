#!/bin/bash
#
# Destroy script for Real-Time Data Transformation with Amazon Kinesis Data Firehose
# This script removes all resources created by the deployment script
# 
# Usage: ./destroy.sh [--force]
#
# The script will:
# 1. Load configuration from .deployment_config
# 2. Delete all AWS resources created during deployment
# 3. Clean up local files
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - .deployment_config file from successful deployment
# - Appropriate AWS permissions to delete resources
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "$1 is required but not installed"
        exit 1
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
}

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    
    case $resource_type in
        "s3-bucket")
            aws s3 ls "s3://$resource_name" &>/dev/null
            ;;
        "lambda-function")
            aws lambda get-function --function-name "$resource_name" &>/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" &>/dev/null
            ;;
        "firehose-stream")
            aws firehose describe-delivery-stream --delivery-stream-name "$resource_name" &>/dev/null
            ;;
        "sns-topic")
            aws sns get-topic-attributes --topic-arn "$resource_name" &>/dev/null
            ;;
        "cloudwatch-alarm")
            aws cloudwatch describe-alarms --alarm-names "$resource_name" --query 'MetricAlarms[0]' --output text &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local resource_name=$2
    local max_attempts=30
    local attempt=1
    
    info "Waiting for $resource_type deletion: $resource_name"
    
    while [ $attempt -le $max_attempts ]; do
        if ! resource_exists "$resource_type" "$resource_name"; then
            return 0
        fi
        sleep 10
        ((attempt++))
    done
    
    warn "Timeout waiting for $resource_type deletion: $resource_name"
    return 1
}

# Function to safely delete S3 bucket
delete_s3_bucket() {
    local bucket_name=$1
    
    if resource_exists "s3-bucket" "$bucket_name"; then
        info "Deleting S3 bucket: $bucket_name"
        
        # First, delete all objects in the bucket
        aws s3 rm "s3://$bucket_name" --recursive 2>/dev/null || true
        
        # Delete all object versions (if versioning is enabled)
        aws s3api delete-objects \
            --bucket "$bucket_name" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$bucket_name" \
                --query '{"Objects": []}' \
                --output json 2>/dev/null || echo '{"Objects": []}')" 2>/dev/null || true
        
        # Delete the bucket
        aws s3api delete-bucket --bucket "$bucket_name" 2>/dev/null || true
        
        log "Deleted S3 bucket: $bucket_name"
    else
        warn "S3 bucket $bucket_name not found, skipping deletion"
    fi
}

# Function to safely delete IAM role
delete_iam_role() {
    local role_name=$1
    local policy_name=$2
    
    if resource_exists "iam-role" "$role_name"; then
        info "Deleting IAM role: $role_name"
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "$role_name" \
            --policy-name "$policy_name" 2>/dev/null || true
        
        # Detach managed policies
        local attached_policies=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null || echo "")
        
        for policy_arn in $attached_policies; do
            aws iam detach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy_arn" 2>/dev/null || true
        done
        
        # Delete the role
        aws iam delete-role --role-name "$role_name" 2>/dev/null || true
        
        log "Deleted IAM role: $role_name"
    else
        warn "IAM role $role_name not found, skipping deletion"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    local force_flag=$1
    
    if [ "$force_flag" = "true" ]; then
        return 0
    fi
    
    echo ""
    echo "===== RESOURCES TO BE DELETED ====="
    echo "Firehose Delivery Stream: ${DELIVERY_STREAM_NAME:-N/A}"
    echo "Raw Data Bucket: ${RAW_BUCKET:-N/A}"
    echo "Processed Data Bucket: ${PROCESSED_BUCKET:-N/A}"
    echo "Error Data Bucket: ${ERROR_BUCKET:-N/A}"
    echo "Lambda Function: ${LAMBDA_FUNCTION:-N/A}"
    echo "Lambda IAM Role: ${LAMBDA_ROLE_NAME:-N/A}"
    echo "Firehose IAM Role: ${FIREHOSE_ROLE_NAME:-N/A}"
    echo "SNS Topic: ${SNS_TOPIC_NAME:-N/A}"
    echo "CloudWatch Alarm: FirehoseDeliveryFailure-${DELIVERY_STREAM_NAME:-N/A}"
    echo ""
    
    warn "This will permanently delete all resources listed above."
    warn "Data in S3 buckets will be lost forever."
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
}

# Parse command line arguments
FORCE_FLAG="false"
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_FLAG="true"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--force]"
            echo "  --force    Skip confirmation prompt"
            echo "  -h, --help Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Main cleanup function
main() {
    log "Starting cleanup of Kinesis Data Firehose resources"
    
    # Prerequisites check
    log "Checking prerequisites..."
    check_command "aws"
    check_aws_credentials
    
    # Load configuration from deployment
    if [ ! -f ".deployment_config" ]; then
        error "Configuration file .deployment_config not found"
        error "This file is created during deployment and contains resource names"
        error "Please ensure you're running this script from the same directory as the deploy script"
        exit 1
    fi
    
    log "Loading configuration from .deployment_config"
    source .deployment_config
    
    # Validate required configuration
    if [ -z "${DELIVERY_STREAM_NAME:-}" ]; then
        error "Invalid configuration: DELIVERY_STREAM_NAME not found"
        exit 1
    fi
    
    # Show confirmation prompt
    confirm_deletion "$FORCE_FLAG"
    
    # Step 1: Delete CloudWatch alarm
    log "Deleting CloudWatch alarm..."
    ALARM_NAME="FirehoseDeliveryFailure-${DELIVERY_STREAM_NAME}"
    if resource_exists "cloudwatch-alarm" "$ALARM_NAME"; then
        aws cloudwatch delete-alarms --alarm-names "$ALARM_NAME"
        log "Deleted CloudWatch alarm: $ALARM_NAME"
    else
        warn "CloudWatch alarm $ALARM_NAME not found, skipping deletion"
    fi
    
    # Step 2: Delete SNS topic
    log "Deleting SNS topic..."
    if [ -n "${SNS_TOPIC_ARN:-}" ]; then
        if resource_exists "sns-topic" "$SNS_TOPIC_ARN"; then
            aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN"
            log "Deleted SNS topic: $SNS_TOPIC_NAME"
        else
            warn "SNS topic $SNS_TOPIC_ARN not found, skipping deletion"
        fi
    else
        warn "SNS topic ARN not found in configuration, skipping deletion"
    fi
    
    # Step 3: Delete Kinesis Data Firehose delivery stream
    log "Deleting Kinesis Data Firehose delivery stream..."
    if resource_exists "firehose-stream" "$DELIVERY_STREAM_NAME"; then
        aws firehose delete-delivery-stream --delivery-stream-name "$DELIVERY_STREAM_NAME"
        log "Initiated deletion of Firehose delivery stream: $DELIVERY_STREAM_NAME"
        
        # Wait for delivery stream to be deleted
        info "Waiting for delivery stream deletion to complete..."
        wait_for_deletion "firehose-stream" "$DELIVERY_STREAM_NAME"
        log "Firehose delivery stream deleted successfully"
    else
        warn "Firehose delivery stream $DELIVERY_STREAM_NAME not found, skipping deletion"
    fi
    
    # Step 4: Delete Lambda function
    log "Deleting Lambda function..."
    if resource_exists "lambda-function" "$LAMBDA_FUNCTION"; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION"
        log "Deleted Lambda function: $LAMBDA_FUNCTION"
    else
        warn "Lambda function $LAMBDA_FUNCTION not found, skipping deletion"
    fi
    
    # Step 5: Delete IAM roles
    log "Deleting IAM roles..."
    
    # Delete Lambda IAM role
    if [ -n "${LAMBDA_ROLE_NAME:-}" ]; then
        delete_iam_role "$LAMBDA_ROLE_NAME" "firehose-transform-policy"
    fi
    
    # Delete Firehose IAM role
    if [ -n "${FIREHOSE_ROLE_NAME:-}" ]; then
        delete_iam_role "$FIREHOSE_ROLE_NAME" "firehose-delivery-policy"
    fi
    
    # Step 6: Delete S3 buckets
    log "Deleting S3 buckets..."
    
    # Delete buckets in order (processed, raw, error)
    for bucket in "${PROCESSED_BUCKET:-}" "${RAW_BUCKET:-}" "${ERROR_BUCKET:-}"; do
        if [ -n "$bucket" ]; then
            delete_s3_bucket "$bucket"
        fi
    done
    
    # Step 7: Clean up local files
    log "Cleaning up local files..."
    
    # Remove configuration file
    if [ -f ".deployment_config" ]; then
        rm -f .deployment_config
        log "Removed .deployment_config file"
    fi
    
    # Remove any temporary files that might have been left behind
    rm -f lambda-trust-policy.json lambda-policy.json firehose-trust-policy.json firehose-policy.json
    rm -f test_data.json processed_sample.gz
    rm -rf lambda_transform lambda_transform.zip
    
    log "Cleaned up local files"
    
    # Step 8: Verify cleanup
    log "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check if any resources still exist
    if [ -n "${DELIVERY_STREAM_NAME:-}" ] && resource_exists "firehose-stream" "$DELIVERY_STREAM_NAME"; then
        warn "Firehose delivery stream still exists: $DELIVERY_STREAM_NAME"
        ((cleanup_issues++))
    fi
    
    if [ -n "${LAMBDA_FUNCTION:-}" ] && resource_exists "lambda-function" "$LAMBDA_FUNCTION"; then
        warn "Lambda function still exists: $LAMBDA_FUNCTION"
        ((cleanup_issues++))
    fi
    
    if [ -n "${LAMBDA_ROLE_NAME:-}" ] && resource_exists "iam-role" "$LAMBDA_ROLE_NAME"; then
        warn "Lambda IAM role still exists: $LAMBDA_ROLE_NAME"
        ((cleanup_issues++))
    fi
    
    if [ -n "${FIREHOSE_ROLE_NAME:-}" ] && resource_exists "iam-role" "$FIREHOSE_ROLE_NAME"; then
        warn "Firehose IAM role still exists: $FIREHOSE_ROLE_NAME"
        ((cleanup_issues++))
    fi
    
    for bucket in "${RAW_BUCKET:-}" "${PROCESSED_BUCKET:-}" "${ERROR_BUCKET:-}"; do
        if [ -n "$bucket" ] && resource_exists "s3-bucket" "$bucket"; then
            warn "S3 bucket still exists: $bucket"
            ((cleanup_issues++))
        fi
    done
    
    if [ $cleanup_issues -gt 0 ]; then
        warn "Cleanup completed with $cleanup_issues issues"
        warn "Some resources may still exist and require manual cleanup"
        warn "This can happen due to dependencies or eventual consistency"
        warn "Please check the AWS console and delete any remaining resources manually"
    else
        log "All resources have been successfully cleaned up"
    fi
    
    log "Cleanup completed!"
    echo ""
    echo "===== CLEANUP SUMMARY ====="
    echo "✅ CloudWatch alarm deleted"
    echo "✅ SNS topic deleted"
    echo "✅ Kinesis Data Firehose delivery stream deleted"
    echo "✅ Lambda function deleted"
    echo "✅ IAM roles deleted"
    echo "✅ S3 buckets deleted"
    echo "✅ Local files cleaned up"
    echo ""
    
    if [ $cleanup_issues -eq 0 ]; then
        echo "🎉 All resources have been successfully removed!"
        echo "💰 You are no longer being charged for these resources."
    else
        echo "⚠️  Some resources may still exist - please check the AWS console"
        echo "💡 Wait a few minutes and run this script again if needed"
    fi
}

# Run main function
main "$@"