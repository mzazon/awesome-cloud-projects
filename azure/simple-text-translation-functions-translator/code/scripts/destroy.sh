#!/bin/bash

#######################################################################
# Azure Simple Text Translation Cleanup Script
# 
# This script removes all Azure resources created by the deploy.sh script
# for the serverless text translation API
#
# Prerequisites:
# - Azure CLI installed and authenticated
# - Appropriate Azure permissions for resource deletion
# - bash shell environment
#######################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
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
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load deployment info
load_deployment_info() {
    log_info "Loading deployment information..."
    
    local info_file="deployment-info.txt"
    
    if [ -f "${info_file}" ]; then
        log_info "Found deployment info file: ${info_file}"
        
        # Source the deployment info file to get environment variables
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^#.*$ ]] && continue
            [[ -z $key ]] && continue
            
            # Export the variable
            export "$key"="$value"
        done < "${info_file}"
        
        log_success "Deployment information loaded"
        log_info "Resource Group: ${RESOURCE_GROUP:-Not found}"
        log_info "Function App: ${FUNCTION_APP_NAME:-Not found}"
        log_info "Translator: ${TRANSLATOR_NAME:-Not found}"
        log_info "Storage Account: ${STORAGE_ACCOUNT_NAME:-Not found}"
    else
        log_warning "No deployment info file found. Will attempt to use environment variables or prompt for input."
    fi
}

# Function to prompt for resource group if not found
prompt_for_resource_group() {
    if [ -z "${RESOURCE_GROUP:-}" ]; then
        log_warning "Resource group not specified."
        echo -n "Enter the resource group name to delete (or press Ctrl+C to cancel): "
        read -r RESOURCE_GROUP
        
        if [ -z "${RESOURCE_GROUP}" ]; then
            log_error "Resource group name is required"
            exit 1
        fi
        
        export RESOURCE_GROUP
    fi
    
    # Verify the resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Resource group '${RESOURCE_GROUP}' not found or not accessible"
        exit 1
    fi
    
    log_info "Target resource group: ${RESOURCE_GROUP}"
}

# Function to list resources to be deleted
list_resources() {
    log_info "Listing resources in resource group: ${RESOURCE_GROUP}"
    
    local resources
    if resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --output table 2>/dev/null); then
        if [ -n "$resources" ]; then
            echo ""
            echo "$resources"
            echo ""
            log_info "Found $(az resource list --resource-group "${RESOURCE_GROUP}" --query 'length(@)' --output tsv) resources to delete"
        else
            log_warning "No resources found in resource group ${RESOURCE_GROUP}"
        fi
    else
        log_error "Failed to list resources in resource group ${RESOURCE_GROUP}"
        exit 1
    fi
}

# Function to confirm deletion
confirm_deletion() {
    if [ "${FORCE_DELETE:-false}" = "true" ]; then
        log_warning "Force delete mode enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    log_warning "This will permanently delete ALL resources in the resource group: ${RESOURCE_GROUP}"
    log_warning "This action cannot be undone!"
    echo ""
    
    local confirmation
    echo -n "Are you sure you want to continue? Type 'yes' to confirm: "
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_info "Deletion confirmed by user"
}

# Function to delete individual resources (optional detailed cleanup)
delete_individual_resources() {
    if [ "${DETAILED_CLEANUP:-false}" != "true" ]; then
        log_info "Skipping individual resource deletion (will delete resource group)"
        return 0
    fi
    
    log_info "Performing detailed resource cleanup..."
    
    # Delete Function App
    if [ -n "${FUNCTION_APP_NAME:-}" ]; then
        log_info "Deleting Function App: ${FUNCTION_APP_NAME}"
        if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az functionapp delete \
                --name "${FUNCTION_APP_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output table
            log_success "Function App deleted: ${FUNCTION_APP_NAME}"
        else
            log_warning "Function App ${FUNCTION_APP_NAME} not found"
        fi
    fi
    
    # Delete Translator Service
    if [ -n "${TRANSLATOR_NAME:-}" ]; then
        log_info "Deleting Translator service: ${TRANSLATOR_NAME}"
        if az cognitiveservices account show --name "${TRANSLATOR_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az cognitiveservices account delete \
                --name "${TRANSLATOR_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output table
            log_success "Translator service deleted: ${TRANSLATOR_NAME}"
        else
            log_warning "Translator service ${TRANSLATOR_NAME} not found"
        fi
    fi
    
    # Delete Storage Account
    if [ -n "${STORAGE_ACCOUNT_NAME:-}" ]; then
        log_info "Deleting Storage Account: ${STORAGE_ACCOUNT_NAME}"
        if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az storage account delete \
                --name "${STORAGE_ACCOUNT_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output table
            log_success "Storage Account deleted: ${STORAGE_ACCOUNT_NAME}"
        else
            log_warning "Storage Account ${STORAGE_ACCOUNT_NAME} not found"
        fi
    fi
    
    log_success "Individual resource cleanup completed"
}

# Function to delete resource group
delete_resource_group() {
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} not found"
        return 0
    fi
    
    # Start async deletion
    if [ "${WAIT_FOR_DELETION:-true}" = "true" ]; then
        log_info "Deleting resource group (waiting for completion)..."
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --output table
        log_success "Resource group deleted: ${RESOURCE_GROUP}"
    else
        log_info "Initiating resource group deletion (not waiting for completion)..."
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait \
            --output table
        log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        log_info "Note: Deletion may take several minutes to complete"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-info.txt"
        "function.zip"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_success "Removed local file: $file"
        fi
    done
    
    # Clean up environment variables
    local vars_to_unset=(
        "RESOURCE_GROUP"
        "LOCATION"
        "SUBSCRIPTION_ID"
        "RANDOM_SUFFIX"
        "TRANSLATOR_NAME"
        "FUNCTION_APP_NAME"
        "STORAGE_ACCOUNT_NAME"
        "TRANSLATOR_ENDPOINT"
        "TRANSLATOR_KEY"
        "FUNCTION_URL"
        "FUNCTION_KEY"
    )
    
    for var in "${vars_to_unset[@]}"; do
        unset "$var" 2>/dev/null || true
    done
    
    log_success "Environment variables cleaned up"
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} still exists"
        log_info "Deletion may still be in progress if --no-wait was used"
        
        # Show remaining resources
        local remaining_count
        remaining_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query 'length(@)' --output tsv 2>/dev/null || echo "unknown")
        
        if [ "$remaining_count" != "unknown" ] && [ "$remaining_count" -gt 0 ]; then
            log_warning "Found $remaining_count remaining resources:"
            az resource list --resource-group "${RESOURCE_GROUP}" --output table 2>/dev/null || true
        fi
    else
        log_success "Resource group ${RESOURCE_GROUP} has been successfully deleted"
    fi
}

# Function to show cleanup status
show_cleanup_status() {
    log_info "Cleanup Status Summary"
    log_info "====================="
    
    if [ -n "${RESOURCE_GROUP:-}" ]; then
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            local resource_count
            resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query 'length(@)' --output tsv 2>/dev/null || echo "0")
            
            if [ "$resource_count" -eq 0 ]; then
                log_success "✓ Resource group exists but contains no resources"
            else
                log_warning "⚠ Resource group contains $resource_count resources (deletion may be in progress)"
            fi
        else
            log_success "✓ Resource group has been completely removed"
        fi
    fi
    
    # Check for local files
    if [ -f "deployment-info.txt" ]; then
        log_warning "⚠ deployment-info.txt still exists"
    else
        log_success "✓ Local deployment files cleaned up"
    fi
    
    log_info "====================="
}

# Main cleanup function
main() {
    log_info "Starting Azure Text Translation cleanup..."
    log_info "=========================================="
    
    # Check if running in dry-run mode
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        load_deployment_info
        prompt_for_resource_group
        list_resources
        log_info "In normal mode, would delete resource group: ${RESOURCE_GROUP}"
        exit 0
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_info
    prompt_for_resource_group
    list_resources
    confirm_deletion
    delete_individual_resources
    delete_resource_group
    cleanup_local_files
    
    # Verification (if not using no-wait)
    if [ "${WAIT_FOR_DELETION:-true}" = "true" ]; then
        verify_deletion
    fi
    
    show_cleanup_status
    
    log_success "=========================================="
    log_success "Cleanup completed successfully!"
    log_success "=========================================="
    
    if [ "${WAIT_FOR_DELETION:-true}" != "true" ]; then
        log_info "Note: Resource deletion was initiated asynchronously."
        log_info "Check Azure portal to monitor deletion progress."
    fi
}

# Handle script interruption
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        log_error "Cleanup failed! Check the error messages above."
        log_info "You may need to manually remove resources from the Azure portal."
    fi
}

trap cleanup_on_exit EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            export DRY_RUN=true
            shift
            ;;
        --force)
            export FORCE_DELETE=true
            shift
            ;;
        --detailed)
            export DETAILED_CLEANUP=true
            shift
            ;;
        --no-wait)
            export WAIT_FOR_DELETION=false
            shift
            ;;
        --resource-group)
            export RESOURCE_GROUP="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run              Show what would be deleted without removing resources"
            echo "  --force                Skip deletion confirmation prompt"
            echo "  --detailed             Delete individual resources before deleting resource group"
            echo "  --no-wait              Don't wait for deletion to complete (async)"
            echo "  --resource-group NAME  Specify resource group name to delete"
            echo "  --help                 Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  RESOURCE_GROUP         Override resource group name"
            echo "  FORCE_DELETE          Skip confirmation (set to 'true')"
            echo "  DETAILED_CLEANUP      Delete individual resources first (set to 'true')"
            echo "  WAIT_FOR_DELETION     Wait for deletion completion (set to 'false' for async)"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Interactive cleanup"
            echo "  $0 --dry-run                         # Preview what would be deleted"
            echo "  $0 --force --no-wait                 # Quick non-interactive cleanup"
            echo "  $0 --resource-group my-rg --detailed # Delete specific RG with detailed cleanup"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main cleanup
main "$@"