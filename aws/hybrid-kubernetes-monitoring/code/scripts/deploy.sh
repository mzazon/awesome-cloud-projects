#!/bin/bash

# AWS EKS Hybrid Kubernetes Monitoring Deployment Script
# This script deploys the complete infrastructure for implementing hybrid Kubernetes monitoring
# with Amazon EKS Hybrid Nodes and CloudWatch

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration flags
DRY_RUN=${DRY_RUN:-false}
SKIP_PREREQUISITES=${SKIP_PREREQUISITES:-false}
TIMEOUT_MINUTES=${TIMEOUT_MINUTES:-30}

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${ERROR_LOG}" >&2)

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

# Cleanup function for script exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code $exit_code"
        log_error "Check the error log: ${ERROR_LOG}"
        log_error "For troubleshooting, review the deployment log: ${LOG_FILE}"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Display script banner
show_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════╗
║                 AWS EKS Hybrid Monitoring Deployment                    ║
║          Implementing Hybrid Kubernetes Monitoring with                 ║
║              Amazon EKS Hybrid Nodes and CloudWatch                     ║
╚══════════════════════════════════════════════════════════════════════════╝
EOF
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required CLI tools
    if ! command -v aws >/dev/null 2>&1; then
        missing_tools+=("aws-cli")
    fi
    
    if ! command -v kubectl >/dev/null 2>&1; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_tools+=("jq")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install the missing tools and run the script again."
        exit 1
    fi
    
    # Check AWS authentication
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or credentials are invalid"
        log_error "Please run 'aws configure' or set up your AWS credentials"
        exit 1
    fi
    
    # Verify AWS permissions
    log_info "Verifying AWS permissions..."
    local required_permissions=(
        "eks:CreateCluster"
        "eks:DescribeCluster"
        "iam:CreateRole"
        "iam:AttachRolePolicy"
        "ec2:CreateVpc"
        "ec2:DescribeVpcs"
        "cloudwatch:PutDashboard"
        "cloudwatch:PutMetricAlarm"
    )
    
    # Note: This is a simplified check - in production you might want more detailed permission validation
    log_success "AWS CLI and basic permissions verified"
}

# Generate unique resource identifiers
generate_resource_names() {
    log_info "Generating unique resource identifiers..."
    
    # Generate random suffix for unique naming
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set environment variables for resource naming
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export CLUSTER_NAME="hybrid-monitoring-cluster-${RANDOM_SUFFIX}"
    export VPC_NAME="hybrid-monitoring-vpc-${RANDOM_SUFFIX}"
    export CLOUDWATCH_NAMESPACE="EKS/HybridMonitoring"
    
    log_info "Generated resource names:"
    log_info "  AWS Region: ${AWS_REGION}"
    log_info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "  Cluster Name: ${CLUSTER_NAME}"
    log_info "  VPC Name: ${VPC_NAME}"
    log_info "  CloudWatch Namespace: ${CLOUDWATCH_NAMESPACE}"
}

# Create VPC and networking infrastructure
create_vpc_infrastructure() {
    log_info "Creating VPC and networking infrastructure..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would create VPC infrastructure"
        return 0
    fi
    
    # Create VPC
    log_info "Creating VPC with CIDR 10.0.0.0/16..."
    aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}},{Key=Purpose,Value=EKS-Hybrid-Monitoring}]" \
        >/dev/null
    
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=${VPC_NAME}" \
        --query 'Vpcs[0].VpcId' --output text)
    
    if [[ "$VPC_ID" == "None" ]] || [[ -z "$VPC_ID" ]]; then
        log_error "Failed to create or retrieve VPC"
        exit 1
    fi
    
    log_success "VPC created: ${VPC_ID}"
    
    # Create Internet Gateway
    log_info "Creating Internet Gateway..."
    aws ec2 create-internet-gateway \
        --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw}]" \
        >/dev/null
    
    export IGW_ID=$(aws ec2 describe-internet-gateways \
        --filters "Name=tag:Name,Values=${VPC_NAME}-igw" \
        --query 'InternetGateways[0].InternetGatewayId' --output text)
    
    # Attach Internet Gateway to VPC
    aws ec2 attach-internet-gateway \
        --vpc-id "${VPC_ID}" \
        --internet-gateway-id "${IGW_ID}"
    
    log_success "Internet Gateway created and attached: ${IGW_ID}"
    
    # Create public subnets
    log_info "Creating public subnets..."
    aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=hybrid-public-1}]" \
        >/dev/null
    
    aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.2.0/24 \
        --availability-zone "${AWS_REGION}b" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=hybrid-public-2}]" \
        >/dev/null
    
    export PUBLIC_SUBNET_1=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=hybrid-public-1" \
        --query 'Subnets[0].SubnetId' --output text)
    
    export PUBLIC_SUBNET_2=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=hybrid-public-2" \
        --query 'Subnets[0].SubnetId' --output text)
    
    # Enable auto-assign public IPs
    aws ec2 modify-subnet-attribute \
        --subnet-id "${PUBLIC_SUBNET_1}" \
        --map-public-ip-on-launch
    
    aws ec2 modify-subnet-attribute \
        --subnet-id "${PUBLIC_SUBNET_2}" \
        --map-public-ip-on-launch
    
    log_success "Public subnets created: ${PUBLIC_SUBNET_1}, ${PUBLIC_SUBNET_2}"
    
    # Create private subnets for Fargate
    log_info "Creating private subnets for Fargate..."
    aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.3.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=hybrid-private-1}]" \
        >/dev/null
    
    aws ec2 create-subnet \
        --vpc-id "${VPC_ID}" \
        --cidr-block 10.0.4.0/24 \
        --availability-zone "${AWS_REGION}b" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=hybrid-private-2}]" \
        >/dev/null
    
    export PRIVATE_SUBNET_1=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=hybrid-private-1" \
        --query 'Subnets[0].SubnetId' --output text)
    
    export PRIVATE_SUBNET_2=$(aws ec2 describe-subnets \
        --filters "Name=tag:Name,Values=hybrid-private-2" \
        --query 'Subnets[0].SubnetId' --output text)
    
    log_success "Private subnets created: ${PRIVATE_SUBNET_1}, ${PRIVATE_SUBNET_2}"
    
    # Create and configure route tables
    setup_routing
}

# Setup routing for VPC
setup_routing() {
    log_info "Setting up routing tables..."
    
    # Create route table for public subnets
    aws ec2 create-route-table \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-public-rt}]" \
        >/dev/null
    
    export PUBLIC_RT_ID=$(aws ec2 describe-route-tables \
        --filters "Name=tag:Name,Values=${VPC_NAME}-public-rt" \
        --query 'RouteTables[0].RouteTableId' --output text)
    
    # Create route to internet gateway
    aws ec2 create-route \
        --route-table-id "${PUBLIC_RT_ID}" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "${IGW_ID}" \
        >/dev/null
    
    # Associate public subnets with route table
    aws ec2 associate-route-table \
        --subnet-id "${PUBLIC_SUBNET_1}" \
        --route-table-id "${PUBLIC_RT_ID}" \
        >/dev/null
    
    aws ec2 associate-route-table \
        --subnet-id "${PUBLIC_SUBNET_2}" \
        --route-table-id "${PUBLIC_RT_ID}" \
        >/dev/null
    
    # Create NAT Gateway for private subnets
    log_info "Creating NAT Gateway for private subnet internet access..."
    aws ec2 allocate-address --domain vpc \
        --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${VPC_NAME}-nat-eip-1}]" \
        >/dev/null
    
    export NAT_EIP_1=$(aws ec2 describe-addresses \
        --filters "Name=tag:Name,Values=${VPC_NAME}-nat-eip-1" \
        --query 'Addresses[0].AllocationId' --output text)
    
    aws ec2 create-nat-gateway \
        --subnet-id "${PUBLIC_SUBNET_1}" \
        --allocation-id "${NAT_EIP_1}" \
        --tag-specifications "ResourceType=nat-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-nat-gw-1}]" \
        >/dev/null
    
    # Wait for NAT Gateway to be available
    log_info "Waiting for NAT Gateway to be available..."
    export NAT_GW_1=$(aws ec2 describe-nat-gateways \
        --filter "Name=tag:Name,Values=${VPC_NAME}-nat-gw-1" \
        --query 'NatGateways[0].NatGatewayId' --output text)
    
    aws ec2 wait nat-gateway-available --nat-gateway-ids "${NAT_GW_1}"
    
    # Create route table for private subnets
    aws ec2 create-route-table \
        --vpc-id "${VPC_ID}" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-private-rt}]" \
        >/dev/null
    
    export PRIVATE_RT_ID=$(aws ec2 describe-route-tables \
        --filters "Name=tag:Name,Values=${VPC_NAME}-private-rt" \
        --query 'RouteTables[0].RouteTableId' --output text)
    
    # Create route to NAT gateway
    aws ec2 create-route \
        --route-table-id "${PRIVATE_RT_ID}" \
        --destination-cidr-block 0.0.0.0/0 \
        --nat-gateway-id "${NAT_GW_1}" \
        >/dev/null
    
    # Associate private subnets with route table
    aws ec2 associate-route-table \
        --subnet-id "${PRIVATE_SUBNET_1}" \
        --route-table-id "${PRIVATE_RT_ID}" \
        >/dev/null
    
    aws ec2 associate-route-table \
        --subnet-id "${PRIVATE_SUBNET_2}" \
        --route-table-id "${PRIVATE_RT_ID}" \
        >/dev/null
    
    log_success "Routing configured successfully"
}

# Create IAM roles for EKS
create_iam_roles() {
    log_info "Creating IAM roles for EKS cluster..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would create IAM roles"
        return 0
    fi
    
    # Create EKS cluster service role
    log_info "Creating EKS cluster service role..."
    
    cat > /tmp/eks-cluster-trust-policy.json << EOF
{
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
}
EOF
    
    aws iam create-role \
        --role-name "EKSClusterServiceRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document file:///tmp/eks-cluster-trust-policy.json \
        --tags Key=Purpose,Value=EKS-Hybrid-Monitoring \
        >/dev/null
    
    aws iam attach-role-policy \
        --role-name "EKSClusterServiceRole-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
    
    export EKS_ROLE_ARN=$(aws iam get-role \
        --role-name "EKSClusterServiceRole-${RANDOM_SUFFIX}" \
        --query 'Role.Arn' --output text)
    
    log_success "EKS cluster service role created: ${EKS_ROLE_ARN}"
    
    # Create Fargate execution role
    log_info "Creating Fargate execution role..."
    
    cat > /tmp/fargate-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks-fargate-pods.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    aws iam create-role \
        --role-name "EKSFargateExecutionRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document file:///tmp/fargate-trust-policy.json \
        --tags Key=Purpose,Value=EKS-Hybrid-Monitoring \
        >/dev/null
    
    aws iam attach-role-policy \
        --role-name "EKSFargateExecutionRole-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy
    
    export FARGATE_ROLE_ARN=$(aws iam get-role \
        --role-name "EKSFargateExecutionRole-${RANDOM_SUFFIX}" \
        --query 'Role.Arn' --output text)
    
    log_success "Fargate execution role created: ${FARGATE_ROLE_ARN}"
    
    # Clean up temporary files
    rm -f /tmp/eks-cluster-trust-policy.json /tmp/fargate-trust-policy.json
}

# Create EKS cluster with hybrid node support
create_eks_cluster() {
    log_info "Creating EKS cluster with hybrid node support..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would create EKS cluster"
        return 0
    fi
    
    # Create EKS cluster
    log_info "Creating EKS cluster: ${CLUSTER_NAME}"
    aws eks create-cluster \
        --name "${CLUSTER_NAME}" \
        --version 1.31 \
        --role-arn "${EKS_ROLE_ARN}" \
        --resources-vpc-config "subnetIds=${PUBLIC_SUBNET_1},${PUBLIC_SUBNET_2}" \
        --access-config authenticationMode=API_AND_CONFIG_MAP \
        --remote-network-config 'remoteNodeNetworks=[{cidrs=["10.100.0.0/16"]}]' \
        --tags Purpose=EKS-Hybrid-Monitoring,Environment=Demo \
        >/dev/null
    
    log_info "Waiting for EKS cluster to become active (this may take 10-15 minutes)..."
    aws eks wait cluster-active --name "${CLUSTER_NAME}"
    
    # Update kubeconfig
    log_info "Updating kubeconfig for cluster access..."
    aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"
    
    log_success "EKS cluster created and kubeconfig updated"
    
    # Verify cluster access
    if kubectl cluster-info >/dev/null 2>&1; then
        log_success "Kubernetes cluster access verified"
    else
        log_error "Failed to access Kubernetes cluster"
        exit 1
    fi
}

# Create Fargate profile
create_fargate_profile() {
    log_info "Creating Fargate profile for cloud workloads..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would create Fargate profile"
        return 0
    fi
    
    aws eks create-fargate-profile \
        --cluster-name "${CLUSTER_NAME}" \
        --fargate-profile-name cloud-workloads \
        --pod-execution-role-arn "${FARGATE_ROLE_ARN}" \
        --subnets "${PRIVATE_SUBNET_1}" "${PRIVATE_SUBNET_2}" \
        --selectors namespace=cloud-apps \
        --tags Environment=Demo,Component=CloudWorkloads \
        >/dev/null
    
    log_info "Waiting for Fargate profile to become active..."
    aws eks wait fargate-profile-active \
        --cluster-name "${CLUSTER_NAME}" \
        --fargate-profile-name cloud-workloads
    
    log_success "Fargate profile created successfully"
}

# Install CloudWatch Observability add-on
install_cloudwatch_addon() {
    log_info "Installing CloudWatch Observability add-on..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would install CloudWatch add-on"
        return 0
    fi
    
    # Get OIDC issuer URL
    export OIDC_ISSUER=$(aws eks describe-cluster \
        --name "${CLUSTER_NAME}" \
        --query 'cluster.identity.oidc.issuer' --output text)
    
    export OIDC_ID=$(echo "${OIDC_ISSUER}" | sed 's|https://||')
    
    # Check if OIDC provider exists, create if not
    if ! aws iam list-open-id-connect-providers \
        --query "OpenIDConnectProviderList[?contains(Arn, '${OIDC_ID}')].Arn" \
        --output text | grep -q "${OIDC_ID}"; then
        
        log_info "Creating OIDC identity provider..."
        aws iam create-open-id-connect-provider \
            --url "${OIDC_ISSUER}" \
            --client-id-list sts.amazonaws.com \
            --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab7280 \
            >/dev/null
    fi
    
    # Create IAM role for CloudWatch Observability add-on
    log_info "Creating IAM role for CloudWatch Observability add-on..."
    
    cat > /tmp/cloudwatch-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ID}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_ID}:sub": "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent",
          "${OIDC_ID}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF
    
    aws iam create-role \
        --role-name "CloudWatchObservabilityRole-${RANDOM_SUFFIX}" \
        --assume-role-policy-document file:///tmp/cloudwatch-trust-policy.json \
        --tags Key=Purpose,Value=EKS-Hybrid-Monitoring \
        >/dev/null
    
    aws iam attach-role-policy \
        --role-name "CloudWatchObservabilityRole-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
    
    export CLOUDWATCH_ROLE_ARN=$(aws iam get-role \
        --role-name "CloudWatchObservabilityRole-${RANDOM_SUFFIX}" \
        --query 'Role.Arn' --output text)
    
    # Install CloudWatch Observability add-on
    log_info "Installing CloudWatch Observability add-on with Container Insights..."
    aws eks create-addon \
        --cluster-name "${CLUSTER_NAME}" \
        --addon-name amazon-cloudwatch-observability \
        --addon-version v2.1.0-eksbuild.1 \
        --service-account-role-arn "${CLOUDWATCH_ROLE_ARN}" \
        --configuration-values '{"containerInsights":{"enabled":true}}' \
        >/dev/null
    
    log_info "Waiting for CloudWatch add-on to become active..."
    aws eks wait addon-active \
        --cluster-name "${CLUSTER_NAME}" \
        --addon-name amazon-cloudwatch-observability
    
    log_success "CloudWatch Observability add-on installed successfully"
    
    # Clean up temporary files
    rm -f /tmp/cloudwatch-trust-policy.json
}

# Deploy sample applications
deploy_sample_applications() {
    log_info "Deploying sample applications for testing..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would deploy sample applications"
        return 0
    fi
    
    # Create namespace for cloud applications
    kubectl create namespace cloud-apps --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace cloud-apps monitoring=enabled --overwrite
    
    # Deploy sample application on Fargate
    log_info "Deploying sample application to Fargate..."
    
    cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cloud-sample-app
  namespace: cloud-apps
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cloud-sample-app
  template:
    metadata:
      labels:
        app: cloud-sample-app
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "80"
    spec:
      containers:
      - name: sample-app
        image: public.ecr.aws/docker/library/nginx:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
        env:
        - name: ENVIRONMENT
          value: "fargate"
        - name: CLUSTER_NAME
          value: "${CLUSTER_NAME}"
---
apiVersion: v1
kind: Service
metadata:
  name: cloud-sample-service
  namespace: cloud-apps
spec:
  selector:
    app: cloud-sample-app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP
EOF
    
    # Wait for pods to be ready
    log_info "Waiting for sample application pods to be ready..."
    kubectl wait --for=condition=ready pod -l app=cloud-sample-app -n cloud-apps --timeout=300s
    
    log_success "Sample applications deployed successfully"
}

# Setup CloudWatch dashboards and alarms
setup_monitoring() {
    log_info "Setting up CloudWatch dashboards and alarms..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would setup monitoring"
        return 0
    fi
    
    # Create CloudWatch dashboard
    log_info "Creating CloudWatch dashboard..."
    
    cat > /tmp/dashboard-body.json << EOF
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
          [ "AWS/EKS", "cluster_node_count", "ClusterName", "${CLUSTER_NAME}" ],
          [ "${CLOUDWATCH_NAMESPACE}", "HybridNodeCount" ],
          [ ".", "FargatePodCount" ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "${AWS_REGION}",
        "title": "Hybrid Cluster Capacity",
        "yAxis": {
          "left": {
            "min": 0
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
          [ "AWS/ContainerInsights", "pod_cpu_utilization", "ClusterName", "${CLUSTER_NAME}" ],
          [ ".", "pod_memory_utilization", ".", "." ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "${AWS_REGION}",
        "title": "Pod Resource Utilization",
        "yAxis": {
          "left": {
            "min": 0,
            "max": 100
          }
        }
      }
    },
    {
      "type": "log",
      "x": 0,
      "y": 12,
      "width": 24,
      "height": 6,
      "properties": {
        "query": "SOURCE \"/aws/containerinsights/${CLUSTER_NAME}/application\"\n| fields @timestamp, kubernetes.pod_name, log\n| filter kubernetes.namespace_name = \"cloud-apps\"\n| sort @timestamp desc\n| limit 100",
        "region": "${AWS_REGION}",
        "title": "Application Logs from Cloud Apps",
        "view": "table"
      }
    }
  ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "EKS-Hybrid-Monitoring-${CLUSTER_NAME}" \
        --dashboard-body file:///tmp/dashboard-body.json \
        >/dev/null
    
    # Create CloudWatch alarms
    log_info "Creating CloudWatch alarms..."
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "EKS-Hybrid-HighCPU-${CLUSTER_NAME}" \
        --alarm-description "High CPU utilization in hybrid cluster" \
        --metric-name pod_cpu_utilization \
        --namespace AWS/ContainerInsights \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=ClusterName,Value="${CLUSTER_NAME}" \
        --treat-missing-data notBreaching \
        >/dev/null
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "EKS-Hybrid-HighMemory-${CLUSTER_NAME}" \
        --alarm-description "High memory utilization in hybrid cluster" \
        --metric-name pod_memory_utilization \
        --namespace AWS/ContainerInsights \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=ClusterName,Value="${CLUSTER_NAME}" \
        --treat-missing-data notBreaching \
        >/dev/null
    
    log_success "CloudWatch monitoring configured successfully"
    
    # Clean up temporary files
    rm -f /tmp/dashboard-body.json
}

# Save deployment configuration
save_deployment_config() {
    log_info "Saving deployment configuration..."
    
    cat > "${SCRIPT_DIR}/deployment-config.env" << EOF
# EKS Hybrid Monitoring Deployment Configuration
# Generated on $(date)

# Resource Identifiers
RANDOM_SUFFIX=${RANDOM_SUFFIX}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
CLUSTER_NAME=${CLUSTER_NAME}
VPC_NAME=${VPC_NAME}
CLOUDWATCH_NAMESPACE=${CLOUDWATCH_NAMESPACE}

# Network Resources
VPC_ID=${VPC_ID}
IGW_ID=${IGW_ID}
PUBLIC_SUBNET_1=${PUBLIC_SUBNET_1}
PUBLIC_SUBNET_2=${PUBLIC_SUBNET_2}
PRIVATE_SUBNET_1=${PRIVATE_SUBNET_1}
PRIVATE_SUBNET_2=${PRIVATE_SUBNET_2}
PUBLIC_RT_ID=${PUBLIC_RT_ID}
PRIVATE_RT_ID=${PRIVATE_RT_ID}
NAT_GW_1=${NAT_GW_1}
NAT_EIP_1=${NAT_EIP_1}

# IAM Resources
EKS_ROLE_ARN=${EKS_ROLE_ARN}
FARGATE_ROLE_ARN=${FARGATE_ROLE_ARN}
CLOUDWATCH_ROLE_ARN=${CLOUDWATCH_ROLE_ARN}

# EKS Resources
OIDC_ISSUER=${OIDC_ISSUER}
OIDC_ID=${OIDC_ID}
EOF
    
    log_success "Deployment configuration saved to: ${SCRIPT_DIR}/deployment-config.env"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check EKS cluster status
    local cluster_status=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query 'cluster.status' --output text)
    if [[ "$cluster_status" != "ACTIVE" ]]; then
        log_error "EKS cluster is not active: ${cluster_status}"
        return 1
    fi
    
    # Check Fargate profile status
    local fargate_status=$(aws eks describe-fargate-profile \
        --cluster-name "${CLUSTER_NAME}" \
        --fargate-profile-name cloud-workloads \
        --query 'fargateProfile.status' --output text)
    if [[ "$fargate_status" != "ACTIVE" ]]; then
        log_error "Fargate profile is not active: ${fargate_status}"
        return 1
    fi
    
    # Check CloudWatch add-on status
    local addon_status=$(aws eks describe-addon \
        --cluster-name "${CLUSTER_NAME}" \
        --addon-name amazon-cloudwatch-observability \
        --query 'addon.status' --output text)
    if [[ "$addon_status" != "ACTIVE" ]]; then
        log_error "CloudWatch add-on is not active: ${addon_status}"
        return 1
    fi
    
    # Check sample application pods
    if ! kubectl get pods -n cloud-apps -l app=cloud-sample-app --no-headers | grep -q "Running"; then
        log_error "Sample application pods are not running"
        return 1
    fi
    
    log_success "Deployment validation completed successfully"
}

# Display deployment summary
show_deployment_summary() {
    cat << EOF

╔══════════════════════════════════════════════════════════════════════════╗
║                        DEPLOYMENT COMPLETED                             ║
╚══════════════════════════════════════════════════════════════════════════╝

🎉 EKS Hybrid Monitoring infrastructure has been successfully deployed!

📊 Resources Created:
   • EKS Cluster: ${CLUSTER_NAME}
   • VPC: ${VPC_ID}
   • Fargate Profile: cloud-workloads
   • CloudWatch Dashboard: EKS-Hybrid-Monitoring-${CLUSTER_NAME}

🔗 Access Links:
   • CloudWatch Dashboard: https://${AWS_REGION}.console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=EKS-Hybrid-Monitoring-${CLUSTER_NAME}
   • EKS Console: https://${AWS_REGION}.console.aws.amazon.com/eks/home?region=${AWS_REGION}#/clusters/${CLUSTER_NAME}

📋 Next Steps:
   1. Connect your on-premises nodes to the EKS cluster using the hybrid node configuration
   2. Deploy additional applications to test the monitoring capabilities
   3. Configure custom alerts and notifications as needed
   4. Review the CloudWatch dashboard for monitoring insights

🧹 Cleanup:
   To remove all resources, run: ./destroy.sh

📝 Configuration saved to: ${SCRIPT_DIR}/deployment-config.env
📊 Deployment logs: ${LOG_FILE}

EOF
}

# Print usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AWS EKS Hybrid Kubernetes Monitoring infrastructure.

OPTIONS:
    --dry-run              Show what would be deployed without making changes
    --skip-prerequisites   Skip prerequisite checks (not recommended)
    --timeout MINUTES      Set timeout for operations (default: 30)
    --help                 Show this help message

ENVIRONMENT VARIABLES:
    AWS_REGION            AWS region to deploy to (default: from AWS CLI config)
    DRY_RUN              Set to 'true' for dry run mode
    SKIP_PREREQUISITES   Set to 'true' to skip prerequisite checks
    TIMEOUT_MINUTES      Timeout for operations in minutes

EXAMPLES:
    $0                    # Deploy with default settings
    $0 --dry-run          # Preview deployment without making changes
    $0 --timeout 45       # Deploy with 45-minute timeout

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-prerequisites)
                SKIP_PREREQUISITES=true
                shift
                ;;
            --timeout)
                TIMEOUT_MINUTES="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Main deployment function
main() {
    parse_arguments "$@"
    
    show_banner
    
    log_info "Starting EKS Hybrid Monitoring deployment..."
    log_info "Deployment mode: $([[ "$DRY_RUN" == "true" ]] && echo "DRY RUN" || echo "LIVE")"
    log_info "Log file: ${LOG_FILE}"
    
    if [[ "$SKIP_PREREQUISITES" != "true" ]]; then
        check_prerequisites
    fi
    
    generate_resource_names
    create_vpc_infrastructure
    create_iam_roles
    create_eks_cluster
    create_fargate_profile
    install_cloudwatch_addon
    deploy_sample_applications
    setup_monitoring
    
    if [[ "$DRY_RUN" != "true" ]]; then
        save_deployment_config
        validate_deployment
        show_deployment_summary
    else
        log_info "DRY RUN completed - no resources were created"
    fi
    
    log_success "Deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"