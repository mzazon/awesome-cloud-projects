#!/bin/bash

# Azure Serverless Video Transcription - Deployment Script
# Recipe: Serverless Video Transcription with Video Indexer and Event Grid
# This script deploys a complete serverless video transcription pipeline using Azure services

set -euo pipefail

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

# Error handler
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check the logs above for details."
    exit 1
}

# Display banner
display_banner() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "  Azure Serverless Video Transcription Pipeline"
    echo "  Deployment Script v1.0"
    echo "=================================================="
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI and try again."
    fi
    
    # Check if Azure Functions Core Tools is installed
    if ! command -v func &> /dev/null; then
        log_warning "Azure Functions Core Tools not found. Will skip function deployment."
        SKIP_FUNCTIONS=true
    else
        SKIP_FUNCTIONS=false
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' and try again."
    fi
    
    # Check if Node.js is available for Functions (if deploying functions)
    if [ "$SKIP_FUNCTIONS" = false ] && ! command -v node &> /dev/null; then
        log_warning "Node.js not found. Function deployment will be skipped."
        SKIP_FUNCTIONS=true
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set required variables
    export RESOURCE_GROUP="rg-video-indexer-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export STORAGE_ACCOUNT="stvideo${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-video-${RANDOM_SUFFIX}"
    export COSMOS_ACCOUNT="cosmos-video-${RANDOM_SUFFIX}"
    export EVENT_GRID_TOPIC="eg-video-${RANDOM_SUFFIX}"
    
    # Save variables to file for destroy script
    cat > .deployment_vars << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
FUNCTION_APP=${FUNCTION_APP}
COSMOS_ACCOUNT=${COSMOS_ACCOUNT}
EVENT_GRID_TOPIC=${EVENT_GRID_TOPIC}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment variables configured"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Storage Account: ${STORAGE_ACCOUNT}"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists. Continuing..."
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=video-transcription environment=demo \
            --output none || error_exit "Failed to create resource group"
    fi
    
    log_success "Resource group created successfully"
}

# Create storage account with containers
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT}"
    
    # Create storage account
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --output none || error_exit "Failed to create storage account"
    
    # Get storage connection string
    STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString --output tsv) || error_exit "Failed to get storage connection string"
    
    # Create containers
    az storage container create \
        --name videos \
        --account-name "${STORAGE_ACCOUNT}" \
        --public-access off \
        --output none || error_exit "Failed to create videos container"
    
    az storage container create \
        --name results \
        --account-name "${STORAGE_ACCOUNT}" \
        --public-access off \
        --output none || error_exit "Failed to create results container"
    
    log_success "Storage account and containers created successfully"
}

# Create Cosmos DB account
create_cosmos_db() {
    log_info "Creating Cosmos DB account: ${COSMOS_ACCOUNT}"
    
    # Create Cosmos DB account with serverless capacity
    az cosmosdb create \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --capabilities EnableServerless \
        --default-consistency-level Session \
        --locations regionName="${LOCATION}" \
        --output none || error_exit "Failed to create Cosmos DB account"
    
    # Wait for account to be ready
    log_info "Waiting for Cosmos DB account to be ready..."
    az cosmosdb wait \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --created || error_exit "Cosmos DB account creation timeout"
    
    # Create database and container
    az cosmosdb sql database create \
        --account-name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name VideoAnalytics \
        --output none || error_exit "Failed to create Cosmos DB database"
    
    az cosmosdb sql container create \
        --account-name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --database-name VideoAnalytics \
        --name VideoMetadata \
        --partition-key-path /videoId \
        --output none || error_exit "Failed to create Cosmos DB container"
    
    # Get Cosmos DB connection string
    COSMOS_CONNECTION=$(az cosmosdb keys list \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --type connection-strings \
        --query connectionStrings[0].connectionString \
        --output tsv) || error_exit "Failed to get Cosmos DB connection string"
    
    log_success "Cosmos DB account created successfully"
}

# Prompt for Video Indexer credentials
get_video_indexer_credentials() {
    log_info "Azure Video Indexer account setup required"
    echo ""
    log_warning "MANUAL STEP REQUIRED:"
    echo "1. Navigate to https://www.videoindexer.ai/"
    echo "2. Sign in with your Azure account"
    echo "3. Create a new Video Indexer account if you don't have one"
    echo "4. Note your Account ID from the account settings"
    echo "5. Generate an API key from your profile page"
    echo ""
    
    # Prompt for credentials
    echo -n "Enter Video Indexer Account ID: "
    read -r VI_ACCOUNT_ID
    
    echo -n "Enter Video Indexer API Key: "
    read -rs VI_API_KEY
    echo ""
    
    if [[ -z "$VI_ACCOUNT_ID" || -z "$VI_API_KEY" ]]; then
        error_exit "Video Indexer credentials are required"
    fi
    
    export VI_ACCOUNT_ID
    export VI_API_KEY
    
    # Add to deployment vars file
    echo "VI_ACCOUNT_ID=${VI_ACCOUNT_ID}" >> .deployment_vars
    echo "VI_API_KEY=${VI_API_KEY}" >> .deployment_vars
    
    log_success "Video Indexer credentials configured"
}

# Create Function App
create_function_app() {
    if [ "$SKIP_FUNCTIONS" = true ]; then
        log_warning "Skipping Function App creation (prerequisites not met)"
        return
    fi
    
    log_info "Creating Function App: ${FUNCTION_APP}"
    
    # Create Function App with Node.js runtime
    az functionapp create \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime node \
        --runtime-version 18 \
        --functions-version 4 \
        --output none || error_exit "Failed to create Function App"
    
    log_success "Function App created successfully"
}

# Create Event Grid topic
create_event_grid_topic() {
    log_info "Creating Event Grid topic: ${EVENT_GRID_TOPIC}"
    
    # Create custom Event Grid topic
    az eventgrid topic create \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --output none || error_exit "Failed to create Event Grid topic"
    
    # Get topic endpoint and key
    TOPIC_ENDPOINT=$(az eventgrid topic show \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query endpoint --output tsv) || error_exit "Failed to get Event Grid endpoint"
    
    TOPIC_KEY=$(az eventgrid topic key list \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 --output tsv) || error_exit "Failed to get Event Grid key"
    
    # Add to deployment vars
    echo "TOPIC_ENDPOINT=${TOPIC_ENDPOINT}" >> .deployment_vars
    echo "TOPIC_KEY=${TOPIC_KEY}" >> .deployment_vars
    
    log_success "Event Grid topic created successfully"
}

# Configure Function App settings
configure_function_app() {
    if [ "$SKIP_FUNCTIONS" = true ]; then
        log_warning "Skipping Function App configuration"
        return
    fi
    
    log_info "Configuring Function App settings"
    
    # Configure application settings
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "STORAGE_CONNECTION=${STORAGE_CONNECTION}" \
        "COSMOS_CONNECTION=${COSMOS_CONNECTION}" \
        "VI_ACCOUNT_ID=${VI_ACCOUNT_ID}" \
        "VI_API_KEY=${VI_API_KEY}" \
        "VI_LOCATION=${LOCATION}" \
        "EVENT_GRID_TOPIC_ENDPOINT=${TOPIC_ENDPOINT}" \
        "EVENT_GRID_TOPIC_KEY=${TOPIC_KEY}" \
        --output none || error_exit "Failed to configure Function App settings"
    
    log_success "Function App configured successfully"
}

# Create event subscriptions
create_event_subscriptions() {
    if [ "$SKIP_FUNCTIONS" = true ]; then
        log_warning "Skipping Event Grid subscriptions (Function App not available)"
        return
    fi
    
    log_info "Creating Event Grid subscriptions"
    
    # Get Function App resource ID
    FUNCTION_ID=$(az functionapp show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv) || error_exit "Failed to get Function App ID"
    
    # Get Storage Account resource ID
    STORAGE_ID=$(az storage account show \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv) || error_exit "Failed to get Storage Account ID"
    
    # Create event subscription for blob uploads
    az eventgrid event-subscription create \
        --name video-upload-subscription \
        --source-resource-id "${STORAGE_ID}" \
        --endpoint "${FUNCTION_ID}/functions/ProcessVideoUpload" \
        --endpoint-type azurefunction \
        --included-event-types Microsoft.Storage.BlobCreated \
        --subject-filter --subject-begins-with /blobServices/default/containers/videos/ \
        --output none || error_exit "Failed to create blob event subscription"
    
    log_success "Event subscriptions created successfully"
}

# Deploy function code (placeholder)
deploy_function_code() {
    if [ "$SKIP_FUNCTIONS" = true ]; then
        log_warning "Skipping function code deployment"
        log_info "To deploy functions manually:"
        log_info "1. Create function project: func init --worker-runtime node"
        log_info "2. Add ProcessVideoUpload and ProcessVideoResults functions"
        log_info "3. Deploy with: func azure functionapp publish ${FUNCTION_APP}"
        return
    fi
    
    log_info "Function code deployment placeholder"
    log_warning "Manual function deployment required:"
    echo "1. Create a local function project with the Azure Functions Core Tools"
    echo "2. Add the ProcessVideoUpload and ProcessVideoResults functions"
    echo "3. Deploy using: func azure functionapp publish ${FUNCTION_APP}"
    echo ""
    echo "Refer to the recipe documentation for complete function code."
}

# Display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo -e "${BLUE}=== Deployment Summary ===${NC}"
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "Cosmos DB Account: ${COSMOS_ACCOUNT}"
    echo "Event Grid Topic: ${EVENT_GRID_TOPIC}"
    if [ "$SKIP_FUNCTIONS" = false ]; then
        echo "Function App: ${FUNCTION_APP}"
    fi
    echo ""
    echo -e "${BLUE}=== Next Steps ===${NC}"
    echo "1. Complete Video Indexer account setup at https://www.videoindexer.ai/"
    if [ "$SKIP_FUNCTIONS" = true ]; then
        echo "2. Install Azure Functions Core Tools and deploy function code"
        echo "3. Create Event Grid subscriptions manually"
    else
        echo "2. Deploy function code using Azure Functions Core Tools"
    fi
    echo "3. Upload test videos to the 'videos' container"
    echo "4. Monitor function logs for processing status"
    echo ""
    echo -e "${YELLOW}Important:${NC} Deployment variables saved to .deployment_vars"
    echo -e "${YELLOW}Run './destroy.sh' to clean up all resources${NC}"
}

# Main deployment function
main() {
    display_banner
    
    # Check for dry run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log_info "Running in dry-run mode"
        DRY_RUN=true
    else
        DRY_RUN=false
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "Would check prerequisites"
        log_info "Would set environment variables"
        log_info "Would create resource group"
        log_info "Would create storage account"
        log_info "Would create Cosmos DB"
        log_info "Would prompt for Video Indexer credentials"
        log_info "Would create Function App"
        log_info "Would create Event Grid topic"
        log_info "Would configure Function App"
        log_info "Would create event subscriptions"
        log_info "Would deploy function code"
        log_success "Dry run completed"
        return
    fi
    
    # Execute deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_storage_account
    create_cosmos_db
    get_video_indexer_credentials
    create_function_app
    create_event_grid_topic
    configure_function_app
    create_event_subscriptions
    deploy_function_code
    display_summary
}

# Run main function with all arguments
main "$@"