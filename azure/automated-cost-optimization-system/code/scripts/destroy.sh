#!/bin/bash

# Azure Cost Optimization Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" >&2
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_LOG="${SCRIPT_DIR}/cleanup_$(date +%Y%m%d_%H%M%S).log"
CONFIG_FILE="${SCRIPT_DIR}/deployment_config.env"

# Check if running in dry-run mode
DRY_RUN=false
FORCE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log "Running in DRY-RUN mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE=true
            log "Force mode enabled - will not prompt for confirmation"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--force]"
            echo "  --dry-run  Show what would be deleted without actually deleting"
            echo "  --force    Skip confirmation prompts"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to load configuration
load_configuration() {
    log "Loading deployment configuration..."
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        error "Configuration file not found: ${CONFIG_FILE}"
        error "Please run the deployment script first or create the configuration file manually."
        exit 1
    fi
    
    source "${CONFIG_FILE}"
    
    # Validate required variables
    if [[ -z "${SUBSCRIPTION_ID}" ]] || [[ -z "${RESOURCE_GROUP}" ]]; then
        error "Invalid configuration file. Missing required variables."
        exit 1
    fi
    
    # Display configuration
    log "Configuration loaded:"
    echo "  Subscription ID: ${SUBSCRIPTION_ID}"
    echo "  Resource Group: ${RESOURCE_GROUP}"
    echo "  Storage Account: ${STORAGE_ACCOUNT:-'Not configured'}"
    echo "  Logic App: ${LOGIC_APP_NAME:-'Not configured'}"
    echo "  Budget: ${BUDGET_NAME:-'Not configured'}"
    echo "  Location: ${LOCATION:-'Not configured'}"
    
    success "Configuration loaded successfully"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    warning "This will permanently delete all cost optimization resources!"
    echo "Resources to be deleted:"
    echo "  • Resource Group: ${RESOURCE_GROUP}"
    echo "  • All contained resources (Storage Account, Logic Apps, etc.)"
    echo "  • Service Principal: ${SP_APP_ID:-'Unknown'}"
    echo "  • Budget: ${BUDGET_NAME:-'Unknown'}"
    echo "  • Cost Export: ${EXPORT_NAME:-'Unknown'}"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " CONFIRM
    if [[ "$CONFIRM" != "DELETE" ]]; then
        log "Deletion cancelled by user."
        exit 0
    fi
    
    warning "Starting deletion process in 5 seconds... (Ctrl+C to cancel)"
    sleep 5
}

# Function to delete cost data export
delete_cost_export() {
    log "Deleting cost data export..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would delete cost export ${EXPORT_NAME:-'Unknown'}"
        return 0
    fi
    
    if [[ -n "${EXPORT_NAME}" ]]; then
        if az consumption export show --export-name "${EXPORT_NAME}" &> /dev/null; then
            az consumption export delete --export-name "${EXPORT_NAME}" --yes &> /dev/null
            if [[ $? -eq 0 ]]; then
                success "Cost data export deleted: ${EXPORT_NAME}"
            else
                warning "Failed to delete cost data export: ${EXPORT_NAME}"
            fi
        else
            warning "Cost data export not found: ${EXPORT_NAME}"
        fi
    else
        warning "Cost data export name not found in configuration"
    fi
}

# Function to delete budget
delete_budget() {
    log "Deleting budget..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would delete budget ${BUDGET_NAME:-'Unknown'}"
        return 0
    fi
    
    if [[ -n "${BUDGET_NAME}" ]]; then
        if az consumption budget show --budget-name "${BUDGET_NAME}" &> /dev/null; then
            az consumption budget delete --budget-name "${BUDGET_NAME}" --yes &> /dev/null
            if [[ $? -eq 0 ]]; then
                success "Budget deleted: ${BUDGET_NAME}"
            else
                warning "Failed to delete budget: ${BUDGET_NAME}"
            fi
        else
            warning "Budget not found: ${BUDGET_NAME}"
        fi
    else
        warning "Budget name not found in configuration"
    fi
}

# Function to delete service principal
delete_service_principal() {
    log "Deleting service principal..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would delete service principal ${SP_APP_ID:-'Unknown'}"
        return 0
    fi
    
    if [[ -n "${SP_APP_ID}" ]]; then
        if az ad sp show --id "${SP_APP_ID}" &> /dev/null; then
            az ad sp delete --id "${SP_APP_ID}" &> /dev/null
            if [[ $? -eq 0 ]]; then
                success "Service principal deleted: ${SP_APP_ID}"
            else
                warning "Failed to delete service principal: ${SP_APP_ID}"
            fi
        else
            warning "Service principal not found: ${SP_APP_ID}"
        fi
    else
        warning "Service principal ID not found in configuration"
    fi
}

# Function to delete alerts
delete_alerts() {
    log "Deleting cost anomaly alerts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would delete alerts in resource group ${RESOURCE_GROUP}"
        return 0
    fi
    
    # Find and delete all alerts in the resource group
    local alerts=$(az monitor metrics alert list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null)
    
    if [[ -n "$alerts" ]]; then
        while IFS= read -r alert_name; do
            if [[ -n "$alert_name" ]]; then
                az monitor metrics alert delete --name "$alert_name" --resource-group "${RESOURCE_GROUP}" &> /dev/null
                if [[ $? -eq 0 ]]; then
                    success "Alert deleted: $alert_name"
                else
                    warning "Failed to delete alert: $alert_name"
                fi
            fi
        done <<< "$alerts"
    else
        warning "No alerts found in resource group"
    fi
}

# Function to delete action groups
delete_action_groups() {
    log "Deleting action groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would delete action groups in resource group ${RESOURCE_GROUP}"
        return 0
    fi
    
    # Find and delete all action groups in the resource group
    local action_groups=$(az monitor action-group list --resource-group "${RESOURCE_GROUP}" --query "[].name" --output tsv 2>/dev/null)
    
    if [[ -n "$action_groups" ]]; then
        while IFS= read -r ag_name; do
            if [[ -n "$ag_name" ]]; then
                az monitor action-group delete --name "$ag_name" --resource-group "${RESOURCE_GROUP}" &> /dev/null
                if [[ $? -eq 0 ]]; then
                    success "Action group deleted: $ag_name"
                else
                    warning "Failed to delete action group: $ag_name"
                fi
            fi
        done <<< "$action_groups"
    else
        warning "No action groups found in resource group"
    fi
}

# Function to empty storage account
empty_storage_account() {
    log "Emptying storage account contents..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would empty storage account ${STORAGE_ACCOUNT:-'Unknown'}"
        return 0
    fi
    
    if [[ -n "${STORAGE_ACCOUNT}" ]]; then
        if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            # Get storage account connection string
            local connection_string=$(az storage account show-connection-string \
                --name "${STORAGE_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --query connectionString \
                --output tsv 2>/dev/null)
            
            if [[ -n "$connection_string" ]]; then
                # Delete all blobs in all containers
                local containers=$(az storage container list --connection-string "$connection_string" --query "[].name" --output tsv 2>/dev/null)
                
                if [[ -n "$containers" ]]; then
                    while IFS= read -r container_name; do
                        if [[ -n "$container_name" ]]; then
                            az storage blob delete-batch --source "$container_name" --connection-string "$connection_string" &> /dev/null
                            success "Emptied container: $container_name"
                        fi
                    done <<< "$containers"
                else
                    log "No containers found in storage account"
                fi
            else
                warning "Could not retrieve storage account connection string"
            fi
        else
            warning "Storage account not found: ${STORAGE_ACCOUNT}"
        fi
    else
        warning "Storage account name not found in configuration"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group and all contained resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would delete resource group ${RESOURCE_GROUP}"
        return 0
    fi
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        # Delete resource group (this will delete all contained resources)
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait &> /dev/null
        if [[ $? -eq 0 ]]; then
            success "Resource group deletion initiated: ${RESOURCE_GROUP}"
            log "Deletion is running in the background. Check Azure portal for completion status."
        else
            error "Failed to delete resource group: ${RESOURCE_GROUP}"
            exit 1
        fi
    else
        warning "Resource group not found: ${RESOURCE_GROUP}"
    fi
}

# Function to verify deletion
verify_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would verify deletion"
        return 0
    fi
    
    log "Verifying deletion..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Resource group still exists (deletion may still be in progress)"
    else
        success "Resource group deletion verified"
    fi
    
    # Check if service principal still exists
    if [[ -n "${SP_APP_ID}" ]]; then
        if az ad sp show --id "${SP_APP_ID}" &> /dev/null; then
            warning "Service principal still exists: ${SP_APP_ID}"
        else
            success "Service principal deletion verified"
        fi
    fi
    
    # Check if budget still exists
    if [[ -n "${BUDGET_NAME}" ]]; then
        if az consumption budget show --budget-name "${BUDGET_NAME}" &> /dev/null; then
            warning "Budget still exists: ${BUDGET_NAME}"
        else
            success "Budget deletion verified"
        fi
    fi
}

# Function to cleanup configuration files
cleanup_config_files() {
    log "Cleaning up configuration files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN: Would cleanup configuration files"
        return 0
    fi
    
    # Archive configuration file instead of deleting
    if [[ -f "${CONFIG_FILE}" ]]; then
        local archive_file="${CONFIG_FILE}.$(date +%Y%m%d_%H%M%S).backup"
        mv "${CONFIG_FILE}" "${archive_file}"
        success "Configuration file archived: ${archive_file}"
    fi
    
    # Remove cleanup logs older than 7 days
    find "${SCRIPT_DIR}" -name "cleanup_*.log" -mtime +7 -delete 2>/dev/null || true
    find "${SCRIPT_DIR}" -name "deployment_*.log" -mtime +7 -delete 2>/dev/null || true
    
    success "Configuration cleanup completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "Deleted Resources:"
    echo "  • Resource Group: ${RESOURCE_GROUP}"
    echo "  • Storage Account: ${STORAGE_ACCOUNT:-'Not configured'}"
    echo "  • Logic Apps: ${LOGIC_APP_NAME:-'Not configured'}"
    echo "  • Log Analytics: ${LOG_ANALYTICS_WORKSPACE:-'Not configured'}"
    echo "  • Budget: ${BUDGET_NAME:-'Not configured'}"
    echo "  • Service Principal: ${SP_APP_ID:-'Not configured'}"
    echo "  • Cost Export: ${EXPORT_NAME:-'Not configured'}"
    echo ""
    echo "Notes:"
    echo "• Resource group deletion may take several minutes to complete"
    echo "• Check Azure portal for final deletion confirmation"
    echo "• Configuration files have been archived for reference"
    echo "• All cost optimization resources have been removed"
    echo ""
    echo "Cleanup log saved to: ${CLEANUP_LOG}"
    echo ""
    success "Cleanup completed successfully!"
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    error "An error occurred during cleanup. Some resources may still exist."
    error "Please check the Azure portal and manually delete any remaining resources."
    error "Resource group: ${RESOURCE_GROUP}"
    error "Subscription: ${SUBSCRIPTION_ID}"
    exit 1
}

# Trap to handle script interruption
trap handle_cleanup_error ERR INT TERM

# Main cleanup function
main() {
    log "Starting Azure Cost Optimization Cleanup"
    log "========================================"
    
    # Start cleanup log
    exec 1> >(tee -a "${CLEANUP_LOG}")
    exec 2> >(tee -a "${CLEANUP_LOG}" >&2)
    
    check_prerequisites
    load_configuration
    confirm_deletion
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY-RUN completed successfully!"
        exit 0
    fi
    
    # Delete resources in reverse order of creation
    delete_cost_export
    delete_alerts
    delete_action_groups
    delete_budget
    delete_service_principal
    empty_storage_account
    delete_resource_group
    
    # Wait a moment for Azure to process the deletion
    sleep 5
    
    verify_deletion
    cleanup_config_files
    display_cleanup_summary
    
    log "Cleanup log saved to: ${CLEANUP_LOG}"
}

# Run main function
main "$@"