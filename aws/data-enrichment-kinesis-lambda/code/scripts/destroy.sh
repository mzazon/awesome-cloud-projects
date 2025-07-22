#!/bin/bash

# Destroy script for Streaming Data Enrichment with Kinesis
# This script removes all infrastructure components created for the data enrichment pipeline

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

# Error handler
error_handler() {
    log_error "Script failed at line $1"
    log_error "Some resources may not have been deleted. Please check AWS Console."
    exit 1
}

trap 'error_handler $LINENO' ERR

# Function to confirm destruction
confirm_destruction() {
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete the following AWS resources:"
    echo "  • Lambda Function: ${FUNCTION_NAME:-<function>}"
    echo "  • Kinesis Data Stream: ${STREAM_NAME:-<stream>}"
    echo "  • DynamoDB Table: ${TABLE_NAME:-<table>} (and all data)"
    echo "  • S3 Bucket: ${BUCKET_NAME:-<bucket>} (and all objects)"
    echo "  • IAM Role and Policy: ${ROLE_NAME:-<role>}"
    echo "  • CloudWatch Alarms"
    echo ""
    echo "💰 This operation will stop all charges for these resources."
    echo ""
    read -p "Are you absolutely sure you want to continue? (Type 'DELETE' to confirm): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log_warning "Destruction cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource destruction..."
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to load from saved environment file
    if [ -f "/tmp/data-enrichment-env.sh" ]; then
        log "Loading environment from /tmp/data-enrichment-env.sh"
        source /tmp/data-enrichment-env.sh
    else
        log_warning "Environment file not found. You'll need to provide resource names manually."
        
        # Prompt for resource names if not in environment
        if [ -z "${STREAM_NAME:-}" ]; then
            read -p "Enter Kinesis Stream Name: " STREAM_NAME
            export STREAM_NAME
        fi
        
        if [ -z "${FUNCTION_NAME:-}" ]; then
            read -p "Enter Lambda Function Name: " FUNCTION_NAME
            export FUNCTION_NAME
        fi
        
        if [ -z "${BUCKET_NAME:-}" ]; then
            read -p "Enter S3 Bucket Name: " BUCKET_NAME
            export BUCKET_NAME
        fi
        
        if [ -z "${TABLE_NAME:-}" ]; then
            read -p "Enter DynamoDB Table Name: " TABLE_NAME
            export TABLE_NAME
        fi
        
        if [ -z "${ROLE_NAME:-}" ]; then
            read -p "Enter IAM Role Name: " ROLE_NAME
            export ROLE_NAME
        fi
        
        # Set AWS region and account ID
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
        fi
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
    
    log_success "Environment variables loaded"
    log "Stream Name: ${STREAM_NAME}"
    log "Function Name: ${FUNCTION_NAME}"
    log "Bucket Name: ${BUCKET_NAME}"
    log "Table Name: ${TABLE_NAME}"
    log "Role Name: ${ROLE_NAME}"
}

# Function to delete event source mapping
delete_event_source_mapping() {
    log "Deleting event source mapping..."
    
    # List and delete event source mappings for the Lambda function
    MAPPING_UUIDS=$(aws lambda list-event-source-mappings \
        --function-name ${FUNCTION_NAME} \
        --query 'EventSourceMappings[].UUID' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$MAPPING_UUIDS" ] && [ "$MAPPING_UUIDS" != "None" ]; then
        for uuid in $MAPPING_UUIDS; do
            log "Deleting event source mapping: $uuid"
            aws lambda delete-event-source-mapping --uuid $uuid 2>/dev/null || true
        done
        log_success "Event source mappings deleted"
    else
        log_warning "No event source mappings found for function ${FUNCTION_NAME}"
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    log "Deleting Lambda function..."
    
    # Check if function exists before attempting deletion
    if aws lambda get-function --function-name ${FUNCTION_NAME} &>/dev/null; then
        aws lambda delete-function --function-name ${FUNCTION_NAME}
        log_success "Lambda function deleted: ${FUNCTION_NAME}"
    else
        log_warning "Lambda function ${FUNCTION_NAME} not found or already deleted"
    fi
}

# Function to delete Kinesis Data Stream
delete_kinesis_stream() {
    log "Deleting Kinesis Data Stream..."
    
    # Check if stream exists before attempting deletion
    if aws kinesis describe-stream --stream-name ${STREAM_NAME} &>/dev/null; then
        aws kinesis delete-stream --stream-name ${STREAM_NAME}
        
        # Wait for stream to be deleted
        log "Waiting for Kinesis stream to be deleted..."
        while aws kinesis describe-stream --stream-name ${STREAM_NAME} &>/dev/null; do
            sleep 30
            log "Still waiting for stream deletion..."
        done
        
        log_success "Kinesis Data Stream deleted: ${STREAM_NAME}"
    else
        log_warning "Kinesis stream ${STREAM_NAME} not found or already deleted"
    fi
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    # List of alarm names to delete
    ALARM_NAMES=(
        "${FUNCTION_NAME}-Errors"
        "${STREAM_NAME}-IncomingRecords"
        "${FUNCTION_NAME}-Duration"
    )
    
    for alarm_name in "${ALARM_NAMES[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm_name" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm_name"; then
            aws cloudwatch delete-alarms --alarm-names "$alarm_name"
            log "Deleted alarm: $alarm_name"
        else
            log_warning "Alarm $alarm_name not found or already deleted"
        fi
    done
    
    log_success "CloudWatch alarms deleted"
}

# Function to delete S3 bucket and contents
delete_s3_bucket() {
    log "Deleting S3 bucket and all contents..."
    
    # Check if bucket exists
    if aws s3api head-bucket --bucket ${BUCKET_NAME} 2>/dev/null; then
        # Delete all objects and versions in the bucket
        log "Deleting all objects in bucket..."
        aws s3 rm s3://${BUCKET_NAME} --recursive 2>/dev/null || true
        
        # Delete all object versions (if versioning was enabled)
        log "Deleting all object versions..."
        aws s3api delete-objects \
            --bucket ${BUCKET_NAME} \
            --delete "$(aws s3api list-object-versions \
                --bucket ${BUCKET_NAME} \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
                --max-items 1000)" 2>/dev/null || true
        
        # Delete all delete markers
        aws s3api delete-objects \
            --bucket ${BUCKET_NAME} \
            --delete "$(aws s3api list-object-versions \
                --bucket ${BUCKET_NAME} \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
                --max-items 1000)" 2>/dev/null || true
        
        # Delete the bucket
        aws s3 rb s3://${BUCKET_NAME} --force
        log_success "S3 bucket deleted: ${BUCKET_NAME}"
    else
        log_warning "S3 bucket ${BUCKET_NAME} not found or already deleted"
    fi
}

# Function to delete DynamoDB table
delete_dynamodb_table() {
    log "Deleting DynamoDB table..."
    
    # Check if table exists before attempting deletion
    if aws dynamodb describe-table --table-name ${TABLE_NAME} &>/dev/null; then
        aws dynamodb delete-table --table-name ${TABLE_NAME}
        
        # Wait for table to be deleted
        log "Waiting for DynamoDB table to be deleted..."
        aws dynamodb wait table-not-exists --table-name ${TABLE_NAME}
        
        log_success "DynamoDB table deleted: ${TABLE_NAME}"
    else
        log_warning "DynamoDB table ${TABLE_NAME} not found or already deleted"
    fi
}

# Function to delete IAM role and policy
delete_iam_resources() {
    log "Deleting IAM role and policy..."
    
    # Check if role exists
    if aws iam get-role --role-name ${ROLE_NAME} &>/dev/null; then
        # Detach AWS managed policies
        log "Detaching AWS managed policies..."
        aws iam detach-role-policy \
            --role-name ${ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
            2>/dev/null || true
        
        # Detach and delete custom policy
        log "Detaching and deleting custom policy..."
        aws iam detach-role-policy \
            --role-name ${ROLE_NAME} \
            --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-policy \
            2>/dev/null || true
        
        # Delete custom policy
        if aws iam get-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-policy &>/dev/null; then
            aws iam delete-policy \
                --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${ROLE_NAME}-policy
            log "Deleted custom policy: ${ROLE_NAME}-policy"
        fi
        
        # Delete IAM role
        aws iam delete-role --role-name ${ROLE_NAME}
        log_success "IAM role deleted: ${ROLE_NAME}"
    else
        log_warning "IAM role ${ROLE_NAME} not found or already deleted"
    fi
}

# Function to clean up temporary files
cleanup_temporary_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files
    rm -f /tmp/trust-policy.json /tmp/lambda-policy.json 2>/dev/null || true
    rm -f /tmp/enrichment_function.py /tmp/enrichment_function.zip 2>/dev/null || true
    rm -f /tmp/enriched_sample.json 2>/dev/null || true
    
    # Clean up environment file
    rm -f /tmp/data-enrichment-env.sh 2>/dev/null || true
    
    log_success "Temporary files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check Lambda function
    if aws lambda get-function --function-name ${FUNCTION_NAME} &>/dev/null; then
        log_error "Lambda function ${FUNCTION_NAME} still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check Kinesis stream
    if aws kinesis describe-stream --stream-name ${STREAM_NAME} &>/dev/null; then
        log_error "Kinesis stream ${STREAM_NAME} still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name ${TABLE_NAME} &>/dev/null; then
        log_error "DynamoDB table ${TABLE_NAME} still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket ${BUCKET_NAME} &>/dev/null; then
        log_error "S3 bucket ${BUCKET_NAME} still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name ${ROLE_NAME} &>/dev/null; then
        log_error "IAM role ${ROLE_NAME} still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log_success "All resources successfully cleaned up"
    else
        log_warning "Some resources may still exist. Please check AWS Console manually."
    fi
}

# Function to display cleanup summary
display_summary() {
    log_success "=== Cleanup Complete ==="
    echo ""
    echo "Resources Deleted:"
    echo "  • Lambda Function: ${FUNCTION_NAME}"
    echo "  • Kinesis Data Stream: ${STREAM_NAME}"
    echo "  • DynamoDB Table: ${TABLE_NAME}"
    echo "  • S3 Bucket: ${BUCKET_NAME}"
    echo "  • IAM Role and Policy: ${ROLE_NAME}"
    echo "  • CloudWatch Alarms: 3 alarms"
    echo ""
    echo "💰 All charges for these resources have been stopped."
    echo ""
    echo "Note: Some services may have a brief delay before charges completely stop."
    echo "Check your AWS billing console to confirm all resources are removed."
    echo ""
    echo "If you need to redeploy this solution, run the deploy.sh script again."
}

# Main destruction function
main() {
    log "=== Starting Data Enrichment Pipeline Cleanup ==="
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    # Delete resources in reverse dependency order
    delete_event_source_mapping
    delete_lambda_function
    delete_kinesis_stream
    delete_cloudwatch_alarms
    delete_s3_bucket
    delete_dynamodb_table
    delete_iam_resources
    cleanup_temporary_files
    
    verify_cleanup
    display_summary
}

# Handle script arguments
case "${1:-}" in
    --force)
        # Skip confirmation when --force flag is used
        log_warning "Force mode enabled - skipping confirmation"
        FORCE_MODE=true
        ;;
    --help|-h)
        echo "Usage: $0 [--force] [--help]"
        echo ""
        echo "Options:"
        echo "  --force    Skip confirmation prompt (use with caution)"
        echo "  --help     Show this help message"
        echo ""
        echo "This script will delete all AWS resources created by the deploy.sh script."
        echo "Make sure you have the correct AWS credentials configured."
        exit 0
        ;;
    "")
        # No arguments - normal interactive mode
        FORCE_MODE=false
        ;;
    *)
        log_error "Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Override confirmation function if force mode is enabled
if [ "${FORCE_MODE:-false}" = "true" ]; then
    confirm_destruction() {
        log_warning "Force mode: Skipping confirmation"
    }
fi

# Run main function
main "$@"