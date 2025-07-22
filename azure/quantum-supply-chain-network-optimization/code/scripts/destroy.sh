#!/bin/bash

# Azure Quantum Supply Chain Network Optimization - Cleanup Script
# This script removes all resources created for the quantum supply chain optimization solution
# to avoid ongoing costs and clean up the Azure subscription

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Banner
echo -e "${RED}"
echo "=================================================================="
echo "  Azure Quantum Supply Chain Optimization - CLEANUP"
echo "=================================================================="
echo -e "${NC}"

# Prerequisites check
log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error "Not logged into Azure. Please run 'az login' first."
    exit 1
fi

success "Prerequisites check completed"

# Check for deployment configuration file
DEPLOYMENT_CONFIG="deployment-config.json"
if [ -f "$DEPLOYMENT_CONFIG" ]; then
    log "Found deployment configuration file: $DEPLOYMENT_CONFIG"
    
    # Extract resource information from config
    RESOURCE_GROUP=$(jq -r '.resource_group' "$DEPLOYMENT_CONFIG" 2>/dev/null)
    LOCATION=$(jq -r '.location' "$DEPLOYMENT_CONFIG" 2>/dev/null)
    QUANTUM_WORKSPACE=$(jq -r '.resources.quantum_workspace' "$DEPLOYMENT_CONFIG" 2>/dev/null)
    DIGITAL_TWINS_INSTANCE=$(jq -r '.resources.digital_twins_instance' "$DEPLOYMENT_CONFIG" 2>/dev/null)
    FUNCTION_APP=$(jq -r '.resources.function_app' "$DEPLOYMENT_CONFIG" 2>/dev/null)
    STREAM_ANALYTICS_JOB=$(jq -r '.resources.stream_analytics_job' "$DEPLOYMENT_CONFIG" 2>/dev/null)
    STORAGE_ACCOUNT=$(jq -r '.resources.storage_account' "$DEPLOYMENT_CONFIG" 2>/dev/null)
    COSMOS_ACCOUNT=$(jq -r '.resources.cosmos_account' "$DEPLOYMENT_CONFIG" 2>/dev/null)
    EVENT_HUB_NAMESPACE=$(jq -r '.resources.event_hub_namespace' "$DEPLOYMENT_CONFIG" 2>/dev/null)
    
    if [ "$RESOURCE_GROUP" = "null" ] || [ -z "$RESOURCE_GROUP" ]; then
        warning "Could not parse deployment configuration. Will attempt interactive cleanup."
        RESOURCE_GROUP=""
    else
        log "Using configuration: Resource Group = $RESOURCE_GROUP"
    fi
else
    warning "No deployment configuration file found. Will attempt interactive cleanup."
    RESOURCE_GROUP=""
fi

# If no config file or parsing failed, try to get resource group interactively
if [ -z "$RESOURCE_GROUP" ]; then
    echo ""
    echo -e "${YELLOW}Please select the resource group to clean up:${NC}"
    
    # List resource groups that contain quantum-related resources
    QUANTUM_RESOURCE_GROUPS=$(az group list --query "[?contains(name, 'quantum') || contains(name, 'supplychain')].name" --output tsv 2>/dev/null)
    
    if [ -n "$QUANTUM_RESOURCE_GROUPS" ]; then
        echo "Found potential quantum supply chain resource groups:"
        echo "$QUANTUM_RESOURCE_GROUPS" | nl -w2 -s') '
        echo ""
        read -p "Enter the resource group name (or press Enter to cancel): " RESOURCE_GROUP
        
        if [ -z "$RESOURCE_GROUP" ]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    else
        read -p "Enter the resource group name to clean up: " RESOURCE_GROUP
        
        if [ -z "$RESOURCE_GROUP" ]; then
            error "Resource group name is required"
            exit 1
        fi
    fi
fi

# Verify resource group exists
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    error "Resource group '$RESOURCE_GROUP' does not exist or is not accessible"
    exit 1
fi

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
log "Current subscription: $SUBSCRIPTION_ID"

# List resources in the resource group
log "Listing resources in resource group: $RESOURCE_GROUP"
RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output table 2>/dev/null)

if [ -z "$RESOURCES" ]; then
    log "No resources found in resource group: $RESOURCE_GROUP"
    echo ""
    read -p "Delete empty resource group? (y/N): " DELETE_EMPTY_RG
    if [[ "$DELETE_EMPTY_RG" =~ ^[Yy]$ ]]; then
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait
        success "Empty resource group deletion initiated"
    fi
    exit 0
fi

echo ""
echo "Resources found in resource group '$RESOURCE_GROUP':"
echo "$RESOURCES"
echo ""

# Confirmation prompt
echo -e "${RED}WARNING: This will permanently delete ALL resources in the resource group!${NC}"
echo -e "${RED}This action cannot be undone!${NC}"
echo ""
read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " CONFIRMATION

if [ "$CONFIRMATION" != "DELETE" ]; then
    log "Cleanup cancelled by user"
    exit 0
fi

# Start cleanup process
log "Starting resource cleanup process..."

# Function to check if resource exists and delete it
cleanup_resource() {
    local resource_type=$1
    local resource_name=$2
    local additional_params=$3
    
    if [ -z "$resource_name" ] || [ "$resource_name" = "null" ]; then
        return 0
    fi
    
    log "Cleaning up $resource_type: $resource_name"
    
    case $resource_type in
        "quantum-workspace")
            if az quantum workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$resource_name" &> /dev/null; then
                az quantum workspace delete --resource-group "$RESOURCE_GROUP" --workspace-name "$resource_name" --yes --no-wait
                success "Quantum workspace deletion initiated"
            else
                warning "Quantum workspace not found or already deleted"
            fi
            ;;
        "digital-twins")
            if az dt show --dt-name "$resource_name" &> /dev/null; then
                az dt delete --dt-name "$resource_name" --yes
                success "Digital Twins instance deleted"
            else
                warning "Digital Twins instance not found or already deleted"
            fi
            ;;
        "function-app")
            if az functionapp show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &> /dev/null; then
                az functionapp delete --resource-group "$RESOURCE_GROUP" --name "$resource_name"
                success "Function App deleted"
            else
                warning "Function App not found or already deleted"
            fi
            ;;
        "stream-analytics")
            if az stream-analytics job show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &> /dev/null; then
                az stream-analytics job delete --resource-group "$RESOURCE_GROUP" --name "$resource_name" --yes
                success "Stream Analytics job deleted"
            else
                warning "Stream Analytics job not found or already deleted"
            fi
            ;;
        "storage-account")
            if az storage account show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &> /dev/null; then
                az storage account delete --resource-group "$RESOURCE_GROUP" --name "$resource_name" --yes
                success "Storage account deleted"
            else
                warning "Storage account not found or already deleted"
            fi
            ;;
        "cosmos-account")
            if az cosmosdb show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &> /dev/null; then
                az cosmosdb delete --resource-group "$RESOURCE_GROUP" --name "$resource_name" --yes
                success "Cosmos DB account deleted"
            else
                warning "Cosmos DB account not found or already deleted"
            fi
            ;;
        "event-hub-namespace")
            if az eventhubs namespace show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &> /dev/null; then
                az eventhubs namespace delete --resource-group "$RESOURCE_GROUP" --name "$resource_name"
                success "Event Hub namespace deleted"
            else
                warning "Event Hub namespace not found or already deleted"
            fi
            ;;
    esac
}

# Clean up resources in dependency order (reverse of creation order)
log "Cleaning up individual resources..."

# Delete Application Insights and Log Analytics workspace first
APP_INSIGHTS_RESOURCES=$(az monitor app-insights component list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
if [ -n "$APP_INSIGHTS_RESOURCES" ]; then
    for app_insight in $APP_INSIGHTS_RESOURCES; do
        log "Deleting Application Insights: $app_insight"
        az monitor app-insights component delete --resource-group "$RESOURCE_GROUP" --app "$app_insight" --yes
    done
    success "Application Insights resources deleted"
fi

LA_WORKSPACES=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
if [ -n "$LA_WORKSPACES" ]; then
    for workspace in $LA_WORKSPACES; do
        log "Deleting Log Analytics workspace: $workspace"
        az monitor log-analytics workspace delete --resource-group "$RESOURCE_GROUP" --workspace-name "$workspace" --yes --force
    done
    success "Log Analytics workspaces deleted"
fi

# Clean up main resources
cleanup_resource "stream-analytics" "$STREAM_ANALYTICS_JOB"
cleanup_resource "function-app" "$FUNCTION_APP"
cleanup_resource "digital-twins" "$DIGITAL_TWINS_INSTANCE"
cleanup_resource "event-hub-namespace" "$EVENT_HUB_NAMESPACE"
cleanup_resource "cosmos-account" "$COSMOS_ACCOUNT"
cleanup_resource "quantum-workspace" "$QUANTUM_WORKSPACE"
cleanup_resource "storage-account" "$STORAGE_ACCOUNT"

# Wait a moment for async operations to start
log "Waiting for resource deletion operations to complete..."
sleep 10

# Check for any remaining resources
REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null)
if [ -n "$REMAINING_RESOURCES" ]; then
    warning "Some resources may still be present:"
    echo "$REMAINING_RESOURCES"
    log "These resources will be deleted with the resource group"
fi

# Delete the entire resource group
log "Deleting resource group: $RESOURCE_GROUP"
echo ""
echo -e "${YELLOW}Final confirmation: Delete resource group '$RESOURCE_GROUP' and all remaining resources?${NC}"
read -p "Type 'YES' to confirm: " FINAL_CONFIRMATION

if [ "$FINAL_CONFIRMATION" = "YES" ]; then
    if az group delete --name "$RESOURCE_GROUP" --yes --no-wait; then
        success "Resource group deletion initiated"
        log "Resource group '$RESOURCE_GROUP' is being deleted in the background"
    else
        error "Failed to delete resource group"
        exit 1
    fi
else
    warning "Resource group deletion cancelled"
    log "Individual resources have been cleaned up, but resource group remains"
fi

# Clean up local files
log "Cleaning up local files..."
if [ -f "deployment-config.json" ]; then
    rm -f deployment-config.json
    success "Deployment configuration file removed"
fi

if [ -f "supplier-model.json" ]; then
    rm -f supplier-model.json
    success "Supplier model file removed"
fi

if [ -f "warehouse-model.json" ]; then
    rm -f warehouse-model.json
    success "Warehouse model file removed"
fi

# Final summary
echo ""
echo -e "${GREEN}"
echo "=================================================================="
echo "  CLEANUP COMPLETED"
echo "=================================================================="
echo -e "${NC}"

if [ "$FINAL_CONFIRMATION" = "YES" ]; then
    echo "✅ Resource group '$RESOURCE_GROUP' deletion initiated"
    echo "✅ All Azure resources will be removed"
    echo "✅ Local configuration files cleaned up"
    echo ""
    echo "Note: Resource group deletion may take several minutes to complete."
    echo "You can check the status in the Azure portal or by running:"
    echo "  az group show --name '$RESOURCE_GROUP'"
else
    echo "✅ Individual resources cleaned up"
    echo "⚠️  Resource group '$RESOURCE_GROUP' still exists"
    echo "✅ Local configuration files cleaned up"
    echo ""
    echo "To manually delete the resource group later, run:"
    echo "  az group delete --name '$RESOURCE_GROUP' --yes"
fi

echo ""
echo -e "${GREEN}Cleanup process completed successfully!${NC}"
echo ""
echo -e "${YELLOW}Cost Impact:${NC}"
echo "• All billable resources have been removed"
echo "• No ongoing charges will be incurred"
echo "• Storage data has been permanently deleted"
echo ""
echo "If you need to redeploy, run the deploy.sh script again."

success "Cleanup completed successfully!"