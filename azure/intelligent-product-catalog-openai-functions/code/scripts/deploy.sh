#!/bin/bash

# Azure Intelligent Product Catalog Deployment Script
# This script deploys an automated product catalog system using Azure Functions,
# Azure OpenAI Service, and Azure Blob Storage for AI-powered product analysis.

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TEMP_DIR=$(mktemp -d)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() { log "INFO" "${BLUE}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }
log_warning() { log "WARNING" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }

# Cleanup function
cleanup() {
    local exit_code=$?
    log_info "Cleaning up temporary files..."
    rm -rf "${TEMP_DIR}"
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed. Check ${LOG_FILE} for details."
    fi
    exit $exit_code
}

trap cleanup EXIT

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if Azure Functions Core Tools is installed
    if ! command -v func &> /dev/null; then
        log_error "Azure Functions Core Tools is not installed. Please install it from https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local"
        exit 1
    fi
    
    # Check if jq is installed for JSON processing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Installing jq for JSON processing..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v brew &> /dev/null; then
            brew install jq
        else
            log_error "Please install jq manually: https://stedolan.github.io/jq/download/"
            exit 1
        fi
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed."
        exit 1
    fi
    
    # Check Azure CLI login status
    if ! az account show &> /dev/null; then
        log_error "Please login to Azure CLI using 'az login'"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Validate Azure OpenAI Service access
validate_openai_access() {
    log_info "Validating Azure OpenAI Service access..."
    
    # Check if user has access to create Cognitive Services resources
    local test_result=$(az provider show --namespace Microsoft.CognitiveServices --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
    
    if [ "$test_result" != "Registered" ]; then
        log_warning "Microsoft.CognitiveServices provider not registered. Registering..."
        az provider register --namespace Microsoft.CognitiveServices
        log_info "Waiting for provider registration to complete..."
        sleep 30
    fi
    
    log_info "Azure OpenAI Service access validation completed"
}

# Set environment variables
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-catalog-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set unique resource names
    export STORAGE_ACCOUNT="stcatalog${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-catalog-${RANDOM_SUFFIX}"
    export OPENAI_ACCOUNT="openai-catalog-${RANDOM_SUFFIX}"
    
    # Validate resource names
    if [ ${#STORAGE_ACCOUNT} -gt 24 ]; then
        log_error "Storage account name too long: ${STORAGE_ACCOUNT}"
        exit 1
    fi
    
    log_info "Environment variables configured:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT}"
    log_info "  Function App: ${FUNCTION_APP}"
    log_info "  OpenAI Account: ${OPENAI_ACCOUNT}"
    
    # Save environment variables for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
FUNCTION_APP=${FUNCTION_APP}
OPENAI_ACCOUNT=${OPENAI_ACCOUNT}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables set and saved"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
        return 0
    fi
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=recipe environment=demo created_by=deploy_script
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

# Create Azure OpenAI Service resource
create_openai_service() {
    log_info "Creating Azure OpenAI Service: ${OPENAI_ACCOUNT}"
    
    # Create Azure OpenAI resource
    az cognitiveservices account create \
        --name "${OPENAI_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --kind OpenAI \
        --sku S0 \
        --custom-domain "${OPENAI_ACCOUNT}" \
        --tags purpose=recipe environment=demo
    
    # Wait for resource to be ready
    log_info "Waiting for Azure OpenAI Service to be ready..."
    sleep 30
    
    # Get the endpoint and key
    export OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "${OPENAI_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "properties.endpoint" --output tsv)
    
    export OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "${OPENAI_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "key1" --output tsv)
    
    # Save credentials to .env file
    echo "OPENAI_ENDPOINT=${OPENAI_ENDPOINT}" >> "${SCRIPT_DIR}/.env"
    echo "OPENAI_KEY=${OPENAI_KEY}" >> "${SCRIPT_DIR}/.env"
    
    log_success "Azure OpenAI Service created with endpoint: ${OPENAI_ENDPOINT}"
}

# Deploy GPT-4o model
deploy_gpt4o_model() {
    log_info "Deploying GPT-4o model..."
    
    # Check if deployment already exists
    if az cognitiveservices account deployment show \
        --name "${OPENAI_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name gpt-4o-deployment &> /dev/null; then
        log_warning "GPT-4o deployment already exists"
        return 0
    fi
    
    # Deploy GPT-4o model with latest version
    az cognitiveservices account deployment create \
        --name "${OPENAI_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name gpt-4o-deployment \
        --model-name gpt-4o \
        --model-version "2024-11-20" \
        --model-format OpenAI \
        --sku-capacity 1 \
        --sku-name "Standard"
    
    # Wait for deployment to complete
    log_info "Waiting for model deployment to complete..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local status=$(az cognitiveservices account deployment show \
            --name "${OPENAI_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --deployment-name gpt-4o-deployment \
            --query "properties.provisioningState" -o tsv)
        
        if [ "$status" = "Succeeded" ]; then
            break
        elif [ "$status" = "Failed" ]; then
            log_error "Model deployment failed"
            exit 1
        fi
        
        log_info "Model deployment status: ${status}. Waiting..."
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log_error "Model deployment timed out"
        exit 1
    fi
    
    log_success "GPT-4o model deployed successfully"
}

# Create storage account with containers
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT}"
    
    # Create storage account
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --tags purpose=recipe environment=demo
    
    # Get storage connection string
    export STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "connectionString" --output tsv)
    
    # Save to .env file
    echo "STORAGE_CONNECTION=${STORAGE_CONNECTION}" >> "${SCRIPT_DIR}/.env"
    
    # Create blob containers
    log_info "Creating blob containers..."
    
    az storage container create \
        --name product-images \
        --connection-string "${STORAGE_CONNECTION}" \
        --public-access off
    
    az storage container create \
        --name catalog-results \
        --connection-string "${STORAGE_CONNECTION}" \
        --public-access off
    
    log_success "Storage account and containers created"
}

# Create Azure Function App
create_function_app() {
    log_info "Creating Function App: ${FUNCTION_APP}"
    
    # Create Function App
    az functionapp create \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime python \
        --runtime-version 3.11 \
        --functions-version 4 \
        --os-type Linux \
        --tags purpose=recipe environment=demo
    
    # Wait for Function App to be ready
    log_info "Waiting for Function App to be ready..."
    sleep 60
    
    log_success "Function App created: ${FUNCTION_APP}"
}

# Configure Function App settings
configure_function_settings() {
    log_info "Configuring Function App settings..."
    
    # Configure application settings
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "AZURE_OPENAI_ENDPOINT=${OPENAI_ENDPOINT}" \
        "AZURE_OPENAI_KEY=${OPENAI_KEY}" \
        "AZURE_OPENAI_DEPLOYMENT=gpt-4o-deployment" \
        "AzureWebJobsStorage=${STORAGE_CONNECTION}" \
        "STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION}"
    
    log_success "Function App settings configured"
}

# Create and deploy function code
create_deploy_function() {
    log_info "Creating and deploying function code..."
    
    # Create local function project directory
    local function_dir="${TEMP_DIR}/azure-function"
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    # Initialize function project
    func init . --python --model V2
    
    # Create the main function file
    cat > function_app.py << 'EOF'
import azure.functions as func
import json
import logging
import base64
from openai import AzureOpenAI
import os
from datetime import datetime

app = func.FunctionApp()

@app.blob_trigger(arg_name="myblob", 
                  path="product-images/{name}",
                  connection="AzureWebJobsStorage")
@app.blob_output(arg_name="outputblob",
                 path="catalog-results/{name}.json",
                 connection="AzureWebJobsStorage")
def ProductCatalogProcessor(myblob: func.InputStream, outputblob: func.Out[str]):
    logging.info(f"Processing blob: {myblob.name}, Size: {myblob.length} bytes")
    
    try:
        # Initialize Azure OpenAI client with latest API version
        client = AzureOpenAI(
            azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
            api_key=os.environ["AZURE_OPENAI_KEY"],
            api_version="2024-10-21"
        )
        
        # Read and encode image
        image_data = myblob.read()
        image_base64 = base64.b64encode(image_data).decode('utf-8')
        
        # Create detailed prompt for product analysis
        prompt = """
        Analyze this product image and provide a comprehensive product catalog entry. 
        Return a JSON object with the following structure:
        {
            "product_name": "Clear, descriptive product name",
            "description": "Detailed 2-3 sentence product description",
            "features": ["List of key features and specifications"],
            "category": "Primary product category",
            "subcategory": "Specific subcategory",
            "colors": ["Identified colors in the product"],
            "materials": ["Detected materials if applicable"],
            "style": "Design style (modern, classic, etc.)",
            "target_audience": "Intended customer demographic",
            "keywords": ["SEO-friendly keywords"],
            "estimated_price_range": "Price range category (budget/mid-range/premium)"
        }
        
        Focus on accuracy and detail. If certain information cannot be determined from the image, use "Not determinable from image".
        """
        
        # Call GPT-4o with vision
        response = client.chat.completions.create(
            model=os.environ["AZURE_OPENAI_DEPLOYMENT"],
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{image_base64}",
                                "detail": "high"
                            }
                        }
                    ]
                }
            ],
            max_tokens=1000,
            temperature=0.3
        )
        
        # Parse the response
        catalog_data = json.loads(response.choices[0].message.content)
        
        # Add metadata
        catalog_data["processing_timestamp"] = datetime.utcnow().isoformat() + "Z"
        catalog_data["source_image"] = myblob.name
        catalog_data["image_size_bytes"] = myblob.length
        catalog_data["model_used"] = os.environ["AZURE_OPENAI_DEPLOYMENT"]
        
        # Output the catalog data
        outputblob.set(json.dumps(catalog_data, indent=2))
        
        logging.info(f"Successfully processed {myblob.name}")
        
    except Exception as e:
        logging.error(f"Error processing {myblob.name}: {str(e)}")
        
        # Create error output
        error_data = {
            "error": str(e),
            "source_image": myblob.name,
            "processing_timestamp": datetime.utcnow().isoformat() + "Z",
            "status": "failed"
        }
        outputblob.set(json.dumps(error_data, indent=2))
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
azure-functions
openai>=1.0.0
azure-storage-blob
EOF
    
    # Deploy the function
    log_info "Deploying function to Azure..."
    func azure functionapp publish "${FUNCTION_APP}" --python
    
    log_success "Function deployed successfully"
}

# Test deployment with sample image
test_deployment() {
    log_info "Testing deployment with sample image..."
    
    # Download a sample product image for testing
    local test_image="${TEMP_DIR}/sample-product.jpg"
    curl -s -o "${test_image}" \
        "https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=500" || {
        log_warning "Could not download test image. Skipping test."
        return 0
    }
    
    # Upload test image to trigger function
    az storage blob upload \
        --account-name "${STORAGE_ACCOUNT}" \
        --container-name product-images \
        --name "sample-product.jpg" \
        --file "${test_image}" \
        --connection-string "${STORAGE_CONNECTION}" \
        --overwrite
    
    log_info "Test image uploaded. Function should process it automatically."
    log_info "Check the catalog-results container in a few minutes for results."
    
    log_success "Deployment test completed"
}

# Print deployment summary
print_summary() {
    log_success "================================"
    log_success "DEPLOYMENT COMPLETED SUCCESSFULLY"
    log_success "================================"
    log_info ""
    log_info "Resource Details:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT}"
    log_info "  Function App: ${FUNCTION_APP}"
    log_info "  OpenAI Account: ${OPENAI_ACCOUNT}"
    log_info ""
    log_info "Next Steps:"
    log_info "1. Upload product images to the 'product-images' container"
    log_info "2. Check the 'catalog-results' container for generated catalog entries"
    log_info "3. Monitor function logs: az functionapp logs tail --name ${FUNCTION_APP} --resource-group ${RESOURCE_GROUP}"
    log_info ""
    log_info "Cost Management:"
    log_info "- This deployment uses consumption-based pricing"
    log_info "- Estimated cost: \$5-10 for 100 product images"
    log_info "- Remember to run cleanup script when done: ./destroy.sh"
    log_info ""
    log_info "Configuration saved to: ${SCRIPT_DIR}/.env"
    log_info "Deployment log saved to: ${LOG_FILE}"
}

# Main deployment flow
main() {
    log_info "Starting Azure Intelligent Product Catalog deployment..."
    log_info "Deployment log: ${LOG_FILE}"
    
    check_prerequisites
    validate_openai_access
    set_environment_variables
    create_resource_group
    create_openai_service
    deploy_gpt4o_model
    create_storage_account
    create_function_app
    configure_function_settings
    create_deploy_function
    test_deployment
    print_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"