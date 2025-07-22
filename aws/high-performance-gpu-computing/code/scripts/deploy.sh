#!/bin/bash

# GPU-Accelerated Workloads Deployment Script
# This script deploys AWS EC2 P4 and G4 instances for GPU computing workloads
# Recipe: High-Performance GPU Computing Workloads

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of partial resources..."
    if [ -f "./destroy.sh" ]; then
        chmod +x ./destroy.sh
        ./destroy.sh --force
    fi
}

# Set trap for error cleanup
trap cleanup_on_error ERR

# Check if AWS CLI is installed and configured
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
        exit 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check for required permissions
    log_info "Checking AWS permissions..."
    if ! aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text &> /dev/null; then
        log_error "Insufficient EC2 permissions. Please ensure you have EC2 admin permissions."
        exit 1
    fi
    
    # Check for spot fleet role (warn if missing)
    if ! aws iam get-role --role-name aws-ec2-spot-fleet-tagging-role &> /dev/null; then
        log_warning "aws-ec2-spot-fleet-tagging-role not found. G4 instances will be launched as on-demand instead of spot."
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export GPU_FLEET_NAME="gpu-workload-fleet-${RANDOM_SUFFIX}"
    export GPU_KEYPAIR_NAME="gpu-workload-key-${RANDOM_SUFFIX}"
    export GPU_SECURITY_GROUP="gpu-workload-sg-${RANDOM_SUFFIX}"
    export GPU_IAM_ROLE="gpu-workload-role-${RANDOM_SUFFIX}"
    export GPU_SNS_TOPIC="gpu-workload-alerts-${RANDOM_SUFFIX}"
    
    # Get default VPC and subnet information
    export DEFAULT_VPC=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text)
    
    if [ "$DEFAULT_VPC" = "None" ] || [ -z "$DEFAULT_VPC" ]; then
        log_error "No default VPC found. Please create a VPC first or specify a VPC ID."
        exit 1
    fi
    
    export DEFAULT_SUBNET=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${DEFAULT_VPC}" \
        "Name=default-for-az,Values=true" \
        --query "Subnets[0].SubnetId" --output text)
    
    if [ "$DEFAULT_SUBNET" = "None" ] || [ -z "$DEFAULT_SUBNET" ]; then
        log_error "No default subnet found. Please create a subnet first or specify a subnet ID."
        exit 1
    fi
    
    # Save environment variables for cleanup script
    cat > .gpu_deployment_vars << EOF
export AWS_REGION=${AWS_REGION}
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
export GPU_FLEET_NAME=${GPU_FLEET_NAME}
export GPU_KEYPAIR_NAME=${GPU_KEYPAIR_NAME}
export GPU_SECURITY_GROUP=${GPU_SECURITY_GROUP}
export GPU_IAM_ROLE=${GPU_IAM_ROLE}
export GPU_SNS_TOPIC=${GPU_SNS_TOPIC}
export DEFAULT_VPC=${DEFAULT_VPC}
export DEFAULT_SUBNET=${DEFAULT_SUBNET}
EOF
    
    log_success "Environment variables configured"
    log_info "VPC: ${DEFAULT_VPC}, Subnet: ${DEFAULT_SUBNET}"
}

# Create security group
create_security_group() {
    log_info "Creating security group for GPU instances..."
    
    SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name ${GPU_SECURITY_GROUP} \
        --description "Security group for GPU workloads" \
        --vpc-id ${DEFAULT_VPC} \
        --output text --query GroupId)
    
    # Add security group ID to environment file
    echo "export SECURITY_GROUP_ID=${SECURITY_GROUP_ID}" >> .gpu_deployment_vars
    
    # Allow SSH access
    aws ec2 authorize-security-group-ingress \
        --group-id ${SECURITY_GROUP_ID} \
        --protocol tcp --port 22 \
        --cidr 0.0.0.0/0
    
    # Allow Jupyter/TensorBoard access
    aws ec2 authorize-security-group-ingress \
        --group-id ${SECURITY_GROUP_ID} \
        --protocol tcp --port 8888 \
        --source-group ${SECURITY_GROUP_ID}
    
    log_success "Security group created: ${SECURITY_GROUP_ID}"
}

# Create key pair
create_key_pair() {
    log_info "Creating key pair for SSH access..."
    
    aws ec2 create-key-pair \
        --key-name ${GPU_KEYPAIR_NAME} \
        --key-type rsa --key-format pem \
        --query "KeyMaterial" --output text \
        > ${GPU_KEYPAIR_NAME}.pem
    
    chmod 400 ${GPU_KEYPAIR_NAME}.pem
    
    log_success "Key pair created: ${GPU_KEYPAIR_NAME}.pem"
}

# Create IAM role
create_iam_role() {
    log_info "Creating IAM role for GPU instances..."
    
    # Create trust policy
    cat > gpu-trust-policy.json << 'EOF'
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
    aws iam create-role \
        --role-name ${GPU_IAM_ROLE} \
        --assume-role-policy-document file://gpu-trust-policy.json
    
    # Attach necessary policies
    aws iam attach-role-policy \
        --role-name ${GPU_IAM_ROLE} \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
    
    aws iam attach-role-policy \
        --role-name ${GPU_IAM_ROLE} \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
    
    # Create instance profile
    aws iam create-instance-profile \
        --instance-profile-name ${GPU_IAM_ROLE}
    
    # Wait for instance profile to be available
    sleep 10
    
    aws iam add-role-to-instance-profile \
        --instance-profile-name ${GPU_IAM_ROLE} \
        --role-name ${GPU_IAM_ROLE}
    
    log_success "IAM role and instance profile created"
}

# Create SNS topic
create_sns_topic() {
    log_info "Creating SNS topic for monitoring alerts..."
    
    GPU_SNS_ARN=$(aws sns create-topic \
        --name ${GPU_SNS_TOPIC} \
        --output text --query TopicArn)
    
    # Add SNS ARN to environment file
    echo "export GPU_SNS_ARN=${GPU_SNS_ARN}" >> .gpu_deployment_vars
    
    # Subscribe email if provided
    if [ ! -z "$USER_EMAIL" ]; then
        aws sns subscribe \
            --topic-arn ${GPU_SNS_ARN} \
            --protocol email \
            --notification-endpoint ${USER_EMAIL}
        log_info "Email subscription added. Please confirm subscription in your email."
    else
        log_warning "No email provided for SNS notifications. Set USER_EMAIL environment variable to receive alerts."
    fi
    
    log_success "SNS topic created: ${GPU_SNS_ARN}"
}

# Create user data script
create_user_data_script() {
    log_info "Creating user data script for GPU setup..."
    
    cat > gpu-userdata.sh << 'EOF'
#!/bin/bash
yum update -y
yum install -y awscli

# Install NVIDIA drivers
aws s3 cp --recursive s3://ec2-linux-nvidia-drivers/latest/ .
chmod +x NVIDIA-Linux-x86_64*.run
./NVIDIA-Linux-x86_64*.run --silent

# Install Docker for containerized workloads
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | rpm --import -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.repo | tee /etc/yum.repos.d/nvidia-docker.repo
yum install -y nvidia-docker2
systemctl restart docker

# Install Python and ML frameworks
amazon-linux-extras install python3.8 -y
pip3 install torch torchvision torchaudio tensorflow-gpu jupyter matplotlib pandas numpy

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Configure GPU monitoring
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'
{
    "agent": {
        "metrics_collection_interval": 60
    },
    "metrics": {
        "namespace": "GPU/EC2",
        "metrics_collected": {
            "nvidia_gpu": {
                "measurement": [
                    "utilization_gpu",
                    "utilization_memory",
                    "temperature_gpu",
                    "power_draw"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
CWCONFIG

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

echo "GPU setup completed" > /tmp/gpu-setup-complete
EOF
    
    log_success "User data script created"
}

# Launch P4 instance
launch_p4_instance() {
    log_info "Launching P4 instance for ML training..."
    
    # Get the latest Deep Learning AMI
    DLAMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=Deep Learning AMI*Ubuntu*" \
        "Name=state,Values=available" \
        --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" \
        --output text)
    
    if [ "$DLAMI_ID" = "None" ] || [ -z "$DLAMI_ID" ]; then
        log_error "Could not find Deep Learning AMI. Please check your region."
        exit 1
    fi
    
    # Launch P4 instance
    P4_INSTANCE_ID=$(aws ec2 run-instances \
        --image-id ${DLAMI_ID} \
        --instance-type p4d.24xlarge \
        --key-name ${GPU_KEYPAIR_NAME} \
        --security-group-ids ${SECURITY_GROUP_ID} \
        --subnet-id ${DEFAULT_SUBNET} \
        --iam-instance-profile Name=${GPU_IAM_ROLE} \
        --user-data file://gpu-userdata.sh \
        --tag-specifications \
        'ResourceType=instance,Tags=[{Key=Name,Value=P4-ML-Training},{Key=Purpose,Value=GPU-Workload}]' \
        --query "Instances[0].InstanceId" --output text)
    
    # Add P4 instance ID to environment file
    echo "export P4_INSTANCE_ID=${P4_INSTANCE_ID}" >> .gpu_deployment_vars
    
    log_success "P4 instance launched: ${P4_INSTANCE_ID}"
    log_info "Instance is initializing - this may take 10-15 minutes"
}

# Launch G4 instances
launch_g4_instances() {
    log_info "Launching G4 instances for inference and graphics..."
    
    # Get the latest Deep Learning AMI
    DLAMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=Deep Learning AMI*Ubuntu*" \
        "Name=state,Values=available" \
        --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" \
        --output text)
    
    # Check if spot fleet role exists
    if aws iam get-role --role-name aws-ec2-spot-fleet-tagging-role &> /dev/null; then
        log_info "Creating Spot Fleet for cost-optimized G4 instances..."
        
        # Create Spot Fleet configuration
        cat > g4-spot-fleet-config.json << EOF
{
    "SpotPrice": "0.50",
    "TargetCapacity": 2,
    "AllocationStrategy": "lowestPrice",
    "IamFleetRole": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/aws-ec2-spot-fleet-tagging-role",
    "LaunchSpecifications": [
        {
            "ImageId": "${DLAMI_ID}",
            "InstanceType": "g4dn.xlarge",
            "KeyName": "${GPU_KEYPAIR_NAME}",
            "SecurityGroups": [
                {
                    "GroupId": "${SECURITY_GROUP_ID}"
                }
            ],
            "SubnetId": "${DEFAULT_SUBNET}",
            "IamInstanceProfile": {
                "Name": "${GPU_IAM_ROLE}"
            },
            "UserData": "$(base64 -w 0 gpu-userdata.sh)",
            "TagSpecifications": [
                {
                    "ResourceType": "instance",
                    "Tags": [
                        {
                            "Key": "Name",
                            "Value": "G4-Spot-Inference"
                        },
                        {
                            "Key": "Purpose",
                            "Value": "GPU-Workload"
                        }
                    ]
                }
            ]
        },
        {
            "ImageId": "${DLAMI_ID}",
            "InstanceType": "g4dn.2xlarge",
            "KeyName": "${GPU_KEYPAIR_NAME}",
            "SecurityGroups": [
                {
                    "GroupId": "${SECURITY_GROUP_ID}"
                }
            ],
            "SubnetId": "${DEFAULT_SUBNET}",
            "IamInstanceProfile": {
                "Name": "${GPU_IAM_ROLE}"
            },
            "UserData": "$(base64 -w 0 gpu-userdata.sh)",
            "TagSpecifications": [
                {
                    "ResourceType": "instance",
                    "Tags": [
                        {
                            "Key": "Name",
                            "Value": "G4-Spot-Graphics"
                        },
                        {
                            "Key": "Purpose",
                            "Value": "GPU-Workload"
                        }
                    ]
                }
            ]
        }
    ]
}
EOF
        
        SPOT_FLEET_ID=$(aws ec2 request-spot-fleet \
            --spot-fleet-request-config file://g4-spot-fleet-config.json \
            --query "SpotFleetRequestId" --output text)
        
        echo "export SPOT_FLEET_ID=${SPOT_FLEET_ID}" >> .gpu_deployment_vars
        log_success "G4 Spot Fleet requested: ${SPOT_FLEET_ID}"
    else
        log_warning "Spot Fleet role not found. Creating G4 instance directly..."
        
        G4_INSTANCE_ID=$(aws ec2 run-instances \
            --image-id ${DLAMI_ID} \
            --instance-type g4dn.xlarge \
            --key-name ${GPU_KEYPAIR_NAME} \
            --security-group-ids ${SECURITY_GROUP_ID} \
            --subnet-id ${DEFAULT_SUBNET} \
            --iam-instance-profile Name=${GPU_IAM_ROLE} \
            --user-data file://gpu-userdata.sh \
            --tag-specifications \
            'ResourceType=instance,Tags=[{Key=Name,Value=G4-Inference},{Key=Purpose,Value=GPU-Workload}]' \
            --query "Instances[0].InstanceId" --output text)
        
        echo "export G4_INSTANCE_ID=${G4_INSTANCE_ID}" >> .gpu_deployment_vars
        log_success "G4 instance launched: ${G4_INSTANCE_ID}"
    fi
}

# Create CloudWatch dashboard
create_cloudwatch_dashboard() {
    log_info "Setting up GPU performance monitoring..."
    
    # Source the environment variables to get P4_INSTANCE_ID
    source .gpu_deployment_vars
    
    cat > gpu-dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0, "y": 0, "width": 12, "height": 6,
            "properties": {
                "metrics": [
                    [ "GPU/EC2", "utilization_gpu", "InstanceId", "${P4_INSTANCE_ID}" ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "GPU Utilization"
            }
        },
        {
            "type": "metric",
            "x": 12, "y": 0, "width": 12, "height": 6,
            "properties": {
                "metrics": [
                    [ "GPU/EC2", "utilization_memory", "InstanceId", "${P4_INSTANCE_ID}" ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "GPU Memory Utilization"
            }
        },
        {
            "type": "metric",
            "x": 0, "y": 6, "width": 12, "height": 6,
            "properties": {
                "metrics": [
                    [ "GPU/EC2", "temperature_gpu", "InstanceId", "${P4_INSTANCE_ID}" ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "GPU Temperature"
            }
        },
        {
            "type": "metric",
            "x": 12, "y": 6, "width": 12, "height": 6,
            "properties": {
                "metrics": [
                    [ "GPU/EC2", "power_draw", "InstanceId", "${P4_INSTANCE_ID}" ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "GPU Power Consumption"
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "GPU-Workload-Monitoring" \
        --dashboard-body file://gpu-dashboard.json
    
    log_success "CloudWatch dashboard created"
}

# Create performance alarms
create_performance_alarms() {
    log_info "Creating performance alarms..."
    
    # Source the environment variables
    source .gpu_deployment_vars
    
    # High temperature alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "GPU-High-Temperature" \
        --alarm-description "GPU temperature too high" \
        --metric-name temperature_gpu \
        --namespace GPU/EC2 \
        --statistic Average \
        --period 300 \
        --threshold 85 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions ${GPU_SNS_ARN} \
        --dimensions Name=InstanceId,Value=${P4_INSTANCE_ID}
    
    # Low utilization alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "GPU-Low-Utilization" \
        --alarm-description "GPU utilization too low" \
        --metric-name utilization_gpu \
        --namespace GPU/EC2 \
        --statistic Average \
        --period 1800 \
        --threshold 10 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 3 \
        --alarm-actions ${GPU_SNS_ARN} \
        --dimensions Name=InstanceId,Value=${P4_INSTANCE_ID}
    
    log_success "Performance alarms created"
}

# Wait for instance initialization
wait_for_instances() {
    log_info "Waiting for instances to be ready..."
    
    # Source the environment variables
    source .gpu_deployment_vars
    
    # Wait for P4 instance to be running
    log_info "Waiting for P4 instance to be running..."
    aws ec2 wait instance-running --instance-ids ${P4_INSTANCE_ID}
    
    # Get instance public IP
    P4_PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids ${P4_INSTANCE_ID} \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --output text)
    
    echo "export P4_PUBLIC_IP=${P4_PUBLIC_IP}" >> .gpu_deployment_vars
    
    log_success "P4 instance is running at: ${P4_PUBLIC_IP}"
    log_info "GPU drivers are installing in the background (this may take 10-15 minutes)"
}

# Display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=================="
    
    # Source the environment variables
    source .gpu_deployment_vars
    
    echo -e "${GREEN}✅ GPU Infrastructure Deployed Successfully${NC}"
    echo
    echo "P4 Instance (ML Training):"
    echo "  Instance ID: ${P4_INSTANCE_ID}"
    echo "  Public IP: ${P4_PUBLIC_IP}"
    echo "  SSH Command: ssh -i ${GPU_KEYPAIR_NAME}.pem ubuntu@${P4_PUBLIC_IP}"
    echo
    echo "Monitoring:"
    echo "  CloudWatch Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=GPU-Workload-Monitoring"
    echo "  SNS Topic: ${GPU_SNS_ARN}"
    echo
    echo "Security:"
    echo "  Security Group: ${SECURITY_GROUP_ID}"
    echo "  Key Pair: ${GPU_KEYPAIR_NAME}.pem"
    echo "  IAM Role: ${GPU_IAM_ROLE}"
    echo
    echo "Next Steps:"
    echo "1. Wait 10-15 minutes for GPU drivers to install"
    echo "2. SSH to the P4 instance and verify setup:"
    echo "   nvidia-smi"
    echo "   python3 -c 'import torch; print(torch.cuda.is_available())'"
    echo "3. Monitor GPU metrics in CloudWatch dashboard"
    echo "4. Run your ML training workloads"
    echo
    echo -e "${YELLOW}Remember: GPU instances are expensive. Monitor usage and terminate when not needed.${NC}"
    echo -e "${YELLOW}Use ./destroy.sh to clean up all resources.${NC}"
}

# Main deployment function
main() {
    echo "=============================================="
    echo "GPU-Accelerated Workloads Deployment Script"
    echo "=============================================="
    echo
    
    # Check for email parameter
    if [ "$1" = "--email" ] && [ ! -z "$2" ]; then
        export USER_EMAIL="$2"
        log_info "Email notifications will be sent to: $USER_EMAIL"
    fi
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_security_group
    create_key_pair
    create_iam_role
    create_sns_topic
    create_user_data_script
    launch_p4_instance
    launch_g4_instances
    create_cloudwatch_dashboard
    create_performance_alarms
    wait_for_instances
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function with all arguments
main "$@"