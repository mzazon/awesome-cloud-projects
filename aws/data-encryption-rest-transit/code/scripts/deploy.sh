#!/bin/bash

# =============================================================================
# AWS Data Encryption at Rest and in Transit - Deployment Script
# =============================================================================
# This script deploys the comprehensive encryption solution including:
# - KMS customer-managed keys
# - S3 bucket with server-side encryption
# - RDS database with encryption at rest
# - EC2 instance with encrypted EBS volumes
# - Secrets Manager for secure credential storage
# - CloudTrail for encryption event logging
# =============================================================================

set -e
set -o pipefail

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for user confirmation
confirm() {
    read -p "$1 (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 1
    fi
}

# Function to cleanup on error
cleanup_on_error() {
    error "Deployment failed. Cleaning up partial resources..."
    
    # Cleanup any created resources
    if [[ -n "$EC2_INSTANCE_ID" ]]; then
        log "Terminating EC2 instance..."
        aws ec2 terminate-instances --instance-ids "$EC2_INSTANCE_ID" || true
    fi
    
    if [[ -n "$RDS_INSTANCE_ID" ]]; then
        log "Deleting RDS instance..."
        aws rds delete-db-instance --db-instance-identifier "$RDS_INSTANCE_ID" --skip-final-snapshot || true
    fi
    
    if [[ -n "$S3_BUCKET_NAME" ]]; then
        log "Deleting S3 bucket..."
        aws s3 rb "s3://$S3_BUCKET_NAME" --force || true
    fi
    
    if [[ -n "$KMS_KEY_ID" ]]; then
        log "Scheduling KMS key deletion..."
        aws kms schedule-key-deletion --key-id "$KMS_KEY_ID" --pending-window-in-days 7 || true
    fi
    
    exit 1
}

# Trap to cleanup on error
trap cleanup_on_error ERR

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command_exists aws; then
    error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS CLI is not configured. Please run 'aws configure' first."
    exit 1
fi

# Check required permissions
log "Checking AWS permissions..."
CALLER_IDENTITY=$(aws sts get-caller-identity)
AWS_ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
AWS_USER_ARN=$(echo "$CALLER_IDENTITY" | jq -r '.Arn')

if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    error "Unable to determine AWS account ID"
    exit 1
fi

success "Prerequisites check passed"
log "AWS Account ID: $AWS_ACCOUNT_ID"
log "AWS User/Role: $AWS_USER_ARN"

# =============================================================================
# CONFIGURATION
# =============================================================================
log "Setting up configuration..."

# Get AWS region
export AWS_REGION=$(aws configure get region)
if [[ -z "$AWS_REGION" ]]; then
    export AWS_REGION="us-east-1"
    warning "No default region set, using us-east-1"
fi

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword)

export KMS_KEY_ALIAS="alias/encryption-demo-${RANDOM_SUFFIX}"
export S3_BUCKET_NAME="encrypted-data-bucket-${RANDOM_SUFFIX}"
export RDS_INSTANCE_ID="encrypted-db-${RANDOM_SUFFIX}"
export SECRET_NAME="database-credentials-${RANDOM_SUFFIX}"

# Store configuration in environment file
cat > .env << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
KMS_KEY_ALIAS=$KMS_KEY_ALIAS
S3_BUCKET_NAME=$S3_BUCKET_NAME
RDS_INSTANCE_ID=$RDS_INSTANCE_ID
SECRET_NAME=$SECRET_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF

success "Configuration completed"
log "Resources will be created with suffix: $RANDOM_SUFFIX"

# =============================================================================
# COST ESTIMATION
# =============================================================================
log "Estimated monthly costs:"
echo "  - KMS Customer Managed Key: ~$1.00"
echo "  - S3 Storage (minimal): ~$0.50"
echo "  - RDS db.t3.micro: ~$12.00"
echo "  - EC2 t3.micro: ~$8.50"
echo "  - Secrets Manager: ~$0.40"
echo "  - CloudTrail: ~$2.00"
echo "  - Total estimated: ~$25.00/month"
echo ""

confirm "Do you want to continue with the deployment?"

# =============================================================================
# VPC AND NETWORKING SETUP
# =============================================================================
log "Creating VPC and networking components..."

# Create VPC
export VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=encryption-demo-vpc},{Key=Project,Value=encryption-demo}]' \
    --query 'Vpc.VpcId' --output text)

# Enable DNS support
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support

# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=encryption-demo-igw},{Key=Project,Value=encryption-demo}]' \
    --query 'InternetGateway.InternetGatewayId' --output text)

# Attach Internet Gateway to VPC
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"

# Create subnets
export SUBNET_1=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block 10.0.1.0/24 \
    --availability-zone "${AWS_REGION}a" \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=encryption-demo-subnet-1},{Key=Project,Value=encryption-demo}]' \
    --query 'Subnet.SubnetId' --output text)

export SUBNET_2=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block 10.0.2.0/24 \
    --availability-zone "${AWS_REGION}b" \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=encryption-demo-subnet-2},{Key=Project,Value=encryption-demo}]' \
    --query 'Subnet.SubnetId' --output text)

# Create route table
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
    --vpc-id "$VPC_ID" \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=encryption-demo-rt},{Key=Project,Value=encryption-demo}]' \
    --query 'RouteTable.RouteTableId' --output text)

# Add route to Internet Gateway
aws ec2 create-route \
    --route-table-id "$ROUTE_TABLE_ID" \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id "$IGW_ID"

# Associate route table with subnets
aws ec2 associate-route-table --route-table-id "$ROUTE_TABLE_ID" --subnet-id "$SUBNET_1"
aws ec2 associate-route-table --route-table-id "$ROUTE_TABLE_ID" --subnet-id "$SUBNET_2"

# Update environment file with network resources
cat >> .env << EOF
VPC_ID=$VPC_ID
IGW_ID=$IGW_ID
SUBNET_1=$SUBNET_1
SUBNET_2=$SUBNET_2
ROUTE_TABLE_ID=$ROUTE_TABLE_ID
EOF

success "VPC and networking components created"

# =============================================================================
# KMS KEY CREATION
# =============================================================================
log "Creating KMS customer-managed key..."

# Create KMS key with comprehensive policy
export KMS_KEY_ID=$(aws kms create-key \
    --description "Customer managed key for data encryption demo" \
    --key-usage ENCRYPT_DECRYPT \
    --key-spec SYMMETRIC_DEFAULT \
    --policy '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "Enable root permissions",
                "Effect": "Allow",
                "Principal": {
                    "AWS": "arn:aws:iam::'$AWS_ACCOUNT_ID':root"
                },
                "Action": "kms:*",
                "Resource": "*"
            },
            {
                "Sid": "Allow use of the key for encryption services",
                "Effect": "Allow",
                "Principal": {
                    "AWS": "arn:aws:iam::'$AWS_ACCOUNT_ID':root"
                },
                "Action": [
                    "kms:Decrypt",
                    "kms:GenerateDataKey",
                    "kms:CreateGrant"
                ],
                "Resource": "*"
            }
        ]
    }' \
    --tags TagKey=Name,TagValue=encryption-demo-key TagKey=Project,TagValue=encryption-demo \
    --query 'KeyMetadata.KeyId' --output text)

# Create alias for easier management
aws kms create-alias \
    --alias-name "$KMS_KEY_ALIAS" \
    --target-key-id "$KMS_KEY_ID"

# Enable key rotation
aws kms enable-key-rotation --key-id "$KMS_KEY_ID"

success "KMS key created: $KMS_KEY_ID with alias: $KMS_KEY_ALIAS"

# =============================================================================
# S3 BUCKET WITH ENCRYPTION
# =============================================================================
log "Creating S3 bucket with server-side encryption..."

# Create S3 bucket with encryption enabled
if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$AWS_REGION"
else
    aws s3api create-bucket \
        --bucket "$S3_BUCKET_NAME" \
        --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION"
fi

# Enable default encryption with KMS
aws s3api put-bucket-encryption \
    --bucket "$S3_BUCKET_NAME" \
    --server-side-encryption-configuration '{
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "aws:kms",
                    "KMSMasterKeyID": "'$KMS_KEY_ID'"
                },
                "BucketKeyEnabled": true
            }
        ]
    }'

# Block public access for security
aws s3api put-public-access-block \
    --bucket "$S3_BUCKET_NAME" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Add bucket versioning
aws s3api put-bucket-versioning \
    --bucket "$S3_BUCKET_NAME" \
    --versioning-configuration Status=Enabled

# Add bucket tagging
aws s3api put-bucket-tagging \
    --bucket "$S3_BUCKET_NAME" \
    --tagging 'TagSet=[{Key=Name,Value=encryption-demo-bucket},{Key=Project,Value=encryption-demo}]'

success "S3 bucket created with encryption: $S3_BUCKET_NAME"

# =============================================================================
# DATABASE SUBNET GROUP AND SECURITY GROUP
# =============================================================================
log "Creating database subnet group and security group..."

# Create DB subnet group
aws rds create-db-subnet-group \
    --db-subnet-group-name encryption-demo-subnet-group \
    --db-subnet-group-description "Subnet group for encrypted RDS demo" \
    --subnet-ids "$SUBNET_1" "$SUBNET_2" \
    --tags Key=Name,Value=encryption-demo-subnet-group Key=Project,Value=encryption-demo

# Create security group for RDS
export DB_SECURITY_GROUP=$(aws ec2 create-security-group \
    --group-name encryption-demo-db-sg \
    --description "Security group for encrypted RDS database" \
    --vpc-id "$VPC_ID" \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=encryption-demo-db-sg},{Key=Project,Value=encryption-demo}]' \
    --query 'GroupId' --output text)

# Allow MySQL/Aurora access from within VPC
aws ec2 authorize-security-group-ingress \
    --group-id "$DB_SECURITY_GROUP" \
    --protocol tcp \
    --port 3306 \
    --cidr 10.0.0.0/16

success "Database subnet group and security group created"

# =============================================================================
# SECRETS MANAGER SETUP
# =============================================================================
log "Setting up Secrets Manager with encrypted credentials..."

# Generate random password for database
DB_PASSWORD=$(aws secretsmanager get-random-password \
    --password-length 16 \
    --exclude-characters '"@/\' \
    --require-each-included-type \
    --query 'RandomPassword' --output text)

# Create encrypted secret
aws secretsmanager create-secret \
    --name "$SECRET_NAME" \
    --description "Database credentials for encryption demo" \
    --secret-string '{
        "username": "admin",
        "password": "'$DB_PASSWORD'",
        "engine": "mysql",
        "host": "placeholder",
        "port": 3306,
        "dbname": "encrypteddemo"
    }' \
    --kms-key-id "$KMS_KEY_ID" \
    --tags Key=Name,Value=encryption-demo-secret Key=Project,Value=encryption-demo

success "Secrets Manager secret created: $SECRET_NAME"

# =============================================================================
# RDS DATABASE WITH ENCRYPTION
# =============================================================================
log "Creating RDS database with encryption at rest..."

# Create encrypted RDS MySQL instance
aws rds create-db-instance \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --db-instance-class db.t3.micro \
    --engine mysql \
    --master-username admin \
    --master-user-password "$DB_PASSWORD" \
    --allocated-storage 20 \
    --storage-type gp2 \
    --storage-encrypted \
    --kms-key-id "$KMS_KEY_ID" \
    --db-subnet-group-name encryption-demo-subnet-group \
    --vpc-security-group-ids "$DB_SECURITY_GROUP" \
    --backup-retention-period 7 \
    --copy-tags-to-snapshot \
    --deletion-protection \
    --tags Key=Name,Value=encryption-demo-rds Key=Project,Value=encryption-demo

# Wait for DB to be available
log "Waiting for RDS instance to be available (this may take 5-10 minutes)..."
aws rds wait db-instance-available \
    --db-instance-identifier "$RDS_INSTANCE_ID"

# Get RDS endpoint
export RDS_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier "$RDS_INSTANCE_ID" \
    --query 'DBInstances[0].Endpoint.Address' --output text)

success "RDS instance created: $RDS_INSTANCE_ID"
log "RDS endpoint: $RDS_ENDPOINT"

# =============================================================================
# UPDATE SECRET WITH RDS ENDPOINT
# =============================================================================
log "Updating secret with RDS endpoint..."

# Update secret with actual RDS endpoint
aws secretsmanager update-secret \
    --secret-id "$SECRET_NAME" \
    --secret-string '{
        "username": "admin",
        "password": "'$DB_PASSWORD'",
        "engine": "mysql",
        "host": "'$RDS_ENDPOINT'",
        "port": 3306,
        "dbname": "encrypteddemo"
    }'

success "Secret updated with RDS endpoint"

# =============================================================================
# EC2 INSTANCE WITH ENCRYPTED EBS
# =============================================================================
log "Creating EC2 instance with encrypted EBS volumes..."

# Get latest Amazon Linux 2 AMI
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text)

# Create key pair for EC2 access
aws ec2 create-key-pair \
    --key-name encryption-demo-key \
    --key-type rsa \
    --tag-specifications 'ResourceType=key-pair,Tags=[{Key=Name,Value=encryption-demo-key},{Key=Project,Value=encryption-demo}]' \
    --query 'KeyMaterial' --output text > encryption-demo-key.pem

chmod 400 encryption-demo-key.pem

# Create security group for EC2
export EC2_SECURITY_GROUP=$(aws ec2 create-security-group \
    --group-name encryption-demo-ec2-sg \
    --description "Security group for encrypted EC2 demo" \
    --vpc-id "$VPC_ID" \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=encryption-demo-ec2-sg},{Key=Project,Value=encryption-demo}]' \
    --query 'GroupId' --output text)

# Allow SSH access (restrict to your IP in production)
aws ec2 authorize-security-group-ingress \
    --group-id "$EC2_SECURITY_GROUP" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

# Allow HTTPS traffic
aws ec2 authorize-security-group-ingress \
    --group-id "$EC2_SECURITY_GROUP" \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0

# Launch EC2 instance with encrypted EBS volume
export EC2_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type t3.micro \
    --key-name encryption-demo-key \
    --security-group-ids "$EC2_SECURITY_GROUP" \
    --subnet-id "$SUBNET_1" \
    --associate-public-ip-address \
    --block-device-mappings '[
        {
            "DeviceName": "/dev/xvda",
            "Ebs": {
                "VolumeSize": 8,
                "VolumeType": "gp2",
                "DeleteOnTermination": true,
                "Encrypted": true,
                "KmsKeyId": "'$KMS_KEY_ID'"
            }
        }
    ]' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=encryption-demo-ec2},{Key=Project,Value=encryption-demo}]' \
    --query 'Instances[0].InstanceId' --output text)

# Wait for instance to be running
log "Waiting for EC2 instance to be running..."
aws ec2 wait instance-running --instance-ids "$EC2_INSTANCE_ID"

# Get instance public IP
EC2_PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$EC2_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

success "EC2 instance created: $EC2_INSTANCE_ID"
log "EC2 public IP: $EC2_PUBLIC_IP"

# =============================================================================
# CLOUDTRAIL SETUP
# =============================================================================
log "Setting up CloudTrail for encryption events logging..."

# Create CloudTrail bucket
export CLOUDTRAIL_BUCKET="${S3_BUCKET_NAME}-cloudtrail"

# Create separate bucket for CloudTrail logs
if [[ "$AWS_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$CLOUDTRAIL_BUCKET" --region "$AWS_REGION"
else
    aws s3api create-bucket \
        --bucket "$CLOUDTRAIL_BUCKET" \
        --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION"
fi

# Apply CloudTrail bucket policy
aws s3api put-bucket-policy \
    --bucket "$CLOUDTRAIL_BUCKET" \
    --policy '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "AWSCloudTrailAclCheck",
                "Effect": "Allow",
                "Principal": {
                    "Service": "cloudtrail.amazonaws.com"
                },
                "Action": "s3:GetBucketAcl",
                "Resource": "arn:aws:s3:::'$CLOUDTRAIL_BUCKET'"
            },
            {
                "Sid": "AWSCloudTrailWrite",
                "Effect": "Allow",
                "Principal": {
                    "Service": "cloudtrail.amazonaws.com"
                },
                "Action": "s3:PutObject",
                "Resource": "arn:aws:s3:::'$CLOUDTRAIL_BUCKET'/AWSLogs/'$AWS_ACCOUNT_ID'/*",
                "Condition": {
                    "StringEquals": {
                        "s3:x-amz-acl": "bucket-owner-full-control"
                    }
                }
            }
        ]
    }'

# Enable CloudTrail
aws cloudtrail create-trail \
    --name encryption-demo-trail \
    --s3-bucket-name "$CLOUDTRAIL_BUCKET" \
    --include-global-service-events \
    --is-multi-region-trail \
    --enable-log-file-validation \
    --event-selectors '[
        {
            "ReadWriteType": "All",
            "IncludeManagementEvents": true,
            "DataResources": [
                {
                    "Type": "AWS::KMS::Key",
                    "Values": ["arn:aws:kms:*:*:key/*"]
                }
            ]
        }
    ]' \
    --tags-list Key=Name,Value=encryption-demo-trail Key=Project,Value=encryption-demo

# Start logging
aws cloudtrail start-logging \
    --name encryption-demo-trail

success "CloudTrail configured for encryption events"

# =============================================================================
# FINAL CONFIGURATION UPDATE
# =============================================================================
# Update environment file with all resource IDs
cat >> .env << EOF
KMS_KEY_ID=$KMS_KEY_ID
DB_SECURITY_GROUP=$DB_SECURITY_GROUP
EC2_SECURITY_GROUP=$EC2_SECURITY_GROUP
RDS_ENDPOINT=$RDS_ENDPOINT
EC2_INSTANCE_ID=$EC2_INSTANCE_ID
EC2_PUBLIC_IP=$EC2_PUBLIC_IP
CLOUDTRAIL_BUCKET=$CLOUDTRAIL_BUCKET
EOF

# =============================================================================
# TESTING AND VALIDATION
# =============================================================================
log "Testing encryption implementation..."

# Test S3 encryption by uploading a file
echo "Sensitive data for encryption test - $(date)" > test-file.txt
aws s3 cp test-file.txt "s3://$S3_BUCKET_NAME/"

# Verify encryption
ENCRYPTION_CHECK=$(aws s3api head-object \
    --bucket "$S3_BUCKET_NAME" \
    --key test-file.txt \
    --query 'ServerSideEncryption' --output text)

if [[ "$ENCRYPTION_CHECK" == "aws:kms" ]]; then
    success "S3 encryption verified"
else
    error "S3 encryption verification failed"
fi

# Test KMS key usage
KMS_TEST=$(aws kms generate-data-key \
    --key-id "$KMS_KEY_ID" \
    --key-spec AES_256 \
    --query 'KeyId' --output text)

if [[ -n "$KMS_TEST" ]]; then
    success "KMS key functionality verified"
else
    error "KMS key verification failed"
fi

# Clean up test file
rm test-file.txt

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================
echo ""
echo "============================================================================="
echo "                     DEPLOYMENT COMPLETED SUCCESSFULLY"
echo "============================================================================="
echo ""
echo "Resources created:"
echo "  • KMS Key: $KMS_KEY_ID"
echo "  • KMS Alias: $KMS_KEY_ALIAS"
echo "  • S3 Bucket: $S3_BUCKET_NAME"
echo "  • RDS Instance: $RDS_INSTANCE_ID"
echo "  • RDS Endpoint: $RDS_ENDPOINT"
echo "  • EC2 Instance: $EC2_INSTANCE_ID"
echo "  • EC2 Public IP: $EC2_PUBLIC_IP"
echo "  • Secret: $SECRET_NAME"
echo "  • CloudTrail: encryption-demo-trail"
echo ""
echo "Configuration saved to: .env"
echo ""
echo "To connect to EC2 instance:"
echo "  ssh -i encryption-demo-key.pem ec2-user@$EC2_PUBLIC_IP"
echo ""
echo "To clean up resources, run:"
echo "  ./destroy.sh"
echo ""
echo "============================================================================="

success "Deployment completed successfully!"