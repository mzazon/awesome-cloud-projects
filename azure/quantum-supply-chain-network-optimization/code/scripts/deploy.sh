#!/bin/bash

# Deploy script for Quantum Supply Chain Network Optimization with Azure Quantum and Digital Twins
# This script automates the deployment of a complete supply chain optimization solution
# using Azure Quantum for optimization algorithms and Azure Digital Twins for network modeling

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Banner
echo -e "${GREEN}"
echo "=================================================================="
echo "  Azure Quantum Supply Chain Optimization Deployment"
echo "=================================================================="
echo -e "${NC}"

# Prerequisites check
log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error "Not logged into Azure. Please run 'az login' first."
    exit 1
fi

# Check if openssl is available for random generation
if ! command -v openssl &> /dev/null; then
    error "OpenSSL is not available. Please install OpenSSL for random string generation."
    exit 1
fi

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    warning "Python3 is not available. Some optimization features may not work."
fi

success "Prerequisites check completed"

# Set default values and generate unique identifiers
log "Setting up environment variables..."

export LOCATION="${LOCATION:-eastus}"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
log "Generated random suffix: ${RANDOM_SUFFIX}"

# Set resource names
export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-quantum-supplychain-${RANDOM_SUFFIX}}"
export QUANTUM_WORKSPACE="${QUANTUM_WORKSPACE:-quantum-workspace-${RANDOM_SUFFIX}}"
export DIGITAL_TWINS_INSTANCE="${DIGITAL_TWINS_INSTANCE:-dt-supplychain-${RANDOM_SUFFIX}}"
export FUNCTION_APP="${FUNCTION_APP:-func-optimizer-${RANDOM_SUFFIX}}"
export STREAM_ANALYTICS_JOB="${STREAM_ANALYTICS_JOB:-asa-supplychain-${RANDOM_SUFFIX}}"
export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stsupplychain${RANDOM_SUFFIX}}"
export COSMOS_ACCOUNT="${COSMOS_ACCOUNT:-cosmos-supplychain-${RANDOM_SUFFIX}}"
export EVENT_HUB_NAMESPACE="${EVENT_HUB_NAMESPACE:-eh-supplychain-${RANDOM_SUFFIX}}"
export EVENT_HUB_NAME="${EVENT_HUB_NAME:-supply-chain-events}"

# Verify location supports required services
log "Verifying location supports Azure Quantum and Digital Twins..."
SUPPORTED_LOCATIONS=("eastus" "westus2" "northeurope" "westeurope")
if [[ ! " ${SUPPORTED_LOCATIONS[@]} " =~ " ${LOCATION} " ]]; then
    warning "Location ${LOCATION} may not support all services. Recommended locations: ${SUPPORTED_LOCATIONS[*]}"
fi

# Create resource group
log "Creating resource group: ${RESOURCE_GROUP}"
if az group create \
    --name "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --tags purpose=quantum-optimization environment=demo project=supply-chain-optimization \
    --output none; then
    success "Resource group created successfully"
else
    error "Failed to create resource group"
    exit 1
fi

# Create storage account for Azure Functions
log "Creating storage account: ${STORAGE_ACCOUNT}"
if az storage account create \
    --name "${STORAGE_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --access-tier Hot \
    --https-only true \
    --min-tls-version TLS1_2 \
    --output none; then
    success "Storage account created successfully"
else
    error "Failed to create storage account"
    exit 1
fi

# Create Cosmos DB account for optimization results
log "Creating Cosmos DB account: ${COSMOS_ACCOUNT}"
if az cosmosdb create \
    --name "${COSMOS_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --kind GlobalDocumentDB \
    --default-consistency-level Session \
    --enable-automatic-failover true \
    --enable-multiple-write-locations false \
    --output none; then
    success "Cosmos DB account created successfully"
else
    error "Failed to create Cosmos DB account"
    exit 1
fi

# Create Azure Quantum workspace
log "Creating Azure Quantum workspace: ${QUANTUM_WORKSPACE}"
if az quantum workspace create \
    --resource-group "${RESOURCE_GROUP}" \
    --workspace-name "${QUANTUM_WORKSPACE}" \
    --location "${LOCATION}" \
    --storage-account "${STORAGE_ACCOUNT}" \
    --output none; then
    success "Quantum workspace created successfully"
else
    error "Failed to create Quantum workspace"
    exit 1
fi

# Add optimization providers to quantum workspace
log "Adding optimization providers to quantum workspace..."

# Add Microsoft QIO provider
if az quantum workspace provider add \
    --resource-group "${RESOURCE_GROUP}" \
    --workspace-name "${QUANTUM_WORKSPACE}" \
    --provider-id "microsoft-qio" \
    --provider-sku "standard" \
    --output none; then
    success "Microsoft QIO provider added successfully"
else
    warning "Failed to add Microsoft QIO provider - may already exist"
fi

# Add 1QBit provider if available
if az quantum workspace provider add \
    --resource-group "${RESOURCE_GROUP}" \
    --workspace-name "${QUANTUM_WORKSPACE}" \
    --provider-id "1qbit" \
    --provider-sku "standard" \
    --output none 2>/dev/null; then
    success "1QBit provider added successfully"
else
    warning "1QBit provider not available in this region - continuing with Microsoft QIO"
fi

# Create Digital Twins instance
log "Creating Azure Digital Twins instance: ${DIGITAL_TWINS_INSTANCE}"
if az dt create \
    --dt-name "${DIGITAL_TWINS_INSTANCE}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --assign-identity \
    --output none; then
    success "Digital Twins instance created successfully"
else
    error "Failed to create Digital Twins instance"
    exit 1
fi

# Get Digital Twins endpoint
DT_ENDPOINT=$(az dt show \
    --dt-name "${DIGITAL_TWINS_INSTANCE}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query hostName --output tsv)

if [ -z "$DT_ENDPOINT" ]; then
    error "Failed to get Digital Twins endpoint"
    exit 1
fi

log "Digital Twins endpoint: ${DT_ENDPOINT}"

# Create Digital Twins models
log "Creating Digital Twins models..."

# Create supplier model
cat > supplier-model.json << 'EOF'
{
  "@id": "dtmi:supplychain:Supplier;1",
  "@type": "Interface",
  "displayName": "Supplier",
  "contents": [
    {
      "@type": "Property",
      "name": "capacity",
      "schema": "double"
    },
    {
      "@type": "Property",
      "name": "location",
      "schema": "string"
    },
    {
      "@type": "Property",
      "name": "cost_per_unit",
      "schema": "double"
    },
    {
      "@type": "Telemetry",
      "name": "current_inventory",
      "schema": "double"
    }
  ]
}
EOF

# Create warehouse model
cat > warehouse-model.json << 'EOF'
{
  "@id": "dtmi:supplychain:Warehouse;1",
  "@type": "Interface",
  "displayName": "Warehouse",
  "contents": [
    {
      "@type": "Property",
      "name": "storage_capacity",
      "schema": "double"
    },
    {
      "@type": "Property",
      "name": "location",
      "schema": "string"
    },
    {
      "@type": "Telemetry",
      "name": "current_stock",
      "schema": "double"
    },
    {
      "@type": "Relationship",
      "name": "connected_to",
      "target": "dtmi:supplychain:Supplier;1"
    }
  ]
}
EOF

# Upload models to Digital Twins
if az dt model create \
    --dt-name "${DIGITAL_TWINS_INSTANCE}" \
    --models supplier-model.json warehouse-model.json \
    --output none; then
    success "Digital Twins models uploaded successfully"
else
    error "Failed to upload Digital Twins models"
    exit 1
fi

# Create Event Hub namespace and hub
log "Creating Event Hub namespace: ${EVENT_HUB_NAMESPACE}"
if az eventhubs namespace create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${EVENT_HUB_NAMESPACE}" \
    --location "${LOCATION}" \
    --sku Standard \
    --enable-auto-inflate false \
    --output none; then
    success "Event Hub namespace created successfully"
else
    error "Failed to create Event Hub namespace"
    exit 1
fi

# Create Event Hub
log "Creating Event Hub: ${EVENT_HUB_NAME}"
if az eventhubs eventhub create \
    --resource-group "${RESOURCE_GROUP}" \
    --namespace-name "${EVENT_HUB_NAMESPACE}" \
    --name "${EVENT_HUB_NAME}" \
    --partition-count 4 \
    --message-retention 1 \
    --output none; then
    success "Event Hub created successfully"
else
    error "Failed to create Event Hub"
    exit 1
fi

# Create Function App
log "Creating Function App: ${FUNCTION_APP}"
if az functionapp create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${FUNCTION_APP}" \
    --storage-account "${STORAGE_ACCOUNT}" \
    --consumption-plan-location "${LOCATION}" \
    --runtime python \
    --runtime-version 3.9 \
    --functions-version 4 \
    --assign-identity \
    --output none; then
    success "Function App created successfully"
else
    error "Failed to create Function App"
    exit 1
fi

# Get Cosmos DB connection string
log "Configuring Function App settings..."
COSMOS_CONNECTION_STRING=$(az cosmosdb keys list \
    --name "${COSMOS_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --type connection-strings \
    --query connectionStrings[0].connectionString --output tsv)

if [ -z "$COSMOS_CONNECTION_STRING" ]; then
    error "Failed to get Cosmos DB connection string"
    exit 1
fi

# Configure Function App settings
if az functionapp config appsettings set \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${FUNCTION_APP}" \
    --settings \
    "AZURE_QUANTUM_WORKSPACE=${QUANTUM_WORKSPACE}" \
    "AZURE_DIGITAL_TWINS_ENDPOINT=https://${DT_ENDPOINT}" \
    "COSMOS_CONNECTION_STRING=${COSMOS_CONNECTION_STRING}" \
    "SUBSCRIPTION_ID=${SUBSCRIPTION_ID}" \
    "RESOURCE_GROUP=${RESOURCE_GROUP}" \
    "LOCATION=${LOCATION}" \
    --output none; then
    success "Function App settings configured successfully"
else
    error "Failed to configure Function App settings"
    exit 1
fi

# Create Stream Analytics job
log "Creating Stream Analytics job: ${STREAM_ANALYTICS_JOB}"
if az stream-analytics job create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${STREAM_ANALYTICS_JOB}" \
    --location "${LOCATION}" \
    --sku Standard \
    --streaming-units 1 \
    --output none; then
    success "Stream Analytics job created successfully"
else
    error "Failed to create Stream Analytics job"
    exit 1
fi

# Create Digital Twins instances
log "Creating sample Digital Twins instances..."

# Create supplier twins
az dt twin create \
    --dt-name "${DIGITAL_TWINS_INSTANCE}" \
    --dtmi "dtmi:supplychain:Supplier;1" \
    --twin-id "supplier-001" \
    --properties '{
      "capacity": 1000,
      "location": "Dallas, TX",
      "cost_per_unit": 15.50
    }' \
    --output none

az dt twin create \
    --dt-name "${DIGITAL_TWINS_INSTANCE}" \
    --dtmi "dtmi:supplychain:Supplier;1" \
    --twin-id "supplier-002" \
    --properties '{
      "capacity": 1500,
      "location": "Chicago, IL",
      "cost_per_unit": 12.75
    }' \
    --output none

# Create warehouse twins
az dt twin create \
    --dt-name "${DIGITAL_TWINS_INSTANCE}" \
    --dtmi "dtmi:supplychain:Warehouse;1" \
    --twin-id "warehouse-001" \
    --properties '{
      "storage_capacity": 5000,
      "location": "Atlanta, GA"
    }' \
    --output none

az dt twin create \
    --dt-name "${DIGITAL_TWINS_INSTANCE}" \
    --dtmi "dtmi:supplychain:Warehouse;1" \
    --twin-id "warehouse-002" \
    --properties '{
      "storage_capacity": 3000,
      "location": "Phoenix, AZ"
    }' \
    --output none

# Create relationships
az dt twin relationship create \
    --dt-name "${DIGITAL_TWINS_INSTANCE}" \
    --twin-id "warehouse-001" \
    --relationship-id "supplier-connection-001" \
    --relationship "connected_to" \
    --target "supplier-001" \
    --output none

az dt twin relationship create \
    --dt-name "${DIGITAL_TWINS_INSTANCE}" \
    --twin-id "warehouse-002" \
    --relationship-id "supplier-connection-002" \
    --relationship "connected_to" \
    --target "supplier-002" \
    --output none

success "Sample Digital Twins instances and relationships created"

# Create Application Insights
log "Creating Application Insights for monitoring..."
INSIGHTS_NAME="insights-supplychain-${RANDOM_SUFFIX}"

if az monitor app-insights component create \
    --resource-group "${RESOURCE_GROUP}" \
    --app "${INSIGHTS_NAME}" \
    --location "${LOCATION}" \
    --application-type web \
    --output none; then
    success "Application Insights created successfully"
    
    # Get instrumentation key and configure Function App
    INSIGHTS_KEY=$(az monitor app-insights component show \
        --resource-group "${RESOURCE_GROUP}" \
        --app "${INSIGHTS_NAME}" \
        --query instrumentationKey --output tsv)
    
    if [ -n "$INSIGHTS_KEY" ]; then
        az functionapp config appsettings set \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${FUNCTION_APP}" \
            --settings "APPINSIGHTS_INSTRUMENTATIONKEY=${INSIGHTS_KEY}" \
            --output none
        success "Application Insights integrated with Function App"
    fi
else
    warning "Failed to create Application Insights - continuing without monitoring"
fi

# Create Log Analytics workspace
log "Creating Log Analytics workspace..."
LA_WORKSPACE="la-supplychain-${RANDOM_SUFFIX}"

if az monitor log-analytics workspace create \
    --resource-group "${RESOURCE_GROUP}" \
    --workspace-name "${LA_WORKSPACE}" \
    --location "${LOCATION}" \
    --sku PerGB2018 \
    --output none; then
    success "Log Analytics workspace created successfully"
else
    warning "Failed to create Log Analytics workspace - continuing without advanced logging"
fi

# Save deployment configuration
log "Saving deployment configuration..."
cat > deployment-config.json << EOF
{
  "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "resource_group": "${RESOURCE_GROUP}",
  "location": "${LOCATION}",
  "subscription_id": "${SUBSCRIPTION_ID}",
  "resources": {
    "quantum_workspace": "${QUANTUM_WORKSPACE}",
    "digital_twins_instance": "${DIGITAL_TWINS_INSTANCE}",
    "digital_twins_endpoint": "${DT_ENDPOINT}",
    "function_app": "${FUNCTION_APP}",
    "stream_analytics_job": "${STREAM_ANALYTICS_JOB}",
    "storage_account": "${STORAGE_ACCOUNT}",
    "cosmos_account": "${COSMOS_ACCOUNT}",
    "event_hub_namespace": "${EVENT_HUB_NAMESPACE}",
    "event_hub_name": "${EVENT_HUB_NAME}",
    "application_insights": "${INSIGHTS_NAME}",
    "log_analytics_workspace": "${LA_WORKSPACE}"
  }
}
EOF

# Clean up temporary files
log "Cleaning up temporary files..."
rm -f supplier-model.json warehouse-model.json

# Display deployment summary
echo -e "${GREEN}"
echo "=================================================================="
echo "  DEPLOYMENT COMPLETED SUCCESSFULLY"
echo "=================================================================="
echo -e "${NC}"

echo "Resource Group: ${RESOURCE_GROUP}"
echo "Location: ${LOCATION}"
echo ""
echo "Key Resources Created:"
echo "  • Quantum Workspace: ${QUANTUM_WORKSPACE}"
echo "  • Digital Twins: ${DIGITAL_TWINS_INSTANCE}"
echo "  • Function App: ${FUNCTION_APP}"
echo "  • Stream Analytics: ${STREAM_ANALYTICS_JOB}"
echo "  • Cosmos DB: ${COSMOS_ACCOUNT}"
echo "  • Event Hub: ${EVENT_HUB_NAMESPACE}/${EVENT_HUB_NAME}"
echo ""
echo "Digital Twins Endpoint: https://${DT_ENDPOINT}"
echo ""
echo "Configuration saved to: deployment-config.json"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Review the created resources in the Azure portal"
echo "2. Test the Digital Twins instance by querying sample data"
echo "3. Configure Stream Analytics inputs and outputs"
echo "4. Deploy quantum optimization functions"
echo "5. Test end-to-end supply chain optimization workflow"
echo ""
echo -e "${YELLOW}Estimated Monthly Cost: \$500-1000 USD${NC}"
echo "Use 'destroy.sh' to clean up all resources when finished"

success "Deployment completed successfully!"