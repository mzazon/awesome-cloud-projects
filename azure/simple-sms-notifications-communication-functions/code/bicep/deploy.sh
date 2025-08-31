#!/bin/bash

# Deploy script for Simple SMS Notifications Bicep template
# This script provides an interactive deployment experience

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        print_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    if ! az bicep version &> /dev/null; then
        print_warning "Bicep CLI not found. Installing..."
        az bicep install
    fi
    
    print_success "Prerequisites check passed"
}

# Get deployment parameters
get_parameters() {
    print_info "Gathering deployment parameters..."
    
    # Resource Group
    read -p "Resource Group name (default: rg-sms-notifications): " RESOURCE_GROUP
    RESOURCE_GROUP=${RESOURCE_GROUP:-rg-sms-notifications}
    
    # Location
    read -p "Azure region (default: eastus): " LOCATION
    LOCATION=${LOCATION:-eastus}
    
    # Environment
    echo "Select environment:"
    echo "1) dev (default)"
    echo "2) test"
    echo "3) prod"
    read -p "Choice (1-3): " ENV_CHOICE
    case $ENV_CHOICE in
        2) ENVIRONMENT="test";;
        3) ENVIRONMENT="prod";;
        *) ENVIRONMENT="dev";;
    esac
    
    # Unique suffix
    read -p "Unique suffix for resources (leave empty for auto-generation): " UNIQUE_SUFFIX
    
    # Application Insights
    read -p "Enable Application Insights monitoring? (Y/n): " ENABLE_AI
    if [[ $ENABLE_AI =~ ^[Nn]$ ]]; then
        ENABLE_APPLICATION_INSIGHTS="false"
    else
        ENABLE_APPLICATION_INSIGHTS="true"
    fi
    
    print_success "Parameters collected"
}

# Create resource group if it doesn't exist
create_resource_group() {
    print_info "Checking resource group: $RESOURCE_GROUP"
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_info "Creating resource group: $RESOURCE_GROUP"
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
        print_success "Resource group created"
    else
        print_info "Resource group already exists"
    fi
}

# Deploy Bicep template
deploy_template() {
    print_info "Starting Bicep template deployment..."
    
    DEPLOYMENT_NAME="sms-notifications-$(date +%Y%m%d-%H%M%S)"
    
    # Build parameters
    PARAMETERS="environment=$ENVIRONMENT"
    if [ ! -z "$UNIQUE_SUFFIX" ]; then
        PARAMETERS="$PARAMETERS uniqueSuffix=$UNIQUE_SUFFIX"
    fi
    PARAMETERS="$PARAMETERS enableApplicationInsights=$ENABLE_APPLICATION_INSIGHTS"
    
    # Deploy template
    DEPLOYMENT_OUTPUT=$(az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --template-file main.bicep \
        --parameters $PARAMETERS \
        --name "$DEPLOYMENT_NAME" \
        --output json)
    
    if [ $? -eq 0 ]; then
        print_success "Deployment completed successfully"
        
        # Extract outputs
        COMMUNICATION_SERVICE_NAME=$(echo $DEPLOYMENT_OUTPUT | jq -r '.properties.outputs.communicationServiceName.value')
        FUNCTION_APP_NAME=$(echo $DEPLOYMENT_OUTPUT | jq -r '.properties.outputs.functionAppName.value')
        FUNCTION_APP_URL=$(echo $DEPLOYMENT_OUTPUT | jq -r '.properties.outputs.functionAppUrl.value')
        
        print_success "Resources created:"
        echo "  • Communication Service: $COMMUNICATION_SERVICE_NAME"
        echo "  • Function App: $FUNCTION_APP_NAME"
        echo "  • Function App URL: $FUNCTION_APP_URL"
        
        # Save deployment info
        cat > deployment-info.json << EOF
{
  "deploymentName": "$DEPLOYMENT_NAME",
  "resourceGroup": "$RESOURCE_GROUP",
  "communicationServiceName": "$COMMUNICATION_SERVICE_NAME",
  "functionAppName": "$FUNCTION_APP_NAME",
  "functionAppUrl": "$FUNCTION_APP_URL",
  "deploymentDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
        print_success "Deployment info saved to: deployment-info.json"
        
    else
        print_error "Deployment failed"
        exit 1
    fi
}

# Show next steps
show_next_steps() {
    print_info "Next steps to complete your SMS notification system:"
    echo
    echo "1. Purchase a phone number:"
    echo "   az communication phonenumber list-available \\"
    echo "     --resource-group $RESOURCE_GROUP \\"
    echo "     --communication-service $COMMUNICATION_SERVICE_NAME \\"
    echo "     --phone-number-type \"tollFree\" \\"
    echo "     --assignment-type \"application\" \\"
    echo "     --capabilities \"sms\""
    echo
    echo "2. Update Function App with phone number:"
    echo "   az functionapp config appsettings set \\"
    echo "     --name $FUNCTION_APP_NAME \\"
    echo "     --resource-group $RESOURCE_GROUP \\"
    echo "     --settings \"SMS_FROM_PHONE=+18001234567\""
    echo
    echo "3. Deploy your function code (see README.md for details)"
    echo
    echo "4. Test SMS functionality"
    echo
    print_warning "Important: Toll-free numbers require verification before SMS can be sent"
    print_info "See Azure portal > Communication Services > Phone numbers for verification status"
}

# Estimate costs
show_cost_estimate() {
    print_info "Estimated monthly costs:"
    echo "  • Function App (Consumption): \$0 (pay-per-execution)"
    echo "  • Storage Account: \$1-2"
    echo "  • Phone Number (toll-free): \$2"
    echo "  • SMS Messages: \$0.0075-0.01 per message"
    if [ "$ENABLE_APPLICATION_INSIGHTS" = "true" ]; then
        echo "  • Application Insights: Based on data ingestion (~\$1-5)"
    fi
    echo "  • Total base cost: ~\$3-7/month + SMS usage"
}

# Main execution
main() {
    echo
    echo "🚀 Azure SMS Notifications Deployment Script"
    echo "=============================================="
    echo
    
    check_prerequisites
    echo
    
    get_parameters
    echo
    
    show_cost_estimate
    echo
    
    read -p "Continue with deployment? (Y/n): " CONTINUE
    if [[ $CONTINUE =~ ^[Nn]$ ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    echo
    create_resource_group
    echo
    
    deploy_template
    echo
    
    show_next_steps
    echo
    
    print_success "Deployment script completed! 🎉"
}

# Run main function
main "$@"