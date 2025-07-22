#!/bin/bash

# =============================================================================
# AWS IoT SiteWise Sustainable Manufacturing Monitoring - Cleanup Script
# =============================================================================
# This script removes all resources created by the deployment script, ensuring
# complete cleanup to avoid unnecessary charges.
# 
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Deployment state file from previous deployment
# - Appropriate AWS permissions for resource deletion
# =============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# =============================================================================
# CONFIGURATION AND GLOBALS
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# LOGGING AND UTILITY FUNCTIONS
# =============================================================================

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "${LOG_FILE}"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "${LOG_FILE}"
}

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check deployment state file
    if [[ ! -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        log_error "Deployment state file not found: ${DEPLOYMENT_STATE_FILE}"
        log_error "Cannot proceed with cleanup without deployment state information."
        exit 1
    fi
    
    # Load deployment state
    source "${DEPLOYMENT_STATE_FILE}"
    
    # Verify required variables
    if [[ -z "${DEPLOYMENT_ID}" ]]; then
        log_error "DEPLOYMENT_ID not found in state file."
        exit 1
    fi
    
    log "Prerequisites check completed successfully."
    log_info "Deployment ID: ${DEPLOYMENT_ID}"
}

# =============================================================================
# CONFIRMATION AND SAFETY CHECKS
# =============================================================================

confirm_cleanup() {
    log_warn "This will permanently delete all resources created by the deployment."
    log_warn "This action cannot be undone."
    log ""
    log "Resources to be deleted:"
    log "- IoT SiteWise Asset Model: ${ASSET_MODEL_ID:-"Not found"}"
    log "- IoT SiteWise Assets: ${EQUIPMENT_1_ID:-"Not found"}, ${EQUIPMENT_2_ID:-"Not found"}"
    log "- Lambda Function: ${LAMBDA_FUNCTION_NAME:-"Not found"}"
    log "- IAM Role: ${LAMBDA_ROLE_NAME:-"Not found"}"
    log "- CloudWatch Alarms: ${CARBON_ALARM_NAME:-"Not found"}, ${EFFICIENCY_ALARM_NAME:-"Not found"}"
    log "- EventBridge Rule: ${EVENTBRIDGE_RULE_NAME:-"Not found"}"
    log ""
    
    read -p "Are you sure you want to continue? (Type 'yes' to confirm): " -r
    if [[ ! $REPLY == "yes" ]]; then
        log_info "Cleanup cancelled."
        exit 0
    fi
    
    log "Proceeding with cleanup..."
}

# =============================================================================
# EVENTBRIDGE CLEANUP
# =============================================================================

cleanup_eventbridge() {
    log "Cleaning up EventBridge resources..."
    
    if [[ -n "${EVENTBRIDGE_RULE_NAME}" ]]; then
        # Remove targets first
        log_info "Removing EventBridge targets..."
        aws events remove-targets \
            --rule "${EVENTBRIDGE_RULE_NAME}" \
            --ids "1" 2>/dev/null || log_warn "Failed to remove EventBridge targets"
        
        # Delete rule
        log_info "Deleting EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
        aws events delete-rule \
            --name "${EVENTBRIDGE_RULE_NAME}" 2>/dev/null || log_warn "Failed to delete EventBridge rule"
        
        log "EventBridge rule deleted successfully."
    else
        log_warn "EventBridge rule name not found in state file."
    fi
}

# =============================================================================
# CLOUDWATCH CLEANUP
# =============================================================================

cleanup_cloudwatch() {
    log "Cleaning up CloudWatch resources..."
    
    # Delete carbon emissions alarm
    if [[ -n "${CARBON_ALARM_NAME}" ]]; then
        log_info "Deleting CloudWatch alarm: ${CARBON_ALARM_NAME}"
        aws cloudwatch delete-alarms \
            --alarm-names "${CARBON_ALARM_NAME}" 2>/dev/null || log_warn "Failed to delete carbon emissions alarm"
    fi
    
    # Delete energy efficiency alarm
    if [[ -n "${EFFICIENCY_ALARM_NAME}" ]]; then
        log_info "Deleting CloudWatch alarm: ${EFFICIENCY_ALARM_NAME}"
        aws cloudwatch delete-alarms \
            --alarm-names "${EFFICIENCY_ALARM_NAME}" 2>/dev/null || log_warn "Failed to delete energy efficiency alarm"
    fi
    
    # Note: CloudWatch metrics are automatically cleaned up by AWS after retention period
    log_info "CloudWatch metrics will be automatically cleaned up after retention period."
    
    log "CloudWatch alarms cleanup completed."
}

# =============================================================================
# LAMBDA CLEANUP
# =============================================================================

cleanup_lambda() {
    log "Cleaning up Lambda resources..."
    
    if [[ -n "${LAMBDA_FUNCTION_NAME}" ]]; then
        # Remove Lambda permissions first
        log_info "Removing Lambda permissions..."
        aws lambda remove-permission \
            --function-name "${LAMBDA_FUNCTION_NAME}" \
            --statement-id "daily-sustainability-report" 2>/dev/null || log_warn "Failed to remove Lambda permissions"
        
        # Delete Lambda function
        log_info "Deleting Lambda function: ${LAMBDA_FUNCTION_NAME}"
        aws lambda delete-function \
            --function-name "${LAMBDA_FUNCTION_NAME}" 2>/dev/null || log_warn "Failed to delete Lambda function"
        
        log "Lambda function deleted successfully."
    else
        log_warn "Lambda function name not found in state file."
    fi
    
    # Clean up IAM role
    if [[ -n "${LAMBDA_ROLE_NAME}" ]]; then
        log_info "Cleaning up IAM role: ${LAMBDA_ROLE_NAME}"
        
        # Detach policies
        aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || log_warn "Failed to detach Lambda execution policy"
        
        aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess 2>/dev/null || log_warn "Failed to detach CloudWatch policy"
        
        aws iam detach-role-policy \
            --role-name "${LAMBDA_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/AWSIoTSiteWiseReadOnlyAccess 2>/dev/null || log_warn "Failed to detach IoT SiteWise policy"
        
        # Delete role
        aws iam delete-role \
            --role-name "${LAMBDA_ROLE_NAME}" 2>/dev/null || log_warn "Failed to delete IAM role"
        
        log "IAM role cleaned up successfully."
    else
        log_warn "Lambda role name not found in state file."
    fi
}

# =============================================================================
# IOT SITEWISE CLEANUP
# =============================================================================

cleanup_iot_sitewise() {
    log "Cleaning up IoT SiteWise resources..."
    
    # Delete equipment assets first
    if [[ -n "${EQUIPMENT_1_ID}" ]]; then
        log_info "Deleting equipment asset 1: ${EQUIPMENT_1_ID}"
        aws iotsitewise delete-asset --asset-id "${EQUIPMENT_1_ID}" 2>/dev/null || log_warn "Failed to delete equipment asset 1"
        
        # Wait for asset deletion
        log_info "Waiting for asset 1 to be deleted..."
        aws iotsitewise wait asset-not-exists --asset-id "${EQUIPMENT_1_ID}" 2>/dev/null || log_warn "Asset 1 deletion wait failed"
    fi
    
    if [[ -n "${EQUIPMENT_2_ID}" ]]; then
        log_info "Deleting equipment asset 2: ${EQUIPMENT_2_ID}"
        aws iotsitewise delete-asset --asset-id "${EQUIPMENT_2_ID}" 2>/dev/null || log_warn "Failed to delete equipment asset 2"
        
        # Wait for asset deletion
        log_info "Waiting for asset 2 to be deleted..."
        aws iotsitewise wait asset-not-exists --asset-id "${EQUIPMENT_2_ID}" 2>/dev/null || log_warn "Asset 2 deletion wait failed"
    fi
    
    # Delete asset model
    if [[ -n "${ASSET_MODEL_ID}" ]]; then
        log_info "Deleting asset model: ${ASSET_MODEL_ID}"
        aws iotsitewise delete-asset-model --asset-model-id "${ASSET_MODEL_ID}" 2>/dev/null || log_warn "Failed to delete asset model"
        
        # Wait for asset model deletion
        log_info "Waiting for asset model to be deleted..."
        aws iotsitewise wait asset-model-not-exists --asset-model-id "${ASSET_MODEL_ID}" 2>/dev/null || log_warn "Asset model deletion wait failed"
    fi
    
    log "IoT SiteWise resources cleanup completed."
}

# =============================================================================
# FILE CLEANUP
# =============================================================================

cleanup_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files created during deployment
    local files_to_remove=(
        "manufacturing-equipment-model.json"
        "carbon-calculator.py"
        "carbon-calculator.zip"
        "trust-policy.json"
        "simulate-data.json"
        "test-response.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${SCRIPT_DIR}/${file}" ]]; then
            log_info "Removing file: ${file}"
            rm -f "${SCRIPT_DIR}/${file}"
        fi
    done
    
    # Ask user if they want to remove deployment state and logs
    log ""
    read -p "Do you want to remove deployment state and log files? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Removing deployment state and log files..."
        rm -f "${DEPLOYMENT_STATE_FILE}"
        rm -f "${LOG_FILE}"
        log_info "All files cleaned up."
    else
        log_info "Keeping deployment state and log files for reference."
    fi
}

# =============================================================================
# VERIFICATION
# =============================================================================

verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check IoT SiteWise assets
    if [[ -n "${EQUIPMENT_1_ID}" ]]; then
        if aws iotsitewise describe-asset --asset-id "${EQUIPMENT_1_ID}" &>/dev/null; then
            log_warn "Equipment asset 1 still exists: ${EQUIPMENT_1_ID}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [[ -n "${EQUIPMENT_2_ID}" ]]; then
        if aws iotsitewise describe-asset --asset-id "${EQUIPMENT_2_ID}" &>/dev/null; then
            log_warn "Equipment asset 2 still exists: ${EQUIPMENT_2_ID}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check asset model
    if [[ -n "${ASSET_MODEL_ID}" ]]; then
        if aws iotsitewise describe-asset-model --asset-model-id "${ASSET_MODEL_ID}" &>/dev/null; then
            log_warn "Asset model still exists: ${ASSET_MODEL_ID}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check Lambda function
    if [[ -n "${LAMBDA_FUNCTION_NAME}" ]]; then
        if aws lambda get-function --function-name "${LAMBDA_FUNCTION_NAME}" &>/dev/null; then
            log_warn "Lambda function still exists: ${LAMBDA_FUNCTION_NAME}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check IAM role
    if [[ -n "${LAMBDA_ROLE_NAME}" ]]; then
        if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &>/dev/null; then
            log_warn "IAM role still exists: ${LAMBDA_ROLE_NAME}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check CloudWatch alarms
    if [[ -n "${CARBON_ALARM_NAME}" ]]; then
        if aws cloudwatch describe-alarms --alarm-names "${CARBON_ALARM_NAME}" --query 'MetricAlarms[0]' --output text 2>/dev/null | grep -q "${CARBON_ALARM_NAME}"; then
            log_warn "CloudWatch alarm still exists: ${CARBON_ALARM_NAME}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check EventBridge rule
    if [[ -n "${EVENTBRIDGE_RULE_NAME}" ]]; then
        if aws events describe-rule --name "${EVENTBRIDGE_RULE_NAME}" &>/dev/null; then
            log_warn "EventBridge rule still exists: ${EVENTBRIDGE_RULE_NAME}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [[ ${cleanup_issues} -eq 0 ]]; then
        log "Cleanup verification completed successfully. All resources removed."
    else
        log_warn "Cleanup verification found ${cleanup_issues} issues. Some resources may still exist."
        log_warn "Please check the AWS console manually for any remaining resources."
    fi
}

# =============================================================================
# MAIN CLEANUP FUNCTION
# =============================================================================

main() {
    log "Starting AWS IoT SiteWise Sustainable Manufacturing Monitoring cleanup..."
    
    # Initialize log file
    echo "=== AWS IoT SiteWise Sustainable Manufacturing Monitoring Cleanup ===" > "${LOG_FILE}"
    echo "Started at: $(date)" >> "${LOG_FILE}"
    
    # Execute cleanup steps
    check_prerequisites
    confirm_cleanup
    
    # Cleanup in reverse order of creation
    cleanup_eventbridge
    cleanup_cloudwatch
    cleanup_lambda
    cleanup_iot_sitewise
    cleanup_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display cleanup summary
    log ""
    log "=========================================="
    log "CLEANUP COMPLETED"
    log "=========================================="
    log ""
    log "Cleanup Summary:"
    log "- Deployment ID: ${DEPLOYMENT_ID}"
    log "- All AWS resources have been removed"
    log "- Local files have been cleaned up"
    log ""
    log "Notes:"
    log "- CloudWatch metrics will be automatically cleaned up after retention period"
    log "- Check AWS console to verify no unexpected charges"
    log "- Keep this log for reference: ${LOG_FILE}"
    log ""
    
    log "Cleanup completed successfully! Check ${LOG_FILE} for detailed logs."
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi