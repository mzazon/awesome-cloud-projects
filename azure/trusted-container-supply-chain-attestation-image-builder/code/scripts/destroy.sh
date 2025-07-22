#!/bin/bash

# =============================================================================
# Azure Trusted Container Supply Chain Cleanup Script
# =============================================================================
# This script removes all resources created by the deployment script
# for the trusted container supply chain infrastructure
# 
# Prerequisites:
# - Azure CLI installed and configured
# - Appropriate Azure subscription permissions
# - Previous deployment using the deploy.sh script
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration and Variables
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo -e "$message" | tee -a "$LOG_FILE"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

error_exit() {
    log "ERROR" "$1"
    exit 1
}

warning_continue() {
    log "WARN" "$1"
    return 0
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI first."
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    log "INFO" "Prerequisites check passed."
}

load_deployment_state() {
    local key="$1"
    
    if [ -f "$DEPLOYMENT_STATE_FILE" ]; then
        grep "^$key=" "$DEPLOYMENT_STATE_FILE" | cut -d'=' -f2 || echo ""
    else
        echo ""
    fi
}

confirm_destruction() {
    local resource_group="$1"
    
    echo
    log "WARN" "======================================================"
    log "WARN" "WARNING: This will permanently delete all resources"
    log "WARN" "in the resource group: $resource_group"
    log "WARN" "======================================================"
    echo
    
    # List resources that will be deleted
    log "INFO" "The following resources will be deleted:"
    
    if az group show --name "$resource_group" &> /dev/null; then
        az resource list --resource-group "$resource_group" --output table
    else
        log "WARN" "Resource group $resource_group does not exist or is not accessible."
    fi
    
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "INFO" "Cleanup cancelled by user."
        exit 0
    fi
    
    log "INFO" "Proceeding with resource cleanup..."
}

# =============================================================================
# Azure Resource Cleanup Functions
# =============================================================================

cleanup_image_builder_template() {
    local template_name="$1"
    local rg_name="$2"
    
    log "INFO" "Cleaning up Image Builder template: $template_name"
    
    if az resource show \
        --resource-group "$rg_name" \
        --resource-type "Microsoft.VirtualMachineImages/imageTemplates" \
        --name "$template_name" &> /dev/null; then
        
        # Cancel any running builds first
        log "INFO" "Cancelling any running Image Builder builds..."
        
        local build_status=$(az resource show \
            --resource-group "$rg_name" \
            --resource-type "Microsoft.VirtualMachineImages/imageTemplates" \
            --name "$template_name" \
            --api-version "2024-02-01" \
            --query 'properties.lastRunStatus.runState' \
            --output tsv 2>/dev/null || echo "")
        
        if [ "$build_status" = "Running" ]; then
            log "INFO" "Image build is currently running. Attempting to cancel..."
            
            az resource invoke-action \
                --resource-group "$rg_name" \
                --resource-type "Microsoft.VirtualMachineImages/imageTemplates" \
                --name "$template_name" \
                --api-version "2024-02-01" \
                --action Cancel \
                --output none || warning_continue "Failed to cancel running build"
            
            # Wait for cancellation to complete
            log "INFO" "Waiting for build cancellation to complete..."
            sleep 30
        fi
        
        # Delete the template
        az resource delete \
            --resource-group "$rg_name" \
            --resource-type "Microsoft.VirtualMachineImages/imageTemplates" \
            --name "$template_name" \
            --api-version "2024-02-01" \
            --output none
        
        if [ $? -eq 0 ]; then
            log "INFO" "Image Builder template $template_name deleted successfully."
        else
            warning_continue "Failed to delete Image Builder template $template_name."
        fi
    else
        log "INFO" "Image Builder template $template_name does not exist."
    fi
}

cleanup_attestation_provider() {
    local provider_name="$1"
    local rg_name="$2"
    
    log "INFO" "Cleaning up attestation provider: $provider_name"
    
    if az attestation show --name "$provider_name" --resource-group "$rg_name" &> /dev/null; then
        az attestation delete \
            --name "$provider_name" \
            --resource-group "$rg_name" \
            --yes \
            --output none
        
        if [ $? -eq 0 ]; then
            log "INFO" "Attestation provider $provider_name deleted successfully."
        else
            warning_continue "Failed to delete attestation provider $provider_name."
        fi
    else
        log "INFO" "Attestation provider $provider_name does not exist."
    fi
}

cleanup_key_vault() {
    local kv_name="$1"
    local rg_name="$2"
    local location="$3"
    
    log "INFO" "Cleaning up Key Vault: $kv_name"
    
    if az keyvault show --name "$kv_name" --resource-group "$rg_name" &> /dev/null; then
        # Delete Key Vault (soft delete enabled by default)
        az keyvault delete \
            --name "$kv_name" \
            --resource-group "$rg_name" \
            --output none
        
        if [ $? -eq 0 ]; then
            log "INFO" "Key Vault $kv_name deleted successfully."
            
            # Purge Key Vault to completely remove it
            log "INFO" "Purging Key Vault to completely remove it..."
            
            az keyvault purge \
                --name "$kv_name" \
                --location "$location" \
                --output none
            
            if [ $? -eq 0 ]; then
                log "INFO" "Key Vault $kv_name purged successfully."
            else
                warning_continue "Failed to purge Key Vault $kv_name. You may need to purge it manually."
            fi
        else
            warning_continue "Failed to delete Key Vault $kv_name."
        fi
    else
        log "INFO" "Key Vault $kv_name does not exist."
    fi
}

cleanup_container_registry() {
    local acr_name="$1"
    local rg_name="$2"
    
    log "INFO" "Cleaning up Container Registry: $acr_name"
    
    if az acr show --name "$acr_name" --resource-group "$rg_name" &> /dev/null; then
        # List and delete all repositories first
        log "INFO" "Deleting all repositories in Container Registry..."
        
        local repositories=$(az acr repository list --name "$acr_name" --output tsv 2>/dev/null || echo "")
        
        if [ -n "$repositories" ]; then
            for repo in $repositories; do
                log "INFO" "Deleting repository: $repo"
                az acr repository delete \
                    --name "$acr_name" \
                    --repository "$repo" \
                    --yes \
                    --output none || warning_continue "Failed to delete repository $repo"
            done
        fi
        
        # Delete the registry
        az acr delete \
            --name "$acr_name" \
            --resource-group "$rg_name" \
            --yes \
            --output none
        
        if [ $? -eq 0 ]; then
            log "INFO" "Container Registry $acr_name deleted successfully."
        else
            warning_continue "Failed to delete Container Registry $acr_name."
        fi
    else
        log "INFO" "Container Registry $acr_name does not exist."
    fi
}

cleanup_managed_identity() {
    local identity_name="$1"
    local rg_name="$2"
    
    log "INFO" "Cleaning up managed identity: $identity_name"
    
    if az identity show --name "$identity_name" --resource-group "$rg_name" &> /dev/null; then
        # Get identity details for role assignment cleanup
        local identity_principal_id=$(az identity show \
            --name "$identity_name" \
            --resource-group "$rg_name" \
            --query principalId \
            --output tsv)
        
        # Clean up role assignments
        log "INFO" "Cleaning up role assignments for managed identity..."
        
        local assignments=$(az role assignment list \
            --assignee "$identity_principal_id" \
            --output tsv \
            --query '[].id' 2>/dev/null || echo "")
        
        if [ -n "$assignments" ]; then
            for assignment in $assignments; do
                log "INFO" "Deleting role assignment: $assignment"
                az role assignment delete \
                    --ids "$assignment" \
                    --output none || warning_continue "Failed to delete role assignment $assignment"
            done
        fi
        
        # Delete the managed identity
        az identity delete \
            --name "$identity_name" \
            --resource-group "$rg_name" \
            --output none
        
        if [ $? -eq 0 ]; then
            log "INFO" "Managed identity $identity_name deleted successfully."
        else
            warning_continue "Failed to delete managed identity $identity_name."
        fi
    else
        log "INFO" "Managed identity $identity_name does not exist."
    fi
}

cleanup_resource_group() {
    local rg_name="$1"
    local force_delete="$2"
    
    log "INFO" "Cleaning up resource group: $rg_name"
    
    if az group show --name "$rg_name" &> /dev/null; then
        if [ "$force_delete" = "true" ]; then
            log "INFO" "Force deleting entire resource group..."
            
            az group delete \
                --name "$rg_name" \
                --yes \
                --no-wait \
                --output none
            
            if [ $? -eq 0 ]; then
                log "INFO" "Resource group $rg_name deletion initiated."
                log "INFO" "Note: Resource group deletion may take several minutes to complete."
            else
                warning_continue "Failed to delete resource group $rg_name."
            fi
        else
            # Check if resource group is empty
            local resource_count=$(az resource list --resource-group "$rg_name" --query 'length(@)' --output tsv)
            
            if [ "$resource_count" = "0" ]; then
                log "INFO" "Resource group is empty. Deleting..."
                
                az group delete \
                    --name "$rg_name" \
                    --yes \
                    --no-wait \
                    --output none
                
                if [ $? -eq 0 ]; then
                    log "INFO" "Resource group $rg_name deletion initiated."
                else
                    warning_continue "Failed to delete resource group $rg_name."
                fi
            else
                log "WARN" "Resource group $rg_name still contains $resource_count resources."
                log "WARN" "Use --force to delete the entire resource group."
            fi
        fi
    else
        log "INFO" "Resource group $rg_name does not exist."
    fi
}

cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    # List of files to clean up
    local files_to_clean=(
        "$SCRIPT_DIR/sign-image.sh"
        "$SCRIPT_DIR/verify-deployment.sh"
        "$SCRIPT_DIR/image-template.json"
        "$SCRIPT_DIR/attestation-policy.txt"
        "$SCRIPT_DIR/container-policy.json"
    )
    
    for file in "${files_to_clean[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "INFO" "Deleted local file: $(basename "$file")"
        fi
    done
    
    # Clean up deployment state file
    if [ -f "$DEPLOYMENT_STATE_FILE" ]; then
        rm -f "$DEPLOYMENT_STATE_FILE"
        log "INFO" "Deleted deployment state file."
    fi
    
    log "INFO" "Local files cleanup completed."
}

# =============================================================================
# Main Cleanup Function
# =============================================================================

cleanup_infrastructure() {
    local force_delete="${1:-false}"
    local skip_confirmation="${2:-false}"
    
    log "INFO" "Starting trusted container supply chain cleanup..."
    
    # Check if deployment state file exists
    if [ ! -f "$DEPLOYMENT_STATE_FILE" ]; then
        log "WARN" "No deployment state file found. This may indicate no previous deployment."
        log "WARN" "Attempting to proceed with manual resource group cleanup..."
        
        read -p "Enter the resource group name to clean up: " -r RESOURCE_GROUP
        
        if [ -z "$RESOURCE_GROUP" ]; then
            error_exit "No resource group specified. Exiting."
        fi
    else
        # Load deployment state
        local resource_group=$(load_deployment_state "RESOURCE_GROUP")
        local location=$(load_deployment_state "LOCATION")
        local attestation_provider=$(load_deployment_state "ATTESTATION_PROVIDER")
        local image_builder_name=$(load_deployment_state "IMAGE_BUILDER_NAME")
        local acr_name=$(load_deployment_state "ACR_NAME")
        local key_vault_name=$(load_deployment_state "KEY_VAULT_NAME")
        local managed_identity=$(load_deployment_state "MANAGED_IDENTITY")
        
        if [ -z "$resource_group" ]; then
            error_exit "Could not load resource group from deployment state."
        fi
        
        log "INFO" "Loaded deployment state:"
        log "INFO" "Resource Group: $resource_group"
        log "INFO" "Location: $location"
        log "INFO" "Attestation Provider: $attestation_provider"
        log "INFO" "Image Builder: $image_builder_name"
        log "INFO" "Container Registry: $acr_name"
        log "INFO" "Key Vault: $key_vault_name"
        log "INFO" "Managed Identity: $managed_identity"
    fi
    
    # Confirm destruction unless skipped
    if [ "$skip_confirmation" != "true" ]; then
        confirm_destruction "$resource_group"
    fi
    
    # If force delete is enabled, just delete the entire resource group
    if [ "$force_delete" = "true" ]; then
        cleanup_resource_group "$resource_group" "true"
        cleanup_local_files
        
        log "INFO" "Force cleanup completed!"
        log "INFO" "Resource group deletion initiated: $resource_group"
        log "INFO" "Note: It may take several minutes for the deletion to complete."
        return 0
    fi
    
    # Individual resource cleanup (reverse order of creation)
    if [ -n "$image_builder_name" ]; then
        cleanup_image_builder_template "$image_builder_name" "$resource_group"
    fi
    
    if [ -n "$attestation_provider" ]; then
        cleanup_attestation_provider "$attestation_provider" "$resource_group"
    fi
    
    if [ -n "$key_vault_name" ]; then
        cleanup_key_vault "$key_vault_name" "$resource_group" "$location"
    fi
    
    if [ -n "$acr_name" ]; then
        cleanup_container_registry "$acr_name" "$resource_group"
    fi
    
    if [ -n "$managed_identity" ]; then
        cleanup_managed_identity "$managed_identity" "$resource_group"
    fi
    
    # Clean up resource group if it's empty
    cleanup_resource_group "$resource_group" "false"
    
    # Clean up local files
    cleanup_local_files
    
    log "INFO" "Cleanup completed successfully!"
    log "INFO" "All resources have been removed."
}

# =============================================================================
# Script Usage and Help
# =============================================================================

show_help() {
    cat << EOF
Azure Trusted Container Supply Chain Cleanup Script

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -f, --force             Force delete entire resource group without individual cleanup
    -y, --yes               Skip confirmation prompts
    -v, --verbose           Enable verbose logging
    --dry-run              Show what would be deleted without actually deleting

EXAMPLES:
    $0                      # Interactive cleanup with confirmation
    $0 --force              # Force delete entire resource group
    $0 --yes                # Skip confirmation prompts
    $0 --force --yes        # Force delete without confirmation
    $0 --dry-run            # Show what would be deleted

NOTES:
    - This script reads deployment state from .deployment_state file
    - If no state file exists, you'll be prompted for resource group name
    - Use --force for faster cleanup of entire resource group
    - Individual resource cleanup is safer but slower

WARNING:
    This script will permanently delete all resources created by the deployment script.
    Make sure you have backed up any important data before running this script.

For more information, see the recipe documentation.
EOF
}

# =============================================================================
# Main Script Logic
# =============================================================================

# Initialize logging
mkdir -p "$(dirname "$LOG_FILE")"
echo "Cleanup started at $(date)" > "$LOG_FILE"

# Parse command line options
VERBOSE=false
FORCE=false
SKIP_CONFIRMATION=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -*)
            error_exit "Unknown option: $1"
            ;;
        *)
            error_exit "Unexpected argument: $1"
            ;;
    esac
done

log "INFO" "Starting cleanup with options: Force=$FORCE, Skip Confirmation=$SKIP_CONFIRMATION, Dry Run=$DRY_RUN"

# Check if this is a dry run
if [ "$DRY_RUN" = true ]; then
    log "INFO" "DRY RUN MODE - No resources will be deleted"
    
    if [ -f "$DEPLOYMENT_STATE_FILE" ]; then
        log "INFO" "Would delete the following resources:"
        log "INFO" "Resource Group: $(load_deployment_state "RESOURCE_GROUP")"
        log "INFO" "Location: $(load_deployment_state "LOCATION")"
        log "INFO" "Attestation Provider: $(load_deployment_state "ATTESTATION_PROVIDER")"
        log "INFO" "Image Builder: $(load_deployment_state "IMAGE_BUILDER_NAME")"
        log "INFO" "Container Registry: $(load_deployment_state "ACR_NAME")"
        log "INFO" "Key Vault: $(load_deployment_state "KEY_VAULT_NAME")"
        log "INFO" "Managed Identity: $(load_deployment_state "MANAGED_IDENTITY")"
        log "INFO" "Local files: sign-image.sh, verify-deployment.sh, etc."
    else
        log "INFO" "No deployment state file found. Would prompt for resource group name."
    fi
    
    exit 0
fi

# Check prerequisites
check_prerequisites

# Run cleanup
cleanup_infrastructure "$FORCE" "$SKIP_CONFIRMATION"

log "INFO" "Cleanup script completed successfully!"
log "INFO" "Check the log file for details: $LOG_FILE"