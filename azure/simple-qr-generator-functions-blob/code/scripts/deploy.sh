#!/bin/bash

# Azure QR Code Generator - Deployment Script
# This script deploys Azure Functions and Blob Storage for QR code generation
# Prerequisites: Azure CLI installed and authenticated

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        log_info "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. JSON output will be less readable."
        JQ_AVAILABLE=false
    else
        JQ_AVAILABLE=true
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        log_error "zip command is not available. Required for function deployment."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get current subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    log_info "Using subscription: $SUBSCRIPTION_ID"
    
    # Set default region if not provided
    export LOCATION=${AZURE_LOCATION:-"eastus"}
    log_info "Using location: $LOCATION"
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        if command -v openssl &> /dev/null; then
            export RANDOM_SUFFIX=$(openssl rand -hex 3)
        else
            # Fallback for systems without openssl
            export RANDOM_SUFFIX=$(date +%s | tail -c 6)
        fi
    fi
    
    # Set resource names with unique suffix
    export RESOURCE_GROUP="rg-qr-generator-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stqrgen${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-qr-generator-${RANDOM_SUFFIX}"
    export CONTAINER_NAME="qr-codes"
    
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Storage Account: $STORAGE_ACCOUNT"
    log_info "Function App: $FUNCTION_APP"
    log_info "Random Suffix: $RANDOM_SUFFIX"
    
    # Save configuration to file for cleanup script
    cat > ./.azure-qr-config << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
FUNCTION_APP=$FUNCTION_APP
CONTAINER_NAME=$CONTAINER_NAME
LOCATION=$LOCATION
RANDOM_SUFFIX=$RANDOM_SUFFIX
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
EOF
    
    log_success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    # Check if resource group already exists
    if az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo project=qr-generator \
            --output table
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    
    # Check if storage account already exists
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Storage account $STORAGE_ACCOUNT already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --min-tls-version TLS1_2 \
            --allow-blob-public-access true \
            --output table
        
        log_success "Storage account created: $STORAGE_ACCOUNT"
    fi
    
    # Get storage connection string
    export STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    log_info "Storage connection string retrieved"
}

# Function to create blob container
create_blob_container() {
    log_info "Creating blob container: $CONTAINER_NAME"
    
    # Check if container already exists
    if az storage container exists \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --connection-string "$STORAGE_CONNECTION" \
        --query exists --output tsv | grep -q "true"; then
        log_warning "Container $CONTAINER_NAME already exists"
    else
        az storage container create \
            --name "$CONTAINER_NAME" \
            --account-name "$STORAGE_ACCOUNT" \
            --public-access blob \
            --connection-string "$STORAGE_CONNECTION" \
            --output table
        
        log_success "Blob container created: $CONTAINER_NAME"
    fi
}

# Function to create Function App
create_function_app() {
    log_info "Creating Function App: $FUNCTION_APP"
    
    # Check if function app already exists
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Function App $FUNCTION_APP already exists"
    else
        az functionapp create \
            --resource-group "$RESOURCE_GROUP" \
            --consumption-plan-location "$LOCATION" \
            --runtime python \
            --runtime-version 3.11 \
            --functions-version 4 \
            --name "$FUNCTION_APP" \
            --storage-account "$STORAGE_ACCOUNT" \
            --os-type Linux \
            --output table
        
        log_success "Function App created: $FUNCTION_APP"
    fi
}

# Function to configure Function App settings
configure_function_settings() {
    log_info "Configuring Function App settings..."
    
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings "STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION" \
                   "BLOB_CONTAINER_NAME=$CONTAINER_NAME" \
        --output table
    
    log_success "Function App settings configured"
}

# Function to prepare function code
prepare_function_code() {
    log_info "Preparing function code..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Create host.json
    cat > host.json << 'EOF'
{
    "version": "2.0",
    "extensionBundle": {
        "id": "Microsoft.Azure.Functions.ExtensionBundle",
        "version": "[4.*, 5.0.0)"
    },
    "functionTimeout": "00:05:00"
}
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
azure-functions
azure-storage-blob
qrcode[pil]
pillow
EOF
    
    # Create function_app.py
    cat > function_app.py << 'EOF'
import azure.functions as func
import logging
import json
import qrcode
import io
import os
from datetime import datetime
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

@app.route(route="generate-qr", methods=["POST"])
def generate_qr_code(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('QR Code generation request received.')
    
    try:
        # Parse request body
        req_body = req.get_json()
        if not req_body or 'text' not in req_body:
            return func.HttpResponse(
                json.dumps({"error": "Please provide 'text' in request body"}),
                status_code=400,
                headers={"Content-Type": "application/json"}
            )
        
        text_input = req_body['text']
        if not text_input.strip():
            return func.HttpResponse(
                json.dumps({"error": "Text input cannot be empty"}),
                status_code=400,
                headers={"Content-Type": "application/json"}
            )
        
        # Generate QR code
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(text_input)
        qr.make(fit=True)
        
        # Create QR code image
        img = qr.make_image(fill_color="black", back_color="white")
        
        # Convert image to bytes
        img_bytes = io.BytesIO()
        img.save(img_bytes, format='PNG')
        img_bytes.seek(0)
        
        # Generate unique filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"qr_code_{timestamp}.png"
        
        # Upload to blob storage
        connection_string = os.environ.get('STORAGE_CONNECTION_STRING')
        container_name = os.environ.get('BLOB_CONTAINER_NAME', 'qr-codes')
        
        blob_service_client = BlobServiceClient.from_connection_string(connection_string)
        blob_client = blob_service_client.get_blob_client(
            container=container_name, 
            blob=filename
        )
        
        blob_client.upload_blob(img_bytes.getvalue(), overwrite=True)
        
        # Get blob URL
        blob_url = blob_client.url
        
        logging.info(f'QR code generated and saved: {filename}')
        
        return func.HttpResponse(
            json.dumps({
                "success": True,
                "filename": filename,
                "url": blob_url,
                "text": text_input
            }),
            headers={"Content-Type": "application/json"}
        )
        
    except Exception as e:
        logging.error(f'Error generating QR code: {str(e)}')
        return func.HttpResponse(
            json.dumps({"error": f"Failed to generate QR code: {str(e)}"}),
            status_code=500,
            headers={"Content-Type": "application/json"}
        )
EOF
    
    # Create deployment package
    zip -r function-package.zip . > /dev/null
    
    # Move package to original directory
    mv function-package.zip "$OLDPWD/"
    cd "$OLDPWD"
    
    # Clean up temporary directory
    rm -rf "$TEMP_DIR"
    
    export FUNCTION_PACKAGE="./function-package.zip"
    log_success "Function code prepared: $FUNCTION_PACKAGE"
}

# Function to deploy function code
deploy_function_code() {
    log_info "Deploying function code to Azure..."
    
    az functionapp deployment source config-zip \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP" \
        --src "$FUNCTION_PACKAGE" \
        --build-remote true \
        --output table
    
    log_info "Waiting for deployment to complete..."
    sleep 45
    
    # Get function URL
    export FUNCTION_URL="https://${FUNCTION_APP}.azurewebsites.net"
    
    log_success "Function deployed successfully"
    log_info "Function URL: ${FUNCTION_URL}/api/generate-qr"
    
    # Save function URL to config file
    echo "FUNCTION_URL=$FUNCTION_URL" >> ./.azure-qr-config
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Function App status
    local app_state=$(az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query state \
        --output tsv)
    
    if [[ "$app_state" == "Running" ]]; then
        log_success "Function App is running"
    else
        log_warning "Function App state: $app_state"
    fi
    
    # Test QR code generation endpoint
    log_info "Testing QR code generation endpoint..."
    
    local test_response
    if test_response=$(curl -s -X POST "${FUNCTION_URL}/api/generate-qr" \
        -H "Content-Type: application/json" \
        -d '{"text": "Hello Azure Functions Deployment Test!"}' \
        --max-time 30); then
        
        if $JQ_AVAILABLE; then
            echo "$test_response" | jq '.'
        else
            echo "$test_response"
        fi
        
        if echo "$test_response" | grep -q '"success":true'; then
            log_success "QR code generation test passed"
        else
            log_warning "QR code generation test may have failed"
        fi
    else
        log_warning "Could not test QR code generation endpoint (endpoint may still be starting up)"
    fi
    
    # List storage contents
    log_info "Checking blob storage contents..."
    az storage blob list \
        --container-name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --connection-string "$STORAGE_CONNECTION" \
        --output table || log_warning "Could not list blob contents"
}

# Function to display deployment summary
deployment_summary() {
    log_info "=== DEPLOYMENT SUMMARY ==="
    echo
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Function App: $FUNCTION_APP"
    echo "Container Name: $CONTAINER_NAME"
    echo "Function URL: ${FUNCTION_URL}/api/generate-qr"
    echo
    echo "Test the QR generator with:"
    echo "curl -X POST '${FUNCTION_URL}/api/generate-qr' \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -d '{\"text\": \"Your text here\"}'"
    echo
    echo "Configuration saved to: ./.azure-qr-config"
    echo "Use ./destroy.sh to clean up resources"
    echo
    log_success "Deployment completed successfully!"
}

# Function to handle cleanup on error
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    
    # Remove function package if it exists
    [[ -f "$FUNCTION_PACKAGE" ]] && rm -f "$FUNCTION_PACKAGE"
    
    # Note: We don't auto-delete Azure resources on error to allow investigation
    log_info "Azure resources left for investigation. Run ./destroy.sh to clean up."
}

# Main deployment function
main() {
    log_info "Starting Azure QR Code Generator deployment..."
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_resource_group
    create_storage_account
    create_blob_container
    create_function_app
    configure_function_settings
    prepare_function_code
    deploy_function_code
    validate_deployment
    deployment_summary
    
    # Clean up temporary files
    [[ -f "$FUNCTION_PACKAGE" ]] && rm -f "$FUNCTION_PACKAGE"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi