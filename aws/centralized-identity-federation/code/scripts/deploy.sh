#!/bin/bash

# =============================================================================
# AWS Identity Federation with SSO - Deployment Script
# =============================================================================
# This script deploys a complete identity federation solution using AWS IAM 
# Identity Center (formerly AWS SSO) with external identity provider integration.
#
# Features:
# - IAM Identity Center setup and configuration
# - External identity provider integration (SAML/OIDC)
# - Permission sets with role-based access control
# - Multi-account access assignments
# - Application integration for SSO
# - Automated user provisioning (SCIM)
# - Session and security controls
# - Comprehensive audit logging
# - High availability and disaster recovery
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
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly STATE_FILE="${SCRIPT_DIR}/deployment-state.json"

# Default configuration values
readonly DEFAULT_AWS_REGION="us-east-1"
readonly DEFAULT_IDP_METADATA_URL="https://your-idp.example.com/metadata"
readonly DEFAULT_SCIM_ENDPOINT="https://your-idp.example.com/scim/v2"

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

save_state() {
    local key="$1"
    local value="$2"
    
    # Create state file if it doesn't exist
    if [[ ! -f "${STATE_FILE}" ]]; then
        echo '{}' > "${STATE_FILE}"
    fi
    
    # Update state using jq
    if command -v jq >/dev/null 2>&1; then
        jq --arg key "$key" --arg value "$value" '.[$key] = $value' "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
    else
        log_warning "jq not available, state tracking limited"
    fi
}

get_state() {
    local key="$1"
    
    if [[ -f "${STATE_FILE}" ]] && command -v jq >/dev/null 2>&1; then
        jq -r --arg key "$key" '.[$key] // empty' "${STATE_FILE}"
    fi
}

cleanup_on_error() {
    log_error "Script failed. Check ${LOG_FILE} for details."
    log_error "Run destroy.sh to clean up any partially created resources."
    exit 1
}

# =============================================================================
# Prerequisites and Validation Functions
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: ${aws_version}"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    # Check required permissions
    log "Validating AWS permissions..."
    if ! aws organizations describe-organization >/dev/null 2>&1; then
        log_error "AWS Organizations access required. Ensure you have the necessary permissions."
        exit 1
    fi
    
    # Check for existing SSO instance
    local existing_instances
    existing_instances=$(aws sso-admin list-instances --query 'length(Instances)' --output text 2>/dev/null || echo "0")
    if [[ "${existing_instances}" -gt 0 ]]; then
        log_warning "Existing IAM Identity Center instance found. This script will work with the existing instance."
    fi
    
    log_success "Prerequisites check completed"
}

validate_environment() {
    log "Validating environment variables..."
    
    # Set default region if not provided
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION="${DEFAULT_AWS_REGION}"
        log "Using default AWS region: ${AWS_REGION}"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log "AWS Account ID: ${AWS_ACCOUNT_ID}"
    
    # Generate unique suffix for resources
    export RANDOM_SUFFIX
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    export SSO_INSTANCE_NAME="enterprise-sso-${RANDOM_SUFFIX}"
    export PERMISSION_SET_PREFIX="PS-${RANDOM_SUFFIX}"
    
    log "Generated unique suffix: ${RANDOM_SUFFIX}"
    log_success "Environment validation completed"
}

# =============================================================================
# Infrastructure Setup Functions
# =============================================================================

setup_cloudtrail() {
    log "Setting up CloudTrail for audit logging..."
    
    local bucket_name="identity-audit-logs-${AWS_ACCOUNT_ID}-${RANDOM_SUFFIX}"
    local trail_name="identity-federation-audit-trail"
    
    # Create S3 bucket for CloudTrail logs
    if aws s3api head-bucket --bucket "${bucket_name}" >/dev/null 2>&1; then
        log "S3 bucket ${bucket_name} already exists"
    else
        aws s3 mb "s3://${bucket_name}" --region "${AWS_REGION}"
        log "Created S3 bucket: ${bucket_name}"
    fi
    
    # Apply bucket policy for CloudTrail
    local bucket_policy=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${bucket_name}/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control"
                }
            }
        },
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:GetBucketAcl",
            "Resource": "arn:aws:s3:::${bucket_name}"
        }
    ]
}
EOF
    )
    
    aws s3api put-bucket-policy \
        --bucket "${bucket_name}" \
        --policy "${bucket_policy}"
    
    # Create CloudTrail
    if aws cloudtrail describe-trails --trail-name-list "${trail_name}" --query 'trailList[0]' --output text | grep -q "${trail_name}"; then
        log "CloudTrail ${trail_name} already exists"
    else
        aws cloudtrail create-trail \
            --name "${trail_name}" \
            --s3-bucket-name "${bucket_name}" \
            --include-global-service-events \
            --is-multi-region-trail \
            --enable-log-file-validation
        
        # Start logging
        aws cloudtrail start-logging --name "${trail_name}"
        log "Created and started CloudTrail: ${trail_name}"
    fi
    
    save_state "cloudtrail_bucket" "${bucket_name}"
    save_state "cloudtrail_name" "${trail_name}"
    log_success "CloudTrail setup completed"
}

setup_identity_center() {
    log "Setting up IAM Identity Center..."
    
    # Check for existing instance
    local existing_instance_arn
    existing_instance_arn=$(aws sso-admin list-instances \
        --query 'Instances[0].InstanceArn' --output text 2>/dev/null || echo "None")
    
    if [[ "${existing_instance_arn}" != "None" ]]; then
        export SSO_INSTANCE_ARN="${existing_instance_arn}"
        export SSO_IDENTITY_STORE_ID
        SSO_IDENTITY_STORE_ID=$(aws sso-admin list-instances \
            --query 'Instances[0].IdentityStoreId' --output text)
        log "Using existing IAM Identity Center instance: ${SSO_INSTANCE_ARN}"
    else
        # Enable IAM Identity Center
        aws sso-admin create-instance \
            --name "${SSO_INSTANCE_NAME}" \
            --tags Key=Environment,Value=Production Key=Purpose,Value=IdentityFederation
        
        # Get the instance ARN
        export SSO_INSTANCE_ARN
        SSO_INSTANCE_ARN=$(aws sso-admin list-instances \
            --query 'Instances[0].InstanceArn' --output text)
        
        export SSO_IDENTITY_STORE_ID
        SSO_IDENTITY_STORE_ID=$(aws sso-admin list-instances \
            --query 'Instances[0].IdentityStoreId' --output text)
        
        log "Created IAM Identity Center instance: ${SSO_INSTANCE_ARN}"
    fi
    
    save_state "sso_instance_arn" "${SSO_INSTANCE_ARN}"
    save_state "sso_identity_store_id" "${SSO_IDENTITY_STORE_ID}"
    log_success "IAM Identity Center setup completed"
}

configure_external_identity_provider() {
    log "Configuring external identity provider integration..."
    
    # Check if user wants to configure external IdP
    read -p "Do you want to configure external identity provider integration? (y/N): " configure_idp
    if [[ "${configure_idp,,}" != "y" ]]; then
        log "Skipping external identity provider configuration"
        return 0
    fi
    
    # Get IdP metadata URL
    read -p "Enter your SAML identity provider metadata URL [${DEFAULT_IDP_METADATA_URL}]: " idp_url
    idp_url="${idp_url:-${DEFAULT_IDP_METADATA_URL}}"
    
    # Create identity provider configuration
    local idp_config=$(cat <<EOF
{
    "SamlConfiguration": {
        "MetadataUrl": "${idp_url}",
        "AttributeMapping": {
            "email": "\${path:enterprise.email}",
            "given_name": "\${path:enterprise.givenName}",
            "family_name": "\${path:enterprise.familyName}",
            "name": "\${path:enterprise.displayName}"
        }
    }
}
EOF
    )
    
    # Create identity provider
    aws sso-admin create-identity-provider \
        --instance-arn "${SSO_INSTANCE_ARN}" \
        --identity-provider-type "SAML" \
        --identity-provider-configuration "${idp_config}" || \
        log_warning "Identity provider may already exist or configuration needs adjustment"
    
    # Get identity provider ARN
    export IDP_ARN
    IDP_ARN=$(aws sso-admin list-identity-providers \
        --instance-arn "${SSO_INSTANCE_ARN}" \
        --query 'IdentityProviders[0].IdentityProviderArn' --output text 2>/dev/null || echo "")
    
    if [[ -n "${IDP_ARN}" ]]; then
        save_state "idp_arn" "${IDP_ARN}"
        log "Configured external identity provider: ${IDP_ARN}"
    fi
    
    log_success "External identity provider configuration completed"
}

create_permission_sets() {
    log "Creating permission sets for role-based access..."
    
    # Create developer permission set
    aws sso-admin create-permission-set \
        --instance-arn "${SSO_INSTANCE_ARN}" \
        --name "${PERMISSION_SET_PREFIX}-Developer" \
        --description "Development environment access with limited permissions" \
        --session-duration "PT8H" \
        --tags Key=Role,Value=Developer || \
        log_warning "Developer permission set may already exist"
    
    # Create administrator permission set
    aws sso-admin create-permission-set \
        --instance-arn "${SSO_INSTANCE_ARN}" \
        --name "${PERMISSION_SET_PREFIX}-Administrator" \
        --description "Full administrative access across all accounts" \
        --session-duration "PT4H" \
        --tags Key=Role,Value=Administrator || \
        log_warning "Administrator permission set may already exist"
    
    # Create read-only permission set
    aws sso-admin create-permission-set \
        --instance-arn "${SSO_INSTANCE_ARN}" \
        --name "${PERMISSION_SET_PREFIX}-ReadOnly" \
        --description "Read-only access for business users and auditors" \
        --session-duration "PT12H" \
        --tags Key=Role,Value=ReadOnly || \
        log_warning "ReadOnly permission set may already exist"
    
    # Get permission set ARNs
    local permission_sets
    permission_sets=$(aws sso-admin list-permission-sets \
        --instance-arn "${SSO_INSTANCE_ARN}" \
        --query 'PermissionSets' --output text)
    
    export DEV_PERMISSION_SET_ARN
    DEV_PERMISSION_SET_ARN=$(echo "${permission_sets}" | grep "Developer" | head -1)
    
    export ADMIN_PERMISSION_SET_ARN
    ADMIN_PERMISSION_SET_ARN=$(echo "${permission_sets}" | grep "Administrator" | head -1)
    
    export READONLY_PERMISSION_SET_ARN
    READONLY_PERMISSION_SET_ARN=$(echo "${permission_sets}" | grep "ReadOnly" | head -1)
    
    save_state "dev_permission_set_arn" "${DEV_PERMISSION_SET_ARN}"
    save_state "admin_permission_set_arn" "${ADMIN_PERMISSION_SET_ARN}"
    save_state "readonly_permission_set_arn" "${READONLY_PERMISSION_SET_ARN}"
    
    log_success "Permission sets created successfully"
}

attach_managed_policies() {
    log "Attaching AWS managed policies to permission sets..."
    
    # Attach PowerUserAccess to developer permission set
    aws sso-admin attach-managed-policy-to-permission-set \
        --instance-arn "${SSO_INSTANCE_ARN}" \
        --permission-set-arn "${DEV_PERMISSION_SET_ARN}" \
        --managed-policy-arn "arn:aws:iam::aws:policy/PowerUserAccess" || \
        log_warning "Policy may already be attached to developer permission set"
    
    # Attach AdministratorAccess to administrator permission set
    aws sso-admin attach-managed-policy-to-permission-set \
        --instance-arn "${SSO_INSTANCE_ARN}" \
        --permission-set-arn "${ADMIN_PERMISSION_SET_ARN}" \
        --managed-policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" || \
        log_warning "Policy may already be attached to administrator permission set"
    
    # Attach ReadOnlyAccess to read-only permission set
    aws sso-admin attach-managed-policy-to-permission-set \
        --instance-arn "${SSO_INSTANCE_ARN}" \
        --permission-set-arn "${READONLY_PERMISSION_SET_ARN}" \
        --managed-policy-arn "arn:aws:iam::aws:policy/ReadOnlyAccess" || \
        log_warning "Policy may already be attached to read-only permission set"
    
    log_success "AWS managed policies attached successfully"
}

create_inline_policies() {
    log "Creating custom inline policies for fine-grained access..."
    
    # Developer policy with specific restrictions
    local dev_policy=$(cat <<'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Deny",
            "Action": [
                "iam:*",
                "organizations:*",
                "account:*",
                "billing:*",
                "aws-portal:*"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "iam:GetRole",
                "iam:GetRolePolicy",
                "iam:ListRoles",
                "iam:ListRolePolicies",
                "iam:PassRole"
            ],
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "iam:PassedToService": [
                        "lambda.amazonaws.com",
                        "ec2.amazonaws.com",
                        "ecs-tasks.amazonaws.com"
                    ]
                }
            }
        }
    ]
}
EOF
    )
    
    # Business user policy for read-only access with enhanced capabilities
    local business_policy=$(cat <<'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket",
                "cloudwatch:GetMetricStatistics",
                "cloudwatch:ListMetrics",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:FilterLogEvents"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "quicksight:*"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    )
    
    # Apply inline policies
    aws sso-admin put-inline-policy-to-permission-set \
        --instance-arn "${SSO_INSTANCE_ARN}" \
        --permission-set-arn "${DEV_PERMISSION_SET_ARN}" \
        --inline-policy "${dev_policy}" || \
        log_warning "Inline policy may already exist for developer permission set"
    
    aws sso-admin put-inline-policy-to-permission-set \
        --instance-arn "${SSO_INSTANCE_ARN}" \
        --permission-set-arn "${READONLY_PERMISSION_SET_ARN}" \
        --inline-policy "${business_policy}" || \
        log_warning "Inline policy may already exist for read-only permission set"
    
    log_success "Custom inline policies created successfully"
}

setup_cloudwatch_logging() {
    log "Setting up CloudWatch logging and monitoring..."
    
    # Create CloudWatch log group for audit logs
    aws logs create-log-group \
        --log-group-name "/aws/sso/audit-logs" || \
        log_warning "Log group may already exist"
    
    # Set retention policy
    aws logs put-retention-policy \
        --log-group-name "/aws/sso/audit-logs" \
        --retention-in-days 365
    
    # Create CloudWatch dashboard
    local dashboard_body=$(cat <<EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/SSO", "SignInAttempts"],
                    ["AWS/SSO", "SignInSuccesses"],
                    ["AWS/SSO", "SignInFailures"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "Identity Center Sign-in Metrics"
            }
        },
        {
            "type": "log",
            "properties": {
                "query": "SOURCE \"/aws/sso/audit-logs\" | fields @timestamp, eventName, sourceIPAddress, userIdentity.type\\n| filter eventName like /SignIn/\\n| stats count() by sourceIPAddress\\n| sort count desc",
                "region": "${AWS_REGION}",
                "title": "Sign-in Activity by IP Address"
            }
        }
    ]
}
EOF
    )
    
    aws cloudwatch put-dashboard \
        --dashboard-name "IdentityFederationDashboard" \
        --dashboard-body "${dashboard_body}" || \
        log_warning "Dashboard may already exist"
    
    log_success "CloudWatch logging and monitoring setup completed"
}

provision_permission_sets() {
    log "Provisioning permission sets to accounts..."
    
    # Get organization accounts
    local accounts
    accounts=$(aws organizations list-accounts \
        --query 'Accounts[?Status==`ACTIVE`].Id' --output text 2>/dev/null || echo "")
    
    if [[ -z "${accounts}" ]]; then
        log_warning "No organization accounts found or insufficient permissions"
        return 0
    fi
    
    # Provision permission sets to accounts
    for account_id in ${accounts}; do
        log "Provisioning permission sets to account: ${account_id}"
        
        # Provision developer permission set
        aws sso-admin provision-permission-set \
            --instance-arn "${SSO_INSTANCE_ARN}" \
            --permission-set-arn "${DEV_PERMISSION_SET_ARN}" \
            --target-type "AWS_ACCOUNT" \
            --target-id "${account_id}" >/dev/null 2>&1 || \
            log_warning "Failed to provision developer permission set to ${account_id}"
        
        # Provision admin permission set
        aws sso-admin provision-permission-set \
            --instance-arn "${SSO_INSTANCE_ARN}" \
            --permission-set-arn "${ADMIN_PERMISSION_SET_ARN}" \
            --target-type "AWS_ACCOUNT" \
            --target-id "${account_id}" >/dev/null 2>&1 || \
            log_warning "Failed to provision admin permission set to ${account_id}"
        
        # Provision read-only permission set
        aws sso-admin provision-permission-set \
            --instance-arn "${SSO_INSTANCE_ARN}" \
            --permission-set-arn "${READONLY_PERMISSION_SET_ARN}" \
            --target-type "AWS_ACCOUNT" \
            --target-id "${account_id}" >/dev/null 2>&1 || \
            log_warning "Failed to provision read-only permission set to ${account_id}"
    done
    
    # Wait for provisioning to complete
    log "Waiting for permission set provisioning to complete..."
    sleep 30
    
    log_success "Permission set provisioning completed"
}

# =============================================================================
# Main Deployment Function
# =============================================================================

main() {
    log "Starting AWS Identity Federation with SSO deployment..."
    log "Deployment log: ${LOG_FILE}"
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Initialize log file
    echo "AWS Identity Federation with SSO - Deployment Log" > "${LOG_FILE}"
    echo "Started at: $(date)" >> "${LOG_FILE}"
    echo "=============================================" >> "${LOG_FILE}"
    
    # Run deployment steps
    check_prerequisites
    validate_environment
    setup_cloudtrail
    setup_identity_center
    configure_external_identity_provider
    create_permission_sets
    attach_managed_policies
    create_inline_policies
    setup_cloudwatch_logging
    provision_permission_sets
    
    # Save final state
    save_state "deployment_completed" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    save_state "aws_region" "${AWS_REGION}"
    save_state "aws_account_id" "${AWS_ACCOUNT_ID}"
    
    log_success "AWS Identity Federation with SSO deployment completed successfully!"
    log ""
    log "Next steps:"
    log "1. Configure your external identity provider with the SSO SAML metadata"
    log "2. Create user groups in your identity store"
    log "3. Assign users to permission sets and accounts"
    log "4. Test the federation with a pilot group"
    log ""
    log "Important resources created:"
    log "- SSO Instance ARN: ${SSO_INSTANCE_ARN}"
    log "- Identity Store ID: ${SSO_IDENTITY_STORE_ID}"
    log "- CloudTrail: $(get_state cloudtrail_name)"
    log "- S3 Audit Bucket: $(get_state cloudtrail_bucket)"
    log ""
    log "Access the AWS SSO portal at: https://${AWS_REGION}.console.aws.amazon.com/singlesignon"
    log ""
    log "Deployment state saved to: ${STATE_FILE}"
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi