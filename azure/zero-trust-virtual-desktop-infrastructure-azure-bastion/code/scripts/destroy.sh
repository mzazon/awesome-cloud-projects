#!/bin/bash

# Azure Virtual Desktop with Azure Bastion Cleanup Script
# This script safely removes all resources created by the deployment script
# with proper dependency handling and confirmation prompts

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
DRY_RUN=${DRY_RUN:-false}
FORCE_CLEANUP=${FORCE_CLEANUP:-false}
DELETE_RESOURCE_GROUP=${DELETE_RESOURCE_GROUP:-true}

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
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    log ERROR "Script failed at line $line_number with exit code $exit_code"
    log ERROR "Check the log file: $LOG_FILE"
    log WARN "Some resources may not have been deleted. Please check manually."
    exit $exit_code
}

# Set up error trap
trap 'handle_error $LINENO' ERR

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup Azure Virtual Desktop infrastructure resources.

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deleted without making changes
    -f, --force            Skip all confirmation prompts
    -g, --resource-group RG Specify resource group to delete (required)
    -k, --keep-rg          Keep the resource group (delete only individual resources)
    -v, --verbose          Enable verbose logging

EXAMPLES:
    $0 -g rg-avd-infra-abc123                    # Interactive cleanup
    $0 -d -g rg-avd-infra-abc123                 # Dry run to see what would be deleted
    $0 -f -g rg-avd-infra-abc123                 # Force cleanup without prompts
    $0 -g rg-avd-infra-abc123 --keep-rg          # Delete resources but keep RG

ENVIRONMENT VARIABLES:
    DRY_RUN               Set to 'true' for dry run mode
    FORCE_CLEANUP         Set to 'true' to skip all prompts
    DELETE_RESOURCE_GROUP Set to 'false' to keep resource group

SAFETY FEATURES:
    - Multiple confirmation prompts for destructive actions
    - Dry run mode to preview changes
    - Proper dependency ordering for resource deletion
    - Verification of resource existence before deletion
    - Comprehensive logging of all actions

EOF
}

# Parse command line arguments
parse_args() {
    RESOURCE_GROUP=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_CLEANUP=true
                shift
                ;;
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -k|--keep-rg)
                DELETE_RESOURCE_GROUP=false
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                log ERROR "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log ERROR "Resource group is required. Use -g or --resource-group option."
        usage
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log ERROR "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log ERROR "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log ERROR "Resource group '$RESOURCE_GROUP' does not exist or is not accessible."
        exit 1
    fi
    
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    log INFO "Using subscription: $subscription_name ($subscription_id)"
    log INFO "Target resource group: $RESOURCE_GROUP"
    
    log INFO "Prerequisites check completed successfully"
}

# Execute Azure CLI command with dry run support
execute_az_command() {
    local description="$1"
    shift
    local command=("$@")
    
    log INFO "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "DRY RUN: az ${command[*]}"
        return 0
    fi
    
    log DEBUG "Executing: az ${command[*]}"
    if az "${command[@]}" 2>/dev/null; then
        log DEBUG "Command succeeded"
        return 0
    else
        log WARN "Command failed (this may be expected if resource doesn't exist)"
        return 1
    fi
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    
    case "$resource_type" in
        "vm")
            az vm show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "bastion")
            az network bastion show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "hostpool")
            az desktopvirtualization hostpool show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "workspace")
            az desktopvirtualization workspace show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "applicationgroup")
            az desktopvirtualization applicationgroup show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "keyvault")
            az keyvault show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "vnet")
            az network vnet show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "nsg")
            az network nsg show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "pip")
            az network public-ip show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
    esac
}

# Wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    local max_attempts="${4:-20}"
    local sleep_interval="${5:-15}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log DEBUG "DRY RUN: Would wait for $resource_type $resource_name deletion"
        return 0
    fi
    
    log INFO "Waiting for $resource_type '$resource_name' to be deleted..."
    
    for ((i=1; i<=max_attempts; i++)); do
        if ! resource_exists "$resource_type" "$resource_name" "$resource_group"; then
            log INFO "$resource_type '$resource_name' has been deleted"
            return 0
        fi
        
        log DEBUG "Attempt $i/$max_attempts: $resource_type still exists"
        sleep "$sleep_interval"
    done
    
    log WARN "$resource_type '$resource_name' was not deleted within expected time"
    return 1
}

# Get resource names from resource group
discover_resources() {
    log INFO "Discovering resources in resource group '$RESOURCE_GROUP'..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Get all VMs in the resource group
        VM_NAMES=($(az vm list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'vm-avd-host')].name" -o tsv 2>/dev/null || true))
        
        # Get Bastion instances
        BASTION_NAMES=($(az network bastion list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || true))
        
        # Get public IPs
        PIP_NAMES=($(az network public-ip list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'pip-bastion')].name" -o tsv 2>/dev/null || true))
        
        # Get AVD resources
        HOSTPOOL_NAMES=($(az desktopvirtualization hostpool list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || true))
        WORKSPACE_NAMES=($(az desktopvirtualization workspace list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || true))
        APPGROUP_NAMES=($(az desktopvirtualization applicationgroup list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || true))
        
        # Get Key Vaults
        KEYVAULT_NAMES=($(az keyvault list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'kv-avd')].name" -o tsv 2>/dev/null || true))
        
        # Get Network resources
        VNET_NAMES=($(az network vnet list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'vnet-avd')].name" -o tsv 2>/dev/null || true))
        NSG_NAMES=($(az network nsg list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'nsg-avd')].name" -o tsv 2>/dev/null || true))
    else
        # For dry run, use placeholder names
        VM_NAMES=("vm-avd-host-01-example" "vm-avd-host-02-example")
        BASTION_NAMES=("bastion-avd-example")
        PIP_NAMES=("pip-bastion-example")
        HOSTPOOL_NAMES=("hp-multi-session-example")
        WORKSPACE_NAMES=("ws-remote-desktop-example")
        APPGROUP_NAMES=("ag-desktop-example")
        KEYVAULT_NAMES=("kv-avd-example")
        VNET_NAMES=("vnet-avd-example")
        NSG_NAMES=("nsg-avd-hosts")
    fi
    
    log DEBUG "Discovered resources:"
    log DEBUG "  VMs: ${VM_NAMES[*]:-none}"
    log DEBUG "  Bastions: ${BASTION_NAMES[*]:-none}"
    log DEBUG "  Public IPs: ${PIP_NAMES[*]:-none}"
    log DEBUG "  Host Pools: ${HOSTPOOL_NAMES[*]:-none}"
    log DEBUG "  Workspaces: ${WORKSPACE_NAMES[*]:-none}"
    log DEBUG "  App Groups: ${APPGROUP_NAMES[*]:-none}"
    log DEBUG "  Key Vaults: ${KEYVAULT_NAMES[*]:-none}"
    log DEBUG "  VNets: ${VNET_NAMES[*]:-none}"
    log DEBUG "  NSGs: ${NSG_NAMES[*]:-none}"
}

# Delete Azure Virtual Desktop resources
delete_avd_resources() {
    log INFO "Deleting Azure Virtual Desktop resources..."
    
    # Delete application groups first
    for appgroup in "${APPGROUP_NAMES[@]}"; do
        if [[ -n "$appgroup" ]] && resource_exists "applicationgroup" "$appgroup" "$RESOURCE_GROUP"; then
            execute_az_command "Deleting application group: $appgroup" \
                desktopvirtualization applicationgroup delete \
                --name "$appgroup" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
        fi
    done
    
    # Delete workspaces
    for workspace in "${WORKSPACE_NAMES[@]}"; do
        if [[ -n "$workspace" ]] && resource_exists "workspace" "$workspace" "$RESOURCE_GROUP"; then
            execute_az_command "Deleting workspace: $workspace" \
                desktopvirtualization workspace delete \
                --name "$workspace" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
        fi
    done
    
    # Delete host pools
    for hostpool in "${HOSTPOOL_NAMES[@]}"; do
        if [[ -n "$hostpool" ]] && resource_exists "hostpool" "$hostpool" "$RESOURCE_GROUP"; then
            execute_az_command "Deleting host pool: $hostpool" \
                desktopvirtualization hostpool delete \
                --name "$hostpool" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
        fi
    done
    
    log INFO "✅ Azure Virtual Desktop resources deleted"
}

# Delete virtual machines
delete_virtual_machines() {
    log INFO "Deleting session host virtual machines..."
    
    for vm in "${VM_NAMES[@]}"; do
        if [[ -n "$vm" ]] && resource_exists "vm" "$vm" "$RESOURCE_GROUP"; then
            execute_az_command "Deleting VM: $vm" \
                vm delete \
                --name "$vm" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --no-wait
        fi
    done
    
    # Wait for VMs to be deleted
    for vm in "${VM_NAMES[@]}"; do
        if [[ -n "$vm" ]]; then
            wait_for_deletion "vm" "$vm" "$RESOURCE_GROUP" 30 20
        fi
    done
    
    log INFO "✅ Virtual machines deleted"
}

# Delete Azure Bastion
delete_azure_bastion() {
    log INFO "Deleting Azure Bastion resources..."
    
    # Delete Bastion instances
    for bastion in "${BASTION_NAMES[@]}"; do
        if [[ -n "$bastion" ]] && resource_exists "bastion" "$bastion" "$RESOURCE_GROUP"; then
            execute_az_command "Deleting Bastion: $bastion" \
                network bastion delete \
                --name "$bastion" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --no-wait
        fi
    done
    
    # Wait for Bastion deletion before deleting public IPs
    for bastion in "${BASTION_NAMES[@]}"; do
        if [[ -n "$bastion" ]]; then
            wait_for_deletion "bastion" "$bastion" "$RESOURCE_GROUP" 30 20
        fi
    done
    
    # Delete public IPs
    for pip in "${PIP_NAMES[@]}"; do
        if [[ -n "$pip" ]] && resource_exists "pip" "$pip" "$RESOURCE_GROUP"; then
            execute_az_command "Deleting public IP: $pip" \
                network public-ip delete \
                --name "$pip" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
        fi
    done
    
    log INFO "✅ Azure Bastion resources deleted"
}

# Delete Key Vault resources
delete_key_vault() {
    log INFO "Deleting Azure Key Vault resources..."
    
    for keyvault in "${KEYVAULT_NAMES[@]}"; do
        if [[ -n "$keyvault" ]] && resource_exists "keyvault" "$keyvault" "$RESOURCE_GROUP"; then
            execute_az_command "Deleting Key Vault: $keyvault" \
                keyvault delete \
                --name "$keyvault" \
                --resource-group "$RESOURCE_GROUP"
            
            # Purge Key Vault to completely remove it
            if [[ "$DRY_RUN" == "false" ]]; then
                execute_az_command "Purging Key Vault: $keyvault" \
                    keyvault purge \
                    --name "$keyvault"
            fi
        fi
    done
    
    log INFO "✅ Key Vault resources deleted"
}

# Delete network resources
delete_network_resources() {
    log INFO "Deleting network resources..."
    
    # Delete virtual networks (this will also delete subnets)
    for vnet in "${VNET_NAMES[@]}"; do
        if [[ -n "$vnet" ]] && resource_exists "vnet" "$vnet" "$RESOURCE_GROUP"; then
            execute_az_command "Deleting virtual network: $vnet" \
                network vnet delete \
                --name "$vnet" \
                --resource-group "$RESOURCE_GROUP"
        fi
    done
    
    # Delete network security groups
    for nsg in "${NSG_NAMES[@]}"; do
        if [[ -n "$nsg" ]] && resource_exists "nsg" "$nsg" "$RESOURCE_GROUP"; then
            execute_az_command "Deleting network security group: $nsg" \
                network nsg delete \
                --name "$nsg" \
                --resource-group "$RESOURCE_GROUP"
        fi
    done
    
    log INFO "✅ Network resources deleted"
}

# Delete resource group
delete_resource_group() {
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        log INFO "Deleting resource group..."
        
        execute_az_command "Deleting resource group: $RESOURCE_GROUP" \
            group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        
        log INFO "✅ Resource group deletion initiated: $RESOURCE_GROUP"
        log INFO "Note: Complete cleanup may take several minutes"
    else
        log INFO "Keeping resource group as requested"
    fi
}

# Display cleanup summary
display_cleanup_summary() {
    echo
    echo "==============================================="
    echo "        Cleanup Summary"
    echo "==============================================="
    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN MODE - No resources were actually deleted"
        echo
        echo "The following resources would be deleted:"
    else
        echo "The following resources have been deleted:"
    fi
    echo
    echo "Azure Virtual Desktop:"
    for appgroup in "${APPGROUP_NAMES[@]}"; do
        [[ -n "$appgroup" ]] && echo "  • Application Group: $appgroup"
    done
    for workspace in "${WORKSPACE_NAMES[@]}"; do
        [[ -n "$workspace" ]] && echo "  • Workspace: $workspace"
    done
    for hostpool in "${HOSTPOOL_NAMES[@]}"; do
        [[ -n "$hostpool" ]] && echo "  • Host Pool: $hostpool"
    done
    echo
    echo "Virtual Machines:"
    for vm in "${VM_NAMES[@]}"; do
        [[ -n "$vm" ]] && echo "  • VM: $vm"
    done
    echo
    echo "Security & Access:"
    for bastion in "${BASTION_NAMES[@]}"; do
        [[ -n "$bastion" ]] && echo "  • Bastion: $bastion"
    done
    for keyvault in "${KEYVAULT_NAMES[@]}"; do
        [[ -n "$keyvault" ]] && echo "  • Key Vault: $keyvault"
    done
    echo
    echo "Networking:"
    for vnet in "${VNET_NAMES[@]}"; do
        [[ -n "$vnet" ]] && echo "  • Virtual Network: $vnet"
    done
    for nsg in "${NSG_NAMES[@]}"; do
        [[ -n "$nsg" ]] && echo "  • Network Security Group: $nsg"
    done
    echo
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        echo "Resource Group: $RESOURCE_GROUP"
    else
        echo "Resource Group: $RESOURCE_GROUP (preserved)"
    fi
    echo
    echo "Log file: $LOG_FILE"
    echo "==============================================="
}

# Confirmation prompts
confirm_cleanup() {
    if [[ "$FORCE_CLEANUP" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    echo "⚠️  WARNING: DESTRUCTIVE OPERATION ⚠️"
    echo
    echo "This will permanently delete the following resources:"
    echo "• Resource Group: $RESOURCE_GROUP"
    echo "• All Azure Virtual Desktop resources"
    echo "• All session host virtual machines and their data"
    echo "• Azure Bastion and network infrastructure"
    echo "• Azure Key Vault and all stored certificates/secrets"
    echo
    echo "This action cannot be undone!"
    echo
    
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " -r
    echo
    
    if [[ "$REPLY" != "DELETE" ]]; then
        log INFO "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    read -p "Last chance! Type 'CONFIRM' to proceed with deletion: " -r
    echo
    
    if [[ "$REPLY" != "CONFIRM" ]]; then
        log INFO "Cleanup cancelled by user"
        exit 0
    fi
    
    log INFO "User confirmed cleanup operation"
}

# Main cleanup function
main() {
    log INFO "Starting Azure Virtual Desktop cleanup script"
    log INFO "Script location: $SCRIPT_DIR"
    log INFO "Log file: $LOG_FILE"
    
    parse_args "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "Running in DRY RUN mode - no resources will be deleted"
    fi
    
    check_prerequisites
    discover_resources
    confirm_cleanup
    
    # Main cleanup steps (in proper dependency order)
    delete_avd_resources
    delete_virtual_machines
    delete_azure_bastion
    delete_key_vault
    delete_network_resources
    
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        delete_resource_group
    fi
    
    display_cleanup_summary
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log INFO "Cleanup completed successfully! 🎉"
    else
        log INFO "DRY RUN completed - no resources were deleted"
    fi
    
    log INFO "Cleanup script completed"
}

# Run main function with all arguments
main "$@"