#!/bin/bash

# Destroy script for Container Health Checks and Self-Healing Applications
# This script cleans up all resources created by the deployment

set -e  # Exit on any error
set -o pipefail  # Exit if any command in pipeline fails

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  INFO: $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ SUCCESS: $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}"
}

log_error() {
    echo -e "${RED}❌ ERROR: $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"
FORCE_DELETE=false
CONFIRM_DELETE=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            CONFIRM_DELETE=false
            shift
            ;;
        --yes)
            CONFIRM_DELETE=false
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force    Force deletion without confirmation"
            echo "  --yes      Skip confirmation prompts"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Required command '$1' not found. Please install it first."
        exit 1
    fi
}

# Function to load deployment state
load_deployment_state() {
    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
        log_error "Deployment state file not found: $DEPLOYMENT_STATE_FILE"
        log_error "Cannot proceed with cleanup without state information."
        exit 1
    fi
    
    log_info "Loading deployment state..."
    source "$DEPLOYMENT_STATE_FILE"
    
    # Validate required variables
    if [[ -z "$RANDOM_SUFFIX" ]]; then
        log_error "RANDOM_SUFFIX not found in deployment state. Cannot proceed."
        exit 1
    fi
    
    log_success "Deployment state loaded (Suffix: $RANDOM_SUFFIX)"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$CONFIRM_DELETE" == "true" ]]; then
        echo ""
        log_warning "This will delete ALL resources created by the deployment."
        echo "Resources to be deleted:"
        echo "  - ECS Cluster: $CLUSTER_NAME"
        echo "  - ECS Service: $SERVICE_NAME"
        echo "  - Application Load Balancer: $ALB_NAME"
        echo "  - VPC and networking components"
        echo "  - Lambda function: self-healing-function-${RANDOM_SUFFIX}"
        echo "  - CloudWatch alarms"
        echo "  - IAM roles and policies"
        echo ""
        
        read -p "Are you sure you want to proceed? [y/N]: " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Destruction cancelled by user."
            exit 0
        fi
    fi
}

# Function to safely delete resource with error handling
safe_delete() {
    local description="$1"
    local command="$2"
    local ignore_errors="${3:-false}"
    
    log_info "Deleting $description..."
    
    if eval "$command" 2>/dev/null; then
        log_success "$description deleted"
    else
        if [[ "$ignore_errors" == "true" ]]; then
            log_warning "$description not found or already deleted"
        else
            log_error "Failed to delete $description"
            return 1
        fi
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local description="$1"
    local check_command="$2"
    local max_attempts=30
    local attempt=0
    
    log_info "Waiting for $description to be deleted..."
    
    while [[ $attempt -lt $max_attempts ]]; do
        if ! eval "$check_command" &>/dev/null; then
            log_success "$description deleted"
            return 0
        fi
        
        attempt=$((attempt + 1))
        sleep 10
    done
    
    log_warning "$description deletion timed out"
    return 1
}

# Function to delete Lambda function and role
delete_lambda_resources() {
    log_info "Deleting Lambda function and role..."
    
    # Delete Lambda function
    if [[ -n "$LAMBDA_ARN" ]]; then
        safe_delete "Lambda function" \
            "aws lambda delete-function --function-name self-healing-function-${RANDOM_SUFFIX}" \
            true
    fi
    
    # Delete Lambda role
    if [[ -n "$LAMBDA_ROLE_ARN" ]]; then
        safe_delete "Lambda role policies" \
            "aws iam detach-role-policy --role-name health-check-lambda-role-${RANDOM_SUFFIX} --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
            true
        
        safe_delete "Lambda role policies" \
            "aws iam detach-role-policy --role-name health-check-lambda-role-${RANDOM_SUFFIX} --policy-arn arn:aws:iam::aws:policy/AmazonECS_FullAccess" \
            true
        
        safe_delete "Lambda execution role" \
            "aws iam delete-role --role-name health-check-lambda-role-${RANDOM_SUFFIX}" \
            true
    fi
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log_info "Deleting CloudWatch alarms..."
    
    local alarms=(
        "UnhealthyTargets-${RANDOM_SUFFIX}"
        "HighResponseTime-${RANDOM_SUFFIX}"
        "ECSServiceRunningTasks-${RANDOM_SUFFIX}"
    )
    
    for alarm in "${alarms[@]}"; do
        safe_delete "CloudWatch alarm: $alarm" \
            "aws cloudwatch delete-alarms --alarm-names $alarm" \
            true
    done
}

# Function to delete auto-scaling resources
delete_autoscaling_resources() {
    log_info "Deleting auto-scaling resources..."
    
    # Delete scaling policy
    safe_delete "Auto-scaling policy" \
        "aws application-autoscaling delete-scaling-policy --service-namespace ecs --resource-id service/$CLUSTER_NAME/$SERVICE_NAME --scalable-dimension ecs:service:DesiredCount --policy-name health-check-scaling-policy-${RANDOM_SUFFIX}" \
        true
    
    # Deregister scalable target
    safe_delete "Scalable target" \
        "aws application-autoscaling deregister-scalable-target --service-namespace ecs --resource-id service/$CLUSTER_NAME/$SERVICE_NAME --scalable-dimension ecs:service:DesiredCount" \
        true
}

# Function to delete ECS resources
delete_ecs_resources() {
    log_info "Deleting ECS resources..."
    
    # Scale down service to 0
    if [[ -n "$SERVICE_NAME" && -n "$CLUSTER_NAME" ]]; then
        log_info "Scaling down ECS service to 0..."
        safe_delete "ECS service scale-down" \
            "aws ecs update-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --desired-count 0" \
            true
        
        # Wait for tasks to stop
        log_info "Waiting for ECS tasks to stop..."
        sleep 30
        
        # Delete ECS service
        safe_delete "ECS service" \
            "aws ecs delete-service --cluster $CLUSTER_NAME --service $SERVICE_NAME" \
            true
        
        # Wait for service deletion
        wait_for_deletion "ECS service" \
            "aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --query 'services[0].status' --output text | grep -q ACTIVE"
    fi
    
    # Delete ECS cluster
    if [[ -n "$CLUSTER_NAME" ]]; then
        safe_delete "ECS cluster" \
            "aws ecs delete-cluster --cluster $CLUSTER_NAME" \
            true
    fi
    
    # Deregister task definition
    safe_delete "Task definition" \
        "aws ecs deregister-task-definition --task-definition health-check-app-${RANDOM_SUFFIX}:1" \
        true
    
    # Delete task execution role
    if [[ -n "$TASK_EXECUTION_ROLE_ARN" ]]; then
        safe_delete "Task execution role policy" \
            "aws iam detach-role-policy --role-name ecsTaskExecutionRole-${RANDOM_SUFFIX} --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" \
            true
        
        safe_delete "Task execution role" \
            "aws iam delete-role --role-name ecsTaskExecutionRole-${RANDOM_SUFFIX}" \
            true
    fi
}

# Function to delete Load Balancer resources
delete_load_balancer_resources() {
    log_info "Deleting Load Balancer resources..."
    
    # Delete ALB listener
    if [[ -n "$ALB_ARN" ]]; then
        local listener_arn=$(aws elbv2 describe-listeners \
            --load-balancer-arn "$ALB_ARN" \
            --query 'Listeners[0].ListenerArn' --output text 2>/dev/null || echo "")
        
        if [[ -n "$listener_arn" && "$listener_arn" != "None" ]]; then
            safe_delete "ALB listener" \
                "aws elbv2 delete-listener --listener-arn $listener_arn" \
                true
        fi
    fi
    
    # Delete target group
    if [[ -n "$TG_ARN" ]]; then
        safe_delete "Target group" \
            "aws elbv2 delete-target-group --target-group-arn $TG_ARN" \
            true
    fi
    
    # Delete Application Load Balancer
    if [[ -n "$ALB_ARN" ]]; then
        safe_delete "Application Load Balancer" \
            "aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN" \
            true
        
        # Wait for ALB deletion
        wait_for_deletion "Application Load Balancer" \
            "aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN"
    fi
}

# Function to delete security groups
delete_security_groups() {
    log_info "Deleting security groups..."
    
    # Delete ECS security group
    if [[ -n "$ECS_SG_ID" ]]; then
        safe_delete "ECS security group" \
            "aws ec2 delete-security-group --group-id $ECS_SG_ID" \
            true
    fi
    
    # Delete ALB security group
    if [[ -n "$ALB_SG_ID" ]]; then
        safe_delete "ALB security group" \
            "aws ec2 delete-security-group --group-id $ALB_SG_ID" \
            true
    fi
}

# Function to delete VPC resources
delete_vpc_resources() {
    log_info "Deleting VPC resources..."
    
    # Disassociate and delete route tables
    if [[ -n "$ROUTE_TABLE_ID" ]]; then
        # Get associations
        local associations=$(aws ec2 describe-route-tables \
            --route-table-ids "$ROUTE_TABLE_ID" \
            --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' \
            --output text 2>/dev/null || echo "")
        
        # Disassociate route tables
        if [[ -n "$associations" ]]; then
            for association in $associations; do
                safe_delete "Route table association" \
                    "aws ec2 disassociate-route-table --association-id $association" \
                    true
            done
        fi
        
        # Delete route table
        safe_delete "Route table" \
            "aws ec2 delete-route-table --route-table-id $ROUTE_TABLE_ID" \
            true
    fi
    
    # Delete subnets
    if [[ -n "$SUBNET_1_ID" ]]; then
        safe_delete "Subnet 1" \
            "aws ec2 delete-subnet --subnet-id $SUBNET_1_ID" \
            true
    fi
    
    if [[ -n "$SUBNET_2_ID" ]]; then
        safe_delete "Subnet 2" \
            "aws ec2 delete-subnet --subnet-id $SUBNET_2_ID" \
            true
    fi
    
    # Detach and delete internet gateway
    if [[ -n "$IGW_ID" && -n "$VPC_ID" ]]; then
        safe_delete "Internet gateway attachment" \
            "aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID" \
            true
        
        safe_delete "Internet gateway" \
            "aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID" \
            true
    fi
    
    # Delete VPC
    if [[ -n "$VPC_ID" ]]; then
        safe_delete "VPC" \
            "aws ec2 delete-vpc --vpc-id $VPC_ID" \
            true
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Clean up deployment state file
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        rm -f "$DEPLOYMENT_STATE_FILE"
        log_success "Deployment state file removed"
    fi
    
    # Clean up any temporary files
    rm -f /tmp/task-definition.json
    rm -f /tmp/self-healing-lambda.py
    rm -f /tmp/self-healing-lambda.zip
    
    log_success "Temporary files cleaned up"
}

# Function to verify AWS credentials
check_aws_credentials() {
    log_info "Validating AWS credentials..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    log_success "AWS credentials validated"
}

# Main destruction function
main() {
    log_info "Starting Container Health Checks and Self-Healing Applications destruction..."
    
    # Prerequisites check
    check_command "aws"
    check_aws_credentials
    
    # Load deployment state
    load_deployment_state
    
    # Confirm deletion
    confirm_deletion
    
    # Delete resources in reverse order of creation
    log_info "Beginning resource cleanup..."
    
    # Delete Lambda resources
    delete_lambda_resources
    
    # Delete CloudWatch alarms
    delete_cloudwatch_alarms
    
    # Delete auto-scaling resources
    delete_autoscaling_resources
    
    # Delete ECS resources
    delete_ecs_resources
    
    # Delete Load Balancer resources
    delete_load_balancer_resources
    
    # Delete security groups
    delete_security_groups
    
    # Delete VPC resources
    delete_vpc_resources
    
    # Clean up temporary files
    cleanup_temp_files
    
    log_success "All resources have been cleaned up successfully!"
    echo ""
    echo "=== CLEANUP COMPLETED ==="
    echo "All infrastructure resources have been deleted."
    echo "If you encounter any issues, you may need to manually"
    echo "delete remaining resources through the AWS Console."
    echo "=========================="
}

# Run main function
main "$@"