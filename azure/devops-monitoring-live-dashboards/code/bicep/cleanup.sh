#!/bin/bash

# Azure DevOps Monitoring Live Dashboards - Cleanup Script
# This script removes all resources created for the monitoring dashboard solution

set -e

# Default values
RESOURCE_GROUP=""
FORCE=false
KEEP_RESOURCE_GROUP=false
SUBSCRIPTION_ID=""

# Function to display usage
usage() {
    echo "Usage: $0 -g <resource-group> [-f] [-k] [-s <subscription-id>]"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group     Resource group name (required)"
    echo "  -f, --force              Skip confirmation prompts"
    echo "  -k, --keep-resource-group Keep the resource group after cleanup"
    echo "  -s, --subscription-id    Azure subscription ID (optional)"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -g rg-monitoring-demo"
    echo "  $0 -g rg-monitoring-prod -f -k"
    echo "  $0 -g rg-monitoring-test -s 12345678-1234-1234-1234-123456789012"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -k|--keep-resource-group)
            KEEP_RESOURCE_GROUP=true
            shift
            ;;
        -s|--subscription-id)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required parameters
if [[ -z "$RESOURCE_GROUP" ]]; then
    echo "Error: Resource group name is required"
    usage
fi

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo "Error: Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Set subscription if provided
if [[ -n "$SUBSCRIPTION_ID" ]]; then
    echo "Setting subscription to: $SUBSCRIPTION_ID"
    az account set --subscription "$SUBSCRIPTION_ID"
fi

# Get current subscription info
CURRENT_SUBSCRIPTION=$(az account show --query "name" -o tsv)
CURRENT_SUBSCRIPTION_ID=$(az account show --query "id" -o tsv)

echo "========================================="
echo "Azure DevOps Monitoring Live Dashboards"
echo "CLEANUP SCRIPT"
echo "========================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Subscription: $CURRENT_SUBSCRIPTION ($CURRENT_SUBSCRIPTION_ID)"
echo "Keep Resource Group: $KEEP_RESOURCE_GROUP"
echo "Force: $FORCE"
echo "========================================="

# Check if resource group exists
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    echo "Resource group '$RESOURCE_GROUP' does not exist. Nothing to clean up."
    exit 0
fi

# List resources that will be deleted
echo "Resources to be deleted:"
echo "----------------------------------------"
az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table

# Confirmation prompt
if [[ "$FORCE" != true ]]; then
    echo ""
    echo "⚠️  WARNING: This will permanently delete all resources in the resource group!"
    echo "   Resource Group: $RESOURCE_GROUP"
    echo "   Subscription: $CURRENT_SUBSCRIPTION"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
fi

# Delete resources
if [[ "$KEEP_RESOURCE_GROUP" == true ]]; then
    echo "Deleting resources in resource group '$RESOURCE_GROUP'..."
    
    # Get list of resources
    RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].id" --output tsv)
    
    if [[ -n "$RESOURCES" ]]; then
        # Delete resources one by one to handle dependencies
        echo "Deleting individual resources..."
        
        # Delete metric alerts first
        az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Insights/metricAlerts" --query "[].id" --output tsv | while read -r resource_id; do
            if [[ -n "$resource_id" ]]; then
                echo "Deleting metric alert: $resource_id"
                az resource delete --ids "$resource_id" --verbose
            fi
        done
        
        # Delete action groups
        az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Insights/actionGroups" --query "[].id" --output tsv | while read -r resource_id; do
            if [[ -n "$resource_id" ]]; then
                echo "Deleting action group: $resource_id"
                az resource delete --ids "$resource_id" --verbose
            fi
        done
        
        # Delete web apps
        az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Web/sites" --query "[].id" --output tsv | while read -r resource_id; do
            if [[ -n "$resource_id" ]]; then
                echo "Deleting web app: $resource_id"
                az resource delete --ids "$resource_id" --verbose
            fi
        done
        
        # Delete app service plans
        az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Web/serverfarms" --query "[].id" --output tsv | while read -r resource_id; do
            if [[ -n "$resource_id" ]]; then
                echo "Deleting app service plan: $resource_id"
                az resource delete --ids "$resource_id" --verbose
            fi
        done
        
        # Delete SignalR service
        az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.SignalRService/signalR" --query "[].id" --output tsv | while read -r resource_id; do
            if [[ -n "$resource_id" ]]; then
                echo "Deleting SignalR service: $resource_id"
                az resource delete --ids "$resource_id" --verbose
            fi
        done
        
        # Delete Application Insights
        az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Insights/components" --query "[].id" --output tsv | while read -r resource_id; do
            if [[ -n "$resource_id" ]]; then
                echo "Deleting Application Insights: $resource_id"
                az resource delete --ids "$resource_id" --verbose
            fi
        done
        
        # Delete Log Analytics workspace
        az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.OperationalInsights/workspaces" --query "[].id" --output tsv | while read -r resource_id; do
            if [[ -n "$resource_id" ]]; then
                echo "Deleting Log Analytics workspace: $resource_id"
                az resource delete --ids "$resource_id" --verbose
            fi
        done
        
        # Delete storage accounts last
        az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Storage/storageAccounts" --query "[].id" --output tsv | while read -r resource_id; do
            if [[ -n "$resource_id" ]]; then
                echo "Deleting storage account: $resource_id"
                az resource delete --ids "$resource_id" --verbose
            fi
        done
        
        echo "✅ All resources deleted from resource group '$RESOURCE_GROUP'"
    else
        echo "No resources found in resource group '$RESOURCE_GROUP'"
    fi
else
    echo "Deleting resource group '$RESOURCE_GROUP' and all its resources..."
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    echo "✅ Resource group deletion initiated"
    echo "Note: Deletion may take several minutes to complete"
fi

# Clean up any remaining deployments
echo ""
echo "Cleaning up deployment history..."
az deployment group list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null | while read -r deployment_name; do
    if [[ -n "$deployment_name" ]]; then
        echo "Deleting deployment: $deployment_name"
        az deployment group delete --resource-group "$RESOURCE_GROUP" --name "$deployment_name" 2>/dev/null || true
    fi
done

echo ""
echo "========================================="
echo "Cleanup completed successfully!"
echo "========================================="

if [[ "$KEEP_RESOURCE_GROUP" == true ]]; then
    echo "Resource group '$RESOURCE_GROUP' has been kept as requested."
else
    echo "Resource group '$RESOURCE_GROUP' deletion has been initiated."
    echo "You can check the deletion status with:"
    echo "  az group show --name '$RESOURCE_GROUP'"
fi

echo ""
echo "Additional cleanup tasks:"
echo "1. Remove any Azure DevOps Service Hook configurations"
echo "2. Clean up any local configuration files"
echo "3. Remove any custom domain configurations"
echo "4. Check for any remaining costs in Azure Cost Management"