#!/bin/bash

# Secure Database Access with VPC Lattice Resource Gateway - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging configuration
LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT_SECONDS=1800  # 30 minutes
FORCE_CLEANUP=false

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handler (non-fatal for cleanup)
handle_error() {
    print_warning "Non-fatal error at line $1. Continuing cleanup..."
}

trap 'handle_error $LINENO' ERR

# Load environment variables from deployment
load_environment() {
    print_status "Loading deployment environment..."
    
    if [[ -f "${SCRIPT_DIR}/deployment_env.sh" ]]; then
        source "${SCRIPT_DIR}/deployment_env.sh"
        print_success "Environment loaded from deployment_env.sh"
    else
        print_warning "deployment_env.sh not found. Manual environment setup required."
        return 1
    fi
    
    # Validate required variables
    local required_vars=(
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "DB_INSTANCE_ID"
        "SERVICE_NETWORK_ARN"
        "RESOURCE_CONFIG_ARN"
        "RESOURCE_GATEWAY_ARN"
        "RESOURCE_SHARE_ARN"
        "RANDOM_SUFFIX"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_error "Missing required environment variables: ${missing_vars[*]}"
        return 1
    fi
    
    print_status "Cleanup will target resources with suffix: ${RANDOM_SUFFIX}"
}

# Confirmation prompt
confirm_cleanup() {
    if [[ "$FORCE_CLEANUP" == "true" ]]; then
        return 0
    fi
    
    echo ""
    print_warning "This will permanently delete the following resources:"
    echo "  - RDS Database Instance: ${DB_INSTANCE_ID}"
    echo "  - VPC Lattice Service Network: ${SERVICE_NETWORK_NAME:-${SERVICE_NETWORK_ARN}}"
    echo "  - Resource Gateway: ${RESOURCE_GATEWAY_ARN}"
    echo "  - Resource Configuration: ${RESOURCE_CONFIG_ARN}"
    echo "  - AWS RAM Resource Share: ${RESOURCE_SHARE_ARN}"
    echo "  - Security Groups and associated resources"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/NO): " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_status "Cleanup cancelled by user"
        exit 0
    fi
}

# Wait for resource deletion with timeout
wait_for_deletion() {
    local check_command="$1"
    local resource_name="$2"
    local timeout_seconds="${3:-300}"
    
    print_status "Waiting for $resource_name deletion..."
    
    timeout_start=$(date +%s)
    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - timeout_start))
        
        if [[ $elapsed -gt $timeout_seconds ]]; then
            print_warning "Timeout waiting for $resource_name deletion"
            return 1
        fi
        
        if ! eval "$check_command" &>/dev/null; then
            print_success "$resource_name deleted successfully"
            return 0
        fi
        
        print_status "$resource_name still exists (elapsed: ${elapsed}s)"
        sleep 15
    done
}

# Remove consumer account associations (if accessible)
remove_consumer_associations() {
    print_status "Attempting to remove consumer account associations..."
    
    # Note: This requires access to consumer account
    # In practice, consumer account should clean up their own associations
    
    if [[ -n "${CONSUMER_ACCOUNT_ID:-}" ]]; then
        print_warning "Consumer account ${CONSUMER_ACCOUNT_ID} should remove their VPC associations"
        print_warning "This script cannot access consumer account resources directly"
    fi
    
    # Check for any remaining associations on our service network
    local associations
    associations=$(aws vpc-lattice list-service-network-vpc-associations \
        --service-network-identifier "${SERVICE_NETWORK_ARN}" \
        --query 'items[?associationStatus==`ACTIVE`].id' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$associations" ]]; then
        print_warning "Active VPC associations still exist. Consumer accounts should remove them first."
        print_status "Found associations: $associations"
    fi
}

# Remove resource configuration and associations
remove_resource_configuration() {
    print_status "Removing resource configuration and associations..."
    
    # Get resource configuration association ID
    local config_association_id
    config_association_id=$(aws vpc-lattice list-resource-configuration-associations \
        --resource-configuration-identifier "${RESOURCE_CONFIG_ARN}" \
        --query 'items[0].id' --output text 2>/dev/null || echo "")
    
    if [[ -n "$config_association_id" && "$config_association_id" != "None" ]]; then
        print_status "Deleting resource configuration association: $config_association_id"
        aws vpc-lattice delete-resource-configuration-association \
            --resource-configuration-association-identifier "$config_association_id" || true
        
        # Wait for association deletion
        sleep 30
    fi
    
    # Delete resource configuration
    print_status "Deleting resource configuration: ${RESOURCE_CONFIG_ARN}"
    aws vpc-lattice delete-resource-configuration \
        --resource-configuration-identifier "${RESOURCE_CONFIG_ARN}" || true
    
    print_success "Resource configuration cleanup initiated"
}

# Remove resource gateway
remove_resource_gateway() {
    print_status "Removing resource gateway..."
    
    # Delete resource gateway
    print_status "Deleting resource gateway: ${RESOURCE_GATEWAY_ARN}"
    aws vpc-lattice delete-resource-gateway \
        --resource-gateway-identifier "${RESOURCE_GATEWAY_ID}" || true
    
    # Wait for resource gateway deletion
    wait_for_deletion \
        "aws vpc-lattice get-resource-gateway --resource-gateway-identifier ${RESOURCE_GATEWAY_ID}" \
        "resource gateway" 300
    
    print_success "Resource gateway removed"
}

# Remove service network and VPC associations
remove_service_network() {
    print_status "Removing service network and VPC associations..."
    
    # Get service network VPC association ID
    local sn_vpc_association_id
    sn_vpc_association_id=$(aws vpc-lattice list-service-network-vpc-associations \
        --service-network-identifier "${SERVICE_NETWORK_ARN}" \
        --query 'items[0].id' --output text 2>/dev/null || echo "")
    
    if [[ -n "$sn_vpc_association_id" && "$sn_vpc_association_id" != "None" ]]; then
        print_status "Deleting service network VPC association: $sn_vpc_association_id"
        aws vpc-lattice delete-service-network-vpc-association \
            --service-network-vpc-association-identifier "$sn_vpc_association_id" || true
        
        # Wait for VPC association deletion
        sleep 30
    fi
    
    # Delete service network
    print_status "Deleting service network: ${SERVICE_NETWORK_ARN}"
    aws vpc-lattice delete-service-network \
        --service-network-identifier "${SERVICE_NETWORK_ARN}" || true
    
    print_success "Service network cleanup initiated"
}

# Remove RDS resources
remove_rds_resources() {
    print_status "Removing RDS resources..."
    
    # Delete RDS database instance
    print_status "Deleting RDS instance: ${DB_INSTANCE_ID}"
    aws rds delete-db-instance \
        --db-instance-identifier "${DB_INSTANCE_ID}" \
        --skip-final-snapshot || true
    
    # Wait for RDS deletion
    print_status "Waiting for RDS instance deletion (this may take several minutes)..."
    timeout_start=$(date +%s)
    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - timeout_start))
        
        if [[ $elapsed -gt $TIMEOUT_SECONDS ]]; then
            print_warning "Timeout waiting for RDS deletion"
            break
        fi
        
        db_status=$(aws rds describe-db-instances \
            --db-instance-identifier "${DB_INSTANCE_ID}" \
            --query 'DBInstances[0].DBInstanceStatus' \
            --output text 2>/dev/null || echo "deleted")
        
        if [[ "$db_status" == "deleted" ]]; then
            print_success "RDS instance deleted"
            break
        fi
        
        print_status "RDS status: $db_status (elapsed: ${elapsed}s)"
        sleep 30
    done
    
    # Delete DB subnet group
    if [[ -n "${DB_SUBNET_GROUP_NAME:-}" ]]; then
        print_status "Deleting DB subnet group: ${DB_SUBNET_GROUP_NAME}"
        aws rds delete-db-subnet-group \
            --db-subnet-group-name "${DB_SUBNET_GROUP_NAME}" || true
    fi
    
    print_success "RDS resources cleanup completed"
}

# Remove security groups
remove_security_groups() {
    print_status "Removing security groups..."
    
    # Delete resource gateway security group
    if [[ -n "${RESOURCE_GW_SG_ID:-}" ]]; then
        print_status "Deleting resource gateway security group: ${RESOURCE_GW_SG_ID}"
        aws ec2 delete-security-group \
            --group-id "${RESOURCE_GW_SG_ID}" || true
    fi
    
    # Delete RDS security group
    if [[ -n "${RDS_SECURITY_GROUP_ID:-}" ]]; then
        print_status "Deleting RDS security group: ${RDS_SECURITY_GROUP_ID}"
        aws ec2 delete-security-group \
            --group-id "${RDS_SECURITY_GROUP_ID}" || true
    fi
    
    print_success "Security groups cleanup completed"
}

# Remove AWS RAM resource share
remove_ram_share() {
    print_status "Removing AWS RAM resource share..."
    
    print_status "Deleting RAM resource share: ${RESOURCE_SHARE_ARN}"
    aws ram delete-resource-share \
        --resource-share-arn "${RESOURCE_SHARE_ARN}" || true
    
    print_success "RAM resource share cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    print_status "Cleaning up local files..."
    
    # Remove policy file
    if [[ -f "${SCRIPT_DIR}/lattice-db-access-policy.json" ]]; then
        rm -f "${SCRIPT_DIR}/lattice-db-access-policy.json"
        print_success "Removed IAM policy file"
    fi
    
    # Ask about environment file
    if [[ -f "${SCRIPT_DIR}/deployment_env.sh" ]] && [[ "$FORCE_CLEANUP" != "true" ]]; then
        read -p "Remove deployment environment file? (y/N): " remove_env
        if [[ "$remove_env" =~ ^[Yy]$ ]]; then
            rm -f "${SCRIPT_DIR}/deployment_env.sh"
            print_success "Removed deployment environment file"
        else
            print_status "Kept deployment environment file for reference"
        fi
    elif [[ "$FORCE_CLEANUP" == "true" ]] && [[ -f "${SCRIPT_DIR}/deployment_env.sh" ]]; then
        rm -f "${SCRIPT_DIR}/deployment_env.sh"
        print_success "Removed deployment environment file"
    fi
    
    print_success "Local files cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    print_status "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check RDS instance
    if aws rds describe-db-instances --db-instance-identifier "${DB_INSTANCE_ID}" &>/dev/null; then
        print_warning "RDS instance still exists"
        ((cleanup_errors++))
    fi
    
    # Check service network
    if aws vpc-lattice get-service-network --service-network-identifier "${SERVICE_NETWORK_ARN}" &>/dev/null; then
        print_warning "Service network still exists"
        ((cleanup_errors++))
    fi
    
    # Check resource gateway
    if aws vpc-lattice get-resource-gateway --resource-gateway-identifier "${RESOURCE_GATEWAY_ID}" &>/dev/null; then
        print_warning "Resource gateway still exists"
        ((cleanup_errors++))
    fi
    
    # Check RAM share
    if aws ram get-resource-shares --resource-share-arns "${RESOURCE_SHARE_ARN}" --resource-owner SELF &>/dev/null; then
        local share_status
        share_status=$(aws ram get-resource-shares \
            --resource-share-arns "${RESOURCE_SHARE_ARN}" \
            --resource-owner SELF \
            --query 'resourceShares[0].status' --output text 2>/dev/null || echo "DELETED")
        
        if [[ "$share_status" != "DELETED" ]]; then
            print_warning "RAM resource share still active: $share_status"
            ((cleanup_errors++))
        fi
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        print_success "Cleanup verification completed successfully"
        return 0
    else
        print_warning "Cleanup completed with $cleanup_errors remaining resources"
        print_warning "Some resources may take additional time to fully delete"
        return 1
    fi
}

# Print cleanup summary
print_cleanup_summary() {
    print_success "=== Cleanup Summary ==="
    echo "Cleanup completed at: $(date)"
    echo "Deployment ID: ${RANDOM_SUFFIX}"
    echo "AWS Region: ${AWS_REGION}"
    echo ""
    print_status "Cleanup log saved to: $LOG_FILE"
    echo ""
    print_warning "Note: Some AWS resources may take additional time to fully delete"
    print_warning "Check AWS console to verify all resources are removed"
    echo ""
    if [[ -n "${CONSUMER_ACCOUNT_ID:-}" ]]; then
        print_warning "Consumer account ${CONSUMER_ACCOUNT_ID} should also clean up their VPC associations"
    fi
}

# Main cleanup function
main() {
    print_status "Starting secure database access cleanup..."
    print_status "Cleanup started at: $(date)"
    
    if ! load_environment; then
        print_error "Cannot proceed without deployment environment"
        exit 1
    fi
    
    confirm_cleanup
    
    # Cleanup in reverse order of creation
    remove_consumer_associations
    remove_resource_configuration
    remove_resource_gateway
    remove_service_network
    remove_rds_resources
    remove_security_groups
    remove_ram_share
    cleanup_local_files
    
    verify_cleanup
    print_cleanup_summary
    
    print_success "Cleanup process completed!"
}

# Help function
show_help() {
    cat << EOF
Secure Database Access with VPC Lattice Resource Gateway - Cleanup Script

Usage: $0 [OPTIONS]

This script removes all resources created by the deployment script.
It reads the deployment environment from deployment_env.sh.

Options:
  -f, --force            Force cleanup without confirmation prompts
  -h, --help             Show this help message
  -v, --version          Show script version

Environment File:
  The script expects deployment_env.sh to exist in the same directory.
  This file is created automatically by the deployment script.

Example:
  $0                     # Interactive cleanup
  $0 --force             # Non-interactive cleanup

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE_CLEANUP=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            echo "Secure Database Access Cleanup Script v1.0"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"