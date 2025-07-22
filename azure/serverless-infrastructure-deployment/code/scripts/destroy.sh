#!/bin/bash

# Azure Container Apps Jobs Infrastructure Cleanup Script
# This script removes all resources created for automated infrastructure deployment workflows
# Author: Azure Recipe Generator
# Version: 1.0

set -e
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
CLEANUP_START_TIME=$(date +%s)

# Default configuration
DEFAULT_RESOURCE_GROUP="rg-deployment-automation"
DEFAULT_LOCATION="eastus"
DEFAULT_CONTAINER_APPS_ENV="cae-deployment-env"
DEFAULT_JOB_NAME="deployment-job"

# Configuration variables (can be overridden by environment variables)
RESOURCE_GROUP="${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"
LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
CONTAINER_APPS_ENV="${CONTAINER_APPS_ENV:-$DEFAULT_CONTAINER_APPS_ENV}"
JOB_NAME="${JOB_NAME:-$DEFAULT_JOB_NAME}"
KEY_VAULT_NAME="${KEY_VAULT_NAME:-}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_CONFIRMATIONS="${SKIP_CONFIRMATIONS:-false}"
FORCE_DELETE="${FORCE_DELETE:-false}"

# Arrays to track resources for cleanup
declare -a RESOURCES_TO_DELETE=()
declare -a FAILED_DELETIONS=()

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Info logging
info() {
    log "INFO" "${BLUE}$*${NC}"
}

# Success logging
success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

# Warning logging
warn() {
    log "WARNING" "${YELLOW}$*${NC}"
}

# Error logging
error() {
    log "ERROR" "${RED}$*${NC}"
}

# Fatal error (exit)
fatal() {
    error "$*"
    exit 1
}

# Progress indicator
show_progress() {
    local message="$1"
    echo -e "${BLUE}🗑️  ${message}...${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    info "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        fatal "Azure CLI is not installed. Please install Azure CLI v2.50.0 or later."
    fi
    
    # Check if user is logged in
    if ! az account show >/dev/null 2>&1; then
        fatal "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Get subscription ID if not provided
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    fi
    
    # Validate subscription
    if ! az account show --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
        fatal "Invalid subscription ID: $SUBSCRIPTION_ID"
    fi
    
    success "Prerequisites validation completed"
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    
    case "$resource_type" in
        "group")
            az group show --name "$resource_name" >/dev/null 2>&1
            ;;
        "keyvault")
            az keyvault show --name "$resource_name" >/dev/null 2>&1
            ;;
        "storage")
            az storage account show --name "$resource_name" --resource-group "$resource_group" >/dev/null 2>&1
            ;;
        "identity")
            az identity show --name "$resource_name" --resource-group "$resource_group" >/dev/null 2>&1
            ;;
        "containerapp-env")
            az containerapp env show --name "$resource_name" --resource-group "$resource_group" >/dev/null 2>&1
            ;;
        "containerapp-job")
            az containerapp job show --name "$resource_name" --resource-group "$resource_group" >/dev/null 2>&1
            ;;
        *)
            false
            ;;
    esac
}

# Discover existing resources
discover_resources() {
    info "Discovering existing resources..."
    
    # Check if resource group exists
    if ! resource_exists "group" "$RESOURCE_GROUP"; then
        warn "Resource group $RESOURCE_GROUP does not exist. Nothing to clean up."
        return 0
    fi
    
    # List all resources in the resource group
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{name:name,type:type}" --output tsv 2>/dev/null)
    
    if [[ -z "$resources" ]]; then
        warn "No resources found in resource group $RESOURCE_GROUP"
        return 0
    fi
    
    # Parse resources and build cleanup list
    while IFS=$'\t' read -r name type; do
        case "$type" in
            "Microsoft.ContainerApp/containerApps")
                RESOURCES_TO_DELETE+=("containerapp-job:$name")
                ;;
            "Microsoft.App/containerApps")
                RESOURCES_TO_DELETE+=("containerapp-job:$name")
                ;;
            "Microsoft.App/managedEnvironments")
                RESOURCES_TO_DELETE+=("containerapp-env:$name")
                ;;
            "Microsoft.KeyVault/vaults")
                RESOURCES_TO_DELETE+=("keyvault:$name")
                KEY_VAULT_NAME="$name"
                ;;
            "Microsoft.Storage/storageAccounts")
                RESOURCES_TO_DELETE+=("storage:$name")
                STORAGE_ACCOUNT="$name"
                ;;
            "Microsoft.ManagedIdentity/userAssignedIdentities")
                RESOURCES_TO_DELETE+=("identity:$name")
                ;;
        esac
    done <<< "$resources"
    
    # Add known resources if not discovered
    if resource_exists "containerapp-job" "$JOB_NAME" "$RESOURCE_GROUP"; then
        RESOURCES_TO_DELETE+=("containerapp-job:$JOB_NAME")
    fi
    
    if resource_exists "containerapp-job" "${JOB_NAME}-scheduled" "$RESOURCE_GROUP"; then
        RESOURCES_TO_DELETE+=("containerapp-job:${JOB_NAME}-scheduled")
    fi
    
    if resource_exists "containerapp-env" "$CONTAINER_APPS_ENV" "$RESOURCE_GROUP"; then
        RESOURCES_TO_DELETE+=("containerapp-env:$CONTAINER_APPS_ENV")
    fi
    
    # Remove duplicates
    local temp_array=()
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ ! " ${temp_array[@]} " =~ " ${resource} " ]]; then
            temp_array+=("$resource")
        fi
    done
    RESOURCES_TO_DELETE=("${temp_array[@]}")
    
    success "Discovered ${#RESOURCES_TO_DELETE[@]} resources to clean up"
}

# Clean up target resource group from deployments
cleanup_target_deployments() {
    info "Cleaning up target deployment resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would check for and clean up target deployments"
        return 0
    fi
    
    # Check if target resource group exists
    if resource_exists "group" "rg-deployment-target"; then
        show_progress "Deleting target deployment resource group"
        
        if [[ "$FORCE_DELETE" == "true" || "$SKIP_CONFIRMATIONS" == "true" ]]; then
            az group delete --name "rg-deployment-target" --yes --no-wait --output none 2>/dev/null || true
            success "Target deployment resource group deletion initiated"
        else
            read -p "Delete target deployment resource group 'rg-deployment-target'? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                az group delete --name "rg-deployment-target" --yes --no-wait --output none 2>/dev/null || true
                success "Target deployment resource group deletion initiated"
            else
                info "Skipping target deployment resource group deletion"
            fi
        fi
    else
        info "Target deployment resource group does not exist"
    fi
}

# Delete Container Apps Jobs
delete_container_apps_jobs() {
    info "Deleting Container Apps Jobs..."
    
    local jobs_to_delete=()
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" == containerapp-job:* ]]; then
            jobs_to_delete+=("${resource#containerapp-job:}")
        fi
    done
    
    if [[ ${#jobs_to_delete[@]} -eq 0 ]]; then
        info "No Container Apps Jobs to delete"
        return 0
    fi
    
    for job in "${jobs_to_delete[@]}"; do
        show_progress "Deleting Container Apps Job: $job"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete Container Apps Job: $job"
            continue
        fi
        
        if az containerapp job delete --name "$job" --resource-group "$RESOURCE_GROUP" --yes --output none 2>/dev/null; then
            success "✅ Container Apps Job deleted: $job"
        else
            error "❌ Failed to delete Container Apps Job: $job"
            FAILED_DELETIONS+=("containerapp-job:$job")
        fi
    done
}

# Delete Container Apps Environment
delete_container_apps_environment() {
    info "Deleting Container Apps Environment..."
    
    local environments_to_delete=()
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" == containerapp-env:* ]]; then
            environments_to_delete+=("${resource#containerapp-env:}")
        fi
    done
    
    if [[ ${#environments_to_delete[@]} -eq 0 ]]; then
        info "No Container Apps Environments to delete"
        return 0
    fi
    
    for env in "${environments_to_delete[@]}"; do
        show_progress "Deleting Container Apps Environment: $env"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete Container Apps Environment: $env"
            continue
        fi
        
        if az containerapp env delete --name "$env" --resource-group "$RESOURCE_GROUP" --yes --output none 2>/dev/null; then
            success "✅ Container Apps Environment deleted: $env"
        else
            error "❌ Failed to delete Container Apps Environment: $env"
            FAILED_DELETIONS+=("containerapp-env:$env")
        fi
    done
}

# Delete Storage Account
delete_storage_account() {
    info "Deleting Storage Account..."
    
    local storage_accounts_to_delete=()
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" == storage:* ]]; then
            storage_accounts_to_delete+=("${resource#storage:}")
        fi
    done
    
    if [[ ${#storage_accounts_to_delete[@]} -eq 0 ]]; then
        info "No Storage Accounts to delete"
        return 0
    fi
    
    for storage in "${storage_accounts_to_delete[@]}"; do
        show_progress "Deleting Storage Account: $storage"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete Storage Account: $storage"
            continue
        fi
        
        if az storage account delete --name "$storage" --resource-group "$RESOURCE_GROUP" --yes --output none 2>/dev/null; then
            success "✅ Storage Account deleted: $storage"
        else
            error "❌ Failed to delete Storage Account: $storage"
            FAILED_DELETIONS+=("storage:$storage")
        fi
    done
}

# Delete Key Vault
delete_key_vault() {
    info "Deleting Key Vault..."
    
    local key_vaults_to_delete=()
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" == keyvault:* ]]; then
            key_vaults_to_delete+=("${resource#keyvault:}")
        fi
    done
    
    if [[ ${#key_vaults_to_delete[@]} -eq 0 ]]; then
        info "No Key Vaults to delete"
        return 0
    fi
    
    for keyvault in "${key_vaults_to_delete[@]}"; do
        show_progress "Deleting Key Vault: $keyvault"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete Key Vault: $keyvault"
            continue
        fi
        
        if az keyvault delete --name "$keyvault" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
            success "✅ Key Vault deleted: $keyvault"
            
            # Purge the Key Vault to fully remove it
            if az keyvault purge --name "$keyvault" --output none 2>/dev/null; then
                success "✅ Key Vault purged: $keyvault"
            else
                warn "⚠️  Failed to purge Key Vault: $keyvault (may need manual cleanup)"
            fi
        else
            error "❌ Failed to delete Key Vault: $keyvault"
            FAILED_DELETIONS+=("keyvault:$keyvault")
        fi
    done
}

# Delete Managed Identity
delete_managed_identity() {
    info "Deleting Managed Identity..."
    
    local identities_to_delete=()
    for resource in "${RESOURCES_TO_DELETE[@]}"; do
        if [[ "$resource" == identity:* ]]; then
            identities_to_delete+=("${resource#identity:}")
        fi
    done
    
    if [[ ${#identities_to_delete[@]} -eq 0 ]]; then
        info "No Managed Identities to delete"
        return 0
    fi
    
    for identity in "${identities_to_delete[@]}"; do
        show_progress "Deleting Managed Identity: $identity"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would delete Managed Identity: $identity"
            continue
        fi
        
        if az identity delete --name "$identity" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
            success "✅ Managed Identity deleted: $identity"
        else
            error "❌ Failed to delete Managed Identity: $identity"
            FAILED_DELETIONS+=("identity:$identity")
        fi
    done
}

# Delete Resource Group
delete_resource_group() {
    info "Deleting Resource Group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete Resource Group: $RESOURCE_GROUP"
        return 0
    fi
    
    if ! resource_exists "group" "$RESOURCE_GROUP"; then
        info "Resource group $RESOURCE_GROUP does not exist"
        return 0
    fi
    
    show_progress "Deleting Resource Group: $RESOURCE_GROUP"
    
    if [[ "$FORCE_DELETE" == "true" || "$SKIP_CONFIRMATIONS" == "true" ]]; then
        if az group delete --name "$RESOURCE_GROUP" --yes --no-wait --output none 2>/dev/null; then
            success "✅ Resource Group deletion initiated: $RESOURCE_GROUP"
        else
            error "❌ Failed to delete Resource Group: $RESOURCE_GROUP"
            FAILED_DELETIONS+=("group:$RESOURCE_GROUP")
        fi
    else
        read -p "Delete entire resource group '$RESOURCE_GROUP'? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if az group delete --name "$RESOURCE_GROUP" --yes --no-wait --output none 2>/dev/null; then
                success "✅ Resource Group deletion initiated: $RESOURCE_GROUP"
            else
                error "❌ Failed to delete Resource Group: $RESOURCE_GROUP"
                FAILED_DELETIONS+=("group:$RESOURCE_GROUP")
            fi
        else
            info "Skipping Resource Group deletion"
        fi
    fi
}

# Wait for resource deletions to complete
wait_for_deletions() {
    info "Waiting for resource deletions to complete..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would wait for resource deletions"
        return 0
    fi
    
    local max_wait=300 # 5 minutes
    local wait_time=0
    local check_interval=10
    
    while [[ $wait_time -lt $max_wait ]]; do
        if ! resource_exists "group" "$RESOURCE_GROUP"; then
            success "✅ Resource group deletion completed"
            return 0
        fi
        
        info "Waiting for resource deletion... (${wait_time}s/${max_wait}s)"
        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done
    
    warn "⚠️  Resource deletion is taking longer than expected. Check Azure portal for status."
}

# Verify cleanup
verify_cleanup() {
    info "Verifying cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would verify cleanup"
        return 0
    fi
    
    # Check if resource group still exists
    if resource_exists "group" "$RESOURCE_GROUP"; then
        warn "⚠️  Resource group still exists: $RESOURCE_GROUP"
        
        # List remaining resources
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{name:name,type:type}" --output table 2>/dev/null)
        
        if [[ -n "$remaining_resources" ]]; then
            warn "Remaining resources:"
            echo "$remaining_resources"
        fi
    else
        success "✅ Resource group successfully deleted: $RESOURCE_GROUP"
    fi
    
    # Check target deployment resource group
    if resource_exists "group" "rg-deployment-target"; then
        info "Target deployment resource group still exists (deletion may be in progress)"
    else
        success "✅ Target deployment resource group cleaned up"
    fi
}

# Display cleanup summary
display_summary() {
    local cleanup_end_time=$(date +%s)
    local cleanup_duration=$((cleanup_end_time - CLEANUP_START_TIME))
    
    echo
    echo "=================================="
    echo "🗑️  CLEANUP COMPLETED"
    echo "=================================="
    echo
    echo "📋 Cleanup Summary:"
    echo "  • Resource Group: $RESOURCE_GROUP"
    echo "  • Resources Processed: ${#RESOURCES_TO_DELETE[@]}"
    echo "  • Failed Deletions: ${#FAILED_DELETIONS[@]}"
    echo "  • Cleanup Duration: ${cleanup_duration}s"
    echo
    
    if [[ ${#FAILED_DELETIONS[@]} -gt 0 ]]; then
        echo "❌ Failed to delete the following resources:"
        for resource in "${FAILED_DELETIONS[@]}"; do
            echo "  • $resource"
        done
        echo
        echo "Please manually clean up these resources in the Azure portal."
    else
        echo "✅ All resources successfully cleaned up!"
    fi
    
    echo
    echo "💡 Note: Resource group deletion may take a few minutes to complete."
    echo "   Check the Azure portal if you need to verify completion."
    echo
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Clean up Azure Container Apps Jobs infrastructure deployment"
    echo
    echo "Options:"
    echo "  -g, --resource-group NAME     Resource group name (default: $DEFAULT_RESOURCE_GROUP)"
    echo "  -l, --location LOCATION       Azure region (default: $DEFAULT_LOCATION)"
    echo "  -e, --environment NAME        Container Apps environment name (default: $DEFAULT_CONTAINER_APPS_ENV)"
    echo "  -j, --job-name NAME           Container Apps job name (default: $DEFAULT_JOB_NAME)"
    echo "  -k, --key-vault NAME          Key Vault name (auto-discovered if not provided)"
    echo "  -s, --storage-account NAME    Storage account name (auto-discovered if not provided)"
    echo "  -n, --dry-run                 Show what would be deleted without making changes"
    echo "  -y, --yes                     Skip confirmation prompts"
    echo "  -f, --force                   Force deletion without confirmations"
    echo "  -h, --help                    Show this help message"
    echo
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP                Resource group name"
    echo "  LOCATION                      Azure region"
    echo "  CONTAINER_APPS_ENV            Container Apps environment name"
    echo "  JOB_NAME                      Container Apps job name"
    echo "  KEY_VAULT_NAME                Key Vault name"
    echo "  STORAGE_ACCOUNT               Storage account name"
    echo "  SUBSCRIPTION_ID               Azure subscription ID"
    echo "  DRY_RUN                       Enable dry run mode (true/false)"
    echo "  SKIP_CONFIRMATIONS            Skip confirmation prompts (true/false)"
    echo "  FORCE_DELETE                  Force deletion without confirmations (true/false)"
    echo
    echo "Examples:"
    echo "  $0                            Clean up with default settings"
    echo "  $0 -g my-rg                   Clean up specific resource group"
    echo "  $0 --dry-run                  Show cleanup plan without executing"
    echo "  $0 -f                         Force cleanup without confirmations"
    echo
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -g|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -e|--environment)
                CONTAINER_APPS_ENV="$2"
                shift 2
                ;;
            -j|--job-name)
                JOB_NAME="$2"
                shift 2
                ;;
            -k|--key-vault)
                KEY_VAULT_NAME="$2"
                shift 2
                ;;
            -s|--storage-account)
                STORAGE_ACCOUNT="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATIONS="true"
                shift
                ;;
            -f|--force)
                FORCE_DELETE="true"
                SKIP_CONFIRMATIONS="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main cleanup function
main() {
    # Initialize log file
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Show banner
    echo "=================================="
    echo "Azure Container Apps Jobs Cleanup"
    echo "=================================="
    echo
    
    # Show configuration
    info "Configuration:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    info "  Container Apps Environment: $CONTAINER_APPS_ENV"
    info "  Job Name: $JOB_NAME"
    info "  Dry Run: $DRY_RUN"
    info "  Force Delete: $FORCE_DELETE"
    echo
    
    # Final confirmation
    if [[ "$DRY_RUN" != "true" && "$FORCE_DELETE" != "true" && "$SKIP_CONFIRMATIONS" != "true" ]]; then
        echo "⚠️  WARNING: This will permanently delete all resources in the resource group!"
        echo "   This action cannot be undone."
        echo
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute cleanup steps
    validate_prerequisites
    discover_resources
    cleanup_target_deployments
    delete_container_apps_jobs
    delete_container_apps_environment
    delete_storage_account
    delete_key_vault
    delete_managed_identity
    delete_resource_group
    wait_for_deletions
    verify_cleanup
    display_summary
    
    if [[ ${#FAILED_DELETIONS[@]} -gt 0 ]]; then
        error "Cleanup completed with some failures. Check $LOG_FILE for details."
        exit 1
    else
        success "🎉 Cleanup completed successfully!"
    fi
}

# Handle script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        error "Cleanup failed. Check $LOG_FILE for details."
        echo "Some resources may need manual cleanup in the Azure portal."
    fi
}

# Set up signal handlers
trap cleanup_on_exit EXIT

# Run main function
main "$@"