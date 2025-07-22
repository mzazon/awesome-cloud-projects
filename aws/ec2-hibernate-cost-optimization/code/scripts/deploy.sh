#!/bin/bash

# EC2 Hibernation Cost Optimization - Deployment Script
# This script deploys the infrastructure for testing EC2 hibernation capabilities

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if jq is installed (optional but helpful)
    if ! command_exists jq; then
        warn "jq is not installed. JSON parsing will be limited."
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "AWS region not configured, using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export KEY_PAIR_NAME="hibernate-demo-key-${RANDOM_SUFFIX}"
    export INSTANCE_NAME="hibernate-demo-instance-${RANDOM_SUFFIX}"
    export TOPIC_NAME="hibernate-notifications-${RANDOM_SUFFIX}"
    export SECURITY_GROUP_NAME="hibernate-demo-sg-${RANDOM_SUFFIX}"
    
    # Store variables in a file for cleanup script
    cat > .env << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export KEY_PAIR_NAME="${KEY_PAIR_NAME}"
export INSTANCE_NAME="${INSTANCE_NAME}"
export TOPIC_NAME="${TOPIC_NAME}"
export SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME}"
EOF
    
    log "Environment variables set successfully"
    info "AWS Region: ${AWS_REGION}"
    info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    info "Resource suffix: ${RANDOM_SUFFIX}"
}

# Function to create key pair
create_key_pair() {
    log "Creating EC2 key pair..."
    
    # Check if key pair already exists
    if aws ec2 describe-key-pairs --key-names "${KEY_PAIR_NAME}" >/dev/null 2>&1; then
        warn "Key pair ${KEY_PAIR_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create key pair
    aws ec2 create-key-pair \
        --key-name "${KEY_PAIR_NAME}" \
        --query 'KeyMaterial' \
        --output text > "${KEY_PAIR_NAME}.pem"
    
    # Set proper permissions
    chmod 400 "${KEY_PAIR_NAME}.pem"
    
    log "Key pair created successfully: ${KEY_PAIR_NAME}"
    info "Private key saved to: ${KEY_PAIR_NAME}.pem"
}

# Function to create security group
create_security_group() {
    log "Creating security group..."
    
    # Get default VPC ID
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
        error "No default VPC found. Please create a VPC first."
        exit 1
    fi
    
    # Create security group
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "${SECURITY_GROUP_NAME}" \
        --description "Security group for hibernation demo" \
        --vpc-id "${VPC_ID}" \
        --query 'GroupId' \
        --output text)
    
    # Add SSH rule
    aws ec2 authorize-security-group-ingress \
        --group-id "${SECURITY_GROUP_ID}" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0
    
    # Store security group ID
    echo "export SECURITY_GROUP_ID=\"${SECURITY_GROUP_ID}\"" >> .env
    
    log "Security group created successfully: ${SECURITY_GROUP_ID}"
}

# Function to launch EC2 instance with hibernation
launch_instance() {
    log "Launching EC2 instance with hibernation enabled..."
    
    # Get the latest Amazon Linux 2 AMI ID that supports hibernation
    AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*" \
                  "Name=state,Values=available" \
                  "Name=architecture,Values=x86_64" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text)
    
    if [ -z "$AMI_ID" ] || [ "$AMI_ID" == "None" ]; then
        error "Could not find suitable Amazon Linux 2 AMI"
        exit 1
    fi
    
    info "Using AMI: ${AMI_ID}"
    
    # Launch instance with hibernation enabled
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "${AMI_ID}" \
        --instance-type m5.large \
        --key-name "${KEY_PAIR_NAME}" \
        --security-group-ids "${SECURITY_GROUP_ID}" \
        --hibernation-options Configured=true \
        --block-device-mappings '[{
            "DeviceName": "/dev/xvda",
            "Ebs": {
                "VolumeSize": 30,
                "VolumeType": "gp3",
                "Encrypted": true,
                "DeleteOnTermination": true
            }
        }]' \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}},{Key=Purpose,Value=HibernationDemo},{Key=Environment,Value=Demo}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "None" ]; then
        error "Failed to launch EC2 instance"
        exit 1
    fi
    
    # Store instance ID
    echo "export INSTANCE_ID=\"${INSTANCE_ID}\"" >> .env
    
    log "EC2 instance launched successfully: ${INSTANCE_ID}"
    
    # Wait for instance to be running
    info "Waiting for instance to be in running state..."
    aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
    
    # Verify hibernation is enabled
    HIBERNATION_ENABLED=$(aws ec2 describe-instances \
        --instance-ids "${INSTANCE_ID}" \
        --query 'Reservations[0].Instances[0].HibernationOptions.Configured' \
        --output text)
    
    if [ "$HIBERNATION_ENABLED" == "true" ]; then
        log "Hibernation enabled successfully: ${HIBERNATION_ENABLED}"
    else
        error "Hibernation is not enabled on the instance"
        exit 1
    fi
}

# Function to create SNS topic and CloudWatch alarm
create_monitoring() {
    log "Creating monitoring infrastructure..."
    
    # Create SNS topic
    TOPIC_ARN=$(aws sns create-topic \
        --name "${TOPIC_NAME}" \
        --query 'TopicArn' \
        --output text)
    
    if [ -z "$TOPIC_ARN" ]; then
        error "Failed to create SNS topic"
        exit 1
    fi
    
    # Store topic ARN
    echo "export TOPIC_ARN=\"${TOPIC_ARN}\"" >> .env
    
    info "SNS topic created: ${TOPIC_ARN}"
    
    # Create CloudWatch alarm for CPU utilization
    aws cloudwatch put-metric-alarm \
        --alarm-name "LowCPU-${INSTANCE_NAME}" \
        --alarm-description "Alarm when CPU utilization is low for hibernation demo" \
        --metric-name CPUUtilization \
        --namespace AWS/EC2 \
        --statistic Average \
        --period 300 \
        --threshold 10 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 6 \
        --alarm-actions "${TOPIC_ARN}" \
        --dimensions Name=InstanceId,Value="${INSTANCE_ID}" \
        --treat-missing-data notBreaching
    
    # Store alarm name
    echo "export ALARM_NAME=\"LowCPU-${INSTANCE_NAME}\"" >> .env
    
    log "CloudWatch alarm created successfully: LowCPU-${INSTANCE_NAME}"
}

# Function to display instance information
display_instance_info() {
    log "Retrieving instance information..."
    
    # Get instance details
    INSTANCE_INFO=$(aws ec2 describe-instances \
        --instance-ids "${INSTANCE_ID}" \
        --query 'Reservations[0].Instances[0].[InstanceId,InstanceType,State.Name,PublicIpAddress,PrivateIpAddress]' \
        --output table)
    
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids "${INSTANCE_ID}" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    echo
    echo "================================================================"
    echo "                   DEPLOYMENT COMPLETED                         "
    echo "================================================================"
    echo
    echo "Instance Information:"
    echo "${INSTANCE_INFO}"
    echo
    echo "SSH Connection:"
    echo "  ssh -i ${KEY_PAIR_NAME}.pem ec2-user@${PUBLIC_IP}"
    echo
    echo "To test hibernation:"
    echo "  1. SSH to the instance and create some test files"
    echo "  2. Run: aws ec2 stop-instances --instance-ids ${INSTANCE_ID} --hibernate"
    echo "  3. Wait for instance to be stopped"
    echo "  4. Run: aws ec2 start-instances --instance-ids ${INSTANCE_ID}"
    echo "  5. Verify your test files are still present"
    echo
    echo "CloudWatch Monitoring:"
    echo "  - SNS Topic: ${TOPIC_NAME}"
    echo "  - CloudWatch Alarm: LowCPU-${INSTANCE_NAME}"
    echo
    echo "To cleanup resources, run: ./destroy.sh"
    echo "================================================================"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check if instance is running
    INSTANCE_STATE=$(aws ec2 describe-instances \
        --instance-ids "${INSTANCE_ID}" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text)
    
    if [ "$INSTANCE_STATE" != "running" ]; then
        error "Instance is not in running state: ${INSTANCE_STATE}"
        exit 1
    fi
    
    # Check if hibernation is enabled
    HIBERNATION_ENABLED=$(aws ec2 describe-instances \
        --instance-ids "${INSTANCE_ID}" \
        --query 'Reservations[0].Instances[0].HibernationOptions.Configured' \
        --output text)
    
    if [ "$HIBERNATION_ENABLED" != "true" ]; then
        error "Hibernation is not enabled on the instance"
        exit 1
    fi
    
    # Check if SNS topic exists
    if ! aws sns get-topic-attributes --topic-arn "${TOPIC_ARN}" >/dev/null 2>&1; then
        error "SNS topic was not created successfully"
        exit 1
    fi
    
    # Check if CloudWatch alarm exists
    if ! aws cloudwatch describe-alarms --alarm-names "LowCPU-${INSTANCE_NAME}" >/dev/null 2>&1; then
        error "CloudWatch alarm was not created successfully"
        exit 1
    fi
    
    log "Deployment validation completed successfully"
}

# Main deployment function
main() {
    log "Starting EC2 Hibernation Cost Optimization deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Create key pair
    create_key_pair
    
    # Create security group
    create_security_group
    
    # Launch instance
    launch_instance
    
    # Create monitoring
    create_monitoring
    
    # Validate deployment
    validate_deployment
    
    # Display instance information
    display_instance_info
    
    log "Deployment completed successfully!"
}

# Trap to cleanup on script exit
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        error "Deployment failed. Check the logs above for details."
        error "You may need to manually cleanup resources."
        echo "To cleanup, run: ./destroy.sh"
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"