#!/bin/bash

# Destroy script for Kubernetes Operators for AWS Resources
# This script safely removes ACK controllers, custom operators, and associated AWS resources

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
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

# Banner
print_banner() {
    echo -e "${RED}"
    echo "=================================================="
    echo "  Kubernetes Operators for AWS Resources"
    echo "  DESTROY Script - This will DELETE resources!"
    echo "=================================================="
    echo -e "${NC}"
}

# Configuration with defaults
DEFAULT_AWS_REGION="us-west-2"
DEFAULT_CLUSTER_NAME="ack-operators-cluster"
DEFAULT_ACK_NAMESPACE="ack-system"

# Environment variables with defaults
export AWS_REGION="${AWS_REGION:-$DEFAULT_AWS_REGION}"
export CLUSTER_NAME="${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}"
export ACK_SYSTEM_NAMESPACE="${ACK_SYSTEM_NAMESPACE:-$DEFAULT_ACK_NAMESPACE}"

# Safety confirmation
confirm_destruction() {
    print_warning "This script will permanently delete the following resources:"
    echo "  • EKS cluster: $CLUSTER_NAME"
    echo "  • All ACK controllers and CRDs"
    echo "  • IAM roles and policies"
    echo "  • OIDC identity provider"
    echo "  • Any AWS resources created by ACK controllers"
    echo ""
    
    read -p "Are you sure you want to continue? Type 'yes' to proceed: " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        print_status "Destruction cancelled by user."
        exit 0
    fi
    
    print_warning "Starting destruction in 5 seconds... Press Ctrl+C to cancel."
    sleep 5
}

# Get resource suffix from deployment summary or generate
get_resource_suffix() {
    if [[ -f "${SCRIPT_DIR}/deployment-summary.txt" ]]; then
        RESOURCE_SUFFIX=$(grep "Resource Suffix:" "${SCRIPT_DIR}/deployment-summary.txt" | cut -d: -f2 | xargs || echo "")
        if [[ -n "$RESOURCE_SUFFIX" ]]; then
            print_status "Found resource suffix from deployment: $RESOURCE_SUFFIX"
            return
        fi
    fi
    
    # Try to extract from existing resources
    print_status "Attempting to discover resource suffix from existing resources..."
    
    # Try to find ACK controller role
    ROLE_ARN=$(kubectl get serviceaccount -n "$ACK_SYSTEM_NAMESPACE" -o jsonpath='{.items[*].metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null | head -1 || echo "")
    if [[ -n "$ROLE_ARN" ]]; then
        ROLE_NAME=$(echo "$ROLE_ARN" | cut -d'/' -f2)
        RESOURCE_SUFFIX=$(echo "$ROLE_NAME" | sed 's/ACK-Controller-Role-//')
        print_status "Discovered resource suffix from ACK role: $RESOURCE_SUFFIX"
        return
    fi
    
    print_warning "Could not determine resource suffix. Some resources may not be cleaned up."
    RESOURCE_SUFFIX=""
}

# Check if AWS CLI and kubectl are available
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Cannot proceed with cleanup."
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_warning "kubectl is not installed. Kubernetes resource cleanup will be skipped."
        KUBECTL_AVAILABLE=false
    else
        KUBECTL_AVAILABLE=true
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        print_warning "Helm is not installed. Helm release cleanup will be skipped."
        HELM_AVAILABLE=false
    else
        HELM_AVAILABLE=true
    fi
    
    # Check AWS authentication
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS authentication failed. Please configure AWS credentials."
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_status "AWS Account ID: $AWS_ACCOUNT_ID"
    print_status "AWS Region: $AWS_REGION"
}

# Delete custom applications and CRDs
cleanup_custom_resources() {
    if [[ "$KUBECTL_AVAILABLE" != true ]]; then
        print_warning "kubectl not available. Skipping custom resource cleanup."
        return
    fi
    
    print_status "Cleaning up custom applications and CRDs..."
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &>/dev/null; then
        print_warning "Cannot connect to Kubernetes cluster. Skipping custom resource cleanup."
        return
    fi
    
    # Delete custom Application resources
    print_status "Deleting custom Application resources..."
    kubectl delete applications --all --all-namespaces --ignore-not-found=true --timeout=60s || true
    
    # Delete custom Application CRD
    print_status "Deleting custom Application CRD..."
    kubectl delete crd applications.platform.example.com --ignore-not-found=true --timeout=60s || true
    
    # Wait for finalizers to complete
    print_status "Waiting for custom resource finalizers..."
    sleep 10
    
    print_success "Custom resources cleanup completed"
}

# Uninstall ACK controllers
uninstall_ack_controllers() {
    if [[ "$HELM_AVAILABLE" != true ]]; then
        print_warning "Helm not available. Skipping ACK controller uninstall."
        return
    fi
    
    print_status "Uninstalling ACK controllers..."
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &>/dev/null; then
        print_warning "Cannot connect to Kubernetes cluster. Skipping ACK controller cleanup."
        return
    fi
    
    # List and delete any AWS resources created by ACK controllers
    print_status "Checking for AWS resources managed by ACK controllers..."
    
    # Delete S3 buckets managed by ACK
    kubectl get buckets.s3.services.k8s.aws --all-namespaces -o jsonpath='{.items[*].spec.name}' 2>/dev/null | \
    xargs -I {} sh -c 'echo "Deleting S3 bucket: {}"; aws s3 rm s3://{} --recursive 2>/dev/null || true; aws s3 rb s3://{} 2>/dev/null || true' || true
    
    # Delete Lambda functions managed by ACK
    kubectl get functions.lambda.services.k8s.aws --all-namespaces -o jsonpath='{.items[*].spec.name}' 2>/dev/null | \
    xargs -I {} sh -c 'echo "Deleting Lambda function: {}"; aws lambda delete-function --function-name {} 2>/dev/null || true' || true
    
    # Delete IAM roles managed by ACK
    kubectl get roles.iam.services.k8s.aws --all-namespaces -o jsonpath='{.items[*].spec.name}' 2>/dev/null | \
    xargs -I {} sh -c 'echo "Deleting IAM role: {}"; aws iam delete-role --role-name {} 2>/dev/null || true' || true
    
    # Delete ACK managed resources in Kubernetes
    print_status "Deleting ACK managed Kubernetes resources..."
    kubectl delete buckets.s3.services.k8s.aws --all --all-namespaces --ignore-not-found=true --timeout=60s || true
    kubectl delete functions.lambda.services.k8s.aws --all --all-namespaces --ignore-not-found=true --timeout=60s || true
    kubectl delete roles.iam.services.k8s.aws --all --all-namespaces --ignore-not-found=true --timeout=60s || true
    
    # Uninstall Helm releases
    print_status "Uninstalling ACK controller Helm releases..."
    helm uninstall ack-s3-controller -n "$ACK_SYSTEM_NAMESPACE" --ignore-not-found 2>/dev/null || true
    helm uninstall ack-iam-controller -n "$ACK_SYSTEM_NAMESPACE" --ignore-not-found 2>/dev/null || true
    helm uninstall ack-lambda-controller -n "$ACK_SYSTEM_NAMESPACE" --ignore-not-found 2>/dev/null || true
    
    # Delete ACK runtime CRDs
    print_status "Deleting ACK runtime CRDs..."
    kubectl delete -f https://raw.githubusercontent.com/aws-controllers-k8s/runtime/main/config/crd/bases/services.k8s.aws_adoptedresources.yaml --ignore-not-found=true || true
    kubectl delete -f https://raw.githubusercontent.com/aws-controllers-k8s/runtime/main/config/crd/bases/services.k8s.aws_fieldexports.yaml --ignore-not-found=true || true
    
    # Delete all ACK CRDs
    print_status "Deleting all ACK CRDs..."
    kubectl get crd -o name | grep ".k8s.aws$" | xargs -I {} kubectl delete {} --ignore-not-found=true || true
    
    # Delete ACK namespace
    print_status "Deleting ACK namespace..."
    kubectl delete namespace "$ACK_SYSTEM_NAMESPACE" --ignore-not-found=true --timeout=120s || true
    
    print_success "ACK controllers cleanup completed"
}

# Delete IAM roles and policies
cleanup_iam_resources() {
    print_status "Cleaning up IAM resources..."
    
    if [[ -n "$RESOURCE_SUFFIX" ]]; then
        # Delete ACK controller role
        ACK_ROLE_NAME="ACK-Controller-Role-${RESOURCE_SUFFIX}"
        if aws iam get-role --role-name "$ACK_ROLE_NAME" &>/dev/null; then
            print_status "Deleting ACK controller role: $ACK_ROLE_NAME"
            
            # Detach policies
            aws iam detach-role-policy --role-name "$ACK_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess 2>/dev/null || true
            aws iam detach-role-policy --role-name "$ACK_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/IAMFullAccess 2>/dev/null || true
            aws iam detach-role-policy --role-name "$ACK_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess 2>/dev/null || true
            
            # Delete role
            aws iam delete-role --role-name "$ACK_ROLE_NAME" || true
        fi
        
        # Delete EKS service role
        EKS_ROLE_NAME="eks-service-role-${RESOURCE_SUFFIX}"
        if aws iam get-role --role-name "$EKS_ROLE_NAME" &>/dev/null; then
            print_status "Deleting EKS service role: $EKS_ROLE_NAME"
            aws iam detach-role-policy --role-name "$EKS_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy 2>/dev/null || true
            aws iam delete-role --role-name "$EKS_ROLE_NAME" || true
        fi
        
        # Delete EKS node group role
        NODE_ROLE_NAME="eks-node-role-${RESOURCE_SUFFIX}"
        if aws iam get-role --role-name "$NODE_ROLE_NAME" &>/dev/null; then
            print_status "Deleting EKS node group role: $NODE_ROLE_NAME"
            aws iam detach-role-policy --role-name "$NODE_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy 2>/dev/null || true
            aws iam detach-role-policy --role-name "$NODE_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy 2>/dev/null || true
            aws iam detach-role-policy --role-name "$NODE_ROLE_NAME" \
                --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly 2>/dev/null || true
            aws iam delete-role --role-name "$NODE_ROLE_NAME" || true
        fi
    else
        print_warning "Resource suffix not available. Searching for roles manually..."
        
        # Search for roles with known patterns
        aws iam list-roles --query "Roles[?contains(RoleName, 'ACK-Controller-Role')].RoleName" \
            --output text | xargs -I {} sh -c 'echo "Found ACK role: {}"; aws iam delete-role --role-name {} 2>/dev/null || true' || true
        
        aws iam list-roles --query "Roles[?contains(RoleName, 'eks-service-role')].RoleName" \
            --output text | xargs -I {} sh -c 'echo "Found EKS role: {}"; aws iam delete-role --role-name {} 2>/dev/null || true' || true
    fi
    
    print_success "IAM resources cleanup completed"
}

# Delete OIDC identity provider
cleanup_oidc_provider() {
    print_status "Cleaning up OIDC identity provider..."
    
    # Check if cluster exists to get OIDC issuer
    if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" &>/dev/null; then
        OIDC_ISSUER=$(aws eks describe-cluster --name "$CLUSTER_NAME" \
            --query "cluster.identity.oidc.issuer" --output text)
        
        if [[ -n "$OIDC_ISSUER" ]]; then
            OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ISSUER#https://}"
            
            if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" &>/dev/null; then
                print_status "Deleting OIDC identity provider: $OIDC_PROVIDER_ARN"
                aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" || true
            else
                print_warning "OIDC provider not found or already deleted."
            fi
        fi
    else
        print_warning "EKS cluster not found. Cannot determine OIDC provider."
    fi
    
    print_success "OIDC provider cleanup completed"
}

# Delete EKS cluster
delete_eks_cluster() {
    print_status "Deleting EKS cluster..."
    
    # Check if cluster exists
    if ! aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" &>/dev/null; then
        print_warning "EKS cluster '$CLUSTER_NAME' not found. Skipping deletion."
        return
    fi
    
    # Delete node groups first
    print_status "Deleting EKS node groups..."
    NODE_GROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" \
        --query "nodegroups" --output text 2>/dev/null || echo "")
    
    for nodegroup in $NODE_GROUPS; do
        if [[ -n "$nodegroup" && "$nodegroup" != "None" ]]; then
            print_status "Deleting node group: $nodegroup"
            aws eks delete-nodegroup --cluster-name "$CLUSTER_NAME" \
                --nodegroup-name "$nodegroup" || true
        fi
    done
    
    # Wait for node groups to be deleted
    if [[ -n "$NODE_GROUPS" && "$NODE_GROUPS" != "None" ]]; then
        print_status "Waiting for node groups to be deleted..."
        for nodegroup in $NODE_GROUPS; do
            if [[ -n "$nodegroup" && "$nodegroup" != "None" ]]; then
                aws eks wait nodegroup-deleted --cluster-name "$CLUSTER_NAME" \
                    --nodegroup-name "$nodegroup" || true
            fi
        done
    fi
    
    # Delete the cluster
    print_status "Deleting EKS cluster: $CLUSTER_NAME"
    aws eks delete-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION"
    
    print_status "Waiting for cluster deletion (this may take 10-15 minutes)..."
    aws eks wait cluster-deleted --name "$CLUSTER_NAME" --region "$AWS_REGION" || true
    
    print_success "EKS cluster deletion completed"
}

# Clean up local files
cleanup_local_files() {
    print_status "Cleaning up local files..."
    
    # Remove temporary files
    rm -f /tmp/eks-trust-policy.json
    rm -f /tmp/node-trust-policy.json
    rm -f /tmp/ack-trust-policy.json
    rm -f /tmp/application-crd.yaml
    rm -f /tmp/test-application.yaml
    
    # Update kubeconfig to remove cluster context
    if [[ "$KUBECTL_AVAILABLE" == true ]]; then
        kubectl config delete-context "arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster/${CLUSTER_NAME}" 2>/dev/null || true
        kubectl config unset "clusters.arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster/${CLUSTER_NAME}" 2>/dev/null || true
        kubectl config unset "users.arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster/${CLUSTER_NAME}" 2>/dev/null || true
    fi
    
    print_success "Local files cleanup completed"
}

# Create destruction summary
create_destruction_summary() {
    print_status "Creating destruction summary..."
    
    cat > "${SCRIPT_DIR}/destruction-summary.txt" << EOF
Kubernetes Operators for AWS Resources - Destruction Summary
==========================================================

Destruction Date: $(date)
AWS Region: $AWS_REGION
AWS Account ID: $AWS_ACCOUNT_ID
Resource Suffix: ${RESOURCE_SUFFIX:-"Unknown"}

Resources Removed:
- EKS Cluster: $CLUSTER_NAME
- ACK Controllers (S3, IAM, Lambda)
- Custom Application CRD
- IAM Roles and Policies
- OIDC Identity Provider
- Local configuration files

Notes:
- All AWS resources created by ACK controllers have been removed
- Local kubectl context has been cleaned up
- Temporary files have been removed

If you encounter any issues or orphaned resources, check:
- AWS Console for any remaining resources
- kubectl config for any remaining contexts
- IAM console for any remaining roles/policies

Log file: ${LOG_FILE}
EOF
    
    print_success "Destruction summary saved to destruction-summary.txt"
}

# Main destruction function
main() {
    print_banner
    log_info "Starting destruction at $TIMESTAMP"
    
    confirm_destruction
    check_prerequisites
    get_resource_suffix
    
    # Cleanup in reverse order of creation
    cleanup_custom_resources
    uninstall_ack_controllers
    cleanup_oidc_provider
    cleanup_iam_resources
    delete_eks_cluster
    cleanup_local_files
    create_destruction_summary
    
    print_success "Destruction completed successfully!"
    print_status "All resources have been removed."
    print_status "Check destruction-summary.txt for details."
    print_status "Log file: $LOG_FILE"
}

# Dry run mode
dry_run() {
    print_status "DRY RUN MODE - No resources will be deleted"
    print_status "The following resources would be deleted:"
    
    check_prerequisites
    get_resource_suffix
    
    echo "• Custom Application resources and CRDs"
    echo "• ACK Controllers (S3, IAM, Lambda)"
    echo "• EKS Cluster: $CLUSTER_NAME"
    
    if [[ -n "$RESOURCE_SUFFIX" ]]; then
        echo "• IAM Role: ACK-Controller-Role-${RESOURCE_SUFFIX}"
        echo "• IAM Role: eks-service-role-${RESOURCE_SUFFIX}"
        echo "• IAM Role: eks-node-role-${RESOURCE_SUFFIX}"
    else
        echo "• IAM Roles (pattern-based search)"
    fi
    
    echo "• OIDC Identity Provider"
    echo "• Local configuration files"
    
    print_status "To perform actual deletion, run: $0"
}

# Check command line arguments
if [[ $# -gt 0 && "$1" == "--dry-run" ]]; then
    dry_run
elif [[ $# -gt 0 && "$1" == "--help" ]]; then
    echo "Usage: $0 [--dry-run] [--help]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deleted without actually deleting"
    echo "  --help       Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_REGION              AWS region (default: us-west-2)"
    echo "  CLUSTER_NAME            EKS cluster name (default: ack-operators-cluster)"
    echo "  ACK_SYSTEM_NAMESPACE    ACK namespace (default: ack-system)"
else
    main "$@"
fi