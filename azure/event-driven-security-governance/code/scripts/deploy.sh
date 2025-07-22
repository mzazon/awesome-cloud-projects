#!/bin/bash

# =============================================================================
# Deploy Script for Azure Security Governance Workflows
# Recipe: Event-Driven Security Governance with Event Grid and Managed Identity
# =============================================================================

set -e
set -o pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$ERROR_LOG"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    log_error "Error occurred in script at line $1. Exit code: $2"
    log_error "Check $ERROR_LOG for more details"
    exit 1
}

trap 'handle_error $LINENO $?' ERR

# Functions
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '."azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log "Azure CLI version: $az_version"
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Check required tools
    local required_tools=("openssl" "zip" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool '$tool' is not installed"
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    log "Generated random suffix: $RANDOM_SUFFIX"
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-security-governance-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set specific resource names
    export EVENT_GRID_TOPIC="eg-security-governance-${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-security-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stsecurity${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_WORKSPACE="law-security-${RANDOM_SUFFIX}"
    export ACTION_GROUP="ag-security-${RANDOM_SUFFIX}"
    
    log "Environment variables set:"
    log "  RESOURCE_GROUP: $RESOURCE_GROUP"
    log "  LOCATION: $LOCATION"
    log "  SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
    log "  EVENT_GRID_TOPIC: $EVENT_GRID_TOPIC"
    log "  FUNCTION_APP: $FUNCTION_APP"
    log "  STORAGE_ACCOUNT: $STORAGE_ACCOUNT"
    log "  LOG_ANALYTICS_WORKSPACE: $LOG_ANALYTICS_WORKSPACE"
    log "  ACTION_GROUP: $ACTION_GROUP"
    
    log_success "Environment variables configured"
}

create_resource_group() {
    log "Creating resource group..."
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=security-governance environment=demo \
               owner=admin compliance=required \
        --output none
    
    log_success "Resource group created: $RESOURCE_GROUP"
}

create_log_analytics_workspace() {
    log "Creating Log Analytics workspace..."
    
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --location "$LOCATION" \
        --tags purpose=compliance-monitoring \
        --output none
    
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query customerId --output tsv)
    
    log_success "Log Analytics workspace created with ID: $WORKSPACE_ID"
}

create_event_grid_topic() {
    log "Creating Event Grid custom topic..."
    
    az eventgrid topic create \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=security-events compliance=required \
        --output none
    
    # Get topic endpoint and access key
    export TOPIC_ENDPOINT=$(az eventgrid topic show \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query endpoint --output tsv)
    
    export TOPIC_KEY=$(az eventgrid topic key list \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    log_success "Event Grid topic created at: $TOPIC_ENDPOINT"
}

create_storage_account() {
    log "Creating storage account for Function App..."
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --tags purpose=function-storage compliance=required \
        --output none
    
    # Retrieve storage connection string
    export STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    log_success "Storage account created for Function App support"
}

create_function_app() {
    log "Creating Azure Function App with system-assigned managed identity..."
    
    az functionapp create \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --consumption-plan-location "$LOCATION" \
        --runtime python \
        --runtime-version 3.9 \
        --functions-version 4 \
        --assign-identity \
        --tags purpose=security-automation compliance=required \
        --output none
    
    # Get the managed identity principal ID
    export FUNCTION_PRINCIPAL_ID=$(az functionapp identity show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId --output tsv)
    
    log_success "Function App created with managed identity: $FUNCTION_PRINCIPAL_ID"
}

assign_rbac_permissions() {
    log "Assigning RBAC permissions to managed identity..."
    
    # Wait for managed identity to propagate
    sleep 30
    
    # Assign Security Reader role for compliance checking
    az role assignment create \
        --assignee "$FUNCTION_PRINCIPAL_ID" \
        --role "Security Reader" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
        --output none
    
    # Assign Contributor role for remediation actions
    az role assignment create \
        --assignee "$FUNCTION_PRINCIPAL_ID" \
        --role "Contributor" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
        --output none
    
    # Assign Monitoring Contributor for Azure Monitor operations
    az role assignment create \
        --assignee "$FUNCTION_PRINCIPAL_ID" \
        --role "Monitoring Contributor" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
        --output none
    
    log_success "RBAC permissions assigned to Function App managed identity"
}

configure_function_app_settings() {
    log "Configuring Function App settings for Event Grid integration..."
    
    # Create Application Insights first
    local app_insights_key=$(az monitor app-insights component create \
        --app "${FUNCTION_APP}-insights" \
        --location "$LOCATION" \
        --resource-group "$RESOURCE_GROUP" \
        --workspace "$LOG_ANALYTICS_WORKSPACE" \
        --query instrumentationKey --output tsv)
    
    # Configure Function App settings
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings "EventGridTopicEndpoint=$TOPIC_ENDPOINT" \
                   "EventGridTopicKey=$TOPIC_KEY" \
                   "LogAnalyticsWorkspaceId=$WORKSPACE_ID" \
                   "FUNCTIONS_WORKER_RUNTIME=python" \
                   "AzureWebJobsFeatureFlags=EnableWorkerIndexing" \
                   "APPINSIGHTS_INSTRUMENTATIONKEY=$app_insights_key" \
        --output none
    
    log_success "Function App configured with Event Grid and monitoring settings"
}

create_function_code() {
    log "Creating and deploying security assessment function code..."
    
    # Create temporary directory for function code
    local temp_dir=$(mktemp -d)
    local function_dir="$temp_dir/SecurityEventProcessor"
    
    mkdir -p "$function_dir"
    
    # Create function configuration
    cat > "$function_dir/function.json" << 'EOF'
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "authLevel": "function",
      "type": "eventGridTrigger",
      "direction": "in",
      "name": "event"
    }
  ]
}
EOF
    
    # Create Python function code
    cat > "$function_dir/__init__.py" << 'EOF'
import azure.functions as func
import json
import logging
from azure.identity import DefaultAzureCredential
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.monitor import MonitorManagementClient
import os

def main(event: func.EventGridEvent):
    logging.info(f'Processing security event: {event.get_json()}')
    
    try:
        # Parse event data
        event_data = event.get_json()
        resource_uri = event_data.get('subject', '')
        operation_name = event_data.get('data', {}).get('operationName', '')
        
        logging.info(f'Resource URI: {resource_uri}')
        logging.info(f'Operation: {operation_name}')
        
        # Initialize Azure clients with managed identity
        credential = DefaultAzureCredential()
        
        # Get subscription ID from environment or event
        subscription_id = os.environ.get('SUBSCRIPTION_ID', event_data.get('data', {}).get('subscriptionId', ''))
        
        # Perform security assessment based on resource type
        if 'Microsoft.Compute/virtualMachines' in operation_name:
            assess_vm_security(resource_uri, credential, subscription_id)
        elif 'Microsoft.Network/networkSecurityGroups' in operation_name:
            assess_nsg_security(resource_uri, credential, subscription_id)
        elif 'Microsoft.Storage/storageAccounts' in operation_name:
            assess_storage_security(resource_uri, credential, subscription_id)
        else:
            logging.info(f'No security assessment defined for operation: {operation_name}')
            
    except Exception as e:
        logging.error(f'Error processing security event: {str(e)}')
        raise

def assess_vm_security(resource_uri, credential, subscription_id):
    logging.info(f'Assessing VM security for: {resource_uri}')
    # Implementation for VM security checks
    # This would include checks for:
    # - Disk encryption
    # - Network security group rules
    # - Endpoint protection
    # - Update management
    
def assess_nsg_security(resource_uri, credential, subscription_id):
    logging.info(f'Assessing NSG security for: {resource_uri}')
    # Implementation for NSG security checks
    # This would include checks for:
    # - Open ports to internet
    # - Overly permissive rules
    # - Missing required security rules
    
def assess_storage_security(resource_uri, credential, subscription_id):
    logging.info(f'Assessing Storage security for: {resource_uri}')
    # Implementation for Storage security checks
    # This would include checks for:
    # - Encryption at rest
    # - Public access settings
    # - Network access rules
    # - Audit logging
EOF
    
    # Create requirements file
    cat > "$temp_dir/requirements.txt" << 'EOF'
azure-functions
azure-identity
azure-mgmt-resource
azure-mgmt-monitor
azure-mgmt-storage
azure-mgmt-compute
azure-mgmt-network
EOF
    
    # Create host.json for Function App
    cat > "$temp_dir/host.json" << 'EOF'
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
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[2.*, 3.0.0)"
  }
}
EOF
    
    # Package and deploy function
    cd "$temp_dir"
    zip -r security-function.zip . > /dev/null 2>&1
    
    az functionapp deployment source config-zip \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --src security-function.zip \
        --output none
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    log_success "Security assessment function deployed successfully"
}

create_event_grid_subscription() {
    log "Creating Event Grid subscription for resource changes..."
    
    # Wait for function to be fully deployed
    sleep 60
    
    az eventgrid event-subscription create \
        --name "security-governance-subscription" \
        --source-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
        --endpoint-type azurefunction \
        --endpoint "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP/functions/SecurityEventProcessor" \
        --included-event-types Microsoft.Resources.ResourceWriteSuccess \
                                Microsoft.Resources.ResourceDeleteSuccess \
                                Microsoft.Resources.ResourceActionSuccess \
        --advanced-filter data.operationName StringBeginsWith Microsoft.Compute/virtualMachines \
                           data.operationName StringBeginsWith Microsoft.Network/networkSecurityGroups \
                           data.operationName StringBeginsWith Microsoft.Storage/storageAccounts \
        --output none
    
    log_success "Event Grid subscription created for resource monitoring"
}

create_monitoring_alerts() {
    log "Creating Azure Monitor alert rules for security events..."
    
    # Create Action Group for alert notifications
    az monitor action-group create \
        --name "$ACTION_GROUP" \
        --resource-group "$RESOURCE_GROUP" \
        --short-name "SecAlert" \
        --email-receivers name="SecurityTeam" email="${SECURITY_EMAIL:-admin@example.com}" \
        --output none
    
    # Create alert rule for security violations
    az monitor metrics alert create \
        --name "SecurityViolationAlert" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP" \
        --condition "count FunctionExecutionCount > 5" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --action-groups "$ACTION_GROUP" \
        --description "Alert when security violations exceed threshold" \
        --severity 2 \
        --output none
    
    # Create alert rule for function failures
    az monitor metrics alert create \
        --name "SecurityFunctionFailureAlert" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP" \
        --condition "count FunctionExecutionFailures > 0" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --action-groups "$ACTION_GROUP" \
        --description "Alert when security function executions fail" \
        --severity 1 \
        --output none
    
    log_success "Azure Monitor alert rules configured for security governance"
}

save_deployment_info() {
    log "Saving deployment information..."
    
    local info_file="${SCRIPT_DIR}/deployment_info.json"
    
    cat > "$info_file" << EOF
{
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "resource_group": "$RESOURCE_GROUP",
  "location": "$LOCATION",
  "subscription_id": "$SUBSCRIPTION_ID",
  "resources": {
    "event_grid_topic": "$EVENT_GRID_TOPIC",
    "function_app": "$FUNCTION_APP",
    "storage_account": "$STORAGE_ACCOUNT",
    "log_analytics_workspace": "$LOG_ANALYTICS_WORKSPACE",
    "action_group": "$ACTION_GROUP",
    "function_principal_id": "$FUNCTION_PRINCIPAL_ID"
  },
  "endpoints": {
    "topic_endpoint": "$TOPIC_ENDPOINT",
    "workspace_id": "$WORKSPACE_ID"
  },
  "random_suffix": "$RANDOM_SUFFIX"
}
EOF
    
    log_success "Deployment information saved to: $info_file"
}

validate_deployment() {
    log "Validating deployment..."
    
    # Check Event Grid topic status
    local topic_status=$(az eventgrid topic show \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query provisioningState --output tsv)
    
    if [ "$topic_status" != "Succeeded" ]; then
        log_error "Event Grid topic is not in Succeeded state: $topic_status"
        return 1
    fi
    
    # Check Function App status
    local func_status=$(az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query state --output tsv)
    
    if [ "$func_status" != "Running" ]; then
        log_error "Function App is not in Running state: $func_status"
        return 1
    fi
    
    # Check Event Grid subscription
    local sub_count=$(az eventgrid event-subscription list \
        --source-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
        --query "length([?name=='security-governance-subscription'])" --output tsv)
    
    if [ "$sub_count" != "1" ]; then
        log_error "Event Grid subscription not found or multiple found: $sub_count"
        return 1
    fi
    
    log_success "Deployment validation completed successfully"
}

print_deployment_summary() {
    log "Deployment Summary:"
    log "==================="
    log "Resource Group: $RESOURCE_GROUP"
    log "Location: $LOCATION"
    log "Event Grid Topic: $EVENT_GRID_TOPIC"
    log "Function App: $FUNCTION_APP"
    log "Storage Account: $STORAGE_ACCOUNT"
    log "Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    log "Action Group: $ACTION_GROUP"
    log ""
    log "Next Steps:"
    log "1. Test the security governance system by creating a test VM"
    log "2. Monitor function execution logs in Azure Portal"
    log "3. Configure additional security policies as needed"
    log "4. Set up custom alert recipients in the Action Group"
    log ""
    log "To clean up resources, run: ./destroy.sh"
}

# Main execution
main() {
    log "Starting Azure Security Governance Workflows deployment..."
    log "=========================================================="
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_log_analytics_workspace
    create_event_grid_topic
    create_storage_account
    create_function_app
    assign_rbac_permissions
    configure_function_app_settings
    create_function_code
    create_event_grid_subscription
    create_monitoring_alerts
    save_deployment_info
    validate_deployment
    print_deployment_summary
    
    log_success "Deployment completed successfully!"
    log "Check the deployment logs at: $LOG_FILE"
    
    if [ -f "$ERROR_LOG" ]; then
        log_warning "Some warnings/errors were logged to: $ERROR_LOG"
    fi
}

# Run main function
main "$@"