#!/bin/bash

# ================================================================================
# Azure Hybrid Network Security Cleanup Script
# Recipe: Hybrid Network Threat Protection with Premium Firewall
# ================================================================================

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate Azure CLI authentication
validate_azure_auth() {
    log "Validating Azure CLI authentication..."
    if ! az account show >/dev/null 2>&1; then
        error "Azure CLI not authenticated. Please run 'az login' first."
        exit 1
    fi
    success "Azure CLI authentication validated"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '."azure-cli"' -o tsv 2>/dev/null)
    if [ -z "$az_version" ]; then
        error "Unable to determine Azure CLI version"
        exit 1
    fi
    
    log "Azure CLI version: $az_version"
    
    # Validate authentication
    validate_azure_auth
    
    success "All prerequisites met"
}

# Function to discover resources
discover_resources() {
    log "Discovering Azure resources..."
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Try to find resource groups matching the pattern
    local resource_groups=$(az group list --query "[?starts_with(name, 'rg-hybrid-security-')].name" --output tsv)
    
    if [ -z "$resource_groups" ]; then
        warn "No resource groups found matching pattern 'rg-hybrid-security-*'"
        return 1
    fi
    
    log "Found resource groups:"
    for rg in $resource_groups; do
        log "  - $rg"
    done
    
    # If multiple resource groups found, let user choose
    if [ $(echo "$resource_groups" | wc -l) -gt 1 ]; then
        warn "Multiple resource groups found. Please specify which one to delete:"
        select RESOURCE_GROUP in $resource_groups "Cancel"; do
            if [ "$RESOURCE_GROUP" = "Cancel" ]; then
                log "Operation cancelled by user"
                exit 0
            elif [ -n "$RESOURCE_GROUP" ]; then
                log "Selected resource group: $RESOURCE_GROUP"
                break
            else
                error "Invalid selection. Please try again."
            fi
        done
    else
        export RESOURCE_GROUP=$resource_groups
        log "Using resource group: $RESOURCE_GROUP"
    fi
    
    return 0
}

# Function to list resources in the resource group
list_resources() {
    log "Listing resources in resource group: $RESOURCE_GROUP"
    
    # Get all resources in the resource group
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table)
    
    if [ -z "$resources" ]; then
        warn "No resources found in resource group: $RESOURCE_GROUP"
        return 1
    fi
    
    echo "$resources"
    return 0
}

# Function to confirm deletion
confirm_deletion() {
    warn "WARNING: This operation will permanently delete all resources in the resource group!"
    warn "Resource Group: $RESOURCE_GROUP"
    warn "This action cannot be undone."
    echo ""
    
    # List resources to be deleted
    if ! list_resources; then
        warn "Resource group appears to be empty or already deleted."
        return 1
    fi
    
    echo ""
    read -p "Are you sure you want to delete all these resources? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Operation cancelled by user"
        exit 0
    fi
    
    warn "Proceeding with deletion..."
    return 0
}

# Function to remove specific high-cost resources first
remove_high_cost_resources() {
    log "Removing high-cost resources first..."
    
    # Remove ExpressRoute Gateway connections first
    local connections=$(az network vpn-connection list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
    if [ -n "$connections" ]; then
        for connection in $connections; do
            log "Removing ExpressRoute connection: $connection"
            az network vpn-connection delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$connection" \
                --no-wait
        done
        success "ExpressRoute connections removal initiated"
    fi
    
    # Remove ExpressRoute Gateway
    local gateways=$(az network vnet-gateway list --resource-group "$RESOURCE_GROUP" --query "[?gatewayType=='ExpressRoute'].name" --output tsv 2>/dev/null)
    if [ -n "$gateways" ]; then
        for gateway in $gateways; do
            log "Removing ExpressRoute Gateway: $gateway (this may take 10-15 minutes)"
            az network vnet-gateway delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$gateway" \
                --no-wait
        done
        success "ExpressRoute Gateway removal initiated"
    fi
    
    # Remove Azure Firewall
    local firewalls=$(az network firewall list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
    if [ -n "$firewalls" ]; then
        for firewall in $firewalls; do
            log "Removing Azure Firewall: $firewall"
            az network firewall delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$firewall" \
                --no-wait
        done
        success "Azure Firewall removal initiated"
    fi
    
    # Remove firewall policies
    local policies=$(az network firewall policy list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
    if [ -n "$policies" ]; then
        for policy in $policies; do
            log "Removing firewall policy: $policy"
            az network firewall policy delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$policy" \
                --no-wait
        done
        success "Firewall policies removal initiated"
    fi
}

# Function to remove network configurations
remove_network_configurations() {
    log "Removing network configurations..."
    
    # Remove route table associations first
    local route_tables=$(az network route-table list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
    if [ -n "$route_tables" ]; then
        for rt in $route_tables; do
            log "Removing route table associations for: $rt"
            # Get associated subnets
            local subnets=$(az network route-table show --resource-group "$RESOURCE_GROUP" --name "$rt" --query "subnets[].id" --output tsv 2>/dev/null)
            for subnet_id in $subnets; do
                # Extract vnet and subnet name from ID
                local vnet_name=$(echo "$subnet_id" | grep -o '/virtualNetworks/[^/]*' | cut -d'/' -f3)
                local subnet_name=$(echo "$subnet_id" | grep -o '/subnets/[^/]*' | cut -d'/' -f3)
                
                if [ -n "$vnet_name" ] && [ -n "$subnet_name" ]; then
                    log "Removing route table association from subnet: $subnet_name"
                    az network vnet subnet update \
                        --resource-group "$RESOURCE_GROUP" \
                        --vnet-name "$vnet_name" \
                        --name "$subnet_name" \
                        --remove routeTable 2>/dev/null || true
                fi
            done
        done
    fi
    
    # Remove virtual network peerings
    local vnets=$(az network vnet list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
    if [ -n "$vnets" ]; then
        for vnet in $vnets; do
            local peerings=$(az network vnet peering list --resource-group "$RESOURCE_GROUP" --vnet-name "$vnet" --query "[].name" --output tsv 2>/dev/null)
            for peering in $peerings; do
                log "Removing VNet peering: $peering from $vnet"
                az network vnet peering delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$peering" \
                    --vnet-name "$vnet" 2>/dev/null || true
            done
        done
    fi
    
    success "Network configurations removal initiated"
}

# Function to remove monitoring resources
remove_monitoring_resources() {
    log "Removing monitoring resources..."
    
    # Remove Log Analytics workspaces
    local workspaces=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
    if [ -n "$workspaces" ]; then
        for workspace in $workspaces; do
            log "Removing Log Analytics workspace: $workspace"
            az monitor log-analytics workspace delete \
                --resource-group "$RESOURCE_GROUP" \
                --workspace-name "$workspace" \
                --yes \
                --no-wait 2>/dev/null || true
        done
        success "Log Analytics workspaces removal initiated"
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    log "Waiting for high-cost resource deletion to complete..."
    
    local max_wait=1800  # 30 minutes
    local wait_time=0
    local check_interval=30
    
    while [ $wait_time -lt $max_wait ]; do
        # Check if ExpressRoute Gateways are still being deleted
        local gateways=$(az network vnet-gateway list --resource-group "$RESOURCE_GROUP" --query "[?gatewayType=='ExpressRoute'].name" --output tsv 2>/dev/null)
        
        # Check if Azure Firewalls are still being deleted  
        local firewalls=$(az network firewall list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
        
        if [ -z "$gateways" ] && [ -z "$firewalls" ]; then
            success "High-cost resources deletion completed"
            return 0
        fi
        
        if [ -n "$gateways" ]; then
            log "Still waiting for ExpressRoute Gateway deletion..."
        fi
        
        if [ -n "$firewalls" ]; then
            log "Still waiting for Azure Firewall deletion..."
        fi
        
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    warn "Timeout waiting for resource deletion. Proceeding with resource group deletion..."
    return 1
}

# Function to delete entire resource group
delete_resource_group() {
    log "Deleting resource group: $RESOURCE_GROUP"
    
    # Delete the entire resource group
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    success "Resource group deletion initiated: $RESOURCE_GROUP"
    log "Note: Complete deletion may take 30-45 minutes"
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource group deletion..."
    
    local max_wait=300  # 5 minutes for verification
    local wait_time=0
    local check_interval=10
    
    while [ $wait_time -lt $max_wait ]; do
        if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
            success "Resource group successfully deleted: $RESOURCE_GROUP"
            return 0
        fi
        
        log "Resource group still exists, waiting..."
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    warn "Resource group deletion is still in progress. Check Azure portal for status."
    return 1
}

# Function to cleanup by resource type (selective cleanup)
selective_cleanup() {
    log "Performing selective cleanup by resource type..."
    
    remove_high_cost_resources
    
    # Wait a bit for initial deletions to start
    sleep 30
    
    remove_network_configurations
    remove_monitoring_resources
    
    # Wait for critical resources to be deleted
    wait_for_deletion
    
    # Delete remaining resources
    delete_resource_group
}

# Function to force cleanup (direct resource group deletion)
force_cleanup() {
    log "Performing force cleanup (direct resource group deletion)..."
    
    delete_resource_group
}

# Function to show cleanup summary
show_cleanup_summary() {
    log "Cleanup Summary:"
    log "================"
    log "Resource Group: $RESOURCE_GROUP"
    log "Cleanup Method: $1"
    log "Status: $2"
    log ""
    
    if [ "$2" = "Completed" ]; then
        success "All resources have been cleaned up successfully!"
        log "Please verify in the Azure portal that all resources are deleted."
    else
        warn "Cleanup is still in progress. Monitor the Azure portal for completion."
    fi
    
    log ""
    log "Cost Impact:"
    log "- Azure Firewall Premium billing will stop once the resource is deleted"
    log "- ExpressRoute Gateway billing will stop once the resource is deleted"
    log "- Log Analytics workspace billing will stop once the resource is deleted"
    log "- VNet peering costs will stop immediately"
    log ""
    log "Note: Some resources may continue to incur minimal costs until fully deleted."
}

# Function to handle script errors
handle_error() {
    error "An error occurred during cleanup. Some resources may still exist."
    error "Please check the Azure portal and manually delete any remaining resources."
    exit 1
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Cleanup Azure Hybrid Network Security resources"
    echo ""
    echo "Options:"
    echo "  -h, --help         Show this help message"
    echo "  --resource-group   Specify resource group name (optional)"
    echo "  --force            Force cleanup without confirmation"
    echo "  --selective        Perform selective cleanup by resource type"
    echo "  --dry-run          Show resources that would be deleted"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup"
    echo "  $0 --resource-group rg-hybrid-security-abc123  # Cleanup specific RG"
    echo "  $0 --force                           # Force cleanup without confirmation"
    echo "  $0 --selective                       # Selective cleanup by resource type"
    echo "  $0 --dry-run                         # Show what would be deleted"
    echo ""
}

# Parse command line arguments
FORCE=false
SELECTIVE=false
DRY_RUN=false
RESOURCE_GROUP_SPECIFIED=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --resource-group)
            RESOURCE_GROUP_SPECIFIED="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --selective)
            SELECTIVE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Set error handler
trap handle_error ERR

# Main cleanup function
main() {
    log "Starting Azure Hybrid Network Security cleanup..."
    log "Script version: 1.0"
    log "Date: $(date)"
    log ""
    
    # Check prerequisites
    check_prerequisites
    
    # Discover or set resource group
    if [ -n "$RESOURCE_GROUP_SPECIFIED" ]; then
        export RESOURCE_GROUP="$RESOURCE_GROUP_SPECIFIED"
        log "Using specified resource group: $RESOURCE_GROUP"
        
        # Verify resource group exists
        if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
            error "Resource group '$RESOURCE_GROUP' not found"
            exit 1
        fi
    else
        if ! discover_resources; then
            error "No resources found to cleanup"
            exit 1
        fi
    fi
    
    # Dry run mode
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN MODE: The following resources would be deleted:"
        list_resources
        exit 0
    fi
    
    # Confirm deletion unless forced
    if [ "$FORCE" = false ]; then
        if ! confirm_deletion; then
            exit 1
        fi
    fi
    
    # Perform cleanup based on method
    if [ "$SELECTIVE" = true ]; then
        selective_cleanup
        cleanup_method="Selective"
    else
        force_cleanup
        cleanup_method="Force"
    fi
    
    # Verify deletion
    if verify_deletion; then
        cleanup_status="Completed"
    else
        cleanup_status="In Progress"
    fi
    
    # Show summary
    show_cleanup_summary "$cleanup_method" "$cleanup_status"
}

# Run main function
main "$@"