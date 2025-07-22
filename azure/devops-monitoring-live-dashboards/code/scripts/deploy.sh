#!/bin/bash

# Azure DevOps Monitoring Dashboard - Deployment Script
# This script deploys the complete real-time monitoring solution including:
# - Azure SignalR Service for real-time communication
# - Azure Functions for event processing
# - Azure App Service for dashboard hosting
# - Azure Monitor alerts for infrastructure monitoring

set -e  # Exit on any error

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

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        log "$description"
        eval "$cmd"
        return $?
    fi
}

log "Starting Azure DevOps Monitoring Dashboard deployment..."

# Prerequisites check
log "Checking prerequisites..."

# Check Azure CLI installation
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check Azure CLI login status
if ! az account show &> /dev/null; then
    error "Not logged into Azure. Please run 'az login' first."
    exit 1
fi

# Check Node.js installation
if ! command -v node &> /dev/null; then
    error "Node.js is not installed. Please install Node.js 16+ first."
    exit 1
fi

# Check npm installation
if ! command -v npm &> /dev/null; then
    error "npm is not installed. Please install npm first."
    exit 1
fi

# Check zip command availability
if ! command -v zip &> /dev/null; then
    error "zip command is not available. Please install zip utility."
    exit 1
fi

success "Prerequisites check completed"

# Set default values if not provided
RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-monitoring-dashboard"}
LOCATION=${LOCATION:-"eastus"}

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
if [[ -z "$SUBSCRIPTION_ID" ]]; then
    error "Failed to get Azure subscription ID"
    exit 1
fi

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")

# Set resource names with unique suffix
SIGNALR_NAME="signalr-monitor-${RANDOM_SUFFIX}"
FUNCTION_APP_NAME="func-monitor-${RANDOM_SUFFIX}"
STORAGE_ACCOUNT_NAME="stmonitor${RANDOM_SUFFIX}"
APP_SERVICE_PLAN_NAME="asp-monitor-${RANDOM_SUFFIX}"
WEB_APP_NAME="webapp-monitor-${RANDOM_SUFFIX}"
LOG_ANALYTICS_NAME="log-monitor-${RANDOM_SUFFIX}"

log "Deployment configuration:"
log "  Resource Group: $RESOURCE_GROUP"
log "  Location: $LOCATION"
log "  Subscription ID: $SUBSCRIPTION_ID"
log "  Random Suffix: $RANDOM_SUFFIX"

# Create resource group
log "Creating resource group..."
execute_command "az group create --name ${RESOURCE_GROUP} --location ${LOCATION} --tags purpose=monitoring environment=demo" \
    "Creating resource group ${RESOURCE_GROUP}"

if [[ "$DRY_RUN" == "false" ]]; then
    success "Resource group created: ${RESOURCE_GROUP}"
fi

# Create Log Analytics workspace
log "Creating Log Analytics workspace..."
execute_command "az monitor log-analytics workspace create --resource-group ${RESOURCE_GROUP} --workspace-name ${LOG_ANALYTICS_NAME} --location ${LOCATION}" \
    "Creating Log Analytics workspace ${LOG_ANALYTICS_NAME}"

if [[ "$DRY_RUN" == "false" ]]; then
    success "Log Analytics workspace created: ${LOG_ANALYTICS_NAME}"
fi

# Create SignalR Service
log "Creating Azure SignalR Service..."
execute_command "az signalr create --name ${SIGNALR_NAME} --resource-group ${RESOURCE_GROUP} --location ${LOCATION} --sku Standard_S1 --service-mode Default" \
    "Creating SignalR Service ${SIGNALR_NAME}"

if [[ "$DRY_RUN" == "false" ]]; then
    # Get SignalR connection string
    SIGNALR_CONNECTION_STRING=$(az signalr key list --name ${SIGNALR_NAME} --resource-group ${RESOURCE_GROUP} --query primaryConnectionString --output tsv)
    if [[ -z "$SIGNALR_CONNECTION_STRING" ]]; then
        error "Failed to get SignalR connection string"
        exit 1
    fi
    success "SignalR Service created: ${SIGNALR_NAME}"
fi

# Create Storage Account
log "Creating Storage Account for Azure Functions..."
execute_command "az storage account create --name ${STORAGE_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} --location ${LOCATION} --sku Standard_LRS --kind StorageV2" \
    "Creating Storage Account ${STORAGE_ACCOUNT_NAME}"

if [[ "$DRY_RUN" == "false" ]]; then
    # Get storage connection string
    STORAGE_CONNECTION_STRING=$(az storage account show-connection-string --name ${STORAGE_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} --query connectionString --output tsv)
    if [[ -z "$STORAGE_CONNECTION_STRING" ]]; then
        error "Failed to get Storage Account connection string"
        exit 1
    fi
    success "Storage Account created: ${STORAGE_ACCOUNT_NAME}"
fi

# Create Function App
log "Creating Azure Function App..."
execute_command "az functionapp create --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP} --storage-account ${STORAGE_ACCOUNT_NAME} --consumption-plan-location ${LOCATION} --runtime node --runtime-version 18 --functions-version 4" \
    "Creating Function App ${FUNCTION_APP_NAME}"

if [[ "$DRY_RUN" == "false" ]]; then
    # Configure SignalR connection in Function App
    log "Configuring SignalR connection in Function App..."
    az functionapp config appsettings set --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP} --settings "AzureSignalRConnectionString=${SIGNALR_CONNECTION_STRING}"
    success "Function App created and configured: ${FUNCTION_APP_NAME}"
fi

# Create and deploy Function code
if [[ "$DRY_RUN" == "false" ]]; then
    log "Preparing Function code..."
    
    # Create temporary directory for function code
    TEMP_FUNCTIONS_DIR=$(mktemp -d)
    cd "$TEMP_FUNCTIONS_DIR"
    
    # Initialize npm project
    npm init -y > /dev/null 2>&1
    npm install @azure/functions > /dev/null 2>&1
    
    # Create DevOps webhook function
    mkdir -p DevOpsWebhook
    cat > DevOpsWebhook/function.json << 'EOF'
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
      "name": "res"
    },
    {
      "type": "signalR",
      "direction": "out",
      "name": "signalRMessages",
      "hubName": "monitoring"
    }
  ]
}
EOF
    
    cat > DevOpsWebhook/index.js << 'EOF'
module.exports = async function (context, req) {
  const event = req.body;
  
  if (event && event.eventType) {
    const monitoringData = {
      timestamp: new Date().toISOString(),
      eventType: event.eventType,
      resource: event.resource,
      projectName: event.resourceContainers?.project?.id || 'unknown',
      status: event.resource?.result || event.resource?.status || 'unknown',
      message: event.message?.text || 'DevOps event received'
    };
    
    context.bindings.signalRMessages = {
      target: 'monitoringUpdate',
      arguments: [monitoringData]
    };
    
    context.log('Processed DevOps event:', monitoringData);
  }
  
  context.res = {
    status: 200,
    body: { message: 'Event processed successfully' }
  };
};
EOF
    
    # Create negotiate function
    mkdir -p negotiate
    cat > negotiate/function.json << 'EOF'
{
  "bindings": [
    {
      "authLevel": "anonymous",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["post"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    },
    {
      "type": "signalRConnectionInfo",
      "direction": "in",
      "name": "connectionInfo",
      "hubName": "monitoring"
    }
  ]
}
EOF
    
    cat > negotiate/index.js << 'EOF'
module.exports = async function (context, req) {
  context.res = {
    body: context.bindings.connectionInfo
  };
};
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
    "http": {
      "routePrefix": ""
    }
  }
}
EOF
    
    # Deploy functions
    log "Deploying Function code..."
    zip -r function-app.zip . > /dev/null 2>&1
    az functionapp deployment source config-zip --src function-app.zip --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP} > /dev/null 2>&1
    
    success "Function code deployed successfully"
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "$TEMP_FUNCTIONS_DIR"
fi

# Create App Service Plan
log "Creating App Service Plan..."
execute_command "az appservice plan create --name ${APP_SERVICE_PLAN_NAME} --resource-group ${RESOURCE_GROUP} --location ${LOCATION} --sku B1 --is-linux" \
    "Creating App Service Plan ${APP_SERVICE_PLAN_NAME}"

if [[ "$DRY_RUN" == "false" ]]; then
    success "App Service Plan created: ${APP_SERVICE_PLAN_NAME}"
fi

# Create Web App
log "Creating Web App for dashboard..."
execute_command "az webapp create --name ${WEB_APP_NAME} --resource-group ${RESOURCE_GROUP} --plan ${APP_SERVICE_PLAN_NAME} --runtime \"NODE|18-lts\"" \
    "Creating Web App ${WEB_APP_NAME}"

if [[ "$DRY_RUN" == "false" ]]; then
    # Configure Web App settings
    log "Configuring Web App settings..."
    az webapp config appsettings set --name ${WEB_APP_NAME} --resource-group ${RESOURCE_GROUP} --settings "FUNCTIONS_URL=https://${FUNCTION_APP_NAME}.azurewebsites.net" > /dev/null 2>&1
    success "Web App created and configured: ${WEB_APP_NAME}"
fi

# Create and deploy dashboard application
if [[ "$DRY_RUN" == "false" ]]; then
    log "Preparing dashboard application..."
    
    # Create temporary directory for dashboard app
    TEMP_DASHBOARD_DIR=$(mktemp -d)
    cd "$TEMP_DASHBOARD_DIR"
    
    # Initialize Node.js project
    npm init -y > /dev/null 2>&1
    npm install express @microsoft/signalr > /dev/null 2>&1
    
    # Create server.js
    cat > server.js << 'EOF'
const express = require('express');
const path = require('path');
const app = express();

app.use(express.static(path.join(__dirname, 'public')));

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Dashboard server running on port ${port}`);
});
EOF
    
    # Create dashboard HTML
    mkdir -p public
    cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>Real-Time Infrastructure Monitoring Dashboard</title>
  <script src="https://unpkg.com/@microsoft/signalr@latest/dist/browser/signalr.js"></script>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
    .dashboard { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
    .panel { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
    .event { padding: 10px; margin: 5px 0; border-left: 4px solid #007acc; background: #f9f9f9; }
    .event.success { border-left-color: #28a745; }
    .event.failed { border-left-color: #dc3545; }
    .event.running { border-left-color: #ffc107; }
    .timestamp { font-size: 0.8em; color: #666; }
    .status { font-weight: bold; text-transform: uppercase; }
    .connection-status { padding: 10px; border-radius: 4px; margin-bottom: 20px; }
    .connected { background-color: #d4edda; color: #155724; }
    .disconnected { background-color: #f8d7da; color: #721c24; }
  </style>
</head>
<body>
  <h1>Real-Time Infrastructure Monitoring Dashboard</h1>
  <div id="connectionStatus" class="connection-status disconnected">
    Connecting to monitoring service...
  </div>
  
  <div class="dashboard">
    <div class="panel">
      <h2>Pipeline Events</h2>
      <div id="pipelineEvents"></div>
    </div>
    
    <div class="panel">
      <h2>System Status</h2>
      <div id="systemStatus">
        <div>Active Connections: <span id="activeConnections">0</span></div>
        <div>Last Update: <span id="lastUpdate">Never</span></div>
      </div>
    </div>
    
    <div class="panel">
      <h2>Recent Activity</h2>
      <div id="recentActivity"></div>
    </div>
    
    <div class="panel">
      <h2>Metrics</h2>
      <div id="metrics">
        <div>Total Events: <span id="totalEvents">0</span></div>
        <div>Success Rate: <span id="successRate">0%</span></div>
      </div>
    </div>
  </div>

  <script>
    let totalEvents = 0;
    let successfulEvents = 0;
    
    const connection = new signalR.HubConnectionBuilder()
      .withUrl("/negotiate")
      .build();

    connection.start().then(function () {
      console.log("SignalR Connected");
      updateConnectionStatus(true);
    }).catch(function (err) {
      console.error("SignalR Connection Error: ", err);
      updateConnectionStatus(false);
    });

    connection.on("monitoringUpdate", function (data) {
      addEvent(data);
      updateMetrics(data);
      updateLastUpdate();
    });

    function updateConnectionStatus(connected) {
      const statusDiv = document.getElementById('connectionStatus');
      if (connected) {
        statusDiv.className = 'connection-status connected';
        statusDiv.textContent = 'Connected to monitoring service';
      } else {
        statusDiv.className = 'connection-status disconnected';
        statusDiv.textContent = 'Disconnected from monitoring service';
      }
    }

    function addEvent(data) {
      const eventsDiv = document.getElementById('pipelineEvents');
      const activityDiv = document.getElementById('recentActivity');
      
      const eventDiv = document.createElement('div');
      eventDiv.className = 'event ' + getEventClass(data.status);
      eventDiv.innerHTML = `
        <div class="status">${data.status}</div>
        <div>${data.eventType} - ${data.projectName}</div>
        <div class="timestamp">${new Date(data.timestamp).toLocaleString()}</div>
      `;
      
      eventsDiv.insertBefore(eventDiv, eventsDiv.firstChild);
      activityDiv.insertBefore(eventDiv.cloneNode(true), activityDiv.firstChild);
      
      // Keep only last 10 events
      while (eventsDiv.children.length > 10) {
        eventsDiv.removeChild(eventsDiv.lastChild);
      }
      while (activityDiv.children.length > 10) {
        activityDiv.removeChild(activityDiv.lastChild);
      }
    }

    function getEventClass(status) {
      if (status && status.toLowerCase().includes('success')) return 'success';
      if (status && status.toLowerCase().includes('fail')) return 'failed';
      if (status && status.toLowerCase().includes('running')) return 'running';
      return '';
    }

    function updateMetrics(data) {
      totalEvents++;
      if (data.status && data.status.toLowerCase().includes('success')) {
        successfulEvents++;
      }
      
      document.getElementById('totalEvents').textContent = totalEvents;
      document.getElementById('successRate').textContent = 
        totalEvents > 0 ? Math.round((successfulEvents / totalEvents) * 100) + '%' : '0%';
    }

    function updateLastUpdate() {
      document.getElementById('lastUpdate').textContent = new Date().toLocaleString();
    }
  </script>
</body>
</html>
EOF
    
    # Create package.json for deployment
    cat > package.json << 'EOF'
{
  "name": "monitoring-dashboard",
  "version": "1.0.0",
  "description": "Real-time infrastructure monitoring dashboard",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "@microsoft/signalr": "^7.0.0"
  }
}
EOF
    
    # Deploy dashboard to Azure Web App
    log "Deploying dashboard application..."
    zip -r dashboard-app.zip . > /dev/null 2>&1
    az webapp deployment source config-zip --src dashboard-app.zip --name ${WEB_APP_NAME} --resource-group ${RESOURCE_GROUP} > /dev/null 2>&1
    
    success "Dashboard application deployed successfully"
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "$TEMP_DASHBOARD_DIR"
fi

# Configure Azure Monitor alerts
if [[ "$DRY_RUN" == "false" ]]; then
    log "Configuring Azure Monitor alerts..."
    
    # Get Function App webhook URL and key
    WEBHOOK_URL=$(az functionapp function show --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP} --function-name DevOpsWebhook --query invokeUrlTemplate --output tsv)
    FUNCTION_KEY=$(az functionapp keys list --name ${FUNCTION_APP_NAME} --resource-group ${RESOURCE_GROUP} --query functionKeys.default --output tsv)
    COMPLETE_WEBHOOK_URL="${WEBHOOK_URL}?code=${FUNCTION_KEY}"
    
    # Create action group for webhook
    az monitor action-group create \
        --name "ag-monitoring-webhook" \
        --resource-group ${RESOURCE_GROUP} \
        --action webhook webhook1 ${COMPLETE_WEBHOOK_URL} > /dev/null 2>&1
    
    # Create alert rules (with error handling)
    az monitor metrics alert create \
        --name "FunctionAppErrors" \
        --resource-group ${RESOURCE_GROUP} \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Web/sites/${FUNCTION_APP_NAME}" \
        --condition "count Microsoft.Web/sites FunctionExecutionCount > 0" \
        --condition "count Microsoft.Web/sites FunctionErrors > 5" \
        --action "ag-monitoring-webhook" \
        --description "Alert when Function App has errors" > /dev/null 2>&1 || warning "Failed to create Function App error alert"
    
    az monitor metrics alert create \
        --name "SignalRConnectionIssues" \
        --resource-group ${RESOURCE_GROUP} \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.SignalRService/signalR/${SIGNALR_NAME}" \
        --condition "count Microsoft.SignalRService/signalR ConnectionCount < 1" \
        --action "ag-monitoring-webhook" \
        --description "Alert when SignalR has no active connections" > /dev/null 2>&1 || warning "Failed to create SignalR connection alert"
    
    success "Azure Monitor alerts configured"
fi

# Display deployment summary
log "Deployment completed successfully!"
echo ""
success "=== DEPLOYMENT SUMMARY ==="
success "Resource Group: ${RESOURCE_GROUP}"
success "SignalR Service: ${SIGNALR_NAME}"
success "Function App: ${FUNCTION_APP_NAME}"
success "Web App: ${WEB_APP_NAME}"
success "Storage Account: ${STORAGE_ACCOUNT_NAME}"
success "Log Analytics: ${LOG_ANALYTICS_NAME}"
echo ""

if [[ "$DRY_RUN" == "false" ]]; then
    # Get Web App URL
    WEB_APP_URL=$(az webapp show --name ${WEB_APP_NAME} --resource-group ${RESOURCE_GROUP} --query defaultHostName --output tsv)
    
    success "=== ACCESS INFORMATION ==="
    success "Dashboard URL: https://${WEB_APP_URL}"
    success "Function Webhook URL: ${COMPLETE_WEBHOOK_URL}"
    echo ""
    
    success "=== NEXT STEPS ==="
    success "1. Open the dashboard: https://${WEB_APP_URL}"
    success "2. Configure Azure DevOps Service Hooks:"
    success "   - Go to your Azure DevOps project"
    success "   - Navigate to Project Settings > Service hooks"
    success "   - Create a new service hook with:"
    success "     - Service: Web Hooks"
    success "     - Event: Build completed, Release deployment completed"
    success "     - URL: ${COMPLETE_WEBHOOK_URL}"
    success "     - Resource details: All events"
    echo ""
fi

# Save deployment information
if [[ "$DRY_RUN" == "false" ]]; then
    cat > deployment-info.json << EOF
{
  "resourceGroup": "${RESOURCE_GROUP}",
  "location": "${LOCATION}",
  "subscriptionId": "${SUBSCRIPTION_ID}",
  "signalrName": "${SIGNALR_NAME}",
  "functionAppName": "${FUNCTION_APP_NAME}",
  "webAppName": "${WEB_APP_NAME}",
  "storageAccountName": "${STORAGE_ACCOUNT_NAME}",
  "logAnalyticsName": "${LOG_ANALYTICS_NAME}",
  "dashboardUrl": "https://${WEB_APP_URL}",
  "webhookUrl": "${COMPLETE_WEBHOOK_URL}",
  "deploymentDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    success "Deployment information saved to deployment-info.json"
fi

success "Deployment completed successfully! 🎉"