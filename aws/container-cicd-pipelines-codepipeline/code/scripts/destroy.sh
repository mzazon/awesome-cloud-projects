#!/bin/bash

# AWS CI/CD Pipeline Cleanup Script
# This script removes all resources created by the CI/CD pipeline deployment
# WARNING: This will delete ALL resources - use with caution!

set -e  # Exit on any error

# Color codes for output
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

# Check if we're running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

if [ "$DRY_RUN" = "true" ]; then
    warn "Running in DRY-RUN mode. No actual resources will be deleted."
fi

# Function to execute command with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local ignore_error="${3:-false}"
    
    if [ "$DRY_RUN" = "true" ]; then
        info "DRY-RUN: Would execute: $cmd"
        if [ -n "$description" ]; then
            info "DRY-RUN: $description"
        fi
    else
        log "Executing: $description"
        if [ "$ignore_error" = "true" ]; then
            eval "$cmd" || warn "Command failed but continuing: $cmd"
        else
            eval "$cmd"
        fi
    fi
}

# Function to get user confirmation
confirm() {
    local message="$1"
    if [ "$FORCE" = "true" ]; then
        return 0
    fi
    
    echo -e "${YELLOW}$message${NC}"
    read -p "Are you sure? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_id="$2"
    local check_cmd="$3"
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    if [ "$DRY_RUN" = "true" ]; then
        info "DRY-RUN: Would wait for $resource_type deletion: $resource_id"
        return 0
    fi
    
    log "Waiting for $resource_type deletion: $resource_id"
    while [ $wait_time -lt $max_wait ]; do
        if ! eval "$check_cmd" &>/dev/null; then
            log "$resource_type deleted successfully"
            return 0
        fi
        sleep 10
        wait_time=$((wait_time + 10))
        info "Waiting... ($wait_time/$max_wait seconds)"
    done
    warn "$resource_type may still exist after timeout"
}

# Banner
echo "=========================================="
echo "    AWS CI/CD Pipeline Cleanup"
echo "=========================================="
warn "This script will DELETE ALL CI/CD pipeline resources!"
warn "This action is IRREVERSIBLE!"

# Check for force flag
FORCE=${FORCE:-false}
if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
    FORCE=true
    shift
fi

# Get confirmation
if [ "$FORCE" != "true" ] && [ "$DRY_RUN" != "true" ]; then
    confirm "⚠️  DANGER: This will permanently delete all CI/CD pipeline resources!"
fi

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
fi

# Check if AWS credentials are configured
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure' first."
fi

log "Prerequisites check passed ✓"

# Try to load deployment info if available
if [ -f "/tmp/deployment-info.json" ]; then
    log "Loading deployment information from /tmp/deployment-info.json"
    PROJECT_NAME=$(jq -r '.project_name' /tmp/deployment-info.json)
    AWS_REGION=$(jq -r '.aws_region' /tmp/deployment-info.json)
    AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' /tmp/deployment-info.json)
    DEV_CLUSTER_NAME=$(jq -r '.dev_cluster_name' /tmp/deployment-info.json)
    PROD_CLUSTER_NAME=$(jq -r '.prod_cluster_name' /tmp/deployment-info.json)
    SERVICE_NAME=$(jq -r '.service_name' /tmp/deployment-info.json)
    REPOSITORY_NAME=$(jq -r '.repository_name' /tmp/deployment-info.json)
    PIPELINE_NAME=$(jq -r '.pipeline_name' /tmp/deployment-info.json)
    APPLICATION_NAME=$(jq -r '.application_name' /tmp/deployment-info.json)
    BUILD_PROJECT_NAME=$(jq -r '.build_project_name' /tmp/deployment-info.json)
    SNS_TOPIC_ARN=$(jq -r '.sns_topic_arn' /tmp/deployment-info.json)
    VPC_ID=$(jq -r '.vpc_id' /tmp/deployment-info.json)
    SUBNET_1=$(jq -r '.subnet_1' /tmp/deployment-info.json)
    SUBNET_2=$(jq -r '.subnet_2' /tmp/deployment-info.json)
    SUBNET_3=$(jq -r '.subnet_3' /tmp/deployment-info.json)
    ALB_SG_ID=$(jq -r '.alb_sg_id' /tmp/deployment-info.json)
    ECS_SG_ID=$(jq -r '.ecs_sg_id' /tmp/deployment-info.json)
    DEV_ALB_ARN=$(jq -r '.dev_alb_arn' /tmp/deployment-info.json)
    PROD_ALB_ARN=$(jq -r '.prod_alb_arn' /tmp/deployment-info.json)
    DEV_TG=$(jq -r '.dev_tg' /tmp/deployment-info.json)
    PROD_TG_BLUE=$(jq -r '.prod_tg_blue' /tmp/deployment-info.json)
    PROD_TG_GREEN=$(jq -r '.prod_tg_green' /tmp/deployment-info.json)
    DEV_LISTENER_ARN=$(jq -r '.dev_listener_arn' /tmp/deployment-info.json)
    PROD_LISTENER_ARN=$(jq -r '.prod_listener_arn' /tmp/deployment-info.json)
    IGW_ID=$(jq -r '.igw_id' /tmp/deployment-info.json)
    RT_ID=$(jq -r '.rt_id' /tmp/deployment-info.json)
    
    log "Deployment information loaded successfully"
else
    warn "Deployment information file not found. Using environment variables or prompting for input."
    
    # Get environment variables or prompt for input
    AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not set. Please set AWS_REGION environment variable."
    fi
    
    AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
    
    # Prompt for project name if not set
    if [ -z "$PROJECT_NAME" ]; then
        read -p "Enter project name (e.g., advanced-cicd-12345678): " PROJECT_NAME
        if [ -z "$PROJECT_NAME" ]; then
            error "Project name is required"
        fi
    fi
    
    # Derive other names from project name
    DEV_CLUSTER_NAME="${PROJECT_NAME}-dev-cluster"
    PROD_CLUSTER_NAME="${PROJECT_NAME}-prod-cluster"
    SERVICE_NAME="${PROJECT_NAME}-service"
    REPOSITORY_NAME="${PROJECT_NAME}-repo"
    PIPELINE_NAME="${PROJECT_NAME}-pipeline"
    APPLICATION_NAME="${PROJECT_NAME}-app"
    BUILD_PROJECT_NAME="${PROJECT_NAME}-build"
fi

log "Using configuration:"
info "  PROJECT_NAME: $PROJECT_NAME"
info "  AWS_REGION: $AWS_REGION"
info "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"

# Step 1: Delete CodePipeline and CodeBuild Resources
log "Step 1: Deleting CodePipeline and CodeBuild resources..."

execute_cmd "aws codepipeline delete-pipeline \
    --name ${PIPELINE_NAME} \
    --region ${AWS_REGION}" \
    "Delete CodePipeline" \
    true

execute_cmd "aws codebuild delete-project \
    --name ${BUILD_PROJECT_NAME} \
    --region ${AWS_REGION}" \
    "Delete CodeBuild project" \
    true

# Step 2: Delete CodeDeploy Resources
log "Step 2: Deleting CodeDeploy resources..."

execute_cmd "aws deploy delete-deployment-group \
    --application-name ${APPLICATION_NAME} \
    --deployment-group-name ${PROJECT_NAME}-prod-deployment-group \
    --region ${AWS_REGION}" \
    "Delete CodeDeploy deployment group" \
    true

execute_cmd "aws deploy delete-application \
    --application-name ${APPLICATION_NAME} \
    --region ${AWS_REGION}" \
    "Delete CodeDeploy application" \
    true

# Step 3: Scale down and delete ECS Services
log "Step 3: Scaling down and deleting ECS services..."

# Scale down development service
execute_cmd "aws ecs update-service \
    --cluster ${DEV_CLUSTER_NAME} \
    --service ${SERVICE_NAME}-dev \
    --desired-count 0 \
    --region ${AWS_REGION}" \
    "Scale down development service" \
    true

# Scale down production service
execute_cmd "aws ecs update-service \
    --cluster ${PROD_CLUSTER_NAME} \
    --service ${SERVICE_NAME}-prod \
    --desired-count 0 \
    --region ${AWS_REGION}" \
    "Scale down production service" \
    true

# Wait for services to scale down
if [ "$DRY_RUN" = "false" ]; then
    log "Waiting for services to scale down..."
    sleep 30
fi

# Delete development service
execute_cmd "aws ecs delete-service \
    --cluster ${DEV_CLUSTER_NAME} \
    --service ${SERVICE_NAME}-dev \
    --region ${AWS_REGION}" \
    "Delete development service" \
    true

# Delete production service
execute_cmd "aws ecs delete-service \
    --cluster ${PROD_CLUSTER_NAME} \
    --service ${SERVICE_NAME}-prod \
    --region ${AWS_REGION}" \
    "Delete production service" \
    true

# Step 4: Delete ECS Clusters
log "Step 4: Deleting ECS clusters..."

execute_cmd "aws ecs delete-cluster \
    --cluster ${DEV_CLUSTER_NAME} \
    --region ${AWS_REGION}" \
    "Delete development cluster" \
    true

execute_cmd "aws ecs delete-cluster \
    --cluster ${PROD_CLUSTER_NAME} \
    --region ${AWS_REGION}" \
    "Delete production cluster" \
    true

# Step 5: Delete Load Balancers and Target Groups
log "Step 5: Deleting load balancers and target groups..."

# Delete listeners if we have the ARNs
if [ -n "$DEV_LISTENER_ARN" ]; then
    execute_cmd "aws elbv2 delete-listener \
        --listener-arn ${DEV_LISTENER_ARN} \
        --region ${AWS_REGION}" \
        "Delete development listener" \
        true
fi

if [ -n "$PROD_LISTENER_ARN" ]; then
    execute_cmd "aws elbv2 delete-listener \
        --listener-arn ${PROD_LISTENER_ARN} \
        --region ${AWS_REGION}" \
        "Delete production listener" \
        true
fi

# Delete load balancers if we have the ARNs
if [ -n "$DEV_ALB_ARN" ]; then
    execute_cmd "aws elbv2 delete-load-balancer \
        --load-balancer-arn ${DEV_ALB_ARN} \
        --region ${AWS_REGION}" \
        "Delete development load balancer" \
        true
fi

if [ -n "$PROD_ALB_ARN" ]; then
    execute_cmd "aws elbv2 delete-load-balancer \
        --load-balancer-arn ${PROD_ALB_ARN} \
        --region ${AWS_REGION}" \
        "Delete production load balancer" \
        true
fi

# Wait for load balancers to be deleted
if [ "$DRY_RUN" = "false" ]; then
    log "Waiting for load balancers to be deleted..."
    sleep 30
fi

# Delete target groups if we have the ARNs
if [ -n "$DEV_TG" ]; then
    execute_cmd "aws elbv2 delete-target-group \
        --target-group-arn ${DEV_TG} \
        --region ${AWS_REGION}" \
        "Delete development target group" \
        true
fi

if [ -n "$PROD_TG_BLUE" ]; then
    execute_cmd "aws elbv2 delete-target-group \
        --target-group-arn ${PROD_TG_BLUE} \
        --region ${AWS_REGION}" \
        "Delete production blue target group" \
        true
fi

if [ -n "$PROD_TG_GREEN" ]; then
    execute_cmd "aws elbv2 delete-target-group \
        --target-group-arn ${PROD_TG_GREEN} \
        --region ${AWS_REGION}" \
        "Delete production green target group" \
        true
fi

# Fallback: Delete load balancers by name if ARNs not available
execute_cmd "aws elbv2 delete-load-balancer \
    --load-balancer-arn \$(aws elbv2 describe-load-balancers \
    --names ${PROJECT_NAME}-dev-alb \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text --region ${AWS_REGION} 2>/dev/null)" \
    "Delete development load balancer (fallback)" \
    true

execute_cmd "aws elbv2 delete-load-balancer \
    --load-balancer-arn \$(aws elbv2 describe-load-balancers \
    --names ${PROJECT_NAME}-prod-alb \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text --region ${AWS_REGION} 2>/dev/null)" \
    "Delete production load balancer (fallback)" \
    true

# Step 6: Delete Security Groups
log "Step 6: Deleting security groups..."

# Delete security groups if we have the IDs
if [ -n "$ECS_SG_ID" ]; then
    execute_cmd "aws ec2 delete-security-group \
        --group-id ${ECS_SG_ID} \
        --region ${AWS_REGION}" \
        "Delete ECS security group" \
        true
fi

if [ -n "$ALB_SG_ID" ]; then
    execute_cmd "aws ec2 delete-security-group \
        --group-id ${ALB_SG_ID} \
        --region ${AWS_REGION}" \
        "Delete ALB security group" \
        true
fi

# Fallback: Delete security groups by name
execute_cmd "aws ec2 delete-security-group \
    --group-name ${PROJECT_NAME}-ecs-sg \
    --region ${AWS_REGION}" \
    "Delete ECS security group (fallback)" \
    true

execute_cmd "aws ec2 delete-security-group \
    --group-name ${PROJECT_NAME}-alb-sg \
    --region ${AWS_REGION}" \
    "Delete ALB security group (fallback)" \
    true

# Step 7: Delete VPC and Networking Resources
log "Step 7: Deleting VPC and networking resources..."

# Delete subnets if we have the IDs
if [ -n "$SUBNET_1" ]; then
    execute_cmd "aws ec2 delete-subnet \
        --subnet-id ${SUBNET_1} \
        --region ${AWS_REGION}" \
        "Delete subnet 1" \
        true
fi

if [ -n "$SUBNET_2" ]; then
    execute_cmd "aws ec2 delete-subnet \
        --subnet-id ${SUBNET_2} \
        --region ${AWS_REGION}" \
        "Delete subnet 2" \
        true
fi

if [ -n "$SUBNET_3" ]; then
    execute_cmd "aws ec2 delete-subnet \
        --subnet-id ${SUBNET_3} \
        --region ${AWS_REGION}" \
        "Delete subnet 3" \
        true
fi

# Delete route table if we have the ID
if [ -n "$RT_ID" ]; then
    execute_cmd "aws ec2 delete-route-table \
        --route-table-id ${RT_ID} \
        --region ${AWS_REGION}" \
        "Delete route table" \
        true
fi

# Detach and delete internet gateway if we have the ID
if [ -n "$IGW_ID" ] && [ -n "$VPC_ID" ]; then
    execute_cmd "aws ec2 detach-internet-gateway \
        --internet-gateway-id ${IGW_ID} \
        --vpc-id ${VPC_ID} \
        --region ${AWS_REGION}" \
        "Detach internet gateway" \
        true
    
    execute_cmd "aws ec2 delete-internet-gateway \
        --internet-gateway-id ${IGW_ID} \
        --region ${AWS_REGION}" \
        "Delete internet gateway" \
        true
fi

# Delete VPC if we have the ID
if [ -n "$VPC_ID" ]; then
    execute_cmd "aws ec2 delete-vpc \
        --vpc-id ${VPC_ID} \
        --region ${AWS_REGION}" \
        "Delete VPC" \
        true
fi

# Step 8: Delete IAM Roles and Policies
log "Step 8: Deleting IAM roles and policies..."

# Delete task role policy and role
execute_cmd "aws iam delete-role-policy \
    --role-name ${PROJECT_NAME}-task-role \
    --policy-name ${PROJECT_NAME}-task-policy" \
    "Delete task role policy" \
    true

execute_cmd "aws iam delete-role \
    --role-name ${PROJECT_NAME}-task-role" \
    "Delete task role" \
    true

# Delete task execution role
execute_cmd "aws iam detach-role-policy \
    --role-name ${PROJECT_NAME}-task-execution-role \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" \
    "Detach task execution policy" \
    true

execute_cmd "aws iam delete-role \
    --role-name ${PROJECT_NAME}-task-execution-role" \
    "Delete task execution role" \
    true

# Delete CodeDeploy role
execute_cmd "aws iam detach-role-policy \
    --role-name ${PROJECT_NAME}-codedeploy-role \
    --policy-arn arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS" \
    "Detach CodeDeploy policy" \
    true

execute_cmd "aws iam delete-role \
    --role-name ${PROJECT_NAME}-codedeploy-role" \
    "Delete CodeDeploy role" \
    true

# Delete CodeBuild role
execute_cmd "aws iam delete-role-policy \
    --role-name ${PROJECT_NAME}-codebuild-role \
    --policy-name ${PROJECT_NAME}-codebuild-policy" \
    "Delete CodeBuild role policy" \
    true

execute_cmd "aws iam delete-role \
    --role-name ${PROJECT_NAME}-codebuild-role" \
    "Delete CodeBuild role" \
    true

# Delete CodePipeline role
execute_cmd "aws iam delete-role-policy \
    --role-name ${PROJECT_NAME}-codepipeline-role \
    --policy-name ${PROJECT_NAME}-codepipeline-policy" \
    "Delete CodePipeline role policy" \
    true

execute_cmd "aws iam delete-role \
    --role-name ${PROJECT_NAME}-codepipeline-role" \
    "Delete CodePipeline role" \
    true

# Step 9: Delete CloudWatch Resources
log "Step 9: Deleting CloudWatch resources..."

execute_cmd "aws cloudwatch delete-alarms \
    --alarm-names ${PROJECT_NAME}-high-error-rate ${PROJECT_NAME}-high-response-time \
    --region ${AWS_REGION}" \
    "Delete CloudWatch alarms" \
    true

# Delete SNS topic if we have the ARN
if [ -n "$SNS_TOPIC_ARN" ]; then
    execute_cmd "aws sns delete-topic \
        --topic-arn ${SNS_TOPIC_ARN} \
        --region ${AWS_REGION}" \
        "Delete SNS topic" \
        true
fi

# Delete CloudWatch log groups
execute_cmd "aws logs delete-log-group \
    --log-group-name /ecs/${PROJECT_NAME}/dev \
    --region ${AWS_REGION}" \
    "Delete dev log group" \
    true

execute_cmd "aws logs delete-log-group \
    --log-group-name /ecs/${PROJECT_NAME}/prod \
    --region ${AWS_REGION}" \
    "Delete prod log group" \
    true

# Step 10: Delete Parameter Store Parameters
log "Step 10: Deleting Parameter Store parameters..."

execute_cmd "aws ssm delete-parameter \
    --name /${PROJECT_NAME}/app/environment \
    --region ${AWS_REGION}" \
    "Delete environment parameter" \
    true

execute_cmd "aws ssm delete-parameter \
    --name /${PROJECT_NAME}/app/version \
    --region ${AWS_REGION}" \
    "Delete version parameter" \
    true

# Step 11: Delete S3 Bucket
log "Step 11: Deleting S3 bucket..."

execute_cmd "aws s3 rb s3://${PROJECT_NAME}-artifacts-${AWS_REGION} \
    --force \
    --region ${AWS_REGION}" \
    "Delete S3 artifacts bucket" \
    true

# Step 12: Delete ECR Repository
log "Step 12: Deleting ECR repository..."

execute_cmd "aws ecr delete-repository \
    --repository-name ${REPOSITORY_NAME} \
    --force \
    --region ${AWS_REGION}" \
    "Delete ECR repository" \
    true

# Step 13: Cleanup temporary files
log "Step 13: Cleaning up temporary files..."

execute_cmd "rm -f /tmp/deployment-info.json" \
    "Remove deployment info file" \
    true

execute_cmd "rm -f /tmp/lifecycle-policy.json" \
    "Remove lifecycle policy file" \
    true

execute_cmd "rm -f /tmp/task-role-policy.json" \
    "Remove task role policy file" \
    true

execute_cmd "rm -f /tmp/dev-task-definition.json" \
    "Remove dev task definition file" \
    true

execute_cmd "rm -f /tmp/prod-task-definition.json" \
    "Remove prod task definition file" \
    true

execute_cmd "rm -f /tmp/prod-deployment-group-config.json" \
    "Remove deployment group config file" \
    true

execute_cmd "rm -f /tmp/codebuild-policy.json" \
    "Remove CodeBuild policy file" \
    true

execute_cmd "rm -f /tmp/codepipeline-policy.json" \
    "Remove CodePipeline policy file" \
    true

execute_cmd "rm -f /tmp/pipeline-config.json" \
    "Remove pipeline config file" \
    true

# Final verification
log "Step 14: Final verification..."

if [ "$DRY_RUN" = "false" ]; then
    # Check if major resources still exist
    if aws ecs describe-clusters --clusters ${DEV_CLUSTER_NAME} --region ${AWS_REGION} &>/dev/null; then
        warn "Development cluster may still exist"
    fi
    
    if aws ecs describe-clusters --clusters ${PROD_CLUSTER_NAME} --region ${AWS_REGION} &>/dev/null; then
        warn "Production cluster may still exist"
    fi
    
    if aws codepipeline get-pipeline --name ${PIPELINE_NAME} --region ${AWS_REGION} &>/dev/null; then
        warn "CodePipeline may still exist"
    fi
    
    if aws ecr describe-repositories --repository-names ${REPOSITORY_NAME} --region ${AWS_REGION} &>/dev/null; then
        warn "ECR repository may still exist"
    fi
    
    if aws s3 ls s3://${PROJECT_NAME}-artifacts-${AWS_REGION} &>/dev/null; then
        warn "S3 bucket may still exist"
    fi
fi

# Final summary
echo "=========================================="
echo "    AWS CI/CD Pipeline Cleanup Complete"
echo "=========================================="
log "Cleanup completed!"
info "Project: ${PROJECT_NAME}"
info "Region: ${AWS_REGION}"

if [ "$DRY_RUN" = "true" ]; then
    warn "This was a DRY-RUN. No actual resources were deleted."
    info "To perform actual cleanup, run: DRY_RUN=false $0"
else
    log "All resources have been cleaned up successfully"
    warn "Please verify in AWS Console that all resources are deleted"
    info "You may need to manually delete any remaining resources"
fi

echo "=========================================="
echo "Cleanup Summary:"
echo "✓ CodePipeline and CodeBuild resources"
echo "✓ CodeDeploy resources"
echo "✓ ECS services and clusters"
echo "✓ Load balancers and target groups"
echo "✓ Security groups"
echo "✓ VPC and networking resources"
echo "✓ IAM roles and policies"
echo "✓ CloudWatch resources"
echo "✓ Parameter Store parameters"
echo "✓ S3 bucket"
echo "✓ ECR repository"
echo "✓ Temporary files"
echo "=========================================="

log "Cleanup script completed successfully!"