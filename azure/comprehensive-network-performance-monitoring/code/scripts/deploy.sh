#!/bin/bash

# Deploy Azure Network Performance Monitoring with Network Watcher and Application Insights
# This script implements the complete solution from the recipe

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required tools are available
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $az_version"
    
    # Get current subscription
    local subscription=$(az account show --query name -o tsv)
    log "Current subscription: $subscription"
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-network-monitoring-${RANDOM_SUFFIX}"
    export LOCATION="eastus"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export VNET_NAME="vnet-monitoring"
    export SUBNET_NAME="subnet-monitoring"
    export LOG_ANALYTICS_WORKSPACE="law-network-monitoring-${RANDOM_SUFFIX}"
    export APP_INSIGHTS_NAME="ai-network-monitoring-${RANDOM_SUFFIX}"
    export SOURCE_VM_NAME="vm-source-${RANDOM_SUFFIX}"
    export DEST_VM_NAME="vm-dest-${RANDOM_SUFFIX}"
    export CONNECTION_MONITOR_NAME="cm-network-performance-${RANDOM_SUFFIX}"
    export NSG_NAME="nsg-monitoring-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stanetmon${RANDOM_SUFFIX}"
    
    info "Resource naming suffix: ${RANDOM_SUFFIX}"
    info "Resource group: ${RESOURCE_GROUP}"
    info "Location: ${LOCATION}"
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
RANDOM_SUFFIX=${RANDOM_SUFFIX}
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
VNET_NAME=${VNET_NAME}
SUBNET_NAME=${SUBNET_NAME}
LOG_ANALYTICS_WORKSPACE=${LOG_ANALYTICS_WORKSPACE}
APP_INSIGHTS_NAME=${APP_INSIGHTS_NAME}
SOURCE_VM_NAME=${SOURCE_VM_NAME}
DEST_VM_NAME=${DEST_VM_NAME}
CONNECTION_MONITOR_NAME=${CONNECTION_MONITOR_NAME}
NSG_NAME=${NSG_NAME}
STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME}
EOF
    
    log "Environment variables set successfully"
}

# Function to create resource group and network infrastructure
create_infrastructure() {
    log "Creating infrastructure..."
    
    # Create resource group
    az group create \
        --name ${RESOURCE_GROUP} \
        --location ${LOCATION} \
        --tags purpose=network-monitoring environment=demo
    
    log "Resource group created: ${RESOURCE_GROUP}"
    
    # Create virtual network and subnet
    az network vnet create \
        --name ${VNET_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --location ${LOCATION} \
        --address-prefixes 10.0.0.0/16 \
        --subnet-name ${SUBNET_NAME} \
        --subnet-prefixes 10.0.1.0/24
    
    log "Virtual network created: ${VNET_NAME}"
    
    # Ensure Network Watcher is enabled in the region
    az network watcher configure \
        --resource-group NetworkWatcherRG \
        --location ${LOCATION} \
        --enabled true
    
    log "Network Watcher enabled in region: ${LOCATION}"
}

# Function to create monitoring resources
create_monitoring_resources() {
    log "Creating monitoring resources..."
    
    # Create Log Analytics workspace
    az monitor log-analytics workspace create \
        --resource-group ${RESOURCE_GROUP} \
        --workspace-name ${LOG_ANALYTICS_WORKSPACE} \
        --location ${LOCATION} \
        --sku PerGB2018
    
    # Get workspace ID for later use
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group ${RESOURCE_GROUP} \
        --workspace-name ${LOG_ANALYTICS_WORKSPACE} \
        --query customerId --output tsv)
    
    log "Log Analytics workspace created: ${LOG_ANALYTICS_WORKSPACE}"
    
    # Create Application Insights instance
    az monitor app-insights component create \
        --app ${APP_INSIGHTS_NAME} \
        --location ${LOCATION} \
        --resource-group ${RESOURCE_GROUP} \
        --workspace ${LOG_ANALYTICS_WORKSPACE}
    
    # Get instrumentation key
    export INSTRUMENTATION_KEY=$(az monitor app-insights component show \
        --app ${APP_INSIGHTS_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query instrumentationKey --output tsv)
    
    log "Application Insights created: ${APP_INSIGHTS_NAME}"
    
    # Update environment file with new variables
    echo "WORKSPACE_ID=${WORKSPACE_ID}" >> .env
    echo "INSTRUMENTATION_KEY=${INSTRUMENTATION_KEY}" >> .env
}

# Function to create virtual machines
create_virtual_machines() {
    log "Creating virtual machines..."
    
    # Create source VM
    az vm create \
        --resource-group ${RESOURCE_GROUP} \
        --name ${SOURCE_VM_NAME} \
        --image Ubuntu2204 \
        --vnet-name ${VNET_NAME} \
        --subnet ${SUBNET_NAME} \
        --admin-username azureuser \
        --generate-ssh-keys \
        --size Standard_B2s \
        --public-ip-sku Standard
    
    log "Source VM created: ${SOURCE_VM_NAME}"
    
    # Create destination VM
    az vm create \
        --resource-group ${RESOURCE_GROUP} \
        --name ${DEST_VM_NAME} \
        --image Ubuntu2204 \
        --vnet-name ${VNET_NAME} \
        --subnet ${SUBNET_NAME} \
        --admin-username azureuser \
        --generate-ssh-keys \
        --size Standard_B2s \
        --public-ip-sku Standard
    
    log "Destination VM created: ${DEST_VM_NAME}"
    
    # Install Network Watcher extension on source VM
    az vm extension set \
        --resource-group ${RESOURCE_GROUP} \
        --vm-name ${SOURCE_VM_NAME} \
        --name NetworkWatcherAgentLinux \
        --publisher Microsoft.Azure.NetworkWatcher \
        --version 1.4
    
    log "Network Watcher extension installed on source VM"
    
    # Get VM resource IDs
    export SOURCE_VM_ID=$(az vm show \
        --resource-group ${RESOURCE_GROUP} \
        --name ${SOURCE_VM_NAME} \
        --query id --output tsv)
    
    export DEST_VM_ID=$(az vm show \
        --resource-group ${RESOURCE_GROUP} \
        --name ${DEST_VM_NAME} \
        --query id --output tsv)
    
    # Update environment file with VM IDs
    echo "SOURCE_VM_ID=${SOURCE_VM_ID}" >> .env
    echo "DEST_VM_ID=${DEST_VM_ID}" >> .env
}

# Function to configure connection monitor
configure_connection_monitor() {
    log "Configuring connection monitor..."
    
    # Create connection monitor configuration
    cat > connection-monitor-config.json << EOF
{
    "location": "${LOCATION}",
    "properties": {
        "endpoints": [
            {
                "name": "source-endpoint",
                "type": "AzureVM",
                "resourceId": "${SOURCE_VM_ID}"
            },
            {
                "name": "dest-endpoint",
                "type": "AzureVM",
                "resourceId": "${DEST_VM_ID}"
            },
            {
                "name": "external-endpoint",
                "type": "ExternalAddress",
                "address": "www.microsoft.com"
            }
        ],
        "testConfigurations": [
            {
                "name": "tcp-test",
                "testFrequencySec": 30,
                "protocol": "TCP",
                "tcpConfiguration": {
                    "port": 80,
                    "disableTraceRoute": false
                },
                "successThreshold": {
                    "checksFailedPercent": 20,
                    "roundTripTimeMs": 1000
                }
            },
            {
                "name": "icmp-test",
                "testFrequencySec": 60,
                "protocol": "ICMP",
                "icmpConfiguration": {
                    "disableTraceRoute": false
                },
                "successThreshold": {
                    "checksFailedPercent": 10,
                    "roundTripTimeMs": 500
                }
            }
        ],
        "testGroups": [
            {
                "name": "vm-to-vm-tests",
                "sources": ["source-endpoint"],
                "destinations": ["dest-endpoint"],
                "testConfigurations": ["tcp-test", "icmp-test"]
            },
            {
                "name": "vm-to-external-tests",
                "sources": ["source-endpoint"],
                "destinations": ["external-endpoint"],
                "testConfigurations": ["tcp-test", "icmp-test"]
            }
        ],
        "outputs": [
            {
                "type": "Workspace",
                "workspaceSettings": {
                    "workspaceResourceId": "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${LOG_ANALYTICS_WORKSPACE}"
                }
            }
        ]
    }
}
EOF
    
    # Create connection monitor
    az rest \
        --method PUT \
        --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/NetworkWatcherRG/providers/Microsoft.Network/networkWatchers/NetworkWatcher_${LOCATION}/connectionMonitors/${CONNECTION_MONITOR_NAME}?api-version=2021-05-01" \
        --body @connection-monitor-config.json
    
    log "Connection Monitor created: ${CONNECTION_MONITOR_NAME}"
}

# Function to configure monitoring alerts
configure_monitoring_alerts() {
    log "Configuring monitoring alerts..."
    
    # Create action group for network alerts
    az monitor action-group create \
        --name "NetworkAlerts" \
        --resource-group ${RESOURCE_GROUP} \
        --short-name "NetAlert" \
        --email-receiver name="Admin" email="admin@company.com" || {
        warn "Failed to create action group - continuing with deployment"
    }
    
    log "Network monitoring alerts configured"
}

# Function to setup advanced diagnostics
setup_advanced_diagnostics() {
    log "Setting up advanced diagnostics..."
    
    # Create storage account for flow logs
    az storage account create \
        --name ${STORAGE_ACCOUNT_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --location ${LOCATION} \
        --sku Standard_LRS \
        --kind StorageV2
    
    # Get storage account ID
    export STORAGE_ACCOUNT_ID=$(az storage account show \
        --name ${STORAGE_ACCOUNT_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query id --output tsv)
    
    # Create NSG for network monitoring
    az network nsg create \
        --resource-group ${RESOURCE_GROUP} \
        --name ${NSG_NAME} \
        --location ${LOCATION}
    
    # Get NSG ID
    export NSG_ID=$(az network nsg show \
        --resource-group ${RESOURCE_GROUP} \
        --name ${NSG_NAME} \
        --query id --output tsv)
    
    # Configure NSG flow logs
    az network watcher flow-log create \
        --resource-group NetworkWatcherRG \
        --name "flow-log-${RANDOM_SUFFIX}" \
        --nsg ${NSG_ID} \
        --storage-account ${STORAGE_ACCOUNT_ID} \
        --location ${LOCATION} \
        --format JSON \
        --log-version 2 \
        --retention 30 \
        --workspace ${LOG_ANALYTICS_WORKSPACE} || {
        warn "Failed to configure NSG flow logs - continuing with deployment"
    }
    
    log "Advanced diagnostics configured"
    
    # Update environment file with additional variables
    echo "STORAGE_ACCOUNT_ID=${STORAGE_ACCOUNT_ID}" >> .env
    echo "NSG_ID=${NSG_ID}" >> .env
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check resource group exists
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        log "✅ Resource group validation passed"
    else
        error "❌ Resource group validation failed"
        exit 1
    fi
    
    # Check VMs are running
    local source_vm_state=$(az vm show --resource-group ${RESOURCE_GROUP} --name ${SOURCE_VM_NAME} --query "instanceView.statuses[?code=='PowerState/running']" --output tsv)
    local dest_vm_state=$(az vm show --resource-group ${RESOURCE_GROUP} --name ${DEST_VM_NAME} --query "instanceView.statuses[?code=='PowerState/running']" --output tsv)
    
    if [[ -n "$source_vm_state" && -n "$dest_vm_state" ]]; then
        log "✅ Virtual machines validation passed"
    else
        warn "⚠️ Virtual machines may still be starting up"
    fi
    
    # Check Log Analytics workspace
    if az monitor log-analytics workspace show --resource-group ${RESOURCE_GROUP} --workspace-name ${LOG_ANALYTICS_WORKSPACE} &> /dev/null; then
        log "✅ Log Analytics workspace validation passed"
    else
        error "❌ Log Analytics workspace validation failed"
        exit 1
    fi
    
    # Check Application Insights
    if az monitor app-insights component show --app ${APP_INSIGHTS_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        log "✅ Application Insights validation passed"
    else
        error "❌ Application Insights validation failed"
        exit 1
    fi
    
    log "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "==================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Virtual Network: ${VNET_NAME}"
    echo "Source VM: ${SOURCE_VM_NAME}"
    echo "Destination VM: ${DEST_VM_NAME}"
    echo "Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}"
    echo "Application Insights: ${APP_INSIGHTS_NAME}"
    echo "Connection Monitor: ${CONNECTION_MONITOR_NAME}"
    echo "Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "==================="
    echo ""
    echo "Next Steps:"
    echo "1. Wait 5-10 minutes for connection monitor to collect initial data"
    echo "2. Check Azure portal for monitoring dashboards"
    echo "3. Review Log Analytics workspace for network metrics"
    echo "4. Test connectivity using Network Watcher tools"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting Azure Network Performance Monitoring deployment..."
    
    check_prerequisites
    set_environment_variables
    create_infrastructure
    create_monitoring_resources
    create_virtual_machines
    configure_connection_monitor
    configure_monitoring_alerts
    setup_advanced_diagnostics
    validate_deployment
    display_summary
    
    log "Deployment completed successfully!"
    log "Check the Azure portal for your monitoring resources."
}

# Trap to handle script interruption
trap 'error "Script interrupted. Resources may be partially created. Run ./destroy.sh to clean up."; exit 1' INT TERM

# Run main function
main "$@"