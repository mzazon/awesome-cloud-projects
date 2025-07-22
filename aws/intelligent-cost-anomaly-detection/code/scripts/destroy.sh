#!/bin/bash

# =============================================================================
# AWS Cost Anomaly Detection Cleanup Script
# =============================================================================
# This script removes all resources created by the cost anomaly detection
# deployment, including Lambda functions, SNS topics, IAM roles, and Cost
# Anomaly Detection monitors and detectors.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for resource deletion
# - Deployment artifacts from deploy.sh
#
# Usage: ./destroy.sh [options]
# Options:
#   --force           Skip confirmation prompts
#   --dry-run         Show what would be deleted without making changes
#   --debug           Enable debug logging
#   --help            Show this help message
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
FORCE=false
DRY_RUN=false
DEBUG=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
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

log_debug() {
    if [[ "${DEBUG}" == "true" ]]; then
        log "${BLUE}[DEBUG]${NC} $1"
    fi
}

show_help() {
    cat << EOF
AWS Cost Anomaly Detection Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --force           Skip confirmation prompts for deletion
    --dry-run         Show what would be deleted without making changes
    --debug           Enable debug logging
    --help            Show this help message

EXAMPLES:
    $0                              # Interactive cleanup with confirmations
    $0 --force                      # Automatic cleanup without confirmations
    $0 --dry-run                    # Show what would be deleted
    $0 --force --debug              # Force cleanup with debug logging

DESCRIPTION:
    This script removes all AWS resources created by the cost anomaly detection
    deployment script. Resources are deleted in reverse order of creation to
    handle dependencies properly.

WARNING:
    This action is irreversible. All cost anomaly detection infrastructure
    will be permanently removed, including:
    - Cost Anomaly Detection monitors and detectors
    - Lambda functions and IAM roles
    - SNS topics and subscriptions
    - EventBridge rules and targets
    - CloudWatch dashboards

EOF
}

confirm_action() {
    local action="$1"
    
    if [[ "${FORCE}" == "true" ]]; then
        log_debug "Force mode enabled, skipping confirmation for: ${action}"
        return 0
    fi
    
    echo -n -e "${YELLOW}[CONFIRM]${NC} ${action} (y/N): "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            log_info "Skipping: ${action}"
            return 1
            ;;
    esac
}

# =============================================================================
# Resource Discovery Functions
# =============================================================================

discover_cost_anomaly_resources() {
    log_info "Discovering Cost Anomaly Detection resources..."
    
    # Find anomaly detectors
    DETECTOR_ARNS=($(aws ce get-anomaly-detectors \
        --query "AnomalyDetectors[?contains(DetectorName, 'cost-anomaly-detector')].DetectorArn" \
        --output text 2>/dev/null || echo ""))
    
    # Find anomaly monitors
    MONITOR_ARNS=($(aws ce get-anomaly-monitors \
        --query "AnomalyMonitors[?contains(MonitorName, 'cost-anomaly-monitor')].MonitorArn" \
        --output text 2>/dev/null || echo ""))
    
    log_debug "Found ${#DETECTOR_ARNS[@]} anomaly detectors"
    log_debug "Found ${#MONITOR_ARNS[@]} anomaly monitors"
}

discover_lambda_resources() {
    log_info "Discovering Lambda resources..."
    
    # Find Lambda functions
    FUNCTION_NAMES=($(aws lambda list-functions \
        --query "Functions[?contains(FunctionName, 'cost-anomaly-processor')].FunctionName" \
        --output text 2>/dev/null || echo ""))
    
    log_debug "Found ${#FUNCTION_NAMES[@]} Lambda functions"
}

discover_iam_resources() {
    log_info "Discovering IAM resources..."
    
    # Find IAM roles
    ROLE_NAMES=($(aws iam list-roles \
        --query "Roles[?contains(RoleName, 'CostAnomalyLambdaRole')].RoleName" \
        --output text 2>/dev/null || echo ""))
    
    # Find custom policies
    POLICY_ARNS=($(aws iam list-policies --scope Local \
        --query "Policies[?contains(PolicyName, 'CostAnomalyPolicy')].Arn" \
        --output text 2>/dev/null || echo ""))
    
    log_debug "Found ${#ROLE_NAMES[@]} IAM roles"
    log_debug "Found ${#POLICY_ARNS[@]} custom policies"
}

discover_sns_resources() {
    log_info "Discovering SNS resources..."
    
    # Find SNS topics
    SNS_TOPIC_ARNS=($(aws sns list-topics \
        --query "Topics[?contains(TopicArn, 'cost-anomaly-alerts')].TopicArn" \
        --output text 2>/dev/null || echo ""))
    
    log_debug "Found ${#SNS_TOPIC_ARNS[@]} SNS topics"
}

discover_eventbridge_resources() {
    log_info "Discovering EventBridge resources..."
    
    # Find EventBridge rules
    RULE_NAMES=($(aws events list-rules \
        --query "Rules[?contains(Name, 'cost-anomaly-rule')].Name" \
        --output text 2>/dev/null || echo ""))
    
    log_debug "Found ${#RULE_NAMES[@]} EventBridge rules"
}

discover_cloudwatch_resources() {
    log_info "Discovering CloudWatch resources..."
    
    # Find CloudWatch dashboards
    DASHBOARD_NAMES=($(aws cloudwatch list-dashboards \
        --query "DashboardEntries[?contains(DashboardName, 'CostAnomalyDetection')].DashboardName" \
        --output text 2>/dev/null || echo ""))
    
    log_debug "Found ${#DASHBOARD_NAMES[@]} CloudWatch dashboards"
}

# =============================================================================
# Resource Deletion Functions
# =============================================================================

delete_cost_anomaly_detectors() {
    if [[ ${#DETECTOR_ARNS[@]} -eq 0 ]]; then
        log_info "No Cost Anomaly Detectors found to delete"
        return 0
    fi
    
    for detector_arn in "${DETECTOR_ARNS[@]}"; do
        if [[ -z "${detector_arn}" ]]; then
            continue
        fi
        
        local detector_name=$(basename "${detector_arn}")
        
        if confirm_action "Delete Cost Anomaly Detector: ${detector_name}"; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY RUN] Would delete Cost Anomaly Detector: ${detector_arn}"
            else
                log_info "Deleting Cost Anomaly Detector: ${detector_arn}"
                
                if aws ce delete-anomaly-detector --detector-arn "${detector_arn}" 2>/dev/null; then
                    log_success "✅ Deleted Cost Anomaly Detector: ${detector_name}"
                else
                    log_error "❌ Failed to delete Cost Anomaly Detector: ${detector_name}"
                fi
            fi
        fi
    done
}

delete_cost_anomaly_monitors() {
    if [[ ${#MONITOR_ARNS[@]} -eq 0 ]]; then
        log_info "No Cost Anomaly Monitors found to delete"
        return 0
    fi
    
    for monitor_arn in "${MONITOR_ARNS[@]}"; do
        if [[ -z "${monitor_arn}" ]]; then
            continue
        fi
        
        local monitor_name=$(basename "${monitor_arn}")
        
        if confirm_action "Delete Cost Anomaly Monitor: ${monitor_name}"; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY RUN] Would delete Cost Anomaly Monitor: ${monitor_arn}"
            else
                log_info "Deleting Cost Anomaly Monitor: ${monitor_arn}"
                
                if aws ce delete-anomaly-monitor --monitor-arn "${monitor_arn}" 2>/dev/null; then
                    log_success "✅ Deleted Cost Anomaly Monitor: ${monitor_name}"
                else
                    log_error "❌ Failed to delete Cost Anomaly Monitor: ${monitor_name}"
                fi
            fi
        fi
    done
}

delete_eventbridge_rules() {
    if [[ ${#RULE_NAMES[@]} -eq 0 ]]; then
        log_info "No EventBridge rules found to delete"
        return 0
    fi
    
    for rule_name in "${RULE_NAMES[@]}"; do
        if [[ -z "${rule_name}" ]]; then
            continue
        fi
        
        if confirm_action "Delete EventBridge rule: ${rule_name}"; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY RUN] Would delete EventBridge rule: ${rule_name}"
            else
                log_info "Deleting EventBridge rule: ${rule_name}"
                
                # Remove targets first
                local targets=$(aws events list-targets-by-rule --rule "${rule_name}" \
                    --query "Targets[].Id" --output text 2>/dev/null || echo "")
                
                if [[ -n "${targets}" ]]; then
                    log_debug "Removing targets from rule: ${rule_name}"
                    aws events remove-targets --rule "${rule_name}" --ids ${targets} 2>/dev/null || true
                fi
                
                # Delete the rule
                if aws events delete-rule --name "${rule_name}" 2>/dev/null; then
                    log_success "✅ Deleted EventBridge rule: ${rule_name}"
                else
                    log_error "❌ Failed to delete EventBridge rule: ${rule_name}"
                fi
            fi
        fi
    done
}

delete_lambda_functions() {
    if [[ ${#FUNCTION_NAMES[@]} -eq 0 ]]; then
        log_info "No Lambda functions found to delete"
        return 0
    fi
    
    for function_name in "${FUNCTION_NAMES[@]}"; do
        if [[ -z "${function_name}" ]]; then
            continue
        fi
        
        if confirm_action "Delete Lambda function: ${function_name}"; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY RUN] Would delete Lambda function: ${function_name}"
            else
                log_info "Deleting Lambda function: ${function_name}"
                
                # Remove Lambda permissions first
                local statement_ids=$(aws lambda get-policy --function-name "${function_name}" \
                    --query "Policy" --output text 2>/dev/null | \
                    jq -r '.Statement[].Sid' 2>/dev/null || echo "")
                
                for sid in ${statement_ids}; do
                    if [[ -n "${sid}" && "${sid}" != "null" ]]; then
                        log_debug "Removing Lambda permission: ${sid}"
                        aws lambda remove-permission --function-name "${function_name}" \
                            --statement-id "${sid}" 2>/dev/null || true
                    fi
                done
                
                # Delete the function
                if aws lambda delete-function --function-name "${function_name}" 2>/dev/null; then
                    log_success "✅ Deleted Lambda function: ${function_name}"
                else
                    log_error "❌ Failed to delete Lambda function: ${function_name}"
                fi
            fi
        fi
    done
}

delete_iam_resources() {
    # Delete IAM roles
    if [[ ${#ROLE_NAMES[@]} -gt 0 ]]; then
        for role_name in "${ROLE_NAMES[@]}"; do
            if [[ -z "${role_name}" ]]; then
                continue
            fi
            
            if confirm_action "Delete IAM role: ${role_name}"; then
                if [[ "${DRY_RUN}" == "true" ]]; then
                    log_info "[DRY RUN] Would delete IAM role: ${role_name}"
                else
                    log_info "Deleting IAM role: ${role_name}"
                    
                    # Detach managed policies
                    local attached_policies=$(aws iam list-attached-role-policies \
                        --role-name "${role_name}" --query "AttachedPolicies[].PolicyArn" \
                        --output text 2>/dev/null || echo "")
                    
                    for policy_arn in ${attached_policies}; do
                        if [[ -n "${policy_arn}" ]]; then
                            log_debug "Detaching policy: ${policy_arn}"
                            aws iam detach-role-policy --role-name "${role_name}" \
                                --policy-arn "${policy_arn}" 2>/dev/null || true
                        fi
                    done
                    
                    # Delete inline policies
                    local inline_policies=$(aws iam list-role-policies \
                        --role-name "${role_name}" --query "PolicyNames" \
                        --output text 2>/dev/null || echo "")
                    
                    for policy_name in ${inline_policies}; do
                        if [[ -n "${policy_name}" ]]; then
                            log_debug "Deleting inline policy: ${policy_name}"
                            aws iam delete-role-policy --role-name "${role_name}" \
                                --policy-name "${policy_name}" 2>/dev/null || true
                        fi
                    done
                    
                    # Delete the role
                    if aws iam delete-role --role-name "${role_name}" 2>/dev/null; then
                        log_success "✅ Deleted IAM role: ${role_name}"
                    else
                        log_error "❌ Failed to delete IAM role: ${role_name}"
                    fi
                fi
            fi
        done
    fi
    
    # Delete custom policies
    if [[ ${#POLICY_ARNS[@]} -gt 0 ]]; then
        for policy_arn in "${POLICY_ARNS[@]}"; do
            if [[ -z "${policy_arn}" ]]; then
                continue
            fi
            
            local policy_name=$(basename "${policy_arn}")
            
            if confirm_action "Delete IAM policy: ${policy_name}"; then
                if [[ "${DRY_RUN}" == "true" ]]; then
                    log_info "[DRY RUN] Would delete IAM policy: ${policy_arn}"
                else
                    log_info "Deleting IAM policy: ${policy_arn}"
                    
                    # List and delete all policy versions (except default)
                    local versions=$(aws iam list-policy-versions --policy-arn "${policy_arn}" \
                        --query "Versions[?!IsDefaultVersion].VersionId" --output text 2>/dev/null || echo "")
                    
                    for version in ${versions}; do
                        if [[ -n "${version}" ]]; then
                            log_debug "Deleting policy version: ${version}"
                            aws iam delete-policy-version --policy-arn "${policy_arn}" \
                                --version-id "${version}" 2>/dev/null || true
                        fi
                    done
                    
                    # Delete the policy
                    if aws iam delete-policy --policy-arn "${policy_arn}" 2>/dev/null; then
                        log_success "✅ Deleted IAM policy: ${policy_name}"
                    else
                        log_error "❌ Failed to delete IAM policy: ${policy_name}"
                    fi
                fi
            fi
        done
    fi
    
    if [[ ${#ROLE_NAMES[@]} -eq 0 && ${#POLICY_ARNS[@]} -eq 0 ]]; then
        log_info "No IAM resources found to delete"
    fi
}

delete_sns_topics() {
    if [[ ${#SNS_TOPIC_ARNS[@]} -eq 0 ]]; then
        log_info "No SNS topics found to delete"
        return 0
    fi
    
    for topic_arn in "${SNS_TOPIC_ARNS[@]}"; do
        if [[ -z "${topic_arn}" ]]; then
            continue
        fi
        
        local topic_name=$(basename "${topic_arn}")
        
        if confirm_action "Delete SNS topic: ${topic_name}"; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY RUN] Would delete SNS topic: ${topic_arn}"
            else
                log_info "Deleting SNS topic: ${topic_arn}"
                
                if aws sns delete-topic --topic-arn "${topic_arn}" 2>/dev/null; then
                    log_success "✅ Deleted SNS topic: ${topic_name}"
                else
                    log_error "❌ Failed to delete SNS topic: ${topic_name}"
                fi
            fi
        fi
    done
}

delete_cloudwatch_dashboards() {
    if [[ ${#DASHBOARD_NAMES[@]} -eq 0 ]]; then
        log_info "No CloudWatch dashboards found to delete"
        return 0
    fi
    
    for dashboard_name in "${DASHBOARD_NAMES[@]}"; do
        if [[ -z "${dashboard_name}" ]]; then
            continue
        fi
        
        if confirm_action "Delete CloudWatch dashboard: ${dashboard_name}"; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY RUN] Would delete CloudWatch dashboard: ${dashboard_name}"
            else
                log_info "Deleting CloudWatch dashboard: ${dashboard_name}"
                
                if aws cloudwatch delete-dashboards --dashboard-names "${dashboard_name}" 2>/dev/null; then
                    log_success "✅ Deleted CloudWatch dashboard: ${dashboard_name}"
                else
                    log_error "❌ Failed to delete CloudWatch dashboard: ${dashboard_name}"
                fi
            fi
        fi
    done
}

# =============================================================================
# Validation and Summary Functions
# =============================================================================

validate_cleanup() {
    log_info "Validating cleanup completion..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would validate cleanup"
        return 0
    fi
    
    local remaining_resources=0
    
    # Check for remaining Cost Anomaly Detection resources
    local remaining_detectors=$(aws ce get-anomaly-detectors \
        --query "AnomalyDetectors[?contains(DetectorName, 'cost-anomaly-detector')]" \
        --output text 2>/dev/null | wc -l)
    
    local remaining_monitors=$(aws ce get-anomaly-monitors \
        --query "AnomalyMonitors[?contains(MonitorName, 'cost-anomaly-monitor')]" \
        --output text 2>/dev/null | wc -l)
    
    # Check for remaining Lambda functions
    local remaining_functions=$(aws lambda list-functions \
        --query "Functions[?contains(FunctionName, 'cost-anomaly-processor')]" \
        --output text 2>/dev/null | wc -l)
    
    # Check for remaining IAM roles
    local remaining_roles=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, 'CostAnomalyLambdaRole')]" \
        --output text 2>/dev/null | wc -l)
    
    # Check for remaining SNS topics
    local remaining_topics=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, 'cost-anomaly-alerts')]" \
        --output text 2>/dev/null | wc -l)
    
    # Check for remaining EventBridge rules
    local remaining_rules=$(aws events list-rules \
        --query "Rules[?contains(Name, 'cost-anomaly-rule')]" \
        --output text 2>/dev/null | wc -l)
    
    # Check for remaining CloudWatch dashboards
    local remaining_dashboards=$(aws cloudwatch list-dashboards \
        --query "DashboardEntries[?contains(DashboardName, 'CostAnomalyDetection')]" \
        --output text 2>/dev/null | wc -l)
    
    remaining_resources=$((remaining_detectors + remaining_monitors + remaining_functions + remaining_roles + remaining_topics + remaining_rules + remaining_dashboards))
    
    if [[ ${remaining_resources} -eq 0 ]]; then
        log_success "✅ Cleanup validation passed - all resources removed"
        return 0
    else
        log_warning "⚠️  Cleanup validation found ${remaining_resources} remaining resources"
        log_info "Detectors: ${remaining_detectors}, Monitors: ${remaining_monitors}, Functions: ${remaining_functions}, Roles: ${remaining_roles}, Topics: ${remaining_topics}, Rules: ${remaining_rules}, Dashboards: ${remaining_dashboards}"
        return 1
    fi
}

show_cleanup_summary() {
    local total_resources=$((${#DETECTOR_ARNS[@]} + ${#MONITOR_ARNS[@]} + ${#FUNCTION_NAMES[@]} + ${#ROLE_NAMES[@]} + ${#POLICY_ARNS[@]} + ${#SNS_TOPIC_ARNS[@]} + ${#RULE_NAMES[@]} + ${#DASHBOARD_NAMES[@]}))
    
    cat << EOF

=============================================================================
CLEANUP SUMMARY
=============================================================================
Resources Discovered:
- Cost Anomaly Detectors:   ${#DETECTOR_ARNS[@]}
- Cost Anomaly Monitors:    ${#MONITOR_ARNS[@]}
- Lambda Functions:         ${#FUNCTION_NAMES[@]}
- IAM Roles:               ${#ROLE_NAMES[@]}
- IAM Policies:            ${#POLICY_ARNS[@]}
- SNS Topics:              ${#SNS_TOPIC_ARNS[@]}
- EventBridge Rules:       ${#RULE_NAMES[@]}
- CloudWatch Dashboards:   ${#DASHBOARD_NAMES[@]}

Total Resources:           ${total_resources}

AWS Region:               $(aws configure get region 2>/dev/null || echo "Not configured")
AWS Account:              $(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "Not available")

Log file:                 ${LOG_FILE}
=============================================================================

EOF
}

# =============================================================================
# Main Cleanup Logic
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            --help)
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
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

cleanup_infrastructure() {
    log_info "Starting AWS Cost Anomaly Detection cleanup..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Initialize log file
    echo "=== AWS Cost Anomaly Detection Cleanup Log ===" > "${LOG_FILE}"
    echo "Started at: $(date)" >> "${LOG_FILE}"
    
    # Discover all resources
    discover_cost_anomaly_resources
    discover_lambda_resources
    discover_iam_resources
    discover_sns_resources
    discover_eventbridge_resources
    discover_cloudwatch_resources
    
    # Show summary before cleanup
    show_cleanup_summary
    
    # Confirm cleanup if not in force mode
    if [[ "${FORCE}" != "true" && "${DRY_RUN}" != "true" ]]; then
        echo ""
        log_warning "This will permanently delete all Cost Anomaly Detection resources!"
        if ! confirm_action "Proceed with cleanup"; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
        echo ""
    fi
    
    # Delete resources in reverse order of creation
    delete_cost_anomaly_detectors
    delete_cost_anomaly_monitors
    delete_eventbridge_rules
    delete_lambda_functions
    delete_iam_resources
    delete_sns_topics
    delete_cloudwatch_dashboards
    
    # Validate cleanup
    if [[ "${DRY_RUN}" != "true" ]]; then
        sleep 5  # Allow time for eventual consistency
        validate_cleanup
    fi
    
    log_success "Cleanup completed!"
}

# =============================================================================
# Script Execution
# =============================================================================

main() {
    parse_arguments "$@"
    check_prerequisites
    cleanup_infrastructure
}

# Execute main function with all arguments
main "$@"