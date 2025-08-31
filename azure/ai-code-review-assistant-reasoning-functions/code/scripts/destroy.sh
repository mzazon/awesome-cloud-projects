#!/bin/bash

# AI Code Review Assistant Cleanup Script
# Remove all Azure resources created by the deployment script

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy-$(date +%Y%m%d_%H%M%S).log"
CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Run 'az login' first"
    fi
    
    log "Prerequisites satisfied"
}

# Function to load configuration
load_configuration() {
    log "Loading deployment configuration..."
    
    if [ ! -f "$CONFIG_FILE" ]; then
        warning "Configuration file not found at $CONFIG_FILE"
        warning "You may need to specify resource names manually"
        
        # Prompt for manual configuration
        read -p "Enter resource group name (or press Enter to skip): " RESOURCE_GROUP
        if [ -z "$RESOURCE_GROUP" ]; then
            error_exit "Resource group name is required for cleanup"
        fi
        
        read -p "Enter storage account name (optional): " STORAGE_ACCOUNT
        read -p "Enter function app name (optional): " FUNCTION_APP
        read -p "Enter OpenAI account name (optional): " OPENAI_ACCOUNT
        
        # Create minimal config
        SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        LOCATION="eastus"
    else
        # Load from config file
        source "$CONFIG_FILE"
        log "Configuration loaded from $CONFIG_FILE"
    fi
    
    # Display configuration
    log "Cleanup Configuration:"
    log "  Subscription ID: ${SUBSCRIPTION_ID:-unknown}"
    log "  Resource Group: ${RESOURCE_GROUP:-unknown}"
    log "  Storage Account: ${STORAGE_ACCOUNT:-unknown}"
    log "  Function App: ${FUNCTION_APP:-unknown}"
    log "  OpenAI Account: ${OPENAI_ACCOUNT:-unknown}"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    echo -e "${RED}⚠️  WARNING: This will permanently delete the following resources:${NC}"
    echo -e "${RED}   - Resource Group: ${RESOURCE_GROUP}${NC}"
    echo -e "${RED}   - ALL resources within the resource group${NC}"
    echo ""
    
    # Double confirmation for safety
    read -p "Are you sure you want to proceed? This action cannot be undone. (yes/no): " -r
    if [[ ! $REPLY == "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    read -p "Type 'DELETE' to confirm resource deletion: " -r
    if [[ ! $REPLY == "DELETE" ]]; then
        log "Cleanup cancelled - confirmation not provided"
        exit 0
    fi
    
    log "User confirmed resource deletion"
}

# Function to list resources before deletion
list_resources() {
    log "Listing resources in resource group: $RESOURCE_GROUP"
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group $RESOURCE_GROUP does not exist"
        return 0
    fi
    
    # List all resources in the resource group
    echo "Resources to be deleted:"
    az resource list --resource-group "$RESOURCE_GROUP" --output table >> "$LOG_FILE" 2>&1
    
    # Display summary
    local resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv)
    log "Found $resource_count resources in resource group"
}

# Function to delete specific resources (optional, for granular control)
delete_individual_resources() {
    log "Deleting individual resources for safer cleanup..."
    
    # Delete Function App
    if [ -n "${FUNCTION_APP:-}" ]; then
        log "Deleting Function App: $FUNCTION_APP"
        if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az functionapp delete \
                --name "$FUNCTION_APP" \
                --resource-group "$RESOURCE_GROUP" \
                --output table >> "$LOG_FILE" 2>&1
            
            if [ $? -eq 0 ]; then
                success "Function App deleted: $FUNCTION_APP"
            else
                warning "Failed to delete Function App: $FUNCTION_APP"
            fi
        else
            log "Function App $FUNCTION_APP not found"
        fi
    fi
    
    # Delete OpenAI Service
    if [ -n "${OPENAI_ACCOUNT:-}" ]; then
        log "Deleting Azure OpenAI service: $OPENAI_ACCOUNT"
        if az cognitiveservices account show --name "$OPENAI_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az cognitiveservices account delete \
                --name "$OPENAI_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --output table >> "$LOG_FILE" 2>&1
            
            if [ $? -eq 0 ]; then
                success "OpenAI service deleted: $OPENAI_ACCOUNT"
            else
                warning "Failed to delete OpenAI service: $OPENAI_ACCOUNT"
            fi
        else
            log "OpenAI service $OPENAI_ACCOUNT not found"
        fi
    fi
    
    # Delete Storage Account
    if [ -n "${STORAGE_ACCOUNT:-}" ]; then
        log "Deleting Storage Account: $STORAGE_ACCOUNT"
        if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az storage account delete \
                --name "$STORAGE_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output table >> "$LOG_FILE" 2>&1
            
            if [ $? -eq 0 ]; then
                success "Storage Account deleted: $STORAGE_ACCOUNT"
            else
                warning "Failed to delete Storage Account: $STORAGE_ACCOUNT"
            fi
        else
            log "Storage Account $STORAGE_ACCOUNT not found"
        fi
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group: $RESOURCE_GROUP"
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group $RESOURCE_GROUP does not exist"
        return 0
    fi
    
    # Delete resource group and all resources within it
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output table >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        success "Resource group deletion initiated: $RESOURCE_GROUP"
        log "Note: Deletion may take several minutes to complete"
        
        # Monitor deletion progress
        monitor_deletion
    else
        error_exit "Failed to initiate resource group deletion"
    fi
}

# Function to monitor deletion progress
monitor_deletion() {
    log "Monitoring resource group deletion progress..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            success "Resource group deletion completed: $RESOURCE_GROUP"
            return 0
        fi
        
        log "Deletion in progress... (attempt $attempt/$max_attempts)"
        sleep 30
        ((attempt++))
    done
    
    warning "Deletion monitoring timed out. Resource group may still be deleting in the background"
    log "You can check the status in the Azure portal or run: az group show --name $RESOURCE_GROUP"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local deployment files..."
    
    if [ -f "$CONFIG_FILE" ]; then
        # Archive the config file instead of deleting it
        local archive_name="${CONFIG_FILE}.$(date +%Y%m%d_%H%M%S).bak"
        mv "$CONFIG_FILE" "$archive_name"
        log "Configuration file archived as: $archive_name"
    fi
    
    # Clean up any temporary files
    local temp_files=("${SCRIPT_DIR}/.azure_temp" "${SCRIPT_DIR}/deployment_*.tmp")
    for temp_file in "${temp_files[@]}"; do
        if [ -f "$temp_file" ]; then
            rm -f "$temp_file"
            log "Cleaned up temporary file: $temp_file"
        fi
    done
    
    success "Local cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group $RESOURCE_GROUP still exists"
        warning "Deletion may still be in progress"
        
        local resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")
        if [ "$resource_count" -eq 0 ]; then
            log "Resource group is empty - deletion should complete shortly"
        else
            warning "$resource_count resources still exist in the resource group"
        fi
    else
        success "Resource group successfully deleted: $RESOURCE_GROUP"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "=== CLEANUP SUMMARY ==="
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Storage Account: ${STORAGE_ACCOUNT:-N/A}"
    log "Function App: ${FUNCTION_APP:-N/A}"
    log "OpenAI Account: ${OPENAI_ACCOUNT:-N/A}"
    log "Cleanup Log: $LOG_FILE"
    log ""
    log "✅ Cleanup completed!"
    log "Note: Some resources may take additional time to be fully removed from Azure"
    log "You can verify complete removal by checking the Azure portal"
}

# Function to handle cleanup method selection
select_cleanup_method() {
    echo ""
    echo "Select cleanup method:"
    echo "1. Delete entire resource group (recommended - faster)"
    echo "2. Delete individual resources first, then resource group (safer)"
    echo "3. Cancel cleanup"
    echo ""
    
    read -p "Enter your choice (1-3): " -n 1 -r
    echo ""
    
    case $REPLY in
        1)
            log "Selected: Delete entire resource group"
            return 1
            ;;
        2)
            log "Selected: Delete individual resources first"
            return 2
            ;;
        3)
            log "Cleanup cancelled by user"
            exit 0
            ;;
        *)
            warning "Invalid selection. Defaulting to resource group deletion"
            return 1
            ;;
    esac
}

# Main cleanup function
main() {
    log "=== AI Code Review Assistant Cleanup Started ==="
    log "Cleanup log: $LOG_FILE"
    
    check_prerequisites
    load_configuration
    list_resources
    confirm_deletion
    
    # Select cleanup method
    select_cleanup_method
    local method=$?
    
    if [ $method -eq 2 ]; then
        delete_individual_resources
        delete_resource_group
    else
        delete_resource_group
    fi
    
    cleanup_local_files
    verify_cleanup
    display_summary
    
    log "=== Cleanup Completed ==="
}

# Handle script interruption
trap 'log "Cleanup interrupted"; exit 1' INT TERM

# Run main function
main "$@"