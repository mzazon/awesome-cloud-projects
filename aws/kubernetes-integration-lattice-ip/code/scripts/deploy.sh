#!/bin/bash

# Self-Managed Kubernetes Integration with VPC Lattice IP Targets - Deployment Script
# Recipe: kubernetes-integration-lattice-ip
# Version: 1.1
# Last Updated: 2025-07-12

set -euo pipefail

# Enable debug mode if DEBUG environment variable is set
if [[ "${DEBUG:-}" == "true" ]]; then
    set -x
fi

# Color codes for output
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
    log_error "Deployment failed. Check the logs above for details."
    log_info "Run the destroy script to clean up any partially created resources."
    exit 1
}

# Trap to handle script interruption
trap 'error_exit "Script interrupted by user"' INT TERM

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version=$(echo $aws_version | cut -d. -f1)
    if [[ $major_version -lt 2 ]]; then
        error_exit "AWS CLI v2 or higher is required. Current version: $aws_version"
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set appropriate environment variables."
    fi
    
    # Check if required permissions exist (basic check)
    local account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    if [[ -z "$account_id" ]]; then
        error_exit "Unable to retrieve AWS account information. Check your credentials and permissions."
    fi
    
    log_success "Prerequisites check completed successfully"
    log_info "AWS Account ID: $account_id"
}

# Initialize environment variables
initialize_environment() {
    log_info "Initializing environment variables..."
    
    # Set AWS configuration
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    if [[ -z "$AWS_REGION" ]]; then
        log_warning "AWS region not configured, using us-east-1 as default"
        export AWS_REGION="us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifier for resources
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || \
            echo "$(date +%s | tail -c 6)")
    fi
    
    # Set resource names with unique suffix
    export VPC_A_NAME="k8s-vpc-a-${RANDOM_SUFFIX}"
    export VPC_B_NAME="k8s-vpc-b-${RANDOM_SUFFIX}"
    export SERVICE_NETWORK_NAME="lattice-k8s-mesh-${RANDOM_SUFFIX}"
    export FRONTEND_SERVICE_NAME="frontend-svc-${RANDOM_SUFFIX}"
    export BACKEND_SERVICE_NAME="backend-svc-${RANDOM_SUFFIX}"
    export KEY_PAIR_NAME="k8s-lattice-${RANDOM_SUFFIX}"
    
    log_success "Environment initialized with unique suffix: ${RANDOM_SUFFIX}"
    log_info "AWS Region: ${AWS_REGION}"
}

# Create SSH key pair
create_ssh_key() {
    log_info "Creating SSH key pair..."
    
    # Check if key pair already exists
    if aws ec2 describe-key-pairs --key-names "${KEY_PAIR_NAME}" &>/dev/null; then
        log_warning "Key pair ${KEY_PAIR_NAME} already exists, skipping creation"
        return 0
    fi
    
    aws ec2 create-key-pair \
        --key-name "${KEY_PAIR_NAME}" \
        --query 'KeyMaterial' --output text > k8s-lattice-key.pem || \
        error_exit "Failed to create SSH key pair"
    
    chmod 400 k8s-lattice-key.pem
    
    log_success "SSH key pair created: ${KEY_PAIR_NAME}"
}

# Create VPC infrastructure
create_vpc_infrastructure() {
    log_info "Creating VPC infrastructure..."
    
    # Create VPC A
    log_info "Creating VPC A..."
    export VPC_A_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --query 'Vpc.VpcId' --output text) || \
        error_exit "Failed to create VPC A"
    
    aws ec2 create-tags \
        --resources ${VPC_A_ID} \
        --tags Key=Name,Value=${VPC_A_NAME} || \
        error_exit "Failed to tag VPC A"
    
    # Create VPC B
    log_info "Creating VPC B..."
    export VPC_B_ID=$(aws ec2 create-vpc \
        --cidr-block 10.1.0.0/16 \
        --query 'Vpc.VpcId' --output text) || \
        error_exit "Failed to create VPC B"
    
    aws ec2 create-tags \
        --resources ${VPC_B_ID} \
        --tags Key=Name,Value=${VPC_B_NAME} || \
        error_exit "Failed to tag VPC B"
    
    log_success "VPCs created: ${VPC_A_ID} and ${VPC_B_ID}"
    
    # Wait for VPCs to be available
    log_info "Waiting for VPCs to be available..."
    aws ec2 wait vpc-available --vpc-ids ${VPC_A_ID} ${VPC_B_ID} || \
        error_exit "VPCs did not become available in time"
}

# Configure networking components
configure_networking() {
    log_info "Configuring networking components..."
    
    # Configure VPC A networking
    log_info "Configuring VPC A networking..."
    export SUBNET_A_ID=$(aws ec2 create-subnet \
        --vpc-id ${VPC_A_ID} \
        --cidr-block 10.0.1.0/24 \
        --availability-zone ${AWS_REGION}a \
        --query 'Subnet.SubnetId' --output text) || \
        error_exit "Failed to create subnet A"
    
    export IGW_A_ID=$(aws ec2 create-internet-gateway \
        --query 'InternetGateway.InternetGatewayId' --output text) || \
        error_exit "Failed to create internet gateway A"
    
    aws ec2 attach-internet-gateway \
        --internet-gateway-id ${IGW_A_ID} \
        --vpc-id ${VPC_A_ID} || \
        error_exit "Failed to attach internet gateway A"
    
    export RTB_A_ID=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=${VPC_A_ID}" \
        --query 'RouteTables[0].RouteTableId' --output text) || \
        error_exit "Failed to get route table A"
    
    aws ec2 create-route \
        --route-table-id ${RTB_A_ID} \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id ${IGW_A_ID} || \
        error_exit "Failed to create route A"
    
    # Configure VPC B networking
    log_info "Configuring VPC B networking..."
    export SUBNET_B_ID=$(aws ec2 create-subnet \
        --vpc-id ${VPC_B_ID} \
        --cidr-block 10.1.1.0/24 \
        --availability-zone ${AWS_REGION}a \
        --query 'Subnet.SubnetId' --output text) || \
        error_exit "Failed to create subnet B"
    
    export IGW_B_ID=$(aws ec2 create-internet-gateway \
        --query 'InternetGateway.InternetGatewayId' --output text) || \
        error_exit "Failed to create internet gateway B"
    
    aws ec2 attach-internet-gateway \
        --internet-gateway-id ${IGW_B_ID} \
        --vpc-id ${VPC_B_ID} || \
        error_exit "Failed to attach internet gateway B"
    
    export RTB_B_ID=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=${VPC_B_ID}" \
        --query 'RouteTables[0].RouteTableId' --output text) || \
        error_exit "Failed to get route table B"
    
    aws ec2 create-route \
        --route-table-id ${RTB_B_ID} \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id ${IGW_B_ID} || \
        error_exit "Failed to create route B"
    
    log_success "Network infrastructure configured"
}

# Create security groups
create_security_groups() {
    log_info "Creating security groups..."
    
    # Get VPC Lattice managed prefix list
    local lattice_prefix_list=$(aws ec2 describe-managed-prefix-lists \
        --filters "Name=prefix-list-name,Values=com.amazonaws.vpce.${AWS_REGION}.vpce-svc*" \
        --query 'PrefixLists[?contains(PrefixListName, `vpc-lattice`)].PrefixListId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$lattice_prefix_list" ]]; then
        log_warning "VPC Lattice managed prefix list not found, using broader CIDR for health checks"
        lattice_prefix_list="169.254.171.0/24"  # VPC Lattice IP range
    fi
    
    # Create security group for VPC A
    log_info "Creating security group for VPC A..."
    export SG_A_ID=$(aws ec2 create-security-group \
        --group-name "k8s-cluster-a-${RANDOM_SUFFIX}" \
        --description "Security group for Kubernetes cluster A" \
        --vpc-id ${VPC_A_ID} \
        --query 'GroupId' --output text) || \
        error_exit "Failed to create security group A"
    
    # Configure security group A rules
    aws ec2 authorize-security-group-ingress \
        --group-id ${SG_A_ID} \
        --protocol -1 \
        --source-group ${SG_A_ID} || \
        error_exit "Failed to configure security group A self-reference"
    
    aws ec2 authorize-security-group-ingress \
        --group-id ${SG_A_ID} \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 || \
        error_exit "Failed to configure SSH access for security group A"
    
    # Add VPC Lattice health check rule for port 8080
    if [[ "$lattice_prefix_list" == pl-* ]]; then
        aws ec2 authorize-security-group-ingress \
            --group-id ${SG_A_ID} \
            --protocol tcp \
            --port 8080 \
            --source-prefix-list-id ${lattice_prefix_list} || \
            log_warning "Failed to add VPC Lattice prefix list rule for security group A"
    else
        aws ec2 authorize-security-group-ingress \
            --group-id ${SG_A_ID} \
            --protocol tcp \
            --port 8080 \
            --cidr ${lattice_prefix_list} || \
            log_warning "Failed to add VPC Lattice CIDR rule for security group A"
    fi
    
    # Create security group for VPC B
    log_info "Creating security group for VPC B..."
    export SG_B_ID=$(aws ec2 create-security-group \
        --group-name "k8s-cluster-b-${RANDOM_SUFFIX}" \
        --description "Security group for Kubernetes cluster B" \
        --vpc-id ${VPC_B_ID} \
        --query 'GroupId' --output text) || \
        error_exit "Failed to create security group B"
    
    # Configure security group B rules
    aws ec2 authorize-security-group-ingress \
        --group-id ${SG_B_ID} \
        --protocol -1 \
        --source-group ${SG_B_ID} || \
        error_exit "Failed to configure security group B self-reference"
    
    aws ec2 authorize-security-group-ingress \
        --group-id ${SG_B_ID} \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 || \
        error_exit "Failed to configure SSH access for security group B"
    
    # Add VPC Lattice health check rule for port 9090
    if [[ "$lattice_prefix_list" == pl-* ]]; then
        aws ec2 authorize-security-group-ingress \
            --group-id ${SG_B_ID} \
            --protocol tcp \
            --port 9090 \
            --source-prefix-list-id ${lattice_prefix_list} || \
            log_warning "Failed to add VPC Lattice prefix list rule for security group B"
    else
        aws ec2 authorize-security-group-ingress \
            --group-id ${SG_B_ID} \
            --protocol tcp \
            --port 9090 \
            --cidr ${lattice_prefix_list} || \
            log_warning "Failed to add VPC Lattice CIDR rule for security group B"
    fi
    
    log_success "Security groups created: ${SG_A_ID}, ${SG_B_ID}"
}

# Launch EC2 instances
launch_ec2_instances() {
    log_info "Launching EC2 instances for Kubernetes clusters..."
    
    # Get latest Amazon Linux 2 AMI
    local amazon_linux_ami=$(aws ec2 describe-images \
        --owners amazon \
        --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
                "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text) || \
        error_exit "Failed to get Amazon Linux 2 AMI"
    
    log_info "Using AMI: ${amazon_linux_ami}"
    
    # Create user data script for Kubernetes installation
    local user_data=$(cat << 'EOF'
#!/bin/bash
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Install Kubernetes components using new repository
cat <<REPO > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
REPO

yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable kubelet

# Signal completion
/opt/aws/bin/cfn-signal -e $? --stack ${AWS::StackName} --resource AutoScalingGroup --region ${AWS::Region} || echo "CFN signal not available"
EOF
)
    
    # Launch instance A
    log_info "Launching Kubernetes cluster A instance..."
    export INSTANCE_A_ID=$(aws ec2 run-instances \
        --image-id ${amazon_linux_ami} \
        --instance-type t3.medium \
        --key-name "${KEY_PAIR_NAME}" \
        --security-group-ids ${SG_A_ID} \
        --subnet-id ${SUBNET_A_ID} \
        --associate-public-ip-address \
        --user-data "${user_data}" \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=k8s-cluster-a}]' \
        --query 'Instances[0].InstanceId' --output text) || \
        error_exit "Failed to launch instance A"
    
    # Launch instance B
    log_info "Launching Kubernetes cluster B instance..."
    export INSTANCE_B_ID=$(aws ec2 run-instances \
        --image-id ${amazon_linux_ami} \
        --instance-type t3.medium \
        --key-name "${KEY_PAIR_NAME}" \
        --security-group-ids ${SG_B_ID} \
        --subnet-id ${SUBNET_B_ID} \
        --associate-public-ip-address \
        --user-data "${user_data}" \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=k8s-cluster-b}]' \
        --query 'Instances[0].InstanceId' --output text) || \
        error_exit "Failed to launch instance B"
    
    # Wait for instances to be running
    log_info "Waiting for instances to be running..."
    aws ec2 wait instance-running --instance-ids ${INSTANCE_A_ID} ${INSTANCE_B_ID} || \
        error_exit "Instances did not start in time"
    
    log_success "EC2 instances launched: ${INSTANCE_A_ID}, ${INSTANCE_B_ID}"
}

# Create VPC Lattice service network
create_service_network() {
    log_info "Creating VPC Lattice service network..."
    
    export SERVICE_NETWORK_ID=$(aws vpc-lattice create-service-network \
        --name ${SERVICE_NETWORK_NAME} \
        --query 'id' --output text) || \
        error_exit "Failed to create VPC Lattice service network"
    
    # Wait for service network to be active
    log_info "Waiting for service network to be active..."
    local max_attempts=30
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local status=$(aws vpc-lattice get-service-network \
            --service-network-identifier ${SERVICE_NETWORK_ID} \
            --query 'status' --output text 2>/dev/null || echo "")
        
        if [[ "$status" == "ACTIVE" ]]; then
            break
        fi
        
        log_info "Service network status: ${status:-UNKNOWN}, waiting... (attempt ${attempt}/${max_attempts})"
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        error_exit "Service network did not become active in time"
    fi
    
    # Associate VPCs with service network
    log_info "Associating VPCs with service network..."
    aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --vpc-identifier ${VPC_A_ID} \
        --security-group-ids ${SG_A_ID} || \
        error_exit "Failed to associate VPC A with service network"
    
    aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --vpc-identifier ${VPC_B_ID} \
        --security-group-ids ${SG_B_ID} || \
        error_exit "Failed to associate VPC B with service network"
    
    log_success "VPC Lattice service network created: ${SERVICE_NETWORK_ID}"
}

# Create target groups
create_target_groups() {
    log_info "Creating VPC Lattice target groups..."
    
    # Create frontend target group
    export FRONTEND_TG_ID=$(aws vpc-lattice create-target-group \
        --name "frontend-tg-${RANDOM_SUFFIX}" \
        --type IP \
        --protocol HTTP \
        --port 8080 \
        --vpc-identifier ${VPC_A_ID} \
        --query 'id' --output text) || \
        error_exit "Failed to create frontend target group"
    
    # Create backend target group
    export BACKEND_TG_ID=$(aws vpc-lattice create-target-group \
        --name "backend-tg-${RANDOM_SUFFIX}" \
        --type IP \
        --protocol HTTP \
        --port 9090 \
        --vpc-identifier ${VPC_B_ID} \
        --query 'id' --output text) || \
        error_exit "Failed to create backend target group"
    
    # Configure health checks
    log_info "Configuring health checks for target groups..."
    aws vpc-lattice modify-target-group \
        --target-group-identifier ${FRONTEND_TG_ID} \
        --health-check-enabled \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --health-check-protocol HTTP \
        --health-check-port 8080 \
        --health-check-path "/health" || \
        error_exit "Failed to configure frontend target group health checks"
    
    aws vpc-lattice modify-target-group \
        --target-group-identifier ${BACKEND_TG_ID} \
        --health-check-enabled \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --health-check-protocol HTTP \
        --health-check-port 9090 \
        --health-check-path "/health" || \
        error_exit "Failed to configure backend target group health checks"
    
    log_success "Target groups created: ${FRONTEND_TG_ID}, ${BACKEND_TG_ID}"
}

# Create VPC Lattice services
create_lattice_services() {
    log_info "Creating VPC Lattice services..."
    
    # Create frontend service
    export FRONTEND_SERVICE_ID=$(aws vpc-lattice create-service \
        --name ${FRONTEND_SERVICE_NAME} \
        --query 'id' --output text) || \
        error_exit "Failed to create frontend service"
    
    # Create backend service
    export BACKEND_SERVICE_ID=$(aws vpc-lattice create-service \
        --name ${BACKEND_SERVICE_NAME} \
        --query 'id' --output text) || \
        error_exit "Failed to create backend service"
    
    # Create listeners
    log_info "Creating service listeners..."
    aws vpc-lattice create-listener \
        --service-identifier ${FRONTEND_SERVICE_ID} \
        --name "frontend-listener" \
        --protocol HTTP \
        --port 80 \
        --default-action '{
            "forward": {
                "targetGroups": [{
                    "targetGroupIdentifier": "'${FRONTEND_TG_ID}'",
                    "weight": 100
                }]
            }
        }' || error_exit "Failed to create frontend listener"
    
    aws vpc-lattice create-listener \
        --service-identifier ${BACKEND_SERVICE_ID} \
        --name "backend-listener" \
        --protocol HTTP \
        --port 80 \
        --default-action '{
            "forward": {
                "targetGroups": [{
                    "targetGroupIdentifier": "'${BACKEND_TG_ID}'",
                    "weight": 100
                }]
            }
        }' || error_exit "Failed to create backend listener"
    
    log_success "VPC Lattice services created: ${FRONTEND_SERVICE_ID}, ${BACKEND_SERVICE_ID}"
}

# Associate services with service network
associate_services() {
    log_info "Associating services with service network..."
    
    aws vpc-lattice create-service-network-service-association \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --service-identifier ${FRONTEND_SERVICE_ID} || \
        error_exit "Failed to associate frontend service with network"
    
    aws vpc-lattice create-service-network-service-association \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --service-identifier ${BACKEND_SERVICE_ID} || \
        error_exit "Failed to associate backend service with network"
    
    log_success "Services associated with service network"
}

# Register targets
register_targets() {
    log_info "Registering instance IPs as targets..."
    
    # Get instance private IPs
    export INSTANCE_A_IP=$(aws ec2 describe-instances \
        --instance-ids ${INSTANCE_A_ID} \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text) || \
        error_exit "Failed to get instance A IP"
    
    export INSTANCE_B_IP=$(aws ec2 describe-instances \
        --instance-ids ${INSTANCE_B_ID} \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text) || \
        error_exit "Failed to get instance B IP"
    
    # Register targets
    aws vpc-lattice register-targets \
        --target-group-identifier ${FRONTEND_TG_ID} \
        --targets id=${INSTANCE_A_IP},port=8080 || \
        error_exit "Failed to register frontend target"
    
    aws vpc-lattice register-targets \
        --target-group-identifier ${BACKEND_TG_ID} \
        --targets id=${INSTANCE_B_IP},port=9090 || \
        error_exit "Failed to register backend target"
    
    log_success "Targets registered - Frontend: ${INSTANCE_A_IP}, Backend: ${INSTANCE_B_IP}"
}

# Configure CloudWatch monitoring
configure_monitoring() {
    log_info "Configuring CloudWatch monitoring..."
    
    # Create log group
    aws logs create-log-group \
        --log-group-name "/aws/vpc-lattice/${SERVICE_NETWORK_NAME}" || \
        log_warning "Failed to create CloudWatch log group (may already exist)"
    
    # Enable access logging
    aws vpc-lattice put-access-log-subscription \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --destination-arn "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/vpc-lattice/${SERVICE_NETWORK_NAME}" || \
        log_warning "Failed to enable access logging"
    
    # Create CloudWatch dashboard
    local dashboard_body=$(cat << EOF
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/VPCLattice", "ActiveConnectionCount", "ServiceNetwork", "${SERVICE_NETWORK_ID}"],
                    ["AWS/VPCLattice", "NewConnectionCount", "ServiceNetwork", "${SERVICE_NETWORK_ID}"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "VPC Lattice Service Network Connections"
            }
        }
    ]
}
EOF
)
    
    aws cloudwatch put-dashboard \
        --dashboard-name "VPC-Lattice-K8s-Mesh-${RANDOM_SUFFIX}" \
        --dashboard-body "${dashboard_body}" || \
        log_warning "Failed to create CloudWatch dashboard"
    
    log_success "CloudWatch monitoring configured"
}

# Save deployment state
save_deployment_state() {
    log_info "Saving deployment state..."
    
    cat > .deployment_state << EOF
# VPC Lattice Kubernetes Integration Deployment State
# Generated on $(date)
RANDOM_SUFFIX=${RANDOM_SUFFIX}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
VPC_A_ID=${VPC_A_ID}
VPC_B_ID=${VPC_B_ID}
SUBNET_A_ID=${SUBNET_A_ID}
SUBNET_B_ID=${SUBNET_B_ID}
IGW_A_ID=${IGW_A_ID}
IGW_B_ID=${IGW_B_ID}
RTB_A_ID=${RTB_A_ID}
RTB_B_ID=${RTB_B_ID}
SG_A_ID=${SG_A_ID}
SG_B_ID=${SG_B_ID}
INSTANCE_A_ID=${INSTANCE_A_ID}
INSTANCE_B_ID=${INSTANCE_B_ID}
INSTANCE_A_IP=${INSTANCE_A_IP}
INSTANCE_B_IP=${INSTANCE_B_IP}
SERVICE_NETWORK_ID=${SERVICE_NETWORK_ID}
FRONTEND_TG_ID=${FRONTEND_TG_ID}
BACKEND_TG_ID=${BACKEND_TG_ID}
FRONTEND_SERVICE_ID=${FRONTEND_SERVICE_ID}
BACKEND_SERVICE_ID=${BACKEND_SERVICE_ID}
KEY_PAIR_NAME=${KEY_PAIR_NAME}
SERVICE_NETWORK_NAME=${SERVICE_NETWORK_NAME}
FRONTEND_SERVICE_NAME=${FRONTEND_SERVICE_NAME}
BACKEND_SERVICE_NAME=${BACKEND_SERVICE_NAME}
VPC_A_NAME=${VPC_A_NAME}
VPC_B_NAME=${VPC_B_NAME}
EOF
    
    log_success "Deployment state saved to .deployment_state"
}

# Print deployment summary
print_deployment_summary() {
    log_success "=== Deployment Complete ==="
    echo
    log_info "Resource Summary:"
    echo "  • VPC A: ${VPC_A_ID} (${VPC_A_NAME})"
    echo "  • VPC B: ${VPC_B_ID} (${VPC_B_NAME})"
    echo "  • Service Network: ${SERVICE_NETWORK_ID}"
    echo "  • Frontend Service: ${FRONTEND_SERVICE_ID}"
    echo "  • Backend Service: ${BACKEND_SERVICE_ID}"
    echo "  • Instance A (Frontend): ${INSTANCE_A_ID} (${INSTANCE_A_IP})"
    echo "  • Instance B (Backend): ${INSTANCE_B_ID} (${INSTANCE_B_IP})"
    echo
    
    # Get service network domain
    local service_network_domain=$(aws vpc-lattice get-service-network \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --query 'dnsEntry.domainName' --output text 2>/dev/null || echo "Not available")
    
    if [[ "$service_network_domain" != "Not available" ]]; then
        log_info "Service Discovery Endpoints:"
        echo "  • Frontend: ${FRONTEND_SERVICE_NAME}.${service_network_domain}"
        echo "  • Backend: ${BACKEND_SERVICE_NAME}.${service_network_domain}"
        echo
    fi
    
    log_info "CloudWatch Dashboard: VPC-Lattice-K8s-Mesh-${RANDOM_SUFFIX}"
    log_info "SSH Key: k8s-lattice-key.pem"
    echo
    log_warning "Note: This deployment creates resources that incur costs."
    log_warning "Run './destroy.sh' to clean up when finished testing."
    echo
    log_success "Deployment completed successfully!"
}

# Main execution
main() {
    log_info "Starting VPC Lattice Kubernetes Integration deployment..."
    echo
    
    check_prerequisites
    initialize_environment
    create_ssh_key
    create_vpc_infrastructure
    configure_networking
    create_security_groups
    launch_ec2_instances
    create_service_network
    create_target_groups
    create_lattice_services
    associate_services
    register_targets
    configure_monitoring
    save_deployment_state
    print_deployment_summary
}

# Execute main function
main "$@"