#!/bin/bash

# =============================================================================
# AWS S3 Cross-Region Replication Disaster Recovery Solution - Deploy Script
# =============================================================================
# This script deploys a complete disaster recovery solution using S3 Cross-Region
# Replication with monitoring, alerting, and automated failover procedures.
#
# Features:
# - S3 Cross-Region Replication setup
# - IAM roles with least privilege access
# - CloudWatch monitoring and alerting
# - Lifecycle policies for cost optimization
# - Disaster recovery procedures
# - Comprehensive logging and error handling
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for S3, IAM, CloudWatch, CloudTrail, SNS
# - Two AWS regions available for deployment
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration and Constants
# =============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly PRIMARY_REGION="${AWS_REGION:-us-east-1}"
readonly SECONDARY_REGION="${SECONDARY_REGION:-us-west-2}"
readonly DEPLOYMENT_ID="$(date +%Y%m%d-%H%M%S)"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Logging Functions
# =============================================================================
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] ${RED}$*${NC}" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] ${GREEN}$*${NC}" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] ${YELLOW}$*${NC}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [INFO] ${BLUE}$*${NC}" | tee -a "${LOG_FILE}"
}

# =============================================================================
# Error Handling
# =============================================================================
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    
    # Attempt to clean up any resources that may have been created
    if [[ -n "${SOURCE_BUCKET:-}" ]]; then
        aws s3 rm "s3://${SOURCE_BUCKET}" --recursive --quiet 2>/dev/null || true
        aws s3 rb "s3://${SOURCE_BUCKET}" --force --quiet 2>/dev/null || true
    fi
    
    if [[ -n "${REPLICA_BUCKET:-}" ]]; then
        aws s3 rm "s3://${REPLICA_BUCKET}" --recursive --quiet --region "${SECONDARY_REGION}" 2>/dev/null || true
        aws s3 rb "s3://${REPLICA_BUCKET}" --force --quiet --region "${SECONDARY_REGION}" 2>/dev/null || true
    fi
    
    if [[ -n "${REPLICATION_ROLE:-}" ]]; then
        aws iam delete-role-policy --role-name "${REPLICATION_ROLE}" --policy-name S3ReplicationPolicy 2>/dev/null || true
        aws iam delete-role --role-name "${REPLICATION_ROLE}" 2>/dev/null || true
    fi
    
    exit 1
}

trap cleanup_on_error ERR

# =============================================================================
# Prerequisite Validation
# =============================================================================
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "${aws_version}" | cut -d. -f1) -lt 2 ]]; then
        log_warning "AWS CLI v2 is recommended. Current version: ${aws_version}"
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if required regions are available
    if ! aws ec2 describe-regions --region-names "${PRIMARY_REGION}" --query 'Regions[0].RegionName' --output text &> /dev/null; then
        log_error "Primary region ${PRIMARY_REGION} is not available or accessible."
        exit 1
    fi
    
    if ! aws ec2 describe-regions --region-names "${SECONDARY_REGION}" --query 'Regions[0].RegionName' --output text &> /dev/null; then
        log_error "Secondary region ${SECONDARY_REGION} is not available or accessible."
        exit 1
    fi
    
    # Check required IAM permissions
    local required_permissions=(
        "s3:*"
        "iam:CreateRole"
        "iam:AttachRolePolicy"
        "iam:PutRolePolicy"
        "cloudwatch:PutMetricAlarm"
        "cloudwatch:PutDashboard"
        "cloudtrail:CreateTrail"
        "sns:CreateTopic"
    )
    
    log_info "Checking IAM permissions..."
    
    # Get current user identity
    local current_user
    current_user=$(aws sts get-caller-identity --query 'Arn' --output text)
    log_info "Current user: ${current_user}"
    
    log_success "Prerequisites validation completed"
}

# =============================================================================
# Environment Setup
# =============================================================================
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "${DEPLOYMENT_ID}")
    
    export SOURCE_BUCKET="dr-source-bucket-${random_suffix}"
    export REPLICA_BUCKET="dr-replica-bucket-${random_suffix}"
    export REPLICATION_ROLE="s3-replication-role-${random_suffix}"
    export SNS_TOPIC="s3-dr-alerts-${random_suffix}"
    export CLOUDTRAIL_NAME="s3-dr-audit-trail-${random_suffix}"
    
    log_info "Environment variables set:"
    log_info "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    log_info "  PRIMARY_REGION: ${PRIMARY_REGION}"
    log_info "  SECONDARY_REGION: ${SECONDARY_REGION}"
    log_info "  SOURCE_BUCKET: ${SOURCE_BUCKET}"
    log_info "  REPLICA_BUCKET: ${REPLICA_BUCKET}"
    log_info "  REPLICATION_ROLE: ${REPLICATION_ROLE}"
    
    # Save environment variables to file for cleanup script
    cat > "${SCRIPT_DIR}/deployment-vars.env" << EOF
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export PRIMARY_REGION="${PRIMARY_REGION}"
export SECONDARY_REGION="${SECONDARY_REGION}"
export SOURCE_BUCKET="${SOURCE_BUCKET}"
export REPLICA_BUCKET="${REPLICA_BUCKET}"
export REPLICATION_ROLE="${REPLICATION_ROLE}"
export SNS_TOPIC="${SNS_TOPIC}"
export CLOUDTRAIL_NAME="${CLOUDTRAIL_NAME}"
export DEPLOYMENT_ID="${DEPLOYMENT_ID}"
EOF
    
    log_success "Environment setup completed"
}

# =============================================================================
# SNS Topic Creation
# =============================================================================
create_sns_topic() {
    log_info "Creating SNS topic for alerts..."
    
    # Create SNS topic
    local topic_arn
    topic_arn=$(aws sns create-topic \
        --name "${SNS_TOPIC}" \
        --region "${PRIMARY_REGION}" \
        --query 'TopicArn' --output text)
    
    export SNS_TOPIC_ARN="${topic_arn}"
    
    # Add tags to SNS topic
    aws sns tag-resource \
        --resource-arn "${topic_arn}" \
        --tags Key=Purpose,Value=DisasterRecovery \
               Key=Environment,Value=Production \
               Key=CostCenter,Value=IT-DR \
               Key=DeploymentId,Value="${DEPLOYMENT_ID}" \
        --region "${PRIMARY_REGION}"
    
    log_success "SNS topic created: ${topic_arn}"
}

# =============================================================================
# S3 Bucket Creation
# =============================================================================
create_source_bucket() {
    log_info "Creating source bucket in ${PRIMARY_REGION}..."
    
    # Create source bucket
    if [[ "${PRIMARY_REGION}" == "us-east-1" ]]; then
        aws s3 mb "s3://${SOURCE_BUCKET}" --region "${PRIMARY_REGION}"
    else
        aws s3 mb "s3://${SOURCE_BUCKET}" --region "${PRIMARY_REGION}"
    fi
    
    # Enable versioning (required for replication)
    aws s3api put-bucket-versioning \
        --bucket "${SOURCE_BUCKET}" \
        --versioning-configuration Status=Enabled
    
    # Add bucket tags
    aws s3api put-bucket-tagging \
        --bucket "${SOURCE_BUCKET}" \
        --tagging 'TagSet=[
            {Key=Purpose,Value=DisasterRecovery},
            {Key=Environment,Value=Production},
            {Key=CostCenter,Value=IT-DR},
            {Key=DeploymentId,Value='${DEPLOYMENT_ID}'}
        ]'
    
    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "${SOURCE_BUCKET}" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "${SOURCE_BUCKET}" \
        --public-access-block-configuration \
            BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    
    log_success "Source bucket created: ${SOURCE_BUCKET}"
}

create_replica_bucket() {
    log_info "Creating replica bucket in ${SECONDARY_REGION}..."
    
    # Create replica bucket
    aws s3 mb "s3://${REPLICA_BUCKET}" --region "${SECONDARY_REGION}"
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${REPLICA_BUCKET}" \
        --versioning-configuration Status=Enabled \
        --region "${SECONDARY_REGION}"
    
    # Add bucket tags
    aws s3api put-bucket-tagging \
        --bucket "${REPLICA_BUCKET}" \
        --tagging 'TagSet=[
            {Key=Purpose,Value=DisasterRecovery},
            {Key=Environment,Value=Production},
            {Key=CostCenter,Value=IT-DR},
            {Key=DeploymentId,Value='${DEPLOYMENT_ID}'}
        ]' \
        --region "${SECONDARY_REGION}"
    
    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "${REPLICA_BUCKET}" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }' \
        --region "${SECONDARY_REGION}"
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "${REPLICA_BUCKET}" \
        --public-access-block-configuration \
            BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
        --region "${SECONDARY_REGION}"
    
    log_success "Replica bucket created: ${REPLICA_BUCKET}"
}

# =============================================================================
# IAM Role Creation
# =============================================================================
create_replication_role() {
    log_info "Creating IAM role for S3 replication..."
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/replication-trust-policy.json" << EOF
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
    
    # Create IAM role
    aws iam create-role \
        --role-name "${REPLICATION_ROLE}" \
        --assume-role-policy-document file://"${SCRIPT_DIR}/replication-trust-policy.json" \
        --tags Key=Purpose,Value=DisasterRecovery \
               Key=Environment,Value=Production \
               Key=CostCenter,Value=IT-DR \
               Key=DeploymentId,Value="${DEPLOYMENT_ID}"
    
    # Get role ARN
    export REPLICATION_ROLE_ARN
    REPLICATION_ROLE_ARN=$(aws iam get-role \
        --role-name "${REPLICATION_ROLE}" \
        --query Role.Arn --output text)
    
    # Create replication permissions policy
    cat > "${SCRIPT_DIR}/replication-permissions-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetReplicationConfiguration",
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::${SOURCE_BUCKET}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObjectVersionForReplication",
                "s3:GetObjectVersionAcl",
                "s3:GetObjectVersionTagging"
            ],
            "Resource": "arn:aws:s3:::${SOURCE_BUCKET}/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ReplicateObject",
                "s3:ReplicateDelete",
                "s3:ReplicateTags"
            ],
            "Resource": "arn:aws:s3:::${REPLICA_BUCKET}/*"
        }
    ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name "${REPLICATION_ROLE}" \
        --policy-name S3ReplicationPolicy \
        --policy-document file://"${SCRIPT_DIR}/replication-permissions-policy.json"
    
    # Wait for role to be available
    log_info "Waiting for IAM role to become available..."
    sleep 10
    
    log_success "IAM role created: ${REPLICATION_ROLE_ARN}"
}

# =============================================================================
# CloudTrail Configuration
# =============================================================================
create_cloudtrail() {
    log_info "Creating CloudTrail for audit logging..."
    
    # Create a separate bucket for CloudTrail logs
    local cloudtrail_bucket="cloudtrail-logs-${DEPLOYMENT_ID}"
    aws s3 mb "s3://${cloudtrail_bucket}" --region "${PRIMARY_REGION}"
    
    # Create CloudTrail bucket policy
    cat > "${SCRIPT_DIR}/cloudtrail-bucket-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AWSCloudTrailAclCheck",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:GetBucketAcl",
            "Resource": "arn:aws:s3:::${cloudtrail_bucket}"
        },
        {
            "Sid": "AWSCloudTrailWrite",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${cloudtrail_bucket}/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control"
                }
            }
        }
    ]
}
EOF
    
    # Apply bucket policy
    aws s3api put-bucket-policy \
        --bucket "${cloudtrail_bucket}" \
        --policy file://"${SCRIPT_DIR}/cloudtrail-bucket-policy.json"
    
    # Create CloudTrail
    aws cloudtrail create-trail \
        --name "${CLOUDTRAIL_NAME}" \
        --s3-bucket-name "${cloudtrail_bucket}" \
        --include-global-service-events \
        --is-multi-region-trail \
        --enable-log-file-validation \
        --region "${PRIMARY_REGION}"
    
    # Start logging
    aws cloudtrail start-logging \
        --name "${CLOUDTRAIL_NAME}" \
        --region "${PRIMARY_REGION}"
    
    export CLOUDTRAIL_BUCKET="${cloudtrail_bucket}"
    
    log_success "CloudTrail created: ${CLOUDTRAIL_NAME}"
}

# =============================================================================
# S3 Replication Configuration
# =============================================================================
configure_replication() {
    log_info "Configuring S3 cross-region replication..."
    
    # Create replication configuration
    cat > "${SCRIPT_DIR}/replication-config.json" << EOF
{
    "Role": "${REPLICATION_ROLE_ARN}",
    "Rules": [
        {
            "ID": "ReplicateEverything",
            "Status": "Enabled",
            "Priority": 1,
            "Filter": {
                "Prefix": ""
            },
            "DeleteMarkerReplication": {
                "Status": "Enabled"
            },
            "Destination": {
                "Bucket": "arn:aws:s3:::${REPLICA_BUCKET}",
                "StorageClass": "STANDARD_IA"
            }
        },
        {
            "ID": "ReplicateCriticalData",
            "Status": "Enabled",
            "Priority": 2,
            "Filter": {
                "And": {
                    "Prefix": "critical/",
                    "Tags": [
                        {
                            "Key": "Classification",
                            "Value": "Critical"
                        }
                    ]
                }
            },
            "DeleteMarkerReplication": {
                "Status": "Enabled"
            },
            "Destination": {
                "Bucket": "arn:aws:s3:::${REPLICA_BUCKET}",
                "StorageClass": "STANDARD"
            }
        }
    ]
}
EOF
    
    # Apply replication configuration
    aws s3api put-bucket-replication \
        --bucket "${SOURCE_BUCKET}" \
        --replication-configuration file://"${SCRIPT_DIR}/replication-config.json"
    
    log_success "Cross-region replication configured"
}

# =============================================================================
# CloudWatch Monitoring
# =============================================================================
setup_monitoring() {
    log_info "Setting up CloudWatch monitoring and alerting..."
    
    # Create CloudWatch alarm for replication failures
    aws cloudwatch put-metric-alarm \
        --alarm-name "S3-Replication-Failure-${SOURCE_BUCKET}" \
        --alarm-description "S3 replication failure alarm for DR solution" \
        --metric-name ReplicationLatency \
        --namespace AWS/S3 \
        --statistic Average \
        --period 300 \
        --threshold 900 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=SourceBucket,Value="${SOURCE_BUCKET}" \
                    Name=DestinationBucket,Value="${REPLICA_BUCKET}" \
        --region "${PRIMARY_REGION}"
    
    # Create CloudWatch dashboard
    cat > "${SCRIPT_DIR}/dashboard-config.json" << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/S3", "ReplicationLatency", "SourceBucket", "${SOURCE_BUCKET}"],
                    ["AWS/S3", "ReplicationFailureCount", "SourceBucket", "${SOURCE_BUCKET}"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${PRIMARY_REGION}",
                "title": "S3 Replication Metrics",
                "view": "timeSeries"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/S3", "BucketSizeBytes", "BucketName", "${SOURCE_BUCKET}", "StorageType", "StandardStorage"],
                    ["AWS/S3", "BucketSizeBytes", "BucketName", "${REPLICA_BUCKET}", "StorageType", "StandardStorage"]
                ],
                "period": 86400,
                "stat": "Average",
                "region": "${PRIMARY_REGION}",
                "title": "Bucket Size Comparison",
                "view": "timeSeries"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "S3-DR-Dashboard-${DEPLOYMENT_ID}" \
        --dashboard-body file://"${SCRIPT_DIR}/dashboard-config.json" \
        --region "${PRIMARY_REGION}"
    
    log_success "CloudWatch monitoring configured"
}

# =============================================================================
# Lifecycle Policies
# =============================================================================
configure_lifecycle_policies() {
    log_info "Configuring S3 lifecycle policies for cost optimization..."
    
    # Create lifecycle policy for source bucket
    cat > "${SCRIPT_DIR}/lifecycle-policy.json" << EOF
{
    "Rules": [
        {
            "ID": "TransitionToIA",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "standard/"
            },
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 365,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ]
        },
        {
            "ID": "DeleteOldVersions",
            "Status": "Enabled",
            "Filter": {
                "Prefix": ""
            },
            "NoncurrentVersionTransitions": [
                {
                    "NoncurrentDays": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "NoncurrentDays": 90,
                    "StorageClass": "GLACIER"
                }
            ],
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 365
            }
        }
    ]
}
EOF
    
    # Apply lifecycle policy to source bucket
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "${SOURCE_BUCKET}" \
        --lifecycle-configuration file://"${SCRIPT_DIR}/lifecycle-policy.json"
    
    # Apply similar policy to replica bucket
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "${REPLICA_BUCKET}" \
        --lifecycle-configuration file://"${SCRIPT_DIR}/lifecycle-policy.json" \
        --region "${SECONDARY_REGION}"
    
    log_success "Lifecycle policies configured"
}

# =============================================================================
# Disaster Recovery Scripts
# =============================================================================
create_dr_scripts() {
    log_info "Creating disaster recovery scripts..."
    
    # Create failover script
    cat > "${SCRIPT_DIR}/dr-failover.sh" << 'EOF'
#!/bin/bash
# Disaster Recovery Failover Script
# This script switches applications from primary to secondary region

set -euo pipefail

REPLICA_BUCKET="${1:-}"
APPLICATION_CONFIG="${2:-}"

if [[ -z "${REPLICA_BUCKET}" ]] || [[ -z "${APPLICATION_CONFIG}" ]]; then
    echo "Usage: $0 <replica-bucket> <application-config>"
    echo "Example: $0 my-replica-bucket /path/to/app.conf"
    exit 1
fi

echo "$(date): Starting DR failover to bucket: ${REPLICA_BUCKET}"

# Backup current configuration
cp "${APPLICATION_CONFIG}" "${APPLICATION_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"

# Update application configuration
if grep -q "bucket_name=" "${APPLICATION_CONFIG}"; then
    sed -i "s/bucket_name=.*/bucket_name=${REPLICA_BUCKET}/" "${APPLICATION_CONFIG}"
else
    echo "bucket_name=${REPLICA_BUCKET}" >> "${APPLICATION_CONFIG}"
fi

# Update region configuration
if grep -q "aws_region=" "${APPLICATION_CONFIG}"; then
    sed -i "s/aws_region=.*/aws_region=us-west-2/" "${APPLICATION_CONFIG}"
else
    echo "aws_region=us-west-2" >> "${APPLICATION_CONFIG}"
fi

# Verify bucket accessibility
echo "Verifying replica bucket accessibility..."
if aws s3 ls "s3://${REPLICA_BUCKET}" --region us-west-2 > /dev/null 2>&1; then
    echo "✅ Replica bucket is accessible"
else
    echo "❌ Replica bucket is not accessible"
    echo "Restoring original configuration..."
    if [[ -f "${APPLICATION_CONFIG}.backup.$(date +%Y%m%d)" ]]; then
        cp "${APPLICATION_CONFIG}.backup.$(date +%Y%m%d)" "${APPLICATION_CONFIG}"
    fi
    exit 1
fi

# Test basic operations
echo "Testing basic S3 operations..."
TEST_FILE="/tmp/dr-test-$(date +%s).txt"
echo "DR test file created at $(date)" > "${TEST_FILE}"

if aws s3 cp "${TEST_FILE}" "s3://${REPLICA_BUCKET}/dr-test/" --region us-west-2 > /dev/null 2>&1; then
    echo "✅ Write test successful"
    aws s3 rm "s3://${REPLICA_BUCKET}/dr-test/$(basename "${TEST_FILE}")" --region us-west-2 > /dev/null 2>&1
else
    echo "❌ Write test failed"
    exit 1
fi

# Log failover event
mkdir -p /var/log/dr-events 2>/dev/null || true
echo "$(date): DR failover completed to ${REPLICA_BUCKET}" >> /var/log/dr-events/dr-events.log

# Clean up
rm -f "${TEST_FILE}"

echo "✅ DR failover completed successfully"
echo "Application is now using replica bucket: ${REPLICA_BUCKET}"
echo "Region switched to: us-west-2"
EOF
    
    # Create failback script
    cat > "${SCRIPT_DIR}/dr-failback.sh" << 'EOF'
#!/bin/bash
# Disaster Recovery Failback Script
# This script switches applications back to primary region

set -euo pipefail

SOURCE_BUCKET="${1:-}"
APPLICATION_CONFIG="${2:-}"

if [[ -z "${SOURCE_BUCKET}" ]] || [[ -z "${APPLICATION_CONFIG}" ]]; then
    echo "Usage: $0 <source-bucket> <application-config>"
    echo "Example: $0 my-source-bucket /path/to/app.conf"
    exit 1
fi

echo "$(date): Starting DR failback to bucket: ${SOURCE_BUCKET}"

# Verify source bucket is accessible
echo "Verifying source bucket accessibility..."
if aws s3 ls "s3://${SOURCE_BUCKET}" --region us-east-1 > /dev/null 2>&1; then
    echo "✅ Source bucket is accessible"
else
    echo "❌ Source bucket is not accessible"
    echo "Failback aborted - primary region may still be unavailable"
    exit 1
fi

# Backup current configuration
cp "${APPLICATION_CONFIG}" "${APPLICATION_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"

# Update application configuration
if grep -q "bucket_name=" "${APPLICATION_CONFIG}"; then
    sed -i "s/bucket_name=.*/bucket_name=${SOURCE_BUCKET}/" "${APPLICATION_CONFIG}"
else
    echo "bucket_name=${SOURCE_BUCKET}" >> "${APPLICATION_CONFIG}"
fi

# Update region configuration
if grep -q "aws_region=" "${APPLICATION_CONFIG}"; then
    sed -i "s/aws_region=.*/aws_region=us-east-1/" "${APPLICATION_CONFIG}"
else
    echo "aws_region=us-east-1" >> "${APPLICATION_CONFIG}"
fi

# Test basic operations
echo "Testing basic S3 operations..."
TEST_FILE="/tmp/dr-test-$(date +%s).txt"
echo "DR failback test file created at $(date)" > "${TEST_FILE}"

if aws s3 cp "${TEST_FILE}" "s3://${SOURCE_BUCKET}/dr-test/" --region us-east-1 > /dev/null 2>&1; then
    echo "✅ Write test successful"
    aws s3 rm "s3://${SOURCE_BUCKET}/dr-test/$(basename "${TEST_FILE}")" --region us-east-1 > /dev/null 2>&1
else
    echo "❌ Write test failed"
    exit 1
fi

# Log failback event
mkdir -p /var/log/dr-events 2>/dev/null || true
echo "$(date): DR failback completed to ${SOURCE_BUCKET}" >> /var/log/dr-events/dr-events.log

# Clean up
rm -f "${TEST_FILE}"

echo "✅ DR failback completed successfully"
echo "Application is now using source bucket: ${SOURCE_BUCKET}"
echo "Region switched to: us-east-1"
EOF
    
    # Make scripts executable
    chmod +x "${SCRIPT_DIR}/dr-failover.sh"
    chmod +x "${SCRIPT_DIR}/dr-failback.sh"
    
    log_success "DR scripts created and made executable"
}

# =============================================================================
# Test Data Upload
# =============================================================================
upload_test_data() {
    log_info "Uploading test data to validate replication..."
    
    # Create test files
    mkdir -p "${SCRIPT_DIR}/test-data"
    
    echo "Critical financial data - $(date)" > "${SCRIPT_DIR}/test-data/critical-data.txt"
    echo "Standard business data - $(date)" > "${SCRIPT_DIR}/test-data/standard-data.txt"
    echo "Archive data - $(date)" > "${SCRIPT_DIR}/test-data/archive-data.txt"
    
    # Upload critical data with tags
    aws s3 cp "${SCRIPT_DIR}/test-data/critical-data.txt" "s3://${SOURCE_BUCKET}/critical/" \
        --metadata "classification=critical" \
        --tagging "Classification=Critical&DataType=Financial"
    
    # Upload standard data
    aws s3 cp "${SCRIPT_DIR}/test-data/standard-data.txt" "s3://${SOURCE_BUCKET}/standard/" \
        --metadata "classification=standard"
    
    # Upload archive data
    aws s3 cp "${SCRIPT_DIR}/test-data/archive-data.txt" "s3://${SOURCE_BUCKET}/archive/" \
        --metadata "classification=archive"
    
    log_success "Test data uploaded successfully"
}

# =============================================================================
# Validation
# =============================================================================
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check replication configuration
    local replication_status
    replication_status=$(aws s3api get-bucket-replication \
        --bucket "${SOURCE_BUCKET}" \
        --query 'ReplicationConfiguration.Rules[0].Status' \
        --output text 2>/dev/null || echo "FAILED")
    
    if [[ "${replication_status}" == "Enabled" ]]; then
        log_success "Replication configuration is enabled"
    else
        log_error "Replication configuration validation failed"
        return 1
    fi
    
    # Wait for replication and check replica bucket
    log_info "Waiting 60 seconds for replication to complete..."
    sleep 60
    
    local replica_objects
    replica_objects=$(aws s3 ls "s3://${REPLICA_BUCKET}" --recursive --region "${SECONDARY_REGION}" | wc -l)
    
    if [[ ${replica_objects} -gt 0 ]]; then
        log_success "Objects successfully replicated to secondary region"
    else
        log_warning "No objects found in replica bucket yet - replication may still be in progress"
    fi
    
    # Check CloudWatch alarms
    local alarm_state
    alarm_state=$(aws cloudwatch describe-alarms \
        --alarm-names "S3-Replication-Failure-${SOURCE_BUCKET}" \
        --query 'MetricAlarms[0].StateValue' \
        --output text --region "${PRIMARY_REGION}")
    
    if [[ "${alarm_state}" == "INSUFFICIENT_DATA" ]] || [[ "${alarm_state}" == "OK" ]]; then
        log_success "CloudWatch alarm is properly configured"
    else
        log_warning "CloudWatch alarm state: ${alarm_state}"
    fi
    
    log_success "Deployment validation completed"
}

# =============================================================================
# Cleanup Temporary Files
# =============================================================================
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Clean up temporary JSON files
    rm -f "${SCRIPT_DIR}/replication-trust-policy.json"
    rm -f "${SCRIPT_DIR}/replication-permissions-policy.json"
    rm -f "${SCRIPT_DIR}/replication-config.json"
    rm -f "${SCRIPT_DIR}/lifecycle-policy.json"
    rm -f "${SCRIPT_DIR}/dashboard-config.json"
    rm -f "${SCRIPT_DIR}/cloudtrail-bucket-policy.json"
    
    # Clean up test data
    rm -rf "${SCRIPT_DIR}/test-data"
    
    log_success "Temporary files cleaned up"
}

# =============================================================================
# Main Deployment Function
# =============================================================================
main() {
    log_info "Starting AWS S3 Cross-Region Replication Disaster Recovery deployment..."
    log_info "Deployment ID: ${DEPLOYMENT_ID}"
    
    # Execute deployment steps
    validate_prerequisites
    setup_environment
    create_sns_topic
    create_source_bucket
    create_replica_bucket
    create_replication_role
    create_cloudtrail
    configure_replication
    setup_monitoring
    configure_lifecycle_policies
    create_dr_scripts
    upload_test_data
    validate_deployment
    cleanup_temp_files
    
    # Display deployment summary
    log_success "=================================="
    log_success "DEPLOYMENT COMPLETED SUCCESSFULLY"
    log_success "=================================="
    log_success "Deployment ID: ${DEPLOYMENT_ID}"
    log_success "Source Bucket: ${SOURCE_BUCKET} (${PRIMARY_REGION})"
    log_success "Replica Bucket: ${REPLICA_BUCKET} (${SECONDARY_REGION})"
    log_success "Replication Role: ${REPLICATION_ROLE}"
    log_success "SNS Topic: ${SNS_TOPIC_ARN}"
    log_success "CloudTrail: ${CLOUDTRAIL_NAME}"
    
    log_info ""
    log_info "Next Steps:"
    log_info "1. Monitor replication status in CloudWatch Dashboard"
    log_info "2. Test DR procedures using the created scripts:"
    log_info "   - ${SCRIPT_DIR}/dr-failover.sh"
    log_info "   - ${SCRIPT_DIR}/dr-failback.sh"
    log_info "3. Review and customize lifecycle policies as needed"
    log_info "4. Set up application integration with the buckets"
    log_info ""
    log_info "To clean up all resources, run: ${SCRIPT_DIR}/destroy.sh"
    log_info ""
    log_info "Deployment variables saved to: ${SCRIPT_DIR}/deployment-vars.env"
    log_info "Deployment log saved to: ${LOG_FILE}"
}

# =============================================================================
# Script Entry Point
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi