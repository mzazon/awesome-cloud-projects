#!/usr/bin/env bash

#############################################################################
# Azure Communication Monitoring Cleanup Script
# Recipe: Communication Monitoring with Communication Services and Application Insights
# Purpose: Safely remove all resources created by the deployment script
#############################################################################

set -euo pipefail

# Configuration and Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deploy-config"
readonly QUERY_FILE="${SCRIPT_DIR}/monitoring-query.kql"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#############################################################################
# Utility Functions
#############################################################################

# Logging function
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
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handler
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Cleanup failed. Check $LOG_FILE for details."
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate Azure CLI authentication
validate_azure_auth() {
    log "INFO" "Validating Azure CLI authentication..."
    
    if ! command_exists az; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/"
    fi
    
    local account_info
    if ! account_info=$(az account show 2>/dev/null); then
        error_exit "Not logged into Azure CLI. Please run 'az login' first."
    fi
    
    local subscription_id
    subscription_id=$(echo "$account_info" | jq -r '.id')
    local subscription_name
    subscription_name=$(echo "$account_info" | jq -r '.name')
    
    log "INFO" "Authenticated to Azure subscription: $subscription_name ($subscription_id)"
}

# Load configuration from deployment
load_config() {
    log "INFO" "Loading deployment configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_exit "Configuration file not found: $CONFIG_FILE. Run deploy.sh first or provide resource details manually."
    fi
    
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    
    # Validate required variables
    local required_vars=("RESOURCE_GROUP" "COMM_SERVICE_NAME" "LOG_WORKSPACE_NAME" "APP_INSIGHTS_NAME")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error_exit "Required variable $var not found in configuration"
        fi
    done
    
    log "INFO" "Configuration loaded successfully:"
    log "INFO" "  Resource Group: $RESOURCE_GROUP"
    log "INFO" "  Communication Service: $COMM_SERVICE_NAME"
    log "INFO" "  Log Analytics Workspace: $LOG_WORKSPACE_NAME"
    log "INFO" "  Application Insights: $APP_INSIGHTS_NAME"
}

# Check if resource group exists
check_resource_group() {
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Get resource information safely
get_resource_info() {
    log "INFO" "Gathering resource information for cleanup..."
    
    # Get Communication Services ID if it exists
    if az communication show --name "$COMM_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        COMM_SERVICE_ID=$(az communication show \
            --name "$COMM_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query id --output tsv 2>/dev/null || echo "")
        log "DEBUG" "Communication Services ID: $COMM_SERVICE_ID"
    else
        COMM_SERVICE_ID=""
        log "WARN" "Communication Services resource not found or already deleted"
    fi
    
    # Get Log Analytics Workspace ID if it exists
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_WORKSPACE_NAME" >/dev/null 2>&1; then
        WORKSPACE_ID=$(az monitor log-analytics workspace show \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_WORKSPACE_NAME" \
            --query id --output tsv 2>/dev/null || echo "")
        log "DEBUG" "Workspace ID: $WORKSPACE_ID"
    else
        WORKSPACE_ID=""
        log "WARN" "Log Analytics Workspace not found or already deleted"
    fi
}

# Remove metric alerts
remove_alerts() {
    log "INFO" "Removing metric alerts and action groups..."
    
    local alert_name="CommunicationServiceFailures"
    local action_group_name="CommServiceAlerts"
    
    # Remove metric alert
    if az monitor metrics alert show --name "$alert_name" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "INFO" "Deleting metric alert: $alert_name"
        az monitor metrics alert delete \
            --name "$alert_name" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            || log "WARN" "Failed to delete metric alert (non-critical)"
        log "INFO" "✅ Metric alert deleted"
    else
        log "WARN" "Metric alert not found, skipping deletion"
    fi
    
    # Remove action group
    if az monitor action-group show --name "$action_group_name" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "INFO" "Deleting action group: $action_group_name"
        az monitor action-group delete \
            --name "$action_group_name" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            || log "WARN" "Failed to delete action group (non-critical)"
        log "INFO" "✅ Action group deleted"
    else
        log "WARN" "Action group not found, skipping deletion"
    fi
}

# Remove diagnostic settings
remove_diagnostic_settings() {
    if [[ -n "$COMM_SERVICE_ID" ]]; then
        log "INFO" "Removing diagnostic settings..."
        
        local diag_name="CommServiceDiagnostics"
        
        # Check if diagnostic settings exist
        if az monitor diagnostic-settings list --resource "$COMM_SERVICE_ID" --query "[?name=='$diag_name']" --output tsv | grep -q "$diag_name"; then
            log "INFO" "Deleting diagnostic settings: $diag_name"
            az monitor diagnostic-settings delete \
                --name "$diag_name" \
                --resource "$COMM_SERVICE_ID" \
                || log "WARN" "Failed to delete diagnostic settings (non-critical)"
            log "INFO" "✅ Diagnostic settings deleted"
        else
            log "WARN" "Diagnostic settings not found, skipping deletion"
        fi
    else
        log "WARN" "Communication Services ID not available, skipping diagnostic settings cleanup"
    fi
}

# Remove Communication Services
remove_communication_services() {
    log "INFO" "Removing Communication Services: $COMM_SERVICE_NAME"
    
    if az communication show --name "$COMM_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "INFO" "Deleting Communication Services resource..."
        az communication delete \
            --name "$COMM_SERVICE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            || error_exit "Failed to delete Communication Services"
        
        # Wait for deletion to complete
        local max_attempts=30
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
            if ! az communication show --name "$COMM_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
                log "INFO" "✅ Communication Services deleted successfully"
                break
            fi
            log "INFO" "Waiting for Communication Services deletion... (attempt $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            log "WARN" "Timeout waiting for Communication Services deletion (may still be in progress)"
        fi
    else
        log "WARN" "Communication Services not found, skipping deletion"
    fi
}

# Remove Application Insights
remove_application_insights() {
    log "INFO" "Removing Application Insights: $APP_INSIGHTS_NAME"
    
    if az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "INFO" "Deleting Application Insights resource..."
        az monitor app-insights component delete \
            --app "$APP_INSIGHTS_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            || log "WARN" "Failed to delete Application Insights (non-critical)"
        log "INFO" "✅ Application Insights deleted"
    else
        log "WARN" "Application Insights not found, skipping deletion"
    fi
}

# Remove Log Analytics Workspace
remove_log_analytics_workspace() {
    log "INFO" "Removing Log Analytics Workspace: $LOG_WORKSPACE_NAME"
    
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_WORKSPACE_NAME" >/dev/null 2>&1; then
        log "INFO" "Deleting Log Analytics Workspace..."
        
        # Log Analytics Workspace deletion is soft delete by default
        az monitor log-analytics workspace delete \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_WORKSPACE_NAME" \
            --yes \
            || log "WARN" "Failed to delete Log Analytics Workspace (non-critical)"
        
        log "INFO" "✅ Log Analytics Workspace deleted (soft delete)"
        log "INFO" "Note: Workspace can be recovered within 14 days if needed"
    else
        log "WARN" "Log Analytics Workspace not found, skipping deletion"
    fi
}

# Remove resource group (optional)
remove_resource_group() {
    local force_delete_rg="$1"
    
    if [[ "$force_delete_rg" == true ]]; then
        log "INFO" "Removing resource group: $RESOURCE_GROUP"
        
        if check_resource_group; then
            # Check if resource group has other resources
            local resource_count
            resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length([])" --output tsv 2>/dev/null || echo "0")
            
            if [[ "$resource_count" -gt 0 ]]; then
                log "WARN" "Resource group contains $resource_count resources. Proceeding with deletion..."
            fi
            
            log "INFO" "Deleting resource group and all remaining resources..."
            az group delete \
                --name "$RESOURCE_GROUP" \
                --yes \
                --no-wait \
                || error_exit "Failed to initiate resource group deletion"
            
            log "INFO" "✅ Resource group deletion initiated"
            log "INFO" "Note: Deletion may take several minutes to complete"
        else
            log "WARN" "Resource group not found, skipping deletion"
        fi
    else
        log "INFO" "Keeping resource group: $RESOURCE_GROUP"
        log "INFO" "To delete the resource group later, run: az group delete --name $RESOURCE_GROUP --yes"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    local files_to_remove=("$CONFIG_FILE" "$QUERY_FILE")
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log "INFO" "Removing file: $file"
            rm -f "$file" || log "WARN" "Failed to remove $file"
        else
            log "DEBUG" "File not found: $file"
        fi
    done
    
    log "INFO" "✅ Local files cleaned up"
}

# Validate cleanup
validate_cleanup() {
    log "INFO" "Validating resource cleanup..."
    
    local remaining_resources=0
    
    # Check Communication Services
    if az communication show --name "$COMM_SERVICE_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "WARN" "Communication Services still exists"
        ((remaining_resources++))
    fi
    
    # Check Application Insights
    if az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log "WARN" "Application Insights still exists"
        ((remaining_resources++))
    fi
    
    # Check Log Analytics Workspace (may be in soft-delete state)
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_WORKSPACE_NAME" >/dev/null 2>&1; then
        local workspace_state
        workspace_state=$(az monitor log-analytics workspace show \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_WORKSPACE_NAME" \
            --query "provisioningState" --output tsv 2>/dev/null || echo "Unknown")
        
        if [[ "$workspace_state" != "Deleting" ]]; then
            log "WARN" "Log Analytics Workspace still active: $workspace_state"
            ((remaining_resources++))
        else
            log "INFO" "Log Analytics Workspace is being deleted"
        fi
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        log "INFO" "✅ All resources successfully cleaned up"
        return 0
    else
        log "WARN" "Some resources may still exist ($remaining_resources found)"
        log "INFO" "This may be normal due to soft-delete policies or async deletion"
        return 1
    fi
}

# Display cleanup summary
display_summary() {
    log "INFO" "Cleanup Summary:"
    log "INFO" "==============="
    log "INFO" "Resource Group: $RESOURCE_GROUP"
    log "INFO" ""
    log "INFO" "Removed Resources:"
    log "INFO" "  ✅ Metric Alerts and Action Groups"
    log "INFO" "  ✅ Diagnostic Settings"
    log "INFO" "  ✅ Communication Services: $COMM_SERVICE_NAME"
    log "INFO" "  ✅ Application Insights: $APP_INSIGHTS_NAME"
    log "INFO" "  ✅ Log Analytics Workspace: $LOG_WORKSPACE_NAME (soft delete)"
    log "INFO" "  ✅ Local configuration files"
    log "INFO" ""
    log "INFO" "Notes:"
    log "INFO" "  - Log Analytics Workspace uses soft delete (14-day recovery period)"
    log "INFO" "  - Some resources may take additional time for complete removal"
    log "INFO" "  - Check Azure portal to confirm all resources are removed"
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Azure Communication Services monitoring infrastructure.

OPTIONS:
    -h, --help              Show this help message
    -f, --force             Skip confirmation prompts
    --delete-rg             Delete the entire resource group
    --keep-rg               Keep resource group (default)
    -v, --verbose           Enable verbose logging
    --dry-run              Show what would be deleted without removing resources

EXAMPLES:
    $0                      # Remove resources, keep resource group
    $0 --delete-rg          # Remove everything including resource group
    $0 --dry-run            # Preview what would be deleted
    $0 -f --delete-rg       # Force delete everything without prompts

EOF
}

# Confirmation prompt
confirm_deletion() {
    local delete_rg="$1"
    local force="$2"
    
    if [[ "$force" == true ]]; then
        log "INFO" "Force mode enabled, skipping confirmation"
        return 0
    fi
    
    echo
    log "WARN" "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log "WARN" "This will permanently delete the following resources:"
    log "WARN" "  - Communication Services: $COMM_SERVICE_NAME"
    log "WARN" "  - Application Insights: $APP_INSIGHTS_NAME"
    log "WARN" "  - Log Analytics Workspace: $LOG_WORKSPACE_NAME"
    log "WARN" "  - All associated alerts and diagnostic settings"
    
    if [[ "$delete_rg" == true ]]; then
        log "WARN" "  - Resource Group: $RESOURCE_GROUP (and ALL contents)"
    fi
    
    echo
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "INFO" "Operation cancelled by user"
        exit 0
    fi
    
    log "INFO" "Deletion confirmed, proceeding..."
}

#############################################################################
# Main Execution
#############################################################################

main() {
    local force_deletion=false
    local delete_resource_group=false
    local dry_run=false
    local verbose=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -f|--force)
                force_deletion=true
                shift
                ;;
            --delete-rg)
                delete_resource_group=true
                shift
                ;;
            --keep-rg)
                delete_resource_group=false
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Initialize logging
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    if [[ "$verbose" == true ]]; then
        set -x
    fi
    
    log "INFO" "Starting Azure Communication Monitoring cleanup..."
    log "INFO" "Script directory: $SCRIPT_DIR"
    log "INFO" "Log file: $LOG_FILE"
    
    # Validate prerequisites
    validate_azure_auth
    load_config
    
    # Check if resource group exists
    if ! check_resource_group; then
        log "ERROR" "Resource group '$RESOURCE_GROUP' not found"
        log "INFO" "Either the resources were already deleted or the deployment never completed"
        
        # Clean up local files anyway
        cleanup_local_files
        log "INFO" "Local cleanup completed"
        exit 0
    fi
    
    # Dry run mode
    if [[ "$dry_run" == true ]]; then
        log "INFO" "DRY RUN MODE - No resources will be deleted"
        get_resource_info
        log "INFO" "Would delete the following resources:"
        log "INFO" "  - Communication Services: $COMM_SERVICE_NAME"
        log "INFO" "  - Application Insights: $APP_INSIGHTS_NAME"
        log "INFO" "  - Log Analytics Workspace: $LOG_WORKSPACE_NAME"
        if [[ "$delete_resource_group" == true ]]; then
            log "INFO" "  - Resource Group: $RESOURCE_GROUP"
        fi
        exit 0
    fi
    
    # Get resource information
    get_resource_info
    
    # Confirm deletion
    confirm_deletion "$delete_resource_group" "$force_deletion"
    
    # Execute cleanup steps in reverse order of creation
    log "INFO" "Beginning resource cleanup..."
    
    remove_alerts
    remove_diagnostic_settings
    remove_communication_services
    remove_application_insights
    remove_log_analytics_workspace
    remove_resource_group "$delete_resource_group"
    cleanup_local_files
    
    # Validate and summarize
    log "INFO" "Validating cleanup results..."
    validate_cleanup || log "WARN" "Some resources may still be present"
    
    display_summary
    log "INFO" "🎉 Cleanup completed successfully!"
    log "INFO" "Logs available at: $LOG_FILE"
}

# Execute main function with all arguments
main "$@"