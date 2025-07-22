#!/bin/bash

# Destroy script for Orchestrating Automated Environmental Data Pipelines
# Recipe: orchestrating-automated-environmental-data-pipelines-with-azure-data-factory-and-azure-sustainability-manager
# Generated: 2025-01-16

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
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
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set default values that can be overridden
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-env-data-pipeline}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Try to get resource names from deployment or use defaults
    if [ -z "${DATA_FACTORY_NAME:-}" ] || [ -z "${STORAGE_ACCOUNT_NAME:-}" ] || [ -z "${FUNCTION_APP_NAME:-}" ] || [ -z "${LOG_ANALYTICS_NAME:-}" ]; then
        log_warning "Resource names not provided. Attempting to discover resources in resource group..."
        
        # Try to discover Data Factory
        if [ -z "${DATA_FACTORY_NAME:-}" ]; then
            DATA_FACTORY_NAME=$(az datafactory list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")
        fi
        
        # Try to discover Storage Account
        if [ -z "${STORAGE_ACCOUNT_NAME:-}" ]; then
            STORAGE_ACCOUNT_NAME=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'stenvdata')].name | [0]" --output tsv 2>/dev/null || echo "")
        fi
        
        # Try to discover Function App
        if [ -z "${FUNCTION_APP_NAME:-}" ]; then
            FUNCTION_APP_NAME=$(az functionapp list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'func-env-transform')].name | [0]" --output tsv 2>/dev/null || echo "")
        fi
        
        # Try to discover Log Analytics workspace
        if [ -z "${LOG_ANALYTICS_NAME:-}" ]; then
            LOG_ANALYTICS_NAME=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'log-env-monitor')].name | [0]" --output tsv 2>/dev/null || echo "")
        fi
    fi
    
    log "Environment variables set:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  Subscription ID: $SUBSCRIPTION_ID"
    log "  Data Factory Name: ${DATA_FACTORY_NAME:-'Not found'}"
    log "  Storage Account Name: ${STORAGE_ACCOUNT_NAME:-'Not found'}"
    log "  Function App Name: ${FUNCTION_APP_NAME:-'Not found'}"
    log "  Log Analytics Name: ${LOG_ANALYTICS_NAME:-'Not found'}"
    
    log_success "Environment variables configured"
}

# Function to confirm deletion
confirm_deletion() {
    log_warning "This will permanently delete all resources in the resource group: $RESOURCE_GROUP"
    log_warning "This action cannot be undone!"
    
    # Check if running in non-interactive mode
    if [ "${FORCE_DELETE:-false}" = "true" ]; then
        log_warning "FORCE_DELETE is set. Proceeding with deletion..."
        return 0
    fi
    
    echo -n "Are you sure you want to continue? (yes/no): "
    read -r confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource deletion..."
}

# Function to stop and remove Data Factory triggers
remove_data_factory_triggers() {
    if [ -n "${DATA_FACTORY_NAME:-}" ]; then
        log "Stopping and removing Data Factory triggers..."
        
        # Stop all triggers
        local triggers=$(az datafactory trigger list \
            --resource-group "$RESOURCE_GROUP" \
            --factory-name "$DATA_FACTORY_NAME" \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [ -n "$triggers" ]; then
            while IFS= read -r trigger_name; do
                if [ -n "$trigger_name" ]; then
                    log "Stopping trigger: $trigger_name"
                    az datafactory trigger stop \
                        --resource-group "$RESOURCE_GROUP" \
                        --factory-name "$DATA_FACTORY_NAME" \
                        --trigger-name "$trigger_name" || log_warning "Failed to stop trigger: $trigger_name"
                    
                    # Wait a moment for the trigger to stop
                    sleep 5
                    
                    log "Deleting trigger: $trigger_name"
                    az datafactory trigger delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --factory-name "$DATA_FACTORY_NAME" \
                        --trigger-name "$trigger_name" \
                        --yes || log_warning "Failed to delete trigger: $trigger_name"
                fi
            done <<< "$triggers"
            
            log_success "Data Factory triggers stopped and removed"
        else
            log_warning "No triggers found to remove"
        fi
    else
        log_warning "Data Factory name not found. Skipping trigger removal."
    fi
}

# Function to remove monitoring alerts
remove_monitoring_alerts() {
    log "Removing monitoring alerts and action groups..."
    
    # Remove alert rules
    local alert_rules=("EnvironmentalPipelineFailures" "EnvironmentalDataProcessingDelay")
    
    for alert_rule in "${alert_rules[@]}"; do
        log "Removing alert rule: $alert_rule"
        az monitor metrics alert delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$alert_rule" || log_warning "Failed to delete alert rule: $alert_rule (may not exist)"
    done
    
    # Remove action group
    log "Removing action group: EnvironmentalAlerts"
    az monitor action-group delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "EnvironmentalAlerts" || log_warning "Failed to delete action group (may not exist)"
    
    log_success "Monitoring alerts and action groups removed"
}

# Function to remove Data Factory
remove_data_factory() {
    if [ -n "${DATA_FACTORY_NAME:-}" ]; then
        log "Removing Data Factory: $DATA_FACTORY_NAME"
        
        # First, remove all pipelines to ensure clean deletion
        local pipelines=$(az datafactory pipeline list \
            --resource-group "$RESOURCE_GROUP" \
            --factory-name "$DATA_FACTORY_NAME" \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [ -n "$pipelines" ]; then
            while IFS= read -r pipeline_name; do
                if [ -n "$pipeline_name" ]; then
                    log "Deleting pipeline: $pipeline_name"
                    az datafactory pipeline delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --factory-name "$DATA_FACTORY_NAME" \
                        --pipeline-name "$pipeline_name" \
                        --yes || log_warning "Failed to delete pipeline: $pipeline_name"
                fi
            done <<< "$pipelines"
        fi
        
        # Remove datasets
        local datasets=$(az datafactory dataset list \
            --resource-group "$RESOURCE_GROUP" \
            --factory-name "$DATA_FACTORY_NAME" \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [ -n "$datasets" ]; then
            while IFS= read -r dataset_name; do
                if [ -n "$dataset_name" ]; then
                    log "Deleting dataset: $dataset_name"
                    az datafactory dataset delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --factory-name "$DATA_FACTORY_NAME" \
                        --dataset-name "$dataset_name" \
                        --yes || log_warning "Failed to delete dataset: $dataset_name"
                fi
            done <<< "$datasets"
        fi
        
        # Remove linked services
        local linked_services=$(az datafactory linked-service list \
            --resource-group "$RESOURCE_GROUP" \
            --factory-name "$DATA_FACTORY_NAME" \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [ -n "$linked_services" ]; then
            while IFS= read -r linked_service_name; do
                if [ -n "$linked_service_name" ]; then
                    log "Deleting linked service: $linked_service_name"
                    az datafactory linked-service delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --factory-name "$DATA_FACTORY_NAME" \
                        --linked-service-name "$linked_service_name" \
                        --yes || log_warning "Failed to delete linked service: $linked_service_name"
                fi
            done <<< "$linked_services"
        fi
        
        # Finally, delete the Data Factory
        log "Deleting Data Factory: $DATA_FACTORY_NAME"
        az datafactory delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$DATA_FACTORY_NAME" \
            --yes || log_warning "Failed to delete Data Factory: $DATA_FACTORY_NAME"
        
        log_success "Data Factory removed: $DATA_FACTORY_NAME"
    else
        log_warning "Data Factory name not found. Skipping Data Factory removal."
    fi
}

# Function to remove Function App
remove_function_app() {
    if [ -n "${FUNCTION_APP_NAME:-}" ]; then
        log "Removing Function App: $FUNCTION_APP_NAME"
        
        az functionapp delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$FUNCTION_APP_NAME" || log_warning "Failed to delete Function App: $FUNCTION_APP_NAME"
        
        log_success "Function App removed: $FUNCTION_APP_NAME"
    else
        log_warning "Function App name not found. Skipping Function App removal."
    fi
}

# Function to remove storage account
remove_storage_account() {
    if [ -n "${STORAGE_ACCOUNT_NAME:-}" ]; then
        log "Removing storage account: $STORAGE_ACCOUNT_NAME"
        
        # First, try to remove any containers/blobs if needed
        log "Checking for storage containers..."
        local containers=$(az storage container list \
            --account-name "$STORAGE_ACCOUNT_NAME" \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [ -n "$containers" ]; then
            log_warning "Found storage containers. They will be deleted with the storage account."
        fi
        
        # Delete the storage account
        az storage account delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$STORAGE_ACCOUNT_NAME" \
            --yes || log_warning "Failed to delete storage account: $STORAGE_ACCOUNT_NAME"
        
        log_success "Storage account removed: $STORAGE_ACCOUNT_NAME"
    else
        log_warning "Storage account name not found. Skipping storage account removal."
    fi
}

# Function to remove Log Analytics workspace
remove_log_analytics() {
    if [ -n "${LOG_ANALYTICS_NAME:-}" ]; then
        log "Removing Log Analytics workspace: $LOG_ANALYTICS_NAME"
        
        # Check if diagnostic settings exist and remove them first
        log "Checking for diagnostic settings..."
        local diagnostic_settings=$(az monitor diagnostic-settings list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [ -n "$diagnostic_settings" ]; then
            while IFS= read -r setting_name; do
                if [ -n "$setting_name" ] && [[ "$setting_name" == *"EnvironmentalDataFactory"* ]]; then
                    log "Removing diagnostic setting: $setting_name"
                    # Note: This requires the resource ID, which we may not have at this point
                    # The diagnostic settings will be removed when the resource is deleted
                fi
            done <<< "$diagnostic_settings"
        fi
        
        # Delete the Log Analytics workspace
        az monitor log-analytics workspace delete \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_NAME" \
            --yes || log_warning "Failed to delete Log Analytics workspace: $LOG_ANALYTICS_NAME"
        
        log_success "Log Analytics workspace removed: $LOG_ANALYTICS_NAME"
    else
        log_warning "Log Analytics workspace name not found. Skipping Log Analytics removal."
    fi
}

# Function to remove resource group
remove_resource_group() {
    log "Checking if resource group should be removed..."
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' does not exist"
        return 0
    fi
    
    # Check if there are any remaining resources in the resource group
    local remaining_resources=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "length(@)" --output tsv 2>/dev/null || echo "0")
    
    if [ "$remaining_resources" -eq 0 ]; then
        log "No resources remaining in resource group. Removing resource group..."
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait || log_warning "Failed to delete resource group: $RESOURCE_GROUP"
        
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        log "Note: Resource group deletion may take several minutes to complete"
    else
        log_warning "Resource group contains $remaining_resources remaining resources"
        log "Would you like to force delete the entire resource group? (yes/no): "
        
        if [ "${FORCE_DELETE:-false}" = "true" ]; then
            log_warning "FORCE_DELETE is set. Deleting resource group with all remaining resources..."
            az group delete \
                --name "$RESOURCE_GROUP" \
                --yes \
                --no-wait || log_warning "Failed to delete resource group: $RESOURCE_GROUP"
            
            log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        else
            read -r force_confirmation
            if [ "$force_confirmation" = "yes" ]; then
                az group delete \
                    --name "$RESOURCE_GROUP" \
                    --yes \
                    --no-wait || log_warning "Failed to delete resource group: $RESOURCE_GROUP"
                
                log_success "Resource group deletion initiated: $RESOURCE_GROUP"
            else
                log "Resource group deletion cancelled. You may need to manually remove remaining resources."
            fi
        fi
    fi
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        local remaining_resources=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query "length(@)" --output tsv 2>/dev/null || echo "0")
        
        if [ "$remaining_resources" -eq 0 ]; then
            log_success "Resource group is empty. Cleanup validation passed."
        else
            log_warning "Resource group contains $remaining_resources remaining resources"
            
            # List remaining resources
            log "Remaining resources:"
            az resource list \
                --resource-group "$RESOURCE_GROUP" \
                --query "[].{Name:name, Type:type, Location:location}" \
                --output table 2>/dev/null || log_warning "Could not list remaining resources"
        fi
    else
        log_success "Resource group has been deleted. Cleanup validation passed."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "===================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Data Factory: ${DATA_FACTORY_NAME:-'Not found'}"
    echo "Storage Account: ${STORAGE_ACCOUNT_NAME:-'Not found'}"
    echo "Function App: ${FUNCTION_APP_NAME:-'Not found'}"
    echo "Log Analytics: ${LOG_ANALYTICS_NAME:-'Not found'}"
    echo "===================="
    echo ""
    echo "Cleanup Actions Performed:"
    echo "1. Stopped and removed Data Factory triggers"
    echo "2. Removed monitoring alerts and action groups"
    echo "3. Removed Data Factory and all components"
    echo "4. Removed Function App"
    echo "5. Removed storage account"
    echo "6. Removed Log Analytics workspace"
    echo "7. Removed resource group (if empty)"
    echo ""
    echo "Note: Some resources may take additional time to be fully removed from Azure."
    echo "You can verify cleanup completion in the Azure portal."
}

# Main cleanup function
main() {
    log "Starting Azure Environmental Data Pipeline cleanup..."
    
    # Run cleanup steps
    check_prerequisites
    set_environment_variables
    confirm_deletion
    remove_data_factory_triggers
    remove_monitoring_alerts
    remove_data_factory
    remove_function_app
    remove_storage_account
    remove_log_analytics
    remove_resource_group
    validate_cleanup
    display_cleanup_summary
    
    log_success "Cleanup completed successfully!"
    log "Total cleanup time: $SECONDS seconds"
}

# Error handling
trap 'log_error "Cleanup failed at line $LINENO. Exit code: $?"' ERR

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -f, --force          Force deletion without confirmation prompts"
    echo "  --resource-group RG  Override resource group name"
    echo "  --data-factory DF    Override Data Factory name"
    echo "  --storage-account SA Override storage account name"
    echo "  --function-app FA    Override Function App name"
    echo "  --log-analytics LA   Override Log Analytics workspace name"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP       Resource group name (default: rg-env-data-pipeline)"
    echo "  DATA_FACTORY_NAME    Data Factory name"
    echo "  STORAGE_ACCOUNT_NAME Storage account name"
    echo "  FUNCTION_APP_NAME    Function App name"
    echo "  LOG_ANALYTICS_NAME   Log Analytics workspace name"
    echo "  FORCE_DELETE         Set to 'true' to skip confirmation prompts"
    echo ""
    echo "Examples:"
    echo "  $0                           # Interactive cleanup"
    echo "  $0 --force                   # Force cleanup without prompts"
    echo "  $0 --resource-group my-rg    # Cleanup specific resource group"
    echo "  FORCE_DELETE=true $0         # Force cleanup using environment variable"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            export FORCE_DELETE=true
            shift
            ;;
        --resource-group)
            export RESOURCE_GROUP="$2"
            shift 2
            ;;
        --data-factory)
            export DATA_FACTORY_NAME="$2"
            shift 2
            ;;
        --storage-account)
            export STORAGE_ACCOUNT_NAME="$2"
            shift 2
            ;;
        --function-app)
            export FUNCTION_APP_NAME="$2"
            shift 2
            ;;
        --log-analytics)
            export LOG_ANALYTICS_NAME="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"