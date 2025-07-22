#!/bin/bash

# Azure Multi-Channel Customer Communication Platform - Cleanup Script
# This script removes all resources created for the communication platform
# including Communication Services, Event Grid, Functions, and Cosmos DB

set -e  # Exit on any error
set -o pipefail  # Exit if any command in pipeline fails

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Default values - can be overridden by environment variables
    export RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-multi-channel-comms"}
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # If resource names are not provided, we'll try to discover them
    if [ -z "$COMM_SERVICE_NAME" ] || [ -z "$EVENTGRID_TOPIC_NAME" ] || [ -z "$FUNCTION_APP_NAME" ] || [ -z "$COSMOS_ACCOUNT_NAME" ] || [ -z "$STORAGE_ACCOUNT_NAME" ]; then
        log "Resource names not provided, attempting to discover them..."
        discover_resources
    fi
    
    log "Environment variables configured:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Communication Services: ${COMM_SERVICE_NAME:-"Not found"}"
    log "  Event Grid Topic: ${EVENTGRID_TOPIC_NAME:-"Not found"}"
    log "  Function App: ${FUNCTION_APP_NAME:-"Not found"}"
    log "  Cosmos DB: ${COSMOS_ACCOUNT_NAME:-"Not found"}"
    log "  Storage Account: ${STORAGE_ACCOUNT_NAME:-"Not found"}"
}

# Function to discover resources in the resource group
discover_resources() {
    log "Discovering resources in resource group: ${RESOURCE_GROUP}"
    
    # Check if resource group exists
    if ! az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} does not exist"
        return
    fi
    
    # Discover Communication Services
    if [ -z "$COMM_SERVICE_NAME" ]; then
        COMM_SERVICE_NAME=$(az communication list \
            --resource-group ${RESOURCE_GROUP} \
            --query "[0].name" \
            --output tsv 2>/dev/null || echo "")
    fi
    
    # Discover Event Grid Topics
    if [ -z "$EVENTGRID_TOPIC_NAME" ]; then
        EVENTGRID_TOPIC_NAME=$(az eventgrid topic list \
            --resource-group ${RESOURCE_GROUP} \
            --query "[0].name" \
            --output tsv 2>/dev/null || echo "")
    fi
    
    # Discover Function Apps
    if [ -z "$FUNCTION_APP_NAME" ]; then
        FUNCTION_APP_NAME=$(az functionapp list \
            --resource-group ${RESOURCE_GROUP} \
            --query "[0].name" \
            --output tsv 2>/dev/null || echo "")
    fi
    
    # Discover Cosmos DB accounts
    if [ -z "$COSMOS_ACCOUNT_NAME" ]; then
        COSMOS_ACCOUNT_NAME=$(az cosmosdb list \
            --resource-group ${RESOURCE_GROUP} \
            --query "[0].name" \
            --output tsv 2>/dev/null || echo "")
    fi
    
    # Discover Storage accounts
    if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
        STORAGE_ACCOUNT_NAME=$(az storage account list \
            --resource-group ${RESOURCE_GROUP} \
            --query "[?starts_with(name, 'stacomms')].name | [0]" \
            --output tsv 2>/dev/null || echo "")
    fi
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warning "WARNING: This will permanently delete the following resources:"
    echo "  Resource Group: ${RESOURCE_GROUP}"
    [ -n "$COMM_SERVICE_NAME" ] && echo "  Communication Services: ${COMM_SERVICE_NAME}"
    [ -n "$EVENTGRID_TOPIC_NAME" ] && echo "  Event Grid Topic: ${EVENTGRID_TOPIC_NAME}"
    [ -n "$FUNCTION_APP_NAME" ] && echo "  Function App: ${FUNCTION_APP_NAME}"
    [ -n "$COSMOS_ACCOUNT_NAME" ] && echo "  Cosmos DB: ${COSMOS_ACCOUNT_NAME}"
    [ -n "$STORAGE_ACCOUNT_NAME" ] && echo "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo ""
    
    # Check for --force flag
    if [ "$1" = "--force" ] || [ "$FORCE_DELETE" = "true" ]; then
        warning "Force deletion requested, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to delete these resources? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
}

# Function to remove Event Grid subscriptions
remove_event_subscriptions() {
    log "Removing Event Grid subscriptions..."
    
    if [ -z "$EVENTGRID_TOPIC_NAME" ]; then
        warning "Event Grid topic name not found, skipping subscription removal"
        return
    fi
    
    # List and delete event subscriptions
    local subscriptions=$(az eventgrid event-subscription list \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENTGRID_TOPIC_NAME}" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "$subscriptions" ]; then
        for subscription in $subscriptions; do
            log "Deleting Event Grid subscription: $subscription"
            az eventgrid event-subscription delete \
                --name "$subscription" \
                --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENTGRID_TOPIC_NAME}" \
                --output none 2>/dev/null || warning "Failed to delete subscription: $subscription"
        done
        success "Event Grid subscriptions removed"
    else
        log "No Event Grid subscriptions found"
    fi
}

# Function to remove Function App
remove_function_app() {
    log "Removing Function App..."
    
    if [ -z "$FUNCTION_APP_NAME" ]; then
        warning "Function App name not found, skipping"
        return
    fi
    
    if az functionapp show --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log "Deleting Function App: ${FUNCTION_APP_NAME}"
        az functionapp delete \
            --name ${FUNCTION_APP_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --output none 2>/dev/null || warning "Failed to delete Function App"
        
        success "Function App deleted: ${FUNCTION_APP_NAME}"
    else
        log "Function App not found: ${FUNCTION_APP_NAME}"
    fi
}

# Function to remove Event Grid topic
remove_event_grid() {
    log "Removing Event Grid topic..."
    
    if [ -z "$EVENTGRID_TOPIC_NAME" ]; then
        warning "Event Grid topic name not found, skipping"
        return
    fi
    
    if az eventgrid topic show --name ${EVENTGRID_TOPIC_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log "Deleting Event Grid topic: ${EVENTGRID_TOPIC_NAME}"
        az eventgrid topic delete \
            --name ${EVENTGRID_TOPIC_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --output none 2>/dev/null || warning "Failed to delete Event Grid topic"
        
        success "Event Grid topic deleted: ${EVENTGRID_TOPIC_NAME}"
    else
        log "Event Grid topic not found: ${EVENTGRID_TOPIC_NAME}"
    fi
}

# Function to remove Cosmos DB
remove_cosmos_db() {
    log "Removing Cosmos DB account..."
    
    if [ -z "$COSMOS_ACCOUNT_NAME" ]; then
        warning "Cosmos DB account name not found, skipping"
        return
    fi
    
    if az cosmosdb show --name ${COSMOS_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log "Deleting Cosmos DB account: ${COSMOS_ACCOUNT_NAME}"
        az cosmosdb delete \
            --name ${COSMOS_ACCOUNT_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --yes \
            --output none 2>/dev/null || warning "Failed to delete Cosmos DB account"
        
        success "Cosmos DB account deleted: ${COSMOS_ACCOUNT_NAME}"
    else
        log "Cosmos DB account not found: ${COSMOS_ACCOUNT_NAME}"
    fi
}

# Function to remove Communication Services
remove_communication_services() {
    log "Removing Communication Services..."
    
    if [ -z "$COMM_SERVICE_NAME" ]; then
        warning "Communication Services name not found, skipping"
        return
    fi
    
    if az communication show --name ${COMM_SERVICE_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log "Deleting Communication Services: ${COMM_SERVICE_NAME}"
        az communication delete \
            --name ${COMM_SERVICE_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --yes \
            --output none 2>/dev/null || warning "Failed to delete Communication Services"
        
        success "Communication Services deleted: ${COMM_SERVICE_NAME}"
    else
        log "Communication Services not found: ${COMM_SERVICE_NAME}"
    fi
}

# Function to remove Storage Account
remove_storage_account() {
    log "Removing Storage Account..."
    
    if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
        warning "Storage Account name not found, skipping"
        return
    fi
    
    if az storage account show --name ${STORAGE_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log "Deleting Storage Account: ${STORAGE_ACCOUNT_NAME}"
        az storage account delete \
            --name ${STORAGE_ACCOUNT_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --yes \
            --output none 2>/dev/null || warning "Failed to delete Storage Account"
        
        success "Storage Account deleted: ${STORAGE_ACCOUNT_NAME}"
    else
        log "Storage Account not found: ${STORAGE_ACCOUNT_NAME}"
    fi
}

# Function to remove resource group
remove_resource_group() {
    log "Removing Resource Group..."
    
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        log "Deleting Resource Group: ${RESOURCE_GROUP}"
        az group delete \
            --name ${RESOURCE_GROUP} \
            --yes \
            --no-wait \
            --output none 2>/dev/null || warning "Failed to delete Resource Group"
        
        success "Resource Group deletion initiated: ${RESOURCE_GROUP}"
        log "Note: Resource group deletion is running in the background"
    else
        log "Resource Group not found: ${RESOURCE_GROUP}"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local remaining_resources=0
    
    # Check Communication Services
    if [ -n "$COMM_SERVICE_NAME" ] && az communication show --name ${COMM_SERVICE_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        warning "Communication Services still exists: ${COMM_SERVICE_NAME}"
        ((remaining_resources++))
    fi
    
    # Check Event Grid Topic
    if [ -n "$EVENTGRID_TOPIC_NAME" ] && az eventgrid topic show --name ${EVENTGRID_TOPIC_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        warning "Event Grid topic still exists: ${EVENTGRID_TOPIC_NAME}"
        ((remaining_resources++))
    fi
    
    # Check Function App
    if [ -n "$FUNCTION_APP_NAME" ] && az functionapp show --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        warning "Function App still exists: ${FUNCTION_APP_NAME}"
        ((remaining_resources++))
    fi
    
    # Check Cosmos DB
    if [ -n "$COSMOS_ACCOUNT_NAME" ] && az cosmosdb show --name ${COSMOS_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        warning "Cosmos DB account still exists: ${COSMOS_ACCOUNT_NAME}"
        ((remaining_resources++))
    fi
    
    # Check Storage Account
    if [ -n "$STORAGE_ACCOUNT_NAME" ] && az storage account show --name ${STORAGE_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        warning "Storage Account still exists: ${STORAGE_ACCOUNT_NAME}"
        ((remaining_resources++))
    fi
    
    if [ $remaining_resources -eq 0 ]; then
        success "All resources have been successfully removed"
    else
        warning "$remaining_resources resources may still exist. Check Azure portal for details."
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    log "Cleanup Summary:"
    echo "======================================"
    echo "The following resources have been deleted or are being deleted:"
    [ -n "$COMM_SERVICE_NAME" ] && echo "✓ Communication Services: ${COMM_SERVICE_NAME}"
    [ -n "$EVENTGRID_TOPIC_NAME" ] && echo "✓ Event Grid Topic: ${EVENTGRID_TOPIC_NAME}"
    [ -n "$FUNCTION_APP_NAME" ] && echo "✓ Function App: ${FUNCTION_APP_NAME}"
    [ -n "$COSMOS_ACCOUNT_NAME" ] && echo "✓ Cosmos DB Account: ${COSMOS_ACCOUNT_NAME}"
    [ -n "$STORAGE_ACCOUNT_NAME" ] && echo "✓ Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "✓ Resource Group: ${RESOURCE_GROUP} (deletion in progress)"
    echo "======================================"
    echo ""
    echo "Notes:"
    echo "- Resource group deletion is asynchronous and may take several minutes"
    echo "- You can monitor deletion progress in the Azure portal"
    echo "- Some resources may have soft-delete enabled and can be recovered if needed"
    echo ""
    success "Multi-channel communication platform cleanup completed!"
}

# Function to display help
show_help() {
    echo "Azure Multi-Channel Communication Platform - Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force                Skip confirmation prompts"
    echo "  --resource-group NAME  Specify resource group name (default: rg-multi-channel-comms)"
    echo "  --help                 Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP         Resource group name"
    echo "  COMM_SERVICE_NAME      Communication Services name"
    echo "  EVENTGRID_TOPIC_NAME   Event Grid topic name"
    echo "  FUNCTION_APP_NAME      Function App name"
    echo "  COSMOS_ACCOUNT_NAME    Cosmos DB account name"
    echo "  STORAGE_ACCOUNT_NAME   Storage account name"
    echo "  FORCE_DELETE          Set to 'true' to skip confirmations"
    echo ""
    echo "Examples:"
    echo "  $0                              # Interactive deletion"
    echo "  $0 --force                      # Skip confirmations"
    echo "  $0 --resource-group my-rg       # Specify resource group"
    echo "  FORCE_DELETE=true $0            # Use environment variable"
    echo ""
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE="true"
                shift
                ;;
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Main execution
main() {
    log "Starting Azure Multi-Channel Communication Platform cleanup..."
    
    parse_arguments "$@"
    check_prerequisites
    setup_environment
    confirm_deletion "$@"
    
    # Remove resources in the correct order (reverse of creation)
    remove_event_subscriptions
    remove_function_app
    remove_event_grid
    remove_cosmos_db
    remove_communication_services
    remove_storage_account
    
    # Option to remove entire resource group
    echo ""
    if [ "$FORCE_DELETE" = "true" ]; then
        remove_resource_group
    else
        read -p "Do you want to delete the entire resource group '${RESOURCE_GROUP}'? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            remove_resource_group
        else
            log "Resource group preserved: ${RESOURCE_GROUP}"
        fi
    fi
    
    verify_cleanup
    show_cleanup_summary
}

# Run main function with all arguments
main "$@"