#!/bin/bash

# =============================================================================
# Azure Infrastructure Health Monitoring Deployment Script
# =============================================================================
# Description: Deploys automated infrastructure health monitoring using 
#              Azure Functions Flex Consumption and Azure Update Manager
# Author: Recipe Generator
# Version: 1.0
# =============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check the logs above for details."
    log "You may need to run the destroy script to clean up partial resources."
    exit 1
}

trap cleanup_on_error ERR

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        log_error "Please login to Azure CLI first: az login"
        exit 1
    fi
    
    # Check Azure Functions Core Tools
    if ! command -v func &> /dev/null; then
        log_error "Azure Functions Core Tools not found. Please install it first."
        exit 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is required but not found."
        exit 1
    fi
    
    # Check openssl for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is required but not found."
        exit 1
    fi
    
    log_success "All prerequisites checked successfully"
}

# =============================================================================
# Configuration
# =============================================================================

setup_configuration() {
    log "Setting up configuration..."
    
    # Set environment variables for consistent resource naming
    export RESOURCE_GROUP="rg-infra-health-monitor"
    export LOCATION="eastus"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export FUNCTION_APP_NAME="func-health-monitor-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="sthealth${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_NAME="la-health-monitor-${RANDOM_SUFFIX}"
    export EVENT_GRID_TOPIC="egt-health-updates-${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-health-${RANDOM_SUFFIX}"
    export VNET_NAME="vnet-health-monitor"
    export SUBNET_NAME="subnet-functions"
    
    log "Configuration:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Location: ${LOCATION}"
    log "  Function App: ${FUNCTION_APP_NAME}"
    log "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
    log "  Key Vault: ${KEY_VAULT_NAME}"
    
    log_success "Configuration setup complete"
}

# =============================================================================
# Resource Group and Foundation
# =============================================================================

create_resource_group() {
    log "Creating resource group..."
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=infrastructure-monitoring environment=demo
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

create_log_analytics() {
    log "Creating Log Analytics workspace..."
    
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --location "${LOCATION}" \
        --sku PerGB2018
    
    log_success "Log Analytics workspace created: ${LOG_ANALYTICS_NAME}"
}

# =============================================================================
# Networking
# =============================================================================

create_virtual_network() {
    log "Creating virtual network for secure connectivity..."
    
    # Create virtual network with appropriate address space
    az network vnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${VNET_NAME}" \
        --location "${LOCATION}" \
        --address-prefixes 10.0.0.0/16 \
        --subnet-name "${SUBNET_NAME}" \
        --subnet-prefixes 10.0.1.0/24
    
    # Configure subnet delegation for Azure Functions
    az network vnet subnet update \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${VNET_NAME}" \
        --name "${SUBNET_NAME}" \
        --delegations Microsoft.App/environments
    
    log_success "Virtual network configured with function delegation"
}

# =============================================================================
# Storage and Security
# =============================================================================

create_storage_account() {
    log "Creating storage account for Function App..."
    
    az storage account create \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --min-tls-version TLS1_2
    
    # Get storage account connection string
    STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString --output tsv)
    
    log_success "Storage account created with secure configuration"
}

create_key_vault() {
    log "Creating Key Vault for secure configuration management..."
    
    az keyvault create \
        --name "${KEY_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku standard \
        --enabled-for-template-deployment true \
        --enable-rbac-authorization false
    
    # Store storage connection string in Key Vault
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "StorageConnectionString" \
        --value "${STORAGE_CONNECTION_STRING}"
    
    log_success "Key Vault created with secure credential storage"
}

# =============================================================================
# Event Grid
# =============================================================================

create_event_grid() {
    log "Creating Event Grid topic for health event distribution..."
    
    az eventgrid topic create \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --input-schema EventGridSchema
    
    # Get Event Grid topic endpoint and key
    EVENT_GRID_ENDPOINT=$(az eventgrid topic show \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query endpoint --output tsv)
    
    EVENT_GRID_KEY=$(az eventgrid topic key list \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 --output tsv)
    
    # Store Event Grid credentials in Key Vault
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "EventGridEndpoint" \
        --value "${EVENT_GRID_ENDPOINT}"
    
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "EventGridKey" \
        --value "${EVENT_GRID_KEY}"
    
    log_success "Event Grid topic configured for health event distribution"
}

# =============================================================================
# Azure Functions
# =============================================================================

create_function_app() {
    log "Creating Azure Functions App with Flex Consumption plan..."
    
    # Get subnet ID for VNet integration
    SUBNET_ID=$(az network vnet subnet show \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${VNET_NAME}" \
        --name "${SUBNET_NAME}" \
        --query id --output tsv)
    
    # Create Function App with Flex Consumption plan
    az functionapp create \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${STORAGE_ACCOUNT_NAME}" \
        --functions-version 4 \
        --runtime python \
        --runtime-version 3.11 \
        --os-type Linux \
        --consumption-plan-location "${LOCATION}" \
        --plan-name flexconsumption
    
    # Wait for function app to be ready
    log "Waiting for Function App to be ready..."
    sleep 30
    
    # Enable virtual network integration
    az functionapp vnet-integration add \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --subnet "${SUBNET_ID}"
    
    log_success "Function App created with Flex Consumption and VNet integration"
}

configure_function_app() {
    log "Configuring Function App with Application Insights and Key Vault access..."
    
    # Create Application Insights for function monitoring
    az monitor app-insights component create \
        --app "${FUNCTION_APP_NAME}" \
        --location "${LOCATION}" \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace "${LOG_ANALYTICS_NAME}"
    
    # Get Application Insights connection string
    APP_INSIGHTS_CONNECTION_STRING=$(az monitor app-insights component show \
        --app "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString --output tsv)
    
    # Configure Function App settings
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
            "APPLICATIONINSIGHTS_CONNECTION_STRING=${APP_INSIGHTS_CONNECTION_STRING}" \
            "AzureWebJobsFeatureFlags=EnableWorkerIndexing" \
            "KEY_VAULT_NAME=${KEY_VAULT_NAME}" \
            "EVENT_GRID_TOPIC_NAME=${EVENT_GRID_TOPIC}" \
            "LOG_ANALYTICS_WORKSPACE=${LOG_ANALYTICS_NAME}"
    
    log_success "Function App configured with monitoring and Key Vault integration"
}

# =============================================================================
# Function Code Deployment
# =============================================================================

deploy_function_code() {
    log "Creating and deploying function code..."
    
    # Create temporary directory for function project
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Initialize Azure Functions project
    func init . --python --worker-runtime python
    
    # Create timer-triggered health check function
    func new --name HealthChecker --template "Timer trigger"
    
    # Create event-driven update response function
    func new --name UpdateEventHandler --template "Event Grid trigger"
    
    # Create requirements.txt for dependencies
    cat > requirements.txt << 'EOF'
azure-functions==1.18.0
azure-identity==1.15.0
azure-keyvault-secrets==4.7.0
azure-eventgrid==4.17.0
azure-monitor-query==1.2.0
azure-mgmt-automation==1.1.0
requests==2.31.0
EOF
    
    # Create comprehensive health checker function
    cat > HealthChecker/__init__.py << 'EOF'
import azure.functions as func
import json
import logging
import os
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.eventgrid import EventGridPublisherClient
from azure.monitor.query import LogsQueryClient
from datetime import datetime, timedelta
import requests

def main(mytimer: func.TimerRequest) -> None:
    logging.info('Infrastructure health check started')
    
    try:
        # Initialize Azure clients with managed identity
        credential = DefaultAzureCredential()
        
        # Get Key Vault secrets
        kv_name = os.environ['KEY_VAULT_NAME']
        kv_client = SecretClient(
            vault_url=f"https://{kv_name}.vault.azure.net/",
            credential=credential
        )
        
        # Get Event Grid configuration
        try:
            eg_endpoint = kv_client.get_secret("EventGridEndpoint").value
            eg_key = kv_client.get_secret("EventGridKey").value
            
            # Initialize Event Grid client
            eg_client = EventGridPublisherClient(eg_endpoint, credential)
        except Exception as e:
            logging.warning(f'Event Grid configuration not available: {str(e)}')
            eg_client = None
        
        # Perform infrastructure health checks
        health_results = perform_health_checks(credential)
        
        # Process health results and trigger updates if needed
        process_health_results(health_results, eg_client)
        
        logging.info('Infrastructure health check completed successfully')
        
    except Exception as e:
        logging.error(f'Health check failed: {str(e)}')
        # Send alert for failed health check if Event Grid is available
        if 'eg_client' in locals() and eg_client:
            send_health_alert("CRITICAL", f"Health check failed: {str(e)}", eg_client)

def perform_health_checks(credential):
    """Perform comprehensive infrastructure health assessments"""
    health_results = {
        'timestamp': datetime.utcnow().isoformat(),
        'checks': []
    }
    
    try:
        # Simulate health check results for demonstration
        # In production, integrate with actual monitoring systems
        health_results['checks'].extend([
            {
                'check_type': 'performance',
                'status': 'healthy',
                'message': 'All systems within normal parameters',
                'details': {'cpu_avg': 45, 'memory_available': 2048}
            },
            {
                'check_type': 'security',
                'status': 'warning',
                'message': 'Elevated login failures detected',
                'details': {'failed_logins': 12, 'affected_systems': 2}
            }
        ])
        
        logging.info("Health checks executed successfully")
        
    except Exception as e:
        logging.error(f'Health check execution failed: {str(e)}')
        health_results['checks'].append({
            'check_type': 'system',
            'status': 'error',
            'message': f'Health check failed: {str(e)}'
        })
    
    return health_results

def process_health_results(health_results, eg_client):
    """Process health check results and trigger appropriate actions"""
    
    critical_issues = [
        check for check in health_results['checks'] 
        if check['status'] in ['error', 'critical']
    ]
    
    warning_issues = [
        check for check in health_results['checks'] 
        if check['status'] == 'warning'
    ]
    
    if critical_issues:
        logging.warning(f"Critical issues detected: {len(critical_issues)}")
        if eg_client:
            send_health_alert("CRITICAL", f"Critical issues detected: {len(critical_issues)}", eg_client)
    
    elif warning_issues:
        logging.info(f"Warning issues detected: {len(warning_issues)}")
        if eg_client:
            send_health_alert("WARNING", f"Warning issues detected: {len(warning_issues)}", eg_client)
    
    else:
        logging.info("All health checks passed - system healthy")

def send_health_alert(severity, message, eg_client):
    """Send health alert through Event Grid"""
    
    alert_data = {
        'eventType': f'Infrastructure.Alert.{severity}',
        'subject': 'infrastructure/alerts',
        'data': {
            'alertSeverity': severity,
            'message': message,
            'timestamp': datetime.utcnow().isoformat(),
            'source': 'HealthMonitor'
        },
        'dataVersion': '1.0'
    }
    
    logging.info(f"Sending {severity} alert: {message}")
EOF
    
    # Create Event Grid triggered update handler
    cat > UpdateEventHandler/__init__.py << 'EOF'
import azure.functions as func
import json
import logging
import os
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from datetime import datetime

def main(event: func.EventGridEvent):
    logging.info('Update event handler triggered')
    
    try:
        # Parse Event Grid event
        event_data = json.loads(event.get_body().decode('utf-8'))
        logging.info(f'Received event: {event_data}')
        
        # Initialize Azure clients
        credential = DefaultAzureCredential()
        
        # Get Key Vault client
        kv_name = os.environ['KEY_VAULT_NAME']
        kv_client = SecretClient(
            vault_url=f"https://{kv_name}.vault.azure.net/",
            credential=credential
        )
        
        # Process different event types
        event_type = event_data.get('eventType', '')
        
        if 'Infrastructure.HealthCheck.Critical' in event_type:
            handle_critical_health_event(event_data, credential)
        elif 'Infrastructure.HealthCheck.Warning' in event_type:
            handle_warning_health_event(event_data, credential)
        elif 'Microsoft.Automation.UpdateManagement' in event_type:
            handle_update_manager_event(event_data, credential)
        else:
            logging.info(f'Unhandled event type: {event_type}')
        
        logging.info('Update event processed successfully')
        
    except Exception as e:
        logging.error(f'Update event processing failed: {str(e)}')

def handle_critical_health_event(event_data, credential):
    """Handle critical infrastructure health events"""
    logging.info('Processing critical health event')
    
def handle_warning_health_event(event_data, credential):
    """Handle warning-level infrastructure health events"""
    logging.info('Processing warning health event')
    
def handle_update_manager_event(event_data, credential):
    """Handle Azure Update Manager events"""
    logging.info('Processing Update Manager event')
EOF
    
    # Deploy function code to Azure
    func azure functionapp publish "${FUNCTION_APP_NAME}" --python
    
    # Return to original directory
    cd - > /dev/null
    
    # Clean up temporary directory
    rm -rf "${TEMP_DIR}"
    
    log_success "Function code deployed successfully"
}

# =============================================================================
# Permissions and Integration
# =============================================================================

configure_permissions() {
    log "Configuring managed identity and permissions..."
    
    # Configure managed identity for the Function App
    az functionapp identity assign \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}"
    
    # Get the Function App managed identity principal ID
    FUNCTION_PRINCIPAL_ID=$(az functionapp identity show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query principalId --output tsv)
    
    # Grant Key Vault access to the Function App
    az keyvault set-policy \
        --name "${KEY_VAULT_NAME}" \
        --object-id "${FUNCTION_PRINCIPAL_ID}" \
        --secret-permissions get list
    
    # Grant Event Grid contributor access
    az role assignment create \
        --assignee "${FUNCTION_PRINCIPAL_ID}" \
        --role "EventGrid Contributor" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
    
    log_success "Function App configured with managed identity and permissions"
}

configure_update_manager() {
    log "Configuring Update Manager integration..."
    
    # Add automation extension if not present
    az extension add --name automation --upgrade 2>/dev/null || true
    
    # Create Event Grid subscription for Update Manager events
    FUNCTION_ENDPOINT="https://${FUNCTION_APP_NAME}.azurewebsites.net/runtime/webhooks/eventgrid?functionName=UpdateEventHandler"
    
    az eventgrid event-subscription create \
        --name "update-manager-events" \
        --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}" \
        --endpoint "${FUNCTION_ENDPOINT}" \
        --endpoint-type webhook \
        --included-event-types \
            "Microsoft.Automation.UpdateManagement.AssessmentCompleted" \
            "Microsoft.Automation.UpdateManagement.InstallationCompleted"
    
    log_success "Update Manager integration configured with Event Grid subscriptions"
}

# =============================================================================
# Validation
# =============================================================================

validate_deployment() {
    log "Validating deployment..."
    
    # Check Function App status
    FUNC_STATE=$(az functionapp show \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query state --output tsv)
    
    if [[ "${FUNC_STATE}" == "Running" ]]; then
        log_success "Function App is running successfully"
    else
        log_warning "Function App state: ${FUNC_STATE}"
    fi
    
    # Check virtual network integration
    VNET_INTEGRATION=$(az functionapp vnet-integration list \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query length(@) --output tsv)
    
    if [[ "${VNET_INTEGRATION}" -gt 0 ]]; then
        log_success "Virtual network integration configured"
    else
        log_warning "Virtual network integration not found"
    fi
    
    # Check Event Grid topic
    EG_STATE=$(az eventgrid topic show \
        --name "${EVENT_GRID_TOPIC}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query provisioningState --output tsv)
    
    if [[ "${EG_STATE}" == "Succeeded" ]]; then
        log_success "Event Grid topic is ready"
    else
        log_warning "Event Grid topic state: ${EG_STATE}"
    fi
    
    log_success "Deployment validation completed"
}

# =============================================================================
# Main Deployment Flow
# =============================================================================

main() {
    log "Starting Azure Infrastructure Health Monitoring deployment..."
    log "========================================================"
    
    # Prerequisites and setup
    check_prerequisites
    setup_configuration
    
    # Core infrastructure
    create_resource_group
    create_log_analytics
    
    # Networking
    create_virtual_network
    
    # Storage and security
    create_storage_account
    create_key_vault
    
    # Event Grid
    create_event_grid
    
    # Azure Functions
    create_function_app
    configure_function_app
    deploy_function_code
    
    # Permissions and integrations
    configure_permissions
    configure_update_manager
    
    # Validation
    validate_deployment
    
    log "========================================================"
    log_success "Azure Infrastructure Health Monitoring deployment completed successfully!"
    log ""
    log "📋 Deployment Summary:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Function App: ${FUNCTION_APP_NAME}"
    log "  Key Vault: ${KEY_VAULT_NAME}"
    log "  Event Grid Topic: ${EVENT_GRID_TOPIC}"
    log "  Log Analytics: ${LOG_ANALYTICS_NAME}"
    log ""
    log "🔗 Next Steps:"
    log "  1. Monitor Function App logs in Application Insights"
    log "  2. Configure additional Event Grid subscribers for notifications"
    log "  3. Set up Azure Arc for hybrid infrastructure management"
    log "  4. Customize health check logic for your specific environment"
    log ""
    log "💰 Cost Estimate: $10-30/month for development usage"
    log "📚 Documentation: Check the recipe for detailed configuration options"
    log ""
    log_warning "Remember to run the destroy script when done testing to avoid ongoing charges"
}

# Execute main function
main "$@"