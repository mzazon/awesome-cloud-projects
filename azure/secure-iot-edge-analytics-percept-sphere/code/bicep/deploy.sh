#!/bin/bash

# ==============================================================================
# Azure IoT Edge Analytics Deployment Script
# ==============================================================================
# This script deploys the Secure IoT Edge Analytics solution using Azure Bicep
# Supports development, test, and production environments
# ==============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="dev"
LOCATION="eastus"
RESOURCE_GROUP=""
UNIQUE_SUFFIX=""
ADMIN_EMAIL=""
DEPLOY_CONFIRM=false
VERBOSE=false

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
    echo -e "${BLUE}[HEADER]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure IoT Edge Analytics solution using Bicep templates.

OPTIONS:
    -e, --environment ENV      Environment (dev, test, prod) [default: dev]
    -l, --location LOCATION    Azure region [default: eastus]
    -g, --resource-group RG    Resource group name [required]
    -s, --suffix SUFFIX        Unique suffix for resources [required]
    -m, --email EMAIL          Admin email for alerts [required]
    -y, --yes                  Skip confirmation prompts
    -v, --verbose              Enable verbose output
    -h, --help                 Show this help message

EXAMPLES:
    # Deploy to development environment
    $0 -e dev -g rg-iot-analytics-dev -s abc123 -m admin@company.com

    # Deploy to production with confirmation
    $0 -e prod -g rg-iot-analytics-prod -s xyz789 -m admin@company.com -y

    # Deploy to specific region
    $0 -e test -l westus2 -g rg-iot-analytics-test -s tst456 -m test@company.com

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--suffix)
            UNIQUE_SUFFIX="$2"
            shift 2
            ;;
        -m|--email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        -y|--yes)
            DEPLOY_CONFIRM=true
            shift
            ;;
        -v|--verbose)
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
    print_error "Resource group is required. Use -g or --resource-group"
    exit 1
fi

if [[ -z "$UNIQUE_SUFFIX" ]]; then
    print_error "Unique suffix is required. Use -s or --suffix"
    exit 1
fi

if [[ -z "$ADMIN_EMAIL" ]]; then
    print_error "Admin email is required. Use -m or --email"
    exit 1
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|test|prod)$ ]]; then
    print_error "Environment must be 'dev', 'test', or 'prod'"
    exit 1
fi

# Validate unique suffix
if [[ ! "$UNIQUE_SUFFIX" =~ ^[a-z0-9]{3,8}$ ]]; then
    print_error "Unique suffix must be 3-8 characters (lowercase letters and numbers only)"
    exit 1
fi

# Validate email format
if [[ ! "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    print_error "Invalid email format"
    exit 1
fi

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it from https://aka.ms/azure-cli"
    exit 1
fi

# Check if Bicep is installed
if ! az bicep version &> /dev/null; then
    print_warning "Bicep CLI is not installed. Installing..."
    az bicep install
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first"
    exit 1
fi

# Get current subscription
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

# Determine parameter file
PARAM_FILE="parameters.json"
if [[ "$ENVIRONMENT" == "prod" ]]; then
    PARAM_FILE="parameters.prod.json"
elif [[ "$ENVIRONMENT" == "test" ]]; then
    PARAM_FILE="parameters.test.json"
fi

# Check if parameter file exists
if [[ ! -f "$PARAM_FILE" ]]; then
    print_error "Parameter file '$PARAM_FILE' not found"
    exit 1
fi

# Display deployment information
print_header "Azure IoT Edge Analytics Deployment"
echo "Environment:     $ENVIRONMENT"
echo "Location:        $LOCATION"
echo "Resource Group:  $RESOURCE_GROUP"
echo "Unique Suffix:   $UNIQUE_SUFFIX"
echo "Admin Email:     $ADMIN_EMAIL"
echo "Parameter File:  $PARAM_FILE"
echo "Subscription:    $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
echo

# Confirm deployment
if [[ "$DEPLOY_CONFIRM" == false ]]; then
    read -p "Do you want to continue with this deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deployment cancelled"
        exit 0
    fi
fi

# Create resource group if it doesn't exist
print_status "Checking resource group..."
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    print_status "Creating resource group '$RESOURCE_GROUP' in '$LOCATION'..."
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
    print_status "Resource group created successfully"
else
    print_status "Resource group '$RESOURCE_GROUP' already exists"
fi

# Start deployment
print_status "Starting Bicep deployment..."
START_TIME=$(date +%s)

# Set deployment parameters
DEPLOYMENT_NAME="iot-edge-analytics-$(date +%Y%m%d-%H%M%S)"

# Build deployment command
DEPLOY_CMD="az deployment group create \
    --resource-group \"$RESOURCE_GROUP\" \
    --name \"$DEPLOYMENT_NAME\" \
    --template-file main.bicep \
    --parameters @$PARAM_FILE \
    --parameters uniqueSuffix=\"$UNIQUE_SUFFIX\" \
    --parameters adminEmail=\"$ADMIN_EMAIL\" \
    --parameters location=\"$LOCATION\" \
    --parameters environment=\"$ENVIRONMENT\""

if [[ "$VERBOSE" == true ]]; then
    DEPLOY_CMD="$DEPLOY_CMD --verbose"
fi

# Execute deployment
print_status "Executing deployment command..."
if [[ "$VERBOSE" == true ]]; then
    echo "Command: $DEPLOY_CMD"
fi

eval $DEPLOY_CMD

# Check deployment status
if [[ $? -eq 0 ]]; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    print_status "Deployment completed successfully in ${DURATION}s"
    
    # Display deployment outputs
    print_header "Deployment Outputs"
    az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query "properties.outputs" \
        --output table
    
    print_status "Getting connection information..."
    
    # Get IoT Hub connection string
    IOT_HUB_NAME="iot-edge-${ENVIRONMENT}-${UNIQUE_SUFFIX}-hub"
    IOT_CONNECTION_STRING=$(az iot hub connection-string show \
        --hub-name "$IOT_HUB_NAME" \
        --query "connectionString" \
        --output tsv 2>/dev/null || echo "Not available")
    
    # Get Storage Account connection string
    STORAGE_ACCOUNT_NAME="iotedge${ENVIRONMENT}${UNIQUE_SUFFIX}storage"
    STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "connectionString" \
        --output tsv 2>/dev/null || echo "Not available")
    
    print_header "Connection Information"
    echo "IoT Hub Connection String:"
    echo "$IOT_CONNECTION_STRING"
    echo
    echo "Storage Account Connection String:"
    echo "$STORAGE_CONNECTION_STRING"
    echo
    
    print_header "Next Steps"
    echo "1. Configure your Azure Percept device with the IoT Hub connection string"
    echo "2. Set up your Azure Sphere device with X.509 certificates"
    echo "3. Start the Stream Analytics job to begin processing telemetry data"
    echo "4. Monitor alerts and adjust thresholds as needed"
    echo
    echo "For detailed configuration instructions, see the README.md file"
    
else
    print_error "Deployment failed"
    exit 1
fi

print_status "Deployment script completed"