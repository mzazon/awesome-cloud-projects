#!/bin/bash

# Cleanup script for Serverless Real-Time Analytics Pipeline with Kinesis and Lambda
# This script removes all infrastructure created by the deploy.sh script

set -euo pipefail

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if AWS CLI is configured
check_aws_config() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured or credentials are invalid"
        error "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS configuration
    check_aws_config
    
    # Check if environment file exists
    if [ ! -f .env ]; then
        error "Environment file (.env) not found. This script requires the environment file created by deploy.sh"
        error "If you deployed resources manually, you'll need to delete them manually as well."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables from .env file..."
    
    # Source the environment file
    source .env
    
    log "Loaded environment variables:"
    log "Kinesis Stream: ${KINESIS_STREAM_NAME:-'Not set'}"
    log "Lambda Function: ${LAMBDA_FUNCTION_NAME:-'Not set'}"
    log "DynamoDB Table: ${DYNAMODB_TABLE_NAME:-'Not set'}"
    log "IAM Role: ${IAM_ROLE_NAME:-'Not set'}"
    log "Random Suffix: ${RANDOM_SUFFIX:-'Not set'}"
    
    success "Environment variables loaded"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warning "This will DELETE ALL resources created by the deployment script:"
    echo "  - Kinesis Data Stream: ${KINESIS_STREAM_NAME}"
    echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  - DynamoDB Table: ${DYNAMODB_TABLE_NAME}"
    echo "  - IAM Role: ${IAM_ROLE_NAME}"
    echo "  - CloudWatch Alarms: KinesisLambdaProcessorErrors-${RANDOM_SUFFIX}, DynamoDBThrottling-${RANDOM_SUFFIX}"
    echo "  - Event Source Mapping between Kinesis and Lambda"
    echo ""
    warning "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource deletion..."
}

# Function to delete event source mapping
delete_event_source_mapping() {
    log "Deleting event source mapping..."
    
    if [ -n "${EVENT_SOURCE_MAPPING_UUID:-}" ]; then
        if aws lambda delete-event-source-mapping --uuid "$EVENT_SOURCE_MAPPING_UUID" >/dev/null 2>&1; then
            success "Event source mapping deleted successfully"
        else
            warning "Event source mapping may have already been deleted or doesn't exist"
        fi
    else
        # Try to find and delete mapping by function name
        log "Searching for event source mappings for function: $LAMBDA_FUNCTION_NAME"
        local mappings
        mappings=$(aws lambda list-event-source-mappings \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --query 'EventSourceMappings[].UUID' \
            --output text 2>/dev/null || true)
        
        if [ -n "$mappings" ] && [ "$mappings" != "None" ]; then
            for uuid in $mappings; do
                log "Deleting event source mapping: $uuid"
                if aws lambda delete-event-source-mapping --uuid "$uuid" >/dev/null 2>&1; then
                    success "Event source mapping $uuid deleted"
                else
                    warning "Failed to delete event source mapping $uuid"
                fi
            done
        else
            warning "No event source mappings found for function $LAMBDA_FUNCTION_NAME"
        fi
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function: $LAMBDA_FUNCTION_NAME"
    
    # Check if function exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        if aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"; then
            success "Lambda function deleted successfully"
        else
            error "Failed to delete Lambda function"
            return 1
        fi
    else
        warning "Lambda function $LAMBDA_FUNCTION_NAME not found or already deleted"
    fi
}

# Function to delete Kinesis Data Stream
delete_kinesis_stream() {
    log "Deleting Kinesis Data Stream: $KINESIS_STREAM_NAME"
    
    # Check if stream exists
    if aws kinesis describe-stream --stream-name "$KINESIS_STREAM_NAME" >/dev/null 2>&1; then
        if aws kinesis delete-stream --stream-name "$KINESIS_STREAM_NAME"; then
            log "Kinesis stream deletion initiated..."
            
            # Wait for stream to be deleted (optional)
            log "Waiting for Kinesis stream to be deleted (this may take a few minutes)..."
            local attempts=0
            local max_attempts=30
            
            while [ $attempts -lt $max_attempts ]; do
                if ! aws kinesis describe-stream --stream-name "$KINESIS_STREAM_NAME" >/dev/null 2>&1; then
                    success "Kinesis stream deleted successfully"
                    return 0
                fi
                
                log "Stream still exists, waiting... (attempt $((attempts + 1))/$max_attempts)"
                sleep 10
                attempts=$((attempts + 1))
            done
            
            warning "Kinesis stream deletion is still in progress. It may take additional time to complete."
        else
            error "Failed to delete Kinesis stream"
            return 1
        fi
    else
        warning "Kinesis stream $KINESIS_STREAM_NAME not found or already deleted"
    fi
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    log "Deleting DynamoDB table: $DYNAMODB_TABLE_NAME"
    
    # Check if table exists
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE_NAME" >/dev/null 2>&1; then
        if aws dynamodb delete-table --table-name "$DYNAMODB_TABLE_NAME" >/dev/null; then
            log "DynamoDB table deletion initiated..."
            
            # Wait for table to be deleted
            log "Waiting for DynamoDB table to be deleted..."
            if aws dynamodb wait table-not-exists --table-name "$DYNAMODB_TABLE_NAME"; then
                success "DynamoDB table deleted successfully"
            else
                warning "DynamoDB table deletion may still be in progress"
            fi
        else
            error "Failed to delete DynamoDB table"
            return 1
        fi
    else
        warning "DynamoDB table $DYNAMODB_TABLE_NAME not found or already deleted"
    fi
}

# Function to delete IAM role and policies
delete_iam_role() {
    log "Deleting IAM role and policies..."
    
    # Check if role exists
    if aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
        # Delete attached policies first
        log "Deleting role policy: KinesisLambdaProcessorPolicy"
        if aws iam delete-role-policy \
            --role-name "$IAM_ROLE_NAME" \
            --policy-name KinesisLambdaProcessorPolicy >/dev/null 2>&1; then
            success "Role policy deleted successfully"
        else
            warning "Role policy may have already been deleted"
        fi
        
        # Delete the role
        log "Deleting IAM role: $IAM_ROLE_NAME"
        if aws iam delete-role --role-name "$IAM_ROLE_NAME"; then
            success "IAM role deleted successfully"
        else
            error "Failed to delete IAM role"
            return 1
        fi
    else
        warning "IAM role $IAM_ROLE_NAME not found or already deleted"
    fi
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    local alarm_names=()
    
    # Check for Lambda error alarm
    if [ -n "${LAMBDA_ERROR_ALARM:-}" ]; then
        alarm_names+=("$LAMBDA_ERROR_ALARM")
    else
        alarm_names+=("KinesisLambdaProcessorErrors-${RANDOM_SUFFIX}")
    fi
    
    # Check for DynamoDB throttling alarm
    if [ -n "${DYNAMODB_THROTTLING_ALARM:-}" ]; then
        alarm_names+=("$DYNAMODB_THROTTLING_ALARM")
    else
        alarm_names+=("DynamoDBThrottling-${RANDOM_SUFFIX}")
    fi
    
    # Delete alarms
    for alarm_name in "${alarm_names[@]}"; do
        log "Checking for alarm: $alarm_name"
        if aws cloudwatch describe-alarms --alarm-names "$alarm_name" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm_name"; then
            log "Deleting alarm: $alarm_name"
            if aws cloudwatch delete-alarms --alarm-names "$alarm_name"; then
                success "Alarm $alarm_name deleted successfully"
            else
                warning "Failed to delete alarm $alarm_name"
            fi
        else
            warning "Alarm $alarm_name not found or already deleted"
        fi
    done
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        ".env"
        "lambda-kinesis-policy.json"
        "lambda-trust-policy.json"
        "lambda-processor.zip"
        "data_producer.py"
    )
    
    local dirs_to_remove=(
        "lambda-processor"
    )
    
    # Remove files
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Removed file: $file"
        fi
    done
    
    # Remove directories
    for dir in "${dirs_to_remove[@]}"; do
        if [ -d "$dir" ]; then
            rm -rf "$dir"
            log "Removed directory: $dir"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary:"
    echo "=================================="
    echo "The following resources have been deleted:"
    echo "  ✓ Event Source Mapping"
    echo "  ✓ Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "  ✓ Kinesis Data Stream: $KINESIS_STREAM_NAME"
    echo "  ✓ DynamoDB Table: $DYNAMODB_TABLE_NAME"
    echo "  ✓ IAM Role: $IAM_ROLE_NAME"
    echo "  ✓ CloudWatch Alarms"
    echo "  ✓ Local files and directories"
    echo "=================================="
    echo ""
    success "Cleanup completed successfully!"
    echo ""
    log "All resources from the Serverless Real-Time Analytics Pipeline have been removed."
    log "You can now run deploy.sh again to create a new deployment if needed."
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    error "An error occurred during cleanup. Some resources may not have been deleted."
    error "Please check the AWS Console to verify which resources still exist and delete them manually if necessary."
    
    echo ""
    log "Resources that should be checked manually:"
    echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME:-'Unknown'}"
    echo "  - Kinesis Data Stream: ${KINESIS_STREAM_NAME:-'Unknown'}"
    echo "  - DynamoDB Table: ${DYNAMODB_TABLE_NAME:-'Unknown'}"
    echo "  - IAM Role: ${IAM_ROLE_NAME:-'Unknown'}"
    echo "  - CloudWatch Alarms with suffix: ${RANDOM_SUFFIX:-'Unknown'}"
    
    exit 1
}

# Main cleanup function
main() {
    log "Starting cleanup of Serverless Real-Time Analytics Pipeline"
    
    # Set trap for error handling
    trap handle_cleanup_error ERR
    
    check_prerequisites
    load_environment
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_event_source_mapping
    delete_lambda_function
    delete_kinesis_stream
    delete_dynamodb_table
    delete_iam_role
    delete_cloudwatch_alarms
    cleanup_local_files
    
    display_summary
}

# Run main function
main "$@"