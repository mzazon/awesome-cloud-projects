#!/bin/bash

# Deploy script for Secure EC2 Management with Systems Manager
# This script automates the deployment of a secure EC2 instance managed through AWS Systems Manager

set -e

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling function
handle_error() {
    log_error "Deployment failed at line $1"
    log_error "Please check the error above and run the destroy.sh script to clean up any partially created resources"
    exit 1
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version=$(echo $aws_version | cut -d. -f1)
    if [ "$major_version" -lt 2 ]; then
        log_warning "AWS CLI v1 detected. Consider upgrading to v2 for better performance."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region not configured. Please set default region with 'aws configure'"
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate a random suffix for resource names
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    # Define resource names
    export EC2_INSTANCE_NAME="secure-server-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="SSMInstanceRole-${RANDOM_SUFFIX}"
    export IAM_PROFILE_NAME="SSMInstanceProfile-${RANDOM_SUFFIX}"
    export LOG_GROUP_NAME="/aws/ssm/sessions/${RANDOM_SUFFIX}"
    export SG_NAME="SSM-SecureServer-${RANDOM_SUFFIX}"
    
    # Save variables to file for cleanup script
    cat > .env_vars << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
EC2_INSTANCE_NAME=${EC2_INSTANCE_NAME}
IAM_ROLE_NAME=${IAM_ROLE_NAME}
IAM_PROFILE_NAME=${IAM_PROFILE_NAME}
LOG_GROUP_NAME=${LOG_GROUP_NAME}
SG_NAME=${SG_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables configured"
    log "Using region: ${AWS_REGION}"
    log "Random suffix: ${RANDOM_SUFFIX}"
}

# Function to select AMI
select_ami() {
    log "Selecting appropriate AMI..."
    
    # Default to Amazon Linux 2023 unless user specifies otherwise
    if [ -z "$OS_CHOICE" ]; then
        echo "Select operating system:"
        echo "1) Amazon Linux 2023 (recommended)"
        echo "2) Ubuntu 22.04 LTS"
        read -p "Enter choice (1 or 2, default 1): " OS_CHOICE
        OS_CHOICE=${OS_CHOICE:-1}
    fi
    
    if [ "$OS_CHOICE" = "1" ]; then
        # Amazon Linux 2023 AMI ID for x86_64
        export AMI_ID=$(aws ec2 describe-images \
            --owners amazon \
            --filters "Name=name,Values=al2023-ami-2023*x86_64" \
            "Name=state,Values=available" \
            --query "sort_by(Images, &CreationDate)[-1].ImageId" \
            --output text)
        export OS_TYPE="Amazon Linux 2023"
    else
        # Ubuntu 22.04 LTS AMI ID for x86_64
        export AMI_ID=$(aws ec2 describe-images \
            --owners 099720109477 \
            --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-*" \
            "Name=state,Values=available" \
            --query "sort_by(Images, &CreationDate)[-1].ImageId" \
            --output text)
        export OS_TYPE="Ubuntu 22.04"
    fi
    
    if [ "$AMI_ID" = "None" ] || [ -z "$AMI_ID" ]; then
        log_error "Could not find appropriate AMI for selected OS"
        exit 1
    fi
    
    # Add to env file
    echo "AMI_ID=${AMI_ID}" >> .env_vars
    echo "OS_TYPE=${OS_TYPE}" >> .env_vars
    
    log_success "Selected ${OS_TYPE} with AMI ID: ${AMI_ID}"
}

# Function to create IAM role
create_iam_role() {
    log "Creating IAM role for EC2 Systems Manager access..."
    
    # Create IAM role with EC2 trust relationship
    aws iam create-role \
        --role-name ${IAM_ROLE_NAME} \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {"Service": "ec2.amazonaws.com"},
                    "Action": "sts:AssumeRole"
                }
            ]
        }' \
        --tags "Key=Project,Value=SSM-SecureServer" "Key=Environment,Value=Demo"
    
    # Attach AmazonSSMManagedInstanceCore policy
    aws iam attach-role-policy \
        --role-name ${IAM_ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
    
    # Create instance profile
    aws iam create-instance-profile \
        --instance-profile-name ${IAM_PROFILE_NAME} \
        --tags "Key=Project,Value=SSM-SecureServer" "Key=Environment,Value=Demo"
    
    # Add role to instance profile
    aws iam add-role-to-instance-profile \
        --instance-profile-name ${IAM_PROFILE_NAME} \
        --role-name ${IAM_ROLE_NAME}
    
    # Wait for profile propagation
    log "Waiting for IAM instance profile to propagate..."
    sleep 15
    
    log_success "IAM role and instance profile created"
}

# Function to create security group
create_security_group() {
    log "Creating security group..."
    
    # Get default VPC ID
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --query "Vpcs[0].VpcId" \
        --output text)
    
    if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
        log_error "No default VPC found. Please create a VPC first."
        exit 1
    fi
    
    # Create security group
    SG_ID=$(aws ec2 create-security-group \
        --group-name "${SG_NAME}" \
        --description "Security group for SSM managed instance - no inbound access required" \
        --vpc-id ${VPC_ID} \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${SG_NAME}},{Key=Project,Value=SSM-SecureServer},{Key=Environment,Value=Demo}]" \
        --query "GroupId" \
        --output text)
    
    # Note: We explicitly do NOT add any inbound rules to demonstrate SSM security
    # Only outbound HTTPS is needed for Systems Manager communication
    
    # Add to env file
    echo "VPC_ID=${VPC_ID}" >> .env_vars
    echo "SG_ID=${SG_ID}" >> .env_vars
    
    log_success "Security group created: ${SG_ID}"
    log "Note: No inbound ports opened - access only through Systems Manager"
}

# Function to launch EC2 instance
launch_ec2_instance() {
    log "Launching EC2 instance..."
    
    # Get first available subnet in the VPC
    SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query "Subnets[0].SubnetId" \
        --output text)
    
    if [ "$SUBNET_ID" = "None" ] || [ -z "$SUBNET_ID" ]; then
        log_error "No subnet found in VPC ${VPC_ID}"
        exit 1
    fi
    
    # Launch instance
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id ${AMI_ID} \
        --instance-type t3.micro \
        --subnet-id ${SUBNET_ID} \
        --security-group-ids ${SG_ID} \
        --iam-instance-profile Name=${IAM_PROFILE_NAME} \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${EC2_INSTANCE_NAME}},{Key=Project,Value=SSM-SecureServer},{Key=Environment,Value=Demo}]" \
        --user-data "#!/bin/bash
# Ensure SSM agent is running (pre-installed on modern AMIs)
if command -v systemctl &> /dev/null; then
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
fi" \
        --query "Instances[0].InstanceId" \
        --output text)
    
    # Add to env file
    echo "SUBNET_ID=${SUBNET_ID}" >> .env_vars
    echo "INSTANCE_ID=${INSTANCE_ID}" >> .env_vars
    
    log "Instance ID: ${INSTANCE_ID}"
    log "Waiting for instance to be in 'running' state..."
    
    aws ec2 wait instance-running --instance-ids ${INSTANCE_ID}
    
    log_success "EC2 instance launched successfully"
}

# Function to verify Systems Manager connection
verify_ssm_connection() {
    log "Verifying Systems Manager connection..."
    
    local max_attempts=12
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Attempt ${attempt}/${max_attempts}: Checking if instance is registered with Systems Manager..."
        
        SSM_STATUS=$(aws ssm describe-instance-information \
            --filters "Key=InstanceIds,Values=${INSTANCE_ID}" \
            --query "InstanceInformationList[0].PingStatus" \
            --output text 2>/dev/null || echo "None")
        
        if [ "$SSM_STATUS" = "Online" ]; then
            log_success "Instance successfully registered with Systems Manager"
            return 0
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            log_error "Instance failed to register with Systems Manager after ${max_attempts} attempts"
            log "Troubleshooting tips:"
            log "1. Ensure the instance has internet connectivity"
            log "2. Verify IAM role includes AmazonSSMManagedInstanceCore policy"
            log "3. Check that SSM agent is running on the instance"
            log "4. Review CloudWatch Logs for SSM agent errors"
            return 1
        fi
        
        log "Status: ${SSM_STATUS}. Waiting 30 seconds before retry..."
        sleep 30
        ((attempt++))
    done
}

# Function to test Run Command
test_run_command() {
    log "Testing Systems Manager Run Command..."
    
    # Execute a simple command to verify functionality
    CMD_ID=$(aws ssm send-command \
        --document-name "AWS-RunShellScript" \
        --targets "[{\"Key\":\"InstanceIds\",\"Values\":[\"${INSTANCE_ID}\"]}]" \
        --parameters "{\"commands\":[\"echo 'Systems Manager Run Command test successful'\", \"hostname\", \"whoami\", \"date\"]}" \
        --timeout-seconds 300 \
        --comment "Deployment verification test" \
        --query "Command.CommandId" \
        --output text)
    
    log "Command ID: ${CMD_ID}"
    log "Waiting for command execution..."
    sleep 10
    
    # Get command result
    aws ssm get-command-invocation \
        --command-id ${CMD_ID} \
        --instance-id ${INSTANCE_ID} \
        --query "StandardOutputContent" \
        --output text
    
    log_success "Run Command test completed successfully"
}

# Function to configure CloudWatch logging
configure_logging() {
    log "Configuring CloudWatch logging for Sessions..."
    
    # Create CloudWatch Log Group
    aws logs create-log-group \
        --log-group-name "${LOG_GROUP_NAME}" \
        --tags "Project=SSM-SecureServer,Environment=Demo"
    
    # Set retention policy (optional)
    aws logs put-retention-policy \
        --log-group-name "${LOG_GROUP_NAME}" \
        --retention-in-days 30
    
    log_success "CloudWatch Log Group created: ${LOG_GROUP_NAME}"
    log "Session logs will be automatically captured for audit purposes"
}

# Function to deploy sample web application
deploy_sample_app() {
    if [ "${DEPLOY_SAMPLE_APP:-yes}" = "yes" ]; then
        log "Deploying sample web application..."
        
        DEPLOY_CMD_ID=$(aws ssm send-command \
            --document-name "AWS-RunShellScript" \
            --targets "[{\"Key\":\"InstanceIds\",\"Values\":[\"${INSTANCE_ID}\"]}]" \
            --parameters '{
                "commands": [
                    "#!/bin/bash",
                    "set -e",
                    "echo \"Installing web server...\"",
                    "if command -v apt-get &> /dev/null; then",
                    "    # Ubuntu",
                    "    apt-get update -y",
                    "    apt-get install -y nginx",
                    "    systemctl enable nginx",
                    "    systemctl start nginx",
                    "    echo \"<html><body><h1>Hello from Systems Manager</h1><p>This server is managed securely without SSH!</p><p>Deployed at: $(date)</p></body></html>\" > /var/www/html/index.html",
                    "else",
                    "    # Amazon Linux",
                    "    dnf update -y",
                    "    dnf install -y nginx",
                    "    systemctl enable nginx",
                    "    systemctl start nginx",
                    "    echo \"<html><body><h1>Hello from Systems Manager</h1><p>This server is managed securely without SSH!</p><p>Deployed at: $(date)</p></body></html>\" > /usr/share/nginx/html/index.html",
                    "fi",
                    "echo \"Web server deployed successfully\"",
                    "systemctl status nginx --no-pager"
                ]
            }' \
            --timeout-seconds 600 \
            --comment "Sample web application deployment" \
            --query "Command.CommandId" \
            --output text)
        
        log "Waiting for web application deployment..."
        sleep 30
        
        # Get deployment result
        DEPLOY_OUTPUT=$(aws ssm get-command-invocation \
            --command-id ${DEPLOY_CMD_ID} \
            --instance-id ${INSTANCE_ID} \
            --query "StandardOutputContent" \
            --output text)
        
        if echo "$DEPLOY_OUTPUT" | grep -q "successfully"; then
            log_success "Sample web application deployed successfully"
        else
            log_warning "Web application deployment may have encountered issues"
            echo "Deployment output:"
            echo "$DEPLOY_OUTPUT"
        fi
    fi
}

# Function to display connection information
display_connection_info() {
    log "Deployment completed successfully!"
    echo
    echo "=== Connection Information ==="
    echo "Instance ID: ${INSTANCE_ID}"
    echo "Instance Name: ${EC2_INSTANCE_NAME}"
    echo "AMI: ${OS_TYPE} (${AMI_ID})"
    echo "Region: ${AWS_REGION}"
    echo
    echo "=== How to Connect ==="
    echo "1. Start a secure shell session (requires Session Manager plugin):"
    echo "   aws ssm start-session --target ${INSTANCE_ID}"
    echo
    echo "2. Or connect via AWS Console:"
    echo "   - Go to EC2 Console"
    echo "   - Select instance '${EC2_INSTANCE_NAME}'"
    echo "   - Click 'Connect' → 'Session Manager' → 'Connect'"
    echo
    echo "3. Test web application (if deployed):"
    echo "   - Connect via Session Manager"
    echo "   - Run: curl http://localhost"
    echo
    echo "=== Monitoring and Logs ==="
    echo "CloudWatch Log Group: ${LOG_GROUP_NAME}"
    echo "Console URL: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#logsV2:log-groups"
    echo
    echo "=== Next Steps ==="
    echo "- Explore Session Manager capabilities"
    echo "- Test Run Command for automation"
    echo "- Review CloudWatch Logs for session activity"
    echo "- When finished, run './destroy.sh' to clean up resources"
    echo
    log_success "Deployment completed! Environment variables saved in .env_vars"
}

# Main deployment function
main() {
    log "Starting deployment of AWS Systems Manager secure EC2 instance"
    log "This deployment demonstrates secure server management without SSH"
    echo
    
    # Check if script is being run from correct directory
    if [ ! -f "deploy.sh" ]; then
        log_error "Please run this script from the scripts directory"
        exit 1
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    select_ami
    create_iam_role
    create_security_group
    launch_ec2_instance
    verify_ssm_connection
    test_run_command
    configure_logging
    deploy_sample_app
    display_connection_info
}

# Run main function
main "$@"