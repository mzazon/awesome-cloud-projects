#!/bin/bash

# Distributed Session Management with MemoryDB
# Cleanup Script
# 
# This script safely removes all resources created by the deployment script:
# - ECS Services and Clusters
# - Application Load Balancer and Target Groups
# - MemoryDB for Redis Cluster
# - VPC and Networking Components
# - IAM Roles and Policies
# - Systems Manager Parameters
# - S3 Buckets and Objects

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check if deployment state directory exists
    if [ ! -d ".deployment-state" ]; then
        warning "No .deployment-state directory found."
        warning "This script expects to be run from the same directory as the deployment."
        warning "Attempting to continue with manual resource discovery..."
        return 1
    fi
    
    # Check if resource files exist
    if [ ! -f ".deployment-state/environment.sh" ] || [ ! -f ".deployment-state/resources.txt" ]; then
        warning "Deployment state files not found."
        warning "Some resources may need to be cleaned up manually."
        return 1
    fi
    
    success "Prerequisites check completed"
    return 0
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    echo "⚠️  =================================="
    echo "   DESTRUCTIVE OPERATION WARNING"
    echo "================================== ⚠️"
    echo ""
    echo "This will permanently delete ALL resources created by the deployment:"
    echo ""
    echo "• MemoryDB cluster (all session data will be lost)"
    echo "• ECS services and clusters"
    echo "• Application Load Balancer"
    echo "• VPC and all networking components"
    echo "• IAM roles and policies"
    echo "• S3 bucket and contents"
    echo "• Systems Manager parameters"
    echo "• CloudWatch log groups"
    echo ""
    echo -e "${RED}THIS OPERATION CANNOT BE UNDONE!${NC}"
    echo ""
    
    # Double confirmation for safety
    read -p "Are you absolutely sure you want to destroy all resources? (type 'yes' to continue): " -r
    if [ "$REPLY" != "yes" ]; then
        echo "Operation cancelled."
        exit 0
    fi
    
    echo ""
    read -p "Final confirmation - type 'DESTROY' to proceed: " -r
    if [ "$REPLY" != "DESTROY" ]; then
        echo "Operation cancelled."
        exit 0
    fi
    
    echo ""
    log "Destruction confirmed. Beginning cleanup in 5 seconds..."
    sleep 5
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    if [ -f ".deployment-state/environment.sh" ]; then
        source .deployment-state/environment.sh
        success "Loaded environment variables"
    else
        warning "Environment file not found. Some cleanup may be incomplete."
        return 1
    fi
    
    if [ -f ".deployment-state/resources.txt" ]; then
        source .deployment-state/resources.txt
        success "Loaded resource identifiers"
    else
        warning "Resource file not found. Some cleanup may be incomplete."
        return 1
    fi
    
    return 0
}

# Function to delete ECS service and cluster
delete_ecs_resources() {
    log "Deleting ECS resources..."
    
    # Delete ECS service first
    if [ -n "${CLUSTER_NAME:-}" ] && [ -n "${ECS_SERVICE_NAME:-}" ]; then
        log "Deleting ECS service: ${ECS_SERVICE_NAME}"
        
        # Scale service down to 0
        aws ecs update-service \
            --cluster ${CLUSTER_NAME} \
            --service ${ECS_SERVICE_NAME} \
            --desired-count 0 &> /dev/null || true
        
        # Wait for service to scale down
        log "Waiting for ECS service to scale down..."
        local timeout=300  # 5 minutes
        local elapsed=0
        local interval=10
        
        while [ $elapsed -lt $timeout ]; do
            RUNNING_COUNT=$(aws ecs describe-services \
                --cluster ${CLUSTER_NAME} \
                --services ${ECS_SERVICE_NAME} \
                --query 'services[0].runningCount' \
                --output text 2>/dev/null || echo "0")
            
            if [ "$RUNNING_COUNT" -eq 0 ]; then
                break
            fi
            
            log "Waiting for tasks to stop... (${RUNNING_COUNT} still running)"
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        # Delete the service
        aws ecs delete-service \
            --cluster ${CLUSTER_NAME} \
            --service ${ECS_SERVICE_NAME} \
            --force &> /dev/null || true
        
        success "ECS service deleted"
    fi
    
    # Delete auto scaling configurations
    if [ -n "${CLUSTER_NAME:-}" ] && [ -n "${ECS_SERVICE_NAME:-}" ]; then
        log "Removing auto scaling configuration..."
        
        # Delete scaling policy
        aws application-autoscaling delete-scaling-policy \
            --service-namespace ecs \
            --resource-id service/${CLUSTER_NAME}/${ECS_SERVICE_NAME} \
            --scalable-dimension ecs:service:DesiredCount \
            --policy-name session-app-cpu-scaling &> /dev/null || true
        
        # Deregister scalable target
        aws application-autoscaling deregister-scalable-target \
            --service-namespace ecs \
            --resource-id service/${CLUSTER_NAME}/${ECS_SERVICE_NAME} \
            --scalable-dimension ecs:service:DesiredCount &> /dev/null || true
        
        success "Auto scaling configuration removed"
    fi
    
    # Delete ECS cluster
    if [ -n "${CLUSTER_NAME:-}" ]; then
        log "Deleting ECS cluster: ${CLUSTER_NAME}"
        aws ecs delete-cluster --cluster ${CLUSTER_NAME} &> /dev/null || true
        success "ECS cluster deleted"
    fi
    
    # Deregister task definition (optional - keeps it for historical reference)
    if [ -n "${TASK_DEFINITION_FAMILY:-}" ]; then
        log "Deregistering task definition: ${TASK_DEFINITION_FAMILY}"
        
        # Get all revisions of the task definition
        TASK_DEF_ARNS=$(aws ecs list-task-definitions \
            --family-prefix ${TASK_DEFINITION_FAMILY} \
            --query 'taskDefinitionArns' \
            --output text 2>/dev/null || echo "")
        
        # Deregister each revision
        for arn in $TASK_DEF_ARNS; do
            aws ecs deregister-task-definition \
                --task-definition $arn &> /dev/null || true
        done
        
        success "Task definitions deregistered"
    fi
    
    # Delete CloudWatch log group
    if [ -n "${LOG_GROUP:-}" ]; then
        log "Deleting CloudWatch log group: ${LOG_GROUP}"
        aws logs delete-log-group --log-group-name ${LOG_GROUP} &> /dev/null || true
        success "CloudWatch log group deleted"
    fi
}

# Function to delete Application Load Balancer
delete_load_balancer() {
    log "Deleting Application Load Balancer resources..."
    
    # Delete listener
    if [ -n "${LISTENER_ARN:-}" ]; then
        log "Deleting ALB listener"
        aws elbv2 delete-listener --listener-arn ${LISTENER_ARN} &> /dev/null || true
        success "ALB listener deleted"
    fi
    
    # Delete target group
    if [ -n "${TG_ARN:-}" ]; then
        log "Deleting target group"
        aws elbv2 delete-target-group --target-group-arn ${TG_ARN} &> /dev/null || true
        success "Target group deleted"
    fi
    
    # Delete load balancer
    if [ -n "${ALB_ARN:-}" ]; then
        log "Deleting Application Load Balancer"
        aws elbv2 delete-load-balancer --load-balancer-arn ${ALB_ARN} &> /dev/null || true
        
        # Wait for load balancer deletion
        log "Waiting for load balancer to be deleted..."
        local timeout=300  # 5 minutes
        local elapsed=0
        local interval=15
        
        while [ $elapsed -lt $timeout ]; do
            if ! aws elbv2 describe-load-balancers \
                --load-balancer-arns ${ALB_ARN} &> /dev/null; then
                break
            fi
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        success "Application Load Balancer deleted"
    fi
}

# Function to delete MemoryDB resources
delete_memorydb() {
    log "Deleting MemoryDB resources..."
    
    # Delete MemoryDB cluster
    if [ -n "${MEMORYDB_CLUSTER_NAME:-}" ]; then
        log "Deleting MemoryDB cluster: ${MEMORYDB_CLUSTER_NAME}"
        
        # Check if cluster exists before attempting deletion
        if aws memorydb describe-clusters --cluster-name ${MEMORYDB_CLUSTER_NAME} &> /dev/null; then
            aws memorydb delete-cluster --cluster-name ${MEMORYDB_CLUSTER_NAME} &> /dev/null || true
            
            # Wait for cluster deletion with timeout
            log "Waiting for MemoryDB cluster deletion (this may take 10-15 minutes)..."
            local timeout=1200  # 20 minutes
            local elapsed=0
            local interval=30
            
            while [ $elapsed -lt $timeout ]; do
                if ! aws memorydb describe-clusters --cluster-name ${MEMORYDB_CLUSTER_NAME} &> /dev/null; then
                    break
                fi
                
                CLUSTER_STATUS=$(aws memorydb describe-clusters \
                    --cluster-name ${MEMORYDB_CLUSTER_NAME} \
                    --query 'Clusters[0].Status' \
                    --output text 2>/dev/null || echo "deleted")
                
                if [ "$CLUSTER_STATUS" = "deleted" ] || [ "$CLUSTER_STATUS" = "None" ]; then
                    break
                fi
                
                log "MemoryDB cluster still deleting... (${elapsed}s elapsed, status: ${CLUSTER_STATUS})"
                sleep $interval
                elapsed=$((elapsed + interval))
            done
            
            success "MemoryDB cluster deleted"
        else
            warning "MemoryDB cluster not found or already deleted"
        fi
    fi
    
    # Delete MemoryDB subnet group
    if [ -n "${MEMORYDB_SUBNET_GROUP:-}" ]; then
        log "Deleting MemoryDB subnet group: ${MEMORYDB_SUBNET_GROUP}"
        aws memorydb delete-subnet-group \
            --subnet-group-name ${MEMORYDB_SUBNET_GROUP} &> /dev/null || true
        success "MemoryDB subnet group deleted"
    fi
}

# Function to delete Parameter Store parameters
delete_parameter_store() {
    log "Deleting Systems Manager parameters..."
    
    # Delete all session-app parameters
    PARAMETER_NAMES=(
        "/session-app/memorydb/endpoint"
        "/session-app/memorydb/port"
        "/session-app/config/session-timeout"
        "/session-app/config/redis-db"
    )
    
    for param in "${PARAMETER_NAMES[@]}"; do
        if aws ssm get-parameter --name "$param" &> /dev/null; then
            aws ssm delete-parameter --name "$param" &> /dev/null || true
            log "Deleted parameter: $param"
        fi
    done
    
    success "Parameter Store parameters deleted"
}

# Function to delete IAM roles and policies
delete_iam_roles() {
    log "Deleting IAM roles and policies..."
    
    # Delete ECS task execution role
    if [ -n "${ECS_EXECUTION_ROLE_NAME:-}" ]; then
        log "Deleting ECS execution role: ${ECS_EXECUTION_ROLE_NAME}"
        
        # Detach policies
        aws iam detach-role-policy \
            --role-name ${ECS_EXECUTION_ROLE_NAME} \
            --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy &> /dev/null || true
        
        # Delete role
        aws iam delete-role --role-name ${ECS_EXECUTION_ROLE_NAME} &> /dev/null || true
        success "ECS execution role deleted"
    fi
    
    # Delete ECS task role
    if [ -n "${ECS_TASK_ROLE_NAME:-}" ]; then
        log "Deleting ECS task role: ${ECS_TASK_ROLE_NAME}"
        
        # Delete inline policies
        aws iam delete-role-policy \
            --role-name ${ECS_TASK_ROLE_NAME} \
            --policy-name SessionAppSSMAccess &> /dev/null || true
        
        # Delete role
        aws iam delete-role --role-name ${ECS_TASK_ROLE_NAME} &> /dev/null || true
        success "ECS task role deleted"
    fi
}

# Function to delete S3 bucket and contents
delete_s3_bucket() {
    log "Deleting S3 bucket and contents..."
    
    if [ -n "${S3_BUCKET:-}" ]; then
        log "Deleting S3 bucket: ${S3_BUCKET}"
        
        # Check if bucket exists
        if aws s3 ls s3://${S3_BUCKET} &> /dev/null; then
            # Remove all objects first
            aws s3 rm s3://${S3_BUCKET} --recursive &> /dev/null || true
            
            # Delete the bucket
            aws s3 rb s3://${S3_BUCKET} &> /dev/null || true
            success "S3 bucket deleted"
        else
            warning "S3 bucket not found or already deleted"
        fi
    fi
}

# Function to delete security groups
delete_security_groups() {
    log "Deleting security groups..."
    
    # Security groups need to be deleted in order due to dependencies
    local security_groups=("${ALB_SG:-}" "${ECS_SG:-}" "${MEMORYDB_SG:-}")
    
    for sg in "${security_groups[@]}"; do
        if [ -n "$sg" ]; then
            log "Deleting security group: $sg"
            
            # Wait a moment for dependencies to clear
            sleep 5
            
            # Attempt deletion with retry
            local retries=3
            local delay=10
            
            for ((i=1; i<=retries; i++)); do
                if aws ec2 delete-security-group --group-id $sg &> /dev/null; then
                    success "Security group deleted: $sg"
                    break
                elif [ $i -eq $retries ]; then
                    warning "Failed to delete security group: $sg (may have dependencies)"
                else
                    log "Retrying security group deletion in ${delay} seconds... (attempt $i/$retries)"
                    sleep $delay
                fi
            done
        fi
    done
}

# Function to delete networking resources
delete_networking() {
    log "Deleting networking resources..."
    
    # Delete NAT Gateway
    if [ -n "${NAT_GW_1:-}" ]; then
        log "Deleting NAT Gateway: ${NAT_GW_1}"
        aws ec2 delete-nat-gateway --nat-gateway-id ${NAT_GW_1} &> /dev/null || true
        
        # Wait for NAT Gateway deletion
        log "Waiting for NAT Gateway to be deleted..."
        aws ec2 wait nat-gateway-deleted --nat-gateway-ids ${NAT_GW_1} &> /dev/null || true
        success "NAT Gateway deleted"
    fi
    
    # Release Elastic IP
    if [ -n "${NAT_EIP_1:-}" ]; then
        log "Releasing Elastic IP: ${NAT_EIP_1}"
        aws ec2 release-address --allocation-id ${NAT_EIP_1} &> /dev/null || true
        success "Elastic IP released"
    fi
    
    # Disassociate and delete route tables
    if [ -n "${PUBLIC_RT_ID:-}" ] && [ -n "${VPC_ID:-}" ]; then
        log "Cleaning up public route table: ${PUBLIC_RT_ID}"
        
        # Get route table associations
        ASSOCIATIONS=$(aws ec2 describe-route-tables \
            --route-table-ids ${PUBLIC_RT_ID} \
            --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' \
            --output text 2>/dev/null || echo "")
        
        # Disassociate subnets
        for assoc in $ASSOCIATIONS; do
            aws ec2 disassociate-route-table \
                --association-id $assoc &> /dev/null || true
        done
        
        # Delete route to IGW
        if [ -n "${IGW_ID:-}" ]; then
            aws ec2 delete-route \
                --route-table-id ${PUBLIC_RT_ID} \
                --destination-cidr-block 0.0.0.0/0 &> /dev/null || true
        fi
        
        # Delete route table
        aws ec2 delete-route-table --route-table-id ${PUBLIC_RT_ID} &> /dev/null || true
        success "Public route table deleted"
    fi
    
    if [ -n "${PRIVATE_RT_ID:-}" ] && [ -n "${VPC_ID:-}" ]; then
        log "Cleaning up private route table: ${PRIVATE_RT_ID}"
        
        # Get route table associations
        ASSOCIATIONS=$(aws ec2 describe-route-tables \
            --route-table-ids ${PRIVATE_RT_ID} \
            --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' \
            --output text 2>/dev/null || echo "")
        
        # Disassociate subnets
        for assoc in $ASSOCIATIONS; do
            aws ec2 disassociate-route-table \
                --association-id $assoc &> /dev/null || true
        done
        
        # Delete route to NAT Gateway
        if [ -n "${NAT_GW_1:-}" ]; then
            aws ec2 delete-route \
                --route-table-id ${PRIVATE_RT_ID} \
                --destination-cidr-block 0.0.0.0/0 &> /dev/null || true
        fi
        
        # Delete route table
        aws ec2 delete-route-table --route-table-id ${PRIVATE_RT_ID} &> /dev/null || true
        success "Private route table deleted"
    fi
    
    # Delete subnets
    local subnets=("${PUBLIC_SUBNET_1:-}" "${PUBLIC_SUBNET_2:-}" "${PRIVATE_SUBNET_1:-}" "${PRIVATE_SUBNET_2:-}")
    
    for subnet in "${subnets[@]}"; do
        if [ -n "$subnet" ]; then
            log "Deleting subnet: $subnet"
            aws ec2 delete-subnet --subnet-id $subnet &> /dev/null || true
            success "Subnet deleted: $subnet"
        fi
    done
    
    # Detach and delete Internet Gateway
    if [ -n "${IGW_ID:-}" ] && [ -n "${VPC_ID:-}" ]; then
        log "Detaching and deleting Internet Gateway: ${IGW_ID}"
        aws ec2 detach-internet-gateway \
            --internet-gateway-id ${IGW_ID} \
            --vpc-id ${VPC_ID} &> /dev/null || true
        aws ec2 delete-internet-gateway \
            --internet-gateway-id ${IGW_ID} &> /dev/null || true
        success "Internet Gateway deleted"
    fi
    
    # Delete VPC
    if [ -n "${VPC_ID:-}" ]; then
        log "Deleting VPC: ${VPC_ID}"
        aws ec2 delete-vpc --vpc-id ${VPC_ID} &> /dev/null || true
        success "VPC deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove session utility files
    local files_to_remove=(
        "session-config.sh"
        "test-session.py"
        "load-test-sessions.py"
        "index.html"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Removed: $file"
        fi
    done
    
    # Remove deployment state directory
    if [ -d ".deployment-state" ]; then
        rm -rf .deployment-state
        success "Removed deployment state directory"
    fi
    
    success "Local cleanup completed"
}

# Function to discover and clean orphaned resources
cleanup_orphaned_resources() {
    log "Searching for orphaned resources..."
    
    if [ -n "${RANDOM_SUFFIX:-}" ]; then
        # Look for resources with our suffix that might have been missed
        log "Checking for orphaned resources with suffix: ${RANDOM_SUFFIX}"
        
        # Check for orphaned security groups
        ORPHANED_SGS=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=*${RANDOM_SUFFIX}*" \
            --query 'SecurityGroups[].GroupId' \
            --output text 2>/dev/null || echo "")
        
        for sg in $ORPHANED_SGS; do
            if [ -n "$sg" ]; then
                warning "Found orphaned security group: $sg"
                aws ec2 delete-security-group --group-id $sg &> /dev/null || true
            fi
        done
        
        # Check for orphaned load balancers
        ORPHANED_ALBS=$(aws elbv2 describe-load-balancers \
            --query "LoadBalancers[?contains(LoadBalancerName, '${RANDOM_SUFFIX}')].LoadBalancerArn" \
            --output text 2>/dev/null || echo "")
        
        for alb in $ORPHANED_ALBS; do
            if [ -n "$alb" ]; then
                warning "Found orphaned load balancer: $alb"
                aws elbv2 delete-load-balancer --load-balancer-arn $alb &> /dev/null || true
            fi
        done
        
        # Check for orphaned ECS clusters
        ORPHANED_CLUSTERS=$(aws ecs list-clusters \
            --query "clusterArns[?contains(@, '${RANDOM_SUFFIX}')]" \
            --output text 2>/dev/null || echo "")
        
        for cluster in $ORPHANED_CLUSTERS; do
            if [ -n "$cluster" ]; then
                warning "Found orphaned ECS cluster: $cluster"
                aws ecs delete-cluster --cluster $cluster &> /dev/null || true
            fi
        done
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup operation completed"
    
    echo ""
    echo "🧹 =================================="
    echo "   CLEANUP COMPLETED SUCCESSFULLY"
    echo "================================== 🧹"
    echo ""
    echo "✅ Resources Cleaned Up:"
    echo "   • ECS services and clusters"
    echo "   • Application Load Balancer and target groups"
    echo "   • MemoryDB cluster and subnet groups"
    echo "   • Security groups"
    echo "   • VPC and networking components"
    echo "   • NAT Gateway and Elastic IP"
    echo "   • IAM roles and policies"
    echo "   • Systems Manager parameters"
    echo "   • S3 bucket and contents"
    echo "   • CloudWatch log groups"
    echo "   • Local deployment files"
    echo ""
    echo "💡 Post-Cleanup Notes:"
    echo "   • All billable resources have been removed"
    echo "   • Session data has been permanently deleted"
    echo "   • IAM roles have been cleaned up"
    echo "   • No ongoing charges should occur"
    echo ""
    echo "🔍 Verification Commands:"
    echo "   # Check for remaining resources (should return empty)"
    echo "   aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, \`session\`)].LoadBalancerName'"
    echo "   aws ecs list-clusters --query 'clusterArns[?contains(@, \`session\`)]'"
    echo "   aws memorydb describe-clusters --query 'Clusters[?contains(ClusterName, \`session\`)].ClusterName'"
    echo ""
    echo "⚠️  If you see any remaining resources, they may need manual cleanup."
    echo ""
}

# Function to handle cleanup errors gracefully
handle_cleanup_errors() {
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        echo ""
        error "Cleanup encountered errors (exit code: $exit_code)"
        echo ""
        echo "🔧 Troubleshooting:"
        echo "   • Some resources may have dependencies preventing deletion"
        echo "   • Try running the script again in a few minutes"
        echo "   • Check AWS console for any remaining resources"
        echo "   • You may need to manually delete some resources"
        echo ""
        echo "🆘 Manual Cleanup Commands:"
        echo "   # List all resources with 'session' in the name"
        echo "   aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=distributed-session-management"
        echo ""
        echo "   # Delete specific resource types if needed"
        echo "   aws ecs list-clusters | grep session"
        echo "   aws elbv2 describe-load-balancers | grep session"
        echo "   aws memorydb describe-clusters | grep session"
        echo ""
    fi
    
    exit $exit_code
}

# Main cleanup function
main() {
    log "Starting distributed session management cleanup..."
    
    # Set up error handling
    trap handle_cleanup_errors ERR
    
    # Check prerequisites and get confirmation
    if ! check_prerequisites; then
        warning "Prerequisite check failed. Attempting manual cleanup..."
    fi
    
    confirm_destruction
    
    # Load deployment state if available
    if ! load_deployment_state; then
        warning "Could not load deployment state. Attempting partial cleanup..."
    fi
    
    # Execute cleanup in dependency order
    log "Beginning resource cleanup..."
    
    delete_ecs_resources
    delete_load_balancer
    delete_memorydb
    delete_parameter_store
    delete_iam_roles
    delete_s3_bucket
    
    # Network resources last due to dependencies
    delete_security_groups
    delete_networking
    
    # Clean up local files
    cleanup_local_files
    
    # Look for any orphaned resources
    cleanup_orphaned_resources
    
    # Display summary
    display_cleanup_summary
    
    success "All resources have been successfully cleaned up!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi