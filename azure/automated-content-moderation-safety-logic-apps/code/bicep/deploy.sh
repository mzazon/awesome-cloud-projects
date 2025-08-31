#!/bin/bash

# Azure Bicep Deployment Script for Automated Content Moderation
# This script deploys the content moderation solution using Azure Bicep templates

set -e  # Exit on error

# Default values
RESOURCE_GROUP=""
LOCATION="eastus"
ENVIRONMENT="demo"
TEMPLATE_FILE="main.bicep"
PARAMETERS_FILE=""
SUBSCRIPTION_ID=""
VALIDATE_ONLY=false
VERBOSE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[DEPLOY]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 -g <resource-group> [OPTIONS]

This script deploys the Automated Content Moderation solution using Azure Bicep.

Required Parameters:
  -g, --resource-group    Name of the Azure resource group

Optional Parameters:
  -l, --location         Azure region (default: eastus)
  -e, --environment      Environment name (default: demo)
  -p, --parameters       Parameters file (auto-selected based on environment if not specified)
  -s, --subscription     Azure subscription ID (uses default if not specified)
  -v, --validate         Validate template only, don't deploy
  --verbose              Enable verbose output
  -h, --help             Show this help message

Environment-specific parameters files:
  - parameters.json      (default/demo)
  - parameters.dev.json  (development with free tier)
  - parameters.prod.json (production with premium features)

Examples:
  # Deploy to demo environment
  $0 -g rg-content-moderation-demo

  # Deploy to development environment
  $0 -g rg-content-moderation-dev -e dev

  # Deploy to production environment
  $0 -g rg-content-moderation-prod -e prod -l westus2

  # Validate template only
  $0 -g rg-content-moderation-test -v

  # Deploy with custom parameters file
  $0 -g rg-content-moderation-custom -p my-parameters.json

EOF
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
        -p|--parameters)
            PARAMETERS_FILE="$2"
            shift 2
            ;;
        -s|--subscription)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -v|--validate)
            VALIDATE_ONLY=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$RESOURCE_GROUP" ]]; then
    print_error "Resource group name is required"
    show_usage
    exit 1
fi

# Auto-select parameters file based on environment if not specified
if [[ -z "$PARAMETERS_FILE" ]]; then
    case $ENVIRONMENT in
        dev)
            PARAMETERS_FILE="parameters.dev.json"
            ;;
        prod|production)
            PARAMETERS_FILE="parameters.prod.json"
            ;;
        *)
            PARAMETERS_FILE="parameters.json"
            ;;
    esac
fi

# Verify files exist
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    print_error "Template file not found: $TEMPLATE_FILE"
    exit 1
fi

if [[ ! -f "$PARAMETERS_FILE" ]]; then
    print_error "Parameters file not found: $PARAMETERS_FILE"
    exit 1
fi

# Print deployment information
print_header "Azure Content Moderation Solution Deployment"
echo "======================================================"
print_status "Resource Group: $RESOURCE_GROUP"
print_status "Location: $LOCATION"
print_status "Environment: $ENVIRONMENT"
print_status "Template: $TEMPLATE_FILE"
print_status "Parameters: $PARAMETERS_FILE"
if [[ "$VALIDATE_ONLY" == true ]]; then
    print_warning "Validation mode enabled - no resources will be deployed"
fi
echo "======================================================"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first:"
    print_error "https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in to Azure
print_status "Checking Azure CLI authentication..."
if ! az account show &> /dev/null; then
    print_error "You are not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Set subscription if provided
if [[ -n "$SUBSCRIPTION_ID" ]]; then
    print_status "Setting subscription to: $SUBSCRIPTION_ID"
    az account set --subscription "$SUBSCRIPTION_ID"
fi

# Display current subscription
CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv)
print_status "Using subscription: $CURRENT_SUBSCRIPTION"

# Check if resource group exists, create if it doesn't
print_status "Checking if resource group exists..."
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    print_warning "Resource group '$RESOURCE_GROUP' does not exist"
    read -p "Do you want to create it in '$LOCATION'? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
        if [[ $? -eq 0 ]]; then
            print_status "Resource group created successfully"
        else
            print_error "Failed to create resource group"
            exit 1
        fi
    else
        print_error "Cannot proceed without resource group"
        exit 1
    fi
else
    print_status "Resource group '$RESOURCE_GROUP' exists"
fi

# Validate template
print_status "Validating Bicep template..."
VALIDATION_RESULT=$(az deployment group validate \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "@$PARAMETERS_FILE" \
    --query "error" -o tsv 2>&1)

if [[ "$VALIDATION_RESULT" != "None" && -n "$VALIDATION_RESULT" ]]; then
    print_error "Template validation failed:"
    echo "$VALIDATION_RESULT"
    exit 1
else
    print_status "Template validation successful"
fi

# If validate-only mode, exit here
if [[ "$VALIDATE_ONLY" == true ]]; then
    print_status "Validation complete. Exiting without deployment."
    exit 0
fi

# Confirm deployment
echo
print_warning "This will deploy Azure resources that may incur costs."
read -p "Do you want to continue with the deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Deployment cancelled by user"
    exit 0
fi

# Deploy template
print_status "Starting deployment..."
DEPLOYMENT_NAME="content-moderation-$(date +%Y%m%d-%H%M%S)"

# Build deployment command
DEPLOY_CMD="az deployment group create \
    --resource-group '$RESOURCE_GROUP' \
    --name '$DEPLOYMENT_NAME' \
    --template-file '$TEMPLATE_FILE' \
    --parameters '@$PARAMETERS_FILE'"

if [[ "$VERBOSE" == true ]]; then
    DEPLOY_CMD="$DEPLOY_CMD --verbose"
fi

# Execute deployment
print_status "Executing deployment command..."
eval $DEPLOY_CMD

# Check deployment result
if [[ $? -eq 0 ]]; then
    print_status "Deployment completed successfully!"
    
    # Get deployment outputs
    print_status "Retrieving deployment outputs..."
    OUTPUTS=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query properties.outputs)
    
    if [[ -n "$OUTPUTS" && "$OUTPUTS" != "null" ]]; then
        echo
        print_header "Deployment Outputs:"
        echo "$OUTPUTS" | jq .
    fi
    
    # Display next steps
    echo
    print_header "Next Steps:"
    echo "1. Test content upload to verify the workflow"
    echo "2. Monitor Logic App runs in the Azure portal"
    echo "3. Adjust content safety thresholds as needed"
    echo "4. Configure additional notifications or actions"
    echo
    print_status "Resource group: $RESOURCE_GROUP"
    print_status "View resources: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/overview"
    
else
    print_error "Deployment failed!"
    exit 1
fi

# Cleanup function
cleanup() {
    if [[ -f "deployment.log" ]]; then
        print_status "Deployment log available: deployment.log"
    fi
}

trap cleanup EXIT

print_status "Deployment script completed!"