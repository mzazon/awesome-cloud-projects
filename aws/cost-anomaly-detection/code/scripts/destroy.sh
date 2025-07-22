#!/bin/bash

# AWS Cost Anomaly Detection Cleanup Script
# This script removes all resources created by the cost anomaly detection deployment
# Based on the recipe: Cost Anomaly Detection with Machine Learning

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
RESOURCES_FILE="${SCRIPT_DIR}/deployed_resources.txt"

# Default values
FORCE_DELETE="${FORCE_DELETE:-false}"
DRY_RUN="${DRY_RUN:-false}"
INTERACTIVE="${INTERACTIVE:-true}"

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

log_success() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ✅ SUCCESS: $1" | tee -a "$LOG_FILE"
}

log_warning() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ⚠️  WARNING: $1" | tee -a "$LOG_FILE"
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

confirm_action() {
    local message="$1"
    
    if [[ "$FORCE_DELETE" == "true" ]] || [[ "$INTERACTIVE" == "false" ]]; then
        return 0
    fi
    
    echo -n "$message (y/N): "
    read -r response
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        log "Operation cancelled by user"
        return 1
    fi
}

check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed."
        return 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured or invalid."
        return 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region || echo "us-east-1")
    log "AWS Account ID: $account_id"
    log "AWS Region: $region"
    
    export AWS_ACCOUNT_ID="$account_id"
    export AWS_REGION="$region"
}

# =============================================================================
# RESOURCE DELETION FUNCTIONS
# =============================================================================

delete_anomaly_subscriptions() {
    log "Deleting Cost Anomaly Detection subscriptions..."
    
    local subscriptions=$(aws ce get-anomaly-subscriptions \
        --query 'AnomalySubscriptions[?contains(SubscriptionName, `Daily-Cost-Summary`) || contains(SubscriptionName, `Individual-Cost-Alerts`)].{Name:SubscriptionName,ARN:SubscriptionArn}' \
        --output json)
    
    if [[ "$subscriptions" == "[]" ]]; then
        log "No anomaly subscriptions found to delete"
        return 0
    fi
    
    local subscription_count=$(echo "$subscriptions" | jq length)
    log "Found $subscription_count anomaly subscription(s) to delete"
    
    if ! confirm_action "Delete $subscription_count anomaly subscription(s)?"; then
        return 0
    fi
    
    echo "$subscriptions" | jq -r '.[] | @base64' | while read -r subscription; do
        local sub_data=$(echo "$subscription" | base64 --decode)
        local sub_name=$(echo "$sub_data" | jq -r '.Name')
        local sub_arn=$(echo "$sub_data" | jq -r '.ARN')
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would delete subscription: $sub_name"
            continue
        fi
        
        log "Deleting subscription: $sub_name"
        
        if aws ce delete-anomaly-subscription --subscription-arn "$sub_arn" 2>/dev/null; then
            log_success "Deleted subscription: $sub_name"
        else
            log_error "Failed to delete subscription: $sub_name"
        fi
    done
}

delete_anomaly_monitors() {
    log "Deleting Cost Anomaly Detection monitors..."
    
    local monitors=$(aws ce get-anomaly-monitors \
        --query 'AnomalyMonitors[?contains(MonitorName, `AWS-Services-Monitor`) || contains(MonitorName, `Account-Based-Monitor`) || contains(MonitorName, `Environment-Tag-Monitor`)].{Name:MonitorName,ARN:MonitorArn}' \
        --output json)
    
    if [[ "$monitors" == "[]" ]]; then
        log "No anomaly monitors found to delete"
        return 0
    fi
    
    local monitor_count=$(echo "$monitors" | jq length)
    log "Found $monitor_count anomaly monitor(s) to delete"
    
    if ! confirm_action "Delete $monitor_count anomaly monitor(s)?"; then
        return 0
    fi
    
    echo "$monitors" | jq -r '.[] | @base64' | while read -r monitor; do
        local mon_data=$(echo "$monitor" | base64 --decode)
        local mon_name=$(echo "$mon_data" | jq -r '.Name')
        local mon_arn=$(echo "$mon_data" | jq -r '.ARN')
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would delete monitor: $mon_name"
            continue
        fi
        
        log "Deleting monitor: $mon_name"
        
        if aws ce delete-anomaly-monitor --monitor-arn "$mon_arn" 2>/dev/null; then
            log_success "Deleted monitor: $mon_name"
        else
            log_error "Failed to delete monitor: $mon_name"
        fi
    done
}

delete_lambda_function() {
    local function_name="cost-anomaly-processor"
    
    log "Checking for Lambda function: $function_name"
    
    if ! aws lambda get-function --function-name "$function_name" &> /dev/null; then
        log "Lambda function $function_name not found"
        return 0
    fi
    
    if ! confirm_action "Delete Lambda function: $function_name?"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete Lambda function: $function_name"
        return 0
    fi
    
    log "Deleting Lambda function: $function_name"
    
    if aws lambda delete-function --function-name "$function_name" 2>/dev/null; then
        log_success "Deleted Lambda function: $function_name"
    else
        log_error "Failed to delete Lambda function: $function_name"
    fi
}

delete_eventbridge_rule() {
    local rule_name="cost-anomaly-detection-rule"
    
    log "Checking for EventBridge rule: $rule_name"
    
    if ! aws events describe-rule --name "$rule_name" &> /dev/null; then
        log "EventBridge rule $rule_name not found"
        return 0
    fi
    
    if ! confirm_action "Delete EventBridge rule: $rule_name?"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would remove targets and delete EventBridge rule: $rule_name"
        return 0
    fi
    
    log "Removing targets from EventBridge rule: $rule_name"
    
    # Remove all targets from the rule
    local targets=$(aws events list-targets-by-rule --rule "$rule_name" --query 'Targets[].Id' --output text)
    
    if [[ -n "$targets" ]]; then
        aws events remove-targets --rule "$rule_name" --ids $targets 2>/dev/null || true
        log "Removed targets from rule: $rule_name"
    fi
    
    log "Deleting EventBridge rule: $rule_name"
    
    if aws events delete-rule --name "$rule_name" 2>/dev/null; then
        log_success "Deleted EventBridge rule: $rule_name"
    else
        log_error "Failed to delete EventBridge rule: $rule_name"
    fi
}

delete_sns_topics() {
    log "Checking for SNS topics with cost-anomaly-alerts prefix..."
    
    local topics=$(aws sns list-topics \
        --query 'Topics[?contains(TopicArn, `cost-anomaly-alerts`)].TopicArn' \
        --output text)
    
    if [[ -z "$topics" ]]; then
        log "No SNS topics found with cost-anomaly-alerts prefix"
        return 0
    fi
    
    local topic_count=$(echo "$topics" | wc -w)
    log "Found $topic_count SNS topic(s) to delete"
    
    if ! confirm_action "Delete $topic_count SNS topic(s)?"; then
        return 0
    fi
    
    for topic_arn in $topics; do
        local topic_name=$(basename "$topic_arn")
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would delete SNS topic: $topic_name"
            continue
        fi
        
        log "Deleting SNS topic: $topic_name"
        
        if aws sns delete-topic --topic-arn "$topic_arn" 2>/dev/null; then
            log_success "Deleted SNS topic: $topic_name"
        else
            log_error "Failed to delete SNS topic: $topic_name"
        fi
    done
}

delete_cloudwatch_dashboard() {
    local dashboard_name="Cost-Anomaly-Detection-Dashboard"
    
    log "Checking for CloudWatch dashboard: $dashboard_name"
    
    if ! aws cloudwatch list-dashboards --query "DashboardEntries[?DashboardName=='$dashboard_name']" --output text | grep -q "$dashboard_name"; then
        log "CloudWatch dashboard $dashboard_name not found"
        return 0
    fi
    
    if ! confirm_action "Delete CloudWatch dashboard: $dashboard_name?"; then
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete CloudWatch dashboard: $dashboard_name"
        return 0
    fi
    
    log "Deleting CloudWatch dashboard: $dashboard_name"
    
    if aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name" 2>/dev/null; then
        log_success "Deleted CloudWatch dashboard: $dashboard_name"
    else
        log_error "Failed to delete CloudWatch dashboard: $dashboard_name"
    fi
}

delete_cloudwatch_log_groups() {
    log "Checking for CloudWatch log groups..."
    
    local log_groups=$(aws logs describe-log-groups \
        --query 'logGroups[?contains(logGroupName, `cost-anomaly-processor`)].logGroupName' \
        --output text)
    
    if [[ -z "$log_groups" ]]; then
        log "No relevant CloudWatch log groups found"
        return 0
    fi
    
    local log_group_count=$(echo "$log_groups" | wc -w)
    log "Found $log_group_count CloudWatch log group(s) to delete"
    
    if ! confirm_action "Delete $log_group_count CloudWatch log group(s)?"; then
        return 0
    fi
    
    for log_group in $log_groups; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would delete log group: $log_group"
            continue
        fi
        
        log "Deleting log group: $log_group"
        
        if aws logs delete-log-group --log-group-name "$log_group" 2>/dev/null; then
            log_success "Deleted log group: $log_group"
        else
            log_error "Failed to delete log group: $log_group"
        fi
    done
}

delete_iam_role() {
    local role_name="lambda-execution-role"
    
    log "Checking for IAM role: $role_name"
    
    if ! aws iam get-role --role-name "$role_name" &> /dev/null; then
        log "IAM role $role_name not found"
        return 0
    fi
    
    if ! confirm_action "Delete IAM role: $role_name? (This may affect other Lambda functions)"; then
        log_warning "Skipping IAM role deletion. Manual cleanup may be required."
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would detach policies and delete IAM role: $role_name"
        return 0
    fi
    
    log "Detaching policies from IAM role: $role_name"
    
    # Detach AWS managed policies
    aws iam detach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        2>/dev/null || true
    
    aws iam detach-role-policy \
        --role-name "$role_name" \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess \
        2>/dev/null || true
    
    log "Deleting IAM role: $role_name"
    
    if aws iam delete-role --role-name "$role_name" 2>/dev/null; then
        log_success "Deleted IAM role: $role_name"
    else
        log_error "Failed to delete IAM role: $role_name"
    fi
}

delete_from_resources_file() {
    if [[ ! -f "$RESOURCES_FILE" ]]; then
        log_warning "Resources file not found: $RESOURCES_FILE"
        log "Will attempt to find and delete resources by pattern matching"
        return 0
    fi
    
    log "Reading resources from: $RESOURCES_FILE"
    
    # Parse resources file and delete resources
    grep -v '^#' "$RESOURCES_FILE" | while IFS='|' read -r resource_type resource_name resource_arn; do
        if [[ -z "$resource_type" ]]; then
            continue
        fi
        
        log "Processing resource: $resource_type/$resource_name"
        
        case "$resource_type" in
            "sns-topic")
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "[DRY RUN] Would delete SNS topic: $resource_name"
                else
                    aws sns delete-topic --topic-arn "$resource_arn" 2>/dev/null || true
                fi
                ;;
            "anomaly-monitor")
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "[DRY RUN] Would delete anomaly monitor: $resource_name"
                else
                    aws ce delete-anomaly-monitor --monitor-arn "$resource_arn" 2>/dev/null || true
                fi
                ;;
            "anomaly-subscription")
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "[DRY RUN] Would delete anomaly subscription: $resource_name"
                else
                    aws ce delete-anomaly-subscription --subscription-arn "$resource_arn" 2>/dev/null || true
                fi
                ;;
            "lambda-function")
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "[DRY RUN] Would delete Lambda function: $resource_name"
                else
                    aws lambda delete-function --function-name "$resource_name" 2>/dev/null || true
                fi
                ;;
            "eventbridge-rule")
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "[DRY RUN] Would delete EventBridge rule: $resource_name"
                else
                    # Remove targets first
                    local targets=$(aws events list-targets-by-rule --rule "$resource_name" --query 'Targets[].Id' --output text 2>/dev/null || true)
                    if [[ -n "$targets" ]]; then
                        aws events remove-targets --rule "$resource_name" --ids $targets 2>/dev/null || true
                    fi
                    aws events delete-rule --name "$resource_name" 2>/dev/null || true
                fi
                ;;
            "cloudwatch-dashboard")
                if [[ "$DRY_RUN" == "true" ]]; then
                    log "[DRY RUN] Would delete CloudWatch dashboard: $resource_name"
                else
                    aws cloudwatch delete-dashboards --dashboard-names "$resource_name" 2>/dev/null || true
                fi
                ;;
        esac
    done
}

# =============================================================================
# MAIN CLEANUP FUNCTION
# =============================================================================

main() {
    log "Starting AWS Cost Anomaly Detection cleanup..."
    log "Script directory: $SCRIPT_DIR"
    log "Log file: $LOG_FILE"
    log "Resources file: $RESOURCES_FILE"
    log "Force delete: $FORCE_DELETE"
    log "Dry run: $DRY_RUN"
    log "Interactive: $INTERACTIVE"
    
    # Prerequisites check
    check_aws_cli
    
    # Warning message
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        log_warning "This will DELETE AWS resources created by the Cost Anomaly Detection deployment!"
        log_warning "This action cannot be undone."
        echo ""
        
        if [[ "$FORCE_DELETE" != "true" ]] && [[ "$INTERACTIVE" == "true" ]]; then
            if ! confirm_action "Are you sure you want to proceed with cleanup?"; then
                log "Cleanup cancelled by user"
                exit 0
            fi
        fi
    fi
    
    # Delete resources in reverse order of creation to handle dependencies
    
    # 1. Delete anomaly subscriptions first (they depend on monitors and SNS)
    delete_anomaly_subscriptions
    
    # 2. Delete anomaly monitors
    delete_anomaly_monitors
    
    # 3. Delete EventBridge rule and targets
    delete_eventbridge_rule
    
    # 4. Delete Lambda function
    delete_lambda_function
    
    # 5. Delete CloudWatch resources
    delete_cloudwatch_dashboard
    delete_cloudwatch_log_groups
    
    # 6. Delete SNS topics
    delete_sns_topics
    
    # 7. Delete IAM role (optional, with confirmation)
    delete_iam_role
    
    # 8. Try to delete from resources file if it exists
    delete_from_resources_file
    
    # Clean up local files
    if [[ "$DRY_RUN" != "true" ]]; then
        if [[ -f "$RESOURCES_FILE" ]]; then
            if confirm_action "Remove deployed resources tracking file: $RESOURCES_FILE?"; then
                rm -f "$RESOURCES_FILE"
                log_success "Removed resources file: $RESOURCES_FILE"
            fi
        fi
    fi
    
    # Summary
    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "Dry run completed. No resources were actually deleted."
        log "Run without --dry-run to perform actual cleanup."
    else
        log_success "Cleanup completed!"
        log ""
        log "=== CLEANUP SUMMARY ==="
        log "The following resource types were processed for deletion:"
        log "  - Cost Anomaly Detection subscriptions"
        log "  - Cost Anomaly Detection monitors"
        log "  - Lambda function and IAM role"
        log "  - EventBridge rule and targets"
        log "  - SNS topics"
        log "  - CloudWatch dashboard and log groups"
        log ""
        log "Note: Some resources may take a few minutes to be fully removed."
        log "You can verify cleanup by checking the AWS Console."
    fi
}

# =============================================================================
# HELP FUNCTION
# =============================================================================

show_help() {
    cat << EOF
AWS Cost Anomaly Detection Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -f, --force            Skip confirmation prompts and force deletion
    -d, --dry-run         Show what would be deleted without making changes
    -n, --non-interactive Skip interactive prompts (use with --force for automation)
    -h, --help            Show this help message

ENVIRONMENT VARIABLES:
    FORCE_DELETE          Set to 'true' to skip confirmation prompts
    DRY_RUN              Set to 'true' for dry run mode
    INTERACTIVE          Set to 'false' to skip interactive prompts

EXAMPLES:
    # Interactive cleanup (default)
    $0

    # Force cleanup without prompts
    $0 --force

    # Dry run to see what would be deleted
    $0 --dry-run

    # Non-interactive cleanup (useful for automation)
    $0 --force --non-interactive

SAFETY FEATURES:
    - Confirmation prompts for destructive actions (unless --force is used)
    - Dry run mode to preview actions without making changes
    - Proper dependency order for resource deletion
    - Detailed logging of all operations

EOF
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_DELETE="true"
            shift
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -n|--non-interactive)
            INTERACTIVE="false"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# =============================================================================
# MAIN EXECUTION
# =============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi