#!/bin/bash

#################################################################################
# Real-Time Stream Enrichment with Kinesis Data Firehose and EventBridge Pipes
# Cleanup/Destroy Script
#################################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_ROOT/cleanup.log"
CONFIG_FILE="$PROJECT_ROOT/.deployment-config"

# Force cleanup flag
FORCE_CLEANUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE_CLEANUP=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force|-f] [--help|-h]"
            echo "  --force, -f    Force cleanup without confirmation prompts"
            echo "  --help, -h     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

#################################################################################
# Load Configuration
#################################################################################

load_configuration() {
    print_status "Loading deployment configuration..."
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Configuration file not found: $CONFIG_FILE"
        print_error "Cannot proceed with cleanup without deployment configuration."
        print_status "You may need to clean up resources manually using the AWS Console."
        exit 1
    fi
    
    # Source the configuration file
    source "$CONFIG_FILE"
    
    # Verify required variables are set
    REQUIRED_VARS=(
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "RANDOM_SUFFIX"
        "BUCKET_NAME"
        "STREAM_NAME"
        "FIREHOSE_NAME"
        "TABLE_NAME"
        "FUNCTION_NAME"
        "PIPE_NAME"
    )
    
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var:-}" ]; then
            print_error "Required variable $var not found in configuration"
            exit 1
        fi
    done
    
    print_success "Configuration loaded successfully"
    print_status "Cleanup will be performed in region: $AWS_REGION"
    print_status "Resources to clean up:"
    echo "  - S3 Bucket: $BUCKET_NAME"
    echo "  - DynamoDB Table: $TABLE_NAME"
    echo "  - Kinesis Stream: $STREAM_NAME"
    echo "  - Lambda Function: $FUNCTION_NAME"
    echo "  - Firehose Stream: $FIREHOSE_NAME"
    echo "  - EventBridge Pipe: $PIPE_NAME"
    echo "  - IAM Roles: *-${RANDOM_SUFFIX}"
    echo
}

#################################################################################
# Confirmation Prompt
#################################################################################

confirm_cleanup() {
    if [ "$FORCE_CLEANUP" = true ]; then
        print_warning "Force mode enabled - skipping confirmation prompts"
        return 0
    fi
    
    echo -e "${YELLOW}WARNING: This will delete ALL resources created by the deployment.${NC}"
    echo -e "${YELLOW}This action CANNOT be undone!${NC}"
    echo
    echo "Resources to be deleted:"
    echo "  - S3 bucket and ALL its contents: $BUCKET_NAME"
    echo "  - DynamoDB table and ALL data: $TABLE_NAME"
    echo "  - Kinesis Data Stream: $STREAM_NAME"
    echo "  - Lambda function: $FUNCTION_NAME"
    echo "  - Kinesis Data Firehose: $FIREHOSE_NAME"
    echo "  - EventBridge Pipe: $PIPE_NAME"
    echo "  - All associated IAM roles and policies"
    echo
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        print_status "Cleanup cancelled by user"
        exit 0
    fi
    
    print_status "Proceeding with cleanup..."
}

#################################################################################
# EventBridge Pipe Cleanup
#################################################################################

cleanup_eventbridge_pipe() {
    print_status "Cleaning up EventBridge Pipe..."
    
    # Check if pipe exists
    if aws pipes describe-pipe --name "$PIPE_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        print_status "Deleting EventBridge Pipe: $PIPE_NAME"
        
        # Stop the pipe first
        aws pipes stop-pipe --name "$PIPE_NAME" --region "$AWS_REGION" || true
        
        # Wait a moment for the pipe to stop
        sleep 10
        
        # Delete the pipe
        if aws pipes delete-pipe --name "$PIPE_NAME" --region "$AWS_REGION"; then
            print_success "EventBridge Pipe deleted successfully"
        else
            print_warning "Failed to delete EventBridge Pipe via CLI"
            print_warning "You may need to delete it manually from the AWS Console"
        fi
    else
        print_warning "EventBridge Pipe not found or already deleted"
    fi
}

#################################################################################
# Kinesis Data Firehose Cleanup
#################################################################################

cleanup_firehose() {
    print_status "Cleaning up Kinesis Data Firehose..."
    
    # Check if Firehose delivery stream exists
    if aws firehose describe-delivery-stream --delivery-stream-name "$FIREHOSE_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        print_status "Deleting Kinesis Data Firehose: $FIREHOSE_NAME"
        
        # Delete Firehose delivery stream
        aws firehose delete-delivery-stream \
            --delivery-stream-name "$FIREHOSE_NAME" \
            --allow-force-delete \
            --region "$AWS_REGION"
        
        print_success "Kinesis Data Firehose deletion initiated"
        
        # Note: Firehose deletion is asynchronous, we don't wait for completion
    else
        print_warning "Kinesis Data Firehose not found or already deleted"
    fi
    
    # Clean up Firehose IAM role
    FIREHOSE_ROLE_NAME="${FIREHOSE_ROLE_NAME:-firehose-delivery-role-${RANDOM_SUFFIX}}"
    
    if aws iam get-role --role-name "$FIREHOSE_ROLE_NAME" >/dev/null 2>&1; then
        print_status "Deleting Firehose IAM role: $FIREHOSE_ROLE_NAME"
        
        # Delete role policies
        aws iam delete-role-policy \
            --role-name "$FIREHOSE_ROLE_NAME" \
            --policy-name FirehoseDeliveryPolicy 2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "$FIREHOSE_ROLE_NAME"
        
        print_success "Firehose IAM role deleted"
    else
        print_warning "Firehose IAM role not found or already deleted"
    fi
}

#################################################################################
# EventBridge Pipes IAM Role Cleanup
#################################################################################

cleanup_pipes_role() {
    print_status "Cleaning up EventBridge Pipes IAM role..."
    
    PIPES_ROLE_NAME="${PIPES_ROLE_NAME:-pipes-execution-role-${RANDOM_SUFFIX}}"
    
    if aws iam get-role --role-name "$PIPES_ROLE_NAME" >/dev/null 2>&1; then
        print_status "Deleting Pipes IAM role: $PIPES_ROLE_NAME"
        
        # Delete role policies
        aws iam delete-role-policy \
            --role-name "$PIPES_ROLE_NAME" \
            --policy-name PipesExecutionPolicy 2>/dev/null || true
            
        aws iam delete-role-policy \
            --role-name "$PIPES_ROLE_NAME" \
            --policy-name FirehoseTargetPolicy 2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "$PIPES_ROLE_NAME"
        
        print_success "Pipes IAM role deleted"
    else
        print_warning "Pipes IAM role not found or already deleted"
    fi
}

#################################################################################
# Lambda Function Cleanup
#################################################################################

cleanup_lambda() {
    print_status "Cleaning up Lambda function..."
    
    # Delete Lambda function
    if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        print_status "Deleting Lambda function: $FUNCTION_NAME"
        
        aws lambda delete-function \
            --function-name "$FUNCTION_NAME" \
            --region "$AWS_REGION"
        
        print_success "Lambda function deleted"
    else
        print_warning "Lambda function not found or already deleted"
    fi
    
    # Clean up Lambda IAM role
    LAMBDA_ROLE_NAME="${LAMBDA_ROLE_NAME:-lambda-enrichment-role-${RANDOM_SUFFIX}}"
    
    if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" >/dev/null 2>&1; then
        print_status "Deleting Lambda IAM role: $LAMBDA_ROLE_NAME"
        
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-name DynamoDBReadPolicy 2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "$LAMBDA_ROLE_NAME"
        
        print_success "Lambda IAM role deleted"
    else
        print_warning "Lambda IAM role not found or already deleted"
    fi
}

#################################################################################
# Kinesis Data Stream Cleanup
#################################################################################

cleanup_kinesis_stream() {
    print_status "Cleaning up Kinesis Data Stream..."
    
    # Check if stream exists
    if aws kinesis describe-stream --stream-name "$STREAM_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        print_status "Deleting Kinesis Data Stream: $STREAM_NAME"
        
        aws kinesis delete-stream \
            --stream-name "$STREAM_NAME" \
            --region "$AWS_REGION"
        
        print_success "Kinesis Data Stream deletion initiated"
    else
        print_warning "Kinesis Data Stream not found or already deleted"
    fi
}

#################################################################################
# DynamoDB Table Cleanup
#################################################################################

cleanup_dynamodb() {
    print_status "Cleaning up DynamoDB table..."
    
    # Check if table exists
    if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        print_status "Deleting DynamoDB table: $TABLE_NAME"
        print_warning "This will delete all reference data in the table!"
        
        aws dynamodb delete-table \
            --table-name "$TABLE_NAME" \
            --region "$AWS_REGION"
        
        print_success "DynamoDB table deletion initiated"
    else
        print_warning "DynamoDB table not found or already deleted"
    fi
}

#################################################################################
# S3 Bucket Cleanup
#################################################################################

cleanup_s3_bucket() {
    print_status "Cleaning up S3 bucket..."
    
    # Check if bucket exists
    if aws s3 ls "s3://$BUCKET_NAME" >/dev/null 2>&1; then
        print_status "Deleting S3 bucket contents: $BUCKET_NAME"
        print_warning "This will delete ALL data in the bucket!"
        
        # Get object count for logging
        OBJECT_COUNT=$(aws s3api list-objects-v2 --bucket "$BUCKET_NAME" --query 'KeyCount' --output text 2>/dev/null || echo "0")
        
        if [ "$OBJECT_COUNT" -gt 0 ]; then
            print_status "Deleting $OBJECT_COUNT objects from S3 bucket..."
            
            # Delete all objects and versions
            aws s3 rm "s3://$BUCKET_NAME" --recursive
            
            # Delete all object versions (in case versioning was enabled)
            aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | \
            while read -r key version_id; do
                if [ -n "$key" ] && [ -n "$version_id" ]; then
                    aws s3api delete-object \
                        --bucket "$BUCKET_NAME" \
                        --key "$key" \
                        --version-id "$version_id" >/dev/null || true
                fi
            done
            
            # Delete all delete markers
            aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | \
            while read -r key version_id; do
                if [ -n "$key" ] && [ -n "$version_id" ]; then
                    aws s3api delete-object \
                        --bucket "$BUCKET_NAME" \
                        --key "$key" \
                        --version-id "$version_id" >/dev/null || true
                fi
            done
        fi
        
        # Delete the bucket
        print_status "Deleting S3 bucket: $BUCKET_NAME"
        aws s3 rb "s3://$BUCKET_NAME" --force
        
        print_success "S3 bucket deleted successfully"
    else
        print_warning "S3 bucket not found or already deleted"
    fi
}

#################################################################################
# CloudWatch Logs Cleanup
#################################################################################

cleanup_cloudwatch_logs() {
    print_status "Cleaning up CloudWatch log groups..."
    
    # Lambda function log group
    LAMBDA_LOG_GROUP="/aws/lambda/$FUNCTION_NAME"
    if aws logs describe-log-groups --log-group-name-prefix "$LAMBDA_LOG_GROUP" --region "$AWS_REGION" | grep -q "$LAMBDA_LOG_GROUP"; then
        print_status "Deleting Lambda log group: $LAMBDA_LOG_GROUP"
        aws logs delete-log-group --log-group-name "$LAMBDA_LOG_GROUP" --region "$AWS_REGION" || true
    fi
    
    # Firehose log group
    FIREHOSE_LOG_GROUP="/aws/kinesisfirehose/$FIREHOSE_NAME"
    if aws logs describe-log-groups --log-group-name-prefix "$FIREHOSE_LOG_GROUP" --region "$AWS_REGION" | grep -q "$FIREHOSE_LOG_GROUP"; then
        print_status "Deleting Firehose log group: $FIREHOSE_LOG_GROUP"
        aws logs delete-log-group --log-group-name "$FIREHOSE_LOG_GROUP" --region "$AWS_REGION" || true
    fi
    
    print_success "CloudWatch log groups cleanup completed"
}

#################################################################################
# Cleanup Temporary Files
#################################################################################

cleanup_local_files() {
    print_status "Cleaning up local temporary files..."
    
    # Remove temporary files that might have been created
    FILES_TO_REMOVE=(
        "$PROJECT_ROOT/lambda_function.py"
        "$PROJECT_ROOT/function.zip"
        "$PROJECT_ROOT/pipe-config.json"
        "$PROJECT_ROOT/sample-enriched.gz"
        "$CONFIG_FILE"
    )
    
    for file in "${FILES_TO_REMOVE[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            print_status "Removed: $file"
        fi
    done
    
    print_success "Local files cleanup completed"
}

#################################################################################
# Verify Cleanup
#################################################################################

verify_cleanup() {
    print_status "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check S3 bucket
    if aws s3 ls "s3://$BUCKET_NAME" >/dev/null 2>&1; then
        print_warning "S3 bucket still exists: $BUCKET_NAME"
        ((cleanup_issues++))
    fi
    
    # Check DynamoDB table
    if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        print_warning "DynamoDB table still exists: $TABLE_NAME"
        ((cleanup_issues++))
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        print_warning "Lambda function still exists: $FUNCTION_NAME"
        ((cleanup_issues++))
    fi
    
    # Check Kinesis stream
    if aws kinesis describe-stream --stream-name "$STREAM_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        print_warning "Kinesis stream still exists: $STREAM_NAME"
        ((cleanup_issues++))
    fi
    
    # Check Firehose delivery stream
    if aws firehose describe-delivery-stream --delivery-stream-name "$FIREHOSE_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
        print_warning "Firehose delivery stream still exists: $FIREHOSE_NAME"
        ((cleanup_issues++))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        print_success "Cleanup verification passed - all resources removed"
    else
        print_warning "Cleanup verification found $cleanup_issues remaining resources"
        print_warning "Some resources may take time to delete or require manual removal"
    fi
}

#################################################################################
# Cost Estimation
#################################################################################

estimate_saved_costs() {
    print_status "Estimating cost savings from cleanup..."
    
    echo "Approximate monthly costs avoided:"
    echo "  - S3 storage: ~\$0.023 per GB (varies by storage class)"
    echo "  - DynamoDB on-demand: ~\$1.25 per million read/write requests"
    echo "  - Kinesis Data Streams: ~\$0.015 per shard hour"
    echo "  - Lambda: ~\$0.20 per million requests + compute time"
    echo "  - Kinesis Data Firehose: ~\$0.029 per GB ingested"
    echo
    print_status "Note: Actual costs depend on usage patterns and data volume"
}

#################################################################################
# Main Cleanup Function
#################################################################################

main() {
    echo "=========================================="
    echo "Real-Time Stream Enrichment Cleanup"
    echo "=========================================="
    echo
    
    # Initialize log file
    log "Starting cleanup at $(date)"
    
    # Load configuration and confirm
    load_configuration
    confirm_cleanup
    
    echo
    print_status "Beginning cleanup process..."
    echo
    
    # Cleanup resources in reverse order of creation
    # This helps avoid dependency issues
    cleanup_eventbridge_pipe
    cleanup_firehose
    cleanup_pipes_role
    cleanup_lambda
    cleanup_kinesis_stream
    cleanup_dynamodb
    cleanup_s3_bucket
    cleanup_cloudwatch_logs
    cleanup_local_files
    
    # Verify cleanup
    echo
    verify_cleanup
    
    # Show cost savings
    echo
    estimate_saved_costs
    
    echo
    echo "=========================================="
    echo "Cleanup Completed Successfully!"
    echo "=========================================="
    echo
    print_success "All resources have been deleted"
    print_status "Cleanup logs saved to: $LOG_FILE"
    echo
    print_status "If you see any warnings above, you may need to:"
    print_status "1. Wait a few minutes for asynchronous deletions to complete"
    print_status "2. Check the AWS Console for any remaining resources"
    print_status "3. Manually delete any remaining resources if needed"
    echo
    print_success "Thank you for using the Real-Time Stream Enrichment solution!"
    
    log "Cleanup completed successfully at $(date)"
}

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install AWS CLI v2."
    exit 1
fi

# Run main function
main "$@"