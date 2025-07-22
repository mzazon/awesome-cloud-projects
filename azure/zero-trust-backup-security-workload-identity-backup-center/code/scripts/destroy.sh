#!/bin/bash

# =============================================================================
# Azure Zero-Trust Backup Security Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script
# with proper confirmation prompts and dependency handling
# =============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging configuration
LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_STATE_FILE="$SCRIPT_DIR/.deployment_state"
RESOURCE_TRACKING_FILE="$SCRIPT_DIR/.resource_tracking"

# Default configuration
DEFAULT_CONFIRMATION_TIMEOUT=30

# =============================================================================
# Utility Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely remove Azure Zero-Trust Backup Security resources

OPTIONS:
    -h, --help                      Show this help message
    -r, --resource-group NAME       Resource group name (default: from deployment state)
    -f, --force                     Skip confirmation prompts
    -d, --dry-run                   Show what would be deleted without removing resources
    -v, --verbose                   Enable verbose logging
    --keep-keyvault                 Keep Key Vault and its contents
    --keep-logs                     Keep Log Analytics workspace and logs
    --disable-purge-protection      Disable Key Vault purge protection before deletion
    --timeout SECONDS               Confirmation timeout (default: $DEFAULT_CONFIRMATION_TIMEOUT)

EXAMPLES:
    $0 --resource-group my-backup-rg
    $0 --dry-run --verbose
    $0 --force --keep-keyvault
    $0 --disable-purge-protection --timeout 60

SAFETY FEATURES:
    - Confirmation prompts for destructive actions
    - Resource dependency checking
    - Backup protection disabling before deletion
    - Purge protection handling for Key Vault
    - Partial cleanup recovery

EOF
}

load_deployment_state() {
    local key="$1"
    
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        grep "^$key=" "$DEPLOYMENT_STATE_FILE" 2>/dev/null | cut -d'=' -f2 || echo ""
    else
        echo ""
    fi
}

check_resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    
    case "$resource_type" in
        "ResourceGroup")
            az group show --name "$resource_name" &> /dev/null
            ;;
        "KeyVault")
            az keyvault show --name "$resource_name" &> /dev/null
            ;;
        "ManagedIdentity")
            az identity show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "RecoveryVault")
            az backup vault show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "StorageAccount")
            az storage account show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "VirtualMachine")
            az vm show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        *)
            log_warning "Unknown resource type: $resource_type"
            return 1
            ;;
    esac
}

confirm_action() {
    local message="$1"
    local timeout="${2:-$DEFAULT_CONFIRMATION_TIMEOUT}"
    
    if [[ "$FORCE" == "true" ]]; then
        log_info "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    echo -e "${YELLOW}[CONFIRMATION]${NC} $message"
    echo -e "${YELLOW}[CONFIRMATION]${NC} Type 'yes' to continue (timeout: ${timeout}s): "
    
    read -t "$timeout" -r response || {
        echo
        log_error "Confirmation timeout reached"
        return 1
    }
    
    if [[ "$response" != "yes" ]]; then
        log_error "Operation cancelled by user"
        return 1
    fi
    
    return 0
}

list_resources_to_delete() {
    log_info "Resources that will be deleted:"
    
    if [[ -f "$RESOURCE_TRACKING_FILE" ]]; then
        echo "┌─────────────────────────────────────────────────────────────────────────────┐"
        echo "│ Resource Type    │ Resource Name                    │ Resource Group     │"
        echo "├─────────────────────────────────────────────────────────────────────────────┤"
        
        while IFS='|' read -r resource_type resource_name resource_group timestamp; do
            if [[ -n "$resource_type" ]]; then
                printf "│ %-15s │ %-32s │ %-18s │\n" "$resource_type" "$resource_name" "$resource_group"
            fi
        done < "$RESOURCE_TRACKING_FILE"
        
        echo "└─────────────────────────────────────────────────────────────────────────────┘"
    else
        log_warning "No resource tracking file found"
    fi
}

# =============================================================================
# Resource Cleanup Functions
# =============================================================================

disable_backup_protection() {
    local vm_name="$1"
    local resource_group="$2"
    local recovery_vault="$3"
    
    log_info "Disabling backup protection for VM: $vm_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would disable backup protection for VM: $vm_name"
        return 0
    fi
    
    # Check if VM is protected
    if az backup item show \
        --vault-name "$recovery_vault" \
        --resource-group "$resource_group" \
        --container-name "$vm_name" \
        --item-name "$vm_name" \
        --backup-management-type AzureIaasVM \
        --workload-type VM &> /dev/null; then
        
        log_info "Disabling backup protection and deleting backup data..."
        
        az backup protection disable \
            --vault-name "$recovery_vault" \
            --resource-group "$resource_group" \
            --container-name "$vm_name" \
            --item-name "$vm_name" \
            --backup-management-type AzureIaasVM \
            --workload-type VM \
            --delete-backup-data true \
            --yes || {
            log_error "Failed to disable backup protection for VM: $vm_name"
            return 1
        }
        
        # Wait for backup protection to be disabled
        log_info "Waiting for backup protection to be disabled..."
        sleep 60
        
        log_success "Backup protection disabled for VM: $vm_name"
    else
        log_info "VM $vm_name is not protected or protection already disabled"
    fi
}

remove_virtual_machine() {
    local vm_name="$1"
    local resource_group="$2"
    
    log_info "Removing virtual machine: $vm_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove VM: $vm_name and associated resources"
        return 0
    fi
    
    if ! check_resource_exists "VirtualMachine" "$vm_name" "$resource_group"; then
        log_info "VM $vm_name does not exist, skipping"
        return 0
    fi
    
    # Delete VM and associated resources
    az vm delete \
        --name "$vm_name" \
        --resource-group "$resource_group" \
        --yes || {
        log_error "Failed to delete VM: $vm_name"
        return 1
    }
    
    # Remove network resources
    local network_resources=(
        "nic-backup-test"
        "pip-backup-test"
        "nsg-backup-test"
        "vnet-backup-test"
    )
    
    for resource in "${network_resources[@]}"; do
        log_info "Checking for network resource: $resource"
        case "$resource" in
            "vnet-backup-test")
                az network vnet delete \
                    --name "$resource" \
                    --resource-group "$resource_group" 2>/dev/null || true
                ;;
            "nsg-backup-test")
                az network nsg delete \
                    --name "$resource" \
                    --resource-group "$resource_group" 2>/dev/null || true
                ;;
            "pip-backup-test")
                az network public-ip delete \
                    --name "$resource" \
                    --resource-group "$resource_group" 2>/dev/null || true
                ;;
            "nic-backup-test")
                az network nic delete \
                    --name "$resource" \
                    --resource-group "$resource_group" 2>/dev/null || true
                ;;
        esac
    done
    
    log_success "Virtual machine and network resources removed"
}

remove_recovery_vault() {
    local vault_name="$1"
    local resource_group="$2"
    
    log_info "Removing Recovery Services Vault: $vault_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove Recovery Services Vault: $vault_name"
        return 0
    fi
    
    if ! check_resource_exists "RecoveryVault" "$vault_name" "$resource_group"; then
        log_info "Recovery Services Vault $vault_name does not exist, skipping"
        return 0
    fi
    
    # Delete Recovery Services Vault
    az backup vault delete \
        --name "$vault_name" \
        --resource-group "$resource_group" \
        --yes || {
        log_error "Failed to delete Recovery Services Vault: $vault_name"
        return 1
    }
    
    log_success "Recovery Services Vault removed"
}

remove_storage_account() {
    local storage_name="$1"
    local resource_group="$2"
    
    log_info "Removing storage account: $storage_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove storage account: $storage_name"
        return 0
    fi
    
    if ! check_resource_exists "StorageAccount" "$storage_name" "$resource_group"; then
        log_info "Storage account $storage_name does not exist, skipping"
        return 0
    fi
    
    # Delete storage account
    az storage account delete \
        --name "$storage_name" \
        --resource-group "$resource_group" \
        --yes || {
        log_error "Failed to delete storage account: $storage_name"
        return 1
    }
    
    log_success "Storage account removed"
}

remove_log_analytics_workspace() {
    local resource_group="$1"
    
    if [[ "$KEEP_LOGS" == "true" ]]; then
        log_info "Keeping Log Analytics workspace (--keep-logs flag)"
        return 0
    fi
    
    log_info "Removing Log Analytics workspace"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove Log Analytics workspace"
        return 0
    fi
    
    # Find and delete Log Analytics workspace
    local workspaces=$(az monitor log-analytics workspace list \
        --resource-group "$resource_group" \
        --query "[?contains(name, 'law-backup-center')].name" \
        --output tsv)
    
    if [[ -n "$workspaces" ]]; then
        for workspace in $workspaces; do
            log_info "Removing Log Analytics workspace: $workspace"
            az monitor log-analytics workspace delete \
                --name "$workspace" \
                --resource-group "$resource_group" \
                --yes || {
                log_warning "Failed to delete Log Analytics workspace: $workspace"
            }
        done
    else
        log_info "No Log Analytics workspaces found"
    fi
    
    log_success "Log Analytics workspace removal completed"
}

remove_key_vault() {
    local vault_name="$1"
    local location="$2"
    
    if [[ "$KEEP_KEYVAULT" == "true" ]]; then
        log_info "Keeping Key Vault (--keep-keyvault flag)"
        return 0
    fi
    
    log_info "Removing Key Vault: $vault_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove Key Vault: $vault_name"
        return 0
    fi
    
    if ! check_resource_exists "KeyVault" "$vault_name" ""; then
        log_info "Key Vault $vault_name does not exist, skipping"
        return 0
    fi
    
    # Check if purge protection is enabled
    local purge_protection=$(az keyvault show \
        --name "$vault_name" \
        --query properties.enablePurgeProtection \
        --output tsv 2>/dev/null || echo "false")
    
    if [[ "$purge_protection" == "true" && "$DISABLE_PURGE_PROTECTION" == "true" ]]; then
        log_warning "Attempting to disable purge protection (not recommended in production)"
        # Note: Purge protection cannot be disabled once enabled, this is by design
        log_warning "Purge protection cannot be disabled once enabled"
    fi
    
    # Delete Key Vault
    az keyvault delete \
        --name "$vault_name" || {
        log_error "Failed to delete Key Vault: $vault_name"
        return 1
    }
    
    if [[ "$purge_protection" == "true" ]]; then
        log_warning "Key Vault has purge protection enabled"
        log_warning "The vault will be recoverable for the retention period"
        log_warning "To permanently delete, use: az keyvault purge --name $vault_name --location $location"
    else
        # Purge the Key Vault if purge protection is not enabled
        log_info "Purging Key Vault: $vault_name"
        az keyvault purge \
            --name "$vault_name" \
            --location "$location" || {
            log_warning "Failed to purge Key Vault: $vault_name"
        }
    fi
    
    log_success "Key Vault removal completed"
}

remove_managed_identity() {
    local identity_name="$1"
    local resource_group="$2"
    
    log_info "Removing managed identity: $identity_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove managed identity: $identity_name"
        return 0
    fi
    
    if ! check_resource_exists "ManagedIdentity" "$identity_name" "$resource_group"; then
        log_info "Managed identity $identity_name does not exist, skipping"
        return 0
    fi
    
    # Remove federated credentials first
    local fed_creds=$(az identity federated-credential list \
        --identity-name "$identity_name" \
        --resource-group "$resource_group" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$fed_creds" ]]; then
        for cred in $fed_creds; do
            log_info "Removing federated credential: $cred"
            az identity federated-credential delete \
                --identity-name "$identity_name" \
                --resource-group "$resource_group" \
                --name "$cred" || {
                log_warning "Failed to remove federated credential: $cred"
            }
        done
    fi
    
    # Delete managed identity
    az identity delete \
        --name "$identity_name" \
        --resource-group "$resource_group" || {
        log_error "Failed to delete managed identity: $identity_name"
        return 1
    }
    
    log_success "Managed identity removed"
}

remove_resource_group() {
    local resource_group="$1"
    
    log_info "Removing resource group: $resource_group"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would remove resource group: $resource_group"
        return 0
    fi
    
    if ! check_resource_exists "ResourceGroup" "$resource_group" ""; then
        log_info "Resource group $resource_group does not exist, skipping"
        return 0
    fi
    
    # Final confirmation for resource group deletion
    if ! confirm_action "Are you sure you want to delete the entire resource group '$resource_group'? This action cannot be undone." 60; then
        log_error "Resource group deletion cancelled"
        return 1
    fi
    
    # Delete resource group
    az group delete \
        --name "$resource_group" \
        --yes \
        --no-wait || {
        log_error "Failed to delete resource group: $resource_group"
        return 1
    }
    
    log_success "Resource group deletion initiated (may take several minutes)"
}

cleanup_state_files() {
    log_info "Cleaning up state files"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up state files"
        return 0
    fi
    
    # Remove state files
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        rm -f "$DEPLOYMENT_STATE_FILE"
        log_success "Deployment state file removed"
    fi
    
    if [[ -f "$RESOURCE_TRACKING_FILE" ]]; then
        rm -f "$RESOURCE_TRACKING_FILE"
        log_success "Resource tracking file removed"
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    log_info "Starting Azure Zero-Trust Backup Security cleanup"
    log_info "Log file: $LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -r|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -f|--force)
                FORCE="true"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            --keep-keyvault)
                KEEP_KEYVAULT="true"
                shift
                ;;
            --keep-logs)
                KEEP_LOGS="true"
                shift
                ;;
            --disable-purge-protection)
                DISABLE_PURGE_PROTECTION="true"
                shift
                ;;
            --timeout)
                CONFIRMATION_TIMEOUT="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set default values
    RESOURCE_GROUP="${RESOURCE_GROUP:-}"
    FORCE="${FORCE:-false}"
    DRY_RUN="${DRY_RUN:-false}"
    VERBOSE="${VERBOSE:-false}"
    KEEP_KEYVAULT="${KEEP_KEYVAULT:-false}"
    KEEP_LOGS="${KEEP_LOGS:-false}"
    DISABLE_PURGE_PROTECTION="${DISABLE_PURGE_PROTECTION:-false}"
    CONFIRMATION_TIMEOUT="${CONFIRMATION_TIMEOUT:-$DEFAULT_CONFIRMATION_TIMEOUT}"
    
    # Load resource information from deployment state
    if [[ -z "$RESOURCE_GROUP" ]]; then
        RESOURCE_GROUP=$(load_deployment_state "RESOURCE_GROUP")
    fi
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log_error "Resource group not specified and not found in deployment state"
        log_error "Please provide resource group name with -r/--resource-group"
        exit 1
    fi
    
    # Load other resource names from deployment state
    KEY_VAULT_NAME=$(load_deployment_state "KEY_VAULT_NAME")
    WORKLOAD_IDENTITY_NAME=$(load_deployment_state "WORKLOAD_IDENTITY_NAME")
    RECOVERY_VAULT_NAME=$(load_deployment_state "RECOVERY_VAULT_NAME")
    STORAGE_ACCOUNT_NAME=$(load_deployment_state "STORAGE_ACCOUNT_NAME")
    VM_NAME=$(load_deployment_state "VM_NAME")
    
    # Get location from Azure if not in state
    LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location --output tsv 2>/dev/null || echo "")
    
    log_info "Cleanup Configuration:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Force: $FORCE"
    log_info "  Dry Run: $DRY_RUN"
    log_info "  Keep Key Vault: $KEEP_KEYVAULT"
    log_info "  Keep Logs: $KEEP_LOGS"
    log_info "  Disable Purge Protection: $DISABLE_PURGE_PROTECTION"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Check if Azure CLI is available
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Show resources to be deleted
    list_resources_to_delete
    
    # Main confirmation
    if ! confirm_action "Do you want to proceed with the cleanup? This will delete Azure resources and may result in charges." "$CONFIRMATION_TIMEOUT"; then
        log_error "Cleanup cancelled by user"
        exit 1
    fi
    
    # Execute cleanup in proper order (reverse of deployment)
    log_info "Starting cleanup process..."
    
    # 1. Disable backup protection for VMs
    if [[ -n "$VM_NAME" && -n "$RECOVERY_VAULT_NAME" ]]; then
        disable_backup_protection "$VM_NAME" "$RESOURCE_GROUP" "$RECOVERY_VAULT_NAME"
    fi
    
    # 2. Remove virtual machine and network resources
    if [[ -n "$VM_NAME" ]]; then
        remove_virtual_machine "$VM_NAME" "$RESOURCE_GROUP"
    fi
    
    # 3. Remove Recovery Services Vault
    if [[ -n "$RECOVERY_VAULT_NAME" ]]; then
        remove_recovery_vault "$RECOVERY_VAULT_NAME" "$RESOURCE_GROUP"
    fi
    
    # 4. Remove storage account
    if [[ -n "$STORAGE_ACCOUNT_NAME" ]]; then
        remove_storage_account "$STORAGE_ACCOUNT_NAME" "$RESOURCE_GROUP"
    fi
    
    # 5. Remove Log Analytics workspace
    remove_log_analytics_workspace "$RESOURCE_GROUP"
    
    # 6. Remove Key Vault
    if [[ -n "$KEY_VAULT_NAME" ]]; then
        remove_key_vault "$KEY_VAULT_NAME" "$LOCATION"
    fi
    
    # 7. Remove managed identity
    if [[ -n "$WORKLOAD_IDENTITY_NAME" ]]; then
        remove_managed_identity "$WORKLOAD_IDENTITY_NAME" "$RESOURCE_GROUP"
    fi
    
    # 8. Remove resource group (optional, with confirmation)
    if confirm_action "Do you want to delete the entire resource group '$RESOURCE_GROUP'? This will remove any remaining resources." "$CONFIRMATION_TIMEOUT"; then
        remove_resource_group "$RESOURCE_GROUP"
    else
        log_info "Resource group deletion skipped"
    fi
    
    # 9. Clean up state files
    cleanup_state_files
    
    # Display cleanup summary
    log_success "Cleanup completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo
        echo "=== CLEANUP SUMMARY ==="
        echo "Resource Group: $RESOURCE_GROUP"
        if [[ -n "$KEY_VAULT_NAME" ]]; then
            echo "Key Vault: $KEY_VAULT_NAME $([ "$KEEP_KEYVAULT" == "true" ] && echo "(kept)" || echo "(removed)")"
        fi
        if [[ -n "$WORKLOAD_IDENTITY_NAME" ]]; then
            echo "Workload Identity: $WORKLOAD_IDENTITY_NAME (removed)"
        fi
        if [[ -n "$RECOVERY_VAULT_NAME" ]]; then
            echo "Recovery Vault: $RECOVERY_VAULT_NAME (removed)"
        fi
        if [[ -n "$STORAGE_ACCOUNT_NAME" ]]; then
            echo "Storage Account: $STORAGE_ACCOUNT_NAME (removed)"
        fi
        if [[ -n "$VM_NAME" ]]; then
            echo "Test VM: $VM_NAME (removed)"
        fi
        echo "Log Analytics: $([ "$KEEP_LOGS" == "true" ] && echo "(kept)" || echo "(removed)")"
        echo
        echo "Notes:"
        echo "- Resource group deletion may take several minutes to complete"
        echo "- Key Vault with purge protection will be recoverable for the retention period"
        echo "- Check Azure portal to verify all resources have been removed"
        echo
        echo "Log file: $LOG_FILE"
    fi
}

# Trap to handle script interruption
trap 'log_error "Cleanup interrupted"; exit 1' INT TERM

# Execute main function
main "$@"