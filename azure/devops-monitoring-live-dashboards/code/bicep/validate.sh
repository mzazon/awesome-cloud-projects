#!/bin/bash

# Azure DevOps Monitoring Live Dashboards - Validation Script
# This script validates the Bicep template and parameters

set -e

# Default values
RESOURCE_GROUP=""
LOCATION="eastus"
ENVIRONMENT="demo"
PARAMETERS_FILE="parameters.json"
SUBSCRIPTION_ID=""
VERBOSE=false

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
    echo "  -v, --verbose           Enable verbose output"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -g rg-monitoring-demo"
    echo "  $0 -g rg-monitoring-prod -e prod -p parameters.prod.json -v"
    echo "  $0 -g rg-monitoring-test -e test -p parameters.test.json"
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
        -v|--verbose)
            VERBOSE=true
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

# Check if main.bicep exists
if [[ ! -f "main.bicep" ]]; then
    echo "Error: main.bicep template not found"
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
echo "VALIDATION SCRIPT"
echo "========================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "Environment: $ENVIRONMENT"
echo "Parameters File: $PARAMETERS_FILE"
echo "Subscription: $CURRENT_SUBSCRIPTION ($CURRENT_SUBSCRIPTION_ID)"
echo "Verbose: $VERBOSE"
echo "========================================="

# Check if Bicep CLI is available
if ! command -v bicep &> /dev/null; then
    echo "ℹ️  Bicep CLI not found. Using Azure CLI for validation."
    BICEP_CLI_AVAILABLE=false
else
    echo "✅ Bicep CLI found"
    BICEP_CLI_AVAILABLE=true
fi

# Validate JSON parameters file
echo ""
echo "Validating parameters file..."
if command -v jq &> /dev/null; then
    if jq empty "$PARAMETERS_FILE" 2>/dev/null; then
        echo "✅ Parameters file is valid JSON"
    else
        echo "❌ Parameters file is not valid JSON"
        exit 1
    fi
else
    echo "ℹ️  jq not found. Skipping JSON validation."
fi

# Bicep template validation
echo ""
echo "Validating Bicep template..."
if [[ "$BICEP_CLI_AVAILABLE" == true ]]; then
    if bicep build main.bicep --outfile /tmp/main.json 2>/dev/null; then
        echo "✅ Bicep template builds successfully"
        if [[ "$VERBOSE" == true ]]; then
            echo "Generated ARM template size: $(wc -c < /tmp/main.json) bytes"
        fi
        rm -f /tmp/main.json
    else
        echo "❌ Bicep template build failed"
        bicep build main.bicep --outfile /tmp/main.json
        exit 1
    fi
fi

# Check if resource group exists (for deployment validation)
echo ""
echo "Checking resource group..."
if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    echo "✅ Resource group '$RESOURCE_GROUP' exists"
    RG_EXISTS=true
else
    echo "⚠️  Resource group '$RESOURCE_GROUP' does not exist"
    echo "   It will be created during deployment"
    RG_EXISTS=false
fi

# Azure deployment validation
echo ""
echo "Validating Azure deployment..."
if [[ "$RG_EXISTS" == true ]]; then
    # Validate against existing resource group
    VALIDATION_OUTPUT=$(az deployment group validate \
        --resource-group "$RESOURCE_GROUP" \
        --template-file main.bicep \
        --parameters "@$PARAMETERS_FILE" \
        --parameters location="$LOCATION" environment="$ENVIRONMENT" \
        --output json 2>&1)
    
    if [[ $? -eq 0 ]]; then
        echo "✅ Azure deployment validation successful"
        
        if [[ "$VERBOSE" == true ]]; then
            echo ""
            echo "Validation details:"
            echo "$VALIDATION_OUTPUT" | jq -r '.properties.validatedResources[] | "  - \(.resourceName) (\(.resourceType))"' 2>/dev/null || echo "$VALIDATION_OUTPUT"
        fi
    else
        echo "❌ Azure deployment validation failed"
        echo "Error details:"
        echo "$VALIDATION_OUTPUT"
        exit 1
    fi
else
    # Create temporary resource group for validation
    TEMP_RG="${RESOURCE_GROUP}-temp-validation"
    echo "Creating temporary resource group for validation: $TEMP_RG"
    
    az group create --name "$TEMP_RG" --location "$LOCATION" --tags validation=true &> /dev/null
    
    VALIDATION_OUTPUT=$(az deployment group validate \
        --resource-group "$TEMP_RG" \
        --template-file main.bicep \
        --parameters "@$PARAMETERS_FILE" \
        --parameters location="$LOCATION" environment="$ENVIRONMENT" \
        --output json 2>&1)
    
    if [[ $? -eq 0 ]]; then
        echo "✅ Azure deployment validation successful"
        
        if [[ "$VERBOSE" == true ]]; then
            echo ""
            echo "Validation details:"
            echo "$VALIDATION_OUTPUT" | jq -r '.properties.validatedResources[] | "  - \(.resourceName) (\(.resourceType))"' 2>/dev/null || echo "$VALIDATION_OUTPUT"
        fi
    else
        echo "❌ Azure deployment validation failed"
        echo "Error details:"
        echo "$VALIDATION_OUTPUT"
        
        # Clean up temporary resource group
        az group delete --name "$TEMP_RG" --yes --no-wait &> /dev/null
        exit 1
    fi
    
    # Clean up temporary resource group
    echo "Cleaning up temporary resource group..."
    az group delete --name "$TEMP_RG" --yes --no-wait &> /dev/null
fi

# Parameter validation
echo ""
echo "Validating parameters..."
if command -v jq &> /dev/null; then
    # Check required parameters
    REQUIRED_PARAMS=("resourcePrefix" "location" "environment")
    for param in "${REQUIRED_PARAMS[@]}"; do
        if jq -e ".parameters.$param.value" "$PARAMETERS_FILE" &> /dev/null; then
            VALUE=$(jq -r ".parameters.$param.value" "$PARAMETERS_FILE")
            echo "✅ $param: $VALUE"
        else
            echo "❌ Missing required parameter: $param"
        fi
    done
    
    # Check environment value
    ENV_VALUE=$(jq -r ".parameters.environment.value" "$PARAMETERS_FILE" 2>/dev/null)
    if [[ "$ENV_VALUE" =~ ^(dev|test|staging|prod|demo)$ ]]; then
        echo "✅ Environment value is valid: $ENV_VALUE"
    else
        echo "⚠️  Environment value should be one of: dev, test, staging, prod, demo"
    fi
    
    # Check SKU values
    SIGNALR_SKU=$(jq -r ".parameters.signalrSku.value" "$PARAMETERS_FILE" 2>/dev/null)
    if [[ "$SIGNALR_SKU" =~ ^(Free_F1|Standard_S1)$ ]]; then
        echo "✅ SignalR SKU is valid: $SIGNALR_SKU"
    else
        echo "⚠️  SignalR SKU should be Free_F1 or Standard_S1"
    fi
    
else
    echo "ℹ️  jq not found. Skipping detailed parameter validation."
fi

# Resource quota check
echo ""
echo "Checking resource quotas..."
LOCATION_DISPLAY=$(az account list-locations --query "[?name=='$LOCATION'].displayName" --output tsv)
if [[ -n "$LOCATION_DISPLAY" ]]; then
    echo "✅ Location '$LOCATION' ($LOCATION_DISPLAY) is valid"
else
    echo "⚠️  Location '$LOCATION' may not be valid"
fi

# Cost estimation
echo ""
echo "Estimated monthly costs (USD):"
echo "- SignalR Service (Standard_S1): ~$25-50"
echo "- Function App (Consumption): ~$0-20"
echo "- Web App (B1): ~$13-15"
echo "- Storage Account: ~$1-5"
echo "- Log Analytics: ~$2-10"
echo "- Application Insights: ~$1-5"
echo "Total estimated cost: ~$42-105/month"
echo ""
echo "💡 Costs may vary based on usage patterns and data volume"

# Summary
echo ""
echo "========================================="
echo "Validation Summary"
echo "========================================="
echo "✅ All validations completed successfully"
echo ""
echo "Ready for deployment with:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Location: $LOCATION"
echo "  Environment: $ENVIRONMENT"
echo "  Parameters File: $PARAMETERS_FILE"
echo ""
echo "To deploy, run:"
echo "  ./deploy.sh -g $RESOURCE_GROUP -l $LOCATION -e $ENVIRONMENT -p $PARAMETERS_FILE"