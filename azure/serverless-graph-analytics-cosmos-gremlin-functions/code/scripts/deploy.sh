#!/bin/bash

# Serverless Graph Analytics with Azure Cosmos DB Gremlin and Azure Functions - Deployment Script
# This script deploys a complete serverless graph analytics solution using Azure services

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command_exists jq; then
        log_error "jq is not installed. Please install it for JSON parsing."
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command_exists openssl; then
        log_error "openssl is not installed. Please install it for random string generation."
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# Set environment variables
set_environment_variables() {
    log_info "Setting environment variables..."
    
    # Core resource settings
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-graph-analytics}"
    export LOCATION="${LOCATION:-eastus}"
    export RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
    
    # Azure resource names
    export COSMOS_ACCOUNT="${COSMOS_ACCOUNT:-cosmos-graph-${RANDOM_SUFFIX}}"
    export DATABASE_NAME="${DATABASE_NAME:-GraphAnalytics}"
    export GRAPH_NAME="${GRAPH_NAME:-RelationshipGraph}"
    export FUNCTION_APP="${FUNCTION_APP:-func-graph-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stgraph${RANDOM_SUFFIX}}"
    export EVENT_GRID_TOPIC="${EVENT_GRID_TOPIC:-eg-graph-${RANDOM_SUFFIX}}"
    export APP_INSIGHTS="${APP_INSIGHTS:-ai-graph-${RANDOM_SUFFIX}}"
    
    # Tags for resource organization
    export TAGS="purpose=graph-analytics environment=demo project=serverless-graph deployedBy=deployment-script"
    
    log_success "Environment variables configured"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}..."
    
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists, skipping creation"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags ${TAGS}
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Create Application Insights
create_application_insights() {
    log_info "Creating Application Insights: ${APP_INSIGHTS}..."
    
    if az monitor app-insights component show --app "${APP_INSIGHTS}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Application Insights ${APP_INSIGHTS} already exists, skipping creation"
    else
        az monitor app-insights component create \
            --app "${APP_INSIGHTS}" \
            --location "${LOCATION}" \
            --resource-group "${RESOURCE_GROUP}" \
            --application-type web \
            --tags ${TAGS}
        
        log_success "Application Insights created: ${APP_INSIGHTS}"
    fi
    
    # Get instrumentation key
    export INSTRUMENTATION_KEY=$(az monitor app-insights component show \
        --app "${APP_INSIGHTS}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query instrumentationKey \
        --output tsv)
    
    log_info "Application Insights instrumentation key retrieved"
}

# Create Cosmos DB account with Gremlin API
create_cosmos_db() {
    log_info "Creating Cosmos DB account: ${COSMOS_ACCOUNT}..."
    
    if az cosmosdb show --name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Cosmos DB account ${COSMOS_ACCOUNT} already exists, skipping creation"
    else
        log_info "Creating Cosmos DB account (this may take 5-10 minutes)..."
        az cosmosdb create \
            --name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --capabilities EnableGremlin \
            --default-consistency-level Session \
            --locations regionName="${LOCATION}" failoverPriority=0 \
            --enable-automatic-failover false \
            --tags ${TAGS}
        
        log_success "Cosmos DB account created: ${COSMOS_ACCOUNT}"
    fi
    
    # Get Cosmos DB key
    export COSMOS_KEY=$(az cosmosdb keys list \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query primaryMasterKey \
        --output tsv)
    
    log_info "Cosmos DB primary key retrieved"
}

# Create Gremlin database and graph
create_gremlin_database() {
    log_info "Creating Gremlin database: ${DATABASE_NAME}..."
    
    if az cosmosdb gremlin database show \
        --account-name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${DATABASE_NAME}" >/dev/null 2>&1; then
        log_warning "Gremlin database ${DATABASE_NAME} already exists, skipping creation"
    else
        az cosmosdb gremlin database create \
            --account-name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${DATABASE_NAME}"
        
        log_success "Gremlin database created: ${DATABASE_NAME}"
    fi
    
    log_info "Creating Gremlin graph: ${GRAPH_NAME}..."
    
    if az cosmosdb gremlin graph show \
        --account-name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --database-name "${DATABASE_NAME}" \
        --name "${GRAPH_NAME}" >/dev/null 2>&1; then
        log_warning "Gremlin graph ${GRAPH_NAME} already exists, skipping creation"
    else
        az cosmosdb gremlin graph create \
            --account-name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --database-name "${DATABASE_NAME}" \
            --name "${GRAPH_NAME}" \
            --partition-key-path "/partitionKey" \
            --throughput 400
        
        log_success "Gremlin graph created: ${GRAPH_NAME}"
    fi
}

# Create storage account for Function App
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT}..."
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Storage account ${STORAGE_ACCOUNT} already exists, skipping creation"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --tags ${TAGS}
        
        log_success "Storage account created: ${STORAGE_ACCOUNT}"
    fi
}

# Create Function App
create_function_app() {
    log_info "Creating Function App: ${FUNCTION_APP}..."
    
    if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Function App ${FUNCTION_APP} already exists, skipping creation"
    else
        az functionapp create \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime node \
            --runtime-version 18 \
            --functions-version 4 \
            --tags ${TAGS}
        
        log_success "Function App created: ${FUNCTION_APP}"
    fi
    
    # Configure Function App settings
    log_info "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "COSMOS_ENDPOINT=https://${COSMOS_ACCOUNT}.documents.azure.com:443/" \
        "COSMOS_KEY=${COSMOS_KEY}" \
        "DATABASE_NAME=${DATABASE_NAME}" \
        "GRAPH_NAME=${GRAPH_NAME}" \
        "APPINSIGHTS_INSTRUMENTATIONKEY=${INSTRUMENTATION_KEY}" \
        >/dev/null
    
    log_success "Function App settings configured"
}

# Create Event Grid topic
create_event_grid_topic() {
    log_info "Creating Event Grid topic: ${EVENT_GRID_TOPIC}..."
    
    if az eventgrid topic show --name "${EVENT_GRID_TOPIC}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Event Grid topic ${EVENT_GRID_TOPIC} already exists, skipping creation"
    else
        az eventgrid topic create \
            --name "${EVENT_GRID_TOPIC}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags ${TAGS}
        
        log_success "Event Grid topic created: ${EVENT_GRID_TOPIC}"
    fi
    
    # Get Event Grid endpoint and key
    export TOPIC_ENDPOINT=$(az eventgrid topic show \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query endpoint \
        --output tsv)
    
    export TOPIC_KEY=$(az eventgrid topic key list \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 \
        --output tsv)
    
    log_info "Event Grid topic endpoint and key retrieved"
}

# Deploy function code
deploy_function_code() {
    log_info "Preparing function code deployment..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "graph-analytics-functions",
  "version": "1.0.0",
  "description": "Serverless graph analytics functions for Azure Cosmos DB Gremlin",
  "dependencies": {
    "gremlin": "^3.6.2",
    "@azure/event-grid": "^4.13.0"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF
    
    # Create GraphWriter function
    mkdir -p GraphWriter
    cat > GraphWriter/index.js << 'EOF'
const gremlin = require('gremlin');

module.exports = async function (context, eventGridEvent) {
    context.log('GraphWriter function triggered with event:', JSON.stringify(eventGridEvent, null, 2));
    
    const client = new gremlin.driver.Client(
        process.env.COSMOS_ENDPOINT,
        {
            authenticator: new gremlin.driver.auth.PlainTextSaslAuthenticator(
                `/dbs/${process.env.DATABASE_NAME}/colls/${process.env.GRAPH_NAME}`,
                process.env.COSMOS_KEY
            ),
            traversalsource: 'g',
            mimeType: 'application/vnd.gremlin-v2.0+json'
        }
    );
    
    try {
        const { action, vertex, edge } = eventGridEvent.data;
        
        if (action === 'addVertex') {
            const query = "g.addV(label).property('id', id).property('partitionKey', pk)";
            const bindings = { 
                label: vertex.label, 
                id: vertex.id, 
                pk: vertex.partitionKey 
            };
            
            // Add additional properties if present
            if (vertex.properties) {
                for (const [key, value] of Object.entries(vertex.properties)) {
                    bindings[key] = value;
                }
            }
            
            await client.submit(query, bindings);
            context.log(`Vertex added: ${vertex.id} (${vertex.label})`);
            
        } else if (action === 'addEdge') {
            const query = "g.V(source).addE(label).to(g.V(target))";
            const bindings = { 
                source: edge.source, 
                label: edge.label, 
                target: edge.target 
            };
            
            await client.submit(query, bindings);
            context.log(`Edge added: ${edge.source} --[${edge.label}]--> ${edge.target}`);
            
        } else {
            context.log.warn(`Unknown action: ${action}`);
        }
        
        context.res = {
            status: 200,
            body: { message: `Graph operation '${action}' completed successfully` }
        };
        
    } catch (error) {
        context.log.error('Error in GraphWriter:', error);
        context.res = {
            status: 500,
            body: { error: 'Graph operation failed', details: error.message }
        };
    } finally {
        await client.close();
    }
};
EOF
    
    cat > GraphWriter/function.json << 'EOF'
{
  "bindings": [
    {
      "type": "eventGridTrigger",
      "name": "eventGridEvent",
      "direction": "in"
    }
  ]
}
EOF
    
    # Create GraphAnalytics function
    mkdir -p GraphAnalytics
    cat > GraphAnalytics/index.js << 'EOF'
const gremlin = require('gremlin');

module.exports = async function (context, eventGridEvent) {
    context.log('GraphAnalytics function triggered with event:', JSON.stringify(eventGridEvent, null, 2));
    
    const client = new gremlin.driver.Client(
        process.env.COSMOS_ENDPOINT,
        {
            authenticator: new gremlin.driver.auth.PlainTextSaslAuthenticator(
                `/dbs/${process.env.DATABASE_NAME}/colls/${process.env.GRAPH_NAME}`,
                process.env.COSMOS_KEY
            ),
            traversalsource: 'g',
            mimeType: 'application/vnd.gremlin-v2.0+json'
        }
    );
    
    try {
        const { analysisType, parameters } = eventGridEvent.data;
        let result;
        
        switch (analysisType) {
            case 'vertexCount':
                result = await client.submit("g.V().count()");
                break;
                
            case 'edgeCount':
                result = await client.submit("g.E().count()");
                break;
                
            case 'findConnections':
                if (parameters && parameters.vertexId) {
                    result = await client.submit("g.V(vertexId).both().values('name')", { vertexId: parameters.vertexId });
                }
                break;
                
            case 'shortestPath':
                if (parameters && parameters.source && parameters.target) {
                    result = await client.submit(
                        "g.V(source).repeat(both().simplePath()).until(hasId(target)).path().limit(1)",
                        { source: parameters.source, target: parameters.target }
                    );
                }
                break;
                
            case 'influentialNodes':
                result = await client.submit("g.V().order().by(bothE().count(), desc).limit(5).project('id', 'degree').by(id()).by(bothE().count())");
                break;
                
            default:
                throw new Error(`Unknown analysis type: ${analysisType}`);
        }
        
        context.log(`Analysis '${analysisType}' completed with result:`, result);
        
        context.res = {
            status: 200,
            body: { 
                analysisType,
                result: result.toArray ? result.toArray() : result,
                timestamp: new Date().toISOString()
            }
        };
        
    } catch (error) {
        context.log.error('Error in GraphAnalytics:', error);
        context.res = {
            status: 500,
            body: { error: 'Graph analysis failed', details: error.message }
        };
    } finally {
        await client.close();
    }
};
EOF
    
    cat > GraphAnalytics/function.json << 'EOF'
{
  "bindings": [
    {
      "type": "eventGridTrigger",
      "name": "eventGridEvent",
      "direction": "in"
    }
  ]
}
EOF
    
    # Create host.json
    cat > host.json << 'EOF'
{
  "version": "2.0",
  "functionTimeout": "00:05:00",
  "extensions": {
    "eventGrid": {
      "maxEventsPerBatch": 1,
      "preferredBatchSizeInKb": 64
    }
  },
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true
      }
    }
  }
}
EOF
    
    # Create deployment package
    zip -r functions.zip . >/dev/null
    
    log_info "Deploying function code to ${FUNCTION_APP}..."
    az functionapp deployment source config-zip \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --src functions.zip >/dev/null
    
    log_success "Function code deployed successfully"
    
    # Cleanup temporary directory
    cd - >/dev/null
    rm -rf "${TEMP_DIR}"
}

# Configure Event Grid subscriptions
configure_event_subscriptions() {
    log_info "Configuring Event Grid subscriptions..."
    
    # Get Function App resource ID
    FUNCTION_ID=$(az functionapp show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id \
        --output tsv)
    
    # Create subscription for GraphWriter function
    if az eventgrid event-subscription show \
        --name graph-writer-subscription \
        --source-resource-id "$(az eventgrid topic show --name ${EVENT_GRID_TOPIC} --resource-group ${RESOURCE_GROUP} --query id --output tsv)" >/dev/null 2>&1; then
        log_warning "GraphWriter subscription already exists, skipping creation"
    else
        az eventgrid event-subscription create \
            --name graph-writer-subscription \
            --source-resource-id "$(az eventgrid topic show --name ${EVENT_GRID_TOPIC} --resource-group ${RESOURCE_GROUP} --query id --output tsv)" \
            --endpoint "${FUNCTION_ID}/functions/GraphWriter" \
            --endpoint-type azurefunction \
            --included-event-types GraphDataEvent
        
        log_success "GraphWriter Event Grid subscription created"
    fi
    
    # Create subscription for GraphAnalytics function
    if az eventgrid event-subscription show \
        --name graph-analytics-subscription \
        --source-resource-id "$(az eventgrid topic show --name ${EVENT_GRID_TOPIC} --resource-group ${RESOURCE_GROUP} --query id --output tsv)" >/dev/null 2>&1; then
        log_warning "GraphAnalytics subscription already exists, skipping creation"
    else
        az eventgrid event-subscription create \
            --name graph-analytics-subscription \
            --source-resource-id "$(az eventgrid topic show --name ${EVENT_GRID_TOPIC} --resource-group ${RESOURCE_GROUP} --query id --output tsv)" \
            --endpoint "${FUNCTION_ID}/functions/GraphAnalytics" \
            --endpoint-type azurefunction \
            --included-event-types GraphAnalysisEvent
        
        log_success "GraphAnalytics Event Grid subscription created"
    fi
}

# Test the deployment
test_deployment() {
    log_info "Testing deployment with sample graph data..."
    
    # Wait for function deployment to complete
    log_info "Waiting for function deployment to complete..."
    sleep 30
    
    # Create test event for adding a vertex
    TEST_EVENT_VERTEX=$(cat << EOF
[{
  "id": "$(uuidgen)",
  "eventType": "GraphDataEvent",
  "subject": "users/add",
  "eventTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "data": {
    "action": "addVertex",
    "vertex": {
      "id": "user1",
      "label": "person",
      "partitionKey": "user1",
      "properties": {
        "name": "Alice",
        "age": 30,
        "city": "Seattle"
      }
    }
  },
  "dataVersion": "1.0"
}]
EOF
    )
    
    # Send test event
    log_info "Sending test vertex creation event..."
    echo "${TEST_EVENT_VERTEX}" | curl -X POST "${TOPIC_ENDPOINT}" \
        -H "aeg-sas-key: ${TOPIC_KEY}" \
        -H "Content-Type: application/json" \
        -d @- >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Test event sent successfully"
    else
        log_warning "Failed to send test event, but deployment is complete"
    fi
    
    # Wait for event processing
    sleep 10
    
    # Create test analytics event
    TEST_EVENT_ANALYTICS=$(cat << EOF
[{
  "id": "$(uuidgen)",
  "eventType": "GraphAnalysisEvent",
  "subject": "analytics/count",
  "eventTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "data": {
    "analysisType": "vertexCount",
    "parameters": {}
  },
  "dataVersion": "1.0"
}]
EOF
    )
    
    # Send analytics test event
    log_info "Sending test analytics event..."
    echo "${TEST_EVENT_ANALYTICS}" | curl -X POST "${TOPIC_ENDPOINT}" \
        -H "aeg-sas-key: ${TOPIC_KEY}" \
        -H "Content-Type: application/json" \
        -d @- >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Analytics test event sent successfully"
    else
        log_warning "Failed to send analytics test event, but deployment is complete"
    fi
}

# Display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=================="
    echo
    echo "✅ Resource Group: ${RESOURCE_GROUP}"
    echo "✅ Cosmos DB Account: ${COSMOS_ACCOUNT}"
    echo "✅ Gremlin Database: ${DATABASE_NAME}"
    echo "✅ Gremlin Graph: ${GRAPH_NAME}"
    echo "✅ Function App: ${FUNCTION_APP}"
    echo "✅ Storage Account: ${STORAGE_ACCOUNT}"
    echo "✅ Event Grid Topic: ${EVENT_GRID_TOPIC}"
    echo "✅ Application Insights: ${APP_INSIGHTS}"
    echo
    echo "🔗 Useful Links:"
    echo "   - Azure Portal: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/overview"
    echo "   - Cosmos DB Data Explorer: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DocumentDB/databaseAccounts/${COSMOS_ACCOUNT}/dataExplorer"
    echo "   - Function App: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${FUNCTION_APP}/functions"
    echo "   - Application Insights: https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Insights/components/${APP_INSIGHTS}/overview"
    echo
    echo "📋 Next Steps:"
    echo "   1. Test the solution by sending events to the Event Grid topic"
    echo "   2. Monitor function execution in Application Insights"
    echo "   3. Explore graph data using Cosmos DB Data Explorer"
    echo "   4. Customize functions for your specific use case"
    echo
    echo "🧪 Sample Events:"
    echo "   Event Grid Endpoint: ${TOPIC_ENDPOINT}"
    echo "   (Use the topic key from Azure Portal for authentication)"
    echo
    echo "💰 Estimated Monthly Cost: \$50-100 USD (varies by usage)"
    echo "   - Cosmos DB: ~\$25-50"
    echo "   - Functions: ~\$10-20"
    echo "   - Event Grid: ~\$5-10"
    echo "   - Storage & App Insights: ~\$5-10"
    echo
    echo "🗑️ Cleanup: Run ./destroy.sh when you're done testing"
}

# Main deployment function
main() {
    log_info "Starting Azure Serverless Graph Analytics deployment..."
    echo
    
    validate_prerequisites
    set_environment_variables
    create_resource_group
    create_application_insights
    create_cosmos_db
    create_gremlin_database
    create_storage_account
    create_function_app
    create_event_grid_topic
    deploy_function_code
    configure_event_subscriptions
    test_deployment
    
    echo
    log_success "Deployment completed successfully!"
    echo
    display_summary
}

# Execute main function
main "$@"