#!/bin/bash

# Destroy script for EKS CloudWatch Container Insights
# This script removes all monitoring components and resources created by the deploy script
# WARNING: This will permanently delete monitoring infrastructure and historical data

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy EKS CloudWatch Container Insights monitoring solution.

WARNING: This will permanently delete all monitoring infrastructure including:
- CloudWatch alarms and their history
- SNS topic and subscriptions
- Container Insights data streams
- Kubernetes monitoring resources

OPTIONS:
    -c, --cluster-name CLUSTER_NAME    Name of the EKS cluster (required)
    -r, --region REGION               AWS region (default: us-west-2)
    -f, --force                       Skip confirmation prompts (use with caution)
    -d, --dry-run                     Show what would be deleted without making changes
    -h, --help                        Show this help message

EXAMPLES:
    $0 -c my-eks-cluster
    $0 --cluster-name production-cluster --region us-east-1
    $0 -c test-cluster --force --dry-run

PREREQUISITES:
    - AWS CLI configured with appropriate permissions
    - kubectl configured with cluster access
    - eksctl installed for IRSA management

EOF
}

# Default values
AWS_REGION="us-west-2"
DRY_RUN=false
FORCE=false
CLUSTER_NAME=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$CLUSTER_NAME" ]]; then
    error "Cluster name is required. Use -c or --cluster-name option."
    show_help
    exit 1
fi

log "EKS CloudWatch Container Insights cleanup configuration:"
log "Cluster: $CLUSTER_NAME"
log "Region: $AWS_REGION"
log "Dry run: $DRY_RUN"
log "Force: $FORCE"

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check eksctl
    if ! command -v eksctl &> /dev/null; then
        error "eksctl is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS authentication
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to get user confirmation
confirm_action() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    warning "This action will permanently delete the following resources:"
    warning "  - CloudWatch alarms for cluster: $CLUSTER_NAME"
    warning "  - SNS topic: eks-monitoring-alerts-${CLUSTER_NAME}"
    warning "  - Container Insights data collection for cluster: $CLUSTER_NAME"
    warning "  - All monitoring pods and configurations"
    warning "  - IRSA service account and IAM role"
    warning ""
    warning "Historical monitoring data and alarm history will be lost permanently."
    echo ""
    
    read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " -r
    echo
    if [[ "$REPLY" != "DELETE" ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
}

# Function to safely delete CloudWatch alarms
delete_alarms() {
    log "Checking for CloudWatch alarms..."
    
    local alarm_names=(
        "EKS-${CLUSTER_NAME}-HighCPU"
        "EKS-${CLUSTER_NAME}-HighMemory"
        "EKS-${CLUSTER_NAME}-FailedPods"
    )
    
    local existing_alarms=()
    
    for alarm_name in "${alarm_names[@]}"; do
        if aws cloudwatch describe-alarms \
            --alarm-names "$alarm_name" \
            --region "$AWS_REGION" \
            --query 'MetricAlarms[0].AlarmName' \
            --output text 2>/dev/null | grep -q "$alarm_name"; then
            existing_alarms+=("$alarm_name")
        fi
    done
    
    if [[ ${#existing_alarms[@]} -eq 0 ]]; then
        log "No CloudWatch alarms found for cluster: $CLUSTER_NAME"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete CloudWatch alarms: ${existing_alarms[*]}"
        return 0
    fi
    
    log "Deleting CloudWatch alarms: ${existing_alarms[*]}"
    aws cloudwatch delete-alarms \
        --alarm-names "${existing_alarms[@]}" \
        --region "$AWS_REGION"
    
    success "CloudWatch alarms deleted"
}

# Function to safely delete SNS topic
delete_sns_topic() {
    log "Checking for SNS topic..."
    
    local topic_name="eks-monitoring-alerts-${CLUSTER_NAME}"
    local topic_arn=""
    
    # Try to find the topic
    topic_arn=$(aws sns list-topics \
        --region "$AWS_REGION" \
        --query "Topics[?contains(TopicArn, '${topic_name}')].TopicArn" \
        --output text 2>/dev/null || echo "")
    
    if [[ -z "$topic_arn" || "$topic_arn" == "None" ]]; then
        log "No SNS topic found: $topic_name"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete SNS topic: $topic_arn"
        return 0
    fi
    
    log "Deleting SNS topic: $topic_arn"
    aws sns delete-topic \
        --topic-arn "$topic_arn" \
        --region "$AWS_REGION"
    
    success "SNS topic deleted"
}

# Function to safely delete Kubernetes resources
delete_kubernetes_resources() {
    log "Checking for Kubernetes monitoring resources..."
    
    # Check if namespace exists
    if ! kubectl get namespace amazon-cloudwatch &> /dev/null; then
        log "CloudWatch namespace not found"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete Kubernetes monitoring resources"
        return 0
    fi
    
    log "Deleting Fluent Bit DaemonSet..."
    kubectl delete -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml 2>/dev/null || {
        warning "Failed to delete Fluent Bit using remote manifest, trying local deletion..."
        kubectl delete daemonset fluent-bit -n amazon-cloudwatch 2>/dev/null || true
        kubectl delete configmap fluent-bit-config -n amazon-cloudwatch 2>/dev/null || true
        kubectl delete serviceaccount fluent-bit -n amazon-cloudwatch 2>/dev/null || true
        kubectl delete clusterrole fluent-bit-role 2>/dev/null || true
        kubectl delete clusterrolebinding fluent-bit-role-binding 2>/dev/null || true
    }
    
    log "Deleting CloudWatch Agent DaemonSet..."
    kubectl delete -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-daemonset.yaml 2>/dev/null || {
        warning "Failed to delete CloudWatch Agent using remote manifest, trying local deletion..."
        kubectl delete daemonset cloudwatch-agent -n amazon-cloudwatch 2>/dev/null || true
        kubectl delete configmap cwagentconfig -n amazon-cloudwatch 2>/dev/null || true
    }
    
    success "Kubernetes monitoring resources deleted"
}

# Function to safely delete IRSA service account
delete_irsa_service_account() {
    log "Checking for IRSA service account..."
    
    if ! eksctl get iamserviceaccount \
        --cluster="$CLUSTER_NAME" \
        --name=cloudwatch-agent \
        --namespace=amazon-cloudwatch \
        --region="$AWS_REGION" &> /dev/null; then
        log "IRSA service account not found"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete IRSA service account: cloudwatch-agent"
        return 0
    fi
    
    log "Deleting IRSA service account..."
    eksctl delete iamserviceaccount \
        --name cloudwatch-agent \
        --namespace amazon-cloudwatch \
        --cluster "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --wait
    
    success "IRSA service account deleted"
}

# Function to safely delete CloudWatch namespace
delete_cloudwatch_namespace() {
    log "Checking for CloudWatch namespace..."
    
    if ! kubectl get namespace amazon-cloudwatch &> /dev/null; then
        log "CloudWatch namespace not found"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete namespace: amazon-cloudwatch"
        return 0
    fi
    
    log "Deleting CloudWatch namespace..."
    kubectl delete namespace amazon-cloudwatch --timeout=300s
    
    # Wait for namespace to be fully deleted
    log "Waiting for namespace deletion to complete..."
    while kubectl get namespace amazon-cloudwatch &> /dev/null; do
        log "Waiting for namespace amazon-cloudwatch to be deleted..."
        sleep 10
    done
    
    success "CloudWatch namespace deleted"
}

# Function to disable EKS control plane logging (optional)
disable_control_plane_logging() {
    log "Checking EKS control plane logging..."
    
    local logging_status
    logging_status=$(aws eks describe-cluster \
        --name "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --query 'cluster.logging.clusterLogging[0].enabled' \
        --output text 2>/dev/null || echo "false")
    
    if [[ "$logging_status" == "false" || "$logging_status" == "None" ]]; then
        log "EKS control plane logging is already disabled"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would disable EKS control plane logging"
        return 0
    fi
    
    warning "Disabling EKS control plane logging (this may reduce security visibility)"
    read -p "Do you want to disable control plane logging? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        aws eks update-cluster-config \
            --region "$AWS_REGION" \
            --name "$CLUSTER_NAME" \
            --logging '{"disable":["api","audit","authenticator","controllerManager","scheduler"]}' > /dev/null
        success "EKS control plane logging disabled"
    else
        log "EKS control plane logging left enabled"
    fi
}

# Main cleanup function
cleanup_monitoring() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN MODE - No actual changes will be made"
    fi
    
    # Delete resources in reverse order of creation
    delete_alarms
    delete_sns_topic
    delete_kubernetes_resources
    delete_irsa_service_account
    delete_cloudwatch_namespace
    
    # Optional: disable control plane logging
    if [[ "$FORCE" == "false" ]]; then
        disable_control_plane_logging
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        success "✅ EKS CloudWatch Container Insights cleanup completed successfully!"
        success ""
        success "The following resources have been removed:"
        success "  - CloudWatch alarms for cluster: $CLUSTER_NAME"
        success "  - SNS topic: eks-monitoring-alerts-${CLUSTER_NAME}"
        success "  - Container Insights monitoring pods and configurations"
        success "  - IRSA service account and associated IAM role"
        success "  - CloudWatch namespace and all monitoring resources"
        success ""
        warning "Note: Historical CloudWatch metrics and logs are retained according to your CloudWatch retention settings"
        warning "To permanently delete historical data, manually delete log groups in CloudWatch Logs console"
    else
        log "DRY RUN completed - no actual resources were deleted"
    fi
}

# Error handling function
handle_error() {
    error "Cleanup script encountered an error on line $1"
    error "Some resources may not have been deleted completely"
    error "Please check AWS console and kubectl for any remaining resources"
    exit 1
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# Main execution
main() {
    check_prerequisites
    confirm_action
    cleanup_monitoring
}

# Execute main function
main "$@"