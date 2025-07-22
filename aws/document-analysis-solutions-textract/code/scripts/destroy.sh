#!/bin/bash

# AWS Textract Document Analysis Solution - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
DEPLOYMENT_VARS_FILE="${SCRIPT_DIR}/deployment-vars.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Status output functions
info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Load deployment variables
load_deployment_vars() {
    if [[ -f "$DEPLOYMENT_VARS_FILE" ]]; then
        info "Loading deployment variables from $DEPLOYMENT_VARS_FILE"
        source "$DEPLOYMENT_VARS_FILE"
        success "Deployment variables loaded successfully"
    else
        error "Deployment variables file not found: $DEPLOYMENT_VARS_FILE"
        error "This script requires the deployment variables file created by deploy.sh"
        info "You can manually set the following variables and run the script again:"
        info "export AWS_REGION=<your-region>"
        info "export AWS_ACCOUNT_ID=<your-account-id>"
        info "export BUCKET_INPUT=<input-bucket-name>"
        info "export BUCKET_OUTPUT=<output-bucket-name>"
        info "export LAMBDA_FUNCTION=<lambda-function-name>"
        info "export SNS_TOPIC=<sns-topic-name>"
        info "export IAM_ROLE=<iam-role-name>"
        info "export RANDOM_SUFFIX=<random-suffix>"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Verify we're in the correct AWS account
    local current_account=$(aws sts get-caller-identity --query Account --output text)
    if [[ "$current_account" != "$AWS_ACCOUNT_ID" ]]; then
        error "Current AWS account ($current_account) doesn't match deployment account ($AWS_ACCOUNT_ID)"
        exit 1
    fi
    
    # Verify we're in the correct region
    local current_region=$(aws configure get region)
    if [[ "$current_region" != "$AWS_REGION" ]]; then
        error "Current AWS region ($current_region) doesn't match deployment region ($AWS_REGION)"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Confirmation prompt
confirm_deletion() {
    info "This will delete the following resources:"
    info "  - Lambda Function: ${LAMBDA_FUNCTION}"
    info "  - S3 Bucket: ${BUCKET_INPUT} (and all contents)"
    info "  - S3 Bucket: ${BUCKET_OUTPUT} (and all contents)"
    info "  - SNS Topic: ${SNS_TOPIC}"
    info "  - IAM Role: ${IAM_ROLE}"
    info "  - All associated policies and permissions"
    info ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    info "Proceeding with cleanup..."
}

# Remove Lambda function and permissions
remove_lambda_function() {
    info "Removing Lambda function and permissions..."
    
    # Check if Lambda function exists
    if aws lambda get-function --function-name ${LAMBDA_FUNCTION} &>/dev/null; then
        # Remove Lambda permission for S3
        aws lambda remove-permission \
            --function-name ${LAMBDA_FUNCTION} \
            --statement-id s3-invoke-permission-${RANDOM_SUFFIX} 2>/dev/null || true
        
        # Delete Lambda function
        aws lambda delete-function --function-name ${LAMBDA_FUNCTION}
        success "Lambda function deleted: ${LAMBDA_FUNCTION}"
    else
        warning "Lambda function ${LAMBDA_FUNCTION} not found"
    fi
}

# Remove S3 event notifications
remove_s3_notifications() {
    info "Removing S3 event notifications..."
    
    # Check if input bucket exists
    if aws s3api head-bucket --bucket ${BUCKET_INPUT} &>/dev/null; then
        # Remove notification configuration
        aws s3api put-bucket-notification-configuration \
            --bucket ${BUCKET_INPUT} \
            --notification-configuration '{}' 2>/dev/null || true
        success "S3 event notifications removed from ${BUCKET_INPUT}"
    else
        warning "Input bucket ${BUCKET_INPUT} not found"
    fi
}

# Remove S3 buckets and contents
remove_s3_buckets() {
    info "Removing S3 buckets and contents..."
    
    # Remove input bucket
    if aws s3api head-bucket --bucket ${BUCKET_INPUT} &>/dev/null; then
        info "Emptying input bucket: ${BUCKET_INPUT}"
        aws s3 rm s3://${BUCKET_INPUT} --recursive 2>/dev/null || true
        
        info "Deleting input bucket: ${BUCKET_INPUT}"
        aws s3 rb s3://${BUCKET_INPUT} 2>/dev/null || true
        success "Input bucket deleted: ${BUCKET_INPUT}"
    else
        warning "Input bucket ${BUCKET_INPUT} not found"
    fi
    
    # Remove output bucket
    if aws s3api head-bucket --bucket ${BUCKET_OUTPUT} &>/dev/null; then
        info "Emptying output bucket: ${BUCKET_OUTPUT}"
        aws s3 rm s3://${BUCKET_OUTPUT} --recursive 2>/dev/null || true
        
        info "Deleting output bucket: ${BUCKET_OUTPUT}"
        aws s3 rb s3://${BUCKET_OUTPUT} 2>/dev/null || true
        success "Output bucket deleted: ${BUCKET_OUTPUT}"
    else
        warning "Output bucket ${BUCKET_OUTPUT} not found"
    fi
}

# Remove SNS topic
remove_sns_topic() {
    info "Removing SNS topic..."
    
    local sns_topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC}"
    
    # Check if SNS topic exists
    if aws sns get-topic-attributes --topic-arn ${sns_topic_arn} &>/dev/null; then
        # Delete SNS topic
        aws sns delete-topic --topic-arn ${sns_topic_arn}
        success "SNS topic deleted: ${SNS_TOPIC}"
    else
        warning "SNS topic ${SNS_TOPIC} not found"
    fi
}

# Remove IAM role and policies
remove_iam_role() {
    info "Removing IAM role and policies..."
    
    # Check if IAM role exists
    if aws iam get-role --role-name ${IAM_ROLE} &>/dev/null; then
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name ${IAM_ROLE} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        aws iam detach-role-policy \
            --role-name ${IAM_ROLE} \
            --policy-arn arn:aws:iam::aws:policy/AmazonTextractFullAccess 2>/dev/null || true
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name ${IAM_ROLE} \
            --policy-name CustomTextractPolicy 2>/dev/null || true
        
        # Delete IAM role
        aws iam delete-role --role-name ${IAM_ROLE}
        success "IAM role deleted: ${IAM_ROLE}"
    else
        warning "IAM role ${IAM_ROLE} not found"
    fi
}

# Remove CloudWatch logs
remove_cloudwatch_logs() {
    info "Removing CloudWatch log groups..."
    
    local log_group_name="/aws/lambda/${LAMBDA_FUNCTION}"
    
    # Check if log group exists
    if aws logs describe-log-groups --log-group-name-prefix ${log_group_name} --query 'logGroups[0].logGroupName' --output text | grep -q "${log_group_name}"; then
        aws logs delete-log-group --log-group-name ${log_group_name}
        success "CloudWatch log group deleted: ${log_group_name}"
    else
        warning "CloudWatch log group ${log_group_name} not found"
    fi
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove deployment variables file
    if [[ -f "$DEPLOYMENT_VARS_FILE" ]]; then
        rm -f "$DEPLOYMENT_VARS_FILE"
        success "Deployment variables file removed"
    fi
    
    # Remove any remaining temporary files
    rm -f "${SCRIPT_DIR}/trust-policy.json"
    rm -f "${SCRIPT_DIR}/lambda-policy.json"
    rm -f "${SCRIPT_DIR}/notification-config.json"
    rm -f "${SCRIPT_DIR}/textract_processor.py"
    rm -f "${SCRIPT_DIR}/textract_processor.zip"
    rm -f "${SCRIPT_DIR}/test-document.txt"
    
    success "Local files cleaned up"
}

# Validate cleanup
validate_cleanup() {
    info "Validating cleanup..."
    
    local cleanup_errors=0
    
    # Check Lambda function
    if aws lambda get-function --function-name ${LAMBDA_FUNCTION} &>/dev/null; then
        error "Lambda function still exists: ${LAMBDA_FUNCTION}"
        cleanup_errors=$((cleanup_errors + 1))
    else
        success "Lambda function successfully removed"
    fi
    
    # Check S3 buckets
    if aws s3api head-bucket --bucket ${BUCKET_INPUT} &>/dev/null; then
        error "Input bucket still exists: ${BUCKET_INPUT}"
        cleanup_errors=$((cleanup_errors + 1))
    else
        success "Input bucket successfully removed"
    fi
    
    if aws s3api head-bucket --bucket ${BUCKET_OUTPUT} &>/dev/null; then
        error "Output bucket still exists: ${BUCKET_OUTPUT}"
        cleanup_errors=$((cleanup_errors + 1))
    else
        success "Output bucket successfully removed"
    fi
    
    # Check SNS topic
    local sns_topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC}"
    if aws sns get-topic-attributes --topic-arn ${sns_topic_arn} &>/dev/null; then
        error "SNS topic still exists: ${SNS_TOPIC}"
        cleanup_errors=$((cleanup_errors + 1))
    else
        success "SNS topic successfully removed"
    fi
    
    # Check IAM role
    if aws iam get-role --role-name ${IAM_ROLE} &>/dev/null; then
        error "IAM role still exists: ${IAM_ROLE}"
        cleanup_errors=$((cleanup_errors + 1))
    else
        success "IAM role successfully removed"
    fi
    
    if [[ $cleanup_errors -gt 0 ]]; then
        error "Cleanup validation failed with $cleanup_errors errors"
        return 1
    else
        success "Cleanup validation completed successfully"
        return 0
    fi
}

# Display cleanup summary
display_summary() {
    info "Cleanup Summary:"
    info "================"
    info "AWS Region: ${AWS_REGION}"
    info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    info ""
    info "Removed resources:"
    info "  ✓ Lambda Function: ${LAMBDA_FUNCTION}"
    info "  ✓ S3 Input Bucket: ${BUCKET_INPUT}"
    info "  ✓ S3 Output Bucket: ${BUCKET_OUTPUT}"
    info "  ✓ SNS Topic: ${SNS_TOPIC}"
    info "  ✓ IAM Role: ${IAM_ROLE}"
    info "  ✓ CloudWatch Logs"
    info "  ✓ Local deployment files"
    info ""
    success "All resources have been successfully removed!"
}

# Handle cleanup errors
handle_cleanup_errors() {
    error "Some resources may not have been completely removed."
    error "Please check the AWS console and manually remove any remaining resources:"
    error "  - Lambda Functions: https://console.aws.amazon.com/lambda/"
    error "  - S3 Buckets: https://console.aws.amazon.com/s3/"
    error "  - SNS Topics: https://console.aws.amazon.com/sns/"
    error "  - IAM Roles: https://console.aws.amazon.com/iam/"
    error "  - CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/"
    exit 1
}

# Main execution
main() {
    log "Starting AWS Textract Document Analysis Solution cleanup..."
    
    load_deployment_vars
    check_prerequisites
    confirm_deletion
    
    # Remove resources in reverse order of creation
    remove_lambda_function
    remove_s3_notifications
    remove_s3_buckets
    remove_sns_topic
    remove_iam_role
    remove_cloudwatch_logs
    cleanup_local_files
    
    # Validate cleanup
    if validate_cleanup; then
        display_summary
    else
        handle_cleanup_errors
    fi
    
    log "Cleanup completed successfully at $(date)"
}

# Run main function
main "$@"