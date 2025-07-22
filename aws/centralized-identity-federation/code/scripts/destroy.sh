#!/bin/bash

# =============================================================================
# AWS Identity Federation with SSO - Cleanup Script
# =============================================================================
# This script safely removes all resources created by the identity federation
# deployment, including IAM Identity Center configuration, permission sets,
# CloudTrail, and associated resources.
#
# Safety Features:
# - Interactive confirmation prompts
# - Resource dependency order handling
# - Graceful error handling for missing resources
# - Comprehensive logging of cleanup operations
# - State file cleanup
# =============================================================================

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly STATE_FILE="${SCRIPT_DIR}/deployment-state.json"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

get_state() {
    local key="$1"
    
    if [[ -f "${STATE_FILE}" ]] && command -v jq >/dev/null 2>&1; then
        jq -r --arg key "$key" '.[$key] // empty' "${STATE_FILE}"
    fi
}

confirm_action() {
    local prompt="$1"
    local response
    
    echo -e "${YELLOW}${prompt}${NC}"
    read -p "Type 'yes' to continue: " response
    
    if [[ "${response}" != "yes" ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
}

resource_exists() {
    local check_command="$1"
    eval "${check_command}" >/dev/null 2>&1
}

# =============================================================================
# Safety and Prerequisites Functions
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI is not installed."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    # Check if state file exists
    if [[ ! -f "${STATE_FILE}" ]]; then
        log_warning "Deployment state file not found. Some resources may need manual cleanup."
        confirm_action "Continue with cleanup without state file?"
    fi
    
    log_success "Prerequisites check completed"
}

load_environment() {
    log "Loading environment from state file..."
    
    # Load from state file if available
    if [[ -f "${STATE_FILE}" ]]; then
        export SSO_INSTANCE_ARN
        SSO_INSTANCE_ARN=$(get_state "sso_instance_arn")
        
        export SSO_IDENTITY_STORE_ID
        SSO_IDENTITY_STORE_ID=$(get_state "sso_identity_store_id")
        
        export AWS_REGION
        AWS_REGION=$(get_state "aws_region")
        
        export AWS_ACCOUNT_ID
        AWS_ACCOUNT_ID=$(get_state "aws_account_id")
        
        export DEV_PERMISSION_SET_ARN
        DEV_PERMISSION_SET_ARN=$(get_state "dev_permission_set_arn")
        
        export ADMIN_PERMISSION_SET_ARN
        ADMIN_PERMISSION_SET_ARN=$(get_state "admin_permission_set_arn")
        
        export READONLY_PERMISSION_SET_ARN
        READONLY_PERMISSION_SET_ARN=$(get_state "readonly_permission_set_arn")
        
        export IDP_ARN
        IDP_ARN=$(get_state "idp_arn")
        
        export CLOUDTRAIL_BUCKET
        CLOUDTRAIL_BUCKET=$(get_state "cloudtrail_bucket")
        
        export CLOUDTRAIL_NAME
        CLOUDTRAIL_NAME=$(get_state "cloudtrail_name")
        
        log "Loaded configuration from state file"
    else
        # Fallback: discover resources
        log_warning "Discovering resources without state file..."
        discover_resources
    fi
    
    # Set defaults if still empty
    AWS_REGION="${AWS_REGION:-$(aws configure get region || echo 'us-east-1')}"
    AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
    
    log "Using AWS Region: ${AWS_REGION}"
    log "Using AWS Account: ${AWS_ACCOUNT_ID}"
}

discover_resources() {
    log "Discovering existing resources..."
    
    # Find SSO instance
    if [[ -z "${SSO_INSTANCE_ARN:-}" ]]; then
        SSO_INSTANCE_ARN=$(aws sso-admin list-instances \
            --query 'Instances[0].InstanceArn' --output text 2>/dev/null || echo "")
    fi
    
    # Find CloudTrail
    if [[ -z "${CLOUDTRAIL_NAME:-}" ]]; then
        CLOUDTRAIL_NAME=$(aws cloudtrail describe-trails \
            --query 'trailList[?contains(Name, `identity-federation`)].Name' --output text 2>/dev/null || echo "")
    fi
    
    log "Resource discovery completed"
}

# =============================================================================
# Cleanup Functions
# =============================================================================

cleanup_account_assignments() {
    log "Removing account assignments..."
    
    if [[ -z "${SSO_INSTANCE_ARN}" ]]; then
        log_warning "SSO instance ARN not found, skipping account assignments cleanup"
        return 0
    fi
    
    # Get organization accounts
    local accounts
    accounts=$(aws organizations list-accounts \
        --query 'Accounts[?Status==`ACTIVE`].Id' --output text 2>/dev/null || echo "")
    
    if [[ -z "${accounts}" ]]; then
        log_warning "No organization accounts found or insufficient permissions"
        return 0
    fi
    
    # Remove account assignments for each permission set
    for permission_set_arn in "${DEV_PERMISSION_SET_ARN}" "${ADMIN_PERMISSION_SET_ARN}" "${READONLY_PERMISSION_SET_ARN}"; do
        if [[ -n "${permission_set_arn}" ]]; then
            for account_id in ${accounts}; do
                # List and delete account assignments
                local assignments
                assignments=$(aws sso-admin list-account-assignments \
                    --instance-arn "${SSO_INSTANCE_ARN}" \
                    --account-id "${account_id}" \
                    --permission-set-arn "${permission_set_arn}" \
                    --query 'AccountAssignments[].{PrincipalType:PrincipalType,PrincipalId:PrincipalId}' \
                    --output text 2>/dev/null || echo "")
                
                if [[ -n "${assignments}" ]]; then
                    while read -r principal_type principal_id; do
                        if [[ -n "${principal_type}" && -n "${principal_id}" ]]; then
                            aws sso-admin delete-account-assignment \
                                --instance-arn "${SSO_INSTANCE_ARN}" \
                                --target-id "${account_id}" \
                                --target-type "AWS_ACCOUNT" \
                                --permission-set-arn "${permission_set_arn}" \
                                --principal-type "${principal_type}" \
                                --principal-id "${principal_id}" >/dev/null 2>&1 || \
                                log_warning "Failed to delete assignment for ${principal_id} in ${account_id}"
                        fi
                    done <<< "${assignments}"
                fi
            done
        fi
    done
    
    log_success "Account assignments cleanup completed"
}

cleanup_application_integrations() {
    log "Removing application integrations..."
    
    if [[ -z "${SSO_INSTANCE_ARN}" ]]; then
        log_warning "SSO instance ARN not found, skipping application cleanup"
        return 0
    fi
    
    # List and delete applications
    local applications
    applications=$(aws sso-admin list-applications \
        --instance-arn "${SSO_INSTANCE_ARN}" \
        --query 'Applications[].ApplicationArn' --output text 2>/dev/null || echo "")
    
    for app_arn in ${applications}; do
        if [[ -n "${app_arn}" ]]; then
            # Delete application assignments first
            local app_assignments
            app_assignments=$(aws sso-admin list-application-assignments \
                --instance-arn "${SSO_INSTANCE_ARN}" \
                --application-arn "${app_arn}" \
                --query 'ApplicationAssignments[].{PrincipalType:PrincipalType,PrincipalId:PrincipalId}' \
                --output text 2>/dev/null || echo "")
            
            while read -r principal_type principal_id; do
                if [[ -n "${principal_type}" && -n "${principal_id}" ]]; then
                    aws sso-admin delete-application-assignment \
                        --instance-arn "${SSO_INSTANCE_ARN}" \
                        --application-arn "${app_arn}" \
                        --principal-type "${principal_type}" \
                        --principal-id "${principal_id}" >/dev/null 2>&1 || \
                        log_warning "Failed to delete application assignment"
                fi
            done <<< "${app_assignments}"
            
            # Delete the application
            aws sso-admin delete-application \
                --instance-arn "${SSO_INSTANCE_ARN}" \
                --application-arn "${app_arn}" >/dev/null 2>&1 || \
                log_warning "Failed to delete application ${app_arn}"
        fi
    done
    
    log_success "Application integrations cleanup completed"
}

cleanup_permission_sets() {
    log "Removing permission sets..."
    
    if [[ -z "${SSO_INSTANCE_ARN}" ]]; then
        log_warning "SSO instance ARN not found, skipping permission sets cleanup"
        return 0
    fi
    
    # Get all permission sets
    local permission_sets
    permission_sets=$(aws sso-admin list-permission-sets \
        --instance-arn "${SSO_INSTANCE_ARN}" \
        --query 'PermissionSets' --output text 2>/dev/null || echo "")
    
    for permission_set_arn in ${permission_sets}; do
        if [[ -n "${permission_set_arn}" ]]; then
            log "Cleaning up permission set: ${permission_set_arn}"
            
            # Detach managed policies
            local managed_policies
            managed_policies=$(aws sso-admin list-managed-policies-in-permission-set \
                --instance-arn "${SSO_INSTANCE_ARN}" \
                --permission-set-arn "${permission_set_arn}" \
                --query 'AttachedManagedPolicies[].Arn' --output text 2>/dev/null || echo "")
            
            for policy_arn in ${managed_policies}; do
                aws sso-admin detach-managed-policy-from-permission-set \
                    --instance-arn "${SSO_INSTANCE_ARN}" \
                    --permission-set-arn "${permission_set_arn}" \
                    --managed-policy-arn "${policy_arn}" >/dev/null 2>&1 || \
                    log_warning "Failed to detach managed policy ${policy_arn}"
            done
            
            # Delete inline policies
            aws sso-admin delete-inline-policy-from-permission-set \
                --instance-arn "${SSO_INSTANCE_ARN}" \
                --permission-set-arn "${permission_set_arn}" >/dev/null 2>&1 || \
                log_warning "No inline policy to delete or deletion failed"
            
            # Delete the permission set
            aws sso-admin delete-permission-set \
                --instance-arn "${SSO_INSTANCE_ARN}" \
                --permission-set-arn "${permission_set_arn}" >/dev/null 2>&1 || \
                log_warning "Failed to delete permission set ${permission_set_arn}"
        fi
    done
    
    log_success "Permission sets cleanup completed"
}

cleanup_identity_provider() {
    log "Removing external identity provider..."
    
    if [[ -z "${SSO_INSTANCE_ARN}" ]]; then
        log_warning "SSO instance ARN not found, skipping identity provider cleanup"
        return 0
    fi
    
    # Delete identity providers
    local identity_providers
    identity_providers=$(aws sso-admin list-identity-providers \
        --instance-arn "${SSO_INSTANCE_ARN}" \
        --query 'IdentityProviders[].IdentityProviderArn' --output text 2>/dev/null || echo "")
    
    for idp_arn in ${identity_providers}; do
        if [[ -n "${idp_arn}" ]]; then
            aws sso-admin delete-identity-provider \
                --instance-arn "${SSO_INSTANCE_ARN}" \
                --identity-provider-arn "${idp_arn}" >/dev/null 2>&1 || \
                log_warning "Failed to delete identity provider ${idp_arn}"
        fi
    done
    
    log_success "Identity provider cleanup completed"
}

cleanup_identity_center() {
    log "Removing IAM Identity Center instance..."
    
    if [[ -z "${SSO_INSTANCE_ARN}" ]]; then
        log_warning "SSO instance ARN not found, skipping Identity Center cleanup"
        return 0
    fi
    
    # Note: IAM Identity Center instances cannot be deleted via API
    # This is a safety feature to prevent accidental deletion
    log_warning "IAM Identity Center instances cannot be deleted programmatically"
    log_warning "To disable IAM Identity Center, go to the AWS Console:"
    log_warning "1. Navigate to IAM Identity Center"
    log_warning "2. Choose Settings"
    log_warning "3. Choose Delete Identity Center configuration"
    log_warning "This must be done manually for safety reasons"
    
    log_success "Identity Center cleanup instructions provided"
}

cleanup_cloudwatch_resources() {
    log "Removing CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    aws cloudwatch delete-dashboards \
        --dashboard-names "IdentityFederationDashboard" >/dev/null 2>&1 || \
        log_warning "Dashboard may not exist or deletion failed"
    
    # Delete CloudWatch alarms
    aws cloudwatch delete-alarms \
        --alarm-names "IdentityFederationHealthAlarm" >/dev/null 2>&1 || \
        log_warning "Alarm may not exist or deletion failed"
    
    # Delete CloudWatch log groups
    aws logs delete-log-group \
        --log-group-name "/aws/sso/audit-logs" >/dev/null 2>&1 || \
        log_warning "Log group may not exist or deletion failed"
    
    log_success "CloudWatch resources cleanup completed"
}

cleanup_cloudtrail() {
    log "Removing CloudTrail and associated resources..."
    
    # Delete CloudTrail
    if [[ -n "${CLOUDTRAIL_NAME}" ]]; then
        aws cloudtrail delete-trail \
            --name "${CLOUDTRAIL_NAME}" >/dev/null 2>&1 || \
            log_warning "CloudTrail may not exist or deletion failed"
        log "Deleted CloudTrail: ${CLOUDTRAIL_NAME}"
    fi
    
    # Delete S3 bucket and contents
    if [[ -n "${CLOUDTRAIL_BUCKET}" ]]; then
        # Empty the bucket first
        aws s3 rm "s3://${CLOUDTRAIL_BUCKET}" --recursive >/dev/null 2>&1 || \
            log_warning "Failed to empty S3 bucket or bucket doesn't exist"
        
        # Delete the bucket
        aws s3 rb "s3://${CLOUDTRAIL_BUCKET}" >/dev/null 2>&1 || \
            log_warning "Failed to delete S3 bucket or bucket doesn't exist"
        
        log "Deleted S3 bucket: ${CLOUDTRAIL_BUCKET}"
    fi
    
    log_success "CloudTrail cleanup completed"
}

cleanup_ssm_documents() {
    log "Removing SSM documents..."
    
    # Delete disaster recovery document
    aws ssm delete-document \
        --name "IdentityFederationDisasterRecovery" >/dev/null 2>&1 || \
        log_warning "SSM document may not exist or deletion failed"
    
    log_success "SSM documents cleanup completed"
}

cleanup_state_files() {
    log "Cleaning up state files..."
    
    # Remove state file
    if [[ -f "${STATE_FILE}" ]]; then
        rm -f "${STATE_FILE}"
        log "Removed state file: ${STATE_FILE}"
    fi
    
    # Clean up temporary files
    rm -f "${STATE_FILE}.tmp"
    
    log_success "State files cleanup completed"
}

# =============================================================================
# Main Cleanup Function
# =============================================================================

main() {
    log "Starting AWS Identity Federation with SSO cleanup..."
    log "Cleanup log: ${LOG_FILE}"
    
    # Initialize log file
    echo "AWS Identity Federation with SSO - Cleanup Log" > "${LOG_FILE}"
    echo "Started at: $(date)" >> "${LOG_FILE}"
    echo "=============================================" >> "${LOG_FILE}"
    
    # Safety checks
    check_prerequisites
    load_environment
    
    # Confirm destructive action
    confirm_action "This will permanently delete all Identity Federation resources. Are you sure?"
    
    # Run cleanup in dependency order
    log "Starting resource cleanup in dependency order..."
    
    cleanup_account_assignments
    cleanup_application_integrations
    cleanup_permission_sets
    cleanup_identity_provider
    cleanup_identity_center
    cleanup_cloudwatch_resources
    cleanup_cloudtrail
    cleanup_ssm_documents
    cleanup_state_files
    
    log_success "AWS Identity Federation with SSO cleanup completed successfully!"
    log ""
    log "Manual cleanup required:"
    log "1. Disable IAM Identity Center in the AWS Console if desired"
    log "2. Review any remaining IAM roles with 'AWSReservedSSO' prefix"
    log "3. Verify all resources have been removed in the AWS Console"
    log ""
    log "Cleanup completed at: $(date)"
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Handle command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--force] [--help]"
            echo ""
            echo "Options:"
            echo "  --force    Skip confirmation prompts (use with caution)"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Override confirm_action if force mode is enabled
if [[ "${FORCE_CLEANUP:-false}" == "true" ]]; then
    confirm_action() {
        log_warning "Force mode enabled, skipping confirmation for: $1"
    }
fi

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi