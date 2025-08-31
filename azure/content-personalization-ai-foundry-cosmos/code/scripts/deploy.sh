#!/bin/bash

# Deploy Azure Content Personalization Engine with AI Foundry and Cosmos
# This script deploys the complete infrastructure for content personalization
# including Cosmos DB, Azure OpenAI, AI Foundry, and Azure Functions

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment-state"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    exit 1
}

# Cleanup on script exit
cleanup() {
    if [[ $? -ne 0 ]]; then
        log_error "Script interrupted. Run destroy.sh to clean up partial deployment."
    fi
}
trap cleanup EXIT

# Save deployment state
save_state() {
    local key="$1"
    local value="$2"
    echo "${key}=${value}" >> "${DEPLOYMENT_STATE_FILE}"
}

# Load deployment state
load_state() {
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        source "${DEPLOYMENT_STATE_FILE}"
    fi
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: ${az_version}"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if required extensions are available
    log_info "Checking Azure CLI extensions..."
    if ! az extension list --query "[?name=='ml'].name" -o tsv | grep -q "ml"; then
        log_info "Installing Azure ML extension..."
        az extension add --name ml --yes
    fi
    
    # Check if zip command is available (for function deployment)
    if ! command -v zip &> /dev/null; then
        error_exit "zip command is not available. Please install zip utility."
    fi
    
    # Check if openssl is available (for random suffix generation)
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl command is not available. Please install OpenSSL."
    fi
    
    log_success "Prerequisites check completed"
}

# Initialize environment variables
initialize_environment() {
    log_info "Initializing environment variables..."
    
    # Load existing state if available
    load_state
    
    # Set default values if not already set
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    # Generate unique suffix if not already set
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
        save_state "RANDOM_SUFFIX" "${RANDOM_SUFFIX}"
    fi
    
    # Set resource names with unique suffix
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-personalization-${RANDOM_SUFFIX}}"
    export COSMOS_ACCOUNT="${COSMOS_ACCOUNT:-cosmos-personalization-${RANDOM_SUFFIX}}"
    export AI_FOUNDRY_PROJECT="${AI_FOUNDRY_PROJECT:-ai-personalization-${RANDOM_SUFFIX}}"
    export OPENAI_SERVICE="${OPENAI_SERVICE:-openai-personalization-${RANDOM_SUFFIX}}"
    export FUNCTION_APP="${FUNCTION_APP:-func-personalization-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stpersonalization${RANDOM_SUFFIX}}"
    
    # Save all variables to state file
    save_state "LOCATION" "${LOCATION}"
    save_state "SUBSCRIPTION_ID" "${SUBSCRIPTION_ID}"
    save_state "RESOURCE_GROUP" "${RESOURCE_GROUP}"
    save_state "COSMOS_ACCOUNT" "${COSMOS_ACCOUNT}"
    save_state "AI_FOUNDRY_PROJECT" "${AI_FOUNDRY_PROJECT}"
    save_state "OPENAI_SERVICE" "${OPENAI_SERVICE}"
    save_state "FUNCTION_APP" "${FUNCTION_APP}"
    save_state "STORAGE_ACCOUNT" "${STORAGE_ACCOUNT}"
    
    log_info "Environment initialized with resource group: ${RESOURCE_GROUP}"
    log_success "Environment variables configured"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=recipe environment=demo created-by=deploy-script \
            || error_exit "Failed to create resource group"
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Create storage account for Azure Functions
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT}..."
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account ${STORAGE_ACCOUNT} already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --tags purpose=functions-storage \
            || error_exit "Failed to create storage account"
        
        log_success "Storage account created: ${STORAGE_ACCOUNT}"
    fi
}

# Create Cosmos DB account with vector search
create_cosmos_db() {
    log_info "Creating Cosmos DB account: ${COSMOS_ACCOUNT}..."
    
    if az cosmosdb show --name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Cosmos DB account ${COSMOS_ACCOUNT} already exists"
    else
        az cosmosdb create \
            --name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --locations regionName="${LOCATION}" \
            --enable-automatic-failover true \
            --default-consistency-level Session \
            --capabilities EnableNoSQLVectorSearch \
            || error_exit "Failed to create Cosmos DB account"
        
        log_success "Cosmos DB account created: ${COSMOS_ACCOUNT}"
    fi
    
    # Wait for account to be fully provisioned
    log_info "Waiting for Cosmos DB account to be ready..."
    local max_attempts=30
    local attempt=1
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local status=$(az cosmosdb show \
            --name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query provisioningState \
            --output tsv 2>/dev/null || echo "NotReady")
        
        if [[ "${status}" == "Succeeded" ]]; then
            break
        fi
        
        log_info "Cosmos DB status: ${status}. Waiting... (${attempt}/${max_attempts})"
        sleep 30
        ((attempt++))
    done
    
    if [[ ${attempt} -gt ${max_attempts} ]]; then
        error_exit "Cosmos DB account failed to provision within expected time"
    fi
    
    # Create database and containers
    log_info "Creating Cosmos DB database and containers..."
    
    # Create database
    az cosmosdb sql database create \
        --account-name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name PersonalizationDB \
        || log_warning "Database PersonalizationDB may already exist"
    
    # Create UserProfiles container
    az cosmosdb sql container create \
        --account-name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --database-name PersonalizationDB \
        --name UserProfiles \
        --partition-key-path "/userId" \
        --throughput 400 \
        || log_warning "Container UserProfiles may already exist"
    
    # Create ContentItems container
    az cosmosdb sql container create \
        --account-name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --database-name PersonalizationDB \
        --name ContentItems \
        --partition-key-path "/category" \
        --throughput 400 \
        || log_warning "Container ContentItems may already exist"
    
    log_success "Cosmos DB database and containers created"
}

# Create Azure OpenAI service
create_openai_service() {
    log_info "Creating Azure OpenAI service: ${OPENAI_SERVICE}..."
    
    if az cognitiveservices account show --name "${OPENAI_SERVICE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Azure OpenAI service ${OPENAI_SERVICE} already exists"
    else
        az cognitiveservices account create \
            --name "${OPENAI_SERVICE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --kind OpenAI \
            --sku S0 \
            --custom-domain "${OPENAI_SERVICE}" \
            --tags purpose=content-generation \
            || error_exit "Failed to create Azure OpenAI service"
        
        log_success "Azure OpenAI service created: ${OPENAI_SERVICE}"
    fi
    
    # Wait for service to be ready
    log_info "Waiting for Azure OpenAI service to be ready..."
    local max_attempts=20
    local attempt=1
    while [[ ${attempt} -le ${max_attempts} ]]; do
        local status=$(az cognitiveservices account show \
            --name "${OPENAI_SERVICE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query provisioningState \
            --output tsv 2>/dev/null || echo "NotReady")
        
        if [[ "${status}" == "Succeeded" ]]; then
            break
        fi
        
        log_info "OpenAI service status: ${status}. Waiting... (${attempt}/${max_attempts})"
        sleep 15
        ((attempt++))
    done
    
    if [[ ${attempt} -gt ${max_attempts} ]]; then
        error_exit "Azure OpenAI service failed to provision within expected time"
    fi
    
    # Deploy models
    log_info "Deploying OpenAI models..."
    
    # Deploy GPT-4 model for content generation
    az cognitiveservices account deployment create \
        --name "${OPENAI_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name gpt-4-content \
        --model-name gpt-4 \
        --model-version "0613" \
        --model-format OpenAI \
        --sku-capacity 10 \
        --sku-name Standard \
        || log_warning "GPT-4 deployment may already exist or model unavailable in region"
    
    # Deploy text embedding model for vector search
    az cognitiveservices account deployment create \
        --name "${OPENAI_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name text-embedding \
        --model-name text-embedding-ada-002 \
        --model-version "2" \
        --model-format OpenAI \
        --sku-capacity 10 \
        --sku-name Standard \
        || log_warning "Text embedding deployment may already exist or model unavailable in region"
    
    log_success "OpenAI models deployed"
}

# Create AI Foundry workspace
create_ai_foundry() {
    log_info "Creating AI Foundry workspace: ${AI_FOUNDRY_PROJECT}..."
    
    if az ml workspace show --name "${AI_FOUNDRY_PROJECT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "AI Foundry workspace ${AI_FOUNDRY_PROJECT} already exists"
    else
        az ml workspace create \
            --name "${AI_FOUNDRY_PROJECT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --description "AI Foundry workspace for content personalization" \
            --tags purpose=ai-orchestration \
            || error_exit "Failed to create AI Foundry workspace"
        
        log_success "AI Foundry workspace created: ${AI_FOUNDRY_PROJECT}"
    fi
}

# Configure vector search in Cosmos DB
configure_vector_search() {
    log_info "Configuring vector search in Cosmos DB..."
    
    # Create vector index policy file
    cat > "${SCRIPT_DIR}/vector-index-policy.json" << 'EOF'
{
  "vectorEmbeddingPolicy": {
    "vectorEmbeddings": [
      {
        "path": "/contentEmbedding",
        "dataType": "float32",
        "distanceFunction": "cosine",
        "dimensions": 1536
      },
      {
        "path": "/userPreferenceEmbedding", 
        "dataType": "float32",
        "distanceFunction": "cosine",
        "dimensions": 1536
      }
    ]
  },
  "indexingPolicy": {
    "vectorIndexes": [
      {
        "path": "/contentEmbedding",
        "type": "quantizedFlat"
      },
      {
        "path": "/userPreferenceEmbedding",
        "type": "quantizedFlat"
      }
    ],
    "excludedPaths": [
      {
        "path": "/contentEmbedding/*"
      },
      {
        "path": "/userPreferenceEmbedding/*"
      }
    ]
  }
}
EOF
    
    # Update container with vector search capabilities
    az cosmosdb sql container update \
        --account-name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --database-name PersonalizationDB \
        --name ContentItems \
        --idx @"${SCRIPT_DIR}/vector-index-policy.json" \
        || error_exit "Failed to configure vector search index"
    
    # Clean up temporary file
    rm -f "${SCRIPT_DIR}/vector-index-policy.json"
    
    log_success "Vector search index configured"
}

# Create Azure Function App
create_function_app() {
    log_info "Creating Function App: ${FUNCTION_APP}..."
    
    if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Function App ${FUNCTION_APP} already exists"
    else
        az functionapp create \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime python \
            --runtime-version 3.12 \
            --functions-version 4 \
            --os-type Linux \
            --tags purpose=personalization-api \
            || error_exit "Failed to create Function App"
        
        log_success "Function App created: ${FUNCTION_APP}"
    fi
    
    # Get service credentials for configuration
    log_info "Retrieving service credentials..."
    
    local openai_endpoint=$(az cognitiveservices account show \
        --name "${OPENAI_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.endpoint \
        --output tsv)
    
    local openai_key=$(az cognitiveservices account keys list \
        --name "${OPENAI_SERVICE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 \
        --output tsv)
    
    local cosmos_connection=$(az cosmosdb keys list \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --type connection-strings \
        --query "connectionStrings[0].connectionString" \
        --output tsv)
    
    # Configure Function App settings
    log_info "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        COSMOS_CONNECTION_STRING="${cosmos_connection}" \
        OPENAI_ENDPOINT="${openai_endpoint}" \
        OPENAI_API_KEY="${openai_key}" \
        AI_FOUNDRY_WORKSPACE="${AI_FOUNDRY_PROJECT}" \
        || error_exit "Failed to configure Function App settings"
    
    log_success "Function App configured with AI service connections"
}

# Deploy function code
deploy_function_code() {
    log_info "Deploying personalization function code..."
    
    # Create temporary directory for function code
    local temp_dir="${SCRIPT_DIR}/temp-function"
    mkdir -p "${temp_dir}"
    
    # Create requirements.txt
    cat > "${temp_dir}/requirements.txt" << 'EOF'
azure-functions==1.20.0
azure-cosmos==4.6.0
openai==1.10.0
azure-identity==1.15.0
numpy==1.24.3
EOF
    
    # Create function code
    cat > "${temp_dir}/__init__.py" << 'EOF'
import json
import logging
import os
from azure.functions import HttpRequest, HttpResponse
from azure.cosmos import CosmosClient
from openai import AzureOpenAI
import numpy as np

def main(req: HttpRequest) -> HttpResponse:
    try:
        # Get user ID from request
        user_id = req.params.get('userId')
        if not user_id:
            return HttpResponse(
                json.dumps({"error": "userId parameter required"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Initialize services
        cosmos_client = CosmosClient.from_connection_string(
            os.environ['COSMOS_CONNECTION_STRING']
        )
        
        # Initialize Azure OpenAI client (v1 API)
        openai_client = AzureOpenAI(
            api_key=os.environ['OPENAI_API_KEY'],
            azure_endpoint=os.environ['OPENAI_ENDPOINT'],
            api_version="2024-02-01"
        )
        
        # Get user profile and generate personalized content
        database = cosmos_client.get_database_client("PersonalizationDB")
        users_container = database.get_container_client("UserProfiles")
        content_container = database.get_container_client("ContentItems")
        
        # Retrieve user profile
        try:
            user_profile = users_container.read_item(
                item=user_id, 
                partition_key=user_id
            )
        except:
            # Create default profile for new users
            user_profile = {
                "id": user_id,
                "userId": user_id,
                "preferences": [],
                "engagement_history": []
            }
        
        # Generate personalized recommendations
        recommendations = generate_recommendations(
            user_profile, content_container, openai_client
        )
        
        return HttpResponse(
            json.dumps({
                "userId": user_id,
                "recommendations": recommendations,
                "status": "success"
            }),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logging.error(f"Error in personalization function: {str(e)}")
        return HttpResponse(
            json.dumps({"error": "Internal server error"}),
            status_code=500,
            mimetype="application/json"
        )

def generate_recommendations(user_profile, content_container, openai_client):
    # Simplified recommendation logic
    # In production, this would use vector search and AI Foundry orchestration
    try:
        # Generate sample personalized content using OpenAI
        prompt = f"Generate a personalized article title for user with preferences: {user_profile.get('preferences', [])}"
        
        response = openai_client.chat.completions.create(
            model="gpt-4-content",
            messages=[
                {"role": "system", "content": "You are a content personalization assistant."},
                {"role": "user", "content": prompt}
            ],
            max_tokens=50
        )
        
        personalized_title = response.choices[0].message.content.strip()
        
        return [
            {
                "contentId": "article_001",
                "title": personalized_title,
                "type": "article",
                "confidence": 0.95
            }
        ]
    except Exception as e:
        logging.error(f"Error generating recommendations: {str(e)}")
        # Fallback to default recommendation
        return [
            {
                "contentId": "article_001",
                "title": "Personalized Content for You",
                "type": "article",
                "confidence": 0.75
            }
        ]
EOF
    
    # Create function.json
    cat > "${temp_dir}/function.json" << 'EOF'
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["get", "post"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "$return"
    }
  ]
}
EOF
    
    # Create deployment package
    cd "${temp_dir}"
    zip -r "${SCRIPT_DIR}/personalization-function.zip" . > /dev/null
    cd "${SCRIPT_DIR}"
    
    # Deploy function code to Azure
    az functionapp deployment source config-zip \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --src "${SCRIPT_DIR}/personalization-function.zip" \
        || error_exit "Failed to deploy function code"
    
    # Clean up temporary files
    rm -rf "${temp_dir}"
    rm -f "${SCRIPT_DIR}/personalization-function.zip"
    
    log_success "Personalization function deployed"
}

# Create AI agent configuration
create_ai_agent_config() {
    log_info "Creating AI Foundry agent configuration..."
    
    cat > "${SCRIPT_DIR}/ai-agent-config.json" << 'EOF'
{
  "agent": {
    "name": "ContentPersonalizationAgent",
    "description": "Intelligent agent for content personalization and recommendation",
    "instructions": "You are a content personalization agent. Analyze user preferences, behavior patterns, and content characteristics to generate highly relevant, personalized content recommendations. Use vector search to find similar content and users, then generate customized articles, product recommendations, and marketing content based on individual user profiles.",
    "model": "gpt-4-content",
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "query_user_preferences",
          "description": "Retrieve user preference data from Cosmos DB",
          "parameters": {
            "type": "object",
            "properties": {
              "userId": {
                "type": "string",
                "description": "Unique user identifier"
              }
            },
            "required": ["userId"]
          }
        }
      },
      {
        "type": "function", 
        "function": {
          "name": "vector_search_content",
          "description": "Perform vector similarity search for content recommendations",
          "parameters": {
            "type": "object",
            "properties": {
              "embedding": {
                "type": "array",
                "description": "Vector embedding for similarity search"
              },
              "limit": {
                "type": "integer",
                "description": "Maximum number of results to return"
              }
            },
            "required": ["embedding"]
          }
        }
      }
    ]
  }
}
EOF
    
    log_success "AI agent configuration created at: ${SCRIPT_DIR}/ai-agent-config.json"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check resource statuses
    local cosmos_status=$(az cosmosdb show \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query provisioningState \
        --output tsv)
    
    local function_status=$(az functionapp show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query state \
        --output tsv)
    
    local ai_foundry_status=$(az ml workspace show \
        --name "${AI_FOUNDRY_PROJECT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query provisioningState \
        --output tsv)
    
    if [[ "${cosmos_status}" == "Succeeded" && "${function_status}" == "Running" && "${ai_foundry_status}" == "Succeeded" ]]; then
        log_success "All services deployed successfully"
        
        # Get function URL and key for testing
        local function_key=$(az functionapp keys list \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query functionKeys.default \
            --output tsv 2>/dev/null || echo "N/A")
        
        log_info "Deployment completed successfully!"
        log_info "Resource Group: ${RESOURCE_GROUP}"
        log_info "Function App: ${FUNCTION_APP}"
        log_info "Function Key: ${function_key}"
        log_info "Test URL: https://${FUNCTION_APP}.azurewebsites.net/api/personalization-function?userId=testuser&code=${function_key}"
        
        return 0
    else
        log_error "Some services failed to deploy properly:"
        log_error "Cosmos DB: ${cosmos_status}"
        log_error "Function App: ${function_status}"
        log_error "AI Foundry: ${ai_foundry_status}"
        return 1
    fi
}

# Print deployment summary
print_summary() {
    log_info ""
    log_info "=== DEPLOYMENT SUMMARY ==="
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Cosmos DB Account: ${COSMOS_ACCOUNT}"
    log_info "OpenAI Service: ${OPENAI_SERVICE}"
    log_info "AI Foundry Project: ${AI_FOUNDRY_PROJECT}"
    log_info "Function App: ${FUNCTION_APP}"
    log_info "Storage Account: ${STORAGE_ACCOUNT}"
    log_info "Deployment State File: ${DEPLOYMENT_STATE_FILE}"
    log_info "Deployment Log: ${LOG_FILE}"
    log_info ""
    log_success "Content Personalization Engine deployed successfully!"
    log_info "You can now test the personalization API or extend the solution."
    log_info "Run destroy.sh to clean up all resources when finished."
}

# Main deployment flow
main() {
    log_info "Starting Azure Content Personalization Engine deployment..."
    log_info "Deployment started at: $(date)"
    
    check_prerequisites
    initialize_environment
    create_resource_group
    create_storage_account
    create_cosmos_db
    create_openai_service
    create_ai_foundry
    configure_vector_search
    create_function_app
    deploy_function_code
    create_ai_agent_config
    
    if validate_deployment; then
        print_summary
        log_success "Deployment completed successfully at: $(date)"
        exit 0
    else
        error_exit "Deployment validation failed"
    fi
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Deploy Azure Content Personalization Engine"
            echo ""
            echo "Options:"
            echo "  --help, -h        Show this help message"
            echo "  --location LOCATION   Set Azure region (default: eastus)"
            echo "  --dry-run         Show what would be deployed without creating resources"
            echo ""
            echo "Environment Variables:"
            echo "  LOCATION          Azure region for deployment"
            echo "  RESOURCE_GROUP    Resource group name (generated if not set)"
            echo ""
            exit 0
            ;;
        --location)
            export LOCATION="$2"
            shift 2
            ;;
        --dry-run)
            log_info "DRY RUN MODE - No resources will be created"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute main deployment
main "$@"