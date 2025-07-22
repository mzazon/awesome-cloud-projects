#!/bin/bash

# Intelligent Alert Response Automation with Monitor Workbooks and Azure Functions
# Deployment Script
# 
# This script deploys the complete intelligent alert response system including:
# - Azure Monitor Workbooks for visualization
# - Azure Functions for alert processing
# - Azure Event Grid for event orchestration
# - Azure Logic Apps for notification workflows
# - Azure Cosmos DB for alert state management
# - Azure Key Vault for secure configuration

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Azure CLI login status
check_azure_login() {
    if ! az account show >/dev/null 2>&1; then
        error "Azure CLI is not logged in. Please run 'az login' first."
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install Azure CLI v2.57.0 or later."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    local required_version="2.57.0"
    
    if [[ "$(printf '%s\n' "$required_version" "$az_version" | sort -V | head -n1)" != "$required_version" ]]; then
        error "Azure CLI version $az_version is too old. Required: $required_version or later."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command_exists openssl; then
        error "openssl is required for generating random suffixes. Please install openssl."
        exit 1
    fi
    
    # Check Azure CLI login
    check_azure_login
    
    # Check required Azure CLI extensions
    local extensions=("eventgrid" "logic" "cosmosdb-preview")
    for ext in "${extensions[@]}"; do
        if ! az extension show --name "$ext" >/dev/null 2>&1; then
            warn "Extension '$ext' not found. Installing..."
            az extension add --name "$ext" --yes
        fi
    done
    
    log "Prerequisites check completed successfully."
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-intelligent-alerts-${RANDOM_SUFFIX}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names with unique suffix
    export STORAGE_ACCOUNT="stintelligent${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-alert-response-${RANDOM_SUFFIX}"
    export EVENT_GRID_TOPIC="eg-alerts-${RANDOM_SUFFIX}"
    export LOGIC_APP="logic-notifications-${RANDOM_SUFFIX}"
    export COSMOS_DB="cosmos-alertstate-${RANDOM_SUFFIX}"
    export KEY_VAULT="kv-alerts-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS="law-monitoring-${RANDOM_SUFFIX}"
    
    # Validate resource name lengths (Azure naming restrictions)
    if [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
        error "Storage account name too long: ${STORAGE_ACCOUNT}"
        exit 1
    fi
    
    if [[ ${#KEY_VAULT} -gt 24 ]]; then
        error "Key Vault name too long: ${KEY_VAULT}"
        exit 1
    fi
    
    # Save environment variables to file for cleanup script
    cat > .env.deployment << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
FUNCTION_APP=${FUNCTION_APP}
EVENT_GRID_TOPIC=${EVENT_GRID_TOPIC}
LOGIC_APP=${LOGIC_APP}
COSMOS_DB=${COSMOS_DB}
KEY_VAULT=${KEY_VAULT}
LOG_ANALYTICS=${LOG_ANALYTICS}
EOF
    
    log "Environment variables set successfully."
    info "Resource Group: ${RESOURCE_GROUP}"
    info "Location: ${LOCATION}"
    info "Subscription ID: ${SUBSCRIPTION_ID}"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Resource group ${RESOURCE_GROUP} already exists. Skipping creation."
        return 0
    fi
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=intelligent-alerts environment=demo \
        --output none
    
    log "Resource group created successfully: ${RESOURCE_GROUP}"
}

# Function to create Log Analytics workspace
create_log_analytics() {
    log "Creating Log Analytics workspace..."
    
    if az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS}" >/dev/null 2>&1; then
        warn "Log Analytics workspace ${LOG_ANALYTICS} already exists. Skipping creation."
        return 0
    fi
    
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS}" \
        --location "${LOCATION}" \
        --sku pergb2018 \
        --output none
    
    log "Log Analytics workspace created successfully: ${LOG_ANALYTICS}"
}

# Function to create storage account and key vault
create_storage_and_keyvault() {
    log "Creating storage account and Key Vault..."
    
    # Create storage account
    if az storage account show \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Storage account ${STORAGE_ACCOUNT} already exists. Skipping creation."
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --https-only true \
            --output none
        
        log "Storage account created successfully: ${STORAGE_ACCOUNT}"
    fi
    
    # Create Key Vault
    if az keyvault show \
        --name "${KEY_VAULT}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Key Vault ${KEY_VAULT} already exists. Skipping creation."
    else
        az keyvault create \
            --name "${KEY_VAULT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku standard \
            --enable-rbac-authorization true \
            --output none
        
        log "Key Vault created successfully: ${KEY_VAULT}"
    fi
}

# Function to create Cosmos DB
create_cosmos_db() {
    log "Creating Cosmos DB for alert state management..."
    
    # Create Cosmos DB account
    if az cosmosdb show \
        --name "${COSMOS_DB}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Cosmos DB ${COSMOS_DB} already exists. Skipping creation."
    else
        az cosmosdb create \
            --name "${COSMOS_DB}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --kind GlobalDocumentDB \
            --enable-free-tier false \
            --default-consistency-level Session \
            --output none
        
        log "Cosmos DB created successfully: ${COSMOS_DB}"
    fi
    
    # Create database and container
    if az cosmosdb sql database show \
        --account-name "${COSMOS_DB}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name AlertDatabase >/dev/null 2>&1; then
        warn "Cosmos DB database AlertDatabase already exists. Skipping creation."
    else
        az cosmosdb sql database create \
            --account-name "${COSMOS_DB}" \
            --resource-group "${RESOURCE_GROUP}" \
            --name AlertDatabase \
            --output none
        
        log "Cosmos DB database created successfully: AlertDatabase"
    fi
    
    if az cosmosdb sql container show \
        --account-name "${COSMOS_DB}" \
        --resource-group "${RESOURCE_GROUP}" \
        --database-name AlertDatabase \
        --name AlertStates >/dev/null 2>&1; then
        warn "Cosmos DB container AlertStates already exists. Skipping creation."
    else
        az cosmosdb sql container create \
            --account-name "${COSMOS_DB}" \
            --resource-group "${RESOURCE_GROUP}" \
            --database-name AlertDatabase \
            --name AlertStates \
            --partition-key-path "/alertId" \
            --throughput 400 \
            --output none
        
        log "Cosmos DB container created successfully: AlertStates"
    fi
}

# Function to create Event Grid topic
create_event_grid() {
    log "Creating Event Grid topic for alert orchestration..."
    
    if az eventgrid topic show \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Event Grid topic ${EVENT_GRID_TOPIC} already exists. Skipping creation."
    else
        az eventgrid topic create \
            --name "${EVENT_GRID_TOPIC}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --output none
        
        log "Event Grid topic created successfully: ${EVENT_GRID_TOPIC}"
    fi
    
    # Get Event Grid connection details
    EVENT_GRID_KEY=$(az eventgrid topic key list \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 --output tsv)
    
    EVENT_GRID_ENDPOINT=$(az eventgrid topic show \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query endpoint --output tsv)
    
    # Store Event Grid details for later use
    echo "EVENT_GRID_KEY=${EVENT_GRID_KEY}" >> .env.deployment
    echo "EVENT_GRID_ENDPOINT=${EVENT_GRID_ENDPOINT}" >> .env.deployment
    
    log "Event Grid topic configuration completed."
}

# Function to create Function App
create_function_app() {
    log "Creating Azure Function App for alert processing..."
    
    if az functionapp show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Function App ${FUNCTION_APP} already exists. Skipping creation."
    else
        az functionapp create \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime python \
            --runtime-version 3.11 \
            --functions-version 4 \
            --os-type Linux \
            --output none
        
        log "Function App created successfully: ${FUNCTION_APP}"
    fi
    
    # Wait for Function App to be ready
    info "Waiting for Function App to be ready..."
    local attempts=0
    local max_attempts=30
    
    while [[ $attempts -lt $max_attempts ]]; do
        if az functionapp show \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query "state" --output tsv | grep -q "Running"; then
            break
        fi
        sleep 10
        ((attempts++))
    done
    
    if [[ $attempts -eq $max_attempts ]]; then
        error "Function App failed to reach running state within timeout."
        exit 1
    fi
    
    # Get Log Analytics workspace ID
    LOG_ANALYTICS_WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS}" \
        --query customerId --output tsv)
    
    # Configure Function App settings
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "COSMOS_DB_CONNECTION_STRING=@Microsoft.KeyVault(SecretUri=https://${KEY_VAULT}.vault.azure.net/secrets/cosmos-connection/)" \
        "EVENT_GRID_ENDPOINT=${EVENT_GRID_ENDPOINT}" \
        "EVENT_GRID_KEY=@Microsoft.KeyVault(SecretUri=https://${KEY_VAULT}.vault.azure.net/secrets/eventgrid-key/)" \
        "LOG_ANALYTICS_WORKSPACE_ID=${LOG_ANALYTICS_WORKSPACE_ID}" \
        --output none
    
    log "Function App configured successfully."
}

# Function to create Logic App
create_logic_app() {
    log "Creating Logic App for notification orchestration..."
    
    if az logic workflow show \
        --name "${LOGIC_APP}" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Logic App ${LOGIC_APP} already exists. Skipping creation."
    else
        # Create Logic App with basic workflow definition
        az logic workflow create \
            --name "${LOGIC_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --definition '{
              "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
              "contentVersion": "1.0.0.0",
              "parameters": {},
              "triggers": {
                "manual": {
                  "type": "Request",
                  "kind": "Http",
                  "inputs": {
                    "schema": {
                      "type": "object",
                      "properties": {
                        "alertId": {"type": "string"},
                        "severity": {"type": "string"},
                        "resourceId": {"type": "string"},
                        "alertContext": {"type": "object"}
                      }
                    }
                  }
                }
              },
              "actions": {
                "Initialize_Response": {
                  "type": "InitializeVariable",
                  "inputs": {
                    "variables": [{
                      "name": "notificationSent",
                      "type": "boolean",
                      "value": true
                    }]
                  }
                }
              },
              "outputs": {}
            }' \
            --output none
        
        log "Logic App created successfully: ${LOGIC_APP}"
    fi
    
    # Get Logic App trigger URL
    LOGIC_APP_URL=$(az logic workflow show \
        --name "${LOGIC_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "accessEndpoint" --output tsv)
    
    # Store Logic App URL for later use
    echo "LOGIC_APP_URL=${LOGIC_APP_URL}" >> .env.deployment
    
    log "Logic App configuration completed."
}

# Function to deploy Function code
deploy_function_code() {
    log "Deploying Function code for alert processing..."
    
    # Create temporary directory for function code
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
azure-functions
azure-cosmos
azure-eventgrid
azure-monitor-query
azure-identity
requests
EOF
    
    # Create main function file
    cat > function_app.py << 'EOF'
import azure.functions as func
import json
import logging
import os
from azure.cosmos import CosmosClient
from azure.eventgrid import EventGridPublisherClient
from azure.core.credentials import AzureKeyCredential
from azure.identity import DefaultAzureCredential

app = func.FunctionApp()

@app.function_name("ProcessAlert")
@app.event_grid_trigger(arg_name="event")
def process_alert(event: func.EventGridEvent):
    logging.info(f"Processing alert: {event.get_json()}")
    
    # Parse alert data
    alert_data = event.get_json()
    alert_id = alert_data.get('alertId', 'unknown')
    severity = alert_data.get('severity', 'medium')
    
    # Store alert state in Cosmos DB
    try:
        cosmos_client = CosmosClient.from_connection_string(
            os.environ['COSMOS_DB_CONNECTION_STRING']
        )
        database = cosmos_client.get_database_client('AlertDatabase')
        container = database.get_container_client('AlertStates')
        
        alert_state = {
            'id': alert_id,
            'alertId': alert_id,
            'severity': severity,
            'status': 'processing',
            'timestamp': event.event_time.isoformat(),
            'data': alert_data
        }
        
        container.create_item(alert_state)
        logging.info(f"Alert state stored for {alert_id}")
        
        # Trigger workbook update if high severity
        if severity in ['high', 'critical']:
            update_workbook(alert_data)
            
    except Exception as e:
        logging.error(f"Error processing alert {alert_id}: {str(e)}")
        raise

def update_workbook(alert_data):
    # Logic to refresh workbook data
    logging.info("Triggering workbook update for critical alert")
EOF
    
    # Create host.json
    cat > host.json << 'EOF'
{
  "version": "2.0",
  "functionTimeout": "00:05:00",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true
      }
    }
  },
  "extensions": {
    "eventGrid": {
      "maxEventsPerBatch": 1
    }
  }
}
EOF
    
    # Create deployment package
    zip -r function-code.zip .
    
    # Deploy function code
    az functionapp deployment source config-zip \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --src function-code.zip \
        --output none
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    log "Function code deployed successfully."
}

# Function to create Event Grid subscriptions
create_event_subscriptions() {
    log "Creating Event Grid subscriptions for alert routing..."
    
    # Create subscription for Function App
    if az eventgrid event-subscription show \
        --name "alerts-to-function" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" >/dev/null 2>&1; then
        warn "Event Grid subscription alerts-to-function already exists. Skipping creation."
    else
        az eventgrid event-subscription create \
            --name "alerts-to-function" \
            --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" \
            --endpoint-type azurefunction \
            --endpoint "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${FUNCTION_APP}/functions/ProcessAlert" \
            --included-event-types Microsoft.AlertManagement.Alert.Activated Microsoft.AlertManagement.Alert.Resolved \
            --output none
        
        log "Event Grid subscription created for Function App."
    fi
    
    # Create subscription for Logic App notifications
    if az eventgrid event-subscription show \
        --name "alerts-to-logic" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" >/dev/null 2>&1; then
        warn "Event Grid subscription alerts-to-logic already exists. Skipping creation."
    else
        az eventgrid event-subscription create \
            --name "alerts-to-logic" \
            --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" \
            --endpoint-type webhook \
            --endpoint "${LOGIC_APP_URL}" \
            --included-event-types Microsoft.AlertManagement.Alert.Activated \
            --advanced-filter data.severity StringIn high critical \
            --output none
        
        log "Event Grid subscription created for Logic App."
    fi
}

# Function to create Azure Monitor Workbook
create_workbook() {
    log "Creating Azure Monitor Workbook for alert dashboard..."
    
    # Create workbook template
    local workbook_template='{
      "version": "Notebook/1.0",
      "items": [
        {
          "type": 1,
          "content": {
            "json": "# Intelligent Alert Response Dashboard\n\nThis workbook provides real-time insights into alert patterns, response effectiveness, and system health."
          }
        },
        {
          "type": 3,
          "content": {
            "version": "KqlItem/1.0",
            "query": "AlertsManagementResources\n| where type == \"microsoft.alertsmanagement/alerts\"\n| summarize AlertCount = count() by tostring(properties.severity)\n| order by AlertCount desc",
            "size": 1,
            "title": "Alert Count by Severity",
            "queryType": 1,
            "resourceType": "microsoft.resourcegraph/resources",
            "visualization": "piechart"
          }
        },
        {
          "type": 3,
          "content": {
            "version": "KqlItem/1.0",
            "query": "AlertsManagementResources\n| where type == \"microsoft.alertsmanagement/alerts\"\n| extend AlertTime = todatetime(properties.essentials.startDateTime)\n| where AlertTime > ago(24h)\n| summarize AlertCount = count() by bin(AlertTime, 1h)\n| order by AlertTime asc",
            "size": 0,
            "title": "Alert Trends (24 Hours)",
            "queryType": 1,
            "resourceType": "microsoft.resourcegraph/resources",
            "visualization": "timechart"
          }
        }
      ]
    }'
    
    # Create workbook
    az monitor workbook create \
        --name "Intelligent Alert Dashboard" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --category "monitoring" \
        --serialized-data "$workbook_template" \
        --display-name "Intelligent Alert Response Dashboard" \
        --description "Comprehensive dashboard for intelligent alert response system" \
        --output none
    
    log "Azure Monitor Workbook created successfully."
}

# Function to configure Key Vault secrets
configure_secrets() {
    log "Configuring Key Vault secrets for secure access..."
    
    # Get Cosmos DB connection string
    COSMOS_CONNECTION=$(az cosmosdb keys list \
        --name "${COSMOS_DB}" \
        --resource-group "${RESOURCE_GROUP}" \
        --type connection-strings \
        --query "connectionStrings[0].connectionString" --output tsv)
    
    # Store Cosmos DB connection string
    az keyvault secret set \
        --vault-name "${KEY_VAULT}" \
        --name "cosmos-connection" \
        --value "${COSMOS_CONNECTION}" \
        --output none
    
    # Store Event Grid access key
    az keyvault secret set \
        --vault-name "${KEY_VAULT}" \
        --name "eventgrid-key" \
        --value "${EVENT_GRID_KEY}" \
        --output none
    
    # Grant Function App access to Key Vault
    FUNCTION_IDENTITY=$(az functionapp identity show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query principalId --output tsv)
    
    az keyvault set-policy \
        --name "${KEY_VAULT}" \
        --object-id "${FUNCTION_IDENTITY}" \
        --secret-permissions get list \
        --output none
    
    log "Key Vault secrets configured successfully."
}

# Function to create test alert rule
create_test_alert() {
    log "Creating test alert rule for system validation..."
    
    # Create action group
    if az monitor action-group show \
        --name "test-alert-actions" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Action group test-alert-actions already exists. Skipping creation."
    else
        az monitor action-group create \
            --name "test-alert-actions" \
            --resource-group "${RESOURCE_GROUP}" \
            --short-name "testalert" \
            --action webhook "webhook1" "${EVENT_GRID_ENDPOINT}" \
            --output none
        
        log "Action group created successfully."
    fi
    
    # Create test alert rule
    if az monitor metrics alert show \
        --name "test-cpu-alert" \
        --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Test alert rule test-cpu-alert already exists. Skipping creation."
    else
        az monitor metrics alert create \
            --name "test-cpu-alert" \
            --resource-group "${RESOURCE_GROUP}" \
            --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
            --condition "avg Percentage CPU > 80" \
            --window-size 5m \
            --evaluation-frequency 1m \
            --action "test-alert-actions" \
            --description "Test alert rule for intelligent response system" \
            --severity 2 \
            --output none
        
        log "Test alert rule created successfully."
    fi
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    local errors=0
    
    # Check Function App status
    if ! az functionapp show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "state" --output tsv | grep -q "Running"; then
        error "Function App is not in running state"
        ((errors++))
    fi
    
    # Check Event Grid topic
    if ! az eventgrid topic show \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "provisioningState" --output tsv | grep -q "Succeeded"; then
        error "Event Grid topic is not in succeeded state"
        ((errors++))
    fi
    
    # Check Cosmos DB
    if ! az cosmosdb show \
        --name "${COSMOS_DB}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "provisioningState" --output tsv | grep -q "Succeeded"; then
        error "Cosmos DB is not in succeeded state"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log "Deployment validation completed successfully."
    else
        error "Deployment validation failed with $errors errors."
        exit 1
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    
    echo ""
    echo "==================== DEPLOYMENT SUMMARY ===================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Subscription ID: ${SUBSCRIPTION_ID}"
    echo ""
    echo "Created Resources:"
    echo "  - Storage Account: ${STORAGE_ACCOUNT}"
    echo "  - Function App: ${FUNCTION_APP}"
    echo "  - Event Grid Topic: ${EVENT_GRID_TOPIC}"
    echo "  - Logic App: ${LOGIC_APP}"
    echo "  - Cosmos DB: ${COSMOS_DB}"
    echo "  - Key Vault: ${KEY_VAULT}"
    echo "  - Log Analytics: ${LOG_ANALYTICS}"
    echo ""
    echo "Access Points:"
    echo "  - Function App URL: https://${FUNCTION_APP}.azurewebsites.net"
    echo "  - Logic App URL: ${LOGIC_APP_URL}"
    echo "  - Event Grid Endpoint: ${EVENT_GRID_ENDPOINT}"
    echo ""
    echo "Next Steps:"
    echo "  1. Access the Azure Monitor Workbook in the Azure portal"
    echo "  2. Configure additional notification channels in the Logic App"
    echo "  3. Test the system by triggering the test alert rule"
    echo "  4. Monitor Function App logs for alert processing"
    echo ""
    echo "Configuration saved to: .env.deployment"
    echo "Use ./destroy.sh to clean up all resources when done."
    echo "==========================================================="
}

# Main deployment function
main() {
    log "Starting deployment of Intelligent Alert Response System..."
    
    # Check if dry run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "DRY RUN MODE: No resources will be created"
        exit 0
    fi
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_log_analytics
    create_storage_and_keyvault
    create_cosmos_db
    create_event_grid
    create_function_app
    create_logic_app
    deploy_function_code
    create_event_subscriptions
    create_workbook
    configure_secrets
    create_test_alert
    validate_deployment
    display_summary
    
    log "Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted. Resources may be in incomplete state. Check Azure portal and run cleanup if needed."; exit 1' INT TERM

# Run main function
main "$@"