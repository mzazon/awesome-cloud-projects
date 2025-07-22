#!/bin/bash

# AWS EKS Hybrid Kubernetes Monitoring Cleanup Script
# This script safely removes all infrastructure created for the hybrid monitoring solution

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/deployment-config.env"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration flags
DRY_RUN=${DRY_RUN:-false}
FORCE_DELETE=${FORCE_DELETE:-false}
SKIP_CONFIRMATION=${SKIP_CONFIRMATION:-false}
PARALLEL_DELETE=${PARALLEL_DELETE:-false}

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
        log_error "Cleanup failed with exit code $exit_code"
        log_error "Check the error log: ${ERROR_LOG}"
        log_error "Some resources may still exist and need manual cleanup"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Display script banner
show_banner() {
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════╗
║                 AWS EKS Hybrid Monitoring Cleanup                       ║
║              Safely Remove All Infrastructure Resources                  ║
╚══════════════════════════════════════════════════════════════════════════╝
EOF
}

# Load deployment configuration
load_config() {
    log_info "Loading deployment configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_error "Please ensure you have the deployment configuration from the deploy script"
        
        # Try to discover resources if config file is missing
        discover_resources
        return
    fi
    
    # Source the configuration file
    set -a  # Automatically export all variables
    source "$CONFIG_FILE"
    set +a
    
    log_info "Configuration loaded from: $CONFIG_FILE"
    log_info "Cluster: ${CLUSTER_NAME:-NOT_SET}"
    log_info "VPC: ${VPC_NAME:-NOT_SET}"
    log_info "Region: ${AWS_REGION:-NOT_SET}"
}

# Discover resources if config file is missing
discover_resources() {
    log_warning "Attempting to discover resources automatically..."
    
    # Set basic AWS configuration
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        log_error "Unable to determine AWS account ID. Please check AWS CLI configuration."
        exit 1
    fi
    
    # Try to find EKS clusters with hybrid monitoring pattern
    log_info "Searching for EKS clusters with hybrid monitoring pattern..."
    local clusters=$(aws eks list-clusters --query 'clusters[]' --output text 2>/dev/null | grep -E "hybrid-monitoring-cluster-" | head -1)
    
    if [[ -n "$clusters" ]]; then
        export CLUSTER_NAME="$clusters"
        log_info "Found cluster: $CLUSTER_NAME"
        
        # Extract random suffix from cluster name
        export RANDOM_SUFFIX=$(echo "$CLUSTER_NAME" | sed 's/hybrid-monitoring-cluster-//')
        export VPC_NAME="hybrid-monitoring-vpc-${RANDOM_SUFFIX}"
        export CLOUDWATCH_NAMESPACE="EKS/HybridMonitoring"
        
        log_info "Derived resource names from cluster:"
        log_info "  VPC Name: $VPC_NAME"
        log_info "  Random Suffix: $RANDOM_SUFFIX"
    else
        log_warning "No hybrid monitoring clusters found"
        log_warning "You may need to specify resource names manually or clean up individually"
    fi
}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check required CLI tools
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI is required but not installed"
        exit 1
    fi
    
    if ! command -v kubectl >/dev/null 2>&1; then
        log_warning "kubectl not found - Kubernetes resource cleanup will be skipped"
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log_warning "jq not found - some JSON parsing may be limited"
    fi
    
    # Check AWS authentication
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Confirm destructive action
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        log_warning "Skipping confirmation as requested"
        return 0
    fi
    
    echo
    log_warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo
    echo "This script will permanently delete the following resources:"
    echo "  • EKS Cluster: ${CLUSTER_NAME:-UNKNOWN}"
    echo "  • VPC and all networking components: ${VPC_NAME:-UNKNOWN}"
    echo "  • IAM roles and policies created for the deployment"
    echo "  • CloudWatch dashboards and alarms"
    echo "  • Sample applications and namespaces"
    echo
    echo "This action CANNOT be undone!"
    echo
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN MODE: No actual resources will be deleted"
        echo
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    log_info "Proceeding with resource cleanup..."
}

# Remove sample applications and Kubernetes resources
cleanup_kubernetes_resources() {
    log_info "Cleaning up Kubernetes resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would clean up Kubernetes resources"
        return 0
    fi
    
    if ! command -v kubectl >/dev/null 2>&1; then
        log_warning "kubectl not available - skipping Kubernetes cleanup"
        return 0
    fi
    
    # Check if we can access the cluster
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_warning "Cannot access Kubernetes cluster - skipping Kubernetes cleanup"
        return 0
    fi
    
    # Delete application namespaces
    log_info "Deleting application namespaces..."
    
    # Delete cloud-apps namespace (this will delete all resources within it)
    if kubectl get namespace cloud-apps >/dev/null 2>&1; then
        kubectl delete namespace cloud-apps --timeout=300s || log_warning "Failed to delete cloud-apps namespace"
        log_success "Deleted cloud-apps namespace"
    fi
    
    # Delete onprem-apps namespace if it exists
    if kubectl get namespace onprem-apps >/dev/null 2>&1; then
        kubectl delete namespace onprem-apps --timeout=300s || log_warning "Failed to delete onprem-apps namespace"
        log_success "Deleted onprem-apps namespace"
    fi
    
    # Clean up any custom monitoring configurations
    if kubectl get configmap hybrid-monitoring-config -n amazon-cloudwatch >/dev/null 2>&1; then
        kubectl delete configmap hybrid-monitoring-config -n amazon-cloudwatch || log_warning "Failed to delete monitoring config"
    fi
    
    log_success "Kubernetes resources cleanup completed"
}

# Remove CloudWatch dashboards and alarms
cleanup_cloudwatch_resources() {
    log_info "Cleaning up CloudWatch resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would clean up CloudWatch resources"
        return 0
    fi
    
    # Delete CloudWatch dashboard
    if [[ -n "${CLUSTER_NAME:-}" ]]; then
        log_info "Deleting CloudWatch dashboard..."
        aws cloudwatch delete-dashboards \
            --dashboard-names "EKS-Hybrid-Monitoring-${CLUSTER_NAME}" \
            2>/dev/null || log_warning "Dashboard may not exist or already deleted"
        
        # Delete CloudWatch alarms
        log_info "Deleting CloudWatch alarms..."
        local alarms=(
            "EKS-Hybrid-HighCPU-${CLUSTER_NAME}"
            "EKS-Hybrid-HighMemory-${CLUSTER_NAME}"
            "EKS-Hybrid-LowNodeCount-${CLUSTER_NAME}"
        )
        
        for alarm in "${alarms[@]}"; do
            aws cloudwatch delete-alarms --alarm-names "$alarm" 2>/dev/null || true
        done
        
        log_success "CloudWatch resources cleaned up"
    else
        log_warning "Cluster name not available - skipping CloudWatch cleanup"
    fi
}

# Remove EKS add-ons and Fargate profile
cleanup_eks_addons() {
    log_info "Cleaning up EKS add-ons and Fargate profiles..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would clean up EKS add-ons"
        return 0
    fi
    
    if [[ -z "${CLUSTER_NAME:-}" ]]; then
        log_warning "Cluster name not available - skipping EKS add-on cleanup"
        return 0
    fi
    
    # Check if cluster exists
    if ! aws eks describe-cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; then
        log_warning "Cluster $CLUSTER_NAME not found - skipping EKS cleanup"
        return 0
    fi
    
    # Delete CloudWatch Observability add-on
    log_info "Deleting CloudWatch Observability add-on..."
    if aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name amazon-cloudwatch-observability >/dev/null 2>&1; then
        aws eks delete-addon \
            --cluster-name "$CLUSTER_NAME" \
            --addon-name amazon-cloudwatch-observability || log_warning "Failed to delete CloudWatch add-on"
        
        # Wait for add-on deletion (with timeout)
        local timeout=300
        local elapsed=0
        while aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name amazon-cloudwatch-observability >/dev/null 2>&1; do
            if [[ $elapsed -ge $timeout ]]; then
                log_warning "Timeout waiting for add-on deletion"
                break
            fi
            sleep 10
            elapsed=$((elapsed + 10))
        done
    fi
    
    # Delete Fargate profile
    log_info "Deleting Fargate profile..."
    if aws eks describe-fargate-profile --cluster-name "$CLUSTER_NAME" --fargate-profile-name cloud-workloads >/dev/null 2>&1; then
        aws eks delete-fargate-profile \
            --cluster-name "$CLUSTER_NAME" \
            --fargate-profile-name cloud-workloads || log_warning "Failed to delete Fargate profile"
        
        log_info "Waiting for Fargate profile deletion..."
        aws eks wait fargate-profile-deleted \
            --cluster-name "$CLUSTER_NAME" \
            --fargate-profile-name cloud-workloads || log_warning "Timeout waiting for Fargate profile deletion"
    fi
    
    log_success "EKS add-ons and Fargate profile cleanup completed"
}

# Delete EKS cluster
delete_eks_cluster() {
    log_info "Deleting EKS cluster..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would delete EKS cluster"
        return 0
    fi
    
    if [[ -z "${CLUSTER_NAME:-}" ]]; then
        log_warning "Cluster name not available - skipping cluster deletion"
        return 0
    fi
    
    # Check if cluster exists
    if ! aws eks describe-cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; then
        log_warning "Cluster $CLUSTER_NAME not found - may already be deleted"
        return 0
    fi
    
    # Delete EKS cluster
    log_info "Deleting EKS cluster: $CLUSTER_NAME"
    aws eks delete-cluster --name "$CLUSTER_NAME" || log_error "Failed to initiate cluster deletion"
    
    log_info "Waiting for cluster deletion (this may take 10-15 minutes)..."
    aws eks wait cluster-deleted --name "$CLUSTER_NAME" || log_warning "Timeout waiting for cluster deletion"
    
    log_success "EKS cluster deleted successfully"
}

# Delete VPC and networking resources
cleanup_vpc_resources() {
    log_info "Cleaning up VPC and networking resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would clean up VPC resources"
        return 0
    fi
    
    # If we don't have VPC_ID, try to find it
    if [[ -z "${VPC_ID:-}" ]] && [[ -n "${VPC_NAME:-}" ]]; then
        export VPC_ID=$(aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=${VPC_NAME}" \
            --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
    fi
    
    if [[ -z "${VPC_ID:-}" ]] || [[ "$VPC_ID" == "None" ]]; then
        log_warning "VPC not found - may already be deleted"
        return 0
    fi
    
    log_info "Found VPC to delete: $VPC_ID"
    
    # Delete NAT Gateway and release Elastic IP
    cleanup_nat_resources
    
    # Delete subnets
    cleanup_subnets
    
    # Delete route tables
    cleanup_route_tables
    
    # Delete Internet Gateway
    cleanup_internet_gateway
    
    # Finally, delete the VPC
    delete_vpc
}

cleanup_nat_resources() {
    log_info "Cleaning up NAT Gateway and Elastic IP..."
    
    # Find and delete NAT gateways in the VPC
    local nat_gateways=$(aws ec2 describe-nat-gateways \
        --filter "Name=vpc-id,Values=${VPC_ID}" "Name=state,Values=available" \
        --query 'NatGateways[].NatGatewayId' --output text 2>/dev/null || echo "")
    
    for nat_gw in $nat_gateways; do
        if [[ -n "$nat_gw" ]] && [[ "$nat_gw" != "None" ]]; then
            log_info "Deleting NAT Gateway: $nat_gw"
            
            # Get the Elastic IP allocation ID before deleting NAT Gateway
            local eip_alloc=$(aws ec2 describe-nat-gateways \
                --nat-gateway-ids "$nat_gw" \
                --query 'NatGateways[0].NatGatewayAddresses[0].AllocationId' --output text 2>/dev/null || echo "")
            
            aws ec2 delete-nat-gateway --nat-gateway-id "$nat_gw" || log_warning "Failed to delete NAT Gateway $nat_gw"
            
            # Wait for NAT Gateway to be deleted before releasing EIP
            log_info "Waiting for NAT Gateway $nat_gw to be deleted..."
            local timeout=300
            local elapsed=0
            while aws ec2 describe-nat-gateways --nat-gateway-ids "$nat_gw" --query 'NatGateways[0].State' --output text 2>/dev/null | grep -E "(available|pending)" >/dev/null; do
                if [[ $elapsed -ge $timeout ]]; then
                    log_warning "Timeout waiting for NAT Gateway deletion"
                    break
                fi
                sleep 10
                elapsed=$((elapsed + 10))
            done
            
            # Release the Elastic IP
            if [[ -n "$eip_alloc" ]] && [[ "$eip_alloc" != "None" ]]; then
                log_info "Releasing Elastic IP: $eip_alloc"
                aws ec2 release-address --allocation-id "$eip_alloc" || log_warning "Failed to release EIP $eip_alloc"
            fi
        fi
    done
}

cleanup_subnets() {
    log_info "Deleting subnets..."
    
    local subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo "")
    
    for subnet in $subnets; do
        if [[ -n "$subnet" ]] && [[ "$subnet" != "None" ]]; then
            log_info "Deleting subnet: $subnet"
            aws ec2 delete-subnet --subnet-id "$subnet" || log_warning "Failed to delete subnet $subnet"
        fi
    done
}

cleanup_route_tables() {
    log_info "Deleting route tables..."
    
    # Get all route tables for the VPC (excluding the main route table)
    local route_tables=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query 'RouteTables[?Associations[0].Main != `true`].RouteTableId' --output text 2>/dev/null || echo "")
    
    for rt in $route_tables; do
        if [[ -n "$rt" ]] && [[ "$rt" != "None" ]]; then
            log_info "Deleting route table: $rt"
            aws ec2 delete-route-table --route-table-id "$rt" || log_warning "Failed to delete route table $rt"
        fi
    done
}

cleanup_internet_gateway() {
    log_info "Deleting Internet Gateway..."
    
    local igw_id=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
        --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "")
    
    if [[ -n "$igw_id" ]] && [[ "$igw_id" != "None" ]]; then
        # Detach from VPC first
        log_info "Detaching Internet Gateway: $igw_id"
        aws ec2 detach-internet-gateway \
            --vpc-id "$VPC_ID" \
            --internet-gateway-id "$igw_id" || log_warning "Failed to detach IGW"
        
        # Delete the Internet Gateway
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" || log_warning "Failed to delete IGW"
    fi
}

delete_vpc() {
    log_info "Deleting VPC: $VPC_ID"
    
    # Add a small delay to ensure all dependencies are cleaned up
    sleep 10
    
    aws ec2 delete-vpc --vpc-id "$VPC_ID" || log_warning "Failed to delete VPC - may have remaining dependencies"
    
    log_success "VPC cleanup completed"
}

# Delete IAM roles and policies
cleanup_iam_resources() {
    log_info "Cleaning up IAM resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would clean up IAM resources"
        return 0
    fi
    
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        log_warning "Random suffix not available - skipping IAM cleanup"
        return 0
    fi
    
    # Define IAM roles to delete
    local roles=(
        "EKSClusterServiceRole-${RANDOM_SUFFIX}"
        "EKSFargateExecutionRole-${RANDOM_SUFFIX}"
        "CloudWatchObservabilityRole-${RANDOM_SUFFIX}"
        "HybridMetricsRole-${RANDOM_SUFFIX}"
    )
    
    # Define policies to detach for each role
    declare -A role_policies=(
        ["EKSClusterServiceRole-${RANDOM_SUFFIX}"]="arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
        ["EKSFargateExecutionRole-${RANDOM_SUFFIX}"]="arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
        ["CloudWatchObservabilityRole-${RANDOM_SUFFIX}"]="arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        ["HybridMetricsRole-${RANDOM_SUFFIX}"]="arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    )
    
    # Clean up each role
    for role in "${roles[@]}"; do
        if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
            log_info "Cleaning up IAM role: $role"
            
            # Detach managed policies
            if [[ -n "${role_policies[$role]:-}" ]]; then
                aws iam detach-role-policy \
                    --role-name "$role" \
                    --policy-arn "${role_policies[$role]}" || log_warning "Failed to detach policy from $role"
            fi
            
            # Delete the role
            aws iam delete-role --role-name "$role" || log_warning "Failed to delete role $role"
            log_success "Deleted IAM role: $role"
        fi
    done
    
    log_success "IAM resources cleanup completed"
}

# Delete OIDC identity provider
cleanup_oidc_provider() {
    log_info "Cleaning up OIDC identity provider..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would clean up OIDC provider"
        return 0
    fi
    
    if [[ -n "${OIDC_ID:-}" ]]; then
        local oidc_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ID}"
        
        if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$oidc_arn" >/dev/null 2>&1; then
            log_info "Deleting OIDC provider: $oidc_arn"
            aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$oidc_arn" || log_warning "Failed to delete OIDC provider"
            log_success "OIDC provider deleted"
        fi
    else
        log_warning "OIDC ID not available - skipping OIDC provider cleanup"
    fi
}

# Cleanup deployment configuration
cleanup_config_files() {
    log_info "Cleaning up configuration files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN: Would clean up configuration files"
        return 0
    fi
    
    # Remove deployment configuration file
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
        log_success "Removed deployment configuration file"
    fi
    
    # Keep log files for reference but note their location
    log_info "Log files retained for reference:"
    log_info "  Cleanup log: $LOG_FILE"
    log_info "  Error log: $ERROR_LOG"
}

# Validate cleanup completion
validate_cleanup() {
    log_info "Validating cleanup completion..."
    
    local issues_found=false
    
    # Check if EKS cluster is gone
    if [[ -n "${CLUSTER_NAME:-}" ]] && aws eks describe-cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; then
        log_warning "EKS cluster still exists: $CLUSTER_NAME"
        issues_found=true
    fi
    
    # Check if VPC is gone
    if [[ -n "${VPC_ID:-}" ]] && aws ec2 describe-vpcs --vpc-ids "$VPC_ID" >/dev/null 2>&1; then
        log_warning "VPC still exists: $VPC_ID"
        issues_found=true
    fi
    
    # Check for remaining IAM roles
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local remaining_roles=$(aws iam list-roles --query "Roles[?contains(RoleName, '${RANDOM_SUFFIX}')].RoleName" --output text 2>/dev/null || echo "")
        if [[ -n "$remaining_roles" ]]; then
            log_warning "Some IAM roles may still exist: $remaining_roles"
            issues_found=true
        fi
    fi
    
    if [[ "$issues_found" == "true" ]]; then
        log_warning "Some resources may still exist - check the AWS console for manual cleanup"
        return 1
    else
        log_success "Cleanup validation completed successfully"
        return 0
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    cat << EOF

╔══════════════════════════════════════════════════════════════════════════╗
║                         CLEANUP COMPLETED                               ║
╚══════════════════════════════════════════════════════════════════════════╝

🧹 All EKS Hybrid Monitoring resources have been successfully removed!

📋 Resources Cleaned Up:
   • EKS Cluster: ${CLUSTER_NAME:-UNKNOWN}
   • VPC and Networking: ${VPC_ID:-UNKNOWN}
   • IAM Roles: 4 roles deleted
   • CloudWatch Dashboard and Alarms
   • Sample Applications and Namespaces

💰 Cost Impact:
   • All billable resources have been removed
   • No ongoing charges should occur from this deployment

📝 Cleanup Summary:
   • Cleanup logs: ${LOG_FILE}
   • Error logs: ${ERROR_LOG}
   • Configuration removed: ${CONFIG_FILE}

🔍 Next Steps:
   • Verify no unexpected charges appear on your AWS bill
   • Check AWS console to confirm all resources are removed
   • Review logs if any warnings were reported during cleanup

EOF
}

# Print usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely remove all AWS EKS Hybrid Kubernetes Monitoring infrastructure.

OPTIONS:
    --dry-run              Show what would be deleted without making changes
    --force                Skip confirmation prompts (DANGEROUS)
    --skip-confirmation    Skip the main deletion confirmation
    --parallel             Delete resources in parallel where possible
    --help                 Show this help message

ENVIRONMENT VARIABLES:
    DRY_RUN               Set to 'true' for dry run mode
    FORCE_DELETE          Set to 'true' to force deletion without prompts
    SKIP_CONFIRMATION     Set to 'true' to skip confirmation prompts
    PARALLEL_DELETE       Set to 'true' for parallel deletion

EXAMPLES:
    $0                    # Interactive cleanup with confirmations
    $0 --dry-run          # Preview what would be deleted
    $0 --force            # Delete everything without prompts (DANGEROUS)

SAFETY FEATURES:
    • Confirmation prompts before destructive actions
    • Dry run mode to preview changes
    • Comprehensive logging of all operations
    • Validation of cleanup completion

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
            --force)
                FORCE_DELETE=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            --skip-confirmation)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --parallel)
                PARALLEL_DELETE=true
                shift
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

# Main cleanup function
main() {
    parse_arguments "$@"
    
    show_banner
    
    log_info "Starting EKS Hybrid Monitoring cleanup..."
    log_info "Cleanup mode: $([[ "$DRY_RUN" == "true" ]] && echo "DRY RUN" || echo "LIVE")"
    log_info "Log file: ${LOG_FILE}"
    
    check_prerequisites
    load_config
    confirm_deletion
    
    # Execute cleanup in order (reverse of deployment)
    cleanup_kubernetes_resources
    cleanup_cloudwatch_resources
    cleanup_eks_addons
    delete_eks_cluster
    cleanup_vpc_resources
    cleanup_iam_resources
    cleanup_oidc_provider
    
    if [[ "$DRY_RUN" != "true" ]]; then
        cleanup_config_files
        
        if validate_cleanup; then
            show_cleanup_summary
        else
            log_warning "Cleanup completed with warnings - some manual cleanup may be required"
        fi
    else
        log_info "DRY RUN completed - no resources were actually deleted"
    fi
    
    log_success "Cleanup process completed!"
}

# Execute main function with all arguments
main "$@"