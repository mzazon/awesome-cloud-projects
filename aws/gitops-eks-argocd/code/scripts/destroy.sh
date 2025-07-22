#!/bin/bash

# GitOps Workflows EKS with ArgoCD and CodeCommit - Cleanup Script
# This script safely removes all resources created by the deployment script:
# - ArgoCD applications and configurations
# - AWS Load Balancer Controller and associated resources
# - EKS cluster and managed node groups
# - CodeCommit repository
# - IAM roles and policies

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
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

# Error handling (non-fatal for cleanup)
error_continue() {
    log "ERROR" "$1"
    echo -e "${RED}❌ Error (continuing): $1${NC}"
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

# Get deployment state
get_state() {
    local key=$1
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        grep "^${key}=" "${DEPLOYMENT_STATE_FILE}" | cut -d'=' -f2 || echo ""
    else
        echo ""
    fi
}

# Check if resource exists before deletion
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-}
    
    if [[ -n "${namespace}" ]]; then
        kubectl get "${resource_type}" "${resource_name}" -n "${namespace}" &>/dev/null
    else
        kubectl get "${resource_type}" "${resource_name}" &>/dev/null
    fi
}

# Confirm deletion with user
confirm_deletion() {
    local resource_type=$1
    local resource_name=$2
    
    echo -e "${YELLOW}⚠️  About to delete ${resource_type}: ${resource_name}${NC}"
    
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        info "Force delete enabled, proceeding..."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Deletion cancelled by user"
        return 1
    fi
    return 0
}

# Banner
echo -e "${RED}"
cat << "EOF"
   ______ _  _    ____                 _____ _                             
  |  ____(_)| |  / __ \               / ____| |                            
  | |__   _ | |_| |  | |_ __  ___     | |    | | ___  __ _ _ __  _   _ _ __  
  |  __| | || __| |  | | '_ \/ __|    | |    | |/ _ \/ _` | '_ \| | | | '_ \ 
  | |____| || |_| |__| | |_) \__ \    | |____| |  __/ (_| | | | | |_| | |_) |
  |______|_| \__|\____/| .__/|___/     \_____|_|\___|\__,_|_| |_|\__,_| .__/ 
                       | |                                           | |    
                       |_|                                           |_|    

GitOps Infrastructure Cleanup
EOF
echo -e "${NC}"

# Initialize log file
echo "Starting GitOps cleanup at $(date)" > "${LOG_FILE}"
info "Cleanup started at $(date)"

# Check for force delete flag
FORCE_DELETE=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE_DELETE=true
    warning "Force delete mode enabled - will not prompt for confirmations"
fi

# Check if deployment state file exists
if [[ ! -f "${DEPLOYMENT_STATE_FILE}" ]]; then
    warning "No deployment state file found. Attempting cleanup based on default naming..."
    warning "Some resources may not be detected automatically."
    echo ""
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Cleanup cancelled"
        exit 0
    fi
fi

# Load deployment configuration
AWS_REGION=$(get_state "AWS_REGION")
CLUSTER_NAME=$(get_state "CLUSTER_NAME")
REPO_NAME=$(get_state "REPO_NAME")
NAMESPACE=$(get_state "NAMESPACE")
RANDOM_SUFFIX=$(get_state "RANDOM_SUFFIX")

# Set defaults if not found in state file
if [[ -z "${AWS_REGION}" ]]; then
    AWS_REGION=$(aws configure get region || echo "us-east-1")
    warning "Using default/configured region: ${AWS_REGION}"
fi

if [[ -z "${CLUSTER_NAME}" ]]; then
    warning "Cluster name not found in state file"
    read -p "Enter EKS cluster name to delete: " CLUSTER_NAME
    if [[ -z "${CLUSTER_NAME}" ]]; then
        error_continue "No cluster name provided"
        exit 1
    fi
fi

if [[ -z "${REPO_NAME}" ]]; then
    warning "Repository name not found in state file"
    read -p "Enter CodeCommit repository name to delete (or press Enter to skip): " REPO_NAME
fi

if [[ -z "${NAMESPACE}" ]]; then
    NAMESPACE="argocd"
    warning "Using default ArgoCD namespace: ${NAMESPACE}"
fi

info "Cleanup configuration:"
info "  AWS Region: ${AWS_REGION}"
info "  EKS Cluster: ${CLUSTER_NAME}"
info "  CodeCommit Repo: ${REPO_NAME:-[skipped]}"
info "  ArgoCD Namespace: ${NAMESPACE}"

# Final confirmation
echo ""
echo -e "${RED}🚨 WARNING: This will permanently delete all GitOps infrastructure! 🚨${NC}"
echo ""
if ! confirm_deletion "GitOps Infrastructure" "All resources"; then
    info "Cleanup cancelled"
    exit 0
fi

echo ""
info "Starting resource cleanup..."

# Step 1: Delete ArgoCD Applications
info "Step 1: Removing ArgoCD applications..."
if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
    # Delete all applications first to prevent them from managing resources
    if kubectl get applications -n "${NAMESPACE}" &>/dev/null; then
        info "Deleting ArgoCD applications..."
        kubectl delete applications --all -n "${NAMESPACE}" --timeout=300s || \
            error_continue "Failed to delete ArgoCD applications"
        success "ArgoCD applications deleted"
    else
        info "No ArgoCD applications found"
    fi
    
    # Wait for applications to be fully removed
    sleep 30
else
    info "ArgoCD namespace not found, skipping application cleanup"
fi

# Step 2: Delete Sample Application Resources
info "Step 2: Removing sample application resources..."
if kubectl get namespace default &>/dev/null; then
    # Delete sample app resources in default namespace
    kubectl delete deployment sample-app --ignore-not-found=true || true
    kubectl delete service sample-app-service --ignore-not-found=true || true
    success "Sample application resources removed"
else
    info "Default namespace not accessible, skipping sample app cleanup"
fi

# Step 3: Delete ArgoCD Ingress and Load Balancer
info "Step 3: Removing ArgoCD Ingress and Load Balancer..."
if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
    # Delete ingress first to remove ALB
    if resource_exists ingress argocd-server-ingress "${NAMESPACE}"; then
        info "Deleting ArgoCD Ingress (this will remove the Application Load Balancer)..."
        kubectl delete ingress argocd-server-ingress -n "${NAMESPACE}" --timeout=600s || \
            error_continue "Failed to delete ArgoCD Ingress"
        
        # Wait for ALB to be fully removed
        info "Waiting for Application Load Balancer to be removed..."
        sleep 60
        success "ArgoCD Ingress and ALB removed"
    else
        info "ArgoCD Ingress not found"
    fi
else
    info "ArgoCD namespace not found, skipping Ingress cleanup"
fi

# Step 4: Uninstall AWS Load Balancer Controller
info "Step 4: Removing AWS Load Balancer Controller..."
if kubectl get namespace kube-system &>/dev/null; then
    # Check if helm is available and ALB controller is installed
    if command -v helm &>/dev/null; then
        if helm list -n kube-system | grep -q aws-load-balancer-controller; then
            info "Uninstalling AWS Load Balancer Controller..."
            helm uninstall aws-load-balancer-controller -n kube-system --timeout=300s || \
                error_continue "Failed to uninstall AWS Load Balancer Controller"
            success "AWS Load Balancer Controller uninstalled"
        else
            info "AWS Load Balancer Controller not found in Helm releases"
        fi
    else
        warning "Helm not available, skipping ALB controller uninstall"
    fi
    
    # Delete service account if it exists
    if resource_exists serviceaccount aws-load-balancer-controller kube-system; then
        kubectl delete serviceaccount aws-load-balancer-controller -n kube-system || \
            error_continue "Failed to delete ALB controller service account"
    fi
else
    info "kube-system namespace not accessible, skipping ALB controller cleanup"
fi

# Step 5: Delete ArgoCD Installation
info "Step 5: Removing ArgoCD installation..."
if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
    info "Deleting ArgoCD namespace and all components..."
    kubectl delete namespace "${NAMESPACE}" --timeout=600s || \
        error_continue "Failed to delete ArgoCD namespace"
    
    # Wait for namespace to be fully removed
    local attempts=0
    local max_attempts=20
    while [[ $attempts -lt $max_attempts ]]; do
        if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
            break
        fi
        attempts=$((attempts + 1))
        info "Waiting for ArgoCD namespace deletion... (attempt ${attempts}/${max_attempts})"
        sleep 15
    done
    
    success "ArgoCD installation removed"
else
    info "ArgoCD namespace not found"
fi

# Step 6: Delete EKS Cluster
info "Step 6: Removing EKS cluster..."
if eksctl get cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" &>/dev/null; then
    if confirm_deletion "EKS Cluster" "${CLUSTER_NAME}"; then
        info "Deleting EKS cluster (this may take 15-20 minutes)..."
        eksctl delete cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --timeout=30m || \
            error_continue "Failed to delete EKS cluster"
        success "EKS cluster deleted"
    else
        info "EKS cluster deletion skipped"
    fi
else
    info "EKS cluster not found or not accessible"
fi

# Step 7: Clean up IAM Resources
info "Step 7: Cleaning up IAM resources..."

# Delete IAM role for ALB controller if it exists
if [[ -n "${RANDOM_SUFFIX}" ]]; then
    ROLE_NAME="AmazonEKSLoadBalancerControllerRole-${RANDOM_SUFFIX}"
    if aws iam get-role --role-name "${ROLE_NAME}" &>/dev/null; then
        info "Deleting IAM role: ${ROLE_NAME}"
        
        # Detach policies first
        aws iam detach-role-policy \
            --role-name "${ROLE_NAME}" \
            --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy" \
            &>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "${ROLE_NAME}" || \
            error_continue "Failed to delete IAM role: ${ROLE_NAME}"
        success "IAM role deleted: ${ROLE_NAME}"
    else
        info "IAM role not found: ${ROLE_NAME}"
    fi
fi

# Note about shared IAM policy
if aws iam get-policy --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy" &>/dev/null; then
    warning "IAM policy 'AWSLoadBalancerControllerIAMPolicy' still exists"
    warning "This policy may be shared with other ALB controllers"
    warning "Delete manually if no longer needed: aws iam delete-policy --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy"
fi

# Step 8: Delete CodeCommit Repository
if [[ -n "${REPO_NAME}" ]]; then
    info "Step 8: Removing CodeCommit repository..."
    if aws codecommit get-repository --repository-name "${REPO_NAME}" &>/dev/null; then
        if confirm_deletion "CodeCommit Repository" "${REPO_NAME}"; then
            aws codecommit delete-repository --repository-name "${REPO_NAME}" || \
                error_continue "Failed to delete CodeCommit repository"
            success "CodeCommit repository deleted: ${REPO_NAME}"
        else
            info "CodeCommit repository deletion skipped"
        fi
    else
        info "CodeCommit repository not found: ${REPO_NAME}"
    fi
else
    info "Step 8: Skipping CodeCommit repository cleanup (name not provided)"
fi

# Step 9: Clean up local files
info "Step 9: Cleaning up local files..."

# Remove kubeconfig context if it exists
if kubectl config get-contexts | grep -q "${CLUSTER_NAME}"; then
    kubectl config delete-context "arn:aws:eks:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):cluster/${CLUSTER_NAME}" || \
        error_continue "Failed to remove kubeconfig context"
    success "Kubeconfig context removed"
fi

# Clean up temporary files
rm -f /tmp/iam_policy.json /tmp/argocd-ingress.yaml /tmp/sample-app.yaml

# Clean up deployment state file
if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
    if confirm_deletion "Deployment State File" "${DEPLOYMENT_STATE_FILE}"; then
        rm -f "${DEPLOYMENT_STATE_FILE}"
        success "Deployment state file removed"
    else
        info "Deployment state file preserved"
    fi
fi

success "Local files cleaned up"

# Final verification
info "Performing final verification..."

# Check if cluster still exists
if eksctl get cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" &>/dev/null; then
    warning "EKS cluster still exists: ${CLUSTER_NAME}"
else
    success "EKS cluster successfully removed"
fi

# Check if repository still exists
if [[ -n "${REPO_NAME}" ]] && aws codecommit get-repository --repository-name "${REPO_NAME}" &>/dev/null; then
    warning "CodeCommit repository still exists: ${REPO_NAME}"
else
    if [[ -n "${REPO_NAME}" ]]; then
        success "CodeCommit repository successfully removed"
    fi
fi

# Display cleanup summary
echo ""
echo -e "${GREEN}🧹 GitOps Infrastructure Cleanup Complete! 🧹${NC}"
echo ""
echo "Cleanup Summary:"
echo "==============="
echo "✅ ArgoCD applications removed"
echo "✅ Sample application resources removed"
echo "✅ ArgoCD Ingress and ALB removed"
echo "✅ AWS Load Balancer Controller uninstalled"
echo "✅ ArgoCD installation removed"
echo "✅ EKS cluster removed (if confirmed)"
echo "✅ IAM roles cleaned up"
echo "✅ CodeCommit repository removed (if confirmed)"
echo "✅ Local files cleaned up"

echo ""
echo "Notes:"
echo "======"
if aws iam get-policy --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy" &>/dev/null; then
    echo "⚠️  IAM policy 'AWSLoadBalancerControllerIAMPolicy' still exists (may be shared)"
fi

echo "ℹ️  Check AWS console to verify all resources have been removed"
echo "ℹ️  Review CloudWatch logs for any remaining log groups"
echo "ℹ️  Check for any remaining ALB/NLB resources that may incur charges"

echo ""
success "Cleanup completed successfully!"
log "INFO" "Cleanup completed at $(date)"

exit 0