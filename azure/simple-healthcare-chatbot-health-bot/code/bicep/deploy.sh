#!/bin/bash

# Azure Health Bot Deployment Script
# This script deploys the Azure Health Bot infrastructure using Bicep

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
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        print_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check Bicep version
    BICEP_VERSION=$(az bicep version 2>/dev/null | cut -d' ' -f3)
    if [[ -z "$BICEP_VERSION" ]]; then
        print_warning "Bicep CLI not found. Installing..."
        az bicep install
    else
        print_success "Bicep CLI version: $BICEP_VERSION"
    fi
    
    print_success "Prerequisites check completed"
}

# Function to set default values
set_defaults() {
    # Generate random suffix for unique naming
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 7))
    
    # Default values
    DEFAULT_RESOURCE_GROUP="rg-healthbot-${RANDOM_SUFFIX}"
    DEFAULT_LOCATION="eastus"
    DEFAULT_HEALTHBOT_NAME="healthbot-${RANDOM_SUFFIX}"
    DEFAULT_ENVIRONMENT="demo"
    DEFAULT_SKU="F0"
    DEFAULT_ORG_NAME="healthcare-org"
    
    print_status "Default values set with suffix: ${RANDOM_SUFFIX}"
}

# Function to prompt for user input
get_user_input() {
    print_status "Please provide deployment configuration:"
    
    read -p "Resource Group Name [${DEFAULT_RESOURCE_GROUP}]: " RESOURCE_GROUP
    RESOURCE_GROUP=${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}
    
    read -p "Location [${DEFAULT_LOCATION}]: " LOCATION
    LOCATION=${LOCATION:-$DEFAULT_LOCATION}
    
    read -p "Health Bot Name [${DEFAULT_HEALTHBOT_NAME}]: " HEALTHBOT_NAME
    HEALTHBOT_NAME=${HEALTHBOT_NAME:-$DEFAULT_HEALTHBOT_NAME}
    
    read -p "Environment (dev/test/prod/demo) [${DEFAULT_ENVIRONMENT}]: " ENVIRONMENT
    ENVIRONMENT=${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}
    
    read -p "SKU (F0/S1) [${DEFAULT_SKU}]: " SKU
    SKU=${SKU:-$DEFAULT_SKU}
    
    read -p "Organization Name [${DEFAULT_ORG_NAME}]: " ORG_NAME
    ORG_NAME=${ORG_NAME:-$DEFAULT_ORG_NAME}
    
    read -p "Enable Audit Logging (true/false) [true]: " ENABLE_LOGGING
    ENABLE_LOGGING=${ENABLE_LOGGING:-true}
    
    read -p "Data Retention Days [90]: " RETENTION_DAYS
    RETENTION_DAYS=${RETENTION_DAYS:-90}
}

# Function to validate inputs
validate_inputs() {
    print_status "Validating inputs..."
    
    # Validate environment
    if [[ ! "$ENVIRONMENT" =~ ^(dev|test|prod|demo)$ ]]; then
        print_error "Environment must be one of: dev, test, prod, demo"
        exit 1
    fi
    
    # Validate SKU
    if [[ ! "$SKU" =~ ^(F0|S1)$ ]]; then
        print_error "SKU must be either F0 or S1"
        exit 1
    fi
    
    # Validate retention days
    if [[ ! "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || [ "$RETENTION_DAYS" -lt 30 ] || [ "$RETENTION_DAYS" -gt 2555 ]; then
        print_error "Data retention days must be between 30 and 2555"
        exit 1
    fi
    
    # Validate Health Bot name (must be globally unique)
    if [[ ${#HEALTHBOT_NAME} -lt 3 ]] || [[ ${#HEALTHBOT_NAME} -gt 64 ]]; then
        print_error "Health Bot name must be between 3 and 64 characters"
        exit 1
    fi
    
    print_success "Input validation completed"
}

# Function to create resource group if it doesn't exist
create_resource_group() {
    print_status "Checking if resource group exists..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_success "Resource group '$RESOURCE_GROUP' already exists"
    else
        print_status "Creating resource group '$RESOURCE_GROUP'..."
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=healthcare-chatbot environment="$ENVIRONMENT"
        print_success "Resource group created successfully"
    fi
}

# Function to deploy the template
deploy_template() {
    print_status "Starting Bicep template deployment..."
    
    # Validate template first
    print_status "Validating template syntax..."
    az deployment group validate \
        --resource-group "$RESOURCE_GROUP" \
        --template-file main.bicep \
        --parameters \
            healthBotName="$HEALTHBOT_NAME" \
            location="$LOCATION" \
            healthBotSku="$SKU" \
            environment="$ENVIRONMENT" \
            organizationName="$ORG_NAME" \
            enableAuditLogging="$ENABLE_LOGGING" \
            dataRetentionDays="$RETENTION_DAYS"
    
    print_success "Template validation passed"
    
    # Deploy the template
    print_status "Deploying Azure Health Bot infrastructure..."
    DEPLOYMENT_OUTPUT=$(az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --template-file main.bicep \
        --parameters \
            healthBotName="$HEALTHBOT_NAME" \
            location="$LOCATION" \
            healthBotSku="$SKU" \
            environment="$ENVIRONMENT" \
            organizationName="$ORG_NAME" \
            enableAuditLogging="$ENABLE_LOGGING" \
            dataRetentionDays="$RETENTION_DAYS" \
        --output json)
    
    if [ $? -eq 0 ]; then
        print_success "Deployment completed successfully!"
    else
        print_error "Deployment failed. Please check the error messages above."
        exit 1
    fi
}

# Function to display deployment outputs
show_outputs() {
    print_status "Retrieving deployment outputs..."
    
    # Get outputs from deployment
    OUTPUTS=$(az deployment group show \
        --resource-group "$RESOURCE_GROUP" \
        --name main \
        --query 'properties.outputs' \
        --output json)
    
    if [ $? -eq 0 ]; then
        echo ""
        print_success "=== DEPLOYMENT SUMMARY ==="
        
        # Extract specific outputs
        HEALTHBOT_ID=$(echo "$OUTPUTS" | jq -r '.healthBotId.value // "N/A"')
        MANAGEMENT_URL=$(echo "$OUTPUTS" | jq -r '.managementPortalUrl.value // "N/A"')
        WEBCHAT_URL=$(echo "$OUTPUTS" | jq -r '.webChatEndpoint.value // "N/A"')
        DEPLOYED_AT=$(echo "$OUTPUTS" | jq -r '.deployedAt.value // "N/A"')
        
        echo "Resource Group: $RESOURCE_GROUP"
        echo "Health Bot Name: $HEALTHBOT_NAME"
        echo "Location: $LOCATION"
        echo "SKU: $SKU"
        echo "Environment: $ENVIRONMENT"
        echo "Deployed At: $DEPLOYED_AT"
        echo ""
        print_success "=== IMPORTANT URLS ==="
        echo "Management Portal: $MANAGEMENT_URL"
        echo "Web Chat Endpoint: $WEBCHAT_URL"
        echo ""
        print_success "=== NEXT STEPS ==="
        echo "1. Access the Health Bot Management Portal using the URL above"
        echo "2. Configure healthcare scenarios (symptom checker, disease lookup, etc.)"
        echo "3. Enable web chat channel for website integration"
        echo "4. Review HIPAA compliance settings"
        echo "5. Test built-in medical scenarios"
        echo "6. Customize branding and welcome messages"
        echo ""
        print_warning "Save these URLs - you'll need them for configuration!"
    else
        print_error "Failed to retrieve deployment outputs"
    fi
}

# Function to estimate costs
show_cost_estimate() {
    print_status "Cost Estimation:"
    
    if [ "$SKU" = "F0" ]; then
        echo "SKU: F0 (Free Tier) - $0/month"
        print_warning "Free tier has transaction limits. Use S1 for production."
    else
        echo "SKU: S1 (Standard) - ~$500/month"
        print_status "Standard tier includes unlimited transactions for production use."
    fi
    
    if [ "$ENABLE_LOGGING" = "true" ]; then
        echo "Log Analytics & Application Insights: ~$5-50/month (depends on usage)"
        print_status "Monitoring costs depend on data ingestion volume."
    fi
}

# Main execution
main() {
    echo ""
    print_success "=== Azure Health Bot Deployment Script ==="
    echo ""
    
    # Parse command line arguments
    INTERACTIVE=true
    while [[ $# -gt 0 ]]; do
        case $1 in
            --non-interactive)
                INTERACTIVE=false
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--non-interactive] [--help]"
                echo ""
                echo "Options:"
                echo "  --non-interactive    Use default values without prompting"
                echo "  --help, -h          Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    set_defaults
    
    if [ "$INTERACTIVE" = "true" ]; then
        get_user_input
        validate_inputs
        
        # Show configuration summary
        echo ""
        print_status "=== DEPLOYMENT CONFIGURATION ==="
        echo "Resource Group: $RESOURCE_GROUP"
        echo "Location: $LOCATION"
        echo "Health Bot Name: $HEALTHBOT_NAME"
        echo "Environment: $ENVIRONMENT"
        echo "SKU: $SKU"
        echo "Organization: $ORG_NAME"
        echo "Audit Logging: $ENABLE_LOGGING"
        echo "Retention Days: $RETENTION_DAYS"
        echo ""
        
        show_cost_estimate
        echo ""
        
        read -p "Proceed with deployment? (y/N): " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            print_warning "Deployment cancelled by user"
            exit 0
        fi
    else
        # Use defaults for non-interactive mode
        RESOURCE_GROUP="$DEFAULT_RESOURCE_GROUP"
        LOCATION="$DEFAULT_LOCATION"
        HEALTHBOT_NAME="$DEFAULT_HEALTHBOT_NAME"
        ENVIRONMENT="$DEFAULT_ENVIRONMENT"
        SKU="$DEFAULT_SKU"
        ORG_NAME="$DEFAULT_ORG_NAME"
        ENABLE_LOGGING="true"
        RETENTION_DAYS="90"
        
        print_status "Running in non-interactive mode with default values"
    fi
    
    create_resource_group
    deploy_template
    show_outputs
    
    echo ""
    print_success "Azure Health Bot deployment completed successfully!"
    print_status "Check the management portal URL above to configure your healthcare chatbot."
}

# Run main function with all arguments
main "$@"