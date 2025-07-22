#!/bin/bash

# Destroy script for EKS Auto-Scaling Recipe
# Safely removes all resources created by the deployment script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Default configuration
CLUSTER_NAME=""
DRY_RUN=false
FORCE=false
SKIP_CONFIRMATION=false
PRESERVE_MONITORING=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --preserve-monitoring)
            PRESERVE_MONITORING=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --cluster-name NAME       Specify cluster name to destroy"
            echo "  --dry-run                Show what would be destroyed without executing"
            echo "  --force                  Force deletion even if some resources fail"
            echo "  --yes                    Skip confirmation prompts"
            echo "  --preserve-monitoring    Keep monitoring stack (Prometheus/Grafana)"
            echo "  --help                   Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# List available clusters
list_clusters() {
    log "Available EKS clusters:"
    aws eks list-clusters --output table --query 'clusters[?contains(@, `eks-autoscaling-demo`)]' 2>/dev/null || {
        warn "No EKS clusters found or AWS CLI not configured"
        return 1
    }
}

# Interactive cluster selection
select_cluster() {
    if [[ -n "$CLUSTER_NAME" ]]; then
        return 0
    fi
    
    local clusters=($(aws eks list-clusters --query 'clusters[?contains(@, `eks-autoscaling-demo`)]' --output text 2>/dev/null))
    
    if [[ ${#clusters[@]} -eq 0 ]]; then
        error "No EKS clusters found with 'eks-autoscaling-demo' prefix"
    fi
    
    if [[ ${#clusters[@]} -eq 1 ]]; then
        CLUSTER_NAME="${clusters[0]}"
        info "Auto-selected cluster: $CLUSTER_NAME"
        return 0
    fi
    
    echo "Multiple clusters found:"
    for i in "${!clusters[@]}"; do
        echo "$((i+1)). ${clusters[i]}"
    done
    
    while true; do
        read -p "Select cluster to destroy (1-${#clusters[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#clusters[@]}" ]]; then
            CLUSTER_NAME="${clusters[$((choice-1))]}"
            break
        else
            error "Invalid selection. Please enter a number between 1 and ${#clusters[@]}"
        fi
    done
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    warn "This will permanently delete the following resources:"
    echo "  - EKS Cluster: $CLUSTER_NAME"
    echo "  - All worker nodes and node groups"
    echo "  - All deployed applications"
    echo "  - All Kubernetes resources"
    echo "  - All associated AWS resources"
    echo ""
    
    if [[ "$PRESERVE_MONITORING" == "true" ]]; then
        info "Monitoring stack will be preserved"
    else
        warn "Monitoring stack will be deleted"
    fi
    
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured"
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed"
    fi
    
    # Check eksctl
    if ! command -v eksctl &> /dev/null; then
        error "eksctl is not installed"
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        error "Helm is not installed"
    fi
    
    # Set AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            error "AWS region not set"
        fi
    fi
    
    log "Prerequisites check completed"
}

# Verify cluster exists and is accessible
verify_cluster() {
    log "Verifying cluster access..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would verify cluster access"
        return 0
    fi
    
    # Check if cluster exists
    if ! aws eks describe-cluster --name "$CLUSTER_NAME" &> /dev/null; then
        error "Cluster $CLUSTER_NAME not found"
    fi
    
    # Update kubeconfig
    if ! aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"; then
        error "Failed to update kubeconfig for cluster $CLUSTER_NAME"
    fi
    
    # Test cluster connectivity
    if ! kubectl get nodes &> /dev/null; then
        error "Cannot connect to cluster $CLUSTER_NAME"
    fi
    
    log "Cluster verification completed"
}

# Delete test applications
delete_test_applications() {
    log "Deleting test applications..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete test applications"
        return 0
    fi
    
    # Delete load generator
    kubectl delete deployment load-generator -n demo-apps --ignore-not-found=true || {
        if [[ "$FORCE" == "true" ]]; then
            warn "Failed to delete load generator, continuing..."
        else
            error "Failed to delete load generator"
        fi
    }
    
    # Delete any running test pods
    kubectl delete pod metrics-generator -n demo-apps --ignore-not-found=true || true
    
    # Delete node scale test
    kubectl delete deployment node-scale-test -n demo-apps --ignore-not-found=true || true
    
    log "Test applications deleted"
}

# Delete sample applications
delete_sample_applications() {
    log "Deleting sample applications..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete sample applications"
        return 0
    fi
    
    # Delete applications in reverse order of creation
    local apps=("cpu-app.yaml" "memory-app.yaml" "custom-metrics-app.yaml" "pod-disruption-budgets.yaml")
    
    for app in "${apps[@]}"; do
        if [[ -f "$app" ]]; then
            kubectl delete -f "$app" --ignore-not-found=true || {
                if [[ "$FORCE" == "true" ]]; then
                    warn "Failed to delete $app, continuing..."
                else
                    error "Failed to delete $app"
                fi
            }
        fi
    done
    
    # Force delete any remaining resources in demo-apps namespace
    kubectl delete deployment --all -n demo-apps --ignore-not-found=true || true
    kubectl delete hpa --all -n demo-apps --ignore-not-found=true || true
    kubectl delete scaledobject --all -n demo-apps --ignore-not-found=true || true
    kubectl delete pdb --all -n demo-apps --ignore-not-found=true || true
    kubectl delete service --all -n demo-apps --ignore-not-found=true || true
    
    log "Sample applications deleted"
}

# Delete KEDA
delete_keda() {
    log "Deleting KEDA..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete KEDA"
        return 0
    fi
    
    # Uninstall KEDA
    helm uninstall keda -n keda-system --ignore-not-found 2>/dev/null || {
        if [[ "$FORCE" == "true" ]]; then
            warn "Failed to uninstall KEDA, continuing..."
        else
            error "Failed to uninstall KEDA"
        fi
    }
    
    # Delete KEDA namespace
    kubectl delete namespace keda-system --ignore-not-found=true || true
    
    log "KEDA deleted"
}

# Delete monitoring stack
delete_monitoring() {
    if [[ "$PRESERVE_MONITORING" == "true" ]]; then
        log "Preserving monitoring stack as requested"
        return 0
    fi
    
    log "Deleting monitoring stack..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete monitoring stack"
        return 0
    fi
    
    # Uninstall Prometheus
    helm uninstall prometheus -n monitoring --ignore-not-found 2>/dev/null || {
        if [[ "$FORCE" == "true" ]]; then
            warn "Failed to uninstall Prometheus, continuing..."
        else
            error "Failed to uninstall Prometheus"
        fi
    }
    
    # Uninstall Grafana
    helm uninstall grafana -n monitoring --ignore-not-found 2>/dev/null || {
        if [[ "$FORCE" == "true" ]]; then
            warn "Failed to uninstall Grafana, continuing..."
        else
            error "Failed to uninstall Grafana"
        fi
    }
    
    # Delete monitoring namespace
    kubectl delete namespace monitoring --ignore-not-found=true || true
    
    log "Monitoring stack deleted"
}

# Delete cluster autoscaler
delete_cluster_autoscaler() {
    log "Deleting Cluster Autoscaler..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete Cluster Autoscaler"
        return 0
    fi
    
    # Delete cluster autoscaler deployment
    if [[ -f "cluster-autoscaler-autodiscover.yaml" ]]; then
        kubectl delete -f cluster-autoscaler-autodiscover.yaml --ignore-not-found=true || {
            if [[ "$FORCE" == "true" ]]; then
                warn "Failed to delete cluster autoscaler from file, continuing..."
            else
                error "Failed to delete cluster autoscaler from file"
            fi
        }
    else
        # Delete by label if file not found
        kubectl delete deployment cluster-autoscaler -n kube-system --ignore-not-found=true || true
        kubectl delete serviceaccount cluster-autoscaler -n kube-system --ignore-not-found=true || true
        kubectl delete clusterrole cluster-autoscaler --ignore-not-found=true || true
        kubectl delete clusterrolebinding cluster-autoscaler --ignore-not-found=true || true
    fi
    
    log "Cluster Autoscaler deleted"
}

# Delete metrics server
delete_metrics_server() {
    log "Deleting Metrics Server..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete Metrics Server"
        return 0
    fi
    
    # Delete metrics server
    kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml --ignore-not-found=true || {
        if [[ "$FORCE" == "true" ]]; then
            warn "Failed to delete Metrics Server, continuing..."
        else
            error "Failed to delete Metrics Server"
        fi
    }
    
    log "Metrics Server deleted"
}

# Delete namespaces
delete_namespaces() {
    log "Deleting application namespaces..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete namespaces"
        return 0
    fi
    
    # List of namespaces to delete
    local namespaces=("demo-apps")
    
    # Add monitoring namespace if not preserving
    if [[ "$PRESERVE_MONITORING" != "true" ]]; then
        namespaces+=("monitoring")
    fi
    
    for namespace in "${namespaces[@]}"; do
        if kubectl get namespace "$namespace" &> /dev/null; then
            log "Deleting namespace: $namespace"
            kubectl delete namespace "$namespace" --timeout=300s || {
                if [[ "$FORCE" == "true" ]]; then
                    warn "Failed to delete namespace $namespace, continuing..."
                    # Force delete namespace
                    kubectl patch namespace "$namespace" -p '{"metadata":{"finalizers":[]}}' --type=merge || true
                else
                    error "Failed to delete namespace $namespace"
                fi
            }
        fi
    done
    
    log "Namespaces deleted"
}

# Delete VPA (if installed)
delete_vpa() {
    log "Checking for VPA installation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete VPA if installed"
        return 0
    fi
    
    # Check if VPA is installed
    if kubectl get deployment vpa-recommender -n kube-system &> /dev/null; then
        log "Deleting VPA..."
        
        # Delete VPA configurations
        kubectl delete vpa --all --all-namespaces --ignore-not-found=true || true
        
        # Delete VPA components
        kubectl delete deployment vpa-recommender -n kube-system --ignore-not-found=true || true
        kubectl delete deployment vpa-updater -n kube-system --ignore-not-found=true || true
        kubectl delete deployment vpa-admission-controller -n kube-system --ignore-not-found=true || true
        
        log "VPA deleted"
    else
        info "VPA not found, skipping"
    fi
}

# Delete EKS cluster
delete_eks_cluster() {
    log "Deleting EKS cluster..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would delete EKS cluster $CLUSTER_NAME"
        return 0
    fi
    
    # Delete the cluster using eksctl
    if ! eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --wait; then
        if [[ "$FORCE" == "true" ]]; then
            warn "Failed to delete cluster with eksctl, attempting manual cleanup..."
            
            # Manual cleanup of node groups
            local node_groups=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --query 'nodegroups' --output text 2>/dev/null || echo "")
            
            if [[ -n "$node_groups" ]]; then
                for ng in $node_groups; do
                    log "Deleting node group: $ng"
                    aws eks delete-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ng" --region "$AWS_REGION" || true
                done
                
                # Wait for node groups to be deleted
                log "Waiting for node groups to be deleted..."
                sleep 60
            fi
            
            # Delete the cluster
            aws eks delete-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" || true
            
            warn "Manual cleanup completed. Some resources may need to be deleted manually."
        else
            error "Failed to delete EKS cluster"
        fi
    fi
    
    log "EKS cluster deleted"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would clean up local files"
        return 0
    fi
    
    # List of files to clean up
    local files=(
        "cluster-config.yaml"
        "cluster-autoscaler-autodiscover.yaml"
        "cluster-autoscaler-trust-policy.json"
        "cpu-app.yaml"
        "memory-app.yaml"
        "custom-metrics-app.yaml"
        "pod-disruption-budgets.yaml"
        "load-test.yaml"
        "node-scale-test.yaml"
        "vpa-config.yaml"
    )
    
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            info "Removed: $file"
        fi
    done
    
    # Remove autoscaler directory if it exists
    if [[ -d "autoscaler" ]]; then
        rm -rf "autoscaler"
        info "Removed: autoscaler directory"
    fi
    
    log "Local files cleaned up"
}

# Display destruction summary
show_destruction_summary() {
    log "Destruction Summary"
    echo "=================================="
    info "Cluster Name: $CLUSTER_NAME"
    info "AWS Region: $AWS_REGION"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN MODE: No actual resources were deleted"
        return 0
    fi
    
    # Check if cluster still exists
    if aws eks describe-cluster --name "$CLUSTER_NAME" &> /dev/null; then
        warn "Cluster still exists - deletion may have failed"
    else
        log "Cluster successfully deleted"
    fi
    
    # Check for remaining resources
    info "Checking for remaining resources..."
    
    # Check for remaining node groups
    local remaining_ngs=$(aws eks list-nodegroups --cluster-name "$CLUSTER_NAME" --query 'nodegroups' --output text 2>/dev/null || echo "")
    if [[ -n "$remaining_ngs" ]]; then
        warn "Remaining node groups: $remaining_ngs"
    fi
    
    # Check for remaining Auto Scaling Groups
    local remaining_asgs=$(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?contains(AutoScalingGroupName, '$CLUSTER_NAME')].AutoScalingGroupName" --output text 2>/dev/null || echo "")
    if [[ -n "$remaining_asgs" ]]; then
        warn "Remaining Auto Scaling Groups: $remaining_asgs"
    fi
    
    echo "=================================="
    log "Destruction process completed!"
    echo ""
    
    if [[ "$PRESERVE_MONITORING" == "true" ]]; then
        info "Monitoring stack was preserved and may still be running"
    fi
    
    warn "Please check your AWS console for any remaining resources"
    info "Some resources may take additional time to be fully deleted"
}

# Main execution
main() {
    log "Starting EKS Auto-Scaling destruction..."
    
    check_prerequisites
    
    if [[ -z "$CLUSTER_NAME" ]]; then
        list_clusters
        select_cluster
    fi
    
    verify_cluster
    confirm_destruction
    
    delete_test_applications
    delete_sample_applications
    delete_keda
    delete_monitoring
    delete_cluster_autoscaler
    delete_metrics_server
    delete_vpa
    delete_namespaces
    delete_eks_cluster
    cleanup_local_files
    
    show_destruction_summary
    
    log "Destruction process completed successfully!"
}

# Trap to handle script interruption
trap 'error "Script interrupted by user"' INT TERM

# Run main function
main "$@"