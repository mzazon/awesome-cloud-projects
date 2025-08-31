#!/bin/bash

# Destruction script for Simple Expense Tracker with Cosmos DB and Functions
# This script removes all Azure resources created by the deploy.sh script

set -euo pipefail

# Colors for output
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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Try to load from deployment-info.txt if available
    if [[ -f "deployment-info.txt" ]]; then
        export RESOURCE_GROUP=$(grep "Resource Group:" deployment-info.txt | cut -d' ' -f3 || echo "")
        export COSMOS_ACCOUNT=$(grep "Cosmos DB Account:" deployment-info.txt | cut -d' ' -f4 || echo "")
        export FUNCTION_APP=$(grep "Function App:" deployment-info.txt | cut -d' ' -f3 || echo "")
        export STORAGE_ACCOUNT=$(grep "Storage Account:" deployment-info.txt | cut -d' ' -f3 || echo "")
        
        if [[ -n "${RESOURCE_GROUP}" ]]; then
            log_success "Loaded deployment info from deployment-info.txt"
            log_info "Resource Group: ${RESOURCE_GROUP}"
            return 0
        fi
    fi
    
    # If no deployment info file or empty values, try to discover resources
    log_warning "No deployment-info.txt found or incomplete. Attempting to discover resources..."
    
    # Look for resource groups that match our pattern
    local rg_candidates=$(az group list --query "[?starts_with(name, 'rg-expense-tracker-')].name" --output tsv 2>/dev/null || echo "")
    
    if [[ -z "${rg_candidates}" ]]; then
        log_error "No expense tracker resource groups found."
        log_info "If you know the resource group name, you can run: az group delete --name YOUR_RESOURCE_GROUP"
        exit 1
    fi
    
    # If only one candidate, use it
    local rg_count=$(echo "${rg_candidates}" | wc -l)
    if [[ ${rg_count} -eq 1 ]]; then
        export RESOURCE_GROUP="${rg_candidates}"
        log_info "Found resource group: ${RESOURCE_GROUP}"
    else
        log_warning "Multiple expense tracker resource groups found:"
        echo "${rg_candidates}"
        echo
        read -p "Enter the resource group name to delete: " RESOURCE_GROUP
        
        if [[ -z "${RESOURCE_GROUP}" ]]; then
            log_error "No resource group specified. Exiting."
            exit 1
        fi
    fi
    
    # Discover resources in the selected resource group
    discover_resources_in_group
}

# Discover resources in the specified resource group
discover_resources_in_group() {
    log_info "Discovering resources in group: ${RESOURCE_GROUP}"
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Resource group ${RESOURCE_GROUP} does not exist."
        exit 1
    fi
    
    # Find Cosmos DB accounts
    local cosmos_accounts=$(az cosmosdb list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "${cosmos_accounts}" ]]; then
        export COSMOS_ACCOUNT=$(echo "${cosmos_accounts}" | head -n1)
        log_info "Found Cosmos DB account: ${COSMOS_ACCOUNT}"
    fi
    
    # Find Function Apps
    local function_apps=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "${function_apps}" ]]; then
        export FUNCTION_APP=$(echo "${function_apps}" | head -n1)
        log_info "Found Function App: ${FUNCTION_APP}"
    fi
    
    # Find Storage Accounts
    local storage_accounts=$(az storage account list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "${storage_accounts}" ]]; then
        export STORAGE_ACCOUNT=$(echo "${storage_accounts}" | head -n1)
        log_info "Found Storage Account: ${STORAGE_ACCOUNT}"
    fi
}

# Display resources to be deleted
display_resources() {
    log_info "Resources that will be deleted:"
    echo
    echo -e "${YELLOW}Resource Group:${NC} ${RESOURCE_GROUP:-Not specified}"
    
    if [[ -n "${COSMOS_ACCOUNT:-}" ]]; then
        echo -e "${YELLOW}Cosmos DB Account:${NC} ${COSMOS_ACCOUNT}"
    fi
    
    if [[ -n "${FUNCTION_APP:-}" ]]; then
        echo -e "${YELLOW}Function App:${NC} ${FUNCTION_APP}"
    fi
    
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        echo -e "${YELLOW}Storage Account:${NC} ${STORAGE_ACCOUNT}"
    fi
    
    # List all resources in the resource group
    log_info "All resources in resource group:"
    az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" --output table 2>/dev/null || log_warning "Could not list resources"
    echo
}

# Confirm deletion
confirm_deletion() {
    log_warning "This operation will permanently delete all resources and data!"
    echo -e "${RED}WARNING: This action cannot be undone!${NC}"
    echo
    
    # Extra confirmation for production-like resource groups
    if [[ "${RESOURCE_GROUP}" == *"prod"* ]] || [[ "${RESOURCE_GROUP}" == *"production"* ]]; then
        log_error "This appears to be a production resource group!"
        echo -e "${RED}Extra confirmation required for production resources.${NC}"
        echo
        read -p "Type 'DELETE PRODUCTION' to confirm: " confirmation
        if [[ "${confirmation}" != "DELETE PRODUCTION" ]]; then
            log_info "Destruction cancelled."
            exit 0
        fi
    else
        read -p "Are you sure you want to delete these resources? (yes/no): " confirmation
        if [[ "${confirmation}" != "yes" ]] && [[ "${confirmation}" != "y" ]]; then
            log_info "Destruction cancelled."
            exit 0
        fi
    fi
    
    log_info "Proceeding with resource deletion..."
}

# Delete individual resources (if needed)
delete_individual_resources() {
    log_info "Attempting to delete individual resources first..."
    
    # Delete Function App
    if [[ -n "${FUNCTION_APP:-}" ]]; then
        log_info "Deleting Function App: ${FUNCTION_APP}"
        if az functionapp delete --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" --yes &> /dev/null; then
            log_success "Function App deleted: ${FUNCTION_APP}"
        else
            log_warning "Could not delete Function App individually"
        fi
    fi
    
    # Delete Cosmos DB Account
    if [[ -n "${COSMOS_ACCOUNT:-}" ]]; then
        log_info "Deleting Cosmos DB Account: ${COSMOS_ACCOUNT}"
        if az cosmosdb delete --name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --yes &> /dev/null; then
            log_success "Cosmos DB Account deleted: ${COSMOS_ACCOUNT}"
        else
            log_warning "Could not delete Cosmos DB Account individually"
        fi
    fi
    
    # Delete Storage Account
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        log_info "Deleting Storage Account: ${STORAGE_ACCOUNT}"
        if az storage account delete --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --yes &> /dev/null; then
            log_success "Storage Account deleted: ${STORAGE_ACCOUNT}"
        else
            log_warning "Could not delete Storage Account individually"
        fi
    fi
    
    log_info "Individual resource deletion attempts completed"
}

# Delete resource group
delete_resource_group() {
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    log_info "This may take several minutes..."
    
    # Try synchronous deletion first (faster feedback)
    if az group delete --name "${RESOURCE_GROUP}" --yes --no-wait; then
        log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        log_info "Deletion is running in the background and may take several minutes to complete"
        
        # Optional: Wait and check progress
        read -p "Wait for deletion to complete? (yes/no): " wait_confirmation
        if [[ "${wait_confirmation}" == "yes" ]] || [[ "${wait_confirmation}" == "y" ]]; then
            log_info "Waiting for deletion to complete..."
            
            # Check deletion progress
            local max_attempts=30
            local attempt=0
            while [[ ${attempt} -lt ${max_attempts} ]]; do
                if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
                    log_success "Resource group successfully deleted!"
                    break
                fi
                
                attempt=$((attempt + 1))
                log_info "Still deleting... (attempt ${attempt}/${max_attempts})"
                sleep 30
            done
            
            if [[ ${attempt} -eq ${max_attempts} ]]; then
                log_warning "Deletion is taking longer than expected but is still in progress"
                log_info "You can check status in the Azure portal"
            fi
        fi
    else
        log_error "Failed to initiate resource group deletion"
        log_info "You may need to delete resources manually in the Azure portal"
        exit 1
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove function code directory
    if [[ -d "expense-functions" ]]; then
        rm -rf expense-functions
        log_success "Removed expense-functions directory"
    fi
    
    # Remove deployment package
    if [[ -f "functions.zip" ]]; then
        rm -f functions.zip
        log_success "Removed functions.zip"
    fi
    
    # Optionally remove deployment info
    if [[ -f "deployment-info.txt" ]]; then
        read -p "Remove deployment-info.txt? (yes/no): " remove_info
        if [[ "${remove_info}" == "yes" ]] || [[ "${remove_info}" == "y" ]]; then
            rm -f deployment-info.txt
            log_success "Removed deployment-info.txt"
        else
            log_info "Kept deployment-info.txt for reference"
        fi
    fi
    
    # Clear exported environment variables
    unset RESOURCE_GROUP COSMOS_ACCOUNT FUNCTION_APP STORAGE_ACCOUNT
    unset COSMOS_CONNECTION_STRING RANDOM_SUFFIX
    
    log_success "Local cleanup completed"
}

# Verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group still exists - deletion may still be in progress"
        log_info "Check the Azure portal for current status"
    else
        log_success "Resource group has been successfully deleted"
    fi
}

# Main destruction function
main() {
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                    RESOURCE DESTRUCTION                     ║${NC}"
    echo -e "${RED}║               Simple Expense Tracker Cleanup                ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
    
    check_prerequisites
    load_deployment_info
    display_resources
    confirm_deletion
    delete_individual_resources
    delete_resource_group
    cleanup_local_files
    verify_deletion
    
    echo
    log_success "🗑️  Cleanup completed!"
    echo
    echo -e "${GREEN}Summary:${NC}"
    echo "• All Azure resources have been deleted"
    echo "• Local files have been cleaned up"
    echo "• No ongoing charges should occur"
    echo
    echo -e "${BLUE}Note:${NC} It may take a few minutes for all resources to be fully removed from Azure"
    echo "You can verify deletion in the Azure portal"
}

# Handle script interruption
cleanup_on_interrupt() {
    echo
    log_warning "Script interrupted. Some resources may still exist."
    log_info "You can run this script again or check the Azure portal"
    exit 1
}

trap cleanup_on_interrupt SIGINT SIGTERM

# Run main function
main "$@"