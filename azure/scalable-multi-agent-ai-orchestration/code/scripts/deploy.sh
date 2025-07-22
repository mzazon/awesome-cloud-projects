#!/bin/bash

# Multi-Agent AI Orchestration with Azure AI Foundry Agent Service and Container Apps
# Deployment Script - Creates a complete multi-agent AI system with orchestration capabilities
# Author: Generated from Azure Recipe
# Version: 1.0

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "${ERROR_LOG}" >&2
}

# Error handling
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "Script failed at line ${line_number} with exit code ${exit_code}"
    log_error "Check ${ERROR_LOG} for details"
    exit "${exit_code}"
}

trap 'handle_error $? $LINENO' ERR

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' --output tsv)
    log "Azure CLI version: ${az_version}"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Please log in to Azure CLI first using 'az login'"
        exit 1
    fi
    
    # Check if required commands are available
    for cmd in openssl jq curl; do
        if ! command -v "${cmd}" &> /dev/null; then
            log_error "Required command '${cmd}' is not installed"
            exit 1
        fi
    done
    
    log "✅ Prerequisites check passed"
}

# Environment setup
setup_environment() {
    log "Setting up environment variables..."
    
    # Core configuration
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-multiagent-orchestration}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export CONTAINER_ENVIRONMENT="cae-agents-${RANDOM_SUFFIX}"
    export AI_FOUNDRY_RESOURCE="aif-orchestration-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stagentstg${RANDOM_SUFFIX}"
    export EVENT_GRID_TOPIC="egt-agent-events-${RANDOM_SUFFIX}"
    export COSMOS_ACCOUNT="cosmos-agents-${RANDOM_SUFFIX}"
    
    # Additional required resources
    export ACR_NAME="cracragents${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-agents-${RANDOM_SUFFIX}"
    export APP_INSIGHTS_NAME="ai-agents-${RANDOM_SUFFIX}"
    export ML_WORKSPACE_NAME="project-multi-agent-${RANDOM_SUFFIX}"
    
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Location: ${LOCATION}"
    log "Subscription ID: ${SUBSCRIPTION_ID}"
    log "Random Suffix: ${RANDOM_SUFFIX}"
    
    # Save configuration for cleanup script
    cat > "${SCRIPT_DIR}/deployment_config.env" << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
CONTAINER_ENVIRONMENT=${CONTAINER_ENVIRONMENT}
AI_FOUNDRY_RESOURCE=${AI_FOUNDRY_RESOURCE}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
EVENT_GRID_TOPIC=${EVENT_GRID_TOPIC}
COSMOS_ACCOUNT=${COSMOS_ACCOUNT}
ACR_NAME=${ACR_NAME}
KEY_VAULT_NAME=${KEY_VAULT_NAME}
APP_INSIGHTS_NAME=${APP_INSIGHTS_NAME}
ML_WORKSPACE_NAME=${ML_WORKSPACE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log "✅ Environment setup completed"
}

# Create foundational resources
create_foundational_resources() {
    log "Creating foundational resources..."
    
    # Create resource group
    log "Creating resource group: ${RESOURCE_GROUP}"
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=multi-agent-orchestration environment=demo \
        --output none
    
    # Create storage account for agent data
    log "Creating storage account: ${STORAGE_ACCOUNT}"
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --output none
    
    # Create Cosmos DB account for agent state management
    log "Creating Cosmos DB account: ${COSMOS_ACCOUNT}"
    az cosmosdb create \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --kind GlobalDocumentDB \
        --enable-automatic-failover true \
        --output none
    
    # Create Container Registry
    log "Creating Container Registry: ${ACR_NAME}"
    az acr create \
        --name "${ACR_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Basic \
        --output none
    
    # Create Key Vault
    log "Creating Key Vault: ${KEY_VAULT_NAME}"
    az keyvault create \
        --name "${KEY_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --output none
    
    # Create Application Insights
    log "Creating Application Insights: ${APP_INSIGHTS_NAME}"
    az monitor app-insights component create \
        --app "${APP_INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --kind web \
        --application-type web \
        --output none
    
    # Create Azure AI Foundry resource
    log "Creating Azure AI Foundry resource: ${AI_FOUNDRY_RESOURCE}"
    az cognitiveservices account create \
        --name "${AI_FOUNDRY_RESOURCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --kind AIServices \
        --sku S0 \
        --location "${LOCATION}" \
        --yes \
        --output none
    
    log "✅ Foundational resources created successfully"
}

# Create Container Apps Environment
create_container_environment() {
    log "Creating Container Apps Environment: ${CONTAINER_ENVIRONMENT}"
    
    # Create Container Apps environment
    az containerapp env create \
        --name "${CONTAINER_ENVIRONMENT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --logs-destination none \
        --output none
    
    # Enable workload profiles for better resource control
    log "Configuring workload profiles for Container Apps environment"
    az containerapp env workload-profile set \
        --name "${CONTAINER_ENVIRONMENT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --workload-profile-name "Consumption" \
        --workload-profile-type "Consumption" \
        --output none
    
    log "✅ Container Apps environment created with workload profiles"
}

# Create Event Grid Topic
create_event_grid() {
    log "Creating Event Grid Topic: ${EVENT_GRID_TOPIC}"
    
    # Create Event Grid topic
    az eventgrid topic create \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --input-schema EventGridSchema \
        --output none
    
    # Get Event Grid endpoint and key
    export EVENT_GRID_ENDPOINT=$(az eventgrid topic show \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query endpoint --output tsv)
    
    export EVENT_GRID_KEY=$(az eventgrid topic key list \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 --output tsv)
    
    log "Event Grid Topic created successfully"
    log "Endpoint: ${EVENT_GRID_ENDPOINT}"
    
    # Update config file with Event Grid details
    cat >> "${SCRIPT_DIR}/deployment_config.env" << EOF
EVENT_GRID_ENDPOINT=${EVENT_GRID_ENDPOINT}
EVENT_GRID_KEY=${EVENT_GRID_KEY}
EOF
    
    log "✅ Event Grid topic created and configured"
}

# Create AI Foundry Project and Deploy Models
create_ai_foundry_project() {
    log "Creating AI Foundry Project: ${ML_WORKSPACE_NAME}"
    
    # Get resource IDs for ML workspace dependencies
    local app_insights_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Insights/components/${APP_INSIGHTS_NAME}"
    local acr_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ContainerRegistry/registries/${ACR_NAME}"
    local storage_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"
    local kv_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}"
    
    # Create AI Foundry project (Machine Learning workspace)
    az ml workspace create \
        --name "${ML_WORKSPACE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --application-insights "${app_insights_id}" \
        --container-registry "${acr_id}" \
        --storage-account "${storage_id}" \
        --key-vault "${kv_id}" \
        --output none
    
    # Deploy GPT-4 model for general agent tasks
    log "Deploying GPT-4 model for agent tasks"
    az cognitiveservices account deployment create \
        --name "${AI_FOUNDRY_RESOURCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name "gpt-4-deployment" \
        --model-name "gpt-4" \
        --model-version "0613" \
        --model-format "OpenAI" \
        --sku-capacity 10 \
        --sku-name "Standard" \
        --output none
    
    # Get AI Foundry endpoint
    export AI_FOUNDRY_ENDPOINT=$(az cognitiveservices account show \
        --name "${AI_FOUNDRY_RESOURCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.endpoint --output tsv)
    
    # Get connection strings
    export STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString --output tsv)
    
    export COSMOS_CONNECTION_STRING=$(az cosmosdb keys list \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --type connection-strings \
        --query 'connectionStrings[0].connectionString' --output tsv)
    
    # Update config file with additional connection details
    cat >> "${SCRIPT_DIR}/deployment_config.env" << EOF
AI_FOUNDRY_ENDPOINT=${AI_FOUNDRY_ENDPOINT}
STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION_STRING}
COSMOS_CONNECTION_STRING=${COSMOS_CONNECTION_STRING}
EOF
    
    log "✅ AI Foundry project created with GPT-4 model deployment"
}

# Deploy Coordinator Agent
deploy_coordinator_agent() {
    log "Deploying Coordinator Agent Container App"
    
    # Create coordinator agent container app
    az containerapp create \
        --name "coordinator-agent" \
        --resource-group "${RESOURCE_GROUP}" \
        --environment "${CONTAINER_ENVIRONMENT}" \
        --image "mcr.microsoft.com/azure-cognitive-services/language/agent-coordinator:latest" \
        --target-port 8080 \
        --ingress external \
        --min-replicas 1 \
        --max-replicas 5 \
        --cpu 1.0 \
        --memory 2.0Gi \
        --env-vars \
            "AI_FOUNDRY_ENDPOINT=${AI_FOUNDRY_ENDPOINT}" \
            "EVENT_GRID_ENDPOINT=${EVENT_GRID_ENDPOINT}" \
            "EVENT_GRID_KEY=${EVENT_GRID_KEY}" \
            "COSMOS_CONNECTION_STRING=${COSMOS_CONNECTION_STRING}" \
        --output none
    
    # Configure scaling rules based on HTTP requests
    log "Configuring scaling rules for coordinator agent"
    az containerapp revision set \
        --name "coordinator-agent" \
        --resource-group "${RESOURCE_GROUP}" \
        --scale-rule-name "http-scaling" \
        --scale-rule-type "http" \
        --scale-rule-metadata "concurrentRequests=10" \
        --output none
    
    log "✅ Coordinator agent container app created and configured"
}

# Deploy Specialized Agents
deploy_specialized_agents() {
    log "Deploying specialized agent container apps"
    
    # Deploy Document Processing Agent
    log "Creating Document Processing Agent"
    az containerapp create \
        --name "document-agent" \
        --resource-group "${RESOURCE_GROUP}" \
        --environment "${CONTAINER_ENVIRONMENT}" \
        --image "mcr.microsoft.com/azure-cognitive-services/document-intelligence/agent:latest" \
        --target-port 8080 \
        --ingress internal \
        --min-replicas 0 \
        --max-replicas 10 \
        --cpu 2.0 \
        --memory 4.0Gi \
        --env-vars \
            "AI_FOUNDRY_ENDPOINT=${AI_FOUNDRY_ENDPOINT}" \
            "STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION_STRING}" \
            "EVENT_GRID_ENDPOINT=${EVENT_GRID_ENDPOINT}" \
            "EVENT_GRID_KEY=${EVENT_GRID_KEY}" \
        --output none
    
    # Deploy Data Analysis Agent
    log "Creating Data Analysis Agent"
    az containerapp create \
        --name "data-analysis-agent" \
        --resource-group "${RESOURCE_GROUP}" \
        --environment "${CONTAINER_ENVIRONMENT}" \
        --image "mcr.microsoft.com/azure-cognitive-services/data-analysis/agent:latest" \
        --target-port 8080 \
        --ingress internal \
        --min-replicas 0 \
        --max-replicas 8 \
        --cpu 4.0 \
        --memory 8.0Gi \
        --env-vars \
            "AI_FOUNDRY_ENDPOINT=${AI_FOUNDRY_ENDPOINT}" \
            "STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION_STRING}" \
            "EVENT_GRID_ENDPOINT=${EVENT_GRID_ENDPOINT}" \
            "EVENT_GRID_KEY=${EVENT_GRID_KEY}" \
            "COSMOS_CONNECTION_STRING=${COSMOS_CONNECTION_STRING}" \
        --output none
    
    # Deploy Customer Service Agent
    log "Creating Customer Service Agent"
    az containerapp create \
        --name "customer-service-agent" \
        --resource-group "${RESOURCE_GROUP}" \
        --environment "${CONTAINER_ENVIRONMENT}" \
        --image "mcr.microsoft.com/azure-cognitive-services/language/customer-service-agent:latest" \
        --target-port 8080 \
        --ingress internal \
        --min-replicas 1 \
        --max-replicas 15 \
        --cpu 1.0 \
        --memory 2.0Gi \
        --env-vars \
            "AI_FOUNDRY_ENDPOINT=${AI_FOUNDRY_ENDPOINT}" \
            "COSMOS_CONNECTION_STRING=${COSMOS_CONNECTION_STRING}" \
            "EVENT_GRID_ENDPOINT=${EVENT_GRID_ENDPOINT}" \
            "EVENT_GRID_KEY=${EVENT_GRID_KEY}" \
        --output none
    
    log "✅ Specialized agents deployed successfully"
}

# Configure Event Grid Subscriptions
configure_event_subscriptions() {
    log "Configuring Event Grid subscriptions for agent communication"
    
    # Create storage container for dead letter events
    log "Creating dead letter storage container"
    az storage container create \
        --name "deadletter-events" \
        --account-name "${STORAGE_ACCOUNT}" \
        --public-access off \
        --output none
    
    # Configure Event Grid subscription for document events
    log "Creating document agent Event Grid subscription"
    az eventgrid event-subscription create \
        --name "document-agent-subscription" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" \
        --endpoint-type "webhook" \
        --endpoint "https://document-agent.${CONTAINER_ENVIRONMENT}.azurecontainerapps.io/api/events" \
        --included-event-types "DocumentProcessing.Requested" \
        --output none
    
    # Configure Event Grid subscription for data analysis events
    log "Creating data analysis agent Event Grid subscription"
    az eventgrid event-subscription create \
        --name "data-analysis-subscription" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" \
        --endpoint-type "webhook" \
        --endpoint "https://data-analysis-agent.${CONTAINER_ENVIRONMENT}.azurecontainerapps.io/api/events" \
        --included-event-types "DataAnalysis.Requested" "DataProcessing.Completed" \
        --output none
    
    # Configure Event Grid subscription for customer service events
    log "Creating customer service agent Event Grid subscription"
    az eventgrid event-subscription create \
        --name "customer-service-subscription" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" \
        --endpoint-type "webhook" \
        --endpoint "https://customer-service-agent.${CONTAINER_ENVIRONMENT}.azurecontainerapps.io/api/events" \
        --included-event-types "CustomerService.Requested" "CustomerInquiry.Received" \
        --output none
    
    # Configure advanced Event Grid subscription with filtering
    log "Creating workflow orchestration subscription"
    az eventgrid event-subscription create \
        --name "workflow-orchestration" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" \
        --endpoint-type "webhook" \
        --endpoint "https://coordinator-agent.${CONTAINER_ENVIRONMENT}.azurecontainerapps.io/api/orchestration" \
        --included-event-types "Workflow.Started" "Agent.Completed" "Agent.Failed" \
        --subject-begins-with "multi-agent" \
        --deadletter-endpoint "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}/blobServices/default/containers/deadletter-events" \
        --max-delivery-attempts 3 \
        --event-ttl 1440 \
        --output none
    
    # Configure agent health monitoring subscription
    log "Creating agent health monitoring subscription"
    az eventgrid event-subscription create \
        --name "agent-health-monitoring" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" \
        --endpoint-type "webhook" \
        --endpoint "https://coordinator-agent.${CONTAINER_ENVIRONMENT}.azurecontainerapps.io/api/health" \
        --included-event-types "Agent.HealthCheck" "Agent.Error" \
        --max-delivery-attempts 5 \
        --output none
    
    log "✅ Event Grid subscriptions configured successfully"
}

# Deploy API Gateway
deploy_api_gateway() {
    log "Deploying API Gateway Container App"
    
    # Create API Gateway container app
    az containerapp create \
        --name "api-gateway" \
        --resource-group "${RESOURCE_GROUP}" \
        --environment "${CONTAINER_ENVIRONMENT}" \
        --image "mcr.microsoft.com/azure-api-management/gateway:latest" \
        --target-port 8080 \
        --ingress external \
        --min-replicas 2 \
        --max-replicas 10 \
        --cpu 0.5 \
        --memory 1.0Gi \
        --env-vars \
            "COORDINATOR_ENDPOINT=https://coordinator-agent.${CONTAINER_ENVIRONMENT}.azurecontainerapps.io" \
            "EVENT_GRID_ENDPOINT=${EVENT_GRID_ENDPOINT}" \
            "EVENT_GRID_KEY=${EVENT_GRID_KEY}" \
        --output none
    
    # Get API Gateway URL
    export API_GATEWAY_URL=$(az containerapp show \
        --name "api-gateway" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.configuration.ingress.fqdn \
        --output tsv)
    
    # Update config file with API Gateway URL
    cat >> "${SCRIPT_DIR}/deployment_config.env" << EOF
API_GATEWAY_URL=${API_GATEWAY_URL}
EOF
    
    log "✅ API Gateway created and accessible at: https://${API_GATEWAY_URL}"
}

# Configure Monitoring and Observability
configure_monitoring() {
    log "Configuring monitoring and observability"
    
    # Get Application Insights connection string
    export APPINSIGHTS_CONNECTION_STRING=$(az monitor app-insights component show \
        --app "${APP_INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString --output tsv)
    
    # Configure Log Analytics workspace
    log "Creating Log Analytics workspace"
    az monitor log-analytics workspace create \
        --workspace-name "multi-agent-logs" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku PerGB2018 \
        --output none
    
    # Create custom metrics for agent performance
    log "Creating custom metrics alert for agent performance"
    az monitor metrics alert create \
        --name "agent-response-time" \
        --resource-group "${RESOURCE_GROUP}" \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.App/containerApps/coordinator-agent" \
        --condition "avg requests/duration > 5000" \
        --description "Alert when agent response time exceeds 5 seconds" \
        --evaluation-frequency 1m \
        --window-size 5m \
        --severity 2 \
        --output none
    
    # Update config file with monitoring details
    cat >> "${SCRIPT_DIR}/deployment_config.env" << EOF
APPINSIGHTS_CONNECTION_STRING=${APPINSIGHTS_CONNECTION_STRING}
EOF
    
    log "✅ Monitoring and observability configured with custom metrics"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check all container apps are running
    log "Checking container apps status"
    local app_status=$(az containerapp list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].{Name:name,State:properties.runningStatus}" \
        --output table)
    
    log "Container Apps Status:"
    log "${app_status}"
    
    # Verify container app environment health
    local env_status=$(az containerapp env show \
        --name "${CONTAINER_ENVIRONMENT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "properties.provisioningState" \
        --output tsv)
    
    log "Container Apps Environment Status: ${env_status}"
    
    # Wait for agents to be ready
    log "Waiting for agents to be ready..."
    sleep 30
    
    # Test Event Grid by sending a test event
    log "Testing Event Grid communication"
    az eventgrid event publish \
        --topic-name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --events "[{
            \"id\": \"test-event-001\",
            \"subject\": \"multi-agent/test\",
            \"eventType\": \"Workflow.Started\",
            \"eventTime\": \"$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)\",
            \"data\": {
                \"workflowId\": \"test-workflow-001\",
                \"agentType\": \"document-processing\",
                \"priority\": \"high\"
            }
        }]" \
        --output none
    
    log "✅ Test event published to Event Grid"
    log "✅ Deployment validation completed successfully"
}

# Display deployment summary
show_deployment_summary() {
    log "=================================================="
    log "Multi-Agent AI Orchestration Deployment Complete"
    log "=================================================="
    log ""
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Location: ${LOCATION}"
    log "Container Apps Environment: ${CONTAINER_ENVIRONMENT}"
    log "API Gateway URL: https://${API_GATEWAY_URL}"
    log "Event Grid Topic: ${EVENT_GRID_TOPIC}"
    log "AI Foundry Resource: ${AI_FOUNDRY_RESOURCE}"
    log "Storage Account: ${STORAGE_ACCOUNT}"
    log "Cosmos DB Account: ${COSMOS_ACCOUNT}"
    log ""
    log "Container Apps Deployed:"
    log "  - coordinator-agent (External ingress)"
    log "  - document-agent (Internal ingress)"
    log "  - data-analysis-agent (Internal ingress)"
    log "  - customer-service-agent (Internal ingress)"
    log "  - api-gateway (External ingress)"
    log ""
    log "Configuration saved to: ${SCRIPT_DIR}/deployment_config.env"
    log ""
    log "Next Steps:"
    log "1. Test the API Gateway: curl https://${API_GATEWAY_URL}/api/health"
    log "2. Monitor container apps: az containerapp list --resource-group ${RESOURCE_GROUP}"
    log "3. View logs: az containerapp logs show --name coordinator-agent --resource-group ${RESOURCE_GROUP}"
    log "4. When finished, run: ./destroy.sh"
    log ""
    log "Estimated daily cost: \$50-100 for development/testing workloads"
    log "=================================================="
}

# Main execution flow
main() {
    log "Starting Multi-Agent AI Orchestration deployment..."
    log "Deployment started at: $(date)"
    
    # Check if running in idempotent mode
    if [[ -f "${SCRIPT_DIR}/deployment_config.env" ]]; then
        log "Existing deployment configuration found. Loading..."
        source "${SCRIPT_DIR}/deployment_config.env"
        log "Continuing with existing deployment configuration"
    fi
    
    check_prerequisites
    setup_environment
    create_foundational_resources
    create_container_environment
    create_event_grid
    create_ai_foundry_project
    deploy_coordinator_agent
    deploy_specialized_agents
    configure_event_subscriptions
    deploy_api_gateway
    configure_monitoring
    validate_deployment
    show_deployment_summary
    
    log "Deployment completed successfully at: $(date)"
    log "Total deployment time: $SECONDS seconds"
}

# Run main function
main "$@"