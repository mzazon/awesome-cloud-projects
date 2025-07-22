#!/bin/bash

# =============================================================================
# AWS Multi-Region Backup Strategy Cleanup Script
# =============================================================================
# This script safely removes all resources created by the multi-region backup
# strategy deployment, including backup plans, vaults, Lambda functions,
# EventBridge rules, SNS topics, and IAM roles.
#
# Author: Recipe Generator v1.3
# Last Updated: 2025-07-12
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy-$(date +%Y%m%d-%H%M%S).log"
TEMP_DIR=$(mktemp -d)
trap 'cleanup' EXIT

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

header() {
    echo -e "\n${PURPLE}=== $1 ===${NC}" | tee -a "$LOG_FILE"
}

cleanup() {
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log "Cleaned up temporary directory: $TEMP_DIR"
    fi
}

# =============================================================================
# Prerequisites and Configuration
# =============================================================================

check_prerequisites() {
    header "Checking Prerequisites"
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS account information
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "AWS User: $AWS_USER_ARN"
    
    success "Prerequisites validation completed"
}

setup_configuration() {
    header "Setting Up Configuration"
    
    # Default configuration values (should match deploy script)
    export PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
    export SECONDARY_REGION="${SECONDARY_REGION:-us-west-2}"
    export TERTIARY_REGION="${TERTIARY_REGION:-eu-west-1}"
    export ORGANIZATION_NAME="${ORGANIZATION_NAME:-YourOrg}"
    export BACKUP_PLAN_NAME="${BACKUP_PLAN_NAME:-MultiRegionBackupPlan}"
    
    info "Configuration:"
    info "  Primary Region: $PRIMARY_REGION"
    info "  Secondary Region: $SECONDARY_REGION"
    info "  Tertiary Region: $TERTIARY_REGION"
    info "  Organization: $ORGANIZATION_NAME"
    
    success "Configuration setup completed"
}

# =============================================================================
# Discovery Functions
# =============================================================================

discover_backup_resources() {
    header "Discovering Backup Resources"
    
    info "Discovering backup plans..."
    
    # Find backup plans by name
    BACKUP_PLAN_IDS=$(aws backup list-backup-plans \
        --region "$PRIMARY_REGION" \
        --query "BackupPlansList[?BackupPlanName=='$BACKUP_PLAN_NAME'].BackupPlanId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$BACKUP_PLAN_IDS" ]]; then
        info "Found backup plan(s): $BACKUP_PLAN_IDS"
        export BACKUP_PLAN_ID=$(echo "$BACKUP_PLAN_IDS" | head -n1)
    else
        warning "No backup plans found with name: $BACKUP_PLAN_NAME"
        export BACKUP_PLAN_ID=""
    fi
    
    info "Discovering backup vaults..."
    
    # Find backup vaults by organization prefix
    VAULT_NAMES_PRIMARY=$(aws backup list-backup-vaults \
        --region "$PRIMARY_REGION" \
        --query "BackupVaultList[?starts_with(BackupVaultName, '${ORGANIZATION_NAME}-')].BackupVaultName" \
        --output text 2>/dev/null || echo "")
    
    VAULT_NAMES_SECONDARY=$(aws backup list-backup-vaults \
        --region "$SECONDARY_REGION" \
        --query "BackupVaultList[?starts_with(BackupVaultName, '${ORGANIZATION_NAME}-')].BackupVaultName" \
        --output text 2>/dev/null || echo "")
    
    VAULT_NAMES_TERTIARY=$(aws backup list-backup-vaults \
        --region "$TERTIARY_REGION" \
        --query "BackupVaultList[?starts_with(BackupVaultName, '${ORGANIZATION_NAME}-')].BackupVaultName" \
        --output text 2>/dev/null || echo "")
    
    info "Found vaults in primary region: ${VAULT_NAMES_PRIMARY:-none}"
    info "Found vaults in secondary region: ${VAULT_NAMES_SECONDARY:-none}"
    info "Found vaults in tertiary region: ${VAULT_NAMES_TERTIARY:-none}"
    
    # Find SNS topics related to backup notifications
    SNS_TOPIC_ARNS=$(aws sns list-topics \
        --region "$PRIMARY_REGION" \
        --query "Topics[?contains(TopicArn, 'backup-notifications')].TopicArn" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$SNS_TOPIC_ARNS" ]]; then
        info "Found SNS topic(s): $SNS_TOPIC_ARNS"
        export SNS_TOPIC_ARN=$(echo "$SNS_TOPIC_ARNS" | head -n1)
    else
        warning "No backup notification SNS topics found"
        export SNS_TOPIC_ARN=""
    fi
    
    success "Resource discovery completed"
}

# =============================================================================
# Backup Resources Cleanup
# =============================================================================

remove_backup_selections() {
    header "Removing Backup Selections"
    
    if [[ -z "$BACKUP_PLAN_ID" ]]; then
        warning "No backup plan ID available, skipping backup selection removal"
        return 0
    fi
    
    info "Listing backup selections for plan: $BACKUP_PLAN_ID"
    
    # Get backup selections
    BACKUP_SELECTIONS=$(aws backup list-backup-selections \
        --backup-plan-id "$BACKUP_PLAN_ID" \
        --region "$PRIMARY_REGION" \
        --query "BackupSelectionsList[].[SelectionId,SelectionName]" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$BACKUP_SELECTIONS" ]]; then
        while IFS=$'\t' read -r selection_id selection_name; do
            if [[ -n "$selection_id" ]]; then
                info "Removing backup selection: $selection_name ($selection_id)"
                
                aws backup delete-backup-selection \
                    --backup-plan-id "$BACKUP_PLAN_ID" \
                    --selection-id "$selection_id" \
                    --region "$PRIMARY_REGION"
                
                success "Backup selection removed: $selection_name"
                
                # Wait for deletion to complete
                sleep 5
            fi
        done <<< "$BACKUP_SELECTIONS"
    else
        info "No backup selections found to remove"
    fi
    
    success "Backup selections removal completed"
}

remove_backup_plans() {
    header "Removing Backup Plans"
    
    if [[ -z "$BACKUP_PLAN_ID" ]]; then
        warning "No backup plan ID available, skipping backup plan removal"
        return 0
    fi
    
    info "Removing backup plan: $BACKUP_PLAN_ID"
    
    # Check if backup plan still exists
    if aws backup get-backup-plan --backup-plan-id "$BACKUP_PLAN_ID" --region "$PRIMARY_REGION" &> /dev/null; then
        aws backup delete-backup-plan \
            --backup-plan-id "$BACKUP_PLAN_ID" \
            --region "$PRIMARY_REGION"
        
        success "Backup plan removed: $BACKUP_PLAN_ID"
    else
        warning "Backup plan not found or already removed: $BACKUP_PLAN_ID"
    fi
    
    success "Backup plans removal completed"
}

remove_recovery_points() {
    header "Removing Recovery Points"
    
    # Function to remove recovery points from a vault
    remove_vault_recovery_points() {
        local vault_name=$1
        local region=$2
        
        info "Checking recovery points in vault: $vault_name ($region)"
        
        # List recovery points in the vault
        local recovery_points=$(aws backup list-recovery-points-by-backup-vault \
            --backup-vault-name "$vault_name" \
            --region "$region" \
            --query "RecoveryPoints[].RecoveryPointArn" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$recovery_points" ]]; then
            warning "Found recovery points in $vault_name. These must be manually reviewed and deleted if needed."
            warning "Recovery points:"
            echo "$recovery_points" | tr '\t' '\n' | while read -r rp; do
                if [[ -n "$rp" ]]; then
                    warning "  - $rp"
                fi
            done
            warning "Use 'aws backup delete-recovery-point' to remove specific recovery points if needed"
        else
            info "No recovery points found in vault: $vault_name"
        fi
    }
    
    # Check recovery points in all discovered vaults
    if [[ -n "$VAULT_NAMES_PRIMARY" ]]; then
        for vault in $VAULT_NAMES_PRIMARY; do
            remove_vault_recovery_points "$vault" "$PRIMARY_REGION"
        done
    fi
    
    if [[ -n "$VAULT_NAMES_SECONDARY" ]]; then
        for vault in $VAULT_NAMES_SECONDARY; do
            remove_vault_recovery_points "$vault" "$SECONDARY_REGION"
        done
    fi
    
    if [[ -n "$VAULT_NAMES_TERTIARY" ]]; then
        for vault in $VAULT_NAMES_TERTIARY; do
            remove_vault_recovery_points "$vault" "$TERTIARY_REGION"
        done
    fi
    
    success "Recovery points check completed"
}

remove_backup_vaults() {
    header "Removing Backup Vaults"
    
    # Function to remove vaults from a region
    remove_vaults_from_region() {
        local vault_names=$1
        local region=$2
        
        if [[ -z "$vault_names" ]]; then
            info "No vaults to remove in region: $region"
            return 0
        fi
        
        for vault_name in $vault_names; do
            info "Removing backup vault: $vault_name ($region)"
            
            # Check if vault exists and is empty
            if aws backup describe-backup-vault --backup-vault-name "$vault_name" --region "$region" &> /dev/null; then
                # Check for recovery points
                local rp_count=$(aws backup list-recovery-points-by-backup-vault \
                    --backup-vault-name "$vault_name" \
                    --region "$region" \
                    --query "length(RecoveryPoints)" \
                    --output text 2>/dev/null || echo "0")
                
                if [[ "$rp_count" -gt 0 ]]; then
                    warning "Vault $vault_name contains $rp_count recovery points. Cannot delete non-empty vault."
                    warning "Please remove all recovery points first, then run this script again."
                else
                    aws backup delete-backup-vault \
                        --backup-vault-name "$vault_name" \
                        --region "$region"
                    success "Backup vault removed: $vault_name"
                fi
            else
                warning "Backup vault not found or already removed: $vault_name"
            fi
        done
    }
    
    # Remove vaults from all regions
    remove_vaults_from_region "$VAULT_NAMES_PRIMARY" "$PRIMARY_REGION"
    remove_vaults_from_region "$VAULT_NAMES_SECONDARY" "$SECONDARY_REGION"
    remove_vaults_from_region "$VAULT_NAMES_TERTIARY" "$TERTIARY_REGION"
    
    success "Backup vaults removal completed"
}

# =============================================================================
# EventBridge and Lambda Cleanup
# =============================================================================

remove_eventbridge_rules() {
    header "Removing EventBridge Rules"
    
    info "Removing EventBridge rule: BackupJobFailureRule"
    
    # Check if rule exists
    if aws events describe-rule --name BackupJobFailureRule --region "$PRIMARY_REGION" &> /dev/null; then
        
        # Remove targets first
        info "Removing targets from EventBridge rule"
        local targets=$(aws events list-targets-by-rule \
            --rule BackupJobFailureRule \
            --region "$PRIMARY_REGION" \
            --query "Targets[].Id" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$targets" ]]; then
            aws events remove-targets \
                --rule BackupJobFailureRule \
                --ids $targets \
                --region "$PRIMARY_REGION"
            success "EventBridge rule targets removed"
        fi
        
        # Delete the rule
        aws events delete-rule \
            --name BackupJobFailureRule \
            --region "$PRIMARY_REGION"
        success "EventBridge rule removed: BackupJobFailureRule"
    else
        warning "EventBridge rule not found: BackupJobFailureRule"
    fi
    
    success "EventBridge rules removal completed"
}

remove_lambda_function() {
    header "Removing Lambda Function"
    
    info "Removing Lambda function: backup-validator"
    
    # Check if function exists
    if aws lambda get-function --function-name backup-validator --region "$PRIMARY_REGION" &> /dev/null; then
        aws lambda delete-function \
            --function-name backup-validator \
            --region "$PRIMARY_REGION"
        success "Lambda function removed: backup-validator"
    else
        warning "Lambda function not found: backup-validator"
    fi
    
    success "Lambda function removal completed"
}

# =============================================================================
# SNS Cleanup
# =============================================================================

remove_sns_topics() {
    header "Removing SNS Topics"
    
    if [[ -z "$SNS_TOPIC_ARN" ]]; then
        warning "No SNS topic ARN available, skipping SNS cleanup"
        return 0
    fi
    
    info "Removing SNS topic: $SNS_TOPIC_ARN"
    
    # Check if topic exists
    if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" --region "$PRIMARY_REGION" &> /dev/null; then
        aws sns delete-topic \
            --topic-arn "$SNS_TOPIC_ARN" \
            --region "$PRIMARY_REGION"
        success "SNS topic removed: $SNS_TOPIC_ARN"
    else
        warning "SNS topic not found: $SNS_TOPIC_ARN"
    fi
    
    success "SNS topics removal completed"
}

# =============================================================================
# IAM Cleanup
# =============================================================================

remove_iam_roles() {
    header "Removing IAM Roles"
    
    # Remove BackupValidatorRole
    info "Removing Lambda execution role: BackupValidatorRole"
    
    if aws iam get-role --role-name BackupValidatorRole &> /dev/null; then
        # Detach managed policies
        aws iam detach-role-policy \
            --role-name BackupValidatorRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
        
        # Remove inline policies
        aws iam delete-role-policy \
            --role-name BackupValidatorRole \
            --policy-name BackupValidatorPolicy 2>/dev/null || true
        
        # Delete the role
        aws iam delete-role --role-name BackupValidatorRole
        success "IAM role removed: BackupValidatorRole"
    else
        warning "IAM role not found: BackupValidatorRole"
    fi
    
    # Confirmation for AWS Backup service role removal
    echo ""
    warning "The AWSBackupServiceRole IAM role is still present."
    warning "This role may be used by other backup plans or AWS Backup operations."
    read -p "Do you want to remove AWSBackupServiceRole? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Removing AWS Backup service role: AWSBackupServiceRole"
        
        if aws iam get-role --role-name AWSBackupServiceRole &> /dev/null; then
            # Detach managed policies
            aws iam detach-role-policy \
                --role-name AWSBackupServiceRole \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup 2>/dev/null || true
            
            aws iam detach-role-policy \
                --role-name AWSBackupServiceRole \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores 2>/dev/null || true
            
            # Delete the role
            aws iam delete-role --role-name AWSBackupServiceRole
            success "IAM role removed: AWSBackupServiceRole"
        else
            warning "IAM role not found: AWSBackupServiceRole"
        fi
    else
        info "Keeping AWSBackupServiceRole for other backup operations"
    fi
    
    success "IAM roles removal completed"
}

# =============================================================================
# Cleanup Validation
# =============================================================================

validate_cleanup() {
    header "Validating Cleanup"
    
    local cleanup_issues=0
    
    # Check backup plans
    if [[ -n "$BACKUP_PLAN_ID" ]]; then
        if aws backup get-backup-plan --backup-plan-id "$BACKUP_PLAN_ID" --region "$PRIMARY_REGION" &> /dev/null; then
            warning "Backup plan still exists: $BACKUP_PLAN_ID"
            ((cleanup_issues++))
        else
            success "Backup plan successfully removed"
        fi
    fi
    
    # Check backup vaults
    local remaining_vaults=""
    for region in "$PRIMARY_REGION" "$SECONDARY_REGION" "$TERTIARY_REGION"; do
        local vaults=$(aws backup list-backup-vaults \
            --region "$region" \
            --query "BackupVaultList[?starts_with(BackupVaultName, '${ORGANIZATION_NAME}-')].BackupVaultName" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$vaults" ]]; then
            remaining_vaults="$remaining_vaults $vaults"
        fi
    done
    
    if [[ -n "$remaining_vaults" ]]; then
        warning "Some backup vaults still exist: $remaining_vaults"
        warning "These may contain recovery points that prevent deletion"
        ((cleanup_issues++))
    else
        success "All backup vaults successfully removed"
    fi
    
    # Check Lambda function
    if aws lambda get-function --function-name backup-validator --region "$PRIMARY_REGION" &> /dev/null; then
        warning "Lambda function still exists: backup-validator"
        ((cleanup_issues++))
    else
        success "Lambda function successfully removed"
    fi
    
    # Check EventBridge rule
    if aws events describe-rule --name BackupJobFailureRule --region "$PRIMARY_REGION" &> /dev/null; then
        warning "EventBridge rule still exists: BackupJobFailureRule"
        ((cleanup_issues++))
    else
        success "EventBridge rule successfully removed"
    fi
    
    # Check SNS topic
    if [[ -n "$SNS_TOPIC_ARN" ]] && aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" --region "$PRIMARY_REGION" &> /dev/null; then
        warning "SNS topic still exists: $SNS_TOPIC_ARN"
        ((cleanup_issues++))
    else
        success "SNS topic successfully removed"
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        success "All resources successfully cleaned up"
    else
        warning "$cleanup_issues issues found during cleanup validation"
        warning "Some resources may require manual intervention"
    fi
}

# =============================================================================
# Cleanup Summary
# =============================================================================

display_cleanup_summary() {
    header "Cleanup Summary"
    
    echo -e "\n${GREEN}🧹 Multi-Region Backup Strategy Cleanup Completed!${NC}\n"
    
    echo -e "${CYAN}Cleanup Actions Performed:${NC}"
    echo -e "  ✅ Backup selections removed"
    echo -e "  ✅ Backup plans removed"
    echo -e "  ⚠️  Recovery points checked (manual action may be required)"
    echo -e "  ✅ Backup vaults removed (if empty)"
    echo -e "  ✅ EventBridge rules removed"
    echo -e "  ✅ Lambda functions removed"
    echo -e "  ✅ SNS topics removed"
    echo -e "  ✅ IAM roles cleaned up"
    
    echo -e "\n${YELLOW}Important Notes:${NC}"
    echo -e "  • Backup vaults with recovery points cannot be deleted automatically"
    echo -e "  • Recovery points must be manually reviewed and deleted if needed"
    echo -e "  • Cross-region data transfer charges may apply for existing backups"
    echo -e "  • Some IAM roles may be preserved for other AWS Backup operations"
    
    echo -e "\n${CYAN}Manual Actions Required:${NC}"
    echo -e "  • Review and delete any remaining recovery points if no longer needed"
    echo -e "  • Monitor AWS costs for any remaining backup storage"
    echo -e "  • Remove resource tags if they're no longer needed"
    echo -e "  • Review CloudWatch logs and metrics for cleanup verification"
    
    echo -e "\n${CYAN}Final Verification:${NC}"
    echo -e "  📋 Cleanup log: ${LOG_FILE}"
    echo -e "  🔍 AWS Backup Console: Check for any remaining resources"
    echo -e "  💰 Cost Explorer: Monitor for any remaining charges"
    
    echo -e "\n${GREEN}Cleanup completed at $(date)${NC}\n"
}

# =============================================================================
# Main Execution Function
# =============================================================================

main() {
    echo -e "${RED}"
    echo "============================================================================="
    echo "               AWS Multi-Region Backup Strategy Cleanup"
    echo "============================================================================="
    echo -e "${NC}"
    echo "This script will remove all resources created by the multi-region backup"
    echo "strategy deployment. This includes backup plans, vaults, Lambda functions,"
    echo "EventBridge rules, SNS topics, and IAM roles."
    echo ""
    echo -e "${RED}⚠️  WARNING: This action is irreversible!${NC}"
    echo ""
    echo "Resources to be removed:"
    echo "  - Backup plans and selections"
    echo "  - Backup vaults (if empty)"
    echo "  - Lambda functions"
    echo "  - EventBridge rules"
    echo "  - SNS topics"
    echo "  - IAM roles (with confirmation)"
    echo ""
    echo -e "${YELLOW}Note: Backup vaults containing recovery points cannot be deleted${NC}"
    echo -e "${YELLOW}automatically and will require manual intervention.${NC}"
    echo ""
    
    # Confirmation prompt
    read -p "Are you sure you want to proceed with the cleanup? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cleanup cancelled by user."
        exit 0
    fi
    
    echo ""
    read -p "Type 'DELETE' to confirm resource removal: " -r
    echo ""
    if [[ "$REPLY" != "DELETE" ]]; then
        echo "Cleanup cancelled. Expected 'DELETE' but got '$REPLY'."
        exit 0
    fi
    
    # Start cleanup
    log "Starting multi-region backup strategy cleanup"
    
    # Execute cleanup steps
    check_prerequisites
    setup_configuration
    discover_backup_resources
    remove_backup_selections
    remove_backup_plans
    remove_recovery_points
    remove_backup_vaults
    remove_eventbridge_rules
    remove_lambda_function
    remove_sns_topics
    remove_iam_roles
    validate_cleanup
    display_cleanup_summary
    
    log "Multi-region backup strategy cleanup completed"
    
    return 0
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Handle script interruption
trap 'error "Cleanup script interrupted by user"; cleanup; exit 1' INT TERM

# Start main execution
main "$@"