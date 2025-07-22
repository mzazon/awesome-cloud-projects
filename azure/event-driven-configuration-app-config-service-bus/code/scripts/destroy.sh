#!/bin/bash

# Destroy script for Event-Driven Configuration Management with Azure App Configuration and Service Bus
# This script safely removes all resources created by the deploy.sh script

set -euo pipefail

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

# Error handling
handle_error() {
    log_error "An error occurred on line $1. Continuing with cleanup..."
    # Don't exit on error during cleanup - continue removing resources
}

trap 'handle_error $LINENO' ERR

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Start logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

log_info "Starting cleanup at $(date)"
log_info "Log file: ${LOG_FILE}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI to proceed with cleanup."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites met"
}

# Function to load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        source "${DEPLOYMENT_STATE_FILE}"
        log_success "Deployment state loaded from ${DEPLOYMENT_STATE_FILE}"
        log_info "Found deployment from: ${DEPLOYMENT_TIMESTAMP:-Unknown}"
    else
        log_warning "Deployment state file not found: ${DEPLOYMENT_STATE_FILE}"
        log_warning "You will need to provide resource names manually"
        return 1
    fi
}

# Function to prompt for manual input if state file is missing
prompt_manual_input() {
    log_info "Deployment state not found. Please provide resource information manually."
    
    read -p "Resource Group name: " RESOURCE_GROUP
    read -p "Subscription ID: " SUBSCRIPTION_ID
    read -p "App Configuration name: " APP_CONFIG_NAME
    read -p "Service Bus namespace: " SERVICE_BUS_NAMESPACE
    read -p "Service Bus topic (default: configuration-changes): " SERVICE_BUS_TOPIC
    SERVICE_BUS_TOPIC=${SERVICE_BUS_TOPIC:-configuration-changes}
    read -p "Function App name: " FUNCTION_APP_NAME
    read -p "Storage Account name: " STORAGE_ACCOUNT_NAME
    read -p "Logic App name: " LOGIC_APP_NAME
    
    export RESOURCE_GROUP SUBSCRIPTION_ID APP_CONFIG_NAME SERVICE_BUS_NAMESPACE 
    export SERVICE_BUS_TOPIC FUNCTION_APP_NAME STORAGE_ACCOUNT_NAME LOGIC_APP_NAME
    
    log_info "Manual input completed"
}

# Function to confirm deletion
confirm_deletion() {
    log_warning "This will permanently delete the following resources:"
    echo ""
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "App Configuration: ${APP_CONFIG_NAME}"
    echo "Service Bus Namespace: ${SERVICE_BUS_NAMESPACE}"
    echo "Function App: ${FUNCTION_APP_NAME}"
    echo "Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "Logic App: ${LOGIC_APP_NAME}"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Deletion confirmed. Proceeding with cleanup..."
}

# Function to safely delete a resource with error handling
safe_delete() {
    local resource_type="$1"
    local delete_command="$2"
    local resource_name="$3"
    
    log_info "Deleting ${resource_type}: ${resource_name}"
    
    if eval "${delete_command}" 2>/dev/null; then
        log_success "${resource_type} deleted: ${resource_name}"
    else
        log_warning "Failed to delete ${resource_type}: ${resource_name} (may not exist or already deleted)"
    fi
}

# Function to check if resource exists
resource_exists() {
    local check_command="$1"
    eval "${check_command}" &> /dev/null
}

# Function to delete Event Grid subscription
delete_event_grid_subscription() {
    local subscription_name="${EVENT_GRID_SUBSCRIPTION:-config-changes-to-servicebus}"
    
    log_info "Checking for Event Grid subscription: ${subscription_name}"
    
    local check_cmd="az eventgrid event-subscription show \
        --name '${subscription_name}' \
        --source-resource-id '/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.AppConfiguration/configurationStores/${APP_CONFIG_NAME}'"
    
    if resource_exists "${check_cmd}"; then
        local delete_cmd="az eventgrid event-subscription delete \
            --name '${subscription_name}' \
            --source-resource-id '/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.AppConfiguration/configurationStores/${APP_CONFIG_NAME}'"
        
        safe_delete "Event Grid subscription" "${delete_cmd}" "${subscription_name}"
        
        # Wait for deletion to complete
        log_info "Waiting for Event Grid subscription deletion to complete..."
        sleep 30
    else
        log_warning "Event Grid subscription ${subscription_name} not found or already deleted"
    fi
}

# Function to delete Logic App
delete_logic_app() {
    log_info "Checking for Logic App: ${LOGIC_APP_NAME}"
    
    local check_cmd="az logic workflow show --name '${LOGIC_APP_NAME}' --resource-group '${RESOURCE_GROUP}'"
    
    if resource_exists "${check_cmd}"; then
        local delete_cmd="az logic workflow delete \
            --name '${LOGIC_APP_NAME}' \
            --resource-group '${RESOURCE_GROUP}' \
            --yes"
        
        safe_delete "Logic App" "${delete_cmd}" "${LOGIC_APP_NAME}"
    else
        log_warning "Logic App ${LOGIC_APP_NAME} not found or already deleted"
    fi
}

# Function to delete Function App
delete_function_app() {
    log_info "Checking for Function App: ${FUNCTION_APP_NAME}"
    
    local check_cmd="az functionapp show --name '${FUNCTION_APP_NAME}' --resource-group '${RESOURCE_GROUP}'"
    
    if resource_exists "${check_cmd}"; then
        local delete_cmd="az functionapp delete \
            --name '${FUNCTION_APP_NAME}' \
            --resource-group '${RESOURCE_GROUP}'"
        
        safe_delete "Function App" "${delete_cmd}" "${FUNCTION_APP_NAME}"
    else
        log_warning "Function App ${FUNCTION_APP_NAME} not found or already deleted"
    fi
}

# Function to delete Storage Account
delete_storage_account() {
    log_info "Checking for Storage Account: ${STORAGE_ACCOUNT_NAME}"
    
    local check_cmd="az storage account show --name '${STORAGE_ACCOUNT_NAME}' --resource-group '${RESOURCE_GROUP}'"
    
    if resource_exists "${check_cmd}"; then
        local delete_cmd="az storage account delete \
            --name '${STORAGE_ACCOUNT_NAME}' \
            --resource-group '${RESOURCE_GROUP}' \
            --yes"
        
        safe_delete "Storage Account" "${delete_cmd}" "${STORAGE_ACCOUNT_NAME}"
    else
        log_warning "Storage Account ${STORAGE_ACCOUNT_NAME} not found or already deleted"
    fi
}

# Function to delete Service Bus namespace (includes topics and subscriptions)
delete_service_bus() {
    log_info "Checking for Service Bus namespace: ${SERVICE_BUS_NAMESPACE}"
    
    local check_cmd="az servicebus namespace show --name '${SERVICE_BUS_NAMESPACE}' --resource-group '${RESOURCE_GROUP}'"
    
    if resource_exists "${check_cmd}"; then
        log_info "Deleting Service Bus subscriptions first..."
        
        # Delete subscriptions individually (optional, as they'll be deleted with namespace)
        local subscriptions=("web-services" "api-services" "worker-services")
        for subscription in "${subscriptions[@]}"; do
            local sub_check_cmd="az servicebus topic subscription show \
                --name '${subscription}' \
                --topic-name '${SERVICE_BUS_TOPIC}' \
                --namespace-name '${SERVICE_BUS_NAMESPACE}' \
                --resource-group '${RESOURCE_GROUP}'"
            
            if resource_exists "${sub_check_cmd}"; then
                local sub_delete_cmd="az servicebus topic subscription delete \
                    --name '${subscription}' \
                    --topic-name '${SERVICE_BUS_TOPIC}' \
                    --namespace-name '${SERVICE_BUS_NAMESPACE}' \
                    --resource-group '${RESOURCE_GROUP}'"
                
                safe_delete "Service Bus subscription" "${sub_delete_cmd}" "${subscription}"
            fi
        done
        
        # Delete the entire namespace (this will delete topics and remaining subscriptions)
        local delete_cmd="az servicebus namespace delete \
            --name '${SERVICE_BUS_NAMESPACE}' \
            --resource-group '${RESOURCE_GROUP}'"
        
        safe_delete "Service Bus namespace" "${delete_cmd}" "${SERVICE_BUS_NAMESPACE}"
        
        # Wait for deletion to complete
        log_info "Waiting for Service Bus namespace deletion to complete..."
        sleep 60
    else
        log_warning "Service Bus namespace ${SERVICE_BUS_NAMESPACE} not found or already deleted"
    fi
}

# Function to delete App Configuration store
delete_app_configuration() {
    log_info "Checking for App Configuration store: ${APP_CONFIG_NAME}"
    
    local check_cmd="az appconfig show --name '${APP_CONFIG_NAME}' --resource-group '${RESOURCE_GROUP}'"
    
    if resource_exists "${check_cmd}"; then
        local delete_cmd="az appconfig delete \
            --name '${APP_CONFIG_NAME}' \
            --resource-group '${RESOURCE_GROUP}' \
            --yes"
        
        safe_delete "App Configuration store" "${delete_cmd}" "${APP_CONFIG_NAME}"
    else
        log_warning "App Configuration store ${APP_CONFIG_NAME} not found or already deleted"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log_info "Checking for Resource Group: ${RESOURCE_GROUP}"
    
    local check_cmd="az group show --name '${RESOURCE_GROUP}'"
    
    if resource_exists "${check_cmd}"; then
        log_warning "This will delete the entire resource group and ALL contained resources"
        read -p "Delete resource group ${RESOURCE_GROUP}? (yes/no): " rg_confirmation
        
        if [[ "${rg_confirmation}" == "yes" ]]; then
            local delete_cmd="az group delete \
                --name '${RESOURCE_GROUP}' \
                --yes \
                --no-wait"
            
            safe_delete "Resource Group" "${delete_cmd}" "${RESOURCE_GROUP}"
            
            log_info "Resource group deletion initiated. This may take several minutes to complete."
            log_info "You can check the status with: az group show --name '${RESOURCE_GROUP}'"
        else
            log_info "Resource group deletion skipped"
        fi
    else
        log_warning "Resource Group ${RESOURCE_GROUP} not found or already deleted"
    fi
}

# Function to cleanup deployment state files
cleanup_state_files() {
    log_info "Cleaning up deployment state files..."
    
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        rm -f "${DEPLOYMENT_STATE_FILE}"
        log_success "Deployment state file removed"
    fi
    
    # Clean up any temporary function code directories
    if ls /tmp/function-code-* 1> /dev/null 2>&1; then
        rm -rf /tmp/function-code-*
        log_success "Temporary function code directories cleaned up"
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_status=0
    
    # Check if resource group still exists
    if resource_exists "az group show --name '${RESOURCE_GROUP}'"; then
        log_warning "Resource group ${RESOURCE_GROUP} still exists"
        
        # List remaining resources
        log_info "Remaining resources in resource group:"
        az resource list --resource-group "${RESOURCE_GROUP}" --output table 2>/dev/null || true
        cleanup_status=1
    else
        log_success "Resource group ${RESOURCE_GROUP} successfully deleted"
    fi
    
    return ${cleanup_status}
}

# Function to display cleanup summary
display_summary() {
    log_info "Cleanup Summary:"
    echo ""
    echo "Deleted resources:"
    echo "- Event Grid subscription: ${EVENT_GRID_SUBSCRIPTION:-config-changes-to-servicebus}"
    echo "- Logic App: ${LOGIC_APP_NAME}"
    echo "- Function App: ${FUNCTION_APP_NAME}"
    echo "- Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "- Service Bus namespace: ${SERVICE_BUS_NAMESPACE}"
    echo "- App Configuration: ${APP_CONFIG_NAME}"
    echo "- Resource Group: ${RESOURCE_GROUP}"
    echo ""
    echo "Cleanup logs saved to: ${LOG_FILE}"
    echo ""
    
    if verify_cleanup; then
        log_success "All resources have been successfully cleaned up!"
        log_info "Your Azure subscription will no longer incur charges for these resources."
    else
        log_warning "Some resources may still exist. Please check the Azure portal and remove any remaining resources manually."
        log_info "You can also re-run this script to attempt cleanup again."
    fi
}

# Main cleanup function
main() {
    log_info "Starting Azure Event-Driven Configuration Management cleanup"
    
    check_prerequisites
    
    # Try to load deployment state, fallback to manual input if not found
    if ! load_deployment_state; then
        prompt_manual_input
    fi
    
    confirm_deletion
    
    # Delete resources in reverse order of creation
    # This ensures dependencies are handled properly
    delete_event_grid_subscription
    delete_logic_app
    delete_function_app
    delete_storage_account
    delete_service_bus
    delete_app_configuration
    delete_resource_group
    
    cleanup_state_files
    display_summary
    
    log_success "Cleanup completed at $(date)"
}

# Function to show help
show_help() {
    echo "Azure Event-Driven Configuration Management Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h          Show this help message"
    echo "  --force             Skip confirmation prompts (use with caution)"
    echo "  --keep-rg           Keep the resource group and only delete individual resources"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP      Override the resource group name"
    echo "  SUBSCRIPTION_ID     Override the subscription ID"
    echo ""
    echo "Examples:"
    echo "  $0                  Interactive cleanup with confirmations"
    echo "  $0 --force          Automatic cleanup without prompts"
    echo "  $0 --keep-rg        Delete resources but keep the resource group"
    echo ""
}

# Parse command line arguments
FORCE_DELETE=false
KEEP_RESOURCE_GROUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            exit 0
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --keep-rg)
            KEEP_RESOURCE_GROUP=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Override confirmation function if force delete is enabled
if [[ "${FORCE_DELETE}" == true ]]; then
    confirm_deletion() {
        log_warning "Force delete enabled - skipping confirmation"
    }
fi

# Override resource group deletion if keep-rg is enabled
if [[ "${KEEP_RESOURCE_GROUP}" == true ]]; then
    delete_resource_group() {
        log_info "Keeping resource group as requested (--keep-rg flag)"
    }
fi

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi