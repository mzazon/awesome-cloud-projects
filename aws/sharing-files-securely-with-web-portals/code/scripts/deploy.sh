#!/bin/bash

# Deploy Secure File Sharing with AWS Transfer Family Web Apps
# This script deploys the complete infrastructure for secure file sharing

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Default configuration
DRY_RUN=false
FORCE_DEPLOYMENT=false
SKIP_PREREQUISITES=false

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Deploy Secure File Sharing with AWS Transfer Family Web Apps"
    echo ""
    echo "Options:"
    echo "  -d, --dry-run           Show what would be deployed without making changes"
    echo "  -f, --force             Force deployment even if resources exist"
    echo "  -s, --skip-prereqs      Skip prerequisite checks"
    echo "  -h, --help              Display this help message"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_REGION              AWS region for deployment (default: from AWS config)"
    echo "  RESOURCE_PREFIX         Prefix for resource names (default: secure-files)"
    echo ""
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE_DEPLOYMENT=true
            shift
            ;;
        -s|--skip-prereqs)
            SKIP_PREREQUISITES=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Prerequisite checks
check_prerequisites() {
    if [[ "$SKIP_PREREQUISITES" == "true" ]]; then
        warning "Skipping prerequisite checks"
        return 0
    fi

    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo $AWS_VERSION | cut -d. -f1) -lt 2 ]]; then
        error "AWS CLI v2 is required. Current version: $AWS_VERSION"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid. Run 'aws configure' first."
    fi
    
    # Check required permissions (basic check)
    CALLER_IDENTITY=$(aws sts get-caller-identity)
    if [[ -z "$CALLER_IDENTITY" ]]; then
        error "Unable to verify AWS credentials"
    fi
    
    success "Prerequisites check passed"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "No region specified, using default: $AWS_REGION"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names with prefix
    RESOURCE_PREFIX=${RESOURCE_PREFIX:-"secure-files"}
    export BUCKET_NAME="${RESOURCE_PREFIX}-${RANDOM_SUFFIX}"
    export WEBAPP_NAME="${RESOURCE_PREFIX}-portal-${RANDOM_SUFFIX}"
    export TRAIL_NAME="${RESOURCE_PREFIX}-audit-${RANDOM_SUFFIX}"
    export ROLE_NAME="TransferFamilyRole-${RANDOM_SUFFIX}"
    export USER_NAME="testuser"
    
    # Store configuration for later use
    cat > .deployment-config << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
BUCKET_NAME=$BUCKET_NAME
WEBAPP_NAME=$WEBAPP_NAME
TRAIL_NAME=$TRAIL_NAME
ROLE_NAME=$ROLE_NAME
USER_NAME=$USER_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    log "Environment initialized:"
    log "  AWS Region: $AWS_REGION"
    log "  AWS Account: $AWS_ACCOUNT_ID"
    log "  S3 Bucket: $BUCKET_NAME"
    log "  Web App: $WEBAPP_NAME"
    log "  CloudTrail: $TRAIL_NAME"
    log "  IAM Role: $ROLE_NAME"
}

# Check if resources already exist
check_existing_resources() {
    log "Checking for existing resources..."
    
    EXISTING_RESOURCES=false
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        warning "S3 bucket $BUCKET_NAME already exists"
        EXISTING_RESOURCES=true
    fi
    
    # Check IAM role
    if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
        warning "IAM role $ROLE_NAME already exists"
        EXISTING_RESOURCES=true
    fi
    
    if [[ "$EXISTING_RESOURCES" == "true" && "$FORCE_DEPLOYMENT" != "true" ]]; then
        error "Resources already exist. Use --force to proceed anyway or run destroy script first."
    fi
}

# Create S3 bucket with security configurations
create_s3_bucket() {
    log "Creating S3 bucket: $BUCKET_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create S3 bucket: $BUCKET_NAME"
        return 0
    fi
    
    # Create S3 bucket
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb s3://${BUCKET_NAME}
    else
        aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket ${BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket ${BUCKET_NAME} \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket ${BUCKET_NAME} \
        --public-access-block-configuration \
        'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
    
    # Add bucket tags
    aws s3api put-bucket-tagging \
        --bucket ${BUCKET_NAME} \
        --tagging 'TagSet=[{Key=Purpose,Value=SecureFileSharing},{Key=Environment,Value=Development},{Key=ManagedBy,Value=TransferFamily}]'
    
    success "S3 bucket created and configured: $BUCKET_NAME"
}

# Setup IAM Identity Center
setup_identity_center() {
    log "Setting up IAM Identity Center..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would setup IAM Identity Center"
        return 0
    fi
    
    # Check if Identity Center is already enabled
    EXISTING_INSTANCE=$(aws sso-admin list-instances \
        --query 'Instances[0].InstanceArn' --output text 2>/dev/null || echo "None")
    
    if [[ "$EXISTING_INSTANCE" != "None" && -n "$EXISTING_INSTANCE" ]]; then
        log "Identity Center already enabled"
        export IDENTITY_CENTER_ARN=$EXISTING_INSTANCE
    else
        log "Enabling IAM Identity Center (this may take a few minutes)..."
        # Note: Identity Center enablement is typically done through console
        warning "Please enable IAM Identity Center through the AWS Console if not already enabled"
        
        # Wait for user confirmation
        read -p "Press Enter after Identity Center is enabled, or Ctrl+C to abort..."
        
        # Get the instance ARN after enablement
        export IDENTITY_CENTER_ARN=$(aws sso-admin list-instances \
            --query 'Instances[0].InstanceArn' --output text)
    fi
    
    # Get the Identity Store ID
    export IDENTITY_STORE_ID=$(aws sso-admin list-instances \
        --query 'Instances[0].IdentityStoreId' --output text)
    
    # Create test user if it doesn't exist
    EXISTING_USER=$(aws identitystore list-users \
        --identity-store-id ${IDENTITY_STORE_ID} \
        --query "Users[?UserName=='${USER_NAME}'].UserId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$EXISTING_USER" ]]; then
        log "Creating test user: $USER_NAME"
        aws identitystore create-user \
            --identity-store-id ${IDENTITY_STORE_ID} \
            --user-name "${USER_NAME}" \
            --display-name "Test User" \
            --name '{"FamilyName":"User","GivenName":"Test"}' \
            --emails '[{"Value":"testuser@example.com","Type":"Work","Primary":true}]'
    else
        log "Test user already exists: $USER_NAME"
    fi
    
    # Get user ID
    export USER_ID=$(aws identitystore list-users \
        --identity-store-id ${IDENTITY_STORE_ID} \
        --query "Users[?UserName=='${USER_NAME}'].UserId" --output text)
    
    success "Identity Center configured with test user: $USER_NAME"
}

# Create IAM role for Transfer Family
create_iam_role() {
    log "Creating IAM role for Transfer Family: $ROLE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create IAM role: $ROLE_NAME"
        return 0
    fi
    
    # Create trust policy
    cat > /tmp/transfer-trust-policy.json << EOF
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
    
    # Create IAM role
    aws iam create-role \
        --role-name ${ROLE_NAME} \
        --assume-role-policy-document file:///tmp/transfer-trust-policy.json \
        --description "Role for AWS Transfer Family to access S3 resources" \
        --tags Key=Purpose,Value=TransferFamily Key=Environment,Value=Development
    
    # Create S3 access policy
    cat > /tmp/s3-access-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:GetObjectVersion",
                "s3:DeleteObjectVersion"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        }
    ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-name S3AccessPolicy \
        --policy-document file:///tmp/s3-access-policy.json
    
    # Get role ARN
    export ROLE_ARN=$(aws iam get-role \
        --role-name ${ROLE_NAME} \
        --query 'Role.Arn' --output text)
    
    # Clean up temporary files
    rm -f /tmp/transfer-trust-policy.json /tmp/s3-access-policy.json
    
    success "IAM role created: $ROLE_ARN"
}

# Create CloudTrail for audit logging
create_cloudtrail() {
    log "Creating CloudTrail for audit logging: $TRAIL_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create CloudTrail: $TRAIL_NAME"
        return 0
    fi
    
    # Create CloudTrail
    aws cloudtrail create-trail \
        --name ${TRAIL_NAME} \
        --s3-bucket-name ${BUCKET_NAME} \
        --s3-key-prefix "audit-logs/" \
        --include-global-service-events \
        --is-multi-region-trail \
        --enable-log-file-validation
    
    # Configure data events for S3 bucket
    aws cloudtrail put-event-selectors \
        --trail-name ${TRAIL_NAME} \
        --event-selectors \
        "ReadWriteType=All,IncludeManagementEvents=true,DataResources=[{Type=AWS::S3::Object,Values=[\"arn:aws:s3:::${BUCKET_NAME}/*\"]}]"
    
    # Start logging
    aws cloudtrail start-logging --name ${TRAIL_NAME}
    
    # Add tags
    aws cloudtrail add-tags \
        --resource-id "arn:aws:cloudtrail:${AWS_REGION}:${AWS_ACCOUNT_ID}:trail/${TRAIL_NAME}" \
        --tags-list Key=Purpose,Value=AuditLogging Key=Environment,Value=Development
    
    success "CloudTrail configured and logging started: $TRAIL_NAME"
}

# Create Transfer Family server
create_transfer_server() {
    log "Creating Transfer Family server..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Transfer Family server"
        return 0
    fi
    
    # Create Transfer Family server
    export SERVER_ID=$(aws transfer create-server \
        --identity-provider-type SERVICE_MANAGED \
        --logging-role ${ROLE_ARN} \
        --protocols SFTP \
        --endpoint-type PUBLIC \
        --tags Key=Environment,Value=Development Key=Purpose,Value=SecureFileSharing \
        --query 'ServerId' --output text)
    
    log "Waiting for Transfer Family server to come online..."
    aws transfer wait server-online --server-id ${SERVER_ID}
    
    success "Transfer Family server created: $SERVER_ID"
}

# Create Transfer Family web app
create_web_app() {
    log "Creating Transfer Family web app..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Transfer Family web app"
        return 0
    fi
    
    # Create web app
    export WEBAPP_ID=$(aws transfer create-web-app \
        --identity-provider-type SERVICE_MANAGED \
        --access-endpoint-type PUBLIC \
        --web-app-units 1 \
        --tags Key=Environment,Value=Development Key=Purpose,Value=SecureFileSharing \
        --query 'WebAppId' --output text)
    
    log "Waiting for web app to become available..."
    aws transfer wait web-app-available --web-app-id ${WEBAPP_ID} || {
        warning "Web app wait command may not be available in your AWS CLI version"
        log "Checking web app status manually..."
        for i in {1..30}; do
            STATUS=$(aws transfer describe-web-app --web-app-id ${WEBAPP_ID} --query 'WebApp.State' --output text)
            if [[ "$STATUS" == "AVAILABLE" ]]; then
                break
            fi
            log "Web app status: $STATUS (attempt $i/30)"
            sleep 10
        done
    }
    
    # Get web app endpoint
    export WEBAPP_ENDPOINT=$(aws transfer describe-web-app \
        --web-app-id ${WEBAPP_ID} \
        --query 'WebApp.AccessEndpoint' --output text)
    
    success "Transfer Family web app created: $WEBAPP_ENDPOINT"
}

# Create user for web app access
create_transfer_user() {
    log "Creating Transfer Family user: $USER_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Transfer Family user: $USER_NAME"
        return 0
    fi
    
    # Create user
    aws transfer create-user \
        --server-id ${SERVER_ID} \
        --user-name ${USER_NAME} \
        --role ${ROLE_ARN} \
        --home-directory /${BUCKET_NAME} \
        --home-directory-type LOGICAL \
        --home-directory-mappings \
        "Entry=\"/\",Target=\"/${BUCKET_NAME}\"" \
        --tags Key=Department,Value=IT Key=AccessLevel,Value=Standard
    
    success "Transfer Family user created: $USER_NAME"
}

# Create sample files and directory structure
create_sample_content() {
    log "Creating sample files and directory structure..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create sample files"
        return 0
    fi
    
    # Create temporary directory for sample files
    mkdir -p /tmp/test-files/{uploads,shared,archive}
    
    # Create sample files
    echo "Welcome to Secure File Sharing Portal" > /tmp/test-files/welcome.txt
    echo "Sample document for testing upload functionality - Created $(date)" > /tmp/test-files/uploads/sample.txt
    echo "Shared resource document for collaboration - Created $(date)" > /tmp/test-files/shared/resource.txt
    echo "Archived document for long-term storage - Created $(date)" > /tmp/test-files/archive/archive.txt
    
    # Upload sample files to S3
    aws s3 cp /tmp/test-files/ s3://${BUCKET_NAME}/ --recursive
    
    # Create lifecycle policy for archive folder
    cat > /tmp/lifecycle-policy.json << EOF
{
    "Rules": [
        {
            "ID": "ArchiveRule",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "archive/"
            },
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }
            ]
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket ${BUCKET_NAME} \
        --lifecycle-configuration file:///tmp/lifecycle-policy.json
    
    # Clean up temporary files
    rm -rf /tmp/test-files /tmp/lifecycle-policy.json
    
    success "Sample files uploaded with lifecycle policies configured"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    # Update configuration with all resource IDs
    cat >> .deployment-config << EOF
IDENTITY_CENTER_ARN=$IDENTITY_CENTER_ARN
IDENTITY_STORE_ID=$IDENTITY_STORE_ID
USER_ID=$USER_ID
ROLE_ARN=$ROLE_ARN
SERVER_ID=$SERVER_ID
WEBAPP_ID=$WEBAPP_ID
WEBAPP_ENDPOINT=$WEBAPP_ENDPOINT
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    # Create summary file
    cat > deployment-summary.txt << EOF
===================================
Secure File Sharing Deployment Summary
===================================
Deployment Date: $(date)
AWS Region: $AWS_REGION
AWS Account: $AWS_ACCOUNT_ID

Resources Created:
- S3 Bucket: $BUCKET_NAME
- IAM Role: $ROLE_NAME
- CloudTrail: $TRAIL_NAME
- Transfer Server: $SERVER_ID
- Web App: $WEBAPP_ID
- Web App URL: $WEBAPP_ENDPOINT
- Test User: $USER_NAME

Next Steps:
1. Access the web app at: $WEBAPP_ENDPOINT
2. Use test user credentials to log in
3. Upload and manage files through the web interface
4. Monitor activities through CloudTrail logs

Cleanup:
Run ./destroy.sh to remove all resources
===================================
EOF
    
    success "Deployment information saved to deployment-summary.txt"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    local validation_errors=0
    
    # Check S3 bucket
    if ! aws s3api head-bucket --bucket "$BUCKET_NAME" &>/dev/null; then
        error "S3 bucket validation failed: $BUCKET_NAME"
        ((validation_errors++))
    fi
    
    # Check IAM role
    if ! aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        error "IAM role validation failed: $ROLE_NAME"
        ((validation_errors++))
    fi
    
    # Check CloudTrail
    TRAIL_STATUS=$(aws cloudtrail get-trail-status --name ${TRAIL_NAME} --query 'IsLogging' --output text 2>/dev/null)
    if [[ "$TRAIL_STATUS" != "True" ]]; then
        error "CloudTrail validation failed: $TRAIL_NAME"
        ((validation_errors++))
    fi
    
    # Check Transfer server
    SERVER_STATE=$(aws transfer describe-server --server-id ${SERVER_ID} --query 'Server.State' --output text 2>/dev/null)
    if [[ "$SERVER_STATE" != "ONLINE" ]]; then
        error "Transfer server validation failed: $SERVER_ID (State: $SERVER_STATE)"
        ((validation_errors++))
    fi
    
    # Check web app
    WEBAPP_STATE=$(aws transfer describe-web-app --web-app-id ${WEBAPP_ID} --query 'WebApp.State' --output text 2>/dev/null)
    if [[ "$WEBAPP_STATE" != "AVAILABLE" ]]; then
        error "Web app validation failed: $WEBAPP_ID (State: $WEBAPP_STATE)"
        ((validation_errors++))
    fi
    
    # Check Transfer user
    if ! aws transfer describe-user --server-id ${SERVER_ID} --user-name ${USER_NAME} &>/dev/null; then
        error "Transfer user validation failed: $USER_NAME"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        success "All resources validated successfully"
        return 0
    else
        error "Validation failed with $validation_errors errors"
        return 1
    fi
}

# Display deployment summary
show_summary() {
    log "Deployment Summary:"
    echo ""
    echo "🔗 Web App URL: $WEBAPP_ENDPOINT"
    echo "🏢 Test User: $USER_NAME"
    echo "📦 S3 Bucket: $BUCKET_NAME"
    echo "🛡️  CloudTrail: $TRAIL_NAME"
    echo "🔧 Transfer Server: $SERVER_ID"
    echo ""
    echo "📋 Next Steps:"
    echo "1. Access the web app and configure user authentication"
    echo "2. Test file upload and download functionality"
    echo "3. Review CloudTrail logs for audit purposes"
    echo "4. Configure additional security settings as needed"
    echo ""
    echo "📁 Configuration saved to: .deployment-config"
    echo "📝 Summary saved to: deployment-summary.txt"
}

# Main deployment function
main() {
    log "Starting deployment of Secure File Sharing with AWS Transfer Family Web Apps"
    
    check_prerequisites
    initialize_environment
    
    if [[ "$DRY_RUN" != "true" ]]; then
        check_existing_resources
    fi
    
    create_s3_bucket
    setup_identity_center
    create_iam_role
    create_cloudtrail
    create_transfer_server
    create_web_app
    create_transfer_user
    create_sample_content
    
    if [[ "$DRY_RUN" != "true" ]]; then
        save_deployment_info
        validate_deployment
    fi
    
    show_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Dry run completed successfully"
    else
        success "Deployment completed successfully!"
    fi
}

# Error handling
trap 'error "Deployment failed at line $LINENO"' ERR

# Run main function
main "$@"