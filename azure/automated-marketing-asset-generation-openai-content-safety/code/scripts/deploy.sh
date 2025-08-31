#!/bin/bash

# Azure Marketing Asset Generation with OpenAI and Content Safety - Deployment Script
# This script deploys the complete infrastructure for automated marketing content generation
# using Azure OpenAI, Content Safety, Functions, and Blob Storage

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

# Function to print script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -g, --resource-group    Resource group name (optional, will generate if not provided)"
    echo "  -l, --location          Azure region (default: eastus)"
    echo "  -s, --suffix            Custom suffix for resource names (optional, will generate if not provided)"
    echo "  -d, --dry-run           Validate parameters and show what would be deployed without actually deploying"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --resource-group rg-marketing-ai --location eastus2 --suffix dev01"
    echo "  $0 --dry-run"
}

# Default values
LOCATION="eastus"
DRY_RUN=false
CUSTOM_RESOURCE_GROUP=""
CUSTOM_SUFFIX=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            CUSTOM_RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -s|--suffix)
            CUSTOM_SUFFIX="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if zip command is available for function deployment
    if ! command -v zip &> /dev/null; then
        log_error "zip command is not available. Please install zip utility."
        exit 1
    fi
    
    # Check if openssl is available for generating random values
    if ! command -v openssl &> /dev/null; then
        log_error "openssl command is not available. Please install openssl."
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

# Function to set environment variables
set_environment_variables() {
    log_info "Setting environment variables..."
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    log_info "Using subscription: $SUBSCRIPTION_ID"
    
    # Generate or use provided suffix
    if [[ -z "$CUSTOM_SUFFIX" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
        log_info "Generated random suffix: $RANDOM_SUFFIX"
    else
        RANDOM_SUFFIX="$CUSTOM_SUFFIX"
        log_info "Using custom suffix: $RANDOM_SUFFIX"
    fi
    
    # Set resource group name
    if [[ -z "$CUSTOM_RESOURCE_GROUP" ]]; then
        export RESOURCE_GROUP="rg-marketing-ai-${RANDOM_SUFFIX}"
    else
        export RESOURCE_GROUP="$CUSTOM_RESOURCE_GROUP"
    fi
    
    # Set location
    export LOCATION="$LOCATION"
    
    # Set resource names with suffix
    export STORAGE_ACCOUNT="stmarketingai${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-marketing-ai-${RANDOM_SUFFIX}"
    export OPENAI_ACCOUNT="openai-marketing-${RANDOM_SUFFIX}"
    export CONTENT_SAFETY_ACCOUNT="cs-marketing-${RANDOM_SUFFIX}"
    
    log_info "Environment variables configured:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Storage Account: $STORAGE_ACCOUNT"
    log_info "  Function App: $FUNCTION_APP"
    log_info "  OpenAI Account: $OPENAI_ACCOUNT"
    log_info "  Content Safety Account: $CONTENT_SAFETY_ACCOUNT"
}

# Function to validate resource names
validate_resource_names() {
    log_info "Validating resource names..."
    
    # Validate storage account name (3-24 chars, lowercase, numbers only)
    if [[ ! "$STORAGE_ACCOUNT" =~ ^[a-z0-9]{3,24}$ ]]; then
        log_error "Storage account name '$STORAGE_ACCOUNT' is invalid. Must be 3-24 characters, lowercase letters and numbers only."
        exit 1
    fi
    
    # Validate function app name length
    if [[ ${#FUNCTION_APP} -gt 60 ]]; then
        log_error "Function app name '$FUNCTION_APP' is too long. Must be 60 characters or less."
        exit 1
    fi
    
    log_success "Resource names validated"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo project=marketing-ai
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create storage account: $STORAGE_ACCOUNT"
        return
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --tags purpose=marketing-assets
    
    # Get storage account key
    export STORAGE_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT" \
        --query '[0].value' --output tsv)
    
    log_success "Storage account created: $STORAGE_ACCOUNT"
}

# Function to create blob containers
create_blob_containers() {
    log_info "Creating blob containers for content workflow"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create blob containers: marketing-requests, marketing-assets, rejected-content"
        return
    fi
    
    # Create container for input prompts and requests
    az storage container create \
        --name "marketing-requests" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --public-access off
    
    # Create container for generated marketing assets
    az storage container create \
        --name "marketing-assets" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --public-access blob
    
    # Create container for rejected content (safety violations)
    az storage container create \
        --name "rejected-content" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --public-access off
    
    log_success "Blob containers created successfully"
}

# Function to create Azure OpenAI service
create_openai_service() {
    log_info "Creating Azure OpenAI service: $OPENAI_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Azure OpenAI service: $OPENAI_ACCOUNT"
        return
    fi
    
    # Create Azure OpenAI resource
    az cognitiveservices account create \
        --name "$OPENAI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind OpenAI \
        --sku S0 \
        --custom-domain "$OPENAI_ACCOUNT" \
        --tags purpose=marketing-content-generation
    
    # Get OpenAI endpoint and key
    export OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "$OPENAI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    export OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "$OPENAI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    log_success "Azure OpenAI service created: $OPENAI_ENDPOINT"
}

# Function to deploy OpenAI models
deploy_openai_models() {
    log_info "Deploying OpenAI models for content generation"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy GPT-4 and DALL-E 3 models"
        return
    fi
    
    # Deploy GPT-4 model for text generation
    log_info "Deploying GPT-4 model..."
    az cognitiveservices account deployment create \
        --name "$OPENAI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "gpt-4-marketing" \
        --model-name "gpt-4" \
        --model-version "0613" \
        --model-format "OpenAI" \
        --sku-name "Standard" \
        --sku-capacity 10
    
    # Deploy DALL-E 3 model for image generation
    log_info "Deploying DALL-E 3 model..."
    az cognitiveservices account deployment create \
        --name "$OPENAI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "dalle-3-marketing" \
        --model-name "dall-e-3" \
        --model-version "3.0" \
        --model-format "OpenAI" \
        --sku-name "Standard" \
        --sku-capacity 1
    
    log_success "OpenAI models deployed successfully"
}

# Function to create Content Safety service
create_content_safety_service() {
    log_info "Creating Content Safety service: $CONTENT_SAFETY_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Content Safety service: $CONTENT_SAFETY_ACCOUNT"
        return
    fi
    
    # Create Content Safety resource
    az cognitiveservices account create \
        --name "$CONTENT_SAFETY_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind ContentSafety \
        --sku S0 \
        --tags purpose=marketing-content-moderation
    
    # Get Content Safety endpoint and key
    export CONTENT_SAFETY_ENDPOINT=$(az cognitiveservices account show \
        --name "$CONTENT_SAFETY_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    export CONTENT_SAFETY_KEY=$(az cognitiveservices account keys list \
        --name "$CONTENT_SAFETY_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    log_success "Content Safety service created: $CONTENT_SAFETY_ENDPOINT"
}

# Function to create Function App
create_function_app() {
    log_info "Creating Function App: $FUNCTION_APP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Function App: $FUNCTION_APP"
        return
    fi
    
    # Create Function App with Python runtime
    az functionapp create \
        --resource-group "$RESOURCE_GROUP" \
        --consumption-plan-location "$LOCATION" \
        --runtime python \
        --runtime-version 3.11 \
        --functions-version 4 \
        --name "$FUNCTION_APP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --tags purpose=marketing-automation
    
    log_success "Function App created: $FUNCTION_APP"
    
    # Wait for Function App deployment
    log_info "Waiting for Function App to be ready..."
    sleep 30
}

# Function to configure Function App settings
configure_function_app() {
    log_info "Configuring Function App settings"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure Function App with service connections"
        return
    fi
    
    # Configure application settings for all services
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "AZURE_OPENAI_ENDPOINT=$OPENAI_ENDPOINT" \
        "AZURE_OPENAI_KEY=$OPENAI_KEY" \
        "CONTENT_SAFETY_ENDPOINT=$CONTENT_SAFETY_ENDPOINT" \
        "CONTENT_SAFETY_KEY=$CONTENT_SAFETY_KEY" \
        "STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT;AccountKey=$STORAGE_KEY;EndpointSuffix=core.windows.net"
    
    # Enable system-assigned managed identity for enhanced security
    az functionapp identity assign \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP"
    
    log_success "Function App configured with service connections"
}

# Function to create and deploy the marketing function
deploy_marketing_function() {
    log_info "Creating and deploying marketing content generation function"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create and deploy the marketing function code"
        return
    fi
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    pushd "$TEMP_DIR" > /dev/null
    
    # Create requirements.txt for Python dependencies
    cat > requirements.txt << 'EOF'
azure-functions
azure-storage-blob
azure-ai-contentsafety
openai
requests
Pillow
EOF
    
    # Create the main function file
    cat > function_app.py << 'EOF'
import azure.functions as func
import json
import logging
import os
from azure.storage.blob import BlobServiceClient
from azure.ai.contentsafety import ContentSafetyClient
from azure.ai.contentsafety.models import AnalyzeTextOptions, AnalyzeImageOptions, ImageData
from azure.core.credentials import AzureKeyCredential
from openai import AzureOpenAI
import requests
from PIL import Image
from io import BytesIO
import base64

app = func.FunctionApp()

# Initialize clients
openai_client = AzureOpenAI(
    api_key=os.environ["AZURE_OPENAI_KEY"],
    api_version="2024-02-01",
    azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"]
)

safety_client = ContentSafetyClient(
    os.environ["CONTENT_SAFETY_ENDPOINT"],
    AzureKeyCredential(os.environ["CONTENT_SAFETY_KEY"])
)

blob_client = BlobServiceClient.from_connection_string(
    os.environ["STORAGE_CONNECTION_STRING"]
)

@app.blob_trigger(arg_name="inputblob", 
                 path="marketing-requests/{name}",
                 connection="STORAGE_CONNECTION_STRING")
def generate_marketing_content(inputblob: func.InputStream):
    logging.info("Processing marketing content request")
    
    try:
        # Parse request from blob
        request_data = json.loads(inputblob.read().decode('utf-8'))
        
        # Generate text content
        if request_data.get("generate_text"):
            text_content = generate_marketing_text(request_data)
            if validate_content_safety(text_content):
                save_to_blob("marketing-assets", f"text/{request_data['campaign_id']}.txt", text_content)
                logging.info(f"Text content approved and saved for {request_data['campaign_id']}")
            else:
                save_to_blob("rejected-content", f"text/{request_data['campaign_id']}.txt", text_content)
                logging.warning(f"Text content rejected for safety violations: {request_data['campaign_id']}")
        
        # Generate image content
        if request_data.get("generate_image"):
            image_url = generate_marketing_image(request_data)
            if image_url and validate_image_safety(image_url):
                save_image_to_blob("marketing-assets", f"images/{request_data['campaign_id']}.png", image_url)
                logging.info(f"Image content approved and saved for {request_data['campaign_id']}")
            else:
                logging.warning(f"Image generation failed safety check for {request_data['campaign_id']}")
    
    except Exception as e:
        logging.error(f"Error processing marketing request: {str(e)}")

def generate_marketing_text(request_data):
    response = openai_client.chat.completions.create(
        model="gpt-4-marketing",
        messages=[
            {"role": "system", "content": "You are a marketing copywriter creating engaging, brand-appropriate content."},
            {"role": "user", "content": request_data["text_prompt"]}
        ],
        max_tokens=500,
        temperature=0.7
    )
    return response.choices[0].message.content

def generate_marketing_image(request_data):
    response = openai_client.images.generate(
        model="dalle-3-marketing",
        prompt=request_data["image_prompt"],
        size="1024x1024",
        quality="standard",
        n=1
    )
    return response.data[0].url

def validate_content_safety(text_content):
    try:
        # Analyze text content for safety violations
        request = AnalyzeTextOptions(text=text_content)
        response = safety_client.analyze_text(request)
        
        # Check if any category exceeded threshold (adjust thresholds as needed)
        for category_result in response.categories_analysis:
            if category_result.severity >= 4:  # High severity threshold
                return False
        return True
    except Exception as e:
        logging.error(f"Content safety analysis failed: {str(e)}")
        return False  # Reject on error for safety

def validate_image_safety(image_url):
    try:
        # Download image for analysis
        response = requests.get(image_url)
        image_data = response.content
        
        # Analyze image content for safety violations
        request = AnalyzeImageOptions(image=ImageData(content=image_data))
        response = safety_client.analyze_image(request)
        
        # Check if any category exceeded threshold
        for category_result in response.categories_analysis:
            if category_result.severity >= 4:  # High severity threshold
                return False
        return True
    except Exception as e:
        logging.error(f"Image safety analysis failed: {str(e)}")
        return False  # Reject on error for safety

def save_to_blob(container_name, blob_name, content):
    blob_client_instance = blob_client.get_blob_client(
        container=container_name, blob=blob_name
    )
    blob_client_instance.upload_blob(content, overwrite=True)
    logging.info(f"Saved content to {container_name}/{blob_name}")

def save_image_to_blob(container_name, blob_name, image_url):
    response = requests.get(image_url)
    blob_client_instance = blob_client.get_blob_client(
        container=container_name, blob=blob_name
    )
    blob_client_instance.upload_blob(response.content, overwrite=True)
    logging.info(f"Saved image to {container_name}/{blob_name}")
EOF
    
    # Create host.json configuration
    cat > host.json << 'EOF'
{
  "version": "2.0",
  "functionTimeout": "00:05:00",
  "extensions": {
    "blobs": {
      "maxDegreeOfParallelism": 4
    }
  }
}
EOF
    
    # Package and deploy function
    zip -r marketing-function.zip . -x "*.git*" "*.DS_Store*"
    
    # Deploy function package to Azure
    az functionapp deployment source config-zip \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP" \
        --src marketing-function.zip
    
    # Wait for deployment to complete
    log_info "Waiting for function deployment to complete..."
    sleep 60
    
    # Return to original directory and cleanup
    popd > /dev/null
    rm -rf "$TEMP_DIR"
    
    log_success "Marketing function deployed successfully"
}

# Function to create test content
create_test_content() {
    log_info "Creating test marketing request"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create test marketing content"
        return
    fi
    
    # Create test marketing request
    cat > test-marketing-request.json << 'EOF'
{
  "campaign_id": "summer-2025-launch",
  "generate_text": true,
  "text_prompt": "Create an engaging social media post for a summer product launch featuring sustainable outdoor gear. Include a call-to-action and relevant hashtags.",
  "generate_image": true,
  "image_prompt": "A vibrant summer scene with eco-friendly outdoor gear including backpacks and water bottles, natural lighting, professional marketing photography style"
}
EOF
    
    # Upload test request to trigger function
    az storage blob upload \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --container-name "marketing-requests" \
        --name "test-request.json" \
        --file test-marketing-request.json
    
    # Clean up local test file
    rm test-marketing-request.json
    
    log_success "Test marketing request uploaded"
    log_info "Function processing will complete in 1-2 minutes"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "==================== DEPLOYMENT SUMMARY ===================="
    echo "Resource Group:        $RESOURCE_GROUP"
    echo "Location:              $LOCATION"
    echo "Storage Account:       $STORAGE_ACCOUNT"
    echo "Function App:          $FUNCTION_APP"
    echo "OpenAI Service:        $OPENAI_ACCOUNT"
    echo "Content Safety:        $CONTENT_SAFETY_ACCOUNT"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor function execution in Azure portal"
    echo "2. Check generated assets in the 'marketing-assets' container"
    echo "3. Review logs for any processing issues"
    echo ""
    echo "Azure Portal Links:"
    echo "Function App: https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP"
    echo "Storage Account: https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"
    echo "=========================================================="
}

# Function to handle script interruption
cleanup_on_interrupt() {
    log_warning "Script interrupted. Some resources may have been created."
    log_info "Run the destroy.sh script to clean up any created resources."
    exit 1
}

# Set trap for script interruption
trap cleanup_on_interrupt INT TERM

# Main deployment function
main() {
    log_info "Starting Azure Marketing Asset Generation deployment..."
    echo "========================================================"
    
    check_prerequisites
    set_environment_variables
    validate_resource_names
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        echo "========================================================"
    fi
    
    create_resource_group
    create_storage_account
    create_blob_containers
    create_openai_service
    deploy_openai_models
    create_content_safety_service
    create_function_app
    configure_function_app
    deploy_marketing_function
    create_test_content
    
    if [[ "$DRY_RUN" == "false" ]]; then
        display_summary
    else
        log_info "DRY RUN completed. No resources were created."
    fi
}

# Execute main function
main "$@"