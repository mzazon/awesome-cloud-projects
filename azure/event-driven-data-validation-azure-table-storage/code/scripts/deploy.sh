#!/bin/bash

#######################################
# Azure Real-Time Data Validation Workflows Deployment Script
# Description: Deploys Azure Table Storage, Event Grid, Logic Apps, and Functions
# for real-time data validation workflows
#######################################

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please log in to Azure using 'az login'"
        exit 1
    fi
    
    # Check if required tools are available
    if ! command -v openssl &> /dev/null; then
        error "openssl is required but not installed"
        exit 1
    fi
    
    if ! command -v zip &> /dev/null; then
        error "zip is required but not installed"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resource names
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
        log "Generated random suffix: ${RANDOM_SUFFIX}"
    fi
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-data-validation-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set storage and validation resource names
    export STORAGE_ACCOUNT="stdataval${RANDOM_SUFFIX}"
    export TABLE_NAME="CustomerOrders"
    export VALIDATION_RULES_TABLE="ValidationRules"
    export EVENT_GRID_TOPIC="data-validation-events-${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="validation-workflow-${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="validation-functions-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_WORKSPACE="validation-monitoring-${RANDOM_SUFFIX}"
    export APP_INSIGHTS_NAME="validation-insights-${RANDOM_SUFFIX}"
    
    # Validate location
    if ! az account list-locations --query "[?name=='${LOCATION}']" --output tsv &> /dev/null; then
        error "Invalid Azure location: ${LOCATION}"
        exit 1
    fi
    
    success "Environment variables set"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: ${RESOURCE_GROUP}"
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=data-validation environment=demo \
        --output none
    
    success "Resource group created: ${RESOURCE_GROUP}"
}

# Function to create storage account and tables
create_storage_resources() {
    log "Creating storage account: ${STORAGE_ACCOUNT}"
    
    # Create storage account
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --output none
    
    # Get storage account connection string
    export STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString --output tsv)
    
    success "Storage account created: ${STORAGE_ACCOUNT}"
    
    # Create tables
    log "Creating tables in storage account..."
    
    az storage table create \
        --name "${TABLE_NAME}" \
        --connection-string "${STORAGE_CONNECTION_STRING}" \
        --output none
    
    az storage table create \
        --name "${VALIDATION_RULES_TABLE}" \
        --connection-string "${STORAGE_CONNECTION_STRING}" \
        --output none
    
    success "Tables created successfully"
}

# Function to create Event Grid topic
create_event_grid_topic() {
    log "Creating Event Grid topic: ${EVENT_GRID_TOPIC}"
    
    az eventgrid topic create \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --output none
    
    # Get Event Grid topic endpoint and key
    export TOPIC_ENDPOINT=$(az eventgrid topic show \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query endpoint --output tsv)
    
    export TOPIC_KEY=$(az eventgrid topic key list \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 --output tsv)
    
    success "Event Grid topic created: ${EVENT_GRID_TOPIC}"
}

# Function to create Function App
create_function_app() {
    log "Creating Function App: ${FUNCTION_APP_NAME}"
    
    # Create Function App
    az functionapp create \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime python \
        --runtime-version 3.11 \
        --functions-version 4 \
        --output none
    
    # Configure Function App settings
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION_STRING}" \
        "EVENT_GRID_TOPIC_ENDPOINT=${TOPIC_ENDPOINT}" \
        "EVENT_GRID_TOPIC_KEY=${TOPIC_KEY}" \
        --output none
    
    success "Function App created and configured: ${FUNCTION_APP_NAME}"
}

# Function to deploy validation function code
deploy_validation_function() {
    log "Deploying validation function code..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Create function configuration
    cat > host.json << 'EOF'
{
  "version": "2.0",
  "functionTimeout": "00:05:00",
  "extensions": {
    "eventGrid": {
      "maxBatchSize": 10,
      "prefetchCount": 100
    }
  }
}
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
azure-functions
azure-storage-table
azure-eventgrid
azure-functions-worker
EOF
    
    # Create validation function directory and configuration
    mkdir -p DataValidationFunction
    cat > DataValidationFunction/function.json << 'EOF'
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "type": "eventGridTrigger",
      "name": "event",
      "direction": "in"
    }
  ]
}
EOF
    
    # Create Python validation logic
    cat > DataValidationFunction/__init__.py << 'EOF'
import azure.functions as func
import json
import logging
import os
from azure.storage.table import TableServiceClient
from azure.eventgrid import EventGridPublisherClient

def main(event: func.EventGridEvent):
    logging.info('Data validation function triggered')
    
    # Parse event data
    event_data = event.get_json()
    
    # Validation results
    validation_results = {
        'entity_id': event_data.get('id', 'unknown'),
        'validation_status': 'valid',
        'errors': []
    }
    
    # Basic validation logic
    if 'amount' in event_data:
        try:
            amount = float(event_data['amount'])
            if amount < 0:
                validation_results['errors'].append('Amount cannot be negative')
            if amount > 10000:
                validation_results['errors'].append('Amount exceeds maximum limit')
        except ValueError:
            validation_results['errors'].append('Invalid amount format')
    
    if 'email' in event_data:
        email = event_data['email']
        if '@' not in email or '.' not in email:
            validation_results['errors'].append('Invalid email format')
    
    if 'orderId' in event_data:
        order_id = event_data['orderId']
        if not order_id or len(order_id) < 3:
            validation_results['errors'].append('Order ID must be at least 3 characters')
    
    # Set validation status
    if validation_results['errors']:
        validation_results['validation_status'] = 'invalid'
    
    # Log results
    logging.info(f'Validation results: {validation_results}')
    
    return validation_results
EOF
    
    # Create deployment package
    zip -r function-app.zip . -x "*.pyc" "__pycache__/*"
    
    # Deploy function
    az functionapp deployment source config-zip \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --src function-app.zip \
        --output none
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "${TEMP_DIR}"
    
    success "Validation function deployed successfully"
}

# Function to create Logic App
create_logic_app() {
    log "Creating Logic App: ${LOGIC_APP_NAME}"
    
    # Create Logic App with basic workflow
    az logic workflow create \
        --name "${LOGIC_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --definition '{
          "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
          "contentVersion": "1.0.0.0",
          "triggers": {
            "When_a_HTTP_request_is_received": {
              "type": "Request",
              "kind": "Http",
              "inputs": {
                "schema": {
                  "properties": {
                    "data": {
                      "properties": {
                        "amount": {"type": "number"},
                        "customerEmail": {"type": "string"},
                        "orderId": {"type": "string"}
                      },
                      "type": "object"
                    }
                  },
                  "type": "object"
                }
              }
            }
          },
          "actions": {
            "Condition": {
              "type": "If",
              "expression": {
                "and": [
                  {
                    "greater": [
                      "@triggerBody().data.amount",
                      1000
                    ]
                  }
                ]
              },
              "actions": {
                "Response": {
                  "type": "Response",
                  "inputs": {
                    "statusCode": 200,
                    "body": "High-value order detected and logged"
                  }
                }
              },
              "else": {
                "actions": {
                  "Response_2": {
                    "type": "Response",
                    "inputs": {
                      "statusCode": 200,
                      "body": "Standard order processed"
                    }
                  }
                }
              }
            }
          }
        }' \
        --output none
    
    success "Logic App workflow created successfully"
}

# Function to configure Event Grid subscriptions
configure_event_subscriptions() {
    log "Configuring Event Grid subscriptions..."
    
    # Create Event Grid subscription for Function
    az eventgrid event-subscription create \
        --name "function-validation-subscription" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
        --endpoint-type azurefunction \
        --endpoint "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${FUNCTION_APP_NAME}/functions/DataValidationFunction" \
        --included-event-types Microsoft.Storage.BlobCreated \
        --subject-begins-with "/blobServices/default/containers/tabledata" \
        --output none
    
    # Get Logic App trigger URL
    export LOGIC_APP_TRIGGER_URL=$(az logic workflow show \
        --name "${LOGIC_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "accessEndpoint" --output tsv)
    
    # Create Event Grid subscription for Logic App
    az eventgrid event-subscription create \
        --name "logicapp-validation-subscription" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" \
        --endpoint-type webhook \
        --endpoint "${LOGIC_APP_TRIGGER_URL}" \
        --event-delivery-schema eventgridschema \
        --output none
    
    success "Event Grid subscriptions configured"
}

# Function to create validation rules
create_validation_rules() {
    log "Creating validation rules in table storage..."
    
    # Insert sample validation rules into table
    az storage entity insert \
        --connection-string "${STORAGE_CONNECTION_STRING}" \
        --table-name "${VALIDATION_RULES_TABLE}" \
        --entity PartitionKey="OrderValidation" RowKey="MinAmount" \
        Rule="amount >= 1" Description="Minimum order amount validation" \
        --output none
    
    az storage entity insert \
        --connection-string "${STORAGE_CONNECTION_STRING}" \
        --table-name "${VALIDATION_RULES_TABLE}" \
        --entity PartitionKey="OrderValidation" RowKey="MaxAmount" \
        Rule="amount <= 10000" Description="Maximum order amount validation" \
        --output none
    
    az storage entity insert \
        --connection-string "${STORAGE_CONNECTION_STRING}" \
        --table-name "${VALIDATION_RULES_TABLE}" \
        --entity PartitionKey="OrderValidation" RowKey="EmailFormat" \
        Rule="email contains @" Description="Email format validation" \
        --output none
    
    success "Validation rules configured in table storage"
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring monitoring and alerting..."
    
    # Create Log Analytics workspace
    az monitor log-analytics workspace create \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --output none
    
    # Get workspace ID
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query customerId --output tsv)
    
    # Create Application Insights
    az monitor app-insights component create \
        --app "${APP_INSIGHTS_NAME}" \
        --location "${LOCATION}" \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace "${WORKSPACE_ID}" \
        --output none
    
    # Link Function App to Application Insights
    export INSIGHTS_KEY=$(az monitor app-insights component show \
        --app "${APP_INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query instrumentationKey --output tsv)
    
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "APPINSIGHTS_INSTRUMENTATIONKEY=${INSIGHTS_KEY}" \
        --output none
    
    success "Monitoring and alerting configured"
}

# Function to test deployment
test_deployment() {
    log "Testing deployment..."
    
    # Test storage account
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        success "Storage account is accessible"
    else
        error "Storage account test failed"
        return 1
    fi
    
    # Test Function App
    if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        success "Function App is accessible"
    else
        error "Function App test failed"
        return 1
    fi
    
    # Test Logic App
    if az logic workflow show --name "${LOGIC_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        success "Logic App is accessible"
    else
        error "Logic App test failed"
        return 1
    fi
    
    # Insert test data
    log "Inserting test data..."
    az storage entity insert \
        --connection-string "${STORAGE_CONNECTION_STRING}" \
        --table-name "${TABLE_NAME}" \
        --entity PartitionKey="Test" RowKey="Order001" \
        amount=1500 customerEmail="test@example.com" orderId="ORD001" \
        --output none
    
    success "Test data inserted successfully"
    success "Deployment testing completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "=================================================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "Event Grid Topic: ${EVENT_GRID_TOPIC}"
    echo "Function App: ${FUNCTION_APP_NAME}"
    echo "Logic App: ${LOGIC_APP_NAME}"
    echo "Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}"
    echo "Application Insights: ${APP_INSIGHTS_NAME}"
    echo "=================================================="
    echo "Environment variables saved to: deployment-env.sh"
    echo "Run 'source deployment-env.sh' to load environment variables"
    echo "=================================================="
    
    # Save environment variables to file
    cat > deployment-env.sh << EOF
#!/bin/bash
# Deployment environment variables
export RESOURCE_GROUP="${RESOURCE_GROUP}"
export STORAGE_ACCOUNT="${STORAGE_ACCOUNT}"
export STORAGE_CONNECTION_STRING="${STORAGE_CONNECTION_STRING}"
export EVENT_GRID_TOPIC="${EVENT_GRID_TOPIC}"
export FUNCTION_APP_NAME="${FUNCTION_APP_NAME}"
export LOGIC_APP_NAME="${LOGIC_APP_NAME}"
export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE}"
export APP_INSIGHTS_NAME="${APP_INSIGHTS_NAME}"
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
export LOCATION="${LOCATION}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF
    
    chmod +x deployment-env.sh
}

# Main deployment function
main() {
    log "Starting Azure Real-Time Data Validation Workflows deployment..."
    
    # Check if dry run mode
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log "DRY RUN MODE - No resources will be created"
        return 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_storage_resources
    create_event_grid_topic
    create_function_app
    deploy_validation_function
    create_logic_app
    configure_event_subscriptions
    create_validation_rules
    configure_monitoring
    test_deployment
    display_summary
    
    success "Deployment completed successfully!"
    log "Total deployment time: $((SECONDS/60)) minutes"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi