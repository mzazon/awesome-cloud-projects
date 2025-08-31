#!/bin/bash

# Destroy Azure Content Personalization Engine with AI Foundry and Cosmos
# This script removes all infrastructure created by the deploy.sh script
# including Cosmos DB, Azure OpenAI, AI Foundry, and Azure Functions

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy-$(date +%Y%m%d-%H%M%S).log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment-state"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Check ${LOG_FILE} for details."
    exit 1
}

# Load deployment state
load_state() {
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        source "${DEPLOYMENT_STATE_FILE}"
        return 0
    else
        log_warning "No deployment state file found at ${DEPLOYMENT_STATE_FILE}"
        return 1
    fi
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    log_success "Prerequisites check completed"
}

# Prompt for confirmation
confirm_destruction() {
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log_warning "Force destroy mode enabled. Skipping confirmation."
        return 0
    fi
    
    log_warning "This will permanently delete the following resources:"
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_warning "  - Resource Group: ${RESOURCE_GROUP}"
        log_warning "  - All resources within the resource group"
    else
        log_warning "  - Resource group name not found in state file"
    fi
    log_warning ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
}

# Initialize environment from state
initialize_environment() {
    log_info "Loading deployment state..."
    
    if load_state; then
        log_info "Deployment state loaded successfully"
        log_info "Resource Group: ${RESOURCE_GROUP:-not-found}"
        log_info "Subscription: ${SUBSCRIPTION_ID:-not-found}"
        log_info "Location: ${LOCATION:-not-found}"
    else
        log_warning "No deployment state found. Manual cleanup may be required."
        
        # Try to get resource group from user input if state is not available
        if [[ -z "${RESOURCE_GROUP:-}" ]]; then
            read -p "Enter resource group name to delete (or press Enter to skip): " -r RESOURCE_GROUP
            if [[ -z "${RESOURCE_GROUP}" ]]; then
                log_info "No resource group specified. Exiting."
                exit 0
            fi
        fi
    fi
}

# Check if resource group exists
check_resource_group() {
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_error "Resource group name not specified"
        return 1
    fi
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Resource group ${RESOURCE_GROUP} exists and will be deleted"
        return 0
    else
        log_warning "Resource group ${RESOURCE_GROUP} does not exist or was already deleted"
        return 1
    fi
}

# List resources before deletion
list_resources() {
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_warning "Cannot list resources: resource group name not available"
        return
    fi
    
    log_info "Listing resources in ${RESOURCE_GROUP}..."
    
    local resources=$(az resource list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].{Name:name, Type:type, Location:location}" \
        --output table 2>/dev/null || echo "Failed to list resources")
    
    if [[ "${resources}" != "Failed to list resources" ]]; then
        log_info "Resources to be deleted:"
        echo "${resources}" | tee -a "${LOG_FILE}"
    else
        log_warning "Could not list resources in resource group"
    fi
}

# Remove individual resources (optional graceful cleanup)
graceful_cleanup() {
    if [[ "${SKIP_GRACEFUL:-}" == "true" ]]; then
        log_info "Skipping graceful cleanup. Will delete resource group directly."
        return 0
    fi
    
    log_info "Performing graceful cleanup of individual resources..."
    
    # Remove Function App first (fastest to delete)
    if [[ -n "${FUNCTION_APP:-}" ]]; then
        log_info "Removing Function App: ${FUNCTION_APP}..."
        az functionapp delete \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes &> /dev/null || log_warning "Failed to delete Function App or it was already deleted"
        log_success "Function App removal initiated"
    fi
    
    # Remove Azure OpenAI service
    if [[ -n "${OPENAI_SERVICE:-}" ]]; then
        log_info "Removing Azure OpenAI service: ${OPENAI_SERVICE}..."
        az cognitiveservices account delete \
            --name "${OPENAI_SERVICE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes &> /dev/null || log_warning "Failed to delete OpenAI service or it was already deleted"
        log_success "Azure OpenAI service removal initiated"
    fi
    
    # Remove AI Foundry workspace
    if [[ -n "${AI_FOUNDRY_PROJECT:-}" ]]; then
        log_info "Removing AI Foundry workspace: ${AI_FOUNDRY_PROJECT}..."
        az ml workspace delete \
            --name "${AI_FOUNDRY_PROJECT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes --force-purge &> /dev/null || log_warning "Failed to delete AI Foundry workspace or it was already deleted"
        log_success "AI Foundry workspace removal initiated"
    fi
    
    # Remove Cosmos DB account (takes longest)
    if [[ -n "${COSMOS_ACCOUNT:-}" ]]; then
        log_info "Removing Cosmos DB account: ${COSMOS_ACCOUNT}..."
        log_info "Note: Cosmos DB deletion may take several minutes..."
        az cosmosdb delete \
            --name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes &> /dev/null || log_warning "Failed to delete Cosmos DB or it was already deleted"
        log_success "Cosmos DB account removal initiated"
    fi
    
    # Remove storage account
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        log_info "Removing storage account: ${STORAGE_ACCOUNT}..."
        az storage account delete \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes &> /dev/null || log_warning "Failed to delete storage account or it was already deleted"
        log_success "Storage account removal initiated"
    fi
    
    # Wait a bit for deletions to process
    log_info "Waiting for individual resource deletions to process..."
    sleep 30
}

# Delete the entire resource group
delete_resource_group() {
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_error "Cannot delete resource group: name not available"
        return 1
    fi
    
    if ! check_resource_group; then
        log_info "Resource group does not exist. Nothing to delete."
        return 0
    fi
    
    log_info "Deleting resource group: ${RESOURCE_GROUP}..."
    log_info "This operation will delete ALL resources in the resource group."
    
    # Delete with no-wait flag for faster script completion
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        || error_exit "Failed to initiate resource group deletion"
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Deletion is running in the background and may take several minutes to complete."
}

# Monitor deletion progress (optional)
monitor_deletion() {
    if [[ "${MONITOR_DELETION:-}" != "true" ]]; then
        log_info "Skipping deletion monitoring. Use --monitor to wait for completion."
        return 0
    fi
    
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_warning "Cannot monitor deletion: resource group name not available"
        return 0
    fi
    
    log_info "Monitoring resource group deletion progress..."
    log_info "This may take 5-15 minutes depending on resources..."
    
    local max_attempts=60  # 30 minutes maximum
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            log_success "Resource group ${RESOURCE_GROUP} has been successfully deleted"
            return 0
        fi
        
        log_info "Deletion in progress... (${attempt}/${max_attempts})"
        sleep 30
        ((attempt++))
    done
    
    log_warning "Deletion monitoring timed out. Resource group deletion may still be in progress."
    log_info "Check Azure portal or run 'az group show --name ${RESOURCE_GROUP}' to verify completion."
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove temporary files
    local files_to_remove=(
        "${SCRIPT_DIR}/ai-agent-config.json"
        "${SCRIPT_DIR}/vector-index-policy.json"
        "${SCRIPT_DIR}/personalization-function.zip"
        "${SCRIPT_DIR}/temp-function"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "${file}" ]]; then
            rm -rf "${file}"
            log_info "Removed: ${file}"
        fi
    done
    
    # Optionally remove deployment state file
    if [[ "${KEEP_STATE:-}" != "true" ]]; then
        if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
            rm -f "${DEPLOYMENT_STATE_FILE}"
            log_info "Removed deployment state file: ${DEPLOYMENT_STATE_FILE}"
        fi
    else
        log_info "Keeping deployment state file: ${DEPLOYMENT_STATE_FILE}"
    fi
    
    log_success "Local file cleanup completed"
}

# Validate cleanup
validate_cleanup() {
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_warning "Cannot validate cleanup: resource group name not available"
        return 0
    fi
    
    log_info "Validating cleanup..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} still exists"
        log_info "Deletion may still be in progress. Check Azure portal for status."
        return 1
    else
        log_success "Resource group ${RESOURCE_GROUP} has been deleted successfully"
        return 0
    fi
}

# Print cleanup summary
print_summary() {
    log_info ""
    log_info "=== CLEANUP SUMMARY ==="
    log_info "Resource Group: ${RESOURCE_GROUP:-not-specified}"
    log_info "Subscription: ${SUBSCRIPTION_ID:-not-specified}"
    log_info "Location: ${LOCATION:-not-specified}"
    log_info "Cleanup Log: ${LOG_FILE}"
    log_info ""
    
    if validate_cleanup; then
        log_success "Content Personalization Engine cleanup completed successfully!"
        log_info "All Azure resources have been removed."
    else
        log_warning "Cleanup may still be in progress."
        log_info "Check the Azure portal to verify resource deletion status."
    fi
    
    log_info ""
    log_info "If you encounter any issues:"
    log_info "1. Check the Azure portal for remaining resources"
    log_info "2. Manually delete any remaining resources if needed"
    log_info "3. Review the cleanup log: ${LOG_FILE}"
}

# Main cleanup flow
main() {
    log_info "Starting Azure Content Personalization Engine cleanup..."
    log_info "Cleanup started at: $(date)"
    
    check_prerequisites
    initialize_environment
    confirm_destruction
    
    if check_resource_group; then
        list_resources
        graceful_cleanup
        delete_resource_group
        monitor_deletion
    else
        log_info "No resource group to delete"
    fi
    
    cleanup_local_files
    print_summary
    
    log_success "Cleanup completed at: $(date)"
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Destroy Azure Content Personalization Engine"
            echo ""
            echo "Options:"
            echo "  --help, -h          Show this help message"
            echo "  --force             Skip confirmation prompt"
            echo "  --monitor           Wait for deletion to complete"
            echo "  --skip-graceful     Skip individual resource cleanup"
            echo "  --keep-state        Keep deployment state file"
            echo "  --resource-group RG Specify resource group name manually"
            echo ""
            echo "Environment Variables:"
            echo "  FORCE_DESTROY=true    Skip confirmation (same as --force)"
            echo "  MONITOR_DELETION=true Wait for completion (same as --monitor)"
            echo "  SKIP_GRACEFUL=true    Skip graceful cleanup (same as --skip-graceful)"
            echo "  KEEP_STATE=true       Keep state file (same as --keep-state)"
            echo ""
            exit 0
            ;;
        --force)
            export FORCE_DESTROY="true"
            shift
            ;;
        --monitor)
            export MONITOR_DELETION="true"
            shift
            ;;
        --skip-graceful)
            export SKIP_GRACEFUL="true"
            shift
            ;;
        --keep-state)
            export KEEP_STATE="true"
            shift
            ;;
        --resource-group)
            export RESOURCE_GROUP="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute main cleanup
main "$@"