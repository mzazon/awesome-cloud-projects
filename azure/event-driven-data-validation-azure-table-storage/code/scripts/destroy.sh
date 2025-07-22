#!/bin/bash

#######################################
# Azure Real-Time Data Validation Workflows Cleanup Script
# Description: Safely removes all Azure resources created for real-time data validation workflows
#######################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please log in to Azure using 'az login'"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load environment variables
load_environment_variables() {
    log "Loading environment variables..."
    
    # Check if deployment environment file exists
    if [ -f "deployment-env.sh" ]; then
        source deployment-env.sh
        log "Environment variables loaded from deployment-env.sh"
    else
        warn "deployment-env.sh not found. Please provide environment variables manually."
        
        # Prompt for required variables if not set
        if [ -z "${RESOURCE_GROUP:-}" ]; then
            read -p "Enter Resource Group name: " RESOURCE_GROUP
            export RESOURCE_GROUP
        fi
        
        if [ -z "${SUBSCRIPTION_ID:-}" ]; then
            export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        fi
    fi
    
    # Validate required environment variables
    if [ -z "${RESOURCE_GROUP:-}" ]; then
        error "RESOURCE_GROUP is required but not set"
        exit 1
    fi
    
    log "Using Resource Group: ${RESOURCE_GROUP}"
    success "Environment variables loaded"
}

# Function to confirm deletion
confirm_deletion() {
    if [ "${FORCE:-false}" = "true" ]; then
        log "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    warn "This will DELETE ALL resources in the resource group: ${RESOURCE_GROUP}"
    warn "This action cannot be undone!"
    
    read -p "Are you sure you want to proceed? (Type 'yes' to continue): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed by user"
}

# Function to check if resource group exists
check_resource_group() {
    log "Checking if resource group exists..."
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Resource group ${RESOURCE_GROUP} does not exist"
        return 1
    fi
    
    success "Resource group exists: ${RESOURCE_GROUP}"
    return 0
}

# Function to list resources in resource group
list_resources() {
    log "Listing resources in resource group..."
    
    local resource_count
    resource_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" --output tsv)
    
    if [ "$resource_count" -eq 0 ]; then
        warn "No resources found in resource group ${RESOURCE_GROUP}"
        return 0
    fi
    
    log "Found ${resource_count} resources in resource group:"
    az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name,Type:type,Location:location}" --output table
}

# Function to delete Event Grid subscriptions
delete_event_subscriptions() {
    log "Deleting Event Grid subscriptions..."
    
    # Delete function validation subscription
    if az eventgrid event-subscription show \
        --name "function-validation-subscription" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT:-}" \
        &> /dev/null; then
        
        az eventgrid event-subscription delete \
            --name "function-validation-subscription" \
            --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT:-}" \
            --output none
        
        success "Function validation subscription deleted"
    else
        warn "Function validation subscription not found or already deleted"
    fi
    
    # Delete logic app validation subscription
    if az eventgrid event-subscription show \
        --name "logicapp-validation-subscription" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC:-}" \
        &> /dev/null; then
        
        az eventgrid event-subscription delete \
            --name "logicapp-validation-subscription" \
            --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC:-}" \
            --output none
        
        success "Logic App validation subscription deleted"
    else
        warn "Logic App validation subscription not found or already deleted"
    fi
    
    success "Event Grid subscriptions cleanup completed"
}

# Function to delete Function App
delete_function_app() {
    log "Deleting Function App..."
    
    if [ -n "${FUNCTION_APP_NAME:-}" ]; then
        if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az functionapp delete \
                --name "${FUNCTION_APP_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output none
            
            success "Function App deleted: ${FUNCTION_APP_NAME}"
        else
            warn "Function App not found or already deleted: ${FUNCTION_APP_NAME:-}"
        fi
    else
        warn "Function App name not provided, skipping deletion"
    fi
}

# Function to delete Logic App
delete_logic_app() {
    log "Deleting Logic App..."
    
    if [ -n "${LOGIC_APP_NAME:-}" ]; then
        if az logic workflow show --name "${LOGIC_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az logic workflow delete \
                --name "${LOGIC_APP_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            
            success "Logic App deleted: ${LOGIC_APP_NAME}"
        else
            warn "Logic App not found or already deleted: ${LOGIC_APP_NAME:-}"
        fi
    else
        warn "Logic App name not provided, skipping deletion"
    fi
}

# Function to delete Event Grid topic
delete_event_grid_topic() {
    log "Deleting Event Grid topic..."
    
    if [ -n "${EVENT_GRID_TOPIC:-}" ]; then
        if az eventgrid topic show --name "${EVENT_GRID_TOPIC}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az eventgrid topic delete \
                --name "${EVENT_GRID_TOPIC}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output none
            
            success "Event Grid topic deleted: ${EVENT_GRID_TOPIC}"
        else
            warn "Event Grid topic not found or already deleted: ${EVENT_GRID_TOPIC:-}"
        fi
    else
        warn "Event Grid topic name not provided, skipping deletion"
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log "Deleting monitoring resources..."
    
    # Delete Application Insights
    if [ -n "${APP_INSIGHTS_NAME:-}" ]; then
        if az monitor app-insights component show --app "${APP_INSIGHTS_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az monitor app-insights component delete \
                --app "${APP_INSIGHTS_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output none
            
            success "Application Insights deleted: ${APP_INSIGHTS_NAME}"
        else
            warn "Application Insights not found or already deleted: ${APP_INSIGHTS_NAME:-}"
        fi
    else
        warn "Application Insights name not provided, skipping deletion"
    fi
    
    # Delete Log Analytics workspace
    if [ -n "${LOG_ANALYTICS_WORKSPACE:-}" ]; then
        if az monitor log-analytics workspace show --workspace-name "${LOG_ANALYTICS_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az monitor log-analytics workspace delete \
                --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            
            success "Log Analytics workspace deleted: ${LOG_ANALYTICS_WORKSPACE}"
        else
            warn "Log Analytics workspace not found or already deleted: ${LOG_ANALYTICS_WORKSPACE:-}"
        fi
    else
        warn "Log Analytics workspace name not provided, skipping deletion"
    fi
}

# Function to delete storage account
delete_storage_account() {
    log "Deleting storage account..."
    
    if [ -n "${STORAGE_ACCOUNT:-}" ]; then
        if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az storage account delete \
                --name "${STORAGE_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            
            success "Storage account deleted: ${STORAGE_ACCOUNT}"
        else
            warn "Storage account not found or already deleted: ${STORAGE_ACCOUNT:-}"
        fi
    else
        warn "Storage account name not provided, skipping deletion"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group..."
    
    if [ "${DELETE_RESOURCE_GROUP:-true}" = "true" ]; then
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            log "Deleting resource group: ${RESOURCE_GROUP}"
            log "This may take several minutes..."
            
            az group delete \
                --name "${RESOURCE_GROUP}" \
                --yes \
                --no-wait \
                --output none
            
            success "Resource group deletion initiated: ${RESOURCE_GROUP}"
            log "Resource group deletion is running in the background"
        else
            warn "Resource group not found or already deleted: ${RESOURCE_GROUP}"
        fi
    else
        log "Resource group deletion skipped (DELETE_RESOURCE_GROUP=false)"
    fi
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Resource group still exists: ${RESOURCE_GROUP}"
        
        # List remaining resources
        local remaining_count
        remaining_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" --output tsv)
        
        if [ "$remaining_count" -gt 0 ]; then
            warn "Found ${remaining_count} remaining resources:"
            az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name,Type:type}" --output table
        else
            log "No resources remaining in resource group"
        fi
    else
        success "Resource group has been deleted: ${RESOURCE_GROUP}"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [ -f "deployment-env.sh" ]; then
        if [ "${KEEP_ENV_FILE:-false}" = "true" ]; then
            log "Keeping deployment-env.sh file"
        else
            rm -f deployment-env.sh
            success "deployment-env.sh file removed"
        fi
    fi
    
    # Remove temporary files
    if [ -d "/tmp/validation-function" ]; then
        rm -rf "/tmp/validation-function"
        success "Temporary function directory removed"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "=================================================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Subscription: ${SUBSCRIPTION_ID}"
    echo "=================================================="
    echo "Resources cleaned up:"
    echo "  - Event Grid subscriptions"
    echo "  - Function App: ${FUNCTION_APP_NAME:-N/A}"
    echo "  - Logic App: ${LOGIC_APP_NAME:-N/A}"
    echo "  - Event Grid Topic: ${EVENT_GRID_TOPIC:-N/A}"
    echo "  - Application Insights: ${APP_INSIGHTS_NAME:-N/A}"
    echo "  - Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE:-N/A}"
    echo "  - Storage Account: ${STORAGE_ACCOUNT:-N/A}"
    echo "  - Resource Group: ${RESOURCE_GROUP} (if enabled)"
    echo "=================================================="
    
    if [ "${DELETE_RESOURCE_GROUP:-true}" = "true" ]; then
        log "Resource group deletion is running in the background"
        log "Use 'az group show --name ${RESOURCE_GROUP}' to check status"
    fi
}

# Function to handle cleanup with retry
cleanup_with_retry() {
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Cleanup attempt ${attempt}/${max_attempts}"
        
        if [ $attempt -gt 1 ]; then
            log "Waiting 30 seconds before retry..."
            sleep 30
        fi
        
        # Delete resources in reverse order of creation
        delete_event_subscriptions
        delete_function_app
        delete_logic_app
        delete_event_grid_topic
        delete_monitoring_resources
        delete_storage_account
        
        # Check if we should continue to next attempt
        if [ $attempt -lt $max_attempts ]; then
            # Check if there are still resources to clean up
            local remaining_count
            remaining_count=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" --output tsv 2>/dev/null || echo "0")
            
            if [ "$remaining_count" -eq 0 ]; then
                log "All resources cleaned up successfully"
                break
            else
                warn "Some resources remain, will retry..."
                ((attempt++))
            fi
        else
            log "Maximum cleanup attempts reached"
            break
        fi
    done
}

# Main cleanup function
main() {
    log "Starting Azure Real-Time Data Validation Workflows cleanup..."
    
    # Check if dry run mode
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log "DRY RUN MODE - No resources will be deleted"
        load_environment_variables
        check_resource_group && list_resources
        return 0
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_environment_variables
    
    # Check if resource group exists
    if ! check_resource_group; then
        log "No cleanup needed - resource group doesn't exist"
        return 0
    fi
    
    list_resources
    confirm_deletion
    cleanup_with_retry
    delete_resource_group
    verify_deletion
    cleanup_local_files
    display_cleanup_summary
    
    success "Cleanup completed successfully!"
    log "Total cleanup time: $((SECONDS/60)) minutes"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi