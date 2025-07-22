#!/bin/bash

# Azure Serverless Data Mesh Deployment Script
# Recipe: Serverless Data Mesh with Databricks and API Management
# Version: 1.0

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

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warn "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    info "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
        return 0
    fi
    
    if ! eval "$cmd"; then
        error "Failed to execute: $cmd"
        return 1
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '."azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    info "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random strings"
        exit 1
    fi
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        error "jq is required for JSON processing. Please install it from https://stedolan.github.io/jq/"
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Configuration and environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set default values or use environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-data-mesh-demo}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names
    export DATABRICKS_WORKSPACE="databricks-${RANDOM_SUFFIX}"
    export APIM_SERVICE="apim-mesh-${RANDOM_SUFFIX}"
    export KEYVAULT_NAME="kv-mesh-${RANDOM_SUFFIX}"
    export EVENT_GRID_TOPIC="eg-mesh-${RANDOM_SUFFIX}"
    
    # Display configuration
    info "Configuration:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    info "  Subscription: $SUBSCRIPTION_ID"
    info "  Random Suffix: $RANDOM_SUFFIX"
    info "  Databricks Workspace: $DATABRICKS_WORKSPACE"
    info "  API Management: $APIM_SERVICE"
    info "  Key Vault: $KEYVAULT_NAME"
    info "  Event Grid Topic: $EVENT_GRID_TOPIC"
    
    # Save configuration to file for cleanup script
    cat > .deployment-config <<EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
RANDOM_SUFFIX=$RANDOM_SUFFIX
DATABRICKS_WORKSPACE=$DATABRICKS_WORKSPACE
APIM_SERVICE=$APIM_SERVICE
KEYVAULT_NAME=$KEYVAULT_NAME
EVENT_GRID_TOPIC=$EVENT_GRID_TOPIC
EOF
    
    log "Environment setup completed"
}

# Create resource group
create_resource_group() {
    log "Creating resource group..."
    
    local cmd="az group create --name ${RESOURCE_GROUP} --location ${LOCATION} --tags purpose=data-mesh environment=demo"
    execute_command "$cmd" "Creating resource group: $RESOURCE_GROUP"
    
    log "Resource group created successfully"
}

# Create Azure Databricks workspace
create_databricks_workspace() {
    log "Creating Azure Databricks workspace..."
    
    local cmd="az databricks workspace create --name ${DATABRICKS_WORKSPACE} --resource-group ${RESOURCE_GROUP} --location ${LOCATION} --sku premium --enable-no-public-ip true"
    execute_command "$cmd" "Creating Databricks workspace: $DATABRICKS_WORKSPACE"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Get workspace details
        export DATABRICKS_WORKSPACE_ID=$(az databricks workspace show --name ${DATABRICKS_WORKSPACE} --resource-group ${RESOURCE_GROUP} --query id --output tsv)
        info "Databricks workspace ID: $DATABRICKS_WORKSPACE_ID"
        
        # Add to config file
        echo "DATABRICKS_WORKSPACE_ID=$DATABRICKS_WORKSPACE_ID" >> .deployment-config
    fi
    
    log "Databricks workspace created successfully"
}

# Create Key Vault
create_keyvault() {
    log "Creating Azure Key Vault..."
    
    local cmd="az keyvault create --name ${KEYVAULT_NAME} --resource-group ${RESOURCE_GROUP} --location ${LOCATION} --sku standard --enable-rbac-authorization true"
    execute_command "$cmd" "Creating Key Vault: $KEYVAULT_NAME"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Store Databricks workspace URL
        local databricks_url=$(az databricks workspace show --name ${DATABRICKS_WORKSPACE} --resource-group ${RESOURCE_GROUP} --query workspaceUrl --output tsv)
        
        local store_cmd="az keyvault secret set --vault-name ${KEYVAULT_NAME} --name 'databricks-url' --value 'https://${databricks_url}'"
        execute_command "$store_cmd" "Storing Databricks URL in Key Vault"
        
        # Add to config file
        echo "DATABRICKS_URL=$databricks_url" >> .deployment-config
    fi
    
    log "Key Vault created and configured successfully"
}

# Create API Management service
create_apim() {
    log "Creating Azure API Management service..."
    warn "API Management provisioning may take 20-30 minutes"
    
    local cmd="az apim create --name ${APIM_SERVICE} --resource-group ${RESOURCE_GROUP} --publisher-name 'DataMeshTeam' --publisher-email 'datamesh@example.com' --sku-name Consumption --location ${LOCATION}"
    execute_command "$cmd" "Creating API Management service: $APIM_SERVICE"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for APIM to be fully provisioned
        info "Waiting for API Management provisioning..."
        local wait_cmd="az apim wait --name ${APIM_SERVICE} --resource-group ${RESOURCE_GROUP} --created --timeout 3600"
        execute_command "$wait_cmd" "Waiting for API Management provisioning"
    fi
    
    log "API Management service created successfully"
}

# Create Event Grid topic
create_event_grid() {
    log "Creating Event Grid topic..."
    
    local cmd="az eventgrid topic create --name ${EVENT_GRID_TOPIC} --resource-group ${RESOURCE_GROUP} --location ${LOCATION} --identity systemassigned"
    execute_command "$cmd" "Creating Event Grid topic: $EVENT_GRID_TOPIC"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Get Event Grid endpoint and key
        local endpoint=$(az eventgrid topic show --name ${EVENT_GRID_TOPIC} --resource-group ${RESOURCE_GROUP} --query endpoint --output tsv)
        local key=$(az eventgrid topic key list --name ${EVENT_GRID_TOPIC} --resource-group ${RESOURCE_GROUP} --query key1 --output tsv)
        
        # Store credentials in Key Vault
        local store_endpoint_cmd="az keyvault secret set --vault-name ${KEYVAULT_NAME} --name 'eventgrid-endpoint' --value '${endpoint}'"
        execute_command "$store_endpoint_cmd" "Storing Event Grid endpoint in Key Vault"
        
        local store_key_cmd="az keyvault secret set --vault-name ${KEYVAULT_NAME} --name 'eventgrid-key' --value '${key}'"
        execute_command "$store_key_cmd" "Storing Event Grid key in Key Vault"
        
        # Add to config file
        echo "EVENT_GRID_ENDPOINT=$endpoint" >> .deployment-config
        echo "EVENT_GRID_KEY=$key" >> .deployment-config
    fi
    
    log "Event Grid topic created and configured successfully"
}

# Create API definition and import to APIM
create_api_definition() {
    log "Creating and importing API definition..."
    
    # Create API definition file
    cat > data-product-api.json <<EOF
{
  "openapi": "3.0.1",
  "info": {
    "title": "Customer Analytics Data Product",
    "description": "Domain-owned customer analytics data product API",
    "version": "1.0"
  },
  "servers": [
    {
      "url": "https://${APIM_SERVICE}.azure-api.net/customer-analytics"
    }
  ],
  "paths": {
    "/metrics": {
      "get": {
        "summary": "Get customer metrics",
        "operationId": "getCustomerMetrics",
        "parameters": [
          {
            "name": "dateFrom",
            "in": "query",
            "required": true,
            "schema": {
              "type": "string",
              "format": "date"
            }
          }
        ],
        "responses": {
          "200": {
            "description": "Successful response",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object"
                }
              }
            }
          }
        }
      }
    }
  }
}
EOF

    info "API definition file created: data-product-api.json"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Import API definition
        local import_cmd="az apim api import --resource-group ${RESOURCE_GROUP} --service-name ${APIM_SERVICE} --api-id 'customer-analytics-api' --path 'customer-analytics' --specification-format OpenApi --specification-path data-product-api.json --display-name 'Customer Analytics Data Product'"
        execute_command "$import_cmd" "Importing API definition to API Management"
        
        # Create API subscription
        local subscription_key=$(az apim subscription create --resource-group ${RESOURCE_GROUP} --service-name ${APIM_SERVICE} --name 'data-consumer-subscription' --display-name 'Data Consumer Subscription' --scope '/apis/customer-analytics-api' --query primaryKey --output tsv)
        
        info "API subscription created with key: ${subscription_key:0:10}..."
        
        # Add to config file
        echo "SUBSCRIPTION_KEY=$subscription_key" >> .deployment-config
    fi
    
    log "API definition created and imported successfully"
}

# Configure API policies
configure_api_policies() {
    log "Configuring API policies..."
    
    # Create API policy XML
    cat > api-policy.xml <<EOF
<policies>
  <inbound>
    <base />
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
      <openid-config url="https://login.microsoftonline.com/${SUBSCRIPTION_ID}/.well-known/openid-configuration" />
      <audiences>
        <audience>https://${APIM_SERVICE}.azure-api.net</audience>
      </audiences>
    </validate-jwt>
    <rate-limit calls="100" renewal-period="60" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
    <cache-store duration="300" />
  </outbound>
</policies>
EOF

    info "API policy file created: api-policy.xml"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Apply policy to API
        local policy_cmd="az apim api policy create --resource-group ${RESOURCE_GROUP} --service-name ${APIM_SERVICE} --api-id 'customer-analytics-api' --policy-file api-policy.xml"
        execute_command "$policy_cmd" "Applying API policies"
    fi
    
    log "API policies configured successfully"
}

# Create Event Grid subscription
create_event_grid_subscription() {
    log "Creating Event Grid subscription..."
    
    # Note: Using a placeholder webhook endpoint for demo purposes
    local webhook_endpoint="https://webhook.site/unique-endpoint"
    warn "Using placeholder webhook endpoint: $webhook_endpoint"
    warn "Replace with your actual endpoint URL for production use"
    
    local cmd="az eventgrid event-subscription create --name 'data-product-updates' --source-resource-id '/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}' --endpoint '${webhook_endpoint}' --event-types 'DataProductUpdated' 'DataProductCreated'"
    execute_command "$cmd" "Creating Event Grid subscription"
    
    log "Event Grid subscription created successfully"
}

# Configure Databricks service principal
configure_databricks_sp() {
    log "Configuring Databricks service principal..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create service principal
        local sp_result=$(az ad sp create-for-rbac --name "sp-databricks-${RANDOM_SUFFIX}" --role "Contributor" --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}")
        
        local sp_app_id=$(echo "$sp_result" | jq -r '.appId')
        local sp_password=$(echo "$sp_result" | jq -r '.password')
        
        # Store credentials in Key Vault
        local store_id_cmd="az keyvault secret set --vault-name ${KEYVAULT_NAME} --name 'databricks-sp-id' --value '${sp_app_id}'"
        execute_command "$store_id_cmd" "Storing service principal ID in Key Vault"
        
        local store_secret_cmd="az keyvault secret set --vault-name ${KEYVAULT_NAME} --name 'databricks-sp-secret' --value '${sp_password}'"
        execute_command "$store_secret_cmd" "Storing service principal secret in Key Vault"
        
        # Add to config file
        echo "SP_APP_ID=$sp_app_id" >> .deployment-config
        echo "SP_PASSWORD=$sp_password" >> .deployment-config
        
        info "Service principal created: $sp_app_id"
    else
        info "Would create service principal for Databricks"
    fi
    
    log "Databricks service principal configured successfully"
}

# Create sample data product notebook
create_sample_notebook() {
    log "Creating sample data product notebook..."
    
    cat > data-product-notebook.py <<'EOF'
# Databricks notebook source
# MAGIC %md
# MAGIC # Customer Analytics Data Product
# MAGIC This notebook implements the customer analytics data product

# COMMAND ----------
# Import required libraries
from pyspark.sql import SparkSession
from delta.tables import DeltaTable
import requests
import json
import uuid
from datetime import datetime

# COMMAND ----------
# Configure Unity Catalog
spark.conf.set("spark.databricks.unityCatalog.enabled", "true")
catalog_name = "data_mesh_catalog"
schema_name = "customer_analytics"

# COMMAND ----------
# Create sample data product
spark.sql(f"CREATE CATALOG IF NOT EXISTS {catalog_name}")
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {catalog_name}.{schema_name}")

# COMMAND ----------
# Define data product table
spark.sql(f"""
CREATE TABLE IF NOT EXISTS {catalog_name}.{schema_name}.customer_metrics (
    customer_id STRING,
    metric_date DATE,
    total_purchases DECIMAL(10,2),
    engagement_score DOUBLE,
    last_updated TIMESTAMP
)
USING DELTA
""")

# COMMAND ----------
# Function to publish data product update event
def publish_update_event(table_name, version):
    try:
        event_grid_endpoint = dbutils.secrets.get("keyvault", "eventgrid-endpoint")
        event_grid_key = dbutils.secrets.get("keyvault", "eventgrid-key")
        
        event = {
            "id": str(uuid.uuid4()),
            "eventType": "DataProductUpdated",
            "subject": f"datamesh/{table_name}",
            "eventTime": datetime.utcnow().isoformat() + "Z",
            "data": {
                "tableName": table_name,
                "version": version,
                "catalog": catalog_name,
                "schema": schema_name
            }
        }
        
        headers = {
            "aeg-sas-key": event_grid_key,
            "Content-Type": "application/json"
        }
        
        response = requests.post(event_grid_endpoint, json=[event], headers=headers)
        return response.status_code == 200
    except Exception as e:
        print(f"Error publishing event: {e}")
        return False

# COMMAND ----------
# Sample data processing and event publishing
def process_customer_data():
    # Sample data processing logic
    print("Processing customer analytics data...")
    
    # Publish update event
    if publish_update_event("customer_metrics", "1.0"):
        print("Data product update event published successfully")
    else:
        print("Failed to publish data product update event")

# COMMAND ----------
# Execute data processing
process_customer_data()
EOF

    info "Sample notebook created: data-product-notebook.py"
    
    log "Sample data product notebook created successfully"
}

# Validation function
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Skipping validation in dry-run mode"
        return 0
    fi
    
    # Check API Management status
    local apim_status=$(az apim show --name ${APIM_SERVICE} --resource-group ${RESOURCE_GROUP} --query "provisioningState" --output tsv)
    if [[ "$apim_status" == "Succeeded" ]]; then
        log "✅ API Management validation: PASSED"
    else
        warn "API Management validation: Status is $apim_status"
    fi
    
    # Check Databricks workspace
    local databricks_name=$(az databricks workspace show --name ${DATABRICKS_WORKSPACE} --resource-group ${RESOURCE_GROUP} --query "name" --output tsv)
    if [[ "$databricks_name" == "$DATABRICKS_WORKSPACE" ]]; then
        log "✅ Databricks workspace validation: PASSED"
    else
        warn "Databricks workspace validation: FAILED"
    fi
    
    # Check Event Grid subscriptions
    local subscriptions=$(az eventgrid event-subscription list --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}" --query "length([*])" --output tsv)
    if [[ "$subscriptions" -gt 0 ]]; then
        log "✅ Event Grid subscription validation: PASSED"
    else
        warn "Event Grid subscription validation: FAILED"
    fi
    
    log "Validation completed"
}

# Main deployment function
main() {
    log "Starting Azure Serverless Data Mesh deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Create resources
    create_resource_group
    create_databricks_workspace
    create_keyvault
    create_apim
    create_event_grid
    create_api_definition
    configure_api_policies
    create_event_grid_subscription
    configure_databricks_sp
    create_sample_notebook
    
    # Validate deployment
    validate_deployment
    
    log "Deployment completed successfully!"
    
    # Display summary
    info "Deployment Summary:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Databricks Workspace: $DATABRICKS_WORKSPACE"
    info "  API Management: $APIM_SERVICE"
    info "  Key Vault: $KEYVAULT_NAME"
    info "  Event Grid Topic: $EVENT_GRID_TOPIC"
    info "  Configuration saved to: .deployment-config"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        local databricks_url=$(az databricks workspace show --name ${DATABRICKS_WORKSPACE} --resource-group ${RESOURCE_GROUP} --query workspaceUrl --output tsv)
        info "  Databricks URL: https://${databricks_url}"
        info "  API Management URL: https://${APIM_SERVICE}.azure-api.net"
    fi
    
    warn "Remember to configure Unity Catalog and upload the sample notebook to Databricks"
    warn "Update the Event Grid subscription webhook endpoint with your actual endpoint"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi