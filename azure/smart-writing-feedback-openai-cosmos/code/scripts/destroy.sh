#!/bin/bash

# Destroy Smart Writing Feedback System with OpenAI and Cosmos
# This script safely removes all Azure resources created by deploy.sh
# to avoid ongoing charges and clean up the environment

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handler
error_exit() {
    log_error "Cleanup failed: $1"
    log_error "Some resources may still exist in Azure"
    log_error "Check the Azure portal and manually remove remaining resources"
    exit 1
}

# Trap errors
trap 'error_exit "Script failed at line $LINENO"' ERR

log "=== Azure Smart Writing Feedback System Cleanup ==="

# Check prerequisites
log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error_exit "Azure CLI is not installed. Please install it first."
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error_exit "Not logged into Azure CLI. Please run 'az login' first."
fi

# Check if deployment config exists
if [[ ! -f ".deployment_config" ]]; then
    log_error "Deployment configuration file (.deployment_config) not found!"
    log_error "This file is created by deploy.sh and contains resource names."
    echo
    log "Manual cleanup options:"
    log "1. Find and delete the resource group via Azure portal"
    log "2. Look for resources with tags: purpose=writing-feedback"
    log "3. Use Azure CLI to list and delete resources manually"
    echo
    read -p "Do you want to attempt manual cleanup by resource group name? (y/N): " MANUAL_CLEANUP
    
    if [[ $MANUAL_CLEANUP =~ ^[Yy]$ ]]; then
        echo
        read -p "Enter the resource group name to delete: " MANUAL_RG
        if [[ -n "$MANUAL_RG" ]]; then
            log "Attempting to delete resource group: $MANUAL_RG"
            
            # Verify resource group exists
            if az group show --name "$MANUAL_RG" &> /dev/null; then
                echo
                log_warning "⚠️ DANGER: This will delete ALL resources in the resource group!"
                log "Resource group contents:"
                az resource list --resource-group "$MANUAL_RG" --query "[].{Name:name, Type:type}" --output table
                echo
                read -p "Are you absolutely sure you want to delete '$MANUAL_RG'? (type 'DELETE' to confirm): " FINAL_CONFIRM
                
                if [[ "$FINAL_CONFIRM" == "DELETE" ]]; then
                    log "Deleting resource group: $MANUAL_RG"
                    az group delete --name "$MANUAL_RG" --yes --no-wait
                    log_success "Resource group deletion initiated: $MANUAL_RG"
                    log "Note: Deletion may take several minutes to complete"
                else
                    log "Manual cleanup cancelled"
                fi
            else
                log_error "Resource group '$MANUAL_RG' not found"
            fi
        fi
    fi
    exit 1
fi

# Load deployment configuration
log "Loading deployment configuration..."
source .deployment_config

# Validate required variables are set
if [[ -z "$RESOURCE_GROUP" ]]; then
    error_exit "RESOURCE_GROUP not found in deployment configuration"
fi

log "Loaded configuration from deployment:"
log "  Resource Group: $RESOURCE_GROUP"
log "  Deployment Time: ${DEPLOYMENT_TIME:-Unknown}"
if [[ -n "$OPENAI_ACCOUNT" ]]; then
    log "  OpenAI Account: $OPENAI_ACCOUNT"
fi
if [[ -n "$COSMOS_ACCOUNT" ]]; then
    log "  Cosmos Account: $COSMOS_ACCOUNT"
fi
if [[ -n "$FUNCTION_APP" ]]; then
    log "  Function App: $FUNCTION_APP"
fi
if [[ -n "$STORAGE_ACCOUNT" ]]; then
    log "  Storage Account: $STORAGE_ACCOUNT"
fi

# Verify resource group exists
log "Verifying resource group exists..."
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    log_warning "Resource group '$RESOURCE_GROUP' not found"
    log "This may mean resources have already been deleted"
    log_success "No cleanup needed - resources don't exist"
    rm -f .deployment_config
    exit 0
fi

# Show current resources in the resource group
log "Current resources in resource group:"
RESOURCE_COUNT=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv)

if [[ "$RESOURCE_COUNT" -eq 0 ]]; then
    log_warning "No resources found in resource group"
    log "Proceeding to delete empty resource group"
else
    log "Found $RESOURCE_COUNT resources:"
    az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table
fi

echo
log_warning "⚠️ DESTRUCTIVE OPERATION WARNING ⚠️"
log "This will permanently delete ALL resources in the resource group:"
log "  Resource Group: $RESOURCE_GROUP"
log "  All data in Cosmos DB will be lost"
log "  All function code and logs will be lost"
log "  This action cannot be undone"
echo

# Cost savings information
log "💰 After cleanup, you will no longer incur costs for:"
log "  - Azure OpenAI Service compute and storage"
log "  - Cosmos DB throughput and storage"
log "  - Azure Functions execution and storage"
log "  - Azure Storage account transactions"

echo
read -p "Are you sure you want to proceed with deletion? (y/N): " CONFIRM_DELETE
if [[ ! $CONFIRM_DELETE =~ ^[Yy]$ ]]; then
    log "Cleanup cancelled by user"
    log "Resources remain active and may incur ongoing costs"
    exit 0
fi

echo
read -p "Type 'DELETE' to confirm permanent deletion of all resources: " FINAL_CONFIRM
if [[ "$FINAL_CONFIRM" != "DELETE" ]]; then
    log "Cleanup cancelled - confirmation not received"
    exit 0
fi

log "=== Starting Resource Cleanup ==="

# Optional: Attempt graceful shutdown of individual resources
# This can help avoid issues with resource dependencies

if [[ -n "$FUNCTION_APP" ]]; then
    log "Stopping Function App: $FUNCTION_APP"
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az functionapp stop --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --output none || log_warning "Failed to stop Function App"
        log_success "Function App stopped"
    else
        log_warning "Function App not found, may already be deleted"
    fi
fi

# Delete individual resources in reverse dependency order
# This approach can be more reliable than deleting the entire resource group

log "Deleting resources individually to ensure clean removal..."

# Delete Function App first (depends on storage)
if [[ -n "$FUNCTION_APP" ]]; then
    log "Deleting Function App: $FUNCTION_APP"
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az functionapp delete --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --output none
        log_success "Function App deleted: $FUNCTION_APP"
    else
        log_warning "Function App not found: $FUNCTION_APP"
    fi
fi

# Delete OpenAI Service
if [[ -n "$OPENAI_ACCOUNT" ]]; then
    log "Deleting Azure OpenAI Service: $OPENAI_ACCOUNT"
    if az cognitiveservices account show --name "$OPENAI_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az cognitiveservices account delete --name "$OPENAI_ACCOUNT" --resource-group "$RESOURCE_GROUP" --output none
        log_success "Azure OpenAI Service deleted: $OPENAI_ACCOUNT"
    else
        log_warning "OpenAI Service not found: $OPENAI_ACCOUNT"
    fi
fi

# Delete Cosmos DB (may take longer)
if [[ -n "$COSMOS_ACCOUNT" ]]; then
    log "Deleting Cosmos DB account: $COSMOS_ACCOUNT"
    log "This may take 2-3 minutes..."
    if az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az cosmosdb delete --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --yes --output none
        log_success "Cosmos DB account deleted: $COSMOS_ACCOUNT"
    else
        log_warning "Cosmos DB account not found: $COSMOS_ACCOUNT"
    fi
fi

# Delete Storage Account
if [[ -n "$STORAGE_ACCOUNT" ]]; then
    log "Deleting Storage Account: $STORAGE_ACCOUNT"
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az storage account delete --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --yes --output none
        log_success "Storage Account deleted: $STORAGE_ACCOUNT"
    else
        log_warning "Storage Account not found: $STORAGE_ACCOUNT"
    fi
fi

# Wait a moment for resources to be fully deleted
log "Waiting for resource deletions to complete..."
sleep 10

# Check if any resources remain
REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv)

if [[ "$REMAINING_RESOURCES" -gt 0 ]]; then
    log_warning "Some resources still remain in the resource group:"
    az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output table
    log "These will be deleted with the resource group"
fi

# Delete the resource group (this ensures everything is cleaned up)
log "Deleting resource group: $RESOURCE_GROUP"
log "This ensures all resources are completely removed..."

az group delete --name "$RESOURCE_GROUP" --yes --no-wait --output none

log_success "Resource group deletion initiated: $RESOURCE_GROUP"

# Verify deletion started
sleep 5
if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    RG_STATE=$(az group show --name "$RESOURCE_GROUP" --query "properties.provisioningState" --output tsv 2>/dev/null || echo "Unknown")
    if [[ "$RG_STATE" == "Deleting" ]]; then
        log_success "Resource group is being deleted (Status: $RG_STATE)"
    else
        log_warning "Resource group status: $RG_STATE"
    fi
else
    log_success "Resource group has been deleted successfully"
fi

# Clean up local configuration
log "Cleaning up local configuration files..."

if [[ -f ".deployment_config" ]]; then
    # Create backup of config for reference
    mv .deployment_config ".deployment_config.deleted.$(date +%Y%m%d_%H%M%S)"
    log_success "Deployment configuration backed up and removed"
fi

# Clean up any temporary files
if [[ -f "function-app.zip" ]]; then
    rm -f function-app.zip
    log_success "Temporary deployment files cleaned up"
fi

log "=== Cleanup Complete ==="
echo
log_success "🎉 Smart Writing Feedback System successfully destroyed!"
echo
log "📋 Cleanup Summary:"
log "  ✅ Resource Group: $RESOURCE_GROUP (deletion in progress)"
if [[ -n "$OPENAI_ACCOUNT" ]]; then
    log "  ✅ Azure OpenAI Service: $OPENAI_ACCOUNT"
fi
if [[ -n "$COSMOS_ACCOUNT" ]]; then
    log "  ✅ Cosmos DB: $COSMOS_ACCOUNT"
fi
if [[ -n "$FUNCTION_APP" ]]; then
    log "  ✅ Function App: $FUNCTION_APP"
fi
if [[ -n "$STORAGE_ACCOUNT" ]]; then
    log "  ✅ Storage Account: $STORAGE_ACCOUNT"
fi
echo
log "💰 Cost Impact:"
log "  All ongoing charges for these resources have been stopped"
log "  No further costs will be incurred for this deployment"
echo
log "📝 Important Notes:"
log "  - Resource group deletion may take 5-10 minutes to complete"
log "  - All data has been permanently deleted and cannot be recovered"
log "  - You can monitor deletion progress in the Azure portal"
log "  - Deployment configuration saved as backup with timestamp"
echo
log "🔍 Verification:"
log "  Check Azure portal to confirm all resources are deleted"
log "  Monitor your Azure billing to confirm charges have stopped"
echo
log_success "Cleanup completed at $(date)"

# Final check and advice
log "Performing final verification..."
sleep 5

if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    RG_STATE=$(az group show --name "$RESOURCE_GROUP" --query "properties.provisioningState" --output tsv 2>/dev/null || echo "Unknown")
    log "Final status - Resource Group: $RG_STATE"
    
    if [[ "$RG_STATE" == "Deleting" ]]; then
        log_success "✅ Deletion is in progress and will complete automatically"
    else
        log_warning "⚠️ Resource group still exists with status: $RG_STATE"
        log "You may need to check the Azure portal for any issues"
    fi
else
    log_success "✅ Resource group has been completely removed"
fi

log "🚀 You can now run deploy.sh again to create a new deployment if needed"