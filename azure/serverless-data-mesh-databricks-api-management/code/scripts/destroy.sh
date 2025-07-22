#!/bin/bash

# Azure Serverless Data Mesh Cleanup Script
# Recipe: Serverless Data Mesh with Databricks and API Management
# Version: 1.0

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
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Global variables
FORCE_DELETE=false
DRY_RUN=false
SKIP_CONFIRMATION=false

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown parameter: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help message
show_help() {
    cat << EOF
Azure Serverless Data Mesh Cleanup Script

Usage: $0 [OPTIONS]

Options:
    --force         Force deletion without additional confirmations
    --dry-run       Show what would be deleted without actually deleting
    --yes           Skip initial confirmation prompt
    -h, --help      Show this help message

Examples:
    $0                      # Interactive deletion with confirmations
    $0 --dry-run           # Show what would be deleted
    $0 --force --yes       # Force deletion without confirmations
EOF
}

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    info "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
        return 0
    fi
    
    if [[ "$ignore_errors" == "true" ]]; then
        eval "$cmd" || warn "Command failed but continuing: $cmd"
    else
        if ! eval "$cmd"; then
            error "Failed to execute: $cmd"
            return 1
        fi
    fi
}

# Load configuration from deployment
load_configuration() {
    log "Loading deployment configuration..."
    
    if [[ ! -f ".deployment-config" ]]; then
        error "Configuration file '.deployment-config' not found"
        error "This script should be run from the same directory as the deployment script"
        exit 1
    fi
    
    # Source the configuration file
    source .deployment-config
    
    # Validate required variables
    local required_vars=("RESOURCE_GROUP" "DATABRICKS_WORKSPACE" "APIM_SERVICE" "KEYVAULT_NAME" "EVENT_GRID_TOPIC")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable $var not found in configuration"
            exit 1
        fi
    done
    
    info "Configuration loaded successfully"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Databricks Workspace: $DATABRICKS_WORKSPACE"
    info "  API Management: $APIM_SERVICE"
    info "  Key Vault: $KEYVAULT_NAME"
    info "  Event Grid Topic: $EVENT_GRID_TOPIC"
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Resource group '${RESOURCE_GROUP}' does not exist or is not accessible"
        info "This might be expected if resources were already deleted"
    fi
    
    log "Prerequisites check completed"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    warn "This will delete the following resources:"
    echo "  - Resource Group: $RESOURCE_GROUP"
    echo "  - Databricks Workspace: $DATABRICKS_WORKSPACE"
    echo "  - API Management Service: $APIM_SERVICE"
    echo "  - Key Vault: $KEYVAULT_NAME"
    echo "  - Event Grid Topic: $EVENT_GRID_TOPIC"
    echo "  - All associated resources and data"
    echo ""
    warn "This action cannot be undone!"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Running in dry-run mode - no resources will actually be deleted"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed by user"
}

# Check resource existence
check_resource_existence() {
    log "Checking resource existence..."
    
    local resources_exist=false
    
    # Check API Management service
    if az apim show --name "${APIM_SERVICE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "✓ API Management service exists"
        resources_exist=true
    else
        info "✗ API Management service not found"
    fi
    
    # Check Databricks workspace
    if az databricks workspace show --name "${DATABRICKS_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "✓ Databricks workspace exists"
        resources_exist=true
    else
        info "✗ Databricks workspace not found"
    fi
    
    # Check Event Grid topic
    if az eventgrid topic show --name "${EVENT_GRID_TOPIC}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "✓ Event Grid topic exists"
        resources_exist=true
    else
        info "✗ Event Grid topic not found"
    fi
    
    # Check Key Vault
    if az keyvault show --name "${KEYVAULT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "✓ Key Vault exists"
        resources_exist=true
    else
        info "✗ Key Vault not found"
    fi
    
    # Check resource group
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        info "✓ Resource group exists"
        resources_exist=true
    else
        info "✗ Resource group not found"
    fi
    
    if [[ "$resources_exist" == "false" ]]; then
        warn "No resources found to delete"
        if [[ "$DRY_RUN" == "false" ]]; then
            info "Cleaning up local files..."
            cleanup_local_files
        fi
        exit 0
    fi
    
    log "Resource existence check completed"
}

# Delete API Management service
delete_apim() {
    log "Deleting API Management service..."
    
    if az apim show --name "${APIM_SERVICE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "API Management deletion may take 15-20 minutes"
        
        local cmd="az apim delete --name ${APIM_SERVICE} --resource-group ${RESOURCE_GROUP} --yes"
        execute_command "$cmd" "Deleting API Management service: $APIM_SERVICE"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            info "Waiting for API Management deletion to complete..."
            local timeout=1800  # 30 minutes timeout
            local elapsed=0
            local interval=30
            
            while [[ $elapsed -lt $timeout ]]; do
                if ! az apim show --name "${APIM_SERVICE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
                    log "API Management service deleted successfully"
                    return 0
                fi
                
                sleep $interval
                elapsed=$((elapsed + interval))
                info "Still waiting for API Management deletion... (${elapsed}s elapsed)"
            done
            
            warn "API Management deletion timeout reached, but deletion may still be in progress"
        fi
    else
        info "API Management service not found, skipping deletion"
    fi
}

# Delete Databricks workspace
delete_databricks_workspace() {
    log "Deleting Databricks workspace..."
    
    if az databricks workspace show --name "${DATABRICKS_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        local cmd="az databricks workspace delete --name ${DATABRICKS_WORKSPACE} --resource-group ${RESOURCE_GROUP} --yes"
        execute_command "$cmd" "Deleting Databricks workspace: $DATABRICKS_WORKSPACE"
        
        log "Databricks workspace deleted successfully"
    else
        info "Databricks workspace not found, skipping deletion"
    fi
}

# Delete Event Grid resources
delete_event_grid() {
    log "Deleting Event Grid resources..."
    
    # Delete Event Grid subscriptions first
    if az eventgrid topic show --name "${EVENT_GRID_TOPIC}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "Deleting Event Grid subscriptions..."
        
        local subscriptions=$(az eventgrid event-subscription list \
            --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" \
            --query "[].name" --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$subscriptions" ]]; then
            while IFS= read -r subscription; do
                if [[ -n "$subscription" ]]; then
                    local delete_sub_cmd="az eventgrid event-subscription delete --name ${subscription} --source-resource-id /subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}"
                    execute_command "$delete_sub_cmd" "Deleting Event Grid subscription: $subscription" "true"
                fi
            done <<< "$subscriptions"
        fi
        
        # Delete Event Grid topic
        local cmd="az eventgrid topic delete --name ${EVENT_GRID_TOPIC} --resource-group ${RESOURCE_GROUP} --yes"
        execute_command "$cmd" "Deleting Event Grid topic: $EVENT_GRID_TOPIC"
        
        log "Event Grid resources deleted successfully"
    else
        info "Event Grid topic not found, skipping deletion"
    fi
}

# Delete Key Vault
delete_keyvault() {
    log "Deleting Key Vault..."
    
    if az keyvault show --name "${KEYVAULT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        # Delete Key Vault (soft delete)
        local cmd="az keyvault delete --name ${KEYVAULT_NAME} --resource-group ${RESOURCE_GROUP}"
        execute_command "$cmd" "Deleting Key Vault: $KEYVAULT_NAME"
        
        # Purge Key Vault (permanent deletion)
        if [[ "$FORCE_DELETE" == "true" ]]; then
            local purge_cmd="az keyvault purge --name ${KEYVAULT_NAME} --location ${LOCATION:-eastus}"
            execute_command "$purge_cmd" "Purging Key Vault: $KEYVAULT_NAME" "true"
        else
            warn "Key Vault soft-deleted. Use --force to permanently purge it"
        fi
        
        log "Key Vault deleted successfully"
    else
        info "Key Vault not found, skipping deletion"
    fi
}

# Delete service principal
delete_service_principal() {
    log "Deleting service principal..."
    
    if [[ -n "${SP_APP_ID:-}" ]] && [[ "$SP_APP_ID" != "null" ]]; then
        local cmd="az ad sp delete --id ${SP_APP_ID}"
        execute_command "$cmd" "Deleting service principal: $SP_APP_ID" "true"
        
        log "Service principal deleted successfully"
    else
        info "Service principal ID not found, skipping deletion"
    fi
}

# Delete resource group
delete_resource_group() {
    log "Deleting resource group..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        local cmd="az group delete --name ${RESOURCE_GROUP} --yes --no-wait"
        execute_command "$cmd" "Deleting resource group: $RESOURCE_GROUP"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            info "Resource group deletion initiated (running in background)"
            warn "Complete deletion may take several minutes"
        fi
        
        log "Resource group deletion initiated successfully"
    else
        info "Resource group not found, skipping deletion"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_delete=(
        ".deployment-config"
        "data-product-api.json"
        "api-policy.xml"
        "data-product-notebook.py"
    )
    
    for file in "${files_to_delete[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "Would delete file: $file"
            else
                rm -f "$file"
                info "Deleted file: $file"
            fi
        fi
    done
    
    log "Local files cleanup completed"
}

# Validate deletion
validate_deletion() {
    log "Validating deletion..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Skipping validation in dry-run mode"
        return 0
    fi
    
    local validation_failed=false
    
    # Check if API Management still exists
    if az apim show --name "${APIM_SERVICE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "API Management service still exists (may still be deleting)"
        validation_failed=true
    else
        log "✅ API Management service deletion confirmed"
    fi
    
    # Check if Databricks workspace still exists
    if az databricks workspace show --name "${DATABRICKS_WORKSPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Databricks workspace still exists"
        validation_failed=true
    else
        log "✅ Databricks workspace deletion confirmed"
    fi
    
    # Check if Event Grid topic still exists
    if az eventgrid topic show --name "${EVENT_GRID_TOPIC}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Event Grid topic still exists"
        validation_failed=true
    else
        log "✅ Event Grid topic deletion confirmed"
    fi
    
    # Check if Key Vault still exists (excluding soft-deleted state)
    if az keyvault show --name "${KEYVAULT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Key Vault still exists (may be in soft-deleted state)"
    else
        log "✅ Key Vault deletion confirmed"
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        warn "Some resources may still be in the process of deletion"
    else
        log "Validation completed successfully"
    fi
}

# Main cleanup function
main() {
    log "Starting Azure Serverless Data Mesh cleanup..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "Running in DRY-RUN mode - no resources will be deleted"
    fi
    
    # Load configuration
    load_configuration
    
    # Check prerequisites
    check_prerequisites
    
    # Confirm deletion
    confirm_deletion
    
    # Check resource existence
    check_resource_existence
    
    # Delete resources in order (handling dependencies)
    delete_apim
    delete_databricks_workspace
    delete_event_grid
    delete_keyvault
    delete_service_principal
    delete_resource_group
    
    # Clean up local files
    cleanup_local_files
    
    # Validate deletion
    validate_deletion
    
    log "Cleanup completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "Summary:"
        info "  All Azure resources have been deleted or are in the process of deletion"
        info "  Local configuration files have been cleaned up"
        info "  Resource group deletion is running in the background"
        warn "Monitor the Azure portal to confirm complete deletion"
    fi
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi