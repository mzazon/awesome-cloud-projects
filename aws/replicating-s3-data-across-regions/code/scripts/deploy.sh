#!/bin/bash

# S3 Cross-Region Replication with Encryption and Access Controls - Deployment Script
# Recipe: Replicating S3 Data Across Regions with Encryption
# Version: 1.1

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_FILE="/tmp/s3-crr-deploy-$(date +%Y%m%d-%H%M%S).log"
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/s3-crr-deployment-$$"
DRY_RUN=false
SKIP_CONFIRMATION=false
WAIT_TIMEOUT=300

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${BLUE}[INFO]${NC} ${timestamp} - $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - $message"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${NC} ${timestamp} - $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} ${timestamp} - $message"
            ;;
    esac
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to cleanup temporary files
cleanup() {
    log INFO "Cleaning up temporary files..."
    rm -rf "${TEMP_DIR}"
    log INFO "Temporary files cleaned up"
}

# Trap to ensure cleanup happens
trap cleanup EXIT

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy S3 Cross-Region Replication with Encryption and Access Controls

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run           Show what would be deployed without making changes
    -y, --yes               Skip confirmation prompts
    -r, --primary-region    Primary AWS region (default: us-east-1)
    -s, --secondary-region  Secondary AWS region (default: us-west-2)
    -p, --prefix            Resource name prefix (default: crr)
    -t, --timeout           Wait timeout in seconds (default: 300)
    -v, --verbose           Enable verbose logging

EXAMPLES:
    $0                                          # Deploy with default settings
    $0 --dry-run                               # Show what would be deployed
    $0 --primary-region us-east-1 --secondary-region eu-west-1
    $0 --prefix mycompany --yes                # Deploy with custom prefix, skip confirmation

EOF
}

# Function to validate AWS CLI and credentials
validate_aws_prerequisites() {
    log INFO "Validating AWS prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        log ERROR "AWS CLI is not installed. Please install AWS CLI v2"
        return 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log INFO "AWS CLI version: $aws_version"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log ERROR "AWS credentials not configured. Please run 'aws configure' or set AWS environment variables"
        return 1
    fi
    
    # Get caller identity
    local caller_identity
    caller_identity=$(aws sts get-caller-identity)
    log INFO "AWS caller identity: $(echo "$caller_identity" | jq -r '.Arn')"
    
    return 0
}

# Function to validate regions
validate_regions() {
    log INFO "Validating AWS regions..."
    
    # Check if primary region is valid
    if ! aws ec2 describe-regions --region-names "$PRIMARY_REGION" >/dev/null 2>&1; then
        log ERROR "Invalid primary region: $PRIMARY_REGION"
        return 1
    fi
    
    # Check if secondary region is valid
    if ! aws ec2 describe-regions --region-names "$SECONDARY_REGION" >/dev/null 2>&1; then
        log ERROR "Invalid secondary region: $SECONDARY_REGION"
        return 1
    fi
    
    # Ensure regions are different
    if [[ "$PRIMARY_REGION" == "$SECONDARY_REGION" ]]; then
        log ERROR "Primary and secondary regions must be different"
        return 1
    fi
    
    log SUCCESS "Regions validated: $PRIMARY_REGION -> $SECONDARY_REGION"
    return 0
}

# Function to generate resource names
generate_resource_names() {
    log INFO "Generating resource names..."
    
    # Generate random suffix for unique naming
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 9)")
    
    # Set resource names
    SOURCE_BUCKET="${PREFIX}-source-${RANDOM_SUFFIX}"
    DEST_BUCKET="${PREFIX}-dest-${RANDOM_SUFFIX}"
    REPLICATION_ROLE="${PREFIX}ReplicationRole-${RANDOM_SUFFIX}"
    SOURCE_KMS_ALIAS="alias/${PREFIX}-source-${RANDOM_SUFFIX}"
    DEST_KMS_ALIAS="alias/${PREFIX}-dest-${RANDOM_SUFFIX}"
    
    log INFO "Generated resource names:"
    log INFO "  Source Bucket: $SOURCE_BUCKET"
    log INFO "  Destination Bucket: $DEST_BUCKET"
    log INFO "  Replication Role: $REPLICATION_ROLE"
    log INFO "  Source KMS Alias: $SOURCE_KMS_ALIAS"
    log INFO "  Destination KMS Alias: $DEST_KMS_ALIAS"
}

# Function to create KMS keys
create_kms_keys() {
    log INFO "Creating KMS keys..."
    
    mkdir -p "${TEMP_DIR}"
    
    # Create KMS key policy
    cat > "${TEMP_DIR}/kms-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Enable IAM User Permissions",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
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
}
EOF
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create KMS key in primary region: $PRIMARY_REGION"
        log INFO "[DRY RUN] Would create KMS key in secondary region: $SECONDARY_REGION"
        return 0
    fi
    
    # Create KMS key in primary region
    log INFO "Creating KMS key in primary region ($PRIMARY_REGION)..."
    SOURCE_KMS_KEY=$(aws kms create-key \
        --region "$PRIMARY_REGION" \
        --policy file://"${TEMP_DIR}/kms-policy.json" \
        --description "S3 Cross-Region Replication Source Key" \
        --output text --query 'KeyMetadata.KeyId')
    
    if [[ -z "$SOURCE_KMS_KEY" ]]; then
        log ERROR "Failed to create source KMS key"
        return 1
    fi
    
    log SUCCESS "Created source KMS key: $SOURCE_KMS_KEY"
    
    # Create alias for source key
    aws kms create-alias \
        --region "$PRIMARY_REGION" \
        --alias-name "$SOURCE_KMS_ALIAS" \
        --target-key-id "$SOURCE_KMS_KEY"
    
    log SUCCESS "Created source KMS alias: $SOURCE_KMS_ALIAS"
    
    # Create KMS key in secondary region
    log INFO "Creating KMS key in secondary region ($SECONDARY_REGION)..."
    DEST_KMS_KEY=$(aws kms create-key \
        --region "$SECONDARY_REGION" \
        --policy file://"${TEMP_DIR}/kms-policy.json" \
        --description "S3 Cross-Region Replication Destination Key" \
        --output text --query 'KeyMetadata.KeyId')
    
    if [[ -z "$DEST_KMS_KEY" ]]; then
        log ERROR "Failed to create destination KMS key"
        return 1
    fi
    
    log SUCCESS "Created destination KMS key: $DEST_KMS_KEY"
    
    # Create alias for destination key
    aws kms create-alias \
        --region "$SECONDARY_REGION" \
        --alias-name "$DEST_KMS_ALIAS" \
        --target-key-id "$DEST_KMS_KEY"
    
    log SUCCESS "Created destination KMS alias: $DEST_KMS_ALIAS"
}

# Function to create S3 buckets
create_s3_buckets() {
    log INFO "Creating S3 buckets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create source bucket: $SOURCE_BUCKET"
        log INFO "[DRY RUN] Would create destination bucket: $DEST_BUCKET"
        return 0
    fi
    
    # Create source bucket
    log INFO "Creating source bucket: $SOURCE_BUCKET"
    if [[ "$PRIMARY_REGION" == "us-east-1" ]]; then
        aws s3api create-bucket --bucket "$SOURCE_BUCKET" --region "$PRIMARY_REGION"
    else
        aws s3api create-bucket \
            --bucket "$SOURCE_BUCKET" \
            --region "$PRIMARY_REGION" \
            --create-bucket-configuration LocationConstraint="$PRIMARY_REGION"
    fi
    
    # Enable versioning on source bucket
    aws s3api put-bucket-versioning \
        --bucket "$SOURCE_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Configure default encryption on source bucket
    aws s3api put-bucket-encryption \
        --bucket "$SOURCE_BUCKET" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "aws:kms",
                        "KMSMasterKeyID": "'$SOURCE_KMS_KEY'"
                    },
                    "BucketKeyEnabled": true
                }
            ]
        }'
    
    log SUCCESS "Created and configured source bucket: $SOURCE_BUCKET"
    
    # Create destination bucket
    log INFO "Creating destination bucket: $DEST_BUCKET"
    aws s3api create-bucket \
        --bucket "$DEST_BUCKET" \
        --region "$SECONDARY_REGION" \
        --create-bucket-configuration LocationConstraint="$SECONDARY_REGION"
    
    # Enable versioning on destination bucket
    aws s3api put-bucket-versioning \
        --bucket "$DEST_BUCKET" \
        --versioning-configuration Status=Enabled \
        --region "$SECONDARY_REGION"
    
    # Configure default encryption on destination bucket
    aws s3api put-bucket-encryption \
        --bucket "$DEST_BUCKET" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "aws:kms",
                        "KMSMasterKeyID": "'$DEST_KMS_KEY'"
                    },
                    "BucketKeyEnabled": true
                }
            ]
        }' \
        --region "$SECONDARY_REGION"
    
    log SUCCESS "Created and configured destination bucket: $DEST_BUCKET"
}

# Function to create IAM replication role
create_iam_role() {
    log INFO "Creating IAM replication role..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would create IAM role: $REPLICATION_ROLE"
        return 0
    fi
    
    # Create trust policy
    cat > "${TEMP_DIR}/trust-policy.json" << EOF
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
        --role-name "$REPLICATION_ROLE" \
        --assume-role-policy-document file://"${TEMP_DIR}/trust-policy.json" \
        --description "S3 Cross-Region Replication Role"
    
    # Create permissions policy
    cat > "${TEMP_DIR}/replication-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObjectVersion",
                "s3:GetObjectVersionAcl",
                "s3:GetObjectVersionForReplication",
                "s3:GetObjectVersionTagging"
            ],
            "Resource": [
                "arn:aws:s3:::${SOURCE_BUCKET}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetBucketVersioning"
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
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt"
            ],
            "Resource": [
                "arn:aws:kms:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:key/${SOURCE_KMS_KEY}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "kms:GenerateDataKey"
            ],
            "Resource": [
                "arn:aws:kms:${SECONDARY_REGION}:${AWS_ACCOUNT_ID}:key/${DEST_KMS_KEY}"
            ]
        }
    ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name "$REPLICATION_ROLE" \
        --policy-name S3ReplicationPolicy \
        --policy-document file://"${TEMP_DIR}/replication-policy.json"
    
    log SUCCESS "Created IAM replication role: $REPLICATION_ROLE"
    
    # Wait for role to be available
    log INFO "Waiting for IAM role to be available..."
    sleep 10
}

# Function to configure cross-region replication
configure_replication() {
    log INFO "Configuring cross-region replication..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would configure replication from $SOURCE_BUCKET to $DEST_BUCKET"
        return 0
    fi
    
    # Create replication configuration
    cat > "${TEMP_DIR}/replication-config.json" << EOF
{
    "Role": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${REPLICATION_ROLE}",
    "Rules": [
        {
            "ID": "ReplicateEncryptedObjects",
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
                "StorageClass": "STANDARD_IA",
                "EncryptionConfiguration": {
                    "ReplicaKmsKeyID": "arn:aws:kms:${SECONDARY_REGION}:${AWS_ACCOUNT_ID}:key/${DEST_KMS_KEY}"
                }
            },
            "SourceSelectionCriteria": {
                "SseKmsEncryptedObjects": {
                    "Status": "Enabled"
                }
            }
        }
    ]
}
EOF
    
    # Apply replication configuration
    aws s3api put-bucket-replication \
        --bucket "$SOURCE_BUCKET" \
        --replication-configuration file://"${TEMP_DIR}/replication-config.json"
    
    log SUCCESS "Configured cross-region replication"
}

# Function to configure monitoring
configure_monitoring() {
    log INFO "Configuring monitoring and alarms..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would configure CloudWatch monitoring"
        return 0
    fi
    
    # Enable replication metrics
    aws s3api put-bucket-metrics-configuration \
        --bucket "$SOURCE_BUCKET" \
        --id "ReplicationMetrics" \
        --metrics-configuration '{
            "Id": "ReplicationMetrics",
            "Filter": {
                "Prefix": ""
            }
        }'
    
    # Create CloudWatch alarm for replication failures
    aws cloudwatch put-metric-alarm \
        --alarm-name "S3-Replication-Failures-${SOURCE_BUCKET}" \
        --alarm-description "Alert when S3 replication fails" \
        --metric-name ReplicationLatency \
        --namespace AWS/S3 \
        --statistic Maximum \
        --period 300 \
        --threshold 900 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --region "$PRIMARY_REGION" \
        --dimensions Name=SourceBucket,Value="$SOURCE_BUCKET" \
            Name=DestinationBucket,Value="$DEST_BUCKET"
    
    log SUCCESS "Configured monitoring and alarms"
}

# Function to configure bucket policies
configure_bucket_policies() {
    log INFO "Configuring bucket security policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would configure bucket policies"
        return 0
    fi
    
    # Create source bucket policy
    cat > "${TEMP_DIR}/source-bucket-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyUnencryptedObjectUploads",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${SOURCE_BUCKET}/*",
            "Condition": {
                "StringNotEquals": {
                    "s3:x-amz-server-side-encryption": "aws:kms"
                }
            }
        },
        {
            "Sid": "DenyInsecureConnections",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${SOURCE_BUCKET}",
                "arn:aws:s3:::${SOURCE_BUCKET}/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
EOF
    
    # Apply source bucket policy
    aws s3api put-bucket-policy \
        --bucket "$SOURCE_BUCKET" \
        --policy file://"${TEMP_DIR}/source-bucket-policy.json"
    
    # Create destination bucket policy
    cat > "${TEMP_DIR}/dest-bucket-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyInsecureConnections",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${DEST_BUCKET}",
                "arn:aws:s3:::${DEST_BUCKET}/*"
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
                "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${REPLICATION_ROLE}"
            },
            "Action": [
                "s3:ReplicateObject",
                "s3:ReplicateDelete",
                "s3:ReplicateTags"
            ],
            "Resource": "arn:aws:s3:::${DEST_BUCKET}/*"
        }
    ]
}
EOF
    
    # Apply destination bucket policy
    aws s3api put-bucket-policy \
        --bucket "$DEST_BUCKET" \
        --policy file://"${TEMP_DIR}/dest-bucket-policy.json" \
        --region "$SECONDARY_REGION"
    
    log SUCCESS "Configured bucket security policies"
}

# Function to test replication
test_replication() {
    log INFO "Testing replication functionality..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would test replication"
        return 0
    fi
    
    # Create test files
    echo "Test data for replication - $(date)" > "${TEMP_DIR}/test-file-1.txt"
    echo "Second test file - $(date)" > "${TEMP_DIR}/test-file-2.txt"
    
    # Upload test files with KMS encryption
    log INFO "Uploading test files to source bucket..."
    aws s3 cp "${TEMP_DIR}/test-file-1.txt" "s3://${SOURCE_BUCKET}/test-file-1.txt" \
        --sse aws:kms \
        --sse-kms-key-id "$SOURCE_KMS_KEY"
    
    aws s3 cp "${TEMP_DIR}/test-file-2.txt" "s3://${SOURCE_BUCKET}/folder/test-file-2.txt" \
        --sse aws:kms \
        --sse-kms-key-id "$SOURCE_KMS_KEY"
    
    log SUCCESS "Uploaded test files to source bucket"
    
    # Wait for replication
    log INFO "Waiting for replication to complete (up to ${WAIT_TIMEOUT} seconds)..."
    local wait_time=0
    local replication_complete=false
    
    while [[ $wait_time -lt $WAIT_TIMEOUT ]]; do
        if aws s3 ls "s3://${DEST_BUCKET}/test-file-1.txt" --region "$SECONDARY_REGION" >/dev/null 2>&1; then
            replication_complete=true
            break
        fi
        sleep 10
        wait_time=$((wait_time + 10))
        log INFO "Still waiting for replication... (${wait_time}s elapsed)"
    done
    
    if [[ "$replication_complete" == "true" ]]; then
        log SUCCESS "Replication completed successfully"
        
        # Verify encryption on replicated objects
        local encryption_info
        encryption_info=$(aws s3api head-object \
            --bucket "$DEST_BUCKET" \
            --key test-file-1.txt \
            --region "$SECONDARY_REGION" \
            --query '[ServerSideEncryption,SSEKMSKeyId]' \
            --output text)
        
        log INFO "Replicated object encryption: $encryption_info"
    else
        log WARNING "Replication did not complete within timeout period"
    fi
}

# Function to save deployment information
save_deployment_info() {
    log INFO "Saving deployment information..."
    
    local info_file="${SCRIPT_DIR}/../deployment-info.json"
    
    cat > "$info_file" << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "primary_region": "${PRIMARY_REGION}",
    "secondary_region": "${SECONDARY_REGION}",
    "source_bucket": "${SOURCE_BUCKET}",
    "destination_bucket": "${DEST_BUCKET}",
    "replication_role": "${REPLICATION_ROLE}",
    "source_kms_key": "${SOURCE_KMS_KEY:-}",
    "destination_kms_key": "${DEST_KMS_KEY:-}",
    "source_kms_alias": "${SOURCE_KMS_ALIAS}",
    "destination_kms_alias": "${DEST_KMS_ALIAS}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "log_file": "${LOG_FILE}"
}
EOF
    
    log SUCCESS "Deployment information saved to: $info_file"
}

# Function to show deployment summary
show_deployment_summary() {
    log INFO "Deployment Summary:"
    log INFO "==================="
    log INFO "Primary Region: $PRIMARY_REGION"
    log INFO "Secondary Region: $SECONDARY_REGION"
    log INFO "Source Bucket: $SOURCE_BUCKET"
    log INFO "Destination Bucket: $DEST_BUCKET"
    log INFO "Replication Role: $REPLICATION_ROLE"
    log INFO "Source KMS Alias: $SOURCE_KMS_ALIAS"
    log INFO "Destination KMS Alias: $DEST_KMS_ALIAS"
    log INFO "Log File: $LOG_FILE"
    log INFO ""
    log SUCCESS "S3 Cross-Region Replication deployment completed successfully!"
    log INFO "You can now upload encrypted files to the source bucket and they will be automatically replicated to the destination bucket."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -r|--primary-region)
            PRIMARY_REGION="$2"
            shift 2
            ;;
        -s|--secondary-region)
            SECONDARY_REGION="$2"
            shift 2
            ;;
        -p|--prefix)
            PREFIX="$2"
            shift 2
            ;;
        -t|--timeout)
            WAIT_TIMEOUT="$2"
            shift 2
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            log ERROR "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Set default values
PRIMARY_REGION="${PRIMARY_REGION:-us-east-1}"
SECONDARY_REGION="${SECONDARY_REGION:-us-west-2}"
PREFIX="${PREFIX:-crr}"

# Main execution
main() {
    log INFO "Starting S3 Cross-Region Replication deployment..."
    log INFO "Script version: 1.1"
    log INFO "Deployment mode: $(if [[ "$DRY_RUN" == "true" ]]; then echo "DRY RUN"; else echo "LIVE"; fi)"
    
    # Validate prerequisites
    validate_aws_prerequisites || exit 1
    validate_regions || exit 1
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log INFO "AWS Account ID: $AWS_ACCOUNT_ID"
    
    # Generate resource names
    generate_resource_names
    
    # Show confirmation if not skipped
    if [[ "$SKIP_CONFIRMATION" != "true" && "$DRY_RUN" != "true" ]]; then
        echo
        log WARNING "This will create the following resources:"
        log WARNING "  - KMS keys in both regions"
        log WARNING "  - S3 buckets with versioning and encryption"
        log WARNING "  - IAM role for replication"
        log WARNING "  - CloudWatch alarms"
        log WARNING "  - S3 bucket policies"
        echo
        read -p "Do you want to continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    create_kms_keys || exit 1
    create_s3_buckets || exit 1
    create_iam_role || exit 1
    configure_replication || exit 1
    configure_monitoring || exit 1
    configure_bucket_policies || exit 1
    
    if [[ "$DRY_RUN" != "true" ]]; then
        test_replication
        save_deployment_info
    fi
    
    show_deployment_summary
}

# Run main function
main "$@"