#!/bin/bash

# Destroy script for EKS Cluster Logging and Monitoring with CloudWatch and Prometheus
# This script safely removes all infrastructure created by the deploy.sh script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "$1" == "--force" ]]; then
        warn "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    warn "This script will permanently delete the following resources:"
    warn "  - EKS cluster and node groups"
    warn "  - VPC and all networking components"
    warn "  - IAM roles and policies"
    warn "  - CloudWatch dashboards and alarms"
    warn "  - Prometheus workspace"
    warn "  - All application data and configurations"
    echo ""
    warn "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    if [[ ! "$REPLY" =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Operation cancelled by user"
        exit 0
    fi
    
    read -p "Final confirmation - type 'DELETE' to proceed: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        info "Operation cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource destruction..."
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to load from the environment file created by deploy.sh
    if [[ -f "/tmp/eks-observability-env.sh" ]]; then
        source "/tmp/eks-observability-env.sh"
        info "Environment variables loaded from /tmp/eks-observability-env.sh"
    else
        warn "Environment file not found. You may need to provide cluster details manually."
        
        # Prompt for cluster name if not set
        if [[ -z "$CLUSTER_NAME" ]]; then
            read -p "Enter EKS cluster name: " CLUSTER_NAME
            if [[ -z "$CLUSTER_NAME" ]]; then
                error "Cluster name is required"
                exit 1
            fi
        fi
        
        # Set other required variables
        export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        if [[ -z "$NODEGROUP_NAME" ]]; then
            # Try to find the node group name
            NODEGROUP_NAME=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --query 'nodegroups[0]' --output text 2>/dev/null || echo "")
            if [[ -z "$NODEGROUP_NAME" ]] || [[ "$NODEGROUP_NAME" == "None" ]]; then
                warn "Could not auto-detect node group name. Proceeding without it."
            fi
        fi
        
        if [[ -z "$PROMETHEUS_WORKSPACE_NAME" ]]; then
            PROMETHEUS_WORKSPACE_NAME="eks-prometheus-workspace"
        fi
    fi
    
    info "Using the following configuration:"
    info "  AWS_REGION: $AWS_REGION"
    info "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    info "  CLUSTER_NAME: $CLUSTER_NAME"
    info "  NODEGROUP_NAME: $NODEGROUP_NAME"
    info "  PROMETHEUS_WORKSPACE_NAME: $PROMETHEUS_WORKSPACE_NAME"
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    # Get all alarms with our cluster name
    ALARMS=$(aws cloudwatch describe-alarms --alarm-name-prefix "${CLUSTER_NAME}-" --query 'MetricAlarms[].AlarmName' --output text 2>/dev/null || echo "")
    
    if [[ -n "$ALARMS" ]]; then
        for alarm in $ALARMS; do
            info "Deleting alarm: $alarm"
            aws cloudwatch delete-alarms --alarm-names "$alarm" || warn "Failed to delete alarm: $alarm"
        done
        log "CloudWatch alarms deleted ✅"
    else
        info "No CloudWatch alarms found to delete"
    fi
}

# Function to delete CloudWatch dashboard
delete_cloudwatch_dashboard() {
    log "Deleting CloudWatch dashboard..."
    
    DASHBOARD_NAME="${CLUSTER_NAME}-observability"
    
    if aws cloudwatch get-dashboard --dashboard-name "$DASHBOARD_NAME" >/dev/null 2>&1; then
        aws cloudwatch delete-dashboards --dashboard-names "$DASHBOARD_NAME"
        info "CloudWatch dashboard deleted: $DASHBOARD_NAME"
    else
        info "CloudWatch dashboard not found: $DASHBOARD_NAME"
    fi
    
    log "CloudWatch dashboard cleanup completed ✅"
}

# Function to delete sample application
delete_sample_application() {
    log "Deleting sample application..."
    
    if kubectl get deployment sample-app -n default >/dev/null 2>&1; then
        kubectl delete deployment sample-app -n default --ignore-not-found=true
        kubectl delete service sample-app-service -n default --ignore-not-found=true
        info "Sample application deleted"
    else
        info "Sample application not found"
    fi
    
    log "Sample application cleanup completed ✅"
}

# Function to delete Kubernetes resources
delete_kubernetes_resources() {
    log "Deleting Kubernetes resources..."
    
    # Try to connect to the cluster
    if ! kubectl cluster-info >/dev/null 2>&1; then
        # Try to update kubeconfig
        if [[ -n "$CLUSTER_NAME" ]]; then
            aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION" 2>/dev/null || true
        fi
    fi
    
    # Delete sample application
    delete_sample_application
    
    # Delete CloudWatch resources
    if kubectl get namespace amazon-cloudwatch >/dev/null 2>&1; then
        info "Deleting CloudWatch agent DaemonSet..."
        kubectl delete daemonset cloudwatch-agent -n amazon-cloudwatch --ignore-not-found=true
        
        info "Deleting Fluent Bit DaemonSet..."
        kubectl delete daemonset fluent-bit -n amazon-cloudwatch --ignore-not-found=true
        
        info "Deleting CloudWatch configurations..."
        kubectl delete configmap cwagentconfig -n amazon-cloudwatch --ignore-not-found=true
        kubectl delete configmap fluent-bit-config -n amazon-cloudwatch --ignore-not-found=true
        
        info "Deleting service account..."
        kubectl delete serviceaccount cloudwatch-agent -n amazon-cloudwatch --ignore-not-found=true
        
        # Wait for pods to terminate
        info "Waiting for pods to terminate..."
        kubectl wait --for=delete pods --all -n amazon-cloudwatch --timeout=300s || warn "Timeout waiting for pods to terminate"
        
        info "Deleting amazon-cloudwatch namespace..."
        kubectl delete namespace amazon-cloudwatch --ignore-not-found=true
    else
        info "amazon-cloudwatch namespace not found"
    fi
    
    log "Kubernetes resources deleted ✅"
}

# Function to delete Prometheus workspace
delete_prometheus_workspace() {
    log "Deleting Prometheus workspace..."
    
    # Try to find workspace by name if ID not available
    if [[ -z "$PROMETHEUS_WORKSPACE_ID" ]]; then
        PROMETHEUS_WORKSPACE_ID=$(aws amp list-workspaces --query "workspaces[?alias=='${PROMETHEUS_WORKSPACE_NAME}'].workspaceId" --output text 2>/dev/null || echo "")
    fi
    
    if [[ -n "$PROMETHEUS_WORKSPACE_ID" ]] && [[ "$PROMETHEUS_WORKSPACE_ID" != "None" ]]; then
        info "Deleting Prometheus workspace: $PROMETHEUS_WORKSPACE_ID"
        
        # Delete any scrapers first
        SCRAPERS=$(aws amp list-scrapers --query "scrapers[?destination.ampConfiguration.workspaceArn=='arn:aws:aps:${AWS_REGION}:${AWS_ACCOUNT_ID}:workspace/${PROMETHEUS_WORKSPACE_ID}'].scraperId" --output text 2>/dev/null || echo "")
        
        if [[ -n "$SCRAPERS" ]]; then
            for scraper in $SCRAPERS; do
                info "Deleting scraper: $scraper"
                aws amp delete-scraper --scraper-id "$scraper" || warn "Failed to delete scraper: $scraper"
            done
            
            # Wait for scrapers to be deleted
            info "Waiting for scrapers to be deleted..."
            sleep 60
        fi
        
        # Delete workspace
        aws amp delete-workspace --workspace-id "$PROMETHEUS_WORKSPACE_ID" || warn "Failed to delete Prometheus workspace"
        
        # Wait for workspace to be deleted
        info "Waiting for Prometheus workspace to be deleted..."
        while true; do
            WORKSPACE_STATUS=$(aws amp describe-workspace --workspace-id "$PROMETHEUS_WORKSPACE_ID" --query 'workspace.status' --output text 2>/dev/null || echo "DELETED")
            if [[ "$WORKSPACE_STATUS" == "DELETED" ]] || [[ "$WORKSPACE_STATUS" == "None" ]]; then
                break
            fi
            info "Workspace status: $WORKSPACE_STATUS - waiting 30 seconds..."
            sleep 30
        done
        
        info "Prometheus workspace deleted"
    else
        info "Prometheus workspace not found"
    fi
    
    log "Prometheus workspace cleanup completed ✅"
}

# Function to delete EKS node group
delete_eks_node_group() {
    log "Deleting EKS node group..."
    
    if [[ -z "$NODEGROUP_NAME" ]]; then
        # Try to find node groups
        NODEGROUPS=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --query 'nodegroups' --output text 2>/dev/null || echo "")
        if [[ -n "$NODEGROUPS" ]]; then
            for nodegroup in $NODEGROUPS; do
                info "Deleting node group: $nodegroup"
                aws eks delete-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$nodegroup" || warn "Failed to delete node group: $nodegroup"
            done
            
            # Wait for all node groups to be deleted
            for nodegroup in $NODEGROUPS; do
                info "Waiting for node group to be deleted: $nodegroup"
                aws eks wait nodegroup-deleted --cluster-name "$CLUSTER_NAME" --nodegroup-name "$nodegroup" --timeout 1200 || warn "Timeout waiting for node group deletion: $nodegroup"
            done
        else
            info "No node groups found"
        fi
    else
        if aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" >/dev/null 2>&1; then
            info "Deleting node group: $NODEGROUP_NAME"
            aws eks delete-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME"
            
            info "Waiting for node group to be deleted..."
            aws eks wait nodegroup-deleted --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" --timeout 1200
            
            info "Node group deleted: $NODEGROUP_NAME"
        else
            info "Node group not found: $NODEGROUP_NAME"
        fi
    fi
    
    log "EKS node group cleanup completed ✅"
}

# Function to delete EKS cluster
delete_eks_cluster() {
    log "Deleting EKS cluster..."
    
    if aws eks describe-cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; then
        info "Deleting EKS cluster: $CLUSTER_NAME"
        aws eks delete-cluster --name "$CLUSTER_NAME"
        
        info "Waiting for EKS cluster to be deleted..."
        aws eks wait cluster-deleted --name "$CLUSTER_NAME" --timeout 1200
        
        info "EKS cluster deleted: $CLUSTER_NAME"
    else
        info "EKS cluster not found: $CLUSTER_NAME"
    fi
    
    log "EKS cluster cleanup completed ✅"
}

# Function to delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    # List of roles to delete
    ROLES=(
        "${CLUSTER_NAME}-service-role"
        "${CLUSTER_NAME}-node-role"
        "${CLUSTER_NAME}-cloudwatch-agent-role"
        "${CLUSTER_NAME}-prometheus-scraper-role"
    )
    
    for role_name in "${ROLES[@]}"; do
        if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
            info "Deleting IAM role: $role_name"
            
            # Detach all managed policies
            ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            if [[ -n "$ATTACHED_POLICIES" ]]; then
                for policy_arn in $ATTACHED_POLICIES; do
                    info "Detaching policy: $policy_arn"
                    aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" || warn "Failed to detach policy: $policy_arn"
                done
            fi
            
            # Delete inline policies
            INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames' --output text 2>/dev/null || echo "")
            if [[ -n "$INLINE_POLICIES" ]]; then
                for policy_name in $INLINE_POLICIES; do
                    info "Deleting inline policy: $policy_name"
                    aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" || warn "Failed to delete inline policy: $policy_name"
                done
            fi
            
            # Delete the role
            aws iam delete-role --role-name "$role_name" || warn "Failed to delete role: $role_name"
            info "IAM role deleted: $role_name"
        else
            info "IAM role not found: $role_name"
        fi
    done
    
    log "IAM roles cleanup completed ✅"
}

# Function to delete OIDC provider
delete_oidc_provider() {
    log "Deleting OIDC provider..."
    
    # Try to get OIDC provider from environment or derive from cluster
    if [[ -z "$OIDC_PROVIDER" ]]; then
        if aws eks describe-cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; then
            OIDC_ISSUER=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.identity.oidc.issuer' --output text 2>/dev/null)
            OIDC_PROVIDER=$(echo "$OIDC_ISSUER" | sed 's|https://||')
        fi
    fi
    
    if [[ -n "$OIDC_PROVIDER" ]]; then
        OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
        
        if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" >/dev/null 2>&1; then
            info "Deleting OIDC provider: $OIDC_PROVIDER"
            aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_PROVIDER_ARN" || warn "Failed to delete OIDC provider"
            info "OIDC provider deleted"
        else
            info "OIDC provider not found: $OIDC_PROVIDER"
        fi
    else
        info "OIDC provider information not available"
    fi
    
    log "OIDC provider cleanup completed ✅"
}

# Function to delete VPC and networking resources
delete_vpc_resources() {
    log "Deleting VPC and networking resources..."
    
    # Try to get VPC ID if not available
    if [[ -z "$VPC_ID" ]]; then
        VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${CLUSTER_NAME}-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
    fi
    
    if [[ -n "$VPC_ID" ]] && [[ "$VPC_ID" != "None" ]]; then
        info "Deleting VPC resources for VPC: $VPC_ID"
        
        # Delete route table associations first
        ROUTE_TABLES=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${CLUSTER_NAME}-rt" --query 'RouteTables[].RouteTableId' --output text 2>/dev/null || echo "")
        if [[ -n "$ROUTE_TABLES" ]]; then
            for rt in $ROUTE_TABLES; do
                info "Deleting route table associations for: $rt"
                ASSOCIATIONS=$(aws ec2 describe-route-tables --route-table-ids "$rt" --query 'RouteTables[0].Associations[?Main==`false`].RouteTableAssociationId' --output text 2>/dev/null || echo "")
                if [[ -n "$ASSOCIATIONS" ]]; then
                    for assoc in $ASSOCIATIONS; do
                        aws ec2 disassociate-route-table --association-id "$assoc" || warn "Failed to disassociate route table: $assoc"
                    done
                fi
            done
        fi
        
        # Delete route tables
        if [[ -n "$ROUTE_TABLES" ]]; then
            for rt in $ROUTE_TABLES; do
                info "Deleting route table: $rt"
                aws ec2 delete-route-table --route-table-id "$rt" || warn "Failed to delete route table: $rt"
            done
        fi
        
        # Detach and delete internet gateways
        IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || echo "")
        if [[ -n "$IGWS" ]]; then
            for igw in $IGWS; do
                info "Detaching internet gateway: $igw"
                aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID" || warn "Failed to detach internet gateway: $igw"
                info "Deleting internet gateway: $igw"
                aws ec2 delete-internet-gateway --internet-gateway-id "$igw" || warn "Failed to delete internet gateway: $igw"
            done
        fi
        
        # Delete subnets
        SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo "")
        if [[ -n "$SUBNETS" ]]; then
            for subnet in $SUBNETS; do
                info "Deleting subnet: $subnet"
                aws ec2 delete-subnet --subnet-id "$subnet" || warn "Failed to delete subnet: $subnet"
            done
        fi
        
        # Delete security groups (except default)
        SECURITY_GROUPS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")
        if [[ -n "$SECURITY_GROUPS" ]]; then
            for sg in $SECURITY_GROUPS; do
                info "Deleting security group: $sg"
                aws ec2 delete-security-group --group-id "$sg" || warn "Failed to delete security group: $sg"
            done
        fi
        
        # Delete VPC
        info "Deleting VPC: $VPC_ID"
        aws ec2 delete-vpc --vpc-id "$VPC_ID" || warn "Failed to delete VPC: $VPC_ID"
        
        info "VPC resources deleted"
    else
        info "VPC not found for cleanup"
    fi
    
    log "VPC and networking cleanup completed ✅"
}

# Function to delete CloudWatch log groups
delete_cloudwatch_logs() {
    log "Deleting CloudWatch log groups..."
    
    # List of log group prefixes to delete
    LOG_GROUP_PREFIXES=(
        "/aws/eks/${CLUSTER_NAME}"
        "/aws/containerinsights/${CLUSTER_NAME}"
    )
    
    for prefix in "${LOG_GROUP_PREFIXES[@]}"; do
        LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "$prefix" --query 'logGroups[].logGroupName' --output text 2>/dev/null || echo "")
        if [[ -n "$LOG_GROUPS" ]]; then
            for log_group in $LOG_GROUPS; do
                info "Deleting log group: $log_group"
                aws logs delete-log-group --log-group-name "$log_group" || warn "Failed to delete log group: $log_group"
            done
        fi
    done
    
    log "CloudWatch log groups cleanup completed ✅"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files
    rm -f /tmp/eks-cluster-role-trust-policy.json
    rm -f /tmp/node-group-role-trust-policy.json
    rm -f /tmp/cloudwatch-agent-role-trust-policy.json
    rm -f /tmp/cloudwatch-agent-service-account.yaml
    rm -f /tmp/fluent-bit-config.yaml
    rm -f /tmp/fluent-bit-daemonset.yaml
    rm -f /tmp/cwagent-config.yaml
    rm -f /tmp/cwagent-daemonset.yaml
    rm -f /tmp/cloudwatch-dashboard.json
    rm -f /tmp/sample-app-with-metrics.yaml
    
    # Keep the environment file for reference
    if [[ -f "/tmp/eks-observability-env.sh" ]]; then
        info "Environment file preserved at: /tmp/eks-observability-env.sh"
    fi
    
    log "Temporary files cleaned up ✅"
}

# Function to validate prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command_exists kubectl; then
        warn "kubectl is not installed. Some cleanup operations may be skipped."
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "Prerequisites check passed ✅"
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "==============="
    info "The following resources have been cleaned up:"
    info "  ✅ CloudWatch alarms"
    info "  ✅ CloudWatch dashboard"
    info "  ✅ Sample application"
    info "  ✅ Kubernetes resources"
    info "  ✅ Prometheus workspace"
    info "  ✅ EKS node group"
    info "  ✅ EKS cluster"
    info "  ✅ IAM roles"
    info "  ✅ OIDC provider"
    info "  ✅ VPC and networking"
    info "  ✅ CloudWatch log groups"
    info "  ✅ Temporary files"
    echo ""
    info "Cleanup completed successfully! 🎉"
    echo ""
    warn "Note: Some resources may take additional time to be fully removed from AWS."
    warn "You can verify cleanup by checking the AWS console or running AWS CLI commands."
}

# Main destroy function
main() {
    log "Starting EKS Cluster Logging and Monitoring cleanup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Confirm destruction
    confirm_destruction "$@"
    
    # Load environment variables
    load_environment
    
    # Execute cleanup steps in reverse order
    delete_cloudwatch_alarms
    delete_cloudwatch_dashboard
    delete_kubernetes_resources
    delete_prometheus_workspace
    delete_eks_node_group
    delete_eks_cluster
    delete_iam_roles
    delete_oidc_provider
    delete_vpc_resources
    delete_cloudwatch_logs
    cleanup_temp_files
    display_summary
    
    log "Cleanup completed successfully! 🎉"
}

# Trap to clean up on exit
trap cleanup_temp_files EXIT

# Execute main function with all arguments
main "$@"