#!/bin/bash

# Azure Real-Time Collaborative Dashboard Deployment Script
# This script deploys a complete real-time monitoring dashboard using Azure Web PubSub and Azure Monitor

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

error_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "${ERROR_LOG}" >&2
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "${LOG_FILE}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "${LOG_FILE}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "${ERROR_LOG}"
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Initiating cleanup..."
    if [[ "${RESOURCE_GROUP:-}" != "" ]]; then
        warning "Cleaning up resources in group: ${RESOURCE_GROUP}"
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait 2>/dev/null || true
    fi
    exit 1
}

# Set error trap
trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --output tsv --query '"azure-cli"' 2>/dev/null || echo "0.0.0")
    local min_version="2.50.0"
    if [[ "$(printf '%s\n' "$min_version" "$az_version" | sort -V | head -n1)" != "$min_version" ]]; then
        error "Azure CLI version $min_version or higher required. Current version: $az_version"
        exit 1
    fi
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        warning "Node.js not found. Some development features may not work."
    else
        local node_version
        node_version=$(node --version | sed 's/v//')
        info "Node.js version: $node_version"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check for required tools
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is required for generating random suffixes."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Validate environment
validate_environment() {
    info "Validating environment..."
    
    # Get current subscription
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    info "Using Azure subscription: $subscription_id"
    
    # Check if location is valid
    if ! az account list-locations --query "[?name=='$LOCATION']" --output tsv | grep -q "$LOCATION"; then
        error "Invalid Azure location: $LOCATION"
        exit 1
    fi
    
    # Check resource group doesn't exist
    if az group exists --name "$RESOURCE_GROUP" --output tsv | grep -q "true"; then
        error "Resource group $RESOURCE_GROUP already exists"
        exit 1
    fi
    
    success "Environment validation completed"
}

# Set default values and environment variables
set_environment_variables() {
    info "Setting environment variables..."
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-collab-dashboard}"
    export LOCATION="${LOCATION:-eastus}"
    export RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
    export WEBPUBSUB_NAME="${WEBPUBSUB_NAME:-wps-dashboard-${RANDOM_SUFFIX}}"
    export STATIC_APP_NAME="${STATIC_APP_NAME:-swa-dashboard-${RANDOM_SUFFIX}}"
    export FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-dashboard-${RANDOM_SUFFIX}}"
    export STORAGE_NAME="${STORAGE_NAME:-stdashboard${RANDOM_SUFFIX}}"
    export APP_INSIGHTS_NAME="${APP_INSIGHTS_NAME:-appi-dashboard-${RANDOM_SUFFIX}}"
    export LOG_ANALYTICS_NAME="${LOG_ANALYTICS_NAME:-log-dashboard-${RANDOM_SUFFIX}}"
    
    # Display configuration
    info "Deployment configuration:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    info "  Random Suffix: $RANDOM_SUFFIX"
    info "  Web PubSub: $WEBPUBSUB_NAME"
    info "  Static Web App: $STATIC_APP_NAME"
    info "  Function App: $FUNCTION_APP_NAME"
    info "  Storage Account: $STORAGE_NAME"
    info "  App Insights: $APP_INSIGHTS_NAME"
    info "  Log Analytics: $LOG_ANALYTICS_NAME"
    
    # Validate naming conventions
    if [[ ${#STORAGE_NAME} -gt 24 ]]; then
        error "Storage account name too long (max 24 characters): $STORAGE_NAME"
        exit 1
    fi
    
    if [[ ! $STORAGE_NAME =~ ^[a-z0-9]+$ ]]; then
        error "Storage account name must contain only lowercase letters and numbers: $STORAGE_NAME"
        exit 1
    fi
    
    success "Environment variables configured"
}

# Create resource group
create_resource_group() {
    info "Creating resource group..."
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=collab-dashboard environment=demo \
        --output none
    
    success "Resource group created: $RESOURCE_GROUP"
}

# Create Log Analytics workspace
create_log_analytics() {
    info "Creating Log Analytics workspace..."
    
    az monitor log-analytics workspace create \
        --name "$LOG_ANALYTICS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --retention-time 30 \
        --output none
    
    # Store workspace ID
    LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
        --name "$LOG_ANALYTICS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    if [[ -z "$LOG_ANALYTICS_ID" ]]; then
        error "Failed to get Log Analytics workspace ID"
        exit 1
    fi
    
    success "Log Analytics workspace created: $LOG_ANALYTICS_NAME"
}

# Create Application Insights
create_application_insights() {
    info "Creating Application Insights..."
    
    az monitor app-insights component create \
        --app "$APP_INSIGHTS_NAME" \
        --location "$LOCATION" \
        --resource-group "$RESOURCE_GROUP" \
        --workspace "$LOG_ANALYTICS_ID" \
        --application-type web \
        --output none
    
    # Get instrumentation key
    INSTRUMENTATION_KEY=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query instrumentationKey --output tsv)
    
    if [[ -z "$INSTRUMENTATION_KEY" ]]; then
        error "Failed to get Application Insights instrumentation key"
        exit 1
    fi
    
    success "Application Insights created with key: ${INSTRUMENTATION_KEY:0:8}..."
}

# Create Azure Web PubSub
create_webpubsub() {
    info "Creating Azure Web PubSub service..."
    
    az webpubsub create \
        --name "$WEBPUBSUB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Free_F1 \
        --unit-count 1 \
        --output none
    
    # Wait for service to be ready
    info "Waiting for Web PubSub service to be ready..."
    local max_attempts=30
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local state
        state=$(az webpubsub show \
            --name "$WEBPUBSUB_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query provisioningState --output tsv)
        
        if [[ "$state" == "Succeeded" ]]; then
            break
        fi
        
        info "Attempt $attempt/$max_attempts: Web PubSub state is $state"
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        error "Web PubSub service failed to become ready"
        exit 1
    fi
    
    # Get connection string
    WEBPUBSUB_CONNECTION=$(az webpubsub key show \
        --name "$WEBPUBSUB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryConnectionString --output tsv)
    
    if [[ -z "$WEBPUBSUB_CONNECTION" ]]; then
        error "Failed to get Web PubSub connection string"
        exit 1
    fi
    
    success "Web PubSub service created: $WEBPUBSUB_NAME"
}

# Create storage account
create_storage_account() {
    info "Creating storage account..."
    
    az storage account create \
        --name "$STORAGE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --https-only true \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --output none
    
    # Wait for storage account to be ready
    info "Waiting for storage account to be ready..."
    local max_attempts=15
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local state
        state=$(az storage account show \
            --name "$STORAGE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query provisioningState --output tsv 2>/dev/null || echo "NotFound")
        
        if [[ "$state" == "Succeeded" ]]; then
            break
        fi
        
        info "Attempt $attempt/$max_attempts: Storage account state is $state"
        sleep 5
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        error "Storage account failed to become ready"
        exit 1
    fi
    
    success "Storage account created: $STORAGE_NAME"
}

# Create Function App
create_function_app() {
    info "Creating Function App..."
    
    az functionapp create \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_NAME" \
        --consumption-plan-location "$LOCATION" \
        --runtime node \
        --runtime-version 18 \
        --functions-version 4 \
        --output none
    
    # Wait for Function App to be ready
    info "Waiting for Function App to be ready..."
    local max_attempts=30
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local state
        state=$(az functionapp show \
            --name "$FUNCTION_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query state --output tsv 2>/dev/null || echo "NotReady")
        
        if [[ "$state" == "Running" ]]; then
            break
        fi
        
        info "Attempt $attempt/$max_attempts: Function App state is $state"
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        error "Function App failed to become ready"
        exit 1
    fi
    
    # Configure application settings
    info "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
            "WEBPUBSUB_CONNECTION=$WEBPUBSUB_CONNECTION" \
            "APPINSIGHTS_INSTRUMENTATIONKEY=$INSTRUMENTATION_KEY" \
            "AzureWebJobsFeatureFlags=EnableWorkerIndexing" \
        --output none
    
    # Enable Application Insights integration
    az monitor app-insights component connect-webapp \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --web-app "$FUNCTION_APP_NAME" \
        --output none
    
    success "Function App created and configured: $FUNCTION_APP_NAME"
}

# Configure Web PubSub hub
configure_webpubsub_hub() {
    info "Configuring Web PubSub hub..."
    
    # Get Function App hostname
    local function_hostname
    function_hostname=$(az functionapp show \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query defaultHostName --output tsv)
    
    if [[ -z "$function_hostname" ]]; then
        error "Failed to get Function App hostname"
        exit 1
    fi
    
    # Create hub with event handlers
    az webpubsub hub create \
        --name dashboard \
        --resource-group "$RESOURCE_GROUP" \
        --webpubsub-name "$WEBPUBSUB_NAME" \
        --event-handler url-template="https://${function_hostname}/api/eventhandler" \
        --event-handler user-event-pattern="*" \
        --event-handler system-event="connect,connected,disconnected" \
        --output none
    
    success "Web PubSub hub configured"
}

# Create Static Web App
create_static_web_app() {
    info "Creating Static Web App..."
    
    az staticwebapp create \
        --name "$STATIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Free \
        --output none
    
    # Get Static Web App URL
    local static_url
    static_url=$(az staticwebapp show \
        --name "$STATIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query defaultHostname --output tsv)
    
    if [[ -z "$static_url" ]]; then
        error "Failed to get Static Web App URL"
        exit 1
    fi
    
    success "Static Web App created: https://$static_url"
}

# Configure monitoring and alerts
configure_monitoring() {
    info "Configuring monitoring and alerts..."
    
    # Get subscription ID for resource scopes
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    
    # Create custom metric alert for high WebSocket connections
    az monitor metrics alert create \
        --name "high-websocket-connections" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "/subscriptions/$subscription_id/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.SignalRService/webPubSub/$WEBPUBSUB_NAME" \
        --condition "total ConnectionCount > 1000" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --severity 2 \
        --description "Alert when WebSocket connections exceed 1000" \
        --output none 2>/dev/null || warning "Failed to create metric alert (may require additional permissions)"
    
    # Configure diagnostic settings
    az monitor diagnostic-settings create \
        --name "dashboard-diagnostics" \
        --resource "/subscriptions/$subscription_id/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.SignalRService/webPubSub/$WEBPUBSUB_NAME" \
        --workspace "$LOG_ANALYTICS_ID" \
        --logs '[{"category": "AllLogs", "enabled": true}]' \
        --metrics '[{"category": "AllMetrics", "enabled": true}]' \
        --output none 2>/dev/null || warning "Failed to configure diagnostic settings"
    
    success "Monitoring configuration completed"
}

# Save deployment information
save_deployment_info() {
    info "Saving deployment information..."
    
    local deployment_info_file="${SCRIPT_DIR}/deployment_info.json"
    
    cat > "$deployment_info_file" << EOF
{
  "deployment_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "resource_group": "$RESOURCE_GROUP",
  "location": "$LOCATION",
  "random_suffix": "$RANDOM_SUFFIX",
  "resources": {
    "webpubsub_name": "$WEBPUBSUB_NAME",
    "static_app_name": "$STATIC_APP_NAME",
    "function_app_name": "$FUNCTION_APP_NAME",
    "storage_name": "$STORAGE_NAME",
    "app_insights_name": "$APP_INSIGHTS_NAME",
    "log_analytics_name": "$LOG_ANALYTICS_NAME"
  },
  "endpoints": {
    "static_web_app_url": "$(az staticwebapp show --name "$STATIC_APP_NAME" --resource-group "$RESOURCE_GROUP" --query defaultHostname --output tsv)",
    "function_app_url": "$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --query defaultHostName --output tsv)"
  }
}
EOF
    
    success "Deployment information saved to: $deployment_info_file"
}

# Main deployment function
main() {
    info "Starting Azure Real-Time Collaborative Dashboard deployment..."
    
    # Initialize logging
    > "$LOG_FILE"
    > "$ERROR_LOG"
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    validate_environment
    create_resource_group
    create_log_analytics
    create_application_insights
    create_webpubsub
    create_storage_account
    create_function_app
    configure_webpubsub_hub
    create_static_web_app
    configure_monitoring
    save_deployment_info
    
    # Display final information
    echo ""
    success "🎉 Deployment completed successfully!"
    echo ""
    info "Dashboard Resources:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Static Web App URL: https://$(az staticwebapp show --name "$STATIC_APP_NAME" --resource-group "$RESOURCE_GROUP" --query defaultHostname --output tsv)"
    info "  Function App URL: https://$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" --query defaultHostName --output tsv)"
    echo ""
    info "Next Steps:"
    info "  1. Deploy your frontend code to the Static Web App"
    info "  2. Deploy your Function App code"
    info "  3. Configure Web PubSub client connections"
    info "  4. Test real-time collaboration features"
    echo ""
    info "Cleanup: Run './destroy.sh' to remove all resources"
    echo ""
    info "Logs saved to: $LOG_FILE"
    if [[ -s "$ERROR_LOG" ]]; then
        warning "Some warnings occurred. Check: $ERROR_LOG"
    fi
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi