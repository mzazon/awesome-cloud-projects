#!/bin/bash
#
# Azure Automated Audio Summarization Cleanup Script
# This script removes all Azure resources created by the deployment script
#
# Prerequisites:
# - Azure CLI installed and authenticated
# - Deployment configuration file from deploy.sh
#
# Usage: ./destroy.sh [--force]
#

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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_CONFIG_FILE="${SCRIPT_DIR}/deployment_config.env"
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--force]"
            echo "  --force    Skip confirmation prompts"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI authentication
    if ! az account show &> /dev/null; then
        log_error "Azure CLI is not authenticated. Please run 'az login'"
        exit 1
    fi
    
    # Check for deployment configuration file
    if [[ ! -f "${DEPLOYMENT_CONFIG_FILE}" ]]; then
        log_error "Deployment configuration file not found: ${DEPLOYMENT_CONFIG_FILE}"
        log_error "This file is created by the deploy.sh script and contains resource information."
        log_error "You may need to manually identify and delete resources."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load deployment configuration
load_deployment_config() {
    log_info "Loading deployment configuration..."
    
    # Source the configuration file
    source "${DEPLOYMENT_CONFIG_FILE}"
    
    # Verify required variables are loaded
    if [[ -z "${RESOURCE_GROUP:-}" || -z "${STORAGE_ACCOUNT:-}" || -z "${FUNCTION_APP:-}" || -z "${OPENAI_RESOURCE:-}" ]]; then
        log_error "Invalid or incomplete deployment configuration file"
        log_error "Required variables: RESOURCE_GROUP, STORAGE_ACCOUNT, FUNCTION_APP, OPENAI_RESOURCE"
        exit 1
    fi
    
    log_success "Configuration loaded successfully"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Storage Account: ${STORAGE_ACCOUNT}"
    log_info "Function App: ${FUNCTION_APP}"
    log_info "OpenAI Resource: ${OPENAI_RESOURCE}"
    
    if [[ -n "${DEPLOYMENT_DATE:-}" ]]; then
        log_info "Deployment Date: ${DEPLOYMENT_DATE}"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation prompts"
        return 0
    fi
    
    echo
    log_warning "This will permanently delete the following Azure resources:"
    echo "  • Resource Group: ${RESOURCE_GROUP}"
    echo "  • Storage Account: ${STORAGE_ACCOUNT} (including all blob data)"
    echo "  • Function App: ${FUNCTION_APP}"
    echo "  • Azure OpenAI Resource: ${OPENAI_RESOURCE}"
    echo "  • All associated data and configurations"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to proceed? (type 'yes' to continue): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    log_warning "Final confirmation: This will delete ALL resources in resource group ${RESOURCE_GROUP}"
    read -p "Type the resource group name to confirm: " -r
    if [[ "$REPLY" != "${RESOURCE_GROUP}" ]]; then
        log_error "Resource group name doesn't match. Cleanup cancelled."
        exit 1
    fi
    
    log_info "Deletion confirmed. Proceeding with cleanup..."
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    
    case "${resource_type}" in
        "resourcegroup")
            az group show --name "${resource_name}" --output none 2>/dev/null
            ;;
        "functionapp")
            az functionapp show --name "${resource_name}" --resource-group "${resource_group}" --output none 2>/dev/null
            ;;
        "storage")
            az storage account show --name "${resource_name}" --resource-group "${resource_group}" --output none 2>/dev/null
            ;;
        "cognitiveservices")
            az cognitiveservices account show --name "${resource_name}" --resource-group "${resource_group}" --output none 2>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to delete Function App
delete_function_app() {
    log_info "Checking Function App: ${FUNCTION_APP}"
    
    if resource_exists "functionapp" "${FUNCTION_APP}" "${RESOURCE_GROUP}"; then
        log_info "Deleting Function App: ${FUNCTION_APP}"
        
        # Stop the function app first to ensure clean shutdown
        az functionapp stop \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none 2>/dev/null || true
        
        # Delete the function app
        az functionapp delete \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none
        
        log_success "Function App deleted: ${FUNCTION_APP}"
    else
        log_warning "Function App not found: ${FUNCTION_APP}"
    fi
}

# Function to delete Azure OpenAI resource
delete_openai_resource() {
    log_info "Checking Azure OpenAI resource: ${OPENAI_RESOURCE}"
    
    if resource_exists "cognitiveservices" "${OPENAI_RESOURCE}" "${RESOURCE_GROUP}"; then
        log_info "Deleting Azure OpenAI resource: ${OPENAI_RESOURCE}"
        
        # Delete OpenAI resource
        az cognitiveservices account delete \
            --name "${OPENAI_RESOURCE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none
        
        log_success "Azure OpenAI resource deleted: ${OPENAI_RESOURCE}"
    else
        log_warning "Azure OpenAI resource not found: ${OPENAI_RESOURCE}"
    fi
}

# Function to delete storage account
delete_storage_account() {
    log_info "Checking Storage Account: ${STORAGE_ACCOUNT}"
    
    if resource_exists "storage" "${STORAGE_ACCOUNT}" "${RESOURCE_GROUP}"; then
        log_info "Deleting Storage Account and all blob data: ${STORAGE_ACCOUNT}"
        
        # Delete storage account (this also deletes all containers and blobs)
        az storage account delete \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none
        
        log_success "Storage Account deleted: ${STORAGE_ACCOUNT}"
    else
        log_warning "Storage Account not found: ${STORAGE_ACCOUNT}"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log_info "Checking Resource Group: ${RESOURCE_GROUP}"
    
    if resource_exists "resourcegroup" "${RESOURCE_GROUP}" ""; then
        log_info "Deleting Resource Group and all remaining resources: ${RESOURCE_GROUP}"
        
        # Delete resource group and all contained resources
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait \
            --output none
        
        log_success "Resource Group deletion initiated: ${RESOURCE_GROUP}"
        log_info "Note: Resource group deletion may take several minutes to complete"
        
        # Optionally wait for deletion to complete
        if [[ "${FORCE_DELETE}" != "true" ]]; then
            read -p "Wait for resource group deletion to complete? (y/N): " -r
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "Waiting for resource group deletion to complete..."
                
                # Wait for resource group to be deleted (timeout after 10 minutes)
                local timeout=600
                local elapsed=0
                local interval=15
                
                while resource_exists "resourcegroup" "${RESOURCE_GROUP}" "" && [[ $elapsed -lt $timeout ]]; do
                    sleep $interval
                    elapsed=$((elapsed + interval))
                    echo -n "."
                    
                    if [[ $((elapsed % 60)) -eq 0 ]]; then
                        echo " (${elapsed}s elapsed)"
                    fi
                done
                
                if resource_exists "resourcegroup" "${RESOURCE_GROUP}" ""; then
                    log_warning "Resource group deletion is taking longer than expected"
                    log_info "You can check the status with: az group show --name ${RESOURCE_GROUP}"
                else
                    echo
                    log_success "Resource group deletion completed successfully"
                fi
            fi
        fi
    else
        log_warning "Resource Group not found: ${RESOURCE_GROUP}"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment configuration file
    if [[ -f "${DEPLOYMENT_CONFIG_FILE}" ]]; then
        rm -f "${DEPLOYMENT_CONFIG_FILE}"
        log_success "Removed deployment configuration file"
    fi
    
    # Remove any sample files that might have been left behind
    if [[ -f "${SCRIPT_DIR}/sample-audio.wav" ]]; then
        rm -f "${SCRIPT_DIR}/sample-audio.wav"
        log_success "Removed sample audio file"
    fi
    
    if [[ -f "${SCRIPT_DIR}/result.json" ]]; then
        rm -f "${SCRIPT_DIR}/result.json"
        log_success "Removed result file"
    fi
    
    log_success "Local file cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if resource_exists "resourcegroup" "${RESOURCE_GROUP}" ""; then
        log_warning "Resource Group still exists: ${RESOURCE_GROUP}"
        log_info "Deletion may still be in progress. Check status with:"
        log_info "  az group show --name ${RESOURCE_GROUP}"
    else
        log_success "Resource Group successfully deleted: ${RESOURCE_GROUP}"
    fi
    
    # Check for any remaining resources (in case of partial deletion)
    log_info "Checking for any remaining resources..."
    
    # This will only work if the resource group still exists
    if resource_exists "resourcegroup" "${RESOURCE_GROUP}" ""; then
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length([?not(contains(type, 'Microsoft.Insights'))])" --output tsv 2>/dev/null || echo "0")
        
        if [[ "${remaining_resources}" -gt 0 ]]; then
            log_warning "Found ${remaining_resources} remaining resources in ${RESOURCE_GROUP}"
            log_info "List remaining resources with:"
            log_info "  az resource list --resource-group ${RESOURCE_GROUP} --output table"
        else
            log_success "No remaining resources found in resource group"
        fi
    fi
}

# Function to display cleanup summary
display_summary() {
    echo
    log_success "Cleanup process completed!"
    echo
    echo "=== Cleanup Summary ==="
    echo "Resource Group: ${RESOURCE_GROUP} - Deletion initiated"
    echo "Function App: ${FUNCTION_APP} - Deleted"
    echo "Azure OpenAI Resource: ${OPENAI_RESOURCE} - Deleted"
    echo "Storage Account: ${STORAGE_ACCOUNT} - Deleted"
    echo "Local configuration files - Cleaned up"
    echo
    echo "=== Notes ==="
    echo "• Resource group deletion may take several minutes to complete"
    echo "• All blob data has been permanently deleted"
    echo "• Azure OpenAI model deployments have been removed"
    echo "• Check your Azure portal to confirm all resources are deleted"
    echo
    
    if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
        echo "=== Verification Commands ==="
        echo "Check resource group status:"
        echo "  az group show --name ${RESOURCE_GROUP}"
        echo
        echo "List any remaining resources:"
        echo "  az resource list --resource-group ${RESOURCE_GROUP} --output table"
        echo
    fi
}

# Function to handle cleanup errors
handle_cleanup_error() {
    local error_message="$1"
    local resource_name="$2"
    
    log_error "Failed to delete ${resource_name}: ${error_message}"
    log_warning "You may need to manually delete this resource through the Azure portal"
    log_info "Resource: ${resource_name}"
    log_info "Resource Group: ${RESOURCE_GROUP}"
}

# Main cleanup function with error handling
perform_cleanup() {
    log_info "Starting resource cleanup process..."
    
    # Delete resources in reverse order of dependencies
    
    # 1. Delete Function App first (depends on storage)
    delete_function_app || handle_cleanup_error "Function app deletion failed" "${FUNCTION_APP}"
    
    # 2. Delete Azure OpenAI resource (independent)
    delete_openai_resource || handle_cleanup_error "OpenAI resource deletion failed" "${OPENAI_RESOURCE}"
    
    # 3. Delete Storage Account (may have dependencies)
    delete_storage_account || handle_cleanup_error "Storage account deletion failed" "${STORAGE_ACCOUNT}"
    
    # 4. Delete Resource Group (contains all resources)
    delete_resource_group || handle_cleanup_error "Resource group deletion failed" "${RESOURCE_GROUP}"
    
    # 5. Clean up local files
    cleanup_local_files || log_warning "Local file cleanup had some issues"
    
    log_success "Resource cleanup process completed"
}

# Main execution flow
main() {
    log_info "Starting Azure Automated Audio Summarization cleanup..."
    
    check_prerequisites
    load_deployment_config
    confirm_deletion
    perform_cleanup
    verify_cleanup
    display_summary
    
    log_success "Cleanup completed successfully!"
}

# Handle script interruption
trap 'log_error "Cleanup interrupted. Some resources may not have been deleted."; exit 1' INT TERM

# Error handling for cleanup operations
set +e  # Don't exit on errors during cleanup - we want to try to clean up as much as possible

# Run main function
main "$@"