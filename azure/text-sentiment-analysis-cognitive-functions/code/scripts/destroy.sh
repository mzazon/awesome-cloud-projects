#!/bin/bash

# Destroy script for Text Sentiment Analysis with Cognitive Services
# This script safely removes all Azure resources created by the deployment

set -e  # Exit on any error

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

# Check if Azure CLI is installed and user is logged in
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check if user is logged in to Azure CLI
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    local deployment_file=""
    
    # Look for deployment info file in current directory and parent directories
    if [[ -f "deployment-info.txt" ]]; then
        deployment_file="deployment-info.txt"
    elif [[ -f "../deployment-info.txt" ]]; then
        deployment_file="../deployment-info.txt"
    elif [[ -f "../../deployment-info.txt" ]]; then
        deployment_file="../../deployment-info.txt"
    fi
    
    if [[ -n "${deployment_file}" ]]; then
        log_info "Found deployment info file: ${deployment_file}"
        
        # Source the deployment info file to load variables
        source "${deployment_file}"
        
        log_info "Loaded deployment information:"
        log_info "  - Resource Group: ${RESOURCE_GROUP}"
        log_info "  - Language Service: ${LANGUAGE_SERVICE_NAME}"
        log_info "  - Function App: ${FUNCTION_APP_NAME}"
        log_info "  - Storage Account: ${STORAGE_ACCOUNT_NAME}"
        
        return 0
    fi
    
    log_warning "No deployment-info.txt file found. Will prompt for resource information."
    return 1
}

# Prompt for resource information if not found in deployment file
prompt_for_resources() {
    log_info "Please provide the resource information for cleanup:"
    
    echo -n "Enter Resource Group name: "
    read -r RESOURCE_GROUP
    
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        log_error "Resource Group name is required for cleanup"
        exit 1
    fi
    
    # Set default values based on resource group pattern
    if [[ "${RESOURCE_GROUP}" =~ rg-sentiment-([a-f0-9]+) ]]; then
        local suffix="${BASH_REMATCH[1]}"
        LANGUAGE_SERVICE_NAME="lang-sentiment-${suffix}"
        FUNCTION_APP_NAME="func-sentiment-${suffix}"
        STORAGE_ACCOUNT_NAME="stsentiment${suffix}"
        
        log_info "Detected resource naming pattern, will attempt cleanup of:"
        log_info "  - Language Service: ${LANGUAGE_SERVICE_NAME}"
        log_info "  - Function App: ${FUNCTION_APP_NAME}"
        log_info "  - Storage Account: ${STORAGE_ACCOUNT_NAME}"
    fi
}

# Verify resource group exists
verify_resource_group() {
    log_info "Verifying resource group exists: ${RESOURCE_GROUP}"
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group '${RESOURCE_GROUP}' does not exist or is already deleted"
        return 1
    fi
    
    log_success "Resource group found: ${RESOURCE_GROUP}"
    return 0
}

# List resources in the resource group
list_resources() {
    log_info "Listing resources in resource group: ${RESOURCE_GROUP}"
    
    local resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" --output table 2>/dev/null)
    
    if [[ -n "${resources}" ]]; then
        echo "${resources}"
        echo ""
        
        local resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length([])" --output tsv 2>/dev/null)
        log_info "Found ${resource_count} resources to be deleted"
    else
        log_warning "No resources found in resource group or resource group doesn't exist"
    fi
}

# Get estimated costs (if available)
show_cost_warning() {
    log_warning "⚠️  IMPORTANT: This action will permanently delete all resources!"
    log_warning "⚠️  This includes:"
    log_warning "   - Azure Cognitive Services Language resource"
    log_warning "   - Azure Function App and all its functions"
    log_warning "   - Azure Storage Account and all its data"
    log_warning "   - All configuration and logs"
    log_warning ""
    log_warning "⚠️  This action cannot be undone!"
}

# Prompt for confirmation
confirm_deletion() {
    local force_delete="${1:-false}"
    
    if [[ "${force_delete}" == "true" ]]; then
        log_warning "Force delete enabled, skipping confirmation"
        return 0
    fi
    
    show_cost_warning
    
    echo ""
    echo -n "Are you sure you want to delete all resources in '${RESOURCE_GROUP}'? (Type 'yes' to confirm): "
    read -r confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    echo ""
    echo -n "Final confirmation - Type the resource group name '${RESOURCE_GROUP}' to proceed: "
    read -r final_confirmation
    
    if [[ "${final_confirmation}" != "${RESOURCE_GROUP}" ]]; then
        log_error "Resource group name does not match. Deletion cancelled for safety."
        exit 1
    fi
    
    log_info "Deletion confirmed by user"
}

# Stop Function App (to prevent new executions)
stop_function_app() {
    if [[ -n "${FUNCTION_APP_NAME}" ]]; then
        log_info "Stopping Function App: ${FUNCTION_APP_NAME}"
        
        if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az functionapp stop --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1
            log_success "Function App stopped: ${FUNCTION_APP_NAME}"
        else
            log_warning "Function App not found or already deleted: ${FUNCTION_APP_NAME}"
        fi
    fi
}

# Delete individual resources (for detailed feedback)
delete_resources_individually() {
    log_info "Deleting resources individually for better progress tracking..."
    
    # Delete Function App
    if [[ -n "${FUNCTION_APP_NAME}" ]]; then
        log_info "Deleting Function App: ${FUNCTION_APP_NAME}"
        if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az functionapp delete --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1
            log_success "Function App deleted: ${FUNCTION_APP_NAME}"
        else
            log_warning "Function App not found: ${FUNCTION_APP_NAME}"
        fi
    fi
    
    # Delete Language Service
    if [[ -n "${LANGUAGE_SERVICE_NAME}" ]]; then
        log_info "Deleting Language Service: ${LANGUAGE_SERVICE_NAME}"
        if az cognitiveservices account show --name "${LANGUAGE_SERVICE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az cognitiveservices account delete --name "${LANGUAGE_SERVICE_NAME}" --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1
            log_success "Language Service deleted: ${LANGUAGE_SERVICE_NAME}"
        else
            log_warning "Language Service not found: ${LANGUAGE_SERVICE_NAME}"
        fi
    fi
    
    # Delete Storage Account
    if [[ -n "${STORAGE_ACCOUNT_NAME}" ]]; then
        log_info "Deleting Storage Account: ${STORAGE_ACCOUNT_NAME}"
        if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az storage account delete --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" --yes > /dev/null 2>&1
            log_success "Storage Account deleted: ${STORAGE_ACCOUNT_NAME}"
        else
            log_warning "Storage Account not found: ${STORAGE_ACCOUNT_NAME}"
        fi
    fi
}

# Delete entire resource group
delete_resource_group() {
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    
    # First try to delete individual resources for better feedback
    delete_resources_individually
    
    # Then delete the resource group (this will catch any remaining resources)
    log_info "Deleting resource group and any remaining resources: ${RESOURCE_GROUP}"
    
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait > /dev/null 2>&1
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Note: Complete deletion may take several minutes to finish in the background"
}

# Verify deletion
verify_deletion() {
    log_info "Verifying resource group deletion..."
    
    # Wait a moment for the deletion to start
    sleep 5
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        local state=$(az group show --name "${RESOURCE_GROUP}" --query "properties.provisioningState" --output tsv 2>/dev/null)
        if [[ "${state}" == "Deleting" ]]; then
            log_info "Resource group is being deleted (state: ${state})"
        else
            log_warning "Resource group still exists with state: ${state}"
        fi
    else
        log_success "Resource group has been deleted: ${RESOURCE_GROUP}"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment info file if it exists
    if [[ -f "deployment-info.txt" ]]; then
        rm deployment-info.txt
        log_success "Removed deployment-info.txt"
    fi
    
    # Remove any temporary function files
    if [[ -d "sentiment-function" ]]; then
        rm -rf sentiment-function
        log_success "Removed local function directory"
    fi
    
    log_success "Local cleanup completed"
}

# Show post-deletion information
show_post_deletion_info() {
    log_success "Cleanup completed successfully!"
    log_info ""
    log_info "What was deleted:"
    log_info "  ✅ Resource Group: ${RESOURCE_GROUP}"
    if [[ -n "${LANGUAGE_SERVICE_NAME}" ]]; then
        log_info "  ✅ Language Service: ${LANGUAGE_SERVICE_NAME}"
    fi
    if [[ -n "${FUNCTION_APP_NAME}" ]]; then
        log_info "  ✅ Function App: ${FUNCTION_APP_NAME}"
    fi
    if [[ -n "${STORAGE_ACCOUNT_NAME}" ]]; then
        log_info "  ✅ Storage Account: ${STORAGE_ACCOUNT_NAME}"
    fi
    log_info ""
    log_info "💰 Cost Impact:"
    log_info "  - All billable resources have been deleted"
    log_info "  - No further charges will be incurred"
    log_info ""
    log_info "🔍 Verification:"
    log_info "  You can verify deletion in the Azure Portal:"
    log_info "  https://portal.azure.com/#blade/HubsExtension/BrowseResourceGroups"
    log_info ""
    log_info "Note: Complete deletion may take up to 10 minutes to finish in the background."
}

# Main deletion function
main() {
    log_info "Starting Azure Text Sentiment Analysis cleanup..."
    
    # Check for help flag
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h       Show this help message"
        echo "  --force          Skip confirmation prompts (use with caution!)"
        echo "  --rg NAME        Specify resource group name directly"
        echo ""
        echo "This script will delete all resources created by the deployment script:"
        echo "  - Azure Cognitive Services (Language API)"
        echo "  - Azure Functions App"
        echo "  - Azure Storage Account"
        echo "  - Resource Group and all contained resources"
        echo ""
        echo "⚠️  WARNING: This action cannot be undone!"
        echo ""
        exit 0
    fi
    
    local force_delete="false"
    local specified_rg=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force_delete="true"
                shift
                ;;
            --rg)
                specified_rg="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                log_info "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Execute cleanup steps
    check_prerequisites
    
    # Load resource information
    if [[ -n "${specified_rg}" ]]; then
        RESOURCE_GROUP="${specified_rg}"
        log_info "Using specified resource group: ${RESOURCE_GROUP}"
    elif ! load_deployment_info; then
        prompt_for_resources
    fi
    
    # Verify and proceed with deletion
    if verify_resource_group; then
        list_resources
        confirm_deletion "${force_delete}"
        stop_function_app
        delete_resource_group
        verify_deletion
        cleanup_local_files
        show_post_deletion_info
    else
        log_info "No resources to delete. Cleanup completed."
    fi
}

# Run main function with all arguments
main "$@"