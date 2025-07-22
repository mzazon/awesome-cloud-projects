#!/bin/bash

# Real-Time Fraud Detection with Amazon Fraud Detector - Cleanup Script
# This script removes all resources created by the deployment script including:
# - Amazon Fraud Detector models, rules, and detectors
# - Lambda functions and event source mappings
# - Kinesis streams
# - DynamoDB tables
# - SNS topics
# - S3 buckets
# - IAM roles and policies
# - CloudWatch dashboards

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI not configured or authentication failed"
        error "Please run 'aws configure' or set up AWS credentials"
        exit 1
    fi
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ -f ".env" ]; then
        set -a  # Automatically export all variables
        source .env
        set +a
        log "Environment variables loaded from .env file"
    else
        warn "No .env file found. You may need to provide resource names manually."
        
        # Try to get basic AWS info
        export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
        
        if [ -z "$AWS_REGION" ] || [ -z "$AWS_ACCOUNT_ID" ]; then
            error "Failed to get AWS region or account ID"
            exit 1
        fi
        
        warn "Using detected AWS Region: $AWS_REGION"
        warn "Using detected AWS Account: $AWS_ACCOUNT_ID"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warn "⚠️  This will permanently delete all fraud detection resources!"
    echo ""
    info "Resources to be deleted:"
    echo "  - S3 Bucket: ${FRAUD_BUCKET:-<not set>}"
    echo "  - Kinesis Stream: ${KINESIS_STREAM:-<not set>}"
    echo "  - DynamoDB Table: ${DECISIONS_TABLE:-<not set>}"
    echo "  - Model: ${MODEL_NAME:-<not set>}"
    echo "  - Detector: ${DETECTOR_NAME:-<not set>}"
    echo "  - SNS Topic: ${SNS_TOPIC_ARN:-<not set>}"
    echo "  - Lambda Functions: event-enrichment-processor, fraud-detection-processor"
    echo "  - IAM Roles: FraudDetectorEnhancedRole, FraudDetectionLambdaRole"
    echo "  - CloudWatch Dashboard: FraudDetectionPlatform"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed. Proceeding with cleanup..."
}

# Function to delete Fraud Detector resources
delete_fraud_detector() {
    log "Deleting Fraud Detector resources..."
    
    # Deactivate detector version if it exists
    if [ -n "${DETECTOR_NAME:-}" ]; then
        info "Deactivating detector version: $DETECTOR_NAME"
        aws frauddetector update-detector-version-status \
            --detector-id ${DETECTOR_NAME} \
            --detector-version-id "1" \
            --status INACTIVE \
            2>/dev/null || warn "Failed to deactivate detector version or it doesn't exist"
        
        # Wait a moment for deactivation
        sleep 5
        
        # Delete detector version
        info "Deleting detector version: $DETECTOR_NAME"
        aws frauddetector delete-detector-version \
            --detector-id ${DETECTOR_NAME} \
            --detector-version-id "1" \
            2>/dev/null || warn "Failed to delete detector version or it doesn't exist"
        
        # Delete detector
        info "Deleting detector: $DETECTOR_NAME"
        aws frauddetector delete-detector \
            --detector-id ${DETECTOR_NAME} \
            2>/dev/null || warn "Failed to delete detector or it doesn't exist"
    fi
    
    # Delete model version and model
    if [ -n "${MODEL_NAME:-}" ]; then
        info "Deleting model version: $MODEL_NAME"
        aws frauddetector delete-model-version \
            --model-id ${MODEL_NAME} \
            --model-type TRANSACTION_FRAUD_INSIGHTS \
            --model-version-number 1.0 \
            2>/dev/null || warn "Failed to delete model version or it doesn't exist"
        
        info "Deleting model: $MODEL_NAME"
        aws frauddetector delete-model \
            --model-id ${MODEL_NAME} \
            --model-type TRANSACTION_FRAUD_INSIGHTS \
            2>/dev/null || warn "Failed to delete model or it doesn't exist"
    fi
    
    # Delete rules
    info "Deleting fraud detection rules..."
    local rules=("immediate_block_rule" "suspicious_pattern_rule" "challenge_authentication_rule" "approve_low_risk_rule")
    for rule in "${rules[@]}"; do
        aws frauddetector delete-rule \
            --rule-id $rule \
            2>/dev/null || warn "Failed to delete rule $rule or it doesn't exist"
    done
    
    # Delete outcomes
    info "Deleting fraud detection outcomes..."
    local outcomes=("immediate_block" "manual_review" "challenge_authentication" "approve_transaction")
    for outcome in "${outcomes[@]}"; do
        aws frauddetector delete-outcome \
            --name $outcome \
            2>/dev/null || warn "Failed to delete outcome $outcome or it doesn't exist"
    done
    
    # Delete event type
    if [ -n "${EVENT_TYPE_NAME:-}" ]; then
        info "Deleting event type: $EVENT_TYPE_NAME"
        aws frauddetector delete-event-type \
            --name ${EVENT_TYPE_NAME} \
            2>/dev/null || warn "Failed to delete event type or it doesn't exist"
    fi
    
    # Delete entity type
    if [ -n "${ENTITY_TYPE_NAME:-}" ]; then
        info "Deleting entity type: $ENTITY_TYPE_NAME"
        aws frauddetector delete-entity-type \
            --name ${ENTITY_TYPE_NAME} \
            2>/dev/null || warn "Failed to delete entity type or it doesn't exist"
    fi
    
    # Delete labels
    info "Deleting fraud detection labels..."
    aws frauddetector delete-label --name "fraud" 2>/dev/null || warn "Failed to delete fraud label or it doesn't exist"
    aws frauddetector delete-label --name "legit" 2>/dev/null || warn "Failed to delete legit label or it doesn't exist"
    
    # Delete custom variables
    info "Deleting custom variables..."
    local variables=("transaction_frequency" "velocity_score" "geo_distance")
    for var in "${variables[@]}"; do
        aws frauddetector delete-variable \
            --name $var \
            2>/dev/null || warn "Failed to delete variable $var or it doesn't exist"
    done
    
    log "Fraud Detector resources cleanup completed"
}

# Function to delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    # Delete event source mappings first
    info "Deleting Kinesis event source mappings..."
    local mappings=$(aws lambda list-event-source-mappings \
        --function-name event-enrichment-processor \
        --query 'EventSourceMappings[].UUID' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$mappings" ]; then
        for mapping in $mappings; do
            aws lambda delete-event-source-mapping \
                --uuid $mapping \
                2>/dev/null || warn "Failed to delete event source mapping $mapping"
        done
    fi
    
    # Delete Lambda functions
    info "Deleting Lambda function: fraud-detection-processor"
    aws lambda delete-function \
        --function-name fraud-detection-processor \
        2>/dev/null || warn "Failed to delete fraud-detection-processor function or it doesn't exist"
    
    info "Deleting Lambda function: event-enrichment-processor"
    aws lambda delete-function \
        --function-name event-enrichment-processor \
        2>/dev/null || warn "Failed to delete event-enrichment-processor function or it doesn't exist"
    
    log "Lambda functions cleanup completed"
}

# Function to delete SNS topic
delete_sns_topic() {
    log "Deleting SNS topic..."
    
    if [ -n "${SNS_TOPIC_ARN:-}" ]; then
        info "Deleting SNS topic: $SNS_TOPIC_ARN"
        aws sns delete-topic \
            --topic-arn ${SNS_TOPIC_ARN} \
            2>/dev/null || warn "Failed to delete SNS topic or it doesn't exist"
    else
        # Try to find and delete by name
        local topic_arn=$(aws sns list-topics \
            --query 'Topics[?contains(TopicArn, `fraud-detection-alerts`)].TopicArn' \
            --output text 2>/dev/null)
        
        if [ -n "$topic_arn" ]; then
            info "Found and deleting SNS topic: $topic_arn"
            aws sns delete-topic \
                --topic-arn $topic_arn \
                2>/dev/null || warn "Failed to delete SNS topic"
        fi
    fi
    
    log "SNS topic cleanup completed"
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    log "Deleting DynamoDB table..."
    
    if [ -n "${DECISIONS_TABLE:-}" ]; then
        info "Deleting DynamoDB table: $DECISIONS_TABLE"
        aws dynamodb delete-table \
            --table-name ${DECISIONS_TABLE} \
            2>/dev/null || warn "Failed to delete DynamoDB table or it doesn't exist"
        
        # Wait for table deletion
        info "Waiting for DynamoDB table deletion..."
        aws dynamodb wait table-not-exists \
            --table-name ${DECISIONS_TABLE} \
            2>/dev/null || warn "Table deletion wait failed or timed out"
    else
        warn "DynamoDB table name not found in environment variables"
    fi
    
    log "DynamoDB table cleanup completed"
}

# Function to delete Kinesis stream
delete_kinesis_stream() {
    log "Deleting Kinesis stream..."
    
    if [ -n "${KINESIS_STREAM:-}" ]; then
        info "Deleting Kinesis stream: $KINESIS_STREAM"
        aws kinesis delete-stream \
            --stream-name ${KINESIS_STREAM} \
            2>/dev/null || warn "Failed to delete Kinesis stream or it doesn't exist"
        
        # Wait for stream deletion
        info "Waiting for Kinesis stream deletion..."
        local max_attempts=30
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            if ! aws kinesis describe-stream \
                --stream-name ${KINESIS_STREAM} \
                >/dev/null 2>&1; then
                log "Kinesis stream deletion confirmed"
                break
            fi
            
            sleep 10
            attempt=$((attempt + 1))
            info "Waiting for stream deletion... (attempt $attempt/$max_attempts)"
        done
        
        if [ $attempt -eq $max_attempts ]; then
            warn "Kinesis stream deletion timeout - may still be in progress"
        fi
    else
        warn "Kinesis stream name not found in environment variables"
    fi
    
    log "Kinesis stream cleanup completed"
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket..."
    
    if [ -n "${FRAUD_BUCKET:-}" ]; then
        info "Emptying S3 bucket: $FRAUD_BUCKET"
        
        # Check if bucket exists
        if aws s3api head-bucket --bucket ${FRAUD_BUCKET} 2>/dev/null; then
            # Empty bucket contents
            aws s3 rm s3://${FRAUD_BUCKET} --recursive 2>/dev/null || warn "Failed to empty S3 bucket"
            
            # Delete bucket
            info "Deleting S3 bucket: $FRAUD_BUCKET"
            aws s3 rb s3://${FRAUD_BUCKET} 2>/dev/null || warn "Failed to delete S3 bucket"
        else
            warn "S3 bucket does not exist or is not accessible"
        fi
    else
        warn "S3 bucket name not found in environment variables"
    fi
    
    log "S3 bucket cleanup completed"
}

# Function to delete CloudWatch dashboard
delete_cloudwatch_dashboard() {
    log "Deleting CloudWatch dashboard..."
    
    info "Deleting CloudWatch dashboard: FraudDetectionPlatform"
    aws cloudwatch delete-dashboards \
        --dashboard-names "FraudDetectionPlatform" \
        2>/dev/null || warn "Failed to delete CloudWatch dashboard or it doesn't exist"
    
    log "CloudWatch dashboard cleanup completed"
}

# Function to delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    # Delete Lambda execution role
    info "Deleting Lambda execution role..."
    
    # Detach managed policies
    aws iam detach-role-policy \
        --role-name FraudDetectionLambdaRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        2>/dev/null || warn "Failed to detach AWSLambdaBasicExecutionRole policy"
    
    aws iam detach-role-policy \
        --role-name FraudDetectionLambdaRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaKinesisExecutionRole \
        2>/dev/null || warn "Failed to detach AWSLambdaKinesisExecutionRole policy"
    
    # Delete custom policies attached to Lambda role
    local lambda_policies=$(aws iam list-role-policies \
        --role-name FraudDetectionLambdaRole \
        --query 'PolicyNames' \
        --output text 2>/dev/null || echo "")
    
    for policy in $lambda_policies; do
        aws iam delete-role-policy \
            --role-name FraudDetectionLambdaRole \
            --policy-name $policy \
            2>/dev/null || warn "Failed to delete policy $policy"
    done
    
    # Delete Lambda role
    aws iam delete-role \
        --role-name FraudDetectionLambdaRole \
        2>/dev/null || warn "Failed to delete Lambda role or it doesn't exist"
    
    # Delete Fraud Detector role
    info "Deleting Fraud Detector role..."
    
    # Delete inline policies
    aws iam delete-role-policy \
        --role-name FraudDetectorEnhancedRole \
        --policy-name FraudDetectorEnhancedPolicy \
        2>/dev/null || warn "Failed to delete FraudDetectorEnhancedPolicy"
    
    # Delete role
    aws iam delete-role \
        --role-name FraudDetectorEnhancedRole \
        2>/dev/null || warn "Failed to delete Fraud Detector role or it doesn't exist"
    
    log "IAM roles cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [ -f ".env" ]; then
        rm -f .env
        info "Deleted .env file"
    fi
    
    # Remove any temporary files that might exist
    rm -f /tmp/fraud-detector-*.json
    rm -f /tmp/generate_training_data.py
    rm -f /tmp/enhanced_training_data.csv
    rm -f /tmp/*lambda*.py
    rm -f /tmp/*.zip
    rm -f /tmp/fraud_detection_dashboard.json
    rm -f /tmp/test_response.json
    
    log "Local files cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_issues=0
    
    # Check Lambda functions
    if aws lambda get-function --function-name fraud-detection-processor >/dev/null 2>&1; then
        warn "Lambda function fraud-detection-processor still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if aws lambda get-function --function-name event-enrichment-processor >/dev/null 2>&1; then
        warn "Lambda function event-enrichment-processor still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check DynamoDB table
    if [ -n "${DECISIONS_TABLE:-}" ]; then
        if aws dynamodb describe-table --table-name ${DECISIONS_TABLE} >/dev/null 2>&1; then
            warn "DynamoDB table ${DECISIONS_TABLE} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check Kinesis stream
    if [ -n "${KINESIS_STREAM:-}" ]; then
        if aws kinesis describe-stream --stream-name ${KINESIS_STREAM} >/dev/null 2>&1; then
            warn "Kinesis stream ${KINESIS_STREAM} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check S3 bucket
    if [ -n "${FRAUD_BUCKET:-}" ]; then
        if aws s3api head-bucket --bucket ${FRAUD_BUCKET} >/dev/null 2>&1; then
            warn "S3 bucket ${FRAUD_BUCKET} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name FraudDetectorEnhancedRole >/dev/null 2>&1; then
        warn "IAM role FraudDetectorEnhancedRole still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if aws iam get-role --role-name FraudDetectionLambdaRole >/dev/null 2>&1; then
        warn "IAM role FraudDetectionLambdaRole still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log "Cleanup verification passed - all resources appear to be deleted"
    else
        warn "Cleanup verification found $cleanup_issues potential issues"
        warn "Some resources may still exist or be in the process of deletion"
        warn "Please check the AWS console to verify complete cleanup"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it to run cleanup"
        exit 1
    fi
    
    # Check AWS authentication
    check_aws_auth
    
    log "Prerequisites check completed"
}

# Main cleanup function
main() {
    log "Starting fraud detection platform cleanup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Load environment variables
    load_environment
    
    # Confirm deletion
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_fraud_detector
    delete_lambda_functions
    delete_sns_topic
    delete_cloudwatch_dashboard
    delete_dynamodb_table
    delete_kinesis_stream
    delete_s3_bucket
    delete_iam_roles
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    log "Fraud detection platform cleanup completed!"
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    echo "✅ Fraud Detector resources deleted"
    echo "✅ Lambda functions deleted"
    echo "✅ SNS topic deleted"
    echo "✅ CloudWatch dashboard deleted"
    echo "✅ DynamoDB table deleted"
    echo "✅ Kinesis stream deleted"
    echo "✅ S3 bucket deleted"
    echo "✅ IAM roles deleted"
    echo "✅ Local files cleaned up"
    echo ""
    warn "Note: Some resources may take a few minutes to fully delete"
    warn "Please check the AWS console if you need to verify complete cleanup"
    echo ""
    log "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Script interrupted by user"; exit 1' INT TERM

# Run main function
main "$@"