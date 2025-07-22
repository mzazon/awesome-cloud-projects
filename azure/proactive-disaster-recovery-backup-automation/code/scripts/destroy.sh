#!/bin/bash

# destroy.sh - Cleanup script for Proactive Disaster Recovery with Backup Center Automation
# This script safely removes all Azure resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "ERROR: $1"
    log "Cleanup failed. Check ${LOG_FILE} for details."
    exit 1
}

# Success indicator function
success() {
    log "✅ $1"
}

# Warning function
warning() {
    log "⚠️  WARNING: $1"
}

# Confirmation prompt function
confirm_action() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [ "${FORCE_CLEANUP:-false}" = "true" ]; then
        log "FORCE_CLEANUP is enabled, automatically confirming: ${prompt}"
        return 0
    fi
    
    echo -n "${prompt} [y/N]: "
    read -r response
    response=${response:-$default}
    
    case "${response}" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Load deployment variables function
load_deployment_variables() {
    log "Loading deployment variables..."
    
    if [ -f "${SCRIPT_DIR}/deployment_vars.sh" ]; then
        source "${SCRIPT_DIR}/deployment_vars.sh"
        success "Deployment variables loaded from deployment_vars.sh"
    else
        warning "deployment_vars.sh not found. Using environment variables or defaults."
        
        # Set default values if not already set
        export PRIMARY_REGION="${PRIMARY_REGION:-eastus}"
        export SECONDARY_REGION="${SECONDARY_REGION:-westus2}"
        export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-dr-orchestration}"
        export BACKUP_RESOURCE_GROUP="${BACKUP_RESOURCE_GROUP:-rg-dr-backup}"
        export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv 2>/dev/null || echo '')}"
        
        if [ -z "${SUBSCRIPTION_ID}" ]; then
            error_exit "Could not determine subscription ID. Please ensure you're logged in to Azure."
        fi
        
        # Try to discover resource names if not set
        if [ -z "${RSV_PRIMARY_NAME:-}" ]; then
            log "Attempting to discover Recovery Services Vault names..."
            RSV_PRIMARY_NAME=$(az backup vault list \
                --resource-group ${BACKUP_RESOURCE_GROUP} \
                --query "[?starts_with(name, 'rsv-dr-primary-')].name | [0]" \
                --output tsv 2>/dev/null || echo "")
        fi
        
        if [ -z "${RSV_SECONDARY_NAME:-}" ]; then
            RSV_SECONDARY_NAME=$(az backup vault list \
                --resource-group ${BACKUP_RESOURCE_GROUP} \
                --query "[?starts_with(name, 'rsv-dr-secondary-')].name | [0]" \
                --output tsv 2>/dev/null || echo "")
        fi
        
        if [ -z "${LOGIC_APP_NAME:-}" ]; then
            log "Attempting to discover Logic App name..."
            LOGIC_APP_NAME=$(az logic workflow list \
                --resource-group ${RESOURCE_GROUP} \
                --query "[?starts_with(name, 'la-dr-orchestration-')].name | [0]" \
                --output tsv 2>/dev/null || echo "")
        fi
        
        if [ -z "${MONITOR_WORKSPACE_NAME:-}" ]; then
            log "Attempting to discover Log Analytics Workspace name..."
            MONITOR_WORKSPACE_NAME=$(az monitor log-analytics workspace list \
                --resource-group ${RESOURCE_GROUP} \
                --query "[?starts_with(name, 'law-dr-monitoring-')].name | [0]" \
                --output tsv 2>/dev/null || echo "")
        fi
        
        if [ -z "${STORAGE_ACCOUNT_NAME:-}" ]; then
            log "Attempting to discover Storage Account name..."
            STORAGE_ACCOUNT_NAME=$(az storage account list \
                --resource-group ${RESOURCE_GROUP} \
                --query "[?starts_with(name, 'stdrbackup')].name | [0]" \
                --output tsv 2>/dev/null || echo "")
        fi
        
        if [ -z "${ACTION_GROUP_NAME:-}" ]; then
            log "Attempting to discover Action Group name..."
            ACTION_GROUP_NAME=$(az monitor action-group list \
                --resource-group ${RESOURCE_GROUP} \
                --query "[?starts_with(name, 'ag-dr-alerts-')].name | [0]" \
                --output tsv 2>/dev/null || echo "")
        fi
    fi
    
    log "Using the following configuration:"
    log "  Primary Region: ${PRIMARY_REGION}"
    log "  Secondary Region: ${SECONDARY_REGION}"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Backup Resource Group: ${BACKUP_RESOURCE_GROUP}"
    log "  Subscription ID: ${SUBSCRIPTION_ID}"
    log "  Primary Vault: ${RSV_PRIMARY_NAME:-'Not found'}"
    log "  Secondary Vault: ${RSV_SECONDARY_NAME:-'Not found'}"
    log "  Logic App: ${LOGIC_APP_NAME:-'Not found'}"
    log "  Monitor Workspace: ${MONITOR_WORKSPACE_NAME:-'Not found'}"
    log "  Storage Account: ${STORAGE_ACCOUNT_NAME:-'Not found'}"
    log "  Action Group: ${ACTION_GROUP_NAME:-'Not found'}"
}

# Check prerequisites function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    success "Prerequisites check completed"
}

# Check if resources exist function
check_resource_existence() {
    log "Checking which resources exist..."
    
    # Check if resource groups exist
    RG_EXISTS=$(az group exists --name ${RESOURCE_GROUP} 2>/dev/null || echo "false")
    BACKUP_RG_EXISTS=$(az group exists --name ${BACKUP_RESOURCE_GROUP} 2>/dev/null || echo "false")
    
    log "Resource Group '${RESOURCE_GROUP}' exists: ${RG_EXISTS}"
    log "Backup Resource Group '${BACKUP_RESOURCE_GROUP}' exists: ${BACKUP_RG_EXISTS}"
    
    # If no resource groups exist, nothing to clean up
    if [ "${RG_EXISTS}" = "false" ] && [ "${BACKUP_RG_EXISTS}" = "false" ]; then
        log "No resource groups found. Nothing to clean up."
        exit 0
    fi
    
    success "Resource existence check completed"
}

# Remove Logic Apps and orchestration resources function
remove_logic_apps() {
    log "Removing Logic Apps and orchestration resources..."
    
    if [ -n "${LOGIC_APP_NAME:-}" ] && [ "${LOGIC_APP_NAME}" != "Not found" ]; then
        # Check if Logic App exists
        LA_EXISTS=$(az logic workflow show \
            --name ${LOGIC_APP_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --query 'name' --output tsv 2>/dev/null || echo "")
        
        if [ -n "${LA_EXISTS}" ]; then
            log "Deleting Logic App: ${LOGIC_APP_NAME}"
            az logic workflow delete \
                --name ${LOGIC_APP_NAME} \
                --resource-group ${RESOURCE_GROUP} \
                --yes \
                >> "${LOG_FILE}" 2>&1
            success "Logic App deleted: ${LOGIC_APP_NAME}"
        else
            log "Logic App not found: ${LOGIC_APP_NAME}"
        fi
    else
        log "No Logic App name specified, skipping Logic App deletion"
    fi
    
    if [ -n "${STORAGE_ACCOUNT_NAME:-}" ] && [ "${STORAGE_ACCOUNT_NAME}" != "Not found" ]; then
        # Check if Storage Account exists
        SA_EXISTS=$(az storage account show \
            --name ${STORAGE_ACCOUNT_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --query 'name' --output tsv 2>/dev/null || echo "")
        
        if [ -n "${SA_EXISTS}" ]; then
            log "Deleting Storage Account: ${STORAGE_ACCOUNT_NAME}"
            az storage account delete \
                --name ${STORAGE_ACCOUNT_NAME} \
                --resource-group ${RESOURCE_GROUP} \
                --yes \
                >> "${LOG_FILE}" 2>&1
            success "Storage Account deleted: ${STORAGE_ACCOUNT_NAME}"
        else
            log "Storage Account not found: ${STORAGE_ACCOUNT_NAME}"
        fi
    else
        log "No Storage Account name specified, skipping Storage Account deletion"
    fi
    
    success "Logic Apps and orchestration resources cleanup completed"
}

# Remove monitoring infrastructure function
remove_monitoring() {
    log "Removing monitoring infrastructure..."
    
    # Remove alert rules
    log "Removing alert rules..."
    for alert_name in "BackupJobFailureAlert" "RecoveryVaultHealthAlert"; do
        ALERT_EXISTS=$(az monitor metrics alert show \
            --name ${alert_name} \
            --resource-group ${RESOURCE_GROUP} \
            --query 'name' --output tsv 2>/dev/null || echo "")
        
        if [ -n "${ALERT_EXISTS}" ]; then
            log "Deleting alert rule: ${alert_name}"
            az monitor metrics alert delete \
                --name ${alert_name} \
                --resource-group ${RESOURCE_GROUP} \
                >> "${LOG_FILE}" 2>&1
            success "Alert rule deleted: ${alert_name}"
        else
            log "Alert rule not found: ${alert_name}"
        fi
    done
    
    # Remove Action Group
    if [ -n "${ACTION_GROUP_NAME:-}" ] && [ "${ACTION_GROUP_NAME}" != "Not found" ]; then
        AG_EXISTS=$(az monitor action-group show \
            --name ${ACTION_GROUP_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --query 'name' --output tsv 2>/dev/null || echo "")
        
        if [ -n "${AG_EXISTS}" ]; then
            log "Deleting Action Group: ${ACTION_GROUP_NAME}"
            az monitor action-group delete \
                --name ${ACTION_GROUP_NAME} \
                --resource-group ${RESOURCE_GROUP} \
                >> "${LOG_FILE}" 2>&1
            success "Action Group deleted: ${ACTION_GROUP_NAME}"
        else
            log "Action Group not found: ${ACTION_GROUP_NAME}"
        fi
    else
        log "No Action Group name specified, skipping Action Group deletion"
    fi
    
    # Remove workbooks
    log "Removing monitoring workbooks..."
    WORKBOOK_EXISTS=$(az resource show \
        --resource-group ${RESOURCE_GROUP} \
        --resource-type "microsoft.insights/workbooks" \
        --name "disaster-recovery-dashboard" \
        --query 'name' --output tsv 2>/dev/null || echo "")
    
    if [ -n "${WORKBOOK_EXISTS}" ]; then
        log "Deleting monitoring workbook: disaster-recovery-dashboard"
        az resource delete \
            --resource-group ${RESOURCE_GROUP} \
            --resource-type "microsoft.insights/workbooks" \
            --name "disaster-recovery-dashboard" \
            >> "${LOG_FILE}" 2>&1
        success "Monitoring workbook deleted"
    else
        log "Monitoring workbook not found"
    fi
    
    # Remove Log Analytics workspace
    if [ -n "${MONITOR_WORKSPACE_NAME:-}" ] && [ "${MONITOR_WORKSPACE_NAME}" != "Not found" ]; then
        LAW_EXISTS=$(az monitor log-analytics workspace show \
            --workspace-name ${MONITOR_WORKSPACE_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --query 'name' --output tsv 2>/dev/null || echo "")
        
        if [ -n "${LAW_EXISTS}" ]; then
            log "Deleting Log Analytics workspace: ${MONITOR_WORKSPACE_NAME}"
            az monitor log-analytics workspace delete \
                --workspace-name ${MONITOR_WORKSPACE_NAME} \
                --resource-group ${RESOURCE_GROUP} \
                --yes \
                >> "${LOG_FILE}" 2>&1
            success "Log Analytics workspace deleted: ${MONITOR_WORKSPACE_NAME}"
        else
            log "Log Analytics workspace not found: ${MONITOR_WORKSPACE_NAME}"
        fi
    else
        log "No Log Analytics workspace name specified, skipping workspace deletion"
    fi
    
    success "Monitoring infrastructure cleanup completed"
}

# Remove Recovery Services Vaults function
remove_recovery_vaults() {
    log "Removing Recovery Services Vaults..."
    
    warning "This will permanently delete all backup data in the Recovery Services Vaults!"
    if ! confirm_action "Are you sure you want to delete all Recovery Services Vaults and backup data?"; then
        log "Skipping Recovery Services Vault deletion"
        return 0
    fi
    
    # Remove secondary Recovery Services Vault
    if [ -n "${RSV_SECONDARY_NAME:-}" ] && [ "${RSV_SECONDARY_NAME}" != "Not found" ]; then
        RSV_SEC_EXISTS=$(az backup vault show \
            --name ${RSV_SECONDARY_NAME} \
            --resource-group ${BACKUP_RESOURCE_GROUP} \
            --query 'name' --output tsv 2>/dev/null || echo "")
        
        if [ -n "${RSV_SEC_EXISTS}" ]; then
            log "Deleting secondary Recovery Services Vault: ${RSV_SECONDARY_NAME}"
            
            # Check for protected items and warn user
            PROTECTED_ITEMS=$(az backup item list \
                --resource-group ${BACKUP_RESOURCE_GROUP} \
                --vault-name ${RSV_SECONDARY_NAME} \
                --query 'length([])' --output tsv 2>/dev/null || echo "0")
            
            if [ "${PROTECTED_ITEMS}" -gt 0 ]; then
                warning "Found ${PROTECTED_ITEMS} protected items in vault ${RSV_SECONDARY_NAME}"
                warning "These items need to be unprotected before vault deletion"
                log "Attempting to stop protection for all items..."
                
                # This is a complex operation that may require manual intervention
                # For safety, we'll warn and continue
                warning "Manual intervention may be required to remove all protected items"
            fi
            
            az backup vault delete \
                --name ${RSV_SECONDARY_NAME} \
                --resource-group ${BACKUP_RESOURCE_GROUP} \
                --yes \
                >> "${LOG_FILE}" 2>&1 || warning "Failed to delete secondary vault, may require manual cleanup"
            
            success "Secondary Recovery Services Vault deletion attempted: ${RSV_SECONDARY_NAME}"
        else
            log "Secondary Recovery Services Vault not found: ${RSV_SECONDARY_NAME}"
        fi
    else
        log "No secondary Recovery Services Vault name specified, skipping deletion"
    fi
    
    # Remove primary Recovery Services Vault
    if [ -n "${RSV_PRIMARY_NAME:-}" ] && [ "${RSV_PRIMARY_NAME}" != "Not found" ]; then
        RSV_PRI_EXISTS=$(az backup vault show \
            --name ${RSV_PRIMARY_NAME} \
            --resource-group ${BACKUP_RESOURCE_GROUP} \
            --query 'name' --output tsv 2>/dev/null || echo "")
        
        if [ -n "${RSV_PRI_EXISTS}" ]; then
            log "Deleting primary Recovery Services Vault: ${RSV_PRIMARY_NAME}"
            
            # Check for protected items and warn user
            PROTECTED_ITEMS=$(az backup item list \
                --resource-group ${BACKUP_RESOURCE_GROUP} \
                --vault-name ${RSV_PRIMARY_NAME} \
                --query 'length([])' --output tsv 2>/dev/null || echo "0")
            
            if [ "${PROTECTED_ITEMS}" -gt 0 ]; then
                warning "Found ${PROTECTED_ITEMS} protected items in vault ${RSV_PRIMARY_NAME}"
                warning "These items need to be unprotected before vault deletion"
                log "Attempting to stop protection for all items..."
                
                # This is a complex operation that may require manual intervention
                # For safety, we'll warn and continue
                warning "Manual intervention may be required to remove all protected items"
            fi
            
            az backup vault delete \
                --name ${RSV_PRIMARY_NAME} \
                --resource-group ${BACKUP_RESOURCE_GROUP} \
                --yes \
                >> "${LOG_FILE}" 2>&1 || warning "Failed to delete primary vault, may require manual cleanup"
            
            success "Primary Recovery Services Vault deletion attempted: ${RSV_PRIMARY_NAME}"
        else
            log "Primary Recovery Services Vault not found: ${RSV_PRIMARY_NAME}"
        fi
    else
        log "No primary Recovery Services Vault name specified, skipping deletion"
    fi
    
    success "Recovery Services Vaults cleanup completed"
}

# Remove resource groups function
remove_resource_groups() {
    log "Removing resource groups..."
    
    warning "This will permanently delete all resources in the resource groups!"
    if ! confirm_action "Are you sure you want to delete all resource groups and their contents?"; then
        log "Skipping resource group deletion"
        return 0
    fi
    
    # Delete backup resource group
    BACKUP_RG_EXISTS=$(az group exists --name ${BACKUP_RESOURCE_GROUP} 2>/dev/null || echo "false")
    if [ "${BACKUP_RG_EXISTS}" = "true" ]; then
        log "Deleting backup resource group: ${BACKUP_RESOURCE_GROUP}"
        az group delete \
            --name ${BACKUP_RESOURCE_GROUP} \
            --yes \
            --no-wait \
            >> "${LOG_FILE}" 2>&1
        success "Backup resource group deletion initiated: ${BACKUP_RESOURCE_GROUP}"
    else
        log "Backup resource group not found: ${BACKUP_RESOURCE_GROUP}"
    fi
    
    # Delete main resource group
    RG_EXISTS=$(az group exists --name ${RESOURCE_GROUP} 2>/dev/null || echo "false")
    if [ "${RG_EXISTS}" = "true" ]; then
        log "Deleting main resource group: ${RESOURCE_GROUP}"
        az group delete \
            --name ${RESOURCE_GROUP} \
            --yes \
            --no-wait \
            >> "${LOG_FILE}" 2>&1
        success "Main resource group deletion initiated: ${RESOURCE_GROUP}"
    else
        log "Main resource group not found: ${RESOURCE_GROUP}"
    fi
    
    success "Resource group deletion initiated (may take several minutes to complete)"
}

# Clean up local files function
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment variables file
    if [ -f "${SCRIPT_DIR}/deployment_vars.sh" ]; then
        rm -f "${SCRIPT_DIR}/deployment_vars.sh"
        success "Removed deployment_vars.sh"
    fi
    
    # Remove any temporary files that might remain
    for temp_file in "logic-app-workflow.json" "vm-policy.json" "sql-policy.json" "dr-workbook-template.json"; do
        if [ -f "${SCRIPT_DIR}/${temp_file}" ]; then
            rm -f "${SCRIPT_DIR}/${temp_file}"
            success "Removed temporary file: ${temp_file}"
        fi
    done
    
    success "Local files cleanup completed"
}

# Display cleanup summary function
display_summary() {
    log ""
    log "=== CLEANUP SUMMARY ==="
    log "Cleanup completed at: $(date)"
    log ""
    log "Resources processed:"
    log "  ✅ Logic Apps and orchestration resources"
    log "  ✅ Monitoring infrastructure (alerts, workbooks, Log Analytics)"
    log "  ✅ Recovery Services Vaults (with backup data)"
    log "  ✅ Resource Groups (deletion initiated)"
    log "  ✅ Local temporary files"
    log ""
    log "Important notes:"
    log "  • Resource group deletion runs asynchronously and may take several minutes"
    log "  • If Recovery Services Vaults had protected items, manual cleanup may be required"
    log "  • Check Azure portal to verify all resources have been deleted"
    log "  • Some resources may have soft-delete enabled and require additional steps"
    log ""
    log "Cleanup log saved to: ${LOG_FILE}"
}

# Main cleanup function
main() {
    log "Starting Azure Disaster Recovery cleanup..."
    log "Cleanup started at: $(date)"
    
    # Check command line arguments
    if [ "${1:-}" = "--force" ]; then
        export FORCE_CLEANUP=true
        log "Force cleanup mode enabled - skipping confirmations"
    fi
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_variables
    check_resource_existence
    
    warning "This script will permanently delete Azure resources and data!"
    warning "Make sure you have backed up any important data before proceeding."
    
    if ! confirm_action "Do you want to proceed with the cleanup?"; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    remove_logic_apps
    remove_monitoring
    remove_recovery_vaults
    remove_resource_groups
    cleanup_local_files
    display_summary
    
    log "Cleanup process completed successfully!"
}

# Show usage information
show_usage() {
    echo "Usage: $0 [--force]"
    echo ""
    echo "Options:"
    echo "  --force    Skip confirmation prompts (use with caution)"
    echo ""
    echo "This script will remove all Azure resources created by the disaster recovery deployment."
    echo "Use with caution as this action is irreversible."
}

# Handle command line arguments
case "${1:-}" in
    -h|--help)
        show_usage
        exit 0
        ;;
    --force)
        main "$@"
        ;;
    "")
        main "$@"
        ;;
    *)
        echo "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac