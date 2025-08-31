#!/bin/bash
#
# Azure Automated Audio Summarization Deployment Script
# This script deploys Azure Functions, Blob Storage, and Azure OpenAI for automated audio processing
#
# Prerequisites:
# - Azure CLI installed and authenticated
# - Azure Functions Core Tools installed
# - OpenSSL for random string generation
# - Azure OpenAI access approved
#
# Usage: ./deploy.sh
#

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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
DEPLOYMENT_CONFIG_FILE="${SCRIPT_DIR}/deployment_config.env"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure Functions Core Tools
    if ! command -v func &> /dev/null; then
        log_error "Azure Functions Core Tools not installed. Please install from: https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local"
        exit 1
    fi
    
    # Check OpenSSL
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is required for generating random strings"
        exit 1
    fi
    
    # Check curl for sample file download
    if ! command -v curl &> /dev/null; then
        log_error "curl is required for downloading sample files"
        exit 1
    fi
    
    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        log_warning "jq not found. Installing via package manager recommended for better output formatting"
    fi
    
    # Check Azure CLI authentication
    if ! az account show &> /dev/null; then
        log_error "Azure CLI is not authenticated. Please run 'az login'"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    # Set Azure resource variables
    export RESOURCE_GROUP="rg-audio-summarization-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names with unique suffix
    export STORAGE_ACCOUNT="staudio${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-audio-summary-${RANDOM_SUFFIX}"
    export OPENAI_RESOURCE="aoai-audio-${RANDOM_SUFFIX}"
    
    # Validate location
    if ! az account list-locations --query "[?name=='${LOCATION}']" --output tsv | grep -q "${LOCATION}"; then
        log_error "Invalid Azure location: ${LOCATION}"
        log_info "Available locations: $(az account list-locations --query '[].name' --output tsv | tr '\n' ' ')"
        exit 1
    fi
    
    # Save configuration for cleanup script
    cat > "${DEPLOYMENT_CONFIG_FILE}" << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
FUNCTION_APP=${FUNCTION_APP}
OPENAI_RESOURCE=${OPENAI_RESOURCE}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    log_success "Environment variables configured"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Storage Account: ${STORAGE_ACCOUNT}"
    log_info "Function App: ${FUNCTION_APP}"
    log_info "OpenAI Resource: ${OPENAI_RESOURCE}"
}

# Function to create Azure resources
create_azure_resources() {
    log_info "Creating Azure resources..."
    
    # Create resource group
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=recipe environment=demo project=audio-summarization \
        --output none
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
    
    # Create storage account
    log_info "Creating storage account: ${STORAGE_ACCOUNT}"
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --output none
    
    # Wait for storage account to be ready
    log_info "Waiting for storage account to be ready..."
    while ! az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --query "provisioningState" --output tsv | grep -q "Succeeded"; do
        sleep 5
        echo -n "."
    done
    echo
    
    log_success "Storage account created: ${STORAGE_ACCOUNT}"
}

# Function to create Azure OpenAI resource
create_openai_resource() {
    log_info "Creating Azure OpenAI resource: ${OPENAI_RESOURCE}"
    
    # Check if Azure OpenAI is available in the region
    if ! az cognitiveservices account list-kinds --location "${LOCATION}" --query "[?contains(resourceType, 'OpenAI')]" --output tsv | grep -q "OpenAI"; then
        log_warning "Azure OpenAI may not be available in ${LOCATION}. Trying anyway..."
    fi
    
    # Create Azure OpenAI resource
    az cognitiveservices account create \
        --name "${OPENAI_RESOURCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --kind OpenAI \
        --sku S0 \
        --custom-domain "${OPENAI_RESOURCE}" \
        --output none
    
    # Wait for OpenAI resource to be ready
    log_info "Waiting for Azure OpenAI resource to be ready..."
    while ! az cognitiveservices account show --name "${OPENAI_RESOURCE}" --resource-group "${RESOURCE_GROUP}" --query "provisioningState" --output tsv | grep -q "Succeeded"; do
        sleep 10
        echo -n "."
    done
    echo
    
    # Get OpenAI endpoint and key
    export OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "${OPENAI_RESOURCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "properties.endpoint" --output tsv)
    
    export OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "${OPENAI_RESOURCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "key1" --output tsv)
    
    log_success "Azure OpenAI resource created: ${OPENAI_RESOURCE}"
    log_info "OpenAI Endpoint: ${OPENAI_ENDPOINT}"
}

# Function to deploy AI models
deploy_ai_models() {
    log_info "Deploying AI models..."
    
    # Deploy Whisper model for transcription
    log_info "Deploying Whisper model..."
    az cognitiveservices account deployment create \
        --name "${OPENAI_RESOURCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name whisper-1 \
        --model-name whisper \
        --model-version "001" \
        --model-format OpenAI \
        --sku-capacity 10 \
        --sku-name Standard \
        --output none
    
    # Wait for Whisper deployment
    log_info "Waiting for Whisper model deployment..."
    while ! az cognitiveservices account deployment show --name "${OPENAI_RESOURCE}" --resource-group "${RESOURCE_GROUP}" --deployment-name whisper-1 --query "properties.provisioningState" --output tsv | grep -q "Succeeded"; do
        sleep 15
        echo -n "."
    done
    echo
    
    # Deploy GPT-4 model for summarization
    log_info "Deploying GPT-4 model..."
    az cognitiveservices account deployment create \
        --name "${OPENAI_RESOURCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name gpt-4 \
        --model-name gpt-4 \
        --model-version "0613" \
        --model-format OpenAI \
        --sku-capacity 10 \
        --sku-name Standard \
        --output none
    
    # Wait for GPT-4 deployment
    log_info "Waiting for GPT-4 model deployment..."
    while ! az cognitiveservices account deployment show --name "${OPENAI_RESOURCE}" --resource-group "${RESOURCE_GROUP}" --deployment-name gpt-4 --query "properties.provisioningState" --output tsv | grep -q "Succeeded"; do
        sleep 15
        echo -n "."
    done
    echo
    
    log_success "AI models deployed successfully"
}

# Function to create blob containers
create_blob_containers() {
    log_info "Creating blob containers..."
    
    # Get storage connection string
    export STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString --output tsv)
    
    # Create container for audio uploads
    az storage container create \
        --name audio-input \
        --connection-string "${STORAGE_CONNECTION}" \
        --public-access off \
        --output none
    
    # Create container for processed outputs
    az storage container create \
        --name audio-output \
        --connection-string "${STORAGE_CONNECTION}" \
        --public-access off \
        --output none
    
    log_success "Blob containers created: audio-input, audio-output"
}

# Function to create and configure Function App
create_function_app() {
    log_info "Creating Function App: ${FUNCTION_APP}"
    
    # Create Function App with latest Python runtime
    az functionapp create \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime python \
        --runtime-version 3.12 \
        --functions-version 4 \
        --os-type Linux \
        --output none
    
    # Wait for Function App to be ready
    log_info "Waiting for Function App to be ready..."
    while ! az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" --query "state" --output tsv | grep -q "Running"; do
        sleep 10
        echo -n "."
    done
    echo
    
    # Configure Function App settings with secure environment variables
    log_info "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
            "AZURE_OPENAI_ENDPOINT=${OPENAI_ENDPOINT}" \
            "AZURE_OPENAI_KEY=${OPENAI_KEY}" \
            "STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION}" \
            "WEBSITE_RUN_FROM_PACKAGE=1" \
        --output none
    
    log_success "Function App created and configured: ${FUNCTION_APP}"
}

# Function to create and deploy function code
deploy_function_code() {
    log_info "Creating and deploying function code..."
    
    # Create temporary directory for function code
    TEMP_FUNCTION_DIR=$(mktemp -d)
    cd "${TEMP_FUNCTION_DIR}"
    
    # Initialize function project with Python
    func init --worker-runtime python --quiet
    
    # Create blob trigger function
    func new --name ProcessAudio --template "Azure Blob Storage trigger" --quiet
    
    # Create requirements.txt with updated dependencies
    cat > requirements.txt << 'EOF'
azure-functions==1.21.0
azure-storage-blob==12.23.1
openai==1.54.3
python-multipart==0.0.9
EOF
    
    # Create the main function code
    cat > ProcessAudio/__init__.py << 'EOF'
import azure.functions as func
import json
import logging
import os
import tempfile
from azure.storage.blob import BlobServiceClient
from openai import AzureOpenAI
from datetime import datetime

def main(myblob: func.InputStream) -> None:
    logging.info(f"Processing audio blob: {myblob.name}")
    
    try:
        # Initialize clients with proper configuration
        openai_client = AzureOpenAI(
            api_key=os.environ["AZURE_OPENAI_KEY"],
            api_version="2024-02-01",
            azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"]
        )
        
        blob_service = BlobServiceClient.from_connection_string(
            os.environ["STORAGE_CONNECTION_STRING"]
        )
        
        # Read audio data
        audio_data = myblob.read()
        logging.info(f"Audio file size: {len(audio_data)} bytes")
        
        # Create temporary file for audio processing
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as temp_file:
            temp_file.write(audio_data)
            temp_file_path = temp_file.name
        
        # Transcribe audio using Whisper
        with open(temp_file_path, "rb") as audio_file:
            transcript = openai_client.audio.transcriptions.create(
                model="whisper-1",
                file=audio_file,
                response_format="text"
            )
        
        logging.info(f"Transcription completed: {len(transcript)} characters")
        
        # Generate summary using GPT-4
        summary_prompt = f"""
        Please provide a concise summary of the following transcript:
        
        {transcript}
        
        Include:
        1. Main topics discussed
        2. Key insights or decisions
        3. Important action items (if any)
        
        Keep the summary under 200 words.
        """
        
        summary_response = openai_client.chat.completions.create(
            model="gpt-4",
            messages=[{"role": "user", "content": summary_prompt}],
            max_tokens=300,
            temperature=0.3
        )
        
        summary = summary_response.choices[0].message.content
        logging.info("Summary generation completed")
        
        # Create structured output document
        output_data = {
            "original_file": myblob.name,
            "processed_at": datetime.utcnow().isoformat(),
            "transcript": transcript,
            "summary": summary,
            "word_count": len(transcript.split()),
            "character_count": len(transcript),
            "processing_status": "completed"
        }
        
        # Upload results to output container
        output_filename = f"processed/{myblob.name.split('/')[-1]}.json"
        output_blob = blob_service.get_blob_client(
            container="audio-output",
            blob=output_filename
        )
        
        output_blob.upload_blob(
            json.dumps(output_data, indent=2),
            overwrite=True,
            content_type="application/json"
        )
        
        # Cleanup temporary file
        os.unlink(temp_file_path)
        
        logging.info(f"Successfully processed audio file: {myblob.name}")
        logging.info(f"Output saved to: {output_filename}")
        
    except Exception as e:
        logging.error(f"Error processing audio file {myblob.name}: {str(e)}")
        
        # Create error document for troubleshooting
        error_data = {
            "original_file": myblob.name,
            "processed_at": datetime.utcnow().isoformat(),
            "error_message": str(e),
            "error_type": type(e).__name__,
            "processing_status": "failed"
        }
        
        try:
            error_filename = f"errors/{myblob.name.split('/')[-1]}.error.json"
            error_blob = blob_service.get_blob_client(
                container="audio-output",
                blob=error_filename
            )
            
            error_blob.upload_blob(
                json.dumps(error_data, indent=2),
                overwrite=True,
                content_type="application/json"
            )
        except Exception as cleanup_error:
            logging.error(f"Failed to save error document: {cleanup_error}")
        
        # Cleanup temporary file if it exists
        if 'temp_file_path' in locals():
            try:
                os.unlink(temp_file_path)
            except:
                pass
EOF
    
    # Update function.json for blob trigger
    cat > ProcessAudio/function.json << 'EOF'
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "name": "myblob",
      "type": "blobTrigger",
      "direction": "in",
      "path": "audio-input/{name}",
      "connection": "STORAGE_CONNECTION_STRING"
    }
  ]
}
EOF
    
    # Deploy function to Azure
    log_info "Deploying function code to Azure..."
    func azure functionapp publish "${FUNCTION_APP}" --python --build remote --no-bundler
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "${TEMP_FUNCTION_DIR}"
    
    log_success "Function code deployed successfully"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing the deployment..."
    
    # Check function app status
    FUNCTION_STATUS=$(az functionapp show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "state" --output tsv)
    
    if [[ "${FUNCTION_STATUS}" != "Running" ]]; then
        log_warning "Function App is not in Running state: ${FUNCTION_STATUS}"
    else
        log_success "Function App is running correctly"
    fi
    
    # Download and upload sample audio file for testing
    log_info "Downloading sample audio file for testing..."
    SAMPLE_AUDIO_URL="https://github.com/Azure-Samples/cognitive-services-speech-sdk/raw/master/sampledata/audiofiles/wikipediaOcelot.wav"
    
    if curl -L "${SAMPLE_AUDIO_URL}" -o sample-audio.wav --fail --silent; then
        log_info "Uploading sample audio file to trigger processing..."
        
        az storage blob upload \
            --container-name audio-input \
            --file sample-audio.wav \
            --name "sample-audio.wav" \
            --connection-string "${STORAGE_CONNECTION}" \
            --output none
        
        log_success "Sample audio file uploaded. Processing will begin automatically."
        log_info "Monitor function logs with: az webapp log tail --name ${FUNCTION_APP} --resource-group ${RESOURCE_GROUP}"
        
        # Clean up local sample file
        rm -f sample-audio.wav
    else
        log_warning "Could not download sample audio file for testing"
    fi
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "Function App: ${FUNCTION_APP}"
    echo "OpenAI Resource: ${OPENAI_RESOURCE}"
    echo "OpenAI Endpoint: ${OPENAI_ENDPOINT}"
    echo
    echo "=== Next Steps ==="
    echo "1. Upload audio files to the 'audio-input' container"
    echo "2. Check processed results in the 'audio-output' container"
    echo "3. Monitor function execution logs:"
    echo "   az webapp log tail --name ${FUNCTION_APP} --resource-group ${RESOURCE_GROUP}"
    echo
    echo "=== Cleanup ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo
    echo "Configuration saved to: ${DEPLOYMENT_CONFIG_FILE}"
}

# Main execution flow
main() {
    log_info "Starting Azure Automated Audio Summarization deployment..."
    
    check_prerequisites
    setup_environment
    create_azure_resources
    create_openai_resource
    deploy_ai_models
    create_blob_containers
    create_function_app
    deploy_function_code
    test_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Deployment interrupted. You may need to clean up resources manually."; exit 1' INT TERM

# Run main function
main "$@"