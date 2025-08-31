#!/bin/bash

# Simple Todo API - Bicep Deployment Script
# This script deploys the Todo API infrastructure using Azure Bicep

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/main.bicep"
PARAMETERS_FILE="$SCRIPT_DIR/parameters.json"

# Default values
RESOURCE_GROUP=""
LOCATION="eastus"
ENVIRONMENT="dev"
RESOURCE_PREFIX=""
SUBSCRIPTION=""
DEPLOYMENT_NAME="simple-todo-api-$(date +%Y%m%d-%H%M%S)"

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

# Function to show usage
show_usage() {
    cat << EOF
Simple Todo API Bicep Deployment Script

Usage: $0 [OPTIONS]

Required Options:
  -g, --resource-group    Resource group name
  -p, --prefix           Resource prefix (3-10 characters)

Optional Options:
  -l, --location         Azure region (default: eastus)
  -e, --environment      Environment name: dev|test|prod (default: dev)
  -s, --subscription     Azure subscription ID
  -n, --deployment-name  Deployment name (default: auto-generated)
  -f, --parameters-file  Custom parameters file (default: parameters.json)
  --skip-resource-group  Skip resource group creation
  --validate-only        Validate template without deploying
  --what-if             Show what would be deployed
  -h, --help            Show this help message

Examples:
  # Basic deployment
  $0 -g "rg-todo-api" -p "mytodo"

  # Production deployment with custom location
  $0 -g "rg-todo-prod" -p "todo" -e "prod" -l "westus2"

  # Validate template only
  $0 -g "rg-todo-api" -p "mytodo" --validate-only

  # Show what would be deployed
  $0 -g "rg-todo-api" -p "mytodo" --what-if

EOF
}

# Function to validate prerequisites
validate_prerequisites() {
    print_status "Validating prerequisites..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check if Bicep is available
    if ! az bicep version &> /dev/null; then
        print_warning "Bicep CLI not found. Installing..."
        az bicep install
    fi

    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    # Check if template file exists
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        print_error "Template file not found: $TEMPLATE_FILE"
        exit 1
    fi

    # Check if parameters file exists
    if [[ ! -f "$PARAMETERS_FILE" ]]; then
        print_error "Parameters file not found: $PARAMETERS_FILE"
        exit 1
    fi

    print_success "Prerequisites validated"
}

# Function to validate parameters
validate_parameters() {
    print_status "Validating parameters..."

    # Validate required parameters
    if [[ -z "$RESOURCE_GROUP" ]]; then
        print_error "Resource group name is required. Use -g or --resource-group"
        exit 1
    fi

    if [[ -z "$RESOURCE_PREFIX" ]]; then
        print_error "Resource prefix is required. Use -p or --prefix"
        exit 1
    fi

    # Validate resource prefix length
    if [[ ${#RESOURCE_PREFIX} -lt 3 || ${#RESOURCE_PREFIX} -gt 10 ]]; then
        print_error "Resource prefix must be between 3 and 10 characters"
        exit 1
    fi

    # Validate environment
    if [[ ! "$ENVIRONMENT" =~ ^(dev|test|prod)$ ]]; then
        print_error "Environment must be one of: dev, test, prod"
        exit 1
    fi

    print_success "Parameters validated"
}

# Function to set subscription
set_subscription() {
    if [[ -n "$SUBSCRIPTION" ]]; then
        print_status "Setting subscription to: $SUBSCRIPTION"
        az account set --subscription "$SUBSCRIPTION"
        print_success "Subscription set"
    fi
}

# Function to create resource group
create_resource_group() {
    if [[ "$SKIP_RESOURCE_GROUP" == "true" ]]; then
        print_status "Skipping resource group creation"
        return
    fi

    print_status "Creating resource group: $RESOURCE_GROUP in $LOCATION"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_warning "Resource group already exists: $RESOURCE_GROUP"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags "Environment=$ENVIRONMENT" "ManagedBy=BicepScript" "Project=SimpleTodoAPI"
        print_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to validate template
validate_template() {
    print_status "Validating Bicep template..."
    
    az deployment group validate \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETERS_FILE" \
        --parameters location="$LOCATION" environment="$ENVIRONMENT" resourcePrefix="$RESOURCE_PREFIX" \
        --no-prompt

    print_success "Template validation completed"
}

# Function to show what-if
show_what_if() {
    print_status "Showing what would be deployed..."
    
    az deployment group what-if \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETERS_FILE" \
        --parameters location="$LOCATION" environment="$ENVIRONMENT" resourcePrefix="$RESOURCE_PREFIX" \
        --no-prompt

    print_success "What-if analysis completed"
}

# Function to deploy template
deploy_template() {
    print_status "Deploying Bicep template..."
    print_status "Deployment name: $DEPLOYMENT_NAME"
    
    # Deploy the template
    az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETERS_FILE" \
        --parameters location="$LOCATION" environment="$ENVIRONMENT" resourcePrefix="$RESOURCE_PREFIX" \
        --no-prompt

    print_success "Deployment completed: $DEPLOYMENT_NAME"
}

# Function to show deployment outputs
show_outputs() {
    print_status "Deployment outputs:"
    
    az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query "properties.outputs" \
        --output table
}

# Function to show next steps
show_next_steps() {
    local function_app_url
    function_app_url=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query "properties.outputs.functionAppUrl.value" \
        --output tsv 2>/dev/null || echo "")

    cat << EOF

$(print_success "Deployment completed successfully!")

Next Steps:
1. Deploy your function code to the Function App
2. Test the API endpoints
3. Configure monitoring and alerts

Quick Commands:
# Get deployment outputs
az deployment group show --resource-group "$RESOURCE_GROUP" --name "$DEPLOYMENT_NAME" --query "properties.outputs"

# List created resources
az resource list --resource-group "$RESOURCE_GROUP" --output table

EOF

    if [[ -n "$function_app_url" ]]; then
        echo "# Test the API (after code deployment)"
        echo "curl -X GET \"${function_app_url}/api/todos\""
        echo
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -p|--prefix)
            RESOURCE_PREFIX="$2"
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
        -s|--subscription)
            SUBSCRIPTION="$2"
            shift 2
            ;;
        -n|--deployment-name)
            DEPLOYMENT_NAME="$2"
            shift 2
            ;;
        -f|--parameters-file)
            PARAMETERS_FILE="$2"
            shift 2
            ;;
        --skip-resource-group)
            SKIP_RESOURCE_GROUP="true"
            shift
            ;;
        --validate-only)
            VALIDATE_ONLY="true"
            shift
            ;;
        --what-if)
            WHAT_IF="true"
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

# Main execution
main() {
    echo "Simple Todo API - Bicep Deployment"
    echo "=================================="
    echo

    validate_prerequisites
    validate_parameters
    set_subscription

    # Show configuration
    print_status "Deployment Configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Environment: $ENVIRONMENT"
    echo "  Resource Prefix: $RESOURCE_PREFIX"
    echo "  Template File: $TEMPLATE_FILE"
    echo "  Parameters File: $PARAMETERS_FILE"
    echo

    # Create resource group (unless skipped)
    create_resource_group

    # Handle different execution modes
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        validate_template
        print_success "Template validation completed successfully"
        exit 0
    fi

    if [[ "$WHAT_IF" == "true" ]]; then
        show_what_if
        exit 0
    fi

    # Deploy template
    validate_template
    deploy_template
    show_outputs
    show_next_steps
}

# Run main function
main "$@"