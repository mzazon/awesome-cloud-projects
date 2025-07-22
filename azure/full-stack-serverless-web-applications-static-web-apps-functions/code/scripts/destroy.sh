#!/bin/bash

# Destroy script for Full-Stack Serverless Web Applications with Azure Static Web Apps and Azure Functions
# This script removes all resources created by the deployment script

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show > /dev/null 2>&1; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    success "Prerequisites validation completed"
}

# Function to get environment variables
get_environment_variables() {
    log "Getting environment variables..."
    
    # Try to get from environment or use defaults
    export RESOURCE_GROUP="${RESOURCE_GROUP:-}"
    export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-}"
    export STATIC_WEB_APP_NAME="${STATIC_WEB_APP_NAME:-}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    # If resource group is not provided, prompt for it
    if [ -z "$RESOURCE_GROUP" ]; then
        echo -n "Enter the resource group name to delete: "
        read RESOURCE_GROUP
        
        if [ -z "$RESOURCE_GROUP" ]; then
            error "Resource group name is required"
            exit 1
        fi
    fi
    
    log "Environment variables set:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Storage Account: $STORAGE_ACCOUNT_NAME"
    log "  Static Web App: $STATIC_WEB_APP_NAME"
    log "  Subscription ID: $SUBSCRIPTION_ID"
    
    success "Environment variables configured"
}

# Function to confirm deletion
confirm_deletion() {
    echo
    echo "============================================="
    echo "⚠️  WARNING: DESTRUCTIVE OPERATION"
    echo "============================================="
    echo
    echo "This will permanently delete the following resources:"
    echo "  - Resource Group: $RESOURCE_GROUP"
    echo "  - All resources within the resource group"
    echo "  - All data stored in the application"
    echo
    echo "This action cannot be undone!"
    echo
    echo -n "Are you sure you want to continue? (type 'YES' to confirm): "
    read confirmation
    
    if [ "$confirmation" != "YES" ]; then
        echo "Operation cancelled."
        exit 0
    fi
    
    echo
    echo "Proceeding with resource deletion..."
    echo
}

# Function to list resources in resource group
list_resources() {
    log "Listing resources in resource group..."
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" > /dev/null 2>&1; then
        warning "Resource group '$RESOURCE_GROUP' does not exist or is not accessible"
        return 1
    fi
    
    # List all resources in the group
    echo "Resources found in resource group '$RESOURCE_GROUP':"
    az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,Type:type,Location:location}" --output table
    
    success "Resource listing completed"
}

# Function to delete Static Web App
delete_static_web_app() {
    log "Deleting Static Web App..."
    
    # If Static Web App name is not provided, try to find it
    if [ -z "$STATIC_WEB_APP_NAME" ]; then
        log "Static Web App name not provided, searching for Static Web Apps in resource group..."
        STATIC_WEB_APP_NAME=$(az staticwebapp list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null)
    fi
    
    if [ -n "$STATIC_WEB_APP_NAME" ] && [ "$STATIC_WEB_APP_NAME" != "null" ]; then
        log "Found Static Web App: $STATIC_WEB_APP_NAME"
        
        # Check if Static Web App exists
        if az staticwebapp show --name "$STATIC_WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" > /dev/null 2>&1; then
            az staticwebapp delete \
                --name "$STATIC_WEB_APP_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            
            success "Static Web App deleted: $STATIC_WEB_APP_NAME"
        else
            warning "Static Web App '$STATIC_WEB_APP_NAME' not found"
        fi
    else
        warning "No Static Web App found in resource group"
    fi
}

# Function to delete storage account
delete_storage_account() {
    log "Deleting storage account..."
    
    # If storage account name is not provided, try to find it
    if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
        log "Storage account name not provided, searching for storage accounts in resource group..."
        STORAGE_ACCOUNT_NAME=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null)
    fi
    
    if [ -n "$STORAGE_ACCOUNT_NAME" ] && [ "$STORAGE_ACCOUNT_NAME" != "null" ]; then
        log "Found storage account: $STORAGE_ACCOUNT_NAME"
        
        # Check if storage account exists
        if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" > /dev/null 2>&1; then
            az storage account delete \
                --name "$STORAGE_ACCOUNT_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            
            success "Storage account deleted: $STORAGE_ACCOUNT_NAME"
        else
            warning "Storage account '$STORAGE_ACCOUNT_NAME' not found"
        fi
    else
        warning "No storage account found in resource group"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group..."
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" > /dev/null 2>&1; then
        warning "Resource group '$RESOURCE_GROUP' does not exist"
        return 0
    fi
    
    # Delete the resource group and all its resources
    log "Deleting resource group '$RESOURCE_GROUP' and all contained resources..."
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    success "Resource group deletion initiated: $RESOURCE_GROUP"
    log "Note: Deletion may take several minutes to complete in the background"
}

# Function to wait for resource group deletion
wait_for_deletion() {
    log "Waiting for resource group deletion to complete..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ! az group show --name "$RESOURCE_GROUP" > /dev/null 2>&1; then
            success "Resource group '$RESOURCE_GROUP' has been successfully deleted"
            return 0
        fi
        
        log "Waiting for deletion to complete... (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    warning "Resource group deletion is taking longer than expected"
    warning "You can check the status in the Azure Portal or run: az group show --name '$RESOURCE_GROUP'"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove application directory if it exists
    if [ -d "fullstack-serverless-app" ]; then
        log "Removing local application directory..."
        rm -rf fullstack-serverless-app
        success "Local application directory removed"
    fi
    
    # Remove configuration files
    if [ -f "staticwebapp.config.json" ]; then
        log "Removing Static Web App configuration..."
        rm -f staticwebapp.config.json
        success "Static Web App configuration removed"
    fi
    
    # Clear environment variables
    unset RESOURCE_GROUP STORAGE_ACCOUNT_NAME STATIC_WEB_APP_NAME
    unset STORAGE_CONNECTION_STRING STATIC_WEB_APP_URL SUBSCRIPTION_ID
    
    success "Local environment cleaned up"
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" > /dev/null 2>&1; then
        warning "Resource group '$RESOURCE_GROUP' still exists (deletion may be in progress)"
        log "You can monitor the deletion status in the Azure Portal"
    else
        success "Resource group '$RESOURCE_GROUP' has been successfully deleted"
    fi
    
    # Check for any remaining resources
    local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
    
    if [ "$remaining_resources" -gt 0 ]; then
        warning "Some resources may still exist in the resource group"
        log "Remaining resources:"
        az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,Type:type}" --output table 2>/dev/null
    fi
    
    success "Deletion verification completed"
}

# Function to show deletion summary
show_deletion_summary() {
    echo
    echo "============================================="
    echo "Deletion Summary"
    echo "============================================="
    echo
    echo "✅ Operations completed:"
    echo "  - Resource group deletion initiated: $RESOURCE_GROUP"
    echo "  - Static Web App deletion attempted"
    echo "  - Storage account deletion attempted"
    echo "  - Local files cleaned up"
    echo
    echo "📋 Important Notes:"
    echo "  - Resource deletion may take several minutes to complete"
    echo "  - You can monitor progress in the Azure Portal"
    echo "  - All data has been permanently deleted"
    echo
    echo "🔍 Verification:"
    echo "  Run 'az group show --name $RESOURCE_GROUP' to check deletion status"
    echo "  Resources should show as 'NotFound' when deletion is complete"
    echo
}

# Main deletion function
main() {
    echo "============================================="
    echo "Azure Static Web Apps Destruction Script"
    echo "============================================="
    echo
    
    validate_prerequisites
    get_environment_variables
    confirm_deletion
    list_resources
    delete_static_web_app
    delete_storage_account
    delete_resource_group
    cleanup_local_files
    verify_deletion
    show_deletion_summary
    
    echo "============================================="
    echo "Destruction completed!"
    echo "============================================="
    echo
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may not have been deleted."; exit 1' INT

# Run main function
main "$@"