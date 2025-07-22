#!/bin/bash

# Destroy script for Real-Time Collaborative Applications with Azure Communication Services and Azure Fluid Relay
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${2:-$GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    log "$1" "$RED"
    exit 1
}

warn() {
    log "$1" "$YELLOW"
}

info() {
    log "$1" "$BLUE"
}

success() {
    log "$1" "$GREEN"
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Please login to Azure using 'az login' first."
    fi
    
    success "Prerequisites check completed"
}

# Function to load deployment state
load_deployment_state() {
    info "Loading deployment state..."
    
    if [ ! -f "$DEPLOYMENT_STATE_FILE" ]; then
        error "Deployment state file not found. Cannot proceed with cleanup."
    fi
    
    # Source the deployment state file
    source "$DEPLOYMENT_STATE_FILE"
    
    # Verify required variables are set
    local required_vars=("RESOURCE_GROUP" "ACS_NAME" "FLUID_NAME" "FUNC_NAME" "STORAGE_NAME" "KV_NAME")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            error "Required variable $var not found in deployment state"
        fi
    done
    
    success "Deployment state loaded successfully"
    info "Resource Group: ${RESOURCE_GROUP}"
    info "Location: ${LOCATION}"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    warn "WARNING: This will permanently delete all resources in the resource group: ${RESOURCE_GROUP}"
    echo ""
    echo "Resources to be deleted:"
    echo "- Azure Communication Services: ${ACS_NAME}"
    echo "- Azure Fluid Relay: ${FLUID_NAME}"
    echo "- Azure Functions: ${FUNC_NAME}"
    echo "- Storage Account: ${STORAGE_NAME}"
    echo "- Key Vault: ${KV_NAME}"
    echo "- Application Insights: ${FUNC_NAME}-insights"
    echo "- All associated role assignments and policies"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Function to backup critical data (optional)
backup_critical_data() {
    info "Checking for critical data to backup..."
    
    # Check if storage account exists and has data
    if az storage account show --name "${STORAGE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        local storage_key=$(az storage account keys list \
            --account-name "${STORAGE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query [0].value \
            --output tsv 2>/dev/null)
        
        if [ -n "$storage_key" ]; then
            # List containers and their contents
            local containers=$(az storage container list \
                --account-name "${STORAGE_NAME}" \
                --account-key "$storage_key" \
                --query "[].name" \
                --output tsv 2>/dev/null)
            
            if [ -n "$containers" ]; then
                warn "Storage account contains data in containers: $containers"
                echo "Consider backing up important data before continuing."
                read -p "Continue with destruction? (y/n): " continue_choice
                
                if [ "$continue_choice" != "y" ]; then
                    info "Destruction cancelled to allow data backup"
                    exit 0
                fi
            fi
        fi
    fi
    
    success "Critical data check completed"
}

# Function to remove Function App
remove_function_app() {
    info "Removing Function App: ${FUNC_NAME}"
    
    if az functionapp show --name "${FUNC_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        # Remove the Function App
        az functionapp delete \
            --name "${FUNC_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none
        
        success "Function App removed: ${FUNC_NAME}"
    else
        warn "Function App ${FUNC_NAME} not found or already deleted"
    fi
}

# Function to remove Application Insights
remove_application_insights() {
    local app_insights_name="${FUNC_NAME}-insights"
    info "Removing Application Insights: ${app_insights_name}"
    
    if az monitor app-insights component show --app "$app_insights_name" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        az monitor app-insights component delete \
            --app "$app_insights_name" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none
        
        success "Application Insights removed: ${app_insights_name}"
    else
        warn "Application Insights ${app_insights_name} not found or already deleted"
    fi
}

# Function to remove Key Vault
remove_key_vault() {
    info "Removing Key Vault: ${KV_NAME}"
    
    if az keyvault show --name "${KV_NAME}" &> /dev/null; then
        # Enable soft delete purge protection bypass (if needed)
        az keyvault delete \
            --name "${KV_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none
        
        # Purge the Key Vault to completely remove it
        local purge_result=$(az keyvault purge \
            --name "${KV_NAME}" \
            --location "${LOCATION}" \
            --output none 2>&1)
        
        if [ $? -eq 0 ]; then
            success "Key Vault removed and purged: ${KV_NAME}"
        else
            warn "Key Vault deleted but purge may have failed. Check manually if needed."
        fi
    else
        warn "Key Vault ${KV_NAME} not found or already deleted"
    fi
}

# Function to remove Storage Account
remove_storage_account() {
    info "Removing Storage Account: ${STORAGE_NAME}"
    
    if az storage account show --name "${STORAGE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        az storage account delete \
            --name "${STORAGE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none
        
        success "Storage Account removed: ${STORAGE_NAME}"
    else
        warn "Storage Account ${STORAGE_NAME} not found or already deleted"
    fi
}

# Function to remove Azure Communication Services
remove_acs_resource() {
    info "Removing Azure Communication Services: ${ACS_NAME}"
    
    if az communication show --name "${ACS_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        az communication delete \
            --name "${ACS_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none
        
        success "ACS resource removed: ${ACS_NAME}"
    else
        warn "ACS resource ${ACS_NAME} not found or already deleted"
    fi
}

# Function to remove Fluid Relay
remove_fluid_relay() {
    info "Removing Azure Fluid Relay: ${FLUID_NAME}"
    
    if az fluid-relay server show --name "${FLUID_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        az fluid-relay server delete \
            --name "${FLUID_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none
        
        success "Fluid Relay removed: ${FLUID_NAME}"
    else
        warn "Fluid Relay ${FLUID_NAME} not found or already deleted"
    fi
}

# Function to remove role assignments
remove_role_assignments() {
    info "Removing role assignments..."
    
    # Get the subscription ID
    local subscription_id=$(az account show --query id --output tsv)
    
    # Try to find and remove role assignments for the Function App identity
    local func_identity=$(az functionapp identity show \
        --name "${FUNC_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query principalId \
        --output tsv 2>/dev/null)
    
    if [ -n "$func_identity" ]; then
        # Remove storage role assignment
        az role assignment delete \
            --assignee "$func_identity" \
            --role "Storage Blob Data Contributor" \
            --scope "/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_NAME}" \
            --output none 2>/dev/null || true
        
        success "Role assignments removed for Function App identity"
    else
        warn "Function App identity not found, skipping role assignment cleanup"
    fi
}

# Function to remove resource group
remove_resource_group() {
    info "Removing resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        # Final confirmation for resource group deletion
        warn "Final confirmation: Delete resource group ${RESOURCE_GROUP}?"
        read -p "Type 'DELETE' to confirm: " final_confirmation
        
        if [ "$final_confirmation" != "DELETE" ]; then
            error "Resource group deletion cancelled"
        fi
        
        # Delete the resource group and all remaining resources
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait \
            --output none
        
        success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        info "Deletion may take several minutes to complete..."
        
        # Wait for deletion to complete (optional)
        read -p "Wait for deletion to complete? (y/n): " wait_choice
        if [ "$wait_choice" = "y" ]; then
            info "Waiting for resource group deletion to complete..."
            while az group show --name "${RESOURCE_GROUP}" &> /dev/null; do
                echo -n "."
                sleep 10
            done
            echo ""
            success "Resource group deletion completed"
        fi
    else
        warn "Resource group ${RESOURCE_GROUP} not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove deployment state file
    if [ -f "$DEPLOYMENT_STATE_FILE" ]; then
        rm -f "$DEPLOYMENT_STATE_FILE"
        success "Deployment state file removed"
    fi
    
    # Clean up any temporary function code directories
    local temp_dirs=("/tmp/collab-functions-${RANDOM_SUFFIX}")
    for dir in "${temp_dirs[@]}"; do
        if [ -d "$dir" ]; then
            rm -rf "$dir"
            success "Temporary directory removed: $dir"
        fi
    done
    
    success "Local cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    info "Verifying cleanup..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Resource group ${RESOURCE_GROUP} still exists"
        info "Deletion may still be in progress. Check Azure portal for status."
    else
        success "Resource group ${RESOURCE_GROUP} successfully deleted"
    fi
    
    # Check for any remaining resources that might have been created outside the resource group
    local remaining_resources=0
    
    # Check Key Vault (might be in soft-deleted state)
    if az keyvault show-deleted --name "${KV_NAME}" &> /dev/null; then
        warn "Key Vault ${KV_NAME} is in soft-deleted state"
        info "It will be permanently deleted after the retention period"
        remaining_resources=$((remaining_resources + 1))
    fi
    
    if [ $remaining_resources -eq 0 ]; then
        success "All resources successfully cleaned up"
    else
        warn "$remaining_resources resources may still exist in soft-deleted state"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    info "Cleanup Summary"
    echo "===================="
    echo "Destroyed Resource Group: ${RESOURCE_GROUP}"
    echo "Destroyed ACS Resource: ${ACS_NAME}"
    echo "Destroyed Fluid Relay: ${FLUID_NAME}"
    echo "Destroyed Function App: ${FUNC_NAME}"
    echo "Destroyed Storage Account: ${STORAGE_NAME}"
    echo "Destroyed Key Vault: ${KV_NAME}"
    echo "Destroyed Application Insights: ${FUNC_NAME}-insights"
    echo "===================="
    echo "Cleanup log saved to: ${LOG_FILE}"
    echo ""
    echo "Notes:"
    echo "- Some resources may take additional time to fully delete"
    echo "- Check Azure portal to confirm all resources are removed"
    echo "- Monitor Azure Cost Management to ensure billing has stopped"
}

# Main cleanup function
main() {
    info "Starting cleanup of Real-Time Collaborative Applications infrastructure"
    
    # Initialize log file
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_state
    confirm_destruction
    backup_critical_data
    
    # Remove resources in reverse order of creation
    remove_function_app
    remove_application_insights
    remove_role_assignments
    remove_key_vault
    remove_storage_account
    remove_acs_resource
    remove_fluid_relay
    
    # Remove resource group (this will catch any remaining resources)
    remove_resource_group
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_cleanup_summary
    
    success "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup interrupted by user"' INT TERM

# Run main function
main "$@"