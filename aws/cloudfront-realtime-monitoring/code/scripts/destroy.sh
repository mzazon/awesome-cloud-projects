#!/bin/bash

# CloudFront Real-time Monitoring and Analytics - Cleanup Script
# This script removes all AWS resources created by the deployment script

set -e  # Exit on any error

# Colors for output
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

# Error handling
handle_error() {
    log_error "Cleanup failed at line $1"
    log_error "Some resources may still exist. Please check the AWS console."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [[ ! -f .env ]]; then
        log_error ".env file not found. Make sure you run this script from the same directory as deploy.sh"
        log_error "Or ensure the deployment script was run successfully first."
        exit 1
    fi
    
    # Source environment variables
    source .env
    
    # Verify required variables exist
    local required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "PROJECT_NAME" 
        "S3_BUCKET_NAME" "S3_CONTENT_BUCKET" "KINESIS_STREAM_NAME" 
        "OPENSEARCH_DOMAIN" "METRICS_TABLE_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    log_success "Environment variables loaded"
    log_info "Project Name: ${PROJECT_NAME}"
    log_info "AWS Region: ${AWS_REGION}"
}

# Check AWS CLI and credentials
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for cleanup operations"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Confirm deletion
confirm_deletion() {
    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    log_warning "This script will permanently delete the following resources:"
    echo "  - CloudFront Distribution: ${CF_DISTRIBUTION_ID:-unknown}"
    echo "  - OpenSearch Domain: ${OPENSEARCH_DOMAIN}"
    echo "  - DynamoDB Table: ${METRICS_TABLE_NAME}"
    echo "  - Lambda Function: ${PROJECT_NAME}-log-processor"
    echo "  - Kinesis Streams: ${KINESIS_STREAM_NAME} and ${KINESIS_STREAM_NAME}-processed"
    echo "  - S3 Buckets: ${S3_BUCKET_NAME} and ${S3_CONTENT_BUCKET}"
    echo "  - IAM Roles and Policies"
    echo "  - CloudWatch Dashboard: ${DASHBOARD_NAME:-CloudFront-RealTime-Analytics-${RANDOM_SUFFIX}}"
    echo "  - All associated logs and data"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " confirm
    if [[ "$confirm" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Delete CloudFront Distribution and Real-time Logs
delete_cloudfront_resources() {
    log_info "Deleting CloudFront distribution and real-time logs..."
    
    # Delete real-time log configuration first
    if aws cloudfront get-realtime-log-config --name "${PROJECT_NAME}-realtime-logs" &>/dev/null; then
        aws cloudfront delete-realtime-log-config \
            --name "${PROJECT_NAME}-realtime-logs" &>/dev/null || log_warning "Failed to delete real-time log config"
        log_success "Real-time log configuration deleted"
    else
        log_warning "Real-time log configuration not found"
    fi
    
    # Get CloudFront distribution if not in env
    if [[ -z "$CF_DISTRIBUTION_ID" ]]; then
        log_warning "CloudFront distribution ID not found in environment"
        return
    fi
    
    # Check if distribution exists
    if ! aws cloudfront get-distribution --id ${CF_DISTRIBUTION_ID} &>/dev/null; then
        log_warning "CloudFront distribution ${CF_DISTRIBUTION_ID} not found"
        return
    fi
    
    # Disable distribution first
    log_info "Disabling CloudFront distribution..."
    DIST_CONFIG=$(aws cloudfront get-distribution-config --id ${CF_DISTRIBUTION_ID})
    ETAG=$(echo $DIST_CONFIG | jq -r '.ETag')
    
    echo $DIST_CONFIG | jq '.DistributionConfig.Enabled = false' | \
        jq '.DistributionConfig' > /tmp/disable-dist.json
    
    aws cloudfront update-distribution \
        --id ${CF_DISTRIBUTION_ID} \
        --distribution-config file:///tmp/disable-dist.json \
        --if-match ${ETAG} &>/dev/null || log_warning "Failed to disable distribution"
    
    # Wait for distribution to be deployed
    log_info "Waiting for CloudFront distribution to be disabled..."
    aws cloudfront wait distribution-deployed --id ${CF_DISTRIBUTION_ID} || log_warning "Timeout waiting for distribution"
    
    # Delete distribution
    NEW_ETAG=$(aws cloudfront get-distribution \
        --id ${CF_DISTRIBUTION_ID} \
        --query 'ETag' --output text 2>/dev/null || echo "")
    
    if [[ -n "$NEW_ETAG" ]]; then
        aws cloudfront delete-distribution \
            --id ${CF_DISTRIBUTION_ID} \
            --if-match ${NEW_ETAG} &>/dev/null || log_warning "Failed to delete distribution"
        log_success "CloudFront distribution deletion initiated"
    fi
}

# Delete Lambda function and event source mappings
delete_lambda_resources() {
    log_info "Deleting Lambda function and related resources..."
    
    # Delete event source mappings
    local mappings=$(aws lambda list-event-source-mappings \
        --function-name ${PROJECT_NAME}-log-processor \
        --query 'EventSourceMappings[].UUID' --output text 2>/dev/null || echo "")
    
    if [[ -n "$mappings" ]]; then
        for uuid in $mappings; do
            aws lambda delete-event-source-mapping --uuid $uuid &>/dev/null || log_warning "Failed to delete mapping $uuid"
            log_success "Event source mapping $uuid deleted"
        done
    fi
    
    # Delete Lambda function
    if aws lambda get-function --function-name ${PROJECT_NAME}-log-processor &>/dev/null; then
        aws lambda delete-function --function-name ${PROJECT_NAME}-log-processor &>/dev/null || log_warning "Failed to delete Lambda function"
        log_success "Lambda function deleted"
    else
        log_warning "Lambda function not found"
    fi
}

# Delete IAM roles and policies
delete_iam_resources() {
    log_info "Deleting IAM roles and policies..."
    
    # Delete Lambda IAM role
    if aws iam get-role --role-name ${PROJECT_NAME}-lambda-role &>/dev/null; then
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name ${PROJECT_NAME}-lambda-role \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole &>/dev/null || true
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name ${PROJECT_NAME}-lambda-role \
            --policy-name CloudFrontLogProcessingPolicy &>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name ${PROJECT_NAME}-lambda-role &>/dev/null || log_warning "Failed to delete Lambda IAM role"
        log_success "Lambda IAM role deleted"
    fi
    
    # Delete Firehose IAM role
    if aws iam get-role --role-name ${PROJECT_NAME}-firehose-role &>/dev/null; then
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name ${PROJECT_NAME}-firehose-role \
            --policy-name FirehoseDeliveryPolicy &>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name ${PROJECT_NAME}-firehose-role &>/dev/null || log_warning "Failed to delete Firehose IAM role"
        log_success "Firehose IAM role deleted"
    fi
    
    # Delete real-time logs IAM role
    if aws iam get-role --role-name ${PROJECT_NAME}-realtime-logs-role &>/dev/null; then
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name ${PROJECT_NAME}-realtime-logs-role \
            --policy-name KinesisAccess &>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name ${PROJECT_NAME}-realtime-logs-role &>/dev/null || log_warning "Failed to delete real-time logs IAM role"
        log_success "Real-time logs IAM role deleted"
    fi
}

# Delete Kinesis resources
delete_kinesis_resources() {
    log_info "Deleting Kinesis resources..."
    
    # Delete Kinesis Data Firehose delivery stream
    if aws firehose describe-delivery-stream --delivery-stream-name ${PROJECT_NAME}-logs-to-s3-opensearch &>/dev/null; then
        aws firehose delete-delivery-stream \
            --delivery-stream-name ${PROJECT_NAME}-logs-to-s3-opensearch &>/dev/null || log_warning "Failed to delete Firehose delivery stream"
        log_success "Firehose delivery stream deleted"
    fi
    
    # Delete Kinesis Data Streams
    if aws kinesis describe-stream --stream-name ${KINESIS_STREAM_NAME} &>/dev/null; then
        aws kinesis delete-stream --stream-name ${KINESIS_STREAM_NAME} &>/dev/null || log_warning "Failed to delete primary Kinesis stream"
        log_success "Primary Kinesis stream deleted"
    fi
    
    if aws kinesis describe-stream --stream-name ${KINESIS_STREAM_NAME}-processed &>/dev/null; then
        aws kinesis delete-stream --stream-name ${KINESIS_STREAM_NAME}-processed &>/dev/null || log_warning "Failed to delete processed Kinesis stream"
        log_success "Processed Kinesis stream deleted"
    fi
}

# Delete OpenSearch domain
delete_opensearch_domain() {
    log_info "Deleting OpenSearch domain..."
    
    if aws opensearch describe-domain --domain-name ${OPENSEARCH_DOMAIN} &>/dev/null; then
        aws opensearch delete-domain --domain-name ${OPENSEARCH_DOMAIN} &>/dev/null || log_warning "Failed to delete OpenSearch domain"
        log_success "OpenSearch domain deletion initiated (this may take 10-15 minutes)"
    else
        log_warning "OpenSearch domain not found"
    fi
}

# Delete DynamoDB table
delete_dynamodb_table() {
    log_info "Deleting DynamoDB table..."
    
    if aws dynamodb describe-table --table-name ${METRICS_TABLE_NAME} &>/dev/null; then
        aws dynamodb delete-table --table-name ${METRICS_TABLE_NAME} &>/dev/null || log_warning "Failed to delete DynamoDB table"
        log_success "DynamoDB table deleted"
    else
        log_warning "DynamoDB table not found"
    fi
}

# Delete S3 resources
delete_s3_resources() {
    log_info "Deleting S3 resources..."
    
    # Delete logs bucket contents and bucket
    if aws s3 ls s3://${S3_BUCKET_NAME} &>/dev/null; then
        log_info "Emptying S3 logs bucket..."
        aws s3 rm s3://${S3_BUCKET_NAME} --recursive &>/dev/null || log_warning "Failed to empty logs bucket"
        aws s3 rb s3://${S3_BUCKET_NAME} &>/dev/null || log_warning "Failed to delete logs bucket"
        log_success "S3 logs bucket deleted"
    fi
    
    # Delete content bucket policy first, then contents and bucket
    if aws s3 ls s3://${S3_CONTENT_BUCKET} &>/dev/null; then
        aws s3api delete-bucket-policy --bucket ${S3_CONTENT_BUCKET} &>/dev/null || log_warning "Failed to delete bucket policy"
        log_info "Emptying S3 content bucket..."
        aws s3 rm s3://${S3_CONTENT_BUCKET} --recursive &>/dev/null || log_warning "Failed to empty content bucket"
        aws s3 rb s3://${S3_CONTENT_BUCKET} &>/dev/null || log_warning "Failed to delete content bucket"
        log_success "S3 content bucket deleted"
    fi
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log_info "Deleting CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    local dashboard_name="${DASHBOARD_NAME:-CloudFront-RealTime-Analytics-${RANDOM_SUFFIX}}"
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name" &>/dev/null || log_warning "Failed to delete dashboard"
        log_success "CloudWatch dashboard deleted"
    fi
    
    # Delete CloudWatch log groups
    local log_groups=(
        "/aws/lambda/${PROJECT_NAME}-log-processor"
        "/aws/kinesisfirehose/${PROJECT_NAME}"
    )
    
    for log_group in "${log_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
            aws logs delete-log-group --log-group-name "$log_group" &>/dev/null || log_warning "Failed to delete log group $log_group"
            log_success "Log group $log_group deleted"
        fi
    done
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove temporary files
    rm -rf /tmp/content /tmp/lambda-log-processor
    rm -f /tmp/*.json
    
    # Ask user if they want to remove .env file
    read -p "Do you want to remove the .env file? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f .env
        log_success "Environment file removed"
    else
        log_info "Environment file preserved"
    fi
    
    log_success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local resources_remaining=0
    
    # Check CloudFront distribution
    if [[ -n "$CF_DISTRIBUTION_ID" ]] && aws cloudfront get-distribution --id ${CF_DISTRIBUTION_ID} &>/dev/null; then
        log_warning "CloudFront distribution still exists (may take time to delete)"
        resources_remaining=$((resources_remaining + 1))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name ${PROJECT_NAME}-log-processor &>/dev/null; then
        log_warning "Lambda function still exists"
        resources_remaining=$((resources_remaining + 1))
    fi
    
    # Check Kinesis streams
    if aws kinesis describe-stream --stream-name ${KINESIS_STREAM_NAME} &>/dev/null; then
        log_warning "Primary Kinesis stream still exists"
        resources_remaining=$((resources_remaining + 1))
    fi
    
    # Check OpenSearch domain
    if aws opensearch describe-domain --domain-name ${OPENSEARCH_DOMAIN} &>/dev/null; then
        local domain_status=$(aws opensearch describe-domain --domain-name ${OPENSEARCH_DOMAIN} --query 'DomainStatus.Processing' --output text)
        if [[ "$domain_status" == "true" ]]; then
            log_warning "OpenSearch domain is being deleted (this can take 10-15 minutes)"
        else
            log_warning "OpenSearch domain still exists"
            resources_remaining=$((resources_remaining + 1))
        fi
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name ${METRICS_TABLE_NAME} &>/dev/null; then
        log_warning "DynamoDB table still exists"
        resources_remaining=$((resources_remaining + 1))
    fi
    
    # Check S3 buckets
    if aws s3 ls s3://${S3_BUCKET_NAME} &>/dev/null; then
        log_warning "S3 logs bucket still exists"
        resources_remaining=$((resources_remaining + 1))
    fi
    
    if aws s3 ls s3://${S3_CONTENT_BUCKET} &>/dev/null; then
        log_warning "S3 content bucket still exists"
        resources_remaining=$((resources_remaining + 1))
    fi
    
    if [[ $resources_remaining -eq 0 ]]; then
        log_success "All resources successfully cleaned up!"
    else
        log_warning "$resources_remaining resource(s) may still be in the process of deletion"
        log_info "Please check the AWS console to verify complete cleanup"
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    log_success "=== CLEANUP COMPLETED ==="
    echo
    log_info "The following resources have been removed or are being removed:"
    echo "  ✓ CloudFront Distribution and Real-time Logs"
    echo "  ✓ Lambda Function and Event Source Mappings"
    echo "  ✓ IAM Roles and Policies"
    echo "  ✓ Kinesis Data Streams and Firehose"
    echo "  ✓ OpenSearch Domain (deletion in progress)"
    echo "  ✓ DynamoDB Table"
    echo "  ✓ S3 Buckets and Contents"
    echo "  ✓ CloudWatch Dashboard and Log Groups"
    echo
    log_info "Notes:"
    echo "  - OpenSearch domain deletion can take 10-15 minutes"
    echo "  - CloudFront distribution deletion can take several minutes"
    echo "  - Check the AWS console to verify complete resource removal"
    echo
    log_success "Cleanup script completed successfully!"
}

# Main cleanup function
main() {
    log_info "Starting CloudFront Real-time Monitoring cleanup..."
    echo
    
    load_environment
    check_prerequisites
    confirm_deletion
    
    # Perform cleanup in reverse order of creation
    delete_cloudfront_resources
    delete_lambda_resources
    delete_iam_resources
    delete_kinesis_resources
    delete_opensearch_domain
    delete_dynamodb_table
    delete_s3_resources
    delete_cloudwatch_resources
    cleanup_local_files
    
    verify_cleanup
    show_cleanup_summary
}

# Run main function
main "$@"