#!/bin/bash

# Deploy script for Multi-Modal Content Generation Workflows
# Recipe: Automated Multimodal Content Generation Workflows
# This script deploys the complete infrastructure for multi-modal AI content generation

set -euo pipefail

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

# Error handling function
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate Azure CLI login
validate_azure_login() {
    log_info "Validating Azure CLI authentication..."
    if ! az account show >/dev/null 2>&1; then
        error_exit "Azure CLI not logged in. Please run 'az login' first."
    fi
    
    local subscription_id=$(az account show --query id --output tsv)
    local account_name=$(az account show --query name --output tsv)
    log_success "Authenticated to Azure subscription: $account_name ($subscription_id)"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' --output tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check Docker
    if ! command_exists docker; then
        error_exit "Docker is not installed. Please install Docker Desktop from https://www.docker.com/products/docker-desktop"
    fi
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        error_exit "Docker is not running. Please start Docker Desktop."
    fi
    
    # Check required Azure providers
    log_info "Checking Azure resource providers..."
    az provider register --namespace Microsoft.MachineLearningServices --wait
    az provider register --namespace Microsoft.ContainerRegistry --wait
    az provider register --namespace Microsoft.EventGrid --wait
    az provider register --namespace Microsoft.KeyVault --wait
    az provider register --namespace Microsoft.Storage --wait
    az provider register --namespace Microsoft.Web --wait
    
    log_success "Prerequisites validated successfully"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set Azure resource names
    export RESOURCE_GROUP="rg-multimodal-content-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set specific resource names
    export AI_FOUNDRY_HUB="aif-hub-${RANDOM_SUFFIX}"
    export AI_FOUNDRY_PROJECT="aif-project-${RANDOM_SUFFIX}"
    export CONTAINER_REGISTRY="acr${RANDOM_SUFFIX}"
    export EVENT_GRID_TOPIC="egt-content-${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-content-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stcontent${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="func-content-${RANDOM_SUFFIX}"
    
    # Deployment configuration
    export DEPLOYMENT_LOG="deployment-$(date +%Y%m%d-%H%M%S).log"
    
    log_success "Environment variables configured"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Unique Suffix: $RANDOM_SUFFIX"
    log_info "Deployment Log: $DEPLOYMENT_LOG"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=multi-modal-content environment=demo created-by=azure-recipe \
            >> "$DEPLOYMENT_LOG" 2>&1
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Create storage account
create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --allow-blob-public-access false \
        --min-tls-version TLS1_2 \
        >> "$DEPLOYMENT_LOG" 2>&1
    
    # Wait for storage account to be ready
    log_info "Waiting for storage account to be fully provisioned..."
    sleep 30
    
    log_success "Storage account created: $STORAGE_ACCOUNT"
}

# Create Key Vault
create_key_vault() {
    log_info "Creating Key Vault: $KEY_VAULT_NAME"
    
    # Create Key Vault with RBAC authorization
    az keyvault create \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku standard \
        --enable-rbac-authorization true \
        --enable-soft-delete true \
        --retention-days 7 \
        >> "$DEPLOYMENT_LOG" 2>&1
    
    # Get current user object ID for RBAC assignment
    local current_user_id=$(az ad signed-in-user show --query id --output tsv)
    
    # Assign Key Vault Administrator role to current user
    az role assignment create \
        --assignee "$current_user_id" \
        --role "Key Vault Administrator" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME" \
        >> "$DEPLOYMENT_LOG" 2>&1
    
    # Wait for role assignment to propagate
    log_info "Waiting for Key Vault RBAC permissions to propagate..."
    sleep 60
    
    log_success "Key Vault created with RBAC authorization: $KEY_VAULT_NAME"
}

# Create Container Registry
create_container_registry() {
    log_info "Creating Azure Container Registry: $CONTAINER_REGISTRY"
    
    # Create Premium tier ACR for advanced features
    az acr create \
        --name "$CONTAINER_REGISTRY" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Premium \
        --admin-enabled false \
        >> "$DEPLOYMENT_LOG" 2>&1
    
    # Enable system-assigned managed identity for ACR
    az acr identity assign \
        --name "$CONTAINER_REGISTRY" \
        --identities [system] \
        >> "$DEPLOYMENT_LOG" 2>&1
    
    # Get ACR login server for later use
    export ACR_LOGIN_SERVER=$(az acr show \
        --name "$CONTAINER_REGISTRY" \
        --resource-group "$RESOURCE_GROUP" \
        --query loginServer --output tsv)
    
    log_success "Container Registry created: $ACR_LOGIN_SERVER"
}

# Create AI Foundry Hub and Project
create_ai_foundry() {
    log_info "Creating Azure AI Foundry Hub: $AI_FOUNDRY_HUB"
    
    # Create AI Foundry Hub
    az ml workspace create \
        --name "$AI_FOUNDRY_HUB" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind hub \
        --storage-account "$STORAGE_ACCOUNT" \
        --key-vault "$KEY_VAULT_NAME" \
        --container-registry "$CONTAINER_REGISTRY" \
        >> "$DEPLOYMENT_LOG" 2>&1
    
    log_info "Creating Azure AI Foundry Project: $AI_FOUNDRY_PROJECT"
    
    # Create AI Foundry Project within the Hub
    az ml workspace create \
        --name "$AI_FOUNDRY_PROJECT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind project \
        --hub-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.MachineLearningServices/workspaces/$AI_FOUNDRY_HUB" \
        >> "$DEPLOYMENT_LOG" 2>&1
    
    log_success "AI Foundry Hub and Project created successfully"
}

# Deploy AI models (placeholder - actual model deployment requires model catalog access)
deploy_ai_models() {
    log_info "Preparing AI model deployment configurations..."
    
    # Note: Actual model deployment would require access to Azure AI model catalog
    # and specific model deployment configurations
    log_warning "AI model deployment requires manual setup in Azure AI Foundry portal"
    log_info "Please visit the Azure AI Foundry portal to deploy:"
    log_info "1. GPT-4o model for text generation"
    log_info "2. DALL-E 3 model for image generation"
    log_info "3. Speech synthesis models for audio generation"
    
    # Create placeholder deployment endpoints configuration
    cat > ai-model-endpoints.json << 'EOF'
{
  "text_generation": {
    "model": "gpt-4o",
    "deployment_name": "gpt4o-text-deployment",
    "instance_type": "Standard_NC6s_v3"
  },
  "image_generation": {
    "model": "dall-e-3",
    "deployment_name": "dalle3-image-deployment",
    "instance_type": "Standard_NC12s_v3"
  },
  "speech_synthesis": {
    "model": "tts-1",
    "deployment_name": "tts-speech-deployment",
    "instance_type": "Standard_D2s_v3"
  }
}
EOF
    
    log_success "AI model deployment configuration created"
}

# Create Event Grid Topic
create_event_grid() {
    log_info "Creating Event Grid Topic: $EVENT_GRID_TOPIC"
    
    # Create Event Grid custom topic
    az eventgrid topic create \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --input-schema CloudEventSchemaV1_0 \
        >> "$DEPLOYMENT_LOG" 2>&1
    
    # Get Event Grid topic endpoint and access key
    local topic_endpoint=$(az eventgrid topic show \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query endpoint --output tsv)
    
    local topic_key=$(az eventgrid topic key list \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    # Store Event Grid credentials in Key Vault
    log_info "Storing Event Grid credentials in Key Vault..."
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "eventgrid-endpoint" \
        --value "$topic_endpoint" \
        >> "$DEPLOYMENT_LOG" 2>&1
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "eventgrid-key" \
        --value "$topic_key" \
        >> "$DEPLOYMENT_LOG" 2>&1
    
    log_success "Event Grid topic created: $EVENT_GRID_TOPIC"
}

# Build and deploy custom AI model container
build_custom_container() {
    log_info "Building custom AI model container..."
    
    # Create sample custom model container structure
    mkdir -p custom-ai-model/src
    
    # Create Dockerfile for custom AI model
    cat > custom-ai-model/Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Install required packages
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy model code
COPY src/ ./src/

# Expose port for model inference
EXPOSE 8080

# Start model server
CMD ["python", "src/model_server.py"]
EOF

    # Create requirements.txt
    cat > custom-ai-model/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
transformers==4.35.2
torch==2.1.0
numpy==1.24.3
pillow==10.0.1
EOF

    # Create basic model server
    cat > custom-ai-model/src/model_server.py << 'EOF'
from fastapi import FastAPI
import uvicorn

app = FastAPI(title="Custom AI Model Server")

@app.get("/health")
def health_check():
    return {"status": "healthy"}

@app.post("/predict")
def predict(data: dict):
    # Placeholder for custom AI model inference
    return {"result": "Custom AI processing completed", "input": data}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
EOF

    # Build and push container to ACR
    cd custom-ai-model
    
    # Login to ACR
    log_info "Logging into Azure Container Registry..."
    az acr login --name "$CONTAINER_REGISTRY" >> "../$DEPLOYMENT_LOG" 2>&1
    
    # Build container image
    log_info "Building custom AI model container..."
    docker build -t "$ACR_LOGIN_SERVER/custom-ai-model:v1.0" . >> "../$DEPLOYMENT_LOG" 2>&1
    
    # Push to ACR
    log_info "Pushing container to Azure Container Registry..."
    docker push "$ACR_LOGIN_SERVER/custom-ai-model:v1.0" >> "../$DEPLOYMENT_LOG" 2>&1
    
    cd ..
    
    log_success "Custom AI model container deployed to ACR"
}

# Create Function App for workflow orchestration
create_function_app() {
    log_info "Creating Function App: $FUNCTION_APP_NAME"
    
    # Create Function App for workflow orchestration
    az functionapp create \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --consumption-plan-location "$LOCATION" \
        --runtime python \
        --runtime-version 3.9 \
        --functions-version 4 \
        --os-type Linux \
        >> "$DEPLOYMENT_LOG" 2>&1
    
    # Get storage connection string
    local storage_key=$(az storage account keys list \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query '[0].value' --output tsv)
    
    local storage_connection_string="DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT;AccountKey=$storage_key;EndpointSuffix=core.windows.net"
    
    # Configure Function App settings
    az functionapp config appsettings set \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
            "STORAGE_CONNECTION_STRING=$storage_connection_string" \
            "KEY_VAULT_URL=https://$KEY_VAULT_NAME.vault.azure.net/" \
            "CONTAINER_REGISTRY_URL=$ACR_LOGIN_SERVER" \
        >> "$DEPLOYMENT_LOG" 2>&1
    
    log_success "Function App created and configured: $FUNCTION_APP_NAME"
}

# Create content coordination configuration
create_coordination_config() {
    log_info "Creating content coordination configuration..."
    
    # Create content coordination configuration
    cat > content-coordination-config.json << 'EOF'
{
  "workflows": {
    "marketing_campaign": {
      "text_model": "gpt-4o",
      "image_model": "dall-e-3",
      "audio_model": "speech-synthesis",
      "coordination_rules": {
        "style_consistency": true,
        "brand_alignment": true,
        "message_coherence": true
      }
    },
    "social_media": {
      "text_model": "gpt-4o-mini",
      "image_model": "dall-e-3",
      "coordination_rules": {
        "platform_optimization": true,
        "engagement_focus": true
      }
    }
  },
  "quality_gates": {
    "content_safety": true,
    "brand_compliance": true,
    "technical_validation": true
  }
}
EOF

    # Store configuration in Key Vault
    local coordination_config=$(cat content-coordination-config.json | base64 -w 0)
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "content-coordination-config" \
        --value "$coordination_config" \
        >> "$DEPLOYMENT_LOG" 2>&1
    
    # Create sample workflow trigger event
    cat > sample-event.json << 'EOF'
{
  "specversion": "1.0",
  "type": "content.generation.requested",
  "source": "/marketing/campaigns",
  "id": "campaign-001",
  "time": "2025-07-12T10:00:00Z",
  "data": {
    "workflow_type": "marketing_campaign",
    "content_requirements": {
      "topic": "Product Launch",
      "target_audience": "Technology Professionals",
      "brand_guidelines": "professional_modern",
      "output_formats": ["blog_post", "social_image", "podcast_intro"]
    },
    "metadata": {
      "priority": "high",
      "deadline": "2025-07-15T17:00:00Z"
    }
  }
}
EOF
    
    log_success "Content coordination configuration created and stored"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > deployment-info.json << EOF
{
  "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "resource_group": "$RESOURCE_GROUP",
  "location": "$LOCATION",
  "subscription_id": "$SUBSCRIPTION_ID",
  "resources": {
    "ai_foundry_hub": "$AI_FOUNDRY_HUB",
    "ai_foundry_project": "$AI_FOUNDRY_PROJECT",
    "container_registry": "$CONTAINER_REGISTRY",
    "container_registry_url": "$ACR_LOGIN_SERVER",
    "event_grid_topic": "$EVENT_GRID_TOPIC",
    "key_vault": "$KEY_VAULT_NAME",
    "storage_account": "$STORAGE_ACCOUNT",
    "function_app": "$FUNCTION_APP_NAME"
  },
  "random_suffix": "$RANDOM_SUFFIX"
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

# Display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "============================="
    echo "DEPLOYMENT SUMMARY"
    echo "============================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Unique Suffix: $RANDOM_SUFFIX"
    echo
    echo "Created Resources:"
    echo "- AI Foundry Hub: $AI_FOUNDRY_HUB"
    echo "- AI Foundry Project: $AI_FOUNDRY_PROJECT"
    echo "- Container Registry: $ACR_LOGIN_SERVER"
    echo "- Event Grid Topic: $EVENT_GRID_TOPIC"
    echo "- Key Vault: $KEY_VAULT_NAME"
    echo "- Storage Account: $STORAGE_ACCOUNT"
    echo "- Function App: $FUNCTION_APP_NAME"
    echo
    echo "Next Steps:"
    echo "1. Visit Azure AI Foundry portal to deploy AI models"
    echo "2. Configure Event Grid subscriptions"
    echo "3. Deploy Function App code for workflow orchestration"
    echo "4. Test the multi-modal content generation pipeline"
    echo
    echo "Clean up: Run './destroy.sh' to remove all resources"
    echo "============================="
}

# Main execution function
main() {
    log_info "Starting Azure Multi-Modal Content Generation Workflow deployment..."
    
    # Create deployment log
    touch "$DEPLOYMENT_LOG"
    
    # Execute deployment steps
    check_prerequisites
    validate_azure_login
    setup_environment
    create_resource_group
    create_storage_account
    create_key_vault
    create_container_registry
    create_ai_foundry
    deploy_ai_models
    create_event_grid
    build_custom_container
    create_function_app
    create_coordination_config
    save_deployment_info
    display_summary
    
    log_success "Deployment script completed successfully!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi