#!/bin/bash

# =============================================================================
# Azure Resource Rightsizing Deployment Script
# =============================================================================
# This script deploys the complete Azure Resource Rightsizing solution
# including monitoring, automation, and cost management components.
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

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Starting cleanup..."
    # Only cleanup if resource group exists
    if az group exists --name "${RESOURCE_GROUP}" --output tsv 2>/dev/null; then
        warning "Cleaning up partial deployment..."
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait || true
    fi
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# =============================================================================
# Configuration and Prerequisites
# =============================================================================

# Default configuration
DEFAULT_LOCATION="eastus"
DEFAULT_ADMIN_EMAIL="admin@company.com"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --location)
            LOCATION="$2"
            shift 2
            ;;
        --admin-email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --location LOCATION           Azure region (default: eastus)"
            echo "  --admin-email EMAIL           Admin email for notifications (default: admin@company.com)"
            echo "  --resource-group NAME         Resource group name (default: auto-generated)"
            echo "  --dry-run                     Validate parameters without deployment"
            echo "  --help                        Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set defaults for unspecified parameters
LOCATION=${LOCATION:-$DEFAULT_LOCATION}
ADMIN_EMAIL=${ADMIN_EMAIL:-$DEFAULT_ADMIN_EMAIL}
DRY_RUN=${DRY_RUN:-false}

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))

# Set environment variables
export RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-rightsizing-${RANDOM_SUFFIX}"}
export LOCATION
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
export FUNCTION_APP_NAME="func-rightsizing-${RANDOM_SUFFIX}"
export STORAGE_ACCOUNT_NAME="st${RANDOM_SUFFIX}"
export LOG_ANALYTICS_NAME="log-rightsizing-${RANDOM_SUFFIX}"
export APP_INSIGHTS_NAME="ai-rightsizing-${RANDOM_SUFFIX}"
export LOGIC_APP_NAME="logic-rightsizing-${RANDOM_SUFFIX}"

# =============================================================================
# Prerequisites Check
# =============================================================================

log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Check if subscription is set
if [[ -z "${SUBSCRIPTION_ID}" ]]; then
    error "No active Azure subscription found. Please run 'az account set --subscription <subscription-id>'."
    exit 1
fi

# Check if required tools are available
for tool in curl openssl; do
    if ! command -v $tool &> /dev/null; then
        error "$tool is not installed. Please install it first."
        exit 1
    fi
done

# Validate email format
if [[ ! "$ADMIN_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    error "Invalid email format: $ADMIN_EMAIL"
    exit 1
fi

# Check if storage account name is valid (lowercase, 3-24 chars, alphanumeric)
if [[ ! "$STORAGE_ACCOUNT_NAME" =~ ^[a-z0-9]{3,24}$ ]]; then
    error "Invalid storage account name: $STORAGE_ACCOUNT_NAME"
    exit 1
fi

success "Prerequisites check completed"

# =============================================================================
# Configuration Summary
# =============================================================================

log "Deployment Configuration:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Location: $LOCATION"
echo "  Subscription: $SUBSCRIPTION_ID"
echo "  Admin Email: $ADMIN_EMAIL"
echo "  Function App: $FUNCTION_APP_NAME"
echo "  Storage Account: $STORAGE_ACCOUNT_NAME"
echo "  Log Analytics: $LOG_ANALYTICS_NAME"
echo "  Application Insights: $APP_INSIGHTS_NAME"
echo "  Logic App: $LOGIC_APP_NAME"

if [[ "$DRY_RUN" == "true" ]]; then
    success "Dry run completed successfully. Configuration is valid."
    exit 0
fi

# Confirmation prompt
echo ""
read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Deployment cancelled by user."
    exit 0
fi

# =============================================================================
# Deployment Start
# =============================================================================

log "Starting Azure Resource Rightsizing deployment..."

# Create resource group
log "Creating resource group..."
az group create \
    --name "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --tags purpose=recipe environment=demo project=rightsizing \
    --output table

success "Resource group created: ${RESOURCE_GROUP}"

# Create storage account for Function App
log "Creating storage account..."
az storage account create \
    --name "${STORAGE_ACCOUNT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --output table

success "Storage account created: ${STORAGE_ACCOUNT_NAME}"

# =============================================================================
# Monitoring Infrastructure
# =============================================================================

log "Creating monitoring infrastructure..."

# Create Log Analytics workspace
log "Creating Log Analytics workspace..."
az monitor log-analytics workspace create \
    --resource-group "${RESOURCE_GROUP}" \
    --workspace-name "${LOG_ANALYTICS_NAME}" \
    --location "${LOCATION}" \
    --sku PerGB2018 \
    --output table

# Get workspace ID for Application Insights
WORKSPACE_ID=$(az monitor log-analytics workspace show \
    --resource-group "${RESOURCE_GROUP}" \
    --workspace-name "${LOG_ANALYTICS_NAME}" \
    --query id --output tsv)

success "Log Analytics workspace created: ${LOG_ANALYTICS_NAME}"

# Create Application Insights
log "Creating Application Insights..."
az monitor app-insights component create \
    --resource-group "${RESOURCE_GROUP}" \
    --app "${APP_INSIGHTS_NAME}" \
    --location "${LOCATION}" \
    --workspace "${WORKSPACE_ID}" \
    --output table

success "Application Insights created: ${APP_INSIGHTS_NAME}"

# =============================================================================
# Function App Creation
# =============================================================================

log "Creating Function App..."
az functionapp create \
    --resource-group "${RESOURCE_GROUP}" \
    --consumption-plan-location "${LOCATION}" \
    --runtime node \
    --functions-version 4 \
    --name "${FUNCTION_APP_NAME}" \
    --storage-account "${STORAGE_ACCOUNT_NAME}" \
    --app-insights "${APP_INSIGHTS_NAME}" \
    --output table

success "Function App created: ${FUNCTION_APP_NAME}"

# Configure Function App settings
log "Configuring Function App settings..."
az functionapp config appsettings set \
    --name "${FUNCTION_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --settings "SUBSCRIPTION_ID=${SUBSCRIPTION_ID}" \
              "RESOURCE_GROUP=${RESOURCE_GROUP}" \
              "LOG_ANALYTICS_WORKSPACE=${LOG_ANALYTICS_NAME}" \
    --output table

success "Function App settings configured"

# =============================================================================
# Function Code Deployment
# =============================================================================

log "Deploying Function code..."

# Create temporary directory for function code
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Initialize Azure Functions project
func init --javascript --name rightsizing-function

# Create rightsizing function
func new --name RightsizingAnalyzer --template "Timer trigger" --language javascript

# Create package.json for dependencies
cat > package.json << 'EOF'
{
  "name": "rightsizing-function",
  "version": "1.0.0",
  "description": "Azure Resource Rightsizing Function",
  "main": "index.js",
  "dependencies": {
    "@azure/monitor-query": "^1.0.0",
    "@azure/arm-compute": "^20.0.0",
    "@azure/arm-sql": "^9.0.0",
    "@azure/identity": "^3.0.0",
    "axios": "^1.0.0"
  },
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "keywords": ["azure", "rightsizing", "cost-optimization"],
  "author": "Azure Recipe",
  "license": "MIT"
}
EOF

# Create function code
cat > RightsizingAnalyzer/index.js << 'EOF'
const { DefaultAzureCredential } = require('@azure/identity');
const { MonitorQueryClient } = require('@azure/monitor-query');
const { ComputeManagementClient } = require('@azure/arm-compute');

module.exports = async function (context, myTimer) {
    const timeStamp = new Date().toISOString();
    context.log('Rightsizing function triggered at:', timeStamp);
    
    const credential = new DefaultAzureCredential();
    const subscriptionId = process.env.SUBSCRIPTION_ID;
    const resourceGroup = process.env.RESOURCE_GROUP;
    
    try {
        // Initialize clients
        const monitorClient = new MonitorQueryClient(credential);
        const computeClient = new ComputeManagementClient(credential, subscriptionId);
        
        // Query CPU utilization for VMs
        const kustoQuery = `
            Perf
            | where CounterName == "% Processor Time" 
            | where TimeGenerated > ago(7d)
            | summarize AvgCPU = avg(CounterValue) by Computer
            | where AvgCPU < 20 or AvgCPU > 80
        `;
        
        const workspaceId = process.env.LOG_ANALYTICS_WORKSPACE;
        
        // For demo purposes, create sample recommendations
        const recommendations = [
            {
                resource: 'vm-sample-001',
                action: 'downsize',
                reason: 'Low CPU utilization: 15%',
                priority: 'medium',
                timestamp: timeStamp
            },
            {
                resource: 'vm-sample-002',
                action: 'upsize',
                reason: 'High CPU utilization: 85%',
                priority: 'high',
                timestamp: timeStamp
            }
        ];
        
        // Log recommendations
        context.log('Rightsizing recommendations generated:', recommendations);
        
        // Store recommendations for further processing
        context.bindings.recommendations = recommendations;
        
        context.log('Rightsizing analysis completed successfully');
        
    } catch (error) {
        context.log.error('Error in rightsizing analysis:', error);
        throw error;
    }
};
EOF

# Update function configuration
cat > RightsizingAnalyzer/function.json << 'EOF'
{
  "bindings": [
    {
      "name": "myTimer",
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 0 */6 * * *"
    }
  ],
  "scriptFile": "index.js"
}
EOF

# Check if func command exists
if command -v func &> /dev/null; then
    # Deploy function to Azure
    func azure functionapp publish "${FUNCTION_APP_NAME}" --javascript
    success "Function code deployed successfully"
else
    warning "Azure Functions Core Tools not found. Function code created but not deployed."
    warning "Please install Azure Functions Core Tools and run: func azure functionapp publish ${FUNCTION_APP_NAME}"
fi

# Cleanup temporary directory
cd - > /dev/null
rm -rf "$TEMP_DIR"

# =============================================================================
# Logic App Creation
# =============================================================================

log "Creating Logic App..."
az logic workflow create \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --name "${LOGIC_APP_NAME}" \
    --definition '{
      "$schema": "https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#",
      "contentVersion": "1.0.0.0",
      "parameters": {
        "functionUrl": {
          "type": "string",
          "defaultValue": ""
        }
      },
      "triggers": {
        "manual": {
          "type": "Request",
          "kind": "Http",
          "inputs": {
            "schema": {
              "type": "object",
              "properties": {
                "action": {"type": "string"},
                "resource": {"type": "string"},
                "reason": {"type": "string"}
              }
            }
          }
        }
      },
      "actions": {
        "ProcessRecommendations": {
          "type": "Http",
          "inputs": {
            "method": "POST",
            "uri": "@parameters(\"functionUrl\")",
            "headers": {
              "Content-Type": "application/json"
            },
            "body": "@triggerBody()"
          }
        },
        "SendNotification": {
          "type": "Http",
          "inputs": {
            "method": "POST",
            "uri": "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK",
            "headers": {
              "Content-Type": "application/json"
            },
            "body": {
              "text": "Rightsizing recommendation: @{triggerBody()[\"action\"]} @{triggerBody()[\"resource\"]} - @{triggerBody()[\"reason\"]}"
            }
          },
          "runAfter": {
            "ProcessRecommendations": ["Succeeded"]
          }
        }
      }
    }' \
    --output table

# Get Logic App callback URL
LOGIC_APP_URL=$(az logic workflow show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${LOGIC_APP_NAME}" \
    --query accessEndpoint --output tsv)

success "Logic App created: ${LOGIC_APP_NAME}"

# =============================================================================
# Cost Management Setup
# =============================================================================

log "Setting up cost management..."

# Create budget for cost monitoring
az consumption budget create \
    --resource-group "${RESOURCE_GROUP}" \
    --budget-name "rightsizing-budget" \
    --amount 100 \
    --time-grain Monthly \
    --time-period start-date="2025-01-01" \
    --category Cost \
    --threshold 80 \
    --contact-emails "${ADMIN_EMAIL}" \
    --output table

success "Cost budget created"

# Create notification action group
az monitor action-group create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "rightsizing-alerts" \
    --short-name "rightsizing" \
    --email-receivers name=admin email="${ADMIN_EMAIL}" \
    --output table

success "Notification action group created"

# Create cost alert rule
az monitor metrics alert create \
    --name "high-cost-alert" \
    --resource-group "${RESOURCE_GROUP}" \
    --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
    --condition "total Microsoft.Consumption/Budget > 80" \
    --description "Alert when resource group costs exceed 80% of budget" \
    --action-group "rightsizing-alerts" \
    --evaluation-frequency 5m \
    --window-size 15m \
    --output table

success "Cost alert rule created"

# =============================================================================
# Test Resources Creation
# =============================================================================

log "Creating test resources..."

# Create test Virtual Machine
az vm create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "vm-test-${RANDOM_SUFFIX}" \
    --image Ubuntu2204 \
    --size Standard_B2s \
    --admin-username azureuser \
    --generate-ssh-keys \
    --no-wait \
    --output table

success "Test VM creation initiated"

# Create test App Service Plan
az appservice plan create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "plan-test-${RANDOM_SUFFIX}" \
    --location "${LOCATION}" \
    --sku S1 \
    --is-linux \
    --output table

success "Test App Service Plan created"

# Create test Web App
az webapp create \
    --resource-group "${RESOURCE_GROUP}" \
    --plan "plan-test-${RANDOM_SUFFIX}" \
    --name "app-test-${RANDOM_SUFFIX}" \
    --runtime "NODE:18-lts" \
    --output table

success "Test Web App created"

# =============================================================================
# Azure Developer CLI Setup
# =============================================================================

log "Setting up Azure Developer CLI integration..."

# Create azd configuration directory
mkdir -p ./azd-rightsizing
cd ./azd-rightsizing

# Create azd configuration file
cat > azure.yaml << EOF
name: rightsizing-automation
metadata:
  template: rightsizing-automation@1.0.0
services:
  rightsizing:
    project: .
    host: functionapp
    language: javascript
hooks:
  postdeploy:
    shell: pwsh
    run: |
      Write-Host "Running rightsizing analysis..."
      \$functionKey = az functionapp keys list --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --query "functionKeys.default" -o tsv
      \$functionUrl = "https://$FUNCTION_APP_NAME.azurewebsites.net/api/RightsizingAnalyzer?code=\$functionKey"
      try {
        Invoke-RestMethod -Uri \$functionUrl -Method Post -TimeoutSec 30
        Write-Host "Rightsizing analysis completed successfully"
      } catch {
        Write-Warning "Failed to trigger rightsizing analysis: \$_"
      }
EOF

# Create environment configuration
mkdir -p .azure/dev
cat > .azure/dev/.env << EOF
AZURE_RESOURCE_GROUP=${RESOURCE_GROUP}
AZURE_LOCATION=${LOCATION}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
LOGIC_APP_NAME=${LOGIC_APP_NAME}
ADMIN_EMAIL=${ADMIN_EMAIL}
EOF

cd - > /dev/null

success "Azure Developer CLI integration configured"

# =============================================================================
# Deployment Validation
# =============================================================================

log "Validating deployment..."

# Check Function App status
FUNCTION_STATUS=$(az functionapp show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${FUNCTION_APP_NAME}" \
    --query state --output tsv)

if [[ "$FUNCTION_STATUS" == "Running" ]]; then
    success "Function App is running"
else
    warning "Function App status: $FUNCTION_STATUS"
fi

# Check Logic App status
LOGIC_STATUS=$(az logic workflow show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${LOGIC_APP_NAME}" \
    --query state --output tsv)

if [[ "$LOGIC_STATUS" == "Enabled" ]]; then
    success "Logic App is enabled"
else
    warning "Logic App status: $LOGIC_STATUS"
fi

# =============================================================================
# Deployment Summary
# =============================================================================

success "Azure Resource Rightsizing deployment completed successfully!"

echo ""
echo "==============================================================================="
echo "DEPLOYMENT SUMMARY"
echo "==============================================================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "Function App: $FUNCTION_APP_NAME"
echo "Logic App: $LOGIC_APP_NAME"
echo "Storage Account: $STORAGE_ACCOUNT_NAME"
echo "Log Analytics: $LOG_ANALYTICS_NAME"
echo "Application Insights: $APP_INSIGHTS_NAME"
echo ""
echo "Next Steps:"
echo "1. Configure monitoring alerts for your specific resources"
echo "2. Customize the rightsizing logic in the Function App"
echo "3. Set up notification endpoints in the Logic App"
echo "4. Review and adjust the cost budget thresholds"
echo "5. Test the automation with your actual workloads"
echo ""
echo "Access your resources:"
echo "- Function App: https://$FUNCTION_APP_NAME.azurewebsites.net"
echo "- Logic App: https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Logic/workflows/$LOGIC_APP_NAME"
echo "- Application Insights: https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/components/$APP_INSIGHTS_NAME"
echo ""
echo "For cleanup, run: ./destroy.sh --resource-group $RESOURCE_GROUP"
echo "==============================================================================="