#!/bin/bash

# =============================================================================
# Deploy Script for Intelligent Document Processing with Azure AI Document Intelligence and Logic Apps
# =============================================================================
#
# This script deploys the complete infrastructure for automated document processing
# using Azure AI Document Intelligence, Logic Apps, and supporting services.
#
# Prerequisites:
# - Azure CLI installed and configured
# - Appropriate Azure subscription permissions
# - bash shell environment
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# Configuration and Variables
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Deployment configuration
DEPLOYMENT_NAME="docprocessing-deployment-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="deploy-$(date +%Y%m%d-%H%M%S).log"

# Default configuration (can be overridden via environment variables)
DEFAULT_LOCATION="eastus"
DEFAULT_ENVIRONMENT="demo"

# =============================================================================
# Helper Functions
# =============================================================================

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

# Error logging function
error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Success logging function
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

# Warning logging function
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate Azure CLI is logged in
validate_azure_cli() {
    log "Validating Azure CLI authentication..."
    
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    if ! az account show >/dev/null 2>&1; then
        error "Azure CLI is not logged in. Please run 'az login' first."
        exit 1
    fi
    
    # Get account info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    ACCOUNT_NAME=$(az account show --query name --output tsv)
    
    log "Using Azure subscription: $ACCOUNT_NAME ($SUBSCRIPTION_ID)"
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check for required tools
    local required_tools=("az" "openssl" "curl" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            error "Required tool '$tool' is not installed."
            exit 1
        fi
    done
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' --output tsv)
    log "Azure CLI version: $az_version"
    
    success "Prerequisites validation completed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Use environment variables if provided, otherwise use defaults
    export LOCATION="${AZURE_LOCATION:-$DEFAULT_LOCATION}"
    export ENVIRONMENT="${AZURE_ENVIRONMENT:-$DEFAULT_ENVIRONMENT}"
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names
    export RESOURCE_GROUP="rg-docprocessing-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stdocs${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-docs-${RANDOM_SUFFIX}"
    export DOC_INTELLIGENCE_NAME="docintell-${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="logic-docprocess-${RANDOM_SUFFIX}"
    export SERVICE_BUS_NAMESPACE="sb-docs-${RANDOM_SUFFIX}"
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    log "Environment configuration:"
    log "  Location: $LOCATION"
    log "  Environment: $ENVIRONMENT"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Storage Account: $STORAGE_ACCOUNT"
    log "  Key Vault: $KEY_VAULT_NAME"
    log "  Document Intelligence: $DOC_INTELLIGENCE_NAME"
    log "  Logic App: $LOGIC_APP_NAME"
    log "  Service Bus: $SERVICE_BUS_NAMESPACE"
    log "  Random Suffix: $RANDOM_SUFFIX"
    
    success "Environment setup completed"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=document-processing environment="$ENVIRONMENT" deployment="$DEPLOYMENT_NAME"
        
        success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account: $STORAGE_ACCOUNT"
    
    # Create storage account
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --tags purpose=document-processing environment="$ENVIRONMENT"
    
    # Get storage account key
    export STORAGE_KEY=$(az storage account keys list \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].value" --output tsv)
    
    # Create containers
    az storage container create \
        --name input-documents \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --public-access off
    
    az storage container create \
        --name processed-documents \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --public-access off
    
    success "Storage account and containers created: $STORAGE_ACCOUNT"
}

# Function to create Document Intelligence service
create_document_intelligence() {
    log "Creating Document Intelligence service: $DOC_INTELLIGENCE_NAME"
    
    # Create Document Intelligence resource
    az cognitiveservices account create \
        --name "$DOC_INTELLIGENCE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --kind FormRecognizer \
        --sku S0 \
        --location "$LOCATION" \
        --tags purpose=document-processing environment="$ENVIRONMENT" \
        --yes
    
    # Get Document Intelligence endpoint and key
    export DOC_INTELLIGENCE_ENDPOINT=$(az cognitiveservices account show \
        --name "$DOC_INTELLIGENCE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.endpoint" --output tsv)
    
    export DOC_INTELLIGENCE_KEY=$(az cognitiveservices account keys list \
        --name "$DOC_INTELLIGENCE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "key1" --output tsv)
    
    success "Document Intelligence service created: $DOC_INTELLIGENCE_NAME"
    log "Endpoint: $DOC_INTELLIGENCE_ENDPOINT"
}

# Function to create Key Vault
create_key_vault() {
    log "Creating Key Vault: $KEY_VAULT_NAME"
    
    # Create Key Vault
    az keyvault create \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku standard \
        --tags purpose=document-processing environment="$ENVIRONMENT"
    
    # Wait for Key Vault to be ready
    log "Waiting for Key Vault to be ready..."
    sleep 30
    
    # Store secrets in Key Vault
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "storage-account-key" \
        --value "$STORAGE_KEY" \
        --description "Storage account key for document processing"
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "doc-intelligence-key" \
        --value "$DOC_INTELLIGENCE_KEY" \
        --description "Document Intelligence API key"
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "doc-intelligence-endpoint" \
        --value "$DOC_INTELLIGENCE_ENDPOINT" \
        --description "Document Intelligence endpoint URL"
    
    success "Key Vault created and secrets stored: $KEY_VAULT_NAME"
}

# Function to create Service Bus
create_service_bus() {
    log "Creating Service Bus namespace: $SERVICE_BUS_NAMESPACE"
    
    # Create Service Bus namespace
    az servicebus namespace create \
        --name "$SERVICE_BUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard \
        --tags purpose=document-processing environment="$ENVIRONMENT"
    
    # Create queue for processed documents
    az servicebus queue create \
        --name processed-docs-queue \
        --namespace-name "$SERVICE_BUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --max-size 1024 \
        --default-message-time-to-live P7D
    
    # Get Service Bus connection string
    export SERVICE_BUS_CONNECTION=$(az servicebus namespace \
        authorization-rule keys list \
        --resource-group "$RESOURCE_GROUP" \
        --namespace-name "$SERVICE_BUS_NAMESPACE" \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString --output tsv)
    
    # Store Service Bus connection in Key Vault
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "servicebus-connection" \
        --value "$SERVICE_BUS_CONNECTION" \
        --description "Service Bus connection string"
    
    success "Service Bus namespace and queue created: $SERVICE_BUS_NAMESPACE"
}

# Function to create Logic App
create_logic_app() {
    log "Creating Logic App: $LOGIC_APP_NAME"
    
    # Create Logic App with basic definition
    az logic workflow create \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=document-processing environment="$ENVIRONMENT" \
        --definition '{
            "definition": {
                "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
                "contentVersion": "1.0.0.0",
                "triggers": {},
                "actions": {},
                "outputs": {}
            }
        }'
    
    # Enable system-assigned managed identity
    az logic workflow identity assign \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP"
    
    # Get Logic App principal ID
    export LOGIC_APP_PRINCIPAL_ID=$(az logic workflow show \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "identity.principalId" --output tsv)
    
    # Wait for managed identity to propagate
    log "Waiting for managed identity to propagate..."
    sleep 30
    
    success "Logic App created with managed identity: $LOGIC_APP_NAME"
    log "Principal ID: $LOGIC_APP_PRINCIPAL_ID"
}

# Function to configure Key Vault access
configure_key_vault_access() {
    log "Configuring Key Vault access for Logic App..."
    
    # Grant Logic App access to Key Vault secrets
    az keyvault set-policy \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --object-id "$LOGIC_APP_PRINCIPAL_ID" \
        --secret-permissions get list
    
    success "Key Vault access configured for Logic App"
}

# Function to create API connections
create_api_connections() {
    log "Creating API connections for Logic App..."
    
    # Create API connection for Blob Storage
    az resource create \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type Microsoft.Web/connections \
        --name azureblob-connection \
        --properties '{
            "api": {
                "id": "/subscriptions/'$SUBSCRIPTION_ID'/providers/Microsoft.Web/locations/'$LOCATION'/managedApis/azureblob"
            },
            "displayName": "Blob Storage Connection",
            "parameterValues": {
                "accountName": "'$STORAGE_ACCOUNT'",
                "accessKey": "'$STORAGE_KEY'"
            }
        }'
    
    # Create API connection for Key Vault
    az resource create \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type Microsoft.Web/connections \
        --name keyvault-connection \
        --properties '{
            "api": {
                "id": "/subscriptions/'$SUBSCRIPTION_ID'/providers/Microsoft.Web/locations/'$LOCATION'/managedApis/keyvault"
            },
            "displayName": "Key Vault Connection",
            "parameterValueType": "Alternative",
            "alternativeParameterValues": {
                "vaultName": "'$KEY_VAULT_NAME'"
            }
        }'
    
    # Create API connection for Service Bus
    az resource create \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type Microsoft.Web/connections \
        --name servicebus-connection \
        --properties '{
            "api": {
                "id": "/subscriptions/'$SUBSCRIPTION_ID'/providers/Microsoft.Web/locations/'$LOCATION'/managedApis/servicebus"
            },
            "displayName": "Service Bus Connection",
            "parameterValues": {
                "connectionString": "'$SERVICE_BUS_CONNECTION'"
            }
        }'
    
    success "API connections created for Logic App"
}

# Function to upload sample document
upload_sample_document() {
    log "Uploading sample document for testing..."
    
    # Create a sample invoice document
    cat > sample-invoice.txt << EOF
INVOICE
Invoice Number: INV-2024-001
Date: 2024-01-15

Bill To:
Contoso Ltd.
123 Main Street
Seattle, WA 98101

Items:
Product A - \$100.00
Product B - \$200.00
Tax - \$30.00
Total: \$330.00
EOF
    
    # Upload sample document
    az storage blob upload \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --container-name input-documents \
        --file sample-invoice.txt \
        --name "invoice-$(date +%s).txt"
    
    # Clean up local file
    rm sample-invoice.txt
    
    success "Sample document uploaded for testing"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    log "==================="
    log "Resource Group: $RESOURCE_GROUP"
    log "Storage Account: $STORAGE_ACCOUNT"
    log "Key Vault: $KEY_VAULT_NAME"
    log "Document Intelligence: $DOC_INTELLIGENCE_NAME"
    log "Logic App: $LOGIC_APP_NAME"
    log "Service Bus: $SERVICE_BUS_NAMESPACE"
    log ""
    log "Next Steps:"
    log "1. Configure the Logic App workflow in Azure Portal"
    log "2. Test document processing by uploading files to the 'input-documents' container"
    log "3. Monitor Logic App runs and Service Bus messages"
    log "4. Integrate with downstream systems using the Service Bus queue"
    log ""
    log "Azure Portal URLs:"
    log "- Resource Group: https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
    log "- Logic App: https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Logic/workflows/$LOGIC_APP_NAME"
    log "- Storage Account: https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"
    log ""
    log "To clean up resources, run: ./destroy.sh"
    log "Log file: $LOG_FILE"
}

# Function to handle cleanup on error
cleanup_on_error() {
    error "Deployment failed. Check $LOG_FILE for details."
    warning "Resources may have been partially created. Run ./destroy.sh to clean up."
    exit 1
}

# =============================================================================
# Main Deployment Function
# =============================================================================

main() {
    log "Starting deployment of Intelligent Document Processing solution..."
    log "Deployment name: $DEPLOYMENT_NAME"
    log "Log file: $LOG_FILE"
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Execute deployment steps
    validate_azure_cli
    validate_prerequisites
    setup_environment
    create_resource_group
    create_storage_account
    create_document_intelligence
    create_key_vault
    create_service_bus
    create_logic_app
    configure_key_vault_access
    create_api_connections
    upload_sample_document
    
    success "Deployment completed successfully!"
    display_summary
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi