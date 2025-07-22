#!/bin/bash

# =============================================================================
# Azure Invoice Processing Workflow Deployment Script
# =============================================================================
# This script deploys the complete invoice processing solution using:
# - Azure Blob Storage for document storage
# - Azure AI Document Intelligence for invoice data extraction
# - Azure Logic Apps for workflow orchestration
# - Azure Service Bus for enterprise integration
# - Azure Functions for additional processing capabilities
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# CONFIGURATION AND VALIDATION
# =============================================================================

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly REQUIRED_TOOLS=("az" "openssl" "curl" "jq")

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
cleanup_on_error() {
    error "Deployment failed. Check ${LOG_FILE} for details."
    warn "Run './destroy.sh' to clean up any partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# =============================================================================
# PREREQUISITES VALIDATION
# =============================================================================

validate_prerequisites() {
    info "Validating prerequisites..."
    
    # Check required tools
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "$tool is required but not installed"
            exit 1
        fi
    done
    
    # Check Azure CLI authentication
    if ! az account show &> /dev/null; then
        error "Azure CLI not authenticated. Run 'az login' first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv)
    info "Azure CLI version: ${az_version}"
    
    # Validate subscription access
    local subscription_id
    subscription_id=$(az account show --query id -o tsv)
    info "Using Azure subscription: ${subscription_id}"
    
    success "Prerequisites validation completed"
}

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================

setup_environment() {
    info "Setting up environment variables..."
    
    # Generate unique suffix
    readonly RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Azure configuration
    export RESOURCE_GROUP="rg-invoice-processing-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Resource names with proper Azure naming conventions
    export STORAGE_ACCOUNT="stinvoice${RANDOM_SUFFIX}"
    export DOC_INTELLIGENCE_NAME="di-invoice-${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="la-invoice-processor-${RANDOM_SUFFIX}"
    export SERVICE_BUS_NAMESPACE="sb-invoice-${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="fa-invoice-processor-${RANDOM_SUFFIX}"
    export CONTAINER_NAME="invoices"
    
    # Validation
    if [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
        error "Storage account name too long. Reduce RANDOM_SUFFIX length."
        exit 1
    fi
    
    # Create environment file for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
DOC_INTELLIGENCE_NAME=${DOC_INTELLIGENCE_NAME}
LOGIC_APP_NAME=${LOGIC_APP_NAME}
SERVICE_BUS_NAMESPACE=${SERVICE_BUS_NAMESPACE}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
CONTAINER_NAME=${CONTAINER_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    info "Resource Group: ${RESOURCE_GROUP}"
    info "Location: ${LOCATION}"
    info "Storage Account: ${STORAGE_ACCOUNT}"
    info "Random Suffix: ${RANDOM_SUFFIX}"
    
    success "Environment setup completed"
}

# =============================================================================
# AZURE RESOURCE DEPLOYMENT
# =============================================================================

create_resource_group() {
    info "Creating resource group..."
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=invoice-processing environment=demo owner="${USER:-system}" \
        --output table
    
    success "Resource group created: ${RESOURCE_GROUP}"
}

deploy_storage_account() {
    info "Deploying Azure Blob Storage..."
    
    # Create storage account
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --allow-blob-public-access false \
        --min-tls-version TLS1_2 \
        --https-only true \
        --output table
    
    # Get storage account key
    local storage_key
    storage_key=$(az storage account keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --account-name "${STORAGE_ACCOUNT}" \
        --query '[0].value' \
        --output tsv)
    
    export STORAGE_KEY="${storage_key}"
    echo "STORAGE_KEY=${storage_key}" >> "${SCRIPT_DIR}/.env"
    
    # Create container for invoices
    az storage container create \
        --name "${CONTAINER_NAME}" \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${storage_key}" \
        --public-access off \
        --output table
    
    # Create additional containers for processed documents
    az storage container create \
        --name "processed" \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${storage_key}" \
        --public-access off \
        --output table
    
    success "Storage account deployed with containers"
}

deploy_document_intelligence() {
    info "Deploying Azure AI Document Intelligence..."
    
    # Create AI Document Intelligence resource
    az cognitiveservices account create \
        --name "${DOC_INTELLIGENCE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --kind FormRecognizer \
        --sku S0 \
        --custom-domain "${DOC_INTELLIGENCE_NAME}" \
        --output table
    
    # Wait for deployment to complete
    info "Waiting for Document Intelligence service to be ready..."
    sleep 30
    
    # Get endpoint and key
    local doc_endpoint
    doc_endpoint=$(az cognitiveservices account show \
        --name "${DOC_INTELLIGENCE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.endpoint \
        --output tsv)
    
    local doc_key
    doc_key=$(az cognitiveservices account keys list \
        --name "${DOC_INTELLIGENCE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 \
        --output tsv)
    
    export DOC_INTELLIGENCE_ENDPOINT="${doc_endpoint}"
    export DOC_INTELLIGENCE_KEY="${doc_key}"
    
    echo "DOC_INTELLIGENCE_ENDPOINT=${doc_endpoint}" >> "${SCRIPT_DIR}/.env"
    echo "DOC_INTELLIGENCE_KEY=${doc_key}" >> "${SCRIPT_DIR}/.env"
    
    success "AI Document Intelligence service deployed"
    info "Endpoint: ${doc_endpoint}"
}

deploy_service_bus() {
    info "Deploying Azure Service Bus..."
    
    # Create Service Bus namespace
    az servicebus namespace create \
        --name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard \
        --output table
    
    # Wait for namespace to be ready
    info "Waiting for Service Bus namespace to be ready..."
    sleep 30
    
    # Create topic for invoice processing events
    az servicebus topic create \
        --name invoice-processing \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --max-size 1024 \
        --output table
    
    # Create queue for processed invoices
    az servicebus queue create \
        --name processed-invoices \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --max-delivery-count 10 \
        --message-time-to-live P14D \
        --lock-duration PT5M \
        --output table
    
    # Create subscription for topic
    az servicebus topic subscription create \
        --name invoice-processor \
        --topic-name invoice-processing \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --output table
    
    # Get connection string
    local connection_string
    connection_string=$(az servicebus namespace authorization-rule keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString \
        --output tsv)
    
    export SERVICE_BUS_CONNECTION="${connection_string}"
    echo "SERVICE_BUS_CONNECTION=${connection_string}" >> "${SCRIPT_DIR}/.env"
    
    success "Service Bus namespace created with topic and queue"
}

deploy_function_app() {
    info "Deploying Azure Function App..."
    
    # Create Function App
    az functionapp create \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime python \
        --runtime-version 3.11 \
        --functions-version 4 \
        --os-type Linux \
        --output table
    
    # Wait for Function App to be ready
    info "Waiting for Function App to be ready..."
    sleep 45
    
    # Configure app settings
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
            "DOCUMENT_INTELLIGENCE_ENDPOINT=${DOC_INTELLIGENCE_ENDPOINT}" \
            "DOCUMENT_INTELLIGENCE_KEY=${DOC_INTELLIGENCE_KEY}" \
            "SERVICE_BUS_CONNECTION=${SERVICE_BUS_CONNECTION}" \
            "STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT};AccountKey=${STORAGE_KEY};EndpointSuffix=core.windows.net" \
        --output table
    
    success "Function App created and configured"
}

deploy_logic_app() {
    info "Deploying Azure Logic App..."
    
    # Create basic Logic App (workflow will be configured separately)
    az logic workflow create \
        --name "${LOGIC_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --definition '{
          "$schema": "https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json",
          "contentVersion": "1.0.0.0",
          "parameters": {},
          "triggers": {},
          "actions": {}
        }' \
        --output table
    
    # Get Logic App details
    local logic_app_url
    logic_app_url=$(az logic workflow show \
        --name "${LOGIC_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query accessEndpoint \
        --output tsv)
    
    export LOGIC_APP_URL="${logic_app_url}"
    echo "LOGIC_APP_URL=${logic_app_url}" >> "${SCRIPT_DIR}/.env"
    
    success "Logic App created successfully"
    info "Logic App URL: ${logic_app_url}"
}

configure_event_grid() {
    info "Configuring Event Grid integration..."
    
    # Create Event Grid system topic for storage events
    az eventgrid system-topic create \
        --name "storage-events-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --topic-type Microsoft.Storage.StorageAccounts \
        --source "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
        --output table
    
    # Enable blob change events on storage account
    az storage account blob-service-properties update \
        --account-name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --change-feed-enabled true \
        --versioning-enabled true \
        --output table
    
    success "Event Grid integration configured"
}

create_api_connections() {
    info "Creating API connections for Logic App..."
    
    # Create blob storage connection
    az resource create \
        --resource-group "${RESOURCE_GROUP}" \
        --resource-type Microsoft.Web/connections \
        --name "blob-connection-${RANDOM_SUFFIX}" \
        --properties '{
          "displayName": "Blob Storage Connection",
          "api": {
            "id": "/subscriptions/'${SUBSCRIPTION_ID}'/providers/Microsoft.Web/locations/'${LOCATION}'/managedApis/azureblob"
          },
          "parameterValues": {
            "accountName": "'${STORAGE_ACCOUNT}'",
            "accessKey": "'${STORAGE_KEY}'"
          }
        }' \
        --output table
    
    # Create Service Bus connection
    az resource create \
        --resource-group "${RESOURCE_GROUP}" \
        --resource-type Microsoft.Web/connections \
        --name "servicebus-connection-${RANDOM_SUFFIX}" \
        --properties '{
          "displayName": "Service Bus Connection",
          "api": {
            "id": "/subscriptions/'${SUBSCRIPTION_ID}'/providers/Microsoft.Web/locations/'${LOCATION}'/managedApis/servicebus"
          },
          "parameterValues": {
            "connectionString": "'${SERVICE_BUS_CONNECTION}'"
          }
        }' \
        --output table
    
    success "API connections created for Logic App"
}

# =============================================================================
# DEPLOYMENT VALIDATION
# =============================================================================

validate_deployment() {
    info "Validating deployment..."
    
    # Check resource group
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        error "Resource group validation failed"
        return 1
    fi
    
    # Check storage account
    if ! az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        error "Storage account validation failed"
        return 1
    fi
    
    # Check Document Intelligence service
    if ! az cognitiveservices account show --name "${DOC_INTELLIGENCE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        error "Document Intelligence service validation failed"
        return 1
    fi
    
    # Check Service Bus namespace
    if ! az servicebus namespace show --name "${SERVICE_BUS_NAMESPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        error "Service Bus namespace validation failed"
        return 1
    fi
    
    # Check Function App
    if ! az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        error "Function App validation failed"
        return 1
    fi
    
    # Check Logic App
    if ! az logic workflow show --name "${LOGIC_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        error "Logic App validation failed"
        return 1
    fi
    
    success "All resources validated successfully"
}

create_test_invoice() {
    info "Creating test invoice for validation..."
    
    # Create a simple test invoice content
    cat > "${SCRIPT_DIR}/test-invoice.pdf" << 'EOF'
%PDF-1.4
1 0 obj
<<
/Type /Catalog
/Pages 2 0 R
>>
endobj

2 0 obj
<<
/Type /Pages
/Kids [3 0 R]
/Count 1
>>
endobj

3 0 obj
<<
/Type /Page
/Parent 2 0 R
/MediaBox [0 0 612 792]
/Contents 4 0 R
>>
endobj

4 0 obj
<<
/Length 44
>>
stream
BT
/F1 12 Tf
72 720 Td
(Test Invoice - Amount: $500) Tj
ET
endstream
endobj

xref
0 5
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000205 00000 n 
trailer
<<
/Size 5
/Root 1 0 R
>>
startxref
299
%%EOF
EOF
    
    # Upload test invoice
    az storage blob upload \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${STORAGE_KEY}" \
        --container-name "${CONTAINER_NAME}" \
        --name "test-invoice-$(date +%Y%m%d-%H%M%S).pdf" \
        --file "${SCRIPT_DIR}/test-invoice.pdf" \
        --output table
    
    success "Test invoice uploaded to storage"
}

# =============================================================================
# MAIN DEPLOYMENT FLOW
# =============================================================================

main() {
    info "Starting Azure Invoice Processing Workflow deployment..."
    info "Log file: ${LOG_FILE}"
    
    # Deployment steps
    validate_prerequisites
    setup_environment
    create_resource_group
    deploy_storage_account
    deploy_document_intelligence
    deploy_service_bus
    deploy_function_app
    deploy_logic_app
    configure_event_grid
    create_api_connections
    validate_deployment
    create_test_invoice
    
    # Deployment summary
    success "==================================="
    success "DEPLOYMENT COMPLETED SUCCESSFULLY"
    success "==================================="
    info ""
    info "Resource Group: ${RESOURCE_GROUP}"
    info "Storage Account: ${STORAGE_ACCOUNT}"
    info "Document Intelligence: ${DOC_INTELLIGENCE_NAME}"
    info "Service Bus Namespace: ${SERVICE_BUS_NAMESPACE}"
    info "Function App: ${FUNCTION_APP_NAME}"
    info "Logic App: ${LOGIC_APP_NAME}"
    info ""
    info "Environment variables saved to: ${SCRIPT_DIR}/.env"
    info "Log file: ${LOG_FILE}"
    info ""
    warn "NEXT STEPS:"
    warn "1. Configure Logic App workflow through Azure Portal"
    warn "2. Test invoice processing with sample documents"
    warn "3. Set up approval email addresses and business rules"
    warn "4. Configure integration with ERP systems"
    info ""
    warn "COST REMINDER:"
    warn "This deployment creates billable Azure resources."
    warn "Run './destroy.sh' when done to avoid ongoing charges."
    info ""
    success "Deployment completed in $((SECONDS / 60)) minutes and $((SECONDS % 60)) seconds"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi