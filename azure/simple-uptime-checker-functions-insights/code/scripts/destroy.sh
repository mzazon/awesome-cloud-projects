#!/bin/bash

# Simple Website Uptime Checker with Functions and Application Insights - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to find resources by tags or patterns
find_resources() {
    log_info "Searching for uptime checker resources..."
    
    # Find resource groups with uptime checker pattern
    RESOURCE_GROUPS=$(az group list --query "[?contains(name, 'uptime-checker')].name" --output tsv)
    
    if [ -z "${RESOURCE_GROUPS}" ]; then
        log_warning "No resource groups found matching 'uptime-checker' pattern"
        
        # Allow manual specification of resource group
        read -p "Enter the resource group name to delete (or press Enter to exit): " MANUAL_RG
        if [ -z "${MANUAL_RG}" ]; then
            log_info "No resource group specified. Exiting."
            exit 0
        else
            RESOURCE_GROUPS="${MANUAL_RG}"
        fi
    fi
    
    log_info "Found resource groups: ${RESOURCE_GROUPS}"
}

# Function to prompt for confirmation
confirm_deletion() {
    local resource_group=$1
    
    echo ""
    log_warning "This will permanently delete the following resource group and ALL resources within it:"
    echo "  Resource Group: ${resource_group}"
    
    # List resources in the group
    log_info "Resources to be deleted:"
    az resource list --resource-group "${resource_group}" --query "[].{Name:name,Type:type}" --output table 2>/dev/null || log_warning "Could not list resources in ${resource_group}"
    
    echo ""
    log_warning "This action cannot be undone!"
    read -p "Are you sure you want to delete resource group '${resource_group}' and all its resources? (yes/no): " confirmation
    
    case "${confirmation}" in
        yes|YES|Yes)
            return 0
            ;;
        *)
            log_info "Deletion cancelled by user"
            return 1
            ;;
    esac
}

# Function to delete individual resources (if needed)
delete_individual_resources() {
    local resource_group=$1
    
    log_info "Attempting graceful cleanup of individual resources in ${resource_group}..."
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Delete alert rules first (they depend on Application Insights)
    log_info "Deleting alert rules..."
    ALERT_RULES=$(az monitor scheduled-query list --resource-group "${resource_group}" --query "[].name" --output tsv 2>/dev/null || true)
    
    for rule in ${ALERT_RULES}; do
        if [ -n "${rule}" ]; then
            log_info "Deleting alert rule: ${rule}"
            az monitor scheduled-query delete \
                --name "${rule}" \
                --resource-group "${resource_group}" \
                --yes 2>/dev/null || log_warning "Failed to delete alert rule: ${rule}"
        fi
    done
    
    # Delete action groups
    log_info "Deleting action groups..."
    ACTION_GROUPS=$(az monitor action-group list --resource-group "${resource_group}" --query "[].name" --output tsv 2>/dev/null || true)
    
    for group in ${ACTION_GROUPS}; do
        if [ -n "${group}" ]; then
            log_info "Deleting action group: ${group}"
            az monitor action-group delete \
                --name "${group}" \
                --resource-group "${resource_group}" \
                --yes 2>/dev/null || log_warning "Failed to delete action group: ${group}"
        fi
    done
    
    # Delete Function Apps
    log_info "Deleting Function Apps..."
    FUNCTION_APPS=$(az functionapp list --resource-group "${resource_group}" --query "[].name" --output tsv 2>/dev/null || true)
    
    for app in ${FUNCTION_APPS}; do
        if [ -n "${app}" ]; then
            log_info "Deleting Function App: ${app}"
            az functionapp delete \
                --name "${app}" \
                --resource-group "${resource_group}" 2>/dev/null || log_warning "Failed to delete Function App: ${app}"
        fi
    done
    
    # Delete Application Insights
    log_info "Deleting Application Insights..."
    AI_COMPONENTS=$(az monitor app-insights component list --resource-group "${resource_group}" --query "[].name" --output tsv 2>/dev/null || true)
    
    for component in ${AI_COMPONENTS}; do
        if [ -n "${component}" ]; then
            log_info "Deleting Application Insights: ${component}"
            az monitor app-insights component delete \
                --app "${component}" \
                --resource-group "${resource_group}" 2>/dev/null || log_warning "Failed to delete Application Insights: ${component}"
        fi
    done
    
    # Delete Storage Accounts
    log_info "Deleting Storage Accounts..."
    STORAGE_ACCOUNTS=$(az storage account list --resource-group "${resource_group}" --query "[].name" --output tsv 2>/dev/null || true)
    
    for account in ${STORAGE_ACCOUNTS}; do
        if [ -n "${account}" ]; then
            log_info "Deleting Storage Account: ${account}"
            az storage account delete \
                --name "${account}" \
                --resource-group "${resource_group}" \
                --yes 2>/dev/null || log_warning "Failed to delete Storage Account: ${account}"
        fi
    done
    
    log_success "Individual resource cleanup completed"
}

# Function to delete resource group
delete_resource_group() {
    local resource_group=$1
    
    log_info "Deleting resource group: ${resource_group}"
    
    # Check if resource group exists
    if ! az group show --name "${resource_group}" &> /dev/null; then
        log_warning "Resource group '${resource_group}' does not exist or was already deleted"
        return 0
    fi
    
    # Try individual resource cleanup first
    delete_individual_resources "${resource_group}"
    
    # Wait a moment for individual deletions to process
    log_info "Waiting for individual resource deletions to complete..."
    sleep 30
    
    # Delete the resource group
    log_info "Deleting resource group: ${resource_group}"
    az group delete \
        --name "${resource_group}" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: ${resource_group}"
    log_info "Note: Complete deletion may take several minutes"
    
    # Optionally wait for deletion to complete
    read -p "Wait for deletion to complete? This may take several minutes (y/n): " wait_confirmation
    case "${wait_confirmation}" in
        y|Y|yes|YES|Yes)
            log_info "Waiting for resource group deletion to complete..."
            while az group show --name "${resource_group}" &> /dev/null; do
                echo -n "."
                sleep 10
            done
            echo ""
            log_success "Resource group '${resource_group}' has been completely deleted"
            ;;
        *)
            log_info "Deletion is running in the background. Check Azure portal for status."
            ;;
    esac
}

# Function to verify deletion
verify_deletion() {
    local resource_group=$1
    
    log_info "Verifying deletion of resource group: ${resource_group}"
    
    if az group show --name "${resource_group}" &> /dev/null; then
        log_warning "Resource group '${resource_group}' still exists. Deletion may still be in progress."
        log_info "Check the Azure portal for deletion status: https://portal.azure.com/#blade/HubsExtension/BrowseResourceGroups"
    else
        log_success "Resource group '${resource_group}' has been successfully deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local temporary files..."
    
    # Remove any temporary function code directories
    if [ -d "uptime-function" ]; then
        rm -rf uptime-function
        log_success "Removed local uptime-function directory"
    fi
    
    # Remove any zip files
    if [ -f "uptime-function.zip" ]; then
        rm -f uptime-function.zip
        log_success "Removed uptime-function.zip"
    fi
    
    log_success "Local cleanup completed"
}

# Function to display cleanup summary
display_summary() {
    log_success "Cleanup process completed!"
    echo ""
    echo "=== Cleanup Summary ==="
    echo "- All uptime checker resources have been scheduled for deletion"
    echo "- Resource groups and contained resources are being deleted"
    echo "- Local temporary files have been cleaned up"
    echo ""
    echo "=== Notes ==="
    echo "- Azure resource deletion can take several minutes to complete"
    echo "- You can verify deletion in the Azure portal"
    echo "- No additional charges will be incurred after resources are deleted"
    echo ""
    echo "If you need to check deletion status, use:"
    echo "  az group list --query \"[?contains(name, 'uptime-checker')]\""
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Simple Website Uptime Checker resources..."
    
    check_prerequisites
    find_resources
    
    # Process each found resource group
    for resource_group in ${RESOURCE_GROUPS}; do
        if [ -n "${resource_group}" ]; then
            if confirm_deletion "${resource_group}"; then
                delete_resource_group "${resource_group}"
                verify_deletion "${resource_group}"
            else
                log_info "Skipping deletion of resource group: ${resource_group}"
            fi
        fi
    done
    
    cleanup_local_files
    display_summary
    
    log_success "Cleanup script completed!"
}

# Handle script interruption
trap 'log_error "Script interrupted. Some resources may not have been deleted."; exit 1' INT TERM

# Run main function
main "$@"