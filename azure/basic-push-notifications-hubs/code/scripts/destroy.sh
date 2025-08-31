#!/bin/bash

#===============================================================================
# Azure Basic Push Notifications with Notification Hubs - Cleanup Script
#===============================================================================
# This script removes all infrastructure created by the deployment script
# following the recipe "Basic Push Notifications with Notification Hubs"
#
# Prerequisites:
# - Azure CLI installed and authenticated
# - Contributor permissions on target subscription
# - notification-hub extension for Azure CLI
#===============================================================================

set -euo pipefail

# Color codes for output formatting
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
cleanup_on_error() {
    log_error "Cleanup failed. Check the logs above for details."
    log_warning "Some resources may still exist and need manual cleanup."
    exit 1
}

trap cleanup_on_error ERR

#===============================================================================
# Configuration and Variables
#===============================================================================

# Default configuration (can be overridden by environment variables)
RESOURCE_GROUP_PREFIX="${RESOURCE_GROUP_PREFIX:-rg-notifications}"
FORCE_DELETE="${FORCE_DELETE:-false}"
DRY_RUN="${DRY_RUN:-false}"
AUTO_CONFIRM="${AUTO_CONFIRM:-false}"

# Variables for discovered resources
RESOURCE_GROUP=""
NH_NAMESPACE=""
NH_NAME=""
SUBSCRIPTION_ID=""

#===============================================================================
# Prerequisites Check
#===============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    
    log_info "Using subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
    
    # Check if notification-hub extension is available
    if ! az extension show --name notification-hub &> /dev/null; then
        log_warning "Notification Hub extension not found. Installing..."
        az extension add --name notification-hub --yes
        log_success "Notification Hub extension installed successfully"
    fi
    
    log_success "Prerequisites check completed"
}

#===============================================================================
# Resource Discovery
#===============================================================================

discover_resources() {
    log_info "Discovering resources to cleanup..."
    
    # If specific resource group is provided, use it
    if [[ -n "${RESOURCE_GROUP_NAME:-}" ]]; then
        RESOURCE_GROUP="${RESOURCE_GROUP_NAME}"
        log_info "Using specified resource group: ${RESOURCE_GROUP}"
    else
        # Find resource groups with the recipe prefix and tags
        local resource_groups
        resource_groups=$(az group list \
            --query "[?starts_with(name, '${RESOURCE_GROUP_PREFIX}') && tags.purpose=='recipe'].name" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -z "${resource_groups}" ]]; then
            log_warning "No resource groups found with prefix '${RESOURCE_GROUP_PREFIX}' and purpose tag 'recipe'"
            
            # Try to find any resource groups with the prefix
            resource_groups=$(az group list \
                --query "[?starts_with(name, '${RESOURCE_GROUP_PREFIX}')].name" \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -z "${resource_groups}" ]]; then
                log_warning "No resource groups found with prefix '${RESOURCE_GROUP_PREFIX}'"
                return 0
            else
                log_warning "Found resource groups with prefix but without recipe tag:"
                echo "${resource_groups}"
                echo ""
            fi
        fi
        
        # Handle multiple resource groups
        local rg_array
        IFS=$'\n' read -rd '' -a rg_array <<< "${resource_groups}" || true
        
        if [[ ${#rg_array[@]} -eq 0 ]]; then
            log_info "No matching resource groups found"
            return 0
        elif [[ ${#rg_array[@]} -eq 1 ]]; then
            RESOURCE_GROUP="${rg_array[0]}"
            log_info "Found resource group: ${RESOURCE_GROUP}"
        else
            log_info "Multiple resource groups found:"
            for i in "${!rg_array[@]}"; do
                echo "  $((i+1)). ${rg_array[i]}"
            done
            echo ""
            
            if [[ "${AUTO_CONFIRM}" == "true" ]]; then
                log_warning "AUTO_CONFIRM is enabled. Will delete ALL found resource groups."
            else
                read -p "Enter the number of the resource group to delete (1-${#rg_array[@]}) or 'all' for all: " choice
                
                if [[ "${choice}" == "all" ]]; then
                    log_info "Will delete all found resource groups"
                elif [[ "${choice}" =~ ^[0-9]+$ ]] && [[ "${choice}" -ge 1 ]] && [[ "${choice}" -le ${#rg_array[@]} ]]; then
                    RESOURCE_GROUP="${rg_array[$((choice-1))]}"
                    log_info "Selected resource group: ${RESOURCE_GROUP}"
                else
                    log_error "Invalid selection: ${choice}"
                    exit 1
                fi
            fi
        fi
    fi
    
    # If we have a specific resource group, discover its notification hubs
    if [[ -n "${RESOURCE_GROUP}" ]]; then
        discover_notification_hubs_in_group "${RESOURCE_GROUP}"
    fi
}

discover_notification_hubs_in_group() {
    local rg_name="$1"
    
    log_info "Discovering Notification Hubs in resource group: ${rg_name}..."
    
    # Find notification hub namespaces
    local namespaces
    namespaces=$(az notification-hub namespace list \
        --resource-group "${rg_name}" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${namespaces}" ]]; then
        local ns_array
        IFS=$'\n' read -rd '' -a ns_array <<< "${namespaces}" || true
        
        for namespace in "${ns_array[@]}"; do
            log_info "Found notification hub namespace: ${namespace}"
            
            # Find notification hubs in this namespace
            local hubs
            hubs=$(az notification-hub list \
                --resource-group "${rg_name}" \
                --namespace-name "${namespace}" \
                --query "[].name" \
                --output tsv 2>/dev/null || echo "")
            
            if [[ -n "${hubs}" ]]; then
                local hub_array
                IFS=$'\n' read -rd '' -a hub_array <<< "${hubs}" || true
                
                for hub in "${hub_array[@]}"; do
                    log_info "Found notification hub: ${hub} in namespace: ${namespace}"
                done
            fi
        done
    else
        log_info "No notification hub namespaces found in resource group: ${rg_name}"
    fi
}

#===============================================================================
# Cleanup Functions
#===============================================================================

cleanup_notification_hubs() {
    local rg_name="$1"
    
    log_info "Cleaning up notification hubs in resource group: ${rg_name}..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would cleanup notification hubs in: ${rg_name}"
        return 0
    fi
    
    # Get all notification hub namespaces
    local namespaces
    namespaces=$(az notification-hub namespace list \
        --resource-group "${rg_name}" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -z "${namespaces}" ]]; then
        log_info "No notification hub namespaces found in resource group: ${rg_name}"
        return 0
    fi
    
    local ns_array
    IFS=$'\n' read -rd '' -a ns_array <<< "${namespaces}" || true
    
    for namespace in "${ns_array[@]}"; do
        log_info "Processing namespace: ${namespace}"
        
        # Get all notification hubs in this namespace
        local hubs
        hubs=$(az notification-hub list \
            --resource-group "${rg_name}" \
            --namespace-name "${namespace}" \
            --query "[].name" \
            --output tsv 2>/dev/null || echo "")
        
        # Delete notification hubs first
        if [[ -n "${hubs}" ]]; then
            local hub_array
            IFS=$'\n' read -rd '' -a hub_array <<< "${hubs}" || true
            
            for hub in "${hub_array[@]}"; do
                log_info "Deleting notification hub: ${hub}"
                
                if az notification-hub delete \
                    --resource-group "${rg_name}" \
                    --namespace-name "${namespace}" \
                    --name "${hub}" \
                    --yes \
                    --output none 2>/dev/null; then
                    log_success "Deleted notification hub: ${hub}"
                else
                    log_warning "Failed to delete notification hub: ${hub} (may not exist)"
                fi
            done
        fi
        
        # Delete the namespace
        log_info "Deleting notification hub namespace: ${namespace}"
        
        if az notification-hub namespace delete \
            --resource-group "${rg_name}" \
            --name "${namespace}" \
            --yes \
            --output none 2>/dev/null; then
            log_success "Deleted notification hub namespace: ${namespace}"
        else
            log_warning "Failed to delete namespace: ${namespace} (may not exist)"
        fi
    done
}

cleanup_resource_group() {
    local rg_name="$1"
    
    log_info "Deleting resource group: ${rg_name}..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete resource group: ${rg_name}"
        return 0
    fi
    
    # Verify the resource group exists
    if ! az group show --name "${rg_name}" --output none 2>/dev/null; then
        log_warning "Resource group does not exist: ${rg_name}"
        return 0
    fi
    
    # Delete the resource group and all its resources
    log_info "Initiating resource group deletion (this may take several minutes)..."
    
    if az group delete \
        --name "${rg_name}" \
        --yes \
        --no-wait \
        --output none 2>/dev/null; then
        log_success "Resource group deletion initiated: ${rg_name}"
        log_info "Note: Deletion will continue in the background and may take several minutes to complete"
    else
        log_error "Failed to initiate resource group deletion: ${rg_name}"
        return 1
    fi
}

wait_for_deletion() {
    local rg_name="$1"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    log_info "Waiting for resource group deletion to complete: ${rg_name}"
    
    local timeout=1800  # 30 minutes
    local elapsed=0
    local check_interval=30
    
    while [[ $elapsed -lt $timeout ]]; do
        if ! az group show --name "${rg_name}" --output none 2>/dev/null; then
            log_success "Resource group successfully deleted: ${rg_name}"
            return 0
        fi
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
        log_info "Still waiting for deletion... (${elapsed}s/${timeout}s)"
    done
    
    log_warning "Timeout waiting for resource group deletion. Deletion may still be in progress."
    log_info "You can check the status in the Azure portal or with: az group show --name ${rg_name}"
}

verify_cleanup() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would verify cleanup completion"
        return 0
    fi
    
    log_info "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if [[ -n "${RESOURCE_GROUP}" ]]; then
        if az group show --name "${RESOURCE_GROUP}" --output none 2>/dev/null; then
            log_warning "Resource group still exists: ${RESOURCE_GROUP}"
            log_info "Deletion may still be in progress. Check Azure portal for status."
        else
            log_success "Resource group successfully removed: ${RESOURCE_GROUP}"
        fi
    fi
    
    # Check for any remaining resource groups with our prefix
    local remaining_groups
    remaining_groups=$(az group list \
        --query "[?starts_with(name, '${RESOURCE_GROUP_PREFIX}') && tags.purpose=='recipe'].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${remaining_groups}" ]]; then
        log_warning "Some resource groups with recipe tag still exist:"
        echo "${remaining_groups}"
        log_info "These may be from other deployments or still being deleted"
    else
        log_success "No recipe-tagged resource groups found with prefix: ${RESOURCE_GROUP_PREFIX}"
    fi
}

#===============================================================================
# Interactive Confirmation
#===============================================================================

confirm_deletion() {
    if [[ "${AUTO_CONFIRM}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    echo "This will permanently delete the following resources:"
    
    if [[ -n "${RESOURCE_GROUP}" ]]; then
        echo "  - Resource Group: ${RESOURCE_GROUP}"
        echo "  - All resources within this resource group"
    else
        echo "  - All resource groups with prefix: ${RESOURCE_GROUP_PREFIX}"
        echo "  - All resources within those resource groups"
    fi
    
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [[ "${confirmation}" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource deletion..."
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
    log_info "Starting Azure Notification Hubs cleanup..."
    
    # Check if help is requested
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        echo "Azure Notification Hubs Cleanup Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Environment Variables:"
        echo "  RESOURCE_GROUP_PREFIX  Prefix for resource group name (default: rg-notifications)"
        echo "  RESOURCE_GROUP_NAME    Specific resource group name to delete"
        echo "  FORCE_DELETE           Skip confirmation prompts (default: false)"
        echo "  DRY_RUN                Set to 'true' for dry run (default: false)"
        echo "  AUTO_CONFIRM           Auto-confirm deletions (default: false)"
        echo ""
        echo "Examples:"
        echo "  $0                                           # Interactive cleanup"
        echo "  RESOURCE_GROUP_NAME=my-rg $0                # Delete specific resource group"
        echo "  DRY_RUN=true $0                             # Dry run mode"
        echo "  AUTO_CONFIRM=true $0                        # Auto-confirm all deletions"
        echo "  FORCE_DELETE=true $0                        # Force delete without prompts"
        echo ""
        echo "Safety Features:"
        echo "  - Interactive confirmation required by default"
        echo "  - Dry run mode available for testing"
        echo "  - Resource discovery before deletion"
        echo "  - Graceful handling of missing resources"
        echo ""
        exit 0
    fi
    
    # Execute cleanup steps
    check_prerequisites
    discover_resources
    
    # If no resources found, exit gracefully
    if [[ -z "${RESOURCE_GROUP}" ]] && [[ "${AUTO_CONFIRM}" != "true" ]]; then
        log_info "No resources found to cleanup"
        exit 0
    fi
    
    # Confirm deletion
    confirm_deletion
    
    # Perform cleanup
    if [[ -n "${RESOURCE_GROUP}" ]]; then
        # Clean up specific resource group
        cleanup_notification_hubs "${RESOURCE_GROUP}"
        cleanup_resource_group "${RESOURCE_GROUP}"
        
        if [[ "${DRY_RUN}" != "true" ]]; then
            wait_for_deletion "${RESOURCE_GROUP}"
        fi
    else
        # Clean up all matching resource groups
        local resource_groups
        resource_groups=$(az group list \
            --query "[?starts_with(name, '${RESOURCE_GROUP_PREFIX}') && tags.purpose=='recipe'].name" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "${resource_groups}" ]]; then
            local rg_array
            IFS=$'\n' read -rd '' -a rg_array <<< "${resource_groups}" || true
            
            for rg in "${rg_array[@]}"; do
                cleanup_notification_hubs "${rg}"
                cleanup_resource_group "${rg}"
            done
            
            if [[ "${DRY_RUN}" != "true" ]]; then
                for rg in "${rg_array[@]}"; do
                    wait_for_deletion "${rg}"
                done
            fi
        fi
    fi
    
    verify_cleanup
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Dry run completed. No resources were actually deleted."
    else
        log_success "Cleanup completed successfully!"
    fi
}

# Execute main function with all arguments
main "$@"