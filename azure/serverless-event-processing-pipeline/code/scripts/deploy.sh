#!/bin/bash

# deploy.sh - Deploy Azure Functions and Event Hubs for Real-time Data Processing
# This script deploys the complete infrastructure for the real-time data processing recipe

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate Azure CLI authentication
validate_azure_auth() {
    log "Validating Azure CLI authentication..."
    
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show >/dev/null 2>&1; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    
    info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check required tools
    local required_tools=("az" "node" "npm" "func" "openssl")
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            error "Required tool '$tool' is not installed"
            exit 1
        fi
    done
    
    # Check Azure Functions Core Tools version
    local func_version=$(func --version 2>/dev/null || echo "unknown")
    info "Azure Functions Core Tools version: $func_version"
    
    # Check Node.js version
    local node_version=$(node --version 2>/dev/null || echo "unknown")
    info "Node.js version: $node_version"
    
    log "Prerequisites check completed successfully"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set default values if not provided
    export LOCATION=${LOCATION:-"eastus"}
    export RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-recipe-${RANDOM_SUFFIX}"}
    export EVENTHUB_NAMESPACE=${EVENTHUB_NAMESPACE:-"eh-ns-${RANDOM_SUFFIX}"}
    export EVENTHUB_NAME=${EVENTHUB_NAME:-"events-hub"}
    export FUNCTION_APP_NAME=${FUNCTION_APP_NAME:-"func-processor-${RANDOM_SUFFIX}"}
    export STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME:-"st${RANDOM_SUFFIX}"}
    export APP_INSIGHTS_NAME=${APP_INSIGHTS_NAME:-"ai-processor-${RANDOM_SUFFIX}"}
    
    # Validate storage account name (must be 3-24 characters, lowercase, numbers only)
    if [[ ! "$STORAGE_ACCOUNT_NAME" =~ ^[a-z0-9]{3,24}$ ]]; then
        error "Storage account name must be 3-24 characters, lowercase letters and numbers only"
        exit 1
    fi
    
    info "Resource Group: $RESOURCE_GROUP"
    info "Location: $LOCATION"
    info "Event Hub Namespace: $EVENTHUB_NAMESPACE"
    info "Function App: $FUNCTION_APP_NAME"
    info "Storage Account: $STORAGE_ACCOUNT_NAME"
    info "Application Insights: $APP_INSIGHTS_NAME"
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warn "Resource group '$RESOURCE_GROUP' already exists, skipping creation"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log "Resource group '$RESOURCE_GROUP' created successfully"
    else
        error "Failed to create resource group"
        exit 1
    fi
}

# Function to create Event Hubs namespace and Event Hub
create_event_hubs() {
    log "Creating Event Hubs namespace and Event Hub..."
    
    # Create Event Hubs namespace
    info "Creating Event Hubs namespace: $EVENTHUB_NAMESPACE"
    az eventhubs namespace create \
        --name "$EVENTHUB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Basic \
        --enable-auto-inflate false \
        --output none
    
    if [[ $? -ne 0 ]]; then
        error "Failed to create Event Hubs namespace"
        exit 1
    fi
    
    # Wait for namespace to be ready
    info "Waiting for Event Hubs namespace to be ready..."
    sleep 30
    
    # Create Event Hub within the namespace
    info "Creating Event Hub: $EVENTHUB_NAME"
    az eventhubs eventhub create \
        --name "$EVENTHUB_NAME" \
        --namespace-name "$EVENTHUB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --partition-count 4 \
        --message-retention 1 \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log "Event Hubs namespace and Event Hub created successfully"
    else
        error "Failed to create Event Hub"
        exit 1
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account..."
    
    # Check if storage account name is available
    local availability=$(az storage account check-name --name "$STORAGE_ACCOUNT_NAME" --query nameAvailable --output tsv)
    if [[ "$availability" != "true" ]]; then
        error "Storage account name '$STORAGE_ACCOUNT_NAME' is not available"
        exit 1
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log "Storage account '$STORAGE_ACCOUNT_NAME' created successfully"
    else
        error "Failed to create storage account"
        exit 1
    fi
    
    # Get storage account connection string
    STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    if [[ -z "$STORAGE_CONNECTION_STRING" ]]; then
        error "Failed to get storage account connection string"
        exit 1
    fi
    
    info "Storage account connection string configured"
}

# Function to create Application Insights
create_app_insights() {
    log "Creating Application Insights..."
    
    az monitor app-insights component create \
        --app "$APP_INSIGHTS_NAME" \
        --location "$LOCATION" \
        --resource-group "$RESOURCE_GROUP" \
        --application-type web \
        --kind web \
        --output none
    
    if [[ $? -ne 0 ]]; then
        error "Failed to create Application Insights"
        exit 1
    fi
    
    # Get Application Insights instrumentation key
    APPINSIGHTS_KEY=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query instrumentationKey \
        --output tsv)
    
    if [[ -z "$APPINSIGHTS_KEY" ]]; then
        error "Failed to get Application Insights instrumentation key"
        exit 1
    fi
    
    log "Application Insights '$APP_INSIGHTS_NAME' created successfully"
}

# Function to create Function App
create_function_app() {
    log "Creating Function App..."
    
    az functionapp create \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT_NAME" \
        --consumption-plan-location "$LOCATION" \
        --runtime node \
        --runtime-version 18 \
        --functions-version 4 \
        --app-insights "$APP_INSIGHTS_NAME" \
        --output none
    
    if [[ $? -ne 0 ]]; then
        error "Failed to create Function App"
        exit 1
    fi
    
    # Get Event Hubs connection string
    EVENTHUB_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list \
        --resource-group "$RESOURCE_GROUP" \
        --namespace-name "$EVENTHUB_NAMESPACE" \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString \
        --output tsv)
    
    if [[ -z "$EVENTHUB_CONNECTION_STRING" ]]; then
        error "Failed to get Event Hubs connection string"
        exit 1
    fi
    
    # Configure Function App settings
    info "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
            "EventHubConnectionString=$EVENTHUB_CONNECTION_STRING" \
            "APPINSIGHTS_INSTRUMENTATIONKEY=$APPINSIGHTS_KEY" \
            "FUNCTIONS_WORKER_RUNTIME=node" \
        --output none
    
    if [[ $? -eq 0 ]]; then
        log "Function App '$FUNCTION_APP_NAME' created and configured successfully"
    else
        error "Failed to configure Function App settings"
        exit 1
    fi
}

# Function to deploy function code
deploy_function_code() {
    log "Deploying function code..."
    
    # Create temporary directory for function project
    local temp_dir=$(mktemp -d)
    local original_dir=$(pwd)
    
    cd "$temp_dir"
    
    # Initialize function project
    info "Initializing function project..."
    func init . --worker-runtime node --language javascript --force
    
    # Create Event Hub triggered function
    info "Creating Event Hub triggered function..."
    func new --name ProcessEvents --template "EventHubTrigger" --authlevel "function"
    
    # Create the function implementation
    cat > ProcessEvents/index.js << 'EOF'
const { app } = require('@azure/functions');

app.eventHub('ProcessEvents', {
    connection: 'EventHubConnectionString',
    eventHubName: 'events-hub',
    cardinality: 'many',
    handler: async (events, context) => {
        context.log(`Processing ${events.length} events`);
        
        for (const event of events) {
            try {
                // Process each event
                const eventData = typeof event === 'string' ? JSON.parse(event) : event;
                
                // Add your processing logic here
                const processedData = {
                    id: eventData.id || 'unknown',
                    timestamp: new Date().toISOString(),
                    source: eventData.source || 'unknown',
                    processed: true,
                    originalEvent: eventData
                };
                
                // Log processed event for monitoring
                context.log(`Processed event: ${JSON.stringify(processedData)}`);
                
                // Here you would typically save to database or forward to another service
                // Example: await saveToDatabase(processedData);
                
            } catch (error) {
                context.log.error(`Error processing event: ${error.message}`);
                // Implement dead letter queue logic if needed
            }
        }
        
        context.log(`Successfully processed ${events.length} events`);
    }
});
EOF
    
    # Create package.json with required dependencies
    cat > package.json << 'EOF'
{
    "name": "event-processor-function",
    "version": "1.0.0",
    "description": "Azure Function for real-time event processing",
    "main": "index.js",
    "scripts": {
        "test": "echo \"Error: no test specified\" && exit 1"
    },
    "dependencies": {
        "@azure/functions": "^4.0.0"
    }
}
EOF
    
    # Deploy function to Azure
    info "Publishing function to Azure..."
    func azure functionapp publish "$FUNCTION_APP_NAME" --javascript
    
    if [[ $? -eq 0 ]]; then
        log "Function code deployed successfully"
    else
        error "Failed to deploy function code"
        cd "$original_dir"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Clean up temporary directory
    cd "$original_dir"
    rm -rf "$temp_dir"
}

# Function to create event producer for testing
create_event_producer() {
    log "Creating event producer for testing..."
    
    # Create temporary directory for event producer
    local temp_dir=$(mktemp -d)
    local original_dir=$(pwd)
    
    cd "$temp_dir"
    
    # Create event producer script
    cat > send-events.js << 'EOF'
const { EventHubProducerClient } = require("@azure/event-hubs");

const connectionString = process.env.EVENTHUB_CONNECTION_STRING;
const eventHubName = "events-hub";

async function sendEvents() {
    const producer = new EventHubProducerClient(connectionString, eventHubName);
    
    try {
        const batch = await producer.createBatch();
        
        for (let i = 1; i <= 10; i++) {
            const eventData = {
                id: `event-${i}`,
                source: "test-producer",
                timestamp: new Date().toISOString(),
                data: `Sample event data ${i}`,
                temperature: Math.random() * 100,
                humidity: Math.random() * 100
            };
            
            const success = batch.tryAdd({ body: eventData });
            if (!success) {
                console.log(`Failed to add event ${i} to batch`);
            }
        }
        
        await producer.sendBatch(batch);
        console.log("✅ Successfully sent 10 events to Event Hub");
        
    } catch (error) {
        console.error("Error sending events:", error);
    } finally {
        await producer.close();
    }
}

sendEvents().catch(console.error);
EOF
    
    # Create package.json for event producer
    cat > package.json << 'EOF'
{
    "name": "event-producer",
    "version": "1.0.0",
    "dependencies": {
        "@azure/event-hubs": "^5.11.0"
    }
}
EOF
    
    # Install dependencies
    info "Installing event producer dependencies..."
    npm install
    
    # Send test events
    info "Sending test events to Event Hub..."
    EVENTHUB_CONNECTION_STRING="$EVENTHUB_CONNECTION_STRING" node send-events.js
    
    if [[ $? -eq 0 ]]; then
        log "Test events sent successfully"
    else
        warn "Failed to send test events, but deployment continues"
    fi
    
    # Clean up temporary directory
    cd "$original_dir"
    rm -rf "$temp_dir"
}

# Function to display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    echo
    echo "=================================="
    echo "       DEPLOYMENT SUMMARY"
    echo "=================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Event Hub Namespace: $EVENTHUB_NAMESPACE"
    echo "Event Hub Name: $EVENTHUB_NAME"
    echo "Function App: $FUNCTION_APP_NAME"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "Application Insights: $APP_INSIGHTS_NAME"
    echo "=================================="
    echo
    echo "Next steps:"
    echo "1. Monitor function executions in the Azure portal"
    echo "2. View logs in Application Insights"
    echo "3. Send events to test the pipeline"
    echo "4. Use destroy.sh to clean up resources when done"
    echo
    echo "Azure Portal Links:"
    echo "- Function App: https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP_NAME"
    echo "- Event Hubs: https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.EventHub/namespaces/$EVENTHUB_NAMESPACE"
    echo "- Application Insights: https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/components/$APP_INSIGHTS_NAME"
}

# Function to handle cleanup on script failure
cleanup_on_failure() {
    error "Deployment failed. Cleaning up resources..."
    
    # Call destroy script if it exists
    if [[ -f "destroy.sh" ]]; then
        info "Running cleanup script..."
        ./destroy.sh --force
    else
        warn "Cleanup script not found. Please manually clean up resources."
    fi
}

# Main execution
main() {
    log "Starting Azure Functions and Event Hubs deployment..."
    
    # Set up error handling
    trap cleanup_on_failure ERR
    
    # Run deployment steps
    validate_azure_auth
    check_prerequisites
    setup_environment
    create_resource_group
    create_event_hubs
    create_storage_account
    create_app_insights
    create_function_app
    deploy_function_code
    create_event_producer
    display_summary
    
    log "All deployment steps completed successfully!"
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Deploy Azure Functions and Event Hubs for real-time data processing"
            echo
            echo "Environment Variables:"
            echo "  LOCATION              Azure region (default: eastus)"
            echo "  RESOURCE_GROUP        Resource group name"
            echo "  EVENTHUB_NAMESPACE    Event Hub namespace name"
            echo "  FUNCTION_APP_NAME     Function app name"
            echo "  STORAGE_ACCOUNT_NAME  Storage account name"
            echo "  APP_INSIGHTS_NAME     Application Insights name"
            echo
            echo "Options:"
            echo "  --help, -h            Show this help message"
            echo "  --dry-run             Show what would be deployed without actually deploying"
            echo
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Handle dry run mode
if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log "DRY RUN MODE - No resources will be created"
    setup_environment
    echo
    echo "Would create the following resources:"
    echo "- Resource Group: $RESOURCE_GROUP"
    echo "- Event Hub Namespace: $EVENTHUB_NAMESPACE"
    echo "- Event Hub: $EVENTHUB_NAME"
    echo "- Function App: $FUNCTION_APP_NAME"
    echo "- Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "- Application Insights: $APP_INSIGHTS_NAME"
    echo
    echo "Run without --dry-run to actually deploy these resources."
    exit 0
fi

# Run main function
main "$@"