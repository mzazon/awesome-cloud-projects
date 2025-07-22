#!/bin/bash

# Azure Content Moderation Deployment Script
# Recipe: Automated Content Safety Moderation with Logic Apps
# Version: 1.0
# Description: Deploys complete content moderation infrastructure on Azure

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Colors for output
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
}

# Banner
echo -e "${BLUE}"
echo "=================================================="
echo "  Azure Content Moderation Deployment Script"
echo "=================================================="
echo -e "${NC}"

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$DRY_RUN" == "true" ]]; then
    warning "Running in DRY-RUN mode - no resources will be created"
fi

# Default values
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP="rg-content-moderation"

# Allow override via environment variables
LOCATION=${LOCATION:-$DEFAULT_LOCATION}
RESOURCE_GROUP=${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}

# Generate unique suffix if not provided
if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
fi

# Resource names
STORAGE_ACCOUNT="stcontentmod${RANDOM_SUFFIX}"
AI_SERVICES_NAME="ai-content-safety-${RANDOM_SUFFIX}"
LOGIC_APP_NAME="logic-content-mod-${RANDOM_SUFFIX}"
EVENT_GRID_TOPIC="eg-content-${RANDOM_SUFFIX}"
FUNCTION_APP_NAME="func-content-${RANDOM_SUFFIX}"
LOG_ANALYTICS_NAME="law-content-${RANDOM_SUFFIX}"

# Prerequisites check
log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error "Please log in to Azure CLI first: az login"
    exit 1
fi

# Check if openssl is available for random generation
if ! command -v openssl &> /dev/null; then
    warning "openssl not found. Using date-based random suffix."
fi

# Get current subscription info
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
log "Using subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"

# Validate location
if ! az account list-locations --query "[?name=='${LOCATION}']" -o tsv | grep -q .; then
    error "Invalid location: ${LOCATION}"
    exit 1
fi

# Check if resource group already exists
if az group exists --name "${RESOURCE_GROUP}" --output tsv | grep -q "true"; then
    warning "Resource group ${RESOURCE_GROUP} already exists. Continuing with existing group."
else
    log "Resource group ${RESOURCE_GROUP} will be created."
fi

# Display deployment plan
echo -e "\n${BLUE}Deployment Plan:${NC}"
echo "  Resource Group: ${RESOURCE_GROUP}"
echo "  Location: ${LOCATION}"
echo "  Storage Account: ${STORAGE_ACCOUNT}"
echo "  AI Services: ${AI_SERVICES_NAME}"
echo "  Logic App: ${LOGIC_APP_NAME}"
echo "  Event Grid Topic: ${EVENT_GRID_TOPIC}"
echo "  Function App: ${FUNCTION_APP_NAME}"
echo "  Log Analytics: ${LOG_ANALYTICS_NAME}"
echo "  Random Suffix: ${RANDOM_SUFFIX}"

# Confirmation prompt
if [[ "$DRY_RUN" != "true" ]]; then
    echo -e "\n${YELLOW}Do you want to continue with the deployment? (y/N)${NC}"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user."
        exit 0
    fi
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    log "${description}..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    if eval "$cmd"; then
        success "${description} completed"
        return 0
    else
        error "${description} failed"
        return 1
    fi
}

# Cleanup function for partial deployments
cleanup_on_error() {
    error "Deployment failed. Attempting cleanup..."
    
    # Only cleanup if not in dry-run mode
    if [[ "$DRY_RUN" != "true" ]]; then
        # Check if resource group exists and was created by this script
        if az group exists --name "${RESOURCE_GROUP}" --output tsv | grep -q "true"; then
            warning "Consider running the destroy script to clean up resources"
        fi
    fi
    
    exit 1
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Start deployment
log "Starting deployment of Azure Content Moderation infrastructure..."

# Step 1: Create resource group
execute_command \
    "az group create --name '${RESOURCE_GROUP}' --location '${LOCATION}' --tags purpose=content-moderation environment=demo" \
    "Creating resource group"

# Step 2: Create storage account
execute_command \
    "az storage account create --name '${STORAGE_ACCOUNT}' --resource-group '${RESOURCE_GROUP}' --location '${LOCATION}' --sku Standard_LRS --kind StorageV2 --enable-hierarchical-namespace false" \
    "Creating storage account"

# Get storage connection string
if [[ "$DRY_RUN" != "true" ]]; then
    log "Retrieving storage connection string..."
    STORAGE_CONNECTION=$(az storage account show-connection-string --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --query connectionString -o tsv)
    success "Storage connection string retrieved"
fi

# Step 3: Create Azure AI Content Safety service
execute_command \
    "az cognitiveservices account create --name '${AI_SERVICES_NAME}' --resource-group '${RESOURCE_GROUP}' --location '${LOCATION}' --kind ContentSafety --sku S0 --yes" \
    "Creating Azure AI Content Safety service"

# Get AI service endpoint and key
if [[ "$DRY_RUN" != "true" ]]; then
    log "Retrieving AI service configuration..."
    AI_ENDPOINT=$(az cognitiveservices account show --name "${AI_SERVICES_NAME}" --resource-group "${RESOURCE_GROUP}" --query properties.endpoint -o tsv)
    AI_KEY=$(az cognitiveservices account keys list --name "${AI_SERVICES_NAME}" --resource-group "${RESOURCE_GROUP}" --query key1 -o tsv)
    success "AI service configuration retrieved"
fi

# Step 4: Create storage containers and queue
if [[ "$DRY_RUN" != "true" ]]; then
    log "Creating storage containers..."
    
    # Create containers
    az storage container create --name uploads --connection-string "${STORAGE_CONNECTION}" --public-access off
    az storage container create --name quarantine --connection-string "${STORAGE_CONNECTION}" --public-access off
    az storage container create --name approved --connection-string "${STORAGE_CONNECTION}" --public-access off
    
    # Create queue
    az storage queue create --name content-processing --connection-string "${STORAGE_CONNECTION}"
    
    success "Storage containers and queue created"
else
    log "Would create storage containers (uploads, quarantine, approved) and processing queue"
fi

# Step 5: Create Event Grid topic
execute_command \
    "az eventgrid topic create --name '${EVENT_GRID_TOPIC}' --resource-group '${RESOURCE_GROUP}' --location '${LOCATION}'" \
    "Creating Event Grid topic"

# Get Event Grid configuration
if [[ "$DRY_RUN" != "true" ]]; then
    log "Retrieving Event Grid configuration..."
    EVENT_GRID_ENDPOINT=$(az eventgrid topic show --name "${EVENT_GRID_TOPIC}" --resource-group "${RESOURCE_GROUP}" --query endpoint -o tsv)
    EVENT_GRID_KEY=$(az eventgrid topic key list --name "${EVENT_GRID_TOPIC}" --resource-group "${RESOURCE_GROUP}" --query key1 -o tsv)
    success "Event Grid configuration retrieved"
fi

# Step 6: Create Logic App
LOGIC_APP_DEFINITION='{
    "definition": {
        "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
        "contentVersion": "1.0.0.0",
        "triggers": {},
        "actions": {},
        "outputs": {}
    }
}'

execute_command \
    "az logic workflow create --name '${LOGIC_APP_NAME}' --resource-group '${RESOURCE_GROUP}' --location '${LOCATION}' --definition '${LOGIC_APP_DEFINITION}'" \
    "Creating Logic App"

# Get Logic App ID
if [[ "$DRY_RUN" != "true" ]]; then
    log "Retrieving Logic App ID..."
    LOGIC_APP_ID=$(az logic workflow show --name "${LOGIC_APP_NAME}" --resource-group "${RESOURCE_GROUP}" --query id -o tsv)
    success "Logic App ID retrieved"
fi

# Step 7: Create Event Grid subscription
if [[ "$DRY_RUN" != "true" ]]; then
    STORAGE_RESOURCE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"
    
    execute_command \
        "az eventgrid event-subscription create --name content-upload-subscription --source-resource-id '${STORAGE_RESOURCE_ID}' --endpoint-type webhook --endpoint '${EVENT_GRID_ENDPOINT}' --included-event-types Microsoft.Storage.BlobCreated --subject-begins-with '/blobServices/default/containers/uploads/'" \
        "Creating Event Grid subscription"
else
    log "Would create Event Grid subscription for blob storage events"
fi

# Step 8: Create Function App
execute_command \
    "az functionapp create --name '${FUNCTION_APP_NAME}' --resource-group '${RESOURCE_GROUP}' --storage-account '${STORAGE_ACCOUNT}' --consumption-plan-location '${LOCATION}' --runtime python --functions-version 4 --os-type Linux" \
    "Creating Function App"

# Configure Function App settings
if [[ "$DRY_RUN" != "true" ]]; then
    log "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "AI_ENDPOINT=${AI_ENDPOINT}" \
        "AI_KEY=${AI_KEY}" \
        "STORAGE_CONNECTION=${STORAGE_CONNECTION}"
    success "Function App settings configured"
else
    log "Would configure Function App with AI and storage settings"
fi

# Step 9: Create Log Analytics workspace
execute_command \
    "az monitor log-analytics workspace create --name '${LOG_ANALYTICS_NAME}' --resource-group '${RESOURCE_GROUP}' --location '${LOCATION}'" \
    "Creating Log Analytics workspace"

# Configure diagnostic settings
if [[ "$DRY_RUN" != "true" ]]; then
    log "Configuring diagnostic settings..."
    WORKSPACE_ID=$(az monitor log-analytics workspace show --name "${LOG_ANALYTICS_NAME}" --resource-group "${RESOURCE_GROUP}" --query id -o tsv)
    
    az monitor diagnostic-settings create \
        --name logic-app-diagnostics \
        --resource "${LOGIC_APP_ID}" \
        --workspace "${WORKSPACE_ID}" \
        --logs '[{"category": "WorkflowRuntime", "enabled": true}]' \
        --metrics '[{"category": "AllMetrics", "enabled": true}]'
    success "Diagnostic settings configured"
else
    log "Would configure diagnostic settings for Logic App"
fi

# Step 10: Test AI Content Safety service
if [[ "$DRY_RUN" != "true" ]]; then
    log "Testing AI Content Safety service..."
    
    TEST_RESPONSE=$(curl -s -X POST "${AI_ENDPOINT}contentsafety/text:analyze?api-version=2023-10-01" \
        -H "Ocp-Apim-Subscription-Key: ${AI_KEY}" \
        -H "Content-Type: application/json" \
        -d '{
            "text": "This is a test message for content moderation.",
            "categories": ["Hate", "Violence", "Sexual", "SelfHarm"],
            "outputType": "FourSeverityLevels"
        }' || echo "Test failed")
    
    if [[ "$TEST_RESPONSE" == *"categoriesAnalysis"* ]]; then
        success "AI Content Safety service is working correctly"
    else
        warning "AI Content Safety service test failed or returned unexpected response"
    fi
else
    log "Would test AI Content Safety service"
fi

# Save deployment configuration
if [[ "$DRY_RUN" != "true" ]]; then
    log "Saving deployment configuration..."
    
    cat > ".deployment_config" << EOF
# Azure Content Moderation Deployment Configuration
# Generated: $(date)

RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
AI_SERVICES_NAME=${AI_SERVICES_NAME}
LOGIC_APP_NAME=${LOGIC_APP_NAME}
EVENT_GRID_TOPIC=${EVENT_GRID_TOPIC}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
LOG_ANALYTICS_NAME=${LOG_ANALYTICS_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
EOF
    
    success "Deployment configuration saved to .deployment_config"
fi

# Display deployment summary
echo -e "\n${GREEN}=================================================="
echo "        Deployment Completed Successfully!"
echo -e "==================================================${NC}"
echo
echo "Resource Summary:"
echo "  Resource Group: ${RESOURCE_GROUP}"
echo "  Location: ${LOCATION}"
echo "  Storage Account: ${STORAGE_ACCOUNT}"
echo "  AI Content Safety: ${AI_SERVICES_NAME}"
echo "  Logic App: ${LOGIC_APP_NAME}"
echo "  Event Grid Topic: ${EVENT_GRID_TOPIC}"
echo "  Function App: ${FUNCTION_APP_NAME}"
echo "  Log Analytics: ${LOG_ANALYTICS_NAME}"
echo

if [[ "$DRY_RUN" != "true" ]]; then
    echo "Next Steps:"
    echo "1. Upload test content to the 'uploads' container"
    echo "2. Configure Logic App workflows in the Azure portal"
    echo "3. Monitor content moderation in Log Analytics"
    echo "4. Review quarantined content as needed"
    echo
    echo "Access your resources:"
    echo "  Portal: https://portal.azure.com"
    echo "  Resource Group: https://portal.azure.com/#@/resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
    echo
    echo "To clean up resources, run: ./destroy.sh"
else
    echo "This was a dry-run. No resources were actually created."
    echo "To perform the actual deployment, run: DRY_RUN=false ./deploy.sh"
fi

success "Deployment script completed successfully!"