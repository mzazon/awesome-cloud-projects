#!/bin/bash

# Predictive Scaling EC2 Auto Scaling with Machine Learning - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    log "${RED}Cleanup failed at ${TIMESTAMP}${NC}"
    exit 1
}

# Success message function
success() {
    log "${GREEN}✅ ${1}${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️  ${1}${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️  ${1}${NC}"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed."
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials are not configured."
    fi
    
    # Get AWS region
    export AWS_REGION=$(aws configure get region || echo "us-east-1")
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, using default: us-east-1"
    fi
    
    info "Using AWS region: ${AWS_REGION}"
    success "Prerequisites check completed"
}

# Confirmation prompt
confirm_deletion() {
    log "${YELLOW}========================================${NC}"
    log "${YELLOW}WARNING: This will delete ALL resources${NC}"
    log "${YELLOW}created by the predictive scaling demo!${NC}"
    log "${YELLOW}========================================${NC}"
    log ""
    log "Resources to be deleted:"
    log "- Auto Scaling Group (PredictiveScalingASG)"
    log "- Launch Template (PredictiveScalingTemplate)"
    log "- CloudWatch Dashboard (PredictiveScalingDashboard)"
    log "- Security Group (PredictiveScalingSG)"
    log "- VPC and all networking components"
    log "- IAM Role and Instance Profile"
    log ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " CONFIRMATION
    
    if [[ "${CONFIRMATION}" != "yes" ]]; then
        log "${BLUE}Cleanup cancelled by user.${NC}"
        exit 0
    fi
    
    info "User confirmed deletion. Proceeding with cleanup..."
}

# Get resource IDs from deployment info or AWS
get_resource_ids() {
    info "Retrieving resource identifiers..."
    
    # Try to load from deployment info file first
    if [[ -f "${SCRIPT_DIR}/deployment-info.txt" ]]; then
        info "Loading resource IDs from deployment-info.txt"
        export VPC_ID=$(grep "VPC ID:" "${SCRIPT_DIR}/deployment-info.txt" | cut -d' ' -f3 || echo "")
        export SG_ID=$(grep "Security Group ID:" "${SCRIPT_DIR}/deployment-info.txt" | cut -d' ' -f4 || echo "")
        export LAUNCH_TEMPLATE_ID=$(grep "Launch Template ID:" "${SCRIPT_DIR}/deployment-info.txt" | cut -d' ' -f4 || echo "")
        export IGW_ID=$(grep "Internet Gateway ID:" "${SCRIPT_DIR}/deployment-info.txt" | cut -d' ' -f4 || echo "")
        export RTB_ID=$(grep "Route Table ID:" "${SCRIPT_DIR}/deployment-info.txt" | cut -d' ' -f4 || echo "")
    fi
    
    # Fallback to AWS CLI queries if not found in deployment info
    if [[ -z "${VPC_ID}" ]]; then
        export VPC_ID=$(aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=PredictiveScalingVPC" \
            --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")
    fi
    
    if [[ -z "${SG_ID}" ]]; then
        export SG_ID=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=PredictiveScalingSG" \
            --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "None")
    fi
    
    if [[ -z "${LAUNCH_TEMPLATE_ID}" ]]; then
        export LAUNCH_TEMPLATE_ID=$(aws ec2 describe-launch-templates \
            --filters "Name=launch-template-name,Values=PredictiveScalingTemplate" \
            --query "LaunchTemplates[0].LaunchTemplateId" --output text 2>/dev/null || echo "None")
    fi
    
    if [[ -z "${IGW_ID}" ]]; then
        export IGW_ID=$(aws ec2 describe-internet-gateways \
            --filters "Name=tag:Name,Values=PredictiveScalingIGW" \
            --query "InternetGateways[0].InternetGatewayId" --output text 2>/dev/null || echo "None")
    fi
    
    if [[ -z "${RTB_ID}" ]]; then
        export RTB_ID=$(aws ec2 describe-route-tables \
            --filters "Name=tag:Name,Values=PredictiveScalingRTB" \
            --query "RouteTables[0].RouteTableId" --output text 2>/dev/null || echo "None")
    fi
    
    # Get subnet IDs if VPC exists
    if [[ "${VPC_ID}" != "None" ]] && [[ -n "${VPC_ID}" ]]; then
        export SUBNET_IDS=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query "Subnets[*].SubnetId" --output text 2>/dev/null || echo "")
    fi
    
    success "Resource identifiers retrieved"
}

# Delete scaling policies
delete_scaling_policies() {
    info "Deleting scaling policies..."
    
    # Check if Auto Scaling Group exists
    ASG_EXISTS=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names PredictiveScalingASG \
        --query "AutoScalingGroups[0].AutoScalingGroupName" --output text 2>/dev/null || echo "None")
    
    if [[ "${ASG_EXISTS}" == "None" ]]; then
        warning "Auto Scaling Group does not exist, skipping policy deletion"
        return 0
    fi
    
    # Delete predictive scaling policy
    aws autoscaling delete-policy \
        --auto-scaling-group-name PredictiveScalingASG \
        --policy-name PredictiveScalingPolicy 2>/dev/null || \
        warning "Predictive scaling policy may not exist"
    
    # Delete target tracking policy
    aws autoscaling delete-policy \
        --auto-scaling-group-name PredictiveScalingASG \
        --policy-name CPUTargetTracking 2>/dev/null || \
        warning "Target tracking policy may not exist"
    
    success "Scaling policies deleted"
}

# Delete Auto Scaling Group
delete_auto_scaling_group() {
    info "Deleting Auto Scaling Group..."
    
    # Check if Auto Scaling Group exists
    ASG_EXISTS=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names PredictiveScalingASG \
        --query "AutoScalingGroups[0].AutoScalingGroupName" --output text 2>/dev/null || echo "None")
    
    if [[ "${ASG_EXISTS}" == "None" ]]; then
        warning "Auto Scaling Group does not exist"
        return 0
    fi
    
    # Scale down to 0 instances
    info "Scaling down Auto Scaling Group to 0 instances..."
    aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name PredictiveScalingASG \
        --min-size 0 --max-size 0 --desired-capacity 0 || \
        warning "Failed to scale down Auto Scaling Group"
    
    # Wait for instances to terminate
    info "Waiting for instances to terminate..."
    local timeout=300
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        INSTANCE_COUNT=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names PredictiveScalingASG \
            --query "AutoScalingGroups[0].Instances | length(@)" --output text 2>/dev/null || echo "0")
        
        if [[ "${INSTANCE_COUNT}" == "0" ]]; then
            break
        fi
        
        info "Waiting for ${INSTANCE_COUNT} instances to terminate... (${elapsed}s elapsed)"
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        warning "Timeout waiting for instances to terminate. Forcing deletion."
    fi
    
    # Delete Auto Scaling Group
    aws autoscaling delete-auto-scaling-group \
        --auto-scaling-group-name PredictiveScalingASG \
        --force-delete || error_exit "Failed to delete Auto Scaling Group"
    
    success "Auto Scaling Group deleted"
}

# Delete launch template
delete_launch_template() {
    info "Deleting launch template..."
    
    if [[ "${LAUNCH_TEMPLATE_ID}" == "None" ]] || [[ -z "${LAUNCH_TEMPLATE_ID}" ]]; then
        warning "Launch template not found"
        return 0
    fi
    
    aws ec2 delete-launch-template \
        --launch-template-id "${LAUNCH_TEMPLATE_ID}" || \
        warning "Failed to delete launch template ${LAUNCH_TEMPLATE_ID}"
    
    success "Launch template deleted: ${LAUNCH_TEMPLATE_ID}"
}

# Delete CloudWatch Dashboard
delete_dashboard() {
    info "Deleting CloudWatch Dashboard..."
    
    aws cloudwatch delete-dashboards \
        --dashboard-names "PredictiveScalingDashboard" || \
        warning "CloudWatch dashboard may not exist"
    
    success "CloudWatch dashboard deleted"
}

# Delete IAM resources
delete_iam_resources() {
    info "Deleting IAM resources..."
    
    # Remove role from instance profile
    aws iam remove-role-from-instance-profile \
        --instance-profile-name PredictiveScalingProfile \
        --role-name PredictiveScalingEC2Role 2>/dev/null || \
        warning "Role may not be in instance profile"
    
    # Delete instance profile
    aws iam delete-instance-profile \
        --instance-profile-name PredictiveScalingProfile 2>/dev/null || \
        warning "Instance profile may not exist"
    
    # Detach policies from role
    aws iam detach-role-policy \
        --role-name PredictiveScalingEC2Role \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy 2>/dev/null || \
        warning "Policy may not be attached"
    
    # Delete IAM role
    aws iam delete-role \
        --role-name PredictiveScalingEC2Role 2>/dev/null || \
        warning "IAM role may not exist"
    
    success "IAM resources deleted"
}

# Delete security group
delete_security_group() {
    info "Deleting security group..."
    
    if [[ "${SG_ID}" == "None" ]] || [[ -z "${SG_ID}" ]]; then
        warning "Security group not found"
        return 0
    fi
    
    # Wait a bit for any remaining dependencies
    sleep 10
    
    aws ec2 delete-security-group --group-id "${SG_ID}" || \
        warning "Failed to delete security group ${SG_ID}. It may still have dependencies."
    
    success "Security group deleted: ${SG_ID}"
}

# Delete networking components
delete_networking() {
    info "Deleting networking components..."
    
    if [[ "${VPC_ID}" == "None" ]] || [[ -z "${VPC_ID}" ]]; then
        warning "VPC not found"
        return 0
    fi
    
    # Delete route table associations first
    if [[ "${RTB_ID}" != "None" ]] && [[ -n "${RTB_ID}" ]]; then
        info "Removing route table associations..."
        for RT_ASSOC in $(aws ec2 describe-route-tables \
            --route-table-ids "${RTB_ID}" \
            --query "RouteTables[0].Associations[?Main==\`false\`].RouteTableAssociationId" \
            --output text 2>/dev/null || echo ""); do
            if [[ -n "${RT_ASSOC}" ]] && [[ "${RT_ASSOC}" != "None" ]]; then
                aws ec2 disassociate-route-table --association-id "${RT_ASSOC}" || \
                    warning "Failed to disassociate route table ${RT_ASSOC}"
            fi
        done
        
        # Delete custom route table
        aws ec2 delete-route-table --route-table-id "${RTB_ID}" || \
            warning "Failed to delete route table ${RTB_ID}"
    fi
    
    # Detach and delete internet gateway
    if [[ "${IGW_ID}" != "None" ]] && [[ -n "${IGW_ID}" ]]; then
        info "Detaching and deleting internet gateway..."
        aws ec2 detach-internet-gateway \
            --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}" || \
            warning "Failed to detach internet gateway"
        
        aws ec2 delete-internet-gateway --internet-gateway-id "${IGW_ID}" || \
            warning "Failed to delete internet gateway ${IGW_ID}"
    fi
    
    # Delete subnets
    if [[ -n "${SUBNET_IDS}" ]]; then
        info "Deleting subnets..."
        for SUBNET_ID in ${SUBNET_IDS}; do
            if [[ -n "${SUBNET_ID}" ]] && [[ "${SUBNET_ID}" != "None" ]]; then
                aws ec2 delete-subnet --subnet-id "${SUBNET_ID}" || \
                    warning "Failed to delete subnet ${SUBNET_ID}"
            fi
        done
    fi
    
    # Delete VPC
    info "Deleting VPC..."
    aws ec2 delete-vpc --vpc-id "${VPC_ID}" || \
        warning "Failed to delete VPC ${VPC_ID}"
    
    success "Networking components deleted"
}

# Clean up temporary files
cleanup_files() {
    info "Cleaning up temporary files..."
    
    # Remove generated files
    rm -f "${SCRIPT_DIR}/trust-policy.json" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/user-data.txt" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/dashboard.json" 2>/dev/null || true
    rm -f "${SCRIPT_DIR}/predictive-scaling-config.json" 2>/dev/null || true
    
    # Optionally remove deployment info (comment out if you want to keep it)
    # rm -f "${SCRIPT_DIR}/deployment-info.txt" 2>/dev/null || true
    
    success "Temporary files cleaned up"
}

# Validate cleanup
validate_cleanup() {
    info "Validating cleanup..."
    
    local cleanup_issues=0
    
    # Check Auto Scaling Group
    ASG_EXISTS=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names PredictiveScalingASG \
        --query "AutoScalingGroups[0].AutoScalingGroupName" --output text 2>/dev/null || echo "None")
    
    if [[ "${ASG_EXISTS}" != "None" ]]; then
        warning "Auto Scaling Group still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check VPC
    if [[ "${VPC_ID}" != "None" ]] && [[ -n "${VPC_ID}" ]]; then
        VPC_EXISTS=$(aws ec2 describe-vpcs \
            --vpc-ids "${VPC_ID}" \
            --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "None")
        
        if [[ "${VPC_EXISTS}" != "None" ]]; then
            warning "VPC still exists: ${VPC_ID}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check Launch Template
    if [[ "${LAUNCH_TEMPLATE_ID}" != "None" ]] && [[ -n "${LAUNCH_TEMPLATE_ID}" ]]; then
        LT_EXISTS=$(aws ec2 describe-launch-templates \
            --launch-template-ids "${LAUNCH_TEMPLATE_ID}" \
            --query "LaunchTemplates[0].LaunchTemplateId" --output text 2>/dev/null || echo "None")
        
        if [[ "${LT_EXISTS}" != "None" ]]; then
            warning "Launch Template still exists: ${LAUNCH_TEMPLATE_ID}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    if [[ $cleanup_issues -gt 0 ]]; then
        warning "Some resources may still exist. Check AWS console manually."
    else
        success "All resources have been successfully deleted"
    fi
}

# Main cleanup function
main() {
    log "${BLUE}Starting Predictive Scaling cleanup at ${TIMESTAMP}${NC}"
    
    check_prerequisites
    confirm_deletion
    get_resource_ids
    delete_scaling_policies
    delete_auto_scaling_group
    delete_launch_template
    delete_dashboard
    delete_iam_resources
    delete_security_group
    delete_networking
    cleanup_files
    validate_cleanup
    
    log ""
    log "${GREEN}========================================${NC}"
    log "${GREEN}Cleanup completed successfully! 🎉${NC}"
    log "${GREEN}========================================${NC}"
    log ""
    log "${BLUE}All Predictive Scaling demo resources have been removed.${NC}"
    log ""
    log "${YELLOW}Note: Please verify in the AWS console that all resources${NC}"
    log "${YELLOW}have been deleted to avoid unexpected charges.${NC}"
    log ""
}

# Cleanup function for script interruption
cleanup_on_exit() {
    warning "Script interrupted. Some resources may still exist."
    log "Check the AWS console manually and delete any remaining resources."
}

# Set trap for cleanup
trap cleanup_on_exit EXIT

# Run main function
main "$@"