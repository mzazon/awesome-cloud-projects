#!/bin/bash

# Azure Proactive Infrastructure Health Monitoring Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Script variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_LOG="${SCRIPT_DIR}/cleanup.log"
DRY_RUN=false
FORCE_DELETE=false
KEEP_LOGS=false
RESOURCE_GROUP=""
CONFIG_FILE="${SCRIPT_DIR}/deployment-config.json"

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Azure Proactive Infrastructure Health Monitoring Solution

OPTIONS:
    -g, --resource-group NAME           Specific resource group to delete
    -c, --config-file PATH             Path to deployment configuration file
    -d, --dry-run                      Show what would be deleted without executing
    -f, --force                        Force deletion without confirmation prompts
    -k, --keep-logs                    Keep Log Analytics workspace and logs
    -h, --help                         Show this help message

Examples:
    $0 --resource-group rg-health-monitoring-abc123
    $0 --dry-run --config-file ./deployment-config.json
    $0 --force --keep-logs

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -c|--config-file)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -k|--keep-logs)
            KEEP_LOGS=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi

    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    # Get subscription info
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    log "Using subscription: $subscription_name ($subscription_id)"

    success "Prerequisites check completed"
}

# Load configuration from file
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        log "Loading configuration from: $CONFIG_FILE"
        
        if ! command -v jq &> /dev/null; then
            warn "jq not found. Parsing JSON manually."
            RESOURCE_GROUP=$(grep -o '"resource_group": "[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4 || echo "")
            WORKSPACE_NAME=$(grep -o '"workspace_name": "[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4 || echo "")
            ACTION_GROUP_NAME=$(grep -o '"action_group_name": "[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4 || echo "")
            LOGIC_APP_NAME=$(grep -o '"logic_app_name": "[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4 || echo "")
            AUTOMATION_ACCOUNT=$(grep -o '"automation_account": "[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4 || echo "")
            SCHEDULE_NAME=$(grep -o '"schedule_name": "[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4 || echo "")
            RUNBOOK_NAME=$(grep -o '"runbook_name": "[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4 || echo "")
            WEBHOOK_NAME=$(grep -o '"webhook_name": "[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4 || echo "")
            WORKBOOK_NAME=$(grep -o '"workbook_name": "[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4 || echo "")
        else
            RESOURCE_GROUP=$(jq -r '.resource_group // empty' "$CONFIG_FILE")
            WORKSPACE_NAME=$(jq -r '.workspace_name // empty' "$CONFIG_FILE")
            ACTION_GROUP_NAME=$(jq -r '.action_group_name // empty' "$CONFIG_FILE")
            LOGIC_APP_NAME=$(jq -r '.logic_app_name // empty' "$CONFIG_FILE")
            AUTOMATION_ACCOUNT=$(jq -r '.automation_account // empty' "$CONFIG_FILE")
            SCHEDULE_NAME=$(jq -r '.schedule_name // empty' "$CONFIG_FILE")
            RUNBOOK_NAME=$(jq -r '.runbook_name // empty' "$CONFIG_FILE")
            WEBHOOK_NAME=$(jq -r '.webhook_name // empty' "$CONFIG_FILE")
            WORKBOOK_NAME=$(jq -r '.workbook_name // empty' "$CONFIG_FILE")
        fi
        
        success "Configuration loaded successfully"
    else
        warn "Configuration file not found: $CONFIG_FILE"
        warn "Will attempt to delete resources by resource group only"
    fi
}

# Confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi

    echo
    warn "This will permanently delete the following resources:"
    if [[ -n "$RESOURCE_GROUP" ]]; then
        echo "  - Resource Group: $RESOURCE_GROUP"
    fi
    if [[ -n "$WORKSPACE_NAME" ]] && [[ "$KEEP_LOGS" == "false" ]]; then
        echo "  - Log Analytics Workspace: $WORKSPACE_NAME"
    fi
    if [[ -n "$ACTION_GROUP_NAME" ]]; then
        echo "  - Action Group: $ACTION_GROUP_NAME"
    fi
    if [[ -n "$LOGIC_APP_NAME" ]]; then
        echo "  - Logic App: $LOGIC_APP_NAME"
    fi
    if [[ -n "$AUTOMATION_ACCOUNT" ]]; then
        echo "  - Automation Account: $AUTOMATION_ACCOUNT"
    fi
    if [[ -n "$WORKBOOK_NAME" ]]; then
        echo "  - Monitoring Workbook: $WORKBOOK_NAME"
    fi
    
    echo
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Delete Azure Monitor alert rules
delete_monitor_alerts() {
    if [[ -z "$RESOURCE_GROUP" ]]; then
        warn "Resource group not specified, skipping alert rule deletion"
        return 0
    fi

    log "Deleting Azure Monitor alert rules..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete alert rules in resource group: $RESOURCE_GROUP"
        return 0
    fi

    local alert_rules=(
        "Critical-Patch-Compliance-Alert"
        "Update-Installation-Failures"
        "Automation-Effectiveness-Metric"
    )

    for rule in "${alert_rules[@]}"; do
        if az monitor scheduled-query show --name "$rule" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log "Deleting alert rule: $rule"
            az monitor scheduled-query delete \
                --name "$rule" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
        elif az monitor metrics alert show --name "$rule" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log "Deleting metrics alert: $rule"
            az monitor metrics alert delete \
                --name "$rule" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
        else
            warn "Alert rule not found: $rule"
        fi
    done

    success "Alert rules deleted"
}

# Delete Automation Account
delete_automation_account() {
    if [[ -z "$AUTOMATION_ACCOUNT" ]] || [[ -z "$RESOURCE_GROUP" ]]; then
        warn "Automation account name or resource group not specified, skipping"
        return 0
    fi

    log "Deleting Automation Account: $AUTOMATION_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete Automation Account: $AUTOMATION_ACCOUNT"
        return 0
    fi

    if az automation account show --name "$AUTOMATION_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az automation account delete \
            --name "$AUTOMATION_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        success "Automation Account deleted: $AUTOMATION_ACCOUNT"
    else
        warn "Automation Account not found: $AUTOMATION_ACCOUNT"
    fi
}

# Delete Logic App
delete_logic_app() {
    if [[ -z "$LOGIC_APP_NAME" ]] || [[ -z "$RESOURCE_GROUP" ]]; then
        warn "Logic App name or resource group not specified, skipping"
        return 0
    fi

    log "Deleting Logic App: $LOGIC_APP_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete Logic App: $LOGIC_APP_NAME"
        return 0
    fi

    if az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az logic workflow delete \
            --name "$LOGIC_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        success "Logic App deleted: $LOGIC_APP_NAME"
    else
        warn "Logic App not found: $LOGIC_APP_NAME"
    fi
}

# Delete monitoring workbook
delete_monitoring_workbook() {
    if [[ -z "$WORKBOOK_NAME" ]] || [[ -z "$RESOURCE_GROUP" ]]; then
        warn "Workbook name or resource group not specified, skipping"
        return 0
    fi

    log "Deleting monitoring workbook: $WORKBOOK_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete monitoring workbook: $WORKBOOK_NAME"
        return 0
    fi

    if az monitor app-insights workbook show --name "$WORKBOOK_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az monitor app-insights workbook delete \
            --name "$WORKBOOK_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        success "Monitoring workbook deleted: $WORKBOOK_NAME"
    else
        warn "Monitoring workbook not found: $WORKBOOK_NAME"
    fi
}

# Delete Service Health alert rule
delete_service_health_alert() {
    if [[ -z "$RESOURCE_GROUP" ]]; then
        warn "Resource group not specified, skipping Service Health alert deletion"
        return 0
    fi

    log "Deleting Service Health alert rule"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete Service Health alert rule"
        return 0
    fi

    if az monitor activity-log alert show --name "Service Health Issues" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az monitor activity-log alert delete \
            --name "Service Health Issues" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        success "Service Health alert rule deleted"
    else
        warn "Service Health alert rule not found"
    fi
}

# Delete action group
delete_action_group() {
    if [[ -z "$ACTION_GROUP_NAME" ]] || [[ -z "$RESOURCE_GROUP" ]]; then
        warn "Action group name or resource group not specified, skipping"
        return 0
    fi

    log "Deleting action group: $ACTION_GROUP_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete action group: $ACTION_GROUP_NAME"
        return 0
    fi

    if az monitor action-group show --name "$ACTION_GROUP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az monitor action-group delete \
            --name "$ACTION_GROUP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        success "Action group deleted: $ACTION_GROUP_NAME"
    else
        warn "Action group not found: $ACTION_GROUP_NAME"
    fi
}

# Delete maintenance configuration
delete_maintenance_config() {
    if [[ -z "$SCHEDULE_NAME" ]] || [[ -z "$RESOURCE_GROUP" ]]; then
        warn "Maintenance schedule name or resource group not specified, skipping"
        return 0
    fi

    log "Deleting maintenance configuration: $SCHEDULE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete maintenance configuration: $SCHEDULE_NAME"
        return 0
    fi

    if az maintenance configuration show --name "$SCHEDULE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az maintenance configuration delete \
            --name "$SCHEDULE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        success "Maintenance configuration deleted: $SCHEDULE_NAME"
    else
        warn "Maintenance configuration not found: $SCHEDULE_NAME"
    fi
}

# Delete Update Manager policy
delete_update_manager_policy() {
    if [[ -z "$RESOURCE_GROUP" ]]; then
        warn "Resource group not specified, skipping Update Manager policy deletion"
        return 0
    fi

    log "Deleting Update Manager assessment policy"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete Update Manager assessment policy"
        return 0
    fi

    local subscription_id=$(az account show --query id --output tsv)
    local policy_scope="/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}"

    if az policy assignment show --name "Enable-UpdateManager-Assessment" --scope "$policy_scope" &> /dev/null; then
        az policy assignment delete \
            --name "Enable-UpdateManager-Assessment" \
            --scope "$policy_scope"
        success "Update Manager assessment policy deleted"
    else
        warn "Update Manager assessment policy not found"
    fi
}

# Delete Log Analytics workspace
delete_log_analytics() {
    if [[ "$KEEP_LOGS" == "true" ]]; then
        log "Keeping Log Analytics workspace as requested"
        return 0
    fi

    if [[ -z "$WORKSPACE_NAME" ]] || [[ -z "$RESOURCE_GROUP" ]]; then
        warn "Workspace name or resource group not specified, skipping"
        return 0
    fi

    log "Deleting Log Analytics workspace: $WORKSPACE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete Log Analytics workspace: $WORKSPACE_NAME"
        return 0
    fi

    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" &> /dev/null; then
        az monitor log-analytics workspace delete \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$WORKSPACE_NAME" \
            --yes
        success "Log Analytics workspace deleted: $WORKSPACE_NAME"
    else
        warn "Log Analytics workspace not found: $WORKSPACE_NAME"
    fi
}

# Delete resource group
delete_resource_group() {
    if [[ -z "$RESOURCE_GROUP" ]]; then
        warn "Resource group not specified, skipping resource group deletion"
        return 0
    fi

    log "Deleting resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi

    if az group exists --name "$RESOURCE_GROUP"; then
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        success "Resource group deletion initiated: $RESOURCE_GROUP"
        log "Note: Deletion may take several minutes to complete"
    else
        warn "Resource group not found: $RESOURCE_GROUP"
    fi
}

# Wait for resource group deletion
wait_for_deletion() {
    if [[ "$DRY_RUN" == "true" ]] || [[ -z "$RESOURCE_GROUP" ]]; then
        return 0
    fi

    log "Waiting for resource group deletion to complete..."
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while az group exists --name "$RESOURCE_GROUP" && [[ $wait_time -lt $max_wait ]]; do
        sleep 10
        wait_time=$((wait_time + 10))
        log "Still waiting... (${wait_time}s elapsed)"
    done

    if az group exists --name "$RESOURCE_GROUP"; then
        warn "Resource group deletion is taking longer than expected"
        log "You can check the deletion status manually with: az group show --name $RESOURCE_GROUP"
    else
        success "Resource group deletion completed"
    fi
}

# Clean up configuration files
cleanup_config_files() {
    log "Cleaning up configuration files"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would clean up configuration files"
        return 0
    fi

    local files_to_clean=(
        "$CONFIG_FILE"
        "${SCRIPT_DIR}/deployment.log"
        "${SCRIPT_DIR}/deploy.log"
    )

    for file in "${files_to_clean[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$FORCE_DELETE" == "true" ]]; then
                rm -f "$file"
                log "Deleted: $file"
            else
                read -p "Delete configuration file $file? (y/n): " -r
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    rm -f "$file"
                    log "Deleted: $file"
                fi
            fi
        fi
    done
}

# Main cleanup function
main() {
    log "Starting Azure Proactive Infrastructure Health Monitoring cleanup"
    log "Resource Group: ${RESOURCE_GROUP:-'Auto-detect'}"
    log "Keep Logs: $KEEP_LOGS"
    log "Dry Run: $DRY_RUN"
    log "Force Delete: $FORCE_DELETE"
    
    # Start logging
    exec 1> >(tee -a "$CLEANUP_LOG")
    exec 2> >(tee -a "$CLEANUP_LOG" >&2)
    
    # Check prerequisites
    check_prerequisites
    
    # Load configuration
    load_config
    
    # Confirm deletion
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_monitor_alerts
    delete_automation_account
    delete_logic_app
    delete_monitoring_workbook
    delete_service_health_alert
    delete_action_group
    delete_maintenance_config
    delete_update_manager_policy
    delete_log_analytics
    delete_resource_group
    
    # Wait for deletion if not dry run
    if [[ "$DRY_RUN" == "false" ]]; then
        wait_for_deletion
    fi
    
    # Clean up configuration files
    cleanup_config_files
    
    if [[ "$DRY_RUN" == "false" ]]; then
        success "Cleanup completed successfully!"
        log "Cleanup log saved to: $CLEANUP_LOG"
    else
        success "Dry run completed. No resources were deleted."
    fi
}

# Trap to handle cleanup on script exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Cleanup failed with exit code $exit_code"
        log "Check the cleanup log for details: $CLEANUP_LOG"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Run main function
main "$@"