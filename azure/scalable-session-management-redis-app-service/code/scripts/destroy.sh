#!/bin/bash

# =============================================================================
# Azure Distributed Session Management Cleanup Script
# =============================================================================
# 
# This script safely removes all Azure resources created by the deployment
# script for the distributed session management solution.
#
# Prerequisites:
# - Azure CLI installed and authenticated
# - Access to the same subscription used for deployment
# - Bash shell environment
#
# Safety Features:
# - Confirmation prompts for destructive actions
# - Selective resource deletion
# - Resource dependency handling
# - Verification of deletion completion
#
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Cleanup configuration
RESOURCE_GROUP=""
FORCE_DELETE="false"
DRY_RUN="false"
SKIP_CONFIRMATION="false"
DELETE_RESOURCE_GROUP="true"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
    
    echo "[$timestamp][$level] $message" >> "$LOG_FILE"
}

error_exit() {
    log "ERROR" "$1"
    exit 1
}

confirm_action() {
    local action="$1"
    local resource="$2"
    
    if [[ "$SKIP_CONFIRMATION" == "true" ]] || [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${YELLOW}WARNING:${NC} About to $action: $resource"
    read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Operation cancelled by user"
        return 1
    fi
    
    return 0
}

check_prerequisites() {
    log "INFO" "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    local subscription_id
    subscription_id=$(az account show --query id --output tsv 2>/dev/null) || \
        error_exit "Unable to get subscription ID. Please check your Azure access."
    
    log "INFO" "Using Azure subscription: $subscription_id"
    log "INFO" "Prerequisites check completed successfully"
}

load_deployment_state() {
    log "INFO" "Loading deployment state..."
    
    if [[ ! -f "$STATE_FILE" ]]; then
        log "WARN" "No deployment state file found at $STATE_FILE"
        log "INFO" "You may need to specify the resource group manually"
        return 1
    fi
    
    # Source the state file to load variables
    source "$STATE_FILE"
    
    log "INFO" "Loaded deployment state:"
    log "DEBUG" "Status: ${DEPLOYMENT_STATUS:-unknown}"
    log "DEBUG" "Resource Group: ${RESOURCE_GROUP:-unknown}"
    log "DEBUG" "Location: ${LOCATION:-unknown}"
    log "DEBUG" "Timestamp: ${DEPLOYMENT_TIMESTAMP:-unknown}"
    
    return 0
}

check_resource_group_exists() {
    local rg="$1"
    
    if az group show --name "$rg" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

list_resources_in_group() {
    local rg="$1"
    
    log "INFO" "Resources in resource group '$rg':"
    
    local resources
    resources=$(az resource list --resource-group "$rg" --output table 2>/dev/null) || {
        log "WARN" "Could not list resources in resource group '$rg'"
        return 1
    }
    
    if [[ -z "$resources" ]] || [[ "$resources" == *"No resources found"* ]]; then
        log "INFO" "No resources found in resource group '$rg'"
        return 0
    fi
    
    echo "$resources"
    echo ""
    
    return 0
}

wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local max_wait="${3:-300}"  # Default 5 minutes
    local interval=15
    local waited=0
    
    log "INFO" "Waiting for $resource_type '$resource_name' deletion to complete..."
    
    while [ $waited -lt $max_wait ]; do
        local exists="false"
        
        case "$resource_type" in
            "resource-group")
                if check_resource_group_exists "$resource_name"; then
                    exists="true"
                fi
                ;;
            "redis")
                if az redis show --name "$resource_name" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
                    exists="true"
                fi
                ;;
            "webapp")
                if az webapp show --name "$resource_name" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
                    exists="true"
                fi
                ;;
            *)
                log "WARN" "Unknown resource type for deletion verification: $resource_type"
                return 0
                ;;
        esac
        
        if [[ "$exists" == "false" ]]; then
            log "INFO" "$resource_type '$resource_name' has been deleted successfully"
            return 0
        fi
        
        log "DEBUG" "$resource_type '$resource_name' still exists (waited ${waited}s)"
        sleep $interval
        waited=$((waited + interval))
    done
    
    log "WARN" "$resource_type '$resource_name' deletion did not complete within ${max_wait}s"
    return 1
}

# =============================================================================
# Cleanup Functions
# =============================================================================

delete_metric_alerts() {
    log "INFO" "Deleting metric alerts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete metric alerts in resource group $RESOURCE_GROUP"
        return 0
    fi
    
    local alerts
    alerts=$(az monitor metrics alert list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null) || {
        log "WARN" "Could not list metric alerts"
        return 0
    }
    
    if [[ -z "$alerts" ]]; then
        log "INFO" "No metric alerts found to delete"
        return 0
    fi
    
    while IFS= read -r alert_name; do
        if [[ -n "$alert_name" ]]; then
            log "INFO" "Deleting metric alert: $alert_name"
            az monitor metrics alert delete \
                --name "$alert_name" \
                --resource-group "$RESOURCE_GROUP" \
                --output none || log "WARN" "Failed to delete metric alert: $alert_name"
        fi
    done <<< "$alerts"
    
    log "INFO" "Metric alerts cleanup completed"
}

delete_diagnostic_settings() {
    log "INFO" "Deleting diagnostic settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete diagnostic settings"
        return 0
    fi
    
    # Note: Diagnostic settings are typically deleted automatically when the resource is deleted
    # But we'll attempt to clean them up explicitly if the resource still exists
    
    if [[ -n "${REDIS_NAME:-}" ]] && az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        local subscription_id
        subscription_id=$(az account show --query id --output tsv)
        
        az monitor diagnostic-settings delete \
            --name "RedisSessionDiagnostics" \
            --resource "/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Cache/Redis/${REDIS_NAME}" \
            --output none 2>/dev/null || log "DEBUG" "Diagnostic settings may not exist or already deleted"
    fi
    
    log "INFO" "Diagnostic settings cleanup completed"
}

delete_action_groups() {
    log "INFO" "Deleting action groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete action groups in resource group $RESOURCE_GROUP"
        return 0
    fi
    
    local action_groups
    action_groups=$(az monitor action-group list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null) || {
        log "WARN" "Could not list action groups"
        return 0
    }
    
    if [[ -z "$action_groups" ]]; then
        log "INFO" "No action groups found to delete"
        return 0
    fi
    
    while IFS= read -r group_name; do
        if [[ -n "$group_name" ]]; then
            log "INFO" "Deleting action group: $group_name"
            az monitor action-group delete \
                --name "$group_name" \
                --resource-group "$RESOURCE_GROUP" \
                --output none || log "WARN" "Failed to delete action group: $group_name"
        fi
    done <<< "$action_groups"
    
    log "INFO" "Action groups cleanup completed"
}

delete_log_analytics_workspace() {
    log "INFO" "Deleting Log Analytics workspace..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete Log Analytics workspace ${WORKSPACE_NAME:-}"
        return 0
    fi
    
    if [[ -z "${WORKSPACE_NAME:-}" ]]; then
        log "INFO" "No workspace name found, skipping workspace deletion"
        return 0
    fi
    
    if ! az monitor log-analytics workspace show --name "$WORKSPACE_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log "INFO" "Log Analytics workspace '$WORKSPACE_NAME' not found, may already be deleted"
        return 0
    fi
    
    log "INFO" "Deleting Log Analytics workspace: $WORKSPACE_NAME"
    az monitor log-analytics workspace delete \
        --name "$WORKSPACE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --yes \
        --output none || log "WARN" "Failed to delete Log Analytics workspace: $WORKSPACE_NAME"
    
    log "INFO" "Log Analytics workspace deletion completed"
}

delete_web_app() {
    log "INFO" "Deleting Web App..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete Web App ${WEB_APP_NAME:-}"
        return 0
    fi
    
    if [[ -z "${WEB_APP_NAME:-}" ]]; then
        log "INFO" "No Web App name found, skipping Web App deletion"
        return 0
    fi
    
    if ! az webapp show --name "$WEB_APP_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log "INFO" "Web App '$WEB_APP_NAME' not found, may already be deleted"
        return 0
    fi
    
    if ! confirm_action "delete Web App" "$WEB_APP_NAME"; then
        log "INFO" "Skipping Web App deletion"
        return 0
    fi
    
    log "INFO" "Deleting Web App: $WEB_APP_NAME"
    az webapp delete \
        --name "$WEB_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --output none || log "WARN" "Failed to delete Web App: $WEB_APP_NAME"
    
    # Wait for deletion to complete
    wait_for_deletion "webapp" "$WEB_APP_NAME" 180
    
    log "INFO" "Web App deletion completed"
}

delete_app_service_plan() {
    log "INFO" "Deleting App Service Plan..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete App Service Plan ${APP_SERVICE_PLAN:-}"
        return 0
    fi
    
    if [[ -z "${APP_SERVICE_PLAN:-}" ]]; then
        log "INFO" "No App Service Plan name found, skipping deletion"
        return 0
    fi
    
    if ! az appservice plan show --name "$APP_SERVICE_PLAN" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log "INFO" "App Service Plan '$APP_SERVICE_PLAN' not found, may already be deleted"
        return 0
    fi
    
    log "INFO" "Deleting App Service Plan: $APP_SERVICE_PLAN"
    az appservice plan delete \
        --name "$APP_SERVICE_PLAN" \
        --resource-group "$RESOURCE_GROUP" \
        --yes \
        --output none || log "WARN" "Failed to delete App Service Plan: $APP_SERVICE_PLAN"
    
    log "INFO" "App Service Plan deletion completed"
}

delete_redis_instance() {
    log "INFO" "Deleting Redis instance..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete Redis instance ${REDIS_NAME:-}"
        return 0
    fi
    
    if [[ -z "${REDIS_NAME:-}" ]]; then
        log "INFO" "No Redis name found, skipping Redis deletion"
        return 0
    fi
    
    if ! az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log "INFO" "Redis instance '$REDIS_NAME' not found, may already be deleted"
        return 0
    fi
    
    if ! confirm_action "delete Redis instance" "$REDIS_NAME"; then
        log "INFO" "Skipping Redis deletion"
        return 0
    fi
    
    log "INFO" "Deleting Redis instance: $REDIS_NAME"
    az redis delete \
        --name "$REDIS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --yes \
        --output none || log "WARN" "Failed to delete Redis instance: $REDIS_NAME"
    
    # Wait for deletion to complete (Redis can take a while)
    wait_for_deletion "redis" "$REDIS_NAME" 600
    
    log "INFO" "Redis instance deletion completed"
}

delete_virtual_network() {
    log "INFO" "Deleting Virtual Network..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete Virtual Network ${VNET_NAME:-}"
        return 0
    fi
    
    if [[ -z "${VNET_NAME:-}" ]]; then
        log "INFO" "No VNet name found, skipping VNet deletion"
        return 0
    fi
    
    if ! az network vnet show --name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log "INFO" "Virtual Network '$VNET_NAME' not found, may already be deleted"
        return 0
    fi
    
    log "INFO" "Deleting Virtual Network: $VNET_NAME"
    az network vnet delete \
        --name "$VNET_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --output none || log "WARN" "Failed to delete Virtual Network: $VNET_NAME"
    
    log "INFO" "Virtual Network deletion completed"
}

delete_resource_group() {
    log "INFO" "Deleting resource group..."
    
    if [[ "$DELETE_RESOURCE_GROUP" != "true" ]]; then
        log "INFO" "Resource group deletion disabled, skipping"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would delete resource group $RESOURCE_GROUP"
        return 0
    fi
    
    if ! check_resource_group_exists "$RESOURCE_GROUP"; then
        log "INFO" "Resource group '$RESOURCE_GROUP' not found, may already be deleted"
        return 0
    fi
    
    if ! confirm_action "delete entire resource group and ALL its resources" "$RESOURCE_GROUP"; then
        log "INFO" "Skipping resource group deletion"
        return 0
    fi
    
    log "INFO" "Deleting resource group: $RESOURCE_GROUP"
    log "WARN" "This will delete ALL resources in the resource group!"
    
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        --output none || log "WARN" "Failed to initiate resource group deletion: $RESOURCE_GROUP"
    
    # Wait for deletion to complete
    wait_for_deletion "resource-group" "$RESOURCE_GROUP" 1200  # 20 minutes max
    
    log "INFO" "Resource group deletion completed"
}

cleanup_local_files() {
    log "INFO" "Cleaning up local configuration files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    # Remove deployment state file
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE" || log "WARN" "Failed to remove state file: $STATE_FILE"
        log "INFO" "Removed deployment state file"
    fi
    
    # Remove any temporary configuration files that might have been created
    local script_dir
    script_dir="$(dirname "$STATE_FILE")"
    
    if [[ -f "${script_dir}/appsettings.json" ]]; then
        rm -f "${script_dir}/appsettings.json" || log "WARN" "Failed to remove appsettings.json"
        log "INFO" "Removed appsettings.json"
    fi
    
    log "INFO" "Local file cleanup completed"
}

# =============================================================================
# Main Execution
# =============================================================================

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Azure Distributed Session Management Cleanup Script"
    echo ""
    echo "Options:"
    echo "  --resource-group NAME    Resource group to delete (overrides state file)"
    echo "  --keep-resource-group    Delete individual resources but keep the resource group"
    echo "  --dry-run                Show what would be deleted without actually deleting"
    echo "  --force                  Skip all confirmation prompts (DANGEROUS)"
    echo "  --yes                    Skip confirmation prompts (alias for --force)"
    echo "  --help, -h               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup using state file"
    echo "  $0 --resource-group my-rg            # Delete specific resource group"
    echo "  $0 --dry-run                         # Show what would be deleted"
    echo "  $0 --keep-resource-group --force     # Delete resources but keep RG, no prompts"
    echo ""
    echo "Safety Features:"
    echo "- Loads deployment state from previous deployment"
    echo "- Shows resources before deletion"
    echo "- Confirmation prompts for destructive actions"
    echo "- Handles resource dependencies properly"
    echo "- Verifies deletion completion"
}

main() {
    local start_time
    start_time=$(date +%s)
    
    echo "=========================================="
    echo "Azure Distributed Session Management"
    echo "Cleanup Script"
    echo "=========================================="
    echo ""
    
    # Initialize logging
    : > "$LOG_FILE"  # Clear log file
    log "INFO" "Starting cleanup process..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                log "INFO" "Resource group specified: $RESOURCE_GROUP"
                shift
                ;;
            --keep-resource-group)
                DELETE_RESOURCE_GROUP="false"
                log "INFO" "Will preserve resource group"
                ;;
            --dry-run)
                DRY_RUN="true"
                log "INFO" "Dry run mode enabled"
                ;;
            --force|--yes)
                FORCE_DELETE="true"
                SKIP_CONFIRMATION="true"
                log "INFO" "Force mode enabled - skipping confirmations"
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log "WARN" "Unknown option: $1"
                shift
                ;;
        esac
        shift
    done
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment state if no resource group specified
    if [[ -z "$RESOURCE_GROUP" ]]; then
        if load_deployment_state; then
            log "INFO" "Using resource group from deployment state: $RESOURCE_GROUP"
        else
            echo ""
            read -p "Enter the resource group name to clean up: " RESOURCE_GROUP
            if [[ -z "$RESOURCE_GROUP" ]]; then
                error_exit "Resource group name is required"
            fi
        fi
    fi
    
    # Verify resource group exists
    if ! check_resource_group_exists "$RESOURCE_GROUP"; then
        log "WARN" "Resource group '$RESOURCE_GROUP' does not exist"
        
        if [[ "$FORCE_DELETE" != "true" ]]; then
            read -p "Continue anyway to clean up local files? [y/N]: " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "INFO" "Cleanup cancelled"
                exit 0
            fi
        fi
        
        cleanup_local_files
        log "INFO" "Local cleanup completed"
        exit 0
    fi
    
    # Show what will be deleted
    echo ""
    log "INFO" "Resource group to process: $RESOURCE_GROUP"
    list_resources_in_group "$RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "Dry run mode - no resources will actually be deleted"
    else
        echo ""
        echo -e "${RED}WARNING: This will permanently delete Azure resources!${NC}"
        if [[ "$FORCE_DELETE" != "true" ]]; then
            read -p "Continue with cleanup? [y/N]: " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "INFO" "Cleanup cancelled by user"
                exit 0
            fi
        fi
    fi
    
    # Execute cleanup in proper order (reverse of creation)
    log "INFO" "Starting resource cleanup..."
    
    # Clean up monitoring first (these depend on other resources)
    delete_metric_alerts
    delete_diagnostic_settings
    delete_action_groups
    delete_log_analytics_workspace
    
    # Clean up application resources
    delete_web_app
    delete_app_service_plan
    
    # Clean up infrastructure resources
    delete_redis_instance
    delete_virtual_network
    
    # Finally, clean up the resource group (if requested)
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        delete_resource_group
    else
        log "INFO" "Keeping resource group as requested: $RESOURCE_GROUP"
    fi
    
    # Clean up local files
    cleanup_local_files
    
    local end_time duration
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    echo ""
    echo "=========================================="
    echo "Cleanup Summary"
    echo "=========================================="
    echo "Resource Group: $RESOURCE_GROUP"
    if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
        echo "Status: Resource group and all resources deleted"
    else
        echo "Status: Individual resources deleted, resource group preserved"
    fi
    echo "Duration: ${duration} seconds"
    echo "Log File: $LOG_FILE"
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "This was a dry run - no actual resources were deleted"
    else
        echo "Cleanup completed successfully!"
    fi
    echo "=========================================="
    
    log "INFO" "Cleanup process completed in ${duration} seconds"
    
    return 0
}

# Execute main function with all arguments
main "$@"