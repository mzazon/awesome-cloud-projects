#!/bin/bash

# CloudFront Cache Invalidation Strategies - Cleanup Script
# This script removes all infrastructure created by the deployment script

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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    if [[ ! -f ".deployment_state" ]]; then
        error "Deployment state file not found. Cannot proceed with cleanup."
        error "Please ensure you run this script from the same directory where deploy.sh was executed."
        exit 1
    fi
    
    # Load variables from deployment state
    source .deployment_state
    
    # Set AWS region if not already set
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
            warn "No region configured, using default: us-east-1"
        fi
    fi
    
    log "Deployment state loaded successfully"
    info "Project Name: ${PROJECT_NAME}"
    info "AWS Region: ${AWS_REGION}"
}

# Function to confirm cleanup
confirm_cleanup() {
    echo ""
    echo "=== CLEANUP CONFIRMATION ==="
    echo "This will permanently delete the following resources:"
    echo "- CloudFront Distribution: ${DISTRIBUTION_ID:-Unknown}"
    echo "- S3 Bucket: ${S3_BUCKET_NAME:-Unknown}"
    echo "- Lambda Function: ${LAMBDA_FUNCTION_NAME:-Unknown}"
    echo "- DynamoDB Table: ${DDB_TABLE_NAME:-Unknown}"
    echo "- EventBridge Bus: ${EVENTBRIDGE_BUS_NAME:-Unknown}"
    echo "- SQS Queues: ${PROJECT_NAME:-Unknown}-batch-queue and ${PROJECT_NAME:-Unknown}-dlq"
    echo "- IAM Role: ${LAMBDA_FUNCTION_NAME:-Unknown}-role"
    echo "- CloudWatch Dashboard: ${DASHBOARD_NAME:-Unknown}"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/NO): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    echo ""
    warn "Starting cleanup in 10 seconds... Press Ctrl+C to cancel."
    sleep 10
}

# Function to disable and delete CloudFront distribution
cleanup_cloudfront_distribution() {
    log "Cleaning up CloudFront distribution..."
    
    if [[ -z "${DISTRIBUTION_ID:-}" ]]; then
        warn "Distribution ID not found in deployment state. Skipping CloudFront cleanup."
        return
    fi
    
    # Check if distribution exists
    if ! aws cloudfront get-distribution --id "$DISTRIBUTION_ID" &> /dev/null; then
        warn "CloudFront distribution ${DISTRIBUTION_ID} not found. May have been deleted already."
        return
    fi
    
    # Get current distribution config
    log "Getting current distribution configuration..."
    local dist_config_output=$(aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID")
    local etag=$(echo "$dist_config_output" | jq -r '.ETag')
    
    # Check if distribution is already disabled
    local is_enabled=$(echo "$dist_config_output" | jq -r '.DistributionConfig.Enabled')
    
    if [[ "$is_enabled" == "true" ]]; then
        log "Disabling CloudFront distribution..."
        
        # Disable distribution
        echo "$dist_config_output" | jq '.DistributionConfig.Enabled = false' | \
            jq '.DistributionConfig' > /tmp/disable-dist.json
        
        aws cloudfront update-distribution \
            --id "$DISTRIBUTION_ID" \
            --distribution-config file:///tmp/disable-dist.json \
            --if-match "$etag"
        
        # Wait for distribution to be disabled
        log "Waiting for distribution to be disabled (this may take 15-20 minutes)..."
        aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID"
        
        # Get new ETag after update
        etag=$(aws cloudfront get-distribution \
            --id "$DISTRIBUTION_ID" \
            --query 'ETag' --output text)
    else
        log "Distribution is already disabled"
    fi
    
    # Delete distribution
    log "Deleting CloudFront distribution..."
    aws cloudfront delete-distribution \
        --id "$DISTRIBUTION_ID" \
        --if-match "$etag"
    
    # Clean up temp files
    rm -f /tmp/disable-dist.json
    
    log "CloudFront distribution cleanup completed"
}

# Function to delete Lambda function and related resources
cleanup_lambda_function() {
    log "Cleaning up Lambda function..."
    
    if [[ -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        warn "Lambda function name not found in deployment state. Skipping Lambda cleanup."
        return
    fi
    
    # Check if function exists
    if ! aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        warn "Lambda function ${LAMBDA_FUNCTION_NAME} not found. May have been deleted already."
    else
        # Delete event source mappings
        log "Deleting Lambda event source mappings..."
        local event_source_mappings=$(aws lambda list-event-source-mappings \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --query 'EventSourceMappings[].UUID' --output text)
        
        if [[ -n "$event_source_mappings" ]]; then
            for uuid in $event_source_mappings; do
                aws lambda delete-event-source-mapping --uuid "$uuid"
                log "Deleted event source mapping: $uuid"
            done
        fi
        
        # Delete Lambda function
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
        log "Lambda function deleted: ${LAMBDA_FUNCTION_NAME}"
    fi
    
    # Delete IAM role and policies
    log "Cleaning up IAM role..."
    local role_name="${LAMBDA_FUNCTION_NAME}-role"
    
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "$role_name" \
            --policy-name CloudFrontInvalidationPolicy 2>/dev/null || true
        
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "$role_name"
        log "IAM role deleted: ${role_name}"
    else
        warn "IAM role ${role_name} not found. May have been deleted already."
    fi
    
    log "Lambda function cleanup completed"
}

# Function to delete EventBridge resources
cleanup_eventbridge_resources() {
    log "Cleaning up EventBridge resources..."
    
    if [[ -z "${EVENTBRIDGE_BUS_NAME:-}" || -z "${PROJECT_NAME:-}" ]]; then
        warn "EventBridge configuration not found in deployment state. Skipping EventBridge cleanup."
        return
    fi
    
    # Check if event bus exists
    if ! aws events describe-event-bus --name "$EVENTBRIDGE_BUS_NAME" &> /dev/null; then
        warn "EventBridge bus ${EVENTBRIDGE_BUS_NAME} not found. May have been deleted already."
        return
    fi
    
    # Remove targets from rules
    log "Removing targets from EventBridge rules..."
    aws events remove-targets \
        --rule "${PROJECT_NAME}-s3-rule" \
        --event-bus-name "$EVENTBRIDGE_BUS_NAME" \
        --ids "1" 2>/dev/null || true
    
    aws events remove-targets \
        --rule "${PROJECT_NAME}-deploy-rule" \
        --event-bus-name "$EVENTBRIDGE_BUS_NAME" \
        --ids "1" 2>/dev/null || true
    
    # Delete rules
    log "Deleting EventBridge rules..."
    aws events delete-rule \
        --name "${PROJECT_NAME}-s3-rule" \
        --event-bus-name "$EVENTBRIDGE_BUS_NAME" 2>/dev/null || true
    
    aws events delete-rule \
        --name "${PROJECT_NAME}-deploy-rule" \
        --event-bus-name "$EVENTBRIDGE_BUS_NAME" 2>/dev/null || true
    
    # Delete custom event bus
    log "Deleting EventBridge custom bus..."
    aws events delete-event-bus --name "$EVENTBRIDGE_BUS_NAME"
    
    log "EventBridge resources cleanup completed"
}

# Function to delete SQS queues
cleanup_sqs_queues() {
    log "Cleaning up SQS queues..."
    
    if [[ -z "${PROJECT_NAME:-}" ]]; then
        warn "Project name not found in deployment state. Skipping SQS cleanup."
        return
    fi
    
    # Delete main queue
    local main_queue_url
    main_queue_url=$(aws sqs get-queue-url \
        --queue-name "${PROJECT_NAME}-batch-queue" \
        --query 'QueueUrl' --output text 2>/dev/null || echo "")
    
    if [[ -n "$main_queue_url" ]]; then
        aws sqs delete-queue --queue-url "$main_queue_url"
        log "Deleted SQS queue: ${PROJECT_NAME}-batch-queue"
    else
        warn "SQS queue ${PROJECT_NAME}-batch-queue not found. May have been deleted already."
    fi
    
    # Delete dead letter queue
    local dlq_url
    dlq_url=$(aws sqs get-queue-url \
        --queue-name "${PROJECT_NAME}-dlq" \
        --query 'QueueUrl' --output text 2>/dev/null || echo "")
    
    if [[ -n "$dlq_url" ]]; then
        aws sqs delete-queue --queue-url "$dlq_url"
        log "Deleted SQS dead letter queue: ${PROJECT_NAME}-dlq"
    else
        warn "SQS dead letter queue ${PROJECT_NAME}-dlq not found. May have been deleted already."
    fi
    
    log "SQS queues cleanup completed"
}

# Function to delete DynamoDB table
cleanup_dynamodb_table() {
    log "Cleaning up DynamoDB table..."
    
    if [[ -z "${DDB_TABLE_NAME:-}" ]]; then
        warn "DynamoDB table name not found in deployment state. Skipping DynamoDB cleanup."
        return
    fi
    
    # Check if table exists
    if ! aws dynamodb describe-table --table-name "$DDB_TABLE_NAME" &> /dev/null; then
        warn "DynamoDB table ${DDB_TABLE_NAME} not found. May have been deleted already."
        return
    fi
    
    # Delete DynamoDB table
    aws dynamodb delete-table --table-name "$DDB_TABLE_NAME"
    log "DynamoDB table deletion initiated: ${DDB_TABLE_NAME}"
    
    # Wait for table to be deleted
    log "Waiting for DynamoDB table to be deleted..."
    aws dynamodb wait table-not-exists --table-name "$DDB_TABLE_NAME"
    
    log "DynamoDB table cleanup completed"
}

# Function to delete S3 resources
cleanup_s3_resources() {
    log "Cleaning up S3 resources..."
    
    if [[ -z "${S3_BUCKET_NAME:-}" ]]; then
        warn "S3 bucket name not found in deployment state. Skipping S3 cleanup."
        return
    fi
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
        warn "S3 bucket ${S3_BUCKET_NAME} not found. May have been deleted already."
        return
    fi
    
    # Remove bucket policy
    log "Removing S3 bucket policy..."
    aws s3api delete-bucket-policy --bucket "$S3_BUCKET_NAME" 2>/dev/null || true
    
    # Remove bucket notifications
    log "Removing S3 bucket notifications..."
    aws s3api put-bucket-notification-configuration \
        --bucket "$S3_BUCKET_NAME" \
        --notification-configuration '{}' 2>/dev/null || true
    
    # Delete all objects in bucket
    log "Deleting S3 bucket contents..."
    aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive
    
    # Delete bucket
    log "Deleting S3 bucket..."
    aws s3 rb "s3://${S3_BUCKET_NAME}"
    
    log "S3 resources cleanup completed"
}

# Function to delete CloudWatch resources
cleanup_cloudwatch_resources() {
    log "Cleaning up CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    if [[ -n "${DASHBOARD_NAME:-}" ]]; then
        if aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" &> /dev/null; then
            aws cloudwatch delete-dashboards --dashboard-names "$DASHBOARD_NAME"
            log "CloudWatch dashboard deleted: ${DASHBOARD_NAME}"
        else
            warn "CloudWatch dashboard ${DASHBOARD_NAME} not found. May have been deleted already."
        fi
    fi
    
    # Delete CloudWatch log groups
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        local log_group_name="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
        if aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --query 'logGroups[0]' --output text &> /dev/null; then
            aws logs delete-log-group --log-group-name "$log_group_name"
            log "CloudWatch log group deleted: ${log_group_name}"
        else
            warn "CloudWatch log group ${log_group_name} not found. May have been deleted already."
        fi
    fi
    
    log "CloudWatch resources cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment state file
    if [[ -f ".deployment_state" ]]; then
        rm -f .deployment_state
        log "Deployment state file removed"
    fi
    
    # Remove temporary files
    rm -f /tmp/*.json 2>/dev/null || true
    rm -f /tmp/*.json.bak 2>/dev/null || true
    rm -rf /tmp/lambda-invalidation 2>/dev/null || true
    rm -rf /tmp/cf-invalidation-content 2>/dev/null || true
    
    log "Local files cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_issues=0
    
    # Check CloudFront distribution
    if [[ -n "${DISTRIBUTION_ID:-}" ]]; then
        if aws cloudfront get-distribution --id "$DISTRIBUTION_ID" &> /dev/null; then
            warn "CloudFront distribution ${DISTRIBUTION_ID} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check Lambda function
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
            warn "Lambda function ${LAMBDA_FUNCTION_NAME} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check S3 bucket
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" &> /dev/null; then
            warn "S3 bucket ${S3_BUCKET_NAME} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check DynamoDB table
    if [[ -n "${DDB_TABLE_NAME:-}" ]]; then
        if aws dynamodb describe-table --table-name "$DDB_TABLE_NAME" &> /dev/null; then
            warn "DynamoDB table ${DDB_TABLE_NAME} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check EventBridge bus
    if [[ -n "${EVENTBRIDGE_BUS_NAME:-}" ]]; then
        if aws events describe-event-bus --name "$EVENTBRIDGE_BUS_NAME" &> /dev/null; then
            warn "EventBridge bus ${EVENTBRIDGE_BUS_NAME} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log "Cleanup verification completed successfully - all resources removed"
    else
        warn "Cleanup verification found ${cleanup_issues} issues. Some resources may still exist."
        warn "You may need to manually remove remaining resources to avoid charges."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup completed!"
    
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    echo "The following resources have been removed:"
    echo "✓ CloudFront Distribution: ${DISTRIBUTION_ID:-Unknown}"
    echo "✓ S3 Bucket: ${S3_BUCKET_NAME:-Unknown}"
    echo "✓ Lambda Function: ${LAMBDA_FUNCTION_NAME:-Unknown}"
    echo "✓ DynamoDB Table: ${DDB_TABLE_NAME:-Unknown}"
    echo "✓ EventBridge Bus: ${EVENTBRIDGE_BUS_NAME:-Unknown}"
    echo "✓ SQS Queues: ${PROJECT_NAME:-Unknown}-batch-queue and ${PROJECT_NAME:-Unknown}-dlq"
    echo "✓ IAM Role: ${LAMBDA_FUNCTION_NAME:-Unknown}-role"
    echo "✓ CloudWatch Dashboard: ${DASHBOARD_NAME:-Unknown}"
    echo "✓ CloudWatch Log Groups"
    echo "✓ Local deployment files"
    echo ""
    echo "All infrastructure has been successfully removed."
    echo "You should no longer incur charges for these resources."
    echo ""
    echo "Note: CloudFront distributions may take up to 24 hours to fully propagate"
    echo "the deletion across all edge locations, but billing stops immediately."
}

# Function to handle cleanup errors
handle_cleanup_errors() {
    local exit_code=$?
    error "Cleanup encountered errors (exit code: $exit_code)"
    
    echo ""
    echo "=== PARTIAL CLEANUP DETECTED ==="
    echo "Some resources may not have been fully removed."
    echo "Please check the AWS console for any remaining resources:"
    echo ""
    echo "1. CloudFront: https://console.aws.amazon.com/cloudfront/home"
    echo "2. Lambda: https://console.aws.amazon.com/lambda/home"
    echo "3. S3: https://console.aws.amazon.com/s3/home"
    echo "4. DynamoDB: https://console.aws.amazon.com/dynamodb/home"
    echo "5. EventBridge: https://console.aws.amazon.com/events/home"
    echo "6. SQS: https://console.aws.amazon.com/sqs/home"
    echo "7. IAM: https://console.aws.amazon.com/iam/home"
    echo "8. CloudWatch: https://console.aws.amazon.com/cloudwatch/home"
    echo ""
    echo "Manual cleanup may be required to avoid ongoing charges."
    
    exit $exit_code
}

# Main execution
main() {
    log "Starting CloudFront Cache Invalidation infrastructure cleanup..."
    
    # Set up error handling
    trap handle_cleanup_errors ERR
    
    check_prerequisites
    load_deployment_state
    confirm_cleanup
    
    # Execute cleanup in reverse order of creation
    cleanup_cloudwatch_resources
    cleanup_s3_resources
    cleanup_dynamodb_table
    cleanup_sqs_queues
    cleanup_eventbridge_resources
    cleanup_lambda_function
    cleanup_cloudfront_distribution
    cleanup_local_files
    
    verify_cleanup
    display_cleanup_summary
    
    log "Cleanup script completed successfully!"
}

# Run main function
main "$@"