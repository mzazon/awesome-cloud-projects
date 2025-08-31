#!/bin/bash

#==============================================================================
# Azure Event Grid and Functions Deployment Script
# 
# This script deploys the complete infrastructure for event notifications
# using Azure Event Grid and Azure Functions as described in the recipe.
#==============================================================================

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partially created resources..."
    
    # Remove local files if they exist
    if [[ -d "./event-processor" ]]; then
        rm -rf ./event-processor
        log_info "Removed local event-processor directory"
    fi
    
    if [[ -f "event-processor.zip" ]]; then
        rm -f event-processor.zip
        log_info "Removed deployment package"
    fi
    
    # Attempt to clean up Azure resources if resource group exists
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
            log_warning "Resource group ${RESOURCE_GROUP} exists. You may want to run destroy.sh to clean up resources."
        fi
    fi
    
    exit 1
}

trap cleanup_on_error ERR

# Configuration variables with defaults
DEFAULT_LOCATION="eastus"
LOCATION="${AZURE_LOCATION:-$DEFAULT_LOCATION}"
DRY_RUN="${DRY_RUN:-false}"

# Generate unique resource names
generate_unique_suffix() {
    # Use timestamp and random number for uniqueness
    local timestamp=$(date +%s | tail -c 5)
    local random=$(shuf -i 100-999 -n 1 2>/dev/null || echo $((RANDOM % 900 + 100)))
    echo "${timestamp}${random}"
}

# Prerequisites checking
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if curl is available for testing
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install curl for event testing."
        exit 1
    fi
    
    # Check if zip is available for function deployment
    if ! command -v zip &> /dev/null; then
        log_error "zip is not installed. Please install zip for function deployment."
        exit 1
    fi
    
    # Check if uuidgen is available (for event IDs)
    if ! command -v uuidgen &> /dev/null; then
        log_warning "uuidgen not found. Will use alternative method for generating UUIDs."
    fi
    
    # Validate location
    if ! az account list-locations --query "[?name=='${LOCATION}']" -o tsv | grep -q "${LOCATION}"; then
        log_error "Invalid Azure location: ${LOCATION}. Use 'az account list-locations -o table' to see available locations."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Generate UUID alternative if uuidgen is not available
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen
    else
        # Alternative UUID generation using Python
        python3 -c "import uuid; print(str(uuid.uuid4()))" 2>/dev/null || \
        python -c "import uuid; print(str(uuid.uuid4()))" 2>/dev/null || \
        echo "$(date +%s)-$(shuf -i 1000-9999 -n 1 2>/dev/null || echo $((RANDOM % 9000 + 1000)))"
    fi
}

# Dry run mode
if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "Running in DRY RUN mode - no resources will be created"
fi

# Display banner
echo "============================================================================="
echo "           Azure Event Grid and Functions Deployment Script"
echo "============================================================================="
echo ""

# Check prerequisites
check_prerequisites

# Set environment variables for Azure resources
RANDOM_SUFFIX=$(generate_unique_suffix)
export RESOURCE_GROUP="rg-recipe-${RANDOM_SUFFIX}"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# Set resource names with unique suffixes
export TOPIC_NAME="topic-notifications-${RANDOM_SUFFIX}"
export FUNCTION_APP_NAME="func-processor-${RANDOM_SUFFIX}"
export STORAGE_ACCOUNT="stg${RANDOM_SUFFIX}"
export SUBSCRIPTION_NAME="sub-event-processor"

log_info "Deployment Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Location: ${LOCATION}"
log_info "  Topic Name: ${TOPIC_NAME}"
log_info "  Function App: ${FUNCTION_APP_NAME}"
log_info "  Storage Account: ${STORAGE_ACCOUNT}"
log_info "  Subscription ID: ${SUBSCRIPTION_ID}"
echo ""

if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "DRY RUN: Would create resources with above configuration"
    exit 0
fi

# Confirm deployment
read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Deployment cancelled by user"
    exit 0
fi

# Step 1: Create resource group
log_info "Creating resource group..."
az group create \
    --name "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --tags purpose=recipe environment=demo
log_success "Resource group created: ${RESOURCE_GROUP}"

# Step 2: Create storage account for Function App
log_info "Creating storage account for Function App..."
az storage account create \
    --name "${STORAGE_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --access-tier Hot
log_success "Storage account created: ${STORAGE_ACCOUNT}"

# Step 3: Create Event Grid custom topic
log_info "Creating Event Grid custom topic..."
az eventgrid topic create \
    --name "${TOPIC_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --input-schema cloudeventschemav1_0

# Get topic endpoint and access key
export TOPIC_ENDPOINT=$(az eventgrid topic show \
    --name "${TOPIC_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "endpoint" --output tsv)

export TOPIC_KEY=$(az eventgrid topic key list \
    --name "${TOPIC_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "key1" --output tsv)

log_success "Event Grid topic created: ${TOPIC_NAME}"
log_info "Topic endpoint: ${TOPIC_ENDPOINT}"

# Step 4: Create Function App with Application Insights
log_info "Creating Function App with Application Insights..."
az functionapp create \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --storage-account "${STORAGE_ACCOUNT}" \
    --consumption-plan-location "${LOCATION}" \
    --runtime node \
    --runtime-version 20 \
    --functions-version 4

# Create Application Insights component
az monitor app-insights component create \
    --app "${FUNCTION_APP_NAME}" \
    --location "${LOCATION}" \
    --resource-group "${RESOURCE_GROUP}" \
    --application-type web

log_success "Function App created with Application Insights: ${FUNCTION_APP_NAME}"

# Step 5: Create and deploy function code
log_info "Creating function code..."

# Create function code directory
mkdir -p ./event-processor
cd ./event-processor

# Create package.json
cat > package.json << 'EOF'
{
  "name": "event-processor",
  "version": "1.0.0",
  "description": "Event Grid triggered function",
  "main": "src/functions/*.js",
  "dependencies": {
    "@azure/functions": "^4.5.0"
  }
}
EOF

# Create host.json
cat > host.json << 'EOF'
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "excludedTypes": "Request"
      }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.0.0, 5.0.0)"
  }
}
EOF

# Create src/functions directory
mkdir -p src/functions

# Create function implementation
cat > src/functions/eventProcessor.js << 'EOF'
const { app } = require('@azure/functions');

app.eventGrid('eventProcessor', {
    handler: (event, context) => {
        context.log('=== Event Grid Trigger Function Executed ===');
        context.log('Event Type:', event.type);
        context.log('Event Subject:', event.subject);
        context.log('Event Time:', event.time);
        context.log('Event Source:', event.source);
        context.log('Event Data:', JSON.stringify(event.data, null, 2));
        
        // Process the event data based on event type
        if (event.data && event.data.message) {
            context.log(`📧 Processing notification: ${event.data.message}`);
            
            // Simulate event processing logic
            if (event.data.priority === 'high') {
                context.log('⚡ High priority event - processing immediately');
            } else {
                context.log('📝 Standard priority event - queued for processing');
            }
        }
        
        context.log('✅ Event processed successfully');
    }
});
EOF

log_success "Function code created using v4 programming model"

# Step 6: Deploy function to Azure
log_info "Deploying function to Azure..."

# Create deployment package
zip -r ../event-processor.zip . -x "*.git/*" "node_modules/*"
cd ..

# Deploy function code
az functionapp deployment source config-zip \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${FUNCTION_APP_NAME}" \
    --src event-processor.zip

# Wait for deployment to complete
log_info "Waiting for deployment to complete..."
sleep 45

export FUNCTION_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net"
log_success "Function deployed to Azure"
log_info "Function App URL: ${FUNCTION_URL}"

# Step 7: Create Event Grid subscription
log_info "Creating Event Grid subscription..."
az eventgrid event-subscription create \
    --name "${SUBSCRIPTION_NAME}" \
    --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${TOPIC_NAME}" \
    --endpoint "${FUNCTION_URL}/runtime/webhooks/eventgrid?functionName=eventProcessor" \
    --endpoint-type webhook \
    --event-delivery-schema cloudeventschemav1_0

log_success "Event subscription created: ${SUBSCRIPTION_NAME}"

# Verify subscription status
SUBSCRIPTION_STATUS=$(az eventgrid event-subscription show \
    --name "${SUBSCRIPTION_NAME}" \
    --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${TOPIC_NAME}" \
    --query "provisioningState" --output tsv)

log_info "Subscription status: ${SUBSCRIPTION_STATUS}"

# Step 8: Send test event
log_info "Sending test event..."

# Generate test event
EVENT_ID=$(generate_uuid)
CURRENT_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)

EVENT_DATA=$(cat << EOF
[{
  "id": "${EVENT_ID}",
  "source": "recipe-demo",
  "specversion": "1.0",
  "type": "notification.created",
  "subject": "demo/notifications",
  "time": "${CURRENT_TIME}",
  "data": {
    "message": "Hello from Event Grid!",
    "priority": "high",
    "category": "demo",
    "userId": "user123"
  }
}]
EOF
)

# Send event to Event Grid topic
curl -X POST \
    -H "aeg-sas-key: ${TOPIC_KEY}" \
    -H "Content-Type: application/json" \
    -d "${EVENT_DATA}" \
    "${TOPIC_ENDPOINT}/api/events"

log_success "Test event sent to Event Grid topic"

# Save configuration for cleanup script
cat > .deployment-config << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
TOPIC_NAME=${TOPIC_NAME}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
SUBSCRIPTION_NAME=${SUBSCRIPTION_NAME}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
EOF

log_success "Deployment configuration saved to .deployment-config"

# Display summary
echo ""
echo "============================================================================="
echo "                           DEPLOYMENT COMPLETE"
echo "============================================================================="
echo ""
log_success "Azure Event Grid and Functions solution deployed successfully!"
echo ""
echo "📋 Resource Summary:"
echo "   Resource Group: ${RESOURCE_GROUP}"
echo "   Event Grid Topic: ${TOPIC_NAME}"
echo "   Function App: ${FUNCTION_APP_NAME}"
echo "   Storage Account: ${STORAGE_ACCOUNT}"
echo "   Event Subscription: ${SUBSCRIPTION_NAME}"
echo ""
echo "🌐 Portal URLs:"
echo "   Function App: https://portal.azure.com/#@/resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${FUNCTION_APP_NAME}"
echo "   Event Grid Topic: https://portal.azure.com/#@/resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${TOPIC_NAME}"
echo "   Application Insights: https://portal.azure.com/#@/resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/microsoft.insights/components/${FUNCTION_APP_NAME}"
echo ""
echo "🧪 Test the solution:"
echo "   1. Check Function App logs in the Azure Portal"
echo "   2. Send custom events using the test commands from the recipe"
echo "   3. Monitor Application Insights for detailed telemetry"
echo ""
echo "🧹 To clean up resources, run:"
echo "   ./destroy.sh"
echo ""
echo "⚠️  Remember to clean up resources when finished to avoid ongoing charges."
echo "============================================================================="