#!/bin/bash

# =============================================================================
# DynamoDB Global Tables Destroy Script
# =============================================================================
# This script safely destroys all resources created by the deployment script
# following the recipe: Architecting NoSQL Databases with DynamoDB Global Tables
# =============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# =============================================================================
# Configuration Variables
# =============================================================================

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_SUMMARY="${SCRIPT_DIR}/deployment-summary.json"
LOG_FILE="${SCRIPT_DIR}/destruction.log"

# Default regions (can be overridden)
PRIMARY_REGION=${PRIMARY_REGION:-"us-east-1"}
SECONDARY_REGION=${SECONDARY_REGION:-"eu-west-1"}
TERTIARY_REGION=${TERTIARY_REGION:-"ap-southeast-1"}

# Initialize variables
TABLE_NAME=""
IAM_ROLE_NAME=""
LAMBDA_FUNCTION_NAME=""
BACKUP_VAULT_NAME=""
BACKUP_PLAN_ID=""
PRIMARY_KEY_ID=""
SECONDARY_KEY_ID=""
TERTIARY_KEY_ID=""
RANDOM_SUFFIX=""

# =============================================================================
# Helper Functions
# =============================================================================

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log "✅ Prerequisites check completed"
}

# Load deployment configuration
load_deployment_config() {
    log "Loading deployment configuration..."
    
    if [ -f "${DEPLOYMENT_SUMMARY}" ]; then
        if command -v jq &> /dev/null; then
            # Use jq if available
            TABLE_NAME=$(jq -r '.table_name' "${DEPLOYMENT_SUMMARY}")
            IAM_ROLE_NAME=$(jq -r '.resources.iam_role' "${DEPLOYMENT_SUMMARY}")
            LAMBDA_FUNCTION_NAME=$(jq -r '.resources.lambda_function' "${DEPLOYMENT_SUMMARY}")
            BACKUP_VAULT_NAME=$(jq -r '.resources.backup_vault' "${DEPLOYMENT_SUMMARY}")
            BACKUP_PLAN_ID=$(jq -r '.backup_plan_id' "${DEPLOYMENT_SUMMARY}")
            PRIMARY_KEY_ID=$(jq -r '.resources.kms_keys.primary' "${DEPLOYMENT_SUMMARY}")
            SECONDARY_KEY_ID=$(jq -r '.resources.kms_keys.secondary' "${DEPLOYMENT_SUMMARY}")
            TERTIARY_KEY_ID=$(jq -r '.resources.kms_keys.tertiary' "${DEPLOYMENT_SUMMARY}")
            RANDOM_SUFFIX=$(jq -r '.random_suffix' "${DEPLOYMENT_SUMMARY}")
            PRIMARY_REGION=$(jq -r '.regions.primary' "${DEPLOYMENT_SUMMARY}")
            SECONDARY_REGION=$(jq -r '.regions.secondary' "${DEPLOYMENT_SUMMARY}")
            TERTIARY_REGION=$(jq -r '.regions.tertiary' "${DEPLOYMENT_SUMMARY}")
        else
            # Parse manually if jq is not available
            TABLE_NAME=$(grep '"table_name"' "${DEPLOYMENT_SUMMARY}" | cut -d'"' -f4)
            IAM_ROLE_NAME=$(grep '"iam_role"' "${DEPLOYMENT_SUMMARY}" | cut -d'"' -f4)
            LAMBDA_FUNCTION_NAME=$(grep '"lambda_function"' "${DEPLOYMENT_SUMMARY}" | cut -d'"' -f4)
            BACKUP_VAULT_NAME=$(grep '"backup_vault"' "${DEPLOYMENT_SUMMARY}" | cut -d'"' -f4)
            BACKUP_PLAN_ID=$(grep '"backup_plan_id"' "${DEPLOYMENT_SUMMARY}" | cut -d'"' -f4)
            RANDOM_SUFFIX=$(grep '"random_suffix"' "${DEPLOYMENT_SUMMARY}" | cut -d'"' -f4)
            
            # Extract KMS key IDs
            PRIMARY_KEY_ID=$(grep -A2 '"kms_keys"' "${DEPLOYMENT_SUMMARY}" | grep '"primary"' | cut -d'"' -f4)
            SECONDARY_KEY_ID=$(grep -A3 '"kms_keys"' "${DEPLOYMENT_SUMMARY}" | grep '"secondary"' | cut -d'"' -f4)
            TERTIARY_KEY_ID=$(grep -A4 '"kms_keys"' "${DEPLOYMENT_SUMMARY}" | grep '"tertiary"' | cut -d'"' -f4)
            
            # Extract regions
            PRIMARY_REGION=$(grep -A2 '"regions"' "${DEPLOYMENT_SUMMARY}" | grep '"primary"' | cut -d'"' -f4)
            SECONDARY_REGION=$(grep -A3 '"regions"' "${DEPLOYMENT_SUMMARY}" | grep '"secondary"' | cut -d'"' -f4)
            TERTIARY_REGION=$(grep -A4 '"regions"' "${DEPLOYMENT_SUMMARY}" | grep '"tertiary"' | cut -d'"' -f4)
        fi
        
        log "✅ Loaded deployment configuration"
        info "Table Name: ${TABLE_NAME}"
        info "IAM Role: ${IAM_ROLE_NAME}"
        info "Lambda Function: ${LAMBDA_FUNCTION_NAME}"
        info "Backup Vault: ${BACKUP_VAULT_NAME}"
        info "Regions: ${PRIMARY_REGION}, ${SECONDARY_REGION}, ${TERTIARY_REGION}"
    else
        warn "Deployment summary not found. You'll need to provide resource names manually."
        prompt_for_manual_input
    fi
}

# Prompt for manual input if deployment summary is not found
prompt_for_manual_input() {
    echo ""
    warn "Deployment summary file not found at: ${DEPLOYMENT_SUMMARY}"
    warn "Please provide the resource names manually:"
    echo ""
    
    read -p "Enter DynamoDB table name: " TABLE_NAME
    read -p "Enter IAM role name: " IAM_ROLE_NAME
    read -p "Enter Lambda function name: " LAMBDA_FUNCTION_NAME
    read -p "Enter backup vault name: " BACKUP_VAULT_NAME
    read -p "Enter backup plan ID: " BACKUP_PLAN_ID
    read -p "Enter random suffix: " RANDOM_SUFFIX
    
    if [ -z "${TABLE_NAME}" ]; then
        error "Table name is required"
        exit 1
    fi
    
    # Set default names if not provided
    IAM_ROLE_NAME=${IAM_ROLE_NAME:-"DynamoDBGlobalTableRole-${RANDOM_SUFFIX}"}
    LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME:-"global-table-test-${RANDOM_SUFFIX}"}
    BACKUP_VAULT_NAME=${BACKUP_VAULT_NAME:-"DynamoDB-Global-Backup-${RANDOM_SUFFIX}"}
}

# Confirmation prompt
confirm_destruction() {
    echo ""
    warn "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo ""
    echo "This will permanently delete the following resources:"
    echo "  - DynamoDB Global Table: ${TABLE_NAME}"
    echo "  - IAM Role: ${IAM_ROLE_NAME}"
    echo "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
    echo "  - Backup Vault: ${BACKUP_VAULT_NAME}"
    echo "  - KMS Keys in all regions (scheduled for deletion)"
    echo "  - CloudWatch Alarms in all regions"
    echo ""
    warn "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    if [ "$confirmation" != "yes" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Proceeding with resource destruction..."
}

# Wait for resource to be deleted
wait_for_deletion() {
    local resource_type=$1
    local resource_name=$2
    local region=$3
    local max_attempts=${4:-30}
    local attempt=0
    
    log "Waiting for ${resource_type} ${resource_name} to be deleted..."
    
    while [ $attempt -lt $max_attempts ]; do
        case $resource_type in
            "table")
                if ! aws dynamodb describe-table --region "$region" --table-name "$resource_name" &>/dev/null; then
                    log "✅ Table ${resource_name} deleted successfully"
                    return 0
                fi
                ;;
            "global-table")
                if ! aws dynamodb describe-global-table --region "$region" --global-table-name "$resource_name" &>/dev/null; then
                    log "✅ Global Table ${resource_name} deleted successfully"
                    return 0
                fi
                ;;
        esac
        
        sleep 10
        ((attempt++))
        info "Attempt ${attempt}/${max_attempts}..."
    done
    
    warn "Timeout waiting for ${resource_type} ${resource_name} deletion"
    return 1
}

# =============================================================================
# Lambda Function Cleanup
# =============================================================================

destroy_lambda_function() {
    log "Destroying Lambda function..."
    
    if [ -n "${LAMBDA_FUNCTION_NAME}" ]; then
        # Delete Lambda function
        if aws lambda get-function --region "${PRIMARY_REGION}" --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
            aws lambda delete-function \
                --region "${PRIMARY_REGION}" \
                --function-name "${LAMBDA_FUNCTION_NAME}" \
                >> "${LOG_FILE}" 2>&1
            log "✅ Deleted Lambda function: ${LAMBDA_FUNCTION_NAME}"
        else
            info "Lambda function ${LAMBDA_FUNCTION_NAME} not found or already deleted"
        fi
    else
        warn "Lambda function name not provided, skipping..."
    fi
}

# =============================================================================
# CloudWatch Alarms Cleanup
# =============================================================================

destroy_cloudwatch_alarms() {
    log "Destroying CloudWatch alarms..."
    
    destroy_alarms_in_region() {
        local region=$1
        local alarm_names=(
            "${TABLE_NAME}-ReadThrottles-${region}"
            "${TABLE_NAME}-WriteThrottles-${region}"
            "${TABLE_NAME}-ReplicationLag-${region}"
        )
        
        for alarm_name in "${alarm_names[@]}"; do
            if aws cloudwatch describe-alarms --region "${region}" --alarm-names "${alarm_name}" --query 'MetricAlarms[0]' --output text 2>/dev/null | grep -q "${alarm_name}"; then
                aws cloudwatch delete-alarms \
                    --region "${region}" \
                    --alarm-names "${alarm_name}" \
                    >> "${LOG_FILE}" 2>&1
                log "✅ Deleted alarm: ${alarm_name}"
            else
                info "Alarm ${alarm_name} not found in ${region}"
            fi
        done
    }
    
    if [ -n "${TABLE_NAME}" ]; then
        destroy_alarms_in_region "${PRIMARY_REGION}"
        destroy_alarms_in_region "${SECONDARY_REGION}"
        destroy_alarms_in_region "${TERTIARY_REGION}"
    else
        warn "Table name not provided, skipping CloudWatch alarms cleanup"
    fi
}

# =============================================================================
# Backup Configuration Cleanup
# =============================================================================

destroy_backup_configuration() {
    log "Destroying backup configuration..."
    
    if [ -n "${BACKUP_PLAN_ID}" ] && [ -n "${BACKUP_VAULT_NAME}" ]; then
        # Delete backup selections
        local backup_selections=$(aws backup list-backup-selections \
            --region "${PRIMARY_REGION}" \
            --backup-plan-id "${BACKUP_PLAN_ID}" \
            --query 'BackupSelectionsList[].SelectionId' \
            --output text 2>/dev/null)
        
        if [ -n "${backup_selections}" ] && [ "${backup_selections}" != "None" ]; then
            for selection_id in $backup_selections; do
                aws backup delete-backup-selection \
                    --region "${PRIMARY_REGION}" \
                    --backup-plan-id "${BACKUP_PLAN_ID}" \
                    --selection-id "${selection_id}" \
                    >> "${LOG_FILE}" 2>&1
                log "✅ Deleted backup selection: ${selection_id}"
            done
        fi
        
        # Delete backup plan
        if aws backup get-backup-plan --region "${PRIMARY_REGION}" --backup-plan-id "${BACKUP_PLAN_ID}" &>/dev/null; then
            aws backup delete-backup-plan \
                --region "${PRIMARY_REGION}" \
                --backup-plan-id "${BACKUP_PLAN_ID}" \
                >> "${LOG_FILE}" 2>&1
            log "✅ Deleted backup plan: ${BACKUP_PLAN_ID}"
        fi
        
        # Delete backup vault
        if aws backup describe-backup-vault --region "${PRIMARY_REGION}" --backup-vault-name "${BACKUP_VAULT_NAME}" &>/dev/null; then
            aws backup delete-backup-vault \
                --region "${PRIMARY_REGION}" \
                --backup-vault-name "${BACKUP_VAULT_NAME}" \
                >> "${LOG_FILE}" 2>&1
            log "✅ Deleted backup vault: ${BACKUP_VAULT_NAME}"
        fi
    else
        warn "Backup configuration details not found, skipping backup cleanup"
    fi
}

# =============================================================================
# DynamoDB Global Tables Cleanup
# =============================================================================

destroy_global_tables() {
    log "Destroying DynamoDB Global Tables..."
    
    if [ -n "${TABLE_NAME}" ]; then
        # Check if global table exists
        if aws dynamodb describe-global-table --region "${PRIMARY_REGION}" --global-table-name "${TABLE_NAME}" &>/dev/null; then
            
            # Remove replicas in reverse order
            log "Removing tertiary region replica..."
            aws dynamodb update-global-table \
                --region "${PRIMARY_REGION}" \
                --global-table-name "${TABLE_NAME}" \
                --replica-updates Delete={RegionName="${TERTIARY_REGION}"} \
                >> "${LOG_FILE}" 2>&1 || warn "Failed to remove tertiary region replica"
            
            sleep 30
            
            log "Removing secondary region replica..."
            aws dynamodb update-global-table \
                --region "${PRIMARY_REGION}" \
                --global-table-name "${TABLE_NAME}" \
                --replica-updates Delete={RegionName="${SECONDARY_REGION}"} \
                >> "${LOG_FILE}" 2>&1 || warn "Failed to remove secondary region replica"
            
            sleep 30
            
            log "✅ Removed Global Table replicas"
        else
            info "Global table ${TABLE_NAME} not found"
        fi
        
        # Delete primary table
        if aws dynamodb describe-table --region "${PRIMARY_REGION}" --table-name "${TABLE_NAME}" &>/dev/null; then
            # Disable deletion protection first
            aws dynamodb update-table \
                --region "${PRIMARY_REGION}" \
                --table-name "${TABLE_NAME}" \
                --no-deletion-protection-enabled \
                >> "${LOG_FILE}" 2>&1
            
            sleep 10
            
            # Delete the table
            aws dynamodb delete-table \
                --region "${PRIMARY_REGION}" \
                --table-name "${TABLE_NAME}" \
                >> "${LOG_FILE}" 2>&1
            
            wait_for_deletion "table" "${TABLE_NAME}" "${PRIMARY_REGION}"
            log "✅ Deleted DynamoDB table: ${TABLE_NAME}"
        else
            info "Primary table ${TABLE_NAME} not found"
        fi
    else
        warn "Table name not provided, skipping DynamoDB cleanup"
    fi
}

# =============================================================================
# IAM Role Cleanup
# =============================================================================

destroy_iam_role() {
    log "Destroying IAM role..."
    
    if [ -n "${IAM_ROLE_NAME}" ]; then
        # Detach policies from role
        local attached_policies=$(aws iam list-attached-role-policies \
            --role-name "${IAM_ROLE_NAME}" \
            --query 'AttachedPolicies[].PolicyArn' \
            --output text 2>/dev/null)
        
        if [ -n "${attached_policies}" ]; then
            for policy_arn in $attached_policies; do
                aws iam detach-role-policy \
                    --role-name "${IAM_ROLE_NAME}" \
                    --policy-arn "${policy_arn}" \
                    >> "${LOG_FILE}" 2>&1
                log "✅ Detached policy: ${policy_arn}"
                
                # Delete custom policy if it's our created policy
                if echo "${policy_arn}" | grep -q "${IAM_ROLE_NAME}-Policy"; then
                    aws iam delete-policy \
                        --policy-arn "${policy_arn}" \
                        >> "${LOG_FILE}" 2>&1
                    log "✅ Deleted policy: ${policy_arn}"
                fi
            done
        fi
        
        # Delete IAM role
        if aws iam get-role --role-name "${IAM_ROLE_NAME}" &>/dev/null; then
            aws iam delete-role --role-name "${IAM_ROLE_NAME}" >> "${LOG_FILE}" 2>&1
            log "✅ Deleted IAM role: ${IAM_ROLE_NAME}"
        else
            info "IAM role ${IAM_ROLE_NAME} not found"
        fi
    else
        warn "IAM role name not provided, skipping IAM cleanup"
    fi
}

# =============================================================================
# KMS Keys Cleanup
# =============================================================================

destroy_kms_keys() {
    log "Destroying KMS keys..."
    
    if [ -n "${RANDOM_SUFFIX}" ]; then
        local kms_alias_base="alias/dynamodb-global-${RANDOM_SUFFIX}"
        
        # Schedule key deletion for each region
        schedule_key_deletion() {
            local region=$1
            local key_id=$2
            local alias_name="${kms_alias_base}-${region}"
            
            # Delete alias first
            if aws kms describe-key --region "${region}" --key-id "${alias_name}" &>/dev/null; then
                aws kms delete-alias \
                    --region "${region}" \
                    --alias-name "${alias_name}" \
                    >> "${LOG_FILE}" 2>&1
                log "✅ Deleted KMS alias: ${alias_name}"
            fi
            
            # Schedule key deletion
            if [ -n "${key_id}" ] && aws kms describe-key --region "${region}" --key-id "${key_id}" &>/dev/null; then
                aws kms schedule-key-deletion \
                    --region "${region}" \
                    --key-id "${key_id}" \
                    --pending-window-in-days 7 \
                    >> "${LOG_FILE}" 2>&1
                log "✅ Scheduled KMS key deletion in ${region}: ${key_id}"
            else
                info "KMS key not found in ${region}"
            fi
        }
        
        # Schedule deletion for all regions
        schedule_key_deletion "${PRIMARY_REGION}" "${PRIMARY_KEY_ID}"
        schedule_key_deletion "${SECONDARY_REGION}" "${SECONDARY_KEY_ID}"
        schedule_key_deletion "${TERTIARY_REGION}" "${TERTIARY_KEY_ID}"
        
        warn "KMS keys are scheduled for deletion in 7 days (minimum AWS requirement)"
    else
        warn "Random suffix not found, skipping KMS key cleanup"
    fi
}

# =============================================================================
# Cleanup Summary
# =============================================================================

create_destruction_summary() {
    log "Creating destruction summary..."
    
    local summary_file="${SCRIPT_DIR}/destruction-summary.json"
    
    cat > "${summary_file}" << EOF
{
    "destruction_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "destroyed_resources": {
        "dynamodb_table": "${TABLE_NAME}",
        "iam_role": "${IAM_ROLE_NAME}",
        "lambda_function": "${LAMBDA_FUNCTION_NAME}",
        "backup_vault": "${BACKUP_VAULT_NAME}",
        "backup_plan_id": "${BACKUP_PLAN_ID}",
        "kms_keys_scheduled_for_deletion": {
            "primary_region": "${PRIMARY_REGION}",
            "secondary_region": "${SECONDARY_REGION}",
            "tertiary_region": "${TERTIARY_REGION}"
        }
    },
    "regions_cleaned": [
        "${PRIMARY_REGION}",
        "${SECONDARY_REGION}",
        "${TERTIARY_REGION}"
    ],
    "notes": [
        "KMS keys are scheduled for deletion in 7 days",
        "Some CloudWatch logs may remain and should be manually cleaned if needed",
        "Backup recovery points may still exist in the backup vault"
    ]
}
EOF
    
    log "✅ Destruction summary created: ${summary_file}"
}

# =============================================================================
# Main Destruction Function
# =============================================================================

main() {
    log "Starting DynamoDB Global Tables destruction..."
    log "=================================================="
    
    # Initialize logging
    echo "Destruction started at $(date)" > "${LOG_FILE}"
    
    # Setup and configuration
    check_prerequisites
    load_deployment_config
    confirm_destruction
    
    # Destroy resources in reverse order of creation
    destroy_lambda_function
    destroy_cloudwatch_alarms
    destroy_backup_configuration
    destroy_global_tables
    destroy_iam_role
    destroy_kms_keys
    
    # Create summary
    create_destruction_summary
    
    # Remove deployment summary file
    if [ -f "${DEPLOYMENT_SUMMARY}" ]; then
        rm "${DEPLOYMENT_SUMMARY}"
        log "✅ Removed deployment summary file"
    fi
    
    log "=================================================="
    log "🎉 DynamoDB Global Tables destruction completed!"
    log "=================================================="
    
    info "Destruction log: ${LOG_FILE}"
    info "Destruction summary: ${SCRIPT_DIR}/destruction-summary.json"
    
    warn "Important notes:"
    warn "- KMS keys are scheduled for deletion in 7 days (AWS minimum)"
    warn "- Some CloudWatch logs may remain and should be manually cleaned if needed"
    warn "- Backup recovery points may still exist in backup vaults"
    warn "- Check the destruction summary for complete details"
}

# =============================================================================
# Script Execution
# =============================================================================

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo "Destroy DynamoDB Global Tables architecture"
        echo ""
        echo "Options:"
        echo "  -h, --help         Show this help message"
        echo "  --force            Skip confirmation prompt"
        echo "  --dry-run          Show what would be destroyed without executing"
        echo ""
        echo "Environment Variables:"
        echo "  PRIMARY_REGION     Primary AWS region (default: us-east-1)"
        echo "  SECONDARY_REGION   Secondary AWS region (default: eu-west-1)"
        echo "  TERTIARY_REGION    Tertiary AWS region (default: ap-southeast-1)"
        echo ""
        exit 0
        ;;
    --dry-run)
        log "DRY RUN MODE - No resources will be destroyed"
        check_prerequisites
        load_deployment_config
        log "Would destroy:"
        log "  - DynamoDB Global Table: ${TABLE_NAME}"
        log "  - IAM Role: ${IAM_ROLE_NAME}"
        log "  - Lambda Function: ${LAMBDA_FUNCTION_NAME}"
        log "  - Backup Vault: ${BACKUP_VAULT_NAME}"
        log "  - KMS Keys in regions: ${PRIMARY_REGION}, ${SECONDARY_REGION}, ${TERTIARY_REGION}"
        log "  - CloudWatch Alarms in all regions"
        exit 0
        ;;
    --force)
        log "FORCE MODE - Skipping confirmation prompt"
        # Override confirmation function to skip prompt
        confirm_destruction() {
            log "Skipping confirmation prompt (force mode)"
        }
        main
        ;;
    "")
        main
        ;;
    *)
        error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac