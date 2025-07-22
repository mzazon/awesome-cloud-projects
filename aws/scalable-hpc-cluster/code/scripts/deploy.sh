#!/bin/bash

# AWS ParallelCluster HPC Deployment Script
# This script deploys a high-performance computing cluster using AWS ParallelCluster
# Based on the "Scalable HPC Cluster with Auto-Scaling" recipe

set -e
set -o pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
CONFIG_FILE="${SCRIPT_DIR}/cluster-config.yaml"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    exit 1
}

# Success message
success() {
    log "${GREEN}SUCCESS: ${1}${NC}"
}

# Warning message
warning() {
    log "${YELLOW}WARNING: ${1}${NC}"
}

# Info message
info() {
    log "${BLUE}INFO: ${1}${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    info "Validating prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set up credentials"
    fi
    
    # Check Python
    if ! command_exists python3; then
        error_exit "Python 3 is not installed. Please install Python 3.8+"
    fi
    
    # Check pip
    if ! command_exists pip3; then
        error_exit "pip3 is not installed. Please install pip for Python 3"
    fi
    
    # Check if ParallelCluster CLI is installed
    if ! command_exists pcluster; then
        info "ParallelCluster CLI not found. Installing..."
        pip3 install --user aws-parallelcluster
        export PATH="$PATH:$(python3 -m site --user-base)/bin"
        
        if ! command_exists pcluster; then
            error_exit "Failed to install ParallelCluster CLI. Please install manually with: pip3 install aws-parallelcluster"
        fi
    fi
    
    success "Prerequisites validation completed"
}

# Initialize environment variables
initialize_environment() {
    info "Initializing environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured. Using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        error_exit "Failed to get AWS account ID"
    fi
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    export CLUSTER_NAME="hpc-cluster-${RANDOM_SUFFIX}"
    export VPC_NAME="hpc-vpc-${RANDOM_SUFFIX}"
    export KEYPAIR_NAME="hpc-keypair-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="hpc-data-${RANDOM_SUFFIX}-${AWS_ACCOUNT_ID}"
    
    # Store environment variables for cleanup
    cat > "${SCRIPT_DIR}/deployment-vars.env" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
CLUSTER_NAME=${CLUSTER_NAME}
VPC_NAME=${VPC_NAME}
KEYPAIR_NAME=${KEYPAIR_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
EOF
    
    info "Environment variables initialized:"
    info "  AWS Region: ${AWS_REGION}"
    info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    info "  Cluster Name: ${CLUSTER_NAME}"
    info "  VPC Name: ${VPC_NAME}"
    info "  Key Pair Name: ${KEYPAIR_NAME}"
    info "  S3 Bucket Name: ${S3_BUCKET_NAME}"
}

# Create SSH key pair
create_keypair() {
    info "Creating SSH key pair..."
    
    # Check if key pair already exists
    if aws ec2 describe-key-pairs --key-names "${KEYPAIR_NAME}" >/dev/null 2>&1; then
        warning "Key pair ${KEYPAIR_NAME} already exists. Skipping creation."
        return 0
    fi
    
    # Create SSH directory if it doesn't exist
    mkdir -p ~/.ssh
    
    # Create key pair
    aws ec2 create-key-pair \
        --key-name "${KEYPAIR_NAME}" \
        --query 'KeyMaterial' \
        --output text > ~/.ssh/${KEYPAIR_NAME}.pem || error_exit "Failed to create key pair"
    
    chmod 600 ~/.ssh/${KEYPAIR_NAME}.pem
    
    success "SSH key pair created: ~/.ssh/${KEYPAIR_NAME}.pem"
}

# Create VPC and networking infrastructure
create_vpc() {
    info "Creating VPC and networking infrastructure..."
    
    # Create VPC
    VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}},{Key=Project,Value=HPC-ParallelCluster}]" \
        --query 'Vpc.VpcId' --output text) || error_exit "Failed to create VPC"
    
    info "Created VPC: ${VPC_ID}"
    
    # Enable DNS hostnames
    aws ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-hostnames
    
    # Create public subnet
    PUBLIC_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-public},{Key=Project,Value=HPC-ParallelCluster}]" \
        --query 'Subnet.SubnetId' --output text) || error_exit "Failed to create public subnet"
    
    info "Created public subnet: ${PUBLIC_SUBNET_ID}"
    
    # Create private subnet
    PRIVATE_SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.2.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-private},{Key=Project,Value=HPC-ParallelCluster}]" \
        --query 'Subnet.SubnetId' --output text) || error_exit "Failed to create private subnet"
    
    info "Created private subnet: ${PRIVATE_SUBNET_ID}"
    
    # Create internet gateway
    IGW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw},{Key=Project,Value=HPC-ParallelCluster}]" \
        --query 'InternetGateway.InternetGatewayId' --output text) || error_exit "Failed to create internet gateway"
    
    info "Created internet gateway: ${IGW_ID}"
    
    # Attach internet gateway to VPC
    aws ec2 attach-internet-gateway \
        --internet-gateway-id "${IGW_ID}" \
        --vpc-id "${VPC_ID}" || error_exit "Failed to attach internet gateway"
    
    # Store network IDs for later use
    cat >> "${SCRIPT_DIR}/deployment-vars.env" << EOF
VPC_ID=${VPC_ID}
PUBLIC_SUBNET_ID=${PUBLIC_SUBNET_ID}
PRIVATE_SUBNET_ID=${PRIVATE_SUBNET_ID}
IGW_ID=${IGW_ID}
EOF
    
    success "VPC and networking infrastructure created"
}

# Configure NAT Gateway and routing
configure_nat_routing() {
    info "Configuring NAT Gateway and routing..."
    
    # Source the environment variables
    source "${SCRIPT_DIR}/deployment-vars.env"
    
    # Allocate Elastic IP for NAT Gateway
    NAT_ALLOCATION_ID=$(aws ec2 allocate-address \
        --domain vpc \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${VPC_NAME}-nat-eip},{Key=Project,Value=HPC-ParallelCluster}]" \
        --query 'AllocationId' --output text) || error_exit "Failed to allocate Elastic IP"
    
    info "Allocated Elastic IP: ${NAT_ALLOCATION_ID}"
    
    # Create NAT Gateway
    NAT_GW_ID=$(aws ec2 create-nat-gateway \
        --subnet-id "${PUBLIC_SUBNET_ID}" \
        --allocation-id "${NAT_ALLOCATION_ID}" \
        --tag-specifications "ResourceType=nat-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-nat},{Key=Project,Value=HPC-ParallelCluster}]" \
        --query 'NatGateway.NatGatewayId' --output text) || error_exit "Failed to create NAT Gateway"
    
    info "Created NAT Gateway: ${NAT_GW_ID}"
    
    # Wait for NAT Gateway to be available
    info "Waiting for NAT Gateway to be available..."
    aws ec2 wait nat-gateway-available --nat-gateway-ids "${NAT_GW_ID}" || error_exit "NAT Gateway failed to become available"
    
    # Get main route table ID
    PUBLIC_RT_ID=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=${VPC_ID}" "Name=association.main,Values=true" \
        --query 'RouteTables[0].RouteTableId' --output text) || error_exit "Failed to get main route table"
    
    # Add route to internet gateway in main route table
    aws ec2 create-route \
        --route-table-id "${PUBLIC_RT_ID}" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "${IGW_ID}" >/dev/null 2>&1 || warning "Route to internet gateway may already exist"
    
    # Associate public subnet with main route table
    aws ec2 associate-route-table \
        --route-table-id "${PUBLIC_RT_ID}" \
        --subnet-id "${PUBLIC_SUBNET_ID}" >/dev/null 2>&1 || warning "Public subnet may already be associated with main route table"
    
    # Create private route table
    PRIVATE_RT_ID=$(aws ec2 create-route-table \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-private},{Key=Project,Value=HPC-ParallelCluster}]" \
        --query 'RouteTable.RouteTableId' --output text) || error_exit "Failed to create private route table"
    
    # Add route to NAT Gateway in private route table
    aws ec2 create-route \
        --route-table-id "${PRIVATE_RT_ID}" \
        --destination-cidr-block 0.0.0.0/0 \
        --nat-gateway-id "${NAT_GW_ID}" || error_exit "Failed to create route to NAT Gateway"
    
    # Associate private subnet with private route table
    aws ec2 associate-route-table \
        --route-table-id "${PRIVATE_RT_ID}" \
        --subnet-id "${PRIVATE_SUBNET_ID}" || error_exit "Failed to associate private subnet with route table"
    
    # Store additional network IDs
    cat >> "${SCRIPT_DIR}/deployment-vars.env" << EOF
NAT_ALLOCATION_ID=${NAT_ALLOCATION_ID}
NAT_GW_ID=${NAT_GW_ID}
PUBLIC_RT_ID=${PUBLIC_RT_ID}
PRIVATE_RT_ID=${PRIVATE_RT_ID}
EOF
    
    success "NAT Gateway and routing configured"
}

# Create S3 bucket for data storage
create_s3_bucket() {
    info "Creating S3 bucket for data storage..."
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" >/dev/null 2>&1; then
        warning "S3 bucket ${S3_BUCKET_NAME} already exists. Skipping creation."
        return 0
    fi
    
    # Create S3 bucket
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "${S3_BUCKET_NAME}" || error_exit "Failed to create S3 bucket"
    else
        aws s3api create-bucket \
            --bucket "${S3_BUCKET_NAME}" \
            --create-bucket-configuration LocationConstraint="${AWS_REGION}" || error_exit "Failed to create S3 bucket"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${S3_BUCKET_NAME}" \
        --versioning-configuration Status=Enabled || error_exit "Failed to enable bucket versioning"
    
    # Create folder structure
    echo "Sample HPC input data" > /tmp/input.txt
    aws s3 cp /tmp/input.txt "s3://${S3_BUCKET_NAME}/input/" || error_exit "Failed to upload sample input data"
    
    # Create sample job script
    cat > /tmp/sample_job.sh << 'EOF'
#!/bin/bash
#SBATCH --job-name=hpc-test
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=8
#SBATCH --time=00:10:00
#SBATCH --output=output_%j.log

module load openmpi
mpirun hostname
EOF
    
    aws s3 cp /tmp/sample_job.sh "s3://${S3_BUCKET_NAME}/jobs/" || error_exit "Failed to upload sample job script"
    
    # Cleanup temp files
    rm -f /tmp/input.txt /tmp/sample_job.sh
    
    success "S3 bucket created: ${S3_BUCKET_NAME}"
}

# Create ParallelCluster configuration
create_cluster_config() {
    info "Creating ParallelCluster configuration..."
    
    # Source the environment variables
    source "${SCRIPT_DIR}/deployment-vars.env"
    
    # Create cluster configuration
    cat > "${CONFIG_FILE}" << EOF
Region: ${AWS_REGION}
Image:
  Os: alinux2
HeadNode:
  InstanceType: m5.large
  Networking:
    SubnetId: ${PUBLIC_SUBNET_ID}
  Ssh:
    KeyName: ${KEYPAIR_NAME}
  LocalStorage:
    RootVolume:
      Size: 50
      VolumeType: gp3
      Encrypted: true
  Iam:
    AdditionalIamPolicies:
      - Policy: arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
Scheduling:
  Scheduler: slurm
  SlurmSettings:
    ScaledownIdletime: 5
    QueueUpdateStrategy: TERMINATE
  SlurmQueues:
    - Name: compute
      ComputeResources:
        - Name: compute-nodes
          InstanceType: c5n.large
          MinCount: 0
          MaxCount: 10
          DisableSimultaneousMultithreading: true
          Efa:
            Enabled: true
          Iam:
            AdditionalIamPolicies:
              - Policy: arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
      Networking:
        SubnetIds:
          - ${PRIVATE_SUBNET_ID}
      ComputeSettings:
        LocalStorage:
          RootVolume:
            Size: 50
            VolumeType: gp3
            Encrypted: true
SharedStorage:
  - MountDir: /shared
    Name: shared-storage
    StorageType: Ebs
    EbsSettings:
      Size: 100
      VolumeType: gp3
      Encrypted: true
  - MountDir: /fsx
    Name: fsx-storage
    StorageType: FsxLustre
    FsxLustreSettings:
      StorageCapacity: 1200
      DeploymentType: SCRATCH_2
      ImportPath: s3://${S3_BUCKET_NAME}/
      ExportPath: s3://${S3_BUCKET_NAME}/output/
Monitoring:
  CloudWatch:
    Enabled: true
    DashboardName: ${CLUSTER_NAME}-dashboard
Tags:
  - Key: Project
    Value: HPC-ParallelCluster
  - Key: Environment
    Value: Development
EOF
    
    success "ParallelCluster configuration created: ${CONFIG_FILE}"
}

# Deploy ParallelCluster
deploy_cluster() {
    info "Deploying ParallelCluster..."
    
    # Validate configuration
    pcluster validate-cluster-configuration \
        --cluster-configuration "${CONFIG_FILE}" || error_exit "Cluster configuration validation failed"
    
    success "Cluster configuration validated"
    
    # Create the cluster
    info "Creating HPC cluster (this may take 10-15 minutes)..."
    pcluster create-cluster \
        --cluster-name "${CLUSTER_NAME}" \
        --cluster-configuration "${CONFIG_FILE}" \
        --rollback-on-failure false || error_exit "Failed to create cluster"
    
    # Wait for cluster creation
    info "Waiting for cluster creation to complete..."
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local status=$(pcluster describe-cluster --cluster-name "${CLUSTER_NAME}" --query 'clusterStatus' --output text 2>/dev/null)
        
        case "$status" in
            "CREATE_COMPLETE")
                success "Cluster created successfully"
                break
                ;;
            "CREATE_FAILED")
                error_exit "Cluster creation failed"
                ;;
            "CREATE_IN_PROGRESS")
                info "Cluster creation in progress... (attempt $((attempt + 1))/${max_attempts})"
                sleep 30
                ;;
            *)
                warning "Unknown cluster status: $status"
                sleep 30
                ;;
        esac
        
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        error_exit "Cluster creation timed out"
    fi
    
    # Get head node IP
    HEAD_NODE_IP=$(pcluster describe-cluster \
        --cluster-name "${CLUSTER_NAME}" \
        --query 'headNode.publicIpAddress' --output text) || error_exit "Failed to get head node IP"
    
    echo "HEAD_NODE_IP=${HEAD_NODE_IP}" >> "${SCRIPT_DIR}/deployment-vars.env"
    
    success "HPC cluster deployed successfully"
    info "Head node IP: ${HEAD_NODE_IP}"
}

# Create monitoring dashboard
create_monitoring() {
    info "Creating CloudWatch monitoring dashboard..."
    
    # Create dashboard configuration
    cat > /tmp/dashboard-config.json << EOF
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
                    [ "AWS/EC2", "CPUUtilization", "ClusterName", "${CLUSTER_NAME}" ],
                    [ ".", "NetworkIn", ".", "." ],
                    [ ".", "NetworkOut", ".", "." ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "HPC Cluster Performance Metrics",
                "yAxis": {
                    "left": {
                        "min": 0,
                        "max": 100
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/EC2", "NetworkPacketsIn", "ClusterName", "${CLUSTER_NAME}" ],
                    [ ".", "NetworkPacketsOut", ".", "." ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${AWS_REGION}",
                "title": "Network Packets",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        }
    ]
}
EOF
    
    # Create dashboard
    aws cloudwatch put-dashboard \
        --dashboard-name "${CLUSTER_NAME}-performance" \
        --dashboard-body file:///tmp/dashboard-config.json || error_exit "Failed to create CloudWatch dashboard"
    
    # Create CloudWatch alarms
    aws cloudwatch put-metric-alarm \
        --alarm-name "${CLUSTER_NAME}-high-cpu" \
        --alarm-description "High CPU utilization on HPC cluster" \
        --metric-name CPUUtilization \
        --namespace AWS/EC2 \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --treat-missing-data notBreaching || error_exit "Failed to create CPU alarm"
    
    # Cleanup temp file
    rm -f /tmp/dashboard-config.json
    
    success "CloudWatch monitoring dashboard and alarms created"
}

# Print deployment summary
print_summary() {
    source "${SCRIPT_DIR}/deployment-vars.env"
    
    info "=== DEPLOYMENT SUMMARY ==="
    info "Cluster Name: ${CLUSTER_NAME}"
    info "AWS Region: ${AWS_REGION}"
    info "VPC ID: ${VPC_ID}"
    info "Head Node IP: ${HEAD_NODE_IP}"
    info "S3 Bucket: ${S3_BUCKET_NAME}"
    info "SSH Key: ~/.ssh/${KEYPAIR_NAME}.pem"
    info ""
    info "To connect to the head node:"
    info "  ssh -i ~/.ssh/${KEYPAIR_NAME}.pem ec2-user@${HEAD_NODE_IP}"
    info ""
    info "To submit a test job:"
    info "  sbatch --nodes=2 --ntasks=8 --time=00:05:00 --wrap='hostname'"
    info ""
    info "To monitor the cluster:"
    info "  AWS Console -> CloudWatch -> Dashboards -> ${CLUSTER_NAME}-performance"
    info ""
    info "To clean up resources:"
    info "  ./destroy.sh"
    info "=========================="
}

# Main deployment function
main() {
    info "Starting AWS ParallelCluster HPC deployment..."
    echo "Deployment started at $(date)" > "${LOG_FILE}"
    
    validate_prerequisites
    initialize_environment
    create_keypair
    create_vpc
    configure_nat_routing
    create_s3_bucket
    create_cluster_config
    deploy_cluster
    create_monitoring
    print_summary
    
    success "Deployment completed successfully at $(date)"
    echo "Deployment completed at $(date)" >> "${LOG_FILE}"
}

# Run main function
main "$@"