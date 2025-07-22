#!/bin/bash

# =============================================================================
# Azure AI Agent Governance Cleanup Script
# =============================================================================
# This script removes all Azure resources created by the AI agent governance
# deployment script. Use with caution as this will permanently delete resources.
#
# Prerequisites:
# - Azure CLI v2.50.0 or later
# - Global Administrator or Security Administrator permissions
# - Bash shell (Linux/macOS/WSL)
#
# Usage: ./destroy.sh [OPTIONS]
# Options:
#   -h, --help          Show this help message
#   -v, --verbose       Enable verbose output
#   -d, --dry-run       Show what would be deleted without executing
#   -g, --resource-group Resource group to delete
#   -f, --force         Skip confirmation prompts
#   -k, --keep-keyvault Keep Key Vault (only disable)
#
# =============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
VERBOSE=false
DRY_RUN=false
FORCE=false
KEEP_KEYVAULT=false
RESOURCE_GROUP=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1" | tee -a "$LOG_FILE"
}

verbose_log() {
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "$1"
    fi
}

# Help function
show_help() {
    cat << EOF
Azure AI Agent Governance Cleanup Script

This script removes all Azure resources created by the AI agent governance
deployment script. Use with caution as this will permanently delete resources.

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -d, --dry-run       Show what would be deleted without executing
    -g, --resource-group Resource group to delete (required)
    -f, --force         Skip confirmation prompts
    -k, --keep-keyvault Keep Key Vault (only disable, don't delete)

Examples:
    $0 -g rg-ai-governance-abc123      # Delete specific resource group
    $0 -g rg-ai-governance-abc123 -d   # Dry run to see what would be deleted
    $0 -g rg-ai-governance-abc123 -f   # Force delete without confirmation
    $0 -g rg-ai-governance-abc123 -k   # Keep Key Vault, delete everything else

Prerequisites:
    - Azure CLI v2.50.0 or later
    - Global Administrator or Security Administrator permissions
    - Bash shell (Linux/macOS/WSL)

WARNING: This script will permanently delete Azure resources. Make sure you
have backups of any important data before running this script.

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -k|--keep-keyvault)
                KEEP_KEYVAULT=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log_error "Resource group is required. Use -g or --resource-group option."
        show_help
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI v2.50.0 or later."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    local min_version="2.50.0"
    
    if ! printf '%s\n%s' "$min_version" "$az_version" | sort -V -C; then
        log_error "Azure CLI version $az_version is too old. Please upgrade to v2.50.0 or later."
        exit 1
    fi
    
    verbose_log "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "✅ Prerequisites check passed"
}

# Validate resource group exists
validate_resource_group() {
    log "Validating resource group..."
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group '$RESOURCE_GROUP' not found"
        exit 1
    fi
    
    local subscription_id
    subscription_id=$(az account show --query id -o tsv)
    verbose_log "Subscription ID: $subscription_id"
    verbose_log "Resource Group: $RESOURCE_GROUP"
    
    log "✅ Resource group validation passed"
}

# Get resource inventory
get_resource_inventory() {
    log "Getting resource inventory..."
    
    # Get all resources in the resource group
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,Type:type,Location:location}" --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$resources" ]]; then
        log_warning "No resources found in resource group '$RESOURCE_GROUP'"
        return 0
    fi
    
    log_info "Resources found in '$RESOURCE_GROUP':"
    echo "$resources" | while IFS=$'\t' read -r name type location; do
        echo "  - $name ($type) in $location"
    done | tee -a "$LOG_FILE"
    
    # Get specific resource types for targeted cleanup
    LOGIC_APPS=$(az logic workflow list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
    KEY_VAULTS=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
    LOG_WORKSPACES=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    verbose_log "Logic Apps: $LOGIC_APPS"
    verbose_log "Key Vaults: $KEY_VAULTS"
    verbose_log "Log Analytics Workspaces: $LOG_WORKSPACES"
    
    log "✅ Resource inventory completed"
}

# Confirm deletion
confirm_deletion() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will permanently delete all resources in resource group: $RESOURCE_GROUP"
    log_warning "This action cannot be undone!"
    echo ""
    
    if [[ "$KEEP_KEYVAULT" == "true" ]]; then
        log_info "Key Vault will be kept (only disabled)"
    else
        log_warning "Key Vault will be permanently deleted"
    fi
    
    echo ""
    read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " -r
    echo ""
    
    if [[ "$REPLY" != "DELETE" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed by user"
}

# Stop Logic Apps workflows
stop_logic_apps() {
    if [[ -z "$LOGIC_APPS" ]]; then
        verbose_log "No Logic Apps found to stop"
        return 0
    fi
    
    log "Stopping Logic Apps workflows..."
    
    while IFS= read -r workflow_name; do
        if [[ -n "$workflow_name" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would stop Logic App: $workflow_name"
            else
                verbose_log "Stopping Logic App: $workflow_name"
                az logic workflow disable \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$workflow_name" \
                    --output none 2>/dev/null || log_warning "Failed to stop Logic App: $workflow_name"
            fi
        fi
    done <<< "$LOGIC_APPS"
    
    log "✅ Logic Apps workflows stopped"
}

# Delete Logic Apps
delete_logic_apps() {
    if [[ -z "$LOGIC_APPS" ]]; then
        verbose_log "No Logic Apps found to delete"
        return 0
    fi
    
    log "Deleting Logic Apps..."
    
    while IFS= read -r workflow_name; do
        if [[ -n "$workflow_name" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete Logic App: $workflow_name"
            else
                verbose_log "Deleting Logic App: $workflow_name"
                az logic workflow delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$workflow_name" \
                    --yes \
                    --output none 2>/dev/null || log_warning "Failed to delete Logic App: $workflow_name"
            fi
        fi
    done <<< "$LOGIC_APPS"
    
    log "✅ Logic Apps deleted"
}

# Handle Key Vault cleanup
handle_key_vault() {
    if [[ -z "$KEY_VAULTS" ]]; then
        verbose_log "No Key Vaults found"
        return 0
    fi
    
    while IFS= read -r vault_name; do
        if [[ -n "$vault_name" ]]; then
            if [[ "$KEEP_KEYVAULT" == "true" ]]; then
                log "Disabling Key Vault: $vault_name"
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY RUN] Would disable Key Vault: $vault_name"
                else
                    # Just disable access policies but keep the vault
                    verbose_log "Disabling Key Vault access: $vault_name"
                    az keyvault update \
                        --name "$vault_name" \
                        --enabled-for-deployment false \
                        --enabled-for-disk-encryption false \
                        --enabled-for-template-deployment false \
                        --output none 2>/dev/null || log_warning "Failed to disable Key Vault: $vault_name"
                fi
            else
                log "Deleting Key Vault: $vault_name"
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY RUN] Would delete Key Vault: $vault_name"
                else
                    verbose_log "Deleting Key Vault: $vault_name"
                    az keyvault delete \
                        --name "$vault_name" \
                        --output none 2>/dev/null || log_warning "Failed to delete Key Vault: $vault_name"
                    
                    # Also purge the Key Vault to completely remove it
                    verbose_log "Purging Key Vault: $vault_name"
                    az keyvault purge \
                        --name "$vault_name" \
                        --output none 2>/dev/null || log_warning "Failed to purge Key Vault: $vault_name"
                fi
            fi
        fi
    done <<< "$KEY_VAULTS"
    
    if [[ "$KEEP_KEYVAULT" == "true" ]]; then
        log "✅ Key Vaults disabled"
    else
        log "✅ Key Vaults deleted"
    fi
}

# Delete Log Analytics workspaces
delete_log_analytics() {
    if [[ -z "$LOG_WORKSPACES" ]]; then
        verbose_log "No Log Analytics workspaces found"
        return 0
    fi
    
    log "Deleting Log Analytics workspaces..."
    
    while IFS= read -r workspace_name; do
        if [[ -n "$workspace_name" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete Log Analytics workspace: $workspace_name"
            else
                verbose_log "Deleting Log Analytics workspace: $workspace_name"
                az monitor log-analytics workspace delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --workspace-name "$workspace_name" \
                    --yes \
                    --output none 2>/dev/null || log_warning "Failed to delete Log Analytics workspace: $workspace_name"
            fi
        fi
    done <<< "$LOG_WORKSPACES"
    
    log "✅ Log Analytics workspaces deleted"
}

# Delete resource group
delete_resource_group() {
    log "Deleting resource group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    if [[ "$KEEP_KEYVAULT" == "true" ]]; then
        log_info "Skipping resource group deletion to preserve Key Vault"
        log_info "Note: Other resources in the group will remain. Clean up manually if needed."
        return 0
    fi
    
    # Delete the entire resource group
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none
    
    log "✅ Resource group deletion initiated: $RESOURCE_GROUP"
    log_info "Note: Complete deletion may take 5-10 minutes"
}

# Verify cleanup
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify cleanup"
        return 0
    fi
    
    log "Verifying cleanup..."
    
    # Wait a moment for deletions to take effect
    sleep 5
    
    if [[ "$KEEP_KEYVAULT" == "true" ]]; then
        # Check that Key Vault still exists but is disabled
        while IFS= read -r vault_name; do
            if [[ -n "$vault_name" ]]; then
                if az keyvault show --name "$vault_name" &> /dev/null; then
                    verbose_log "Key Vault preserved: $vault_name"
                else
                    log_warning "Key Vault may have been deleted: $vault_name"
                fi
            fi
        done <<< "$KEY_VAULTS"
    else
        # Check that resource group is being deleted
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            local rg_state
            rg_state=$(az group show --name "$RESOURCE_GROUP" --query "properties.provisioningState" -o tsv 2>/dev/null || echo "Unknown")
            if [[ "$rg_state" == "Deleting" ]]; then
                log_info "Resource group is being deleted: $RESOURCE_GROUP"
            else
                log_warning "Resource group may not be deleting properly: $RESOURCE_GROUP (state: $rg_state)"
            fi
        else
            log "✅ Resource group successfully deleted: $RESOURCE_GROUP"
        fi
    fi
    
    log "✅ Cleanup verification completed"
}

# Display cleanup summary
display_summary() {
    log "Cleanup process completed!"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Summary of what would be deleted:"
    else
        log_info "Cleanup Summary:"
    fi
    
    echo ""
    echo "=== Resource Group ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo ""
    echo "=== Cleanup Actions ==="
    if [[ -n "$LOGIC_APPS" ]]; then
        echo "Logic Apps: Deleted"
        echo "$LOGIC_APPS" | while IFS= read -r workflow_name; do
            if [[ -n "$workflow_name" ]]; then
                echo "  - $workflow_name"
            fi
        done
    fi
    
    if [[ -n "$LOG_WORKSPACES" ]]; then
        echo "Log Analytics Workspaces: Deleted"
        echo "$LOG_WORKSPACES" | while IFS= read -r workspace_name; do
            if [[ -n "$workspace_name" ]]; then
                echo "  - $workspace_name"
            fi
        done
    fi
    
    if [[ -n "$KEY_VAULTS" ]]; then
        if [[ "$KEEP_KEYVAULT" == "true" ]]; then
            echo "Key Vaults: Disabled (preserved)"
        else
            echo "Key Vaults: Deleted and purged"
        fi
        echo "$KEY_VAULTS" | while IFS= read -r vault_name; do
            if [[ -n "$vault_name" ]]; then
                echo "  - $vault_name"
            fi
        done
    fi
    
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        if [[ "$KEEP_KEYVAULT" == "true" ]]; then
            echo "=== Remaining Resources ==="
            echo "Resource group and Key Vault have been preserved"
            echo "You may need to manually clean up other resources if needed"
        else
            echo "=== Complete Cleanup ==="
            echo "All resources have been deleted"
            echo "The resource group deletion may take 5-10 minutes to complete"
        fi
    fi
    
    echo ""
    log "Cleanup log saved to: $LOG_FILE"
}

# Error handling
handle_error() {
    local exit_code=$?
    log_error "Script failed with exit code $exit_code"
    log_error "Check the log file for details: $LOG_FILE"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log_warning "Some resources may not have been deleted properly"
        log_warning "Please check the Azure portal to verify resource cleanup"
    fi
    
    exit $exit_code
}

# Main execution
main() {
    # Set up error handling
    trap handle_error ERR
    
    # Initialize log file
    echo "Azure AI Agent Governance Cleanup Log" > "$LOG_FILE"
    echo "Started: $(date)" >> "$LOG_FILE"
    echo "=========================================" >> "$LOG_FILE"
    
    # Parse command line arguments
    parse_args "$@"
    
    log "Starting Azure AI Agent Governance cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE: No resources will be deleted"
    fi
    
    # Execute cleanup steps
    check_prerequisites
    validate_resource_group
    get_resource_inventory
    confirm_deletion
    stop_logic_apps
    delete_logic_apps
    delete_log_analytics
    handle_key_vault
    delete_resource_group
    verify_cleanup
    display_summary
    
    log "Cleanup completed successfully!"
}

# Execute main function with all arguments
main "$@"