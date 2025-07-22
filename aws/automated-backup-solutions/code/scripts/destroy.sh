#!/bin/bash

# AWS Backup Automated Solution Cleanup Script
# Safely removes all backup infrastructure resources

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
VARS_FILE="${SCRIPT_DIR}/deploy_vars.env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "${ERROR_LOG}"
    echo -e "${RED}ERROR: $1${NC}" >&2
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Confirmation prompt
confirm_deletion() {
    echo
    echo "=================================================="
    echo "WARNING: This will delete the following resources:"
    echo "=================================================="
    echo "- Backup plans and selections"
    echo "- Backup vaults (if empty)"
    echo "- CloudWatch alarms"
    echo "- SNS topics"
    echo "- IAM roles and policies"
    echo "- Config rules"
    echo "- S3 buckets (if empty)"
    echo "- All configuration files"
    echo
    echo -e "${RED}IMPORTANT: Recovery points in backup vaults must be manually deleted first!${NC}"
    echo
    
    read -p "Are you sure you want to proceed with cleanup? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Type 'DELETE' to confirm permanent resource removal: " -r
    if [[ $REPLY != "DELETE" ]]; then
        echo "Cleanup cancelled - confirmation not received"
        exit 0
    fi
}

# Load environment variables
load_environment() {
    log_info "Loading deployment configuration..."
    
    if [[ ! -f "${VARS_FILE}" ]]; then
        log_error "Configuration file not found: ${VARS_FILE}"
        log_error "Cannot proceed without deployment configuration"
        exit 1
    fi
    
    # Source the variables
    source "${VARS_FILE}"
    
    # Validate required variables
    required_vars=(
        "AWS_REGION" "AWS_ACCOUNT_ID" "DR_REGION"
        "BACKUP_PLAN_NAME" "BACKUP_VAULT_NAME" "DR_BACKUP_VAULT_NAME"
        "BACKUP_ROLE_NAME" "SNS_TOPIC_NAME" "RANDOM_SUFFIX"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable ${var} not found in configuration"
            exit 1
        fi
    done
    
    log_success "Configuration loaded successfully"
    log_info "Primary Region: ${AWS_REGION}"
    log_info "DR Region: ${DR_REGION}"
}

# Check AWS credentials
check_credentials() {
    log_info "Checking AWS credentials..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    log_success "AWS credentials validated"
}

# Delete backup selections and plans
delete_backup_plans() {
    log_info "Deleting backup selections and plans..."
    
    # Get backup plan ID if not set
    if [[ -z "${BACKUP_PLAN_ID:-}" ]]; then
        BACKUP_PLAN_ID=$(aws backup list-backup-plans \
            --query "BackupPlansList[?BackupPlanName=='${BACKUP_PLAN_NAME}'].BackupPlanId" \
            --output text 2>/dev/null || echo "")
    fi
    
    if [[ -n "${BACKUP_PLAN_ID}" && "${BACKUP_PLAN_ID}" != "None" ]]; then
        # Delete backup selections
        SELECTION_IDS=$(aws backup list-backup-selections \
            --backup-plan-id "${BACKUP_PLAN_ID}" \
            --query 'BackupSelectionsList[].SelectionId' \
            --output text 2>/dev/null || echo "")
        
        for SELECTION_ID in ${SELECTION_IDS}; do
            if [[ -n "${SELECTION_ID}" && "${SELECTION_ID}" != "None" ]]; then
                aws backup delete-backup-selection \
                    --backup-plan-id "${BACKUP_PLAN_ID}" \
                    --selection-id "${SELECTION_ID}" \
                    --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1 || log_warning "Failed to delete backup selection: ${SELECTION_ID}"
            fi
        done
        
        # Delete backup plan
        aws backup delete-backup-plan \
            --backup-plan-id "${BACKUP_PLAN_ID}" \
            --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1 || log_warning "Failed to delete backup plan: ${BACKUP_PLAN_ID}"
        
        log_success "Backup plans and selections deleted"
    else
        log_warning "No backup plan found to delete"
    fi
}

# Delete restore testing plans
delete_restore_testing() {
    log_info "Deleting restore testing plans..."
    
    RESTORE_PLAN_NAME="automated-restore-test-${RANDOM_SUFFIX}"
    
    aws backup delete-restore-testing-plan \
        --restore-testing-plan-name "${RESTORE_PLAN_NAME}" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1 || log_warning "Restore testing plan not found or already deleted"
    
    log_success "Restore testing plans cleaned up"
}

# Delete backup report plans
delete_backup_reports() {
    log_info "Deleting backup report plans..."
    
    REPORT_PLAN_NAME="backup-compliance-report-${RANDOM_SUFFIX}"
    
    aws backup delete-report-plan \
        --report-plan-name "${REPORT_PLAN_NAME}" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1 || log_warning "Backup report plan not found or already deleted"
    
    # Clean up S3 bucket if it exists and is empty
    if [[ -n "${REPORTS_BUCKET:-}" ]]; then
        # Try to remove objects first
        aws s3 rm "s3://${REPORTS_BUCKET}" --recursive >> "${LOG_FILE}" 2>&1 || log_warning "Failed to clear S3 bucket contents"
        
        # Try to delete bucket
        aws s3 rb "s3://${REPORTS_BUCKET}" \
            --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1 || log_warning "Failed to delete S3 bucket: ${REPORTS_BUCKET}"
    fi
    
    log_success "Backup reporting resources cleaned up"
}

# List and warn about recovery points
check_recovery_points() {
    log_info "Checking for recovery points in backup vaults..."
    
    # Check primary vault
    PRIMARY_RECOVERY_POINTS=$(aws backup list-recovery-points-by-backup-vault \
        --backup-vault-name "${BACKUP_VAULT_NAME}" \
        --query 'RecoveryPoints[].RecoveryPointArn' \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null || echo "")
    
    # Check DR vault
    DR_RECOVERY_POINTS=$(aws backup list-recovery-points-by-backup-vault \
        --backup-vault-name "${DR_BACKUP_VAULT_NAME}" \
        --query 'RecoveryPoints[].RecoveryPointArn' \
        --output text \
        --region "${DR_REGION}" 2>/dev/null || echo "")
    
    if [[ -n "${PRIMARY_RECOVERY_POINTS}" && "${PRIMARY_RECOVERY_POINTS}" != "None" ]]; then
        log_warning "Recovery points found in primary vault: ${BACKUP_VAULT_NAME}"
        log_warning "These must be manually deleted before vault deletion"
    fi
    
    if [[ -n "${DR_RECOVERY_POINTS}" && "${DR_RECOVERY_POINTS}" != "None" ]]; then
        log_warning "Recovery points found in DR vault: ${DR_BACKUP_VAULT_NAME}"
        log_warning "These must be manually deleted before vault deletion"
    fi
}

# Delete backup vaults
delete_backup_vaults() {
    log_info "Attempting to delete backup vaults..."
    
    check_recovery_points
    
    # Attempt to delete primary vault
    aws backup delete-backup-vault \
        --backup-vault-name "${BACKUP_VAULT_NAME}" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1 || log_warning "Primary backup vault contains recovery points or policies - manual cleanup required"
    
    # Attempt to delete DR vault
    aws backup delete-backup-vault \
        --backup-vault-name "${DR_BACKUP_VAULT_NAME}" \
        --region "${DR_REGION}" >> "${LOG_FILE}" 2>&1 || log_warning "DR backup vault contains recovery points or policies - manual cleanup required"
    
    log_success "Backup vault deletion attempted"
}

# Delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log_info "Deleting CloudWatch alarms..."
    
    aws cloudwatch delete-alarms \
        --alarm-names "AWS-Backup-Job-Failures-${RANDOM_SUFFIX}" "AWS-Backup-Storage-Usage-${RANDOM_SUFFIX}" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1 || log_warning "Some CloudWatch alarms not found"
    
    log_success "CloudWatch alarms deleted"
}

# Delete SNS topic
delete_sns_topic() {
    log_info "Deleting SNS topic..."
    
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        aws sns delete-topic \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1 || log_warning "SNS topic not found or already deleted"
    else
        # Try to find and delete by name
        SNS_TOPIC_ARN_FOUND=$(aws sns list-topics \
            --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${SNS_TOPIC_ARN_FOUND}" && "${SNS_TOPIC_ARN_FOUND}" != "None" ]]; then
            aws sns delete-topic \
                --topic-arn "${SNS_TOPIC_ARN_FOUND}" \
                --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1
        fi
    fi
    
    log_success "SNS topic deleted"
}

# Delete Config rules
delete_config_rules() {
    log_info "Deleting Config rules..."
    
    aws configservice delete-config-rule \
        --config-rule-name "backup-plan-min-frequency-and-min-retention-check" \
        --region "${AWS_REGION}" >> "${LOG_FILE}" 2>&1 || log_warning "Config rule not found or Config service not enabled"
    
    log_success "Config rules cleaned up"
}

# Delete IAM roles and policies
delete_iam_resources() {
    log_info "Deleting IAM roles and policies..."
    
    # Detach policies from role
    aws iam detach-role-policy \
        --role-name "${BACKUP_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup >> "${LOG_FILE}" 2>&1 || log_warning "Policy not attached or role not found"
    
    aws iam detach-role-policy \
        --role-name "${BACKUP_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores >> "${LOG_FILE}" 2>&1 || log_warning "Policy not attached or role not found"
    
    # Delete IAM role
    aws iam delete-role \
        --role-name "${BACKUP_ROLE_NAME}" >> "${LOG_FILE}" 2>&1 || log_warning "IAM role not found or has attached policies"
    
    log_success "IAM resources deleted"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    # List of files to clean up
    files_to_remove=(
        "${SCRIPT_DIR}/backup-trust-policy.json"
        "${SCRIPT_DIR}/backup-plan.json"
        "${SCRIPT_DIR}/backup-selection.json"
        "${SCRIPT_DIR}/backup-compliance-rule.json"
        "${SCRIPT_DIR}/restore-testing-plan.json"
        "${SCRIPT_DIR}/backup-report-plan.json"
        "${SCRIPT_DIR}/vault-access-policy.json"
        "${VARS_FILE}"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}" && log_info "Removed: $(basename "${file}")"
        fi
    done
    
    log_success "Local configuration files cleaned up"
}

# Validate cleanup
validate_cleanup() {
    log_info "Validating cleanup completion..."
    
    # Check for remaining backup plans
    REMAINING_PLANS=$(aws backup list-backup-plans \
        --query "BackupPlansList[?contains(BackupPlanName, '${RANDOM_SUFFIX}')].BackupPlanName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${REMAINING_PLANS}" && "${REMAINING_PLANS}" != "None" ]]; then
        log_warning "Some backup plans may still exist: ${REMAINING_PLANS}"
    fi
    
    # Check for remaining vaults
    REMAINING_VAULTS=$(aws backup list-backup-vaults \
        --query "BackupVaultList[?contains(BackupVaultName, '${RANDOM_SUFFIX}')].BackupVaultName" \
        --output text --region "${AWS_REGION}" 2>/dev/null || echo "")
    
    if [[ -n "${REMAINING_VAULTS}" && "${REMAINING_VAULTS}" != "None" ]]; then
        log_warning "Some backup vaults may still exist: ${REMAINING_VAULTS}"
    fi
    
    log_success "Cleanup validation completed"
}

# Display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary"
    echo
    echo "=================================================="
    echo "AWS Backup Solution Cleanup Summary"
    echo "=================================================="
    echo "The following resources have been cleaned up:"
    echo "✅ Backup plans and selections"
    echo "✅ Restore testing plans"
    echo "✅ Backup report plans"
    echo "✅ CloudWatch alarms"
    echo "✅ SNS topics"
    echo "✅ Config rules"
    echo "✅ IAM roles and policies"
    echo "✅ Local configuration files"
    echo
    echo "⚠️  Manual cleanup may be required for:"
    echo "   - Recovery points in backup vaults"
    echo "   - Backup vaults (if recovery points exist)"
    echo "   - S3 buckets (if not empty)"
    echo
    echo "Cleanup logs available at: ${LOG_FILE}"
    echo "=================================================="
}

# Main cleanup function
main() {
    echo "Starting AWS Backup Solution Cleanup..."
    echo "Logs will be written to: ${LOG_FILE}"
    echo
    
    check_credentials
    load_environment
    confirm_deletion
    
    delete_backup_plans
    delete_restore_testing
    delete_backup_reports
    delete_backup_vaults
    delete_cloudwatch_alarms
    delete_sns_topic
    delete_config_rules
    delete_iam_resources
    cleanup_local_files
    validate_cleanup
    display_cleanup_summary
    
    log_success "AWS Backup solution cleanup completed!"
}

# Handle script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        log_error "Cleanup script interrupted or failed. Check logs: ${LOG_FILE} and ${ERROR_LOG}"
        log_info "Some resources may require manual cleanup"
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"