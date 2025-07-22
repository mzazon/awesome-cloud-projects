#!/bin/bash

#==============================================================================
# Azure Storage Mover and Azure Monitor Cleanup Script
# 
# This script safely removes all Azure resources created by the deployment script
# for the Azure Storage Mover and Monitor recipe.
#
# Recipe: Multi-Cloud Data Migration with Azure Storage Mover and Azure Monitor
# Author: Azure Recipe Generator
# Version: 1.0
#==============================================================================

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

#==============================================================================
# Configuration Variables
#==============================================================================

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Deployment state file
STATE_FILE="${PROJECT_ROOT}/deployment_state.json"

# Default values (can be overridden)
RESOURCE_GROUP="${RESOURCE_GROUP:-}"
LOCATION="${LOCATION:-}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-}"
STORAGE_MOVER_NAME="${STORAGE_MOVER_NAME:-}"
LOG_WORKSPACE_NAME="${LOG_WORKSPACE_NAME:-}"
LOGIC_APP_NAME="${LOGIC_APP_NAME:-}"
FORCE_DELETE="${FORCE_DELETE:-false}"
DELETE_RESOURCE_GROUP="${DELETE_RESOURCE_GROUP:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

#==============================================================================
# Utility Functions
#==============================================================================

# Check if required tools are installed
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/"
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check subscription
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    info "Using subscription: $subscription_name ($subscription_id)"
    
    log "Prerequisites check completed successfully"
}

# Load deployment state
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        log "Loading deployment state from: $STATE_FILE"
        
        # Extract values from state file
        if command -v jq &> /dev/null; then
            RESOURCE_GROUP=$(jq -r '.resource_group' "$STATE_FILE")
            LOCATION=$(jq -r '.location' "$STATE_FILE")
            STORAGE_ACCOUNT_NAME=$(jq -r '.storage_account_name' "$STATE_FILE")
            STORAGE_MOVER_NAME=$(jq -r '.storage_mover_name' "$STATE_FILE")
            LOG_WORKSPACE_NAME=$(jq -r '.log_workspace_name' "$STATE_FILE")
            LOGIC_APP_NAME=$(jq -r '.logic_app_name' "$STATE_FILE")
        else
            warn "jq not available. Please set environment variables manually."
            return 1
        fi
        
        info "Loaded configuration from state file"
        return 0
    else
        warn "No deployment state file found at: $STATE_FILE"
        return 1
    fi
}

# Validate configuration
validate_configuration() {
    log "Validating configuration..."
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        error "Resource group name is required. Set RESOURCE_GROUP environment variable or use --resource-group"
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group $RESOURCE_GROUP does not exist"
    fi
    
    log "Configuration validation completed"
}

# Confirm deletion
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "=================================="
    echo "DELETION CONFIRMATION"
    echo "=================================="
    echo "This will DELETE the following resources:"
    echo "Resource Group: $RESOURCE_GROUP"
    
    if [[ -n "$STORAGE_ACCOUNT_NAME" ]]; then
        echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    fi
    
    if [[ -n "$STORAGE_MOVER_NAME" ]]; then
        echo "Storage Mover: $STORAGE_MOVER_NAME"
    fi
    
    if [[ -n "$LOG_WORKSPACE_NAME" ]]; then
        echo "Log Analytics Workspace: $LOG_WORKSPACE_NAME"
    fi
    
    if [[ -n "$LOGIC_APP_NAME" ]]; then
        echo "Logic App: $LOGIC_APP_NAME"
    fi
    
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        echo ""
        echo "⚠️  WARNING: This will DELETE the entire resource group and ALL resources within it!"
    fi
    
    echo ""
    echo "This action cannot be undone!"
    echo "=================================="
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to continue): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed by user"
}

# Stop running migration jobs
stop_migration_jobs() {
    if [[ -z "$STORAGE_MOVER_NAME" ]]; then
        warn "Storage Mover name not available, skipping job termination"
        return 0
    fi
    
    log "Stopping running migration jobs..."
    
    # Note: This is a placeholder for when Storage Mover CLI commands are available
    # Currently, Azure Storage Mover may not have full CLI support for job management
    if az storage-mover --help &> /dev/null; then
        # Try to list and stop jobs
        info "Checking for running migration jobs..."
        
        # This would be the actual command structure when available:
        # az storage-mover job list --resource-group "$RESOURCE_GROUP" --storage-mover-name "$STORAGE_MOVER_NAME"
        
        warn "Storage Mover CLI commands may not be fully available yet. Please stop any running jobs manually through the Azure portal."
    else
        warn "Storage Mover CLI commands not available. Please stop any running jobs manually through the Azure portal."
    fi
}

# Delete Azure Monitor alerts
delete_monitor_alerts() {
    log "Deleting Azure Monitor alerts..."
    
    local action_group_name="migration-alerts"
    
    # Delete metric alerts
    local alert_names=("migration-job-failure" "migration-job-success")
    
    for alert_name in "${alert_names[@]}"; do
        if az monitor metrics alert show --resource-group "$RESOURCE_GROUP" --name "$alert_name" &> /dev/null; then
            info "Deleting alert: $alert_name"
            az monitor metrics alert delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$alert_name" \
                --yes
        else
            info "Alert $alert_name not found or already deleted"
        fi
    done
    
    # Delete action group
    if az monitor action-group show --resource-group "$RESOURCE_GROUP" --name "$action_group_name" &> /dev/null; then
        info "Deleting action group: $action_group_name"
        az monitor action-group delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$action_group_name" \
            --yes
    else
        info "Action group $action_group_name not found or already deleted"
    fi
    
    log "Azure Monitor alerts deletion completed"
}

# Delete Logic App
delete_logic_app() {
    if [[ -z "$LOGIC_APP_NAME" ]]; then
        warn "Logic App name not available, skipping deletion"
        return 0
    fi
    
    log "Deleting Logic App: $LOGIC_APP_NAME"
    
    if az logic app show --resource-group "$RESOURCE_GROUP" --name "$LOGIC_APP_NAME" &> /dev/null; then
        az logic app delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$LOGIC_APP_NAME" \
            --yes
        
        info "Logic App $LOGIC_APP_NAME deleted successfully"
    else
        info "Logic App $LOGIC_APP_NAME not found or already deleted"
    fi
}

# Delete Storage Mover
delete_storage_mover() {
    if [[ -z "$STORAGE_MOVER_NAME" ]]; then
        warn "Storage Mover name not available, skipping deletion"
        return 0
    fi
    
    log "Deleting Storage Mover: $STORAGE_MOVER_NAME"
    
    if az storage-mover show --resource-group "$RESOURCE_GROUP" --name "$STORAGE_MOVER_NAME" &> /dev/null; then
        az storage-mover delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$STORAGE_MOVER_NAME" \
            --yes
        
        info "Storage Mover $STORAGE_MOVER_NAME deleted successfully"
    else
        info "Storage Mover $STORAGE_MOVER_NAME not found or already deleted"
    fi
}

# Delete Log Analytics workspace
delete_log_analytics_workspace() {
    if [[ -z "$LOG_WORKSPACE_NAME" ]]; then
        warn "Log Analytics workspace name not available, skipping deletion"
        return 0
    fi
    
    log "Deleting Log Analytics workspace: $LOG_WORKSPACE_NAME"
    
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_WORKSPACE_NAME" &> /dev/null; then
        az monitor log-analytics workspace delete \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_WORKSPACE_NAME" \
            --yes
        
        info "Log Analytics workspace $LOG_WORKSPACE_NAME deleted successfully"
    else
        info "Log Analytics workspace $LOG_WORKSPACE_NAME not found or already deleted"
    fi
}

# Delete storage account
delete_storage_account() {
    if [[ -z "$STORAGE_ACCOUNT_NAME" ]]; then
        warn "Storage account name not available, skipping deletion"
        return 0
    fi
    
    log "Deleting storage account: $STORAGE_ACCOUNT_NAME"
    
    if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        # Check if storage account has any important data
        local blob_count=$(az storage blob list \
            --container-name "migrated-data" \
            --account-name "$STORAGE_ACCOUNT_NAME" \
            --query "length(@)" \
            --output tsv 2>/dev/null || echo "0")
        
        if [[ "$blob_count" -gt 0 ]]; then
            warn "Storage account contains $blob_count blobs. Data will be permanently deleted."
            
            if [[ "$FORCE_DELETE" != "true" && "$SKIP_CONFIRMATION" != "true" ]]; then
                read -p "Continue with storage account deletion? (type 'yes' to continue): " storage_confirmation
                if [[ "$storage_confirmation" != "yes" ]]; then
                    warn "Skipping storage account deletion"
                    return 0
                fi
            fi
        fi
        
        az storage account delete \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        
        info "Storage account $STORAGE_ACCOUNT_NAME deleted successfully"
    else
        info "Storage account $STORAGE_ACCOUNT_NAME not found or already deleted"
    fi
}

# Delete resource group
delete_resource_group() {
    if [[ "$DELETE_RESOURCE_GROUP" != "true" ]]; then
        return 0
    fi
    
    log "Deleting resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        # List all resources in the group
        info "Resources in resource group:"
        az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output table
        
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        
        info "Resource group $RESOURCE_GROUP deletion initiated"
        info "Note: Deletion may take several minutes to complete"
    else
        info "Resource group $RESOURCE_GROUP not found or already deleted"
    fi
}

# Clean up deployment state
cleanup_state() {
    log "Cleaning up deployment state..."
    
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        info "Deployment state file removed: $STATE_FILE"
    else
        info "No deployment state file found"
    fi
    
    # Clean up any temporary files
    if [[ -d "${PROJECT_ROOT}/temp" ]]; then
        rm -rf "${PROJECT_ROOT}/temp"
        info "Temporary files cleaned up"
    fi
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local errors=0
    
    # Check if resource group still exists (only if not deleting entire group)
    if [[ "$DELETE_RESOURCE_GROUP" != "true" ]]; then
        if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            warn "Resource group $RESOURCE_GROUP was deleted"
        fi
    fi
    
    # Check individual resources (only if not deleting entire group)
    if [[ "$DELETE_RESOURCE_GROUP" != "true" ]]; then
        if [[ -n "$STORAGE_ACCOUNT_NAME" ]] && az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            warn "Storage account $STORAGE_ACCOUNT_NAME still exists"
            ((errors++))
        fi
        
        if [[ -n "$STORAGE_MOVER_NAME" ]] && az storage-mover show --resource-group "$RESOURCE_GROUP" --name "$STORAGE_MOVER_NAME" &> /dev/null; then
            warn "Storage Mover $STORAGE_MOVER_NAME still exists"
            ((errors++))
        fi
        
        if [[ -n "$LOG_WORKSPACE_NAME" ]] && az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_WORKSPACE_NAME" &> /dev/null; then
            warn "Log Analytics workspace $LOG_WORKSPACE_NAME still exists"
            ((errors++))
        fi
        
        if [[ -n "$LOGIC_APP_NAME" ]] && az logic app show --resource-group "$RESOURCE_GROUP" --name "$LOGIC_APP_NAME" &> /dev/null; then
            warn "Logic App $LOGIC_APP_NAME still exists"
            ((errors++))
        fi
    fi
    
    if [[ "$errors" -eq 0 ]]; then
        log "Cleanup verification completed successfully"
    else
        warn "Cleanup verification found $errors issues"
    fi
}

# Display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "=================================="
    echo "Resource Group: $RESOURCE_GROUP"
    
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        echo "Status: Entire resource group deletion initiated"
    else
        echo "Status: Individual resources cleaned up"
    fi
    
    echo "Cleanup completed at: $(date)"
    echo "=================================="
    
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        info "Note: Resource group deletion is asynchronous and may take several minutes to complete"
        info "You can check the status in the Azure portal or using 'az group show --name $RESOURCE_GROUP'"
    fi
}

#==============================================================================
# Main Execution
#==============================================================================

main() {
    log "Starting Azure Storage Mover and Monitor cleanup..."
    
    # Check prerequisites
    check_prerequisites
    
    # Try to load state from file
    if ! load_state; then
        warn "Could not load deployment state. Please set environment variables manually."
    fi
    
    # Validate configuration
    validate_configuration
    
    # Confirm deletion
    confirm_deletion
    
    # Stop any running migration jobs
    stop_migration_jobs
    
    # Delete resources in reverse order of creation
    delete_monitor_alerts
    delete_logic_app
    delete_storage_mover
    delete_log_analytics_workspace
    delete_storage_account
    
    # Delete resource group if requested
    delete_resource_group
    
    # Clean up state files
    cleanup_state
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_summary
    
    log "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Script interrupted by user"' INT TERM

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Clean up Azure Storage Mover and Azure Monitor resources"
    echo ""
    echo "Options:"
    echo "  -h, --help                Show this help message"
    echo "  -g, --resource-group      Resource group name (required if no state file)"
    echo "  -s, --storage-account     Storage account name"
    echo "  -m, --storage-mover       Storage Mover name"
    echo "  -w, --log-workspace       Log Analytics workspace name"
    echo "  -a, --logic-app           Logic App name"
    echo "  -f, --force               Force deletion without additional confirmations"
    echo "  -r, --delete-resource-group Delete entire resource group"
    echo "  -y, --yes                 Skip confirmation prompts"
    echo ""
    echo "Environment variables:"
    echo "  RESOURCE_GROUP, STORAGE_ACCOUNT_NAME, STORAGE_MOVER_NAME"
    echo "  LOG_WORKSPACE_NAME, LOGIC_APP_NAME, FORCE_DELETE"
    echo "  DELETE_RESOURCE_GROUP, SKIP_CONFIRMATION"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use deployment state file"
    echo "  $0 -g my-migration-rg                # Clean up specific resource group"
    echo "  $0 -g my-migration-rg -r             # Delete entire resource group"
    echo "  $0 -g my-migration-rg -f -y          # Force delete with no confirmations"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--storage-account)
            STORAGE_ACCOUNT_NAME="$2"
            shift 2
            ;;
        -m|--storage-mover)
            STORAGE_MOVER_NAME="$2"
            shift 2
            ;;
        -w|--log-workspace)
            LOG_WORKSPACE_NAME="$2"
            shift 2
            ;;
        -a|--logic-app)
            LOGIC_APP_NAME="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_DELETE="true"
            shift
            ;;
        -r|--delete-resource-group)
            DELETE_RESOURCE_GROUP="true"
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Run main function
main "$@"