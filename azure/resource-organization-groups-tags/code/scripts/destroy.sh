#!/bin/bash

# Resource Organization with Resource Groups and Tags - Cleanup Script
# Recipe: resource-organization-groups-tags
# Version: 1.1
# Provider: Azure

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for graceful exit
cleanup() {
    if [[ $? -ne 0 ]]; then
        log_error "Cleanup failed. Some resources may still exist."
        log_info "You may need to manually delete remaining resources through the Azure Portal."
    fi
}

trap cleanup EXIT

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    log_success "Prerequisites check completed"
}

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [[ -f .env_vars ]]; then
        # Source the environment variables file
        source .env_vars
        log_success "Environment variables loaded from .env_vars file"
        log_info "   Development RG: ${DEV_RG:-not set}"
        log_info "   Production RG: ${PROD_RG:-not set}"
        log_info "   Shared RG: ${SHARED_RG:-not set}"
    else
        log_warning ".env_vars file not found. Attempting manual discovery..."
        
        # Attempt to discover resource groups by pattern
        local subscription_id
        subscription_id=$(az account show --query id --output tsv) || error_exit "Failed to get subscription ID"
        
        # Look for resource groups that match our naming pattern
        local resource_groups
        resource_groups=$(az group list --query "[?contains(name, 'rg-demo-')].name" --output tsv)
        
        if [[ -z "$resource_groups" ]]; then
            log_warning "No resource groups found matching pattern 'rg-demo-*'"
            log_info "If you know the resource group names, you can set them manually:"
            log_info "export DEV_RG='your-dev-resource-group'"
            log_info "export PROD_RG='your-prod-resource-group'"
            log_info "export SHARED_RG='your-shared-resource-group'"
            log_info "Then run this script again."
            exit 0
        fi
        
        # Set discovered resource groups
        while IFS= read -r rg; do
            if [[ $rg == *"-dev-"* ]]; then
                export DEV_RG="$rg"
            elif [[ $rg == *"-prod-"* ]]; then
                export PROD_RG="$rg"
            elif [[ $rg == *"-shared-"* ]]; then
                export SHARED_RG="$rg"
            fi
        done <<< "$resource_groups"
        
        log_info "Discovered resource groups:"
        log_info "   Development RG: ${DEV_RG:-not found}"
        log_info "   Production RG: ${PROD_RG:-not found}"
        log_info "   Shared RG: ${SHARED_RG:-not found}"
    fi
}

# Confirmation prompt
confirm_deletion() {
    echo
    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    log_warning "This script will DELETE the following resource groups and ALL contained resources:"
    
    if [[ -n "${DEV_RG:-}" ]]; then
        log_warning "   • ${DEV_RG} (Development environment)"
    fi
    if [[ -n "${PROD_RG:-}" ]]; then
        log_warning "   • ${PROD_RG} (Production environment)"
    fi
    if [[ -n "${SHARED_RG:-}" ]]; then
        log_warning "   • ${SHARED_RG} (Shared infrastructure)"
    fi
    
    log_warning "This action CANNOT be undone!"
    echo
    
    # Check if running in non-interactive mode
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log_warning "FORCE_DELETE is set, proceeding without confirmation..."
        return 0
    fi
    
    read -p "Do you want to proceed with deletion? (type 'yes' to continue): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource deletion..."
}

# Wait for resource group deletion
wait_for_deletion() {
    local resource_group="$1"
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for ${resource_group} deletion to complete..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if ! az group show --name "$resource_group" &> /dev/null; then
            log_success "Resource group ${resource_group} successfully deleted"
            return 0
        fi
        
        log_info "Attempt ${attempt}/${max_attempts}: Still deleting ${resource_group}..."
        sleep 10
        ((attempt++))
    done
    
    log_warning "Timeout waiting for ${resource_group} deletion. It may still be in progress."
    return 1
}

# Delete production resource group
delete_prod_resource_group() {
    if [[ -z "${PROD_RG:-}" ]]; then
        log_warning "Production resource group not specified, skipping"
        return 0
    fi
    
    log_info "Checking if production resource group exists..."
    
    if ! az group show --name "${PROD_RG}" &> /dev/null; then
        log_warning "Production resource group ${PROD_RG} does not exist, skipping"
        return 0
    fi
    
    log_info "Deleting production resource group: ${PROD_RG}"
    
    # List resources before deletion for logging
    log_info "Resources in ${PROD_RG}:"
    az resource list --resource-group "${PROD_RG}" --query "[].{Name:name, Type:type}" --output table || log_warning "Could not list resources"
    
    # Delete the resource group
    az group delete \
        --name "${PROD_RG}" \
        --yes \
        --no-wait \
        || error_exit "Failed to initiate deletion of production resource group"
    
    log_success "Production resource group deletion initiated: ${PROD_RG}"
}

# Delete development resource group
delete_dev_resource_group() {
    if [[ -z "${DEV_RG:-}" ]]; then
        log_warning "Development resource group not specified, skipping"
        return 0
    fi
    
    log_info "Checking if development resource group exists..."
    
    if ! az group show --name "${DEV_RG}" &> /dev/null; then
        log_warning "Development resource group ${DEV_RG} does not exist, skipping"
        return 0
    fi
    
    log_info "Deleting development resource group: ${DEV_RG}"
    
    # List resources before deletion for logging
    log_info "Resources in ${DEV_RG}:"
    az resource list --resource-group "${DEV_RG}" --query "[].{Name:name, Type:type}" --output table || log_warning "Could not list resources"
    
    # Delete the resource group
    az group delete \
        --name "${DEV_RG}" \
        --yes \
        --no-wait \
        || error_exit "Failed to initiate deletion of development resource group"
    
    log_success "Development resource group deletion initiated: ${DEV_RG}"
}

# Delete shared resource group
delete_shared_resource_group() {
    if [[ -z "${SHARED_RG:-}" ]]; then
        log_warning "Shared resource group not specified, skipping"
        return 0
    fi
    
    log_info "Checking if shared resource group exists..."
    
    if ! az group show --name "${SHARED_RG}" &> /dev/null; then
        log_warning "Shared resource group ${SHARED_RG} does not exist, skipping"
        return 0
    fi
    
    log_info "Deleting shared resource group: ${SHARED_RG}"
    
    # List resources before deletion for logging
    log_info "Resources in ${SHARED_RG}:"
    az resource list --resource-group "${SHARED_RG}" --query "[].{Name:name, Type:type}" --output table || log_warning "Could not list resources"
    
    # Delete the resource group
    az group delete \
        --name "${SHARED_RG}" \
        --yes \
        --no-wait \
        || error_exit "Failed to initiate deletion of shared resource group"
    
    log_success "Shared resource group deletion initiated: ${SHARED_RG}"
}

# Verify complete cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local all_deleted=true
    local resource_groups=("${PROD_RG:-}" "${DEV_RG:-}" "${SHARED_RG:-}")
    
    for rg in "${resource_groups[@]}"; do
        if [[ -n "$rg" ]] && az group show --name "$rg" &> /dev/null; then
            log_warning "Resource group $rg still exists (deletion may be in progress)"
            all_deleted=false
        fi
    done
    
    if [[ "$all_deleted" == "true" ]]; then
        log_success "All resource groups have been successfully deleted"
    else
        log_warning "Some resource groups may still be deleting. Check Azure portal for status."
        log_info "Resource group deletion can take several minutes to complete."
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local environment files..."
    
    # Remove environment variables file
    if [[ -f .env_vars ]]; then
        rm -f .env_vars
        log_success "Removed .env_vars file"
    fi
    
    # Clear environment variables from current session
    unset DEV_RG PROD_RG SHARED_RG LOCATION SUBSCRIPTION_ID RANDOM_SUFFIX
    unset STORAGE_DEV STORAGE_PROD APP_PLAN_DEV APP_PLAN_PROD
    
    log_success "Environment variables cleared from current session"
}

# Display final status
show_final_status() {
    echo
    log_info "=== Cleanup Summary ==="
    log_info "Recipe: resource-organization-groups-tags v1.1"
    log_info "All specified resource groups have been marked for deletion."
    log_info "Deletion operations are running asynchronously in the background."
    echo
    log_info "To verify complete deletion, you can:"
    log_info "1. Check the Azure Portal"
    log_info "2. Run: az group list --query \"[?contains(name, 'rg-demo-')]\""
    echo
    log_success "Cleanup script completed successfully!"
}

# Main cleanup function
main() {
    log_info "Starting Azure Resource Organization cleanup..."
    log_info "Recipe: resource-organization-groups-tags v1.1"
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_deletion
    delete_prod_resource_group
    delete_dev_resource_group
    delete_shared_resource_group
    
    # Wait a moment for deletions to start
    sleep 5
    
    verify_cleanup
    cleanup_local_files
    show_final_status
}

# Execute main function
main "$@"