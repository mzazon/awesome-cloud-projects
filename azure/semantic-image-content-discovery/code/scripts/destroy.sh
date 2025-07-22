#!/bin/bash
set -e

# =============================================================================
# Azure Intelligent Image Content Discovery - Cleanup Script
# =============================================================================
# This script removes all resources created by the deployment script for the
# intelligent image content discovery system.
#
# Resources to be deleted:
# - Azure Functions App
# - Azure AI Search Service and Index
# - Azure AI Vision Service
# - Azure Storage Account and Container
# - Resource Group (optional)
# =============================================================================

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it first."
        log_info "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if jq is installed (for JSON parsing)
    if ! command_exists jq; then
        log_error "jq is not installed. Please install it first."
        log_info "Visit: https://stedolan.github.io/jq/download/"
        exit 1
    fi
    
    # Check if curl is installed
    if ! command_exists curl; then
        log_error "curl is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI login status
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to prompt for confirmation
confirm_deletion() {
    local resource_name="$1"
    local default_answer="${2:-n}"
    
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}Are you sure you want to delete ${resource_name}? (y/N):${NC} "
    read -r response
    
    if [[ "${response}" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to set environment variables from user input or defaults
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Check if resource group is provided as argument
    if [[ -n "$1" ]]; then
        export RESOURCE_GROUP="$1"
    else
        export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-image-discovery-demo}"
    fi
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_error "Resource group '${RESOURCE_GROUP}' does not exist."
        log_info "Available resource groups:"
        az group list --query "[].name" --output table
        exit 1
    fi
    
    export LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location --output tsv)
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    log_success "Environment variables configured"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
}

# Function to discover resources in the resource group
discover_resources() {
    log_info "Discovering resources in resource group '${RESOURCE_GROUP}'..."
    
    # Get all resources in the resource group
    RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{name:name,type:type}" --output json)
    
    if [[ $(echo "${RESOURCES}" | jq length) -eq 0 ]]; then
        log_warning "No resources found in resource group '${RESOURCE_GROUP}'"
        return 1
    fi
    
    # Extract resource names by type
    export FUNCTION_APPS=$(echo "${RESOURCES}" | jq -r '.[] | select(.type=="Microsoft.Web/sites") | .name')
    export STORAGE_ACCOUNTS=$(echo "${RESOURCES}" | jq -r '.[] | select(.type=="Microsoft.Storage/storageAccounts") | .name')
    export VISION_SERVICES=$(echo "${RESOURCES}" | jq -r '.[] | select(.type=="Microsoft.CognitiveServices/accounts" and (.name | contains("vision") or .name | contains("aivision"))) | .name')
    export SEARCH_SERVICES=$(echo "${RESOURCES}" | jq -r '.[] | select(.type=="Microsoft.Search/searchServices") | .name')
    
    log_success "Resources discovered successfully"
    
    # Display found resources
    echo "Found resources:"
    echo "- Function Apps: ${FUNCTION_APPS:-none}"
    echo "- Storage Accounts: ${STORAGE_ACCOUNTS:-none}"
    echo "- AI Vision Services: ${VISION_SERVICES:-none}"
    echo "- AI Search Services: ${SEARCH_SERVICES:-none}"
}

# Function to delete search index
delete_search_index() {
    log_info "Deleting search indexes..."
    
    for search_service in ${SEARCH_SERVICES}; do
        if [[ -n "${search_service}" ]]; then
            log_info "Processing search service: ${search_service}"
            
            # Get search service admin key
            SEARCH_KEY=$(az search admin-key show \
                --service-name "${search_service}" \
                --resource-group "${RESOURCE_GROUP}" \
                --query "primaryKey" --output tsv 2>/dev/null)
            
            if [[ -n "${SEARCH_KEY}" ]]; then
                SEARCH_ENDPOINT="https://${search_service}.search.windows.net"
                
                # Delete the search index
                log_info "Deleting search index 'image-content-index' from ${search_service}..."
                
                RESPONSE=$(curl -s -X DELETE \
                    "${SEARCH_ENDPOINT}/indexes/image-content-index?api-version=2024-05-01-preview" \
                    -H "api-key: ${SEARCH_KEY}" \
                    -w "%{http_code}")
                
                HTTP_CODE=$(echo "${RESPONSE}" | tail -c 4)
                
                if [[ "${HTTP_CODE}" == "204" ]]; then
                    log_success "Search index deleted successfully from ${search_service}"
                elif [[ "${HTTP_CODE}" == "404" ]]; then
                    log_warning "Search index 'image-content-index' not found in ${search_service}"
                else
                    log_warning "Failed to delete search index from ${search_service}. HTTP Code: ${HTTP_CODE}"
                fi
            else
                log_warning "Could not retrieve admin key for search service ${search_service}"
            fi
        fi
    done
}

# Function to delete Azure Functions apps
delete_function_apps() {
    log_info "Deleting Azure Functions apps..."
    
    for function_app in ${FUNCTION_APPS}; do
        if [[ -n "${function_app}" ]]; then
            if confirm_deletion "Function App '${function_app}'"; then
                log_info "Deleting Function App: ${function_app}"
                
                if az functionapp delete \
                    --name "${function_app}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --yes >/dev/null 2>&1; then
                    log_success "Function App '${function_app}' deleted successfully"
                else
                    log_warning "Failed to delete Function App '${function_app}' or it was already deleted"
                fi
            else
                log_info "Skipping deletion of Function App '${function_app}'"
            fi
        fi
    done
}

# Function to delete AI Search services
delete_search_services() {
    log_info "Deleting AI Search services..."
    
    for search_service in ${SEARCH_SERVICES}; do
        if [[ -n "${search_service}" ]]; then
            if confirm_deletion "AI Search Service '${search_service}'"; then
                log_info "Deleting AI Search Service: ${search_service}"
                
                if az search service delete \
                    --name "${search_service}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --yes >/dev/null 2>&1; then
                    log_success "AI Search Service '${search_service}' deleted successfully"
                else
                    log_warning "Failed to delete AI Search Service '${search_service}' or it was already deleted"
                fi
            else
                log_info "Skipping deletion of AI Search Service '${search_service}'"
            fi
        fi
    done
}

# Function to delete AI Vision services
delete_vision_services() {
    log_info "Deleting AI Vision services..."
    
    for vision_service in ${VISION_SERVICES}; do
        if [[ -n "${vision_service}" ]]; then
            if confirm_deletion "AI Vision Service '${vision_service}'"; then
                log_info "Deleting AI Vision Service: ${vision_service}"
                
                if az cognitiveservices account delete \
                    --name "${vision_service}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --yes >/dev/null 2>&1; then
                    log_success "AI Vision Service '${vision_service}' deleted successfully"
                else
                    log_warning "Failed to delete AI Vision Service '${vision_service}' or it was already deleted"
                fi
            else
                log_info "Skipping deletion of AI Vision Service '${vision_service}'"
            fi
        fi
    done
}

# Function to delete storage accounts
delete_storage_accounts() {
    log_info "Deleting storage accounts..."
    
    for storage_account in ${STORAGE_ACCOUNTS}; do
        if [[ -n "${storage_account}" ]]; then
            if confirm_deletion "Storage Account '${storage_account}' and all its data"; then
                log_info "Deleting Storage Account: ${storage_account}"
                
                if az storage account delete \
                    --name "${storage_account}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --yes >/dev/null 2>&1; then
                    log_success "Storage Account '${storage_account}' deleted successfully"
                else
                    log_warning "Failed to delete Storage Account '${storage_account}' or it was already deleted"
                fi
            else
                log_info "Skipping deletion of Storage Account '${storage_account}'"
            fi
        fi
    done
}

# Function to delete resource group
delete_resource_group() {
    log_info "Resource group deletion options..."
    
    if confirm_deletion "the entire Resource Group '${RESOURCE_GROUP}' and ALL its contents"; then
        log_info "Deleting Resource Group: ${RESOURCE_GROUP}"
        
        if az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait >/dev/null 2>&1; then
            log_success "Resource Group '${RESOURCE_GROUP}' deletion initiated (running in background)"
            log_info "You can check the deletion status with: az group show --name ${RESOURCE_GROUP}"
        else
            log_warning "Failed to delete Resource Group '${RESOURCE_GROUP}' or it was already deleted"
        fi
    else
        log_info "Skipping deletion of Resource Group '${RESOURCE_GROUP}'"
    fi
}

# Function to clean up local files
clean_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove search interface file if it exists
    if [[ -f "search-interface.html" ]]; then
        if confirm_deletion "local search interface file 'search-interface.html'"; then
            rm -f "search-interface.html"
            log_success "Local file 'search-interface.html' deleted"
        else
            log_info "Keeping local file 'search-interface.html'"
        fi
    fi
    
    # Remove any temporary files
    if [[ -f "image-processor.zip" ]]; then
        rm -f "image-processor.zip"
        log_success "Temporary file 'image-processor.zip' deleted"
    fi
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        # List remaining resources
        REMAINING_RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{name:name,type:type}" --output json)
        REMAINING_COUNT=$(echo "${REMAINING_RESOURCES}" | jq length)
        
        if [[ ${REMAINING_COUNT} -gt 0 ]]; then
            log_warning "Resource group '${RESOURCE_GROUP}' still contains ${REMAINING_COUNT} resource(s):"
            echo "${REMAINING_RESOURCES}" | jq -r '.[] | "- \(.name) (\(.type))"'
        else
            log_success "Resource group '${RESOURCE_GROUP}' is now empty"
        fi
    else
        log_success "Resource group '${RESOURCE_GROUP}' has been deleted"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "===================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "===================="
    echo ""
    log_success "✅ Cleanup process completed!"
    echo ""
    log_info "What was cleaned up:"
    echo "- Search indexes and AI Search services"
    echo "- Azure Functions apps and code"
    echo "- AI Vision services"
    echo "- Storage accounts and containers"
    echo "- Local files (if confirmed)"
    echo ""
    log_info "Note: Some resources may take a few minutes to be fully deleted."
    log_info "You can verify the deletion status in the Azure portal."
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [RESOURCE_GROUP] [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --force     Force deletion without confirmation prompts"
    echo "  -h, --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Delete from default resource group"
    echo "  $0 my-resource-group                  # Delete from specific resource group"
    echo "  $0 my-resource-group --force          # Force delete without prompts"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP   Default resource group name (default: rg-image-discovery-demo)"
    echo "  FORCE_DELETE     Set to 'true' to skip confirmation prompts"
}

# Main cleanup function
main() {
    # Parse command line arguments
    RESOURCE_GROUP_ARG=""
    FORCE_DELETE="false"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_DELETE="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "${RESOURCE_GROUP_ARG}" ]]; then
                    RESOURCE_GROUP_ARG="$1"
                else
                    log_error "Multiple resource groups specified: '${RESOURCE_GROUP_ARG}' and '$1'"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    export FORCE_DELETE
    
    log_info "Starting Azure Intelligent Image Content Discovery cleanup..."
    
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation prompts"
    fi
    
    # Run cleanup steps
    check_prerequisites
    set_environment_variables "${RESOURCE_GROUP_ARG}"
    
    if ! discover_resources; then
        log_info "No resources to clean up."
        exit 0
    fi
    
    # Delete resources in reverse order of creation
    delete_search_index
    delete_function_apps
    delete_search_services
    delete_vision_services
    delete_storage_accounts
    clean_local_files
    
    # Optionally delete the resource group
    delete_resource_group
    
    verify_deletion
    display_cleanup_summary
}

# Run main function with all arguments
main "$@"