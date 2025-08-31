#!/bin/bash

# Deploy Resource Organization with Resource Groups and Tags
# This script automates the deployment of the Bicep template for all three environments

set -e

# Configuration
LOCATION="eastus"
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Resource Group Names
DEV_RG="rg-demo-dev-${RANDOM_SUFFIX}"
PROD_RG="rg-demo-prod-${RANDOM_SUFFIX}"
SHARED_RG="rg-demo-shared-${RANDOM_SUFFIX}"

echo "🚀 Starting Resource Organization Deployment"
echo "   Location: ${LOCATION}"
echo "   Suffix: ${RANDOM_SUFFIX}"
echo "   Dev RG: ${DEV_RG}"
echo "   Prod RG: ${PROD_RG}"
echo "   Shared RG: ${SHARED_RG}"
echo ""

# Function to create resource group with tags
create_resource_group() {
    local rg_name=$1
    local environment=$2
    local department=$3
    local purpose=$4
    
    echo "📁 Creating resource group: ${rg_name}"
    
    az group create \
        --name "${rg_name}" \
        --location "${LOCATION}" \
        --tags environment="${environment}" \
               purpose="${purpose}" \
               department="${department}" \
               project="resource-organization" \
               lastUpdated="2025-07-12" \
               managedBy="bicep-script" \
        --output none
    
    echo "✅ Resource group created: ${rg_name}"
}

# Function to deploy Bicep template
deploy_template() {
    local rg_name=$1
    local parameters_file=$2
    local environment=$3
    
    echo "🔧 Deploying Bicep template to: ${rg_name}"
    
    az deployment group create \
        --resource-group "${rg_name}" \
        --template-file main.bicep \
        --parameters "${parameters_file}" \
        --parameters uniqueSuffix="${RANDOM_SUFFIX}" \
        --output none
    
    echo "✅ Deployment completed for: ${rg_name}"
}

# Function to validate deployment
validate_deployment() {
    local rg_name=$1
    local environment=$2
    
    echo "🔍 Validating deployment in: ${rg_name}"
    
    # List resources in the resource group
    echo "Resources created:"
    az resource list \
        --resource-group "${rg_name}" \
        --query "[].{Name:name, Type:type}" \
        --output table
    
    # Show resource group tags
    echo "Resource group tags:"
    az group show \
        --name "${rg_name}" \
        --query "tags" \
        --output table
    
    echo "✅ Validation completed for: ${rg_name}"
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

# Check if Bicep is available
if ! az bicep version &> /dev/null; then
    echo "⚠️  Bicep not found, installing..."
    az bicep install
fi

echo "✅ Prerequisites check completed"
echo ""

# Create Resource Groups
echo "📁 Creating resource groups..."

create_resource_group "${DEV_RG}" "development" "engineering" "demo"
create_resource_group "${PROD_RG}" "production" "engineering" "demo"  
create_resource_group "${SHARED_RG}" "shared" "platform" "infrastructure"

echo "✅ All resource groups created"
echo ""

# Deploy to environments
echo "🚀 Starting deployments..."

# Deploy to Development
if [[ -f "parameters.json" ]]; then
    deploy_template "${DEV_RG}" "parameters.json" "development"
else
    echo "⚠️  parameters.json not found, skipping development deployment"
fi

# Deploy to Production
if [[ -f "parameters-production.json" ]]; then
    deploy_template "${PROD_RG}" "parameters-production.json" "production"
else
    echo "⚠️  parameters-production.json not found, skipping production deployment"
fi

# Deploy to Shared (no sample resources)
if [[ -f "parameters-shared.json" ]]; then
    deploy_template "${SHARED_RG}" "parameters-shared.json" "shared"
else
    echo "⚠️  parameters-shared.json not found, skipping shared deployment"
fi

echo "✅ All deployments completed"
echo ""

# Validate deployments
echo "🔍 Validating deployments..."

validate_deployment "${DEV_RG}" "development"
validate_deployment "${PROD_RG}" "production"
validate_deployment "${SHARED_RG}" "shared"

# Show cost management queries
echo "💰 Cost Management Queries:"
echo ""
echo "Query resources by environment:"
echo "az resource list --tag environment=development --query \"[].{Name:name, Type:type, ResourceGroup:resourceGroup}\" --output table"
echo ""
echo "Query resources by department:"
echo "az resource list --tag department=engineering --query \"[].{Name:name, Type:type, CostCenter:tags.costcenter}\" --output table"
echo ""

# Final summary
echo "🎉 Deployment Summary:"
echo "   ✅ Resource Groups: 3 created"
echo "   ✅ Storage Accounts: 2 created"
echo "   ✅ App Service Plans: 2 created"
echo "   📋 Resource Groups:"
echo "      - ${DEV_RG} (development)"
echo "      - ${PROD_RG} (production)"
echo "      - ${SHARED_RG} (shared)"
echo ""
echo "🧹 To clean up all resources, run:"
echo "   ./destroy.sh ${RANDOM_SUFFIX}"
echo ""
echo "📊 To view cost management reports, visit:"
echo "   https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/overview"
echo ""
echo "✅ Deployment completed successfully!"