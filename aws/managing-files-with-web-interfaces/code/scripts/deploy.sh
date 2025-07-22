#!/bin/bash

# Deploy script for Self-Service File Management with AWS Transfer Family Web Apps
# This script deploys the complete infrastructure for secure file management solution

set -e
set -u
set -o pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

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

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partially created resources..."
    
    # Clean up temporary files
    rm -f access-grants-role-trust-policy.json
    rm -f identity-bearer-trust-policy.json
    rm -f identity-bearer-policy.json
    rm -f webapp-branding.json
    
    exit 1
}

# Set up error trap
trap cleanup_on_error ERR

# Banner
cat << 'EOF'
========================================================
AWS Transfer Family Web Apps Deployment Script
Self-Service File Management Solution
========================================================
EOF

log_info "Starting deployment of AWS Transfer Family Web Apps solution"

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

# Check if jq is installed (optional but helpful)
if ! command -v jq &> /dev/null; then
    log_warning "jq not found. Some output formatting may be limited."
fi

log_success "Prerequisites check completed"

# Set environment variables
log_info "Setting up environment variables..."

export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
if [ -z "${AWS_REGION}" ]; then
    log_error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
    exit 1
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

# Set resource names
export BUCKET_NAME="file-management-demo-${RANDOM_SUFFIX}"
export WEBAPP_NAME="file-management-webapp-${RANDOM_SUFFIX}"
export GRANTS_INSTANCE_NAME="file-management-grants-${RANDOM_SUFFIX}"

log_info "Environment configured:"
log_info "  AWS Region: ${AWS_REGION}"
log_info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
log_info "  Bucket Name: ${BUCKET_NAME}"
log_info "  Random Suffix: ${RANDOM_SUFFIX}"

# Create S3 bucket for file storage
log_info "Creating S3 bucket for file storage..."

if aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
    log_warning "Bucket ${BUCKET_NAME} already exists. Continuing with existing bucket."
else
    aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
    log_success "S3 bucket created: ${BUCKET_NAME}"
fi

# Enable versioning and encryption
log_info "Configuring S3 bucket versioning and encryption..."

aws s3api put-bucket-versioning \
    --bucket ${BUCKET_NAME} \
    --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
    --bucket ${BUCKET_NAME} \
    --server-side-encryption-configuration \
    'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'

log_success "S3 bucket configured with versioning and encryption"

# Check IAM Identity Center configuration
log_info "Checking IAM Identity Center configuration..."

IDC_INSTANCE=$(aws sso-admin list-instances \
    --query 'Instances[0].InstanceArn' \
    --output text 2>/dev/null || echo "None")

if [ "$IDC_INSTANCE" = "None" ] || [ -z "$IDC_INSTANCE" ]; then
    log_error "IAM Identity Center is not enabled in your organization."
    log_error "Please enable IAM Identity Center via the AWS console or contact your administrator."
    exit 1
fi

export IDC_INSTANCE_ARN=$IDC_INSTANCE
export IDC_IDENTITY_STORE_ID=$(aws sso-admin list-instances \
    --query 'Instances[0].IdentityStoreId' \
    --output text)

log_success "IAM Identity Center instance found: ${IDC_INSTANCE_ARN}"

# Create test user in IAM Identity Center
log_info "Creating test user in IAM Identity Center..."

# Check if test user already exists
EXISTING_USER=$(aws identitystore list-users \
    --identity-store-id ${IDC_IDENTITY_STORE_ID} \
    --query 'Users[?UserName==`testuser`].UserId' \
    --output text 2>/dev/null || echo "")

if [ -n "${EXISTING_USER}" ] && [ "${EXISTING_USER}" != "None" ]; then
    log_warning "Test user 'testuser' already exists. Using existing user."
    export TEST_USER_ID=${EXISTING_USER}
else
    aws identitystore create-user \
        --identity-store-id ${IDC_IDENTITY_STORE_ID} \
        --user-name "testuser" \
        --display-name "Test User" \
        --emails '[{"Value":"testuser@example.com","Type":"Work","Primary":true}]' \
        --name '{"GivenName":"Test","FamilyName":"User"}'
    
    export TEST_USER_ID=$(aws identitystore list-users \
        --identity-store-id ${IDC_IDENTITY_STORE_ID} \
        --query 'Users[?UserName==`testuser`].UserId' \
        --output text)
    
    log_success "Test user created with ID: ${TEST_USER_ID}"
fi

# Create S3 Access Grants instance
log_info "Creating S3 Access Grants instance..."

# Check if Access Grants instance already exists
EXISTING_GRANTS_INSTANCE=$(aws s3control get-access-grants-instance \
    --account-id ${AWS_ACCOUNT_ID} \
    --query 'AccessGrantsInstanceArn' \
    --output text 2>/dev/null || echo "None")

if [ "${EXISTING_GRANTS_INSTANCE}" != "None" ] && [ -n "${EXISTING_GRANTS_INSTANCE}" ]; then
    log_warning "S3 Access Grants instance already exists. Using existing instance."
    export GRANTS_INSTANCE_ARN=${EXISTING_GRANTS_INSTANCE}
else
    aws s3control create-access-grants-instance \
        --account-id ${AWS_ACCOUNT_ID} \
        --identity-center-arn ${IDC_INSTANCE_ARN} \
        --tags Key=Name,Value=${GRANTS_INSTANCE_NAME} \
            Key=Purpose,Value=FileManagement
    
    export GRANTS_INSTANCE_ARN=$(aws s3control get-access-grants-instance \
        --account-id ${AWS_ACCOUNT_ID} \
        --query 'AccessGrantsInstanceArn' \
        --output text)
    
    log_success "S3 Access Grants instance created: ${GRANTS_INSTANCE_ARN}"
fi

# Create IAM role for S3 Access Grants
log_info "Creating IAM role for S3 Access Grants..."

cat > access-grants-role-trust-policy.json << 'EOF'
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

# Check if role already exists
if aws iam get-role --role-name "S3AccessGrantsRole-${RANDOM_SUFFIX}" &>/dev/null; then
    log_warning "IAM role S3AccessGrantsRole-${RANDOM_SUFFIX} already exists. Using existing role."
else
    aws iam create-role \
        --role-name "S3AccessGrantsRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document file://access-grants-role-trust-policy.json
    
    aws iam attach-role-policy \
        --role-name "S3AccessGrantsRole-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
    
    log_success "IAM role for S3 Access Grants created"
fi

export GRANTS_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/S3AccessGrantsRole-${RANDOM_SUFFIX}"

# Register S3 location with Access Grants
log_info "Registering S3 location with Access Grants..."

# Check if location is already registered
EXISTING_LOCATION=$(aws s3control list-access-grants-locations \
    --account-id ${AWS_ACCOUNT_ID} \
    --query "AccessGrantsLocationsList[?contains(LocationScope, '${BUCKET_NAME}')].AccessGrantsLocationId" \
    --output text 2>/dev/null || echo "")

if [ -n "${EXISTING_LOCATION}" ] && [ "${EXISTING_LOCATION}" != "None" ]; then
    log_warning "S3 location already registered with Access Grants."
    export LOCATION_ID=${EXISTING_LOCATION}
else
    # Wait a bit for role to be available
    sleep 10
    
    aws s3control create-access-grants-location \
        --account-id ${AWS_ACCOUNT_ID} \
        --location-scope "s3://${BUCKET_NAME}/*" \
        --iam-role-arn ${GRANTS_ROLE_ARN} \
        --tags Key=Name,Value=FileManagementLocation
    
    export LOCATION_ID=$(aws s3control list-access-grants-locations \
        --account-id ${AWS_ACCOUNT_ID} \
        --query 'AccessGrantsLocationsList[0].AccessGrantsLocationId' \
        --output text)
    
    log_success "S3 location registered with Access Grants"
fi

# Create access grant for test user
log_info "Creating access grant for test user..."

# Check if grant already exists for user
EXISTING_GRANT=$(aws s3control list-access-grants \
    --account-id ${AWS_ACCOUNT_ID} \
    --query "AccessGrantsList[?contains(Grantee.GranteeIdentifier, '${TEST_USER_ID}')].AccessGrantId" \
    --output text 2>/dev/null || echo "")

if [ -n "${EXISTING_GRANT}" ] && [ "${EXISTING_GRANT}" != "None" ]; then
    log_warning "Access grant already exists for test user."
else
    aws s3control create-access-grant \
        --account-id ${AWS_ACCOUNT_ID} \
        --access-grants-location-id ${LOCATION_ID} \
        --access-grants-location-configuration "LocationScope=s3://${BUCKET_NAME}/user-files/*" \
        --grantee "GranteeType=IAM_IDENTITY_CENTER_USER,GranteeIdentifier=${TEST_USER_ID}" \
        --permission READWRITE \
        --tags Key=Name,Value=TestUserGrant
    
    log_success "Access grant created for test user"
fi

# Create Identity Bearer Role for Transfer Family
log_info "Creating Identity Bearer Role for Transfer Family..."

cat > identity-bearer-trust-policy.json << 'EOF'
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

# Check if role already exists
if aws iam get-role --role-name "TransferIdentityBearerRole-${RANDOM_SUFFIX}" &>/dev/null; then
    log_warning "Identity Bearer Role already exists. Using existing role."
else
    aws iam create-role \
        --role-name "TransferIdentityBearerRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document file://identity-bearer-trust-policy.json
    
    cat > identity-bearer-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetDataAccess"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sso:DescribeInstance"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "TransferIdentityBearerRole-${RANDOM_SUFFIX}" \
        --policy-name S3AccessGrantsPolicy \
        --policy-document file://identity-bearer-policy.json
    
    log_success "Identity Bearer Role created"
fi

export IDENTITY_BEARER_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/TransferIdentityBearerRole-${RANDOM_SUFFIX}"

# Create Transfer Family Web App
log_info "Creating Transfer Family Web App..."

# Get default VPC and subnet for web app endpoint
DEFAULT_VPC=$(aws ec2 describe-vpcs \
    --filters Name=isDefault,Values=true \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [ "${DEFAULT_VPC}" = "None" ] || [ -z "${DEFAULT_VPC}" ]; then
    log_error "No default VPC found. Please create a VPC or specify VPC configuration."
    exit 1
fi

DEFAULT_SUBNET=$(aws ec2 describe-subnets \
    --filters Name=default-for-az,Values=true \
    --query 'Subnets[0].SubnetId' \
    --output text)

if [ "${DEFAULT_SUBNET}" = "None" ] || [ -z "${DEFAULT_SUBNET}" ]; then
    log_error "No default subnet found. Please create a subnet or specify subnet configuration."
    exit 1
fi

# Check if web app already exists
EXISTING_WEBAPP=$(aws transfer list-web-apps \
    --query "WebApps[?contains(Tags[?Key==\`Name\`].Value, \`${WEBAPP_NAME}\`)].Arn" \
    --output text 2>/dev/null || echo "")

if [ -n "${EXISTING_WEBAPP}" ] && [ "${EXISTING_WEBAPP}" != "None" ]; then
    log_warning "Transfer Family Web App already exists. Using existing web app."
    export WEBAPP_ARN=${EXISTING_WEBAPP}
else
    # Wait for Identity Bearer Role to be available
    log_info "Waiting for Identity Bearer Role to be available..."
    sleep 30
    
    aws transfer create-web-app \
        --identity-provider-type SERVICE_MANAGED \
        --identity-provider-details "{
            \"IdentityCenterConfig\": {
                \"InstanceArn\": \"${IDC_INSTANCE_ARN}\",
                \"Role\": \"${IDENTITY_BEARER_ROLE_ARN}\"
            }
        }" \
        --access-endpoint "{
            \"Type\": \"VPC\",
            \"VpcId\": \"${DEFAULT_VPC}\",
            \"SubnetIds\": [\"${DEFAULT_SUBNET}\"]
        }" \
        --tags Key=Name,Value=${WEBAPP_NAME} \
            Key=Environment,Value=Demo
    
    log_info "Waiting for web app to be created..."
    sleep 30
    
    export WEBAPP_ARN=$(aws transfer list-web-apps \
        --query "WebApps[?contains(Tags[?Key==\`Name\`].Value, \`${WEBAPP_NAME}\`)].Arn" \
        --output text)
    
    log_success "Transfer Family Web App created"
fi

# Get the Web App URL
export WEBAPP_URL=$(aws transfer describe-web-app \
    --web-app-id ${WEBAPP_ARN} \
    --query 'WebApp.WebAppEndpoint' \
    --output text)

# Configure Web App branding
log_info "Configuring web app branding..."

cat > webapp-branding.json << 'EOF'
{
    "Title": "Secure File Management Portal",
    "Description": "Upload, download, and manage your files securely",
    "LogoUrl": "https://via.placeholder.com/200x60/0066CC/FFFFFF?text=Your+Logo",
    "FaviconUrl": "https://via.placeholder.com/32x32/0066CC/FFFFFF?text=F"
}
EOF

aws transfer update-web-app \
    --web-app-id ${WEBAPP_ARN} \
    --branding file://webapp-branding.json

log_success "Web app branding configured"

# Create test files and folder structure
log_info "Creating sample folder structure and files..."

aws s3api put-object \
    --bucket ${BUCKET_NAME} \
    --key "user-files/documents/README.txt" \
    --body /dev/stdin << 'EOF'
Welcome to the Secure File Management Portal!

This system provides a secure, easy-to-use interface for managing your files.

Getting Started:
1. Navigate through folders using the web interface
2. Upload files by dragging and dropping or using the upload button
3. Download files by clicking on them
4. Create new folders using the "New Folder" button

For support, contact your IT administrator.
EOF

aws s3api put-object \
    --bucket ${BUCKET_NAME} \
    --key "user-files/documents/sample-document.txt" \
    --body /dev/stdin << 'EOF'
This is a sample document to demonstrate file management capabilities.
You can upload, download, and manage files like this one through the web interface.
EOF

aws s3api put-object \
    --bucket ${BUCKET_NAME} \
    --key "user-files/shared/team-resources.txt" \
    --body /dev/stdin << 'EOF'
This folder contains shared resources for the team.
All team members have access to files in this location.
EOF

log_success "Sample folder structure and files created"

# Save deployment configuration
log_info "Saving deployment configuration..."

cat > "${SCRIPT_DIR}/deployment-config.env" << EOF
# Deployment Configuration
# Generated on: ${TIMESTAMP}

export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export BUCKET_NAME="${BUCKET_NAME}"
export WEBAPP_NAME="${WEBAPP_NAME}"
export GRANTS_INSTANCE_NAME="${GRANTS_INSTANCE_NAME}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export IDC_INSTANCE_ARN="${IDC_INSTANCE_ARN}"
export IDC_IDENTITY_STORE_ID="${IDC_IDENTITY_STORE_ID}"
export TEST_USER_ID="${TEST_USER_ID}"
export GRANTS_INSTANCE_ARN="${GRANTS_INSTANCE_ARN}"
export GRANTS_ROLE_ARN="${GRANTS_ROLE_ARN}"
export IDENTITY_BEARER_ROLE_ARN="${IDENTITY_BEARER_ROLE_ARN}"
export WEBAPP_ARN="${WEBAPP_ARN}"
export WEBAPP_URL="${WEBAPP_URL}"
EOF

# Clean up temporary files
rm -f access-grants-role-trust-policy.json
rm -f identity-bearer-trust-policy.json
rm -f identity-bearer-policy.json
rm -f webapp-branding.json

# Final deployment summary
log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
log_info "Resource Summary:"
log_info "  S3 Bucket: ${BUCKET_NAME}"
log_info "  Web App URL: ${WEBAPP_URL}"
log_info "  Test User: testuser"
log_info "  IAM Identity Center ID: ${IDC_IDENTITY_STORE_ID}"
log_info ""
log_info "Next Steps:"
log_info "1. Access the web app at: ${WEBAPP_URL}"
log_info "2. Log in with the test user credentials"
log_info "3. Explore the file management interface"
log_info "4. Upload and download test files"
log_info ""
log_info "Configuration saved to: ${SCRIPT_DIR}/deployment-config.env"
log_info "Deployment log saved to: ${LOG_FILE}"

echo ""
echo "========================================================="
echo "Deployment completed successfully!"
echo "Web App URL: ${WEBAPP_URL}"
echo "========================================================="