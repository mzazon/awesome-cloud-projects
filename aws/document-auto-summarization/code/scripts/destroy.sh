#!/bin/bash

# Destroy script for Intelligent Document Summarization with Amazon Bedrock and Lambda
# This script safely removes all AWS resources created by the deployment

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
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
    
    success "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Check if .env file exists
    if [ -f ".env" ]; then
        source .env
        log "Loaded environment from .env file"
        log "  AWS Region: ${AWS_REGION}"
        log "  Input Bucket: ${INPUT_BUCKET}"
        log "  Output Bucket: ${OUTPUT_BUCKET}"
        log "  Lambda Function: ${LAMBDA_FUNCTION_NAME}"
        log "  IAM Role: ${IAM_ROLE_NAME}"
        success "Environment variables loaded"
    else
        warning ".env file not found. Please provide resource names manually."
        
        # Prompt for manual input
        read -p "Enter Input Bucket name (or press Enter to skip): " INPUT_BUCKET
        read -p "Enter Output Bucket name (or press Enter to skip): " OUTPUT_BUCKET
        read -p "Enter Lambda Function name (or press Enter to skip): " LAMBDA_FUNCTION_NAME
        read -p "Enter IAM Role name (or press Enter to skip): " IAM_ROLE_NAME
        
        # Set AWS region if not already set
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            warning "No region configured, using default: us-east-1"
        fi
        
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    fi
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo "=================================================================="
    echo "                    ⚠️  DESTRUCTION WARNING  ⚠️                   "
    echo "=================================================================="
    echo ""
    echo "This script will PERMANENTLY DELETE the following resources:"
    echo ""
    
    if [ -n "$INPUT_BUCKET" ]; then
        echo "  • S3 Bucket: ${INPUT_BUCKET} (and all contents)"
    fi
    
    if [ -n "$OUTPUT_BUCKET" ]; then
        echo "  • S3 Bucket: ${OUTPUT_BUCKET} (and all contents)"
    fi
    
    if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
        echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    fi
    
    if [ -n "$IAM_ROLE_NAME" ]; then
        echo "  • IAM Role: ${IAM_ROLE_NAME}"
    fi
    
    echo "  • CloudWatch Log Groups"
    echo "  • All associated configurations and data"
    echo ""
    echo "=================================================================="
    echo ""
    
    # Require explicit confirmation
    read -p "Type 'DELETE' to confirm destruction (case-sensitive): " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Function to remove S3 bucket notification
remove_s3_notification() {
    if [ -n "$INPUT_BUCKET" ]; then
        log "Removing S3 bucket notification configuration..."
        
        if aws s3api head-bucket --bucket "$INPUT_BUCKET" &>/dev/null; then
            # Remove bucket notification
            aws s3api put-bucket-notification-configuration \
                --bucket "$INPUT_BUCKET" \
                --notification-configuration '{}' \
                2>/dev/null || warning "Could not remove notification configuration"
            
            success "S3 notification configuration removed"
        else
            warning "Input bucket $INPUT_BUCKET not found or not accessible"
        fi
    fi
}

# Function to remove Lambda permissions
remove_lambda_permissions() {
    if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
        log "Removing Lambda function permissions..."
        
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
            # Remove S3 invoke permission
            aws lambda remove-permission \
                --function-name "$LAMBDA_FUNCTION_NAME" \
                --statement-id s3-trigger \
                2>/dev/null || warning "Could not remove S3 permission"
            
            success "Lambda permissions removed"
        else
            warning "Lambda function $LAMBDA_FUNCTION_NAME not found"
        fi
    fi
}

# Function to delete Lambda function
delete_lambda_function() {
    if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
        log "Deleting Lambda function: $LAMBDA_FUNCTION_NAME"
        
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
            aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
            success "Lambda function deleted"
        else
            warning "Lambda function $LAMBDA_FUNCTION_NAME not found"
        fi
    fi
}

# Function to delete IAM role
delete_iam_role() {
    if [ -n "$IAM_ROLE_NAME" ]; then
        log "Deleting IAM role: $IAM_ROLE_NAME"
        
        if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
            # Remove inline policies first
            POLICIES=$(aws iam list-role-policies --role-name "$IAM_ROLE_NAME" \
                --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
            
            for policy in $POLICIES; do
                if [ -n "$policy" ]; then
                    aws iam delete-role-policy \
                        --role-name "$IAM_ROLE_NAME" \
                        --policy-name "$policy"
                    log "Deleted inline policy: $policy"
                fi
            done
            
            # Remove attached managed policies
            ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$IAM_ROLE_NAME" \
                --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            
            for policy_arn in $ATTACHED_POLICIES; do
                if [ -n "$policy_arn" ]; then
                    aws iam detach-role-policy \
                        --role-name "$IAM_ROLE_NAME" \
                        --policy-arn "$policy_arn"
                    log "Detached managed policy: $policy_arn"
                fi
            done
            
            # Delete the role
            aws iam delete-role --role-name "$IAM_ROLE_NAME"
            success "IAM role deleted"
        else
            warning "IAM role $IAM_ROLE_NAME not found"
        fi
    fi
}

# Function to empty and delete S3 buckets
delete_s3_buckets() {
    # Delete input bucket
    if [ -n "$INPUT_BUCKET" ]; then
        log "Deleting S3 input bucket: $INPUT_BUCKET"
        
        if aws s3api head-bucket --bucket "$INPUT_BUCKET" &>/dev/null; then
            # Empty bucket first (including versions and delete markers)
            aws s3 rm "s3://$INPUT_BUCKET" --recursive 2>/dev/null || true
            
            # Remove all versions if versioning is enabled
            aws s3api list-object-versions --bucket "$INPUT_BUCKET" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | while read key version; do
                if [ -n "$key" ] && [ -n "$version" ]; then
                    aws s3api delete-object --bucket "$INPUT_BUCKET" \
                        --key "$key" --version-id "$version" 2>/dev/null || true
                fi
            done
            
            # Remove delete markers
            aws s3api list-object-versions --bucket "$INPUT_BUCKET" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | while read key version; do
                if [ -n "$key" ] && [ -n "$version" ]; then
                    aws s3api delete-object --bucket "$INPUT_BUCKET" \
                        --key "$key" --version-id "$version" 2>/dev/null || true
                fi
            done
            
            # Delete bucket
            aws s3 rb "s3://$INPUT_BUCKET" --force
            success "Input bucket deleted"
        else
            warning "Input bucket $INPUT_BUCKET not found"
        fi
    fi
    
    # Delete output bucket
    if [ -n "$OUTPUT_BUCKET" ]; then
        log "Deleting S3 output bucket: $OUTPUT_BUCKET"
        
        if aws s3api head-bucket --bucket "$OUTPUT_BUCKET" &>/dev/null; then
            # Empty bucket first (including versions and delete markers)
            aws s3 rm "s3://$OUTPUT_BUCKET" --recursive 2>/dev/null || true
            
            # Remove all versions if versioning is enabled
            aws s3api list-object-versions --bucket "$OUTPUT_BUCKET" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | while read key version; do
                if [ -n "$key" ] && [ -n "$version" ]; then
                    aws s3api delete-object --bucket "$OUTPUT_BUCKET" \
                        --key "$key" --version-id "$version" 2>/dev/null || true
                fi
            done
            
            # Remove delete markers
            aws s3api list-object-versions --bucket "$OUTPUT_BUCKET" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
                --output text 2>/dev/null | while read key version; do
                if [ -n "$key" ] && [ -n "$version" ]; then
                    aws s3api delete-object --bucket "$OUTPUT_BUCKET" \
                        --key "$key" --version-id "$version" 2>/dev/null || true
                fi
            done
            
            # Delete bucket
            aws s3 rb "s3://$OUTPUT_BUCKET" --force
            success "Output bucket deleted"
        else
            warning "Output bucket $OUTPUT_BUCKET not found"
        fi
    fi
}

# Function to delete CloudWatch log groups
delete_cloudwatch_logs() {
    if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
        log "Deleting CloudWatch log groups..."
        
        LOG_GROUP_NAME="/aws/lambda/$LAMBDA_FUNCTION_NAME"
        
        if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" \
            --query 'logGroups[].logGroupName' --output text | grep -q "$LOG_GROUP_NAME"; then
            
            aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME"
            success "CloudWatch log group deleted"
        else
            warning "CloudWatch log group $LOG_GROUP_NAME not found"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment artifacts
    rm -f lambda-trust-policy.json
    rm -f lambda-permissions-policy.json
    rm -f s3-notification-config.json
    rm -f test-document.txt
    rm -f summary.txt
    rm -f *.zip
    rm -rf doc-summarizer-*
    
    # Ask user if they want to remove .env file
    if [ -f ".env" ]; then
        read -p "Remove .env file? (y/N): " remove_env
        if [[ "$remove_env" =~ ^[Yy]$ ]]; then
            rm -f .env
            success "Environment file removed"
        else
            log "Environment file preserved"
        fi
    fi
    
    success "Local files cleaned up"
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    REMAINING_RESOURCES=()
    
    # Check Lambda function
    if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
        if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
            REMAINING_RESOURCES+=("Lambda function: $LAMBDA_FUNCTION_NAME")
        fi
    fi
    
    # Check IAM role
    if [ -n "$IAM_ROLE_NAME" ]; then
        if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
            REMAINING_RESOURCES+=("IAM role: $IAM_ROLE_NAME")
        fi
    fi
    
    # Check S3 buckets
    if [ -n "$INPUT_BUCKET" ]; then
        if aws s3api head-bucket --bucket "$INPUT_BUCKET" &>/dev/null; then
            REMAINING_RESOURCES+=("S3 bucket: $INPUT_BUCKET")
        fi
    fi
    
    if [ -n "$OUTPUT_BUCKET" ]; then
        if aws s3api head-bucket --bucket "$OUTPUT_BUCKET" &>/dev/null; then
            REMAINING_RESOURCES+=("S3 bucket: $OUTPUT_BUCKET")
        fi
    fi
    
    # Report results
    if [ ${#REMAINING_RESOURCES[@]} -eq 0 ]; then
        success "All resources successfully deleted"
    else
        warning "Some resources may still exist:"
        for resource in "${REMAINING_RESOURCES[@]}"; do
            echo "  • $resource"
        done
        warning "Please check and manually delete remaining resources if needed"
    fi
}

# Function to display destruction summary
display_summary() {
    echo ""
    echo "=================================================================="
    echo "                   DESTRUCTION COMPLETED                         "
    echo "=================================================================="
    echo ""
    echo "The following resources have been removed:"
    echo ""
    
    if [ -n "$INPUT_BUCKET" ]; then
        echo "  ✅ S3 Input Bucket: ${INPUT_BUCKET}"
    fi
    
    if [ -n "$OUTPUT_BUCKET" ]; then
        echo "  ✅ S3 Output Bucket: ${OUTPUT_BUCKET}"
    fi
    
    if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
        echo "  ✅ Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    fi
    
    if [ -n "$IAM_ROLE_NAME" ]; then
        echo "  ✅ IAM Role: ${IAM_ROLE_NAME}"
    fi
    
    echo "  ✅ CloudWatch Log Groups"
    echo "  ✅ S3 Event Notifications"
    echo "  ✅ Lambda Permissions"
    echo ""
    echo "All AWS resources for the Intelligent Document Summarization"
    echo "system have been successfully removed."
    echo ""
    echo "=================================================================="
}

# Error handling function
handle_error() {
    error "An error occurred during destruction process"
    warning "Some resources may not have been deleted"
    warning "Please check your AWS console and manually remove any remaining resources"
    exit 1
}

# Dry run function
dry_run() {
    echo ""
    echo "=================================================================="
    echo "                      DRY RUN MODE                               "
    echo "=================================================================="
    echo ""
    echo "The following resources would be deleted:"
    echo ""
    
    if [ -n "$INPUT_BUCKET" ]; then
        echo "  • S3 Bucket: ${INPUT_BUCKET}"
    fi
    
    if [ -n "$OUTPUT_BUCKET" ]; then
        echo "  • S3 Bucket: ${OUTPUT_BUCKET}"
    fi
    
    if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
        echo "  • Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    fi
    
    if [ -n "$IAM_ROLE_NAME" ]; then
        echo "  • IAM Role: ${IAM_ROLE_NAME}"
    fi
    
    echo "  • CloudWatch Log Groups"
    echo "  • S3 Event Notifications"
    echo "  • Lambda Permissions"
    echo ""
    echo "To perform actual deletion, run: ./destroy.sh"
    echo ""
    echo "=================================================================="
}

# Main destruction function
main() {
    log "Starting destruction of Intelligent Document Summarization system..."
    
    # Check for dry run mode
    if [[ "$1" == "--dry-run" ]]; then
        check_prerequisites
        load_environment
        dry_run
        exit 0
    fi
    
    # Set trap for error handling
    trap handle_error ERR
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    # Remove resources in proper order (reverse of creation)
    remove_s3_notification
    remove_lambda_permissions
    delete_lambda_function
    delete_iam_role
    delete_s3_buckets
    delete_cloudwatch_logs
    cleanup_local_files
    verify_deletion
    
    display_summary
    success "Destruction completed successfully!"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --dry-run    Show what would be deleted without actually deleting"
        echo "  --help, -h   Show this help message"
        echo ""
        echo "This script will destroy all AWS resources created by the"
        echo "Intelligent Document Summarization deployment."
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac