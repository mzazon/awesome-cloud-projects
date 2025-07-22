#!/bin/bash

# Azure Network Threat Detection Deployment Script
# This script deploys the complete Azure Network Threat Detection solution
# using Azure Network Watcher, Log Analytics, and Logic Apps

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
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

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    log_warning "Running in DRY RUN mode - no resources will be created"
    AZURE_CMD="echo [DRY RUN] az"
else
    AZURE_CMD="az"
fi

# Configuration variables
RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-network-threat-detection"}
LOCATION=${LOCATION:-"eastus"}
STORAGE_ACCOUNT_PREFIX=${STORAGE_ACCOUNT_PREFIX:-"sanetworklogs"}
LOG_ANALYTICS_PREFIX=${LOG_ANALYTICS_PREFIX:-"law-threat-detection"}
LOGIC_APP_PREFIX=${LOGIC_APP_PREFIX:-"la-threat-response"}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for generating random suffix
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Required for generating unique resource names."
        exit 1
    fi
    
    # Get and display current subscription
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    log "Current subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    
    # Check if Network Watcher is available in the region
    if ! az network watcher show --resource-group NetworkWatcherRG --name "NetworkWatcher_${LOCATION}" --query "provisioningState" --output tsv &> /dev/null; then
        log_warning "Network Watcher not found in region $LOCATION. It will be created automatically."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT_PREFIX}${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_PREFIX}-${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="${LOGIC_APP_PREFIX}-${RANDOM_SUFFIX}"
    
    # Store subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    log "Environment variables set:"
    log "  RESOURCE_GROUP: $RESOURCE_GROUP"
    log "  LOCATION: $LOCATION"
    log "  STORAGE_ACCOUNT: $STORAGE_ACCOUNT"
    log "  LOG_ANALYTICS_WORKSPACE: $LOG_ANALYTICS_WORKSPACE"
    log "  LOGIC_APP_NAME: $LOGIC_APP_NAME"
    log "  SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
    
    log_success "Environment setup completed"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    $AZURE_CMD group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=network-security environment=production
    
    log_success "Resource group created: $RESOURCE_GROUP"
}

# Function to verify Network Watcher
verify_network_watcher() {
    log "Verifying Network Watcher..."
    
    # Check if Network Watcher exists, create if not
    if ! $AZURE_CMD network watcher show \
        --resource-group NetworkWatcherRG \
        --name "NetworkWatcher_${LOCATION}" \
        --query "provisioningState" \
        --output tsv &> /dev/null; then
        
        log_warning "Network Watcher not found. Creating..."
        $AZURE_CMD network watcher configure \
            --resource-group NetworkWatcherRG \
            --locations "$LOCATION" \
            --enabled true
    fi
    
    log_success "Network Watcher verified for region: $LOCATION"
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account for NSG Flow Logs..."
    
    $AZURE_CMD storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --tags purpose=flow-logs security=enabled
    
    # Get storage account key
    if [ "$DRY_RUN" != "true" ]; then
        export STORAGE_KEY=$(az storage account keys list \
            --resource-group "$RESOURCE_GROUP" \
            --account-name "$STORAGE_ACCOUNT" \
            --query "[0].value" --output tsv)
    fi
    
    log_success "Storage account created: $STORAGE_ACCOUNT"
}

# Function to create Log Analytics workspace
create_log_analytics_workspace() {
    log "Creating Log Analytics workspace..."
    
    $AZURE_CMD monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --location "$LOCATION" \
        --sku PerGB2018 \
        --retention-time 30 \
        --tags purpose=threat-detection security=enabled
    
    # Get workspace ID and key
    if [ "$DRY_RUN" != "true" ]; then
        export WORKSPACE_ID=$(az monitor log-analytics workspace show \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --query "customerId" --output tsv)
        
        export WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --query "primarySharedKey" --output tsv)
    fi
    
    log_success "Log Analytics workspace created: $LOG_ANALYTICS_WORKSPACE"
}

# Function to configure NSG Flow Logs
configure_nsg_flow_logs() {
    log "Configuring NSG Flow Logs..."
    
    # Get existing NSG for flow log configuration
    # This assumes there's at least one NSG in the resource group
    NSG_ID=$(az network nsg list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].id" --output tsv 2>/dev/null || echo "")
    
    if [ -z "$NSG_ID" ]; then
        log_warning "No existing NSG found. Creating a default NSG for demonstration..."
        
        # Create a default NSG
        $AZURE_CMD network nsg create \
            --resource-group "$RESOURCE_GROUP" \
            --name "nsg-default-${RANDOM_SUFFIX}" \
            --location "$LOCATION" \
            --tags purpose=network-security
        
        NSG_ID=$(az network nsg show \
            --resource-group "$RESOURCE_GROUP" \
            --name "nsg-default-${RANDOM_SUFFIX}" \
            --query "id" --output tsv)
    fi
    
    # Create NSG flow log configuration
    $AZURE_CMD network watcher flow-log create \
        --resource-group NetworkWatcherRG \
        --name "fl-${RANDOM_SUFFIX}" \
        --nsg "$NSG_ID" \
        --storage-account "$STORAGE_ACCOUNT" \
        --enabled true \
        --format JSON \
        --log-version 2 \
        --retention 7 \
        --workspace "$WORKSPACE_ID" \
        --location "$LOCATION"
    
    log_success "NSG Flow Logs configured for Network Security Group"
}

# Function to create threat detection queries
create_threat_detection_queries() {
    log "Creating threat detection queries..."
    
    # Create temporary file for KQL queries
    cat > /tmp/threat-detection-queries.kql << 'EOF'
// Suspicious port scanning activity
let SuspiciousPortScan = AzureNetworkAnalytics_CL
| where TimeGenerated > ago(1h)
| where FlowStatus_s == "D" // Denied flows
| summarize DestPorts = dcount(DestPort_d), 
          FlowCount = count() by SrcIP_s, bin(TimeGenerated, 5m)
| where DestPorts > 20 and FlowCount > 50
| project TimeGenerated, SrcIP_s, DestPorts, FlowCount, ThreatLevel = "High";

// Unusual data transfer volumes
let DataExfiltration = AzureNetworkAnalytics_CL
| where TimeGenerated > ago(1h)
| where FlowStatus_s == "A" // Allowed flows
| summarize TotalBytes = sum(OutboundBytes_d) by SrcIP_s, DestIP_s, bin(TimeGenerated, 10m)
| where TotalBytes > 1000000000 // 1GB threshold
| project TimeGenerated, SrcIP_s, DestIP_s, TotalBytes, ThreatLevel = "Medium";

// Failed connection attempts from external IPs
let ExternalFailedConnections = AzureNetworkAnalytics_CL
| where TimeGenerated > ago(1h)
| where FlowStatus_s == "D" and FlowType_s == "ExternalPublic"
| summarize FailedAttempts = count() by SrcIP_s, DestIP_s, bin(TimeGenerated, 5m)
| where FailedAttempts > 100
| project TimeGenerated, SrcIP_s, DestIP_s, FailedAttempts, ThreatLevel = "High";

// Combine all threat indicators
union SuspiciousPortScan, DataExfiltration, ExternalFailedConnections
| order by TimeGenerated desc
EOF
    
    log_success "Threat detection queries created"
}

# Function to create alert rules
create_alert_rules() {
    log "Creating alert rules for automated detection..."
    
    # Create alert rule for suspicious port scanning
    $AZURE_CMD monitor scheduled-query create \
        --resource-group "$RESOURCE_GROUP" \
        --name "Port-Scanning-Alert" \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${LOG_ANALYTICS_WORKSPACE}" \
        --condition-query "AzureNetworkAnalytics_CL | where TimeGenerated > ago(1h) | where FlowStatus_s == \"D\" | summarize DestPorts = dcount(DestPort_d), FlowCount = count() by SrcIP_s, bin(TimeGenerated, 5m) | where DestPorts > 20 and FlowCount > 50" \
        --condition-time-aggregation "Count" \
        --condition-threshold 1 \
        --condition-operator "GreaterThan" \
        --evaluation-frequency "PT5M" \
        --window-size "PT1H" \
        --severity 1 \
        --enabled true \
        --description "Detects suspicious port scanning activity"
    
    # Create alert rule for data exfiltration
    $AZURE_CMD monitor scheduled-query create \
        --resource-group "$RESOURCE_GROUP" \
        --name "Data-Exfiltration-Alert" \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${LOG_ANALYTICS_WORKSPACE}" \
        --condition-query "AzureNetworkAnalytics_CL | where TimeGenerated > ago(1h) | where FlowStatus_s == \"A\" | summarize TotalBytes = sum(OutboundBytes_d) by SrcIP_s, DestIP_s, bin(TimeGenerated, 10m) | where TotalBytes > 1000000000" \
        --condition-time-aggregation "Count" \
        --condition-threshold 1 \
        --condition-operator "GreaterThan" \
        --evaluation-frequency "PT10M" \
        --window-size "PT1H" \
        --severity 2 \
        --enabled true \
        --description "Detects potential data exfiltration activity"
    
    log_success "Alert rules created for automated threat detection"
}

# Function to create Logic Apps workflow
create_logic_apps_workflow() {
    log "Creating Logic Apps workflow for automated response..."
    
    # Create a simplified Logic Apps workflow
    cat > /tmp/logic-app-definition.json << 'EOF'
{
    "definition": {
        "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
        "contentVersion": "1.0.0.0",
        "parameters": {},
        "triggers": {
            "manual": {
                "type": "Request",
                "kind": "Http"
            }
        },
        "actions": {
            "Send_notification": {
                "type": "Http",
                "inputs": {
                    "method": "POST",
                    "uri": "https://httpbin.org/post",
                    "headers": {
                        "Content-Type": "application/json"
                    },
                    "body": {
                        "message": "Network threat detected by Azure monitoring",
                        "timestamp": "@{utcnow()}",
                        "severity": "High"
                    }
                }
            }
        }
    }
}
EOF
    
    $AZURE_CMD logic workflow create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --location "$LOCATION" \
        --definition @/tmp/logic-app-definition.json
    
    log_success "Logic Apps workflow created: $LOGIC_APP_NAME"
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    log "Creating monitoring dashboard..."
    
    # Create workbook template for threat monitoring
    cat > /tmp/threat-monitoring-dashboard.json << 'EOF'
{
    "version": "Notebook/1.0",
    "items": [
        {
            "type": 1,
            "content": {
                "json": "# Network Threat Detection Dashboard\n\nThis dashboard provides real-time monitoring of network security threats detected by Azure Network Watcher and Log Analytics."
            }
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": "AzureNetworkAnalytics_CL\n| where TimeGenerated > ago(24h)\n| where FlowStatus_s == \"D\"\n| summarize DeniedFlows = count() by bin(TimeGenerated, 1h)\n| render timechart",
                "size": 0,
                "title": "Denied Network Flows (24h)",
                "timeContext": {
                    "durationMs": 86400000
                },
                "queryType": 0,
                "resourceType": "microsoft.operationalinsights/workspaces"
            }
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": "AzureNetworkAnalytics_CL\n| where TimeGenerated > ago(24h)\n| where FlowStatus_s == \"D\"\n| summarize ThreatCount = count() by SrcIP_s\n| top 10 by ThreatCount desc\n| render piechart",
                "size": 0,
                "title": "Top Threat Source IPs",
                "timeContext": {
                    "durationMs": 86400000
                },
                "queryType": 0,
                "resourceType": "microsoft.operationalinsights/workspaces"
            }
        }
    ]
}
EOF
    
    # Deploy the workbook template
    $AZURE_CMD monitor workbook create \
        --resource-group "$RESOURCE_GROUP" \
        --name "Network-Threat-Detection-Dashboard" \
        --location "$LOCATION" \
        --display-name "Network Threat Detection Dashboard" \
        --serialized-data @/tmp/threat-monitoring-dashboard.json \
        --category "security"
    
    log_success "Monitoring dashboard created successfully"
}

# Function to save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    # Create deployment info file
    cat > /tmp/deployment-info.json << EOF
{
    "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "resource_group": "$RESOURCE_GROUP",
    "location": "$LOCATION",
    "subscription_id": "$SUBSCRIPTION_ID",
    "resources": {
        "storage_account": "$STORAGE_ACCOUNT",
        "log_analytics_workspace": "$LOG_ANALYTICS_WORKSPACE",
        "logic_app": "$LOGIC_APP_NAME",
        "flow_log_name": "fl-${RANDOM_SUFFIX}",
        "dashboard_name": "Network-Threat-Detection-Dashboard"
    },
    "alert_rules": [
        "Port-Scanning-Alert",
        "Data-Exfiltration-Alert"
    ]
}
EOF
    
    log_success "Deployment information saved to /tmp/deployment-info.json"
}

# Function to display deployment summary
display_deployment_summary() {
    log "Deployment Summary:"
    echo "=================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    echo "Logic App: $LOGIC_APP_NAME"
    echo "Flow Log: fl-${RANDOM_SUFFIX}"
    echo "Dashboard: Network-Threat-Detection-Dashboard"
    echo "=================================="
    log_success "Azure Network Threat Detection solution deployed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Wait 15-30 minutes for NSG Flow Logs to start generating data"
    echo "2. Check the Log Analytics workspace for incoming data"
    echo "3. View the monitoring dashboard for threat visualization"
    echo "4. Configure additional alert rules as needed"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting Azure Network Threat Detection deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_resource_group
    verify_network_watcher
    create_storage_account
    create_log_analytics_workspace
    configure_nsg_flow_logs
    create_threat_detection_queries
    create_alert_rules
    create_logic_apps_workflow
    create_monitoring_dashboard
    save_deployment_info
    display_deployment_summary
    
    log_success "Deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Deployment interrupted! Some resources may have been created."; exit 1' INT TERM

# Run main function
main "$@"