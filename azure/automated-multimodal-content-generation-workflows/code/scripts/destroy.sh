#!/bin/bash

# Destroy script for Multi-Modal Content Generation Workflows
# Recipe: Automated Multimodal Content Generation Workflows
# This script removes all infrastructure created for the multi-modal AI content generation solution

set -euo pipefail

# Color codes for output formatting
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

# Error handling function
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate Azure CLI login
validate_azure_login() {
    log_info "Validating Azure CLI authentication..."
    if ! az account show >/dev/null 2>&1; then
        error_exit "Azure CLI not logged in. Please run 'az login' first."
    fi
    
    local subscription_id=$(az account show --query id --output tsv)
    local account_name=$(az account show --query name --output tsv)
    log_success "Authenticated to Azure subscription: $account_name ($subscription_id)"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' --output tsv)
    log_info "Azure CLI version: $az_version"
    
    log_success "Prerequisites validated successfully"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ -f "deployment-info.json" ]]; then
        export RESOURCE_GROUP=$(jq -r '.resource_group' deployment-info.json)
        export LOCATION=$(jq -r '.location' deployment-info.json)
        export SUBSCRIPTION_ID=$(jq -r '.subscription_id' deployment-info.json)
        export AI_FOUNDRY_HUB=$(jq -r '.resources.ai_foundry_hub' deployment-info.json)
        export AI_FOUNDRY_PROJECT=$(jq -r '.resources.ai_foundry_project' deployment-info.json)
        export CONTAINER_REGISTRY=$(jq -r '.resources.container_registry' deployment-info.json)
        export EVENT_GRID_TOPIC=$(jq -r '.resources.event_grid_topic' deployment-info.json)
        export KEY_VAULT_NAME=$(jq -r '.resources.key_vault' deployment-info.json)
        export STORAGE_ACCOUNT=$(jq -r '.resources.storage_account' deployment-info.json)
        export FUNCTION_APP_NAME=$(jq -r '.resources.function_app' deployment-info.json)
        export RANDOM_SUFFIX=$(jq -r '.random_suffix' deployment-info.json)
        
        log_success "Deployment information loaded from deployment-info.json"
        log_info "Resource Group: $RESOURCE_GROUP"
        log_info "Location: $LOCATION"
    else
        log_warning "deployment-info.json not found. You'll need to provide resource information manually."
        prompt_for_resource_info
    fi
}

# Prompt for resource information if deployment-info.json is not available
prompt_for_resource_info() {
    log_info "Please provide the following information for cleanup:"
    
    read -p "Resource Group name: " RESOURCE_GROUP
    export RESOURCE_GROUP
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        error_exit "Resource Group name is required for cleanup."
    fi
    
    # Set subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    log_info "Will attempt to clean up all resources in Resource Group: $RESOURCE_GROUP"
}

# Confirm deletion with user
confirm_deletion() {
    echo
    log_warning "WARNING: This will permanently delete all resources in the following Resource Group:"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Subscription: $SUBSCRIPTION_ID"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    while true; do
        read -p "Are you sure you want to proceed? (type 'yes' to confirm, 'no' to cancel): " confirmation
        case $confirmation in
            yes|YES|Yes)
                log_info "Proceeding with resource deletion..."
                break
                ;;
            no|NO|No)
                log_info "Cleanup cancelled by user."
                exit 0
                ;;
            *)
                log_warning "Please type 'yes' or 'no'"
                ;;
        esac
    done
}

# Create cleanup log
create_cleanup_log() {
    export CLEANUP_LOG="cleanup-$(date +%Y%m%d-%H%M%S).log"
    touch "$CLEANUP_LOG"
    log_info "Cleanup log: $CLEANUP_LOG"
}

# Check if resource group exists
check_resource_group() {
    log_info "Checking if resource group exists..."
    
    if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Resource group '$RESOURCE_GROUP' does not exist or has already been deleted."
        log_success "Cleanup completed - no resources to remove."
        exit 0
    fi
    
    log_info "Resource group '$RESOURCE_GROUP' found. Proceeding with cleanup..."
}

# List resources to be deleted
list_resources() {
    log_info "Listing resources to be deleted..."
    echo
    echo "Resources in Resource Group '$RESOURCE_GROUP':"
    echo "=================================================="
    
    az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --output table \
        --query '[].{Name:name, Type:type, Location:location}' \
        2>>"$CLEANUP_LOG" || log_warning "Could not list all resources"
    
    echo "=================================================="
    echo
}

# Remove Event Grid subscriptions first (to prevent orphaned subscriptions)
remove_event_grid_subscriptions() {
    if [[ -n "${EVENT_GRID_TOPIC:-}" ]]; then
        log_info "Removing Event Grid subscriptions..."
        
        # List and delete event subscriptions
        local subscriptions=$(az eventgrid event-subscription list \
            --source-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventGrid/topics/$EVENT_GRID_TOPIC" \
            --query '[].name' --output tsv 2>>"$CLEANUP_LOG" || echo "")
        
        if [[ -n "$subscriptions" ]]; then
            for subscription in $subscriptions; do
                log_info "Deleting Event Grid subscription: $subscription"
                az eventgrid event-subscription delete \
                    --name "$subscription" \
                    --source-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventGrid/topics/$EVENT_GRID_TOPIC" \
                    >> "$CLEANUP_LOG" 2>&1 || log_warning "Failed to delete subscription: $subscription"
            done
        else
            log_info "No Event Grid subscriptions found to delete"
        fi
        
        log_success "Event Grid subscriptions cleanup completed"
    fi
}

# Remove AI Foundry deployments and workspaces
remove_ai_foundry() {
    if [[ -n "${AI_FOUNDRY_PROJECT:-}" ]]; then
        log_info "Removing AI Foundry model deployments..."
        
        # List and delete online deployments
        local deployments=$(az ml online-deployment list \
            --workspace-name "$AI_FOUNDRY_PROJECT" \
            --resource-group "$RESOURCE_GROUP" \
            --query '[].name' --output tsv 2>>"$CLEANUP_LOG" || echo "")
        
        if [[ -n "$deployments" ]]; then
            for deployment in $deployments; do
                log_info "Deleting AI model deployment: $deployment"
                az ml online-deployment delete \
                    --name "$deployment" \
                    --workspace-name "$AI_FOUNDRY_PROJECT" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes \
                    >> "$CLEANUP_LOG" 2>&1 || log_warning "Failed to delete deployment: $deployment"
            done
        else
            log_info "No AI model deployments found to delete"
        fi
        
        # Delete AI Foundry Project
        log_info "Deleting AI Foundry Project: $AI_FOUNDRY_PROJECT"
        az ml workspace delete \
            --name "$AI_FOUNDRY_PROJECT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            >> "$CLEANUP_LOG" 2>&1 || log_warning "Failed to delete AI Foundry Project: $AI_FOUNDRY_PROJECT"
    fi
    
    if [[ -n "${AI_FOUNDRY_HUB:-}" ]]; then
        # Delete AI Foundry Hub
        log_info "Deleting AI Foundry Hub: $AI_FOUNDRY_HUB"
        az ml workspace delete \
            --name "$AI_FOUNDRY_HUB" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            >> "$CLEANUP_LOG" 2>&1 || log_warning "Failed to delete AI Foundry Hub: $AI_FOUNDRY_HUB"
    fi
    
    log_success "AI Foundry resources cleanup completed"
}

# Remove Function App
remove_function_app() {
    if [[ -n "${FUNCTION_APP_NAME:-}" ]]; then
        log_info "Deleting Function App: $FUNCTION_APP_NAME"
        
        az functionapp delete \
            --name "$FUNCTION_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            >> "$CLEANUP_LOG" 2>&1 || log_warning "Failed to delete Function App: $FUNCTION_APP_NAME"
        
        log_success "Function App deleted: $FUNCTION_APP_NAME"
    fi
}

# Remove Container Registry
remove_container_registry() {
    if [[ -n "${CONTAINER_REGISTRY:-}" ]]; then
        log_info "Deleting Azure Container Registry: $CONTAINER_REGISTRY"
        
        az acr delete \
            --name "$CONTAINER_REGISTRY" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            >> "$CLEANUP_LOG" 2>&1 || log_warning "Failed to delete Container Registry: $CONTAINER_REGISTRY"
        
        log_success "Container Registry deleted: $CONTAINER_REGISTRY"
    fi
}

# Remove Event Grid Topic
remove_event_grid_topic() {
    if [[ -n "${EVENT_GRID_TOPIC:-}" ]]; then
        log_info "Deleting Event Grid Topic: $EVENT_GRID_TOPIC"
        
        az eventgrid topic delete \
            --name "$EVENT_GRID_TOPIC" \
            --resource-group "$RESOURCE_GROUP" \
            >> "$CLEANUP_LOG" 2>&1 || log_warning "Failed to delete Event Grid Topic: $EVENT_GRID_TOPIC"
        
        log_success "Event Grid Topic deleted: $EVENT_GRID_TOPIC"
    fi
}

# Remove Key Vault (with purge protection handling)
remove_key_vault() {
    if [[ -n "${KEY_VAULT_NAME:-}" ]]; then
        log_info "Deleting Key Vault: $KEY_VAULT_NAME"
        
        # Delete Key Vault
        az keyvault delete \
            --name "$KEY_VAULT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            >> "$CLEANUP_LOG" 2>&1 || log_warning "Failed to delete Key Vault: $KEY_VAULT_NAME"
        
        # Purge Key Vault to completely remove it (if soft-delete is enabled)
        log_info "Purging Key Vault to remove it completely..."
        az keyvault purge \
            --name "$KEY_VAULT_NAME" \
            --location "$LOCATION" \
            >> "$CLEANUP_LOG" 2>&1 || log_warning "Failed to purge Key Vault (may already be purged): $KEY_VAULT_NAME"
        
        log_success "Key Vault deleted and purged: $KEY_VAULT_NAME"
    fi
}

# Remove Storage Account
remove_storage_account() {
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        log_info "Deleting Storage Account: $STORAGE_ACCOUNT"
        
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            >> "$CLEANUP_LOG" 2>&1 || log_warning "Failed to delete Storage Account: $STORAGE_ACCOUNT"
        
        log_success "Storage Account deleted: $STORAGE_ACCOUNT"
    fi
}

# Remove any remaining resources in the resource group
remove_remaining_resources() {
    log_info "Checking for any remaining resources..."
    
    local remaining_resources=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].id' --output tsv 2>>"$CLEANUP_LOG" || echo "")
    
    if [[ -n "$remaining_resources" ]]; then
        log_warning "Found remaining resources. Attempting to delete them..."
        
        for resource_id in $remaining_resources; do
            local resource_name=$(basename "$resource_id")
            log_info "Deleting remaining resource: $resource_name"
            
            az resource delete \
                --ids "$resource_id" \
                >> "$CLEANUP_LOG" 2>&1 || log_warning "Failed to delete resource: $resource_name"
        done
    else
        log_info "No remaining individual resources found"
    fi
}

# Delete the resource group
delete_resource_group() {
    log_info "Deleting Resource Group: $RESOURCE_GROUP"
    
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        >> "$CLEANUP_LOG" 2>&1
    
    log_success "Resource Group deletion initiated: $RESOURCE_GROUP"
    log_info "Note: Resource group deletion runs asynchronously. It may take several minutes to complete."
}

# Clean up local files
clean_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment artifacts
    local files_to_remove=(
        "deployment-info.json"
        "content-coordination-config.json"
        "sample-event.json"
        "ai-model-endpoints.json"
        "custom-ai-model"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            log_info "Removing: $file"
            rm -rf "$file"
        fi
    done
    
    # Remove deployment logs (except current cleanup log)
    find . -name "deployment-*.log" -not -name "$CLEANUP_LOG" -delete 2>/dev/null || true
    
    log_success "Local files cleaned up"
}

# Wait for resource group deletion (optional)
wait_for_deletion() {
    if [[ "${WAIT_FOR_COMPLETION:-false}" == "true" ]]; then
        log_info "Waiting for resource group deletion to complete..."
        
        while az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; do
            log_info "Resource group still exists. Waiting 30 seconds..."
            sleep 30
        done
        
        log_success "Resource group deletion completed"
    else
        log_info "Skipping wait for completion. Check Azure portal to monitor deletion progress."
    fi
}

# Display cleanup summary
display_summary() {
    echo
    log_success "Cleanup process completed!"
    echo
    echo "============================="
    echo "CLEANUP SUMMARY"
    echo "============================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Cleanup Log: $CLEANUP_LOG"
    echo
    echo "Actions Performed:"
    echo "✓ Event Grid subscriptions deleted"
    echo "✓ AI Foundry deployments and workspaces deleted"
    echo "✓ Function App deleted"
    echo "✓ Container Registry deleted"
    echo "✓ Event Grid Topic deleted"
    echo "✓ Key Vault deleted and purged"
    echo "✓ Storage Account deleted"
    echo "✓ Resource Group deletion initiated"
    echo "✓ Local files cleaned up"
    echo
    echo "Note: Resource group deletion runs asynchronously."
    echo "Check the Azure portal to confirm complete removal."
    echo "============================="
}

# Main execution function
main() {
    log_info "Starting Azure Multi-Modal Content Generation Workflow cleanup..."
    
    # Execute cleanup steps
    check_prerequisites
    validate_azure_login
    load_deployment_info
    confirm_deletion
    create_cleanup_log
    check_resource_group
    list_resources
    
    # Remove resources in dependency order
    remove_event_grid_subscriptions
    remove_ai_foundry
    remove_function_app
    remove_container_registry
    remove_event_grid_topic
    remove_key_vault
    remove_storage_account
    remove_remaining_resources
    delete_resource_group
    clean_local_files
    wait_for_deletion
    display_summary
    
    log_success "Cleanup script completed successfully!"
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --wait)
            export WAIT_FOR_COMPLETION=true
            shift
            ;;
        --resource-group)
            export RESOURCE_GROUP="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --wait              Wait for resource group deletion to complete"
            echo "  --resource-group    Specify resource group name manually"
            echo "  --help              Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi