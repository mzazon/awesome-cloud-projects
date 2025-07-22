#!/bin/bash
# ==============================================================================
# Azure Bicep Deployment Script for Financial Fraud Detection Solution
# ==============================================================================
# This script deploys the complete fraud detection infrastructure using Bicep
# 
# Prerequisites:
# - Azure CLI installed and authenticated
# - Bicep CLI installed
# - Appropriate Azure subscription permissions
# 
# Usage:
# ./deploy.sh [resource-group-name] [location] [environment]
# 
# Example:
# ./deploy.sh rg-fraud-detection-dev eastus dev
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
LOCATION="${2:-eastus}"
ENVIRONMENT="${3:-dev}"
SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Generate unique suffix for resources
RESOURCE_SUFFIX=$(openssl rand -hex 3)

print_status "Starting deployment of Financial Fraud Detection Solution..."
print_status "Resource Group: $RESOURCE_GROUP_NAME"
print_status "Location: $LOCATION"
print_status "Environment: $ENVIRONMENT"
print_status "Subscription: $SUBSCRIPTION_ID"
print_status "Resource Suffix: $RESOURCE_SUFFIX"

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

# Check if Bicep CLI is installed
if ! command -v bicep &> /dev/null; then
    print_warning "Bicep CLI not found. Installing..."
    az bicep install
fi

# Create resource group if it doesn't exist
print_status "Creating resource group '$RESOURCE_GROUP_NAME' in '$LOCATION'..."
az group create \
    --name "$RESOURCE_GROUP_NAME" \
    --location "$LOCATION" \
    --tags \
        Environment="$ENVIRONMENT" \
        Project="FraudDetection" \
        CostCenter="Security" \
        Owner="ComplianceTeam" \
        CreatedBy="BicepDeployment" \
        CreatedDate="$(date -u +%Y-%m-%d)" \
    --output none

print_success "Resource group created successfully."

# Validate the Bicep template
print_status "Validating Bicep template..."
az deployment group validate \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --template-file main.bicep \
    --parameters parameters.json \
    --parameters \
        location="$LOCATION" \
        environment="$ENVIRONMENT" \
        resourceSuffix="$RESOURCE_SUFFIX" \
    --output none

print_success "Bicep template validation passed."

# Deploy the Bicep template
print_status "Deploying Bicep template..."
DEPLOYMENT_NAME="fraud-detection-deployment-$(date +%Y%m%d%H%M%S)"

az deployment group create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$DEPLOYMENT_NAME" \
    --template-file main.bicep \
    --parameters parameters.json \
    --parameters \
        location="$LOCATION" \
        environment="$ENVIRONMENT" \
        resourceSuffix="$RESOURCE_SUFFIX" \
    --output table

print_success "Deployment completed successfully."

# Get deployment outputs
print_status "Retrieving deployment outputs..."
DEPLOYMENT_OUTPUTS=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name "$DEPLOYMENT_NAME" \
    --query properties.outputs \
    --output json)

# Extract key information
METRICS_ADVISOR_ENDPOINT=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.metricsAdvisorEndpoint.value')
IMMERSIVE_READER_ENDPOINT=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.immersiveReaderEndpoint.value')
LOGIC_APP_TRIGGER_URL=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.logicAppTriggerUrl.value')
STORAGE_ACCOUNT_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.storageAccountName.value')
KEY_VAULT_NAME=$(echo "$DEPLOYMENT_OUTPUTS" | jq -r '.keyVaultName.value')

# Create environment configuration file
CONFIG_FILE="fraud-detection-config.env"
cat > "$CONFIG_FILE" << EOF
# Azure Fraud Detection Solution Configuration
# Generated on: $(date)

# Resource Group
RESOURCE_GROUP_NAME=$RESOURCE_GROUP_NAME
LOCATION=$LOCATION
ENVIRONMENT=$ENVIRONMENT
SUBSCRIPTION_ID=$SUBSCRIPTION_ID

# Azure AI Services
METRICS_ADVISOR_ENDPOINT=$METRICS_ADVISOR_ENDPOINT
IMMERSIVE_READER_ENDPOINT=$IMMERSIVE_READER_ENDPOINT

# Logic App
LOGIC_APP_TRIGGER_URL=$LOGIC_APP_TRIGGER_URL

# Storage
STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME

# Key Vault
KEY_VAULT_NAME=$KEY_VAULT_NAME

# Resource Suffix
RESOURCE_SUFFIX=$RESOURCE_SUFFIX
EOF

print_success "Configuration saved to: $CONFIG_FILE"

# Display deployment summary
echo ""
echo "============================================================"
echo "           DEPLOYMENT SUMMARY"
echo "============================================================"
echo "Resource Group:           $RESOURCE_GROUP_NAME"
echo "Location:                 $LOCATION"
echo "Environment:              $ENVIRONMENT"
echo "Deployment Name:          $DEPLOYMENT_NAME"
echo ""
echo "Azure AI Services:"
echo "  Metrics Advisor:        $METRICS_ADVISOR_ENDPOINT"
echo "  Immersive Reader:       $IMMERSIVE_READER_ENDPOINT"
echo ""
echo "Logic App Trigger URL:    $LOGIC_APP_TRIGGER_URL"
echo "Storage Account:          $STORAGE_ACCOUNT_NAME"
echo "Key Vault:               $KEY_VAULT_NAME"
echo ""
echo "Configuration File:       $CONFIG_FILE"
echo "============================================================"

# Post-deployment instructions
echo ""
print_status "Post-deployment steps:"
echo "1. Configure API connections for Logic App (Office 365, Azure Blob)"
echo "2. Test the fraud detection workflow with sample data"
echo "3. Set up data feeds to Azure AI Metrics Advisor"
echo "4. Configure monitoring alerts and dashboards"
echo "5. Review and customize the Logic App workflow as needed"
echo ""

# Test connectivity to key services
print_status "Testing service connectivity..."

# Test Metrics Advisor
if curl -s -f -I "$METRICS_ADVISOR_ENDPOINT" > /dev/null; then
    print_success "Metrics Advisor endpoint is accessible"
else
    print_warning "Metrics Advisor endpoint test failed - this is expected for new deployments"
fi

# Test Immersive Reader
if curl -s -f -I "$IMMERSIVE_READER_ENDPOINT" > /dev/null; then
    print_success "Immersive Reader endpoint is accessible"
else
    print_warning "Immersive Reader endpoint test failed - this is expected for new deployments"
fi

print_success "Deployment completed successfully! 🎉"
print_status "Next steps: Configure API connections and test the fraud detection workflow."

# Offer to open Azure portal
if command -v open &> /dev/null; then
    read -p "Would you like to open the Azure portal to view the deployed resources? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open "https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP_NAME/overview"
    fi
fi