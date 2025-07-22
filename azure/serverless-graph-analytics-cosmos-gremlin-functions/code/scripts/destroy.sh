#!/bin/bash

# Serverless Graph Analytics with Azure Cosmos DB Gremlin and Azure Functions - Cleanup Script
# This script safely removes all resources created for the serverless graph analytics solution

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# Set environment variables (same as deploy script)
set_environment_variables() {
    log_info "Setting environment variables..."
    
    # Core resource settings - try to use existing values or defaults
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-graph-analytics}"
    export LOCATION="${LOCATION:-eastus}"
    
    # If RANDOM_SUFFIX is not set, we'll try to detect it from existing resources
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        log_info "RANDOM_SUFFIX not provided, attempting to detect from existing resources..."
        
        # Try to find existing Function App to extract suffix
        EXISTING_FUNC_APP=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[?starts_with(name, 'func-graph-')].name" --output tsv 2>/dev/null | head -n1 || echo "")
        
        if [ -n "${EXISTING_FUNC_APP}" ]; then
            export RANDOM_SUFFIX="${EXISTING_FUNC_APP#func-graph-}"
            log_info "Detected random suffix: ${RANDOM_SUFFIX}"
        else
            log_warning "Could not detect random suffix. Using default resource names."
            export RANDOM_SUFFIX="unknown"
        fi
    fi
    
    # Azure resource names
    export COSMOS_ACCOUNT="${COSMOS_ACCOUNT:-cosmos-graph-${RANDOM_SUFFIX}}"
    export DATABASE_NAME="${DATABASE_NAME:-GraphAnalytics}"
    export GRAPH_NAME="${GRAPH_NAME:-RelationshipGraph}"
    export FUNCTION_APP="${FUNCTION_APP:-func-graph-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stgraph${RANDOM_SUFFIX}}"
    export EVENT_GRID_TOPIC="${EVENT_GRID_TOPIC:-eg-graph-${RANDOM_SUFFIX}}"
    export APP_INSIGHTS="${APP_INSIGHTS:-ai-graph-${RANDOM_SUFFIX}}"
    
    log_success "Environment variables configured"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Resources to delete: ${COSMOS_ACCOUNT}, ${FUNCTION_APP}, ${STORAGE_ACCOUNT}, ${EVENT_GRID_TOPIC}, ${APP_INSIGHTS}"
}

# Confirm deletion with user
confirm_deletion() {
    echo
    log_warning "⚠️  DANGER: This will permanently delete the following resources:"
    echo "   - Resource Group: ${RESOURCE_GROUP}"
    echo "   - Cosmos DB Account: ${COSMOS_ACCOUNT}"
    echo "   - Function App: ${FUNCTION_APP}"
    echo "   - Storage Account: ${STORAGE_ACCOUNT}"
    echo "   - Event Grid Topic: ${EVENT_GRID_TOPIC}"
    echo "   - Application Insights: ${APP_INSIGHTS}"
    echo "   - All associated data will be permanently lost!"
    echo
    
    # Check if running in non-interactive mode
    if [ "${FORCE_DELETE:-false}" = "true" ]; then
        log_info "FORCE_DELETE is set, skipping confirmation"
        return 0
    fi
    
    echo -n "Are you sure you want to proceed? (Type 'DELETE' to confirm): "
    read -r confirmation
    
    if [ "${confirmation}" != "DELETE" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    log_info "User confirmed deletion, proceeding with cleanup..."
}

# Check if resource group exists
check_resource_group() {
    log_info "Checking if resource group exists..."
    
    if ! az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Resource group ${RESOURCE_GROUP} does not exist"
        log_info "Nothing to clean up"
        exit 0
    fi
    
    log_info "Resource group ${RESOURCE_GROUP} found"
}

# List resources before deletion
list_resources() {
    log_info "Listing resources in ${RESOURCE_GROUP}..."
    
    RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" --output table 2>/dev/null || echo "")
    
    if [ -n "${RESOURCES}" ]; then
        echo "${RESOURCES}"
        echo
    else
        log_info "No resources found in resource group"
    fi
}

# Delete Event Grid subscriptions first (to avoid orphaned subscriptions)
delete_event_grid_subscriptions() {
    log_info "Deleting Event Grid subscriptions..."
    
    # Delete GraphWriter subscription
    if az eventgrid event-subscription show \
        --name graph-writer-subscription \
        --source-resource-id "$(az eventgrid topic show --name ${EVENT_GRID_TOPIC} --resource-group ${RESOURCE_GROUP} --query id --output tsv 2>/dev/null || echo '')" >/dev/null 2>&1; then
        
        az eventgrid event-subscription delete \
            --name graph-writer-subscription \
            --source-resource-id "$(az eventgrid topic show --name ${EVENT_GRID_TOPIC} --resource-group ${RESOURCE_GROUP} --query id --output tsv)"
        
        log_success "GraphWriter subscription deleted"
    else
        log_info "GraphWriter subscription not found, skipping"
    fi
    
    # Delete GraphAnalytics subscription
    if az eventgrid event-subscription show \
        --name graph-analytics-subscription \
        --source-resource-id "$(az eventgrid topic show --name ${EVENT_GRID_TOPIC} --resource-group ${RESOURCE_GROUP} --query id --output tsv 2>/dev/null || echo '')" >/dev/null 2>&1; then
        
        az eventgrid event-subscription delete \
            --name graph-analytics-subscription \
            --source-resource-id "$(az eventgrid topic show --name ${EVENT_GRID_TOPIC} --resource-group ${RESOURCE_GROUP} --query id --output tsv)"
        
        log_success "GraphAnalytics subscription deleted"
    else
        log_info "GraphAnalytics subscription not found, skipping"
    fi
}

# Delete Function App (before storage account to avoid dependency issues)
delete_function_app() {
    log_info "Deleting Function App: ${FUNCTION_APP}..."
    
    if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        az functionapp delete \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --slot production
        
        log_success "Function App deleted: ${FUNCTION_APP}"
    else
        log_info "Function App ${FUNCTION_APP} not found, skipping"
    fi
}

# Delete Event Grid topic
delete_event_grid_topic() {
    log_info "Deleting Event Grid topic: ${EVENT_GRID_TOPIC}..."
    
    if az eventgrid topic show --name "${EVENT_GRID_TOPIC}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        az eventgrid topic delete \
            --name "${EVENT_GRID_TOPIC}" \
            --resource-group "${RESOURCE_GROUP}"
        
        log_success "Event Grid topic deleted: ${EVENT_GRID_TOPIC}"
    else
        log_info "Event Grid topic ${EVENT_GRID_TOPIC} not found, skipping"
    fi
}

# Delete Cosmos DB account
delete_cosmos_db() {
    log_info "Deleting Cosmos DB account: ${COSMOS_ACCOUNT}..."
    
    if az cosmosdb show --name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_info "Cosmos DB deletion may take 5-10 minutes..."
        az cosmosdb delete \
            --name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes
        
        log_success "Cosmos DB account deleted: ${COSMOS_ACCOUNT}"
    else
        log_info "Cosmos DB account ${COSMOS_ACCOUNT} not found, skipping"
    fi
}

# Delete storage account
delete_storage_account() {
    log_info "Deleting storage account: ${STORAGE_ACCOUNT}..."
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        az storage account delete \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes
        
        log_success "Storage account deleted: ${STORAGE_ACCOUNT}"
    else
        log_info "Storage account ${STORAGE_ACCOUNT} not found, skipping"
    fi
}

# Delete Application Insights
delete_application_insights() {
    log_info "Deleting Application Insights: ${APP_INSIGHTS}..."
    
    if az monitor app-insights component show --app "${APP_INSIGHTS}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        az monitor app-insights component delete \
            --app "${APP_INSIGHTS}" \
            --resource-group "${RESOURCE_GROUP}"
        
        log_success "Application Insights deleted: ${APP_INSIGHTS}"
    else
        log_info "Application Insights ${APP_INSIGHTS} not found, skipping"
    fi
}

# Delete resource group (complete cleanup)
delete_resource_group() {
    log_info "Deleting resource group: ${RESOURCE_GROUP}..."
    
    # Final confirmation for resource group deletion
    if [ "${FORCE_DELETE:-false}" != "true" ]; then
        echo
        log_warning "⚠️  FINAL WARNING: About to delete the entire resource group!"
        echo -n "Type 'CONFIRM' to proceed with resource group deletion: "
        read -r final_confirmation
        
        if [ "${final_confirmation}" != "CONFIRM" ]; then
            log_info "Resource group deletion cancelled"
            log_info "Individual resources have been deleted, but resource group remains"
            return 0
        fi
    fi
    
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_info "Resource group deletion may take several minutes..."
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait
        
        log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        log_info "Note: Resource group deletion is running in the background"
    else
        log_info "Resource group ${RESOURCE_GROUP} not found, skipping"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_info "Resource group still exists (deletion may be in progress)"
        
        # List remaining resources
        REMAINING=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null || echo "")
        if [ -n "${REMAINING}" ]; then
            log_warning "Some resources may still exist:"
            echo "${REMAINING}"
            log_info "These resources should be deleted automatically as the resource group deletion completes"
        fi
    else
        log_success "Resource group has been completely deleted"
    fi
}

# Clean up local environment variables
cleanup_environment() {
    log_info "Cleaning up environment variables..."
    
    unset RESOURCE_GROUP LOCATION RANDOM_SUFFIX
    unset COSMOS_ACCOUNT DATABASE_NAME GRAPH_NAME
    unset FUNCTION_APP STORAGE_ACCOUNT EVENT_GRID_TOPIC APP_INSIGHTS
    unset COSMOS_KEY INSTRUMENTATION_KEY TOPIC_ENDPOINT TOPIC_KEY
    
    log_success "Environment variables cleaned up"
}

# Display cleanup summary
display_summary() {
    echo
    log_success "Cleanup completed!"
    echo "==================="
    echo
    echo "✅ Event Grid subscriptions deleted"
    echo "✅ Function App deleted"
    echo "✅ Event Grid topic deleted"
    echo "✅ Cosmos DB account deleted"
    echo "✅ Storage account deleted"
    echo "✅ Application Insights deleted"
    echo "✅ Resource group deletion initiated"
    echo
    echo "📋 Notes:"
    echo "   - Resource group deletion may take 5-10 minutes to complete"
    echo "   - All data has been permanently deleted"
    echo "   - No ongoing charges will be incurred"
    echo
    echo "🔍 Verification:"
    echo "   - Check Azure Portal to confirm all resources are deleted"
    echo "   - Monitor your billing to ensure charges have stopped"
    echo
    echo "💡 Next Steps:"
    echo "   - Review your Azure subscription for any unexpected charges"
    echo "   - Consider running the deploy script again if you need the solution"
    echo
}

# Main cleanup function
main() {
    log_info "Starting Azure Serverless Graph Analytics cleanup..."
    echo
    
    validate_prerequisites
    set_environment_variables
    check_resource_group
    confirm_deletion
    list_resources
    
    echo
    log_info "Beginning resource deletion..."
    
    delete_event_grid_subscriptions
    delete_function_app
    delete_event_grid_topic
    delete_cosmos_db
    delete_storage_account
    delete_application_insights
    
    # Option to delete entire resource group
    echo
    log_info "Individual resources deleted. You can optionally delete the entire resource group."
    delete_resource_group
    
    verify_cleanup
    cleanup_environment
    
    echo
    display_summary
}

# Handle script arguments
case "${1:-}" in
    --force)
        export FORCE_DELETE="true"
        log_info "Force delete mode enabled"
        ;;
    --help|-h)
        echo "Usage: $0 [--force] [--help]"
        echo
        echo "Options:"
        echo "  --force    Skip confirmation prompts (use with caution)"
        echo "  --help     Show this help message"
        echo
        echo "Environment Variables:"
        echo "  RESOURCE_GROUP    Resource group name (default: rg-graph-analytics)"
        echo "  RANDOM_SUFFIX     Random suffix used in resource names"
        echo "  FORCE_DELETE      Skip confirmations (default: false)"
        echo
        exit 0
        ;;
    "")
        # No arguments, proceed normally
        ;;
    *)
        log_error "Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Execute main function
main