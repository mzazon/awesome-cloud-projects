#!/bin/bash

# Deploy script for Secure Self-Service File Portals with AWS Transfer Family Web Apps
# This script automates the deployment of a complete file sharing solution with enterprise security

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version (v2 required)
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1 | cut -d. -f1)
    if [[ "$AWS_CLI_VERSION" -lt 2 ]]; then
        error "AWS CLI v2 is required. Current version: $(aws --version)"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or authentication failed"
        exit 1
    fi
    
    # Check required permissions by testing a basic operation
    if ! aws s3 ls &> /dev/null; then
        warning "Unable to verify S3 permissions. Continuing anyway..."
    fi
    
    log "Prerequisites check completed successfully"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "No region configured, using default: $AWS_REGION"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set resource names
    export BUCKET_NAME="file-portal-bucket-${RANDOM_SUFFIX}"
    export WEBAPP_NAME="file-portal-webapp-${RANDOM_SUFFIX}"
    export USER_NAME="portal-user-${RANDOM_SUFFIX}"
    export LOCATION_ROLE_NAME="S3AccessGrantsLocationRole-${RANDOM_SUFFIX}"
    
    # Create deployment log file
    export DEPLOYMENT_LOG="/tmp/transfer-family-deployment-${RANDOM_SUFFIX}.log"
    
    log "Environment initialized successfully"
    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "Bucket Name: $BUCKET_NAME"
    info "Web App Name: $WEBAPP_NAME"
    info "Deployment Log: $DEPLOYMENT_LOG"
}

# Create S3 bucket with security features
create_s3_bucket() {
    log "Creating S3 bucket with security features..."
    
    # Create S3 bucket with versioning and encryption
    if aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION} 2>> "$DEPLOYMENT_LOG"; then
        info "S3 bucket created: $BUCKET_NAME"
    else
        error "Failed to create S3 bucket"
        exit 1
    fi
    
    # Enable versioning for file history
    aws s3api put-bucket-versioning \
        --bucket ${BUCKET_NAME} \
        --versioning-configuration Status=Enabled \
        2>> "$DEPLOYMENT_LOG"
    
    # Enable server-side encryption with AES-256
    aws s3api put-bucket-encryption \
        --bucket ${BUCKET_NAME} \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]' \
        2>> "$DEPLOYMENT_LOG"
    
    # Enable access logging for compliance
    aws s3api put-bucket-logging \
        --bucket ${BUCKET_NAME} \
        --bucket-logging-status '{
            "LoggingEnabled": {
                "TargetBucket": "'${BUCKET_NAME}'",
                "TargetPrefix": "access-logs/"
            }
        }' \
        2>> "$DEPLOYMENT_LOG"
    
    log "S3 bucket configured with security features"
}

# Create IAM Identity Center user
create_identity_center_user() {
    log "Creating IAM Identity Center user..."
    
    # Get Identity Center instance details
    export IDC_INSTANCE_ARN=$(aws sso-admin list-instances \
        --query 'Instances[0].InstanceArn' --output text)
    export IDC_IDENTITY_STORE_ID=$(aws sso-admin list-instances \
        --query 'Instances[0].IdentityStoreId' --output text)
    
    if [[ "$IDC_INSTANCE_ARN" == "None" || -z "$IDC_INSTANCE_ARN" ]]; then
        error "No IAM Identity Center instance found. Please set up IAM Identity Center first."
        exit 1
    fi
    
    # Create a test user in IAM Identity Center
    aws identitystore create-user \
        --identity-store-id ${IDC_IDENTITY_STORE_ID} \
        --user-name ${USER_NAME} \
        --name '{
            "GivenName": "Test",
            "FamilyName": "User"
        }' \
        --display-name "Test User" \
        --emails '[{
            "Value": "test-user@example.com",
            "Type": "work",
            "Primary": true
        }]' \
        2>> "$DEPLOYMENT_LOG"
    
    # Store the user ID for later use
    export USER_ID=$(aws identitystore list-users \
        --identity-store-id ${IDC_IDENTITY_STORE_ID} \
        --filters 'AttributePath=UserName,AttributeValue='${USER_NAME} \
        --query 'Users[0].UserId' --output text)
    
    log "IAM Identity Center user created with ID: ${USER_ID}"
}

# Create S3 Access Grants instance
create_access_grants_instance() {
    log "Creating S3 Access Grants instance..."
    
    # Create S3 Access Grants instance
    aws s3control create-access-grants-instance \
        --account-id ${AWS_ACCOUNT_ID} \
        --identity-center-arn ${IDC_INSTANCE_ARN} \
        2>> "$DEPLOYMENT_LOG"
    
    # Wait for the instance to be ready
    sleep 10
    
    aws s3control get-access-grants-instance \
        --account-id ${AWS_ACCOUNT_ID} \
        --query 'AccessGrantsInstanceId' --output text \
        >> "$DEPLOYMENT_LOG"
    
    log "S3 Access Grants instance created with Identity Center integration"
}

# Create IAM role for Access Grants location
create_location_role() {
    log "Creating IAM role for Access Grants location..."
    
    # Create IAM role for Access Grants location
    aws iam create-role \
        --role-name ${LOCATION_ROLE_NAME} \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "s3.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        2>> "$DEPLOYMENT_LOG"
    
    # Attach policy for S3 operations
    aws iam attach-role-policy \
        --role-name ${LOCATION_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
        2>> "$DEPLOYMENT_LOG"
    
    # Get the role ARN
    export LOCATION_ROLE_ARN=$(aws iam get-role \
        --role-name ${LOCATION_ROLE_NAME} \
        --query 'Role.Arn' --output text)
    
    # Wait for role to be available
    sleep 15
    
    log "IAM role created for Access Grants location: $LOCATION_ROLE_ARN"
}

# Register S3 location in Access Grants
register_s3_location() {
    log "Registering S3 bucket as Access Grants location..."
    
    # Register S3 bucket as an Access Grants location
    aws s3control create-access-grants-location \
        --account-id ${AWS_ACCOUNT_ID} \
        --location-scope s3://${BUCKET_NAME}/* \
        --iam-role-arn ${LOCATION_ROLE_ARN} \
        --tags '[{
            "Key": "Purpose",
            "Value": "TransferFamilyWebApp"
        }]' \
        2>> "$DEPLOYMENT_LOG"
    
    # Get the location ID
    sleep 5
    export LOCATION_ID=$(aws s3control list-access-grants-locations \
        --account-id ${AWS_ACCOUNT_ID} \
        --query 'AccessGrantsLocationsList[?LocationScope==`s3://'${BUCKET_NAME}'/*`].AccessGrantsLocationId' \
        --output text)
    
    log "S3 location registered in Access Grants with ID: ${LOCATION_ID}"
}

# Create access grant for user
create_access_grant() {
    log "Creating access grant for user..."
    
    # Create access grant for the test user
    aws s3control create-access-grant \
        --account-id ${AWS_ACCOUNT_ID} \
        --access-grants-location-id ${LOCATION_ID} \
        --access-grants-location-configuration '{
            "S3SubPrefix": "*"
        }' \
        --grantee '{
            "GranteeType": "DIRECTORY_USER",
            "GranteeIdentifier": "'${USER_ID}'"
        }' \
        --permission READWRITE \
        --tags '[{
            "Key": "User",
            "Value": "'${USER_NAME}'"
        }]' \
        2>> "$DEPLOYMENT_LOG"
    
    log "Access grant created for user with read/write permissions"
}

# Create IAM role for Transfer Family Web App
create_webapp_role() {
    log "Creating IAM role for Transfer Family Web App..."
    
    # Create IAM role for Transfer Family Web App
    aws iam create-role \
        --role-name AWSTransferFamilyWebAppIdentityBearerRole \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "transfer.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        2>> "$DEPLOYMENT_LOG"
    
    # Attach the managed policy for Transfer Family Web App
    aws iam attach-role-policy \
        --role-name AWSTransferFamilyWebAppIdentityBearerRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSTransferFamilyWebAppIdentityBearerRole \
        2>> "$DEPLOYMENT_LOG"
    
    # Get the role ARN
    export WEBAPP_ROLE_ARN=$(aws iam get-role \
        --role-name AWSTransferFamilyWebAppIdentityBearerRole \
        --query 'Role.Arn' --output text)
    
    # Wait for role to be available
    sleep 15
    
    log "IAM role created for Transfer Family Web App: $WEBAPP_ROLE_ARN"
}

# Create Transfer Family Web App
create_web_app() {
    log "Creating Transfer Family Web App..."
    
    # Create Transfer Family web app with IAM Identity Center
    aws transfer create-web-app \
        --identity-provider-type IDENTITY_CENTER \
        --identity-provider-details '{
            "IdentityCenterConfig": {
                "InstanceArn": "'${IDC_INSTANCE_ARN}'"
            }
        }' \
        --access-role ${WEBAPP_ROLE_ARN} \
        --web-app-units 1 \
        --tags '[{
            "Key": "Name",
            "Value": "'${WEBAPP_NAME}'"
        }]' \
        2>> "$DEPLOYMENT_LOG"
    
    # Get the web app ID
    sleep 5
    export WEBAPP_ID=$(aws transfer list-web-apps \
        --query 'WebApps[?Tags[?Key==`Name`&&Value==`'${WEBAPP_NAME}'`]].WebAppId' \
        --output text)
    
    # Wait for web app to be available
    log "Waiting for web app to become available..."
    aws transfer wait web-app-available --web-app-id ${WEBAPP_ID}
    
    log "Transfer Family web app created with ID: ${WEBAPP_ID}"
}

# Configure CORS for S3 bucket
configure_cors() {
    log "Configuring CORS for S3 bucket..."
    
    # Get the web app access endpoint
    export ACCESS_ENDPOINT=$(aws transfer describe-web-app \
        --web-app-id ${WEBAPP_ID} \
        --query 'WebApp.AccessEndpoint' --output text)
    
    # Configure CORS for the S3 bucket
    aws s3api put-bucket-cors \
        --bucket ${BUCKET_NAME} \
        --cors-configuration '{
            "CORSRules": [{
                "AllowedHeaders": ["*"],
                "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
                "AllowedOrigins": ["https://'${ACCESS_ENDPOINT}'"],
                "ExposeHeaders": [
                    "last-modified", "content-length", "etag",
                    "x-amz-version-id", "content-type", "x-amz-request-id",
                    "x-amz-id-2", "date", "x-amz-cf-id", "x-amz-storage-class"
                ],
                "MaxAgeSeconds": 3000
            }]
        }' \
        2>> "$DEPLOYMENT_LOG"
    
    log "CORS configuration applied to S3 bucket"
}

# Configure Web App Identity Center integration
configure_identity_integration() {
    log "Configuring Web App Identity Center integration..."
    
    # Configure Identity Center integration for the web app
    aws transfer put-web-app-identity-center-config \
        --web-app-id ${WEBAPP_ID} \
        --identity-center-config '{
            "Role": "'${WEBAPP_ROLE_ARN}'"
        }' \
        2>> "$DEPLOYMENT_LOG"
    
    log "Web app configured with Identity Center integration"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check web app status
    local webapp_status=$(aws transfer describe-web-app --web-app-id ${WEBAPP_ID} \
        --query 'WebApp.State' --output text)
    
    if [[ "$webapp_status" == "Available" ]]; then
        log "Web app is available and ready for use"
    else
        warning "Web app status: $webapp_status (may still be initializing)"
    fi
    
    # Verify S3 bucket exists
    if aws s3 ls s3://${BUCKET_NAME} &> /dev/null; then
        log "S3 bucket validation successful"
    else
        error "S3 bucket validation failed"
    fi
    
    # Verify access grants
    local grants_count=$(aws s3control list-access-grants \
        --account-id ${AWS_ACCOUNT_ID} \
        --query 'length(AccessGrantsList)' --output text)
    
    if [[ "$grants_count" -gt 0 ]]; then
        log "Access grants validation successful ($grants_count grants found)"
    else
        warning "No access grants found"
    fi
    
    log "Deployment validation completed"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    local deployment_info_file="deployment-info-${RANDOM_SUFFIX}.txt"
    
    cat > "$deployment_info_file" << EOF
Transfer Family Web App Deployment Information
=============================================

Deployment Date: $(date)
AWS Region: ${AWS_REGION}
AWS Account ID: ${AWS_ACCOUNT_ID}

Resources Created:
- S3 Bucket: ${BUCKET_NAME}
- Web App ID: ${WEBAPP_ID}
- Web App Name: ${WEBAPP_NAME}
- Access Endpoint: https://${ACCESS_ENDPOINT}
- IAM Identity Center User: ${USER_NAME}
- User ID: ${USER_ID}
- Location Role: ${LOCATION_ROLE_NAME}
- Location ID: ${LOCATION_ID}

Access Information:
- Web Portal URL: https://${ACCESS_ENDPOINT}
- Test User: ${USER_NAME}
- Test User Email: test-user@example.com

Cleanup Command:
To remove all resources, run: ./destroy.sh

Important Notes:
- Set a password for the test user in IAM Identity Center before accessing the portal
- Configure MFA for enhanced security
- Monitor usage through CloudWatch logs

EOF

    info "Deployment information saved to: $deployment_info_file"
    log "Access your file portal at: https://${ACCESS_ENDPOINT}"
}

# Main deployment function
main() {
    log "Starting Transfer Family Web App deployment..."
    
    check_prerequisites
    initialize_environment
    
    # Execute deployment steps
    create_s3_bucket
    create_identity_center_user
    create_access_grants_instance
    create_location_role
    register_s3_location
    create_access_grant
    create_webapp_role
    create_web_app
    configure_cors
    configure_identity_integration
    
    # Validate and finalize
    validate_deployment
    save_deployment_info
    
    log "Deployment completed successfully!"
    info "Your secure file portal is ready at: https://${ACCESS_ENDPOINT}"
    warning "Remember to set a password for user '${USER_NAME}' in IAM Identity Center"
}

# Handle script interruption
cleanup_on_error() {
    error "Deployment interrupted. Check the log file for details: $DEPLOYMENT_LOG"
    warning "You may need to manually clean up any partially created resources"
    exit 1
}

# Set trap for cleanup on error
trap cleanup_on_error INT TERM

# Run main function
main "$@"