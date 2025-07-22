#!/bin/bash

# AWS ParallelCluster HPC Cleanup Script
# This script removes all resources created by the deployment script
# Based on the "Scalable HPC Cluster with Auto-Scaling" recipe

set -e
set -o pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
DEPLOYMENT_VARS="${SCRIPT_DIR}/deployment-vars.env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    exit 1
}

# Success message
success() {
    log "${GREEN}SUCCESS: ${1}${NC}"
}

# Warning message
warning() {
    log "${YELLOW}WARNING: ${1}${NC}"
}

# Info message
info() {
    log "${BLUE}INFO: ${1}${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Confirmation prompt
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [ "$default" = "y" ] || [ "$default" = "Y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -p "$prompt" -n 1 -r
    echo
    
    if [ "$default" = "y" ] || [ "$default" = "Y" ]; then
        [[ ! $REPLY =~ ^[Nn]$ ]]
    else
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

# Load deployment variables
load_deployment_vars() {
    if [ ! -f "${DEPLOYMENT_VARS}" ]; then
        error_exit "Deployment variables file not found: ${DEPLOYMENT_VARS}. Please ensure the deployment script was run successfully."
    fi
    
    source "${DEPLOYMENT_VARS}"
    
    # Validate required variables
    local required_vars=("AWS_REGION" "CLUSTER_NAME" "S3_BUCKET_NAME" "KEYPAIR_NAME")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            error_exit "Required variable $var is not set in ${DEPLOYMENT_VARS}"
        fi
    done
    
    info "Loaded deployment variables from ${DEPLOYMENT_VARS}"
}

# Validate prerequisites
validate_prerequisites() {
    info "Validating prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set up credentials"
    fi
    
    # Check ParallelCluster CLI
    if ! command_exists pcluster; then
        error_exit "ParallelCluster CLI is not installed. Please install with: pip3 install aws-parallelcluster"
    fi
    
    success "Prerequisites validation completed"
}

# Delete ParallelCluster
delete_cluster() {
    info "Deleting ParallelCluster..."
    
    # Check if cluster exists
    if ! pcluster describe-cluster --cluster-name "${CLUSTER_NAME}" >/dev/null 2>&1; then
        warning "Cluster ${CLUSTER_NAME} does not exist. Skipping deletion."
        return 0
    fi
    
    # Delete the cluster
    info "Deleting HPC cluster (this may take 10-15 minutes)..."
    pcluster delete-cluster --cluster-name "${CLUSTER_NAME}" || error_exit "Failed to delete cluster"
    
    # Wait for deletion to complete
    info "Waiting for cluster deletion to complete..."
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local status=$(pcluster describe-cluster --cluster-name "${CLUSTER_NAME}" --query 'clusterStatus' --output text 2>/dev/null)
        
        case "$status" in
            "DELETE_COMPLETE")
                success "Cluster deleted successfully"
                break
                ;;
            "DELETE_FAILED")
                error_exit "Cluster deletion failed"
                ;;
            "DELETE_IN_PROGRESS")
                info "Cluster deletion in progress... (attempt $((attempt + 1))/${max_attempts})"
                sleep 30
                ;;
            "")
                # Cluster not found, assuming deleted
                success "Cluster deleted successfully"
                break
                ;;
            *)
                warning "Unknown cluster status: $status"
                sleep 30
                ;;
        esac
        
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        error_exit "Cluster deletion timed out"
    fi
    
    success "ParallelCluster deleted successfully"
}

# Delete CloudWatch resources
delete_monitoring() {
    info "Deleting CloudWatch monitoring resources..."
    
    # Delete dashboard
    aws cloudwatch delete-dashboards \
        --dashboard-names "${CLUSTER_NAME}-performance" >/dev/null 2>&1 || warning "Dashboard ${CLUSTER_NAME}-performance not found"
    
    # Delete alarms
    aws cloudwatch delete-alarms \
        --alarm-names "${CLUSTER_NAME}-high-cpu" >/dev/null 2>&1 || warning "Alarm ${CLUSTER_NAME}-high-cpu not found"
    
    success "CloudWatch resources deleted"
}

# Delete S3 bucket
delete_s3_bucket() {
    info "Deleting S3 bucket..."
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" >/dev/null 2>&1; then
        warning "S3 bucket ${S3_BUCKET_NAME} does not exist. Skipping deletion."
        return 0
    fi
    
    # Empty bucket contents
    info "Emptying S3 bucket contents..."
    aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive >/dev/null 2>&1 || warning "Failed to empty bucket or bucket already empty"
    
    # Delete all versions and delete markers
    aws s3api list-object-versions --bucket "${S3_BUCKET_NAME}" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output json | \
        jq -r '.[] | "--key \"" + .Key + "\" --version-id \"" + .VersionId + "\""' | \
        xargs -I {} aws s3api delete-object --bucket "${S3_BUCKET_NAME}" {} >/dev/null 2>&1 || true
    
    aws s3api list-object-versions --bucket "${S3_BUCKET_NAME}" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output json | \
        jq -r '.[] | "--key \"" + .Key + "\" --version-id \"" + .VersionId + "\""' | \
        xargs -I {} aws s3api delete-object --bucket "${S3_BUCKET_NAME}" {} >/dev/null 2>&1 || true
    
    # Delete bucket
    aws s3api delete-bucket --bucket "${S3_BUCKET_NAME}" || error_exit "Failed to delete S3 bucket"
    
    success "S3 bucket deleted: ${S3_BUCKET_NAME}"
}

# Delete NAT Gateway and associated resources
delete_nat_gateway() {
    info "Deleting NAT Gateway and associated resources..."
    
    if [ -z "$NAT_GW_ID" ]; then
        warning "NAT Gateway ID not found. Skipping deletion."
        return 0
    fi
    
    # Delete NAT Gateway
    aws ec2 delete-nat-gateway --nat-gateway-id "${NAT_GW_ID}" >/dev/null 2>&1 || warning "NAT Gateway ${NAT_GW_ID} not found"
    
    # Wait for NAT Gateway deletion
    info "Waiting for NAT Gateway deletion..."
    local max_attempts=20
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local state=$(aws ec2 describe-nat-gateways --nat-gateway-ids "${NAT_GW_ID}" --query 'NatGateways[0].State' --output text 2>/dev/null)
        
        case "$state" in
            "deleted")
                success "NAT Gateway deleted successfully"
                break
                ;;
            "deleting")
                info "NAT Gateway deletion in progress... (attempt $((attempt + 1))/${max_attempts})"
                sleep 15
                ;;
            "")
                # NAT Gateway not found, assuming deleted
                success "NAT Gateway deleted successfully"
                break
                ;;
            *)
                warning "NAT Gateway state: $state"
                sleep 15
                ;;
        esac
        
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        warning "NAT Gateway deletion timed out, but continuing cleanup"
    fi
    
    # Release Elastic IP
    if [ -n "$NAT_ALLOCATION_ID" ]; then
        aws ec2 release-address --allocation-id "${NAT_ALLOCATION_ID}" >/dev/null 2>&1 || warning "Elastic IP ${NAT_ALLOCATION_ID} not found"
        info "Released Elastic IP: ${NAT_ALLOCATION_ID}"
    fi
    
    success "NAT Gateway resources deleted"
}

# Delete VPC and networking resources
delete_vpc() {
    info "Deleting VPC and networking resources..."
    
    if [ -z "$VPC_ID" ]; then
        warning "VPC ID not found. Skipping VPC deletion."
        return 0
    fi
    
    # Delete private route table
    if [ -n "$PRIVATE_RT_ID" ]; then
        # Disassociate route table from subnet
        local association_id=$(aws ec2 describe-route-tables --route-table-ids "${PRIVATE_RT_ID}" --query 'RouteTables[0].Associations[?Main==`false`].RouteTableAssociationId' --output text 2>/dev/null)
        if [ -n "$association_id" ] && [ "$association_id" != "None" ]; then
            aws ec2 disassociate-route-table --association-id "${association_id}" >/dev/null 2>&1 || warning "Failed to disassociate route table"
        fi
        
        aws ec2 delete-route-table --route-table-id "${PRIVATE_RT_ID}" >/dev/null 2>&1 || warning "Private route table ${PRIVATE_RT_ID} not found"
        info "Deleted private route table: ${PRIVATE_RT_ID}"
    fi
    
    # Detach and delete internet gateway
    if [ -n "$IGW_ID" ]; then
        aws ec2 detach-internet-gateway --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}" >/dev/null 2>&1 || warning "Internet gateway ${IGW_ID} not attached to VPC"
        aws ec2 delete-internet-gateway --internet-gateway-id "${IGW_ID}" >/dev/null 2>&1 || warning "Internet gateway ${IGW_ID} not found"
        info "Deleted internet gateway: ${IGW_ID}"
    fi
    
    # Delete subnets
    if [ -n "$PUBLIC_SUBNET_ID" ]; then
        aws ec2 delete-subnet --subnet-id "${PUBLIC_SUBNET_ID}" >/dev/null 2>&1 || warning "Public subnet ${PUBLIC_SUBNET_ID} not found"
        info "Deleted public subnet: ${PUBLIC_SUBNET_ID}"
    fi
    
    if [ -n "$PRIVATE_SUBNET_ID" ]; then
        aws ec2 delete-subnet --subnet-id "${PRIVATE_SUBNET_ID}" >/dev/null 2>&1 || warning "Private subnet ${PRIVATE_SUBNET_ID} not found"
        info "Deleted private subnet: ${PRIVATE_SUBNET_ID}"
    fi
    
    # Delete security groups (except default)
    local security_groups=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null)
    if [ -n "$security_groups" ]; then
        for sg in $security_groups; do
            aws ec2 delete-security-group --group-id "$sg" >/dev/null 2>&1 || warning "Security group $sg not found or cannot be deleted"
        done
    fi
    
    # Delete VPC
    aws ec2 delete-vpc --vpc-id "${VPC_ID}" >/dev/null 2>&1 || warning "VPC ${VPC_ID} not found"
    
    success "VPC and networking resources deleted"
}

# Delete EC2 key pair
delete_keypair() {
    info "Deleting EC2 key pair..."
    
    # Delete key pair from AWS
    aws ec2 delete-key-pair --key-name "${KEYPAIR_NAME}" >/dev/null 2>&1 || warning "Key pair ${KEYPAIR_NAME} not found"
    
    # Delete local key file
    if [ -f ~/.ssh/"${KEYPAIR_NAME}.pem" ]; then
        rm -f ~/.ssh/"${KEYPAIR_NAME}.pem"
        info "Deleted local key file: ~/.ssh/${KEYPAIR_NAME}.pem"
    fi
    
    success "EC2 key pair deleted"
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove configuration files
    local files_to_remove=(
        "${SCRIPT_DIR}/cluster-config.yaml"
        "${SCRIPT_DIR}/deployment-vars.env"
        "${SCRIPT_DIR}/scaling-config.yaml"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            info "Removed: $file"
        fi
    done
    
    success "Local files cleaned up"
}

# Print cleanup summary
print_summary() {
    info "=== CLEANUP SUMMARY ==="
    info "Cluster Name: ${CLUSTER_NAME}"
    info "AWS Region: ${AWS_REGION}"
    info "S3 Bucket: ${S3_BUCKET_NAME}"
    info "Key Pair: ${KEYPAIR_NAME}"
    info "VPC: ${VPC_ID}"
    info ""
    info "All resources have been deleted successfully."
    info "Please verify in the AWS Console that all resources are removed."
    info "=========================="
}

# Main cleanup function
main() {
    info "Starting AWS ParallelCluster HPC cleanup..."
    echo "Cleanup started at $(date)" > "${LOG_FILE}"
    
    # Load deployment variables
    load_deployment_vars
    
    # Validate prerequisites
    validate_prerequisites
    
    # Confirmation prompt
    warning "This will delete ALL resources created by the deployment script."
    warning "This action cannot be undone."
    echo
    info "Resources to be deleted:"
    info "  - ParallelCluster: ${CLUSTER_NAME}"
    info "  - S3 Bucket: ${S3_BUCKET_NAME}"
    info "  - VPC: ${VPC_ID:-Not available}"
    info "  - Key Pair: ${KEYPAIR_NAME}"
    info "  - CloudWatch Dashboard and Alarms"
    echo
    
    if ! confirm "Are you sure you want to proceed with the cleanup?"; then
        info "Cleanup cancelled by user."
        exit 0
    fi
    
    # Perform cleanup
    delete_cluster
    delete_monitoring
    delete_s3_bucket
    delete_nat_gateway
    delete_vpc
    delete_keypair
    cleanup_local_files
    print_summary
    
    success "Cleanup completed successfully at $(date)"
    echo "Cleanup completed at $(date)" >> "${LOG_FILE}"
}

# Handle script interruption
trap 'warning "Cleanup interrupted. Some resources may remain. Please run this script again or clean up manually."; exit 1' INT TERM

# Run main function
main "$@"