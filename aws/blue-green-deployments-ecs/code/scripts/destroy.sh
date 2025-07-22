#!/bin/bash

# Cleanup script for Blue-Green Deployments with ECS
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if environment file exists
check_environment() {
    if [[ ! -f ".env" ]]; then
        error "Environment file .env not found. This script requires environment variables from the deployment."
        error "Please ensure you're running this script from the same directory where you ran deploy.sh"
        exit 1
    fi
    
    # Load environment variables
    source .env
    
    success "Environment variables loaded"
}

# Function to confirm cleanup
confirm_cleanup() {
    warning "This will permanently delete all resources created by the blue-green deployment."
    warning "The following resources will be deleted:"
    echo "  - ECS Cluster: $CLUSTER_NAME"
    echo "  - ECS Service: $SERVICE_NAME"
    echo "  - ALB: $ALB_NAME"
    echo "  - ECR Repository: $ECR_REPO_NAME"
    echo "  - CodeDeploy Application: $CODEDEPLOY_APP_NAME"
    echo "  - VPC and networking resources"
    echo "  - S3 Bucket: $DEPLOYMENT_BUCKET"
    echo "  - IAM Roles and CloudWatch Log Groups"
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Cleanup confirmed"
}

# Function to handle errors gracefully
handle_error() {
    local resource_type=$1
    local resource_name=$2
    local error_message=$3
    
    warning "Failed to delete $resource_type: $resource_name"
    warning "Error: $error_message"
    warning "This resource may have already been deleted or may not exist"
}

# Function to delete CodeDeploy resources
delete_codedeploy_resources() {
    log "Deleting CodeDeploy resources..."
    
    # Delete deployment group
    if aws deploy delete-deployment-group \
        --application-name $CODEDEPLOY_APP_NAME \
        --deployment-group-name "bluegreen-dg-${RANDOM_SUFFIX}" \
        --region $AWS_REGION 2>/dev/null; then
        success "Deleted CodeDeploy deployment group"
    else
        handle_error "CodeDeploy deployment group" "bluegreen-dg-${RANDOM_SUFFIX}" "May not exist or already deleted"
    fi
    
    # Delete CodeDeploy application
    if aws deploy delete-application \
        --application-name $CODEDEPLOY_APP_NAME \
        --region $AWS_REGION 2>/dev/null; then
        success "Deleted CodeDeploy application"
    else
        handle_error "CodeDeploy application" "$CODEDEPLOY_APP_NAME" "May not exist or already deleted"
    fi
}

# Function to delete ECS resources
delete_ecs_resources() {
    log "Deleting ECS resources..."
    
    # Delete ECS service
    if aws ecs delete-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --force \
        --region $AWS_REGION 2>/dev/null; then
        log "ECS service deletion initiated"
        
        # Wait for service deletion with timeout
        log "Waiting for ECS service to be deleted..."
        local timeout=300  # 5 minutes
        local elapsed=0
        
        while [[ $elapsed -lt $timeout ]]; do
            if aws ecs describe-services \
                --cluster $CLUSTER_NAME \
                --services $SERVICE_NAME \
                --region $AWS_REGION \
                --query 'services[0].status' --output text 2>/dev/null | grep -q "INACTIVE"; then
                success "ECS service deleted successfully"
                break
            fi
            
            sleep 10
            elapsed=$((elapsed + 10))
        done
        
        if [[ $elapsed -ge $timeout ]]; then
            warning "ECS service deletion timed out, but continuing with cleanup"
        fi
    else
        handle_error "ECS service" "$SERVICE_NAME" "May not exist or already deleted"
    fi
    
    # Delete ECS cluster
    if aws ecs delete-cluster \
        --cluster $CLUSTER_NAME \
        --region $AWS_REGION 2>/dev/null; then
        success "Deleted ECS cluster"
    else
        handle_error "ECS cluster" "$CLUSTER_NAME" "May not exist or already deleted"
    fi
}

# Function to delete Load Balancer resources
delete_load_balancer_resources() {
    log "Deleting Load Balancer resources..."
    
    # Delete listener
    if [[ -n "$LISTENER_ARN" ]]; then
        if aws elbv2 delete-listener \
            --listener-arn $LISTENER_ARN \
            --region $AWS_REGION 2>/dev/null; then
            success "Deleted ALB listener"
        else
            handle_error "ALB listener" "$LISTENER_ARN" "May not exist or already deleted"
        fi
    fi
    
    # Delete target groups
    if [[ -n "$BLUE_TG_ARN" ]]; then
        if aws elbv2 delete-target-group \
            --target-group-arn $BLUE_TG_ARN \
            --region $AWS_REGION 2>/dev/null; then
            success "Deleted blue target group"
        else
            handle_error "Blue target group" "$BLUE_TG_ARN" "May not exist or already deleted"
        fi
    fi
    
    if [[ -n "$GREEN_TG_ARN" ]]; then
        if aws elbv2 delete-target-group \
            --target-group-arn $GREEN_TG_ARN \
            --region $AWS_REGION 2>/dev/null; then
            success "Deleted green target group"
        else
            handle_error "Green target group" "$GREEN_TG_ARN" "May not exist or already deleted"
        fi
    fi
    
    # Delete load balancer
    if [[ -n "$ALB_ARN" ]]; then
        if aws elbv2 delete-load-balancer \
            --load-balancer-arn $ALB_ARN \
            --region $AWS_REGION 2>/dev/null; then
            success "Deleted Application Load Balancer"
        else
            handle_error "Application Load Balancer" "$ALB_ARN" "May not exist or already deleted"
        fi
    fi
}

# Function to delete ECR repository
delete_ecr_repository() {
    log "Deleting ECR repository..."
    
    if aws ecr delete-repository \
        --repository-name $ECR_REPO_NAME \
        --force \
        --region $AWS_REGION 2>/dev/null; then
        success "Deleted ECR repository"
    else
        handle_error "ECR repository" "$ECR_REPO_NAME" "May not exist or already deleted"
    fi
}

# Function to delete S3 bucket
delete_s3_bucket() {
    log "Deleting S3 bucket..."
    
    if [[ -n "$DEPLOYMENT_BUCKET" ]]; then
        # Empty bucket first
        if aws s3 rm s3://$DEPLOYMENT_BUCKET --recursive 2>/dev/null; then
            log "Emptied S3 bucket contents"
        fi
        
        # Delete bucket
        if aws s3 rb s3://$DEPLOYMENT_BUCKET --force --region $AWS_REGION 2>/dev/null; then
            success "Deleted S3 bucket"
        else
            handle_error "S3 bucket" "$DEPLOYMENT_BUCKET" "May not exist or already deleted"
        fi
    fi
}

# Function to delete CloudWatch log group
delete_cloudwatch_logs() {
    log "Deleting CloudWatch log group..."
    
    if aws logs delete-log-group \
        --log-group-name "/ecs/bluegreen-task-${RANDOM_SUFFIX}" \
        --region $AWS_REGION 2>/dev/null; then
        success "Deleted CloudWatch log group"
    else
        handle_error "CloudWatch log group" "/ecs/bluegreen-task-${RANDOM_SUFFIX}" "May not exist or already deleted"
    fi
}

# Function to delete IAM roles
delete_iam_roles() {
    log "Deleting IAM roles..."
    
    # Delete ECS task execution role
    if aws iam detach-role-policy \
        --role-name "ecsTaskExecutionRole-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null; then
        log "Detached policy from ECS task execution role"
    fi
    
    if aws iam delete-role \
        --role-name "ecsTaskExecutionRole-${RANDOM_SUFFIX}" 2>/dev/null; then
        success "Deleted ECS task execution role"
    else
        handle_error "ECS task execution role" "ecsTaskExecutionRole-${RANDOM_SUFFIX}" "May not exist or already deleted"
    fi
    
    # Delete CodeDeploy service role
    if aws iam detach-role-policy \
        --role-name "CodeDeployServiceRole-${RANDOM_SUFFIX}" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForECS 2>/dev/null; then
        log "Detached policy from CodeDeploy service role"
    fi
    
    if aws iam delete-role \
        --role-name "CodeDeployServiceRole-${RANDOM_SUFFIX}" 2>/dev/null; then
        success "Deleted CodeDeploy service role"
    else
        handle_error "CodeDeploy service role" "CodeDeployServiceRole-${RANDOM_SUFFIX}" "May not exist or already deleted"
    fi
}

# Function to delete VPC and networking resources
delete_vpc_resources() {
    log "Deleting VPC and networking resources..."
    
    # Delete security group
    if [[ -n "$SECURITY_GROUP_ID" ]]; then
        if aws ec2 delete-security-group \
            --group-id $SECURITY_GROUP_ID 2>/dev/null; then
            success "Deleted security group"
        else
            handle_error "Security group" "$SECURITY_GROUP_ID" "May not exist or already deleted"
        fi
    fi
    
    # Detach and delete internet gateway
    if [[ -n "$IGW_ID" && -n "$VPC_ID" ]]; then
        if aws ec2 detach-internet-gateway \
            --vpc-id $VPC_ID \
            --internet-gateway-id $IGW_ID 2>/dev/null; then
            log "Detached internet gateway"
        fi
        
        if aws ec2 delete-internet-gateway \
            --internet-gateway-id $IGW_ID 2>/dev/null; then
            success "Deleted internet gateway"
        else
            handle_error "Internet gateway" "$IGW_ID" "May not exist or already deleted"
        fi
    fi
    
    # Delete route table (custom route table, not main)
    if [[ -n "$ROUTE_TABLE_ID" ]]; then
        if aws ec2 delete-route-table \
            --route-table-id $ROUTE_TABLE_ID 2>/dev/null; then
            success "Deleted route table"
        else
            handle_error "Route table" "$ROUTE_TABLE_ID" "May not exist or already deleted"
        fi
    fi
    
    # Delete subnets
    if [[ -n "$SUBNET_1_ID" ]]; then
        if aws ec2 delete-subnet --subnet-id $SUBNET_1_ID 2>/dev/null; then
            success "Deleted subnet 1"
        else
            handle_error "Subnet 1" "$SUBNET_1_ID" "May not exist or already deleted"
        fi
    fi
    
    if [[ -n "$SUBNET_2_ID" ]]; then
        if aws ec2 delete-subnet --subnet-id $SUBNET_2_ID 2>/dev/null; then
            success "Deleted subnet 2"
        else
            handle_error "Subnet 2" "$SUBNET_2_ID" "May not exist or already deleted"
        fi
    fi
    
    # Delete VPC
    if [[ -n "$VPC_ID" ]]; then
        if aws ec2 delete-vpc --vpc-id $VPC_ID 2>/dev/null; then
            success "Deleted VPC"
        else
            handle_error "VPC" "$VPC_ID" "May not exist or already deleted"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary files created during deployment
    local files_to_remove=(
        "Dockerfile"
        "index.html"
        "task-definition.json"
        "updated-task-definition.json"
        "service-definition.json"
        "appspec.yaml"
        "blue-green-deploy.sh"
        ".env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed $file"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to perform final validation
validate_cleanup() {
    log "Performing final validation..."
    
    # Check if major resources still exist
    local validation_errors=0
    
    # Check ECS cluster
    if aws ecs describe-clusters \
        --clusters $CLUSTER_NAME \
        --region $AWS_REGION \
        --query 'clusters[0].status' --output text 2>/dev/null | grep -q "ACTIVE"; then
        warning "ECS cluster still exists"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check CodeDeploy application
    if aws deploy get-application \
        --application-name $CODEDEPLOY_APP_NAME \
        --region $AWS_REGION 2>/dev/null; then
        warning "CodeDeploy application still exists"
        validation_errors=$((validation_errors + 1))
    fi
    
    # Check ECR repository
    if aws ecr describe-repositories \
        --repository-names $ECR_REPO_NAME \
        --region $AWS_REGION 2>/dev/null; then
        warning "ECR repository still exists"
        validation_errors=$((validation_errors + 1))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        success "Cleanup validation passed - no major resources detected"
    else
        warning "Cleanup validation found $validation_errors resources that may still exist"
        warning "These resources may be in the process of being deleted or may require manual cleanup"
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    log "Cleanup Summary:"
    echo "✅ CodeDeploy resources deleted"
    echo "✅ ECS resources deleted"
    echo "✅ Load Balancer resources deleted"
    echo "✅ ECR repository deleted"
    echo "✅ S3 bucket deleted"
    echo "✅ CloudWatch log group deleted"
    echo "✅ IAM roles deleted"
    echo "✅ VPC and networking resources deleted"
    echo "✅ Local files cleaned up"
    echo
    success "Blue-green deployment cleanup completed!"
    success "All resources have been successfully removed"
}

# Main cleanup function
main() {
    log "Starting blue-green deployment cleanup..."
    
    check_environment
    confirm_cleanup
    
    # Delete resources in reverse order of creation
    delete_codedeploy_resources
    delete_ecs_resources
    delete_load_balancer_resources
    delete_ecr_repository
    delete_s3_bucket
    delete_cloudwatch_logs
    delete_iam_roles
    delete_vpc_resources
    cleanup_local_files
    
    validate_cleanup
    show_cleanup_summary
}

# Trap errors and provide helpful message
trap 'error "Cleanup script encountered an error. Some resources may still exist and require manual cleanup."' ERR

# Execute main function
main "$@"