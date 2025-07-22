#!/bin/bash

# Azure SCOM Migration - Cleanup Script
# This script removes all resources created for Azure Monitor SCOM Managed Instance
# Based on recipe: Migrate On-Premises SCOM to Azure Monitor Managed Instance

set -e  # Exit on any error

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
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Core configuration - can be overridden by environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-scom-migration}"
    export LOCATION="${LOCATION:-East US}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        error "Resource group ${RESOURCE_GROUP} does not exist. Nothing to clean up."
        exit 1
    fi
    
    success "Environment variables configured"
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Location: ${LOCATION}"
    log "Subscription: ${SUBSCRIPTION_ID}"
}

# Confirm destruction
confirm_destruction() {
    log "This script will permanently delete all resources in resource group: ${RESOURCE_GROUP}"
    warning "This action cannot be undone!"
    
    # List resources to be deleted
    log "Resources to be deleted:"
    az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name,Type:type}" --output table
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    success "Destruction confirmed. Proceeding with cleanup..."
}

# Remove agent multi-homing configuration
remove_agent_multihoming() {
    log "Removing agent multi-homing configuration..."
    
    cat << 'EOF'
# Run this PowerShell script on agent machines to remove multi-homing:

$Agent = Get-WmiObject -Class "Microsoft.ManagementInfrastructure.Agent" -Namespace "root\Microsoft\SystemCenter\Agent"
$Agent.RemoveManagementGroup("SCOM_MI_MG")

# Verify removal
Get-SCOMAgent | Select-Object DisplayName, PrimaryManagementServerName
EOF
    
    success "Multi-homing removal script generated"
}

# Remove SCOM Managed Instance
remove_scom_managed_instance() {
    log "Removing SCOM Managed Instance..."
    
    # Get all SCOM MI resources in the resource group
    SCOM_MI_RESOURCES=$(az resource list \
        --resource-group "${RESOURCE_GROUP}" \
        --resource-type "Microsoft.Monitor/scom-managed-instances" \
        --query "[].name" --output tsv)
    
    if [ -z "$SCOM_MI_RESOURCES" ]; then
        warning "No SCOM Managed Instance found in resource group"
        return 0
    fi
    
    for scom_mi in $SCOM_MI_RESOURCES; do
        log "Removing SCOM Managed Instance: $scom_mi"
        
        # Note: The actual command may vary based on Azure CLI version
        # az monitor scom-managed-instance delete \
        #     --name "$scom_mi" \
        #     --resource-group "${RESOURCE_GROUP}" \
        #     --yes \
        #     --no-wait
        
        # Generic resource deletion as fallback
        az resource delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "$scom_mi" \
            --resource-type "Microsoft.Monitor/scom-managed-instances" \
            --no-wait
        
        success "SCOM Managed Instance $scom_mi removal initiated"
    done
}

# Remove SQL Managed Instance
remove_sql_managed_instance() {
    log "Removing SQL Managed Instance (this may take several minutes)..."
    
    # Get all SQL MI resources in the resource group
    SQL_MI_RESOURCES=$(az sql mi list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" --output tsv)
    
    if [ -z "$SQL_MI_RESOURCES" ]; then
        warning "No SQL Managed Instance found in resource group"
        return 0
    fi
    
    for sql_mi in $SQL_MI_RESOURCES; do
        log "Removing SQL Managed Instance: $sql_mi"
        
        # SQL MI deletion is a long-running operation
        az sql mi delete \
            --name "$sql_mi" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --no-wait
        
        success "SQL Managed Instance $sql_mi removal initiated"
    done
}

# Remove storage accounts
remove_storage_accounts() {
    log "Removing storage accounts..."
    
    # Get all storage accounts in the resource group
    STORAGE_ACCOUNTS=$(az storage account list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" --output tsv)
    
    if [ -z "$STORAGE_ACCOUNTS" ]; then
        warning "No storage accounts found in resource group"
        return 0
    fi
    
    for storage_account in $STORAGE_ACCOUNTS; do
        log "Removing storage account: $storage_account"
        
        az storage account delete \
            --name "$storage_account" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes
        
        success "Storage account $storage_account removed"
    done
}

# Remove Key Vault
remove_key_vault() {
    log "Removing Key Vault..."
    
    # Get all Key Vaults in the resource group
    KEY_VAULTS=$(az keyvault list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" --output tsv)
    
    if [ -z "$KEY_VAULTS" ]; then
        warning "No Key Vaults found in resource group"
        return 0
    fi
    
    for key_vault in $KEY_VAULTS; do
        log "Removing Key Vault: $key_vault"
        
        # Delete Key Vault (soft delete enabled by default)
        az keyvault delete \
            --name "$key_vault" \
            --resource-group "${RESOURCE_GROUP}"
        
        # Purge Key Vault to permanently delete
        az keyvault purge \
            --name "$key_vault" \
            --location "${LOCATION}" \
            --no-wait
        
        success "Key Vault $key_vault removed and purged"
    done
}

# Remove Log Analytics workspace
remove_log_analytics() {
    log "Removing Log Analytics workspace..."
    
    # Get all Log Analytics workspaces in the resource group
    LOG_WORKSPACES=$(az monitor log-analytics workspace list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" --output tsv)
    
    if [ -z "$LOG_WORKSPACES" ]; then
        warning "No Log Analytics workspaces found in resource group"
        return 0
    fi
    
    for workspace in $LOG_WORKSPACES; do
        log "Removing Log Analytics workspace: $workspace"
        
        az monitor log-analytics workspace delete \
            --workspace-name "$workspace" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --force true
        
        success "Log Analytics workspace $workspace removed"
    done
}

# Remove Action Groups
remove_action_groups() {
    log "Removing Action Groups..."
    
    # Get all action groups in the resource group
    ACTION_GROUPS=$(az monitor action-group list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" --output tsv)
    
    if [ -z "$ACTION_GROUPS" ]; then
        warning "No Action Groups found in resource group"
        return 0
    fi
    
    for action_group in $ACTION_GROUPS; do
        log "Removing Action Group: $action_group"
        
        az monitor action-group delete \
            --name "$action_group" \
            --resource-group "${RESOURCE_GROUP}"
        
        success "Action Group $action_group removed"
    done
}

# Remove managed identities
remove_managed_identities() {
    log "Removing managed identities..."
    
    # Get all managed identities in the resource group
    MANAGED_IDENTITIES=$(az identity list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" --output tsv)
    
    if [ -z "$MANAGED_IDENTITIES" ]; then
        warning "No managed identities found in resource group"
        return 0
    fi
    
    for identity in $MANAGED_IDENTITIES; do
        log "Removing managed identity: $identity"
        
        az identity delete \
            --name "$identity" \
            --resource-group "${RESOURCE_GROUP}"
        
        success "Managed identity $identity removed"
    done
}

# Remove network resources
remove_network_resources() {
    log "Removing network resources..."
    
    # Remove Network Security Groups
    NSG_NAMES=$(az network nsg list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" --output tsv)
    
    for nsg in $NSG_NAMES; do
        log "Removing Network Security Group: $nsg"
        
        az network nsg delete \
            --name "$nsg" \
            --resource-group "${RESOURCE_GROUP}"
        
        success "Network Security Group $nsg removed"
    done
    
    # Remove Virtual Networks
    VNET_NAMES=$(az network vnet list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" --output tsv)
    
    for vnet in $VNET_NAMES; do
        log "Removing Virtual Network: $vnet"
        
        az network vnet delete \
            --name "$vnet" \
            --resource-group "${RESOURCE_GROUP}"
        
        success "Virtual Network $vnet removed"
    done
}

# Wait for long-running operations
wait_for_operations() {
    log "Waiting for long-running deletion operations to complete..."
    
    # Check for running operations
    while true; do
        RUNNING_OPS=$(az deployment group list \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[?properties.provisioningState=='Running'].name" \
            --output tsv)
        
        if [ -z "$RUNNING_OPS" ]; then
            break
        fi
        
        log "Waiting for operations to complete: $RUNNING_OPS"
        sleep 30
    done
    
    success "All operations completed"
}

# Remove resource group
remove_resource_group() {
    log "Removing resource group..."
    
    # Final confirmation for resource group deletion
    warning "About to delete the entire resource group: ${RESOURCE_GROUP}"
    read -p "Final confirmation - type 'DELETE' to proceed: " final_confirmation
    
    if [ "$final_confirmation" != "DELETE" ]; then
        log "Resource group deletion cancelled by user."
        return 0
    fi
    
    # Delete the resource group and all remaining resources
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    success "Resource group deletion initiated"
    log "Monitor progress in Azure Portal or use 'az group show --name ${RESOURCE_GROUP}' to check status"
}

# Generate cleanup summary
generate_cleanup_summary() {
    log "Generating cleanup summary..."
    
    cat << EOF

===========================================
SCOM Migration Cleanup Summary
===========================================

Resource Group: ${RESOURCE_GROUP}
Location: ${LOCATION}
Subscription: ${SUBSCRIPTION_ID}

Resources Removed:
- SCOM Managed Instance (if existed)
- SQL Managed Instance
- Storage Accounts
- Key Vault (purged)
- Log Analytics Workspace
- Action Groups
- Managed Identities
- Network Security Groups
- Virtual Networks

Final Action:
- Resource Group deletion initiated

Next Steps:
1. Monitor resource group deletion progress in Azure Portal
2. Verify all resources are removed
3. Update agent configurations if needed
4. Remove any remaining on-premises connections

===========================================
EOF

    success "Cleanup completed successfully!"
}

# Main cleanup function
main() {
    log "Starting Azure SCOM Migration cleanup..."
    
    check_prerequisites
    set_environment_variables
    confirm_destruction
    remove_agent_multihoming
    remove_scom_managed_instance
    remove_sql_managed_instance
    remove_storage_accounts
    remove_key_vault
    remove_log_analytics
    remove_action_groups
    remove_managed_identities
    remove_network_resources
    wait_for_operations
    remove_resource_group
    generate_cleanup_summary
    
    success "Cleanup script completed successfully!"
}

# Command line options
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --force             Skip confirmation prompts (dangerous)"
        echo "  --resource-group    Specify resource group name"
        echo ""
        echo "Environment variables:"
        echo "  RESOURCE_GROUP      Resource group name (default: rg-scom-migration)"
        echo "  LOCATION            Azure location (default: East US)"
        exit 0
        ;;
    --force)
        log "Force mode enabled - skipping confirmations"
        confirm_destruction() { 
            log "Force mode: Skipping confirmation"
            success "Destruction confirmed automatically"
        }
        remove_resource_group() {
            log "Force mode: Removing resource group without confirmation"
            az group delete --name "${RESOURCE_GROUP}" --yes --no-wait
            success "Resource group deletion initiated"
        }
        ;;
    --resource-group)
        export RESOURCE_GROUP="$2"
        shift
        ;;
esac

# Run main function
main "$@"