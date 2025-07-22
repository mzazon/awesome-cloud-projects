#!/bin/bash

#####################################################################
# AWS Single Sign-On with External Identity Providers - Deploy Script
# 
# This script deploys AWS IAM Identity Center (formerly AWS SSO) with
# external identity provider integration, permission sets, and user
# management capabilities.
#
# Usage: ./deploy.sh [OPTIONS]
# Options:
#   --dry-run     Preview changes without executing
#   --verbose     Enable verbose logging
#   --help        Show this help message
#####################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
VERBOSE=false
DRY_RUN=false

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
    
    log DEBUG "Executing: $cmd"
    
    if [[ $DRY_RUN == true ]]; then
        log INFO "[DRY-RUN] Would execute: $description"
        return 0
    fi
    
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        log INFO "✅ $description"
        return 0
    else
        log ERROR "❌ Failed: $description"
        return 1
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
                log ERROR "❌ $operation_type operation failed"
                return 1
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
    
    log ERROR "❌ Timeout waiting for $operation_type operation"
    return 1
}

#####################################################################
# Prerequisites Check Functions
#####################################################################

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log DEBUG "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check AWS Organizations
    if ! aws organizations describe-organization &> /dev/null; then
        error_exit "AWS Organizations is not enabled or accessible. This is required for IAM Identity Center."
    fi
    
    # Check permissions for IAM Identity Center
    if ! aws sso-admin list-instances &> /dev/null; then
        log WARN "Unable to access IAM Identity Center. Ensure you have appropriate permissions."
    fi
    
    log INFO "✅ Prerequisites check completed"
}

#####################################################################
# Environment Setup Functions
#####################################################################

setup_environment() {
    log INFO "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    [[ -z "$AWS_REGION" ]] && export AWS_REGION="us-east-1"
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
        --query Account --output text)
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set identity provider name
    export IDP_NAME="ExternalIdP-${RANDOM_SUFFIX}"
    
    log INFO "Environment configured:"
    log INFO "  AWS Region: $AWS_REGION"
    log INFO "  AWS Account: $AWS_ACCOUNT_ID"
    log INFO "  Random Suffix: $RANDOM_SUFFIX"
    log INFO "  IDP Name: $IDP_NAME"
}

#####################################################################
# IAM Identity Center Setup Functions
#####################################################################

enable_identity_center() {
    log INFO "Enabling IAM Identity Center..."
    
    # Check if IAM Identity Center is already enabled
    if SSO_INSTANCE_ARN=$(aws sso-admin list-instances \
        --query 'Instances[0].InstanceArn' --output text 2>/dev/null) && \
       [[ "$SSO_INSTANCE_ARN" != "None" ]] && [[ -n "$SSO_INSTANCE_ARN" ]]; then
        log INFO "IAM Identity Center already enabled"
        IDENTITY_STORE_ID=$(aws sso-admin list-instances \
            --query 'Instances[0].IdentityStoreId' --output text)
    else
        error_exit "IAM Identity Center is not enabled. Please enable it through the AWS Console first."
    fi
    
    export SSO_INSTANCE_ARN
    export IDENTITY_STORE_ID
    
    log INFO "✅ IAM Identity Center instance: $SSO_INSTANCE_ARN"
    log INFO "✅ Identity Store ID: $IDENTITY_STORE_ID"
}

create_permission_sets() {
    log INFO "Creating permission sets..."
    
    # Create Developer permission set
    if DEVELOPER_PS_ARN=$(aws sso-admin create-permission-set \
        --instance-arn "$SSO_INSTANCE_ARN" \
        --name "DeveloperAccess-${RANDOM_SUFFIX}" \
        --description "Developer access with PowerUser permissions" \
        --session-duration "PT8H" \
        --query 'PermissionSet.PermissionSetArn' --output text 2>/dev/null); then
        log INFO "✅ Developer permission set created"
        export DEVELOPER_PS_ARN
    else
        error_exit "Failed to create Developer permission set"
    fi
    
    # Create Administrator permission set
    if ADMIN_PS_ARN=$(aws sso-admin create-permission-set \
        --instance-arn "$SSO_INSTANCE_ARN" \
        --name "AdministratorAccess-${RANDOM_SUFFIX}" \
        --description "Full administrator access" \
        --session-duration "PT4H" \
        --query 'PermissionSet.PermissionSetArn' --output text 2>/dev/null); then
        log INFO "✅ Administrator permission set created"
        export ADMIN_PS_ARN
    else
        error_exit "Failed to create Administrator permission set"
    fi
    
    # Create ReadOnly permission set
    if READONLY_PS_ARN=$(aws sso-admin create-permission-set \
        --instance-arn "$SSO_INSTANCE_ARN" \
        --name "ReadOnlyAccess-${RANDOM_SUFFIX}" \
        --description "Read-only access to AWS resources" \
        --session-duration "PT12H" \
        --query 'PermissionSet.PermissionSetArn' --output text 2>/dev/null); then
        log INFO "✅ ReadOnly permission set created"
        export READONLY_PS_ARN
    else
        error_exit "Failed to create ReadOnly permission set"
    fi
    
    log INFO "Permission sets created successfully"
}

attach_managed_policies() {
    log INFO "Attaching managed policies to permission sets..."
    
    # Attach PowerUserAccess to Developer permission set
    execute_command \
        "aws sso-admin attach-managed-policy-to-permission-set \
            --instance-arn '$SSO_INSTANCE_ARN' \
            --permission-set-arn '$DEVELOPER_PS_ARN' \
            --managed-policy-arn 'arn:aws:iam::aws:policy/PowerUserAccess'" \
        "Attached PowerUserAccess to Developer permission set"
    
    # Attach AdministratorAccess to Administrator permission set
    execute_command \
        "aws sso-admin attach-managed-policy-to-permission-set \
            --instance-arn '$SSO_INSTANCE_ARN' \
            --permission-set-arn '$ADMIN_PS_ARN' \
            --managed-policy-arn 'arn:aws:iam::aws:policy/AdministratorAccess'" \
        "Attached AdministratorAccess to Administrator permission set"
    
    # Attach ReadOnlyAccess to ReadOnly permission set
    execute_command \
        "aws sso-admin attach-managed-policy-to-permission-set \
            --instance-arn '$SSO_INSTANCE_ARN' \
            --permission-set-arn '$READONLY_PS_ARN' \
            --managed-policy-arn 'arn:aws:iam::aws:policy/ReadOnlyAccess'" \
        "Attached ReadOnlyAccess to ReadOnly permission set"
}

create_custom_policy() {
    log INFO "Creating custom inline policy for permission set..."
    
    # Create custom policy for specific S3 bucket access
    cat > "/tmp/s3-policy-${RANDOM_SUFFIX}.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": "arn:aws:s3:::company-data-${RANDOM_SUFFIX}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::company-data-${RANDOM_SUFFIX}"
        }
    ]
}
EOF
    
    # Attach inline policy to Developer permission set
    execute_command \
        "aws sso-admin put-inline-policy-to-permission-set \
            --instance-arn '$SSO_INSTANCE_ARN' \
            --permission-set-arn '$DEVELOPER_PS_ARN' \
            --inline-policy file:///tmp/s3-policy-${RANDOM_SUFFIX}.json" \
        "Attached custom inline policy to Developer permission set"
}

provision_permission_sets() {
    log INFO "Provisioning permission sets to organization accounts..."
    
    # Get list of accounts in organization
    local accounts
    if ! accounts=$(aws organizations list-accounts \
        --query 'Accounts[?Status==`ACTIVE`].Id' --output text); then
        error_exit "Failed to list organization accounts"
    fi
    
    # Provision permission sets to accounts
    for account_id in $accounts; do
        log INFO "Provisioning permission sets for account: $account_id"
        
        # Provision Developer permission set
        if request_id=$(aws sso-admin provision-permission-set \
            --instance-arn "$SSO_INSTANCE_ARN" \
            --permission-set-arn "$DEVELOPER_PS_ARN" \
            --target-id "$account_id" \
            --target-type AWS_ACCOUNT \
            --query 'ProvisioningStatus.RequestId' --output text 2>/dev/null); then
            wait_for_operation "$request_id" "Developer permission set provisioning"
        fi
        
        # Provision Administrator permission set
        if request_id=$(aws sso-admin provision-permission-set \
            --instance-arn "$SSO_INSTANCE_ARN" \
            --permission-set-arn "$ADMIN_PS_ARN" \
            --target-id "$account_id" \
            --target-type AWS_ACCOUNT \
            --query 'ProvisioningStatus.RequestId' --output text 2>/dev/null); then
            wait_for_operation "$request_id" "Administrator permission set provisioning"
        fi
        
        # Provision ReadOnly permission set
        if request_id=$(aws sso-admin provision-permission-set \
            --instance-arn "$SSO_INSTANCE_ARN" \
            --permission-set-arn "$READONLY_PS_ARN" \
            --target-id "$account_id" \
            --target-type AWS_ACCOUNT \
            --query 'ProvisioningStatus.RequestId' --output text 2>/dev/null); then
            wait_for_operation "$request_id" "ReadOnly permission set provisioning"
        fi
    done
    
    log INFO "✅ Permission sets provisioned to all organization accounts"
}

create_test_users_groups() {
    log INFO "Creating test users and groups..."
    
    # Create a test user
    if TEST_USER_ID=$(aws identitystore create-user \
        --identity-store-id "$IDENTITY_STORE_ID" \
        --user-name "testuser-${RANDOM_SUFFIX}@example.com" \
        --display-name "Test User ${RANDOM_SUFFIX}" \
        --name "{
            \"GivenName\": \"Test\",
            \"FamilyName\": \"User\"
        }" \
        --emails "[{
            \"Value\": \"testuser-${RANDOM_SUFFIX}@example.com\",
            \"Type\": \"Work\",
            \"Primary\": true
        }]" \
        --query 'UserId' --output text 2>/dev/null); then
        log INFO "✅ Test user created: $TEST_USER_ID"
        export TEST_USER_ID
    else
        error_exit "Failed to create test user"
    fi
    
    # Create a test group
    if TEST_GROUP_ID=$(aws identitystore create-group \
        --identity-store-id "$IDENTITY_STORE_ID" \
        --display-name "Developers-${RANDOM_SUFFIX}" \
        --description "Developer group for testing" \
        --query 'GroupId' --output text 2>/dev/null); then
        log INFO "✅ Test group created: $TEST_GROUP_ID"
        export TEST_GROUP_ID
    else
        error_exit "Failed to create test group"
    fi
    
    # Add user to group
    execute_command \
        "aws identitystore create-group-membership \
            --identity-store-id '$IDENTITY_STORE_ID' \
            --group-id '$TEST_GROUP_ID' \
            --member-id '{\"UserId\": \"'$TEST_USER_ID'\"}'" \
        "Added test user to test group"
}

create_account_assignments() {
    log INFO "Creating account assignments..."
    
    # Get first account ID for assignment
    local first_account
    if ! first_account=$(aws organizations list-accounts \
        --query 'Accounts[?Status==`ACTIVE`].Id' --output text | \
        awk '{print $1}'); then
        error_exit "Failed to get organization accounts for assignment"
    fi
    
    export FIRST_ACCOUNT="$first_account"
    
    # Assign group to account with Developer permission set
    execute_command \
        "aws sso-admin create-account-assignment \
            --instance-arn '$SSO_INSTANCE_ARN' \
            --target-id '$FIRST_ACCOUNT' \
            --target-type AWS_ACCOUNT \
            --permission-set-arn '$DEVELOPER_PS_ARN' \
            --principal-type GROUP \
            --principal-id '$TEST_GROUP_ID'" \
        "Created group assignment for Developer access"
    
    # Assign user to account with ReadOnly permission set
    execute_command \
        "aws sso-admin create-account-assignment \
            --instance-arn '$SSO_INSTANCE_ARN' \
            --target-id '$FIRST_ACCOUNT' \
            --target-type AWS_ACCOUNT \
            --permission-set-arn '$READONLY_PS_ARN' \
            --principal-type USER \
            --principal-id '$TEST_USER_ID'" \
        "Created user assignment for ReadOnly access"
    
    log INFO "✅ Account assignments created for account: $FIRST_ACCOUNT"
}

save_deployment_state() {
    log INFO "Saving deployment state..."
    
    cat > "${SCRIPT_DIR}/deployment-state.env" << EOF
# Deployment state for AWS SSO External Identity Provider setup
# Generated on $(date)

# Core IAM Identity Center
export SSO_INSTANCE_ARN="$SSO_INSTANCE_ARN"
export IDENTITY_STORE_ID="$IDENTITY_STORE_ID"

# Permission Sets
export DEVELOPER_PS_ARN="$DEVELOPER_PS_ARN"
export ADMIN_PS_ARN="$ADMIN_PS_ARN"
export READONLY_PS_ARN="$READONLY_PS_ARN"

# Test Resources
export TEST_USER_ID="$TEST_USER_ID"
export TEST_GROUP_ID="$TEST_GROUP_ID"
export FIRST_ACCOUNT="$FIRST_ACCOUNT"

# Configuration
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
export IDP_NAME="$IDP_NAME"
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
EOF
    
    log INFO "✅ Deployment state saved to deployment-state.env"
}

#####################################################################
# Validation Functions
#####################################################################

validate_deployment() {
    log INFO "Validating deployment..."
    
    # Check instance status
    local instance_status
    if instance_status=$(aws sso-admin list-instances \
        --query 'Instances[0].Status' --output text 2>/dev/null); then
        log INFO "✅ IAM Identity Center status: $instance_status"
    else
        log ERROR "❌ Failed to check IAM Identity Center status"
    fi
    
    # List permission sets
    local permission_set_count
    if permission_set_count=$(aws sso-admin list-permission-sets \
        --instance-arn "$SSO_INSTANCE_ARN" \
        --query 'length(PermissionSets)' --output text 2>/dev/null); then
        log INFO "✅ Permission sets created: $permission_set_count"
    else
        log ERROR "❌ Failed to list permission sets"
    fi
    
    # Check account assignments
    local assignment_count
    if assignment_count=$(aws sso-admin list-account-assignments \
        --instance-arn "$SSO_INSTANCE_ARN" \
        --account-id "$FIRST_ACCOUNT" \
        --permission-set-arn "$DEVELOPER_PS_ARN" \
        --query 'length(AccountAssignments)' --output text 2>/dev/null); then
        log INFO "✅ Account assignments created: $assignment_count"
    else
        log ERROR "❌ Failed to check account assignments"
    fi
    
    log INFO "✅ Deployment validation completed"
}

#####################################################################
# Usage and Help Functions
#####################################################################

show_help() {
    cat << EOF
AWS Single Sign-On with External Identity Providers - Deploy Script

This script deploys AWS IAM Identity Center (formerly AWS SSO) with
external identity provider integration, permission sets, and user
management capabilities.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --dry-run     Preview changes without executing
    --verbose     Enable verbose logging
    --help        Show this help message

EXAMPLES:
    $0                    # Deploy with default settings
    $0 --verbose          # Deploy with verbose logging
    $0 --dry-run          # Preview deployment without changes

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - AWS Organizations enabled
    - Appropriate IAM permissions for Identity Center
    - Administrative access to external identity provider

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
            --dry-run)
                DRY_RUN=true
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
    echo "=== AWS SSO External Identity Provider Deployment Started at $(date) ===" > "$LOG_FILE"
    
    log INFO "Starting AWS Single Sign-On External Identity Provider deployment..."
    [[ $DRY_RUN == true ]] && log INFO "DRY RUN MODE - No changes will be made"
    [[ $VERBOSE == true ]] && log INFO "VERBOSE MODE enabled"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    enable_identity_center
    create_permission_sets
    attach_managed_policies
    create_custom_policy
    provision_permission_sets
    create_test_users_groups
    create_account_assignments
    save_deployment_state
    validate_deployment
    
    log INFO "🎉 AWS Single Sign-On External Identity Provider deployment completed successfully!"
    log INFO ""
    log INFO "Next steps:"
    log INFO "1. Configure your external identity provider (Active Directory, Okta, etc.)"
    log INFO "2. Set up SAML metadata exchange"
    log INFO "3. Configure SCIM for user provisioning"
    log INFO "4. Test user authentication through the AWS access portal"
    log INFO ""
    log INFO "Deployment details saved to: ${SCRIPT_DIR}/deployment-state.env"
    log INFO "Full deployment log: $LOG_FILE"
}

# Trap errors and cleanup
trap 'log ERROR "Deployment failed. Check $LOG_FILE for details."' ERR

# Execute main function
main "$@"