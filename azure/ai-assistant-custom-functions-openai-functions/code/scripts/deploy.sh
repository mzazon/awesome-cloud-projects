#!/bin/bash

# AI Assistant with Custom Functions using OpenAI and Functions - Deployment Script
# This script deploys the complete Azure AI Assistant infrastructure as described in the recipe
#
# Author: Azure Recipe Generator
# Version: 1.0
# Last Updated: 2025-01-17

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[1;34m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate Azure CLI login
validate_azure_login() {
    log_info "Validating Azure CLI login..."
    if ! az account show &>/dev/null; then
        log_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    local account_name
    account_name=$(az account show --query name --output tsv)
    
    log_success "Logged into Azure subscription: $account_name ($subscription_id)"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Python
    if ! command_exists python3; then
        log_error "Python 3 is not installed. Please install Python 3.11+ from https://www.python.org/"
        exit 1
    fi
    
    # Check Functions Core Tools
    if ! command_exists func; then
        log_error "Azure Functions Core Tools is not installed. Please install it from https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local"
        exit 1
    fi
    
    # Check pip
    if ! command_exists pip; then
        log_error "pip is not installed. Please install pip for Python package management."
        exit 1
    fi
    
    # Check OpenSSL for random generation
    if ! command_exists openssl; then
        log_error "OpenSSL is not installed. Please install OpenSSL for random string generation."
        exit 1
    fi
    
    validate_azure_login
    log_success "All prerequisites met"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
        export RANDOM_SUFFIX
    fi
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-ai-assistant-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    # Set resource names with unique suffix
    export OPENAI_ACCOUNT="${OPENAI_ACCOUNT:-openai-assistant-${RANDOM_SUFFIX}}"
    export FUNCTION_APP="${FUNCTION_APP:-func-assistant-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stassistant${RANDOM_SUFFIX}}"
    
    log_success "Environment variables configured:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  OpenAI Account: $OPENAI_ACCOUNT"
    log_info "  Function App: $FUNCTION_APP"
    log_info "  Storage Account: $STORAGE_ACCOUNT"
    log_info "  Random Suffix: $RANDOM_SUFFIX"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo \
            --output none
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "Storage account $STORAGE_ACCOUNT already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --output none
        
        log_success "Storage account created: $STORAGE_ACCOUNT"
    fi
    
    # Get storage connection string
    export STORAGE_CONNECTION_STRING
    STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    log_success "Storage connection string retrieved"
}

# Function to create Azure OpenAI account
create_openai_account() {
    log_info "Creating Azure OpenAI account: $OPENAI_ACCOUNT"
    
    if az cognitiveservices account show --name "$OPENAI_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "Azure OpenAI account $OPENAI_ACCOUNT already exists"
    else
        az cognitiveservices account create \
            --name "$OPENAI_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind OpenAI \
            --sku S0 \
            --yes \
            --output none
        
        log_success "Azure OpenAI account created: $OPENAI_ACCOUNT"
    fi
    
    # Get OpenAI endpoint and key
    export OPENAI_ENDPOINT
    OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "$OPENAI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    export OPENAI_KEY
    OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "$OPENAI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    log_success "Azure OpenAI account configured: $OPENAI_ENDPOINT"
}

# Function to deploy GPT-4 model
deploy_gpt4_model() {
    log_info "Deploying GPT-4 model for assistant"
    
    export MODEL_DEPLOYMENT="gpt-4-assistant"
    
    if az cognitiveservices account deployment show \
        --name "$OPENAI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "$MODEL_DEPLOYMENT" &>/dev/null; then
        log_warning "GPT-4 model deployment $MODEL_DEPLOYMENT already exists"
    else
        # Check available models and adjust version if needed
        local model_version="0613"
        
        log_info "Attempting to deploy GPT-4 model version $model_version"
        
        if ! az cognitiveservices account deployment create \
            --name "$OPENAI_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name "$MODEL_DEPLOYMENT" \
            --model-name gpt-4 \
            --model-version "$model_version" \
            --model-format OpenAI \
            --sku-capacity 10 \
            --sku-name Standard \
            --output none; then
            
            log_warning "Failed to deploy GPT-4 version $model_version, trying turbo variant..."
            
            # Try with gpt-4-turbo if regular gpt-4 fails
            az cognitiveservices account deployment create \
                --name "$OPENAI_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --deployment-name "$MODEL_DEPLOYMENT" \
                --model-name gpt-4-turbo \
                --model-version "2024-04-09" \
                --model-format OpenAI \
                --sku-capacity 10 \
                --sku-name Standard \
                --output none
        fi
        
        log_success "GPT-4 model deployed: $MODEL_DEPLOYMENT"
    fi
}

# Function to create function app
create_function_app() {
    log_info "Creating Azure Functions app: $FUNCTION_APP"
    
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "Function app $FUNCTION_APP already exists"
    else
        az functionapp create \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --consumption-plan-location "$LOCATION" \
            --runtime python \
            --runtime-version 3.11 \
            --functions-version 4 \
            --storage-account "$STORAGE_ACCOUNT" \
            --os-type Linux \
            --output none
        
        log_success "Function app created: $FUNCTION_APP"
    fi
    
    # Configure Function App settings
    log_info "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "OPENAI_ENDPOINT=$OPENAI_ENDPOINT" \
        "OPENAI_KEY=$OPENAI_KEY" \
        "STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING" \
        --output none
    
    log_success "Function App settings configured"
}

# Function to create storage containers
create_storage_containers() {
    log_info "Creating storage containers for conversation management"
    
    local containers=("conversations" "sessions" "assistant-data")
    
    for container in "${containers[@]}"; do
        if az storage container show \
            --name "$container" \
            --account-name "$STORAGE_ACCOUNT" \
            --connection-string "$STORAGE_CONNECTION_STRING" &>/dev/null; then
            log_warning "Container $container already exists"
        else
            az storage container create \
                --name "$container" \
                --account-name "$STORAGE_ACCOUNT" \
                --connection-string "$STORAGE_CONNECTION_STRING" \
                --output none
            
            log_success "Container created: $container"
        fi
    done
    
    log_success "Storage containers created for conversation management"
}

# Function to create and deploy Azure Functions
deploy_azure_functions() {
    log_info "Creating and deploying Azure Functions"
    
    local functions_dir="assistant-functions"
    
    # Create local function project directory
    if [[ -d "$functions_dir" ]]; then
        log_warning "Functions directory already exists, cleaning up..."
        rm -rf "$functions_dir"
    fi
    
    mkdir -p "$functions_dir"
    cd "$functions_dir"
    
    # Initialize Function project with Python
    log_info "Initializing Function project"
    func init . --python --output none
    
    # Create business logic function
    log_info "Creating GetCustomerInfo function"
    func new --name GetCustomerInfo --template "HTTP trigger" --output none
    
    # Create the customer info function code
    cat > GetCustomerInfo/__init__.py << 'EOF'
import logging
import json
import azure.functions as func
from datetime import datetime
import random

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Processing GetCustomerInfo request.')

    try:
        req_body = req.get_json()
        customer_id = req_body.get('customerId')
        include_history = req_body.get('includeHistory', False)
        
        if not customer_id:
            return func.HttpResponse(
                json.dumps({"success": False, "error": "customerId is required"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Simulate customer data retrieval
        customer_data = {
            "id": customer_id,
            "name": f"Customer {customer_id}",
            "status": "Active",
            "joinDate": "2023-01-15",
            "totalOrders": random.randint(1, 100),
            "recentActivity": [
                {"date": "2024-07-10", "action": "Order placed", "amount": "$150.00"},
                {"date": "2024-07-05", "action": "Account updated", "amount": None}
            ] if include_history else None
        }
        
        return func.HttpResponse(
            json.dumps({
                "success": True,
                "data": customer_data,
                "message": f"Retrieved information for customer {customer_id}"
            }),
            status_code=200,
            mimetype="application/json"
        )
    except Exception as e:
        logging.error(f"Error processing request: {str(e)}")
        return func.HttpResponse(
            json.dumps({"success": False, "error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )
EOF
    
    log_success "GetCustomerInfo function created"
    
    # Create analytics function
    log_info "Creating AnalyzeMetrics function"
    func new --name AnalyzeMetrics --template "HTTP trigger" --output none
    
    # Create analytics function code
    cat > AnalyzeMetrics/__init__.py << 'EOF'
import logging
import json
import azure.functions as func
import random

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Processing AnalyzeMetrics request.')

    try:
        req_body = req.get_json()
        metric = req_body.get('metric')
        timeframe = req_body.get('timeframe')
        filters = req_body.get('filters', {})
        
        if not metric or not timeframe:
            return func.HttpResponse(
                json.dumps({"success": False, "error": "metric and timeframe are required"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Simulate analytics data generation
        current_value = random.randint(1000, 10000)
        previous_value = random.randint(800, 8000)
        change_percent = round(((current_value - previous_value) / previous_value) * 100, 1)
        
        analytics_data = {
            "metric": metric,
            "timeframe": timeframe,
            "currentValue": current_value,
            "previousValue": previous_value,
            "changePercent": change_percent,
            "trend": "increasing" if change_percent > 0 else "decreasing",
            "insights": [
                f"{metric} shows {abs(change_percent)}% {'increase' if change_percent > 0 else 'decrease'} over {timeframe}",
                "Peak activity observed during business hours",
                "Recommend monitoring for continued trends"
            ],
            "recommendations": [
                "Continue current strategy for positive trends" if change_percent > 0 else "Implement optimization for declining metrics",
                "Set up automated alerts for significant changes"
            ]
        }
        
        return func.HttpResponse(
            json.dumps({
                "success": True,
                "data": analytics_data,
                "message": f"Analytics completed for {metric} over {timeframe}"
            }),
            status_code=200,
            mimetype="application/json"
        )
    except Exception as e:
        logging.error(f"Error processing request: {str(e)}")
        return func.HttpResponse(
            json.dumps({"success": False, "error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )
EOF
    
    log_success "AnalyzeMetrics function created"
    
    # Deploy functions to Azure
    log_info "Deploying functions to Azure (this may take several minutes)..."
    
    if ! func azure functionapp publish "$FUNCTION_APP" --output none; then
        log_error "Failed to deploy functions to Azure"
        cd ..
        exit 1
    fi
    
    log_success "Functions deployed successfully"
    
    # Get function URLs for assistant configuration
    log_info "Retrieving function URLs..."
    
    # Wait a moment for functions to be fully deployed
    sleep 10
    
    export CUSTOMER_FUNCTION_URL
    CUSTOMER_FUNCTION_URL=$(func azure functionapp list-functions "$FUNCTION_APP" --show-keys 2>/dev/null | grep -A 1 "GetCustomerInfo" | grep "Invoke url" | awk '{print $3}' || true)
    
    export ANALYTICS_FUNCTION_URL
    ANALYTICS_FUNCTION_URL=$(func azure functionapp list-functions "$FUNCTION_APP" --show-keys 2>/dev/null | grep -A 1 "AnalyzeMetrics" | grep "Invoke url" | awk '{print $3}' || true)
    
    if [[ -z "$CUSTOMER_FUNCTION_URL" || -z "$ANALYTICS_FUNCTION_URL" ]]; then
        log_warning "Could not retrieve function URLs automatically, trying alternative method..."
        
        # Alternative method using az CLI
        local function_app_hostname
        function_app_hostname=$(az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --query defaultHostName --output tsv)
        
        # Get function key
        local function_key
        function_key=$(az functionapp keys list --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --query "functionKeys.default" --output tsv 2>/dev/null || \
                      az functionapp function keys list --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --function-name "GetCustomerInfo" --query "default" --output tsv 2>/dev/null || \
                      "")
        
        if [[ -n "$function_key" ]]; then
            export CUSTOMER_FUNCTION_URL="https://${function_app_hostname}/api/GetCustomerInfo?code=${function_key}"
            export ANALYTICS_FUNCTION_URL="https://${function_app_hostname}/api/AnalyzeMetrics?code=${function_key}"
        else
            log_warning "Could not retrieve function keys automatically"
            export CUSTOMER_FUNCTION_URL="https://${function_app_hostname}/api/GetCustomerInfo"
            export ANALYTICS_FUNCTION_URL="https://${function_app_hostname}/api/AnalyzeMetrics"
        fi
    fi
    
    log_success "Function URLs configured"
    log_info "  Customer Function: $CUSTOMER_FUNCTION_URL"
    log_info "  Analytics Function: $ANALYTICS_FUNCTION_URL"
    
    cd ..
}

# Function to install Python dependencies
install_python_dependencies() {
    log_info "Installing required Python packages..."
    
    # Install packages with error handling
    if ! pip install openai azure-storage-blob requests --quiet; then
        log_warning "Failed to install some packages via pip, trying with --user flag"
        pip install openai azure-storage-blob requests --user --quiet
    fi
    
    log_success "Python dependencies installed"
}

# Function to create AI assistant
create_ai_assistant() {
    log_info "Creating AI Assistant with custom functions"
    
    install_python_dependencies
    
    # Create assistant configuration script
    cat > create-assistant.py << 'EOF'
import os
import json
import sys
from openai import AzureOpenAI

try:
    # Initialize Azure OpenAI client
    client = AzureOpenAI(
        api_key=os.getenv("OPENAI_KEY"),
        api_version="2024-02-15-preview",
        azure_endpoint=os.getenv("OPENAI_ENDPOINT")
    )

    # Define custom function schemas
    customer_function = {
        "type": "function",
        "function": {
            "name": "get_customer_info",
            "description": "Retrieve customer information and order history",
            "parameters": {
                "type": "object",
                "properties": {
                    "customerId": {
                        "type": "string",
                        "description": "The unique customer identifier"
                    },
                    "includeHistory": {
                        "type": "boolean",
                        "description": "Whether to include recent activity history"
                    }
                },
                "required": ["customerId"]
            }
        }
    }

    analytics_function = {
        "type": "function", 
        "function": {
            "name": "analyze_metrics",
            "description": "Analyze business metrics and provide insights",
            "parameters": {
                "type": "object",
                "properties": {
                    "metric": {
                        "type": "string",
                        "description": "The metric to analyze (e.g., 'sales', 'traffic', 'conversion')"
                    },
                    "timeframe": {
                        "type": "string",
                        "description": "Time period for analysis (e.g., 'last_week', 'last_month')"
                    },
                    "filters": {
                        "type": "object",
                        "description": "Optional filters for the analysis"
                    }
                },
                "required": ["metric", "timeframe"]
            }
        }
    }

    # Create assistant
    assistant = client.beta.assistants.create(
        name="Business Intelligence Assistant",
        instructions="""You are a helpful business intelligence assistant that can access 
        customer information and perform analytics. Use the available functions to retrieve 
        data and provide insights. Always explain your findings clearly and offer actionable 
        recommendations based on the data you receive.""",
        model="gpt-4-assistant",
        tools=[customer_function, analytics_function]
    )

    print(f"Assistant created with ID: {assistant.id}")
    with open("assistant_id.txt", "w") as f:
        f.write(assistant.id)
        
except Exception as e:
    print(f"Error creating assistant: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    
    # Run assistant creation
    if ! python3 create-assistant.py; then
        log_error "Failed to create AI Assistant"
        exit 1
    fi
    
    if [[ -f "assistant_id.txt" ]]; then
        export ASSISTANT_ID
        ASSISTANT_ID=$(cat assistant_id.txt)
        log_success "AI Assistant created with custom functions: $ASSISTANT_ID"
    else
        log_error "Assistant ID file not found after creation"
        exit 1
    fi
}

# Function to create conversation management system
create_conversation_manager() {
    log_info "Creating conversation management system"
    
    # Create conversation manager script
    cat > conversation-manager.py << 'EOF'
import os
import json
import requests
import sys
from datetime import datetime
from openai import AzureOpenAI
from azure.storage.blob import BlobServiceClient
import time

class ConversationManager:
    def __init__(self):
        try:
            self.client = AzureOpenAI(
                api_key=os.getenv("OPENAI_KEY"),
                api_version="2024-02-15-preview",
                azure_endpoint=os.getenv("OPENAI_ENDPOINT")
            )
            self.assistant_id = os.getenv("ASSISTANT_ID")
            self.storage_client = BlobServiceClient.from_connection_string(
                os.getenv("STORAGE_CONNECTION_STRING")
            )
        except Exception as e:
            print(f"Error initializing ConversationManager: {e}", file=sys.stderr)
            sys.exit(1)
        
    def create_thread(self):
        try:
            thread = self.client.beta.threads.create()
            return thread.id
        except Exception as e:
            print(f"Error creating thread: {e}", file=sys.stderr)
            return None
        
    def save_conversation(self, thread_id, message, response):
        try:
            container_client = self.storage_client.get_container_client("conversations")
            conversation_data = {
                "thread_id": thread_id,
                "message": message,
                "response": response,
                "timestamp": datetime.utcnow().isoformat()
            }
            
            blob_name = f"{thread_id}/{datetime.utcnow().isoformat()}.json"
            container_client.upload_blob(
                name=blob_name,
                data=json.dumps(conversation_data),
                overwrite=True
            )
        except Exception as e:
            print(f"Error saving conversation: {e}", file=sys.stderr)
    
    def execute_function_call(self, function_name, arguments):
        function_urls = {
            "get_customer_info": os.getenv("CUSTOMER_FUNCTION_URL"),
            "analyze_metrics": os.getenv("ANALYTICS_FUNCTION_URL")
        }
        
        if function_name in function_urls:
            try:
                response = requests.post(
                    function_urls[function_name],
                    json=json.loads(arguments),
                    headers={"Content-Type": "application/json"},
                    timeout=30
                )
                return response.json()
            except Exception as e:
                return {"error": f"Function execution failed: {str(e)}"}
        else:
            return {"error": f"Unknown function: {function_name}"}
    
    def process_message(self, thread_id, message):
        try:
            # Add message to thread
            self.client.beta.threads.messages.create(
                thread_id=thread_id,
                role="user",
                content=message
            )
            
            # Create and execute run
            run = self.client.beta.threads.runs.create(
                thread_id=thread_id,
                assistant_id=self.assistant_id
            )
            
            # Handle function calls with timeout protection
            max_wait_time = 300  # 5 minutes
            start_time = time.time()
            
            while run.status in ["queued", "in_progress", "requires_action"]:
                if time.time() - start_time > max_wait_time:
                    print("Run timed out")
                    break
                    
                if run.status == "requires_action":
                    tool_calls = run.required_action.submit_tool_outputs.tool_calls
                    tool_outputs = []
                    
                    for tool_call in tool_calls:
                        function_name = tool_call.function.name
                        arguments = tool_call.function.arguments
                        
                        result = self.execute_function_call(function_name, arguments)
                        tool_outputs.append({
                            "tool_call_id": tool_call.id,
                            "output": json.dumps(result)
                        })
                    
                    run = self.client.beta.threads.runs.submit_tool_outputs(
                        thread_id=thread_id,
                        run_id=run.id,
                        tool_outputs=tool_outputs
                    )
                else:
                    run = self.client.beta.threads.runs.retrieve(
                        thread_id=thread_id,
                        run_id=run.id
                    )
                    time.sleep(1)  # Wait before checking again
            
            # Get assistant response
            messages = self.client.beta.threads.messages.list(thread_id=thread_id)
            response = messages.data[0].content[0].text.value
            
            # Save conversation
            self.save_conversation(thread_id, message, response)
            
            return response
        except Exception as e:
            print(f"Error processing message: {e}", file=sys.stderr)
            return f"Error: {str(e)}"

# Example usage for testing
if __name__ == "__main__":
    try:
        manager = ConversationManager()
        thread_id = manager.create_thread()
        
        if thread_id:
            response = manager.process_message(
                thread_id, 
                "Can you get information for customer ID CUST001 and analyze our sales metrics for last month?"
            )
            
            print(f"Assistant Response: {response}")
        else:
            print("Failed to create conversation thread", file=sys.stderr)
            sys.exit(1)
    except Exception as e:
        print(f"Error running conversation manager: {e}", file=sys.stderr)
        sys.exit(1)
EOF
    
    log_success "Conversation management system created"
}

# Function to run validation tests
run_validation_tests() {
    log_info "Running validation tests..."
    
    # Test 1: Verify AI Assistant Function Registration
    log_info "Testing AI Assistant function registration..."
    
    python3 -c "
import os
import sys
from openai import AzureOpenAI

try:
    client = AzureOpenAI(
        api_key=os.environ['OPENAI_KEY'],
        api_version='2024-02-15-preview',
        azure_endpoint=os.environ['OPENAI_ENDPOINT']
    )
    
    assistant = client.beta.assistants.retrieve(os.environ['ASSISTANT_ID'])
    print(f'Assistant: {assistant.name}')
    print(f'Tools: {len(assistant.tools)} functions registered')
    for tool in assistant.tools:
        if tool.type == 'function':
            print(f'  - {tool.function.name}: {tool.function.description}')
except Exception as e:
    print(f'Error testing assistant: {e}', file=sys.stderr)
    sys.exit(1)
" || log_warning "Assistant function registration test failed"
    
    # Test 2: Test Custom Function Endpoints
    log_info "Testing custom function endpoints..."
    
    if command_exists curl; then
        # Test customer function
        if curl -s -X POST "$CUSTOMER_FUNCTION_URL" \
            -H "Content-Type: application/json" \
            -d '{"customerId": "CUST001", "includeHistory": true}' | grep -q "success"; then
            log_success "Customer function endpoint test passed"
        else
            log_warning "Customer function endpoint test failed"
        fi
        
        # Test analytics function  
        if curl -s -X POST "$ANALYTICS_FUNCTION_URL" \
            -H "Content-Type: application/json" \
            -d '{"metric": "sales", "timeframe": "last_month"}' | grep -q "success"; then
            log_success "Analytics function endpoint test passed"
        else
            log_warning "Analytics function endpoint test failed"
        fi
    else
        log_warning "curl not available, skipping function endpoint tests"
    fi
    
    # Test 3: Verify Storage Integration
    log_info "Testing storage integration..."
    
    if az storage blob list \
        --container-name conversations \
        --account-name "$STORAGE_ACCOUNT" \
        --connection-string "$STORAGE_CONNECTION_STRING" \
        --output none &>/dev/null; then
        log_success "Storage integration test passed"
    else
        log_warning "Storage integration test failed"
    fi
    
    log_success "Validation tests completed"
}

# Function to save deployment configuration
save_deployment_config() {
    log_info "Saving deployment configuration..."
    
    cat > deployment-config.env << EOF
# Azure AI Assistant Deployment Configuration
# Generated on $(date)

export RESOURCE_GROUP="$RESOURCE_GROUP"
export LOCATION="$LOCATION"
export SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"

export OPENAI_ACCOUNT="$OPENAI_ACCOUNT"
export FUNCTION_APP="$FUNCTION_APP"
export STORAGE_ACCOUNT="$STORAGE_ACCOUNT"

export OPENAI_ENDPOINT="$OPENAI_ENDPOINT"
export OPENAI_KEY="$OPENAI_KEY"
export STORAGE_CONNECTION_STRING="$STORAGE_CONNECTION_STRING"

export MODEL_DEPLOYMENT="$MODEL_DEPLOYMENT"
export ASSISTANT_ID="$ASSISTANT_ID"

export CUSTOMER_FUNCTION_URL="$CUSTOMER_FUNCTION_URL"
export ANALYTICS_FUNCTION_URL="$ANALYTICS_FUNCTION_URL"
EOF
    
    log_success "Deployment configuration saved to deployment-config.env"
    log_info "You can source this file to restore environment variables: source deployment-config.env"
}

# Function to display deployment summary
display_deployment_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    log_info "Resource Summary:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Azure OpenAI Account: $OPENAI_ACCOUNT"
    log_info "  Function App: $FUNCTION_APP"
    log_info "  Storage Account: $STORAGE_ACCOUNT"
    echo
    log_info "AI Assistant:"
    log_info "  Assistant ID: $ASSISTANT_ID"
    log_info "  Model Deployment: $MODEL_DEPLOYMENT"
    echo
    log_info "Function URLs:"
    log_info "  Customer Function: $CUSTOMER_FUNCTION_URL"
    log_info "  Analytics Function: $ANALYTICS_FUNCTION_URL"
    echo
    log_info "Next Steps:"
    log_info "1. Test the conversation manager: python3 conversation-manager.py"
    log_info "2. Integrate the assistant into your applications"
    log_info "3. Monitor function performance in Azure portal"
    log_info "4. Review conversation logs in Azure Storage"
    echo
    log_warning "Important: Remember to run destroy.sh when you're done to avoid ongoing charges"
    echo
    log_info "Configuration saved to: deployment-config.env"
    log_info "To restore environment variables later: source deployment-config.env"
}

# Main deployment function
main() {
    echo "=========================================="
    echo "Azure AI Assistant Deployment Script"
    echo "=========================================="
    echo
    
    # Check if running in dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log_info "Running in dry-run mode - no resources will be created"
        export DRY_RUN=true
    fi
    
    # Deployment steps
    check_prerequisites
    setup_environment
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "Dry-run mode: Would create the following resources:"
        log_info "  Resource Group: $RESOURCE_GROUP"
        log_info "  Azure OpenAI Account: $OPENAI_ACCOUNT"
        log_info "  Function App: $FUNCTION_APP"
        log_info "  Storage Account: $STORAGE_ACCOUNT"
        log_info "Dry-run completed successfully"
        return 0
    fi
    
    create_resource_group
    create_storage_account
    create_openai_account
    deploy_gpt4_model
    create_function_app
    create_storage_containers
    deploy_azure_functions
    create_ai_assistant
    create_conversation_manager
    run_validation_tests
    save_deployment_config
    display_deployment_summary
    
    log_success "Azure AI Assistant deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Deployment interrupted"; exit 130' INT TERM

# Run main function
main "$@"