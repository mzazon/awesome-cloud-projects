#!/bin/bash

# AWS Config Auto-Remediation Cleanup Script
# This script safely removes all resources created by the deployment script
# including AWS Config, Lambda functions, IAM roles, and S3 buckets.

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/deployment-config.env"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
FORCE_DELETE=false

# Colors for output
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
        ERROR)
            echo -e "${RED}[ERROR] $message${NC}" >&2
            echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS] $message${NC}"
            echo "[$timestamp] [SUCCESS] $message" >> "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN] $message${NC}"
            echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
            ;;
        INFO)
            echo -e "${BLUE}[INFO] $message${NC}"
            echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
            ;;
    esac
}

# Error handler
error_exit() {
    log ERROR "Cleanup failed: $1"
    log ERROR "Check logs at: $LOG_FILE"
    exit 1
}

# Print header
echo "================================================"
echo "AWS Config Auto-Remediation Cleanup Script"
echo "Timestamp: $TIMESTAMP"
echo "Log file: $LOG_FILE"
echo "================================================"
echo

# Load configuration if available
load_configuration() {
    if [ -f "$CONFIG_FILE" ]; then
        log INFO "Loading configuration from: $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        log SUCCESS "Configuration loaded"
        return 0
    else
        log WARN "Configuration file not found: $CONFIG_FILE"
        return 1
    fi
}

# Interactive resource discovery
discover_resources_interactively() {
    log INFO "Configuration file not found. Starting interactive resource discovery..."
    
    # Get region
    AWS_REGION=${AWS_REGION:-$(aws configure get region 2>/dev/null)}
    if [ -z "${AWS_REGION:-}" ]; then
        read -rp "Enter AWS region: " AWS_REGION
    fi
    export AWS_REGION
    
    # Get account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || \
        error_exit "Cannot retrieve AWS account ID"
    export AWS_ACCOUNT_ID
    
    echo
    echo "Discovering AWS Config Auto-Remediation resources..."
    echo "Region: $AWS_REGION"
    echo "Account: $AWS_ACCOUNT_ID"
    echo
    
    # Discover Lambda functions
    echo "Lambda Functions with 'SecurityGroupRemediation' in name:"
    aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `SecurityGroupRemediation`)].FunctionName' \
        --output table 2>/dev/null || true
    
    read -rp "Enter Lambda function name (or press Enter to skip): " LAMBDA_FUNCTION_NAME
    export LAMBDA_FUNCTION_NAME
    
    # Discover S3 buckets
    echo
    echo "S3 Buckets with 'aws-config' in name:"
    aws s3 ls | grep aws-config || true
    
    read -rp "Enter S3 bucket name (or press Enter to skip): " S3_BUCKET_NAME
    export S3_BUCKET_NAME
    
    # Discover SNS topics
    echo
    echo "SNS Topics with 'config-compliance' in name:"
    aws sns list-topics --query 'Topics[?contains(TopicArn, `config-compliance`)].TopicArn' --output table 2>/dev/null || true
    
    read -rp "Enter SNS topic name (or press Enter to skip): " SNS_TOPIC_NAME
    export SNS_TOPIC_NAME
    
    # Discover IAM roles
    echo
    echo "IAM Roles with 'Config' in name:"
    aws iam list-roles --query 'Roles[?contains(RoleName, `Config`)].RoleName' --output table 2>/dev/null || true
    
    read -rp "Enter Config role name (or press Enter to skip): " CONFIG_ROLE_NAME
    read -rp "Enter Lambda role name (or press Enter to skip): " LAMBDA_ROLE_NAME
    export CONFIG_ROLE_NAME LAMBDA_ROLE_NAME
    
    # Discover CloudWatch dashboards
    echo
    echo "CloudWatch Dashboards with 'Config-Compliance' in name:"
    aws cloudwatch list-dashboards --query 'DashboardEntries[?contains(DashboardName, `Config-Compliance`)].DashboardName' --output table 2>/dev/null || true
    
    read -rp "Enter dashboard name (or press Enter to skip): " DASHBOARD_NAME
    export DASHBOARD_NAME
}

# Confirmation prompt
confirm_deletion() {
    if [ "$FORCE_DELETE" = true ]; then
        log WARN "Force delete mode enabled - skipping confirmation"
        return 0
    fi
    
    echo
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo
    [ -n "${LAMBDA_FUNCTION_NAME:-}" ] && echo "  🗑️  Lambda Function: $LAMBDA_FUNCTION_NAME"
    [ -n "${S3_BUCKET_NAME:-}" ] && echo "  🗑️  S3 Bucket: $S3_BUCKET_NAME (and all contents)"
    [ -n "${SNS_TOPIC_NAME:-}" ] && echo "  🗑️  SNS Topic: $SNS_TOPIC_NAME"
    [ -n "${CONFIG_ROLE_NAME:-}" ] && echo "  🗑️  Config IAM Role: $CONFIG_ROLE_NAME"
    [ -n "${LAMBDA_ROLE_NAME:-}" ] && echo "  🗑️  Lambda IAM Role: $LAMBDA_ROLE_NAME"
    [ -n "${DASHBOARD_NAME:-}" ] && echo "  🗑️  CloudWatch Dashboard: $DASHBOARD_NAME"
    echo "  🗑️  Config Rules: security-group-ssh-restricted, s3-bucket-public-access-prohibited"
    echo "  🗑️  Config Recorder and Delivery Channel"
    echo
    
    read -rp "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log INFO "Cleanup cancelled by user"
        exit 0
    fi
    
    log WARN "User confirmed deletion. Proceeding with cleanup..."
}

# Stop and delete Config components
cleanup_aws_config() {
    log INFO "Cleaning up AWS Config components..."
    
    # Delete Config rules
    local rules=("security-group-ssh-restricted" "s3-bucket-public-access-prohibited")
    for rule in "${rules[@]}"; do
        if aws configservice describe-config-rules --config-rule-names "$rule" &>/dev/null; then
            # Delete remediation configuration first
            aws configservice delete-remediation-configuration \
                --config-rule-name "$rule" 2>/dev/null || true
            
            # Delete the rule
            aws configservice delete-config-rule \
                --config-rule-name "$rule" || \
                log WARN "Failed to delete Config rule: $rule"
            log SUCCESS "Deleted Config rule: $rule"
        else
            log INFO "Config rule not found: $rule"
        fi
    done
    
    # Stop configuration recorder
    if aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[?name==`default`]' --output text | grep -q default; then
        aws configservice stop-configuration-recorder \
            --configuration-recorder-name default || \
            log WARN "Failed to stop configuration recorder"
        log SUCCESS "Stopped configuration recorder"
        
        # Delete delivery channel
        aws configservice delete-delivery-channel \
            --delivery-channel-name default || \
            log WARN "Failed to delete delivery channel"
        log SUCCESS "Deleted delivery channel"
        
        # Delete configuration recorder
        aws configservice delete-configuration-recorder \
            --configuration-recorder-name default || \
            log WARN "Failed to delete configuration recorder"
        log SUCCESS "Deleted configuration recorder"
    else
        log INFO "Config recorder 'default' not found"
    fi
}

# Delete Lambda function
cleanup_lambda_function() {
    if [ -z "${LAMBDA_FUNCTION_NAME:-}" ]; then
        log INFO "Lambda function name not specified, skipping"
        return 0
    fi
    
    log INFO "Deleting Lambda function: $LAMBDA_FUNCTION_NAME"
    
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME" || \
            log WARN "Failed to delete Lambda function: $LAMBDA_FUNCTION_NAME"
        log SUCCESS "Deleted Lambda function: $LAMBDA_FUNCTION_NAME"
    else
        log INFO "Lambda function not found: $LAMBDA_FUNCTION_NAME"
    fi
}

# Delete SNS topic
cleanup_sns_topic() {
    if [ -z "${SNS_TOPIC_NAME:-}" ]; then
        log INFO "SNS topic name not specified, skipping"
        return 0
    fi
    
    log INFO "Deleting SNS topic: $SNS_TOPIC_NAME"
    
    local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    
    if aws sns get-topic-attributes --topic-arn "$topic_arn" &>/dev/null; then
        aws sns delete-topic --topic-arn "$topic_arn" || \
            log WARN "Failed to delete SNS topic: $SNS_TOPIC_NAME"
        log SUCCESS "Deleted SNS topic: $SNS_TOPIC_NAME"
    else
        log INFO "SNS topic not found: $SNS_TOPIC_NAME"
    fi
}

# Delete CloudWatch dashboard
cleanup_cloudwatch_dashboard() {
    if [ -z "${DASHBOARD_NAME:-}" ]; then
        log INFO "Dashboard name not specified, skipping"
        return 0
    fi
    
    log INFO "Deleting CloudWatch dashboard: $DASHBOARD_NAME"
    
    if aws cloudwatch describe-dashboards --dashboard-name-prefix "$DASHBOARD_NAME" --query 'DashboardEntries[0]' --output text | grep -q "$DASHBOARD_NAME"; then
        aws cloudwatch delete-dashboards --dashboard-names "$DASHBOARD_NAME" || \
            log WARN "Failed to delete CloudWatch dashboard: $DASHBOARD_NAME"
        log SUCCESS "Deleted CloudWatch dashboard: $DASHBOARD_NAME"
    else
        log INFO "CloudWatch dashboard not found: $DASHBOARD_NAME"
    fi
}

# Delete S3 bucket with contents
cleanup_s3_bucket() {
    if [ -z "${S3_BUCKET_NAME:-}" ]; then
        log INFO "S3 bucket name not specified, skipping"
        return 0
    fi
    
    log INFO "Deleting S3 bucket: $S3_BUCKET_NAME"
    
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
        # Delete all objects and versions
        log INFO "Removing all objects from bucket..."
        aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive || \
            log WARN "Some objects might not have been deleted"
        
        # Delete bucket versions if versioning is enabled
        aws s3api list-object-versions --bucket "$S3_BUCKET_NAME" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output text 2>/dev/null | while read -r key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ] && [ "$version_id" != "None" ]; then
                aws s3api delete-object --bucket "$S3_BUCKET_NAME" --key "$key" --version-id "$version_id" || true
            fi
        done
        
        # Delete delete markers
        aws s3api list-object-versions --bucket "$S3_BUCKET_NAME" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output text 2>/dev/null | while read -r key version_id; do
            if [ -n "$key" ] && [ -n "$version_id" ]; then
                aws s3api delete-object --bucket "$S3_BUCKET_NAME" --key "$key" --version-id "$version_id" || true
            fi
        done
        
        # Delete the bucket
        aws s3api delete-bucket --bucket "$S3_BUCKET_NAME" || \
            log WARN "Failed to delete S3 bucket: $S3_BUCKET_NAME"
        log SUCCESS "Deleted S3 bucket: $S3_BUCKET_NAME"
    else
        log INFO "S3 bucket not found: $S3_BUCKET_NAME"
    fi
}

# Delete IAM roles and policies
cleanup_iam_roles() {
    log INFO "Cleaning up IAM roles and policies..."
    
    # Clean up Lambda role
    if [ -n "${LAMBDA_ROLE_NAME:-}" ]; then
        if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
            local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${LAMBDA_ROLE_NAME}-Policy"
            
            # Detach custom policy
            aws iam detach-role-policy \
                --role-name "$LAMBDA_ROLE_NAME" \
                --policy-arn "$policy_arn" 2>/dev/null || true
            
            # Delete custom policy
            aws iam delete-policy --policy-arn "$policy_arn" 2>/dev/null || \
                log WARN "Failed to delete policy: ${LAMBDA_ROLE_NAME}-Policy"
            
            # Delete role
            aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" || \
                log WARN "Failed to delete Lambda role: $LAMBDA_ROLE_NAME"
            log SUCCESS "Deleted Lambda role: $LAMBDA_ROLE_NAME"
        else
            log INFO "Lambda role not found: $LAMBDA_ROLE_NAME"
        fi
    fi
    
    # Clean up Config role
    if [ -n "${CONFIG_ROLE_NAME:-}" ]; then
        if aws iam get-role --role-name "$CONFIG_ROLE_NAME" &>/dev/null; then
            # Detach AWS managed policy
            aws iam detach-role-policy \
                --role-name "$CONFIG_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole 2>/dev/null || true
            
            # Delete role
            aws iam delete-role --role-name "$CONFIG_ROLE_NAME" || \
                log WARN "Failed to delete Config role: $CONFIG_ROLE_NAME"
            log SUCCESS "Deleted Config role: $CONFIG_ROLE_NAME"
        else
            log INFO "Config role not found: $CONFIG_ROLE_NAME"
        fi
    fi
}

# Delete temporary files
cleanup_temp_files() {
    log INFO "Cleaning up temporary files..."
    
    local temp_files=(
        "${SCRIPT_DIR}/config-bucket-policy.json"
        "${SCRIPT_DIR}/config-trust-policy.json"
        "${SCRIPT_DIR}/lambda-trust-policy.json"
        "${SCRIPT_DIR}/lambda-remediation-policy.json"
        "${SCRIPT_DIR}/sg-remediation-function.py"
        "${SCRIPT_DIR}/sg-remediation-function.zip"
        "${SCRIPT_DIR}/s3-remediation-document.json"
        "${SCRIPT_DIR}/compliance-dashboard.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file" && log SUCCESS "Deleted temp file: $(basename "$file")" || \
                log WARN "Failed to delete temp file: $file"
        fi
    done
}

# Clean up any test resources
cleanup_test_resources() {
    log INFO "Checking for test resources..."
    
    # Look for test security groups created during testing
    local test_sgs
    test_sgs=$(aws ec2 describe-security-groups \
        --query 'SecurityGroups[?contains(GroupName, `test-sg-`)].GroupId' \
        --output text 2>/dev/null || true)
    
    if [ -n "$test_sgs" ]; then
        log WARN "Found test security groups: $test_sgs"
        for sg_id in $test_sgs; do
            # Check if we created it (look for our tags)
            if aws ec2 describe-tags --filters "Name=resource-id,Values=$sg_id" "Name=key,Values=Purpose" \
                --query 'Tags[?Value==`Testing`]' --output text | grep -q Testing; then
                aws ec2 delete-security-group --group-id "$sg_id" || \
                    log WARN "Failed to delete test security group: $sg_id"
                log SUCCESS "Deleted test security group: $sg_id"
            fi
        done
    fi
}

# Verification of cleanup
verify_cleanup() {
    log INFO "Verifying cleanup completion..."
    
    local issues=0
    
    # Check Lambda function
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ] && aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &>/dev/null; then
        log WARN "Lambda function still exists: $LAMBDA_FUNCTION_NAME"
        ((issues++))
    fi
    
    # Check S3 bucket
    if [ -n "${S3_BUCKET_NAME:-}" ] && aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
        log WARN "S3 bucket still exists: $S3_BUCKET_NAME"
        ((issues++))
    fi
    
    # Check Config recorder
    if aws configservice describe-configuration-recorders --query 'ConfigurationRecorders[?name==`default`]' --output text | grep -q default; then
        log WARN "Config recorder still exists"
        ((issues++))
    fi
    
    # Check IAM roles
    if [ -n "${CONFIG_ROLE_NAME:-}" ] && aws iam get-role --role-name "$CONFIG_ROLE_NAME" &>/dev/null; then
        log WARN "Config role still exists: $CONFIG_ROLE_NAME"
        ((issues++))
    fi
    
    if [ -n "${LAMBDA_ROLE_NAME:-}" ] && aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
        log WARN "Lambda role still exists: $LAMBDA_ROLE_NAME"
        ((issues++))
    fi
    
    if [ $issues -eq 0 ]; then
        log SUCCESS "Cleanup verification passed - all resources removed"
    else
        log WARN "Cleanup verification found $issues remaining resources"
        log WARN "Some resources may need manual cleanup"
    fi
}

# Main cleanup flow
main() {
    log INFO "Starting AWS Config Auto-Remediation cleanup..."
    
    # Load configuration or discover resources
    if ! load_configuration; then
        discover_resources_interactively
    fi
    
    # Confirm deletion
    confirm_deletion
    
    # Perform cleanup in correct order
    cleanup_test_resources
    cleanup_aws_config
    cleanup_lambda_function
    cleanup_sns_topic
    cleanup_cloudwatch_dashboard
    cleanup_s3_bucket
    cleanup_iam_roles
    cleanup_temp_files
    verify_cleanup
    
    # Remove configuration file
    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE" && log SUCCESS "Removed configuration file" || \
            log WARN "Failed to remove configuration file"
    fi
    
    # Print summary
    echo
    echo "================================================"
    echo "Cleanup Summary"
    echo "================================================"
    echo "✅ AWS Config components removed"
    echo "✅ Lambda function deleted"
    echo "✅ SNS topic deleted"
    echo "✅ CloudWatch dashboard deleted"
    echo "✅ S3 bucket and contents deleted"
    echo "✅ IAM roles and policies deleted"
    echo "✅ Temporary files cleaned up"
    echo
    echo "📋 Cleanup log: $LOG_FILE"
    echo
    echo "ℹ️  If you encounter any issues, you can:"
    echo "   1. Check the cleanup log for details"
    echo "   2. Manually delete remaining resources in AWS Console"
    echo "   3. Re-run this script with --force to skip confirmations"
    echo "================================================"
    
    log SUCCESS "Auto-remediation cleanup completed!"
}

# Handle script arguments
case "${1:-}" in
    --force)
        FORCE_DELETE=true
        log WARN "Force delete mode enabled"
        main
        ;;
    --list-only)
        log INFO "List mode - showing discovered resources without deletion"
        if load_configuration; then
            echo "Resources found in configuration:"
            [ -n "${LAMBDA_FUNCTION_NAME:-}" ] && echo "  Lambda Function: $LAMBDA_FUNCTION_NAME"
            [ -n "${S3_BUCKET_NAME:-}" ] && echo "  S3 Bucket: $S3_BUCKET_NAME"
            [ -n "${SNS_TOPIC_NAME:-}" ] && echo "  SNS Topic: $SNS_TOPIC_NAME"
            [ -n "${CONFIG_ROLE_NAME:-}" ] && echo "  Config Role: $CONFIG_ROLE_NAME"
            [ -n "${LAMBDA_ROLE_NAME:-}" ] && echo "  Lambda Role: $LAMBDA_ROLE_NAME"
            [ -n "${DASHBOARD_NAME:-}" ] && echo "  Dashboard: $DASHBOARD_NAME"
        else
            discover_resources_interactively
        fi
        exit 0
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo "Options:"
        echo "  --force      Skip confirmation prompts and force deletion"
        echo "  --list-only  Show resources that would be deleted without deleting them"
        echo "  --help       Show this help message"
        echo
        echo "This script removes all AWS Config Auto-Remediation resources."
        echo "It will prompt for confirmation unless --force is used."
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac