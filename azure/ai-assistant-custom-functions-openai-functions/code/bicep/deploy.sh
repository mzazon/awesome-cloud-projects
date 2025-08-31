#!/bin/bash

# AI Assistant with Custom Functions - Bicep Deployment Script
# This script automates the deployment of the AI Assistant infrastructure using Azure Bicep

set -e  # Exit on any error

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/main.bicep"
PARAMETERS_FILE="${SCRIPT_DIR}/parameters.json"

# Default values
DEFAULT_RESOURCE_GROUP="rg-ai-assistant-demo"
DEFAULT_LOCATION="eastus"
DEFAULT_ENVIRONMENT="dev"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
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

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AI Assistant infrastructure using Azure Bicep.

OPTIONS:
    -g, --resource-group NAME    Resource group name (default: ${DEFAULT_RESOURCE_GROUP})
    -l, --location LOCATION      Azure region (default: ${DEFAULT_LOCATION})
    -e, --environment ENV        Environment (dev/test/prod) (default: ${DEFAULT_ENVIRONMENT})
    -s, --suffix SUFFIX          Unique suffix for resources (default: auto-generated)
    -p, --parameters FILE        Custom parameters file (default: ${PARAMETERS_FILE})
    -w, --what-if               Preview changes without deploying
    -v, --validate              Validate template only
    -h, --help                  Show this help message

EXAMPLES:
    # Deploy with defaults
    $0

    # Deploy to specific resource group and location
    $0 -g "rg-ai-prod" -l "eastus2" -e "prod"

    # Preview changes without deploying
    $0 --what-if

    # Use custom parameters file
    $0 -p "parameters-prod.json"

    # Validate template only
    $0 --validate
EOF
}

check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        print_info "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi

    # Check if template file exists
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        print_error "Template file not found: $TEMPLATE_FILE"
        exit 1
    fi

    # Check if parameters file exists (only if using default)
    if [[ "$PARAMETERS_FILE" == "${SCRIPT_DIR}/parameters.json" ]] && [[ ! -f "$PARAMETERS_FILE" ]]; then
        print_error "Parameters file not found: $PARAMETERS_FILE"
        exit 1
    fi

    print_success "Prerequisites check completed"
}

validate_template() {
    print_info "Validating Bicep template..."
    
    if az deployment group validate \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETERS_FILE" \
        --parameters uniqueSuffix="$UNIQUE_SUFFIX" environment="$ENVIRONMENT" location="$LOCATION" \
        --output none; then
        print_success "Template validation successful"
    else
        print_error "Template validation failed"
        exit 1
    fi
}

preview_deployment() {
    print_info "Previewing deployment changes..."
    
    az deployment group what-if \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETERS_FILE" \
        --parameters uniqueSuffix="$UNIQUE_SUFFIX" environment="$ENVIRONMENT" location="$LOCATION" \
        --color always
    
    print_warning "This is a preview. No resources will be deployed."
}

deploy_infrastructure() {
    print_info "Deploying AI Assistant infrastructure..."
    
    # Get start time
    START_TIME=$(date +%s)
    
    # Deploy the template
    DEPLOYMENT_OUTPUT=$(az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMETERS_FILE" \
        --parameters uniqueSuffix="$UNIQUE_SUFFIX" environment="$ENVIRONMENT" location="$LOCATION" \
        --output json)
    
    # Check deployment status
    if [[ $? -eq 0 ]]; then
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        print_success "Deployment completed in ${DURATION} seconds"
        
        # Extract and display outputs
        print_info "Deployment outputs:"
        echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs | to_entries[] | "\(.key): \(.value.value)"' 2>/dev/null || \
        echo "$DEPLOYMENT_OUTPUT" | grep -A 50 '"outputs"'
        
        # Save outputs to file
        OUTPUT_FILE="${SCRIPT_DIR}/deployment-outputs-$(date +%Y%m%d-%H%M%S).json"
        echo "$DEPLOYMENT_OUTPUT" | jq '.properties.outputs' > "$OUTPUT_FILE" 2>/dev/null || \
        echo "$DEPLOYMENT_OUTPUT" > "$OUTPUT_FILE"
        print_info "Outputs saved to: $OUTPUT_FILE"
        
    else
        print_error "Deployment failed"
        exit 1
    fi
}

post_deployment_info() {
    print_success "🎉 AI Assistant infrastructure deployed successfully!"
    
    cat << EOF

📋 Next Steps:
1. Deploy your Python functions to the Function App
2. Create and configure your AI Assistant using the OpenAI endpoint
3. Test the custom functions with the assistant
4. Monitor usage and costs in Azure Portal

🔗 Useful Commands:
# Stream Function App logs
az webapp log tail --name func-assistant-${UNIQUE_SUFFIX} --resource-group ${RESOURCE_GROUP}

# View resources in the portal
az group show --name ${RESOURCE_GROUP} --query 'properties.provisioningState'

# Check deployment status
az deployment group show --resource-group ${RESOURCE_GROUP} --name main

💰 Cost Management:
- Monitor costs in Azure Portal > Cost Management
- Set up budget alerts for the resource group
- Review OpenAI usage patterns to optimize capacity

🔒 Security:
- All secrets are stored in Key Vault
- Function App uses managed identity
- HTTPS is enforced for all endpoints

EOF
}

# Main script
main() {
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
            -s|--suffix)
                UNIQUE_SUFFIX="$2"
                shift 2
                ;;
            -p|--parameters)
                PARAMETERS_FILE="$2"
                shift 2
                ;;
            -w|--what-if)
                WHAT_IF=true
                shift
                ;;
            -v|--validate)
                VALIDATE_ONLY=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done

    # Set defaults
    RESOURCE_GROUP="${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"
    LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
    ENVIRONMENT="${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}"
    UNIQUE_SUFFIX="${UNIQUE_SUFFIX:-$(date +%s | tail -c 6)}"
    
    # Print configuration
    print_info "Deployment Configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Environment: $ENVIRONMENT"
    echo "  Unique Suffix: $UNIQUE_SUFFIX"
    echo "  Parameters File: $PARAMETERS_FILE"
    echo "  Template File: $TEMPLATE_FILE"
    echo ""

    # Run checks
    check_prerequisites

    # Create resource group if it doesn't exist
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_info "Creating resource group: $RESOURCE_GROUP"
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
        print_success "Resource group created"
    else
        print_info "Using existing resource group: $RESOURCE_GROUP"
    fi

    # Validate template
    validate_template

    # Handle different modes
    if [[ "$VALIDATE_ONLY" == true ]]; then
        print_success "Template validation completed successfully"
        exit 0
    elif [[ "$WHAT_IF" == true ]]; then
        preview_deployment
        exit 0
    else
        # Confirm deployment
        read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Deployment cancelled"
            exit 0
        fi
        
        # Deploy infrastructure
        deploy_infrastructure
        post_deployment_info
    fi
}

# Run main function with all arguments
main "$@"