#!/bin/bash

# =============================================================================
# Azure Real-time AI Chat with WebRTC and Model Router - Deployment Script
# =============================================================================
# This script deploys the complete infrastructure for a real-time AI chat
# application with intelligent model routing between GPT-4o-mini and GPT-4o
# models based on conversation complexity.
#
# Version: 1.0
# Last Updated: 2025-07-12
# =============================================================================

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly ERROR_LOG="${SCRIPT_DIR}/deployment_error.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables for cleanup tracking
RESOURCES_CREATED=()
CLEANUP_ON_ERROR=${CLEANUP_ON_ERROR:-true}

# =============================================================================
# Logging and Output Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)
            echo -e "${GREEN}[INFO]${NC} ${message}"
            echo "[${timestamp}] [INFO] ${message}" >> "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} ${message}"
            echo "[${timestamp}] [WARN] ${message}" >> "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} ${message}" >&2
            echo "[${timestamp}] [ERROR] ${message}" >> "$ERROR_LOG"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} ${message}"
            echo "[${timestamp}] [SUCCESS] ${message}" >> "$LOG_FILE"
            ;;
        *)
            echo -e "${BLUE}[DEBUG]${NC} ${message}"
            echo "[${timestamp}] [DEBUG] ${message}" >> "$LOG_FILE"
            ;;
    esac
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Real-time AI Chat with WebRTC and Model Router

OPTIONS:
    -r, --resource-group    Resource group name (default: auto-generated)
    -l, --location         Azure region (default: eastus2)
    -s, --suffix           Resource name suffix (default: auto-generated)
    -h, --help             Show this help message
    --dry-run              Show what would be deployed without executing
    --no-cleanup           Don't cleanup resources on error
    --skip-prereqs         Skip prerequisite checks

EXAMPLES:
    $0                                    # Deploy with default settings
    $0 -r my-rg -l westus2              # Deploy to specific resource group and region
    $0 --dry-run                         # Preview deployment without executing
    $0 --no-cleanup                      # Deploy without error cleanup

EOF
}

# =============================================================================
# Prerequisites and Validation Functions
# =============================================================================

check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log ERROR "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log INFO "Azure CLI version: ${az_version}"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log ERROR "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        log WARN "jq is not installed. Some output formatting may be limited."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log ERROR "openssl is required for generating random suffixes. Please install it."
        exit 1
    fi
    
    # Verify subscription access
    local subscription_id=$(az account show --query id --output tsv 2>/dev/null)
    local subscription_name=$(az account show --query name --output tsv 2>/dev/null)
    log INFO "Using subscription: ${subscription_name} (${subscription_id})"
    
    # Check required resource providers
    check_resource_providers
    
    log SUCCESS "Prerequisites check completed"
}

check_resource_providers() {
    log INFO "Checking required Azure resource providers..."
    
    local providers=(
        "Microsoft.CognitiveServices"
        "Microsoft.SignalRService"
        "Microsoft.Web"
        "Microsoft.Storage"
    )
    
    for provider in "${providers[@]}"; do
        local state=$(az provider show --namespace "$provider" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$state" != "Registered" ]]; then
            log WARN "Resource provider ${provider} is not registered. Registering..."
            az provider register --namespace "$provider" --wait
            log SUCCESS "Resource provider ${provider} registered"
        else
            log INFO "Resource provider ${provider} is already registered"
        fi
    done
}

validate_location() {
    local location="$1"
    
    log INFO "Validating location: ${location}"
    
    # Check if location exists and supports required services
    if ! az account list-locations --query "[?name=='${location}']" -o tsv | grep -q "$location"; then
        log ERROR "Location '${location}' is not valid or not available in your subscription"
        log INFO "Available locations:"
        az account list-locations --query "[].name" -o tsv | sort
        exit 1
    fi
    
    # Check OpenAI availability in region
    local openai_locations=("eastus2" "swedencentral" "westus" "eastus")
    if [[ ! " ${openai_locations[@]} " =~ ' '${location}' ' ]]; then
        log WARN "Azure OpenAI service may not be fully available in ${location}"
        log WARN "Recommended regions for OpenAI Realtime API: ${openai_locations[*]}"
        
        read -p "Continue with ${location}? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    log SUCCESS "Location ${location} validated"
}

# =============================================================================
# Resource Creation Functions
# =============================================================================

create_resource_group() {
    local rg_name="$1"
    local location="$2"
    
    log INFO "Creating resource group: ${rg_name}"
    
    if az group show --name "$rg_name" &> /dev/null; then
        log WARN "Resource group ${rg_name} already exists"
        return 0
    fi
    
    az group create \
        --name "$rg_name" \
        --location "$location" \
        --tags purpose="realtime-ai-chat" environment="demo" deployment-script="azure-realtime-chat" \
        --output none
    
    RESOURCES_CREATED+=("RESOURCE_GROUP:${rg_name}")
    log SUCCESS "Resource group created: ${rg_name}"
}

create_openai_service() {
    local service_name="$1"
    local rg_name="$2"
    local location="$3"
    
    log INFO "Creating Azure OpenAI service: ${service_name}"
    
    # Create OpenAI service
    az cognitiveservices account create \
        --name "$service_name" \
        --resource-group "$rg_name" \
        --location "$location" \
        --kind OpenAI \
        --sku S0 \
        --custom-domain "$service_name" \
        --output none
    
    RESOURCES_CREATED+=("OPENAI:${service_name}")
    
    # Wait for service to be ready
    log INFO "Waiting for OpenAI service to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local state=$(az cognitiveservices account show \
            --name "$service_name" \
            --resource-group "$rg_name" \
            --query provisioningState -o tsv 2>/dev/null || echo "Unknown")
        
        if [[ "$state" == "Succeeded" ]]; then
            break
        fi
        
        log INFO "Attempt ${attempt}/${max_attempts}: Service state is ${state}, waiting..."
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log ERROR "OpenAI service failed to provision within expected time"
        exit 1
    fi
    
    # Get endpoint and key
    OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "$service_name" \
        --resource-group "$rg_name" \
        --query properties.endpoint --output tsv)
    
    OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "$service_name" \
        --resource-group "$rg_name" \
        --query key1 --output tsv)
    
    log SUCCESS "Azure OpenAI service created: ${service_name}"
    log INFO "Endpoint: ${OPENAI_ENDPOINT}"
}

deploy_realtime_models() {
    local service_name="$1"
    local rg_name="$2"
    
    log INFO "Deploying GPT-4o realtime models..."
    
    # Deploy GPT-4o-mini-realtime model
    log INFO "Deploying GPT-4o-mini-realtime model..."
    az cognitiveservices account deployment create \
        --name "$service_name" \
        --resource-group "$rg_name" \
        --deployment-name "gpt-4o-mini-realtime" \
        --model-name "gpt-4o-mini-realtime-preview" \
        --model-version "2024-12-17" \
        --model-format "OpenAI" \
        --sku-capacity 10 \
        --sku-name "GlobalStandard" \
        --output none
    
    # Deploy GPT-4o-realtime model
    log INFO "Deploying GPT-4o-realtime model..."
    az cognitiveservices account deployment create \
        --name "$service_name" \
        --resource-group "$rg_name" \
        --deployment-name "gpt-4o-realtime" \
        --model-name "gpt-4o-realtime-preview" \
        --model-version "2024-12-17" \
        --model-format "OpenAI" \
        --sku-capacity 10 \
        --sku-name "GlobalStandard" \
        --output none
    
    # Wait for deployments to complete
    log INFO "Waiting for model deployments to complete..."
    local models=("gpt-4o-mini-realtime" "gpt-4o-realtime")
    
    for model in "${models[@]}"; do
        local max_attempts=20
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            local state=$(az cognitiveservices account deployment show \
                --name "$service_name" \
                --resource-group "$rg_name" \
                --deployment-name "$model" \
                --query properties.provisioningState -o tsv 2>/dev/null || echo "Unknown")
            
            if [[ "$state" == "Succeeded" ]]; then
                log SUCCESS "Model ${model} deployed successfully"
                break
            fi
            
            log INFO "Attempt ${attempt}/${max_attempts}: Model ${model} state is ${state}, waiting..."
            sleep 15
            ((attempt++))
        done
        
        if [ $attempt -gt $max_attempts ]; then
            log ERROR "Model ${model} failed to deploy within expected time"
            exit 1
        fi
    done
    
    log SUCCESS "Realtime models deployed successfully"
}

create_signalr_service() {
    local service_name="$1"
    local rg_name="$2"
    local location="$3"
    
    log INFO "Creating Azure SignalR service: ${service_name}"
    
    az signalr create \
        --name "$service_name" \
        --resource-group "$rg_name" \
        --location "$location" \
        --sku Standard_S1 \
        --service-mode Serverless \
        --enable-message-logs true \
        --output none
    
    RESOURCES_CREATED+=("SIGNALR:${service_name}")
    
    # Wait for service to be ready
    log INFO "Waiting for SignalR service to be ready..."
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local state=$(az signalr show \
            --name "$service_name" \
            --resource-group "$rg_name" \
            --query provisioningState -o tsv 2>/dev/null || echo "Unknown")
        
        if [[ "$state" == "Succeeded" ]]; then
            break
        fi
        
        log INFO "Attempt ${attempt}/${max_attempts}: SignalR state is ${state}, waiting..."
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log ERROR "SignalR service failed to provision within expected time"
        exit 1
    fi
    
    # Get connection string
    SIGNALR_CONNECTION_STRING=$(az signalr key list \
        --name "$service_name" \
        --resource-group "$rg_name" \
        --query primaryConnectionString --output tsv)
    
    log SUCCESS "SignalR service created: ${service_name}"
}

create_storage_account() {
    local storage_name="$1"
    local rg_name="$2"
    local location="$3"
    
    log INFO "Creating storage account: ${storage_name}"
    
    az storage account create \
        --name "$storage_name" \
        --resource-group "$rg_name" \
        --location "$location" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --output none
    
    RESOURCES_CREATED+=("STORAGE:${storage_name}")
    
    # Get connection string
    STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "$storage_name" \
        --resource-group "$rg_name" \
        --query connectionString --output tsv)
    
    log SUCCESS "Storage account created: ${storage_name}"
}

create_function_app() {
    local function_name="$1"
    local rg_name="$2"
    local location="$3"
    local storage_name="$4"
    
    log INFO "Creating Azure Function App: ${function_name}"
    
    # Create Function App
    az functionapp create \
        --name "$function_name" \
        --resource-group "$rg_name" \
        --storage-account "$storage_name" \
        --consumption-plan-location "$location" \
        --runtime node \
        --runtime-version 18 \
        --functions-version 4 \
        --output none
    
    RESOURCES_CREATED+=("FUNCTION:${function_name}")
    
    # Configure application settings
    log INFO "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "$function_name" \
        --resource-group "$rg_name" \
        --settings \
        "AzureSignalRConnectionString=${SIGNALR_CONNECTION_STRING}" \
        "AZURE_OPENAI_ENDPOINT=${OPENAI_ENDPOINT}" \
        "AZURE_OPENAI_KEY=${OPENAI_KEY}" \
        "OPENAI_API_VERSION=2025-04-01-preview" \
        --output none
    
    log SUCCESS "Function App created and configured: ${function_name}"
}

deploy_function_code() {
    local function_name="$1"
    local rg_name="$2"
    
    log INFO "Preparing Function App code..."
    
    # Create temporary directory for function code
    local temp_dir=$(mktemp -d)
    local functions_dir="${temp_dir}/chat-router-functions"
    
    # Create project structure
    mkdir -p "${functions_dir}/ModelRouter"
    mkdir -p "${functions_dir}/SignalRInfo"
    mkdir -p "${functions_dir}/SignalRMessages"
    
    # Create package.json
    cat > "${functions_dir}/package.json" << 'EOF'
{
  "name": "chat-router-functions",
  "version": "1.0.0",
  "scripts": {
    "start": "func start"
  },
  "dependencies": {
    "@azure/functions": "^4.0.0",
    "@azure/signalr": "^1.0.0-beta.4",
    "axios": "^1.6.0"
  }
}
EOF
    
    # Create host.json
    cat > "${functions_dir}/host.json" << 'EOF'
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[3.*, 4.0.0)"
  }
}
EOF
    
    # Create ModelRouter function
    cat > "${functions_dir}/ModelRouter/index.js" << 'EOF'
const { app } = require('@azure/functions');
const axios = require('axios');

app.http('ModelRouter', {
    methods: ['POST'],
    authLevel: 'function',
    handler: async (request, context) => {
        try {
            const { message, userId, sessionId } = await request.json();
            
            // Analyze message complexity for intelligent routing
            const complexity = analyzeComplexity(message);
            const selectedModel = complexity > 0.6 ? 
                'gpt-4o-realtime' : 'gpt-4o-mini-realtime';
            
            context.log(`Routing to ${selectedModel} (complexity: ${complexity})`);
            
            // Get ephemeral token for WebRTC connection
            const sessionToken = await getEphemeralToken(selectedModel);
            
            // Determine WebRTC endpoint based on deployment region
            const webrtcEndpoint = process.env.AZURE_OPENAI_ENDPOINT.includes('eastus2') ? 
                'https://eastus2.realtimeapi-preview.ai.azure.com/v1/realtimertc' : 
                'https://swedencentral.realtimeapi-preview.ai.azure.com/v1/realtimertc';
            
            return {
                status: 200,
                jsonBody: {
                    model: selectedModel,
                    sessionToken: sessionToken,
                    webrtcEndpoint: webrtcEndpoint,
                    complexity: complexity,
                    cost_optimization: selectedModel === 'gpt-4o-mini-realtime' ? 
                        'Using cost-effective model' : 'Using premium model for complex query'
                }
            };
        } catch (error) {
            context.log.error('Router error:', error);
            return {
                status: 500,
                jsonBody: { error: 'Model routing failed' }
            };
        }
    }
});

function analyzeComplexity(message) {
    const complexIndicators = [
        /technical|programming|code|algorithm|architecture/i,
        /explain.*how.*works|analyze|compare|evaluate/i,
        /\b(why|what|how|when|where)\b.*\b(should|would|could|might)\b/i,
        /multiple.*steps|process|procedure|methodology/i
    ];
    
    const simpleIndicators = [
        /^(hi|hello|hey|thanks|yes|no|ok)\b/i,
        /\b(weather|time|date|simple|quick)\b/i,
        /^.{1,20}$/  // Very short messages
    ];
    
    let complexityScore = 0.3; // Base complexity
    
    // Increase complexity for technical indicators
    complexIndicators.forEach(pattern => {
        if (pattern.test(message)) complexityScore += 0.2;
    });
    
    // Decrease complexity for simple indicators
    simpleIndicators.forEach(pattern => {
        if (pattern.test(message)) complexityScore -= 0.2;
    });
    
    // Length-based complexity adjustment
    if (message.length > 100) complexityScore += 0.1;
    if (message.split(' ').length > 20) complexityScore += 0.1;
    
    return Math.max(0, Math.min(1, complexityScore));
}

async function getEphemeralToken(model) {
    const sessionUrl = `${process.env.AZURE_OPENAI_ENDPOINT}/openai/realtimeapi/sessions?api-version=${process.env.OPENAI_API_VERSION}`;
    
    const response = await axios.post(sessionUrl, {
        model: model,
        voice: 'alloy',
        instructions: 'You are a helpful AI assistant. Respond naturally and concisely.'
    }, {
        headers: {
            'api-key': process.env.AZURE_OPENAI_KEY,
            'Content-Type': 'application/json'
        }
    });
    
    return response.data.token;
}
EOF
    
    # Create SignalRInfo function
    cat > "${functions_dir}/SignalRInfo/index.js" << 'EOF'
const { app, input } = require('@azure/functions');

app.http('SignalRInfo', {
    methods: ['POST'],
    authLevel: 'anonymous',
    extraInputs: [input.signalRConnectionInfo({
        hubName: 'ChatHub'
    })],
    handler: async (request, context) => {
        const connectionInfo = context.extraInputs.get('connectionInfo');
        
        return {
            status: 200,
            jsonBody: connectionInfo
        };
    }
});
EOF
    
    # Create SignalRMessages function
    cat > "${functions_dir}/SignalRMessages/index.js" << 'EOF'
const { app, output } = require('@azure/functions');

app.http('SignalRMessages', {
    methods: ['POST'],
    authLevel: 'function',
    extraOutputs: [output.signalR({
        hubName: 'ChatHub'
    })],
    handler: async (request, context) => {
        const { userId, message, model, timestamp } = await request.json();
        
        const signalRMessage = {
            target: 'messageReceived',
            arguments: [{
                userId,
                message,
                model,
                timestamp,
                type: 'ai-response'
            }]
        };
        
        context.extraOutputs.set('signalRMessages', signalRMessage);
        
        return {
            status: 200,
            jsonBody: { status: 'Message broadcasted' }
        };
    }
});
EOF
    
    # Create deployment package
    log INFO "Creating deployment package..."
    cd "$functions_dir"
    
    # Install dependencies
    if command -v npm &> /dev/null; then
        npm install --production --silent
    else
        log WARN "npm not found, skipping dependency installation"
    fi
    
    # Create zip package
    zip -r "../function-deployment.zip" . -x "node_modules/.bin/*" > /dev/null
    
    # Deploy to Azure
    log INFO "Deploying Function App code..."
    az functionapp deployment source config-zip \
        --name "$function_name" \
        --resource-group "$rg_name" \
        --src "${temp_dir}/function-deployment.zip" \
        --output none
    
    # Wait for deployment
    sleep 30
    
    # Cleanup temp directory
    rm -rf "$temp_dir"
    
    log SUCCESS "Function App code deployed successfully"
}

# =============================================================================
# Error Handling and Cleanup Functions
# =============================================================================

cleanup_on_error() {
    if [[ "$CLEANUP_ON_ERROR" == "true" ]]; then
        log WARN "Deployment failed. Cleaning up created resources..."
        cleanup_resources
    else
        log WARN "Deployment failed. Resources left for manual inspection."
        log INFO "Use the destroy.sh script to clean up resources later."
    fi
}

cleanup_resources() {
    log INFO "Starting resource cleanup..."
    
    # Cleanup in reverse order of creation
    for ((i=${#RESOURCES_CREATED[@]}-1; i>=0; i--)); do
        local resource="${RESOURCES_CREATED[i]}"
        local type="${resource%%:*}"
        local name="${resource#*:}"
        
        case "$type" in
            FUNCTION)
                log INFO "Deleting Function App: ${name}"
                az functionapp delete --name "$name" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null || true
                ;;
            STORAGE)
                log INFO "Deleting Storage Account: ${name}"
                az storage account delete --name "$name" --resource-group "$RESOURCE_GROUP" --yes --output none 2>/dev/null || true
                ;;
            SIGNALR)
                log INFO "Deleting SignalR Service: ${name}"
                az signalr delete --name "$name" --resource-group "$RESOURCE_GROUP" --yes --output none 2>/dev/null || true
                ;;
            OPENAI)
                log INFO "Deleting OpenAI Service: ${name}"
                az cognitiveservices account delete --name "$name" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null || true
                ;;
            RESOURCE_GROUP)
                log INFO "Deleting Resource Group: ${name}"
                az group delete --name "$name" --yes --no-wait --output none 2>/dev/null || true
                ;;
        esac
    done
    
    log SUCCESS "Resource cleanup completed"
}

# =============================================================================
# Main Deployment Logic
# =============================================================================

deploy_infrastructure() {
    local rg_name="$1"
    local location="$2"
    local suffix="$3"
    
    # Generate resource names
    local openai_service="openai-${suffix}"
    local signalr_service="signalr-${suffix}"
    local function_app="func-chat-router-${suffix}"
    local storage_account="stchatrouter${suffix}"
    
    log INFO "Starting deployment with configuration:"
    log INFO "  Resource Group: ${rg_name}"
    log INFO "  Location: ${location}"
    log INFO "  Suffix: ${suffix}"
    log INFO "  OpenAI Service: ${openai_service}"
    log INFO "  SignalR Service: ${signalr_service}"
    log INFO "  Function App: ${function_app}"
    log INFO "  Storage Account: ${storage_account}"
    
    # Create resources in order
    create_resource_group "$rg_name" "$location"
    create_openai_service "$openai_service" "$rg_name" "$location"
    deploy_realtime_models "$openai_service" "$rg_name"
    create_signalr_service "$signalr_service" "$rg_name" "$location"
    create_storage_account "$storage_account" "$rg_name" "$location"
    create_function_app "$function_app" "$rg_name" "$location" "$storage_account"
    deploy_function_code "$function_app" "$rg_name"
    
    # Output deployment summary
    log SUCCESS "Deployment completed successfully!"
    log INFO ""
    log INFO "=== DEPLOYMENT SUMMARY ==="
    log INFO "Resource Group: ${rg_name}"
    log INFO "OpenAI Service: ${openai_service}"
    log INFO "OpenAI Endpoint: ${OPENAI_ENDPOINT}"
    log INFO "SignalR Service: ${signalr_service}"
    log INFO "Function App: ${function_app}"
    log INFO "Function URL: https://${function_app}.azurewebsites.net"
    log INFO "Storage Account: ${storage_account}"
    log INFO ""
    log INFO "=== NEXT STEPS ==="
    log INFO "1. Test the model router endpoint:"
    log INFO "   curl -X POST \"https://${function_app}.azurewebsites.net/api/ModelRouter\" \\"
    log INFO "        -H \"Content-Type: application/json\" \\"
    log INFO "        -d '{\"message\":\"Hello world\",\"userId\":\"test\",\"sessionId\":\"test\"}'"
    log INFO ""
    log INFO "2. Integrate with your client application using the endpoints above"
    log INFO ""
    log INFO "3. Monitor costs and usage in the Azure portal"
    log INFO ""
    log INFO "Use the destroy.sh script to clean up resources when finished."
    
    # Save deployment info for cleanup script
    cat > "${SCRIPT_DIR}/deployment_info.env" << EOF
RESOURCE_GROUP="${rg_name}"
LOCATION="${location}"
SUFFIX="${suffix}"
OPENAI_SERVICE="${openai_service}"
SIGNALR_SERVICE="${signalr_service}"
FUNCTION_APP="${function_app}"
STORAGE_ACCOUNT="${storage_account}"
DEPLOYMENT_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
EOF
    
    log SUCCESS "Deployment information saved to deployment_info.env"
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    # Set default values
    local resource_group=""
    local location="eastus2"
    local suffix=""
    local dry_run=false
    local skip_prereqs=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--resource-group)
                resource_group="$2"
                shift 2
                ;;
            -l|--location)
                location="$2"
                shift 2
                ;;
            -s|--suffix)
                suffix="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --no-cleanup)
                CLEANUP_ON_ERROR=false
                shift
                ;;
            --skip-prereqs)
                skip_prereqs=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log ERROR "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "=== Deployment started at $(date) ===" > "$LOG_FILE"
    echo "=== Error log started at $(date) ===" > "$ERROR_LOG"
    
    # Set error trap
    trap cleanup_on_error ERR
    
    log INFO "Azure Real-time AI Chat with WebRTC Deployment Script"
    log INFO "Script version: 1.0"
    log INFO ""
    
    # Generate default values if not provided
    if [[ -z "$suffix" ]]; then
        suffix=$(openssl rand -hex 3)
        log INFO "Generated suffix: ${suffix}"
    fi
    
    if [[ -z "$resource_group" ]]; then
        resource_group="rg-realtime-chat-${suffix}"
        log INFO "Generated resource group: ${resource_group}"
    fi
    
    # Validate inputs
    if [[ ! "$skip_prereqs" == "true" ]]; then
        check_prerequisites
    fi
    
    validate_location "$location"
    
    # Show dry run information
    if [[ "$dry_run" == "true" ]]; then
        log INFO "=== DRY RUN MODE ==="
        log INFO "Would deploy the following resources:"
        log INFO "  Resource Group: ${resource_group}"
        log INFO "  Location: ${location}"
        log INFO "  OpenAI Service: openai-${suffix}"
        log INFO "  SignalR Service: signalr-${suffix}"
        log INFO "  Function App: func-chat-router-${suffix}"
        log INFO "  Storage Account: stchatrouter${suffix}"
        log INFO ""
        log INFO "Run without --dry-run to execute the deployment"
        exit 0
    fi
    
    # Confirm deployment
    log WARN "This will create Azure resources that may incur charges."
    log INFO "Estimated monthly cost: $15-25 for testing workloads"
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log INFO "Deployment cancelled by user"
        exit 0
    fi
    
    # Start deployment
    export RESOURCE_GROUP="$resource_group"
    deploy_infrastructure "$resource_group" "$location" "$suffix"
}

# Run main function with all arguments
main "$@"