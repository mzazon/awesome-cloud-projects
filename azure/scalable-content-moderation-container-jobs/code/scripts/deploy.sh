#!/bin/bash

# Deploy Azure Content Moderation Workflow
# This script deploys the complete content moderation solution using Azure AI Content Safety and Container Apps Jobs

set -e  # Exit on any error

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
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Docker is installed (for custom container scenarios)
    if ! command -v docker &> /dev/null; then
        warn "Docker is not installed. This is only required if you plan to build custom containers."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is required for generating random suffixes."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    log "Generated random suffix: $RANDOM_SUFFIX"
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-content-moderation-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set specific resource names
    export CONTENT_SAFETY_NAME="cs-moderation-${RANDOM_SUFFIX}"
    export CONTAINER_ENV_NAME="cae-moderation-${RANDOM_SUFFIX}"
    export SERVICE_BUS_NAMESPACE="sb-moderation-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stmoderation${RANDOM_SUFFIX}"
    export CONTAINER_JOB_NAME="job-content-processor"
    export LOG_ANALYTICS_WORKSPACE="law-content-moderation-${RANDOM_SUFFIX}"
    export ACTION_GROUP_NAME="ag-content-moderation"
    
    log "Environment variables set successfully"
    log "Resource Group: $RESOURCE_GROUP"
    log "Location: $LOCATION"
    log "Subscription ID: $SUBSCRIPTION_ID"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=content-moderation environment=demo deployment=automated
    
    if [ $? -eq 0 ]; then
        log "✅ Resource group created successfully"
    else
        error "Failed to create resource group"
        exit 1
    fi
}

# Function to register resource providers
register_providers() {
    log "Registering required Azure resource providers..."
    
    local providers=(
        "Microsoft.App"
        "Microsoft.CognitiveServices"
        "Microsoft.ServiceBus"
        "Microsoft.Storage"
        "Microsoft.Insights"
        "Microsoft.OperationalInsights"
    )
    
    for provider in "${providers[@]}"; do
        log "Registering provider: $provider"
        az provider register --namespace "$provider" --wait
    done
    
    log "✅ All resource providers registered successfully"
}

# Function to create Azure AI Content Safety resource
create_content_safety() {
    log "Creating Azure AI Content Safety resource..."
    
    az cognitiveservices account create \
        --name "$CONTENT_SAFETY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind ContentSafety \
        --sku S0 \
        --assign-identity \
        --tags purpose=content-moderation component=ai-safety
    
    if [ $? -eq 0 ]; then
        log "✅ Content Safety resource created successfully"
        
        # Get endpoint and key
        export CONTENT_SAFETY_ENDPOINT=$(az cognitiveservices account show \
            --name "$CONTENT_SAFETY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query properties.endpoint --output tsv)
        
        export CONTENT_SAFETY_KEY=$(az cognitiveservices account keys list \
            --name "$CONTENT_SAFETY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query key1 --output tsv)
        
        log "Content Safety endpoint: $CONTENT_SAFETY_ENDPOINT"
        log "Content Safety key retrieved successfully"
    else
        error "Failed to create Content Safety resource"
        exit 1
    fi
}

# Function to create Service Bus namespace and queue
create_service_bus() {
    log "Creating Azure Service Bus namespace and queue..."
    
    # Create Service Bus namespace
    az servicebus namespace create \
        --name "$SERVICE_BUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard \
        --tags purpose=content-moderation component=messaging
    
    if [ $? -ne 0 ]; then
        error "Failed to create Service Bus namespace"
        exit 1
    fi
    
    # Create queue for content processing
    az servicebus queue create \
        --namespace-name "$SERVICE_BUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --name content-queue \
        --max-size 5120 \
        --default-message-time-to-live PT24H \
        --enable-dead-lettering-on-message-expiration true
    
    if [ $? -eq 0 ]; then
        log "✅ Service Bus namespace and queue created successfully"
        
        # Get Service Bus connection string
        export SERVICE_BUS_CONNECTION=$(az servicebus namespace authorization-rule keys list \
            --namespace-name "$SERVICE_BUS_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --name RootManageSharedAccessKey \
            --query primaryConnectionString --output tsv)
        
        log "Service Bus connection string retrieved successfully"
    else
        error "Failed to create Service Bus queue"
        exit 1
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating Azure Storage Account..."
    
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --min-tls-version TLS1_2 \
        --tags purpose=content-moderation component=storage
    
    if [ $? -ne 0 ]; then
        error "Failed to create storage account"
        exit 1
    fi
    
    # Create containers for results and audit logs
    az storage container create \
        --name moderation-results \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --auth-mode login \
        --public-access off
    
    az storage container create \
        --name audit-logs \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --auth-mode login \
        --public-access off
    
    if [ $? -eq 0 ]; then
        log "✅ Storage account and containers created successfully"
        
        # Get storage account connection string
        export STORAGE_CONNECTION=$(az storage account show-connection-string \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query connectionString --output tsv)
        
        log "Storage connection string retrieved successfully"
    else
        error "Failed to create storage containers"
        exit 1
    fi
}

# Function to create Container Apps environment
create_container_apps_environment() {
    log "Creating Container Apps Environment..."
    
    az containerapp env create \
        --name "$CONTAINER_ENV_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --enable-workload-profiles \
        --tags purpose=content-moderation component=compute
    
    if [ $? -ne 0 ]; then
        error "Failed to create Container Apps environment"
        exit 1
    fi
    
    # Wait for environment to be ready
    log "Waiting for Container Apps environment to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local state=$(az containerapp env show \
            --name "$CONTAINER_ENV_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query provisioningState --output tsv)
        
        if [ "$state" = "Succeeded" ]; then
            log "✅ Container Apps environment created successfully"
            break
        elif [ "$state" = "Failed" ]; then
            error "Container Apps environment creation failed"
            exit 1
        fi
        
        log "Environment state: $state. Waiting..."
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        error "Timeout waiting for Container Apps environment to be ready"
        exit 1
    fi
}

# Function to create content processing script
create_processing_script() {
    log "Creating content processing script..."
    
    cat > /tmp/process-content.sh << 'EOF'
#!/bin/bash

# Content processing script for Azure Container Apps Job
set -e

# Parse Service Bus message (simplified for demo)
CONTENT_ID=${1:-"sample-content-$(date +%s)"}
CONTENT_TEXT=${2:-"Sample content for moderation"}

echo "Processing content ID: ${CONTENT_ID}"

# Analyze content using Content Safety API
ANALYSIS_RESULT=$(curl -s -X POST \
    "${CONTENT_SAFETY_ENDPOINT}/contentsafety/text:analyze?api-version=2023-10-01" \
    -H "Ocp-Apim-Subscription-Key: ${CONTENT_SAFETY_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
        \"text\": \"${CONTENT_TEXT}\",
        \"categories\": [\"Hate\", \"SelfHarm\", \"Sexual\", \"Violence\"]
    }")

# Store results in Azure Storage
RESULT_FILE="/tmp/result-${CONTENT_ID}.json"
echo "${ANALYSIS_RESULT}" > ${RESULT_FILE}

# Upload to storage (using Azure CLI in container)
az storage blob upload \
    --file ${RESULT_FILE} \
    --name "results/${CONTENT_ID}.json" \
    --container-name moderation-results \
    --connection-string "${STORAGE_CONNECTION}" \
    --overwrite

# Create audit log entry
AUDIT_ENTRY=$(cat << AUDIT_EOF
{
    "contentId": "${CONTENT_ID}",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "action": "content_moderation",
    "result": ${ANALYSIS_RESULT},
    "processor": "container-apps-job"
}
AUDIT_EOF
)

AUDIT_FILE="/tmp/audit-${CONTENT_ID}.json"
echo "${AUDIT_ENTRY}" > ${AUDIT_FILE}

# Upload audit log
az storage blob upload \
    --file ${AUDIT_FILE} \
    --name "audit/$(date +%Y/%m/%d)/${CONTENT_ID}.json" \
    --container-name audit-logs \
    --connection-string "${STORAGE_CONNECTION}" \
    --overwrite

echo "✅ Content ${CONTENT_ID} processed and results stored"
EOF
    
    chmod +x /tmp/process-content.sh
    log "✅ Content processing script created"
}

# Function to create Container Apps job
create_container_apps_job() {
    log "Creating Container Apps Job..."
    
    # Create the container job with Service Bus trigger
    az containerapp job create \
        --name "$CONTAINER_JOB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CONTAINER_ENV_NAME" \
        --trigger-type Event \
        --replica-timeout 300 \
        --replica-retry-limit 3 \
        --parallelism 3 \
        --image "mcr.microsoft.com/azure-cli:latest" \
        --cpu 0.5 \
        --memory 1.0Gi \
        --env-vars "CONTENT_SAFETY_ENDPOINT=${CONTENT_SAFETY_ENDPOINT}" \
                   "CONTENT_SAFETY_KEY=${CONTENT_SAFETY_KEY}" \
                   "STORAGE_CONNECTION=${STORAGE_CONNECTION}" \
                   "SERVICE_BUS_CONNECTION=${SERVICE_BUS_CONNECTION}" \
        --scale-rule-name "service-bus-rule" \
        --scale-rule-type "azure-servicebus" \
        --scale-rule-metadata queueName=content-queue \
                             messageCount=5 \
                             namespace="$SERVICE_BUS_NAMESPACE" \
        --scale-rule-auth connectionFromEnv=SERVICE_BUS_CONNECTION
    
    if [ $? -eq 0 ]; then
        log "✅ Container Apps Job created successfully"
    else
        error "Failed to create Container Apps Job"
        exit 1
    fi
}

# Function to create monitoring and alerts
create_monitoring() {
    log "Creating monitoring and alerting resources..."
    
    # Create Log Analytics workspace
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --location "$LOCATION" \
        --tags purpose=content-moderation component=monitoring
    
    if [ $? -ne 0 ]; then
        error "Failed to create Log Analytics workspace"
        exit 1
    fi
    
    # Get workspace ID
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query customerId --output tsv)
    
    # Create action group for alerts
    az monitor action-group create \
        --name "$ACTION_GROUP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --short-name "ContentMod" \
        --tags purpose=content-moderation component=alerting
    
    if [ $? -ne 0 ]; then
        error "Failed to create action group"
        exit 1
    fi
    
    # Create alert rule for high queue depth
    az monitor metrics alert create \
        --name "High Content Queue Depth" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ServiceBus/namespaces/${SERVICE_BUS_NAMESPACE}" \
        --condition "avg ActiveMessages > 50" \
        --description "Alert when content queue has more than 50 messages" \
        --evaluation-frequency 1m \
        --window-size 5m \
        --action "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Insights/actionGroups/${ACTION_GROUP_NAME}" \
        --severity 2
    
    if [ $? -eq 0 ]; then
        log "✅ Monitoring and alerting configured successfully"
    else
        warn "Failed to create some monitoring resources, but deployment can continue"
    fi
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Test Content Safety API
    log "Testing Content Safety API..."
    local test_result=$(curl -s -X POST \
        "${CONTENT_SAFETY_ENDPOINT}/contentsafety/text:analyze?api-version=2023-10-01" \
        -H "Ocp-Apim-Subscription-Key: ${CONTENT_SAFETY_KEY}" \
        -H "Content-Type: application/json" \
        -d '{
            "text": "This is a test message for content safety analysis",
            "categories": ["Hate", "SelfHarm", "Sexual", "Violence"]
        }')
    
    if [[ $test_result == *"categoriesAnalysis"* ]]; then
        log "✅ Content Safety API test successful"
    else
        warn "Content Safety API test failed, but resources are deployed"
    fi
    
    # Check Service Bus queue
    log "Checking Service Bus queue..."
    local queue_status=$(az servicebus queue show \
        --namespace-name "$SERVICE_BUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --name content-queue \
        --query status --output tsv)
    
    if [ "$queue_status" = "Active" ]; then
        log "✅ Service Bus queue is active"
    else
        warn "Service Bus queue status: $queue_status"
    fi
    
    # Check Container Apps Job
    log "Checking Container Apps Job..."
    local job_status=$(az containerapp job show \
        --name "$CONTAINER_JOB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.provisioningState --output tsv)
    
    if [ "$job_status" = "Succeeded" ]; then
        log "✅ Container Apps Job is ready"
    else
        warn "Container Apps Job status: $job_status"
    fi
    
    log "✅ Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Content Safety Endpoint: $CONTENT_SAFETY_ENDPOINT"
    echo "Service Bus Namespace: $SERVICE_BUS_NAMESPACE"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "Container Apps Environment: $CONTAINER_ENV_NAME"
    echo "Container Apps Job: $CONTAINER_JOB_NAME"
    echo "Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    echo "===================="
    echo ""
    echo "Next Steps:"
    echo "1. Test the content moderation workflow by sending messages to the Service Bus queue"
    echo "2. Monitor processing through Azure Monitor and Log Analytics"
    echo "3. Review moderation results in the Azure Storage containers"
    echo "4. Configure additional alert rules based on your requirements"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting Azure Content Moderation Workflow deployment..."
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    register_providers
    create_content_safety
    create_service_bus
    create_storage_account
    create_container_apps_environment
    create_processing_script
    create_container_apps_job
    create_monitoring
    validate_deployment
    display_summary
    
    log "🎉 Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted. You may need to clean up resources manually."; exit 1' INT TERM

# Run main function
main "$@"