#!/bin/bash

# Predictive Scaling EC2 Auto Scaling with Machine Learning - Deployment Script
# This script automates the deployment of AWS Auto Scaling with predictive scaling capabilities

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    log "${RED}Deployment failed at ${TIMESTAMP}${NC}"
    exit 1
}

# Success message function
success() {
    log "${GREEN}✅ ${1}${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️  ${1}${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️  ${1}${NC}"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2 and configure credentials."
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: ${AWS_CLI_VERSION}"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials are not configured. Please run 'aws configure' or set environment variables."
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some optional features may not work."
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, using default: us-east-1"
    fi
    
    info "Using AWS region: ${AWS_REGION}"
    success "Environment variables configured"
}

# Create VPC and networking components
create_vpc() {
    info "Creating VPC and networking components..."
    
    # Create VPC
    export VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
        --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=PredictiveScalingVPC},{Key=Purpose,Value=PredictiveScalingDemo}]' \
        --query Vpc.VpcId --output text 2>/dev/null || echo "")
    
    if [[ -z "${VPC_ID}" ]]; then
        error_exit "Failed to create VPC"
    fi
    
    info "Created VPC: ${VPC_ID}"
    
    # Wait for VPC to be available
    aws ec2 wait vpc-available --vpc-ids "${VPC_ID}" || error_exit "VPC did not become available"
    
    # Create subnets
    export SUBNET_ID_1=$(aws ec2 create-subnet --vpc-id "${VPC_ID}" --cidr-block 10.0.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=PredictiveScalingSubnet1}]' \
        --query Subnet.SubnetId --output text 2>/dev/null || echo "")
    
    export SUBNET_ID_2=$(aws ec2 create-subnet --vpc-id "${VPC_ID}" --cidr-block 10.0.2.0/24 \
        --availability-zone "${AWS_REGION}b" \
        --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=PredictiveScalingSubnet2}]' \
        --query Subnet.SubnetId --output text 2>/dev/null || echo "")
    
    if [[ -z "${SUBNET_ID_1}" ]] || [[ -z "${SUBNET_ID_2}" ]]; then
        error_exit "Failed to create subnets"
    fi
    
    info "Created subnets: ${SUBNET_ID_1}, ${SUBNET_ID_2}"
    
    # Create Internet Gateway
    export IGW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=PredictiveScalingIGW}]' \
        --query InternetGateway.InternetGatewayId --output text 2>/dev/null || echo "")
    
    if [[ -z "${IGW_ID}" ]]; then
        error_exit "Failed to create Internet Gateway"
    fi
    
    # Attach Internet Gateway to VPC
    aws ec2 attach-internet-gateway --vpc-id "${VPC_ID}" --internet-gateway-id "${IGW_ID}" || \
        error_exit "Failed to attach Internet Gateway to VPC"
    
    info "Created and attached Internet Gateway: ${IGW_ID}"
    
    # Create route table
    export RTB_ID=$(aws ec2 create-route-table --vpc-id "${VPC_ID}" \
        --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=PredictiveScalingRTB}]' \
        --query RouteTable.RouteTableId --output text 2>/dev/null || echo "")
    
    if [[ -z "${RTB_ID}" ]]; then
        error_exit "Failed to create route table"
    fi
    
    # Add route to Internet Gateway
    aws ec2 create-route --route-table-id "${RTB_ID}" \
        --destination-cidr-block 0.0.0.0/0 --gateway-id "${IGW_ID}" || \
        error_exit "Failed to create route to Internet Gateway"
    
    # Associate route table with subnets
    aws ec2 associate-route-table --subnet-id "${SUBNET_ID_1}" --route-table-id "${RTB_ID}" || \
        error_exit "Failed to associate route table with subnet 1"
    
    aws ec2 associate-route-table --subnet-id "${SUBNET_ID_2}" --route-table-id "${RTB_ID}" || \
        error_exit "Failed to associate route table with subnet 2"
    
    success "VPC and networking components created successfully"
}

# Create security group
create_security_group() {
    info "Creating security group..."
    
    export SG_ID=$(aws ec2 create-security-group \
        --group-name PredictiveScalingSG \
        --description "Security group for Predictive Scaling demo" \
        --vpc-id "${VPC_ID}" \
        --query GroupId --output text 2>/dev/null || echo "")
    
    if [[ -z "${SG_ID}" ]]; then
        error_exit "Failed to create security group"
    fi
    
    # Allow HTTP traffic
    aws ec2 authorize-security-group-ingress --group-id "${SG_ID}" \
        --protocol tcp --port 80 --cidr 0.0.0.0/0 || \
        error_exit "Failed to add HTTP rule to security group"
    
    # Allow SSH access (optional, for debugging)
    aws ec2 authorize-security-group-ingress --group-id "${SG_ID}" \
        --protocol tcp --port 22 --cidr 0.0.0.0/0 || \
        warning "Failed to add SSH rule to security group"
    
    success "Security group created: ${SG_ID}"
}

# Create IAM role and instance profile
create_iam_resources() {
    info "Creating IAM resources..."
    
    # Create trust policy
    cat > "${SCRIPT_DIR}/trust-policy.json" << 'EOF'
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
    aws iam create-role --role-name PredictiveScalingEC2Role \
        --assume-role-policy-document file://"${SCRIPT_DIR}/trust-policy.json" || \
        warning "IAM role may already exist"
    
    # Attach CloudWatch policy
    aws iam attach-role-policy --role-name PredictiveScalingEC2Role \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy || \
        warning "Policy may already be attached"
    
    # Create instance profile
    export INSTANCE_PROFILE=$(aws iam create-instance-profile \
        --instance-profile-name PredictiveScalingProfile \
        --query InstanceProfile.InstanceProfileName --output text 2>/dev/null || echo "PredictiveScalingProfile")
    
    # Add role to instance profile
    aws iam add-role-to-instance-profile \
        --instance-profile-name PredictiveScalingProfile \
        --role-name PredictiveScalingEC2Role || \
        warning "Role may already be in instance profile"
    
    # Wait for instance profile to be ready
    sleep 10
    
    success "IAM resources created successfully"
}

# Create launch template
create_launch_template() {
    info "Creating launch template..."
    
    # Get the latest Amazon Linux 2 AMI ID
    export AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-2.0.*-x86_64-gp2" "Name=state,Values=available" \
        --query "sort_by(Images, &CreationDate)[-1].ImageId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "${AMI_ID}" ]]; then
        error_exit "Failed to get Amazon Linux 2 AMI ID"
    fi
    
    info "Using AMI: ${AMI_ID}"
    
    # Create user data script
    cat > "${SCRIPT_DIR}/user-data.txt" << 'EOF'
#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo "<html><body><h1>Predictive Scaling Demo</h1><p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p><p>Timestamp: $(date)</p></body></html>" > /var/www/html/index.html

# Install stress tool for demonstration
yum install -y stress

# Create CPU load patterns for demonstration
cat > /etc/cron.d/stress << 'END'
# Create CPU load during business hours (8 AM - 8 PM UTC) on weekdays
0 8 * * 1-5 root stress --cpu 2 --timeout 12h > /dev/null 2>&1
# Create lower CPU load during weekends
0 10 * * 6,0 root stress --cpu 1 --timeout 8h > /dev/null 2>&1
END

# Install CloudWatch agent
yum install -y amazon-cloudwatch-agent
EOF
    
    # Create launch template
    export LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template \
        --launch-template-name PredictiveScalingTemplate \
        --version-description "Initial version for predictive scaling demo" \
        --launch-template-data "{
          \"ImageId\": \"${AMI_ID}\",
          \"InstanceType\": \"t3.micro\",
          \"SecurityGroupIds\": [\"${SG_ID}\"],
          \"UserData\": \"$(base64 -w 0 "${SCRIPT_DIR}/user-data.txt")\",
          \"IamInstanceProfile\": {
            \"Name\": \"PredictiveScalingProfile\"
          },
          \"TagSpecifications\": [{
            \"ResourceType\": \"instance\",
            \"Tags\": [{
              \"Key\": \"Name\",
              \"Value\": \"PredictiveScalingInstance\"
            }, {
              \"Key\": \"Purpose\",
              \"Value\": \"PredictiveScalingDemo\"
            }]
          }]
        }" \
        --query LaunchTemplate.LaunchTemplateId --output text 2>/dev/null || echo "")
    
    if [[ -z "${LAUNCH_TEMPLATE_ID}" ]]; then
        error_exit "Failed to create launch template"
    fi
    
    success "Launch template created: ${LAUNCH_TEMPLATE_ID}"
}

# Create Auto Scaling Group
create_auto_scaling_group() {
    info "Creating Auto Scaling Group..."
    
    aws autoscaling create-auto-scaling-group \
        --auto-scaling-group-name PredictiveScalingASG \
        --launch-template LaunchTemplateId="${LAUNCH_TEMPLATE_ID}" \
        --min-size 2 \
        --max-size 10 \
        --desired-capacity 2 \
        --vpc-zone-identifier "${SUBNET_ID_1},${SUBNET_ID_2}" \
        --default-instance-warmup 300 \
        --tags "Key=Environment,Value=Demo,PropagateAtLaunch=true" "Key=Purpose,Value=PredictiveScaling,PropagateAtLaunch=true" || \
        error_exit "Failed to create Auto Scaling Group"
    
    # Wait for instances to launch
    info "Waiting for instances to launch..."
    sleep 30
    
    success "Auto Scaling Group created successfully"
}

# Create CloudWatch Dashboard
create_dashboard() {
    info "Creating CloudWatch Dashboard..."
    
    cat > "${SCRIPT_DIR}/dashboard.json" << EOF
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
          [ "AWS/EC2", "CPUUtilization", "AutoScalingGroupName", "PredictiveScalingASG", { "stat": "Average" } ]
        ],
        "period": 300,
        "title": "ASG CPU Utilization",
        "region": "${AWS_REGION}",
        "view": "timeSeries"
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
          [ "AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", "PredictiveScalingASG" ]
        ],
        "period": 300,
        "title": "ASG Instance Count",
        "region": "${AWS_REGION}",
        "view": "timeSeries"
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 6,
      "width": 24,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", "PredictiveScalingASG" ],
          [ ".", "GroupMinSize", ".", "." ],
          [ ".", "GroupMaxSize", ".", "." ]
        ],
        "period": 300,
        "title": "ASG Capacity Settings",
        "region": "${AWS_REGION}",
        "view": "timeSeries"
      }
    }
  ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name PredictiveScalingDashboard \
        --dashboard-body file://"${SCRIPT_DIR}/dashboard.json" || \
        error_exit "Failed to create CloudWatch dashboard"
    
    success "CloudWatch dashboard created"
}

# Create scaling policies
create_scaling_policies() {
    info "Creating scaling policies..."
    
    # Create target tracking scaling policy
    aws autoscaling put-scaling-policy \
        --auto-scaling-group-name PredictiveScalingASG \
        --policy-name CPUTargetTracking \
        --policy-type TargetTrackingScaling \
        --target-tracking-configuration "{
          \"PredefinedMetricSpecification\": {
            \"PredefinedMetricType\": \"ASGAverageCPUUtilization\"
          },
          \"TargetValue\": 50.0,
          \"DisableScaleIn\": false
        }" || error_exit "Failed to create target tracking policy"
    
    success "Target tracking scaling policy created"
    
    # Create predictive scaling policy configuration
    cat > "${SCRIPT_DIR}/predictive-scaling-config.json" << 'EOF'
{
  "MetricSpecifications": [
    {
      "TargetValue": 50,
      "PredefinedMetricPairSpecification": {
        "PredefinedMetricType": "ASGCPUUtilization"
      }
    }
  ],
  "Mode": "ForecastOnly",
  "SchedulingBufferTime": 300,
  "MaxCapacityBreachBehavior": "IncreaseMaxCapacity",
  "MaxCapacityBuffer": 10
}
EOF
    
    # Apply predictive scaling policy
    aws autoscaling put-scaling-policy \
        --auto-scaling-group-name PredictiveScalingASG \
        --policy-name PredictiveScalingPolicy \
        --policy-type PredictiveScaling \
        --predictive-scaling-configuration file://"${SCRIPT_DIR}/predictive-scaling-config.json" || \
        error_exit "Failed to create predictive scaling policy"
    
    success "Predictive scaling policy created (ForecastOnly mode)"
}

# Save deployment information
save_deployment_info() {
    info "Saving deployment information..."
    
    cat > "${SCRIPT_DIR}/deployment-info.txt" << EOF
Predictive Scaling Deployment Information
Generated: ${TIMESTAMP}

AWS Region: ${AWS_REGION}
VPC ID: ${VPC_ID}
Subnet IDs: ${SUBNET_ID_1}, ${SUBNET_ID_2}
Security Group ID: ${SG_ID}
Internet Gateway ID: ${IGW_ID}
Route Table ID: ${RTB_ID}
Launch Template ID: ${LAUNCH_TEMPLATE_ID}
AMI ID: ${AMI_ID}

Auto Scaling Group: PredictiveScalingASG
CloudWatch Dashboard: PredictiveScalingDashboard

Dashboard URL: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=PredictiveScalingDashboard
Auto Scaling Groups Console: https://${AWS_REGION}.console.aws.amazon.com/ec2autoscaling/home?region=${AWS_REGION}#/details/PredictiveScalingASG

Next Steps:
1. Wait 24-48 hours for sufficient historical data
2. Review predictive scaling forecasts
3. Switch to ForecastAndScale mode when ready

Note: This deployment is for demonstration purposes.
Monitor costs and clean up resources when done testing.
EOF
    
    success "Deployment information saved to deployment-info.txt"
}

# Validate deployment
validate_deployment() {
    info "Validating deployment..."
    
    # Check Auto Scaling Group
    ASG_STATUS=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names PredictiveScalingASG \
        --query "AutoScalingGroups[0].AutoScalingGroupName" --output text 2>/dev/null || echo "")
    
    if [[ "${ASG_STATUS}" != "PredictiveScalingASG" ]]; then
        error_exit "Auto Scaling Group validation failed"
    fi
    
    # Check instances
    INSTANCE_COUNT=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names PredictiveScalingASG \
        --query "AutoScalingGroups[0].Instances | length(@)" --output text 2>/dev/null || echo "0")
    
    if [[ "${INSTANCE_COUNT}" -lt "2" ]]; then
        warning "Expected 2 instances, found ${INSTANCE_COUNT}. Instances may still be launching."
    fi
    
    # Check scaling policies
    POLICY_COUNT=$(aws autoscaling describe-policies \
        --auto-scaling-group-name PredictiveScalingASG \
        --query "ScalingPolicies | length(@)" --output text 2>/dev/null || echo "0")
    
    if [[ "${POLICY_COUNT}" -lt "2" ]]; then
        warning "Expected 2 scaling policies, found ${POLICY_COUNT}"
    fi
    
    success "Deployment validation completed"
}

# Main deployment function
main() {
    log "${BLUE}Starting Predictive Scaling deployment at ${TIMESTAMP}${NC}"
    
    check_prerequisites
    setup_environment
    create_vpc
    create_security_group
    create_iam_resources
    create_launch_template
    create_auto_scaling_group
    create_dashboard
    create_scaling_policies
    save_deployment_info
    validate_deployment
    
    log ""
    log "${GREEN}========================================${NC}"
    log "${GREEN}Deployment completed successfully! 🎉${NC}"
    log "${GREEN}========================================${NC}"
    log ""
    log "Dashboard URL: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=PredictiveScalingDashboard"
    log ""
    log "${YELLOW}Important Notes:${NC}"
    log "1. Predictive scaling is currently in ForecastOnly mode"
    log "2. Wait 24-48 hours for historical data collection"
    log "3. Review forecasts before enabling ForecastAndScale mode"
    log "4. Monitor costs and clean up resources when testing is complete"
    log ""
    log "To clean up all resources, run: ./destroy.sh"
    log ""
}

# Cleanup function for script interruption
cleanup_on_exit() {
    warning "Script interrupted. Cleaning up temporary files..."
    rm -f "${SCRIPT_DIR}/trust-policy.json" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/user-data.txt" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/dashboard.json" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/predictive-scaling-config.json" 2>/dev/null || true
}

# Set trap for cleanup
trap cleanup_on_exit EXIT

# Run main function
main "$@"