#!/bin/bash

# Real-Time Streaming Analytics with EMR on EKS and Apache Flink - Cleanup Script
# This script safely removes all resources created by the deployment script

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

# Error handling (continue on errors for cleanup)
error_continue() {
    log_error "$1"
    log_warning "Continuing with cleanup..."
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [ -f .env ]; then
        source .env
        log_success "Environment loaded from .env file"
    else
        log_warning ".env file not found, using defaults or prompting for values"
        
        # Prompt for required values if not found
        read -p "Enter AWS Region [us-west-2]: " AWS_REGION
        AWS_REGION=${AWS_REGION:-us-west-2}
        
        read -p "Enter EKS Cluster Name [emr-flink-analytics]: " CLUSTER_NAME
        CLUSTER_NAME=${CLUSTER_NAME:-emr-flink-analytics}
        
        read -p "Enter EMR Namespace [emr-flink]: " EMR_NAMESPACE
        EMR_NAMESPACE=${EMR_NAMESPACE:-emr-flink}
        
        # Try to derive other values
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    fi
    
    # Set defaults for missing values
    export AWS_REGION=${AWS_REGION:-us-west-2}
    export CLUSTER_NAME=${CLUSTER_NAME:-emr-flink-analytics}
    export EMR_NAMESPACE=${EMR_NAMESPACE:-emr-flink}
    
    log_info "Using configuration:"
    log_info "  AWS Region: $AWS_REGION"
    log_info "  Cluster Name: $CLUSTER_NAME"
    log_info "  EMR Namespace: $EMR_NAMESPACE"
}

# Confirmation prompt
confirm_destruction() {
    echo
    log_warning "This will destroy the following resources:"
    log_warning "  - EKS Cluster: $CLUSTER_NAME"
    log_warning "  - EMR Virtual Cluster"
    log_warning "  - S3 Bucket: $BUCKET_NAME (if defined)"
    log_warning "  - Kinesis Streams: $STREAM_NAME_TRADING, $STREAM_NAME_MARKET (if defined)"
    log_warning "  - IAM Roles: EMRContainersServiceRole, EMRFlinkJobExecutionRole"
    log_warning "  - All Flink applications and monitoring components"
    echo
    
    if [[ "${FORCE_DESTROY:-false}" != "true" ]]; then
        read -p "Are you sure you want to proceed? (yes/no): " confirm
        if [[ $confirm != "yes" ]]; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    fi
}

# Remove Flink applications
remove_flink_applications() {
    log_info "Removing Flink applications..."
    
    if ! command_exists kubectl; then
        log_warning "kubectl not found, skipping Kubernetes resource cleanup"
        return 0
    fi
    
    # Check if cluster context is available
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_warning "No active Kubernetes context, skipping Flink application cleanup"
        return 0
    fi
    
    # Delete Flink deployments
    kubectl delete flinkdeployment fraud-detection -n ${EMR_NAMESPACE} --ignore-not-found=true || error_continue "Failed to delete fraud-detection deployment"
    kubectl delete flinkdeployment risk-analytics -n ${EMR_NAMESPACE} --ignore-not-found=true || error_continue "Failed to delete risk-analytics deployment"
    
    # Delete data generator
    kubectl delete deployment trading-data-generator -n ${EMR_NAMESPACE} --ignore-not-found=true || error_continue "Failed to delete data generator"
    
    # Wait for graceful shutdown
    log_info "Waiting for graceful shutdown of Flink applications..."
    sleep 30
    
    log_success "Flink applications removed"
}

# Remove monitoring components
remove_monitoring() {
    log_info "Removing monitoring components..."
    
    if ! command_exists helm; then
        log_warning "Helm not found, skipping Helm release cleanup"
        return 0
    fi
    
    if ! command_exists kubectl; then
        log_warning "kubectl not found, skipping monitoring cleanup"
        return 0
    fi
    
    # Remove Helm releases
    helm uninstall prometheus -n monitoring --ignore-not-found || error_continue "Failed to uninstall Prometheus"
    helm uninstall flink-kubernetes-operator -n ${EMR_NAMESPACE} --ignore-not-found || error_continue "Failed to uninstall Flink operator"
    
    # Delete monitoring namespace
    kubectl delete namespace monitoring --ignore-not-found=true || error_continue "Failed to delete monitoring namespace"
    
    log_success "Monitoring components removed"
}

# Remove EMR virtual cluster
remove_emr_virtual_cluster() {
    log_info "Removing EMR virtual cluster..."
    
    # Find and delete virtual cluster
    if [ -n "$VIRTUAL_CLUSTER_ID" ]; then
        aws emr-containers delete-virtual-cluster --id ${VIRTUAL_CLUSTER_ID} || error_continue "Failed to delete virtual cluster $VIRTUAL_CLUSTER_ID"
        log_success "EMR virtual cluster $VIRTUAL_CLUSTER_ID deletion initiated"
    else
        # Try to find virtual cluster by name
        VIRTUAL_CLUSTER_ID=$(aws emr-containers list-virtual-clusters \
            --query "virtualClusters[?name=='flink-analytics-cluster' && state=='RUNNING'].id" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$VIRTUAL_CLUSTER_ID" ] && [ "$VIRTUAL_CLUSTER_ID" != "None" ]; then
            aws emr-containers delete-virtual-cluster --id ${VIRTUAL_CLUSTER_ID} || error_continue "Failed to delete virtual cluster $VIRTUAL_CLUSTER_ID"
            log_success "EMR virtual cluster $VIRTUAL_CLUSTER_ID deletion initiated"
        else
            log_warning "No active EMR virtual cluster found"
        fi
    fi
}

# Remove AWS resources
remove_aws_resources() {
    log_info "Removing AWS resources..."
    
    # Delete Kinesis streams
    if [ -n "$STREAM_NAME_TRADING" ]; then
        aws kinesis delete-stream --stream-name ${STREAM_NAME_TRADING} --enforce-consumer-deletion || error_continue "Failed to delete Kinesis stream $STREAM_NAME_TRADING"
        log_success "Kinesis stream $STREAM_NAME_TRADING deletion initiated"
    fi
    
    if [ -n "$STREAM_NAME_MARKET" ]; then
        aws kinesis delete-stream --stream-name ${STREAM_NAME_MARKET} --enforce-consumer-deletion || error_continue "Failed to delete Kinesis stream $STREAM_NAME_MARKET"
        log_success "Kinesis stream $STREAM_NAME_MARKET deletion initiated"
    fi
    
    # Empty and delete S3 bucket
    if [ -n "$BUCKET_NAME" ]; then
        log_info "Emptying S3 bucket: $BUCKET_NAME"
        aws s3 rm s3://${BUCKET_NAME} --recursive || error_continue "Failed to empty S3 bucket $BUCKET_NAME"
        aws s3 rb s3://${BUCKET_NAME} || error_continue "Failed to delete S3 bucket $BUCKET_NAME"
        log_success "S3 bucket $BUCKET_NAME removed"
    fi
    
    # Delete CloudWatch log groups
    log_info "Cleaning up CloudWatch log groups..."
    aws logs describe-log-groups --log-group-name-prefix "/aws/emr-containers" \
        --query 'logGroups[].logGroupName' --output text 2>/dev/null | \
        xargs -r -n1 aws logs delete-log-group --log-group-name || error_continue "Failed to delete some CloudWatch log groups"
}

# Remove IAM roles
remove_iam_roles() {
    log_info "Removing IAM roles..."
    
    # Remove EMR Flink job execution role
    if aws iam get-role --role-name EMRFlinkJobExecutionRole >/dev/null 2>&1; then
        # Detach policies
        aws iam detach-role-policy \
            --role-name EMRFlinkJobExecutionRole \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess || error_continue "Failed to detach S3 policy"
        
        aws iam detach-role-policy \
            --role-name EMRFlinkJobExecutionRole \
            --policy-arn arn:aws:iam::aws:policy/AmazonKinesisFullAccess || error_continue "Failed to detach Kinesis policy"
        
        aws iam detach-role-policy \
            --role-name EMRFlinkJobExecutionRole \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess || error_continue "Failed to detach CloudWatch policy"
        
        # Delete role
        aws iam delete-role --role-name EMRFlinkJobExecutionRole || error_continue "Failed to delete EMRFlinkJobExecutionRole"
        log_success "EMRFlinkJobExecutionRole removed"
    else
        log_warning "EMRFlinkJobExecutionRole not found"
    fi
    
    # Remove EMR containers service role
    if aws iam get-role --role-name EMRContainersServiceRole >/dev/null 2>&1; then
        aws iam detach-role-policy \
            --role-name EMRContainersServiceRole \
            --policy-arn arn:aws:iam::aws:policy/AmazonEMRContainersServiceRolePolicy || error_continue "Failed to detach EMR policy"
        
        aws iam delete-role --role-name EMRContainersServiceRole || error_continue "Failed to delete EMRContainersServiceRole"
        log_success "EMRContainersServiceRole removed"
    else
        log_warning "EMRContainersServiceRole not found"
    fi
}

# Wait for resource deletion
wait_for_deletion() {
    log_info "Waiting for resource deletion to complete..."
    
    # Wait for Kinesis streams
    if [ -n "$STREAM_NAME_TRADING" ]; then
        log_info "Waiting for Kinesis stream deletion: $STREAM_NAME_TRADING"
        aws kinesis wait stream-not-exists --stream-name ${STREAM_NAME_TRADING} || log_warning "Timeout waiting for stream deletion"
    fi
    
    if [ -n "$STREAM_NAME_MARKET" ]; then
        log_info "Waiting for Kinesis stream deletion: $STREAM_NAME_MARKET"
        aws kinesis wait stream-not-exists --stream-name ${STREAM_NAME_MARKET} || log_warning "Timeout waiting for stream deletion"
    fi
    
    log_success "Resource deletion completed"
}

# Remove EKS cluster
remove_eks_cluster() {
    log_info "Removing EKS cluster (this takes 10-15 minutes)..."
    
    if ! command_exists eksctl; then
        log_error "eksctl not found. Please delete the EKS cluster manually:"
        log_error "  aws eks delete-cluster --name $CLUSTER_NAME --region $AWS_REGION"
        return 1
    fi
    
    # Check if cluster exists
    if eksctl get cluster --name $CLUSTER_NAME --region $AWS_REGION >/dev/null 2>&1; then
        eksctl delete cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} --wait || error_continue "Failed to delete EKS cluster"
        log_success "EKS cluster removal initiated"
    else
        log_warning "EKS cluster $CLUSTER_NAME not found or already deleted"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        "cluster-config.yaml"
        "emr-trust-policy.json"
        "job-execution-trust-policy.json"
        "lifecycle-policy.json"
        "fraud-detection-job.yaml"
        "risk-analytics-job.yaml"
        "flink-service-monitor.yaml"
        "fluentd-config.yaml"
        "data-generator.yaml"
        ".env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_info "Removed: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local cleanup_issues=()
    
    # Check EKS cluster
    if eksctl get cluster --name $CLUSTER_NAME --region $AWS_REGION >/dev/null 2>&1; then
        cleanup_issues+=("EKS cluster $CLUSTER_NAME still exists")
    fi
    
    # Check S3 bucket
    if [ -n "$BUCKET_NAME" ] && aws s3 ls s3://${BUCKET_NAME} >/dev/null 2>&1; then
        cleanup_issues+=("S3 bucket $BUCKET_NAME still exists")
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name EMRFlinkJobExecutionRole >/dev/null 2>&1; then
        cleanup_issues+=("IAM role EMRFlinkJobExecutionRole still exists")
    fi
    
    if aws iam get-role --role-name EMRContainersServiceRole >/dev/null 2>&1; then
        cleanup_issues+=("IAM role EMRContainersServiceRole still exists")
    fi
    
    # Report results
    if [ ${#cleanup_issues[@]} -eq 0 ]; then
        log_success "Cleanup verification passed - all resources removed"
    else
        log_warning "Cleanup verification found remaining resources:"
        for issue in "${cleanup_issues[@]}"; do
            log_warning "  - $issue"
        done
        log_info "Some resources may take additional time to be fully deleted"
    fi
}

# Display cleanup summary
display_summary() {
    log_success "Cleanup process completed!"
    echo
    log_info "Summary:"
    log_info "  - Flink applications removed"
    log_info "  - Monitoring components removed"
    log_info "  - EMR virtual cluster removed"
    log_info "  - AWS resources (S3, Kinesis, CloudWatch) removed"
    log_info "  - IAM roles removed"
    log_info "  - EKS cluster removal initiated"
    log_info "  - Local files cleaned up"
    echo
    log_warning "Note: Some resources (especially EKS cluster) may take up to 15 minutes to be fully deleted"
    log_info "Monitor the AWS console to confirm complete deletion"
}

# Main cleanup function
main() {
    log_info "Starting cleanup of EMR on EKS with Flink resources..."
    echo
    
    load_environment
    confirm_destruction
    
    log_info "Beginning resource cleanup..."
    remove_flink_applications
    remove_monitoring
    remove_emr_virtual_cluster
    remove_aws_resources
    wait_for_deletion
    remove_iam_roles
    remove_eks_cluster
    cleanup_local_files
    
    verify_cleanup
    display_summary
    
    log_success "Cleanup script completed!"
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force    Skip confirmation prompts"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Trap errors but continue cleanup
trap 'error_continue "An error occurred during cleanup, but continuing..."' ERR

# Run main function
main "$@"