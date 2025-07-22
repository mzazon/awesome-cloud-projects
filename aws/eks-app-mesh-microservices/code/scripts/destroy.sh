#!/bin/bash

# Destroy EKS Service Mesh with AWS App Mesh
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Colors for output
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
cleanup_on_error() {
    log_error "Cleanup failed. Some resources may still exist."
    log_info "Check AWS console to manually remove any remaining resources."
    exit 1
}

trap cleanup_on_error ERR

# Load configuration if available
load_configuration() {
    if [ -f .deployment_config ]; then
        log_info "Loading deployment configuration..."
        source .deployment_config
        log_success "Configuration loaded"
        log_info "Cluster: ${CLUSTER_NAME:-unknown}"
        log_info "Mesh: ${MESH_NAME:-unknown}"
        log_info "Region: ${AWS_REGION:-unknown}"
    else
        log_warning "No deployment configuration found (.deployment_config)"
        log_info "You will need to provide resource details manually or check AWS console"
        
        # Try to get current AWS region
        export AWS_REGION=${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "")}
        if [ -z "$AWS_REGION" ]; then
            read -p "Enter AWS region: " AWS_REGION
            export AWS_REGION
        fi
        
        # Get cluster name
        if [ -z "${CLUSTER_NAME:-}" ]; then
            echo "Available EKS clusters:"
            aws eks list-clusters --region "$AWS_REGION" --output table || true
            read -p "Enter cluster name to delete (or press Enter to skip): " CLUSTER_NAME
            export CLUSTER_NAME
        fi
        
        # Get other details if needed
        export NAMESPACE="${NAMESPACE:-demo}"
        export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")}"
    fi
}

# Confirmation function
confirm_destruction() {
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log_warning "This will permanently delete the following resources:"
    log_warning "- EKS Cluster: ${CLUSTER_NAME:-unknown}"
    log_warning "- App Mesh: ${MESH_NAME:-unknown}"
    log_warning "- ECR Repositories: ${ECR_REPO_PREFIX:-unknown}/*"
    log_warning "- Load Balancers and associated AWS resources"
    log_warning "- IAM roles and policies created for the demo"
    echo ""
    
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    if [ "$confirmation" != "DELETE" ]; then
        log_info "Destruction cancelled."
        exit 0
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v eksctl &> /dev/null; then
        missing_tools+=("eksctl")
    fi
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check AWS authentication
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS authentication failed. Please configure AWS CLI."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Update kubeconfig for cluster access
update_kubeconfig() {
    if [ -n "${CLUSTER_NAME:-}" ] && [ -n "${AWS_REGION:-}" ]; then
        log_info "Updating kubeconfig for cluster access..."
        if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" &> /dev/null; then
            aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" || true
            log_success "Kubeconfig updated"
        else
            log_warning "Cluster $CLUSTER_NAME not found or already deleted"
        fi
    fi
}

# Remove ingress and load balancer
remove_ingress() {
    log_info "Removing Application Load Balancer and ingress..."
    
    if [ -n "${NAMESPACE:-}" ]; then
        # Delete ingress first to remove ALB
        kubectl delete ingress frontend-ingress -n "$NAMESPACE" --ignore-not-found=true
        
        # Wait for ALB to be deleted
        log_info "Waiting for ALB to be removed (this may take a few minutes)..."
        sleep 60
        
        log_success "Ingress removed"
    fi
}

# Remove AWS Load Balancer Controller
remove_load_balancer_controller() {
    log_info "Removing AWS Load Balancer Controller..."
    
    # Uninstall AWS Load Balancer Controller
    if helm list -n kube-system 2>/dev/null | grep -q aws-load-balancer-controller; then
        helm uninstall aws-load-balancer-controller -n kube-system || true
        log_success "Load Balancer Controller uninstalled"
    fi
    
    # Delete IAM service account
    if [ -n "${CLUSTER_NAME:-}" ]; then
        eksctl delete iamserviceaccount \
            --cluster="$CLUSTER_NAME" \
            --namespace=kube-system \
            --name=aws-load-balancer-controller \
            --region="$AWS_REGION" || true
    fi
    
    # Delete IAM policy
    if [ -n "${AWS_ACCOUNT_ID:-}" ]; then
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy" || true
        log_success "IAM policy removed"
    fi
}

# Remove X-Ray daemon and observability components
remove_observability() {
    log_info "Removing observability components..."
    
    if [ -n "${NAMESPACE:-}" ]; then
        # Delete X-Ray daemon
        kubectl delete daemonset xray-daemon -n "$NAMESPACE" --ignore-not-found=true
        kubectl delete service xray-service -n "$NAMESPACE" --ignore-not-found=true
        
        log_success "X-Ray daemon removed"
    fi
}

# Remove microservices applications
remove_applications() {
    log_info "Removing microservices applications..."
    
    if [ -n "${NAMESPACE:-}" ]; then
        # Delete deployments
        kubectl delete deployment frontend backend backend-v2 database -n "$NAMESPACE" --ignore-not-found=true
        
        # Delete services
        kubectl delete service frontend backend database -n "$NAMESPACE" --ignore-not-found=true
        
        # Wait for pods to terminate
        log_info "Waiting for pods to terminate..."
        kubectl wait --for=delete pod --all -n "$NAMESPACE" --timeout=300s || true
        
        log_success "Applications removed"
    fi
}

# Remove App Mesh resources
remove_app_mesh_resources() {
    log_info "Removing App Mesh resources..."
    
    if [ -n "${NAMESPACE:-}" ]; then
        # Delete virtual routers first (they may have dependencies)
        kubectl delete virtualrouter --all -n "$NAMESPACE" --ignore-not-found=true
        
        # Delete virtual services
        kubectl delete virtualservice --all -n "$NAMESPACE" --ignore-not-found=true
        
        # Delete virtual nodes
        kubectl delete virtualnode --all -n "$NAMESPACE" --ignore-not-found=true
        
        # Delete mesh
        if [ -n "${MESH_NAME:-}" ]; then
            kubectl delete mesh "$MESH_NAME" -n "$NAMESPACE" --ignore-not-found=true
        else
            kubectl delete mesh --all -n "$NAMESPACE" --ignore-not-found=true
        fi
        
        log_success "App Mesh resources removed"
    fi
}

# Remove App Mesh controller
remove_app_mesh_controller() {
    log_info "Removing App Mesh controller..."
    
    # Uninstall App Mesh controller
    if helm list -n appmesh-system 2>/dev/null | grep -q appmesh-controller; then
        helm uninstall appmesh-controller -n appmesh-system || true
        log_success "App Mesh controller uninstalled"
    fi
    
    # Delete IAM service account
    if [ -n "${CLUSTER_NAME:-}" ]; then
        eksctl delete iamserviceaccount \
            --cluster="$CLUSTER_NAME" \
            --namespace=appmesh-system \
            --name=appmesh-controller \
            --region="$AWS_REGION" || true
    fi
    
    # Delete App Mesh CRDs
    kubectl delete -k \
        "https://github.com/aws/eks-charts/stable/appmesh-controller/crds?ref=master" --ignore-not-found=true || true
    
    # Delete namespaces
    kubectl delete namespace appmesh-system --ignore-not-found=true || true
    if [ -n "${NAMESPACE:-}" ]; then
        kubectl delete namespace "$NAMESPACE" --ignore-not-found=true || true
    fi
    
    log_success "App Mesh controller and namespaces removed"
}

# Remove EKS cluster
remove_eks_cluster() {
    if [ -n "${CLUSTER_NAME:-}" ] && [ -n "${AWS_REGION:-}" ]; then
        log_info "Removing EKS cluster (this may take 10-15 minutes)..."
        
        # Check if cluster exists
        if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" &> /dev/null; then
            # Delete cluster using eksctl
            eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --wait
            log_success "EKS cluster removed successfully"
        else
            log_warning "EKS cluster $CLUSTER_NAME not found or already deleted"
        fi
    else
        log_warning "Cluster name or region not specified, skipping EKS cluster deletion"
    fi
}

# Remove ECR repositories
remove_ecr_repositories() {
    if [ -n "${ECR_REPO_PREFIX:-}" ] && [ -n "${AWS_REGION:-}" ]; then
        log_info "Removing ECR repositories..."
        
        local repos=("frontend" "backend" "database")
        
        for repo in "${repos[@]}"; do
            local repo_name="${ECR_REPO_PREFIX}/${repo}"
            if aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" &> /dev/null; then
                aws ecr delete-repository \
                    --repository-name "$repo_name" \
                    --force \
                    --region "$AWS_REGION" || true
                log_success "Removed ECR repository: $repo_name"
            else
                log_info "ECR repository $repo_name not found or already deleted"
            fi
        done
    else
        log_warning "ECR repository prefix not specified, skipping ECR cleanup"
        log_info "You may need to manually delete ECR repositories in the AWS console"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove temporary files
    rm -f iam_policy.json
    
    # Remove deployment configuration (with confirmation)
    if [ -f .deployment_config ]; then
        read -p "Remove deployment configuration file (.deployment_config)? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -f .deployment_config
            log_success "Deployment configuration removed"
        else
            log_info "Deployment configuration preserved"
        fi
    fi
    
    log_success "Local cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local cleanup_issues=false
    
    # Check if cluster still exists
    if [ -n "${CLUSTER_NAME:-}" ] && [ -n "${AWS_REGION:-}" ]; then
        if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" &> /dev/null; then
            log_warning "⚠️  EKS cluster $CLUSTER_NAME still exists"
            cleanup_issues=true
        fi
    fi
    
    # Check ECR repositories
    if [ -n "${ECR_REPO_PREFIX:-}" ] && [ -n "${AWS_REGION:-}" ]; then
        local repos=("frontend" "backend" "database")
        for repo in "${repos[@]}"; do
            if aws ecr describe-repositories --repository-names "${ECR_REPO_PREFIX}/${repo}" --region "$AWS_REGION" &> /dev/null; then
                log_warning "⚠️  ECR repository ${ECR_REPO_PREFIX}/${repo} still exists"
                cleanup_issues=true
            fi
        done
    fi
    
    # Check for orphaned IAM roles
    if [ -n "${RANDOM_SUFFIX:-}" ]; then
        if aws iam get-role --role-name "AmazonEKSLoadBalancerControllerRole-${RANDOM_SUFFIX}" &> /dev/null; then
            log_warning "⚠️  IAM role AmazonEKSLoadBalancerControllerRole-${RANDOM_SUFFIX} still exists"
            aws iam delete-role --role-name "AmazonEKSLoadBalancerControllerRole-${RANDOM_SUFFIX}" || true
        fi
    fi
    
    if [ "$cleanup_issues" = false ]; then
        log_success "✅ All resources have been successfully removed"
    else
        log_warning "⚠️  Some resources may still exist. Please check the AWS console:"
        log_info "- EKS: https://console.aws.amazon.com/eks/home?region=${AWS_REGION}"
        log_info "- ECR: https://console.aws.amazon.com/ecr/repositories?region=${AWS_REGION}"
        log_info "- IAM: https://console.aws.amazon.com/iam/home"
        log_info "- Load Balancers: https://console.aws.amazon.com/ec2/v2/home?region=${AWS_REGION}#LoadBalancers:"
    fi
}

# Main cleanup function
main() {
    log_info "Starting EKS Service Mesh cleanup process..."
    
    load_configuration
    confirm_destruction
    check_prerequisites
    update_kubeconfig
    
    # Remove resources in reverse order of creation
    remove_ingress
    remove_load_balancer_controller
    remove_observability
    remove_applications
    remove_app_mesh_resources
    remove_app_mesh_controller
    remove_eks_cluster
    remove_ecr_repositories
    cleanup_local_files
    verify_cleanup
    
    log_success "🎉 Cleanup completed!"
    log_info ""
    log_info "Summary:"
    log_info "- EKS cluster and associated resources removed"
    log_info "- App Mesh components removed"
    log_info "- ECR repositories removed"
    log_info "- Load balancer and networking components removed"
    log_info "- IAM roles and policies cleaned up"
    log_info ""
    log_info "If you notice any remaining charges in your AWS bill, please check the AWS console"
    log_info "for any resources that may not have been automatically cleaned up."
}

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Destroy EKS Service Mesh with AWS App Mesh deployment"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --force        Skip confirmation prompts (use with caution)"
    echo "  --keep-config  Keep the deployment configuration file"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive cleanup with confirmations"
    echo "  $0 --force           # Non-interactive cleanup (dangerous)"
    echo "  $0 --keep-config     # Cleanup but preserve configuration"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        --keep-config)
            KEEP_CONFIG=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Override confirmation function if force is enabled
if [ "${FORCE_CLEANUP:-false}" = true ]; then
    confirm_destruction() {
        log_warning "⚠️  Force cleanup enabled - skipping confirmation"
    }
fi

# Override cleanup function if keep-config is enabled
if [ "${KEEP_CONFIG:-false}" = true ]; then
    cleanup_local_files() {
        log_info "Cleaning up local files (keeping configuration)..."
        rm -f iam_policy.json
        log_success "Local cleanup completed (configuration preserved)"
    }
fi

# Run main function
main "$@"