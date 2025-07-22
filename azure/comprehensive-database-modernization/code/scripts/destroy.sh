#!/bin/bash

# =============================================================================
# Azure Database Modernization Cleanup Script
# =============================================================================
# This script safely removes all Azure resources created for the database
# modernization recipe, including DMS, SQL Database, Backup Vault, and
# monitoring infrastructure.
#
# Recipe: Orchestrating Database Modernization with Azure Database Migration 
#         Service and Azure Backup
# Version: 1.0
# =============================================================================

set -euo pipefail

# Color codes for output
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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if user is logged in
    if ! az account show >/dev/null 2>&1; then
        error_exit "Not logged into Azure. Please run 'az login' first."
    fi
    
    log_success "Prerequisites validated"
}

# Prompt for confirmation
confirm_deletion() {
    local resource_group="$1"
    
    log_warning "This will permanently delete all resources in resource group: $resource_group"
    log_warning "This action cannot be undone!"
    
    echo -e "\n${YELLOW}Resources that will be deleted:${NC}"
    echo "• Database Migration Service"
    echo "• Azure SQL Database and Server"
    echo "• Recovery Services Vault and backups"
    echo "• Storage Account and containers"
    echo "• Log Analytics workspace"
    echo "• Monitoring alerts and dashboards"
    echo "• Action groups"
    echo "• Resource group and all contained resources"
    
    echo -e "\n${RED}Are you sure you want to proceed? (yes/no):${NC}"
    read -r response
    
    if [[ "$response" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource deletion..."
}

# Get resource group from user input or environment
get_resource_group() {
    local resource_group=""
    
    # Check if resource group is provided as argument
    if [[ $# -gt 0 ]]; then
        resource_group="$1"
    else
        # Try to get from environment variable
        resource_group="${RESOURCE_GROUP:-}"
        
        # If not found, prompt user
        if [[ -z "$resource_group" ]]; then
            echo -e "${YELLOW}Enter the resource group name to delete:${NC}"
            read -r resource_group
        fi
    fi
    
    # Validate resource group exists
    if ! az group show --name "$resource_group" >/dev/null 2>&1; then
        error_exit "Resource group '$resource_group' does not exist or is not accessible"
    fi
    
    echo "$resource_group"
}

# List resources in resource group
list_resources() {
    local resource_group="$1"
    
    log "Listing resources in resource group: $resource_group"
    
    local resources=$(az resource list --resource-group "$resource_group" --query '[].{Name:name, Type:type, Location:location}' --output table)
    
    if [[ -z "$resources" ]]; then
        log_warning "No resources found in resource group: $resource_group"
        return 0
    fi
    
    echo "$resources"
    echo ""
}

# Disable backup protection for SQL Database
disable_backup_protection() {
    local resource_group="$1"
    
    log "Disabling backup protection for SQL databases..."
    
    # Get all Recovery Services Vaults
    local vaults=$(az backup vault list --resource-group "$resource_group" --query '[].name' --output tsv)
    
    if [[ -z "$vaults" ]]; then
        log_warning "No Recovery Services Vaults found"
        return 0
    fi
    
    for vault in $vaults; do
        log "Processing vault: $vault"
        
        # Get all protected SQL databases
        local protected_items=$(az backup item list \
            --resource-group "$resource_group" \
            --vault-name "$vault" \
            --backup-management-type AzureSql \
            --workload-type SQLDataBase \
            --query '[].{container:containerName, item:name}' \
            --output tsv 2>/dev/null || true)
        
        if [[ -n "$protected_items" ]]; then
            while IFS=$'\t' read -r container item; do
                if [[ -n "$container" && -n "$item" ]]; then
                    log "Disabling backup protection for: $item"
                    az backup protection disable \
                        --resource-group "$resource_group" \
                        --vault-name "$vault" \
                        --container-name "$container" \
                        --item-name "$item" \
                        --delete-backup-data true \
                        --yes \
                        --output none 2>/dev/null || log_warning "Failed to disable backup protection for $item"
                fi
            done <<< "$protected_items"
        fi
    done
    
    log_success "Backup protection disabled"
}

# Delete Database Migration Service
delete_dms_service() {
    local resource_group="$1"
    
    log "Deleting Database Migration Service instances..."
    
    # Get all DMS services
    local dms_services=$(az dms list --resource-group "$resource_group" --query '[].name' --output tsv 2>/dev/null || true)
    
    if [[ -z "$dms_services" ]]; then
        log_warning "No DMS services found"
        return 0
    fi
    
    for dms_service in $dms_services; do
        log "Deleting DMS service: $dms_service"
        
        # Delete all projects first
        local projects=$(az dms project list \
            --resource-group "$resource_group" \
            --service-name "$dms_service" \
            --query '[].name' \
            --output tsv 2>/dev/null || true)
        
        for project in $projects; do
            log "Deleting DMS project: $project"
            az dms project delete \
                --resource-group "$resource_group" \
                --service-name "$dms_service" \
                --name "$project" \
                --yes \
                --output none 2>/dev/null || log_warning "Failed to delete DMS project: $project"
        done
        
        # Delete DMS service
        az dms delete \
            --resource-group "$resource_group" \
            --name "$dms_service" \
            --yes \
            --output none 2>/dev/null || log_warning "Failed to delete DMS service: $dms_service"
    done
    
    log_success "DMS services deleted"
}

# Delete Recovery Services Vaults
delete_backup_vaults() {
    local resource_group="$1"
    
    log "Deleting Recovery Services Vaults..."
    
    # Get all Recovery Services Vaults
    local vaults=$(az backup vault list --resource-group "$resource_group" --query '[].name' --output tsv 2>/dev/null || true)
    
    if [[ -z "$vaults" ]]; then
        log_warning "No Recovery Services Vaults found"
        return 0
    fi
    
    for vault in $vaults; do
        log "Deleting Recovery Services Vault: $vault"
        
        # Delete backup vault
        az backup vault delete \
            --resource-group "$resource_group" \
            --name "$vault" \
            --yes \
            --output none 2>/dev/null || log_warning "Failed to delete Recovery Services Vault: $vault"
    done
    
    log_success "Recovery Services Vaults deleted"
}

# Delete Azure SQL Databases and Servers
delete_sql_resources() {
    local resource_group="$1"
    
    log "Deleting Azure SQL databases and servers..."
    
    # Get all SQL servers
    local sql_servers=$(az sql server list --resource-group "$resource_group" --query '[].name' --output tsv 2>/dev/null || true)
    
    if [[ -z "$sql_servers" ]]; then
        log_warning "No SQL servers found"
        return 0
    fi
    
    for sql_server in $sql_servers; do
        log "Processing SQL server: $sql_server"
        
        # Delete all databases first
        local databases=$(az sql db list \
            --resource-group "$resource_group" \
            --server "$sql_server" \
            --query '[?name!=`master`].name' \
            --output tsv 2>/dev/null || true)
        
        for database in $databases; do
            log "Deleting SQL database: $database"
            az sql db delete \
                --resource-group "$resource_group" \
                --server "$sql_server" \
                --name "$database" \
                --yes \
                --output none 2>/dev/null || log_warning "Failed to delete SQL database: $database"
        done
        
        # Delete SQL server
        log "Deleting SQL server: $sql_server"
        az sql server delete \
            --resource-group "$resource_group" \
            --name "$sql_server" \
            --yes \
            --output none 2>/dev/null || log_warning "Failed to delete SQL server: $sql_server"
    done
    
    log_success "SQL resources deleted"
}

# Delete storage accounts
delete_storage_accounts() {
    local resource_group="$1"
    
    log "Deleting storage accounts..."
    
    # Get all storage accounts
    local storage_accounts=$(az storage account list --resource-group "$resource_group" --query '[].name' --output tsv 2>/dev/null || true)
    
    if [[ -z "$storage_accounts" ]]; then
        log_warning "No storage accounts found"
        return 0
    fi
    
    for storage_account in $storage_accounts; do
        log "Deleting storage account: $storage_account"
        az storage account delete \
            --resource-group "$resource_group" \
            --name "$storage_account" \
            --yes \
            --output none 2>/dev/null || log_warning "Failed to delete storage account: $storage_account"
    done
    
    log_success "Storage accounts deleted"
}

# Delete Log Analytics workspaces
delete_log_analytics() {
    local resource_group="$1"
    
    log "Deleting Log Analytics workspaces..."
    
    # Get all Log Analytics workspaces
    local workspaces=$(az monitor log-analytics workspace list --resource-group "$resource_group" --query '[].name' --output tsv 2>/dev/null || true)
    
    if [[ -z "$workspaces" ]]; then
        log_warning "No Log Analytics workspaces found"
        return 0
    fi
    
    for workspace in $workspaces; do
        log "Deleting Log Analytics workspace: $workspace"
        az monitor log-analytics workspace delete \
            --resource-group "$resource_group" \
            --workspace-name "$workspace" \
            --yes \
            --output none 2>/dev/null || log_warning "Failed to delete Log Analytics workspace: $workspace"
    done
    
    log_success "Log Analytics workspaces deleted"
}

# Delete monitoring alerts and action groups
delete_monitoring_resources() {
    local resource_group="$1"
    
    log "Deleting monitoring resources..."
    
    # Delete metric alerts
    local alerts=$(az monitor metrics alert list --resource-group "$resource_group" --query '[].name' --output tsv 2>/dev/null || true)
    
    for alert in $alerts; do
        log "Deleting metric alert: $alert"
        az monitor metrics alert delete \
            --resource-group "$resource_group" \
            --name "$alert" \
            --output none 2>/dev/null || log_warning "Failed to delete metric alert: $alert"
    done
    
    # Delete action groups
    local action_groups=$(az monitor action-group list --resource-group "$resource_group" --query '[].name' --output tsv 2>/dev/null || true)
    
    for action_group in $action_groups; do
        log "Deleting action group: $action_group"
        az monitor action-group delete \
            --resource-group "$resource_group" \
            --name "$action_group" \
            --output none 2>/dev/null || log_warning "Failed to delete action group: $action_group"
    done
    
    log_success "Monitoring resources deleted"
}

# Delete dashboards
delete_dashboards() {
    local resource_group="$1"
    
    log "Deleting dashboards..."
    
    # Get all dashboards
    local dashboards=$(az portal dashboard list --resource-group "$resource_group" --query '[].name' --output tsv 2>/dev/null || true)
    
    if [[ -z "$dashboards" ]]; then
        log_warning "No dashboards found"
        return 0
    fi
    
    for dashboard in $dashboards; do
        log "Deleting dashboard: $dashboard"
        az portal dashboard delete \
            --resource-group "$resource_group" \
            --name "$dashboard" \
            --yes \
            --output none 2>/dev/null || log_warning "Failed to delete dashboard: $dashboard"
    done
    
    log_success "Dashboards deleted"
}

# Delete resource group
delete_resource_group() {
    local resource_group="$1"
    
    log "Deleting resource group: $resource_group"
    
    # Final confirmation
    echo -e "\n${RED}Final confirmation: Delete resource group '$resource_group' and ALL remaining resources? (yes/no):${NC}"
    read -r final_response
    
    if [[ "$final_response" != "yes" ]]; then
        log "Resource group deletion cancelled"
        return 0
    fi
    
    # Delete resource group
    az group delete \
        --name "$resource_group" \
        --yes \
        --no-wait \
        --output none
    
    log_success "Resource group deletion initiated: $resource_group"
    log_warning "Note: Complete deletion may take several minutes"
}

# Wait for resource group deletion
wait_for_deletion() {
    local resource_group="$1"
    
    log "Waiting for resource group deletion to complete..."
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if ! az group show --name "$resource_group" >/dev/null 2>&1; then
            log_success "Resource group '$resource_group' has been completely deleted"
            return 0
        fi
        
        log "Deletion in progress... (attempt $attempt/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    log_warning "Resource group deletion is taking longer than expected"
    log "You can check the deletion status in the Azure Portal"
}

# Display cleanup summary
display_cleanup_summary() {
    local resource_group="$1"
    
    log "Cleanup Summary:"
    log "==============="
    log "Resource Group: $resource_group"
    log "Status: Deletion initiated"
    log ""
    log "The following resources have been deleted:"
    log "• Database Migration Service and projects"
    log "• Recovery Services Vault and backup data"
    log "• Azure SQL Database and Server"
    log "• Storage Account and containers"
    log "• Log Analytics workspace"
    log "• Monitoring alerts and action groups"
    log "• Dashboards"
    log "• Resource Group (deletion in progress)"
    log ""
    log "Note: Complete deletion may take several minutes to finish"
}

# Main cleanup function
main() {
    log "Starting Azure Database Modernization cleanup..."
    log "==============================================="
    
    # Validate prerequisites
    validate_prerequisites
    
    # Get resource group to delete
    local resource_group=$(get_resource_group "$@")
    
    # List resources before deletion
    list_resources "$resource_group"
    
    # Confirm deletion
    confirm_deletion "$resource_group"
    
    # Delete resources in correct order
    disable_backup_protection "$resource_group"
    delete_dms_service "$resource_group"
    delete_backup_vaults "$resource_group"
    delete_sql_resources "$resource_group"
    delete_storage_accounts "$resource_group"
    delete_log_analytics "$resource_group"
    delete_monitoring_resources "$resource_group"
    delete_dashboards "$resource_group"
    
    # Delete resource group
    delete_resource_group "$resource_group"
    
    # Wait for completion (optional)
    if [[ "${WAIT_FOR_COMPLETION:-false}" == "true" ]]; then
        wait_for_deletion "$resource_group"
    fi
    
    # Display summary
    display_cleanup_summary "$resource_group"
    
    log_success "Cleanup completed successfully!"
    log "Total cleanup time: $SECONDS seconds"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [RESOURCE_GROUP_NAME]"
    echo ""
    echo "Options:"
    echo "  RESOURCE_GROUP_NAME    Name of the resource group to delete"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP         Default resource group name"
    echo "  WAIT_FOR_COMPLETION    Set to 'true' to wait for complete deletion"
    echo ""
    echo "Examples:"
    echo "  $0 rg-db-migration-abc123"
    echo "  RESOURCE_GROUP=rg-db-migration-abc123 $0"
    echo "  WAIT_FOR_COMPLETION=true $0 rg-db-migration-abc123"
}

# Handle command line arguments
if [[ $# -gt 1 ]]; then
    show_usage
    exit 1
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_usage
    exit 0
fi

# Handle script interruption
trap 'log_error "Script interrupted by user"; exit 1' INT TERM

# Run main function
main "$@"