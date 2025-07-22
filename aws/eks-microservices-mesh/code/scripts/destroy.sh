#!/bin/bash

# Destroy Microservices on EKS with Service Mesh using AWS App Mesh
# Recipe: microservices-eks-service-mesh-aws-app-mesh
# Description: Automated cleanup script for AWS App Mesh service mesh with EKS

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Default configuration
DEFAULT_CLUSTER_NAME="microservices-mesh-cluster"
DEFAULT_APP_MESH_NAME="microservices-mesh"
DEFAULT_NAMESPACE="production"
DEFAULT_ECR_REPO_PREFIX="microservices-demo"
DEFAULT_REGION=""

# Configuration variables
CLUSTER_NAME="${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}"
APP_MESH_NAME="${APP_MESH_NAME:-$DEFAULT_APP_MESH_NAME}"
NAMESPACE="${NAMESPACE:-$DEFAULT_NAMESPACE}"
ECR_REPO_PREFIX="${ECR_REPO_PREFIX:-$DEFAULT_ECR_REPO_PREFIX}"
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"
KEEP_CLUSTER="${KEEP_CLUSTER:-false}"
KEEP_ECR="${KEEP_ECR:-false}"

# Help function
show_help() {
    cat << EOF
Destroy Microservices on EKS with Service Mesh using AWS App Mesh

Usage: $0 [OPTIONS]

Options:
    -h, --help                  Show this help message
    --dry-run                   Show what would be destroyed without executing
    --force                     Skip confirmation prompts
    --cluster-name NAME         EKS cluster name (default: $DEFAULT_CLUSTER_NAME)
    --mesh-name NAME            App Mesh name (default: $DEFAULT_APP_MESH_NAME)
    --namespace NAME            Kubernetes namespace (default: $DEFAULT_NAMESPACE)
    --ecr-prefix PREFIX         ECR repository prefix (default: $DEFAULT_ECR_REPO_PREFIX)
    --keep-cluster              Keep the EKS cluster (only remove App Mesh resources)
    --keep-ecr                  Keep ECR repositories
    --region REGION             AWS region (default: from AWS CLI config)

Environment Variables:
    CLUSTER_NAME               EKS cluster name
    APP_MESH_NAME              App Mesh name  
    NAMESPACE                  Kubernetes namespace
    ECR_REPO_PREFIX            ECR repository prefix
    DRY_RUN                    Set to 'true' for dry run mode
    FORCE                      Set to 'true' to skip confirmations
    KEEP_CLUSTER               Set to 'true' to keep EKS cluster
    KEEP_ECR                   Set to 'true' to keep ECR repositories

Examples:
    $0                                    # Destroy all resources with confirmation
    $0 --force                            # Destroy all resources without confirmation
    $0 --dry-run                          # Show what would be destroyed
    $0 --keep-cluster                     # Remove only App Mesh resources
    $0 --cluster-name my-cluster          # Use custom cluster name

Warning: This will destroy AWS resources and may result in data loss!

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --mesh-name)
                APP_MESH_NAME="$2"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --ecr-prefix)
                ECR_REPO_PREFIX="$2"
                shift 2
                ;;
            --keep-cluster)
                KEEP_CLUSTER=true
                shift
                ;;
            --keep-ecr)
                KEEP_ECR=true
                shift
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Confirm destruction
confirm_destruction() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    warning "This will destroy the following AWS resources:"
    echo "  - EKS Cluster: $CLUSTER_NAME"
    echo "  - App Mesh: $APP_MESH_NAME"
    echo "  - Kubernetes namespace: $NAMESPACE"
    echo "  - ECR repositories: ${ECR_REPO_PREFIX}-*"
    echo "  - Load Balancer Controller"
    echo "  - CloudWatch Container Insights"
    echo ""
    
    if [[ "$KEEP_CLUSTER" == "true" ]]; then
        echo "Note: EKS cluster will be kept"
    fi
    
    if [[ "$KEEP_ECR" == "true" ]]; then
        echo "Note: ECR repositories will be kept"
    fi
    
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    case $confirmation in
        yes|YES|y|Y)
            log "Proceeding with destruction..."
            ;;
        *)
            log "Destruction cancelled."
            exit 0
            ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    if ! command -v aws &> /dev/null; then
        missing_tools+=(aws-cli)
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=(kubectl)
    fi
    
    if ! command -v eksctl &> /dev/null && [[ "$KEEP_CLUSTER" != "true" ]]; then
        missing_tools+=(eksctl)
    fi
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=(helm)
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing_tools[*]}"
        error "Please install the missing tools and try again."
        exit 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid"
        error "Please run 'aws configure' and try again."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Set up environment
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Please set it using --region or configure AWS CLI."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Check if cluster exists and update kubeconfig
    if eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" &> /dev/null; then
        aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" &> /dev/null || true
        success "Connected to EKS cluster: $CLUSTER_NAME"
    else
        warning "EKS cluster $CLUSTER_NAME not found or not accessible"
    fi
    
    log "Environment configured:"
    log "  AWS Region: $AWS_REGION"
    log "  AWS Account ID: $AWS_ACCOUNT_ID"
    log "  Cluster Name: $CLUSTER_NAME"
    log "  App Mesh Name: $APP_MESH_NAME"
    log "  Namespace: $NAMESPACE"
}

# Remove application resources
remove_application_resources() {
    log "Removing application resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove application deployments and services"
        return 0
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        warning "Kubernetes cluster not accessible, skipping application resource cleanup"
        return 0
    fi
    
    # Delete ingress first to remove load balancer
    if kubectl get ingress service-a-ingress -n "$NAMESPACE" &> /dev/null; then
        kubectl delete ingress service-a-ingress -n "$NAMESPACE" || true
        success "Deleted ingress"
        
        # Wait for load balancer to be deleted
        log "Waiting for load balancer to be deleted..."
        sleep 30
    fi
    
    # Delete deployments and services
    local services=("a" "b" "c")
    for service in "${services[@]}"; do
        if kubectl get deployment "service-${service}" -n "$NAMESPACE" &> /dev/null; then
            kubectl delete deployment "service-${service}" -n "$NAMESPACE" || true
            success "Deleted deployment: service-${service}"
        fi
        
        if kubectl get service "service-${service}" -n "$NAMESPACE" &> /dev/null; then
            kubectl delete service "service-${service}" -n "$NAMESPACE" || true
            success "Deleted service: service-${service}"
        fi
    done
    
    success "Application resources removed"
}

# Remove App Mesh resources
remove_app_mesh_resources() {
    log "Removing App Mesh resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove App Mesh virtual services, virtual nodes, and mesh"
        return 0
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        warning "Kubernetes cluster not accessible, skipping App Mesh resource cleanup"
        return 0
    fi
    
    # Delete virtual services first
    local services=("a" "b" "c")
    for service in "${services[@]}"; do
        if kubectl get virtualservice "service-${service}" -n "$NAMESPACE" &> /dev/null; then
            kubectl delete virtualservice "service-${service}" -n "$NAMESPACE" || true
            success "Deleted virtual service: service-${service}"
        fi
    done
    
    # Delete virtual nodes
    for service in "${services[@]}"; do
        if kubectl get virtualnode "service-${service}" -n "$NAMESPACE" &> /dev/null; then
            kubectl delete virtualnode "service-${service}" -n "$NAMESPACE" || true
            success "Deleted virtual node: service-${service}"
        fi
    done
    
    # Delete mesh
    if kubectl get mesh "$APP_MESH_NAME" &> /dev/null; then
        kubectl delete mesh "$APP_MESH_NAME" || true
        success "Deleted mesh: $APP_MESH_NAME"
    fi
    
    # Delete namespace if it exists and has the mesh label
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        if kubectl get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels.mesh}' 2>/dev/null | grep -q "$APP_MESH_NAME"; then
            kubectl delete namespace "$NAMESPACE" || true
            success "Deleted namespace: $NAMESPACE"
        fi
    fi
    
    success "App Mesh resources removed"
}

# Remove observability components
remove_observability_components() {
    log "Removing observability components..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove CloudWatch Container Insights"
        return 0
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        warning "Kubernetes cluster not accessible, skipping observability cleanup"
        return 0
    fi
    
    # Remove CloudWatch Container Insights
    if kubectl get namespace amazon-cloudwatch &> /dev/null; then
        kubectl delete namespace amazon-cloudwatch || true
        success "Deleted CloudWatch Container Insights namespace"
    fi
    
    # Remove CloudWatch agent daemonset if it exists in default namespace
    if kubectl get daemonset cloudwatch-agent -n amazon-cloudwatch &> /dev/null; then
        kubectl delete daemonset cloudwatch-agent -n amazon-cloudwatch || true
    fi
    
    # Remove fluentd daemonset if it exists
    if kubectl get daemonset fluentd-cloudwatch -n amazon-cloudwatch &> /dev/null; then
        kubectl delete daemonset fluentd-cloudwatch -n amazon-cloudwatch || true
    fi
    
    success "Observability components removed"
}

# Remove App Mesh controller
remove_app_mesh_controller() {
    log "Removing App Mesh controller..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove App Mesh controller and CRDs"
        return 0
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        warning "Kubernetes cluster not accessible, skipping App Mesh controller cleanup"
        return 0
    fi
    
    # Uninstall App Mesh controller using Helm
    if helm list -n appmesh-system | grep -q appmesh-controller; then
        helm uninstall appmesh-controller -n appmesh-system || true
        success "Uninstalled App Mesh controller"
    fi
    
    # Delete service account and IAM role
    if eksctl get iamserviceaccount --cluster "$CLUSTER_NAME" --name appmesh-controller --namespace appmesh-system &> /dev/null; then
        eksctl delete iamserviceaccount \
            --cluster="$CLUSTER_NAME" \
            --namespace=appmesh-system \
            --name=appmesh-controller || true
        success "Deleted App Mesh controller service account"
    fi
    
    # Delete App Mesh CRDs (do this after removing controller)
    if kubectl api-resources | grep -q appmesh.k8s.aws; then
        kubectl delete -k \
            "https://github.com/aws/eks-charts/stable/appmesh-controller/crds?ref=master" || true
        success "Deleted App Mesh CRDs"
    fi
    
    # Delete namespace
    if kubectl get namespace appmesh-system &> /dev/null; then
        kubectl delete namespace appmesh-system || true
        success "Deleted appmesh-system namespace"
    fi
    
    success "App Mesh controller removed"
}

# Remove AWS Load Balancer Controller
remove_load_balancer_controller() {
    log "Removing AWS Load Balancer Controller..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove AWS Load Balancer Controller"
        return 0
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        warning "Kubernetes cluster not accessible, skipping Load Balancer Controller cleanup"
        return 0
    fi
    
    # Uninstall AWS Load Balancer Controller using Helm
    if helm list -n kube-system | grep -q aws-load-balancer-controller; then
        helm uninstall aws-load-balancer-controller -n kube-system || true
        success "Uninstalled AWS Load Balancer Controller"
    fi
    
    # Delete service account
    if eksctl get iamserviceaccount --cluster "$CLUSTER_NAME" --name aws-load-balancer-controller --namespace kube-system &> /dev/null; then
        eksctl delete iamserviceaccount \
            --cluster="$CLUSTER_NAME" \
            --namespace=kube-system \
            --name=aws-load-balancer-controller || true
        success "Deleted Load Balancer Controller service account"
    fi
    
    # Delete IAM policy
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"
    if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        # Check if policy is attached to any roles
        local attached_entities=$(aws iam list-entities-for-policy --policy-arn "$policy_arn" --output text --query 'PolicyRoles[].RoleName + PolicyUsers[].UserName + PolicyGroups[].GroupName')
        if [[ -z "$attached_entities" ]]; then
            aws iam delete-policy --policy-arn "$policy_arn" || true
            success "Deleted Load Balancer Controller IAM policy"
        else
            warning "IAM policy still attached to entities, skipping deletion: $policy_arn"
        fi
    fi
    
    success "AWS Load Balancer Controller removed"
}

# Remove EKS cluster
remove_eks_cluster() {
    if [[ "$KEEP_CLUSTER" == "true" ]]; then
        log "Keeping EKS cluster as requested"
        return 0
    fi
    
    log "Removing EKS cluster..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete EKS cluster: $CLUSTER_NAME"
        return 0
    fi
    
    # Check if cluster exists
    if ! eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" &> /dev/null; then
        warning "EKS cluster $CLUSTER_NAME not found, skipping deletion"
        return 0
    fi
    
    # Delete EKS cluster
    log "This may take 10-15 minutes..."
    eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" || true
    
    success "EKS cluster removed"
}

# Remove ECR repositories
remove_ecr_repositories() {
    if [[ "$KEEP_ECR" == "true" ]]; then
        log "Keeping ECR repositories as requested"
        return 0
    fi
    
    log "Removing ECR repositories..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete ECR repositories: ${ECR_REPO_PREFIX}-*"
        return 0
    fi
    
    # Delete ECR repositories
    local services=("service-a" "service-b" "service-c")
    for service in "${services[@]}"; do
        local repo_name="${ECR_REPO_PREFIX}-${service}"
        
        if aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" &> /dev/null; then
            aws ecr delete-repository \
                --repository-name "$repo_name" \
                --region "$AWS_REGION" \
                --force || true
            success "Deleted ECR repository: $repo_name"
        else
            warning "ECR repository $repo_name not found, skipping"
        fi
    done
    
    success "ECR repositories removed"
}

# Cleanup local files
cleanup_local_files() {
    log "Cleaning up local temporary files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would clean up local temporary files"
        return 0
    fi
    
    # Remove common temporary files that might have been created
    local temp_files=(
        "cluster-config.yaml"
        "iam_policy.json"
        "xray-trust-policy.json"
        "cwagent-fluentd-quickstart.yaml"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            success "Removed local file: $file"
        fi
    done
    
    # Clean up any microservices-demo directory
    if [[ -d "microservices-demo" ]]; then
        rm -rf "microservices-demo"
        success "Removed microservices-demo directory"
    fi
    
    success "Local files cleaned up"
}

# Verify destruction
verify_destruction() {
    log "Verifying destruction..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would verify destruction"
        return 0
    fi
    
    local issues=()
    
    # Check if EKS cluster still exists
    if [[ "$KEEP_CLUSTER" != "true" ]]; then
        if eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" &> /dev/null; then
            issues+=("EKS cluster $CLUSTER_NAME still exists")
        fi
    fi
    
    # Check ECR repositories
    if [[ "$KEEP_ECR" != "true" ]]; then
        local services=("service-a" "service-b" "service-c")
        for service in "${services[@]}"; do
            local repo_name="${ECR_REPO_PREFIX}-${service}"
            if aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" &> /dev/null; then
                issues+=("ECR repository $repo_name still exists")
            fi
        done
    fi
    
    # Check IAM policy
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"
    if aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        issues+=("IAM policy AWSLoadBalancerControllerIAMPolicy still exists")
    fi
    
    if [[ ${#issues[@]} -gt 0 ]]; then
        warning "Some resources may still exist:"
        for issue in "${issues[@]}"; do
            warning "  - $issue"
        done
        warning "Please check and manually remove these resources if needed."
    else
        success "All resources appear to have been removed successfully"
    fi
}

# Print destruction summary
print_summary() {
    log "Destruction Summary"
    echo "==================="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN MODE - No resources were actually destroyed"
        echo ""
        echo "Resources that would be destroyed:"
    else
        echo "Resources destroyed:"
    fi
    
    echo "  ✓ Application deployments and services"
    echo "  ✓ App Mesh virtual services and virtual nodes"
    echo "  ✓ App Mesh mesh resource"
    echo "  ✓ AWS Load Balancer Controller"
    echo "  ✓ CloudWatch Container Insights"
    echo "  ✓ App Mesh controller and CRDs"
    
    if [[ "$KEEP_CLUSTER" == "true" ]]; then
        echo "  - EKS cluster (kept as requested)"
    else
        echo "  ✓ EKS cluster"
    fi
    
    if [[ "$KEEP_ECR" == "true" ]]; then
        echo "  - ECR repositories (kept as requested)"
    else
        echo "  ✓ ECR repositories"
    fi
    
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "To actually destroy resources, run this script without --dry-run"
    else
        echo "Cleanup completed. All specified resources have been removed."
        echo "Please check your AWS Console to verify no unexpected charges."
    fi
}

# Main destruction function
main() {
    log "Starting destruction of Microservices on EKS with AWS App Mesh resources"
    
    parse_args "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN MODE - No actual resources will be destroyed"
    fi
    
    check_prerequisites
    setup_environment
    confirm_destruction
    
    # Remove resources in reverse order of creation
    remove_application_resources
    remove_app_mesh_resources
    remove_observability_components
    remove_app_mesh_controller
    remove_load_balancer_controller
    remove_eks_cluster
    remove_ecr_repositories
    cleanup_local_files
    verify_destruction
    print_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "This was a dry run. No resources were actually destroyed."
        log "Run without --dry-run to perform the actual destruction."
    else
        success "Destruction completed successfully!"
    fi
}

# Run main function with all arguments
main "$@"