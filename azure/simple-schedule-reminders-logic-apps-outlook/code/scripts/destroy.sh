#!/bin/bash

# Destroy script for Simple Schedule Reminders with Logic Apps and Outlook
# This script removes all Azure resources created by the deployment script

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${2:-}$(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    log "$1" "$BLUE"
}

log_success() {
    log "$1" "$GREEN"
}

log_warning() {
    log "$1" "$YELLOW"
}

log_error() {
    log "$1" "$RED"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if deployment state file exists
    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
        log_warning "Deployment state file not found: $DEPLOYMENT_STATE_FILE"
        log_info "Will attempt cleanup based on user input..."
        return 1
    fi
    
    log_success "Prerequisites check completed"
    return 0
}

# Function to load deployment state
load_deployment_state() {
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        source "$DEPLOYMENT_STATE_FILE"
        log_info "Loaded deployment state:"
        log_info "  Resource Group: ${RESOURCE_GROUP:-'Not set'}"
        log_info "  Logic App Name: ${LOGIC_APP_NAME:-'Not set'}"
        log_info "  Location: ${LOCATION:-'Not set'}"
        return 0
    else
        log_warning "No deployment state file found"
        return 1
    fi
}

# Function to get user input for manual cleanup
get_manual_cleanup_input() {
    log_info "Manual cleanup mode - please provide resource information"
    
    echo ""
    read -p "Enter the Resource Group name to delete: " -r RESOURCE_GROUP
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log_error "Resource Group name is required for cleanup"
        exit 1
    fi
    
    # Verify resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource Group '$RESOURCE_GROUP' not found"
        exit 1
    fi
    
    log_info "Will clean up Resource Group: $RESOURCE_GROUP"
}

# Function to display resources that will be deleted
display_resources_to_delete() {
    log_info "Scanning resources in Resource Group: $RESOURCE_GROUP"
    
    # Get list of resources
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --output table 2>/dev/null || echo "No resources found")
    
    if [[ "$resources" == "No resources found" ]]; then
        log_warning "No resources found in Resource Group: $RESOURCE_GROUP"
        return
    fi
    
    echo ""
    echo "=== RESOURCES TO BE DELETED ==="
    echo "$resources"
    echo ""
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    log_warning "WARNING: This action will permanently delete all resources!"
    log_warning "Resource Group: $RESOURCE_GROUP"
    echo ""
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
    if [[ $REPLY != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Final confirmation - type 'DELETE' to proceed: " -r
    if [[ $REPLY != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "User confirmed deletion"
}

# Function to disable Logic App before deletion
disable_logic_app() {
    if [[ -n "${LOGIC_APP_NAME:-}" ]]; then
        log_info "Disabling Logic App: $LOGIC_APP_NAME"
        
        # Check if Logic App exists and is enabled
        local logic_app_state
        logic_app_state=$(az logic workflow show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$LOGIC_APP_NAME" \
            --query "properties.state" \
            --output tsv 2>/dev/null || echo "NotFound")
        
        if [[ "$logic_app_state" == "Enabled" ]]; then
            az logic workflow update \
                --resource-group "$RESOURCE_GROUP" \
                --name "$LOGIC_APP_NAME" \
                --state Disabled \
                >> "$LOG_FILE" 2>&1
            
            log_success "Logic App disabled successfully"
        elif [[ "$logic_app_state" == "NotFound" ]]; then
            log_warning "Logic App not found: $LOGIC_APP_NAME"
        else
            log_info "Logic App already in state: $logic_app_state"
        fi
    else
        log_info "No specific Logic App to disable (checking all Logic Apps in resource group)"
        
        # Find and disable any Logic Apps in the resource group
        local logic_apps
        logic_apps=$(az logic workflow list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].name" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$logic_apps" ]]; then
            while IFS= read -r app_name; do
                log_info "Disabling Logic App: $app_name"
                az logic workflow update \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$app_name" \
                    --state Disabled \
                    >> "$LOG_FILE" 2>&1
            done <<< "$logic_apps"
            
            log_success "All Logic Apps disabled"
        else
            log_info "No Logic Apps found in resource group"
        fi
    fi
}

# Function to delete API connections
delete_api_connections() {
    log_info "Checking for API connections to delete..."
    
    local connections
    connections=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type Microsoft.Web/connections \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$connections" ]]; then
        log_info "Found API connections to delete"
        while IFS= read -r connection_name; do
            log_info "Deleting API connection: $connection_name"
            az resource delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$connection_name" \
                --resource-type Microsoft.Web/connections \
                >> "$LOG_FILE" 2>&1
            log_success "Deleted API connection: $connection_name"
        done <<< "$connections"
    else
        log_info "No API connections found"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log_info "Deleting Resource Group: $RESOURCE_GROUP"
    
    # Start the deletion process
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait \
        >> "$LOG_FILE" 2>&1
    
    log_success "Resource group deletion initiated"
    log_info "Note: Deletion may take several minutes to complete"
    
    # Optional: Wait for deletion to complete
    read -p "Would you like to wait for deletion to complete? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Waiting for resource group deletion to complete..."
        
        while az group show --name "$RESOURCE_GROUP" &> /dev/null; do
            log_info "Still deleting... (checking again in 30 seconds)"
            sleep 30
        done
        
        log_success "Resource group deleted successfully"
    else
        log_info "Deletion is running in the background"
        log_info "You can check status with: az group show --name $RESOURCE_GROUP"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove workflow definition files
    local files_to_remove=(
        "${SCRIPT_DIR}/workflow-definition.json"
        "${SCRIPT_DIR}/updated-workflow.json"
        "$DEPLOYMENT_STATE_FILE"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Removed: $(basename "$file")"
        fi
    done
    
    # Clean up environment variables (if sourced)
    unset RESOURCE_GROUP LOCATION LOGIC_APP_NAME RANDOM_SUFFIX \
          SUBSCRIPTION_ID LOGIC_APP_RESOURCE_ID CONNECTION_ID 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group still exists (deletion may be in progress)"
        log_info "Check deletion status with: az group show --name $RESOURCE_GROUP"
    else
        log_success "Resource group successfully deleted"
    fi
    
    # Check for remaining local files
    local remaining_files=()
    if [[ -f "${SCRIPT_DIR}/workflow-definition.json" ]]; then
        remaining_files+=("workflow-definition.json")
    fi
    if [[ -f "${SCRIPT_DIR}/updated-workflow.json" ]]; then
        remaining_files+=("updated-workflow.json")
    fi
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        remaining_files+=(".deployment_state")
    fi
    
    if [[ ${#remaining_files[@]} -eq 0 ]]; then
        log_success "All local files cleaned up"
    else
        log_warning "Some local files remain: ${remaining_files[*]}"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "Cleanup process completed!"
    echo ""
    echo "=== CLEANUP SUMMARY ==="
    echo "Resource Group: $RESOURCE_GROUP (deleted)"
    echo "Local files: Cleaned up"
    echo ""
    echo "What was removed:"
    echo "- Logic App workflow and triggers"
    echo "- Office 365 API connections"
    echo "- All associated Azure resources"
    echo "- Local workflow definition files"
    echo "- Deployment state files"
    echo ""
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        echo "Note: Resource group deletion may still be in progress."
        echo "Monitor with: az group show --name $RESOURCE_GROUP"
    else
        echo "✅ All resources successfully removed"
    fi
    echo ""
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Simple Schedule Reminders resources"
    log_info "Log file: $LOG_FILE"
    
    # Clear previous log
    > "$LOG_FILE"
    
    check_prerequisites
    
    # Try to load deployment state, fallback to manual input
    if ! load_deployment_state; then
        get_manual_cleanup_input
    fi
    
    display_resources_to_delete
    confirm_deletion
    
    # Perform cleanup steps
    disable_logic_app
    delete_api_connections
    delete_resource_group
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
    
    log_success "Cleanup script completed successfully"
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warning "Script interrupted by user"
    log_info "Partial cleanup may have occurred"
    log_info "Check Azure portal or run script again to complete cleanup"
    exit 130
}

# Set trap for interruption
trap cleanup_on_interrupt SIGINT SIGTERM

# Run main function
main "$@"