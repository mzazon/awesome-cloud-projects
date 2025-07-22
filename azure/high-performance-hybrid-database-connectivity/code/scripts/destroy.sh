#!/bin/bash

# Azure ExpressRoute and Application Gateway Cleanup Script
# Recipe: High-Performance Hybrid Database Connectivity with ExpressRoute
# Version: 1.0
# Last Updated: 2025-07-12

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Default resource group name
DEFAULT_RESOURCE_GROUP="rg-hybrid-db-connectivity"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if subscription is set
    subscription_id=$(az account show --query id -o tsv)
    subscription_name=$(az account show --query name -o tsv)
    log "Using subscription: $subscription_name ($subscription_id)"
    
    log "Prerequisites check completed"
}

# Function to prompt for confirmation
confirm_deletion() {
    local resource_group="$1"
    
    warn "=== DESTRUCTIVE OPERATION WARNING ==="
    warn "This script will DELETE the following:"
    warn "  - Resource Group: $resource_group"
    warn "  - All resources within this resource group"
    warn "  - ExpressRoute Gateway (may take 15-20 minutes)"
    warn "  - Application Gateway and associated resources"
    warn "  - PostgreSQL Flexible Server and all data"
    warn "  - Virtual Network and all subnets"
    warn "  - Network Security Groups and Route Tables"
    warn "  - Private DNS zones and records"
    warn ""
    warn "THIS ACTION CANNOT BE UNDONE!"
    warn ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    read -p "Please type the resource group name '$resource_group' to confirm: " rg_confirmation
    
    if [ "$rg_confirmation" != "$resource_group" ]; then
        error "Resource group name confirmation failed. Cleanup cancelled."
        exit 1
    fi
    
    log "Deletion confirmed. Proceeding with cleanup..."
}

# Function to discover resource groups
discover_resource_groups() {
    log "Discovering resource groups related to hybrid database connectivity..."
    
    # Look for resource groups with the expected naming pattern or tags
    resource_groups=$(az group list \
        --query "[?contains(name, 'hybrid-db-connectivity') || contains(name, 'rg-hybrid-db')].name" \
        --output tsv)
    
    if [ -z "$resource_groups" ]; then
        warn "No resource groups found with hybrid database connectivity pattern"
        return 1
    fi
    
    log "Found the following resource groups:"
    echo "$resource_groups" | while read -r rg; do
        log "  - $rg"
    done
    
    return 0
}

# Function to get resource group from user input or discovery
get_resource_group() {
    local resource_group=""
    
    # Check if resource group was provided as command line argument
    if [ $# -gt 0 ]; then
        resource_group="$1"
        log "Using resource group from command line: $resource_group"
    else
        # Try to discover resource groups
        if discover_resource_groups; then
            echo ""
            read -p "Enter the resource group name to delete (default: $DEFAULT_RESOURCE_GROUP): " user_input
            resource_group="${user_input:-$DEFAULT_RESOURCE_GROUP}"
        else
            resource_group="$DEFAULT_RESOURCE_GROUP"
            log "Using default resource group: $resource_group"
        fi
    fi
    
    # Verify resource group exists
    if ! az group show --name "$resource_group" &> /dev/null; then
        error "Resource group '$resource_group' does not exist"
        exit 1
    fi
    
    echo "$resource_group"
}

# Function to list resources in the resource group
list_resources() {
    local resource_group="$1"
    
    log "Listing resources in resource group: $resource_group"
    
    # Get resource count
    resource_count=$(az resource list --resource-group "$resource_group" --query "length(@)" --output tsv)
    
    if [ "$resource_count" -eq 0 ]; then
        warn "No resources found in resource group '$resource_group'"
        return 1
    fi
    
    log "Found $resource_count resources:"
    
    # List resources with type and name
    az resource list --resource-group "$resource_group" \
        --query "[].{Name:name, Type:type, Location:location}" \
        --output table
    
    return 0
}

# Function to delete ExpressRoute connections first
delete_expressroute_connections() {
    local resource_group="$1"
    
    log "Checking for ExpressRoute connections..."
    
    # List all VPN connections (includes ExpressRoute connections)
    connections=$(az network vpn-connection list \
        --resource-group "$resource_group" \
        --query "[].name" \
        --output tsv 2>/dev/null || true)
    
    if [ -n "$connections" ]; then
        log "Found ExpressRoute/VPN connections to delete:"
        echo "$connections" | while read -r connection; do
            if [ -n "$connection" ]; then
                info "Deleting connection: $connection"
                az network vpn-connection delete \
                    --name "$connection" \
                    --resource-group "$resource_group" \
                    --no-wait
            fi
        done
        
        # Wait a moment for connection deletions to process
        log "Waiting for connections to be deleted..."
        sleep 30
    else
        log "No ExpressRoute connections found"
    fi
}

# Function to delete Application Gateway resources
delete_application_gateway() {
    local resource_group="$1"
    
    log "Deleting Application Gateway resources..."
    
    # List Application Gateways
    appgateways=$(az network application-gateway list \
        --resource-group "$resource_group" \
        --query "[].name" \
        --output tsv 2>/dev/null || true)
    
    if [ -n "$appgateways" ]; then
        echo "$appgateways" | while read -r appgw; do
            if [ -n "$appgw" ]; then
                info "Deleting Application Gateway: $appgw"
                az network application-gateway delete \
                    --name "$appgw" \
                    --resource-group "$resource_group" \
                    --no-wait
            fi
        done
    else
        log "No Application Gateways found"
    fi
    
    # Delete WAF policies
    waf_policies=$(az network application-gateway waf-policy list \
        --resource-group "$resource_group" \
        --query "[].name" \
        --output tsv 2>/dev/null || true)
    
    if [ -n "$waf_policies" ]; then
        echo "$waf_policies" | while read -r policy; do
            if [ -n "$policy" ]; then
                info "Deleting WAF policy: $policy"
                az network application-gateway waf-policy delete \
                    --name "$policy" \
                    --resource-group "$resource_group" \
                    --no-wait
            fi
        done
    fi
}

# Function to delete PostgreSQL servers
delete_postgresql_servers() {
    local resource_group="$1"
    
    log "Deleting PostgreSQL Flexible Servers..."
    
    # List PostgreSQL Flexible Servers
    postgres_servers=$(az postgres flexible-server list \
        --resource-group "$resource_group" \
        --query "[].name" \
        --output tsv 2>/dev/null || true)
    
    if [ -n "$postgres_servers" ]; then
        echo "$postgres_servers" | while read -r server; do
            if [ -n "$server" ]; then
                info "Deleting PostgreSQL server: $server"
                az postgres flexible-server delete \
                    --name "$server" \
                    --resource-group "$resource_group" \
                    --yes \
                    --no-wait
            fi
        done
    else
        log "No PostgreSQL Flexible Servers found"
    fi
}

# Function to delete ExpressRoute Gateways
delete_expressroute_gateways() {
    local resource_group="$1"
    
    log "Deleting ExpressRoute Gateways (this may take 15-20 minutes)..."
    
    # List VNet Gateways of type ExpressRoute
    gateways=$(az network vnet-gateway list \
        --resource-group "$resource_group" \
        --query "[?gatewayType=='ExpressRoute'].name" \
        --output tsv 2>/dev/null || true)
    
    if [ -n "$gateways" ]; then
        echo "$gateways" | while read -r gateway; do
            if [ -n "$gateway" ]; then
                info "Deleting ExpressRoute Gateway: $gateway (this will take time...)"
                az network vnet-gateway delete \
                    --name "$gateway" \
                    --resource-group "$resource_group" \
                    --no-wait
            fi
        done
        
        # Wait for gateway deletions to process before proceeding
        log "Waiting for ExpressRoute Gateway deletions to begin..."
        sleep 60
    else
        log "No ExpressRoute Gateways found"
    fi
}

# Function to delete private DNS zones
delete_private_dns_zones() {
    local resource_group="$1"
    
    log "Deleting Private DNS zones..."
    
    # List Private DNS zones
    dns_zones=$(az network private-dns zone list \
        --resource-group "$resource_group" \
        --query "[].name" \
        --output tsv 2>/dev/null || true)
    
    if [ -n "$dns_zones" ]; then
        echo "$dns_zones" | while read -r zone; do
            if [ -n "$zone" ]; then
                info "Deleting Private DNS zone: $zone"
                az network private-dns zone delete \
                    --name "$zone" \
                    --resource-group "$resource_group" \
                    --yes \
                    --no-wait
            fi
        done
    else
        log "No Private DNS zones found"
    fi
}

# Function to delete public IPs
delete_public_ips() {
    local resource_group="$1"
    
    log "Deleting Public IP addresses..."
    
    # List Public IPs
    public_ips=$(az network public-ip list \
        --resource-group "$resource_group" \
        --query "[].name" \
        --output tsv 2>/dev/null || true)
    
    if [ -n "$public_ips" ]; then
        echo "$public_ips" | while read -r pip; do
            if [ -n "$pip" ]; then
                info "Deleting Public IP: $pip"
                az network public-ip delete \
                    --name "$pip" \
                    --resource-group "$resource_group" \
                    --no-wait
            fi
        done
    else
        log "No Public IP addresses found"
    fi
}

# Function to delete virtual networks and associated resources
delete_virtual_networks() {
    local resource_group="$1"
    
    log "Deleting Virtual Networks and associated resources..."
    
    # Delete Network Security Groups first
    nsgs=$(az network nsg list \
        --resource-group "$resource_group" \
        --query "[].name" \
        --output tsv 2>/dev/null || true)
    
    if [ -n "$nsgs" ]; then
        echo "$nsgs" | while read -r nsg; do
            if [ -n "$nsg" ]; then
                info "Deleting Network Security Group: $nsg"
                az network nsg delete \
                    --name "$nsg" \
                    --resource-group "$resource_group" \
                    --no-wait
            fi
        done
    fi
    
    # Delete Route Tables
    route_tables=$(az network route-table list \
        --resource-group "$resource_group" \
        --query "[].name" \
        --output tsv 2>/dev/null || true)
    
    if [ -n "$route_tables" ]; then
        echo "$route_tables" | while read -r rt; do
            if [ -n "$rt" ]; then
                info "Deleting Route Table: $rt"
                az network route-table delete \
                    --name "$rt" \
                    --resource-group "$resource_group" \
                    --no-wait
            fi
        done
    fi
    
    # Delete Virtual Networks
    vnets=$(az network vnet list \
        --resource-group "$resource_group" \
        --query "[].name" \
        --output tsv 2>/dev/null || true)
    
    if [ -n "$vnets" ]; then
        echo "$vnets" | while read -r vnet; do
            if [ -n "$vnet" ]; then
                info "Deleting Virtual Network: $vnet"
                az network vnet delete \
                    --name "$vnet" \
                    --resource-group "$resource_group" \
                    --no-wait
            fi
        done
    else
        log "No Virtual Networks found"
    fi
}

# Function to wait for long-running deletions
wait_for_deletions() {
    local resource_group="$1"
    
    log "Waiting for resource deletions to complete..."
    
    # Check for remaining resources periodically
    max_wait_time=1800  # 30 minutes
    check_interval=60   # 1 minute
    elapsed_time=0
    
    while [ $elapsed_time -lt $max_wait_time ]; do
        resource_count=$(az resource list --resource-group "$resource_group" --query "length(@)" --output tsv 2>/dev/null || echo "0")
        
        if [ "$resource_count" -eq 0 ]; then
            log "All resources have been deleted"
            return 0
        fi
        
        info "Still waiting... $resource_count resources remaining (elapsed: ${elapsed_time}s)"
        
        # Show remaining resources
        az resource list --resource-group "$resource_group" \
            --query "[].{Name:name, Type:type}" \
            --output table 2>/dev/null || true
        
        sleep $check_interval
        elapsed_time=$((elapsed_time + check_interval))
    done
    
    warn "Timeout reached. Some resources may still be deleting in the background."
    return 1
}

# Function to delete the resource group
delete_resource_group() {
    local resource_group="$1"
    
    log "Deleting resource group: $resource_group"
    
    # Final confirmation
    warn "About to delete the entire resource group: $resource_group"
    read -p "Final confirmation - type 'DELETE' to proceed: " final_confirm
    
    if [ "$final_confirm" != "DELETE" ]; then
        log "Resource group deletion cancelled"
        return 0
    fi
    
    info "Deleting resource group (this may take several minutes)..."
    az group delete \
        --name "$resource_group" \
        --yes \
        --no-wait
    
    log "Resource group deletion initiated"
}

# Function to cleanup environment variables
cleanup_environment() {
    log "Cleaning up environment variables..."
    
    # List of variables that might have been set during deployment
    variables_to_unset=(
        "RESOURCE_GROUP"
        "LOCATION"
        "SUBSCRIPTION_ID"
        "VNET_NAME"
        "APPGW_NAME"
        "POSTGRES_NAME"
        "ERGW_NAME"
        "RANDOM_SUFFIX"
    )
    
    for var in "${variables_to_unset[@]}"; do
        if [ -n "${!var:-}" ]; then
            info "Unsetting environment variable: $var"
            unset "$var"
        fi
    done
    
    log "Environment cleanup completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    local resource_group="$1"
    
    log "=== CLEANUP SUMMARY ==="
    log "Resource group targeted for deletion: $resource_group"
    log ""
    log "Resources that were processed for deletion:"
    log "  ✓ ExpressRoute connections"
    log "  ✓ Application Gateway and WAF policies"
    log "  ✓ PostgreSQL Flexible Servers"
    log "  ✓ ExpressRoute Gateways"
    log "  ✓ Private DNS zones"
    log "  ✓ Public IP addresses"
    log "  ✓ Network Security Groups"
    log "  ✓ Route Tables"
    log "  ✓ Virtual Networks and subnets"
    log "  ✓ Resource group (final deletion)"
    log ""
    log "Note: Some resources may continue deleting in the background."
    log "Large resources like ExpressRoute Gateways can take 15-20 minutes to fully delete."
    log ""
    log "=== CLEANUP COMPLETED ==="
}

# Main cleanup function
main() {
    local resource_group
    
    log "Starting Azure ExpressRoute and Application Gateway cleanup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Get resource group to delete
    resource_group=$(get_resource_group "$@")
    
    # List resources that will be deleted
    if ! list_resources "$resource_group"; then
        log "No resources to delete. Exiting."
        exit 0
    fi
    
    # Confirm deletion
    confirm_deletion "$resource_group"
    
    # Perform ordered deletion
    delete_expressroute_connections "$resource_group"
    delete_application_gateway "$resource_group"
    delete_postgresql_servers "$resource_group"
    delete_expressroute_gateways "$resource_group"
    delete_private_dns_zones "$resource_group"
    delete_public_ips "$resource_group"
    delete_virtual_networks "$resource_group"
    
    # Wait for deletions to complete (with timeout)
    if wait_for_deletions "$resource_group"; then
        # If all individual resources are deleted, remove the resource group
        delete_resource_group "$resource_group"
    else
        # If timeout reached, still offer to delete the resource group
        warn "Some resources are still deleting. You can still delete the resource group."
        read -p "Delete resource group anyway? (y/N): " delete_anyway
        if [[ "$delete_anyway" =~ ^[Yy]$ ]]; then
            delete_resource_group "$resource_group"
        fi
    fi
    
    # Cleanup environment
    cleanup_environment
    
    # Display summary
    display_cleanup_summary "$resource_group"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [RESOURCE_GROUP_NAME]"
    echo ""
    echo "Options:"
    echo "  RESOURCE_GROUP_NAME  Optional. Specify the resource group to delete."
    echo "                       If not provided, script will attempt to discover"
    echo "                       or use default: $DEFAULT_RESOURCE_GROUP"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive mode"
    echo "  $0 rg-hybrid-db-connectivity          # Delete specific resource group"
    echo ""
}

# Handle script arguments
case "${1:-}" in
    -h|--help)
        show_usage
        exit 0
        ;;
    *)
        # Continue with main execution
        ;;
esac

# Handle script interruption
trap 'error "Cleanup interrupted! Some resources may still be deleting in the background."; exit 1' INT TERM

# Execute main function
main "$@"