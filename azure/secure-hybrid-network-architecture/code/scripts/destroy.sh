#!/bin/bash

# =============================================================================
# Azure Hybrid Network Security Cleanup Script
# Recipe: Secure Hybrid Network Architecture with VPN Gateway and Private Link
# Description: Safely removes all Azure resources created by the deployment script
# =============================================================================

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Display current subscription
    CURRENT_SUB=$(az account show --query name -o tsv)
    info "Current subscription: $CURRENT_SUB"
    
    log "Prerequisites check completed successfully"
}

# Function to load environment variables
load_environment_variables() {
    log "Loading environment variables..."
    
    # Try to load from .env file first
    if [ -f ".env" ]; then
        source .env
        info "Loaded environment variables from .env file"
    else
        warn ".env file not found. Please provide resource group name manually or ensure deployment script was run from this directory."
        
        # Prompt for resource group if not available
        if [ -z "$RESOURCE_GROUP" ]; then
            echo -n "Enter the resource group name to delete: "
            read -r RESOURCE_GROUP
            export RESOURCE_GROUP
        fi
        
        # Set default location if not provided
        if [ -z "$LOCATION" ]; then
            export LOCATION="eastus"
        fi
        
        # Try to derive other variables from resource group if possible
        if [[ $RESOURCE_GROUP =~ rg-hybrid-network-([a-f0-9]+) ]]; then
            export RANDOM_SUFFIX="${BASH_REMATCH[1]}"
            export HUB_VNET_NAME="vnet-hub-${RANDOM_SUFFIX}"
            export SPOKE_VNET_NAME="vnet-spoke-${RANDOM_SUFFIX}"
            export VPN_GATEWAY_NAME="vpngw-${RANDOM_SUFFIX}"
            export KEY_VAULT_NAME="kv-${RANDOM_SUFFIX}"
            export STORAGE_ACCOUNT_NAME="st${RANDOM_SUFFIX}"
            export PRIVATE_DNS_ZONE="privatelink.vault.azure.net"
            export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
            info "Derived resource names from resource group name"
        else
            warn "Could not derive resource names. Will attempt to delete entire resource group."
        fi
    fi
    
    if [ -z "$RESOURCE_GROUP" ]; then
        error "Resource group name is required for cleanup"
        exit 1
    fi
    
    info "Target resource group: $RESOURCE_GROUP"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warn "This script will DELETE the following resources:"
    echo "- Resource Group: $RESOURCE_GROUP"
    echo "- All resources within the resource group"
    echo ""
    warn "This action is IRREVERSIBLE!"
    echo ""
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group '$RESOURCE_GROUP' does not exist or you don't have access to it."
        exit 1
    fi
    
    # List resources in the group
    info "Resources that will be deleted:"
    az resource list --resource-group "$RESOURCE_GROUP" --output table 2>/dev/null || echo "Unable to list resources"
    echo ""
    
    echo -n "Are you sure you want to proceed? (yes/no): "
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to delete test VM and associated resources
delete_test_vm() {
    if [ -n "$RANDOM_SUFFIX" ]; then
        log "Removing test virtual machine and associated resources..."
        
        # Delete test VM if it exists
        if az vm show --resource-group "$RESOURCE_GROUP" --name "vm-test-${RANDOM_SUFFIX}" &> /dev/null; then
            info "Deleting test VM: vm-test-${RANDOM_SUFFIX}"
            az vm delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "vm-test-${RANDOM_SUFFIX}" \
                --yes \
                > /dev/null
            
            # Wait a moment for VM deletion
            sleep 5
        fi
        
        # Delete VM network interface if it exists
        if az network nic show --resource-group "$RESOURCE_GROUP" --name "vm-test-${RANDOM_SUFFIX}VMNic" &> /dev/null; then
            info "Deleting VM network interface"
            az network nic delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "vm-test-${RANDOM_SUFFIX}VMNic" \
                > /dev/null 2>&1 || warn "Could not delete VM network interface"
        fi
        
        # Delete VM OS disk if it exists
        VM_DISKS=$(az disk list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'vm-test-${RANDOM_SUFFIX}')].name" -o tsv)
        for disk in $VM_DISKS; do
            if [ -n "$disk" ]; then
                info "Deleting VM disk: $disk"
                az disk delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$disk" \
                    --yes \
                    > /dev/null 2>&1 || warn "Could not delete disk: $disk"
            fi
        done
        
        # Delete VM public IP if it exists
        if az network public-ip show --resource-group "$RESOURCE_GROUP" --name "vm-test-${RANDOM_SUFFIX}PublicIP" &> /dev/null; then
            info "Deleting VM public IP"
            az network public-ip delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "vm-test-${RANDOM_SUFFIX}PublicIP" \
                > /dev/null 2>&1 || warn "Could not delete VM public IP"
        fi
        
        # Delete VM NSG if it exists
        if az network nsg show --resource-group "$RESOURCE_GROUP" --name "vm-test-${RANDOM_SUFFIX}NSG" &> /dev/null; then
            info "Deleting VM network security group"
            az network nsg delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "vm-test-${RANDOM_SUFFIX}NSG" \
                > /dev/null 2>&1 || warn "Could not delete VM NSG"
        fi
        
        log "Test VM and associated resources removed successfully"
    else
        warn "Random suffix not available, skipping individual VM resource deletion"
    fi
}

# Function to delete private endpoints and DNS records
delete_private_endpoints() {
    if [ -n "$RANDOM_SUFFIX" ]; then
        log "Removing private endpoints and DNS records..."
        
        # Delete private endpoints
        if az network private-endpoint show --resource-group "$RESOURCE_GROUP" --name "pe-keyvault-${RANDOM_SUFFIX}" &> /dev/null; then
            info "Deleting Key Vault private endpoint"
            az network private-endpoint delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "pe-keyvault-${RANDOM_SUFFIX}" \
                > /dev/null
        fi
        
        if az network private-endpoint show --resource-group "$RESOURCE_GROUP" --name "pe-storage-${RANDOM_SUFFIX}" &> /dev/null; then
            info "Deleting Storage Account private endpoint"
            az network private-endpoint delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "pe-storage-${RANDOM_SUFFIX}" \
                > /dev/null
        fi
        
        # Delete private DNS zones
        if az network private-dns zone show --resource-group "$RESOURCE_GROUP" --name "$PRIVATE_DNS_ZONE" &> /dev/null; then
            info "Deleting Key Vault private DNS zone"
            az network private-dns zone delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$PRIVATE_DNS_ZONE" \
                --yes \
                > /dev/null
        fi
        
        if az network private-dns zone show --resource-group "$RESOURCE_GROUP" --name "privatelink.blob.core.windows.net" &> /dev/null; then
            info "Deleting Storage private DNS zone"
            az network private-dns zone delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "privatelink.blob.core.windows.net" \
                --yes \
                > /dev/null
        fi
        
        log "Private endpoints and DNS zones removed successfully"
    else
        warn "Random suffix not available, skipping individual private endpoint deletion"
    fi
}

# Function to delete VPN Gateway and associated resources
delete_vpn_gateway() {
    if [ -n "$VPN_GATEWAY_NAME" ]; then
        log "Removing VPN Gateway and associated resources (this may take 10-20 minutes)..."
        
        # Check if VPN Gateway exists
        if az network vnet-gateway show --resource-group "$RESOURCE_GROUP" --name "$VPN_GATEWAY_NAME" &> /dev/null; then
            warn "Deleting VPN Gateway: $VPN_GATEWAY_NAME (this will take 10-20 minutes)"
            az network vnet-gateway delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$VPN_GATEWAY_NAME" \
                > /dev/null
            
            log "VPN Gateway deleted successfully"
        fi
        
        # Delete VPN Gateway public IP
        if az network public-ip show --resource-group "$RESOURCE_GROUP" --name "${VPN_GATEWAY_NAME}-pip" &> /dev/null; then
            info "Deleting VPN Gateway public IP"
            az network public-ip delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "${VPN_GATEWAY_NAME}-pip" \
                > /dev/null
        fi
        
        log "VPN Gateway and public IP removed successfully"
    else
        warn "VPN Gateway name not available, skipping individual VPN Gateway deletion"
    fi
}

# Function to delete Azure services
delete_azure_services() {
    if [ -n "$RANDOM_SUFFIX" ]; then
        log "Removing Azure services..."
        
        # Delete Key Vault
        if [ -n "$KEY_VAULT_NAME" ] && az keyvault show --resource-group "$RESOURCE_GROUP" --name "$KEY_VAULT_NAME" &> /dev/null; then
            info "Deleting Key Vault: $KEY_VAULT_NAME"
            az keyvault delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$KEY_VAULT_NAME" \
                > /dev/null
            
            # Purge Key Vault to completely remove it
            info "Purging Key Vault to completely remove it"
            az keyvault purge --name "$KEY_VAULT_NAME" > /dev/null 2>&1 || warn "Could not purge Key Vault (may not be necessary)"
        fi
        
        # Delete Storage Account
        if [ -n "$STORAGE_ACCOUNT_NAME" ] && az storage account show --resource-group "$RESOURCE_GROUP" --name "$STORAGE_ACCOUNT_NAME" &> /dev/null; then
            info "Deleting Storage Account: $STORAGE_ACCOUNT_NAME"
            az storage account delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$STORAGE_ACCOUNT_NAME" \
                --yes \
                > /dev/null
        fi
        
        log "Azure services removed successfully"
    else
        warn "Random suffix not available, skipping individual service deletion"
    fi
}

# Function to delete virtual networks
delete_virtual_networks() {
    if [ -n "$SPOKE_VNET_NAME" ] || [ -n "$HUB_VNET_NAME" ]; then
        log "Removing virtual networks..."
        
        # Delete spoke virtual network
        if [ -n "$SPOKE_VNET_NAME" ] && az network vnet show --resource-group "$RESOURCE_GROUP" --name "$SPOKE_VNET_NAME" &> /dev/null; then
            info "Deleting spoke virtual network: $SPOKE_VNET_NAME"
            az network vnet delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$SPOKE_VNET_NAME" \
                > /dev/null
        fi
        
        # Delete hub virtual network
        if [ -n "$HUB_VNET_NAME" ] && az network vnet show --resource-group "$RESOURCE_GROUP" --name "$HUB_VNET_NAME" &> /dev/null; then
            info "Deleting hub virtual network: $HUB_VNET_NAME"
            az network vnet delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$HUB_VNET_NAME" \
                > /dev/null
        fi
        
        log "Virtual networks removed successfully"
    else
        warn "VNet names not available, skipping individual VNet deletion"
    fi
}

# Function to delete entire resource group
delete_resource_group() {
    log "Removing entire resource group..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Deleting resource group: $RESOURCE_GROUP"
        warn "This will remove all remaining resources in the group"
        
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            > /dev/null
        
        log "Resource group deletion initiated: $RESOURCE_GROUP"
        info "Note: Complete deletion may take several minutes"
        
        # Monitor deletion progress
        info "Monitoring resource group deletion..."
        while az group show --name "$RESOURCE_GROUP" &> /dev/null; do
            echo -n "."
            sleep 10
        done
        echo ""
        log "Resource group deletion completed successfully"
    else
        warn "Resource group '$RESOURCE_GROUP' does not exist or has already been deleted"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove .env file if it exists
    if [ -f ".env" ]; then
        rm -f .env
        info "Removed .env file"
    fi
    
    # Remove any generated SSH keys if they exist
    if [ -f "vm-test-${RANDOM_SUFFIX}_key.pem" ]; then
        rm -f "vm-test-${RANDOM_SUFFIX}_key.pem"
        info "Removed generated SSH key"
    fi
    
    log "Local files cleaned up successfully"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "Resource Group: $RESOURCE_GROUP - DELETED"
    echo "All associated resources have been removed"
    echo ""
    log "Azure Hybrid Network Security infrastructure cleanup completed successfully!"
}

# Function for complete resource group deletion
complete_cleanup() {
    log "Performing complete resource group cleanup..."
    
    check_prerequisites
    load_environment_variables
    confirm_deletion
    delete_resource_group
    cleanup_local_files
    display_cleanup_summary
}

# Function for incremental cleanup (useful if resource group deletion fails)
incremental_cleanup() {
    log "Performing incremental cleanup..."
    
    check_prerequisites
    load_environment_variables
    confirm_deletion
    delete_test_vm
    delete_private_endpoints
    delete_vpn_gateway
    delete_azure_services
    delete_virtual_networks
    delete_resource_group
    cleanup_local_files
    display_cleanup_summary
}

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --complete      Delete entire resource group at once (default, faster)"
    echo "  --incremental   Delete resources individually (slower, more detailed)"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Complete cleanup (default)"
    echo "  $0 --complete        # Complete cleanup"
    echo "  $0 --incremental     # Incremental cleanup"
}

# Main function
main() {
    local cleanup_method="complete"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --complete)
                cleanup_method="complete"
                shift
                ;;
            --incremental)
                cleanup_method="incremental"
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    log "Starting Azure Hybrid Network Security cleanup..."
    
    case $cleanup_method in
        complete)
            complete_cleanup
            ;;
        incremental)
            incremental_cleanup
            ;;
    esac
}

# Handle script interruption
trap 'error "Cleanup script interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"