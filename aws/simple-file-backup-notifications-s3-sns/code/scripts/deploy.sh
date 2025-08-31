#!/bin/bash

# Deploy script for Simple File Backup Notifications with S3 and SNS
# This script creates an automated notification system for S3 file uploads

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in DRY-RUN mode - no resources will be created"
fi

# Function to run commands (with dry-run support)
run_command() {
    local cmd="$1"
    local description="$2"
    
    log "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
        return 0
    else
        eval "$cmd"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if jq is installed (needed for JSON parsing)
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Installing via package manager if possible..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v brew &> /dev/null; then
            brew install jq
        else
            error "Please install jq manually to continue."
            exit 1
        fi
    fi
    
    success "Prerequisites check completed"
}

# Function to validate email format
validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        error "Invalid email format: $email"
        return 1
    fi
    return 0
}

# Function to setup environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set resource names with unique suffix
    export BUCKET_NAME="backup-notifications-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="backup-alerts-${RANDOM_SUFFIX}"
    
    # Prompt for email address if not provided
    if [[ -z "${EMAIL_ADDRESS:-}" ]]; then
        echo -n "Enter your email address for notifications: "
        read -r EMAIL_ADDRESS
        export EMAIL_ADDRESS
    fi
    
    # Validate email address
    if ! validate_email "$EMAIL_ADDRESS"; then
        exit 1
    fi
    
    success "Environment configured"
    log "AWS Region: ${AWS_REGION}"
    log "AWS Account ID: ${AWS_ACCOUNT_ID}"
    log "Bucket name: ${BUCKET_NAME}"
    log "SNS topic: ${SNS_TOPIC_NAME}"
    log "Email address: ${EMAIL_ADDRESS}"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic for email notifications..."
    
    # Check if topic already exists
    if aws sns get-topic-attributes --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" &>/dev/null; then
        warning "SNS topic ${SNS_TOPIC_NAME} already exists"
        export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    else
        export SNS_TOPIC_ARN=$(run_command \
            "aws sns create-topic --name ${SNS_TOPIC_NAME} --query 'TopicArn' --output text" \
            "Creating SNS topic")
    fi
    
    success "SNS topic created: ${SNS_TOPIC_ARN}"
}

# Function to subscribe email to SNS topic
subscribe_email() {
    log "Subscribing email address to SNS topic..."
    
    # Check if subscription already exists
    EXISTING_SUBSCRIPTION=$(aws sns list-subscriptions-by-topic \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --query "Subscriptions[?Endpoint=='${EMAIL_ADDRESS}'].SubscriptionArn" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$EXISTING_SUBSCRIPTION" && "$EXISTING_SUBSCRIPTION" != "None" ]]; then
        warning "Email subscription already exists for ${EMAIL_ADDRESS}"
    else
        run_command \
            "aws sns subscribe --topic-arn ${SNS_TOPIC_ARN} --protocol email --notification-endpoint ${EMAIL_ADDRESS}" \
            "Creating email subscription"
        
        success "Email subscription created for ${EMAIL_ADDRESS}"
        warning "📧 Check your email and confirm the subscription to receive notifications"
    fi
}

# Function to create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for file storage..."
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        warning "S3 bucket ${BUCKET_NAME} already exists"
    else
        # Create bucket with location constraint if not in us-east-1
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            run_command \
                "aws s3 mb s3://${BUCKET_NAME}" \
                "Creating S3 bucket"
        else
            run_command \
                "aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}" \
                "Creating S3 bucket"
        fi
    fi
    
    # Enable versioning for data protection
    run_command \
        "aws s3api put-bucket-versioning --bucket ${BUCKET_NAME} --versioning-configuration Status=Enabled" \
        "Enabling S3 bucket versioning"
    
    # Enable server-side encryption
    run_command \
        "aws s3api put-bucket-encryption --bucket ${BUCKET_NAME} --server-side-encryption-configuration 'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'" \
        "Enabling S3 server-side encryption"
    
    success "S3 bucket created with security features enabled"
}

# Function to configure SNS topic policy
configure_sns_policy() {
    log "Configuring SNS topic policy for S3 access..."
    
    # Create temporary policy file
    cat > /tmp/sns-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ToPublish",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": "SNS:Publish",
      "Resource": "${SNS_TOPIC_ARN}",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "${AWS_ACCOUNT_ID}"
        },
        "StringLike": {
          "aws:SourceArn": "arn:aws:s3:::${BUCKET_NAME}"
        }
      }
    }
  ]
}
EOF
    
    # Apply the policy to SNS topic
    run_command \
        "aws sns set-topic-attributes --topic-arn ${SNS_TOPIC_ARN} --attribute-name Policy --attribute-value file:///tmp/sns-policy.json" \
        "Applying SNS topic policy"
    
    # Cleanup temporary file
    rm -f /tmp/sns-policy.json
    
    success "SNS topic policy configured for S3 access"
}

# Function to configure S3 event notifications
configure_s3_notifications() {
    log "Configuring S3 event notifications..."
    
    # Create temporary notification configuration file
    cat > /tmp/notification-config.json << EOF
{
  "TopicConfigurations": [
    {
      "Id": "BackupNotification",
      "TopicArn": "${SNS_TOPIC_ARN}",
      "Events": [
        "s3:ObjectCreated:*"
      ]
    }
  ]
}
EOF
    
    # Apply notification configuration to S3 bucket
    run_command \
        "aws s3api put-bucket-notification-configuration --bucket ${BUCKET_NAME} --notification-configuration file:///tmp/notification-config.json" \
        "Configuring S3 event notifications"
    
    # Cleanup temporary file
    rm -f /tmp/notification-config.json
    
    success "S3 event notifications configured"
}

# Function to create test files
create_test_files() {
    log "Creating test files for validation..."
    
    echo "Backup test file created at $(date)" > test-backup-1.txt
    echo "Database backup completed at $(date)" > test-backup-2.txt
    echo "Application logs archived at $(date)" > test-backup-3.txt
    
    success "Test files created for validation"
}

# Function to run validation tests
run_validation_tests() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Skipping validation tests in dry-run mode"
        return 0
    fi
    
    log "Running validation tests..."
    
    # Upload test files to trigger notifications
    aws s3 cp test-backup-1.txt s3://${BUCKET_NAME}/
    aws s3 cp test-backup-2.txt s3://${BUCKET_NAME}/backups/
    aws s3 cp test-backup-3.txt s3://${BUCKET_NAME}/logs/
    
    success "Test files uploaded to S3 bucket"
    
    # List objects in the bucket
    log "Verifying uploaded objects:"
    aws s3 ls s3://${BUCKET_NAME}/ --recursive
    
    # Cleanup test files
    rm -f test-backup-*.txt
    
    success "Validation tests completed"
    warning "📧 You should receive email notifications within 1-2 minutes for each uploaded file"
}

# Function to save deployment information
save_deployment_info() {
    local info_file="deployment-info.json"
    
    cat > "$info_file" << EOF
{
  "deployment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "aws_region": "${AWS_REGION}",
  "aws_account_id": "${AWS_ACCOUNT_ID}",
  "bucket_name": "${BUCKET_NAME}",
  "sns_topic_name": "${SNS_TOPIC_NAME}",
  "sns_topic_arn": "${SNS_TOPIC_ARN}",
  "email_address": "${EMAIL_ADDRESS}",
  "random_suffix": "${RANDOM_SUFFIX}"
}
EOF
    
    success "Deployment information saved to ${info_file}"
}

# Main deployment function
main() {
    log "Starting deployment of Simple File Backup Notifications with S3 and SNS"
    log "========================================="
    
    check_prerequisites
    setup_environment
    create_sns_topic
    subscribe_email
    create_s3_bucket
    configure_sns_policy
    configure_s3_notifications
    create_test_files
    run_validation_tests
    save_deployment_info
    
    log "========================================="
    success "🎉 Deployment completed successfully!"
    log ""
    log "Next steps:"
    log "1. Check your email (${EMAIL_ADDRESS}) and confirm the SNS subscription"
    log "2. Upload files to s3://${BUCKET_NAME}/ to test notifications"
    log "3. Monitor notifications and adjust configuration as needed"
    log ""
    log "To clean up resources, run: ./destroy.sh"
    log "Deployment info saved in: deployment-info.json"
}

# Handle script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        error "Deployment failed. Check the logs above for details."
        log "You may need to manually clean up any partially created resources."
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"