#!/bin/bash
# ==============================================================================
# Azure Bicep Cleanup Script for Financial Fraud Detection Solution
# ==============================================================================
# This script removes all resources created by the fraud detection solution
# 
# WARNING: This script will permanently delete all resources and data.
# Make sure you have backed up any important data before running this script.
# 
# Usage:
# ./cleanup.sh [resource-group-name]
# 
# Example:
# ./cleanup.sh rg-fraud-detection-dev
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Default values
RESOURCE_GROUP_NAME="${1:-rg-fraud-detection-dev}"
SUBSCRIPTION_ID=$(az account show --query id --output tsv)

print_warning "==============================================="
print_warning "        RESOURCE CLEANUP WARNING"
print_warning "==============================================="
print_warning "This script will PERMANENTLY DELETE:"
print_warning "- Resource Group: $RESOURCE_GROUP_NAME"
print_warning "- All resources within the resource group"
print_warning "- All data including fraud detection logs"
print_warning "- All AI model configurations"
print_warning "- All monitoring and alert configurations"
print_warning "==============================================="

# Check if Azure CLI is installed and authenticated
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Check if resource group exists
if ! az group show --name "$RESOURCE_GROUP_NAME" &> /dev/null; then
    print_error "Resource group '$RESOURCE_GROUP_NAME' not found."
    exit 1
fi

# Display resources that will be deleted
print_status "Resources that will be deleted:"
az resource list \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --output table \
    --query '[].{Name:name, Type:type, Location:location}'

echo ""
print_warning "This action cannot be undone!"
read -p "Are you sure you want to delete resource group '$RESOURCE_GROUP_NAME' and all its resources? (type 'yes' to confirm): " -r
echo

if [[ ! $REPLY == "yes" ]]; then
    print_status "Cleanup cancelled by user."
    exit 0
fi

# Additional confirmation for production environments
if [[ $RESOURCE_GROUP_NAME == *"prod"* ]]; then
    print_error "Production environment detected!"
    print_warning "Extra confirmation required for production cleanup."
    read -p "Type 'DELETE-PRODUCTION' to confirm deletion of production resources: " -r
    echo
    
    if [[ ! $REPLY == "DELETE-PRODUCTION" ]]; then
        print_status "Production cleanup cancelled."
        exit 0
    fi
fi

# Start cleanup process
print_status "Starting cleanup process..."
print_status "Subscription: $SUBSCRIPTION_ID"
print_status "Resource Group: $RESOURCE_GROUP_NAME"

# Step 1: Check for Key Vault soft-delete protection
print_status "Checking for Key Vault soft-delete protection..."
KEY_VAULTS=$(az keyvault list \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query '[].name' \
    --output tsv)

if [[ -n $KEY_VAULTS ]]; then
    print_status "Found Key Vaults that may require special handling:"
    for vault in $KEY_VAULTS; do
        echo "  - $vault"
    done
    
    # Disable soft-delete protection if needed
    for vault in $KEY_VAULTS; do
        print_status "Preparing Key Vault '$vault' for deletion..."
        az keyvault update \
            --name "$vault" \
            --enable-soft-delete false \
            --output none 2>/dev/null || true
    done
fi

# Step 2: Stop Logic Apps to prevent ongoing executions
print_status "Stopping Logic Apps..."
LOGIC_APPS=$(az logic workflow list \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query '[].name' \
    --output tsv)

if [[ -n $LOGIC_APPS ]]; then
    for app in $LOGIC_APPS; do
        print_status "Stopping Logic App: $app"
        az logic workflow update \
            --resource-group "$RESOURCE_GROUP_NAME" \
            --name "$app" \
            --state "Disabled" \
            --output none || true
    done
fi

# Step 3: Delete diagnostic settings (these can sometimes block resource deletion)
print_status "Cleaning up diagnostic settings..."
RESOURCES=$(az resource list \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query '[].id' \
    --output tsv)

for resource in $RESOURCES; do
    DIAGNOSTIC_SETTINGS=$(az monitor diagnostic-settings list \
        --resource "$resource" \
        --query '[].name' \
        --output tsv 2>/dev/null || true)
    
    if [[ -n $DIAGNOSTIC_SETTINGS ]]; then
        for setting in $DIAGNOSTIC_SETTINGS; do
            print_status "Deleting diagnostic setting: $setting"
            az monitor diagnostic-settings delete \
                --resource "$resource" \
                --name "$setting" \
                --output none || true
        done
    fi
done

# Step 4: Delete metric alerts
print_status "Deleting metric alerts..."
METRIC_ALERTS=$(az monitor metrics alert list \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query '[].name' \
    --output tsv)

if [[ -n $METRIC_ALERTS ]]; then
    for alert in $METRIC_ALERTS; do
        print_status "Deleting metric alert: $alert"
        az monitor metrics alert delete \
            --name "$alert" \
            --resource-group "$RESOURCE_GROUP_NAME" \
            --output none || true
    done
fi

# Step 5: Delete action groups
print_status "Deleting action groups..."
ACTION_GROUPS=$(az monitor action-group list \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query '[].name' \
    --output tsv)

if [[ -n $ACTION_GROUPS ]]; then
    for group in $ACTION_GROUPS; do
        print_status "Deleting action group: $group"
        az monitor action-group delete \
            --name "$group" \
            --resource-group "$RESOURCE_GROUP_NAME" \
            --output none || true
    done
fi

# Step 6: Clear storage account contents (optional, for faster deletion)
print_status "Clearing storage account contents..."
STORAGE_ACCOUNTS=$(az storage account list \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --query '[].name' \
    --output tsv)

if [[ -n $STORAGE_ACCOUNTS ]]; then
    for account in $STORAGE_ACCOUNTS; do
        print_status "Clearing storage account: $account"
        
        # Get account key
        ACCOUNT_KEY=$(az storage account keys list \
            --account-name "$account" \
            --resource-group "$RESOURCE_GROUP_NAME" \
            --query '[0].value' \
            --output tsv 2>/dev/null || true)
        
        if [[ -n $ACCOUNT_KEY ]]; then
            # Delete all containers
            CONTAINERS=$(az storage container list \
                --account-name "$account" \
                --account-key "$ACCOUNT_KEY" \
                --query '[].name' \
                --output tsv 2>/dev/null || true)
            
            for container in $CONTAINERS; do
                print_status "Deleting container: $container"
                az storage container delete \
                    --name "$container" \
                    --account-name "$account" \
                    --account-key "$ACCOUNT_KEY" \
                    --output none || true
            done
        fi
    done
fi

# Step 7: Delete the resource group
print_status "Deleting resource group: $RESOURCE_GROUP_NAME"
print_warning "This may take several minutes..."

az group delete \
    --name "$RESOURCE_GROUP_NAME" \
    --yes \
    --no-wait

print_success "Resource group deletion initiated."

# Step 8: Wait for deletion to complete (optional)
read -p "Would you like to wait for the deletion to complete? (y/n): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Waiting for resource group deletion to complete..."
    
    # Wait for resource group to be deleted
    while az group show --name "$RESOURCE_GROUP_NAME" &> /dev/null; do
        print_status "Deletion in progress..."
        sleep 30
    done
    
    print_success "Resource group '$RESOURCE_GROUP_NAME' has been completely deleted."
else
    print_status "Deletion initiated in background. You can check the status in the Azure portal."
fi

# Step 9: Clean up any remaining soft-deleted Key Vaults
if [[ -n $KEY_VAULTS ]]; then
    print_status "Checking for soft-deleted Key Vaults..."
    
    for vault in $KEY_VAULTS; do
        if az keyvault show-deleted --name "$vault" &> /dev/null; then
            print_status "Purging soft-deleted Key Vault: $vault"
            az keyvault purge \
                --name "$vault" \
                --output none || true
        fi
    done
fi

# Step 10: Clean up local configuration files
CONFIG_FILE="fraud-detection-config.env"
if [[ -f $CONFIG_FILE ]]; then
    print_status "Removing local configuration file: $CONFIG_FILE"
    rm -f "$CONFIG_FILE"
fi

# Display cleanup summary
echo ""
echo "============================================================"
echo "           CLEANUP SUMMARY"
echo "============================================================"
echo "Resource Group:           $RESOURCE_GROUP_NAME"
echo "Subscription:             $SUBSCRIPTION_ID"
echo "Status:                   Deletion initiated"
echo "============================================================"
echo ""

print_success "Cleanup completed successfully! 🗑️"
print_status "All resources have been deleted or marked for deletion."
print_status "It may take a few minutes for all resources to be fully removed."

# Final verification
echo ""
read -p "Would you like to verify that all resources have been deleted? (y/n): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP_NAME" &> /dev/null; then
        print_warning "Resource group still exists. Deletion may still be in progress."
        
        # Show remaining resources
        REMAINING_RESOURCES=$(az resource list \
            --resource-group "$RESOURCE_GROUP_NAME" \
            --query '[].name' \
            --output tsv 2>/dev/null || true)
        
        if [[ -n $REMAINING_RESOURCES ]]; then
            print_status "Remaining resources:"
            for resource in $REMAINING_RESOURCES; do
                echo "  - $resource"
            done
        fi
    else
        print_success "Resource group has been completely deleted."
    fi
fi

print_status "Cleanup process finished."