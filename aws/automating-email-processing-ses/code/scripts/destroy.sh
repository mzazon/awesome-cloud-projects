#!/bin/bash

# destroy.sh - Cleanup Serverless Email Processing System
# This script safely removes all resources created by the deployment script
# Includes confirmation prompts and handles resource dependencies

set -e  # Exit on any error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to load deployment state
load_state() {
    if [ ! -f "$STATE_FILE" ]; then
        log "ERROR" "Deployment state file not found: $STATE_FILE"
        log "ERROR" "Cannot proceed with cleanup without deployment state"
        exit 1
    fi
    
    log "INFO" "Loading deployment state from: $STATE_FILE"
    source "$STATE_FILE"
    
    # Verify required variables are loaded
    local required_vars=("AWS_REGION" "AWS_ACCOUNT_ID" "BUCKET_NAME" "FUNCTION_NAME" "SNS_TOPIC_NAME" "ROLE_NAME" "POLICY_NAME" "RULE_SET_NAME" "RULE_NAME")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            log "ERROR" "Required variable $var not found in state file"
            exit 1
        fi
    done
    
    log "SUCCESS" "Deployment state loaded successfully"
}

# Function to confirm destruction
confirm_destruction() {
    log "WARNING" "This will permanently delete the following resources:"
    echo
    log "INFO" "  S3 Bucket: $BUCKET_NAME (and all contents)"
    log "INFO" "  Lambda Function: $FUNCTION_NAME"
    log "INFO" "  SNS Topic: $SNS_TOPIC_NAME"
    log "INFO" "  IAM Role: $ROLE_NAME"
    log "INFO" "  IAM Policy: $POLICY_NAME"
    log "INFO" "  SES Rule Set: $RULE_SET_NAME"
    echo
    
    read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " confirmation
    if [ "$confirmation" != "DELETE" ]; then
        log "INFO" "Cleanup cancelled by user"
        exit 0
    fi
    
    log "INFO" "Cleanup confirmed. Proceeding with resource deletion..."
}

# Function to check AWS connectivity
check_aws_connectivity() {
    log "INFO" "Checking AWS connectivity..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "Cannot connect to AWS. Please check AWS CLI configuration"
        exit 1
    fi
    
    local current_account=$(aws sts get-caller-identity --query Account --output text)
    if [ "$current_account" != "$AWS_ACCOUNT_ID" ]; then
        log "ERROR" "Current AWS account ($current_account) doesn't match deployed account ($AWS_ACCOUNT_ID)"
        exit 1
    fi
    
    log "SUCCESS" "AWS connectivity verified"
}

# Function to remove SES configuration
remove_ses_configuration() {
    log "INFO" "Removing SES configuration..."
    
    # Remove receipt rule
    if aws ses describe-receipt-rule --rule-set-name "$RULE_SET_NAME" --rule-name "$RULE_NAME" &> /dev/null; then
        log "INFO" "Deleting SES receipt rule: $RULE_NAME"
        aws ses delete-receipt-rule \
            --rule-set-name "$RULE_SET_NAME" \
            --rule-name "$RULE_NAME" || log "WARNING" "Failed to delete receipt rule"
    else
        log "INFO" "Receipt rule $RULE_NAME not found (may already be deleted)"
    fi
    
    # Remove rule set
    if aws ses describe-receipt-rule-set --rule-set-name "$RULE_SET_NAME" &> /dev/null; then
        log "INFO" "Deleting SES rule set: $RULE_SET_NAME"
        aws ses delete-receipt-rule-set \
            --rule-set-name "$RULE_SET_NAME" || log "WARNING" "Failed to delete rule set"
    else
        log "INFO" "Rule set $RULE_SET_NAME not found (may already be deleted)"
    fi
    
    log "SUCCESS" "SES configuration removed"
}

# Function to remove Lambda function
remove_lambda_function() {
    log "INFO" "Removing Lambda function..."
    
    if aws lambda get-function --function-name "$FUNCTION_NAME" &> /dev/null; then
        log "INFO" "Deleting Lambda function: $FUNCTION_NAME"
        aws lambda delete-function --function-name "$FUNCTION_NAME"
        log "SUCCESS" "Lambda function deleted"
    else
        log "INFO" "Lambda function $FUNCTION_NAME not found (may already be deleted)"
    fi
}

# Function to remove IAM resources
remove_iam_resources() {
    log "INFO" "Removing IAM resources..."
    
    # Detach policies from role
    local basic_policy_arn="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    local custom_policy_arn="arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME"
    
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        log "INFO" "Detaching policies from role: $ROLE_NAME"
        
        # Detach basic Lambda execution policy
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn "$basic_policy_arn" 2>/dev/null || log "WARNING" "Failed to detach basic execution policy"
        
        # Detach custom policy
        aws iam detach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn "$custom_policy_arn" 2>/dev/null || log "WARNING" "Failed to detach custom policy"
        
        # Delete role
        log "INFO" "Deleting IAM role: $ROLE_NAME"
        aws iam delete-role --role-name "$ROLE_NAME"
        log "SUCCESS" "IAM role deleted"
    else
        log "INFO" "IAM role $ROLE_NAME not found (may already be deleted)"
    fi
    
    # Delete custom policy
    if aws iam get-policy --policy-arn "$custom_policy_arn" &> /dev/null; then
        log "INFO" "Deleting IAM policy: $POLICY_NAME"
        aws iam delete-policy --policy-arn "$custom_policy_arn"
        log "SUCCESS" "IAM policy deleted"
    else
        log "INFO" "IAM policy $POLICY_NAME not found (may already be deleted)"
    fi
}

# Function to remove S3 bucket
remove_s3_bucket() {
    log "INFO" "Removing S3 bucket and contents..."
    
    if aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        # Check if bucket has objects
        local object_count=$(aws s3 ls "s3://$BUCKET_NAME" --recursive | wc -l)
        if [ "$object_count" -gt 0 ]; then
            log "INFO" "Bucket contains $object_count objects. Emptying bucket..."
            aws s3 rm "s3://$BUCKET_NAME" --recursive
        fi
        
        # Check for versioned objects
        log "INFO" "Removing versioned objects (if any)..."
        aws s3api delete-objects \
            --bucket "$BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --output json \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
        
        # Remove delete markers
        aws s3api delete-objects \
            --bucket "$BUCKET_NAME" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$BUCKET_NAME" \
                --output json \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
        
        # Delete bucket
        log "INFO" "Deleting S3 bucket: $BUCKET_NAME"
        aws s3 rb "s3://$BUCKET_NAME"
        log "SUCCESS" "S3 bucket deleted"
    else
        log "INFO" "S3 bucket $BUCKET_NAME not found (may already be deleted)"
    fi
}

# Function to remove SNS topic
remove_sns_topic() {
    log "INFO" "Removing SNS topic..."
    
    if [ -n "${SNS_TOPIC_ARN:-}" ]; then
        # List and delete subscriptions first
        local subscriptions=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$SNS_TOPIC_ARN" \
            --query 'Subscriptions[].SubscriptionArn' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$subscriptions" ] && [ "$subscriptions" != "None" ]; then
            log "INFO" "Removing SNS subscriptions..."
            for subscription in $subscriptions; do
                if [ "$subscription" != "PendingConfirmation" ]; then
                    aws sns unsubscribe --subscription-arn "$subscription" 2>/dev/null || true
                fi
            done
        fi
        
        # Delete topic
        log "INFO" "Deleting SNS topic: $SNS_TOPIC_NAME"
        aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN"
        log "SUCCESS" "SNS topic deleted"
    else
        log "INFO" "SNS topic ARN not found in state file"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    # Remove temporary files that might have been left behind
    local temp_files=(
        "/tmp/lambda-trust-policy.json"
        "/tmp/email-processor-policy.json"
        "/tmp/receipt-rule.json"
        "/tmp/bucket-policy.json"
        "/tmp/email-processor.py"
        "/tmp/email-processor.zip"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "INFO" "Removed temporary file: $file"
        fi
    done
    
    # Ask user if they want to remove state file
    read -p "Remove deployment state file? (y/N): " remove_state
    if [[ $remove_state =~ ^[Yy]$ ]]; then
        rm -f "$STATE_FILE"
        log "INFO" "Deployment state file removed"
    else
        log "INFO" "Deployment state file preserved for reference"
    fi
    
    log "SUCCESS" "Local cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "INFO" "Verifying cleanup completion..."
    
    local errors=0
    
    # Check Lambda function
    if aws lambda get-function --function-name "$FUNCTION_NAME" &> /dev/null; then
        log "ERROR" "Lambda function still exists: $FUNCTION_NAME"
        ((errors++))
    fi
    
    # Check S3 bucket
    if aws s3 ls "s3://$BUCKET_NAME" &> /dev/null; then
        log "ERROR" "S3 bucket still exists: $BUCKET_NAME"
        ((errors++))
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
        log "ERROR" "IAM role still exists: $ROLE_NAME"
        ((errors++))
    fi
    
    # Check SNS topic
    if [ -n "${SNS_TOPIC_ARN:-}" ] && aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &> /dev/null; then
        log "ERROR" "SNS topic still exists: $SNS_TOPIC_ARN"
        ((errors++))
    fi
    
    if [ $errors -eq 0 ]; then
        log "SUCCESS" "All resources successfully removed"
        return 0
    else
        log "WARNING" "Some resources may still exist. Please check manually."
        return 1
    fi
}

# Function to display cleanup summary
cleanup_summary() {
    echo
    log "SUCCESS" "Cleanup completed!"
    echo
    log "INFO" "Resources that were removed:"
    log "INFO" "  ✅ S3 Bucket: $BUCKET_NAME"
    log "INFO" "  ✅ Lambda Function: $FUNCTION_NAME"
    log "INFO" "  ✅ SNS Topic: $SNS_TOPIC_NAME"
    log "INFO" "  ✅ IAM Role: $ROLE_NAME"
    log "INFO" "  ✅ IAM Policy: $POLICY_NAME"
    log "INFO" "  ✅ SES Rule Set: $RULE_SET_NAME"
    echo
    
    if [ -f "$STATE_FILE" ]; then
        log "INFO" "Deployment state file preserved at: $STATE_FILE"
        log "INFO" "You can safely delete this file if no longer needed"
    fi
    
    log "INFO" "Cleanup log saved to: $LOG_FILE"
}

# Function to handle partial cleanup scenarios
handle_partial_cleanup() {
    log "WARNING" "Cleanup encountered some issues"
    log "INFO" "You may need to manually remove remaining resources"
    echo
    log "INFO" "To check for remaining resources, run:"
    log "INFO" "  aws lambda list-functions --query 'Functions[?FunctionName==\`$FUNCTION_NAME\`]'"
    log "INFO" "  aws s3 ls s3://$BUCKET_NAME"
    log "INFO" "  aws iam get-role --role-name $ROLE_NAME"
    log "INFO" "  aws sns get-topic-attributes --topic-arn $SNS_TOPIC_ARN"
}

# Main cleanup function
main() {
    log "INFO" "Starting serverless email processing system cleanup..."
    log "INFO" "Log file: $LOG_FILE"
    
    load_state
    confirm_destruction
    check_aws_connectivity
    
    # Perform cleanup in reverse order of creation
    remove_ses_configuration
    remove_lambda_function
    remove_iam_resources
    remove_s3_bucket
    remove_sns_topic
    cleanup_local_files
    
    if verify_cleanup; then
        cleanup_summary
    else
        handle_partial_cleanup
    fi
    
    log "SUCCESS" "Cleanup process completed!"
}

# Error handling for non-critical errors
handle_error() {
    local line_number=$1
    log "ERROR" "Error occurred at line $line_number"
    log "INFO" "Continuing with cleanup process..."
}

# Set up error handling (don't exit on error for cleanup)
set +e
trap 'handle_error $LINENO' ERR

# Run main function
main "$@"