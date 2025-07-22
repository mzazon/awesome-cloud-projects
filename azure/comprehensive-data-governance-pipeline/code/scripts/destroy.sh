#!/bin/bash

# Azure Purview and Data Lake Storage Governance Cleanup Script
# Recipe: Comprehensive Data Governance Pipeline with Purview Discovery
# This script removes all resources created by the deploy.sh script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
    fi
    
    log "✅ Prerequisites check completed successfully"
}

# Function to load deployment configuration
load_deployment_config() {
    log "Loading deployment configuration..."
    
    if [[ -f .deployment_config ]]; then
        source .deployment_config
        info "Configuration loaded from .deployment_config"
        info "Resource Group: ${RESOURCE_GROUP}"
        info "Purview Account: ${PURVIEW_ACCOUNT}"
        info "Storage Account: ${STORAGE_ACCOUNT}"
        info "Synapse Workspace: ${SYNAPSE_WORKSPACE}"
        info "Location: ${LOCATION}"
    else
        warning "No .deployment_config file found. Using environment variables or prompting for input."
        
        # Try to get from environment variables or prompt user
        if [[ -z "${RESOURCE_GROUP:-}" ]]; then
            read -p "Enter Resource Group name: " RESOURCE_GROUP
        fi
        
        if [[ -z "${PURVIEW_ACCOUNT:-}" ]]; then
            read -p "Enter Purview Account name: " PURVIEW_ACCOUNT
        fi
        
        if [[ -z "${STORAGE_ACCOUNT:-}" ]]; then
            read -p "Enter Storage Account name: " STORAGE_ACCOUNT
        fi
        
        if [[ -z "${SYNAPSE_WORKSPACE:-}" ]]; then
            read -p "Enter Synapse Workspace name: " SYNAPSE_WORKSPACE
        fi
        
        # Validate required variables
        if [[ -z "${RESOURCE_GROUP:-}" || -z "${PURVIEW_ACCOUNT:-}" || -z "${STORAGE_ACCOUNT:-}" || -z "${SYNAPSE_WORKSPACE:-}" ]]; then
            error "Missing required configuration. Please ensure all resource names are provided."
        fi
    fi
    
    log "✅ Configuration loaded successfully"
}

# Function to confirm destruction
confirm_destruction() {
    log "=== RESOURCE DESTRUCTION CONFIRMATION ==="
    warning "This script will permanently delete the following resources:"
    echo ""
    info "Resource Group: ${RESOURCE_GROUP}"
    info "  • Purview Account: ${PURVIEW_ACCOUNT}"
    info "  • Storage Account: ${STORAGE_ACCOUNT} (including all data)"
    info "  • Synapse Workspace: ${SYNAPSE_WORKSPACE}"
    echo ""
    warning "THIS ACTION CANNOT BE UNDONE!"
    warning "All data, configurations, and governance metadata will be permanently lost."
    echo ""
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    log "Destruction confirmed. Proceeding with cleanup..."
}

# Function to validate resources exist
validate_resources() {
    log "Validating resources before cleanup..."
    
    # Check if resource group exists
    if ! az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} does not exist. Nothing to clean up."
        exit 0
    fi
    
    # List resources in the group for confirmation
    info "Resources found in ${RESOURCE_GROUP}:"
    az resource list --resource-group ${RESOURCE_GROUP} --query '[].{Name:name,Type:type,Location:location}' --output table
    
    log "✅ Resource validation completed"
}

# Function to remove Synapse workspace and related resources
remove_synapse_workspace() {
    log "Removing Azure Synapse Analytics workspace..."
    
    if az synapse workspace show --resource-group ${RESOURCE_GROUP} --name ${SYNAPSE_WORKSPACE} &> /dev/null; then
        info "Deleting Synapse workspace: ${SYNAPSE_WORKSPACE}"
        
        # Delete firewall rules first (if they exist)
        info "Removing firewall rules..."
        az synapse workspace firewall-rule delete \
            --name AllowAllWindowsAzureIps \
            --resource-group ${RESOURCE_GROUP} \
            --workspace-name ${SYNAPSE_WORKSPACE} \
            --yes || warning "AllowAllWindowsAzureIps firewall rule not found or already deleted"
        
        az synapse workspace firewall-rule delete \
            --name AllowCurrentIP \
            --resource-group ${RESOURCE_GROUP} \
            --workspace-name ${SYNAPSE_WORKSPACE} \
            --yes || warning "AllowCurrentIP firewall rule not found or already deleted"
        
        # Delete the workspace
        az synapse workspace delete \
            --resource-group ${RESOURCE_GROUP} \
            --name ${SYNAPSE_WORKSPACE} \
            --yes \
            --no-wait
        
        log "✅ Synapse workspace deletion initiated"
    else
        warning "Synapse workspace ${SYNAPSE_WORKSPACE} not found"
    fi
}

# Function to remove Azure Purview account
remove_purview_account() {
    log "Removing Azure Purview account..."
    
    if az purview account show --resource-group ${RESOURCE_GROUP} --name ${PURVIEW_ACCOUNT} &> /dev/null; then
        info "Deleting Purview account: ${PURVIEW_ACCOUNT}"
        
        # Get Purview managed resource group name before deletion
        MANAGED_RG=$(az purview account show \
            --resource-group ${RESOURCE_GROUP} \
            --name ${PURVIEW_ACCOUNT} \
            --query 'properties.managedResourceGroupName' \
            --output tsv 2>/dev/null || echo "")
        
        # Delete Purview account
        az purview account delete \
            --resource-group ${RESOURCE_GROUP} \
            --name ${PURVIEW_ACCOUNT} \
            --yes \
            --no-wait
        
        info "Purview account deletion initiated"
        
        # Note about managed resource group
        if [[ -n "${MANAGED_RG}" ]]; then
            info "Managed resource group '${MANAGED_RG}' will be automatically deleted"
        fi
        
        log "✅ Purview account deletion initiated"
    else
        warning "Purview account ${PURVIEW_ACCOUNT} not found"
    fi
}

# Function to remove storage account and all data
remove_storage_account() {
    log "Removing Azure Data Lake Storage account and all data..."
    
    if az storage account show --resource-group ${RESOURCE_GROUP} --name ${STORAGE_ACCOUNT} &> /dev/null; then
        info "Deleting storage account: ${STORAGE_ACCOUNT}"
        
        # List containers before deletion for confirmation
        info "Storage containers that will be deleted:"
        az storage container list \
            --account-name ${STORAGE_ACCOUNT} \
            --query '[].name' \
            --output table || warning "Could not list containers"
        
        # Delete storage account (this removes all containers and data)
        az storage account delete \
            --resource-group ${RESOURCE_GROUP} \
            --name ${STORAGE_ACCOUNT} \
            --yes
        
        log "✅ Storage account deleted successfully"
    else
        warning "Storage account ${STORAGE_ACCOUNT} not found"
    fi
}

# Function to remove role assignments
remove_role_assignments() {
    log "Removing role assignments..."
    
    # Load additional variables from config if available
    if [[ -f .deployment_config ]]; then
        source .deployment_config
    fi
    
    # Remove role assignments if we have the necessary information
    if [[ -n "${PURVIEW_IDENTITY:-}" && -n "${STORAGE_RESOURCE_ID:-}" ]]; then
        info "Removing Storage Blob Data Reader role assignment..."
        az role assignment delete \
            --assignee ${PURVIEW_IDENTITY} \
            --role "Storage Blob Data Reader" \
            --scope ${STORAGE_RESOURCE_ID} || warning "Role assignment not found or already removed"
    fi
    
    if [[ -n "${USER_OBJECT_ID:-}" && -n "${PURVIEW_RESOURCE_ID:-}" ]]; then
        info "Removing Purview Data Curator role assignment..."
        az role assignment delete \
            --assignee ${USER_OBJECT_ID} \
            --role "Purview Data Curator" \
            --scope ${PURVIEW_RESOURCE_ID} || warning "Role assignment not found or already removed"
    fi
    
    log "✅ Role assignments cleanup completed"
}

# Function to wait for resource deletions
wait_for_deletions() {
    log "Waiting for resource deletions to complete..."
    
    # Wait for Synapse workspace deletion
    if az synapse workspace show --resource-group ${RESOURCE_GROUP} --name ${SYNAPSE_WORKSPACE} &> /dev/null; then
        info "Waiting for Synapse workspace deletion..."
        local timeout=600  # 10 minutes
        local elapsed=0
        local interval=30
        
        while az synapse workspace show --resource-group ${RESOURCE_GROUP} --name ${SYNAPSE_WORKSPACE} &> /dev/null && [ $elapsed -lt $timeout ]; do
            info "Synapse workspace still exists, waiting... ($elapsed/$timeout seconds)"
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        if [ $elapsed -ge $timeout ]; then
            warning "Timeout waiting for Synapse workspace deletion. It may still be in progress."
        else
            log "✅ Synapse workspace deletion completed"
        fi
    fi
    
    # Wait for Purview account deletion
    if az purview account show --resource-group ${RESOURCE_GROUP} --name ${PURVIEW_ACCOUNT} &> /dev/null; then
        info "Waiting for Purview account deletion..."
        local timeout=600  # 10 minutes
        local elapsed=0
        local interval=30
        
        while az purview account show --resource-group ${RESOURCE_GROUP} --name ${PURVIEW_ACCOUNT} &> /dev/null && [ $elapsed -lt $timeout ]; do
            info "Purview account still exists, waiting... ($elapsed/$timeout seconds)"
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        if [ $elapsed -ge $timeout ]; then
            warning "Timeout waiting for Purview account deletion. It may still be in progress."
        else
            log "✅ Purview account deletion completed"
        fi
    fi
}

# Function to remove resource group
remove_resource_group() {
    log "Removing resource group and any remaining resources..."
    
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        # Final confirmation for resource group deletion
        warning "Final confirmation: Delete resource group ${RESOURCE_GROUP} and ALL remaining resources?"
        read -p "Type 'DELETE' to confirm: " final_confirmation
        
        if [[ "${final_confirmation}" != "DELETE" ]]; then
            warning "Resource group deletion cancelled. Some resources may still exist."
            log "You can manually delete the resource group later using:"
            log "az group delete --name ${RESOURCE_GROUP} --yes --no-wait"
            return
        fi
        
        # Delete resource group and all remaining resources
        az group delete \
            --name ${RESOURCE_GROUP} \
            --yes \
            --no-wait
        
        info "Resource group deletion initiated"
        
        # Wait a bit and check if deletion started
        sleep 10
        if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
            info "Resource group deletion is in progress..."
            info "This may take several minutes to complete."
        else
            log "✅ Resource group deleted successfully"
        fi
    else
        warning "Resource group ${RESOURCE_GROUP} not found"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local configuration files..."
    
    local files_to_remove=(
        ".deployment_config"
        "customers.csv"
        "orders.csv"
        "products.csv"
        "data-pipeline.json"
        "linked-service.json"
        "classification-rules.json"
        "sensitivity-labels.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            info "Removed: $file"
        fi
    done
    
    log "✅ Local configuration files cleaned up"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "=== CLEANUP SUMMARY ==="
    info "The following resources have been deleted or are being deleted:"
    info "  • Resource Group: ${RESOURCE_GROUP}"
    info "  • Purview Account: ${PURVIEW_ACCOUNT}"
    info "  • Storage Account: ${STORAGE_ACCOUNT}"
    info "  • Synapse Workspace: ${SYNAPSE_WORKSPACE}"
    echo ""
    info "Cleanup Actions Completed:"
    info "  • Synapse workspace and firewall rules removed"
    info "  • Purview account and managed resources removed"
    info "  • Storage account and all data permanently deleted"
    info "  • Role assignments cleaned up"
    info "  • Local configuration files removed"
    echo ""
    warning "Note: Some deletions may still be in progress in the background."
    warning "Check the Azure portal to confirm all resources have been removed."
    echo ""
    log "=== CLEANUP COMPLETED SUCCESSFULLY ==="
}

# Function to handle cleanup errors
handle_cleanup_error() {
    error "Cleanup interrupted. Some resources may not have been deleted."
    echo ""
    warning "You may need to manually clean up remaining resources:"
    warning "1. Check Azure portal for any remaining resources"
    warning "2. Delete resource group manually: az group delete --name ${RESOURCE_GROUP} --yes"
    warning "3. Verify managed resource groups are also cleaned up"
    echo ""
    exit 1
}

# Main cleanup function
main() {
    log "Starting Azure Purview and Data Lake Storage governance cleanup..."
    
    check_prerequisites
    load_deployment_config
    confirm_destruction
    validate_resources
    
    # Start cleanup process
    remove_role_assignments
    remove_synapse_workspace
    remove_purview_account
    remove_storage_account
    
    # Wait for deletions to complete (with timeout)
    wait_for_deletions
    
    # Final cleanup
    remove_resource_group
    cleanup_local_files
    display_cleanup_summary
    
    log "All cleanup operations completed successfully!"
}

# Handle script interruption
trap 'handle_cleanup_error' INT TERM

# Execute main function
main "$@"