#!/bin/bash

# Azure Multi-Database ETL Orchestration Cleanup Script
# This script removes all resources created for the Azure Data Factory ETL orchestration solution
# including Data Factory, MySQL server, Key Vault, and monitoring components

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Script usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group    Resource group name (default: rg-etl-orchestration)"
    echo "  -f, --force             Skip confirmation prompts"
    echo "  -d, --dry-run           Show what would be deleted without actually deleting"
    echo "  -v, --verbose           Enable verbose output"
    echo "  -k, --keep-keyvault     Keep Key Vault (disable purge protection first)"
    echo "  -s, --skip-prereqs      Skip prerequisites check"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  ADF_NAME               Data Factory name (auto-discovered if not set)"
    echo "  MYSQL_SERVER_NAME      MySQL server name (auto-discovered if not set)"
    echo "  KEY_VAULT_NAME         Key Vault name (auto-discovered if not set)"
    echo "  LOG_ANALYTICS_NAME     Log Analytics workspace name (auto-discovered if not set)"
    echo ""
    echo "Example:"
    echo "  $0 -g my-resource-group -f"
    echo "  $0 --dry-run --resource-group my-resource-group"
}

# Default values
RESOURCE_GROUP="rg-etl-orchestration"
FORCE=false
DRY_RUN=false
VERBOSE=false
KEEP_KEYVAULT=false
SKIP_PREREQS=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -k|--keep-keyvault)
            KEEP_KEYVAULT=true
            shift
            ;;
        -s|--skip-prereqs)
            SKIP_PREREQS=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Enable verbose output if requested
if [ "$VERBOSE" = true ]; then
    set -x
fi

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group '$RESOURCE_GROUP' does not exist"
    fi
    
    log "Prerequisites check completed successfully"
}

# Discover resource names if not provided
discover_resources() {
    log "Discovering resources in resource group: $RESOURCE_GROUP"
    
    # Discover Data Factory
    if [ -z "${ADF_NAME:-}" ]; then
        ADF_NAME=$(az datafactory list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[?contains(name, 'adf-etl')].name" \
            --output tsv | head -1)
    fi
    
    # Discover MySQL server
    if [ -z "${MYSQL_SERVER_NAME:-}" ]; then
        MYSQL_SERVER_NAME=$(az mysql flexible-server list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[?contains(name, 'mysql-target')].name" \
            --output tsv | head -1)
    fi
    
    # Discover Key Vault
    if [ -z "${KEY_VAULT_NAME:-}" ]; then
        KEY_VAULT_NAME=$(az keyvault list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[?contains(name, 'kv-etl')].name" \
            --output tsv | head -1)
    fi
    
    # Discover Log Analytics workspace
    if [ -z "${LOG_ANALYTICS_NAME:-}" ]; then
        LOG_ANALYTICS_NAME=$(az monitor log-analytics workspace list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[?contains(name, 'la-etl')].name" \
            --output tsv | head -1)
    fi
    
    log "Discovered resources:"
    log "  Data Factory: ${ADF_NAME:-'Not found'}"
    log "  MySQL Server: ${MYSQL_SERVER_NAME:-'Not found'}"
    log "  Key Vault: ${KEY_VAULT_NAME:-'Not found'}"
    log "  Log Analytics: ${LOG_ANALYTICS_NAME:-'Not found'}"
}

# Confirm deletion
confirm_deletion() {
    if [ "$FORCE" = true ] || [ "$DRY_RUN" = true ]; then
        return
    fi
    
    warn "This will permanently delete the following resources:"
    warn "  Resource Group: $RESOURCE_GROUP"
    warn "  Data Factory: ${ADF_NAME:-'Not found'}"
    warn "  MySQL Server: ${MYSQL_SERVER_NAME:-'Not found'}"
    warn "  Key Vault: ${KEY_VAULT_NAME:-'Not found'}"
    warn "  Log Analytics: ${LOG_ANALYTICS_NAME:-'Not found'}"
    warn ""
    warn "This action cannot be undone!"
    warn ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
}

# Stop Data Factory triggers
stop_datafactory_triggers() {
    if [ -z "${ADF_NAME:-}" ]; then
        warn "Data Factory not found, skipping trigger cleanup"
        return
    fi
    
    log "Stopping Data Factory triggers..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would stop Data Factory triggers"
        return
    fi
    
    # Get all active triggers
    TRIGGERS=$(az datafactory trigger list \
        --resource-group "$RESOURCE_GROUP" \
        --factory-name "$ADF_NAME" \
        --query "[?properties.runtimeState=='Started'].name" \
        --output tsv)
    
    if [ -n "$TRIGGERS" ]; then
        for trigger in $TRIGGERS; do
            log "Stopping trigger: $trigger"
            az datafactory trigger stop \
                --resource-group "$RESOURCE_GROUP" \
                --factory-name "$ADF_NAME" \
                --name "$trigger" \
                --output none || warn "Failed to stop trigger: $trigger"
        done
    else
        log "No active triggers found"
    fi
}

# Delete Data Factory integration runtime
delete_integration_runtime() {
    if [ -z "${ADF_NAME:-}" ]; then
        warn "Data Factory not found, skipping integration runtime cleanup"
        return
    fi
    
    log "Deleting Data Factory integration runtime..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete integration runtime"
        return
    fi
    
    # Delete self-hosted integration runtime
    az datafactory integration-runtime delete \
        --resource-group "$RESOURCE_GROUP" \
        --factory-name "$ADF_NAME" \
        --name "SelfHostedIR" \
        --yes \
        --output none || warn "Failed to delete integration runtime"
    
    log "Integration runtime deleted successfully"
}

# Delete metric alerts
delete_metric_alerts() {
    log "Deleting metric alerts..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete metric alerts"
        return
    fi
    
    # Delete pipeline failure alert
    az monitor metrics alert delete \
        --name "ETL-Pipeline-Failure-Alert" \
        --resource-group "$RESOURCE_GROUP" \
        --yes \
        --output none || warn "Failed to delete metric alert"
    
    log "Metric alerts deleted successfully"
}

# Delete Data Factory
delete_data_factory() {
    if [ -z "${ADF_NAME:-}" ]; then
        warn "Data Factory not found, skipping deletion"
        return
    fi
    
    log "Deleting Data Factory: $ADF_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete Data Factory $ADF_NAME"
        return
    fi
    
    az datafactory delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ADF_NAME" \
        --yes \
        --output none || warn "Failed to delete Data Factory"
    
    log "Data Factory deleted successfully"
}

# Delete MySQL server
delete_mysql_server() {
    if [ -z "${MYSQL_SERVER_NAME:-}" ]; then
        warn "MySQL server not found, skipping deletion"
        return
    fi
    
    log "Deleting MySQL server: $MYSQL_SERVER_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete MySQL server $MYSQL_SERVER_NAME"
        return
    fi
    
    az mysql flexible-server delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$MYSQL_SERVER_NAME" \
        --yes \
        --output none || warn "Failed to delete MySQL server"
    
    log "MySQL server deleted successfully"
}

# Delete Key Vault
delete_key_vault() {
    if [ -z "${KEY_VAULT_NAME:-}" ]; then
        warn "Key Vault not found, skipping deletion"
        return
    fi
    
    if [ "$KEEP_KEYVAULT" = true ]; then
        warn "Keeping Key Vault as requested: $KEY_VAULT_NAME"
        return
    fi
    
    log "Deleting Key Vault: $KEY_VAULT_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete Key Vault $KEY_VAULT_NAME"
        return
    fi
    
    # Disable purge protection first
    az keyvault update \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --enable-purge-protection false \
        --output none || warn "Failed to disable purge protection"
    
    # Delete Key Vault
    az keyvault delete \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --output none || warn "Failed to delete Key Vault"
    
    # Purge Key Vault permanently
    az keyvault purge \
        --name "$KEY_VAULT_NAME" \
        --location "$LOCATION" \
        --output none || warn "Failed to purge Key Vault"
    
    log "Key Vault deleted and purged successfully"
}

# Delete Log Analytics workspace
delete_log_analytics() {
    if [ -z "${LOG_ANALYTICS_NAME:-}" ]; then
        warn "Log Analytics workspace not found, skipping deletion"
        return
    fi
    
    log "Deleting Log Analytics workspace: $LOG_ANALYTICS_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete Log Analytics workspace $LOG_ANALYTICS_NAME"
        return
    fi
    
    az monitor log-analytics workspace delete \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --yes \
        --output none || warn "Failed to delete Log Analytics workspace"
    
    log "Log Analytics workspace deleted successfully"
}

# Delete entire resource group
delete_resource_group() {
    log "Deleting resource group: $RESOURCE_GROUP"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would delete resource group $RESOURCE_GROUP"
        return
    fi
    
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none || error "Failed to delete resource group"
    
    log "Resource group deletion initiated (running in background)"
}

# Wait for resource group deletion
wait_for_deletion() {
    if [ "$DRY_RUN" = true ]; then
        return
    fi
    
    log "Waiting for resource group deletion to complete..."
    
    local timeout=1800  # 30 minutes
    local elapsed=0
    local interval=30
    
    while [ $elapsed -lt $timeout ]; do
        if ! az group exists --name "$RESOURCE_GROUP" --output none; then
            log "Resource group deleted successfully"
            return
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        info "Still waiting for deletion... ($elapsed/${timeout}s)"
    done
    
    warn "Resource group deletion is taking longer than expected"
    warn "Check the Azure portal for deletion status"
}

# Verify deletion
verify_deletion() {
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would verify resource deletion"
        return
    fi
    
    log "Verifying resource deletion..."
    
    # Check if resource group exists
    if az group exists --name "$RESOURCE_GROUP" --output none; then
        warn "Resource group still exists: $RESOURCE_GROUP"
        info "Deletion may still be in progress"
    else
        log "Resource group successfully deleted: $RESOURCE_GROUP"
    fi
}

# Output cleanup summary
output_summary() {
    log "Cleanup Summary:"
    log "================"
    log "Resource Group: $RESOURCE_GROUP"
    log "Data Factory: ${ADF_NAME:-'Not found'}"
    log "MySQL Server: ${MYSQL_SERVER_NAME:-'Not found'}"
    log "Key Vault: ${KEY_VAULT_NAME:-'Not found'} ${KEEP_KEYVAULT:+(kept)}"
    log "Log Analytics: ${LOG_ANALYTICS_NAME:-'Not found'}"
    log ""
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: No resources were actually deleted"
    else
        log "Cleanup completed successfully"
        log "All resources have been deleted"
    fi
}

# Main cleanup function
main() {
    log "Starting Azure Multi-Database ETL Orchestration cleanup..."
    
    # Check prerequisites unless skipped
    if [ "$SKIP_PREREQS" = false ]; then
        check_prerequisites
    fi
    
    # Discover resources
    discover_resources
    
    # Confirm deletion
    confirm_deletion
    
    # Stop and delete resources in proper order
    stop_datafactory_triggers
    delete_integration_runtime
    delete_metric_alerts
    delete_data_factory
    delete_mysql_server
    
    # Delete Key Vault if not keeping it
    if [ "$KEEP_KEYVAULT" = false ]; then
        delete_key_vault
    fi
    
    delete_log_analytics
    delete_resource_group
    
    # Wait for deletion and verify
    wait_for_deletion
    verify_deletion
    
    # Output summary
    output_summary
    
    log "Cleanup completed successfully!"
}

# Handle script interruption
cleanup_on_error() {
    error "Script interrupted. Some resources may still exist."
    error "Run this script again to continue cleanup."
    exit 1
}

# Set up signal handling
trap cleanup_on_error INT TERM

# Run main function
main "$@"