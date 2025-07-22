#!/bin/bash

# Deploy script for Real-Time Collaborative Applications with Azure Communication Services and Azure Fluid Relay
# This script deploys the complete infrastructure for a collaborative whiteboard application

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${2:-$GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    log "$1" "$RED"
    exit 1
}

warn() {
    log "$1" "$YELLOW"
}

info() {
    log "$1" "$BLUE"
}

success() {
    log "$1" "$GREEN"
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Please login to Azure using 'az login' first."
    fi
    
    # Check required utilities
    local required_tools=("curl" "openssl" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is not installed. Please install it first."
        fi
    done
    
    # Check Node.js (for Function deployment)
    if ! command -v node &> /dev/null; then
        warn "Node.js is not installed. Function deployment may fail."
    else
        local node_version=$(node --version)
        info "Node.js version: $node_version"
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    info "Setting environment variables..."
    
    # Generate unique suffix
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set core variables
    export RESOURCE_GROUP="rg-collab-app-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names
    export ACS_NAME="acs-collab-${RANDOM_SUFFIX}"
    export FLUID_NAME="fluid-collab-${RANDOM_SUFFIX}"
    export FUNC_NAME="func-collab-${RANDOM_SUFFIX}"
    export STORAGE_NAME="stcollab${RANDOM_SUFFIX}"
    export KV_NAME="kv-collab-${RANDOM_SUFFIX}"
    
    # Save state for cleanup
    cat > "$DEPLOYMENT_STATE_FILE" << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
ACS_NAME=${ACS_NAME}
FLUID_NAME=${FLUID_NAME}
FUNC_NAME=${FUNC_NAME}
STORAGE_NAME=${STORAGE_NAME}
KV_NAME=${KV_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables set with suffix: ${RANDOM_SUFFIX}"
}

# Function to create resource group
create_resource_group() {
    info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags environment=demo purpose=collaboration \
            --output none
        
        success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create Azure Communication Services
create_acs_resource() {
    info "Creating Azure Communication Services resource: ${ACS_NAME}"
    
    # Check if ACS resource exists
    if az communication show --name "${ACS_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "ACS resource ${ACS_NAME} already exists"
    else
        az communication create \
            --name "${ACS_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location global \
            --data-location unitedstates \
            --output none
        
        success "ACS resource created: ${ACS_NAME}"
    fi
    
    # Get connection string
    export ACS_CONNECTION=$(az communication show \
        --name "${ACS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString \
        --output tsv)
    
    if [ -z "$ACS_CONNECTION" ]; then
        error "Failed to retrieve ACS connection string"
    fi
    
    success "ACS connection string retrieved"
}

# Function to create Fluid Relay service
create_fluid_relay() {
    info "Creating Azure Fluid Relay service: ${FLUID_NAME}"
    
    # Check if Fluid Relay exists
    if az fluid-relay server show --name "${FLUID_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Fluid Relay service ${FLUID_NAME} already exists"
    else
        az fluid-relay server create \
            --name "${FLUID_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku basic \
            --output none
        
        success "Fluid Relay service created: ${FLUID_NAME}"
    fi
    
    # Get Fluid Relay endpoints
    export FLUID_ENDPOINT=$(az fluid-relay server show \
        --name "${FLUID_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query fluidRelayEndpoints.ordererEndpoints[0] \
        --output tsv)
    
    export FLUID_TENANT=$(az fluid-relay server show \
        --name "${FLUID_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query frsTenantId \
        --output tsv)
    
    if [ -z "$FLUID_ENDPOINT" ] || [ -z "$FLUID_TENANT" ]; then
        error "Failed to retrieve Fluid Relay configuration"
    fi
    
    success "Fluid Relay service configured - Endpoint: ${FLUID_ENDPOINT}"
}

# Function to create Key Vault
create_key_vault() {
    info "Creating Azure Key Vault: ${KV_NAME}"
    
    # Check if Key Vault exists
    if az keyvault show --name "${KV_NAME}" &> /dev/null; then
        warn "Key Vault ${KV_NAME} already exists"
    else
        az keyvault create \
            --name "${KV_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku standard \
            --output none
        
        success "Key Vault created: ${KV_NAME}"
    fi
    
    # Store ACS connection string
    az keyvault secret set \
        --vault-name "${KV_NAME}" \
        --name "AcsConnectionString" \
        --value "${ACS_CONNECTION}" \
        --output none
    
    # Get and store Fluid Relay key
    export FLUID_KEY=$(az fluid-relay server list-keys \
        --name "${FLUID_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query primaryKey \
        --output tsv)
    
    if [ -z "$FLUID_KEY" ]; then
        error "Failed to retrieve Fluid Relay key"
    fi
    
    az keyvault secret set \
        --vault-name "${KV_NAME}" \
        --name "FluidRelayKey" \
        --value "${FLUID_KEY}" \
        --output none
    
    success "Secrets stored in Key Vault: ${KV_NAME}"
}

# Function to create storage account
create_storage_account() {
    info "Creating storage account: ${STORAGE_NAME}"
    
    # Check if storage account exists
    if az storage account show --name "${STORAGE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Storage account ${STORAGE_NAME} already exists"
    else
        az storage account create \
            --name "${STORAGE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --https-only true \
            --output none
        
        success "Storage account created: ${STORAGE_NAME}"
    fi
    
    # Get storage key
    export STORAGE_KEY=$(az storage account keys list \
        --account-name "${STORAGE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query [0].value \
        --output tsv)
    
    if [ -z "$STORAGE_KEY" ]; then
        error "Failed to retrieve storage account key"
    fi
    
    # Create containers
    local containers=("whiteboards" "recordings")
    for container in "${containers[@]}"; do
        if az storage container show --name "$container" --account-name "${STORAGE_NAME}" --account-key "${STORAGE_KEY}" &> /dev/null; then
            warn "Container $container already exists"
        else
            az storage container create \
                --name "$container" \
                --account-name "${STORAGE_NAME}" \
                --account-key "${STORAGE_KEY}" \
                --output none
            
            success "Container created: $container"
        fi
    done
}

# Function to create Function App
create_function_app() {
    info "Creating Function App: ${FUNC_NAME}"
    
    # Check if Function App exists
    if az functionapp show --name "${FUNC_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Function App ${FUNC_NAME} already exists"
    else
        az functionapp create \
            --name "${FUNC_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_NAME}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime node \
            --runtime-version 18 \
            --functions-version 4 \
            --output none
        
        success "Function App created: ${FUNC_NAME}"
    fi
    
    # Configure app settings
    az functionapp config appsettings set \
        --name "${FUNC_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "ACS_CONNECTION_STRING=@Microsoft.KeyVault(VaultName=${KV_NAME};SecretName=AcsConnectionString)" \
        "FLUID_RELAY_KEY=@Microsoft.KeyVault(VaultName=${KV_NAME};SecretName=FluidRelayKey)" \
        "FLUID_ENDPOINT=${FLUID_ENDPOINT}" \
        "FLUID_TENANT=${FLUID_TENANT}" \
        --output none
    
    success "Function App configured with Key Vault references"
}

# Function to configure managed identity
configure_managed_identity() {
    info "Configuring managed identity and permissions"
    
    # Enable managed identity
    az functionapp identity assign \
        --name "${FUNC_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --output none
    
    # Get identity principal ID
    export FUNC_IDENTITY=$(az functionapp identity show \
        --name "${FUNC_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query principalId \
        --output tsv)
    
    if [ -z "$FUNC_IDENTITY" ]; then
        error "Failed to retrieve function identity"
    fi
    
    # Grant Key Vault access
    az keyvault set-policy \
        --name "${KV_NAME}" \
        --object-id "${FUNC_IDENTITY}" \
        --secret-permissions get list \
        --output none
    
    # Grant Storage access
    az role assignment create \
        --assignee "${FUNC_IDENTITY}" \
        --role "Storage Blob Data Contributor" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_NAME}" \
        --output none
    
    success "Managed identity configured with permissions"
}

# Function to deploy function code
deploy_function_code() {
    info "Deploying function code"
    
    # Create temporary directory
    local temp_dir="/tmp/collab-functions-${RANDOM_SUFFIX}"
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # Create package.json
    cat > package.json << EOF
{
  "name": "collab-functions",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "@azure/communication-identity": "^1.3.0",
    "@fluidframework/azure-client": "^2.0.0",
    "@azure/identity": "^4.0.0"
  }
}
EOF
    
    # Create GetAcsToken function
    mkdir -p GetAcsToken
    cat > GetAcsToken/index.js << 'EOF'
const { CommunicationIdentityClient } = require("@azure/communication-identity");

module.exports = async function (context, req) {
    const connectionString = process.env["ACS_CONNECTION_STRING"];
    const client = new CommunicationIdentityClient(connectionString);
    
    try {
        const user = await client.createUser();
        const token = await client.getToken(user, ["chat", "voip"]);
        
        context.res = {
            body: {
                userId: user.communicationUserId,
                token: token.token,
                expiresOn: token.expiresOn
            }
        };
    } catch (error) {
        context.log.error("Error generating ACS token:", error);
        context.res = {
            status: 500,
            body: { error: error.message }
        };
    }
};
EOF
    
    # Create function.json for GetAcsToken
    cat > GetAcsToken/function.json << EOF
{
  "bindings": [
    {
      "authLevel": "anonymous",
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
    
    # Create host.json
    cat > host.json << EOF
{
  "version": "2.0",
  "logging": {
    "logLevel": {
      "default": "Information"
    }
  }
}
EOF
    
    # Check if func CLI is available
    if command -v func &> /dev/null; then
        info "Deploying functions using Azure Functions Core Tools"
        func azure functionapp publish "${FUNC_NAME}" --javascript
        success "Function code deployed successfully"
    else
        warn "Azure Functions Core Tools not found. Skipping function deployment."
        warn "Please install Azure Functions Core Tools and run: func azure functionapp publish ${FUNC_NAME}"
    fi
    
    # Clean up temporary directory
    cd "$SCRIPT_DIR"
    rm -rf "$temp_dir"
}

# Function to configure CORS and monitoring
configure_cors_monitoring() {
    info "Configuring CORS and monitoring"
    
    # Configure CORS
    az functionapp cors add \
        --name "${FUNC_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --allowed-origins "*" \
        --output none
    
    # Create Application Insights
    local app_insights_name="${FUNC_NAME}-insights"
    if az monitor app-insights component show --app "$app_insights_name" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Application Insights $app_insights_name already exists"
    else
        az monitor app-insights component create \
            --app "$app_insights_name" \
            --location "${LOCATION}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none
        
        success "Application Insights created: $app_insights_name"
    fi
    
    # Get Application Insights connection string
    export APP_INSIGHTS=$(az monitor app-insights component show \
        --app "$app_insights_name" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString \
        --output tsv)
    
    if [ -n "$APP_INSIGHTS" ]; then
        az functionapp config appsettings set \
            --name "${FUNC_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --settings "APPLICATIONINSIGHTS_CONNECTION_STRING=${APP_INSIGHTS}" \
            --output none
        
        success "Application Insights configured"
    else
        warn "Failed to configure Application Insights"
    fi
}

# Function to validate deployment
validate_deployment() {
    info "Validating deployment"
    
    # Check resource group
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        error "Resource group validation failed"
    fi
    
    # Check ACS resource
    if ! az communication show --name "${ACS_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        error "ACS resource validation failed"
    fi
    
    # Check Fluid Relay
    if ! az fluid-relay server show --name "${FLUID_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        error "Fluid Relay validation failed"
    fi
    
    # Check Key Vault
    if ! az keyvault show --name "${KV_NAME}" &> /dev/null; then
        error "Key Vault validation failed"
    fi
    
    # Check Storage Account
    if ! az storage account show --name "${STORAGE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        error "Storage account validation failed"
    fi
    
    # Check Function App
    if ! az functionapp show --name "${FUNC_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        error "Function App validation failed"
    fi
    
    success "All resources validated successfully"
}

# Function to display deployment summary
display_summary() {
    info "Deployment Summary"
    echo "===================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "ACS Resource: ${ACS_NAME}"
    echo "Fluid Relay: ${FLUID_NAME}"
    echo "Key Vault: ${KV_NAME}"
    echo "Storage Account: ${STORAGE_NAME}"
    echo "Function App: ${FUNC_NAME}"
    echo "===================="
    
    # Get Function App URL
    local func_url=$(az functionapp show \
        --name "${FUNC_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query defaultHostName \
        --output tsv)
    
    if [ -n "$func_url" ]; then
        echo "Function App URL: https://${func_url}"
        echo "ACS Token Endpoint: https://${func_url}/api/GetAcsToken"
    fi
    
    echo "===================="
    echo "Deployment state saved to: ${DEPLOYMENT_STATE_FILE}"
    echo "Deployment log saved to: ${LOG_FILE}"
}

# Main deployment function
main() {
    info "Starting deployment of Real-Time Collaborative Applications"
    
    # Initialize log file
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_acs_resource
    create_fluid_relay
    create_key_vault
    create_storage_account
    create_function_app
    configure_managed_identity
    deploy_function_code
    configure_cors_monitoring
    validate_deployment
    display_summary
    
    success "Deployment completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Test the ACS token endpoint"
    echo "2. Implement client-side code to use the services"
    echo "3. Monitor costs in Azure Cost Management"
    echo "4. Run './destroy.sh' when finished to clean up resources"
}

# Handle script interruption
trap 'error "Deployment interrupted by user"' INT TERM

# Run main function
main "$@"