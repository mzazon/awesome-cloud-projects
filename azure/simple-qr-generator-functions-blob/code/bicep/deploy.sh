#!/bin/bash

# Azure Bicep Deployment Script for QR Code Generator
# This script deploys the complete QR Code Generator infrastructure using Azure Bicep

set -e  # Exit on any error

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

# Default values
RESOURCE_GROUP=""
LOCATION="eastus"
ENVIRONMENT="dev"
PROJECT_NAME="qr-generator"
TEMPLATE_FILE="main.bicep"
PARAMETERS_FILE="parameters.json"
DEPLOYMENT_NAME="qr-generator-deployment-$(date +%Y%m%d-%H%M%S)"
SKIP_VALIDATION=false
DRY_RUN=false

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure QR Code Generator infrastructure using Bicep

OPTIONS:
    -g, --resource-group     Resource group name (required)
    -l, --location          Azure region (default: eastus)
    -e, --environment       Environment name (default: dev)
    -p, --project-name      Project name (default: qr-generator)
    -t, --template          Bicep template file (default: main.bicep)
    -f, --parameters        Parameters file (default: parameters.json)
    -n, --deployment-name   Deployment name (default: auto-generated)
    -s, --skip-validation   Skip template validation
    -d, --dry-run          Validate only, don't deploy
    -h, --help             Show this help message

EXAMPLES:
    # Basic deployment
    $0 -g rg-qr-generator-dev

    # Production deployment
    $0 -g rg-qr-generator-prod -e prod -l westus2

    # Custom project name
    $0 -g rg-company-qr -p company-qr -e prod

    # Dry run to validate template
    $0 -g rg-qr-generator-dev --dry-run

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
        -p|--project-name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -t|--template)
            TEMPLATE_FILE="$2"
            shift 2
            ;;
        -f|--parameters)
            PARAMETERS_FILE="$2"
            shift 2
            ;;
        -n|--deployment-name)
            DEPLOYMENT_NAME="$2"
            shift 2
            ;;
        -s|--skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
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
    print_error "Resource group name is required. Use -g or --resource-group option."
    show_usage
    exit 1
fi

# Check if Azure CLI is installed and logged in
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check Azure CLI login status
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Check if template file exists
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    print_error "Template file '$TEMPLATE_FILE' not found."
    exit 1
fi

# Check if parameters file exists
if [[ ! -f "$PARAMETERS_FILE" ]]; then
    print_error "Parameters file '$PARAMETERS_FILE' not found."
    exit 1
fi

# Display deployment information
print_header "QR Code Generator Infrastructure Deployment"
echo "=========================================="
echo "Resource Group:    $RESOURCE_GROUP"
echo "Location:          $LOCATION"
echo "Environment:       $ENVIRONMENT"
echo "Project Name:      $PROJECT_NAME"
echo "Template File:     $TEMPLATE_FILE"
echo "Parameters File:   $PARAMETERS_FILE"
echo "Deployment Name:   $DEPLOYMENT_NAME"
echo "Dry Run:           $DRY_RUN"
echo "Skip Validation:   $SKIP_VALIDATION"
echo "=========================================="

# Get current subscription
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
print_status "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# Check if resource group exists, create if it doesn't
print_status "Checking resource group: $RESOURCE_GROUP"
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    print_warning "Resource group '$RESOURCE_GROUP' does not exist. Creating it..."
    if [[ "$DRY_RUN" == "false" ]]; then
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags Environment="$ENVIRONMENT" Project="$PROJECT_NAME" ManagedBy="Bicep"
        print_status "Resource group '$RESOURCE_GROUP' created successfully."
    else
        print_status "Would create resource group '$RESOURCE_GROUP' in location '$LOCATION'"
    fi
else
    print_status "Resource group '$RESOURCE_GROUP' already exists."
fi

# Validate Bicep template
if [[ "$SKIP_VALIDATION" == "false" ]]; then
    print_status "Validating Bicep template..."
    if az deployment group validate \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "$PARAMETERS_FILE" \
        --parameters environment="$ENVIRONMENT" projectName="$PROJECT_NAME" location="$LOCATION" \
        --output none; then
        print_status "Template validation successful."
    else
        print_error "Template validation failed. Please check your Bicep template and parameters."
        exit 1
    fi
else
    print_warning "Skipping template validation."
fi

# Perform dry run if requested
if [[ "$DRY_RUN" == "true" ]]; then
    print_status "Performing dry run deployment..."
    az deployment group what-if \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "$PARAMETERS_FILE" \
        --parameters environment="$ENVIRONMENT" projectName="$PROJECT_NAME" location="$LOCATION" \
        --name "$DEPLOYMENT_NAME"
    
    print_status "Dry run completed. No resources were created."
    exit 0
fi

# Deploy the template
print_status "Starting deployment..."
DEPLOYMENT_START_TIME=$(date)

if az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters "$PARAMETERS_FILE" \
    --parameters environment="$ENVIRONMENT" projectName="$PROJECT_NAME" location="$LOCATION" \
    --name "$DEPLOYMENT_NAME" \
    --verbose; then
    
    DEPLOYMENT_END_TIME=$(date)
    print_status "Deployment completed successfully!"
    
    # Get deployment outputs
    print_status "Retrieving deployment outputs..."
    
    FUNCTION_APP_NAME=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query properties.outputs.functionAppName.value \
        --output tsv)
    
    QR_ENDPOINT=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query properties.outputs.qrGenerationEndpoint.value \
        --output tsv)
    
    STORAGE_ACCOUNT=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query properties.outputs.storageAccountName.value \
        --output tsv)
    
    # Display deployment summary
    echo ""
    print_header "Deployment Summary"
    echo "=================="
    echo "Deployment Name:       $DEPLOYMENT_NAME"
    echo "Start Time:           $DEPLOYMENT_START_TIME"
    echo "End Time:             $DEPLOYMENT_END_TIME"
    echo "Function App:         $FUNCTION_APP_NAME"
    echo "QR Generation URL:    $QR_ENDPOINT"
    echo "Storage Account:      $STORAGE_ACCOUNT"
    echo ""
    
    # Next steps
    print_header "Next Steps"
    echo "=========="
    echo "1. Deploy your Function App code:"
    echo "   az functionapp deployment source config-zip \\"
    echo "     --resource-group $RESOURCE_GROUP \\"
    echo "     --name $FUNCTION_APP_NAME \\"
    echo "     --src function-code.zip"
    echo ""
    echo "2. Test the QR generation endpoint:"
    echo "   curl -X POST \"$QR_ENDPOINT\" \\"
    echo "     -H \"Content-Type: application/json\" \\"
    echo "     -d '{\"text\": \"Hello World!\"}'"
    echo ""
    echo "3. Monitor your application:"
    echo "   az monitor app-insights component show \\"
    echo "     --app $FUNCTION_APP_NAME \\"
    echo "     --resource-group $RESOURCE_GROUP"
    
else
    print_error "Deployment failed. Please check the error messages above."
    exit 1
fi

print_status "Deployment script completed successfully!"