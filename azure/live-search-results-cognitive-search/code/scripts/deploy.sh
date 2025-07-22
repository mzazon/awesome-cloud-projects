#!/bin/bash

# Deploy Real-Time Search Application with Azure Cognitive Search and SignalR Service
# This script implements the complete deployment from the recipe with proper error handling

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partially created resources..."
    ./destroy.sh --force 2>/dev/null || true
    exit 1
}

trap cleanup_on_error ERR

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check Azure CLI version (minimum 2.50.0)
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    local min_version="2.50.0"
    if [[ "$(printf '%s\n' "$min_version" "$az_version" | sort -V | head -n1)" != "$min_version" ]]; then
        log_error "Azure CLI version $min_version or higher is required. Current version: $az_version"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Node.js is available for Functions
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js 18+ for Azure Functions development."
        exit 1
    fi
    
    # Check Node.js version (minimum 18.0.0)
    local node_version=$(node --version | sed 's/v//')
    local min_node_version="18.0.0"
    if [[ "$(printf '%s\n' "$min_node_version" "$node_version" | sort -V | head -n1)" != "$min_node_version" ]]; then
        log_error "Node.js version $min_node_version or higher is required. Current version: $node_version"
        exit 1
    fi
    
    # Check if Azure Functions Core Tools are available
    if ! command -v func &> /dev/null; then
        log_warning "Azure Functions Core Tools not found. Installing globally..."
        npm install -g azure-functions-core-tools@4 --unsafe-perm true
    fi
    
    log_success "Prerequisites validation completed"
}

# Set environment variables with validation
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Default values that can be overridden
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-realtimesearch-demo}"
    export LOCATION="${LOCATION:-eastus}"
    
    # Generate unique suffixes for globally unique names
    local timestamp=$(date +%s)
    local random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "${timestamp: -6}")
    
    export SEARCH_SERVICE="${SEARCH_SERVICE:-search${random_suffix}}"
    export SIGNALR_SERVICE="${SIGNALR_SERVICE:-signalr${random_suffix}}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-storage${random_suffix}}"
    export FUNCTION_APP="${FUNCTION_APP:-func${random_suffix}}"
    export EVENT_GRID_TOPIC="${EVENT_GRID_TOPIC:-topic${random_suffix}}"
    export COSMOS_ACCOUNT="${COSMOS_ACCOUNT:-cosmos${random_suffix}}"
    
    # Validate resource names against Azure naming rules
    if [[ ${#SEARCH_SERVICE} -gt 60 || ${#SEARCH_SERVICE} -lt 2 ]]; then
        log_error "Search service name must be 2-60 characters"
        exit 1
    fi
    
    if [[ ${#STORAGE_ACCOUNT} -gt 24 || ${#STORAGE_ACCOUNT} -lt 3 ]]; then
        log_error "Storage account name must be 3-24 characters"
        exit 1
    fi
    
    log_success "Environment variables configured"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Search Service: $SEARCH_SERVICE"
    log_info "SignalR Service: $SIGNALR_SERVICE"
    log_info "Storage Account: $STORAGE_ACCOUNT"
    log_info "Function App: $FUNCTION_APP"
    log_info "Event Grid Topic: $EVENT_GRID_TOPIC"
    log_info "Cosmos Account: $COSMOS_ACCOUNT"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group..."
    
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags environment=demo purpose=real-time-search created-by=deploy-script
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Create storage account
create_storage_account() {
    log_info "Creating storage account for Function App..."
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "Storage account $STORAGE_ACCOUNT already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --https-only true \
            --min-tls-version TLS1_2
        
        log_success "Storage account created: $STORAGE_ACCOUNT"
    fi
}

# Create Azure Cognitive Search service
create_search_service() {
    log_info "Creating Azure Cognitive Search service..."
    
    if az search service show --name "$SEARCH_SERVICE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "Search service $SEARCH_SERVICE already exists"
    else
        az search service create \
            --name "$SEARCH_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku basic \
            --partition-count 1 \
            --replica-count 1
        
        log_success "Search service created: $SEARCH_SERVICE"
    fi
    
    # Get admin key and endpoint
    export SEARCH_ADMIN_KEY=$(az search admin-key show \
        --service-name "$SEARCH_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "primaryKey" -o tsv)
    
    export SEARCH_ENDPOINT="https://${SEARCH_SERVICE}.search.windows.net"
    
    log_info "Search endpoint: $SEARCH_ENDPOINT"
}

# Create Azure SignalR Service
create_signalr_service() {
    log_info "Creating Azure SignalR Service..."
    
    if az signalr show --name "$SIGNALR_SERVICE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "SignalR service $SIGNALR_SERVICE already exists"
    else
        az signalr create \
            --name "$SIGNALR_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_S1 \
            --unit-count 1 \
            --service-mode Serverless
        
        log_success "SignalR Service created: $SIGNALR_SERVICE"
    fi
    
    # Get SignalR connection string
    export SIGNALR_CONNECTION=$(az signalr key list \
        --name "$SIGNALR_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "primaryConnectionString" -o tsv)
}

# Create Azure Cosmos DB
create_cosmos_db() {
    log_info "Creating Azure Cosmos DB..."
    
    if az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "Cosmos DB account $COSMOS_ACCOUNT already exists"
    else
        az cosmosdb create \
            --name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --locations regionName="$LOCATION" \
            --default-consistency-level Session \
            --enable-free-tier false \
            --enable-automatic-failover true
        
        log_success "Cosmos DB account created: $COSMOS_ACCOUNT"
    fi
    
    # Create database and container
    log_info "Creating Cosmos DB database and container..."
    
    if az cosmosdb sql database show --account-name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --name SearchDatabase &>/dev/null; then
        log_warning "Database SearchDatabase already exists"
    else
        az cosmosdb sql database create \
            --account-name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --name SearchDatabase
    fi
    
    if az cosmosdb sql container show --account-name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --database-name SearchDatabase --name Products &>/dev/null; then
        log_warning "Container Products already exists"
    else
        az cosmosdb sql container create \
            --account-name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --database-name SearchDatabase \
            --name Products \
            --partition-key-path "/category" \
            --throughput 400
    fi
    
    # Get Cosmos DB connection string
    export COSMOS_CONNECTION=$(az cosmosdb keys list \
        --name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --type connection-strings \
        --query "connectionStrings[0].connectionString" -o tsv)
    
    log_success "Cosmos DB configured with Products container"
}

# Create Event Grid topic
create_event_grid_topic() {
    log_info "Creating Azure Event Grid topic..."
    
    if az eventgrid topic show --name "$EVENT_GRID_TOPIC" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "Event Grid topic $EVENT_GRID_TOPIC already exists"
    else
        az eventgrid topic create \
            --name "$EVENT_GRID_TOPIC" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION"
        
        log_success "Event Grid topic created: $EVENT_GRID_TOPIC"
    fi
    
    # Get Event Grid endpoint and key
    export EVENT_GRID_ENDPOINT=$(az eventgrid topic show \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query "endpoint" -o tsv)
    
    export EVENT_GRID_KEY=$(az eventgrid topic key list \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query "key1" -o tsv)
}

# Create Azure Function App
create_function_app() {
    log_info "Creating Azure Function App..."
    
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warning "Function App $FUNCTION_APP already exists"
    else
        az functionapp create \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --storage-account "$STORAGE_ACCOUNT" \
            --consumption-plan-location "$LOCATION" \
            --runtime node \
            --runtime-version 18 \
            --functions-version 4 \
            --disable-app-insights false
        
        log_success "Function App created: $FUNCTION_APP"
    fi
    
    # Get storage account key for configuration
    local storage_key=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT" \
        --query '[0].value' -o tsv)
    
    # Configure application settings
    log_info "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "SearchEndpoint=${SEARCH_ENDPOINT}" \
        "SearchAdminKey=${SEARCH_ADMIN_KEY}" \
        "SignalRConnection=${SIGNALR_CONNECTION}" \
        "CosmosDBConnection=${COSMOS_CONNECTION}" \
        "EventGridEndpoint=${EVENT_GRID_ENDPOINT}" \
        "EventGridKey=${EVENT_GRID_KEY}" \
        "AzureWebJobsStorage=DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT};EndpointSuffix=core.windows.net;AccountKey=${storage_key}" \
        "FUNCTIONS_WORKER_RUNTIME=node" \
        "WEBSITE_NODE_DEFAULT_VERSION=~18"
    
    log_success "Function App configured with application settings"
}

# Create search index
create_search_index() {
    log_info "Creating search index schema..."
    
    # Create temporary index definition file
    local index_file=$(mktemp)
    cat > "$index_file" << 'EOF'
{
  "name": "products-index",
  "fields": [
    {"name": "id", "type": "Edm.String", "key": true, "searchable": false},
    {"name": "name", "type": "Edm.String", "searchable": true, "analyzer": "standard.lucene"},
    {"name": "description", "type": "Edm.String", "searchable": true, "analyzer": "standard.lucene"},
    {"name": "category", "type": "Edm.String", "filterable": true, "facetable": true, "searchable": false},
    {"name": "price", "type": "Edm.Double", "filterable": true, "sortable": true, "searchable": false},
    {"name": "inStock", "type": "Edm.Boolean", "filterable": true, "searchable": false},
    {"name": "lastUpdated", "type": "Edm.DateTimeOffset", "filterable": true, "sortable": true, "searchable": false}
  ],
  "suggesters": [
    {"name": "sg", "searchMode": "analyzingInfixMatching", "sourceFields": ["name", "category"]}
  ],
  "scoringProfiles": [
    {
      "name": "boostInStock",
      "functions": [
        {"type": "freshness", "fieldName": "lastUpdated", "boost": 2, "interpolation": "linear", "freshness": {"boostingDuration": "P7D"}}
      ]
    }
  ]
}
EOF
    
    # Create the index using REST API
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        "${SEARCH_ENDPOINT}/indexes/products-index?api-version=2021-04-30-Preview" \
        -H "Content-Type: application/json" \
        -H "api-key: ${SEARCH_ADMIN_KEY}" \
        -d @"$index_file")
    
    rm -f "$index_file"
    
    if [[ "$response_code" == "201" || "$response_code" == "204" ]]; then
        log_success "Search index created successfully"
    else
        log_error "Failed to create search index. HTTP response code: $response_code"
        return 1
    fi
}

# Deploy Azure Functions
deploy_functions() {
    log_info "Creating and deploying Azure Functions..."
    
    # Create temporary function directory
    local func_dir=$(mktemp -d)
    cd "$func_dir"
    
    # Initialize Function App
    func init --javascript --name realtime-search-functions
    cd realtime-search-functions
    
    # Create package.json with required dependencies
    cat > package.json << 'EOF'
{
  "name": "realtime-search-functions",
  "version": "1.0.0",
  "description": "Real-time search application functions",
  "main": "index.js",
  "dependencies": {
    "@azure/search-documents": "^11.3.3",
    "@azure/eventgrid": "^4.10.0"
  },
  "devDependencies": {},
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1"
  }
}
EOF
    
    # Create Index Update Function
    mkdir -p IndexUpdateFunction
    cat > IndexUpdateFunction/function.json << 'EOF'
{
  "bindings": [
    {
      "type": "cosmosDBTrigger",
      "name": "documents",
      "direction": "in",
      "connectionStringSetting": "CosmosDBConnection",
      "databaseName": "SearchDatabase",
      "collectionName": "Products",
      "createLeaseCollectionIfNotExists": true,
      "leaseCollectionName": "leases"
    },
    {
      "type": "eventGrid",
      "name": "eventGridOutput",
      "direction": "out",
      "topicEndpointUri": "EventGridEndpoint",
      "topicAccessKey": "EventGridKey"
    }
  ]
}
EOF
    
    cat > IndexUpdateFunction/index.js << 'EOF'
const { SearchIndexClient, AzureKeyCredential } = require("@azure/search-documents");

module.exports = async function (context, documents) {
    const searchClient = new SearchIndexClient(
        process.env.SearchEndpoint,
        new AzureKeyCredential(process.env.SearchAdminKey)
    );
    
    try {
        // Transform Cosmos DB documents to search documents
        const searchDocuments = documents.map(doc => ({
            id: doc.id,
            name: doc.name,
            description: doc.description,
            category: doc.category,
            price: doc.price,
            inStock: doc.inStock,
            lastUpdated: new Date().toISOString()
        }));
        
        // Update search index
        const indexClient = searchClient.getSearchClient("products-index");
        await indexClient.mergeOrUploadDocuments(searchDocuments);
        
        // Publish event for real-time notification
        context.bindings.eventGridOutput = {
            eventType: "SearchIndexUpdated",
            subject: "products/updated",
            data: {
                documentIds: documents.map(d => d.id),
                updateTime: new Date().toISOString()
            }
        };
        
        context.log(`Updated ${documents.length} documents in search index`);
    } catch (error) {
        context.log.error("Error updating search index:", error);
        throw error;
    }
};
EOF
    
    # Create Notification Function
    mkdir -p NotificationFunction
    cat > NotificationFunction/function.json << 'EOF'
{
  "bindings": [
    {
      "type": "eventGridTrigger",
      "name": "eventGridEvent",
      "direction": "in"
    },
    {
      "type": "signalR",
      "name": "signalRMessages",
      "hubName": "searchHub",
      "connectionStringSetting": "SignalRConnection",
      "direction": "out"
    }
  ]
}
EOF
    
    cat > NotificationFunction/index.js << 'EOF'
module.exports = async function (context, eventGridEvent) {
    if (eventGridEvent.eventType === "SearchIndexUpdated") {
        // Send real-time notification to all connected clients
        context.bindings.signalRMessages = [{
            target: "searchUpdated",
            arguments: [{
                documentIds: eventGridEvent.data.documentIds,
                updateTime: eventGridEvent.data.updateTime,
                message: "Search results have been updated"
            }]
        }];
        
        context.log(`Notified clients about ${eventGridEvent.data.documentIds.length} updated documents`);
    }
};
EOF
    
    # Install dependencies
    npm install
    
    # Deploy to Azure
    log_info "Deploying functions to Azure..."
    func azure functionapp publish "$FUNCTION_APP" --javascript
    
    # Clean up temporary directory
    cd ../../..
    rm -rf "$func_dir"
    
    log_success "Azure Functions deployed successfully"
}

# Create Event Grid subscription
create_event_subscription() {
    log_info "Creating Event Grid subscription..."
    
    # Get Function App resource ID for the notification function
    local function_resource_id=$(az functionapp function show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --function-name NotificationFunction \
        --query id -o tsv)
    
    # Get Event Grid topic resource ID
    local topic_resource_id=$(az eventgrid topic show \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query id -o tsv)
    
    # Create subscription
    az eventgrid event-subscription create \
        --name search-notification-sub \
        --source-resource-id "$topic_resource_id" \
        --endpoint-type azurefunction \
        --endpoint "$function_resource_id" \
        --event-types SearchIndexUpdated \
        --max-delivery-attempts 3 \
        --event-ttl 1440
    
    log_success "Event Grid subscription created"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check search service status
    local search_status=$(az search service show \
        --name "$SEARCH_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "status" -o tsv)
    
    if [[ "$search_status" == "running" ]]; then
        log_success "Search service is running"
    else
        log_error "Search service status: $search_status"
        return 1
    fi
    
    # Check SignalR service status
    local signalr_status=$(az signalr show \
        --name "$SIGNALR_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "provisioningState" -o tsv)
    
    if [[ "$signalr_status" == "Succeeded" ]]; then
        log_success "SignalR service is ready"
    else
        log_error "SignalR service status: $signalr_status"
        return 1
    fi
    
    # Test search index
    log_info "Testing search index..."
    local index_response=$(curl -s -o /dev/null -w "%{http_code}" \
        "${SEARCH_ENDPOINT}/indexes/products-index?api-version=2021-04-30-Preview" \
        -H "api-key: ${SEARCH_ADMIN_KEY}")
    
    if [[ "$index_response" == "200" ]]; then
        log_success "Search index is accessible"
    else
        log_error "Search index test failed. HTTP response: $index_response"
        return 1
    fi
    
    log_success "Deployment verification completed successfully"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > deployment-info.json << EOF
{
  "deployment": {
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "resourceGroup": "$RESOURCE_GROUP",
    "location": "$LOCATION"
  },
  "resources": {
    "searchService": {
      "name": "$SEARCH_SERVICE",
      "endpoint": "$SEARCH_ENDPOINT"
    },
    "signalrService": {
      "name": "$SIGNALR_SERVICE"
    },
    "storageAccount": {
      "name": "$STORAGE_ACCOUNT"
    },
    "functionApp": {
      "name": "$FUNCTION_APP"
    },
    "eventGridTopic": {
      "name": "$EVENT_GRID_TOPIC"
    },
    "cosmosAccount": {
      "name": "$COSMOS_ACCOUNT"
    }
  },
  "endpoints": {
    "searchEndpoint": "$SEARCH_ENDPOINT",
    "eventGridEndpoint": "$EVENT_GRID_ENDPOINT"
  }
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

# Display deployment summary
display_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Search Service: $SEARCH_SERVICE"
    log_info "Search Endpoint: $SEARCH_ENDPOINT"
    log_info "SignalR Service: $SIGNALR_SERVICE"
    log_info "Function App: $FUNCTION_APP"
    log_info "Cosmos DB: $COSMOS_ACCOUNT"
    log_info "Event Grid Topic: $EVENT_GRID_TOPIC"
    echo
    log_info "Next steps:"
    log_info "1. Test the search functionality using the Azure portal"
    log_info "2. Add sample data to Cosmos DB to test real-time updates"
    log_info "3. Connect client applications to SignalR for real-time notifications"
    echo
    log_warning "Remember to run './destroy.sh' when done to avoid ongoing charges"
}

# Main deployment function
main() {
    log_info "Starting deployment of Real-Time Search Application..."
    
    validate_prerequisites
    set_environment_variables
    create_resource_group
    create_storage_account
    create_search_service
    create_signalr_service
    create_cosmos_db
    create_event_grid_topic
    create_function_app
    create_search_index
    deploy_functions
    create_event_subscription
    verify_deployment
    save_deployment_info
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi