#!/bin/bash

# Deploy script for Event-Driven Configuration Management with Azure App Configuration and Service Bus
# This script deploys the complete infrastructure for the configuration management solution

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

# Error handling
handle_error() {
    log_error "An error occurred on line $1. Exiting..."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Start logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

log_info "Starting deployment at $(date)"
log_info "Log file: ${LOG_FILE}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI v2.37.0 or later."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: ${az_version}"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check required tools
    local required_tools=("openssl" "zip")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed. Please install $tool and try again."
            exit 1
        fi
    done
    
    log_success "All prerequisites met"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    log_info "Generated random suffix: ${RANDOM_SUFFIX}"
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-config-management-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names with unique suffixes
    export APP_CONFIG_NAME="${APP_CONFIG_NAME:-appconfig-${RANDOM_SUFFIX}}"
    export SERVICE_BUS_NAMESPACE="${SERVICE_BUS_NAMESPACE:-sb-config-${RANDOM_SUFFIX}}"
    export SERVICE_BUS_TOPIC="${SERVICE_BUS_TOPIC:-configuration-changes}"
    export FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-config-processor-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-stconfig${RANDOM_SUFFIX}}"
    export LOGIC_APP_NAME="${LOGIC_APP_NAME:-logic-config-workflow-${RANDOM_SUFFIX}}"
    
    # Save deployment state
    cat > "${DEPLOYMENT_STATE_FILE}" << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
APP_CONFIG_NAME=${APP_CONFIG_NAME}
SERVICE_BUS_NAMESPACE=${SERVICE_BUS_NAMESPACE}
SERVICE_BUS_TOPIC=${SERVICE_BUS_TOPIC}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME}
LOGIC_APP_NAME=${LOGIC_APP_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    log_success "Environment variables configured"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "App Config: ${APP_CONFIG_NAME}"
    log_info "Service Bus: ${SERVICE_BUS_NAMESPACE}"
    log_info "Function App: ${FUNCTION_APP_NAME}"
    log_info "Storage Account: ${STORAGE_ACCOUNT_NAME}"
    log_info "Logic App: ${LOGIC_APP_NAME}"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=configuration-management environment=demo
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create App Configuration store
create_app_configuration() {
    log_info "Creating Azure App Configuration store: ${APP_CONFIG_NAME}"
    
    if az appconfig show --name "${APP_CONFIG_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "App Configuration store ${APP_CONFIG_NAME} already exists"
    else
        az appconfig create \
            --name "${APP_CONFIG_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku standard \
            --enable-public-network true
        
        log_success "App Configuration store created: ${APP_CONFIG_NAME}"
    fi
    
    # Store connection string
    export APP_CONFIG_CONNECTION_STRING=$(az appconfig credential list \
        --name "${APP_CONFIG_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[0].connectionString" \
        --output tsv)
    
    # Save connection string to state file
    echo "APP_CONFIG_CONNECTION_STRING=${APP_CONFIG_CONNECTION_STRING}" >> "${DEPLOYMENT_STATE_FILE}"
    
    log_info "App Configuration connection string retrieved"
}

# Function to create Service Bus namespace and topic
create_service_bus() {
    log_info "Creating Service Bus namespace: ${SERVICE_BUS_NAMESPACE}"
    
    if az servicebus namespace show --name "${SERVICE_BUS_NAMESPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Service Bus namespace ${SERVICE_BUS_NAMESPACE} already exists"
    else
        az servicebus namespace create \
            --name "${SERVICE_BUS_NAMESPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard
        
        log_success "Service Bus namespace created: ${SERVICE_BUS_NAMESPACE}"
    fi
    
    log_info "Creating Service Bus topic: ${SERVICE_BUS_TOPIC}"
    
    if az servicebus topic show --name "${SERVICE_BUS_TOPIC}" --namespace-name "${SERVICE_BUS_NAMESPACE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Service Bus topic ${SERVICE_BUS_TOPIC} already exists"
    else
        az servicebus topic create \
            --name "${SERVICE_BUS_TOPIC}" \
            --namespace-name "${SERVICE_BUS_NAMESPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --max-size 1024 \
            --enable-duplicate-detection true
        
        log_success "Service Bus topic created: ${SERVICE_BUS_TOPIC}"
    fi
    
    # Store connection string
    export SERVICE_BUS_CONNECTION_STRING=$(az servicebus namespace \
        authorization-rule keys list \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString \
        --output tsv)
    
    # Save connection string to state file
    echo "SERVICE_BUS_CONNECTION_STRING=${SERVICE_BUS_CONNECTION_STRING}" >> "${DEPLOYMENT_STATE_FILE}"
    
    log_info "Service Bus connection string retrieved"
}

# Function to create Service Bus subscriptions
create_service_bus_subscriptions() {
    log_info "Creating Service Bus subscriptions"
    
    local subscriptions=("web-services" "api-services" "worker-services")
    
    for subscription in "${subscriptions[@]}"; do
        log_info "Creating subscription: ${subscription}"
        
        if az servicebus topic subscription show \
            --name "${subscription}" \
            --topic-name "${SERVICE_BUS_TOPIC}" \
            --namespace-name "${SERVICE_BUS_NAMESPACE}" \
            --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_warning "Subscription ${subscription} already exists"
        else
            az servicebus topic subscription create \
                --name "${subscription}" \
                --topic-name "${SERVICE_BUS_TOPIC}" \
                --namespace-name "${SERVICE_BUS_NAMESPACE}" \
                --resource-group "${RESOURCE_GROUP}" \
                --max-delivery-count 10 \
                --lock-duration PT5M
            
            log_success "Subscription created: ${subscription}"
        fi
    done
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT_NAME}"
    
    if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account ${STORAGE_ACCOUNT_NAME} already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot
        
        log_success "Storage account created: ${STORAGE_ACCOUNT_NAME}"
    fi
    
    # Get storage account connection string
    export STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString \
        --output tsv)
    
    # Save connection string to state file
    echo "STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION_STRING}" >> "${DEPLOYMENT_STATE_FILE}"
    
    log_info "Storage account connection string retrieved"
}

# Function to create Function App
create_function_app() {
    log_info "Creating Function App: ${FUNCTION_APP_NAME}"
    
    if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Function App ${FUNCTION_APP_NAME} already exists"
    else
        az functionapp create \
            --name "${FUNCTION_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT_NAME}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime node \
            --runtime-version 18 \
            --functions-version 4
        
        log_success "Function App created: ${FUNCTION_APP_NAME}"
    fi
    
    log_info "Configuring Function App settings"
    
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "ServiceBusConnection=${SERVICE_BUS_CONNECTION_STRING}" \
        "AppConfigConnection=${APP_CONFIG_CONNECTION_STRING}"
    
    log_success "Function App settings configured"
}

# Function to create Logic App
create_logic_app() {
    log_info "Creating Logic App: ${LOGIC_APP_NAME}"
    
    if az logic workflow show --name "${LOGIC_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Logic App ${LOGIC_APP_NAME} already exists"
    else
        az logic workflow create \
            --name "${LOGIC_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --definition '{
              "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
              "contentVersion": "1.0.0.0",
              "parameters": {},
              "triggers": {
                "When_a_message_is_received": {
                  "type": "ServiceBus",
                  "inputs": {
                    "host": {
                      "connection": {
                        "name": "@parameters(\"$connections\")[\"servicebus\"][\"connectionId\"]"
                      }
                    },
                    "method": "get",
                    "path": "/topics/@{encodeURIComponent(\"'"${SERVICE_BUS_TOPIC}"'\")}/subscriptions/@{encodeURIComponent(\"worker-services\")}/messages/head",
                    "queries": {
                      "subscriptionType": "Main"
                    }
                  }
                }
              },
              "actions": {
                "Process_Configuration_Change": {
                  "type": "Http",
                  "inputs": {
                    "method": "POST",
                    "uri": "https://example.com/webhook",
                    "body": "@triggerBody()"
                  }
                }
              }
            }'
        
        log_success "Logic App created: ${LOGIC_APP_NAME}"
    fi
}

# Function to create Event Grid subscription
create_event_grid_subscription() {
    log_info "Creating Event Grid subscription"
    
    # Get Service Bus topic resource ID
    export SERVICE_BUS_TOPIC_ID=$(az servicebus topic show \
        --name "${SERVICE_BUS_TOPIC}" \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id \
        --output tsv)
    
    # Save topic ID to state file
    echo "SERVICE_BUS_TOPIC_ID=${SERVICE_BUS_TOPIC_ID}" >> "${DEPLOYMENT_STATE_FILE}"
    
    local subscription_name="config-changes-to-servicebus"
    
    if az eventgrid event-subscription show \
        --name "${subscription_name}" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.AppConfiguration/configurationStores/${APP_CONFIG_NAME}" &> /dev/null; then
        log_warning "Event Grid subscription ${subscription_name} already exists"
    else
        az eventgrid event-subscription create \
            --name "${subscription_name}" \
            --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.AppConfiguration/configurationStores/${APP_CONFIG_NAME}" \
            --endpoint-type servicebustopic \
            --endpoint "${SERVICE_BUS_TOPIC_ID}" \
            --included-event-types \
            "Microsoft.AppConfiguration.KeyValueModified" \
            "Microsoft.AppConfiguration.KeyValueDeleted" \
            --subject-begins-with "config/"
        
        log_success "Event Grid subscription created: ${subscription_name}"
    fi
    
    # Save subscription name to state file
    echo "EVENT_GRID_SUBSCRIPTION=${subscription_name}" >> "${DEPLOYMENT_STATE_FILE}"
}

# Function to create sample configuration
create_sample_configuration() {
    log_info "Creating sample configuration keys"
    
    # Create sample configuration keys
    az appconfig kv set \
        --name "${APP_CONFIG_NAME}" \
        --key "config/web/app-title" \
        --value "My Web Application" \
        --content-type "text/plain" \
        --yes
    
    az appconfig kv set \
        --name "${APP_CONFIG_NAME}" \
        --key "config/api/max-connections" \
        --value "100" \
        --content-type "application/json" \
        --yes
    
    az appconfig kv set \
        --name "${APP_CONFIG_NAME}" \
        --key "config/worker/batch-size" \
        --value "50" \
        --content-type "application/json" \
        --yes
    
    # Create a feature flag
    az appconfig feature set \
        --name "${APP_CONFIG_NAME}" \
        --feature "config/features/enable-notifications" \
        --yes
    
    log_success "Sample configuration keys and feature flag created"
}

# Function to deploy function code
deploy_function_code() {
    log_info "Deploying Function code"
    
    local temp_dir="/tmp/function-code-${RANDOM_SUFFIX}"
    mkdir -p "${temp_dir}"
    cd "${temp_dir}"
    
    # Create function.json
    cat > function.json << 'EOF'
{
  "bindings": [
    {
      "name": "mySbMsg",
      "type": "serviceBusTrigger",
      "direction": "in",
      "topicName": "configuration-changes",
      "subscriptionName": "web-services",
      "connection": "ServiceBusConnection"
    }
  ]
}
EOF
    
    # Create index.js
    cat > index.js << 'EOF'
module.exports = async function (context, mySbMsg) {
    context.log('Configuration change event received:', mySbMsg);
    
    // Parse the event data
    const eventData = mySbMsg.data || mySbMsg;
    context.log('Event data:', eventData);
    
    // Process configuration change
    if (eventData.key && eventData.key.startsWith('config/')) {
        context.log(`Processing configuration change for key: ${eventData.key}`);
        
        // Here you would implement logic to:
        // 1. Retrieve the new configuration value
        // 2. Update dependent services
        // 3. Log the configuration change
        
        context.log('Configuration change processed successfully');
    }
};
EOF
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "config-processor",
  "version": "1.0.0",
  "description": "Configuration change processor",
  "main": "index.js",
  "dependencies": {
    "@azure/app-configuration": "^1.4.0"
  }
}
EOF
    
    # Create deployment package
    zip -r function.zip .
    
    # Deploy function code
    az functionapp deployment source config-zip \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --src function.zip
    
    log_success "Function code deployed"
    
    # Cleanup
    cd "${SCRIPT_DIR}"
    rm -rf "${temp_dir}"
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check App Configuration store
    local app_config_status=$(az appconfig show \
        --name "${APP_CONFIG_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query provisioningState \
        --output tsv)
    
    if [[ "${app_config_status}" == "Succeeded" ]]; then
        log_success "App Configuration store is ready"
    else
        log_warning "App Configuration store status: ${app_config_status}"
    fi
    
    # Check Service Bus namespace
    local sb_status=$(az servicebus namespace show \
        --name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query status \
        --output tsv)
    
    if [[ "${sb_status}" == "Active" ]]; then
        log_success "Service Bus namespace is active"
    else
        log_warning "Service Bus namespace status: ${sb_status}"
    fi
    
    # Check Function App
    local func_status=$(az functionapp show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query state \
        --output tsv)
    
    if [[ "${func_status}" == "Running" ]]; then
        log_success "Function App is running"
    else
        log_warning "Function App status: ${func_status}"
    fi
    
    log_success "Deployment verification completed"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo ""
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "App Configuration: ${APP_CONFIG_NAME}"
    echo "Service Bus Namespace: ${SERVICE_BUS_NAMESPACE}"
    echo "Service Bus Topic: ${SERVICE_BUS_TOPIC}"
    echo "Function App: ${FUNCTION_APP_NAME}"
    echo "Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "Logic App: ${LOGIC_APP_NAME}"
    echo ""
    echo "Deployment state saved to: ${DEPLOYMENT_STATE_FILE}"
    echo "Deployment logs saved to: ${LOG_FILE}"
    echo ""
    log_success "Event-driven configuration management system deployed successfully!"
    echo ""
    log_info "Next steps:"
    echo "1. Test the configuration change flow by updating values in App Configuration"
    echo "2. Monitor Function App logs to see event processing"
    echo "3. Customize the Function code for your specific use case"
    echo ""
    log_warning "Don't forget to run destroy.sh when you're done to avoid ongoing charges"
}

# Main deployment function
main() {
    log_info "Starting Azure Event-Driven Configuration Management deployment"
    
    check_prerequisites
    setup_environment
    create_resource_group
    create_app_configuration
    create_service_bus
    create_service_bus_subscriptions
    create_storage_account
    create_function_app
    create_logic_app
    create_event_grid_subscription
    create_sample_configuration
    deploy_function_code
    verify_deployment
    display_summary
    
    log_success "Deployment completed successfully at $(date)"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi