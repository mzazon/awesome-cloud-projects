#!/bin/bash

# Smart Model Selection with AI Foundry and Functions - Deployment Script
# This script deploys the complete infrastructure for intelligent model selection using Azure AI Foundry

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $AZ_VERSION"
    
    # Check if Azure Functions Core Tools is installed
    if ! command -v func &> /dev/null; then
        log_error "Azure Functions Core Tools is not installed. Please install it first."
        exit 1
    fi
    
    # Check Functions Core Tools version
    FUNC_VERSION=$(func --version)
    log_info "Azure Functions Core Tools version: $FUNC_VERSION"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random values. Please install it first."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set Azure environment variables
    export RESOURCE_GROUP="rg-smart-model-${RANDOM_SUFFIX}"
    export LOCATION="eastus2"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names with unique suffix
    export AI_FOUNDRY_NAME="aifoundry${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="func-smart-model-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="smartmodel${RANDOM_SUFFIX}"
    export APP_INSIGHTS_NAME="insights-smart-model-${RANDOM_SUFFIX}"
    
    # Store variables in a file for cleanup script
    cat > .deployment_vars << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
AI_FOUNDRY_NAME=${AI_FOUNDRY_NAME}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME}
APP_INSIGHTS_NAME=${APP_INSIGHTS_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables configured:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  AI Foundry: ${AI_FOUNDRY_NAME}"
    log_info "  Function App: ${FUNCTION_APP_NAME}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group..."
    
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --tags purpose=recipe environment=demo \
            --output none
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create AI Services resource
create_ai_services() {
    log_info "Creating Azure AI Services resource..."
    
    if az cognitiveservices account show --name ${AI_FOUNDRY_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "AI Services resource ${AI_FOUNDRY_NAME} already exists"
    else
        az cognitiveservices account create \
            --name ${AI_FOUNDRY_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --kind "AIServices" \
            --sku "S0" \
            --custom-domain ${AI_FOUNDRY_NAME} \
            --tags purpose=smart-model-selection \
            --output none
        
        log_success "AI Services resource created: ${AI_FOUNDRY_NAME}"
    fi
    
    # Get endpoint and key
    AI_FOUNDRY_ENDPOINT=$(az cognitiveservices account show \
        --name ${AI_FOUNDRY_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query "properties.endpoint" \
        --output tsv)
    
    AI_FOUNDRY_KEY=$(az cognitiveservices account keys list \
        --name ${AI_FOUNDRY_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query "key1" \
        --output tsv)
    
    log_info "AI Services endpoint: ${AI_FOUNDRY_ENDPOINT}"
}

# Function to deploy Model Router
deploy_model_router() {
    log_info "Deploying Model Router..."
    
    # Check if deployment already exists
    if az cognitiveservices account deployment show \
        --name ${AI_FOUNDRY_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --deployment-name "model-router" &> /dev/null; then
        log_warning "Model Router deployment already exists"
    else
        az cognitiveservices account deployment create \
            --name ${AI_FOUNDRY_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --deployment-name "model-router" \
            --model-name "model-router" \
            --model-version "2025-05-19" \
            --sku-capacity 10 \
            --sku-name "GlobalStandard" \
            --output none
        
        log_info "Waiting for Model Router deployment to complete..."
        sleep 30
        
        # Verify deployment status
        DEPLOYMENT_STATUS=$(az cognitiveservices account deployment show \
            --name ${AI_FOUNDRY_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --deployment-name "model-router" \
            --query "properties.provisioningState" \
            --output tsv)
        
        if [ "$DEPLOYMENT_STATUS" = "Succeeded" ]; then
            log_success "Model Router deployed successfully"
        else
            log_error "Model Router deployment failed with status: ${DEPLOYMENT_STATUS}"
            exit 1
        fi
    fi
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account for analytics..."
    
    if az storage account show --name ${STORAGE_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Storage account ${STORAGE_ACCOUNT_NAME} already exists"
    else
        az storage account create \
            --name ${STORAGE_ACCOUNT_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --sku Standard_LRS \
            --kind StorageV2 \
            --tags purpose=analytics environment=demo \
            --output none
        
        log_success "Storage account created: ${STORAGE_ACCOUNT_NAME}"
    fi
    
    # Get storage connection string
    STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name ${STORAGE_ACCOUNT_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query "connectionString" \
        --output tsv)
    
    # Create tables for metrics and cost tracking
    log_info "Creating storage tables..."
    
    az storage table create \
        --name "modelmetrics" \
        --connection-string "${STORAGE_CONNECTION_STRING}" \
        --output none
    
    az storage table create \
        --name "costtracking" \
        --connection-string "${STORAGE_CONNECTION_STRING}" \
        --output none
    
    log_success "Storage tables created"
}

# Function to create Application Insights
create_app_insights() {
    log_info "Creating Application Insights..."
    
    if az monitor app-insights component show --app ${APP_INSIGHTS_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Application Insights ${APP_INSIGHTS_NAME} already exists"
    else
        az monitor app-insights component create \
            --app ${APP_INSIGHTS_NAME} \
            --location ${LOCATION} \
            --resource-group ${RESOURCE_GROUP} \
            --tags purpose=monitoring \
            --output none
        
        log_success "Application Insights created: ${APP_INSIGHTS_NAME}"
    fi
    
    # Get instrumentation key
    APPINSIGHTS_KEY=$(az monitor app-insights component show \
        --app ${APP_INSIGHTS_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query "instrumentationKey" \
        --output tsv)
    
    log_info "Application Insights instrumentation key configured"
}

# Function to create Function App
create_function_app() {
    log_info "Creating Azure Function App..."
    
    if az functionapp show --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log_warning "Function App ${FUNCTION_APP_NAME} already exists"
    else
        az functionapp create \
            --name ${FUNCTION_APP_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --storage-account ${STORAGE_ACCOUNT_NAME} \
            --consumption-plan-location ${LOCATION} \
            --runtime python \
            --runtime-version 3.11 \
            --functions-version 4 \
            --app-insights ${APP_INSIGHTS_NAME} \
            --tags purpose=ai-routing \
            --output none
        
        log_success "Function App created: ${FUNCTION_APP_NAME}"
    fi
    
    # Configure application settings
    log_info "Configuring Function App settings..."
    
    az functionapp config appsettings set \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --settings \
            "AI_FOUNDRY_ENDPOINT=${AI_FOUNDRY_ENDPOINT}" \
            "AI_FOUNDRY_KEY=${AI_FOUNDRY_KEY}" \
            "STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION_STRING}" \
            "APPINSIGHTS_INSTRUMENTATIONKEY=${APPINSIGHTS_KEY}" \
        --output none
    
    log_success "Function App settings configured"
}

# Function to deploy Function code
deploy_function_code() {
    log_info "Deploying Function code..."
    
    # Create temporary function directory
    TEMP_DIR=$(mktemp -d)
    cd ${TEMP_DIR}
    
    # Create function directory structure
    mkdir -p smart-model-function/ModelSelection
    mkdir -p smart-model-function/AnalyticsDashboard
    
    # Create requirements.txt
    cat > smart-model-function/requirements.txt << 'EOF'
azure-functions
azure-data-tables>=12.4.0
openai>=1.0.0
requests>=2.28.0
EOF
    
    # Create ModelSelection function.json
    cat > smart-model-function/ModelSelection/function.json << 'EOF'
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
    
    # Create ModelSelection __init__.py
    cat > smart-model-function/ModelSelection/__init__.py << 'EOF'
import azure.functions as func
import json
import logging
import os
import time
from datetime import datetime
from azure.data.tables import TableServiceClient
from openai import AzureOpenAI

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Smart Model Selection function processed a request.')
    
    try:
        # Get request data
        req_body = req.get_json()
        user_message = req_body.get('message', '')
        user_id = req_body.get('user_id', 'anonymous')
        
        # Initialize Azure OpenAI client
        client = AzureOpenAI(
            azure_endpoint=os.environ['AI_FOUNDRY_ENDPOINT'],
            api_key=os.environ['AI_FOUNDRY_KEY'],
            api_version="2024-10-01-preview"
        )
        
        # Record start time for performance tracking
        start_time = time.time()
        
        # Call Model Router
        response = client.chat.completions.create(
            model="model-router",
            messages=[
                {"role": "user", "content": user_message}
            ],
            max_tokens=500,
            temperature=0.7
        )
        
        # Calculate response time
        response_time = time.time() - start_time
        
        # Extract selected model from response
        selected_model = response.model
        response_content = response.choices[0].message.content
        
        # Log metrics to Azure Table Storage
        log_metrics(user_id, user_message, selected_model, response_time, response_content)
        
        return func.HttpResponse(
            json.dumps({
                "response": response_content,
                "selected_model": selected_model,
                "response_time": response_time,
                "user_id": user_id
            }),
            status_code=200,
            headers={"Content-Type": "application/json"}
        )
        
    except Exception as e:
        logging.error(f"Error processing request: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            headers={"Content-Type": "application/json"}
        )

def log_metrics(user_id, message, selected_model, response_time, response_content):
    try:
        # Initialize Table Service Client
        table_service = TableServiceClient.from_connection_string(
            os.environ['STORAGE_CONNECTION_STRING']
        )
        
        # Log to model metrics table
        metrics_table = table_service.get_table_client("modelmetrics")
        metrics_entity = {
            "PartitionKey": datetime.now().strftime("%Y%m%d"),
            "RowKey": f"{int(time.time() * 1000)}_{user_id}",
            "UserId": user_id,
            "MessageLength": len(message),
            "SelectedModel": selected_model,
            "ResponseTime": response_time,
            "ResponseLength": len(response_content),
            "Timestamp": datetime.now()
        }
        metrics_table.create_entity(metrics_entity)
        
        # Log to cost tracking table (estimated costs based on model)
        cost_table = table_service.get_table_client("costtracking")
        estimated_cost = calculate_estimated_cost(selected_model, len(message), len(response_content))
        cost_entity = {
            "PartitionKey": datetime.now().strftime("%Y%m%d"),
            "RowKey": f"{int(time.time() * 1000)}_{user_id}_cost",
            "UserId": user_id,
            "SelectedModel": selected_model,
            "EstimatedCost": estimated_cost,
            "InputTokens": len(message) // 4,  # Rough token estimate
            "OutputTokens": len(response_content) // 4,
            "Timestamp": datetime.now()
        }
        cost_table.create_entity(cost_entity)
        
    except Exception as e:
        logging.error(f"Error logging metrics: {str(e)}")

def calculate_estimated_cost(model, input_length, output_length):
    # Estimated costs per 1K tokens (simplified)
    cost_map = {
        "gpt-4.1": {"input": 0.03, "output": 0.06},
        "gpt-4.1-mini": {"input": 0.015, "output": 0.03},
        "gpt-4.1-nano": {"input": 0.0075, "output": 0.015},
        "o4-mini": {"input": 0.015, "output": 0.06}
    }
    
    # Default to mid-tier pricing if model not found
    pricing = cost_map.get(model, cost_map["gpt-4.1-mini"])
    
    input_tokens = input_length // 4
    output_tokens = output_length // 4
    
    return (input_tokens * pricing["input"] / 1000) + (output_tokens * pricing["output"] / 1000)
EOF
    
    # Create AnalyticsDashboard function.json
    cat > smart-model-function/AnalyticsDashboard/function.json << 'EOF'
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["get"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "$return"
    }
  ]
}
EOF
    
    # Create AnalyticsDashboard __init__.py
    cat > smart-model-function/AnalyticsDashboard/__init__.py << 'EOF'
import azure.functions as func
import json
import logging
import os
from datetime import datetime, timedelta
from azure.data.tables import TableServiceClient
from collections import defaultdict

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Analytics Dashboard function processed a request.')
    
    try:
        # Get query parameters
        days = int(req.params.get('days', '7'))
        
        # Initialize Table Service Client
        table_service = TableServiceClient.from_connection_string(
            os.environ['STORAGE_CONNECTION_STRING']
        )
        
        # Generate analytics
        analytics = generate_analytics(table_service, days)
        
        return func.HttpResponse(
            json.dumps(analytics, indent=2, default=str),
            status_code=200,
            headers={"Content-Type": "application/json"}
        )
        
    except Exception as e:
        logging.error(f"Error generating analytics: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            headers={"Content-Type": "application/json"}
        )

def generate_analytics(table_service, days):
    # Query metrics from the last N days
    start_date = datetime.now() - timedelta(days=days)
    
    metrics_table = table_service.get_table_client("modelmetrics")
    cost_table = table_service.get_table_client("costtracking")
    
    # Get metrics data
    metrics_filter = f"Timestamp ge datetime'{start_date.isoformat()}'"
    metrics_entities = list(metrics_table.query_entities(filter=metrics_filter))
    
    # Get cost data
    cost_entities = list(cost_table.query_entities(filter=metrics_filter))
    
    # Generate analytics
    model_usage = defaultdict(int)
    response_times = defaultdict(list)
    total_cost = 0
    total_requests = len(metrics_entities)
    
    for entity in metrics_entities:
        model = entity.get('SelectedModel', 'unknown')
        model_usage[model] += 1
        response_times[model].append(entity.get('ResponseTime', 0))
    
    for entity in cost_entities:
        total_cost += entity.get('EstimatedCost', 0)
    
    # Calculate average response times
    avg_response_times = {}
    for model, times in response_times.items():
        avg_response_times[model] = sum(times) / len(times) if times else 0
    
    return {
        "period_days": days,
        "total_requests": total_requests,
        "total_estimated_cost": round(total_cost, 4),
        "average_cost_per_request": round(total_cost / total_requests, 6) if total_requests > 0 else 0,
        "model_usage_distribution": dict(model_usage),
        "average_response_times": avg_response_times,
        "cost_savings_estimate": calculate_cost_savings(model_usage, cost_entities)
    }

def calculate_cost_savings(model_usage, cost_entities):
    # Calculate potential savings vs using only GPT-4.1
    gpt4_cost_per_request = 0.003  # Estimate
    actual_cost = sum(entity.get('EstimatedCost', 0) for entity in cost_entities)
    total_requests = sum(model_usage.values())
    
    if total_requests == 0:
        return 0
        
    hypothetical_gpt4_cost = total_requests * gpt4_cost_per_request
    savings = hypothetical_gpt4_cost - actual_cost
    savings_percentage = (savings / hypothetical_gpt4_cost) * 100 if hypothetical_gpt4_cost > 0 else 0
    
    return {
        "estimated_savings": round(savings, 4),
        "savings_percentage": round(savings_percentage, 2)
    }
EOF
    
    # Deploy the function using Azure Functions Core Tools
    cd smart-model-function
    log_info "Publishing function to Azure..."
    
    func azure functionapp publish ${FUNCTION_APP_NAME} --build remote
    
    if [ $? -eq 0 ]; then
        log_success "Function code deployed successfully"
    else
        log_error "Function deployment failed"
        exit 1
    fi
    
    # Clean up temporary directory
    cd ..
    rm -rf ${TEMP_DIR}
}

# Function to test the deployment
test_deployment() {
    log_info "Testing the deployment..."
    
    # Get function URL and key
    FUNCTION_URL=$(az functionapp function show \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --function-name "ModelSelection" \
        --query "invokeUrlTemplate" \
        --output tsv 2>/dev/null || echo "")
    
    if [ -z "$FUNCTION_URL" ]; then
        log_warning "Could not retrieve function URL. Function may need more time to initialize."
        return
    fi
    
    FUNCTION_KEY=$(az functionapp keys list \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query "functionKeys.default" \
        --output tsv 2>/dev/null || echo "")
    
    if [ -z "$FUNCTION_KEY" ]; then
        log_warning "Could not retrieve function key. Using master key instead."
        FUNCTION_KEY=$(az functionapp keys list \
            --name ${FUNCTION_APP_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --query "masterKey" \
            --output tsv)
    fi
    
    # Test with a simple query
    log_info "Testing with a simple query..."
    
    RESPONSE=$(curl -s -X POST "${FUNCTION_URL}?code=${FUNCTION_KEY}" \
        -H "Content-Type: application/json" \
        -d '{
            "message": "What is the capital of France?",
            "user_id": "deployment_test"
        }' 2>/dev/null || echo '{"error": "curl failed"}')
    
    if echo "$RESPONSE" | grep -q "error"; then
        log_warning "Function test returned an error. This may be normal if the deployment is still initializing."
    else
        log_success "Function test completed successfully"
    fi
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "AI Foundry: ${AI_FOUNDRY_NAME}"
    echo "Function App: ${FUNCTION_APP_NAME}"
    echo "Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "Application Insights: ${APP_INSIGHTS_NAME}"
    echo ""
    echo "=== FUNCTION ENDPOINTS ==="
    
    # Get function URLs
    MODEL_SELECTION_URL=$(az functionapp function show \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --function-name "ModelSelection" \
        --query "invokeUrlTemplate" \
        --output tsv 2>/dev/null || echo "Not available yet")
    
    ANALYTICS_URL=$(az functionapp function show \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --function-name "AnalyticsDashboard" \
        --query "invokeUrlTemplate" \
        --output tsv 2>/dev/null || echo "Not available yet")
    
    echo "Model Selection: ${MODEL_SELECTION_URL}"
    echo "Analytics Dashboard: ${ANALYTICS_URL}"
    echo ""
    echo "=== NEXT STEPS ==="
    echo "1. Wait 5-10 minutes for all services to fully initialize"
    echo "2. Test the Model Selection endpoint with POST requests"
    echo "3. View analytics using the Analytics Dashboard endpoint"
    echo "4. Monitor costs and usage through the Azure portal"
    echo ""
    echo "=== CLEANUP ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo ""
    log_info "Deployment variables saved to .deployment_vars file"
}

# Main execution flow
main() {
    echo "======================================"
    echo "Smart Model Selection Deployment"
    echo "======================================"
    echo ""
    
    check_prerequisites
    setup_environment
    create_resource_group
    create_ai_services
    deploy_model_router
    create_storage_account
    create_app_insights
    create_function_app
    deploy_function_code
    test_deployment
    display_summary
}

# Run the main function
main "$@"