#!/bin/bash

# Destroy script for Simple Contact Form with Functions and Table Storage
# This script removes all Azure resources created by the deployment script
# following the recipe: Simple Contact Form with Functions and Table Storage

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    success "Prerequisites validation completed"
}

# Set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Check if RESOURCE_GROUP is provided
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        error "RESOURCE_GROUP environment variable is required"
        error "Please set it to the resource group you want to delete:"
        error "export RESOURCE_GROUP=your-resource-group-name"
        exit 1
    fi
    
    # Set other variables based on resource group or defaults
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}"
    export FUNCTION_APP="${FUNCTION_APP:-}"
    export TABLE_NAME="${TABLE_NAME:-contacts}"
    
    log "Resource Group to delete: $RESOURCE_GROUP"
    
    # Verify resource group exists
    if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warn "Resource group $RESOURCE_GROUP does not exist or is not accessible"
        log "Available resource groups:"
        az group list --query "[].name" --output table 2>/dev/null || true
        exit 1
    fi
}

# List resources in the resource group
list_resources() {
    log "Listing resources in resource group: $RESOURCE_GROUP"
    
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output table 2>/dev/null || echo "No resources found")
    
    if [[ "$resources" == "No resources found" ]]; then
        warn "No resources found in resource group $RESOURCE_GROUP"
        return 0
    fi
    
    echo "$resources"
    log "Found $(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv) resources"
}

# Confirm destruction
confirm_destruction() {
    log "This will permanently delete all resources in resource group: $RESOURCE_GROUP"
    
    # Check if running in non-interactive mode
    if [[ "${SKIP_CONFIRMATION:-false}" == "true" ]]; then
        warn "Skipping confirmation due to SKIP_CONFIRMATION=true"
        return 0
    fi
    
    local response
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " response
    
    if [[ "$response" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed, proceeding..."
}

# Delete Function App
delete_function_app() {
    if [[ -n "${FUNCTION_APP:-}" ]]; then
        log "Deleting Function App: $FUNCTION_APP"
        
        if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            az functionapp delete \
                --name "$FUNCTION_APP" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            
            success "Function App deleted: $FUNCTION_APP"
        else
            warn "Function App $FUNCTION_APP not found or already deleted"
        fi
    else
        log "Attempting to find and delete Function Apps in resource group..."
        
        local function_apps
        function_apps=$(az functionapp list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$function_apps" ]]; then
            while IFS= read -r app_name; do
                if [[ -n "$app_name" ]]; then
                    log "Deleting Function App: $app_name"
                    az functionapp delete \
                        --name "$app_name" \
                        --resource-group "$RESOURCE_GROUP" \
                        --yes
                    success "Function App deleted: $app_name"
                fi
            done <<< "$function_apps"
        else
            log "No Function Apps found in resource group"
        fi
    fi
}

# Delete Table Storage (individual table)
delete_table_storage() {
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        log "Deleting Table Storage table: $TABLE_NAME"
        
        # Get storage connection string
        local storage_connection
        storage_connection=$(az storage account show-connection-string \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --query connectionString \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$storage_connection" ]]; then
            # Check if table exists and delete it
            if az storage table exists \
                --name "$TABLE_NAME" \
                --connection-string "$storage_connection" \
                --query exists \
                --output tsv 2>/dev/null | grep -q "true"; then
                
                az storage table delete \
                    --name "$TABLE_NAME" \
                    --connection-string "$storage_connection" \
                    --fail-not-exist
                
                success "Table deleted: $TABLE_NAME"
            else
                warn "Table $TABLE_NAME not found or already deleted"
            fi
        else
            warn "Could not get storage connection string for $STORAGE_ACCOUNT"
        fi
    else
        log "No specific storage account provided, tables will be deleted with storage accounts"
    fi
}

# Delete Storage Account
delete_storage_account() {
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        log "Deleting Storage Account: $STORAGE_ACCOUNT"
        
        if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
            az storage account delete \
                --name "$STORAGE_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            
            success "Storage Account deleted: $STORAGE_ACCOUNT"
        else
            warn "Storage Account $STORAGE_ACCOUNT not found or already deleted"
        fi
    else
        log "Attempting to find and delete Storage Accounts in resource group..."
        
        local storage_accounts
        storage_accounts=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$storage_accounts" ]]; then
            while IFS= read -r account_name; do
                if [[ -n "$account_name" ]]; then
                    log "Deleting Storage Account: $account_name"
                    az storage account delete \
                        --name "$account_name" \
                        --resource-group "$RESOURCE_GROUP" \
                        --yes
                    success "Storage Account deleted: $account_name"
                fi
            done <<< "$storage_accounts"
        else
            log "No Storage Accounts found in resource group"
        fi
    fi
}

# Delete Resource Group
delete_resource_group() {
    log "Deleting Resource Group: $RESOURCE_GROUP"
    
    # Final confirmation for resource group deletion
    if [[ "${SKIP_CONFIRMATION:-false}" != "true" ]]; then
        local response
        read -p "Final confirmation: Delete resource group $RESOURCE_GROUP and ALL its contents? (type 'DELETE' to confirm): " response
        
        if [[ "$response" != "DELETE" ]]; then
            log "Resource group deletion cancelled by user"
            exit 0
        fi
    fi
    
    # Delete resource group and all contained resources
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    success "Resource group deletion initiated: $RESOURCE_GROUP"
    log "Note: Deletion may take several minutes to complete in the background"
    
    # Optionally wait for deletion to complete if requested
    if [[ "${WAIT_FOR_COMPLETION:-false}" == "true" ]]; then
        log "Waiting for resource group deletion to complete..."
        
        local max_wait=1800  # 30 minutes
        local wait_time=0
        local check_interval=30
        
        while az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1 && [[ $wait_time -lt $max_wait ]]; do
            log "Still deleting... (waited ${wait_time}s)"
            sleep $check_interval
            wait_time=$((wait_time + check_interval))
        done
        
        if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
            warn "Resource group deletion is taking longer than expected"
            log "You can check the status in the Azure portal or run: az group show --name $RESOURCE_GROUP"
        else
            success "Resource group deletion completed"
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove function URL file if it exists
    local url_file="${RESOURCE_GROUP}_function_url.txt"
    if [[ -f "$url_file" ]]; then
        rm -f "$url_file"
        success "Removed local file: $url_file"
    fi
    
    # Remove any temporary files that might have been left behind
    local temp_files=(
        "contact-function.zip"
        "contact-function"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -e "$file" ]]; then
            rm -rf "$file"
            success "Removed local file/directory: $file"
        fi
    done
    
    log "Local file cleanup completed"
}

# Verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warn "Resource group $RESOURCE_GROUP still exists"
        
        # List remaining resources
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining_resources" -gt 0 ]]; then
            warn "Found $remaining_resources remaining resources in the resource group"
            log "Remaining resources:"
            az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output table 2>/dev/null || true
        else
            log "Resource group exists but contains no resources (deletion may be in progress)"
        fi
    else
        success "Resource group $RESOURCE_GROUP has been successfully deleted"
    fi
}

# Main destruction function
main() {
    log "Starting destruction of Simple Contact Form with Functions and Table Storage"
    
    validate_prerequisites
    set_environment_variables
    list_resources
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_function_app
    delete_table_storage
    delete_storage_account
    delete_resource_group
    cleanup_local_files
    verify_deletion
    
    success "Destruction process completed!"
    log "Resource Group: $RESOURCE_GROUP"
    
    if [[ "${WAIT_FOR_COMPLETION:-false}" != "true" ]]; then
        log "Note: Resource deletion continues in the background"
        log "You can monitor progress in the Azure portal"
        log "To wait for completion next time, set: export WAIT_FOR_COMPLETION=true"
    fi
    
    log "All local files have been cleaned up"
    log "Destruction process finished successfully"
}

# Display usage information
usage() {
    echo "Usage: $0"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP        (Required) Resource group to delete"
    echo "  STORAGE_ACCOUNT       (Optional) Specific storage account name"
    echo "  FUNCTION_APP          (Optional) Specific function app name"
    echo "  TABLE_NAME           (Optional) Table name (default: contacts)"
    echo "  SKIP_CONFIRMATION    (Optional) Skip confirmation prompts (default: false)"
    echo "  WAIT_FOR_COMPLETION  (Optional) Wait for deletion to complete (default: false)"
    echo ""
    echo "Examples:"
    echo "  export RESOURCE_GROUP=rg-recipe-abc123"
    echo "  $0"
    echo ""
    echo "  export RESOURCE_GROUP=rg-recipe-abc123"
    echo "  export SKIP_CONFIRMATION=true"
    echo "  export WAIT_FOR_COMPLETION=true"
    echo "  $0"
}

# Handle command line arguments
case "${1:-}" in
    -h|--help|help)
        usage
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac