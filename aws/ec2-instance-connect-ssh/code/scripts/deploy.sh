#!/bin/bash

# Deploy script for EC2 Instance Connect Secure SSH Access
# This script automates the deployment of EC2 Instance Connect infrastructure
# following the recipe: "Secure SSH Access with EC2 Instance Connect"

set -euo pipefail

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up resources..."
    
    # Remove temporary files
    rm -f temp-key temp-key.pub ec2-connect-policy.json ec2-connect-restrictive-policy.json
    
    # Attempt to clean up resources if they were created
    if [[ -n "${INSTANCE_ID:-}" ]]; then
        log_info "Terminating EC2 instance: $INSTANCE_ID"
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" 2>/dev/null || true
    fi
    
    if [[ -n "${PRIVATE_INSTANCE_ID:-}" ]]; then
        log_info "Terminating private EC2 instance: $PRIVATE_INSTANCE_ID"
        aws ec2 terminate-instances --instance-ids "$PRIVATE_INSTANCE_ID" 2>/dev/null || true
    fi
    
    if [[ -n "${EICE_ID:-}" ]]; then
        log_info "Deleting Instance Connect Endpoint: $EICE_ID"
        aws ec2 delete-instance-connect-endpoint --instance-connect-endpoint-id "$EICE_ID" 2>/dev/null || true
    fi
    
    if [[ -n "${SG_ID:-}" ]]; then
        log_info "Deleting security group: $SG_ID"
        aws ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null || true
    fi
    
    if [[ -n "${PRIVATE_SUBNET_ID:-}" ]]; then
        log_info "Deleting private subnet: $PRIVATE_SUBNET_ID"
        aws ec2 delete-subnet --subnet-id "$PRIVATE_SUBNET_ID" 2>/dev/null || true
    fi
}

# Set trap for error cleanup
trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set up credentials."
    fi
    
    # Check if SSH is available
    if ! command -v ssh &> /dev/null; then
        error_exit "SSH client is not installed."
    fi
    
    # Check if ssh-keygen is available
    if ! command -v ssh-keygen &> /dev/null; then
        error_exit "ssh-keygen is not installed."
    fi
    
    log_success "Prerequisites check completed"
}

# Environment setup
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "No default region configured, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set resource names
    export KEY_PAIR_NAME="ec2-connect-key-${RANDOM_SUFFIX}"
    export INSTANCE_NAME="ec2-connect-test-${RANDOM_SUFFIX}"
    export POLICY_NAME="EC2InstanceConnectPolicy-${RANDOM_SUFFIX}"
    export ROLE_NAME="EC2InstanceConnectRole-${RANDOM_SUFFIX}"
    export USER_NAME="ec2-connect-user-${RANDOM_SUFFIX}"
    export TRAIL_NAME="ec2-connect-audit-${RANDOM_SUFFIX}"
    export BUCKET_NAME="ec2-connect-logs-${RANDOM_SUFFIX}-${AWS_ACCOUNT_ID}"
    
    # Get default VPC and subnet information
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text)
    
    if [[ "$VPC_ID" == "None" ]] || [[ -z "$VPC_ID" ]]; then
        error_exit "No default VPC found. Please create a VPC first."
    fi
    
    export SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
            "Name=default-for-az,Values=true" \
        --query "Subnets[0].SubnetId" --output text)
    
    if [[ "$SUBNET_ID" == "None" ]] || [[ -z "$SUBNET_ID" ]]; then
        error_exit "No default subnet found in VPC $VPC_ID"
    fi
    
    log_success "Environment prepared with VPC: ${VPC_ID}, Region: ${AWS_REGION}"
}

# Create IAM resources
create_iam_resources() {
    log_info "Creating IAM resources..."
    
    # Create IAM policy for EC2 Instance Connect access
    cat > ec2-connect-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2-instance-connect:SendSSHPublicKey"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "ec2:osuser": "ec2-user"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeVpcs"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create the policy
    aws iam create-policy \
        --policy-name "${POLICY_NAME}" \
        --policy-document file://ec2-connect-policy.json
    
    export POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
    log_success "IAM policy created: ${POLICY_ARN}"
    
    # Create IAM user for testing
    aws iam create-user --user-name "${USER_NAME}"
    log_success "IAM user created: ${USER_NAME}"
    
    # Attach the policy to the user
    aws iam attach-user-policy \
        --user-name "${USER_NAME}" \
        --policy-arn "${POLICY_ARN}"
    
    # Create access keys for the user
    ACCESS_KEY_OUTPUT=$(aws iam create-access-key \
        --user-name "${USER_NAME}" \
        --query 'AccessKey.{AccessKeyId:AccessKeyId,SecretAccessKey:SecretAccessKey}' \
        --output table)
    
    log_success "IAM user configured with EC2 Instance Connect permissions"
    echo "$ACCESS_KEY_OUTPUT"
}

# Create networking resources
create_networking() {
    log_info "Creating networking resources..."
    
    # Create security group
    export SG_ID=$(aws ec2 create-security-group \
        --group-name "ec2-connect-sg-${RANDOM_SUFFIX}" \
        --description "Security group for EC2 Instance Connect" \
        --vpc-id "${VPC_ID}" \
        --query 'GroupId' --output text)
    
    # Allow SSH access from anywhere (restrict as needed)
    aws ec2 authorize-security-group-ingress \
        --group-id "${SG_ID}" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0
    
    log_success "Security group created: ${SG_ID}"
    
    # Create a private subnet for demonstration
    export PRIVATE_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block "172.31.64.0/24" \
        --availability-zone "${AWS_REGION}a" \
        --query 'Subnet.SubnetId' --output text)
    
    log_success "Private subnet created: ${PRIVATE_SUBNET_ID}"
}

# Launch EC2 instances
launch_instances() {
    log_info "Launching EC2 instances..."
    
    # Get latest Amazon Linux 2023 AMI ID
    export AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=al2023-ami-*" \
            "Name=architecture,Values=x86_64" \
            "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    log_info "Using AMI: ${AMI_ID}"
    
    # Launch public EC2 instance
    export INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "${AMI_ID}" \
        --instance-type t2.micro \
        --security-group-ids "${SG_ID}" \
        --subnet-id "${SUBNET_ID}" \
        --associate-public-ip-address \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" \
        --query 'Instances[0].InstanceId' --output text)
    
    log_success "Public EC2 instance launched: ${INSTANCE_ID}"
    
    # Wait for instance to be running
    log_info "Waiting for public instance to be running..."
    aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
    
    # Get instance public IP
    export INSTANCE_IP=$(aws ec2 describe-instances \
        --instance-ids "${INSTANCE_ID}" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    log_success "Public instance is running with IP: ${INSTANCE_IP}"
}

# Create Instance Connect Endpoint
create_instance_connect_endpoint() {
    log_info "Creating EC2 Instance Connect Endpoint..."
    
    # Create EC2 Instance Connect Endpoint
    export EICE_ID=$(aws ec2 create-instance-connect-endpoint \
        --subnet-id "${PRIVATE_SUBNET_ID}" \
        --query 'InstanceConnectEndpoint.InstanceConnectEndpointId' \
        --output text)
    
    log_info "Waiting for Instance Connect Endpoint to be ready..."
    aws ec2 wait instance-connect-endpoint-available \
        --instance-connect-endpoint-ids "${EICE_ID}"
    
    log_success "Instance Connect Endpoint created: ${EICE_ID}"
}

# Launch private instance
launch_private_instance() {
    log_info "Launching private EC2 instance..."
    
    # Launch instance in private subnet
    export PRIVATE_INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "${AMI_ID}" \
        --instance-type t2.micro \
        --security-group-ids "${SG_ID}" \
        --subnet-id "${PRIVATE_SUBNET_ID}" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}-private}]" \
        --query 'Instances[0].InstanceId' --output text)
    
    # Wait for private instance to be running
    log_info "Waiting for private instance to be running..."
    aws ec2 wait instance-running \
        --instance-ids "${PRIVATE_INSTANCE_ID}"
    
    log_success "Private instance is running: ${PRIVATE_INSTANCE_ID}"
}

# Create advanced IAM policies
create_advanced_policies() {
    log_info "Creating advanced IAM policies..."
    
    # Create more restrictive policy with resource-level permissions
    cat > ec2-connect-restrictive-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "ec2-instance-connect:SendSSHPublicKey",
            "Resource": "arn:aws:ec2:${AWS_REGION}:${AWS_ACCOUNT_ID}:instance/${INSTANCE_ID}",
            "Condition": {
                "StringEquals": {
                    "ec2:osuser": "ec2-user"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeInstances",
                "ec2:DescribeVpcs"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create restrictive policy
    aws iam create-policy \
        --policy-name "${POLICY_NAME}-restrictive" \
        --policy-document file://ec2-connect-restrictive-policy.json
    
    log_success "Restrictive IAM policy created for specific instance"
}

# Setup CloudTrail
setup_cloudtrail() {
    log_info "Setting up CloudTrail for auditing..."
    
    # Create S3 bucket for CloudTrail logs
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3 mb s3://"${BUCKET_NAME}"
    else
        aws s3 mb s3://"${BUCKET_NAME}" --region "${AWS_REGION}"
    fi
    
    # Create bucket policy for CloudTrail
    cat > cloudtrail-bucket-policy.json << EOF
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
            "Resource": "arn:aws:s3:::${BUCKET_NAME}",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudtrail:${AWS_REGION}:${AWS_ACCOUNT_ID}:trail/${TRAIL_NAME}"
                }
            }
        },
        {
            "Sid": "AWSCloudTrailWrite",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/AWSLogs/${AWS_ACCOUNT_ID}/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control",
                    "AWS:SourceArn": "arn:aws:cloudtrail:${AWS_REGION}:${AWS_ACCOUNT_ID}:trail/${TRAIL_NAME}"
                }
            }
        }
    ]
}
EOF
    
    # Apply bucket policy
    aws s3api put-bucket-policy \
        --bucket "${BUCKET_NAME}" \
        --policy file://cloudtrail-bucket-policy.json
    
    # Create CloudTrail
    aws cloudtrail create-trail \
        --name "${TRAIL_NAME}" \
        --s3-bucket-name "${BUCKET_NAME}" \
        --include-global-service-events \
        --is-multi-region-trail
    
    # Start logging
    aws cloudtrail start-logging --name "${TRAIL_NAME}"
    
    log_success "CloudTrail enabled for connection auditing"
    
    # Clean up temporary policy file
    rm -f cloudtrail-bucket-policy.json
}

# Test connections
test_connections() {
    log_info "Testing EC2 Instance Connect functionality..."
    
    # Generate temporary key pair for testing
    ssh-keygen -t rsa -b 2048 -f temp-key -N "" -q
    
    # Test connection to public instance
    log_info "Testing connection to public instance..."
    aws ec2-instance-connect send-ssh-public-key \
        --instance-id "${INSTANCE_ID}" \
        --instance-os-user ec2-user \
        --ssh-public-key file://temp-key.pub
    
    # Quick connectivity test
    timeout 30 ssh -i temp-key ec2-user@"${INSTANCE_IP}" \
        -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
        'echo "✅ Public instance connection successful"' || log_warning "SSH test failed, but Instance Connect API call succeeded"
    
    log_success "Connection tests completed"
}

# Save deployment state
save_deployment_state() {
    log_info "Saving deployment state..."
    
    cat > deployment-state.env << EOF
# EC2 Instance Connect Deployment State
# Generated on: $(date)
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export VPC_ID="${VPC_ID}"
export SUBNET_ID="${SUBNET_ID}"
export PRIVATE_SUBNET_ID="${PRIVATE_SUBNET_ID}"
export SG_ID="${SG_ID}"
export INSTANCE_ID="${INSTANCE_ID}"
export PRIVATE_INSTANCE_ID="${PRIVATE_INSTANCE_ID}"
export INSTANCE_IP="${INSTANCE_IP}"
export EICE_ID="${EICE_ID}"
export POLICY_NAME="${POLICY_NAME}"
export USER_NAME="${USER_NAME}"
export POLICY_ARN="${POLICY_ARN}"
export TRAIL_NAME="${TRAIL_NAME}"
export BUCKET_NAME="${BUCKET_NAME}"
export INSTANCE_NAME="${INSTANCE_NAME}"
export AMI_ID="${AMI_ID}"
EOF
    
    log_success "Deployment state saved to deployment-state.env"
}

# Display deployment summary
display_summary() {
    log_success "EC2 Instance Connect deployment completed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "Public Instance ID: ${INSTANCE_ID}"
    echo "Public Instance IP: ${INSTANCE_IP}"
    echo "Private Instance ID: ${PRIVATE_INSTANCE_ID}"
    echo "Instance Connect Endpoint: ${EICE_ID}"
    echo "Security Group: ${SG_ID}"
    echo "IAM User: ${USER_NAME}"
    echo "CloudTrail: ${TRAIL_NAME}"
    echo
    echo "=== Test Connection Commands ==="
    echo "Connect to public instance:"
    echo "  aws ec2-instance-connect ssh --instance-id ${INSTANCE_ID} --os-user ec2-user"
    echo
    echo "Connect to private instance via endpoint:"
    echo "  aws ec2-instance-connect ssh --instance-id ${PRIVATE_INSTANCE_ID} --os-user ec2-user --connection-type eice"
    echo
    echo "=== Next Steps ==="
    echo "1. Test SSH connections using the commands above"
    echo "2. Review CloudTrail logs for connection auditing"
    echo "3. Customize IAM policies for your specific requirements"
    echo "4. When finished, run ./destroy.sh to clean up resources"
    echo
    log_warning "Remember to clean up resources to avoid ongoing charges!"
}

# Main deployment function
main() {
    echo "=== EC2 Instance Connect Deployment Script ==="
    echo "This script will deploy a complete EC2 Instance Connect infrastructure"
    echo
    
    check_prerequisites
    setup_environment
    create_iam_resources
    create_networking
    launch_instances
    create_instance_connect_endpoint
    launch_private_instance
    create_advanced_policies
    setup_cloudtrail
    test_connections
    save_deployment_state
    
    # Clean up temporary files
    rm -f temp-key temp-key.pub ec2-connect-policy.json ec2-connect-restrictive-policy.json
    
    display_summary
}

# Run main function
main "$@"