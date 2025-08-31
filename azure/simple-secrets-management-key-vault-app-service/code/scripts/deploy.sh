#!/bin/bash

# Azure Key Vault and App Service Deployment Script
# This script deploys the infrastructure for simple secrets management
# using Azure Key Vault and App Service with managed identity

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required tools are available
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is required but not installed."
        exit 1
    fi
    
    if ! command -v zip &> /dev/null; then
        log_error "zip command is required but not installed."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
set_environment_variables() {
    log_info "Setting environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-secrets-demo-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names with unique suffix
    export KEY_VAULT_NAME="kv-secrets-${RANDOM_SUFFIX}"
    export APP_SERVICE_PLAN="asp-secrets-${RANDOM_SUFFIX}"
    export WEB_APP_NAME="webapp-secrets-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  Key Vault: ${KEY_VAULT_NAME}"
    log_info "  Web App: ${WEB_APP_NAME}"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group..."
    
    # Check if resource group already exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
        return 0
    fi
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=secrets-demo environment=tutorial
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

# Function to create Key Vault
create_key_vault() {
    log_info "Creating Azure Key Vault..."
    
    # Check if Key Vault already exists
    if az keyvault show --name "${KEY_VAULT_NAME}" &> /dev/null; then
        log_warning "Key Vault ${KEY_VAULT_NAME} already exists"
        return 0
    fi
    
    az keyvault create \
        --name "${KEY_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku standard \
        --enable-rbac-authorization true \
        --tags purpose=secrets-demo
    
    log_success "Key Vault created: ${KEY_VAULT_NAME}"
}

# Function to add secrets to Key Vault
add_secrets_to_keyvault() {
    log_info "Adding sample secrets to Key Vault..."
    
    # Get current user ID for RBAC role assignment
    CURRENT_USER_ID=$(az ad signed-in-user show --query id --output tsv)
    
    # Check if role assignment already exists
    if ! az role assignment list \
        --assignee "${CURRENT_USER_ID}" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" \
        --role "Key Vault Secrets Officer" \
        --query "[0].id" -o tsv &> /dev/null; then
        
        log_info "Assigning Key Vault Secrets Officer role to current user..."
        az role assignment create \
            --role "Key Vault Secrets Officer" \
            --assignee "${CURRENT_USER_ID}" \
            --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}"
        
        # Wait for role assignment propagation
        log_info "Waiting for role assignment propagation..."
        sleep 30
    else
        log_info "Key Vault Secrets Officer role already assigned"
    fi
    
    # Add sample database connection string
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "DatabaseConnection" \
        --value "Server=myserver.database.windows.net;Database=mydb;User=admin;Password=SecureP@ssw0rd123" \
        > /dev/null
    
    # Add sample API key
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "ExternalApiKey" \
        --value "sk-1234567890abcdef1234567890abcdef" \
        > /dev/null
    
    log_success "Sample secrets added to Key Vault"
}

# Function to create App Service resources
create_app_service() {
    log_info "Creating App Service Plan and Web Application..."
    
    # Create App Service Plan
    if ! az appservice plan show --name "${APP_SERVICE_PLAN}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Creating App Service Plan..."
        az appservice plan create \
            --name "${APP_SERVICE_PLAN}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku B1 \
            --is-linux true \
            > /dev/null
        log_success "App Service Plan created: ${APP_SERVICE_PLAN}"
    else
        log_warning "App Service Plan ${APP_SERVICE_PLAN} already exists"
    fi
    
    # Create Web App
    if ! az webapp show --name "${WEB_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Creating Web App..."
        az webapp create \
            --name "${WEB_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --plan "${APP_SERVICE_PLAN}" \
            --runtime "NODE:18-lts" \
            > /dev/null
        log_success "Web application created: ${WEB_APP_NAME}"
    else
        log_warning "Web App ${WEB_APP_NAME} already exists"
    fi
}

# Function to enable managed identity
enable_managed_identity() {
    log_info "Enabling system-assigned managed identity..."
    
    # Enable system-assigned managed identity for the web app
    az webapp identity assign \
        --name "${WEB_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        > /dev/null
    
    # Get the managed identity principal ID
    MANAGED_IDENTITY_ID=$(az webapp identity show \
        --name "${WEB_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query principalId \
        --output tsv)
    
    export MANAGED_IDENTITY_ID
    log_success "Managed identity enabled with ID: ${MANAGED_IDENTITY_ID}"
}

# Function to grant Key Vault access
grant_keyvault_access() {
    log_info "Granting Key Vault access to managed identity..."
    
    # Check if role assignment already exists
    if ! az role assignment list \
        --assignee "${MANAGED_IDENTITY_ID}" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" \
        --role "Key Vault Secrets User" \
        --query "[0].id" -o tsv &> /dev/null; then
        
        # Assign Key Vault Secrets User role to the managed identity
        az role assignment create \
            --role "Key Vault Secrets User" \
            --assignee "${MANAGED_IDENTITY_ID}" \
            --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" \
            > /dev/null
        
        # Wait for role assignment propagation
        log_info "Waiting for role assignment propagation..."
        sleep 30
        
        log_success "Key Vault access granted to managed identity"
    else
        log_info "Key Vault access already granted to managed identity"
    fi
}

# Function to configure Key Vault references
configure_keyvault_references() {
    log_info "Configuring Key Vault references in app settings..."
    
    # Configure Key Vault references as app settings
    az webapp config appsettings set \
        --name "${WEB_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "DATABASE_CONNECTION=@Microsoft.KeyVault(VaultName=${KEY_VAULT_NAME};SecretName=DatabaseConnection)" \
        "API_KEY=@Microsoft.KeyVault(VaultName=${KEY_VAULT_NAME};SecretName=ExternalApiKey)" \
        > /dev/null
    
    log_success "Key Vault references configured in app settings"
}

# Function to create and deploy sample application
deploy_sample_application() {
    log_info "Creating and deploying sample application..."
    
    # Create temporary directory for app files
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Create sample Node.js application
    cat > app.js << 'EOF'
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
    const html = `
    <html>
    <head><title>Secrets Demo</title></head>
    <body>
        <h1>🔐 Azure Key Vault Secrets Demo</h1>
        <h2>Configuration Status:</h2>
        <ul>
            <li><strong>Database Connection:</strong> ${process.env.DATABASE_CONNECTION ? '✅ Retrieved from Key Vault' : '❌ Not configured'}</li>
            <li><strong>API Key:</strong> ${process.env.API_KEY ? '✅ Retrieved from Key Vault' : '❌ Not configured'}</li>
        </ul>
        <p><em>Secrets are retrieved securely using Managed Identity</em></p>
    </body>
    </html>
    `;
    res.send(html);
});

app.listen(port, () => {
    console.log(`Server running on port ${port}`);
});
EOF

    # Create package.json
    cat > package.json << 'EOF'
{
    "name": "secrets-demo",
    "version": "1.0.0",
    "description": "Azure Key Vault secrets demo",
    "main": "app.js",
    "scripts": {
        "start": "node app.js"
    },
    "dependencies": {
        "express": "^4.18.0"
    }
}
EOF

    # Create deployment package
    zip -q -r app.zip app.js package.json
    
    # Deploy application
    az webapp deploy \
        --name "${WEB_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --src-path app.zip \
        --type zip \
        > /dev/null
    
    # Clean up temporary files
    cd - > /dev/null
    rm -rf "${TEMP_DIR}"
    
    log_success "Sample application deployed successfully"
}

# Function to display deployment results
display_results() {
    log_success "Deployment completed successfully!"
    echo ""
    log_info "Deployment Summary:"
    log_info "==================="
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Key Vault: ${KEY_VAULT_NAME}"
    log_info "Web App: ${WEB_APP_NAME}"
    echo ""
    
    # Get web app URL
    APP_URL=$(az webapp show \
        --name "${WEB_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query defaultHostName \
        --output tsv)
    
    log_info "🌐 Access your application at: https://${APP_URL}"
    echo ""
    log_info "To test the deployment:"
    log_info "1. Visit the application URL above"
    log_info "2. Verify that secrets are retrieved from Key Vault"
    log_info "3. Check Azure portal for resources"
    echo ""
    log_warning "Remember to run './destroy.sh' to clean up resources when done!"
}

# Function to save environment variables for cleanup
save_environment() {
    log_info "Saving environment variables for cleanup..."
    
    cat > .deploy_env << EOF
export RESOURCE_GROUP="${RESOURCE_GROUP}"
export KEY_VAULT_NAME="${KEY_VAULT_NAME}"
export WEB_APP_NAME="${WEB_APP_NAME}"
export APP_SERVICE_PLAN="${APP_SERVICE_PLAN}"
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
EOF
    
    log_success "Environment variables saved to .deploy_env"
}

# Main deployment function
main() {
    log_info "Starting Azure Key Vault and App Service deployment..."
    echo ""
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_key_vault
    add_secrets_to_keyvault
    create_app_service
    enable_managed_identity
    grant_keyvault_access
    configure_keyvault_references
    deploy_sample_application
    save_environment
    display_results
    
    log_success "All deployment steps completed successfully!"
}

# Run main function with error handling
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Trap errors and provide cleanup information
    trap 'log_error "Deployment failed. You may need to clean up partially created resources."' ERR
    
    main "$@"
fi