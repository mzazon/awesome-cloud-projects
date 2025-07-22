#!/bin/bash

# Destroy script for Analytics Workload Isolation with Redshift Workload Management
# This script safely removes all infrastructure created by the deployment

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
CONFIG_FILE="${SCRIPT_DIR}/.deploy_config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup failed. Check logs at: $LOG_FILE"
    log_error "Some resources might still exist and require manual cleanup"
    exit 1
}

trap cleanup_on_error ERR

# Load configuration
load_configuration() {
    log_info "Loading deployment configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_error "Cannot proceed with cleanup without deployment configuration"
        log_info "If you need to clean up manually, look for resources with these patterns:"
        log_info "- Parameter Groups: analytics-wlm-pg-*"
        log_info "- SNS Topics: redshift-wlm-alerts-*"
        log_info "- CloudWatch Alarms: RedshiftWLM-*"
        log_info "- CloudWatch Dashboards: RedshiftWLM-*"
        exit 1
    fi
    
    source "$CONFIG_FILE"
    
    log_info "Loaded configuration:"
    log_info "  Region: ${AWS_REGION:-not-set}"
    log_info "  Account: ${AWS_ACCOUNT_ID:-not-set}"
    log_info "  Cluster ID: ${CLUSTER_IDENTIFIER:-not-set}"
    log_info "  Parameter Group: ${PARAMETER_GROUP_NAME:-not-set}"
    log_info "  SNS Topic: ${SNS_TOPIC_NAME:-not-set}"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "${DESTROY_CONFIRMED:-false}" == "true" ]] || [[ "${1:-}" == "--force" ]]; then
        log_warning "Skipping confirmation prompt"
        return 0
    fi
    
    log_warning "This will permanently delete all resources created by the deployment:"
    log_warning "- Parameter Group: ${PARAMETER_GROUP_NAME:-unknown}"
    log_warning "- SNS Topic: ${SNS_TOPIC_NAME:-unknown}"
    log_warning "- CloudWatch Alarms: ${ALARM_QUEUE_WAIT:-unknown}, ${ALARM_CPU_UTIL:-unknown}, ${ALARM_QUERY_ABORT:-unknown}"
    log_warning "- CloudWatch Dashboard: ${DASHBOARD_NAME:-unknown}"
    log_warning "- Configuration files and SQL scripts"
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Reset cluster parameter group
reset_cluster_parameter_group() {
    log_info "Resetting cluster parameter group to default..."
    
    # Check if cluster exists and is using our parameter group
    if aws redshift describe-clusters \
        --cluster-identifier "$CLUSTER_IDENTIFIER" >/dev/null 2>&1; then
        
        CURRENT_PG=$(aws redshift describe-clusters \
            --cluster-identifier "$CLUSTER_IDENTIFIER" \
            --query 'Clusters[0].ClusterParameterGroups[0].ParameterGroupName' \
            --output text 2>/dev/null || echo "none")
        
        if [[ "$CURRENT_PG" == "$PARAMETER_GROUP_NAME" ]]; then
            log_info "Resetting cluster $CLUSTER_IDENTIFIER to default parameter group..."
            
            aws redshift modify-cluster \
                --cluster-identifier "$CLUSTER_IDENTIFIER" \
                --cluster-parameter-group-name "default.redshift-1.0" \
                --apply-immediately
            
            log_success "Cluster reset to default parameter group"
            log_warning "Cluster will reboot to apply default configuration"
            
            # Wait for cluster modification to start
            log_info "Waiting for cluster modification to start..."
            sleep 30
            
            # Wait for cluster to be available (with timeout)
            local timeout=300  # 5 minutes
            local elapsed=0
            
            while [[ $elapsed -lt $timeout ]]; do
                local status=$(aws redshift describe-clusters \
                    --cluster-identifier "$CLUSTER_IDENTIFIER" \
                    --query 'Clusters[0].ClusterStatus' \
                    --output text 2>/dev/null || echo "error")
                
                if [[ "$status" == "available" ]]; then
                    log_success "Cluster is available and ready"
                    break
                elif [[ "$status" == "error" ]]; then
                    log_error "Error checking cluster status"
                    break
                fi
                
                log_info "Cluster status: $status (waiting for 'available')"
                sleep 30
                elapsed=$((elapsed + 30))
            done
            
            if [[ $elapsed -ge $timeout ]]; then
                log_warning "Timeout waiting for cluster to become available"
                log_warning "Parameter group cleanup will continue, but may require retry"
            fi
            
        else
            log_info "Cluster is not using our parameter group (current: $CURRENT_PG)"
        fi
        
    else
        log_info "Cluster $CLUSTER_IDENTIFIER not found, skipping parameter group reset"
    fi
}

# Remove CloudWatch alarms
remove_cloudwatch_alarms() {
    log_info "Removing CloudWatch alarms..."
    
    local alarms_to_delete=()
    
    # Build list of alarms to delete
    if [[ -n "${ALARM_QUEUE_WAIT:-}" ]]; then
        alarms_to_delete+=("$ALARM_QUEUE_WAIT")
    fi
    if [[ -n "${ALARM_CPU_UTIL:-}" ]]; then
        alarms_to_delete+=("$ALARM_CPU_UTIL")
    fi
    if [[ -n "${ALARM_QUERY_ABORT:-}" ]]; then
        alarms_to_delete+=("$ALARM_QUERY_ABORT")
    fi
    
    # If no specific alarms found, try pattern matching
    if [[ ${#alarms_to_delete[@]} -eq 0 ]] && [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        log_info "No specific alarm names found, searching by pattern..."
        
        local pattern_alarms=$(aws cloudwatch describe-alarms \
            --query "MetricAlarms[?contains(AlarmName, 'RedshiftWLM-') && contains(AlarmName, '${RANDOM_SUFFIX}')].AlarmName" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$pattern_alarms" ]]; then
            read -ra alarms_to_delete <<< "$pattern_alarms"
        fi
    fi
    
    if [[ ${#alarms_to_delete[@]} -eq 0 ]]; then
        log_warning "No CloudWatch alarms found to delete"
        return 0
    fi
    
    # Delete alarms
    for alarm in "${alarms_to_delete[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm" &>/dev/null; then
            aws cloudwatch delete-alarms --alarm-names "$alarm"
            log_success "Deleted alarm: $alarm"
        else
            log_warning "Alarm not found: $alarm"
        fi
    done
}

# Remove CloudWatch dashboard
remove_cloudwatch_dashboard() {
    log_info "Removing CloudWatch dashboard..."
    
    local dashboard_name="${DASHBOARD_NAME:-RedshiftWLM-${RANDOM_SUFFIX:-unknown}}"
    
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "$dashboard_name"
        log_success "Deleted dashboard: $dashboard_name"
    else
        log_warning "Dashboard not found: $dashboard_name"
    fi
}

# Remove SNS topic and subscriptions
remove_sns_topic() {
    log_info "Removing SNS topic and subscriptions..."
    
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        # Check if topic exists
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
            
            # List and delete subscriptions first
            local subscriptions=$(aws sns list-subscriptions-by-topic \
                --topic-arn "$SNS_TOPIC_ARN" \
                --query 'Subscriptions[].SubscriptionArn' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$subscriptions" ]]; then
                for subscription in $subscriptions; do
                    if [[ "$subscription" != "PendingConfirmation" ]]; then
                        aws sns unsubscribe --subscription-arn "$subscription"
                        log_success "Removed subscription: $subscription"
                    fi
                done
            fi
            
            # Delete the topic
            aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN"
            log_success "Deleted SNS topic: $SNS_TOPIC_ARN"
            
        else
            log_warning "SNS topic not found: $SNS_TOPIC_ARN"
        fi
    else
        log_warning "SNS topic ARN not found in configuration"
    fi
}

# Remove parameter group
remove_parameter_group() {
    log_info "Removing custom parameter group..."
    
    if [[ -z "${PARAMETER_GROUP_NAME:-}" ]]; then
        log_warning "Parameter group name not found in configuration"
        return 0
    fi
    
    # Check if parameter group exists
    if aws redshift describe-cluster-parameter-groups \
        --parameter-group-name "$PARAMETER_GROUP_NAME" &>/dev/null; then
        
        # Try to delete parameter group (may fail if still in use)
        local max_retries=5
        local retry_count=0
        local success=false
        
        while [[ $retry_count -lt $max_retries ]] && [[ "$success" == "false" ]]; do
            if aws redshift delete-cluster-parameter-group \
                --parameter-group-name "$PARAMETER_GROUP_NAME" 2>/dev/null; then
                success=true
                log_success "Deleted parameter group: $PARAMETER_GROUP_NAME"
            else
                retry_count=$((retry_count + 1))
                if [[ $retry_count -lt $max_retries ]]; then
                    log_warning "Parameter group deletion failed (attempt $retry_count/$max_retries), retrying in 30 seconds..."
                    sleep 30
                else
                    log_error "Failed to delete parameter group after $max_retries attempts"
                    log_error "The parameter group may still be in use by a cluster"
                    log_info "Manual cleanup required for: $PARAMETER_GROUP_NAME"
                fi
            fi
        done
        
    else
        log_warning "Parameter group not found: $PARAMETER_GROUP_NAME"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local configuration and temporary files..."
    
    local files_to_remove=(
        "wlm_config_with_qmr.json"
        "setup_users_groups.sql"
        "wlm_monitoring_views.sql"
        "wlm_dashboard.json"
        "deployment_summary.txt"
        ".deploy_config"
    )
    
    for file in "${files_to_remove[@]}"; do
        local file_path="${SCRIPT_DIR}/${file}"
        if [[ -f "$file_path" ]]; then
            rm -f "$file_path"
            log_success "Removed file: $file"
        else
            log_info "File not found: $file"
        fi
    done
    
    # Clean up environment variables that might be set
    unset AWS_REGION AWS_ACCOUNT_ID CLUSTER_IDENTIFIER PARAMETER_GROUP_NAME
    unset SNS_TOPIC_NAME PARAMETER_GROUP_FAMILY SNS_TOPIC_ARN RANDOM_SUFFIX
    unset ALARM_QUEUE_WAIT ALARM_CPU_UTIL ALARM_QUERY_ABORT DASHBOARD_NAME
    
    log_success "Local cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check parameter group
    if [[ -n "${PARAMETER_GROUP_NAME:-}" ]]; then
        if aws redshift describe-cluster-parameter-groups \
            --parameter-group-name "$PARAMETER_GROUP_NAME" &>/dev/null; then
            log_warning "Parameter group still exists: $PARAMETER_GROUP_NAME"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check SNS topic
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" &>/dev/null; then
            log_warning "SNS topic still exists: $SNS_TOPIC_ARN"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check CloudWatch alarms
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local remaining_alarms=$(aws cloudwatch describe-alarms \
            --query "MetricAlarms[?contains(AlarmName, 'RedshiftWLM-') && contains(AlarmName, '${RANDOM_SUFFIX}')].AlarmName" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$remaining_alarms" ]]; then
            log_warning "CloudWatch alarms still exist: $remaining_alarms"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check dashboard
    if [[ -n "${DASHBOARD_NAME:-}" ]]; then
        if aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" &>/dev/null; then
            log_warning "CloudWatch dashboard still exists: $DASHBOARD_NAME"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "All resources have been successfully removed"
    else
        log_warning "Cleanup completed with $cleanup_issues issue(s)"
        log_warning "Some resources may require manual removal"
    fi
}

# Generate cleanup summary
generate_cleanup_summary() {
    log_info "Generating cleanup summary..."
    
    cat > "${SCRIPT_DIR}/cleanup_summary.txt" << EOF
Analytics Workload Isolation Cleanup Summary
===========================================

Cleanup Date: $(date)
Region: ${AWS_REGION:-unknown}
Account: ${AWS_ACCOUNT_ID:-unknown}

Resources Removed:
- Parameter Group: ${PARAMETER_GROUP_NAME:-unknown}
- SNS Topic: ${SNS_TOPIC_ARN:-unknown}
- CloudWatch Alarms: ${ALARM_QUEUE_WAIT:-unknown}, ${ALARM_CPU_UTIL:-unknown}, ${ALARM_QUERY_ABORT:-unknown}
- CloudWatch Dashboard: ${DASHBOARD_NAME:-unknown}
- Local configuration files and SQL scripts

Cluster Status:
- Cluster ID: ${CLUSTER_IDENTIFIER:-unknown}
- Parameter group reset to default.redshift-1.0

Manual Verification:
1. Check AWS Console for any remaining resources
2. Verify cluster is using default parameter group
3. Confirm no unexpected charges from lingering resources

Note: If cleanup encountered issues, some resources may require manual removal.
Check the destroy.log file for detailed information.
EOF
    
    log_success "Cleanup summary saved to: ${SCRIPT_DIR}/cleanup_summary.txt"
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Main cleanup function
main() {
    log_info "Starting Analytics Workload Isolation cleanup..."
    log_info "Log file: $LOG_FILE"
    
    # Check command line arguments
    local force_mode=false
    if [[ "${1:-}" == "--force" ]]; then
        force_mode=true
        log_warning "Force mode enabled - skipping confirmation prompts"
    fi
    
    # Check if running in confirmed mode
    if [[ "${DESTROY_CONFIRMED:-false}" == "true" ]]; then
        log_warning "Running in confirmed mode - skipping prompts"
    fi
    
    check_prerequisites
    load_configuration
    
    if [[ "$force_mode" == "true" ]]; then
        confirm_destruction "--force"
    else
        confirm_destruction
    fi
    
    # Cleanup in reverse order of creation
    reset_cluster_parameter_group
    remove_cloudwatch_alarms
    remove_cloudwatch_dashboard
    remove_sns_topic
    remove_parameter_group
    cleanup_local_files
    verify_cleanup
    generate_cleanup_summary
    
    log_success "Analytics Workload Isolation cleanup completed!"
    log_info "Check cleanup_summary.txt for details"
    
    if [[ -f "${SCRIPT_DIR}/cleanup_summary.txt" ]]; then
        log_info "Cleanup summary:"
        cat "${SCRIPT_DIR}/cleanup_summary.txt"
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi