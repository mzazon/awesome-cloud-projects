#!/bin/bash

# =============================================================================
# AWS Database Monitoring Dashboards Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script:
# - CloudWatch alarms and dashboards
# - SNS topics and subscriptions
# - RDS instances (with optional final snapshot)
# - IAM roles and policies
# 
# Author: AWS Recipe Generator
# Version: 1.0
# Last Updated: 2025-01-17
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"
readonly STATE_FILE="${SCRIPT_DIR}/deployment_state.env"

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
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() {
    echo -e "${BLUE}ℹ${NC} $*"
    log "INFO" "$*"
}

success() {
    echo -e "${GREEN}✅${NC} $*"
    log "SUCCESS" "$*"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $*"
    log "WARNING" "$*"
}

error() {
    echo -e "${RED}❌${NC} $*" >&2
    log "ERROR" "$*"
}

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Cleanup failed with exit code: $exit_code"
        error "Check the log file for details: ${LOG_FILE}"
        warning "Some resources may still exist and incur charges"
        warning "Please check AWS console and manually remove remaining resources"
    fi
}

wait_for_deletion() {
    local resource_type=$1
    local resource_id=$2
    local max_attempts=${3:-20}
    local wait_time=${4:-30}
    
    info "Waiting for ${resource_type} ${resource_id} to be deleted..."
    
    case "${resource_type}" in
        "rds-instance")
            local attempt=0
            while [[ $attempt -lt $max_attempts ]]; do
                if ! aws rds describe-db-instances \
                    --db-instance-identifier "${resource_id}" \
                    --query 'DBInstances[0].DBInstanceStatus' \
                    --output text &> /dev/null; then
                    success "${resource_type} ${resource_id} has been deleted"
                    return 0
                fi
                
                ((attempt++))
                info "Attempt ${attempt}/${max_attempts} - still waiting..."
                sleep "${wait_time}"
            done
            
            error "Timeout waiting for ${resource_type} ${resource_id} deletion"
            return 1
            ;;
        *)
            error "Unknown resource type: ${resource_type}"
            return 1
            ;;
    esac
}

# =============================================================================
# Validation Functions
# =============================================================================

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

load_deployment_state() {
    info "Loading deployment state..."
    
    if [[ ! -f "${STATE_FILE}" ]]; then
        warning "Deployment state file not found: ${STATE_FILE}"
        warning "You will need to manually specify resource identifiers"
        return 1
    fi
    
    # Source the state file
    # shellcheck source=/dev/null
    source "${STATE_FILE}"
    
    # Validate required variables
    local required_vars=("DB_INSTANCE_ID" "SNS_TOPIC_NAME" "DASHBOARD_NAME" "IAM_ROLE_NAME" "AWS_REGION")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("${var}")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        error "Missing required variables in state file: ${missing_vars[*]}"
        return 1
    fi
    
    info "Deployment state loaded successfully:"
    info "  DB Instance ID: ${DB_INSTANCE_ID}"
    info "  SNS Topic: ${SNS_TOPIC_NAME}"
    info "  Dashboard: ${DASHBOARD_NAME}"
    info "  IAM Role: ${IAM_ROLE_NAME}"
    info "  AWS Region: ${AWS_REGION}"
    
    # Set AWS region if not already set
    if [[ -z "${AWS_DEFAULT_REGION:-}" ]]; then
        export AWS_DEFAULT_REGION="${AWS_REGION}"
    fi
    
    success "Deployment state loaded"
    return 0
}

prompt_user_confirmation() {
    echo
    warning "This script will DELETE the following AWS resources:"
    echo "  • RDS Instance: ${DB_INSTANCE_ID:-<unknown>}"
    echo "  • CloudWatch Dashboard: ${DASHBOARD_NAME:-<unknown>}"
    echo "  • CloudWatch Alarms (4 alarms)"
    echo "  • SNS Topic: ${SNS_TOPIC_NAME:-<unknown>}"
    echo "  • IAM Role: ${IAM_ROLE_NAME:-<unknown>}"
    echo
    error "THIS ACTION CANNOT BE UNDONE!"
    echo
    
    if [[ "${SKIP_CONFIRMATION:-false}" != "true" ]]; then
        echo "Type 'DELETE' to confirm resource deletion:"
        read -r confirmation
        
        if [[ "${confirmation}" != "DELETE" ]]; then
            info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Ask about final snapshot for RDS
    if [[ "${SKIP_FINAL_SNAPSHOT:-false}" != "true" ]]; then
        echo
        warning "Do you want to create a final snapshot of the RDS instance before deletion?"
        warning "This will preserve your data but incur additional storage costs."
        echo
        read -p "Create final snapshot? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            export CREATE_FINAL_SNAPSHOT="true"
            export FINAL_SNAPSHOT_ID="${DB_INSTANCE_ID:-unknown}-final-$(date +%Y%m%d-%H%M%S)"
            info "Final snapshot will be created: ${FINAL_SNAPSHOT_ID}"
        else
            export CREATE_FINAL_SNAPSHOT="false"
            warning "No final snapshot will be created - all data will be lost!"
        fi
    else
        export CREATE_FINAL_SNAPSHOT="false"
    fi
}

get_manual_resource_ids() {
    warning "Manual resource identification required"
    echo
    
    if [[ -z "${DB_INSTANCE_ID:-}" ]]; then
        echo "Available RDS instances:"
        aws rds describe-db-instances \
            --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]' \
            --output table 2>/dev/null || echo "No RDS instances found or permission denied"
        echo
        read -p "Enter RDS Instance ID to delete (or press Enter to skip): " DB_INSTANCE_ID
    fi
    
    if [[ -z "${DASHBOARD_NAME:-}" ]]; then
        echo "Available CloudWatch dashboards:"
        aws cloudwatch list-dashboards \
            --query 'DashboardEntries[*].DashboardName' \
            --output table 2>/dev/null || echo "No dashboards found or permission denied"
        echo
        read -p "Enter Dashboard Name to delete (or press Enter to skip): " DASHBOARD_NAME
    fi
    
    if [[ -z "${SNS_TOPIC_NAME:-}" ]]; then
        echo "Available SNS topics:"
        aws sns list-topics \
            --query 'Topics[*].TopicArn' \
            --output table 2>/dev/null || echo "No topics found or permission denied"
        echo
        read -p "Enter SNS Topic Name to delete (or press Enter to skip): " SNS_TOPIC_NAME
    fi
    
    if [[ -z "${IAM_ROLE_NAME:-}" ]]; then
        echo "Available IAM roles (showing RDS monitoring roles):"
        aws iam list-roles \
            --query 'Roles[?contains(RoleName, `monitoring`) || contains(RoleName, `rds`)].RoleName' \
            --output table 2>/dev/null || echo "No roles found or permission denied"
        echo
        read -p "Enter IAM Role Name to delete (or press Enter to skip): " IAM_ROLE_NAME
    fi
    
    # Set AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "${AWS_REGION}" ]]; then
            read -p "Enter AWS Region: " AWS_REGION
        fi
    fi
    
    export DB_INSTANCE_ID DASHBOARD_NAME SNS_TOPIC_NAME IAM_ROLE_NAME AWS_REGION
}

# =============================================================================
# Resource Deletion Functions
# =============================================================================

delete_cloudwatch_alarms() {
    if [[ -z "${DB_INSTANCE_ID:-}" ]]; then
        warning "DB Instance ID not available, skipping alarm deletion"
        return 0
    fi
    
    info "Deleting CloudWatch alarms..."
    
    # List of alarms to delete
    local alarms=(
        "${DB_INSTANCE_ID}-HighCPU"
        "${DB_INSTANCE_ID}-HighConnections"
        "${DB_INSTANCE_ID}-LowStorage"
        "${DB_INSTANCE_ID}-HighReadLatency"
    )
    
    local deleted_count=0
    local failed_count=0
    
    for alarm in "${alarms[@]}"; do
        # Check if alarm exists
        if aws cloudwatch describe-alarms \
            --alarm-names "${alarm}" \
            --query 'MetricAlarms[0].AlarmName' \
            --output text &> /dev/null; then
            
            if aws cloudwatch delete-alarms \
                --alarm-names "${alarm}" \
                --output text >> "${LOG_FILE}" 2>&1; then
                success "Deleted alarm: ${alarm}"
                ((deleted_count++))
            else
                error "Failed to delete alarm: ${alarm}"
                ((failed_count++))
            fi
        else
            info "Alarm not found (may already be deleted): ${alarm}"
        fi
    done
    
    if [[ $failed_count -eq 0 ]]; then
        success "All CloudWatch alarms deleted (${deleted_count} alarms)"
    else
        warning "Some alarms could not be deleted (${failed_count} failed, ${deleted_count} succeeded)"
    fi
}

delete_cloudwatch_dashboard() {
    if [[ -z "${DASHBOARD_NAME:-}" ]]; then
        warning "Dashboard name not available, skipping dashboard deletion"
        return 0
    fi
    
    info "Deleting CloudWatch dashboard: ${DASHBOARD_NAME}"
    
    # Check if dashboard exists
    if aws cloudwatch get-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --query 'DashboardName' --output text &> /dev/null; then
        
        if aws cloudwatch delete-dashboards \
            --dashboard-names "${DASHBOARD_NAME}" \
            --output text >> "${LOG_FILE}" 2>&1; then
            success "CloudWatch dashboard deleted: ${DASHBOARD_NAME}"
        else
            error "Failed to delete CloudWatch dashboard: ${DASHBOARD_NAME}"
            return 1
        fi
    else
        info "Dashboard not found (may already be deleted): ${DASHBOARD_NAME}"
    fi
}

delete_sns_topic() {
    if [[ -z "${SNS_TOPIC_NAME:-}" ]]; then
        warning "SNS topic name not available, skipping SNS deletion"
        return 0
    fi
    
    info "Deleting SNS topic: ${SNS_TOPIC_NAME}"
    
    # Get topic ARN
    local topic_arn
    topic_arn=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
        --output text 2>/dev/null)
    
    if [[ -n "${topic_arn}" && "${topic_arn}" != "None" ]]; then
        # List and delete subscriptions first
        local subscriptions
        subscriptions=$(aws sns list-subscriptions-by-topic \
            --topic-arn "${topic_arn}" \
            --query 'Subscriptions[*].SubscriptionArn' \
            --output text 2>/dev/null)
        
        if [[ -n "${subscriptions}" && "${subscriptions}" != "None" ]]; then
            info "Deleting SNS subscriptions..."
            for subscription_arn in ${subscriptions}; do
                if [[ "${subscription_arn}" != "PendingConfirmation" ]]; then
                    if aws sns unsubscribe \
                        --subscription-arn "${subscription_arn}" \
                        --output text >> "${LOG_FILE}" 2>&1; then
                        success "Deleted subscription: ${subscription_arn}"
                    else
                        warning "Failed to delete subscription: ${subscription_arn}"
                    fi
                fi
            done
        fi
        
        # Delete the topic
        if aws sns delete-topic \
            --topic-arn "${topic_arn}" \
            --output text >> "${LOG_FILE}" 2>&1; then
            success "SNS topic deleted: ${SNS_TOPIC_NAME}"
        else
            error "Failed to delete SNS topic: ${SNS_TOPIC_NAME}"
            return 1
        fi
    else
        info "SNS topic not found (may already be deleted): ${SNS_TOPIC_NAME}"
    fi
}

delete_rds_instance() {
    if [[ -z "${DB_INSTANCE_ID:-}" ]]; then
        warning "DB Instance ID not available, skipping RDS deletion"
        return 0
    fi
    
    info "Deleting RDS instance: ${DB_INSTANCE_ID}"
    
    # Check if instance exists
    local db_status
    db_status=$(aws rds describe-db-instances \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --query 'DBInstances[0].DBInstanceStatus' \
        --output text 2>/dev/null)
    
    if [[ -n "${db_status}" && "${db_status}" != "None" ]]; then
        info "Current RDS instance status: ${db_status}"
        
        # Disable deletion protection if enabled
        local deletion_protection
        deletion_protection=$(aws rds describe-db-instances \
            --db-instance-identifier "${DB_INSTANCE_ID}" \
            --query 'DBInstances[0].DeletionProtection' \
            --output text 2>/dev/null)
        
        if [[ "${deletion_protection}" == "true" ]]; then
            info "Disabling deletion protection..."
            if aws rds modify-db-instance \
                --db-instance-identifier "${DB_INSTANCE_ID}" \
                --no-deletion-protection \
                --apply-immediately \
                --output text >> "${LOG_FILE}" 2>&1; then
                success "Deletion protection disabled"
                # Wait a moment for the modification to take effect
                sleep 10
            else
                error "Failed to disable deletion protection"
                return 1
            fi
        fi
        
        # Prepare delete command
        local delete_cmd="aws rds delete-db-instance --db-instance-identifier ${DB_INSTANCE_ID}"
        
        if [[ "${CREATE_FINAL_SNAPSHOT:-false}" == "true" ]]; then
            delete_cmd+=" --final-db-snapshot-identifier ${FINAL_SNAPSHOT_ID}"
            info "Creating final snapshot: ${FINAL_SNAPSHOT_ID}"
        else
            delete_cmd+=" --skip-final-snapshot"
            warning "Skipping final snapshot - all data will be lost"
        fi
        
        # Delete the instance
        if eval "${delete_cmd} --output text >> ${LOG_FILE} 2>&1"; then
            success "RDS instance deletion initiated: ${DB_INSTANCE_ID}"
            
            # Wait for deletion to complete
            wait_for_deletion "rds-instance" "${DB_INSTANCE_ID}"
        else
            error "Failed to delete RDS instance: ${DB_INSTANCE_ID}"
            return 1
        fi
    else
        info "RDS instance not found (may already be deleted): ${DB_INSTANCE_ID}"
    fi
}

delete_iam_role() {
    if [[ -z "${IAM_ROLE_NAME:-}" ]]; then
        warning "IAM role name not available, skipping IAM deletion"
        return 0
    fi
    
    info "Deleting IAM role: ${IAM_ROLE_NAME}"
    
    # Check if role exists
    if aws iam get-role \
        --role-name "${IAM_ROLE_NAME}" \
        --query 'Role.RoleName' --output text &> /dev/null; then
        
        # Detach all attached policies
        info "Detaching policies from IAM role..."
        local attached_policies
        attached_policies=$(aws iam list-attached-role-policies \
            --role-name "${IAM_ROLE_NAME}" \
            --query 'AttachedPolicies[*].PolicyArn' \
            --output text 2>/dev/null)
        
        if [[ -n "${attached_policies}" && "${attached_policies}" != "None" ]]; then
            for policy_arn in ${attached_policies}; do
                if aws iam detach-role-policy \
                    --role-name "${IAM_ROLE_NAME}" \
                    --policy-arn "${policy_arn}" \
                    --output text >> "${LOG_FILE}" 2>&1; then
                    success "Detached policy: ${policy_arn}"
                else
                    warning "Failed to detach policy: ${policy_arn}"
                fi
            done
        fi
        
        # Delete inline policies if any
        local inline_policies
        inline_policies=$(aws iam list-role-policies \
            --role-name "${IAM_ROLE_NAME}" \
            --query 'PolicyNames' \
            --output text 2>/dev/null)
        
        if [[ -n "${inline_policies}" && "${inline_policies}" != "None" ]]; then
            for policy_name in ${inline_policies}; do
                if aws iam delete-role-policy \
                    --role-name "${IAM_ROLE_NAME}" \
                    --policy-name "${policy_name}" \
                    --output text >> "${LOG_FILE}" 2>&1; then
                    success "Deleted inline policy: ${policy_name}"
                else
                    warning "Failed to delete inline policy: ${policy_name}"
                fi
            done
        fi
        
        # Delete the role
        if aws iam delete-role \
            --role-name "${IAM_ROLE_NAME}" \
            --output text >> "${LOG_FILE}" 2>&1; then
            success "IAM role deleted: ${IAM_ROLE_NAME}"
        else
            error "Failed to delete IAM role: ${IAM_ROLE_NAME}"
            return 1
        fi
    else
        info "IAM role not found (may already be deleted): ${IAM_ROLE_NAME}"
    fi
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_cleanup() {
    info "Validating cleanup..."
    local cleanup_issues=()
    
    # Check RDS instance
    if [[ -n "${DB_INSTANCE_ID:-}" ]]; then
        if aws rds describe-db-instances \
            --db-instance-identifier "${DB_INSTANCE_ID}" \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text &> /dev/null; then
            cleanup_issues+=("RDS instance still exists: ${DB_INSTANCE_ID}")
        else
            success "RDS instance deleted: ${DB_INSTANCE_ID}"
        fi
    fi
    
    # Check dashboard
    if [[ -n "${DASHBOARD_NAME:-}" ]]; then
        if aws cloudwatch get-dashboard \
            --dashboard-name "${DASHBOARD_NAME}" \
            --query 'DashboardName' --output text &> /dev/null; then
            cleanup_issues+=("CloudWatch dashboard still exists: ${DASHBOARD_NAME}")
        else
            success "CloudWatch dashboard deleted: ${DASHBOARD_NAME}"
        fi
    fi
    
    # Check SNS topic
    if [[ -n "${SNS_TOPIC_NAME:-}" ]]; then
        local topic_arn
        topic_arn=$(aws sns list-topics \
            --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
            --output text 2>/dev/null)
        
        if [[ -n "${topic_arn}" && "${topic_arn}" != "None" ]]; then
            cleanup_issues+=("SNS topic still exists: ${SNS_TOPIC_NAME}")
        else
            success "SNS topic deleted: ${SNS_TOPIC_NAME}"
        fi
    fi
    
    # Check IAM role
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        if aws iam get-role \
            --role-name "${IAM_ROLE_NAME}" \
            --query 'Role.RoleName' --output text &> /dev/null; then
            cleanup_issues+=("IAM role still exists: ${IAM_ROLE_NAME}")
        else
            success "IAM role deleted: ${IAM_ROLE_NAME}"
        fi
    fi
    
    # Report results
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        success "All resources have been successfully deleted"
        return 0
    else
        warning "Some resources may still exist:"
        for issue in "${cleanup_issues[@]}"; do
            warning "  ${issue}"
        done
        warning "Please check AWS console and manually remove remaining resources"
        return 1
    fi
}

cleanup_state_file() {
    if [[ -f "${STATE_FILE}" ]]; then
        info "Removing deployment state file..."
        if rm -f "${STATE_FILE}"; then
            success "State file removed: ${STATE_FILE}"
        else
            warning "Could not remove state file: ${STATE_FILE}"
        fi
    fi
}

# =============================================================================
# Main Cleanup Function
# =============================================================================

main() {
    echo "======================================================================="
    echo "        AWS Database Monitoring Dashboards Cleanup"
    echo "======================================================================="
    echo
    
    # Set up trap for cleanup on exit
    trap cleanup_on_exit EXIT
    
    # Check prerequisites
    check_prerequisites
    
    # Try to load deployment state
    if ! load_deployment_state; then
        warning "Could not load deployment state automatically"
        get_manual_resource_ids
    fi
    
    # Prompt for user confirmation
    prompt_user_confirmation
    
    echo
    info "Starting cleanup process..."
    echo
    
    # Delete resources in reverse order of creation
    delete_cloudwatch_alarms
    delete_cloudwatch_dashboard
    delete_sns_topic
    delete_rds_instance
    delete_iam_role
    
    echo
    info "Validating cleanup..."
    local validation_result=0
    validate_cleanup || validation_result=$?
    
    # Clean up state file
    cleanup_state_file
    
    echo
    if [[ $validation_result -eq 0 ]]; then
        echo "======================================================================="
        echo "                    CLEANUP COMPLETED SUCCESSFULLY"
        echo "======================================================================="
        echo
        success "All database monitoring resources have been deleted!"
        echo
        info "Final snapshot created: ${FINAL_SNAPSHOT_ID:-None}"
        info "Log file: ${LOG_FILE}"
        echo
        success "No further charges will be incurred from this deployment"
    else
        echo "======================================================================="
        echo "                    CLEANUP COMPLETED WITH WARNINGS"
        echo "======================================================================="
        echo
        warning "Some resources may still exist and could incur charges"
        warning "Please check the AWS console and manually remove any remaining resources"
        echo
        info "Log file: ${LOG_FILE}"
    fi
    
    echo
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-confirmation)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        --skip-final-snapshot)
            SKIP_FINAL_SNAPSHOT="true"
            CREATE_FINAL_SNAPSHOT="false"
            shift
            ;;
        --db-instance-id)
            DB_INSTANCE_ID="$2"
            shift 2
            ;;
        --dashboard-name)
            DASHBOARD_NAME="$2"
            shift 2
            ;;
        --sns-topic-name)
            SNS_TOPIC_NAME="$2"
            shift 2
            ;;
        --iam-role-name)
            IAM_ROLE_NAME="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-confirmation       Skip user confirmation prompts"
            echo "  --skip-final-snapshot     Do not create RDS final snapshot"
            echo "  --db-instance-id ID       Specify DB instance ID to delete"
            echo "  --dashboard-name NAME     Specify dashboard name to delete"
            echo "  --sns-topic-name NAME     Specify SNS topic name to delete"
            echo "  --iam-role-name NAME      Specify IAM role name to delete"
            echo "  --region REGION           Specify AWS region"
            echo "  --help                    Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  SKIP_CONFIRMATION         Skip confirmation (true/false)"
            echo "  SKIP_FINAL_SNAPSHOT       Skip final snapshot (true/false)"
            echo ""
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"