#!/bin/bash

# AWS EKS Container Resource Optimization Cleanup Script
# This script removes all resources created by the deployment script

set -e
set -o pipefail

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
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Some resources may still exist."
    exit 1
}

# Continue on error for cleanup operations
continue_on_error() {
    log_warning "$1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set up AWS credentials."
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        error_exit "kubectl is not installed. Please install kubectl."
    fi
    
    log_success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        error_exit "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log_success "Environment variables configured"
    log_info "AWS Region: $AWS_REGION"
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
}

# Validate EKS cluster connectivity
validate_cluster() {
    log_info "Validating EKS cluster connectivity..."
    
    if [ -z "$CLUSTER_NAME" ]; then
        # Try to detect cluster from kubeconfig
        CLUSTER_NAME=$(kubectl config current-context 2>/dev/null | cut -d'/' -f2 2>/dev/null || echo "")
        
        if [ -z "$CLUSTER_NAME" ]; then
            read -p "Enter your EKS cluster name: " CLUSTER_NAME
        fi
        export CLUSTER_NAME
    fi
    
    # Update kubeconfig
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" 2>/dev/null || \
        log_warning "Failed to update kubeconfig for cluster $CLUSTER_NAME"
    
    # Test cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_warning "Cannot connect to EKS cluster. Some Kubernetes resources may not be cleaned up."
        CLUSTER_ACCESSIBLE=false
    else
        log_success "EKS cluster connectivity validated"
        CLUSTER_ACCESSIBLE=true
    fi
}

# Find random suffix from existing resources
find_random_suffix() {
    log_info "Finding random suffix from existing resources..."
    
    # Try to find the suffix from CloudWatch dashboards
    local dashboards=$(aws cloudwatch list-dashboards --query 'DashboardEntries[?starts_with(DashboardName, `EKS-Cost-Optimization-`)].DashboardName' --output text 2>/dev/null || echo "")
    
    if [ -n "$dashboards" ]; then
        # Extract suffix from dashboard name
        RANDOM_SUFFIX=$(echo "$dashboards" | head -1 | sed 's/EKS-Cost-Optimization-//')
        log_info "Found random suffix: $RANDOM_SUFFIX"
    else
        # Try to find from SNS topics
        local topics=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `eks-cost-optimization-alerts-`)].TopicArn' --output text 2>/dev/null || echo "")
        
        if [ -n "$topics" ]; then
            RANDOM_SUFFIX=$(echo "$topics" | head -1 | sed 's/.*eks-cost-optimization-alerts-//' | sed 's/:.*$//')
            log_info "Found random suffix from SNS: $RANDOM_SUFFIX"
        else
            log_warning "Could not find random suffix. Will attempt cleanup of all matching resources."
            RANDOM_SUFFIX=""
        fi
    fi
}

# Confirmation prompt
confirm_cleanup() {
    echo ""
    echo "========================================"
    echo "         CLEANUP CONFIRMATION"
    echo "========================================"
    echo "This will DELETE the following resources:"
    echo "- VPA (Vertical Pod Autoscaler) components"
    echo "- Test applications and VPA policies"
    echo "- CloudWatch Container Insights"
    echo "- CloudWatch dashboards and alarms"
    echo "- SNS topics and subscriptions"
    echo "- cost-optimization namespace"
    echo "- Generated scripts and files"
    echo ""
    echo "Cluster: ${CLUSTER_NAME:-"Not detected"}"
    echo "Region: $AWS_REGION"
    echo "Random Suffix: ${RANDOM_SUFFIX:-"Not found - will cleanup all matching resources"}"
    echo ""
    
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Remove VPA components
remove_vpa_components() {
    log_info "Removing VPA components..."
    
    if [ "$CLUSTER_ACCESSIBLE" = false ]; then
        log_warning "Skipping VPA removal - cluster not accessible"
        return 0
    fi
    
    # Check if VPA components exist
    if ! kubectl get pods -n kube-system | grep -q vpa 2>/dev/null; then
        log_warning "VPA components not found"
        return 0
    fi
    
    # Create temporary directory for VPA removal
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Clone the VPA repository for cleanup script
    log_info "Downloading VPA source code for cleanup..."
    if git clone https://github.com/kubernetes/autoscaler.git 2>/dev/null; then
        cd autoscaler/vertical-pod-autoscaler/
        
        # Run VPA cleanup script
        if [ -f "./hack/vpa-down.sh" ]; then
            ./hack/vpa-down.sh || continue_on_error "VPA cleanup script failed"
        else
            log_warning "VPA cleanup script not found, attempting manual cleanup"
            # Manual cleanup
            kubectl delete deployment vpa-recommender -n kube-system 2>/dev/null || true
            kubectl delete deployment vpa-updater -n kube-system 2>/dev/null || true
            kubectl delete deployment vpa-admission-controller -n kube-system 2>/dev/null || true
            kubectl delete service vpa-webhook -n kube-system 2>/dev/null || true
            kubectl delete crd verticalpodautoscalers.autoscaling.k8s.io 2>/dev/null || true
        fi
    else
        log_warning "Failed to clone VPA repository, attempting manual cleanup"
        # Manual cleanup
        kubectl delete deployment vpa-recommender -n kube-system 2>/dev/null || true
        kubectl delete deployment vpa-updater -n kube-system 2>/dev/null || true
        kubectl delete deployment vpa-admission-controller -n kube-system 2>/dev/null || true
        kubectl delete service vpa-webhook -n kube-system 2>/dev/null || true
        kubectl delete crd verticalpodautoscalers.autoscaling.k8s.io 2>/dev/null || true
    fi
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    log_success "VPA components removed"
}

# Remove test applications and VPA policies
remove_test_applications() {
    log_info "Removing test applications and VPA policies..."
    
    if [ "$CLUSTER_ACCESSIBLE" = false ]; then
        log_warning "Skipping test application removal - cluster not accessible"
        return 0
    fi
    
    # Delete test application and VPA policies
    kubectl delete deployment resource-test-app -n cost-optimization 2>/dev/null || \
        continue_on_error "Failed to delete test application deployment"
    
    kubectl delete service resource-test-app -n cost-optimization 2>/dev/null || \
        continue_on_error "Failed to delete test application service"
    
    kubectl delete vpa resource-test-app-vpa -n cost-optimization 2>/dev/null || \
        continue_on_error "Failed to delete VPA policy (off mode)"
    
    kubectl delete vpa resource-test-app-vpa-auto -n cost-optimization 2>/dev/null || \
        continue_on_error "Failed to delete VPA policy (auto mode)"
    
    # Delete any running load generators
    kubectl delete pod load-generator -n cost-optimization 2>/dev/null || true
    
    log_success "Test applications and VPA policies removed"
}

# Remove CloudWatch resources
remove_cloudwatch_resources() {
    log_info "Removing CloudWatch resources..."
    
    # Remove CloudWatch dashboards
    if [ -n "$RANDOM_SUFFIX" ]; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "EKS-Cost-Optimization-${RANDOM_SUFFIX}" 2>/dev/null || \
            continue_on_error "Failed to delete specific CloudWatch dashboard"
    else
        # Find and delete all matching dashboards
        local dashboards=$(aws cloudwatch list-dashboards --query 'DashboardEntries[?starts_with(DashboardName, `EKS-Cost-Optimization-`)].DashboardName' --output text 2>/dev/null || echo "")
        if [ -n "$dashboards" ]; then
            for dashboard in $dashboards; do
                aws cloudwatch delete-dashboards --dashboard-names "$dashboard" 2>/dev/null || \
                    continue_on_error "Failed to delete CloudWatch dashboard: $dashboard"
            done
        fi
    fi
    
    # Remove CloudWatch alarms
    if [ -n "$RANDOM_SUFFIX" ]; then
        aws cloudwatch delete-alarms \
            --alarm-names "EKS-High-Resource-Waste-${RANDOM_SUFFIX}" 2>/dev/null || \
            continue_on_error "Failed to delete specific CloudWatch alarm"
    else
        # Find and delete all matching alarms
        local alarms=$(aws cloudwatch describe-alarms --query 'MetricAlarms[?starts_with(AlarmName, `EKS-High-Resource-Waste-`)].AlarmName' --output text 2>/dev/null || echo "")
        if [ -n "$alarms" ]; then
            for alarm in $alarms; do
                aws cloudwatch delete-alarms --alarm-names "$alarm" 2>/dev/null || \
                    continue_on_error "Failed to delete CloudWatch alarm: $alarm"
            done
        fi
    fi
    
    log_success "CloudWatch resources removed"
}

# Remove SNS resources
remove_sns_resources() {
    log_info "Removing SNS resources..."
    
    # Remove SNS topics
    if [ -n "$RANDOM_SUFFIX" ]; then
        local topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:eks-cost-optimization-alerts-${RANDOM_SUFFIX}"
        aws sns delete-topic --topic-arn "$topic_arn" 2>/dev/null || \
            continue_on_error "Failed to delete specific SNS topic"
    else
        # Find and delete all matching topics
        local topics=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `eks-cost-optimization-alerts-`)].TopicArn' --output text 2>/dev/null || echo "")
        if [ -n "$topics" ]; then
            for topic in $topics; do
                aws sns delete-topic --topic-arn "$topic" 2>/dev/null || \
                    continue_on_error "Failed to delete SNS topic: $topic"
            done
        fi
    fi
    
    log_success "SNS resources removed"
}

# Remove Container Insights
remove_container_insights() {
    log_info "Removing CloudWatch Container Insights..."
    
    if [ "$CLUSTER_ACCESSIBLE" = false ]; then
        log_warning "Skipping Container Insights removal - cluster not accessible"
        return 0
    fi
    
    # Remove CloudWatch agent and related resources
    kubectl delete namespace amazon-cloudwatch 2>/dev/null || \
        continue_on_error "Failed to delete amazon-cloudwatch namespace"
    
    # Remove any leftover ConfigMaps
    kubectl delete configmap cwagentconfig -n amazon-cloudwatch 2>/dev/null || true
    
    log_success "CloudWatch Container Insights removed"
}

# Remove Metrics Server (optional - ask user)
remove_metrics_server() {
    if [ "$CLUSTER_ACCESSIBLE" = false ]; then
        log_warning "Skipping Metrics Server removal check - cluster not accessible"
        return 0
    fi
    
    # Check if Metrics Server exists
    if ! kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        log_info "Metrics Server not found"
        return 0
    fi
    
    echo ""
    log_info "Metrics Server is installed on your cluster."
    log_warning "Removing Metrics Server may affect other applications that depend on it (like HPA)."
    read -p "Do you want to remove Metrics Server? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Removing Metrics Server..."
        kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml 2>/dev/null || \
            continue_on_error "Failed to remove Metrics Server"
        log_success "Metrics Server removed"
    else
        log_info "Metrics Server preserved"
    fi
}

# Remove namespace and local files
remove_namespace_and_files() {
    log_info "Removing namespace and local files..."
    
    if [ "$CLUSTER_ACCESSIBLE" = true ]; then
        # Remove cost-optimization namespace
        kubectl delete namespace cost-optimization 2>/dev/null || \
            continue_on_error "Failed to delete cost-optimization namespace"
    fi
    
    # Clean up local files
    rm -f generate-vpa-recommendations.sh 2>/dev/null || true
    rm -f cost-optimization-lambda.py 2>/dev/null || true
    
    # Remove any autoscaler directory if it exists
    rm -rf autoscaler/ 2>/dev/null || true
    
    log_success "Namespace and local files removed"
}

# Disable cluster logging (optional)
disable_cluster_logging() {
    if [ -z "$CLUSTER_NAME" ]; then
        log_warning "Cluster name not available, skipping logging disable"
        return 0
    fi
    
    echo ""
    read -p "Do you want to disable EKS cluster logging? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Disabling EKS cluster logging..."
        aws eks put-cluster-logging \
            --region "$AWS_REGION" \
            --name "$CLUSTER_NAME" \
            --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":false}]}' 2>/dev/null || \
            continue_on_error "Failed to disable cluster logging"
        log_success "EKS cluster logging disabled"
    else
        log_info "EKS cluster logging preserved"
    fi
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local cleanup_issues=0
    
    # Check for remaining VPA components
    if [ "$CLUSTER_ACCESSIBLE" = true ]; then
        if kubectl get pods -n kube-system | grep -q vpa 2>/dev/null; then
            log_warning "Some VPA components may still exist"
            cleanup_issues=$((cleanup_issues + 1))
        fi
        
        # Check for remaining namespace
        if kubectl get namespace cost-optimization &> /dev/null; then
            log_warning "cost-optimization namespace still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
        
        # Check for remaining VPA CRDs
        if kubectl get crd verticalpodautoscalers.autoscaling.k8s.io &> /dev/null; then
            log_warning "VPA CRD still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check for remaining CloudWatch resources
    local remaining_dashboards=$(aws cloudwatch list-dashboards --query 'DashboardEntries[?starts_with(DashboardName, `EKS-Cost-Optimization-`)].DashboardName' --output text 2>/dev/null || echo "")
    if [ -n "$remaining_dashboards" ]; then
        log_warning "Some CloudWatch dashboards may still exist: $remaining_dashboards"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    local remaining_alarms=$(aws cloudwatch describe-alarms --query 'MetricAlarms[?starts_with(AlarmName, `EKS-High-Resource-Waste-`)].AlarmName' --output text 2>/dev/null || echo "")
    if [ -n "$remaining_alarms" ]; then
        log_warning "Some CloudWatch alarms may still exist: $remaining_alarms"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check for remaining SNS topics
    local remaining_topics=$(aws sns list-topics --query 'Topics[?contains(TopicArn, `eks-cost-optimization-alerts-`)].TopicArn' --output text 2>/dev/null || echo "")
    if [ -n "$remaining_topics" ]; then
        log_warning "Some SNS topics may still exist: $remaining_topics"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log_success "Cleanup verification passed"
    else
        log_warning "Cleanup verification found $cleanup_issues potential issues"
        log_info "You may need to manually remove some remaining resources"
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    echo ""
    echo "========================================"
    echo "         CLEANUP SUMMARY"
    echo "========================================"
    echo "Cleanup operations completed for:"
    echo "- VPA (Vertical Pod Autoscaler) components"
    echo "- Test applications and VPA policies"
    echo "- CloudWatch dashboards and alarms"
    echo "- SNS topics and subscriptions"
    echo "- CloudWatch Container Insights"
    echo "- cost-optimization namespace"
    echo "- Generated scripts and files"
    echo ""
    echo "Cluster: ${CLUSTER_NAME:-"Not specified"}"
    echo "Region: $AWS_REGION"
    echo "Random Suffix: ${RANDOM_SUFFIX:-"Not found"}"
    echo ""
    
    if [ "$CLUSTER_ACCESSIBLE" = false ]; then
        log_warning "Some Kubernetes resources may not have been cleaned up due to cluster connectivity issues"
    fi
    
    log_success "Cleanup completed!"
    echo ""
    log_info "If you encounter any issues, you can manually check for remaining resources:"
    echo "- kubectl get all -n cost-optimization"
    echo "- aws cloudwatch list-dashboards"
    echo "- aws cloudwatch describe-alarms"
    echo "- aws sns list-topics"
}

# Main cleanup function
main() {
    echo "========================================"
    echo "  EKS Container Resource Optimization"
    echo "         Cleanup Script"
    echo "========================================"
    echo ""
    
    check_prerequisites
    setup_environment
    validate_cluster
    find_random_suffix
    confirm_cleanup
    
    log_info "Starting cleanup process..."
    
    remove_test_applications
    remove_vpa_components
    remove_cloudwatch_resources
    remove_sns_resources
    remove_container_insights
    remove_metrics_server
    remove_namespace_and_files
    disable_cluster_logging
    verify_cleanup
    show_cleanup_summary
}

# Run main function
main "$@"