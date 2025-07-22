#!/bin/bash

# Cleanup script for Orchestrating Intelligent Financial Trading Signal Analysis
# with Azure AI Content Understanding and Azure Stream Analytics
# 
# This script safely removes all resources created by the deployment script
# in reverse order to handle dependencies correctly.

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Configuration
CLEANUP_TIMEOUT=1800  # 30 minutes timeout
FORCE_DELETE=false

# Resource names (can be overridden with environment variables)
RESOURCE_GROUP=${RESOURCE_GROUP:-""}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT:-""}
AI_SERVICES_NAME=${AI_SERVICES_NAME:-""}
EVENT_HUB_NAMESPACE=${EVENT_HUB_NAMESPACE:-""}
EVENT_HUB_NAME=${EVENT_HUB_NAME:-"eh-market-data"}
STREAM_ANALYTICS_JOB=${STREAM_ANALYTICS_JOB:-"saj-trading-signals"}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME:-""}
COSMOS_DB_ACCOUNT=${COSMOS_DB_ACCOUNT:-""}
SERVICE_BUS_NAMESPACE=${SERVICE_BUS_NAMESPACE:-""}

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Clean up intelligent financial trading signal analysis system"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -g, --resource-group    Resource group name to clean up"
    echo "  -f, --force            Force deletion without confirmation prompts"
    echo "  -n, --dry-run          Show what would be deleted without actually deleting"
    echo "  -v, --verbose          Enable verbose logging"
    echo "  -t, --timeout          Cleanup timeout in seconds (default: 1800)"
    echo "  --delete-rg            Delete the entire resource group (fastest cleanup)"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP         Resource group name to clean up"
    echo "  STORAGE_ACCOUNT        Storage account name to clean up"
    echo "  AI_SERVICES_NAME       AI services name to clean up"
    echo "  EVENT_HUB_NAMESPACE    Event Hub namespace to clean up"
    echo "  FUNCTION_APP_NAME      Function App name to clean up"
    echo "  COSMOS_DB_ACCOUNT      Cosmos DB account name to clean up"
    echo "  SERVICE_BUS_NAMESPACE  Service Bus namespace to clean up"
    echo ""
    echo "Examples:"
    echo "  $0 -g my-rg                          # Clean up specific resource group"
    echo "  $0 -g my-rg --force                  # Force cleanup without prompts"
    echo "  $0 -g my-rg --delete-rg             # Delete entire resource group"
    echo "  $0 --dry-run                         # Show what would be deleted"
    echo "  RESOURCE_GROUP=my-rg $0             # Use environment variable"
}

# Parse command line arguments
VERBOSE=false
DRY_RUN=false
DELETE_RESOURCE_GROUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -t|--timeout)
            CLEANUP_TIMEOUT="$2"
            shift 2
            ;;
        --delete-rg)
            DELETE_RESOURCE_GROUP=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if resource group is specified
    if [ -z "$RESOURCE_GROUP" ]; then
        error "Resource group must be specified with -g option or RESOURCE_GROUP environment variable"
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP does not exist or is not accessible"
        exit 0
    fi
    
    # Get subscription information
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    
    info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    info "Resource group: $RESOURCE_GROUP"
    
    log "Prerequisites check completed successfully"
}

# Discover resources if not specified
discover_resources() {
    log "Discovering resources in resource group: $RESOURCE_GROUP"
    
    # Find storage accounts
    if [ -z "$STORAGE_ACCOUNT" ]; then
        local storage_accounts=$(az storage account list \
            --resource-group "$RESOURCE_GROUP" \
            --query '[?starts_with(name, `sttrading`)].name' \
            --output tsv)
        
        if [ -n "$storage_accounts" ]; then
            STORAGE_ACCOUNT=$(echo "$storage_accounts" | head -n1)
            info "Found storage account: $STORAGE_ACCOUNT"
        fi
    fi
    
    # Find AI Services
    if [ -z "$AI_SERVICES_NAME" ]; then
        local ai_services=$(az cognitiveservices account list \
            --resource-group "$RESOURCE_GROUP" \
            --query '[?starts_with(name, `ais-trading`)].name' \
            --output tsv)
        
        if [ -n "$ai_services" ]; then
            AI_SERVICES_NAME=$(echo "$ai_services" | head -n1)
            info "Found AI Services: $AI_SERVICES_NAME"
        fi
    fi
    
    # Find Event Hubs namespace
    if [ -z "$EVENT_HUB_NAMESPACE" ]; then
        local eh_namespaces=$(az eventhubs namespace list \
            --resource-group "$RESOURCE_GROUP" \
            --query '[?starts_with(name, `ehns-trading`)].name' \
            --output tsv)
        
        if [ -n "$eh_namespaces" ]; then
            EVENT_HUB_NAMESPACE=$(echo "$eh_namespaces" | head -n1)
            info "Found Event Hubs namespace: $EVENT_HUB_NAMESPACE"
        fi
    fi
    
    # Find Function App
    if [ -z "$FUNCTION_APP_NAME" ]; then
        local function_apps=$(az functionapp list \
            --resource-group "$RESOURCE_GROUP" \
            --query '[?starts_with(name, `func-trading`)].name' \
            --output tsv)
        
        if [ -n "$function_apps" ]; then
            FUNCTION_APP_NAME=$(echo "$function_apps" | head -n1)
            info "Found Function App: $FUNCTION_APP_NAME"
        fi
    fi
    
    # Find Cosmos DB account
    if [ -z "$COSMOS_DB_ACCOUNT" ]; then
        local cosmos_accounts=$(az cosmosdb list \
            --resource-group "$RESOURCE_GROUP" \
            --query '[?starts_with(name, `cosmos-trading`)].name' \
            --output tsv)
        
        if [ -n "$cosmos_accounts" ]; then
            COSMOS_DB_ACCOUNT=$(echo "$cosmos_accounts" | head -n1)
            info "Found Cosmos DB account: $COSMOS_DB_ACCOUNT"
        fi
    fi
    
    # Find Service Bus namespace
    if [ -z "$SERVICE_BUS_NAMESPACE" ]; then
        local sb_namespaces=$(az servicebus namespace list \
            --resource-group "$RESOURCE_GROUP" \
            --query '[?starts_with(name, `sb-trading`)].name' \
            --output tsv)
        
        if [ -n "$sb_namespaces" ]; then
            SERVICE_BUS_NAMESPACE=$(echo "$sb_namespaces" | head -n1)
            info "Found Service Bus namespace: $SERVICE_BUS_NAMESPACE"
        fi
    fi
    
    log "Resource discovery completed"
}

# Confirm deletion
confirm_deletion() {
    if [ "$FORCE_DELETE" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    echo ""
    warn "This will permanently delete the following resources:"
    echo "- Resource Group: $RESOURCE_GROUP"
    if [ -n "$STORAGE_ACCOUNT" ]; then
        echo "- Storage Account: $STORAGE_ACCOUNT"
    fi
    if [ -n "$AI_SERVICES_NAME" ]; then
        echo "- AI Services: $AI_SERVICES_NAME"
    fi
    if [ -n "$EVENT_HUB_NAMESPACE" ]; then
        echo "- Event Hubs Namespace: $EVENT_HUB_NAMESPACE"
    fi
    if [ -n "$FUNCTION_APP_NAME" ]; then
        echo "- Function App: $FUNCTION_APP_NAME"
    fi
    if [ -n "$COSMOS_DB_ACCOUNT" ]; then
        echo "- Cosmos DB Account: $COSMOS_DB_ACCOUNT"
    fi
    if [ -n "$SERVICE_BUS_NAMESPACE" ]; then
        echo "- Service Bus Namespace: $SERVICE_BUS_NAMESPACE"
    fi
    echo "- Stream Analytics Job: $STREAM_ANALYTICS_JOB"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Delete entire resource group
delete_resource_group() {
    log "Deleting entire resource group: $RESOURCE_GROUP"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return
    fi
    
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    log "Resource group deletion initiated (running in background)"
    
    # Wait for deletion to complete
    log "Waiting for resource group deletion to complete..."
    local timeout=0
    while az group show --name "$RESOURCE_GROUP" &> /dev/null; do
        if [ $timeout -ge $CLEANUP_TIMEOUT ]; then
            warn "Resource group deletion timed out after $CLEANUP_TIMEOUT seconds"
            break
        fi
        sleep 30
        timeout=$((timeout + 30))
        info "Still waiting for resource group deletion..."
    done
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "Resource group deleted successfully"
    else
        warn "Resource group may still exist - check Azure portal"
    fi
}

# Stop Stream Analytics job
stop_stream_analytics() {
    log "Stopping Stream Analytics job: $STREAM_ANALYTICS_JOB"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would stop Stream Analytics job: $STREAM_ANALYTICS_JOB"
        return
    fi
    
    if az stream-analytics job show --name "$STREAM_ANALYTICS_JOB" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        # Stop the job first
        az stream-analytics job stop \
            --name "$STREAM_ANALYTICS_JOB" \
            --resource-group "$RESOURCE_GROUP" || true
        
        # Wait a bit for job to stop
        sleep 30
        
        # Delete the job
        az stream-analytics job delete \
            --name "$STREAM_ANALYTICS_JOB" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        
        log "Stream Analytics job deleted successfully"
    else
        info "Stream Analytics job $STREAM_ANALYTICS_JOB not found"
    fi
}

# Delete Function App
delete_function_app() {
    if [ -z "$FUNCTION_APP_NAME" ]; then
        info "No Function App to delete"
        return
    fi
    
    log "Deleting Function App: $FUNCTION_APP_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would delete Function App: $FUNCTION_APP_NAME"
        return
    fi
    
    if az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        # Delete Function App
        az functionapp delete \
            --name "$FUNCTION_APP_NAME" \
            --resource-group "$RESOURCE_GROUP"
        
        # Delete hosting plan
        az functionapp plan delete \
            --name "plan-$FUNCTION_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        
        log "Function App and hosting plan deleted successfully"
    else
        info "Function App $FUNCTION_APP_NAME not found"
    fi
}

# Delete Service Bus
delete_service_bus() {
    if [ -z "$SERVICE_BUS_NAMESPACE" ]; then
        info "No Service Bus namespace to delete"
        return
    fi
    
    log "Deleting Service Bus namespace: $SERVICE_BUS_NAMESPACE"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would delete Service Bus namespace: $SERVICE_BUS_NAMESPACE"
        return
    fi
    
    if az servicebus namespace show --name "$SERVICE_BUS_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az servicebus namespace delete \
            --name "$SERVICE_BUS_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP"
        
        log "Service Bus namespace deleted successfully"
    else
        info "Service Bus namespace $SERVICE_BUS_NAMESPACE not found"
    fi
}

# Delete Cosmos DB
delete_cosmos_db() {
    if [ -z "$COSMOS_DB_ACCOUNT" ]; then
        info "No Cosmos DB account to delete"
        return
    fi
    
    log "Deleting Cosmos DB account: $COSMOS_DB_ACCOUNT"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would delete Cosmos DB account: $COSMOS_DB_ACCOUNT"
        return
    fi
    
    if az cosmosdb show --name "$COSMOS_DB_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az cosmosdb delete \
            --name "$COSMOS_DB_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        
        log "Cosmos DB account deleted successfully"
    else
        info "Cosmos DB account $COSMOS_DB_ACCOUNT not found"
    fi
}

# Delete Event Hubs
delete_event_hubs() {
    if [ -z "$EVENT_HUB_NAMESPACE" ]; then
        info "No Event Hubs namespace to delete"
        return
    fi
    
    log "Deleting Event Hubs namespace: $EVENT_HUB_NAMESPACE"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would delete Event Hubs namespace: $EVENT_HUB_NAMESPACE"
        return
    fi
    
    if az eventhubs namespace show --name "$EVENT_HUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az eventhubs namespace delete \
            --name "$EVENT_HUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP"
        
        log "Event Hubs namespace deleted successfully"
    else
        info "Event Hubs namespace $EVENT_HUB_NAMESPACE not found"
    fi
}

# Delete AI Services
delete_ai_services() {
    if [ -z "$AI_SERVICES_NAME" ]; then
        info "No AI Services to delete"
        return
    fi
    
    log "Deleting AI Services: $AI_SERVICES_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would delete AI Services: $AI_SERVICES_NAME"
        return
    fi
    
    if az cognitiveservices account show --name "$AI_SERVICES_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az cognitiveservices account delete \
            --name "$AI_SERVICES_NAME" \
            --resource-group "$RESOURCE_GROUP"
        
        log "AI Services deleted successfully"
    else
        info "AI Services $AI_SERVICES_NAME not found"
    fi
}

# Delete Storage Account
delete_storage_account() {
    if [ -z "$STORAGE_ACCOUNT" ]; then
        info "No Storage Account to delete"
        return
    fi
    
    log "Deleting Storage Account: $STORAGE_ACCOUNT"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would delete Storage Account: $STORAGE_ACCOUNT"
        return
    fi
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        
        log "Storage Account deleted successfully"
    else
        info "Storage Account $STORAGE_ACCOUNT not found"
    fi
}

# Clean up individual resources
cleanup_individual_resources() {
    log "Cleaning up individual resources..."
    
    # Delete resources in reverse order of creation to handle dependencies
    stop_stream_analytics
    delete_function_app
    delete_service_bus
    delete_cosmos_db
    delete_event_hubs
    delete_ai_services
    delete_storage_account
    
    log "Individual resource cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would verify cleanup"
        return
    fi
    
    local remaining_resources=0
    
    # Check if resource group still exists
    if [ "$DELETE_RESOURCE_GROUP" = true ]; then
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            warn "Resource group $RESOURCE_GROUP still exists"
            remaining_resources=$((remaining_resources + 1))
        fi
    else
        # Check individual resources
        if [ -n "$STORAGE_ACCOUNT" ] && az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            warn "Storage Account $STORAGE_ACCOUNT still exists"
            remaining_resources=$((remaining_resources + 1))
        fi
        
        if [ -n "$AI_SERVICES_NAME" ] && az cognitiveservices account show --name "$AI_SERVICES_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            warn "AI Services $AI_SERVICES_NAME still exists"
            remaining_resources=$((remaining_resources + 1))
        fi
        
        if [ -n "$EVENT_HUB_NAMESPACE" ] && az eventhubs namespace show --name "$EVENT_HUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            warn "Event Hubs namespace $EVENT_HUB_NAMESPACE still exists"
            remaining_resources=$((remaining_resources + 1))
        fi
        
        if [ -n "$FUNCTION_APP_NAME" ] && az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            warn "Function App $FUNCTION_APP_NAME still exists"
            remaining_resources=$((remaining_resources + 1))
        fi
        
        if [ -n "$COSMOS_DB_ACCOUNT" ] && az cosmosdb show --name "$COSMOS_DB_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            warn "Cosmos DB account $COSMOS_DB_ACCOUNT still exists"
            remaining_resources=$((remaining_resources + 1))
        fi
        
        if [ -n "$SERVICE_BUS_NAMESPACE" ] && az servicebus namespace show --name "$SERVICE_BUS_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            warn "Service Bus namespace $SERVICE_BUS_NAMESPACE still exists"
            remaining_resources=$((remaining_resources + 1))
        fi
        
        if az stream-analytics job show --name "$STREAM_ANALYTICS_JOB" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            warn "Stream Analytics job $STREAM_ANALYTICS_JOB still exists"
            remaining_resources=$((remaining_resources + 1))
        fi
    fi
    
    if [ $remaining_resources -eq 0 ]; then
        log "Cleanup verification successful - no remaining resources found"
    else
        warn "Cleanup verification found $remaining_resources remaining resources"
        warn "You may need to manually delete remaining resources or wait for background operations to complete"
    fi
}

# Display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "Resource Group: $RESOURCE_GROUP"
    if [ "$DELETE_RESOURCE_GROUP" = true ]; then
        echo "Action: Deleted entire resource group"
    else
        echo "Action: Deleted individual resources"
        echo "Resources cleaned up:"
        if [ -n "$STORAGE_ACCOUNT" ]; then
            echo "- Storage Account: $STORAGE_ACCOUNT"
        fi
        if [ -n "$AI_SERVICES_NAME" ]; then
            echo "- AI Services: $AI_SERVICES_NAME"
        fi
        if [ -n "$EVENT_HUB_NAMESPACE" ]; then
            echo "- Event Hubs Namespace: $EVENT_HUB_NAMESPACE"
        fi
        if [ -n "$FUNCTION_APP_NAME" ]; then
            echo "- Function App: $FUNCTION_APP_NAME"
        fi
        if [ -n "$COSMOS_DB_ACCOUNT" ]; then
            echo "- Cosmos DB Account: $COSMOS_DB_ACCOUNT"
        fi
        if [ -n "$SERVICE_BUS_NAMESPACE" ]; then
            echo "- Service Bus Namespace: $SERVICE_BUS_NAMESPACE"
        fi
        echo "- Stream Analytics Job: $STREAM_ANALYTICS_JOB"
    fi
    echo ""
    
    if [ "$DRY_RUN" = false ]; then
        echo "Important Notes:"
        echo "- Some resources may take additional time to fully delete"
        echo "- Check Azure portal to verify complete removal"
        echo "- Soft-deleted resources may still appear in some views"
        echo "- Monitor your Azure billing to confirm resource deletion"
    fi
}

# Main cleanup function
main() {
    log "Starting cleanup of Intelligent Financial Trading Signal Analysis System"
    
    # Set timeout for the entire cleanup
    timeout $CLEANUP_TIMEOUT bash -c '
        check_prerequisites
        
        if [ "$DELETE_RESOURCE_GROUP" = true ]; then
            confirm_deletion
            delete_resource_group
        else
            discover_resources
            confirm_deletion
            cleanup_individual_resources
        fi
        
        verify_cleanup
    ' || {
        warn "Cleanup timed out after $CLEANUP_TIMEOUT seconds"
        warn "Some resources may still be in the process of deletion"
    }
    
    display_summary
    
    if [ "$DRY_RUN" = false ]; then
        log "Cleanup completed successfully!"
        log "Please verify in Azure portal that all resources have been removed."
    else
        log "Dry run completed. No resources were actually deleted."
    fi
}

# Run main function
main "$@"