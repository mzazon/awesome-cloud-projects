#!/bin/bash

# AWS Chaos Engineering Testing with FIS and EventBridge - Cleanup Script
# This script removes all chaos engineering infrastructure including
# FIS experiment templates, EventBridge rules, CloudWatch alarms, and SNS notifications

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ENV_FILE="${SCRIPT_DIR}/.env"
FORCE_DELETE="${FORCE_DELETE:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Start logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

log_info "Starting AWS Chaos Engineering cleanup..."
log_info "Cleanup log: $LOG_FILE"

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "Environment file not found: $ENV_FILE"
        log_info "This could mean the deployment was not completed or the environment file was deleted."
        log_info "You may need to manually clean up resources or run the script with manual resource identification."
        exit 1
    fi
    
    # Source the environment file
    source "$ENV_FILE"
    
    # Validate required variables
    if [[ -z "${AWS_REGION:-}" ]] || [[ -z "${AWS_ACCOUNT_ID:-}" ]] || [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        log_error "Missing required environment variables in $ENV_FILE"
        log_info "Required variables: AWS_REGION, AWS_ACCOUNT_ID, RANDOM_SUFFIX"
        exit 1
    fi
    
    log_success "Environment variables loaded successfully"
    log_info "AWS Region: $AWS_REGION"
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    log_info "Resource Suffix: $RANDOM_SUFFIX"
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Verify account ID matches
    local current_account_id
    current_account_id=$(aws sts get-caller-identity --query Account --output text)
    if [[ "$current_account_id" != "$AWS_ACCOUNT_ID" ]]; then
        log_warning "Current AWS account ($current_account_id) differs from deployment account ($AWS_ACCOUNT_ID)"
        if [[ "$FORCE_DELETE" != "true" ]]; then
            read -p "Continue with cleanup? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Cleanup cancelled by user"
                exit 0
            fi
        fi
    fi
    
    log_success "Prerequisites validated successfully"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_warning "This will DELETE all chaos engineering resources in region: $AWS_REGION"
    log_warning "Resources to be deleted:"
    echo "- FIS Experiment Template: ${TEMPLATE_ID:-unknown}"
    echo "- SNS Topic: ${SNS_TOPIC_ARN:-unknown}"
    echo "- CloudWatch Dashboard: ${DASHBOARD_NAME:-unknown}"
    echo "- EventBridge Rules and Schedules"
    echo "- IAM Roles and Policies"
    echo "- CloudWatch Alarms"
    echo ""
    
    read -p "Are you sure you want to proceed? This action cannot be undone. (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Stop any running experiments
stop_running_experiments() {
    log_info "Checking for running experiments..."
    
    if [[ -z "${TEMPLATE_ID:-}" ]]; then
        log_warning "Template ID not found, skipping experiment check"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would check and stop running experiments"
        return 0
    fi
    
    # Get running experiments for this template
    local running_experiments
    running_experiments=$(aws fis list-experiments \
        --query "experiments[?experimentTemplateId=='${TEMPLATE_ID}' && state.status=='running'].id" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$running_experiments" ]]; then
        log_warning "Found running experiments, stopping them..."
        for exp_id in $running_experiments; do
            log_info "Stopping experiment: $exp_id"
            aws fis stop-experiment --id "$exp_id" >/dev/null 2>&1 || log_warning "Failed to stop experiment $exp_id"
        done
        
        # Wait for experiments to stop
        log_info "Waiting for experiments to stop (up to 60 seconds)..."
        local wait_count=0
        while [[ $wait_count -lt 12 ]]; do
            local still_running
            still_running=$(aws fis list-experiments \
                --query "experiments[?experimentTemplateId=='${TEMPLATE_ID}' && state.status=='running'].id" \
                --output text 2>/dev/null || echo "")
            
            if [[ -z "$still_running" ]]; then
                log_success "All experiments stopped successfully"
                break
            fi
            
            sleep 5
            ((wait_count++))
        done
        
        if [[ $wait_count -eq 12 ]]; then
            log_warning "Some experiments may still be running. Proceeding with cleanup..."
        fi
    else
        log_success "No running experiments found"
    fi
}

# Delete EventBridge schedules and rules
delete_eventbridge_resources() {
    log_info "Deleting EventBridge schedules and rules..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would delete EventBridge resources"
        return 0
    fi
    
    # Delete scheduler
    if [[ -n "${SCHEDULER_NAME:-}" ]]; then
        log_info "Deleting EventBridge scheduler: $SCHEDULER_NAME"
        aws scheduler delete-schedule --name "$SCHEDULER_NAME" 2>/dev/null || log_warning "Failed to delete scheduler $SCHEDULER_NAME"
    fi
    
    # Remove targets from EventBridge rule
    if [[ -n "${EB_RULE_NAME:-}" ]]; then
        log_info "Removing targets from EventBridge rule: $EB_RULE_NAME"
        aws events remove-targets \
            --rule "$EB_RULE_NAME" \
            --ids "1" 2>/dev/null || log_warning "Failed to remove targets from rule $EB_RULE_NAME"
        
        # Delete EventBridge rule
        log_info "Deleting EventBridge rule: $EB_RULE_NAME"
        aws events delete-rule --name "$EB_RULE_NAME" 2>/dev/null || log_warning "Failed to delete rule $EB_RULE_NAME"
    fi
    
    log_success "EventBridge resources deletion completed"
}

# Delete FIS experiment template
delete_fis_template() {
    log_info "Deleting FIS experiment template..."
    
    if [[ -z "${TEMPLATE_ID:-}" ]]; then
        log_warning "Template ID not found, skipping FIS template deletion"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would delete FIS template $TEMPLATE_ID"
        return 0
    fi
    
    log_info "Deleting FIS experiment template: $TEMPLATE_ID"
    if aws fis delete-experiment-template --id "$TEMPLATE_ID" 2>/dev/null; then
        log_success "FIS experiment template deleted successfully"
    else
        log_warning "Failed to delete FIS experiment template $TEMPLATE_ID (may not exist)"
    fi
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log_info "Deleting CloudWatch resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would delete CloudWatch resources"
        return 0
    fi
    
    # Delete CloudWatch alarms
    local alarms_to_delete=()
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        alarms_to_delete=(
            "FIS-HighErrorRate-${RANDOM_SUFFIX}"
            "FIS-HighCPU-${RANDOM_SUFFIX}"
        )
    fi
    
    if [[ ${#alarms_to_delete[@]} -gt 0 ]]; then
        log_info "Deleting CloudWatch alarms..."
        for alarm in "${alarms_to_delete[@]}"; do
            aws cloudwatch delete-alarms --alarm-names "$alarm" 2>/dev/null || log_warning "Failed to delete alarm $alarm"
        done
    fi
    
    # Delete CloudWatch dashboard
    if [[ -n "${DASHBOARD_NAME:-}" ]]; then
        log_info "Deleting CloudWatch dashboard: $DASHBOARD_NAME"
        aws cloudwatch delete-dashboards --dashboard-names "$DASHBOARD_NAME" 2>/dev/null || log_warning "Failed to delete dashboard $DASHBOARD_NAME"
    fi
    
    log_success "CloudWatch resources deletion completed"
}

# Delete IAM roles and policies
delete_iam_resources() {
    log_info "Deleting IAM roles and policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would delete IAM resources"
        return 0
    fi
    
    # Delete FIS IAM role
    if [[ -n "${FIS_ROLE_NAME:-}" ]]; then
        log_info "Deleting FIS IAM role: $FIS_ROLE_NAME"
        
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name "$FIS_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/PowerUserAccess 2>/dev/null || true
        
        # Delete the role
        aws iam delete-role --role-name "$FIS_ROLE_NAME" 2>/dev/null || log_warning "Failed to delete IAM role $FIS_ROLE_NAME"
    fi
    
    # Delete EventBridge IAM role
    if [[ -n "${EB_ROLE_NAME:-}" ]]; then
        log_info "Deleting EventBridge IAM role: $EB_ROLE_NAME"
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "$EB_ROLE_NAME" \
            --policy-name SNSPublishPolicy 2>/dev/null || true
        
        # Delete the role
        aws iam delete-role --role-name "$EB_ROLE_NAME" 2>/dev/null || log_warning "Failed to delete IAM role $EB_ROLE_NAME"
    fi
    
    # Delete Scheduler IAM role
    if [[ -n "${SCHEDULER_ROLE_NAME:-}" ]]; then
        log_info "Deleting Scheduler IAM role: $SCHEDULER_ROLE_NAME"
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name "$SCHEDULER_ROLE_NAME" \
            --policy-name FISStartExperimentPolicy 2>/dev/null || true
        
        # Delete the role
        aws iam delete-role --role-name "$SCHEDULER_ROLE_NAME" 2>/dev/null || log_warning "Failed to delete IAM role $SCHEDULER_ROLE_NAME"
    fi
    
    log_success "IAM resources deletion completed"
}

# Delete SNS resources
delete_sns_resources() {
    log_info "Deleting SNS resources..."
    
    if [[ -z "${SNS_TOPIC_ARN:-}" ]]; then
        log_warning "SNS Topic ARN not found, skipping SNS deletion"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would delete SNS topic $SNS_TOPIC_ARN"
        return 0
    fi
    
    log_info "Deleting SNS topic: $SNS_TOPIC_ARN"
    if aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" 2>/dev/null; then
        log_success "SNS topic deleted successfully"
    else
        log_warning "Failed to delete SNS topic $SNS_TOPIC_ARN (may not exist)"
    fi
}

# Clean up temporary and configuration files
cleanup_files() {
    log_info "Cleaning up temporary and configuration files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would clean up files"
        return 0
    fi
    
    # Remove temporary files that might be left over
    local temp_files=(
        "${SCRIPT_DIR}/fis-trust-policy.json"
        "${SCRIPT_DIR}/eventbridge-trust-policy.json"
        "${SCRIPT_DIR}/scheduler-trust-policy.json"
        "${SCRIPT_DIR}/experiment-template.json"
        "${SCRIPT_DIR}/dashboard-config.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed temporary file: $(basename "$file")"
        fi
    done
    
    # Remove environment file (keep it for now, user can delete manually)
    log_info "Keeping environment file for reference: $ENV_FILE"
    log_info "You can manually delete it when no longer needed"
    
    log_success "File cleanup completed"
}

# Validate cleanup
validate_cleanup() {
    log_info "Validating cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Skipping validation"
        return 0
    fi
    
    local cleanup_issues=0
    
    # Check if FIS template still exists
    if [[ -n "${TEMPLATE_ID:-}" ]]; then
        if aws fis get-experiment-template --id "$TEMPLATE_ID" >/dev/null 2>&1; then
            log_warning "FIS experiment template still exists: $TEMPLATE_ID"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if SNS topic still exists
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" >/dev/null 2>&1; then
            log_warning "SNS topic still exists: $SNS_TOPIC_ARN"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if EventBridge rule still exists
    if [[ -n "${EB_RULE_NAME:-}" ]]; then
        if aws events describe-rule --name "$EB_RULE_NAME" >/dev/null 2>&1; then
            log_warning "EventBridge rule still exists: $EB_RULE_NAME"
            ((cleanup_issues++))
        fi
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "Cleanup validation completed successfully"
    else
        log_warning "Cleanup validation found $cleanup_issues potential issues"
        log_info "Some resources may need manual cleanup"
    fi
}

# Print cleanup summary
print_summary() {
    log_info "Cleanup Summary:"
    echo "===================="
    echo "AWS Region: ${AWS_REGION:-unknown}"
    echo "AWS Account ID: ${AWS_ACCOUNT_ID:-unknown}"
    echo "Resource Suffix: ${RANDOM_SUFFIX:-unknown}"
    echo ""
    echo "Deleted Resources:"
    echo "- FIS Experiment Template: ${TEMPLATE_ID:-unknown}"
    echo "- SNS Topic: ${SNS_TOPIC_ARN:-unknown}"
    echo "- CloudWatch Dashboard: ${DASHBOARD_NAME:-unknown}"
    echo "- EventBridge Rules and Schedules"
    echo "- IAM Roles and Policies"
    echo "- CloudWatch Alarms"
    echo ""
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "All chaos engineering resources have been removed."
        echo "Environment file preserved at: $ENV_FILE"
    else
        echo "DRY RUN completed - no resources were actually deleted."
    fi
    echo "===================="
}

# Main execution
main() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE: No resources will be deleted"
    fi
    
    load_environment
    validate_prerequisites
    confirm_deletion
    stop_running_experiments
    delete_eventbridge_resources
    delete_fis_template
    delete_cloudwatch_resources
    delete_iam_resources
    delete_sns_resources
    cleanup_files
    validate_cleanup
    print_summary
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log_success "AWS Chaos Engineering cleanup completed successfully!"
    else
        log_info "DRY RUN completed - review the output above for what would be deleted"
    fi
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force     Skip confirmation prompts"
            echo "  --dry-run   Show what would be deleted without actually deleting"
            echo "  --help      Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  FORCE_DELETE=true   Same as --force"
            echo "  DRY_RUN=true        Same as --dry-run"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"