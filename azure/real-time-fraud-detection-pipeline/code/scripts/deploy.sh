#!/bin/bash

# Real-Time Fraud Detection Pipeline Deployment Script
# This script deploys Azure Stream Analytics, Event Hubs, Machine Learning,
# Azure Functions, and Cosmos DB for fraud detection

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$ERROR_LOG" >&2
}

success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1" | tee -a "$LOG_FILE"
}

# Clean up function for error handling
cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log "Deleting resource group: ${RESOURCE_GROUP}"
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true
    fi
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Banner
echo "=================================================="
echo "Azure Fraud Detection Pipeline Deployment"
echo "=================================================="
echo ""

# Initialize log files
> "$LOG_FILE"
> "$ERROR_LOG"

log "Starting deployment process..."

# Check prerequisites
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

# Check if openssl is available for random generation
if ! command -v openssl &> /dev/null; then
    error "OpenSSL is not installed. Required for generating random values."
    exit 1
fi

# Check required Azure providers
log "Checking Azure provider registrations..."
REQUIRED_PROVIDERS=(
    "Microsoft.EventHub"
    "Microsoft.StreamAnalytics"
    "Microsoft.MachineLearningServices"
    "Microsoft.Web"
    "Microsoft.DocumentDB"
    "Microsoft.Storage"
)

for provider in "${REQUIRED_PROVIDERS[@]}"; do
    log "Checking provider: $provider"
    if ! az provider show --namespace "$provider" --query "registrationState" -o tsv | grep -q "Registered"; then
        log "Registering provider: $provider"
        az provider register --namespace "$provider" --wait
    fi
done

success "Prerequisites check completed"

# Set environment variables
log "Setting up environment variables..."

export LOCATION="eastus"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
export RESOURCE_GROUP="rg-fraud-detection-${RANDOM_SUFFIX}"

# Define resource names with consistent naming convention
export EVENT_HUB_NAMESPACE="eh-fraud-${RANDOM_SUFFIX}"
export EVENT_HUB_NAME="transactions"
export STREAM_ANALYTICS_JOB="asa-fraud-detection-${RANDOM_SUFFIX}"
export ML_WORKSPACE="ml-fraud-${RANDOM_SUFFIX}"
export FUNCTION_APP="func-fraud-alerts-${RANDOM_SUFFIX}"
export COSMOS_DB_ACCOUNT="cosmos-fraud-${RANDOM_SUFFIX}"
export STORAGE_ACCOUNT="stfraud${RANDOM_SUFFIX}"

log "Resource Group: ${RESOURCE_GROUP}"
log "Location: ${LOCATION}"
log "Random Suffix: ${RANDOM_SUFFIX}"

# Create resource group
log "Creating resource group..."
az group create \
    --name "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --tags purpose=fraud-detection environment=demo \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

success "Resource group created: ${RESOURCE_GROUP}"

# Create storage account
log "Creating storage account..."
az storage account create \
    --name "${STORAGE_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku Standard_LRS \
    --kind StorageV2 \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

success "Storage account created: ${STORAGE_ACCOUNT}"

# Create Event Hubs namespace and hub
log "Creating Event Hubs namespace..."
az eventhubs namespace create \
    --name "${EVENT_HUB_NAMESPACE}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku Standard \
    --enable-auto-inflate false \
    --maximum-throughput-units 20 \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

log "Creating Event Hub for transactions..."
az eventhubs eventhub create \
    --name "${EVENT_HUB_NAME}" \
    --namespace-name "${EVENT_HUB_NAMESPACE}" \
    --resource-group "${RESOURCE_GROUP}" \
    --partition-count 4 \
    --message-retention 7 \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

log "Creating Event Hub authorization rule..."
az eventhubs eventhub authorization-rule create \
    --name StreamAnalyticsAccess \
    --namespace-name "${EVENT_HUB_NAMESPACE}" \
    --eventhub-name "${EVENT_HUB_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --rights Send Listen \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

success "Event Hubs configured for transaction ingestion"

# Create Azure Machine Learning workspace
log "Creating Azure Machine Learning workspace..."
az ml workspace create \
    --name "${ML_WORKSPACE}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --storage-account "${STORAGE_ACCOUNT}" \
    --description "Fraud detection ML workspace" \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

log "Creating ML compute instance..."
az ml compute create \
    --name fraud-compute \
    --type ComputeInstance \
    --size Standard_DS3_v2 \
    --workspace-name "${ML_WORKSPACE}" \
    --resource-group "${RESOURCE_GROUP}" \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

success "Azure Machine Learning workspace created"

# Create Cosmos DB
log "Creating Cosmos DB account..."
az cosmosdb create \
    --name "${COSMOS_DB_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --default-consistency-level Session \
    --enable-automatic-failover true \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

log "Creating Cosmos DB database..."
az cosmosdb sql database create \
    --name fraud-detection \
    --account-name "${COSMOS_DB_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

log "Creating Cosmos DB containers..."
az cosmosdb sql container create \
    --name transactions \
    --database-name fraud-detection \
    --account-name "${COSMOS_DB_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --partition-key-path "/transactionId" \
    --throughput 400 \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

az cosmosdb sql container create \
    --name fraud-alerts \
    --database-name fraud-detection \
    --account-name "${COSMOS_DB_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --partition-key-path "/alertId" \
    --throughput 400 \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

success "Cosmos DB configured for fraud data storage"

# Create Azure Functions App
log "Creating Azure Functions App..."
az functionapp create \
    --name "${FUNCTION_APP}" \
    --resource-group "${RESOURCE_GROUP}" \
    --storage-account "${STORAGE_ACCOUNT}" \
    --consumption-plan-location "${LOCATION}" \
    --runtime node \
    --functions-version 4 \
    --os-type linux \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

log "Configuring Functions App settings..."
COSMOS_CONNECTION_STRING=$(az cosmosdb keys list \
    --name "${COSMOS_DB_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --type connection-strings \
    --query "connectionStrings[0].connectionString" \
    --output tsv)

az functionapp config appsettings set \
    --name "${FUNCTION_APP}" \
    --resource-group "${RESOURCE_GROUP}" \
    --settings "CosmosDBConnectionString=${COSMOS_CONNECTION_STRING}" \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

success "Functions app configured for fraud alert processing"

# Create Azure Stream Analytics Job
log "Creating Azure Stream Analytics job..."
az stream-analytics job create \
    --name "${STREAM_ANALYTICS_JOB}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku Standard \
    --streaming-units 3 \
    --output-start-mode JobStartTime \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

success "Stream Analytics job created successfully"

# Configure Stream Analytics inputs and outputs
log "Configuring Stream Analytics inputs..."
EVENT_HUB_KEY=$(az eventhubs eventhub authorization-rule keys list \
    --name StreamAnalyticsAccess \
    --namespace-name "${EVENT_HUB_NAMESPACE}" \
    --eventhub-name "${EVENT_HUB_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query primaryKey \
    --output tsv)

# Create temporary JSON files for Stream Analytics configuration
cat > /tmp/eventhub-input.json << EOF
{
    "type": "Microsoft.ServiceBus/EventHub",
    "properties": {
        "eventHubName": "${EVENT_HUB_NAME}",
        "serviceBusNamespace": "${EVENT_HUB_NAMESPACE}",
        "sharedAccessPolicyName": "StreamAnalyticsAccess",
        "sharedAccessPolicyKey": "${EVENT_HUB_KEY}"
    }
}
EOF

cat > /tmp/input-serialization.json << EOF
{
    "type": "Json",
    "properties": {
        "encoding": "UTF8"
    }
}
EOF

az stream-analytics input create \
    --job-name "${STREAM_ANALYTICS_JOB}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name TransactionInput \
    --type Stream \
    --datasource "$(cat /tmp/eventhub-input.json)" \
    --serialization "$(cat /tmp/input-serialization.json)" \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

log "Configuring Stream Analytics outputs..."
COSMOS_KEY=$(az cosmosdb keys list \
    --name "${COSMOS_DB_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query primaryMasterKey \
    --output tsv)

cat > /tmp/cosmos-output.json << EOF
{
    "type": "Microsoft.Storage/DocumentDB",
    "properties": {
        "accountId": "${COSMOS_DB_ACCOUNT}",
        "accountKey": "${COSMOS_KEY}",
        "database": "fraud-detection",
        "collectionNamePattern": "transactions",
        "documentId": "transactionId"
    }
}
EOF

az stream-analytics output create \
    --job-name "${STREAM_ANALYTICS_JOB}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name TransactionOutput \
    --datasource "$(cat /tmp/cosmos-output.json)" \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

cat > /tmp/function-output.json << EOF
{
    "type": "Microsoft.Web/sites/functions",
    "properties": {
        "functionAppName": "${FUNCTION_APP}",
        "functionName": "ProcessFraudAlert",
        "maxBatchCount": 100,
        "maxBatchSize": 262144
    }
}
EOF

az stream-analytics output create \
    --job-name "${STREAM_ANALYTICS_JOB}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name AlertOutput \
    --datasource "$(cat /tmp/function-output.json)" \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

success "Stream Analytics inputs and outputs configured"

# Create ML endpoint
log "Creating Machine Learning endpoint..."
az ml online-endpoint create \
    --name fraud-detection-endpoint \
    --workspace-name "${ML_WORKSPACE}" \
    --resource-group "${RESOURCE_GROUP}" \
    --auth-mode key \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

success "Machine Learning endpoint configured for fraud detection"

# Create and deploy fraud detection query
log "Creating fraud detection query..."
cat > /tmp/fraud-detection-query.sql << 'EOF'
WITH TransactionAnalysis AS (
    SELECT
        transactionId,
        userId,
        amount,
        merchantId,
        location,
        timestamp,
        -- Calculate rolling averages for comparison
        AVG(amount) OVER (
            PARTITION BY userId 
            ORDER BY timestamp ASC
            RANGE INTERVAL '24' HOUR PRECEDING
        ) as avg_daily_amount,
        COUNT(*) OVER (
            PARTITION BY userId 
            ORDER BY timestamp ASC
            RANGE INTERVAL '1' HOUR PRECEDING
        ) as hourly_transaction_count,
        -- Detect velocity patterns
        COUNT(*) OVER (
            PARTITION BY userId 
            ORDER BY timestamp ASC
            RANGE INTERVAL '10' MINUTE PRECEDING
        ) as velocity_count
    FROM TransactionInput
),

FraudScoring AS (
    SELECT
        *,
        CASE 
            WHEN amount > (avg_daily_amount * 10) THEN 50
            WHEN hourly_transaction_count > 20 THEN 40
            WHEN velocity_count > 5 THEN 60
            ELSE 0
        END as fraud_score,
        CASE 
            WHEN amount > (avg_daily_amount * 10) THEN 'UNUSUAL_AMOUNT'
            WHEN hourly_transaction_count > 20 THEN 'HIGH_FREQUENCY'
            WHEN velocity_count > 5 THEN 'RAPID_FIRE'
            ELSE 'NORMAL'
        END as fraud_reason
    FROM TransactionAnalysis
)

-- Store all transactions
SELECT * INTO TransactionOutput FROM FraudScoring;

-- Send high-risk transactions to alert system
SELECT 
    transactionId,
    userId,
    amount,
    merchantId,
    location,
    fraud_score,
    fraud_reason,
    timestamp
INTO AlertOutput 
FROM FraudScoring
WHERE fraud_score > 30;
EOF

az stream-analytics transformation create \
    --job-name "${STREAM_ANALYTICS_JOB}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name FraudDetectionTransformation \
    --streaming-units 3 \
    --query "$(cat /tmp/fraud-detection-query.sql)" \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

success "Fraud detection query deployed to Stream Analytics"

# Create fraud alert processing function code
log "Creating fraud alert processing function..."
mkdir -p /tmp/fraud-alert-function/ProcessFraudAlert

cat > /tmp/fraud-alert-function/ProcessFraudAlert/index.js << 'EOF'
const { CosmosClient } = require('@azure/cosmos');

module.exports = async function (context, req) {
    const cosmosClient = new CosmosClient(process.env.CosmosDBConnectionString);
    const database = cosmosClient.database('fraud-detection');
    const container = database.container('fraud-alerts');

    try {
        // Process fraud alert
        const alert = {
            alertId: context.executionContext.invocationId,
            transactionId: req.body.transactionId,
            userId: req.body.userId,
            fraudScore: req.body.fraud_score,
            fraudReason: req.body.fraud_reason,
            amount: req.body.amount,
            timestamp: new Date().toISOString(),
            status: 'PENDING_REVIEW',
            severity: req.body.fraud_score > 50 ? 'HIGH' : 'MEDIUM'
        };

        // Store alert in Cosmos DB
        await container.items.create(alert);

        // Send notification (placeholder for actual notification logic)
        context.log(`Fraud alert created: ${alert.alertId}`);
        context.log(`Transaction: ${alert.transactionId}, Score: ${alert.fraudScore}`);

        context.res = {
            status: 200,
            body: { 
                message: 'Fraud alert processed successfully',
                alertId: alert.alertId 
            }
        };
    } catch (error) {
        context.log.error('Error processing fraud alert:', error);
        context.res = {
            status: 500,
            body: { error: 'Failed to process fraud alert' }
        };
    }
};
EOF

cat > /tmp/fraud-alert-function/ProcessFraudAlert/function.json << 'EOF'
{
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
            "name": "res"
        }
    ]
}
EOF

cat > /tmp/fraud-alert-function/package.json << 'EOF'
{
    "name": "fraud-alert-processor",
    "version": "1.0.0",
    "dependencies": {
        "@azure/cosmos": "^3.17.3"
    }
}
EOF

cat > /tmp/fraud-alert-function/host.json << 'EOF'
{
    "version": "2.0",
    "extensionBundle": {
        "id": "Microsoft.Azure.Functions.ExtensionBundle",
        "version": "[2.*, 3.0.0)"
    }
}
EOF

# Note: In a real deployment, you would use Azure Functions Core Tools or VS Code
# to deploy the function. For this script, we're creating the function structure.
log "Function code structure created (manual deployment required)"

# Start Stream Analytics Job
log "Starting Stream Analytics job..."
az stream-analytics job start \
    --name "${STREAM_ANALYTICS_JOB}" \
    --resource-group "${RESOURCE_GROUP}" \
    --output-start-mode JobStartTime \
    >> "$LOG_FILE" 2>> "$ERROR_LOG"

success "Stream Analytics job started successfully"

# Clean up temporary files
rm -f /tmp/eventhub-input.json /tmp/input-serialization.json
rm -f /tmp/cosmos-output.json /tmp/function-output.json
rm -f /tmp/fraud-detection-query.sql
rm -rf /tmp/fraud-alert-function

# Create environment file for testing
cat > "${SCRIPT_DIR}/../.env" << EOF
# Azure Fraud Detection Pipeline Environment Variables
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
EVENT_HUB_NAMESPACE=${EVENT_HUB_NAMESPACE}
EVENT_HUB_NAME=${EVENT_HUB_NAME}
STREAM_ANALYTICS_JOB=${STREAM_ANALYTICS_JOB}
ML_WORKSPACE=${ML_WORKSPACE}
FUNCTION_APP=${FUNCTION_APP}
COSMOS_DB_ACCOUNT=${COSMOS_DB_ACCOUNT}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF

# Generate test transaction data
cat > "${SCRIPT_DIR}/../sample-transaction.json" << EOF
{
    "transactionId": "txn-001",
    "userId": "user-123",
    "amount": 50.00,
    "merchantId": "merchant-456",
    "location": "New York",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

cat > "${SCRIPT_DIR}/../high-risk-transaction.json" << EOF
{
    "transactionId": "txn-fraud-001",
    "userId": "user-123",
    "amount": 5000.00,
    "merchantId": "merchant-456",
    "location": "Unknown",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo ""
echo "=================================================="
echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY! 🎉"
echo "=================================================="
echo ""
echo "Resource Group: ${RESOURCE_GROUP}"
echo "Location: ${LOCATION}"
echo ""
echo "📋 NEXT STEPS:"
echo "1. Deploy the Azure Function using Azure Functions Core Tools:"
echo "   cd ${SCRIPT_DIR}/../function-code/"
echo "   func azure functionapp publish ${FUNCTION_APP}"
echo ""
echo "2. Test the pipeline with sample data:"
echo "   az eventhubs eventhub send \\"
echo "     --name ${EVENT_HUB_NAME} \\"
echo "     --namespace-name ${EVENT_HUB_NAMESPACE} \\"
echo "     --resource-group ${RESOURCE_GROUP} \\"
echo "     --data \"\$(cat ${SCRIPT_DIR}/../sample-transaction.json)\""
echo ""
echo "3. Monitor the Stream Analytics job:"
echo "   az stream-analytics job show \\"
echo "     --name ${STREAM_ANALYTICS_JOB} \\"
echo "     --resource-group ${RESOURCE_GROUP}"
echo ""
echo "💰 ESTIMATED DAILY COST: \$50-100 (varies by usage)"
echo ""
echo "📄 Logs:"
echo "   Deployment: ${LOG_FILE}"
echo "   Errors: ${ERROR_LOG}"
echo "   Environment: ${SCRIPT_DIR}/../.env"
echo ""
echo "🧹 To clean up resources, run:"
echo "   ./destroy.sh"
echo ""

success "Fraud detection pipeline deployment completed successfully"