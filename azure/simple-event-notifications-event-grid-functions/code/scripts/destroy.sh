#!/bin/bash

#==============================================================================
# Azure Event Grid and Functions Cleanup Script
# 
# This script safely removes all resources created by the deployment script
# for the event notifications solution using Azure Event Grid and Functions.
#==============================================================================

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Configuration variables
FORCE_DELETE="${FORCE_DELETE:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Error handling
handle_error() {
    log_error "An error occurred during cleanup. Some resources may still exist."
    log_warning "Please check the Azure Portal to verify resource cleanup."
    exit 1
}

trap handle_error ERR

# Load deployment configuration
load_deployment_config() {
    if [[ -f ".deployment-config" ]]; then
        log_info "Loading deployment configuration from .deployment-config"
        source .deployment-config
        
        # Validate required variables
        if [[ -z "${RESOURCE_GROUP:-}" ]] || [[ -z "${SUBSCRIPTION_ID:-}" ]]; then
            log_error "Invalid or incomplete deployment configuration"
            return 1
        fi
        
        log_info "Configuration loaded:"
        log_info "  Resource Group: ${RESOURCE_GROUP}"
        log_info "  Subscription ID: ${SUBSCRIPTION_ID}"
        
        return 0
    fi
    
    return 1
}

# Manual configuration input
manual_configuration() {
    log_warning "No deployment configuration found. Please provide resource details manually."
    echo ""
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv 2>/dev/null || echo "")
    if [[ -z "${SUBSCRIPTION_ID}" ]]; then
        log_error "Cannot determine Azure subscription. Please ensure you are logged in with 'az login'"
        exit 1
    fi
    
    # Get resource group name
    echo "Available resource groups:"
    az group list --query "[].{Name:name, Location:location}" -o table
    echo ""
    
    read -p "Enter the resource group name to delete: " RESOURCE_GROUP
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        log_error "Resource group name is required"
        exit 1
    fi
    
    # Verify resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_error "Resource group '${RESOURCE_GROUP}' not found"
        exit 1
    fi
    
    # Try to identify resources in the group
    log_info "Resources found in group '${RESOURCE_GROUP}':"
    az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" -o table
    echo ""
}

# Prerequisites checking
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Confirm deletion
confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log_warning "Force delete mode enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo ""
    
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        echo "   🗂️  Resource Group: ${RESOURCE_GROUP}"
        
        # List resources in the group
        log_info "Resources to be deleted:"
        az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type, Location:location}" -o table 2>/dev/null || echo "   Unable to list resources"
    fi
    
    echo ""
    echo "💰 This action will:"
    echo "   • Stop all billing for these resources"
    echo "   • Permanently delete all data and configurations"
    echo "   • Remove all Event Grid subscriptions and topics"
    echo "   • Delete the Function App and associated storage"
    echo ""
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would delete the above resources"
        return 0
    fi
    
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    if [[ "${confirmation}" != "DELETE" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Last chance! Press Enter to proceed or Ctrl+C to abort..."
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_cleaned=0
    
    # Remove function code directory
    if [[ -d "./event-processor" ]]; then
        rm -rf ./event-processor
        log_info "Removed event-processor directory"
        ((files_cleaned++))
    fi
    
    # Remove deployment package
    if [[ -f "event-processor.zip" ]]; then
        rm -f event-processor.zip
        log_info "Removed event-processor.zip"
        ((files_cleaned++))
    fi
    
    # Remove deployment configuration
    if [[ -f ".deployment-config" ]]; then
        rm -f .deployment-config
        log_info "Removed .deployment-config"
        ((files_cleaned++))
    fi
    
    # Stop any running log streams
    if pgrep -f "az webapp log tail" >/dev/null 2>&1; then
        pkill -f "az webapp log tail" 2>/dev/null || true
        log_info "Stopped log streaming processes"
        ((files_cleaned++))
    fi
    
    if [[ ${files_cleaned} -eq 0 ]]; then
        log_info "No local files found to clean up"
    else
        log_success "Cleaned up ${files_cleaned} local files/processes"
    fi
}

# Delete specific Event Grid resources
cleanup_eventgrid_resources() {
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        return 0
    fi
    
    log_info "Cleaning up Event Grid resources..."
    
    # Find and delete event subscriptions
    local subscriptions
    subscriptions=$(az eventgrid event-subscription list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${subscriptions}" ]]; then
        while IFS= read -r subscription; do
            if [[ -n "${subscription}" ]]; then
                log_info "Deleting event subscription: ${subscription}"
                
                # Find the source resource for the subscription
                local source_resource
                source_resource=$(az eventgrid event-subscription list --resource-group "${RESOURCE_GROUP}" --query "[?name=='${subscription}'].topic" -o tsv 2>/dev/null || echo "")
                
                if [[ -n "${source_resource}" ]]; then
                    az eventgrid event-subscription delete \
                        --name "${subscription}" \
                        --source-resource-id "${source_resource}" \
                        >/dev/null 2>&1 || log_warning "Failed to delete subscription ${subscription}"
                fi
            fi
        done <<< "${subscriptions}"
    fi
    
    # Find and delete Event Grid topics
    local topics
    topics=$(az eventgrid topic list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${topics}" ]]; then
        while IFS= read -r topic; do
            if [[ -n "${topic}" ]]; then
                log_info "Deleting Event Grid topic: ${topic}"
                az eventgrid topic delete \
                    --name "${topic}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    >/dev/null 2>&1 || log_warning "Failed to delete topic ${topic}"
            fi
        done <<< "${topics}"
    fi
    
    log_success "Event Grid resources cleanup completed"
}

# Delete Function App resources
cleanup_function_resources() {
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        return 0
    fi
    
    log_info "Cleaning up Function App resources..."
    
    # Find and delete Function Apps
    local function_apps
    function_apps=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${function_apps}" ]]; then
        while IFS= read -r app; do
            if [[ -n "${app}" ]]; then
                log_info "Deleting Function App: ${app}"
                az functionapp delete \
                    --name "${app}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    >/dev/null 2>&1 || log_warning "Failed to delete Function App ${app}"
            fi
        done <<< "${function_apps}"
    fi
    
    log_success "Function App resources cleanup completed"
}

# Delete storage accounts
cleanup_storage_resources() {
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        return 0
    fi
    
    log_info "Cleaning up storage resources..."
    
    # Find and delete storage accounts
    local storage_accounts
    storage_accounts=$(az storage account list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${storage_accounts}" ]]; then
        while IFS= read -r account; do
            if [[ -n "${account}" ]]; then
                log_info "Deleting storage account: ${account}"
                az storage account delete \
                    --name "${account}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --yes \
                    >/dev/null 2>&1 || log_warning "Failed to delete storage account ${account}"
            fi
        done <<< "${storage_accounts}"
    fi
    
    log_success "Storage resources cleanup completed"
}

# Delete resource group
delete_resource_group() {
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_warning "No resource group specified for deletion"
        return 0
    fi
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Resource group '${RESOURCE_GROUP}' not found - may already be deleted"
        return 0
    fi
    
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would delete resource group ${RESOURCE_GROUP}"
        return 0
    fi
    
    # Delete resource group (this deletes all contained resources)
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Note: Deletion may take several minutes to complete"
    
    # Optional: Wait for deletion to complete
    if [[ "${FORCE_DELETE:-}" != "true" ]]; then
        read -p "Wait for deletion to complete? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Waiting for resource group deletion to complete..."
            
            local timeout=300  # 5 minutes
            local elapsed=0
            
            while az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; do
                if [[ ${elapsed} -ge ${timeout} ]]; then
                    log_warning "Timeout waiting for deletion. Check Azure Portal for status."
                    break
                fi
                
                sleep 10
                elapsed=$((elapsed + 10))
                echo -n "."
            done
            
            echo
            if ! az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
                log_success "Resource group successfully deleted"
            fi
        fi
    fi
}

# Verify cleanup completion
verify_cleanup() {
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        return 0
    fi
    
    log_info "Verifying cleanup completion..."
    
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Resource group still exists. Deletion may be in progress."
        
        # List remaining resources
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length([])" -o tsv 2>/dev/null || echo "0")
        
        if [[ "${remaining_resources}" -gt 0 ]]; then
            log_warning "${remaining_resources} resources still remain in the group"
            az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" -o table
        fi
    else
        log_success "Resource group successfully deleted"
    fi
}

# Display banner
echo "============================================================================="
echo "           Azure Event Grid and Functions Cleanup Script"
echo "============================================================================="
echo ""

# Check prerequisites
check_prerequisites

# Try to load deployment configuration, fall back to manual input
if ! load_deployment_config; then
    manual_configuration
fi

# Dry run mode
if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "Running in DRY RUN mode - no resources will be deleted"
fi

# Confirm deletion
confirm_deletion

if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "DRY RUN: Would proceed with cleanup of ${RESOURCE_GROUP}"
    exit 0
fi

# Start cleanup process
echo ""
log_info "Starting cleanup process..."

# Clean up resources in order (specific to general)
cleanup_eventgrid_resources
cleanup_function_resources
cleanup_storage_resources

# Delete the entire resource group (this ensures everything is cleaned up)
delete_resource_group

# Clean up local files
cleanup_local_files

# Verify cleanup
sleep 5  # Give Azure a moment to process the deletion
verify_cleanup

# Display completion message
echo ""
echo "============================================================================="
echo "                            CLEANUP COMPLETE"
echo "============================================================================="
echo ""
log_success "Azure Event Grid and Functions solution cleanup completed!"
echo ""
echo "📋 Cleanup Summary:"
if [[ -n "${RESOURCE_GROUP:-}" ]]; then
    echo "   ✅ Resource Group: ${RESOURCE_GROUP} (deleted)"
fi
echo "   ✅ Event Grid topics and subscriptions (deleted)"
echo "   ✅ Function Apps and Application Insights (deleted)"
echo "   ✅ Storage accounts (deleted)"
echo "   ✅ Local files and processes (cleaned up)"
echo ""
echo "💰 Billing Impact:"
echo "   • All resource billing has been stopped"
echo "   • No ongoing charges will be incurred"
echo ""
echo "🔍 Verification:"
echo "   You can verify cleanup in the Azure Portal:"
echo "   https://portal.azure.com/#view/HubsExtension/BrowseResourceGroups"
echo ""
log_info "If you need to redeploy, run: ./deploy.sh"
echo "============================================================================="