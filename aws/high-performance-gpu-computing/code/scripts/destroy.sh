#!/bin/bash

# GPU-Accelerated Workloads Cleanup Script
# This script removes all AWS resources created for GPU computing workloads
# Recipe: High-Performance GPU Computing Workloads

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Check if force flag is provided
FORCE_CLEANUP=false
if [ "$1" = "--force" ]; then
    FORCE_CLEANUP=true
    log_warning "Force cleanup mode enabled - skipping confirmations"
fi

# Load environment variables from deployment
load_environment() {
    if [ -f ".gpu_deployment_vars" ]; then
        log_info "Loading deployment variables..."
        source .gpu_deployment_vars
        log_success "Environment variables loaded"
    else
        log_warning "No deployment variables file found. Some cleanup may be manual."
        log_warning "Attempting to find resources by tags..."
    fi
}

# Confirmation prompt (unless force mode)
confirm_cleanup() {
    if [ "$FORCE_CLEANUP" = "false" ]; then
        echo "=============================================="
        echo "GPU-Accelerated Workloads Cleanup Script"
        echo "=============================================="
        echo
        echo -e "${RED}WARNING: This will permanently delete all GPU workload resources!${NC}"
        echo
        echo "Resources to be deleted:"
        echo "- EC2 instances (P4 and G4)"
        echo "- Spot Fleet requests"
        echo "- Security groups"
        echo "- Key pairs"
        echo "- IAM roles and instance profiles"
        echo "- SNS topics and subscriptions"
        echo "- CloudWatch dashboards and alarms"
        echo "- Local files"
        echo
        read -p "Are you sure you want to continue? (yes/no): " confirmation
        
        if [ "$confirmation" != "yes" ]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    log_info "Starting cleanup process..."
}

# Terminate EC2 instances
terminate_instances() {
    log_info "Terminating EC2 instances..."
    
    # Terminate P4 instance if exists
    if [ ! -z "$P4_INSTANCE_ID" ]; then
        log_info "Terminating P4 instance: $P4_INSTANCE_ID"
        if aws ec2 terminate-instances --instance-ids ${P4_INSTANCE_ID} &> /dev/null; then
            # Wait for termination with timeout
            log_info "Waiting for P4 instance to terminate..."
            timeout 300 aws ec2 wait instance-terminated --instance-ids ${P4_INSTANCE_ID} || {
                log_warning "Timeout waiting for P4 instance termination. It may still be terminating."
            }
            log_success "P4 instance terminated"
        else
            log_warning "Failed to terminate P4 instance $P4_INSTANCE_ID (may already be terminated)"
        fi
    fi
    
    # Terminate G4 instance if exists
    if [ ! -z "$G4_INSTANCE_ID" ]; then
        log_info "Terminating G4 instance: $G4_INSTANCE_ID"
        if aws ec2 terminate-instances --instance-ids ${G4_INSTANCE_ID} &> /dev/null; then
            # Wait for termination with timeout
            log_info "Waiting for G4 instance to terminate..."
            timeout 300 aws ec2 wait instance-terminated --instance-ids ${G4_INSTANCE_ID} || {
                log_warning "Timeout waiting for G4 instance termination. It may still be terminating."
            }
            log_success "G4 instance terminated"
        else
            log_warning "Failed to terminate G4 instance $G4_INSTANCE_ID (may already be terminated)"
        fi
    fi
    
    # Find and terminate any remaining GPU workload instances by tag
    log_info "Searching for additional GPU workload instances..."
    REMAINING_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:Purpose,Values=GPU-Workload" \
        "Name=instance-state-name,Values=running,stopped,stopping" \
        --query "Reservations[*].Instances[*].InstanceId" \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$REMAINING_INSTANCES" ] && [ "$REMAINING_INSTANCES" != "None" ]; then
        log_info "Found additional instances to terminate: $REMAINING_INSTANCES"
        aws ec2 terminate-instances --instance-ids $REMAINING_INSTANCES
        log_success "Additional instances terminated"
    fi
}

# Cancel Spot Fleet requests
cancel_spot_fleet() {
    log_info "Cancelling Spot Fleet requests..."
    
    if [ ! -z "$SPOT_FLEET_ID" ]; then
        log_info "Cancelling Spot Fleet: $SPOT_FLEET_ID"
        if aws ec2 cancel-spot-fleet-requests \
            --spot-fleet-request-ids ${SPOT_FLEET_ID} \
            --terminate-instances &> /dev/null; then
            log_success "Spot Fleet cancelled"
        else
            log_warning "Failed to cancel Spot Fleet $SPOT_FLEET_ID (may already be cancelled)"
        fi
    fi
    
    # Find any remaining spot fleet requests by name pattern
    log_info "Searching for additional Spot Fleet requests..."
    if [ ! -z "$GPU_FLEET_NAME" ]; then
        REMAINING_FLEETS=$(aws ec2 describe-spot-fleet-requests \
            --query "SpotFleetRequestConfigs[?SpotFleetRequestState=='active'].SpotFleetRequestId" \
            --output text 2>/dev/null || echo "")
        
        if [ ! -z "$REMAINING_FLEETS" ] && [ "$REMAINING_FLEETS" != "None" ]; then
            log_info "Found additional Spot Fleets to cancel: $REMAINING_FLEETS"
            aws ec2 cancel-spot-fleet-requests \
                --spot-fleet-request-ids $REMAINING_FLEETS \
                --terminate-instances
            log_success "Additional Spot Fleets cancelled"
        fi
    fi
}

# Delete CloudWatch resources
delete_cloudwatch_resources() {
    log_info "Removing CloudWatch resources..."
    
    # Delete dashboard
    if aws cloudwatch delete-dashboards \
        --dashboard-names "GPU-Workload-Monitoring" &> /dev/null; then
        log_success "CloudWatch dashboard deleted"
    else
        log_warning "CloudWatch dashboard not found or already deleted"
    fi
    
    # Delete alarms
    ALARMS=("GPU-High-Temperature" "GPU-Low-Utilization")
    for alarm in "${ALARMS[@]}"; do
        if aws cloudwatch delete-alarms --alarm-names "$alarm" &> /dev/null; then
            log_success "CloudWatch alarm '$alarm' deleted"
        else
            log_warning "CloudWatch alarm '$alarm' not found or already deleted"
        fi
    done
}

# Delete security group
delete_security_group() {
    log_info "Removing security group..."
    
    if [ ! -z "$SECURITY_GROUP_ID" ]; then
        # Wait for instances to be fully terminated before deleting security group
        log_info "Waiting for instances to fully terminate before deleting security group..."
        sleep 30
        
        if aws ec2 delete-security-group --group-id ${SECURITY_GROUP_ID} &> /dev/null; then
            log_success "Security group deleted: $SECURITY_GROUP_ID"
        else
            log_warning "Failed to delete security group $SECURITY_GROUP_ID (may have dependencies)"
        fi
    fi
    
    # Find security group by name if ID not available
    if [ ! -z "$GPU_SECURITY_GROUP" ] && [ -z "$SECURITY_GROUP_ID" ]; then
        SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=${GPU_SECURITY_GROUP}" \
            --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "")
        
        if [ ! -z "$SECURITY_GROUP_ID" ] && [ "$SECURITY_GROUP_ID" != "None" ]; then
            sleep 30  # Wait for dependencies
            if aws ec2 delete-security-group --group-id ${SECURITY_GROUP_ID} &> /dev/null; then
                log_success "Security group deleted: $SECURITY_GROUP_ID"
            else
                log_warning "Failed to delete security group $SECURITY_GROUP_ID"
            fi
        fi
    fi
}

# Delete key pair
delete_key_pair() {
    log_info "Removing key pair..."
    
    if [ ! -z "$GPU_KEYPAIR_NAME" ]; then
        if aws ec2 delete-key-pair --key-name ${GPU_KEYPAIR_NAME} &> /dev/null; then
            log_success "Key pair deleted: $GPU_KEYPAIR_NAME"
        else
            log_warning "Failed to delete key pair $GPU_KEYPAIR_NAME (may already be deleted)"
        fi
        
        # Remove local key file
        if [ -f "${GPU_KEYPAIR_NAME}.pem" ]; then
            rm -f ${GPU_KEYPAIR_NAME}.pem
            log_success "Local key file removed"
        fi
    fi
}

# Delete IAM resources
delete_iam_resources() {
    log_info "Removing IAM resources..."
    
    if [ ! -z "$GPU_IAM_ROLE" ]; then
        # Remove role from instance profile
        if aws iam remove-role-from-instance-profile \
            --instance-profile-name ${GPU_IAM_ROLE} \
            --role-name ${GPU_IAM_ROLE} &> /dev/null; then
            log_success "Role removed from instance profile"
        else
            log_warning "Failed to remove role from instance profile (may already be removed)"
        fi
        
        # Delete instance profile
        if aws iam delete-instance-profile \
            --instance-profile-name ${GPU_IAM_ROLE} &> /dev/null; then
            log_success "Instance profile deleted"
        else
            log_warning "Failed to delete instance profile (may already be deleted)"
        fi
        
        # Detach policies
        POLICIES=(
            "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
            "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        )
        
        for policy in "${POLICIES[@]}"; do
            if aws iam detach-role-policy \
                --role-name ${GPU_IAM_ROLE} \
                --policy-arn "$policy" &> /dev/null; then
                log_success "Policy detached: $(basename $policy)"
            else
                log_warning "Failed to detach policy: $(basename $policy)"
            fi
        done
        
        # Delete IAM role
        if aws iam delete-role --role-name ${GPU_IAM_ROLE} &> /dev/null; then
            log_success "IAM role deleted: $GPU_IAM_ROLE"
        else
            log_warning "Failed to delete IAM role $GPU_IAM_ROLE"
        fi
    fi
}

# Delete SNS topic
delete_sns_topic() {
    log_info "Removing SNS topic..."
    
    if [ ! -z "$GPU_SNS_ARN" ]; then
        if aws sns delete-topic --topic-arn ${GPU_SNS_ARN} &> /dev/null; then
            log_success "SNS topic deleted: $GPU_SNS_ARN"
        else
            log_warning "Failed to delete SNS topic $GPU_SNS_ARN"
        fi
    fi
    
    # Find SNS topic by name if ARN not available
    if [ ! -z "$GPU_SNS_TOPIC" ] && [ -z "$GPU_SNS_ARN" ]; then
        SNS_ARN=$(aws sns list-topics \
            --query "Topics[?contains(TopicArn, '${GPU_SNS_TOPIC}')].TopicArn" \
            --output text 2>/dev/null || echo "")
        
        if [ ! -z "$SNS_ARN" ] && [ "$SNS_ARN" != "None" ]; then
            if aws sns delete-topic --topic-arn ${SNS_ARN} &> /dev/null; then
                log_success "SNS topic deleted: $SNS_ARN"
            else
                log_warning "Failed to delete SNS topic $SNS_ARN"
            fi
        fi
    fi
}

# Remove local files
remove_local_files() {
    log_info "Removing local files..."
    
    # List of files to remove
    FILES_TO_REMOVE=(
        ".gpu_deployment_vars"
        "gpu-trust-policy.json"
        "gpu-userdata.sh"
        "g4-spot-fleet-config.json"
        "gpu-dashboard.json"
        "monitor-gpu.py"
        "cost-optimizer.py"
        "gpu-test.py"
    )
    
    # Remove key file if variable is set
    if [ ! -z "$GPU_KEYPAIR_NAME" ]; then
        FILES_TO_REMOVE+=("${GPU_KEYPAIR_NAME}.pem")
    fi
    
    for file in "${FILES_TO_REMOVE[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_success "Removed file: $file"
        fi
    done
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Check for remaining instances
    REMAINING_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:Purpose,Values=GPU-Workload" \
        "Name=instance-state-name,Values=running,stopped,stopping" \
        --query "Reservations[*].Instances[*].InstanceId" \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$REMAINING_INSTANCES" ] && [ "$REMAINING_INSTANCES" != "None" ]; then
        log_warning "Some instances may still be terminating: $REMAINING_INSTANCES"
    else
        log_success "All GPU instances cleaned up"
    fi
    
    # Check for remaining security groups
    if [ ! -z "$GPU_SECURITY_GROUP" ]; then
        REMAINING_SG=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=${GPU_SECURITY_GROUP}" \
            --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "")
        
        if [ ! -z "$REMAINING_SG" ] && [ "$REMAINING_SG" != "None" ]; then
            log_warning "Security group still exists (may have dependencies): $REMAINING_SG"
        else
            log_success "Security group cleaned up"
        fi
    fi
}

# Display cleanup summary
display_summary() {
    echo
    log_info "Cleanup Summary"
    echo "==============="
    echo -e "${GREEN}✅ GPU Infrastructure Cleanup Completed${NC}"
    echo
    echo "Cleaned up resources:"
    echo "- EC2 instances (P4 and G4)"
    echo "- Spot Fleet requests"
    echo "- Security groups"
    echo "- Key pairs and local files"
    echo "- IAM roles and instance profiles"
    echo "- SNS topics and subscriptions"
    echo "- CloudWatch dashboards and alarms"
    echo
    echo -e "${YELLOW}Note: Some resources may take a few minutes to fully delete.${NC}"
    echo -e "${YELLOW}Check the AWS console if you need to verify complete removal.${NC}"
    echo
    log_success "All cleanup operations completed!"
}

# Main cleanup function
main() {
    echo "=============================================="
    echo "GPU-Accelerated Workloads Cleanup Script"
    echo "=============================================="
    echo
    
    load_environment
    confirm_cleanup
    
    # Execute cleanup steps
    terminate_instances
    cancel_spot_fleet
    delete_cloudwatch_resources
    delete_security_group
    delete_key_pair
    delete_iam_resources
    delete_sns_topic
    remove_local_files
    verify_cleanup
    display_summary
}

# Error handling for cleanup
cleanup_error_handler() {
    log_error "An error occurred during cleanup. Some resources may need manual removal."
    log_info "Check the AWS console for any remaining resources."
    exit 1
}

# Set trap for error handling
trap cleanup_error_handler ERR

# Run main function with all arguments
main "$@"