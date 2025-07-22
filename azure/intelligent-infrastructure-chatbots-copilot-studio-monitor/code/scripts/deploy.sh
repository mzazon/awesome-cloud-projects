#!/bin/bash

# =============================================================================
# AZURE INFRASTRUCTURE CHATBOT DEPLOYMENT SCRIPT
# =============================================================================
# This script deploys the infrastructure for building intelligent infrastructure
# chatbots with Azure Copilot Studio and Azure Monitor
#
# Prerequisites:
# - Azure CLI v2.50.0 or later
# - Valid Azure subscription with appropriate permissions
# - Bash shell environment
# =============================================================================

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/azure-chatbot-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly DEPLOYMENT_STATE_FILE="/tmp/azure-chatbot-deployment-state.json"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check logs at: ${LOG_FILE}"
    log_error "To clean up partial deployment, run: ./destroy.sh --force"
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites checking
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI v2.50.0 or later."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: ${az_version}"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random suffixes."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Configuration setup
setup_configuration() {
    log_info "Setting up deployment configuration..."
    
    # Generate unique suffix for resource names
    readonly RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-chatbot-infrastructure-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Define resource names
    export FUNCTION_APP_NAME="func-infra-bot-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stinfrabot${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_WORKSPACE="law-infra-bot-${RANDOM_SUFFIX}"
    export APP_INSIGHTS_NAME="ai-infra-bot-${RANDOM_SUFFIX}"
    
    # Validate storage account name length (max 24 characters)
    if [ ${#STORAGE_ACCOUNT_NAME} -gt 24 ]; then
        log_error "Storage account name too long: ${STORAGE_ACCOUNT_NAME}"
        exit 1
    fi
    
    # Save deployment state
    cat > "${DEPLOYMENT_STATE_FILE}" << EOF
{
    "resource_group": "${RESOURCE_GROUP}",
    "location": "${LOCATION}",
    "subscription_id": "${SUBSCRIPTION_ID}",
    "function_app_name": "${FUNCTION_APP_NAME}",
    "storage_account_name": "${STORAGE_ACCOUNT_NAME}",
    "log_analytics_workspace": "${LOG_ANALYTICS_WORKSPACE}",
    "app_insights_name": "${APP_INSIGHTS_NAME}",
    "random_suffix": "${RANDOM_SUFFIX}",
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log_info "Configuration:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  Subscription: ${SUBSCRIPTION_ID}"
    log_info "  Function App: ${FUNCTION_APP_NAME}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
    log_info "  Log Analytics: ${LOG_ANALYTICS_WORKSPACE}"
    log_info "  App Insights: ${APP_INSIGHTS_NAME}"
    
    log_success "Configuration setup completed"
}

# Resource group creation
create_resource_group() {
    log_info "Creating resource group..."
    
    # Check if resource group already exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=infrastructure-chatbot environment=demo \
            --output none
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Log Analytics workspace creation
create_log_analytics_workspace() {
    log_info "Creating Log Analytics workspace..."
    
    # Check if workspace already exists
    if az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" &> /dev/null; then
        log_warning "Log Analytics workspace ${LOG_ANALYTICS_WORKSPACE} already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
            --location "${LOCATION}" \
            --sku PerGB2018 \
            --output none
        
        # Wait for workspace to be fully provisioned
        log_info "Waiting for Log Analytics workspace to be ready..."
        sleep 30
        
        log_success "Log Analytics workspace created: ${LOG_ANALYTICS_WORKSPACE}"
    fi
}

# Storage account creation
create_storage_account() {
    log_info "Creating storage account for Function App..."
    
    # Check if storage account already exists
    if az storage account show \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account ${STORAGE_ACCOUNT_NAME} already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --output none
        
        log_success "Storage account created: ${STORAGE_ACCOUNT_NAME}"
    fi
}

# Function App creation
create_function_app() {
    log_info "Creating Function App..."
    
    # Check if Function App already exists
    if az functionapp show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FUNCTION_APP_NAME}" &> /dev/null; then
        log_warning "Function App ${FUNCTION_APP_NAME} already exists"
    else
        az functionapp create \
            --resource-group "${RESOURCE_GROUP}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime python \
            --runtime-version 3.9 \
            --functions-version 4 \
            --name "${FUNCTION_APP_NAME}" \
            --storage-account "${STORAGE_ACCOUNT_NAME}" \
            --output none
        
        # Wait for Function App to be ready
        log_info "Waiting for Function App to be ready..."
        sleep 60
        
        log_success "Function App created: ${FUNCTION_APP_NAME}"
    fi
}

# Application Insights creation
create_application_insights() {
    log_info "Creating Application Insights..."
    
    # Check if Application Insights already exists
    if az monitor app-insights component show \
        --app "${APP_INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Application Insights ${APP_INSIGHTS_NAME} already exists"
    else
        az monitor app-insights component create \
            --app "${APP_INSIGHTS_NAME}" \
            --location "${LOCATION}" \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace "${LOG_ANALYTICS_WORKSPACE}" \
            --output none
        
        log_success "Application Insights created: ${APP_INSIGHTS_NAME}"
    fi
    
    # Get Application Insights instrumentation key
    log_info "Configuring Function App with Application Insights..."
    local appinsights_key
    appinsights_key=$(az monitor app-insights component show \
        --app "${APP_INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query instrumentationKey --output tsv)
    
    # Configure Function App with Application Insights
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "APPINSIGHTS_INSTRUMENTATIONKEY=${appinsights_key}" \
        --output none
    
    log_success "Application Insights configured for Function App"
}

# Function code deployment
deploy_function_code() {
    log_info "Preparing and deploying Function code..."
    
    # Create temporary directory for function code
    local temp_dir="/tmp/chatbot-functions-${RANDOM_SUFFIX}"
    mkdir -p "${temp_dir}"
    cd "${temp_dir}"
    
    # Create function structure
    mkdir -p QueryProcessor
    
    # Create function.json for HTTP trigger
    cat > QueryProcessor/function.json << 'EOF'
{
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
    
    # Create main function code
    cat > QueryProcessor/__init__.py << 'EOF'
import logging
import json
import os
from datetime import datetime, timedelta
import azure.functions as func
from azure.monitor.query import LogsQueryClient
from azure.identity import DefaultAzureCredential

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Processing infrastructure query request')
    
    try:
        # Parse request body
        req_body = req.get_json()
        user_query = req_body.get('query', '')
        
        # Initialize Azure Monitor client
        credential = DefaultAzureCredential()
        client = LogsQueryClient(credential)
        
        # Convert natural language to KQL
        kql_query = convert_to_kql(user_query)
        
        # Execute query against Log Analytics
        workspace_id = os.environ['LOG_ANALYTICS_WORKSPACE_ID']
        response = client.query_workspace(
            workspace_id=workspace_id,
            query=kql_query,
            timespan=timedelta(hours=1)
        )
        
        # Format response for chatbot
        formatted_response = format_response(response)
        
        return func.HttpResponse(
            json.dumps(formatted_response),
            mimetype="application/json",
            status_code=200
        )
        
    except Exception as e:
        logging.error(f"Error processing query: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": "Failed to process query"}),
            mimetype="application/json",
            status_code=500
        )

def convert_to_kql(user_query):
    """Convert natural language query to KQL"""
    query_lower = user_query.lower()
    
    if "cpu" in query_lower:
        return """
        Perf
        | where CounterName == "% Processor Time"
        | where TimeGenerated > ago(1h)
        | summarize avg(CounterValue) by Computer
        | order by avg_CounterValue desc
        """
    elif "memory" in query_lower:
        return """
        Perf
        | where CounterName == "Available MBytes"
        | where TimeGenerated > ago(1h)
        | summarize avg(CounterValue) by Computer
        | order by avg_CounterValue asc
        """
    elif "disk" in query_lower:
        return """
        Perf
        | where CounterName == "% Free Space"
        | where TimeGenerated > ago(1h)
        | summarize avg(CounterValue) by Computer
        | order by avg_CounterValue asc
        """
    else:
        return """
        Heartbeat
        | where TimeGenerated > ago(1h)
        | summarize count() by Computer
        | order by count_ desc
        """

def format_response(response):
    """Format Log Analytics response for chatbot"""
    if not response.tables:
        return {"message": "No data found for your query"}
    
    table = response.tables[0]
    results = []
    
    for row in table.rows:
        result = {}
        for i, column in enumerate(table.columns):
            result[column.name] = row[i]
        results.append(result)
    
    return {
        "message": "Here are your infrastructure metrics:",
        "data": results[:5]  # Limit to top 5 results
    }
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
azure-functions
azure-monitor-query
azure-identity
EOF
    
    # Create host.json for function app configuration
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
  }
}
EOF
    
    # Package and deploy function
    log_info "Packaging function code..."
    zip -r chatbot-functions.zip . > /dev/null
    
    log_info "Deploying function to Azure..."
    az functionapp deployment source config-zip \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FUNCTION_APP_NAME}" \
        --src chatbot-functions.zip \
        --output none
    
    # Get Log Analytics workspace ID for configuration
    local workspace_id
    workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
        --query customerId --output tsv)
    
    # Configure function app settings
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "LOG_ANALYTICS_WORKSPACE_ID=${workspace_id}" \
        --output none
    
    # Enable managed identity for secure access
    az functionapp identity assign \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --output none
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "${temp_dir}"
    
    log_success "Function code deployed successfully"
}

# Configuration output
output_configuration() {
    log_info "Getting deployment configuration details..."
    
    # Get Function App URL
    local function_url
    function_url=$(az functionapp show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FUNCTION_APP_NAME}" \
        --query defaultHostName --output tsv)
    
    # Get function key
    local function_key
    function_key=$(az functionapp keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FUNCTION_APP_NAME}" \
        --query functionKeys.default --output tsv 2>/dev/null || echo "Key will be available after function restart")
    
    # Get Log Analytics workspace ID
    local workspace_id
    workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
        --query customerId --output tsv)
    
    # Output configuration details
    echo ""
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo ""
    log_info "Azure Copilot Studio Configuration Details:"
    log_info "  Function Endpoint: https://${function_url}/api/QueryProcessor"
    log_info "  Function Key: ${function_key}"
    log_info "  Log Analytics Workspace ID: ${workspace_id}"
    echo ""
    log_info "Resources Created:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Function App: ${FUNCTION_APP_NAME}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
    log_info "  Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}"
    log_info "  Application Insights: ${APP_INSIGHTS_NAME}"
    echo ""
    log_info "Next Steps:"
    log_info "1. Open Azure Copilot Studio in the Power Platform portal"
    log_info "2. Create a new chatbot and configure topics"
    log_info "3. Add the Function endpoint as a Power Automate action"
    log_info "4. Test the chatbot with infrastructure queries"
    echo ""
    log_info "Deployment state saved to: ${DEPLOYMENT_STATE_FILE}"
    log_info "Deployment logs saved to: ${LOG_FILE}"
}

# Validation
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check if all resources exist
    local resources=(
        "group:${RESOURCE_GROUP}"
        "functionapp:${FUNCTION_APP_NAME}"
        "storage:${STORAGE_ACCOUNT_NAME}"
        "workspace:${LOG_ANALYTICS_WORKSPACE}"
        "insights:${APP_INSIGHTS_NAME}"
    )
    
    local validation_failed=false
    
    for resource in "${resources[@]}"; do
        local type="${resource%%:*}"
        local name="${resource##*:}"
        
        case "${type}" in
            "group")
                if ! az group show --name "${name}" &> /dev/null; then
                    log_error "Resource group ${name} not found"
                    validation_failed=true
                fi
                ;;
            "functionapp")
                if ! az functionapp show --resource-group "${RESOURCE_GROUP}" --name "${name}" &> /dev/null; then
                    log_error "Function App ${name} not found"
                    validation_failed=true
                fi
                ;;
            "storage")
                if ! az storage account show --resource-group "${RESOURCE_GROUP}" --name "${name}" &> /dev/null; then
                    log_error "Storage account ${name} not found"
                    validation_failed=true
                fi
                ;;
            "workspace")
                if ! az monitor log-analytics workspace show --resource-group "${RESOURCE_GROUP}" --workspace-name "${name}" &> /dev/null; then
                    log_error "Log Analytics workspace ${name} not found"
                    validation_failed=true
                fi
                ;;
            "insights")
                if ! az monitor app-insights component show --resource-group "${RESOURCE_GROUP}" --app "${name}" &> /dev/null; then
                    log_error "Application Insights ${name} not found"
                    validation_failed=true
                fi
                ;;
        esac
    done
    
    if [ "${validation_failed}" = true ]; then
        log_error "Deployment validation failed"
        exit 1
    fi
    
    log_success "Deployment validation completed successfully"
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure infrastructure for intelligent infrastructure chatbots.

OPTIONS:
    -h, --help              Show this help message
    -l, --location LOCATION Set Azure region (default: eastus)
    -v, --verbose           Enable verbose logging
    --dry-run              Validate configuration without deploying
    --skip-validation      Skip deployment validation

ENVIRONMENT VARIABLES:
    AZURE_LOCATION         Override default Azure region

EXAMPLES:
    $0                     Deploy with default settings
    $0 -l westus2          Deploy to West US 2 region
    $0 --dry-run           Validate configuration only
    $0 -v                  Deploy with verbose logging

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -l|--location)
                if [[ -n $2 && $2 != -* ]]; then
                    export AZURE_LOCATION="$2"
                    shift 2
                else
                    log_error "Location requires a value"
                    exit 1
                fi
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            --dry-run)
                readonly DRY_RUN=true
                shift
                ;;
            --skip-validation)
                readonly SKIP_VALIDATION=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Main execution function
main() {
    echo "=== Azure Infrastructure ChatBot Deployment ==="
    echo "Starting deployment at $(date)"
    echo ""
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check if this is a dry run
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        setup_configuration
        log_success "Dry run completed successfully"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_configuration
    create_resource_group
    create_log_analytics_workspace
    create_storage_account
    create_function_app
    create_application_insights
    deploy_function_code
    
    # Validate deployment unless skipped
    if [[ "${SKIP_VALIDATION:-false}" != "true" ]]; then
        validate_deployment
    fi
    
    # Output configuration details
    output_configuration
    
    log_success "Deployment completed successfully at $(date)"
}

# Execute main function with all arguments
main "$@"