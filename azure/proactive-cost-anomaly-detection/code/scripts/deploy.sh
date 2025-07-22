#!/bin/bash

# =============================================================================
# Azure Cost Anomaly Detection Deployment Script
# =============================================================================
# This script deploys the automated cost anomaly detection solution using 
# Azure Cost Management and Azure Functions.
# 
# Prerequisites:
# - Azure CLI installed and configured
# - Azure subscription with appropriate permissions
# - Python 3.11 for Azure Functions
# =============================================================================

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
        error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please login to Azure using 'az login'"
    fi
    
    # Check if Python 3.11 is available
    if ! command -v python3 &> /dev/null; then
        warn "Python 3 not found. Azure Functions require Python 3.11"
    fi
    
    # Check if Azure Functions Core Tools are installed
    if ! command -v func &> /dev/null; then
        warn "Azure Functions Core Tools not found. Installing..."
        npm install -g azure-functions-core-tools@4 --unsafe-perm true
    fi
    
    log "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Set default values or prompt for input
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-cost-anomaly-detection}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stcostanomaly${RANDOM_SUFFIX}}"
    export FUNCTION_APP="${FUNCTION_APP:-func-cost-anomaly-${RANDOM_SUFFIX}}"
    export COSMOS_ACCOUNT="${COSMOS_ACCOUNT:-cosmos-cost-anomaly-${RANDOM_SUFFIX}}"
    export LOGIC_APP="${LOGIC_APP:-logic-cost-alerts-${RANDOM_SUFFIX}}"
    
    # Configuration variables
    export ANOMALY_THRESHOLD="${ANOMALY_THRESHOLD:-20}"
    export LOOKBACK_DAYS="${LOOKBACK_DAYS:-30}"
    
    log "Environment variables set:"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  Location: ${LOCATION}"
    info "  Subscription ID: ${SUBSCRIPTION_ID}"
    info "  Storage Account: ${STORAGE_ACCOUNT}"
    info "  Function App: ${FUNCTION_APP}"
    info "  Cosmos Account: ${COSMOS_ACCOUNT}"
    info "  Logic App: ${LOGIC_APP}"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        info "Resource group '${RESOURCE_GROUP}' already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=cost-anomaly-detection environment=production
        
        log "Resource group '${RESOURCE_GROUP}' created successfully"
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account..."
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "Storage account '${STORAGE_ACCOUNT}' already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot
        
        log "Storage account '${STORAGE_ACCOUNT}' created successfully"
    fi
}

# Function to create Cosmos DB account
create_cosmos_db() {
    log "Creating Cosmos DB account..."
    
    if az cosmosdb show --name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "Cosmos DB account '${COSMOS_ACCOUNT}' already exists"
    else
        az cosmosdb create \
            --name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --locations regionName="${LOCATION}" \
            --default-consistency-level Session \
            --enable-automatic-failover false
        
        log "Cosmos DB account '${COSMOS_ACCOUNT}' created successfully"
    fi
    
    # Wait for Cosmos DB to be ready
    log "Waiting for Cosmos DB to be ready..."
    while ! az cosmosdb show --name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --query "provisioningState" --output tsv | grep -q "Succeeded"; do
        sleep 30
        info "Still waiting for Cosmos DB..."
    done
}

# Function to create Cosmos DB database and containers
create_cosmos_db_containers() {
    log "Creating Cosmos DB database and containers..."
    
    # Create database
    if az cosmosdb sql database show --account-name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --name "CostAnalytics" &> /dev/null; then
        info "Cosmos DB database 'CostAnalytics' already exists"
    else
        az cosmosdb sql database create \
            --account-name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --name CostAnalytics \
            --throughput 400
        
        log "Cosmos DB database 'CostAnalytics' created successfully"
    fi
    
    # Create DailyCosts container
    if az cosmosdb sql container show --account-name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --database-name "CostAnalytics" --name "DailyCosts" &> /dev/null; then
        info "Cosmos DB container 'DailyCosts' already exists"
    else
        az cosmosdb sql container create \
            --account-name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --database-name CostAnalytics \
            --name DailyCosts \
            --partition-key-path "/date" \
            --throughput 400
        
        log "Cosmos DB container 'DailyCosts' created successfully"
    fi
    
    # Create AnomalyResults container
    if az cosmosdb sql container show --account-name "${COSMOS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" --database-name "CostAnalytics" --name "AnomalyResults" &> /dev/null; then
        info "Cosmos DB container 'AnomalyResults' already exists"
    else
        az cosmosdb sql container create \
            --account-name "${COSMOS_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --database-name CostAnalytics \
            --name AnomalyResults \
            --partition-key-path "/subscriptionId" \
            --throughput 400
        
        log "Cosmos DB container 'AnomalyResults' created successfully"
    fi
}

# Function to create Azure Functions app
create_function_app() {
    log "Creating Azure Functions app..."
    
    if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "Function app '${FUNCTION_APP}' already exists"
    else
        az functionapp create \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime python \
            --runtime-version 3.11 \
            --functions-version 4 \
            --disable-app-insights false
        
        log "Function app '${FUNCTION_APP}' created successfully"
    fi
    
    # Wait for Function App to be ready
    log "Waiting for Function App to be ready..."
    while ! az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" --query "state" --output tsv | grep -q "Running"; do
        sleep 30
        info "Still waiting for Function App..."
    done
}

# Function to configure Function App settings
configure_function_app() {
    log "Configuring Function App settings..."
    
    # Get Cosmos DB connection string
    COSMOS_CONNECTION=$(az cosmosdb keys list \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --type connection-strings \
        --query "connectionStrings[0].connectionString" \
        --output tsv)
    
    # Configure application settings
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "COSMOS_ENDPOINT=https://${COSMOS_ACCOUNT}.documents.azure.com:443/" \
        "COSMOS_CONNECTION=${COSMOS_CONNECTION}" \
        "SUBSCRIPTION_ID=${SUBSCRIPTION_ID}" \
        "ANOMALY_THRESHOLD=${ANOMALY_THRESHOLD}" \
        "LOOKBACK_DAYS=${LOOKBACK_DAYS}"
    
    log "Function App settings configured successfully"
}

# Function to create and deploy Functions
deploy_function_code() {
    log "Creating and deploying Function code..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Initialize Function App
    func init . --python --name "${FUNCTION_APP}"
    
    # Create CostDataCollector function
    func new --language python --template "Timer trigger" --name CostDataCollector
    
    # Create function.json for CostDataCollector
    cat > CostDataCollector/function.json << 'EOF'
{
  "bindings": [
    {
      "name": "mytimer",
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 0 8 * * *"
    },
    {
      "name": "cosmosOut",
      "type": "cosmosDB",
      "databaseName": "CostAnalytics",
      "collectionName": "DailyCosts",
      "createIfNotExists": false,
      "connectionStringSetting": "COSMOS_CONNECTION",
      "direction": "out"
    }
  ]
}
EOF
    
    # Create Python code for CostDataCollector
    cat > CostDataCollector/__init__.py << 'EOF'
import azure.functions as func
import logging
import json
import os
from datetime import datetime, timedelta
from azure.identity import DefaultAzureCredential
from azure.mgmt.consumption import ConsumptionManagementClient
from azure.mgmt.costmanagement import CostManagementClient

def main(mytimer: func.TimerRequest, cosmosOut: func.Out[func.Document]) -> None:
    logging.info('Cost data collection function triggered')
    
    subscription_id = os.environ['SUBSCRIPTION_ID']
    credential = DefaultAzureCredential()
    
    # Initialize Cost Management client
    cost_client = CostManagementClient(credential)
    
    # Calculate date range for yesterday's data
    yesterday = datetime.utcnow() - timedelta(days=1)
    date_str = yesterday.strftime('%Y-%m-%d')
    
    try:
        # Query daily costs by service
        query_definition = {
            "type": "ActualCost",
            "timeframe": "Custom",
            "timePeriod": {
                "from": date_str,
                "to": date_str
            },
            "dataset": {
                "granularity": "Daily",
                "aggregation": {
                    "totalCost": {
                        "name": "PreTaxCost",
                        "function": "Sum"
                    }
                },
                "grouping": [
                    {
                        "type": "Dimension",
                        "name": "ServiceName"
                    },
                    {
                        "type": "Dimension",
                        "name": "ResourceGroupName"
                    }
                ]
            }
        }
        
        scope = f'/subscriptions/{subscription_id}'
        result = cost_client.query.usage(scope, query_definition)
        
        # Process and store cost data
        cost_records = []
        for row in result.rows:
            cost_record = {
                "id": f"{date_str}-{row[2]}-{row[3]}",
                "date": date_str,
                "subscriptionId": subscription_id,
                "serviceName": row[2],
                "resourceGroupName": row[3],
                "cost": float(row[0]),
                "currency": row[1],
                "timestamp": datetime.utcnow().isoformat()
            }
            cost_records.append(cost_record)
        
        # Output to Cosmos DB
        cosmosOut.set(func.Document.from_dict(cost_records))
        
        logging.info(f'Successfully processed {len(cost_records)} cost records for {date_str}')
        
    except Exception as e:
        logging.error(f'Error processing cost data: {str(e)}')
        raise
EOF
    
    # Create AnomalyDetector function
    func new --language python --template "Timer trigger" --name AnomalyDetector
    
    # Create function.json for AnomalyDetector
    cat > AnomalyDetector/function.json << 'EOF'
{
  "bindings": [
    {
      "name": "mytimer",
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 30 8 * * *"
    },
    {
      "name": "cosmosIn",
      "type": "cosmosDB",
      "databaseName": "CostAnalytics",
      "collectionName": "DailyCosts",
      "connectionStringSetting": "COSMOS_CONNECTION",
      "direction": "in"
    },
    {
      "name": "cosmosOut",
      "type": "cosmosDB",
      "databaseName": "CostAnalytics",
      "collectionName": "AnomalyResults",
      "createIfNotExists": false,
      "connectionStringSetting": "COSMOS_CONNECTION",
      "direction": "out"
    }
  ]
}
EOF
    
    # Create Python code for AnomalyDetector
    cat > AnomalyDetector/__init__.py << 'EOF'
import azure.functions as func
import logging
import json
import os
import statistics
from datetime import datetime, timedelta
from collections import defaultdict

def main(mytimer: func.TimerRequest, cosmosIn: func.DocumentList, cosmosOut: func.Out[func.Document]) -> None:
    logging.info('Anomaly detection function triggered')
    
    subscription_id = os.environ['SUBSCRIPTION_ID']
    anomaly_threshold = float(os.environ.get('ANOMALY_THRESHOLD', 20))
    lookback_days = int(os.environ.get('LOOKBACK_DAYS', 30))
    
    # Calculate date range
    today = datetime.utcnow().date()
    yesterday = today - timedelta(days=1)
    lookback_date = today - timedelta(days=lookback_days)
    
    try:
        # Group cost data by service and resource group
        service_costs = defaultdict(list)
        yesterday_costs = {}
        
        for document in cosmosIn:
            doc_date = datetime.fromisoformat(document['date']).date()
            service_key = f"{document['serviceName']}_{document['resourceGroupName']}"
            cost = document['cost']
            
            if doc_date >= lookback_date:
                service_costs[service_key].append(cost)
                
            if doc_date == yesterday:
                yesterday_costs[service_key] = cost
        
        # Detect anomalies
        anomalies = []
        
        for service_key, costs in service_costs.items():
            if len(costs) < 7:  # Need at least 7 days of data
                continue
                
            # Calculate baseline statistics
            baseline_costs = costs[:-1] if service_key in yesterday_costs else costs
            if len(baseline_costs) < 3:
                continue
                
            baseline_mean = statistics.mean(baseline_costs)
            baseline_std = statistics.stdev(baseline_costs) if len(baseline_costs) > 1 else 0
            
            # Check for anomalies
            if service_key in yesterday_costs:
                current_cost = yesterday_costs[service_key]
                
                # Calculate percentage change
                if baseline_mean > 0:
                    percent_change = ((current_cost - baseline_mean) / baseline_mean) * 100
                else:
                    percent_change = 0
                
                # Check if cost exceeds threshold
                if abs(percent_change) > anomaly_threshold:
                    service_name, resource_group = service_key.split('_', 1)
                    
                    anomaly = {
                        "id": f"{yesterday.isoformat()}-{service_key}",
                        "date": yesterday.isoformat(),
                        "subscriptionId": subscription_id,
                        "serviceName": service_name,
                        "resourceGroupName": resource_group,
                        "currentCost": current_cost,
                        "baselineCost": baseline_mean,
                        "percentageChange": percent_change,
                        "anomalyType": "increase" if percent_change > 0 else "decrease",
                        "severity": "high" if abs(percent_change) > 50 else "medium",
                        "timestamp": datetime.utcnow().isoformat()
                    }
                    
                    anomalies.append(anomaly)
        
        # Store anomaly results
        if anomalies:
            cosmosOut.set(func.Document.from_dict(anomalies))
            logging.info(f'Detected {len(anomalies)} cost anomalies')
        else:
            logging.info('No cost anomalies detected')
            
    except Exception as e:
        logging.error(f'Error in anomaly detection: {str(e)}')
        raise
EOF
    
    # Create NotificationHandler function
    func new --language python --template "Cosmos DB trigger" --name NotificationHandler
    
    # Create function.json for NotificationHandler
    cat > NotificationHandler/function.json << 'EOF'
{
  "bindings": [
    {
      "name": "documents",
      "type": "cosmosDBTrigger",
      "direction": "in",
      "databaseName": "CostAnalytics",
      "collectionName": "AnomalyResults",
      "connectionStringSetting": "COSMOS_CONNECTION",
      "createLeaseCollectionIfNotExists": true
    }
  ]
}
EOF
    
    # Create Python code for NotificationHandler
    cat > NotificationHandler/__init__.py << 'EOF'
import azure.functions as func
import logging
import json
import os
from datetime import datetime

def main(documents: func.DocumentList) -> None:
    logging.info('Notification handler triggered')
    
    for doc in documents:
        try:
            # Format alert message
            message = f"""
            Cost Anomaly Alert
            
            Date: {doc['date']}
            Service: {doc['serviceName']}
            Resource Group: {doc['resourceGroupName']}
            Current Cost: ${doc['currentCost']:.2f}
            Baseline Cost: ${doc['baselineCost']:.2f}
            Change: {doc['percentageChange']:.1f}%
            Severity: {doc['severity']}
            
            Please investigate this cost anomaly and take appropriate action.
            """
            
            # Log alert (replace with actual notification logic)
            logging.info(f'ALERT: {message}')
            
            # Here you would integrate with your notification system
            # Examples: send to Slack, Teams, email, SMS, etc.
            
        except Exception as e:
            logging.error(f'Error processing anomaly notification: {str(e)}')
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
azure-functions
azure-identity
azure-mgmt-consumption
azure-mgmt-costmanagement
azure-cosmos
EOF
    
    # Deploy the function
    func azure functionapp publish "${FUNCTION_APP}" --python
    
    # Clean up temporary directory
    cd /
    rm -rf "${TEMP_DIR}"
    
    log "Function code deployed successfully"
}

# Function to configure permissions
configure_permissions() {
    log "Configuring permissions..."
    
    # Enable managed identity for Function App
    az functionapp identity assign \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}"
    
    # Get the managed identity principal ID
    PRINCIPAL_ID=$(az functionapp identity show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query principalId \
        --output tsv)
    
    # Assign Cosmos DB Data Contributor role
    az cosmosdb sql role assignment create \
        --account-name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --scope "/" \
        --principal-id "${PRINCIPAL_ID}" \
        --role-definition-id "00000000-0000-0000-0000-000000000002"
    
    # Assign Cost Management Reader role
    az role assignment create \
        --assignee "${PRINCIPAL_ID}" \
        --role "Cost Management Reader" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}"
    
    log "Permissions configured successfully"
}

# Function to create Logic App
create_logic_app() {
    log "Creating Logic App for notifications..."
    
    if az logic workflow show --name "${LOGIC_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "Logic App '${LOGIC_APP}' already exists"
    else
        az logic workflow create \
            --name "${LOGIC_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --definition '{
                "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
                "contentVersion": "1.0.0.0",
                "parameters": {},
                "triggers": {
                    "Recurrence": {
                        "type": "Recurrence",
                        "recurrence": {
                            "frequency": "Hour",
                            "interval": 1
                        }
                    }
                },
                "actions": {
                    "Initialize_variable": {
                        "type": "InitializeVariable",
                        "inputs": {
                            "variables": [
                                {
                                    "name": "AlertMessage",
                                    "type": "String",
                                    "value": "Cost anomaly detection system is active"
                                }
                            ]
                        }
                    }
                }
            }' \
            --state Enabled
        
        log "Logic App '${LOGIC_APP}' created successfully"
    fi
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check Function App status
    FUNCTION_STATUS=$(az functionapp show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "state" \
        --output tsv)
    
    if [ "${FUNCTION_STATUS}" != "Running" ]; then
        error "Function App is not running. Current status: ${FUNCTION_STATUS}"
    fi
    
    # Check Cosmos DB status
    COSMOS_STATUS=$(az cosmosdb show \
        --name "${COSMOS_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "provisioningState" \
        --output tsv)
    
    if [ "${COSMOS_STATUS}" != "Succeeded" ]; then
        error "Cosmos DB is not ready. Current status: ${COSMOS_STATUS}"
    fi
    
    # List deployed functions
    FUNCTION_COUNT=$(az functionapp function list \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "length(@)" \
        --output tsv)
    
    if [ "${FUNCTION_COUNT}" -lt 3 ]; then
        error "Expected 3 functions, but found ${FUNCTION_COUNT}"
    fi
    
    log "Deployment verification completed successfully"
    info "  Function App Status: ${FUNCTION_STATUS}"
    info "  Cosmos DB Status: ${COSMOS_STATUS}"
    info "  Functions Deployed: ${FUNCTION_COUNT}"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Function App: ${FUNCTION_APP}"
    echo "Cosmos DB: ${COSMOS_ACCOUNT}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "Logic App: ${LOGIC_APP}"
    echo "Subscription: ${SUBSCRIPTION_ID}"
    echo "Location: ${LOCATION}"
    echo "===================="
    echo ""
    echo "Next Steps:"
    echo "1. Monitor function execution logs in Azure portal"
    echo "2. Check Cosmos DB for cost data collection"
    echo "3. Configure notification endpoints in Logic App"
    echo "4. Set up custom alerting rules as needed"
    echo "5. Review and adjust anomaly detection thresholds"
    echo ""
    echo "Estimated monthly cost: $15-30 (based on moderate usage)"
    echo ""
    warn "Remember to clean up resources when done to avoid ongoing charges"
}

# Main execution flow
main() {
    log "Starting Azure Cost Anomaly Detection deployment..."
    
    # Check if this is a dry run
    if [[ "${1:-}" == "--dry-run" ]]; then
        log "Running in dry-run mode - no resources will be created"
        DRY_RUN=true
    else
        DRY_RUN=false
    fi
    
    # Execute deployment steps
    check_prerequisites
    set_environment_variables
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        create_resource_group
        create_storage_account
        create_cosmos_db
        create_cosmos_db_containers
        create_function_app
        configure_function_app
        deploy_function_code
        configure_permissions
        create_logic_app
        verify_deployment
        display_summary
    else
        log "Dry run completed - no resources were created"
    fi
    
    log "Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Script interrupted. Please run cleanup script to remove any partially created resources."' INT

# Run main function with all arguments
main "$@"