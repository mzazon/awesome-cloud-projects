#!/bin/bash

# =============================================================================
# Azure Autonomous Database Scaling - Cleanup Script
# =============================================================================
# Safely removes all resources created for the autonomous database scaling
# solution including SQL Database Hyperscale, Logic Apps, Key Vault, and
# monitoring components.
#
# Recipe: Implementing Autonomous Database Scaling with Azure SQL Database 
#         Hyperscale and Azure Logic Apps
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# Configuration and Variables
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging configuration
LOG_FILE="destroy_$(date +%Y%m%d_%H%M%S).log"
CLEANUP_START_TIME=$(date)

# Default values (can be overridden by environment variables or command line)
FORCE_DELETE="${FORCE_DELETE:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"
DELETE_RESOURCE_GROUP="${DELETE_RESOURCE_GROUP:-true}"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup script for Azure Autonomous Database Scaling recipe.

OPTIONS:
    --resource-group <name>    Specify resource group name to delete
    --keep-resource-group      Keep the resource group, only delete individual resources
    --force                    Skip all confirmation prompts
    --list-resource-groups     List potential resource groups and exit
    --help                     Show this help message

EXAMPLES:
    $0                                          # Interactive cleanup
    $0 --resource-group rg-autonomous-scaling-abc123
    $0 --force --keep-resource-group
    $0 --list-resource-groups

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if subscription is set
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    log_info "Using subscription: $subscription_name ($subscription_id)"
    
    log_success "Prerequisites check completed successfully"
}

list_potential_resource_groups() {
    log_info "Searching for resource groups that match autonomous scaling pattern..."
    
    local rg_list=$(az group list --query "[?starts_with(name, 'rg-autonomous-scaling')].{Name:name, Location:location, CreatedTime:tags.CreatedTime}" --output table)
    
    if [[ -n "$rg_list" ]]; then
        echo "$rg_list"
    else
        log_warning "No resource groups found matching pattern 'rg-autonomous-scaling*'"
        log_info "You can list all resource groups with: az group list --output table"
    fi
}

discover_resource_group() {
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_info "Using specified resource group: ${RESOURCE_GROUP}"
        return 0
    fi
    
    log_info "Discovering resource groups..."
    
    # Get resource groups that match our naming pattern
    local matching_groups=$(az group list --query "[?starts_with(name, 'rg-autonomous-scaling')].name" --output tsv)
    
    if [[ -z "$matching_groups" ]]; then
        log_error "No resource groups found matching pattern 'rg-autonomous-scaling*'"
        log_info "Use --list-resource-groups to see all available resource groups"
        log_info "Or specify a resource group with --resource-group <name>"
        exit 1
    fi
    
    local group_count=$(echo "$matching_groups" | wc -l)
    
    if [[ $group_count -eq 1 ]]; then
        RESOURCE_GROUP="$matching_groups"
        log_info "Found single matching resource group: ${RESOURCE_GROUP}"
    else
        log_warning "Multiple matching resource groups found:"
        echo "$matching_groups" | nl
        echo
        
        if [[ "${SKIP_CONFIRMATION}" != "true" ]]; then
            read -p "Enter the number of the resource group to delete (or Ctrl+C to cancel): " selection
            RESOURCE_GROUP=$(echo "$matching_groups" | sed -n "${selection}p")
            
            if [[ -z "$RESOURCE_GROUP" ]]; then
                log_error "Invalid selection"
                exit 1
            fi
        else
            log_error "Multiple resource groups found but running in non-interactive mode"
            log_info "Please specify --resource-group <name> when using --force"
            exit 1
        fi
    fi
    
    log_info "Selected resource group: ${RESOURCE_GROUP}"
}

verify_resource_group() {
    log_info "Verifying resource group exists: ${RESOURCE_GROUP}"
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Resource group '${RESOURCE_GROUP}' does not exist"
        exit 1
    fi
    
    # Get resource group details
    local rg_info=$(az group show --name "${RESOURCE_GROUP}" --query "{Location:location, ProvisioningState:properties.provisioningState}" --output table)
    log_info "Resource group details:"
    echo "$rg_info"
    
    log_success "Resource group verification completed"
}

show_resources_to_delete() {
    log_info "Analyzing resources in resource group: ${RESOURCE_GROUP}"
    
    # Get list of resources
    local resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type, Location:location}" --output table)
    
    if [[ -n "$resources" ]]; then
        echo
        log_warning "The following resources will be deleted:"
        echo "$resources"
        echo
        
        # Count resources by type for summary
        local resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)")
        log_info "Total resources to delete: ${resource_count}"
        
        # Check for any high-cost resources
        local sql_databases=$(az resource list --resource-group "${RESOURCE_GROUP}" --resource-type "Microsoft.Sql/servers/databases" --query "length(@)")
        local logic_apps=$(az resource list --resource-group "${RESOURCE_GROUP}" --resource-type "Microsoft.Logic/workflows" --query "length(@)")
        local key_vaults=$(az resource list --resource-group "${RESOURCE_GROUP}" --resource-type "Microsoft.KeyVault/vaults" --query "length(@)")
        
        if [[ $sql_databases -gt 0 ]]; then
            log_warning "Found ${sql_databases} SQL Database(s) - these may have ongoing costs"
        fi
        if [[ $logic_apps -gt 0 ]]; then
            log_info "Found ${logic_apps} Logic App(s)"
        fi
        if [[ $key_vaults -gt 0 ]]; then
            log_warning "Found ${key_vaults} Key Vault(s) - these will be soft-deleted and can be recovered"
        fi
    else
        log_warning "No resources found in resource group: ${RESOURCE_GROUP}"
        log_info "The resource group appears to be empty"
    fi
}

confirm_deletion() {
    if [[ "${SKIP_CONFIRMATION}" == "true" || "${FORCE_DELETE}" == "true" ]]; then
        log_warning "Skipping confirmation (force mode enabled)"
        return 0
    fi
    
    echo
    log_warning "=== DELETION CONFIRMATION ==="
    log_error "This action is IRREVERSIBLE!"
    
    if [[ "${DELETE_RESOURCE_GROUP}" == "true" ]]; then
        log_warning "The entire resource group '${RESOURCE_GROUP}' and ALL its resources will be permanently deleted."
    else
        log_warning "Individual resources in '${RESOURCE_GROUP}' will be deleted, but the resource group will remain."
    fi
    
    echo
    log_warning "Are you absolutely sure you want to proceed?"
    read -p "Type 'DELETE' (in uppercase) to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    echo
    log_warning "Final confirmation: Do you want to proceed with deletion?"
    read -p "Type 'YES' to continue: " final_confirmation
    
    if [[ "$final_confirmation" != "YES" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with deletion..."
}

# =============================================================================
# Resource Deletion Functions
# =============================================================================

delete_monitoring_alerts() {
    log_info "Removing monitoring alerts and action groups..."
    
    # Delete metric alert rules
    local alert_names=("CPU-Scale-Up-Alert" "CPU-Scale-Down-Alert")
    
    for alert_name in "${alert_names[@]}"; do
        if az monitor metrics alert show --name "$alert_name" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_info "Deleting alert rule: $alert_name"
            az monitor metrics alert delete \
                --name "$alert_name" \
                --resource-group "${RESOURCE_GROUP}" \
                >> "${LOG_FILE}" 2>&1
            log_success "Deleted alert rule: $alert_name"
        else
            log_warning "Alert rule not found: $alert_name"
        fi
    done
    
    # Delete action groups
    local action_groups=$(az monitor action-group list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv)
    
    for ag_name in $action_groups; do
        log_info "Deleting action group: $ag_name"
        az monitor action-group delete \
            --name "$ag_name" \
            --resource-group "${RESOURCE_GROUP}" \
            >> "${LOG_FILE}" 2>&1
        log_success "Deleted action group: $ag_name"
    done
}

delete_logic_apps() {
    log_info "Removing Logic Apps workflows..."
    
    local logic_apps=$(az logic workflow list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv)
    
    for app_name in $logic_apps; do
        log_info "Deleting Logic App: $app_name"
        az logic workflow delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "$app_name" \
            --yes \
            >> "${LOG_FILE}" 2>&1
        log_success "Deleted Logic App: $app_name"
    done
}

delete_sql_resources() {
    log_info "Removing SQL Database and Server resources..."
    
    # Get all SQL servers in the resource group
    local sql_servers=$(az sql server list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv)
    
    for server_name in $sql_servers; do
        log_info "Processing SQL Server: $server_name"
        
        # Delete all databases in the server (except master)
        local databases=$(az sql db list --resource-group "${RESOURCE_GROUP}" --server "$server_name" --query "[?name!='master'].name" --output tsv)
        
        for db_name in $databases; do
            log_info "Deleting database: $db_name"
            az sql db delete \
                --resource-group "${RESOURCE_GROUP}" \
                --server "$server_name" \
                --name "$db_name" \
                --yes \
                >> "${LOG_FILE}" 2>&1
            log_success "Deleted database: $db_name"
        done
        
        # Delete the SQL server
        log_info "Deleting SQL Server: $server_name"
        az sql server delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "$server_name" \
            --yes \
            >> "${LOG_FILE}" 2>&1
        log_success "Deleted SQL Server: $server_name"
    done
}

delete_key_vaults() {
    log_info "Removing Key Vault resources..."
    
    local key_vaults=$(az keyvault list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv)
    
    for kv_name in $key_vaults; do
        log_info "Deleting Key Vault: $kv_name"
        az keyvault delete \
            --name "$kv_name" \
            --resource-group "${RESOURCE_GROUP}" \
            >> "${LOG_FILE}" 2>&1
        
        log_success "Deleted Key Vault: $kv_name"
        log_warning "Key Vault '$kv_name' is soft-deleted and can be recovered for 90 days"
        log_info "To permanently delete: az keyvault purge --name '$kv_name'"
    done
}

delete_log_analytics() {
    log_info "Removing Log Analytics workspaces..."
    
    local workspaces=$(az monitor log-analytics workspace list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv)
    
    for workspace_name in $workspaces; do
        log_info "Deleting Log Analytics workspace: $workspace_name"
        az monitor log-analytics workspace delete \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "$workspace_name" \
            --yes \
            >> "${LOG_FILE}" 2>&1
        log_success "Deleted Log Analytics workspace: $workspace_name"
    done
}

delete_remaining_resources() {
    log_info "Checking for any remaining resources..."
    
    local remaining=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" --output table)
    
    if [[ -n "$remaining" ]]; then
        log_warning "Found remaining resources:"
        echo "$remaining"
        
        if [[ "${FORCE_DELETE}" == "true" ]]; then
            log_warning "Force deleting remaining resources..."
            az resource delete --ids $(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].id" --output tsv) >> "${LOG_FILE}" 2>&1
            log_success "Deleted remaining resources"
        else
            log_warning "Some resources remain. They will be deleted with the resource group."
        fi
    else
        log_success "No remaining resources found"
    fi
}

delete_resource_group() {
    if [[ "${DELETE_RESOURCE_GROUP}" != "true" ]]; then
        log_info "Skipping resource group deletion (--keep-resource-group specified)"
        return 0
    fi
    
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    
    # Delete the entire resource group
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        >> "${LOG_FILE}" 2>&1
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Note: Complete deletion may take 10-15 minutes"
    
    # Optional: Wait for deletion to complete
    if [[ "${FORCE_DELETE}" != "true" ]]; then
        read -p "Wait for deletion to complete? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Waiting for resource group deletion to complete..."
            while az group show --name "${RESOURCE_GROUP}" &> /dev/null; do
                echo -n "."
                sleep 10
            done
            echo
            log_success "Resource group deletion completed"
        fi
    fi
}

# =============================================================================
# Main Cleanup Function
# =============================================================================

main() {
    log_info "Starting Azure Autonomous Database Scaling cleanup"
    log_info "Cleanup started at: ${CLEANUP_START_TIME}"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --keep-resource-group)
                DELETE_RESOURCE_GROUP="false"
                shift
                ;;
            --force)
                FORCE_DELETE="true"
                SKIP_CONFIRMATION="true"
                shift
                ;;
            --list-resource-groups)
                check_prerequisites
                list_potential_resource_groups
                exit 0
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Run prerequisite checks
    check_prerequisites
    
    # Discover or verify resource group
    discover_resource_group
    verify_resource_group
    
    # Show what will be deleted
    show_resources_to_delete
    
    # Get user confirmation
    confirm_deletion
    
    # Start cleanup process
    log_info "Beginning resource cleanup..."
    
    if [[ "${DELETE_RESOURCE_GROUP}" == "true" ]]; then
        # If deleting the entire resource group, we can do it in one operation
        delete_resource_group
    else
        # Delete resources individually
        delete_monitoring_alerts
        delete_logic_apps
        delete_sql_resources
        delete_key_vaults
        delete_log_analytics
        delete_remaining_resources
    fi
    
    # Display cleanup summary
    echo
    log_success "=== CLEANUP COMPLETED ==="
    log_success "Cleanup completed at: $(date)"
    
    if [[ "${DELETE_RESOURCE_GROUP}" == "true" ]]; then
        log_info "Resource group '${RESOURCE_GROUP}' deletion has been initiated"
        log_info "All resources in the group will be permanently deleted"
    else
        log_info "Individual resources have been deleted from '${RESOURCE_GROUP}'"
        log_info "The resource group has been preserved"
    fi
    
    echo
    log_info "Key points to remember:"
    log_info "• SQL Database Hyperscale charges stop immediately upon deletion"
    log_info "• Key Vaults are soft-deleted and can be recovered for 90 days"
    log_info "• Log Analytics data is retained according to configured retention"
    log_info "• Monitor your Azure billing to confirm charges have stopped"
    echo
    log_info "Cleanup logs saved to: ${LOG_FILE}"
}

# =============================================================================
# Script Execution
# =============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi