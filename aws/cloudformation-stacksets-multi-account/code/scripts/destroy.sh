#!/bin/bash

# Cleanup CloudFormation StackSets for Multi-Account Multi-Region Management
# This script safely removes all resources created by the deployment script

set -e
set -o pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "$ERROR_LOG"
    echo -e "${RED}ERROR: $1${NC}" >&2
}

log_success() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: $1" | tee -a "$LOG_FILE"
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: $1" | tee -a "$LOG_FILE"
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup failed. Check logs for details."
    log_error "Error log: $ERROR_LOG"
    log_error "Full log: $LOG_FILE"
    exit 1
}

trap cleanup_on_error ERR

# Confirmation prompt
confirm_destruction() {
    echo -e "${RED}⚠️  WARNING: This will permanently delete all StackSets and associated resources!${NC}"
    echo -e "${RED}   This includes:${NC}"
    echo -e "${RED}   - All stack instances across multiple accounts and regions${NC}"
    echo -e "${RED}   - CloudTrail logs and audit buckets${NC}"
    echo -e "${RED}   - GuardDuty detectors${NC}"
    echo -e "${RED}   - IAM policies and roles${NC}"
    echo -e "${RED}   - Monitoring and alerting resources${NC}"
    echo
    
    if [ "$SKIP_CONFIRMATION" != "true" ]; then
        read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [ ! -f "$DEPLOYMENT_INFO_FILE" ]; then
        log_error "Deployment info file not found: $DEPLOYMENT_INFO_FILE"
        log_error "Please provide the following information manually:"
        
        read -p "StackSet Name: " STACKSET_NAME
        read -p "Execution Role StackSet Name: " EXECUTION_ROLE_STACKSET
        read -p "Template Bucket Name: " TEMPLATE_BUCKET
        read -p "Management Account ID: " MANAGEMENT_ACCOUNT_ID
        read -p "Target Regions (comma-separated): " TARGET_REGIONS
        read -p "Target Accounts (comma-separated): " TARGET_ACCOUNTS
        read -p "Alert Topic ARN: " ALERT_TOPIC_ARN
        read -p "AWS Region: " AWS_REGION
        
        export STACKSET_NAME EXECUTION_ROLE_STACKSET TEMPLATE_BUCKET MANAGEMENT_ACCOUNT_ID
        export TARGET_REGIONS TARGET_ACCOUNTS ALERT_TOPIC_ARN AWS_REGION
    else
        # Load from deployment info file
        export STACKSET_NAME=$(jq -r '.stackset_name' "$DEPLOYMENT_INFO_FILE")
        export EXECUTION_ROLE_STACKSET=$(jq -r '.execution_role_stackset' "$DEPLOYMENT_INFO_FILE")
        export TEMPLATE_BUCKET=$(jq -r '.template_bucket' "$DEPLOYMENT_INFO_FILE")
        export MANAGEMENT_ACCOUNT_ID=$(jq -r '.management_account_id' "$DEPLOYMENT_INFO_FILE")
        export TARGET_REGIONS=$(jq -r '.target_regions' "$DEPLOYMENT_INFO_FILE")
        export TARGET_ACCOUNTS=$(jq -r '.target_accounts' "$DEPLOYMENT_INFO_FILE")
        export ALERT_TOPIC_ARN=$(jq -r '.alert_topic_arn' "$DEPLOYMENT_INFO_FILE")
        export AWS_REGION=$(jq -r '.aws_region' "$DEPLOYMENT_INFO_FILE")
        
        log_success "Deployment information loaded"
    fi
    
    log_info "Cleanup configuration:"
    log_info "  StackSet Name: $STACKSET_NAME"
    log_info "  Execution Role StackSet: $EXECUTION_ROLE_STACKSET"
    log_info "  Template Bucket: $TEMPLATE_BUCKET"
    log_info "  Management Account: $MANAGEMENT_ACCOUNT_ID"
    log_info "  Target Regions: $TARGET_REGIONS"
    log_info "  Target Accounts: $TARGET_ACCOUNTS"
    log_info "  AWS Region: $AWS_REGION"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Verify we're in the correct account
    local current_account=$(aws sts get-caller-identity --query Account --output text)
    if [ "$current_account" != "$MANAGEMENT_ACCOUNT_ID" ]; then
        log_error "Current account ($current_account) does not match management account ($MANAGEMENT_ACCOUNT_ID)"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Wait for operation completion with timeout
wait_for_operation() {
    local stackset_name=$1
    local operation_id=$2
    local timeout=${3:-3600}  # 1 hour default timeout
    local start_time=$(date +%s)
    
    log_info "Waiting for operation to complete: $operation_id"
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt $timeout ]; then
            log_error "Operation timed out after $timeout seconds"
            return 1
        fi
        
        local status=$(aws cloudformation describe-stack-set-operation \
            --stack-set-name "$stackset_name" \
            --operation-id "$operation_id" \
            --query 'Operation.Status' --output text 2>/dev/null || echo "UNKNOWN")
        
        case "$status" in
            "SUCCEEDED")
                log_success "Operation completed successfully"
                return 0
                ;;
            "FAILED"|"STOPPED")
                log_error "Operation failed with status: $status"
                return 1
                ;;
            "RUNNING"|"STOPPING")
                log_info "Operation in progress... ($elapsed seconds elapsed)"
                sleep 30
                ;;
            *)
                log_warning "Unknown operation status: $status"
                sleep 30
                ;;
        esac
    done
}

# Delete governance StackSet instances
delete_governance_instances() {
    log_info "Deleting governance StackSet instances..."
    
    # Check if StackSet exists
    if ! aws cloudformation describe-stack-set --stack-set-name "$STACKSET_NAME" &>/dev/null; then
        log_warning "Governance StackSet does not exist: $STACKSET_NAME"
        return 0
    fi
    
    # List existing instances
    local instances=$(aws cloudformation list-stack-instances \
        --stack-set-name "$STACKSET_NAME" \
        --query 'Summaries[].{Account:Account,Region:Region}' \
        --output json)
    
    if [ "$instances" = "[]" ]; then
        log_info "No governance StackSet instances to delete"
        return 0
    fi
    
    local instance_count=$(echo "$instances" | jq length)
    log_info "Found $instance_count governance StackSet instances to delete"
    
    # Delete instances by account and region
    local accounts=$(echo "$instances" | jq -r '.[].Account' | sort -u | tr '\n' ',' | sed 's/,$//')
    local regions=$(echo "$instances" | jq -r '.[].Region' | sort -u | tr '\n' ',' | sed 's/,$//')
    
    if [ -n "$accounts" ] && [ -n "$regions" ]; then
        local operation_id=$(aws cloudformation delete-stack-instances \
            --stack-set-name "$STACKSET_NAME" \
            --accounts "$accounts" \
            --regions "$regions" \
            --retain-stacks false \
            --operation-preferences RegionConcurrencyType=PARALLEL,MaxConcurrentPercentage=100,FailureTolerancePercentage=10 \
            --query 'OperationId' --output text)
        
        if [ -n "$operation_id" ]; then
            log_info "Deleting instances with operation ID: $operation_id"
            wait_for_operation "$STACKSET_NAME" "$operation_id"
        fi
    fi
    
    log_success "Governance StackSet instances deleted"
}

# Delete governance StackSet
delete_governance_stackset() {
    log_info "Deleting governance StackSet..."
    
    # Check if StackSet exists
    if ! aws cloudformation describe-stack-set --stack-set-name "$STACKSET_NAME" &>/dev/null; then
        log_warning "Governance StackSet does not exist: $STACKSET_NAME"
        return 0
    fi
    
    # Verify no instances remain
    local remaining_instances=$(aws cloudformation list-stack-instances \
        --stack-set-name "$STACKSET_NAME" \
        --query 'length(Summaries[])' --output text)
    
    if [ "$remaining_instances" != "0" ]; then
        log_error "Cannot delete StackSet: $remaining_instances instances still exist"
        return 1
    fi
    
    # Delete the StackSet
    aws cloudformation delete-stack-set --stack-set-name "$STACKSET_NAME"
    
    log_success "Governance StackSet deleted: $STACKSET_NAME"
}

# Delete execution role StackSet instances
delete_execution_role_instances() {
    log_info "Deleting execution role StackSet instances..."
    
    # Check if StackSet exists
    if ! aws cloudformation describe-stack-set --stack-set-name "$EXECUTION_ROLE_STACKSET" &>/dev/null; then
        log_warning "Execution role StackSet does not exist: $EXECUTION_ROLE_STACKSET"
        return 0
    fi
    
    # List existing instances
    local instances=$(aws cloudformation list-stack-instances \
        --stack-set-name "$EXECUTION_ROLE_STACKSET" \
        --query 'Summaries[].{Account:Account,Region:Region}' \
        --output json)
    
    if [ "$instances" = "[]" ]; then
        log_info "No execution role StackSet instances to delete"
        return 0
    fi
    
    local instance_count=$(echo "$instances" | jq length)
    log_info "Found $instance_count execution role StackSet instances to delete"
    
    # Delete instances
    local accounts=$(echo "$instances" | jq -r '.[].Account' | sort -u | tr '\n' ',' | sed 's/,$//')
    local regions=$(echo "$instances" | jq -r '.[].Region' | sort -u | tr '\n' ',' | sed 's/,$//')
    
    if [ -n "$accounts" ] && [ -n "$regions" ]; then
        local operation_id=$(aws cloudformation delete-stack-instances \
            --stack-set-name "$EXECUTION_ROLE_STACKSET" \
            --accounts "$accounts" \
            --regions "$regions" \
            --retain-stacks false \
            --query 'OperationId' --output text)
        
        if [ -n "$operation_id" ]; then
            log_info "Deleting execution role instances with operation ID: $operation_id"
            wait_for_operation "$EXECUTION_ROLE_STACKSET" "$operation_id"
        fi
    fi
    
    log_success "Execution role StackSet instances deleted"
}

# Delete execution role StackSet
delete_execution_role_stackset() {
    log_info "Deleting execution role StackSet..."
    
    # Check if StackSet exists
    if ! aws cloudformation describe-stack-set --stack-set-name "$EXECUTION_ROLE_STACKSET" &>/dev/null; then
        log_warning "Execution role StackSet does not exist: $EXECUTION_ROLE_STACKSET"
        return 0
    fi
    
    # Verify no instances remain
    local remaining_instances=$(aws cloudformation list-stack-instances \
        --stack-set-name "$EXECUTION_ROLE_STACKSET" \
        --query 'length(Summaries[])' --output text)
    
    if [ "$remaining_instances" != "0" ]; then
        log_error "Cannot delete execution role StackSet: $remaining_instances instances still exist"
        return 1
    fi
    
    # Delete the StackSet
    aws cloudformation delete-stack-set --stack-set-name "$EXECUTION_ROLE_STACKSET"
    
    log_success "Execution role StackSet deleted: $EXECUTION_ROLE_STACKSET"
}

# Delete monitoring resources
delete_monitoring_resources() {
    log_info "Deleting monitoring resources..."
    
    # Delete CloudWatch alarm
    local alarm_name="StackSetOperationFailure-${STACKSET_NAME}"
    if aws cloudwatch describe-alarms --alarm-names "$alarm_name" &>/dev/null; then
        aws cloudwatch delete-alarms --alarm-names "$alarm_name"
        log_info "Deleted CloudWatch alarm: $alarm_name"
    fi
    
    # Delete SNS topic
    if [ -n "$ALERT_TOPIC_ARN" ] && [ "$ALERT_TOPIC_ARN" != "null" ]; then
        aws sns delete-topic --topic-arn "$ALERT_TOPIC_ARN" || true
        log_info "Deleted SNS topic: $ALERT_TOPIC_ARN"
    fi
    
    # Delete CloudWatch dashboard (if exists)
    local dashboard_name="StackSet-Monitoring-$(echo "$STACKSET_NAME" | sed 's/.*-//')"
    if aws cloudwatch describe-dashboards --dashboard-names "$dashboard_name" &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name"
        log_info "Deleted CloudWatch dashboard: $dashboard_name"
    fi
    
    log_success "Monitoring resources deleted"
}

# Delete IAM roles and policies
delete_iam_resources() {
    log_info "Deleting IAM roles and policies..."
    
    # Delete StackSet administrator role
    local admin_role="AWSCloudFormationStackSetAdministrator"
    if aws iam get-role --role-name "$admin_role" &>/dev/null; then
        # Detach policy first
        local policy_arn="arn:aws:iam::${MANAGEMENT_ACCOUNT_ID}:policy/AWSCloudFormationStackSetAdministratorPolicy"
        aws iam detach-role-policy --role-name "$admin_role" --policy-arn "$policy_arn" || true
        
        # Delete role
        aws iam delete-role --role-name "$admin_role" || true
        log_info "Deleted IAM role: $admin_role"
    fi
    
    # Delete StackSet administrator policy
    local policy_arn="arn:aws:iam::${MANAGEMENT_ACCOUNT_ID}:policy/AWSCloudFormationStackSetAdministratorPolicy"
    if aws iam get-policy --policy-arn "$policy_arn" &>/dev/null; then
        aws iam delete-policy --policy-arn "$policy_arn" || true
        log_info "Deleted IAM policy: $policy_arn"
    fi
    
    log_success "IAM resources deleted"
}

# Delete S3 template bucket
delete_template_bucket() {
    log_info "Deleting S3 template bucket..."
    
    if [ -z "$TEMPLATE_BUCKET" ] || [ "$TEMPLATE_BUCKET" = "null" ]; then
        log_warning "No template bucket specified"
        return 0
    fi
    
    # Check if bucket exists
    if ! aws s3 ls "s3://${TEMPLATE_BUCKET}" &>/dev/null; then
        log_warning "Template bucket does not exist: $TEMPLATE_BUCKET"
        return 0
    fi
    
    # Delete all objects in the bucket
    aws s3 rm "s3://${TEMPLATE_BUCKET}" --recursive || true
    
    # Delete all versions (if versioning is enabled)
    aws s3api delete-objects --bucket "$TEMPLATE_BUCKET" \
        --delete "$(aws s3api list-object-versions --bucket "$TEMPLATE_BUCKET" \
        --output json --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" || true
    
    # Delete delete markers
    aws s3api delete-objects --bucket "$TEMPLATE_BUCKET" \
        --delete "$(aws s3api list-object-versions --bucket "$TEMPLATE_BUCKET" \
        --output json --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" || true
    
    # Delete the bucket
    aws s3 rb "s3://${TEMPLATE_BUCKET}" --force || true
    
    log_success "Template bucket deleted: $TEMPLATE_BUCKET"
}

# Disable Organizations trusted access
disable_organizations_trusted_access() {
    log_info "Disabling Organizations trusted access..."
    
    # Check if Organizations is available
    if ! aws organizations describe-organization &>/dev/null; then
        log_warning "AWS Organizations not available"
        return 0
    fi
    
    # Disable trusted access for CloudFormation StackSets
    aws organizations disable-aws-service-access \
        --service-principal stacksets.cloudformation.amazonaws.com || true
    
    log_info "Disabled Organizations trusted access for CloudFormation StackSets"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment info file
    if [ -f "$DEPLOYMENT_INFO_FILE" ]; then
        rm -f "$DEPLOYMENT_INFO_FILE"
        log_info "Removed deployment info file"
    fi
    
    # Remove temporary files
    rm -f "$SCRIPT_DIR"/*.json.tmp
    rm -f "$SCRIPT_DIR"/*.yaml.tmp
    rm -f "$SCRIPT_DIR"/*.log.tmp
    
    log_success "Local files cleaned up"
}

# Validation
validate_cleanup() {
    log_info "Validating cleanup..."
    
    local cleanup_errors=0
    
    # Check if StackSets still exist
    if aws cloudformation describe-stack-set --stack-set-name "$STACKSET_NAME" &>/dev/null; then
        log_error "Governance StackSet still exists: $STACKSET_NAME"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    if aws cloudformation describe-stack-set --stack-set-name "$EXECUTION_ROLE_STACKSET" &>/dev/null; then
        log_error "Execution role StackSet still exists: $EXECUTION_ROLE_STACKSET"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check if S3 bucket still exists
    if [ -n "$TEMPLATE_BUCKET" ] && aws s3 ls "s3://${TEMPLATE_BUCKET}" &>/dev/null; then
        log_error "Template bucket still exists: $TEMPLATE_BUCKET"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check if IAM role still exists
    if aws iam get-role --role-name AWSCloudFormationStackSetAdministrator &>/dev/null; then
        log_error "StackSet administrator role still exists"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    if [ $cleanup_errors -eq 0 ]; then
        log_success "Cleanup validation completed successfully"
        return 0
    else
        log_error "Cleanup validation failed with $cleanup_errors errors"
        return 1
    fi
}

# Main cleanup function
main() {
    log_info "Starting CloudFormation StackSets cleanup..."
    
    confirm_destruction
    load_deployment_info
    check_prerequisites
    
    # Cleanup in reverse order of creation
    delete_governance_instances
    delete_governance_stackset
    delete_execution_role_instances
    delete_execution_role_stackset
    delete_monitoring_resources
    delete_iam_resources
    delete_template_bucket
    disable_organizations_trusted_access
    cleanup_local_files
    
    # Validation
    if validate_cleanup; then
        log_success "CloudFormation StackSets cleanup completed successfully!"
        log_info "Cleanup logs available at: $LOG_FILE"
        
        echo
        echo -e "${GREEN}🎉 Cleanup Summary:${NC}"
        echo -e "${GREEN}   All StackSets and associated resources have been deleted${NC}"
        echo -e "${GREEN}   IAM roles and policies have been cleaned up${NC}"
        echo -e "${GREEN}   S3 template bucket has been removed${NC}"
        echo -e "${GREEN}   Monitoring resources have been deleted${NC}"
        echo
        echo -e "${BLUE}Cleanup completed successfully!${NC}"
    else
        log_error "Cleanup completed with errors. Please check the logs."
        exit 1
    fi
}

# Handle command line arguments
case "${1:-}" in
    --skip-confirmation)
        export SKIP_CONFIRMATION="true"
        shift
        ;;
    --help|-h)
        echo "Usage: $0 [--skip-confirmation] [--help]"
        echo
        echo "Options:"
        echo "  --skip-confirmation  Skip the confirmation prompt"
        echo "  --help, -h          Show this help message"
        echo
        echo "This script will delete all CloudFormation StackSets and associated resources."
        echo "Make sure you have the necessary permissions and that you're in the correct AWS account."
        exit 0
        ;;
esac

# Run main function
main "$@"