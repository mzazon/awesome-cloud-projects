#!/bin/bash

# AWS Storage Gateway Hybrid Cloud Storage Deployment Script
# This script deploys a complete Storage Gateway solution with File Gateway configuration

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some output formatting may be limited."
    fi
    
    # Check required AWS permissions
    log "Verifying AWS permissions..."
    aws iam get-user &> /dev/null || {
        error "Unable to verify AWS IAM permissions. Ensure you have appropriate access."
        exit 1
    }
    
    success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export GATEWAY_NAME="hybrid-gateway-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="storage-gateway-bucket-${RANDOM_SUFFIX}"
    export KMS_KEY_ALIAS="alias/storage-gateway-key-${RANDOM_SUFFIX}"
    
    # Create deployment state file
    cat > deployment_state.env << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
GATEWAY_NAME=${GATEWAY_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
KMS_KEY_ALIAS=${KMS_KEY_ALIAS}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables configured"
    log "Gateway Name: ${GATEWAY_NAME}"
    log "S3 Bucket: ${S3_BUCKET_NAME}"
    log "AWS Region: ${AWS_REGION}"
}

# Function to create foundational resources
create_foundational_resources() {
    log "Creating foundational resources..."
    
    # Create S3 bucket for File Gateway
    log "Creating S3 bucket: ${S3_BUCKET_NAME}"
    if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
        warning "S3 bucket ${S3_BUCKET_NAME} already exists"
    else
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3api create-bucket --bucket "${S3_BUCKET_NAME}"
        else
            aws s3api create-bucket \
                --bucket "${S3_BUCKET_NAME}" \
                --region "${AWS_REGION}" \
                --create-bucket-configuration LocationConstraint="${AWS_REGION}"
        fi
        success "S3 bucket created: ${S3_BUCKET_NAME}"
    fi
    
    # Enable versioning on S3 bucket
    log "Enabling S3 bucket versioning..."
    aws s3api put-bucket-versioning \
        --bucket "${S3_BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    # Create KMS key for encryption
    log "Creating KMS key for encryption..."
    if aws kms describe-key --key-id "${KMS_KEY_ALIAS}" &>/dev/null; then
        warning "KMS key alias ${KMS_KEY_ALIAS} already exists"
        KMS_KEY_ID=$(aws kms describe-key --key-id "${KMS_KEY_ALIAS}" --query KeyMetadata.KeyId --output text)
    else
        KMS_KEY_ID=$(aws kms create-key \
            --description "Storage Gateway encryption key" \
            --query KeyMetadata.KeyId --output text)
        
        aws kms create-alias \
            --alias-name "${KMS_KEY_ALIAS}" \
            --target-key-id "${KMS_KEY_ID}"
        
        success "KMS key created: ${KMS_KEY_ID}"
    fi
    
    # Store KMS key ID in state
    echo "KMS_KEY_ID=${KMS_KEY_ID}" >> deployment_state.env
    export KMS_KEY_ID
    
    success "Foundational resources created"
}

# Function to create IAM role for Storage Gateway
create_iam_role() {
    log "Creating IAM role for Storage Gateway..."
    
    # Check if role already exists
    if aws iam get-role --role-name StorageGatewayRole &>/dev/null; then
        warning "IAM role StorageGatewayRole already exists"
    else
        # Create trust policy document
        cat > storage-gateway-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "storagegateway.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
        
        # Create IAM role
        aws iam create-role \
            --role-name StorageGatewayRole \
            --assume-role-policy-document file://storage-gateway-trust-policy.json
        
        # Attach required policies
        aws iam attach-role-policy \
            --role-name StorageGatewayRole \
            --policy-arn arn:aws:iam::aws:policy/service-role/StorageGatewayServiceRole
        
        success "IAM role created: StorageGatewayRole"
    fi
    
    GATEWAY_ROLE_ARN=$(aws iam get-role \
        --role-name StorageGatewayRole \
        --query Role.Arn --output text)
    
    # Store role ARN in state
    echo "GATEWAY_ROLE_ARN=${GATEWAY_ROLE_ARN}" >> deployment_state.env
    export GATEWAY_ROLE_ARN
    
    success "IAM role configured: ${GATEWAY_ROLE_ARN}"
}

# Function to deploy Storage Gateway VM
deploy_storage_gateway_vm() {
    log "Deploying Storage Gateway VM..."
    
    # Find the latest Storage Gateway AMI
    log "Finding latest Storage Gateway AMI..."
    GATEWAY_AMI=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=aws-storage-gateway-*" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    if [ -z "$GATEWAY_AMI" ] || [ "$GATEWAY_AMI" = "None" ]; then
        error "Could not find Storage Gateway AMI"
        exit 1
    fi
    
    log "Using Storage Gateway AMI: ${GATEWAY_AMI}"
    
    # Create security group for Storage Gateway
    log "Creating security group..."
    SG_ID=$(aws ec2 create-security-group \
        --group-name "storage-gateway-sg-${RANDOM_SUFFIX}" \
        --description "Security group for Storage Gateway" \
        --query GroupId --output text 2>/dev/null || \
        aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=storage-gateway-sg-${RANDOM_SUFFIX}" \
        --query 'SecurityGroups[0].GroupId' --output text)
    
    # Add required inbound rules (idempotent)
    aws ec2 authorize-security-group-ingress \
        --group-id "${SG_ID}" \
        --protocol tcp --port 80 \
        --cidr 0.0.0.0/0 2>/dev/null || true
    
    aws ec2 authorize-security-group-ingress \
        --group-id "${SG_ID}" \
        --protocol tcp --port 443 \
        --cidr 0.0.0.0/0 2>/dev/null || true
    
    aws ec2 authorize-security-group-ingress \
        --group-id "${SG_ID}" \
        --protocol tcp --port 2049 \
        --cidr 10.0.0.0/8 2>/dev/null || true
    
    # Launch Storage Gateway instance
    log "Launching Storage Gateway instance..."
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "${GATEWAY_AMI}" \
        --instance-type m5.large \
        --security-group-ids "${SG_ID}" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${GATEWAY_NAME}},{Key=Purpose,Value=StorageGateway}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    # Store instance details in state
    echo "SG_ID=${SG_ID}" >> deployment_state.env
    echo "INSTANCE_ID=${INSTANCE_ID}" >> deployment_state.env
    echo "GATEWAY_AMI=${GATEWAY_AMI}" >> deployment_state.env
    
    export SG_ID INSTANCE_ID GATEWAY_AMI
    
    success "Storage Gateway instance launched: ${INSTANCE_ID}"
}

# Function to wait for instance and get activation key
wait_for_activation() {
    log "Waiting for instance to be ready..."
    
    # Wait for instance to be running
    aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
    success "Instance is running"
    
    # Get public IP address
    GATEWAY_IP=$(aws ec2 describe-instances \
        --instance-ids "${INSTANCE_ID}" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    if [ -z "$GATEWAY_IP" ] || [ "$GATEWAY_IP" = "None" ]; then
        error "Could not get instance public IP address"
        exit 1
    fi
    
    log "Gateway IP: ${GATEWAY_IP}"
    
    # Wait for Storage Gateway to be ready (this may take 5-10 minutes)
    log "Waiting for Storage Gateway to be ready (this may take 5-10 minutes)..."
    RETRY_COUNT=0
    MAX_RETRIES=30
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if curl -s -m 10 "http://${GATEWAY_IP}/?activationRegion=${AWS_REGION}" &>/dev/null; then
            break
        fi
        log "Gateway not ready yet, waiting 30 seconds... (attempt $((RETRY_COUNT + 1))/${MAX_RETRIES})"
        sleep 30
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done
    
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        error "Storage Gateway did not become ready within the expected time"
        exit 1
    fi
    
    # Get activation key
    log "Getting activation key..."
    ACTIVATION_KEY=$(curl -s "http://${GATEWAY_IP}/?activationRegion=${AWS_REGION}" | \
        grep -o 'activationKey=[^&]*' | cut -d'=' -f2)
    
    if [ -z "$ACTIVATION_KEY" ]; then
        error "Could not obtain activation key"
        exit 1
    fi
    
    # Store in state
    echo "GATEWAY_IP=${GATEWAY_IP}" >> deployment_state.env
    echo "ACTIVATION_KEY=${ACTIVATION_KEY}" >> deployment_state.env
    
    export GATEWAY_IP ACTIVATION_KEY
    
    success "Activation key obtained: ${ACTIVATION_KEY}"
}

# Function to activate Storage Gateway
activate_gateway() {
    log "Activating Storage Gateway..."
    
    GATEWAY_ARN=$(aws storagegateway activate-gateway \
        --activation-key "${ACTIVATION_KEY}" \
        --gateway-name "${GATEWAY_NAME}" \
        --gateway-timezone GMT-5:00 \
        --gateway-region "${AWS_REGION}" \
        --gateway-type FILE_S3 \
        --query GatewayARN --output text)
    
    if [ -z "$GATEWAY_ARN" ]; then
        error "Failed to activate Storage Gateway"
        exit 1
    fi
    
    # Store in state
    echo "GATEWAY_ARN=${GATEWAY_ARN}" >> deployment_state.env
    export GATEWAY_ARN
    
    success "Storage Gateway activated: ${GATEWAY_ARN}"
}

# Function to configure storage
configure_storage() {
    log "Configuring local storage for gateway..."
    
    # Create and attach additional EBS volume for cache
    log "Creating EBS volume for cache storage..."
    AVAILABILITY_ZONE=$(aws ec2 describe-instances \
        --instance-ids "${INSTANCE_ID}" \
        --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' \
        --output text)
    
    VOLUME_ID=$(aws ec2 create-volume \
        --size 100 \
        --volume-type gp3 \
        --availability-zone "${AVAILABILITY_ZONE}" \
        --tag-specifications "ResourceType=volume,Tags=[{Key=Name,Value=${GATEWAY_NAME}-cache},{Key=Purpose,Value=StorageGatewayCache}]" \
        --query VolumeId --output text)
    
    # Wait for volume to be available
    log "Waiting for volume to be available..."
    aws ec2 wait volume-available --volume-ids "${VOLUME_ID}"
    
    # Attach volume to instance
    log "Attaching volume to instance..."
    aws ec2 attach-volume \
        --volume-id "${VOLUME_ID}" \
        --instance-id "${INSTANCE_ID}" \
        --device /dev/sdf
    
    # Wait for attachment
    sleep 30
    
    # Get disk ID for the attached volume
    log "Configuring cache storage..."
    RETRY_COUNT=0
    MAX_RETRIES=10
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        DISK_ID=$(aws storagegateway list-local-disks \
            --gateway-arn "${GATEWAY_ARN}" \
            --query 'Disks[?DiskPath==`/dev/sdf`].DiskId' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$DISK_ID" ] && [ "$DISK_ID" != "None" ]; then
            break
        fi
        
        log "Waiting for disk to be recognized... (attempt $((RETRY_COUNT + 1))/${MAX_RETRIES})"
        sleep 15
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done
    
    if [ -z "$DISK_ID" ] || [ "$DISK_ID" = "None" ]; then
        error "Could not find attached disk for cache storage"
        exit 1
    fi
    
    # Add disk as cache storage
    aws storagegateway add-cache \
        --gateway-arn "${GATEWAY_ARN}" \
        --disk-ids "${DISK_ID}"
    
    # Store in state
    echo "VOLUME_ID=${VOLUME_ID}" >> deployment_state.env
    echo "DISK_ID=${DISK_ID}" >> deployment_state.env
    
    export VOLUME_ID DISK_ID
    
    success "Cache storage configured with disk: ${DISK_ID}"
}

# Function to create file shares
create_file_shares() {
    log "Creating file shares..."
    
    # Create NFS file share
    log "Creating NFS file share..."
    FILE_SHARE_ARN=$(aws storagegateway create-nfs-file-share \
        --client-token "$(date +%s)" \
        --gateway-arn "${GATEWAY_ARN}" \
        --location-arn "arn:aws:s3:::${S3_BUCKET_NAME}" \
        --role "${GATEWAY_ROLE_ARN}" \
        --default-storage-class S3_STANDARD \
        --nfs-file-share-defaults '{"FileMode":"0644","DirectoryMode":"0755","GroupId":65534,"OwnerId":65534}' \
        --client-list "10.0.0.0/8" \
        --squash RootSquash \
        --query FileShareARN --output text)
    
    # Create SMB file share
    log "Creating SMB file share..."
    SMB_SHARE_ARN=$(aws storagegateway create-smb-file-share \
        --client-token "$(date +%s)" \
        --gateway-arn "${GATEWAY_ARN}" \
        --location-arn "arn:aws:s3:::${S3_BUCKET_NAME}/smb-share" \
        --role "${GATEWAY_ROLE_ARN}" \
        --default-storage-class S3_STANDARD \
        --authentication GuestAccess \
        --query FileShareARN --output text)
    
    # Store in state
    echo "FILE_SHARE_ARN=${FILE_SHARE_ARN}" >> deployment_state.env
    echo "SMB_SHARE_ARN=${SMB_SHARE_ARN}" >> deployment_state.env
    
    export FILE_SHARE_ARN SMB_SHARE_ARN
    
    success "NFS file share created: ${FILE_SHARE_ARN}"
    success "SMB file share created: ${SMB_SHARE_ARN}"
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring CloudWatch monitoring..."
    
    # Create CloudWatch log group
    aws logs create-log-group \
        --log-group-name "/aws/storagegateway/${GATEWAY_NAME}" 2>/dev/null || \
        warning "CloudWatch log group may already exist"
    
    # Enable CloudWatch metrics
    aws storagegateway update-gateway-information \
        --gateway-arn "${GATEWAY_ARN}" \
        --cloudwatch-log-group-arn \
        "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/storagegateway/${GATEWAY_NAME}" \
        2>/dev/null || warning "CloudWatch monitoring may already be configured"
    
    success "CloudWatch monitoring configured"
}

# Function to display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    
    # Get gateway network interface
    GATEWAY_NETWORK_INTERFACE=$(aws storagegateway describe-gateway-information \
        --gateway-arn "${GATEWAY_ARN}" \
        --query 'NetworkInterfaces[0].Ipv4Address' \
        --output text 2>/dev/null || echo "${GATEWAY_IP}")
    
    echo ""
    success "=== DEPLOYMENT SUMMARY ==="
    echo "Gateway Name: ${GATEWAY_NAME}"
    echo "Gateway ARN: ${GATEWAY_ARN}"
    echo "Gateway IP: ${GATEWAY_IP}"
    echo "S3 Bucket: ${S3_BUCKET_NAME}"
    echo "Instance ID: ${INSTANCE_ID}"
    echo ""
    echo "File Share Connection Commands:"
    echo "NFS: sudo mount -t nfs ${GATEWAY_NETWORK_INTERFACE}:/${S3_BUCKET_NAME} /local/mount/point"
    echo "SMB: sudo mount -t cifs //${GATEWAY_NETWORK_INTERFACE}/${S3_BUCKET_NAME} /local/mount/point"
    echo ""
    echo "Deployment state saved to: deployment_state.env"
    echo "Use destroy.sh to clean up all resources"
    echo ""
}

# Function to handle cleanup on error
cleanup_on_error() {
    error "Deployment failed. Cleaning up partial resources..."
    
    if [ -f "deployment_state.env" ]; then
        source deployment_state.env 2>/dev/null || true
        
        # Clean up in reverse order
        [ -n "${FILE_SHARE_ARN:-}" ] && aws storagegateway delete-file-share --file-share-arn "${FILE_SHARE_ARN}" 2>/dev/null || true
        [ -n "${SMB_SHARE_ARN:-}" ] && aws storagegateway delete-file-share --file-share-arn "${SMB_SHARE_ARN}" 2>/dev/null || true
        [ -n "${GATEWAY_ARN:-}" ] && aws storagegateway delete-gateway --gateway-arn "${GATEWAY_ARN}" 2>/dev/null || true
        [ -n "${INSTANCE_ID:-}" ] && aws ec2 terminate-instances --instance-ids "${INSTANCE_ID}" 2>/dev/null || true
        
        sleep 30
        
        [ -n "${SG_ID:-}" ] && aws ec2 delete-security-group --group-id "${SG_ID}" 2>/dev/null || true
        [ -n "${S3_BUCKET_NAME:-}" ] && (aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive 2>/dev/null || true; aws s3api delete-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null || true)
    fi
    
    # Clean up local files
    rm -f storage-gateway-trust-policy.json deployment_state.env
    
    error "Partial cleanup completed. Some resources may need manual removal."
}

# Main deployment function
main() {
    log "Starting AWS Storage Gateway deployment..."
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    check_prerequisites
    setup_environment
    create_foundational_resources
    create_iam_role
    deploy_storage_gateway_vm
    wait_for_activation
    activate_gateway
    configure_storage
    create_file_shares
    configure_monitoring
    display_summary
    
    # Clean up temporary files
    rm -f storage-gateway-trust-policy.json
    
    success "Deployment completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi