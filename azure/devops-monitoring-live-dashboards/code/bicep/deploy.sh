#!/bin/bash

# Azure DevOps Monitoring Live Dashboards - Bicep Deployment Script
# This script deploys the infrastructure for real-time monitoring dashboards

set -e

# Default values
RESOURCE_GROUP=""
LOCATION="eastus"
ENVIRONMENT="demo"
PARAMETERS_FILE="parameters.json"
VALIDATE_ONLY=false
SUBSCRIPTION_ID=""

# Function to display usage
usage() {
    echo "Usage: $0 -g <resource-group> [-l <location>] [-e <environment>] [-p <parameters-file>] [-s <subscription-id>] [-v]"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group    Resource group name (required)"
    echo "  -l, --location          Azure region (default: eastus)"
    echo "  -e, --environment       Environment (dev, test, prod, demo) (default: demo)"
    echo "  -p, --parameters-file   Parameters file name (default: parameters.json)"
    echo "  -s, --subscription-id   Azure subscription ID (optional)"
    echo "  -v, --validate-only     Only validate the template without deployment"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -g rg-monitoring-demo"
    echo "  $0 -g rg-monitoring-prod -e prod -p parameters.prod.json"
    echo "  $0 -g rg-monitoring-test -e test -p parameters.test.json -v"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -p|--parameters-file)
            PARAMETERS_FILE="$2"
            shift 2
            ;;
        -s|--subscription-id)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -v|--validate-only)
            VALIDATE_ONLY=true
            shift
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

# Check if parameters file exists
if [[ ! -f "$PARAMETERS_FILE" ]]; then
    echo "Error: Parameters file '$PARAMETERS_FILE' not found"
    echo "Available parameter files:"
    ls -la parameters*.json 2>/dev/null || echo "No parameter files found"
    exit 1
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
echo "========================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "Environment: $ENVIRONMENT"
echo "Parameters File: $PARAMETERS_FILE"
echo "Subscription: $CURRENT_SUBSCRIPTION ($CURRENT_SUBSCRIPTION_ID)"
echo "Validate Only: $VALIDATE_ONLY"
echo "========================================="

# Check if resource group exists
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    echo "Resource group '$RESOURCE_GROUP' does not exist. Creating..."
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --tags \
        environment="$ENVIRONMENT" \
        purpose="monitoring" \
        deployment="bicep" \
        created-by="deploy-script"
    echo "✅ Resource group created successfully"
else
    echo "✅ Resource group '$RESOURCE_GROUP' already exists"
fi

# Validate Bicep template
echo "Validating Bicep template..."
az deployment group validate \
    --resource-group "$RESOURCE_GROUP" \
    --template-file main.bicep \
    --parameters "@$PARAMETERS_FILE" \
    --parameters location="$LOCATION" environment="$ENVIRONMENT"

if [[ $? -eq 0 ]]; then
    echo "✅ Template validation successful"
else
    echo "❌ Template validation failed"
    exit 1
fi

# Exit if validation only
if [[ "$VALIDATE_ONLY" == true ]]; then
    echo "Validation complete. Exiting without deployment."
    exit 0
fi

# Deploy the template
echo "Deploying Bicep template..."
DEPLOYMENT_NAME="monitoring-dashboard-$(date +%Y%m%d-%H%M%S)"

az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file main.bicep \
    --parameters "@$PARAMETERS_FILE" \
    --parameters location="$LOCATION" environment="$ENVIRONMENT" \
    --name "$DEPLOYMENT_NAME" \
    --verbose

if [[ $? -eq 0 ]]; then
    echo "✅ Deployment completed successfully"
    
    # Get deployment outputs
    echo ""
    echo "========================================="
    echo "Deployment Outputs"
    echo "========================================="
    
    OUTPUTS=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query "properties.outputs" \
        --output json)
    
    if [[ -n "$OUTPUTS" && "$OUTPUTS" != "null" ]]; then
        echo "$OUTPUTS" | jq -r '
        if .webhookUrl.value then
            "Webhook URL: " + .webhookUrl.value
        else empty end,
        if .dashboardUrl.value then
            "Dashboard URL: " + .dashboardUrl.value
        else empty end,
        if .functionAppUrl.value then
            "Function App URL: " + .functionAppUrl.value
        else empty end,
        if .signalrServiceName.value then
            "SignalR Service: " + .signalrServiceName.value
        else empty end'
    fi
    
    echo ""
    echo "========================================="
    echo "Next Steps"
    echo "========================================="
    echo "1. Deploy function code to the Azure Function App"
    echo "2. Deploy dashboard application to the Web App"
    echo "3. Configure Azure DevOps Service Hooks with the webhook URL"
    echo "4. Test the end-to-end monitoring flow"
    echo "5. Access the dashboard at the provided URL"
    echo ""
    echo "For detailed configuration instructions, check the deployment outputs above."
    
else
    echo "❌ Deployment failed"
    exit 1
fi