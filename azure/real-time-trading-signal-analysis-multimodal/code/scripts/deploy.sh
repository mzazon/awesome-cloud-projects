#!/bin/bash

# Deployment script for Orchestrating Intelligent Financial Trading Signal Analysis
# with Azure AI Content Understanding and Azure Stream Analytics
# 
# This script deploys a complete intelligent financial trading signal analysis system
# that combines Azure AI Content Understanding with Azure Stream Analytics for
# real-time market data processing and content-enhanced trading signals.

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Configuration
DEPLOYMENT_NAME="trading-signals-deployment"
LOCATION="eastus"
DEPLOYMENT_TIMEOUT=3600  # 1 hour timeout

# Default values (can be overridden with environment variables)
RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-trading-signals"}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT:-"sttrading$(openssl rand -hex 3)"}
AI_SERVICES_NAME=${AI_SERVICES_NAME:-"ais-trading-$(openssl rand -hex 3)"}
EVENT_HUB_NAMESPACE=${EVENT_HUB_NAMESPACE:-"ehns-trading-$(openssl rand -hex 3)"}
EVENT_HUB_NAME=${EVENT_HUB_NAME:-"eh-market-data"}
STREAM_ANALYTICS_JOB=${STREAM_ANALYTICS_JOB:-"saj-trading-signals"}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME:-"func-trading-$(openssl rand -hex 3)"}
COSMOS_DB_ACCOUNT=${COSMOS_DB_ACCOUNT:-"cosmos-trading-$(openssl rand -hex 3)"}
SERVICE_BUS_NAMESPACE=${SERVICE_BUS_NAMESPACE:-"sb-trading-$(openssl rand -hex 3)"}

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy intelligent financial trading signal analysis system"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -g, --resource-group    Resource group name (default: rg-trading-signals)"
    echo "  -l, --location          Azure region (default: eastus)"
    echo "  -n, --dry-run          Show what would be deployed without actually deploying"
    echo "  -v, --verbose          Enable verbose logging"
    echo "  -t, --timeout          Deployment timeout in seconds (default: 3600)"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP         Override default resource group name"
    echo "  STORAGE_ACCOUNT        Override default storage account name"
    echo "  AI_SERVICES_NAME       Override default AI services name"
    echo "  EVENT_HUB_NAMESPACE    Override default Event Hub namespace"
    echo "  FUNCTION_APP_NAME      Override default Function App name"
    echo "  COSMOS_DB_ACCOUNT      Override default Cosmos DB account name"
    echo "  SERVICE_BUS_NAMESPACE  Override default Service Bus namespace"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with defaults"
    echo "  $0 -g my-rg -l westus2              # Deploy to specific resource group and region"
    echo "  $0 --dry-run                         # Show what would be deployed"
    echo "  RESOURCE_GROUP=my-rg $0             # Use environment variable"
}

# Parse command line arguments
VERBOSE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -t|--timeout)
            DEPLOYMENT_TIMEOUT="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Prerequisite checks
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if jq is installed for JSON processing
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some features may not work properly."
    fi
    
    # Check if openssl is available for generating random values
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Required for generating unique resource names."
    fi
    
    # Get subscription information
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    
    info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    info "Resource group: $RESOURCE_GROUP"
    info "Location: $LOCATION"
    
    # Check resource provider registrations
    log "Checking resource provider registrations..."
    
    local providers=("Microsoft.EventHub" "Microsoft.StreamAnalytics" "Microsoft.CognitiveServices" "Microsoft.DocumentDB" "Microsoft.ServiceBus" "Microsoft.Web" "Microsoft.Storage")
    
    for provider in "${providers[@]}"; do
        local state=$(az provider show --namespace "$provider" --query registrationState --output tsv 2>/dev/null || echo "NotRegistered")
        if [ "$state" != "Registered" ]; then
            log "Registering provider: $provider"
            if [ "$DRY_RUN" = false ]; then
                az provider register --namespace "$provider" --wait
            fi
        fi
    done
    
    log "Prerequisites check completed successfully"
}

# Create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        info "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=trading-signals environment=production owner=trading-team cost-center=quantitative-research
        
        log "Resource group created successfully"
    fi
}

# Deploy storage account
deploy_storage_account() {
    log "Deploying storage account: $STORAGE_ACCOUNT"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would deploy storage account: $STORAGE_ACCOUNT"
        return
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --allow-blob-public-access false \
        --min-tls-version TLS1_2
    
    # Create storage containers
    local storage_key=$(az storage account keys list \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query '[0].value' --output tsv)
    
    local containers=("financial-videos" "research-documents" "processed-insights")
    
    for container in "${containers[@]}"; do
        az storage container create \
            --name "$container" \
            --account-name "$STORAGE_ACCOUNT" \
            --account-key "$storage_key" \
            --public-access off
    done
    
    # Create lifecycle management policy
    cat > lifecycle_policy.json << 'EOF'
{
  "rules": [
    {
      "enabled": true,
      "name": "ArchiveOldContent",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"]
        },
        "actions": {
          "baseBlob": {
            "tierToCool": {
              "daysAfterModificationGreaterThan": 30
            },
            "tierToArchive": {
              "daysAfterModificationGreaterThan": 90
            }
          }
        }
      }
    }
  ]
}
EOF
    
    az storage account management-policy create \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --policy @lifecycle_policy.json
    
    rm -f lifecycle_policy.json
    
    log "Storage account deployed successfully"
}

# Deploy AI Services
deploy_ai_services() {
    log "Deploying Azure AI Services: $AI_SERVICES_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would deploy AI Services: $AI_SERVICES_NAME"
        return
    fi
    
    az cognitiveservices account create \
        --name "$AI_SERVICES_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind CognitiveServices \
        --sku S0 \
        --custom-domain "$AI_SERVICES_NAME" \
        --assign-identity
    
    log "AI Services deployed successfully"
}

# Deploy Event Hubs
deploy_event_hubs() {
    log "Deploying Event Hubs: $EVENT_HUB_NAMESPACE"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would deploy Event Hubs: $EVENT_HUB_NAMESPACE"
        return
    fi
    
    # Create Event Hubs namespace
    az eventhubs namespace create \
        --name "$EVENT_HUB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard \
        --enable-auto-inflate true \
        --maximum-throughput-units 10
    
    # Create Event Hub
    az eventhubs eventhub create \
        --name "$EVENT_HUB_NAME" \
        --namespace-name "$EVENT_HUB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --partition-count 8 \
        --message-retention 3
    
    # Create consumer group
    az eventhubs eventhub consumer-group create \
        --name "stream-analytics-consumer" \
        --eventhub-name "$EVENT_HUB_NAME" \
        --namespace-name "$EVENT_HUB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP"
    
    log "Event Hubs deployed successfully"
}

# Deploy Cosmos DB
deploy_cosmos_db() {
    log "Deploying Cosmos DB: $COSMOS_DB_ACCOUNT"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would deploy Cosmos DB: $COSMOS_DB_ACCOUNT"
        return
    fi
    
    # Create Cosmos DB account
    az cosmosdb create \
        --name "$COSMOS_DB_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --locations regionName="$LOCATION" failoverPriority=0 \
        --default-consistency-level "Session" \
        --enable-automatic-failover true \
        --enable-multiple-write-locations false
    
    # Create database
    az cosmosdb sql database create \
        --account-name "$COSMOS_DB_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --name "TradingSignals"
    
    # Create container
    az cosmosdb sql container create \
        --account-name "$COSMOS_DB_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --database-name "TradingSignals" \
        --name "Signals" \
        --partition-key-path "/symbol" \
        --throughput 1000 \
        --default-ttl 604800
    
    log "Cosmos DB deployed successfully"
}

# Deploy Service Bus
deploy_service_bus() {
    log "Deploying Service Bus: $SERVICE_BUS_NAMESPACE"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would deploy Service Bus: $SERVICE_BUS_NAMESPACE"
        return
    fi
    
    # Create Service Bus namespace
    az servicebus namespace create \
        --name "$SERVICE_BUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Premium \
        --capacity 1
    
    # Create topic
    az servicebus topic create \
        --name "trading-signals" \
        --namespace-name "$SERVICE_BUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --max-size 5120 \
        --default-message-time-to-live P7D
    
    # Create subscription
    az servicebus topic subscription create \
        --name "high-priority-signals" \
        --topic-name "trading-signals" \
        --namespace-name "$SERVICE_BUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --max-delivery-count 3
    
    # Create subscription rule
    az servicebus topic subscription rule create \
        --name "strong-signals-only" \
        --topic-name "trading-signals" \
        --subscription-name "high-priority-signals" \
        --namespace-name "$SERVICE_BUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --filter-type SqlFilter \
        --filter-expression "signal IN ('STRONG_BUY', 'STRONG_SELL')"
    
    log "Service Bus deployed successfully"
}

# Deploy Function App
deploy_function_app() {
    log "Deploying Function App: $FUNCTION_APP_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would deploy Function App: $FUNCTION_APP_NAME"
        return
    fi
    
    # Create Function App plan
    az functionapp plan create \
        --name "plan-$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku P1V2 \
        --is-linux false
    
    # Create Function App
    az functionapp create \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --plan "plan-$FUNCTION_APP_NAME" \
        --storage-account "$STORAGE_ACCOUNT" \
        --runtime dotnet \
        --functions-version 4
    
    # Get connection strings and endpoints
    local cosmos_endpoint=$(az cosmosdb show \
        --name "$COSMOS_DB_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query documentEndpoint --output tsv)
    
    local cosmos_key=$(az cosmosdb keys list \
        --name "$COSMOS_DB_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryMasterKey --output tsv)
    
    local eh_connection_string=$(az eventhubs namespace authorization-rule keys list \
        --name RootManageSharedAccessKey \
        --namespace-name "$EVENT_HUB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryConnectionString --output tsv)
    
    local ai_endpoint=$(az cognitiveservices account show \
        --name "$AI_SERVICES_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    local ai_key=$(az cognitiveservices account keys list \
        --name "$AI_SERVICES_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    # Configure application settings
    az functionapp config appsettings set \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
            "CosmosDB_Endpoint=$cosmos_endpoint" \
            "CosmosDB_Key=$cosmos_key" \
            "EventHub_ConnectionString=$eh_connection_string" \
            "AzureAI_Endpoint=$ai_endpoint" \
            "AzureAI_Key=$ai_key"
    
    log "Function App deployed successfully"
}

# Deploy Stream Analytics
deploy_stream_analytics() {
    log "Deploying Stream Analytics: $STREAM_ANALYTICS_JOB"
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would deploy Stream Analytics: $STREAM_ANALYTICS_JOB"
        return
    fi
    
    # Create Stream Analytics job
    az stream-analytics job create \
        --name "$STREAM_ANALYTICS_JOB" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard \
        --streaming-units 6 \
        --data-locale "en-US" \
        --output-error-policy "Stop" \
        --events-out-of-order-policy "Adjust"
    
    # Get Event Hub connection string
    local eh_connection_string=$(az eventhubs namespace authorization-rule keys list \
        --name RootManageSharedAccessKey \
        --namespace-name "$EVENT_HUB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryConnectionString --output tsv)
    
    local eh_key=$(echo "$eh_connection_string" | cut -d";" -f3 | cut -d"=" -f2)
    
    # Configure input
    az stream-analytics input create \
        --job-name "$STREAM_ANALYTICS_JOB" \
        --resource-group "$RESOURCE_GROUP" \
        --name "MarketDataInput" \
        --type "Stream" \
        --datasource "{
          \"type\": \"Microsoft.ServiceBus/EventHub\",
          \"properties\": {
            \"eventHubName\": \"$EVENT_HUB_NAME\",
            \"serviceBusNamespace\": \"$EVENT_HUB_NAMESPACE\",
            \"sharedAccessPolicyName\": \"RootManageSharedAccessKey\",
            \"sharedAccessPolicyKey\": \"$eh_key\"
          }
        }" \
        --serialization '{
          "type": "Json",
          "properties": {
            "encoding": "UTF8"
          }
        }'
    
    # Get Cosmos DB connection details
    local cosmos_key=$(az cosmosdb keys list \
        --name "$COSMOS_DB_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryMasterKey --output tsv)
    
    # Configure output
    az stream-analytics output create \
        --job-name "$STREAM_ANALYTICS_JOB" \
        --resource-group "$RESOURCE_GROUP" \
        --name "SignalOutput" \
        --datasource "{
          \"type\": \"Microsoft.Storage/DocumentDB\",
          \"properties\": {
            \"accountId\": \"$COSMOS_DB_ACCOUNT\",
            \"accountKey\": \"$cosmos_key\",
            \"database\": \"TradingSignals\",
            \"collectionNamePattern\": \"Signals\",
            \"documentId\": \"signal_id\"
          }
        }"
    
    # Create and deploy transformation query
    cat > trading_signals_query.sql << 'EOF'
WITH PriceMovements AS (
    SELECT 
        symbol,
        price,
        volume,
        LAG(price, 1) OVER (PARTITION BY symbol ORDER BY EventEnqueuedUtcTime) as prev_price,
        AVG(price) OVER (PARTITION BY symbol ORDER BY EventEnqueuedUtcTime 
            RANGE BETWEEN INTERVAL '5' MINUTE PRECEDING AND CURRENT ROW) as sma_5min,
        STDEV(price) OVER (PARTITION BY symbol ORDER BY EventEnqueuedUtcTime 
            RANGE BETWEEN INTERVAL '5' MINUTE PRECEDING AND CURRENT ROW) as volatility_5min,
        EventEnqueuedUtcTime,
        System.Timestamp() as WindowEnd
    FROM MarketDataInput
),
TradingSignals AS (
    SELECT 
        symbol,
        price,
        volume,
        prev_price,
        sma_5min,
        volatility_5min,
        CASE 
            WHEN price > prev_price * 1.02 AND volume > LAG(volume, 1) OVER (PARTITION BY symbol ORDER BY EventEnqueuedUtcTime) * 1.5 
            THEN 'STRONG_BUY'
            WHEN price > sma_5min * 1.01 AND volatility_5min < 0.02 
            THEN 'BUY'
            WHEN price < prev_price * 0.98 AND volume > LAG(volume, 1) OVER (PARTITION BY symbol ORDER BY EventEnqueuedUtcTime) * 1.5 
            THEN 'STRONG_SELL'
            WHEN price < sma_5min * 0.99 
            THEN 'SELL'
            ELSE 'HOLD'
        END as signal,
        (price - prev_price) / prev_price * 100 as price_change_pct,
        volatility_5min as risk_score,
        WindowEnd as signal_timestamp
    FROM PriceMovements
    WHERE prev_price IS NOT NULL
)
SELECT * INTO SignalOutput FROM TradingSignals
WHERE signal IN ('STRONG_BUY', 'BUY', 'STRONG_SELL', 'SELL')
EOF
    
    az stream-analytics transformation create \
        --job-name "$STREAM_ANALYTICS_JOB" \
        --resource-group "$RESOURCE_GROUP" \
        --name "TradingSignalsTransformation" \
        --streaming-units 6 \
        --query "$(cat trading_signals_query.sql)"
    
    rm -f trading_signals_query.sql
    
    log "Stream Analytics deployed successfully"
}

# Start services
start_services() {
    log "Starting services..."
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would start Stream Analytics job"
        return
    fi
    
    # Start Stream Analytics job
    az stream-analytics job start \
        --name "$STREAM_ANALYTICS_JOB" \
        --resource-group "$RESOURCE_GROUP" \
        --output-start-mode JobStartTime
    
    log "Services started successfully"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would validate deployment"
        return
    fi
    
    local validation_errors=0
    
    # Check resource group
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group $RESOURCE_GROUP not found"
        ((validation_errors++))
    fi
    
    # Check storage account
    if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        error "Storage account $STORAGE_ACCOUNT not found"
        ((validation_errors++))
    fi
    
    # Check AI Services
    if ! az cognitiveservices account show --name "$AI_SERVICES_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        error "AI Services $AI_SERVICES_NAME not found"
        ((validation_errors++))
    fi
    
    # Check Event Hubs
    if ! az eventhubs namespace show --name "$EVENT_HUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        error "Event Hubs namespace $EVENT_HUB_NAMESPACE not found"
        ((validation_errors++))
    fi
    
    # Check Cosmos DB
    if ! az cosmosdb show --name "$COSMOS_DB_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        error "Cosmos DB account $COSMOS_DB_ACCOUNT not found"
        ((validation_errors++))
    fi
    
    # Check Service Bus
    if ! az servicebus namespace show --name "$SERVICE_BUS_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        error "Service Bus namespace $SERVICE_BUS_NAMESPACE not found"
        ((validation_errors++))
    fi
    
    # Check Function App
    if ! az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        error "Function App $FUNCTION_APP_NAME not found"
        ((validation_errors++))
    fi
    
    # Check Stream Analytics
    if ! az stream-analytics job show --name "$STREAM_ANALYTICS_JOB" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        error "Stream Analytics job $STREAM_ANALYTICS_JOB not found"
        ((validation_errors++))
    fi
    
    if [ $validation_errors -eq 0 ]; then
        log "All resources validated successfully"
    else
        error "Validation failed with $validation_errors errors"
    fi
}

# Display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "AI Services: $AI_SERVICES_NAME"
    echo "Event Hubs Namespace: $EVENT_HUB_NAMESPACE"
    echo "Event Hub: $EVENT_HUB_NAME"
    echo "Cosmos DB Account: $COSMOS_DB_ACCOUNT"
    echo "Service Bus Namespace: $SERVICE_BUS_NAMESPACE"
    echo "Function App: $FUNCTION_APP_NAME"
    echo "Stream Analytics Job: $STREAM_ANALYTICS_JOB"
    echo ""
    
    if [ "$DRY_RUN" = false ]; then
        echo "Access URLs:"
        echo "- Azure Portal: https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
        echo "- Storage Account: https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"
        echo "- Function App: https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP_NAME"
        echo "- Stream Analytics: https://portal.azure.com/#@/resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.StreamAnalytics/streamingjobs/$STREAM_ANALYTICS_JOB"
        echo ""
        echo "Next Steps:"
        echo "1. Upload sample financial content to storage containers"
        echo "2. Configure market data feeds to send events to Event Hub"
        echo "3. Monitor Stream Analytics job for signal generation"
        echo "4. Deploy custom Function App code for content processing"
        echo "5. Set up monitoring and alerts for production workloads"
    fi
}

# Cleanup function for script interruption
cleanup() {
    warn "Deployment interrupted. Cleaning up temporary files..."
    rm -f lifecycle_policy.json trading_signals_query.sql
    exit 1
}

# Main deployment function
main() {
    log "Starting deployment of Intelligent Financial Trading Signal Analysis System"
    
    # Set up signal handlers
    trap cleanup INT TERM
    
    # Set timeout for the entire deployment
    timeout $DEPLOYMENT_TIMEOUT bash -c '
        check_prerequisites
        create_resource_group
        deploy_storage_account
        deploy_ai_services
        deploy_event_hubs
        deploy_cosmos_db
        deploy_service_bus
        deploy_function_app
        deploy_stream_analytics
        start_services
        validate_deployment
    ' || {
        error "Deployment timed out after $DEPLOYMENT_TIMEOUT seconds"
    }
    
    display_summary
    
    if [ "$DRY_RUN" = false ]; then
        log "Deployment completed successfully!"
        log "The intelligent financial trading signal analysis system is now ready for use."
    else
        log "Dry run completed. No resources were actually deployed."
    fi
}

# Run main function
main "$@"