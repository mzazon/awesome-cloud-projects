#!/bin/bash

# Destroy script for Serverless Container Applications with AWS Fargate
# This script safely removes all AWS resources created by the deploy script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [ ! -f "deployment-info.json" ]; then
        log_error "deployment-info.json not found!"
        log_error "This file is created by deploy.sh and contains resource identifiers for cleanup."
        log_error "Without this file, you'll need to manually identify and delete resources."
        
        read -p "Do you want to continue with manual cleanup? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled."
            exit 1
        fi
        
        log_warning "Proceeding with manual cleanup mode..."
        manual_cleanup
        return 0
    fi
    
    # Parse deployment info
    export CLUSTER_NAME=$(jq -r '.clusterName' deployment-info.json)
    export SERVICE_NAME=$(jq -r '.serviceName' deployment-info.json)
    export TASK_FAMILY=$(jq -r '.taskFamily' deployment-info.json)
    export REPOSITORY_NAME=$(jq -r '.repositoryName' deployment-info.json)
    export REPOSITORY_URI=$(jq -r '.repositoryUri' deployment-info.json)
    export EXECUTION_ROLE_NAME=$(jq -r '.executionRoleName' deployment-info.json)
    export EXECUTION_ROLE_ARN=$(jq -r '.executionRoleArn' deployment-info.json)
    export FARGATE_SG_ID=$(jq -r '.securityGroupId' deployment-info.json)
    export DEFAULT_VPC_ID=$(jq -r '.vpcId' deployment-info.json)
    export SUBNET_IDS=$(jq -r '.subnetIds' deployment-info.json)
    export AWS_REGION=$(jq -r '.awsRegion' deployment-info.json)
    export AWS_ACCOUNT_ID=$(jq -r '.awsAccountId' deployment-info.json)
    
    log_success "Deployment information loaded"
    log_info "Will clean up resources from deployment: $(jq -r '.deploymentTimestamp' deployment-info.json)"
}

# Manual cleanup mode for when deployment-info.json is missing
manual_cleanup() {
    log_warning "Manual cleanup mode - you'll need to provide resource identifiers"
    
    read -p "Enter ECS cluster name (or press Enter to skip): " CLUSTER_NAME
    read -p "Enter ECR repository name (or press Enter to skip): " REPOSITORY_NAME
    read -p "Enter IAM execution role name (or press Enter to skip): " EXECUTION_ROLE_NAME
    read -p "Enter security group ID (or press Enter to skip): " FARGATE_SG_ID
    
    export SERVICE_NAME="demo-service"
    export TASK_FAMILY="demo-task"
    
    log_info "Manual cleanup configured"
}

# Confirmation prompt
confirm_destruction() {
    log_warning "========================================================================"
    log_warning "WARNING: This will permanently delete the following AWS resources:"
    log_warning "- ECS Cluster: ${CLUSTER_NAME:-'Not specified'}"
    log_warning "- ECS Service: ${SERVICE_NAME:-'Not specified'}"
    log_warning "- ECR Repository: ${REPOSITORY_NAME:-'Not specified'} (including all images)"
    log_warning "- IAM Role: ${EXECUTION_ROLE_NAME:-'Not specified'}"
    log_warning "- Security Group: ${FARGATE_SG_ID:-'Not specified'}"
    log_warning "- CloudWatch Log Group: /ecs/${TASK_FAMILY:-'demo-task'}"
    log_warning "- Auto-scaling policies and targets"
    log_warning "========================================================================"
    
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled."
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if jq is installed (only if deployment-info.json exists)
    if [ -f "deployment-info.json" ] && ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON parsing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Remove auto-scaling configuration
remove_autoscaling() {
    if [ -z "$CLUSTER_NAME" ] || [ -z "$SERVICE_NAME" ]; then
        log_warning "Skipping auto-scaling cleanup - cluster or service name not provided"
        return 0
    fi
    
    log_info "Removing auto-scaling configuration..."
    
    # Check if scalable target exists
    SCALABLE_TARGET=$(aws application-autoscaling describe-scalable-targets \
        --service-namespace ecs \
        --resource-ids "service/$CLUSTER_NAME/$SERVICE_NAME" \
        --query 'ScalableTargets[0].ResourceId' --output text 2>/dev/null || echo "None")
    
    if [ "$SCALABLE_TARGET" != "None" ] && [ "$SCALABLE_TARGET" != "" ]; then
        log_info "Deregistering scalable target..."
        aws application-autoscaling deregister-scalable-target \
            --service-namespace ecs \
            --resource-id "service/$CLUSTER_NAME/$SERVICE_NAME" \
            --scalable-dimension ecs:service:DesiredCount 2>/dev/null || log_warning "Failed to deregister scalable target"
        
        log_success "Auto-scaling configuration removed"
    else
        log_info "No auto-scaling configuration found"
    fi
}

# Delete ECS service
delete_ecs_service() {
    if [ -z "$CLUSTER_NAME" ] || [ -z "$SERVICE_NAME" ]; then
        log_warning "Skipping ECS service cleanup - cluster or service name not provided"
        return 0
    fi
    
    log_info "Deleting ECS service..."
    
    # Check if service exists
    SERVICE_STATUS=$(aws ecs describe-services \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --query 'services[0].status' --output text 2>/dev/null || echo "None")
    
    if [ "$SERVICE_STATUS" = "None" ] || [ "$SERVICE_STATUS" = "" ]; then
        log_info "ECS service not found or already deleted"
        return 0
    fi
    
    # Scale down the service to 0 tasks
    log_info "Scaling down service to 0 tasks..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --desired-count 0 2>/dev/null || log_warning "Failed to scale down service"
    
    # Wait for tasks to stop
    log_info "Waiting for tasks to stop (this may take a few minutes)..."
    aws ecs wait services-stable \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" 2>/dev/null || log_warning "Service did not stabilize properly"
    
    # Delete the service
    log_info "Deleting ECS service..."
    aws ecs delete-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" 2>/dev/null || log_warning "Failed to delete service"
    
    log_success "ECS service deleted: $SERVICE_NAME"
}

# Delete ECS cluster
delete_ecs_cluster() {
    if [ -z "$CLUSTER_NAME" ]; then
        log_warning "Skipping ECS cluster cleanup - cluster name not provided"
        return 0
    fi
    
    log_info "Deleting ECS cluster..."
    
    # Check if cluster exists
    CLUSTER_STATUS=$(aws ecs describe-clusters \
        --clusters "$CLUSTER_NAME" \
        --query 'clusters[0].status' --output text 2>/dev/null || echo "None")
    
    if [ "$CLUSTER_STATUS" = "None" ] || [ "$CLUSTER_STATUS" = "" ]; then
        log_info "ECS cluster not found or already deleted"
        return 0
    fi
    
    # Delete the cluster
    aws ecs delete-cluster --cluster "$CLUSTER_NAME" 2>/dev/null || log_warning "Failed to delete cluster"
    
    log_success "ECS cluster deleted: $CLUSTER_NAME"
}

# Delete ECR repository and images
delete_ecr_repository() {
    if [ -z "$REPOSITORY_NAME" ]; then
        log_warning "Skipping ECR repository cleanup - repository name not provided"
        return 0
    fi
    
    log_info "Deleting ECR repository and all images..."
    
    # Check if repository exists
    REPO_EXISTS=$(aws ecr describe-repositories \
        --repository-names "$REPOSITORY_NAME" \
        --query 'repositories[0].repositoryName' --output text 2>/dev/null || echo "None")
    
    if [ "$REPO_EXISTS" = "None" ] || [ "$REPO_EXISTS" = "" ]; then
        log_info "ECR repository not found or already deleted"
        return 0
    fi
    
    # List and delete all images in the repository
    log_info "Deleting all images in repository..."
    IMAGE_TAGS=$(aws ecr list-images \
        --repository-name "$REPOSITORY_NAME" \
        --query 'imageIds[*].imageTag' --output text 2>/dev/null || echo "")
    
    if [ -n "$IMAGE_TAGS" ] && [ "$IMAGE_TAGS" != "None" ]; then
        for TAG in $IMAGE_TAGS; do
            if [ "$TAG" != "None" ] && [ "$TAG" != "" ]; then
                aws ecr batch-delete-image \
                    --repository-name "$REPOSITORY_NAME" \
                    --image-ids imageTag="$TAG" 2>/dev/null || log_warning "Failed to delete image tag: $TAG"
            fi
        done
    fi
    
    # Delete images without tags
    UNTAGGED_IMAGES=$(aws ecr list-images \
        --repository-name "$REPOSITORY_NAME" \
        --filter tagStatus=UNTAGGED \
        --query 'imageIds[*].imageDigest' --output text 2>/dev/null || echo "")
    
    if [ -n "$UNTAGGED_IMAGES" ] && [ "$UNTAGGED_IMAGES" != "None" ]; then
        for DIGEST in $UNTAGGED_IMAGES; do
            if [ "$DIGEST" != "None" ] && [ "$DIGEST" != "" ]; then
                aws ecr batch-delete-image \
                    --repository-name "$REPOSITORY_NAME" \
                    --image-ids imageDigest="$DIGEST" 2>/dev/null || log_warning "Failed to delete untagged image: $DIGEST"
            fi
        done
    fi
    
    # Delete the repository
    aws ecr delete-repository \
        --repository-name "$REPOSITORY_NAME" 2>/dev/null || log_warning "Failed to delete repository"
    
    log_success "ECR repository deleted: $REPOSITORY_NAME"
}

# Delete IAM roles
delete_iam_roles() {
    if [ -z "$EXECUTION_ROLE_NAME" ]; then
        log_warning "Skipping IAM role cleanup - role name not provided"
        return 0
    fi
    
    log_info "Deleting IAM roles..."
    
    # Check if role exists
    ROLE_EXISTS=$(aws iam get-role \
        --role-name "$EXECUTION_ROLE_NAME" \
        --query 'Role.RoleName' --output text 2>/dev/null || echo "None")
    
    if [ "$ROLE_EXISTS" = "None" ] || [ "$ROLE_EXISTS" = "" ]; then
        log_info "IAM execution role not found or already deleted"
        return 0
    fi
    
    # Detach policy from execution role
    log_info "Detaching policies from execution role..."
    aws iam detach-role-policy \
        --role-name "$EXECUTION_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || log_warning "Failed to detach policy"
    
    # Delete execution role
    aws iam delete-role --role-name "$EXECUTION_ROLE_NAME" 2>/dev/null || log_warning "Failed to delete execution role"
    
    log_success "IAM execution role deleted: $EXECUTION_ROLE_NAME"
}

# Delete security groups
delete_security_groups() {
    if [ -z "$FARGATE_SG_ID" ]; then
        log_warning "Skipping security group cleanup - security group ID not provided"
        return 0
    fi
    
    log_info "Deleting security groups..."
    
    # Check if security group exists
    SG_EXISTS=$(aws ec2 describe-security-groups \
        --group-ids "$FARGATE_SG_ID" \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")
    
    if [ "$SG_EXISTS" = "None" ] || [ "$SG_EXISTS" = "" ]; then
        log_info "Security group not found or already deleted"
        return 0
    fi
    
    # Delete security group (retry logic in case of dependencies)
    MAX_RETRIES=5
    RETRY_COUNT=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if aws ec2 delete-security-group --group-id "$FARGATE_SG_ID" 2>/dev/null; then
            log_success "Security group deleted: $FARGATE_SG_ID"
            return 0
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            log_warning "Failed to delete security group, retrying in 10 seconds... (attempt $RETRY_COUNT/$MAX_RETRIES)"
            sleep 10
        fi
    done
    
    log_warning "Failed to delete security group after $MAX_RETRIES attempts: $FARGATE_SG_ID"
    log_warning "The security group may have dependencies that need to be resolved manually"
}

# Delete CloudWatch log groups
delete_cloudwatch_logs() {
    if [ -z "$TASK_FAMILY" ]; then
        export TASK_FAMILY="demo-task"
        log_warning "Task family not specified, using default: demo-task"
    fi
    
    log_info "Deleting CloudWatch log groups..."
    
    LOG_GROUP_NAME="/ecs/$TASK_FAMILY"
    
    # Check if log group exists
    LOG_EXISTS=$(aws logs describe-log-groups \
        --log-group-name-prefix "$LOG_GROUP_NAME" \
        --query 'logGroups[0].logGroupName' --output text 2>/dev/null || echo "None")
    
    if [ "$LOG_EXISTS" = "None" ] || [ "$LOG_EXISTS" = "" ]; then
        log_info "CloudWatch log group not found or already deleted"
        return 0
    fi
    
    # Delete CloudWatch log group
    aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME" 2>/dev/null || log_warning "Failed to delete log group"
    
    log_success "CloudWatch log group deleted: $LOG_GROUP_NAME"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # List of files to clean up
    LOCAL_FILES=(
        "fargate-demo-app"
        "task-definition.json"
        "task-execution-assume-role-policy.json"
        "deployment-info.json"
    )
    
    for FILE in "${LOCAL_FILES[@]}"; do
        if [ -e "$FILE" ]; then
            if [ -d "$FILE" ]; then
                rm -rf "$FILE"
                log_info "Removed directory: $FILE"
            else
                rm -f "$FILE"
                log_info "Removed file: $FILE"
            fi
        fi
    done
    
    log_success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    ISSUES_FOUND=0
    
    # Check if cluster still exists
    if [ -n "$CLUSTER_NAME" ]; then
        CLUSTER_STATUS=$(aws ecs describe-clusters \
            --clusters "$CLUSTER_NAME" \
            --query 'clusters[0].status' --output text 2>/dev/null || echo "None")
        
        if [ "$CLUSTER_STATUS" != "None" ] && [ "$CLUSTER_STATUS" != "" ]; then
            log_warning "ECS cluster still exists: $CLUSTER_NAME"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    fi
    
    # Check if repository still exists
    if [ -n "$REPOSITORY_NAME" ]; then
        REPO_EXISTS=$(aws ecr describe-repositories \
            --repository-names "$REPOSITORY_NAME" \
            --query 'repositories[0].repositoryName' --output text 2>/dev/null || echo "None")
        
        if [ "$REPO_EXISTS" != "None" ] && [ "$REPO_EXISTS" != "" ]; then
            log_warning "ECR repository still exists: $REPOSITORY_NAME"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    fi
    
    # Check if IAM role still exists
    if [ -n "$EXECUTION_ROLE_NAME" ]; then
        ROLE_EXISTS=$(aws iam get-role \
            --role-name "$EXECUTION_ROLE_NAME" \
            --query 'Role.RoleName' --output text 2>/dev/null || echo "None")
        
        if [ "$ROLE_EXISTS" != "None" ] && [ "$ROLE_EXISTS" != "" ]; then
            log_warning "IAM execution role still exists: $EXECUTION_ROLE_NAME"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    fi
    
    # Check if security group still exists
    if [ -n "$FARGATE_SG_ID" ]; then
        SG_EXISTS=$(aws ec2 describe-security-groups \
            --group-ids "$FARGATE_SG_ID" \
            --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")
        
        if [ "$SG_EXISTS" != "None" ] && [ "$SG_EXISTS" != "" ]; then
            log_warning "Security group still exists: $FARGATE_SG_ID"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    fi
    
    if [ $ISSUES_FOUND -eq 0 ]; then
        log_success "Cleanup verification completed successfully - all resources removed"
    else
        log_warning "Cleanup verification found $ISSUES_FOUND remaining resources"
        log_warning "You may need to manually remove these resources to avoid ongoing charges"
    fi
    
    return $ISSUES_FOUND
}

# Main destroy function
main() {
    log_info "Starting cleanup of Serverless Container Applications with AWS Fargate"
    log_info "========================================================================"
    
    check_prerequisites
    load_deployment_info
    confirm_destruction
    
    # Remove resources in reverse order of creation
    remove_autoscaling
    delete_ecs_service
    delete_ecs_cluster
    delete_ecr_repository
    delete_iam_roles
    delete_security_groups
    delete_cloudwatch_logs
    cleanup_local_files
    verify_cleanup
    
    log_success "========================================================================"
    if [ $? -eq 0 ]; then
        log_success "Cleanup completed successfully!"
        log_info "All AWS resources have been removed."
    else
        log_warning "Cleanup completed with some issues."
        log_warning "Please check the AWS console to verify all resources are removed."
    fi
    
    log_info "Thank you for using the Fargate deployment recipe!"
}

# Run main function
main "$@"