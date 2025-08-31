#!/bin/bash

# Budget Alert Notifications with Cost Management and Logic Apps - Cleanup Script
# This script removes all Azure resources created for budget monitoring

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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

# Banner
echo "=============================================="
echo "  Azure Budget Alert Notifications Cleanup"
echo "=============================================="
echo ""

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Get resource information from user input or environment
get_resource_information() {
    log_info "Getting resource information..."
    
    # If environment variables are not set, try to get them from user
    if [ -z "${RESOURCE_GROUP:-}" ]; then
        echo ""
        echo "Please provide the resource group name to delete."
        echo "This should be in the format: rg-budget-alerts-XXXXXX"
        echo ""
        read -p "Resource Group Name: " RESOURCE_GROUP
        
        if [ -z "${RESOURCE_GROUP}" ]; then
            log_error "Resource group name is required"
            exit 1
        fi
    fi
    
    # Extract random suffix from resource group name for budget cleanup
    if [[ "${RESOURCE_GROUP}" =~ rg-budget-alerts-([a-f0-9]{6})$ ]]; then
        RANDOM_SUFFIX="${BASH_REMATCH[1]}"
        export BUDGET_NAME="budget-demo-${RANDOM_SUFFIX}"
        export ACTION_GROUP_NAME="ag-budget-${RANDOM_SUFFIX}"
        export LOGIC_APP_NAME="la-budget-alerts-${RANDOM_SUFFIX}"
        export STORAGE_ACCOUNT_NAME="st${RANDOM_SUFFIX}"
    else
        log_warning "Could not extract random suffix from resource group name"
        log_warning "You may need to manually clean up the budget if it exists"
        
        # Try to get budget name from user
        echo ""
        echo "If you know the budget name, please provide it (or press Enter to skip):"
        read -p "Budget Name (optional): " BUDGET_NAME
    fi
    
    log_info "Resource Group: ${RESOURCE_GROUP}"
    if [ -n "${BUDGET_NAME:-}" ]; then
        log_info "Budget Name: ${BUDGET_NAME}"
    fi
}

# Verify resource group exists
verify_resource_group() {
    log_info "Verifying resource group exists..."
    
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Resource group '${RESOURCE_GROUP}' does not exist"
        log_info "Available resource groups:"
        az group list --query "[].name" --output table
        exit 1
    fi
    
    log_success "Resource group found: ${RESOURCE_GROUP}"
}

# Display resources to be deleted
display_resources() {
    log_info "Resources that will be deleted:"
    echo ""
    
    # List resources in the resource group
    local resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" --output table 2>/dev/null)
    
    if [ -n "$resources" ]; then
        echo "$resources"
    else
        log_warning "No resources found in resource group ${RESOURCE_GROUP}"
    fi
    
    echo ""
    
    # Check for budget
    if [ -n "${BUDGET_NAME:-}" ]; then
        if az consumption budget show --budget-name "${BUDGET_NAME}" &> /dev/null; then
            log_info "Budget to be deleted: ${BUDGET_NAME}"
        else
            log_warning "Budget ${BUDGET_NAME} not found or already deleted"
        fi
    fi
    
    echo ""
}

# Confirm deletion
confirm_deletion() {
    log_warning "This action will permanently delete all resources listed above."
    log_warning "This action cannot be undone."
    echo ""
    
    # Double confirmation for safety
    read -p "Are you sure you want to proceed? (yes/no): " confirm1
    if [ "$confirm1" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Please type 'DELETE' to confirm: " confirm2
    if [ "$confirm2" != "DELETE" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource deletion..."
}

# Delete budget
delete_budget() {
    if [ -n "${BUDGET_NAME:-}" ]; then
        log_info "Deleting budget: ${BUDGET_NAME}"
        
        if az consumption budget show --budget-name "${BUDGET_NAME}" &> /dev/null; then
            az consumption budget delete --budget-name "${BUDGET_NAME}"
            log_success "Budget deleted: ${BUDGET_NAME}"
        else
            log_warning "Budget ${BUDGET_NAME} not found or already deleted"
        fi
    else
        log_info "No budget name provided, skipping budget deletion"
        log_info "If a budget exists, you may need to delete it manually from the Azure portal"
    fi
}

# Delete Action Group (if exists separately)
delete_action_group() {
    if [ -n "${ACTION_GROUP_NAME:-}" ]; then
        log_info "Checking for Action Group: ${ACTION_GROUP_NAME}"
        
        if az monitor action-group show --name "${ACTION_GROUP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            log_info "Deleting Action Group: ${ACTION_GROUP_NAME}"
            az monitor action-group delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${ACTION_GROUP_NAME}"
            log_success "Action Group deleted: ${ACTION_GROUP_NAME}"
        else
            log_info "Action Group ${ACTION_GROUP_NAME} not found or already deleted"
        fi
    fi
}

# Delete resource group and all resources
delete_resource_group() {
    log_info "Deleting resource group and all contained resources: ${RESOURCE_GROUP}"
    log_info "This may take several minutes..."
    
    # Delete resource group with all resources
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Note: Deletion may take several minutes to complete"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    # Wait a moment for deletion to start
    sleep 5
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        local state=$(az group show --name "${RESOURCE_GROUP}" --query properties.provisioningState --output tsv 2>/dev/null || echo "Unknown")
        if [ "$state" == "Deleting" ]; then
            log_info "Resource group is being deleted (State: ${state})"
            log_info "You can monitor the deletion with:"
            echo "  az group show --name ${RESOURCE_GROUP} --query properties.provisioningState --output tsv"
        else
            log_warning "Resource group still exists with state: ${state}"
        fi
    else
        log_success "Resource group successfully deleted"
    fi
    
    # Check budget deletion
    if [ -n "${BUDGET_NAME:-}" ]; then
        if az consumption budget show --budget-name "${BUDGET_NAME}" &> /dev/null; then
            log_warning "Budget ${BUDGET_NAME} still exists"
        else
            log_success "Budget successfully deleted"
        fi
    fi
}

# Display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "=============================================="
    echo "  Cleanup Summary"
    echo "=============================================="
    echo ""
    log_success "Cleanup process completed!"
    echo ""
    echo "Resources cleaned up:"
    echo "- Resource Group: ${RESOURCE_GROUP}"
    if [ -n "${BUDGET_NAME:-}" ]; then
        echo "- Budget: ${BUDGET_NAME}"
    fi
    if [ -n "${ACTION_GROUP_NAME:-}" ]; then
        echo "- Action Group: ${ACTION_GROUP_NAME}"
    fi
    if [ -n "${LOGIC_APP_NAME:-}" ]; then
        echo "- Logic App: ${LOGIC_APP_NAME}"
    fi
    if [ -n "${STORAGE_ACCOUNT_NAME:-}" ]; then
        echo "- Storage Account: ${STORAGE_ACCOUNT_NAME}"
    fi
    echo ""
    echo "All resources have been scheduled for deletion."
    echo "Some resources may take additional time to be fully removed."
    echo ""
    echo "You can verify complete deletion by checking that these commands return no results:"
    echo "  az group show --name ${RESOURCE_GROUP}"
    if [ -n "${BUDGET_NAME:-}" ]; then
        echo "  az consumption budget show --budget-name ${BUDGET_NAME}"
    fi
    echo ""
}

# Error handling function
handle_error() {
    log_error "An error occurred during cleanup"
    log_info "Some resources may still exist and need manual cleanup"
    log_info "Check the Azure portal for any remaining resources"
    exit 1
}

# Set trap for error handling
trap handle_error ERR

# Main execution
main() {
    check_prerequisites
    get_resource_information
    verify_resource_group
    display_resources
    confirm_deletion
    
    delete_budget
    delete_action_group
    delete_resource_group
    
    verify_cleanup
    display_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Azure Budget Alert Notifications Cleanup Script"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --force, -f         Skip confirmation prompts (use with caution)"
        echo ""
        echo "Environment Variables:"
        echo "  RESOURCE_GROUP      Name of the resource group to delete"
        echo "  BUDGET_NAME         Name of the budget to delete (optional)"
        echo ""
        echo "Examples:"
        echo "  $0                                    # Interactive mode"
        echo "  RESOURCE_GROUP=rg-budget-alerts-abc123 $0  # Specify resource group"
        echo "  $0 --force                           # Skip confirmations"
        echo ""
        exit 0
        ;;
    --force|-f)
        log_warning "Force mode enabled - skipping confirmation prompts"
        export SKIP_CONFIRMATION=true
        ;;
    "")
        # No arguments, proceed normally
        ;;
    *)
        log_error "Unknown argument: $1"
        log_info "Use --help for usage information"
        exit 1
        ;;
esac

# Override confirmation function if force mode is enabled
if [ "${SKIP_CONFIRMATION:-false}" == "true" ]; then
    confirm_deletion() {
        log_warning "Force mode: Skipping confirmation prompts"
        log_info "Proceeding with resource deletion..."
    }
fi

# Run main function
main "$@"