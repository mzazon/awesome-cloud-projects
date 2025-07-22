#!/bin/bash

# =============================================================================
# AWS Operational Analytics with CloudWatch Insights - Cleanup Script
# =============================================================================
# This script safely removes all resources created by the operational analytics
# deployment, including CloudWatch resources, Lambda functions, IAM roles,
# and SNS topics.
# =============================================================================

set -euo pipefail

# Configuration variables
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly DRY_RUN="${DRY_RUN:-false}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warn() {
    log "WARN" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command '$1' not found. Please install it and try again."
        exit 1
    fi
}

check_aws_credentials() {
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid. Please run 'aws configure' first."
        exit 1
    fi
}

validate_region() {
    local region="$1"
    if ! aws ec2 describe-regions --region-names "$region" &> /dev/null; then
        log_error "Invalid AWS region: $region"
        exit 1
    fi
}

confirm_destruction() {
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        log_warn "Force destruction enabled - skipping confirmation"
        return 0
    fi
    
    echo
    log_warn "⚠️  WARNING: This will permanently delete the following resources:"
    echo
    
    # List resources that will be deleted
    local resources_found=0
    
    # Check Lambda function
    if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME:-}" &> /dev/null; then
        log_warn "  • Lambda Function: ${LAMBDA_FUNCTION_NAME:-}"
        ((resources_found++))
    fi
    
    # Check Log Group
    if [[ -n "${LOG_GROUP_NAME:-}" ]] && aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
        log_warn "  • CloudWatch Log Group: $LOG_GROUP_NAME"
        ((resources_found++))
    fi
    
    # Check SNS Topic
    if [[ -n "${SNS_TOPIC_NAME:-}" ]] && aws sns get-topic-attributes --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" &> /dev/null; then
        log_warn "  • SNS Topic: $SNS_TOPIC_NAME"
        ((resources_found++))
    fi
    
    # Check Dashboard
    if [[ -n "${DASHBOARD_NAME:-}" ]] && aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" &> /dev/null; then
        log_warn "  • CloudWatch Dashboard: $DASHBOARD_NAME"
        ((resources_found++))
    fi
    
    # Check IAM Role
    if [[ -n "${IAM_ROLE_NAME:-}" ]] && aws iam get-role --role-name "$IAM_ROLE_NAME" &> /dev/null; then
        log_warn "  • IAM Role: $IAM_ROLE_NAME"
        ((resources_found++))
    fi
    
    if [[ $resources_found -eq 0 ]]; then
        log_info "No resources found to delete based on current environment variables."
        log_info "You may need to set the resource names manually or re-run with discovery mode."
        return 1
    fi
    
    echo
    log_warn "This action cannot be undone!"
    echo
    
    # Multiple confirmation prompts for safety
    read -p "Are you sure you want to delete these resources? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    read -p "Please type 'DELETE' to confirm: " -r
    if [[ $REPLY != "DELETE" ]]; then
        log_info "Destruction cancelled - confirmation text did not match"
        exit 0
    fi
    
    log_warn "Proceeding with resource destruction..."
}

wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local max_attempts="${3:-30}"
    local check_interval="${4:-5}"
    
    log_info "Waiting for $resource_type '$resource_name' deletion..."
    
    for ((i=1; i<=max_attempts; i++)); do
        case "$resource_type" in
            "lambda")
                if ! aws lambda get-function --function-name "$resource_name" &> /dev/null; then
                    log_success "$resource_type '$resource_name' deleted successfully"
                    return 0
                fi
                ;;
            "log-group")
                if ! aws logs describe-log-groups --log-group-name-prefix "$resource_name" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$resource_name"; then
                    log_success "$resource_type '$resource_name' deleted successfully"
                    return 0
                fi
                ;;
            "iam-role")
                if ! aws iam get-role --role-name "$resource_name" &> /dev/null; then
                    log_success "$resource_type '$resource_name' deleted successfully"
                    return 0
                fi
                ;;
            *)
                log_error "Unknown resource type: $resource_type"
                return 1
                ;;
        esac
        
        if [[ $i -eq $max_attempts ]]; then
            log_warn "Timeout waiting for $resource_type '$resource_name' deletion"
            return 1
        fi
        
        log_info "Deletion attempt $i/$max_attempts, waiting ${check_interval}s..."
        sleep "$check_interval"
    done
}

# =============================================================================
# Resource Discovery Functions
# =============================================================================

discover_resources() {
    log_info "Discovering operational analytics resources..."
    
    # Try to discover resources by tags first
    local resources_found=0
    
    # Discover Lambda functions
    local lambda_functions
    lambda_functions=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `operational-analytics`) || contains(FunctionName, `log-generator`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$lambda_functions" ]]; then
        log_info "Found Lambda functions: $lambda_functions"
        export DISCOVERED_LAMBDA_FUNCTIONS="$lambda_functions"
        ((resources_found++))
    fi
    
    # Discover Log Groups
    local log_groups
    log_groups=$(aws logs describe-log-groups \
        --query 'logGroups[?contains(logGroupName, `operational-analytics`) || contains(logGroupName, `log-generator`)].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$log_groups" ]]; then
        log_info "Found log groups: $log_groups"
        export DISCOVERED_LOG_GROUPS="$log_groups"
        ((resources_found++))
    fi
    
    # Discover SNS Topics
    local sns_topics
    sns_topics=$(aws sns list-topics \
        --query 'Topics[?contains(TopicArn, `operational-alerts`)].TopicArn' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$sns_topics" ]]; then
        log_info "Found SNS topics: $sns_topics"
        export DISCOVERED_SNS_TOPICS="$sns_topics"
        ((resources_found++))
    fi
    
    # Discover CloudWatch Dashboards
    local dashboards
    dashboards=$(aws cloudwatch list-dashboards \
        --query 'DashboardEntries[?contains(DashboardName, `OperationalAnalytics`)].DashboardName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$dashboards" ]]; then
        log_info "Found dashboards: $dashboards"
        export DISCOVERED_DASHBOARDS="$dashboards"
        ((resources_found++))
    fi
    
    # Discover IAM Roles
    local iam_roles
    iam_roles=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `LogGenerator`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$iam_roles" ]]; then
        log_info "Found IAM roles: $iam_roles"
        export DISCOVERED_IAM_ROLES="$iam_roles"
        ((resources_found++))
    fi
    
    log_info "Resource discovery completed. Found $resources_found resource types."
    return $resources_found
}

# =============================================================================
# Resource Deletion Functions
# =============================================================================

delete_cloudwatch_alarms() {
    log_info "Deleting CloudWatch alarms..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete CloudWatch alarms"
        return 0
    fi
    
    # Find and delete alarms related to operational analytics
    local alarms
    alarms=$(aws cloudwatch describe-alarms \
        --query 'MetricAlarms[?contains(AlarmName, `HighErrorRate`) || contains(AlarmName, `LogIngestionAnomaly`) || contains(AlarmName, `HighLogVolume`)].AlarmName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$alarms" ]]; then
        for alarm in $alarms; do
            log_info "Deleting alarm: $alarm"
            aws cloudwatch delete-alarms --alarm-names "$alarm"
            log_success "Deleted alarm: $alarm"
        done
    else
        log_info "No CloudWatch alarms found"
    fi
}

delete_anomaly_detectors() {
    log_info "Deleting CloudWatch anomaly detectors..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete anomaly detectors"
        return 0
    fi
    
    # Delete anomaly detectors for log groups
    if [[ -n "${LOG_GROUP_NAME:-}" ]]; then
        if aws cloudwatch delete-anomaly-detector \
            --namespace "AWS/Logs" \
            --metric-name "IncomingBytes" \
            --dimensions Name=LogGroupName,Value="$LOG_GROUP_NAME" \
            --stat "Average" &> /dev/null; then
            log_success "Deleted anomaly detector for log group: $LOG_GROUP_NAME"
        else
            log_info "No anomaly detector found for log group: $LOG_GROUP_NAME"
        fi
    fi
    
    # Also check discovered log groups
    if [[ -n "${DISCOVERED_LOG_GROUPS:-}" ]]; then
        for log_group in $DISCOVERED_LOG_GROUPS; do
            if aws cloudwatch delete-anomaly-detector \
                --namespace "AWS/Logs" \
                --metric-name "IncomingBytes" \
                --dimensions Name=LogGroupName,Value="$log_group" \
                --stat "Average" &> /dev/null; then
                log_success "Deleted anomaly detector for log group: $log_group"
            fi
        done
    fi
}

delete_dashboards() {
    log_info "Deleting CloudWatch dashboards..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete CloudWatch dashboards"
        return 0
    fi
    
    # Delete specified dashboard
    if [[ -n "${DASHBOARD_NAME:-}" ]] && aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" &> /dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "$DASHBOARD_NAME"
        log_success "Deleted dashboard: $DASHBOARD_NAME"
    fi
    
    # Delete discovered dashboards
    if [[ -n "${DISCOVERED_DASHBOARDS:-}" ]]; then
        for dashboard in $DISCOVERED_DASHBOARDS; do
            aws cloudwatch delete-dashboards --dashboard-names "$dashboard"
            log_success "Deleted dashboard: $dashboard"
        done
    fi
    
    if [[ -z "${DASHBOARD_NAME:-}" && -z "${DISCOVERED_DASHBOARDS:-}" ]]; then
        log_info "No dashboards found to delete"
    fi
}

delete_metric_filters() {
    log_info "Deleting CloudWatch metric filters..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete metric filters"
        return 0
    fi
    
    local log_groups_to_check=()
    
    # Add specified log group
    if [[ -n "${LOG_GROUP_NAME:-}" ]]; then
        log_groups_to_check+=("$LOG_GROUP_NAME")
    fi
    
    # Add discovered log groups
    if [[ -n "${DISCOVERED_LOG_GROUPS:-}" ]]; then
        for log_group in $DISCOVERED_LOG_GROUPS; do
            log_groups_to_check+=("$log_group")
        done
    fi
    
    # Delete metric filters for each log group
    for log_group in "${log_groups_to_check[@]}"; do
        if aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
            # Delete specific metric filters
            local filters=("ErrorRateFilter" "LogVolumeFilter")
            for filter in "${filters[@]}"; do
                if aws logs delete-metric-filter \
                    --log-group-name "$log_group" \
                    --filter-name "$filter" &> /dev/null; then
                    log_success "Deleted metric filter '$filter' from log group: $log_group"
                fi
            done
        fi
    done
}

delete_sns_topics() {
    log_info "Deleting SNS topics..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete SNS topics"
        return 0
    fi
    
    # Delete specified SNS topic
    if [[ -n "${SNS_TOPIC_NAME:-}" ]]; then
        local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
        if aws sns get-topic-attributes --topic-arn "$topic_arn" &> /dev/null; then
            aws sns delete-topic --topic-arn "$topic_arn"
            log_success "Deleted SNS topic: $SNS_TOPIC_NAME"
        fi
    fi
    
    # Delete discovered SNS topics
    if [[ -n "${DISCOVERED_SNS_TOPICS:-}" ]]; then
        for topic_arn in $DISCOVERED_SNS_TOPICS; do
            aws sns delete-topic --topic-arn "$topic_arn"
            local topic_name=$(basename "$topic_arn")
            log_success "Deleted SNS topic: $topic_name"
        done
    fi
    
    if [[ -z "${SNS_TOPIC_NAME:-}" && -z "${DISCOVERED_SNS_TOPICS:-}" ]]; then
        log_info "No SNS topics found to delete"
    fi
}

delete_lambda_functions() {
    log_info "Deleting Lambda functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Lambda functions"
        return 0
    fi
    
    # Delete specified Lambda function
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]] && aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"
        log_success "Deleted Lambda function: $LAMBDA_FUNCTION_NAME"
        wait_for_deletion "lambda" "$LAMBDA_FUNCTION_NAME"
    fi
    
    # Delete discovered Lambda functions
    if [[ -n "${DISCOVERED_LAMBDA_FUNCTIONS:-}" ]]; then
        for lambda_function in $DISCOVERED_LAMBDA_FUNCTIONS; do
            aws lambda delete-function --function-name "$lambda_function"
            log_success "Deleted Lambda function: $lambda_function"
            wait_for_deletion "lambda" "$lambda_function"
        done
    fi
    
    if [[ -z "${LAMBDA_FUNCTION_NAME:-}" && -z "${DISCOVERED_LAMBDA_FUNCTIONS:-}" ]]; then
        log_info "No Lambda functions found to delete"
    fi
}

delete_iam_roles() {
    log_info "Deleting IAM roles..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete IAM roles"
        return 0
    fi
    
    local roles_to_delete=()
    
    # Add specified IAM role
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        roles_to_delete+=("$IAM_ROLE_NAME")
    fi
    
    # Add discovered IAM roles
    if [[ -n "${DISCOVERED_IAM_ROLES:-}" ]]; then
        for role in $DISCOVERED_IAM_ROLES; do
            roles_to_delete+=("$role")
        done
    fi
    
    # Delete IAM roles
    for role_name in "${roles_to_delete[@]}"; do
        if aws iam get-role --role-name "$role_name" &> /dev/null; then
            # Detach managed policies
            local attached_policies
            attached_policies=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            
            for policy_arn in $attached_policies; do
                aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn"
                log_success "Detached policy '$policy_arn' from role: $role_name"
            done
            
            # Delete inline policies
            local inline_policies
            inline_policies=$(aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames' --output text 2>/dev/null || echo "")
            
            for policy_name in $inline_policies; do
                aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name"
                log_success "Deleted inline policy '$policy_name' from role: $role_name"
            done
            
            # Delete the role
            aws iam delete-role --role-name "$role_name"
            log_success "Deleted IAM role: $role_name"
            wait_for_deletion "iam-role" "$role_name"
        fi
    done
    
    if [[ ${#roles_to_delete[@]} -eq 0 ]]; then
        log_info "No IAM roles found to delete"
    fi
}

delete_log_groups() {
    log_info "Deleting CloudWatch log groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete log groups"
        return 0
    fi
    
    # Delete specified log group
    if [[ -n "${LOG_GROUP_NAME:-}" ]] && aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP_NAME"; then
        aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME"
        log_success "Deleted log group: $LOG_GROUP_NAME"
        wait_for_deletion "log-group" "$LOG_GROUP_NAME"
    fi
    
    # Delete discovered log groups
    if [[ -n "${DISCOVERED_LOG_GROUPS:-}" ]]; then
        for log_group in $DISCOVERED_LOG_GROUPS; do
            aws logs delete-log-group --log-group-name "$log_group"
            log_success "Deleted log group: $log_group"
            wait_for_deletion "log-group" "$log_group"
        done
    fi
    
    if [[ -z "${LOG_GROUP_NAME:-}" && -z "${DISCOVERED_LOG_GROUPS:-}" ]]; then
        log_info "No log groups found to delete"
    fi
}

cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    # Remove temporary files that might have been created during deployment
    local temp_files=(
        "${SCRIPT_DIR}/trust-policy.json"
        "${SCRIPT_DIR}/log-generator.py"
        "${SCRIPT_DIR}/log-generator.zip"
        "${SCRIPT_DIR}/dashboard-config.json"
        "${SCRIPT_DIR}/output"*.txt
        "${SCRIPT_DIR}/error-analysis-query.txt"
        "${SCRIPT_DIR}/performance-query.txt"
        "${SCRIPT_DIR}/user-activity-query.txt"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Removed temporary file: $(basename "$file")"
        fi
    done
    
    log_success "Local file cleanup completed"
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check required commands
    local required_commands=("aws" "jq")
    for cmd in "${required_commands[@]}"; do
        check_command "$cmd"
    done
    
    # Check AWS credentials
    check_aws_credentials
    
    # Validate AWS region
    if [[ -n "${AWS_REGION:-}" ]]; then
        validate_region "$AWS_REGION"
    fi
    
    log_success "Prerequisites validation completed"
}

set_environment_variables() {
    log_info "Setting environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
    export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
    
    log_info "Environment variables set:"
    log_info "  AWS_REGION: ${AWS_REGION}"
    log_info "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    
    # Log current resource names if set
    if [[ -n "${LOG_GROUP_NAME:-}" ]]; then
        log_info "  LOG_GROUP_NAME: ${LOG_GROUP_NAME}"
    fi
    if [[ -n "${LAMBDA_FUNCTION_NAME:-}" ]]; then
        log_info "  LAMBDA_FUNCTION_NAME: ${LAMBDA_FUNCTION_NAME}"
    fi
    if [[ -n "${SNS_TOPIC_NAME:-}" ]]; then
        log_info "  SNS_TOPIC_NAME: ${SNS_TOPIC_NAME}"
    fi
    if [[ -n "${DASHBOARD_NAME:-}" ]]; then
        log_info "  DASHBOARD_NAME: ${DASHBOARD_NAME}"
    fi
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        log_info "  IAM_ROLE_NAME: ${IAM_ROLE_NAME}"
    fi
}

# =============================================================================
# Main Destruction Function
# =============================================================================

destroy_operational_analytics() {
    log_info "Starting destruction of AWS Operational Analytics resources..."
    
    # Phase 1: Validation and Setup
    validate_prerequisites
    set_environment_variables
    
    # Phase 2: Resource Discovery
    if ! discover_resources; then
        if [[ -z "${LOG_GROUP_NAME:-}${LAMBDA_FUNCTION_NAME:-}${SNS_TOPIC_NAME:-}${DASHBOARD_NAME:-}${IAM_ROLE_NAME:-}" ]]; then
            log_warn "No resources found and no resource names provided."
            log_warn "Please set environment variables or use resource discovery mode."
            exit 1
        fi
    fi
    
    # Phase 3: Confirmation
    if ! confirm_destruction; then
        exit 1
    fi
    
    # Phase 4: Resource Deletion (in reverse order of creation)
    log_info "Beginning resource deletion..."
    
    delete_cloudwatch_alarms
    delete_anomaly_detectors
    delete_dashboards
    delete_metric_filters
    delete_sns_topics
    delete_lambda_functions
    delete_iam_roles
    delete_log_groups
    cleanup_local_files
    
    # Phase 5: Completion
    log_success "✅ AWS Operational Analytics destruction completed successfully!"
    
    echo
    log_info "=== Destruction Summary ==="
    log_info "All operational analytics resources have been removed"
    log_info "CloudWatch logs and metrics data has been permanently deleted"
    log_info "No further charges will be incurred for these resources"
    
    echo
    log_info "=== Verification ==="
    log_info "You can verify the deletion by checking the AWS Console:"
    log_info "• CloudWatch Dashboards: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:"
    log_info "• Lambda Functions: https://console.aws.amazon.com/lambda/home?region=${AWS_REGION}#/functions"
    log_info "• CloudWatch Logs: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#logsV2:log-groups"
    log_info "• SNS Topics: https://console.aws.amazon.com/sns/v3/home?region=${AWS_REGION}#/topics"
}

# =============================================================================
# Script Entry Point
# =============================================================================

show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Destroy AWS Operational Analytics with CloudWatch Insights resources

OPTIONS:
    -h, --help              Show this help message
    -r, --region REGION     AWS region (default: current AWS CLI region)
    -f, --force             Force destruction without confirmation prompts
    -d, --dry-run           Show what would be deleted without making changes
    -a, --auto-discover     Automatically discover resources to delete
    -v, --verbose           Enable verbose logging

ENVIRONMENT VARIABLES:
    AWS_REGION              AWS region containing resources
    LOG_GROUP_NAME          CloudWatch log group name
    LAMBDA_FUNCTION_NAME    Lambda function name
    SNS_TOPIC_NAME          SNS topic name
    DASHBOARD_NAME          CloudWatch dashboard name
    IAM_ROLE_NAME           IAM role name
    FORCE_DESTROY           Set to 'true' to skip confirmation prompts
    DRY_RUN                 Set to 'true' to enable dry-run mode

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME --auto-discover --force
    $SCRIPT_NAME --dry-run --verbose
    FORCE_DESTROY=true $SCRIPT_NAME
    
    # Delete specific resources
    LOG_GROUP_NAME="/aws/lambda/my-log-group" $SCRIPT_NAME

SAFETY FEATURES:
    • Multiple confirmation prompts before deletion
    • Dry-run mode to preview changes
    • Resource discovery to find related resources
    • Graceful handling of missing resources
    • Detailed logging of all operations

EOF
}

main() {
    # Initialize log file
    : > "$LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -r|--region)
                export AWS_REGION="$2"
                shift 2
                ;;
            -f|--force)
                export FORCE_DESTROY="true"
                shift
                ;;
            -d|--dry-run)
                export DRY_RUN="true"
                shift
                ;;
            -a|--auto-discover)
                export AUTO_DISCOVER="true"
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Start destruction
    destroy_operational_analytics
}

# Execute main function with all arguments
main "$@"