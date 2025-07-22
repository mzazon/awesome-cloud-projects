#!/bin/bash

# AWS AppConfig Feature Flags Cleanup Script
# Based on the "Feature Flags with AWS AppConfig" recipe
# Version: 1.0
# Description: Cleans up all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/feature-flags-appconfig-destroy-$(date +%Y%m%d_%H%M%S).log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Check log file: ${LOG_FILE}"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
    fi
    
    # Test AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured or invalid. Run 'aws configure' first."
    fi
    
    local caller_info=$(aws sts get-caller-identity)
    local account_id=$(echo "$caller_info" | jq -r '.Account' 2>/dev/null || echo "$caller_info" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
    log_info "Connected to AWS Account: ${account_id}"
    
    log_success "Prerequisites check completed."
}

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [ ! -f "${DEPLOYMENT_STATE_FILE}" ]; then
        log_warn "Deployment state file not found: ${DEPLOYMENT_STATE_FILE}"
        log_warn "This may indicate the deployment was not completed or the state file was moved."
        return 1
    fi
    
    # Source the deployment state file
    source "${DEPLOYMENT_STATE_FILE}"
    
    log_info "Loaded deployment state:"
    log_info "  AWS Region: ${AWS_REGION:-NOT_SET}"
    log_info "  AWS Account: ${AWS_ACCOUNT_ID:-NOT_SET}"
    log_info "  Application: ${APP_NAME:-NOT_SET}"
    log_info "  Function: ${FUNCTION_NAME:-NOT_SET}"
    
    return 0
}

# Prompt for confirmation
confirm_destruction() {
    echo ""
    echo -e "${RED}WARNING: This will permanently delete all AWS AppConfig Feature Flags resources!${NC}"
    echo ""
    echo "Resources to be deleted:"
    echo "  • Lambda Function: ${FUNCTION_NAME:-UNKNOWN}"
    echo "  • AppConfig Application: ${APP_NAME:-UNKNOWN}"
    echo "  • AppConfig Environment: ${ENVIRONMENT_NAME:-UNKNOWN}"
    echo "  • IAM Role and Policies: ${ROLE_NAME:-UNKNOWN}"
    echo "  • CloudWatch Alarm: ${ALARM_NAME:-UNKNOWN}"
    echo "  • Deployment Strategy: ${STRATEGY_NAME:-UNKNOWN}"
    echo ""
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " confirmation
    
    if [ "${confirmation}" != "yes" ]; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
    
    log_info "User confirmed destruction. Proceeding..."
}

# Stop active deployments
stop_active_deployments() {
    log_info "Stopping active deployments..."
    
    if [ -n "${APP_ID:-}" ] && [ -n "${ENV_ID:-}" ] && [ -n "${DEPLOYMENT_ID:-}" ]; then
        if aws appconfig stop-deployment \
            --application-id "${APP_ID}" \
            --environment-id "${ENV_ID}" \
            --deployment-number "${DEPLOYMENT_ID}" \
            --output text &>> "${LOG_FILE}"; then
            log_success "Stopped deployment: ${DEPLOYMENT_ID}"
        else
            log_warn "Failed to stop deployment or no active deployment found"
        fi
    else
        log_info "No deployment information available to stop"
    fi
}

# Delete Lambda function
delete_lambda_function() {
    log_info "Deleting Lambda function..."
    
    if [ -n "${FUNCTION_NAME:-}" ]; then
        if aws lambda delete-function \
            --function-name "${FUNCTION_NAME}" \
            &>> "${LOG_FILE}"; then
            log_success "Lambda function deleted: ${FUNCTION_NAME}"
        else
            log_warn "Failed to delete Lambda function or function not found"
        fi
    else
        log_warn "Lambda function name not available"
    fi
}

# Delete AppConfig resources
delete_appconfig_resources() {
    log_info "Deleting AppConfig resources..."
    
    # Delete AppConfig environment
    if [ -n "${APP_ID:-}" ] && [ -n "${ENV_ID:-}" ]; then
        if aws appconfig delete-environment \
            --application-id "${APP_ID}" \
            --environment-id "${ENV_ID}" \
            &>> "${LOG_FILE}"; then
            log_success "AppConfig environment deleted: ${ENVIRONMENT_NAME}"
        else
            log_warn "Failed to delete AppConfig environment or environment not found"
        fi
    else
        log_warn "AppConfig environment IDs not available"
    fi
    
    # Delete configuration profile
    if [ -n "${APP_ID:-}" ] && [ -n "${PROFILE_ID:-}" ]; then
        if aws appconfig delete-configuration-profile \
            --application-id "${APP_ID}" \
            --configuration-profile-id "${PROFILE_ID}" \
            &>> "${LOG_FILE}"; then
            log_success "Configuration profile deleted: ${PROFILE_NAME}"
        else
            log_warn "Failed to delete configuration profile or profile not found"
        fi
    else
        log_warn "Configuration profile IDs not available"
    fi
    
    # Delete deployment strategy
    if [ -n "${STRATEGY_ID:-}" ]; then
        if aws appconfig delete-deployment-strategy \
            --deployment-strategy-id "${STRATEGY_ID}" \
            &>> "${LOG_FILE}"; then
            log_success "Deployment strategy deleted: ${STRATEGY_NAME}"
        else
            log_warn "Failed to delete deployment strategy or strategy not found"
        fi
    else
        log_warn "Deployment strategy ID not available"
    fi
    
    # Delete application (this should be last)
    if [ -n "${APP_ID:-}" ]; then
        if aws appconfig delete-application \
            --application-id "${APP_ID}" \
            &>> "${LOG_FILE}"; then
            log_success "AppConfig application deleted: ${APP_NAME}"
        else
            log_warn "Failed to delete AppConfig application or application not found"
        fi
    else
        log_warn "AppConfig application ID not available"
    fi
}

# Delete IAM resources
delete_iam_resources() {
    log_info "Deleting IAM resources..."
    
    if [ -n "${ROLE_NAME:-}" ] && [ -n "${AWS_ACCOUNT_ID:-}" ] && [ -n "${POLICY_NAME:-}" ]; then
        # Detach policies from role
        if aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
            &>> "${LOG_FILE}"; then
            log_success "Detached Lambda basic execution policy"
        else
            log_warn "Failed to detach Lambda basic execution policy"
        fi
        
        if aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" \
            &>> "${LOG_FILE}"; then
            log_success "Detached AppConfig access policy"
        else
            log_warn "Failed to detach AppConfig access policy"
        fi
        
        # Delete custom policy
        if aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" \
            &>> "${LOG_FILE}"; then
            log_success "Deleted custom policy: ${POLICY_NAME}"
        else
            log_warn "Failed to delete custom policy"
        fi
        
        # Delete IAM role
        if aws iam delete-role \
            --role-name "${ROLE_NAME}" \
            &>> "${LOG_FILE}"; then
            log_success "Deleted IAM role: ${ROLE_NAME}"
        else
            log_warn "Failed to delete IAM role"
        fi
    else
        log_warn "IAM resource names not available"
    fi
}

# Delete CloudWatch alarm
delete_cloudwatch_alarm() {
    log_info "Deleting CloudWatch alarm..."
    
    if [ -n "${ALARM_NAME:-}" ]; then
        if aws cloudwatch delete-alarms \
            --alarm-names "${ALARM_NAME}" \
            &>> "${LOG_FILE}"; then
            log_success "CloudWatch alarm deleted: ${ALARM_NAME}"
        else
            log_warn "Failed to delete CloudWatch alarm or alarm not found"
        fi
    else
        log_warn "CloudWatch alarm name not available"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove temporary files that might still exist
    rm -f "${SCRIPT_DIR}/trust-policy.json" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/appconfig-policy.json" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/feature-flags.json" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/lambda_function.py" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/lambda-function.zip" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/response.json" 2>/dev/null || true
    
    log_success "Local temporary files cleaned up"
}

# Remove deployment state file
remove_deployment_state() {
    log_info "Removing deployment state file..."
    
    if [ -f "${DEPLOYMENT_STATE_FILE}" ]; then
        if rm "${DEPLOYMENT_STATE_FILE}"; then
            log_success "Deployment state file removed"
        else
            log_warn "Failed to remove deployment state file"
        fi
    else
        log_info "Deployment state file not found"
    fi
}

# Manual cleanup guidance
provide_manual_cleanup_guidance() {
    log_info "=== MANUAL CLEANUP GUIDANCE ==="
    log_info "If automated cleanup failed, you can manually delete resources:"
    log_info ""
    log_info "1. Lambda Functions:"
    log_info "   aws lambda list-functions --query 'Functions[?contains(FunctionName, \`feature-flag-demo\`)].FunctionName'"
    log_info ""
    log_info "2. AppConfig Applications:"
    log_info "   aws appconfig list-applications --query 'Items[?contains(Name, \`feature-demo-app\`)].{Name:Name,Id:Id}'"
    log_info ""
    log_info "3. IAM Roles:"
    log_info "   aws iam list-roles --query 'Roles[?contains(RoleName, \`lambda-appconfig-role\`)].RoleName'"
    log_info ""
    log_info "4. CloudWatch Alarms:"
    log_info "   aws cloudwatch describe-alarms --query 'MetricAlarms[?contains(AlarmName, \`lambda-error-rate\`)].AlarmName'"
    log_info ""
    log_info "5. AppConfig Deployment Strategies:"
    log_info "   aws appconfig list-deployment-strategies --query 'Items[?contains(Name, \`gradual-rollout\`)].{Name:Name,Id:Id}'"
}

# Display cleanup summary
display_summary() {
    log_success "=== CLEANUP COMPLETED ==="
    log_info "The following resources have been processed for deletion:"
    log_info "  • Lambda Function: ${FUNCTION_NAME:-NOT_SET}"
    log_info "  • AppConfig Application: ${APP_NAME:-NOT_SET}"
    log_info "  • AppConfig Environment: ${ENVIRONMENT_NAME:-NOT_SET}"
    log_info "  • Configuration Profile: ${PROFILE_NAME:-NOT_SET}"
    log_info "  • Deployment Strategy: ${STRATEGY_NAME:-NOT_SET}"
    log_info "  • IAM Role: ${ROLE_NAME:-NOT_SET}"
    log_info "  • CloudWatch Alarm: ${ALARM_NAME:-NOT_SET}"
    log_info ""
    log_info "Cleanup log saved to: ${LOG_FILE}"
    log_info ""
    log_warn "Note: Some resources may take a few minutes to be fully deleted."
    log_warn "Service-linked roles are not deleted by this script (they are shared resources)."
    log_info ""
    log_success "AWS AppConfig Feature Flags cleanup completed!"
}

# Fallback cleanup without state file
fallback_cleanup() {
    log_warn "Attempting fallback cleanup without state file..."
    log_info "This will search for and delete resources with common naming patterns."
    
    echo ""
    read -p "Do you want to proceed with fallback cleanup? Type 'yes' to confirm: " confirmation
    
    if [ "${confirmation}" != "yes" ]; then
        log_info "Fallback cleanup cancelled by user."
        provide_manual_cleanup_guidance
        return
    fi
    
    log_info "Searching for Lambda functions with 'feature-flag-demo' pattern..."
    local lambda_functions=$(aws lambda list-functions \
        --query 'Functions[?contains(FunctionName, `feature-flag-demo`)].FunctionName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "${lambda_functions}" ]; then
        for func in ${lambda_functions}; do
            log_info "Deleting Lambda function: ${func}"
            aws lambda delete-function --function-name "${func}" &>> "${LOG_FILE}" || log_warn "Failed to delete ${func}"
        done
    fi
    
    log_info "Searching for AppConfig applications with 'feature-demo-app' pattern..."
    local app_ids=$(aws appconfig list-applications \
        --query 'Items[?contains(Name, `feature-demo-app`)].Id' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "${app_ids}" ]; then
        for app_id in ${app_ids}; do
            log_info "Deleting AppConfig application: ${app_id}"
            # Note: This is simplified - in practice you'd need to delete environments and profiles first
            aws appconfig delete-application --application-id "${app_id}" &>> "${LOG_FILE}" || log_warn "Failed to delete app ${app_id}"
        done
    fi
    
    log_info "Searching for IAM roles with 'lambda-appconfig-role' pattern..."
    local iam_roles=$(aws iam list-roles \
        --query 'Roles[?contains(RoleName, `lambda-appconfig-role`)].RoleName' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "${iam_roles}" ]; then
        for role in ${iam_roles}; do
            log_info "Attempting to clean up IAM role: ${role}"
            # This is simplified - you'd need to detach policies first
            log_warn "Manual cleanup required for IAM role: ${role}"
        done
    fi
    
    log_info "Fallback cleanup completed. Some resources may require manual cleanup."
    provide_manual_cleanup_guidance
}

# Main cleanup function
main() {
    echo -e "${BLUE}Starting AWS AppConfig Feature Flags Cleanup${NC}"
    echo "Log file: ${LOG_FILE}"
    echo ""
    
    check_prerequisites
    
    if load_deployment_state; then
        confirm_destruction
        stop_active_deployments
        delete_lambda_function
        delete_appconfig_resources
        delete_iam_resources
        delete_cloudwatch_alarm
        cleanup_local_files
        remove_deployment_state
        display_summary
    else
        log_warn "Could not load deployment state. Attempting fallback cleanup..."
        fallback_cleanup
    fi
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi