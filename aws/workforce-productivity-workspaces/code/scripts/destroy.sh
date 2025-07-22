#!/bin/bash

# =============================================================================
# AWS WorkSpaces Cleanup Script
# =============================================================================
# This script safely removes all AWS WorkSpaces infrastructure including:
# - WorkSpaces virtual desktops
# - Simple AD directory service
# - VPC and networking components
# - CloudWatch monitoring resources
# - All associated security groups and configurations
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    log_info "Checking AWS CLI authentication..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or authentication failed"
        log_error "Please run 'aws configure' or set appropriate environment variables"
        exit 1
    fi
    log_success "AWS CLI authentication verified"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load deployment configuration
load_deployment_config() {
    log_info "Loading deployment configuration..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        log_error "AWS region is not configured"
        exit 1
    fi
    
    # Try to load from deployment log if provided
    if [[ $# -gt 0 && -f "$1" ]]; then
        log_info "Loading configuration from deployment log: $1"
        source "$1"
    else
        log_warning "No deployment log provided. Will attempt to discover resources by tags."
        log_warning "This may not find all resources if tags are missing."
    fi
    
    # Create cleanup log file
    export CLEANUP_LOG="/tmp/workspaces-cleanup-$(date +%Y%m%d-%H%M%S).log"
    echo "# WorkSpaces Cleanup Log - $(date)" > "$CLEANUP_LOG"
    
    log_info "Cleanup log: ${CLEANUP_LOG}"
}

# Function to discover WorkSpaces resources by tags
discover_resources() {
    log_info "Discovering WorkSpaces resources..."
    
    # Find VPCs with WorkSpaces tag
    VPC_IDS=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Purpose,Values=WorkSpaces" \
        --query 'Vpcs[].VpcId' --output text 2>/dev/null || echo "")
    
    # Find directories with WorkSpaces
    DIRECTORY_IDS=$(aws workspaces describe-workspace-directories \
        --query 'Directories[].DirectoryId' --output text 2>/dev/null || echo "")
    
    # Find WorkSpaces IP groups
    IP_GROUP_IDS=$(aws workspaces describe-ip-groups \
        --query 'Result[].GroupId' --output text 2>/dev/null || echo "")
    
    log_info "Discovered VPCs: ${VPC_IDS:-none}"
    log_info "Discovered Directories: ${DIRECTORY_IDS:-none}"
    log_info "Discovered IP Groups: ${IP_GROUP_IDS:-none}"
}

# Function to confirm destructive action
confirm_destruction() {
    echo
    log_warning "This script will PERMANENTLY DELETE the following resources:"
    echo "- All WorkSpaces virtual desktops"
    echo "- Simple AD directory service"
    echo "- VPC and all networking components"
    echo "- CloudWatch logs and alarms"
    echo "- All associated security configurations"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Cleanup confirmed. Proceeding with resource deletion..."
}

# Function to terminate all WorkSpaces
terminate_workspaces() {
    log_info "Terminating WorkSpaces..."
    
    local terminated_any=false
    
    # Process each directory
    for DIRECTORY_ID in $DIRECTORY_IDS; do
        if [[ -z "${DIRECTORY_ID}" ]]; then
            continue
        fi
        
        # Get all WorkSpaces in this directory
        WORKSPACE_IDS=$(aws workspaces describe-workspaces \
            --directory-id "$DIRECTORY_ID" \
            --query 'Workspaces[].WorkspaceId' --output text 2>/dev/null || echo "")
        
        if [[ -n "${WORKSPACE_IDS}" ]]; then
            log_info "Found WorkSpaces in directory ${DIRECTORY_ID}: ${WORKSPACE_IDS}"
            
            # Terminate each WorkSpace
            for WORKSPACE_ID in $WORKSPACE_IDS; do
                log_info "Terminating WorkSpace: ${WORKSPACE_ID}"
                aws workspaces terminate-workspaces \
                    --terminate-workspace-requests "WorkspaceId=${WORKSPACE_ID}" 2>/dev/null || true
                terminated_any=true
                echo "TERMINATED_WORKSPACE_${WORKSPACE_ID}=true" >> "$CLEANUP_LOG"
            done
        fi
    done
    
    if [[ "$terminated_any" == "true" ]]; then
        log_warning "Waiting for WorkSpaces termination to complete (this may take 10-15 minutes)..."
        sleep 30
        
        # Wait for termination with timeout
        local max_wait=30  # 30 minutes max
        local wait_count=0
        
        while [[ $wait_count -lt $max_wait ]]; do
            local all_terminated=true
            
            for DIRECTORY_ID in $DIRECTORY_IDS; do
                if [[ -z "${DIRECTORY_ID}" ]]; then
                    continue
                fi
                
                local remaining_workspaces=$(aws workspaces describe-workspaces \
                    --directory-id "$DIRECTORY_ID" \
                    --query 'length(Workspaces[?State != `TERMINATED`])' --output text 2>/dev/null || echo "0")
                
                if [[ "${remaining_workspaces}" != "0" ]]; then
                    all_terminated=false
                    break
                fi
            done
            
            if [[ "$all_terminated" == "true" ]]; then
                break
            fi
            
            wait_count=$((wait_count + 1))
            log_info "Still waiting for WorkSpaces termination... (${wait_count}/${max_wait})"
            sleep 60
        done
        
        log_success "WorkSpaces termination completed"
    else
        log_info "No WorkSpaces found to terminate"
    fi
}

# Function to remove IP access control groups
remove_ip_groups() {
    log_info "Removing IP access control groups..."
    
    for IP_GROUP_ID in $IP_GROUP_IDS; do
        if [[ -z "${IP_GROUP_ID}" ]]; then
            continue
        fi
        
        log_info "Removing IP group: ${IP_GROUP_ID}"
        
        # First, disassociate from directories
        for DIRECTORY_ID in $DIRECTORY_IDS; do
            if [[ -z "${DIRECTORY_ID}" ]]; then
                continue
            fi
            
            aws workspaces disassociate-ip-groups \
                --directory-id "$DIRECTORY_ID" \
                --group-ids "$IP_GROUP_ID" 2>/dev/null || true
        done
        
        # Then delete the IP group
        aws workspaces delete-ip-group \
            --group-id "$IP_GROUP_ID" 2>/dev/null || true
        
        echo "DELETED_IP_GROUP_${IP_GROUP_ID}=true" >> "$CLEANUP_LOG"
    done
    
    log_success "IP access control groups removed"
}

# Function to deregister directories from WorkSpaces
deregister_directories() {
    log_info "Deregistering directories from WorkSpaces..."
    
    for DIRECTORY_ID in $DIRECTORY_IDS; do
        if [[ -z "${DIRECTORY_ID}" ]]; then
            continue
        fi
        
        log_info "Deregistering directory: ${DIRECTORY_ID}"
        aws workspaces deregister-workspace-directory \
            --directory-id "$DIRECTORY_ID" 2>/dev/null || true
        
        echo "DEREGISTERED_DIRECTORY_${DIRECTORY_ID}=true" >> "$CLEANUP_LOG"
    done
    
    log_success "Directories deregistered from WorkSpaces"
}

# Function to delete Simple AD directories
delete_directories() {
    log_info "Deleting Simple AD directories..."
    
    for DIRECTORY_ID in $DIRECTORY_IDS; do
        if [[ -z "${DIRECTORY_ID}" ]]; then
            continue
        fi
        
        log_info "Deleting directory: ${DIRECTORY_ID}"
        aws ds delete-directory \
            --directory-id "$DIRECTORY_ID" 2>/dev/null || true
        
        echo "DELETED_DIRECTORY_${DIRECTORY_ID}=true" >> "$CLEANUP_LOG"
    done
    
    log_success "Simple AD directories deleted"
}

# Function to remove CloudWatch resources
remove_cloudwatch_resources() {
    log_info "Removing CloudWatch resources..."
    
    for DIRECTORY_ID in $DIRECTORY_IDS; do
        if [[ -z "${DIRECTORY_ID}" ]]; then
            continue
        fi
        
        # Delete log groups
        aws logs delete-log-group \
            --log-group-name "/aws/workspaces/${DIRECTORY_ID}" 2>/dev/null || true
        
        # Delete alarms
        aws cloudwatch delete-alarms \
            --alarm-names "WorkSpaces-Connection-Failures-${DIRECTORY_ID}" 2>/dev/null || true
        
        echo "DELETED_CLOUDWATCH_${DIRECTORY_ID}=true" >> "$CLEANUP_LOG"
    done
    
    log_success "CloudWatch resources removed"
}

# Function to remove networking components
remove_networking() {
    log_info "Removing networking components..."
    
    for VPC_ID in $VPC_IDS; do
        if [[ -z "${VPC_ID}" ]]; then
            continue
        fi
        
        log_info "Processing VPC: ${VPC_ID}"
        
        # Get NAT Gateways
        NAT_GW_IDS=$(aws ec2 describe-nat-gateways \
            --filter "Name=vpc-id,Values=${VPC_ID}" \
            --query 'NatGateways[?State==`available`].NatGatewayId' --output text 2>/dev/null || echo "")
        
        # Delete NAT Gateways
        for NAT_GW_ID in $NAT_GW_IDS; do
            if [[ -z "${NAT_GW_ID}" ]]; then
                continue
            fi
            
            log_info "Deleting NAT Gateway: ${NAT_GW_ID}"
            
            # Get EIP allocation ID before deleting NAT Gateway
            EIP_ALLOCATION_ID=$(aws ec2 describe-nat-gateways \
                --nat-gateway-ids "$NAT_GW_ID" \
                --query 'NatGateways[0].NatGatewayAddresses[0].AllocationId' --output text 2>/dev/null || echo "")
            
            aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_GW_ID" 2>/dev/null || true
            
            # Wait for NAT Gateway deletion
            log_info "Waiting for NAT Gateway deletion..."
            aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_GW_ID" 2>/dev/null || true
            
            # Release Elastic IP
            if [[ -n "${EIP_ALLOCATION_ID}" && "${EIP_ALLOCATION_ID}" != "None" ]]; then
                log_info "Releasing Elastic IP: ${EIP_ALLOCATION_ID}"
                aws ec2 release-address --allocation-id "$EIP_ALLOCATION_ID" 2>/dev/null || true
            fi
            
            echo "DELETED_NAT_GW_${NAT_GW_ID}=true" >> "$CLEANUP_LOG"
        done
        
        # Get and delete custom route tables
        ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables \
            --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query 'RouteTables[?Associations[0].Main==`false`].RouteTableId' --output text 2>/dev/null || echo "")
        
        for RT_ID in $ROUTE_TABLE_IDS; do
            if [[ -z "${RT_ID}" ]]; then
                continue
            fi
            
            log_info "Deleting route table: ${RT_ID}"
            aws ec2 delete-route-table --route-table-id "$RT_ID" 2>/dev/null || true
        done
        
        # Get and detach/delete Internet Gateway
        IGW_IDS=$(aws ec2 describe-internet-gateways \
            --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
            --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || echo "")
        
        for IGW_ID in $IGW_IDS; do
            if [[ -z "${IGW_ID}" ]]; then
                continue
            fi
            
            log_info "Detaching and deleting Internet Gateway: ${IGW_ID}"
            aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" 2>/dev/null || true
            aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" 2>/dev/null || true
        done
        
        # Get and delete subnets
        SUBNET_IDS=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo "")
        
        for SUBNET_ID in $SUBNET_IDS; do
            if [[ -z "${SUBNET_ID}" ]]; then
                continue
            fi
            
            log_info "Deleting subnet: ${SUBNET_ID}"
            aws ec2 delete-subnet --subnet-id "$SUBNET_ID" 2>/dev/null || true
        done
        
        # Get and delete security groups (except default)
        SECURITY_GROUP_IDS=$(aws ec2 describe-security-groups \
            --filters "Name=vpc-id,Values=${VPC_ID}" \
            --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")
        
        for SG_ID in $SECURITY_GROUP_IDS; do
            if [[ -z "${SG_ID}" ]]; then
                continue
            fi
            
            log_info "Deleting security group: ${SG_ID}"
            aws ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null || true
        done
        
        # Finally, delete the VPC
        log_info "Deleting VPC: ${VPC_ID}"
        aws ec2 delete-vpc --vpc-id "$VPC_ID" 2>/dev/null || true
        
        echo "DELETED_VPC_${VPC_ID}=true" >> "$CLEANUP_LOG"
    done
    
    log_success "Networking components removed"
}

# Function to validate cleanup
validate_cleanup() {
    log_info "Validating cleanup..."
    
    local cleanup_issues=0
    
    # Check for remaining WorkSpaces
    for DIRECTORY_ID in $DIRECTORY_IDS; do
        if [[ -z "${DIRECTORY_ID}" ]]; then
            continue
        fi
        
        local remaining_workspaces=$(aws workspaces describe-workspaces \
            --directory-id "$DIRECTORY_ID" \
            --query 'length(Workspaces[?State != `TERMINATED`])' --output text 2>/dev/null || echo "0")
        
        if [[ "${remaining_workspaces}" != "0" ]]; then
            log_warning "Directory ${DIRECTORY_ID} still has ${remaining_workspaces} WorkSpaces"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    done
    
    # Check for remaining VPCs
    for VPC_ID in $VPC_IDS; do
        if [[ -z "${VPC_ID}" ]]; then
            continue
        fi
        
        local vpc_exists=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" \
            --query 'length(Vpcs)' --output text 2>/dev/null || echo "0")
        
        if [[ "${vpc_exists}" != "0" ]]; then
            log_warning "VPC ${VPC_ID} still exists"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    done
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "Cleanup validation successful - all resources removed"
        return 0
    else
        log_warning "Cleanup validation found ${cleanup_issues} remaining resources"
        log_info "Some resources may still be in deletion process"
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary:"
    echo "===================="
    echo "Terminated WorkSpaces: $(grep -c "TERMINATED_WORKSPACE" "$CLEANUP_LOG" 2>/dev/null || echo "0")"
    echo "Deleted Directories: $(grep -c "DELETED_DIRECTORY" "$CLEANUP_LOG" 2>/dev/null || echo "0")"
    echo "Deleted VPCs: $(grep -c "DELETED_VPC" "$CLEANUP_LOG" 2>/dev/null || echo "0")"
    echo "Region: ${AWS_REGION}"
    echo "Cleanup Log: ${CLEANUP_LOG}"
    echo "===================="
    
    log_info "Check the cleanup log for detailed information about deleted resources"
}

# Function to handle script cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Cleanup failed with exit code $exit_code"
        log_info "Check the cleanup log: ${CLEANUP_LOG}"
        log_info "Some resources may need to be removed manually"
    fi
}

# Main cleanup function
main() {
    echo "======================================="
    echo "AWS WorkSpaces Cleanup Script"
    echo "======================================="
    
    # Set trap for cleanup on exit
    trap cleanup_on_exit EXIT
    
    check_prerequisites
    check_aws_auth
    load_deployment_config "$@"
    discover_resources
    confirm_destruction
    
    terminate_workspaces
    remove_ip_groups
    deregister_directories
    delete_directories
    remove_cloudwatch_resources
    remove_networking
    
    # Final validation
    if validate_cleanup; then
        display_cleanup_summary
        log_success "WorkSpaces cleanup completed successfully!"
    else
        display_cleanup_summary
        log_warning "Cleanup completed but some resources may still be removing"
        log_info "Run the validation again in a few minutes"
    fi
}

# Script execution check
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi