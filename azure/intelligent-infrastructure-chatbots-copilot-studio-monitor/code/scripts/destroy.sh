#!/bin/bash

# =============================================================================
# AZURE INFRASTRUCTURE CHATBOT CLEANUP SCRIPT
# =============================================================================
# This script removes all infrastructure created for the intelligent 
# infrastructure chatbots with Azure Copilot Studio and Azure Monitor
#
# Prerequisites:
# - Azure CLI v2.50.0 or later
# - Valid Azure subscription with appropriate permissions
# - Bash shell environment
# =============================================================================

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/azure-chatbot-destroy-$(date +%Y%m%d-%H%M%S).log"
readonly DEPLOYMENT_STATE_FILE="/tmp/azure-chatbot-deployment-state.json"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
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
cleanup_on_error() {
    log_error "Cleanup failed. Check logs at: ${LOG_FILE}"
    log_error "Some resources may still exist and require manual cleanup"
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites checking
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI v2.50.0 or later."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: ${az_version}"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ ! -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        log_warning "Deployment state file not found: ${DEPLOYMENT_STATE_FILE}"
        log_warning "Resource names will need to be provided manually or discovered"
        return 1
    fi
    
    # Parse deployment state JSON
    if command -v jq &> /dev/null; then
        export RESOURCE_GROUP=$(jq -r '.resource_group' "${DEPLOYMENT_STATE_FILE}")
        export LOCATION=$(jq -r '.location' "${DEPLOYMENT_STATE_FILE}")
        export SUBSCRIPTION_ID=$(jq -r '.subscription_id' "${DEPLOYMENT_STATE_FILE}")
        export FUNCTION_APP_NAME=$(jq -r '.function_app_name' "${DEPLOYMENT_STATE_FILE}")
        export STORAGE_ACCOUNT_NAME=$(jq -r '.storage_account_name' "${DEPLOYMENT_STATE_FILE}")
        export LOG_ANALYTICS_WORKSPACE=$(jq -r '.log_analytics_workspace' "${DEPLOYMENT_STATE_FILE}")
        export APP_INSIGHTS_NAME=$(jq -r '.app_insights_name' "${DEPLOYMENT_STATE_FILE}")
        export RANDOM_SUFFIX=$(jq -r '.random_suffix' "${DEPLOYMENT_STATE_FILE}")
    else
        # Fallback parsing without jq
        export RESOURCE_GROUP=$(grep '"resource_group"' "${DEPLOYMENT_STATE_FILE}" | cut -d'"' -f4)
        export LOCATION=$(grep '"location"' "${DEPLOYMENT_STATE_FILE}" | cut -d'"' -f4)
        export SUBSCRIPTION_ID=$(grep '"subscription_id"' "${DEPLOYMENT_STATE_FILE}" | cut -d'"' -f4)
        export FUNCTION_APP_NAME=$(grep '"function_app_name"' "${DEPLOYMENT_STATE_FILE}" | cut -d'"' -f4)
        export STORAGE_ACCOUNT_NAME=$(grep '"storage_account_name"' "${DEPLOYMENT_STATE_FILE}" | cut -d'"' -f4)
        export LOG_ANALYTICS_WORKSPACE=$(grep '"log_analytics_workspace"' "${DEPLOYMENT_STATE_FILE}" | cut -d'"' -f4)
        export APP_INSIGHTS_NAME=$(grep '"app_insights_name"' "${DEPLOYMENT_STATE_FILE}" | cut -d'"' -f4)
        export RANDOM_SUFFIX=$(grep '"random_suffix"' "${DEPLOYMENT_STATE_FILE}" | cut -d'"' -f4)
    fi
    
    log_info "Loaded deployment state:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  Function App: ${FUNCTION_APP_NAME}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
    log_info "  Log Analytics: ${LOG_ANALYTICS_WORKSPACE}"
    log_info "  App Insights: ${APP_INSIGHTS_NAME}"
    
    log_success "Deployment state loaded successfully"
    return 0
}

# Manual configuration setup
setup_manual_configuration() {
    log_info "Setting up manual configuration..."
    
    # Prompt for resource group name if not provided
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        echo ""
        echo "Please provide the resource group name to clean up:"
        read -r -p "Resource Group Name: " RESOURCE_GROUP
        
        if [[ -z "${RESOURCE_GROUP}" ]]; then
            log_error "Resource group name is required"
            exit 1
        fi
    fi
    
    export RESOURCE_GROUP
    
    log_info "Manual configuration:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    
    log_success "Manual configuration setup completed"
}

# Discover resources in resource group
discover_resources() {
    log_info "Discovering resources in resource group..."
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} does not exist"
        return 1
    fi
    
    # List all resources in the resource group
    local resources
    resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query '[].{name:name,type:type}' -o tsv 2>/dev/null || echo "")
    
    if [[ -z "${resources}" ]]; then
        log_warning "No resources found in resource group ${RESOURCE_GROUP}"
        return 1
    fi
    
    log_info "Found resources:"
    echo "${resources}" | while read -r name type; do
        log_info "  ${name} (${type})"
    done
    
    log_success "Resource discovery completed"
    return 0
}

# Delete Function App
delete_function_app() {
    if [[ -n "${FUNCTION_APP_NAME:-}" ]]; then
        log_info "Deleting Function App: ${FUNCTION_APP_NAME}..."
        
        if az functionapp show --resource-group "${RESOURCE_GROUP}" --name "${FUNCTION_APP_NAME}" &> /dev/null; then
            az functionapp delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${FUNCTION_APP_NAME}" \
                --output none
            
            log_success "Function App deleted: ${FUNCTION_APP_NAME}"
        else
            log_warning "Function App ${FUNCTION_APP_NAME} not found"
        fi
    else
        log_info "Attempting to find and delete Function Apps..."
        local function_apps
        function_apps=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query '[].name' -o tsv 2>/dev/null || echo "")
        
        if [[ -n "${function_apps}" ]]; then
            while read -r app_name; do
                if [[ -n "${app_name}" ]]; then
                    log_info "Deleting Function App: ${app_name}..."
                    az functionapp delete \
                        --resource-group "${RESOURCE_GROUP}" \
                        --name "${app_name}" \
                        --output none
                    log_success "Function App deleted: ${app_name}"
                fi
            done <<< "${function_apps}"
        else
            log_warning "No Function Apps found in resource group"
        fi
    fi
}

# Delete Application Insights
delete_application_insights() {
    if [[ -n "${APP_INSIGHTS_NAME:-}" ]]; then
        log_info "Deleting Application Insights: ${APP_INSIGHTS_NAME}..."
        
        if az monitor app-insights component show --app "${APP_INSIGHTS_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az monitor app-insights component delete \
                --app "${APP_INSIGHTS_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output none
            
            log_success "Application Insights deleted: ${APP_INSIGHTS_NAME}"
        else
            log_warning "Application Insights ${APP_INSIGHTS_NAME} not found"
        fi
    else
        log_info "Attempting to find and delete Application Insights..."
        local insights_components
        insights_components=$(az monitor app-insights component list --resource-group "${RESOURCE_GROUP}" --query '[].name' -o tsv 2>/dev/null || echo "")
        
        if [[ -n "${insights_components}" ]]; then
            while read -r component_name; do
                if [[ -n "${component_name}" ]]; then
                    log_info "Deleting Application Insights: ${component_name}..."
                    az monitor app-insights component delete \
                        --app "${component_name}" \
                        --resource-group "${RESOURCE_GROUP}" \
                        --output none
                    log_success "Application Insights deleted: ${component_name}"
                fi
            done <<< "${insights_components}"
        else
            log_warning "No Application Insights components found in resource group"
        fi
    fi
}

# Delete Log Analytics workspace
delete_log_analytics_workspace() {
    if [[ -n "${LOG_ANALYTICS_WORKSPACE:-}" ]]; then
        log_info "Deleting Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE}..."
        
        if az monitor log-analytics workspace show --resource-group "${RESOURCE_GROUP}" --workspace-name "${LOG_ANALYTICS_WORKSPACE}" &> /dev/null; then
            az monitor log-analytics workspace delete \
                --resource-group "${RESOURCE_GROUP}" \
                --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
                --force true \
                --output none
            
            log_success "Log Analytics workspace deleted: ${LOG_ANALYTICS_WORKSPACE}"
        else
            log_warning "Log Analytics workspace ${LOG_ANALYTICS_WORKSPACE} not found"
        fi
    else
        log_info "Attempting to find and delete Log Analytics workspaces..."
        local workspaces
        workspaces=$(az monitor log-analytics workspace list --resource-group "${RESOURCE_GROUP}" --query '[].name' -o tsv 2>/dev/null || echo "")
        
        if [[ -n "${workspaces}" ]]; then
            while read -r workspace_name; do
                if [[ -n "${workspace_name}" ]]; then
                    log_info "Deleting Log Analytics workspace: ${workspace_name}..."
                    az monitor log-analytics workspace delete \
                        --resource-group "${RESOURCE_GROUP}" \
                        --workspace-name "${workspace_name}" \
                        --force true \
                        --output none
                    log_success "Log Analytics workspace deleted: ${workspace_name}"
                fi
            done <<< "${workspaces}"
        else
            log_warning "No Log Analytics workspaces found in resource group"
        fi
    fi
}

# Delete Storage Account
delete_storage_account() {
    if [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]]; then
        log_info "Deleting Storage Account: ${STORAGE_ACCOUNT_NAME}..."
        
        if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az storage account delete \
                --name "${STORAGE_ACCOUNT_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            
            log_success "Storage Account deleted: ${STORAGE_ACCOUNT_NAME}"
        else
            log_warning "Storage Account ${STORAGE_ACCOUNT_NAME} not found"
        fi
    else
        log_info "Attempting to find and delete Storage Accounts..."
        local storage_accounts
        storage_accounts=$(az storage account list --resource-group "${RESOURCE_GROUP}" --query '[].name' -o tsv 2>/dev/null || echo "")
        
        if [[ -n "${storage_accounts}" ]]; then
            while read -r account_name; do
                if [[ -n "${account_name}" ]]; then
                    log_info "Deleting Storage Account: ${account_name}..."
                    az storage account delete \
                        --name "${account_name}" \
                        --resource-group "${RESOURCE_GROUP}" \
                        --yes \
                        --output none
                    log_success "Storage Account deleted: ${account_name}"
                fi
            done <<< "${storage_accounts}"
        else
            log_warning "No Storage Accounts found in resource group"
        fi
    fi
}

# Delete resource group
delete_resource_group() {
    log_info "Deleting resource group: ${RESOURCE_GROUP}..."
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} does not exist"
        return 0
    fi
    
    # Confirm deletion unless forced
    if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
        echo ""
        log_warning "This will permanently delete the resource group '${RESOURCE_GROUP}' and ALL resources within it."
        read -r -p "Are you sure you want to continue? (yes/no): " confirm
        
        if [[ "${confirm}" != "yes" ]]; then
            log_info "Resource group deletion cancelled by user"
            return 0
        fi
    fi
    
    # Delete resource group
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        --output none
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Note: Deletion may take several minutes to complete"
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove deployment state file
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        rm -f "${DEPLOYMENT_STATE_FILE}"
        log_success "Deployment state file removed"
    fi
    
    # Remove any temporary function code directories
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local temp_dir="/tmp/chatbot-functions-${RANDOM_SUFFIX}"
        if [[ -d "${temp_dir}" ]]; then
            rm -rf "${temp_dir}"
            log_success "Temporary function directory removed"
        fi
    fi
    
    # Find and remove any orphaned chatbot function directories
    find /tmp -name "chatbot-functions-*" -type d -mtime +1 -exec rm -rf {} \; 2>/dev/null || true
    
    log_success "Temporary files cleaned up"
}

# Validate cleanup
validate_cleanup() {
    log_info "Validating cleanup..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} still exists (deletion may be in progress)"
        log_info "You can check deletion status with: az group show --name ${RESOURCE_GROUP}"
        return 1
    else
        log_success "Resource group ${RESOURCE_GROUP} has been deleted"
        return 0
    fi
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Azure infrastructure for intelligent infrastructure chatbots.

OPTIONS:
    -h, --help                Show this help message
    -r, --resource-group RG   Specify resource group to delete
    -f, --force              Skip confirmation prompts
    -i, --individual         Delete resources individually (not entire resource group)
    -v, --verbose            Enable verbose logging
    --dry-run               Show what would be deleted without actually deleting

EXAMPLES:
    $0                                    Clean up using deployment state file
    $0 -r rg-chatbot-infrastructure-abc   Clean up specific resource group
    $0 -f                                Force cleanup without confirmation
    $0 -i                                Delete individual resources only
    $0 --dry-run                         Show what would be deleted

SAFETY FEATURES:
    - Requires confirmation before deleting resources (unless --force is used)
    - Validates deployment state before cleanup
    - Provides detailed logging of all operations
    - Supports dry-run mode to preview actions

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -r|--resource-group)
                if [[ -n $2 && $2 != -* ]]; then
                    export RESOURCE_GROUP="$2"
                    shift 2
                else
                    log_error "Resource group requires a value"
                    exit 1
                fi
                ;;
            -f|--force)
                readonly FORCE_DELETE=true
                shift
                ;;
            -i|--individual)
                readonly INDIVIDUAL_DELETE=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            --dry-run)
                readonly DRY_RUN=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Dry run mode
dry_run() {
    log_info "DRY RUN MODE - No resources will be deleted"
    echo ""
    
    if load_deployment_state; then
        log_info "Would delete resources based on deployment state:"
        log_info "  Resource Group: ${RESOURCE_GROUP}"
        log_info "  Function App: ${FUNCTION_APP_NAME}"
        log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
        log_info "  Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}"
        log_info "  Application Insights: ${APP_INSIGHTS_NAME}"
    else
        if [[ -n "${RESOURCE_GROUP:-}" ]]; then
            log_info "Would discover and delete all resources in: ${RESOURCE_GROUP}"
            discover_resources || true
        else
            log_info "Would prompt for resource group name and delete all resources"
        fi
    fi
    
    echo ""
    log_info "Would also clean up temporary files and validate deletion"
    log_success "Dry run completed"
}

# Main execution function
main() {
    echo "=== Azure Infrastructure ChatBot Cleanup ==="
    echo "Starting cleanup at $(date)"
    echo ""
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check if this is a dry run
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        dry_run
        exit 0
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Try to load deployment state, fallback to manual configuration
    if ! load_deployment_state; then
        setup_manual_configuration
    fi
    
    # Discover resources if we don't have specific names
    discover_resources || true
    
    # Delete resources individually or entire resource group
    if [[ "${INDIVIDUAL_DELETE:-false}" == "true" ]]; then
        log_info "Deleting resources individually..."
        delete_function_app
        delete_application_insights
        delete_log_analytics_workspace
        delete_storage_account
        
        # Ask if user wants to delete the empty resource group
        if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
            echo ""
            read -r -p "Delete the now-empty resource group '${RESOURCE_GROUP}'? (yes/no): " confirm
            if [[ "${confirm}" == "yes" ]]; then
                delete_resource_group
            fi
        else
            delete_resource_group
        fi
    else
        log_info "Deleting entire resource group (includes all resources)..."
        delete_resource_group
    fi
    
    # Clean up temporary files
    cleanup_temp_files
    
    # Validate cleanup (only for individual deletion)
    if [[ "${INDIVIDUAL_DELETE:-false}" == "true" ]]; then
        validate_cleanup || true
    fi
    
    echo ""
    log_success "=== CLEANUP COMPLETED ==="
    echo ""
    log_info "Summary:"
    log_info "  Target Resource Group: ${RESOURCE_GROUP}"
    log_info "  Cleanup Method: ${INDIVIDUAL_DELETE:-false == "true" && echo "Individual resources" || echo "Entire resource group"}"
    log_info "  Cleanup logs saved to: ${LOG_FILE}"
    echo ""
    
    if [[ "${INDIVIDUAL_DELETE:-false}" != "true" ]]; then
        log_info "Note: Resource group deletion is asynchronous and may take several minutes."
        log_info "Check status with: az group show --name ${RESOURCE_GROUP}"
    fi
    
    log_success "Cleanup completed successfully at $(date)"
}

# Execute main function with all arguments
main "$@"