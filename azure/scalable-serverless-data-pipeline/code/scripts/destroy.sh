#!/bin/bash

# Azure Serverless Data Pipeline Cleanup Script
# Recipe: Scalable Serverless Data Pipeline with Synapse and Data Factory
# Version: 1.0
# Last Updated: 2025-07-12

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI login status
    if ! az account show >/dev/null 2>&1; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "Prerequisites check passed ✅"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set default values or use existing environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-serverless-pipeline}"
    export LOCATION="${LOCATION:-eastus}"
    export RANDOM_SUFFIX="${RANDOM_SUFFIX:-}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}"
    export SYNAPSE_WORKSPACE="${SYNAPSE_WORKSPACE:-}"
    export DATA_FACTORY="${DATA_FACTORY:-}"
    export KEY_VAULT="${KEY_VAULT:-}"
    
    # If no specific resource names are provided, try to discover them
    if [[ -z "${STORAGE_ACCOUNT}" || -z "${SYNAPSE_WORKSPACE}" || -z "${DATA_FACTORY}" || -z "${KEY_VAULT}" ]]; then
        log "Discovering resources in resource group ${RESOURCE_GROUP}..."
        
        # Get storage account name
        if [[ -z "${STORAGE_ACCOUNT}" ]]; then
            STORAGE_ACCOUNT=$(az storage account list \
                --resource-group "${RESOURCE_GROUP}" \
                --query "[?starts_with(name, 'stpipeline')].name" -o tsv | head -1)
        fi
        
        # Get Synapse workspace name
        if [[ -z "${SYNAPSE_WORKSPACE}" ]]; then
            SYNAPSE_WORKSPACE=$(az synapse workspace list \
                --resource-group "${RESOURCE_GROUP}" \
                --query "[?starts_with(name, 'syn-pipeline')].name" -o tsv | head -1)
        fi
        
        # Get Data Factory name
        if [[ -z "${DATA_FACTORY}" ]]; then
            DATA_FACTORY=$(az datafactory list \
                --resource-group "${RESOURCE_GROUP}" \
                --query "[?starts_with(name, 'adf-pipeline')].name" -o tsv | head -1)
        fi
        
        # Get Key Vault name
        if [[ -z "${KEY_VAULT}" ]]; then
            KEY_VAULT=$(az keyvault list \
                --resource-group "${RESOURCE_GROUP}" \
                --query "[?starts_with(name, 'kv-pipeline')].name" -o tsv | head -1)
        fi
    fi
    
    info "Resource Group: ${RESOURCE_GROUP}"
    info "Storage Account: ${STORAGE_ACCOUNT:-<not found>}"
    info "Synapse Workspace: ${SYNAPSE_WORKSPACE:-<not found>}"
    info "Data Factory: ${DATA_FACTORY:-<not found>}"
    info "Key Vault: ${KEY_VAULT:-<not found>}"
    
    log "Environment variables set ✅"
}

# Function to prompt for confirmation
confirm_deletion() {
    echo ""
    warn "⚠️  DANGER: This will permanently delete all resources in the resource group: ${RESOURCE_GROUP}"
    warn "This action cannot be undone and will result in data loss."
    echo ""
    
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        warn "Force delete mode enabled. Skipping confirmation."
        return 0
    fi
    
    echo -n "Are you sure you want to continue? Type 'yes' to confirm: "
    read -r confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log "Deletion cancelled by user."
        exit 0
    fi
    
    echo -n "Please type the resource group name '${RESOURCE_GROUP}' to confirm: "
    read -r rg_confirmation
    
    if [[ "${rg_confirmation}" != "${RESOURCE_GROUP}" ]]; then
        error "Resource group name mismatch. Deletion cancelled."
        exit 1
    fi
    
    log "Deletion confirmed by user."
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    
    case "${resource_type}" in
        "datafactory")
            az datafactory show --name "${resource_name}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1
            ;;
        "synapse")
            az synapse workspace show --name "${resource_name}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1
            ;;
        "keyvault")
            az keyvault show --name "${resource_name}" >/dev/null 2>&1
            ;;
        "storage")
            az storage account show --name "${resource_name}" --resource-group "${RESOURCE_GROUP}" >/dev/null 2>&1
            ;;
        "resource-group")
            az group show --name "${resource_name}" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to delete Data Factory resources
delete_data_factory() {
    if [[ -n "${DATA_FACTORY}" ]] && resource_exists "datafactory" "${DATA_FACTORY}"; then
        log "Deleting Data Factory: ${DATA_FACTORY}"
        
        # Delete Data Factory (this will also delete associated resources)
        az datafactory delete \
            --name "${DATA_FACTORY}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --no-wait
        
        log "Data Factory deletion initiated ✅"
    else
        warn "Data Factory not found or already deleted"
    fi
}

# Function to delete Synapse workspace
delete_synapse_workspace() {
    if [[ -n "${SYNAPSE_WORKSPACE}" ]] && resource_exists "synapse" "${SYNAPSE_WORKSPACE}"; then
        log "Deleting Synapse workspace: ${SYNAPSE_WORKSPACE}"
        
        # Delete Synapse workspace
        az synapse workspace delete \
            --name "${SYNAPSE_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --no-wait
        
        log "Synapse workspace deletion initiated ✅"
    else
        warn "Synapse workspace not found or already deleted"
    fi
}

# Function to delete Key Vault
delete_key_vault() {
    if [[ -n "${KEY_VAULT}" ]] && resource_exists "keyvault" "${KEY_VAULT}"; then
        log "Deleting Key Vault: ${KEY_VAULT}"
        
        # Delete Key Vault
        az keyvault delete \
            --name "${KEY_VAULT}" \
            --resource-group "${RESOURCE_GROUP}"
        
        # Purge soft-deleted vault to completely remove it
        log "Purging soft-deleted Key Vault: ${KEY_VAULT}"
        az keyvault purge \
            --name "${KEY_VAULT}" \
            --location "${LOCATION}" || warn "Failed to purge Key Vault (it may not exist in soft-deleted state)"
        
        log "Key Vault deleted and purged ✅"
    else
        warn "Key Vault not found or already deleted"
    fi
}

# Function to delete storage account
delete_storage_account() {
    if [[ -n "${STORAGE_ACCOUNT}" ]] && resource_exists "storage" "${STORAGE_ACCOUNT}"; then
        log "Deleting Storage Account: ${STORAGE_ACCOUNT}"
        
        # Delete storage account
        az storage account delete \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes
        
        log "Storage Account deleted ✅"
    else
        warn "Storage Account not found or already deleted"
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log "Cleaning up monitoring resources..."
    
    # Delete metric alerts
    local alerts=$(az monitor metrics alert list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${alerts}" ]]; then
        while IFS= read -r alert; do
            if [[ -n "${alert}" ]]; then
                log "Deleting alert: ${alert}"
                az monitor metrics alert delete \
                    --name "${alert}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --yes || warn "Failed to delete alert: ${alert}"
            fi
        done <<< "${alerts}"
    fi
    
    log "Monitoring resources cleanup completed ✅"
}

# Function to delete resource group
delete_resource_group() {
    if resource_exists "resource-group" "${RESOURCE_GROUP}"; then
        log "Deleting resource group: ${RESOURCE_GROUP}"
        
        # Delete entire resource group
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait
        
        log "Resource group deletion initiated ✅"
        info "Complete deletion may take several minutes to hours depending on resources."
    else
        warn "Resource group ${RESOURCE_GROUP} not found or already deleted"
    fi
}

# Function to wait for resource deletions
wait_for_deletions() {
    if [[ "${WAIT_FOR_COMPLETION:-false}" == "true" ]]; then
        log "Waiting for resource deletions to complete..."
        
        # Wait for resource group deletion
        local max_attempts=60
        local attempt=0
        
        while resource_exists "resource-group" "${RESOURCE_GROUP}" && [[ ${attempt} -lt ${max_attempts} ]]; do
            log "Waiting for resource group deletion... (attempt ${attempt}/${max_attempts})"
            sleep 30
            ((attempt++))
        done
        
        if resource_exists "resource-group" "${RESOURCE_GROUP}"; then
            warn "Resource group deletion is taking longer than expected. Check Azure portal for status."
        else
            log "Resource group deletion completed ✅"
        fi
    else
        info "Resource deletions initiated. Check Azure portal for completion status."
    fi
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    # Check if resource group still exists
    if ! resource_exists "resource-group" "${RESOURCE_GROUP}"; then
        log "Resource group successfully deleted ✅"
        return 0
    fi
    
    # If resource group exists, check individual resources
    local remaining_resources=$(az resource list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "length(@)" -o tsv 2>/dev/null || echo "0")
    
    if [[ "${remaining_resources}" -eq 0 ]]; then
        log "All resources successfully deleted ✅"
        return 0
    else
        warn "Some resources may still be in the deletion process"
        info "Remaining resources: ${remaining_resources}"
        az resource list --resource-group "${RESOURCE_GROUP}" --output table || true
        return 1
    fi
}

# Main cleanup function
main() {
    log "Starting Azure Serverless Data Pipeline cleanup..."
    
    # Check if running in dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        info "Running in dry-run mode. No resources will be deleted."
        set_environment_variables
        log "Dry-run completed. The following resources would be deleted:"
        log "- Resource Group: ${RESOURCE_GROUP}"
        log "- Storage Account: ${STORAGE_ACCOUNT:-<not found>}"
        log "- Synapse Workspace: ${SYNAPSE_WORKSPACE:-<not found>}"
        log "- Data Factory: ${DATA_FACTORY:-<not found>}"
        log "- Key Vault: ${KEY_VAULT:-<not found>}"
        log "Use the following command to delete resources:"
        log "./destroy.sh"
        exit 0
    fi
    
    # Check if using fast cleanup (delete resource group directly)
    if [[ "${1:-}" == "--fast" ]]; then
        info "Fast cleanup mode enabled. Deleting resource group directly."
        export FAST_CLEANUP=true
    fi
    
    # Run cleanup steps
    check_prerequisites
    set_environment_variables
    confirm_deletion
    
    if [[ "${FAST_CLEANUP:-false}" == "true" ]]; then
        # Fast cleanup - delete resource group directly
        delete_resource_group
    else
        # Detailed cleanup - delete resources in reverse order
        delete_monitoring_resources
        delete_data_factory
        delete_synapse_workspace
        delete_key_vault
        delete_storage_account
        
        # Wait a moment before deleting resource group
        log "Waiting 30 seconds before deleting resource group..."
        sleep 30
        
        delete_resource_group
    fi
    
    # Wait for completions if requested
    wait_for_deletions
    
    # Validate cleanup
    if [[ "${WAIT_FOR_COMPLETION:-false}" == "true" ]]; then
        if validate_cleanup; then
            log "🎉 Cleanup completed successfully!"
            info "All resources have been deleted."
        else
            warn "Cleanup may still be in progress. Please check Azure portal for final status."
        fi
    else
        log "🎉 Cleanup initiated successfully!"
        info "Resource deletion is in progress. This may take several minutes to complete."
        info "Check the Azure portal to monitor deletion progress."
    fi
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may still be in the deletion process."; exit 1' INT TERM

# Show usage if help is requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [--dry-run] [--fast] [--help]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deleted without actually deleting resources"
    echo "  --fast       Delete resource group directly (faster but less granular)"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "Environment variables (optional):"
    echo "  RESOURCE_GROUP      Resource group name (default: rg-serverless-pipeline)"
    echo "  LOCATION            Azure region (default: eastus)"
    echo "  STORAGE_ACCOUNT     Storage account name (auto-discovered if not set)"
    echo "  SYNAPSE_WORKSPACE   Synapse workspace name (auto-discovered if not set)"
    echo "  DATA_FACTORY        Data factory name (auto-discovered if not set)"
    echo "  KEY_VAULT           Key vault name (auto-discovered if not set)"
    echo "  FORCE_DELETE        Skip confirmation prompts (default: false)"
    echo "  WAIT_FOR_COMPLETION Wait for all deletions to complete (default: false)"
    echo ""
    echo "Examples:"
    echo "  ./destroy.sh                    # Interactive cleanup with confirmation"
    echo "  ./destroy.sh --dry-run          # Show what would be deleted"
    echo "  ./destroy.sh --fast             # Fast cleanup (delete resource group directly)"
    echo "  FORCE_DELETE=true ./destroy.sh  # Skip confirmation prompts"
    echo "  WAIT_FOR_COMPLETION=true ./destroy.sh  # Wait for completion"
    exit 0
fi

# Run main function
main "$@"