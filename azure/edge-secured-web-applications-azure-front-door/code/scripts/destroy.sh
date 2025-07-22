#!/bin/bash

# =============================================================================
# Azure Secure Web Application Cleanup Script
# =============================================================================
# This script removes all resources created by the deploy.sh script for the
# Azure Static Web Apps with Front Door and WAF security solution.
#
# Prerequisites:
# - Azure CLI v2.53.0 or later
# - Appropriate Azure permissions (Owner/Contributor)
# - Resources previously deployed using deploy.sh
#
# Usage:
#   ./destroy.sh [--resource-group NAME] [--force] [--dry-run]
#
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=false
FORCE_DELETE=false
RESOURCE_GROUP=""
CONFIRMATION_REQUIRED=true

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Logging and Output Functions
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

# =============================================================================
# Error Handling
# =============================================================================

cleanup_on_error() {
    log_error "Cleanup failed. Check ${LOG_FILE} for details."
    log_info "Some resources may still exist. Please check Azure portal."
    exit 1
}

trap cleanup_on_error ERR

# =============================================================================
# Helper Functions
# =============================================================================

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Remove Azure Static Web Apps with Front Door and WAF protection resources.

OPTIONS:
    --resource-group NAME        Specific resource group to delete
    --force                      Skip confirmation prompts
    --dry-run                    Show what would be deleted without making changes
    --help                       Show this help message

EXAMPLES:
    $0                                          # Interactive deletion
    $0 --resource-group rg-secure-webapp-abc123  # Delete specific resource group
    $0 --force                                  # Skip confirmations
    $0 --dry-run                               # Preview deletion

SAFETY:
    This script will DELETE ALL RESOURCES in the target resource group.
    Use with caution in production environments.

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI v2.53.0 or later."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &>/dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get subscription info
    local subscription_id subscription_name
    subscription_id=$(az account show --query id -o tsv)
    subscription_name=$(az account show --query name -o tsv)
    log_info "Using Azure subscription: ${subscription_name} (${subscription_id})"
    
    log_success "Prerequisites check completed"
}

find_resource_groups() {
    log_info "Searching for secure web application resource groups..."
    
    # Get all resource groups with the naming pattern
    local rg_list
    rg_list=$(az group list --query "[?starts_with(name, 'rg-secure-webapp-')].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -z "${rg_list}" ]]; then
        log_warning "No resource groups found with pattern 'rg-secure-webapp-*'"
        return 1
    fi
    
    log_info "Found resource groups:"
    echo "${rg_list}" | while read -r rg; do
        log_info "  - ${rg}"
    done
    
    echo "${rg_list}"
}

select_resource_group() {
    if [[ -n "${RESOURCE_GROUP}" ]]; then
        # Verify the specified resource group exists
        if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
            log_error "Resource group '${RESOURCE_GROUP}' not found"
            exit 1
        fi
        log_info "Using specified resource group: ${RESOURCE_GROUP}"
        return 0
    fi
    
    # Find resource groups automatically
    local available_rgs
    if ! available_rgs=$(find_resource_groups); then
        log_error "No secure web application resource groups found"
        log_info "You can specify a resource group manually with --resource-group option"
        exit 1
    fi
    
    # Count resource groups
    local rg_count
    rg_count=$(echo "${available_rgs}" | wc -l)
    
    if [[ ${rg_count} -eq 1 ]]; then
        RESOURCE_GROUP="${available_rgs}"
        log_info "Auto-selected resource group: ${RESOURCE_GROUP}"
    elif [[ "${FORCE_DELETE}" == "true" ]]; then
        log_error "Multiple resource groups found but --force specified. Use --resource-group to specify which one."
        exit 1
    else
        # Interactive selection
        log_info "Multiple resource groups found. Please select one:"
        local i=1
        declare -a rg_array
        while IFS= read -r rg; do
            echo "  ${i}) ${rg}"
            rg_array[${i}]="${rg}"
            ((i++))
        done <<< "${available_rgs}"
        
        while true; do
            read -p "Enter selection (1-${rg_count}): " selection
            if [[ ${selection} =~ ^[0-9]+$ ]] && [[ ${selection} -ge 1 ]] && [[ ${selection} -le ${rg_count} ]]; then
                RESOURCE_GROUP="${rg_array[${selection}]}"
                log_info "Selected resource group: ${RESOURCE_GROUP}"
                break
            else
                echo "Invalid selection. Please enter a number between 1 and ${rg_count}."
            fi
        done
    fi
}

get_resource_inventory() {
    log_info "Getting resource inventory for '${RESOURCE_GROUP}'..."
    
    # Get all resources in the resource group
    local resources
    resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name,Type:type,Location:location}" -o table 2>/dev/null || echo "")
    
    if [[ -z "${resources}" ]] || [[ "${resources}" == *"No resources found"* ]]; then
        log_warning "No resources found in resource group '${RESOURCE_GROUP}'"
        return 1
    fi
    
    log_info "Resources to be deleted:"
    echo "${resources}" | tee -a "${LOG_FILE}"
    
    # Count resources
    local resource_count
    resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    log_info "Total resources: ${resource_count}"
    
    return 0
}

confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log_warning "Force deletion enabled. Skipping confirmations."
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "Dry run mode. No resources will be deleted."
        return 0
    fi
    
    log_warning "This will permanently DELETE ALL RESOURCES in:"
    log_warning "  Resource Group: ${RESOURCE_GROUP}"
    log_warning ""
    log_warning "This action cannot be undone!"
    log_warning ""
    
    while true; do
        read -p "Are you sure you want to continue? (yes/no): " confirm
        case ${confirm} in
            [Yy]es|[Yy])
                log_info "Deletion confirmed by user"
                break
                ;;
            [Nn]o|[Nn])
                log_info "Deletion cancelled by user"
                exit 0
                ;;
            *)
                echo "Please answer 'yes' or 'no'"
                ;;
        esac
    done
    
    # Double confirmation for safety
    read -p "Type the resource group name to confirm: " rg_confirm
    if [[ "${rg_confirm}" != "${RESOURCE_GROUP}" ]]; then
        log_error "Resource group name confirmation failed. Deletion cancelled."
        exit 1
    fi
    
    log_info "Resource group name confirmed. Proceeding with deletion..."
}

delete_front_door_resources() {
    log_info "Deleting Azure Front Door resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Front Door profiles in ${RESOURCE_GROUP}"
        return 0
    fi
    
    # Find and delete Front Door profiles
    local afd_profiles
    afd_profiles=$(az afd profile list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${afd_profiles}" ]]; then
        while IFS= read -r profile; do
            if [[ -n "${profile}" ]]; then
                log_info "Deleting Front Door profile: ${profile}"
                az afd profile delete \
                    --profile-name "${profile}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --yes \
                    --output none || log_warning "Failed to delete Front Door profile: ${profile}"
            fi
        done <<< "${afd_profiles}"
        
        log_success "Front Door profiles deletion initiated"
    else
        log_info "No Front Door profiles found"
    fi
}

delete_waf_policies() {
    log_info "Deleting WAF policies..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete WAF policies in ${RESOURCE_GROUP}"
        return 0
    fi
    
    # Find and delete WAF policies
    local waf_policies
    waf_policies=$(az network front-door waf-policy list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${waf_policies}" ]]; then
        while IFS= read -r policy; do
            if [[ -n "${policy}" ]]; then
                log_info "Deleting WAF policy: ${policy}"
                az network front-door waf-policy delete \
                    --name "${policy}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --output none || log_warning "Failed to delete WAF policy: ${policy}"
            fi
        done <<< "${waf_policies}"
        
        log_success "WAF policies deleted"
    else
        log_info "No WAF policies found"
    fi
}

delete_static_web_apps() {
    log_info "Deleting Static Web Apps..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Static Web Apps in ${RESOURCE_GROUP}"
        return 0
    fi
    
    # Find and delete Static Web Apps
    local static_apps
    static_apps=$(az staticwebapp list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${static_apps}" ]]; then
        while IFS= read -r app; do
            if [[ -n "${app}" ]]; then
                log_info "Deleting Static Web App: ${app}"
                az staticwebapp delete \
                    --name "${app}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --yes \
                    --output none || log_warning "Failed to delete Static Web App: ${app}"
            fi
        done <<< "${static_apps}"
        
        log_success "Static Web Apps deleted"
    else
        log_info "No Static Web Apps found"
    fi
}

wait_for_resource_deletion() {
    local max_attempts=60
    local attempt=1
    
    log_info "Waiting for resource deletion to complete..."
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local resource_count
        resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
        
        if [[ ${resource_count} -eq 0 ]]; then
            log_success "All resources have been deleted"
            return 0
        fi
        
        log_info "Attempt ${attempt}/${max_attempts}: ${resource_count} resources remaining..."
        sleep 10
        ((attempt++))
    done
    
    log_warning "Timeout waiting for all resources to be deleted"
    log_info "Some resources may still be in deletion process"
}

delete_resource_group() {
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete resource group: ${RESOURCE_GROUP}"
        return 0
    fi
    
    # Delete the entire resource group
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        --output none
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Deletion is running in background and may take several minutes"
}

cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    # Remove configuration files created during deployment
    local config_files=(
        "${SCRIPT_DIR}/staticwebapp.config.json"
        "${SCRIPT_DIR}/deployment_summary.txt"
    )
    
    for file in "${config_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_info "Removed: ${file}"
        fi
    done
    
    log_success "Local files cleaned up"
}

verify_deletion() {
    log_info "Verifying deletion status..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_warning "Resource group '${RESOURCE_GROUP}' still exists"
        log_info "Deletion may still be in progress. Check Azure portal for status."
        
        # List any remaining resources
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")
        if [[ ${remaining_resources} -gt 0 ]]; then
            log_warning "${remaining_resources} resources still remain in the resource group"
        fi
    else
        log_success "Resource group '${RESOURCE_GROUP}' has been completely deleted"
    fi
}

print_deletion_summary() {
    log_info "Deletion Summary:"
    log_info "================="
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Deletion initiated at: $(date)"
    log_info ""
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN completed - No resources were actually deleted"
    else
        log_info "All resources have been scheduled for deletion"
        log_info "Complete deletion may take several minutes"
        log_info "Check Azure portal to monitor deletion progress"
    fi
    
    log_info ""
    log_info "Log file: ${LOG_FILE}"
}

# =============================================================================
# Main Cleanup Flow
# =============================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    log_info "Starting Azure Secure Web Application cleanup..."
    log_info "Log file: ${LOG_FILE}"
    
    # Cleanup steps
    check_prerequisites
    select_resource_group
    
    # Show what will be deleted
    if get_resource_inventory; then
        confirm_deletion
        
        # Perform deletion in order (most dependent first)
        delete_front_door_resources
        delete_waf_policies
        delete_static_web_apps
        
        # Wait a bit for individual resource deletions
        if [[ "${DRY_RUN}" == "false" ]]; then
            sleep 30
            wait_for_resource_deletion
        fi
        
        # Delete the entire resource group
        delete_resource_group
        
        # Cleanup local files
        cleanup_local_files
        
        # Verify deletion
        if [[ "${DRY_RUN}" == "false" ]]; then
            sleep 10
            verify_deletion
        fi
    else
        log_info "Resource group appears to be empty or already deleted"
        if [[ "${DRY_RUN}" == "false" ]]; then
            delete_resource_group
        fi
    fi
    
    print_deletion_summary
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        log_success "Cleanup completed successfully!"
    else
        log_info "Dry run completed. Use without --dry-run to actually delete resources."
    fi
}

# Run main function
main "$@"