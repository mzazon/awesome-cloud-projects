#!/bin/bash

# Destroy Azure Container Apps Dynamic Sessions with Event Grid
# This script safely removes all resources created for the secure code execution workflow

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Configuration
FORCE_DELETE=false
QUIET_MODE=false
SKIP_CONFIRMATION=false

# Check if running in debug mode
DEBUG=${DEBUG:-false}
if [[ "${DEBUG}" == "true" ]]; then
    set -x
fi

# Load environment variables from .env file
load_environment() {
    if [[ -f .env ]]; then
        log "Loading environment variables from .env file..."
        source .env
        log_success "Environment variables loaded"
    else
        log_error ".env file not found. Please ensure you have the deployment environment file."
        log_error "You can also set environment variables manually:"
        echo "  export RESOURCE_GROUP=your-resource-group"
        echo "  export LOCATION=your-location"
        echo "  export CONTAINERAPPS_ENVIRONMENT=your-env-name"
        echo "  export SESSION_POOL_NAME=your-pool-name"
        echo "  export EVENT_GRID_TOPIC=your-topic-name"
        echo "  export KEY_VAULT_NAME=your-keyvault-name"
        echo "  export STORAGE_ACCOUNT=your-storage-name"
        echo "  export FUNCTION_APP_NAME=your-function-name"
        echo "  export APP_INSIGHTS_NAME=your-insights-name"
        echo "  export LOG_ANALYTICS_WORKSPACE=your-workspace-name"
        exit 1
    fi
}

# Confirm destruction with user
confirm_destruction() {
    if [[ "${SKIP_CONFIRMATION}" == "true" ]] || [[ "${FORCE_DELETE}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will permanently delete the following resources:"
    echo "  Resource Group: ${RESOURCE_GROUP}"
    echo "  Container Apps Environment: ${CONTAINERAPPS_ENVIRONMENT}"
    echo "  Session Pool: ${SESSION_POOL_NAME}"
    echo "  Event Grid Topic: ${EVENT_GRID_TOPIC}"
    echo "  Key Vault: ${KEY_VAULT_NAME}"
    echo "  Storage Account: ${STORAGE_ACCOUNT}"
    echo "  Function App: ${FUNCTION_APP_NAME}"
    echo "  Application Insights: ${APP_INSIGHTS_NAME}"
    echo "  Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}"
    echo ""
    log_warning "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
}

# Check prerequisites
check_prerequisites() {
    if [[ "${QUIET_MODE}" != "true" ]]; then
        log "Checking prerequisites..."
    fi
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    if [[ "${QUIET_MODE}" != "true" ]]; then
        log_success "Prerequisites check completed"
    fi
}

# Delete Event Grid subscription (if exists)
delete_event_grid_subscription() {
    if [[ "${QUIET_MODE}" != "true" ]]; then
        log "Checking for Event Grid subscriptions..."
    fi
    
    # List and delete any subscriptions for this topic
    local topic_id=""
    if az eventgrid topic show \
        --name ${EVENT_GRID_TOPIC} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        
        topic_id=$(az eventgrid topic show \
            --name ${EVENT_GRID_TOPIC} \
            --resource-group ${RESOURCE_GROUP} \
            --query id --output tsv)
        
        # Check for subscriptions
        local subscriptions=$(az eventgrid event-subscription list \
            --source-resource-id "${topic_id}" \
            --query "[].name" --output tsv 2>/dev/null || true)
        
        if [[ -n "${subscriptions}" ]]; then
            while IFS= read -r subscription; do
                if [[ -n "${subscription}" ]]; then
                    if [[ "${QUIET_MODE}" != "true" ]]; then
                        log "Deleting Event Grid subscription: ${subscription}"
                    fi
                    az eventgrid event-subscription delete \
                        --name "${subscription}" \
                        --source-resource-id "${topic_id}" &> /dev/null || true
                    
                    if [[ "${QUIET_MODE}" != "true" ]]; then
                        log_success "Event Grid subscription deleted: ${subscription}"
                    fi
                fi
            done <<< "${subscriptions}"
        fi
    fi
}

# Delete Event Grid Topic
delete_event_grid_topic() {
    if [[ "${QUIET_MODE}" != "true" ]]; then
        log "Deleting Event Grid Topic: ${EVENT_GRID_TOPIC}"
    fi
    
    if az eventgrid topic show \
        --name ${EVENT_GRID_TOPIC} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        
        az eventgrid topic delete \
            --name ${EVENT_GRID_TOPIC} \
            --resource-group ${RESOURCE_GROUP} &> /dev/null || true
        
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_success "Event Grid Topic deleted: ${EVENT_GRID_TOPIC}"
        fi
    else
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_warning "Event Grid Topic ${EVENT_GRID_TOPIC} not found"
        fi
    fi
}

# Delete Function App
delete_function_app() {
    if [[ "${QUIET_MODE}" != "true" ]]; then
        log "Deleting Function App: ${FUNCTION_APP_NAME}"
    fi
    
    if az functionapp show \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        
        az functionapp delete \
            --name ${FUNCTION_APP_NAME} \
            --resource-group ${RESOURCE_GROUP} &> /dev/null || true
        
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_success "Function App deleted: ${FUNCTION_APP_NAME}"
        fi
    else
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_warning "Function App ${FUNCTION_APP_NAME} not found"
        fi
    fi
}

# Delete Application Insights
delete_application_insights() {
    if [[ "${QUIET_MODE}" != "true" ]]; then
        log "Deleting Application Insights: ${APP_INSIGHTS_NAME}"
    fi
    
    if az monitor app-insights component show \
        --app ${APP_INSIGHTS_NAME} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        
        az monitor app-insights component delete \
            --app ${APP_INSIGHTS_NAME} \
            --resource-group ${RESOURCE_GROUP} &> /dev/null || true
        
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_success "Application Insights deleted: ${APP_INSIGHTS_NAME}"
        fi
    else
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_warning "Application Insights ${APP_INSIGHTS_NAME} not found"
        fi
    fi
}

# Delete Session Pool
delete_session_pool() {
    if [[ "${QUIET_MODE}" != "true" ]]; then
        log "Deleting Session Pool: ${SESSION_POOL_NAME}"
    fi
    
    if az containerapp sessionpool show \
        --name ${SESSION_POOL_NAME} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        
        az containerapp sessionpool delete \
            --name ${SESSION_POOL_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --yes &> /dev/null || true
        
        # Wait for session pool deletion
        local timeout=300
        local elapsed=0
        local interval=10
        
        while [[ ${elapsed} -lt ${timeout} ]]; do
            if ! az containerapp sessionpool show \
                --name ${SESSION_POOL_NAME} \
                --resource-group ${RESOURCE_GROUP} &> /dev/null; then
                break
            fi
            sleep ${interval}
            elapsed=$((elapsed + interval))
            
            if [[ "${QUIET_MODE}" != "true" ]] && [[ $((elapsed % 30)) -eq 0 ]]; then
                log "Waiting for session pool deletion... (${elapsed}s)"
            fi
        done
        
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_success "Session Pool deleted: ${SESSION_POOL_NAME}"
        fi
    else
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_warning "Session Pool ${SESSION_POOL_NAME} not found"
        fi
    fi
}

# Delete Container Apps Environment
delete_container_apps_environment() {
    if [[ "${QUIET_MODE}" != "true" ]]; then
        log "Deleting Container Apps Environment: ${CONTAINERAPPS_ENVIRONMENT}"
    fi
    
    if az containerapp env show \
        --name ${CONTAINERAPPS_ENVIRONMENT} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        
        az containerapp env delete \
            --name ${CONTAINERAPPS_ENVIRONMENT} \
            --resource-group ${RESOURCE_GROUP} \
            --yes &> /dev/null || true
        
        # Wait for environment deletion
        local timeout=300
        local elapsed=0
        local interval=10
        
        while [[ ${elapsed} -lt ${timeout} ]]; do
            if ! az containerapp env show \
                --name ${CONTAINERAPPS_ENVIRONMENT} \
                --resource-group ${RESOURCE_GROUP} &> /dev/null; then
                break
            fi
            sleep ${interval}
            elapsed=$((elapsed + interval))
            
            if [[ "${QUIET_MODE}" != "true" ]] && [[ $((elapsed % 30)) -eq 0 ]]; then
                log "Waiting for Container Apps Environment deletion... (${elapsed}s)"
            fi
        done
        
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_success "Container Apps Environment deleted: ${CONTAINERAPPS_ENVIRONMENT}"
        fi
    else
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_warning "Container Apps Environment ${CONTAINERAPPS_ENVIRONMENT} not found"
        fi
    fi
}

# Delete Storage Account
delete_storage_account() {
    if [[ "${QUIET_MODE}" != "true" ]]; then
        log "Deleting Storage Account: ${STORAGE_ACCOUNT}"
    fi
    
    if az storage account show \
        --name ${STORAGE_ACCOUNT} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        
        az storage account delete \
            --name ${STORAGE_ACCOUNT} \
            --resource-group ${RESOURCE_GROUP} \
            --yes &> /dev/null || true
        
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_success "Storage Account deleted: ${STORAGE_ACCOUNT}"
        fi
    else
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_warning "Storage Account ${STORAGE_ACCOUNT} not found"
        fi
    fi
}

# Delete Key Vault
delete_key_vault() {
    if [[ "${QUIET_MODE}" != "true" ]]; then
        log "Deleting Key Vault: ${KEY_VAULT_NAME}"
    fi
    
    if az keyvault show --name ${KEY_VAULT_NAME} &> /dev/null; then
        az keyvault delete \
            --name ${KEY_VAULT_NAME} \
            --resource-group ${RESOURCE_GROUP} &> /dev/null || true
        
        # Purge the Key Vault to fully remove it
        if [[ "${FORCE_DELETE}" == "true" ]]; then
            if [[ "${QUIET_MODE}" != "true" ]]; then
                log "Purging Key Vault: ${KEY_VAULT_NAME}"
            fi
            az keyvault purge \
                --name ${KEY_VAULT_NAME} \
                --location ${LOCATION} &> /dev/null || true
        fi
        
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_success "Key Vault deleted: ${KEY_VAULT_NAME}"
            if [[ "${FORCE_DELETE}" != "true" ]]; then
                log_warning "Key Vault is in soft-delete state. Use --force to purge completely."
            fi
        fi
    else
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_warning "Key Vault ${KEY_VAULT_NAME} not found"
        fi
    fi
}

# Delete Log Analytics Workspace
delete_log_analytics_workspace() {
    if [[ "${QUIET_MODE}" != "true" ]]; then
        log "Deleting Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}"
    fi
    
    if az monitor log-analytics workspace show \
        --resource-group ${RESOURCE_GROUP} \
        --workspace-name ${LOG_ANALYTICS_WORKSPACE} &> /dev/null; then
        
        az monitor log-analytics workspace delete \
            --workspace-name ${LOG_ANALYTICS_WORKSPACE} \
            --resource-group ${RESOURCE_GROUP} \
            --yes &> /dev/null || true
        
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_success "Log Analytics Workspace deleted: ${LOG_ANALYTICS_WORKSPACE}"
        fi
    else
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_warning "Log Analytics Workspace ${LOG_ANALYTICS_WORKSPACE} not found"
        fi
    fi
}

# Delete Resource Group
delete_resource_group() {
    if [[ "${QUIET_MODE}" != "true" ]]; then
        log "Deleting Resource Group: ${RESOURCE_GROUP}"
    fi
    
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        az group delete \
            --name ${RESOURCE_GROUP} \
            --yes \
            --no-wait &> /dev/null || true
        
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_success "Resource Group deletion initiated: ${RESOURCE_GROUP}"
            log "Note: Resource group deletion is running in the background"
        fi
    else
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_warning "Resource Group ${RESOURCE_GROUP} not found"
        fi
    fi
}

# Wait for resource group deletion (optional)
wait_for_resource_group_deletion() {
    if [[ "${QUIET_MODE}" == "true" ]]; then
        return 0
    fi
    
    log "Waiting for resource group deletion to complete..."
    
    local timeout=1800  # 30 minutes
    local elapsed=0
    local interval=30
    
    while [[ ${elapsed} -lt ${timeout} ]]; do
        if ! az group show --name ${RESOURCE_GROUP} &> /dev/null; then
            log_success "Resource Group fully deleted: ${RESOURCE_GROUP}"
            return 0
        fi
        
        sleep ${interval}
        elapsed=$((elapsed + interval))
        
        if [[ $((elapsed % 120)) -eq 0 ]]; then
            log "Still waiting for resource group deletion... (${elapsed}s)"
        fi
    done
    
    log_warning "Resource group deletion is taking longer than expected"
    log "You can check the status in the Azure portal or with: az group show --name ${RESOURCE_GROUP}"
}

# Clean up local files
cleanup_local_files() {
    if [[ "${QUIET_MODE}" != "true" ]]; then
        log "Cleaning up local files..."
    fi
    
    if [[ -f .env ]]; then
        rm -f .env
        if [[ "${QUIET_MODE}" != "true" ]]; then
            log_success "Removed .env file"
        fi
    fi
}

# Validate deletion
validate_deletion() {
    if [[ "${QUIET_MODE}" == "true" ]]; then
        return 0
    fi
    
    log "Validating resource deletion..."
    
    local remaining_resources=0
    
    # Check if any resources still exist
    if az eventgrid topic show --name ${EVENT_GRID_TOPIC} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Event Grid Topic still exists: ${EVENT_GRID_TOPIC}"
        ((remaining_resources++))
    fi
    
    if az functionapp show --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Function App still exists: ${FUNCTION_APP_NAME}"
        ((remaining_resources++))
    fi
    
    if az containerapp sessionpool show --name ${SESSION_POOL_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Session Pool still exists: ${SESSION_POOL_NAME}"
        ((remaining_resources++))
    fi
    
    if az containerapp env show --name ${CONTAINERAPPS_ENVIRONMENT} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Container Apps Environment still exists: ${CONTAINERAPPS_ENVIRONMENT}"
        ((remaining_resources++))
    fi
    
    if [[ ${remaining_resources} -eq 0 ]]; then
        log_success "All individual resources successfully deleted"
    else
        log_warning "${remaining_resources} resources may still be deleting"
    fi
}

# Display deletion summary
display_summary() {
    if [[ "${QUIET_MODE}" == "true" ]]; then
        return 0
    fi
    
    log "Deletion Summary:"
    echo "=================="
    echo "✅ Event Grid Topic and subscriptions"
    echo "✅ Function App and settings"
    echo "✅ Application Insights"
    echo "✅ Session Pool"
    echo "✅ Container Apps Environment"
    echo "✅ Storage Account and containers"
    echo "✅ Key Vault $(if [[ "${FORCE_DELETE}" == "true" ]]; then echo "(purged)"; else echo "(soft-deleted)"; fi)"
    echo "✅ Log Analytics Workspace"
    echo "✅ Resource Group (deletion in progress)"
    echo "✅ Local environment file"
    echo "=================="
    echo ""
    echo "All resources have been successfully removed or are being deleted."
    echo "Resource group deletion may take several minutes to complete."
}

# Main destruction function
main() {
    if [[ "${QUIET_MODE}" != "true" ]]; then
        log "Starting Azure Container Apps Dynamic Sessions cleanup..."
    fi
    
    load_environment
    check_prerequisites
    confirm_destruction
    
    # Delete resources in reverse order of dependencies
    delete_event_grid_subscription
    delete_event_grid_topic
    delete_function_app
    delete_application_insights
    delete_session_pool
    delete_container_apps_environment
    delete_storage_account
    delete_key_vault
    delete_log_analytics_workspace
    delete_resource_group
    
    # Validation and cleanup
    validate_deletion
    cleanup_local_files
    
    if [[ "${QUIET_MODE}" != "true" ]]; then
        display_summary
        
        echo ""
        read -p "Do you want to wait for resource group deletion to complete? (y/N): " wait_choice
        if [[ "${wait_choice}" =~ ^[Yy]$ ]]; then
            wait_for_resource_group_deletion
        fi
        
        log_success "Cleanup completed successfully!"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Destroy Azure Container Apps Dynamic Sessions with Event Grid"
            echo ""
            echo "Options:"
            echo "  --help, -h      Show this help message"
            echo "  --force         Force deletion (purge Key Vault, skip confirmations)"
            echo "  --quiet         Run in quiet mode (minimal output)"
            echo "  --yes           Skip confirmation prompts"
            echo "  --debug         Enable debug mode"
            echo ""
            echo "Environment variables:"
            echo "  DEBUG           Enable debug mode (true/false)"
            echo ""
            echo "Note: This script requires a .env file created by the deploy.sh script"
            exit 0
            ;;
        --force)
            FORCE_DELETE=true
            SKIP_CONFIRMATION=true
            shift
            ;;
        --quiet)
            QUIET_MODE=true
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --debug)
            DEBUG=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"