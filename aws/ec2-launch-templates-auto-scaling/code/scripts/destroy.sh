#!/bin/bash

# EC2 Launch Templates with Auto Scaling - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI credentials
check_aws_credentials() {
    log_info "Checking AWS CLI credentials..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI credentials not configured or invalid"
        log_error "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
    log_success "AWS credentials verified"
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check AWS credentials
    check_aws_credentials
    
    log_success "All prerequisites validated"
}

# Function to load deployment state
load_state() {
    local state_file="/tmp/ec2-asg-deployment-state.env"
    
    if [[ -f "${state_file}" ]]; then
        log_info "Loading deployment state from ${state_file}"
        # shellcheck source=/dev/null
        source "${state_file}"
    else
        log_warning "No state file found. You'll need to provide resource names manually"
        return 1
    fi
}

# Function to prompt for manual input if state not found
prompt_manual_input() {
    log_info "Please provide the resource names to clean up:"
    
    read -p "Auto Scaling Group Name (optional): " ASG_NAME
    read -p "Launch Template Name (optional): " LAUNCH_TEMPLATE_NAME
    read -p "Security Group Name (optional): " SECURITY_GROUP_NAME
    
    # Set AWS region if not set
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
    fi
    
    # Export variables for use in other functions
    export ASG_NAME LAUNCH_TEMPLATE_NAME SECURITY_GROUP_NAME
}

# Function to confirm cleanup action
confirm_cleanup() {
    echo ""
    log_warning "WARNING: This will permanently delete the following resources:"
    
    if [[ -n "${ASG_NAME:-}" ]]; then
        echo "  - Auto Scaling Group: ${ASG_NAME}"
    fi
    if [[ -n "${LAUNCH_TEMPLATE_NAME:-}" ]]; then
        echo "  - Launch Template: ${LAUNCH_TEMPLATE_NAME}"
    fi
    if [[ -n "${SECURITY_GROUP_NAME:-}" ]]; then
        echo "  - Security Group: ${SECURITY_GROUP_NAME}"
    fi
    
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to get Auto Scaling Group instances
get_asg_instances() {
    if [[ -z "${ASG_NAME:-}" ]]; then
        return 0
    fi
    
    log_info "Getting instances from Auto Scaling Group ${ASG_NAME}..."
    
    # Check if ASG exists
    if ! aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${ASG_NAME}" >/dev/null 2>&1; then
        log_warning "Auto Scaling Group ${ASG_NAME} not found"
        return 0
    fi
    
    # Get instance IDs
    INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "${ASG_NAME}" \
        --query 'AutoScalingGroups[0].Instances[].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${INSTANCE_IDS}" && "${INSTANCE_IDS}" != "None" ]]; then
        log_info "Found instances: ${INSTANCE_IDS}"
        export INSTANCE_IDS
    else
        log_info "No instances found in Auto Scaling Group"
        export INSTANCE_IDS=""
    fi
}

# Function to delete Auto Scaling Group
delete_auto_scaling_group() {
    if [[ -z "${ASG_NAME:-}" ]]; then
        log_info "No Auto Scaling Group specified, skipping..."
        return 0
    fi
    
    log_info "Deleting Auto Scaling Group ${ASG_NAME}..."
    
    # Check if ASG exists
    if ! aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${ASG_NAME}" >/dev/null 2>&1; then
        log_warning "Auto Scaling Group ${ASG_NAME} not found, skipping..."
        return 0
    fi
    
    # Set desired capacity to 0 and wait for instance termination
    log_info "Scaling down Auto Scaling Group to 0 instances..."
    aws autoscaling update-auto-scaling-group \
        --auto-scaling-group-name "${ASG_NAME}" \
        --min-size 0 --max-size 0 --desired-capacity 0 >/dev/null
    
    # Wait for instances to terminate (with timeout)
    log_info "Waiting for instances to terminate (this may take a few minutes)..."
    local timeout=300  # 5 minutes timeout
    local elapsed=0
    local check_interval=15
    
    while [[ ${elapsed} -lt ${timeout} ]]; do
        local current_instances
        current_instances=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "${ASG_NAME}" \
            --query 'AutoScalingGroups[0].Instances | length(@)' \
            --output text 2>/dev/null || echo "0")
        
        if [[ "${current_instances}" == "0" ]]; then
            log_success "All instances terminated"
            break
        fi
        
        log_info "Still waiting for ${current_instances} instances to terminate..."
        sleep ${check_interval}
        elapsed=$((elapsed + check_interval))
    done
    
    if [[ ${elapsed} -ge ${timeout} ]]; then
        log_warning "Timeout waiting for instances to terminate. Continuing with cleanup..."
    fi
    
    # Delete Auto Scaling group
    aws autoscaling delete-auto-scaling-group \
        --auto-scaling-group-name "${ASG_NAME}" >/dev/null
    
    log_success "Auto Scaling group deleted: ${ASG_NAME}"
}

# Function to delete launch template
delete_launch_template() {
    if [[ -z "${LAUNCH_TEMPLATE_NAME:-}" ]]; then
        log_info "No Launch Template specified, skipping..."
        return 0
    fi
    
    log_info "Deleting Launch Template ${LAUNCH_TEMPLATE_NAME}..."
    
    # Check if launch template exists
    if ! aws ec2 describe-launch-templates --launch-template-names "${LAUNCH_TEMPLATE_NAME}" >/dev/null 2>&1; then
        log_warning "Launch Template ${LAUNCH_TEMPLATE_NAME} not found, skipping..."
        return 0
    fi
    
    # Get launch template ID
    local lt_id
    lt_id=$(aws ec2 describe-launch-templates \
        --launch-template-names "${LAUNCH_TEMPLATE_NAME}" \
        --query 'LaunchTemplates[0].LaunchTemplateId' \
        --output text)
    
    # Delete launch template
    aws ec2 delete-launch-template \
        --launch-template-id "${lt_id}" >/dev/null
    
    log_success "Launch template deleted: ${LAUNCH_TEMPLATE_NAME} (${lt_id})"
}

# Function to delete security group
delete_security_group() {
    if [[ -z "${SECURITY_GROUP_NAME:-}" ]]; then
        log_info "No Security Group specified, skipping..."
        return 0
    fi
    
    log_info "Deleting Security Group ${SECURITY_GROUP_NAME}..."
    
    # Check if security group exists
    if ! aws ec2 describe-security-groups --group-names "${SECURITY_GROUP_NAME}" >/dev/null 2>&1; then
        log_warning "Security Group ${SECURITY_GROUP_NAME} not found, skipping..."
        return 0
    fi
    
    # Get security group ID
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --group-names "${SECURITY_GROUP_NAME}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text)
    
    # Wait for instances to fully terminate before deleting security group
    log_info "Waiting for instances to fully terminate before deleting security group..."
    sleep 30
    
    # Retry deletion with backoff
    local max_attempts=5
    local attempt=1
    local wait_time=10
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        if aws ec2 delete-security-group --group-id "${sg_id}" >/dev/null 2>&1; then
            log_success "Security group deleted: ${SECURITY_GROUP_NAME} (${sg_id})"
            return 0
        else
            log_warning "Attempt ${attempt}/${max_attempts} failed to delete security group. Retrying in ${wait_time} seconds..."
            sleep ${wait_time}
            wait_time=$((wait_time * 2))  # Exponential backoff
            attempt=$((attempt + 1))
        fi
    done
    
    log_error "Failed to delete security group after ${max_attempts} attempts"
    log_error "You may need to delete it manually: ${SECURITY_GROUP_NAME} (${sg_id})"
}

# Function to clean up state file
cleanup_state_file() {
    local state_file="/tmp/ec2-asg-deployment-state.env"
    
    if [[ -f "${state_file}" ]]; then
        rm -f "${state_file}"
        log_success "Deployment state file cleaned up"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local cleanup_issues=0
    
    # Check if Auto Scaling Group still exists
    if [[ -n "${ASG_NAME:-}" ]] && aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${ASG_NAME}" >/dev/null 2>&1; then
        log_warning "Auto Scaling Group ${ASG_NAME} still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check if Launch Template still exists
    if [[ -n "${LAUNCH_TEMPLATE_NAME:-}" ]] && aws ec2 describe-launch-templates --launch-template-names "${LAUNCH_TEMPLATE_NAME}" >/dev/null 2>&1; then
        log_warning "Launch Template ${LAUNCH_TEMPLATE_NAME} still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check if Security Group still exists
    if [[ -n "${SECURITY_GROUP_NAME:-}" ]] && aws ec2 describe-security-groups --group-names "${SECURITY_GROUP_NAME}" >/dev/null 2>&1; then
        log_warning "Security Group ${SECURITY_GROUP_NAME} still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [[ ${cleanup_issues} -eq 0 ]]; then
        log_success "All resources successfully cleaned up!"
    else
        log_warning "Some resources may still exist. Please verify manually."
    fi
}

# Function to display cleanup summary
display_summary() {
    log_info "Cleanup Summary:"
    echo "================"
    echo "The following resources have been processed for deletion:"
    
    if [[ -n "${ASG_NAME:-}" ]]; then
        echo "  ✓ Auto Scaling Group: ${ASG_NAME}"
    fi
    if [[ -n "${LAUNCH_TEMPLATE_NAME:-}" ]]; then
        echo "  ✓ Launch Template: ${LAUNCH_TEMPLATE_NAME}"
    fi
    if [[ -n "${SECURITY_GROUP_NAME:-}" ]]; then
        echo "  ✓ Security Group: ${SECURITY_GROUP_NAME}"
    fi
    
    echo ""
    log_info "Note: It may take a few minutes for all resources to be fully removed"
    log_info "You can verify deletion in the AWS Console or by running AWS CLI describe commands"
}

# Main execution function
main() {
    log_info "Starting EC2 Launch Templates with Auto Scaling cleanup..."
    
    # Validate prerequisites
    validate_prerequisites
    
    # Try to load deployment state, otherwise prompt for manual input
    if ! load_state; then
        prompt_manual_input
    fi
    
    # Confirm cleanup action
    confirm_cleanup
    
    # Get instance information before cleanup
    get_asg_instances
    
    # Delete resources in reverse order of creation
    delete_auto_scaling_group
    delete_launch_template
    delete_security_group
    
    # Clean up state file
    cleanup_state_file
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_summary
    
    log_success "Cleanup script completed!"
}

# Trap errors and provide helpful messages
trap 'log_error "An error occurred during cleanup. Some resources may still exist."; exit 1' ERR

# Support for dry-run mode
if [[ "${1:-}" == "--dry-run" ]]; then
    log_info "DRY RUN MODE - No resources will be deleted"
    
    # Try to load state
    if load_state; then
        log_info "Would delete the following resources:"
        if [[ -n "${ASG_NAME:-}" ]]; then
            echo "  - Auto Scaling Group: ${ASG_NAME}"
        fi
        if [[ -n "${LAUNCH_TEMPLATE_NAME:-}" ]]; then
            echo "  - Launch Template: ${LAUNCH_TEMPLATE_NAME}"
        fi
        if [[ -n "${SECURITY_GROUP_NAME:-}" ]]; then
            echo "  - Security Group: ${SECURITY_GROUP_NAME}"
        fi
    else
        log_warning "No deployment state found for dry run"
    fi
    
    log_info "To actually delete resources, run: ./destroy.sh"
    exit 0
fi

# Support for help option
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "EC2 Launch Templates with Auto Scaling - Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deleted without actually deleting"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "This script will safely remove all resources created by the deployment script."
    echo "It loads resource names from the deployment state file, or prompts for manual input."
    exit 0
fi

# Run main function
main "$@"