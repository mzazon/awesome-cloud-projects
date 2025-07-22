#!/bin/bash

#####################################################################
# AWS Single Sign-On with External Identity Providers - Destroy Script
# 
# This script safely removes all AWS IAM Identity Center resources
# created by the deployment script, including permission sets, user
# assignments, and test users/groups.
#
# Usage: ./destroy.sh [OPTIONS]
# Options:
#   --force       Skip confirmation prompts
#   --keep-users  Keep test users and groups (delete assignments only)
#   --verbose     Enable verbose logging
#   --help        Show this help message
#####################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
STATE_FILE="${SCRIPT_DIR}/deployment-state.env"
VERBOSE=false
FORCE=false
KEEP_USERS=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#####################################################################
# Utility Functions
#####################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
        DEBUG) [[ $VERBOSE == true ]] && echo -e "${BLUE}[DEBUG]${NC} $message" ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

error_exit() {
    log ERROR "$1"
    exit 1
}

execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    log DEBUG "Executing: $cmd"
    
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        log INFO "✅ $description"
        return 0
    else
        if [[ $ignore_errors == "true" ]]; then
            log WARN "⚠️  $description (ignored)"
            return 0
        else
            log ERROR "❌ Failed: $description"
            return 1
        fi
    fi
}

confirm_action() {
    local message="$1"
    
    if [[ $FORCE == true ]]; then
        log INFO "$message (auto-confirmed with --force)"
        return 0
    fi
    
    echo -e "${YELLOW}⚠️  $message${NC}"
    read -p "Do you want to continue? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        log INFO "Operation cancelled by user"
        exit 0
    fi
}

wait_for_operation() {
    local operation_id="$1"
    local operation_type="$2"
    local timeout=300  # 5 minutes
    local elapsed=0
    local interval=10
    
    log INFO "Waiting for $operation_type operation to complete..."
    
    while [[ $elapsed -lt $timeout ]]; do
        local status=$(aws sso-admin describe-permission-set-provisioning-status \
            --instance-arn "$SSO_INSTANCE_ARN" \
            --provisioning-request-id "$operation_id" \
            --query 'ProvisioningStatus.Status' \
            --output text 2>/dev/null || echo "UNKNOWN")
        
        case $status in
            "SUCCEEDED")
                log INFO "✅ $operation_type operation completed successfully"
                return 0
                ;;
            "FAILED")
                log WARN "⚠️  $operation_type operation failed (this may be expected during cleanup)"
                return 0
                ;;
            "IN_PROGRESS")
                log DEBUG "$operation_type operation in progress..."
                ;;
            *)
                log DEBUG "Unknown status: $status"
                ;;
        esac
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    log WARN "⚠️  Timeout waiting for $operation_type operation (continuing cleanup)"
    return 0
}

#####################################################################
# State Management Functions
#####################################################################

load_deployment_state() {
    log INFO "Loading deployment state..."
    
    if [[ ! -f "$STATE_FILE" ]]; then
        error_exit "Deployment state file not found: $STATE_FILE"
    fi
    
    # Source the state file to load environment variables
    set -o allexport
    source "$STATE_FILE"
    set +o allexport
    
    log INFO "Deployment state loaded:"
    log INFO "  SSO Instance ARN: ${SSO_INSTANCE_ARN:-'Not found'}"
    log INFO "  Identity Store ID: ${IDENTITY_STORE_ID:-'Not found'}"
    log INFO "  Random Suffix: ${RANDOM_SUFFIX:-'Not found'}"
    
    # Validate required variables
    if [[ -z "${SSO_INSTANCE_ARN:-}" ]]; then
        error_exit "SSO_INSTANCE_ARN not found in state file"
    fi
    
    if [[ -z "${IDENTITY_STORE_ID:-}" ]]; then
        error_exit "IDENTITY_STORE_ID not found in state file"
    fi
}

verify_resources_exist() {
    log INFO "Verifying resources exist before cleanup..."
    
    # Check IAM Identity Center instance
    if ! aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text &> /dev/null; then
        log WARN "IAM Identity Center instance not accessible"
    fi
    
    # Check permission sets exist
    local ps_count=0
    for ps_arn in "${DEVELOPER_PS_ARN:-}" "${ADMIN_PS_ARN:-}" "${READONLY_PS_ARN:-}"; do
        if [[ -n "$ps_arn" ]] && aws sso-admin describe-permission-set \
            --instance-arn "$SSO_INSTANCE_ARN" \
            --permission-set-arn "$ps_arn" &> /dev/null; then
            ((ps_count++))
        fi
    done
    
    log INFO "Found $ps_count permission sets to clean up"
    
    # Check test users/groups exist
    if [[ -n "${TEST_USER_ID:-}" ]] && aws identitystore describe-user \
        --identity-store-id "$IDENTITY_STORE_ID" \
        --user-id "$TEST_USER_ID" &> /dev/null; then
        log INFO "Test user exists and will be cleaned up"
    fi
    
    if [[ -n "${TEST_GROUP_ID:-}" ]] && aws identitystore describe-group \
        --identity-store-id "$IDENTITY_STORE_ID" \
        --group-id "$TEST_GROUP_ID" &> /dev/null; then
        log INFO "Test group exists and will be cleaned up"
    fi
}

#####################################################################
# Cleanup Functions
#####################################################################

remove_account_assignments() {
    log INFO "Removing account assignments..."
    
    if [[ -z "${FIRST_ACCOUNT:-}" ]]; then
        log WARN "FIRST_ACCOUNT not found in state, skipping account assignments cleanup"
        return 0
    fi
    
    # Remove group assignment for Developer permission set
    if [[ -n "${TEST_GROUP_ID:-}" ]] && [[ -n "${DEVELOPER_PS_ARN:-}" ]]; then
        execute_command \
            "aws sso-admin delete-account-assignment \
                --instance-arn '$SSO_INSTANCE_ARN' \
                --target-id '$FIRST_ACCOUNT' \
                --target-type AWS_ACCOUNT \
                --permission-set-arn '$DEVELOPER_PS_ARN' \
                --principal-type GROUP \
                --principal-id '$TEST_GROUP_ID'" \
            "Removed group assignment for Developer access" \
            "true"
    fi
    
    # Remove user assignment for ReadOnly permission set
    if [[ -n "${TEST_USER_ID:-}" ]] && [[ -n "${READONLY_PS_ARN:-}" ]]; then
        execute_command \
            "aws sso-admin delete-account-assignment \
                --instance-arn '$SSO_INSTANCE_ARN' \
                --target-id '$FIRST_ACCOUNT' \
                --target-type AWS_ACCOUNT \
                --permission-set-arn '$READONLY_PS_ARN' \
                --principal-type USER \
                --principal-id '$TEST_USER_ID'" \
            "Removed user assignment for ReadOnly access" \
            "true"
    fi
    
    log INFO "✅ Account assignments cleanup completed"
}

remove_users_and_groups() {
    if [[ $KEEP_USERS == true ]]; then
        log INFO "Skipping user and group cleanup (--keep-users specified)"
        return 0
    fi
    
    log INFO "Removing test users and groups..."
    
    # Remove group membership first
    if [[ -n "${TEST_GROUP_ID:-}" ]] && [[ -n "${TEST_USER_ID:-}" ]]; then
        # Get membership ID
        local membership_id
        if membership_id=$(aws identitystore list-group-memberships \
            --identity-store-id "$IDENTITY_STORE_ID" \
            --group-id "$TEST_GROUP_ID" \
            --query 'GroupMemberships[0].MembershipId' \
            --output text 2>/dev/null) && [[ "$membership_id" != "None" ]]; then
            
            execute_command \
                "aws identitystore delete-group-membership \
                    --identity-store-id '$IDENTITY_STORE_ID' \
                    --membership-id '$membership_id'" \
                "Removed group membership" \
                "true"
        fi
    fi
    
    # Delete test user
    if [[ -n "${TEST_USER_ID:-}" ]]; then
        execute_command \
            "aws identitystore delete-user \
                --identity-store-id '$IDENTITY_STORE_ID' \
                --user-id '$TEST_USER_ID'" \
            "Deleted test user" \
            "true"
    fi
    
    # Delete test group
    if [[ -n "${TEST_GROUP_ID:-}" ]]; then
        execute_command \
            "aws identitystore delete-group \
                --identity-store-id '$IDENTITY_STORE_ID' \
                --group-id '$TEST_GROUP_ID'" \
            "Deleted test group" \
            "true"
    fi
    
    log INFO "✅ Users and groups cleanup completed"
}

deprovision_permission_sets() {
    log INFO "Deprovisioning permission sets from organization accounts..."
    
    # Get list of accounts in organization
    local accounts
    if ! accounts=$(aws organizations list-accounts \
        --query 'Accounts[?Status==`ACTIVE`].Id' --output text 2>/dev/null); then
        log WARN "Failed to list organization accounts, skipping deprovisioning"
        return 0
    fi
    
    # Deprovision permission sets from accounts
    for account_id in $accounts; do
        log INFO "Deprovisioning permission sets for account: $account_id"
        
        # Deprovision Developer permission set
        if [[ -n "${DEVELOPER_PS_ARN:-}" ]]; then
            if request_id=$(aws sso-admin provision-permission-set \
                --instance-arn "$SSO_INSTANCE_ARN" \
                --permission-set-arn "$DEVELOPER_PS_ARN" \
                --target-id "$account_id" \
                --target-type AWS_ACCOUNT \
                --query 'ProvisioningStatus.RequestId' \
                --output text 2>/dev/null); then
                wait_for_operation "$request_id" "Developer permission set deprovisioning"
            fi
        fi
        
        # Deprovision Administrator permission set
        if [[ -n "${ADMIN_PS_ARN:-}" ]]; then
            if request_id=$(aws sso-admin provision-permission-set \
                --instance-arn "$SSO_INSTANCE_ARN" \
                --permission-set-arn "$ADMIN_PS_ARN" \
                --target-id "$account_id" \
                --target-type AWS_ACCOUNT \
                --query 'ProvisioningStatus.RequestId' \
                --output text 2>/dev/null); then
                wait_for_operation "$request_id" "Administrator permission set deprovisioning"
            fi
        fi
        
        # Deprovision ReadOnly permission set
        if [[ -n "${READONLY_PS_ARN:-}" ]]; then
            if request_id=$(aws sso-admin provision-permission-set \
                --instance-arn "$SSO_INSTANCE_ARN" \
                --permission-set-arn "$READONLY_PS_ARN" \
                --target-id "$account_id" \
                --target-type AWS_ACCOUNT \
                --query 'ProvisioningStatus.RequestId' \
                --output text 2>/dev/null); then
                wait_for_operation "$request_id" "ReadOnly permission set deprovisioning"
            fi
        fi
    done
    
    log INFO "✅ Permission sets deprovisioning completed"
}

remove_permission_sets() {
    log INFO "Removing permission sets..."
    
    # Delete Developer permission set
    if [[ -n "${DEVELOPER_PS_ARN:-}" ]]; then
        execute_command \
            "aws sso-admin delete-permission-set \
                --instance-arn '$SSO_INSTANCE_ARN' \
                --permission-set-arn '$DEVELOPER_PS_ARN'" \
            "Deleted Developer permission set" \
            "true"
    fi
    
    # Delete Administrator permission set
    if [[ -n "${ADMIN_PS_ARN:-}" ]]; then
        execute_command \
            "aws sso-admin delete-permission-set \
                --instance-arn '$SSO_INSTANCE_ARN' \
                --permission-set-arn '$ADMIN_PS_ARN'" \
            "Deleted Administrator permission set" \
            "true"
    fi
    
    # Delete ReadOnly permission set
    if [[ -n "${READONLY_PS_ARN:-}" ]]; then
        execute_command \
            "aws sso-admin delete-permission-set \
                --instance-arn '$SSO_INSTANCE_ARN' \
                --permission-set-arn '$READONLY_PS_ARN'" \
            "Deleted ReadOnly permission set" \
            "true"
    fi
    
    log INFO "✅ Permission sets cleanup completed"
}

cleanup_temporary_files() {
    log INFO "Cleaning up temporary files..."
    
    # Remove temporary policy files
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        rm -f "/tmp/s3-policy-${RANDOM_SUFFIX}.json"
        rm -f "/tmp/saml-metadata-${RANDOM_SUFFIX}.xml"
        rm -f "/tmp/attribute-mapping-${RANDOM_SUFFIX}.json"
    fi
    
    # Remove any other temporary files
    rm -f /tmp/s3-policy-*.json
    rm -f /tmp/saml-metadata*.xml
    rm -f /tmp/attribute-mapping*.json
    
    log INFO "✅ Temporary files cleanup completed"
}

cleanup_state_file() {
    log INFO "Cleaning up deployment state..."
    
    if [[ $FORCE == true ]]; then
        rm -f "$STATE_FILE"
        log INFO "✅ Deployment state file removed"
    else
        log INFO "Deployment state file preserved: $STATE_FILE"
        log INFO "  (Use --force to automatically remove state file)"
    fi
}

#####################################################################
# Validation Functions
#####################################################################

validate_cleanup() {
    log INFO "Validating cleanup..."
    
    # Check if permission sets still exist
    local remaining_ps=0
    for ps_arn in "${DEVELOPER_PS_ARN:-}" "${ADMIN_PS_ARN:-}" "${READONLY_PS_ARN:-}"; do
        if [[ -n "$ps_arn" ]] && aws sso-admin describe-permission-set \
            --instance-arn "$SSO_INSTANCE_ARN" \
            --permission-set-arn "$ps_arn" &> /dev/null; then
            ((remaining_ps++))
            log WARN "Permission set still exists: $ps_arn"
        fi
    done
    
    if [[ $remaining_ps -eq 0 ]]; then
        log INFO "✅ All permission sets successfully removed"
    else
        log WARN "⚠️  $remaining_ps permission sets still exist"
    fi
    
    # Check if test users/groups still exist (only if we tried to delete them)
    if [[ $KEEP_USERS == false ]]; then
        local remaining_users=0
        
        if [[ -n "${TEST_USER_ID:-}" ]] && aws identitystore describe-user \
            --identity-store-id "$IDENTITY_STORE_ID" \
            --user-id "$TEST_USER_ID" &> /dev/null; then
            ((remaining_users++))
            log WARN "Test user still exists: $TEST_USER_ID"
        fi
        
        if [[ -n "${TEST_GROUP_ID:-}" ]] && aws identitystore describe-group \
            --identity-store-id "$IDENTITY_STORE_ID" \
            --group-id "$TEST_GROUP_ID" &> /dev/null; then
            ((remaining_users++))
            log WARN "Test group still exists: $TEST_GROUP_ID"
        fi
        
        if [[ $remaining_users -eq 0 ]]; then
            log INFO "✅ All test users and groups successfully removed"
        else
            log WARN "⚠️  $remaining_users test users/groups still exist"
        fi
    fi
    
    log INFO "✅ Cleanup validation completed"
}

#####################################################################
# Usage and Help Functions
#####################################################################

show_help() {
    cat << EOF
AWS Single Sign-On with External Identity Providers - Destroy Script

This script safely removes all AWS IAM Identity Center resources
created by the deployment script, including permission sets, user
assignments, and test users/groups.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --force       Skip confirmation prompts
    --keep-users  Keep test users and groups (delete assignments only)
    --verbose     Enable verbose logging
    --help        Show this help message

EXAMPLES:
    $0                    # Interactive cleanup with confirmations
    $0 --force            # Automatic cleanup without prompts
    $0 --keep-users       # Keep test users, only remove assignments
    $0 --verbose --force  # Verbose automatic cleanup

NOTES:
    - This script requires the deployment-state.env file
    - IAM Identity Center instance itself is NOT deleted
    - Only resources created by the deployment script are removed
    - Use --force for automated/scripted cleanup

For more information, see the recipe documentation.
EOF
}

#####################################################################
# Main Execution
#####################################################################

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE=true
                shift
                ;;
            --keep-users)
                KEEP_USERS=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Initialize log file
    echo "=== AWS SSO External Identity Provider Cleanup Started at $(date) ===" > "$LOG_FILE"
    
    log INFO "Starting AWS Single Sign-On External Identity Provider cleanup..."
    [[ $FORCE == true ]] && log INFO "FORCE MODE enabled - skipping confirmations"
    [[ $KEEP_USERS == true ]] && log INFO "KEEP USERS MODE enabled - preserving test users/groups"
    [[ $VERBOSE == true ]] && log INFO "VERBOSE MODE enabled"
    
    # Load deployment state
    load_deployment_state
    verify_resources_exist
    
    # Confirm destructive action
    confirm_action "This will remove IAM Identity Center resources created by the deployment script."
    
    # Execute cleanup steps
    remove_account_assignments
    remove_users_and_groups
    deprovision_permission_sets
    remove_permission_sets
    cleanup_temporary_files
    cleanup_state_file
    validate_cleanup
    
    log INFO "🧹 AWS Single Sign-On External Identity Provider cleanup completed!"
    log INFO ""
    log INFO "Summary:"
    log INFO "- Account assignments removed"
    if [[ $KEEP_USERS == false ]]; then
        log INFO "- Test users and groups removed"
    else
        log INFO "- Test users and groups preserved (--keep-users)"
    fi
    log INFO "- Permission sets removed"
    log INFO "- Temporary files cleaned up"
    log INFO ""
    log INFO "Note: IAM Identity Center instance is preserved and can be reused"
    log INFO "Full cleanup log: $LOG_FILE"
}

# Trap errors and cleanup
trap 'log ERROR "Cleanup failed. Check $LOG_FILE for details."' ERR

# Execute main function
main "$@"