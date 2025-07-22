#!/bin/bash

# =============================================================================
# Destroy Script for Azure Security Governance Workflows
# Recipe: Event-Driven Security Governance with Event Grid and Managed Identity
# =============================================================================

set -e
set -o pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment_info.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "$ERROR_LOG"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    log_error "Error occurred in script at line $1. Exit code: $2"
    log_error "Check $ERROR_LOG for more details"
    log_warning "Continuing with cleanup..."
}

trap 'handle_error $LINENO $?' ERR

# Functions
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Check required tools
    local required_tools=("jq")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool '$tool' is not installed"
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

load_deployment_info() {
    log "Loading deployment information..."
    
    if [ ! -f "$DEPLOYMENT_INFO_FILE" ]; then
        log_warning "Deployment info file not found. Will attempt to discover resources by pattern."
        return 1
    fi
    
    # Load deployment info from JSON file
    export RESOURCE_GROUP=$(jq -r '.resource_group' "$DEPLOYMENT_INFO_FILE")
    export LOCATION=$(jq -r '.location' "$DEPLOYMENT_INFO_FILE")
    export SUBSCRIPTION_ID=$(jq -r '.subscription_id' "$DEPLOYMENT_INFO_FILE")
    export EVENT_GRID_TOPIC=$(jq -r '.resources.event_grid_topic' "$DEPLOYMENT_INFO_FILE")
    export FUNCTION_APP=$(jq -r '.resources.function_app' "$DEPLOYMENT_INFO_FILE")
    export STORAGE_ACCOUNT=$(jq -r '.resources.storage_account' "$DEPLOYMENT_INFO_FILE")
    export LOG_ANALYTICS_WORKSPACE=$(jq -r '.resources.log_analytics_workspace' "$DEPLOYMENT_INFO_FILE")
    export ACTION_GROUP=$(jq -r '.resources.action_group' "$DEPLOYMENT_INFO_FILE")
    export FUNCTION_PRINCIPAL_ID=$(jq -r '.resources.function_principal_id' "$DEPLOYMENT_INFO_FILE")
    export RANDOM_SUFFIX=$(jq -r '.random_suffix' "$DEPLOYMENT_INFO_FILE")
    
    log "Loaded deployment info:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  Subscription ID: $SUBSCRIPTION_ID"
    log "  Random Suffix: $RANDOM_SUFFIX"
    
    log_success "Deployment information loaded successfully"
    return 0
}

discover_resources() {
    log "Discovering resources by pattern..."
    
    # Get current subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Try to find resource groups matching the pattern
    local resource_groups=$(az group list --query "[?starts_with(name, 'rg-security-governance-')].name" --output tsv)
    
    if [ -z "$resource_groups" ]; then
        log_error "No resource groups found matching pattern 'rg-security-governance-*'"
        log_error "Manual cleanup may be required"
        return 1
    fi
    
    # If multiple resource groups found, prompt user
    local rg_count=$(echo "$resource_groups" | wc -l)
    if [ "$rg_count" -gt 1 ]; then
        log_warning "Multiple resource groups found:"
        echo "$resource_groups" | nl
        read -p "Enter the number of the resource group to delete (or 'all' to delete all): " choice
        
        if [ "$choice" = "all" ]; then
            export RESOURCE_GROUP_LIST="$resource_groups"
        else
            export RESOURCE_GROUP=$(echo "$resource_groups" | sed -n "${choice}p")
        fi
    else
        export RESOURCE_GROUP="$resource_groups"
    fi
    
    log_success "Resource discovery completed"
    return 0
}

get_user_confirmation() {
    log "Requesting user confirmation for resource deletion..."
    
    if [ -n "$RESOURCE_GROUP_LIST" ]; then
        echo -e "${YELLOW}The following resource groups will be deleted:${NC}"
        echo "$RESOURCE_GROUP_LIST"
    elif [ -n "$RESOURCE_GROUP" ]; then
        echo -e "${YELLOW}The following resource group will be deleted:${NC} $RESOURCE_GROUP"
    else
        log_error "No resource group identified for deletion"
        return 1
    fi
    
    echo -e "${RED}WARNING: This action cannot be undone!${NC}"
    echo -e "${RED}All resources in the resource group(s) will be permanently deleted.${NC}"
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log_success "User confirmation received"
}

remove_test_resources() {
    log "Removing test resources..."
    
    # Try to remove test VMs that might have been created during validation
    local test_vms=$(az vm list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?starts_with(name, 'test-vm-')].name" \
        --output tsv 2>/dev/null || true)
    
    if [ -n "$test_vms" ]; then
        log "Found test VMs to remove: $test_vms"
        for vm in $test_vms; do
            log "Deleting test VM: $vm"
            az vm delete \
                --name "$vm" \
                --resource-group "$RESOURCE_GROUP" \
                --yes \
                --no-wait \
                --output none 2>/dev/null || log_warning "Failed to delete test VM: $vm"
        done
    fi
    
    log_success "Test resources cleanup completed"
}

remove_event_grid_resources() {
    log "Removing Event Grid resources..."
    
    # Remove Event Grid subscription
    local subscriptions=$(az eventgrid event-subscription list \
        --source-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
        --query "[].name" --output tsv 2>/dev/null || true)
    
    if [ -n "$subscriptions" ]; then
        for subscription in $subscriptions; do
            log "Deleting Event Grid subscription: $subscription"
            az eventgrid event-subscription delete \
                --name "$subscription" \
                --source-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
                --output none 2>/dev/null || log_warning "Failed to delete subscription: $subscription"
        done
    fi
    
    # Remove Event Grid topic
    if [ -n "$EVENT_GRID_TOPIC" ]; then
        log "Deleting Event Grid topic: $EVENT_GRID_TOPIC"
        az eventgrid topic delete \
            --name "$EVENT_GRID_TOPIC" \
            --resource-group "$RESOURCE_GROUP" \
            --output none 2>/dev/null || log_warning "Failed to delete Event Grid topic: $EVENT_GRID_TOPIC"
    else
        # Try to find Event Grid topics in the resource group
        local topics=$(az eventgrid topic list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].name" --output tsv 2>/dev/null || true)
        
        if [ -n "$topics" ]; then
            for topic in $topics; do
                log "Deleting Event Grid topic: $topic"
                az eventgrid topic delete \
                    --name "$topic" \
                    --resource-group "$RESOURCE_GROUP" \
                    --output none 2>/dev/null || log_warning "Failed to delete topic: $topic"
            done
        fi
    fi
    
    log_success "Event Grid resources removed"
}

remove_function_app() {
    log "Removing Function App..."
    
    if [ -n "$FUNCTION_APP" ]; then
        log "Deleting Function App: $FUNCTION_APP"
        az functionapp delete \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --output none 2>/dev/null || log_warning "Failed to delete Function App: $FUNCTION_APP"
    else
        # Try to find Function Apps in the resource group
        local function_apps=$(az functionapp list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].name" --output tsv 2>/dev/null || true)
        
        if [ -n "$function_apps" ]; then
            for app in $function_apps; do
                log "Deleting Function App: $app"
                az functionapp delete \
                    --name "$app" \
                    --resource-group "$RESOURCE_GROUP" \
                    --output none 2>/dev/null || log_warning "Failed to delete Function App: $app"
            done
        fi
    fi
    
    log_success "Function App removed"
}

remove_monitoring_resources() {
    log "Removing monitoring resources..."
    
    # Remove alert rules
    local alert_rules=$(az monitor metrics alert list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" --output tsv 2>/dev/null || true)
    
    if [ -n "$alert_rules" ]; then
        for rule in $alert_rules; do
            log "Deleting alert rule: $rule"
            az monitor metrics alert delete \
                --name "$rule" \
                --resource-group "$RESOURCE_GROUP" \
                --output none 2>/dev/null || log_warning "Failed to delete alert rule: $rule"
        done
    fi
    
    # Remove action groups
    if [ -n "$ACTION_GROUP" ]; then
        log "Deleting action group: $ACTION_GROUP"
        az monitor action-group delete \
            --name "$ACTION_GROUP" \
            --resource-group "$RESOURCE_GROUP" \
            --output none 2>/dev/null || log_warning "Failed to delete action group: $ACTION_GROUP"
    else
        local action_groups=$(az monitor action-group list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].name" --output tsv 2>/dev/null || true)
        
        if [ -n "$action_groups" ]; then
            for group in $action_groups; do
                log "Deleting action group: $group"
                az monitor action-group delete \
                    --name "$group" \
                    --resource-group "$RESOURCE_GROUP" \
                    --output none 2>/dev/null || log_warning "Failed to delete action group: $group"
            done
        fi
    fi
    
    # Remove Application Insights
    local app_insights=$(az monitor app-insights component list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" --output tsv 2>/dev/null || true)
    
    if [ -n "$app_insights" ]; then
        for insight in $app_insights; do
            log "Deleting Application Insights: $insight"
            az monitor app-insights component delete \
                --app "$insight" \
                --resource-group "$RESOURCE_GROUP" \
                --output none 2>/dev/null || log_warning "Failed to delete Application Insights: $insight"
        done
    fi
    
    log_success "Monitoring resources removed"
}

remove_log_analytics_workspace() {
    log "Removing Log Analytics workspace..."
    
    if [ -n "$LOG_ANALYTICS_WORKSPACE" ]; then
        log "Deleting Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
        az monitor log-analytics workspace delete \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --yes \
            --force true \
            --output none 2>/dev/null || log_warning "Failed to delete Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
    else
        # Try to find Log Analytics workspaces in the resource group
        local workspaces=$(az monitor log-analytics workspace list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].name" --output tsv 2>/dev/null || true)
        
        if [ -n "$workspaces" ]; then
            for workspace in $workspaces; do
                log "Deleting Log Analytics workspace: $workspace"
                az monitor log-analytics workspace delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --workspace-name "$workspace" \
                    --yes \
                    --force true \
                    --output none 2>/dev/null || log_warning "Failed to delete workspace: $workspace"
            done
        fi
    fi
    
    log_success "Log Analytics workspace removed"
}

remove_storage_account() {
    log "Removing storage account..."
    
    if [ -n "$STORAGE_ACCOUNT" ]; then
        log "Deleting storage account: $STORAGE_ACCOUNT"
        az storage account delete \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none 2>/dev/null || log_warning "Failed to delete storage account: $STORAGE_ACCOUNT"
    else
        # Try to find storage accounts in the resource group
        local storage_accounts=$(az storage account list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].name" --output tsv 2>/dev/null || true)
        
        if [ -n "$storage_accounts" ]; then
            for account in $storage_accounts; do
                log "Deleting storage account: $account"
                az storage account delete \
                    --name "$account" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes \
                    --output none 2>/dev/null || log_warning "Failed to delete storage account: $account"
            done
        fi
    fi
    
    log_success "Storage account removed"
}

remove_rbac_assignments() {
    log "Removing RBAC assignments..."
    
    if [ -n "$FUNCTION_PRINCIPAL_ID" ]; then
        log "Removing RBAC assignments for principal: $FUNCTION_PRINCIPAL_ID"
        
        # List and remove role assignments
        local assignments=$(az role assignment list \
            --assignee "$FUNCTION_PRINCIPAL_ID" \
            --query "[].id" --output tsv 2>/dev/null || true)
        
        if [ -n "$assignments" ]; then
            for assignment in $assignments; do
                log "Removing role assignment: $assignment"
                az role assignment delete \
                    --ids "$assignment" \
                    --output none 2>/dev/null || log_warning "Failed to remove role assignment: $assignment"
            done
        fi
    fi
    
    log_success "RBAC assignments removed"
}

remove_resource_group() {
    log "Removing resource group..."
    
    if [ -n "$RESOURCE_GROUP_LIST" ]; then
        # Remove multiple resource groups
        for rg in $RESOURCE_GROUP_LIST; do
            log "Deleting resource group: $rg"
            az group delete \
                --name "$rg" \
                --yes \
                --no-wait \
                --output none 2>/dev/null || log_warning "Failed to delete resource group: $rg"
        done
    elif [ -n "$RESOURCE_GROUP" ]; then
        # Remove single resource group
        log "Deleting resource group: $RESOURCE_GROUP"
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output none 2>/dev/null || log_warning "Failed to delete resource group: $RESOURCE_GROUP"
    else
        log_error "No resource group specified for deletion"
        return 1
    fi
    
    log_success "Resource group deletion initiated"
}

verify_cleanup() {
    log "Verifying cleanup..."
    
    if [ -n "$RESOURCE_GROUP" ]; then
        # Check if resource group still exists
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log_warning "Resource group $RESOURCE_GROUP still exists (deletion may be in progress)"
            
            # Check remaining resources
            local remaining_resources=$(az resource list \
                --resource-group "$RESOURCE_GROUP" \
                --query "length([])" --output tsv 2>/dev/null || echo "0")
            
            if [ "$remaining_resources" -gt 0 ]; then
                log_warning "$remaining_resources resources still exist in the resource group"
                log "Deletion may take several minutes to complete"
            fi
        else
            log_success "Resource group $RESOURCE_GROUP has been deleted"
        fi
    fi
    
    log_success "Cleanup verification completed"
}

cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment info file
    if [ -f "$DEPLOYMENT_INFO_FILE" ]; then
        rm -f "$DEPLOYMENT_INFO_FILE"
        log_success "Removed deployment info file"
    fi
    
    # Remove any temporary files
    rm -f "${SCRIPT_DIR}"/security-function*.zip 2>/dev/null || true
    
    log_success "Local files cleaned up"
}

print_cleanup_summary() {
    log "Cleanup Summary:"
    log "================"
    
    if [ -n "$RESOURCE_GROUP_LIST" ]; then
        log "Resource Groups Deleted:"
        echo "$RESOURCE_GROUP_LIST" | while read -r rg; do
            log "  - $rg"
        done
    elif [ -n "$RESOURCE_GROUP" ]; then
        log "Resource Group Deleted: $RESOURCE_GROUP"
    fi
    
    log ""
    log "Cleanup process completed successfully!"
    log "Note: Resource deletion may take several minutes to complete in Azure"
    log ""
    log "Check the cleanup logs at: $LOG_FILE"
    
    if [ -f "$ERROR_LOG" ]; then
        log_warning "Some warnings/errors were logged to: $ERROR_LOG"
    fi
}

# Main execution
main() {
    log "Starting Azure Security Governance Workflows cleanup..."
    log "======================================================="
    
    check_prerequisites
    
    # Try to load deployment info, fallback to discovery if not available
    if ! load_deployment_info; then
        if ! discover_resources; then
            log_error "Unable to identify resources for cleanup"
            exit 1
        fi
    fi
    
    get_user_confirmation
    
    # Perform cleanup in reverse order of creation
    remove_test_resources
    remove_event_grid_resources
    remove_function_app
    remove_monitoring_resources
    remove_log_analytics_workspace
    remove_storage_account
    remove_rbac_assignments
    remove_resource_group
    verify_cleanup
    cleanup_local_files
    print_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Run main function
main "$@"