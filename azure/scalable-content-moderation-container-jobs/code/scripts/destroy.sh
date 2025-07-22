#!/bin/bash

# Destroy Azure Content Moderation Workflow
# This script safely removes all resources created for the content moderation solution

set -e  # Exit on any error

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
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to discover resources
discover_resources() {
    log "Discovering resources to delete..."
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Try to find resource groups matching the pattern
    local resource_groups=$(az group list \
        --query "[?starts_with(name, 'rg-content-moderation-')].name" \
        --output tsv)
    
    if [ -z "$resource_groups" ]; then
        log "No content moderation resource groups found."
        return 0
    fi
    
    log "Found the following resource groups:"
    for rg in $resource_groups; do
        log "  - $rg"
    done
    
    # If only one resource group, use it
    if [ $(echo "$resource_groups" | wc -w) -eq 1 ]; then
        export RESOURCE_GROUP="$resource_groups"
        log "Using resource group: $RESOURCE_GROUP"
    else
        # Multiple resource groups found, ask user to specify
        log "Multiple resource groups found. Please specify which one to delete:"
        select rg in $resource_groups "Cancel"; do
            if [ "$rg" = "Cancel" ]; then
                log "Operation cancelled by user."
                exit 0
            elif [ -n "$rg" ]; then
                export RESOURCE_GROUP="$rg"
                log "Selected resource group: $RESOURCE_GROUP"
                break
            else
                warn "Invalid selection. Please try again."
            fi
        done
    fi
    
    # Extract suffix from resource group name
    export RANDOM_SUFFIX=$(echo "$RESOURCE_GROUP" | sed 's/rg-content-moderation-//')
    log "Extracted suffix: $RANDOM_SUFFIX"
    
    # Set resource names based on discovered resource group
    export CONTENT_SAFETY_NAME="cs-moderation-${RANDOM_SUFFIX}"
    export CONTAINER_ENV_NAME="cae-moderation-${RANDOM_SUFFIX}"
    export SERVICE_BUS_NAMESPACE="sb-moderation-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stmoderation${RANDOM_SUFFIX}"
    export CONTAINER_JOB_NAME="job-content-processor"
    export LOG_ANALYTICS_WORKSPACE="law-content-moderation-${RANDOM_SUFFIX}"
    export ACTION_GROUP_NAME="ag-content-moderation"
}

# Function to confirm deletion
confirm_deletion() {
    log "You are about to delete the following resources:"
    echo "================================================"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Content Safety: $CONTENT_SAFETY_NAME"
    echo "Container Apps Environment: $CONTAINER_ENV_NAME"
    echo "Service Bus Namespace: $SERVICE_BUS_NAMESPACE"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "Container Apps Job: $CONTAINER_JOB_NAME"
    echo "Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    echo "Action Group: $ACTION_GROUP_NAME"
    echo "================================================"
    
    # Check if running in non-interactive mode
    if [ "$FORCE_DELETE" = "true" ]; then
        log "Force delete mode enabled, skipping confirmation."
        return 0
    fi
    
    read -p "Are you sure you want to delete these resources? This action cannot be undone. (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Operation cancelled by user."
        exit 0
    fi
    
    log "Deletion confirmed. Proceeding with resource cleanup..."
}

# Function to list resources in resource group
list_resources() {
    log "Listing resources in resource group: $RESOURCE_GROUP"
    
    local resources=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].{Name:name, Type:type, Location:location}" \
        --output table)
    
    if [ -n "$resources" ]; then
        echo "$resources"
    else
        log "No resources found in resource group or resource group doesn't exist."
    fi
}

# Function to delete Container Apps resources
delete_container_apps() {
    log "Deleting Container Apps resources..."
    
    # Check if Container Apps job exists
    if az containerapp job show --name "$CONTAINER_JOB_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting Container Apps job: $CONTAINER_JOB_NAME"
        az containerapp job delete \
            --name "$CONTAINER_JOB_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        
        if [ $? -eq 0 ]; then
            log "✅ Container Apps job deleted successfully"
        else
            warn "Failed to delete Container Apps job, but continuing..."
        fi
    else
        log "Container Apps job not found, skipping..."
    fi
    
    # Check if Container Apps environment exists
    if az containerapp env show --name "$CONTAINER_ENV_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting Container Apps environment: $CONTAINER_ENV_NAME"
        az containerapp env delete \
            --name "$CONTAINER_ENV_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        
        if [ $? -eq 0 ]; then
            log "✅ Container Apps environment deleted successfully"
        else
            warn "Failed to delete Container Apps environment, but continuing..."
        fi
    else
        log "Container Apps environment not found, skipping..."
    fi
}

# Function to delete Service Bus resources
delete_service_bus() {
    log "Deleting Service Bus resources..."
    
    # Check if Service Bus namespace exists
    if az servicebus namespace show --name "$SERVICE_BUS_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting Service Bus namespace: $SERVICE_BUS_NAMESPACE"
        az servicebus namespace delete \
            --name "$SERVICE_BUS_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP"
        
        if [ $? -eq 0 ]; then
            log "✅ Service Bus namespace deleted successfully"
        else
            warn "Failed to delete Service Bus namespace, but continuing..."
        fi
    else
        log "Service Bus namespace not found, skipping..."
    fi
}

# Function to delete storage account
delete_storage_account() {
    log "Deleting Storage Account..."
    
    # Check if storage account exists
    if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting Storage Account: $STORAGE_ACCOUNT_NAME"
        az storage account delete \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        
        if [ $? -eq 0 ]; then
            log "✅ Storage Account deleted successfully"
        else
            warn "Failed to delete Storage Account, but continuing..."
        fi
    else
        log "Storage Account not found, skipping..."
    fi
}

# Function to delete Content Safety resource
delete_content_safety() {
    log "Deleting Azure AI Content Safety resource..."
    
    # Check if Content Safety resource exists
    if az cognitiveservices account show --name "$CONTENT_SAFETY_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting Content Safety resource: $CONTENT_SAFETY_NAME"
        az cognitiveservices account delete \
            --name "$CONTENT_SAFETY_NAME" \
            --resource-group "$RESOURCE_GROUP"
        
        if [ $? -eq 0 ]; then
            log "✅ Content Safety resource deleted successfully"
        else
            warn "Failed to delete Content Safety resource, but continuing..."
        fi
    else
        log "Content Safety resource not found, skipping..."
    fi
}

# Function to delete monitoring resources
delete_monitoring() {
    log "Deleting monitoring resources..."
    
    # Delete alert rules first
    log "Deleting alert rules..."
    local alert_rules=$(az monitor metrics alert list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv)
    
    if [ -n "$alert_rules" ]; then
        for rule in $alert_rules; do
            log "Deleting alert rule: $rule"
            az monitor metrics alert delete \
                --name "$rule" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
        done
        log "✅ Alert rules deleted successfully"
    else
        log "No alert rules found, skipping..."
    fi
    
    # Delete action group
    if az monitor action-group show --name "$ACTION_GROUP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting action group: $ACTION_GROUP_NAME"
        az monitor action-group delete \
            --name "$ACTION_GROUP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        
        if [ $? -eq 0 ]; then
            log "✅ Action group deleted successfully"
        else
            warn "Failed to delete action group, but continuing..."
        fi
    else
        log "Action group not found, skipping..."
    fi
    
    # Delete Log Analytics workspace
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE" &> /dev/null; then
        log "Deleting Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
        az monitor log-analytics workspace delete \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --yes \
            --force
        
        if [ $? -eq 0 ]; then
            log "✅ Log Analytics workspace deleted successfully"
        else
            warn "Failed to delete Log Analytics workspace, but continuing..."
        fi
    else
        log "Log Analytics workspace not found, skipping..."
    fi
}

# Function to delete remaining resources
delete_remaining_resources() {
    log "Checking for any remaining resources..."
    
    # List any remaining resources in the resource group
    local remaining_resources=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].{Name:name, Type:type}" \
        --output tsv)
    
    if [ -n "$remaining_resources" ]; then
        warn "Found remaining resources in resource group:"
        echo "$remaining_resources"
        
        log "Attempting to delete remaining resources..."
        az resource delete \
            --ids $(az resource list --resource-group "$RESOURCE_GROUP" --query "[].id" --output tsv) \
            --force
        
        if [ $? -eq 0 ]; then
            log "✅ Remaining resources deleted successfully"
        else
            warn "Some resources could not be deleted automatically"
        fi
    else
        log "No remaining resources found"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group: $RESOURCE_GROUP"
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        
        if [ $? -eq 0 ]; then
            log "✅ Resource group deletion initiated successfully"
            log "Note: Complete deletion may take several minutes"
        else
            error "Failed to delete resource group"
            exit 1
        fi
    else
        log "Resource group not found, skipping..."
    fi
}

# Function to wait for resource group deletion
wait_for_deletion() {
    if [ "$WAIT_FOR_COMPLETION" = "true" ]; then
        log "Waiting for resource group deletion to complete..."
        
        local max_attempts=60  # 10 minutes maximum
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
                log "✅ Resource group deletion completed"
                return 0
            fi
            
            log "Resource group still exists. Waiting... (attempt $((attempt + 1))/$max_attempts)"
            sleep 10
            ((attempt++))
        done
        
        warn "Timeout waiting for resource group deletion to complete"
        warn "The deletion may still be in progress. Check the Azure portal for status."
    else
        log "Resource group deletion initiated. Check Azure portal for completion status."
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove any temporary files created during deployment
    if [ -f "/tmp/process-content.sh" ]; then
        rm -f "/tmp/process-content.sh"
        log "✅ Removed temporary processing script"
    fi
    
    # Remove any other temporary files
    find /tmp -name "*content-moderation*" -type f -delete 2>/dev/null || true
    find /tmp -name "*${RANDOM_SUFFIX}*" -type f -delete 2>/dev/null || true
    
    log "✅ Local cleanup completed"
}

# Function to display deletion summary
display_summary() {
    log "Deletion Summary:"
    echo "================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Deletion Status: Initiated"
    echo "================="
    echo ""
    echo "The following resources have been deleted or scheduled for deletion:"
    echo "- Azure AI Content Safety resource"
    echo "- Container Apps Job and Environment"
    echo "- Service Bus Namespace and Queue"
    echo "- Storage Account and Containers"
    echo "- Log Analytics Workspace"
    echo "- Action Group and Alert Rules"
    echo "- Resource Group (deletion in progress)"
    echo ""
    echo "Note: Some resources may take several minutes to be completely removed."
    echo "You can check the deletion status in the Azure portal."
}

# Main deletion function
main() {
    log "Starting Azure Content Moderation Workflow cleanup..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force|-f)
                export FORCE_DELETE="true"
                shift
                ;;
            --wait|-w)
                export WAIT_FOR_COMPLETION="true"
                shift
                ;;
            --resource-group|-g)
                export RESOURCE_GROUP="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --force, -f              Skip confirmation prompts"
                echo "  --wait, -w               Wait for deletion to complete"
                echo "  --resource-group, -g     Specify resource group name"
                echo "  --help, -h               Show this help message"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    check_prerequisites
    
    # If resource group not specified, try to discover it
    if [ -z "$RESOURCE_GROUP" ]; then
        discover_resources
    else
        # Extract suffix from provided resource group name
        export RANDOM_SUFFIX=$(echo "$RESOURCE_GROUP" | sed 's/rg-content-moderation-//')
        log "Using provided resource group: $RESOURCE_GROUP"
        log "Extracted suffix: $RANDOM_SUFFIX"
        
        # Set resource names based on provided resource group
        export CONTENT_SAFETY_NAME="cs-moderation-${RANDOM_SUFFIX}"
        export CONTAINER_ENV_NAME="cae-moderation-${RANDOM_SUFFIX}"
        export SERVICE_BUS_NAMESPACE="sb-moderation-${RANDOM_SUFFIX}"
        export STORAGE_ACCOUNT_NAME="stmoderation${RANDOM_SUFFIX}"
        export CONTAINER_JOB_NAME="job-content-processor"
        export LOG_ANALYTICS_WORKSPACE="law-content-moderation-${RANDOM_SUFFIX}"
        export ACTION_GROUP_NAME="ag-content-moderation"
    fi
    
    # Exit if no resource group found
    if [ -z "$RESOURCE_GROUP" ]; then
        log "No content moderation resources found to delete."
        exit 0
    fi
    
    list_resources
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_container_apps
    delete_monitoring
    delete_service_bus
    delete_storage_account
    delete_content_safety
    delete_remaining_resources
    delete_resource_group
    
    wait_for_deletion
    cleanup_local_files
    display_summary
    
    log "🎉 Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"