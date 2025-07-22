#!/bin/bash

# AWS Resource Groups Automated Resource Management - Destroy Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="./destroy-$(date +%Y%m%d-%H%M%S).log"
readonly DRY_RUN=${DRY_RUN:-false}

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "$LOG_FILE"
}

# Usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Destroy AWS Resource Groups automated resource management solution.

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Perform a dry run without deleting resources
    -r, --region        AWS region (default: from AWS CLI config)
    -p, --prefix        Resource name prefix to search for (required for auto-discovery)
    -g, --resource-group Resource group name to delete (optional)
    -s, --sns-topic     SNS topic name to delete (optional)
    --skip-confirm      Skip confirmation prompts
    --force             Force deletion without safety checks

EXAMPLES:
    $SCRIPT_NAME --prefix rg-mgmt
    $SCRIPT_NAME --resource-group production-web-app-123456 --sns-topic resource-alerts-123456
    $SCRIPT_NAME --dry-run --prefix rg-mgmt

ENVIRONMENT VARIABLES:
    DRY_RUN            Set to 'true' for dry run mode
    AWS_REGION         Override AWS region
    RESOURCE_PREFIX    Prefix for resource discovery

EOF
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: $aws_version"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid. Run 'aws configure' first."
    fi
    
    # Get account info
    local account_id
    local user_arn
    account_id=$(aws sts get-caller-identity --query Account --output text)
    user_arn=$(aws sts get-caller-identity --query Arn --output text)
    
    info "AWS Account ID: $account_id"
    info "User ARN: $user_arn"
    
    log "Prerequisites check completed"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -p|--prefix)
                RESOURCE_PREFIX="$2"
                shift 2
                ;;
            -g|--resource-group)
                RESOURCE_GROUP_NAME="$2"
                shift 2
                ;;
            -s|--sns-topic)
                SNS_TOPIC_NAME="$2"
                shift 2
                ;;
            --skip-confirm)
                SKIP_CONFIRM=true
                shift
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
}

# Set environment variables
set_environment() {
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Use --region option or configure AWS CLI."
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log "Environment configured:"
    info "  AWS Region: $AWS_REGION"
    info "  AWS Account: $AWS_ACCOUNT_ID"
}

# Discover resources by prefix
discover_resources() {
    if [[ -z "${RESOURCE_PREFIX:-}" ]] && [[ -z "${RESOURCE_GROUP_NAME:-}" ]]; then
        error "Either --prefix or --resource-group must be specified for resource discovery"
    fi
    
    log "Discovering resources..."
    
    # Discover resource groups
    if [[ -n "${RESOURCE_PREFIX:-}" ]]; then
        info "Searching for resource groups with prefix: $RESOURCE_PREFIX"
        
        # Find resource groups
        mapfile -t RESOURCE_GROUPS < <(aws resource-groups list-groups \
            --query "Groups[?starts_with(Name, \`${RESOURCE_PREFIX}\`)].Name" \
            --output text | tr '\t' '\n')
        
        # Find SNS topics
        mapfile -t SNS_TOPICS < <(aws sns list-topics \
            --query "Topics[?contains(TopicArn, \`${RESOURCE_PREFIX}\`)].TopicArn" \
            --output text | tr '\t' '\n')
        
        # Find CloudWatch dashboards
        mapfile -t DASHBOARDS < <(aws cloudwatch list-dashboards \
            --query "DashboardEntries[?starts_with(DashboardName, \`${RESOURCE_PREFIX}\`)].DashboardName" \
            --output text | tr '\t' '\n')
        
        # Find IAM roles
        mapfile -t IAM_ROLES < <(aws iam list-roles \
            --query "Roles[?starts_with(RoleName, \`ResourceGroupAutomationRole\`)].RoleName" \
            --output text | tr '\t' '\n')
        
        # Find Systems Manager documents
        mapfile -t SSM_DOCS < <(aws ssm list-documents \
            --query "DocumentIdentifiers[?starts_with(Name, \`ResourceGroupMaintenance\`) || starts_with(Name, \`AutomatedResourceTagging\`)].Name" \
            --output text | tr '\t' '\n')
        
        # Find EventBridge rules
        mapfile -t EVENT_RULES < <(aws events list-rules \
            --query "Rules[?starts_with(Name, \`AutoTagNewResources\`)].Name" \
            --output text | tr '\t' '\n')
        
        # Find budgets
        mapfile -t BUDGETS < <(aws budgets describe-budgets \
            --account-id "$AWS_ACCOUNT_ID" \
            --query "Budgets[?starts_with(BudgetName, \`ResourceGroup-Budget\`)].BudgetName" \
            --output text | tr '\t' '\n')
        
        # Find CloudWatch alarms
        mapfile -t ALARMS < <(aws cloudwatch describe-alarms \
            --query "MetricAlarms[?starts_with(AlarmName, \`ResourceGroup-\`)].AlarmName" \
            --output text | tr '\t' '\n')
    
    else
        # Use specific resource names
        RESOURCE_GROUPS=("${RESOURCE_GROUP_NAME}")
        if [[ -n "${SNS_TOPIC_NAME:-}" ]]; then
            SNS_TOPICS=("arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}")
        fi
    fi
    
    # Display discovered resources
    info "Discovered resources:"
    info "  Resource Groups: ${#RESOURCE_GROUPS[@]} found"
    for rg in "${RESOURCE_GROUPS[@]:-}"; do
        [[ -n "$rg" ]] && info "    - $rg"
    done
    
    info "  SNS Topics: ${#SNS_TOPICS[@]:-0} found"
    for topic in "${SNS_TOPICS[@]:-}"; do
        [[ -n "$topic" ]] && info "    - $topic"
    done
    
    info "  CloudWatch Dashboards: ${#DASHBOARDS[@]:-0} found"
    for dashboard in "${DASHBOARDS[@]:-}"; do
        [[ -n "$dashboard" ]] && info "    - $dashboard"
    done
    
    info "  IAM Roles: ${#IAM_ROLES[@]:-0} found"
    for role in "${IAM_ROLES[@]:-}"; do
        [[ -n "$role" ]] && info "    - $role"
    done
    
    info "  SSM Documents: ${#SSM_DOCS[@]:-0} found"
    for doc in "${SSM_DOCS[@]:-}"; do
        [[ -n "$doc" ]] && info "    - $doc"
    done
    
    info "  EventBridge Rules: ${#EVENT_RULES[@]:-0} found"
    for rule in "${EVENT_RULES[@]:-}"; do
        [[ -n "$rule" ]] && info "    - $rule"
    done
    
    info "  Budgets: ${#BUDGETS[@]:-0} found"
    for budget in "${BUDGETS[@]:-}"; do
        [[ -n "$budget" ]] && info "    - $budget"
    done
    
    info "  CloudWatch Alarms: ${#ALARMS[@]:-0} found"
    for alarm in "${ALARMS[@]:-}"; do
        [[ -n "$alarm" ]] && info "    - $alarm"
    done
}

# Confirmation prompt
confirm_deletion() {
    if [[ "${SKIP_CONFIRM:-false}" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo
    warn "This will PERMANENTLY DELETE the following AWS resources:"
    
    # Show what will be deleted
    for rg in "${RESOURCE_GROUPS[@]:-}"; do
        [[ -n "$rg" ]] && echo "  🗂️  Resource Group: $rg"
    done
    
    for topic in "${SNS_TOPICS[@]:-}"; do
        [[ -n "$topic" ]] && echo "  📧 SNS Topic: $topic"
    done
    
    for dashboard in "${DASHBOARDS[@]:-}"; do
        [[ -n "$dashboard" ]] && echo "  📊 CloudWatch Dashboard: $dashboard"
    done
    
    for role in "${IAM_ROLES[@]:-}"; do
        [[ -n "$role" ]] && echo "  🔐 IAM Role: $role"
    done
    
    for doc in "${SSM_DOCS[@]:-}"; do
        [[ -n "$doc" ]] && echo "  📄 SSM Document: $doc"
    done
    
    for rule in "${EVENT_RULES[@]:-}"; do
        [[ -n "$rule" ]] && echo "  ⚡ EventBridge Rule: $rule"
    done
    
    for budget in "${BUDGETS[@]:-}"; do
        [[ -n "$budget" ]] && echo "  💰 Budget: $budget"
    done
    
    for alarm in "${ALARMS[@]:-}"; do
        [[ -n "$alarm" ]] && echo "  🔔 CloudWatch Alarm: $alarm"
    done
    
    echo
    warn "This action CANNOT be undone!"
    echo
    
    if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
        read -p "Type 'DELETE' to confirm resource deletion: " -r
        if [[ "$REPLY" != "DELETE" ]]; then
            log "Deletion cancelled by user"
            exit 0
        fi
    fi
}

# Execute command with dry run support
execute() {
    local description="$1"
    shift
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] $description"
        info "[DRY RUN] Command: $*"
        return 0
    fi
    
    info "$description"
    if ! "$@" 2>/dev/null; then
        warn "Failed to execute (continuing): $*"
        return 1
    fi
    return 0
}

# Delete CloudWatch alarms
delete_cloudwatch_alarms() {
    if [[ ${#ALARMS[@]:-0} -eq 0 ]]; then
        info "No CloudWatch alarms to delete"
        return 0
    fi
    
    log "Deleting CloudWatch alarms..."
    
    for alarm in "${ALARMS[@]}"; do
        if [[ -n "$alarm" ]]; then
            execute "Deleting CloudWatch alarm: $alarm" \
                aws cloudwatch delete-alarms --alarm-names "$alarm"
        fi
    done
    
    log "✅ CloudWatch alarms deletion completed"
}

# Delete CloudWatch dashboards
delete_cloudwatch_dashboards() {
    if [[ ${#DASHBOARDS[@]:-0} -eq 0 ]]; then
        info "No CloudWatch dashboards to delete"
        return 0
    fi
    
    log "Deleting CloudWatch dashboards..."
    
    for dashboard in "${DASHBOARDS[@]}"; do
        if [[ -n "$dashboard" ]]; then
            execute "Deleting CloudWatch dashboard: $dashboard" \
                aws cloudwatch delete-dashboards --dashboard-names "$dashboard"
        fi
    done
    
    log "✅ CloudWatch dashboards deletion completed"
}

# Delete EventBridge rules
delete_eventbridge_rules() {
    if [[ ${#EVENT_RULES[@]:-0} -eq 0 ]]; then
        info "No EventBridge rules to delete"
        return 0
    fi
    
    log "Deleting EventBridge rules..."
    
    for rule in "${EVENT_RULES[@]}"; do
        if [[ -n "$rule" ]]; then
            # Remove targets first
            execute "Removing targets from EventBridge rule: $rule" \
                aws events remove-targets --rule "$rule" --ids "1" || true
            
            # Delete rule
            execute "Deleting EventBridge rule: $rule" \
                aws events delete-rule --name "$rule"
        fi
    done
    
    log "✅ EventBridge rules deletion completed"
}

# Delete Systems Manager documents
delete_ssm_documents() {
    if [[ ${#SSM_DOCS[@]:-0} -eq 0 ]]; then
        info "No Systems Manager documents to delete"
        return 0
    fi
    
    log "Deleting Systems Manager documents..."
    
    for doc in "${SSM_DOCS[@]}"; do
        if [[ -n "$doc" ]]; then
            execute "Deleting SSM document: $doc" \
                aws ssm delete-document --name "$doc"
        fi
    done
    
    log "✅ Systems Manager documents deletion completed"
}

# Delete budgets
delete_budgets() {
    if [[ ${#BUDGETS[@]:-0} -eq 0 ]]; then
        info "No budgets to delete"
        return 0
    fi
    
    log "Deleting budgets..."
    
    for budget in "${BUDGETS[@]}"; do
        if [[ -n "$budget" ]]; then
            execute "Deleting budget: $budget" \
                aws budgets delete-budget \
                    --account-id "$AWS_ACCOUNT_ID" \
                    --budget-name "$budget"
        fi
    done
    
    log "✅ Budgets deletion completed"
}

# Delete cost anomaly detectors
delete_cost_anomaly_detectors() {
    log "Deleting cost anomaly detectors..."
    
    # Find detectors that match our naming pattern
    local detector_arns
    mapfile -t detector_arns < <(aws ce get-anomaly-detectors \
        --query "AnomalyDetectors[?starts_with(DetectorName, \`ResourceGroupAnomalyDetector\`)].AnomalyDetectorArn" \
        --output text | tr '\t' '\n')
    
    if [[ ${#detector_arns[@]} -eq 0 ]]; then
        info "No cost anomaly detectors to delete"
        return 0
    fi
    
    for detector_arn in "${detector_arns[@]}"; do
        if [[ -n "$detector_arn" ]]; then
            execute "Deleting cost anomaly detector: $detector_arn" \
                aws ce delete-anomaly-detector --anomaly-detector-arn "$detector_arn"
        fi
    done
    
    log "✅ Cost anomaly detectors deletion completed"
}

# Delete IAM roles
delete_iam_roles() {
    if [[ ${#IAM_ROLES[@]:-0} -eq 0 ]]; then
        info "No IAM roles to delete"
        return 0
    fi
    
    log "Deleting IAM roles..."
    
    for role in "${IAM_ROLES[@]}"; do
        if [[ -n "$role" ]]; then
            # Detach policies first
            info "Detaching policies from IAM role: $role"
            
            # List attached policies
            local attached_policies
            mapfile -t attached_policies < <(aws iam list-attached-role-policies \
                --role-name "$role" \
                --query "AttachedPolicies[].PolicyArn" \
                --output text | tr '\t' '\n')
            
            # Detach each policy
            for policy_arn in "${attached_policies[@]}"; do
                if [[ -n "$policy_arn" ]]; then
                    execute "Detaching policy $policy_arn from role $role" \
                        aws iam detach-role-policy \
                            --role-name "$role" \
                            --policy-arn "$policy_arn"
                fi
            done
            
            # Delete role
            execute "Deleting IAM role: $role" \
                aws iam delete-role --role-name "$role"
        fi
    done
    
    log "✅ IAM roles deletion completed"
}

# Delete SNS topics
delete_sns_topics() {
    if [[ ${#SNS_TOPICS[@]:-0} -eq 0 ]]; then
        info "No SNS topics to delete"
        return 0
    fi
    
    log "Deleting SNS topics..."
    
    for topic_arn in "${SNS_TOPICS[@]}"; do
        if [[ -n "$topic_arn" ]]; then
            execute "Deleting SNS topic: $topic_arn" \
                aws sns delete-topic --topic-arn "$topic_arn"
        fi
    done
    
    log "✅ SNS topics deletion completed"
}

# Delete resource groups
delete_resource_groups() {
    if [[ ${#RESOURCE_GROUPS[@]:-0} -eq 0 ]]; then
        info "No resource groups to delete"
        return 0
    fi
    
    log "Deleting resource groups..."
    
    for rg in "${RESOURCE_GROUPS[@]}"; do
        if [[ -n "$rg" ]]; then
            execute "Deleting resource group: $rg" \
                aws resource-groups delete-group --group-name "$rg"
        fi
    done
    
    log "✅ Resource groups deletion completed"
}

# Validate cleanup
validate_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Skipping validation in dry-run mode"
        return 0
    fi
    
    log "Validating cleanup..."
    
    # Check if resource groups still exist
    local remaining_rgs=0
    for rg in "${RESOURCE_GROUPS[@]:-}"; do
        if [[ -n "$rg" ]] && aws resource-groups get-group --group-name "$rg" &> /dev/null; then
            warn "Resource group still exists: $rg"
            ((remaining_rgs++))
        fi
    done
    
    # Check if SNS topics still exist
    local remaining_topics=0
    for topic_arn in "${SNS_TOPICS[@]:-}"; do
        if [[ -n "$topic_arn" ]] && aws sns get-topic-attributes --topic-arn "$topic_arn" &> /dev/null; then
            warn "SNS topic still exists: $topic_arn"
            ((remaining_topics++))
        fi
    done
    
    if [[ $remaining_rgs -eq 0 && $remaining_topics -eq 0 ]]; then
        log "✅ Cleanup validation passed"
    else
        warn "Some resources may still exist. Check AWS console for manual cleanup."
    fi
}

# Send cleanup notification
send_cleanup_notification() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Dry-run completed successfully"
        return 0
    fi
    
    # Try to find any remaining SNS topics to send notification
    local remaining_topics
    mapfile -t remaining_topics < <(aws sns list-topics \
        --query "Topics[?contains(TopicArn, \`${RESOURCE_PREFIX:-alert}\`)].TopicArn" \
        --output text | tr '\t' '\n' 2>/dev/null || true)
    
    if [[ ${#remaining_topics[@]} -gt 0 && -n "${remaining_topics[0]}" ]]; then
        local message="AWS Resource Groups automated resource management solution cleanup completed."
        
        execute "Sending cleanup notification" \
            aws sns publish \
                --topic-arn "${remaining_topics[0]}" \
                --message "$message" \
                --subject "AWS Resource Management System - Cleanup Complete" || true
    fi
    
    log "✅ Cleanup completed successfully!"
    echo
    echo "📋 CLEANUP SUMMARY"
    echo "=================="
    echo "Region: $AWS_REGION"
    echo "Log file: $LOG_FILE"
    echo
    info "All AWS Resource Groups automated resource management resources have been deleted."
    warn "Please verify in the AWS console that all resources have been properly cleaned up."
}

# Error handling
trap 'error "Script failed at line $LINENO"' ERR

# Main execution
main() {
    log "Starting AWS Resource Groups automated resource management cleanup"
    
    # Parse arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Set environment
    set_environment
    
    # Discover resources
    discover_resources
    
    # Confirm deletion
    confirm_deletion
    
    # Execute cleanup in reverse order of creation
    delete_cloudwatch_alarms
    delete_cloudwatch_dashboards
    delete_eventbridge_rules
    delete_ssm_documents
    delete_budgets
    delete_cost_anomaly_detectors
    delete_iam_roles
    delete_sns_topics
    delete_resource_groups
    
    # Validate cleanup
    validate_cleanup
    
    # Send cleanup notification
    send_cleanup_notification
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi