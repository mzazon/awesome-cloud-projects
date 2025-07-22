#!/bin/bash

# GitOps Workflows EKS with ArgoCD and CodeCommit - Deployment Script
# This script deploys a complete GitOps infrastructure using:
# - Amazon EKS cluster for container orchestration
# - ArgoCD for GitOps workflow management
# - AWS CodeCommit for Git repository hosting
# - Application Load Balancer for ArgoCD access

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    echo -e "${RED}❌ Deployment failed: $1${NC}"
    exit 1
}

# Success logging
success() {
    log "INFO" "$1"
    echo -e "${GREEN}✅ $1${NC}"
}

# Warning logging
warning() {
    log "WARN" "$1"
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Info logging
info() {
    log "INFO" "$1"
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Save deployment state
save_state() {
    local key=$1
    local value=$2
    echo "${key}=${value}" >> "${DEPLOYMENT_STATE_FILE}"
}

# Get deployment state
get_state() {
    local key=$1
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        grep "^${key}=" "${DEPLOYMENT_STATE_FILE}" | cut -d'=' -f2 || echo ""
    else
        echo ""
    fi
}

# Cleanup function for partial deployments
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        warning "Deployment failed. Resources may have been partially created."
        warning "Run './destroy.sh' to clean up any created resources."
        warning "Check the log file for details: ${LOG_FILE}"
    fi
}

trap cleanup_on_exit EXIT

# Banner
echo -e "${BLUE}"
cat << "EOF"
   ______ _  _    ____                 _____            _       _       
  |  ____(_)| |  / __ \               / ____|          (_)     | |      
  | |__   _ | |_| |  | |_ __  ___     | (___   ___ _ __ _ _ __ | |_ ___ 
  |  __| | || __| |  | | '_ \/ __|     \___ \ / __| '__| | '_ \| __/ __|
  | |____| || |_| |__| | |_) \__ \     ____) | (__| |  | | |_) | |_\__ \
  |______|_| \__|\____/| .__/|___/    |_____/ \___|_|  |_| .__/ \__|___/
                       | |                              | |            
                       |_|                              |_|            

GitOps Workflows with EKS, ArgoCD, and CodeCommit
EOF
echo -e "${NC}"

# Initialize log file
echo "Starting GitOps deployment at $(date)" > "${LOG_FILE}"
info "Deployment started at $(date)"

# Check if this is a dry run
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    info "Running in DRY RUN mode - no resources will be created"
fi

# Prerequisites check
info "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI is not installed. Please install AWS CLI v2."
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error_exit "AWS credentials not configured. Please run 'aws configure' first."
fi

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    error_exit "kubectl is not installed. Please install kubectl."
fi

# Check eksctl
if ! command -v eksctl &> /dev/null; then
    error_exit "eksctl is not installed. Please install eksctl."
fi

# Check helm
if ! command -v helm &> /dev/null; then
    error_exit "helm is not installed. Please install Helm CLI."
fi

# Check git
if ! command -v git &> /dev/null; then
    error_exit "git is not installed. Please install Git."
fi

# Verify prerequisite versions
aws_version=$(aws --version | cut -d' ' -f1 | cut -d'/' -f2)
kubectl_version=$(kubectl version --client --short 2>/dev/null | grep -o 'v[0-9]\+\.[0-9]\+' | head -1)
eksctl_version=$(eksctl version)
helm_version=$(helm version --short | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+')

info "AWS CLI version: ${aws_version}"
info "kubectl version: ${kubectl_version}"
info "eksctl version: ${eksctl_version}"
info "helm version: ${helm_version}"

success "Prerequisites check completed"

# Set environment variables
export AWS_REGION=$(aws configure get region)
if [[ -z "${AWS_REGION}" ]]; then
    AWS_REGION="us-east-1"
    warning "No region configured, defaulting to ${AWS_REGION}"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources if not already set
EXISTING_SUFFIX=$(get_state "RANDOM_SUFFIX")
if [[ -n "${EXISTING_SUFFIX}" ]]; then
    RANDOM_SUFFIX="${EXISTING_SUFFIX}"
    info "Using existing deployment suffix: ${RANDOM_SUFFIX}"
else
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    save_state "RANDOM_SUFFIX" "${RANDOM_SUFFIX}"
    info "Generated new deployment suffix: ${RANDOM_SUFFIX}"
fi

export CLUSTER_NAME="gitops-cluster-${RANDOM_SUFFIX}"
export REPO_NAME="gitops-config-${RANDOM_SUFFIX}"
export NAMESPACE="argocd"

info "Deployment configuration:"
info "  AWS Region: ${AWS_REGION}"
info "  AWS Account: ${AWS_ACCOUNT_ID}"
info "  EKS Cluster: ${CLUSTER_NAME}"
info "  CodeCommit Repo: ${REPO_NAME}"
info "  ArgoCD Namespace: ${NAMESPACE}"

save_state "AWS_REGION" "${AWS_REGION}"
save_state "CLUSTER_NAME" "${CLUSTER_NAME}"
save_state "REPO_NAME" "${REPO_NAME}"
save_state "NAMESPACE" "${NAMESPACE}"

if [[ "${DRY_RUN}" == "true" ]]; then
    info "DRY RUN: Would create resources with the above configuration"
    exit 0
fi

# Step 1: Create EKS Cluster
info "Step 1: Creating EKS cluster..."
EXISTING_CLUSTER=$(get_state "EKS_CREATED")
if [[ "${EXISTING_CLUSTER}" == "true" ]]; then
    info "EKS cluster already exists, skipping creation"
else
    info "Creating EKS cluster with managed node group..."
    
    # Check if cluster already exists
    if eksctl get cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" &>/dev/null; then
        warning "Cluster ${CLUSTER_NAME} already exists"
        save_state "EKS_CREATED" "true"
    else
        eksctl create cluster \
            --name "${CLUSTER_NAME}" \
            --region "${AWS_REGION}" \
            --nodegroup-name workers \
            --node-type t3.medium \
            --nodes 2 \
            --nodes-min 1 \
            --nodes-max 4 \
            --managed \
            --timeout 30m || error_exit "Failed to create EKS cluster"
        
        save_state "EKS_CREATED" "true"
    fi
    
    # Update kubeconfig
    aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}" || \
        error_exit "Failed to update kubeconfig"
    
    # Verify cluster is ready
    info "Verifying cluster readiness..."
    kubectl get nodes || error_exit "Failed to connect to EKS cluster"
    
    success "EKS cluster created and configured successfully"
fi

# Step 2: Create CodeCommit Repository
info "Step 2: Creating CodeCommit repository..."
EXISTING_REPO=$(get_state "CODECOMMIT_CREATED")
if [[ "${EXISTING_REPO}" == "true" ]]; then
    info "CodeCommit repository already exists, skipping creation"
else
    # Check if repository already exists
    if aws codecommit get-repository --repository-name "${REPO_NAME}" &>/dev/null; then
        warning "Repository ${REPO_NAME} already exists"
        save_state "CODECOMMIT_CREATED" "true"
    else
        aws codecommit create-repository \
            --repository-name "${REPO_NAME}" \
            --repository-description "GitOps configuration repository for EKS deployments" || \
            error_exit "Failed to create CodeCommit repository"
        
        save_state "CODECOMMIT_CREATED" "true"
    fi
    
    # Get repository clone URL
    REPO_URL=$(aws codecommit get-repository \
        --repository-name "${REPO_NAME}" \
        --query 'repositoryMetadata.cloneUrlHttp' \
        --output text) || error_exit "Failed to get repository URL"
    
    save_state "REPO_URL" "${REPO_URL}"
    success "CodeCommit repository created: ${REPO_URL}"
fi

# Step 3: Install ArgoCD
info "Step 3: Installing ArgoCD on EKS cluster..."
EXISTING_ARGOCD=$(get_state "ARGOCD_INSTALLED")
if [[ "${EXISTING_ARGOCD}" == "true" ]]; then
    info "ArgoCD already installed, skipping installation"
else
    # Create ArgoCD namespace
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - || \
        error_exit "Failed to create ArgoCD namespace"
    
    # Install ArgoCD using official manifests
    info "Installing ArgoCD components..."
    kubectl apply -n "${NAMESPACE}" -f \
        https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml || \
        error_exit "Failed to install ArgoCD"
    
    # Wait for ArgoCD components to be ready
    info "Waiting for ArgoCD components to be ready (this may take several minutes)..."
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=argocd-server \
        -n "${NAMESPACE}" --timeout=600s || \
        error_exit "ArgoCD components failed to become ready"
    
    save_state "ARGOCD_INSTALLED" "true"
    success "ArgoCD installed and running in ${NAMESPACE} namespace"
fi

# Step 4: Install AWS Load Balancer Controller
info "Step 4: Installing AWS Load Balancer Controller..."
EXISTING_ALB=$(get_state "ALB_CONTROLLER_INSTALLED")
if [[ "${EXISTING_ALB}" == "true" ]]; then
    info "AWS Load Balancer Controller already installed, skipping installation"
else
    # Download IAM policy
    info "Downloading AWS Load Balancer Controller IAM policy..."
    curl -s -o /tmp/iam_policy.json \
        https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/install/iam_policy.json || \
        error_exit "Failed to download IAM policy"
    
    # Create IAM policy (ignore error if already exists)
    aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy \
        --policy-document file:///tmp/iam_policy.json &>/dev/null || \
        info "IAM policy already exists, continuing..."
    
    # Create service account for ALB controller
    info "Creating IAM service account for ALB controller..."
    eksctl create iamserviceaccount \
        --cluster="${CLUSTER_NAME}" \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --role-name="AmazonEKSLoadBalancerControllerRole-${RANDOM_SUFFIX}" \
        --attach-policy-arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" \
        --approve \
        --override-existing-serviceaccounts || \
        error_exit "Failed to create ALB controller service account"
    
    # Add EKS Helm repository
    helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
    helm repo update || error_exit "Failed to update Helm repositories"
    
    # Install ALB controller using Helm
    info "Installing AWS Load Balancer Controller via Helm..."
    helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName="${CLUSTER_NAME}" \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller \
        --wait --timeout=10m || \
        error_exit "Failed to install AWS Load Balancer Controller"
    
    save_state "ALB_CONTROLLER_INSTALLED" "true"
    success "AWS Load Balancer Controller installed successfully"
fi

# Step 5: Create Ingress for ArgoCD
info "Step 5: Creating Ingress for ArgoCD server access..."
EXISTING_INGRESS=$(get_state "ARGOCD_INGRESS_CREATED")
if [[ "${EXISTING_INGRESS}" == "true" ]]; then
    info "ArgoCD Ingress already created, skipping creation"
else
    # Create ArgoCD Ingress manifest
    cat > /tmp/argocd-ingress.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: ${NAMESPACE}
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/backend-protocol: HTTPS
    alb.ingress.kubernetes.io/healthcheck-protocol: HTTPS
    alb.ingress.kubernetes.io/healthcheck-path: /healthz
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 443
EOF
    
    # Apply the Ingress
    kubectl apply -f /tmp/argocd-ingress.yaml || \
        error_exit "Failed to create ArgoCD Ingress"
    
    # Wait for ALB to be provisioned
    info "Waiting for Application Load Balancer to be provisioned (this may take 5-10 minutes)..."
    sleep 30
    
    # Get ALB hostname (retry logic)
    local attempts=0
    local max_attempts=20
    while [[ $attempts -lt $max_attempts ]]; do
        ALB_HOSTNAME=$(kubectl get ingress argocd-server-ingress \
            -n "${NAMESPACE}" \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        
        if [[ -n "${ALB_HOSTNAME}" ]]; then
            break
        fi
        
        attempts=$((attempts + 1))
        info "Waiting for ALB hostname... (attempt ${attempts}/${max_attempts})"
        sleep 30
    done
    
    if [[ -z "${ALB_HOSTNAME}" ]]; then
        warning "ALB hostname not available yet. Check status with: kubectl get ingress -n ${NAMESPACE}"
    else
        save_state "ALB_HOSTNAME" "${ALB_HOSTNAME}"
        success "ArgoCD accessible at: https://${ALB_HOSTNAME}"
    fi
    
    save_state "ARGOCD_INGRESS_CREATED" "true"
fi

# Step 6: Configure ArgoCD and get admin password
info "Step 6: Configuring ArgoCD access..."
EXISTING_ARGOCD_CONFIG=$(get_state "ARGOCD_CONFIGURED")
if [[ "${EXISTING_ARGOCD_CONFIG}" == "true" ]]; then
    info "ArgoCD already configured, skipping configuration"
else
    # Configure ArgoCD for insecure access (required for ALB)
    kubectl patch configmap argocd-cmd-params-cm \
        -n "${NAMESPACE}" \
        --type merge \
        -p '{"data":{"server.insecure":"true"}}' || \
        error_exit "Failed to configure ArgoCD for insecure access"
    
    # Restart ArgoCD server to apply changes
    kubectl rollout restart deployment argocd-server -n "${NAMESPACE}" || \
        error_exit "Failed to restart ArgoCD server"
    
    kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=argocd-server \
        -n "${NAMESPACE}" --timeout=300s || \
        error_exit "ArgoCD server failed to restart"
    
    # Get ArgoCD admin password
    ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
        -n "${NAMESPACE}" \
        -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "")
    
    if [[ -z "${ARGOCD_PASSWORD}" ]]; then
        warning "ArgoCD admin password not available yet"
    else
        save_state "ARGOCD_PASSWORD" "${ARGOCD_PASSWORD}"
    fi
    
    save_state "ARGOCD_CONFIGURED" "true"
    success "ArgoCD configured successfully"
fi

# Step 7: Initialize GitOps Repository Structure
info "Step 7: Initializing GitOps repository structure..."
EXISTING_REPO_INIT=$(get_state "REPO_INITIALIZED")
if [[ "${EXISTING_REPO_INIT}" == "true" ]]; then
    info "Repository already initialized, skipping initialization"
else
    REPO_URL=$(get_state "REPO_URL")
    
    # Create temporary directory for Git operations
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Clone the CodeCommit repository
    info "Cloning repository ${REPO_URL}..."
    git clone "${REPO_URL}" gitops-repo || error_exit "Failed to clone repository"
    cd gitops-repo
    
    # Configure Git credentials
    git config user.name "GitOps Admin"
    git config user.email "admin@example.com"
    
    # Create GitOps directory structure
    mkdir -p {applications,environments}/{development,staging,production}
    mkdir -p manifests/base
    
    # Create initial application manifest
    cat > applications/development/sample-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app
  namespace: ${NAMESPACE}
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: HEAD
    path: manifests/base
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
    
    # Create sample application manifests
    cat > manifests/base/deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  labels:
    app: sample-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
    spec:
      containers:
      - name: nginx
        image: nginx:1.21
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
EOF
    
    cat > manifests/base/service.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: sample-app-service
spec:
  selector:
    app: sample-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: ClusterIP
EOF
    
    # Create Kustomization file
    cat > manifests/base/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
EOF
    
    # Create README
    cat > README.md << EOF
# GitOps Configuration Repository

This repository contains the GitOps configuration for the EKS cluster: ${CLUSTER_NAME}

## Structure

- \`applications/\` - ArgoCD Application definitions
- \`environments/\` - Environment-specific configurations
- \`manifests/\` - Kubernetes manifests organized by application

## Usage

1. Make changes to the Kubernetes manifests
2. Commit and push to this repository
3. ArgoCD will automatically detect and sync changes to the cluster

## ArgoCD Access

- URL: https://${ALB_HOSTNAME:-TBD}
- Username: admin
- Password: Use \`kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d\`
EOF
    
    # Commit and push initial configuration
    git add .
    git commit -m "Initial GitOps configuration

- ArgoCD application definition for development environment
- Sample NGINX deployment with resource limits
- Service configuration for internal access
- Kustomization structure for configuration management"
    
    git push origin main || error_exit "Failed to push initial configuration"
    
    # Cleanup temporary directory
    cd "${SCRIPT_DIR}"
    rm -rf "${TEMP_DIR}"
    
    save_state "REPO_INITIALIZED" "true"
    success "GitOps repository structure created and initialized"
fi

# Step 8: Deploy Sample Application
info "Step 8: Deploying sample application via ArgoCD..."
EXISTING_APP=$(get_state "SAMPLE_APP_DEPLOYED")
if [[ "${EXISTING_APP}" == "true" ]]; then
    info "Sample application already deployed, skipping deployment"
else
    # Apply the ArgoCD application manifest from the repository
    REPO_URL=$(get_state "REPO_URL")
    
    # Create temporary application manifest
    cat > /tmp/sample-app.yaml << EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app
  namespace: ${NAMESPACE}
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: HEAD
    path: manifests/base
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
    
    kubectl apply -f /tmp/sample-app.yaml || \
        error_exit "Failed to create ArgoCD application"
    
    # Wait for application to sync
    info "Waiting for application to sync and deploy..."
    sleep 30
    
    # Check application status
    kubectl get applications -n "${NAMESPACE}" || \
        warning "Could not get application status"
    
    # Verify application deployment
    local attempts=0
    local max_attempts=10
    while [[ $attempts -lt $max_attempts ]]; do
        if kubectl get pods -l app=sample-app 2>/dev/null | grep -q Running; then
            break
        fi
        attempts=$((attempts + 1))
        info "Waiting for sample application pods... (attempt ${attempts}/${max_attempts})"
        sleep 30
    done
    
    save_state "SAMPLE_APP_DEPLOYED" "true"
    success "Sample application deployed via GitOps workflow"
fi

# Final validation and summary
info "Performing final validation..."

# Check cluster status
kubectl get nodes || warning "Could not verify cluster nodes"

# Check ArgoCD components
kubectl get pods -n "${NAMESPACE}" || warning "Could not verify ArgoCD components"

# Check application
kubectl get pods -l app=sample-app || warning "Could not verify sample application"

# Display summary
echo ""
echo -e "${GREEN}🎉 GitOps Infrastructure Deployment Complete! 🎉${NC}"
echo ""
echo "Deployment Summary:"
echo "=================="
echo "• EKS Cluster: ${CLUSTER_NAME}"
echo "• AWS Region: ${AWS_REGION}"
echo "• CodeCommit Repository: ${REPO_NAME}"
echo "• ArgoCD Namespace: ${NAMESPACE}"

ALB_HOSTNAME=$(get_state "ALB_HOSTNAME")
if [[ -n "${ALB_HOSTNAME}" ]]; then
    echo "• ArgoCD URL: https://${ALB_HOSTNAME}"
else
    echo "• ArgoCD URL: Get with 'kubectl get ingress -n ${NAMESPACE}'"
fi

ARGOCD_PASSWORD=$(get_state "ARGOCD_PASSWORD")
if [[ -n "${ARGOCD_PASSWORD}" ]]; then
    echo "• ArgoCD Username: admin"
    echo "• ArgoCD Password: ${ARGOCD_PASSWORD}"
else
    echo "• ArgoCD Password: Get with 'kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath=\"{.data.password}\" | base64 -d'"
fi

REPO_URL=$(get_state "REPO_URL")
echo "• Git Repository: ${REPO_URL}"

echo ""
echo "Next Steps:"
echo "==========="
echo "1. Access ArgoCD dashboard using the URL and credentials above"
echo "2. Clone the Git repository to make configuration changes"
echo "3. Commit changes to trigger automatic deployments"
echo "4. Monitor application health through ArgoCD dashboard"
echo ""
echo "To clean up resources, run: ./destroy.sh"
echo ""

success "Deployment completed successfully!"
log "INFO" "Deployment completed at $(date)"

# Cleanup temporary files
rm -f /tmp/iam_policy.json /tmp/argocd-ingress.yaml /tmp/sample-app.yaml

exit 0