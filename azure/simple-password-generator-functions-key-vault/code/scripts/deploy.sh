#!/bin/bash

# Azure Password Generator Function with Key Vault - Deployment Script
# This script deploys a serverless password generator using Azure Functions and Key Vault
# with managed identity for secure authentication

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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

# Error handler
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check the logs above for details."
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Cleaning up resources created during failed deployment..."
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_info "Deleting resource group: ${RESOURCE_GROUP}"
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait 2>/dev/null || true
    fi
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Configuration
DEFAULT_LOCATION="eastus"
DEFAULT_NODE_VERSION="20"
DEFAULT_FUNCTIONS_VERSION="4"

# Display banner
echo "=========================================="
echo "Azure Password Generator Deployment"
echo "=========================================="
echo ""

# Prerequisites check
log_info "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
fi

# Check if logged into Azure
if ! az account show &> /dev/null; then
    error_exit "Not logged into Azure. Please run 'az login' first."
fi

# Check if Node.js is available for local function development
if ! command -v node &> /dev/null; then
    log_warning "Node.js not found. This is required for local function development."
    log_warning "Install from https://nodejs.org/ or continue for Azure-only deployment."
fi

# Check if Functions Core Tools is available
if ! command -v func &> /dev/null; then
    log_warning "Azure Functions Core Tools not found."
    log_warning "This will be installed during deployment if needed."
fi

log_success "Prerequisites check completed"

# Get user input with defaults
read -p "Enter Azure region [${DEFAULT_LOCATION}]: " LOCATION
LOCATION=${LOCATION:-$DEFAULT_LOCATION}

read -p "Enter resource group name (leave empty for auto-generated): " RESOURCE_GROUP_INPUT
if [[ -z "${RESOURCE_GROUP_INPUT}" ]]; then
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    RESOURCE_GROUP="rg-password-gen-${RANDOM_SUFFIX}"
else
    RESOURCE_GROUP="${RESOURCE_GROUP_INPUT}"
fi

# Generate unique suffix for resources
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Set environment variables
export RESOURCE_GROUP
export LOCATION
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
export KEY_VAULT_NAME="kv-passgen-${RANDOM_SUFFIX}"
export STORAGE_ACCOUNT="stpassgen${RANDOM_SUFFIX}"
export FUNCTION_APP_NAME="func-passgen-${RANDOM_SUFFIX}"

log_info "Deployment configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Location: ${LOCATION}"
log_info "  Key Vault: ${KEY_VAULT_NAME}"
log_info "  Storage Account: ${STORAGE_ACCOUNT}"
log_info "  Function App: ${FUNCTION_APP_NAME}"
echo ""

# Confirm deployment
read -p "Continue with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Deployment cancelled by user"
    exit 0
fi

# Start deployment
log_info "Starting deployment..."

# Step 1: Create resource group
log_info "Creating resource group..."
if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Resource group ${RESOURCE_GROUP} already exists"
else
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=recipe environment=demo \
        --output none
    log_success "Resource group created: ${RESOURCE_GROUP}"
fi

# Step 2: Create Key Vault
log_info "Creating Azure Key Vault..."
if az keyvault show --name "${KEY_VAULT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Key Vault ${KEY_VAULT_NAME} already exists"
    VAULT_URI=$(az keyvault show \
        --name "${KEY_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.vaultUri \
        --output tsv)
else
    az keyvault create \
        --name "${KEY_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --enable-soft-delete true \
        --retention-days 7 \
        --enable-purge-protection false \
        --output none

    VAULT_URI=$(az keyvault show \
        --name "${KEY_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.vaultUri \
        --output tsv)

    log_success "Key Vault created with URI: ${VAULT_URI}"
fi

# Step 3: Create Storage Account
log_info "Creating storage account for Functions runtime..."
if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Storage account ${STORAGE_ACCOUNT} already exists"
else
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --output none
    log_success "Storage account created: ${STORAGE_ACCOUNT}"
fi

# Step 4: Create Function App with managed identity
log_info "Creating Function App with managed identity..."
if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Function App ${FUNCTION_APP_NAME} already exists"
    PRINCIPAL_ID=$(az functionapp identity show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query principalId \
        --output tsv)
else
    az functionapp create \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime node \
        --runtime-version "${DEFAULT_NODE_VERSION}" \
        --functions-version "${DEFAULT_FUNCTIONS_VERSION}" \
        --assign-identity [system] \
        --output none

    # Get the managed identity principal ID
    PRINCIPAL_ID=$(az functionapp identity show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query principalId \
        --output tsv)

    log_success "Function App created with managed identity: ${PRINCIPAL_ID}"
fi

# Step 5: Grant Key Vault access to Function App
log_info "Configuring Key Vault access permissions..."

# Check if role assignment already exists
if az role assignment list \
    --assignee "${PRINCIPAL_ID}" \
    --role "Key Vault Secrets Officer" \
    --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" \
    --query "[0].id" --output tsv &> /dev/null; then
    log_warning "Key Vault role assignment already exists"
else
    # Wait a moment for identity to propagate
    log_info "Waiting for managed identity to propagate..."
    sleep 30

    az role assignment create \
        --assignee "${PRINCIPAL_ID}" \
        --role "Key Vault Secrets Officer" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" \
        --output none
    log_success "Key Vault access granted to Function App"
fi

# Configure Key Vault URI as application setting
az functionapp config appsettings set \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --settings "KEY_VAULT_URI=${VAULT_URI}" \
    --output none
log_success "Key Vault URI configured in Function App settings"

# Step 6: Create Function code
log_info "Creating Function application code..."

# Create temporary directory for function code
TEMP_DIR=$(mktemp -d)
cd "${TEMP_DIR}"

# Create package.json
cat > package.json << 'EOF'
{
  "name": "password-generator-function",
  "version": "1.0.0",
  "description": "Serverless password generator with Key Vault storage",
  "main": "src/functions/*.js",
  "scripts": {
    "start": "func start",
    "test": "echo \"No tests yet\""
  },
  "dependencies": {
    "@azure/functions": "^4.0.0",
    "@azure/keyvault-secrets": "^4.8.0",
    "@azure/identity": "^4.2.1"
  },
  "devDependencies": {}
}
EOF

# Create functions directory
mkdir -p src/functions

# Create the password generator function
cat > src/functions/generatePassword.js << 'EOF'
const { app } = require('@azure/functions');
const { SecretClient } = require('@azure/keyvault-secrets');
const { DefaultAzureCredential } = require('@azure/identity');
const crypto = require('crypto');

// Initialize Key Vault client with managed identity
const credential = new DefaultAzureCredential();
const vaultUrl = process.env.KEY_VAULT_URI;
const client = new SecretClient(vaultUrl, credential);

// Generate cryptographically secure password
function generateSecurePassword(length = 16) {
    const charset = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*';
    let password = '';
    
    for (let i = 0; i < length; i++) {
        const randomIndex = crypto.randomInt(0, charset.length);
        password += charset[randomIndex];
    }
    
    return password;
}

app.http('generatePassword', {
    methods: ['POST'],
    authLevel: 'function',
    handler: async (request, context) => {
        try {
            const requestBody = await request.json();
            const secretName = requestBody.secretName;
            const passwordLength = requestBody.length || 16;
            
            // Validate input
            if (!secretName || secretName.length < 1) {
                return {
                    status: 400,
                    jsonBody: { error: 'secretName is required' }
                };
            }
            
            // Generate secure password
            const password = generateSecurePassword(passwordLength);
            
            // Store password in Key Vault
            await client.setSecret(secretName, password, {
                contentType: 'password',
                tags: {
                    generatedBy: 'azure-functions',
                    timestamp: new Date().toISOString()
                }
            });
            
            context.log(`Password generated and stored for secret: ${secretName}`);
            
            return {
                status: 200,
                jsonBody: {
                    message: 'Password generated and stored successfully',
                    secretName: secretName,
                    vaultUri: vaultUrl
                }
            };
            
        } catch (error) {
            context.log.error('Error generating password:', error);
            return {
                status: 500,
                jsonBody: { error: 'Internal server error' }
            };
        }
    }
});
EOF

log_success "Function code created"

# Step 7: Install Azure Functions Core Tools if needed
if ! command -v func &> /dev/null; then
    log_info "Installing Azure Functions Core Tools..."
    if command -v npm &> /dev/null; then
        npm install -g azure-functions-core-tools@4 --unsafe-perm true
        log_success "Azure Functions Core Tools installed"
    else
        log_warning "npm not available. Please install Azure Functions Core Tools manually."
        log_warning "Visit: https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local"
    fi
fi

# Step 8: Deploy function to Azure
log_info "Installing function dependencies..."
if command -v npm &> /dev/null; then
    npm install --silent
    log_success "Dependencies installed"
else
    log_warning "npm not available. Skipping local dependency installation."
fi

log_info "Deploying function to Azure..."
if command -v func &> /dev/null; then
    func azure functionapp publish "${FUNCTION_APP_NAME}" --no-build
    log_success "Function deployed to Azure"
else
    log_warning "Azure Functions Core Tools not available. Skipping function deployment."
    log_warning "You can deploy manually using: func azure functionapp publish ${FUNCTION_APP_NAME}"
fi

# Step 9: Get function access information
log_info "Retrieving function access information..."

FUNCTION_KEY=$(az functionapp keys list \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query masterKey \
    --output tsv)

FUNCTION_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net"

# Cleanup temporary directory
cd - > /dev/null
rm -rf "${TEMP_DIR}"
log_success "Temporary files cleaned up"

# Display deployment summary
echo ""
echo "=========================================="
echo "Deployment Completed Successfully!"
echo "=========================================="
echo ""
log_success "Resource Group: ${RESOURCE_GROUP}"
log_success "Key Vault: ${KEY_VAULT_NAME}"
log_success "Function App: ${FUNCTION_APP_NAME}"
log_success "Function URL: ${FUNCTION_URL}"
echo ""
echo "To test the password generator:"
echo "curl -X POST \"${FUNCTION_URL}/api/generatePassword?code=${FUNCTION_KEY}\" \\"
echo "     -H \"Content-Type: application/json\" \\"
echo "     -d '{\"secretName\": \"test-password-001\", \"length\": 20}'"
echo ""
echo "To view generated secrets in Key Vault:"
echo "az keyvault secret list --vault-name ${KEY_VAULT_NAME}"
echo ""
echo "To clean up resources, run: ./destroy.sh"
echo ""

# Save deployment info for cleanup script
cat > .deployment_info << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
KEY_VAULT_NAME=${KEY_VAULT_NAME}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
LOCATION=${LOCATION}
EOF

log_success "Deployment information saved to .deployment_info"
log_success "Deployment completed successfully!"