#!/bin/bash

# Destroy script for EKS Multi-Tenant Cluster Security with Namespace Isolation
# This script removes all resources created for the multi-tenant security implementation

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    warn "Running in DRY-RUN mode - no actual resources will be deleted"
    KUBECTL_CMD="echo kubectl"
    AWS_CMD="echo aws"
else
    KUBECTL_CMD="kubectl"
    AWS_CMD="aws"
fi

# Default values
CLUSTER_NAME=${CLUSTER_NAME:-"my-multi-tenant-cluster"}
TENANT_A_NAME=${TENANT_A_NAME:-"tenant-alpha"}
TENANT_B_NAME=${TENANT_B_NAME:-"tenant-beta"}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}
FORCE_DELETE=${FORCE_DELETE:-false}

# Function to confirm destructive action
confirm_destruction() {
    if [ "$SKIP_CONFIRMATION" = "true" ]; then
        warn "Skipping confirmation - proceeding with destruction"
        return 0
    fi
    
    echo ""
    warn "WARNING: This will permanently delete the following resources:"
    echo "  - Tenant namespaces: $TENANT_A_NAME, $TENANT_B_NAME"
    echo "  - All applications and data in these namespaces"
    echo "  - RBAC roles and role bindings"
    echo "  - Network policies and resource quotas"
    echo "  - IAM roles: ${TENANT_A_NAME}-eks-role, ${TENANT_B_NAME}-eks-role"
    echo "  - EKS access entries"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
    if [ "$confirm" != "yes" ]; then
        info "Operation cancelled by user"
        exit 0
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    # Verify AWS region is set
    if [ -z "$(aws configure get region)" ]; then
        error "AWS region not configured. Please set AWS_DEFAULT_REGION or configure region."
    fi
    
    info "Prerequisites check passed"
}

# Function to verify cluster connectivity
verify_cluster_connectivity() {
    log "Verifying EKS cluster connectivity..."
    
    # Check if cluster exists
    if ! aws eks describe-cluster --name "$CLUSTER_NAME" &> /dev/null; then
        warn "EKS cluster '$CLUSTER_NAME' not found. Some resources may have already been deleted."
        return 0
    fi
    
    # Update kubeconfig
    log "Updating kubeconfig for cluster: $CLUSTER_NAME"
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$(aws configure get region)"
    
    # Test kubectl connectivity
    if ! kubectl cluster-info &> /dev/null; then
        warn "Cannot connect to EKS cluster. Will proceed with AWS-only cleanup."
        return 0
    fi
    
    info "Cluster connectivity verified"
}

# Function to remove sample applications
remove_sample_applications() {
    log "Removing sample applications..."
    
    # Remove Tenant A applications
    if kubectl get deployment "${TENANT_A_NAME}-app" -n "$TENANT_A_NAME" &> /dev/null; then
        $KUBECTL_CMD delete deployment "${TENANT_A_NAME}-app" -n "$TENANT_A_NAME"
        info "Deleted Tenant A deployment"
    else
        warn "Tenant A deployment not found"
    fi
    
    if kubectl get service "${TENANT_A_NAME}-service" -n "$TENANT_A_NAME" &> /dev/null; then
        $KUBECTL_CMD delete service "${TENANT_A_NAME}-service" -n "$TENANT_A_NAME"
        info "Deleted Tenant A service"
    else
        warn "Tenant A service not found"
    fi
    
    # Remove Tenant B applications
    if kubectl get deployment "${TENANT_B_NAME}-app" -n "$TENANT_B_NAME" &> /dev/null; then
        $KUBECTL_CMD delete deployment "${TENANT_B_NAME}-app" -n "$TENANT_B_NAME"
        info "Deleted Tenant B deployment"
    else
        warn "Tenant B deployment not found"
    fi
    
    if kubectl get service "${TENANT_B_NAME}-service" -n "$TENANT_B_NAME" &> /dev/null; then
        $KUBECTL_CMD delete service "${TENANT_B_NAME}-service" -n "$TENANT_B_NAME"
        info "Deleted Tenant B service"
    else
        warn "Tenant B service not found"
    fi
    
    info "Sample applications removed"
}

# Function to remove resource quotas and limits
remove_resource_quotas() {
    log "Removing resource quotas and limits..."
    
    # Remove Tenant A resource quota
    if kubectl get resourcequota "${TENANT_A_NAME}-quota" -n "$TENANT_A_NAME" &> /dev/null; then
        $KUBECTL_CMD delete resourcequota "${TENANT_A_NAME}-quota" -n "$TENANT_A_NAME"
        info "Deleted Tenant A resource quota"
    else
        warn "Tenant A resource quota not found"
    fi
    
    # Remove Tenant A limit range
    if kubectl get limitrange "${TENANT_A_NAME}-limits" -n "$TENANT_A_NAME" &> /dev/null; then
        $KUBECTL_CMD delete limitrange "${TENANT_A_NAME}-limits" -n "$TENANT_A_NAME"
        info "Deleted Tenant A limit range"
    else
        warn "Tenant A limit range not found"
    fi
    
    # Remove Tenant B resource quota
    if kubectl get resourcequota "${TENANT_B_NAME}-quota" -n "$TENANT_B_NAME" &> /dev/null; then
        $KUBECTL_CMD delete resourcequota "${TENANT_B_NAME}-quota" -n "$TENANT_B_NAME"
        info "Deleted Tenant B resource quota"
    else
        warn "Tenant B resource quota not found"
    fi
    
    # Remove Tenant B limit range
    if kubectl get limitrange "${TENANT_B_NAME}-limits" -n "$TENANT_B_NAME" &> /dev/null; then
        $KUBECTL_CMD delete limitrange "${TENANT_B_NAME}-limits" -n "$TENANT_B_NAME"
        info "Deleted Tenant B limit range"
    else
        warn "Tenant B limit range not found"
    fi
    
    info "Resource quotas and limits removed"
}

# Function to remove network policies
remove_network_policies() {
    log "Removing network policies..."
    
    # Remove Tenant A network policy
    if kubectl get networkpolicy "${TENANT_A_NAME}-isolation" -n "$TENANT_A_NAME" &> /dev/null; then
        $KUBECTL_CMD delete networkpolicy "${TENANT_A_NAME}-isolation" -n "$TENANT_A_NAME"
        info "Deleted Tenant A network policy"
    else
        warn "Tenant A network policy not found"
    fi
    
    # Remove Tenant B network policy
    if kubectl get networkpolicy "${TENANT_B_NAME}-isolation" -n "$TENANT_B_NAME" &> /dev/null; then
        $KUBECTL_CMD delete networkpolicy "${TENANT_B_NAME}-isolation" -n "$TENANT_B_NAME"
        info "Deleted Tenant B network policy"
    else
        warn "Tenant B network policy not found"
    fi
    
    info "Network policies removed"
}

# Function to remove EKS access entries
remove_access_entries() {
    log "Removing EKS access entries..."
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Remove access entry for Tenant A
    if aws eks describe-access-entry \
        --cluster-name "$CLUSTER_NAME" \
        --principal-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${TENANT_A_NAME}-eks-role" &> /dev/null; then
        $AWS_CMD eks delete-access-entry \
            --cluster-name "$CLUSTER_NAME" \
            --principal-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${TENANT_A_NAME}-eks-role"
        info "Deleted access entry for Tenant A"
    else
        warn "Access entry for Tenant A not found"
    fi
    
    # Remove access entry for Tenant B
    if aws eks describe-access-entry \
        --cluster-name "$CLUSTER_NAME" \
        --principal-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${TENANT_B_NAME}-eks-role" &> /dev/null; then
        $AWS_CMD eks delete-access-entry \
            --cluster-name "$CLUSTER_NAME" \
            --principal-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${TENANT_B_NAME}-eks-role"
        info "Deleted access entry for Tenant B"
    else
        warn "Access entry for Tenant B not found"
    fi
    
    info "Access entries removed"
}

# Function to remove RBAC resources
remove_rbac_resources() {
    log "Removing RBAC resources..."
    
    # Remove Tenant A RBAC
    if kubectl get role "${TENANT_A_NAME}-role" -n "$TENANT_A_NAME" &> /dev/null; then
        $KUBECTL_CMD delete role "${TENANT_A_NAME}-role" -n "$TENANT_A_NAME"
        info "Deleted Tenant A role"
    else
        warn "Tenant A role not found"
    fi
    
    if kubectl get rolebinding "${TENANT_A_NAME}-binding" -n "$TENANT_A_NAME" &> /dev/null; then
        $KUBECTL_CMD delete rolebinding "${TENANT_A_NAME}-binding" -n "$TENANT_A_NAME"
        info "Deleted Tenant A role binding"
    else
        warn "Tenant A role binding not found"
    fi
    
    # Remove Tenant B RBAC
    if kubectl get role "${TENANT_B_NAME}-role" -n "$TENANT_B_NAME" &> /dev/null; then
        $KUBECTL_CMD delete role "${TENANT_B_NAME}-role" -n "$TENANT_B_NAME"
        info "Deleted Tenant B role"
    else
        warn "Tenant B role not found"
    fi
    
    if kubectl get rolebinding "${TENANT_B_NAME}-binding" -n "$TENANT_B_NAME" &> /dev/null; then
        $KUBECTL_CMD delete rolebinding "${TENANT_B_NAME}-binding" -n "$TENANT_B_NAME"
        info "Deleted Tenant B role binding"
    else
        warn "Tenant B role binding not found"
    fi
    
    info "RBAC resources removed"
}

# Function to remove IAM roles
remove_iam_roles() {
    log "Removing IAM roles..."
    
    # Remove IAM role for Tenant A
    if aws iam get-role --role-name "${TENANT_A_NAME}-eks-role" &> /dev/null; then
        $AWS_CMD iam delete-role --role-name "${TENANT_A_NAME}-eks-role"
        info "Deleted IAM role: ${TENANT_A_NAME}-eks-role"
    else
        warn "IAM role ${TENANT_A_NAME}-eks-role not found"
    fi
    
    # Remove IAM role for Tenant B
    if aws iam get-role --role-name "${TENANT_B_NAME}-eks-role" &> /dev/null; then
        $AWS_CMD iam delete-role --role-name "${TENANT_B_NAME}-eks-role"
        info "Deleted IAM role: ${TENANT_B_NAME}-eks-role"
    else
        warn "IAM role ${TENANT_B_NAME}-eks-role not found"
    fi
    
    info "IAM roles removed"
}

# Function to remove tenant namespaces
remove_tenant_namespaces() {
    log "Removing tenant namespaces..."
    
    # Remove Tenant A namespace
    if kubectl get namespace "$TENANT_A_NAME" &> /dev/null; then
        if [ "$FORCE_DELETE" = "true" ]; then
            warn "Force deleting namespace $TENANT_A_NAME"
            $KUBECTL_CMD delete namespace "$TENANT_A_NAME" --force --grace-period=0
        else
            $KUBECTL_CMD delete namespace "$TENANT_A_NAME"
        fi
        info "Deleted namespace: $TENANT_A_NAME"
    else
        warn "Namespace $TENANT_A_NAME not found"
    fi
    
    # Remove Tenant B namespace
    if kubectl get namespace "$TENANT_B_NAME" &> /dev/null; then
        if [ "$FORCE_DELETE" = "true" ]; then
            warn "Force deleting namespace $TENANT_B_NAME"
            $KUBECTL_CMD delete namespace "$TENANT_B_NAME" --force --grace-period=0
        else
            $KUBECTL_CMD delete namespace "$TENANT_B_NAME"
        fi
        info "Deleted namespace: $TENANT_B_NAME"
    else
        warn "Namespace $TENANT_B_NAME not found"
    fi
    
    info "Tenant namespaces removed"
}

# Function to wait for namespace termination
wait_for_namespace_termination() {
    log "Waiting for namespace termination..."
    
    # Wait for Tenant A namespace to be fully deleted
    if kubectl get namespace "$TENANT_A_NAME" &> /dev/null; then
        log "Waiting for namespace $TENANT_A_NAME to be fully deleted..."
        timeout=300  # 5 minutes timeout
        while kubectl get namespace "$TENANT_A_NAME" &> /dev/null && [ $timeout -gt 0 ]; do
            sleep 5
            timeout=$((timeout - 5))
        done
        
        if [ $timeout -eq 0 ]; then
            warn "Timeout waiting for namespace $TENANT_A_NAME to be deleted"
        else
            info "Namespace $TENANT_A_NAME fully deleted"
        fi
    fi
    
    # Wait for Tenant B namespace to be fully deleted
    if kubectl get namespace "$TENANT_B_NAME" &> /dev/null; then
        log "Waiting for namespace $TENANT_B_NAME to be fully deleted..."
        timeout=300  # 5 minutes timeout
        while kubectl get namespace "$TENANT_B_NAME" &> /dev/null && [ $timeout -gt 0 ]; do
            sleep 5
            timeout=$((timeout - 5))
        done
        
        if [ $timeout -eq 0 ]; then
            warn "Timeout waiting for namespace $TENANT_B_NAME to be deleted"
        else
            info "Namespace $TENANT_B_NAME fully deleted"
        fi
    fi
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    # Check if namespaces are gone
    if kubectl get namespace "$TENANT_A_NAME" &> /dev/null; then
        warn "Namespace $TENANT_A_NAME still exists"
    else
        info "Namespace $TENANT_A_NAME successfully removed"
    fi
    
    if kubectl get namespace "$TENANT_B_NAME" &> /dev/null; then
        warn "Namespace $TENANT_B_NAME still exists"
    else
        info "Namespace $TENANT_B_NAME successfully removed"
    fi
    
    # Check if IAM roles are gone
    if aws iam get-role --role-name "${TENANT_A_NAME}-eks-role" &> /dev/null; then
        warn "IAM role ${TENANT_A_NAME}-eks-role still exists"
    else
        info "IAM role ${TENANT_A_NAME}-eks-role successfully removed"
    fi
    
    if aws iam get-role --role-name "${TENANT_B_NAME}-eks-role" &> /dev/null; then
        warn "IAM role ${TENANT_B_NAME}-eks-role still exists"
    else
        info "IAM role ${TENANT_B_NAME}-eks-role successfully removed"
    fi
    
    info "Cleanup validation completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup completed!"
    
    echo ""
    echo "=== Cleanup Summary ==="
    echo "Removed resources:"
    echo "  ✓ Sample applications and services"
    echo "  ✓ Resource quotas and limit ranges"
    echo "  ✓ Network policies"
    echo "  ✓ EKS access entries"
    echo "  ✓ RBAC roles and role bindings"
    echo "  ✓ IAM roles"
    echo "  ✓ Tenant namespaces"
    echo ""
    echo "The multi-tenant security configuration has been completely removed."
    echo "The EKS cluster itself remains intact."
    echo ""
}

# Function to handle cleanup errors
handle_cleanup_errors() {
    log "Some resources could not be cleaned up automatically"
    
    echo ""
    echo "=== Manual Cleanup Required ==="
    echo "If some resources still exist, you can manually remove them:"
    echo ""
    echo "# Remove namespaces (if stuck in terminating state)"
    echo "kubectl patch namespace $TENANT_A_NAME -p '{\"metadata\":{\"finalizers\":null}}'"
    echo "kubectl patch namespace $TENANT_B_NAME -p '{\"metadata\":{\"finalizers\":null}}'"
    echo ""
    echo "# Remove IAM roles (if still exist)"
    echo "aws iam delete-role --role-name ${TENANT_A_NAME}-eks-role"
    echo "aws iam delete-role --role-name ${TENANT_B_NAME}-eks-role"
    echo ""
    echo "# Remove access entries (if still exist)"
    echo "aws eks delete-access-entry --cluster-name $CLUSTER_NAME --principal-arn arn:aws:iam::\$(aws sts get-caller-identity --query Account --output text):role/${TENANT_A_NAME}-eks-role"
    echo "aws eks delete-access-entry --cluster-name $CLUSTER_NAME --principal-arn arn:aws:iam::\$(aws sts get-caller-identity --query Account --output text):role/${TENANT_B_NAME}-eks-role"
    echo ""
}

# Main execution
main() {
    log "Starting EKS Multi-Tenant Cluster Security cleanup..."
    
    check_prerequisites
    confirm_destruction
    verify_cluster_connectivity
    
    # Perform cleanup in reverse order of creation
    remove_sample_applications
    remove_resource_quotas
    remove_network_policies
    remove_access_entries
    remove_rbac_resources
    remove_iam_roles
    remove_tenant_namespaces
    
    # Wait for namespace termination
    wait_for_namespace_termination
    
    validate_cleanup
    display_cleanup_summary
    
    info "Cleanup completed successfully!"
}

# Print usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -c, --cluster-name NAME     EKS cluster name (default: my-multi-tenant-cluster)
    -a, --tenant-a NAME         Tenant A name (default: tenant-alpha)
    -b, --tenant-b NAME         Tenant B name (default: tenant-beta)
    -d, --dry-run              Run in dry-run mode (no actual changes)
    -f, --force                Force delete stuck resources
    -y, --yes                  Skip confirmation prompts
    -h, --help                 Show this help message

Environment Variables:
    CLUSTER_NAME               EKS cluster name
    TENANT_A_NAME              Tenant A namespace name
    TENANT_B_NAME              Tenant B namespace name
    DRY_RUN                    Set to 'true' for dry-run mode
    SKIP_CONFIRMATION          Set to 'true' to skip confirmation prompts
    FORCE_DELETE               Set to 'true' to force delete stuck resources

Examples:
    $0
    $0 --cluster-name my-cluster --tenant-a alpha --tenant-b beta
    $0 --yes --force
    DRY_RUN=true $0
    CLUSTER_NAME=prod-cluster $0 --force
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -a|--tenant-a)
            TENANT_A_NAME="$2"
            shift 2
            ;;
        -b|--tenant-b)
            TENANT_B_NAME="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Set error handling for cleanup
set +e
trap 'handle_cleanup_errors' ERR

# Run main function
main "$@"