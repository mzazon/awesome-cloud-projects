#!/bin/bash

# Deploy script for AWS Session Manager Recipe
# This script deploys secure remote access infrastructure using AWS Systems Manager Session Manager

set -e  # Exit on any error
set -u  # Exit on undefined variable

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

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version (v2.0 or later required)
    AWS_CLI_VERSION=$(aws --version | cut -d/ -f2 | cut -d' ' -f1)
    REQUIRED_VERSION="2.0.0"
    if ! printf '%s\n%s\n' "$REQUIRED_VERSION" "$AWS_CLI_VERSION" | sort -V -C; then
        error "AWS CLI version 2.0 or later is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or you don't have valid credentials."
        exit 1
    fi
    
    # Check required permissions by attempting to list IAM roles
    if ! aws iam list-roles --max-items 1 &> /dev/null; then
        error "Insufficient permissions to create IAM resources."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No default region configured, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    # Set resource names with unique suffix
    export INSTANCE_ROLE_NAME="SessionManagerInstanceRole-${RANDOM_SUFFIX}"
    export INSTANCE_PROFILE_NAME="SessionManagerInstanceProfile-${RANDOM_SUFFIX}"
    export USER_POLICY_NAME="SessionManagerUserPolicy-${RANDOM_SUFFIX}"
    export LOG_GROUP_NAME="/aws/sessionmanager/sessions-${RANDOM_SUFFIX}"
    export LOG_BUCKET_NAME="sessionmanager-logs-${RANDOM_SUFFIX}-$(echo $AWS_ACCOUNT_ID | tail -c 5)"
    
    # Save environment variables for cleanup script
    cat > .env << EOF
INSTANCE_ROLE_NAME=${INSTANCE_ROLE_NAME}
INSTANCE_PROFILE_NAME=${INSTANCE_PROFILE_NAME}
USER_POLICY_NAME=${USER_POLICY_NAME}
LOG_GROUP_NAME=${LOG_GROUP_NAME}
LOG_BUCKET_NAME=${LOG_BUCKET_NAME}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log "Environment configured:"
    log "  AWS Region: ${AWS_REGION}"
    log "  AWS Account: ${AWS_ACCOUNT_ID}"
    log "  Resource suffix: ${RANDOM_SUFFIX}"
    
    success "Environment setup complete"
}

# Create IAM role for EC2 instances
create_iam_role() {
    log "Creating IAM role for EC2 instances..."
    
    # Create trust policy file
    cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create IAM role
    if aws iam create-role \
        --role-name ${INSTANCE_ROLE_NAME} \
        --assume-role-policy-document file://trust-policy.json \
        --description "Role for Session Manager access to EC2 instances" > /dev/null; then
        success "IAM role created: ${INSTANCE_ROLE_NAME}"
    else
        error "Failed to create IAM role"
        exit 1
    fi
    
    # Attach AWS managed policy for Session Manager
    if aws iam attach-role-policy \
        --role-name ${INSTANCE_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore; then
        success "Attached AmazonSSMManagedInstanceCore policy to role"
    else
        error "Failed to attach policy to role"
        exit 1
    fi
    
    # Clean up temporary file
    rm -f trust-policy.json
}

# Create instance profile and attach role
create_instance_profile() {
    log "Creating instance profile..."
    
    # Create instance profile
    if aws iam create-instance-profile \
        --instance-profile-name ${INSTANCE_PROFILE_NAME} > /dev/null; then
        success "Instance profile created: ${INSTANCE_PROFILE_NAME}"
    else
        error "Failed to create instance profile"
        exit 1
    fi
    
    # Add role to instance profile
    if aws iam add-role-to-instance-profile \
        --instance-profile-name ${INSTANCE_PROFILE_NAME} \
        --role-name ${INSTANCE_ROLE_NAME}; then
        success "Role added to instance profile"
    else
        error "Failed to add role to instance profile"
        exit 1
    fi
    
    # Wait for instance profile to be ready
    log "Waiting for instance profile to be ready..."
    if aws iam wait instance-profile-exists \
        --instance-profile-name ${INSTANCE_PROFILE_NAME}; then
        success "Instance profile is ready"
    else
        error "Instance profile creation timed out"
        exit 1
    fi
}

# Create S3 bucket for session logs
create_s3_bucket() {
    log "Creating S3 bucket for session logs..."
    
    # Create S3 bucket with region-specific configuration
    if [ "$AWS_REGION" = "us-east-1" ]; then
        CREATE_BUCKET_CONFIG=""
    else
        CREATE_BUCKET_CONFIG="--create-bucket-configuration LocationConstraint=${AWS_REGION}"
    fi
    
    if aws s3api create-bucket \
        --bucket ${LOG_BUCKET_NAME} \
        --region ${AWS_REGION} \
        ${CREATE_BUCKET_CONFIG} > /dev/null; then
        success "S3 bucket created: ${LOG_BUCKET_NAME}"
    else
        error "Failed to create S3 bucket"
        exit 1
    fi
    
    # Enable versioning
    if aws s3api put-bucket-versioning \
        --bucket ${LOG_BUCKET_NAME} \
        --versioning-configuration Status=Enabled; then
        success "Bucket versioning enabled"
    else
        warning "Failed to enable bucket versioning"
    fi
    
    # Enable server-side encryption
    if aws s3api put-bucket-encryption \
        --bucket ${LOG_BUCKET_NAME} \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'; then
        success "Bucket encryption enabled"
    else
        warning "Failed to enable bucket encryption"
    fi
    
    # Block public access
    if aws s3api put-public-access-block \
        --bucket ${LOG_BUCKET_NAME} \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"; then
        success "Public access blocked on bucket"
    else
        warning "Failed to block public access on bucket"
    fi
}

# Launch EC2 instance with Session Manager role
launch_ec2_instance() {
    log "Launching EC2 instance with Session Manager role..."
    
    # Get latest Amazon Linux 2 AMI ID
    AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text)
    
    if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
        error "Failed to find suitable Amazon Linux 2 AMI"
        exit 1
    fi
    
    log "Using AMI: ${AMI_ID}"
    
    # Create user data script
    cat > user-data.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y amazon-ssm-agent
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent

# Verify SSM agent is running
systemctl status amazon-ssm-agent
EOF
    
    # Launch EC2 instance
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id ${AMI_ID} \
        --instance-type t3.micro \
        --iam-instance-profile Name=${INSTANCE_PROFILE_NAME} \
        --tag-specifications \
        "ResourceType=instance,Tags=[{Key=Name,Value=SessionManagerDemo-${RANDOM_SUFFIX}},{Key=Purpose,Value=SessionManagerTesting},{Key=Environment,Value=Demo}]" \
        --user-data file://user-data.sh \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
        error "Failed to launch EC2 instance"
        exit 1
    fi
    
    # Save instance ID for cleanup
    echo "INSTANCE_ID=${INSTANCE_ID}" >> .env
    
    log "EC2 instance launched: ${INSTANCE_ID}"
    
    # Wait for instance to be running
    log "Waiting for instance to be in running state..."
    if aws ec2 wait instance-running --instance-ids ${INSTANCE_ID}; then
        success "EC2 instance is running"
    else
        error "Instance failed to reach running state"
        exit 1
    fi
    
    # Clean up temporary file
    rm -f user-data.sh
}

# Configure Session Manager logging
configure_logging() {
    log "Configuring Session Manager logging..."
    
    # Create CloudWatch log group
    if aws logs create-log-group \
        --log-group-name ${LOG_GROUP_NAME} \
        --retention-in-days 30 > /dev/null 2>&1; then
        success "CloudWatch log group created: ${LOG_GROUP_NAME}"
    else
        warning "CloudWatch log group may already exist or failed to create"
    fi
    
    # Create session manager logging configuration
    cat > logging-config.json << EOF
{
  "schemaVersion": "1.0",
  "description": "Session Manager logging configuration for secure remote access",
  "sessionType": "Standard_Stream",
  "inputs": {
    "s3BucketName": "${LOG_BUCKET_NAME}",
    "s3KeyPrefix": "session-logs/",
    "s3EncryptionEnabled": true,
    "cloudWatchLogGroupName": "${LOG_GROUP_NAME}",
    "cloudWatchEncryptionEnabled": true,
    "cloudWatchStreamingEnabled": true
  }
}
EOF
    
    # Apply logging configuration
    if aws ssm put-preference \
        --name "SessionManagerLoggingPreferences" \
        --value file://logging-config.json > /dev/null; then
        success "Session Manager logging configured"
    else
        error "Failed to configure Session Manager logging"
        exit 1
    fi
    
    # Clean up temporary file
    rm -f logging-config.json
}

# Create user policy for Session Manager access
create_user_policy() {
    log "Creating user policy for Session Manager access..."
    
    # Create user policy document
    cat > user-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession"
      ],
      "Resource": [
        "arn:aws:ec2:${AWS_REGION}:${AWS_ACCOUNT_ID}:instance/*"
      ],
      "Condition": {
        "StringEquals": {
          "ssm:resourceTag/Purpose": "SessionManagerTesting"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:DescribeInstanceInformation",
        "ssm:DescribeInstanceAssociationsStatus",
        "ssm:GetConnectionStatus"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:DescribeDocumentParameters",
        "ssm:DescribeDocument",
        "ssm:GetDocument"
      ],
      "Resource": "arn:aws:ssm:*:*:document/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:TerminateSession",
        "ssm:ResumeSession"
      ],
      "Resource": "arn:aws:ssm:*:*:session/\${aws:username}-*"
    }
  ]
}
EOF
    
    # Create the policy
    POLICY_ARN=$(aws iam create-policy \
        --policy-name ${USER_POLICY_NAME} \
        --policy-document file://user-policy.json \
        --description "Policy for Session Manager user access" \
        --query 'Policy.Arn' \
        --output text)
    
    if [ -z "$POLICY_ARN" ] || [ "$POLICY_ARN" = "None" ]; then
        error "Failed to create user policy"
        exit 1
    fi
    
    # Save policy ARN for cleanup
    echo "POLICY_ARN=${POLICY_ARN}" >> .env
    
    success "User policy created: ${USER_POLICY_NAME}"
    success "Policy ARN: ${POLICY_ARN}"
    
    # Clean up temporary file
    rm -f user-policy.json
}

# Wait for instance to register with Systems Manager
wait_for_ssm_registration() {
    log "Waiting for instance to register with Systems Manager..."
    
    # Read instance ID from environment file
    source .env
    
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        STATUS=$(aws ssm describe-instance-information \
            --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
            --query 'InstanceInformationList[0].PingStatus' \
            --output text 2>/dev/null || echo "NotFound")
        
        if [ "$STATUS" = "Online" ]; then
            success "Instance registered with Systems Manager"
            
            # Display instance information
            aws ssm describe-instance-information \
                --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
                --query 'InstanceInformationList[0].[InstanceId,PingStatus,AgentVersion,LastPingDateTime]' \
                --output table
            return 0
        fi
        
        log "Instance status: ${STATUS}. Waiting... (attempt ${attempt}/${max_attempts})"
        sleep 10
        ((attempt++))
    done
    
    error "Instance failed to register with Systems Manager within timeout period"
    return 1
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    source .env
    
    # Check IAM role
    if aws iam get-role --role-name ${INSTANCE_ROLE_NAME} > /dev/null 2>&1; then
        success "IAM role validation passed"
    else
        error "IAM role validation failed"
        return 1
    fi
    
    # Check instance profile
    if aws iam get-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} > /dev/null 2>&1; then
        success "Instance profile validation passed"
    else
        error "Instance profile validation failed"
        return 1
    fi
    
    # Check S3 bucket
    if aws s3api head-bucket --bucket ${LOG_BUCKET_NAME} > /dev/null 2>&1; then
        success "S3 bucket validation passed"
    else
        error "S3 bucket validation failed"
        return 1
    fi
    
    # Check EC2 instance
    INSTANCE_STATE=$(aws ec2 describe-instances \
        --instance-ids ${INSTANCE_ID} \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text)
    
    if [ "$INSTANCE_STATE" = "running" ]; then
        success "EC2 instance validation passed"
    else
        error "EC2 instance validation failed - state: ${INSTANCE_STATE}"
        return 1
    fi
    
    # Check CloudWatch log group
    if aws logs describe-log-groups --log-group-name-prefix ${LOG_GROUP_NAME} > /dev/null 2>&1; then
        success "CloudWatch log group validation passed"
    else
        error "CloudWatch log group validation failed"
        return 1
    fi
    
    success "All validation checks passed"
}

# Display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    
    source .env
    
    echo "✅ IAM Role: ${INSTANCE_ROLE_NAME}"
    echo "✅ Instance Profile: ${INSTANCE_PROFILE_NAME}"
    echo "✅ User Policy: ${USER_POLICY_NAME}"
    echo "✅ S3 Log Bucket: ${LOG_BUCKET_NAME}"
    echo "✅ CloudWatch Log Group: ${LOG_GROUP_NAME}"
    echo "✅ EC2 Instance: ${INSTANCE_ID}"
    echo "✅ Session Manager logging configured"
    echo ""
    echo "Next Steps:"
    echo "1. Attach the user policy (${USER_POLICY_NAME}) to IAM users who need Session Manager access"
    echo "2. Test Session Manager access using: aws ssm start-session --target ${INSTANCE_ID}"
    echo "3. Monitor session logs in CloudWatch and S3"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo "Environment file saved as .env for cleanup reference"
    
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting AWS Session Manager deployment..."
    
    check_prerequisites
    setup_environment
    create_iam_role
    create_instance_profile
    create_s3_bucket
    launch_ec2_instance
    configure_logging
    create_user_policy
    
    if wait_for_ssm_registration; then
        if validate_deployment; then
            display_summary
            exit 0
        else
            error "Deployment validation failed"
            exit 1
        fi
    else
        error "SSM registration failed"
        exit 1
    fi
}

# Trap to handle script interruption
trap 'error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"