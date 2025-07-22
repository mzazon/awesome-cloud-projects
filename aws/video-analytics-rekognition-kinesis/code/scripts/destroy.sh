#!/bin/bash

# Real-Time Video Analytics with Rekognition and Kinesis - Cleanup Script
# This script safely removes all AWS resources created by the deployment script
# including:
# - Rekognition stream processors and face collections
# - Lambda functions and event source mappings
# - DynamoDB tables and Kinesis streams
# - API Gateway and SNS topics
# - IAM roles and policies

set -e

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
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check for environment file
    if [ ! -f ".env" ]; then
        error "Environment file .env not found. Cannot determine resources to clean up."
        error "Please ensure you're running this script from the same directory as deploy.sh"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Source environment variables from deployment
    source .env
    
    # Verify required variables are set
    REQUIRED_VARS=("AWS_REGION" "AWS_ACCOUNT_ID" "PROJECT_NAME" "STREAM_NAME" "ROLE_NAME" "COLLECTION_NAME")
    
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    log "Loaded configuration for project: $PROJECT_NAME"
    success "Environment variables loaded"
}

# Function to confirm destruction
confirm_destruction() {
    echo
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    warning "This will permanently delete ALL resources created for project: $PROJECT_NAME"
    warning "This includes:"
    warning "  - Rekognition stream processors and face collections"
    warning "  - Lambda functions and their code"
    warning "  - DynamoDB tables and ALL their data"
    warning "  - Kinesis streams and video streams"
    warning "  - API Gateway endpoints"
    warning "  - SNS topics and subscriptions"
    warning "  - IAM roles and policies"
    echo
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " -r
    echo
    if [[ $REPLY != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource cleanup..."
}

# Function to stop and delete stream processor
cleanup_stream_processor() {
    log "Cleaning up Rekognition stream processor..."
    
    # Check if stream processor exists
    if aws rekognition describe-stream-processor --name "${PROJECT_NAME}-processor" &> /dev/null; then
        # Get current status
        PROCESSOR_STATUS=$(aws rekognition describe-stream-processor \
            --name "${PROJECT_NAME}-processor" \
            --query 'Status' --output text)
        
        log "Stream processor current status: $PROCESSOR_STATUS"
        
        # Stop if running
        if [ "$PROCESSOR_STATUS" = "RUNNING" ]; then
            log "Stopping stream processor..."
            aws rekognition stop-stream-processor \
                --name "${PROJECT_NAME}-processor"
            
            log "Waiting for stream processor to stop..."
            # Wait for processor to stop (with timeout)
            for i in {1..60}; do
                CURRENT_STATUS=$(aws rekognition describe-stream-processor \
                    --name "${PROJECT_NAME}-processor" \
                    --query 'Status' --output text 2>/dev/null || echo "STOPPED")
                
                if [ "$CURRENT_STATUS" = "STOPPED" ]; then
                    break
                fi
                
                if [ $i -eq 60 ]; then
                    warning "Timeout waiting for stream processor to stop, continuing with deletion"
                    break
                fi
                
                sleep 2
            done
        fi
        
        # Delete stream processor
        log "Deleting stream processor..."
        aws rekognition delete-stream-processor \
            --name "${PROJECT_NAME}-processor"
        
        success "Stream processor deleted"
    else
        warning "Stream processor ${PROJECT_NAME}-processor not found"
    fi
}

# Function to delete Lambda functions and event source mappings
cleanup_lambda_functions() {
    log "Cleaning up Lambda functions..."
    
    # Delete event source mappings first
    log "Removing event source mappings..."
    
    for function_name in "${PROJECT_NAME}-analytics-processor" "${PROJECT_NAME}-query-api"; do
        if aws lambda get-function --function-name "$function_name" &> /dev/null; then
            # List and delete event source mappings
            MAPPINGS=$(aws lambda list-event-source-mappings \
                --function-name "$function_name" \
                --query 'EventSourceMappings[].UUID' \
                --output text)
            
            if [ -n "$MAPPINGS" ]; then
                for mapping in $MAPPINGS; do
                    log "Deleting event source mapping: $mapping"
                    aws lambda delete-event-source-mapping --uuid "$mapping" || warning "Failed to delete mapping $mapping"
                done
            fi
        fi
    done
    
    # Delete Lambda functions
    for function_name in "${PROJECT_NAME}-analytics-processor" "${PROJECT_NAME}-query-api"; do
        if aws lambda get-function --function-name "$function_name" &> /dev/null; then
            log "Deleting Lambda function: $function_name"
            aws lambda delete-function --function-name "$function_name"
            success "Deleted Lambda function: $function_name"
        else
            warning "Lambda function $function_name not found"
        fi
    done
}

# Function to delete API Gateway
cleanup_api_gateway() {
    log "Cleaning up API Gateway..."
    
    if [ -n "$API_ID" ]; then
        if aws apigatewayv2 get-api --api-id "$API_ID" &> /dev/null; then
            log "Deleting API Gateway: $API_ID"
            aws apigatewayv2 delete-api --api-id "$API_ID"
            success "API Gateway deleted"
        else
            warning "API Gateway $API_ID not found"
        fi
    else
        warning "API_ID not found in environment, skipping API Gateway cleanup"
    fi
}

# Function to delete DynamoDB tables
cleanup_dynamodb_tables() {
    log "Cleaning up DynamoDB tables..."
    
    for table_name in "${PROJECT_NAME}-detections" "${PROJECT_NAME}-faces"; do
        if aws dynamodb describe-table --table-name "$table_name" &> /dev/null; then
            log "Deleting DynamoDB table: $table_name"
            aws dynamodb delete-table --table-name "$table_name"
            
            log "Waiting for table deletion to complete..."
            aws dynamodb wait table-not-exists --table-name "$table_name" || warning "Timeout waiting for table deletion"
            
            success "Deleted DynamoDB table: $table_name"
        else
            warning "DynamoDB table $table_name not found"
        fi
    done
}

# Function to delete Kinesis streams
cleanup_kinesis_streams() {
    log "Cleaning up Kinesis streams..."
    
    # Delete Kinesis Data Stream
    if aws kinesis describe-stream --stream-name "${PROJECT_NAME}-analytics" &> /dev/null; then
        log "Deleting Kinesis Data Stream: ${PROJECT_NAME}-analytics"
        aws kinesis delete-stream --stream-name "${PROJECT_NAME}-analytics"
        success "Deleted Kinesis Data Stream: ${PROJECT_NAME}-analytics"
    else
        warning "Kinesis Data Stream ${PROJECT_NAME}-analytics not found"
    fi
    
    # Delete Kinesis Video Stream
    if [ -n "$STREAM_ARN" ]; then
        if aws kinesisvideo describe-stream --stream-name "$STREAM_NAME" &> /dev/null; then
            log "Deleting Kinesis Video Stream: $STREAM_NAME"
            aws kinesisvideo delete-stream --stream-arn "$STREAM_ARN"
            success "Deleted Kinesis Video Stream: $STREAM_NAME"
        else
            warning "Kinesis Video Stream $STREAM_NAME not found"
        fi
    else
        warning "STREAM_ARN not found, attempting to delete by name"
        if aws kinesisvideo describe-stream --stream-name "$STREAM_NAME" &> /dev/null; then
            STREAM_ARN=$(aws kinesisvideo describe-stream \
                --stream-name "$STREAM_NAME" \
                --query 'StreamInfo.StreamARN' \
                --output text)
            aws kinesisvideo delete-stream --stream-arn "$STREAM_ARN"
            success "Deleted Kinesis Video Stream: $STREAM_NAME"
        else
            warning "Kinesis Video Stream $STREAM_NAME not found"
        fi
    fi
}

# Function to delete face collection
cleanup_face_collection() {
    log "Cleaning up Rekognition face collection..."
    
    if aws rekognition describe-collection --collection-id "$COLLECTION_NAME" &> /dev/null; then
        log "Deleting face collection: $COLLECTION_NAME"
        aws rekognition delete-collection --collection-id "$COLLECTION_NAME"
        success "Deleted face collection: $COLLECTION_NAME"
    else
        warning "Face collection $COLLECTION_NAME not found"
    fi
}

# Function to delete SNS topic
cleanup_sns_topic() {
    log "Cleaning up SNS topic..."
    
    if [ -n "$TOPIC_ARN" ]; then
        if aws sns get-topic-attributes --topic-arn "$TOPIC_ARN" &> /dev/null; then
            log "Deleting SNS topic: $TOPIC_ARN"
            aws sns delete-topic --topic-arn "$TOPIC_ARN"
            success "Deleted SNS topic: $TOPIC_ARN"
        else
            warning "SNS topic $TOPIC_ARN not found"
        fi
    else
        warning "TOPIC_ARN not found in environment"
        # Try to find and delete by name
        TOPIC_ARN_BY_NAME=$(aws sns list-topics \
            --query "Topics[?contains(TopicArn, '${PROJECT_NAME}-security-alerts')].TopicArn" \
            --output text)
        
        if [ -n "$TOPIC_ARN_BY_NAME" ]; then
            log "Found SNS topic by name, deleting: $TOPIC_ARN_BY_NAME"
            aws sns delete-topic --topic-arn "$TOPIC_ARN_BY_NAME"
            success "Deleted SNS topic by name"
        else
            warning "Could not find SNS topic to delete"
        fi
    fi
}

# Function to delete IAM role
cleanup_iam_role() {
    log "Cleaning up IAM role..."
    
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        log "Detaching policies from IAM role: $ROLE_NAME"
        
        # List and detach all attached policies
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$ROLE_NAME" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text)
        
        if [ -n "$ATTACHED_POLICIES" ]; then
            for policy in $ATTACHED_POLICIES; do
                log "Detaching policy: $policy"
                aws iam detach-role-policy \
                    --role-name "$ROLE_NAME" \
                    --policy-arn "$policy" || warning "Failed to detach policy $policy"
            done
        fi
        
        log "Deleting IAM role: $ROLE_NAME"
        aws iam delete-role --role-name "$ROLE_NAME"
        success "Deleted IAM role: $ROLE_NAME"
    else
        warning "IAM role $ROLE_NAME not found"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files that might still exist
    for file in trust-policy.json stream_processor_config.json \
                analytics_processor.py analytics_processor.zip \
                query_api.py query_api.zip; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Removed temporary file: $file"
        fi
    done
    
    # Ask user if they want to remove .env file
    read -p "Remove environment file (.env)? This will make it harder to re-run cleanup if needed (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f .env
        log "Removed environment file"
    else
        log "Keeping environment file for potential future cleanup"
    fi
    
    success "Local file cleanup completed"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating resource cleanup..."
    
    local cleanup_issues=0
    
    # Check stream processor
    if aws rekognition describe-stream-processor --name "${PROJECT_NAME}-processor" &> /dev/null; then
        warning "Stream processor still exists: ${PROJECT_NAME}-processor"
        ((cleanup_issues++))
    fi
    
    # Check Lambda functions
    for function_name in "${PROJECT_NAME}-analytics-processor" "${PROJECT_NAME}-query-api"; do
        if aws lambda get-function --function-name "$function_name" &> /dev/null; then
            warning "Lambda function still exists: $function_name"
            ((cleanup_issues++))
        fi
    done
    
    # Check DynamoDB tables
    for table_name in "${PROJECT_NAME}-detections" "${PROJECT_NAME}-faces"; do
        TABLE_STATUS=$(aws dynamodb describe-table --table-name "$table_name" \
            --query 'Table.TableStatus' --output text 2>/dev/null || echo "NOT_FOUND")
        if [ "$TABLE_STATUS" != "NOT_FOUND" ]; then
            if [ "$TABLE_STATUS" = "DELETING" ]; then
                log "DynamoDB table still deleting: $table_name"
            else
                warning "DynamoDB table still exists: $table_name (Status: $TABLE_STATUS)"
                ((cleanup_issues++))
            fi
        fi
    done
    
    # Check face collection
    if aws rekognition describe-collection --collection-id "$COLLECTION_NAME" &> /dev/null; then
        warning "Face collection still exists: $COLLECTION_NAME"
        ((cleanup_issues++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        warning "IAM role still exists: $ROLE_NAME"
        ((cleanup_issues++))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        success "All resources appear to have been cleaned up successfully"
    else
        warning "Found $cleanup_issues potential cleanup issues"
        warning "Some resources may take time to fully delete or may require manual intervention"
    fi
    
    log "Cleanup validation completed"
}

# Main cleanup function
main() {
    log "Starting Real-Time Video Analytics cleanup..."
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    # Execute cleanup in reverse order of creation
    cleanup_stream_processor
    cleanup_lambda_functions
    cleanup_api_gateway
    cleanup_dynamodb_tables
    cleanup_kinesis_streams
    cleanup_face_collection
    cleanup_sns_topic
    cleanup_iam_role
    cleanup_local_files
    validate_cleanup
    
    success "Cleanup completed successfully!"
    
    echo
    log "=== CLEANUP SUMMARY ==="
    log "Project: $PROJECT_NAME"
    log "All AWS resources have been removed"
    log "Estimated monthly charges should now be $0"
    echo
    log "If you encounter any issues with remaining resources,"
    log "you can manually delete them using the AWS Console"
    log "or contact AWS Support for assistance."
}

# Handle script interruption
trap 'error "Script interrupted"; exit 1' INT TERM

# Run main function
main