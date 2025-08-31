#!/bin/bash

# =============================================================================
# Azure Static Website Acceleration with CDN and Storage - Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script,
# including resource groups, storage accounts, CDN profiles, and endpoints.
#
# Prerequisites:
# - Azure CLI installed and configured
# - Access to the same Azure subscription used for deployment
# - Appropriate permissions to delete resources
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup failed. Check ${LOG_FILE} for details."
    log_warning "Some resources may still exist. Review the Azure portal."
    exit 1
}

trap cleanup_on_error ERR

# Validation functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if subscription is set
    local subscription_id
    subscription_id=$(az account show --query id -o tsv)
    log_info "Using Azure subscription: ${subscription_id}"
    
    log_success "Prerequisites check completed"
}

# Load deployment state
load_deployment_state() {
    if [[ ! -f "${STATE_FILE}" ]]; then
        log_error "No deployment state file found at ${STATE_FILE}"
        log_info "If you know the resource group name, you can set it manually:"
        log_info "export RESOURCE_GROUP=your-resource-group-name"
        log_info "Then run this script again."
        exit 1
    fi
    
    source "${STATE_FILE}"
    log_info "Loaded deployment state from ${STATE_FILE}"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Storage Account: ${STORAGE_ACCOUNT}"
    log_info "CDN Profile: ${CDN_PROFILE}"
    log_info "CDN Endpoint: ${CDN_ENDPOINT}"
}

# Confirmation functions
confirm_deletion() {
    echo
    log_warning "This will permanently delete all resources in the deployment:"
    echo "  - Resource Group: ${RESOURCE_GROUP}"
    echo "  - Storage Account: ${STORAGE_ACCOUNT} (and all data)"
    echo "  - CDN Profile: ${CDN_PROFILE}"
    echo "  - CDN Endpoint: ${CDN_ENDPOINT}"
    echo
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    log_warning "Last chance! This action cannot be undone."
    read -p "Type 'DELETE' to confirm: " -r
    if [[ $REPLY != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Resource validation
check_resource_existence() {
    local resource_group="$1"
    
    log_info "Checking if resources exist..."
    
    # Check if resource group exists
    if ! az group exists --name "${resource_group}" | grep -q "true"; then
        log_warning "Resource group '${resource_group}' does not exist. Nothing to clean up."
        return 1
    fi
    
    log_info "Resource group '${resource_group}' exists and will be deleted"
    return 0
}

# Resource deletion functions
delete_cdn_resources() {
    local resource_group="$1"
    local cdn_profile="$2"
    local cdn_endpoint="$3"
    
    log_info "Deleting CDN resources..."
    
    # Check if CDN endpoint exists
    if az cdn endpoint show --name "${cdn_endpoint}" --profile-name "${cdn_profile}" --resource-group "${resource_group}" &> /dev/null; then
        log_info "Deleting CDN endpoint: ${cdn_endpoint}"
        az cdn endpoint delete \
            --name "${cdn_endpoint}" \
            --profile-name "${cdn_profile}" \
            --resource-group "${resource_group}" \
            --yes \
            --output none
        log_success "CDN endpoint deleted: ${cdn_endpoint}"
    else
        log_warning "CDN endpoint '${cdn_endpoint}' not found"
    fi
    
    # Check if CDN profile exists
    if az cdn profile show --name "${cdn_profile}" --resource-group "${resource_group}" &> /dev/null; then
        log_info "Deleting CDN profile: ${cdn_profile}"
        az cdn profile delete \
            --name "${cdn_profile}" \
            --resource-group "${resource_group}" \
            --yes \
            --output none
        log_success "CDN profile deleted: ${cdn_profile}"
    else
        log_warning "CDN profile '${cdn_profile}' not found"
    fi
}

delete_storage_resources() {
    local resource_group="$1"
    local storage_account="$2"
    
    log_info "Deleting storage resources..."
    
    # Check if storage account exists
    if az storage account show --name "${storage_account}" --resource-group "${resource_group}" &> /dev/null; then
        log_info "Deleting storage account: ${storage_account}"
        log_warning "This will permanently delete all website data!"
        
        # Delete storage account
        az storage account delete \
            --name "${storage_account}" \
            --resource-group "${resource_group}" \
            --yes \
            --output none
        
        log_success "Storage account deleted: ${storage_account}"
    else
        log_warning "Storage account '${storage_account}' not found"
    fi
}

delete_resource_group() {
    local resource_group="$1"
    
    log_info "Deleting resource group: ${resource_group}"
    log_warning "This will delete ALL resources in the group!"
    
    # Delete resource group and all contained resources
    az group delete \
        --name "${resource_group}" \
        --yes \
        --no-wait \
        --output none
    
    log_success "Resource group deletion initiated: ${resource_group}"
    log_info "Deletion is running in the background and may take several minutes"
}

# Verification functions
verify_deletion() {
    local resource_group="$1"
    local max_attempts=12
    local attempt=1
    
    log_info "Verifying resource deletion..."
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        if ! az group exists --name "${resource_group}" | grep -q "true"; then
            log_success "Resource group '${resource_group}' has been completely deleted"
            return 0
        fi
        
        log_info "Deletion in progress... (attempt ${attempt}/${max_attempts})"
        sleep 30
        ((attempt++))
    done
    
    log_warning "Resource group deletion is still in progress"
    log_info "You can check the status in the Azure portal or run:"
    log_info "az group exists --name '${resource_group}'"
    return 1
}

# Cleanup functions
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove state file
    if [[ -f "${STATE_FILE}" ]]; then
        rm -f "${STATE_FILE}"
        log_success "Deployment state file removed"
    fi
    
    # Remove any leftover website content
    local content_dir="${SCRIPT_DIR}/website-content"
    if [[ -d "${content_dir}" ]]; then
        rm -rf "${content_dir}"
        log_success "Local website content removed"
    fi
    
    # Create cleanup completion marker
    echo "Resources cleaned up at $(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "${SCRIPT_DIR}/.cleanup_complete"
    
    log_success "Local cleanup completed"
}

# Summary functions
display_summary() {
    local resource_group="$1"
    
    echo
    log_success "Cleanup completed successfully!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Resource Group: ${resource_group} (deleted)"
    echo "All contained resources have been removed"
    echo
    echo "=== VERIFICATION ==="
    echo "You can verify deletion by running:"
    echo "az group exists --name '${resource_group}'"
    echo
    echo "Or check the Azure portal at:"
    echo "https://portal.azure.com/#view/HubsExtension/BrowseResourceGroups"
    echo
    log_info "Cleanup log saved to: ${LOG_FILE}"
}

# Interactive mode function
interactive_cleanup() {
    log_info "Interactive cleanup mode"
    echo
    echo "This script can delete resources individually or all at once."
    echo
    echo "Options:"
    echo "1. Delete all resources (recommended)"
    echo "2. Delete CDN resources only"
    echo "3. Delete storage resources only"
    echo "4. Delete resource group (includes everything)"
    echo "5. Cancel"
    echo
    
    read -p "Select option (1-5): " -r option
    
    case $option in
        1)
            log_info "Selected: Delete all resources"
            confirm_deletion
            delete_cdn_resources "${RESOURCE_GROUP}" "${CDN_PROFILE}" "${CDN_ENDPOINT}"
            delete_storage_resources "${RESOURCE_GROUP}" "${STORAGE_ACCOUNT}"
            cleanup_local_files
            ;;
        2)
            log_info "Selected: Delete CDN resources only"
            delete_cdn_resources "${RESOURCE_GROUP}" "${CDN_PROFILE}" "${CDN_ENDPOINT}"
            ;;
        3)
            log_info "Selected: Delete storage resources only"
            delete_storage_resources "${RESOURCE_GROUP}" "${STORAGE_ACCOUNT}"
            ;;
        4)
            log_info "Selected: Delete resource group"
            confirm_deletion
            delete_resource_group "${RESOURCE_GROUP}"
            cleanup_local_files
            ;;
        5)
            log_info "Cleanup cancelled by user"
            exit 0
            ;;
        *)
            log_error "Invalid option selected"
            exit 1
            ;;
    esac
}

# Main cleanup function
main() {
    log_info "Starting Azure Static Website with CDN cleanup..."
    
    # Initialize log file
    echo "Cleanup started at $(date)" > "${LOG_FILE}"
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment state or use environment variables
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_info "Using resource group from environment: ${RESOURCE_GROUP}"
        STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-unknown}"
        CDN_PROFILE="${CDN_PROFILE:-unknown}"
        CDN_ENDPOINT="${CDN_ENDPOINT:-unknown}"
    else
        load_deployment_state
    fi
    
    # Check if resources exist
    if ! check_resource_existence "${RESOURCE_GROUP}"; then
        cleanup_local_files
        log_success "No resources to clean up"
        exit 0
    fi
    
    # Check for interactive mode
    if [[ "${1:-}" == "--interactive" ]] || [[ "${1:-}" == "-i" ]]; then
        interactive_cleanup
    else
        # Default: delete everything
        confirm_deletion
        
        # Delete CDN resources first (fastest)
        delete_cdn_resources "${RESOURCE_GROUP}" "${CDN_PROFILE}" "${CDN_ENDPOINT}"
        
        # Then delete storage resources
        delete_storage_resources "${RESOURCE_GROUP}" "${STORAGE_ACCOUNT}"
        
        # Finally delete the resource group (this ensures everything is gone)
        delete_resource_group "${RESOURCE_GROUP}"
        
        # Verify deletion
        verify_deletion "${RESOURCE_GROUP}"
        
        # Clean up local files
        cleanup_local_files
        
        # Display summary
        display_summary "${RESOURCE_GROUP}"
    fi
}

# Usage information
usage() {
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -i, --interactive    Interactive mode for selective deletion"
    echo "  -h, --help          Show this help message"
    echo
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP      Resource group name (overrides state file)"
    echo "  STORAGE_ACCOUNT     Storage account name"
    echo "  CDN_PROFILE         CDN profile name"
    echo "  CDN_ENDPOINT        CDN endpoint name"
    echo
    echo "Examples:"
    echo "  $0                           # Delete all resources"
    echo "  $0 --interactive             # Interactive mode"
    echo "  RESOURCE_GROUP=my-rg $0      # Delete specific resource group"
    echo
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    -i|--interactive)
        main "$@"
        ;;
    *)
        main "$@"
        ;;
esac