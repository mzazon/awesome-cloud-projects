#!/bin/bash

# AWS Basic Log Monitoring with CloudWatch Logs and SNS - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Configuration and Constants
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/tmp/basic-log-monitoring-destroy-$(date +%Y%m%d-%H%M%S).log"

# Default values
LOG_GROUP_NAME="/aws/application/monitoring-demo"
METRIC_FILTER_NAME="error-count-filter"
ALARM_NAME="application-errors-alarm"
LAMBDA_FUNCTION_NAME=""
SNS_TOPIC_NAME=""
FORCE_DELETE=false
DRY_RUN=false

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR] $*${NC}" | tee -a "$LOG_FILE" >&2
}

warn() {
    echo -e "${YELLOW}[WARN] $*${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO] $*${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS] $*${NC}" | tee -a "$LOG_FILE"
}

# Usage function
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Cleanup AWS Basic Log Monitoring resources

OPTIONS:
    -g, --log-group NAME        CloudWatch log group name (default: $LOG_GROUP_NAME)
    -f, --filter-name NAME      Metric filter name (default: $METRIC_FILTER_NAME)
    -a, --alarm-name NAME       CloudWatch alarm name (default: $ALARM_NAME)
    -l, --lambda-name NAME      Lambda function name (required if not using patterns)
    -s, --sns-topic NAME        SNS topic name (required if not using patterns)
    --force                     Skip confirmation prompts
    --dry-run                   Show what would be deleted without making changes
    -h, --help                  Show this help message
    -v, --verbose               Enable verbose logging

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME --lambda-name log-processor-abc123 --sns-topic log-monitoring-alerts-abc123
    $SCRIPT_NAME --force --dry-run

NOTES:
    - If Lambda function name and SNS topic name are not provided, the script will
      attempt to find them using naming patterns
    - Use --dry-run to see what would be deleted before running the actual cleanup
    - Use --force to skip confirmation prompts (useful for automation)

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--log-group)
                LOG_GROUP_NAME="$2"
                shift 2
                ;;
            -f|--filter-name)
                METRIC_FILTER_NAME="$2"
                shift 2
                ;;
            -a|--alarm-name)
                ALARM_NAME="$2"
                shift 2
                ;;
            -l|--lambda-name)
                LAMBDA_FUNCTION_NAME="$2"
                shift 2
                ;;
            -s|--sns-topic)
                SNS_TOPIC_NAME="$2"
                shift 2
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."

    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi

    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' or set up credentials."
        exit 1
    fi

    success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    info "Setting up environment variables..."

    # Get AWS region and account ID
    export AWS_REGION
    AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION="us-east-1"
        warn "No default region configured, using us-east-1"
    fi

    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
}

# Discover resources if not provided
discover_resources() {
    info "Discovering resources..."

    # Find Lambda functions matching pattern if not provided
    if [[ -z "$LAMBDA_FUNCTION_NAME" ]]; then
        local lambda_functions
        lambda_functions=$(aws lambda list-functions \
            --query 'Functions[?starts_with(FunctionName, `log-processor-`)].FunctionName' \
            --output text)

        if [[ -n "$lambda_functions" ]]; then
            # Take the first match if multiple found
            LAMBDA_FUNCTION_NAME=$(echo "$lambda_functions" | head -n1)
            info "Found Lambda function: $LAMBDA_FUNCTION_NAME"
        else
            warn "No Lambda functions found matching pattern 'log-processor-*'"
        fi
    fi

    # Find SNS topics matching pattern if not provided
    if [[ -z "$SNS_TOPIC_NAME" ]]; then
        local sns_topics
        sns_topics=$(aws sns list-topics \
            --query 'Topics[?contains(TopicArn, `log-monitoring-alerts-`)].TopicArn' \
            --output text)

        if [[ -n "$sns_topics" ]]; then
            # Extract topic name from ARN and take the first match
            SNS_TOPIC_NAME=$(echo "$sns_topics" | head -n1 | awk -F: '{print $NF}')
            info "Found SNS topic: $SNS_TOPIC_NAME"
        else
            warn "No SNS topics found matching pattern 'log-monitoring-alerts-*'"
        fi
    fi

    export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "$resource_type" in
        "log-group")
            aws logs describe-log-groups --log-group-name-prefix "$resource_name" \
                --query 'logGroups[?logGroupName==`'"$resource_name"'`]' --output text | grep -q .
            ;;
        "sns-topic")
            aws sns get-topic-attributes --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${resource_name}" &> /dev/null
            ;;
        "lambda-function")
            [[ -n "$resource_name" ]] && aws lambda get-function --function-name "$resource_name" &> /dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "$resource_name" &> /dev/null
            ;;
        "metric-filter")
            aws logs describe-metric-filters --log-group-name "$LOG_GROUP_NAME" \
                --filter-name-prefix "$resource_name" --query 'metricFilters[0]' --output text | grep -q .
            ;;
        "alarm")
            aws cloudwatch describe-alarms --alarm-names "$resource_name" \
                --query 'MetricAlarms[0]' --output text | grep -q .
            ;;
        *)
            return 1
            ;;
    esac
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi

    echo
    warn "The following resources will be deleted:"
    echo "- CloudWatch Log Group: $LOG_GROUP_NAME"
    echo "- CloudWatch Alarm: $ALARM_NAME"
    echo "- Metric Filter: $METRIC_FILTER_NAME"
    [[ -n "$SNS_TOPIC_NAME" ]] && echo "- SNS Topic: $SNS_TOPIC_NAME"
    [[ -n "$LAMBDA_FUNCTION_NAME" ]] && echo "- Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo "- IAM Role: lambda-log-processor-role"
    echo

    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
}

# Delete CloudWatch Alarm
delete_alarm() {
    info "Deleting CloudWatch Alarm: $ALARM_NAME"

    if ! resource_exists "alarm" "$ALARM_NAME"; then
        warn "CloudWatch alarm $ALARM_NAME does not exist, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete CloudWatch alarm: $ALARM_NAME"
        return 0
    fi

    aws cloudwatch delete-alarms --alarm-names "$ALARM_NAME"
    
    # Wait a moment for deletion to process
    sleep 2
    
    if ! resource_exists "alarm" "$ALARM_NAME"; then
        success "CloudWatch alarm deleted: $ALARM_NAME"
    else
        error "Failed to delete CloudWatch alarm: $ALARM_NAME"
        return 1
    fi
}

# Delete Metric Filter
delete_metric_filter() {
    info "Deleting Metric Filter: $METRIC_FILTER_NAME"

    if ! resource_exists "metric-filter" "$METRIC_FILTER_NAME"; then
        warn "Metric filter $METRIC_FILTER_NAME does not exist, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete metric filter: $METRIC_FILTER_NAME"
        return 0
    fi

    aws logs delete-metric-filter \
        --log-group-name "$LOG_GROUP_NAME" \
        --filter-name "$METRIC_FILTER_NAME"

    success "Metric filter deleted: $METRIC_FILTER_NAME"
}

# Delete Lambda Function
delete_lambda_function() {
    if [[ -z "$LAMBDA_FUNCTION_NAME" ]]; then
        warn "No Lambda function name provided, skipping Lambda deletion"
        return 0
    fi

    info "Deleting Lambda Function: $LAMBDA_FUNCTION_NAME"

    if ! resource_exists "lambda-function" "$LAMBDA_FUNCTION_NAME"; then
        warn "Lambda function $LAMBDA_FUNCTION_NAME does not exist, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete Lambda function: $LAMBDA_FUNCTION_NAME"
        return 0
    fi

    aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME"

    success "Lambda function deleted: $LAMBDA_FUNCTION_NAME"
}

# Delete SNS Topic
delete_sns_topic() {
    if [[ -z "$SNS_TOPIC_NAME" ]]; then
        warn "No SNS topic name provided, skipping SNS deletion"
        return 0
    fi

    info "Deleting SNS Topic: $SNS_TOPIC_NAME"

    if ! resource_exists "sns-topic" "$SNS_TOPIC_NAME"; then
        warn "SNS topic $SNS_TOPIC_NAME does not exist, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete SNS topic: $SNS_TOPIC_NAME"
        return 0
    fi

    # Delete SNS topic (automatically removes subscriptions)
    aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN"

    success "SNS topic deleted: $SNS_TOPIC_NAME"
}

# Delete IAM Role
delete_iam_role() {
    local role_name="lambda-log-processor-role"
    
    info "Deleting IAM Role: $role_name"

    if ! resource_exists "iam-role" "$role_name"; then
        warn "IAM role $role_name does not exist, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete IAM role: $role_name"
        return 0
    fi

    # Detach policies first
    local policies
    policies=$(aws iam list-attached-role-policies --role-name "$role_name" \
        --query 'AttachedPolicies[].PolicyArn' --output text)

    for policy in $policies; do
        info "Detaching policy: $policy"
        aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy"
    done

    # Delete the role
    aws iam delete-role --role-name "$role_name"

    success "IAM role deleted: $role_name"
}

# Delete CloudWatch Log Group
delete_log_group() {
    info "Deleting CloudWatch Log Group: $LOG_GROUP_NAME"

    if ! resource_exists "log-group" "$LOG_GROUP_NAME"; then
        warn "Log group $LOG_GROUP_NAME does not exist, skipping"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete log group: $LOG_GROUP_NAME"
        return 0
    fi

    # Show warning about log data loss
    if [[ "$FORCE_DELETE" != "true" ]]; then
        warn "This will permanently delete all log data in $LOG_GROUP_NAME"
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Log group deletion cancelled"
            return 0
        fi
    fi

    aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME"

    success "CloudWatch log group deleted: $LOG_GROUP_NAME"
}

# Clean up any remaining resources
cleanup_remaining_resources() {
    info "Checking for any remaining resources..."

    # Check for any Lambda function logs
    if [[ -n "$LAMBDA_FUNCTION_NAME" ]]; then
        local lambda_log_group="/aws/lambda/$LAMBDA_FUNCTION_NAME"
        if resource_exists "log-group" "$lambda_log_group"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would delete Lambda log group: $lambda_log_group"
            else
                info "Deleting Lambda log group: $lambda_log_group"
                aws logs delete-log-group --log-group-name "$lambda_log_group" 2>/dev/null || true
                success "Lambda log group deleted: $lambda_log_group"
            fi
        fi
    fi

    # Check for any remaining custom metrics
    if [[ "$DRY_RUN" != "true" ]]; then
        info "Custom metrics in namespace 'CustomApp/Monitoring' will expire automatically"
        info "No manual cleanup required for CloudWatch metrics"
    fi
}

# Print cleanup summary
print_summary() {
    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        success "=== DRY RUN SUMMARY ==="
        info "The following resources would be deleted:"
    else
        success "=== CLEANUP SUMMARY ==="
        info "The following resources have been deleted:"
    fi
    
    echo "- CloudWatch Alarm: $ALARM_NAME"
    echo "- Metric Filter: $METRIC_FILTER_NAME"
    [[ -n "$LAMBDA_FUNCTION_NAME" ]] && echo "- Lambda Function: $LAMBDA_FUNCTION_NAME"
    [[ -n "$SNS_TOPIC_NAME" ]] && echo "- SNS Topic: $SNS_TOPIC_NAME"
    echo "- IAM Role: lambda-log-processor-role"
    echo "- CloudWatch Log Group: $LOG_GROUP_NAME"
    echo "- Log File: $LOG_FILE"
    echo

    if [[ "$DRY_RUN" != "true" ]]; then
        info "Notes:"
        echo "- CloudWatch metrics will expire automatically based on retention settings"
        echo "- Any email subscriptions have been automatically removed with the SNS topic"
        echo "- All AWS charges for these resources should stop immediately"
    fi
    echo
}

# Main cleanup function
main() {
    log "Starting AWS Basic Log Monitoring cleanup"
    
    parse_args "$@"
    check_prerequisites
    setup_environment
    discover_resources
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN MODE - No resources will be deleted"
    else
        confirm_deletion
    fi
    
    # Delete resources in reverse order of dependencies
    delete_alarm
    delete_metric_filter
    delete_lambda_function
    delete_sns_topic
    delete_iam_role
    delete_log_group
    cleanup_remaining_resources
    
    print_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Dry run completed successfully!"
        info "Run without --dry-run to perform actual cleanup"
    else
        success "Cleanup completed successfully!"
    fi
}

# Error handler
error_handler() {
    local line_number=$1
    error "Script failed at line $line_number"
    exit 1
}

# Set up error handling
trap 'error_handler ${LINENO}' ERR

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi