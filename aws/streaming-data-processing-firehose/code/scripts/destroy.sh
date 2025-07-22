#!/bin/bash

# Destroy script for Real-Time Data Processing with Kinesis Data Firehose
# This script removes all infrastructure created by deploy.sh

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
    fi
    
    log "Prerequisites check completed successfully"
}

# Load deployment configuration
load_deployment_config() {
    log "Loading deployment configuration..."
    
    # Check if configuration file exists
    if [ ! -f "./firehose-deployment-config.json" ]; then
        error "Deployment configuration file not found: firehose-deployment-config.json"
        error "Please ensure you're running this script from the same directory as deploy.sh"
        error "Or provide resource names as environment variables"
    fi
    
    # Load configuration from file
    export AWS_REGION=$(jq -r '.aws_region' ./firehose-deployment-config.json)
    export AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' ./firehose-deployment-config.json)
    export FIREHOSE_STREAM_NAME=$(jq -r '.firehose_stream_name' ./firehose-deployment-config.json)
    export S3_BUCKET_NAME=$(jq -r '.s3_bucket_name' ./firehose-deployment-config.json)
    export LAMBDA_FUNCTION_NAME=$(jq -r '.lambda_function_name' ./firehose-deployment-config.json)
    export OPENSEARCH_DOMAIN=$(jq -r '.opensearch_domain' ./firehose-deployment-config.json)
    export IAM_ROLE_NAME=$(jq -r '.iam_role_name' ./firehose-deployment-config.json)
    export OPENSEARCH_ENDPOINT=$(jq -r '.opensearch_endpoint' ./firehose-deployment-config.json)
    export FIREHOSE_ROLE_ARN=$(jq -r '.firehose_role_arn' ./firehose-deployment-config.json)
    export LAMBDA_FUNCTION_ARN=$(jq -r '.lambda_function_arn' ./firehose-deployment-config.json)
    export DLQ_URL=$(jq -r '.dlq_url' ./firehose-deployment-config.json)
    
    log "Configuration loaded successfully"
    info "S3 Bucket: ${S3_BUCKET_NAME}"
    info "Firehose Stream: ${FIREHOSE_STREAM_NAME}"
    info "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    info "OpenSearch Domain: ${OPENSEARCH_DOMAIN}"
    info "IAM Role: ${IAM_ROLE_NAME}"
}

# Confirm destruction
confirm_destruction() {
    echo ""
    echo "=== DESTRUCTION CONFIRMATION ==="
    echo "You are about to destroy the following resources:"
    echo "- S3 Bucket: ${S3_BUCKET_NAME} (and all contents)"
    echo "- Firehose Stream (S3): ${FIREHOSE_STREAM_NAME}"
    echo "- Firehose Stream (OpenSearch): ${FIREHOSE_STREAM_NAME}-opensearch"
    echo "- Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "- OpenSearch Domain: ${OPENSEARCH_DOMAIN}"
    echo "- IAM Role: ${IAM_ROLE_NAME}"
    echo "- CloudWatch Alarms"
    echo "- SQS Dead Letter Queue"
    echo ""
    warn "This action cannot be undone!"
    echo ""
    
    # Check for --force flag
    if [ "${1:-}" = "--force" ]; then
        warn "Force flag detected, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed, proceeding..."
}

# Stop Firehose delivery streams
stop_firehose_streams() {
    log "Stopping Firehose delivery streams..."
    
    # Get list of active delivery streams
    local s3_stream_status=""
    local opensearch_stream_status=""
    
    # Check S3 stream status
    if aws firehose describe-delivery-stream --delivery-stream-name "${FIREHOSE_STREAM_NAME}" &>/dev/null; then
        s3_stream_status=$(aws firehose describe-delivery-stream \
            --delivery-stream-name "${FIREHOSE_STREAM_NAME}" \
            --query 'DeliveryStreamDescription.DeliveryStreamStatus' \
            --output text)
        info "S3 stream status: ${s3_stream_status}"
    else
        warn "S3 delivery stream ${FIREHOSE_STREAM_NAME} not found"
    fi
    
    # Check OpenSearch stream status
    if aws firehose describe-delivery-stream --delivery-stream-name "${FIREHOSE_STREAM_NAME}-opensearch" &>/dev/null; then
        opensearch_stream_status=$(aws firehose describe-delivery-stream \
            --delivery-stream-name "${FIREHOSE_STREAM_NAME}-opensearch" \
            --query 'DeliveryStreamDescription.DeliveryStreamStatus' \
            --output text)
        info "OpenSearch stream status: ${opensearch_stream_status}"
    else
        warn "OpenSearch delivery stream ${FIREHOSE_STREAM_NAME}-opensearch not found"
    fi
    
    log "Firehose streams status checked"
}

# Delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    # List of alarm names to delete
    local alarm_names=(
        "${FIREHOSE_STREAM_NAME}-DeliveryErrors"
        "${LAMBDA_FUNCTION_NAME}-Errors"
        "${FIREHOSE_STREAM_NAME}-OpenSearchErrors"
    )
    
    # Delete each alarm
    for alarm_name in "${alarm_names[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "${alarm_name}" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "${alarm_name}"; then
            aws cloudwatch delete-alarms --alarm-names "${alarm_name}"
            log "Deleted alarm: ${alarm_name}"
        else
            warn "Alarm not found: ${alarm_name}"
        fi
    done
    
    log "CloudWatch alarms deletion completed"
}

# Delete SQS dead letter queue
delete_sqs_queue() {
    log "Deleting SQS dead letter queue..."
    
    # Extract queue name from URL
    local queue_name="${FIREHOSE_STREAM_NAME}-dlq"
    
    # Check if queue exists
    if aws sqs get-queue-url --queue-name "${queue_name}" &>/dev/null; then
        # Get queue URL
        local queue_url=$(aws sqs get-queue-url \
            --queue-name "${queue_name}" \
            --query QueueUrl --output text)
        
        # Delete queue
        aws sqs delete-queue --queue-url "${queue_url}"
        log "Deleted SQS queue: ${queue_name}"
    else
        warn "SQS queue not found: ${queue_name}"
    fi
    
    log "SQS queue deletion completed"
}

# Delete Firehose delivery streams
delete_firehose_streams() {
    log "Deleting Firehose delivery streams..."
    
    # Delete S3 delivery stream
    if aws firehose describe-delivery-stream --delivery-stream-name "${FIREHOSE_STREAM_NAME}" &>/dev/null; then
        aws firehose delete-delivery-stream --delivery-stream-name "${FIREHOSE_STREAM_NAME}"
        log "Deleted S3 delivery stream: ${FIREHOSE_STREAM_NAME}"
        
        # Wait for deletion to complete
        log "Waiting for S3 delivery stream deletion..."
        while aws firehose describe-delivery-stream --delivery-stream-name "${FIREHOSE_STREAM_NAME}" &>/dev/null; do
            sleep 10
            info "Still waiting for S3 stream deletion..."
        done
        log "S3 delivery stream deletion completed"
    else
        warn "S3 delivery stream not found: ${FIREHOSE_STREAM_NAME}"
    fi
    
    # Delete OpenSearch delivery stream
    if aws firehose describe-delivery-stream --delivery-stream-name "${FIREHOSE_STREAM_NAME}-opensearch" &>/dev/null; then
        aws firehose delete-delivery-stream --delivery-stream-name "${FIREHOSE_STREAM_NAME}-opensearch"
        log "Deleted OpenSearch delivery stream: ${FIREHOSE_STREAM_NAME}-opensearch"
        
        # Wait for deletion to complete
        log "Waiting for OpenSearch delivery stream deletion..."
        while aws firehose describe-delivery-stream --delivery-stream-name "${FIREHOSE_STREAM_NAME}-opensearch" &>/dev/null; do
            sleep 10
            info "Still waiting for OpenSearch stream deletion..."
        done
        log "OpenSearch delivery stream deletion completed"
    else
        warn "OpenSearch delivery stream not found: ${FIREHOSE_STREAM_NAME}-opensearch"
    fi
    
    log "Firehose streams deletion completed"
}

# Delete OpenSearch domain
delete_opensearch_domain() {
    log "Deleting OpenSearch domain..."
    
    # Check if domain exists
    if aws opensearch describe-domain --domain-name "${OPENSEARCH_DOMAIN}" &>/dev/null; then
        aws opensearch delete-domain --domain-name "${OPENSEARCH_DOMAIN}"
        log "Initiated deletion of OpenSearch domain: ${OPENSEARCH_DOMAIN}"
        
        # Wait for deletion to complete (this can take 10-15 minutes)
        log "Waiting for OpenSearch domain deletion (this may take 10-15 minutes)..."
        local wait_count=0
        while aws opensearch describe-domain --domain-name "${OPENSEARCH_DOMAIN}" &>/dev/null; do
            sleep 30
            wait_count=$((wait_count + 1))
            if [ $wait_count -eq 10 ]; then
                info "Still waiting for OpenSearch domain deletion... (${wait_count}0 seconds elapsed)"
                wait_count=0
            fi
        done
        log "OpenSearch domain deletion completed"
    else
        warn "OpenSearch domain not found: ${OPENSEARCH_DOMAIN}"
    fi
    
    log "OpenSearch domain deletion completed"
}

# Delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    # Delete main Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
        aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}"
        log "Deleted Lambda function: ${LAMBDA_FUNCTION_NAME}"
    else
        warn "Lambda function not found: ${LAMBDA_FUNCTION_NAME}"
    fi
    
    # Delete error handler Lambda function (if exists)
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}-error-handler" &>/dev/null; then
        aws lambda delete-function --function-name "${LAMBDA_FUNCTION_NAME}-error-handler"
        log "Deleted error handler Lambda function: ${LAMBDA_FUNCTION_NAME}-error-handler"
    else
        info "Error handler Lambda function not found: ${LAMBDA_FUNCTION_NAME}-error-handler"
    fi
    
    # Delete Lambda execution role (extract suffix from main role name)
    local role_suffix=""
    if [[ ${IAM_ROLE_NAME} =~ -([a-z0-9]+)$ ]]; then
        role_suffix="${BASH_REMATCH[1]}"
        local lambda_role_name="lambda-execution-role-${role_suffix}"
        
        if aws iam get-role --role-name "${lambda_role_name}" &>/dev/null; then
            # Detach managed policy
            aws iam detach-role-policy \
                --role-name "${lambda_role_name}" \
                --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" 2>/dev/null || true
            
            # Delete role
            aws iam delete-role --role-name "${lambda_role_name}"
            log "Deleted Lambda execution role: ${lambda_role_name}"
        else
            warn "Lambda execution role not found: ${lambda_role_name}"
        fi
    else
        warn "Could not extract suffix from IAM role name: ${IAM_ROLE_NAME}"
    fi
    
    log "Lambda functions deletion completed"
}

# Delete S3 bucket and all contents
delete_s3_bucket() {
    log "Deleting S3 bucket and all contents..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
        # Delete all objects and versions
        log "Deleting all objects in bucket: ${S3_BUCKET_NAME}"
        aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive
        
        # Delete all object versions if versioning is enabled
        local versions=$(aws s3api list-object-versions \
            --bucket "${S3_BUCKET_NAME}" \
            --output json 2>/dev/null | jq '.Versions[]?' 2>/dev/null)
        
        if [ -n "$versions" ]; then
            log "Deleting object versions..."
            aws s3api list-object-versions \
                --bucket "${S3_BUCKET_NAME}" \
                --output json | \
                jq -r '.Versions[]? | "\(.Key) \(.VersionId)"' | \
                while read -r key version_id; do
                    aws s3api delete-object \
                        --bucket "${S3_BUCKET_NAME}" \
                        --key "$key" \
                        --version-id "$version_id" &>/dev/null
                done
        fi
        
        # Delete all delete markers
        local delete_markers=$(aws s3api list-object-versions \
            --bucket "${S3_BUCKET_NAME}" \
            --output json 2>/dev/null | jq '.DeleteMarkers[]?' 2>/dev/null)
        
        if [ -n "$delete_markers" ]; then
            log "Deleting delete markers..."
            aws s3api list-object-versions \
                --bucket "${S3_BUCKET_NAME}" \
                --output json | \
                jq -r '.DeleteMarkers[]? | "\(.Key) \(.VersionId)"' | \
                while read -r key version_id; do
                    aws s3api delete-object \
                        --bucket "${S3_BUCKET_NAME}" \
                        --key "$key" \
                        --version-id "$version_id" &>/dev/null
                done
        fi
        
        # Delete bucket
        aws s3 rb "s3://${S3_BUCKET_NAME}"
        log "Deleted S3 bucket: ${S3_BUCKET_NAME}"
    else
        warn "S3 bucket not found: ${S3_BUCKET_NAME}"
    fi
    
    log "S3 bucket deletion completed"
}

# Delete IAM roles and policies
delete_iam_roles() {
    log "Deleting IAM roles and policies..."
    
    # Delete Firehose delivery role
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        # Delete inline policy
        aws iam delete-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-name "FirehoseDeliveryPolicy" 2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "${IAM_ROLE_NAME}"
        log "Deleted IAM role: ${IAM_ROLE_NAME}"
    else
        warn "IAM role not found: ${IAM_ROLE_NAME}"
    fi
    
    log "IAM roles deletion completed"
}

# Delete CloudWatch log groups
delete_cloudwatch_logs() {
    log "Deleting CloudWatch log groups..."
    
    # List of log group patterns to delete
    local log_groups=(
        "/aws/kinesisfirehose/${FIREHOSE_STREAM_NAME}"
        "/aws/kinesisfirehose/${FIREHOSE_STREAM_NAME}-opensearch"
        "/aws/lambda/${LAMBDA_FUNCTION_NAME}"
        "/aws/lambda/${LAMBDA_FUNCTION_NAME}-error-handler"
    )
    
    # Delete each log group
    for log_group in "${log_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "${log_group}" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${log_group}"; then
            aws logs delete-log-group --log-group-name "${log_group}"
            log "Deleted log group: ${log_group}"
        else
            warn "Log group not found: ${log_group}"
        fi
    done
    
    log "CloudWatch log groups deletion completed"
}

# Cleanup configuration file
cleanup_config_file() {
    log "Cleaning up configuration file..."
    
    if [ -f "./firehose-deployment-config.json" ]; then
        rm -f "./firehose-deployment-config.json"
        log "Deleted configuration file: firehose-deployment-config.json"
    fi
    
    log "Configuration cleanup completed"
}

# Verify destruction
verify_destruction() {
    log "Verifying resource destruction..."
    
    local errors=0
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
        error "S3 bucket still exists: ${S3_BUCKET_NAME}"
        errors=$((errors + 1))
    fi
    
    # Check Firehose streams
    if aws firehose describe-delivery-stream --delivery-stream-name "${FIREHOSE_STREAM_NAME}" &>/dev/null; then
        error "Firehose stream still exists: ${FIREHOSE_STREAM_NAME}"
        errors=$((errors + 1))
    fi
    
    if aws firehose describe-delivery-stream --delivery-stream-name "${FIREHOSE_STREAM_NAME}-opensearch" &>/dev/null; then
        error "OpenSearch stream still exists: ${FIREHOSE_STREAM_NAME}-opensearch"
        errors=$((errors + 1))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
        error "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
        errors=$((errors + 1))
    fi
    
    # Check OpenSearch domain
    if aws opensearch describe-domain --domain-name "${OPENSEARCH_DOMAIN}" &>/dev/null; then
        error "OpenSearch domain still exists: ${OPENSEARCH_DOMAIN}"
        errors=$((errors + 1))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
        error "IAM role still exists: ${IAM_ROLE_NAME}"
        errors=$((errors + 1))
    fi
    
    if [ $errors -eq 0 ]; then
        log "All resources successfully destroyed"
        return 0
    else
        error "Some resources may still exist. Please check manually."
        return 1
    fi
}

# Main destruction function
main() {
    log "Starting destruction of Real-Time Data Processing with Kinesis Data Firehose"
    
    # Run destruction steps
    check_prerequisites
    load_deployment_config
    confirm_destruction "$@"
    
    # Start destruction process
    log "Beginning resource destruction..."
    
    # Stop data flow first
    stop_firehose_streams
    
    # Delete monitoring and alerting
    delete_cloudwatch_alarms
    delete_sqs_queue
    
    # Delete data processing infrastructure
    delete_firehose_streams
    delete_lambda_functions
    
    # Delete storage and search infrastructure
    delete_opensearch_domain
    delete_s3_bucket
    
    # Delete IAM and logging
    delete_iam_roles
    delete_cloudwatch_logs
    
    # Cleanup configuration
    cleanup_config_file
    
    # Verify everything is gone
    if verify_destruction; then
        log "Destruction completed successfully!"
        echo ""
        echo "=== DESTRUCTION SUMMARY ==="
        echo "All resources have been successfully destroyed:"
        echo "✅ S3 Bucket: ${S3_BUCKET_NAME}"
        echo "✅ Firehose Streams: ${FIREHOSE_STREAM_NAME} and ${FIREHOSE_STREAM_NAME}-opensearch"
        echo "✅ Lambda Function: ${LAMBDA_FUNCTION_NAME}"
        echo "✅ OpenSearch Domain: ${OPENSEARCH_DOMAIN}"
        echo "✅ IAM Role: ${IAM_ROLE_NAME}"
        echo "✅ CloudWatch Alarms and Log Groups"
        echo "✅ SQS Dead Letter Queue"
        echo "✅ Configuration File"
        echo ""
        log "All billable resources have been removed"
    else
        error "Some resources may still exist. Please check the AWS console manually."
        exit 1
    fi
}

# Run main function
main "$@"