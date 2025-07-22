#!/bin/bash

# Destroy script for EKS Node Groups with Spot Instances and Mixed Instance Types
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Configuration
FORCE_DELETE=${FORCE_DELETE:-false}
DRY_RUN=${DRY_RUN:-false}
CONFIRM_EACH=${CONFIRM_EACH:-false}

if [ "$DRY_RUN" = "true" ]; then
    log_warning "Running in DRY RUN mode - no resources will be deleted"
fi

# Function to confirm destructive actions
confirm_action() {
    local action="$1"
    local resource="$2"
    
    if [ "$FORCE_DELETE" = "true" ]; then
        return 0
    fi
    
    if [ "$CONFIRM_EACH" = "true" ]; then
        echo -e "${YELLOW}Are you sure you want to $action $resource? [y/N]${NC}"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_warning "Skipping $action for $resource"
            return 1
        fi
    fi
    
    return 0
}

# Function to execute commands with dry run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local resource="${3:-}"
    
    if [ -n "$resource" ] && ! confirm_action "delete" "$resource"; then
        return 0
    fi
    
    log "$description"
    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY RUN: $cmd"
        return 0
    else
        eval "$cmd" || {
            log_error "Failed to execute: $cmd"
            return 1
        }
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please configure them first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region is not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Set cluster and node group names (these should match the deployment script)
    export CLUSTER_NAME=${CLUSTER_NAME:-""}
    export SPOT_NODE_GROUP_NAME=${SPOT_NODE_GROUP_NAME:-"spot-mixed-nodegroup"}
    export ONDEMAND_NODE_GROUP_NAME=${ONDEMAND_NODE_GROUP_NAME:-"ondemand-backup-nodegroup"}
    
    # If cluster name is not set, try to detect it
    if [ -z "$CLUSTER_NAME" ]; then
        log_warning "CLUSTER_NAME not set. Attempting to detect from kubectl context..."
        CLUSTER_NAME=$(kubectl config current-context 2>/dev/null | sed 's/.*\///g' || echo "")
        if [ -z "$CLUSTER_NAME" ]; then
            log_error "Cannot determine cluster name. Please set CLUSTER_NAME environment variable."
            log "Available clusters:"
            aws eks list-clusters --query clusters --output table
            exit 1
        fi
    fi
    
    log_success "Environment variables configured"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "Cluster Name: $CLUSTER_NAME"
}

# Remove test applications
remove_test_applications() {
    log "Removing test applications..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Skipping test application removal"
        return 0
    fi
    
    # Remove demo application
    if kubectl get deployment spot-demo-app &>/dev/null; then
        execute_cmd "kubectl delete deployment spot-demo-app" \
            "Removing demo application deployment"
    else
        log_warning "Demo application deployment not found, skipping"
    fi
    
    # Remove demo service
    if kubectl get service spot-demo-service &>/dev/null; then
        execute_cmd "kubectl delete service spot-demo-service" \
            "Removing demo application service"
    else
        log_warning "Demo application service not found, skipping"
    fi
    
    # Remove pod disruption budget
    if kubectl get pdb spot-workload-pdb &>/dev/null; then
        execute_cmd "kubectl delete pdb spot-workload-pdb" \
            "Removing pod disruption budget"
    else
        log_warning "Pod disruption budget not found, skipping"
    fi
    
    log_success "Test applications removed"
}

# Remove Kubernetes components
remove_kubernetes_components() {
    log "Removing Kubernetes components..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Skipping Kubernetes component removal"
        return 0
    fi
    
    # Remove cluster autoscaler
    if kubectl get deployment cluster-autoscaler -n kube-system &>/dev/null; then
        execute_cmd "kubectl delete -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml" \
            "Removing cluster autoscaler"
    else
        log_warning "Cluster autoscaler not found, skipping"
    fi
    
    # Remove cluster autoscaler service account
    if kubectl get serviceaccount cluster-autoscaler -n kube-system &>/dev/null; then
        execute_cmd "kubectl delete serviceaccount cluster-autoscaler --namespace kube-system" \
            "Removing cluster autoscaler service account"
    else
        log_warning "Cluster autoscaler service account not found, skipping"
    fi
    
    # Remove AWS Node Termination Handler
    if kubectl get daemonset aws-node-termination-handler -n kube-system &>/dev/null; then
        execute_cmd "kubectl delete -f https://github.com/aws/aws-node-termination-handler/releases/download/v1.21.0/all-resources.yaml" \
            "Removing AWS Node Termination Handler"
    else
        log_warning "AWS Node Termination Handler not found, skipping"
    fi
    
    log_success "Kubernetes components removed"
}

# Remove node groups
remove_node_groups() {
    log "Removing EKS node groups..."
    
    # Remove spot node group
    if aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$SPOT_NODE_GROUP_NAME" &>/dev/null; then
        execute_cmd "aws eks delete-nodegroup \
            --cluster-name '$CLUSTER_NAME' \
            --nodegroup-name '$SPOT_NODE_GROUP_NAME'" \
            "Removing spot node group" \
            "spot node group ($SPOT_NODE_GROUP_NAME)"
    else
        log_warning "Spot node group '$SPOT_NODE_GROUP_NAME' not found, skipping"
    fi
    
    # Remove on-demand node group
    if aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ONDEMAND_NODE_GROUP_NAME" &>/dev/null; then
        execute_cmd "aws eks delete-nodegroup \
            --cluster-name '$CLUSTER_NAME' \
            --nodegroup-name '$ONDEMAND_NODE_GROUP_NAME'" \
            "Removing on-demand node group" \
            "on-demand node group ($ONDEMAND_NODE_GROUP_NAME)"
    else
        log_warning "On-demand node group '$ONDEMAND_NODE_GROUP_NAME' not found, skipping"
    fi
    
    log_success "Node group deletion initiated"
}

# Wait for node groups to be deleted
wait_for_node_groups_deletion() {
    log "Waiting for node groups to be deleted..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Skipping wait for node group deletion"
        return 0
    fi
    
    # Wait for spot node group deletion
    if aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$SPOT_NODE_GROUP_NAME" &>/dev/null; then
        log "Waiting for spot node group to be deleted..."
        aws eks wait nodegroup-deleted \
            --cluster-name "$CLUSTER_NAME" \
            --nodegroup-name "$SPOT_NODE_GROUP_NAME"
        log_success "Spot node group deleted"
    fi
    
    # Wait for on-demand node group deletion
    if aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ONDEMAND_NODE_GROUP_NAME" &>/dev/null; then
        log "Waiting for on-demand node group to be deleted..."
        aws eks wait nodegroup-deleted \
            --cluster-name "$CLUSTER_NAME" \
            --nodegroup-name "$ONDEMAND_NODE_GROUP_NAME"
        log_success "On-demand node group deleted"
    fi
    
    log_success "All node groups deleted"
}

# Remove IAM roles and policies
remove_iam_resources() {
    log "Removing IAM roles and policies..."
    
    # Find roles with the cluster name pattern
    local roles=($(aws iam list-roles --query "Roles[?contains(RoleName, '$CLUSTER_NAME') || contains(RoleName, 'EKSNodeGroupRole') || contains(RoleName, 'ClusterAutoscalerRole')].RoleName" --output text))
    
    for role in "${roles[@]}"; do
        if [ -n "$role" ]; then
            # Get attached policies
            local policies=($(aws iam list-attached-role-policies --role-name "$role" --query "AttachedPolicies[].PolicyArn" --output text 2>/dev/null || echo ""))
            
            # Detach policies
            for policy in "${policies[@]}"; do
                if [ -n "$policy" ]; then
                    execute_cmd "aws iam detach-role-policy \
                        --role-name '$role' \
                        --policy-arn '$policy'" \
                        "Detaching policy from role: $role" \
                        "IAM policy attachment"
                fi
            done
            
            # Delete role
            execute_cmd "aws iam delete-role --role-name '$role'" \
                "Deleting IAM role: $role" \
                "IAM role ($role)"
        fi
    done
    
    # Remove cluster autoscaler policy
    local policy_name="ClusterAutoscalerPolicy"
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${policy_name}"
    
    if aws iam get-policy --policy-arn "$policy_arn" &>/dev/null; then
        execute_cmd "aws iam delete-policy --policy-arn '$policy_arn'" \
            "Deleting cluster autoscaler policy" \
            "cluster autoscaler policy"
    else
        log_warning "Cluster autoscaler policy not found, skipping"
    fi
    
    log_success "IAM resources removed"
}

# Remove CloudWatch resources
remove_cloudwatch_resources() {
    log "Removing CloudWatch resources..."
    
    # Remove CloudWatch log group
    local log_group_name="/aws/eks/${CLUSTER_NAME}/spot-interruptions"
    
    if aws logs describe-log-groups --log-group-name-prefix "$log_group_name" | grep -q "logGroups"; then
        execute_cmd "aws logs delete-log-group \
            --log-group-name '$log_group_name'" \
            "Removing CloudWatch log group" \
            "CloudWatch log group ($log_group_name)"
    else
        log_warning "CloudWatch log group not found, skipping"
    fi
    
    # Remove CloudWatch alarms
    local alarm_name="EKS-${CLUSTER_NAME}-HighSpotInterruptions"
    
    if aws cloudwatch describe-alarms --alarm-names "$alarm_name" | grep -q "MetricAlarms"; then
        execute_cmd "aws cloudwatch delete-alarms --alarm-names '$alarm_name'" \
            "Removing CloudWatch alarm" \
            "CloudWatch alarm ($alarm_name)"
    else
        log_warning "CloudWatch alarm not found, skipping"
    fi
    
    log_success "CloudWatch resources removed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files that might have been created
    local temp_files=(
        "/tmp/node-group-trust-policy.json"
        "/tmp/cluster-autoscaler-policy.json"
        "/tmp/spot-demo-app.yaml"
        "/tmp/spot-pdb.yaml"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -f "$file" ]; then
            execute_cmd "rm -f '$file'" \
                "Removing temporary file: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Validation function
validate_cleanup() {
    log "Validating cleanup..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Skipping cleanup validation"
        return 0
    fi
    
    local errors=0
    
    # Check if node groups still exist
    if aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$SPOT_NODE_GROUP_NAME" &>/dev/null; then
        log_error "Spot node group still exists"
        errors=$((errors + 1))
    fi
    
    if aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ONDEMAND_NODE_GROUP_NAME" &>/dev/null; then
        log_error "On-demand node group still exists"
        errors=$((errors + 1))
    fi
    
    # Check if Kubernetes components still exist
    if kubectl get deployment spot-demo-app &>/dev/null; then
        log_error "Demo application still exists"
        errors=$((errors + 1))
    fi
    
    if kubectl get daemonset aws-node-termination-handler -n kube-system &>/dev/null; then
        log_error "AWS Node Termination Handler still exists"
        errors=$((errors + 1))
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "Cleanup validation completed successfully"
    else
        log_error "Cleanup validation found $errors remaining resources"
        return 1
    fi
}

# Main destroy function
main() {
    log "Starting EKS Node Groups with Spot Instances cleanup..."
    
    # Check for help flag
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        cat << EOF
Usage: $0 [OPTIONS]

Remove EKS node groups with spot instances and all related resources.

Options:
  --help, -h          Show this help message
  --dry-run           Run in dry-run mode (no resources deleted)
  --force             Skip confirmation prompts
  --confirm-each      Confirm each resource deletion individually
  --cluster-name      Specify EKS cluster name
  --region            Specify AWS region (default: from AWS config)

Environment Variables:
  DRY_RUN             Set to 'true' for dry-run mode
  FORCE_DELETE        Set to 'true' to skip confirmations
  CONFIRM_EACH        Set to 'true' to confirm each deletion
  CLUSTER_NAME        EKS cluster name
  AWS_REGION          AWS region

Examples:
  $0                                  # Interactive cleanup
  $0 --force                          # Force cleanup without prompts
  $0 --dry-run                        # Dry run mode
  $0 --cluster-name my-cluster        # Specify cluster
  FORCE_DELETE=true $0                # Environment variable force

WARNING: This script will delete all resources created by the deployment script.
Make sure you have backed up any important data before proceeding.

EOF
        exit 0
    fi
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --confirm-each)
                CONFIRM_EACH=true
                shift
                ;;
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Final confirmation unless force is enabled
    if [ "$FORCE_DELETE" != "true" ] && [ "$DRY_RUN" != "true" ]; then
        echo -e "${RED}WARNING: This will delete all EKS node groups and related resources.${NC}"
        echo -e "${RED}This action cannot be undone.${NC}"
        echo ""
        echo -e "${YELLOW}Are you sure you want to proceed? [y/N]${NC}"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Run cleanup steps
    check_prerequisites
    setup_environment
    remove_test_applications
    remove_kubernetes_components
    remove_node_groups
    wait_for_node_groups_deletion
    remove_iam_resources
    remove_cloudwatch_resources
    cleanup_local_files
    validate_cleanup
    
    log_success "EKS Node Groups with Spot Instances cleanup completed successfully!"
    log ""
    log "Summary of deleted resources:"
    log "- EKS node groups (spot and on-demand)"
    log "- IAM roles and policies"
    log "- Kubernetes applications and components"
    log "- CloudWatch log groups and alarms"
    log "- Local temporary files"
    log ""
    log "Note: The EKS cluster itself was not deleted and can be reused."
}

# Run main function with all arguments
main "$@"