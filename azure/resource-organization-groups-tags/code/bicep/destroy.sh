#!/bin/bash

# Destroy Resource Organization with Resource Groups and Tags
# This script removes all resources created by the deployment script

set -e

# Check if suffix is provided
if [[ -z "$1" ]]; then
    echo "❌ Usage: $0 <random-suffix>"
    echo "   Example: $0 a1b2c3"
    echo ""
    echo "💡 If you don't know the suffix, you can find resource groups with:"
    echo "   az group list --query \"[?contains(name, 'rg-demo')].name\" --output table"
    exit 1
fi

RANDOM_SUFFIX=$1

# Resource Group Names
DEV_RG="rg-demo-dev-${RANDOM_SUFFIX}"
PROD_RG="rg-demo-prod-${RANDOM_SUFFIX}"
SHARED_RG="rg-demo-shared-${RANDOM_SUFFIX}"

echo "🗑️  Starting Resource Cleanup"
echo "   Suffix: ${RANDOM_SUFFIX}"
echo "   Resource Groups to delete:"
echo "   - ${DEV_RG}"
echo "   - ${PROD_RG}"
echo "   - ${SHARED_RG}"
echo ""

# Function to check if resource group exists
resource_group_exists() {
    local rg_name=$1
    az group exists --name "${rg_name}" 2>/dev/null
}

# Function to delete resource group
delete_resource_group() {
    local rg_name=$1
    
    if [[ "$(resource_group_exists "${rg_name}")" == "true" ]]; then
        echo "🗑️  Deleting resource group: ${rg_name}"
        
        # List resources that will be deleted
        echo "   Resources to be deleted:"
        az resource list \
            --resource-group "${rg_name}" \
            --query "[].{Name:name, Type:type}" \
            --output table 2>/dev/null || echo "   No resources found"
        
        # Confirm deletion
        read -p "   ⚠️  Delete ${rg_name} and all its resources? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            az group delete \
                --name "${rg_name}" \
                --yes \
                --no-wait
            echo "   ✅ Deletion initiated for: ${rg_name}"
        else
            echo "   ⏭️  Skipped deletion of: ${rg_name}"
        fi
    else
        echo "   ℹ️  Resource group not found: ${rg_name}"
    fi
    echo ""
}

# Check prerequisites
echo "🔍 Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    echo "❌ Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

echo "✅ Prerequisites check completed"
echo ""

# Confirm overall deletion
echo "⚠️  WARNING: This will permanently delete all resources in the following resource groups:"
echo "   - ${DEV_RG}"
echo "   - ${PROD_RG}"
echo "   - ${SHARED_RG}"
echo ""
read -p "🤔 Are you sure you want to continue? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cleanup cancelled"
    exit 0
fi

echo "🗑️  Starting cleanup process..."
echo ""

# Delete resource groups (in reverse order of dependency)
delete_resource_group "${SHARED_RG}"
delete_resource_group "${PROD_RG}"
delete_resource_group "${DEV_RG}"

echo "⏳ Waiting for deletions to complete..."
echo "   Note: Resource group deletion runs asynchronously"
echo ""

# Function to check deletion status
check_deletion_status() {
    local rg_name=$1
    local status="Deleting"
    local attempts=0
    local max_attempts=30
    
    while [[ "$(resource_group_exists "${rg_name}")" == "true" ]] && [[ $attempts -lt $max_attempts ]]; do
        echo "   ⏳ ${rg_name}: Still deleting... (attempt $((attempts + 1))/${max_attempts})"
        sleep 10
        ((attempts++))
    done
    
    if [[ "$(resource_group_exists "${rg_name}")" == "false" ]]; then
        echo "   ✅ ${rg_name}: Deleted successfully"
        return 0
    else
        echo "   ⚠️  ${rg_name}: Deletion still in progress (timeout reached)"
        return 1
    fi
}

# Monitor deletion progress (optional)
read -p "🔍 Monitor deletion progress? This may take several minutes (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🔍 Monitoring deletion progress..."
    echo ""
    
    check_deletion_status "${DEV_RG}"
    check_deletion_status "${PROD_RG}"
    check_deletion_status "${SHARED_RG}"
    
    echo ""
    echo "✅ Monitoring completed"
else
    echo "ℹ️  Skipping deletion monitoring"
    echo ""
    echo "📋 To check deletion status manually:"
    echo "   az group list --query \"[?contains(name, '${RANDOM_SUFFIX}')].{Name:name, ProvisioningState:properties.provisioningState}\" --output table"
fi

echo ""
echo "🎉 Cleanup Summary:"
echo "   🗑️  Resource group deletions initiated: 3"
echo "   ⏳ Deletions are running asynchronously"
echo "   🔍 Monitor progress in Azure Portal or with Azure CLI"
echo ""
echo "📊 Verify cleanup completion:"
echo "   az group list --query \"[?contains(name, '${RANDOM_SUFFIX}')].name\" --output table"
echo ""
echo "✅ Cleanup script completed!"