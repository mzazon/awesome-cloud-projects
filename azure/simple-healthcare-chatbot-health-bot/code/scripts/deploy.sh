#!/bin/bash

# Azure Health Bot Deployment Script
# This script deploys a Simple Healthcare Chatbot using Azure Health Bot service
# Generated for recipe: simple-healthcare-chatbot-health-bot

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Required for generating random suffixes."
        exit 1
    fi
    
    log "Prerequisites check completed successfully."
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-healthbot-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export HEALTH_BOT_NAME="healthbot-${RANDOM_SUFFIX}"
    
    # Validate subscription
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        error "Could not retrieve subscription ID. Please check your Azure login."
        exit 1
    fi
    
    info "Using Azure Subscription: $SUBSCRIPTION_ID"
    info "Resource Group: $RESOURCE_GROUP"
    info "Health Bot Name: $HEALTH_BOT_NAME"
    info "Location: $LOCATION"
    
    # Save variables to file for cleanup script
    cat > .deployment_vars << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
HEALTH_BOT_NAME=$HEALTH_BOT_NAME
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    log "Environment variables configured successfully."
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP already exists. Skipping creation."
        return 0
    fi
    
    # Create resource group
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=healthcare-chatbot environment=demo deployment=automated \
        --output table
    
    if [[ $? -eq 0 ]]; then
        log "✅ Resource group created successfully: $RESOURCE_GROUP"
    else
        error "Failed to create resource group: $RESOURCE_GROUP"
        exit 1
    fi
}

# Function to create Health Bot service
create_health_bot() {
    log "Creating Azure Health Bot service: $HEALTH_BOT_NAME"
    
    # Check if Health Bot already exists  
    if az healthbot show --name "$HEALTH_BOT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Health Bot $HEALTH_BOT_NAME already exists. Skipping creation."
        return 0
    fi
    
    # Create Health Bot service instance
    az healthbot create \
        --name "$HEALTH_BOT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku F0 \
        --tags environment=demo purpose=healthcare-chatbot deployment=automated \
        --output table
    
    if [[ $? -eq 0 ]]; then
        log "✅ Health Bot instance created successfully: $HEALTH_BOT_NAME"
        
        # Wait for deployment to complete
        log "Waiting for Health Bot deployment to complete..."
        local timeout=300  # 5 minutes timeout
        local elapsed=0
        local interval=10
        
        while [[ $elapsed -lt $timeout ]]; do
            local state=$(az healthbot show \
                --name "$HEALTH_BOT_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --query "properties.provisioningState" \
                --output tsv 2>/dev/null || echo "Unknown")
            
            if [[ "$state" == "Succeeded" ]]; then
                log "✅ Health Bot deployment completed successfully"
                break
            elif [[ "$state" == "Failed" ]]; then
                error "Health Bot deployment failed"
                exit 1
            fi
            
            info "Health Bot provisioning state: $state (waiting ${interval}s...)"
            sleep $interval
            elapsed=$((elapsed + interval))
        done
        
        if [[ $elapsed -ge $timeout ]]; then
            error "Health Bot deployment timed out after ${timeout} seconds"
            exit 1
        fi
    else
        error "Failed to create Health Bot service: $HEALTH_BOT_NAME"
        exit 1
    fi
}

# Function to configure Health Bot and display management information
configure_health_bot() {
    log "Configuring Health Bot management access..."
    
    # Get Health Bot management URL
    local management_url=$(az healthbot show \
        --name "$HEALTH_BOT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.botManagementPortalLink" \
        --output tsv 2>/dev/null)
    
    if [[ -n "$management_url" && "$management_url" != "null" ]]; then
        log "✅ Health Bot Management Portal URL: $management_url"
        
        # Save management URL to file
        echo "MANAGEMENT_URL=$management_url" >> .deployment_vars
        
        info "Access this URL to configure your Health Bot scenarios"
    else
        warn "Could not retrieve management portal URL. You can find it in the Azure portal."
    fi
    
    # Display Health Bot resource details
    log "Health Bot resource details:"
    az healthbot show \
        --name "$HEALTH_BOT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties" \
        --output table
    
    log "✅ Health Bot configured with built-in scenarios:"
    echo "   - Symptom checker and triage"
    echo "   - Disease information lookup" 
    echo "   - Medication guidance"
    echo "   - Doctor type recommendations"
}

# Function to display configuration instructions
display_configuration_instructions() {
    log "Health Bot Configuration Instructions:"
    
    if [[ -f .deployment_vars ]]; then
        source .deployment_vars
        if [[ -n "${MANAGEMENT_URL:-}" ]]; then
            echo ""
            echo "🔗 Management Portal: $MANAGEMENT_URL"
            echo ""
        fi
    fi
    
    echo "📋 Next Steps:"
    echo "1. Access the Management Portal using the URL above"
    echo "2. Navigate to Integration > Channels"
    echo "3. Enable Web Chat channel"
    echo "4. Configure channel settings for your organization"
    echo "5. Copy the embed code for your website"
    echo ""
    echo "🧪 Test your Health Bot with these sample queries:"
    echo "   - 'I have a headache' (symptom triage)"
    echo "   - 'What is diabetes?' (disease information)"
    echo "   - 'What doctor treats back pain?' (provider guidance)"
    echo "   - 'Help' (available commands)"
    echo ""
    echo "🔍 Access test interface at: Management Portal > Chat > Test in Portal"
}

# Function to display cost information
display_cost_information() {
    log "💰 Cost Information:"
    echo "   - Free tier (F0): No charge for testing and development"
    echo "   - Standard tier (S1): Starts at \$500/month for production use"
    echo "   - Monitor your Azure costs at: https://portal.azure.com/#view/Microsoft_Azure_CostManagement"
    echo ""
    warn "Remember to clean up resources when done testing to avoid unexpected charges."
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check Health Bot service status
    local provisioning_state=$(az healthbot show \
        --name "$HEALTH_BOT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.provisioningState" \
        --output tsv 2>/dev/null)
    
    if [[ "$provisioning_state" == "Succeeded" ]]; then
        log "✅ Health Bot service is running successfully"
    else
        error "Health Bot deployment validation failed. State: $provisioning_state"
        exit 1
    fi
    
    # Verify resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "✅ Resource group exists and is accessible"
    else
        error "Resource group validation failed"
        exit 1
    fi
    
    log "✅ Deployment validation completed successfully"
}

# Main deployment function
main() {
    log "Starting Azure Health Bot deployment..."
    log "Recipe: Simple Healthcare Chatbot with Azure Health Bot"
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_health_bot
    configure_health_bot
    validate_deployment
    
    log "🎉 Deployment completed successfully!"
    echo ""
    
    display_configuration_instructions
    display_cost_information
    
    log "Deployment details saved to .deployment_vars"
    log "Use ./destroy.sh to clean up resources when done."
}

# Handle script interruption
cleanup_on_error() {
    error "Script interrupted. Some resources may have been created."
    error "Check the Azure portal and run ./destroy.sh if needed."
    exit 1
}

trap cleanup_on_error INT TERM

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi