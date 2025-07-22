#!/bin/bash

# Destroy script for Serverless Containers with AWS Fargate and Application Load Balancer
# This script safely removes all resources created by the deploy.sh script

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

# Check if .env file exists and load environment variables
load_environment() {
    if [ -f .env ]; then
        log "Loading environment variables from .env file..."
        set -a  # Automatically export all variables
        source .env
        set +a  # Stop automatically exporting
        log "Environment variables loaded"
    else
        error "Environment file .env not found. Please run deploy.sh first or provide the resource names manually."
        exit 1
    fi
}

# Show confirmation prompt
confirm_destruction() {
    echo ""
    echo "=== DESTRUCTION CONFIRMATION ==="
    echo "This will permanently delete the following resources:"
    echo "- ECS Cluster: ${CLUSTER_NAME}"
    echo "- ECS Service: ${SERVICE_NAME}"
    echo "- ECR Repository: ${ECR_REPO_NAME}"
    echo "- Application Load Balancer: ${ALB_NAME}"
    echo "- Security Groups"
    echo "- IAM Roles and Policies"
    echo "- CloudWatch Log Groups"
    echo "- Auto Scaling Policies"
    echo ""
    echo "Region: ${AWS_REGION}"
    echo "Account: ${AWS_ACCOUNT_ID}"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'YES' to confirm): " confirmation
    
    if [ "$confirmation" != "YES" ]; then
        info "Destruction cancelled by user."
        exit 0
    fi
    
    log "Destruction confirmed. Proceeding with cleanup..."
}

# Remove auto scaling configuration
remove_auto_scaling() {
    log "Removing auto scaling configuration..."
    
    # Delete scaling policies
    if [ -n "${CPU_SCALING_POLICY_ARN:-}" ]; then
        aws application-autoscaling delete-scaling-policy \
            --service-namespace ecs \
            --resource-id "service/${CLUSTER_NAME}/${SERVICE_NAME}" \
            --scalable-dimension ecs:service:DesiredCount \
            --policy-name "${SERVICE_NAME}-cpu-scaling" 2>/dev/null || warn "CPU scaling policy not found or already deleted"
    fi
    
    if [ -n "${MEMORY_SCALING_POLICY_ARN:-}" ]; then
        aws application-autoscaling delete-scaling-policy \
            --service-namespace ecs \
            --resource-id "service/${CLUSTER_NAME}/${SERVICE_NAME}" \
            --scalable-dimension ecs:service:DesiredCount \
            --policy-name "${SERVICE_NAME}-memory-scaling" 2>/dev/null || warn "Memory scaling policy not found or already deleted"
    fi
    
    # Deregister scalable target
    aws application-autoscaling deregister-scalable-target \
        --service-namespace ecs \
        --resource-id "service/${CLUSTER_NAME}/${SERVICE_NAME}" \
        --scalable-dimension ecs:service:DesiredCount 2>/dev/null || warn "Scalable target not found or already deregistered"
    
    log "Auto scaling configuration removed"
}

# Delete ECS service and cluster
delete_ecs_resources() {
    log "Deleting ECS service and cluster..."
    
    # Update service to zero desired count
    info "Scaling down service to 0 tasks..."
    aws ecs update-service \
        --cluster ${CLUSTER_NAME} \
        --service ${SERVICE_NAME} \
        --desired-count 0 2>/dev/null || warn "Service not found or already deleted"
    
    # Wait for tasks to stop
    info "Waiting for tasks to stop..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local running_count=$(aws ecs describe-services \
            --cluster ${CLUSTER_NAME} \
            --services ${SERVICE_NAME} \
            --query 'services[0].runningCount' --output text 2>/dev/null || echo "0")
        
        if [ "$running_count" == "0" ] || [ "$running_count" == "None" ]; then
            log "All tasks have stopped"
            break
        fi
        
        info "Attempt $attempt/$max_attempts: $running_count tasks still running. Waiting 10 seconds..."
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        warn "Timeout waiting for tasks to stop. Continuing with deletion..."
    fi
    
    # Delete service
    info "Deleting ECS service..."
    aws ecs delete-service \
        --cluster ${CLUSTER_NAME} \
        --service ${SERVICE_NAME} \
        --force 2>/dev/null || warn "Service not found or already deleted"
    
    # Wait for service to be deleted
    info "Waiting for service to be deleted..."
    sleep 30
    
    # Delete cluster
    info "Deleting ECS cluster..."
    aws ecs delete-cluster \
        --cluster ${CLUSTER_NAME} 2>/dev/null || warn "Cluster not found or already deleted"
    
    log "ECS resources deleted"
}

# Delete Application Load Balancer and target group
delete_load_balancer() {
    log "Deleting Application Load Balancer and target group..."
    
    if [ -n "${ALB_ARN:-}" ]; then
        # Delete listeners
        info "Deleting ALB listeners..."
        local listener_arns=$(aws elbv2 describe-listeners \
            --load-balancer-arn ${ALB_ARN} \
            --query 'Listeners[*].ListenerArn' --output text 2>/dev/null || echo "")
        
        if [ -n "$listener_arns" ]; then
            for listener_arn in $listener_arns; do
                aws elbv2 delete-listener --listener-arn $listener_arn 2>/dev/null || warn "Listener $listener_arn not found or already deleted"
            done
        fi
        
        # Delete target group
        if [ -n "${TARGET_GROUP_ARN:-}" ]; then
            info "Deleting target group..."
            aws elbv2 delete-target-group --target-group-arn ${TARGET_GROUP_ARN} 2>/dev/null || warn "Target group not found or already deleted"
        fi
        
        # Delete load balancer
        info "Deleting Application Load Balancer..."
        aws elbv2 delete-load-balancer --load-balancer-arn ${ALB_ARN} 2>/dev/null || warn "Load balancer not found or already deleted"
        
        # Wait for ALB to be deleted
        info "Waiting for ALB to be fully deleted..."
        sleep 60
    else
        warn "ALB ARN not found in environment variables"
    fi
    
    log "Application Load Balancer resources deleted"
}

# Delete task definition
delete_task_definition() {
    log "Deregistering task definition..."
    
    # Get all task definition revisions
    local task_def_arns=$(aws ecs list-task-definitions \
        --family-prefix ${TASK_FAMILY} \
        --query 'taskDefinitionArns' --output text 2>/dev/null || echo "")
    
    if [ -n "$task_def_arns" ]; then
        for task_def_arn in $task_def_arns; do
            info "Deregistering task definition: $task_def_arn"
            aws ecs deregister-task-definition \
                --task-definition $task_def_arn 2>/dev/null || warn "Task definition $task_def_arn not found or already deregistered"
        done
    else
        warn "No task definitions found for family: ${TASK_FAMILY}"
    fi
    
    log "Task definitions deregistered"
}

# Delete CloudWatch log group
delete_log_group() {
    log "Deleting CloudWatch log group..."
    
    aws logs delete-log-group \
        --log-group-name "/ecs/${TASK_FAMILY}" 2>/dev/null || warn "Log group not found or already deleted"
    
    log "CloudWatch log group deleted"
}

# Delete security groups
delete_security_groups() {
    log "Deleting security groups..."
    
    # Delete Fargate security group
    if [ -n "${FARGATE_SG_ID:-}" ]; then
        info "Deleting Fargate security group..."
        aws ec2 delete-security-group --group-id ${FARGATE_SG_ID} 2>/dev/null || warn "Fargate security group not found or already deleted"
    fi
    
    # Delete ALB security group
    if [ -n "${ALB_SG_ID:-}" ]; then
        info "Deleting ALB security group..."
        aws ec2 delete-security-group --group-id ${ALB_SG_ID} 2>/dev/null || warn "ALB security group not found or already deleted"
    fi
    
    log "Security groups deleted"
}

# Delete IAM roles and policies
delete_iam_roles() {
    log "Deleting IAM roles and policies..."
    
    # Delete task execution role
    if [ -n "${EXECUTION_ROLE_NAME:-}" ]; then
        info "Deleting task execution role..."
        
        # Detach managed policy
        aws iam detach-role-policy \
            --role-name ${EXECUTION_ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || warn "Policy already detached or role not found"
        
        # Delete role
        aws iam delete-role --role-name ${EXECUTION_ROLE_NAME} 2>/dev/null || warn "Execution role not found or already deleted"
    fi
    
    # Delete task role
    if [ -n "${TASK_ROLE_NAME:-}" ]; then
        info "Deleting task role..."
        
        # Detach custom policy
        if [ -n "${TASK_POLICY_ARN:-}" ]; then
            aws iam detach-role-policy \
                --role-name ${TASK_ROLE_NAME} \
                --policy-arn ${TASK_POLICY_ARN} 2>/dev/null || warn "Policy already detached or role not found"
        fi
        
        # Delete role
        aws iam delete-role --role-name ${TASK_ROLE_NAME} 2>/dev/null || warn "Task role not found or already deleted"
    fi
    
    # Delete custom policy
    if [ -n "${TASK_POLICY_ARN:-}" ]; then
        info "Deleting custom policy..."
        aws iam delete-policy --policy-arn ${TASK_POLICY_ARN} 2>/dev/null || warn "Custom policy not found or already deleted"
    fi
    
    log "IAM roles and policies deleted"
}

# Delete ECR repository
delete_ecr_repository() {
    log "Deleting ECR repository..."
    
    # Delete repository with all images
    aws ecr delete-repository \
        --repository-name ${ECR_REPO_NAME} \
        --force 2>/dev/null || warn "ECR repository not found or already deleted"
    
    log "ECR repository deleted"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove application directory
    if [ -d "fargate-demo-app" ]; then
        rm -rf fargate-demo-app/
        info "Removed fargate-demo-app directory"
    fi
    
    # Remove temporary files
    rm -f task-execution-role-trust-policy.json
    rm -f task-role-policy.json
    rm -f task-definition.json
    rm -f service-definition.json
    
    # Remove environment file
    if [ -f .env ]; then
        rm -f .env
        info "Removed .env file"
    fi
    
    log "Local files cleaned up"
}

# Verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local errors=0
    
    # Check ECS cluster
    if aws ecs describe-clusters --clusters ${CLUSTER_NAME} --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
        warn "ECS cluster still exists: ${CLUSTER_NAME}"
        ((errors++))
    fi
    
    # Check ECR repository
    if aws ecr describe-repositories --repository-names ${ECR_REPO_NAME} &>/dev/null; then
        warn "ECR repository still exists: ${ECR_REPO_NAME}"
        ((errors++))
    fi
    
    # Check ALB
    if [ -n "${ALB_ARN:-}" ]; then
        if aws elbv2 describe-load-balancers --load-balancer-arns ${ALB_ARN} &>/dev/null; then
            warn "Application Load Balancer still exists: ${ALB_NAME}"
            ((errors++))
        fi
    fi
    
    # Check security groups
    if [ -n "${FARGATE_SG_ID:-}" ]; then
        if aws ec2 describe-security-groups --group-ids ${FARGATE_SG_ID} &>/dev/null; then
            warn "Fargate security group still exists: ${FARGATE_SG_ID}"
            ((errors++))
        fi
    fi
    
    if [ -n "${ALB_SG_ID:-}" ]; then
        if aws ec2 describe-security-groups --group-ids ${ALB_SG_ID} &>/dev/null; then
            warn "ALB security group still exists: ${ALB_SG_ID}"
            ((errors++))
        fi
    fi
    
    # Check IAM roles
    if [ -n "${EXECUTION_ROLE_NAME:-}" ]; then
        if aws iam get-role --role-name ${EXECUTION_ROLE_NAME} &>/dev/null; then
            warn "Task execution role still exists: ${EXECUTION_ROLE_NAME}"
            ((errors++))
        fi
    fi
    
    if [ -n "${TASK_ROLE_NAME:-}" ]; then
        if aws iam get-role --role-name ${TASK_ROLE_NAME} &>/dev/null; then
            warn "Task role still exists: ${TASK_ROLE_NAME}"
            ((errors++))
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        log "All resources have been successfully deleted"
    else
        warn "$errors resources may still exist. Please check the AWS console for manual cleanup."
    fi
}

# Main destruction function
main() {
    log "Starting resource destruction..."
    
    # Load environment variables
    load_environment
    
    # Show confirmation
    confirm_destruction
    
    # Remove resources in reverse order of creation
    remove_auto_scaling
    delete_ecs_resources
    delete_load_balancer
    delete_task_definition
    delete_log_group
    delete_security_groups
    delete_iam_roles
    delete_ecr_repository
    cleanup_local_files
    
    # Verify deletion
    verify_deletion
    
    log "Resource destruction completed!"
    echo ""
    echo "=== Destruction Summary ==="
    echo "All resources have been removed from AWS"
    echo "Local files have been cleaned up"
    echo "The environment is now clean"
    echo ""
    echo "Note: Some resources may take a few minutes to fully disappear from the AWS console"
}

# Handle script interruption
cleanup_on_exit() {
    error "Script interrupted. Some resources may still exist."
    error "Please run this script again to complete the cleanup."
    exit 1
}

# Set up signal handlers
trap cleanup_on_exit INT TERM

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Run main function
check_prerequisites
main "$@"