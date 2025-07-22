#!/bin/bash

# Intelligent DDoS Protection with Adaptive BGP Routing
# Cleanup/Destroy Script
# 
# This script safely removes all resources created by the deployment script,
# including monitoring, networking, and security components in the proper order
# to handle resource dependencies.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Some resources may still exist. Check Azure portal."
    exit 1
}

# Load environment variables
load_environment() {
    if [ -f ".env" ]; then
        log_info "Loading environment variables from .env file..."
        source .env
        log_success "Environment variables loaded"
    else
        log_warning ".env file not found. You may need to provide resource names manually."
        
        # Try to get resource group from user or use default
        if [ -z "${RESOURCE_GROUP:-}" ]; then
            read -p "Enter resource group name (default: rg-adaptive-network-security): " input_rg
            export RESOURCE_GROUP="${input_rg:-rg-adaptive-network-security}"
        fi
        
        log_info "Using resource group: ${RESOURCE_GROUP}"
        
        # Try to discover resource names if not in environment
        if [ -z "${RANDOM_SUFFIX:-}" ]; then
            log_info "Attempting to discover resource names..."
            
            # Try to find resources with common patterns
            DDOS_PLANS=$(az network ddos-protection list --resource-group "${RESOURCE_GROUP}" --query "[?contains(name,'ddos-plan')].name" -o tsv 2>/dev/null || echo "")
            ROUTE_SERVERS=$(az network routeserver list --resource-group "${RESOURCE_GROUP}" --query "[?contains(name,'rs-adaptive')].name" -o tsv 2>/dev/null || echo "")
            FIREWALLS=$(az network firewall list --resource-group "${RESOURCE_GROUP}" --query "[?contains(name,'fw-adaptive')].name" -o tsv 2>/dev/null || echo "")
            
            # Set discovered names or use defaults
            export DDOS_PLAN_NAME="${DDOS_PLANS:-ddos-plan-unknown}"
            export ROUTE_SERVER_NAME="${ROUTE_SERVERS:-rs-adaptive-unknown}"
            export FIREWALL_NAME="${FIREWALLS:-fw-adaptive-unknown}"
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI before running this script."
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' before running this script."
    fi
    
    # Get current subscription info
    local subscription_name=$(az account show --query name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    log_info "Using subscription: $subscription_name ($subscription_id)"
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group '${RESOURCE_GROUP}' not found. It may have already been deleted."
        exit 0
    fi
    
    log_success "Prerequisites check completed"
}

# Display cleanup confirmation
confirm_cleanup() {
    echo ""
    log_warning "================================== WARNING =================================="
    log_warning "This script will DELETE ALL RESOURCES in the following resource group:"
    log_warning "Resource Group: ${RESOURCE_GROUP}"
    log_warning ""
    log_warning "This includes:"
    log_warning "- Azure DDoS Protection Plan (${DDOS_PLAN_NAME:-unknown})"
    log_warning "- Azure Route Server (${ROUTE_SERVER_NAME:-unknown})"
    log_warning "- Azure Firewall (${FIREWALL_NAME:-unknown})"
    log_warning "- Virtual Networks and all subnets"
    log_warning "- Public IP addresses"
    log_warning "- Log Analytics workspace (${LOG_ANALYTICS_NAME:-unknown})"
    log_warning "- Storage accounts for flow logs"
    log_warning "- Alert rules and action groups"
    log_warning "- All associated monitoring and networking resources"
    log_warning ""
    log_warning "THIS ACTION CANNOT BE UNDONE!"
    log_warning "=========================================================================="
    echo ""
    
    # Allow bypass for automation
    if [ "${FORCE_DELETE:-false}" = "true" ]; then
        log_warning "FORCE_DELETE is set to true. Proceeding with cleanup..."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " confirmation
    if [ "$confirmation" != "yes" ]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "User confirmed cleanup. Proceeding..."
}

# Remove alert rules and action groups
remove_monitoring_alerts() {
    log_info "Removing alert rules and action groups..."
    
    # Delete DDoS attack alert
    if az monitor metrics alert show --name "DDoS-Attack-Alert" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        az monitor metrics alert delete \
            --name "DDoS-Attack-Alert" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            || log_warning "Failed to delete DDoS-Attack-Alert"
        log_success "Deleted DDoS attack alert rule"
    else
        log_info "DDoS attack alert rule not found or already deleted"
    fi
    
    # Delete traffic volume alert
    if az monitor metrics alert show --name "High-Traffic-Volume-Alert" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        az monitor metrics alert delete \
            --name "High-Traffic-Volume-Alert" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            || log_warning "Failed to delete High-Traffic-Volume-Alert"
        log_success "Deleted traffic volume alert rule"
    else
        log_info "Traffic volume alert rule not found or already deleted"
    fi
    
    # Delete action group
    local action_group_name="ddos-alerts-${RANDOM_SUFFIX:-*}"
    local action_groups=$(az monitor action-group list --resource-group "${RESOURCE_GROUP}" --query "[?contains(name,'ddos-alerts')].name" -o tsv 2>/dev/null || echo "")
    
    if [ ! -z "$action_groups" ]; then
        for ag in $action_groups; do
            az monitor action-group delete \
                --name "$ag" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                || log_warning "Failed to delete action group: $ag"
            log_success "Deleted action group: $ag"
        done
    else
        log_info "No action groups found or already deleted"
    fi
    
    log_success "Monitoring alerts cleanup completed"
}

# Remove Flow logs
remove_flow_logs() {
    log_info "Removing Network Watcher flow logs..."
    
    # Find and delete flow logs
    local flow_logs=$(az network watcher flow-log list --location "${LOCATION:-eastus}" --query "[?contains(name,'flowlog')].name" -o tsv 2>/dev/null || echo "")
    
    if [ ! -z "$flow_logs" ]; then
        for fl in $flow_logs; do
            az network watcher flow-log delete \
                --name "$fl" \
                --location "${LOCATION:-eastus}" \
                || log_warning "Failed to delete flow log: $fl"
            log_success "Deleted flow log: $fl"
        done
    else
        log_info "No flow logs found or already deleted"
    fi
    
    log_success "Flow logs cleanup completed"
}

# Remove Azure Route Server
remove_route_server() {
    log_info "Removing Azure Route Server..."
    
    # Check if Route Server exists
    if [ ! -z "${ROUTE_SERVER_NAME:-}" ] && az network routeserver show --name "${ROUTE_SERVER_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Deleting Route Server: ${ROUTE_SERVER_NAME}"
        az network routeserver delete \
            --name "${ROUTE_SERVER_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            || log_warning "Failed to delete Route Server: ${ROUTE_SERVER_NAME}"
        log_success "Deleted Route Server: ${ROUTE_SERVER_NAME}"
    else
        log_info "Route Server not found or already deleted"
    fi
    
    # Delete Route Server public IP
    local rs_pip_name="pip-${ROUTE_SERVER_NAME:-rs-adaptive}"
    if az network public-ip show --name "${rs_pip_name}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        az network public-ip delete \
            --name "${rs_pip_name}" \
            --resource-group "${RESOURCE_GROUP}" \
            || log_warning "Failed to delete Route Server public IP: ${rs_pip_name}"
        log_success "Deleted Route Server public IP: ${rs_pip_name}"
    else
        log_info "Route Server public IP not found or already deleted"
    fi
    
    log_success "Route Server cleanup completed"
}

# Remove Azure Firewall
remove_firewall() {
    log_info "Removing Azure Firewall..."
    
    # Check if Firewall exists
    if [ ! -z "${FIREWALL_NAME:-}" ] && az network firewall show --name "${FIREWALL_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Deleting Azure Firewall: ${FIREWALL_NAME}"
        az network firewall delete \
            --name "${FIREWALL_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            || log_warning "Failed to delete Azure Firewall: ${FIREWALL_NAME}"
        log_success "Deleted Azure Firewall: ${FIREWALL_NAME}"
    else
        log_info "Azure Firewall not found or already deleted"
    fi
    
    # Delete Firewall public IP
    local fw_pip_name="pip-${FIREWALL_NAME:-fw-adaptive}"
    if az network public-ip show --name "${fw_pip_name}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        az network public-ip delete \
            --name "${fw_pip_name}" \
            --resource-group "${RESOURCE_GROUP}" \
            || log_warning "Failed to delete Firewall public IP: ${fw_pip_name}"
        log_success "Deleted Firewall public IP: ${fw_pip_name}"
    else
        log_info "Firewall public IP not found or already deleted"
    fi
    
    log_success "Azure Firewall cleanup completed"
}

# Remove VNet peerings and virtual networks
remove_virtual_networks() {
    log_info "Removing virtual network peerings and VNets..."
    
    # Delete VNet peerings first
    if [ ! -z "${HUB_VNET_NAME:-}" ] && [ ! -z "${SPOKE_VNET_NAME:-}" ]; then
        # Delete hub-to-spoke peering
        if az network vnet peering show --name "hub-to-spoke" --resource-group "${RESOURCE_GROUP}" --vnet-name "${HUB_VNET_NAME}" &> /dev/null; then
            az network vnet peering delete \
                --name "hub-to-spoke" \
                --resource-group "${RESOURCE_GROUP}" \
                --vnet-name "${HUB_VNET_NAME}" \
                || log_warning "Failed to delete hub-to-spoke peering"
            log_success "Deleted hub-to-spoke peering"
        fi
        
        # Delete spoke-to-hub peering
        if az network vnet peering show --name "spoke-to-hub" --resource-group "${RESOURCE_GROUP}" --vnet-name "${SPOKE_VNET_NAME}" &> /dev/null; then
            az network vnet peering delete \
                --name "spoke-to-hub" \
                --resource-group "${RESOURCE_GROUP}" \
                --vnet-name "${SPOKE_VNET_NAME}" \
                || log_warning "Failed to delete spoke-to-hub peering"
            log_success "Deleted spoke-to-hub peering"
        fi
    else
        log_info "VNet names not available, checking for existing peerings..."
        # Try to find and delete any peerings in the resource group
        local vnets=$(az network vnet list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv 2>/dev/null || echo "")
        for vnet in $vnets; do
            local peerings=$(az network vnet peering list --resource-group "${RESOURCE_GROUP}" --vnet-name "$vnet" --query "[].name" -o tsv 2>/dev/null || echo "")
            for peering in $peerings; do
                az network vnet peering delete \
                    --name "$peering" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --vnet-name "$vnet" \
                    || log_warning "Failed to delete peering: $peering"
                log_success "Deleted peering: $peering"
            done
        done
    fi
    
    # Delete virtual networks
    local all_vnets=$(az network vnet list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv 2>/dev/null || echo "")
    if [ ! -z "$all_vnets" ]; then
        for vnet in $all_vnets; do
            log_info "Deleting VNet: $vnet"
            az network vnet delete \
                --name "$vnet" \
                --resource-group "${RESOURCE_GROUP}" \
                || log_warning "Failed to delete VNet: $vnet"
            log_success "Deleted VNet: $vnet"
        done
    else
        log_info "No virtual networks found or already deleted"
    fi
    
    log_success "Virtual networks cleanup completed"
}

# Remove DDoS Protection Plan
remove_ddos_protection() {
    log_info "Removing DDoS Protection Plan..."
    
    # Check if DDoS Protection Plan exists
    if [ ! -z "${DDOS_PLAN_NAME:-}" ] && az network ddos-protection show --name "${DDOS_PLAN_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Deleting DDoS Protection Plan: ${DDOS_PLAN_NAME}"
        az network ddos-protection delete \
            --name "${DDOS_PLAN_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            || log_warning "Failed to delete DDoS Protection Plan: ${DDOS_PLAN_NAME}"
        log_success "Deleted DDoS Protection Plan: ${DDOS_PLAN_NAME}"
    else
        log_info "DDoS Protection Plan not found or already deleted"
    fi
    
    log_success "DDoS Protection cleanup completed"
}

# Remove Log Analytics and storage
remove_supporting_resources() {
    log_info "Removing Log Analytics workspace and storage accounts..."
    
    # Delete Log Analytics workspace
    if [ ! -z "${LOG_ANALYTICS_NAME:-}" ] && az monitor log-analytics workspace show --name "${LOG_ANALYTICS_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        az monitor log-analytics workspace delete \
            --name "${LOG_ANALYTICS_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            || log_warning "Failed to delete Log Analytics workspace: ${LOG_ANALYTICS_NAME}"
        log_success "Deleted Log Analytics workspace: ${LOG_ANALYTICS_NAME}"
    else
        log_info "Log Analytics workspace not found or already deleted"
    fi
    
    # Delete storage accounts (find accounts with "flowlogs" in name)
    local storage_accounts=$(az storage account list --resource-group "${RESOURCE_GROUP}" --query "[?contains(name,'flowlogs')].name" -o tsv 2>/dev/null || echo "")
    if [ ! -z "$storage_accounts" ]; then
        for sa in $storage_accounts; do
            az storage account delete \
                --name "$sa" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                || log_warning "Failed to delete storage account: $sa"
            log_success "Deleted storage account: $sa"
        done
    else
        log_info "No flow logs storage accounts found or already deleted"
    fi
    
    log_success "Supporting resources cleanup completed"
}

# Remove any remaining public IPs
remove_remaining_public_ips() {
    log_info "Removing any remaining public IP addresses..."
    
    local public_ips=$(az network public-ip list --resource-group "${RESOURCE_GROUP}" --query "[].name" -o tsv 2>/dev/null || echo "")
    if [ ! -z "$public_ips" ]; then
        for pip in $public_ips; do
            az network public-ip delete \
                --name "$pip" \
                --resource-group "${RESOURCE_GROUP}" \
                || log_warning "Failed to delete public IP: $pip"
            log_success "Deleted public IP: $pip"
        done
    else
        log_info "No public IP addresses found or already deleted"
    fi
    
    log_success "Public IP cleanup completed"
}

# Remove resource group
remove_resource_group() {
    log_info "Removing resource group and all remaining resources..."
    
    # Final confirmation for resource group deletion
    if [ "${FORCE_DELETE:-false}" != "true" ]; then
        echo ""
        log_warning "Final confirmation: Delete resource group '${RESOURCE_GROUP}' and ALL remaining resources?"
        read -p "Type 'DELETE' to confirm: " final_confirmation
        if [ "$final_confirmation" != "DELETE" ]; then
            log_info "Resource group deletion cancelled. Some resources may still exist."
            exit 0
        fi
    fi
    
    # Delete resource group (this will delete any remaining resources)
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        || error_exit "Failed to initiate resource group deletion"
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Note: Complete deletion may take several minutes to finish"
}

# Clean up environment file
cleanup_environment() {
    if [ -f ".env" ]; then
        rm -f ".env"
        log_success "Cleaned up .env file"
    fi
}

# Display cleanup summary
display_summary() {
    echo ""
    log_info "Cleanup Summary"
    echo "==================="
    log_success "Resource cleanup completed successfully!"
    echo ""
    log_info "The following resources have been removed:"
    echo "- Alert rules and action groups"
    echo "- Network Watcher flow logs"
    echo "- Azure Route Server and public IP"
    echo "- Azure Firewall and public IP"
    echo "- Virtual network peerings"
    echo "- Virtual networks and subnets"
    echo "- DDoS Protection Plan"
    echo "- Log Analytics workspace"
    echo "- Storage accounts"
    echo "- Any remaining public IP addresses"
    echo "- Resource group: ${RESOURCE_GROUP}"
    echo ""
    log_warning "Please verify in the Azure portal that all resources have been deleted."
    log_info "If any resources remain, they may need to be deleted manually."
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Adaptive Network Security infrastructure"
    
    load_environment
    check_prerequisites
    confirm_cleanup
    
    # Remove resources in dependency order
    remove_monitoring_alerts
    remove_flow_logs
    remove_route_server
    remove_firewall
    remove_virtual_networks
    remove_ddos_protection
    remove_supporting_resources
    remove_remaining_public_ips
    remove_resource_group
    
    cleanup_environment
    display_summary
    
    log_success "Cleanup completed successfully!"
}

# Run main function
main "$@"