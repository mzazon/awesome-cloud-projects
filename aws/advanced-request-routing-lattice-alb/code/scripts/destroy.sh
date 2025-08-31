#!/bin/bash

# Advanced Request Routing with VPC Lattice and ALB - Cleanup Script
# This script safely removes all resources created by the deployment script
# Author: AWS Recipe Generator
# Version: 1.0

set -e  # Exit on error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Error handling function
handle_error() {
    local line_num=$1
    local error_code=$2
    log_warning "A warning occurred at line $line_num with exit code $error_code"
    log_warning "Continuing cleanup process..."
}

# Set error trap (warnings only, don't exit)
trap 'handle_error ${LINENO} $?' ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Initialize log file
echo "=== Advanced Request Routing with VPC Lattice and ALB Cleanup ===" > "${LOG_FILE}"
echo "Cleanup started at: $(date)" >> "${LOG_FILE}"

log_info "Starting cleanup of Advanced Request Routing with VPC Lattice and ALB resources"

# Function to check if AWS CLI is available
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Cannot proceed with cleanup."
        exit 1
    fi
}

# Function to load state from deployment
load_state() {
    if [[ ! -f "${STATE_FILE}" ]]; then
        log_warning "State file not found: ${STATE_FILE}"
        log_warning "This might indicate no deployment exists or state was lost."
        
        # Try to discover resources by naming pattern
        discover_resources
        return
    fi
    
    log_info "Loading deployment state from: ${STATE_FILE}"
    source "${STATE_FILE}"
    
    log_info "Loaded state for cleanup:"
    log_info "- AWS Region: ${AWS_REGION:-Not set}"
    log_info "- Resource Suffix: ${RANDOM_SUFFIX:-Not set}"
    log_info "- VPC Lattice Network: ${LATTICE_NETWORK_NAME:-Not set}"
    log_info "- VPC Lattice Service: ${LATTICE_SERVICE_NAME:-Not set}"
}

# Function to discover resources if state file is missing
discover_resources() {
    log_info "Attempting to discover resources..."
    
    # Get AWS region and account
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Try to find VPC Lattice resources with common naming pattern
    log_info "Searching for VPC Lattice resources..."
    
    # This is a best-effort discovery - user may need to manually clean up
    log_warning "State file missing. You may need to manually identify and clean up resources."
    log_warning "Look for resources with names containing 'advanced-routing' or 'lattice-alb-sg'."
}

# Function to confirm cleanup
confirm_cleanup() {
    echo ""
    echo "⚠️  WARNING: This will delete ALL resources created by the deployment script."
    echo ""
    echo "Resources that will be deleted:"
    echo "- VPC Lattice service network and services"
    echo "- Application Load Balancer and target groups"
    echo "- EC2 instances"
    echo "- Security groups"
    echo "- Target VPC and subnet"
    echo "- IAM authentication policies"
    echo ""
    
    # Check if running in non-interactive mode
    if [[ "${FORCE_CLEANUP:-false}" == "true" ]]; then
        log_info "Force cleanup mode enabled. Proceeding without confirmation."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    case $confirmation in
        yes|YES|y|Y)
            log_info "Cleanup confirmed. Proceeding..."
            ;;
        *)
            log_info "Cleanup cancelled by user."
            exit 0
            ;;
    esac
}

# Function to safely delete a resource with error handling
safe_delete() {
    local resource_type="$1"
    local resource_id="$2"
    local delete_command="$3"
    
    if [[ -z "$resource_id" || "$resource_id" == "null" || "$resource_id" == "None" ]]; then
        log_warning "Skipping deletion of $resource_type - ID not available"
        return 0
    fi
    
    log_info "Deleting $resource_type: $resource_id"
    
    if eval "$delete_command" &> /dev/null; then
        log_success "Deleted $resource_type: $resource_id"
    else
        log_warning "Failed to delete $resource_type: $resource_id (may not exist)"
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local check_command="$2"
    local max_wait="$3"
    
    log_info "Waiting for $resource_type deletion to complete..."
    
    local count=0
    while [[ $count -lt $max_wait ]]; do
        if ! eval "$check_command" &> /dev/null; then
            log_success "$resource_type deletion completed"
            return 0
        fi
        
        sleep 5
        ((count++))
        
        if [[ $((count % 6)) -eq 0 ]]; then
            log_info "Still waiting for $resource_type deletion... (${count}/${max_wait})"
        fi
    done
    
    log_warning "$resource_type deletion timeout reached"
}

# Function to remove VPC Lattice listener rules
cleanup_lattice_rules() {
    log_info "Cleaning up VPC Lattice listener rules..."
    
    if [[ -z "$LATTICE_SERVICE_ID" || -z "$LATTICE_LISTENER_ID" ]]; then
        log_warning "VPC Lattice service or listener ID not available. Skipping rule cleanup."
        return 0
    fi
    
    # Get rule IDs for deletion
    local rule_ids=$(aws vpc-lattice list-rules \
        --service-identifier "$LATTICE_SERVICE_ID" \
        --listener-identifier "$LATTICE_LISTENER_ID" \
        --query "items[].id" --output text 2>/dev/null || echo "")
    
    if [[ -n "$rule_ids" ]]; then
        log_info "Found rules to delete: $rule_ids"
        for rule_id in $rule_ids; do
            safe_delete "VPC Lattice rule" "$rule_id" \
                "aws vpc-lattice delete-rule \
                    --service-identifier '$LATTICE_SERVICE_ID' \
                    --listener-identifier '$LATTICE_LISTENER_ID' \
                    --rule-identifier '$rule_id'"
        done
    else
        log_info "No VPC Lattice rules found to delete"
    fi
}

# Function to remove VPC Lattice listener
cleanup_lattice_listener() {
    log_info "Cleaning up VPC Lattice listener..."
    
    safe_delete "VPC Lattice listener" "$LATTICE_LISTENER_ID" \
        "aws vpc-lattice delete-listener \
            --service-identifier '$LATTICE_SERVICE_ID' \
            --listener-identifier '$LATTICE_LISTENER_ID'"
}

# Function to remove VPC Lattice target groups and service associations
cleanup_lattice_targets() {
    log_info "Cleaning up VPC Lattice target groups and service associations..."
    
    # Deregister targets from VPC Lattice target group
    if [[ -n "$LATTICE_TG_ID" && -n "$ALB1_ARN" ]]; then
        safe_delete "VPC Lattice target registration" "$ALB1_ARN" \
            "aws vpc-lattice deregister-targets \
                --target-group-identifier '$LATTICE_TG_ID' \
                --targets Id='$ALB1_ARN'"
    fi
    
    # Delete VPC Lattice target group
    safe_delete "VPC Lattice target group" "$LATTICE_TG_ID" \
        "aws vpc-lattice delete-target-group --target-group-identifier '$LATTICE_TG_ID'"
    
    # Delete service network service association
    if [[ -n "$LATTICE_NETWORK_ID" && -n "$LATTICE_SERVICE_ID" ]]; then
        safe_delete "VPC Lattice service association" "$LATTICE_SERVICE_ID" \
            "aws vpc-lattice delete-service-network-service-association \
                --service-network-identifier '$LATTICE_NETWORK_ID' \
                --service-identifier '$LATTICE_SERVICE_ID'"
    fi
}

# Function to remove VPC Lattice service and network
cleanup_lattice_service() {
    log_info "Cleaning up VPC Lattice service and network..."
    
    # Delete VPC network associations
    if [[ -n "$LATTICE_NETWORK_ID" && -n "$VPC_ID" ]]; then
        safe_delete "VPC Lattice VPC association (default)" "$VPC_ID" \
            "aws vpc-lattice delete-service-network-vpc-association \
                --service-network-identifier '$LATTICE_NETWORK_ID' \
                --vpc-identifier '$VPC_ID'"
    fi
    
    if [[ -n "$LATTICE_NETWORK_ID" && -n "$TARGET_VPC_ID" ]]; then
        safe_delete "VPC Lattice VPC association (target)" "$TARGET_VPC_ID" \
            "aws vpc-lattice delete-service-network-vpc-association \
                --service-network-identifier '$LATTICE_NETWORK_ID' \
                --vpc-identifier '$TARGET_VPC_ID'"
    fi
    
    # Delete VPC Lattice service
    safe_delete "VPC Lattice service" "$LATTICE_SERVICE_ID" \
        "aws vpc-lattice delete-service --service-identifier '$LATTICE_SERVICE_ID'"
    
    # Delete service network
    safe_delete "VPC Lattice service network" "$LATTICE_NETWORK_ID" \
        "aws vpc-lattice delete-service-network --service-network-identifier '$LATTICE_NETWORK_ID'"
}

# Function to remove EC2 instances
cleanup_ec2_instances() {
    log_info "Cleaning up EC2 instances..."
    
    if [[ -n "$INSTANCE_ID1" ]]; then
        # Terminate instances
        safe_delete "EC2 instance" "$INSTANCE_ID1" \
            "aws ec2 terminate-instances --instance-ids '$INSTANCE_ID1'"
        
        # Wait for termination
        if aws ec2 describe-instances --instance-ids "$INSTANCE_ID1" &> /dev/null; then
            log_info "Waiting for EC2 instance termination..."
            aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID1" 2>/dev/null || true
        fi
    fi
}

# Function to remove Load Balancer resources
cleanup_alb_resources() {
    log_info "Cleaning up Application Load Balancer resources..."
    
    # Delete ALB (this also deletes listeners)
    safe_delete "Application Load Balancer" "$ALB1_ARN" \
        "aws elbv2 delete-load-balancer --load-balancer-arn '$ALB1_ARN'"
    
    # Delete target groups
    safe_delete "ALB target group" "$API_TG_ARN" \
        "aws elbv2 delete-target-group --target-group-arn '$API_TG_ARN'"
    
    # Wait for ALB deletion before removing security group
    if [[ -n "$ALB1_ARN" ]]; then
        log_info "Waiting for ALB deletion to complete before removing security group..."
        
        # Check if ALB still exists
        local wait_count=0
        while [[ $wait_count -lt 24 ]]; do  # Wait up to 2 minutes
            if ! aws elbv2 describe-load-balancers --load-balancer-arns "$ALB1_ARN" &> /dev/null; then
                log_success "ALB deletion confirmed"
                break
            fi
            sleep 5
            ((wait_count++))
        done
        
        # Additional safety wait
        sleep 10
    fi
}

# Function to remove security groups
cleanup_security_groups() {
    log_info "Cleaning up security groups..."
    
    # Delete security group (ensure ALB is deleted first)
    if [[ -n "$ALB_SG_ID" ]]; then
        # Try to delete security group with retries
        local retry_count=0
        local max_retries=12  # 1 minute of retries
        
        while [[ $retry_count -lt $max_retries ]]; do
            if aws ec2 delete-security-group --group-id "$ALB_SG_ID" &> /dev/null; then
                log_success "Deleted security group: $ALB_SG_ID"
                break
            else
                log_info "Security group still in use, retrying... (attempt $((retry_count + 1))/$max_retries)"
                sleep 5
                ((retry_count++))
            fi
        done
        
        if [[ $retry_count -eq $max_retries ]]; then
            log_warning "Failed to delete security group: $ALB_SG_ID (may still be in use)"
        fi
    fi
}

# Function to remove target VPC resources
cleanup_target_vpc() {
    log_info "Cleaning up target VPC resources..."
    
    # Delete target subnet
    safe_delete "Target subnet" "$TARGET_SUBNET_ID" \
        "aws ec2 delete-subnet --subnet-id '$TARGET_SUBNET_ID'"
    
    # Delete target VPC
    safe_delete "Target VPC" "$TARGET_VPC_ID" \
        "aws ec2 delete-vpc --vpc-id '$TARGET_VPC_ID'"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove temporary files
    rm -f /tmp/userdata.sh /tmp/auth-policy.json
    
    log_success "Temporary files cleaned up"
}

# Function to remove state file
cleanup_state_file() {
    if [[ -f "${STATE_FILE}" ]]; then
        log_info "Removing deployment state file..."
        rm -f "${STATE_FILE}"
        log_success "State file removed: ${STATE_FILE}"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "=== CLEANUP COMPLETED ==="
    echo ""
    echo "The following resources have been cleaned up:"
    echo "- VPC Lattice service network and services"
    echo "- VPC Lattice listeners and routing rules"
    echo "- VPC Lattice target groups and associations"
    echo "- Application Load Balancer and target groups"
    echo "- EC2 instances"
    echo "- Security groups"
    echo "- Target VPC and subnet"
    echo "- Temporary files"
    echo "- Deployment state file"
    echo ""
    echo "Log file: ${LOG_FILE}"
    echo ""
    
    if [[ -n "${AWS_REGION}" ]]; then
        echo "You may want to verify cleanup in the AWS Console:"
        echo "- VPC Lattice: https://console.aws.amazon.com/vpc/home?region=${AWS_REGION}#Services:"
        echo "- EC2 Load Balancers: https://console.aws.amazon.com/ec2/home?region=${AWS_REGION}#LoadBalancers:"
        echo "- EC2 Instances: https://console.aws.amazon.com/ec2/home?region=${AWS_REGION}#Instances:"
        echo ""
    fi
    
    log_success "Cleanup completed successfully!"
    echo "=== END CLEANUP SUMMARY ==="
}

# Main cleanup function
main() {
    log_info "Advanced Request Routing with VPC Lattice and ALB - Cleanup Started"
    
    # Run cleanup steps
    check_aws_cli
    load_state
    confirm_cleanup
    
    # Cleanup in reverse order of creation
    cleanup_lattice_rules
    cleanup_lattice_listener
    cleanup_lattice_targets
    cleanup_lattice_service
    cleanup_ec2_instances
    cleanup_alb_resources
    cleanup_security_groups
    cleanup_target_vpc
    cleanup_temp_files
    cleanup_state_file
    
    display_cleanup_summary
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_CLEANUP=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--force] [--help]"
            echo ""
            echo "Options:"
            echo "  --force    Skip confirmation prompt"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"