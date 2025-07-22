#!/bin/bash

# Azure HPC Cache Monitoring Deployment Script
# This script deploys the HPC monitoring infrastructure with proper error handling and logging

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
RESOURCE_GROUP_PREFIX="rg-hpc-monitoring"
LOCATION="eastus"
SUBSCRIPTION_ID=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    exit 1
}

# Success message
success() {
    log "${GREEN}SUCCESS: ${1}${NC}"
}

# Warning message
warning() {
    log "${YELLOW}WARNING: ${1}${NC}"
}

# Info message
info() {
    log "${BLUE}INFO: ${1}${NC}"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    info "Using subscription: ${SUBSCRIPTION_ID}"
    
    # Check if OpenSSL is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error_exit "OpenSSL is not installed. Required for generating random strings."
    fi
    
    success "Prerequisites check passed"
}

# Generate resource names
generate_resource_names() {
    info "Generating unique resource names..."
    
    # Generate random suffix
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Export resource names
    export RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX}-${RANDOM_SUFFIX}"
    export HPC_CACHE_NAME="hpc-cache-${RANDOM_SUFFIX}"
    export BATCH_ACCOUNT_NAME="batch${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="hpcstorage${RANDOM_SUFFIX}"
    export WORKSPACE_NAME="hpc-workspace-${RANDOM_SUFFIX}"
    export WORKBOOK_NAME="hpc-monitoring-workbook"
    export VNET_NAME="hpc-vnet"
    export SUBNET_NAME="hpc-subnet"
    export ACTION_GROUP_NAME="hpc-alerts"
    
    info "Resource names generated with suffix: ${RANDOM_SUFFIX}"
}

# Create resource group
create_resource_group() {
    info "Creating resource group: ${RESOURCE_GROUP}"
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=hpc-monitoring environment=demo \
        || error_exit "Failed to create resource group"
    
    success "Resource group created: ${RESOURCE_GROUP}"
}

# Create Log Analytics workspace
create_log_analytics_workspace() {
    info "Creating Log Analytics workspace: ${WORKSPACE_NAME}"
    
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${WORKSPACE_NAME}" \
        --location "${LOCATION}" \
        --sku PerGB2018 \
        || error_exit "Failed to create Log Analytics workspace"
    
    # Get workspace ID for later use
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${WORKSPACE_NAME}" \
        --query id --output tsv)
    
    success "Log Analytics workspace created: ${WORKSPACE_NAME}"
}

# Create storage account
create_storage_account() {
    info "Creating storage account: ${STORAGE_ACCOUNT_NAME}"
    
    az storage account create \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        || error_exit "Failed to create storage account"
    
    # Get storage account key
    export STORAGE_KEY=$(az storage account keys list \
        --account-name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[0].value" --output tsv)
    
    success "Storage account created: ${STORAGE_ACCOUNT_NAME}"
}

# Create virtual network
create_virtual_network() {
    info "Creating virtual network: ${VNET_NAME}"
    
    az network vnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${VNET_NAME}" \
        --address-prefix 10.0.0.0/16 \
        --subnet-name "${SUBNET_NAME}" \
        --subnet-prefix 10.0.1.0/24 \
        || error_exit "Failed to create virtual network"
    
    # Get subnet ID
    export SUBNET_ID=$(az network vnet subnet show \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${VNET_NAME}" \
        --name "${SUBNET_NAME}" \
        --query id --output tsv)
    
    success "Virtual network created: ${VNET_NAME}"
}

# Create HPC Cache
create_hpc_cache() {
    info "Creating HPC Cache: ${HPC_CACHE_NAME}"
    
    # Note: This may take 15-30 minutes to complete
    warning "HPC Cache creation may take 15-30 minutes. Please be patient..."
    
    az hpc-cache create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${HPC_CACHE_NAME}" \
        --location "${LOCATION}" \
        --cache-size-gb 3072 \
        --subnet "${SUBNET_ID}" \
        --sku-name Standard_2G \
        || error_exit "Failed to create HPC Cache"
    
    # Get cache resource ID
    export CACHE_RESOURCE_ID=$(az hpc-cache show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${HPC_CACHE_NAME}" \
        --query id --output tsv)
    
    success "HPC Cache created: ${HPC_CACHE_NAME}"
}

# Create Batch account
create_batch_account() {
    info "Creating Batch account: ${BATCH_ACCOUNT_NAME}"
    
    az batch account create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${BATCH_ACCOUNT_NAME}" \
        --location "${LOCATION}" \
        --storage-account "${STORAGE_ACCOUNT_NAME}" \
        || error_exit "Failed to create Batch account"
    
    # Get Batch account resource ID
    export BATCH_RESOURCE_ID=$(az batch account show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${BATCH_ACCOUNT_NAME}" \
        --query id --output tsv)
    
    # Login to Batch account
    az batch account login \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${BATCH_ACCOUNT_NAME}" \
        || warning "Failed to login to Batch account automatically"
    
    success "Batch account created: ${BATCH_ACCOUNT_NAME}"
}

# Create Batch pool
create_batch_pool() {
    info "Creating Batch pool: hpc-pool"
    
    # Create compute pool for HPC workloads
    az batch pool create \
        --id hpc-pool \
        --vm-size Standard_HC44rs \
        --node-count 2 \
        --image "Canonical:0001-com-ubuntu-server-focal:20_04-lts-gen2" \
        --node-agent-sku-id "batch.node.ubuntu 20.04" \
        || error_exit "Failed to create Batch pool"
    
    success "Batch pool created: hpc-pool"
}

# Enable diagnostic settings
enable_diagnostic_settings() {
    info "Enabling diagnostic settings..."
    
    # Enable diagnostics for HPC Cache
    az monitor diagnostic-settings create \
        --resource "${CACHE_RESOURCE_ID}" \
        --name "hpc-cache-diagnostics" \
        --workspace "${WORKSPACE_ID}" \
        --logs '[
            {
                "category": "ServiceLog",
                "enabled": true
            }
        ]' \
        --metrics '[
            {
                "category": "AllMetrics",
                "enabled": true
            }
        ]' \
        || warning "Failed to enable HPC Cache diagnostics"
    
    # Enable diagnostics for Batch
    az monitor diagnostic-settings create \
        --resource "${BATCH_RESOURCE_ID}" \
        --name "batch-diagnostics" \
        --workspace "${WORKSPACE_ID}" \
        --logs '[
            {
                "category": "ServiceLog",
                "enabled": true
            }
        ]' \
        --metrics '[
            {
                "category": "AllMetrics",
                "enabled": true
            }
        ]' \
        || warning "Failed to enable Batch diagnostics"
    
    success "Diagnostic settings enabled"
}

# Create Azure Monitor Workbook
create_workbook() {
    info "Creating Azure Monitor Workbook: ${WORKBOOK_NAME}"
    
    # Create workbook JSON configuration
    cat > "${SCRIPT_DIR}/hpc-workbook.json" << 'EOF'
{
    "version": "Notebook/1.0",
    "items": [
        {
            "type": 1,
            "content": {
                "json": "## HPC Cache Performance Dashboard\n\nThis dashboard provides comprehensive monitoring for Azure HPC Cache, Batch compute clusters, and storage performance metrics."
            }
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": "AzureMetrics\n| where ResourceProvider == \"MICROSOFT.STORAGECACHE\"\n| where MetricName == \"CacheHitPercent\"\n| summarize avg(Average) by bin(TimeGenerated, 5m)\n| render timechart",
                "size": 0,
                "title": "Cache Hit Rate Over Time",
                "timeContext": {
                    "durationMs": 3600000
                }
            }
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": "AzureMetrics\n| where ResourceProvider == \"MICROSOFT.BATCH\"\n| where MetricName == \"RunningNodeCount\"\n| summarize avg(Average) by bin(TimeGenerated, 5m)\n| render timechart",
                "size": 0,
                "title": "Active Compute Nodes",
                "timeContext": {
                    "durationMs": 3600000
                }
            }
        }
    ]
}
EOF
    
    # Create the workbook
    az monitor workbook create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${WORKBOOK_NAME}" \
        --location "${LOCATION}" \
        --display-name "HPC Monitoring Dashboard" \
        --description "Comprehensive monitoring for HPC Cache and Batch workloads" \
        --serialized-data "@${SCRIPT_DIR}/hpc-workbook.json" \
        || error_exit "Failed to create workbook"
    
    success "Azure Monitor Workbook created: ${WORKBOOK_NAME}"
}

# Create action group and alerts
create_alerts() {
    info "Creating performance alerts..."
    
    # Create action group
    az monitor action-group create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${ACTION_GROUP_NAME}" \
        --display-name "HPC Monitoring Alerts" \
        --email-receiver name=admin email=admin@example.com \
        || warning "Failed to create action group"
    
    # Create alert rule for low cache hit rate
    az monitor metrics alert create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "low-cache-hit-rate" \
        --description "Alert when cache hit rate drops below 80%" \
        --scopes "${CACHE_RESOURCE_ID}" \
        --condition "avg CacheHitPercent < 80" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --action-group "${ACTION_GROUP_NAME}" \
        || warning "Failed to create cache hit rate alert"
    
    # Create alert for high compute utilization
    az monitor metrics alert create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "high-compute-utilization" \
        --description "Alert when compute nodes exceed 90% utilization" \
        --scopes "${BATCH_RESOURCE_ID}" \
        --condition "avg RunningNodeCount > 90" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --action-group "${ACTION_GROUP_NAME}" \
        || warning "Failed to create compute utilization alert"
    
    success "Performance alerts configured"
}

# Display deployment summary
display_summary() {
    info "Deployment Summary"
    echo "==================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "HPC Cache: ${HPC_CACHE_NAME}"
    echo "Batch Account: ${BATCH_ACCOUNT_NAME}"
    echo "Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "Log Analytics Workspace: ${WORKSPACE_NAME}"
    echo "Monitor Workbook: ${WORKBOOK_NAME}"
    echo "==================="
    
    info "To view the monitoring dashboard:"
    echo "1. Navigate to Azure Portal"
    echo "2. Go to Azure Monitor > Workbooks"
    echo "3. Find '${WORKBOOK_NAME}' in your resource group"
    
    info "To run a test workload:"
    echo "1. Submit a job to the Batch pool 'hpc-pool'"
    echo "2. Monitor performance in the workbook"
    echo "3. Check alerts for any threshold violations"
}

# Save deployment info
save_deployment_info() {
    info "Saving deployment information..."
    
    cat > "${SCRIPT_DIR}/deployment-info.json" << EOF
{
    "resourceGroup": "${RESOURCE_GROUP}",
    "location": "${LOCATION}",
    "subscriptionId": "${SUBSCRIPTION_ID}",
    "resources": {
        "hpcCache": "${HPC_CACHE_NAME}",
        "batchAccount": "${BATCH_ACCOUNT_NAME}",
        "storageAccount": "${STORAGE_ACCOUNT_NAME}",
        "workspace": "${WORKSPACE_NAME}",
        "workbook": "${WORKBOOK_NAME}",
        "vnet": "${VNET_NAME}",
        "subnet": "${SUBNET_NAME}"
    },
    "resourceIds": {
        "hpcCache": "${CACHE_RESOURCE_ID}",
        "batchAccount": "${BATCH_RESOURCE_ID}",
        "workspace": "${WORKSPACE_ID}",
        "subnet": "${SUBNET_ID}"
    },
    "deploymentDate": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
}
EOF
    
    success "Deployment information saved to deployment-info.json"
}

# Main deployment function
main() {
    log "Starting Azure HPC Cache Monitoring deployment..."
    log "Log file: ${LOG_FILE}"
    
    # Clear log file
    > "${LOG_FILE}"
    
    # Run deployment steps
    check_prerequisites
    generate_resource_names
    create_resource_group
    create_log_analytics_workspace
    create_storage_account
    create_virtual_network
    create_hpc_cache
    create_batch_account
    create_batch_pool
    enable_diagnostic_settings
    create_workbook
    create_alerts
    save_deployment_info
    display_summary
    
    success "Deployment completed successfully!"
    warning "Note: Azure HPC Cache will be retired on September 30, 2025. Consider migrating to Azure Managed Lustre."
}

# Run the main function
main "$@"