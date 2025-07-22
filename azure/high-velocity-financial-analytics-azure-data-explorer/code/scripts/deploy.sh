#!/bin/bash

# Azure Financial Market Data Processing - Deployment Script
# Recipe: High-Velocity Financial Analytics with Azure Data Explorer and Event Hubs
# Version: 1.1
# Last Updated: 2025-07-12

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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version (minimum 2.50.0)
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    local min_version="2.50.0"
    if [[ $(printf '%s\n' "$min_version" "$az_version" | sort -V | head -n1) != "$min_version" ]]; then
        error "Azure CLI version $az_version is too old. Minimum required: $min_version"
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required tools are available
    if ! command -v openssl &> /dev/null; then
        error "openssl is required but not installed."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-financial-market-data-${RANDOM_SUFFIX}"
    export LOCATION="eastus"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set specific resource names
    export ADX_CLUSTER_NAME="adx-market-${RANDOM_SUFFIX}"
    export EVENT_HUB_NAMESPACE="evhns-market-${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="func-market-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stmarket${RANDOM_SUFFIX}"
    export EVENT_GRID_TOPIC="egt-market-alerts-${RANDOM_SUFFIX}"
    
    # Display configuration
    log "Deployment Configuration:"
    echo "  Resource Group: ${RESOURCE_GROUP}"
    echo "  Location: ${LOCATION}"
    echo "  ADX Cluster: ${ADX_CLUSTER_NAME}"
    echo "  Event Hub Namespace: ${EVENT_HUB_NAMESPACE}"
    echo "  Function App: ${FUNCTION_APP_NAME}"
    echo "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "  Event Grid Topic: ${EVENT_GRID_TOPIC}"
    
    success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=financial-market-data environment=demo \
        --output none
    
    success "Resource group created: ${RESOURCE_GROUP}"
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account for Azure Functions..."
    
    az storage account create \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --output none
    
    success "Storage account created: ${STORAGE_ACCOUNT_NAME}"
}

# Function to create Azure Data Explorer cluster
create_adx_cluster() {
    log "Creating Azure Data Explorer cluster (this may take 10-15 minutes)..."
    
    az kusto cluster create \
        --cluster-name "${ADX_CLUSTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku name=Dev\(No\ SLA\)_Standard_D11_v2 tier=Basic \
        --output none
    
    success "Azure Data Explorer cluster created: ${ADX_CLUSTER_NAME}"
    
    log "Waiting for ADX cluster to be ready..."
    az kusto cluster wait \
        --cluster-name "${ADX_CLUSTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --created \
        --timeout 1800  # 30 minutes timeout
    
    success "ADX cluster is ready"
}

# Function to create ADX database and tables
create_adx_database() {
    log "Creating MarketData database in ADX cluster..."
    
    az kusto database create \
        --cluster-name "${ADX_CLUSTER_NAME}" \
        --database-name MarketData \
        --resource-group "${RESOURCE_GROUP}" \
        --read-write-database location="${LOCATION}" \
            soft-delete-period=P30D \
            hot-cache-period=P7D \
        --output none
    
    success "MarketData database created in ADX cluster"
    
    # Get ADX cluster URI
    export ADX_URI=$(az kusto cluster show \
        --cluster-name "${ADX_CLUSTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query uri --output tsv)
    
    log "ADX URI: ${ADX_URI}"
    
    # Create KQL script for table creation
    cat > market_data_schema.kql << 'EOF'
.create table MarketDataRaw (
    timestamp: datetime,
    symbol: string,
    price: decimal,
    volume: long,
    high: decimal,
    low: decimal,
    open: decimal,
    close: decimal,
    bid: decimal,
    ask: decimal,
    exchange: string,
    eventType: string
)

.create table TradingEvents (
    timestamp: datetime,
    symbol: string,
    action: string,
    quantity: long,
    price: decimal,
    traderId: string,
    orderId: string,
    executionId: string
)

.create table MarketAlerts (
    timestamp: datetime,
    symbol: string,
    alertType: string,
    condition: string,
    currentPrice: decimal,
    threshold: decimal,
    severity: string
)

.create-or-alter table MarketDataRaw ingestion json mapping "MarketDataMapping"
'[
    {"column": "timestamp", "path": "$.timestamp", "datatype": "datetime"},
    {"column": "symbol", "path": "$.symbol", "datatype": "string"},
    {"column": "price", "path": "$.price", "datatype": "decimal"},
    {"column": "volume", "path": "$.volume", "datatype": "long"},
    {"column": "high", "path": "$.high", "datatype": "decimal"},
    {"column": "low", "path": "$.low", "datatype": "decimal"},
    {"column": "open", "path": "$.open", "datatype": "decimal"},
    {"column": "close", "path": "$.close", "datatype": "decimal"},
    {"column": "bid", "path": "$.bid", "datatype": "decimal"},
    {"column": "ask", "path": "$.ask", "datatype": "decimal"},
    {"column": "exchange", "path": "$.exchange", "datatype": "string"},
    {"column": "eventType", "path": "$.eventType", "datatype": "string"}
]'
EOF
    
    success "KQL schema script created for market data tables"
}

# Function to create Event Hubs
create_event_hubs() {
    log "Creating Event Hubs namespace..."
    
    az eventhubs namespace create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${EVENT_HUB_NAMESPACE}" \
        --location "${LOCATION}" \
        --sku Standard \
        --throughput-units 2 \
        --enable-auto-inflate \
        --maximum-throughput-units 10 \
        --output none
    
    success "Event Hubs namespace created: ${EVENT_HUB_NAMESPACE}"
    
    log "Creating Event Hub for market data..."
    az eventhubs eventhub create \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${EVENT_HUB_NAMESPACE}" \
        --name market-data-hub \
        --partition-count 8 \
        --message-retention 1 \
        --output none
    
    log "Creating Event Hub for trading events..."
    az eventhubs eventhub create \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${EVENT_HUB_NAMESPACE}" \
        --name trading-events-hub \
        --partition-count 4 \
        --message-retention 1 \
        --output none
    
    success "Event Hubs created for market data and trading events"
}

# Function to configure data connection
configure_data_connection() {
    log "Creating data connection from Event Hubs to ADX..."
    
    az kusto data-connection event-hub create \
        --cluster-name "${ADX_CLUSTER_NAME}" \
        --database-name MarketData \
        --resource-group "${RESOURCE_GROUP}" \
        --data-connection-name market-data-connection \
        --event-hub-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventHub/namespaces/${EVENT_HUB_NAMESPACE}/eventhubs/market-data-hub" \
        --consumer-group '$Default' \
        --table-name MarketDataRaw \
        --data-format JSON \
        --mapping-rule-name MarketDataMapping \
        --output none
    
    success "Data connection created from Event Hubs to ADX"
    
    log "Creating consumer group for trading events..."
    az eventhubs eventhub consumer-group create \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${EVENT_HUB_NAMESPACE}" \
        --eventhub-name trading-events-hub \
        --name trading-consumer-group \
        --output none
    
    success "Consumer group created for trading events"
}

# Function to create Azure Functions
create_azure_functions() {
    log "Creating Function App..."
    
    az functionapp create \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${STORAGE_ACCOUNT_NAME}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime python \
        --runtime-version 3.9 \
        --functions-version 4 \
        --os-type Linux \
        --output none
    
    success "Function App created: ${FUNCTION_APP_NAME}"
    
    log "Getting Event Hub connection string..."
    local EVENT_HUB_CONNECTION=$(az eventhubs namespace authorization-rule keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${EVENT_HUB_NAMESPACE}" \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString --output tsv)
    
    log "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "EventHubConnectionString=${EVENT_HUB_CONNECTION}" \
                   "ADX_CLUSTER_URI=${ADX_URI}" \
                   "ADX_DATABASE=MarketData" \
        --output none
    
    success "Function App configured with Event Hub and ADX connections"
}

# Function to create Event Grid
create_event_grid() {
    log "Creating Event Grid topic..."
    
    az eventgrid topic create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${EVENT_GRID_TOPIC}" \
        --location "${LOCATION}" \
        --input-schema EventGridSchema \
        --output none
    
    success "Event Grid topic created: ${EVENT_GRID_TOPIC}"
    
    log "Getting Event Grid topic endpoint and key..."
    local EVENT_GRID_ENDPOINT=$(az eventgrid topic show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${EVENT_GRID_TOPIC}" \
        --query endpoint --output tsv)
    
    local EVENT_GRID_KEY=$(az eventgrid topic key list \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${EVENT_GRID_TOPIC}" \
        --query key1 --output tsv)
    
    log "Updating Function App with Event Grid settings..."
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "EventGridEndpoint=${EVENT_GRID_ENDPOINT}" \
                   "EventGridKey=${EVENT_GRID_KEY}" \
        --output none
    
    success "Event Grid configured for trading alerts"
}

# Function to configure monitoring
configure_monitoring() {
    log "Creating Application Insights instance..."
    
    az monitor app-insights component create \
        --app "${FUNCTION_APP_NAME}-insights" \
        --location "${LOCATION}" \
        --resource-group "${RESOURCE_GROUP}" \
        --application-type web \
        --kind web \
        --output none
    
    local INSIGHTS_KEY=$(az monitor app-insights component show \
        --app "${FUNCTION_APP_NAME}-insights" \
        --resource-group "${RESOURCE_GROUP}" \
        --query instrumentationKey --output tsv)
    
    log "Configuring Function App with Application Insights..."
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "APPINSIGHTS_INSTRUMENTATIONKEY=${INSIGHTS_KEY}" \
        --output none
    
    success "Application Insights configured for monitoring"
    
    log "Creating Log Analytics workspace..."
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "law-market-data-${RANDOM_SUFFIX}" \
        --location "${LOCATION}" \
        --sku PerGB2018 \
        --output none
    
    success "Log Analytics workspace created for centralized logging"
}

# Function to run validation tests
run_validation() {
    log "Running validation tests..."
    
    # Check ADX cluster status
    local adx_state=$(az kusto cluster show \
        --cluster-name "${ADX_CLUSTER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query state --output tsv)
    
    if [[ "$adx_state" == "Running" ]]; then
        success "ADX cluster is running"
    else
        warning "ADX cluster state: $adx_state"
    fi
    
    # Check Event Hubs namespace status
    local eh_status=$(az eventhubs namespace show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${EVENT_HUB_NAMESPACE}" \
        --query status --output tsv)
    
    if [[ "$eh_status" == "Active" ]]; then
        success "Event Hubs namespace is active"
    else
        warning "Event Hubs namespace status: $eh_status"
    fi
    
    # Check Function App status
    local func_state=$(az functionapp show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query state --output tsv)
    
    if [[ "$func_state" == "Running" ]]; then
        success "Function App is running"
    else
        warning "Function App state: $func_state"
    fi
    
    # Check Event Grid topic status
    local eg_state=$(az eventgrid topic show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${EVENT_GRID_TOPIC}" \
        --query provisioningState --output tsv)
    
    if [[ "$eg_state" == "Succeeded" ]]; then
        success "Event Grid topic is ready"
    else
        warning "Event Grid topic state: $eg_state"
    fi
    
    success "Validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo ""
    echo "Azure Data Explorer:"
    echo "  Cluster: ${ADX_CLUSTER_NAME}"
    echo "  URI: ${ADX_URI}"
    echo "  Database: MarketData"
    echo ""
    echo "Event Hubs:"
    echo "  Namespace: ${EVENT_HUB_NAMESPACE}"
    echo "  Market Data Hub: market-data-hub"
    echo "  Trading Events Hub: trading-events-hub"
    echo ""
    echo "Azure Functions:"
    echo "  App: ${FUNCTION_APP_NAME}"
    echo ""
    echo "Event Grid:"
    echo "  Topic: ${EVENT_GRID_TOPIC}"
    echo ""
    echo "Storage:"
    echo "  Account: ${STORAGE_ACCOUNT_NAME}"
    echo ""
    echo "Monitoring:"
    echo "  Application Insights: ${FUNCTION_APP_NAME}-insights"
    echo "  Log Analytics: law-market-data-${RANDOM_SUFFIX}"
    echo ""
    warning "IMPORTANT: Save these values for cleanup using destroy.sh"
    echo ""
    success "Deployment completed successfully!"
    echo "Estimated daily cost: \$150-300 (varies by usage)"
}

# Main deployment function
main() {
    log "Starting Azure Financial Market Data Processing deployment..."
    
    check_prerequisites
    setup_environment
    
    # Create infrastructure components
    create_resource_group
    create_storage_account
    create_adx_cluster
    create_adx_database
    create_event_hubs
    configure_data_connection
    create_azure_functions
    create_event_grid
    configure_monitoring
    
    # Validate deployment
    run_validation
    
    # Display summary
    display_summary
    
    # Save deployment info for cleanup
    cat > .deployment_info << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
ADX_CLUSTER_NAME=${ADX_CLUSTER_NAME}
EVENT_HUB_NAMESPACE=${EVENT_HUB_NAMESPACE}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME}
EVENT_GRID_TOPIC=${EVENT_GRID_TOPIC}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
LOCATION=${LOCATION}
EOF
    
    success "Deployment information saved to .deployment_info"
}

# Error handling
trap 'error "Deployment failed at line $LINENO. Check the logs above for details."' ERR

# Run main function
main "$@"