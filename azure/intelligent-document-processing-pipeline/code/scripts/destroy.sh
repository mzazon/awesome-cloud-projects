#!/bin/bash

# Azure Real-time Document Processing Cleanup Script
# This script removes all resources created for the real-time document processing solution
# using Azure Cosmos DB for MongoDB and Azure Event Hubs

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check prerequisites
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
    
    success "Prerequisites check completed"
}

# Function to get environment variables
get_environment_variables() {
    log "Getting environment variables..."
    
    # Check if resource group is provided
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        echo ""
        echo "Resource group not specified. Available options:"
        echo "1. Set RESOURCE_GROUP environment variable"
        echo "2. Pass resource group as first argument"
        echo "3. Select from existing resource groups"
        echo ""
        
        read -p "Enter resource group name (or press Enter to list existing): " RESOURCE_GROUP
        
        if [[ -z "$RESOURCE_GROUP" ]]; then
            echo "Available resource groups:"
            az group list --query "[?starts_with(name, 'rg-docprocessing-')].name" --output table
            echo ""
            read -p "Enter resource group name: " RESOURCE_GROUP
        fi
    fi
    
    # Validate resource group exists
    if ! az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; then
        error "Resource group '$RESOURCE_GROUP' does not exist"
    fi
    
    export RESOURCE_GROUP
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    log "Cleanup configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Subscription ID: $SUBSCRIPTION_ID"
    
    success "Environment variables configured"
}

# Function to confirm deletion
confirm_deletion() {
    log "WARNING: This operation will delete all resources in the resource group!"
    echo ""
    echo "Resource Group: $RESOURCE_GROUP"
    echo "This will delete:"
    echo "  - Event Hubs namespace and all hubs"
    echo "  - Cosmos DB account and all databases"
    echo "  - Function App and all functions"
    echo "  - Storage account and all data"
    echo "  - AI Document Intelligence service"
    echo "  - Application Insights instance"
    echo "  - All associated logs and monitoring data"
    echo ""
    
    # Check if force flag is provided
    if [[ "${1:-}" == "--force" ]]; then
        warning "Force flag detected. Skipping confirmation."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
    
    if [[ "$CONFIRM" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Deletion confirmed"
}

# Function to list resources before deletion
list_resources() {
    log "Listing resources in resource group: $RESOURCE_GROUP"
    
    # List all resources in the resource group
    az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].{Name:name,Type:type,Location:location}" \
        --output table
    
    echo ""
    success "Resource listing completed"
}

# Function to delete Function App
delete_function_app() {
    log "Deleting Function App..."
    
    # Get function app name
    FUNCTION_APPS=$(az functionapp list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv)
    
    if [[ -z "$FUNCTION_APPS" ]]; then
        warning "No Function Apps found in resource group"
        return 0
    fi
    
    for FUNCTION_APP in $FUNCTION_APPS; do
        log "Deleting Function App: $FUNCTION_APP"
        
        # Stop the function app first
        az functionapp stop \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --output none || true
        
        # Delete the function app
        az functionapp delete \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --output none
        
        success "Function App '$FUNCTION_APP' deleted"
    done
}

# Function to delete Application Insights
delete_application_insights() {
    log "Deleting Application Insights..."
    
    # Get Application Insights instances
    INSIGHTS=$(az monitor app-insights component list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv)
    
    if [[ -z "$INSIGHTS" ]]; then
        warning "No Application Insights instances found in resource group"
        return 0
    fi
    
    for INSIGHT in $INSIGHTS; do
        log "Deleting Application Insights: $INSIGHT"
        
        az monitor app-insights component delete \
            --app "$INSIGHT" \
            --resource-group "$RESOURCE_GROUP" \
            --output none
        
        success "Application Insights '$INSIGHT' deleted"
    done
}

# Function to delete AI Document Intelligence service
delete_ai_document_service() {
    log "Deleting AI Document Intelligence service..."
    
    # Get cognitive services accounts
    AI_SERVICES=$(az cognitiveservices account list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?kind=='FormRecognizer'].name" \
        --output tsv)
    
    if [[ -z "$AI_SERVICES" ]]; then
        warning "No AI Document Intelligence services found in resource group"
        return 0
    fi
    
    for AI_SERVICE in $AI_SERVICES; do
        log "Deleting AI Document Intelligence service: $AI_SERVICE"
        
        az cognitiveservices account delete \
            --name "$AI_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --output none
        
        success "AI Document Intelligence service '$AI_SERVICE' deleted"
    done
}

# Function to delete Cosmos DB
delete_cosmos_db() {
    log "Deleting Cosmos DB account..."
    
    # Get Cosmos DB accounts
    COSMOS_ACCOUNTS=$(az cosmosdb list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv)
    
    if [[ -z "$COSMOS_ACCOUNTS" ]]; then
        warning "No Cosmos DB accounts found in resource group"
        return 0
    fi
    
    for COSMOS_ACCOUNT in $COSMOS_ACCOUNTS; do
        log "Deleting Cosmos DB account: $COSMOS_ACCOUNT"
        
        # Delete the Cosmos DB account
        az cosmosdb delete \
            --name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none
        
        success "Cosmos DB account '$COSMOS_ACCOUNT' deleted"
    done
}

# Function to delete Event Hubs
delete_event_hubs() {
    log "Deleting Event Hubs infrastructure..."
    
    # Get Event Hubs namespaces
    EVENT_HUB_NAMESPACES=$(az eventhubs namespace list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv)
    
    if [[ -z "$EVENT_HUB_NAMESPACES" ]]; then
        warning "No Event Hubs namespaces found in resource group"
        return 0
    fi
    
    for NAMESPACE in $EVENT_HUB_NAMESPACES; do
        log "Deleting Event Hubs namespace: $NAMESPACE"
        
        # Delete the namespace (this will delete all hubs and consumer groups)
        az eventhubs namespace delete \
            --name "$NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --output none
        
        success "Event Hubs namespace '$NAMESPACE' deleted"
    done
}

# Function to delete storage accounts
delete_storage_accounts() {
    log "Deleting storage accounts..."
    
    # Get storage accounts
    STORAGE_ACCOUNTS=$(az storage account list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv)
    
    if [[ -z "$STORAGE_ACCOUNTS" ]]; then
        warning "No storage accounts found in resource group"
        return 0
    fi
    
    for STORAGE_ACCOUNT in $STORAGE_ACCOUNTS; do
        log "Deleting storage account: $STORAGE_ACCOUNT"
        
        # Delete the storage account
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none
        
        success "Storage account '$STORAGE_ACCOUNT' deleted"
    done
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group..."
    
    # Ask for final confirmation
    echo ""
    warning "FINAL CONFIRMATION: This will delete the entire resource group and all remaining resources!"
    read -p "Type 'DELETE' to confirm final deletion: " FINAL_CONFIRM
    
    if [[ "$FINAL_CONFIRM" != "DELETE" ]]; then
        log "Final deletion cancelled by user"
        return 0
    fi
    
    # Delete the resource group
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    success "Resource group deletion initiated: $RESOURCE_GROUP"
    log "Note: Resource group deletion is running in the background and may take several minutes to complete"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check if resource group still exists
    if az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; then
        warning "Resource group still exists. Deletion may be in progress."
        
        # List any remaining resources
        REMAINING_RESOURCES=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].name" \
            --output tsv)
        
        if [[ -n "$REMAINING_RESOURCES" ]]; then
            warning "Remaining resources in resource group:"
            echo "$REMAINING_RESOURCES"
        else
            log "No resources remain in the resource group"
        fi
    else
        success "Resource group has been completely deleted"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary:"
    echo "===================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Subscription ID: $SUBSCRIPTION_ID"
    echo "===================="
    echo ""
    echo "Cleanup Actions Performed:"
    echo "✓ Function Apps stopped and deleted"
    echo "✓ Application Insights instances deleted"
    echo "✓ AI Document Intelligence services deleted"
    echo "✓ Cosmos DB accounts deleted"
    echo "✓ Event Hubs namespaces deleted"
    echo "✓ Storage accounts deleted"
    echo "✓ Resource group deletion initiated"
    echo ""
    echo "Note: Some resources may take additional time to be fully removed from Azure."
    echo "You can verify complete cleanup by checking the Azure portal or running:"
    echo "  az group exists --name $RESOURCE_GROUP"
}

# Function to cleanup individual resources (alternative to full resource group deletion)
cleanup_individual_resources() {
    log "Cleaning up individual resources..."
    
    # Delete resources in reverse order of creation
    delete_function_app
    delete_application_insights
    delete_ai_document_service
    delete_cosmos_db
    delete_event_hubs
    delete_storage_accounts
    
    success "Individual resource cleanup completed"
}

# Main cleanup function
main() {
    log "Starting Azure Real-time Document Processing cleanup..."
    
    # Check if dry run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log "DRY RUN MODE: No resources will be deleted"
        check_prerequisites
        get_environment_variables
        list_resources
        return 0
    fi
    
    # Check if individual cleanup mode
    if [[ "${1:-}" == "--individual" ]]; then
        log "INDIVIDUAL CLEANUP MODE: Deleting resources one by one"
        check_prerequisites
        get_environment_variables "${2:-}"
        confirm_deletion "${2:-}"
        list_resources
        cleanup_individual_resources
        verify_cleanup
        display_summary
        return 0
    fi
    
    # Run cleanup steps
    check_prerequisites
    get_environment_variables "${1:-}"
    confirm_deletion "${1:-}"
    list_resources
    
    # Choose cleanup method
    echo ""
    echo "Cleanup options:"
    echo "1. Delete entire resource group (recommended, faster)"
    echo "2. Delete individual resources (slower, more detailed)"
    echo ""
    read -p "Choose cleanup method (1 or 2): " CLEANUP_METHOD
    
    case $CLEANUP_METHOD in
        1)
            delete_resource_group
            ;;
        2)
            cleanup_individual_resources
            ;;
        *)
            error "Invalid cleanup method selected"
            ;;
    esac
    
    verify_cleanup
    display_summary
    
    success "Cleanup completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi