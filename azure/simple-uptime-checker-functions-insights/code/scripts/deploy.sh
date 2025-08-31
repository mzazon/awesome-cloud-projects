#!/bin/bash

# Simple Website Uptime Checker with Functions and Application Insights - Deployment Script
# This script deploys all resources needed for the uptime monitoring solution

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Check if zip utility is available
    if ! command -v zip &> /dev/null; then
        log_error "zip utility is not available. Please install it"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_warning "openssl not found, using alternative random generation"
        RANDOM_SUFFIX=$(date +%s | tail -c 4)
    else
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    log_info "Setting environment variables..."
    
    # Export variables for Azure resources
    export RESOURCE_GROUP="rg-uptime-checker-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export FUNCTION_APP_NAME="func-uptime-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stg${RANDOM_SUFFIX}"
    export APP_INSIGHTS_NAME="ai-uptime-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Function App: ${FUNCTION_APP_NAME}"
    log_info "Storage Account: ${STORAGE_ACCOUNT}"
    log_info "Application Insights: ${APP_INSIGHTS_NAME}"
    log_info "Subscription ID: ${SUBSCRIPTION_ID}"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists, skipping creation"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=uptime-monitoring environment=demo
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account..."
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account ${STORAGE_ACCOUNT} already exists, skipping creation"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2
        
        log_success "Storage account created: ${STORAGE_ACCOUNT}"
    fi
}

# Function to create Application Insights
create_application_insights() {
    log_info "Creating Application Insights instance..."
    
    if az monitor app-insights component show --app "${APP_INSIGHTS_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Application Insights ${APP_INSIGHTS_NAME} already exists, skipping creation"
    else
        az monitor app-insights component create \
            --app "${APP_INSIGHTS_NAME}" \
            --location "${LOCATION}" \
            --resource-group "${RESOURCE_GROUP}" \
            --application-type web \
            --kind web
        
        log_success "Application Insights created: ${APP_INSIGHTS_NAME}"
    fi
    
    # Get Application Insights connection string
    export AI_CONNECTION_STRING=$(az monitor app-insights component show \
        --app "${APP_INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString --output tsv)
    
    log_info "Application Insights connection string retrieved"
}

# Function to create Function App
create_function_app() {
    log_info "Creating Function App..."
    
    if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Function App ${FUNCTION_APP_NAME} already exists, skipping creation"
    else
        az functionapp create \
            --name "${FUNCTION_APP_NAME}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime node \
            --runtime-version 18 \
            --functions-version 4 \
            --app-insights "${APP_INSIGHTS_NAME}"
        
        log_success "Function App created: ${FUNCTION_APP_NAME}"
    fi
    
    # Configure Application Insights connection
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "APPLICATIONINSIGHTS_CONNECTION_STRING=${AI_CONNECTION_STRING}"
    
    log_success "Function App connected to Application Insights"
}

# Function to create and deploy function code
deploy_function_code() {
    log_info "Creating and deploying function code..."
    
    # Create temporary directory for function code
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}"
    
    # Create function project structure
    mkdir -p uptime-function/UptimeChecker
    cd uptime-function
    
    # Create host.json
    cat > host.json << 'EOF'
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[3.*, 4.0.0)"
  },
  "functionTimeout": "00:05:00"
}
EOF
    
    # Create function.json
    cat > UptimeChecker/function.json << 'EOF'
{
  "bindings": [
    {
      "name": "timer",
      "type": "timerTrigger",
      "direction": "in",
      "schedule": "0 */5 * * * *"
    }
  ]
}
EOF
    
    # Create function code
    cat > UptimeChecker/index.js << 'EOF'
const https = require('https');
const http = require('http');
const { URL } = require('url');

// Websites to monitor - add your URLs here
const WEBSITES = [
    'https://www.microsoft.com',
    'https://azure.microsoft.com',
    'https://github.com'
];

module.exports = async function (context, timer) {
    context.log('Uptime checker function started');
    
    const results = [];
    
    for (const website of WEBSITES) {
        try {
            const result = await checkWebsite(website, context);
            results.push(result);
            
            // Log to Application Insights
            context.log(`✅ ${website}: ${result.status} (${result.responseTime}ms)`);
            
        } catch (error) {
            const failureResult = {
                url: website,
                status: 'ERROR',
                responseTime: 0,
                statusCode: 0,
                error: error.message,
                timestamp: new Date().toISOString()
            };
            
            results.push(failureResult);
            context.log(`❌ ${website}: ${error.message}`);
        }
    }
    
    // Send summary to Application Insights
    const summary = {
        totalChecks: results.length,
        successfulChecks: results.filter(r => r.status === 'UP').length,
        failedChecks: results.filter(r => r.status !== 'UP').length,
        averageResponseTime: results
            .filter(r => r.responseTime > 0)
            .reduce((sum, r) => sum + r.responseTime, 0) / 
            Math.max(1, results.filter(r => r.responseTime > 0).length)
    };
    
    context.log('Uptime check summary:', JSON.stringify(summary));
};

async function checkWebsite(url, context) {
    return new Promise((resolve, reject) => {
        const startTime = Date.now();
        const urlObj = new URL(url);
        const client = urlObj.protocol === 'https:' ? https : http;
        
        const request = client.get(url, { timeout: 10000 }, (response) => {
            const responseTime = Date.now() - startTime;
            const status = response.statusCode >= 200 && response.statusCode < 300 ? 'UP' : 'DOWN';
            
            resolve({
                url: url,
                status: status,
                responseTime: responseTime,
                statusCode: response.statusCode,
                timestamp: new Date().toISOString()
            });
        });
        
        request.on('timeout', () => {
            request.destroy();
            reject(new Error('Request timeout'));
        });
        
        request.on('error', (error) => {
            reject(error);
        });
    });
}
EOF
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "uptime-checker",
  "version": "1.0.0",
  "description": "Simple website uptime checker",
  "main": "index.js",
  "dependencies": {}
}
EOF
    
    # Create deployment package
    zip -r uptime-function.zip . -x "*.git*" "*.DS_Store*"
    
    # Deploy function to Azure
    az functionapp deployment source config-zip \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FUNCTION_APP_NAME}" \
        --src uptime-function.zip
    
    # Wait for deployment to complete
    sleep 30
    
    # Verify function deployment
    FUNCTION_EXISTS=$(az functionapp function show \
        --function-name UptimeChecker \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "name" --output tsv 2>/dev/null || echo "")
    
    if [ "${FUNCTION_EXISTS}" = "UptimeChecker" ]; then
        log_success "Function deployed successfully: UptimeChecker"
    else
        log_error "Function deployment verification failed"
        cd /
        rm -rf "${TEMP_DIR}"
        exit 1
    fi
    
    # Cleanup temporary directory
    cd /
    rm -rf "${TEMP_DIR}"
}

# Function to configure alerts
configure_alerts() {
    log_info "Configuring Application Insights alerts..."
    
    # Create action group for notifications
    if az monitor action-group show --name "uptime-alerts" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Action group 'uptime-alerts' already exists, skipping creation"
    else
        az monitor action-group create \
            --name "uptime-alerts" \
            --resource-group "${RESOURCE_GROUP}" \
            --short-name "uptime"
        
        log_success "Action group created: uptime-alerts"
    fi
    
    # Create alert rule for failed uptime checks
    if az monitor scheduled-query show --name "Website-Down-Alert" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Alert rule 'Website-Down-Alert' already exists, skipping creation"
    else
        az monitor scheduled-query create \
            --name "Website-Down-Alert" \
            --resource-group "${RESOURCE_GROUP}" \
            --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Insights/components/${APP_INSIGHTS_NAME}" \
            --condition "count 'traces | where message contains \"❌\"' > 0" \
            --condition-query "traces | where timestamp > ago(10m) | where message contains \"❌\" | summarize count()" \
            --description "Alert when websites are detected as down" \
            --evaluation-frequency 5m \
            --window-size 10m \
            --severity 2
        
        log_success "Alert rule created: Website-Down-Alert"
    fi
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "=== Deployment Summary ==="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Function App: ${FUNCTION_APP_NAME}"
    echo "Application Insights: ${APP_INSIGHTS_NAME}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "Location: ${LOCATION}"
    echo ""
    echo "=== Next Steps ==="
    echo "1. The uptime checker function will run every 5 minutes automatically"
    echo "2. View logs in Application Insights: https://portal.azure.com/#resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Insights/components/${APP_INSIGHTS_NAME}"
    echo "3. Function App URL: https://${FUNCTION_APP_NAME}.azurewebsites.net"
    echo "4. To customize monitored websites, edit the WEBSITES array in the function code"
    echo ""
    echo "=== Cleanup ==="
    echo "To remove all resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log_info "Starting deployment of Simple Website Uptime Checker..."
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_storage_account
    create_application_insights
    create_function_app
    deploy_function_code
    configure_alerts
    display_summary
    
    log_success "Deployment script completed successfully!"
}

# Run main function
main "$@"