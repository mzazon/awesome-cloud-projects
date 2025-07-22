#!/bin/bash

# Deploy script for Orchestrating Intelligent Business Process Automation 
# with Azure OpenAI Assistants and Azure Container Apps Jobs
# 
# This script deploys the complete infrastructure for intelligent business
# process automation using Azure OpenAI Assistants and Container Apps Jobs

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "$ERROR_LOG" >&2
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "Script failed with exit code $exit_code at line $line_number"
    log_error "Check the error log at $ERROR_LOG for details"
    echo -e "${RED}❌ Deployment failed. Check logs for details.${NC}"
    exit $exit_code
}

trap 'handle_error $? $LINENO' ERR

# Cleanup function for partial deployments
cleanup_on_failure() {
    log_warning "Cleaning up partial deployment..."
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true
    fi
}

# Prerequisites checking
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if subscription is set
    local subscription_id
    subscription_id=$(az account show --query id -o tsv)
    log_info "Using Azure subscription: $subscription_id"
    
    # Check required permissions (simplified check)
    if ! az provider show --namespace Microsoft.CognitiveServices &> /dev/null; then
        log_error "Microsoft.CognitiveServices provider not available. Please check permissions."
        exit 1
    fi
    
    # Check for required tools
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random values."
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_warning "python3 not found. Assistant creation may require manual setup."
    fi
    
    log_success "Prerequisites check completed"
}

# Environment variable setup
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Core resource configuration
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-intelligent-automation}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    local random_suffix
    random_suffix=$(openssl rand -hex 3)
    export UNIQUE_SUFFIX="${UNIQUE_SUFFIX:-$random_suffix}"
    
    # Resource names with unique identifiers
    export OPENAI_ACCOUNT_NAME="openai-automation-${UNIQUE_SUFFIX}"
    export SERVICEBUS_NAMESPACE="sb-automation-${UNIQUE_SUFFIX}"
    export CONTAINER_ENV="aca-env-${UNIQUE_SUFFIX}"
    export LOG_ANALYTICS_WORKSPACE="law-automation-${UNIQUE_SUFFIX}"
    export CONTAINER_REGISTRY="acr${UNIQUE_SUFFIX}"
    
    log_info "Resource group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Unique suffix: $UNIQUE_SUFFIX"
    
    # Save environment variables for later use
    cat > "${SCRIPT_DIR}/.env" << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
UNIQUE_SUFFIX=$UNIQUE_SUFFIX
OPENAI_ACCOUNT_NAME=$OPENAI_ACCOUNT_NAME
SERVICEBUS_NAMESPACE=$SERVICEBUS_NAMESPACE
CONTAINER_ENV=$CONTAINER_ENV
LOG_ANALYTICS_WORKSPACE=$LOG_ANALYTICS_WORKSPACE
CONTAINER_REGISTRY=$CONTAINER_REGISTRY
EOF
    
    log_success "Environment variables configured"
}

# Resource group creation
create_resource_group() {
    log_info "Creating resource group..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=intelligent-automation environment=demo \
            --output none
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Log Analytics workspace creation
create_log_analytics() {
    log_info "Creating Log Analytics workspace..."
    
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --location "$LOCATION" \
        --output none
    
    log_success "Log Analytics workspace created: $LOG_ANALYTICS_WORKSPACE"
}

# Azure OpenAI Service creation
create_openai_service() {
    log_info "Creating Azure OpenAI Service..."
    
    # Create Azure OpenAI account
    az cognitiveservices account create \
        --name "$OPENAI_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind OpenAI \
        --sku S0 \
        --custom-domain "$OPENAI_ACCOUNT_NAME" \
        --tags purpose=intelligent-automation \
        --output none
    
    log_success "Azure OpenAI account created: $OPENAI_ACCOUNT_NAME"
    
    # Wait for account to be ready
    log_info "Waiting for OpenAI account to be ready..."
    sleep 30
    
    # Deploy GPT-4 model
    log_info "Deploying GPT-4 model..."
    az cognitiveservices account deployment create \
        --name "$OPENAI_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name gpt-4 \
        --model-name gpt-4 \
        --model-version "0613" \
        --model-format OpenAI \
        --scale-settings-scale-type Standard \
        --output none
    
    log_success "GPT-4 model deployed"
    
    # Get OpenAI endpoint and key
    export OPENAI_ENDPOINT
    OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "$OPENAI_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint \
        --output tsv)
    
    export OPENAI_KEY
    OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "$OPENAI_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 \
        --output tsv)
    
    # Save credentials securely
    echo "OPENAI_ENDPOINT=$OPENAI_ENDPOINT" >> "${SCRIPT_DIR}/.env"
    echo "OPENAI_KEY=$OPENAI_KEY" >> "${SCRIPT_DIR}/.env"
    
    log_success "Azure OpenAI Service configuration completed"
}

# Service Bus creation
create_service_bus() {
    log_info "Creating Service Bus namespace and messaging resources..."
    
    # Create Service Bus namespace
    az servicebus namespace create \
        --name "$SERVICEBUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard \
        --output none
    
    log_success "Service Bus namespace created: $SERVICEBUS_NAMESPACE"
    
    # Create processing queue
    az servicebus queue create \
        --name processing-queue \
        --namespace-name "$SERVICEBUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --max-size 1024 \
        --default-message-time-to-live PT10M \
        --output none
    
    log_success "Processing queue created"
    
    # Create results topic
    az servicebus topic create \
        --name processing-results \
        --namespace-name "$SERVICEBUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --max-size 1024 \
        --output none
    
    log_success "Results topic created"
    
    # Create subscription for notifications
    az servicebus topic subscription create \
        --name notification-sub \
        --topic-name processing-results \
        --namespace-name "$SERVICEBUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --output none
    
    log_success "Notification subscription created"
    
    # Get Service Bus connection string
    export SERVICEBUS_CONNECTION
    SERVICEBUS_CONNECTION=$(az servicebus namespace authorization-rule keys list \
        --resource-group "$RESOURCE_GROUP" \
        --namespace-name "$SERVICEBUS_NAMESPACE" \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString \
        --output tsv)
    
    echo "SERVICEBUS_CONNECTION=$SERVICEBUS_CONNECTION" >> "${SCRIPT_DIR}/.env"
    
    log_success "Service Bus configuration completed"
}

# Container Registry creation
create_container_registry() {
    log_info "Creating Azure Container Registry..."
    
    az acr create \
        --name "$CONTAINER_REGISTRY" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Basic \
        --admin-enabled true \
        --output none
    
    log_success "Container Registry created: $CONTAINER_REGISTRY"
    
    # Get ACR login server
    export ACR_LOGIN_SERVER
    ACR_LOGIN_SERVER=$(az acr show \
        --name "$CONTAINER_REGISTRY" \
        --resource-group "$RESOURCE_GROUP" \
        --query loginServer \
        --output tsv)
    
    echo "ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER" >> "${SCRIPT_DIR}/.env"
    
    log_success "Container Registry configuration completed"
}

# Container Apps Environment creation
create_container_environment() {
    log_info "Creating Container Apps environment..."
    
    # Get Log Analytics workspace details
    local workspace_id
    workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query customerId \
        --output tsv)
    
    local workspace_key
    workspace_key=$(az monitor log-analytics workspace get-shared-keys \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query primarySharedKey \
        --output tsv)
    
    # Create Container Apps environment
    az containerapp env create \
        --name "$CONTAINER_ENV" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --logs-workspace-id "$workspace_id" \
        --logs-workspace-key "$workspace_key" \
        --output none
    
    log_success "Container Apps environment created: $CONTAINER_ENV"
}

# Build and deploy container images
build_container_images() {
    log_info "Building and deploying container images..."
    
    # Create temporary directory for build context
    local build_dir
    build_dir=$(mktemp -d)
    cd "$build_dir"
    
    # Create processing job Dockerfile
    cat > processing-job.dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install required packages
RUN pip install azure-servicebus azure-identity requests pandas

# Copy application code
COPY process_documents.py .

# Set environment variables
ENV PYTHONUNBUFFERED=1

# Run the processing job
CMD ["python", "process_documents.py"]
EOF

    # Create Python processing script
    cat > process_documents.py << 'EOF'
import os
import json
import time
import logging
from azure.servicebus import ServiceBusClient
from azure.identity import DefaultAzureCredential
import requests

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_document(message_data):
    """Process document using AI analysis"""
    try:
        # Extract document information
        doc_info = json.loads(message_data)
        logger.info(f"Processing document: {doc_info.get('document_id')}")
        
        # Simulate document processing
        time.sleep(2)
        
        # Create processing result
        result = {
            "document_id": doc_info.get("document_id"),
            "processed_at": time.time(),
            "status": "completed",
            "insights": {
                "key_points": ["Important finding 1", "Important finding 2"],
                "recommendations": ["Action 1", "Action 2"]
            }
        }
        
        return result
        
    except Exception as e:
        logger.error(f"Error processing document: {str(e)}")
        raise

def main():
    # Get connection string from environment
    connection_string = os.getenv('SERVICEBUS_CONNECTION')
    
    if not connection_string:
        logger.error("Service Bus connection string not found")
        return
        
    # Create Service Bus client
    servicebus_client = ServiceBusClient.from_connection_string(connection_string)
    
    try:
        # Receive from processing queue
        with servicebus_client:
            receiver = servicebus_client.get_queue_receiver(queue_name="processing-queue")
            sender = servicebus_client.get_topic_sender(topic_name="processing-results")
            
            with receiver, sender:
                # Process single message (Container Apps Jobs handle one message per execution)
                received_msgs = receiver.receive_messages(max_message_count=1, max_wait_time=30)
                
                for msg in received_msgs:
                    try:
                        logger.info(f"Processing message: {msg.message_id}")
                        
                        # Process the document
                        result = process_document(str(msg))
                        
                        # Send result to topic
                        result_message = json.dumps(result)
                        sender.send_messages(result_message)
                        
                        # Complete the message
                        receiver.complete_message(msg)
                        logger.info(f"Message {msg.message_id} processed successfully")
                        
                    except Exception as e:
                        logger.error(f"Error processing message {msg.message_id}: {str(e)}")
                        receiver.abandon_message(msg)
                        
    except Exception as e:
        logger.error(f"Service Bus error: {str(e)}")

if __name__ == "__main__":
    main()
EOF

    # Build and push container image
    az acr build \
        --registry "$CONTAINER_REGISTRY" \
        --image processing-job:latest \
        --file processing-job.dockerfile . \
        --output none
    
    log_success "Container image built and pushed to registry"
    
    # Cleanup build directory
    cd "$SCRIPT_DIR"
    rm -rf "$build_dir"
}

# Deploy Container Apps Jobs
deploy_container_jobs() {
    log_info "Deploying Container Apps Jobs..."
    
    # Create document processing job
    az containerapp job create \
        --name document-processor \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CONTAINER_ENV" \
        --image "${ACR_LOGIN_SERVER}/processing-job:latest" \
        --registry-server "$ACR_LOGIN_SERVER" \
        --registry-identity system \
        --trigger-type Event \
        --replica-timeout 300 \
        --parallelism 3 \
        --replica-retry-limit 2 \
        --scale-rule-name servicebus-scale \
        --scale-rule-type azure-servicebus \
        --scale-rule-metadata \
            connectionFromEnv=SERVICEBUS_CONNECTION \
            queueName=processing-queue \
            messageCount=1 \
        --env-vars \
            SERVICEBUS_CONNECTION=secretref:servicebus-connection \
        --secrets \
            servicebus-connection="$SERVICEBUS_CONNECTION" \
        --output none
    
    log_success "Document processor job created"
    
    # Create notification service job
    az containerapp job create \
        --name notification-service \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CONTAINER_ENV" \
        --image "${ACR_LOGIN_SERVER}/processing-job:latest" \
        --registry-server "$ACR_LOGIN_SERVER" \
        --registry-identity system \
        --trigger-type Event \
        --replica-timeout 120 \
        --parallelism 2 \
        --scale-rule-name servicebus-topic-scale \
        --scale-rule-type azure-servicebus \
        --scale-rule-metadata \
            connectionFromEnv=SERVICEBUS_CONNECTION \
            topicName=processing-results \
            subscriptionName=notification-sub \
            messageCount=1 \
        --env-vars \
            SERVICEBUS_CONNECTION=secretref:servicebus-connection \
        --secrets \
            servicebus-connection="$SERVICEBUS_CONNECTION" \
        --output none
    
    log_success "Notification service job created"
    
    log_success "Container Apps Jobs deployed with event-driven scaling"
}

# Create OpenAI Assistant
create_openai_assistant() {
    log_info "Creating Azure OpenAI Assistant..."
    
    if ! command -v python3 &> /dev/null; then
        log_warning "Python3 not available. Skipping assistant creation."
        log_info "Please manually create the assistant using the Azure OpenAI Studio or REST API."
        return
    fi
    
    # Create assistant creation script
    cat > "${SCRIPT_DIR}/create_assistant.py" << EOF
import os
import json
import requests
import time

# Configuration
OPENAI_ENDPOINT = os.getenv('OPENAI_ENDPOINT')
OPENAI_KEY = os.getenv('OPENAI_KEY')

def create_assistant():
    """Create Azure OpenAI Assistant for document processing"""
    
    headers = {
        'Content-Type': 'application/json',
        'api-key': OPENAI_KEY
    }
    
    assistant_config = {
        "model": "gpt-4",
        "name": "Document Processing Assistant",
        "description": "Intelligent assistant for business document processing and workflow automation",
        "instructions": """You are an intelligent business process automation assistant. Your role is to:
        
        1. Analyze documents and extract key business information
        2. Identify processing requirements and priority levels
        3. Make decisions about workflow routing and processing steps
        4. Generate structured output for downstream systems
        5. Provide recommendations for process improvements
        
        When processing documents, focus on:
        - Extracting actionable insights
        - Identifying compliance requirements
        - Determining processing priority
        - Suggesting automation opportunities
        
        Always provide structured JSON output for system integration.""",
        "tools": [
            {
                "type": "function",
                "function": {
                    "name": "queue_processing_task",
                    "description": "Queue a document processing task",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "document_id": {"type": "string"},
                            "processing_type": {"type": "string"},
                            "priority": {"type": "string"},
                            "metadata": {"type": "object"}
                        },
                        "required": ["document_id", "processing_type"]
                    }
                }
            }
        ]
    }
    
    url = f"{OPENAI_ENDPOINT}/openai/assistants?api-version=2024-02-15-preview"
    
    response = requests.post(url, headers=headers, json=assistant_config)
    
    if response.status_code == 200:
        assistant = response.json()
        print(f"Assistant created with ID: {assistant['id']}")
        return assistant['id']
    else:
        print(f"Error creating assistant: {response.text}")
        return None

if __name__ == "__main__":
    assistant_id = create_assistant()
    if assistant_id:
        with open('assistant_id.txt', 'w') as f:
            f.write(assistant_id)
        print(f"Assistant ID saved to assistant_id.txt")
EOF

    # Run assistant creation
    cd "$SCRIPT_DIR"
    python3 create_assistant.py
    
    if [[ -f "assistant_id.txt" ]]; then
        local assistant_id
        assistant_id=$(cat assistant_id.txt)
        echo "OPENAI_ASSISTANT_ID=$assistant_id" >> .env
        log_success "Azure OpenAI Assistant created with ID: $assistant_id"
    else
        log_warning "Assistant creation may have failed. Check create_assistant.py output."
    fi
}

# Configure monitoring
configure_monitoring() {
    log_info "Configuring monitoring and observability..."
    
    # Create Application Insights
    az monitor app-insights component create \
        --app "${OPENAI_ACCOUNT_NAME}-insights" \
        --location "$LOCATION" \
        --resource-group "$RESOURCE_GROUP" \
        --workspace "$(az monitor log-analytics workspace show \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --query id \
            --output tsv)" \
        --output none
    
    log_success "Application Insights created"
    
    # Create alert for high OpenAI API usage
    local openai_resource_id
    openai_resource_id=$(az cognitiveservices account show \
        --name "$OPENAI_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id \
        --output tsv)
    
    az monitor metrics alert create \
        --name "High OpenAI API Usage" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "$openai_resource_id" \
        --condition "avg ProcessedTokens > 10000" \
        --description "Alert when OpenAI API usage is high" \
        --output none || log_warning "Could not create OpenAI usage alert"
    
    log_success "Monitoring and alerting configured"
}

# Main deployment function
main() {
    echo -e "${BLUE}🚀 Starting deployment of Intelligent Business Process Automation${NC}"
    echo "============================================================================="
    
    # Initialize log files
    > "$LOG_FILE"
    > "$ERROR_LOG"
    
    log_info "Deployment started at $(date)"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_resource_group
    create_log_analytics
    create_openai_service
    create_service_bus
    create_container_registry
    create_container_environment
    build_container_images
    deploy_container_jobs
    create_openai_assistant
    configure_monitoring
    
    echo "============================================================================="
    log_success "Deployment completed successfully!"
    echo -e "${GREEN}✅ All resources have been deployed${NC}"
    echo ""
    echo -e "${BLUE}📋 Deployment Summary:${NC}"
    echo "  • Resource Group: $RESOURCE_GROUP"
    echo "  • Azure OpenAI: $OPENAI_ACCOUNT_NAME"
    echo "  • Service Bus: $SERVICEBUS_NAMESPACE"
    echo "  • Container Registry: $CONTAINER_REGISTRY"
    echo "  • Container Environment: $CONTAINER_ENV"
    echo ""
    echo -e "${BLUE}📁 Configuration saved to: ${SCRIPT_DIR}/.env${NC}"
    echo -e "${BLUE}📊 View logs at: $LOG_FILE${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Remember to run the validation tests and cleanup when done!${NC}"
}

# Run main function
main "$@"