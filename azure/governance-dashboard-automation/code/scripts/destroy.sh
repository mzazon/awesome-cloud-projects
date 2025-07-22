#!/bin/bash

# Destroy script for Azure Governance Dashboards with Resource Graph and Monitor Workbooks
# This script safely removes all resources created by the deploy.sh script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Azure CLI login status
check_azure_login() {
    log_info "Checking Azure CLI authentication..."
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    log_success "Azure CLI authentication verified"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    check_azure_login
    log_success "All prerequisites met"
}

# Function to load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [ -f ".deployment_state" ]; then
        source .deployment_state
        log_success "Deployment state loaded from .deployment_state"
        log_info "Resource Group: $RESOURCE_GROUP"
        log_info "Subscription: $SUBSCRIPTION_ID"
    else
        log_warning "No .deployment_state file found. Using environment variables or defaults."
        
        # Set default values if not provided
        export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-governance-dashboard}"
        export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
        
        log_info "Using Resource Group: $RESOURCE_GROUP"
        log_info "Using Subscription: $SUBSCRIPTION_ID"
    fi
}

# Function to confirm destructive action
confirm_destruction() {
    echo
    log_warning "This script will DELETE the following resources:"
    echo "  • Resource Group: $RESOURCE_GROUP"
    echo "  • All contained resources (Workbooks, Logic Apps, Log Analytics, etc.)"
    echo
    log_warning "This action is IRREVERSIBLE!"
    echo
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Operation cancelled by user."
        exit 0
    fi
    
    log_info "Confirmed. Proceeding with resource deletion..."
}

# Function to check if resource group exists
check_resource_group_exists() {
    log_info "Checking if resource group exists..."
    
    if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Resource group '$RESOURCE_GROUP' does not exist."
        log_info "Nothing to clean up."
        exit 0
    fi
    
    log_success "Resource group '$RESOURCE_GROUP' found."
}

# Function to list resources to be deleted
list_resources() {
    log_info "Listing resources to be deleted..."
    
    echo "Resources in '$RESOURCE_GROUP':"
    az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].{Name:name, Type:type, Location:location}" \
        --output table || log_warning "Could not list resources"
    echo
}

# Function to delete alert rules
delete_alert_rules() {
    log_info "Deleting alert rules..."
    
    # Delete scheduled query rules
    local queries=$(az monitor scheduled-query list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" --output tsv 2>/dev/null || true)
    
    if [ -n "$queries" ]; then
        for query in $queries; do
            log_info "Deleting scheduled query rule: $query"
            az monitor scheduled-query delete \
                --name "$query" \
                --resource-group "$RESOURCE_GROUP" \
                --yes >/dev/null 2>&1 || log_warning "Failed to delete query rule: $query"
        done
        log_success "Alert rules deleted"
    else
        log_info "No alert rules found to delete"
    fi
    
    # Delete metric alert rules (if any)
    local alerts=$(az monitor metrics alert list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" --output tsv 2>/dev/null || true)
    
    if [ -n "$alerts" ]; then
        for alert in $alerts; do
            log_info "Deleting metric alert rule: $alert"
            az monitor metrics alert delete \
                --name "$alert" \
                --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 || log_warning "Failed to delete alert rule: $alert"
        done
        log_success "Metric alert rules deleted"
    else
        log_info "No metric alert rules found to delete"
    fi
}

# Function to delete action groups
delete_action_groups() {
    log_info "Deleting action groups..."
    
    local action_groups=$(az monitor action-group list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" --output tsv 2>/dev/null || true)
    
    if [ -n "$action_groups" ]; then
        for ag in $action_groups; do
            log_info "Deleting action group: $ag"
            az monitor action-group delete \
                --name "$ag" \
                --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1 || log_warning "Failed to delete action group: $ag"
        done
        log_success "Action groups deleted"
    else
        log_info "No action groups found to delete"
    fi
}

# Function to delete Logic Apps
delete_logic_apps() {
    log_info "Deleting Logic Apps..."
    
    local logic_apps=$(az logic workflow list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" --output tsv 2>/dev/null || true)
    
    if [ -n "$logic_apps" ]; then
        for app in $logic_apps; do
            log_info "Deleting Logic App: $app"
            az logic workflow delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$app" \
                --yes >/dev/null 2>&1 || log_warning "Failed to delete Logic App: $app"
        done
        log_success "Logic Apps deleted"
    else
        log_info "No Logic Apps found to delete"
    fi
}

# Function to delete workbooks
delete_workbooks() {
    log_info "Deleting Azure Monitor Workbooks..."
    
    # List workbooks using REST API
    local workbooks=$(az rest \
        --method GET \
        --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/workbooks?api-version=2021-03-08" \
        --query "value[].name" --output tsv 2>/dev/null || true)
    
    if [ -n "$workbooks" ]; then
        for workbook in $workbooks; do
            log_info "Deleting workbook: $workbook"
            az rest \
                --method DELETE \
                --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Insights/workbooks/$workbook?api-version=2021-03-08" >/dev/null 2>&1 || log_warning "Failed to delete workbook: $workbook"
        done
        log_success "Workbooks deleted"
    else
        log_info "No workbooks found to delete"
    fi
}

# Function to delete Log Analytics workspaces
delete_log_analytics_workspaces() {
    log_info "Deleting Log Analytics workspaces..."
    
    local workspaces=$(az monitor log-analytics workspace list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" --output tsv 2>/dev/null || true)
    
    if [ -n "$workspaces" ]; then
        for workspace in $workspaces; do
            log_info "Deleting Log Analytics workspace: $workspace"
            az monitor log-analytics workspace delete \
                --resource-group "$RESOURCE_GROUP" \
                --workspace-name "$workspace" \
                --force true \
                --yes >/dev/null 2>&1 || log_warning "Failed to delete workspace: $workspace"
        done
        log_success "Log Analytics workspaces deleted"
    else
        log_info "No Log Analytics workspaces found to delete"
    fi
}

# Function to delete remaining resources
delete_remaining_resources() {
    log_info "Checking for any remaining resources..."
    
    local remaining=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" --output tsv 2>/dev/null || true)
    
    if [ -n "$remaining" ]; then
        log_warning "Found remaining resources. Attempting individual deletion..."
        for resource in $remaining; do
            log_info "Attempting to delete resource: $resource"
            az resource delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$resource" \
                --resource-type "$(az resource list --resource-group "$RESOURCE_GROUP" --name "$resource" --query "[0].type" --output tsv)" >/dev/null 2>&1 || log_warning "Failed to delete resource: $resource"
        done
    else
        log_info "No remaining resources found"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log_info "Deleting resource group..."
    
    # Final confirmation for resource group deletion
    echo
    log_warning "About to delete the entire resource group: $RESOURCE_GROUP"
    read -p "Type the resource group name to confirm deletion: " rg_confirmation
    
    if [ "$rg_confirmation" != "$RESOURCE_GROUP" ]; then
        log_error "Resource group name mismatch. Aborting deletion."
        exit 1
    fi
    
    log_info "Deleting resource group: $RESOURCE_GROUP"
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: $RESOURCE_GROUP"
    log_info "Note: Deletion may take several minutes to complete"
}

# Function to wait for resource group deletion
wait_for_deletion() {
    log_info "Waiting for resource group deletion to complete..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
            log_success "Resource group successfully deleted"
            return 0
        fi
        
        log_info "Attempt $attempt/$max_attempts: Resource group still exists, waiting..."
        sleep 10
        ((attempt++))
    done
    
    log_warning "Resource group deletion is taking longer than expected"
    log_info "You can check the status in the Azure portal or run: az group show --name $RESOURCE_GROUP"
}

# Function to cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment state file
    if [ -f ".deployment_state" ]; then
        rm -f .deployment_state
        log_success "Removed .deployment_state file"
    fi
    
    # Remove any temporary files that might exist
    rm -f governance-queries.kql governance-workbook-template.json 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

# Function to display destruction summary
display_summary() {
    log_success "Cleanup completed successfully!"
    echo
    echo "=== Destruction Summary ==="
    echo "Resource Group: $RESOURCE_GROUP (deleted)"
    echo "Subscription: $SUBSCRIPTION_ID"
    echo
    echo "=== Deleted Resources ==="
    echo "• Alert rules and scheduled queries"
    echo "• Action groups"
    echo "• Logic Apps"
    echo "• Azure Monitor Workbooks"
    echo "• Log Analytics workspaces"
    echo "• Resource group and all contained resources"
    echo
    echo "=== Cleanup Status ==="
    echo "• Local state files removed"
    echo "• Temporary files cleaned up"
    echo
    echo "All governance dashboard resources have been successfully removed."
}

# Main destruction function
main() {
    log_info "Starting Azure Governance Dashboard cleanup..."
    echo "========================================================"
    
    check_prerequisites
    load_deployment_state
    check_resource_group_exists
    list_resources
    confirm_destruction
    
    # Delete resources in reverse dependency order
    delete_alert_rules
    delete_action_groups
    delete_logic_apps
    delete_workbooks
    delete_log_analytics_workspaces
    delete_remaining_resources
    delete_resource_group
    
    # Wait for completion and cleanup
    wait_for_deletion
    cleanup_local_files
    
    echo "========================================================"
    display_summary
}

# Error handling
handle_error() {
    local exit_code=$?
    log_error "Cleanup failed on line $LINENO"
    log_warning "Some resources may still exist. Please check the Azure portal."
    log_info "You can attempt to delete the resource group manually: az group delete --name $RESOURCE_GROUP"
    exit $exit_code
}

trap 'handle_error' ERR

# Check for force flag
if [ "${1:-}" = "--force" ] || [ "${1:-}" = "-f" ]; then
    log_warning "Force flag detected. Skipping confirmation prompts."
    FORCE_DELETE=true
else
    FORCE_DELETE=false
fi

# Override confirmation function if force flag is used
if [ "$FORCE_DELETE" = true ]; then
    confirm_destruction() {
        log_warning "Force delete enabled. Proceeding without confirmation."
    }
fi

# Run main function
main "$@"