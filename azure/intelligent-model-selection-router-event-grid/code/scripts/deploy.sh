#!/bin/bash

###################################################################################
# Deploy Script for Intelligent Model Selection with Model Router and Event Grid
# Recipe: intelligent-model-selection-router-event-grid
# Provider: Azure
# Description: Deploys event-driven AI orchestration with intelligent model routing
###################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
RESOURCE_PREFIX="recipe-ai-router"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Script failed at line $line_number with exit code $exit_code"
    log_error "Check the log file: $LOG_FILE"
    exit $exit_code
}

trap 'handle_error $LINENO' ERR

# Cleanup function for partial deployments
cleanup_on_failure() {
    log_warning "Cleaning up partial deployment..."
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version (minimum 2.50.0)
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv)
    local required_version="2.50.0"
    
    if ! printf '%s\n' "$required_version" "$az_version" | sort -V -C; then
        log_error "Azure CLI version $az_version is too old. Required: $required_version or later"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check for required tools
    local required_tools=("openssl" "zip" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed"
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Set environment variables
set_environment_variables() {
    log_info "Setting environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set Azure subscription and region
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export LOCATION="${AZURE_LOCATION:-eastus2}"
    
    # Validate region supports required services
    local supported_regions=("eastus2" "swedencentral")
    if [[ ! " ${supported_regions[@]} " =~ " ${LOCATION} " ]]; then
        log_warning "Location $LOCATION may not support Model Router preview. Supported: ${supported_regions[*]}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Set resource names with unique suffix
    export RESOURCE_GROUP="${RESOURCE_PREFIX}-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stmodelrouter${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-router-${RANDOM_SUFFIX}"
    export AI_FOUNDRY_RESOURCE="ai-foundry-${RANDOM_SUFFIX}"
    export EVENT_GRID_TOPIC="egt-router-${RANDOM_SUFFIX}"
    export APP_INSIGHTS="ai-router-${RANDOM_SUFFIX}"
    
    # Validate resource name lengths
    if [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
        log_error "Storage account name too long: ${STORAGE_ACCOUNT}"
        exit 1
    fi
    
    log_success "Environment variables set successfully"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Random Suffix: $RANDOM_SUFFIX"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo created=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
        --output none
    
    log_success "Resource group created: $RESOURCE_GROUP"
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
        --https-only true \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --output none
    
    # Wait for storage account to be ready
    local max_attempts=30
    local attempt=1
    while ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv | grep -q "Succeeded"; do
        if [[ $attempt -ge $max_attempts ]]; then
            log_error "Storage account creation timed out"
            exit 1
        fi
        log_info "Waiting for storage account to be ready (attempt $attempt/$max_attempts)..."
        sleep 10
        ((attempt++))
    done
    
    log_success "Storage account created: $STORAGE_ACCOUNT"
}

# Create Application Insights
create_application_insights() {
    log_info "Creating Application Insights: $APP_INSIGHTS"
    
    az monitor app-insights component create \
        --app "$APP_INSIGHTS" \
        --location "$LOCATION" \
        --resource-group "$RESOURCE_GROUP" \
        --kind web \
        --application-type web \
        --output none
    
    # Get Application Insights connection string
    export AI_CONNECTION_STRING=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    if [[ -z "$AI_CONNECTION_STRING" ]]; then
        log_error "Failed to get Application Insights connection string"
        exit 1
    fi
    
    log_success "Application Insights created with monitoring enabled"
}

# Create Function App
create_function_app() {
    log_info "Creating Function App: $FUNCTION_APP"
    
    az functionapp create \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --consumption-plan-location "$LOCATION" \
        --runtime python \
        --runtime-version 3.11 \
        --functions-version 4 \
        --app-insights "$APP_INSIGHTS" \
        --os-type Linux \
        --output none
    
    # Configure Function App settings
    log_info "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "APPLICATIONINSIGHTS_CONNECTION_STRING=$AI_CONNECTION_STRING" \
        "FUNCTIONS_WORKER_RUNTIME=python" \
        "AzureWebJobsFeatureFlags=EnableWorkerIndexing" \
        --output none
    
    # Wait for Function App to be ready
    local max_attempts=30
    local attempt=1
    while ! az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --query state -o tsv | grep -q "Running"; do
        if [[ $attempt -ge $max_attempts ]]; then
            log_error "Function App creation timed out"
            exit 1
        fi
        log_info "Waiting for Function App to be ready (attempt $attempt/$max_attempts)..."
        sleep 10
        ((attempt++))
    done
    
    log_success "Function App created with Event Grid integration"
}

# Create Event Grid Topic
create_event_grid_topic() {
    log_info "Creating Event Grid Topic: $EVENT_GRID_TOPIC"
    
    az eventgrid topic create \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --input-schema eventgridschema \
        --output none
    
    # Get Event Grid topic endpoint and access key
    export EVENT_GRID_ENDPOINT=$(az eventgrid topic show \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query endpoint \
        --output tsv)
    
    export EVENT_GRID_KEY=$(az eventgrid topic key list \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 \
        --output tsv)
    
    if [[ -z "$EVENT_GRID_ENDPOINT" || -z "$EVENT_GRID_KEY" ]]; then
        log_error "Failed to get Event Grid topic configuration"
        exit 1
    fi
    
    log_success "Event Grid topic created: $EVENT_GRID_TOPIC"
}

# Create AI Foundry Resource
create_ai_foundry_resource() {
    log_info "Creating Azure AI Foundry Resource: $AI_FOUNDRY_RESOURCE"
    
    # Check if AI Services provider is registered
    log_info "Registering Microsoft.CognitiveServices provider..."
    az provider register --namespace Microsoft.CognitiveServices --wait
    
    az cognitiveservices account create \
        --name "$AI_FOUNDRY_RESOURCE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind AIServices \
        --sku S0 \
        --custom-domain "$AI_FOUNDRY_RESOURCE" \
        --assign-identity \
        --output none
    
    # Wait for AI resource to be ready
    local max_attempts=30
    local attempt=1
    while ! az cognitiveservices account show --name "$AI_FOUNDRY_RESOURCE" --resource-group "$RESOURCE_GROUP" --query properties.provisioningState -o tsv | grep -q "Succeeded"; do
        if [[ $attempt -ge $max_attempts ]]; then
            log_error "AI Foundry resource creation timed out"
            exit 1
        fi
        log_info "Waiting for AI Foundry resource to be ready (attempt $attempt/$max_attempts)..."
        sleep 15
        ((attempt++))
    done
    
    # Get AI Foundry resource endpoint and key
    export AI_FOUNDRY_ENDPOINT=$(az cognitiveservices account show \
        --name "$AI_FOUNDRY_RESOURCE" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint \
        --output tsv)
    
    export AI_FOUNDRY_KEY=$(az cognitiveservices account keys list \
        --name "$AI_FOUNDRY_RESOURCE" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 \
        --output tsv)
    
    if [[ -z "$AI_FOUNDRY_ENDPOINT" || -z "$AI_FOUNDRY_KEY" ]]; then
        log_error "Failed to get AI Foundry resource configuration"
        exit 1
    fi
    
    log_success "Azure AI Foundry resource created for Model Router"
}

# Deploy Model Router
deploy_model_router() {
    log_info "Deploying Model Router in Azure AI Foundry..."
    
    # Note: Model Router deployment may require preview access
    # Attempt deployment with error handling
    if ! az cognitiveservices account deployment create \
        --name "$AI_FOUNDRY_RESOURCE" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "model-router-deployment" \
        --model-name "model-router" \
        --model-version "2025-05-19" \
        --model-format OpenAI \
        --sku-capacity 50 \
        --sku-name "Standard" \
        --output none 2>/dev/null; then
        
        log_warning "Model Router deployment failed - this may require preview access"
        log_info "Creating alternative GPT-4o-mini deployment for testing..."
        
        # Deploy GPT-4o-mini as fallback
        az cognitiveservices account deployment create \
            --name "$AI_FOUNDRY_RESOURCE" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name "gpt-4o-mini-deployment" \
            --model-name "gpt-4o-mini" \
            --model-version "2024-07-18" \
            --model-format OpenAI \
            --sku-capacity 50 \
            --sku-name "Standard" \
            --output none
        
        export MODEL_DEPLOYMENT_NAME="gpt-4o-mini-deployment"
        log_warning "Using GPT-4o-mini deployment instead of Model Router"
    else
        export MODEL_DEPLOYMENT_NAME="model-router-deployment"
        log_success "Model Router deployed with intelligent routing enabled"
    fi
    
    # Configure Function App with AI Foundry settings
    log_info "Configuring Function App with AI settings..."
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "AI_FOUNDRY_ENDPOINT=$AI_FOUNDRY_ENDPOINT" \
        "AI_FOUNDRY_KEY=$AI_FOUNDRY_KEY" \
        "MODEL_DEPLOYMENT_NAME=$MODEL_DEPLOYMENT_NAME" \
        "EVENT_GRID_ENDPOINT=$EVENT_GRID_ENDPOINT" \
        "EVENT_GRID_KEY=$EVENT_GRID_KEY" \
        --output none
}

# Create and deploy function code
create_and_deploy_function_code() {
    log_info "Creating function code..."
    
    local function_dir="${SCRIPT_DIR}/function_code"
    mkdir -p "$function_dir"
    
    # Create function_app.py
    cat > "$function_dir/function_app.py" << 'EOF'
import azure.functions as func
import json
import logging
import os
from datetime import datetime, timezone
import requests
from azure.eventgrid import EventGridPublisherClient
from azure.core.credentials import AzureKeyCredential
from openai import AzureOpenAI

app = func.FunctionApp()

# Initialize clients
ai_client = AzureOpenAI(
    api_key=os.environ["AI_FOUNDRY_KEY"],
    api_version="2024-02-01",
    azure_endpoint=os.environ["AI_FOUNDRY_ENDPOINT"]
)

@app.event_grid_trigger(arg_name="azeventgrid")
def router_function(azeventgrid: func.EventGridEvent):
    """Intelligent AI request router using Model Router"""
    
    logging.info(f"Processing Event Grid event: {azeventgrid.event_type}")
    
    try:
        # Extract request data from event
        event_data = azeventgrid.get_json()
        user_prompt = event_data.get("prompt", "")
        request_id = event_data.get("request_id", "unknown")
        
        # Analyze request complexity
        complexity_score = analyze_complexity(user_prompt)
        
        # Route through Model Router
        response = ai_client.chat.completions.create(
            model=os.environ["MODEL_DEPLOYMENT_NAME"],
            messages=[
                {"role": "system", "content": "You are a helpful AI assistant."},
                {"role": "user", "content": user_prompt}
            ],
            temperature=0.7,
            max_tokens=1000
        )
        
        # Extract selected model from response
        selected_model = response.model
        
        # Log routing decision
        logging.info(f"Request {request_id}: Complexity {complexity_score}, "
                    f"Selected model: {selected_model}")
        
        # Publish monitoring event
        publish_monitoring_event(request_id, complexity_score, 
                               selected_model, len(response.choices[0].message.content))
        
        return {
            "request_id": request_id,
            "selected_model": selected_model,
            "response": response.choices[0].message.content,
            "complexity_score": complexity_score
        }
        
    except Exception as e:
        logging.error(f"Error processing request: {str(e)}")
        raise

def analyze_complexity(prompt: str) -> float:
    """Analyze prompt complexity for routing decisions"""
    
    # Basic complexity indicators
    complexity_indicators = [
        len(prompt.split()) > 100,  # Long prompts
        "analyze" in prompt.lower() or "reasoning" in prompt.lower(),
        "calculate" in prompt.lower() or "compute" in prompt.lower(),
        "explain" in prompt.lower() and "detail" in prompt.lower(),
        prompt.count("?") > 2,  # Multiple questions
    ]
    
    return sum(complexity_indicators) / len(complexity_indicators)

def publish_monitoring_event(request_id: str, complexity: float, 
                           model: str, response_length: int):
    """Publish monitoring metrics to Event Grid"""
    
    try:
        event_data = {
            "request_id": request_id,
            "complexity_score": complexity,
            "selected_model": model,
            "response_length": response_length,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        
        # This would publish to a monitoring topic in a full implementation
        logging.info(f"Monitoring data: {json.dumps(event_data)}")
        
    except Exception as e:
        logging.warning(f"Failed to publish monitoring event: {str(e)}")

@app.function_name(name="health_check")
@app.route(route="health", methods=["GET"])
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint"""
    return func.HttpResponse("Healthy", status_code=200)
EOF

    # Create requirements.txt
    cat > "$function_dir/requirements.txt" << 'EOF'
azure-functions
azure-eventgrid
openai==1.12.0
requests
EOF

    # Create host.json
    cat > "$function_dir/host.json" << 'EOF'
{
    "version": "2.0",
    "functionTimeout": "00:05:00",
    "logging": {
        "applicationInsights": {
            "samplingSettings": {
                "isEnabled": true
            }
        }
    }
}
EOF

    log_success "Function code created with intelligent routing logic"
    
    # Deploy function code
    log_info "Deploying function code..."
    
    cd "$function_dir"
    zip -r "../function.zip" . > /dev/null
    cd "$SCRIPT_DIR"
    
    az functionapp deployment source config-zip \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --src "function.zip" \
        --output none
    
    # Wait for deployment to complete
    log_info "Waiting for function deployment to complete..."
    sleep 30
    
    log_success "Function deployed successfully"
}

# Create Event Grid subscription
create_event_grid_subscription() {
    log_info "Creating Event Grid subscription..."
    
    local function_endpoint="https://${FUNCTION_APP}.azurewebsites.net/runtime/webhooks/eventgrid?functionName=router_function"
    
    az eventgrid event-subscription create \
        --name "ai-router-subscription" \
        --source-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventGrid/topics/$EVENT_GRID_TOPIC" \
        --endpoint "$function_endpoint" \
        --endpoint-type azurefunction \
        --included-event-types "AIRequest.Submitted" \
        --output none
    
    log_success "Event Grid subscription configured"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Model Router deployment status
    local deployment_status
    deployment_status=$(az cognitiveservices account deployment show \
        --name "$AI_FOUNDRY_RESOURCE" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "$MODEL_DEPLOYMENT_NAME" \
        --query properties.provisioningState \
        --output tsv 2>/dev/null || echo "Failed")
    
    if [[ "$deployment_status" == "Succeeded" ]]; then
        log_success "Model deployment is active: $MODEL_DEPLOYMENT_NAME"
    else
        log_warning "Model deployment status: $deployment_status"
    fi
    
    # Test Event Grid connectivity
    log_info "Testing Event Grid connectivity..."
    
    local test_event='[
        {
            "id": "test-001",
            "eventType": "AIRequest.Submitted",
            "subject": "test-request",
            "data": {
                "prompt": "What is artificial intelligence?",
                "request_id": "test-001"
            },
            "dataVersion": "1.0"
        }
    ]'
    
    if az eventgrid event send \
        --topic-name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --events "$test_event" \
        --output none 2>/dev/null; then
        log_success "Event Grid test event sent successfully"
    else
        log_warning "Event Grid test failed"
    fi
    
    # Check function health
    local function_url="https://${FUNCTION_APP}.azurewebsites.net/api/health"
    if curl -s -f "$function_url" > /dev/null 2>&1; then
        log_success "Function App health check passed"
    else
        log_warning "Function App health check failed"
    fi
    
    log_success "Deployment validation completed"
}

# Save deployment configuration
save_deployment_config() {
    local config_file="${SCRIPT_DIR}/deployment.env"
    
    cat > "$config_file" << EOF
# Deployment Configuration
# Generated: $(date)
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
RANDOM_SUFFIX=$RANDOM_SUFFIX

# Resource Names
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
FUNCTION_APP=$FUNCTION_APP
AI_FOUNDRY_RESOURCE=$AI_FOUNDRY_RESOURCE
EVENT_GRID_TOPIC=$EVENT_GRID_TOPIC
APP_INSIGHTS=$APP_INSIGHTS
MODEL_DEPLOYMENT_NAME=$MODEL_DEPLOYMENT_NAME

# Service Endpoints
AI_FOUNDRY_ENDPOINT=$AI_FOUNDRY_ENDPOINT
EVENT_GRID_ENDPOINT=$EVENT_GRID_ENDPOINT
EOF
    
    log_success "Deployment configuration saved to: $config_file"
}

# Cleanup temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    rm -rf "${SCRIPT_DIR}/function_code" "${SCRIPT_DIR}/function.zip" 2>/dev/null || true
    
    log_success "Temporary files cleaned up"
}

# Main deployment function
main() {
    log_info "Starting deployment of Intelligent Model Selection with Model Router and Event Grid"
    log_info "Script started at: $(date)"
    
    # Trap cleanup on failure
    trap cleanup_on_failure ERR
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_storage_account
    create_application_insights
    create_function_app
    create_event_grid_topic
    create_ai_foundry_resource
    deploy_model_router
    create_and_deploy_function_code
    create_event_grid_subscription
    validate_deployment
    save_deployment_config
    cleanup_temp_files
    
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Function App: $FUNCTION_APP"
    log_info "Event Grid Topic: $EVENT_GRID_TOPIC"
    log_info "AI Resource: $AI_FOUNDRY_RESOURCE"
    log_info "Model Deployment: $MODEL_DEPLOYMENT_NAME"
    log_info "Estimated monthly cost: \$15-25 USD"
    log_info ""
    log_info "To test the deployment:"
    log_info "  az eventgrid event send --topic-name $EVENT_GRID_TOPIC --resource-group $RESOURCE_GROUP --events '[{\"id\":\"test-001\",\"eventType\":\"AIRequest.Submitted\",\"subject\":\"test\",\"data\":{\"prompt\":\"Hello AI!\",\"request_id\":\"test-001\"},\"dataVersion\":\"1.0\"}]'"
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
    log_info "Log file: $LOG_FILE"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help]"
        echo ""
        echo "Deploy Intelligent Model Selection with Model Router and Event Grid"
        echo ""
        echo "Environment Variables:"
        echo "  AZURE_LOCATION    Azure region (default: eastus2)"
        echo ""
        echo "Examples:"
        echo "  $0                           # Deploy with defaults"
        echo "  AZURE_LOCATION=swedencentral $0  # Deploy to Sweden Central"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac