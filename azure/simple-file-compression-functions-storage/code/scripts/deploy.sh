#!/bin/bash

#######################################################################
# Azure File Compression with Functions and Storage - Deployment Script
#######################################################################
# 
# This script deploys a serverless file compression solution using:
# - Azure Functions with Event Grid blob triggers
# - Azure Blob Storage containers for input/output
# - Event Grid system topic and subscription
#
# Recipe: Simple File Compression with Functions and Storage
# Category: Serverless
# Difficulty: 100 (Beginner)
#######################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if zip command exists
    if ! command_exists zip; then
        error "zip command is not available. Please install zip utility."
        exit 1
    fi
    
    # Check if openssl exists for random string generation
    if ! command_exists openssl; then
        error "openssl command is not available. Please install openssl."
        exit 1
    fi
    
    success "Prerequisites validated successfully"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set default values
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-recipe-$(openssl rand -hex 3)}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names with unique identifiers
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-compress${RANDOM_SUFFIX}}"
    export FUNCTION_APP="${FUNCTION_APP:-file-compressor-${RANDOM_SUFFIX}}"
    
    log "Environment configured:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Location: ${LOCATION}"
    log "  Storage Account: ${STORAGE_ACCOUNT}"
    log "  Function App: ${FUNCTION_APP}"
    log "  Subscription ID: ${SUBSCRIPTION_ID}"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Resource group ${RESOURCE_GROUP} already exists, skipping creation"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=recipe environment=demo \
            --output none
        
        success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account: ${STORAGE_ACCOUNT}"
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Storage account ${STORAGE_ACCOUNT} already exists, skipping creation"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --https-only true \
            --output none
        
        success "Storage account created: ${STORAGE_ACCOUNT}"
    fi
}

# Function to create blob containers
create_blob_containers() {
    log "Creating blob containers..."
    
    # Create container for uploaded raw files
    if az storage container show --name raw-files --account-name "${STORAGE_ACCOUNT}" --auth-mode login >/dev/null 2>&1; then
        warn "Container 'raw-files' already exists, skipping creation"
    else
        az storage container create \
            --name raw-files \
            --account-name "${STORAGE_ACCOUNT}" \
            --auth-mode login \
            --output none
        
        success "Container 'raw-files' created"
    fi
    
    # Create container for compressed output files
    if az storage container show --name compressed-files --account-name "${STORAGE_ACCOUNT}" --auth-mode login >/dev/null 2>&1; then
        warn "Container 'compressed-files' already exists, skipping creation"
    else
        az storage container create \
            --name compressed-files \
            --account-name "${STORAGE_ACCOUNT}" \
            --auth-mode login \
            --output none
        
        success "Container 'compressed-files' created"
    fi
}

# Function to create function app
create_function_app() {
    log "Creating Function App: ${FUNCTION_APP}"
    
    if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Function App ${FUNCTION_APP} already exists, skipping creation"
    else
        # Create Function App with Python runtime
        az functionapp create \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime python \
            --runtime-version 3.11 \
            --functions-version 4 \
            --os-type Linux \
            --output none
        
        success "Function App created: ${FUNCTION_APP}"
    fi
}

# Function to configure function app settings
configure_function_app() {
    log "Configuring Function App settings..."
    
    # Get storage account connection string
    STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString \
        --output tsv)
    
    # Configure Function App with storage connection
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "AzureWebJobsStorage=${STORAGE_CONNECTION}" \
                   "STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION}" \
        --output none
    
    success "Function App configured with storage access"
}

# Function to create and deploy function code
deploy_function_code() {
    log "Creating and deploying function code..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Create function_app.py for Python v2 programming model
    cat > function_app.py << 'EOF'
import logging
import gzip
import azure.functions as func

app = func.FunctionApp()

@app.blob_trigger(
    arg_name="inputblob",
    path="raw-files/{name}",
    connection="STORAGE_CONNECTION_STRING",
    source="EventGrid"
)
@app.blob_output(
    arg_name="outputblob",
    path="compressed-files/{name}.gz",
    connection="STORAGE_CONNECTION_STRING"
)
def BlobTrigger(inputblob: func.InputStream, outputblob: func.Out[bytes]) -> None:
    """
    Compress uploaded files using gzip compression.
    
    Args:
        inputblob: Input blob from raw-files container
        outputblob: Output blob to compressed-files container
    """
    logging.info(f"Processing file: {inputblob.name}")
    
    try:
        # Read the input file content
        file_content = inputblob.read()
        logging.info(f"Read {len(file_content)} bytes from input file")
        
        # Compress the content using gzip
        compressed_content = gzip.compress(file_content)
        compression_ratio = len(compressed_content) / len(file_content)
        
        logging.info(f"Compressed to {len(compressed_content)} bytes "
                    f"(ratio: {compression_ratio:.2f})")
        
        # Write compressed content to output blob
        outputblob.set(compressed_content)
        
        logging.info(f"Successfully compressed {inputblob.name}")
        
    except Exception as e:
        logging.error(f"Error compressing file {inputblob.name}: {str(e)}")
        raise
EOF
    
    # Create requirements.txt for Python dependencies
    cat > requirements.txt << 'EOF'
azure-functions>=1.18.0
EOF
    
    # Create deployment package with all function files
    zip -r function.zip function_app.py requirements.txt >/dev/null 2>&1
    
    # Deploy function code to Azure
    az functionapp deployment source config-zip \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --src function.zip \
        --output none
    
    # Wait for deployment to complete
    log "Waiting for function deployment to complete..."
    sleep 30
    
    # Clean up temporary directory
    cd - >/dev/null
    rm -rf "${TEMP_DIR}"
    
    success "Function code deployed successfully"
}

# Function to create Event Grid system topic
create_event_grid_topic() {
    log "Creating Event Grid system topic..."
    
    TOPIC_NAME="${STORAGE_ACCOUNT}-topic"
    
    if az eventgrid system-topic show --name "${TOPIC_NAME}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Event Grid system topic ${TOPIC_NAME} already exists, skipping creation"
    else
        # Create Event Grid system topic for the storage account
        az eventgrid system-topic create \
            --name "${TOPIC_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --topic-type Microsoft.Storage.StorageAccounts \
            --source "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
            --output none
        
        success "Event Grid system topic created: ${TOPIC_NAME}"
    fi
}

# Function to create Event Grid subscription
create_event_grid_subscription() {
    log "Creating Event Grid subscription..."
    
    TOPIC_NAME="${STORAGE_ACCOUNT}-topic"
    SUBSCRIPTION_NAME="blob-compression-subscription"
    
    if az eventgrid system-topic event-subscription show --name "${SUBSCRIPTION_NAME}" --system-topic-name "${TOPIC_NAME}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Event Grid subscription ${SUBSCRIPTION_NAME} already exists, skipping creation"
    else
        # Get the Function App's blob extension endpoint
        FUNCTION_KEY=$(az functionapp keys list \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query "systemKeys.blobs_extension" \
            --output tsv)
        
        # Create Event Grid subscription to trigger the function
        az eventgrid system-topic event-subscription create \
            --name "${SUBSCRIPTION_NAME}" \
            --system-topic-name "${TOPIC_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --endpoint-type webhook \
            --endpoint "https://${FUNCTION_APP}.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.BlobTrigger&code=${FUNCTION_KEY}" \
            --included-event-types Microsoft.Storage.BlobCreated \
            --subject-begins-with "/blobServices/default/containers/raw-files/" \
            --output none
        
        success "Event Grid subscription created: ${SUBSCRIPTION_NAME}"
    fi
}

# Function to test the deployment
test_deployment() {
    log "Testing deployment with sample file..."
    
    # Create a test file with sample content
    TEST_FILE="test-file-$(date +%s).txt"
    echo "This is a test file for compression testing. \
It contains sample text that will be compressed using gzip. \
The compression ratio depends on file content and size. \
Generated at: $(date)" > "${TEST_FILE}"
    
    # Upload test file to trigger compression
    az storage blob upload \
        --account-name "${STORAGE_ACCOUNT}" \
        --container-name raw-files \
        --name "${TEST_FILE}" \
        --file "${TEST_FILE}" \
        --auth-mode login \
        --output none
    
    success "Test file uploaded: ${TEST_FILE}"
    
    # Wait for function execution
    log "Waiting for function execution (20 seconds)..."
    sleep 20
    
    # Check if compressed file was created
    if az storage blob show --account-name "${STORAGE_ACCOUNT}" --container-name compressed-files --name "${TEST_FILE}.gz" --auth-mode login >/dev/null 2>&1; then
        success "Compressed file created successfully: ${TEST_FILE}.gz"
    else
        warn "Compressed file not found yet. The function may still be processing or there may be an issue."
        log "Check Function App logs for more details: az functionapp logs tail --name ${FUNCTION_APP} --resource-group ${RESOURCE_GROUP}"
    fi
    
    # Clean up local test file
    rm -f "${TEST_FILE}"
}

# Function to display deployment summary
display_summary() {
    success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    log "Resources created:"
    log "  • Resource Group: ${RESOURCE_GROUP}"
    log "  • Storage Account: ${STORAGE_ACCOUNT}"
    log "  • Function App: ${FUNCTION_APP}"
    log "  • Event Grid Topic: ${STORAGE_ACCOUNT}-topic"
    log "  • Event Grid Subscription: blob-compression-subscription"
    echo
    log "Storage containers:"
    log "  • raw-files (input files)"
    log "  • compressed-files (compressed output)"
    echo
    log "To test the solution:"
    log "  1. Upload files to the 'raw-files' container"
    log "  2. Check the 'compressed-files' container for .gz files"
    echo
    log "Useful commands:"
    log "  • View Function logs: az functionapp logs tail --name ${FUNCTION_APP} --resource-group ${RESOURCE_GROUP}"
    log "  • List raw files: az storage blob list --account-name ${STORAGE_ACCOUNT} --container-name raw-files --auth-mode login --output table"
    log "  • List compressed files: az storage blob list --account-name ${STORAGE_ACCOUNT} --container-name compressed-files --auth-mode login --output table"
    echo
    log "Environment variables for cleanup:"
    log "  export RESOURCE_GROUP='${RESOURCE_GROUP}'"
    log "  export STORAGE_ACCOUNT='${STORAGE_ACCOUNT}'"
    log "  export FUNCTION_APP='${FUNCTION_APP}'"
    echo
}

# Function to handle script interruption
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        error "Deployment failed. Check the error messages above."
        log "To clean up any partially created resources, run:"
        log "  ./destroy.sh"
    fi
}

# Main deployment function
main() {
    log "Starting Azure File Compression deployment..."
    echo
    
    # Set up error handling
    trap cleanup_on_exit EXIT
    
    # Run deployment steps
    validate_prerequisites
    setup_environment
    create_resource_group
    create_storage_account
    create_blob_containers
    create_function_app
    configure_function_app
    deploy_function_code
    create_event_grid_topic
    create_event_grid_subscription
    test_deployment
    display_summary
    
    # Remove error trap on successful completion
    trap - EXIT
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being executed directly
    main "$@"
fi