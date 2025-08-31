#!/bin/bash

# Azure Simple Email Notifications Deployment Script
# This script deploys Azure Communication Services and Functions for email notifications
# Author: Recipe Generator
# Version: 1.0

set -euo pipefail

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partial resources..."
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait 2>/dev/null || true
    fi
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites check function
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error_exit "You are not logged into Azure. Please run 'az login' first."
    fi
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        error_exit "Node.js is not installed. Please install Node.js 18+ from: https://nodejs.org"
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ ${NODE_VERSION} -lt 18 ]]; then
        error_exit "Node.js version 18 or higher is required. Current version: $(node --version)"
    fi
    
    # Check if zip command is available
    if ! command -v zip &> /dev/null; then
        error_exit "zip command is not available. Please install zip utility."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl command is not available. Please install openssl."
    fi
    
    log_success "All prerequisites met"
}

# Function to validate Azure subscription and permissions
validate_azure_access() {
    log_info "Validating Azure access and permissions..."
    
    # Get current subscription
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    
    log_info "Using subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
    
    # Check if we can create resource groups
    if ! az provider show --namespace Microsoft.Resources &> /dev/null; then
        error_exit "Cannot access Microsoft.Resources provider. Check your subscription permissions."
    fi
    
    # Check required resource providers
    local required_providers=(
        "Microsoft.Communication"
        "Microsoft.Web"
        "Microsoft.Storage"
    )
    
    for provider in "${required_providers[@]}"; do
        log_info "Checking provider: ${provider}"
        if ! az provider show --namespace "${provider}" --query "registrationState" --output tsv | grep -q "Registered"; then
            log_warning "Provider ${provider} is not registered. Registering..."
            az provider register --namespace "${provider}" --wait
        fi
    done
    
    log_success "Azure access validated"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values
    export LOCATION="${LOCATION:-eastus}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set specific resource names
    export RESOURCE_GROUP="rg-email-notifications-${RANDOM_SUFFIX}"
    export COMMUNICATION_SERVICE="cs-email-${RANDOM_SUFFIX}"
    export EMAIL_SERVICE="email-service-${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-email-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stemail${RANDOM_SUFFIX}"
    
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Function App: ${FUNCTION_APP}"
    
    log_success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=recipe environment=demo \
            --output table
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create Communication Services
create_communication_services() {
    log_info "Creating Azure Communication Services resource..."
    
    # Create Communication Services resource
    az communication create \
        --name "${COMMUNICATION_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "Global" \
        --data-location "United States" \
        --output table
    
    # Get the connection string for the Communication Services resource
    COMMUNICATION_CONNECTION_STRING=$(az communication list-key \
        --name "${COMMUNICATION_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query primaryConnectionString \
        --output tsv)
    
    if [[ -z "${COMMUNICATION_CONNECTION_STRING}" ]]; then
        error_exit "Failed to retrieve Communication Services connection string"
    fi
    
    log_success "Communication Services resource created: ${COMMUNICATION_SERVICE}"
}

# Function to create Email Communication Service
create_email_service() {
    log_info "Creating Email Communication Service with managed domain..."
    
    # Create Email Communication Service
    az communication email create \
        --name "${EMAIL_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "Global" \
        --data-location "United States" \
        --output table
    
    # Add Azure managed domain to email service
    az communication email domain create \
        --domain-name AzureManagedDomain \
        --email-service-name "${EMAIL_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "Global" \
        --domain-management AzureManaged \
        --output table
    
    # Get the managed domain details for sender address
    SENDER_DOMAIN=$(az communication email domain show \
        --domain-name AzureManagedDomain \
        --email-service-name "${EMAIL_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query fromSenderDomain \
        --output tsv)
    
    # Link the email service to communication services
    az communication email domain update \
        --domain-name AzureManagedDomain \
        --email-service-name "${EMAIL_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --add "linked-domains=${COMMUNICATION_SERVICE}" \
        --output table
    
    log_success "Email service created with managed domain: ${SENDER_DOMAIN}"
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account for Function App..."
    
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --output table
    
    log_success "Storage account created: ${STORAGE_ACCOUNT}"
}

# Function to create Function App
create_function_app() {
    log_info "Creating Function App with Node.js runtime..."
    
    # Create Function App
    az functionapp create \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime node \
        --runtime-version 18 \
        --functions-version 4 \
        --os-type Linux \
        --output table
    
    # Configure application settings for Communication Services
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "COMMUNICATION_SERVICES_CONNECTION_STRING=${COMMUNICATION_CONNECTION_STRING}" \
        "SENDER_ADDRESS=donotreply@${SENDER_DOMAIN}" \
        --output table
    
    log_success "Function App created and configured: ${FUNCTION_APP}"
}

# Function to create and deploy function code
deploy_function_code() {
    log_info "Creating and deploying function code..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Create host.json for Function App configuration
    cat > host.json << 'EOF'
{
  "version": "2.0",
  "functionTimeout": "00:05:00",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true
      }
    }
  }
}
EOF
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "email-notification-function",
  "version": "1.0.0",
  "description": "Azure Function for sending email notifications",
  "main": "index.js",
  "scripts": {
    "start": "func start"
  },
  "dependencies": {
    "@azure/communication-email": "^1.0.0",
    "@azure/functions": "^4.0.0"
  }
}
EOF
    
    # Create function directory and configuration
    mkdir -p SendEmail
    cd SendEmail
    
    cat > function.json << 'EOF'
{
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["post"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    }
  ]
}
EOF
    
    # Create function implementation
    cat > index.js << 'EOF'
const { EmailClient } = require("@azure/communication-email");

module.exports = async function (context, req) {
    context.log('Email notification function triggered');

    // Validate request body
    const { to, subject, body } = req.body || {};
    
    if (!to || !subject || !body) {
        context.res = {
            status: 400,
            body: {
                error: "Missing required fields: to, subject, body"
            }
        };
        return;
    }

    try {
        // Initialize email client
        const emailClient = new EmailClient(
            process.env.COMMUNICATION_SERVICES_CONNECTION_STRING
        );

        // Prepare email message
        const emailMessage = {
            senderAddress: process.env.SENDER_ADDRESS,
            content: {
                subject: subject,
                plainText: body
            },
            recipients: {
                to: [{ address: to }]
            }
        };

        // Send email
        const poller = await emailClient.beginSend(emailMessage);
        const response = await poller.pollUntilDone();

        context.log(`Email sent successfully. Message ID: ${response.id}`);

        context.res = {
            status: 200,
            body: {
                message: "Email sent successfully",
                messageId: response.id,
                status: response.status
            }
        };

    } catch (error) {
        context.log.error('Error sending email:', error);

        context.res = {
            status: 500,
            body: {
                error: "Failed to send email",
                details: error.message
            }
        };
    }
};
EOF
    
    cd ..
    
    # Create deployment package
    log_info "Creating deployment package..."
    zip -r function-deployment.zip . --exclude "node_modules/*" ".git/*"
    
    # Deploy function code
    log_info "Deploying function to Azure..."
    az functionapp deployment source config-zip \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --src function-deployment.zip \
        --output table
    
    # Wait for deployment to complete
    log_info "Waiting for deployment to complete..."
    sleep 45
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "${TEMP_DIR}"
    
    log_success "Function code deployed successfully"
}

# Function to get function URL and test
get_function_info() {
    log_info "Retrieving function information..."
    
    # Get function URL with access key
    FUNCTION_KEY=$(az functionapp keys list \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query functionKeys.default \
        --output tsv 2>/dev/null || \
        az functionapp function keys list \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --function-name SendEmail \
            --query default \
            --output tsv 2>/dev/null)
    
    FUNCTION_URL="https://${FUNCTION_APP}.azurewebsites.net/api/SendEmail?code=${FUNCTION_KEY}"
    
    log_success "Function deployed and accessible at: ${FUNCTION_URL}"
    
    # Save deployment information
    cat > deployment-info.txt << EOF
Deployment Information:
======================
Resource Group: ${RESOURCE_GROUP}
Location: ${LOCATION}
Communication Service: ${COMMUNICATION_SERVICE}
Email Service: ${EMAIL_SERVICE}
Function App: ${FUNCTION_APP}
Storage Account: ${STORAGE_ACCOUNT}
Sender Domain: ${SENDER_DOMAIN}
Function URL: ${FUNCTION_URL}

To test the function, use:
curl -X POST "${FUNCTION_URL}" \\
    -H "Content-Type: application/json" \\
    -d '{
        "to": "your-email@example.com",
        "subject": "Test Email from Azure Functions",
        "body": "This is a test email sent from Azure Functions using Communication Services."
    }'
EOF
    
    log_success "Deployment information saved to: deployment-info.txt"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check if all resources exist
    local resources_ok=true
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Resource group ${RESOURCE_GROUP} not found"
        resources_ok=false
    fi
    
    if ! az communication show --name "${COMMUNICATION_SERVICE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Communication Service ${COMMUNICATION_SERVICE} not found"
        resources_ok=false
    fi
    
    if ! az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Function App ${FUNCTION_APP} not found"
        resources_ok=false
    fi
    
    if ! az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Storage Account ${STORAGE_ACCOUNT} not found"
        resources_ok=false
    fi
    
    if [[ "${resources_ok}" == "true" ]]; then
        log_success "All resources deployed successfully"
    else
        error_exit "Deployment validation failed"
    fi
}

# Main deployment function
main() {
    log_info "Starting Azure Simple Email Notifications deployment..."
    
    check_prerequisites
    validate_azure_access
    setup_environment
    create_resource_group
    create_communication_services
    create_email_service
    create_storage_account
    create_function_app
    deploy_function_code
    get_function_info
    validate_deployment
    
    log_success "Deployment completed successfully!"
    log_info "Check deployment-info.txt for connection details and testing instructions"
}

# Run main function with all arguments
main "$@"