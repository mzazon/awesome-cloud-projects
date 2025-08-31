#!/bin/bash

# Destroy script for Simple Cost Budget Tracking with Cost Management
# This script removes all Azure resources created by the deploy.sh script

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ -f "deployment-state.json" ]]; then
        # Load variables from deployment state
        RESOURCE_GROUP=$(jq -r '.resource_group' deployment-state.json)
        BUDGET_NAME=$(jq -r '.budget_name' deployment-state.json)
        FILTERED_BUDGET_NAME=$(jq -r '.filtered_budget_name' deployment-state.json)
        ACTION_GROUP_NAME=$(jq -r '.action_group_name' deployment-state.json)
        SUBSCRIPTION_ID=$(jq -r '.subscription_id' deployment-state.json)
        EMAIL_ADDRESS=$(jq -r '.email_address' deployment-state.json)
        BUDGET_AMOUNT=$(jq -r '.budget_amount' deployment-state.json)
        
        log_success "Loaded deployment state from deployment-state.json"
        log_info "Resources to be deleted:"
        log_info "  - Resource Group: $RESOURCE_GROUP"
        log_info "  - Main Budget: $BUDGET_NAME"
        log_info "  - Filtered Budget: $FILTERED_BUDGET_NAME"
        log_info "  - Action Group: $ACTION_GROUP_NAME"
        
        export RESOURCE_GROUP BUDGET_NAME FILTERED_BUDGET_NAME ACTION_GROUP_NAME SUBSCRIPTION_ID EMAIL_ADDRESS BUDGET_AMOUNT
    else
        log_warning "deployment-state.json not found. Using manual resource detection..."
        return 1
    fi
}

# Function to manually detect resources when state file is missing
detect_resources_manually() {
    log_info "Detecting resources manually..."
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export SUBSCRIPTION_ID
    
    # Prompt for resource group if not provided
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        echo -n "Enter the resource group name to delete: "
        read -r RESOURCE_GROUP
        
        if [[ -z "$RESOURCE_GROUP" ]]; then
            log_error "Resource group name is required"
            exit 1
        fi
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group '$RESOURCE_GROUP' not found"
        exit 1
    fi
    
    log_info "Will attempt to clean up resources in: $RESOURCE_GROUP"
    export RESOURCE_GROUP
}

# Function to confirm destruction
confirm_destruction() {
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo
    echo "This will permanently delete the following Azure resources:"
    echo
    if [[ -n "${BUDGET_NAME:-}" ]]; then
        echo "💰 Budgets:"
        echo "   • $BUDGET_NAME"
        [[ -n "${FILTERED_BUDGET_NAME:-}" ]] && echo "   • $FILTERED_BUDGET_NAME"
    fi
    
    if [[ -n "${ACTION_GROUP_NAME:-}" ]]; then
        echo "📧 Action Groups:"
        echo "   • $ACTION_GROUP_NAME"
    fi
    
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        echo "📁 Resource Groups:"
        echo "   • $RESOURCE_GROUP (and all contained resources)"
    fi
    
    echo
    echo "💾 Local Files:"
    echo "   • deployment-state.json"
    echo "   • budget-alerts.json"
    echo
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log_warning "Force delete enabled, skipping confirmation"
        return 0
    fi
    
    echo -n "Are you sure you want to proceed? (yes/no): "
    read -r confirmation
    
    case "$confirmation" in
        yes|YES|y|Y)
            log_info "Proceeding with resource deletion..."
            ;;
        *)
            log_info "Operation cancelled by user"
            exit 0
            ;;
    esac
}

# Function to delete budgets
delete_budgets() {
    log_info "Deleting cost management budgets..."
    
    local deleted_count=0
    
    # Delete main budget if specified
    if [[ -n "${BUDGET_NAME:-}" ]]; then
        log_info "Deleting main budget: $BUDGET_NAME"
        
        if az rest \
            --method DELETE \
            --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Consumption/budgets/$BUDGET_NAME?api-version=2023-11-01" \
            --output none 2>/dev/null; then
            log_success "Main budget deleted: $BUDGET_NAME"
            ((deleted_count++))
        else
            log_warning "Failed to delete main budget or budget doesn't exist: $BUDGET_NAME"
        fi
    fi
    
    # Delete filtered budget if specified
    if [[ -n "${FILTERED_BUDGET_NAME:-}" ]]; then
        log_info "Deleting filtered budget: $FILTERED_BUDGET_NAME"
        
        if az rest \
            --method DELETE \
            --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Consumption/budgets/$FILTERED_BUDGET_NAME?api-version=2023-11-01" \
            --output none 2>/dev/null; then
            log_success "Filtered budget deleted: $FILTERED_BUDGET_NAME"
            ((deleted_count++))
        else
            log_warning "Failed to delete filtered budget or budget doesn't exist: $FILTERED_BUDGET_NAME"
        fi
    fi
    
    # If no specific budgets, try to find and delete any budgets containing our pattern
    if [[ $deleted_count -eq 0 ]]; then
        log_info "Searching for budgets to delete..."
        
        local budget_list
        budget_list=$(az rest \
            --method GET \
            --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Consumption/budgets?api-version=2023-11-01" \
            --query "value[?contains(name, 'cost-budget') || contains(name, 'rg-budget')].name" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$budget_list" ]]; then
            while IFS= read -r budget_name; do
                if [[ -n "$budget_name" ]]; then
                    log_info "Deleting found budget: $budget_name"
                    
                    if az rest \
                        --method DELETE \
                        --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Consumption/budgets/$budget_name?api-version=2023-11-01" \
                        --output none 2>/dev/null; then
                        log_success "Budget deleted: $budget_name"
                        ((deleted_count++))
                    else
                        log_warning "Failed to delete budget: $budget_name"
                    fi
                fi
            done <<< "$budget_list"
        fi
    fi
    
    if [[ $deleted_count -gt 0 ]]; then
        log_success "Deleted $deleted_count budget(s)"
    else
        log_warning "No budgets were deleted"
    fi
}

# Function to delete action group
delete_action_group() {
    if [[ -z "${ACTION_GROUP_NAME:-}" ]] || [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_warning "Action group name or resource group not specified, skipping action group deletion"
        return 0
    fi
    
    log_info "Deleting action group: $ACTION_GROUP_NAME"
    
    if az monitor action-group show --name "$ACTION_GROUP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        if az monitor action-group delete \
            --name "$ACTION_GROUP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --output none; then
            log_success "Action group deleted: $ACTION_GROUP_NAME"
        else
            log_error "Failed to delete action group: $ACTION_GROUP_NAME"
            return 1
        fi
    else
        log_warning "Action group not found or already deleted: $ACTION_GROUP_NAME"
    fi
}

# Function to delete resource group
delete_resource_group() {
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_warning "Resource group not specified, skipping resource group deletion"
        return 0
    fi
    
    log_info "Deleting resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        # List resources in the group before deletion for confirmation
        log_info "Resources in $RESOURCE_GROUP:"
        az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,Type:type}" --output table
        
        if az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait \
            --output none; then
            log_success "Resource group deletion initiated: $RESOURCE_GROUP"
            log_info "Note: Deletion may take several minutes to complete"
        else
            log_error "Failed to delete resource group: $RESOURCE_GROUP"
            return 1
        fi
    else
        log_warning "Resource group not found or already deleted: $RESOURCE_GROUP"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_deleted=0
    
    # Remove deployment state file
    if [[ -f "deployment-state.json" ]]; then
        rm -f deployment-state.json
        log_success "Removed deployment-state.json"
        ((files_deleted++))
    fi
    
    # Remove budget alerts configuration
    if [[ -f "budget-alerts.json" ]]; then
        rm -f budget-alerts.json
        log_success "Removed budget-alerts.json"
        ((files_deleted++))
    fi
    
    # Clear environment variables
    unset RESOURCE_GROUP BUDGET_NAME ACTION_GROUP_NAME EMAIL_ADDRESS BUDGET_AMOUNT FILTERED_BUDGET_NAME SUBSCRIPTION_ID 2>/dev/null || true
    
    if [[ $files_deleted -gt 0 ]]; then
        log_success "Local cleanup completed ($files_deleted files removed)"
    else
        log_info "No local files to clean up"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check if budgets still exist
    if [[ -n "${BUDGET_NAME:-}" ]]; then
        if az rest \
            --method GET \
            --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Consumption/budgets/$BUDGET_NAME?api-version=2023-11-01" \
            &> /dev/null; then
            log_warning "Main budget still exists: $BUDGET_NAME"
            ((cleanup_issues++))
        fi
    fi
    
    if [[ -n "${FILTERED_BUDGET_NAME:-}" ]]; then
        if az rest \
            --method GET \
            --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Consumption/budgets/$FILTERED_BUDGET_NAME?api-version=2023-11-01" \
            &> /dev/null; then
            log_warning "Filtered budget still exists: $FILTERED_BUDGET_NAME"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if resource group still exists (it may still be deleting)
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            local rg_state
            rg_state=$(az group show --name "$RESOURCE_GROUP" --query "properties.provisioningState" --output tsv)
            if [[ "$rg_state" == "Deleting" ]]; then
                log_info "Resource group is still being deleted: $RESOURCE_GROUP"
            else
                log_warning "Resource group still exists: $RESOURCE_GROUP"
                ((cleanup_issues++))
            fi
        fi
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "Cleanup verification completed successfully"
    else
        log_warning "Cleanup verification found $cleanup_issues potential issues"
        log_info "Some resources may still be in the process of being deleted"
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    echo
    log_success "=== CLEANUP COMPLETED ==="
    echo
    echo "🗑️  Resources Deleted:"
    [[ -n "${BUDGET_NAME:-}" ]] && echo "   • Main Budget: $BUDGET_NAME"
    [[ -n "${FILTERED_BUDGET_NAME:-}" ]] && echo "   • Filtered Budget: $FILTERED_BUDGET_NAME"
    [[ -n "${ACTION_GROUP_NAME:-}" ]] && echo "   • Action Group: $ACTION_GROUP_NAME"
    [[ -n "${RESOURCE_GROUP:-}" ]] && echo "   • Resource Group: $RESOURCE_GROUP (deletion in progress)"
    echo
    echo "📁 Local Files Removed:"
    echo "   • deployment-state.json"
    echo "   • budget-alerts.json"
    echo
    echo "💡 Notes:"
    echo "   • Resource group deletion may take several minutes to complete"
    echo "   • Budget deletion is immediate and irreversible"
    echo "   • Email notifications will stop immediately"
    echo
    echo "🌐 Verify in Azure Portal:"
    echo "   • Cost Management: https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/overview"
    echo "   • Budgets: https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/budgets"
    echo
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    log_error "An error occurred during cleanup. Some resources may not have been deleted."
    log_info "You may need to manually delete remaining resources:"
    echo
    [[ -n "${RESOURCE_GROUP:-}" ]] && echo "   • Resource Group: $RESOURCE_GROUP"
    [[ -n "${BUDGET_NAME:-}" ]] && echo "   • Main Budget: $BUDGET_NAME"
    [[ -n "${FILTERED_BUDGET_NAME:-}" ]] && echo "   • Filtered Budget: $FILTERED_BUDGET_NAME"
    echo
    echo "Check the Azure portal for any remaining resources."
}

# Main cleanup function
main() {
    echo "🧹 Starting Azure Cost Budget Tracking Cleanup"
    echo "=============================================="
    
    # Set up error handling
    trap handle_cleanup_error ERR
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment state or detect resources manually
    if ! load_deployment_state; then
        detect_resources_manually
    fi
    
    # Confirm destruction
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_budgets
    delete_action_group  
    delete_resource_group
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Show summary
    show_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

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
        --budget-name)
            BUDGET_NAME="$2"
            shift 2
            ;;
        --action-group)
            ACTION_GROUP_NAME="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --resource-group NAME  Resource group to delete (if state file missing)"
            echo "  --budget-name NAME     Specific budget name to delete"
            echo "  --action-group NAME    Specific action group name to delete"
            echo "  --force                Skip confirmation prompts"
            echo "  --help                 Show this help message"
            echo
            echo "Environment Variables:"
            echo "  RESOURCE_GROUP         Resource group name"
            echo "  BUDGET_NAME           Budget name"
            echo "  ACTION_GROUP_NAME     Action group name"
            echo "  FORCE_DELETE          Set to 'true' to skip confirmations"
            echo
            echo "Notes:"
            echo "  • If deployment-state.json exists, it will be used for resource names"
            echo "  • Otherwise, you'll be prompted for the resource group name"
            echo "  • Use --force to skip confirmation prompts (use with caution)"
            echo
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check for jq if deployment state file exists
if [[ -f "deployment-state.json" ]] && ! command -v jq &> /dev/null; then
    log_error "jq is required to parse deployment-state.json but is not installed"
    log_info "Either install jq or delete deployment-state.json and provide resource names manually"
    exit 1
fi

# Run main function
main "$@"