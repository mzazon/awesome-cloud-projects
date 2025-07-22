#!/bin/bash

# =================================================================
# Multi-Region Data Replication with S3 - Deployment Script
# =================================================================
# This script deploys a comprehensive S3 multi-region replication 
# solution with encryption, monitoring, and intelligent tiering.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Administrative permissions for S3, KMS, IAM, CloudWatch
# - Appropriate AWS account permissions
#
# Usage: ./deploy.sh [--dry-run] [--skip-test-data]
# =================================================================

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false
SKIP_TEST_DATA=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-test-data)
            SKIP_TEST_DATA=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--skip-test-data]"
            echo "  --dry-run        Show what would be deployed without making changes"
            echo "  --skip-test-data Skip uploading test data"
            exit 0
            ;;
        *)
            echo "Unknown option $1"
            exit 1
            ;;
    esac
done

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ℹ️  $*" | tee -a "$LOG_FILE"
}

# Initialize log file
echo "==================================================================" > "$LOG_FILE"
echo "Multi-Region S3 Replication Deployment - $(date)" >> "$LOG_FILE"
echo "==================================================================" >> "$LOG_FILE"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ ! $aws_version =~ ^2\. ]]; then
        log_error "AWS CLI v2 is required. Current version: $aws_version"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check required permissions by testing access to required services
    log "Validating AWS permissions..."
    
    # Test S3 access
    if ! aws s3 ls &> /dev/null; then
        log_error "Insufficient S3 permissions"
        exit 1
    fi
    
    # Test KMS access
    if ! aws kms list-keys --limit 1 &> /dev/null; then
        log_error "Insufficient KMS permissions"
        exit 1
    fi
    
    # Test IAM access
    if ! aws iam list-roles --max-items 1 &> /dev/null; then
        log_error "Insufficient IAM permissions"
        exit 1
    fi
    
    # Test CloudWatch access
    if ! aws cloudwatch list-metrics --max-records 1 &> /dev/null; then
        log_error "Insufficient CloudWatch permissions"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set regions
    export PRIMARY_REGION="us-east-1"
    export SECONDARY_REGION="us-west-2"
    export TERTIARY_REGION="eu-west-1"
    
    # Get AWS Account ID
    export AWS_ACCOUNT_ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        openssl rand -hex 4)
    
    # Set resource names
    export SOURCE_BUCKET="multi-region-source-${random_suffix}"
    export DEST_BUCKET_1="multi-region-dest1-${random_suffix}"
    export DEST_BUCKET_2="multi-region-dest2-${random_suffix}"
    export REPLICATION_ROLE="MultiRegionReplicationRole-${random_suffix}"
    export SOURCE_KMS_ALIAS="alias/s3-multi-region-source-${random_suffix}"
    export DEST_KMS_ALIAS_1="alias/s3-multi-region-dest1-${random_suffix}"
    export DEST_KMS_ALIAS_2="alias/s3-multi-region-dest2-${random_suffix}"
    export SNS_TOPIC="s3-replication-alerts-${random_suffix}"
    export CLOUDTRAIL_NAME="s3-multi-region-audit-trail-${random_suffix}"
    
    # Save environment variables to file for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
PRIMARY_REGION=${PRIMARY_REGION}
SECONDARY_REGION=${SECONDARY_REGION}
TERTIARY_REGION=${TERTIARY_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
SOURCE_BUCKET=${SOURCE_BUCKET}
DEST_BUCKET_1=${DEST_BUCKET_1}
DEST_BUCKET_2=${DEST_BUCKET_2}
REPLICATION_ROLE=${REPLICATION_ROLE}
SOURCE_KMS_ALIAS=${SOURCE_KMS_ALIAS}
DEST_KMS_ALIAS_1=${DEST_KMS_ALIAS_1}
DEST_KMS_ALIAS_2=${DEST_KMS_ALIAS_2}
SNS_TOPIC=${SNS_TOPIC}
CLOUDTRAIL_NAME=${CLOUDTRAIL_NAME}
EOF
    
    log_info "Environment configured:"
    log_info "  Primary Region: ${PRIMARY_REGION}"
    log_info "  Secondary Region: ${SECONDARY_REGION}"
    log_info "  Tertiary Region: ${TERTIARY_REGION}"
    log_info "  Source Bucket: ${SOURCE_BUCKET}"
    log_info "  Destination Bucket 1: ${DEST_BUCKET_1}"
    log_info "  Destination Bucket 2: ${DEST_BUCKET_2}"
    
    log_success "Environment variables configured"
}

# Function to create KMS keys
create_kms_keys() {
    log "Creating KMS keys in all regions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create KMS keys in ${PRIMARY_REGION}, ${SECONDARY_REGION}, ${TERTIARY_REGION}"
        return 0
    fi
    
    # KMS key policy template
    local kms_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "Enable IAM User Permissions",
                "Effect": "Allow",
                "Principal": {
                    "AWS": "arn:aws:iam::'${AWS_ACCOUNT_ID}':root"
                },
                "Action": "kms:*",
                "Resource": "*"
            },
            {
                "Sid": "Allow S3 Service",
                "Effect": "Allow",
                "Principal": {
                    "Service": "s3.amazonaws.com"
                },
                "Action": [
                    "kms:Decrypt",
                    "kms:GenerateDataKey"
                ],
                "Resource": "*"
            }
        ]
    }'
    
    # Create source KMS key
    log "Creating source KMS key in ${PRIMARY_REGION}..."
    SOURCE_KMS_KEY_ID=$(aws kms create-key \
        --region "${PRIMARY_REGION}" \
        --policy "${kms_policy}" \
        --description "KMS key for S3 multi-region replication source" \
        --query 'KeyMetadata.KeyId' --output text)
    
    aws kms create-alias \
        --region "${PRIMARY_REGION}" \
        --alias-name "${SOURCE_KMS_ALIAS}" \
        --target-key-id "${SOURCE_KMS_KEY_ID}"
    
    # Create destination KMS key 1
    log "Creating destination KMS key 1 in ${SECONDARY_REGION}..."
    DEST_KMS_KEY_ID_1=$(aws kms create-key \
        --region "${SECONDARY_REGION}" \
        --policy "${kms_policy}" \
        --description "KMS key for S3 multi-region replication destination 1" \
        --query 'KeyMetadata.KeyId' --output text)
    
    aws kms create-alias \
        --region "${SECONDARY_REGION}" \
        --alias-name "${DEST_KMS_ALIAS_1}" \
        --target-key-id "${DEST_KMS_KEY_ID_1}"
    
    # Create destination KMS key 2
    log "Creating destination KMS key 2 in ${TERTIARY_REGION}..."
    DEST_KMS_KEY_ID_2=$(aws kms create-key \
        --region "${TERTIARY_REGION}" \
        --policy "${kms_policy}" \
        --description "KMS key for S3 multi-region replication destination 2" \
        --query 'KeyMetadata.KeyId' --output text)
    
    aws kms create-alias \
        --region "${TERTIARY_REGION}" \
        --alias-name "${DEST_KMS_ALIAS_2}" \
        --target-key-id "${DEST_KMS_KEY_ID_2}"
    
    # Save KMS key IDs to environment file
    cat >> "${SCRIPT_DIR}/.env" << EOF
SOURCE_KMS_KEY_ID=${SOURCE_KMS_KEY_ID}
DEST_KMS_KEY_ID_1=${DEST_KMS_KEY_ID_1}
DEST_KMS_KEY_ID_2=${DEST_KMS_KEY_ID_2}
EOF
    
    log_success "KMS keys created in all regions"
}

# Function to create S3 buckets
create_s3_buckets() {
    log "Creating S3 buckets with encryption..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create S3 buckets: ${SOURCE_BUCKET}, ${DEST_BUCKET_1}, ${DEST_BUCKET_2}"
        return 0
    fi
    
    # Create source bucket
    log "Creating source bucket: ${SOURCE_BUCKET}"
    aws s3 mb "s3://${SOURCE_BUCKET}" --region "${PRIMARY_REGION}"
    
    # Enable versioning and encryption on source bucket
    aws s3api put-bucket-versioning \
        --bucket "${SOURCE_BUCKET}" \
        --versioning-configuration Status=Enabled
    
    aws s3api put-bucket-encryption \
        --bucket "${SOURCE_BUCKET}" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "aws:kms",
                        "KMSMasterKeyID": "'${SOURCE_KMS_ALIAS}'"
                    },
                    "BucketKeyEnabled": true
                }
            ]
        }'
    
    # Create destination bucket 1
    log "Creating destination bucket 1: ${DEST_BUCKET_1}"
    aws s3 mb "s3://${DEST_BUCKET_1}" --region "${SECONDARY_REGION}"
    
    aws s3api put-bucket-versioning \
        --bucket "${DEST_BUCKET_1}" \
        --versioning-configuration Status=Enabled \
        --region "${SECONDARY_REGION}"
    
    aws s3api put-bucket-encryption \
        --bucket "${DEST_BUCKET_1}" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "aws:kms",
                        "KMSMasterKeyID": "'${DEST_KMS_ALIAS_1}'"
                    },
                    "BucketKeyEnabled": true
                }
            ]
        }' \
        --region "${SECONDARY_REGION}"
    
    # Create destination bucket 2
    log "Creating destination bucket 2: ${DEST_BUCKET_2}"
    aws s3 mb "s3://${DEST_BUCKET_2}" --region "${TERTIARY_REGION}"
    
    aws s3api put-bucket-versioning \
        --bucket "${DEST_BUCKET_2}" \
        --versioning-configuration Status=Enabled \
        --region "${TERTIARY_REGION}"
    
    aws s3api put-bucket-encryption \
        --bucket "${DEST_BUCKET_2}" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "aws:kms",
                        "KMSMasterKeyID": "'${DEST_KMS_ALIAS_2}'"
                    },
                    "BucketKeyEnabled": true
                }
            ]
        }' \
        --region "${TERTIARY_REGION}"
    
    log_success "S3 buckets created with encryption"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for replication..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create IAM role: ${REPLICATION_ROLE}"
        return 0
    fi
    
    # Create trust policy
    local trust_policy='{
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
    }'
    
    # Create IAM role
    aws iam create-role \
        --role-name "${REPLICATION_ROLE}" \
        --assume-role-policy-document "${trust_policy}"
    
    # Get role ARN
    REPLICATION_ROLE_ARN=$(aws iam get-role \
        --role-name "${REPLICATION_ROLE}" \
        --query Role.Arn --output text)
    
    # Save role ARN to environment file
    echo "REPLICATION_ROLE_ARN=${REPLICATION_ROLE_ARN}" >> "${SCRIPT_DIR}/.env"
    
    log_success "IAM role created: ${REPLICATION_ROLE_ARN}"
}

# Function to attach IAM policies
attach_iam_policies() {
    log "Attaching replication permissions to IAM role..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would attach replication policies to ${REPLICATION_ROLE}"
        return 0
    fi
    
    # Create replication policy
    local replication_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "s3:GetReplicationConfiguration",
                    "s3:ListBucket",
                    "s3:GetBucketVersioning"
                ],
                "Resource": "arn:aws:s3:::'${SOURCE_BUCKET}'"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:GetObjectVersionForReplication",
                    "s3:GetObjectVersionAcl",
                    "s3:GetObjectVersionTagging"
                ],
                "Resource": "arn:aws:s3:::'${SOURCE_BUCKET}'/*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:ReplicateObject",
                    "s3:ReplicateDelete",
                    "s3:ReplicateTags"
                ],
                "Resource": [
                    "arn:aws:s3:::'${DEST_BUCKET_1}'/*",
                    "arn:aws:s3:::'${DEST_BUCKET_2}'/*"
                ]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "kms:Decrypt",
                    "kms:GenerateDataKey"
                ],
                "Resource": [
                    "arn:aws:kms:'${PRIMARY_REGION}':'${AWS_ACCOUNT_ID}':key/'${SOURCE_KMS_KEY_ID}'",
                    "arn:aws:kms:'${SECONDARY_REGION}':'${AWS_ACCOUNT_ID}':key/'${DEST_KMS_KEY_ID_1}'",
                    "arn:aws:kms:'${TERTIARY_REGION}':'${AWS_ACCOUNT_ID}':key/'${DEST_KMS_KEY_ID_2}'"
                ]
            }
        ]
    }'
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name "${REPLICATION_ROLE}" \
        --policy-name MultiRegionS3ReplicationPolicy \
        --policy-document "${replication_policy}"
    
    log_success "IAM policies attached"
}

# Function to configure replication
configure_replication() {
    log "Configuring multi-region replication rules..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would configure replication from ${SOURCE_BUCKET} to ${DEST_BUCKET_1}, ${DEST_BUCKET_2}"
        return 0
    fi
    
    # Wait a moment for IAM role to be available
    sleep 10
    
    # Create replication configuration
    local replication_config='{
        "Role": "'${REPLICATION_ROLE_ARN}'",
        "Rules": [
            {
                "ID": "ReplicateAllToSecondary",
                "Status": "Enabled",
                "Priority": 1,
                "Filter": {
                    "Prefix": ""
                },
                "DeleteMarkerReplication": {
                    "Status": "Enabled"
                },
                "Destination": {
                    "Bucket": "arn:aws:s3:::'${DEST_BUCKET_1}'",
                    "StorageClass": "STANDARD_IA",
                    "EncryptionConfiguration": {
                        "ReplicaKmsKeyID": "arn:aws:kms:'${SECONDARY_REGION}':'${AWS_ACCOUNT_ID}':key/'${DEST_KMS_KEY_ID_1}'"
                    },
                    "Metrics": {
                        "Status": "Enabled",
                        "EventThreshold": {
                            "Minutes": 15
                        }
                    },
                    "ReplicationTime": {
                        "Status": "Enabled",
                        "Time": {
                            "Minutes": 15
                        }
                    }
                }
            },
            {
                "ID": "ReplicateAllToTertiary",
                "Status": "Enabled",
                "Priority": 2,
                "Filter": {
                    "Prefix": ""
                },
                "DeleteMarkerReplication": {
                    "Status": "Enabled"
                },
                "Destination": {
                    "Bucket": "arn:aws:s3:::'${DEST_BUCKET_2}'",
                    "StorageClass": "STANDARD_IA",
                    "EncryptionConfiguration": {
                        "ReplicaKmsKeyID": "arn:aws:kms:'${TERTIARY_REGION}':'${AWS_ACCOUNT_ID}':key/'${DEST_KMS_KEY_ID_2}'"
                    },
                    "Metrics": {
                        "Status": "Enabled",
                        "EventThreshold": {
                            "Minutes": 15
                        }
                    },
                    "ReplicationTime": {
                        "Status": "Enabled",
                        "Time": {
                            "Minutes": 15
                        }
                    }
                }
            },
            {
                "ID": "ReplicateCriticalDataFast",
                "Status": "Enabled",
                "Priority": 3,
                "Filter": {
                    "And": {
                        "Prefix": "critical/",
                        "Tags": [
                            {
                                "Key": "Priority",
                                "Value": "High"
                            }
                        ]
                    }
                },
                "DeleteMarkerReplication": {
                    "Status": "Enabled"
                },
                "Destination": {
                    "Bucket": "arn:aws:s3:::'${DEST_BUCKET_1}'",
                    "StorageClass": "STANDARD",
                    "EncryptionConfiguration": {
                        "ReplicaKmsKeyID": "arn:aws:kms:'${SECONDARY_REGION}':'${AWS_ACCOUNT_ID}':key/'${DEST_KMS_KEY_ID_1}'"
                    },
                    "Metrics": {
                        "Status": "Enabled",
                        "EventThreshold": {
                            "Minutes": 15
                        }
                    },
                    "ReplicationTime": {
                        "Status": "Enabled",
                        "Time": {
                            "Minutes": 15
                        }
                    }
                }
            }
        ]
    }'
    
    # Apply replication configuration
    aws s3api put-bucket-replication \
        --bucket "${SOURCE_BUCKET}" \
        --replication-configuration "${replication_config}"
    
    log_success "Multi-region replication configured"
}

# Function to setup monitoring
setup_monitoring() {
    log "Setting up monitoring and alerting..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would setup CloudWatch monitoring and SNS alerts"
        return 0
    fi
    
    # Create SNS topic
    aws sns create-topic \
        --name "${SNS_TOPIC}" \
        --region "${PRIMARY_REGION}"
    
    SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC}" \
        --query 'Attributes.TopicArn' --output text)
    
    # Create CloudWatch alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "S3-Replication-Failure-Rate-${SOURCE_BUCKET}" \
        --alarm-description "High replication failure rate" \
        --metric-name FailedReplication \
        --namespace AWS/S3 \
        --statistic Sum \
        --period 300 \
        --threshold 10 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=SourceBucket,Value="${SOURCE_BUCKET}" \
        --region "${PRIMARY_REGION}"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "S3-Replication-Latency-${SOURCE_BUCKET}" \
        --alarm-description "Replication latency too high" \
        --metric-name ReplicationLatency \
        --namespace AWS/S3 \
        --statistic Average \
        --period 300 \
        --threshold 900 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=SourceBucket,Value="${SOURCE_BUCKET}" \
                    Name=DestinationBucket,Value="${DEST_BUCKET_1}" \
        --region "${PRIMARY_REGION}"
    
    # Save SNS topic ARN
    echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> "${SCRIPT_DIR}/.env"
    
    log_success "Monitoring and alerting configured"
}

# Function to configure lifecycle policies
configure_lifecycle() {
    log "Configuring intelligent tiering and lifecycle policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would configure lifecycle policies for cost optimization"
        return 0
    fi
    
    # Configure intelligent tiering
    aws s3api put-bucket-intelligent-tiering-configuration \
        --bucket "${SOURCE_BUCKET}" \
        --id "EntireBucket" \
        --intelligent-tiering-configuration '{
            "Id": "EntireBucket",
            "Status": "Enabled",
            "Filter": {
                "Prefix": ""
            },
            "Tierings": [
                {
                    "Days": 90,
                    "AccessTier": "ARCHIVE_ACCESS"
                },
                {
                    "Days": 180,
                    "AccessTier": "DEEP_ARCHIVE_ACCESS"
                }
            ],
            "OptionalFields": ["BucketKeyStatus"]
        }'
    
    # Configure lifecycle policy
    local lifecycle_policy='{
        "Rules": [
            {
                "ID": "MultiRegionLifecycleRule",
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
                    },
                    {
                        "Days": 365,
                        "StorageClass": "DEEP_ARCHIVE"
                    }
                ],
                "NoncurrentVersionTransitions": [
                    {
                        "NoncurrentDays": 7,
                        "StorageClass": "STANDARD_IA"
                    },
                    {
                        "NoncurrentDays": 30,
                        "StorageClass": "GLACIER"
                    }
                ],
                "NoncurrentVersionExpiration": {
                    "NoncurrentDays": 365
                }
            }
        ]
    }'
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "${SOURCE_BUCKET}" \
        --lifecycle-configuration "${lifecycle_policy}"
    
    log_success "Lifecycle policies configured"
}

# Function to configure security
configure_security() {
    log "Configuring security and access controls..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would configure bucket policies and public access blocks"
        return 0
    fi
    
    # Create bucket policy
    local bucket_policy='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "DenyInsecureConnections",
                "Effect": "Deny",
                "Principal": "*",
                "Action": "s3:*",
                "Resource": [
                    "arn:aws:s3:::'${SOURCE_BUCKET}'",
                    "arn:aws:s3:::'${SOURCE_BUCKET}'/*"
                ],
                "Condition": {
                    "Bool": {
                        "aws:SecureTransport": "false"
                    }
                }
            },
            {
                "Sid": "AllowReplicationRole",
                "Effect": "Allow",
                "Principal": {
                    "AWS": "'${REPLICATION_ROLE_ARN}'"
                },
                "Action": [
                    "s3:GetReplicationConfiguration",
                    "s3:ListBucket",
                    "s3:GetObjectVersionForReplication",
                    "s3:GetObjectVersionAcl",
                    "s3:GetObjectVersionTagging"
                ],
                "Resource": [
                    "arn:aws:s3:::'${SOURCE_BUCKET}'",
                    "arn:aws:s3:::'${SOURCE_BUCKET}'/*"
                ]
            }
        ]
    }'
    
    # Apply bucket policy
    aws s3api put-bucket-policy \
        --bucket "${SOURCE_BUCKET}" \
        --policy "${bucket_policy}"
    
    # Block public access for all buckets
    aws s3api put-public-access-block \
        --bucket "${SOURCE_BUCKET}" \
        --public-access-block-configuration \
            'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
    
    aws s3api put-public-access-block \
        --bucket "${DEST_BUCKET_1}" \
        --public-access-block-configuration \
            'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true' \
        --region "${SECONDARY_REGION}"
    
    aws s3api put-public-access-block \
        --bucket "${DEST_BUCKET_2}" \
        --public-access-block-configuration \
            'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true' \
        --region "${TERTIARY_REGION}"
    
    log_success "Security configurations applied"
}

# Function to upload test data
upload_test_data() {
    if [[ "$SKIP_TEST_DATA" == "true" ]]; then
        log_info "Skipping test data upload as requested"
        return 0
    fi
    
    log "Uploading test data and configuring tags..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would upload test data to ${SOURCE_BUCKET}"
        return 0
    fi
    
    # Create test data files
    local test_dir="${SCRIPT_DIR}/test-data"
    mkdir -p "${test_dir}"
    
    echo "Critical business data - $(date)" > "${test_dir}/critical-data.txt"
    echo "Standard application data - $(date)" > "${test_dir}/standard-data.txt"
    echo "Archive compliance data - $(date)" > "${test_dir}/archive-data.txt"
    echo "High priority operational data - $(date)" > "${test_dir}/high-priority-data.txt"
    
    # Upload test data with different classifications
    aws s3 cp "${test_dir}/critical-data.txt" "s3://${SOURCE_BUCKET}/critical/" \
        --metadata "classification=critical,owner=finance" \
        --tagging "Priority=High&DataType=Financial&Compliance=SOX"
    
    aws s3 cp "${test_dir}/standard-data.txt" "s3://${SOURCE_BUCKET}/standard/" \
        --metadata "classification=standard,owner=operations" \
        --tagging "Priority=Medium&DataType=Operational"
    
    aws s3 cp "${test_dir}/archive-data.txt" "s3://${SOURCE_BUCKET}/archive/" \
        --metadata "classification=archive,owner=legal" \
        --tagging "Priority=Low&DataType=Compliance&Retention=7years"
    
    aws s3 cp "${test_dir}/high-priority-data.txt" "s3://${SOURCE_BUCKET}/critical/" \
        --metadata "classification=critical,owner=operations" \
        --tagging "Priority=High&DataType=Operational&RTO=15min"
    
    # Configure bucket tags
    aws s3api put-bucket-tagging \
        --bucket "${SOURCE_BUCKET}" \
        --tagging 'TagSet=[
            {Key=Environment,Value=Production},
            {Key=Application,Value=MultiRegionReplication},
            {Key=CostCenter,Value=IT-Storage},
            {Key=Owner,Value=DataTeam},
            {Key=Compliance,Value=SOX-GDPR},
            {Key=BackupStrategy,Value=MultiRegion}
        ]'
    
    aws s3api put-bucket-tagging \
        --bucket "${DEST_BUCKET_1}" \
        --tagging 'TagSet=[
            {Key=Environment,Value=Production},
            {Key=Application,Value=MultiRegionReplication},
            {Key=CostCenter,Value=IT-Storage},
            {Key=Owner,Value=DataTeam},
            {Key=Compliance,Value=SOX-GDPR},
            {Key=BackupStrategy,Value=MultiRegion},
            {Key=ReplicaOf,Value='${SOURCE_BUCKET}'}
        ]' \
        --region "${SECONDARY_REGION}"
    
    aws s3api put-bucket-tagging \
        --bucket "${DEST_BUCKET_2}" \
        --tagging 'TagSet=[
            {Key=Environment,Value=Production},
            {Key=Application,Value=MultiRegionReplication},
            {Key=CostCenter,Value=IT-Storage},
            {Key=Owner,Value=DataTeam},
            {Key=Compliance,Value=SOX-GDPR},
            {Key=BackupStrategy,Value=MultiRegion},
            {Key=ReplicaOf,Value='${SOURCE_BUCKET}'}
        ]' \
        --region "${TERTIARY_REGION}"
    
    # Clean up test data directory
    rm -rf "${test_dir}"
    
    log_success "Test data uploaded and bucket tags configured"
}

# Function to create operational scripts
create_operational_scripts() {
    log "Creating operational scripts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create operational scripts"
        return 0
    fi
    
    # Create health check script
    cat > "${SCRIPT_DIR}/health-check.sh" << EOF
#!/bin/bash

# Multi-Region S3 Health Check Script
# Source environment
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    source "${SCRIPT_DIR}/.env"
fi

echo "Multi-Region S3 Health Check Report - \$(date)"
echo "================================================="

# Check source bucket
if aws s3 ls "s3://\${SOURCE_BUCKET}" --region "\${PRIMARY_REGION}" > /dev/null 2>&1; then
    echo "✅ Source bucket (\${SOURCE_BUCKET}) is healthy"
else
    echo "❌ Source bucket (\${SOURCE_BUCKET}) is unavailable"
fi

# Check destination bucket 1
if aws s3 ls "s3://\${DEST_BUCKET_1}" --region "\${SECONDARY_REGION}" > /dev/null 2>&1; then
    echo "✅ Destination bucket 1 (\${DEST_BUCKET_1}) is healthy"
else
    echo "❌ Destination bucket 1 (\${DEST_BUCKET_1}) is unavailable"
fi

# Check destination bucket 2
if aws s3 ls "s3://\${DEST_BUCKET_2}" --region "\${TERTIARY_REGION}" > /dev/null 2>&1; then
    echo "✅ Destination bucket 2 (\${DEST_BUCKET_2}) is healthy"
else
    echo "❌ Destination bucket 2 (\${DEST_BUCKET_2}) is unavailable"
fi

echo "================================================="
EOF

    chmod +x "${SCRIPT_DIR}/health-check.sh"
    
    log_success "Operational scripts created"
}

# Function to display deployment summary
display_summary() {
    log "==================================================================="
    log "                    DEPLOYMENT SUMMARY"
    log "==================================================================="
    log "Primary Region: ${PRIMARY_REGION}"
    log "Secondary Region: ${SECONDARY_REGION}"
    log "Tertiary Region: ${TERTIARY_REGION}"
    log ""
    log "Created Resources:"
    log "  Source Bucket: ${SOURCE_BUCKET}"
    log "  Destination Bucket 1: ${DEST_BUCKET_1}"
    log "  Destination Bucket 2: ${DEST_BUCKET_2}"
    log "  Replication Role: ${REPLICATION_ROLE}"
    log "  KMS Aliases: ${SOURCE_KMS_ALIAS}, ${DEST_KMS_ALIAS_1}, ${DEST_KMS_ALIAS_2}"
    log "  SNS Topic: ${SNS_TOPIC}"
    log ""
    log "Next Steps:"
    log "  1. Test replication by uploading files to ${SOURCE_BUCKET}"
    log "  2. Monitor replication status in CloudWatch dashboard"
    log "  3. Run health check: ./health-check.sh"
    log "  4. Review CloudWatch alarms and SNS notifications"
    log ""
    log "Cleanup:"
    log "  Run: ./destroy.sh to remove all created resources"
    log "==================================================================="
}

# Main execution function
main() {
    log "Starting multi-region S3 replication deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_kms_keys
    create_s3_buckets
    create_iam_role
    attach_iam_policies
    configure_replication
    setup_monitoring
    configure_lifecycle
    configure_security
    upload_test_data
    create_operational_scripts
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN completed successfully. No resources were created."
    else
        log_success "Multi-region S3 replication deployment completed successfully!"
        display_summary
    fi
}

# Trap errors and cleanup on exit
trap 'log_error "Deployment failed at line $LINENO. Check $LOG_FILE for details."' ERR

# Run main function
main "$@"