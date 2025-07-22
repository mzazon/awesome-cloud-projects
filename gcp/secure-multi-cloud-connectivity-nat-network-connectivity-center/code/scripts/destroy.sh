#!/bin/bash

# GCP Secure Multi-Cloud Connectivity Cleanup Script
# Recipe: Secure Multi-Cloud Connectivity with Cloud NAT and Network Connectivity Center
# Provider: Google Cloud Platform
# Version: 1.0

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found"
        log "Please run: gcloud auth login"
        exit 1
    fi
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "${SKIP_CONFIRMATION:-false}" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will delete ALL resources created by the deployment script!"
    log_warning "This action is IRREVERSIBLE and will:"
    echo "  - Delete all VPC networks and subnets"
    echo "  - Remove Network Connectivity Center hub and spokes"
    echo "  - Delete VPN gateways and tunnels"
    echo "  - Remove Cloud NAT gateways and routers"
    echo "  - Delete all firewall rules"
    echo "  - Clean up all associated resources"
    echo
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    if [[ ! "$REPLY" =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
}

# Function to wait for operation completion
wait_for_operation() {
    local operation_name="$1"
    local max_wait="${2:-300}"  # Default 5 minutes
    local wait_time=0
    
    log "Waiting for operation: $operation_name"
    while [[ $wait_time -lt $max_wait ]]; do
        sleep 10
        wait_time=$((wait_time + 10))
        echo -n "."
    done
    echo
}

# Function to delete resource with retry
delete_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local additional_flags="$3"
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if gcloud "$resource_type" delete "$resource_name" $additional_flags --quiet 2>/dev/null; then
            log_success "Deleted $resource_type: $resource_name"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                log_warning "Failed to delete $resource_name, retrying in 10 seconds... (attempt $retry_count/$max_retries)"
                sleep 10
            else
                log_warning "Failed to delete $resource_name after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Function to remove Network Connectivity Center spokes
remove_ncc_spokes() {
    log "Removing Network Connectivity Center spokes..."
    
    # List existing spokes first
    local spokes
    spokes=$(gcloud network-connectivity spokes list \
        --hub "$HUB_NAME" \
        --global \
        --project="$PROJECT_ID" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$spokes" ]]; then
        for spoke in $spokes; do
            log "Deleting spoke: $spoke"
            delete_resource "network-connectivity spokes" "$spoke" "--hub $HUB_NAME --global --project=$PROJECT_ID"
        done
        
        # Wait for spokes to be fully deleted
        log "Waiting for spokes to be fully deleted..."
        sleep 30
    else
        log "No spokes found to delete"
    fi
    
    log_success "Network Connectivity Center spokes cleanup completed"
}

# Function to remove Network Connectivity Center hub
remove_ncc_hub() {
    log "Removing Network Connectivity Center hub..."
    
    if gcloud network-connectivity hubs describe "$HUB_NAME" --global --project="$PROJECT_ID" >/dev/null 2>&1; then
        delete_resource "network-connectivity hubs" "$HUB_NAME" "--global --project=$PROJECT_ID"
        
        # Wait for hub to be fully deleted
        log "Waiting for hub to be fully deleted..."
        sleep 30
    else
        log "Hub $HUB_NAME not found or already deleted"
    fi
    
    log_success "Network Connectivity Center hub deleted"
}

# Function to remove VPN infrastructure
remove_vpn_infrastructure() {
    log "Removing VPN infrastructure..."
    
    # Remove BGP peers from router
    local bgp_peers
    bgp_peers=$(gcloud compute routers describe hub-router \
        --region "$REGION" \
        --project="$PROJECT_ID" \
        --format="value(bgpPeers[].name)" 2>/dev/null || true)
    
    if [[ -n "$bgp_peers" ]]; then
        for peer in $bgp_peers; do
            log "Removing BGP peer: $peer"
            gcloud compute routers remove-bgp-peer hub-router \
                --peer-name "$peer" \
                --region "$REGION" \
                --project="$PROJECT_ID" \
                --quiet || log_warning "Failed to remove BGP peer: $peer"
        done
    fi
    
    # Delete VPN tunnels
    log "Deleting VPN tunnels..."
    local tunnels
    tunnels=$(gcloud compute vpn-tunnels list \
        --regions="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(name)" 2>/dev/null || true)
    
    for tunnel in $tunnels; do
        delete_resource "compute vpn-tunnels" "$tunnel" "--region $REGION --project=$PROJECT_ID"
    done
    
    # Delete VPN gateways
    log "Deleting VPN gateways..."
    local vpn_gateways
    vpn_gateways=$(gcloud compute vpn-gateways list \
        --regions="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(name)" 2>/dev/null || true)
    
    for gateway in $vpn_gateways; do
        delete_resource "compute vpn-gateways" "$gateway" "--region $REGION --project=$PROJECT_ID"
    done
    
    # Delete external VPN gateways
    log "Deleting external VPN gateways..."
    local external_gateways
    external_gateways=$(gcloud compute external-vpn-gateways list \
        --project="$PROJECT_ID" \
        --format="value(name)" 2>/dev/null || true)
    
    for gateway in $external_gateways; do
        delete_resource "compute external-vpn-gateways" "$gateway" "--project=$PROJECT_ID"
    done
    
    log_success "VPN infrastructure cleanup completed"
}

# Function to remove Cloud NAT gateways and routers
remove_cloud_nat_and_routers() {
    log "Removing Cloud NAT gateways and routers..."
    
    # List of router names to check
    local routers=("hub-router" "prod-router" "dev-router" "shared-router")
    
    for router in "${routers[@]}"; do
        if gcloud compute routers describe "$router" --region "$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
            # Delete NAT gateways first
            local nat_gateways
            nat_gateways=$(gcloud compute routers nats list \
                --router "$router" \
                --region "$REGION" \
                --project="$PROJECT_ID" \
                --format="value(name)" 2>/dev/null || true)
            
            for nat in $nat_gateways; do
                log "Deleting NAT gateway: $nat from router: $router"
                gcloud compute routers nats delete "$nat" \
                    --router "$router" \
                    --region "$REGION" \
                    --project="$PROJECT_ID" \
                    --quiet || log_warning "Failed to delete NAT gateway: $nat"
            done
            
            # Delete the router
            delete_resource "compute routers" "$router" "--region $REGION --project=$PROJECT_ID"
        else
            log "Router $router not found or already deleted"
        fi
    done
    
    log_success "Cloud NAT gateways and routers cleanup completed"
}

# Function to remove firewall rules
remove_firewall_rules() {
    log "Removing firewall rules..."
    
    # List of firewall rules created by the deployment
    local firewall_rules=(
        "hub-allow-vpn"
        "prod-allow-internal"
        "dev-allow-internal"
        "shared-allow-internal"
        "prod-allow-egress"
    )
    
    for rule in "${firewall_rules[@]}"; do
        if gcloud compute firewall-rules describe "$rule" --project="$PROJECT_ID" >/dev/null 2>&1; then
            delete_resource "compute firewall-rules" "$rule" "--project=$PROJECT_ID"
        else
            log "Firewall rule $rule not found or already deleted"
        fi
    done
    
    log_success "Firewall rules cleanup completed"
}

# Function to remove VPC networks and subnets
remove_vpc_networks() {
    log "Removing VPC networks and subnets..."
    
    # List of VPC networks to delete
    local vpc_networks=("$VPC_HUB_NAME" "$VPC_PROD_NAME" "$VPC_DEV_NAME" "$VPC_SHARED_NAME")
    
    for vpc in "${vpc_networks[@]}"; do
        if gcloud compute networks describe "$vpc" --project="$PROJECT_ID" >/dev/null 2>&1; then
            # Delete subnets first
            local subnets
            subnets=$(gcloud compute networks subnets list \
                --filter="network:$vpc" \
                --project="$PROJECT_ID" \
                --format="value(name,region)" 2>/dev/null || true)
            
            while IFS=$'\t' read -r subnet_name subnet_region; do
                if [[ -n "$subnet_name" && -n "$subnet_region" ]]; then
                    log "Deleting subnet: $subnet_name in region: $subnet_region"
                    delete_resource "compute networks subnets" "$subnet_name" "--region $subnet_region --project=$PROJECT_ID"
                fi
            done <<< "$subnets"
            
            # Delete the VPC network
            delete_resource "compute networks" "$vpc" "--project=$PROJECT_ID"
        else
            log "VPC network $vpc not found or already deleted"
        fi
    done
    
    log_success "VPC networks and subnets cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check if hub still exists
    if gcloud network-connectivity hubs describe "$HUB_NAME" --global --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_warning "Hub $HUB_NAME still exists"
    else
        log_success "Hub $HUB_NAME successfully deleted"
    fi
    
    # Check remaining VPC networks
    local remaining_vpcs
    remaining_vpcs=$(gcloud compute networks list \
        --filter="name:($VPC_HUB_NAME OR $VPC_PROD_NAME OR $VPC_DEV_NAME OR $VPC_SHARED_NAME)" \
        --project="$PROJECT_ID" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ "$remaining_vpcs" -eq 0 ]]; then
        log_success "All VPC networks successfully deleted"
    else
        log_warning "$remaining_vpcs VPC networks still exist"
    fi
    
    # Check remaining routers
    local remaining_routers
    remaining_routers=$(gcloud compute routers list \
        --regions="$REGION" \
        --project="$PROJECT_ID" \
        --filter="name:(hub-router OR prod-router OR dev-router OR shared-router)" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ "$remaining_routers" -eq 0 ]]; then
        log_success "All routers successfully deleted"
    else
        log_warning "$remaining_routers routers still exist"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "Cleanup process completed!"
    echo
    log "Cleanup Summary:"
    echo "✅ Network Connectivity Center hub and spokes removed"
    echo "✅ VPN gateways and tunnels deleted"
    echo "✅ Cloud NAT gateways and routers removed"
    echo "✅ Firewall rules deleted"
    echo "✅ VPC networks and subnets removed"
    echo
    log "All resources from the secure multi-cloud connectivity deployment have been cleaned up."
    echo
    log_warning "Note: Some resources may take additional time to be fully removed from your billing."
    log "You can verify complete cleanup in the Google Cloud Console."
}

# Main cleanup function
main() {
    log "Starting GCP Secure Multi-Cloud Connectivity cleanup..."
    
    # Prerequisites check
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    check_gcloud_auth
    
    # Set environment variables with defaults
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export HUB_NAME="${HUB_NAME:-multi-cloud-hub}"
    
    # Try to detect resource names from existing resources
    # If resources exist with standard pattern, use those names
    local existing_vpcs
    existing_vpcs=$(gcloud compute networks list \
        --project="$PROJECT_ID" \
        --filter="name~hub-vpc-.*" \
        --format="value(name)" 2>/dev/null | head -1)
    
    if [[ -n "$existing_vpcs" ]]; then
        # Extract suffix from existing VPC name
        RANDOM_SUFFIX=${existing_vpcs#hub-vpc-}
        export VPC_HUB_NAME="hub-vpc-${RANDOM_SUFFIX}"
        export VPC_PROD_NAME="prod-vpc-${RANDOM_SUFFIX}"
        export VPC_DEV_NAME="dev-vpc-${RANDOM_SUFFIX}"
        export VPC_SHARED_NAME="shared-vpc-${RANDOM_SUFFIX}"
        log "Detected existing resources with suffix: $RANDOM_SUFFIX"
    else
        # Use provided environment variables or ask user
        if [[ -z "${VPC_HUB_NAME:-}" ]]; then
            log_warning "Could not detect existing VPC resources."
            log "Please set the following environment variables or ensure resources exist:"
            log "  VPC_HUB_NAME, VPC_PROD_NAME, VPC_DEV_NAME, VPC_SHARED_NAME"
            log "Or run with the same random suffix used during deployment."
            exit 1
        fi
    fi
    
    # Validate required variables
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID is not set. Please set it or configure gcloud project."
        exit 1
    fi
    
    # Display configuration
    log "Configuration:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Hub Name: $HUB_NAME"
    echo "  VPC Hub Name: $VPC_HUB_NAME"
    echo "  VPC Prod Name: $VPC_PROD_NAME"
    echo "  VPC Dev Name: $VPC_DEV_NAME"
    echo "  VPC Shared Name: $VPC_SHARED_NAME"
    echo
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    # Confirm deletion
    confirm_deletion
    
    # Execute cleanup in reverse order of creation
    # This ensures dependencies are properly handled
    log "Starting cleanup process..."
    
    remove_ncc_spokes
    remove_ncc_hub
    remove_vpn_infrastructure
    remove_cloud_nat_and_routers
    remove_firewall_rules
    remove_vpc_networks
    
    # Final verification
    verify_cleanup
    display_cleanup_summary
}

# Trap errors and provide helpful message
trap 'log_error "Cleanup failed. Some resources may need manual deletion. Check the logs above for details."' ERR

# Run main function
main "$@"