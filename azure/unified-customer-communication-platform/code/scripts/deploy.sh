#!/bin/bash

# Azure Multi-Channel Customer Communication Platform - Deployment Script
# This script deploys a complete communication platform using Azure Communication Services,
# Event Grid, Functions, and Cosmos DB for multi-channel customer messaging

set -e  # Exit on any error
set -o pipefail  # Exit if any command in pipeline fails

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Required for generating random suffixes."
        exit 1
    fi
    
    # Check if zip is available for function deployment
    if ! command -v zip &> /dev/null; then
        error "zip is not installed. Required for Azure Functions deployment."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Default values
    export RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-multi-channel-comms"}
    export LOCATION=${LOCATION:-"eastus"}
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export COMM_SERVICE_NAME="acs-platform-${RANDOM_SUFFIX}"
    export EVENTGRID_TOPIC_NAME="eg-comms-events-${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="func-comms-processor-${RANDOM_SUFFIX}"
    export COSMOS_ACCOUNT_NAME="cosmos-comms-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stacomms${RANDOM_SUFFIX}"
    
    log "Environment variables configured:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Location: ${LOCATION}"
    log "  Communication Services: ${COMM_SERVICE_NAME}"
    log "  Event Grid Topic: ${EVENTGRID_TOPIC_NAME}"
    log "  Function App: ${FUNCTION_APP_NAME}"
    log "  Cosmos DB: ${COSMOS_ACCOUNT_NAME}"
    log "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --tags purpose=multi-channel-comms environment=development \
            --output none
        
        success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create Azure Communication Services
create_communication_services() {
    log "Creating Azure Communication Services resource..."
    
    # Check if resource exists
    if az communication show --name ${COMM_SERVICE_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        warning "Communication Services ${COMM_SERVICE_NAME} already exists"
    else
        az communication create \
            --name ${COMM_SERVICE_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --data-location "UnitedStates" \
            --output none
        
        success "Communication Services resource created: ${COMM_SERVICE_NAME}"
    fi
    
    # Get connection string
    export COMM_CONNECTION_STRING=$(az communication list-key \
        --name ${COMM_SERVICE_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query primaryConnectionString \
        --output tsv)
    
    if [ -z "$COMM_CONNECTION_STRING" ]; then
        error "Failed to retrieve Communication Services connection string"
        exit 1
    fi
    
    log "Communication Services connection string retrieved"
}

# Function to create Cosmos DB
create_cosmos_db() {
    log "Creating Cosmos DB account and collections..."
    
    # Check if account exists
    if az cosmosdb show --name ${COSMOS_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        warning "Cosmos DB account ${COSMOS_ACCOUNT_NAME} already exists"
    else
        az cosmosdb create \
            --name ${COSMOS_ACCOUNT_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --default-consistency-level "Session" \
            --locations regionName=${LOCATION} failoverPriority=0 \
            --output none
        
        success "Cosmos DB account created: ${COSMOS_ACCOUNT_NAME}"
    fi
    
    # Create database
    if az cosmosdb sql database show --account-name ${COSMOS_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} --name "CommunicationPlatform" &> /dev/null; then
        warning "Database CommunicationPlatform already exists"
    else
        az cosmosdb sql database create \
            --account-name ${COSMOS_ACCOUNT_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --name "CommunicationPlatform" \
            --output none
        
        success "Database CommunicationPlatform created"
    fi
    
    # Create containers
    for container in "Conversations" "Messages"; do
        local partition_key="/customerId"
        if [ "$container" = "Messages" ]; then
            partition_key="/conversationId"
        fi
        
        if az cosmosdb sql container show --account-name ${COSMOS_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} --database-name "CommunicationPlatform" --name "$container" &> /dev/null; then
            warning "Container $container already exists"
        else
            az cosmosdb sql container create \
                --account-name ${COSMOS_ACCOUNT_NAME} \
                --resource-group ${RESOURCE_GROUP} \
                --database-name "CommunicationPlatform" \
                --name "$container" \
                --partition-key-path "$partition_key" \
                --output none
            
            success "Container $container created"
        fi
    done
    
    # Get connection string
    export COSMOS_CONNECTION_STRING=$(az cosmosdb keys list \
        --name ${COSMOS_ACCOUNT_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --type connection-strings \
        --query "connectionStrings[0].connectionString" \
        --output tsv)
    
    if [ -z "$COSMOS_CONNECTION_STRING" ]; then
        error "Failed to retrieve Cosmos DB connection string"
        exit 1
    fi
    
    log "Cosmos DB connection string retrieved"
}

# Function to create Event Grid topic
create_event_grid() {
    log "Creating Event Grid topic..."
    
    # Check if topic exists
    if az eventgrid topic show --name ${EVENTGRID_TOPIC_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        warning "Event Grid topic ${EVENTGRID_TOPIC_NAME} already exists"
    else
        az eventgrid topic create \
            --name ${EVENTGRID_TOPIC_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --output none
        
        success "Event Grid topic created: ${EVENTGRID_TOPIC_NAME}"
    fi
    
    # Get endpoint and access key
    export EVENTGRID_ENDPOINT=$(az eventgrid topic show \
        --name ${EVENTGRID_TOPIC_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query endpoint \
        --output tsv)
    
    export EVENTGRID_ACCESS_KEY=$(az eventgrid topic key list \
        --name ${EVENTGRID_TOPIC_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query key1 \
        --output tsv)
    
    if [ -z "$EVENTGRID_ENDPOINT" ] || [ -z "$EVENTGRID_ACCESS_KEY" ]; then
        error "Failed to retrieve Event Grid credentials"
        exit 1
    fi
    
    log "Event Grid credentials retrieved"
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account for Azure Functions..."
    
    # Check if storage account exists
    if az storage account show --name ${STORAGE_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        warning "Storage account ${STORAGE_ACCOUNT_NAME} already exists"
    else
        az storage account create \
            --name ${STORAGE_ACCOUNT_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --sku Standard_LRS \
            --kind StorageV2 \
            --output none
        
        success "Storage account created: ${STORAGE_ACCOUNT_NAME}"
    fi
    
    # Get connection string
    export STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name ${STORAGE_ACCOUNT_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query connectionString \
        --output tsv)
    
    if [ -z "$STORAGE_CONNECTION_STRING" ]; then
        error "Failed to retrieve storage account connection string"
        exit 1
    fi
    
    log "Storage account connection string retrieved"
}

# Function to create Function App
create_function_app() {
    log "Creating Azure Function App..."
    
    # Check if function app exists
    if az functionapp show --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        warning "Function App ${FUNCTION_APP_NAME} already exists"
    else
        az functionapp create \
            --name ${FUNCTION_APP_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --storage-account ${STORAGE_ACCOUNT_NAME} \
            --consumption-plan-location ${LOCATION} \
            --runtime node \
            --functions-version 4 \
            --os-type Linux \
            --output none
        
        success "Function App created: ${FUNCTION_APP_NAME}"
    fi
    
    # Configure application settings
    log "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --settings \
        "COMMUNICATION_SERVICES_CONNECTION_STRING=${COMM_CONNECTION_STRING}" \
        "COSMOS_DB_CONNECTION_STRING=${COSMOS_CONNECTION_STRING}" \
        "EVENTGRID_TOPIC_ENDPOINT=${EVENTGRID_ENDPOINT}" \
        "EVENTGRID_ACCESS_KEY=${EVENTGRID_ACCESS_KEY}" \
        --output none
    
    success "Function App settings configured"
}

# Function to create Event Grid subscription
create_event_subscription() {
    log "Creating Event Grid subscription..."
    
    # Get Function App resource ID
    FUNCTION_RESOURCE_ID=$(az functionapp show \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query id \
        --output tsv)
    
    if [ -z "$FUNCTION_RESOURCE_ID" ]; then
        error "Failed to retrieve Function App resource ID"
        exit 1
    fi
    
    # Check if subscription exists
    if az eventgrid event-subscription show --name "comms-events-subscription" --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENTGRID_TOPIC_NAME}" &> /dev/null; then
        warning "Event Grid subscription already exists"
    else
        az eventgrid event-subscription create \
            --name "comms-events-subscription" \
            --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENTGRID_TOPIC_NAME}" \
            --endpoint "${FUNCTION_RESOURCE_ID}/functions/MessageProcessor" \
            --endpoint-type azurefunction \
            --event-delivery-schema eventgridschema \
            --output none
        
        success "Event Grid subscription created"
    fi
}

# Function to deploy function code
deploy_function_code() {
    log "Deploying Azure Function code..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    
    # Create function directory structure
    mkdir -p "${TEMP_DIR}/MessageProcessor"
    mkdir -p "${TEMP_DIR}/MessageRouter"
    
    # Create MessageProcessor function.json
    cat > "${TEMP_DIR}/MessageProcessor/function.json" << 'EOF'
{
  "bindings": [
    {
      "type": "eventGridTrigger",
      "name": "eventGridEvent",
      "direction": "in"
    },
    {
      "type": "cosmosDB",
      "name": "messagesOut",
      "databaseName": "CommunicationPlatform",
      "collectionName": "Messages",
      "createIfNotExists": false,
      "connectionStringSetting": "COSMOS_DB_CONNECTION_STRING",
      "direction": "out"
    }
  ]
}
EOF
    
    # Create MessageProcessor index.js
    cat > "${TEMP_DIR}/MessageProcessor/index.js" << 'EOF'
const { CommunicationServiceClient } = require('@azure/communication-administration');
const { CosmosClient } = require('@azure/cosmos');

module.exports = async function (context, eventGridEvent) {
    context.log('Processing communication event:', eventGridEvent);
    
    const { eventType, subject, data } = eventGridEvent;
    
    try {
        // Process different event types
        switch (eventType) {
            case 'Microsoft.Communication.MessageReceived':
                await handleMessageReceived(context, data);
                break;
            case 'Microsoft.Communication.MessageDelivered':
                await handleMessageDelivered(context, data);
                break;
            case 'Microsoft.Communication.MessageFailed':
                await handleMessageFailed(context, data);
                break;
            default:
                context.log('Unknown event type:', eventType);
        }
    } catch (error) {
        context.log.error('Error processing event:', error);
        throw error;
    }
};

async function handleMessageReceived(context, data) {
    const messageRecord = {
        id: data.messageId,
        conversationId: data.conversationId,
        customerId: data.customerId,
        channel: data.channel,
        content: data.content,
        timestamp: new Date().toISOString(),
        status: 'received',
        direction: 'inbound'
    };
    
    context.bindings.messagesOut = messageRecord;
    context.log('Message received and stored:', messageRecord.id);
}

async function handleMessageDelivered(context, data) {
    context.log('Message delivered:', data.messageId);
    // Update message status in database
}

async function handleMessageFailed(context, data) {
    context.log('Message failed:', data.messageId, data.reason);
    // Handle failure scenario
}
EOF
    
    # Create MessageRouter function.json
    cat > "${TEMP_DIR}/MessageRouter/function.json" << 'EOF'
{
  "bindings": [
    {
      "type": "httpTrigger",
      "authLevel": "function",
      "name": "req",
      "direction": "in",
      "methods": ["post"]
    },
    {
      "type": "http",
      "name": "res",
      "direction": "out"
    }
  ]
}
EOF
    
    # Create MessageRouter index.js
    cat > "${TEMP_DIR}/MessageRouter/index.js" << 'EOF'
const { CommunicationServiceClient } = require('@azure/communication-administration');
const { EventGridPublisherClient } = require('@azure/eventgrid');

module.exports = async function (context, req) {
    context.log('Processing message routing request');
    
    const { customerId, message, channels, priority } = req.body;
    
    try {
        // Determine optimal channel based on customer preferences
        const selectedChannel = await selectOptimalChannel(customerId, channels, priority);
        
        // Send message through selected channel
        const result = await sendMessage(selectedChannel, customerId, message);
        
        // Publish event for tracking
        await publishMessageEvent(context, {
            messageId: result.messageId,
            customerId: customerId,
            channel: selectedChannel,
            status: 'sent'
        });
        
        context.res = {
            status: 200,
            body: {
                messageId: result.messageId,
                channel: selectedChannel,
                status: 'sent'
            }
        };
    } catch (error) {
        context.log.error('Error routing message:', error);
        context.res = {
            status: 500,
            body: { error: 'Failed to route message' }
        };
    }
};

async function selectOptimalChannel(customerId, channels, priority) {
    // Channel selection logic based on customer preferences and priority
    return channels.includes('whatsapp') ? 'whatsapp' : 
           channels.includes('sms') ? 'sms' : 'email';
}

async function sendMessage(channel, customerId, message) {
    // Simulate message sending logic
    return {
        messageId: `msg-${Date.now()}`,
        status: 'sent'
    };
}

async function publishMessageEvent(context, eventData) {
    // Event publishing logic
    context.log('Publishing message event:', eventData);
}
EOF
    
    # Create package.json
    cat > "${TEMP_DIR}/package.json" << 'EOF'
{
  "name": "communication-platform-functions",
  "version": "1.0.0",
  "dependencies": {
    "@azure/communication-administration": "^1.0.0",
    "@azure/cosmos": "^4.0.0",
    "@azure/eventgrid": "^4.0.0"
  }
}
EOF
    
    # Create deployment package
    cd "${TEMP_DIR}"
    zip -r function-app.zip . > /dev/null
    
    # Deploy to Azure
    az functionapp deployment source config-zip \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --src function-app.zip \
        --output none
    
    # Clean up
    rm -rf "${TEMP_DIR}"
    
    success "Function code deployed successfully"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check Communication Services
    local comm_status=$(az communication show \
        --name ${COMM_SERVICE_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query provisioningState \
        --output tsv 2>/dev/null)
    
    if [ "$comm_status" = "Succeeded" ]; then
        success "Communication Services is running"
    else
        error "Communication Services validation failed"
        return 1
    fi
    
    # Check Cosmos DB
    local cosmos_status=$(az cosmosdb show \
        --name ${COSMOS_ACCOUNT_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query provisioningState \
        --output tsv 2>/dev/null)
    
    if [ "$cosmos_status" = "Succeeded" ]; then
        success "Cosmos DB is running"
    else
        error "Cosmos DB validation failed"
        return 1
    fi
    
    # Check Function App
    local func_status=$(az functionapp show \
        --name ${FUNCTION_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query state \
        --output tsv 2>/dev/null)
    
    if [ "$func_status" = "Running" ]; then
        success "Function App is running"
    else
        warning "Function App status: $func_status"
    fi
    
    # Check Event Grid Topic
    local eg_status=$(az eventgrid topic show \
        --name ${EVENTGRID_TOPIC_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query provisioningState \
        --output tsv 2>/dev/null)
    
    if [ "$eg_status" = "Succeeded" ]; then
        success "Event Grid topic is active"
    else
        error "Event Grid topic validation failed"
        return 1
    fi
}

# Function to display deployment summary
show_deployment_summary() {
    log "Deployment Summary:"
    echo "======================================"
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Communication Services: ${COMM_SERVICE_NAME}"
    echo "Event Grid Topic: ${EVENTGRID_TOPIC_NAME}"
    echo "Function App: ${FUNCTION_APP_NAME}"
    echo "Cosmos DB Account: ${COSMOS_ACCOUNT_NAME}"
    echo "Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "======================================"
    echo ""
    echo "Next Steps:"
    echo "1. Configure domain and email authentication in Communication Services"
    echo "2. Set up SMS and WhatsApp channel credentials"
    echo "3. Test message routing using the Function App endpoints"
    echo "4. Monitor Event Grid events in the Azure portal"
    echo ""
    echo "Function App URL: https://${FUNCTION_APP_NAME}.azurewebsites.net"
    echo ""
    success "Multi-channel communication platform deployed successfully!"
}

# Main execution
main() {
    log "Starting Azure Multi-Channel Communication Platform deployment..."
    
    check_prerequisites
    setup_environment
    create_resource_group
    create_communication_services
    create_cosmos_db
    create_event_grid
    create_storage_account
    create_function_app
    create_event_subscription
    deploy_function_code
    
    if validate_deployment; then
        show_deployment_summary
    else
        error "Deployment validation failed. Please check the resources in Azure portal."
        exit 1
    fi
}

# Run main function
main "$@"