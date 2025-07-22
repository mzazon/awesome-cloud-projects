#!/bin/bash

# Destroy Real-Time Search Application Infrastructure
# This script safely removes all resources created by the deploy.sh script

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Command line arguments
FORCE_DELETE=false
DRY_RUN=false
SKIP_CONFIRMATION=false

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE=true
                SKIP_CONFIRMATION=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --yes|-y)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --help|-h)
                display_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                display_help
                exit 1
                ;;
        esac
    done
}

# Display help information
display_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Destroy Real-Time Search Application infrastructure"
    echo
    echo "OPTIONS:"
    echo "  --force       Force deletion without confirmation (use with caution)"
    echo "  --dry-run     Show what would be deleted without actually deleting"
    echo "  --yes, -y     Skip confirmation prompts"
    echo "  --help, -h    Show this help message"
    echo
    echo "Examples:"
    echo "  $0                    # Interactive deletion with confirmations"
    echo "  $0 --dry-run          # Show what would be deleted"
    echo "  $0 --yes              # Delete with minimal prompts"
    echo "  $0 --force            # Force delete everything immediately"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Try to load from deployment-info.json first
    if [[ -f "deployment-info.json" ]]; then
        log_info "Found deployment-info.json, loading resource names..."
        
        export RESOURCE_GROUP=$(jq -r '.deployment.resourceGroup // empty' deployment-info.json)
        export SEARCH_SERVICE=$(jq -r '.resources.searchService.name // empty' deployment-info.json)
        export SIGNALR_SERVICE=$(jq -r '.resources.signalrService.name // empty' deployment-info.json)
        export STORAGE_ACCOUNT=$(jq -r '.resources.storageAccount.name // empty' deployment-info.json)
        export FUNCTION_APP=$(jq -r '.resources.functionApp.name // empty' deployment-info.json)
        export EVENT_GRID_TOPIC=$(jq -r '.resources.eventGridTopic.name // empty' deployment-info.json)
        export COSMOS_ACCOUNT=$(jq -r '.resources.cosmosAccount.name // empty' deployment-info.json)
        
        if [[ -n "$RESOURCE_GROUP" ]]; then
            log_success "Loaded deployment information from deployment-info.json"
            return 0
        fi
    fi
    
    # Fall back to environment variables or defaults
    log_warning "deployment-info.json not found or incomplete, using environment variables or defaults"
    
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-realtimesearch-demo}"
    export SEARCH_SERVICE="${SEARCH_SERVICE:-}"
    export SIGNALR_SERVICE="${SIGNALR_SERVICE:-}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}"
    export FUNCTION_APP="${FUNCTION_APP:-}"
    export EVENT_GRID_TOPIC="${EVENT_GRID_TOPIC:-}"
    export COSMOS_ACCOUNT="${COSMOS_ACCOUNT:-}"
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log_error "Resource group name not found. Please ensure RESOURCE_GROUP is set or deployment-info.json exists."
        exit 1
    fi
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq not found. Installing jq for JSON parsing..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v brew &> /dev/null; then
            brew install jq
        else
            log_error "Could not install jq. Please install jq manually."
            exit 1
        fi
    fi
    
    log_success "Prerequisites validation completed"
}

# Check if resource group exists
check_resource_group() {
    log_info "Checking if resource group exists..."
    
    if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' does not exist or you don't have access to it"
        return 1
    fi
    
    log_success "Resource group '$RESOURCE_GROUP' found"
    return 0
}

# Discover resources in the resource group
discover_resources() {
    log_info "Discovering resources in resource group '$RESOURCE_GROUP'..."
    
    local resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].{name:name, type:type}' -o json 2>/dev/null || echo '[]')
    
    if [[ "$resources" == "[]" ]]; then
        log_warning "No resources found in resource group '$RESOURCE_GROUP'"
        return 1
    fi
    
    echo "Resources found in '$RESOURCE_GROUP':"
    echo "$resources" | jq -r '.[] | "  - \(.name) (\(.type))"'
    
    return 0
}

# Get user confirmation
get_confirmation() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will permanently delete all resources in the resource group '$RESOURCE_GROUP'"
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    return 0
}

# Delete Event Grid subscriptions first
delete_event_subscriptions() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Event Grid subscriptions"
        return 0
    fi
    
    log_info "Deleting Event Grid subscriptions..."
    
    # List and delete event subscriptions for the topic
    if [[ -n "$EVENT_GRID_TOPIC" ]]; then
        local subscriptions=$(az eventgrid event-subscription list \
            --source-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventGrid/topics/$EVENT_GRID_TOPIC" \
            --query '[].name' -o tsv 2>/dev/null || echo "")
        
        if [[ -n "$subscriptions" ]]; then
            for subscription in $subscriptions; do
                log_info "Deleting event subscription: $subscription"
                az eventgrid event-subscription delete \
                    --source-resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventGrid/topics/$EVENT_GRID_TOPIC" \
                    --name "$subscription" &
            done
            wait
            log_success "Event Grid subscriptions deleted"
        else
            log_info "No Event Grid subscriptions found"
        fi
    fi
}

# Delete Function App
delete_function_app() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Function App: $FUNCTION_APP"
        return 0
    fi
    
    if [[ -n "$FUNCTION_APP" ]] && az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_info "Deleting Function App: $FUNCTION_APP"
        az functionapp delete \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --slot production &
        log_success "Function App deletion initiated: $FUNCTION_APP"
    else
        log_info "Function App not found or already deleted: $FUNCTION_APP"
    fi
}

# Delete Cosmos DB account
delete_cosmos_db() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cosmos DB account: $COSMOS_ACCOUNT"
        return 0
    fi
    
    if [[ -n "$COSMOS_ACCOUNT" ]] && az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_info "Deleting Cosmos DB account: $COSMOS_ACCOUNT"
        az cosmosdb delete \
            --name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes &
        log_success "Cosmos DB deletion initiated: $COSMOS_ACCOUNT"
    else
        log_info "Cosmos DB account not found or already deleted: $COSMOS_ACCOUNT"
    fi
}

# Delete Search service
delete_search_service() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Search service: $SEARCH_SERVICE"
        return 0
    fi
    
    if [[ -n "$SEARCH_SERVICE" ]] && az search service show --name "$SEARCH_SERVICE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_info "Deleting Search service: $SEARCH_SERVICE"
        az search service delete \
            --name "$SEARCH_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --yes &
        log_success "Search service deletion initiated: $SEARCH_SERVICE"
    else
        log_info "Search service not found or already deleted: $SEARCH_SERVICE"
    fi
}

# Delete SignalR service
delete_signalr_service() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete SignalR service: $SIGNALR_SERVICE"
        return 0
    fi
    
    if [[ -n "$SIGNALR_SERVICE" ]] && az signalr show --name "$SIGNALR_SERVICE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_info "Deleting SignalR service: $SIGNALR_SERVICE"
        az signalr delete \
            --name "$SIGNALR_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --yes &
        log_success "SignalR service deletion initiated: $SIGNALR_SERVICE"
    else
        log_info "SignalR service not found or already deleted: $SIGNALR_SERVICE"
    fi
}

# Delete Event Grid topic
delete_event_grid_topic() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Event Grid topic: $EVENT_GRID_TOPIC"
        return 0
    fi
    
    if [[ -n "$EVENT_GRID_TOPIC" ]] && az eventgrid topic show --name "$EVENT_GRID_TOPIC" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_info "Deleting Event Grid topic: $EVENT_GRID_TOPIC"
        az eventgrid topic delete \
            --name "$EVENT_GRID_TOPIC" \
            --resource-group "$RESOURCE_GROUP" &
        log_success "Event Grid topic deletion initiated: $EVENT_GRID_TOPIC"
    else
        log_info "Event Grid topic not found or already deleted: $EVENT_GRID_TOPIC"
    fi
}

# Delete Storage account
delete_storage_account() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete Storage account: $STORAGE_ACCOUNT"
        return 0
    fi
    
    if [[ -n "$STORAGE_ACCOUNT" ]] && az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_info "Deleting Storage account: $STORAGE_ACCOUNT"
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes &
        log_success "Storage account deletion initiated: $STORAGE_ACCOUNT"
    else
        log_info "Storage account not found or already deleted: $STORAGE_ACCOUNT"
    fi
}

# Delete remaining resources
delete_remaining_resources() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete any remaining resources in the resource group"
        return 0
    fi
    
    log_info "Checking for any remaining resources..."
    
    local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query '[].id' -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$remaining_resources" ]]; then
        log_warning "Found remaining resources. Deleting them individually..."
        
        while IFS= read -r resource_id; do
            if [[ -n "$resource_id" ]]; then
                log_info "Deleting resource: $resource_id"
                az resource delete --ids "$resource_id" --yes 2>/dev/null || log_warning "Failed to delete resource: $resource_id"
            fi
        done <<< "$remaining_resources"
        
        # Wait a moment for deletions to process
        sleep 10
    fi
}

# Delete resource group
delete_resource_group() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    log_info "Deleting resource group: $RESOURCE_GROUP"
    
    # Wait for background deletions to complete
    log_info "Waiting for resource deletions to complete..."
    wait
    
    # Delete the resource group
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
    log_info "Note: Complete deletion may take 5-10 minutes"
}

# Clean up local files
cleanup_local_files() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    log_info "Cleaning up local files..."
    
    # Remove deployment info file
    if [[ -f "deployment-info.json" ]]; then
        rm -f deployment-info.json
        log_success "Removed deployment-info.json"
    fi
    
    # Remove any temporary function directories
    if [[ -d "realtime-search-functions" ]]; then
        rm -rf realtime-search-functions
        log_success "Removed function directory"
    fi
    
    # Clear environment variables
    unset RESOURCE_GROUP SEARCH_SERVICE SIGNALR_SERVICE STORAGE_ACCOUNT
    unset FUNCTION_APP EVENT_GRID_TOPIC COSMOS_ACCOUNT
    
    log_success "Local cleanup completed"
}

# Monitor deletion progress
monitor_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_info "Monitoring deletion progress..."
    
    local max_wait=300  # 5 minutes
    local wait_time=0
    local check_interval=30
    
    while [[ $wait_time -lt $max_wait ]]; do
        if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
            log_success "Resource group '$RESOURCE_GROUP' has been successfully deleted"
            return 0
        fi
        
        log_info "Still deleting... ($((wait_time))s elapsed)"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    log_warning "Deletion is taking longer than expected. Check Azure portal for progress."
    log_info "Resource group: $RESOURCE_GROUP"
}

# Display summary
display_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "=== DRY RUN COMPLETED ==="
        log_info "No resources were actually deleted"
        log_info "Run without --dry-run to perform actual deletion"
        return 0
    fi
    
    log_success "=== DESTRUCTION COMPLETED ==="
    echo
    log_info "The following resources have been scheduled for deletion:"
    log_info "- Resource Group: $RESOURCE_GROUP"
    log_info "- Search Service: $SEARCH_SERVICE"
    log_info "- SignalR Service: $SIGNALR_SERVICE"
    log_info "- Function App: $FUNCTION_APP"
    log_info "- Cosmos DB: $COSMOS_ACCOUNT"
    log_info "- Event Grid Topic: $EVENT_GRID_TOPIC"
    log_info "- Storage Account: $STORAGE_ACCOUNT"
    echo
    log_info "Deletion may take several minutes to complete."
    log_info "You can monitor progress in the Azure portal."
    echo
    log_success "All cleanup operations completed successfully!"
}

# Error handling
handle_error() {
    local exit_code=$?
    log_error "An error occurred during destruction (exit code: $exit_code)"
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "Force mode enabled, attempting to continue with resource group deletion..."
        delete_resource_group
    else
        log_error "Destruction failed. You may need to manually clean up remaining resources."
        log_info "Resource group: $RESOURCE_GROUP"
        log_info "Check the Azure portal for remaining resources."
    fi
    
    exit $exit_code
}

# Set up error handling
trap handle_error ERR

# Main destruction function
main() {
    parse_arguments "$@"
    
    log_info "Starting destruction of Real-Time Search Application infrastructure..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "=== DRY RUN MODE - NO RESOURCES WILL BE DELETED ==="
    fi
    
    validate_prerequisites
    load_deployment_info
    
    if ! check_resource_group; then
        log_warning "Resource group not found. Nothing to delete."
        exit 0
    fi
    
    discover_resources
    get_confirmation
    
    # Delete resources in reverse order of creation
    delete_event_subscriptions
    delete_function_app
    delete_cosmos_db
    delete_search_service
    delete_signalr_service
    delete_event_grid_topic
    delete_storage_account
    delete_remaining_resources
    delete_resource_group
    
    if [[ "$DRY_RUN" == "false" ]]; then
        monitor_deletion
    fi
    
    cleanup_local_files
    display_summary
    
    log_success "Destruction completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi