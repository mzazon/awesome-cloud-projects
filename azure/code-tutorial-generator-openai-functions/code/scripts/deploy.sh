#!/bin/bash

# Code Tutorial Generator Deployment Script
# Deploys Azure OpenAI, Functions, and Blob Storage for tutorial generation

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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

# Function to display script usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Code Tutorial Generator infrastructure to Azure.

Options:
    -r, --resource-group NAME    Resource group name (required)
    -l, --location LOCATION      Azure region (default: eastus)
    -s, --suffix SUFFIX          Resource name suffix (default: random)
    -h, --help                   Show this help message
    --dry-run                    Preview changes without deployment
    --verbose                    Enable verbose logging

Example:
    $0 --resource-group rg-tutorial-prod --location eastus2
EOF
}

# Initialize variables with defaults
RESOURCE_GROUP=""
LOCATION="eastus"
SUFFIX=$(openssl rand -hex 3)
DRY_RUN=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -s|--suffix)
            SUFFIX="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
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

# Validate required parameters
if [[ -z "$RESOURCE_GROUP" ]]; then
    log_error "Resource group name is required. Use -r or --resource-group."
    usage
    exit 1
fi

# Enable verbose output if requested
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

# Set Azure CLI output format
export AZURE_CORE_OUTPUT="table"

log_info "Starting Code Tutorial Generator deployment..."
log_info "Resource Group: $RESOURCE_GROUP"
log_info "Location: $LOCATION"
log_info "Suffix: $SUFFIX"

if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY RUN MODE - No resources will be created"
fi

# Check prerequisites
log_info "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    log_error "Azure CLI not found. Please install Azure CLI."
    exit 1
fi

# Check Azure login status
if ! az account show &> /dev/null; then
    log_error "Not logged in to Azure. Please run 'az login'."
    exit 1
fi

# Get subscription information
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
TENANT_ID=$(az account show --query tenantId --output tsv)
log_info "Using subscription: $SUBSCRIPTION_ID"

# Check if Azure OpenAI is available in the subscription
OPENAI_AVAILABLE=$(az cognitiveservices account list-kinds --query "contains([].kind, 'OpenAI')" --output tsv)
if [[ "$OPENAI_AVAILABLE" != "true" ]]; then
    log_warning "Azure OpenAI might not be available in your subscription."
    log_warning "Please ensure you have access to Azure OpenAI service."
fi

# Set resource names
STORAGE_ACCOUNT="tutorialstorage${SUFFIX}"
FUNCTION_APP="tutorial-generator-${SUFFIX}"
OPENAI_ACCOUNT="tutorial-openai-${SUFFIX}"

# Validate resource names
if [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
    log_error "Storage account name too long: $STORAGE_ACCOUNT (max 24 chars)"
    exit 1
fi

if [[ ${#FUNCTION_APP} -gt 60 ]]; then
    log_error "Function app name too long: $FUNCTION_APP (max 60 chars)"
    exit 1
fi

log_info "Resource names:"
log_info "  Storage Account: $STORAGE_ACCOUNT"
log_info "  Function App: $FUNCTION_APP"
log_info "  OpenAI Account: $OPENAI_ACCOUNT"

# Exit if dry run
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry run complete. No resources were created."
    exit 0
fi

# Function to check if resource group exists
check_resource_group() {
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' already exists"
        return 0
    else
        return 1
    fi
}

# Create or verify resource group
log_info "Creating resource group..."
if ! check_resource_group; then
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=tutorial-generator environment=demo deployment-script=true
    log_success "Resource group created: $RESOURCE_GROUP"
else
    log_info "Using existing resource group: $RESOURCE_GROUP"
fi

# Store deployment state for cleanup
DEPLOYMENT_LOG="deployment-${SUFFIX}.log"
cat > "$DEPLOYMENT_LOG" << EOF
# Code Tutorial Generator Deployment Log
# Generated on: $(date)
RESOURCE_GROUP="$RESOURCE_GROUP"
LOCATION="$LOCATION"
SUFFIX="$SUFFIX"
STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
FUNCTION_APP="$FUNCTION_APP"
OPENAI_ACCOUNT="$OPENAI_ACCOUNT"
SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
TENANT_ID="$TENANT_ID"
EOF

log_info "Deployment state saved to: $DEPLOYMENT_LOG"

# Function to check if storage account name is available
check_storage_availability() {
    local available=$(az storage account check-name --name "$STORAGE_ACCOUNT" --query "nameAvailable" --output tsv)
    if [[ "$available" != "true" ]]; then
        log_error "Storage account name '$STORAGE_ACCOUNT' is not available"
        local reason=$(az storage account check-name --name "$STORAGE_ACCOUNT" --query "reason" --output tsv)
        log_error "Reason: $reason"
        exit 1
    fi
}

# Create storage account
log_info "Checking storage account name availability..."
check_storage_availability

log_info "Creating storage account..."
az storage account create \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --access-tier Hot \
    --allow-blob-public-access true \
    --tags purpose=tutorial-storage environment=demo

# Wait for storage account to be ready
log_info "Waiting for storage account to be ready..."
sleep 30

# Get storage account key
log_info "Retrieving storage account key..."
STORAGE_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query '[0].value' --output tsv)

if [[ -z "$STORAGE_KEY" ]]; then
    log_error "Failed to retrieve storage account key"
    exit 1
fi

log_success "Storage account created: $STORAGE_ACCOUNT"

# Create storage containers
log_info "Creating storage containers..."

# Create tutorials container (public blob access)
az storage container create \
    --name tutorials \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$STORAGE_KEY" \
    --public-access blob

# Create metadata container (private access)
az storage container create \
    --name metadata \
    --account-name "$STORAGE_ACCOUNT" \
    --account-key "$STORAGE_KEY" \
    --public-access off

log_success "Storage containers created successfully"

# Create Azure OpenAI service
log_info "Creating Azure OpenAI service..."

# Check if OpenAI account name is available
OPENAI_AVAILABLE=$(az cognitiveservices account check-name \
    --name "$OPENAI_ACCOUNT" \
    --type Microsoft.CognitiveServices/accounts \
    --query "nameAvailable" --output tsv)

if [[ "$OPENAI_AVAILABLE" != "true" ]]; then
    log_error "OpenAI account name '$OPENAI_ACCOUNT' is not available"
    exit 1
fi

az cognitiveservices account create \
    --name "$OPENAI_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --kind OpenAI \
    --sku S0 \
    --custom-domain "$OPENAI_ACCOUNT" \
    --tags purpose=tutorial-generation environment=demo

log_success "Azure OpenAI service created: $OPENAI_ACCOUNT"

# Get OpenAI endpoint and key
log_info "Retrieving OpenAI service credentials..."
OPENAI_ENDPOINT=$(az cognitiveservices account show \
    --name "$OPENAI_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query properties.endpoint --output tsv)

OPENAI_KEY=$(az cognitiveservices account keys list \
    --name "$OPENAI_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query key1 --output tsv)

if [[ -z "$OPENAI_ENDPOINT" ]] || [[ -z "$OPENAI_KEY" ]]; then
    log_error "Failed to retrieve OpenAI service credentials"
    exit 1
fi

log_success "OpenAI endpoint: $OPENAI_ENDPOINT"

# Deploy GPT-4o-mini model
log_info "Deploying GPT-4o-mini model..."
az cognitiveservices account deployment create \
    --name "$OPENAI_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --deployment-name gpt-4o-mini \
    --model-name gpt-4o-mini \
    --model-version "2024-07-18" \
    --model-format OpenAI \
    --sku-capacity 10 \
    --sku-name Standard

log_info "Waiting for model deployment to complete..."
sleep 60

# Verify model deployment
MODEL_STATUS=$(az cognitiveservices account deployment show \
    --name "$OPENAI_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --deployment-name gpt-4o-mini \
    --query "properties.provisioningState" --output tsv)

if [[ "$MODEL_STATUS" != "Succeeded" ]]; then
    log_warning "Model deployment status: $MODEL_STATUS"
    log_warning "Deployment may still be in progress"
else
    log_success "GPT-4o-mini model deployed successfully"
fi

# Create Function App
log_info "Creating Function App..."

# Check if function app name is available
FUNC_AVAILABLE=$(az functionapp list --query "[?name=='$FUNCTION_APP']" --output tsv)
if [[ -n "$FUNC_AVAILABLE" ]]; then
    log_error "Function app name '$FUNCTION_APP' is not available"
    exit 1
fi

az functionapp create \
    --name "$FUNCTION_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --storage-account "$STORAGE_ACCOUNT" \
    --consumption-plan-location "$LOCATION" \
    --runtime python \
    --runtime-version 3.11 \
    --functions-version 4 \
    --os-type Linux \
    --tags purpose=tutorial-processing environment=demo

log_success "Function App created: $FUNCTION_APP"

# Configure Function App settings
log_info "Configuring Function App settings..."
az functionapp config appsettings set \
    --name "$FUNCTION_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --settings \
    "OPENAI_ENDPOINT=$OPENAI_ENDPOINT" \
    "OPENAI_KEY=$OPENAI_KEY" \
    "STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT" \
    "STORAGE_ACCOUNT_KEY=$STORAGE_KEY" \
    "DEPLOYMENT_NAME=gpt-4o-mini"

log_success "Function app configured with OpenAI and Storage settings"

# Create temporary directory for function code
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Create function code
log_info "Creating function code..."
cat > function_app.py << 'EOF'
import azure.functions as func
import json
import logging
from azure.ai.openai import OpenAIClient
from azure.core.credentials import AzureKeyCredential
from azure.storage.blob import BlobServiceClient
import os
from datetime import datetime
import uuid

app = func.FunctionApp()

@app.function_name(name="GenerateTutorial")
@app.route(route="generate", methods=["POST"])
def generate_tutorial(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Tutorial generation request received.')
    
    try:
        # Parse request
        req_body = req.get_json()
        topic = req_body.get('topic', 'Python basics')
        difficulty = req_body.get('difficulty', 'beginner')
        language = req_body.get('language', 'python')
        
        # Initialize OpenAI client
        openai_client = OpenAIClient(
            endpoint=os.environ["OPENAI_ENDPOINT"],
            credential=AzureKeyCredential(os.environ["OPENAI_KEY"])
        )
        
        # Generate tutorial content
        tutorial_content = generate_tutorial_content(
            openai_client, topic, difficulty, language
        )
        
        # Store in blob storage
        tutorial_id = store_tutorial(tutorial_content, topic, difficulty, language)
        
        return func.HttpResponse(
            json.dumps({
                "tutorial_id": tutorial_id,
                "status": "success",
                "content_preview": tutorial_content[:200] + "..."
            }),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logging.error(f"Error generating tutorial: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )

def generate_tutorial_content(client, topic, difficulty, language):
    """Generate tutorial content using OpenAI"""
    
    prompt = f"""
    Create a comprehensive coding tutorial for the topic: {topic}
    Difficulty level: {difficulty}
    Programming language: {language}
    
    Format the tutorial with the following structure:
    1. Introduction (2-3 sentences)
    2. Prerequisites
    3. Step-by-step instructions (5-7 steps)
    4. Code examples with explanations
    5. Practice exercises (3 exercises)
    6. Common pitfalls and solutions
    7. Next steps for further learning
    
    Make it engaging and practical with real-world examples.
    Include code snippets that are properly formatted and commented.
    """
    
    response = client.chat.completions.create(
        model=os.environ["DEPLOYMENT_NAME"],
        messages=[
            {"role": "system", "content": "You are an expert programming instructor creating educational content."},
            {"role": "user", "content": prompt}
        ],
        max_tokens=2000,
        temperature=0.7
    )
    
    return response.choices[0].message.content

def store_tutorial(content, topic, difficulty, language):
    """Store tutorial in blob storage"""
    
    # Initialize blob client
    blob_service_client = BlobServiceClient(
        account_url=f"https://{os.environ['STORAGE_ACCOUNT_NAME']}.blob.core.windows.net",
        credential=os.environ["STORAGE_ACCOUNT_KEY"]
    )
    
    # Generate unique tutorial ID
    tutorial_id = str(uuid.uuid4())
    
    # Create tutorial metadata
    metadata = {
        "topic": topic,
        "difficulty": difficulty,
        "language": language,
        "created_at": datetime.utcnow().isoformat(),
        "tutorial_id": tutorial_id
    }
    
    # Upload tutorial content
    blob_client = blob_service_client.get_blob_client(
        container="tutorials", 
        blob=f"{tutorial_id}.md"
    )
    blob_client.upload_blob(content, overwrite=True)
    
    # Upload metadata
    metadata_client = blob_service_client.get_blob_client(
        container="metadata", 
        blob=f"{tutorial_id}.json"
    )
    metadata_client.upload_blob(json.dumps(metadata), overwrite=True)
    
    return tutorial_id

@app.function_name(name="GetTutorial")
@app.route(route="tutorial/{tutorial_id}", methods=["GET"])
def get_tutorial(req: func.HttpRequest) -> func.HttpResponse:
    """Retrieve a tutorial by ID"""
    
    tutorial_id = req.route_params.get('tutorial_id')
    
    try:
        # Initialize blob client
        blob_service_client = BlobServiceClient(
            account_url=f"https://{os.environ['STORAGE_ACCOUNT_NAME']}.blob.core.windows.net",
            credential=os.environ["STORAGE_ACCOUNT_KEY"]
        )
        
        # Get tutorial content
        blob_client = blob_service_client.get_blob_client(
            container="tutorials", 
            blob=f"{tutorial_id}.md"
        )
        content = blob_client.download_blob().readall().decode('utf-8')
        
        # Get metadata
        metadata_client = blob_service_client.get_blob_client(
            container="metadata", 
            blob=f"{tutorial_id}.json"
        )
        metadata = json.loads(metadata_client.download_blob().readall().decode('utf-8'))
        
        return func.HttpResponse(
            json.dumps({
                "tutorial_id": tutorial_id,
                "content": content,
                "metadata": metadata
            }),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logging.error(f"Error retrieving tutorial: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": "Tutorial not found"}),
            status_code=404,
            mimetype="application/json"
        )
EOF

# Create requirements file
cat > requirements.txt << 'EOF'
azure-functions
azure-ai-openai
azure-storage-blob
azure-core
EOF

log_success "Function code created successfully"

# Deploy function
log_info "Deploying function to Azure..."

# Check if zip command is available
if ! command -v zip &> /dev/null; then
    log_error "zip command not found. Please install zip utility."
    exit 1
fi

zip -r function.zip . > /dev/null

# Deploy using zip
az functionapp deployment source config-zip \
    --name "$FUNCTION_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --src function.zip

log_info "Waiting for function deployment to complete..."
sleep 90

# Verify deployment
FUNC_STATUS=$(az functionapp show \
    --name "$FUNCTION_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --query "state" --output tsv)

if [[ "$FUNC_STATUS" != "Running" ]]; then
    log_warning "Function app status: $FUNC_STATUS"
    log_warning "Function app may still be starting up"
else
    log_success "Function deployed successfully"
fi

# Clean up temporary directory
cd - > /dev/null
rm -rf "$TEMP_DIR"

# Configure CORS
log_info "Configuring CORS for web access..."
az functionapp cors add \
    --name "$FUNCTION_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --allowed-origins "*"

log_success "CORS configured for web access"

# Get function app URL
FUNCTION_URL="https://${FUNCTION_APP}.azurewebsites.net"

# Update deployment log with final information
cat >> "$DEPLOYMENT_LOG" << EOF
OPENAI_ENDPOINT="$OPENAI_ENDPOINT"
FUNCTION_URL="$FUNCTION_URL"
DEPLOYMENT_COMPLETED="$(date)"
EOF

# Final deployment summary
log_success "Deployment completed successfully!"
echo
log_info "Deployment Summary:"
log_info "  Resource Group: $RESOURCE_GROUP"
log_info "  Storage Account: $STORAGE_ACCOUNT"
log_info "  Function App: $FUNCTION_APP"
log_info "  OpenAI Service: $OPENAI_ACCOUNT"
log_info "  Function URL: $FUNCTION_URL"
echo
log_info "Test the deployment with:"
echo "curl -X POST \"$FUNCTION_URL/api/generate\" \\"
echo "     -H \"Content-Type: application/json\" \\"
echo "     -d '{\"topic\": \"Python Functions\", \"difficulty\": \"beginner\", \"language\": \"python\"}'"
echo
log_info "Deployment log saved to: $DEPLOYMENT_LOG"
log_warning "Remember to run the destroy script to clean up resources when done!"