#!/bin/bash

# Blockchain Supply Chain Transparency - Deployment Script
# This script deploys Azure Confidential Ledger, Cosmos DB, Logic Apps, and Event Grid
# for a comprehensive blockchain-powered supply chain tracking solution

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
RESOURCE_GROUP="rg-supply-chain-ledger"
LOCATION="eastus"
SKIP_APIM="${SKIP_APIM:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Logging functions
log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Blockchain Supply Chain Transparency solution.

OPTIONS:
    -g, --resource-group NAME    Resource group name (default: rg-supply-chain-ledger)
    -l, --location LOCATION      Azure region (default: eastus)
    -s, --skip-apim             Skip API Management deployment (saves 20-30 minutes)
    -d, --dry-run               Show what would be deployed without actually deploying
    -h, --help                  Show this help message

EXAMPLES:
    $0                          # Deploy with default settings
    $0 -g my-rg -l westus2     # Deploy to custom resource group and region
    $0 --skip-apim             # Deploy without API Management
    $0 --dry-run               # Preview deployment

PREREQUISITES:
    - Azure CLI installed and logged in
    - Contributor or Owner permissions on Azure subscription
    - Confidential Ledger provider registered in subscription
    - Sufficient quota for services in target region

ESTIMATED COST: \$200-300/month for development environment
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
        -s|--skip-apim)
            SKIP_APIM="true"
            shift
            ;;
        -d|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check if logged in
    if ! az account show >/dev/null 2>&1; then
        error_exit "Not logged into Azure. Please run 'az login' first."
    fi
    
    # Check subscription
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    log_info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    
    # Check if Confidential Ledger provider is registered
    PROVIDER_STATUS=$(az provider show --namespace Microsoft.ConfidentialLedger --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
    if [[ "$PROVIDER_STATUS" != "Registered" ]]; then
        log_warning "Microsoft.ConfidentialLedger provider not registered. Registering now..."
        if [[ "$DRY_RUN" != "true" ]]; then
            az provider register --namespace Microsoft.ConfidentialLedger
            log_info "Waiting for provider registration..."
            while [[ "$(az provider show --namespace Microsoft.ConfidentialLedger --query registrationState -o tsv)" != "Registered" ]]; do
                sleep 10
                echo -n "."
            done
            echo
            log_success "Provider registered successfully"
        fi
    fi
    
    # Check for required tools
    if ! command_exists openssl; then
        error_exit "OpenSSL is required but not installed."
    fi
    
    if ! command_exists curl; then
        error_exit "curl is required but not installed."
    fi
    
    log_success "Prerequisites validation completed"
}

# Save deployment configuration
save_deployment_config() {
    log_info "Saving deployment configuration..."
    
    cat > deployment-config.json << EOF
{
    "deploymentTimestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "resourceGroup": "$RESOURCE_GROUP",
    "location": "$LOCATION",
    "subscription": "$SUBSCRIPTION_ID",
    "randomSuffix": "$RANDOM_SUFFIX",
    "resources": {
        "ledgerName": "$LEDGER_NAME",
        "cosmosAccount": "$COSMOS_ACCOUNT",
        "storageAccount": "$STORAGE_ACCOUNT",
        "keyVaultName": "$KEYVAULT_NAME",
        "logicAppName": "$LOGIC_APP_NAME",
        "eventGridTopic": "$EVENT_GRID_TOPIC",
        "apimName": "$APIM_NAME",
        "appInsightsName": "$APPINSIGHTS_NAME",
        "workspaceName": "$WORKSPACE_NAME",
        "identityName": "$IDENTITY_NAME"
    },
    "skipApim": $SKIP_APIM
}
EOF
    
    log_success "Deployment configuration saved to deployment-config.json"
}

# Set environment variables
set_environment_variables() {
    log_info "Setting environment variables..."
    
    # Generate unique suffix for globally unique resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export LEDGER_NAME="${LEDGER_NAME:-scledger${RANDOM_SUFFIX}}"
    export COSMOS_ACCOUNT="${COSMOS_ACCOUNT:-sccosmos${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-scstorage${RANDOM_SUFFIX}}"
    export KEYVAULT_NAME="${KEYVAULT_NAME:-sckv${RANDOM_SUFFIX}}"
    export LOGIC_APP_NAME="${LOGIC_APP_NAME:-sc-logic-app-${RANDOM_SUFFIX}}"
    export EVENT_GRID_TOPIC="${EVENT_GRID_TOPIC:-sc-events-${RANDOM_SUFFIX}}"
    export APIM_NAME="${APIM_NAME:-sc-apim-${RANDOM_SUFFIX}}"
    export APPINSIGHTS_NAME="${APPINSIGHTS_NAME:-supply-chain-insights-${RANDOM_SUFFIX}}"
    export WORKSPACE_NAME="${WORKSPACE_NAME:-supply-chain-logs-${RANDOM_SUFFIX}}"
    export IDENTITY_NAME="${IDENTITY_NAME:-logic-app-identity-${RANDOM_SUFFIX}}"
    
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Random Suffix: $RANDOM_SUFFIX"
    log_info "Ledger Name: $LEDGER_NAME"
    log_info "Cosmos Account: $COSMOS_ACCOUNT"
    log_info "Storage Account: $STORAGE_ACCOUNT"
    log_info "Key Vault: $KEYVAULT_NAME"
    log_info "Logic App: $LOGIC_APP_NAME"
    log_info "Event Grid Topic: $EVENT_GRID_TOPIC"
    if [[ "$SKIP_APIM" != "true" ]]; then
        log_info "API Management: $APIM_NAME"
    fi
    
    log_success "Environment variables configured"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return
    fi
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Resource group '$RESOURCE_GROUP' already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=supply-chain environment=demo deployment-script=true \
            || error_exit "Failed to create resource group"
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Create Azure AD application
create_azure_ad_app() {
    log_info "Creating Azure AD application for Confidential Ledger access..."
    
    # Create Azure AD application
    export APP_ID=$(az ad app create \
        --display-name "SupplyChainLedgerApp${RANDOM_SUFFIX}" \
        --query appId \
        --output tsv) || error_exit "Failed to create Azure AD application"
    
    export SP_ID=$(az ad sp create \
        --id "$APP_ID" \
        --query id \
        --output tsv) || error_exit "Failed to create service principal"
    
    log_success "Azure AD application created for ledger access"
    log_info "Application ID: $APP_ID"
    log_info "Service Principal ID: $SP_ID"
}

# Create Confidential Ledger
create_confidential_ledger() {
    log_info "Creating Azure Confidential Ledger instance..."
    
    # Check if ledger already exists
    if az confidentialledger show --name "$LEDGER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Confidential Ledger '$LEDGER_NAME' already exists"
    else
        az confidentialledger create \
            --name "$LEDGER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --ledger-type Public \
            --aad-based-security-principals \
                objectId="$SP_ID" \
                tenantId="$(az account show --query tenantId -o tsv)" \
                ledgerRoleName=Administrator \
            || error_exit "Failed to create Confidential Ledger"
        
        log_info "Waiting for ledger creation (this may take 5-10 minutes)..."
        az confidentialledger wait \
            --name "$LEDGER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --created \
            --timeout 600 \
            || error_exit "Timeout waiting for ledger creation"
    fi
    
    # Get ledger endpoint
    export LEDGER_ENDPOINT=$(az confidentialledger show \
        --name "$LEDGER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.ledgerUri \
        --output tsv) || error_exit "Failed to get ledger endpoint"
    
    log_success "Confidential Ledger created: $LEDGER_ENDPOINT"
}

# Deploy Cosmos DB
deploy_cosmos_db() {
    log_info "Deploying Azure Cosmos DB with global distribution..."
    
    # Check if Cosmos DB account already exists
    if az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Cosmos DB account '$COSMOS_ACCOUNT' already exists"
    else
        az cosmosdb create \
            --name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --locations regionName="$LOCATION" failoverPriority=0 \
            --default-consistency-level Session \
            --enable-multiple-write-locations true \
            --enable-analytical-storage true \
            --kind GlobalDocumentDB \
            || error_exit "Failed to create Cosmos DB account"
    fi
    
    # Create database for supply chain data
    if ! az cosmosdb sql database show --account-name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --name SupplyChainDB >/dev/null 2>&1; then
        az cosmosdb sql database create \
            --account-name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --name SupplyChainDB \
            || error_exit "Failed to create Cosmos DB database"
    fi
    
    # Create container for product tracking
    if ! az cosmosdb sql container show --account-name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --database-name SupplyChainDB --name Products >/dev/null 2>&1; then
        az cosmosdb sql container create \
            --account-name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --database-name SupplyChainDB \
            --name Products \
            --partition-key-path /productId \
            --throughput 1000 \
            || error_exit "Failed to create Products container"
    fi
    
    # Create container for transaction records
    if ! az cosmosdb sql container show --account-name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --database-name SupplyChainDB --name Transactions >/dev/null 2>&1; then
        az cosmosdb sql container create \
            --account-name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --database-name SupplyChainDB \
            --name Transactions \
            --partition-key-path /transactionId \
            --throughput 1000 \
            || error_exit "Failed to create Transactions container"
    fi
    
    # Get Cosmos DB connection details
    export COSMOS_ENDPOINT=$(az cosmosdb show \
        --name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query documentEndpoint \
        --output tsv) || error_exit "Failed to get Cosmos DB endpoint"
    
    export COSMOS_KEY=$(az cosmosdb keys list \
        --name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryMasterKey \
        --output tsv) || error_exit "Failed to get Cosmos DB key"
    
    log_success "Cosmos DB deployed with global distribution enabled"
}

# Configure Key Vault
configure_key_vault() {
    log_info "Configuring Azure Key Vault for secure credential management..."
    
    # Check if Key Vault already exists
    if az keyvault show --name "$KEYVAULT_NAME" >/dev/null 2>&1; then
        log_warning "Key Vault '$KEYVAULT_NAME' already exists"
    else
        az keyvault create \
            --name "$KEYVAULT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku standard \
            --enable-rbac-authorization true \
            || error_exit "Failed to create Key Vault"
    fi
    
    # Store Cosmos DB connection string
    az keyvault secret set \
        --vault-name "$KEYVAULT_NAME" \
        --name "CosmosDBConnectionString" \
        --value "AccountEndpoint=${COSMOS_ENDPOINT};AccountKey=${COSMOS_KEY};" \
        || log_warning "Failed to store Cosmos DB connection string"
    
    # Store Ledger endpoint
    az keyvault secret set \
        --vault-name "$KEYVAULT_NAME" \
        --name "LedgerEndpoint" \
        --value "$LEDGER_ENDPOINT" \
        || log_warning "Failed to store Ledger endpoint"
    
    # Create managed identity for Logic Apps
    export LOGIC_APP_IDENTITY=$(az identity create \
        --name "logic-app-identity-${RANDOM_SUFFIX}" \
        --resource-group "$RESOURCE_GROUP" \
        --query id \
        --output tsv) || error_exit "Failed to create managed identity"
    
    # Grant Logic Apps access to Key Vault
    local principal_id=$(az identity show \
        --ids "$LOGIC_APP_IDENTITY" \
        --query principalId \
        --output tsv)
    
    local keyvault_id=$(az keyvault show \
        --name "$KEYVAULT_NAME" \
        --query id \
        --output tsv)
    
    az role assignment create \
        --role "Key Vault Secrets User" \
        --assignee-object-id "$principal_id" \
        --scope "$keyvault_id" \
        || log_warning "Failed to assign Key Vault access role"
    
    log_success "Key Vault configured with secure credential storage"
}

# Deploy Event Grid
deploy_event_grid() {
    log_info "Deploying Event Grid for real-time event distribution..."
    
    # Check if Event Grid topic already exists
    if az eventgrid topic show --name "$EVENT_GRID_TOPIC" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Event Grid topic '$EVENT_GRID_TOPIC' already exists"
    else
        az eventgrid topic create \
            --name "$EVENT_GRID_TOPIC" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --input-schema eventgridschema \
            --public-network-access enabled \
            || error_exit "Failed to create Event Grid topic"
    fi
    
    # Get Event Grid endpoint and key
    export EVENT_GRID_ENDPOINT=$(az eventgrid topic show \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query endpoint \
        --output tsv) || error_exit "Failed to get Event Grid endpoint"
    
    export EVENT_GRID_KEY=$(az eventgrid topic key list \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 \
        --output tsv) || error_exit "Failed to get Event Grid key"
    
    log_success "Event Grid deployed for real-time event distribution"
}

# Create Logic Apps
create_logic_apps() {
    log_info "Creating Logic Apps for blockchain orchestration..."
    
    # Check if Logic App already exists
    if az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Logic App '$LOGIC_APP_NAME' already exists"
    else
        az logic workflow create \
            --name "$LOGIC_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --mi-user-assigned "$LOGIC_APP_IDENTITY" \
            || error_exit "Failed to create Logic App"
    fi
    
    # Create workflow definition
    cat > /tmp/workflow-definition.json << EOF
{
  "definition": {
    "\$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
    "contentVersion": "1.0.0.0",
    "triggers": {
      "When_a_HTTP_request_is_received": {
        "type": "Request",
        "kind": "Http",
        "inputs": {
          "method": "POST",
          "schema": {
            "type": "object",
            "properties": {
              "transactionId": { "type": "string" },
              "productId": { "type": "string" },
              "action": { "type": "string" },
              "timestamp": { "type": "string" },
              "location": { "type": "string" },
              "participant": { "type": "string" },
              "metadata": { "type": "object" }
            }
          }
        }
      }
    },
    "actions": {
      "Record_to_Confidential_Ledger": {
        "type": "Http",
        "inputs": {
          "method": "POST",
          "uri": "@{parameters('ledgerEndpoint')}/app/transactions",
          "headers": {
            "Content-Type": "application/json"
          },
          "body": "@triggerBody()",
          "authentication": {
            "type": "ManagedServiceIdentity"
          }
        }
      },
      "Store_in_Cosmos_DB": {
        "type": "Http",
        "inputs": {
          "method": "POST",
          "uri": "@{parameters('cosmosEndpoint')}/dbs/SupplyChainDB/colls/Transactions/docs",
          "headers": {
            "Content-Type": "application/json",
            "Authorization": "@{parameters('cosmosKey')}"
          },
          "body": "@triggerBody()"
        },
        "runAfter": {
          "Record_to_Confidential_Ledger": ["Succeeded"]
        }
      },
      "Publish_Event": {
        "type": "Http",
        "inputs": {
          "method": "POST",
          "uri": "@{parameters('eventGridEndpoint')}",
          "headers": {
            "aeg-sas-key": "@{parameters('eventGridKey')}",
            "Content-Type": "application/json"
          },
          "body": [{
            "id": "@{guid()}",
            "eventType": "@{triggerBody()['action']}",
            "subject": "supplychain/products/@{triggerBody()['productId']}",
            "eventTime": "@{utcNow()}",
            "data": "@triggerBody()"
          }]
        },
        "runAfter": {
          "Store_in_Cosmos_DB": ["Succeeded"]
        }
      }
    }
  }
}
EOF
    
    # Update Logic App with workflow
    az logic workflow update \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --definition @/tmp/workflow-definition.json \
        || log_warning "Failed to update Logic App workflow"
    
    # Clean up temporary file
    rm -f /tmp/workflow-definition.json
    
    log_success "Logic Apps workflow created for blockchain orchestration"
}

# Deploy API Management
deploy_api_management() {
    if [[ "$SKIP_APIM" == "true" ]]; then
        log_warning "Skipping API Management deployment (--skip-apim flag)"
        return
    fi
    
    log_info "Deploying API Management for partner integration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy API Management: $APIM_NAME (takes 20-30 minutes)"
        return
    fi
    
    # Check if API Management already exists
    if az apim show --name "$APIM_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "API Management '$APIM_NAME' already exists"
        return 0
    fi
    
    # Create API Management instance (Consumption tier for demo)
    log_warning "Creating API Management instance (this may take 20-30 minutes)..."
    az apim create \
        --name "$APIM_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --publisher-name "SupplyChainDemo" \
        --publisher-email "admin@supplychain.demo" \
        --sku-name Consumption \
        --no-wait \
        || log_warning "Failed to create API Management instance"
    
    log_info "API Management deployment initiated (continuing with other resources)"
}

# Configure Storage
configure_storage() {
    log_info "Configuring Storage for document attachments..."
    
    # Check if storage account already exists
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Storage account '$STORAGE_ACCOUNT' already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --hierarchical-namespace false \
            || error_exit "Failed to create storage account"
    fi
    
    # Create containers
    az storage container create \
        --name documents \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login \
        --public-access off \
        || log_warning "Failed to create documents container"
    
    az storage container create \
        --name certificates \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login \
        --public-access off \
        || log_warning "Failed to create certificates container"
    
    # Enable versioning
    az storage account blob-service-properties update \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --enable-versioning true \
        --enable-change-feed true \
        || log_warning "Failed to enable versioning"
    
    log_success "Storage configured for document management"
}

# Implement monitoring
implement_monitoring() {
    log_info "Implementing monitoring and analytics..."
    
    # Create Application Insights
    if ! az monitor app-insights component show --app supply-chain-insights --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        az monitor app-insights component create \
            --app supply-chain-insights \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind web \
            || log_warning "Failed to create Application Insights"
    fi
    
    # Create Log Analytics workspace
    if ! az monitor log-analytics workspace show --workspace-name supply-chain-logs --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        az monitor log-analytics workspace create \
            --workspace-name supply-chain-logs \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            || log_warning "Failed to create Log Analytics workspace"
    fi
    
    log_success "Monitoring and analytics configured"
}

# Display deployment summary
display_summary() {
    log_success "=== Deployment Summary ==="
    echo
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Confidential Ledger: $LEDGER_NAME"
    log_info "Cosmos DB Account: $COSMOS_ACCOUNT"
    log_info "Storage Account: $STORAGE_ACCOUNT"
    log_info "Key Vault: $KEYVAULT_NAME"
    log_info "Logic App: $LOGIC_APP_NAME"
    log_info "Event Grid Topic: $EVENT_GRID_TOPIC"
    log_info "API Management: $APIM_NAME"
    echo
    log_info "Ledger Endpoint: $LEDGER_ENDPOINT"
    log_info "Cosmos Endpoint: $COSMOS_ENDPOINT"
    echo
    log_success "Supply chain blockchain solution deployed successfully!"
    echo
    log_warning "Note: API Management may still be deploying. Check the Azure portal for status."
    log_warning "Estimated monthly cost: \$200-300 for development environment"
}

# Validation function
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return
    fi
    
    local validation_errors=0
    
    # Check Confidential Ledger
    if az confidentialledger show --name "$LEDGER_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        local ledger_state=$(az confidentialledger show \
            --name "$LEDGER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query properties.provisioningState \
            --output tsv)
        
        if [[ "$ledger_state" == "Succeeded" ]]; then
            log_success "Confidential Ledger is ready"
        else
            log_warning "Confidential Ledger state: $ledger_state"
            ((validation_errors++))
        fi
    else
        log_error "Confidential Ledger not found"
        ((validation_errors++))
    fi
    
    # Check Cosmos DB
    if az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        local cosmos_state=$(az cosmosdb show \
            --name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --query provisioningState \
            --output tsv)
        
        if [[ "$cosmos_state" == "Succeeded" ]]; then
            log_success "Cosmos DB is ready"
        else
            log_warning "Cosmos DB state: $cosmos_state"
            ((validation_errors++))
        fi
    else
        log_error "Cosmos DB not found"
        ((validation_errors++))
    fi
    
    # Check Key Vault
    if az keyvault show --name "$KEYVAULT_NAME" >/dev/null 2>&1; then
        local kv_state=$(az keyvault show \
            --name "$KEYVAULT_NAME" \
            --query properties.provisioningState \
            --output tsv)
        
        if [[ "$kv_state" == "Succeeded" ]]; then
            log_success "Key Vault is ready"
        else
            log_warning "Key Vault state: $kv_state"
            ((validation_errors++))
        fi
    else
        log_error "Key Vault not found"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log_success "All core resources validated successfully"
    else
        log_warning "Validation completed with $validation_errors warnings/errors"
    fi
}

# Display summary
display_summary() {
    log_success "=== Deployment Summary ==="
    echo
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Random Suffix: $RANDOM_SUFFIX"
    echo
    log_info "Deployed Resources:"
    log_info "- Confidential Ledger: $LEDGER_NAME"
    log_info "- Cosmos DB Account: $COSMOS_ACCOUNT"
    log_info "- Key Vault: $KEYVAULT_NAME"
    log_info "- Logic App: $LOGIC_APP_NAME"
    log_info "- Event Grid Topic: $EVENT_GRID_TOPIC"
    log_info "- Storage Account: $STORAGE_ACCOUNT"
    log_info "- Application Insights: $APPINSIGHTS_NAME"
    log_info "- Log Analytics Workspace: $WORKSPACE_NAME"
    if [[ "$SKIP_APIM" != "true" ]]; then
        log_info "- API Management: $APIM_NAME (may still be deploying)"
    fi
    echo
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Configuration saved to: deployment-config.json"
        echo
        log_info "Next Steps:"
        log_info "1. Wait for all resources to be fully deployed"
        log_info "2. Test the Logic App endpoint"
        log_info "3. Configure additional monitoring as needed"
        log_info "4. Review the cleanup script: destroy.sh"
        echo
    fi
    log_warning "Estimated monthly cost: \$200-300 USD for development environment"
}

# Main deployment function
main() {
    log_info "Starting Azure Blockchain Supply Chain Transparency deployment..."
    echo
    
    validate_prerequisites
    set_environment_variables
    
    if [[ "$DRY_RUN" != "true" ]]; then
        save_deployment_config
    fi
    
    create_resource_group
    create_azure_ad_app
    create_confidential_ledger
    deploy_cosmos_db
    configure_key_vault
    deploy_event_grid
    create_logic_apps
    deploy_api_management
    configure_storage
    implement_monitoring
    
    if [[ "$DRY_RUN" != "true" ]]; then
        validate_deployment
    fi
    
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Error handling
trap 'error_exit "Deployment failed at line $LINENO"' ERR

# Run main function
main "$@"