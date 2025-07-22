#!/bin/bash

#==============================================================================
# Azure Elastic SAN and VMSS Database Infrastructure Deployment Script
# This script deploys the high-performance database infrastructure using Bicep
#==============================================================================

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
RESOURCE_GROUP=""
LOCATION="East US"
TEMPLATE_FILE="main.bicep"
PARAMETERS_FILE="parameters.json"
DEPLOYMENT_NAME="elastic-san-vmss-$(date +%Y%m%d-%H%M%S)"
SUBSCRIPTION_ID=""
SKIP_CONFIRMATION=false
VALIDATE_ONLY=false

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
    echo -e "${BLUE}$1${NC}"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Elastic SAN and VMSS high-performance database infrastructure.

OPTIONS:
    -g, --resource-group    Resource group name (required)
    -l, --location          Azure location (default: East US)
    -s, --subscription      Azure subscription ID
    -t, --template          Template file path (default: main.bicep)
    -p, --parameters        Parameters file path (default: parameters.json)
    -n, --name              Deployment name
    -y, --yes               Skip confirmation prompts
    -v, --validate-only     Only validate the template, don't deploy
    -h, --help              Show this help message

EXAMPLES:
    $0 -g rg-elastic-san-demo
    $0 -g rg-elastic-san-demo -l "West US 2" -s "your-subscription-id"
    $0 -g rg-elastic-san-demo -v  # Validate only
    $0 -g rg-elastic-san-demo -y  # Skip confirmation

EOF
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        print_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Bicep is installed
    if ! az bicep version &> /dev/null; then
        print_warning "Bicep is not installed. Installing..."
        az bicep install
    fi
    
    # Check if template file exists
    if [ ! -f "$TEMPLATE_FILE" ]; then
        print_error "Template file '$TEMPLATE_FILE' not found."
        exit 1
    fi
    
    # Check if parameters file exists
    if [ ! -f "$PARAMETERS_FILE" ]; then
        print_error "Parameters file '$PARAMETERS_FILE' not found."
        exit 1
    fi
    
    print_status "Prerequisites check completed."
}

# Function to set Azure subscription
set_subscription() {
    if [ -n "$SUBSCRIPTION_ID" ]; then
        print_status "Setting subscription to: $SUBSCRIPTION_ID"
        az account set --subscription "$SUBSCRIPTION_ID"
    fi
    
    # Show current subscription
    CURRENT_SUB=$(az account show --query "name" --output tsv)
    print_status "Current subscription: $CURRENT_SUB"
}

# Function to create resource group
create_resource_group() {
    print_header "Creating Resource Group..."
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_warning "Resource group '$RESOURCE_GROUP' already exists."
    else
        print_status "Creating resource group: $RESOURCE_GROUP"
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
    fi
}

# Function to validate template
validate_template() {
    print_header "Validating Template..."
    
    print_status "Validating Bicep template..."
    if az deployment group validate \
        --resource-group "$RESOURCE_GROUP" \
        --template-file "$TEMPLATE_FILE" \
        --parameters @"$PARAMETERS_FILE" \
        --output table; then
        print_status "Template validation successful."
    else
        print_error "Template validation failed."
        exit 1
    fi
}

# Function to deploy template
deploy_template() {
    print_header "Deploying Template..."
    
    print_status "Starting deployment: $DEPLOYMENT_NAME"
    
    # Start deployment
    if az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --template-file "$TEMPLATE_FILE" \
        --parameters @"$PARAMETERS_FILE" \
        --output table; then
        print_status "Deployment completed successfully."
    else
        print_error "Deployment failed."
        exit 1
    fi
}

# Function to show deployment outputs
show_outputs() {
    print_header "Deployment Outputs..."
    
    print_status "Retrieving deployment outputs..."
    az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query "properties.outputs" \
        --output table
}

# Function to show post-deployment information
show_post_deployment_info() {
    print_header "Post-Deployment Information..."
    
    # Get load balancer public IP
    LB_IP=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query "properties.outputs.loadBalancerPublicIP.value" \
        --output tsv)
    
    # Get load balancer FQDN
    LB_FQDN=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DEPLOYMENT_NAME" \
        --query "properties.outputs.loadBalancerFqdn.value" \
        --output tsv)
    
    echo ""
    print_status "Deployment completed successfully!"
    echo ""
    echo "Connection Information:"
    echo "  Load Balancer IP: $LB_IP"
    echo "  Load Balancer FQDN: $LB_FQDN"
    echo ""
    echo "To connect to PostgreSQL:"
    echo "  psql -h $LB_IP -U pgadmin -d appdb"
    echo "  psql -h $LB_FQDN -U pgadmin -d appdb"
    echo ""
    echo "To monitor the deployment:"
    echo "  az monitor autoscale show --resource-group $RESOURCE_GROUP --name vmss-autoscale-*"
    echo ""
    echo "To check VMSS instances:"
    echo "  az vmss list-instances --resource-group $RESOURCE_GROUP --name vmss-db-*"
    echo ""
}

# Function to show estimated costs
show_estimated_costs() {
    print_header "Estimated Monthly Costs..."
    
    cat << EOF
Based on the default configuration, estimated monthly costs:

Core Infrastructure:
  - Virtual Machine Scale Set (2-10 instances): \$200-1000/month
  - Azure Elastic SAN (3 TiB): \$150-300/month
  - PostgreSQL Flexible Server: \$100-200/month
  - Load Balancer: \$20-50/month
  - Monitoring and Logging: \$50-100/month

Total Estimated Range: \$520-1650/month

Notes:
  - Costs vary by region and actual usage
  - Auto-scaling will adjust compute costs based on demand
  - Use Azure Cost Management for accurate tracking
  - Consider reserved instances for predictable workloads

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
        -s|--subscription)
            SUBSCRIPTION_ID="$2"
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
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -v|--validate-only)
            VALIDATE_ONLY=true
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
if [ -z "$RESOURCE_GROUP" ]; then
    print_error "Resource group is required. Use -g or --resource-group."
    show_usage
    exit 1
fi

# Main execution
main() {
    print_header "Azure Elastic SAN and VMSS Database Infrastructure Deployment"
    echo ""
    
    print_status "Configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Template: $TEMPLATE_FILE"
    echo "  Parameters: $PARAMETERS_FILE"
    echo "  Deployment Name: $DEPLOYMENT_NAME"
    echo "  Validate Only: $VALIDATE_ONLY"
    echo ""
    
    # Show estimated costs
    show_estimated_costs
    
    # Confirmation prompt
    if [ "$SKIP_CONFIRMATION" = false ]; then
        read -p "Do you want to continue with the deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deployment cancelled."
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    set_subscription
    create_resource_group
    validate_template
    
    if [ "$VALIDATE_ONLY" = false ]; then
        deploy_template
        show_outputs
        show_post_deployment_info
    else
        print_status "Validation completed successfully. Skipping deployment."
    fi
}

# Run main function
main