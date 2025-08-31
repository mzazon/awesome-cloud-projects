#!/bin/bash

# Destroy script for Model Improvement Pipeline with Stored Completions and Prompt Flow
# This script safely removes all Azure resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load deployment configuration
load_deployment_config() {
    log_info "Loading deployment configuration..."
    
    # Check if deployment summary exists
    if [[ -f "./pipeline-config/deployment_summary.json" ]]; then
        log_info "Found deployment configuration file"
        
        # Extract resource information from deployment summary
        export RESOURCE_GROUP=$(jq -r '.deployment_info.resource_group' ./pipeline-config/deployment_summary.json 2>/dev/null || echo "")
        export SUBSCRIPTION_ID=$(jq -r '.deployment_info.subscription_id' ./pipeline-config/deployment_summary.json 2>/dev/null || echo "")
        export LOCATION=$(jq -r '.deployment_info.location' ./pipeline-config/deployment_summary.json 2>/dev/null || echo "")
        export RANDOM_SUFFIX=$(jq -r '.deployment_info.random_suffix' ./pipeline-config/deployment_summary.json 2>/dev/null || echo "")
        
        export OPENAI_SERVICE_NAME=$(jq -r '.resources.openai_service' ./pipeline-config/deployment_summary.json 2>/dev/null || echo "")
        export FUNCTION_APP_NAME=$(jq -r '.resources.function_app' ./pipeline-config/deployment_summary.json 2>/dev/null || echo "")
        export STORAGE_ACCOUNT_NAME=$(jq -r '.resources.storage_account' ./pipeline-config/deployment_summary.json 2>/dev/null || echo "")
        export ML_WORKSPACE_NAME=$(jq -r '.resources.ml_workspace' ./pipeline-config/deployment_summary.json 2>/dev/null || echo "")
        export LOG_ANALYTICS_WORKSPACE=$(jq -r '.resources.log_analytics' ./pipeline-config/deployment_summary.json 2>/dev/null || echo "")
        
        log_success "Configuration loaded successfully"
        log_info "Resource Group: ${RESOURCE_GROUP}"
        log_info "Random Suffix: ${RANDOM_SUFFIX}"
    else
        log_warning "Deployment configuration not found. Using interactive mode."
        prompt_for_resource_group
    fi
}

# Function to prompt for resource group if config not found
prompt_for_resource_group() {
    log_info "Please provide the resource group name to delete"
    echo -e "${YELLOW}Available resource groups:${NC}"
    
    # List resource groups that might be related to this recipe
    az group list --query "[?contains(name, 'model-pipeline')].{Name:name, Location:location}" --output table 2>/dev/null || log_warning "Could not list resource groups"
    
    echo
    read -p "Enter the resource group name to delete: " RESOURCE_GROUP
    
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        log_error "Resource group name cannot be empty"
        exit 1
    fi
    
    # Verify the resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_error "Resource group '${RESOURCE_GROUP}' does not exist"
        exit 1
    fi
    
    log_success "Resource group '${RESOURCE_GROUP}' found"
}

# Function to display resources to be deleted
display_resources_to_delete() {
    log_info "Scanning for resources to delete..."
    
    # Get list of resources in the resource group
    local resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" --output table 2>/dev/null)
    
    if [[ -n "${resources}" ]]; then
        echo
        echo "=========================================="
        echo "      RESOURCES TO BE DELETED"
        echo "=========================================="
        echo
        echo "${resources}"
        echo
        
        # Get resource count
        local resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length([])" --output tsv 2>/dev/null || echo "0")
        log_warning "Total resources to delete: ${resource_count}"
    else
        log_info "No resources found in resource group '${RESOURCE_GROUP}'"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    echo
    echo "=========================================="
    echo "           DELETION CONFIRMATION"
    echo "=========================================="
    echo
    log_warning "This action will PERMANENTLY DELETE all resources in:"
    echo "   Resource Group: ${RESOURCE_GROUP}"
    echo "   Subscription: ${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    # Default to 'no' for safety
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    case "${confirmation}" in
        yes|YES|y|Y)
            log_info "Deletion confirmed. Proceeding..."
            ;;
        *)
            log_info "Deletion cancelled by user"
            exit 0
            ;;
    esac
}

# Function to delete specific resources with error handling
delete_individual_resources() {
    log_info "Attempting to delete individual resources for better control..."
    
    # Delete Function App first (to avoid dependencies)
    if [[ -n "${FUNCTION_APP_NAME:-}" ]]; then
        log_info "Deleting Function App: ${FUNCTION_APP_NAME}"
        if az functionapp delete --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" --slot production 2>/dev/null; then
            log_success "Function App deleted successfully"
        else
            log_warning "Function App deletion encountered issues or resource not found"
        fi
    fi
    
    # Delete ML workspace deployments first
    if [[ -n "${ML_WORKSPACE_NAME:-}" ]]; then
        log_info "Deleting ML workspace: ${ML_WORKSPACE_NAME}"
        if az ml workspace delete --name "${ML_WORKSPACE_NAME}" --resource-group "${RESOURCE_GROUP}" --yes --no-wait 2>/dev/null; then
            log_success "ML workspace deletion initiated"
        else
            log_warning "ML workspace deletion encountered issues or resource not found"
        fi
    fi
    
    # Delete OpenAI model deployments first, then the service
    if [[ -n "${OPENAI_SERVICE_NAME:-}" ]]; then
        log_info "Deleting OpenAI model deployments..."
        
        # Try to delete GPT-4o deployment
        az cognitiveservices account deployment delete \
            --name "${OPENAI_SERVICE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --deployment-name gpt-4o-deployment 2>/dev/null || log_warning "GPT-4o deployment deletion encountered issues"
        
        log_info "Deleting OpenAI service: ${OPENAI_SERVICE_NAME}"
        if az cognitiveservices account delete --name "${OPENAI_SERVICE_NAME}" --resource-group "${RESOURCE_GROUP}" 2>/dev/null; then
            log_success "OpenAI service deleted successfully"
        else
            log_warning "OpenAI service deletion encountered issues or resource not found"
        fi
    fi
    
    # Delete Storage Account
    if [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]]; then
        log_info "Deleting Storage Account: ${STORAGE_ACCOUNT_NAME}"
        if az storage account delete --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" --yes 2>/dev/null; then
            log_success "Storage Account deleted successfully"
        else
            log_warning "Storage Account deletion encountered issues or resource not found"
        fi
    fi
    
    # Delete Log Analytics workspace
    if [[ -n "${LOG_ANALYTICS_WORKSPACE:-}" ]]; then
        log_info "Deleting Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE}"
        if az monitor log-analytics workspace delete --workspace-name "${LOG_ANALYTICS_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" --yes --no-wait 2>/dev/null; then
            log_success "Log Analytics workspace deletion initiated"
        else
            log_warning "Log Analytics workspace deletion encountered issues or resource not found"
        fi
    fi
    
    log_info "Individual resource deletion completed"
}

# Function to delete the entire resource group
delete_resource_group() {
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    log_info "This may take several minutes..."
    
    # Delete resource group with no-wait to avoid timeout issues
    if az group delete --name "${RESOURCE_GROUP}" --yes --no-wait; then
        log_success "Resource group deletion initiated successfully"
        log_info "Deletion is running in the background and may take 5-10 minutes to complete"
        return 0
    else
        log_error "Failed to initiate resource group deletion"
        return 1
    fi
}

# Function to verify deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_warning "Resource group still exists (deletion may be in progress)"
        
        # Check remaining resources
        local remaining_resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length([])" --output tsv 2>/dev/null || echo "0")
        
        if [[ "${remaining_resources}" -gt 0 ]]; then
            log_warning "${remaining_resources} resources still remain in the resource group"
            log_info "Deletion may still be in progress. Check Azure Portal for status."
        else
            log_success "All resources have been deleted from the resource group"
        fi
    else
        log_success "Resource group has been completely deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    # Remove configuration directory if it exists
    if [[ -d "./pipeline-config" ]]; then
        log_info "Removing local configuration directory"
        rm -rf ./pipeline-config
        log_success "Local configuration files removed"
    fi
    
    # Remove any temporary Python files
    if [[ -f "/tmp/requirements.txt" ]]; then
        rm -f /tmp/requirements.txt
    fi
    
    if [[ -f "/tmp/generate_conversations.py" ]]; then
        rm -f /tmp/generate_conversations.py
    fi
    
    log_success "Local cleanup completed"
}

# Function to display deletion summary
display_deletion_summary() {
    echo
    echo "=========================================="
    echo "         DELETION COMPLETED"
    echo "=========================================="
    echo
    log_success "Model Improvement Pipeline resources have been deleted!"
    echo
    echo "📋 Deletion Summary:"
    echo "   Resource Group: ${RESOURCE_GROUP}"
    echo "   Status: Deletion initiated"
    echo
    echo "⏱️  Note: Complete deletion may take up to 10 minutes"
    echo "🔗 Monitor progress at: https://portal.azure.com/#@/resource/subscriptions/${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}/resourceGroups/${RESOURCE_GROUP}"
    echo
    echo "✅ Local configuration files have been cleaned up"
    echo
    echo "💡 Tip: You can verify complete deletion by checking the Azure Portal"
    echo "    or by running: az group show --name '${RESOURCE_GROUP}'"
    echo
}

# Function to handle partial cleanup on error
handle_partial_cleanup() {
    log_error "Deletion process encountered errors"
    echo
    echo "=========================================="
    echo "         PARTIAL CLEANUP GUIDE"
    echo "=========================================="
    echo
    log_info "Some resources may still exist. To manually clean up:"
    echo
    echo "1. Check remaining resources:"
    echo "   az resource list --resource-group '${RESOURCE_GROUP}' --output table"
    echo
    echo "2. Delete specific resources manually:"
    echo "   az resource delete --ids <resource-id>"
    echo
    echo "3. Force delete the resource group:"
    echo "   az group delete --name '${RESOURCE_GROUP}' --yes --no-wait"
    echo
    echo "4. Monitor deletion status:"
    echo "   az group show --name '${RESOURCE_GROUP}'"
    echo
    log_warning "Please verify all resources are deleted to avoid ongoing charges"
}

# Main deletion function
main() {
    echo "=========================================="
    echo "  Model Improvement Pipeline Cleanup"
    echo "=========================================="
    echo
    
    # Check if running in list-only mode
    if [[ "${1:-}" == "--list" ]]; then
        log_info "Listing resources that would be deleted..."
        check_prerequisites
        load_deployment_config
        display_resources_to_delete
        exit 0
    fi
    
    # Check if running in force mode (skip confirmation)
    local force_mode=false
    if [[ "${1:-}" == "--force" ]]; then
        force_mode=true
        log_warning "Running in force mode - skipping confirmation"
    fi
    
    # Run deletion process
    check_prerequisites
    load_deployment_config
    display_resources_to_delete
    
    if [[ "${force_mode}" != true ]]; then
        confirm_deletion
    fi
    
    # Attempt individual resource deletion first for better control
    delete_individual_resources
    
    # Wait a moment for individual deletions to process
    log_info "Waiting for individual resource deletions to process..."
    sleep 10
    
    # Delete the entire resource group
    if delete_resource_group; then
        # Clean up local files
        cleanup_local_files
        
        # Wait a moment before verification
        sleep 5
        verify_deletion
        display_deletion_summary
    else
        handle_partial_cleanup
        exit 1
    fi
}

# Handle script interruption
trap 'log_error "Deletion interrupted. Some resources may still exist."; exit 1' INT TERM

# Check if jq is available for JSON parsing (optional but recommended)
if ! command -v jq &> /dev/null; then
    log_warning "jq not found. JSON parsing will be limited."
    log_info "For better experience, install jq: apt-get install jq (Ubuntu) or brew install jq (macOS)"
fi

# Run main function with all arguments
main "$@"