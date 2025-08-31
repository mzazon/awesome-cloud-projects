#!/bin/bash

# Deploy Content Personalization Engine with AI Foundry and Cosmos
# This script deploys the complete Bicep template with proper error handling

set -e  # Exit on any error

# Color codes for output
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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        echo "Install guide: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        print_error "You are not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Bicep is installed
    if ! az bicep version &> /dev/null; then
        print_warning "Bicep CLI not found. Installing..."
        az bicep install
    fi
    
    print_success "Prerequisites check passed"
}

# Function to validate template
validate_template() {
    local resource_group=$1
    local template_file=$2
    local parameters_file=$3
    
    print_status "Validating Bicep template..."
    
    if az deployment group validate \
        --resource-group "$resource_group" \
        --template-file "$template_file" \
        --parameters "@$parameters_file" \
        --output none; then
        print_success "Template validation passed"
    else
        print_error "Template validation failed"
        exit 1
    fi
}

# Function to deploy template
deploy_template() {
    local resource_group=$1
    local template_file=$2
    local parameters_file=$3
    local deployment_name=$4
    
    print_status "Starting deployment: $deployment_name"
    print_status "Resource Group: $resource_group"
    print_status "Template: $template_file"
    print_status "Parameters: $parameters_file"
    
    if az deployment group create \
        --resource-group "$resource_group" \
        --template-file "$template_file" \
        --parameters "@$parameters_file" \
        --name "$deployment_name" \
        --output table; then
        print_success "Deployment completed successfully"
    else
        print_error "Deployment failed"
        exit 1
    fi
}

# Function to show deployment outputs
show_outputs() {
    local resource_group=$1
    local deployment_name=$2
    
    print_status "Retrieving deployment outputs..."
    
    # Get and display key outputs
    echo ""
    echo "=== Deployment Outputs ==="
    
    # Function App URL
    FUNCTION_URL=$(az deployment group show \
        --resource-group "$resource_group" \
        --name "$deployment_name" \
        --query properties.outputs.functionAppUrl.value \
        --output tsv 2>/dev/null || echo "Not available")
    echo "Function App URL: $FUNCTION_URL"
    
    # OpenAI Endpoint
    OPENAI_ENDPOINT=$(az deployment group show \
        --resource-group "$resource_group" \
        --name "$deployment_name" \
        --query properties.outputs.openAiEndpoint.value \
        --output tsv 2>/dev/null || echo "Not available")
    echo "OpenAI Endpoint: $OPENAI_ENDPOINT"
    
    # Cosmos DB Account
    COSMOS_ACCOUNT=$(az deployment group show \
        --resource-group "$resource_group" \
        --name "$deployment_name" \
        --query properties.outputs.cosmosDbAccountName.value \
        --output tsv 2>/dev/null || echo "Not available")
    echo "Cosmos DB Account: $COSMOS_ACCOUNT"
    
    # AI Foundry Workspace
    AI_WORKSPACE=$(az deployment group show \
        --resource-group "$resource_group" \
        --name "$deployment_name" \
        --query properties.outputs.aiFoundryWorkspaceName.value \
        --output tsv 2>/dev/null || echo "Not available")
    echo "AI Foundry Workspace: $AI_WORKSPACE"
    
    echo "=========================="
    echo ""
}

# Main deployment function
main() {
    # Default values
    RESOURCE_GROUP=""
    LOCATION="eastus"
    TEMPLATE_FILE="main.bicep"
    PARAMETERS_FILE="parameters.json"
    DEPLOYMENT_NAME="personalization-deployment-$(date +%Y%m%d-%H%M%S)"
    CREATE_RG=false
    VALIDATE_ONLY=false
    
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
            -t|--template)
                TEMPLATE_FILE="$2"
                shift 2
                ;;
            -p|--parameters)
                PARAMETERS_FILE="$2"
                shift 2
                ;;
            -n|--name)
                DEPLOYMENT_NAME="$2"
                shift 2
                ;;
            --create-rg)
                CREATE_RG=true
                shift
                ;;
            --validate-only)
                VALIDATE_ONLY=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  -g, --resource-group    Resource group name (required)"
                echo "  -l, --location         Azure region (default: eastus)"
                echo "  -t, --template         Bicep template file (default: main.bicep)"
                echo "  -p, --parameters       Parameters file (default: parameters.json)"
                echo "  -n, --name             Deployment name (default: auto-generated)"
                echo "  --create-rg            Create resource group if it doesn't exist"
                echo "  --validate-only        Only validate template, don't deploy"
                echo "  -h, --help             Show this help message"
                echo ""
                echo "Example:"
                echo "  $0 -g rg-personalization-demo --create-rg"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$RESOURCE_GROUP" ]]; then
        print_error "Resource group name is required. Use -g or --resource-group"
        exit 1
    fi
    
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        print_error "Template file not found: $TEMPLATE_FILE"
        exit 1
    fi
    
    if [[ ! -f "$PARAMETERS_FILE" ]]; then
        print_error "Parameters file not found: $PARAMETERS_FILE"
        exit 1
    fi
    
    # Start deployment process
    echo "========================================"
    echo "Content Personalization Engine Deployment"
    echo "========================================"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Create resource group if requested
    if [[ "$CREATE_RG" == true ]]; then
        print_status "Creating resource group: $RESOURCE_GROUP"
        if az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none; then
            print_success "Resource group created"
        else
            print_error "Failed to create resource group"
            exit 1
        fi
    fi
    
    # Validate resource group exists
    if ! az group show --name "$RESOURCE_GROUP" --output none &> /dev/null; then
        print_error "Resource group '$RESOURCE_GROUP' does not exist"
        print_warning "Use --create-rg flag to create it automatically"
        exit 1
    fi
    
    # Validate template
    validate_template "$RESOURCE_GROUP" "$TEMPLATE_FILE" "$PARAMETERS_FILE"
    
    # If validate-only flag is set, exit here
    if [[ "$VALIDATE_ONLY" == true ]]; then
        print_success "Template validation completed successfully"
        exit 0
    fi
    
    # Deploy template
    deploy_template "$RESOURCE_GROUP" "$TEMPLATE_FILE" "$PARAMETERS_FILE" "$DEPLOYMENT_NAME"
    
    # Show outputs
    show_outputs "$RESOURCE_GROUP" "$DEPLOYMENT_NAME"
    
    # Final success message
    print_success "Content Personalization Engine deployed successfully!"
    print_status "You can now proceed with the function code deployment as described in the recipe"
    
    echo ""
    echo "Next steps:"
    echo "1. Deploy the Python function code to the Function App"
    echo "2. Configure vector search indexes in Cosmos DB"
    echo "3. Set up AI Foundry agent configurations"
    echo "4. Test the personalization API endpoints"
    echo ""
    echo "For detailed instructions, refer to the recipe documentation."
}

# Run main function with all arguments
main "$@"