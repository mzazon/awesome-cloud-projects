#!/bin/bash

# Multi-Cluster EKS Deployments with Cross-Region Networking - Deployment Script
# This script deploys a multi-cluster EKS architecture spanning multiple AWS regions,
# connected through AWS Transit Gateway with cross-region peering and AWS VPC Lattice

set -euo pipefail

# Colors for output
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

# Error handling
error_exit() {
    log_error "$1"
    echo "Deployment failed. Check the logs above for details."
    exit 1
}

# Trap for cleanup on exit
cleanup_on_error() {
    log_error "Script interrupted. Some resources may have been created."
    log_warning "Run the destroy.sh script to clean up any created resources."
    exit 1
}

trap cleanup_on_error INT TERM

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        error_exit "kubectl is not installed. Please install kubectl version 1.28+."
    fi
    
    # Check if eksctl is installed
    if ! command -v eksctl &> /dev/null; then
        error_exit "eksctl is not installed. Please install eksctl version 0.140+."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set up IAM roles."
    fi
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        error_exit "Unable to determine AWS account ID."
    fi
    
    log_success "Prerequisites check completed. AWS Account ID: $AWS_ACCOUNT_ID"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set regions
    export PRIMARY_REGION=${PRIMARY_REGION:-us-east-1}
    export SECONDARY_REGION=${SECONDARY_REGION:-us-west-2}
    export AWS_ACCOUNT_ID
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
    
    # Set cluster and resource names
    export PRIMARY_CLUSTER_NAME="eks-primary-${RANDOM_SUFFIX}"
    export SECONDARY_CLUSTER_NAME="eks-secondary-${RANDOM_SUFFIX}"
    export VPC_PRIMARY_NAME="vpc-primary-${RANDOM_SUFFIX}"
    export VPC_SECONDARY_NAME="vpc-secondary-${RANDOM_SUFFIX}"
    export TGW_PRIMARY_NAME="tgw-primary-${RANDOM_SUFFIX}"
    export TGW_SECONDARY_NAME="tgw-secondary-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > /tmp/eks-multi-cluster-env.sh << EOF
export PRIMARY_REGION=${PRIMARY_REGION}
export SECONDARY_REGION=${SECONDARY_REGION}
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
export PRIMARY_CLUSTER_NAME=${PRIMARY_CLUSTER_NAME}
export SECONDARY_CLUSTER_NAME=${SECONDARY_CLUSTER_NAME}
export VPC_PRIMARY_NAME=${VPC_PRIMARY_NAME}
export VPC_SECONDARY_NAME=${VPC_SECONDARY_NAME}
export TGW_PRIMARY_NAME=${TGW_PRIMARY_NAME}
export TGW_SECONDARY_NAME=${TGW_SECONDARY_NAME}
export RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables configured with suffix: $RANDOM_SUFFIX"
}

# Create IAM roles
create_iam_roles() {
    log "Creating IAM roles for EKS clusters..."
    
    # Create EKS cluster role
    if ! aws iam get-role --role-name "eks-cluster-role-${RANDOM_SUFFIX}" &>/dev/null; then
        aws iam create-role \
            --role-name "eks-cluster-role-${RANDOM_SUFFIX}" \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "eks.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }' > /dev/null
        
        aws iam attach-role-policy \
            --role-name "eks-cluster-role-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
    fi
    
    # Create EKS node group role
    if ! aws iam get-role --role-name "eks-nodegroup-role-${RANDOM_SUFFIX}" &>/dev/null; then
        aws iam create-role \
            --role-name "eks-nodegroup-role-${RANDOM_SUFFIX}" \
            --assume-role-policy-document '{
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
            }' > /dev/null
        
        # Attach required policies
        aws iam attach-role-policy \
            --role-name "eks-nodegroup-role-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        
        aws iam attach-role-policy \
            --role-name "eks-nodegroup-role-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        
        aws iam attach-role-policy \
            --role-name "eks-nodegroup-role-${RANDOM_SUFFIX}" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
    fi
    
    # Wait for role propagation
    sleep 10
    
    log_success "IAM roles created successfully"
}

# Create primary region infrastructure
create_primary_infrastructure() {
    log "Creating primary region VPC and Transit Gateway..."
    
    # Create VPC for primary region
    aws ec2 create-vpc \
        --cidr-block 10.1.0.0/16 \
        --tag-specifications \
        "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_PRIMARY_NAME}}]" \
        --region ${PRIMARY_REGION} > /dev/null
    
    # Get VPC ID
    PRIMARY_VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=${VPC_PRIMARY_NAME}" \
        --region ${PRIMARY_REGION} \
        --query 'Vpcs[0].VpcId' --output text)
    
    # Enable DNS hostnames and resolution
    aws ec2 modify-vpc-attribute \
        --vpc-id ${PRIMARY_VPC_ID} \
        --enable-dns-hostnames \
        --region ${PRIMARY_REGION}
    
    aws ec2 modify-vpc-attribute \
        --vpc-id ${PRIMARY_VPC_ID} \
        --enable-dns-support \
        --region ${PRIMARY_REGION}
    
    # Create Transit Gateway in primary region
    aws ec2 create-transit-gateway \
        --description "Primary region Transit Gateway" \
        --options AmazonSideAsn=64512,AutoAcceptSharedAttachments=enable,DefaultRouteTableAssociation=enable,DefaultRouteTablePropagation=enable \
        --tag-specifications \
        "ResourceType=transit-gateway,Tags=[{Key=Name,Value=${TGW_PRIMARY_NAME}}]" \
        --region ${PRIMARY_REGION} > /dev/null
    
    # Get Transit Gateway ID
    PRIMARY_TGW_ID=$(aws ec2 describe-transit-gateways \
        --filters "Name=tag:Name,Values=${TGW_PRIMARY_NAME}" \
        --region ${PRIMARY_REGION} \
        --query 'TransitGateways[0].TransitGatewayId' --output text)
    
    # Wait for Transit Gateway to be available
    log "Waiting for primary Transit Gateway to be available..."
    aws ec2 wait transit-gateway-available \
        --transit-gateway-ids ${PRIMARY_TGW_ID} \
        --region ${PRIMARY_REGION}
    
    # Create subnets
    create_subnets_primary
    
    # Configure networking
    configure_primary_networking
    
    echo "PRIMARY_VPC_ID=${PRIMARY_VPC_ID}" >> /tmp/eks-multi-cluster-env.sh
    echo "PRIMARY_TGW_ID=${PRIMARY_TGW_ID}" >> /tmp/eks-multi-cluster-env.sh
    
    log_success "Primary region infrastructure created"
}

# Create subnets in primary region
create_subnets_primary() {
    log "Creating subnets in primary region..."
    
    # Create public subnets
    aws ec2 create-subnet \
        --vpc-id ${PRIMARY_VPC_ID} \
        --cidr-block 10.1.1.0/24 \
        --availability-zone ${PRIMARY_REGION}a \
        --tag-specifications \
        "ResourceType=subnet,Tags=[{Key=Name,Value=primary-public-1},{Key=kubernetes.io/role/elb,Value=1}]" \
        --region ${PRIMARY_REGION} > /dev/null
    
    aws ec2 create-subnet \
        --vpc-id ${PRIMARY_VPC_ID} \
        --cidr-block 10.1.2.0/24 \
        --availability-zone ${PRIMARY_REGION}b \
        --tag-specifications \
        "ResourceType=subnet,Tags=[{Key=Name,Value=primary-public-2},{Key=kubernetes.io/role/elb,Value=1}]" \
        --region ${PRIMARY_REGION} > /dev/null
    
    # Create private subnets
    aws ec2 create-subnet \
        --vpc-id ${PRIMARY_VPC_ID} \
        --cidr-block 10.1.3.0/24 \
        --availability-zone ${PRIMARY_REGION}a \
        --tag-specifications \
        "ResourceType=subnet,Tags=[{Key=Name,Value=primary-private-1},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
        --region ${PRIMARY_REGION} > /dev/null
    
    aws ec2 create-subnet \
        --vpc-id ${PRIMARY_VPC_ID} \
        --cidr-block 10.1.4.0/24 \
        --availability-zone ${PRIMARY_REGION}b \
        --tag-specifications \
        "ResourceType=subnet,Tags=[{Key=Name,Value=primary-private-2},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
        --region ${PRIMARY_REGION} > /dev/null
    
    # Get subnet IDs
    PRIMARY_PUBLIC_SUBNET_1=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=primary-public-1" \
        --region ${PRIMARY_REGION} \
        --query 'Subnets[0].SubnetId' --output text)
    
    PRIMARY_PUBLIC_SUBNET_2=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=primary-public-2" \
        --region ${PRIMARY_REGION} \
        --query 'Subnets[0].SubnetId' --output text)
    
    PRIMARY_PRIVATE_SUBNET_1=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=primary-private-1" \
        --region ${PRIMARY_REGION} \
        --query 'Subnets[0].SubnetId' --output text)
    
    PRIMARY_PRIVATE_SUBNET_2=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=primary-private-2" \
        --region ${PRIMARY_REGION} \
        --query 'Subnets[0].SubnetId' --output text)
    
    # Save subnet IDs
    cat >> /tmp/eks-multi-cluster-env.sh << EOF
export PRIMARY_PUBLIC_SUBNET_1=${PRIMARY_PUBLIC_SUBNET_1}
export PRIMARY_PUBLIC_SUBNET_2=${PRIMARY_PUBLIC_SUBNET_2}
export PRIMARY_PRIVATE_SUBNET_1=${PRIMARY_PRIVATE_SUBNET_1}
export PRIMARY_PRIVATE_SUBNET_2=${PRIMARY_PRIVATE_SUBNET_2}
EOF
    
    log_success "Primary region subnets created"
}

# Configure primary region networking
configure_primary_networking() {
    log "Configuring primary region networking..."
    
    # Create Internet Gateway
    aws ec2 create-internet-gateway \
        --tag-specifications \
        "ResourceType=internet-gateway,Tags=[{Key=Name,Value=primary-igw}]" \
        --region ${PRIMARY_REGION} > /dev/null
    
    PRIMARY_IGW_ID=$(aws ec2 describe-internet-gateways \
        --filters "Name=tag:Name,Values=primary-igw" \
        --region ${PRIMARY_REGION} \
        --query 'InternetGateways[0].InternetGatewayId' --output text)
    
    # Attach IGW to VPC
    aws ec2 attach-internet-gateway \
        --internet-gateway-id ${PRIMARY_IGW_ID} \
        --vpc-id ${PRIMARY_VPC_ID} \
        --region ${PRIMARY_REGION}
    
    # Enable auto-assign public IP for public subnets
    aws ec2 modify-subnet-attribute \
        --subnet-id ${PRIMARY_PUBLIC_SUBNET_1} \
        --map-public-ip-on-launch \
        --region ${PRIMARY_REGION}
    
    aws ec2 modify-subnet-attribute \
        --subnet-id ${PRIMARY_PUBLIC_SUBNET_2} \
        --map-public-ip-on-launch \
        --region ${PRIMARY_REGION}
    
    # Create NAT Gateways for private subnet internet access
    create_nat_gateways_primary
    
    echo "PRIMARY_IGW_ID=${PRIMARY_IGW_ID}" >> /tmp/eks-multi-cluster-env.sh
    
    log_success "Primary region networking configured"
}

# Create NAT Gateways for primary region
create_nat_gateways_primary() {
    log "Creating NAT Gateways in primary region..."
    
    # Allocate Elastic IPs
    PRIMARY_EIP_1=$(aws ec2 allocate-address \
        --domain vpc \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=primary-nat-eip-1}]" \
        --region ${PRIMARY_REGION} \
        --query 'AllocationId' --output text)
    
    PRIMARY_EIP_2=$(aws ec2 allocate-address \
        --domain vpc \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=primary-nat-eip-2}]" \
        --region ${PRIMARY_REGION} \
        --query 'AllocationId' --output text)
    
    # Create NAT Gateways
    PRIMARY_NAT_1=$(aws ec2 create-nat-gateway \
        --subnet-id ${PRIMARY_PUBLIC_SUBNET_1} \
        --allocation-id ${PRIMARY_EIP_1} \
        --tag-specifications "ResourceType=nat-gateway,Tags=[{Key=Name,Value=primary-nat-1}]" \
        --region ${PRIMARY_REGION} \
        --query 'NatGateway.NatGatewayId' --output text)
    
    PRIMARY_NAT_2=$(aws ec2 create-nat-gateway \
        --subnet-id ${PRIMARY_PUBLIC_SUBNET_2} \
        --allocation-id ${PRIMARY_EIP_2} \
        --tag-specifications "ResourceType=nat-gateway,Tags=[{Key=Name,Value=primary-nat-2}]" \
        --region ${PRIMARY_REGION} \
        --query 'NatGateway.NatGatewayId' --output text)
    
    # Wait for NAT Gateways to be available
    log "Waiting for NAT Gateways to be available..."
    aws ec2 wait nat-gateway-available --nat-gateway-ids ${PRIMARY_NAT_1} --region ${PRIMARY_REGION}
    aws ec2 wait nat-gateway-available --nat-gateway-ids ${PRIMARY_NAT_2} --region ${PRIMARY_REGION}
    
    # Configure route tables
    configure_route_tables_primary
    
    cat >> /tmp/eks-multi-cluster-env.sh << EOF
export PRIMARY_NAT_1=${PRIMARY_NAT_1}
export PRIMARY_NAT_2=${PRIMARY_NAT_2}
export PRIMARY_EIP_1=${PRIMARY_EIP_1}
export PRIMARY_EIP_2=${PRIMARY_EIP_2}
EOF
    
    log_success "NAT Gateways created in primary region"
}

# Configure route tables for primary region
configure_route_tables_primary() {
    log "Configuring route tables for primary region..."
    
    # Get main route table
    MAIN_RT_ID=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=${PRIMARY_VPC_ID}" "Name=association.main,Values=true" \
        --region ${PRIMARY_REGION} \
        --query 'RouteTables[0].RouteTableId' --output text)
    
    # Create route table for public subnets
    PUBLIC_RT_ID=$(aws ec2 create-route-table \
        --vpc-id ${PRIMARY_VPC_ID} \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=primary-public-rt}]" \
        --region ${PRIMARY_REGION} \
        --query 'RouteTable.RouteTableId' --output text)
    
    # Add internet gateway route to public route table
    aws ec2 create-route \
        --route-table-id ${PUBLIC_RT_ID} \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id ${PRIMARY_IGW_ID} \
        --region ${PRIMARY_REGION} > /dev/null
    
    # Associate public subnets with public route table
    aws ec2 associate-route-table \
        --subnet-id ${PRIMARY_PUBLIC_SUBNET_1} \
        --route-table-id ${PUBLIC_RT_ID} \
        --region ${PRIMARY_REGION} > /dev/null
    
    aws ec2 associate-route-table \
        --subnet-id ${PRIMARY_PUBLIC_SUBNET_2} \
        --route-table-id ${PUBLIC_RT_ID} \
        --region ${PRIMARY_REGION} > /dev/null
    
    # Create route tables for private subnets
    PRIVATE_RT_1=$(aws ec2 create-route-table \
        --vpc-id ${PRIMARY_VPC_ID} \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=primary-private-rt-1}]" \
        --region ${PRIMARY_REGION} \
        --query 'RouteTable.RouteTableId' --output text)
    
    PRIVATE_RT_2=$(aws ec2 create-route-table \
        --vpc-id ${PRIMARY_VPC_ID} \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=primary-private-rt-2}]" \
        --region ${PRIMARY_REGION} \
        --query 'RouteTable.RouteTableId' --output text)
    
    # Add NAT gateway routes to private route tables
    aws ec2 create-route \
        --route-table-id ${PRIVATE_RT_1} \
        --destination-cidr-block 0.0.0.0/0 \
        --nat-gateway-id ${PRIMARY_NAT_1} \
        --region ${PRIMARY_REGION} > /dev/null
    
    aws ec2 create-route \
        --route-table-id ${PRIVATE_RT_2} \
        --destination-cidr-block 0.0.0.0/0 \
        --nat-gateway-id ${PRIMARY_NAT_2} \
        --region ${PRIMARY_REGION} > /dev/null
    
    # Associate private subnets with private route tables
    aws ec2 associate-route-table \
        --subnet-id ${PRIMARY_PRIVATE_SUBNET_1} \
        --route-table-id ${PRIVATE_RT_1} \
        --region ${PRIMARY_REGION} > /dev/null
    
    aws ec2 associate-route-table \
        --subnet-id ${PRIMARY_PRIVATE_SUBNET_2} \
        --route-table-id ${PRIVATE_RT_2} \
        --region ${PRIMARY_REGION} > /dev/null
    
    log_success "Route tables configured for primary region"
}

# Create secondary region infrastructure
create_secondary_infrastructure() {
    log "Creating secondary region VPC and Transit Gateway..."
    
    # Create VPC for secondary region
    aws ec2 create-vpc \
        --cidr-block 10.2.0.0/16 \
        --tag-specifications \
        "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_SECONDARY_NAME}}]" \
        --region ${SECONDARY_REGION} > /dev/null
    
    # Get VPC ID
    SECONDARY_VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=${VPC_SECONDARY_NAME}" \
        --region ${SECONDARY_REGION} \
        --query 'Vpcs[0].VpcId' --output text)
    
    # Enable DNS hostnames and resolution
    aws ec2 modify-vpc-attribute \
        --vpc-id ${SECONDARY_VPC_ID} \
        --enable-dns-hostnames \
        --region ${SECONDARY_REGION}
    
    aws ec2 modify-vpc-attribute \
        --vpc-id ${SECONDARY_VPC_ID} \
        --enable-dns-support \
        --region ${SECONDARY_REGION}
    
    # Create Transit Gateway in secondary region
    aws ec2 create-transit-gateway \
        --description "Secondary region Transit Gateway" \
        --options AmazonSideAsn=64513,AutoAcceptSharedAttachments=enable,DefaultRouteTableAssociation=enable,DefaultRouteTablePropagation=enable \
        --tag-specifications \
        "ResourceType=transit-gateway,Tags=[{Key=Name,Value=${TGW_SECONDARY_NAME}}]" \
        --region ${SECONDARY_REGION} > /dev/null
    
    # Get Transit Gateway ID
    SECONDARY_TGW_ID=$(aws ec2 describe-transit-gateways \
        --filters "Name=tag:Name,Values=${TGW_SECONDARY_NAME}" \
        --region ${SECONDARY_REGION} \
        --query 'TransitGateways[0].TransitGatewayId' --output text)
    
    # Wait for Transit Gateway to be available
    log "Waiting for secondary Transit Gateway to be available..."
    aws ec2 wait transit-gateway-available \
        --transit-gateway-ids ${SECONDARY_TGW_ID} \
        --region ${SECONDARY_REGION}
    
    # Create subnets
    create_subnets_secondary
    
    # Configure networking
    configure_secondary_networking
    
    cat >> /tmp/eks-multi-cluster-env.sh << EOF
export SECONDARY_VPC_ID=${SECONDARY_VPC_ID}
export SECONDARY_TGW_ID=${SECONDARY_TGW_ID}
EOF
    
    log_success "Secondary region infrastructure created"
}

# Create subnets in secondary region
create_subnets_secondary() {
    log "Creating subnets in secondary region..."
    
    # Create public subnets
    aws ec2 create-subnet \
        --vpc-id ${SECONDARY_VPC_ID} \
        --cidr-block 10.2.1.0/24 \
        --availability-zone ${SECONDARY_REGION}a \
        --tag-specifications \
        "ResourceType=subnet,Tags=[{Key=Name,Value=secondary-public-1},{Key=kubernetes.io/role/elb,Value=1}]" \
        --region ${SECONDARY_REGION} > /dev/null
    
    aws ec2 create-subnet \
        --vpc-id ${SECONDARY_VPC_ID} \
        --cidr-block 10.2.2.0/24 \
        --availability-zone ${SECONDARY_REGION}b \
        --tag-specifications \
        "ResourceType=subnet,Tags=[{Key=Name,Value=secondary-public-2},{Key=kubernetes.io/role/elb,Value=1}]" \
        --region ${SECONDARY_REGION} > /dev/null
    
    # Create private subnets
    aws ec2 create-subnet \
        --vpc-id ${SECONDARY_VPC_ID} \
        --cidr-block 10.2.3.0/24 \
        --availability-zone ${SECONDARY_REGION}a \
        --tag-specifications \
        "ResourceType=subnet,Tags=[{Key=Name,Value=secondary-private-1},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
        --region ${SECONDARY_REGION} > /dev/null
    
    aws ec2 create-subnet \
        --vpc-id ${SECONDARY_VPC_ID} \
        --cidr-block 10.2.4.0/24 \
        --availability-zone ${SECONDARY_REGION}b \
        --tag-specifications \
        "ResourceType=subnet,Tags=[{Key=Name,Value=secondary-private-2},{Key=kubernetes.io/role/internal-elb,Value=1}]" \
        --region ${SECONDARY_REGION} > /dev/null
    
    # Get subnet IDs
    SECONDARY_PUBLIC_SUBNET_1=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=secondary-public-1" \
        --region ${SECONDARY_REGION} \
        --query 'Subnets[0].SubnetId' --output text)
    
    SECONDARY_PUBLIC_SUBNET_2=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=secondary-public-2" \
        --region ${SECONDARY_REGION} \
        --query 'Subnets[0].SubnetId' --output text)
    
    SECONDARY_PRIVATE_SUBNET_1=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=secondary-private-1" \
        --region ${SECONDARY_REGION} \
        --query 'Subnets[0].SubnetId' --output text)
    
    SECONDARY_PRIVATE_SUBNET_2=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=secondary-private-2" \
        --region ${SECONDARY_REGION} \
        --query 'Subnets[0].SubnetId' --output text)
    
    # Save subnet IDs
    cat >> /tmp/eks-multi-cluster-env.sh << EOF
export SECONDARY_PUBLIC_SUBNET_1=${SECONDARY_PUBLIC_SUBNET_1}
export SECONDARY_PUBLIC_SUBNET_2=${SECONDARY_PUBLIC_SUBNET_2}
export SECONDARY_PRIVATE_SUBNET_1=${SECONDARY_PRIVATE_SUBNET_1}
export SECONDARY_PRIVATE_SUBNET_2=${SECONDARY_PRIVATE_SUBNET_2}
EOF
    
    log_success "Secondary region subnets created"
}

# Configure secondary region networking
configure_secondary_networking() {
    log "Configuring secondary region networking..."
    
    # Create Internet Gateway
    aws ec2 create-internet-gateway \
        --tag-specifications \
        "ResourceType=internet-gateway,Tags=[{Key=Name,Value=secondary-igw}]" \
        --region ${SECONDARY_REGION} > /dev/null
    
    SECONDARY_IGW_ID=$(aws ec2 describe-internet-gateways \
        --filters "Name=tag:Name,Values=secondary-igw" \
        --region ${SECONDARY_REGION} \
        --query 'InternetGateways[0].InternetGatewayId' --output text)
    
    # Attach IGW to VPC
    aws ec2 attach-internet-gateway \
        --internet-gateway-id ${SECONDARY_IGW_ID} \
        --vpc-id ${SECONDARY_VPC_ID} \
        --region ${SECONDARY_REGION}
    
    # Enable auto-assign public IP for public subnets
    aws ec2 modify-subnet-attribute \
        --subnet-id ${SECONDARY_PUBLIC_SUBNET_1} \
        --map-public-ip-on-launch \
        --region ${SECONDARY_REGION}
    
    aws ec2 modify-subnet-attribute \
        --subnet-id ${SECONDARY_PUBLIC_SUBNET_2} \
        --map-public-ip-on-launch \
        --region ${SECONDARY_REGION}
    
    # Create NAT Gateways for private subnet internet access
    create_nat_gateways_secondary
    
    echo "SECONDARY_IGW_ID=${SECONDARY_IGW_ID}" >> /tmp/eks-multi-cluster-env.sh
    
    log_success "Secondary region networking configured"
}

# Create NAT Gateways for secondary region
create_nat_gateways_secondary() {
    log "Creating NAT Gateways in secondary region..."
    
    # Allocate Elastic IPs
    SECONDARY_EIP_1=$(aws ec2 allocate-address \
        --domain vpc \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=secondary-nat-eip-1}]" \
        --region ${SECONDARY_REGION} \
        --query 'AllocationId' --output text)
    
    SECONDARY_EIP_2=$(aws ec2 allocate-address \
        --domain vpc \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=secondary-nat-eip-2}]" \
        --region ${SECONDARY_REGION} \
        --query 'AllocationId' --output text)
    
    # Create NAT Gateways
    SECONDARY_NAT_1=$(aws ec2 create-nat-gateway \
        --subnet-id ${SECONDARY_PUBLIC_SUBNET_1} \
        --allocation-id ${SECONDARY_EIP_1} \
        --tag-specifications "ResourceType=nat-gateway,Tags=[{Key=Name,Value=secondary-nat-1}]" \
        --region ${SECONDARY_REGION} \
        --query 'NatGateway.NatGatewayId' --output text)
    
    SECONDARY_NAT_2=$(aws ec2 create-nat-gateway \
        --subnet-id ${SECONDARY_PUBLIC_SUBNET_2} \
        --allocation-id ${SECONDARY_EIP_2} \
        --tag-specifications "ResourceType=nat-gateway,Tags=[{Key=Name,Value=secondary-nat-2}]" \
        --region ${SECONDARY_REGION} \
        --query 'NatGateway.NatGatewayId' --output text)
    
    # Wait for NAT Gateways to be available
    log "Waiting for NAT Gateways to be available..."
    aws ec2 wait nat-gateway-available --nat-gateway-ids ${SECONDARY_NAT_1} --region ${SECONDARY_REGION}
    aws ec2 wait nat-gateway-available --nat-gateway-ids ${SECONDARY_NAT_2} --region ${SECONDARY_REGION}
    
    # Configure route tables
    configure_route_tables_secondary
    
    cat >> /tmp/eks-multi-cluster-env.sh << EOF
export SECONDARY_NAT_1=${SECONDARY_NAT_1}
export SECONDARY_NAT_2=${SECONDARY_NAT_2}
export SECONDARY_EIP_1=${SECONDARY_EIP_1}
export SECONDARY_EIP_2=${SECONDARY_EIP_2}
EOF
    
    log_success "NAT Gateways created in secondary region"
}

# Configure route tables for secondary region
configure_route_tables_secondary() {
    log "Configuring route tables for secondary region..."
    
    # Create route table for public subnets
    PUBLIC_RT_ID_SEC=$(aws ec2 create-route-table \
        --vpc-id ${SECONDARY_VPC_ID} \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=secondary-public-rt}]" \
        --region ${SECONDARY_REGION} \
        --query 'RouteTable.RouteTableId' --output text)
    
    # Add internet gateway route to public route table
    aws ec2 create-route \
        --route-table-id ${PUBLIC_RT_ID_SEC} \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id ${SECONDARY_IGW_ID} \
        --region ${SECONDARY_REGION} > /dev/null
    
    # Associate public subnets with public route table
    aws ec2 associate-route-table \
        --subnet-id ${SECONDARY_PUBLIC_SUBNET_1} \
        --route-table-id ${PUBLIC_RT_ID_SEC} \
        --region ${SECONDARY_REGION} > /dev/null
    
    aws ec2 associate-route-table \
        --subnet-id ${SECONDARY_PUBLIC_SUBNET_2} \
        --route-table-id ${PUBLIC_RT_ID_SEC} \
        --region ${SECONDARY_REGION} > /dev/null
    
    # Create route tables for private subnets
    PRIVATE_RT_1_SEC=$(aws ec2 create-route-table \
        --vpc-id ${SECONDARY_VPC_ID} \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=secondary-private-rt-1}]" \
        --region ${SECONDARY_REGION} \
        --query 'RouteTable.RouteTableId' --output text)
    
    PRIVATE_RT_2_SEC=$(aws ec2 create-route-table \
        --vpc-id ${SECONDARY_VPC_ID} \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=secondary-private-rt-2}]" \
        --region ${SECONDARY_REGION} \
        --query 'RouteTable.RouteTableId' --output text)
    
    # Add NAT gateway routes to private route tables
    aws ec2 create-route \
        --route-table-id ${PRIVATE_RT_1_SEC} \
        --destination-cidr-block 0.0.0.0/0 \
        --nat-gateway-id ${SECONDARY_NAT_1} \
        --region ${SECONDARY_REGION} > /dev/null
    
    aws ec2 create-route \
        --route-table-id ${PRIVATE_RT_2_SEC} \
        --destination-cidr-block 0.0.0.0/0 \
        --nat-gateway-id ${SECONDARY_NAT_2} \
        --region ${SECONDARY_REGION} > /dev/null
    
    # Associate private subnets with private route tables
    aws ec2 associate-route-table \
        --subnet-id ${SECONDARY_PRIVATE_SUBNET_1} \
        --route-table-id ${PRIVATE_RT_1_SEC} \
        --region ${SECONDARY_REGION} > /dev/null
    
    aws ec2 associate-route-table \
        --subnet-id ${SECONDARY_PRIVATE_SUBNET_2} \
        --route-table-id ${PRIVATE_RT_2_SEC} \
        --region ${SECONDARY_REGION} > /dev/null
    
    log_success "Route tables configured for secondary region"
}

# Establish Transit Gateway cross-region peering
establish_tgw_peering() {
    log "Establishing Transit Gateway cross-region peering..."
    
    # Create Transit Gateway peering attachment
    TGW_PEERING_ID=$(aws ec2 create-transit-gateway-peering-attachment \
        --transit-gateway-id ${PRIMARY_TGW_ID} \
        --peer-transit-gateway-id ${SECONDARY_TGW_ID} \
        --peer-region ${SECONDARY_REGION} \
        --tag-specifications \
        "ResourceType=transit-gateway-peering-attachment,Tags=[{Key=Name,Value=multi-cluster-tgw-peering}]" \
        --region ${PRIMARY_REGION} \
        --query 'TransitGatewayPeeringAttachment.TransitGatewayPeeringAttachmentId' --output text)
    
    # Accept peering attachment in secondary region
    aws ec2 accept-transit-gateway-peering-attachment \
        --transit-gateway-peering-attachment-id ${TGW_PEERING_ID} \
        --region ${SECONDARY_REGION} > /dev/null
    
    # Wait for peering attachment to be available
    log "Waiting for Transit Gateway peering to be available..."
    aws ec2 wait transit-gateway-peering-attachment-available \
        --transit-gateway-peering-attachment-ids ${TGW_PEERING_ID} \
        --region ${PRIMARY_REGION}
    
    # Configure cross-region routing
    configure_cross_region_routing
    
    echo "TGW_PEERING_ID=${TGW_PEERING_ID}" >> /tmp/eks-multi-cluster-env.sh
    
    log_success "Transit Gateway cross-region peering established"
}

# Configure cross-region routing
configure_cross_region_routing() {
    log "Configuring Transit Gateway cross-region routing..."
    
    # Get Transit Gateway route table IDs
    PRIMARY_TGW_RT_ID=$(aws ec2 describe-transit-gateways \
        --transit-gateway-ids ${PRIMARY_TGW_ID} \
        --region ${PRIMARY_REGION} \
        --query 'TransitGateways[0].Options.DefaultRouteTableId' --output text)
    
    SECONDARY_TGW_RT_ID=$(aws ec2 describe-transit-gateways \
        --transit-gateway-ids ${SECONDARY_TGW_ID} \
        --region ${SECONDARY_REGION} \
        --query 'TransitGateways[0].Options.DefaultRouteTableId' --output text)
    
    # Add routes to Transit Gateway peering attachment
    aws ec2 create-route \
        --route-table-id ${PRIMARY_TGW_RT_ID} \
        --destination-cidr-block 10.2.0.0/16 \
        --transit-gateway-peering-attachment-id ${TGW_PEERING_ID} \
        --region ${PRIMARY_REGION} > /dev/null
    
    aws ec2 create-route \
        --route-table-id ${SECONDARY_TGW_RT_ID} \
        --destination-cidr-block 10.1.0.0/16 \
        --transit-gateway-peering-attachment-id ${TGW_PEERING_ID} \
        --region ${SECONDARY_REGION} > /dev/null
    
    # Attach VPCs to Transit Gateways
    PRIMARY_TGW_ATTACHMENT_ID=$(aws ec2 create-transit-gateway-vpc-attachment \
        --transit-gateway-id ${PRIMARY_TGW_ID} \
        --vpc-id ${PRIMARY_VPC_ID} \
        --subnet-ids ${PRIMARY_PRIVATE_SUBNET_1} ${PRIMARY_PRIVATE_SUBNET_2} \
        --tag-specifications \
        "ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=primary-tgw-attachment}]" \
        --region ${PRIMARY_REGION} \
        --query 'TransitGatewayVpcAttachment.TransitGatewayVpcAttachmentId' --output text)
    
    SECONDARY_TGW_ATTACHMENT_ID=$(aws ec2 create-transit-gateway-vpc-attachment \
        --transit-gateway-id ${SECONDARY_TGW_ID} \
        --vpc-id ${SECONDARY_VPC_ID} \
        --subnet-ids ${SECONDARY_PRIVATE_SUBNET_1} ${SECONDARY_PRIVATE_SUBNET_2} \
        --tag-specifications \
        "ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=secondary-tgw-attachment}]" \
        --region ${SECONDARY_REGION} \
        --query 'TransitGatewayVpcAttachment.TransitGatewayVpcAttachmentId' --output text)
    
    cat >> /tmp/eks-multi-cluster-env.sh << EOF
export PRIMARY_TGW_ATTACHMENT_ID=${PRIMARY_TGW_ATTACHMENT_ID}
export SECONDARY_TGW_ATTACHMENT_ID=${SECONDARY_TGW_ATTACHMENT_ID}
EOF
    
    log_success "Cross-region routing configured"
}

# Create EKS clusters
create_eks_clusters() {
    log "Creating EKS clusters in both regions..."
    
    # Load subnet IDs from environment file
    source /tmp/eks-multi-cluster-env.sh
    
    # Create primary EKS cluster
    log "Creating primary EKS cluster..."
    aws eks create-cluster \
        --name ${PRIMARY_CLUSTER_NAME} \
        --version 1.28 \
        --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/eks-cluster-role-${RANDOM_SUFFIX} \
        --resources-vpc-config subnetIds=${PRIMARY_PUBLIC_SUBNET_1},${PRIMARY_PUBLIC_SUBNET_2},${PRIMARY_PRIVATE_SUBNET_1},${PRIMARY_PRIVATE_SUBNET_2} \
        --region ${PRIMARY_REGION} \
        --logging '{"clusterLogging":[{"types":["api","audit","authenticator"],"enabled":true}]}' > /dev/null
    
    # Create secondary EKS cluster
    log "Creating secondary EKS cluster..."
    aws eks create-cluster \
        --name ${SECONDARY_CLUSTER_NAME} \
        --version 1.28 \
        --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/eks-cluster-role-${RANDOM_SUFFIX} \
        --resources-vpc-config subnetIds=${SECONDARY_PUBLIC_SUBNET_1},${SECONDARY_PUBLIC_SUBNET_2},${SECONDARY_PRIVATE_SUBNET_1},${SECONDARY_PRIVATE_SUBNET_2} \
        --region ${SECONDARY_REGION} \
        --logging '{"clusterLogging":[{"types":["api","audit","authenticator"],"enabled":true}]}' > /dev/null
    
    # Wait for clusters to be active
    log "Waiting for primary EKS cluster to be active (this may take 10-15 minutes)..."
    aws eks wait cluster-active \
        --name ${PRIMARY_CLUSTER_NAME} \
        --region ${PRIMARY_REGION}
    
    log "Waiting for secondary EKS cluster to be active (this may take 10-15 minutes)..."
    aws eks wait cluster-active \
        --name ${SECONDARY_CLUSTER_NAME} \
        --region ${SECONDARY_REGION}
    
    log_success "EKS clusters created successfully"
}

# Create node groups
create_node_groups() {
    log "Creating node groups for both clusters..."
    
    # Load environment variables
    source /tmp/eks-multi-cluster-env.sh
    
    # Create node group for primary cluster
    aws eks create-nodegroup \
        --cluster-name ${PRIMARY_CLUSTER_NAME} \
        --nodegroup-name primary-nodes \
        --node-role arn:aws:iam::${AWS_ACCOUNT_ID}:role/eks-nodegroup-role-${RANDOM_SUFFIX} \
        --subnets ${PRIMARY_PRIVATE_SUBNET_1} ${PRIMARY_PRIVATE_SUBNET_2} \
        --scaling-config minSize=2,maxSize=6,desiredSize=3 \
        --instance-types m5.large \
        --capacity-type ON_DEMAND \
        --region ${PRIMARY_REGION} > /dev/null
    
    # Create node group for secondary cluster
    aws eks create-nodegroup \
        --cluster-name ${SECONDARY_CLUSTER_NAME} \
        --nodegroup-name secondary-nodes \
        --node-role arn:aws:iam::${AWS_ACCOUNT_ID}:role/eks-nodegroup-role-${RANDOM_SUFFIX} \
        --subnets ${SECONDARY_PRIVATE_SUBNET_1} ${SECONDARY_PRIVATE_SUBNET_2} \
        --scaling-config minSize=2,maxSize=6,desiredSize=3 \
        --instance-types m5.large \
        --capacity-type ON_DEMAND \
        --region ${SECONDARY_REGION} > /dev/null
    
    # Wait for node groups to be ready
    log "Waiting for primary node group to be ready..."
    aws eks wait nodegroup-active \
        --cluster-name ${PRIMARY_CLUSTER_NAME} \
        --nodegroup-name primary-nodes \
        --region ${PRIMARY_REGION}
    
    log "Waiting for secondary node group to be ready..."
    aws eks wait nodegroup-active \
        --cluster-name ${SECONDARY_CLUSTER_NAME} \
        --nodegroup-name secondary-nodes \
        --region ${SECONDARY_REGION}
    
    log_success "Node groups created for both clusters"
}

# Configure kubectl access
configure_kubectl() {
    log "Configuring kubectl for multi-cluster access..."
    
    # Update kubeconfig for primary cluster
    aws eks update-kubeconfig \
        --name ${PRIMARY_CLUSTER_NAME} \
        --region ${PRIMARY_REGION} \
        --alias primary-cluster > /dev/null
    
    # Update kubeconfig for secondary cluster
    aws eks update-kubeconfig \
        --name ${SECONDARY_CLUSTER_NAME} \
        --region ${SECONDARY_REGION} \
        --alias secondary-cluster > /dev/null
    
    # Test connectivity
    log "Testing connectivity to both clusters..."
    kubectl --context=primary-cluster get nodes > /dev/null
    kubectl --context=secondary-cluster get nodes > /dev/null
    
    log_success "kubectl configured for multi-cluster access"
}

# Install VPC Lattice Gateway API Controller
install_vpc_lattice_controller() {
    log "Installing VPC Lattice Gateway API Controller..."
    
    # Install VPC Lattice Gateway API Controller in primary cluster
    kubectl --context=primary-cluster apply -f \
        https://raw.githubusercontent.com/aws/aws-application-networking-k8s/main/deploy/deploy-v1.0.0.yaml > /dev/null
    
    # Install VPC Lattice Gateway API Controller in secondary cluster
    kubectl --context=secondary-cluster apply -f \
        https://raw.githubusercontent.com/aws/aws-application-networking-k8s/main/deploy/deploy-v1.0.0.yaml > /dev/null
    
    # Wait for controllers to be ready
    log "Waiting for VPC Lattice controllers to be ready..."
    kubectl --context=primary-cluster wait --for=condition=Ready pod \
        -l app.kubernetes.io/name=gateway-api-controller \
        -n aws-application-networking-system --timeout=300s > /dev/null
    
    kubectl --context=secondary-cluster wait --for=condition=Ready pod \
        -l app.kubernetes.io/name=gateway-api-controller \
        -n aws-application-networking-system --timeout=300s > /dev/null
    
    log_success "VPC Lattice Gateway API Controllers installed"
}

# Deploy sample applications
deploy_sample_applications() {
    log "Deploying sample applications with VPC Lattice..."
    
    # Deploy to primary cluster
    kubectl --context=primary-cluster apply -f - <<EOF > /dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-primary
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-primary
  template:
    metadata:
      labels:
        app: nginx-primary
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        env:
        - name: REGION
          value: "primary-${PRIMARY_REGION}"
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-primary-service
  namespace: default
spec:
  selector:
    app: nginx-primary
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: nginx-primary-gateway
  namespace: default
  annotations:
    application-networking.k8s.aws/lattice-assigned-domain-name: "primary-nginx.${AWS_ACCOUNT_ID}.vpce-svc.${PRIMARY_REGION}.vpce.amazonaws.com"
spec:
  gatewayClassName: amazon-vpc-lattice
  listeners:
  - name: http
    protocol: HTTP
    port: 80
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: nginx-primary-route
  namespace: default
spec:
  parentRefs:
  - name: nginx-primary-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: "/"
    backendRefs:
    - name: nginx-primary-service
      port: 80
EOF
    
    # Deploy to secondary cluster
    kubectl --context=secondary-cluster apply -f - <<EOF > /dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-secondary
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-secondary
  template:
    metadata:
      labels:
        app: nginx-secondary
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        env:
        - name: REGION
          value: "secondary-${SECONDARY_REGION}"
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-secondary-service
  namespace: default
spec:
  selector:
    app: nginx-secondary
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: nginx-secondary-gateway
  namespace: default
  annotations:
    application-networking.k8s.aws/lattice-assigned-domain-name: "secondary-nginx.${AWS_ACCOUNT_ID}.vpce-svc.${SECONDARY_REGION}.vpce.amazonaws.com"
spec:
  gatewayClassName: amazon-vpc-lattice
  listeners:
  - name: http
    protocol: HTTP
    port: 80
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: nginx-secondary-route
  namespace: default
spec:
  parentRefs:
  - name: nginx-secondary-gateway
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: "/"
    backendRefs:
    - name: nginx-secondary-service
      port: 80
EOF
    
    log_success "Sample applications deployed to both clusters"
}

# Configure VPC Lattice Service Network
configure_vpc_lattice_service_network() {
    log "Configuring VPC Lattice Service Network..."
    
    # Create VPC Lattice Service Network
    SERVICE_NETWORK_NAME="multi-cluster-service-network-${RANDOM_SUFFIX}"
    
    # Load environment variables
    source /tmp/eks-multi-cluster-env.sh
    
    SERVICE_NETWORK_ID=$(aws vpc-lattice create-service-network \
        --name ${SERVICE_NETWORK_NAME} \
        --auth-type AWS_IAM \
        --tags Key=Name,Value=${SERVICE_NETWORK_NAME} \
        --region ${PRIMARY_REGION} \
        --query 'id' --output text)
    
    # Associate VPCs with Service Network
    aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --vpc-identifier ${PRIMARY_VPC_ID} \
        --region ${PRIMARY_REGION} > /dev/null
    
    aws vpc-lattice create-service-network-vpc-association \
        --service-network-identifier ${SERVICE_NETWORK_ID} \
        --vpc-identifier ${SECONDARY_VPC_ID} \
        --region ${PRIMARY_REGION} > /dev/null
    
    cat >> /tmp/eks-multi-cluster-env.sh << EOF
export SERVICE_NETWORK_ID=${SERVICE_NETWORK_ID}
export SERVICE_NETWORK_NAME=${SERVICE_NETWORK_NAME}
EOF
    
    log_success "VPC Lattice Service Network configured"
}

# Main deployment function
main() {
    log "Starting multi-cluster EKS deployment..."
    
    check_prerequisites
    setup_environment
    create_iam_roles
    create_primary_infrastructure
    create_secondary_infrastructure
    establish_tgw_peering
    create_eks_clusters
    create_node_groups
    configure_kubectl
    install_vpc_lattice_controller
    deploy_sample_applications
    configure_vpc_lattice_service_network
    
    log_success "Multi-cluster EKS deployment completed successfully!"
    echo ""
    echo "Environment details saved to: /tmp/eks-multi-cluster-env.sh"
    echo "Primary cluster: ${PRIMARY_CLUSTER_NAME} (${PRIMARY_REGION})"
    echo "Secondary cluster: ${SECONDARY_CLUSTER_NAME} (${SECONDARY_REGION})"
    echo ""
    echo "To manage clusters:"
    echo "  kubectl --context=primary-cluster get nodes"
    echo "  kubectl --context=secondary-cluster get nodes"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Run main function
main "$@"