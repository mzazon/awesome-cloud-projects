#!/bin/bash

# destroy.sh - Cleanup AWS Resource Cleanup Automation infrastructure
# This script removes all resources created by the deploy.sh script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ENV_FILE="${SCRIPT_DIR}/.env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

# Info message function
info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "$LOG_FILE"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI version 2.0 or later."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials are not configured or invalid. Please run 'aws configure' or set appropriate environment variables."
    fi
    
    success "Prerequisites check completed"
}

# Load environment variables from deployment
load_environment() {
    info "Loading environment variables from deployment..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        error_exit "Environment file not found at $ENV_FILE. Please ensure the deployment was successful or set variables manually."
    fi
    
    # Source the environment file
    set -a  # Automatically export all variables
    source "$ENV_FILE"
    set +a  # Turn off automatic export
    
    # Validate required variables
    local required_vars=("AWS_REGION" "FUNCTION_NAME" "ROLE_NAME" "SNS_TOPIC_NAME")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error_exit "Required variable $var is not set in environment file"
        fi
    done
    
    success "Environment variables loaded successfully"
    info "AWS Region: ${AWS_REGION}"
    info "Function Name: ${FUNCTION_NAME}"
    info "Role Name: ${ROLE_NAME}"
    info "SNS Topic Name: ${SNS_TOPIC_NAME}"
}

# Confirm destruction with user
confirm_destruction() {
    if [[ "${FORCE:-false}" == "true" ]]; then
        warning "Force mode enabled - skipping confirmation"
        return
    fi
    
    echo ""
    echo -e "${RED}⚠️  WARNING: This will permanently delete the following resources:${NC}"
    echo "- Lambda Function: ${FUNCTION_NAME}"
    echo "- IAM Role: ${ROLE_NAME}"
    echo "- SNS Topic: ${SNS_TOPIC_NAME}"
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        echo "- SNS Topic ARN: ${SNS_TOPIC_ARN}"
    fi
    if [[ -n "${TEST_INSTANCE_ID:-}" ]]; then
        echo "- Test EC2 Instance: ${TEST_INSTANCE_ID} (if still running)"
    fi
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    echo -n "Are you sure you want to proceed? Type 'yes' to confirm: "
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    info "Proceeding with resource destruction..."
}

# Check if resource exists (returns 0 if exists, 1 if not)
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local region="${3:-$AWS_REGION}"
    
    case "$resource_type" in
        "lambda")
            aws lambda get-function --function-name "$resource_name" --region "$region" &>/dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" &>/dev/null
            ;;
        "sns-topic")
            aws sns get-topic-attributes --topic-arn "$resource_name" --region "$region" &>/dev/null
            ;;
        "ec2-instance")
            local state=$(aws ec2 describe-instances --instance-ids "$resource_name" --region "$region" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "not-found")
            [[ "$state" != "not-found" && "$state" != "terminated" ]]
            ;;
        *)
            error_exit "Unknown resource type: $resource_type"
            ;;
    esac
}

# Delete Lambda function
delete_lambda_function() {
    info "Deleting Lambda function..."
    
    if resource_exists "lambda" "$FUNCTION_NAME"; then
        aws lambda delete-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" || warning "Failed to delete Lambda function $FUNCTION_NAME"
        
        # Wait a moment for deletion to propagate
        sleep 5
        
        # Verify deletion
        if ! resource_exists "lambda" "$FUNCTION_NAME"; then
            success "Lambda function deleted: $FUNCTION_NAME"
        else
            warning "Lambda function may still exist: $FUNCTION_NAME"
        fi
    else
        warning "Lambda function not found: $FUNCTION_NAME"
    fi
}

# Delete CloudWatch Log Group
delete_log_group() {
    info "Deleting CloudWatch Log Group..."
    
    local log_group_name="/aws/lambda/${FUNCTION_NAME}"
    
    if aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --region "$AWS_REGION" --query 'logGroups[0]' --output text | grep -q "^/aws/lambda"; then
        aws logs delete-log-group --log-group-name "$log_group_name" --region "$AWS_REGION" || warning "Failed to delete log group $log_group_name"
        success "CloudWatch Log Group deleted: $log_group_name"
    else
        warning "CloudWatch Log Group not found: $log_group_name"
    fi
}

# Delete IAM role and policies
delete_iam_role() {
    info "Deleting IAM role and policies..."
    
    if resource_exists "iam-role" "$ROLE_NAME"; then
        # Delete inline policies first
        local policies=$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames' --output text 2>/dev/null || echo "")
        
        if [[ -n "$policies" && "$policies" != "None" ]]; then
            for policy in $policies; do
                info "Deleting inline policy: $policy"
                aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$policy" || warning "Failed to delete policy $policy"
            done
        fi
        
        # Delete attached managed policies
        local attached_policies=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        
        if [[ -n "$attached_policies" && "$attached_policies" != "None" ]]; then
            for policy_arn in $attached_policies; do
                info "Detaching managed policy: $policy_arn"
                aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$policy_arn" || warning "Failed to detach policy $policy_arn"
            done
        fi
        
        # Wait for policies to be detached
        sleep 5
        
        # Delete the role
        aws iam delete-role --role-name "$ROLE_NAME" || warning "Failed to delete IAM role $ROLE_NAME"
        
        # Verify deletion
        if ! resource_exists "iam-role" "$ROLE_NAME"; then
            success "IAM role deleted: $ROLE_NAME"
        else
            warning "IAM role may still exist: $ROLE_NAME"
        fi
    else
        warning "IAM role not found: $ROLE_NAME"
    fi
}

# Delete SNS topic and subscriptions
delete_sns_topic() {
    info "Deleting SNS topic..."
    
    # Try to get topic ARN from environment or construct it
    if [[ -z "${SNS_TOPIC_ARN:-}" ]]; then
        export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    fi
    
    if resource_exists "sns-topic" "$SNS_TOPIC_ARN"; then
        # List and delete subscriptions first
        local subscriptions=$(aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" --region "$AWS_REGION" --query 'Subscriptions[].SubscriptionArn' --output text 2>/dev/null || echo "")
        
        if [[ -n "$subscriptions" && "$subscriptions" != "None" ]]; then
            for subscription_arn in $subscriptions; do
                if [[ "$subscription_arn" != "PendingConfirmation" ]]; then
                    info "Deleting subscription: $subscription_arn"
                    aws sns unsubscribe --subscription-arn "$subscription_arn" --region "$AWS_REGION" || warning "Failed to delete subscription $subscription_arn"
                fi
            done
        fi
        
        # Wait for subscriptions to be deleted
        sleep 3
        
        # Delete the topic
        aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" --region "$AWS_REGION" || warning "Failed to delete SNS topic $SNS_TOPIC_ARN"
        
        # Verify deletion
        if ! resource_exists "sns-topic" "$SNS_TOPIC_ARN"; then
            success "SNS topic deleted: $SNS_TOPIC_ARN"
        else
            warning "SNS topic may still exist: $SNS_TOPIC_ARN"
        fi
    else
        warning "SNS topic not found: $SNS_TOPIC_ARN"
    fi
}

# Delete test instance if it exists
delete_test_instance() {
    if [[ -z "${TEST_INSTANCE_ID:-}" ]]; then
        info "No test instance ID found, skipping"
        return
    fi
    
    info "Checking test instance..."
    
    if resource_exists "ec2-instance" "$TEST_INSTANCE_ID"; then
        local instance_state=$(aws ec2 describe-instances --instance-ids "$TEST_INSTANCE_ID" --region "$AWS_REGION" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "unknown")
        
        if [[ "$instance_state" == "running" || "$instance_state" == "stopped" ]]; then
            echo -n "Test instance $TEST_INSTANCE_ID is $instance_state. Terminate it? (y/n): "
            read -r terminate_instance
            
            if [[ "$terminate_instance" =~ ^[Yy]$ ]]; then
                info "Terminating test instance: $TEST_INSTANCE_ID"
                aws ec2 terminate-instances --instance-ids "$TEST_INSTANCE_ID" --region "$AWS_REGION" || warning "Failed to terminate test instance"
                success "Test instance termination initiated: $TEST_INSTANCE_ID"
            else
                info "Keeping test instance: $TEST_INSTANCE_ID"
            fi
        else
            info "Test instance is already $instance_state: $TEST_INSTANCE_ID"
        fi
    else
        warning "Test instance not found or already terminated: $TEST_INSTANCE_ID"
    fi
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    local files_to_remove=(
        "$ENV_FILE"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            success "Removed file: $file"
        fi
    done
    
    success "Local files cleaned up"
}

# Verify destruction completion
verify_destruction() {
    info "Verifying resource destruction..."
    
    local errors=0
    
    # Check Lambda function
    if resource_exists "lambda" "$FUNCTION_NAME"; then
        warning "Lambda function still exists: $FUNCTION_NAME"
        ((errors++))
    fi
    
    # Check IAM role
    if resource_exists "iam-role" "$ROLE_NAME"; then
        warning "IAM role still exists: $ROLE_NAME"
        ((errors++))
    fi
    
    # Check SNS topic
    if [[ -n "${SNS_TOPIC_ARN:-}" ]] && resource_exists "sns-topic" "$SNS_TOPIC_ARN"; then
        warning "SNS topic still exists: $SNS_TOPIC_ARN"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        success "All resources have been successfully destroyed"
    else
        warning "$errors resource(s) may still exist. Check AWS console for manual cleanup."
    fi
}

# Display destruction summary
display_summary() {
    echo ""
    echo "=== Destruction Summary ==="
    echo "Attempted to delete:"
    echo "- Lambda Function: ${FUNCTION_NAME}"
    echo "- IAM Role: ${ROLE_NAME}"
    echo "- SNS Topic: ${SNS_TOPIC_NAME}"
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        echo "- SNS Topic ARN: ${SNS_TOPIC_ARN}"
    fi
    if [[ -n "${TEST_INSTANCE_ID:-}" ]]; then
        echo "- Test Instance: ${TEST_INSTANCE_ID}"
    fi
    echo "- CloudWatch Log Group: /aws/lambda/${FUNCTION_NAME}"
    echo "- Local environment file: $ENV_FILE"
    echo ""
    echo "=== Post-Destruction Notes ==="
    echo "- Check AWS Console to verify all resources are deleted"
    echo "- Any EC2 instances with AutoCleanup tags are unaffected"
    echo "- Email subscriptions were automatically removed with SNS topic"
    echo ""
    success "Resource cleanup automation has been destroyed!"
}

# Print usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force     Skip confirmation prompts and force deletion"
    echo "  --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive destruction with confirmations"
    echo "  $0 --force           # Force destruction without confirmations"
    echo ""
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

# Main execution
main() {
    echo "=== AWS Resource Cleanup Automation Destruction ==="
    echo "This script will remove all resources created by the deployment script"
    echo ""
    
    log "Starting destruction process..."
    
    parse_args "$@"
    check_prerequisites
    load_environment
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_test_instance
    delete_lambda_function
    delete_log_group
    delete_iam_role
    delete_sns_topic
    cleanup_local_files
    
    verify_destruction
    display_summary
    
    log "Destruction process completed"
}

# Run main function with all arguments
main "$@"