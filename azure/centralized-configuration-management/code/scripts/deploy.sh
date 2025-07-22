#!/bin/bash

# Deploy script for Azure App Configuration and Key Vault recipe
# This script implements centralized application configuration management
# with Azure App Configuration and Azure Key Vault integration

set -euo pipefail

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

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

if [[ "$DRY_RUN" == "true" ]]; then
    warning "Running in DRY RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    info "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: $cmd"
        return 0
    else
        eval "$cmd"
    fi
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    if [[ -n "${RESOURCE_GROUP:-}" ]] && [[ "$DRY_RUN" != "true" ]]; then
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true
    fi
    exit 1
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    log "All prerequisites met ✅"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    # Set Azure subscription and location
    export LOCATION=${LOCATION:-"eastus"}
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names with unique suffixes
    export RESOURCE_GROUP="rg-config-mgmt-${RANDOM_SUFFIX}"
    export APP_CONFIG_NAME="ac-config-${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-secrets-${RANDOM_SUFFIX}"
    export WEB_APP_NAME="wa-demo-${RANDOM_SUFFIX}"
    export APP_SERVICE_PLAN="asp-demo-${RANDOM_SUFFIX}"
    
    info "Configuration values:"
    info "  Location: ${LOCATION}"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  App Configuration: ${APP_CONFIG_NAME}"
    info "  Key Vault: ${KEY_VAULT_NAME}"
    info "  Web App: ${WEB_APP_NAME}"
    info "  App Service Plan: ${APP_SERVICE_PLAN}"
    
    # Save configuration to file for cleanup script
    cat > .deployment_config << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
APP_CONFIG_NAME=${APP_CONFIG_NAME}
KEY_VAULT_NAME=${KEY_VAULT_NAME}
WEB_APP_NAME=${WEB_APP_NAME}
APP_SERVICE_PLAN=${APP_SERVICE_PLAN}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
EOF
    
    log "Environment variables configured ✅"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    execute_command "az group create \
        --name ${RESOURCE_GROUP} \
        --location ${LOCATION} \
        --tags purpose=recipe environment=demo recipe=config-management" \
        "Creating resource group ${RESOURCE_GROUP}"
    
    log "Resource group created ✅"
}

# Function to create App Configuration store
create_app_configuration() {
    log "Creating Azure App Configuration store..."
    
    execute_command "az appconfig create \
        --name ${APP_CONFIG_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --location ${LOCATION} \
        --sku Standard \
        --tags environment=demo purpose=configuration" \
        "Creating App Configuration store ${APP_CONFIG_NAME}"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Get App Configuration endpoint
        export APP_CONFIG_ENDPOINT=$(az appconfig show \
            --name ${APP_CONFIG_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --query endpoint --output tsv)
        
        info "App Configuration endpoint: ${APP_CONFIG_ENDPOINT}"
        
        # Save endpoint to config file
        echo "APP_CONFIG_ENDPOINT=${APP_CONFIG_ENDPOINT}" >> .deployment_config
    fi
    
    log "App Configuration store created ✅"
}

# Function to create Key Vault
create_key_vault() {
    log "Creating Azure Key Vault..."
    
    execute_command "az keyvault create \
        --name ${KEY_VAULT_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --location ${LOCATION} \
        --sku Standard \
        --enable-soft-delete true \
        --retention-days 7 \
        --tags environment=demo purpose=secrets" \
        "Creating Key Vault ${KEY_VAULT_NAME}"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Get current user object ID for Key Vault permissions
        export USER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)
        
        # Grant current user full access to Key Vault secrets
        execute_command "az keyvault set-policy \
            --name ${KEY_VAULT_NAME} \
            --object-id ${USER_OBJECT_ID} \
            --secret-permissions all" \
            "Granting user permissions to Key Vault"
    fi
    
    log "Key Vault created ✅"
}

# Function to create configuration settings and secrets
create_configuration_data() {
    log "Creating sample configuration settings and secrets..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Add application settings to App Configuration
        execute_command "az appconfig kv set \
            --name ${APP_CONFIG_NAME} \
            --key \"App:Name\" \
            --value \"Demo Configuration App\" \
            --label \"Production\"" \
            "Adding App:Name configuration"
        
        execute_command "az appconfig kv set \
            --name ${APP_CONFIG_NAME} \
            --key \"App:Version\" \
            --value \"1.0.0\" \
            --label \"Production\"" \
            "Adding App:Version configuration"
        
        execute_command "az appconfig kv set \
            --name ${APP_CONFIG_NAME} \
            --key \"Features:EnableLogging\" \
            --value \"true\" \
            --label \"Production\"" \
            "Adding Features:EnableLogging configuration"
        
        # Create a feature flag for A/B testing
        execute_command "az appconfig feature set \
            --name ${APP_CONFIG_NAME} \
            --feature \"BetaFeatures\" \
            --label \"Production\" \
            --yes" \
            "Creating BetaFeatures feature flag"
        
        # Add secrets to Key Vault
        execute_command "az keyvault secret set \
            --vault-name ${KEY_VAULT_NAME} \
            --name \"DatabaseConnection\" \
            --value \"Server=db.example.com;Database=prod;Uid=admin;Pwd=SecureP@ssw0rd123;\"" \
            "Adding database connection secret"
        
        execute_command "az keyvault secret set \
            --vault-name ${KEY_VAULT_NAME} \
            --name \"ApiKey\" \
            --value \"sk-1234567890abcdef1234567890abcdef\"" \
            "Adding API key secret"
    fi
    
    log "Configuration settings and secrets created ✅"
}

# Function to create App Service Plan and Web App
create_web_app() {
    log "Creating App Service Plan and Web App..."
    
    execute_command "az appservice plan create \
        --name ${APP_SERVICE_PLAN} \
        --resource-group ${RESOURCE_GROUP} \
        --location ${LOCATION} \
        --sku B1 \
        --is-linux \
        --tags environment=demo purpose=hosting" \
        "Creating App Service Plan ${APP_SERVICE_PLAN}"
    
    execute_command "az webapp create \
        --name ${WEB_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --plan ${APP_SERVICE_PLAN} \
        --runtime \"NODE:18-lts\" \
        --tags environment=demo purpose=application" \
        "Creating Web App ${WEB_APP_NAME}"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        info "Web App URL: https://${WEB_APP_NAME}.azurewebsites.net"
    fi
    
    log "Web App created ✅"
}

# Function to enable managed identity
enable_managed_identity() {
    log "Enabling managed identity for Web App..."
    
    execute_command "az webapp identity assign \
        --name ${WEB_APP_NAME} \
        --resource-group ${RESOURCE_GROUP}" \
        "Enabling system-assigned managed identity"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Get the managed identity object ID
        export WEBAPP_IDENTITY=$(az webapp identity show \
            --name ${WEB_APP_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --query principalId --output tsv)
        
        info "Managed identity Object ID: ${WEBAPP_IDENTITY}"
        
        # Save identity to config file
        echo "WEBAPP_IDENTITY=${WEBAPP_IDENTITY}" >> .deployment_config
    fi
    
    log "Managed identity enabled ✅"
}

# Function to grant permissions
grant_permissions() {
    log "Granting permissions to Web App managed identity..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Grant App Configuration Data Reader role to Web App identity
        execute_command "az role assignment create \
            --assignee ${WEBAPP_IDENTITY} \
            --role \"App Configuration Data Reader\" \
            --scope \"/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.AppConfiguration/configurationStores/${APP_CONFIG_NAME}\"" \
            "Granting App Configuration Data Reader role"
        
        # Grant Key Vault Secrets User role to Web App identity
        execute_command "az keyvault set-policy \
            --name ${KEY_VAULT_NAME} \
            --object-id ${WEBAPP_IDENTITY} \
            --secret-permissions get list" \
            "Granting Key Vault secret permissions"
    fi
    
    log "Permissions granted ✅"
}

# Function to configure Web App settings
configure_web_app_settings() {
    log "Configuring Web App settings with configuration references..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Configure App Configuration connection
        execute_command "az webapp config appsettings set \
            --name ${WEB_APP_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --settings \"AZURE_APP_CONFIG_ENDPOINT=${APP_CONFIG_ENDPOINT}\"" \
            "Configuring App Configuration endpoint"
        
        # Add Key Vault references as application settings
        execute_command "az webapp config appsettings set \
            --name ${WEB_APP_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --settings \"DATABASE_CONNECTION=@Microsoft.KeyVault(VaultName=${KEY_VAULT_NAME};SecretName=DatabaseConnection)\"" \
            "Configuring database connection reference"
        
        execute_command "az webapp config appsettings set \
            --name ${WEB_APP_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --settings \"API_KEY=@Microsoft.KeyVault(VaultName=${KEY_VAULT_NAME};SecretName=ApiKey)\"" \
            "Configuring API key reference"
    fi
    
    log "Web App settings configured ✅"
}

# Function to deploy demo application
deploy_demo_application() {
    log "Deploying demo application..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Create temporary directory for application files
        TEMP_DIR=$(mktemp -d)
        
        # Create demo application
        cat > "${TEMP_DIR}/app.js" << 'EOF'
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
    const config = {
        appConfigEndpoint: process.env.AZURE_APP_CONFIG_ENDPOINT || 'Not configured',
        databaseConnection: process.env.DATABASE_CONNECTION ? 'Configured (hidden)' : 'Not configured',
        apiKey: process.env.API_KEY ? 'Configured (hidden)' : 'Not configured',
        timestamp: new Date().toISOString()
    };
    
    res.json({
        message: 'Centralized Configuration Demo',
        configuration: config,
        status: 'success'
    });
});

app.listen(port, () => {
    console.log(`App listening at port ${port}`);
});
EOF
        
        # Create package.json
        cat > "${TEMP_DIR}/package.json" << 'EOF'
{
    "name": "config-demo",
    "version": "1.0.0",
    "main": "app.js",
    "dependencies": {
        "express": "^4.18.0"
    },
    "scripts": {
        "start": "node app.js"
    }
}
EOF
        
        # Create zip file for deployment
        cd "${TEMP_DIR}"
        zip -r app.zip app.js package.json
        
        # Deploy the application
        execute_command "az webapp deploy \
            --name ${WEB_APP_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --src-path app.zip \
            --type zip" \
            "Deploying application to Web App"
        
        # Clean up temporary files
        cd - > /dev/null
        rm -rf "${TEMP_DIR}"
    fi
    
    log "Demo application deployed ✅"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Wait for application to be ready
        sleep 30
        
        # Test the deployed application
        info "Testing deployed application..."
        RESPONSE=$(curl -s "https://${WEB_APP_NAME}.azurewebsites.net" || echo "")
        
        if [[ -n "$RESPONSE" ]]; then
            echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
            log "Application is responding ✅"
        else
            warning "Application may not be fully ready yet. Please check manually."
        fi
        
        # Verify configuration settings
        info "Verifying App Configuration settings..."
        az appconfig kv list \
            --name ${APP_CONFIG_NAME} \
            --label "Production" \
            --query "[].{Key:key, Value:value}" \
            --output table
        
        # Verify feature flags
        info "Verifying feature flags..."
        az appconfig feature show \
            --name ${APP_CONFIG_NAME} \
            --feature "BetaFeatures" \
            --label "Production" \
            --query "{Feature:key, Enabled:enabled}" \
            --output table
        
        # Verify Key Vault secrets (without revealing values)
        info "Verifying Key Vault secrets..."
        az keyvault secret list \
            --vault-name ${KEY_VAULT_NAME} \
            --query "[].{Name:name, Enabled:attributes.enabled}" \
            --output table
    fi
    
    log "Deployment validation completed ✅"
}

# Main deployment function
main() {
    log "Starting Azure App Configuration and Key Vault deployment..."
    log "=========================================================="
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_app_configuration
    create_key_vault
    create_configuration_data
    create_web_app
    enable_managed_identity
    grant_permissions
    configure_web_app_settings
    deploy_demo_application
    validate_deployment
    
    log "=========================================================="
    log "Deployment completed successfully! 🎉"
    log "=========================================================="
    
    if [[ "$DRY_RUN" != "true" ]]; then
        info "Resources created:"
        info "  Resource Group: ${RESOURCE_GROUP}"
        info "  App Configuration: ${APP_CONFIG_NAME}"
        info "  Key Vault: ${KEY_VAULT_NAME}"
        info "  Web App: ${WEB_APP_NAME}"
        info "  Web App URL: https://${WEB_APP_NAME}.azurewebsites.net"
        info ""
        info "Configuration file saved as: .deployment_config"
        info "Use this file with destroy.sh to clean up resources."
    fi
}

# Run main function
main "$@"