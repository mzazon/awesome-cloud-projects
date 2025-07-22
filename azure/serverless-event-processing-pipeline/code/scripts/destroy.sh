#!/bin/bash

# destroy.sh - Clean up Azure Functions and Event Hubs resources
# This script removes all resources created by the real-time data processing recipe

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate Azure CLI authentication
validate_azure_auth() {
    log "Validating Azure CLI authentication..."
    
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show >/dev/null 2>&1; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    
    info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
}

# Function to detect resource group from environment or prompt user
detect_resource_group() {
    log "Detecting resource group to clean up..."
    
    # Check if resource group is set in environment
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        info "Using resource group from environment: $RESOURCE_GROUP"
        return 0
    fi
    
    # Look for resource groups with recipe tags
    local recipe_groups=$(az group list --query "[?tags.purpose=='recipe'].name" --output tsv)
    
    if [[ -z "$recipe_groups" ]]; then
        error "No recipe resource groups found. Please set RESOURCE_GROUP environment variable."
        exit 1
    fi
    
    # If only one recipe group, use it
    local group_count=$(echo "$recipe_groups" | wc -l)
    if [[ $group_count -eq 1 ]]; then
        export RESOURCE_GROUP="$recipe_groups"
        info "Auto-detected resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Multiple groups found, prompt user
    echo "Multiple recipe resource groups found:"
    echo "$recipe_groups"
    echo
    read -p "Enter the resource group name to delete: " RESOURCE_GROUP
    export RESOURCE_GROUP
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        error "No resource group specified"
        exit 1
    fi
}

# Function to get resource names from resource group
get_resource_names() {
    log "Getting resource names from resource group..."
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        error "Resource group '$RESOURCE_GROUP' not found"
        exit 1
    fi
    
    # Get Function App name
    FUNCTION_APP_NAME=$(az functionapp list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Get Event Hubs namespace
    EVENTHUB_NAMESPACE=$(az eventhubs namespace list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Get Storage Account name
    STORAGE_ACCOUNT_NAME=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Get Application Insights name
    APP_INSIGHTS_NAME=$(az monitor app-insights component list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Display what was found
    info "Found resources in resource group '$RESOURCE_GROUP':"
    [[ -n "$FUNCTION_APP_NAME" ]] && info "  Function App: $FUNCTION_APP_NAME"
    [[ -n "$EVENTHUB_NAMESPACE" ]] && info "  Event Hub Namespace: $EVENTHUB_NAMESPACE"
    [[ -n "$STORAGE_ACCOUNT_NAME" ]] && info "  Storage Account: $STORAGE_ACCOUNT_NAME"
    [[ -n "$APP_INSIGHTS_NAME" ]] && info "  Application Insights: $APP_INSIGHTS_NAME"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        warn "Force delete enabled - skipping confirmation"
        return 0
    fi
    
    echo
    echo "=================================="
    echo "        DELETION WARNING"
    echo "=================================="
    echo "This will permanently delete the following resources:"
    echo "- Resource Group: $RESOURCE_GROUP"
    [[ -n "$FUNCTION_APP_NAME" ]] && echo "- Function App: $FUNCTION_APP_NAME"
    [[ -n "$EVENTHUB_NAMESPACE" ]] && echo "- Event Hub Namespace: $EVENTHUB_NAMESPACE"
    [[ -n "$STORAGE_ACCOUNT_NAME" ]] && echo "- Storage Account: $STORAGE_ACCOUNT_NAME"
    [[ -n "$APP_INSIGHTS_NAME" ]] && echo "- Application Insights: $APP_INSIGHTS_NAME"
    echo "=================================="
    echo
    
    read -p "Are you sure you want to delete these resources? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed, proceeding with cleanup..."
}

# Function to delete Function App
delete_function_app() {
    if [[ -z "$FUNCTION_APP_NAME" ]]; then
        info "No Function App found, skipping..."
        return 0
    fi
    
    log "Deleting Function App: $FUNCTION_APP_NAME"
    
    # Check if Function App exists
    if ! az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warn "Function App '$FUNCTION_APP_NAME' not found, skipping..."
        return 0
    fi
    
    # Stop the Function App first
    info "Stopping Function App..."
    az functionapp stop --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null || true
    
    # Delete Function App
    az functionapp delete --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --output none
    
    if [[ $? -eq 0 ]]; then
        log "Function App '$FUNCTION_APP_NAME' deleted successfully"
    else
        error "Failed to delete Function App '$FUNCTION_APP_NAME'"
        return 1
    fi
}

# Function to delete Event Hubs namespace
delete_event_hubs() {
    if [[ -z "$EVENTHUB_NAMESPACE" ]]; then
        info "No Event Hubs namespace found, skipping..."
        return 0
    fi
    
    log "Deleting Event Hubs namespace: $EVENTHUB_NAMESPACE"
    
    # Check if Event Hubs namespace exists
    if ! az eventhubs namespace show --name "$EVENTHUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warn "Event Hubs namespace '$EVENTHUB_NAMESPACE' not found, skipping..."
        return 0
    fi
    
    # Delete Event Hubs namespace (this also deletes all Event Hubs within it)
    az eventhubs namespace delete --name "$EVENTHUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" --output none
    
    if [[ $? -eq 0 ]]; then
        log "Event Hubs namespace '$EVENTHUB_NAMESPACE' deleted successfully"
    else
        error "Failed to delete Event Hubs namespace '$EVENTHUB_NAMESPACE'"
        return 1
    fi
}

# Function to delete Storage Account
delete_storage_account() {
    if [[ -z "$STORAGE_ACCOUNT_NAME" ]]; then
        info "No Storage Account found, skipping..."
        return 0
    fi
    
    log "Deleting Storage Account: $STORAGE_ACCOUNT_NAME"
    
    # Check if Storage Account exists
    if ! az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warn "Storage Account '$STORAGE_ACCOUNT_NAME' not found, skipping..."
        return 0
    fi
    
    # Delete Storage Account
    az storage account delete --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" --yes --output none
    
    if [[ $? -eq 0 ]]; then
        log "Storage Account '$STORAGE_ACCOUNT_NAME' deleted successfully"
    else
        error "Failed to delete Storage Account '$STORAGE_ACCOUNT_NAME'"
        return 1
    fi
}

# Function to delete Application Insights
delete_app_insights() {
    if [[ -z "$APP_INSIGHTS_NAME" ]]; then
        info "No Application Insights found, skipping..."
        return 0
    fi
    
    log "Deleting Application Insights: $APP_INSIGHTS_NAME"
    
    # Check if Application Insights exists
    if ! az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warn "Application Insights '$APP_INSIGHTS_NAME' not found, skipping..."
        return 0
    fi
    
    # Delete Application Insights
    az monitor app-insights component delete --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" --output none
    
    if [[ $? -eq 0 ]]; then
        log "Application Insights '$APP_INSIGHTS_NAME' deleted successfully"
    else
        error "Failed to delete Application Insights '$APP_INSIGHTS_NAME'"
        return 1
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group: $RESOURCE_GROUP"
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warn "Resource group '$RESOURCE_GROUP' not found, skipping..."
        return 0
    fi
    
    # Delete resource group and all contained resources
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait --output none
    
    if [[ $? -eq 0 ]]; then
        log "Resource group '$RESOURCE_GROUP' deletion initiated"
        info "Note: Resource group deletion may take several minutes to complete"
    else
        error "Failed to delete resource group '$RESOURCE_GROUP'"
        return 1
    fi
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    # Wait a moment for deletion to propagate
    sleep 5
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        info "Resource group '$RESOURCE_GROUP' still exists (deletion in progress)"
        
        # Show remaining resources
        local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        if [[ -n "$remaining_resources" ]]; then
            info "Remaining resources being deleted:"
            echo "$remaining_resources" | while read -r resource; do
                info "  - $resource"
            done
        fi
        
        info "You can check deletion progress in the Azure portal"
        echo "Portal link: https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
    else
        log "Resource group '$RESOURCE_GROUP' has been deleted successfully"
    fi
}

# Function to clean up environment variables
cleanup_environment() {
    log "Cleaning up environment variables..."
    
    # List of variables to unset
    local vars_to_unset=(
        "RESOURCE_GROUP"
        "EVENTHUB_NAMESPACE"
        "EVENTHUB_NAME"
        "FUNCTION_APP_NAME"
        "STORAGE_ACCOUNT_NAME"
        "APP_INSIGHTS_NAME"
        "SUBSCRIPTION_ID"
    )
    
    for var in "${vars_to_unset[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            info "Unsetting $var"
            unset "$var"
        fi
    done
    
    log "Environment variables cleaned up"
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup completed successfully!"
    echo
    echo "=================================="
    echo "        CLEANUP SUMMARY"
    echo "=================================="
    echo "The following resources have been deleted:"
    echo "- Resource Group: $RESOURCE_GROUP"
    [[ -n "${FUNCTION_APP_NAME:-}" ]] && echo "- Function App: $FUNCTION_APP_NAME"
    [[ -n "${EVENTHUB_NAMESPACE:-}" ]] && echo "- Event Hub Namespace: $EVENTHUB_NAMESPACE"
    [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]] && echo "- Storage Account: $STORAGE_ACCOUNT_NAME"
    [[ -n "${APP_INSIGHTS_NAME:-}" ]] && echo "- Application Insights: $APP_INSIGHTS_NAME"
    echo "=================================="
    echo
    echo "Note: Resource deletion may take several minutes to complete."
    echo "You can verify deletion status in the Azure portal."
}

# Function to handle individual resource deletion
delete_individual_resources() {
    log "Deleting individual resources..."
    
    # Delete resources in reverse order of creation
    local deletion_errors=0
    
    # Delete Function App
    if ! delete_function_app; then
        ((deletion_errors++))
    fi
    
    # Delete Event Hubs namespace
    if ! delete_event_hubs; then
        ((deletion_errors++))
    fi
    
    # Delete Storage Account
    if ! delete_storage_account; then
        ((deletion_errors++))
    fi
    
    # Delete Application Insights
    if ! delete_app_insights; then
        ((deletion_errors++))
    fi
    
    if [[ $deletion_errors -eq 0 ]]; then
        log "All individual resources deleted successfully"
    else
        warn "$deletion_errors resource(s) failed to delete"
    fi
}

# Main execution
main() {
    log "Starting Azure Functions and Event Hubs cleanup..."
    
    validate_azure_auth
    detect_resource_group
    get_resource_names
    confirm_deletion
    
    if [[ "${DELETE_INDIVIDUAL_RESOURCES:-false}" == "true" ]]; then
        delete_individual_resources
    else
        delete_resource_group
    fi
    
    verify_deletion
    cleanup_environment
    display_summary
    
    log "Cleanup process completed!"
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Clean up Azure Functions and Event Hubs resources"
    echo
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP        Resource group to delete (auto-detected if not set)"
    echo
    echo "Options:"
    echo "  --help, -h            Show this help message"
    echo "  --force               Skip confirmation prompts"
    echo "  --individual          Delete individual resources instead of resource group"
    echo "  --dry-run             Show what would be deleted without actually deleting"
    echo
    echo "Examples:"
    echo "  $0                    # Interactive cleanup with confirmation"
    echo "  $0 --force            # Force cleanup without confirmation"
    echo "  $0 --individual       # Delete individual resources instead of resource group"
    echo "  RESOURCE_GROUP=my-rg $0 --force  # Delete specific resource group"
}

# Handle script arguments
FORCE_DELETE=false
DELETE_INDIVIDUAL_RESOURCES=false
DRY_RUN=false

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
        --individual)
            DELETE_INDIVIDUAL_RESOURCES=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Handle dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN MODE - No resources will be deleted"
    validate_azure_auth
    detect_resource_group
    get_resource_names
    
    echo
    echo "Would delete the following resources:"
    echo "- Resource Group: $RESOURCE_GROUP"
    [[ -n "${FUNCTION_APP_NAME:-}" ]] && echo "- Function App: $FUNCTION_APP_NAME"
    [[ -n "${EVENTHUB_NAMESPACE:-}" ]] && echo "- Event Hub Namespace: $EVENTHUB_NAMESPACE"
    [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]] && echo "- Storage Account: $STORAGE_ACCOUNT_NAME"
    [[ -n "${APP_INSIGHTS_NAME:-}" ]] && echo "- Application Insights: $APP_INSIGHTS_NAME"
    echo
    echo "Run without --dry-run to actually delete these resources."
    exit 0
fi

# Run main function
main "$@"