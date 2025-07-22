#!/bin/bash

# Azure IoT Device Update and Update Manager Cleanup Script
# Recipe: Unified Edge-to-Cloud Security Updates with IoT Device Update and Update Manager
# Version: 1.0
# Last Updated: 2025-07-12

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

# Function to confirm destructive action
confirm_deletion() {
    local resource_name="$1"
    local force_delete="${FORCE_DELETE:-false}"
    
    if [[ "$force_delete" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warn "You are about to delete $resource_name and all associated resources."
    warn "This action is IRREVERSIBLE and will result in data loss."
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
}

# Function to check if Azure CLI is installed and user is logged in
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    local account_name=$(az account show --query name --output tsv)
    local subscription_id=$(az account show --query id --output tsv)
    log "Logged in to Azure account: $account_name"
    log "Using subscription: $subscription_id"
    
    log "Prerequisites check completed successfully"
}

# Function to load environment variables or prompt for resource group
setup_environment() {
    log "Setting up environment variables..."
    
    # If RESOURCE_GROUP is not set, try to detect or prompt
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        # Try to find IoT update resource groups
        local rg_candidates=$(az group list --query "[?tags.purpose=='iot-updates'].name" --output tsv)
        
        if [[ -n "$rg_candidates" ]]; then
            echo "Found the following IoT update resource groups:"
            echo "$rg_candidates"
            echo ""
            read -p "Enter the resource group name to delete: " -r RESOURCE_GROUP
        else
            read -p "Enter the resource group name to delete: " -r RESOURCE_GROUP
        fi
        
        if [[ -z "$RESOURCE_GROUP" ]]; then
            error "Resource group name is required"
            exit 1
        fi
    fi
    
    export RESOURCE_GROUP
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group '$RESOURCE_GROUP' does not exist"
        exit 1
    fi
    
    log "Using resource group: $RESOURCE_GROUP"
}

# Function to remove Logic App workflow and monitoring resources
cleanup_orchestration_monitoring() {
    log "Cleaning up orchestration and monitoring resources..."
    
    local workflow_name="update-orchestration-workflow"
    local alert_name="DeviceUpdateFailures"
    local dashboard_name="IoT-Updates-Dashboard"
    
    # Delete Logic App workflow
    if az logic workflow show --name "$workflow_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting Logic App workflow: $workflow_name"
        az logic workflow delete \
            --name "$workflow_name" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none || warn "Failed to delete Logic App workflow"
        log "✅ Logic App workflow deleted"
    else
        info "Logic App workflow not found, skipping deletion"
    fi
    
    # Delete monitoring alert
    if az monitor metrics alert show --name "$alert_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting alert rule: $alert_name"
        az monitor metrics alert delete \
            --name "$alert_name" \
            --resource-group "$RESOURCE_GROUP" \
            --output none || warn "Failed to delete alert rule"
        log "✅ Alert rule deleted"
    else
        info "Alert rule not found, skipping deletion"
    fi
    
    # Delete monitoring dashboard
    if az monitor dashboard show --resource-group "$RESOURCE_GROUP" --name "$dashboard_name" &> /dev/null; then
        log "Deleting monitoring dashboard: $dashboard_name"
        az monitor dashboard delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$dashboard_name" \
            --yes \
            --output none || warn "Failed to delete monitoring dashboard"
        log "✅ Monitoring dashboard deleted"
    else
        info "Monitoring dashboard not found, skipping deletion"
    fi
}

# Function to remove device identities and simulated devices
cleanup_device_simulation() {
    log "Cleaning up device simulation resources..."
    
    local device_id="sim-device-001"
    
    # Get IoT Hub name from resource group
    local iot_hub_name=$(az iot hub list --resource-group "$RESOURCE_GROUP" --query "[0].name" --output tsv)
    
    if [[ -n "$iot_hub_name" && "$iot_hub_name" != "null" ]]; then
        # Delete device identity
        if az iot hub device-identity show \
            --hub-name "$iot_hub_name" \
            --device-id "$device_id" \
            --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log "Deleting device identity: $device_id"
            az iot hub device-identity delete \
                --hub-name "$iot_hub_name" \
                --device-id "$device_id" \
                --resource-group "$RESOURCE_GROUP" \
                --output none || warn "Failed to delete device identity"
            log "✅ Device identity deleted"
        else
            info "Device identity not found, skipping deletion"
        fi
    else
        info "IoT Hub not found, skipping device cleanup"
    fi
    
    # Clean up local update package files
    local update_dir="$HOME/device-updates"
    if [[ -d "$update_dir" ]]; then
        log "Cleaning up local update package files..."
        rm -rf "$update_dir" || warn "Failed to remove local update files"
        log "✅ Local update package files removed"
    fi
}

# Function to remove Azure IoT resources
cleanup_iot_resources() {
    log "Cleaning up Azure IoT resources..."
    
    # Get Device Update account names
    local device_update_accounts=$(az iot du account list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    if [[ -n "$device_update_accounts" ]]; then
        for account in $device_update_accounts; do
            log "Processing Device Update account: $account"
            
            # Get instances for this account
            local instances=$(az iot du instance list \
                --account "$account" \
                --resource-group "$RESOURCE_GROUP" \
                --query "[].name" --output tsv)
            
            # Delete instances first
            if [[ -n "$instances" ]]; then
                for instance in $instances; do
                    log "Deleting Device Update instance: $instance"
                    az iot du instance delete \
                        --account "$account" \
                        --instance "$instance" \
                        --resource-group "$RESOURCE_GROUP" \
                        --yes \
                        --output none || warn "Failed to delete Device Update instance: $instance"
                    log "✅ Device Update instance deleted: $instance"
                done
            fi
            
            # Delete the account
            log "Deleting Device Update account: $account"
            az iot du account delete \
                --account "$account" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none || warn "Failed to delete Device Update account: $account"
            log "✅ Device Update account deleted: $account"
        done
    else
        info "No Device Update accounts found, skipping deletion"
    fi
    
    # Delete IoT Hub
    local iot_hubs=$(az iot hub list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    if [[ -n "$iot_hubs" ]]; then
        for hub in $iot_hubs; do
            log "Deleting IoT Hub: $hub"
            az iot hub delete \
                --name "$hub" \
                --resource-group "$RESOURCE_GROUP" \
                --output none || warn "Failed to delete IoT Hub: $hub"
            log "✅ IoT Hub deleted: $hub"
        done
    else
        info "No IoT Hubs found, skipping deletion"
    fi
}

# Function to remove infrastructure resources
cleanup_infrastructure_resources() {
    log "Cleaning up infrastructure resources..."
    
    # Delete VMs
    local vms=$(az vm list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    if [[ -n "$vms" ]]; then
        for vm in $vms; do
            log "Deleting VM: $vm"
            az vm delete \
                --name "$vm" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none || warn "Failed to delete VM: $vm"
            log "✅ VM deleted: $vm"
        done
    else
        info "No VMs found, skipping deletion"
    fi
    
    # Delete Network Security Groups
    local nsgs=$(az network nsg list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    if [[ -n "$nsgs" ]]; then
        for nsg in $nsgs; do
            log "Deleting Network Security Group: $nsg"
            az network nsg delete \
                --name "$nsg" \
                --resource-group "$RESOURCE_GROUP" \
                --output none || warn "Failed to delete NSG: $nsg"
        done
        log "✅ Network Security Groups deleted"
    fi
    
    # Delete Public IPs
    local public_ips=$(az network public-ip list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    if [[ -n "$public_ips" ]]; then
        for ip in $public_ips; do
            log "Deleting Public IP: $ip"
            az network public-ip delete \
                --name "$ip" \
                --resource-group "$RESOURCE_GROUP" \
                --output none || warn "Failed to delete Public IP: $ip"
        done
        log "✅ Public IPs deleted"
    fi
    
    # Delete Network Interfaces
    local nics=$(az network nic list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    if [[ -n "$nics" ]]; then
        for nic in $nics; do
            log "Deleting Network Interface: $nic"
            az network nic delete \
                --name "$nic" \
                --resource-group "$RESOURCE_GROUP" \
                --output none || warn "Failed to delete NIC: $nic"
        done
        log "✅ Network Interfaces deleted"
    fi
    
    # Delete Virtual Networks
    local vnets=$(az network vnet list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    if [[ -n "$vnets" ]]; then
        for vnet in $vnets; do
            log "Deleting Virtual Network: $vnet"
            az network vnet delete \
                --name "$vnet" \
                --resource-group "$RESOURCE_GROUP" \
                --output none || warn "Failed to delete VNet: $vnet"
        done
        log "✅ Virtual Networks deleted"
    fi
    
    # Delete Storage Accounts
    local storage_accounts=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    if [[ -n "$storage_accounts" ]]; then
        for storage in $storage_accounts; do
            log "Deleting Storage Account: $storage"
            az storage account delete \
                --name "$storage" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none || warn "Failed to delete Storage Account: $storage"
            log "✅ Storage Account deleted: $storage"
        done
    else
        info "No Storage Accounts found, skipping deletion"
    fi
    
    # Delete Log Analytics Workspaces
    local workspaces=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
    
    if [[ -n "$workspaces" ]]; then
        for workspace in $workspaces; do
            log "Deleting Log Analytics Workspace: $workspace"
            az monitor log-analytics workspace delete \
                --resource-group "$RESOURCE_GROUP" \
                --workspace-name "$workspace" \
                --yes \
                --output none || warn "Failed to delete Log Analytics Workspace: $workspace"
            log "✅ Log Analytics Workspace deleted: $workspace"
        done
    else
        info "No Log Analytics Workspaces found, skipping deletion"
    fi
}

# Function to wait for resource deletion completion
wait_for_deletions() {
    log "Waiting for resource deletions to complete..."
    
    local max_wait=300  # 5 minutes
    local wait_time=0
    local check_interval=30
    
    while [[ $wait_time -lt $max_wait ]]; do
        local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv)
        
        if [[ "$remaining_resources" == "0" ]]; then
            log "✅ All resources have been deleted"
            return 0
        fi
        
        info "Waiting for remaining resources to be deleted... ($remaining_resources remaining)"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    warn "Some resources may still be deleting. Check the Azure portal for completion status."
}

# Function to remove resource group
cleanup_resource_group() {
    log "Deleting resource group: $RESOURCE_GROUP"
    
    # Confirm deletion of the entire resource group
    confirm_deletion "resource group '$RESOURCE_GROUP'"
    
    # Delete resource group and all remaining resources
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none
    
    log "✅ Resource group deletion initiated: $RESOURCE_GROUP"
    log "Note: Complete deletion may take several minutes"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup completed successfully!"
    echo ""
    echo "=========================================="
    echo "         CLEANUP SUMMARY"
    echo "=========================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo ""
    echo "Cleaned up resources:"
    echo "✅ Logic App workflows and monitoring"
    echo "✅ Device identities and simulation"
    echo "✅ Azure IoT Device Update resources"
    echo "✅ Virtual machines and networking"
    echo "✅ Storage accounts"
    echo "✅ Log Analytics workspaces"
    echo "✅ Resource group deletion initiated"
    echo ""
    echo "Notes:"
    echo "- Resource group deletion may take several minutes to complete"
    echo "- Check the Azure portal to verify all resources are removed"
    echo "- Local files in ~/device-updates have been removed"
    echo ""
    echo "If any resources remain, you can manually delete them through"
    echo "the Azure portal or by running specific deletion commands."
    echo "=========================================="
}

# Function to handle individual resource cleanup (alternative to full deletion)
cleanup_individual_resources() {
    log "Starting individual resource cleanup..."
    
    cleanup_orchestration_monitoring
    cleanup_device_simulation
    cleanup_iot_resources
    cleanup_infrastructure_resources
    wait_for_deletions
    
    log "Individual resource cleanup completed"
}

# Main cleanup function
main() {
    local cleanup_type="${1:-full}"
    
    log "Starting Azure IoT Device Update and Update Manager cleanup..."
    
    check_prerequisites
    setup_environment
    
    case "$cleanup_type" in
        "full")
            cleanup_resource_group
            ;;
        "resources")
            cleanup_individual_resources
            ;;
        *)
            error "Invalid cleanup type. Use 'full' or 'resources'"
            exit 1
            ;;
    esac
    
    display_cleanup_summary
    
    log "Cleanup completed successfully!"
}

# Script usage information
usage() {
    echo "Usage: $0 [cleanup_type]"
    echo ""
    echo "Cleanup types:"
    echo "  full       Delete the entire resource group (default)"
    echo "  resources  Delete individual resources but keep the resource group"
    echo ""
    echo "Environment variables:"
    echo "  RESOURCE_GROUP    Resource group to clean up"
    echo "  FORCE_DELETE      Skip confirmation prompts (true/false)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Delete entire resource group"
    echo "  $0 full               # Delete entire resource group"
    echo "  $0 resources          # Delete individual resources"
    echo "  FORCE_DELETE=true $0  # Skip confirmation prompts"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        usage
        exit 0
    fi
    
    main "${1:-full}"
fi