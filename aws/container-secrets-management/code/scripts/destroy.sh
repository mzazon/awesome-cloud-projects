#!/bin/bash

# Container Secrets Management with AWS Secrets Manager - Cleanup Script
# This script removes all resources created by the deployment script

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
ENV_FILE="${SCRIPT_DIR}/environment.env"

# Function to log messages
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" | tee -a "$ERROR_LOG"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Function to confirm deletion
confirm_deletion() {
    log "WARN" "This will delete ALL resources created by the deployment script."
    log "WARN" "This action cannot be undone."
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "INFO" "Cleanup cancelled by user."
        exit 0
    fi
}

# Function to load environment variables
load_environment() {
    log "INFO" "Loading environment variables..."
    
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
        log "INFO" "Environment variables loaded from: $ENV_FILE"
        log "INFO" "Cluster Name: $CLUSTER_NAME"
        log "INFO" "Secret Name: $SECRET_NAME"
        log "INFO" "Lambda Function: $LAMBDA_FUNCTION_NAME"
    else
        log "ERROR" "Environment file not found: $ENV_FILE"
        log "ERROR" "Unable to proceed without environment variables."
        exit 1
    fi
    
    # Validate required variables
    if [ -z "$CLUSTER_NAME" ] || [ -z "$SECRET_NAME" ] || [ -z "$AWS_REGION" ]; then
        log "ERROR" "Required environment variables are missing."
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed."
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log "ERROR" "kubectl is not installed."
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        log "ERROR" "Helm is not installed."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials are not configured."
        exit 1
    fi
    
    log "INFO" "Prerequisites check completed successfully."
}

# Function to delete EKS resources
delete_eks_resources() {
    log "INFO" "Deleting EKS resources..."
    
    # Delete Kubernetes resources
    if kubectl get deployment demo-app &> /dev/null; then
        kubectl delete deployment demo-app &> /dev/null
        log "INFO" "Deleted demo-app deployment"
    fi
    
    if kubectl get secretproviderclass demo-secrets-provider &> /dev/null; then
        kubectl delete secretproviderclass demo-secrets-provider &> /dev/null
        log "INFO" "Deleted SecretProviderClass"
    fi
    
    if kubectl get serviceaccount secrets-demo-sa &> /dev/null; then
        kubectl delete serviceaccount secrets-demo-sa &> /dev/null
        log "INFO" "Deleted service account"
    fi
    
    if kubectl get secret demo-secrets &> /dev/null; then
        kubectl delete secret demo-secrets &> /dev/null
        log "INFO" "Deleted Kubernetes secret"
    fi
    
    # Uninstall Helm charts
    if helm list -n kube-system | grep -q secrets-provider-aws; then
        helm uninstall secrets-provider-aws -n kube-system &> /dev/null
        log "INFO" "Uninstalled AWS Secrets Provider"
    fi
    
    if helm list -n kube-system | grep -q csi-secrets-store; then
        helm uninstall csi-secrets-store -n kube-system &> /dev/null
        log "INFO" "Uninstalled CSI Secrets Store"
    fi
    
    log "INFO" "EKS resources cleanup completed"
}

# Function to delete EKS cluster
delete_eks_cluster() {
    log "INFO" "Deleting EKS cluster..."
    
    # Check if cluster exists
    if aws eks describe-cluster --name "$CLUSTER_NAME" &> /dev/null; then
        log "INFO" "EKS cluster found. Initiating deletion..."
        
        # Delete EKS cluster
        aws eks delete-cluster --name "$CLUSTER_NAME" &> /dev/null
        
        if [ $? -eq 0 ]; then
            log "INFO" "EKS cluster deletion initiated"
            log "INFO" "Waiting for cluster deletion to complete..."
            
            # Wait for cluster to be deleted (this can take 10-15 minutes)
            while aws eks describe-cluster --name "$CLUSTER_NAME" &> /dev/null; do
                log "INFO" "Cluster still exists. Waiting..."
                sleep 30
            done
            
            log "INFO" "EKS cluster deleted successfully"
        else
            log "ERROR" "Failed to delete EKS cluster"
        fi
    else
        log "INFO" "EKS cluster not found or already deleted"
    fi
    
    # Delete IAM roles
    if aws iam get-role --role-name "${CLUSTER_NAME}-pod-role" &> /dev/null; then
        aws iam delete-role-policy \
            --role-name "${CLUSTER_NAME}-pod-role" \
            --policy-name SecretsManagerAccess &> /dev/null
        
        aws iam delete-role --role-name "${CLUSTER_NAME}-pod-role" &> /dev/null
        log "INFO" "Deleted pod IAM role"
    fi
    
    if aws iam get-role --role-name "${CLUSTER_NAME}-eks-service-role" &> /dev/null; then
        aws iam detach-role-policy \
            --role-name "${CLUSTER_NAME}-eks-service-role" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy &> /dev/null
        
        aws iam delete-role --role-name "${CLUSTER_NAME}-eks-service-role" &> /dev/null
        log "INFO" "Deleted EKS service role"
    fi
}

# Function to delete ECS resources
delete_ecs_resources() {
    log "INFO" "Deleting ECS resources..."
    
    # Check if cluster exists
    if aws ecs describe-clusters --clusters "$CLUSTER_NAME" --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
        # Stop running tasks
        TASK_ARNS=$(aws ecs list-tasks \
            --cluster "$CLUSTER_NAME" \
            --query 'taskArns' --output text 2>/dev/null)
        
        if [ -n "$TASK_ARNS" ] && [ "$TASK_ARNS" != "None" ]; then
            for task_arn in $TASK_ARNS; do
                aws ecs stop-task \
                    --cluster "$CLUSTER_NAME" \
                    --task "$task_arn" &> /dev/null
                log "INFO" "Stopped ECS task: $task_arn"
            done
        fi
        
        # Wait for tasks to stop
        sleep 10
        
        # Delete ECS cluster
        aws ecs delete-cluster --cluster "$CLUSTER_NAME" &> /dev/null
        log "INFO" "Deleted ECS cluster"
    else
        log "INFO" "ECS cluster not found or already deleted"
    fi
    
    # Delete IAM role
    if aws iam get-role --role-name "${CLUSTER_NAME}-ecs-task-role" &> /dev/null; then
        aws iam delete-role-policy \
            --role-name "${CLUSTER_NAME}-ecs-task-role" \
            --policy-name SecretsManagerAccess &> /dev/null
        
        aws iam delete-role --role-name "${CLUSTER_NAME}-ecs-task-role" &> /dev/null
        log "INFO" "Deleted ECS task role"
    fi
    
    # Delete log group
    if aws logs describe-log-groups --log-group-name-prefix "/ecs/${CLUSTER_NAME}" &> /dev/null; then
        aws logs delete-log-group --log-group-name "/ecs/${CLUSTER_NAME}" &> /dev/null
        log "INFO" "Deleted ECS log group"
    fi
}

# Function to delete Lambda function and related resources
delete_lambda_resources() {
    log "INFO" "Deleting Lambda function and related resources..."
    
    # Delete Lambda function
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null
        log "INFO" "Deleted Lambda function: $LAMBDA_FUNCTION_NAME"
    fi
    
    # Delete Lambda role
    if aws iam get-role --role-name "${LAMBDA_FUNCTION_NAME}-role" &> /dev/null; then
        aws iam delete-role-policy \
            --role-name "${LAMBDA_FUNCTION_NAME}-role" \
            --policy-name SecretsManagerRotation &> /dev/null
        
        aws iam detach-role-policy \
            --role-name "${LAMBDA_FUNCTION_NAME}-role" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole &> /dev/null
        
        aws iam delete-role --role-name "${LAMBDA_FUNCTION_NAME}-role" &> /dev/null
        log "INFO" "Deleted Lambda role"
    fi
}

# Function to delete secrets
delete_secrets() {
    log "INFO" "Deleting secrets from AWS Secrets Manager..."
    
    # Delete database secret
    if [ -n "$DB_SECRET_ARN" ]; then
        aws secretsmanager delete-secret \
            --secret-id "$DB_SECRET_ARN" \
            --force-delete-without-recovery &> /dev/null
        log "INFO" "Deleted database secret"
    else
        # Try to delete by name
        if aws secretsmanager describe-secret --secret-id "${SECRET_NAME}-db" &> /dev/null; then
            aws secretsmanager delete-secret \
                --secret-id "${SECRET_NAME}-db" \
                --force-delete-without-recovery &> /dev/null
            log "INFO" "Deleted database secret by name"
        fi
    fi
    
    # Delete API secret
    if [ -n "$API_SECRET_ARN" ]; then
        aws secretsmanager delete-secret \
            --secret-id "$API_SECRET_ARN" \
            --force-delete-without-recovery &> /dev/null
        log "INFO" "Deleted API secret"
    else
        # Try to delete by name
        if aws secretsmanager describe-secret --secret-id "${SECRET_NAME}-api" &> /dev/null; then
            aws secretsmanager delete-secret \
                --secret-id "${SECRET_NAME}-api" \
                --force-delete-without-recovery &> /dev/null
            log "INFO" "Deleted API secret by name"
        fi
    fi
}

# Function to delete KMS key
delete_kms_key() {
    log "INFO" "Scheduling KMS key deletion..."
    
    if [ -n "$KMS_KEY_ID" ]; then
        # Schedule KMS key deletion
        aws kms schedule-key-deletion \
            --key-id "$KMS_KEY_ID" \
            --pending-window-in-days 7 &> /dev/null
        
        if [ $? -eq 0 ]; then
            log "INFO" "KMS key scheduled for deletion in 7 days"
        else
            log "WARN" "Failed to schedule KMS key deletion"
        fi
        
        # Delete alias
        RANDOM_SUFFIX=$(echo "$CLUSTER_NAME" | cut -d'-' -f3-)
        aws kms delete-alias \
            --alias-name "alias/secrets-manager-${RANDOM_SUFFIX}" &> /dev/null
        
        if [ $? -eq 0 ]; then
            log "INFO" "KMS key alias deleted"
        else
            log "WARN" "Failed to delete KMS key alias"
        fi
    else
        log "INFO" "KMS key ID not found in environment variables"
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log "INFO" "Deleting monitoring resources..."
    
    # Delete CloudWatch alarms
    if aws cloudwatch describe-alarms --alarm-names "${SECRET_NAME}-unauthorized-access" &> /dev/null; then
        aws cloudwatch delete-alarms \
            --alarm-names "${SECRET_NAME}-unauthorized-access" &> /dev/null
        log "INFO" "Deleted CloudWatch alarm"
    fi
    
    # Delete log groups
    if aws logs describe-log-groups --log-group-name-prefix "/aws/secretsmanager/${SECRET_NAME}" &> /dev/null; then
        aws logs delete-log-group \
            --log-group-name "/aws/secretsmanager/${SECRET_NAME}" &> /dev/null
        log "INFO" "Deleted Secrets Manager log group"
    fi
    
    # Delete Lambda log group
    if aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/${LAMBDA_FUNCTION_NAME}" &> /dev/null; then
        aws logs delete-log-group \
            --log-group-name "/aws/lambda/${LAMBDA_FUNCTION_NAME}" &> /dev/null
        log "INFO" "Deleted Lambda log group"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    # List of files to remove
    files_to_remove=(
        "ecs-task-trust-policy.json"
        "ecs-secrets-policy.json"
        "ecs-task-definition.json"
        "eks-pod-trust-policy.json"
        "secret-provider-class.yaml"
        "demo-app-deployment.yaml"
        "lambda-rotation.py"
        "lambda-rotation.zip"
        "environment.env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "${SCRIPT_DIR}/${file}" ]; then
            rm -f "${SCRIPT_DIR}/${file}"
            log "INFO" "Removed local file: $file"
        fi
    done
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "INFO" "Cleanup Summary:"
    log "INFO" "================="
    log "INFO" "✅ EKS resources deleted"
    log "INFO" "✅ EKS cluster deleted"
    log "INFO" "✅ ECS resources deleted"
    log "INFO" "✅ Lambda function deleted"
    log "INFO" "✅ Secrets deleted"
    log "INFO" "✅ KMS key scheduled for deletion"
    log "INFO" "✅ Monitoring resources deleted"
    log "INFO" "✅ Local files cleaned up"
    log "INFO" ""
    log "INFO" "Note: KMS key will be permanently deleted in 7 days"
    log "INFO" "Cleanup logs saved to: $LOG_FILE"
}

# Function to handle cleanup errors
handle_cleanup_errors() {
    log "ERROR" "Some resources may not have been deleted completely."
    log "ERROR" "Please check the error log: $ERROR_LOG"
    log "ERROR" "You may need to manually delete remaining resources."
    log "ERROR" ""
    log "ERROR" "Common manual cleanup steps:"
    log "ERROR" "1. Check EKS cluster status in AWS Console"
    log "ERROR" "2. Check ECS cluster status in AWS Console"
    log "ERROR" "3. Check Secrets Manager for remaining secrets"
    log "ERROR" "4. Check Lambda functions for remaining functions"
    log "ERROR" "5. Check IAM roles for remaining roles"
    log "ERROR" "6. Check CloudWatch for remaining alarms and log groups"
}

# Main execution
main() {
    log "INFO" "Starting Container Secrets Management cleanup..."
    log "INFO" "================================================="
    
    # Initialize log files
    echo "Container Secrets Management Cleanup Log - $(date)" > "$LOG_FILE"
    echo "Container Secrets Management Cleanup Errors - $(date)" > "$ERROR_LOG"
    
    # Set trap for error handling
    trap 'handle_cleanup_errors' ERR
    
    # Execute cleanup steps
    check_prerequisites
    confirm_deletion
    load_environment
    
    # Continue with cleanup even if some steps fail
    set +e
    
    delete_eks_resources
    delete_eks_cluster
    delete_ecs_resources
    delete_lambda_resources
    delete_secrets
    delete_kms_key
    delete_monitoring_resources
    cleanup_local_files
    
    # Re-enable exit on error
    set -e
    
    display_cleanup_summary
    
    log "INFO" "✅ Container Secrets Management cleanup completed!"
    log "INFO" "Cleanup logs saved to: $LOG_FILE"
    
    if [ -s "$ERROR_LOG" ]; then
        log "WARN" "Some errors occurred during cleanup. Check: $ERROR_LOG"
    fi
}

# Run main function
main "$@"