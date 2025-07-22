#!/bin/bash

# Azure AI-Powered Migration Assessment - Deployment Script
# This script deploys the complete infrastructure for AI-powered migration assessment
# using Azure Migrate, Azure OpenAI Service, Azure Functions, and Azure Storage

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Enable logging
exec > >(tee -a "deploy_$(date +%Y%m%d_%H%M%S).log")
exec 2>&1

# Colors for output
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

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check the logs for details."
    exit 1
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config/deployment.conf"

# Default values
DEFAULT_RESOURCE_GROUP="rg-migrate-ai-assessment"
DEFAULT_LOCATION="eastus"
DEFAULT_ENVIRONMENT="dev"

# Load configuration if exists
if [[ -f "$CONFIG_FILE" ]]; then
    log_info "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
else
    log_info "Using default configuration values"
fi

# Set environment variables with defaults
export RESOURCE_GROUP="${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"
export LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
export ENVIRONMENT="${ENVIRONMENT:-$DEFAULT_ENVIRONMENT}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first."
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az --version | grep 'azure-cli' | awk '{print $2}')
    log_info "Azure CLI version: $AZ_VERSION"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Please log in to Azure using 'az login' first."
    fi
    
    # Check if subscription is set
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        error_exit "No Azure subscription selected. Please run 'az account set --subscription <subscription-id>'."
    fi
    
    log_info "Using subscription: $SUBSCRIPTION_ID"
    
    # Check if required tools are available
    if ! command -v openssl &> /dev/null; then
        error_exit "OpenSSL is not installed. Please install it first."
    fi
    
    if ! command -v curl &> /dev/null; then
        error_exit "curl is not installed. Please install it first."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to generate unique resource names
generate_resource_names() {
    log_info "Generating unique resource names..."
    
    # Generate random suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    export STORAGE_ACCOUNT="stamigrate${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-migrate-ai-${RANDOM_SUFFIX}"
    export OPENAI_SERVICE="openai-migrate-${RANDOM_SUFFIX}"
    export MIGRATE_PROJECT="migrate-project-${RANDOM_SUFFIX}"
    
    log_info "Resource names generated with suffix: $RANDOM_SUFFIX"
    log_info "Storage Account: $STORAGE_ACCOUNT"
    log_info "Function App: $FUNCTION_APP"
    log_info "OpenAI Service: $OPENAI_SERVICE"
    log_info "Migrate Project: $MIGRATE_PROJECT"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=migration-assessment environment="$ENVIRONMENT" \
            --output none
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Storage account $STORAGE_ACCOUNT already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --output none
        
        log_success "Storage account created: $STORAGE_ACCOUNT"
    fi
    
    # Get storage account key
    STORAGE_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT" \
        --query '[0].value' \
        --output tsv)
    
    # Create storage containers
    log_info "Creating storage containers..."
    
    for container in "assessment-data" "ai-insights" "modernization-reports"; do
        if az storage container exists \
            --account-name "$STORAGE_ACCOUNT" \
            --account-key "$STORAGE_KEY" \
            --name "$container" \
            --output tsv | grep -q "True"; then
            log_warning "Container $container already exists"
        else
            az storage container create \
                --name "$container" \
                --account-name "$STORAGE_ACCOUNT" \
                --account-key "$STORAGE_KEY" \
                --public-access off \
                --output none
            
            log_success "Container created: $container"
        fi
    done
}

# Function to create Azure Migrate project
create_migrate_project() {
    log_info "Creating Azure Migrate project: $MIGRATE_PROJECT"
    
    # Check if project already exists
    if az migrate project show --name "$MIGRATE_PROJECT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Azure Migrate project $MIGRATE_PROJECT already exists"
    else
        # Create Azure Migrate project
        az migrate project create \
            --name "$MIGRATE_PROJECT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --properties "{
                \"assessmentSolutionId\": \"/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Migrate/assessmentProjects/$MIGRATE_PROJECT\",
                \"customerWorkspaceId\": \"\",
                \"customerWorkspaceLocation\": \"\"
            }" \
            --output none
        
        log_success "Azure Migrate project created: $MIGRATE_PROJECT"
    fi
}

# Function to create Azure OpenAI Service
create_openai_service() {
    log_info "Creating Azure OpenAI Service: $OPENAI_SERVICE"
    
    # Check if service already exists
    if az cognitiveservices account show --name "$OPENAI_SERVICE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Azure OpenAI Service $OPENAI_SERVICE already exists"
    else
        # Create Azure OpenAI Service
        az cognitiveservices account create \
            --name "$OPENAI_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind OpenAI \
            --sku S0 \
            --custom-domain "$OPENAI_SERVICE" \
            --output none
        
        log_success "Azure OpenAI Service created: $OPENAI_SERVICE"
    fi
    
    # Get OpenAI service endpoint and key
    OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "$OPENAI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint \
        --output tsv)
    
    OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "$OPENAI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 \
        --output tsv)
    
    log_info "OpenAI Service endpoint: $OPENAI_ENDPOINT"
    
    # Deploy GPT-4 model
    log_info "Deploying GPT-4 model for migration analysis..."
    
    if az cognitiveservices account deployment show \
        --name "$OPENAI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "gpt-4-migration-analysis" &> /dev/null; then
        log_warning "GPT-4 model deployment already exists"
    else
        az cognitiveservices account deployment create \
            --name "$OPENAI_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name "gpt-4-migration-analysis" \
            --model-name "gpt-4" \
            --model-version "0613" \
            --model-format OpenAI \
            --sku-capacity 20 \
            --sku-name Standard \
            --output none
        
        log_info "Waiting for model deployment to complete..."
        sleep 30
        
        # Verify deployment status
        DEPLOYMENT_STATUS=$(az cognitiveservices account deployment show \
            --name "$OPENAI_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name "gpt-4-migration-analysis" \
            --query properties.provisioningState \
            --output tsv)
        
        if [[ "$DEPLOYMENT_STATUS" == "Succeeded" ]]; then
            log_success "GPT-4 model deployed successfully"
        else
            error_exit "GPT-4 model deployment failed with status: $DEPLOYMENT_STATUS"
        fi
    fi
}

# Function to create Azure Function App
create_function_app() {
    log_info "Creating Azure Function App: $FUNCTION_APP"
    
    # Check if function app already exists
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Function App $FUNCTION_APP already exists"
    else
        # Create Function App with consumption plan
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
        
        log_success "Function App created: $FUNCTION_APP"
    fi
    
    # Get storage connection string
    STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    # Configure application settings
    log_info "Configuring Function App settings..."
    
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
            "OPENAI_ENDPOINT=$OPENAI_ENDPOINT" \
            "OPENAI_KEY=$OPENAI_KEY" \
            "OPENAI_MODEL_DEPLOYMENT=gpt-4-migration-analysis" \
            "MIGRATE_PROJECT=$MIGRATE_PROJECT" \
            "STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING" \
        --output none
    
    log_success "Function App settings configured"
}

# Function to deploy function code
deploy_function_code() {
    log_info "Deploying function code..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Create function code for AI assessment processing
    cat > __init__.py << 'EOF'
import azure.functions as func
import json
import logging
import os
from azure.storage.blob import BlobServiceClient
from openai import AzureOpenAI
import asyncio

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Migration AI Assessment function triggered')
    
    try:
        # Initialize OpenAI client
        client = AzureOpenAI(
            api_key=os.environ["OPENAI_KEY"],
            api_version="2024-06-01",
            azure_endpoint=os.environ["OPENAI_ENDPOINT"]
        )
        
        # Get assessment data from request
        assessment_data = req.get_json()
        
        # Process with AI analysis
        analysis_prompt = f"""
        Analyze the following migration assessment data and provide intelligent modernization recommendations:
        
        Assessment Data: {json.dumps(assessment_data, indent=2)}
        
        Please provide:
        1. Workload modernization opportunities
        2. Cost optimization recommendations
        3. Security and compliance considerations
        4. Performance optimization strategies
        5. Risk assessment and mitigation
        
        Format the response as structured JSON with clear recommendations.
        """
        
        response = client.chat.completions.create(
            model=os.environ["OPENAI_MODEL_DEPLOYMENT"],
            messages=[
                {"role": "system", "content": "You are an expert Azure migration architect providing intelligent workload modernization recommendations."},
                {"role": "user", "content": analysis_prompt}
            ],
            max_tokens=2000,
            temperature=0.1
        )
        
        ai_insights = response.choices[0].message.content
        
        # Store insights in blob storage
        blob_service_client = BlobServiceClient.from_connection_string(
            os.environ["STORAGE_CONNECTION_STRING"]
        )
        
        blob_client = blob_service_client.get_blob_client(
            container="ai-insights",
            blob=f"assessment-{assessment_data.get('timestamp', 'unknown')}.json"
        )
        
        blob_client.upload_blob(ai_insights, overwrite=True)
        
        return func.HttpResponse(
            json.dumps({
                "status": "success",
                "insights": ai_insights,
                "message": "AI assessment completed successfully"
            }),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logging.error(f"Error processing assessment: {str(e)}")
        return func.HttpResponse(
            json.dumps({
                "status": "error",
                "message": f"Error processing assessment: {str(e)}"
            }),
            status_code=500,
            mimetype="application/json"
        )
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
azure-functions
azure-storage-blob
openai==1.3.0
EOF
    
    # Create function.json
    mkdir -p migrate-ai-assessment
    cat > migrate-ai-assessment/function.json << 'EOF'
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
    
    # Move function code to correct location
    mv __init__.py migrate-ai-assessment/
    
    # Create deployment package
    zip -r function-app.zip . > /dev/null 2>&1
    
    # Deploy function code
    az functionapp deployment source config-zip \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP" \
        --src function-app.zip \
        --output none
    
    log_success "Function code deployed successfully"
    
    # Clean up temporary files
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
}

# Function to create sample assessment data
create_sample_data() {
    log_info "Creating sample assessment data..."
    
    # Create sample assessment data file
    SAMPLE_DATA_FILE="/tmp/sample-assessment.json"
    
    cat > "$SAMPLE_DATA_FILE" << 'EOF'
{
  "timestamp": "2025-07-12T10:00:00Z",
  "project": "migrate-project-demo",
  "servers": [
    {
      "name": "web-server-01",
      "os": "Windows Server 2016",
      "cpu_cores": 4,
      "memory_gb": 16,
      "storage_gb": 500,
      "network_utilization": "medium",
      "applications": ["IIS", "ASP.NET"],
      "dependencies": ["sql-server-01", "file-server-01"]
    },
    {
      "name": "sql-server-01",
      "os": "Windows Server 2019",
      "cpu_cores": 8,
      "memory_gb": 32,
      "storage_gb": 1000,
      "network_utilization": "high",
      "applications": ["SQL Server 2019"],
      "dependencies": ["backup-server-01"]
    }
  ],
  "assessment_recommendations": {
    "azure_readiness": "Ready",
    "estimated_monthly_cost": 2500,
    "recommended_vm_sizes": {
      "web-server-01": "Standard_D4s_v3",
      "sql-server-01": "Standard_E8s_v3"
    }
  }
}
EOF
    
    # Upload sample data to storage
    az storage blob upload \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --container-name assessment-data \
        --file "$SAMPLE_DATA_FILE" \
        --name sample-assessment.json \
        --overwrite \
        --output none
    
    log_success "Sample assessment data uploaded"
    
    # Clean up temporary file
    rm "$SAMPLE_DATA_FILE"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing deployment..."
    
    # Test Azure Migrate project
    MIGRATE_STATUS=$(az migrate project show \
        --name "$MIGRATE_PROJECT" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.provisioningState \
        --output tsv 2>/dev/null || echo "Failed")
    
    if [[ "$MIGRATE_STATUS" == "Succeeded" ]]; then
        log_success "Azure Migrate project is ready"
    else
        log_error "Azure Migrate project status: $MIGRATE_STATUS"
    fi
    
    # Test OpenAI service
    OPENAI_STATUS=$(az cognitiveservices account show \
        --name "$OPENAI_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.provisioningState \
        --output tsv 2>/dev/null || echo "Failed")
    
    if [[ "$OPENAI_STATUS" == "Succeeded" ]]; then
        log_success "Azure OpenAI Service is ready"
    else
        log_error "Azure OpenAI Service status: $OPENAI_STATUS"
    fi
    
    # Test Function App
    FUNCTION_STATUS=$(az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query state \
        --output tsv 2>/dev/null || echo "Failed")
    
    if [[ "$FUNCTION_STATUS" == "Running" ]]; then
        log_success "Function App is ready"
    else
        log_error "Function App status: $FUNCTION_STATUS"
    fi
    
    # Test storage containers
    CONTAINERS=$(az storage container list \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --query '[].name' \
        --output tsv 2>/dev/null || echo "Failed")
    
    if [[ "$CONTAINERS" == *"assessment-data"* && "$CONTAINERS" == *"ai-insights"* ]]; then
        log_success "Storage containers are ready"
    else
        log_error "Storage containers not found"
    fi
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=========================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Function App: $FUNCTION_APP"
    echo "OpenAI Service: $OPENAI_SERVICE"
    echo "Migrate Project: $MIGRATE_PROJECT"
    echo "=========================="
    
    # Get Function URL
    FUNCTION_URL=$(az functionapp function show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP" \
        --function-name migrate-ai-assessment \
        --query invokeUrlTemplate \
        --output tsv 2>/dev/null || echo "Not available")
    
    echo "Function URL: $FUNCTION_URL"
    
    # Save deployment info
    DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/../deployment-info.json"
    cat > "$DEPLOYMENT_INFO_FILE" << EOF
{
  "resourceGroup": "$RESOURCE_GROUP",
  "location": "$LOCATION",
  "storageAccount": "$STORAGE_ACCOUNT",
  "functionApp": "$FUNCTION_APP",
  "openaiService": "$OPENAI_SERVICE",
  "migrateProject": "$MIGRATE_PROJECT",
  "functionUrl": "$FUNCTION_URL",
  "deploymentDate": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    
    log_success "Deployment information saved to $DEPLOYMENT_INFO_FILE"
}

# Main deployment function
main() {
    log_info "Starting Azure AI-Powered Migration Assessment deployment"
    log_info "Deployment started at: $(date)"
    
    # Check if dry run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log_info "Running in dry-run mode - no resources will be created"
        return 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    generate_resource_names
    create_resource_group
    create_storage_account
    create_migrate_project
    create_openai_service
    create_function_app
    deploy_function_code
    create_sample_data
    test_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
    log_info "Deployment finished at: $(date)"
    
    log_info "Next steps:"
    echo "1. Configure your on-premises environment with Azure Migrate appliance"
    echo "2. Run assessments and collect workload data"
    echo "3. Use the Function URL to process assessment data through AI analysis"
    echo "4. Review AI-generated insights in the storage account"
    echo "5. Run ./destroy.sh to clean up resources when done"
}

# Check if running directly or being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi