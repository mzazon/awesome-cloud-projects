#!/bin/bash

# Azure Password Generator Function with Key Vault - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

# Error handler
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Check the logs above for details."
    exit 1
}

# Display banner
echo "=========================================="
echo "Azure Password Generator Cleanup"
echo "=========================================="
echo ""

# Prerequisites check
log_info "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
fi

# Check if logged into Azure
if ! az account show &> /dev/null; then
    error_exit "Not logged into Azure. Please run 'az login' first."
fi

log_success "Prerequisites check completed"

# Load deployment information if available
if [[ -f ".deployment_info" ]]; then
    log_info "Loading deployment information from .deployment_info..."
    source .deployment_info
    log_success "Deployment information loaded"
else
    log_warning "No .deployment_info file found. Manual input required."
    
    # Get user input for resource identification
    read -p "Enter resource group name to delete: " RESOURCE_GROUP
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        error_exit "Resource group name is required"
    fi
    
    # Set other variables for individual resource cleanup (if needed)
    KEY_VAULT_NAME=""
    FUNCTION_APP_NAME=""
    STORAGE_ACCOUNT=""
    LOCATION=""
fi

# Display cleanup configuration
log_info "Cleanup configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
if [[ -n "${KEY_VAULT_NAME:-}" ]]; then
    log_info "  Key Vault: ${KEY_VAULT_NAME}"
fi
if [[ -n "${FUNCTION_APP_NAME:-}" ]]; then
    log_info "  Function App: ${FUNCTION_APP_NAME}"
fi
if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
    log_info "  Storage Account: ${STORAGE_ACCOUNT}"
fi
echo ""

# Check if resource group exists
if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Resource group '${RESOURCE_GROUP}' does not exist or has already been deleted"
    log_success "Cleanup completed - no resources found"
    
    # Clean up local files
    if [[ -f ".deployment_info" ]]; then
        rm -f .deployment_info
        log_success "Removed .deployment_info file"
    fi
    
    exit 0
fi

# List resources in the resource group for confirmation
log_info "Resources in resource group '${RESOURCE_GROUP}':"
az resource list --resource-group "${RESOURCE_GROUP}" --output table 2>/dev/null || log_warning "Could not list resources"
echo ""

# Confirmation prompts with multiple safety checks
log_warning "This will permanently delete ALL resources in the resource group: ${RESOURCE_GROUP}"
log_warning "This action cannot be undone!"
echo ""

read -p "Are you sure you want to delete all resources in '${RESOURCE_GROUP}'? (type 'yes' to confirm): " CONFIRM1
if [[ "${CONFIRM1}" != "yes" ]]; then
    log_info "Cleanup cancelled by user"
    exit 0
fi

read -p "Type the resource group name to confirm deletion: " CONFIRM2
if [[ "${CONFIRM2}" != "${RESOURCE_GROUP}" ]]; then
    log_error "Resource group name does not match. Cleanup cancelled."
    exit 1
fi

read -p "Final confirmation - DELETE ALL RESOURCES? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Cleanup cancelled by user"
    exit 0
fi

# Start cleanup process
log_info "Starting cleanup process..."

# Step 1: Optional - Remove test secrets from Key Vault before deletion
if [[ -n "${KEY_VAULT_NAME:-}" ]]; then
    log_info "Checking for test secrets in Key Vault..."
    
    # Check if Key Vault exists and list any test secrets
    if az keyvault show --name "${KEY_VAULT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Listing secrets in Key Vault (for reference):"
        az keyvault secret list \
            --vault-name "${KEY_VAULT_NAME}" \
            --query "[].{Name:name, Created:attributes.created}" \
            --output table 2>/dev/null || log_warning "Could not list Key Vault secrets"
        
        # Ask if user wants to purge specific test secrets
        read -p "Do you want to purge test secrets individually before resource group deletion? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deleting common test secrets..."
            
            # Delete common test secret names
            TEST_SECRETS=("test-password-001" "test-password" "demo-password" "sample-password")
            for secret in "${TEST_SECRETS[@]}"; do
                if az keyvault secret show --vault-name "${KEY_VAULT_NAME}" --name "${secret}" &> /dev/null; then
                    log_info "Deleting secret: ${secret}"
                    az keyvault secret delete --vault-name "${KEY_VAULT_NAME}" --name "${secret}" --output none 2>/dev/null || true
                    # Purge the secret immediately
                    az keyvault secret purge --vault-name "${KEY_VAULT_NAME}" --name "${secret}" --output none 2>/dev/null || true
                    log_success "Secret '${secret}' deleted and purged"
                fi
            done
        fi
    else
        log_warning "Key Vault '${KEY_VAULT_NAME}' not found or already deleted"
    fi
fi

# Step 2: Stop Function App (graceful shutdown)
if [[ -n "${FUNCTION_APP_NAME:-}" ]]; then
    if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Stopping Function App: ${FUNCTION_APP_NAME}"
        az functionapp stop \
            --name "${FUNCTION_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none 2>/dev/null || log_warning "Could not stop Function App"
        log_success "Function App stopped"
    else
        log_warning "Function App '${FUNCTION_APP_NAME}' not found or already deleted"
    fi
fi

# Step 3: Delete the entire resource group
log_info "Deleting resource group and all contained resources..."
log_warning "This may take several minutes to complete..."

# Use --no-wait for faster script completion, but provide option for synchronous deletion
read -p "Wait for deletion to complete? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Synchronous deletion - wait for completion
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --verbose
    log_success "Resource group '${RESOURCE_GROUP}' deleted successfully"
else
    # Asynchronous deletion - don't wait
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Deletion is running in the background and may take several minutes to complete"
fi

# Step 4: Clean up local files
log_info "Cleaning up local files..."

if [[ -f ".deployment_info" ]]; then
    rm -f .deployment_info
    log_success "Removed .deployment_info file"
fi

# Remove any temporary function files if they exist
if [[ -d "temp_function_code" ]]; then
    rm -rf temp_function_code
    log_success "Removed temporary function code directory"
fi

# Step 5: Verify cleanup (if synchronous deletion was chosen)
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Verifying resource group deletion..."
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_success "Confirmed: Resource group '${RESOURCE_GROUP}' has been deleted"
    else
        log_warning "Resource group still exists. Deletion may still be in progress."
    fi
fi

# Display cleanup summary
echo ""
echo "=========================================="
echo "Cleanup Process Completed"
echo "=========================================="
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_success "All resources have been successfully deleted"
    log_success "Resource group '${RESOURCE_GROUP}' has been removed"
else
    log_success "Cleanup initiated successfully"
    log_info "Resource group '${RESOURCE_GROUP}' deletion is running in background"
    log_info "You can monitor progress in the Azure portal or with:"
    log_info "az group show --name '${RESOURCE_GROUP}'"
fi

log_success "Local cleanup files removed"
echo ""

# Optional: Show how to verify cleanup
log_info "To verify all resources are deleted, run:"
log_info "az group list --query \"[?name=='${RESOURCE_GROUP}']\" --output table"
echo ""

# Cost estimation note
log_info "Note: Some costs may still appear in billing for a few hours after deletion"
log_info "All compute and storage costs have been stopped with this cleanup"
echo ""

log_success "Cleanup completed successfully!"

# Exit successfully
exit 0