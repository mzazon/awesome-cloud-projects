#!/bin/bash

# Deploy script for Automated Content Generation with Prompt Flow and OpenAI
# This script deploys the complete infrastructure for automated content generation
# using Azure AI Prompt Flow, Azure OpenAI Service, and Azure Functions

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    log_info "You can run ./destroy.sh to clean up any partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Functions Core Tools is installed
    if ! command -v func &> /dev/null; then
        log_warning "Azure Functions Core Tools not found. Some features may not work."
    fi
    
    # Check minimum Azure CLI version (2.60.0 or later)
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    local min_version="2.60.0"
    if [[ "$(printf '%s\n' "$min_version" "$az_version" | sort -V | head -n1)" != "$min_version" ]]; then
        log_error "Azure CLI version $az_version is too old. Please upgrade to $min_version or later."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Initialize deployment state
init_deployment_state() {
    echo "# Deployment state file - tracks created resources" > "${DEPLOYMENT_STATE_FILE}"
    echo "# Format: RESOURCE_TYPE=RESOURCE_NAME" >> "${DEPLOYMENT_STATE_FILE}"
}

# Save resource to state file
save_resource_state() {
    local resource_type=$1
    local resource_name=$2
    echo "${resource_type}=${resource_name}" >> "${DEPLOYMENT_STATE_FILE}"
}

# Configuration and variables
set_variables() {
    log_info "Setting up deployment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-content-gen-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Resource names
    export ML_WORKSPACE_NAME="ml-contentgen-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="storcontentgen${RANDOM_SUFFIX}"
    export OPENAI_ACCOUNT_NAME="aoai-contentgen-${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="func-contentgen-${RANDOM_SUFFIX}"
    export COSMOS_ACCOUNT_NAME="cosmos-contentgen-${RANDOM_SUFFIX}"
    
    # Validate storage account name length (3-24 characters)
    if [[ ${#STORAGE_ACCOUNT_NAME} -gt 24 ]]; then
        log_error "Storage account name '${STORAGE_ACCOUNT_NAME}' is too long (max 24 characters)"
        exit 1
    fi
    
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
    
    # Save variables to state file
    save_resource_state "RESOURCE_GROUP" "${RESOURCE_GROUP}"
    save_resource_state "LOCATION" "${LOCATION}"
    save_resource_state "RANDOM_SUFFIX" "${RANDOM_SUFFIX}"
}

# Confirm deployment
confirm_deployment() {
    log_info "This will deploy the following resources:"
    echo "  - Resource Group: ${RESOURCE_GROUP}"
    echo "  - ML Workspace: ${ML_WORKSPACE_NAME}"
    echo "  - Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "  - OpenAI Service: ${OPENAI_ACCOUNT_NAME}"
    echo "  - Function App: ${FUNCTION_APP_NAME}"
    echo "  - Cosmos DB: ${COSMOS_ACCOUNT_NAME}"
    echo ""
    echo "Estimated cost: \$20-30 for completing this recipe"
    echo ""
    
    if [[ "${AUTO_APPROVE:-false}" != "true" ]]; then
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=recipe environment=demo \
            --output none
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Create Azure Machine Learning workspace
create_ml_workspace() {
    log_info "Creating Azure Machine Learning workspace: ${ML_WORKSPACE_NAME}"
    
    # Check if ML extension is installed
    if ! az extension show --name ml &> /dev/null; then
        log_info "Installing Azure ML CLI extension..."
        az extension add --name ml --yes
    fi
    
    if az ml workspace show --name "${ML_WORKSPACE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "ML workspace ${ML_WORKSPACE_NAME} already exists"
    else
        az ml workspace create \
            --name "${ML_WORKSPACE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --display-name "Content Generation ML Workspace" \
            --output none
        
        log_success "Azure ML workspace created: ${ML_WORKSPACE_NAME}"
        save_resource_state "ML_WORKSPACE" "${ML_WORKSPACE_NAME}"
    fi
    
    # Get workspace details
    export ML_WORKSPACE_ID=$(az ml workspace show \
        --name "${ML_WORKSPACE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
}

# Create Azure OpenAI Service
create_openai_service() {
    log_info "Creating Azure OpenAI Service: ${OPENAI_ACCOUNT_NAME}"
    
    if az cognitiveservices account show --name "${OPENAI_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "OpenAI service ${OPENAI_ACCOUNT_NAME} already exists"
    else
        # Check if OpenAI is available in the selected region
        local available_locations=$(az cognitiveservices account list-skus \
            --kind OpenAI \
            --query "[?resourceType=='Microsoft.CognitiveServices/accounts'].locations[]" \
            --output tsv | tr '\n' ' ')
        
        if [[ ! " ${available_locations} " =~ " ${LOCATION} " ]]; then
            log_warning "OpenAI service may not be available in ${LOCATION}. Available locations: ${available_locations}"
        fi
        
        az cognitiveservices account create \
            --name "${OPENAI_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --kind OpenAI \
            --sku S0 \
            --custom-domain "${OPENAI_ACCOUNT_NAME}" \
            --output none
        
        log_success "Azure OpenAI service created: ${OPENAI_ACCOUNT_NAME}"
        save_resource_state "OPENAI_ACCOUNT" "${OPENAI_ACCOUNT_NAME}"
    fi
    
    # Get OpenAI endpoint and key
    export OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "${OPENAI_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.endpoint --output tsv)
    
    export OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "${OPENAI_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 --output tsv)
}

# Deploy AI models
deploy_ai_models() {
    log_info "Deploying AI models for content generation..."
    
    # Deploy GPT-4o model
    log_info "Deploying GPT-4o model..."
    if az cognitiveservices account deployment show \
        --name "${OPENAI_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name gpt-4o-content &> /dev/null; then
        log_warning "GPT-4o deployment already exists"
    else
        az cognitiveservices account deployment create \
            --name "${OPENAI_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --deployment-name gpt-4o-content \
            --model-name gpt-4o \
            --model-version "2024-11-20" \
            --model-format OpenAI \
            --sku-name Standard \
            --sku-capacity 10 \
            --output none
        
        log_success "GPT-4o model deployed"
        save_resource_state "GPT4O_DEPLOYMENT" "gpt-4o-content"
    fi
    
    # Deploy text embedding model
    log_info "Deploying text embedding model..."
    if az cognitiveservices account deployment show \
        --name "${OPENAI_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name text-embedding-ada-002 &> /dev/null; then
        log_warning "Text embedding deployment already exists"
    else
        az cognitiveservices account deployment create \
            --name "${OPENAI_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --deployment-name text-embedding-ada-002 \
            --model-name text-embedding-ada-002 \
            --model-version "2" \
            --model-format OpenAI \
            --sku-name Standard \
            --sku-capacity 10 \
            --output none
        
        log_success "Text embedding model deployed"
        save_resource_state "EMBEDDING_DEPLOYMENT" "text-embedding-ada-002"
    fi
}

# Create storage account
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT_NAME}"
    
    if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account ${STORAGE_ACCOUNT_NAME} already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --hierarchical-namespace true \
            --enable-large-file-share \
            --output none
        
        log_success "Storage account created: ${STORAGE_ACCOUNT_NAME}"
        save_resource_state "STORAGE_ACCOUNT" "${STORAGE_ACCOUNT_NAME}"
    fi
    
    # Get storage connection string
    export STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString --output tsv)
    
    # Create containers
    log_info "Creating storage containers..."
    az storage container create \
        --name "content-templates" \
        --connection-string "${STORAGE_CONNECTION_STRING}" \
        --output none
    
    az storage container create \
        --name "generated-content" \
        --connection-string "${STORAGE_CONNECTION_STRING}" \
        --output none
    
    log_success "Storage containers created"
}

# Create Cosmos DB
create_cosmos_db() {
    log_info "Creating Cosmos DB account: ${COSMOS_ACCOUNT_NAME}"
    
    if az cosmosdb show --name "${COSMOS_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Cosmos DB account ${COSMOS_ACCOUNT_NAME} already exists"
    else
        az cosmosdb create \
            --name "${COSMOS_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --locations regionName="${LOCATION}" \
            --default-consistency-level Eventual \
            --enable-automatic-failover false \
            --enable-multiple-write-locations false \
            --output none
        
        log_success "Cosmos DB account created: ${COSMOS_ACCOUNT_NAME}"
        save_resource_state "COSMOS_ACCOUNT" "${COSMOS_ACCOUNT_NAME}"
    fi
    
    # Create database and container
    log_info "Creating Cosmos DB database and container..."
    
    if az cosmosdb sql database show \
        --account-name "${COSMOS_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name ContentGeneration &> /dev/null; then
        log_warning "Cosmos DB database already exists"
    else
        az cosmosdb sql database create \
            --account-name "${COSMOS_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --name ContentGeneration \
            --output none
        
        log_success "Cosmos DB database created"
    fi
    
    if az cosmosdb sql container show \
        --account-name "${COSMOS_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --database-name ContentGeneration \
        --name ContentMetadata &> /dev/null; then
        log_warning "Cosmos DB container already exists"
    else
        az cosmosdb sql container create \
            --account-name "${COSMOS_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --database-name ContentGeneration \
            --name ContentMetadata \
            --partition-key-path "/campaignId" \
            --throughput 400 \
            --output none
        
        log_success "Cosmos DB container created"
    fi
    
    # Get Cosmos DB connection details
    export COSMOS_ENDPOINT=$(az cosmosdb show \
        --name "${COSMOS_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query documentEndpoint --output tsv)
    
    export COSMOS_KEY=$(az cosmosdb keys list \
        --name "${COSMOS_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query primaryMasterKey --output tsv)
}

# Configure Prompt Flow connection
configure_prompt_flow() {
    log_info "Configuring Prompt Flow connection..."
    
    # Create connection configuration
    cat > "${SCRIPT_DIR}/aoai-connection.yaml" << EOF
\$schema: https://azuremlschemas.azureedge.net/latest/connection.schema.json
name: aoai-content-generation
type: azure_open_ai
api_base: ${OPENAI_ENDPOINT}
api_key: ${OPENAI_KEY}
api_version: "2024-02-15-preview"
EOF
    
    # Create the connection in ML workspace
    if az ml connection show \
        --name aoai-content-generation \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${ML_WORKSPACE_NAME}" &> /dev/null; then
        log_warning "Prompt Flow connection already exists"
    else
        az ml connection create \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${ML_WORKSPACE_NAME}" \
            --file "${SCRIPT_DIR}/aoai-connection.yaml" \
            --output none
        
        log_success "Prompt Flow connection configured"
        save_resource_state "PROMPT_FLOW_CONNECTION" "aoai-content-generation"
    fi
    
    # Clean up temporary file
    rm -f "${SCRIPT_DIR}/aoai-connection.yaml"
}

# Create Function App
create_function_app() {
    log_info "Creating Function App: ${FUNCTION_APP_NAME}"
    
    if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Function App ${FUNCTION_APP_NAME} already exists"
    else
        az functionapp create \
            --name "${FUNCTION_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT_NAME}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime python \
            --runtime-version 3.11 \
            --functions-version 4 \
            --os-type Linux \
            --output none
        
        log_success "Function App created: ${FUNCTION_APP_NAME}"
        save_resource_state "FUNCTION_APP" "${FUNCTION_APP_NAME}"
    fi
    
    # Configure app settings
    log_info "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "ML_WORKSPACE_NAME=${ML_WORKSPACE_NAME}" \
        "RESOURCE_GROUP=${RESOURCE_GROUP}" \
        "SUBSCRIPTION_ID=${SUBSCRIPTION_ID}" \
        "COSMOS_ENDPOINT=${COSMOS_ENDPOINT}" \
        "COSMOS_KEY=${COSMOS_KEY}" \
        "STORAGE_CONNECTION=${STORAGE_CONNECTION_STRING}" \
        --output none
    
    log_success "Function App configured"
}

# Create Prompt Flow assets
create_prompt_flow_assets() {
    log_info "Creating Prompt Flow assets..."
    
    # Create flow directory structure
    local flow_dir="${SCRIPT_DIR}/content-generation-flow"
    mkdir -p "${flow_dir}"
    
    # Create flow definition
    cat > "${flow_dir}/flow.dag.yaml" << 'EOF'
inputs:
  campaign_type:
    type: string
    default: "social_media"
  target_audience:
    type: string
    default: "general"
  content_tone:
    type: string
    default: "professional"
  key_messages:
    type: string
    default: ""

outputs:
  generated_content:
    type: string
    reference: ${format_output.output}
  content_metadata:
    type: object
    reference: ${create_metadata.output}

nodes:
- name: generate_content
  type: llm
  source:
    type: code
    path: generate_content.jinja2
  inputs:
    deployment_name: gpt-4o-content
    temperature: 0.7
    max_tokens: 1000
    campaign_type: ${inputs.campaign_type}
    target_audience: ${inputs.target_audience}
    content_tone: ${inputs.content_tone}
    key_messages: ${inputs.key_messages}
  connection: aoai-content-generation
  api: chat

- name: validate_content
  type: python
  source:
    type: code
    path: validate_content.py
  inputs:
    content: ${generate_content.output}
    tone: ${inputs.content_tone}

- name: format_output
  type: python
  source:
    type: code
    path: format_output.py
  inputs:
    content: ${validate_content.output}
    campaign_type: ${inputs.campaign_type}

- name: create_metadata
  type: python
  source:
    type: code
    path: create_metadata.py
  inputs:
    content: ${format_output.output}
    campaign_type: ${inputs.campaign_type}
    target_audience: ${inputs.target_audience}

environment:
  python_requirements_txt: requirements.txt
EOF
    
    # Create prompt template
    cat > "${flow_dir}/generate_content.jinja2" << 'EOF'
system:
You are an expert marketing content creator specializing in {{campaign_type}} campaigns. Create engaging, high-quality content that resonates with the {{target_audience}} audience using a {{content_tone}} tone.

Guidelines:
- Maintain brand consistency and professional standards
- Include relevant hashtags for social media content
- Ensure content is appropriate for the target platform
- Incorporate the key messages naturally
- Keep content length appropriate for the campaign type

user:
Create {{campaign_type}} content for {{target_audience}} audience with a {{content_tone}} tone.

Key messages to incorporate: {{key_messages}}

Requirements:
- Engaging headline or opening
- Clear value proposition
- Call-to-action when appropriate
- Platform-optimized formatting
EOF
    
    # Create Python components
    cat > "${flow_dir}/validate_content.py" << 'EOF'
import re
from typing import Dict, Any

def main(content: str, tone: str) -> Dict[str, Any]:
    """Validate generated content quality and compliance"""
    
    validation_results = {
        "is_valid": True,
        "issues": [],
        "content": content,
        "quality_score": 0
    }
    
    # Basic content quality checks
    if len(content.strip()) < 50:
        validation_results["issues"].append("Content too short")
        validation_results["is_valid"] = False
    
    if len(content.strip()) > 2000:
        validation_results["issues"].append("Content too long")
        validation_results["is_valid"] = False
    
    # Tone validation
    tone_keywords = {
        "professional": ["expertise", "solution", "quality", "reliable"],
        "casual": ["easy", "simple", "fun", "great"],
        "formal": ["please", "furthermore", "consequently", "therefore"]
    }
    
    tone_matches = 0
    if tone in tone_keywords:
        for keyword in tone_keywords[tone]:
            if keyword.lower() in content.lower():
                tone_matches += 1
    
    # Calculate quality score
    quality_score = 70  # Base score
    if tone_matches > 0:
        quality_score += 10
    if 100 <= len(content) <= 500:
        quality_score += 10
    if re.search(r'[.!?]$', content.strip()):
        quality_score += 10
    
    validation_results["quality_score"] = min(quality_score, 100)
    
    return validation_results
EOF
    
    cat > "${flow_dir}/format_output.py" << 'EOF'
import json
from datetime import datetime
from typing import Dict, Any

def main(content: Dict[str, Any], campaign_type: str) -> str:
    """Format content for specific campaign type"""
    
    if not content.get("is_valid", False):
        return json.dumps({
            "error": "Content validation failed",
            "issues": content.get("issues", [])
        })
    
    formatted_content = {
        "content": content["content"],
        "campaign_type": campaign_type,
        "quality_score": content.get("quality_score", 0),
        "generated_at": datetime.utcnow().isoformat(),
        "format_version": "1.0"
    }
    
    # Add campaign-specific formatting
    if campaign_type == "social_media":
        # Add hashtag optimization
        text = content["content"]
        if "#" not in text:
            text += " #marketing #content"
        formatted_content["content"] = text
        formatted_content["character_count"] = len(text)
    
    elif campaign_type == "email":
        # Add email structure
        formatted_content["subject_line"] = content["content"].split('\n')[0]
        formatted_content["preview_text"] = content["content"][:150] + "..."
    
    return json.dumps(formatted_content, indent=2)
EOF
    
    cat > "${flow_dir}/create_metadata.py" << 'EOF'
import json
import hashlib
from datetime import datetime
from typing import Dict, Any

def main(content: str, campaign_type: str, target_audience: str) -> Dict[str, Any]:
    """Create metadata for content tracking and analytics"""
    
    try:
        content_obj = json.loads(content)
    except:
        content_obj = {"content": content}
    
    # Generate content hash for deduplication
    content_hash = hashlib.md5(
        content_obj.get("content", "").encode()
    ).hexdigest()
    
    metadata = {
        "content_id": f"content_{content_hash[:8]}",
        "campaign_type": campaign_type,
        "target_audience": target_audience,
        "generated_timestamp": datetime.utcnow().isoformat(),
        "quality_score": content_obj.get("quality_score", 0),
        "content_hash": content_hash,
        "word_count": len(content_obj.get("content", "").split()),
        "status": "generated",
        "version": "1.0"
    }
    
    return metadata
EOF
    
    cat > "${flow_dir}/requirements.txt" << 'EOF'
azure-ai-ml
azure-identity
python-dotenv
EOF
    
    log_success "Prompt Flow assets created"
}

# Create Function code
create_function_code() {
    log_info "Creating Function App code..."
    
    local function_dir="${SCRIPT_DIR}/function-app"
    mkdir -p "${function_dir}/ContentGenerationTrigger"
    
    # Create host.json
    cat > "${function_dir}/host.json" << 'EOF'
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "excludedTypes": "Request"
      }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  }
}
EOF
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
azure-functions
azure-ai-ml==1.15.0
azure-cosmos==4.6.0
azure-identity==1.16.0
azure-storage-blob==12.19.0
requests==2.31.0
EOF
    
    # Create function.json
    cat > "${function_dir}/ContentGenerationTrigger/function.json" << 'EOF'
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["post"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "$return"
    }
  ]
}
EOF
    
    # Create function implementation
    cat > "${function_dir}/ContentGenerationTrigger/__init__.py" << 'EOF'
import azure.functions as func
import json
import logging
import os
from azure.ai.ml import MLClient
from azure.identity import DefaultAzureCredential
from azure.cosmos import CosmosClient
from azure.storage.blob import BlobServiceClient
from datetime import datetime

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Content generation function triggered')
    
    try:
        # Parse request
        req_body = req.get_json()
        if not req_body:
            return func.HttpResponse(
                json.dumps({"error": "Request body required"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Extract parameters
        campaign_type = req_body.get('campaign_type', 'social_media')
        target_audience = req_body.get('target_audience', 'general')
        content_tone = req_body.get('content_tone', 'professional')
        key_messages = req_body.get('key_messages', '')
        
        # Initialize Azure clients
        credential = DefaultAzureCredential()
        
        # Initialize ML client for prompt flow
        ml_client = MLClient(
            credential=credential,
            subscription_id=os.environ['SUBSCRIPTION_ID'],
            resource_group_name=os.environ['RESOURCE_GROUP'],
            workspace_name=os.environ['ML_WORKSPACE_NAME']
        )
        
        # Execute prompt flow (simulated for this recipe)
        flow_result = execute_content_generation_flow(
            campaign_type, target_audience, content_tone, key_messages
        )
        
        # Store results in Cosmos DB
        cosmos_client = CosmosClient(
            os.environ['COSMOS_ENDPOINT'],
            os.environ['COSMOS_KEY']
        )
        
        database = cosmos_client.get_database_client('ContentGeneration')
        container = database.get_container_client('ContentMetadata')
        
        # Store metadata
        metadata = flow_result.get('content_metadata', {})
        metadata['campaignId'] = f"campaign_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}"
        
        container.create_item(metadata)
        
        # Store content in blob storage
        blob_client = BlobServiceClient.from_connection_string(
            os.environ['STORAGE_CONNECTION']
        )
        
        content_blob = blob_client.get_blob_client(
            container='generated-content',
            blob=f"{metadata['content_id']}.json"
        )
        
        content_blob.upload_blob(
            json.dumps(flow_result['generated_content'], indent=2),
            overwrite=True
        )
        
        return func.HttpResponse(
            json.dumps({
                "status": "success",
                "content_id": metadata['content_id'],
                "campaign_id": metadata['campaignId'],
                "quality_score": metadata.get('quality_score', 0),
                "content_preview": flow_result['generated_content'][:200] + "..."
            }),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logging.error(f"Error in content generation: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Generation failed: {str(e)}"}),
            status_code=500,
            mimetype="application/json"
        )

def execute_content_generation_flow(campaign_type, target_audience, content_tone, key_messages):
    """Simulate prompt flow execution with sample content"""
    # In production, this would execute the actual prompt flow
    sample_content = f"""
🚀 Exciting News for {target_audience}!

Discover innovative solutions tailored specifically for your needs. Our {content_tone} approach ensures quality results that exceed expectations.

Key benefits:
• Industry-leading expertise
• Proven track record
• Dedicated support team

{key_messages}

Ready to transform your business? Get started today!

#innovation #business #solutions
    """
    
    return {
        "generated_content": sample_content.strip(),
        "content_metadata": {
            "content_id": f"content_{hash(sample_content) % 100000000:08d}",
            "campaign_type": campaign_type,
            "target_audience": target_audience,
            "quality_score": 85,
            "word_count": len(sample_content.split()),
            "generated_timestamp": datetime.utcnow().isoformat()
        }
    }
EOF
    
    log_success "Function App code created"
}

# Deploy Function App code
deploy_function_code() {
    log_info "Deploying Function App code..."
    
    if command -v func &> /dev/null; then
        cd "${SCRIPT_DIR}/function-app"
        
        # Deploy using Core Tools
        func azure functionapp publish "${FUNCTION_APP_NAME}" --python
        
        cd "${SCRIPT_DIR}"
        log_success "Function App code deployed"
    else
        log_warning "Azure Functions Core Tools not available. Skipping code deployment."
        log_info "To deploy the function code, install Core Tools and run:"
        log_info "  cd ${SCRIPT_DIR}/function-app"
        log_info "  func azure functionapp publish ${FUNCTION_APP_NAME} --python"
    fi
}

# Display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo ""
    echo "Created Resources:"
    echo "- ML Workspace: ${ML_WORKSPACE_NAME}"
    echo "- Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "- OpenAI Service: ${OPENAI_ACCOUNT_NAME}"
    echo "- Function App: ${FUNCTION_APP_NAME}"
    echo "- Cosmos DB: ${COSMOS_ACCOUNT_NAME}"
    echo ""
    echo "AI Models Deployed:"
    echo "- GPT-4o (2024-11-20): gpt-4o-content"
    echo "- Text Embeddings: text-embedding-ada-002"
    echo ""
    
    # Get function URL if possible
    if az functionapp function show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --function-name ContentGenerationTrigger &> /dev/null; then
        local function_url=$(az functionapp function show \
            --name "${FUNCTION_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --function-name ContentGenerationTrigger \
            --query invokeUrlTemplate --output tsv 2>/dev/null || echo "URL not available")
        echo "Function URL: ${function_url}"
    fi
    
    echo ""
    echo "Next Steps:"
    echo "1. Test the content generation function"
    echo "2. Customize the Prompt Flow templates"
    echo "3. Monitor costs in Azure Cost Management"
    echo ""
    echo "To test the function, use:"
    echo 'curl -X POST "<function-url>" -H "Content-Type: application/json" -d '\''{"campaign_type":"social_media","target_audience":"developers","content_tone":"professional"}'\'''
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log_info "Starting deployment of Automated Content Generation system"
    
    # Initialize
    init_deployment_state
    check_prerequisites
    set_variables
    confirm_deployment
    
    # Deploy infrastructure
    create_resource_group
    create_ml_workspace
    create_openai_service
    deploy_ai_models
    create_storage_account
    create_cosmos_db
    configure_prompt_flow
    create_function_app
    
    # Create assets
    create_prompt_flow_assets
    create_function_code
    deploy_function_code
    
    # Summary
    display_summary
    
    log_success "Deployment script completed successfully"
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-approve)
            export AUTO_APPROVE=true
            shift
            ;;
        --resource-group)
            export RESOURCE_GROUP="$2"
            shift 2
            ;;
        --location)
            export LOCATION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --auto-approve          Skip confirmation prompts"
            echo "  --resource-group NAME   Use specific resource group name"
            echo "  --location LOCATION     Deploy to specific Azure region"
            echo "  --help                  Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  RESOURCE_GROUP         Override default resource group name"
            echo "  LOCATION              Override default location (eastus)"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main deployment
main "$@"