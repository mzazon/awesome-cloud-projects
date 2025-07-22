#!/bin/bash

# =============================================================================
# Azure Self-Healing Infrastructure Deployment Script
# =============================================================================
# This script deploys a self-healing infrastructure using Azure Traffic Manager
# and Azure Load Testing with automated monitoring and remediation capabilities.
# =============================================================================

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# =============================================================================
# Prerequisites Check
# =============================================================================
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please log in to Azure CLI first using 'az login'"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random values"
        exit 1
    fi
    
    # Check if required Azure providers are registered
    log "Checking required Azure providers..."
    REQUIRED_PROVIDERS=(
        "Microsoft.Web"
        "Microsoft.Network"
        "Microsoft.Insights"
        "Microsoft.LoadTestService"
        "Microsoft.Storage"
    )
    
    for provider in "${REQUIRED_PROVIDERS[@]}"; do
        if ! az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null | grep -q "Registered"; then
            warning "Registering provider: $provider"
            az provider register --namespace "$provider"
        fi
    done
    
    success "Prerequisites check completed"
}

# =============================================================================
# Configuration
# =============================================================================
setup_configuration() {
    log "Setting up configuration..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for resource management
    export RESOURCE_GROUP="rg-selfhealing-${RANDOM_SUFFIX}"
    export LOCATION="eastus"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set unique names for all resources
    export TRAFFIC_MANAGER_PROFILE="tm-selfhealing-${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="func-monitor-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stselfheal${RANDOM_SUFFIX}"
    export APP_SERVICE_PLAN_EAST="asp-east-${RANDOM_SUFFIX}"
    export APP_SERVICE_PLAN_WEST="asp-west-${RANDOM_SUFFIX}"
    export APP_SERVICE_PLAN_EUROPE="asp-europe-${RANDOM_SUFFIX}"
    export WEB_APP_EAST="webapp-east-${RANDOM_SUFFIX}"
    export WEB_APP_WEST="webapp-west-${RANDOM_SUFFIX}"
    export WEB_APP_EUROPE="webapp-europe-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_WORKSPACE="law-selfhealing-${RANDOM_SUFFIX}"
    export LOAD_TEST_RESOURCE="alt-selfhealing-${RANDOM_SUFFIX}"
    
    # Save configuration to file for cleanup script
    cat > .deployment_config << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
TRAFFIC_MANAGER_PROFILE=${TRAFFIC_MANAGER_PROFILE}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
APP_SERVICE_PLAN_EAST=${APP_SERVICE_PLAN_EAST}
APP_SERVICE_PLAN_WEST=${APP_SERVICE_PLAN_WEST}
APP_SERVICE_PLAN_EUROPE=${APP_SERVICE_PLAN_EUROPE}
WEB_APP_EAST=${WEB_APP_EAST}
WEB_APP_WEST=${WEB_APP_WEST}
WEB_APP_EUROPE=${WEB_APP_EUROPE}
LOG_ANALYTICS_WORKSPACE=${LOG_ANALYTICS_WORKSPACE}
LOAD_TEST_RESOURCE=${LOAD_TEST_RESOURCE}
EOF
    
    success "Configuration completed with suffix: ${RANDOM_SUFFIX}"
}

# =============================================================================
# Resource Group and Analytics Workspace
# =============================================================================
create_foundational_resources() {
    log "Creating foundational resources..."
    
    # Create primary resource group
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=self-healing-demo environment=test
    
    success "Resource group created: ${RESOURCE_GROUP}"
    
    # Create Log Analytics workspace for centralized monitoring
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
        --location "${LOCATION}"
    
    success "Log Analytics workspace created: ${LOG_ANALYTICS_WORKSPACE}"
}

# =============================================================================
# Multi-Region Web Applications
# =============================================================================
create_web_applications() {
    log "Creating multi-region web applications..."
    
    # Create App Service plans in different regions
    log "Creating App Service plans..."
    
    az appservice plan create \
        --name "${APP_SERVICE_PLAN_EAST}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location eastus \
        --sku B1 \
        --is-linux true &
    
    az appservice plan create \
        --name "${APP_SERVICE_PLAN_WEST}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location westus \
        --sku B1 \
        --is-linux true &
    
    az appservice plan create \
        --name "${APP_SERVICE_PLAN_EUROPE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location westeurope \
        --sku B1 \
        --is-linux true &
    
    # Wait for all App Service plans to be created
    wait
    success "App Service plans created in all regions"
    
    # Create web applications in each region
    log "Creating web applications..."
    
    az webapp create \
        --name "${WEB_APP_EAST}" \
        --resource-group "${RESOURCE_GROUP}" \
        --plan "${APP_SERVICE_PLAN_EAST}" \
        --runtime "NODE:18-lts" &
    
    az webapp create \
        --name "${WEB_APP_WEST}" \
        --resource-group "${RESOURCE_GROUP}" \
        --plan "${APP_SERVICE_PLAN_WEST}" \
        --runtime "NODE:18-lts" &
    
    az webapp create \
        --name "${WEB_APP_EUROPE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --plan "${APP_SERVICE_PLAN_EUROPE}" \
        --runtime "NODE:18-lts" &
    
    # Wait for all web apps to be created
    wait
    success "Multi-region web applications created successfully"
}

# =============================================================================
# Traffic Manager Configuration
# =============================================================================
configure_traffic_manager() {
    log "Configuring Azure Traffic Manager..."
    
    # Create Traffic Manager profile with performance routing
    az network traffic-manager profile create \
        --name "${TRAFFIC_MANAGER_PROFILE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --routing-method Performance \
        --dns-ttl 30 \
        --monitor-protocol HTTP \
        --monitor-port 80 \
        --monitor-path "/" \
        --monitor-interval 30 \
        --monitor-timeout 10 \
        --monitor-failure-threshold 3
    
    success "Traffic Manager profile created"
    
    # Add web app endpoints to Traffic Manager
    log "Adding endpoints to Traffic Manager..."
    
    # Get web app resource IDs
    WEBAPP_EAST_ID=$(az webapp show \
        --name "${WEB_APP_EAST}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    WEBAPP_WEST_ID=$(az webapp show \
        --name "${WEB_APP_WEST}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    WEBAPP_EUROPE_ID=$(az webapp show \
        --name "${WEB_APP_EUROPE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    # Add endpoints
    az network traffic-manager endpoint create \
        --name east-endpoint \
        --profile-name "${TRAFFIC_MANAGER_PROFILE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --type azureEndpoints \
        --target-resource-id "${WEBAPP_EAST_ID}" \
        --priority 1 &
    
    az network traffic-manager endpoint create \
        --name west-endpoint \
        --profile-name "${TRAFFIC_MANAGER_PROFILE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --type azureEndpoints \
        --target-resource-id "${WEBAPP_WEST_ID}" \
        --priority 2 &
    
    az network traffic-manager endpoint create \
        --name europe-endpoint \
        --profile-name "${TRAFFIC_MANAGER_PROFILE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --type azureEndpoints \
        --target-resource-id "${WEBAPP_EUROPE_ID}" \
        --priority 3 &
    
    wait
    success "Traffic Manager configured with multi-region endpoints"
}

# =============================================================================
# Azure Load Testing Resource
# =============================================================================
create_load_testing_resource() {
    log "Creating Azure Load Testing resource..."
    
    # Create Azure Load Testing resource
    az load test create \
        --name "${LOAD_TEST_RESOURCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}"
    
    success "Azure Load Testing resource created: ${LOAD_TEST_RESOURCE}"
}

# =============================================================================
# Function App for Monitoring
# =============================================================================
create_function_app() {
    log "Creating monitoring Function App..."
    
    # Create storage account for Function App
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2
    
    success "Storage account created: ${STORAGE_ACCOUNT}"
    
    # Create Function App with managed identity
    az functionapp create \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime python \
        --runtime-version 3.9 \
        --functions-version 4 \
        --assign-identity [system]
    
    success "Function App created with managed identity"
    
    # Configure Function App settings
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
            "TRAFFIC_MANAGER_PROFILE=${TRAFFIC_MANAGER_PROFILE}" \
            "RESOURCE_GROUP=${RESOURCE_GROUP}" \
            "SUBSCRIPTION_ID=${SUBSCRIPTION_ID}"
    
    success "Function App configuration completed"
}

# =============================================================================
# Application Insights and Monitoring
# =============================================================================
configure_monitoring() {
    log "Configuring Application Insights and monitoring..."
    
    # Create Application Insights for comprehensive monitoring
    az monitor app-insights component create \
        --app "${FUNCTION_APP_NAME}-insights" \
        --location "${LOCATION}" \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace "${LOG_ANALYTICS_WORKSPACE}"
    
    success "Application Insights created"
    
    # Get Application Insights connection string
    AI_CONNECTION_STRING=$(az monitor app-insights component show \
        --app "${FUNCTION_APP_NAME}-insights" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString --output tsv)
    
    # Configure web apps with Application Insights
    az webapp config appsettings set \
        --name "${WEB_APP_EAST}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "APPLICATIONINSIGHTS_CONNECTION_STRING=${AI_CONNECTION_STRING}" &
    
    az webapp config appsettings set \
        --name "${WEB_APP_WEST}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "APPLICATIONINSIGHTS_CONNECTION_STRING=${AI_CONNECTION_STRING}" &
    
    az webapp config appsettings set \
        --name "${WEB_APP_EUROPE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "APPLICATIONINSIGHTS_CONNECTION_STRING=${AI_CONNECTION_STRING}" &
    
    wait
    success "Application Insights configured for all web applications"
}

# =============================================================================
# Function Code Deployment
# =============================================================================
deploy_function_code() {
    log "Deploying self-healing function code..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Create function requirements
    cat > requirements.txt << 'EOF'
azure-functions
azure-mgmt-trafficmanager
azure-identity
azure-monitor-query
requests
EOF
    
    # Create main function code
    cat > __init__.py << 'EOF'
import azure.functions as func
import json
import logging
import os
from azure.identity import DefaultAzureCredential
from azure.mgmt.trafficmanager import TrafficManagerManagementClient
from azure.monitor.query import LogsQueryClient
import requests
from datetime import datetime, timedelta

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Self-healing function triggered')
    
    try:
        # Parse alert data
        alert_data = req.get_json()
        logging.info(f'Alert received: {alert_data}')
        
        # Initialize Azure clients
        credential = DefaultAzureCredential()
        subscription_id = os.environ['SUBSCRIPTION_ID']
        resource_group = os.environ['RESOURCE_GROUP']
        tm_profile = os.environ['TRAFFIC_MANAGER_PROFILE']
        
        tm_client = TrafficManagerManagementClient(credential, subscription_id)
        
        # Evaluate endpoint health and performance
        unhealthy_endpoints = evaluate_endpoint_health()
        
        # Take corrective actions
        for endpoint in unhealthy_endpoints:
            disable_endpoint(tm_client, resource_group, tm_profile, endpoint)
            trigger_load_test(endpoint)
        
        return func.HttpResponse(
            json.dumps({"status": "success", "actions_taken": len(unhealthy_endpoints)}),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logging.error(f'Error in self-healing function: {str(e)}')
        return func.HttpResponse(
            json.dumps({"status": "error", "message": str(e)}),
            status_code=500,
            mimetype="application/json"
        )

def evaluate_endpoint_health():
    """Evaluate endpoint health based on multiple metrics"""
    # Implement health check logic based on monitoring data
    logging.info('Evaluating endpoint health')
    return []

def disable_endpoint(tm_client, resource_group, profile_name, endpoint_name):
    """Disable unhealthy endpoint in Traffic Manager"""
    logging.info(f'Disabling endpoint: {endpoint_name}')
    try:
        tm_client.endpoints.update(
            resource_group,
            profile_name,
            'azureEndpoints',
            endpoint_name,
            {'endpoint_status': 'Disabled'}
        )
        logging.info(f'Successfully disabled endpoint: {endpoint_name}')
    except Exception as e:
        logging.error(f'Failed to disable endpoint {endpoint_name}: {str(e)}')

def trigger_load_test(endpoint):
    """Trigger load test for recovered endpoint"""
    logging.info(f'Triggering load test for: {endpoint}')
    # Implement load test triggering logic
    pass
EOF
    
    # Create function configuration
    cat > function.json << 'EOF'
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["post"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "$return"
    }
  ]
}
EOF
    
    # Package and deploy function
    zip -r function.zip .
    az functionapp deployment source config-zip \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --src function.zip
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    
    success "Self-healing function deployed successfully"
}

# =============================================================================
# Function Permissions
# =============================================================================
configure_function_permissions() {
    log "Configuring Function App permissions..."
    
    # Get Function App managed identity
    FUNCTION_IDENTITY=$(az functionapp identity show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query principalId --output tsv)
    
    # Grant Traffic Manager Contributor role
    az role assignment create \
        --assignee "${FUNCTION_IDENTITY}" \
        --role "Traffic Manager Contributor" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
    
    # Grant Monitoring Reader role for telemetry access
    az role assignment create \
        --assignee "${FUNCTION_IDENTITY}" \
        --role "Monitoring Reader" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
    
    # Grant Load Test Contributor role
    az role assignment create \
        --assignee "${FUNCTION_IDENTITY}" \
        --role "Load Test Contributor" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
    
    success "Function App permissions configured successfully"
}

# =============================================================================
# Alert Rules and Automation
# =============================================================================
configure_alert_rules() {
    log "Configuring alert rules and automation..."
    
    # Get function URL (simplified - in production would need proper function key)
    FUNCTION_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net/api/self-healing"
    
    # Create action group for function invocation
    az monitor action-group create \
        --name ag-self-healing \
        --resource-group "${RESOURCE_GROUP}" \
        --short-name selfheal \
        --webhook-receiver webhook-function "${FUNCTION_URL}"
    
    success "Action group created for function invocation"
    
    # Create alert rules for each web app
    for webapp in "${WEB_APP_EAST}" "${WEB_APP_WEST}" "${WEB_APP_EUROPE}"; do
        # Get web app resource ID
        WEBAPP_ID=$(az webapp show --name "$webapp" --resource-group "${RESOURCE_GROUP}" --query id --output tsv)
        
        # Create alert rule for response time degradation
        az monitor metrics alert create \
            --name "alert-response-time-${webapp}" \
            --resource-group "${RESOURCE_GROUP}" \
            --scopes "$WEBAPP_ID" \
            --condition "avg requests/duration > 5000" \
            --window-size 5m \
            --evaluation-frequency 1m \
            --action ag-self-healing \
            --description "Alert when average response time exceeds 5 seconds for ${webapp}"
        
        # Create alert rule for availability degradation
        az monitor metrics alert create \
            --name "alert-availability-${webapp}" \
            --resource-group "${RESOURCE_GROUP}" \
            --scopes "$WEBAPP_ID" \
            --condition "avg requests/count < 1" \
            --window-size 3m \
            --evaluation-frequency 1m \
            --action ag-self-healing \
            --description "Alert when request rate drops below threshold for ${webapp}"
    done
    
    success "Alert rules configured for automated self-healing"
}

# =============================================================================
# Validation
# =============================================================================
validate_deployment() {
    log "Validating deployment..."
    
    # Check Traffic Manager status
    TM_STATUS=$(az network traffic-manager profile show \
        --name "${TRAFFIC_MANAGER_PROFILE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query profileStatus --output tsv)
    
    if [ "$TM_STATUS" = "Enabled" ]; then
        success "Traffic Manager profile is enabled"
    else
        error "Traffic Manager profile is not enabled"
        return 1
    fi
    
    # Check endpoint health
    ENDPOINT_COUNT=$(az network traffic-manager endpoint list \
        --profile-name "${TRAFFIC_MANAGER_PROFILE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --type azureEndpoints \
        --query "length(@)")
    
    if [ "$ENDPOINT_COUNT" -eq 3 ]; then
        success "All 3 endpoints are configured"
    else
        error "Expected 3 endpoints, found $ENDPOINT_COUNT"
        return 1
    fi
    
    # Check Function App status
    FUNCTION_STATUS=$(az functionapp show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query state --output tsv)
    
    if [ "$FUNCTION_STATUS" = "Running" ]; then
        success "Function App is running"
    else
        warning "Function App status: $FUNCTION_STATUS"
    fi
    
    # Check Load Testing resource
    LOAD_TEST_STATUS=$(az load test show \
        --name "${LOAD_TEST_RESOURCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query provisioningState --output tsv)
    
    if [ "$LOAD_TEST_STATUS" = "Succeeded" ]; then
        success "Load Testing resource is ready"
    else
        warning "Load Testing resource status: $LOAD_TEST_STATUS"
    fi
    
    success "Deployment validation completed"
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
    log "Starting Azure Self-Healing Infrastructure deployment..."
    
    # Execute deployment steps
    check_prerequisites
    setup_configuration
    create_foundational_resources
    create_web_applications
    configure_traffic_manager
    create_load_testing_resource
    create_function_app
    configure_monitoring
    deploy_function_code
    configure_function_permissions
    configure_alert_rules
    validate_deployment
    
    # Display deployment summary
    echo ""
    echo "=============================================="
    echo "    DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "=============================================="
    echo ""
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Traffic Manager FQDN: ${TRAFFIC_MANAGER_PROFILE}.trafficmanager.net"
    echo "Function App: ${FUNCTION_APP_NAME}"
    echo "Load Testing Resource: ${LOAD_TEST_RESOURCE}"
    echo ""
    echo "Next Steps:"
    echo "1. Test the Traffic Manager endpoint: https://${TRAFFIC_MANAGER_PROFILE}.trafficmanager.net"
    echo "2. Monitor the applications in Application Insights"
    echo "3. Review alert rules in Azure Monitor"
    echo "4. Test failover scenarios using the Function App"
    echo ""
    echo "Configuration saved to: .deployment_config"
    echo "Use destroy.sh to clean up resources when done."
    echo ""
    
    success "Self-healing infrastructure deployment completed!"
}

# Run main function
main "$@"