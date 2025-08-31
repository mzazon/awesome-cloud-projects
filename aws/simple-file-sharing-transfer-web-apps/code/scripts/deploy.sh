#!/bin/bash

# =============================================================================
# AWS Transfer Family Web Apps - Simple File Sharing Deployment Script
# =============================================================================
# This script deploys a complete file sharing solution using AWS Transfer Family
# Web Apps, S3, IAM Identity Center, and S3 Access Grants.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - IAM Identity Center enabled in your AWS account
# - Appropriate AWS permissions for Transfer Family, S3, and IAM operations
#
# Usage: ./deploy.sh [--dry-run] [--verbose] [--help]
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Script configuration
readonly SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
readonly LOG_FILE="/tmp/transfer-family-deploy-$(date +%Y%m%d_%H%M%S).log"

# Default configuration
DRY_RUN=false
VERBOSE=false
FORCE_CLEANUP=false

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="${1}"
    shift
    local message="${*}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() {
    log "INFO" "${@}"
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${BLUE}ℹ ${*}${NC}"
    fi
}

success() {
    log "SUCCESS" "${@}"
    echo -e "${GREEN}✅ ${*}${NC}"
}

warn() {
    log "WARN" "${@}"
    echo -e "${YELLOW}⚠️  ${*}${NC}"
}

error() {
    log "ERROR" "${@}"
    echo -e "${RED}❌ ${*}${NC}" >&2
}

fatal() {
    error "${@}"
    echo -e "${RED}💥 Deployment failed. Check log file: ${LOG_FILE}${NC}" >&2
    exit 1
}

cleanup_on_error() {
    warn "Deployment failed. Starting cleanup of partially created resources..."
    if [[ "${FORCE_CLEANUP}" == "true" ]]; then
        run_cleanup
    else
        warn "Run './destroy.sh --force' to clean up partial deployment"
    fi
}

# Trap to handle errors and cleanup
trap cleanup_on_error ERR

# =============================================================================
# Validation Functions
# =============================================================================

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        fatal "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: ${aws_version}"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        fatal "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check required tools
    local required_tools=("jq" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" &> /dev/null; then
            fatal "Required tool '${tool}' is not installed."
        fi
    done
    
    success "Prerequisites check completed"
}

validate_aws_permissions() {
    info "Validating AWS permissions..."
    
    local required_actions=(
        "s3:CreateBucket"
        "s3:PutBucketVersioning"
        "s3:PutBucketEncryption"
        "transfer:CreateWebApp"
        "transfer:DescribeWebApp"
        "identitystore:CreateUser"
        "identitystore:ListUsers"
        "sso:ListInstances"
        "s3control:CreateAccessGrantsInstance"
        "s3control:CreateAccessGrant"
    )
    
    # This is a basic check - in production you might want more thorough validation
    if ! aws iam simulate-principal-policy \
        --policy-source-arn "$(aws sts get-caller-identity --query Arn --output text)" \
        --action-names "${required_actions[@]}" \
        --resource-arns "*" &> /dev/null; then
        warn "Unable to validate all required permissions. Proceeding with deployment..."
    fi
    
    success "Permission validation completed"
}

# =============================================================================
# Core Deployment Functions
# =============================================================================

setup_environment() {
    info "Setting up environment variables..."
    
    # Get AWS region and account
    export AWS_REGION
    AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        AWS_REGION="us-east-1"
        warn "No default region found, using ${AWS_REGION}"
    fi
    
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export BUCKET_NAME="file-sharing-demo-${RANDOM_SUFFIX}"
    export WEB_APP_NAME="file-sharing-app-${RANDOM_SUFFIX}"
    export USER_NAME="demo-user-${RANDOM_SUFFIX}"
    
    # Save configuration for cleanup
    cat > "${SCRIPT_DIR}/.deployment-config" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
BUCKET_NAME=${BUCKET_NAME}
WEB_APP_NAME=${WEB_APP_NAME}
USER_NAME=${USER_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment configured - Region: ${AWS_REGION}, Account: ${AWS_ACCOUNT_ID}, Suffix: ${RANDOM_SUFFIX}"
}

create_s3_bucket() {
    info "Creating S3 bucket for file storage..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create bucket: ${BUCKET_NAME}"
        return 0
    fi
    
    # Create S3 bucket with region-specific handling
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
        aws s3 mb "s3://${BUCKET_NAME}"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "${BUCKET_NAME}" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    # Add bucket tagging
    aws s3api put-bucket-tagging \
        --bucket "${BUCKET_NAME}" \
        --tagging 'TagSet=[
            {Key=Purpose,Value=FileSharing},
            {Key=Recipe,Value=TransferFamilyWebApps},
            {Key=Environment,Value=Demo}
        ]'
    
    success "S3 bucket created and configured: ${BUCKET_NAME}"
}

verify_identity_center() {
    info "Verifying IAM Identity Center configuration..."
    
    # Check if IAM Identity Center is enabled
    IDENTITY_CENTER_ARN=$(aws sso-admin list-instances \
        --query 'Instances[0].InstanceArn' --output text 2>/dev/null || echo "None")
    
    if [[ "${IDENTITY_CENTER_ARN}" == "None" ]] || [[ "${IDENTITY_CENTER_ARN}" == "null" ]]; then
        fatal "IAM Identity Center not enabled. Please enable it manually:
1. Go to https://console.aws.amazon.com/singlesignon/
2. Click 'Enable' and follow the setup wizard
3. Re-run this script after enabling IAM Identity Center"
    fi
    
    # Get Identity Store ID
    export IDENTITY_STORE_ID
    IDENTITY_STORE_ID=$(aws sso-admin list-instances \
        --query 'Instances[0].IdentityStoreId' --output text)
    
    success "IAM Identity Center verified - Instance: ${IDENTITY_CENTER_ARN}"
    info "Identity Store ID: ${IDENTITY_STORE_ID}"
}

create_demo_user() {
    info "Creating demo user in IAM Identity Center..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create user: ${USER_NAME}"
        return 0
    fi
    
    # Check if user already exists
    existing_user=$(aws identitystore list-users \
        --identity-store-id "${IDENTITY_STORE_ID}" \
        --filters AttributePath=UserName,AttributeValue="${USER_NAME}" \
        --query 'Users[0].UserId' --output text 2>/dev/null || echo "None")
    
    if [[ "${existing_user}" != "None" ]] && [[ "${existing_user}" != "null" ]]; then
        export DEMO_USER_ID="${existing_user}"
        warn "Demo user already exists: ${USER_NAME} (ID: ${DEMO_USER_ID})"
        return 0
    fi
    
    # Create demo user
    aws identitystore create-user \
        --identity-store-id "${IDENTITY_STORE_ID}" \
        --user-name "${USER_NAME}" \
        --display-name "Demo File Sharing User" \
        --name 'FamilyName=User,GivenName=Demo' \
        --emails 'Value=demo@example.com,Type=work,Primary=true' \
        > "${SCRIPT_DIR}/user-creation-result.json"
    
    # Extract user ID
    export DEMO_USER_ID
    DEMO_USER_ID=$(jq -r '.UserId' "${SCRIPT_DIR}/user-creation-result.json")
    
    success "Demo user created: ${USER_NAME} (ID: ${DEMO_USER_ID})"
}

setup_access_grants() {
    info "Setting up S3 Access Grants..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would setup S3 Access Grants"
        return 0
    fi
    
    # Create S3 Access Grants instance (idempotent)
    aws s3control create-access-grants-instance \
        --account-id "${AWS_ACCOUNT_ID}" \
        --identity-center-arn "${IDENTITY_CENTER_ARN}" \
        --region "${AWS_REGION}" 2>/dev/null || \
        info "Access Grants instance already exists"
    
    # Wait for instance to be ready
    sleep 10
    
    # Create IAM role for S3 Access Grants (if not exists)
    local role_name="S3AccessGrantsLocationRole"
    if ! aws iam get-role --role-name "${role_name}" &>/dev/null; then
        info "Creating IAM role for S3 Access Grants..."
        
        # Create trust policy
        cat > "${SCRIPT_DIR}/trust-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "s3.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
        
        aws iam create-role \
            --role-name "${role_name}" \
            --assume-role-policy-document file://"${SCRIPT_DIR}/trust-policy.json"
        
        aws iam attach-role-policy \
            --role-name "${role_name}" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess"
    fi
    
    # Register S3 location
    aws s3control create-access-grants-location \
        --account-id "${AWS_ACCOUNT_ID}" \
        --location-scope "s3://${BUCKET_NAME}/*" \
        --iam-role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_name}" \
        > "${SCRIPT_DIR}/location-result.json" 2>/dev/null || \
        aws s3control list-access-grants-locations \
            --account-id "${AWS_ACCOUNT_ID}" \
            --query "AccessGrantsLocationsList[?LocationScope=='s3://${BUCKET_NAME}/*']" \
            > "${SCRIPT_DIR}/location-result.json"
    
    # Extract location ID
    export LOCATION_ID
    LOCATION_ID=$(jq -r '.[0].AccessGrantsLocationId // .AccessGrantsLocationId' "${SCRIPT_DIR}/location-result.json")
    
    success "S3 Access Grants location registered: ${LOCATION_ID}"
}

create_access_grant() {
    info "Creating access grant for demo user..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create access grant for user: ${DEMO_USER_ID}"
        return 0
    fi
    
    # Create access grant
    aws s3control create-access-grant \
        --account-id "${AWS_ACCOUNT_ID}" \
        --access-grants-location-id "${LOCATION_ID}" \
        --grantee "{
            \"GranteeType\": \"DIRECTORY_USER\",
            \"GranteeIdentifier\": \"${IDENTITY_STORE_ID}:user/${DEMO_USER_ID}\"
        }" \
        --permission READWRITE \
        > "${SCRIPT_DIR}/grant-result.json"
    
    export GRANT_ID
    GRANT_ID=$(jq -r '.AccessGrantId' "${SCRIPT_DIR}/grant-result.json")
    
    success "S3 Access Grant created: ${GRANT_ID}"
}

create_transfer_web_app() {
    info "Creating Transfer Family Web App..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would create Transfer Family Web App"
        return 0
    fi
    
    # Create IAM role for Transfer Family Web App (if not exists)
    local role_name="TransferFamily-S3AccessGrants-WebAppRole"
    if ! aws iam get-role --role-name "${role_name}" &>/dev/null; then
        info "Creating IAM role for Transfer Family Web App..."
        
        # Create trust policy for Transfer Family
        cat > "${SCRIPT_DIR}/transfer-trust-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "transfer.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
        
        aws iam create-role \
            --role-name "${role_name}" \
            --assume-role-policy-document file://"${SCRIPT_DIR}/transfer-trust-policy.json"
        
        # Attach necessary policies
        aws iam attach-role-policy \
            --role-name "${role_name}" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonS3FullAccess"
            
        aws iam attach-role-policy \
            --role-name "${role_name}" \
            --policy-arn "arn:aws:iam::aws:policy/AWSSSODirectoryReadOnly"
    fi
    
    # Create the Transfer Family Web App
    aws transfer create-web-app \
        --identity-provider-details "{
            \"IdentityCenterConfig\": {
                \"InstanceArn\": \"${IDENTITY_CENTER_ARN}\",
                \"Role\": \"arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_name}\"
            }
        }" \
        --tags "Key=Name,Value=${WEB_APP_NAME}" \
               "Key=Purpose,Value=FileSharing" \
               "Key=Recipe,Value=TransferFamilyWebApps" \
        > "${SCRIPT_DIR}/webapp-creation-result.json"
    
    # Extract Web App ID
    export WEB_APP_ID
    WEB_APP_ID=$(jq -r '.WebAppId' "${SCRIPT_DIR}/webapp-creation-result.json")
    
    # Wait for web app to be available
    info "Waiting for web app to become available..."
    local max_attempts=30
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local status
        status=$(aws transfer describe-web-app \
            --web-app-id "${WEB_APP_ID}" \
            --query 'WebApp.State' --output text 2>/dev/null || echo "UNKNOWN")
        
        if [[ "${status}" == "AVAILABLE" ]]; then
            break
        elif [[ "${status}" == "FAILED" ]]; then
            fatal "Web app creation failed"
        fi
        
        info "Web app status: ${status} (attempt ${attempt}/${max_attempts})"
        sleep 30
        ((attempt++))
    done
    
    # Get access endpoint
    export ACCESS_ENDPOINT
    ACCESS_ENDPOINT=$(aws transfer describe-web-app \
        --web-app-id "${WEB_APP_ID}" \
        --query 'WebApp.AccessEndpoint' --output text)
    
    success "Transfer Family Web App created: ${WEB_APP_ID}"
    success "Access endpoint: ${ACCESS_ENDPOINT}"
}

configure_cors() {
    info "Configuring S3 CORS for web app access..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would configure CORS for bucket: ${BUCKET_NAME}"
        return 0
    fi
    
    # Create CORS configuration
    cat > "${SCRIPT_DIR}/cors-config.json" << EOF
{
    "CORSRules": [
        {
            "AllowedHeaders": ["*"],
            "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
            "AllowedOrigins": ["${ACCESS_ENDPOINT}"],
            "ExposeHeaders": [
                "last-modified", "content-length", "etag", 
                "x-amz-version-id", "content-type", "x-amz-request-id",
                "x-amz-id-2", "date", "x-amz-cf-id", "x-amz-storage-class"
            ],
            "MaxAgeSeconds": 3000
        }
    ]
}
EOF
    
    # Apply CORS configuration
    aws s3api put-bucket-cors \
        --bucket "${BUCKET_NAME}" \
        --cors-configuration file://"${SCRIPT_DIR}/cors-config.json"
    
    success "CORS configuration applied to bucket: ${BUCKET_NAME}"
}

assign_user_to_webapp() {
    info "Assigning user to Transfer Family Web App..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would assign user ${DEMO_USER_ID} to web app ${WEB_APP_ID}"
        return 0
    fi
    
    # Assign user to web app
    aws transfer create-web-app-assignment \
        --web-app-id "${WEB_APP_ID}" \
        --grantee "{
            \"Type\": \"USER\",
            \"Identifier\": \"${DEMO_USER_ID}\"
        }" \
        > "${SCRIPT_DIR}/assignment-result.json"
    
    success "User assigned to Transfer Family Web App"
    success "User '${USER_NAME}' can now access: ${ACCESS_ENDPOINT}"
}

save_deployment_state() {
    info "Saving deployment state..."
    
    # Update configuration with all created resources
    cat >> "${SCRIPT_DIR}/.deployment-config" << EOF
IDENTITY_CENTER_ARN=${IDENTITY_CENTER_ARN}
IDENTITY_STORE_ID=${IDENTITY_STORE_ID}
DEMO_USER_ID=${DEMO_USER_ID}
LOCATION_ID=${LOCATION_ID}
GRANT_ID=${GRANT_ID}
WEB_APP_ID=${WEB_APP_ID}
ACCESS_ENDPOINT=${ACCESS_ENDPOINT}
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    success "Deployment state saved to .deployment-config"
}

run_deployment() {
    info "Starting Transfer Family Web Apps deployment..."
    
    check_prerequisites
    validate_aws_permissions
    setup_environment
    create_s3_bucket
    verify_identity_center
    create_demo_user
    setup_access_grants
    create_access_grant
    create_transfer_web_app
    configure_cors
    assign_user_to_webapp
    save_deployment_state
    
    success "🎉 Deployment completed successfully!"
    echo
    echo "=========================================="
    echo "📋 DEPLOYMENT SUMMARY"
    echo "=========================================="
    echo "🌐 Web App Access URL: ${ACCESS_ENDPOINT}"
    echo "👤 Demo User: ${USER_NAME}"
    echo "🪣 S3 Bucket: ${BUCKET_NAME}"
    echo "🆔 Web App ID: ${WEB_APP_ID}"
    echo "📁 Log File: ${LOG_FILE}"
    echo
    echo "⚠️  IMPORTANT NEXT STEPS:"
    echo "1. Set a password for user '${USER_NAME}' in IAM Identity Center console"
    echo "2. Access the web app at: ${ACCESS_ENDPOINT}"
    echo "3. Test file upload/download functionality"
    echo
    echo "🧹 To clean up resources, run: ./destroy.sh"
    echo "=========================================="
}

run_cleanup() {
    warn "Running emergency cleanup due to deployment failure..."
    if [[ -f "${SCRIPT_DIR}/.deployment-config" ]]; then
        source "${SCRIPT_DIR}/.deployment-config"
        "${SCRIPT_DIR}/destroy.sh" --force --partial
    fi
}

# =============================================================================
# Main Script Logic
# =============================================================================

show_help() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Deploy AWS Transfer Family Web Apps for simple file sharing.

OPTIONS:
    --dry-run           Show what would be deployed without making changes
    --verbose           Enable verbose logging
    --force-cleanup     Automatically cleanup on failure
    --help              Show this help message

EXAMPLES:
    ${SCRIPT_NAME}                    # Deploy with default settings
    ${SCRIPT_NAME} --dry-run          # Preview deployment
    ${SCRIPT_NAME} --verbose          # Deploy with detailed logging

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - IAM Identity Center enabled in your AWS account
    - Appropriate AWS permissions

For more information, see the recipe documentation.
EOF
}

parse_arguments() {
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
            --force-cleanup)
                FORCE_CLEANUP=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

main() {
    echo "🚀 AWS Transfer Family Web Apps Deployment Script"
    echo "=================================================="
    
    parse_arguments "$@"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        warn "DRY RUN MODE - No resources will be created"
    fi
    
    run_deployment
}

# Execute main function with all arguments
main "$@"