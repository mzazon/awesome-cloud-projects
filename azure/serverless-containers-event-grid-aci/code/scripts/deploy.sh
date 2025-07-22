#!/bin/bash

# Event-Driven Serverless Container Workloads with Azure Event Grid and Container Instances
# Deployment Script
# Version: 1.0
# Last Updated: 2025-01-12

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
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $az_version"
    
    # Check if required tools are available
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Please install it."
    fi
    
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Please install it."
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set environment variables for consistent resource naming
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-event-driven-containers}"
    export LOCATION="${LOCATION:-eastus}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-steventcontainers$(openssl rand -hex 4)}"
    export CONTAINER_REGISTRY="${CONTAINER_REGISTRY:-acreventcontainers$(openssl rand -hex 4)}"
    export EVENT_GRID_TOPIC="${EVENT_GRID_TOPIC:-egt-container-events}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Store variables in a file for cleanup script
    cat > .env << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
CONTAINER_REGISTRY=$CONTAINER_REGISTRY
EVENT_GRID_TOPIC=$EVENT_GRID_TOPIC
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    info "Environment variables set:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    info "  Storage Account: $STORAGE_ACCOUNT"
    info "  Container Registry: $CONTAINER_REGISTRY"
    info "  Event Grid Topic: $EVENT_GRID_TOPIC"
    info "  Subscription ID: $SUBSCRIPTION_ID"
    info "  Random Suffix: $RANDOM_SUFFIX"
}

# Function to create foundational resources
create_foundational_resources() {
    log "Creating foundational resources..."
    
    # Create resource group for all related resources
    log "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=event-driven-containers environment=demo
    
    log "✅ Resource group created: ${RESOURCE_GROUP}"
    
    # Create storage account with Event Grid events enabled
    log "Creating storage account: $STORAGE_ACCOUNT"
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --enable-hierarchical-namespace false
    
    log "✅ Storage account created: ${STORAGE_ACCOUNT}"
    
    # Create container registry for custom images
    log "Creating container registry: $CONTAINER_REGISTRY"
    az acr create \
        --name "${CONTAINER_REGISTRY}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Basic \
        --admin-enabled true
    
    log "✅ Container registry created: ${CONTAINER_REGISTRY}"
}

# Function to create Event Grid topic
create_event_grid_topic() {
    log "Creating Azure Event Grid custom topic..."
    
    # Create custom Event Grid topic for container orchestration
    az eventgrid topic create \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --input-schema EventGridSchema
    
    # Get topic endpoint and access key for later use
    local topic_endpoint=$(az eventgrid topic show \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query endpoint --output tsv)
    
    local topic_key=$(az eventgrid topic key list \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 --output tsv)
    
    # Store topic details for later use
    echo "TOPIC_ENDPOINT=$topic_endpoint" >> .env
    echo "TOPIC_KEY=$topic_key" >> .env
    
    log "✅ Event Grid topic created with endpoint: ${topic_endpoint}"
}

# Function to create container instances
create_container_instances() {
    log "Creating container instances for event processing..."
    
    # Create container instance with webhook processing capabilities
    log "Creating event processor container instance..."
    az container create \
        --name "event-processor-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --image mcr.microsoft.com/azure-functions/dotnet:3.0 \
        --cpu 1 \
        --memory 1.5 \
        --restart-policy OnFailure \
        --environment-variables \
            STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT}" \
            EVENT_GRID_TOPIC="${EVENT_GRID_TOPIC}" \
        --ports 80 \
        --dns-name-label "event-processor-${RANDOM_SUFFIX}"
    
    # Get container instance FQDN for webhook configuration
    local container_fqdn=$(az container show \
        --name "event-processor-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query ipAddress.fqdn --output tsv)
    
    # Store container FQDN for later use
    echo "CONTAINER_FQDN=$container_fqdn" >> .env
    
    log "✅ Container instance created with FQDN: ${container_fqdn}"
}

# Function to configure storage event subscriptions
configure_storage_events() {
    log "Configuring storage account event subscriptions..."
    
    # Get container FQDN from environment file
    local container_fqdn=$(grep CONTAINER_FQDN .env | cut -d'=' -f2)
    
    # Create storage account event subscription for blob events
    log "Creating blob events subscription..."
    az eventgrid event-subscription create \
        --name "blob-events-subscription" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
        --endpoint-type webhook \
        --endpoint "https://${container_fqdn}/api/events" \
        --event-delivery-schema EventGridSchema \
        --included-event-types "Microsoft.Storage.BlobCreated" \
        --subject-begins-with "/blobServices/default/containers/input/" \
        --advanced-filter data.contentType StringContains "image"
    
    # Verify event subscription status
    local provision_state=$(az eventgrid event-subscription show \
        --name "blob-events-subscription" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
        --query provisioningState --output tsv)
    
    log "✅ Storage event subscription configured for blob events (Status: $provision_state)"
}

# Function to create storage containers and processing logic
create_storage_containers() {
    log "Creating storage containers and processing logic..."
    
    # Create storage containers for input and output data
    local storage_key=$(az storage account keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --account-name "${STORAGE_ACCOUNT}" \
        --query "[0].value" --output tsv)
    
    # Store storage key for later use
    echo "STORAGE_KEY=$storage_key" >> .env
    
    log "Creating input container..."
    az storage container create \
        --name "input" \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${storage_key}" \
        --public-access off
    
    log "Creating output container..."
    az storage container create \
        --name "output" \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${storage_key}" \
        --public-access off
    
    # Create sample processing container with custom logic
    log "Creating image processor container..."
    az container create \
        --name "image-processor-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --image mcr.microsoft.com/azure-cli:latest \
        --cpu 0.5 \
        --memory 1 \
        --restart-policy OnFailure \
        --command-line "sleep 3600" \
        --environment-variables \
            STORAGE_ACCOUNT="${STORAGE_ACCOUNT}" \
            STORAGE_KEY="${storage_key}"
    
    log "✅ Storage containers and processing container created"
}

# Function to deploy function app
deploy_function_app() {
    log "Deploying Function App for Event Grid integration..."
    
    # Create Function App for Event Grid webhook processing
    log "Creating Function App..."
    az functionapp create \
        --name "func-event-processor-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime node \
        --functions-version 4 \
        --os-type Linux
    
    # Configure function app settings for container integration
    log "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "func-event-processor-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
            CONTAINER_REGISTRY="${CONTAINER_REGISTRY}" \
            STORAGE_ACCOUNT="${STORAGE_ACCOUNT}" \
            RESOURCE_GROUP="${RESOURCE_GROUP}" \
            SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
    
    # Get function app URL for Event Grid subscription
    local function_app_url=$(az functionapp show \
        --name "func-event-processor-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query defaultHostName --output tsv)
    
    # Store function app URL for later use
    echo "FUNCTION_APP_URL=$function_app_url" >> .env
    
    log "✅ Function app created at: https://${function_app_url}"
}

# Function to configure webhook integration
configure_webhook_integration() {
    log "Configuring Event Grid webhook integration..."
    
    # Get function app URL from environment file
    local function_app_url=$(grep FUNCTION_APP_URL .env | cut -d'=' -f2)
    
    # Create Event Grid subscription to function app webhook
    log "Creating function webhook subscription..."
    az eventgrid event-subscription create \
        --name "function-webhook-subscription" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
        --endpoint-type webhook \
        --endpoint "https://${function_app_url}/api/ProcessStorageEvent" \
        --event-delivery-schema EventGridSchema \
        --included-event-types "Microsoft.Storage.BlobCreated" \
        --max-delivery-attempts 3 \
        --event-ttl 1440
    
    # Verify webhook configuration
    az eventgrid event-subscription show \
        --name "function-webhook-subscription" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
        --query "{status: provisioningState, endpoint: destination.endpointUrl}" \
        --output table
    
    log "✅ Event Grid webhook integration configured"
}

# Function to create container template
create_container_template() {
    log "Creating container instance template for dynamic scaling..."
    
    # Create container instance template for dynamic deployment
    cat > container-template.json << 'EOF'
{
    "name": "dynamic-processor-{unique_id}",
    "location": "{location}",
    "properties": {
        "containers": [
            {
                "name": "event-processor",
                "properties": {
                    "image": "mcr.microsoft.com/azure-cli:latest",
                    "resources": {
                        "requests": {
                            "cpu": 0.5,
                            "memoryInGB": 1.0
                        }
                    },
                    "environmentVariables": [
                        {
                            "name": "STORAGE_ACCOUNT",
                            "value": "{storage_account}"
                        },
                        {
                            "name": "BLOB_URL",
                            "value": "{blob_url}"
                        },
                        {
                            "name": "EVENT_TYPE",
                            "value": "{event_type}"
                        }
                    ],
                    "command": [
                        "/bin/sh",
                        "-c",
                        "echo 'Processing event for blob: ${BLOB_URL}' && sleep 30 && echo 'Processing complete'"
                    ]
                }
            }
        ],
        "restartPolicy": "Never",
        "osType": "Linux"
    }
}
EOF
    
    # Get storage key from environment file
    local storage_key=$(grep STORAGE_KEY .env | cut -d'=' -f2)
    
    # Store template in storage account for function app access
    log "Uploading container template to storage..."
    az storage blob upload \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${storage_key}" \
        --container-name "output" \
        --name "container-template.json" \
        --file container-template.json \
        --overwrite
    
    log "✅ Container instance template created and stored"
}

# Function to setup monitoring and logging
setup_monitoring() {
    log "Setting up monitoring and logging..."
    
    # Create Log Analytics workspace for container monitoring
    log "Creating Log Analytics workspace..."
    az monitor log-analytics workspace create \
        --workspace-name "law-containers-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku PerGB2018
    
    # Get workspace ID for container insights configuration
    local workspace_id=$(az monitor log-analytics workspace show \
        --workspace-name "law-containers-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query customerId --output tsv)
    
    local workspace_key=$(az monitor log-analytics workspace get-shared-keys \
        --workspace-name "law-containers-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query primarySharedKey --output tsv)
    
    # Store workspace details for later use
    echo "WORKSPACE_ID=$workspace_id" >> .env
    echo "WORKSPACE_KEY=$workspace_key" >> .env
    
    # Create action group for alerting
    log "Creating action group for alerting..."
    az monitor action-group create \
        --name "container-alerts" \
        --resource-group "${RESOURCE_GROUP}" \
        --short-name "ContainerAlerts"
    
    log "✅ Monitoring and logging configured with workspace: ${workspace_id}"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check Event Grid topic status
    log "Checking Event Grid topic status..."
    local topic_status=$(az eventgrid topic show \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query provisioningState --output tsv)
    
    if [[ "$topic_status" == "Succeeded" ]]; then
        log "✅ Event Grid topic is running successfully"
    else
        warn "Event Grid topic status: $topic_status"
    fi
    
    # Check container instance status
    log "Checking container instance status..."
    local container_status=$(az container show \
        --name "event-processor-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "containers[0].instanceView.currentState.state" --output tsv)
    
    if [[ "$container_status" == "Running" ]]; then
        log "✅ Container instance is running successfully"
    else
        warn "Container instance status: $container_status"
    fi
    
    # Check function app status
    log "Checking function app status..."
    local function_status=$(az functionapp show \
        --name "func-event-processor-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query state --output tsv)
    
    if [[ "$function_status" == "Running" ]]; then
        log "✅ Function app is running successfully"
    else
        warn "Function app status: $function_status"
    fi
    
    # List event subscriptions
    log "Checking event subscriptions..."
    az eventgrid event-subscription list \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
        --output table
    
    log "✅ Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Container Registry: $CONTAINER_REGISTRY"
    echo "Event Grid Topic: $EVENT_GRID_TOPIC"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Container Instances:"
    echo "  - event-processor-${RANDOM_SUFFIX}"
    echo "  - image-processor-${RANDOM_SUFFIX}"
    echo ""
    echo "Function App: func-event-processor-${RANDOM_SUFFIX}"
    echo ""
    echo "Event Subscriptions:"
    echo "  - blob-events-subscription"
    echo "  - function-webhook-subscription"
    echo ""
    echo "Log Analytics Workspace: law-containers-${RANDOM_SUFFIX}"
    echo ""
    info "All environment variables have been saved to .env file"
    info "Use the destroy.sh script to clean up resources when done"
    echo ""
    warn "Estimated cost: \$10-20 for testing resources"
    warn "Remember to clean up resources to avoid ongoing charges"
}

# Main deployment function
main() {
    log "Starting deployment of Event-Driven Serverless Container Workloads"
    log "================================================================="
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    create_foundational_resources
    create_event_grid_topic
    create_container_instances
    configure_storage_events
    create_storage_containers
    deploy_function_app
    configure_webhook_integration
    create_container_template
    setup_monitoring
    validate_deployment
    display_summary
    
    log "🎉 Deployment completed successfully!"
    log "You can now test the solution by uploading image files to the 'input' container"
}

# Run main function
main "$@"