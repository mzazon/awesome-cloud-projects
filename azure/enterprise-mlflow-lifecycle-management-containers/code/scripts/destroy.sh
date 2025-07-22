#!/bin/bash

# Destroy script for MLflow Model Lifecycle Management with Azure ML and Container Apps
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/deployment_config.env"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
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

# Load configuration
load_configuration() {
    log_info "Loading deployment configuration..."
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
        log_error "Please ensure the deployment script was run successfully, or provide resource names manually."
        
        # Prompt for manual configuration
        read -p "Do you want to enter resource names manually? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            setup_manual_configuration
        else
            exit 1
        fi
    else
        source "${CONFIG_FILE}"
        log_success "Configuration loaded successfully"
        log_info "Resource Group: ${RESOURCE_GROUP:-not set}"
        log_info "Location: ${LOCATION:-not set}"
    fi
}

# Manual configuration setup
setup_manual_configuration() {
    log_info "Setting up manual configuration..."
    
    read -p "Enter Resource Group name: " RESOURCE_GROUP
    read -p "Enter Azure region (default: eastus): " LOCATION
    LOCATION=${LOCATION:-eastus}
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv 2>/dev/null || echo "")
    
    if [[ -z "${SUBSCRIPTION_ID}" ]]; then
        log_error "Unable to get subscription ID. Please ensure you're logged into Azure CLI."
        exit 1
    fi
    
    log_info "Manual configuration set:"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Subscription ID: ${SUBSCRIPTION_ID}"
}

# Confirmation prompt
confirm_destruction() {
    log_warning "This script will permanently delete all resources in the following resource group:"
    log_warning "Resource Group: ${RESOURCE_GROUP}"
    log_warning "Location: ${LOCATION}"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " -r
    echo
    
    if [[ "$REPLY" != "DELETE" ]]; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
    
    log_info "Destruction confirmed. Proceeding with cleanup..."
}

# Check if resource group exists
check_resource_group() {
    log_info "Checking if resource group exists..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Resource group '${RESOURCE_GROUP}' found."
        return 0
    else
        log_warning "Resource group '${RESOURCE_GROUP}' not found."
        log_info "Either the resources were already deleted or the resource group name is incorrect."
        return 1
    fi
}

# List resources in the resource group
list_resources() {
    log_info "Listing resources to be deleted..."
    
    local resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null)
    
    if [[ -n "$resources" ]]; then
        echo "$resources"
        echo
        local resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" --output tsv 2>/dev/null)
        log_info "Found ${resource_count} resources to delete."
    else
        log_info "No resources found in the resource group."
    fi
}

# Remove Container Apps and Environment
remove_container_apps() {
    log_info "Removing Container Apps and environment..."
    
    # Remove container app if it exists
    if [[ -n "${CONTAINER_APP_NAME:-}" ]]; then
        log_info "Deleting Container App: ${CONTAINER_APP_NAME}"
        if az containerapp show --name "${CONTAINER_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az containerapp delete \
                --name "${CONTAINER_APP_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes &> /dev/null || log_warning "Failed to delete Container App: ${CONTAINER_APP_NAME}"
            log_success "Container App deleted: ${CONTAINER_APP_NAME}"
        else
            log_info "Container App not found: ${CONTAINER_APP_NAME}"
        fi
    fi
    
    # Remove container app environment if it exists
    if [[ -n "${CONTAINER_APP_ENV:-}" ]]; then
        log_info "Deleting Container App Environment: ${CONTAINER_APP_ENV}"
        if az containerapp env show --name "${CONTAINER_APP_ENV}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az containerapp env delete \
                --name "${CONTAINER_APP_ENV}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes &> /dev/null || log_warning "Failed to delete Container App Environment: ${CONTAINER_APP_ENV}"
            log_success "Container App Environment deleted: ${CONTAINER_APP_ENV}"
        else
            log_info "Container App Environment not found: ${CONTAINER_APP_ENV}"
        fi
    fi
}

# Remove Azure ML workspace
remove_ml_workspace() {
    log_info "Removing Azure Machine Learning workspace..."
    
    if [[ -n "${ML_WORKSPACE_NAME:-}" ]]; then
        log_info "Deleting ML Workspace: ${ML_WORKSPACE_NAME}"
        if az ml workspace show --name "${ML_WORKSPACE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az ml workspace delete \
                --name "${ML_WORKSPACE_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes &> /dev/null || log_warning "Failed to delete ML Workspace: ${ML_WORKSPACE_NAME}"
            log_success "ML Workspace deleted: ${ML_WORKSPACE_NAME}"
        else
            log_info "ML Workspace not found: ${ML_WORKSPACE_NAME}"
        fi
    fi
}

# Remove monitoring alerts
remove_monitoring_alerts() {
    log_info "Removing monitoring alerts..."
    
    # List and delete all metric alerts in the resource group
    local alerts=$(az monitor metrics alert list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null)
    
    if [[ -n "$alerts" ]]; then
        while IFS= read -r alert_name; do
            if [[ -n "$alert_name" ]]; then
                log_info "Deleting alert: ${alert_name}"
                az monitor metrics alert delete \
                    --name "${alert_name}" \
                    --resource-group "${RESOURCE_GROUP}" &> /dev/null || log_warning "Failed to delete alert: ${alert_name}"
            fi
        done <<< "$alerts"
        log_success "Monitoring alerts removed"
    else
        log_info "No monitoring alerts found"
    fi
}

# Remove Container Registry
remove_container_registry() {
    log_info "Removing Container Registry..."
    
    if [[ -n "${CONTAINER_REGISTRY_NAME:-}" ]]; then
        log_info "Deleting Container Registry: ${CONTAINER_REGISTRY_NAME}"
        if az acr show --name "${CONTAINER_REGISTRY_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az acr delete \
                --name "${CONTAINER_REGISTRY_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes &> /dev/null || log_warning "Failed to delete Container Registry: ${CONTAINER_REGISTRY_NAME}"
            log_success "Container Registry deleted: ${CONTAINER_REGISTRY_NAME}"
        else
            log_info "Container Registry not found: ${CONTAINER_REGISTRY_NAME}"
        fi
    fi
}

# Remove Key Vault
remove_key_vault() {
    log_info "Removing Key Vault..."
    
    if [[ -n "${KEY_VAULT_NAME:-}" ]]; then
        log_info "Deleting Key Vault: ${KEY_VAULT_NAME}"
        if az keyvault show --name "${KEY_VAULT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            # Delete the key vault
            az keyvault delete \
                --name "${KEY_VAULT_NAME}" \
                --resource-group "${RESOURCE_GROUP}" &> /dev/null || log_warning "Failed to delete Key Vault: ${KEY_VAULT_NAME}"
            
            # Purge the key vault to allow immediate recreation with the same name
            log_info "Purging Key Vault to allow name reuse..."
            az keyvault purge \
                --name "${KEY_VAULT_NAME}" \
                --location "${LOCATION}" &> /dev/null || log_warning "Failed to purge Key Vault: ${KEY_VAULT_NAME}"
            
            log_success "Key Vault deleted and purged: ${KEY_VAULT_NAME}"
        else
            log_info "Key Vault not found: ${KEY_VAULT_NAME}"
        fi
    fi
}

# Remove Storage Account
remove_storage_account() {
    log_info "Removing Storage Account..."
    
    if [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]]; then
        log_info "Deleting Storage Account: ${STORAGE_ACCOUNT_NAME}"
        if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az storage account delete \
                --name "${STORAGE_ACCOUNT_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes &> /dev/null || log_warning "Failed to delete Storage Account: ${STORAGE_ACCOUNT_NAME}"
            log_success "Storage Account deleted: ${STORAGE_ACCOUNT_NAME}"
        else
            log_info "Storage Account not found: ${STORAGE_ACCOUNT_NAME}"
        fi
    fi
}

# Remove Log Analytics workspace
remove_log_analytics() {
    log_info "Removing Log Analytics workspace..."
    
    if [[ -n "${LOG_ANALYTICS_NAME:-}" ]]; then
        log_info "Deleting Log Analytics workspace: ${LOG_ANALYTICS_NAME}"
        if az monitor log-analytics workspace show --resource-group "${RESOURCE_GROUP}" --workspace-name "${LOG_ANALYTICS_NAME}" &> /dev/null; then
            az monitor log-analytics workspace delete \
                --resource-group "${RESOURCE_GROUP}" \
                --workspace-name "${LOG_ANALYTICS_NAME}" \
                --yes &> /dev/null || log_warning "Failed to delete Log Analytics workspace: ${LOG_ANALYTICS_NAME}"
            log_success "Log Analytics workspace deleted: ${LOG_ANALYTICS_NAME}"
        else
            log_info "Log Analytics workspace not found: ${LOG_ANALYTICS_NAME}"
        fi
    fi
}

# Final resource group cleanup
remove_resource_group() {
    log_info "Performing final resource group cleanup..."
    
    # Check if there are any remaining resources
    local remaining_resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" --output tsv 2>/dev/null)
    
    if [[ "$remaining_resources" -gt 0 ]]; then
        log_warning "Found ${remaining_resources} remaining resources in the resource group."
        log_info "Listing remaining resources:"
        az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" --output table
        
        echo
        read -p "Do you want to delete the entire resource group and all remaining resources? (y/n): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deleting resource group: ${RESOURCE_GROUP}"
            az group delete \
                --name "${RESOURCE_GROUP}" \
                --yes \
                --no-wait &> /dev/null || {
                log_error "Failed to delete resource group: ${RESOURCE_GROUP}"
                return 1
            }
            log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
            log_info "Note: Resource group deletion may take several minutes to complete."
        else
            log_info "Resource group deletion skipped."
        fi
    else
        log_info "No remaining resources found. Deleting empty resource group."
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait &> /dev/null || {
            log_warning "Failed to delete resource group: ${RESOURCE_GROUP}"
        }
        log_success "Empty resource group deletion initiated: ${RESOURCE_GROUP}"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove generated directories
    local dirs_to_remove=(
        "${SCRIPT_DIR}/../mlflow-work"
        "${SCRIPT_DIR}/../model-serving"
    )
    
    for dir in "${dirs_to_remove[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "Removing directory: $dir"
            rm -rf "$dir" || log_warning "Failed to remove directory: $dir"
        fi
    done
    
    # Remove configuration file
    if [[ -f "${CONFIG_FILE}" ]]; then
        log_info "Removing configuration file: ${CONFIG_FILE}"
        rm -f "${CONFIG_FILE}" || log_warning "Failed to remove configuration file"
    fi
    
    log_success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        local remaining_resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" --output tsv 2>/dev/null)
        
        if [[ "$remaining_resources" -gt 0 ]]; then
            log_warning "Cleanup verification: ${remaining_resources} resources still exist in ${RESOURCE_GROUP}"
            log_info "These may be in the process of being deleted, or deletion may have failed."
        else
            log_success "Cleanup verification: Resource group is empty"
        fi
    else
        log_success "Cleanup verification: Resource group ${RESOURCE_GROUP} no longer exists"
    fi
}

# Display cleanup summary
display_summary() {
    log_info "Cleanup Summary"
    echo "=============================================="
    echo "MLflow Model Lifecycle Management Cleanup"
    echo "=============================================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo ""
    echo "Cleanup actions performed:"
    echo "- Container Apps and Environment removed"
    echo "- Azure ML Workspace removed"
    echo "- Monitoring alerts removed"
    echo "- Container Registry removed"
    echo "- Key Vault removed and purged"
    echo "- Storage Account removed"
    echo "- Log Analytics workspace removed"
    echo "- Local working files cleaned up"
    echo ""
    echo "Log file: ${LOG_FILE}"
    echo ""
    echo "Note: Resource deletion may take several minutes to complete."
    echo "You can verify completion in the Azure portal."
    echo "=============================================="
}

# Main cleanup function
main() {
    log_info "Starting MLflow Model Lifecycle Management cleanup"
    log_info "Cleanup started at: $(date)"
    
    load_configuration
    
    if check_resource_group; then
        list_resources
        confirm_destruction
        
        # Perform cleanup in dependency order
        remove_container_apps
        remove_monitoring_alerts
        remove_ml_workspace
        remove_container_registry
        remove_key_vault
        remove_storage_account
        remove_log_analytics
        remove_resource_group
        
        verify_cleanup
    fi
    
    cleanup_local_files
    display_summary
    
    log_success "Cleanup completed at: $(date)"
    log_info "Total cleanup time: $SECONDS seconds"
}

# Error handling for cleanup script
cleanup_error_handler() {
    log_error "An error occurred during cleanup. Check ${LOG_FILE} for details."
    log_error "Some resources may still exist and require manual cleanup."
    exit 1
}

trap cleanup_error_handler ERR

# Execute main function
main "$@"