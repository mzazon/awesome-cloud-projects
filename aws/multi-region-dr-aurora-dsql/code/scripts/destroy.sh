#!/bin/bash

#==============================================================================
# Aurora DSQL Multi-Region Disaster Recovery Cleanup Script
# This script safely removes all resources created by the deploy.sh script,
# including Aurora DSQL clusters, Lambda functions, EventBridge rules, and
# associated monitoring infrastructure.
#==============================================================================

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
readonly LOG_FILE="/tmp/aurora-dsql-dr-destroy-${TIMESTAMP}.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Safety settings
FORCE_DELETE=false
CONFIG_FILE=""
DEPLOYMENT_ID=""

#==============================================================================
# Utility Functions
#==============================================================================

log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

print_colored() {
    local color="$1"
    shift
    echo -e "${color}$*${NC}"
}

error_exit() {
    print_colored "$RED" "❌ Error: $*" >&2
    log_error "$*"
    exit 1
}

success_msg() {
    print_colored "$GREEN" "✅ $*"
    log_success "$*"
}

info_msg() {
    print_colored "$BLUE" "ℹ️ $*"
    log_info "$*"
}

warn_msg() {
    print_colored "$YELLOW" "⚠️ $*"
    log_warn "$*"
}

#==============================================================================
# Safety and Confirmation Functions
#==============================================================================

prompt_confirmation() {
    local message="$1"
    local default="${2:-no}"
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        warn_msg "Force delete enabled - skipping confirmation"
        return 0
    fi
    
    while true; do
        if [[ "$default" == "yes" ]]; then
            read -p "$(print_colored "$YELLOW" "$message [Y/n]: ")" -r response
            response=${response:-yes}
        else
            read -p "$(print_colored "$YELLOW" "$message [y/N]: ")" -r response
            response=${response:-no}
        fi
        
        case "${response,,}" in
            yes|y)
                return 0
                ;;
            no|n)
                return 1
                ;;
            *)
                echo "Please answer yes or no."
                ;;
        esac
    done
}

safety_check() {
    info_msg "Performing safety checks before deletion..."
    
    # Check if AWS CLI is available
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI not found. Please install AWS CLI v2."
    fi
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured or invalid. Run 'aws configure' first."
    fi
    
    # Check if we're in the right AWS account
    local current_account
    current_account=$(aws sts get-caller-identity --query Account --output text)
    
    if [[ -n "$AWS_ACCOUNT_ID" ]] && [[ "$current_account" != "$AWS_ACCOUNT_ID" ]]; then
        error_exit "AWS account mismatch. Expected: $AWS_ACCOUNT_ID, Current: $current_account"
    fi
    
    success_msg "Safety checks passed"
}

display_resources_to_delete() {
    info_msg "The following resources will be PERMANENTLY DELETED:"
    echo
    print_colored "$RED" "Aurora DSQL Clusters:"
    print_colored "$RED" "  • ${CLUSTER_PREFIX}-primary (${PRIMARY_REGION})"
    print_colored "$RED" "  • ${CLUSTER_PREFIX}-secondary (${SECONDARY_REGION})"
    echo
    print_colored "$RED" "Lambda Functions:"
    print_colored "$RED" "  • ${LAMBDA_FUNCTION_NAME}-primary (${PRIMARY_REGION})"
    print_colored "$RED" "  • ${LAMBDA_FUNCTION_NAME}-secondary (${SECONDARY_REGION})"
    echo
    print_colored "$RED" "EventBridge Rules:"
    print_colored "$RED" "  • ${EVENTBRIDGE_RULE_NAME}-primary (${PRIMARY_REGION})"
    print_colored "$RED" "  • ${EVENTBRIDGE_RULE_NAME}-secondary (${SECONDARY_REGION})"
    echo
    print_colored "$RED" "SNS Topics:"
    print_colored "$RED" "  • ${SNS_TOPIC_NAME}-primary (${PRIMARY_REGION})"
    print_colored "$RED" "  • ${SNS_TOPIC_NAME}-secondary (${SECONDARY_REGION})"
    echo
    print_colored "$RED" "CloudWatch Resources:"
    print_colored "$RED" "  • Dashboard: Aurora-DSQL-DR-Dashboard-${DEPLOYMENT_ID}"
    print_colored "$RED" "  • Alarms: Aurora-DSQL-*-${DEPLOYMENT_ID}"
    echo
    print_colored "$RED" "IAM Role:"
    print_colored "$RED" "  • ${LAMBDA_FUNCTION_NAME}-role"
    echo
    print_colored "$YELLOW" "⚠️  WARNING: This action cannot be undone!"
    print_colored "$YELLOW" "⚠️  All data in Aurora DSQL clusters will be lost!"
    echo
}

#==============================================================================
# Configuration Loading Functions
#==============================================================================

load_configuration() {
    info_msg "Loading deployment configuration..."
    
    if [[ -n "$CONFIG_FILE" ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            error_exit "Configuration file not found: $CONFIG_FILE"
        fi
        
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        info_msg "Configuration loaded from: $CONFIG_FILE"
    elif [[ -n "$DEPLOYMENT_ID" ]]; then
        local config_file="/tmp/aurora-dsql-dr-config-${DEPLOYMENT_ID}.env"
        if [[ ! -f "$config_file" ]]; then
            error_exit "Configuration file for deployment ID '$DEPLOYMENT_ID' not found: $config_file"
        fi
        
        # shellcheck source=/dev/null
        source "$config_file"
        CONFIG_FILE="$config_file"
        info_msg "Configuration loaded for deployment ID: $DEPLOYMENT_ID"
    else
        # Try to find the most recent config file
        local latest_config
        latest_config=$(find /tmp -name "aurora-dsql-dr-config-*.env" -type f -printf "%T@ %p\n" 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
        
        if [[ -z "$latest_config" ]]; then
            error_exit "No configuration file found. Please specify --config or --deployment-id"
        fi
        
        # shellcheck source=/dev/null
        source "$latest_config"
        CONFIG_FILE="$latest_config"
        DEPLOYMENT_ID=$(basename "$latest_config" .env | sed 's/aurora-dsql-dr-config-//')
        warn_msg "Using most recent configuration: $latest_config"
    fi
    
    # Validate required variables
    local required_vars=(
        "PRIMARY_REGION"
        "SECONDARY_REGION" 
        "WITNESS_REGION"
        "CLUSTER_PREFIX"
        "LAMBDA_FUNCTION_NAME"
        "EVENTBRIDGE_RULE_NAME"
        "SNS_TOPIC_NAME"
        "AWS_ACCOUNT_ID"
        "DEPLOYMENT_ID"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error_exit "Required configuration variable '$var' not found"
        fi
    done
    
    success_msg "Configuration validation completed"
}

#==============================================================================
# Resource Deletion Functions
#==============================================================================

delete_cloudwatch_resources() {
    info_msg "Deleting CloudWatch alarms and dashboard..."
    
    # Delete CloudWatch alarms
    local alarms=(
        "Aurora-DSQL-Lambda-Errors-Primary-${DEPLOYMENT_ID}"
        "Aurora-DSQL-Cluster-Health-${DEPLOYMENT_ID}"
        "Aurora-DSQL-EventBridge-Failures-${DEPLOYMENT_ID}"
    )
    
    for alarm in "${alarms[@]}"; do
        if aws cloudwatch describe-alarms \
            --region "$PRIMARY_REGION" \
            --alarm-names "$alarm" \
            --query 'MetricAlarms[0].AlarmName' \
            --output text 2>/dev/null | grep -q "$alarm"; then
            
            aws cloudwatch delete-alarms \
                --region "$PRIMARY_REGION" \
                --alarm-names "$alarm" \
                && success_msg "Deleted alarm: $alarm" \
                || warn_msg "Failed to delete alarm: $alarm"
        else
            info_msg "Alarm not found (may have been deleted): $alarm"
        fi
    done
    
    # Delete secondary region alarm
    local secondary_alarm="Aurora-DSQL-Lambda-Errors-Secondary-${DEPLOYMENT_ID}"
    if aws cloudwatch describe-alarms \
        --region "$SECONDARY_REGION" \
        --alarm-names "$secondary_alarm" \
        --query 'MetricAlarms[0].AlarmName' \
        --output text 2>/dev/null | grep -q "$secondary_alarm"; then
        
        aws cloudwatch delete-alarms \
            --region "$SECONDARY_REGION" \
            --alarm-names "$secondary_alarm" \
            && success_msg "Deleted secondary alarm: $secondary_alarm" \
            || warn_msg "Failed to delete secondary alarm: $secondary_alarm"
    else
        info_msg "Secondary alarm not found (may have been deleted): $secondary_alarm"
    fi
    
    # Delete CloudWatch dashboard
    local dashboard_name="Aurora-DSQL-DR-Dashboard-${DEPLOYMENT_ID}"
    if aws cloudwatch list-dashboards \
        --region "$PRIMARY_REGION" \
        --query "DashboardEntries[?DashboardName=='$dashboard_name'].DashboardName" \
        --output text 2>/dev/null | grep -q "$dashboard_name"; then
        
        aws cloudwatch delete-dashboards \
            --region "$PRIMARY_REGION" \
            --dashboard-names "$dashboard_name" \
            && success_msg "Deleted dashboard: $dashboard_name" \
            || warn_msg "Failed to delete dashboard: $dashboard_name"
    else
        info_msg "Dashboard not found (may have been deleted): $dashboard_name"
    fi
    
    success_msg "CloudWatch resources cleanup completed"
}

delete_eventbridge_rules() {
    info_msg "Deleting EventBridge rules and targets..."
    
    # Delete primary region EventBridge rule
    local primary_rule="${EVENTBRIDGE_RULE_NAME}-primary"
    if aws events describe-rule \
        --region "$PRIMARY_REGION" \
        --name "$primary_rule" &> /dev/null; then
        
        # Remove targets first
        aws events remove-targets \
            --region "$PRIMARY_REGION" \
            --rule "$primary_rule" \
            --ids "1" \
            && info_msg "Removed targets from primary EventBridge rule" \
            || warn_msg "Failed to remove targets from primary EventBridge rule"
        
        # Delete the rule
        aws events delete-rule \
            --region "$PRIMARY_REGION" \
            --name "$primary_rule" \
            && success_msg "Deleted primary EventBridge rule: $primary_rule" \
            || warn_msg "Failed to delete primary EventBridge rule: $primary_rule"
    else
        info_msg "Primary EventBridge rule not found (may have been deleted): $primary_rule"
    fi
    
    # Delete secondary region EventBridge rule
    local secondary_rule="${EVENTBRIDGE_RULE_NAME}-secondary"
    if aws events describe-rule \
        --region "$SECONDARY_REGION" \
        --name "$secondary_rule" &> /dev/null; then
        
        # Remove targets first
        aws events remove-targets \
            --region "$SECONDARY_REGION" \
            --rule "$secondary_rule" \
            --ids "1" \
            && info_msg "Removed targets from secondary EventBridge rule" \
            || warn_msg "Failed to remove targets from secondary EventBridge rule"
        
        # Delete the rule
        aws events delete-rule \
            --region "$SECONDARY_REGION" \
            --name "$secondary_rule" \
            && success_msg "Deleted secondary EventBridge rule: $secondary_rule" \
            || warn_msg "Failed to delete secondary EventBridge rule: $secondary_rule"
    else
        info_msg "Secondary EventBridge rule not found (may have been deleted): $secondary_rule"
    fi
    
    success_msg "EventBridge rules cleanup completed"
}

delete_lambda_functions() {
    info_msg "Deleting Lambda functions..."
    
    # Delete primary Lambda function
    local primary_function="${LAMBDA_FUNCTION_NAME}-primary"
    if aws lambda get-function \
        --region "$PRIMARY_REGION" \
        --function-name "$primary_function" &> /dev/null; then
        
        aws lambda delete-function \
            --region "$PRIMARY_REGION" \
            --function-name "$primary_function" \
            && success_msg "Deleted primary Lambda function: $primary_function" \
            || warn_msg "Failed to delete primary Lambda function: $primary_function"
    else
        info_msg "Primary Lambda function not found (may have been deleted): $primary_function"
    fi
    
    # Delete secondary Lambda function
    local secondary_function="${LAMBDA_FUNCTION_NAME}-secondary"
    if aws lambda get-function \
        --region "$SECONDARY_REGION" \
        --function-name "$secondary_function" &> /dev/null; then
        
        aws lambda delete-function \
            --region "$SECONDARY_REGION" \
            --function-name "$secondary_function" \
            && success_msg "Deleted secondary Lambda function: $secondary_function" \
            || warn_msg "Failed to delete secondary Lambda function: $secondary_function"
    else
        info_msg "Secondary Lambda function not found (may have been deleted): $secondary_function"
    fi
    
    success_msg "Lambda functions cleanup completed"
}

delete_iam_role() {
    info_msg "Deleting IAM role and associated policies..."
    
    local role_name="${LAMBDA_FUNCTION_NAME}-role"
    
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        # Detach managed policies
        local policies=(
            "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
            "arn:aws:iam::aws:policy/AmazonDSQLFullAccess"
            "arn:aws:iam::aws:policy/AmazonSNSFullAccess"
            "arn:aws:iam::aws:policy/CloudWatchFullAccess"
        )
        
        for policy in "${policies[@]}"; do
            aws iam detach-role-policy \
                --role-name "$role_name" \
                --policy-arn "$policy" \
                && info_msg "Detached policy: $(basename "$policy")" \
                || warn_msg "Failed to detach policy: $(basename "$policy")"
        done
        
        # Delete the role
        aws iam delete-role \
            --role-name "$role_name" \
            && success_msg "Deleted IAM role: $role_name" \
            || warn_msg "Failed to delete IAM role: $role_name"
    else
        info_msg "IAM role not found (may have been deleted): $role_name"
    fi
    
    success_msg "IAM role cleanup completed"
}

delete_sns_topics() {
    info_msg "Deleting SNS topics and subscriptions..."
    
    # Find and delete primary SNS topic
    local primary_topic_name="${SNS_TOPIC_NAME}-primary"
    local primary_topic_arn
    primary_topic_arn=$(aws sns list-topics \
        --region "$PRIMARY_REGION" \
        --query "Topics[?ends_with(TopicArn, ':$primary_topic_name')].TopicArn" \
        --output text 2>/dev/null)
    
    if [[ -n "$primary_topic_arn" ]] && [[ "$primary_topic_arn" != "None" ]]; then
        aws sns delete-topic \
            --region "$PRIMARY_REGION" \
            --topic-arn "$primary_topic_arn" \
            && success_msg "Deleted primary SNS topic: $primary_topic_name" \
            || warn_msg "Failed to delete primary SNS topic: $primary_topic_name"
    else
        info_msg "Primary SNS topic not found (may have been deleted): $primary_topic_name"
    fi
    
    # Find and delete secondary SNS topic
    local secondary_topic_name="${SNS_TOPIC_NAME}-secondary"
    local secondary_topic_arn
    secondary_topic_arn=$(aws sns list-topics \
        --region "$SECONDARY_REGION" \
        --query "Topics[?ends_with(TopicArn, ':$secondary_topic_name')].TopicArn" \
        --output text 2>/dev/null)
    
    if [[ -n "$secondary_topic_arn" ]] && [[ "$secondary_topic_arn" != "None" ]]; then
        aws sns delete-topic \
            --region "$SECONDARY_REGION" \
            --topic-arn "$secondary_topic_arn" \
            && success_msg "Deleted secondary SNS topic: $secondary_topic_name" \
            || warn_msg "Failed to delete secondary SNS topic: $secondary_topic_name"
    else
        info_msg "Secondary SNS topic not found (may have been deleted): $secondary_topic_name"
    fi
    
    success_msg "SNS topics cleanup completed"
}

delete_aurora_dsql_clusters() {
    info_msg "Deleting Aurora DSQL clusters..."
    
    # Check if clusters exist and get their status
    local primary_exists=false
    local secondary_exists=false
    
    if aws dsql describe-cluster \
        --region "$PRIMARY_REGION" \
        --identifier "${CLUSTER_PREFIX}-primary" &> /dev/null; then
        primary_exists=true
    fi
    
    if aws dsql describe-cluster \
        --region "$SECONDARY_REGION" \
        --identifier "${CLUSTER_PREFIX}-secondary" &> /dev/null; then
        secondary_exists=true
    fi
    
    # Remove cluster peering if both clusters exist
    if [[ "$primary_exists" == "true" ]] && [[ "$secondary_exists" == "true" ]]; then
        info_msg "Removing cluster peering before deletion..."
        
        # Remove peering from primary cluster
        aws dsql update-cluster \
            --region "$PRIMARY_REGION" \
            --identifier "${CLUSTER_PREFIX}-primary" \
            --multi-region-properties "{\"witnessRegion\":\"$WITNESS_REGION\",\"clusters\":[]}" \
            && info_msg "Removed peering from primary cluster" \
            || warn_msg "Failed to remove peering from primary cluster"
        
        # Remove peering from secondary cluster
        aws dsql update-cluster \
            --region "$SECONDARY_REGION" \
            --identifier "${CLUSTER_PREFIX}-secondary" \
            --multi-region-properties "{\"witnessRegion\":\"$WITNESS_REGION\",\"clusters\":[]}" \
            && info_msg "Removed peering from secondary cluster" \
            || warn_msg "Failed to remove peering from secondary cluster"
        
        # Wait for peering removal to complete
        info_msg "Waiting for peering removal to complete..."
        sleep 60
    fi
    
    # Delete primary cluster
    if [[ "$primary_exists" == "true" ]]; then
        info_msg "Deleting primary Aurora DSQL cluster..."
        aws dsql delete-cluster \
            --region "$PRIMARY_REGION" \
            --identifier "${CLUSTER_PREFIX}-primary" \
            && success_msg "Initiated deletion of primary cluster: ${CLUSTER_PREFIX}-primary" \
            || warn_msg "Failed to delete primary cluster: ${CLUSTER_PREFIX}-primary"
    else
        info_msg "Primary cluster not found (may have been deleted): ${CLUSTER_PREFIX}-primary"
    fi
    
    # Delete secondary cluster
    if [[ "$secondary_exists" == "true" ]]; then
        info_msg "Deleting secondary Aurora DSQL cluster..."
        aws dsql delete-cluster \
            --region "$SECONDARY_REGION" \
            --identifier "${CLUSTER_PREFIX}-secondary" \
            && success_msg "Initiated deletion of secondary cluster: ${CLUSTER_PREFIX}-secondary" \
            || warn_msg "Failed to delete secondary cluster: ${CLUSTER_PREFIX}-secondary"
    else
        info_msg "Secondary cluster not found (may have been deleted): ${CLUSTER_PREFIX}-secondary"
    fi
    
    # Wait for cluster deletion to complete (this may take several minutes)
    if [[ "$primary_exists" == "true" ]] || [[ "$secondary_exists" == "true" ]]; then
        info_msg "Waiting for cluster deletion to complete..."
        info_msg "This may take several minutes. You can safely interrupt this script."
        info_msg "Cluster deletion will continue in the background."
        
        local wait_time=0
        local max_wait=600  # 10 minutes maximum wait
        
        while [[ $wait_time -lt $max_wait ]]; do
            local primary_status="DELETED"
            local secondary_status="DELETED"
            
            if [[ "$primary_exists" == "true" ]]; then
                primary_status=$(aws dsql describe-cluster \
                    --region "$PRIMARY_REGION" \
                    --identifier "${CLUSTER_PREFIX}-primary" \
                    --query 'status' --output text 2>/dev/null || echo "DELETED")
            fi
            
            if [[ "$secondary_exists" == "true" ]]; then
                secondary_status=$(aws dsql describe-cluster \
                    --region "$SECONDARY_REGION" \
                    --identifier "${CLUSTER_PREFIX}-secondary" \
                    --query 'status' --output text 2>/dev/null || echo "DELETED")
            fi
            
            if [[ "$primary_status" == "DELETED" ]] && [[ "$secondary_status" == "DELETED" ]]; then
                success_msg "All Aurora DSQL clusters have been deleted"
                break
            fi
            
            info_msg "Cluster deletion in progress... (${wait_time}s elapsed)"
            info_msg "Primary: $primary_status, Secondary: $secondary_status"
            sleep 30
            wait_time=$((wait_time + 30))
        done
        
        if [[ $wait_time -ge $max_wait ]]; then
            warn_msg "Timeout waiting for cluster deletion. Deletion continues in background."
        fi
    fi
    
    success_msg "Aurora DSQL clusters cleanup completed"
}

cleanup_configuration_files() {
    info_msg "Cleaning up configuration files..."
    
    if [[ -n "$CONFIG_FILE" ]] && [[ -f "$CONFIG_FILE" ]]; then
        if prompt_confirmation "Delete configuration file: $CONFIG_FILE?"; then
            rm -f "$CONFIG_FILE" \
                && success_msg "Deleted configuration file: $CONFIG_FILE" \
                || warn_msg "Failed to delete configuration file: $CONFIG_FILE"
        else
            info_msg "Configuration file preserved: $CONFIG_FILE"
        fi
    fi
    
    # Clean up temporary files
    rm -f /tmp/primary_response.json /tmp/secondary_response.json
    
    success_msg "Configuration cleanup completed"
}

#==============================================================================
# Main Functions
#==============================================================================

usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Safely destroy Aurora DSQL Multi-Region Disaster Recovery Infrastructure

OPTIONS:
    -c, --config FILE               Configuration file from deployment
    -d, --deployment-id ID          Deployment ID to clean up
    -f, --force                     Skip confirmation prompts (DANGEROUS)
    -v, --verbose                   Enable verbose logging
    -h, --help                      Show this help message

EXAMPLES:
    $SCRIPT_NAME
    $SCRIPT_NAME --config /tmp/aurora-dsql-dr-config-abc12345.env
    $SCRIPT_NAME --deployment-id abc12345
    $SCRIPT_NAME --force --verbose

SAFETY NOTES:
    • This script will PERMANENTLY DELETE all Aurora DSQL clusters and data
    • Use --force flag with extreme caution in production environments
    • Configuration files contain deployment details needed for cleanup

EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -d|--deployment-id)
                DEPLOYMENT_ID="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

main() {
    print_colored "$CYAN" "================================================================"
    print_colored "$CYAN" "Aurora DSQL Multi-Region Disaster Recovery Cleanup"
    print_colored "$CYAN" "================================================================"
    echo
    
    # Parse command line arguments
    parse_arguments "$@"
    
    info_msg "Starting cleanup process..."
    info_msg "Log file: $LOG_FILE"
    
    # Load configuration and perform safety checks
    load_configuration
    safety_check
    
    # Display what will be deleted
    display_resources_to_delete
    
    # Final confirmation
    if ! prompt_confirmation "Are you absolutely sure you want to delete all these resources?"; then
        info_msg "Cleanup cancelled by user"
        exit 0
    fi
    
    if ! prompt_confirmation "This will PERMANENTLY DELETE all data. Continue?"; then
        info_msg "Cleanup cancelled by user"
        exit 0
    fi
    
    # Perform cleanup in reverse order of creation
    info_msg "Beginning resource cleanup..."
    
    delete_cloudwatch_resources
    delete_eventbridge_rules
    delete_lambda_functions
    delete_iam_role
    delete_sns_topics
    delete_aurora_dsql_clusters
    cleanup_configuration_files
    
    # Success summary
    echo
    print_colored "$GREEN" "================================================================"
    print_colored "$GREEN" "🧹 CLEANUP COMPLETED SUCCESSFULLY!"
    print_colored "$GREEN" "================================================================"
    echo
    success_msg "Aurora DSQL Multi-Region Disaster Recovery cleanup completed"
    info_msg "All resources have been deleted or are in the process of being deleted"
    echo
    info_msg "Cleanup summary:"
    info_msg "  • Aurora DSQL clusters: Deleted (may take additional time to complete)"
    info_msg "  • Lambda functions: Deleted"
    info_msg "  • EventBridge rules: Deleted"
    info_msg "  • SNS topics: Deleted"
    info_msg "  • CloudWatch resources: Deleted"
    info_msg "  • IAM role: Deleted"
    echo
    warn_msg "Aurora DSQL cluster deletion may continue in the background"
    warn_msg "Monitor the AWS console to confirm complete deletion"
    echo
    info_msg "Thank you for using Aurora DSQL Multi-Region Disaster Recovery"
    echo
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi