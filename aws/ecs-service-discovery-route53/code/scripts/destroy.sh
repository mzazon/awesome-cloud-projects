#!/bin/bash

# ECS Service Discovery with Route 53 and Application Load Balancer - Cleanup Script
# This script removes all infrastructure created for ECS service discovery with ALB integration

set -euo pipefail

# Color codes for output
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
    exit 1
}

# Check if force mode is enabled
FORCE_MODE=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE_MODE=true
    shift
fi

# Load deployment configuration
load_deployment_config() {
    local config_file="$(dirname "$0")/deployment-config.env"
    
    if [[ -f "$config_file" ]]; then
        log_info "Loading deployment configuration from $config_file"
        source "$config_file"
    else
        log_warning "Deployment configuration file not found. Will attempt to discover resources."
        
        # Try to discover resources if config file doesn't exist
        export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
        if [[ -z "$AWS_REGION" ]]; then
            error_exit "AWS region not configured. Please set AWS_REGION environment variable."
        fi
        
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Try to find resources by tags
        discover_resources
    fi
}

# Discover resources by tags when config file is not available
discover_resources() {
    log_info "Discovering resources by tags..."
    
    # Find ECS clusters with ServiceDiscovery tag
    local clusters=$(aws ecs list-clusters --query "clusterArns[*]" --output text)
    for cluster_arn in $clusters; do
        local cluster_name=$(basename "$cluster_arn")
        if [[ "$cluster_name" =~ ^microservices-cluster- ]]; then
            export CLUSTER_NAME="$cluster_name"
            local suffix=$(echo "$cluster_name" | sed 's/microservices-cluster-//')
            export RANDOM_SUFFIX="$suffix"
            break
        fi
    done
    
    # Find ALB with ServiceDiscovery tag
    local albs=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?contains(LoadBalancerName, 'microservices-alb-')].LoadBalancerArn" \
        --output text)
    
    if [[ -n "$albs" ]]; then
        export ALB_ARN=$(echo "$albs" | head -n1)
        export ALB_NAME=$(aws elbv2 describe-load-balancers \
            --load-balancer-arns "$ALB_ARN" \
            --query "LoadBalancers[0].LoadBalancerName" --output text)
    fi
    
    # Find VPC and security groups
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text)
    
    # Find security groups by name pattern
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        export ALB_SG_ID=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=alb-sg-${RANDOM_SUFFIX}" \
            --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "")
        
        export ECS_SG_ID=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=ecs-tasks-sg-${RANDOM_SUFFIX}" \
            --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "")
    fi
    
    # Find service discovery namespace
    export NAMESPACE_ID=$(aws servicediscovery list-namespaces \
        --query "Namespaces[?Name=='internal.local'].Id" \
        --output text)
    
    export NAMESPACE_NAME="internal.local"
    
    if [[ -n "$NAMESPACE_ID" ]]; then
        # Find service discovery services
        export WEB_SERVICE_ID=$(aws servicediscovery list-services \
            --filters "Name=NAMESPACE_ID,Values=${NAMESPACE_ID}" \
            --query "Services[?Name=='web'].Id" --output text)
        
        export API_SERVICE_ID=$(aws servicediscovery list-services \
            --filters "Name=NAMESPACE_ID,Values=${NAMESPACE_ID}" \
            --query "Services[?Name=='api'].Id" --output text)
        
        export DB_SERVICE_ID=$(aws servicediscovery list-services \
            --filters "Name=NAMESPACE_ID,Values=${NAMESPACE_ID}" \
            --query "Services[?Name=='database'].Id" --output text)
    fi
    
    log_info "Resource discovery completed"
}

# Safe resource deletion with error handling
safe_delete() {
    local resource_type="$1"
    local delete_command="$2"
    local resource_id="$3"
    
    if [[ -z "$resource_id" || "$resource_id" == "None" ]]; then
        log_warning "No $resource_type found to delete"
        return 0
    fi
    
    log_info "Deleting $resource_type: $resource_id"
    
    if eval "$delete_command" 2>/dev/null; then
        log_success "Deleted $resource_type: $resource_id"
    else
        log_error "Failed to delete $resource_type: $resource_id"
        return 1
    fi
}

# Wait for resource deletion
wait_for_deletion() {
    local check_command="$1"
    local resource_type="$2"
    local max_attempts=30
    local attempt=0
    
    log_info "Waiting for $resource_type deletion to complete..."
    
    while [[ $attempt -lt $max_attempts ]]; do
        if ! eval "$check_command" &>/dev/null; then
            log_success "$resource_type deletion completed"
            return 0
        fi
        
        sleep 10
        ((attempt++))
        echo -n "."
    done
    
    log_warning "Timeout waiting for $resource_type deletion"
    return 1
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE_MODE" == true ]]; then
        return 0
    fi
    
    echo ""
    echo "========================================="
    echo "         RESOURCE DELETION WARNING"
    echo "========================================="
    echo "This will delete the following resources:"
    echo "- ECS Cluster: ${CLUSTER_NAME:-unknown}"
    echo "- DNS Namespace: ${NAMESPACE_NAME:-unknown}"
    echo "- Load Balancer: ${ALB_NAME:-unknown}"
    echo "- Security Groups and other resources"
    echo ""
    echo "This action cannot be undone!"
    echo "========================================="
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
}

# Main cleanup function
cleanup_infrastructure() {
    log_info "Starting infrastructure cleanup..."
    
    # Step 1: Scale down and delete ECS services
    if [[ -n "${CLUSTER_NAME:-}" ]]; then
        log_info "Scaling down and deleting ECS services..."
        
        # Get all services in the cluster
        local services=$(aws ecs list-services \
            --cluster "${CLUSTER_NAME}" \
            --query "serviceArns[*]" --output text 2>/dev/null || echo "")
        
        for service_arn in $services; do
            local service_name=$(basename "$service_arn")
            
            # Scale down service
            log_info "Scaling down service: $service_name"
            aws ecs update-service \
                --cluster "${CLUSTER_NAME}" \
                --service "$service_name" \
                --desired-count 0 &>/dev/null || true
        done
        
        # Wait for tasks to stop
        log_info "Waiting for tasks to stop..."
        sleep 30
        
        # Delete services
        for service_arn in $services; do
            local service_name=$(basename "$service_arn")
            
            safe_delete "ECS service" \
                "aws ecs delete-service --cluster \"${CLUSTER_NAME}\" --service \"$service_name\" --force" \
                "$service_name"
        done
        
        # Wait for services to be deleted
        sleep 20
    fi
    
    # Step 2: Remove ALB listeners and rules
    if [[ -n "${WEB_LISTENER_ARN:-}" ]]; then
        log_info "Deleting ALB listeners..."
        
        # Get all rules for the listener
        local rules=$(aws elbv2 describe-rules \
            --listener-arn "${WEB_LISTENER_ARN}" \
            --query "Rules[?Priority!='default'].RuleArn" \
            --output text 2>/dev/null || echo "")
        
        # Delete rules
        for rule_arn in $rules; do
            safe_delete "ALB rule" \
                "aws elbv2 delete-rule --rule-arn \"$rule_arn\"" \
                "$rule_arn"
        done
        
        # Delete listener
        safe_delete "ALB listener" \
            "aws elbv2 delete-listener --listener-arn \"${WEB_LISTENER_ARN}\"" \
            "${WEB_LISTENER_ARN}"
    fi
    
    # Step 3: Delete target groups
    if [[ -n "${WEB_TG_ARN:-}" ]]; then
        safe_delete "Web target group" \
            "aws elbv2 delete-target-group --target-group-arn \"${WEB_TG_ARN}\"" \
            "${WEB_TG_ARN}"
    fi
    
    if [[ -n "${API_TG_ARN:-}" ]]; then
        safe_delete "API target group" \
            "aws elbv2 delete-target-group --target-group-arn \"${API_TG_ARN}\"" \
            "${API_TG_ARN}"
    fi
    
    # Step 4: Delete Application Load Balancer
    if [[ -n "${ALB_ARN:-}" ]]; then
        safe_delete "Application Load Balancer" \
            "aws elbv2 delete-load-balancer --load-balancer-arn \"${ALB_ARN}\"" \
            "${ALB_ARN}"
        
        # Wait for ALB deletion
        wait_for_deletion \
            "aws elbv2 describe-load-balancers --load-balancer-arns \"${ALB_ARN}\"" \
            "Application Load Balancer"
    fi
    
    # Step 5: Delete service discovery services
    log_info "Deleting service discovery services..."
    
    if [[ -n "${WEB_SERVICE_ID:-}" ]]; then
        safe_delete "Web service discovery" \
            "aws servicediscovery delete-service --id \"${WEB_SERVICE_ID}\"" \
            "${WEB_SERVICE_ID}"
    fi
    
    if [[ -n "${API_SERVICE_ID:-}" ]]; then
        safe_delete "API service discovery" \
            "aws servicediscovery delete-service --id \"${API_SERVICE_ID}\"" \
            "${API_SERVICE_ID}"
    fi
    
    if [[ -n "${DB_SERVICE_ID:-}" ]]; then
        safe_delete "Database service discovery" \
            "aws servicediscovery delete-service --id \"${DB_SERVICE_ID}\"" \
            "${DB_SERVICE_ID}"
    fi
    
    # Step 6: Delete service discovery namespace
    if [[ -n "${NAMESPACE_ID:-}" ]]; then
        safe_delete "Service discovery namespace" \
            "aws servicediscovery delete-namespace --id \"${NAMESPACE_ID}\"" \
            "${NAMESPACE_ID}"
    fi
    
    # Step 7: Delete ECS cluster
    if [[ -n "${CLUSTER_NAME:-}" ]]; then
        safe_delete "ECS cluster" \
            "aws ecs delete-cluster --cluster \"${CLUSTER_NAME}\"" \
            "${CLUSTER_NAME}"
    fi
    
    # Step 8: Delete security groups
    if [[ -n "${ECS_SG_ID:-}" ]]; then
        safe_delete "ECS security group" \
            "aws ec2 delete-security-group --group-id \"${ECS_SG_ID}\"" \
            "${ECS_SG_ID}"
    fi
    
    if [[ -n "${ALB_SG_ID:-}" ]]; then
        safe_delete "ALB security group" \
            "aws ec2 delete-security-group --group-id \"${ALB_SG_ID}\"" \
            "${ALB_SG_ID}"
    fi
    
    # Step 9: Delete IAM role
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local role_name="ecsTaskExecutionRole-${RANDOM_SUFFIX}"
        
        log_info "Deleting IAM role: $role_name"
        
        # Detach policies
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" \
            2>/dev/null || true
        
        # Delete role
        aws iam delete-role --role-name "$role_name" 2>/dev/null || true
        
        log_success "Deleted IAM role: $role_name"
    fi
    
    # Step 10: Deregister task definitions
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        log_info "Deregistering task definitions..."
        
        # List and deregister web service task definitions
        local web_task_definitions=$(aws ecs list-task-definitions \
            --family-prefix "web-service-${RANDOM_SUFFIX}" \
            --query "taskDefinitionArns[*]" --output text 2>/dev/null || echo "")
        
        for task_def in $web_task_definitions; do
            aws ecs deregister-task-definition --task-definition "$task_def" &>/dev/null || true
        done
        
        # List and deregister API service task definitions
        local api_task_definitions=$(aws ecs list-task-definitions \
            --family-prefix "api-service-${RANDOM_SUFFIX}" \
            --query "taskDefinitionArns[*]" --output text 2>/dev/null || echo "")
        
        for task_def in $api_task_definitions; do
            aws ecs deregister-task-definition --task-definition "$task_def" &>/dev/null || true
        done
        
        log_success "Deregistered task definitions"
    fi
    
    # Step 11: Delete CloudWatch log groups
    log_info "Deleting CloudWatch log groups..."
    
    aws logs delete-log-group --log-group-name "/ecs/web-service" 2>/dev/null || true
    aws logs delete-log-group --log-group-name "/ecs/api-service" 2>/dev/null || true
    
    log_success "Deleted CloudWatch log groups"
    
    # Step 12: Clean up configuration file
    local config_file="$(dirname "$0")/deployment-config.env"
    if [[ -f "$config_file" ]]; then
        rm -f "$config_file"
        log_success "Removed deployment configuration file"
    fi
    
    log_success "Infrastructure cleanup completed successfully!"
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set appropriate environment variables."
    fi
    
    log_success "Prerequisites check completed"
}

# Dry run mode
dry_run() {
    log_info "Running in dry-run mode. No resources will be deleted."
    
    load_deployment_config
    
    echo ""
    echo "========================================="
    echo "         DRY RUN - RESOURCES TO DELETE"
    echo "========================================="
    echo "ECS Cluster: ${CLUSTER_NAME:-not found}"
    echo "DNS Namespace: ${NAMESPACE_NAME:-not found} (${NAMESPACE_ID:-not found})"
    echo "Load Balancer: ${ALB_NAME:-not found}"
    echo "ALB ARN: ${ALB_ARN:-not found}"
    echo "Web Service ID: ${WEB_SERVICE_ID:-not found}"
    echo "API Service ID: ${API_SERVICE_ID:-not found}"
    echo "Database Service ID: ${DB_SERVICE_ID:-not found}"
    echo "ALB Security Group: ${ALB_SG_ID:-not found}"
    echo "ECS Security Group: ${ECS_SG_ID:-not found}"
    echo "Web Target Group: ${WEB_TG_ARN:-not found}"
    echo "API Target Group: ${API_TG_ARN:-not found}"
    echo "Web Listener: ${WEB_LISTENER_ARN:-not found}"
    echo "Execution Role: ${EXECUTION_ROLE_ARN:-not found}"
    echo "Random Suffix: ${RANDOM_SUFFIX:-not found}"
    echo "========================================="
    
    log_info "Dry-run completed. Use --force to skip confirmation prompts."
}

# Main execution
main() {
    log_info "Starting ECS Service Discovery cleanup..."
    
    # Handle dry run
    if [[ "${1:-}" == "--dry-run" ]]; then
        check_prerequisites
        dry_run
        exit 0
    fi
    
    check_prerequisites
    load_deployment_config
    confirm_deletion
    cleanup_infrastructure
    
    log_success "ECS Service Discovery cleanup completed successfully!"
}

# Execute main function
main "$@"