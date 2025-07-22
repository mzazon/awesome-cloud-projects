#!/bin/bash

# Destroy script for Self-Service File Management with AWS Transfer Family Web Apps
# This script safely removes all infrastructure created by the deployment script

set -e
set -u
set -o pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
CONFIG_FILE="${SCRIPT_DIR}/deployment-config.env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${TIMESTAMP} - ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${TIMESTAMP} - ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${TIMESTAMP} - ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${TIMESTAMP} - ${1}"
}

# Function to prompt for confirmation
confirm_action() {
    local message="$1"
    local default_response="${2:-n}"
    
    while true; do
        if [ "$default_response" = "y" ]; then
            read -p "${message} [Y/n]: " response
            response=${response:-y}
        else
            read -p "${message} [y/N]: " response
            response=${response:-n}
        fi
        
        case $response in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Safety check function
safety_check() {
    log_warning "This script will permanently delete the following resources:"
    log_warning "  - Transfer Family Web App"
    log_warning "  - S3 Access Grants instance and all grants"
    log_warning "  - IAM roles and policies"
    log_warning "  - S3 bucket and all contents"
    log_warning "  - IAM Identity Center test user"
    echo ""
    
    if ! confirm_action "Are you sure you want to proceed with the destruction?"; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
    
    echo ""
    log_info "Proceeding with resource destruction..."
}

# Banner
cat << 'EOF'
========================================================
AWS Transfer Family Web Apps Destruction Script
Self-Service File Management Solution Cleanup
========================================================
EOF

log_info "Starting destruction of AWS Transfer Family Web Apps solution"

# Safety confirmation
safety_check

# Load deployment configuration if available
if [ -f "${CONFIG_FILE}" ]; then
    log_info "Loading deployment configuration from ${CONFIG_FILE}"
    source "${CONFIG_FILE}"
    log_success "Configuration loaded successfully"
else
    log_warning "Deployment configuration file not found. Manual configuration required."
    
    # Prompt for required information
    read -p "Enter AWS Region: " AWS_REGION
    read -p "Enter random suffix used during deployment: " RANDOM_SUFFIX
    
    export AWS_REGION
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export BUCKET_NAME="file-management-demo-${RANDOM_SUFFIX}"
    export WEBAPP_NAME="file-management-webapp-${RANDOM_SUFFIX}"
fi

# Check prerequisites
log_info "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI not found. Please install AWS CLI and try again."
    exit 1
fi

# Check if AWS credentials are configured
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure' and try again."
    exit 1
fi

log_success "Prerequisites check completed"

# Set default values if not loaded from config
AWS_REGION=${AWS_REGION:-$(aws configure get region)}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}

log_info "Destruction configuration:"
log_info "  AWS Region: ${AWS_REGION}"
log_info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
log_info "  Target resources with suffix: ${RANDOM_SUFFIX:-'not specified'}"

# Function to handle resource deletion with error handling
safe_delete() {
    local resource_type="$1"
    local delete_command="$2"
    local success_message="$3"
    
    log_info "Deleting ${resource_type}..."
    
    if eval "$delete_command" 2>/dev/null; then
        log_success "${success_message}"
    else
        log_warning "Failed to delete ${resource_type} or resource does not exist"
    fi
}

# 1. Remove Transfer Family Web App
log_info "=== REMOVING TRANSFER FAMILY WEB APP ==="

if [ -n "${WEBAPP_ARN:-}" ]; then
    safe_delete "Transfer Family Web App" \
        "aws transfer delete-web-app --web-app-id ${WEBAPP_ARN}" \
        "Transfer Family Web App deleted successfully"
else
    # Try to find and delete web app by name
    WEBAPP_ARN=$(aws transfer list-web-apps \
        --query "WebApps[?contains(Tags[?Key==\`Name\`].Value, \`${WEBAPP_NAME:-file-management-webapp}\`)].Arn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "${WEBAPP_ARN}" ] && [ "${WEBAPP_ARN}" != "None" ]; then
        safe_delete "Transfer Family Web App" \
            "aws transfer delete-web-app --web-app-id ${WEBAPP_ARN}" \
            "Transfer Family Web App deleted successfully"
    else
        log_warning "Transfer Family Web App not found or already deleted"
    fi
fi

# Wait for web app deletion to complete
log_info "Waiting for web app deletion to complete..."
sleep 30

# 2. Remove S3 Access Grants Resources
log_info "=== REMOVING S3 ACCESS GRANTS RESOURCES ==="

# Delete access grants
log_info "Deleting access grants..."
GRANT_IDS=$(aws s3control list-access-grants \
    --account-id ${AWS_ACCOUNT_ID} \
    --query 'AccessGrantsList[].AccessGrantId' \
    --output text 2>/dev/null || echo "")

if [ -n "${GRANT_IDS}" ] && [ "${GRANT_IDS}" != "None" ]; then
    for grant_id in ${GRANT_IDS}; do
        safe_delete "Access Grant ${grant_id}" \
            "aws s3control delete-access-grant --account-id ${AWS_ACCOUNT_ID} --access-grant-id ${grant_id}" \
            "Access Grant ${grant_id} deleted successfully"
    done
else
    log_warning "No access grants found"
fi

# Delete access grants locations
log_info "Deleting access grants locations..."
LOCATION_IDS=$(aws s3control list-access-grants-locations \
    --account-id ${AWS_ACCOUNT_ID} \
    --query 'AccessGrantsLocationsList[].AccessGrantsLocationId' \
    --output text 2>/dev/null || echo "")

if [ -n "${LOCATION_IDS}" ] && [ "${LOCATION_IDS}" != "None" ]; then
    for location_id in ${LOCATION_IDS}; do
        safe_delete "Access Grants Location ${location_id}" \
            "aws s3control delete-access-grants-location --account-id ${AWS_ACCOUNT_ID} --access-grants-location-id ${location_id}" \
            "Access Grants Location ${location_id} deleted successfully"
    done
else
    log_warning "No access grants locations found"
fi

# Delete access grants instance
safe_delete "S3 Access Grants Instance" \
    "aws s3control delete-access-grants-instance --account-id ${AWS_ACCOUNT_ID}" \
    "S3 Access Grants Instance deleted successfully"

# 3. Remove IAM Roles and Policies
log_info "=== REMOVING IAM ROLES AND POLICIES ==="

# Delete Identity Bearer Role
if [ -n "${RANDOM_SUFFIX:-}" ]; then
    IDENTITY_BEARER_ROLE="TransferIdentityBearerRole-${RANDOM_SUFFIX}"
    GRANTS_ROLE="S3AccessGrantsRole-${RANDOM_SUFFIX}"
    
    # Delete Identity Bearer Role policy and role
    safe_delete "Identity Bearer Role Policy" \
        "aws iam delete-role-policy --role-name ${IDENTITY_BEARER_ROLE} --policy-name S3AccessGrantsPolicy" \
        "Identity Bearer Role Policy deleted successfully"
    
    safe_delete "Identity Bearer Role" \
        "aws iam delete-role --role-name ${IDENTITY_BEARER_ROLE}" \
        "Identity Bearer Role deleted successfully"
    
    # Delete S3 Access Grants Role
    safe_delete "S3 Access Grants Role Policy Attachment" \
        "aws iam detach-role-policy --role-name ${GRANTS_ROLE} --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess" \
        "S3 Access Grants Role Policy detached successfully"
    
    safe_delete "S3 Access Grants Role" \
        "aws iam delete-role --role-name ${GRANTS_ROLE}" \
        "S3 Access Grants Role deleted successfully"
else
    log_warning "Random suffix not available. Skipping IAM role deletion."
    log_warning "You may need to manually delete IAM roles with pattern: TransferIdentityBearerRole-* and S3AccessGrantsRole-*"
fi

# 4. Remove S3 Bucket and Contents
log_info "=== REMOVING S3 BUCKET AND CONTENTS ==="

if [ -n "${BUCKET_NAME:-}" ]; then
    # Check if bucket exists
    if aws s3 ls "s3://${BUCKET_NAME}" &>/dev/null; then
        log_info "Bucket ${BUCKET_NAME} found. Proceeding with deletion..."
        
        # Delete all objects in bucket
        log_info "Deleting all objects in bucket..."
        aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>/dev/null || log_warning "No objects to delete or error deleting objects"
        
        # Handle versioned objects and delete markers
        log_info "Deleting object versions and delete markers..."
        
        # Create temporary file for versions
        VERSIONS_FILE=$(mktemp)
        
        # Get all object versions
        aws s3api list-object-versions \
            --bucket ${BUCKET_NAME} \
            --output json \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' > "${VERSIONS_FILE}" 2>/dev/null || echo '{"Objects": []}' > "${VERSIONS_FILE}"
        
        # Delete versions if any exist
        if [ -s "${VERSIONS_FILE}" ] && [ "$(cat "${VERSIONS_FILE}" | grep -c '\"Key\"')" -gt 0 ]; then
            aws s3api delete-objects \
                --bucket ${BUCKET_NAME} \
                --delete "file://${VERSIONS_FILE}" 2>/dev/null || log_warning "Error deleting object versions"
        fi
        
        # Get and delete all delete markers
        aws s3api list-object-versions \
            --bucket ${BUCKET_NAME} \
            --output json \
            --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' > "${VERSIONS_FILE}" 2>/dev/null || echo '{"Objects": []}' > "${VERSIONS_FILE}"
        
        # Delete delete markers if any exist
        if [ -s "${VERSIONS_FILE}" ] && [ "$(cat "${VERSIONS_FILE}" | grep -c '\"Key\"')" -gt 0 ]; then
            aws s3api delete-objects \
                --bucket ${BUCKET_NAME} \
                --delete "file://${VERSIONS_FILE}" 2>/dev/null || log_warning "Error deleting delete markers"
        fi
        
        # Clean up temporary file
        rm -f "${VERSIONS_FILE}"
        
        # Delete bucket
        safe_delete "S3 Bucket" \
            "aws s3 rb s3://${BUCKET_NAME}" \
            "S3 bucket ${BUCKET_NAME} deleted successfully"
    else
        log_warning "Bucket ${BUCKET_NAME} not found or already deleted"
    fi
else
    log_warning "Bucket name not available. Skipping S3 bucket deletion."
fi

# 5. Remove IAM Identity Center Test User
log_info "=== REMOVING IAM IDENTITY CENTER TEST USER ==="

if [ -n "${IDC_IDENTITY_STORE_ID:-}" ] && [ -n "${TEST_USER_ID:-}" ]; then
    safe_delete "IAM Identity Center Test User" \
        "aws identitystore delete-user --identity-store-id ${IDC_IDENTITY_STORE_ID} --user-id ${TEST_USER_ID}" \
        "Test user deleted successfully"
elif [ -n "${IDC_IDENTITY_STORE_ID:-}" ]; then
    # Try to find and delete test user by username
    TEST_USER_ID=$(aws identitystore list-users \
        --identity-store-id ${IDC_IDENTITY_STORE_ID} \
        --query 'Users[?UserName==`testuser`].UserId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "${TEST_USER_ID}" ] && [ "${TEST_USER_ID}" != "None" ]; then
        safe_delete "IAM Identity Center Test User" \
            "aws identitystore delete-user --identity-store-id ${IDC_IDENTITY_STORE_ID} --user-id ${TEST_USER_ID}" \
            "Test user deleted successfully"
    else
        log_warning "Test user not found or already deleted"
    fi
else
    log_warning "Identity Center configuration not available. Skipping test user deletion."
fi

# 6. Clean up local files
log_info "=== CLEANING UP LOCAL FILES ==="

log_info "Removing temporary and configuration files..."

# Remove temporary files that might have been left behind
rm -f access-grants-role-trust-policy.json
rm -f identity-bearer-trust-policy.json
rm -f identity-bearer-policy.json
rm -f webapp-branding.json
rm -f versions.json

# Ask if user wants to remove deployment configuration
if [ -f "${CONFIG_FILE}" ]; then
    if confirm_action "Remove deployment configuration file (${CONFIG_FILE})?"; then
        rm -f "${CONFIG_FILE}"
        log_success "Deployment configuration file removed"
    else
        log_info "Deployment configuration file preserved"
    fi
fi

log_success "Local files cleaned up"

# Final summary
log_success "=== DESTRUCTION COMPLETED ==="
log_info "All resources have been processed for deletion."
log_info ""
log_info "Resources that were deleted (if they existed):"
log_info "  ✓ Transfer Family Web App"
log_info "  ✓ S3 Access Grants (instance, locations, grants)"
log_info "  ✓ IAM Roles (Identity Bearer Role, S3 Access Grants Role)"
log_info "  ✓ S3 Bucket and all contents"
log_info "  ✓ IAM Identity Center test user"
log_info "  ✓ Local temporary files"
log_info ""
log_info "Note: IAM Identity Center instance remains active as it may be shared"
log_info "Destruction log saved to: ${LOG_FILE}"

# Verification section
log_info "=== VERIFICATION ==="
log_info "Running verification checks..."

# Check if S3 bucket still exists
if [ -n "${BUCKET_NAME:-}" ]; then
    if aws s3 ls "s3://${BUCKET_NAME}" &>/dev/null; then
        log_warning "S3 bucket ${BUCKET_NAME} still exists"
    else
        log_success "S3 bucket ${BUCKET_NAME} successfully deleted"
    fi
fi

# Check if IAM roles still exist
if [ -n "${RANDOM_SUFFIX:-}" ]; then
    if aws iam get-role --role-name "TransferIdentityBearerRole-${RANDOM_SUFFIX}" &>/dev/null; then
        log_warning "Identity Bearer Role still exists"
    else
        log_success "Identity Bearer Role successfully deleted"
    fi
    
    if aws iam get-role --role-name "S3AccessGrantsRole-${RANDOM_SUFFIX}" &>/dev/null; then
        log_warning "S3 Access Grants Role still exists"
    else
        log_success "S3 Access Grants Role successfully deleted"
    fi
fi

echo ""
echo "========================================================="
echo "Destruction completed!"
echo "Check the log above for any warnings or manual cleanup needed."
echo "========================================================="