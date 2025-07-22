#!/bin/bash

# =============================================================================
# Azure Network Security Orchestration - Cleanup Script
# =============================================================================
# This script removes all resources created by the deployment script
# 
# Features:
# - Safe deletion with confirmation prompts
# - Comprehensive resource cleanup
# - Force mode support (--force)
# - Graceful error handling
# - Automatic resource discovery
# - Detailed logging
# =============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe errors

# Colors for output
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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please log in to Azure CLI first using 'az login'"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load environment variables
load_environment_variables() {
    log "Loading environment variables..."
    
    # Script configuration
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Check if .env file exists
    if [ -f "${SCRIPT_DIR}/.env" ]; then
        source "${SCRIPT_DIR}/.env"
        success "Environment variables loaded from .env file"
    else
        warning ".env file not found. Using default values or prompting for input."
        
        # Prompt for resource group name
        read -p "Enter the resource group name to delete (default: rg-security-orchestration): " RESOURCE_GROUP
        export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-security-orchestration}"
        
        # Get other variables from Azure if resource group exists
        if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
            export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
            
            # Try to find resources in the resource group
            export LOGIC_APP_NAME=$(az logic workflow list --resource-group ${RESOURCE_GROUP} --query '[0].name' --output tsv 2>/dev/null || echo "")
            export KEY_VAULT_NAME=$(az keyvault list --resource-group ${RESOURCE_GROUP} --query '[0].name' --output tsv 2>/dev/null || echo "")
            export STORAGE_ACCOUNT_NAME=$(az storage account list --resource-group ${RESOURCE_GROUP} --query '[0].name' --output tsv 2>/dev/null || echo "")
            export NSG_NAME=$(az network nsg list --resource-group ${RESOURCE_GROUP} --query '[0].name' --output tsv 2>/dev/null || echo "")
            export VNET_NAME=$(az network vnet list --resource-group ${RESOURCE_GROUP} --query '[0].name' --output tsv 2>/dev/null || echo "")
            export LOG_ANALYTICS_NAME=$(az monitor log-analytics workspace list --resource-group ${RESOURCE_GROUP} --query '[0].name' --output tsv 2>/dev/null || echo "")
        else
            error "Resource group ${RESOURCE_GROUP} not found"
            exit 1
        fi
    fi
    
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Subscription ID: ${SUBSCRIPTION_ID}"
}

# Function to confirm deletion
confirm_deletion() {
    log "Resources to be deleted:"
    echo "=================================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    
    if [ ! -z "$LOGIC_APP_NAME" ]; then
        echo "Logic Apps Workflow: ${LOGIC_APP_NAME}"
    fi
    
    if [ ! -z "$KEY_VAULT_NAME" ]; then
        echo "Key Vault: ${KEY_VAULT_NAME}"
    fi
    
    if [ ! -z "$STORAGE_ACCOUNT_NAME" ]; then
        echo "Storage Account: ${STORAGE_ACCOUNT_NAME}"
    fi
    
    if [ ! -z "$NSG_NAME" ]; then
        echo "Network Security Group: ${NSG_NAME}"
    fi
    
    if [ ! -z "$VNET_NAME" ]; then
        echo "Virtual Network: ${VNET_NAME}"
    fi
    
    if [ ! -z "$LOG_ANALYTICS_NAME" ]; then
        echo "Log Analytics Workspace: ${LOG_ANALYTICS_NAME}"
    fi
    
    echo "=================================="
    
    warning "This action cannot be undone!"
    read -p "Are you sure you want to delete these resources? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    success "Deletion confirmed"
}

# Function to remove diagnostic settings
remove_diagnostic_settings() {
    log "Removing diagnostic settings..."
    
    if [ ! -z "$LOGIC_APP_NAME" ]; then
        az monitor diagnostic-settings delete \
            --name "SecurityOrchestrationLogs" \
            --resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Logic/workflows/${LOGIC_APP_NAME}" \
            2>/dev/null || warning "Diagnostic settings may not exist or already deleted"
        
        success "Diagnostic settings removed"
    fi
}

# Function to remove Logic Apps workflow
remove_logic_apps() {
    log "Removing Logic Apps workflow..."
    
    if [ ! -z "$LOGIC_APP_NAME" ]; then
        if az logic workflow show --name ${LOGIC_APP_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
            az logic workflow delete \
                --name ${LOGIC_APP_NAME} \
                --resource-group ${RESOURCE_GROUP} \
                --yes
            
            success "Logic Apps workflow deleted: ${LOGIC_APP_NAME}"
        else
            warning "Logic Apps workflow not found: ${LOGIC_APP_NAME}"
        fi
    fi
}

# Function to remove network infrastructure
remove_network_infrastructure() {
    log "Removing network infrastructure..."
    
    # Remove Network Security Group
    if [ ! -z "$NSG_NAME" ]; then
        if az network nsg show --name ${NSG_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
            az network nsg delete \
                --name ${NSG_NAME} \
                --resource-group ${RESOURCE_GROUP}
            
            success "Network Security Group deleted: ${NSG_NAME}"
        else
            warning "Network Security Group not found: ${NSG_NAME}"
        fi
    fi
    
    # Remove Virtual Network
    if [ ! -z "$VNET_NAME" ]; then
        if az network vnet show --name ${VNET_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
            az network vnet delete \
                --name ${VNET_NAME} \
                --resource-group ${RESOURCE_GROUP}
            
            success "Virtual Network deleted: ${VNET_NAME}"
        else
            warning "Virtual Network not found: ${VNET_NAME}"
        fi
    fi
}

# Function to remove storage account
remove_storage_account() {
    log "Removing storage account..."
    
    if [ ! -z "$STORAGE_ACCOUNT_NAME" ]; then
        if az storage account show --name ${STORAGE_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
            az storage account delete \
                --name ${STORAGE_ACCOUNT_NAME} \
                --resource-group ${RESOURCE_GROUP} \
                --yes
            
            success "Storage account deleted: ${STORAGE_ACCOUNT_NAME}"
        else
            warning "Storage account not found: ${STORAGE_ACCOUNT_NAME}"
        fi
    fi
}

# Function to remove Key Vault
remove_key_vault() {
    log "Removing Key Vault..."
    
    if [ ! -z "$KEY_VAULT_NAME" ]; then
        if az keyvault show --name ${KEY_VAULT_NAME} &> /dev/null; then
            # Delete Key Vault
            az keyvault delete \
                --name ${KEY_VAULT_NAME} \
                --resource-group ${RESOURCE_GROUP}
            
            # Purge Key Vault (permanent deletion)
            warning "Purging Key Vault permanently..."
            az keyvault purge \
                --name ${KEY_VAULT_NAME} \
                --location ${LOCATION:-eastus} \
                --no-wait || warning "Key Vault purge failed or not supported in this region"
            
            success "Key Vault deleted: ${KEY_VAULT_NAME}"
        else
            warning "Key Vault not found: ${KEY_VAULT_NAME}"
        fi
    fi
}

# Function to remove Log Analytics workspace
remove_log_analytics() {
    log "Removing Log Analytics workspace..."
    
    if [ ! -z "$LOG_ANALYTICS_NAME" ]; then
        if az monitor log-analytics workspace show --resource-group ${RESOURCE_GROUP} --workspace-name ${LOG_ANALYTICS_NAME} &> /dev/null; then
            az monitor log-analytics workspace delete \
                --resource-group ${RESOURCE_GROUP} \
                --workspace-name ${LOG_ANALYTICS_NAME} \
                --yes \
                --force
            
            success "Log Analytics workspace deleted: ${LOG_ANALYTICS_NAME}"
        else
            warning "Log Analytics workspace not found: ${LOG_ANALYTICS_NAME}"
        fi
    fi
}

# Function to remove resource group
remove_resource_group() {
    log "Removing resource group..."
    
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        warning "Deleting resource group will remove all remaining resources..."
        
        az group delete \
            --name ${RESOURCE_GROUP} \
            --yes \
            --no-wait
        
        success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        log "Note: Complete deletion may take several minutes"
    else
        warning "Resource group not found: ${RESOURCE_GROUP}"
    fi
}

# Function to wait for resource group deletion
wait_for_deletion() {
    log "Waiting for resource group deletion to complete..."
    
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while az group show --name ${RESOURCE_GROUP} &> /dev/null; do
        if [ $wait_time -ge $max_wait ]; then
            warning "Resource group deletion is taking longer than expected"
            log "You can check the deletion status in the Azure portal"
            break
        fi
        
        sleep 10
        wait_time=$((wait_time + 10))
        echo -n "."
    done
    
    echo ""
    
    if ! az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        success "Resource group deletion completed"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [ -f "${SCRIPT_DIR}/.env" ]; then
        rm -f "${SCRIPT_DIR}/.env"
        success "Environment file removed"
    fi
    
    # Remove any other temporary files
    rm -f .deployment_status 2>/dev/null || true
    
    success "Local cleanup completed"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    # Check if resource group still exists
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        warning "Resource group still exists: ${RESOURCE_GROUP}"
        log "This may be normal if deletion is still in progress"
    else
        success "Resource group successfully deleted: ${RESOURCE_GROUP}"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "=================================="
    echo "Resource Group: ${RESOURCE_GROUP} - Deleted"
    
    if [ ! -z "$LOGIC_APP_NAME" ]; then
        echo "Logic Apps Workflow: ${LOGIC_APP_NAME} - Deleted"
    fi
    
    if [ ! -z "$KEY_VAULT_NAME" ]; then
        echo "Key Vault: ${KEY_VAULT_NAME} - Deleted"
    fi
    
    if [ ! -z "$STORAGE_ACCOUNT_NAME" ]; then
        echo "Storage Account: ${STORAGE_ACCOUNT_NAME} - Deleted"
    fi
    
    if [ ! -z "$NSG_NAME" ]; then
        echo "Network Security Group: ${NSG_NAME} - Deleted"
    fi
    
    if [ ! -z "$VNET_NAME" ]; then
        echo "Virtual Network: ${VNET_NAME} - Deleted"
    fi
    
    if [ ! -z "$LOG_ANALYTICS_NAME" ]; then
        echo "Log Analytics Workspace: ${LOG_ANALYTICS_NAME} - Deleted"
    fi
    
    echo "=================================="
    
    success "Azure Network Security Orchestration cleanup completed successfully!"
    log "All resources have been removed to prevent ongoing charges"
}

# Main cleanup function
main() {
    log "Starting Azure Network Security Orchestration cleanup..."
    
    check_prerequisites
    load_environment_variables
    confirm_deletion
    remove_diagnostic_settings
    remove_logic_apps
    remove_network_infrastructure
    remove_storage_account
    remove_key_vault
    remove_log_analytics
    remove_resource_group
    wait_for_deletion
    cleanup_local_files
    validate_cleanup
    display_cleanup_summary
    
    success "Cleanup completed successfully!"
}

# Error handling function
cleanup_on_error() {
    error "An error occurred during cleanup"
    error "Some resources may still exist and could incur charges"
    error "Please check the Azure portal and manually delete any remaining resources"
    
    # Try to get resource group information for manual cleanup
    if [ ! -z "${RESOURCE_GROUP:-}" ]; then
        warning "Check the following resource group for remaining resources:"
        warning "Resource Group: ${RESOURCE_GROUP}"
        warning "Azure Portal: https://portal.azure.com/#@/resource/subscriptions/${SUBSCRIPTION_ID:-}/resourceGroups/${RESOURCE_GROUP}/overview"
    fi
    
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--force] [--help]"
            echo "  --force    Skip confirmation prompts"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Skip confirmation if force flag is set
if [ "${FORCE_DELETE:-false}" = "true" ]; then
    log "Force deletion enabled - skipping confirmation"
    confirm_deletion() {
        log "Skipping confirmation due to --force flag"
    }
fi

# Run main function
main "$@"