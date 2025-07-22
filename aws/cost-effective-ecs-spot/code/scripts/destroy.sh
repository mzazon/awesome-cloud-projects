#!/bin/bash

# Cost-Effective ECS Clusters with Spot Instances
# Destroy Script - Removes all resources created by the deploy script
# Version: 1.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Default values
CLUSTER_NAME="cost-optimized-cluster"
SERVICE_NAME="spot-resilient-service"
CAPACITY_PROVIDER_NAME="spot-capacity-provider"
ASG_NAME="ecs-spot-asg"
REGION=""
FORCE=false
SKIP_CONFIRM=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --service-name)
            SERVICE_NAME="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            SKIP_CONFIRM=true
            shift
            ;;
        --yes)
            SKIP_CONFIRM=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --cluster-name NAME      ECS cluster name (default: cost-optimized-cluster)"
            echo "  --service-name NAME      ECS service name (default: spot-resilient-service)"
            echo "  --region REGION          AWS region (default: from AWS CLI config)"
            echo "  --force                 Skip all confirmations and force cleanup"
            echo "  --yes                   Skip confirmations but show what's being deleted"
            echo "  --help                  Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

log "Starting cleanup of Cost-Effective ECS Cluster with Spot Instances"

# Set region from CLI config if not provided
if [[ -z "$REGION" ]]; then
    REGION=$(aws configure get region)
    if [[ -z "$REGION" ]]; then
        error "AWS region not configured. Set region using 'aws configure' or --region parameter"
    fi
fi

log "Using AWS region: $REGION"

# Set environment variables
export AWS_REGION="$REGION"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured or invalid"
fi

# Display what will be deleted
log "The following resources will be deleted:"
echo "  • ECS Service: $SERVICE_NAME"
echo "  • ECS Cluster: $CLUSTER_NAME"
echo "  • ECS Capacity Provider: $CAPACITY_PROVIDER_NAME"
echo "  • Auto Scaling Group: $ASG_NAME"
echo "  • Launch Template: ecs-spot-template"
echo "  • Security Group: ecs-spot-cluster-sg"
echo "  • IAM Roles: ecsTaskExecutionRole, ecsInstanceRole"
echo "  • IAM Instance Profile: ecsInstanceProfile"
echo "  • Application Auto Scaling configurations"
echo "  • CloudWatch Log Groups"
echo

# Confirmation prompt
if [[ "$SKIP_CONFIRM" == "false" ]]; then
    read -p "Are you sure you want to delete these resources? This action cannot be undone. (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
fi

# Function to safely delete resources with error handling
safe_delete() {
    local resource_type="$1"
    local command="$2"
    local resource_name="$3"
    
    log "Deleting $resource_type: $resource_name"
    
    if eval "$command" &>/dev/null; then
        log "✅ $resource_type deleted successfully"
    else
        warn "Failed to delete $resource_type or resource doesn't exist"
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local check_command="$1"
    local resource_name="$2"
    local max_wait="$3"
    
    log "Waiting for $resource_name to be deleted..."
    local count=0
    
    while eval "$check_command" &>/dev/null && [ $count -lt $max_wait ]; do
        sleep 10
        count=$((count + 1))
        echo -n "."
    done
    echo
    
    if [ $count -ge $max_wait ]; then
        warn "$resource_name deletion timed out"
        return 1
    fi
    
    return 0
}

# 1. Remove auto scaling configuration
log "Removing auto scaling configuration..."

safe_delete "Auto Scaling Policy" \
    "aws application-autoscaling delete-scaling-policy --service-namespace ecs --resource-id service/$CLUSTER_NAME/$SERVICE_NAME --scalable-dimension ecs:service:DesiredCount --policy-name cpu-target-tracking" \
    "cpu-target-tracking"

safe_delete "Scalable Target" \
    "aws application-autoscaling deregister-scalable-target --service-namespace ecs --resource-id service/$CLUSTER_NAME/$SERVICE_NAME --scalable-dimension ecs:service:DesiredCount" \
    "ECS Service Scalable Target"

# 2. Scale down and delete ECS service
log "Scaling down ECS service..."

if aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" &> /dev/null; then
    log "Scaling service to 0 tasks..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --desired-count 0 &>/dev/null || warn "Failed to scale down service"
    
    # Wait for tasks to stop
    log "Waiting for tasks to stop..."
    aws ecs wait services-stable --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" || \
        warn "Service did not stabilize within timeout"
    
    # Delete the service
    safe_delete "ECS Service" \
        "aws ecs delete-service --cluster $CLUSTER_NAME --service $SERVICE_NAME" \
        "$SERVICE_NAME"
else
    log "ECS service $SERVICE_NAME not found"
fi

# 3. Remove capacity provider from cluster
log "Removing capacity provider from cluster..."

safe_delete "Capacity Provider Association" \
    "aws ecs put-cluster-capacity-providers --cluster $CLUSTER_NAME --capacity-providers --default-capacity-provider-strategy" \
    "Cluster Capacity Provider"

# 4. Delete capacity provider
log "Deleting capacity provider..."

safe_delete "ECS Capacity Provider" \
    "aws ecs delete-capacity-provider --capacity-provider $CAPACITY_PROVIDER_NAME" \
    "$CAPACITY_PROVIDER_NAME"

# 5. Delete Auto Scaling Group
log "Deleting Auto Scaling Group..."

if aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" &> /dev/null; then
    # Update ASG to 0 instances
    log "Scaling Auto Scaling Group to 0 instances..."
    aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name "$ASG_NAME" \
        --min-size 0 --max-size 0 --desired-capacity 0 &>/dev/null || \
        warn "Failed to scale down Auto Scaling Group"
    
    # Wait for instances to terminate
    log "Waiting for instances to terminate..."
    wait_for_deletion \
        "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG_NAME --query 'AutoScalingGroups[0].Instances[0]' --output text | grep -v None" \
        "Auto Scaling Group instances" \
        30
    
    # Delete Auto Scaling Group
    safe_delete "Auto Scaling Group" \
        "aws autoscaling delete-auto-scaling-group --auto-scaling-group-name $ASG_NAME" \
        "$ASG_NAME"
else
    log "Auto Scaling Group $ASG_NAME not found"
fi

# 6. Delete launch template
log "Deleting launch template..."

LAUNCH_TEMPLATE_ID=$(aws ec2 describe-launch-templates --launch-template-names ecs-spot-template \
    --query 'LaunchTemplates[0].LaunchTemplateId' --output text 2>/dev/null || echo "None")

if [[ "$LAUNCH_TEMPLATE_ID" != "None" ]]; then
    safe_delete "Launch Template" \
        "aws ec2 delete-launch-template --launch-template-id $LAUNCH_TEMPLATE_ID" \
        "ecs-spot-template"
else
    log "Launch template ecs-spot-template not found"
fi

# 7. Delete security group
log "Deleting security group..."

SG_ID=$(aws ec2 describe-security-groups --group-names ecs-spot-cluster-sg \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "None")

if [[ "$SG_ID" != "None" ]]; then
    safe_delete "Security Group" \
        "aws ec2 delete-security-group --group-id $SG_ID" \
        "ecs-spot-cluster-sg"
else
    log "Security group ecs-spot-cluster-sg not found"
fi

# 8. Delete ECS cluster
log "Deleting ECS cluster..."

if aws ecs describe-clusters --clusters "$CLUSTER_NAME" &> /dev/null; then
    safe_delete "ECS Cluster" \
        "aws ecs delete-cluster --cluster $CLUSTER_NAME" \
        "$CLUSTER_NAME"
else
    log "ECS cluster $CLUSTER_NAME not found"
fi

# 9. Clean up IAM roles and instance profile
log "Cleaning up IAM roles..."

# Remove role from instance profile
if aws iam get-instance-profile --instance-profile-name ecsInstanceProfile &> /dev/null; then
    safe_delete "Role from Instance Profile" \
        "aws iam remove-role-from-instance-profile --instance-profile-name ecsInstanceProfile --role-name ecsInstanceRole" \
        "ecsInstanceRole from ecsInstanceProfile"
fi

# Delete instance profile
safe_delete "Instance Profile" \
    "aws iam delete-instance-profile --instance-profile-name ecsInstanceProfile" \
    "ecsInstanceProfile"

# Detach policies and delete ECS instance role
if aws iam get-role --role-name ecsInstanceRole &> /dev/null; then
    safe_delete "Policy from Role" \
        "aws iam detach-role-policy --role-name ecsInstanceRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role" \
        "EC2 Policy from ecsInstanceRole"
    
    safe_delete "ECS Instance Role" \
        "aws iam delete-role --role-name ecsInstanceRole" \
        "ecsInstanceRole"
else
    log "ECS Instance Role not found"
fi

# Detach policies and delete ECS task execution role
if aws iam get-role --role-name ecsTaskExecutionRole &> /dev/null; then
    safe_delete "Policy from Role" \
        "aws iam detach-role-policy --role-name ecsTaskExecutionRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" \
        "Task Execution Policy from ecsTaskExecutionRole"
    
    safe_delete "ECS Task Execution Role" \
        "aws iam delete-role --role-name ecsTaskExecutionRole" \
        "ecsTaskExecutionRole"
else
    log "ECS Task Execution Role not found"
fi

# 10. Clean up CloudWatch Log Groups
log "Cleaning up CloudWatch Log Groups..."

safe_delete "CloudWatch Log Group" \
    "aws logs delete-log-group --log-group-name /ecs/spot-resilient-app" \
    "/ecs/spot-resilient-app"

# 11. Clean up temporary files
log "Cleaning up temporary files..."

rm -f /tmp/ecs-task-execution-role-policy.json
rm -f /tmp/ec2-role-policy.json
rm -f /tmp/mixed-instances-policy.json
rm -f /tmp/task-definition.json
rm -f /tmp/user-data.sh

log "Temporary files cleaned up"

# 12. Final verification
log "Verifying cleanup completion..."

# Check if cluster exists
if aws ecs describe-clusters --clusters "$CLUSTER_NAME" &> /dev/null; then
    CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --query 'clusters[0].status' --output text)
    if [[ "$CLUSTER_STATUS" == "INACTIVE" ]]; then
        log "✅ ECS cluster is being deleted"
    else
        warn "ECS cluster still exists with status: $CLUSTER_STATUS"
    fi
else
    log "✅ ECS cluster successfully deleted"
fi

# Check Auto Scaling Group
if aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" &> /dev/null; then
    warn "Auto Scaling Group still exists"
else
    log "✅ Auto Scaling Group successfully deleted"
fi

# Check IAM roles
if aws iam get-role --role-name ecsInstanceRole &> /dev/null; then
    warn "ECS Instance Role still exists"
else
    log "✅ ECS Instance Role successfully deleted"
fi

if aws iam get-role --role-name ecsTaskExecutionRole &> /dev/null; then
    warn "ECS Task Execution Role still exists"
else
    log "✅ ECS Task Execution Role successfully deleted"
fi

# Display cleanup summary
echo
echo "=== CLEANUP SUMMARY ==="
echo "Cluster Name: $CLUSTER_NAME"
echo "Service Name: $SERVICE_NAME"
echo "Capacity Provider: $CAPACITY_PROVIDER_NAME"
echo "Auto Scaling Group: $ASG_NAME"
echo "AWS Region: $AWS_REGION"
echo

# Cost impact information
echo "=== COST IMPACT ==="
echo "✅ All EC2 Spot and On-Demand instances terminated"
echo "✅ All ECS services stopped (no more task charges)"
echo "✅ CloudWatch Container Insights disabled"
echo "✅ Application Load Balancer charges stopped (if used)"
echo
echo "⚠️  Some resources may continue to incur minimal charges:"
echo "   • CloudWatch logs (if retention is configured)"
echo "   • EBS volumes (if not deleted with instances)"
echo "   • VPC resources (if custom VPC was used)"
echo
echo "💡 Monitor your AWS billing console for the next 24-48 hours"
echo "   to ensure all charges have stopped."
echo

# Check for remaining resources that might incur costs
log "Checking for remaining resources that might incur costs..."

# Check for remaining ECS tasks
RUNNING_TASKS=$(aws ecs list-tasks --cluster "$CLUSTER_NAME" --desired-status RUNNING \
    --query 'taskArns' --output text 2>/dev/null || echo "")

if [[ -n "$RUNNING_TASKS" ]]; then
    warn "Found running tasks that may still incur charges:"
    echo "$RUNNING_TASKS"
else
    log "✅ No running ECS tasks found"
fi

# Check for remaining EC2 instances with our tags
REMAINING_INSTANCES=$(aws ec2 describe-instances --filters \
    "Name=tag:CreatedBy,Values=cost-optimized-ecs-recipe" \
    "Name=instance-state-name,Values=running,pending" \
    --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null || echo "")

if [[ -n "$REMAINING_INSTANCES" ]]; then
    warn "Found EC2 instances that may still incur charges:"
    echo "$REMAINING_INSTANCES"
else
    log "✅ No remaining EC2 instances found"
fi

echo
if [[ "$FORCE" == "true" ]]; then
    log "Cleanup completed (forced mode)"
else
    log "Cleanup completed successfully! 🎉"
fi

log "All resources have been cleaned up. Check AWS console to verify complete deletion."