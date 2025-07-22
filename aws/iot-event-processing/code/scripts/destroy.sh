#!/bin/bash

# IoT Rules Engine Event Processing - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TEMP_DIR="/tmp/iot-rules-cleanup-$$"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1" | tee -a "$LOG_FILE"
    fi
}

# Cleanup function for temporary files
cleanup() {
    log_debug "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    log_debug "Cleanup completed"
}

# Error handler
error_handler() {
    local line_number=$1
    log_error "Script failed at line $line_number"
    log_error "Check the log file for details: $LOG_FILE"
    log_error "Some resources may not have been cleaned up. Please check AWS console."
    cleanup
    exit 1
}

# Set up error handling
trap 'error_handler ${LINENO}' ERR
trap cleanup EXIT

# Help function
show_help() {
    cat << EOF
IoT Rules Engine Event Processing - Cleanup Script

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -d, --debug         Enable debug logging
    -y, --yes           Skip confirmation prompts
    -p, --prefix PREFIX Custom resource prefix (default: factory)
    --dry-run          Show what would be deleted without removing resources
    --force            Force cleanup without confirmation
    --partial          Allow partial cleanup (continue on errors)

EXAMPLES:
    $0                  # Clean up with default settings
    $0 -d -y            # Clean up with debug logging, skip confirmations
    $0 --prefix myorg   # Clean up with custom prefix
    $0 --dry-run        # Show cleanup plan without removing resources
    $0 --force          # Force cleanup without any prompts

EOF
}

# Parse command line arguments
DRY_RUN=false
DEBUG=false
SKIP_CONFIRM=false
FORCE_CLEANUP=false
PARTIAL_CLEANUP=false
RESOURCE_PREFIX="factory"

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--debug)
            DEBUG=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRM=true
            shift
            ;;
        -p|--prefix)
            RESOURCE_PREFIX="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_CLEANUP=true
            SKIP_CONFIRM=true
            shift
            ;;
        --partial)
            PARTIAL_CLEANUP=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Initialize logging
echo "=== IoT Rules Engine Event Processing Cleanup ===" > "$LOG_FILE"
echo "Started at: $(date)" >> "$LOG_FILE"
echo "Script: $0" >> "$LOG_FILE"
echo "Arguments: $*" >> "$LOG_FILE"
echo "User: $(whoami)" >> "$LOG_FILE"
echo "Working directory: $(pwd)" >> "$LOG_FILE"

log "Starting IoT Rules Engine cleanup..."

# Create temporary directory
mkdir -p "$TEMP_DIR"
log_debug "Created temporary directory: $TEMP_DIR"

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Get AWS info
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    
    if [[ -z "$region" ]]; then
        log_error "AWS region not configured. Please run 'aws configure'."
        exit 1
    fi
    
    log "Prerequisites check passed"
    log "AWS Account ID: $account_id"
    log "AWS Region: $region"
    
    # Export for use in script
    export AWS_ACCOUNT_ID="$account_id"
    export AWS_REGION="$region"
}

# Discover existing resources
discover_resources() {
    log "Discovering existing resources with prefix: $RESOURCE_PREFIX"
    
    # Initialize arrays for discovered resources
    declare -a IOT_RULES
    declare -a LAMBDA_FUNCTIONS
    declare -a DDB_TABLES
    declare -a SNS_TOPICS
    declare -a IAM_ROLES
    declare -a IAM_POLICIES
    declare -a LOG_GROUPS
    
    # Find IoT rules
    log_debug "Searching for IoT rules..."
    if aws iot list-topic-rules --query 'rules[].ruleName' --output text &>/dev/null; then
        local rules=$(aws iot list-topic-rules --query 'rules[].ruleName' --output text)
        for rule in $rules; do
            if [[ "$rule" == *"Rule" ]]; then
                IOT_RULES+=("$rule")
                log_debug "Found IoT rule: $rule"
            fi
        done
    fi
    
    # Find Lambda functions
    log_debug "Searching for Lambda functions..."
    if aws lambda list-functions --query 'Functions[].FunctionName' --output text &>/dev/null; then
        local functions=$(aws lambda list-functions --query 'Functions[].FunctionName' --output text)
        for func in $functions; do
            if [[ "$func" == *"${RESOURCE_PREFIX}"* ]]; then
                LAMBDA_FUNCTIONS+=("$func")
                log_debug "Found Lambda function: $func"
            fi
        done
    fi
    
    # Find DynamoDB tables
    log_debug "Searching for DynamoDB tables..."
    if aws dynamodb list-tables --query 'TableNames' --output text &>/dev/null; then
        local tables=$(aws dynamodb list-tables --query 'TableNames' --output text)
        for table in $tables; do
            if [[ "$table" == *"${RESOURCE_PREFIX}"* ]]; then
                DDB_TABLES+=("$table")
                log_debug "Found DynamoDB table: $table"
            fi
        done
    fi
    
    # Find SNS topics
    log_debug "Searching for SNS topics..."
    if aws sns list-topics --query 'Topics[].TopicArn' --output text &>/dev/null; then
        local topics=$(aws sns list-topics --query 'Topics[].TopicArn' --output text)
        for topic in $topics; do
            if [[ "$topic" == *"${RESOURCE_PREFIX}"* ]]; then
                SNS_TOPICS+=("$topic")
                log_debug "Found SNS topic: $topic"
            fi
        done
    fi
    
    # Find IAM roles
    log_debug "Searching for IAM roles..."
    if aws iam list-roles --query 'Roles[].RoleName' --output text &>/dev/null; then
        local roles=$(aws iam list-roles --query 'Roles[].RoleName' --output text)
        for role in $roles; do
            if [[ "$role" == *"${RESOURCE_PREFIX}"* ]]; then
                IAM_ROLES+=("$role")
                log_debug "Found IAM role: $role"
            fi
        done
    fi
    
    # Find IAM policies
    log_debug "Searching for IAM policies..."
    if aws iam list-policies --scope Local --query 'Policies[].PolicyName' --output text &>/dev/null; then
        local policies=$(aws iam list-policies --scope Local --query 'Policies[].PolicyName' --output text)
        for policy in $policies; do
            if [[ "$policy" == *"${RESOURCE_PREFIX}"* ]]; then
                IAM_POLICIES+=("$policy")
                log_debug "Found IAM policy: $policy"
            fi
        done
    fi
    
    # Find CloudWatch log groups
    log_debug "Searching for CloudWatch log groups..."
    if aws logs describe-log-groups --query 'logGroups[].logGroupName' --output text &>/dev/null; then
        local log_groups=$(aws logs describe-log-groups --query 'logGroups[].logGroupName' --output text)
        for log_group in $log_groups; do
            if [[ "$log_group" == "/aws/iot/rules" ]] || [[ "$log_group" == *"${RESOURCE_PREFIX}"* ]]; then
                LOG_GROUPS+=("$log_group")
                log_debug "Found CloudWatch log group: $log_group"
            fi
        done
    fi
    
    # Export discovered resources
    export DISCOVERED_IOT_RULES="${IOT_RULES[*]}"
    export DISCOVERED_LAMBDA_FUNCTIONS="${LAMBDA_FUNCTIONS[*]}"
    export DISCOVERED_DDB_TABLES="${DDB_TABLES[*]}"
    export DISCOVERED_SNS_TOPICS="${SNS_TOPICS[*]}"
    export DISCOVERED_IAM_ROLES="${IAM_ROLES[*]}"
    export DISCOVERED_IAM_POLICIES="${IAM_POLICIES[*]}"
    export DISCOVERED_LOG_GROUPS="${LOG_GROUPS[*]}"
    
    log "Resource discovery completed"
}

# Safe delete function with error handling
safe_delete() {
    local resource_type="$1"
    local resource_name="$2"
    local delete_command="$3"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete $resource_type: $resource_name"
        return 0
    fi
    
    log "Deleting $resource_type: $resource_name"
    
    if [[ "$PARTIAL_CLEANUP" == "true" ]]; then
        # Continue on errors if partial cleanup is enabled
        if eval "$delete_command" 2>/dev/null; then
            log "✅ Successfully deleted $resource_type: $resource_name"
        else
            log_warn "Failed to delete $resource_type: $resource_name (continuing with partial cleanup)"
        fi
    else
        # Exit on errors if partial cleanup is disabled
        if eval "$delete_command"; then
            log "✅ Successfully deleted $resource_type: $resource_name"
        else
            log_error "Failed to delete $resource_type: $resource_name"
            return 1
        fi
    fi
}

# Delete IoT rules
delete_iot_rules() {
    log "Deleting IoT rules..."
    
    if [[ -n "$DISCOVERED_IOT_RULES" ]]; then
        for rule in $DISCOVERED_IOT_RULES; do
            safe_delete "IoT rule" "$rule" "aws iot delete-topic-rule --rule-name '$rule'"
        done
    else
        log "No IoT rules found to delete"
    fi
}

# Delete Lambda functions
delete_lambda_functions() {
    log "Deleting Lambda functions..."
    
    if [[ -n "$DISCOVERED_LAMBDA_FUNCTIONS" ]]; then
        for func in $DISCOVERED_LAMBDA_FUNCTIONS; do
            # Remove Lambda permissions first
            log_debug "Removing Lambda permissions for function: $func"
            aws lambda remove-permission \
                --function-name "$func" \
                --statement-id "iot-rules-permission" \
                2>/dev/null || log_debug "No permissions to remove for $func"
            
            safe_delete "Lambda function" "$func" "aws lambda delete-function --function-name '$func'"
        done
    else
        log "No Lambda functions found to delete"
    fi
}

# Delete DynamoDB tables
delete_dynamodb_tables() {
    log "Deleting DynamoDB tables..."
    
    if [[ -n "$DISCOVERED_DDB_TABLES" ]]; then
        for table in $DISCOVERED_DDB_TABLES; do
            safe_delete "DynamoDB table" "$table" "aws dynamodb delete-table --table-name '$table'"
            
            # Wait for table deletion if not in dry run mode
            if [[ "$DRY_RUN" != "true" ]]; then
                log "Waiting for table deletion to complete: $table"
                aws dynamodb wait table-not-exists --table-name "$table" 2>/dev/null || true
            fi
        done
    else
        log "No DynamoDB tables found to delete"
    fi
}

# Delete SNS topics
delete_sns_topics() {
    log "Deleting SNS topics..."
    
    if [[ -n "$DISCOVERED_SNS_TOPICS" ]]; then
        for topic in $DISCOVERED_SNS_TOPICS; do
            safe_delete "SNS topic" "$topic" "aws sns delete-topic --topic-arn '$topic'"
        done
    else
        log "No SNS topics found to delete"
    fi
}

# Delete IAM roles and policies
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    # Delete IAM roles
    if [[ -n "$DISCOVERED_IAM_ROLES" ]]; then
        for role in $DISCOVERED_IAM_ROLES; do
            log_debug "Processing IAM role: $role"
            
            # Detach managed policies
            local attached_policies
            attached_policies=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            
            for policy_arn in $attached_policies; do
                log_debug "Detaching policy from role: $policy_arn"
                aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" 2>/dev/null || true
            done
            
            # Delete inline policies
            local inline_policies
            inline_policies=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames' --output text 2>/dev/null || echo "")
            
            for policy_name in $inline_policies; do
                log_debug "Deleting inline policy from role: $policy_name"
                aws iam delete-role-policy --role-name "$role" --policy-name "$policy_name" 2>/dev/null || true
            done
            
            safe_delete "IAM role" "$role" "aws iam delete-role --role-name '$role'"
        done
    else
        log "No IAM roles found to delete"
    fi
    
    # Delete IAM policies
    if [[ -n "$DISCOVERED_IAM_POLICIES" ]]; then
        for policy in $DISCOVERED_IAM_POLICIES; do
            local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy}"
            safe_delete "IAM policy" "$policy" "aws iam delete-policy --policy-arn '$policy_arn'"
        done
    else
        log "No IAM policies found to delete"
    fi
}

# Delete CloudWatch log groups
delete_cloudwatch_logs() {
    log "Deleting CloudWatch log groups..."
    
    if [[ -n "$DISCOVERED_LOG_GROUPS" ]]; then
        for log_group in $DISCOVERED_LOG_GROUPS; do
            safe_delete "CloudWatch log group" "$log_group" "aws logs delete-log-group --log-group-name '$log_group'"
        done
    else
        log "No CloudWatch log groups found to delete"
    fi
}

# Display cleanup summary
display_cleanup_summary() {
    log "=== Cleanup Summary ==="
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "AWS Region: $AWS_REGION"
    log "Resource Prefix: $RESOURCE_PREFIX"
    log ""
    log "Resources processed for deletion:"
    
    if [[ -n "$DISCOVERED_IOT_RULES" ]]; then
        log "  IoT Rules: $DISCOVERED_IOT_RULES"
    fi
    
    if [[ -n "$DISCOVERED_LAMBDA_FUNCTIONS" ]]; then
        log "  Lambda Functions: $DISCOVERED_LAMBDA_FUNCTIONS"
    fi
    
    if [[ -n "$DISCOVERED_DDB_TABLES" ]]; then
        log "  DynamoDB Tables: $DISCOVERED_DDB_TABLES"
    fi
    
    if [[ -n "$DISCOVERED_SNS_TOPICS" ]]; then
        log "  SNS Topics: $DISCOVERED_SNS_TOPICS"
    fi
    
    if [[ -n "$DISCOVERED_IAM_ROLES" ]]; then
        log "  IAM Roles: $DISCOVERED_IAM_ROLES"
    fi
    
    if [[ -n "$DISCOVERED_IAM_POLICIES" ]]; then
        log "  IAM Policies: $DISCOVERED_IAM_POLICIES"
    fi
    
    if [[ -n "$DISCOVERED_LOG_GROUPS" ]]; then
        log "  CloudWatch Log Groups: $DISCOVERED_LOG_GROUPS"
    fi
    
    log ""
    log "Cleanup completed successfully!"
}

# Confirmation prompt
confirm_cleanup() {
    if [[ "$SKIP_CONFIRM" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${RED}WARNING: This will permanently delete the following resources:${NC}"
    echo ""
    
    if [[ -n "$DISCOVERED_IOT_RULES" ]]; then
        echo "  IoT Rules: $DISCOVERED_IOT_RULES"
    fi
    
    if [[ -n "$DISCOVERED_LAMBDA_FUNCTIONS" ]]; then
        echo "  Lambda Functions: $DISCOVERED_LAMBDA_FUNCTIONS"
    fi
    
    if [[ -n "$DISCOVERED_DDB_TABLES" ]]; then
        echo "  DynamoDB Tables: $DISCOVERED_DDB_TABLES"
    fi
    
    if [[ -n "$DISCOVERED_SNS_TOPICS" ]]; then
        echo "  SNS Topics: $DISCOVERED_SNS_TOPICS"
    fi
    
    if [[ -n "$DISCOVERED_IAM_ROLES" ]]; then
        echo "  IAM Roles: $DISCOVERED_IAM_ROLES"
    fi
    
    if [[ -n "$DISCOVERED_IAM_POLICIES" ]]; then
        echo "  IAM Policies: $DISCOVERED_IAM_POLICIES"
    fi
    
    if [[ -n "$DISCOVERED_LOG_GROUPS" ]]; then
        echo "  CloudWatch Log Groups: $DISCOVERED_LOG_GROUPS"
    fi
    
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    if [[ "$FORCE_CLEANUP" == "true" ]]; then
        log "Force cleanup enabled - proceeding without confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to delete all these resources? (type 'yes' to confirm): " -r
    if [[ ! $REPLY == "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Last chance! Type 'DELETE' to proceed with cleanup: " -r
    if [[ ! $REPLY == "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check if any resources still exist
    if [[ -n "$DISCOVERED_IOT_RULES" ]]; then
        for rule in $DISCOVERED_IOT_RULES; do
            if aws iot get-topic-rule --rule-name "$rule" &>/dev/null; then
                log_warn "IoT rule still exists: $rule"
                ((cleanup_issues++))
            fi
        done
    fi
    
    if [[ -n "$DISCOVERED_LAMBDA_FUNCTIONS" ]]; then
        for func in $DISCOVERED_LAMBDA_FUNCTIONS; do
            if aws lambda get-function --function-name "$func" &>/dev/null; then
                log_warn "Lambda function still exists: $func"
                ((cleanup_issues++))
            fi
        done
    fi
    
    if [[ -n "$DISCOVERED_DDB_TABLES" ]]; then
        for table in $DISCOVERED_DDB_TABLES; do
            if aws dynamodb describe-table --table-name "$table" &>/dev/null; then
                log_warn "DynamoDB table still exists: $table"
                ((cleanup_issues++))
            fi
        done
    fi
    
    if [[ "$cleanup_issues" -gt 0 ]]; then
        log_warn "Cleanup verification found $cleanup_issues issues"
        log_warn "Please check the AWS console to verify resource deletion"
    else
        log "✅ Cleanup verification passed - all resources successfully deleted"
    fi
}

# Main cleanup function
main() {
    log "Starting IoT Rules Engine cleanup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Discover existing resources
    discover_resources
    
    # Check if any resources were found
    if [[ -z "$DISCOVERED_IOT_RULES" && -z "$DISCOVERED_LAMBDA_FUNCTIONS" && -z "$DISCOVERED_DDB_TABLES" && -z "$DISCOVERED_SNS_TOPICS" && -z "$DISCOVERED_IAM_ROLES" && -z "$DISCOVERED_IAM_POLICIES" && -z "$DISCOVERED_LOG_GROUPS" ]]; then
        log "No resources found to clean up with prefix: $RESOURCE_PREFIX"
        log "Cleanup completed - nothing to do"
        return 0
    fi
    
    # Show cleanup plan and confirm
    confirm_cleanup
    
    # Delete resources in reverse order of creation
    delete_iot_rules
    delete_lambda_functions
    delete_dynamodb_tables
    delete_sns_topics
    delete_iam_resources
    delete_cloudwatch_logs
    
    # Verify cleanup completion
    verify_cleanup
    
    # Display summary
    display_cleanup_summary
    
    log "✅ IoT Rules Engine cleanup completed successfully!"
    log "Cleanup log saved to: $LOG_FILE"
}

# Run main function
main "$@"