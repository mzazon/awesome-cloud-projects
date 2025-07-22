#!/bin/bash

# Destroy Azure Network Performance Monitoring resources
# This script cleans up all resources created by the deploy.sh script

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
    
    # Check if environment file exists
    if [ ! -f .env ]; then
        error "Environment file (.env) not found. This file is created by deploy.sh."
        error "Please ensure you run this script from the same directory as deploy.sh"
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to load environment variables
load_environment_variables() {
    log "Loading environment variables..."
    
    # Source the environment file
    if [ -f .env ]; then
        source .env
        log "Environment variables loaded from .env file"
    else
        error "Environment file (.env) not found"
        exit 1
    fi
    
    # Validate required variables
    local required_vars=("RESOURCE_GROUP" "LOCATION" "SUBSCRIPTION_ID" "CONNECTION_MONITOR_NAME" "RANDOM_SUFFIX")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    info "Resource group to delete: ${RESOURCE_GROUP}"
    info "Location: ${LOCATION}"
    info "Subscription: ${SUBSCRIPTION_ID}"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warn "⚠️  WARNING: This will permanently delete all resources in the resource group: ${RESOURCE_GROUP}"
    echo ""
    echo "Resources to be deleted:"
    echo "- Resource Group: ${RESOURCE_GROUP}"
    echo "- Virtual Machines: ${SOURCE_VM_NAME:-"vm-source-*"}, ${DEST_VM_NAME:-"vm-dest-*"}"
    echo "- Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE:-"law-network-monitoring-*"}"
    echo "- Application Insights: ${APP_INSIGHTS_NAME:-"ai-network-monitoring-*"}"
    echo "- Connection Monitor: ${CONNECTION_MONITOR_NAME}"
    echo "- Storage Account: ${STORAGE_ACCOUNT_NAME:-"stanetmon*"}"
    echo "- Virtual Network: ${VNET_NAME:-"vnet-monitoring"}"
    echo "- Network Security Group: ${NSG_NAME:-"nsg-monitoring-*"}"
    echo "- All associated resources (NICs, disks, public IPs, etc.)"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed. Proceeding with resource cleanup..."
}

# Function to delete connection monitor
delete_connection_monitor() {
    log "Deleting connection monitor..."
    
    # Delete connection monitor
    if az rest \
        --method DELETE \
        --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/NetworkWatcherRG/providers/Microsoft.Network/networkWatchers/NetworkWatcher_${LOCATION}/connectionMonitors/${CONNECTION_MONITOR_NAME}?api-version=2021-05-01" \
        2>/dev/null; then
        log "✅ Connection monitor deleted: ${CONNECTION_MONITOR_NAME}"
    else
        warn "⚠️ Failed to delete connection monitor or it may not exist"
    fi
    
    # Delete flow log if it exists
    if [ -n "${NSG_ID:-}" ]; then
        if az network watcher flow-log delete \
            --resource-group NetworkWatcherRG \
            --name "flow-log-${RANDOM_SUFFIX}" \
            --location ${LOCATION} \
            2>/dev/null; then
            log "✅ Flow log deleted"
        else
            warn "⚠️ Failed to delete flow log or it may not exist"
        fi
    fi
}

# Function to delete monitoring alerts
delete_monitoring_alerts() {
    log "Deleting monitoring alerts..."
    
    # Delete metric alerts
    local alerts=("High Network Latency Alert" "Network Connectivity Failure")
    for alert in "${alerts[@]}"; do
        if az monitor metrics alert delete \
            --name "$alert" \
            --resource-group ${RESOURCE_GROUP} \
            2>/dev/null; then
            log "✅ Deleted alert: $alert"
        else
            warn "⚠️ Failed to delete alert: $alert (may not exist)"
        fi
    done
    
    # Delete action group
    if az monitor action-group delete \
        --name "NetworkAlerts" \
        --resource-group ${RESOURCE_GROUP} \
        2>/dev/null; then
        log "✅ Action group deleted"
    else
        warn "⚠️ Failed to delete action group (may not exist)"
    fi
}

# Function to delete virtual machines
delete_virtual_machines() {
    log "Deleting virtual machines..."
    
    # Delete source VM
    if [ -n "${SOURCE_VM_NAME:-}" ]; then
        if az vm delete \
            --resource-group ${RESOURCE_GROUP} \
            --name ${SOURCE_VM_NAME} \
            --yes \
            --no-wait \
            2>/dev/null; then
            log "✅ Source VM deletion initiated: ${SOURCE_VM_NAME}"
        else
            warn "⚠️ Failed to delete source VM or it may not exist"
        fi
    fi
    
    # Delete destination VM
    if [ -n "${DEST_VM_NAME:-}" ]; then
        if az vm delete \
            --resource-group ${RESOURCE_GROUP} \
            --name ${DEST_VM_NAME} \
            --yes \
            --no-wait \
            2>/dev/null; then
            log "✅ Destination VM deletion initiated: ${DEST_VM_NAME}"
        else
            warn "⚠️ Failed to delete destination VM or it may not exist"
        fi
    fi
    
    # Wait for VMs to be deleted before proceeding
    info "Waiting for VMs to be deleted..."
    sleep 30
}

# Function to delete storage resources
delete_storage_resources() {
    log "Deleting storage resources..."
    
    # Delete storage account
    if [ -n "${STORAGE_ACCOUNT_NAME:-}" ]; then
        if az storage account delete \
            --name ${STORAGE_ACCOUNT_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --yes \
            2>/dev/null; then
            log "✅ Storage account deleted: ${STORAGE_ACCOUNT_NAME}"
        else
            warn "⚠️ Failed to delete storage account or it may not exist"
        fi
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log "Deleting monitoring resources..."
    
    # Delete Application Insights
    if [ -n "${APP_INSIGHTS_NAME:-}" ]; then
        if az monitor app-insights component delete \
            --app ${APP_INSIGHTS_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            2>/dev/null; then
            log "✅ Application Insights deleted: ${APP_INSIGHTS_NAME}"
        else
            warn "⚠️ Failed to delete Application Insights or it may not exist"
        fi
    fi
    
    # Delete Log Analytics workspace
    if [ -n "${LOG_ANALYTICS_WORKSPACE:-}" ]; then
        if az monitor log-analytics workspace delete \
            --resource-group ${RESOURCE_GROUP} \
            --workspace-name ${LOG_ANALYTICS_WORKSPACE} \
            --yes \
            --force \
            2>/dev/null; then
            log "✅ Log Analytics workspace deleted: ${LOG_ANALYTICS_WORKSPACE}"
        else
            warn "⚠️ Failed to delete Log Analytics workspace or it may not exist"
        fi
    fi
}

# Function to delete network security groups
delete_network_security_groups() {
    log "Deleting network security groups..."
    
    # Delete NSG
    if [ -n "${NSG_NAME:-}" ]; then
        if az network nsg delete \
            --resource-group ${RESOURCE_GROUP} \
            --name ${NSG_NAME} \
            2>/dev/null; then
            log "✅ Network Security Group deleted: ${NSG_NAME}"
        else
            warn "⚠️ Failed to delete NSG or it may not exist"
        fi
    fi
}

# Function to delete network resources
delete_network_resources() {
    log "Deleting network resources..."
    
    # Delete public IPs
    local public_ips=$(az network public-ip list \
        --resource-group ${RESOURCE_GROUP} \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    for ip in $public_ips; do
        if az network public-ip delete \
            --resource-group ${RESOURCE_GROUP} \
            --name $ip \
            2>/dev/null; then
            log "✅ Public IP deleted: $ip"
        else
            warn "⚠️ Failed to delete public IP: $ip"
        fi
    done
    
    # Delete NICs
    local nics=$(az network nic list \
        --resource-group ${RESOURCE_GROUP} \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    for nic in $nics; do
        if az network nic delete \
            --resource-group ${RESOURCE_GROUP} \
            --name $nic \
            2>/dev/null; then
            log "✅ NIC deleted: $nic"
        else
            warn "⚠️ Failed to delete NIC: $nic"
        fi
    done
    
    # Delete virtual network
    if [ -n "${VNET_NAME:-}" ]; then
        if az network vnet delete \
            --resource-group ${RESOURCE_GROUP} \
            --name ${VNET_NAME} \
            2>/dev/null; then
            log "✅ Virtual network deleted: ${VNET_NAME}"
        else
            warn "⚠️ Failed to delete virtual network or it may not exist"
        fi
    fi
}

# Function to delete remaining resources
delete_remaining_resources() {
    log "Deleting remaining resources..."
    
    # Delete disks
    local disks=$(az disk list \
        --resource-group ${RESOURCE_GROUP} \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    for disk in $disks; do
        if az disk delete \
            --resource-group ${RESOURCE_GROUP} \
            --name $disk \
            --yes \
            2>/dev/null; then
            log "✅ Disk deleted: $disk"
        else
            warn "⚠️ Failed to delete disk: $disk"
        fi
    done
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group..."
    
    # Give resources time to clean up
    info "Waiting for resources to be properly cleaned up..."
    sleep 60
    
    # Delete resource group and all remaining resources
    if az group delete \
        --name ${RESOURCE_GROUP} \
        --yes \
        --no-wait; then
        log "✅ Resource group deletion initiated: ${RESOURCE_GROUP}"
        info "Note: Complete deletion may take several minutes"
    else
        error "❌ Failed to delete resource group: ${RESOURCE_GROUP}"
        exit 1
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        ".env"
        "connection-monitor-config.json"
        "network-telemetry-config.json"
        "network-app-correlation-query.kusto"
        "network-performance-workbook.json"
        "packet-capture-config.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "✅ Removed local file: $file"
        fi
    done
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    # Check if resource group still exists
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        warn "⚠️ Resource group still exists. Deletion may be in progress."
        info "You can check the deletion status in the Azure portal."
    else
        log "✅ Resource group successfully deleted"
    fi
    
    # Check if connection monitor still exists
    if az rest \
        --method GET \
        --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/NetworkWatcherRG/providers/Microsoft.Network/networkWatchers/NetworkWatcher_${LOCATION}/connectionMonitors/${CONNECTION_MONITOR_NAME}?api-version=2021-05-01" \
        &> /dev/null; then
        warn "⚠️ Connection monitor may still exist"
    else
        log "✅ Connection monitor successfully deleted"
    fi
    
    log "Cleanup validation completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "==================="
    echo "Deleted Resource Group: ${RESOURCE_GROUP}"
    echo "Deleted Connection Monitor: ${CONNECTION_MONITOR_NAME}"
    echo "Deleted Virtual Machines: ${SOURCE_VM_NAME:-"N/A"}, ${DEST_VM_NAME:-"N/A"}"
    echo "Deleted Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE:-"N/A"}"
    echo "Deleted Application Insights: ${APP_INSIGHTS_NAME:-"N/A"}"
    echo "Deleted Storage Account: ${STORAGE_ACCOUNT_NAME:-"N/A"}"
    echo "Deleted Virtual Network: ${VNET_NAME:-"N/A"}"
    echo "Deleted Network Security Group: ${NSG_NAME:-"N/A"}"
    echo "==================="
    echo ""
    echo "All resources have been cleaned up successfully!"
    echo "Note: Some resources may take additional time to be completely removed from Azure."
}

# Main cleanup function
main() {
    log "Starting Azure Network Performance Monitoring cleanup..."
    
    check_prerequisites
    load_environment_variables
    confirm_deletion
    delete_connection_monitor
    delete_monitoring_alerts
    delete_virtual_machines
    delete_storage_resources
    delete_monitoring_resources
    delete_network_security_groups
    delete_network_resources
    delete_remaining_resources
    delete_resource_group
    cleanup_local_files
    validate_cleanup
    display_cleanup_summary
    
    log "Cleanup completed successfully!"
}

# Trap to handle script interruption
trap 'error "Script interrupted. Some resources may not have been deleted. Please check the Azure portal."; exit 1' INT TERM

# Run main function
main "$@"