#!/bin/bash

# File Upload Processing with Azure Functions and Blob Storage - Cleanup Script
# This script removes all Azure resources created by the deployment script
# Recipe: file-upload-processing-functions-blob

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

# Error handling function
handle_error() {
    log_error "Cleanup failed at line $1"
    log_error "Some resources may still exist. Please check the Azure portal."
    exit 1
}

# Set up error trap
trap 'handle_error $LINENO' ERR

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Check if deployment info file exists
    if [ ! -f "deployment_info.txt" ]; then
        log_warning "deployment_info.txt not found. You'll need to provide resource information manually."
        return 1
    fi
    
    # Extract information from deployment info file
    export RESOURCE_GROUP=$(grep "Resource Group:" deployment_info.txt | cut -d' ' -f3)
    export LOCATION=$(grep "Location:" deployment_info.txt | cut -d' ' -f2)
    export STORAGE_ACCOUNT=$(grep "Storage Account:" deployment_info.txt | cut -d' ' -f3)
    export FUNCTION_APP=$(grep "Function App:" deployment_info.txt | cut -d' ' -f3)
    export CONTAINER_NAME=$(grep "Container Name:" deployment_info.txt | cut -d' ' -f3)
    
    if [ -z "${RESOURCE_GROUP}" ]; then
        log_error "Could not extract resource group from deployment_info.txt"
        return 1
    fi
    
    log_info "Loaded deployment information:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT}"
    log_info "  Function App: ${FUNCTION_APP}"
    log_info "  Container: ${CONTAINER_NAME}"
    
    return 0
}

# Function to get resource information manually
get_manual_input() {
    log_info "Please provide the resource information to clean up:"
    
    # Get resource group name
    echo -n "Enter the Resource Group name (e.g., rg-file-processing-abc123): "
    read -r RESOURCE_GROUP
    
    if [ -z "${RESOURCE_GROUP}" ]; then
        log_error "Resource Group name is required"
        exit 1
    fi
    
    # Verify resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Resource Group '${RESOURCE_GROUP}' not found"
        exit 1
    fi
    
    log_success "Resource Group found: ${RESOURCE_GROUP}"
}

# Function to display resources to be deleted
display_resources() {
    log_info "Checking resources in Resource Group: ${RESOURCE_GROUP}"
    
    # Get list of resources
    local resources=$(az resource list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].{Name:name, Type:type}" \
        --output table 2>/dev/null || echo "No resources found or unable to list resources")
    
    if [ -n "${resources}" ] && [ "${resources}" != "No resources found or unable to list resources" ]; then
        echo
        log_info "Resources that will be deleted:"
        echo "${resources}"
        echo
    else
        log_warning "No resources found in the resource group"
    fi
    
    # Get cost information if available
    log_info "Checking for any ongoing costs..."
    local cost_info=$(az consumption usage list \
        --billing-period-name $(az billing period list --query "[0].name" -o tsv 2>/dev/null || echo "current") \
        --max-items 1 \
        --query "[?contains(instanceId, '${RESOURCE_GROUP}')].{Resource:instanceName, Cost:pretaxCost}" \
        --output table 2>/dev/null || echo "Cost information not available")
    
    if [ -n "${cost_info}" ] && [ "${cost_info}" != "Cost information not available" ]; then
        echo
        log_info "Recent cost information:"
        echo "${cost_info}"
        echo
    fi
}

# Function to confirm deletion
confirm_deletion() {
    echo
    log_warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    log_warning "This will permanently delete the Resource Group '${RESOURCE_GROUP}' and ALL resources within it."
    log_warning "This action cannot be undone!"
    echo
    
    # Multiple confirmation prompts for safety
    echo -n "Are you sure you want to proceed? (yes/no): "
    read -r confirm1
    
    if [ "${confirm1}" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo -n "Type the resource group name to confirm deletion: "
    read -r confirm_rg
    
    if [ "${confirm_rg}" != "${RESOURCE_GROUP}" ]; then
        log_error "Resource group name does not match. Cleanup cancelled."
        exit 1
    fi
    
    echo -n "Final confirmation - type 'DELETE' to proceed: "
    read -r final_confirm
    
    if [ "${final_confirm}" != "DELETE" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Deletion confirmed by user"
}

# Function to backup critical data (optional)
backup_critical_data() {
    log_info "Checking for critical data to backup..."
    
    # Check if storage account exists and has data
    if [ -n "${STORAGE_ACCOUNT:-}" ] && az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        
        # Get storage connection string
        local storage_connection=$(az storage account show-connection-string \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query connectionString \
            --output tsv 2>/dev/null || echo "")
        
        if [ -n "${storage_connection}" ] && [ -n "${CONTAINER_NAME:-}" ]; then
            # Count blobs in container
            local blob_count=$(az storage blob list \
                --container-name "${CONTAINER_NAME}" \
                --connection-string "${storage_connection}" \
                --query "length(@)" \
                --output tsv 2>/dev/null || echo "0")
            
            if [ "${blob_count}" -gt 0 ]; then
                log_warning "Found ${blob_count} blob(s) in container '${CONTAINER_NAME}'"
                echo -n "Do you want to list the blobs before deletion? (y/n): "
                read -r list_blobs
                
                if [ "${list_blobs}" = "y" ] || [ "${list_blobs}" = "Y" ]; then
                    log_info "Blobs in container '${CONTAINER_NAME}':"
                    az storage blob list \
                        --container-name "${CONTAINER_NAME}" \
                        --connection-string "${storage_connection}" \
                        --query "[].{Name:name, Size:properties.contentLength, Modified:properties.lastModified}" \
                        --output table 2>/dev/null || log_warning "Could not list blobs"
                fi
                
                echo -n "Do you want to download all blobs for backup? (y/n): "
                read -r backup_blobs
                
                if [ "${backup_blobs}" = "y" ] || [ "${backup_blobs}" = "Y" ]; then
                    log_info "Downloading blobs to ./backup/ directory..."
                    mkdir -p backup
                    
                    az storage blob download-batch \
                        --destination backup \
                        --source "${CONTAINER_NAME}" \
                        --connection-string "${storage_connection}" \
                        --output none 2>/dev/null || log_warning "Some blobs may not have been downloaded"
                    
                    log_success "Blobs downloaded to ./backup/ directory"
                fi
            fi
        fi
    fi
}

# Function to stop function app gracefully
stop_function_app() {
    if [ -n "${FUNCTION_APP:-}" ]; then
        log_info "Stopping Function App: ${FUNCTION_APP}"
        
        # Check if function app exists
        if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            # Stop the function app gracefully
            az functionapp stop \
                --name "${FUNCTION_APP}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output none 2>/dev/null || log_warning "Could not stop Function App gracefully"
            
            log_success "Function App stopped"
            
            # Wait a moment for graceful shutdown
            sleep 5
        else
            log_warning "Function App '${FUNCTION_APP}' not found"
        fi
    fi
}

# Function to delete individual resources (if needed)
delete_individual_resources() {
    log_info "Attempting to delete individual resources first..."
    
    # Delete Function App
    if [ -n "${FUNCTION_APP:-}" ]; then
        if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_info "Deleting Function App: ${FUNCTION_APP}"
            az functionapp delete \
                --name "${FUNCTION_APP}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output none 2>/dev/null || log_warning "Could not delete Function App"
        fi
    fi
    
    # Delete Storage Account
    if [ -n "${STORAGE_ACCOUNT:-}" ]; then
        if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_info "Deleting Storage Account: ${STORAGE_ACCOUNT}"
            az storage account delete \
                --name "${STORAGE_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none 2>/dev/null || log_warning "Could not delete Storage Account"
        fi
    fi
    
    log_info "Individual resource deletion completed"
}

# Function to delete resource group
delete_resource_group() {
    log_info "Deleting Resource Group: ${RESOURCE_GROUP}"
    
    # Verify resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource Group '${RESOURCE_GROUP}' not found - may already be deleted"
        return 0
    fi
    
    # Delete resource group (this deletes all contained resources)
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    log_success "Resource Group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Deletion is running asynchronously and may take several minutes to complete"
    
    # Option to wait for completion
    echo -n "Do you want to wait for deletion to complete? (y/n): "
    read -r wait_completion
    
    if [ "${wait_completion}" = "y" ] || [ "${wait_completion}" = "Y" ]; then
        log_info "Waiting for resource group deletion to complete..."
        log_info "This may take several minutes..."
        
        # Wait for resource group to be deleted (check every 30 seconds)
        local max_wait=600  # 10 minutes
        local wait_time=0
        
        while [ ${wait_time} -lt ${max_wait} ]; do
            if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
                log_success "Resource Group deletion completed successfully"
                return 0
            fi
            
            echo -n "."
            sleep 30
            wait_time=$((wait_time + 30))
        done
        
        log_warning "Deletion is taking longer than expected, but is still in progress"
        log_info "You can check the status in the Azure portal"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment files
    local files_to_remove=(
        "deployment_info.txt"
        "function-deploy.zip"
        "test-file.txt"
        "test-image.jpg"
        "test-document.pdf"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "${file}" ]; then
            rm -f "${file}"
            log_info "Removed: ${file}"
        fi
    done
    
    # Remove function code directory
    if [ -d "function-code" ]; then
        rm -rf function-code
        log_info "Removed: function-code directory"
    fi
    
    # Ask about backup directory
    if [ -d "backup" ]; then
        echo -n "Remove backup directory? (y/n): "
        read -r remove_backup
        
        if [ "${remove_backup}" = "y" ] || [ "${remove_backup}" = "Y" ]; then
            rm -rf backup
            log_info "Removed: backup directory"
        else
            log_info "Kept: backup directory"
        fi
    fi
    
    log_success "Local files cleaned up"
}

# Function to display cleanup summary
display_summary() {
    log_success "=== CLEANUP COMPLETED ==="
    echo
    log_info "Summary:"
    echo "  ✅ Resource Group '${RESOURCE_GROUP}' deletion initiated"
    echo "  ✅ Local files cleaned up"
    echo
    log_info "Please note:"
    echo "  • Resource deletion may take several minutes to complete"
    echo "  • You can verify deletion in the Azure Portal"
    echo "  • Billing for resources stops when deletion is complete"
    echo
    log_info "If you backed up any data, it's stored in the ./backup/ directory"
    echo
    log_success "Cleanup completed successfully!"
}

# Function to handle cases where deployment info is not available
handle_no_deployment_info() {
    log_warning "No deployment information found"
    log_info "You can still clean up resources manually:"
    echo
    echo "1. Find your resource group in the Azure Portal"
    echo "2. Look for resource groups starting with 'rg-file-processing-'"
    echo "3. Delete the resource group containing your file processing resources"
    echo
    echo "Or run this script again and provide the resource group name manually."
    echo
    
    echo -n "Do you want to provide the resource group name now? (y/n): "
    read -r provide_name
    
    if [ "${provide_name}" = "y" ] || [ "${provide_name}" = "Y" ]; then
        get_manual_input
        return 0
    else
        log_info "Cleanup cancelled. Please clean up resources manually."
        exit 0
    fi
}

# Main cleanup function
main() {
    log_info "Starting Azure File Upload Processing cleanup..."
    log_info "Recipe: file-upload-processing-functions-blob"
    echo
    
    check_prerequisites
    
    # Try to load deployment information
    if ! load_deployment_info; then
        handle_no_deployment_info
    fi
    
    display_resources
    confirm_deletion
    backup_critical_data
    stop_function_app
    delete_individual_resources
    delete_resource_group
    cleanup_local_files
    display_summary
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi