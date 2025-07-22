#!/bin/bash

# Azure HPC Cache Monitoring Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    exit 1
}

# Success message
success() {
    log "${GREEN}SUCCESS: ${1}${NC}"
}

# Warning message
warning() {
    log "${YELLOW}WARNING: ${1}${NC}"
}

# Info message
info() {
    log "${BLUE}INFO: ${1}${NC}"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    success "Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    info "Loading deployment information..."
    
    if [[ ! -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        error_exit "Deployment info file not found: ${DEPLOYMENT_INFO_FILE}"
    fi
    
    # Extract resource information from JSON file
    RESOURCE_GROUP=$(jq -r '.resourceGroup' "${DEPLOYMENT_INFO_FILE}")
    LOCATION=$(jq -r '.location' "${DEPLOYMENT_INFO_FILE}")
    HPC_CACHE_NAME=$(jq -r '.resources.hpcCache' "${DEPLOYMENT_INFO_FILE}")
    BATCH_ACCOUNT_NAME=$(jq -r '.resources.batchAccount' "${DEPLOYMENT_INFO_FILE}")
    STORAGE_ACCOUNT_NAME=$(jq -r '.resources.storageAccount' "${DEPLOYMENT_INFO_FILE}")
    WORKSPACE_NAME=$(jq -r '.resources.workspace' "${DEPLOYMENT_INFO_FILE}")
    WORKBOOK_NAME=$(jq -r '.resources.workbook' "${DEPLOYMENT_INFO_FILE}")
    VNET_NAME=$(jq -r '.resources.vnet' "${DEPLOYMENT_INFO_FILE}")
    
    # Validate extracted values
    if [[ "${RESOURCE_GROUP}" == "null" ]] || [[ -z "${RESOURCE_GROUP}" ]]; then
        error_exit "Invalid resource group in deployment info"
    fi
    
    info "Loaded deployment info for resource group: ${RESOURCE_GROUP}"
}

# Prompt for confirmation
confirm_deletion() {
    info "This will permanently delete the following resources:"
    echo "  Resource Group: ${RESOURCE_GROUP}"
    echo "  Location: ${LOCATION}"
    echo "  HPC Cache: ${HPC_CACHE_NAME}"
    echo "  Batch Account: ${BATCH_ACCOUNT_NAME}"
    echo "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "  Log Analytics Workspace: ${WORKSPACE_NAME}"
    echo "  Monitor Workbook: ${WORKBOOK_NAME}"
    echo "  Virtual Network: ${VNET_NAME}"
    echo ""
    
    warning "THIS ACTION CANNOT BE UNDONE!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [[ "${confirmation}" != "DELETE" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    info "Confirmation received. Proceeding with cleanup..."
}

# Check if resource group exists
check_resource_group() {
    info "Checking if resource group exists: ${RESOURCE_GROUP}"
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} does not exist. Nothing to clean up."
        exit 0
    fi
    
    success "Resource group found: ${RESOURCE_GROUP}"
}

# Delete Batch pool first (to avoid dependency issues)
delete_batch_pool() {
    info "Deleting Batch pool: hpc-pool"
    
    # Login to Batch account first
    if az batch account login --resource-group "${RESOURCE_GROUP}" --name "${BATCH_ACCOUNT_NAME}" &> /dev/null; then
        # Delete the pool
        if az batch pool delete --pool-id hpc-pool --yes &> /dev/null; then
            success "Batch pool deleted: hpc-pool"
        else
            warning "Failed to delete Batch pool or pool doesn't exist"
        fi
    else
        warning "Failed to login to Batch account or account doesn't exist"
    fi
}

# Delete HPC Cache (this may take time)
delete_hpc_cache() {
    info "Deleting HPC Cache: ${HPC_CACHE_NAME}"
    
    # Check if HPC Cache exists
    if az hpc-cache show --resource-group "${RESOURCE_GROUP}" --name "${HPC_CACHE_NAME}" &> /dev/null; then
        warning "HPC Cache deletion may take 10-15 minutes. Please be patient..."
        
        if az hpc-cache delete --resource-group "${RESOURCE_GROUP}" --name "${HPC_CACHE_NAME}" --yes &> /dev/null; then
            success "HPC Cache deleted: ${HPC_CACHE_NAME}"
        else
            warning "Failed to delete HPC Cache: ${HPC_CACHE_NAME}"
        fi
    else
        warning "HPC Cache not found: ${HPC_CACHE_NAME}"
    fi
}

# Delete individual resources (in case resource group deletion fails)
delete_individual_resources() {
    info "Deleting individual resources..."
    
    # Delete workbook
    if az monitor workbook delete --resource-group "${RESOURCE_GROUP}" --name "${WORKBOOK_NAME}" --yes &> /dev/null; then
        success "Workbook deleted: ${WORKBOOK_NAME}"
    else
        warning "Failed to delete workbook or workbook doesn't exist"
    fi
    
    # Delete Batch account
    if az batch account delete --resource-group "${RESOURCE_GROUP}" --name "${BATCH_ACCOUNT_NAME}" --yes &> /dev/null; then
        success "Batch account deleted: ${BATCH_ACCOUNT_NAME}"
    else
        warning "Failed to delete Batch account or account doesn't exist"
    fi
    
    # Delete storage account
    if az storage account delete --resource-group "${RESOURCE_GROUP}" --name "${STORAGE_ACCOUNT_NAME}" --yes &> /dev/null; then
        success "Storage account deleted: ${STORAGE_ACCOUNT_NAME}"
    else
        warning "Failed to delete storage account or account doesn't exist"
    fi
    
    # Delete Log Analytics workspace
    if az monitor log-analytics workspace delete --resource-group "${RESOURCE_GROUP}" --workspace-name "${WORKSPACE_NAME}" --yes &> /dev/null; then
        success "Log Analytics workspace deleted: ${WORKSPACE_NAME}"
    else
        warning "Failed to delete Log Analytics workspace or workspace doesn't exist"
    fi
    
    # Delete virtual network
    if az network vnet delete --resource-group "${RESOURCE_GROUP}" --name "${VNET_NAME}" &> /dev/null; then
        success "Virtual network deleted: ${VNET_NAME}"
    else
        warning "Failed to delete virtual network or network doesn't exist"
    fi
}

# Delete alerts and action groups
delete_alerts() {
    info "Deleting alerts and action groups..."
    
    # Delete metric alerts
    local alerts=("low-cache-hit-rate" "high-compute-utilization")
    for alert in "${alerts[@]}"; do
        if az monitor metrics alert delete --resource-group "${RESOURCE_GROUP}" --name "${alert}" &> /dev/null; then
            success "Alert deleted: ${alert}"
        else
            warning "Failed to delete alert or alert doesn't exist: ${alert}"
        fi
    done
    
    # Delete action group
    if az monitor action-group delete --resource-group "${RESOURCE_GROUP}" --name "hpc-alerts" &> /dev/null; then
        success "Action group deleted: hpc-alerts"
    else
        warning "Failed to delete action group or action group doesn't exist"
    fi
}

# Delete resource group
delete_resource_group() {
    info "Deleting resource group: ${RESOURCE_GROUP}"
    
    warning "This will delete ALL resources in the resource group. Final confirmation required."
    read -p "Type 'CONFIRM' to proceed with resource group deletion: " final_confirmation
    
    if [[ "${final_confirmation}" != "CONFIRM" ]]; then
        info "Resource group deletion cancelled by user"
        info "Individual resources may have been deleted"
        return 0
    fi
    
    info "Deleting resource group (this may take several minutes)..."
    
    if az group delete --name "${RESOURCE_GROUP}" --yes --no-wait; then
        success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        info "Complete deletion may take several minutes"
        info "Monitor progress in Azure Portal or use: az group show --name ${RESOURCE_GROUP}"
    else
        error_exit "Failed to delete resource group: ${RESOURCE_GROUP}"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    info "Cleaning up temporary files..."
    
    # Remove temporary files created during deployment
    local temp_files=(
        "${SCRIPT_DIR}/hpc-workbook.json"
        "${SCRIPT_DIR}/deployment-info.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            success "Removed temporary file: $(basename "${file}")"
        fi
    done
}

# Verify cleanup
verify_cleanup() {
    info "Verifying cleanup..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Resource group still exists: ${RESOURCE_GROUP}"
        info "Deletion may still be in progress. Check Azure Portal for status."
    else
        success "Resource group successfully deleted: ${RESOURCE_GROUP}"
    fi
}

# Display cleanup summary
display_summary() {
    info "Cleanup Summary"
    echo "==================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Status: Cleanup initiated"
    echo "==================="
    
    info "Cleanup process completed"
    warning "Note: Some resources may take additional time to fully delete"
    info "Monitor progress in Azure Portal if needed"
}

# Main cleanup function
main() {
    log "Starting Azure HPC Cache Monitoring cleanup..."
    log "Log file: ${LOG_FILE}"
    
    # Clear log file
    > "${LOG_FILE}"
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install jq to parse deployment info."
    fi
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_info
    confirm_deletion
    check_resource_group
    delete_batch_pool
    delete_hpc_cache
    delete_alerts
    delete_individual_resources
    delete_resource_group
    cleanup_temp_files
    verify_cleanup
    display_summary
    
    success "Cleanup completed successfully!"
    info "All resources have been deleted or deletion has been initiated"
}

# Handle script interruption
trap 'log "${RED}Cleanup interrupted by user${NC}"; exit 1' INT TERM

# Run the main function
main "$@"