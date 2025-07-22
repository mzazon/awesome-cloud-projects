#!/bin/bash

# Azure Service Fabric Microservices Monitoring - Deployment Script
# This script deploys the complete monitoring solution for distributed microservices
# using Azure Service Fabric and Application Insights

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

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warn "Running in DRY-RUN mode - no resources will be created"
fi

# Banner
echo -e "${BLUE}"
echo "========================================================"
echo "  Azure Service Fabric Microservices Monitoring"
echo "  Deployment Script"
echo "========================================================"
echo -e "${NC}"

# Prerequisites check
log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first."
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error "Not logged in to Azure. Please run 'az login' first."
fi

# Check Azure CLI version
AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
log "Azure CLI version: $AZ_VERSION"

# Check if openssl is available for random string generation
if ! command -v openssl &> /dev/null; then
    error "openssl is not installed. Required for generating random strings."
fi

# Get subscription info
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
log "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# Set environment variables
export RESOURCE_GROUP="rg-microservices-monitoring-${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
export LOCATION="${LOCATION:-eastus}"
export SUBSCRIPTION_ID

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
export RANDOM_SUFFIX

# Set additional environment variables for resources
export SF_CLUSTER_NAME="sf-cluster-${RANDOM_SUFFIX}"
export APP_INSIGHTS_NAME="ai-monitoring-${RANDOM_SUFFIX}"
export FUNCTION_APP_NAME="fn-eventprocessor-${RANDOM_SUFFIX}"
export STORAGE_ACCOUNT_NAME="st${RANDOM_SUFFIX}"
export EVENT_HUB_NAMESPACE="eh-namespace-${RANDOM_SUFFIX}"
export LOG_ANALYTICS_NAME="la-workspace-${RANDOM_SUFFIX}"

# Display configuration
info "Deployment Configuration:"
info "  Resource Group: $RESOURCE_GROUP"
info "  Location: $LOCATION"
info "  Service Fabric Cluster: $SF_CLUSTER_NAME"
info "  Application Insights: $APP_INSIGHTS_NAME"
info "  Function App: $FUNCTION_APP_NAME"
info "  Storage Account: $STORAGE_ACCOUNT_NAME"
info "  Event Hub Namespace: $EVENT_HUB_NAMESPACE"
info "  Log Analytics Workspace: $LOG_ANALYTICS_NAME"

# Confirmation prompt
if [[ "$DRY_RUN" == "false" ]]; then
    echo
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user."
        exit 0
    fi
fi

# Function to run command with dry-run support
run_command() {
    local cmd="$1"
    local description="$2"
    
    info "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
        return 0
    else
        eval "$cmd"
        return $?
    fi
}

# Step 1: Create Resource Group
log "Step 1: Creating Resource Group..."
run_command "az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION \
    --tags purpose=microservices-monitoring environment=demo" \
    "Creating resource group $RESOURCE_GROUP"

# Step 2: Create Log Analytics Workspace
log "Step 2: Creating Log Analytics Workspace..."
run_command "az monitor log-analytics workspace create \
    --resource-group $RESOURCE_GROUP \
    --workspace-name $LOG_ANALYTICS_NAME \
    --location $LOCATION \
    --sku pergb2018" \
    "Creating Log Analytics workspace"

# Get workspace ID for Application Insights
if [[ "$DRY_RUN" == "false" ]]; then
    info "Getting Log Analytics workspace ID..."
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group $RESOURCE_GROUP \
        --workspace-name $LOG_ANALYTICS_NAME \
        --query id --output tsv)
    export WORKSPACE_ID
    info "Workspace ID: $WORKSPACE_ID"
fi

# Step 3: Create Application Insights
log "Step 3: Creating Application Insights..."
if [[ "$DRY_RUN" == "false" ]]; then
    run_command "az monitor app-insights component create \
        --app $APP_INSIGHTS_NAME \
        --location $LOCATION \
        --resource-group $RESOURCE_GROUP \
        --workspace $WORKSPACE_ID \
        --application-type web \
        --kind web" \
        "Creating Application Insights instance"
else
    info "DRY-RUN: Creating Application Insights instance"
fi

# Step 4: Create Event Hub Namespace
log "Step 4: Creating Event Hub Namespace..."
run_command "az eventhubs namespace create \
    --resource-group $RESOURCE_GROUP \
    --name $EVENT_HUB_NAMESPACE \
    --location $LOCATION \
    --sku Standard \
    --enable-auto-inflate true \
    --maximum-throughput-units 10" \
    "Creating Event Hub namespace"

# Create Event Hub
log "Creating Event Hub..."
run_command "az eventhubs eventhub create \
    --resource-group $RESOURCE_GROUP \
    --namespace-name $EVENT_HUB_NAMESPACE \
    --name service-events \
    --partition-count 4 \
    --message-retention 1" \
    "Creating Event Hub for service events"

# Get Event Hub connection string
if [[ "$DRY_RUN" == "false" ]]; then
    info "Getting Event Hub connection string..."
    EVENT_HUB_CONNECTION=$(az eventhubs namespace authorization-rule keys list \
        --resource-group $RESOURCE_GROUP \
        --namespace-name $EVENT_HUB_NAMESPACE \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString --output tsv)
    export EVENT_HUB_CONNECTION
    info "Event Hub connection string obtained"
fi

# Step 5: Create Service Fabric Managed Cluster
log "Step 5: Creating Service Fabric Managed Cluster..."
warn "This step may take 10-15 minutes to complete..."
run_command "az sf managed-cluster create \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $SF_CLUSTER_NAME \
    --location $LOCATION \
    --admin-username azureuser \
    --admin-password 'ComplexPassword123!' \
    --sku Standard \
    --cluster-code-version 9.1.1436.9590 \
    --client-connection-port 19000 \
    --http-gateway-port 19080" \
    "Creating Service Fabric managed cluster"

# Wait for cluster to be ready
if [[ "$DRY_RUN" == "false" ]]; then
    info "Waiting for Service Fabric cluster to be ready..."
    while true; do
        CLUSTER_STATE=$(az sf managed-cluster show \
            --resource-group $RESOURCE_GROUP \
            --cluster-name $SF_CLUSTER_NAME \
            --query provisioningState --output tsv)
        
        if [[ "$CLUSTER_STATE" == "Succeeded" ]]; then
            log "Service Fabric cluster is ready!"
            break
        elif [[ "$CLUSTER_STATE" == "Failed" ]]; then
            error "Service Fabric cluster creation failed"
        else
            info "Cluster state: $CLUSTER_STATE - waiting..."
            sleep 30
        fi
    done
fi

# Step 6: Create Storage Account for Function App
log "Step 6: Creating Storage Account..."
run_command "az storage account create \
    --name $STORAGE_ACCOUNT_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Standard_LRS \
    --kind StorageV2" \
    "Creating storage account for Function App"

# Step 7: Create Function App
log "Step 7: Creating Function App..."
run_command "az functionapp create \
    --resource-group $RESOURCE_GROUP \
    --consumption-plan-location $LOCATION \
    --runtime node \
    --runtime-version 18 \
    --functions-version 4 \
    --name $FUNCTION_APP_NAME \
    --storage-account $STORAGE_ACCOUNT_NAME \
    --os-type Linux" \
    "Creating Function App for event processing"

# Get Application Insights instrumentation key
if [[ "$DRY_RUN" == "false" ]]; then
    info "Getting Application Insights instrumentation key..."
    APPINSIGHTS_KEY=$(az monitor app-insights component show \
        --app $APP_INSIGHTS_NAME \
        --resource-group $RESOURCE_GROUP \
        --query instrumentationKey --output tsv)
    export APPINSIGHTS_KEY
    info "Application Insights key obtained"
fi

# Configure Function App settings
log "Configuring Function App settings..."
if [[ "$DRY_RUN" == "false" ]]; then
    run_command "az functionapp config appsettings set \
        --name $FUNCTION_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --settings \
        \"APPINSIGHTS_INSTRUMENTATIONKEY=$APPINSIGHTS_KEY\" \
        \"EventHubConnectionString=$EVENT_HUB_CONNECTION\" \
        \"ApplicationInsightsAgent_EXTENSION_VERSION=~3\"" \
        "Configuring Function App with monitoring settings"
else
    info "DRY-RUN: Configuring Function App settings"
fi

# Step 8: Configure Service Fabric Monitoring
log "Step 8: Configuring Service Fabric Monitoring..."
run_command "az sf managed-cluster update \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $SF_CLUSTER_NAME \
    --enable-diagnostics true" \
    "Enabling diagnostics on Service Fabric cluster"

# Get cluster resource ID and configure diagnostic settings
if [[ "$DRY_RUN" == "false" ]]; then
    info "Getting cluster resource ID..."
    CLUSTER_ID=$(az sf managed-cluster show \
        --resource-group $RESOURCE_GROUP \
        --cluster-name $SF_CLUSTER_NAME \
        --query id --output tsv)
    export CLUSTER_ID
    info "Cluster ID: $CLUSTER_ID"

    # Configure diagnostic settings
    info "Configuring diagnostic settings..."
    az monitor diagnostic-settings create \
        --resource "$CLUSTER_ID" \
        --name sf-diagnostics \
        --workspace "$WORKSPACE_ID" \
        --logs '[
          {
            "category": "OperationalChannel",
            "enabled": true,
            "retentionPolicy": {
              "enabled": true,
              "days": 30
            }
          },
          {
            "category": "ReliableServiceActorChannel",
            "enabled": true,
            "retentionPolicy": {
              "enabled": true,
              "days": 30
            }
          }
        ]' \
        --metrics '[
          {
            "category": "AllMetrics",
            "enabled": true,
            "retentionPolicy": {
              "enabled": true,
              "days": 30
            }
          }
        ]'
    
    log "Diagnostic settings configured"
fi

# Step 9: Create Monitoring Dashboard and Alerts
log "Step 9: Creating Monitoring Dashboard and Alerts..."

# Create alert rules for service health
if [[ "$DRY_RUN" == "false" ]]; then
    run_command "az monitor metrics alert create \
        --name \"Service Fabric Cluster Health\" \
        --resource-group $RESOURCE_GROUP \
        --scopes \"$CLUSTER_ID\" \
        --condition \"avg ClusterHealthState < 3\" \
        --description \"Alert when cluster health degrades\" \
        --evaluation-frequency 1m \
        --window-size 5m \
        --severity 2" \
        "Creating cluster health alert"

    # Create alert for application errors
    run_command "az monitor scheduled-query create \
        --resource-group $RESOURCE_GROUP \
        --name \"High Error Rate Alert\" \
        --scopes \"$WORKSPACE_ID\" \
        --condition-query \"exceptions | where timestamp > ago(5m) | summarize count()\" \
        --condition-threshold 10 \
        --condition-operator \"GreaterThan\" \
        --description \"Alert when error rate exceeds threshold\" \
        --evaluation-frequency 1m \
        --window-size 5m \
        --severity 2" \
        "Creating high error rate alert"
else
    info "DRY-RUN: Creating monitoring alerts"
fi

# Step 10: Create Configuration Files
log "Step 10: Creating Configuration Files..."

# Create distributed tracing configuration
if [[ "$DRY_RUN" == "false" ]]; then
    # Get Application Insights connection string
    APP_INSIGHTS_CONNECTION=$(az monitor app-insights component show \
        --app $APP_INSIGHTS_NAME \
        --resource-group $RESOURCE_GROUP \
        --query connectionString --output tsv)

    # Create configuration directory
    mkdir -p ~/microservices-monitoring-config

    # Create distributed tracing config
    cat > ~/microservices-monitoring-config/distributed-tracing-config.json << EOF
{
  "applicationInsights": {
    "connectionString": "$APP_INSIGHTS_CONNECTION",
    "sampling": {
      "percentage": 100,
      "excludedTypes": "Trace"
    },
    "enableLiveMetrics": true,
    "enableDependencyTracking": true
  },
  "eventHub": {
    "connectionString": "$EVENT_HUB_CONNECTION",
    "eventHubName": "service-events"
  },
  "correlationSettings": {
    "enableW3CTraceContext": true,
    "enableRequestIdGeneration": true,
    "enableActivityTracking": true
  }
}
EOF

    # Create monitoring queries
    cat > ~/microservices-monitoring-config/monitoring-queries.kql << 'EOF'
// Service dependency map
dependencies
| where timestamp > ago(1h)
| summarize count() by cloud_RoleName, name, target
| order by count_ desc

// Request performance across services
requests
| where timestamp > ago(1h)
| summarize avg(duration), percentile(duration, 95), count() by cloud_RoleName
| order by avg_duration desc

// Error rate by service
union exceptions, traces
| where timestamp > ago(1h) and severityLevel >= 2
| summarize errors = count() by cloud_RoleName
| order by errors desc
EOF

    log "Configuration files created in ~/microservices-monitoring-config/"
else
    info "DRY-RUN: Creating configuration files"
fi

# Save deployment information
if [[ "$DRY_RUN" == "false" ]]; then
    cat > ~/microservices-monitoring-config/deployment-info.txt << EOF
Deployment Information
======================
Date: $(date)
Resource Group: $RESOURCE_GROUP
Location: $LOCATION
Service Fabric Cluster: $SF_CLUSTER_NAME
Application Insights: $APP_INSIGHTS_NAME
Function App: $FUNCTION_APP_NAME
Storage Account: $STORAGE_ACCOUNT_NAME
Event Hub Namespace: $EVENT_HUB_NAMESPACE
Log Analytics Workspace: $LOG_ANALYTICS_NAME

Connection Information
=====================
Event Hub Connection String: $EVENT_HUB_CONNECTION
Application Insights Key: $APPINSIGHTS_KEY
Cluster ID: $CLUSTER_ID
Workspace ID: $WORKSPACE_ID

Access URLs
===========
Service Fabric Explorer: https://$SF_CLUSTER_NAME.$LOCATION.cloudapp.azure.com:19080
Application Insights: https://portal.azure.com/#@/resource$WORKSPACE_ID/overview

Cleanup Command
===============
To clean up all resources, run:
./destroy.sh
EOF

    log "Deployment information saved to ~/microservices-monitoring-config/deployment-info.txt"
fi

# Final validation
log "Performing final validation..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Check resource group exists
    if az group show --name $RESOURCE_GROUP &> /dev/null; then
        log "✅ Resource group verified"
    else
        error "❌ Resource group not found"
    fi

    # Check Service Fabric cluster
    CLUSTER_STATE=$(az sf managed-cluster show \
        --resource-group $RESOURCE_GROUP \
        --cluster-name $SF_CLUSTER_NAME \
        --query clusterState --output tsv 2>/dev/null || echo "NotFound")
    
    if [[ "$CLUSTER_STATE" == "WaitingForNodes" ]] || [[ "$CLUSTER_STATE" == "Ready" ]]; then
        log "✅ Service Fabric cluster verified (State: $CLUSTER_STATE)"
    else
        warn "⚠️  Service Fabric cluster state: $CLUSTER_STATE"
    fi

    # Check Application Insights
    if az monitor app-insights component show \
        --app $APP_INSIGHTS_NAME \
        --resource-group $RESOURCE_GROUP &> /dev/null; then
        log "✅ Application Insights verified"
    else
        error "❌ Application Insights not found"
    fi

    # Check Function App
    if az functionapp show \
        --name $FUNCTION_APP_NAME \
        --resource-group $RESOURCE_GROUP &> /dev/null; then
        log "✅ Function App verified"
    else
        error "❌ Function App not found"
    fi
else
    info "DRY-RUN: Skipping validation"
fi

# Success message
echo
echo -e "${GREEN}========================================================"
echo "  Deployment Complete!"
echo "========================================================${NC}"
echo
log "Azure Service Fabric Microservices Monitoring solution deployed successfully!"
echo
info "Next Steps:"
info "1. Review the configuration files in ~/microservices-monitoring-config/"
info "2. Access Service Fabric Explorer at: https://$SF_CLUSTER_NAME.$LOCATION.cloudapp.azure.com:19080"
info "3. Monitor your services in Application Insights through the Azure Portal"
info "4. Deploy your microservices applications to the Service Fabric cluster"
info "5. Configure your applications to send telemetry to Application Insights"
echo
warn "Remember to run './destroy.sh' when you're finished to avoid ongoing charges!"
echo