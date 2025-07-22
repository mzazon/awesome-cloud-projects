#!/bin/bash

# =============================================================================
# AWS Site-to-Site VPN Cleanup Script
# =============================================================================
# This script safely removes all AWS resources created by the deploy.sh script
# It reads the state file to ensure complete cleanup
# =============================================================================

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS CLI configuration
validate_aws_cli() {
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "AWS CLI validation successful"
}

# Function to find and load state file
find_state_file() {
    # Check if state file was provided as argument
    if [ $# -eq 1 ]; then
        STATE_FILE="$1"
        if [ ! -f "$STATE_FILE" ]; then
            error "State file not found: $STATE_FILE"
            exit 1
        fi
    else
        # Look for state files in /tmp
        STATE_FILES=$(find /tmp -name "vpn-deployment-state-*.json" 2>/dev/null)
        
        if [ -z "$STATE_FILES" ]; then
            warn "No state files found in /tmp"
            echo "Available options:"
            echo "1. Provide state file path as argument: $0 <state_file>"
            echo "2. Manual cleanup (will prompt for each resource type)"
            echo ""
            read -p "Choose option (1 or 2): " choice
            
            case $choice in
                1)
                    read -p "Enter state file path: " STATE_FILE
                    if [ ! -f "$STATE_FILE" ]; then
                        error "State file not found: $STATE_FILE"
                        exit 1
                    fi
                    ;;
                2)
                    manual_cleanup
                    exit 0
                    ;;
                *)
                    error "Invalid choice"
                    exit 1
                    ;;
            esac
        else
            # Multiple state files found
            echo "Multiple state files found:"
            echo "$STATE_FILES" | nl
            echo ""
            read -p "Enter the number of the state file to use: " choice
            
            STATE_FILE=$(echo "$STATE_FILES" | sed -n "${choice}p")
            if [ -z "$STATE_FILE" ]; then
                error "Invalid choice"
                exit 1
            fi
        fi
    fi
    
    export STATE_FILE
    log "Using state file: $STATE_FILE"
}

# Function to load configuration from state file
load_state() {
    if [ ! -f "$STATE_FILE" ]; then
        error "State file not found: $STATE_FILE"
        exit 1
    fi
    
    # Load variables from state file
    export AWS_REGION=$(jq -r '.aws_region' "$STATE_FILE")
    export VPC_ID=$(jq -r '.vpc_id' "$STATE_FILE")
    export IGW_ID=$(jq -r '.igw_id' "$STATE_FILE")
    export PUB_SUBNET_ID=$(jq -r '.pub_subnet_id' "$STATE_FILE")
    export PRIV_SUBNET_ID=$(jq -r '.priv_subnet_id' "$STATE_FILE")
    export VPN_RT_ID=$(jq -r '.vpn_rt_id' "$STATE_FILE")
    export MAIN_RT_ID=$(jq -r '.main_rt_id' "$STATE_FILE")
    export CGW_ID=$(jq -r '.cgw_id' "$STATE_FILE")
    export VGW_ID=$(jq -r '.vgw_id' "$STATE_FILE")
    export VPN_ID=$(jq -r '.vpn_id' "$STATE_FILE")
    export SG_ID=$(jq -r '.sg_id' "$STATE_FILE")
    export INSTANCE_ID=$(jq -r '.instance_id' "$STATE_FILE")
    export DASHBOARD_NAME=$(jq -r '.dashboard_name' "$STATE_FILE")
    
    log "State loaded successfully"
    info "AWS Region: $AWS_REGION"
    info "VPC ID: $VPC_ID"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warn "This will permanently delete all AWS resources created by the VPN deployment!"
    echo "Resources to be deleted:"
    echo "- VPC: $VPC_ID"
    echo "- VPN Connection: $VPN_ID"
    echo "- Customer Gateway: $CGW_ID"
    echo "- Virtual Private Gateway: $VGW_ID"
    
    if [ "$INSTANCE_ID" != "null" ] && [ -n "$INSTANCE_ID" ]; then
        echo "- Test Instance: $INSTANCE_ID"
    fi
    
    if [ "$DASHBOARD_NAME" != "null" ] && [ -n "$DASHBOARD_NAME" ]; then
        echo "- CloudWatch Dashboard: $DASHBOARD_NAME"
    fi
    
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        info "Cleanup cancelled"
        exit 0
    fi
}

# Function to delete CloudWatch dashboard
delete_dashboard() {
    if [ "$DASHBOARD_NAME" != "null" ] && [ -n "$DASHBOARD_NAME" ]; then
        log "Deleting CloudWatch dashboard..."
        
        aws cloudwatch delete-dashboards \
            --region "$AWS_REGION" \
            --dashboard-names "$DASHBOARD_NAME" >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            log "CloudWatch dashboard deleted: $DASHBOARD_NAME"
        else
            warn "Failed to delete CloudWatch dashboard (may not exist)"
        fi
    fi
}

# Function to terminate EC2 instance
terminate_instance() {
    if [ "$INSTANCE_ID" != "null" ] && [ -n "$INSTANCE_ID" ]; then
        log "Terminating test instance..."
        
        # Check if instance exists
        if aws ec2 describe-instances \
            --region "$AWS_REGION" \
            --instance-ids "$INSTANCE_ID" \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text >/dev/null 2>&1; then
            
            aws ec2 terminate-instances \
                --region "$AWS_REGION" \
                --instance-ids "$INSTANCE_ID" >/dev/null
            
            if [ $? -eq 0 ]; then
                log "Instance termination initiated: $INSTANCE_ID"
                
                # Wait for instance termination
                info "Waiting for instance termination..."
                aws ec2 wait instance-terminated \
                    --region "$AWS_REGION" \
                    --instance-ids "$INSTANCE_ID"
                
                if [ $? -eq 0 ]; then
                    log "Instance terminated successfully"
                else
                    warn "Instance termination wait timed out"
                fi
            else
                warn "Failed to terminate instance"
            fi
        else
            warn "Instance not found (may already be terminated)"
        fi
    fi
}

# Function to delete VPN connection
delete_vpn_connection() {
    if [ "$VPN_ID" != "null" ] && [ -n "$VPN_ID" ]; then
        log "Deleting VPN connection..."
        
        # Check if VPN connection exists
        if aws ec2 describe-vpn-connections \
            --region "$AWS_REGION" \
            --vpn-connection-ids "$VPN_ID" \
            --query 'VpnConnections[0].State' \
            --output text >/dev/null 2>&1; then
            
            aws ec2 delete-vpn-connection \
                --region "$AWS_REGION" \
                --vpn-connection-id "$VPN_ID" >/dev/null
            
            if [ $? -eq 0 ]; then
                log "VPN connection deletion initiated: $VPN_ID"
                
                # Wait for VPN connection to be deleted
                info "Waiting for VPN connection deletion..."
                local timeout=300
                local counter=0
                
                while [ $counter -lt $timeout ]; do
                    state=$(aws ec2 describe-vpn-connections \
                        --region "$AWS_REGION" \
                        --vpn-connection-ids "$VPN_ID" \
                        --query 'VpnConnections[0].State' \
                        --output text 2>/dev/null || echo "deleted")
                    
                    if [ "$state" == "deleted" ]; then
                        log "VPN connection deleted successfully"
                        break
                    fi
                    
                    sleep 10
                    counter=$((counter + 10))
                done
                
                if [ $counter -ge $timeout ]; then
                    warn "VPN connection deletion timed out"
                fi
            else
                warn "Failed to delete VPN connection"
            fi
        else
            warn "VPN connection not found (may already be deleted)"
        fi
    fi
}

# Function to clean up VPN gateway
cleanup_vpn_gateway() {
    if [ "$VGW_ID" != "null" ] && [ -n "$VGW_ID" ]; then
        log "Cleaning up Virtual Private Gateway..."
        
        # Check if VGW exists
        if aws ec2 describe-vpn-gateways \
            --region "$AWS_REGION" \
            --vpn-gateway-ids "$VGW_ID" \
            --query 'VpnGateways[0].State' \
            --output text >/dev/null 2>&1; then
            
            # Detach VPN gateway from VPC
            aws ec2 detach-vpn-gateway \
                --region "$AWS_REGION" \
                --vpn-gateway-id "$VGW_ID" \
                --vpc-id "$VPC_ID" >/dev/null 2>&1
            
            if [ $? -eq 0 ]; then
                log "VPN gateway detached from VPC"
                
                # Wait for detachment
                sleep 30
            else
                warn "Failed to detach VPN gateway (may not be attached)"
            fi
            
            # Delete VPN gateway
            aws ec2 delete-vpn-gateway \
                --region "$AWS_REGION" \
                --vpn-gateway-id "$VGW_ID" >/dev/null
            
            if [ $? -eq 0 ]; then
                log "Virtual Private Gateway deleted: $VGW_ID"
            else
                warn "Failed to delete Virtual Private Gateway"
            fi
        else
            warn "Virtual Private Gateway not found (may already be deleted)"
        fi
    fi
}

# Function to delete Customer Gateway
delete_customer_gateway() {
    if [ "$CGW_ID" != "null" ] && [ -n "$CGW_ID" ]; then
        log "Deleting Customer Gateway..."
        
        # Check if CGW exists
        if aws ec2 describe-customer-gateways \
            --region "$AWS_REGION" \
            --customer-gateway-ids "$CGW_ID" \
            --query 'CustomerGateways[0].State' \
            --output text >/dev/null 2>&1; then
            
            aws ec2 delete-customer-gateway \
                --region "$AWS_REGION" \
                --customer-gateway-id "$CGW_ID" >/dev/null
            
            if [ $? -eq 0 ]; then
                log "Customer Gateway deleted: $CGW_ID"
            else
                warn "Failed to delete Customer Gateway"
            fi
        else
            warn "Customer Gateway not found (may already be deleted)"
        fi
    fi
}

# Function to delete security group
delete_security_group() {
    if [ "$SG_ID" != "null" ] && [ -n "$SG_ID" ]; then
        log "Deleting security group..."
        
        # Check if security group exists
        if aws ec2 describe-security-groups \
            --region "$AWS_REGION" \
            --group-ids "$SG_ID" \
            --query 'SecurityGroups[0].GroupId' \
            --output text >/dev/null 2>&1; then
            
            aws ec2 delete-security-group \
                --region "$AWS_REGION" \
                --group-id "$SG_ID" >/dev/null
            
            if [ $? -eq 0 ]; then
                log "Security group deleted: $SG_ID"
            else
                warn "Failed to delete security group"
            fi
        else
            warn "Security group not found (may already be deleted)"
        fi
    fi
}

# Function to clean up VPC resources
cleanup_vpc_resources() {
    log "Cleaning up VPC resources..."
    
    # Detach and delete internet gateway
    if [ "$IGW_ID" != "null" ] && [ -n "$IGW_ID" ]; then
        if aws ec2 describe-internet-gateways \
            --region "$AWS_REGION" \
            --internet-gateway-ids "$IGW_ID" \
            --query 'InternetGateways[0].InternetGatewayId' \
            --output text >/dev/null 2>&1; then
            
            aws ec2 detach-internet-gateway \
                --region "$AWS_REGION" \
                --internet-gateway-id "$IGW_ID" \
                --vpc-id "$VPC_ID" >/dev/null 2>&1
            
            aws ec2 delete-internet-gateway \
                --region "$AWS_REGION" \
                --internet-gateway-id "$IGW_ID" >/dev/null
            
            if [ $? -eq 0 ]; then
                log "Internet Gateway deleted: $IGW_ID"
            else
                warn "Failed to delete Internet Gateway"
            fi
        else
            warn "Internet Gateway not found (may already be deleted)"
        fi
    fi
    
    # Delete route tables
    if [ "$VPN_RT_ID" != "null" ] && [ -n "$VPN_RT_ID" ]; then
        if aws ec2 describe-route-tables \
            --region "$AWS_REGION" \
            --route-table-ids "$VPN_RT_ID" \
            --query 'RouteTables[0].RouteTableId' \
            --output text >/dev/null 2>&1; then
            
            # Disassociate route table
            ASSOCIATION_ID=$(aws ec2 describe-route-tables \
                --region "$AWS_REGION" \
                --route-table-ids "$VPN_RT_ID" \
                --query 'RouteTables[0].Associations[0].RouteTableAssociationId' \
                --output text 2>/dev/null)
            
            if [ "$ASSOCIATION_ID" != "null" ] && [ -n "$ASSOCIATION_ID" ]; then
                aws ec2 disassociate-route-table \
                    --region "$AWS_REGION" \
                    --association-id "$ASSOCIATION_ID" >/dev/null 2>&1
            fi
            
            aws ec2 delete-route-table \
                --region "$AWS_REGION" \
                --route-table-id "$VPN_RT_ID" >/dev/null
            
            if [ $? -eq 0 ]; then
                log "VPN route table deleted: $VPN_RT_ID"
            else
                warn "Failed to delete VPN route table"
            fi
        else
            warn "VPN route table not found (may already be deleted)"
        fi
    fi
    
    # Delete subnets
    for subnet_id in "$PUB_SUBNET_ID" "$PRIV_SUBNET_ID"; do
        if [ "$subnet_id" != "null" ] && [ -n "$subnet_id" ]; then
            if aws ec2 describe-subnets \
                --region "$AWS_REGION" \
                --subnet-ids "$subnet_id" \
                --query 'Subnets[0].SubnetId' \
                --output text >/dev/null 2>&1; then
                
                aws ec2 delete-subnet \
                    --region "$AWS_REGION" \
                    --subnet-id "$subnet_id" >/dev/null
                
                if [ $? -eq 0 ]; then
                    log "Subnet deleted: $subnet_id"
                else
                    warn "Failed to delete subnet: $subnet_id"
                fi
            else
                warn "Subnet not found (may already be deleted): $subnet_id"
            fi
        fi
    done
    
    # Delete VPC
    if [ "$VPC_ID" != "null" ] && [ -n "$VPC_ID" ]; then
        if aws ec2 describe-vpcs \
            --region "$AWS_REGION" \
            --vpc-ids "$VPC_ID" \
            --query 'Vpcs[0].VpcId' \
            --output text >/dev/null 2>&1; then
            
            aws ec2 delete-vpc \
                --region "$AWS_REGION" \
                --vpc-id "$VPC_ID" >/dev/null
            
            if [ $? -eq 0 ]; then
                log "VPC deleted: $VPC_ID"
            else
                warn "Failed to delete VPC"
            fi
        else
            warn "VPC not found (may already be deleted)"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove VPN configuration file
    if [ -f "vpn-config.txt" ]; then
        rm -f vpn-config.txt
        log "VPN configuration file removed"
    fi
    
    # Remove state file
    if [ -f "$STATE_FILE" ]; then
        rm -f "$STATE_FILE"
        log "State file removed: $STATE_FILE"
    fi
}

# Function for manual cleanup when no state file is available
manual_cleanup() {
    log "Starting manual cleanup..."
    
    # Get AWS region
    AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        read -p "Enter AWS region: " AWS_REGION
    fi
    
    echo "Manual cleanup options:"
    echo "1. Delete all VPN connections"
    echo "2. Delete all Customer Gateways"
    echo "3. Delete all Virtual Private Gateways"
    echo "4. Delete VPCs with 'vpn-demo' tag"
    echo "5. Delete CloudWatch dashboards starting with 'VPN-Monitoring'"
    echo "6. All of the above"
    echo ""
    read -p "Choose option (1-6): " choice
    
    case $choice in
        1|6)
            log "Deleting VPN connections..."
            VPN_IDS=$(aws ec2 describe-vpn-connections \
                --region "$AWS_REGION" \
                --query 'VpnConnections[?State==`available`].VpnConnectionId' \
                --output text)
            
            for vpn_id in $VPN_IDS; do
                aws ec2 delete-vpn-connection \
                    --region "$AWS_REGION" \
                    --vpn-connection-id "$vpn_id" >/dev/null
                log "Deleted VPN connection: $vpn_id"
            done
            ;;& # Continue to next case
        2|6)
            log "Deleting Customer Gateways..."
            CGW_IDS=$(aws ec2 describe-customer-gateways \
                --region "$AWS_REGION" \
                --query 'CustomerGateways[?State==`available`].CustomerGatewayId' \
                --output text)
            
            for cgw_id in $CGW_IDS; do
                aws ec2 delete-customer-gateway \
                    --region "$AWS_REGION" \
                    --customer-gateway-id "$cgw_id" >/dev/null
                log "Deleted Customer Gateway: $cgw_id"
            done
            ;;& # Continue to next case
        3|6)
            log "Deleting Virtual Private Gateways..."
            VGW_IDS=$(aws ec2 describe-vpn-gateways \
                --region "$AWS_REGION" \
                --query 'VpnGateways[?State==`available`].VpnGatewayId' \
                --output text)
            
            for vgw_id in $VGW_IDS; do
                aws ec2 delete-vpn-gateway \
                    --region "$AWS_REGION" \
                    --vpn-gateway-id "$vgw_id" >/dev/null
                log "Deleted Virtual Private Gateway: $vgw_id"
            done
            ;;& # Continue to next case
        4|6)
            log "Deleting VPCs with vpn-demo tag..."
            VPC_IDS=$(aws ec2 describe-vpcs \
                --region "$AWS_REGION" \
                --filters "Name=tag:Project,Values=vpn-demo" \
                --query 'Vpcs[].VpcId' \
                --output text)
            
            for vpc_id in $VPC_IDS; do
                warn "Found VPC with vpn-demo tag: $vpc_id"
                warn "Manual VPC cleanup required (contains multiple resources)"
            done
            ;;& # Continue to next case
        5|6)
            log "Deleting CloudWatch dashboards..."
            DASHBOARD_NAMES=$(aws cloudwatch list-dashboards \
                --region "$AWS_REGION" \
                --query 'DashboardEntries[?starts_with(DashboardName, `VPN-Monitoring`)].DashboardName' \
                --output text)
            
            for dashboard in $DASHBOARD_NAMES; do
                aws cloudwatch delete-dashboards \
                    --region "$AWS_REGION" \
                    --dashboard-names "$dashboard" >/dev/null
                log "Deleted dashboard: $dashboard"
            done
            ;;
        *)
            error "Invalid choice"
            exit 1
            ;;
    esac
    
    log "Manual cleanup completed"
}

# Main execution function
main() {
    log "Starting AWS Site-to-Site VPN cleanup..."
    
    # Check if jq is installed
    if ! command_exists jq; then
        error "jq is required but not installed. Please install jq first."
        exit 1
    fi
    
    validate_aws_cli
    find_state_file "$@"
    load_state
    confirm_deletion
    
    # Clean up resources in reverse order
    delete_dashboard
    terminate_instance
    delete_vpn_connection
    cleanup_vpn_gateway
    delete_customer_gateway
    delete_security_group
    cleanup_vpc_resources
    cleanup_local_files
    
    log "Cleanup completed successfully!"
    info "All AWS resources have been removed"
}

# Run main function
main "$@"