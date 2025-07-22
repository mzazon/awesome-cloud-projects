#!/bin/bash

#
# destroy.sh - Destroy Azure Virtual Desktop Cost Optimization Infrastructure
#
# This script safely removes all resources created by the AVD cost optimization solution
# including AVD workspaces, host pools, VM scale sets, automation components, and storage.
# Resources are deleted in reverse dependency order to avoid conflicts.
#
# Usage: ./destroy.sh [--force] [--keep-storage] [--debug]
#

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEBUG_MODE=false
FORCE_DELETE=false
KEEP_STORAGE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) if $DEBUG_MODE; then echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"; fi ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log ERROR "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log ERROR "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log INFO "Prerequisites check passed ✅"
}

# Function to load environment variables
load_environment() {
    log INFO "Loading environment variables..."
    
    # Try to load from environment or set defaults
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-avd-cost-optimization}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log WARN "Resource group '$RESOURCE_GROUP' not found. It may have already been deleted."
        log INFO "Available resource groups:"
        az group list --query "[].name" --output table
        
        if ! $FORCE_DELETE; then
            read -p "Enter the correct resource group name (or press Enter to exit): " input_rg
            if [ -n "$input_rg" ]; then
                export RESOURCE_GROUP="$input_rg"
            else
                log INFO "Exiting cleanup process."
                exit 0
            fi
        else
            log WARN "Force mode enabled, but resource group not found. Nothing to clean up."
            exit 0
        fi
    fi
    
    # Try to detect resource names from existing resources
    log INFO "Detecting existing resources in $RESOURCE_GROUP..."
    
    # Detect AVD workspace
    AVD_WORKSPACE=$(az desktopvirtualization workspace list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Detect host pool
    HOST_POOL_NAME=$(az desktopvirtualization hostpool list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Detect VM scale set
    VMSS_NAME=$(az vmss list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Detect storage account
    STORAGE_ACCOUNT=$(az storage account list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Detect virtual network
    VNET_NAME=$(az network vnet list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Detect Logic App
    LOGIC_APP_NAME=$(az logic workflow list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Detect Function App
    FUNCTION_APP_NAME=$(az functionapp list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Detect auto-scaling settings
    AUTOSCALE_NAME=$(az monitor autoscale list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Detect Log Analytics workspace
    LAW_NAME=$(az monitor log-analytics workspace list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    # Detect budget
    BUDGET_NAME=$(az consumption budget list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].name" --output tsv 2>/dev/null || echo "")
    
    log INFO "Detected resources:"
    log INFO "  Resource Group: $RESOURCE_GROUP"
    log INFO "  AVD Workspace: ${AVD_WORKSPACE:-'Not found'}"
    log INFO "  Host Pool: ${HOST_POOL_NAME:-'Not found'}"
    log INFO "  VM Scale Set: ${VMSS_NAME:-'Not found'}"
    log INFO "  Virtual Network: ${VNET_NAME:-'Not found'}"
    log INFO "  Storage Account: ${STORAGE_ACCOUNT:-'Not found'}"
    log INFO "  Logic App: ${LOGIC_APP_NAME:-'Not found'}"
    log INFO "  Function App: ${FUNCTION_APP_NAME:-'Not found'}"
    log INFO "  Auto-scaling: ${AUTOSCALE_NAME:-'Not found'}"
    log INFO "  Log Analytics: ${LAW_NAME:-'Not found'}"
    log INFO "  Budget: ${BUDGET_NAME:-'Not found'}"
}

# Function to confirm deletion
confirm_deletion() {
    if $FORCE_DELETE; then
        log WARN "Force mode enabled - skipping confirmation prompts"
        return 0
    fi
    
    log WARN "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log WARN "This will permanently delete ALL resources in the resource group: $RESOURCE_GROUP"
    log WARN "This action cannot be undone!"
    echo ""
    
    # List all resources that will be deleted
    log INFO "Resources to be deleted:"
    az resource list --resource-group "$RESOURCE_GROUP" --output table 2>/dev/null || log WARN "Unable to list resources"
    
    echo ""
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log INFO "Deletion cancelled by user."
        exit 0
    fi
    
    log WARN "Proceeding with resource deletion..."
}

# Function to delete automation resources
delete_automation_resources() {
    log INFO "Deleting automation resources..."
    
    # Delete Function App
    if [ -n "$FUNCTION_APP_NAME" ]; then
        log INFO "Deleting Function App: $FUNCTION_APP_NAME"
        if az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            az functionapp delete \
                --name "$FUNCTION_APP_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --output none
            log INFO "✅ Function App deleted: $FUNCTION_APP_NAME"
        else
            log DEBUG "Function App $FUNCTION_APP_NAME not found, skipping"
        fi
    fi
    
    # Delete Logic App
    if [ -n "$LOGIC_APP_NAME" ]; then
        log INFO "Deleting Logic App: $LOGIC_APP_NAME"
        if az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            az logic workflow delete \
                --name "$LOGIC_APP_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none
            log INFO "✅ Logic App deleted: $LOGIC_APP_NAME"
        else
            log DEBUG "Logic App $LOGIC_APP_NAME not found, skipping"
        fi
    fi
    
    log INFO "Automation resources cleanup completed"
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log INFO "Deleting monitoring and auto-scaling resources..."
    
    # Delete auto-scaling settings
    if [ -n "$AUTOSCALE_NAME" ]; then
        log INFO "Deleting auto-scaling settings: $AUTOSCALE_NAME"
        if az monitor autoscale show --name "$AUTOSCALE_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            az monitor autoscale delete \
                --name "$AUTOSCALE_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --output none
            log INFO "✅ Auto-scaling settings deleted: $AUTOSCALE_NAME"
        else
            log DEBUG "Auto-scaling settings $AUTOSCALE_NAME not found, skipping"
        fi
    fi
    
    # Delete Log Analytics workspace
    if [ -n "$LAW_NAME" ]; then
        log INFO "Deleting Log Analytics workspace: $LAW_NAME"
        if az monitor log-analytics workspace show --workspace-name "$LAW_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            az monitor log-analytics workspace delete \
                --workspace-name "$LAW_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --force true \
                --output none
            log INFO "✅ Log Analytics workspace deleted: $LAW_NAME"
        else
            log DEBUG "Log Analytics workspace $LAW_NAME not found, skipping"
        fi
    fi
    
    log INFO "Monitoring resources cleanup completed"
}

# Function to delete compute resources
delete_compute_resources() {
    log INFO "Deleting compute resources..."
    
    # Delete VM scale set (this will also remove associated VMs)
    if [ -n "$VMSS_NAME" ]; then
        log INFO "Deleting VM Scale Set: $VMSS_NAME"
        if az vmss show --name "$VMSS_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            # Check if scale set has instances and scale down first
            local instance_count=$(az vmss show \
                --name "$VMSS_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --query "sku.capacity" --output tsv)
            
            if [ "$instance_count" -gt 0 ]; then
                log INFO "Scaling down VM Scale Set to 0 instances before deletion..."
                az vmss scale \
                    --name "$VMSS_NAME" \
                    --resource-group "$RESOURCE_GROUP" \
                    --new-capacity 0 \
                    --output none
                
                # Wait for scale down to complete
                log INFO "Waiting for scale down to complete..."
                sleep 60
            fi
            
            az vmss delete \
                --name "$VMSS_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --output none
            log INFO "✅ VM Scale Set deleted: $VMSS_NAME"
        else
            log DEBUG "VM Scale Set $VMSS_NAME not found, skipping"
        fi
    fi
    
    log INFO "Compute resources cleanup completed"
}

# Function to delete networking resources
delete_networking_resources() {
    log INFO "Deleting networking resources..."
    
    # Delete virtual network (this will also delete subnets)
    if [ -n "$VNET_NAME" ]; then
        log INFO "Deleting virtual network: $VNET_NAME"
        if az network vnet show --name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            az network vnet delete \
                --name "$VNET_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --output none
            log INFO "✅ Virtual network deleted: $VNET_NAME"
        else
            log DEBUG "Virtual network $VNET_NAME not found, skipping"
        fi
    fi
    
    log INFO "Networking resources cleanup completed"
}

# Function to delete AVD resources
delete_avd_resources() {
    log INFO "Deleting Azure Virtual Desktop resources..."
    
    # Delete application groups first (if they exist)
    local app_groups=$(az desktopvirtualization applicationgroup list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" --output tsv 2>/dev/null || echo "")
    
    if [ -n "$app_groups" ]; then
        for app_group in $app_groups; do
            log INFO "Deleting application group: $app_group"
            az desktopvirtualization applicationgroup delete \
                --name "$app_group" \
                --resource-group "$RESOURCE_GROUP" \
                --output none
            log INFO "✅ Application group deleted: $app_group"
        done
    fi
    
    # Delete host pool
    if [ -n "$HOST_POOL_NAME" ]; then
        log INFO "Deleting host pool: $HOST_POOL_NAME"
        if az desktopvirtualization hostpool show --name "$HOST_POOL_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            az desktopvirtualization hostpool delete \
                --name "$HOST_POOL_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --output none
            log INFO "✅ Host pool deleted: $HOST_POOL_NAME"
        else
            log DEBUG "Host pool $HOST_POOL_NAME not found, skipping"
        fi
    fi
    
    # Delete AVD workspace
    if [ -n "$AVD_WORKSPACE" ]; then
        log INFO "Deleting AVD workspace: $AVD_WORKSPACE"
        if az desktopvirtualization workspace show --name "$AVD_WORKSPACE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            az desktopvirtualization workspace delete \
                --name "$AVD_WORKSPACE" \
                --resource-group "$RESOURCE_GROUP" \
                --output none
            log INFO "✅ AVD workspace deleted: $AVD_WORKSPACE"
        else
            log DEBUG "AVD workspace $AVD_WORKSPACE not found, skipping"
        fi
    fi
    
    log INFO "AVD resources cleanup completed"
}

# Function to delete cost management resources
delete_cost_management() {
    log INFO "Deleting cost management resources..."
    
    # Delete budget
    if [ -n "$BUDGET_NAME" ]; then
        log INFO "Deleting budget: $BUDGET_NAME"
        if az consumption budget show --budget-name "$BUDGET_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            az consumption budget delete \
                --budget-name "$BUDGET_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --output none
            log INFO "✅ Budget deleted: $BUDGET_NAME"
        else
            log DEBUG "Budget $BUDGET_NAME not found, skipping"
        fi
    fi
    
    log INFO "Cost management resources cleanup completed"
}

# Function to delete storage resources
delete_storage_resources() {
    if $KEEP_STORAGE; then
        log INFO "Keeping storage resources as requested"
        return 0
    fi
    
    log INFO "Deleting storage resources..."
    
    # Delete storage containers first
    if [ -n "$STORAGE_ACCOUNT" ]; then
        log INFO "Deleting storage containers in: $STORAGE_ACCOUNT"
        if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
            # Delete cost-analysis container if it exists
            if az storage container show --name "cost-analysis" --account-name "$STORAGE_ACCOUNT" &>/dev/null; then
                az storage container delete \
                    --name "cost-analysis" \
                    --account-name "$STORAGE_ACCOUNT" \
                    --output none
                log DEBUG "Cost-analysis container deleted"
            fi
            
            # Delete storage account
            log INFO "Deleting storage account: $STORAGE_ACCOUNT"
            az storage account delete \
                --name "$STORAGE_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --output none
            log INFO "✅ Storage account deleted: $STORAGE_ACCOUNT"
        else
            log DEBUG "Storage account $STORAGE_ACCOUNT not found, skipping"
        fi
    fi
    
    log INFO "Storage resources cleanup completed"
}

# Function to delete remaining resources and resource group
delete_resource_group() {
    log INFO "Performing final cleanup..."
    
    # List any remaining resources
    local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")
    
    if [ "$remaining_resources" -gt 0 ]; then
        log WARN "Found $remaining_resources remaining resources in resource group"
        log INFO "Remaining resources:"
        az resource list --resource-group "$RESOURCE_GROUP" --output table 2>/dev/null || log WARN "Unable to list remaining resources"
        
        if ! $FORCE_DELETE; then
            read -p "Delete resource group and all remaining resources? (y/N): " confirm_rg
            if [[ ! "$confirm_rg" =~ ^[Yy]$ ]]; then
                log INFO "Keeping resource group and remaining resources"
                return 0
            fi
        fi
    fi
    
    # Delete the entire resource group
    log INFO "Deleting resource group: $RESOURCE_GROUP"
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none
    
    log INFO "✅ Resource group deletion initiated: $RESOURCE_GROUP"
    log INFO "Note: Complete deletion may take several minutes to finish"
}

# Function to validate cleanup
validate_cleanup() {
    log INFO "Validating cleanup..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        local remaining_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "unknown")
        if [ "$remaining_count" = "0" ]; then
            log INFO "✅ Resource group exists but is empty"
        else
            log WARN "⚠️  Resource group exists with $remaining_count remaining resources"
        fi
    else
        log INFO "✅ Resource group has been deleted"
    fi
    
    log INFO "Cleanup validation completed"
}

# Function to display cleanup summary
display_summary() {
    log INFO "Cleanup Summary"
    log INFO "==============="
    log INFO "Cleaned up resource group: $RESOURCE_GROUP"
    log INFO "Deleted resources:"
    [ -n "$FUNCTION_APP_NAME" ] && log INFO "  ✅ Function App: $FUNCTION_APP_NAME"
    [ -n "$LOGIC_APP_NAME" ] && log INFO "  ✅ Logic App: $LOGIC_APP_NAME"
    [ -n "$AUTOSCALE_NAME" ] && log INFO "  ✅ Auto-scaling: $AUTOSCALE_NAME"
    [ -n "$LAW_NAME" ] && log INFO "  ✅ Log Analytics: $LAW_NAME"
    [ -n "$VMSS_NAME" ] && log INFO "  ✅ VM Scale Set: $VMSS_NAME"
    [ -n "$VNET_NAME" ] && log INFO "  ✅ Virtual Network: $VNET_NAME"
    [ -n "$HOST_POOL_NAME" ] && log INFO "  ✅ Host Pool: $HOST_POOL_NAME"
    [ -n "$AVD_WORKSPACE" ] && log INFO "  ✅ AVD Workspace: $AVD_WORKSPACE"
    [ -n "$BUDGET_NAME" ] && log INFO "  ✅ Budget: $BUDGET_NAME"
    
    if $KEEP_STORAGE; then
        [ -n "$STORAGE_ACCOUNT" ] && log INFO "  🔄 Storage Account: $STORAGE_ACCOUNT (preserved)"
    else
        [ -n "$STORAGE_ACCOUNT" ] && log INFO "  ✅ Storage Account: $STORAGE_ACCOUNT"
    fi
    
    log INFO ""
    log INFO "Cleanup process completed successfully!"
    log INFO "Resource group deletion may continue in the background."
}

# Main cleanup function
main() {
    log INFO "Starting Azure Virtual Desktop Cost Optimization cleanup"
    log INFO "Log file: $LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE=true
                log WARN "Force mode enabled - no confirmation prompts"
                shift
                ;;
            --keep-storage)
                KEEP_STORAGE=true
                log INFO "Storage preservation mode enabled"
                shift
                ;;
            --debug)
                DEBUG_MODE=true
                log INFO "Debug mode enabled"
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [--force] [--keep-storage] [--debug]"
                echo "  --force         Skip confirmation prompts"
                echo "  --keep-storage  Preserve storage account and data"
                echo "  --debug         Enable debug logging"
                exit 0
                ;;
            *)
                log ERROR "Unknown parameter: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute cleanup steps
    check_prerequisites
    load_environment
    confirm_deletion
    
    # Delete resources in reverse dependency order
    delete_automation_resources
    delete_monitoring_resources
    delete_compute_resources
    delete_networking_resources
    delete_avd_resources
    delete_cost_management
    delete_storage_resources
    delete_resource_group
    
    # Validate and summarize
    validate_cleanup
    display_summary
    
    log INFO "🧹 Azure Virtual Desktop Cost Optimization cleanup completed!"
}

# Trap errors and cleanup
trap 'log ERROR "Script failed on line $LINENO"' ERR

# Initialize log file
echo "Azure Virtual Desktop Cost Optimization Cleanup Log" > "$LOG_FILE"
echo "Started: $(date)" >> "$LOG_FILE"
echo "=========================================" >> "$LOG_FILE"

# Run main function
main "$@"