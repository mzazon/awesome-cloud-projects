#!/bin/bash

# EC2 Fleet Management Deployment Script
# This script deploys EC2 Fleet with Spot Fleet and On-Demand instances
# for cost optimization and high availability

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly TEMP_DIR="${SCRIPT_DIR}/temp"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code: ${exit_code}"
    log_error "Check ${LOG_FILE} for details"
    
    # Cleanup temporary files
    if [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
    
    exit "${exit_code}"
}

trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if region is set
    if [[ -z "${AWS_DEFAULT_REGION:-}" ]]; then
        if ! aws configure get region &> /dev/null; then
            log_error "AWS region is not configured. Please set AWS_DEFAULT_REGION or run 'aws configure'."
            exit 1
        fi
    fi
    
    log_success "Prerequisites check passed"
}

# Initialize environment
initialize_environment() {
    log_info "Initializing environment..."
    
    # Create temporary directory
    mkdir -p "${TEMP_DIR}"
    
    # Set environment variables
    export AWS_REGION="${AWS_DEFAULT_REGION:-$(aws configure get region)}"
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export FLEET_NAME="ec2-fleet-demo-${RANDOM_SUFFIX}"
    export LAUNCH_TEMPLATE_NAME="fleet-template-${RANDOM_SUFFIX}"
    export KEY_PAIR_NAME="fleet-keypair-${RANDOM_SUFFIX}"
    export SECURITY_GROUP_NAME="fleet-sg-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="aws-ec2-spot-fleet-role-${RANDOM_SUFFIX}"
    export DASHBOARD_NAME="EC2-Fleet-Monitoring-${RANDOM_SUFFIX}"
    
    # Get default VPC and subnets
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [[ "${VPC_ID}" == "None" ]]; then
        log_error "No default VPC found. Please create a VPC first."
        exit 1
    fi
    
    export SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[*].SubnetId' --output text)
    
    if [[ -z "${SUBNET_IDS}" ]]; then
        log_error "No subnets found in default VPC."
        exit 1
    fi
    
    # Save deployment state
    cat > "${TEMP_DIR}/deployment-state.json" << EOF
{
    "fleet_name": "${FLEET_NAME}",
    "launch_template_name": "${LAUNCH_TEMPLATE_NAME}",
    "key_pair_name": "${KEY_PAIR_NAME}",
    "security_group_name": "${SECURITY_GROUP_NAME}",
    "iam_role_name": "${IAM_ROLE_NAME}",
    "dashboard_name": "${DASHBOARD_NAME}",
    "vpc_id": "${VPC_ID}",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "random_suffix": "${RANDOM_SUFFIX}"
}
EOF
    
    log_success "Environment initialized"
    log_info "Fleet Name: ${FLEET_NAME}"
    log_info "VPC ID: ${VPC_ID}"
    log_info "Region: ${AWS_REGION}"
}

# Create security group
create_security_group() {
    log_info "Creating security group..."
    
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name "${SECURITY_GROUP_NAME}" \
        --description "Security group for EC2 Fleet demo" \
        --vpc-id "${VPC_ID}" \
        --query 'GroupId' --output text)
    
    # Allow SSH access (restrict as needed)
    aws ec2 authorize-security-group-ingress \
        --group-id "${SECURITY_GROUP_ID}" \
        --protocol tcp --port 22 \
        --cidr 0.0.0.0/0 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=SSH-Access}]" \
        2>/dev/null || true
    
    # Allow HTTP traffic
    aws ec2 authorize-security-group-ingress \
        --group-id "${SECURITY_GROUP_ID}" \
        --protocol tcp --port 80 \
        --cidr 0.0.0.0/0 \
        --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=HTTP-Access}]" \
        2>/dev/null || true
    
    export SECURITY_GROUP_ID
    jq --arg sg_id "${SECURITY_GROUP_ID}" '.security_group_id = $sg_id' \
        "${TEMP_DIR}/deployment-state.json" > "${TEMP_DIR}/deployment-state.tmp" && \
        mv "${TEMP_DIR}/deployment-state.tmp" "${TEMP_DIR}/deployment-state.json"
    
    log_success "Created security group: ${SECURITY_GROUP_ID}"
}

# Create key pair
create_key_pair() {
    log_info "Creating key pair..."
    
    aws ec2 create-key-pair \
        --key-name "${KEY_PAIR_NAME}" \
        --query 'KeyMaterial' --output text > "${TEMP_DIR}/${KEY_PAIR_NAME}.pem"
    
    chmod 400 "${TEMP_DIR}/${KEY_PAIR_NAME}.pem"
    
    log_success "Created key pair: ${KEY_PAIR_NAME}"
    log_info "Private key saved to: ${TEMP_DIR}/${KEY_PAIR_NAME}.pem"
}

# Get latest AMI
get_latest_ami() {
    log_info "Getting latest Amazon Linux 2 AMI..."
    
    AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    if [[ "${AMI_ID}" == "None" ]]; then
        log_error "Could not find Amazon Linux 2 AMI"
        exit 1
    fi
    
    export AMI_ID
    jq --arg ami_id "${AMI_ID}" '.ami_id = $ami_id' \
        "${TEMP_DIR}/deployment-state.json" > "${TEMP_DIR}/deployment-state.tmp" && \
        mv "${TEMP_DIR}/deployment-state.tmp" "${TEMP_DIR}/deployment-state.json"
    
    log_success "Using AMI: ${AMI_ID}"
}

# Create launch template
create_launch_template() {
    log_info "Creating launch template..."
    
    # Create user data script
    cat > "${TEMP_DIR}/fleet-user-data.sh" << 'EOF'
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<h1>EC2 Fleet Instance</h1>" > /var/www/html/index.html
echo "<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" >> /var/www/html/index.html
echo "<p>Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)</p>" >> /var/www/html/index.html
echo "<p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>" >> /var/www/html/index.html
echo "<p>Lifecycle: $(curl -s http://169.254.169.254/latest/meta-data/instance-life-cycle)</p>" >> /var/www/html/index.html
EOF
    
    # Create launch template
    LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template \
        --launch-template-name "${LAUNCH_TEMPLATE_NAME}" \
        --launch-template-data '{
            "ImageId": "'${AMI_ID}'",
            "InstanceType": "t3.micro",
            "KeyName": "'${KEY_PAIR_NAME}'",
            "SecurityGroupIds": ["'${SECURITY_GROUP_ID}'"],
            "UserData": "'$(base64 -w 0 "${TEMP_DIR}/fleet-user-data.sh")'",
            "TagSpecifications": [{
                "ResourceType": "instance",
                "Tags": [
                    {"Key": "Name", "Value": "Fleet-Instance"},
                    {"Key": "Project", "Value": "EC2-Fleet-Demo"},
                    {"Key": "Environment", "Value": "Demo"}
                ]
            }]
        }' \
        --query 'LaunchTemplate.LaunchTemplateId' --output text)
    
    export LAUNCH_TEMPLATE_ID
    jq --arg lt_id "${LAUNCH_TEMPLATE_ID}" '.launch_template_id = $lt_id' \
        "${TEMP_DIR}/deployment-state.json" > "${TEMP_DIR}/deployment-state.tmp" && \
        mv "${TEMP_DIR}/deployment-state.tmp" "${TEMP_DIR}/deployment-state.json"
    
    log_success "Created launch template: ${LAUNCH_TEMPLATE_ID}"
}

# Create IAM role for Spot Fleet
create_spot_fleet_role() {
    log_info "Creating IAM role for Spot Fleet..."
    
    # Create trust policy
    cat > "${TEMP_DIR}/spot-fleet-trust-policy.json" << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "spotfleet.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role
    SPOT_FLEET_ROLE_ARN=$(aws iam create-role \
        --role-name "${IAM_ROLE_NAME}" \
        --assume-role-policy-document "file://${TEMP_DIR}/spot-fleet-trust-policy.json" \
        --query 'Role.Arn' --output text)
    
    # Attach AWS managed policy
    aws iam attach-role-policy \
        --role-name "${IAM_ROLE_NAME}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonEC2SpotFleetRequestRole"
    
    export SPOT_FLEET_ROLE_ARN
    jq --arg role_arn "${SPOT_FLEET_ROLE_ARN}" '.spot_fleet_role_arn = $role_arn' \
        "${TEMP_DIR}/deployment-state.json" > "${TEMP_DIR}/deployment-state.tmp" && \
        mv "${TEMP_DIR}/deployment-state.tmp" "${TEMP_DIR}/deployment-state.json"
    
    log_success "Created Spot Fleet IAM role: ${SPOT_FLEET_ROLE_ARN}"
}

# Create EC2 Fleet
create_ec2_fleet() {
    log_info "Creating EC2 Fleet..."
    
    # Get availability zones from subnets
    SUBNET_ARRAY=(${SUBNET_IDS})
    AZ1=$(aws ec2 describe-subnets --subnet-ids ${SUBNET_ARRAY[0]} --query 'Subnets[0].AvailabilityZone' --output text)
    AZ2=$(aws ec2 describe-subnets --subnet-ids ${SUBNET_ARRAY[1]} --query 'Subnets[0].AvailabilityZone' --output text 2>/dev/null || echo "${AZ1}")
    
    # Create fleet configuration
    cat > "${TEMP_DIR}/ec2-fleet-config.json" << EOF
{
    "LaunchTemplateConfigs": [
        {
            "LaunchTemplateSpecification": {
                "LaunchTemplateId": "${LAUNCH_TEMPLATE_ID}",
                "Version": "1"
            },
            "Overrides": [
                {
                    "InstanceType": "t3.micro",
                    "SubnetId": "${SUBNET_ARRAY[0]}",
                    "AvailabilityZone": "${AZ1}"
                },
                {
                    "InstanceType": "t3.small",
                    "SubnetId": "${SUBNET_ARRAY[1]:-${SUBNET_ARRAY[0]}}",
                    "AvailabilityZone": "${AZ2}"
                },
                {
                    "InstanceType": "t3.nano",
                    "SubnetId": "${SUBNET_ARRAY[0]}",
                    "AvailabilityZone": "${AZ1}"
                }
            ]
        }
    ],
    "TargetCapacitySpecification": {
        "TotalTargetCapacity": 4,
        "OnDemandTargetCapacity": 1,
        "SpotTargetCapacity": 3,
        "DefaultTargetCapacityType": "spot"
    },
    "OnDemandOptions": {
        "AllocationStrategy": "diversified"
    },
    "SpotOptions": {
        "AllocationStrategy": "capacity-optimized",
        "InstanceInterruptionBehavior": "terminate",
        "ReplaceUnhealthyInstances": true
    },
    "Type": "maintain",
    "ExcessCapacityTerminationPolicy": "termination",
    "ReplaceUnhealthyInstances": true,
    "TagSpecifications": [
        {
            "ResourceType": "fleet",
            "Tags": [
                {"Key": "Name", "Value": "${FLEET_NAME}"},
                {"Key": "Project", "Value": "EC2-Fleet-Demo"},
                {"Key": "Environment", "Value": "Demo"}
            ]
        }
    ]
}
EOF
    
    # Create EC2 Fleet
    FLEET_ID=$(aws ec2 create-fleet \
        --cli-input-json "file://${TEMP_DIR}/ec2-fleet-config.json" \
        --query 'FleetId' --output text)
    
    if [[ "${FLEET_ID}" == "None" ]]; then
        log_error "Failed to create EC2 Fleet"
        exit 1
    fi
    
    export FLEET_ID
    jq --arg fleet_id "${FLEET_ID}" '.fleet_id = $fleet_id' \
        "${TEMP_DIR}/deployment-state.json" > "${TEMP_DIR}/deployment-state.tmp" && \
        mv "${TEMP_DIR}/deployment-state.tmp" "${TEMP_DIR}/deployment-state.json"
    
    log_success "Created EC2 Fleet: ${FLEET_ID}"
    
    # Wait for fleet to be active
    log_info "Waiting for fleet to become active..."
    local max_attempts=20
    local attempt=0
    
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        local fleet_state=$(aws ec2 describe-fleets \
            --fleet-ids "${FLEET_ID}" \
            --query 'Fleets[0].FleetState' --output text)
        
        if [[ "${fleet_state}" == "active" ]]; then
            log_success "EC2 Fleet is now active"
            break
        elif [[ "${fleet_state}" == "failed" ]]; then
            log_error "EC2 Fleet failed to activate"
            exit 1
        fi
        
        sleep 15
        ((attempt++))
        log_info "Fleet state: ${fleet_state} (attempt ${attempt}/${max_attempts})"
    done
    
    if [[ ${attempt} -ge ${max_attempts} ]]; then
        log_error "Timeout waiting for fleet to become active"
        exit 1
    fi
}

# Create Spot Fleet for comparison
create_spot_fleet() {
    log_info "Creating Spot Fleet for comparison..."
    
    # Create Spot Fleet configuration
    cat > "${TEMP_DIR}/spot-fleet-config.json" << EOF
{
    "IamFleetRole": "${SPOT_FLEET_ROLE_ARN}",
    "AllocationStrategy": "capacity-optimized",
    "TargetCapacity": 2,
    "SpotPrice": "0.10",
    "LaunchSpecifications": [
        {
            "ImageId": "${AMI_ID}",
            "InstanceType": "t3.micro",
            "KeyName": "${KEY_PAIR_NAME}",
            "SecurityGroups": [
                {
                    "GroupId": "${SECURITY_GROUP_ID}"
                }
            ],
            "UserData": "$(base64 -w 0 "${TEMP_DIR}/fleet-user-data.sh")",
            "SubnetId": "${SUBNET_ARRAY[0]}",
            "TagSpecifications": [
                {
                    "ResourceType": "instance",
                    "Tags": [
                        {"Key": "Name", "Value": "Spot-Fleet-Instance"},
                        {"Key": "Project", "Value": "EC2-Fleet-Demo"},
                        {"Key": "Environment", "Value": "Demo"}
                    ]
                }
            ]
        }
    ],
    "Type": "maintain",
    "ReplaceUnhealthyInstances": true
}
EOF
    
    # Create Spot Fleet
    SPOT_FLEET_ID=$(aws ec2 request-spot-fleet \
        --spot-fleet-request-config "file://${TEMP_DIR}/spot-fleet-config.json" \
        --query 'SpotFleetRequestId' --output text)
    
    if [[ "${SPOT_FLEET_ID}" == "None" ]]; then
        log_error "Failed to create Spot Fleet"
        exit 1
    fi
    
    export SPOT_FLEET_ID
    jq --arg spot_fleet_id "${SPOT_FLEET_ID}" '.spot_fleet_id = $spot_fleet_id' \
        "${TEMP_DIR}/deployment-state.json" > "${TEMP_DIR}/deployment-state.tmp" && \
        mv "${TEMP_DIR}/deployment-state.tmp" "${TEMP_DIR}/deployment-state.json"
    
    log_success "Created Spot Fleet: ${SPOT_FLEET_ID}"
}

# Create CloudWatch dashboard
create_dashboard() {
    log_info "Creating CloudWatch dashboard..."
    
    cat > "${TEMP_DIR}/dashboard-config.json" << EOF
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
                    ["AWS/EC2", "CPUUtilization", "FleetRequestId", "${FLEET_ID}"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "EC2 Fleet CPU Utilization"
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
                    ["AWS/EC2Spot", "AvailableInstancePoolsCount", "FleetRequestId", "${SPOT_FLEET_ID}"]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Spot Fleet Available Pools"
            }
        }
    ]
}
EOF
    
    # Create CloudWatch dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body "file://${TEMP_DIR}/dashboard-config.json"
    
    log_success "Created CloudWatch dashboard: ${DASHBOARD_NAME}"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check EC2 Fleet instances
    local active_instances=$(aws ec2 describe-fleet-instances \
        --fleet-id "${FLEET_ID}" \
        --query 'length(ActiveInstances)' --output text)
    
    if [[ "${active_instances}" -gt 0 ]]; then
        log_success "EC2 Fleet has ${active_instances} active instances"
        
        # Display instance details
        aws ec2 describe-fleet-instances \
            --fleet-id "${FLEET_ID}" \
            --query 'ActiveInstances[*].[InstanceId,InstanceType,AvailabilityZone,Lifecycle]' \
            --output table
    else
        log_warning "No active instances found in EC2 Fleet"
    fi
    
    # Check Spot Fleet instances
    local spot_instances=$(aws ec2 describe-spot-fleet-instances \
        --spot-fleet-request-id "${SPOT_FLEET_ID}" \
        --query 'length(ActiveInstances)' --output text 2>/dev/null || echo "0")
    
    if [[ "${spot_instances}" -gt 0 ]]; then
        log_success "Spot Fleet has ${spot_instances} active instances"
    else
        log_warning "No active instances found in Spot Fleet"
    fi
    
    # Display current Spot prices
    log_info "Current Spot prices:"
    aws ec2 describe-spot-price-history \
        --instance-types t3.micro t3.small t3.nano \
        --product-descriptions "Linux/UNIX" \
        --max-items 3 \
        --query 'SpotPriceHistory[*].[InstanceType,SpotPrice,AvailabilityZone]' \
        --output table
}

# Main deployment function
main() {
    log_info "Starting EC2 Fleet Management deployment..."
    log_info "Log file: ${LOG_FILE}"
    
    check_prerequisites
    initialize_environment
    create_security_group
    create_key_pair
    get_latest_ami
    create_launch_template
    create_spot_fleet_role
    create_ec2_fleet
    create_spot_fleet
    create_dashboard
    validate_deployment
    
    log_success "Deployment completed successfully!"
    log_info "Deployment state saved to: ${TEMP_DIR}/deployment-state.json"
    log_info "Private key saved to: ${TEMP_DIR}/${KEY_PAIR_NAME}.pem"
    
    echo
    echo "=================================="
    echo "DEPLOYMENT SUMMARY"
    echo "=================================="
    echo "EC2 Fleet ID: ${FLEET_ID}"
    echo "Spot Fleet ID: ${SPOT_FLEET_ID}"
    echo "Launch Template ID: ${LAUNCH_TEMPLATE_ID}"
    echo "Security Group ID: ${SECURITY_GROUP_ID}"
    echo "CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "Key Pair: ${KEY_PAIR_NAME}"
    echo "=================================="
    echo
    echo "To access instances via SSH:"
    echo "chmod 400 ${TEMP_DIR}/${KEY_PAIR_NAME}.pem"
    echo "ssh -i ${TEMP_DIR}/${KEY_PAIR_NAME}.pem ec2-user@<instance-public-ip>"
    echo
    echo "To clean up resources, run:"
    echo "./destroy.sh"
}

# Execute main function
main "$@"