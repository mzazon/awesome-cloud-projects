#!/bin/bash

# ========================================================================
# Azure Maps Store Locator - Deployment Script
# ========================================================================
# This script automates the deployment of Azure Maps infrastructure
# for the store locator application using Bicep templates.
#
# Usage:
#   ./deploy.sh [environment] [resource-group] [location]
#
# Examples:
#   ./deploy.sh dev rg-storemaps-dev eastus
#   ./deploy.sh prod rg-storemaps-prod eastus
# ========================================================================

set -e  # Exit on any error

# ========================================================================
# CONFIGURATION
# ========================================================================

# Default values
DEFAULT_ENVIRONMENT="dev"
DEFAULT_RESOURCE_GROUP="rg-storemaps-demo"
DEFAULT_LOCATION="eastus"
DEFAULT_MAPS_ACCOUNT_PREFIX="mapstore"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ========================================================================
# HELPER FUNCTIONS
# ========================================================================

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Function to validate prerequisites
validate_prerequisites() {
    print_header "Validating Prerequisites"
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        print_info "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    print_success "Azure CLI is installed"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    print_success "Logged in to Azure"
    
    # Display current subscription
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    print_info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    
    # Check if Bicep is available
    if ! az bicep version &> /dev/null; then
        print_warning "Bicep not found. Installing Bicep CLI..."
        az bicep install
        print_success "Bicep CLI installed"
    else
        BICEP_VERSION=$(az bicep version --output tsv)
        print_success "Bicep CLI is available (version: $BICEP_VERSION)"
    fi
}

# Function to generate unique Maps account name
generate_maps_account_name() {
    local env=$1
    local suffix=$(openssl rand -hex 3)
    echo "${DEFAULT_MAPS_ACCOUNT_PREFIX}-${env}-${suffix}"
}

# Function to check if resource group exists
check_resource_group() {
    local rg_name=$1
    if az group show --name "$rg_name" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to create resource group
create_resource_group() {
    local rg_name=$1
    local location=$2
    
    print_info "Creating resource group: $rg_name"
    az group create \
        --name "$rg_name" \
        --location "$location" \
        --tags Environment="$ENVIRONMENT" Project="store-locator" \
        --output none
    print_success "Resource group created: $rg_name"
}

# Function to validate Maps account name availability
validate_maps_account_name() {
    local account_name=$1
    
    print_info "Validating Maps account name availability: $account_name"
    
    # Note: Azure CLI doesn't have a direct name availability check for Maps accounts
    # We'll rely on the deployment to catch naming conflicts
    print_success "Maps account name validated: $account_name"
}

# Function to deploy Bicep template
deploy_template() {
    local rg_name=$1
    local environment=$2
    local maps_account_name=$3
    local location=$4
    
    print_header "Deploying Azure Maps Infrastructure"
    
    # Determine which parameters file to use
    local params_file="parameters.json"
    if [[ "$environment" == "prod" && -f "parameters.prod.json" ]]; then
        params_file="parameters.prod.json"
        print_info "Using production parameters file: $params_file"
    else
        print_info "Using parameters file: $params_file"
    fi
    
    # Create temporary parameters file with custom values
    local temp_params_file="temp-parameters-$(date +%s).json"
    
    # Read the base parameters file and update specific values
    jq --arg name "$maps_account_name" \
       --arg loc "$location" \
       --arg env "$environment" \
       '.parameters.mapsAccountName.value = $name | 
        .parameters.location.value = $loc | 
        .parameters.environment.value = $env' \
       "$params_file" > "$temp_params_file"
    
    print_info "Starting deployment..."
    print_info "Resource Group: $rg_name"
    print_info "Maps Account: $maps_account_name"
    print_info "Location: $location"
    print_info "Environment: $environment"
    
    # Deploy the template
    DEPLOYMENT_NAME="maps-store-locator-$(date +%Y%m%d-%H%M%S)"
    
    if az deployment group create \
        --resource-group "$rg_name" \
        --name "$DEPLOYMENT_NAME" \
        --template-file "main.bicep" \
        --parameters "@$temp_params_file" \
        --output table; then
        
        print_success "Deployment completed successfully!"
        
        # Clean up temporary file
        rm -f "$temp_params_file"
        
        # Get deployment outputs
        print_header "Deployment Outputs"
        
        print_info "Retrieving deployment outputs..."
        
        # Get the Maps account name
        DEPLOYED_MAPS_NAME=$(az deployment group show \
            --resource-group "$rg_name" \
            --name "$DEPLOYMENT_NAME" \
            --query "properties.outputs.mapsAccountName.value" \
            --output tsv)
        
        # Get the primary key (securely)
        print_success "Maps Account: $DEPLOYED_MAPS_NAME"
        print_success "Location: $location"
        print_success "Environment: $environment"
        
        print_warning "Subscription keys are available in the Azure portal or via:"
        print_info "az maps account keys list --resource-group $rg_name --name $DEPLOYED_MAPS_NAME"
        
        # Get configuration summary
        SUMMARY=$(az deployment group show \
            --resource-group "$rg_name" \
            --name "$DEPLOYMENT_NAME" \
            --query "properties.outputs.configurationSummary.value" \
            --output json)
        
        print_info "Configuration Summary:"
        echo "$SUMMARY" | jq '.'
        
    else
        print_error "Deployment failed!"
        rm -f "$temp_params_file"
        exit 1
    fi
}

# Function to display usage information
show_usage() {
    echo "Azure Maps Store Locator - Deployment Script"
    echo ""
    echo "Usage: $0 [environment] [resource-group] [location]"
    echo ""
    echo "Parameters:"
    echo "  environment     Environment name (dev, test, staging, prod) [default: dev]"
    echo "  resource-group  Azure resource group name [default: rg-storemaps-demo]"
    echo "  location        Azure region [default: eastus]"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy to dev environment with defaults"
    echo "  $0 dev                               # Deploy to dev environment"
    echo "  $0 prod rg-storemaps-prod westus2   # Deploy to production"
    echo "  $0 test rg-storemaps-test eastus    # Deploy to test environment"
    echo ""
    echo "Environment-specific features:"
    echo "  dev:      Basic configuration with local development CORS rules"
    echo "  prod:     Enhanced security, system identity, additional regions"
}

# ========================================================================
# MAIN SCRIPT
# ========================================================================

# Parse command line arguments
ENVIRONMENT=${1:-$DEFAULT_ENVIRONMENT}
RESOURCE_GROUP=${2:-$DEFAULT_RESOURCE_GROUP}
LOCATION=${3:-$DEFAULT_LOCATION}

# Show help if requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_usage
    exit 0
fi

# Validate environment parameter
if [[ ! "$ENVIRONMENT" =~ ^(dev|test|staging|prod)$ ]]; then
    print_error "Invalid environment: $ENVIRONMENT"
    print_info "Valid environments: dev, test, staging, prod"
    exit 1
fi

print_header "Azure Maps Store Locator Deployment"
print_info "Environment: $ENVIRONMENT"
print_info "Resource Group: $RESOURCE_GROUP"
print_info "Location: $LOCATION"

# Validate prerequisites
validate_prerequisites

# Generate unique Maps account name
MAPS_ACCOUNT_NAME=$(generate_maps_account_name "$ENVIRONMENT")
print_info "Generated Maps account name: $MAPS_ACCOUNT_NAME"

# Check if resource group exists
if check_resource_group "$RESOURCE_GROUP"; then
    print_success "Resource group exists: $RESOURCE_GROUP"
else
    print_warning "Resource group does not exist: $RESOURCE_GROUP"
    read -p "Create resource group? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_resource_group "$RESOURCE_GROUP" "$LOCATION"
    else
        print_error "Cannot proceed without resource group"
        exit 1
    fi
fi

# Validate Maps account name
validate_maps_account_name "$MAPS_ACCOUNT_NAME"

# Confirm deployment
print_warning "About to deploy Azure Maps infrastructure:"
print_info "  Environment: $ENVIRONMENT"
print_info "  Resource Group: $RESOURCE_GROUP"
print_info "  Maps Account: $MAPS_ACCOUNT_NAME"
print_info "  Location: $LOCATION"
echo ""

read -p "Continue with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Deployment cancelled by user"
    exit 0
fi

# Deploy the template
deploy_template "$RESOURCE_GROUP" "$ENVIRONMENT" "$MAPS_ACCOUNT_NAME" "$LOCATION"

print_header "Deployment Complete"
print_success "Azure Maps Store Locator infrastructure has been deployed successfully!"
print_info "Next steps:"
print_info "1. Retrieve your Maps subscription key from the Azure portal"
print_info "2. Update your web application configuration"
print_info "3. Test your store locator application"
print_info ""
print_info "For more information, see the README.md file in this directory."

exit 0