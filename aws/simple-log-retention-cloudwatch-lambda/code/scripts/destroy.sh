#!/bin/bash

# Destroy Script for Simple Log Retention Management with CloudWatch and Lambda
# This script removes all resources created by the deployment script

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
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message"
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        BLUE)
            echo -e "${BLUE}[INFO]${NC} $message"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
    esac
}

# Cleanup function for script termination
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log ERROR "Cleanup failed with exit code $exit_code"
        log INFO "Check the log file at $LOG_FILE for details"
        log INFO "Some resources may need to be manually removed"
    fi
    exit $exit_code
}

# Set up trap for cleanup
trap cleanup EXIT

# Load environment variables
load_environment() {
    log INFO "Loading environment variables..."
    
    if [ ! -f "$ENV_FILE" ]; then
        log ERROR "Environment file not found: $ENV_FILE"
        log ERROR "This file is created by the deploy script and contains resource identifiers"
        log INFO "If you know the resource names, you can manually create the .env file with:"
        echo
        echo "AWS_REGION=your-region"
        echo "AWS_ACCOUNT_ID=your-account-id"
        echo "FUNCTION_NAME=your-function-name"
        echo "ROLE_NAME=your-role-name"
        echo "TEST_LOG_GROUP=your-test-log-group"
        echo "RULE_NAME=your-rule-name"
        echo "RANDOM_SUFFIX=your-suffix"
        exit 1
    fi
    
    # Source environment variables
    source "$ENV_FILE"
    
    log INFO "Environment loaded:"
    log INFO "• AWS Region: ${AWS_REGION}"
    log INFO "• Function Name: ${FUNCTION_NAME}"
    log INFO "• IAM Role: ${ROLE_NAME}"
    log INFO "• EventBridge Rule: ${RULE_NAME}"
}

# Check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log ERROR "AWS CLI is not installed. Please install AWS CLI version 2.0 or later."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log ERROR "AWS credentials are not configured. Please run 'aws configure' or set up credentials."
        exit 1
    fi
    
    log INFO "Prerequisites check completed ✅"
}

# Confirmation prompt
confirm_destruction() {
    local force=${1:-false}
    
    if [ "$force" != "true" ]; then
        echo
        log WARN "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
        echo
        log WARN "This will permanently delete the following resources:"
        log WARN "• Lambda Function: ${FUNCTION_NAME}"
        log WARN "• IAM Role: ${ROLE_NAME}"
        log WARN "• EventBridge Rule: ${RULE_NAME}"
        log WARN "• Test Log Groups: 4 groups"
        echo
        log WARN "This action cannot be undone!"
        echo
        
        read -p "Are you sure you want to continue? (yes/no): " confirmation
        
        case $confirmation in
            yes|YES|y|Y)
                log INFO "Proceeding with resource destruction..."
                ;;
            *)
                log INFO "Operation cancelled by user"
                exit 0
                ;;
        esac
    else
        log INFO "Force mode enabled, skipping confirmation"
    fi
}

# Remove EventBridge rule and targets
remove_eventbridge_rule() {
    log INFO "Removing EventBridge rule and targets..."
    
    # Check if rule exists
    if ! aws events describe-rule --name "${RULE_NAME}" &> /dev/null; then
        log WARN "EventBridge rule ${RULE_NAME} not found, skipping"
        return 0
    fi
    
    # Remove targets from EventBridge rule
    local targets_exist=$(aws events list-targets-by-rule \
        --rule "${RULE_NAME}" \
        --query 'Targets[].Id' --output text 2>/dev/null || echo "")
    
    if [ -n "$targets_exist" ]; then
        aws events remove-targets \
            --rule "${RULE_NAME}" \
            --ids "1" 2>/dev/null || log WARN "Failed to remove EventBridge targets"
        log INFO "EventBridge targets removed"
    fi
    
    # Delete EventBridge rule
    aws events delete-rule --name "${RULE_NAME}"
    log INFO "EventBridge rule deleted: ${RULE_NAME} ✅"
}

# Remove Lambda function
remove_lambda_function() {
    log INFO "Removing Lambda function..."
    
    # Check if function exists
    if ! aws lambda get-function --function-name "${FUNCTION_NAME}" &> /dev/null; then
        log WARN "Lambda function ${FUNCTION_NAME} not found, skipping"
        return 0
    fi
    
    # Remove Lambda permissions first (if they exist)
    local statement_id="allow-eventbridge-${RANDOM_SUFFIX}"
    aws lambda remove-permission \
        --function-name "${FUNCTION_NAME}" \
        --statement-id "$statement_id" &> /dev/null || log WARN "Lambda permission already removed or not found"
    
    # Delete Lambda function
    aws lambda delete-function --function-name "${FUNCTION_NAME}"
    log INFO "Lambda function deleted: ${FUNCTION_NAME} ✅"
}

# Remove test log groups
remove_test_log_groups() {
    log INFO "Removing test log groups..."
    
    local test_groups=(
        "/aws/lambda/test-function-${RANDOM_SUFFIX}"
        "/aws/apigateway/test-api-${RANDOM_SUFFIX}"
        "/application/web-app-${RANDOM_SUFFIX}"
        "${TEST_LOG_GROUP}"
    )
    
    local removed_count=0
    
    for log_group in "${test_groups[@]}"; do
        # Check if log group exists
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
            aws logs delete-log-group --log-group-name "$log_group"
            log INFO "Deleted test log group: $log_group"
            ((removed_count++))
        else
            log WARN "Test log group not found: $log_group"
        fi
    done
    
    log INFO "Test log groups removed: $removed_count ✅"
}

# Remove IAM role and policies
remove_iam_role() {
    log INFO "Removing IAM role and policies..."
    
    # Check if role exists
    if ! aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
        log WARN "IAM role ${ROLE_NAME} not found, skipping"
        return 0
    fi
    
    # Remove inline policies from role
    local policies=$(aws iam list-role-policies \
        --role-name "${ROLE_NAME}" \
        --query 'PolicyNames' --output text 2>/dev/null || echo "")
    
    for policy in $policies; do
        if [ -n "$policy" ] && [ "$policy" != "None" ]; then
            aws iam delete-role-policy \
                --role-name "${ROLE_NAME}" \
                --policy-name "$policy"
            log INFO "Deleted inline policy: $policy"
        fi
    done
    
    # Remove attached managed policies (if any)
    local managed_policies=$(aws iam list-attached-role-policies \
        --role-name "${ROLE_NAME}" \
        --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    
    for policy_arn in $managed_policies; do
        if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
            aws iam detach-role-policy \
                --role-name "${ROLE_NAME}" \
                --policy-arn "$policy_arn"
            log INFO "Detached managed policy: $policy_arn"
        fi
    done
    
    # Delete IAM role
    aws iam delete-role --role-name "${ROLE_NAME}"
    log INFO "IAM role deleted: ${ROLE_NAME} ✅"
}

# Clean up local files
cleanup_local_files() {
    log INFO "Cleaning up local files..."
    
    local files_to_remove=(
        "${ENV_FILE}"
        "${SCRIPT_DIR}/temp"
        "${SCRIPT_DIR}/*.json"
        "${SCRIPT_DIR}/*.py"
        "${SCRIPT_DIR}/*.zip"
    )
    
    for file_pattern in "${files_to_remove[@]}"; do
        if [ -e "$file_pattern" ] || ls $file_pattern 1> /dev/null 2>&1; then
            rm -rf $file_pattern 2>/dev/null || log WARN "Could not remove: $file_pattern"
        fi
    done
    
    log INFO "Local files cleaned up ✅"
}

# Verify resource removal
verify_removal() {
    log INFO "Verifying resource removal..."
    
    local errors=()
    
    # Check Lambda function
    if aws lambda get-function --function-name "${FUNCTION_NAME}" &> /dev/null; then
        errors+=("Lambda function ${FUNCTION_NAME} still exists")
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "${ROLE_NAME}" &> /dev/null; then
        errors+=("IAM role ${ROLE_NAME} still exists")
    fi
    
    # Check EventBridge rule
    if aws events describe-rule --name "${RULE_NAME}" &> /dev/null; then
        errors+=("EventBridge rule ${RULE_NAME} still exists")
    fi
    
    # Check test log groups
    local remaining_groups=()
    local test_groups=(
        "/aws/lambda/test-function-${RANDOM_SUFFIX}"
        "/aws/apigateway/test-api-${RANDOM_SUFFIX}"
        "/application/web-app-${RANDOM_SUFFIX}"
        "${TEST_LOG_GROUP}"
    )
    
    for log_group in "${test_groups[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
            remaining_groups+=("$log_group")
        fi
    done
    
    if [ ${#remaining_groups[@]} -gt 0 ]; then
        errors+=("${#remaining_groups[@]} test log groups still exist")
    fi
    
    # Report verification results
    if [ ${#errors[@]} -gt 0 ]; then
        log WARN "Some resources may not have been completely removed:"
        for error in "${errors[@]}"; do
            log WARN "• $error"
        done
        log WARN "You may need to manually remove these resources"
        return 1
    else
        log INFO "All resources successfully removed ✅"
        return 0
    fi
}

# Display destruction summary
display_summary() {
    log INFO "=== Destruction Summary ==="
    echo
    log BLUE "Resources Removed:"
    log INFO "• EventBridge Rule: ${RULE_NAME}"
    log INFO "• Lambda Function: ${FUNCTION_NAME}"
    log INFO "• Test Log Groups: 4 groups"
    log INFO "• IAM Role: ${ROLE_NAME}"
    log INFO "• Local Files: Temporary files and environment"
    echo
    log BLUE "Clean Up Status:"
    if verify_removal; then
        log GREEN "✅ All resources successfully removed"
    else
        log YELLOW "⚠️  Some resources may require manual removal"
    fi
    echo
    log GREEN "Destruction completed! 🧹"
}

# Main destruction function
main() {
    local force=${1:-false}
    
    log INFO "Starting destruction of Simple Log Retention Management solution..."
    log INFO "Log file: $LOG_FILE"
    echo
    
    # Execute destruction steps
    check_prerequisites
    load_environment
    confirm_destruction "$force"
    
    echo
    log INFO "Beginning resource removal..."
    
    # Remove resources in reverse order of creation
    remove_eventbridge_rule
    remove_lambda_function
    remove_test_log_groups
    remove_iam_role
    cleanup_local_files
    
    echo
    display_summary
    
    log INFO "Destruction completed!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--force] [--help]"
        echo
        echo "Destroy Simple Log Retention Management resources"
        echo
        echo "Options:"
        echo "  --force       Skip confirmation prompt"
        echo "  --help, -h    Show this help message"
        echo
        echo "This script will remove:"
        echo "  • Lambda function and permissions"
        echo "  • IAM role and policies"
        echo "  • EventBridge rule and targets"
        echo "  • Test log groups"
        echo "  • Local configuration files"
        echo
        echo "Prerequisites:"
        echo "  • AWS CLI installed and configured"
        echo "  • .env file from deployment (contains resource identifiers)"
        exit 0
        ;;
    --force)
        main true
        ;;
    "")
        main false
        ;;
    *)
        log ERROR "Unknown option: $1"
        log INFO "Use --help for usage information"
        exit 1
        ;;
esac