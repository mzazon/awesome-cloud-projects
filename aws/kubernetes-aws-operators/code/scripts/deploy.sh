#!/bin/bash

# Deploy script for Kubernetes Operators for AWS Resources
# This script deploys ACK controllers and custom operators for managing AWS resources through Kubernetes

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Logging functions
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO: $1"
}

log_error() {
    log "ERROR: $1"
}

log_warning() {
    log "WARNING: $1"
}

# Color output for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    print_error "$1"
    exit 1
}

# Cleanup function for script interruption
cleanup() {
    if [[ $? -ne 0 ]]; then
        print_error "Deployment failed. Check $LOG_FILE for details."
        print_warning "You may need to run the destroy script to clean up partially created resources."
    fi
}

trap cleanup EXIT

# Banner
print_banner() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "  Kubernetes Operators for AWS Resources"
    echo "  Deployment Script"
    echo "=================================================="
    echo -e "${NC}"
}

# Configuration with defaults
DEFAULT_AWS_REGION="us-west-2"
DEFAULT_CLUSTER_NAME="ack-operators-cluster"
DEFAULT_ACK_NAMESPACE="ack-system"
DEFAULT_NODE_GROUP_SIZE="2"

# Environment variables with defaults
export AWS_REGION="${AWS_REGION:-$DEFAULT_AWS_REGION}"
export CLUSTER_NAME="${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}"
export ACK_SYSTEM_NAMESPACE="${ACK_SYSTEM_NAMESPACE:-$DEFAULT_ACK_NAMESPACE}"
export NODE_GROUP_SIZE="${NODE_GROUP_SIZE:-$DEFAULT_NODE_GROUP_SIZE}"

# Prerequisites check
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        error_exit "kubectl is not installed. Please install kubectl."
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        error_exit "Helm is not installed. Please install Helm v3.8+."
    fi
    
    # Check operator-sdk
    if ! command -v operator-sdk &> /dev/null; then
        print_warning "Operator SDK not found. Custom operator features may be limited."
    fi
    
    # Check Go
    if ! command -v go &> /dev/null; then
        print_warning "Go is not installed. Custom operator development will be skipped."
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_warning "Docker is not installed. Custom operator image building will be skipped."
    fi
    
    # Check AWS authentication
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS authentication failed. Please configure AWS credentials."
    fi
    
    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install jq for JSON parsing."
    fi
    
    print_success "Prerequisites check completed"
    
    # Get AWS account info
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_status "AWS Account ID: $AWS_ACCOUNT_ID"
    print_status "AWS Region: $AWS_REGION"
}

# Generate unique suffix for resources
generate_resource_suffix() {
    print_status "Generating unique resource suffix..."
    
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    export RESOURCE_SUFFIX="ack-${RANDOM_SUFFIX}"
    print_status "Resource suffix: $RESOURCE_SUFFIX"
}

# Create or update EKS cluster
setup_eks_cluster() {
    print_status "Setting up EKS cluster..."
    
    # Check if cluster exists
    if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" &>/dev/null; then
        print_warning "EKS cluster '$CLUSTER_NAME' already exists. Skipping creation."
    else
        print_status "Creating EKS cluster '$CLUSTER_NAME'..."
        
        # Create cluster service role if it doesn't exist
        ROLE_NAME="eks-service-role-${RESOURCE_SUFFIX}"
        if ! aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
            print_status "Creating EKS service role..."
            
            cat > /tmp/eks-trust-policy.json << EOF
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
                --role-name "$ROLE_NAME" \
                --assume-role-policy-document file:///tmp/eks-trust-policy.json \
                --description "EKS service role for ACK operators cluster"
            
            aws iam attach-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
            
            # Wait for role propagation
            sleep 10
        fi
        
        # Get default VPC and subnets
        VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" \
            --query "Vpcs[0].VpcId" --output text)
        
        if [[ "$VPC_ID" == "None" ]]; then
            error_exit "No default VPC found. Please create a VPC or specify subnet IDs."
        fi
        
        SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
            --query "Subnets[*].SubnetId" --output text | tr '\t' ',')
        
        print_status "Using VPC: $VPC_ID"
        print_status "Using subnets: $SUBNET_IDS"
        
        # Create EKS cluster
        aws eks create-cluster \
            --name "$CLUSTER_NAME" \
            --version 1.28 \
            --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}" \
            --resources-vpc-config subnetIds="$SUBNET_IDS" \
            --region "$AWS_REGION"
        
        print_status "Waiting for cluster to become active (this may take 10-15 minutes)..."
        aws eks wait cluster-active --name "$CLUSTER_NAME" --region "$AWS_REGION"
        
        # Create node group
        print_status "Creating managed node group..."
        
        NODE_ROLE_NAME="eks-node-role-${RESOURCE_SUFFIX}"
        if ! aws iam get-role --role-name "$NODE_ROLE_NAME" &>/dev/null; then
            cat > /tmp/node-trust-policy.json << EOF
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
            
            aws iam create-role \
                --role-name "$NODE_ROLE_NAME" \
                --assume-role-policy-document file:///tmp/node-trust-policy.json
            
            aws iam attach-role-policy \
                --role-name "$NODE_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
            
            aws iam attach-role-policy \
                --role-name "$NODE_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
            
            aws iam attach-role-policy \
                --role-name "$NODE_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
        fi
        
        aws eks create-nodegroup \
            --cluster-name "$CLUSTER_NAME" \
            --nodegroup-name "ack-operators-nodes" \
            --scaling-config minSize=1,maxSize=4,desiredSize="$NODE_GROUP_SIZE" \
            --instance-types t3.medium \
            --ami-type AL2_x86_64 \
            --node-role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${NODE_ROLE_NAME}" \
            --subnets $(echo "$SUBNET_IDS" | tr ',' ' ')
        
        print_status "Waiting for node group to become active..."
        aws eks wait nodegroup-active \
            --cluster-name "$CLUSTER_NAME" \
            --nodegroup-name "ack-operators-nodes"
    fi
    
    # Update kubeconfig
    print_status "Updating kubeconfig..."
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
    
    # Verify cluster connectivity
    if kubectl cluster-info &>/dev/null; then
        print_success "EKS cluster setup completed successfully"
    else
        error_exit "Failed to connect to EKS cluster"
    fi
}

# Setup OIDC identity provider and IAM roles
setup_oidc_and_iam() {
    print_status "Setting up OIDC identity provider and IAM roles..."
    
    # Get OIDC issuer URL
    OIDC_ISSUER=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
        --query "cluster.identity.oidc.issuer" --output text)
    OIDC_ID=$(echo "$OIDC_ISSUER" | cut -d '/' -f 5)
    
    print_status "OIDC Issuer: $OIDC_ISSUER"
    
    # Check if OIDC provider exists
    if ! aws iam get-open-id-connect-provider \
        --open-id-connect-provider-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ISSUER#https://}" &>/dev/null; then
        
        print_status "Creating OIDC identity provider..."
        
        # Get OIDC root CA thumbprint
        THUMBPRINT=$(echo | openssl s_client -servername oidc.eks."$AWS_REGION".amazonaws.com \
            -connect oidc.eks."$AWS_REGION".amazonaws.com:443 2>&- | \
            openssl x509 -fingerprint -noout | \
            cut -d= -f2 | tr -d :)
        
        aws iam create-open-id-connect-provider \
            --url "$OIDC_ISSUER" \
            --client-id-list sts.amazonaws.com \
            --thumbprint-list "$THUMBPRINT"
    else
        print_warning "OIDC provider already exists. Skipping creation."
    fi
    
    # Create IAM role for ACK controllers
    ACK_ROLE_NAME="ACK-Controller-Role-${RESOURCE_SUFFIX}"
    if ! aws iam get-role --role-name "$ACK_ROLE_NAME" &>/dev/null; then
        print_status "Creating IAM role for ACK controllers..."
        
        cat > /tmp/ack-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ISSUER#https://}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_ISSUER#https://}:sub": "system:serviceaccount:${ACK_SYSTEM_NAMESPACE}:ack-controller",
          "${OIDC_ISSUER#https://}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF
        
        aws iam create-role \
            --role-name "$ACK_ROLE_NAME" \
            --assume-role-policy-document file:///tmp/ack-trust-policy.json \
            --description "IAM role for ACK controllers"
        
        # Attach necessary policies for ACK controllers
        aws iam attach-role-policy \
            --role-name "$ACK_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
        
        aws iam attach-role-policy \
            --role-name "$ACK_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/IAMFullAccess
        
        aws iam attach-role-policy \
            --role-name "$ACK_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess
    else
        print_warning "ACK controller role already exists. Skipping creation."
    fi
    
    export ACK_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ACK_ROLE_NAME}"
    print_success "OIDC and IAM setup completed"
}

# Install ACK runtime and controllers
install_ack_controllers() {
    print_status "Installing ACK controllers..."
    
    # Create namespace for ACK controllers
    kubectl create namespace "$ACK_SYSTEM_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Add ACK Helm repository
    helm repo add aws-controllers-k8s https://aws-controllers-k8s.github.io/charts
    helm repo update
    
    # Install shared CRDs for ACK
    print_status "Installing ACK runtime CRDs..."
    kubectl apply -f https://raw.githubusercontent.com/aws-controllers-k8s/runtime/main/config/crd/bases/services.k8s.aws_adoptedresources.yaml
    kubectl apply -f https://raw.githubusercontent.com/aws-controllers-k8s/runtime/main/config/crd/bases/services.k8s.aws_fieldexports.yaml
    
    # Login to ECR public registry
    aws ecr-public get-login-password --region us-east-1 | \
        helm registry login --username AWS --password-stdin public.ecr.aws
    
    # Install S3 controller
    print_status "Installing S3 ACK controller..."
    S3_VERSION=$(curl -sL https://api.github.com/repos/aws-controllers-k8s/s3-controller/releases/latest | \
        jq -r '.tag_name | ltrimstr("v")')
    
    helm upgrade --install ack-s3-controller \
        oci://public.ecr.aws/aws-controllers-k8s/s3-chart \
        --version="$S3_VERSION" \
        --namespace "$ACK_SYSTEM_NAMESPACE" \
        --create-namespace \
        --set aws.region="$AWS_REGION" \
        --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$ACK_ROLE_ARN" \
        --wait
    
    # Install IAM controller
    print_status "Installing IAM ACK controller..."
    IAM_VERSION=$(curl -sL https://api.github.com/repos/aws-controllers-k8s/iam-controller/releases/latest | \
        jq -r '.tag_name | ltrimstr("v")')
    
    helm upgrade --install ack-iam-controller \
        oci://public.ecr.aws/aws-controllers-k8s/iam-chart \
        --version="$IAM_VERSION" \
        --namespace "$ACK_SYSTEM_NAMESPACE" \
        --set aws.region="$AWS_REGION" \
        --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$ACK_ROLE_ARN" \
        --wait
    
    # Install Lambda controller
    print_status "Installing Lambda ACK controller..."
    LAMBDA_VERSION=$(curl -sL https://api.github.com/repos/aws-controllers-k8s/lambda-controller/releases/latest | \
        jq -r '.tag_name | ltrimstr("v")')
    
    helm upgrade --install ack-lambda-controller \
        oci://public.ecr.aws/aws-controllers-k8s/lambda-chart \
        --version="$LAMBDA_VERSION" \
        --namespace "$ACK_SYSTEM_NAMESPACE" \
        --set aws.region="$AWS_REGION" \
        --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="$ACK_ROLE_ARN" \
        --wait
    
    print_success "ACK controllers installed successfully"
}

# Verify ACK controller deployment
verify_ack_deployment() {
    print_status "Verifying ACK controller deployment..."
    
    # Wait for pods to be ready
    print_status "Waiting for ACK controller pods to be ready..."
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=s3-chart \
        -n "$ACK_SYSTEM_NAMESPACE" --timeout=300s
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=iam-chart \
        -n "$ACK_SYSTEM_NAMESPACE" --timeout=300s
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=lambda-chart \
        -n "$ACK_SYSTEM_NAMESPACE" --timeout=300s
    
    # Display pod status
    print_status "ACK controller pod status:"
    kubectl get pods -n "$ACK_SYSTEM_NAMESPACE"
    
    # Check CRDs are installed
    print_status "Checking ACK CRDs..."
    kubectl get crd | grep -E "(buckets|roles|functions).*k8s.aws" || true
    
    print_success "ACK controller verification completed"
}

# Create custom Application CRD
create_custom_crd() {
    print_status "Creating custom Application CRD..."
    
    cat > /tmp/application-crd.yaml << 'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: applications.platform.example.com
spec:
  group: platform.example.com
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              name:
                type: string
              environment:
                type: string
                enum: ["dev", "staging", "prod"]
              storageClass:
                type: string
                default: "STANDARD"
              lambdaRuntime:
                type: string
                default: "python3.9"
              enableLogging:
                type: boolean
                default: true
          status:
            type: object
            properties:
              phase:
                type: string
              bucketName:
                type: string
              roleArn:
                type: string
              functionName:
                type: string
              message:
                type: string
  scope: Namespaced
  names:
    plural: applications
    singular: application
    kind: Application
EOF
    
    kubectl apply -f /tmp/application-crd.yaml
    print_success "Custom Application CRD created"
}

# Create test application
create_test_application() {
    print_status "Creating test application..."
    
    cat > /tmp/test-application.yaml << EOF
apiVersion: platform.example.com/v1
kind: Application
metadata:
  name: sample-app
  namespace: default
spec:
  name: sample-app
  environment: dev
  storageClass: STANDARD
  lambdaRuntime: python3.9
  enableLogging: true
EOF
    
    kubectl apply -f /tmp/test-application.yaml
    print_status "Test application created. Note: Full operator reconciliation requires custom operator deployment."
}

# Create deployment summary
create_deployment_summary() {
    print_status "Creating deployment summary..."
    
    cat > "${SCRIPT_DIR}/deployment-summary.txt" << EOF
Kubernetes Operators for AWS Resources - Deployment Summary
=========================================================

Deployment Date: $(date)
AWS Region: $AWS_REGION
AWS Account ID: $AWS_ACCOUNT_ID
Resource Suffix: $RESOURCE_SUFFIX

EKS Cluster:
- Name: $CLUSTER_NAME
- Version: 1.28
- Node Group: ack-operators-nodes

ACK Controllers Installed:
- S3 Controller: $S3_VERSION
- IAM Controller: $IAM_VERSION
- Lambda Controller: $LAMBDA_VERSION

IAM Resources:
- ACK Controller Role: ACK-Controller-Role-${RESOURCE_SUFFIX}
- EKS Service Role: eks-service-role-${RESOURCE_SUFFIX}
- Node Group Role: eks-node-role-${RESOURCE_SUFFIX}

Custom Resources:
- Application CRD: applications.platform.example.com

Next Steps:
1. Deploy custom operator using operator-sdk
2. Create Application resources to test functionality
3. Implement monitoring and observability
4. Set up GitOps workflows

Access Commands:
- kubectl config current-context
- kubectl get pods -n $ACK_SYSTEM_NAMESPACE
- kubectl get applications

Cleanup:
- Run ./destroy.sh to remove all resources
EOF
    
    print_success "Deployment summary saved to deployment-summary.txt"
}

# Main deployment function
main() {
    print_banner
    log_info "Starting deployment at $TIMESTAMP"
    
    check_prerequisites
    generate_resource_suffix
    setup_eks_cluster
    setup_oidc_and_iam
    install_ack_controllers
    verify_ack_deployment
    create_custom_crd
    create_test_application
    create_deployment_summary
    
    print_success "Deployment completed successfully!"
    print_status "Check deployment-summary.txt for details and next steps."
    print_status "Log file: $LOG_FILE"
    
    # Clean up temporary files
    rm -f /tmp/eks-trust-policy.json /tmp/node-trust-policy.json \
          /tmp/ack-trust-policy.json /tmp/application-crd.yaml \
          /tmp/test-application.yaml
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi