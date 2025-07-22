#!/bin/bash

# destroy.sh - Cleanup script for Carbon-Aware Cost Optimization with Azure Carbon Optimization and Azure Automation
# This script safely removes all resources created by the deploy.sh script

set -e  # Exit on any error
set -o pipefail  # Exit if any command in a pipeline fails

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to prompt for confirmation
confirm_destruction() {
    local resource_group="$1"
    
    log_warning "=========================================="
    log_warning "DESTRUCTIVE OPERATION WARNING"
    log_warning "=========================================="
    log_warning "This script will permanently delete the following:"
    log_warning "• Resource Group: $resource_group"
    log_warning "• All contained resources (Automation Account, Key Vault, Logic Apps, etc.)"
    log_warning "• All automation schedules and runbooks"
    log_warning "• All stored configuration and data"
    log_warning "=========================================="
    
    echo -n -e "${YELLOW}Are you sure you want to proceed? Type 'yes' to confirm: ${NC}"
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo -n -e "${YELLOW}This action cannot be undone. Type 'DELETE' to confirm: ${NC}"
    read -r final_confirmation
    
    if [ "$final_confirmation" != "DELETE" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource deletion..."
}

# Function to detect resource group from environment or prompt user
detect_resource_group() {
    local resource_group=""
    
    # Try to detect from environment variables first
    if [ -n "$RESOURCE_GROUP" ]; then
        resource_group="$RESOURCE_GROUP"
        log "Using resource group from environment: $resource_group"
    else
        # List carbon optimization resource groups
        log "Searching for carbon optimization resource groups..."
        local rg_list=$(az group list --query "[?contains(name, 'carbon-optimization')].name" --output tsv)
        
        if [ -z "$rg_list" ]; then
            log_error "No carbon optimization resource groups found."
            log "Please specify the resource group manually:"
            echo -n "Enter resource group name: "
            read -r resource_group
        else
            log "Found the following carbon optimization resource groups:"
            echo "$rg_list"
            echo
            echo -n "Enter the resource group name to delete: "
            read -r resource_group
        fi
    fi
    
    # Validate resource group exists
    if ! az group show --name "$resource_group" &> /dev/null; then
        log_error "Resource group '$resource_group' not found"
        exit 1
    fi
    
    echo "$resource_group"
}

# Function to list resources in the group
list_resources() {
    local resource_group="$1"
    
    log "Listing resources in resource group: $resource_group"
    
    local resources=$(az resource list --resource-group "$resource_group" --query "[].{name:name,type:type}" --output table)
    
    if [ -n "$resources" ]; then
        echo "$resources"
    else
        log_warning "No resources found in resource group $resource_group"
    fi
}

# Function to safely delete Logic Apps workflow
delete_logic_app() {
    local resource_group="$1"
    local logic_app_name="$2"
    
    if az logic workflow show --resource-group "$resource_group" --name "$logic_app_name" &> /dev/null; then
        log "Deleting Logic Apps workflow: $logic_app_name"
        
        # Disable the workflow first to stop any running instances
        az logic workflow update \
            --resource-group "$resource_group" \
            --name "$logic_app_name" \
            --state Disabled \
            --output none 2>/dev/null || log_warning "Could not disable Logic App workflow"
        
        # Wait a moment for any running instances to complete
        sleep 10
        
        # Delete the workflow
        az logic workflow delete \
            --resource-group "$resource_group" \
            --name "$logic_app_name" \
            --yes \
            --output none
        
        log_success "Logic Apps workflow deleted: $logic_app_name"
    else
        log_warning "Logic Apps workflow not found: $logic_app_name"
    fi
}

# Function to safely delete Automation Account
delete_automation_account() {
    local resource_group="$1"
    local automation_account="$2"
    
    if az automation account show --name "$automation_account" --resource-group "$resource_group" &> /dev/null; then
        log "Deleting Automation Account: $automation_account"
        
        # List and delete job schedules first
        local schedules=$(az automation job-schedule list \
            --automation-account-name "$automation_account" \
            --resource-group "$resource_group" \
            --query "[].{runbook:runbookName,schedule:scheduleName}" --output tsv 2>/dev/null)
        
        if [ -n "$schedules" ]; then
            log "Removing automation job schedules..."
            while IFS=$'\t' read -r runbook schedule; do
                if [ -n "$runbook" ] && [ -n "$schedule" ]; then
                    az automation job-schedule delete \
                        --automation-account-name "$automation_account" \
                        --resource-group "$resource_group" \
                        --runbook-name "$runbook" \
                        --schedule-name "$schedule" \
                        --yes \
                        --output none 2>/dev/null || log_warning "Could not delete job schedule: $runbook/$schedule"
                fi
            done <<< "$schedules"
        fi
        
        # Delete the automation account (this will remove all runbooks, schedules, etc.)
        az automation account delete \
            --name "$automation_account" \
            --resource-group "$resource_group" \
            --yes \
            --output none
        
        log_success "Automation Account deleted: $automation_account"
    else
        log_warning "Automation Account not found: $automation_account"
    fi
}

# Function to safely delete Key Vault
delete_key_vault() {
    local key_vault_name="$1"
    
    if az keyvault show --name "$key_vault_name" &> /dev/null; then
        log "Deleting Key Vault: $key_vault_name"
        
        # Delete the Key Vault
        az keyvault delete \
            --name "$key_vault_name" \
            --output none
        
        # Purge the Key Vault to fully remove it (optional, but recommended for cleanup)
        log "Purging Key Vault to ensure complete removal..."
        az keyvault purge \
            --name "$key_vault_name" \
            --output none 2>/dev/null || log_warning "Could not purge Key Vault (may not be necessary)"
        
        log_success "Key Vault deleted and purged: $key_vault_name"
    else
        log_warning "Key Vault not found: $key_vault_name"
    fi
}

# Function to delete storage account
delete_storage_account() {
    local resource_group="$1"
    local storage_account="$2"
    
    if az storage account show --name "$storage_account" --resource-group "$resource_group" &> /dev/null; then
        log "Deleting storage account: $storage_account"
        
        az storage account delete \
            --name "$storage_account" \
            --resource-group "$resource_group" \
            --yes \
            --output none
        
        log_success "Storage account deleted: $storage_account"
    else
        log_warning "Storage account not found: $storage_account"
    fi
}

# Function to delete Log Analytics workspace
delete_log_analytics() {
    local resource_group="$1"
    local workspace_name="$2"
    
    if az monitor log-analytics workspace show --workspace-name "$workspace_name" --resource-group "$resource_group" &> /dev/null; then
        log "Deleting Log Analytics workspace: $workspace_name"
        
        az monitor log-analytics workspace delete \
            --resource-group "$resource_group" \
            --workspace-name "$workspace_name" \
            --yes \
            --output none
        
        log_success "Log Analytics workspace deleted: $workspace_name"
    else
        log_warning "Log Analytics workspace not found: $workspace_name"
    fi
}

# Function to clean up role assignments (best effort)
cleanup_role_assignments() {
    local resource_group="$1"
    
    log "Cleaning up role assignments for carbon optimization resources..."
    
    # This is a best-effort cleanup since managed identities are deleted with their resources
    # Role assignments will be automatically cleaned up when the resource group is deleted
    log_warning "Role assignments will be automatically cleaned up with resource deletion"
}

# Function to delete individual resources before deleting the resource group
delete_resources_individually() {
    local resource_group="$1"
    
    log "Attempting to identify and delete carbon optimization resources individually..."
    
    # Try to identify resources by naming patterns
    local logic_apps=$(az logic workflow list --resource-group "$resource_group" --query "[?contains(name, 'carbon-optimization')].name" --output tsv 2>/dev/null)
    local automation_accounts=$(az automation account list --resource-group "$resource_group" --query "[?contains(name, 'carbon-opt')].name" --output tsv 2>/dev/null)
    local key_vaults=$(az keyvault list --resource-group "$resource_group" --query "[?contains(name, 'carbon')].name" --output tsv 2>/dev/null)
    local storage_accounts=$(az storage account list --resource-group "$resource_group" --query "[?contains(name, 'carbonopt')].name" --output tsv 2>/dev/null)
    local log_workspaces=$(az monitor log-analytics workspace list --resource-group "$resource_group" --query "[?contains(name, 'carbon-opt')].name" --output tsv 2>/dev/null)
    
    # Delete Logic Apps
    if [ -n "$logic_apps" ]; then
        for logic_app in $logic_apps; do
            delete_logic_app "$resource_group" "$logic_app"
        done
    fi
    
    # Delete Automation Accounts
    if [ -n "$automation_accounts" ]; then
        for automation_account in $automation_accounts; do
            delete_automation_account "$resource_group" "$automation_account"
        done
    fi
    
    # Delete Key Vaults
    if [ -n "$key_vaults" ]; then
        for key_vault in $key_vaults; do
            delete_key_vault "$key_vault"
        done
    fi
    
    # Delete Storage Accounts
    if [ -n "$storage_accounts" ]; then
        for storage_account in $storage_accounts; do
            delete_storage_account "$resource_group" "$storage_account"
        done
    fi
    
    # Delete Log Analytics Workspaces
    if [ -n "$log_workspaces" ]; then
        for workspace in $log_workspaces; do
            delete_log_analytics "$resource_group" "$workspace"
        done
    fi
    
    # Clean up role assignments
    cleanup_role_assignments "$resource_group"
}

# Function to delete the entire resource group
delete_resource_group() {
    local resource_group="$1"
    
    log "Deleting resource group: $resource_group"
    log_warning "This will delete ALL resources in the resource group..."
    
    # Delete the resource group and all its contents
    az group delete \
        --name "$resource_group" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: $resource_group"
    log "Note: Deletion may take several minutes to complete"
    
    # Optional: Wait for deletion to complete
    echo -n -e "${YELLOW}Would you like to wait for deletion to complete? (y/n): ${NC}"
    read -r wait_response
    
    if [ "$wait_response" = "y" ] || [ "$wait_response" = "yes" ]; then
        log "Waiting for resource group deletion to complete..."
        
        # Wait for resource group to be deleted (check every 30 seconds)
        while az group show --name "$resource_group" &> /dev/null; do
            echo -n "."
            sleep 30
        done
        echo
        
        log_success "Resource group deletion completed: $resource_group"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    local resource_group="$1"
    
    log "Verifying cleanup..."
    
    if az group show --name "$resource_group" &> /dev/null; then
        log_warning "Resource group still exists. Deletion may still be in progress."
        log "You can check the status in the Azure portal or run:"
        log "az group show --name $resource_group"
    else
        log_success "Resource group has been successfully deleted: $resource_group"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    local resource_group="$1"
    
    log "=========================================="
    log "CLEANUP SUMMARY"
    log "=========================================="
    log "Resource Group: $resource_group"
    log "Status: Deletion initiated"
    log "=========================================="
    log_success "Carbon optimization infrastructure cleanup completed!"
    log "All resources associated with the carbon optimization solution have been removed."
    log "Please verify in the Azure portal that all resources have been deleted."
    log "=========================================="
}

# Main cleanup function
main() {
    log "Starting cleanup of Carbon-Aware Cost Optimization solution..."
    
    check_prerequisites
    
    # Detect or prompt for resource group
    RESOURCE_GROUP=$(detect_resource_group)
    
    # List resources for user review
    list_resources "$RESOURCE_GROUP"
    
    # Get confirmation from user
    confirm_destruction "$RESOURCE_GROUP"
    
    # Perform cleanup
    log "Beginning resource cleanup process..."
    
    # Option 1: Delete individual resources first (more controlled)
    delete_resources_individually "$RESOURCE_GROUP"
    
    # Wait a bit for individual deletions to complete
    sleep 30
    
    # Option 2: Delete the entire resource group (ensures everything is removed)
    delete_resource_group "$RESOURCE_GROUP"
    
    # Verify cleanup
    sleep 10
    verify_cleanup "$RESOURCE_GROUP"
    
    # Display summary
    display_cleanup_summary "$RESOURCE_GROUP"
    
    log_success "Cleanup process completed!"
}

# Error handling
trap 'log_error "Cleanup failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"