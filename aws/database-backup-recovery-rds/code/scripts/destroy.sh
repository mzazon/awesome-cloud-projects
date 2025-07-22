#!/bin/bash

# AWS Database Backup and Point-in-Time Recovery Strategies - Cleanup Script
# This script safely removes all infrastructure created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
DRY_RUN=${DRY_RUN:-false}
FORCE_DELETE=${FORCE_DELETE:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")  echo -e "${GREEN}[INFO]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - $message" | tee -a "$LOG_FILE" ;;
        *)       echo -e "${timestamp} - $message" | tee -a "$LOG_FILE" ;;
    esac
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Cleanup failed. Check $LOG_FILE for details."
    exit 1
}

# Cleanup function for temporary files
cleanup_temp_files() {
    log "INFO" "Cleaning up temporary files..."
    rm -f backup-plan.json backup-selection.json vault-access-policy.json backup-trust-policy.json
    log "INFO" "Temporary files cleanup completed"
}

# Set trap to cleanup temp files on exit
trap cleanup_temp_files EXIT

# Prerequisites check
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    # Check if jq is available (optional but helpful)
    if command -v jq &> /dev/null; then
        log "INFO" "jq is available for JSON parsing"
    else
        log "WARN" "jq not found. Some output formatting may be limited."
    fi
    
    log "INFO" "Prerequisites check completed successfully"
}

# Discover resources
discover_resources() {
    log "INFO" "Discovering deployed resources..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log "WARN" "No region configured, using default: $AWS_REGION"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export DR_REGION="us-west-2"
    
    log "INFO" "AWS Account ID: $AWS_ACCOUNT_ID"
    log "INFO" "Primary Region: $AWS_REGION"
    log "INFO" "DR Region: $DR_REGION"
    
    # Discover RDS instances with our naming pattern
    local rds_instances
    rds_instances=$(aws rds describe-db-instances \
        --query 'DBInstances[?starts_with(DBInstanceIdentifier, `production-db-`)].DBInstanceIdentifier' \
        --output text)
    
    # Discover backup vaults
    local backup_vaults
    backup_vaults=$(aws backup list-backup-vaults \
        --query 'BackupVaultList[?starts_with(BackupVaultName, `rds-backup-vault-`)].BackupVaultName' \
        --output text)
    
    # Discover backup plans
    local backup_plans
    backup_plans=$(aws backup list-backup-plans \
        --query 'BackupPlansList[?starts_with(BackupPlanName, `rds-backup-plan-`)].BackupPlanId' \
        --output text)
    
    # Discover IAM roles
    local iam_roles
    iam_roles=$(aws iam list-roles \
        --query 'Roles[?starts_with(RoleName, `rds-backup-role-`)].RoleName' \
        --output text)
    
    # Discover KMS keys (this requires checking aliases)
    local kms_aliases
    kms_aliases=$(aws kms list-aliases \
        --query 'Aliases[?starts_with(AliasName, `alias/rds-backup-key-`)].AliasName' \
        --output text)
    
    # Discover SNS topics
    local sns_topics
    sns_topics=$(aws sns list-topics \
        --query 'Topics[?contains(TopicArn, `rds-backup-notifications-`)].TopicArn' \
        --output text)
    
    # Discover CloudWatch alarms
    local cw_alarms
    cw_alarms=$(aws cloudwatch describe-alarms \
        --query 'MetricAlarms[?starts_with(AlarmName, `RDS-Backup-Failures-`)].AlarmName' \
        --output text)
    
    # Store discovered resources
    export DISCOVERED_RDS_INSTANCES=($rds_instances)
    export DISCOVERED_BACKUP_VAULTS=($backup_vaults)
    export DISCOVERED_BACKUP_PLANS=($backup_plans)
    export DISCOVERED_IAM_ROLES=($iam_roles)
    export DISCOVERED_KMS_ALIASES=($kms_aliases)
    export DISCOVERED_SNS_TOPICS=($sns_topics)
    export DISCOVERED_CW_ALARMS=($cw_alarms)
    
    log "INFO" "Resource discovery completed"
    log "INFO" "Found ${#DISCOVERED_RDS_INSTANCES[@]} RDS instances"
    log "INFO" "Found ${#DISCOVERED_BACKUP_VAULTS[@]} backup vaults"
    log "INFO" "Found ${#DISCOVERED_BACKUP_PLANS[@]} backup plans"
    log "INFO" "Found ${#DISCOVERED_IAM_ROLES[@]} IAM roles"
    log "INFO" "Found ${#DISCOVERED_KMS_ALIASES[@]} KMS aliases"
    log "INFO" "Found ${#DISCOVERED_SNS_TOPICS[@]} SNS topics"
    log "INFO" "Found ${#DISCOVERED_CW_ALARMS[@]} CloudWatch alarms"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        log "INFO" "Skipping confirmation as requested"
        return 0
    fi
    
    log "WARN" "This will delete the following resources:"
    
    # Display resources to be deleted
    if [[ ${#DISCOVERED_RDS_INSTANCES[@]} -gt 0 ]]; then
        log "WARN" "RDS Instances: ${DISCOVERED_RDS_INSTANCES[*]}"
    fi
    
    if [[ ${#DISCOVERED_BACKUP_VAULTS[@]} -gt 0 ]]; then
        log "WARN" "Backup Vaults: ${DISCOVERED_BACKUP_VAULTS[*]}"
    fi
    
    if [[ ${#DISCOVERED_BACKUP_PLANS[@]} -gt 0 ]]; then
        log "WARN" "Backup Plans: ${DISCOVERED_BACKUP_PLANS[*]}"
    fi
    
    if [[ ${#DISCOVERED_IAM_ROLES[@]} -gt 0 ]]; then
        log "WARN" "IAM Roles: ${DISCOVERED_IAM_ROLES[*]}"
    fi
    
    if [[ ${#DISCOVERED_KMS_ALIASES[@]} -gt 0 ]]; then
        log "WARN" "KMS Aliases: ${DISCOVERED_KMS_ALIASES[*]}"
    fi
    
    if [[ ${#DISCOVERED_SNS_TOPICS[@]} -gt 0 ]]; then
        log "WARN" "SNS Topics: ${DISCOVERED_SNS_TOPICS[*]}"
    fi
    
    if [[ ${#DISCOVERED_CW_ALARMS[@]} -gt 0 ]]; then
        log "WARN" "CloudWatch Alarms: ${DISCOVERED_CW_ALARMS[*]}"
    fi
    
    echo
    read -p "Are you sure you want to delete these resources? [y/N]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Deletion cancelled by user"
        exit 0
    fi
    
    log "INFO" "Proceeding with resource deletion..."
}

# Stop cross-region replication
stop_cross_region_replication() {
    log "INFO" "Stopping cross-region backup replication..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would stop cross-region automated backup replication"
        return 0
    fi
    
    for db_instance in "${DISCOVERED_RDS_INSTANCES[@]}"; do
        if [[ -n "$db_instance" ]]; then
            log "INFO" "Stopping replication for: $db_instance"
            
            # Stop automated backup replication
            aws rds stop-db-instance-automated-backups-replication \
                --region "$DR_REGION" \
                --source-db-instance-arn "arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNT_ID}:db:${db_instance}" \
                2>/dev/null || log "WARN" "Failed to stop replication for $db_instance (may not exist)"
        fi
    done
    
    log "INFO" "Cross-region replication stopped"
}

# Delete backup selections and plans
delete_backup_selections_and_plans() {
    log "INFO" "Deleting backup selections and plans..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete backup selections and plans"
        return 0
    fi
    
    for backup_plan_id in "${DISCOVERED_BACKUP_PLANS[@]}"; do
        if [[ -n "$backup_plan_id" ]]; then
            log "INFO" "Processing backup plan: $backup_plan_id"
            
            # Get backup selections for this plan
            local selections
            selections=$(aws backup list-backup-selections \
                --backup-plan-id "$backup_plan_id" \
                --query 'BackupSelectionsList[*].SelectionId' \
                --output text 2>/dev/null || echo "")
            
            # Delete backup selections
            for selection_id in $selections; do
                if [[ -n "$selection_id" ]]; then
                    log "INFO" "Deleting backup selection: $selection_id"
                    aws backup delete-backup-selection \
                        --backup-plan-id "$backup_plan_id" \
                        --selection-id "$selection_id" \
                        2>/dev/null || log "WARN" "Failed to delete backup selection $selection_id"
                fi
            done
            
            # Delete backup plan
            log "INFO" "Deleting backup plan: $backup_plan_id"
            aws backup delete-backup-plan \
                --backup-plan-id "$backup_plan_id" \
                2>/dev/null || log "WARN" "Failed to delete backup plan $backup_plan_id"
        fi
    done
    
    log "INFO" "Backup selections and plans deleted"
}

# Delete recovery points and backup vaults
delete_backup_vaults() {
    log "INFO" "Deleting backup vaults and recovery points..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete recovery points and backup vaults"
        return 0
    fi
    
    for vault_name in "${DISCOVERED_BACKUP_VAULTS[@]}"; do
        if [[ -n "$vault_name" ]]; then
            log "INFO" "Processing backup vault: $vault_name"
            
            # Delete recovery points from primary vault
            local recovery_points
            recovery_points=$(aws backup list-recovery-points-by-backup-vault \
                --backup-vault-name "$vault_name" \
                --query 'RecoveryPoints[*].RecoveryPointArn' \
                --output text 2>/dev/null || echo "")
            
            for arn in $recovery_points; do
                if [[ -n "$arn" ]]; then
                    log "INFO" "Deleting recovery point: $arn"
                    aws backup delete-recovery-point \
                        --backup-vault-name "$vault_name" \
                        --recovery-point-arn "$arn" \
                        2>/dev/null || log "WARN" "Failed to delete recovery point $arn"
                fi
            done
            
            # Wait a bit for recovery points to be deleted
            sleep 5
            
            # Delete backup vault
            log "INFO" "Deleting backup vault: $vault_name"
            aws backup delete-backup-vault \
                --backup-vault-name "$vault_name" \
                2>/dev/null || log "WARN" "Failed to delete backup vault $vault_name"
            
            # Delete DR backup vault
            log "INFO" "Deleting DR backup vault: ${vault_name}-dr"
            aws backup delete-backup-vault \
                --region "$DR_REGION" \
                --backup-vault-name "${vault_name}-dr" \
                2>/dev/null || log "WARN" "Failed to delete DR backup vault ${vault_name}-dr"
        fi
    done
    
    log "INFO" "Backup vaults deletion completed"
}

# Delete RDS instances and snapshots
delete_rds_resources() {
    log "INFO" "Deleting RDS instances and snapshots..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete RDS instances and snapshots"
        return 0
    fi
    
    for db_instance in "${DISCOVERED_RDS_INSTANCES[@]}"; do
        if [[ -n "$db_instance" ]]; then
            log "INFO" "Processing RDS instance: $db_instance"
            
            # Delete manual snapshots
            local snapshots
            snapshots=$(aws rds describe-db-snapshots \
                --db-instance-identifier "$db_instance" \
                --snapshot-type manual \
                --query 'DBSnapshots[*].DBSnapshotIdentifier' \
                --output text 2>/dev/null || echo "")
            
            for snapshot in $snapshots; do
                if [[ -n "$snapshot" ]]; then
                    log "INFO" "Deleting snapshot: $snapshot"
                    aws rds delete-db-snapshot \
                        --db-snapshot-identifier "$snapshot" \
                        2>/dev/null || log "WARN" "Failed to delete snapshot $snapshot"
                fi
            done
            
            # Delete RDS instance
            log "INFO" "Deleting RDS instance: $db_instance"
            aws rds delete-db-instance \
                --db-instance-identifier "$db_instance" \
                --skip-final-snapshot \
                --delete-automated-backups \
                2>/dev/null || log "WARN" "Failed to delete RDS instance $db_instance"
            
            # Wait for instance to be deleted
            log "INFO" "Waiting for RDS instance to be deleted..."
            aws rds wait db-instance-deleted \
                --db-instance-identifier "$db_instance" \
                2>/dev/null || log "WARN" "Timeout waiting for RDS instance deletion"
        fi
    done
    
    log "INFO" "RDS resources deletion completed"
}

# Delete IAM roles
delete_iam_roles() {
    log "INFO" "Deleting IAM roles..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete IAM roles and policies"
        return 0
    fi
    
    for role_name in "${DISCOVERED_IAM_ROLES[@]}"; do
        if [[ -n "$role_name" ]]; then
            log "INFO" "Processing IAM role: $role_name"
            
            # Detach policies from role
            local policies
            policies=$(aws iam list-attached-role-policies \
                --role-name "$role_name" \
                --query 'AttachedPolicies[*].PolicyArn' \
                --output text 2>/dev/null || echo "")
            
            for policy_arn in $policies; do
                if [[ -n "$policy_arn" ]]; then
                    log "INFO" "Detaching policy: $policy_arn"
                    aws iam detach-role-policy \
                        --role-name "$role_name" \
                        --policy-arn "$policy_arn" \
                        2>/dev/null || log "WARN" "Failed to detach policy $policy_arn"
                fi
            done
            
            # Delete IAM role
            log "INFO" "Deleting IAM role: $role_name"
            aws iam delete-role \
                --role-name "$role_name" \
                2>/dev/null || log "WARN" "Failed to delete IAM role $role_name"
        fi
    done
    
    log "INFO" "IAM roles deletion completed"
}

# Delete KMS keys
delete_kms_keys() {
    log "INFO" "Scheduling KMS keys for deletion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would schedule KMS keys for deletion"
        return 0
    fi
    
    for alias_name in "${DISCOVERED_KMS_ALIASES[@]}"; do
        if [[ -n "$alias_name" ]]; then
            log "INFO" "Processing KMS alias: $alias_name"
            
            # Get key ID from alias
            local key_id
            key_id=$(aws kms describe-key \
                --key-id "$alias_name" \
                --query 'KeyMetadata.KeyId' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$key_id" ]]; then
                # Delete alias first
                log "INFO" "Deleting KMS alias: $alias_name"
                aws kms delete-alias \
                    --alias-name "$alias_name" \
                    2>/dev/null || log "WARN" "Failed to delete KMS alias $alias_name"
                
                # Schedule key deletion
                log "INFO" "Scheduling KMS key deletion: $key_id"
                aws kms schedule-key-deletion \
                    --key-id "$key_id" \
                    --pending-window-in-days 7 \
                    2>/dev/null || log "WARN" "Failed to schedule KMS key deletion $key_id"
                
                # Schedule DR key deletion (derive DR key from primary)
                local dr_alias="${alias_name}-dr"
                local dr_key_id
                dr_key_id=$(aws kms describe-key \
                    --region "$DR_REGION" \
                    --key-id "$dr_alias" \
                    --query 'KeyMetadata.KeyId' \
                    --output text 2>/dev/null || echo "")
                
                if [[ -n "$dr_key_id" ]]; then
                    log "INFO" "Scheduling DR KMS key deletion: $dr_key_id"
                    aws kms schedule-key-deletion \
                        --region "$DR_REGION" \
                        --key-id "$dr_key_id" \
                        --pending-window-in-days 7 \
                        2>/dev/null || log "WARN" "Failed to schedule DR KMS key deletion $dr_key_id"
                fi
            fi
        fi
    done
    
    log "INFO" "KMS keys scheduling completed"
}

# Delete monitoring resources
delete_monitoring_resources() {
    log "INFO" "Deleting monitoring resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete CloudWatch alarms and SNS topics"
        return 0
    fi
    
    # Delete CloudWatch alarms
    for alarm_name in "${DISCOVERED_CW_ALARMS[@]}"; do
        if [[ -n "$alarm_name" ]]; then
            log "INFO" "Deleting CloudWatch alarm: $alarm_name"
            aws cloudwatch delete-alarms \
                --alarm-names "$alarm_name" \
                2>/dev/null || log "WARN" "Failed to delete CloudWatch alarm $alarm_name"
        fi
    done
    
    # Delete SNS topics
    for topic_arn in "${DISCOVERED_SNS_TOPICS[@]}"; do
        if [[ -n "$topic_arn" ]]; then
            log "INFO" "Deleting SNS topic: $topic_arn"
            aws sns delete-topic \
                --topic-arn "$topic_arn" \
                2>/dev/null || log "WARN" "Failed to delete SNS topic $topic_arn"
        fi
    done
    
    log "INFO" "Monitoring resources deletion completed"
}

# Delete test resources
delete_test_resources() {
    log "INFO" "Deleting test resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete test restore instances"
        return 0
    fi
    
    # Find and delete test restore instances
    local test_instances
    test_instances=$(aws rds describe-db-instances \
        --query 'DBInstances[?contains(DBInstanceIdentifier, `-pitr-test`)].DBInstanceIdentifier' \
        --output text 2>/dev/null || echo "")
    
    for instance in $test_instances; do
        if [[ -n "$instance" ]]; then
            log "INFO" "Deleting test instance: $instance"
            aws rds delete-db-instance \
                --db-instance-identifier "$instance" \
                --skip-final-snapshot \
                --delete-automated-backups \
                2>/dev/null || log "WARN" "Failed to delete test instance $instance"
        fi
    done
    
    log "INFO" "Test resources deletion completed"
}

# Validation function
validate_cleanup() {
    log "INFO" "Validating cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would validate resource cleanup"
        return 0
    fi
    
    local cleanup_errors=0
    
    # Check if RDS instances are gone
    for db_instance in "${DISCOVERED_RDS_INSTANCES[@]}"; do
        if [[ -n "$db_instance" ]]; then
            local status
            status=$(aws rds describe-db-instances \
                --db-instance-identifier "$db_instance" \
                --query 'DBInstances[0].DBInstanceStatus' \
                --output text 2>/dev/null || echo "NOT_FOUND")
            
            if [[ "$status" != "NOT_FOUND" ]]; then
                log "WARN" "RDS instance still exists: $db_instance (status: $status)"
                ((cleanup_errors++))
            fi
        fi
    done
    
    # Check if backup vaults are gone
    for vault_name in "${DISCOVERED_BACKUP_VAULTS[@]}"; do
        if [[ -n "$vault_name" ]]; then
            local vault_status
            vault_status=$(aws backup describe-backup-vault \
                --backup-vault-name "$vault_name" \
                --query 'BackupVaultName' \
                --output text 2>/dev/null || echo "NOT_FOUND")
            
            if [[ "$vault_status" != "NOT_FOUND" ]]; then
                log "WARN" "Backup vault still exists: $vault_name"
                ((cleanup_errors++))
            fi
        fi
    done
    
    # Check if IAM roles are gone
    for role_name in "${DISCOVERED_IAM_ROLES[@]}"; do
        if [[ -n "$role_name" ]]; then
            local role_status
            role_status=$(aws iam get-role \
                --role-name "$role_name" \
                --query 'Role.RoleName' \
                --output text 2>/dev/null || echo "NOT_FOUND")
            
            if [[ "$role_status" != "NOT_FOUND" ]]; then
                log "WARN" "IAM role still exists: $role_name"
                ((cleanup_errors++))
            fi
        fi
    done
    
    if [[ $cleanup_errors -gt 0 ]]; then
        log "WARN" "Cleanup validation found $cleanup_errors issues"
        log "WARN" "Some resources may take time to be fully deleted"
    else
        log "INFO" "Cleanup validation completed successfully"
    fi
}

# Generate cleanup summary
generate_cleanup_summary() {
    log "INFO" "Generating cleanup summary..."
    
    cat << EOF | tee -a "$LOG_FILE"

===============================================
    CLEANUP SUMMARY
===============================================
Date: $(date)
Region: $AWS_REGION
DR Region: $DR_REGION
Account: $AWS_ACCOUNT_ID

RESOURCES PROCESSED:
• RDS Instances: ${#DISCOVERED_RDS_INSTANCES[@]}
• Backup Vaults: ${#DISCOVERED_BACKUP_VAULTS[@]}
• Backup Plans: ${#DISCOVERED_BACKUP_PLANS[@]}
• IAM Roles: ${#DISCOVERED_IAM_ROLES[@]}
• KMS Aliases: ${#DISCOVERED_KMS_ALIASES[@]}
• SNS Topics: ${#DISCOVERED_SNS_TOPICS[@]}
• CloudWatch Alarms: ${#DISCOVERED_CW_ALARMS[@]}

IMPORTANT NOTES:
• KMS keys are scheduled for deletion in 7 days
• Some resources may take time to be fully deleted
• Cross-region backup replication has been stopped
• All manual snapshots have been deleted

NEXT STEPS:
1. Verify all resources are deleted in AWS console
2. Check billing for any remaining charges
3. Review CloudTrail logs for deletion events
4. Cancel any pending KMS key deletions if needed

For any issues, check the log file: $LOG_FILE
===============================================
EOF
}

# Main cleanup function
main() {
    log "INFO" "Starting AWS Database Backup and Recovery cleanup..."
    log "INFO" "Log file: $LOG_FILE"
    
    # Check if dry run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "Running in DRY RUN mode - no resources will be deleted"
    fi
    
    # Run cleanup steps
    check_prerequisites
    discover_resources
    confirm_deletion
    delete_test_resources
    stop_cross_region_replication
    delete_backup_selections_and_plans
    delete_backup_vaults
    delete_rds_resources
    delete_iam_roles
    delete_monitoring_resources
    delete_kms_keys
    validate_cleanup
    generate_cleanup_summary
    
    log "INFO" "Cleanup completed successfully!"
    log "INFO" "Check $LOG_FILE for detailed logs"
}

# Script usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run           Run in dry-run mode (no resources deleted)
    -f, --force             Force deletion without confirmation
    -y, --yes               Skip confirmation prompts
    -v, --verbose           Enable verbose logging

ENVIRONMENT VARIABLES:
    DRY_RUN=true           Enable dry-run mode
    FORCE_DELETE=true      Force deletion without confirmation
    SKIP_CONFIRMATION=true Skip confirmation prompts
    AWS_REGION             Override AWS region (default: from AWS config)

EXAMPLES:
    $0                     # Normal cleanup with confirmation
    $0 --dry-run           # Dry run mode
    $0 --force             # Force deletion without confirmation
    $0 --yes               # Skip confirmation prompts
    DRY_RUN=true $0        # Dry run via environment variable

SAFETY:
    This script will delete ALL resources created by the deployment script.
    Use with caution in production environments.
    Always run with --dry-run first to verify what will be deleted.

EOF
}

# Parse command line arguments
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
        -f|--force)
            FORCE_DELETE=true
            SKIP_CONFIRMATION=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Safety check for force delete
if [[ "$FORCE_DELETE" == "true" ]]; then
    log "WARN" "Force delete mode enabled - all resources will be deleted without confirmation"
fi

# Run main function
main "$@"