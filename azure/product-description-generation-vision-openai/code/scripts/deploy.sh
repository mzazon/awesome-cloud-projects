#!/bin/bash

# Product Description Generation with AI Vision and OpenAI - Deployment Script
# This script deploys the complete Azure infrastructure for automated product description generation

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

# Script metadata
SCRIPT_NAME="Azure Product Description Generator Deployment"
SCRIPT_VERSION="1.0"
DEPLOYMENT_START_TIME=$(date)

log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
log_info "Deployment initiated at: $DEPLOYMENT_START_TIME"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        log_info "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required tools are available
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some output formatting may be limited."
    fi
    
    log_success "Prerequisites check completed"
}

# Set default values and environment variables
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Core configuration
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-product-description-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Storage configuration
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stproddesc${RANDOM_SUFFIX}}"
    export CONTAINER_NAME="${CONTAINER_NAME:-product-images}"
    export OUTPUT_CONTAINER="${OUTPUT_CONTAINER:-descriptions}"
    
    # Function App configuration
    export FUNCTION_APP="${FUNCTION_APP:-func-prod-desc-${RANDOM_SUFFIX}}"
    
    # AI Services configuration
    export AI_VISION_NAME="${AI_VISION_NAME:-cv-prod-desc-${RANDOM_SUFFIX}}"
    export OPENAI_NAME="${OPENAI_NAME:-oai-prod-desc-${RANDOM_SUFFIX}}"
    
    # Model configuration
    export MODEL_DEPLOYMENT_NAME="${MODEL_DEPLOYMENT_NAME:-gpt-4o}"
    export MODEL_NAME="${MODEL_NAME:-gpt-4o}"
    export MODEL_VERSION="${MODEL_VERSION:-2024-11-20}"
    
    log_success "Environment variables configured"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Random Suffix: $RANDOM_SUFFIX"
}

# Create Azure Resource Group
create_resource_group() {
    log_info "Creating resource group..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo category=ai-ml \
            --output none
        
        log_success "Resource group '$RESOURCE_GROUP' created successfully"
    fi
}

# Create Storage Account and Containers
create_storage_resources() {
    log_info "Creating storage account..."
    
    # Create storage account
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --output none
    
    log_success "Storage account '$STORAGE_ACCOUNT' created"
    
    # Get storage account key
    log_info "Retrieving storage account key..."
    STORAGE_KEY=$(az storage account keys list \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query '[0].value' --output tsv)
    
    if [ -z "$STORAGE_KEY" ]; then
        log_error "Failed to retrieve storage account key"
        exit 1
    fi
    
    # Create containers
    log_info "Creating storage containers..."
    
    az storage container create \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --public-access off \
        --output none
    
    az storage container create \
        --name "$OUTPUT_CONTAINER" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --public-access off \
        --output none
    
    log_success "Storage containers created successfully"
}

# Deploy AI Vision Service
deploy_ai_vision_service() {
    log_info "Deploying AI Vision service..."
    
    az cognitiveservices account create \
        --name "$AI_VISION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind ComputerVision \
        --sku S1 \
        --custom-domain "$AI_VISION_NAME" \
        --output none
    
    log_success "AI Vision service '$AI_VISION_NAME' deployed"
    
    # Get AI Vision endpoint and key
    log_info "Retrieving AI Vision credentials..."
    
    VISION_ENDPOINT=$(az cognitiveservices account show \
        --name "$AI_VISION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    VISION_KEY=$(az cognitiveservices account keys list \
        --name "$AI_VISION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    if [ -z "$VISION_ENDPOINT" ] || [ -z "$VISION_KEY" ]; then
        log_error "Failed to retrieve AI Vision credentials"
        exit 1
    fi
    
    log_success "AI Vision credentials retrieved"
}

# Deploy Azure OpenAI Service
deploy_openai_service() {
    log_info "Deploying Azure OpenAI service..."
    
    # Note: OpenAI service creation might require approval in some regions
    az cognitiveservices account create \
        --name "$OPENAI_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind OpenAI \
        --sku S0 \
        --custom-domain "$OPENAI_NAME" \
        --output none
    
    log_success "OpenAI service '$OPENAI_NAME' deployed"
    
    # Get OpenAI endpoint and key
    log_info "Retrieving OpenAI credentials..."
    
    OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "$OPENAI_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "$OPENAI_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    if [ -z "$OPENAI_ENDPOINT" ] || [ -z "$OPENAI_KEY" ]; then
        log_error "Failed to retrieve OpenAI credentials"
        exit 1
    fi
    
    log_success "OpenAI credentials retrieved"
}

# Deploy GPT-4o Model
deploy_gpt_model() {
    log_info "Deploying GPT-4o model..."
    
    az cognitiveservices account deployment create \
        --name "$OPENAI_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "$MODEL_DEPLOYMENT_NAME" \
        --model-name "$MODEL_NAME" \
        --model-version "$MODEL_VERSION" \
        --model-format OpenAI \
        --sku-capacity 10 \
        --sku-name Standard \
        --output none
    
    log_info "Waiting for model deployment to complete..."
    sleep 30
    
    # Verify deployment status
    DEPLOYMENT_STATUS=$(az cognitiveservices account deployment show \
        --name "$OPENAI_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "$MODEL_DEPLOYMENT_NAME" \
        --query provisioningState --output tsv)
    
    if [ "$DEPLOYMENT_STATUS" = "Succeeded" ]; then
        log_success "GPT-4o model deployed successfully"
    else
        log_warning "Model deployment status: $DEPLOYMENT_STATUS"
        log_info "Model deployment may still be in progress"
    fi
}

# Create Function App
create_function_app() {
    log_info "Creating Function App..."
    
    az functionapp create \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --consumption-plan-location "$LOCATION" \
        --runtime python \
        --runtime-version 3.11 \
        --functions-version 4 \
        --os-type Linux \
        --output none
    
    log_success "Function App '$FUNCTION_APP' created"
    
    # Configure application settings
    log_info "Configuring Function App settings..."
    
    STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT};AccountKey=${STORAGE_KEY};EndpointSuffix=core.windows.net"
    
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "VISION_ENDPOINT=${VISION_ENDPOINT}" \
        "VISION_KEY=${VISION_KEY}" \
        "OPENAI_ENDPOINT=${OPENAI_ENDPOINT}" \
        "OPENAI_KEY=${OPENAI_KEY}" \
        "STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION_STRING}" \
        "OUTPUT_CONTAINER=${OUTPUT_CONTAINER}" \
        --output none
    
    log_success "Function App settings configured"
}

# Deploy Function Code
deploy_function_code() {
    log_info "Preparing Function code deployment..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Create function configuration files
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
    
    cat > requirements.txt << 'EOF'
azure-functions>=1.18.0
azure-storage-blob>=12.19.0
requests>=2.31.0
azure-ai-vision-imageanalysis>=1.0.0
openai>=1.10.0
Pillow>=10.0.0
azure-core>=1.29.0
EOF
    
    # Create function directory and configuration
    mkdir -p ProductDescriptionGenerator
    cat > ProductDescriptionGenerator/function.json << 'EOF'
{
    "scriptFile": "__init__.py",
    "bindings": [
        {
            "name": "myblob",
            "type": "blobTrigger",
            "direction": "in",
            "path": "product-images/{name}",
            "connection": "STORAGE_CONNECTION_STRING",
            "source": "EventGrid"
        }
    ]
}
EOF
    
    # Create the main function code
    cat > ProductDescriptionGenerator/__init__.py << 'EOF'
import logging
import json
import os
import io
from azure.functions import InputStream
from azure.storage.blob import BlobServiceClient
from azure.ai.vision.imageanalysis import ImageAnalysisClient
from azure.ai.vision.imageanalysis.models import VisualFeatures
from azure.core.credentials import AzureKeyCredential
from openai import AzureOpenAI
from PIL import Image

def main(myblob: InputStream):
    logging.info(f"Processing blob: {myblob.name}")
    
    try:
        # Initialize clients with proper Azure SDK patterns
        vision_client = ImageAnalysisClient(
            endpoint=os.environ["VISION_ENDPOINT"],
            credential=AzureKeyCredential(os.environ["VISION_KEY"])
        )
        
        openai_client = AzureOpenAI(
            azure_endpoint=os.environ["OPENAI_ENDPOINT"],
            api_key=os.environ["OPENAI_KEY"],
            api_version="2024-02-01"
        )
        
        blob_service = BlobServiceClient.from_connection_string(
            os.environ["STORAGE_CONNECTION_STRING"]
        )
        
        # Read image data
        image_data = myblob.read()
        
        # Analyze image with Vision API
        logging.info("Analyzing image with AI Vision...")
        result = vision_client.analyze(
            image_data=image_data,
            visual_features=[
                VisualFeatures.CAPTION,
                VisualFeatures.OBJECTS,
                VisualFeatures.TAGS,
                VisualFeatures.CATEGORIES
            ]
        )
        
        # Extract analysis results
        caption = result.caption.text if result.caption else "Product image"
        objects = [obj.object_property for obj in result.objects.list] if result.objects else []
        tags = [tag.name for tag in result.tags.list[:10]] if result.tags else []
        categories = [cat.name for cat in result.categories.list] if result.categories else []
        
        logging.info(f"Vision analysis complete: {caption}")
        
        # Create prompt for OpenAI
        prompt = f"""
Create a compelling e-commerce product description based on this image analysis:

Image Description: {caption}
Detected Objects: {', '.join(objects)}
Key Tags: {', '.join(tags)}
Categories: {', '.join(categories)}

Generate a professional product description that includes:
1. An engaging headline
2. Key features and benefits
3. Use cases or styling suggestions
4. Material/quality highlights where applicable

Format as JSON with fields: headline, description, features, suggested_uses
Keep the tone professional yet engaging, suitable for online retail.
"""
        
        # Generate description with OpenAI using latest SDK patterns
        logging.info("Generating product description...")
        response = openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": "You are an expert e-commerce copywriter specializing in product descriptions."},
                {"role": "user", "content": prompt}
            ],
            max_tokens=500,
            temperature=0.7
        )
        
        generated_content = response.choices[0].message.content
        
        # Parse and structure the output
        try:
            product_description = json.loads(generated_content)
        except json.JSONDecodeError:
            # Fallback if JSON parsing fails
            product_description = {
                "headline": "Premium Product",
                "description": generated_content,
                "features": [],
                "suggested_uses": []
            }
        
        # Create final output with enhanced metadata
        import datetime
        output_data = {
            "filename": myblob.name,
            "timestamp": datetime.datetime.utcnow().isoformat(),
            "blob_uri": myblob.uri,
            "vision_analysis": {
                "caption": caption,
                "objects": objects,
                "tags": tags,
                "categories": categories
            },
            "generated_content": product_description,
            "processing_status": "success",
            "model_version": "gpt-4o",
            "processing_duration_ms": None  # Could be enhanced with timing
        }
        
        # Save results to output container
        output_filename = f"description_{os.path.splitext(os.path.basename(myblob.name))[0]}.json"
        blob_client = blob_service.get_blob_client(
            container=os.environ["OUTPUT_CONTAINER"],
            blob=output_filename
        )
        
        blob_client.upload_blob(
            json.dumps(output_data, indent=2),
            overwrite=True,
            content_type="application/json"
        )
        
        logging.info(f"Successfully processed {myblob.name} -> {output_filename}")
        
    except Exception as e:
        logging.error(f"Error processing {myblob.name}: {str(e)}")
        
        # Save error information with enhanced context
        import datetime
        error_data = {
            "filename": myblob.name,
            "timestamp": datetime.datetime.utcnow().isoformat(),
            "error": str(e),
            "error_type": type(e).__name__,
            "processing_status": "failed"
        }
        
        error_filename = f"error_{os.path.splitext(os.path.basename(myblob.name))[0]}.json"
        try:
            blob_client = blob_service.get_blob_client(
                container=os.environ["OUTPUT_CONTAINER"],
                blob=error_filename
            )
            blob_client.upload_blob(
                json.dumps(error_data, indent=2),
                overwrite=True,
                content_type="application/json"
            )
        except Exception as save_error:
            logging.error(f"Failed to save error info: {str(save_error)}")
EOF
    
    # Package and deploy the function
    log_info "Packaging and deploying Function code..."
    
    zip -r function.zip . -x "*.git*" "*.DS_Store*" > /dev/null 2>&1
    
    az functionapp deployment source config-zip \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --src function.zip \
        --output none
    
    log_info "Waiting for function deployment to complete..."
    sleep 60
    
    # Clean up temporary files
    cd /
    rm -rf "$TEMP_DIR"
    
    log_success "Function code deployed successfully"
}

# Configure Event Grid Integration
configure_event_grid() {
    log_info "Configuring Event Grid integration..."
    
    # Get Function App resource ID
    FUNCTION_RESOURCE_ID=$(az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    if [ -z "$FUNCTION_RESOURCE_ID" ]; then
        log_error "Failed to retrieve Function App resource ID"
        exit 1
    fi
    
    # Create Event Grid subscription
    az eventgrid event-subscription create \
        --name "product-image-processor" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
        --endpoint "${FUNCTION_RESOURCE_ID}/functions/ProductDescriptionGenerator" \
        --endpoint-type azurefunction \
        --included-event-types Microsoft.Storage.BlobCreated \
        --subject-begins-with "/blobServices/default/containers/${CONTAINER_NAME}/blobs/" \
        --advanced-filter data.contentType StringContains image \
        --output none
    
    log_success "Event Grid subscription configured"
}

# Test deployment with sample image
test_deployment() {
    log_info "Testing deployment with sample image..."
    
    # Create test image URL
    TEST_IMAGE_URL="https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=800"
    TEST_IMAGE_FILE="test-product.jpg"
    
    # Download test image
    if command -v curl &> /dev/null; then
        curl -s -o "$TEST_IMAGE_FILE" "$TEST_IMAGE_URL"
    elif command -v wget &> /dev/null; then
        wget -q -O "$TEST_IMAGE_FILE" "$TEST_IMAGE_URL"
    else
        log_warning "Neither curl nor wget available. Skipping test image upload."
        return
    fi
    
    if [ -f "$TEST_IMAGE_FILE" ]; then
        # Upload test image
        az storage blob upload \
            --account-name "$STORAGE_ACCOUNT" \
            --account-key "$STORAGE_KEY" \
            --container-name "$CONTAINER_NAME" \
            --name "test-product-001.jpg" \
            --file "$TEST_IMAGE_FILE" \
            --content-type "image/jpeg" \
            --output none
        
        log_success "Test image uploaded successfully"
        
        # Clean up test file
        rm -f "$TEST_IMAGE_FILE"
        
        log_info "Processing will begin automatically via Event Grid trigger"
        log_info "Check the '$OUTPUT_CONTAINER' container for generated descriptions"
    else
        log_warning "Failed to download test image. Skipping test upload."
    fi
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    DEPLOYMENT_INFO_FILE="deployment-info-${RANDOM_SUFFIX}.json"
    
    cat > "$DEPLOYMENT_INFO_FILE" << EOF
{
    "deployment_timestamp": "$DEPLOYMENT_START_TIME",
    "script_version": "$SCRIPT_VERSION",
    "resource_group": "$RESOURCE_GROUP",
    "location": "$LOCATION",
    "subscription_id": "$SUBSCRIPTION_ID",
    "storage_account": "$STORAGE_ACCOUNT",
    "function_app": "$FUNCTION_APP",
    "ai_vision_service": "$AI_VISION_NAME",
    "openai_service": "$OPENAI_NAME",
    "containers": {
        "input": "$CONTAINER_NAME",
        "output": "$OUTPUT_CONTAINER"
    },
    "endpoints": {
        "vision_endpoint": "$VISION_ENDPOINT",
        "openai_endpoint": "$OPENAI_ENDPOINT"
    },
    "model_deployment": "$MODEL_DEPLOYMENT_NAME",
    "random_suffix": "$RANDOM_SUFFIX"
}
EOF
    
    log_success "Deployment information saved to: $DEPLOYMENT_INFO_FILE"
}

# Display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "=================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Function App: $FUNCTION_APP"
    echo "AI Vision Service: $AI_VISION_NAME"
    echo "OpenAI Service: $OPENAI_NAME"
    echo "Input Container: $CONTAINER_NAME"
    echo "Output Container: $OUTPUT_CONTAINER"
    echo "=================================="
    echo ""
    
    log_success "Deployment completed successfully!"
    
    echo "Next Steps:"
    echo "1. Upload product images to the '$CONTAINER_NAME' container"
    echo "2. Generated descriptions will appear in the '$OUTPUT_CONTAINER' container"
    echo "3. Monitor function logs: az functionapp logs tail --name $FUNCTION_APP --resource-group $RESOURCE_GROUP"
    echo ""
    
    echo "Cost Management:"
    echo "- Monitor usage in Azure Cost Management + Billing"
    echo "- Consider implementing alerts for unexpected costs"
    echo "- Run destroy.sh when testing is complete to avoid ongoing charges"
    echo ""
    
    DEPLOYMENT_END_TIME=$(date)
    log_info "Deployment completed at: $DEPLOYMENT_END_TIME"
}

# Error handling function
handle_error() {
    log_error "Deployment failed at step: $1"
    log_error "Error details: $2"
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check Azure CLI authentication: az account show"
    echo "2. Verify Azure subscription permissions"
    echo "3. Check Azure service availability in region: $LOCATION"
    echo "4. Review Azure resource quotas and limits"
    echo ""
    echo "To clean up partial deployment, run: ./destroy.sh"
    exit 1
}

# Main deployment workflow
main() {
    log_info "Initializing deployment workflow..."
    
    # Set trap for error handling
    trap 'handle_error "Unknown step" "$?"' ERR
    
    check_prerequisites || handle_error "Prerequisites check" "$?"
    set_environment_variables || handle_error "Environment setup" "$?"
    create_resource_group || handle_error "Resource group creation" "$?"
    create_storage_resources || handle_error "Storage resources creation" "$?"
    deploy_ai_vision_service || handle_error "AI Vision service deployment" "$?"
    deploy_openai_service || handle_error "OpenAI service deployment" "$?"
    deploy_gpt_model || handle_error "GPT model deployment" "$?"
    create_function_app || handle_error "Function App creation" "$?"
    deploy_function_code || handle_error "Function code deployment" "$?"
    configure_event_grid || handle_error "Event Grid configuration" "$?"
    test_deployment || handle_error "Deployment testing" "$?"
    save_deployment_info || handle_error "Saving deployment info" "$?"
    display_summary
}

# Script options handling
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -l, --location LOCATION Set Azure region (default: eastus)"
    echo "  -g, --resource-group RG Set resource group name"
    echo "  --skip-test            Skip deployment testing"
    echo "  --dry-run              Show what would be deployed without executing"
    echo ""
    echo "Environment Variables:"
    echo "  LOCATION               Azure region for deployment"
    echo "  RESOURCE_GROUP         Custom resource group name"
    echo "  STORAGE_ACCOUNT        Custom storage account name"
    echo "  FUNCTION_APP           Custom function app name"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with default settings"
    echo "  $0 --location westus2                # Deploy to West US 2"
    echo "  $0 --resource-group my-rg            # Use custom resource group"
    echo "  $0 --skip-test                       # Deploy without test image"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --skip-test)
            SKIP_TEST=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Handle dry run mode
if [ "$DRY_RUN" = true ]; then
    log_info "DRY RUN MODE - No resources will be created"
    set_environment_variables
    echo ""
    echo "Resources that would be created:"
    echo "- Resource Group: $RESOURCE_GROUP"
    echo "- Storage Account: $STORAGE_ACCOUNT"
    echo "- Function App: $FUNCTION_APP"
    echo "- AI Vision Service: $AI_VISION_NAME"
    echo "- OpenAI Service: $OPENAI_NAME"
    echo "- Location: $LOCATION"
    echo ""
    exit 0
fi

# Execute main deployment
main "$@"