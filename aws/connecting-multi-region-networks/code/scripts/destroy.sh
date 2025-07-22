#!/bin/bash

# Multi-Region VPC Connectivity with Transit Gateway - Cleanup Script
# This script safely removes all resources created by the deployment script
# in the correct order to avoid dependency conflicts

set -e
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/deployment-state.env"
FORCE_DELETE=false
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            cat << EOF
Usage: $0 [OPTIONS]

Safely destroy all resources created by the multi-region Transit Gateway deployment

OPTIONS:
    --force      Skip confirmation prompts and force deletion
    --dry-run    Show what would be deleted without making changes
    --help       Show this help message

EXAMPLES:
    $0                    # Interactive cleanup with confirmations
    $0 --force            # Force cleanup without confirmations
    $0 --dry-run          # Preview what would be deleted
EOF
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if state file exists
    if [[ ! -f "$STATE_FILE" ]]; then
        error "State file not found: $STATE_FILE"
        error "Cannot determine what resources to delete."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load state from file
load_state() {
    log "Loading deployment state..."
    
    # Source the state file to load variables
    # shellcheck disable=SC1090
    source "$STATE_FILE"
    
    # Validate required variables are set
    if [[ -z "$PROJECT_NAME" || -z "$PRIMARY_REGION" || -z "$SECONDARY_REGION" ]]; then
        error "State file is incomplete. Missing required variables."
        exit 1
    fi
    
    success "State loaded from ${STATE_FILE}"
    log "Project Name: ${PROJECT_NAME}"
    log "Primary Region: ${PRIMARY_REGION}"
    log "Secondary Region: ${SECONDARY_REGION}"
}

# Function to prompt for confirmation
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warning "This will permanently delete all resources for project: ${PROJECT_NAME}"
    echo "Resources to be deleted:"
    echo "  - Transit Gateways in ${PRIMARY_REGION} and ${SECONDARY_REGION}"
    echo "  - VPCs and associated networking resources"
    echo "  - Security groups and route tables"
    echo "  - CloudWatch dashboard"
    echo ""
    echo "This action cannot be undone."
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    warning "Final confirmation required"
    read -p "Type 'DELETE' to confirm resource deletion: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to safely delete a resource with error handling
safe_delete() {
    local resource_type="$1"
    local resource_id="$2"
    local region="$3"
    local delete_command="$4"
    
    if [[ -z "$resource_id" ]]; then
        log "Skipping ${resource_type} deletion - no resource ID found"
        return 0
    fi
    
    log "Deleting ${resource_type}: ${resource_id}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete ${resource_type} ${resource_id}"
        return 0
    fi
    
    if eval "$delete_command"; then
        success "Deleted ${resource_type}: ${resource_id}"
    else
        warning "Failed to delete ${resource_type}: ${resource_id} (may already be deleted)"
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_id="$2"
    local region="$3"
    local check_command="$4"
    local max_wait="${5:-300}"  # Default 5 minutes
    
    if [[ -z "$resource_id" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log "Waiting for ${resource_type} ${resource_id} to be deleted..."
    
    local counter=0
    while [[ $counter -lt $max_wait ]]; do
        if ! eval "$check_command" &>/dev/null; then
            success "${resource_type} ${resource_id} deleted successfully"
            return 0
        fi
        
        sleep 10
        counter=$((counter + 10))
    done
    
    warning "${resource_type} ${resource_id} deletion timed out after ${max_wait} seconds"
}

# Function to delete cross-region routes
delete_cross_region_routes() {
    log "Deleting cross-region routes..."
    
    # Delete routes from primary to secondary region
    if [[ -n "$PRIMARY_ROUTE_TABLE_ID" && -n "$SECONDARY_VPC_A_CIDR" ]]; then
        safe_delete "route" "${SECONDARY_VPC_A_CIDR}" "${PRIMARY_REGION}" \
            "aws ec2 delete-transit-gateway-route \
                --destination-cidr-block \"${SECONDARY_VPC_A_CIDR}\" \
                --transit-gateway-route-table-id \"${PRIMARY_ROUTE_TABLE_ID}\" \
                --region \"${PRIMARY_REGION}\""
    fi
    
    if [[ -n "$PRIMARY_ROUTE_TABLE_ID" && -n "$SECONDARY_VPC_B_CIDR" ]]; then
        safe_delete "route" "${SECONDARY_VPC_B_CIDR}" "${PRIMARY_REGION}" \
            "aws ec2 delete-transit-gateway-route \
                --destination-cidr-block \"${SECONDARY_VPC_B_CIDR}\" \
                --transit-gateway-route-table-id \"${PRIMARY_ROUTE_TABLE_ID}\" \
                --region \"${PRIMARY_REGION}\""
    fi
    
    # Delete routes from secondary to primary region
    if [[ -n "$SECONDARY_ROUTE_TABLE_ID" && -n "$PRIMARY_VPC_A_CIDR" ]]; then
        safe_delete "route" "${PRIMARY_VPC_A_CIDR}" "${SECONDARY_REGION}" \
            "aws ec2 delete-transit-gateway-route \
                --destination-cidr-block \"${PRIMARY_VPC_A_CIDR}\" \
                --transit-gateway-route-table-id \"${SECONDARY_ROUTE_TABLE_ID}\" \
                --region \"${SECONDARY_REGION}\""
    fi
    
    if [[ -n "$SECONDARY_ROUTE_TABLE_ID" && -n "$PRIMARY_VPC_B_CIDR" ]]; then
        safe_delete "route" "${PRIMARY_VPC_B_CIDR}" "${SECONDARY_REGION}" \
            "aws ec2 delete-transit-gateway-route \
                --destination-cidr-block \"${PRIMARY_VPC_B_CIDR}\" \
                --transit-gateway-route-table-id \"${SECONDARY_ROUTE_TABLE_ID}\" \
                --region \"${SECONDARY_REGION}\""
    fi
    
    success "Cross-region routes deletion completed"
}

# Function to delete route table associations
delete_route_table_associations() {
    log "Deleting route table associations..."
    
    # Disassociate primary region attachments
    if [[ -n "$PRIMARY_ATTACHMENT_A_ID" && -n "$PRIMARY_ROUTE_TABLE_ID" ]]; then
        safe_delete "association" "${PRIMARY_ATTACHMENT_A_ID}" "${PRIMARY_REGION}" \
            "aws ec2 disassociate-transit-gateway-route-table \
                --transit-gateway-attachment-id \"${PRIMARY_ATTACHMENT_A_ID}\" \
                --transit-gateway-route-table-id \"${PRIMARY_ROUTE_TABLE_ID}\" \
                --region \"${PRIMARY_REGION}\""
    fi
    
    if [[ -n "$PRIMARY_ATTACHMENT_B_ID" && -n "$PRIMARY_ROUTE_TABLE_ID" ]]; then
        safe_delete "association" "${PRIMARY_ATTACHMENT_B_ID}" "${PRIMARY_REGION}" \
            "aws ec2 disassociate-transit-gateway-route-table \
                --transit-gateway-attachment-id \"${PRIMARY_ATTACHMENT_B_ID}\" \
                --transit-gateway-route-table-id \"${PRIMARY_ROUTE_TABLE_ID}\" \
                --region \"${PRIMARY_REGION}\""
    fi
    
    # Disassociate secondary region attachments
    if [[ -n "$SECONDARY_ATTACHMENT_A_ID" && -n "$SECONDARY_ROUTE_TABLE_ID" ]]; then
        safe_delete "association" "${SECONDARY_ATTACHMENT_A_ID}" "${SECONDARY_REGION}" \
            "aws ec2 disassociate-transit-gateway-route-table \
                --transit-gateway-attachment-id \"${SECONDARY_ATTACHMENT_A_ID}\" \
                --transit-gateway-route-table-id \"${SECONDARY_ROUTE_TABLE_ID}\" \
                --region \"${SECONDARY_REGION}\""
    fi
    
    if [[ -n "$SECONDARY_ATTACHMENT_B_ID" && -n "$SECONDARY_ROUTE_TABLE_ID" ]]; then
        safe_delete "association" "${SECONDARY_ATTACHMENT_B_ID}" "${SECONDARY_REGION}" \
            "aws ec2 disassociate-transit-gateway-route-table \
                --transit-gateway-attachment-id \"${SECONDARY_ATTACHMENT_B_ID}\" \
                --transit-gateway-route-table-id \"${SECONDARY_ROUTE_TABLE_ID}\" \
                --region \"${SECONDARY_REGION}\""
    fi
    
    # Disassociate peering attachment
    if [[ -n "$PEERING_ATTACHMENT_ID" && -n "$PRIMARY_ROUTE_TABLE_ID" ]]; then
        safe_delete "association" "${PEERING_ATTACHMENT_ID}" "${PRIMARY_REGION}" \
            "aws ec2 disassociate-transit-gateway-route-table \
                --transit-gateway-attachment-id \"${PEERING_ATTACHMENT_ID}\" \
                --transit-gateway-route-table-id \"${PRIMARY_ROUTE_TABLE_ID}\" \
                --region \"${PRIMARY_REGION}\""
    fi
    
    if [[ -n "$PEERING_ATTACHMENT_ID" && -n "$SECONDARY_ROUTE_TABLE_ID" ]]; then
        safe_delete "association" "${PEERING_ATTACHMENT_ID}" "${SECONDARY_REGION}" \
            "aws ec2 disassociate-transit-gateway-route-table \
                --transit-gateway-attachment-id \"${PEERING_ATTACHMENT_ID}\" \
                --transit-gateway-route-table-id \"${SECONDARY_ROUTE_TABLE_ID}\" \
                --region \"${SECONDARY_REGION}\""
    fi
    
    success "Route table associations deletion completed"
}

# Function to delete custom route tables
delete_route_tables() {
    log "Deleting custom route tables..."
    
    # Delete primary region route table
    if [[ -n "$PRIMARY_ROUTE_TABLE_ID" ]]; then
        safe_delete "route-table" "${PRIMARY_ROUTE_TABLE_ID}" "${PRIMARY_REGION}" \
            "aws ec2 delete-transit-gateway-route-table \
                --transit-gateway-route-table-id \"${PRIMARY_ROUTE_TABLE_ID}\" \
                --region \"${PRIMARY_REGION}\""
    fi
    
    # Delete secondary region route table
    if [[ -n "$SECONDARY_ROUTE_TABLE_ID" ]]; then
        safe_delete "route-table" "${SECONDARY_ROUTE_TABLE_ID}" "${SECONDARY_REGION}" \
            "aws ec2 delete-transit-gateway-route-table \
                --transit-gateway-route-table-id \"${SECONDARY_ROUTE_TABLE_ID}\" \
                --region \"${SECONDARY_REGION}\""
    fi
    
    success "Custom route tables deletion completed"
}

# Function to delete Transit Gateway peering attachment
delete_peering_attachment() {
    log "Deleting Transit Gateway peering attachment..."
    
    if [[ -n "$PEERING_ATTACHMENT_ID" ]]; then
        safe_delete "peering-attachment" "${PEERING_ATTACHMENT_ID}" "${PRIMARY_REGION}" \
            "aws ec2 delete-transit-gateway-peering-attachment \
                --transit-gateway-attachment-id \"${PEERING_ATTACHMENT_ID}\" \
                --region \"${PRIMARY_REGION}\""
        
        # Wait for peering attachment to be deleted
        wait_for_deletion "peering-attachment" "${PEERING_ATTACHMENT_ID}" "${PRIMARY_REGION}" \
            "aws ec2 describe-transit-gateway-peering-attachments \
                --transit-gateway-attachment-ids \"${PEERING_ATTACHMENT_ID}\" \
                --region \"${PRIMARY_REGION}\" \
                --query 'TransitGatewayPeeringAttachments[0].State' --output text"
    fi
    
    success "Transit Gateway peering attachment deletion completed"
}

# Function to delete VPC attachments
delete_vpc_attachments() {
    log "Deleting VPC attachments..."
    
    # Delete primary region VPC attachments
    if [[ -n "$PRIMARY_ATTACHMENT_A_ID" ]]; then
        safe_delete "vpc-attachment" "${PRIMARY_ATTACHMENT_A_ID}" "${PRIMARY_REGION}" \
            "aws ec2 delete-transit-gateway-vpc-attachment \
                --transit-gateway-attachment-id \"${PRIMARY_ATTACHMENT_A_ID}\" \
                --region \"${PRIMARY_REGION}\""
    fi
    
    if [[ -n "$PRIMARY_ATTACHMENT_B_ID" ]]; then
        safe_delete "vpc-attachment" "${PRIMARY_ATTACHMENT_B_ID}" "${PRIMARY_REGION}" \
            "aws ec2 delete-transit-gateway-vpc-attachment \
                --transit-gateway-attachment-id \"${PRIMARY_ATTACHMENT_B_ID}\" \
                --region \"${PRIMARY_REGION}\""
    fi
    
    # Delete secondary region VPC attachments
    if [[ -n "$SECONDARY_ATTACHMENT_A_ID" ]]; then
        safe_delete "vpc-attachment" "${SECONDARY_ATTACHMENT_A_ID}" "${SECONDARY_REGION}" \
            "aws ec2 delete-transit-gateway-vpc-attachment \
                --transit-gateway-attachment-id \"${SECONDARY_ATTACHMENT_A_ID}\" \
                --region \"${SECONDARY_REGION}\""
    fi
    
    if [[ -n "$SECONDARY_ATTACHMENT_B_ID" ]]; then
        safe_delete "vpc-attachment" "${SECONDARY_ATTACHMENT_B_ID}" "${SECONDARY_REGION}" \
            "aws ec2 delete-transit-gateway-vpc-attachment \
                --transit-gateway-attachment-id \"${SECONDARY_ATTACHMENT_B_ID}\" \
                --region \"${SECONDARY_REGION}\""
    fi
    
    success "VPC attachments deletion completed"
}

# Function to delete Transit Gateways
delete_transit_gateways() {
    log "Deleting Transit Gateways..."
    
    # Delete primary region Transit Gateway
    if [[ -n "$PRIMARY_TGW_ID" ]]; then
        safe_delete "transit-gateway" "${PRIMARY_TGW_ID}" "${PRIMARY_REGION}" \
            "aws ec2 delete-transit-gateway \
                --transit-gateway-id \"${PRIMARY_TGW_ID}\" \
                --region \"${PRIMARY_REGION}\""
    fi
    
    # Delete secondary region Transit Gateway
    if [[ -n "$SECONDARY_TGW_ID" ]]; then
        safe_delete "transit-gateway" "${SECONDARY_TGW_ID}" "${SECONDARY_REGION}" \
            "aws ec2 delete-transit-gateway \
                --transit-gateway-id \"${SECONDARY_TGW_ID}\" \
                --region \"${SECONDARY_REGION}\""
    fi
    
    success "Transit Gateways deletion completed"
}

# Function to delete security groups
delete_security_groups() {
    log "Deleting security groups..."
    
    # Delete primary region security group
    if [[ -n "$PRIMARY_SG_A_ID" ]]; then
        safe_delete "security-group" "${PRIMARY_SG_A_ID}" "${PRIMARY_REGION}" \
            "aws ec2 delete-security-group \
                --group-id \"${PRIMARY_SG_A_ID}\" \
                --region \"${PRIMARY_REGION}\""
    fi
    
    # Delete secondary region security group
    if [[ -n "$SECONDARY_SG_A_ID" ]]; then
        safe_delete "security-group" "${SECONDARY_SG_A_ID}" "${SECONDARY_REGION}" \
            "aws ec2 delete-security-group \
                --group-id \"${SECONDARY_SG_A_ID}\" \
                --region \"${SECONDARY_REGION}\""
    fi
    
    success "Security groups deletion completed"
}

# Function to delete subnets
delete_subnets() {
    log "Deleting subnets..."
    
    # Delete primary region subnets
    if [[ -n "$PRIMARY_SUBNET_A_ID" ]]; then
        safe_delete "subnet" "${PRIMARY_SUBNET_A_ID}" "${PRIMARY_REGION}" \
            "aws ec2 delete-subnet \
                --subnet-id \"${PRIMARY_SUBNET_A_ID}\" \
                --region \"${PRIMARY_REGION}\""
    fi
    
    if [[ -n "$PRIMARY_SUBNET_B_ID" ]]; then
        safe_delete "subnet" "${PRIMARY_SUBNET_B_ID}" "${PRIMARY_REGION}" \
            "aws ec2 delete-subnet \
                --subnet-id \"${PRIMARY_SUBNET_B_ID}\" \
                --region \"${PRIMARY_REGION}\""
    fi
    
    # Delete secondary region subnets
    if [[ -n "$SECONDARY_SUBNET_A_ID" ]]; then
        safe_delete "subnet" "${SECONDARY_SUBNET_A_ID}" "${SECONDARY_REGION}" \
            "aws ec2 delete-subnet \
                --subnet-id \"${SECONDARY_SUBNET_A_ID}\" \
                --region \"${SECONDARY_REGION}\""
    fi
    
    if [[ -n "$SECONDARY_SUBNET_B_ID" ]]; then
        safe_delete "subnet" "${SECONDARY_SUBNET_B_ID}" "${SECONDARY_REGION}" \
            "aws ec2 delete-subnet \
                --subnet-id \"${SECONDARY_SUBNET_B_ID}\" \
                --region \"${SECONDARY_REGION}\""
    fi
    
    success "Subnets deletion completed"
}

# Function to delete VPCs
delete_vpcs() {
    log "Deleting VPCs..."
    
    # Delete primary region VPCs
    if [[ -n "$PRIMARY_VPC_A_ID" ]]; then
        safe_delete "vpc" "${PRIMARY_VPC_A_ID}" "${PRIMARY_REGION}" \
            "aws ec2 delete-vpc \
                --vpc-id \"${PRIMARY_VPC_A_ID}\" \
                --region \"${PRIMARY_REGION}\""
    fi
    
    if [[ -n "$PRIMARY_VPC_B_ID" ]]; then
        safe_delete "vpc" "${PRIMARY_VPC_B_ID}" "${PRIMARY_REGION}" \
            "aws ec2 delete-vpc \
                --vpc-id \"${PRIMARY_VPC_B_ID}\" \
                --region \"${PRIMARY_REGION}\""
    fi
    
    # Delete secondary region VPCs
    if [[ -n "$SECONDARY_VPC_A_ID" ]]; then
        safe_delete "vpc" "${SECONDARY_VPC_A_ID}" "${SECONDARY_REGION}" \
            "aws ec2 delete-vpc \
                --vpc-id \"${SECONDARY_VPC_A_ID}\" \
                --region \"${SECONDARY_REGION}\""
    fi
    
    if [[ -n "$SECONDARY_VPC_B_ID" ]]; then
        safe_delete "vpc" "${SECONDARY_VPC_B_ID}" "${SECONDARY_REGION}" \
            "aws ec2 delete-vpc \
                --vpc-id \"${SECONDARY_VPC_B_ID}\" \
                --region \"${SECONDARY_REGION}\""
    fi
    
    success "VPCs deletion completed"
}

# Function to delete CloudWatch dashboard
delete_monitoring() {
    log "Deleting CloudWatch dashboard..."
    
    if [[ -n "$PROJECT_NAME" ]]; then
        safe_delete "dashboard" "${PROJECT_NAME}-tgw-dashboard" "${PRIMARY_REGION}" \
            "aws cloudwatch delete-dashboards \
                --dashboard-names \"${PROJECT_NAME}-tgw-dashboard\" \
                --region \"${PRIMARY_REGION}\""
    fi
    
    success "CloudWatch dashboard deletion completed"
}

# Function to clean up state file
cleanup_state_file() {
    log "Cleaning up state file..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete state file ${STATE_FILE}"
        return 0
    fi
    
    if [[ -f "$STATE_FILE" ]]; then
        rm "$STATE_FILE"
        success "State file deleted: ${STATE_FILE}"
    else
        log "State file not found: ${STATE_FILE}"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "=================================="
    echo "Project Name: ${PROJECT_NAME}"
    echo "Primary Region: ${PRIMARY_REGION}"
    echo "Secondary Region: ${SECONDARY_REGION}"
    echo ""
    echo "Resources Deleted:"
    echo "  - Cross-region routes"
    echo "  - Route table associations"
    echo "  - Custom route tables"
    echo "  - Transit Gateway peering attachment"
    echo "  - VPC attachments"
    echo "  - Transit Gateways"
    echo "  - Security groups"
    echo "  - Subnets"
    echo "  - VPCs"
    echo "  - CloudWatch dashboard"
    echo "  - State file"
    echo ""
    echo "Cost Impact:"
    echo "  - Transit Gateway hourly charges stopped"
    echo "  - Data processing charges stopped"
    echo "  - Cross-region data transfer charges stopped"
    echo ""
    echo "All resources have been successfully removed."
    echo "=================================="
}

# Function to handle cleanup errors
handle_cleanup_errors() {
    warning "Some resources may not have been deleted successfully."
    echo "This can happen if:"
    echo "  - Resources were already deleted manually"
    echo "  - Network dependencies prevent deletion"
    echo "  - AWS service limits are preventing deletion"
    echo ""
    echo "Please check the AWS console to verify all resources are cleaned up."
    echo "You may need to manually delete any remaining resources."
}

# Main cleanup function
cleanup() {
    log "Starting multi-region Transit Gateway cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN MODE - No resources will be deleted"
        log "The following resources would be deleted:"
        echo "  - Cross-region routes"
        echo "  - Route table associations"
        echo "  - Custom route tables"
        echo "  - Transit Gateway peering attachment"
        echo "  - VPC attachments"
        echo "  - Transit Gateways"
        echo "  - Security groups"
        echo "  - Subnets"
        echo "  - VPCs"
        echo "  - CloudWatch dashboard"
        echo "  - State file"
        return 0
    fi
    
    # Delete resources in reverse order of creation
    local cleanup_error=false
    
    # Delete application-level resources first
    delete_cross_region_routes || cleanup_error=true
    delete_route_table_associations || cleanup_error=true
    delete_route_tables || cleanup_error=true
    
    # Delete Transit Gateway resources
    delete_peering_attachment || cleanup_error=true
    delete_vpc_attachments || cleanup_error=true
    delete_transit_gateways || cleanup_error=true
    
    # Delete networking resources
    delete_security_groups || cleanup_error=true
    delete_subnets || cleanup_error=true
    delete_vpcs || cleanup_error=true
    
    # Delete monitoring resources
    delete_monitoring || cleanup_error=true
    
    # Clean up state file
    cleanup_state_file || cleanup_error=true
    
    if [[ "$cleanup_error" == "true" ]]; then
        handle_cleanup_errors
    else
        success "Multi-region Transit Gateway cleanup completed successfully!"
    fi
    
    # Display summary
    display_cleanup_summary
}

# Main script execution
main() {
    check_prerequisites
    load_state
    confirm_deletion
    cleanup
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may not have been deleted."; exit 1' INT TERM

# Execute main function
main "$@"