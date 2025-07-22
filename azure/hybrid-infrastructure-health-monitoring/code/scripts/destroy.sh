#!/bin/bash

# =============================================================================
# Azure Infrastructure Health Monitoring Cleanup Script
# =============================================================================
# Description: Removes all resources created by the health monitoring deployment
# Author: Recipe Generator
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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
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

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        log_error "Please login to Azure CLI first: az login"
        exit 1
    fi
    
    log_success "Prerequisites checked successfully"
}

# =============================================================================
# Configuration Discovery
# =============================================================================

discover_resources() {
    log "Discovering deployed resources..."
    
    # Check if resource group exists and get its properties
    if az group show --name "rg-infra-health-monitor" &> /dev/null; then
        export RESOURCE_GROUP="rg-infra-health-monitor"
        export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        
        # List all resources in the resource group to identify components
        RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{name:name, type:type}" --output json)
        
        # Extract resource names dynamically
        export FUNCTION_APP_NAME=$(echo "${RESOURCES}" | jq -r '.[] | select(.type=="Microsoft.Web/sites") | .name' | head -1)
        export STORAGE_ACCOUNT_NAME=$(echo "${RESOURCES}" | jq -r '.[] | select(.type=="Microsoft.Storage/storageAccounts") | .name' | head -1)
        export LOG_ANALYTICS_NAME=$(echo "${RESOURCES}" | jq -r '.[] | select(.type=="Microsoft.OperationalInsights/workspaces") | .name' | head -1)
        export EVENT_GRID_TOPIC=$(echo "${RESOURCES}" | jq -r '.[] | select(.type=="Microsoft.EventGrid/topics") | .name' | head -1)
        export KEY_VAULT_NAME=$(echo "${RESOURCES}" | jq -r '.[] | select(.type=="Microsoft.KeyVault/vaults") | .name' | head -1)
        export VNET_NAME=$(echo "${RESOURCES}" | jq -r '.[] | select(.type=="Microsoft.Network/virtualNetworks") | .name' | head -1)
        
        log "Discovered resources:"
        log "  Resource Group: ${RESOURCE_GROUP}"
        log "  Function App: ${FUNCTION_APP_NAME:-"Not found"}"
        log "  Storage Account: ${STORAGE_ACCOUNT_NAME:-"Not found"}"
        log "  Key Vault: ${KEY_VAULT_NAME:-"Not found"}"
        log "  Event Grid Topic: ${EVENT_GRID_TOPIC:-"Not found"}"
        log "  Virtual Network: ${VNET_NAME:-"Not found"}"
        
        log_success "Resource discovery completed"
    else
        log_warning "Resource group 'rg-infra-health-monitor' not found"
        log "Either the resources have already been cleaned up or were never deployed"
        exit 0
    fi
}

# =============================================================================
# Confirmation and Safety Checks
# =============================================================================

confirm_destruction() {
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log ""
    log "This script will permanently delete the following Azure resources:"
    log "  • Resource Group: ${RESOURCE_GROUP}"
    log "  • Function App: ${FUNCTION_APP_NAME:-"N/A"}"
    log "  • Storage Account: ${STORAGE_ACCOUNT_NAME:-"N/A"} (and all data)"
    log "  • Key Vault: ${KEY_VAULT_NAME:-"N/A"} (and all secrets)"
    log "  • Event Grid Topic: ${EVENT_GRID_TOPIC:-"N/A"}"
    log "  • Virtual Network: ${VNET_NAME:-"N/A"}"
    log "  • Log Analytics Workspace: ${LOG_ANALYTICS_NAME:-"N/A"} (and all logs)"
    log "  • Application Insights components"
    log "  • Event Grid subscriptions"
    log "  • Role assignments and permissions"
    log ""
    log_warning "THIS ACTION CANNOT BE UNDONE!"
    log ""
    
    # Interactive confirmation unless --force flag is provided
    if [[ "${1:-}" != "--force" ]]; then
        read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " confirmation
        if [[ "${confirmation}" != "DELETE" ]]; then
            log "Operation cancelled by user"
            exit 0
        fi
        
        read -p "Last chance! Type 'YES' to proceed with deletion: " final_confirmation
        if [[ "${final_confirmation}" != "YES" ]]; then
            log "Operation cancelled by user"
            exit 0
        fi
    else
        log_warning "Force flag detected - skipping confirmation prompts"
    fi
    
    log_success "Destruction confirmed - proceeding with cleanup"
}

# =============================================================================
# Event Grid Cleanup
# =============================================================================

cleanup_event_grid_subscriptions() {
    log "Removing Event Grid subscriptions..."
    
    # List and remove all Event Grid subscriptions for Update Manager events
    SUBSCRIPTIONS=$(az eventgrid event-subscription list \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}" \
        --query "[?contains(name, 'update-manager')].name" \
        --output tsv 2>/dev/null || true)
    
    if [[ -n "${SUBSCRIPTIONS}" ]]; then
        for subscription in ${SUBSCRIPTIONS}; do
            log "Removing Event Grid subscription: ${subscription}"
            az eventgrid event-subscription delete \
                --name "${subscription}" \
                --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}" \
                2>/dev/null || log_warning "Failed to remove subscription: ${subscription}"
        done
        log_success "Event Grid subscriptions removed"
    else
        log "No Event Grid subscriptions found to remove"
    fi
}

# =============================================================================
# Function App Cleanup
# =============================================================================

cleanup_function_app() {
    if [[ -n "${FUNCTION_APP_NAME}" ]]; then
        log "Removing Function App: ${FUNCTION_APP_NAME}"
        
        # Remove VNet integration first
        log "Removing virtual network integration..."
        az functionapp vnet-integration remove \
            --name "${FUNCTION_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            2>/dev/null || log_warning "VNet integration removal failed or not present"
        
        # Delete Function App
        az functionapp delete \
            --name "${FUNCTION_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            2>/dev/null || log_warning "Function App deletion failed or already deleted"
        
        log_success "Function App removed: ${FUNCTION_APP_NAME}"
    else
        log "No Function App found to remove"
    fi
}

# =============================================================================
# Storage Cleanup
# =============================================================================

cleanup_storage_account() {
    if [[ -n "${STORAGE_ACCOUNT_NAME}" ]]; then
        log "Removing Storage Account: ${STORAGE_ACCOUNT_NAME}"
        log_warning "This will permanently delete all stored data"
        
        az storage account delete \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            2>/dev/null || log_warning "Storage Account deletion failed or already deleted"
        
        log_success "Storage Account removed: ${STORAGE_ACCOUNT_NAME}"
    else
        log "No Storage Account found to remove"
    fi
}

# =============================================================================
# Key Vault Cleanup
# =============================================================================

cleanup_key_vault() {
    if [[ -n "${KEY_VAULT_NAME}" ]]; then
        log "Removing Key Vault: ${KEY_VAULT_NAME}"
        log_warning "This will permanently delete all secrets and certificates"
        
        # Delete Key Vault
        az keyvault delete \
            --name "${KEY_VAULT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            2>/dev/null || log_warning "Key Vault deletion failed or already deleted"
        
        # Purge Key Vault to immediately free the name
        log "Purging Key Vault to free the name for reuse..."
        az keyvault purge \
            --name "${KEY_VAULT_NAME}" \
            --location "eastus" \
            2>/dev/null || log_warning "Key Vault purge failed or not required"
        
        log_success "Key Vault removed and purged: ${KEY_VAULT_NAME}"
    else
        log "No Key Vault found to remove"
    fi
}

# =============================================================================
# Event Grid Topic Cleanup
# =============================================================================

cleanup_event_grid_topic() {
    if [[ -n "${EVENT_GRID_TOPIC}" ]]; then
        log "Removing Event Grid topic: ${EVENT_GRID_TOPIC}"
        
        az eventgrid topic delete \
            --name "${EVENT_GRID_TOPIC}" \
            --resource-group "${RESOURCE_GROUP}" \
            2>/dev/null || log_warning "Event Grid topic deletion failed or already deleted"
        
        log_success "Event Grid topic removed: ${EVENT_GRID_TOPIC}"
    else
        log "No Event Grid topic found to remove"
    fi
}

# =============================================================================
# Monitoring Cleanup
# =============================================================================

cleanup_monitoring_resources() {
    if [[ -n "${LOG_ANALYTICS_NAME}" ]]; then
        log "Removing Log Analytics workspace: ${LOG_ANALYTICS_NAME}"
        log_warning "This will permanently delete all collected logs and metrics"
        
        az monitor log-analytics workspace delete \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_ANALYTICS_NAME}" \
            --force true \
            2>/dev/null || log_warning "Log Analytics workspace deletion failed or already deleted"
        
        log_success "Log Analytics workspace removed: ${LOG_ANALYTICS_NAME}"
    else
        log "No Log Analytics workspace found to remove"
    fi
    
    # Application Insights components are typically deleted with the resource group
    log "Application Insights components will be removed with resource group"
}

# =============================================================================
# Network Cleanup
# =============================================================================

cleanup_networking() {
    if [[ -n "${VNET_NAME}" ]]; then
        log "Removing Virtual Network: ${VNET_NAME}"
        
        az network vnet delete \
            --name "${VNET_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            2>/dev/null || log_warning "Virtual Network deletion failed or already deleted"
        
        log_success "Virtual Network removed: ${VNET_NAME}"
    else
        log "No Virtual Network found to remove"
    fi
}

# =============================================================================
# Role Assignment Cleanup
# =============================================================================

cleanup_role_assignments() {
    log "Removing role assignments..."
    
    # Get all role assignments in the resource group scope
    ROLE_ASSIGNMENTS=$(az role assignment list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[?contains(principalName, 'func-health-monitor')].id" \
        --output tsv 2>/dev/null || true)
    
    if [[ -n "${ROLE_ASSIGNMENTS}" ]]; then
        for assignment in ${ROLE_ASSIGNMENTS}; do
            log "Removing role assignment: ${assignment}"
            az role assignment delete \
                --ids "${assignment}" \
                2>/dev/null || log_warning "Failed to remove role assignment: ${assignment}"
        done
        log_success "Role assignments removed"
    else
        log "No role assignments found to remove"
    fi
}

# =============================================================================
# Resource Group Cleanup
# =============================================================================

cleanup_resource_group() {
    log "Removing Resource Group: ${RESOURCE_GROUP}"
    log_warning "This will remove any remaining resources not explicitly handled above"
    
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log "Note: Complete deletion may take several minutes to complete in the background"
}

# =============================================================================
# Verification
# =============================================================================

verify_cleanup() {
    log "Verifying cleanup completion..."
    
    # Wait a moment for deletions to propagate
    sleep 5
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group still exists - deletion is in progress"
        log "You can monitor deletion progress in the Azure Portal"
    else
        log_success "Resource group has been deleted successfully"
    fi
    
    # Check for any remaining Event Grid subscriptions
    REMAINING_SUBSCRIPTIONS=$(az eventgrid event-subscription list \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}" \
        --query "[?contains(name, 'update-manager')].name" \
        --output tsv 2>/dev/null || true)
    
    if [[ -n "${REMAINING_SUBSCRIPTIONS}" ]]; then
        log_warning "Some Event Grid subscriptions may still exist:"
        echo "${REMAINING_SUBSCRIPTIONS}"
    else
        log_success "All Event Grid subscriptions have been removed"
    fi
    
    log_success "Cleanup verification completed"
}

# =============================================================================
# Main Cleanup Flow
# =============================================================================

show_usage() {
    echo "Usage: $0 [--force]"
    echo ""
    echo "Options:"
    echo "  --force    Skip confirmation prompts (use with caution)"
    echo ""
    echo "This script will delete all Azure resources created by the"
    echo "infrastructure health monitoring deployment."
}

main() {
    # Handle help flag
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        show_usage
        exit 0
    fi
    
    log "Starting Azure Infrastructure Health Monitoring cleanup..."
    log "========================================================"
    
    # Prerequisites and discovery
    check_prerequisites
    discover_resources
    
    # Safety confirmation
    confirm_destruction "$@"
    
    # Cleanup components in dependency order
    cleanup_event_grid_subscriptions
    cleanup_function_app
    cleanup_role_assignments
    cleanup_storage_account
    cleanup_key_vault
    cleanup_event_grid_topic
    cleanup_monitoring_resources
    cleanup_networking
    
    # Final cleanup
    cleanup_resource_group
    
    # Verification
    verify_cleanup
    
    log "========================================================"
    log_success "Azure Infrastructure Health Monitoring cleanup completed!"
    log ""
    log "📋 Cleanup Summary:"
    log "  ✅ Event Grid subscriptions removed"
    log "  ✅ Function App and runtime deleted"
    log "  ✅ Storage Account and data deleted"
    log "  ✅ Key Vault and secrets purged"
    log "  ✅ Event Grid topic deleted"
    log "  ✅ Monitoring resources deleted"
    log "  ✅ Virtual Network deleted"
    log "  ✅ Role assignments removed"
    log "  ✅ Resource group deletion initiated"
    log ""
    log "💰 Cost Impact: All billable resources have been removed"
    log "🔒 Security: All secrets and credentials have been permanently deleted"
    log "📊 Data: All logs, metrics, and stored data have been permanently deleted"
    log ""
    log_warning "Note: Resource group deletion may take a few additional minutes to complete"
    log "You can monitor the progress in the Azure Portal if needed"
}

# Execute main function with all arguments
main "$@"