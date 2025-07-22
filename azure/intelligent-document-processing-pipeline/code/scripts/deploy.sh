#!/bin/bash

# Azure Real-time Document Processing Deployment Script
# This script deploys the complete infrastructure for real-time document processing
# using Azure Cosmos DB for MongoDB and Azure Event Hubs

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $AZ_VERSION"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if required tools are available
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random suffixes but not found."
    fi
    
    if ! command -v node &> /dev/null; then
        warning "Node.js is not installed. Some testing features may not work."
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-docprocessing-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set specific resource names
    export EVENT_HUB_NAMESPACE="${EVENT_HUB_NAMESPACE:-eh-docprocessing-${RANDOM_SUFFIX}}"
    export EVENT_HUB_NAME="${EVENT_HUB_NAME:-document-events}"
    export COSMOS_ACCOUNT="${COSMOS_ACCOUNT:-cosmos-docprocessing-${RANDOM_SUFFIX}}"
    export FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-docprocessing-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stdocprocessing${RANDOM_SUFFIX}}"
    export AI_DOCUMENT_SERVICE="${AI_DOCUMENT_SERVICE:-ai-docprocessing-${RANDOM_SUFFIX}}"
    
    # Display configuration
    log "Deployment configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Subscription ID: $SUBSCRIPTION_ID"
    echo "  Random Suffix: $RANDOM_SUFFIX"
    
    success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    # Check if resource group already exists
    if az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; then
        warning "Resource group '$RESOURCE_GROUP' already exists. Skipping creation."
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=document-processing environment=demo \
        --output table
    
    success "Resource group created: $RESOURCE_GROUP"
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account for Function App..."
    
    # Check if storage account already exists
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        warning "Storage account '$STORAGE_ACCOUNT' already exists. Skipping creation."
        return 0
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --output table
    
    success "Storage account created: $STORAGE_ACCOUNT"
}

# Function to create Event Hubs infrastructure
create_event_hubs() {
    log "Creating Azure Event Hubs infrastructure..."
    
    # Create Event Hubs namespace
    if az eventhubs namespace show --name "$EVENT_HUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        warning "Event Hubs namespace '$EVENT_HUB_NAMESPACE' already exists. Skipping creation."
    else
        az eventhubs namespace create \
            --name "$EVENT_HUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard \
            --capacity 1 \
            --output table
        
        log "Waiting for Event Hubs namespace to be ready..."
        az eventhubs namespace wait \
            --name "$EVENT_HUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --created
    fi
    
    # Create Event Hub
    if az eventhubs eventhub show --name "$EVENT_HUB_NAME" --namespace-name "$EVENT_HUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        warning "Event Hub '$EVENT_HUB_NAME' already exists. Skipping creation."
    else
        az eventhubs eventhub create \
            --name "$EVENT_HUB_NAME" \
            --namespace-name "$EVENT_HUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --partition-count 4 \
            --message-retention 1 \
            --output table
    fi
    
    # Create consumer group for Functions
    if az eventhubs eventhub consumer-group show \
        --name functions-consumer \
        --eventhub-name "$EVENT_HUB_NAME" \
        --namespace-name "$EVENT_HUB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        warning "Consumer group 'functions-consumer' already exists. Skipping creation."
    else
        az eventhubs eventhub consumer-group create \
            --name functions-consumer \
            --eventhub-name "$EVENT_HUB_NAME" \
            --namespace-name "$EVENT_HUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --output table
    fi
    
    success "Event Hubs infrastructure created with partitioned architecture"
}

# Function to create Cosmos DB
create_cosmos_db() {
    log "Creating Azure Cosmos DB for MongoDB..."
    
    # Create Cosmos DB account
    if az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        warning "Cosmos DB account '$COSMOS_ACCOUNT' already exists. Skipping creation."
    else
        az cosmosdb create \
            --name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind MongoDB \
            --server-version 4.2 \
            --default-consistency-level Session \
            --enable-automatic-failover true \
            --output table
        
        log "Waiting for Cosmos DB account to be ready..."
        az cosmosdb wait \
            --name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --created
    fi
    
    # Create database
    if az cosmosdb mongodb database show \
        --account-name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --name DocumentProcessingDB &>/dev/null; then
        warning "Database 'DocumentProcessingDB' already exists. Skipping creation."
    else
        az cosmosdb mongodb database create \
            --account-name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --name DocumentProcessingDB \
            --output table
    fi
    
    # Create collection
    if az cosmosdb mongodb collection show \
        --account-name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --database-name DocumentProcessingDB \
        --name ProcessedDocuments &>/dev/null; then
        warning "Collection 'ProcessedDocuments' already exists. Skipping creation."
    else
        az cosmosdb mongodb collection create \
            --account-name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --database-name DocumentProcessingDB \
            --name ProcessedDocuments \
            --throughput 400 \
            --shard documentId \
            --output table
    fi
    
    success "Cosmos DB MongoDB API configured with automatic failover"
}

# Function to create AI Document Intelligence service
create_ai_document_service() {
    log "Creating Azure AI Document Intelligence service..."
    
    # Check if service already exists
    if az cognitiveservices account show \
        --name "$AI_DOCUMENT_SERVICE" \
        --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        warning "AI Document Intelligence service '$AI_DOCUMENT_SERVICE' already exists. Skipping creation."
    else
        az cognitiveservices account create \
            --name "$AI_DOCUMENT_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind FormRecognizer \
            --sku S0 \
            --custom-domain "$AI_DOCUMENT_SERVICE" \
            --output table
    fi
    
    # Get API key and endpoint
    export AI_DOC_KEY=$(az cognitiveservices account keys list \
        --name "$AI_DOCUMENT_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    export AI_DOC_ENDPOINT=$(az cognitiveservices account show \
        --name "$AI_DOCUMENT_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    success "AI Document Intelligence service deployed and configured"
}

# Function to create Function App
create_function_app() {
    log "Creating Azure Functions App..."
    
    # Check if Function App already exists
    if az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        warning "Function App '$FUNCTION_APP_NAME' already exists. Skipping creation."
    else
        az functionapp create \
            --name "$FUNCTION_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --storage-account "$STORAGE_ACCOUNT" \
            --consumption-plan-location "$LOCATION" \
            --runtime node \
            --runtime-version 18 \
            --functions-version 4 \
            --output table
    fi
    
    # Get connection strings
    export EVENT_HUB_CONNECTION=$(az eventhubs namespace authorization-rule keys list \
        --name RootManageSharedAccessKey \
        --namespace-name "$EVENT_HUB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryConnectionString --output tsv)
    
    export COSMOS_CONNECTION=$(az cosmosdb keys list \
        --name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --type connection-strings \
        --query "connectionStrings[0].connectionString" --output tsv)
    
    # Configure application settings
    az functionapp config appsettings set \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "EventHubConnection=$EVENT_HUB_CONNECTION" \
        "CosmosDBConnection=$COSMOS_CONNECTION" \
        "AIDocumentKey=$AI_DOC_KEY" \
        "AIDocumentEndpoint=$AI_DOC_ENDPOINT" \
        --output table
    
    success "Function App configured with Event Hub and Cosmos DB integration"
}

# Function to deploy function code
deploy_function_code() {
    log "Deploying Function App code..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Create DocumentProcessor function
    mkdir -p DocumentProcessor
    cd DocumentProcessor
    
    # Create function.json
    cat > function.json << 'EOF'
{
  "bindings": [
    {
      "type": "eventHubTrigger",
      "name": "eventHubMessages",
      "direction": "in",
      "eventHubName": "document-events",
      "connection": "EventHubConnection",
      "consumerGroup": "functions-consumer",
      "cardinality": "many"
    }
  ]
}
EOF
    
    # Create main function code
    cat > index.js << 'EOF'
const { MongoClient } = require('mongodb');
const axios = require('axios');

module.exports = async function (context, eventHubMessages) {
    const cosmosConnection = process.env.CosmosDBConnection;
    const aiEndpoint = process.env.AIDocumentEndpoint;
    const aiKey = process.env.AIDocumentKey;
    
    const client = new MongoClient(cosmosConnection);
    
    try {
        await client.connect();
        const db = client.db('DocumentProcessingDB');
        const collection = db.collection('ProcessedDocuments');
        
        for (const message of eventHubMessages) {
            try {
                context.log('Processing document:', message.documentId);
                
                // Call AI Document Intelligence
                const response = await axios.post(
                    `${aiEndpoint}/formrecognizer/v2.1/layout/analyze`,
                    { source: message.documentUrl },
                    {
                        headers: {
                            'Ocp-Apim-Subscription-Key': aiKey,
                            'Content-Type': 'application/json'
                        }
                    }
                );
                
                // Get operation location for polling
                const operationLocation = response.headers['operation-location'];
                
                // Poll for completion
                let result;
                let attempts = 0;
                do {
                    await new Promise(resolve => setTimeout(resolve, 1000));
                    const pollResponse = await axios.get(operationLocation, {
                        headers: { 'Ocp-Apim-Subscription-Key': aiKey }
                    });
                    result = pollResponse.data;
                    attempts++;
                } while (result.status === 'running' && attempts < 30);
                
                if (result.status === 'succeeded') {
                    // Store processed document
                    const processedDoc = {
                        documentId: message.documentId,
                        originalUrl: message.documentUrl,
                        extractedText: result.analyzeResult.readResults.map(r => r.lines.map(l => l.text).join(' ')).join('\n'),
                        processingDate: new Date(),
                        metadata: message.metadata || {},
                        aiAnalysis: result.analyzeResult
                    };
                    
                    await collection.insertOne(processedDoc);
                    context.log('Document processed successfully:', message.documentId);
                } else {
                    context.log.error('Document processing failed:', message.documentId);
                }
                
            } catch (error) {
                context.log.error('Error processing document:', error);
            }
        }
    } finally {
        await client.close();
    }
};
EOF
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "document-processor",
  "version": "1.0.0",
  "dependencies": {
    "mongodb": "^6.0.0",
    "axios": "^1.6.0"
  }
}
EOF
    
    cd ..
    
    # Create ChangeProcessor function
    mkdir -p ChangeProcessor
    cd ChangeProcessor
    
    # Create function.json for change feed
    cat > function.json << 'EOF'
{
  "bindings": [
    {
      "type": "cosmosDBTrigger",
      "name": "documents",
      "direction": "in",
      "connectionStringSetting": "CosmosDBConnection",
      "databaseName": "DocumentProcessingDB",
      "collectionName": "ProcessedDocuments",
      "createLeaseCollectionIfNotExists": true,
      "leaseCollectionName": "leases"
    }
  ]
}
EOF
    
    # Create change feed processor
    cat > index.js << 'EOF'
module.exports = async function (context, documents) {
    if (documents && documents.length > 0) {
        context.log('Processing', documents.length, 'document changes');
        
        for (const doc of documents) {
            context.log('Document changed:', doc.documentId);
            
            // Example downstream processing
            if (doc.extractedText && doc.extractedText.length > 1000) {
                context.log('Large document detected, triggering special processing');
                // Add logic for large document handling
            }
            
            // Example: Send notification for specific document types
            if (doc.metadata && doc.metadata.type === 'invoice') {
                context.log('Invoice processed, sending notification');
                // Add notification logic
            }
        }
    }
};
EOF
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "change-processor",
  "version": "1.0.0"
}
EOF
    
    cd ..
    
    # Create deployment package
    zip -r functions.zip DocumentProcessor ChangeProcessor
    
    # Deploy to Function App
    az functionapp deployment source config-zip \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --src functions.zip \
        --timeout 300
    
    # Cleanup temp directory
    rm -rf "$TEMP_DIR"
    
    success "Function App code deployed successfully"
}

# Function to create Application Insights
create_application_insights() {
    log "Creating Application Insights for monitoring..."
    
    # Check if Application Insights already exists
    if az monitor app-insights component show \
        --app "${FUNCTION_APP_NAME}-insights" \
        --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        warning "Application Insights '${FUNCTION_APP_NAME}-insights' already exists. Skipping creation."
    else
        az monitor app-insights component create \
            --app "${FUNCTION_APP_NAME}-insights" \
            --location "$LOCATION" \
            --resource-group "$RESOURCE_GROUP" \
            --kind web \
            --application-type web \
            --output table
    fi
    
    # Get instrumentation key
    APPINSIGHTS_KEY=$(az monitor app-insights component show \
        --app "${FUNCTION_APP_NAME}-insights" \
        --resource-group "$RESOURCE_GROUP" \
        --query instrumentationKey --output tsv)
    
    # Configure Function App with Application Insights
    az functionapp config appsettings set \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings "APPINSIGHTS_INSTRUMENTATIONKEY=$APPINSIGHTS_KEY" \
        --output table
    
    success "Application Insights configured for comprehensive monitoring"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check Event Hub status
    log "Checking Event Hub status..."
    az eventhubs eventhub show \
        --name "$EVENT_HUB_NAME" \
        --namespace-name "$EVENT_HUB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "{Status:status,Partitions:partitionCount,MessageRetention:messageRetentionInDays}" \
        --output table
    
    # Check Cosmos DB status
    log "Checking Cosmos DB status..."
    az cosmosdb show \
        --name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query "{Status:provisioningState,ConsistencyLevel:consistencyPolicy.defaultConsistencyLevel}" \
        --output table
    
    # Check Function App status
    log "Checking Function App status..."
    az functionapp show \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "{State:state,Runtime:siteConfig.linuxFxVersion}" \
        --output table
    
    success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Event Hub Namespace: $EVENT_HUB_NAMESPACE"
    echo "Event Hub Name: $EVENT_HUB_NAME"
    echo "Cosmos DB Account: $COSMOS_ACCOUNT"
    echo "Function App: $FUNCTION_APP_NAME"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "AI Document Service: $AI_DOCUMENT_SERVICE"
    echo "Application Insights: ${FUNCTION_APP_NAME}-insights"
    echo "===================="
    echo ""
    echo "Next Steps:"
    echo "1. Test the deployment by sending document events to the Event Hub"
    echo "2. Monitor function execution in Application Insights"
    echo "3. Check processed documents in Cosmos DB"
    echo "4. Review Azure portal for detailed resource status"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting Azure Real-time Document Processing deployment..."
    
    # Check if dry run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log "DRY RUN MODE: No resources will be created"
        return 0
    fi
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_storage_account
    create_event_hubs
    create_cosmos_db
    create_ai_document_service
    create_function_app
    deploy_function_code
    create_application_insights
    validate_deployment
    display_summary
    
    success "Deployment completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi