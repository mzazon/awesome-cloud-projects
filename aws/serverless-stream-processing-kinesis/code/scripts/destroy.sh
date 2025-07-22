#!/bin/bash

# Real-time Data Processing with Kinesis and Lambda - Cleanup Script
# This script safely removes all resources created by the deployment

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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

# Global variables
FORCE_DELETE=false
SKIP_CONFIRMATION=false

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            --yes|-y)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "OPTIONS:"
    echo "  --force    Force deletion without confirmation prompts"
    echo "  --yes, -y  Skip confirmation prompts"
    echo "  --help, -h Show this help message"
    echo
    echo "EXAMPLES:"
    echo "  $0                    # Interactive cleanup with confirmations"
    echo "  $0 --yes            # Skip confirmations but show what's being deleted"
    echo "  $0 --force          # Force delete everything without prompts"
}

# Function to check if AWS CLI is configured
check_aws_config() {
    log_info "Checking AWS CLI configuration..."
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or credentials are invalid"
        log_error "Please run 'aws configure' or set AWS environment variables"
        exit 1
    fi
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region || echo "us-east-1")
    
    log_success "AWS CLI configured for account: $AWS_ACCOUNT_ID in region: $AWS_REGION"
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [ -f .env_vars ]; then
        source .env_vars
        log_success "Environment variables loaded from .env_vars"
    else
        log_warning "No .env_vars file found. Using default/manual values."
        
        # Prompt for resource names if not found
        if [ "$SKIP_CONFIRMATION" = false ]; then
            read -p "Enter Kinesis Stream Name (or press Enter to skip): " STREAM_NAME
            read -p "Enter Lambda Function Name (or press Enter to skip): " LAMBDA_FUNCTION_NAME
            read -p "Enter S3 Bucket Name (or press Enter to skip): " S3_BUCKET_NAME
            read -p "Enter IAM Role Name (or press Enter to skip): " IAM_ROLE_NAME
        fi
    fi
    
    # Display what will be deleted
    log_info "Resources to be deleted:"
    [ -n "${STREAM_NAME:-}" ] && log_info "  Kinesis Stream: $STREAM_NAME"
    [ -n "${LAMBDA_FUNCTION_NAME:-}" ] && log_info "  Lambda Function: $LAMBDA_FUNCTION_NAME"
    [ -n "${S3_BUCKET_NAME:-}" ] && log_info "  S3 Bucket: $S3_BUCKET_NAME"
    [ -n "${IAM_ROLE_NAME:-}" ] && log_info "  IAM Role: $IAM_ROLE_NAME"
    [ -n "${EVENT_SOURCE_UUID:-}" ] && log_info "  Event Source Mapping: $EVENT_SOURCE_UUID"
}

# Function to confirm deletion
confirm_deletion() {
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return 0
    fi
    
    echo
    log_warning "This will permanently delete all resources listed above!"
    log_warning "This action cannot be undone."
    echo
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to delete event source mapping
delete_event_source_mapping() {
    if [ -z "${LAMBDA_FUNCTION_NAME:-}" ]; then
        log_warning "Lambda function name not provided, skipping event source mapping deletion"
        return 0
    fi
    
    log_info "Deleting event source mapping..."
    
    # Get event source mapping UUID if not already known
    if [ -z "${EVENT_SOURCE_UUID:-}" ]; then
        EVENT_SOURCE_UUID=$(aws lambda list-event-source-mappings \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --query 'EventSourceMappings[0].UUID' \
            --output text 2>/dev/null || echo "")
    fi
    
    if [ -n "$EVENT_SOURCE_UUID" ] && [ "$EVENT_SOURCE_UUID" != "None" ] && [ "$EVENT_SOURCE_UUID" != "null" ]; then
        aws lambda delete-event-source-mapping --uuid "$EVENT_SOURCE_UUID" || {
            log_warning "Failed to delete event source mapping $EVENT_SOURCE_UUID"
        }
        log_success "Event source mapping deleted: $EVENT_SOURCE_UUID"
    else
        log_warning "No event source mapping found for Lambda function: $LAMBDA_FUNCTION_NAME"
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    if [ -z "${LAMBDA_FUNCTION_NAME:-}" ]; then
        log_warning "Lambda function name not provided, skipping Lambda deletion"
        return 0
    fi
    
    log_info "Deleting Lambda function: $LAMBDA_FUNCTION_NAME"
    
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
        log_success "Lambda function deleted: $LAMBDA_FUNCTION_NAME"
    else
        log_warning "Lambda function not found: $LAMBDA_FUNCTION_NAME"
    fi
}

# Function to delete Kinesis stream
delete_kinesis_stream() {
    if [ -z "${STREAM_NAME:-}" ]; then
        log_warning "Kinesis stream name not provided, skipping stream deletion"
        return 0
    fi
    
    log_info "Deleting Kinesis stream: $STREAM_NAME"
    
    if aws kinesis describe-stream --stream-name "$STREAM_NAME" >/dev/null 2>&1; then
        aws kinesis delete-stream --stream-name "$STREAM_NAME"
        log_success "Kinesis stream deletion initiated: $STREAM_NAME"
        log_info "Stream will be fully deleted in a few minutes"
    else
        log_warning "Kinesis stream not found: $STREAM_NAME"
    fi
}

# Function to delete IAM role and detach policies
delete_iam_role() {
    if [ -z "${IAM_ROLE_NAME:-}" ]; then
        log_warning "IAM role name not provided, skipping role deletion"
        return 0
    fi
    
    log_info "Deleting IAM role and detaching policies: $IAM_ROLE_NAME"
    
    if aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
        # Detach managed policies
        local policies=(
            "arn:aws:iam::aws:policy/AWSLambdaKinesisExecutionRole"
            "arn:aws:iam::aws:policy/AmazonS3FullAccess"
        )
        
        for policy in "${policies[@]}"; do
            aws iam detach-role-policy \
                --role-name "$IAM_ROLE_NAME" \
                --policy-arn "$policy" 2>/dev/null || {
                log_warning "Failed to detach policy: $policy"
            }
        done
        
        # Delete the role
        aws iam delete-role --role-name "$IAM_ROLE_NAME"
        log_success "IAM role deleted: $IAM_ROLE_NAME"
    else
        log_warning "IAM role not found: $IAM_ROLE_NAME"
    fi
}

# Function to delete S3 bucket and contents
delete_s3_bucket() {
    if [ -z "${S3_BUCKET_NAME:-}" ]; then
        log_warning "S3 bucket name not provided, skipping bucket deletion"
        return 0
    fi
    
    log_info "Deleting S3 bucket and contents: $S3_BUCKET_NAME"
    
    if aws s3 ls "s3://$S3_BUCKET_NAME" >/dev/null 2>&1; then
        # Check if bucket has objects
        object_count=$(aws s3api list-objects-v2 --bucket "$S3_BUCKET_NAME" --query 'KeyCount' --output text 2>/dev/null || echo "0")
        
        if [ "$object_count" -gt 0 ]; then
            log_info "Deleting $object_count objects from bucket..."
            aws s3 rm "s3://$S3_BUCKET_NAME" --recursive
        fi
        
        # Delete the bucket
        aws s3 rb "s3://$S3_BUCKET_NAME"
        log_success "S3 bucket deleted: $S3_BUCKET_NAME"
    else
        log_warning "S3 bucket not found: $S3_BUCKET_NAME"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_delete=(
        "lambda-function.zip"
        "lambda_function.py"
        "data_generator.py"
        "trust-policy.json"
        ".env_vars"
    )
    
    for file in "${files_to_delete[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_info "Deleted local file: $file"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local errors=0
    
    # Check Kinesis stream
    if [ -n "${STREAM_NAME:-}" ]; then
        if aws kinesis describe-stream --stream-name "$STREAM_NAME" >/dev/null 2>&1; then
            local status=$(aws kinesis describe-stream --stream-name "$STREAM_NAME" --query 'StreamDescription.StreamStatus' --output text)
            if [ "$status" = "DELETING" ]; then
                log_info "Kinesis stream is being deleted: $STREAM_NAME"
            else
                log_warning "Kinesis stream still exists: $STREAM_NAME (Status: $status)"
                ((errors++))
            fi
        else
            log_success "Kinesis stream deleted: $STREAM_NAME"
        fi
    fi
    
    # Check Lambda function
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" >/dev/null 2>&1; then
            log_warning "Lambda function still exists: $LAMBDA_FUNCTION_NAME"
            ((errors++))
        else
            log_success "Lambda function deleted: $LAMBDA_FUNCTION_NAME"
        fi
    fi
    
    # Check S3 bucket
    if [ -n "${S3_BUCKET_NAME:-}" ]; then
        if aws s3 ls "s3://$S3_BUCKET_NAME" >/dev/null 2>&1; then
            log_warning "S3 bucket still exists: $S3_BUCKET_NAME"
            ((errors++))
        else
            log_success "S3 bucket deleted: $S3_BUCKET_NAME"
        fi
    fi
    
    # Check IAM role
    if [ -n "${IAM_ROLE_NAME:-}" ]; then
        if aws iam get-role --role-name "$IAM_ROLE_NAME" >/dev/null 2>&1; then
            log_warning "IAM role still exists: $IAM_ROLE_NAME"
            ((errors++))
        else
            log_success "IAM role deleted: $IAM_ROLE_NAME"
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "All resources successfully deleted"
    else
        log_warning "$errors resources may still exist or are being deleted"
    fi
}

# Function to display cleanup summary
display_summary() {
    echo
    echo "=== CLEANUP SUMMARY ==="
    
    if [ -n "${STREAM_NAME:-}" ]; then
        echo "✓ Kinesis Stream: $STREAM_NAME"
    fi
    
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        echo "✓ Lambda Function: $LAMBDA_FUNCTION_NAME"
    fi
    
    if [ -n "${S3_BUCKET_NAME:-}" ]; then
        echo "✓ S3 Bucket: $S3_BUCKET_NAME"
    fi
    
    if [ -n "${IAM_ROLE_NAME:-}" ]; then
        echo "✓ IAM Role: $IAM_ROLE_NAME"
    fi
    
    echo "✓ Local files cleaned up"
    echo
    log_success "Cleanup completed successfully!"
    
    if [ "$FORCE_DELETE" = false ]; then
        echo
        log_info "Note: Some resources (like Kinesis streams) may take a few minutes to be fully deleted."
        log_info "You can verify deletion in the AWS Console or by running AWS CLI commands."
    fi
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    log_error "An error occurred during cleanup"
    log_info "Some resources may not have been deleted"
    log_info "You may need to clean them up manually through the AWS Console"
    
    if [ -f .env_vars ]; then
        log_info "Resource details are saved in .env_vars file for manual cleanup"
    fi
    
    exit 1
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Real-time Data Processing with Kinesis and Lambda"
    echo
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Set trap for error handling
    trap handle_cleanup_error ERR
    
    # Run cleanup steps
    check_aws_config
    load_environment
    confirm_deletion
    
    echo
    log_info "Beginning resource deletion..."
    
    # Delete resources in reverse order of creation
    delete_event_source_mapping
    delete_lambda_function
    delete_kinesis_stream
    delete_iam_role
    delete_s3_bucket
    cleanup_local_files
    
    # Verify deletion
    echo
    verify_deletion
    display_summary
    
    # Clear the error trap
    trap - ERR
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi