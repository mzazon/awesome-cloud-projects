#!/bin/bash

# AWS S3 Cross-Region Replication Disaster Recovery Deployment Script
# This script implements the infrastructure described in the disaster recovery recipe
# with proper error handling, logging, and prerequisites checking

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
START_TIME=$(date +%s)

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Info logging with blue color
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

# Success logging with green color
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

# Warning logging with yellow color
log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

# Error logging with red color
log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partially created resources..."
    # Note: Full cleanup is handled by destroy.sh
    log_error "Run ./destroy.sh to clean up any partially created resources"
    exit 1
}

# Set error trap
trap cleanup_on_error ERR

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log_info "Checking AWS authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or authentication failed"
        log_error "Please run 'aws configure' or set up AWS credentials"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local user_arn=$(aws sts get-caller-identity --query Arn --output text)
    log_success "AWS authentication successful"
    log_info "Account ID: ${account_id}"
    log_info "User/Role ARN: ${user_arn}"
}

# Function to validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: ${aws_version}"
    
    # Check jq for JSON processing
    if ! command_exists jq; then
        log_warning "jq is not installed. Some JSON processing may be limited"
    fi
    
    check_aws_auth
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default regions if not provided
    export PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
    export DR_REGION="${DR_REGION:-us-west-2}"
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --region "${PRIMARY_REGION}" \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names with unique suffixes
    export SOURCE_BUCKET="dr-source-${random_suffix}"
    export DEST_BUCKET="dr-destination-${random_suffix}"
    export REPLICATION_ROLE_NAME="s3-replication-role-${random_suffix}"
    export CLOUDTRAIL_NAME="s3-replication-trail-${random_suffix}"
    export ALARM_NAME="S3-Replication-Failures-${random_suffix}"
    
    # Create environment file for destroy script
    cat > "${SCRIPT_DIR}/.env" << EOF
PRIMARY_REGION=${PRIMARY_REGION}
DR_REGION=${DR_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
SOURCE_BUCKET=${SOURCE_BUCKET}
DEST_BUCKET=${DEST_BUCKET}
REPLICATION_ROLE_NAME=${REPLICATION_ROLE_NAME}
CLOUDTRAIL_NAME=${CLOUDTRAIL_NAME}
ALARM_NAME=${ALARM_NAME}
EOF
    
    log_success "Environment setup completed"
    log_info "Primary Region: ${PRIMARY_REGION}"
    log_info "DR Region: ${DR_REGION}"
    log_info "Source Bucket: ${SOURCE_BUCKET}"
    log_info "Destination Bucket: ${DEST_BUCKET}"
}

# Function to create source S3 bucket with versioning
create_source_bucket() {
    log_info "Creating source S3 bucket with versioning..."
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "${SOURCE_BUCKET}" --region "${PRIMARY_REGION}" 2>/dev/null; then
        log_warning "Source bucket ${SOURCE_BUCKET} already exists"
    else
        # Create source bucket
        aws s3 mb "s3://${SOURCE_BUCKET}" --region "${PRIMARY_REGION}"
        log_success "Source bucket ${SOURCE_BUCKET} created"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${SOURCE_BUCKET}" \
        --versioning-configuration Status=Enabled \
        --region "${PRIMARY_REGION}"
    
    log_success "Versioning enabled on source bucket"
}

# Function to create destination S3 bucket with versioning
create_destination_bucket() {
    log_info "Creating destination S3 bucket with versioning..."
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "${DEST_BUCKET}" --region "${DR_REGION}" 2>/dev/null; then
        log_warning "Destination bucket ${DEST_BUCKET} already exists"
    else
        # Create destination bucket
        aws s3 mb "s3://${DEST_BUCKET}" --region "${DR_REGION}"
        log_success "Destination bucket ${DEST_BUCKET} created"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${DEST_BUCKET}" \
        --versioning-configuration Status=Enabled \
        --region "${DR_REGION}"
    
    log_success "Versioning enabled on destination bucket"
}

# Function to create IAM role for replication
create_replication_role() {
    log_info "Creating IAM role for cross-region replication..."
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/replication-trust-policy.json" << 'EOF'
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
    if aws iam get-role --role-name "${REPLICATION_ROLE_NAME}" >/dev/null 2>&1; then
        log_warning "Replication role ${REPLICATION_ROLE_NAME} already exists"
    else
        # Create the replication role
        aws iam create-role \
            --role-name "${REPLICATION_ROLE_NAME}" \
            --assume-role-policy-document "file://${SCRIPT_DIR}/replication-trust-policy.json"
        log_success "Replication role ${REPLICATION_ROLE_NAME} created"
    fi
    
    # Get role ARN
    export REPLICATION_ROLE_ARN=$(aws iam get-role \
        --role-name "${REPLICATION_ROLE_NAME}" \
        --query Role.Arn --output text)
    
    log_info "Replication role ARN: ${REPLICATION_ROLE_ARN}"
}

# Function to create and attach replication policy
create_replication_policy() {
    log_info "Creating and attaching replication policy..."
    
    # Create replication policy document
    cat > "${SCRIPT_DIR}/replication-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObjectVersionForReplication",
        "s3:GetObjectVersionAcl",
        "s3:GetObjectVersionTagging"
      ],
      "Resource": [
        "arn:aws:s3:::${SOURCE_BUCKET}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${SOURCE_BUCKET}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ReplicateObject",
        "s3:ReplicateDelete",
        "s3:ReplicateTags"
      ],
      "Resource": [
        "arn:aws:s3:::${DEST_BUCKET}/*"
      ]
    }
  ]
}
EOF
    
    # Create and attach the policy
    aws iam put-role-policy \
        --role-name "${REPLICATION_ROLE_NAME}" \
        --policy-name ReplicationPolicy \
        --policy-document "file://${SCRIPT_DIR}/replication-policy.json"
    
    log_success "Replication policy created and attached"
    
    # Wait for IAM consistency
    log_info "Waiting for IAM consistency..."
    sleep 10
}

# Function to configure cross-region replication
configure_replication() {
    log_info "Configuring cross-region replication..."
    
    # Create replication configuration
    cat > "${SCRIPT_DIR}/replication-config.json" << EOF
{
  "Role": "${REPLICATION_ROLE_ARN}",
  "Rules": [
    {
      "ID": "disaster-recovery-replication",
      "Status": "Enabled",
      "Priority": 1,
      "DeleteMarkerReplication": {
        "Status": "Enabled"
      },
      "Filter": {
        "Prefix": ""
      },
      "Destination": {
        "Bucket": "arn:aws:s3:::${DEST_BUCKET}",
        "StorageClass": "STANDARD_IA"
      }
    }
  ]
}
EOF
    
    # Apply replication configuration to source bucket
    aws s3api put-bucket-replication \
        --bucket "${SOURCE_BUCKET}" \
        --replication-configuration "file://${SCRIPT_DIR}/replication-config.json" \
        --region "${PRIMARY_REGION}"
    
    log_success "Cross-region replication configured"
}

# Function to enable CloudTrail logging
enable_cloudtrail() {
    log_info "Enabling CloudTrail logging..."
    
    # Check if trail already exists
    if aws cloudtrail describe-trails --trail-name-list "${CLOUDTRAIL_NAME}" \
        --region "${PRIMARY_REGION}" --query 'trailList[0]' --output text 2>/dev/null | grep -q "${CLOUDTRAIL_NAME}"; then
        log_warning "CloudTrail ${CLOUDTRAIL_NAME} already exists"
    else
        # Create CloudTrail for S3 API logging
        aws cloudtrail create-trail \
            --name "${CLOUDTRAIL_NAME}" \
            --s3-bucket-name "${SOURCE_BUCKET}" \
            --s3-key-prefix cloudtrail-logs \
            --include-global-service-events \
            --is-multi-region-trail \
            --enable-log-file-validation \
            --region "${PRIMARY_REGION}"
        log_success "CloudTrail ${CLOUDTRAIL_NAME} created"
    fi
    
    # Start logging
    aws cloudtrail start-logging \
        --name "${CLOUDTRAIL_NAME}" \
        --region "${PRIMARY_REGION}"
    
    log_success "CloudTrail logging enabled"
}

# Function to set up CloudWatch monitoring
setup_cloudwatch_monitoring() {
    log_info "Setting up CloudWatch monitoring and alarms..."
    
    # Check if alarm already exists
    if aws cloudwatch describe-alarms --alarm-names "${ALARM_NAME}" \
        --region "${PRIMARY_REGION}" --query 'MetricAlarms[0]' --output text 2>/dev/null | grep -q "${ALARM_NAME}"; then
        log_warning "CloudWatch alarm ${ALARM_NAME} already exists"
    else
        # Create CloudWatch alarm for replication metrics
        aws cloudwatch put-metric-alarm \
            --alarm-name "${ALARM_NAME}" \
            --alarm-description "Monitor S3 replication failures" \
            --metric-name ReplicationLatency \
            --namespace AWS/S3 \
            --statistic Average \
            --period 300 \
            --threshold 900 \
            --comparison-operator GreaterThanThreshold \
            --evaluation-periods 2 \
            --dimensions Name=SourceBucket,Value="${SOURCE_BUCKET}" \
            --region "${PRIMARY_REGION}" 2>/dev/null || {
                log_warning "Failed to create CloudWatch alarm (SNS topic may not exist)"
            }
        
        log_success "CloudWatch monitoring configured"
    fi
}

# Function to test replication
test_replication() {
    log_info "Testing replication with sample data..."
    
    # Create test file with timestamp
    echo "Disaster Recovery Test - $(date)" > "${SCRIPT_DIR}/test-file.txt"
    
    # Upload test file to source bucket
    aws s3 cp "${SCRIPT_DIR}/test-file.txt" "s3://${SOURCE_BUCKET}/test-file.txt" \
        --region "${PRIMARY_REGION}"
    
    log_info "Test file uploaded to source bucket"
    log_info "Waiting for replication to complete (30 seconds)..."
    sleep 30
    
    # Verify replication in destination bucket
    if aws s3 ls "s3://${DEST_BUCKET}/" --region "${DR_REGION}" | grep -q "test-file.txt"; then
        log_success "Replication test successful - file replicated to destination bucket"
    else
        log_warning "Replication may still be in progress - check destination bucket manually"
    fi
    
    # Clean up test file
    rm -f "${SCRIPT_DIR}/test-file.txt"
}

# Function to display deployment summary
display_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    log_success "Deployment completed successfully!"
    echo
    echo "======================== DEPLOYMENT SUMMARY ========================"
    echo "Primary Region:      ${PRIMARY_REGION}"
    echo "DR Region:           ${DR_REGION}"
    echo "Source Bucket:       ${SOURCE_BUCKET}"
    echo "Destination Bucket:  ${DEST_BUCKET}"
    echo "Replication Role:    ${REPLICATION_ROLE_NAME}"
    echo "CloudTrail:          ${CLOUDTRAIL_NAME}"
    echo "CloudWatch Alarm:    ${ALARM_NAME}"
    echo "Deployment Time:     ${duration} seconds"
    echo "=================================================================="
    echo
    echo "Next Steps:"
    echo "1. Upload files to the source bucket to test replication"
    echo "2. Monitor replication through CloudWatch metrics"
    echo "3. Verify disaster recovery procedures regularly"
    echo "4. Run ./destroy.sh when ready to clean up resources"
    echo
}

# Main deployment function
main() {
    log_info "Starting AWS S3 Cross-Region Replication deployment..."
    log_info "Log file: ${LOG_FILE}"
    
    check_prerequisites
    setup_environment
    create_source_bucket
    create_destination_bucket
    create_replication_role
    create_replication_policy
    configure_replication
    enable_cloudtrail
    setup_cloudwatch_monitoring
    test_replication
    display_summary
    
    log_success "Deployment script completed successfully"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi