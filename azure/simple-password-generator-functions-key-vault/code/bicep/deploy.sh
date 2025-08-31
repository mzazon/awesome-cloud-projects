#!/bin/bash

# ============================================================================
# Azure Bicep Deployment Script: Simple Password Generator
# ============================================================================
# This script deploys the password generator infrastructure using Azure Bicep
# with proper error handling, validation, and user-friendly output.

set -e  # Exit on any error

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_RESOURCE_GROUP="rg-password-generator"
DEFAULT_LOCATION="East US"
DEFAULT_ENVIRONMENT="dev"

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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        echo "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        print_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check Bicep version
    if ! az bicep version &> /dev/null; then
        print_warning "Bicep CLI not found. Installing latest version..."
        az bicep install
    fi
    
    print_success "Prerequisites check completed"
}

# Function to get user inputs
get_user_inputs() {
    echo
    print_status "Please provide deployment configuration:"
    
    # Resource Group Name
    read -p "Resource Group Name [$DEFAULT_RESOURCE_GROUP]: " RESOURCE_GROUP
    RESOURCE_GROUP=${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}
    
    # Location
    read -p "Azure Location [$DEFAULT_LOCATION]: " LOCATION
    LOCATION=${LOCATION:-$DEFAULT_LOCATION}
    
    # Environment
    echo "Available environments: dev, test, staging, prod"
    read -p "Environment [$DEFAULT_ENVIRONMENT]: " ENVIRONMENT
    ENVIRONMENT=${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}
    
    # Validate environment
    if [[ ! "$ENVIRONMENT" =~ ^(dev|test|staging|prod)$ ]]; then
        print_error "Invalid environment. Must be one of: dev, test, staging, prod"
        exit 1
    fi
    
    # Generate unique suffix
    UNIQUE_SUFFIX=$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 7)
    
    # Node.js version
    echo "Available Node.js versions: 18, 20"
    read -p "Function App Node.js version [20]: " NODE_VERSION
    NODE_VERSION=${NODE_VERSION:-20}
    
    # Validate Node.js version
    if [[ ! "$NODE_VERSION" =~ ^(18|20)$ ]]; then
        print_error "Invalid Node.js version. Must be 18 or 20"
        exit 1
    fi
    
    # Key Vault settings based on environment
    if [[ "$ENVIRONMENT" == "prod" ]]; then
        ENABLE_PURGE_PROTECTION="true"
        RETENTION_DAYS="90"
    else
        ENABLE_PURGE_PROTECTION="false"
        RETENTION_DAYS="7"
    fi
    
    echo
    print_status "Deployment Configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Environment: $ENVIRONMENT"
    echo "  Unique Suffix: $UNIQUE_SUFFIX"
    echo "  Node.js Version: $NODE_VERSION"
    echo "  Purge Protection: $ENABLE_PURGE_PROTECTION"
    echo "  Retention Days: $RETENTION_DAYS"
    echo
}

# Function to create resource group if it doesn't exist
create_resource_group() {
    print_status "Checking if resource group exists..."
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_status "Creating resource group: $RESOURCE_GROUP"
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags \
                Environment="$ENVIRONMENT" \
                Purpose="password-generator-recipe" \
                CreatedBy="bicep-deploy-script" \
                CreatedDate="$(date -u +%Y-%m-%d)" \
            > /dev/null
        print_success "Resource group created successfully"
    else
        print_success "Resource group already exists"
    fi
}

# Function to deploy Bicep template
deploy_infrastructure() {
    print_status "Starting Bicep deployment..."
    
    # Create deployment name with timestamp
    DEPLOYMENT_NAME="password-gen-$(date +%Y%m%d-%H%M%S)"
    
    # Deploy the template
    az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --template-file "main.bicep" \
        --parameters \
            location="$LOCATION" \
            environment="$ENVIRONMENT" \
            uniqueSuffix="$UNIQUE_SUFFIX" \
            functionAppNodeVersion="$NODE_VERSION" \
            enableKeyVaultPurgeProtection="$ENABLE_PURGE_PROTECTION" \
            keyVaultRetentionDays="$RETENTION_DAYS" \
        --output none
    
    print_success "Infrastructure deployment completed"
    
    # Get deployment outputs
    print_status "Retrieving deployment outputs..."
    OUTPUTS=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query 'properties.outputs' \
        --output json)
    
    # Extract key values
    FUNCTION_APP_NAME=$(echo "$OUTPUTS" | jq -r '.functionAppName.value')
    FUNCTION_APP_URL=$(echo "$OUTPUTS" | jq -r '.functionAppUrl.value')
    KEY_VAULT_NAME=$(echo "$OUTPUTS" | jq -r '.keyVaultName.value')
    KEY_VAULT_URI=$(echo "$OUTPUTS" | jq -r '.keyVaultUri.value')
    
    echo
    print_success "Deployment Summary:"
    echo "  Function App: $FUNCTION_APP_NAME"
    echo "  Function URL: $FUNCTION_APP_URL"
    echo "  Key Vault: $KEY_VAULT_NAME"
    echo "  Key Vault URI: $KEY_VAULT_URI"
    echo
}

# Function to validate deployment
validate_deployment() {
    print_status "Validating deployment..."
    
    # Check Function App status
    FUNCTION_STATUS=$(az functionapp show \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query 'state' \
        --output tsv)
    
    if [[ "$FUNCTION_STATUS" == "Running" ]]; then
        print_success "Function App is running"
    else
        print_warning "Function App status: $FUNCTION_STATUS"
    fi
    
    # Check Key Vault access
    if az keyvault show --name "$KEY_VAULT_NAME" &> /dev/null; then
        print_success "Key Vault is accessible"
    else
        print_warning "Key Vault may not be fully configured"
    fi
    
    # Check RBAC assignment
    ROLE_ASSIGNMENTS=$(az role assignment list \
        --scope "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME" \
        --query 'length(@)')
    
    if [[ "$ROLE_ASSIGNMENTS" -gt 0 ]]; then
        print_success "RBAC assignments configured"
    else
        print_warning "RBAC assignments may still be processing"
    fi
}

# Function to display next steps
show_next_steps() {
    echo
    print_status "Next Steps:"
    echo "1. Deploy the Function App code using Azure Functions Core Tools"
    echo "2. Test the password generator API"
    echo "3. Monitor the application using Application Insights"
    echo
    echo "Function App Deployment Command:"
    echo "  func azure functionapp publish $FUNCTION_APP_NAME"
    echo
    echo "Test API Command (after code deployment):"
    echo "  curl -X POST \"$FUNCTION_APP_URL/api/generatePassword?code=<function-key>\" \\"
    echo "       -H \"Content-Type: application/json\" \\"
    echo "       -d '{\"secretName\": \"test-password\", \"length\": 16}'"
    echo
    echo "Access Azure Portal:"
    echo "  https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP"
    echo
}

# Main execution
main() {
    echo "============================================================================"
    echo "Azure Password Generator - Bicep Deployment Script"
    echo "============================================================================"
    echo
    
    # Check if we're in the right directory
    if [[ ! -f "main.bicep" ]]; then
        print_error "main.bicep file not found. Please run this script from the bicep directory."
        exit 1
    fi
    
    check_prerequisites
    get_user_inputs
    
    # Confirm deployment
    echo
    read -p "Proceed with deployment? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_status "Deployment cancelled by user"
        exit 0
    fi
    
    echo
    print_status "Starting deployment process..."
    create_resource_group
    deploy_infrastructure
    validate_deployment
    show_next_steps
    
    print_success "Deployment completed successfully! 🎉"
}

# Handle script interruption
trap 'print_error "Deployment interrupted by user"; exit 1' INT

# Execute main function
main "$@"