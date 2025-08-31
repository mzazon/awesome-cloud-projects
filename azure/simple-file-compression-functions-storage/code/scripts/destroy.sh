#!/bin/bash

#######################################################################
# Azure File Compression with Functions and Storage - Cleanup Script
#######################################################################
# 
# This script safely removes all resources created by the deployment script:
# - Event Grid subscriptions and system topics
# - Azure Functions and related resources
# - Azure Blob Storage containers and storage account
# - Resource group (optional)
#
# Recipe: Simple File Compression with Functions and Storage
# Category: Serverless
# Difficulty: 100 (Beginner)
#######################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    success "Prerequisites validated successfully"
}

# Function to get environment variables from user input or environment
setup_environment() {
    log "Setting up environment variables..."
    
    # Try to get resource group from environment or prompt user
    if [ -z "${RESOURCE_GROUP:-}" ]; then
        echo
        read -p "Enter the resource group name to delete: " RESOURCE_GROUP
        if [ -z "${RESOURCE_GROUP}" ]; then
            error "Resource group name is required"
            exit 1
        fi
    fi
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        error "Resource group '${RESOURCE_GROUP}' does not exist"
        exit 1
    fi
    
    # Auto-detect storage account and function app if not provided
    if [ -z "${STORAGE_ACCOUNT:-}" ]; then
        log "Auto-detecting storage account..."
        STORAGE_ACCOUNT=$(az storage account list --resource-group "${RESOURCE_GROUP}" --query "[?contains(name, 'compress')].name" --output tsv | head -n1)
        if [ -z "${STORAGE_ACCOUNT}" ]; then
            warn "Could not auto-detect storage account. You may need to specify it manually."
        else
            log "Found storage account: ${STORAGE_ACCOUNT}"
        fi
    fi
    
    if [ -z "${FUNCTION_APP:-}" ]; then
        log "Auto-detecting function app..."
        FUNCTION_APP=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[?contains(name, 'file-compressor')].name" --output tsv | head -n1)
        if [ -z "${FUNCTION_APP}" ]; then
            warn "Could not auto-detect function app. You may need to specify it manually."
        else
            log "Found function app: ${FUNCTION_APP}"
        fi
    fi
    
    export RESOURCE_GROUP
    export STORAGE_ACCOUNT
    export FUNCTION_APP
    
    log "Environment configured:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Storage Account: ${STORAGE_ACCOUNT:-<not found>}"
    log "  Function App: ${FUNCTION_APP:-<not found>}"
}

# Function to confirm deletion
confirm_deletion() {
    echo
    warn "This will permanently delete the following resources:"
    warn "  • Resource Group: ${RESOURCE_GROUP}"
    if [ -n "${STORAGE_ACCOUNT:-}" ]; then
        warn "  • Storage Account: ${STORAGE_ACCOUNT} (including all blob data)"
    fi
    if [ -n "${FUNCTION_APP:-}" ]; then
        warn "  • Function App: ${FUNCTION_APP}"
    fi
    warn "  • All Event Grid topics and subscriptions"
    warn "  • All other resources in the resource group"
    echo
    warn "THIS ACTION CANNOT BE UNDONE!"
    echo
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " CONFIRMATION
    
    if [ "${CONFIRMATION}" != "yes" ]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed. Proceeding with cleanup..."
}

# Function to delete Event Grid subscription
delete_event_grid_subscription() {
    if [ -n "${STORAGE_ACCOUNT:-}" ]; then
        log "Deleting Event Grid subscription..."
        
        TOPIC_NAME="${STORAGE_ACCOUNT}-topic"
        SUBSCRIPTION_NAME="blob-compression-subscription"
        
        if az eventgrid system-topic event-subscription show --name "${SUBSCRIPTION_NAME}" --system-topic-name "${TOPIC_NAME}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
            az eventgrid system-topic event-subscription delete \
                --name "${SUBSCRIPTION_NAME}" \
                --system-topic-name "${TOPIC_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            
            success "Event Grid subscription deleted: ${SUBSCRIPTION_NAME}"
        else
            warn "Event Grid subscription not found, skipping deletion"
        fi
    else
        warn "Storage account not found, skipping Event Grid subscription deletion"
    fi
}

# Function to delete Event Grid system topic
delete_event_grid_topic() {
    if [ -n "${STORAGE_ACCOUNT:-}" ]; then
        log "Deleting Event Grid system topic..."
        
        TOPIC_NAME="${STORAGE_ACCOUNT}-topic"
        
        if az eventgrid system-topic show --name "${TOPIC_NAME}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
            az eventgrid system-topic delete \
                --name "${TOPIC_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            
            success "Event Grid system topic deleted: ${TOPIC_NAME}"
        else
            warn "Event Grid system topic not found, skipping deletion"
        fi
    else
        warn "Storage account not found, skipping Event Grid system topic deletion"
    fi
}

# Function to delete Function App
delete_function_app() {
    if [ -n "${FUNCTION_APP:-}" ]; then
        log "Deleting Function App: ${FUNCTION_APP}"
        
        if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
            az functionapp delete \
                --name "${FUNCTION_APP}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output none
            
            success "Function App deleted: ${FUNCTION_APP}"
        else
            warn "Function App not found, skipping deletion"
        fi
    else
        warn "Function App not found, skipping deletion"
    fi
}

# Function to delete storage containers (optional, before deleting storage account)
delete_storage_containers() {
    if [ -n "${STORAGE_ACCOUNT:-}" ]; then
        log "Checking storage containers for data..."
        
        if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
            # Check if containers have blobs
            RAW_FILES_COUNT=$(az storage blob list --account-name "${STORAGE_ACCOUNT}" --container-name raw-files --auth-mode login --query "length([*])" --output tsv 2>/dev/null || echo "0")
            COMPRESSED_FILES_COUNT=$(az storage blob list --account-name "${STORAGE_ACCOUNT}" --container-name compressed-files --auth-mode login --query "length([*])" --output tsv 2>/dev/null || echo "0")
            
            if [ "${RAW_FILES_COUNT}" -gt 0 ] || [ "${COMPRESSED_FILES_COUNT}" -gt 0 ]; then
                warn "Storage containers contain ${RAW_FILES_COUNT} raw files and ${COMPRESSED_FILES_COUNT} compressed files"
                echo
                read -p "Do you want to delete all blob data? (type 'yes' to confirm): " BLOB_CONFIRMATION
                
                if [ "${BLOB_CONFIRMATION}" == "yes" ]; then
                    log "Deleting all blob data..."
                    
                    # Delete all blobs in raw-files container
                    if [ "${RAW_FILES_COUNT}" -gt 0 ]; then
                        az storage blob delete-batch \
                            --account-name "${STORAGE_ACCOUNT}" \
                            --source raw-files \
                            --auth-mode login \
                            --output none 2>/dev/null || true
                        
                        success "Deleted blobs from raw-files container"
                    fi
                    
                    # Delete all blobs in compressed-files container
                    if [ "${COMPRESSED_FILES_COUNT}" -gt 0 ]; then
                        az storage blob delete-batch \
                            --account-name "${STORAGE_ACCOUNT}" \
                            --source compressed-files \
                            --auth-mode login \
                            --output none 2>/dev/null || true
                        
                        success "Deleted blobs from compressed-files container"
                    fi
                else
                    warn "Blob data will be preserved (but storage account will still be deleted)"
                fi
            else
                log "No blob data found in containers"
            fi
        else
            warn "Storage account not found, skipping container cleanup"
        fi
    fi
}

# Function to delete storage account
delete_storage_account() {
    if [ -n "${STORAGE_ACCOUNT:-}" ]; then
        log "Deleting storage account: ${STORAGE_ACCOUNT}"
        
        if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
            az storage account delete \
                --name "${STORAGE_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            
            success "Storage account deleted: ${STORAGE_ACCOUNT}"
        else
            warn "Storage account not found, skipping deletion"
        fi
    else
        warn "Storage account not found, skipping deletion"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group: ${RESOURCE_GROUP}"
    
    # Final confirmation for resource group deletion
    echo
    warn "Final confirmation: Delete resource group '${RESOURCE_GROUP}' and ALL remaining resources?"
    read -p "Type 'DELETE' to confirm: " FINAL_CONFIRMATION
    
    if [ "${FINAL_CONFIRMATION}" != "DELETE" ]; then
        log "Resource group deletion cancelled"
        log "Individual resources have been deleted, but resource group '${RESOURCE_GROUP}' remains"
        return 0
    fi
    
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        # Use --no-wait for faster response, but inform user
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait \
            --output none
        
        success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        log "Note: Resource group deletion may take several minutes to complete in the background"
    else
        warn "Resource group not found or already deleted"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log "Resource group '${RESOURCE_GROUP}' still exists (deletion may be in progress)"
        
        # List remaining resources
        REMAINING_RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length([*])" --output tsv)
        if [ "${REMAINING_RESOURCES}" -gt 0 ]; then
            warn "${REMAINING_RESOURCES} resources still exist in the resource group"
            log "To check remaining resources: az resource list --resource-group ${RESOURCE_GROUP} --output table"
        else
            log "No resources found in the resource group"
        fi
    else
        success "Resource group '${RESOURCE_GROUP}' has been successfully deleted"
    fi
}

# Function to display cleanup summary
display_summary() {
    success "=== CLEANUP COMPLETED ==="
    echo
    log "Resources deleted:"
    log "  • Event Grid subscription: blob-compression-subscription"
    if [ -n "${STORAGE_ACCOUNT:-}" ]; then
        log "  • Event Grid system topic: ${STORAGE_ACCOUNT}-topic"
        log "  • Storage account: ${STORAGE_ACCOUNT}"
    fi
    if [ -n "${FUNCTION_APP:-}" ]; then
        log "  • Function App: ${FUNCTION_APP}"
    fi
    log "  • Resource group: ${RESOURCE_GROUP} (deletion initiated)"
    echo
    log "Cleanup commands completed successfully"
    log "Resource group deletion may continue in the background"
    echo
    log "To verify complete deletion:"
    log "  az group exists --name ${RESOURCE_GROUP}"
    echo
}

# Function to handle script interruption
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        error "Cleanup failed. Check the error messages above."
        log "Some resources may still exist. You can:"
        log "  1. Re-run this script to retry cleanup"
        log "  2. Manually delete resources in the Azure portal"
        log "  3. Use Azure CLI commands to delete specific resources"
    fi
}

# Main cleanup function
main() {
    log "Starting Azure File Compression cleanup..."
    echo
    
    # Set up error handling
    trap cleanup_on_exit EXIT
    
    # Run cleanup steps
    validate_prerequisites
    setup_environment
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_event_grid_subscription
    delete_event_grid_topic
    delete_function_app
    delete_storage_containers
    delete_storage_account
    delete_resource_group
    
    verify_cleanup
    display_summary
    
    # Remove error trap on successful completion
    trap - EXIT
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    main "$@"
fi