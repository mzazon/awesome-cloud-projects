#!/bin/bash
set -e

# =============================================================================
# Azure Serverless AI Agents with OpenAI Service and Container Instances
# Deployment Script
# =============================================================================
# This script deploys the serverless AI agents infrastructure using Azure CLI
# Prerequisites: Azure CLI installed and authenticated

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# =============================================================================
# Prerequisites Check
# =============================================================================

log "Starting Azure Serverless AI Agents deployment..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error "Please log in to Azure CLI first: az login"
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    error "Docker is not installed. Please install it first: https://docs.docker.com/get-docker/"
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    error "Docker daemon is not running. Please start Docker first."
fi

log "Prerequisites check passed ✅"

# =============================================================================
# Configuration
# =============================================================================

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))

# Set default values
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-ai-agents-${RANDOM_SUFFIX}}"
LOCATION="${LOCATION:-eastus}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-staiagents${RANDOM_SUFFIX}}"
CONTAINER_REGISTRY="${CONTAINER_REGISTRY:-craiagents${RANDOM_SUFFIX}}"
OPENAI_RESOURCE="${OPENAI_RESOURCE:-oai-agents-${RANDOM_SUFFIX}}"
EVENTGRID_TOPIC="${EVENTGRID_TOPIC:-egt-agents-${RANDOM_SUFFIX}}"
FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-agents-${RANDOM_SUFFIX}}"
FUNCTION_APP_PLAN="${FUNCTION_APP_PLAN:-plan-agents-${RANDOM_SUFFIX}}"

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id --output tsv)

info "Configuration:"
info "  Resource Group: ${RESOURCE_GROUP}"
info "  Location: ${LOCATION}"
info "  Storage Account: ${STORAGE_ACCOUNT}"
info "  Container Registry: ${CONTAINER_REGISTRY}"
info "  OpenAI Resource: ${OPENAI_RESOURCE}"
info "  Event Grid Topic: ${EVENTGRID_TOPIC}"
info "  Function App: ${FUNCTION_APP_NAME}"
info "  Subscription ID: ${SUBSCRIPTION_ID}"

# =============================================================================
# Deployment Functions
# =============================================================================

deploy_resource_group() {
    log "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Resource group ${RESOURCE_GROUP} already exists, skipping creation"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=recipe environment=demo created-by=deploy-script
        
        log "Resource group created successfully ✅"
    fi
}

deploy_storage_account() {
    log "Creating storage account: ${STORAGE_ACCOUNT}"
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Storage account ${STORAGE_ACCOUNT} already exists, skipping creation"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --tags purpose=recipe environment=demo
        
        log "Storage account created successfully ✅"
    fi
    
    # Get connection string
    export STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString \
        --output tsv)
    
    # Create results container
    log "Creating storage container for results"
    az storage container create \
        --name results \
        --connection-string "${STORAGE_CONNECTION}" \
        --public-access off \
        --fail-on-exist false
    
    log "Storage container created successfully ✅"
}

deploy_container_registry() {
    log "Creating container registry: ${CONTAINER_REGISTRY}"
    
    if az acr show --name "${CONTAINER_REGISTRY}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Container registry ${CONTAINER_REGISTRY} already exists, skipping creation"
    else
        az acr create \
            --name "${CONTAINER_REGISTRY}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Basic \
            --admin-enabled true \
            --tags purpose=recipe environment=demo
        
        log "Container registry created successfully ✅"
    fi
    
    # Get registry credentials
    export ACR_USERNAME=$(az acr credential show \
        --name "${CONTAINER_REGISTRY}" \
        --query username \
        --output tsv)
    
    export ACR_PASSWORD=$(az acr credential show \
        --name "${CONTAINER_REGISTRY}" \
        --query passwords[0].value \
        --output tsv)
    
    log "Container registry credentials retrieved ✅"
}

deploy_openai_service() {
    log "Creating Azure OpenAI Service: ${OPENAI_RESOURCE}"
    
    if az cognitiveservices account show --name "${OPENAI_RESOURCE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "OpenAI resource ${OPENAI_RESOURCE} already exists, skipping creation"
    else
        az cognitiveservices account create \
            --name "${OPENAI_RESOURCE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --kind OpenAI \
            --sku S0 \
            --custom-domain "${OPENAI_RESOURCE}" \
            --tags purpose=recipe environment=demo
        
        log "Azure OpenAI Service created successfully ✅"
    fi
    
    # Check if GPT-4 deployment exists
    if az cognitiveservices account deployment show \
        --name "${OPENAI_RESOURCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name gpt-4 &> /dev/null; then
        warn "GPT-4 deployment already exists, skipping creation"
    else
        log "Deploying GPT-4 model"
        az cognitiveservices account deployment create \
            --name "${OPENAI_RESOURCE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --deployment-name gpt-4 \
            --model-name gpt-4 \
            --model-version "0613" \
            --model-format OpenAI \
            --scale-type "Standard"
        
        log "GPT-4 model deployed successfully ✅"
    fi
    
    # Get endpoint and key
    export OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "${OPENAI_RESOURCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.endpoint \
        --output tsv)
    
    export OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "${OPENAI_RESOURCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 \
        --output tsv)
    
    log "OpenAI Service endpoint and key retrieved ✅"
}

deploy_eventgrid_topic() {
    log "Creating Event Grid topic: ${EVENTGRID_TOPIC}"
    
    if az eventgrid topic show --name "${EVENTGRID_TOPIC}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Event Grid topic ${EVENTGRID_TOPIC} already exists, skipping creation"
    else
        az eventgrid topic create \
            --name "${EVENTGRID_TOPIC}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --input-schema EventGridSchema \
            --tags purpose=recipe environment=demo
        
        log "Event Grid topic created successfully ✅"
    fi
    
    # Get Event Grid endpoint and key
    export EVENTGRID_ENDPOINT=$(az eventgrid topic show \
        --name "${EVENTGRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query endpoint \
        --output tsv)
    
    export EVENTGRID_KEY=$(az eventgrid topic key list \
        --name "${EVENTGRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 \
        --output tsv)
    
    log "Event Grid endpoint and key retrieved ✅"
}

create_container_image() {
    log "Creating AI agent container image"
    
    # Create temporary directory for Docker build
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip install --no-cache-dir \
    openai==0.28.1 \
    azure-storage-blob==12.19.0 \
    azure-eventgrid==4.15.0 \
    azure-identity==1.15.0

# Copy agent script
COPY agent.py /app/agent.py
WORKDIR /app

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app

# Run the agent
CMD ["python", "agent.py"]
EOF
    
    # Create agent script
    cat > agent.py << 'EOF'
import os
import json
import logging
import sys
from typing import Dict, Any
import openai
from azure.storage.blob import BlobServiceClient
from azure.eventgrid import EventGridPublisherClient, EventGridEvent
from azure.core.credentials import AzureKeyCredential

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class AIAgent:
    def __init__(self):
        """Initialize the AI agent with required configuration."""
        self.openai_endpoint = os.environ.get('OPENAI_ENDPOINT')
        self.openai_key = os.environ.get('OPENAI_KEY')
        self.storage_connection = os.environ.get('STORAGE_CONNECTION')
        self.eventgrid_endpoint = os.environ.get('EVENTGRID_ENDPOINT')
        self.eventgrid_key = os.environ.get('EVENTGRID_KEY')
        
        # Task-specific environment variables
        self.task_id = os.environ.get('TASK_ID')
        self.task_prompt = os.environ.get('TASK_PROMPT')
        
        # Validate required environment variables
        required_vars = [
            'OPENAI_ENDPOINT', 'OPENAI_KEY', 'STORAGE_CONNECTION',
            'TASK_ID', 'TASK_PROMPT'
        ]
        
        for var in required_vars:
            if not os.environ.get(var):
                logger.error(f"Missing required environment variable: {var}")
                sys.exit(1)
        
        # Initialize OpenAI client
        openai.api_key = self.openai_key
        openai.api_base = self.openai_endpoint
        openai.api_type = 'azure'
        openai.api_version = '2023-05-15'
        
        logger.info(f"AI Agent initialized for task: {self.task_id}")
    
    def process_task(self) -> Dict[str, Any]:
        """Process the assigned task using OpenAI GPT-4."""
        try:
            logger.info(f"Processing task {self.task_id} with prompt: {self.task_prompt[:100]}...")
            
            # Call OpenAI GPT-4
            response = openai.ChatCompletion.create(
                engine="gpt-4",
                messages=[
                    {
                        "role": "system",
                        "content": "You are a helpful AI assistant. Provide clear, accurate, and detailed responses."
                    },
                    {
                        "role": "user",
                        "content": self.task_prompt
                    }
                ],
                temperature=0.7,
                max_tokens=1000
            )
            
            result = response.choices[0].message.content
            logger.info(f"Task {self.task_id} processed successfully")
            
            return {
                "task_id": self.task_id,
                "prompt": self.task_prompt,
                "result": result,
                "status": "completed",
                "model": "gpt-4",
                "usage": response.usage
            }
            
        except Exception as e:
            logger.error(f"Error processing task {self.task_id}: {str(e)}")
            return {
                "task_id": self.task_id,
                "prompt": self.task_prompt,
                "error": str(e),
                "status": "failed"
            }
    
    def store_result(self, result: Dict[str, Any]) -> None:
        """Store the processing result in Azure Blob Storage."""
        try:
            blob_service_client = BlobServiceClient.from_connection_string(
                self.storage_connection
            )
            
            blob_client = blob_service_client.get_blob_client(
                container="results",
                blob=f"{self.task_id}.json"
            )
            
            blob_client.upload_blob(
                json.dumps(result, indent=2),
                overwrite=True
            )
            
            logger.info(f"Result stored for task {self.task_id}")
            
        except Exception as e:
            logger.error(f"Error storing result for task {self.task_id}: {str(e)}")
            raise
    
    def publish_completion_event(self, result: Dict[str, Any]) -> None:
        """Publish task completion event to Event Grid."""
        try:
            if not self.eventgrid_endpoint or not self.eventgrid_key:
                logger.warning("Event Grid configuration not found, skipping event publication")
                return
            
            client = EventGridPublisherClient(
                self.eventgrid_endpoint,
                AzureKeyCredential(self.eventgrid_key)
            )
            
            event = EventGridEvent(
                subject=f"agent/task/{self.task_id}",
                event_type="Agent.TaskCompleted",
                data={
                    "taskId": self.task_id,
                    "status": result.get("status", "unknown"),
                    "hasError": "error" in result
                },
                data_version="1.0"
            )
            
            client.send(event)
            logger.info(f"Completion event published for task {self.task_id}")
            
        except Exception as e:
            logger.error(f"Error publishing completion event for task {self.task_id}: {str(e)}")
            # Don't raise here - event publication failure shouldn't fail the task
    
    def run(self) -> None:
        """Main execution method."""
        try:
            logger.info(f"Starting AI agent for task {self.task_id}")
            
            # Process the task
            result = self.process_task()
            
            # Store the result
            self.store_result(result)
            
            # Publish completion event
            self.publish_completion_event(result)
            
            if result.get("status") == "completed":
                logger.info(f"Task {self.task_id} completed successfully")
                sys.exit(0)
            else:
                logger.error(f"Task {self.task_id} failed")
                sys.exit(1)
                
        except Exception as e:
            logger.error(f"Fatal error in AI agent: {str(e)}")
            sys.exit(1)

if __name__ == "__main__":
    agent = AIAgent()
    agent.run()
EOF
    
    # Login to ACR
    log "Logging into Azure Container Registry"
    az acr login --name "${CONTAINER_REGISTRY}"
    
    # Build and push the image
    log "Building and pushing AI agent container image"
    docker build -t "${CONTAINER_REGISTRY}.azurecr.io/ai-agent:latest" .
    docker push "${CONTAINER_REGISTRY}.azurecr.io/ai-agent:latest"
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "${TEMP_DIR}"
    
    log "AI agent container image created and pushed successfully ✅"
}

create_function_app() {
    log "Creating Azure Function App: ${FUNCTION_APP_NAME}"
    
    # Create consumption plan
    if az functionapp plan show --name "${FUNCTION_APP_PLAN}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Function App plan ${FUNCTION_APP_PLAN} already exists, skipping creation"
    else
        az functionapp plan create \
            --name "${FUNCTION_APP_PLAN}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --consumption-plan-location "${LOCATION}" \
            --sku Y1 \
            --tags purpose=recipe environment=demo
        
        log "Function App plan created successfully ✅"
    fi
    
    # Create Function App
    if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Function App ${FUNCTION_APP_NAME} already exists, skipping creation"
    else
        az functionapp create \
            --name "${FUNCTION_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --plan "${FUNCTION_APP_PLAN}" \
            --runtime python \
            --runtime-version 3.11 \
            --functions-version 4 \
            --tags purpose=recipe environment=demo
        
        log "Function App created successfully ✅"
    fi
    
    # Configure Function App settings
    log "Configuring Function App settings"
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "EVENTGRID_ENDPOINT=${EVENTGRID_ENDPOINT}" \
        "EVENTGRID_KEY=${EVENTGRID_KEY}" \
        "STORAGE_CONNECTION=${STORAGE_CONNECTION}" \
        "OPENAI_ENDPOINT=${OPENAI_ENDPOINT}" \
        "OPENAI_KEY=${OPENAI_KEY}" \
        "CONTAINER_REGISTRY=${CONTAINER_REGISTRY}.azurecr.io" \
        "ACR_USERNAME=${ACR_USERNAME}" \
        "ACR_PASSWORD=${ACR_PASSWORD}" \
        "SUBSCRIPTION_ID=${SUBSCRIPTION_ID}" \
        "RESOURCE_GROUP=${RESOURCE_GROUP}"
    
    log "Function App settings configured successfully ✅"
}

deploy_function_code() {
    log "Deploying Function App code"
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Create function structure
    mkdir -p agent-api
    
    # Create function.json
    cat > agent-api/function.json << 'EOF'
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
    
    # Create function code
    cat > agent-api/__init__.py << 'EOF'
import logging
import json
import uuid
import os
import azure.functions as func
from azure.eventgrid import EventGridPublisherClient, EventGridEvent
from azure.core.credentials import AzureKeyCredential

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Processing AI agent request')
    
    try:
        # Parse request body
        req_body = req.get_json()
        
        if not req_body:
            return func.HttpResponse(
                json.dumps({"error": "Request body is required"}),
                status_code=400,
                mimetype="application/json"
            )
        
        task_prompt = req_body.get('prompt')
        
        if not task_prompt:
            return func.HttpResponse(
                json.dumps({"error": "Missing 'prompt' in request body"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Generate task ID
        task_id = str(uuid.uuid4())
        
        # Get Event Grid configuration
        eventgrid_endpoint = os.environ.get('EVENTGRID_ENDPOINT')
        eventgrid_key = os.environ.get('EVENTGRID_KEY')
        
        if not eventgrid_endpoint or not eventgrid_key:
            return func.HttpResponse(
                json.dumps({"error": "Event Grid configuration not found"}),
                status_code=500,
                mimetype="application/json"
            )
        
        # Publish event to Event Grid
        client = EventGridPublisherClient(
            eventgrid_endpoint,
            AzureKeyCredential(eventgrid_key)
        )
        
        event = EventGridEvent(
            subject="agent/task/new",
            event_type="Agent.TaskCreated",
            data={
                "taskId": task_id,
                "prompt": task_prompt,
                "timestamp": str(uuid.uuid1().time)
            },
            data_version="1.0"
        )
        
        client.send(event)
        
        logging.info(f'Task {task_id} created and event published')
        
        return func.HttpResponse(
            json.dumps({
                "taskId": task_id,
                "status": "accepted",
                "message": "Task submitted for processing"
            }),
            status_code=202,
            mimetype="application/json"
        )
        
    except Exception as e:
        logging.error(f'Error processing request: {str(e)}')
        return func.HttpResponse(
            json.dumps({"error": f"Internal server error: {str(e)}"}),
            status_code=500,
            mimetype="application/json"
        )
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
azure-functions
azure-eventgrid==4.15.0
azure-core==1.29.5
EOF
    
    # Create host.json
    cat > host.json << 'EOF'
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
    "version": "[3.*, 4.0.0)"
  },
  "functionTimeout": "00:05:00"
}
EOF
    
    # Create deployment package
    zip -r functionapp.zip .
    
    # Deploy function code
    az functionapp deployment source config-zip \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --src functionapp.zip
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "${TEMP_DIR}"
    
    log "Function App code deployed successfully ✅"
}

create_application_insights() {
    log "Creating Application Insights instance"
    
    INSIGHTS_NAME="insights-ai-agents-${RANDOM_SUFFIX}"
    
    if az monitor app-insights component show --app "${INSIGHTS_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Application Insights ${INSIGHTS_NAME} already exists, skipping creation"
    else
        az monitor app-insights component create \
            --app "${INSIGHTS_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --kind web \
            --tags purpose=recipe environment=demo
        
        log "Application Insights created successfully ✅"
    fi
    
    # Get instrumentation key
    APPINSIGHTS_KEY=$(az monitor app-insights component show \
        --app "${INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query instrumentationKey \
        --output tsv)
    
    # Update Function App with Application Insights
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "APPINSIGHTS_INSTRUMENTATIONKEY=${APPINSIGHTS_KEY}"
    
    log "Application Insights integration configured ✅"
}

# =============================================================================
# Main Deployment Flow
# =============================================================================

main() {
    log "Starting deployment process..."
    
    # Deploy infrastructure components
    deploy_resource_group
    deploy_storage_account
    deploy_container_registry
    deploy_openai_service
    deploy_eventgrid_topic
    
    # Create and deploy application components
    create_container_image
    create_function_app
    deploy_function_code
    create_application_insights
    
    # Output deployment summary
    log "==================================="
    log "Deployment completed successfully! ✅"
    log "==================================="
    
    info "Resource Group: ${RESOURCE_GROUP}"
    info "Storage Account: ${STORAGE_ACCOUNT}"
    info "Container Registry: ${CONTAINER_REGISTRY}"
    info "OpenAI Resource: ${OPENAI_RESOURCE}"
    info "Event Grid Topic: ${EVENTGRID_TOPIC}"
    info "Function App: ${FUNCTION_APP_NAME}"
    
    # Get Function App URL
    FUNCTION_URL=$(az functionapp function show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --function-name agent-api \
        --query invokeUrlTemplate \
        --output tsv 2>/dev/null || echo "Function URL not available yet - may need a few minutes")
    
    log "==================================="
    log "Usage Instructions:"
    log "==================================="
    info "Function App URL: ${FUNCTION_URL}"
    info ""
    info "To test the AI agent system, use:"
    info "curl -X POST '${FUNCTION_URL}' \\"
    info "  -H 'Content-Type: application/json' \\"
    info "  -d '{\"prompt\": \"Your AI prompt here\"}'"
    info ""
    info "To view logs:"
    info "az logs tail --ids $(az functionapp show --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP} --query id --output tsv)"
    
    log "==================================="
    log "Next Steps:"
    log "==================================="
    info "1. Test the API endpoint with a sample request"
    info "2. Monitor Azure Monitor for logs and metrics"
    info "3. Check Azure Storage for task results"
    info "4. Scale the solution by submitting multiple requests"
    info ""
    info "To clean up resources, run: ./destroy.sh"
}

# =============================================================================
# Script Execution
# =============================================================================

# Check for help flag
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy Azure Serverless AI Agents infrastructure"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP       Resource group name (default: rg-ai-agents-<random>)"
    echo "  LOCATION             Azure region (default: eastus)"
    echo "  STORAGE_ACCOUNT      Storage account name (default: staiagents<random>)"
    echo "  CONTAINER_REGISTRY   Container registry name (default: craiagents<random>)"
    echo "  OPENAI_RESOURCE      OpenAI resource name (default: oai-agents-<random>)"
    echo "  EVENTGRID_TOPIC      Event Grid topic name (default: egt-agents-<random>)"
    echo "  FUNCTION_APP_NAME    Function app name (default: func-agents-<random>)"
    echo ""
    echo "Examples:"
    echo "  ./deploy.sh"
    echo "  LOCATION=westus2 ./deploy.sh"
    echo "  RESOURCE_GROUP=my-ai-agents ./deploy.sh"
    exit 0
fi

# Run main deployment
main "$@"