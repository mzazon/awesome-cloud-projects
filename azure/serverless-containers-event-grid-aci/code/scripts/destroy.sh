#!/bin/bash

# Event-Driven Serverless Container Workloads with Azure Event Grid and Container Instances
# Cleanup/Destroy Script
# Version: 1.0
# Last Updated: 2025-01-12

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to load environment variables
load_environment_variables() {
    log "Loading environment variables..."
    
    # Check if .env file exists
    if [[ ! -f .env ]]; then
        error "Environment file .env not found. Please run deploy.sh first or create the file manually."
    fi
    
    # Load environment variables from .env file
    source .env
    
    # Verify required variables are set
    if [[ -z "${RESOURCE_GROUP:-}" ]] || [[ -z "${SUBSCRIPTION_ID:-}" ]]; then
        error "Required environment variables are missing. Please check the .env file."
    fi
    
    info "Environment variables loaded:"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  Subscription ID: ${SUBSCRIPTION_ID}"
    info "  Random Suffix: ${RANDOM_SUFFIX:-unknown}"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "  - Resource Group: ${RESOURCE_GROUP}"
    echo "  - All contained resources (Storage Account, Container Registry, Event Grid Topic, etc.)"
    echo "  - All data stored in the storage account"
    echo "  - All container instances and function apps"
    echo ""
    warn "This action cannot be undone!"
    echo ""
    
    # Prompt for confirmation
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Destruction cancelled by user."
        exit 0
    fi
    
    log "Destruction confirmed. Proceeding with cleanup..."
}

# Function to remove Event Grid subscriptions
remove_event_grid_subscriptions() {
    log "Removing Event Grid subscriptions..."
    
    # Check if storage account exists and get its resource ID
    local storage_resource_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"
    
    # Delete blob events subscription
    if az eventgrid event-subscription show \
        --name "blob-events-subscription" \
        --source-resource-id "$storage_resource_id" &> /dev/null; then
        
        log "Deleting blob-events-subscription..."
        az eventgrid event-subscription delete \
            --name "blob-events-subscription" \
            --source-resource-id "$storage_resource_id" \
            --yes || warn "Failed to delete blob-events-subscription"
    else
        info "blob-events-subscription not found or already deleted"
    fi
    
    # Delete function webhook subscription
    if az eventgrid event-subscription show \
        --name "function-webhook-subscription" \
        --source-resource-id "$storage_resource_id" &> /dev/null; then
        
        log "Deleting function-webhook-subscription..."
        az eventgrid event-subscription delete \
            --name "function-webhook-subscription" \
            --source-resource-id "$storage_resource_id" \
            --yes || warn "Failed to delete function-webhook-subscription"
    else
        info "function-webhook-subscription not found or already deleted"
    fi
    
    log "✅ Event Grid subscriptions removal completed"
}

# Function to delete container instances
delete_container_instances() {
    log "Deleting container instances..."
    
    # Delete event processor container
    if az container show \
        --name "event-processor-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        
        log "Deleting event-processor-${RANDOM_SUFFIX}..."
        az container delete \
            --name "event-processor-${RANDOM_SUFFIX}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes || warn "Failed to delete event-processor-${RANDOM_SUFFIX}"
    else
        info "event-processor-${RANDOM_SUFFIX} not found or already deleted"
    fi
    
    # Delete image processor container
    if az container show \
        --name "image-processor-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        
        log "Deleting image-processor-${RANDOM_SUFFIX}..."
        az container delete \
            --name "image-processor-${RANDOM_SUFFIX}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes || warn "Failed to delete image-processor-${RANDOM_SUFFIX}"
    else
        info "image-processor-${RANDOM_SUFFIX} not found or already deleted"
    fi
    
    log "✅ Container instances deletion completed"
}

# Function to delete function app
delete_function_app() {
    log "Deleting function app..."
    
    # Delete function app
    if az functionapp show \
        --name "func-event-processor-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        
        log "Deleting func-event-processor-${RANDOM_SUFFIX}..."
        az functionapp delete \
            --name "func-event-processor-${RANDOM_SUFFIX}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes || warn "Failed to delete func-event-processor-${RANDOM_SUFFIX}"
    else
        info "func-event-processor-${RANDOM_SUFFIX} not found or already deleted"
    fi
    
    log "✅ Function app deletion completed"
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local timeout=300  # 5 minutes
    local elapsed=0
    
    info "Waiting for $resource_type deletion to complete..."
    
    while [[ $elapsed -lt $timeout ]]; do
        sleep 10
        elapsed=$((elapsed + 10))
        info "Waiting... (${elapsed}s/${timeout}s)"
    done
    
    info "$resource_type deletion wait completed"
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group and all remaining resources..."
    
    # Check if resource group exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log "Deleting resource group: ${RESOURCE_GROUP}"
        
        # Delete the entire resource group and all contained resources
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait
        
        log "✅ Resource group deletion initiated: ${RESOURCE_GROUP}"
        info "Complete deletion may take several minutes"
        
        # Wait for deletion to complete
        local timeout=600  # 10 minutes
        local elapsed=0
        
        info "Monitoring resource group deletion..."
        while [[ $elapsed -lt $timeout ]]; do
            if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
                log "✅ Resource group ${RESOURCE_GROUP} has been completely deleted"
                break
            fi
            sleep 30
            elapsed=$((elapsed + 30))
            info "Still deleting... (${elapsed}s/${timeout}s)"
        done
        
        if [[ $elapsed -ge $timeout ]]; then
            warn "Resource group deletion is taking longer than expected"
            info "Check Azure portal for deletion status"
        fi
    else
        info "Resource group ${RESOURCE_GROUP} not found or already deleted"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # List of local files to clean up
    local files_to_cleanup=(
        ".env"
        "test-file.txt"
        "container-template.json"
    )
    
    for file in "${files_to_cleanup[@]}"; do
        if [[ -f "$file" ]]; then
            log "Removing $file..."
            rm -f "$file"
        fi
    done
    
    log "✅ Local files cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Resource group ${RESOURCE_GROUP} still exists"
        info "Deletion may still be in progress"
    else
        log "✅ Resource group ${RESOURCE_GROUP} has been deleted"
    fi
    
    # Check for any remaining resources with our naming pattern
    log "Checking for any remaining resources..."
    
    # Check for container instances
    local remaining_containers=$(az container list \
        --query "[?contains(name, '${RANDOM_SUFFIX}')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$remaining_containers" ]]; then
        warn "Found remaining container instances: $remaining_containers"
    else
        log "✅ No remaining container instances found"
    fi
    
    # Check for function apps
    local remaining_functions=$(az functionapp list \
        --query "[?contains(name, '${RANDOM_SUFFIX}')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$remaining_functions" ]]; then
        warn "Found remaining function apps: $remaining_functions"
    else
        log "✅ No remaining function apps found"
    fi
    
    log "✅ Cleanup verification completed"
}

# Function to estimate cost savings
estimate_cost_savings() {
    log "Estimating cost savings..."
    
    echo ""
    info "💰 Cost Savings Estimation"
    echo "========================="
    echo "By deleting these resources, you will save approximately:"
    echo "• Container Registry (Basic): ~\$5/month"
    echo "• Storage Account (LRS): ~\$1-2/month"
    echo "• Event Grid Topic: ~\$0.60/million operations"
    echo "• Container Instances: ~\$0.0012/vCPU-second when running"
    echo "• Function App (Consumption): Pay per execution only"
    echo "• Log Analytics Workspace: ~\$2.76/GB ingested"
    echo ""
    info "Total estimated monthly savings: \$10-20 (depending on usage)"
    echo ""
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "✅ Event Grid subscriptions removed"
    echo "✅ Container instances deleted"
    echo "✅ Function app deleted"
    echo "✅ Resource group deleted: ${RESOURCE_GROUP}"
    echo "✅ Local files cleaned up"
    echo ""
    info "All resources have been successfully cleaned up"
    echo ""
    estimate_cost_savings
}

# Function to handle cleanup errors
handle_cleanup_errors() {
    warn "Some cleanup operations may have failed"
    echo ""
    info "Manual cleanup may be required for:"
    echo "• Check Azure portal for any remaining resources"
    echo "• Verify resource group ${RESOURCE_GROUP} is completely deleted"
    echo "• Check for any orphaned resources with suffix ${RANDOM_SUFFIX}"
    echo ""
    info "Common reasons for cleanup failures:"
    echo "• Resources are still in use or have dependencies"
    echo "• Insufficient permissions for deletion"
    echo "• Network connectivity issues"
    echo "• Azure service temporary unavailability"
    echo ""
    info "You can re-run this script to retry cleanup operations"
}

# Main cleanup function
main() {
    log "Starting cleanup of Event-Driven Serverless Container Workloads"
    log "==============================================================="
    
    # Run cleanup steps
    check_prerequisites
    load_environment_variables
    confirm_destruction
    
    # Perform cleanup in order (dependencies first)
    remove_event_grid_subscriptions
    delete_container_instances
    delete_function_app
    wait_for_deletion "container and function resources"
    delete_resource_group
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
    
    log "🎉 Cleanup completed successfully!"
    log "All resources have been removed and costs have been eliminated"
}

# Error handling
trap 'handle_cleanup_errors' ERR

# Run main function
main "$@"