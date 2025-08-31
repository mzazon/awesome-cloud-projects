#!/bin/bash

# EC2 Launch Templates with Auto Scaling - Deployment Script
# This script creates EC2 launch templates and auto scaling groups following AWS best practices

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI credentials
check_aws_credentials() {
    log_info "Checking AWS CLI credentials..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI credentials not configured or invalid"
        log_error "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
    log_success "AWS credentials verified"
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $aws_version"
    
    # Check AWS credentials
    check_aws_credentials
    
    # Check if jq is available (optional but helpful)
    if command_exists jq; then
        log_info "jq is available for JSON parsing"
    else
        log_warning "jq is not available. Install jq for better JSON parsing"
    fi
    
    log_success "All prerequisites validated"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "${AWS_REGION}" ]]; then
        log_warning "AWS_REGION not set, defaulting to us-east-1"
        export AWS_REGION="us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set resource names with unique suffix
    export LAUNCH_TEMPLATE_NAME="demo-launch-template-${random_suffix}"
    export ASG_NAME="demo-auto-scaling-group-${random_suffix}"
    export SECURITY_GROUP_NAME="demo-sg-${random_suffix}"
    
    log_info "Environment variables set:"
    log_info "  AWS_REGION: ${AWS_REGION}"
    log_info "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    log_info "  LAUNCH_TEMPLATE_NAME: ${LAUNCH_TEMPLATE_NAME}"
    log_info "  ASG_NAME: ${ASG_NAME}"
    log_info "  SECURITY_GROUP_NAME: ${SECURITY_GROUP_NAME}"
}

# Function to get latest Amazon Linux 2 AMI
get_latest_ami() {
    log_info "Getting latest Amazon Linux 2 AMI..."
    
    export AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    if [[ -z "${AMI_ID}" || "${AMI_ID}" == "None" ]]; then
        log_error "Failed to retrieve latest Amazon Linux 2 AMI"
        exit 1
    fi
    
    log_success "Latest AMI ID: ${AMI_ID}"
}

# Function to get VPC and subnet information
get_vpc_info() {
    log_info "Getting VPC and subnet information..."
    
    # Get default VPC
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [[ -z "${VPC_ID}" || "${VPC_ID}" == "None" ]]; then
        log_error "No default VPC found. Please create a VPC first"
        exit 1
    fi
    
    # Get subnets in the VPC
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[].SubnetId' --output text)
    
    if [[ -z "${SUBNET_IDS}" ]]; then
        log_error "No subnets found in VPC ${VPC_ID}"
        exit 1
    fi
    
    log_success "VPC ID: ${VPC_ID}"
    log_success "Subnet IDs: ${SUBNET_IDS}"
}

# Function to create security group
create_security_group() {
    log_info "Creating security group..."
    
    # Check if security group already exists
    if aws ec2 describe-security-groups --group-names "${SECURITY_GROUP_NAME}" >/dev/null 2>&1; then
        log_warning "Security group ${SECURITY_GROUP_NAME} already exists"
        export SG_ID=$(aws ec2 describe-security-groups \
            --group-names "${SECURITY_GROUP_NAME}" \
            --query 'SecurityGroups[0].GroupId' --output text)
    else
        # Create security group
        aws ec2 create-security-group \
            --group-name "${SECURITY_GROUP_NAME}" \
            --description "Security group for Auto Scaling demo" \
            --vpc-id "${VPC_ID}" >/dev/null
        
        # Get security group ID
        export SG_ID=$(aws ec2 describe-security-groups \
            --group-names "${SECURITY_GROUP_NAME}" \
            --query 'SecurityGroups[0].GroupId' --output text)
        
        # Add inbound rules for HTTP and SSH
        aws ec2 authorize-security-group-ingress \
            --group-id "${SG_ID}" \
            --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null || true
        
        aws ec2 authorize-security-group-ingress \
            --group-id "${SG_ID}" \
            --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null || true
        
        log_success "Security group created: ${SG_ID}"
    fi
}

# Function to create launch template
create_launch_template() {
    log_info "Creating launch template..."
    
    # Check if launch template already exists
    if aws ec2 describe-launch-templates --launch-template-names "${LAUNCH_TEMPLATE_NAME}" >/dev/null 2>&1; then
        log_warning "Launch template ${LAUNCH_TEMPLATE_NAME} already exists"
        export LT_ID=$(aws ec2 describe-launch-templates \
            --launch-template-names "${LAUNCH_TEMPLATE_NAME}" \
            --query 'LaunchTemplates[0].LaunchTemplateId' \
            --output text)
    else
        # Create UserData script
        local user_data
        user_data=$(cat <<'EOF'
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>Hello from $(hostname -f)</h1>" > /var/www/html/index.html
echo "<p>Instance launched at $(date)</p>" >> /var/www/html/index.html
EOF
)
        
        # Encode UserData
        local encoded_user_data
        encoded_user_data=$(echo "${user_data}" | base64 -w 0)
        
        # Create launch template with proper JSON formatting
        aws ec2 create-launch-template \
            --launch-template-name "${LAUNCH_TEMPLATE_NAME}" \
            --launch-template-data "{
                \"ImageId\": \"${AMI_ID}\",
                \"InstanceType\": \"t2.micro\",
                \"SecurityGroupIds\": [\"${SG_ID}\"],
                \"UserData\": \"${encoded_user_data}\",
                \"TagSpecifications\": [{
                    \"ResourceType\": \"instance\",
                    \"Tags\": [{
                        \"Key\": \"Name\",
                        \"Value\": \"AutoScaling-Instance\"
                    }, {
                        \"Key\": \"Environment\",
                        \"Value\": \"Demo\"
                    }, {
                        \"Key\": \"CreatedBy\",
                        \"Value\": \"ec2-launch-templates-auto-scaling-recipe\"
                    }]
                }]
            }" >/dev/null
        
        # Get launch template ID
        export LT_ID=$(aws ec2 describe-launch-templates \
            --launch-template-names "${LAUNCH_TEMPLATE_NAME}" \
            --query 'LaunchTemplates[0].LaunchTemplateId' \
            --output text)
        
        log_success "Launch template created: ${LT_ID}"
    fi
}

# Function to create Auto Scaling group
create_auto_scaling_group() {
    log_info "Creating Auto Scaling group..."
    
    # Check if Auto Scaling group already exists
    if aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${ASG_NAME}" >/dev/null 2>&1; then
        log_warning "Auto Scaling group ${ASG_NAME} already exists"
    else
        # Convert space-separated subnet IDs to comma-separated
        local subnet_list
        subnet_list="${SUBNET_IDS// /,}"
        
        # Create Auto Scaling group
        aws autoscaling create-auto-scaling-group \
            --auto-scaling-group-name "${ASG_NAME}" \
            --launch-template "LaunchTemplateId=${LT_ID},Version=\$Latest" \
            --min-size 1 \
            --max-size 4 \
            --desired-capacity 2 \
            --vpc-zone-identifier "${subnet_list}" \
            --health-check-type EC2 \
            --health-check-grace-period 300 \
            --tags "Key=Name,Value=AutoScaling-ASG,PropagateAtLaunch=false" \
                   "Key=Environment,Value=Demo,PropagateAtLaunch=true" \
                   "Key=CreatedBy,Value=ec2-launch-templates-auto-scaling-recipe,PropagateAtLaunch=true"
        
        log_info "Waiting for Auto Scaling group instances to be in service..."
        aws autoscaling wait instances-in-service \
            --auto-scaling-group-names "${ASG_NAME}" || {
            log_warning "Timeout waiting for instances to be in service. Continuing..."
        }
        
        log_success "Auto Scaling group created: ${ASG_NAME}"
    fi
}

# Function to create scaling policy
create_scaling_policy() {
    log_info "Creating target tracking scaling policy..."
    
    # Create target tracking scaling policy for CPU utilization
    aws autoscaling put-scaling-policy \
        --auto-scaling-group-name "${ASG_NAME}" \
        --policy-name "cpu-target-tracking-policy" \
        --policy-type "TargetTrackingScaling" \
        --target-tracking-configuration '{
            "TargetValue": 70.0,
            "PredefinedMetricSpecification": {
                "PredefinedMetricType": "ASGAverageCPUUtilization"
            },
            "ScaleOutCooldown": 300,
            "ScaleInCooldown": 300
        }' >/dev/null
    
    log_success "Target tracking scaling policy created"
}

# Function to enable metrics collection
enable_metrics() {
    log_info "Enabling Auto Scaling group metrics..."
    
    aws autoscaling enable-metrics-collection \
        --auto-scaling-group-name "${ASG_NAME}" \
        --metrics "GroupMinSize" "GroupMaxSize" "GroupDesiredCapacity" \
                 "GroupInServiceInstances" "GroupTotalInstances" >/dev/null
    
    log_success "CloudWatch metrics enabled for Auto Scaling group"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "===================="
    echo "AWS Region: ${AWS_REGION}"
    echo "VPC ID: ${VPC_ID}"
    echo "Security Group ID: ${SG_ID}"
    echo "Launch Template ID: ${LT_ID}"
    echo "Auto Scaling Group: ${ASG_NAME}"
    echo "AMI ID: ${AMI_ID}"
    echo ""
    
    # Get instance information
    local instance_ids
    instance_ids=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "${ASG_NAME}" \
        --query 'AutoScalingGroups[0].Instances[].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${instance_ids}" ]]; then
        log_info "Running instances:"
        aws ec2 describe-instances \
            --instance-ids ${instance_ids} \
            --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]' \
            --output table 2>/dev/null || echo "Unable to fetch instance details"
    fi
    
    echo ""
    log_success "Deployment completed successfully!"
    log_info "You can now test the web servers by accessing the public IP addresses above"
    log_info "To clean up resources, run: ./destroy.sh"
}

# Function to save state
save_state() {
    local state_file="/tmp/ec2-asg-deployment-state.env"
    cat > "${state_file}" <<EOF
# EC2 Launch Templates Auto Scaling Deployment State
# Generated on $(date)
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export LAUNCH_TEMPLATE_NAME="${LAUNCH_TEMPLATE_NAME}"
export ASG_NAME="${ASG_NAME}"
export SECURITY_GROUP_NAME="${SECURITY_GROUP_NAME}"
export AMI_ID="${AMI_ID}"
export VPC_ID="${VPC_ID}"
export SG_ID="${SG_ID}"
export LT_ID="${LT_ID}"
EOF
    log_info "Deployment state saved to ${state_file}"
}

# Main execution function
main() {
    log_info "Starting EC2 Launch Templates with Auto Scaling deployment..."
    
    # Validate prerequisites
    validate_prerequisites
    
    # Setup environment
    setup_environment
    
    # Get infrastructure information
    get_latest_ami
    get_vpc_info
    
    # Create resources
    create_security_group
    create_launch_template
    create_auto_scaling_group
    create_scaling_policy
    enable_metrics
    
    # Save state and display summary
    save_state
    display_summary
    
    log_success "Deployment script completed successfully!"
}

# Trap errors and cleanup
trap 'log_error "An error occurred. Check the logs above for details."; exit 1' ERR

# Run main function
main "$@"