#!/bin/bash

# Destroy script for Hyperledger Fabric Applications on Amazon Managed Blockchain
# Recipe: hyperledger-fabric-applications-managed-blockchain
# Description: Safely cleans up all resources created by the deployment script

set -euo pipefail

# Colors for output
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
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Cleanup on script exit
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Script failed with exit code $exit_code. Some resources may not have been cleaned up."
        echo "Please check the AWS console and manually remove any remaining resources."
    fi
}

trap cleanup_on_exit EXIT

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    success "Prerequisites check completed"
}

# Load state from deployment
load_state() {
    log "Loading deployment state..."
    
    # Try to find state file
    local state_file=""
    
    # Check if state file is provided as argument
    if [ $# -gt 0 ] && [ -f "$1" ]; then
        state_file="$1"
        log "Using provided state file: $state_file"
    else
        # Look for recent state files
        local recent_state=$(find /tmp -name "blockchain-deploy-state-*.env" -mtime -1 2>/dev/null | head -1)
        
        if [ -n "$recent_state" ] && [ -f "$recent_state" ]; then
            state_file="$recent_state"
            log "Found recent state file: $state_file"
        else
            warning "No state file found. Will attempt to discover resources interactively."
            return 1
        fi
    fi
    
    # Load variables from state file
    if [ -f "$state_file" ]; then
        source "$state_file"
        export STATE_FILE="$state_file"
        
        log "Loaded state from: $state_file"
        log "  AWS_REGION: ${AWS_REGION:-not set}"
        log "  NETWORK_NAME: ${NETWORK_NAME:-not set}"
        log "  MEMBER_NAME: ${MEMBER_NAME:-not set}"
        log "  RANDOM_SUFFIX: ${RANDOM_SUFFIX:-not set}"
        
        success "State loaded successfully"
        return 0
    else
        warning "State file not found or not readable"
        return 1
    fi
}

# Interactive resource discovery
discover_resources() {
    log "Attempting to discover blockchain resources..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not set. Please set AWS_REGION or configure default region."
    fi
    
    # Try to find networks created today
    log "Searching for recent blockchain networks..."
    local networks=$(aws managedblockchain list-networks \
        --query 'Networks[?contains(Name, `fabric-network`)].[Id,Name,Status]' \
        --output table 2>/dev/null || echo "")
    
    if [ -n "$networks" ] && [ "$networks" != "" ]; then
        echo "Found blockchain networks:"
        echo "$networks"
        echo
        
        # Get user input for network selection
        read -p "Enter the Network ID to delete (or 'skip' to skip blockchain cleanup): " user_network_id
        
        if [ "$user_network_id" != "skip" ] && [ -n "$user_network_id" ]; then
            export NETWORK_ID="$user_network_id"
            
            # Get network name
            export NETWORK_NAME=$(aws managedblockchain get-network \
                --network-id "$NETWORK_ID" \
                --query 'Network.Name' \
                --output text 2>/dev/null || echo "unknown")
            
            log "Selected network: $NETWORK_NAME ($NETWORK_ID)"
        else
            warning "Skipping blockchain network cleanup"
            export NETWORK_ID=""
        fi
    else
        warning "No blockchain networks found"
        export NETWORK_ID=""
    fi
    
    # Try to find VPCs with blockchain tags
    log "Searching for blockchain VPCs..."
    local vpcs=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Purpose,Values=ManagedBlockchain" \
        --query 'Vpcs[*].[VpcId,Tags[?Key==`Name`].Value|[0]]' \
        --output table 2>/dev/null || echo "")
    
    if [ -n "$vpcs" ] && [ "$vpcs" != "" ]; then
        echo "Found VPCs with blockchain tags:"
        echo "$vpcs"
        echo
        
        read -p "Enter the VPC ID to delete (or 'skip' to skip VPC cleanup): " user_vpc_id
        
        if [ "$user_vpc_id" != "skip" ] && [ -n "$user_vpc_id" ]; then
            export VPC_ID="$user_vpc_id"
            log "Selected VPC: $VPC_ID"
        else
            warning "Skipping VPC cleanup"
            export VPC_ID=""
        fi
    else
        warning "No blockchain VPCs found"
        export VPC_ID=""
    fi
    
    success "Resource discovery completed"
}

# Confirmation prompt
confirm_destruction() {
    echo
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "This script will permanently delete the following resources:"
    echo
    echo "Blockchain Resources:"
    echo "  • Network: ${NETWORK_NAME:-N/A} (${NETWORK_ID:-N/A})"
    echo "  • All associated peer nodes and members"
    echo
    echo "Infrastructure Resources:"
    echo "  • VPC: ${VPC_ID:-N/A}"
    echo "  • All associated subnets, security groups, and instances"
    echo "  • Internet Gateway and routing tables"
    echo
    echo "Local Resources:"
    echo "  • Client application directory: ./fabric-client-app"
    echo "  • State file: ${STATE_FILE:-N/A}"
    echo
    warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Operation cancelled by user"
        exit 0
    fi
    
    success "Confirmation received. Proceeding with cleanup..."
}

# Delete blockchain network resources
delete_blockchain_resources() {
    if [ -z "${NETWORK_ID:-}" ]; then
        warning "No network ID available. Skipping blockchain cleanup."
        return 0
    fi
    
    log "Deleting blockchain network resources..."
    
    # Get member information
    local members=$(aws managedblockchain list-members \
        --network-id "$NETWORK_ID" \
        --query 'Members[*].[Id,Name]' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$members" ]; then
        echo "$members" | while read -r member_id member_name; do
            if [ -n "$member_id" ] && [ "$member_id" != "None" ]; then
                log "Processing member: $member_name ($member_id)"
                
                # Delete all nodes for this member
                local nodes=$(aws managedblockchain list-nodes \
                    --network-id "$NETWORK_ID" \
                    --member-id "$member_id" \
                    --query 'Nodes[*].Id' \
                    --output text 2>/dev/null || echo "")
                
                if [ -n "$nodes" ] && [ "$nodes" != "" ]; then
                    for node_id in $nodes; do
                        if [ "$node_id" != "None" ]; then
                            log "Deleting node: $node_id"
                            aws managedblockchain delete-node \
                                --network-id "$NETWORK_ID" \
                                --member-id "$member_id" \
                                --node-id "$node_id" 2>/dev/null || warning "Failed to delete node $node_id"
                        fi
                    done
                    
                    # Wait for nodes to be deleted
                    log "Waiting for nodes to be deleted..."
                    local max_attempts=20
                    local attempt=1
                    
                    while [ $attempt -le $max_attempts ]; do
                        local remaining_nodes=$(aws managedblockchain list-nodes \
                            --network-id "$NETWORK_ID" \
                            --member-id "$member_id" \
                            --query 'length(Nodes)' \
                            --output text 2>/dev/null || echo "0")
                        
                        if [ "$remaining_nodes" = "0" ]; then
                            success "All nodes deleted"
                            break
                        else
                            log "Waiting for node deletion... ($attempt/$max_attempts)"
                            sleep 30
                            ((attempt++))
                        fi
                    done
                fi
                
                # Delete the member
                log "Deleting member: $member_name"
                aws managedblockchain delete-member \
                    --network-id "$NETWORK_ID" \
                    --member-id "$member_id" 2>/dev/null || warning "Failed to delete member $member_id"
            fi
        done
        
        # Wait a bit for member deletion to process
        log "Waiting for member deletion to complete..."
        sleep 60
    fi
    
    # Delete the network
    log "Deleting blockchain network: ${NETWORK_NAME}"
    aws managedblockchain delete-network \
        --network-id "$NETWORK_ID" 2>/dev/null && success "Network deletion initiated" || warning "Failed to delete network"
    
    # Note: We don't wait for network deletion as it can take a very long time
    log "Network deletion initiated. This may take 30+ minutes to complete."
    
    success "Blockchain resources cleanup initiated"
}

# Delete VPC and related resources
delete_vpc_resources() {
    if [ -z "${VPC_ID:-}" ]; then
        warning "No VPC ID available. Skipping VPC cleanup."
        return 0
    fi
    
    log "Deleting VPC and related resources..."
    
    # Terminate EC2 instances
    log "Terminating EC2 instances..."
    local instances=$(aws ec2 describe-instances \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running,stopped,stopping" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$instances" ] && [ "$instances" != "" ]; then
        for instance_id in $instances; do
            if [ "$instance_id" != "None" ]; then
                log "Terminating instance: $instance_id"
                aws ec2 terminate-instances --instance-ids "$instance_id" > /dev/null 2>&1 || warning "Failed to terminate instance $instance_id"
            fi
        done
        
        # Wait for instances to terminate
        if [ -n "$instances" ]; then
            log "Waiting for instances to terminate..."
            aws ec2 wait instance-terminated --instance-ids $instances 2>/dev/null || warning "Timeout waiting for instance termination"
        fi
    fi
    
    # Delete VPC endpoints
    log "Deleting VPC endpoints..."
    local vpc_endpoints=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'VpcEndpoints[*].VpcEndpointId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$vpc_endpoints" ] && [ "$vpc_endpoints" != "" ]; then
        for endpoint_id in $vpc_endpoints; do
            if [ "$endpoint_id" != "None" ]; then
                log "Deleting VPC endpoint: $endpoint_id"
                aws ec2 delete-vpc-endpoint --vpc-endpoint-id "$endpoint_id" > /dev/null 2>&1 || warning "Failed to delete VPC endpoint $endpoint_id"
            fi
        done
    fi
    
    # Delete NAT gateways
    log "Deleting NAT gateways..."
    local nat_gateways=$(aws ec2 describe-nat-gateways \
        --filter "Name=vpc-id,Values=$VPC_ID" \
        --query 'NatGateways[?State==`available`].NatGatewayId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$nat_gateways" ] && [ "$nat_gateways" != "" ]; then
        for nat_id in $nat_gateways; do
            if [ "$nat_id" != "None" ]; then
                log "Deleting NAT gateway: $nat_id"
                aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id" > /dev/null 2>&1 || warning "Failed to delete NAT gateway $nat_id"
            fi
        done
    fi
    
    # Delete security groups (except default)
    log "Deleting security groups..."
    local security_groups=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$security_groups" ] && [ "$security_groups" != "" ]; then
        for sg_id in $security_groups; do
            if [ "$sg_id" != "None" ]; then
                log "Deleting security group: $sg_id"
                aws ec2 delete-security-group --group-id "$sg_id" > /dev/null 2>&1 || warning "Failed to delete security group $sg_id"
            fi
        done
    fi
    
    # Detach and delete internet gateways
    log "Detaching and deleting internet gateways..."
    local internet_gateways=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
        --query 'InternetGateways[*].InternetGatewayId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$internet_gateways" ] && [ "$internet_gateways" != "" ]; then
        for igw_id in $internet_gateways; do
            if [ "$igw_id" != "None" ]; then
                log "Detaching internet gateway: $igw_id"
                aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$VPC_ID" > /dev/null 2>&1 || warning "Failed to detach internet gateway $igw_id"
                
                log "Deleting internet gateway: $igw_id"
                aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" > /dev/null 2>&1 || warning "Failed to delete internet gateway $igw_id"
            fi
        done
    fi
    
    # Delete subnets
    log "Deleting subnets..."
    local subnets=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'Subnets[*].SubnetId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$subnets" ] && [ "$subnets" != "" ]; then
        for subnet_id in $subnets; do
            if [ "$subnet_id" != "None" ]; then
                log "Deleting subnet: $subnet_id"
                aws ec2 delete-subnet --subnet-id "$subnet_id" > /dev/null 2>&1 || warning "Failed to delete subnet $subnet_id"
            fi
        done
    fi
    
    # Delete custom route tables
    log "Deleting route tables..."
    local route_tables=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$route_tables" ] && [ "$route_tables" != "" ]; then
        for rt_id in $route_tables; do
            if [ "$rt_id" != "None" ]; then
                log "Deleting route table: $rt_id"
                aws ec2 delete-route-table --route-table-id "$rt_id" > /dev/null 2>&1 || warning "Failed to delete route table $rt_id"
            fi
        done
    fi
    
    # Delete VPC
    log "Deleting VPC: $VPC_ID"
    aws ec2 delete-vpc --vpc-id "$VPC_ID" > /dev/null 2>&1 && success "VPC deleted successfully" || warning "Failed to delete VPC"
    
    success "VPC resources cleanup completed"
}

# Delete local resources
delete_local_resources() {
    log "Cleaning up local resources..."
    
    # Remove client application directory
    if [ -d "./fabric-client-app" ]; then
        log "Removing client application directory..."
        rm -rf "./fabric-client-app" && success "Client application directory removed" || warning "Failed to remove client application directory"
    fi
    
    # Remove state file
    if [ -n "${STATE_FILE:-}" ] && [ -f "$STATE_FILE" ]; then
        log "Removing state file: $STATE_FILE"
        rm -f "$STATE_FILE" && success "State file removed" || warning "Failed to remove state file"
    fi
    
    success "Local resources cleanup completed"
}

# Display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo
    echo "✅ Completed cleanup operations:"
    
    if [ -n "${NETWORK_ID:-}" ]; then
        echo "  • Blockchain network deletion initiated: ${NETWORK_NAME:-N/A}"
        echo "  • All associated peer nodes and members"
    else
        echo "  • No blockchain resources to clean up"
    fi
    
    if [ -n "${VPC_ID:-}" ]; then
        echo "  • VPC and all associated resources: $VPC_ID"
        echo "  • EC2 instances, security groups, subnets"
        echo "  • Internet gateways and route tables"
    else
        echo "  • No VPC resources to clean up"
    fi
    
    echo "  • Local client application directory"
    echo "  • Deployment state files"
    echo
    
    warning "Important Notes:"
    echo "• Blockchain network deletion may take 30+ minutes to complete"
    echo "• Monitor AWS console to verify all resources are deleted"
    echo "• Check AWS billing for any remaining charges"
    echo
    
    success "Cleanup process completed!"
}

# Main cleanup function
main() {
    echo "🧹 Starting Hyperledger Fabric Blockchain Cleanup"
    echo "================================================="
    echo
    
    check_prerequisites
    
    # Try to load state, fallback to discovery if needed
    if ! load_state "$@"; then
        discover_resources
    fi
    
    confirm_destruction
    delete_blockchain_resources
    delete_vpc_resources
    delete_local_resources
    display_cleanup_summary
    
    echo
    success "All cleanup operations completed!"
}

# Help function
show_help() {
    echo "Usage: $0 [state-file]"
    echo
    echo "Arguments:"
    echo "  state-file    Optional path to deployment state file"
    echo
    echo "Examples:"
    echo "  $0                                     # Auto-discover resources"
    echo "  $0 /tmp/blockchain-deploy-state.env   # Use specific state file"
    echo
    echo "This script safely removes all resources created by the deployment script."
    echo "If no state file is provided, it will attempt to discover resources interactively."
}

# Handle help option
if [ $# -gt 0 ] && [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# Run main function
main "$@"