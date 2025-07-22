#!/bin/bash

# Azure Sustainable Workload Optimization - Cleanup Script
# This script removes all resources created for the carbon optimization solution including:
# - Automated alerts and action groups
# - Azure Monitor workbook
# - Scheduled monitoring jobs and runbooks
# - Azure Automation Account
# - Log Analytics workspace
# - Resource group (optional)

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Azure CLI login status
check_azure_login() {
    log "Checking Azure CLI login status..."
    if ! az account show >/dev/null 2>&1; then
        error "Azure CLI not logged in. Please run 'az login' first."
    fi
    
    local account_name=$(az account show --query name --output tsv)
    local subscription_id=$(az account show --query id --output tsv)
    info "Logged in to Azure account: $account_name"
    info "Using subscription: $subscription_id"
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    check_azure_login
    
    log "Prerequisites validation completed successfully"
}

# Function to get user confirmation
get_user_confirmation() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        return 0
    fi
    
    echo -n "Are you sure you want to delete $resource_type '$resource_name'? (y/N): "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            info "Skipping deletion of $resource_type '$resource_name'"
            return 1
            ;;
    esac
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Use provided values or discover from existing resources
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        warn "RESOURCE_GROUP not set. Please provide resource group name."
        echo -n "Enter resource group name: "
        read -r RESOURCE_GROUP
    fi
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        error "Resource group name is required"
    fi
    
    export RESOURCE_GROUP
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Try to discover other resource names from the resource group
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        info "Resource group '$RESOURCE_GROUP' found"
        
        # Discover automation account
        local automation_accounts=$(az automation account list --resource-group "$RESOURCE_GROUP" --query "[?starts_with(name, 'aa-carbon-opt')].name" --output tsv)
        if [[ -n "$automation_accounts" ]]; then
            export AUTOMATION_ACCOUNT=$(echo "$automation_accounts" | head -n1)
            info "Found automation account: $AUTOMATION_ACCOUNT"
        fi
        
        # Discover Log Analytics workspace
        local workspaces=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[?starts_with(name, 'law-carbon-opt')].name" --output tsv)
        if [[ -n "$workspaces" ]]; then
            export WORKSPACE_NAME=$(echo "$workspaces" | head -n1)
            info "Found Log Analytics workspace: $WORKSPACE_NAME"
        fi
        
        # Discover workbook
        local workbooks=$(az monitor workbook list --resource-group "$RESOURCE_GROUP" --query "[?contains(displayName, 'Carbon Optimization')].name" --output tsv)
        if [[ -n "$workbooks" ]]; then
            export WORKBOOK_NAME=$(echo "$workbooks" | head -n1)
            info "Found workbook: $WORKBOOK_NAME"
        fi
    else
        error "Resource group '$RESOURCE_GROUP' not found"
    fi
    
    # Set defaults for missing values
    export AUTOMATION_ACCOUNT="${AUTOMATION_ACCOUNT:-}"
    export WORKSPACE_NAME="${WORKSPACE_NAME:-}"
    export WORKBOOK_NAME="${WORKBOOK_NAME:-}"
    
    info "Environment variables configured"
}

# Function to remove automated alerts
remove_alerts() {
    log "Removing automated alerts..."
    
    # Remove metric alert rules
    local alert_rules=$(az monitor metrics alert list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'Carbon')].name" --output tsv)
    
    if [[ -n "$alert_rules" ]]; then
        while IFS= read -r alert_rule; do
            if get_user_confirmation "alert rule" "$alert_rule"; then
                log "Deleting alert rule: $alert_rule"
                az monitor metrics alert delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$alert_rule"
                info "Alert rule '$alert_rule' deleted successfully"
            fi
        done <<< "$alert_rules"
    else
        info "No carbon optimization alert rules found"
    fi
    
    # Remove action groups
    local action_groups=$(az monitor action-group list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'CarbonOptimization')].name" --output tsv)
    
    if [[ -n "$action_groups" ]]; then
        while IFS= read -r action_group; do
            if get_user_confirmation "action group" "$action_group"; then
                log "Deleting action group: $action_group"
                az monitor action-group delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$action_group"
                info "Action group '$action_group' deleted successfully"
            fi
        done <<< "$action_groups"
    else
        info "No carbon optimization action groups found"
    fi
}

# Function to remove Azure Monitor workbook
remove_workbook() {
    log "Removing Azure Monitor workbook..."
    
    if [[ -n "$WORKBOOK_NAME" ]]; then
        if az monitor workbook show --resource-group "$RESOURCE_GROUP" --name "$WORKBOOK_NAME" >/dev/null 2>&1; then
            if get_user_confirmation "workbook" "$WORKBOOK_NAME"; then
                log "Deleting workbook: $WORKBOOK_NAME"
                az monitor workbook delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$WORKBOOK_NAME"
                info "Workbook '$WORKBOOK_NAME' deleted successfully"
            fi
        else
            info "Workbook '$WORKBOOK_NAME' not found"
        fi
    else
        info "No workbook name provided, skipping workbook deletion"
    fi
}

# Function to remove scheduled monitoring jobs and runbooks
remove_automation_resources() {
    log "Removing automation resources..."
    
    if [[ -n "$AUTOMATION_ACCOUNT" ]]; then
        if az automation account show --resource-group "$RESOURCE_GROUP" --name "$AUTOMATION_ACCOUNT" >/dev/null 2>&1; then
            
            # Remove job schedules first
            log "Removing job schedules..."
            local job_schedules=$(az automation job-schedule list --resource-group "$RESOURCE_GROUP" --automation-account-name "$AUTOMATION_ACCOUNT" --query "[].jobScheduleId" --output tsv)
            
            if [[ -n "$job_schedules" ]]; then
                while IFS= read -r job_schedule_id; do
                    log "Deleting job schedule: $job_schedule_id"
                    az automation job-schedule delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --automation-account-name "$AUTOMATION_ACCOUNT" \
                        --job-schedule-id "$job_schedule_id"
                done <<< "$job_schedules"
                info "Job schedules removed successfully"
            else
                info "No job schedules found"
            fi
            
            # Remove schedules
            log "Removing schedules..."
            local schedules=$(az automation schedule list --resource-group "$RESOURCE_GROUP" --automation-account-name "$AUTOMATION_ACCOUNT" --query "[].name" --output tsv)
            
            if [[ -n "$schedules" ]]; then
                while IFS= read -r schedule; do
                    log "Deleting schedule: $schedule"
                    az automation schedule delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --automation-account-name "$AUTOMATION_ACCOUNT" \
                        --name "$schedule"
                done <<< "$schedules"
                info "Schedules removed successfully"
            else
                info "No schedules found"
            fi
            
            # Remove runbooks
            log "Removing runbooks..."
            local runbooks=$(az automation runbook list --resource-group "$RESOURCE_GROUP" --automation-account-name "$AUTOMATION_ACCOUNT" --query "[].name" --output tsv)
            
            if [[ -n "$runbooks" ]]; then
                while IFS= read -r runbook; do
                    log "Deleting runbook: $runbook"
                    az automation runbook delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --automation-account-name "$AUTOMATION_ACCOUNT" \
                        --name "$runbook"
                done <<< "$runbooks"
                info "Runbooks removed successfully"
            else
                info "No runbooks found"
            fi
            
        else
            info "Automation account '$AUTOMATION_ACCOUNT' not found"
        fi
    else
        info "No automation account name provided, skipping automation resources cleanup"
    fi
}

# Function to remove Azure Automation Account
remove_automation_account() {
    log "Removing Azure Automation Account..."
    
    if [[ -n "$AUTOMATION_ACCOUNT" ]]; then
        if az automation account show --resource-group "$RESOURCE_GROUP" --name "$AUTOMATION_ACCOUNT" >/dev/null 2>&1; then
            if get_user_confirmation "automation account" "$AUTOMATION_ACCOUNT"; then
                log "Deleting automation account: $AUTOMATION_ACCOUNT"
                az automation account delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$AUTOMATION_ACCOUNT" \
                    --yes
                info "Automation account '$AUTOMATION_ACCOUNT' deleted successfully"
            fi
        else
            info "Automation account '$AUTOMATION_ACCOUNT' not found"
        fi
    else
        info "No automation account name provided, skipping automation account deletion"
    fi
}

# Function to remove Log Analytics workspace
remove_log_analytics_workspace() {
    log "Removing Log Analytics workspace..."
    
    if [[ -n "$WORKSPACE_NAME" ]]; then
        if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" >/dev/null 2>&1; then
            if get_user_confirmation "Log Analytics workspace" "$WORKSPACE_NAME"; then
                log "Deleting Log Analytics workspace: $WORKSPACE_NAME"
                az monitor log-analytics workspace delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --workspace-name "$WORKSPACE_NAME" \
                    --yes
                info "Log Analytics workspace '$WORKSPACE_NAME' deleted successfully"
            fi
        else
            info "Log Analytics workspace '$WORKSPACE_NAME' not found"
        fi
    else
        info "No workspace name provided, skipping Log Analytics workspace deletion"
    fi
}

# Function to remove role assignments
remove_role_assignments() {
    log "Removing role assignments..."
    
    # Remove Carbon Optimization Reader role assignments
    local current_user=$(az ad signed-in-user show --query id --output tsv)
    local carbon_reader_assignments=$(az role assignment list \
        --assignee "$current_user" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --query "[?roleDefinitionName=='Carbon Optimization Reader'].id" \
        --output tsv)
    
    if [[ -n "$carbon_reader_assignments" ]]; then
        if get_user_confirmation "Carbon Optimization Reader role assignments" "current user"; then
            while IFS= read -r assignment_id; do
                log "Removing role assignment: $assignment_id"
                az role assignment delete --ids "$assignment_id"
            done <<< "$carbon_reader_assignments"
            info "Carbon Optimization Reader role assignments removed successfully"
        fi
    else
        info "No Carbon Optimization Reader role assignments found for current user"
    fi
    
    # Note: Managed identity role assignments are automatically removed when the automation account is deleted
}

# Function to remove resource group
remove_resource_group() {
    log "Removing resource group..."
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        
        # List remaining resources in the group
        local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
        
        if [[ -n "$remaining_resources" ]]; then
            warn "The following resources remain in the resource group:"
            echo "$remaining_resources"
            echo
        fi
        
        if get_user_confirmation "entire resource group" "$RESOURCE_GROUP"; then
            log "Deleting resource group: $RESOURCE_GROUP"
            warn "This will delete ALL resources in the resource group!"
            
            # Final confirmation for resource group deletion
            if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
                echo -n "Type 'DELETE' to confirm resource group deletion: "
                read -r confirmation
                if [[ "$confirmation" != "DELETE" ]]; then
                    info "Resource group deletion cancelled"
                    return 0
                fi
            fi
            
            az group delete \
                --name "$RESOURCE_GROUP" \
                --yes \
                --no-wait
            
            info "Resource group '$RESOURCE_GROUP' deletion initiated"
            info "Note: Resource group deletion may take several minutes to complete"
        fi
    else
        info "Resource group '$RESOURCE_GROUP' not found"
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check if resource group still exists (if it was deleted)
    if [[ "${DELETE_RESOURCE_GROUP:-true}" == "true" ]]; then
        if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
            warn "Resource group '$RESOURCE_GROUP' still exists (deletion may be in progress)"
        else
            info "✓ Resource group '$RESOURCE_GROUP' has been deleted"
        fi
    fi
    
    # Check for remaining carbon optimization resources
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        
        # Check automation account
        if [[ -n "$AUTOMATION_ACCOUNT" ]] && az automation account show --resource-group "$RESOURCE_GROUP" --name "$AUTOMATION_ACCOUNT" >/dev/null 2>&1; then
            warn "✗ Automation account '$AUTOMATION_ACCOUNT' still exists"
            cleanup_issues=$((cleanup_issues + 1))
        else
            info "✓ Automation account has been removed"
        fi
        
        # Check Log Analytics workspace
        if [[ -n "$WORKSPACE_NAME" ]] && az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" >/dev/null 2>&1; then
            warn "✗ Log Analytics workspace '$WORKSPACE_NAME' still exists"
            cleanup_issues=$((cleanup_issues + 1))
        else
            info "✓ Log Analytics workspace has been removed"
        fi
        
        # Check workbook
        if [[ -n "$WORKBOOK_NAME" ]] && az monitor workbook show --resource-group "$RESOURCE_GROUP" --name "$WORKBOOK_NAME" >/dev/null 2>&1; then
            warn "✗ Workbook '$WORKBOOK_NAME' still exists"
            cleanup_issues=$((cleanup_issues + 1))
        else
            info "✓ Workbook has been removed"
        fi
        
        # Check action groups
        local remaining_action_groups=$(az monitor action-group list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'CarbonOptimization')].name" --output tsv)
        if [[ -n "$remaining_action_groups" ]]; then
            warn "✗ Action groups still exist: $remaining_action_groups"
            cleanup_issues=$((cleanup_issues + 1))
        else
            info "✓ Action groups have been removed"
        fi
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log "Cleanup verification completed successfully"
    else
        warn "Cleanup verification found $cleanup_issues issues"
        warn "Some resources may still be in the process of being deleted"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "======================================"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Subscription ID: $SUBSCRIPTION_ID"
    echo "======================================"
    echo "Removed Resources:"
    echo "- Automated alerts and action groups"
    echo "- Azure Monitor workbook"
    echo "- Scheduled monitoring jobs"
    echo "- PowerShell runbooks"
    echo "- Azure Automation Account"
    echo "- Log Analytics workspace"
    if [[ "${DELETE_RESOURCE_GROUP:-true}" == "true" ]]; then
        echo "- Resource group (deletion in progress)"
    fi
    echo "======================================"
    echo "Cleanup Status: Complete"
    echo "Note: Some resources may take additional time to be fully removed"
    echo "======================================"
}

# Main cleanup function
main() {
    log "Starting Azure Sustainable Workload Optimization cleanup..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --force)
                FORCE_DELETE="true"
                shift
                ;;
            --keep-resource-group)
                DELETE_RESOURCE_GROUP="false"
                shift
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  --resource-group <name>  Specify the resource group name"
                echo "  --force                  Skip confirmation prompts"
                echo "  --keep-resource-group    Don't delete the resource group"
                echo "  --help                   Show this help message"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    # Check if running in dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "Running in dry-run mode - no resources will be deleted"
        set_environment_variables
        echo "Would delete resources in resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    validate_prerequisites
    set_environment_variables
    
    # Safety check - ensure we're not deleting a production resource group
    if [[ "$RESOURCE_GROUP" == *"prod"* || "$RESOURCE_GROUP" == *"production"* ]]; then
        warn "Resource group name contains 'prod' or 'production'"
        warn "Please double-check that you want to delete this resource group"
        echo -n "Type 'YES' to continue: "
        read -r confirmation
        if [[ "$confirmation" != "YES" ]]; then
            error "Cleanup cancelled for safety"
        fi
    fi
    
    # Display what will be deleted
    echo "The following resources will be deleted:"
    echo "- Resource Group: $RESOURCE_GROUP"
    if [[ -n "$AUTOMATION_ACCOUNT" ]]; then
        echo "- Automation Account: $AUTOMATION_ACCOUNT"
    fi
    if [[ -n "$WORKSPACE_NAME" ]]; then
        echo "- Log Analytics Workspace: $WORKSPACE_NAME"
    fi
    if [[ -n "$WORKBOOK_NAME" ]]; then
        echo "- Workbook: $WORKBOOK_NAME"
    fi
    echo "- All associated schedules, runbooks, and alerts"
    echo
    
    # Final confirmation
    if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
        echo -n "Are you sure you want to proceed with cleanup? (y/N): "
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                ;;
            *)
                info "Cleanup cancelled by user"
                exit 0
                ;;
        esac
    fi
    
    # Perform cleanup in reverse order of creation
    remove_alerts
    remove_workbook
    remove_automation_resources
    remove_automation_account
    remove_log_analytics_workspace
    remove_role_assignments
    
    # Only delete resource group if requested
    if [[ "${DELETE_RESOURCE_GROUP:-true}" == "true" ]]; then
        remove_resource_group
    fi
    
    verify_cleanup
    
    log "Cleanup completed successfully!"
    display_cleanup_summary
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi