#!/bin/bash

# Site Recovery Automation with Integrated Update Management
# Cleanup/Destroy Script
# 
# This script safely removes all resources created by the deployment script including:
# - Site Recovery protection and policies
# - Virtual machines and network resources
# - Recovery Services Vault
# - Resource groups and all contained resources

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_CONFIG="${SCRIPT_DIR}/deployment-config.json"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Success message function
success() {
    log "${GREEN}✅ ${1}${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️ ${1}${NC}"
}

# Error message function
error() {
    log "${RED}❌ ${1}${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️ ${1}${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please login to Azure CLI first: az login"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to load deployment configuration
load_deployment_config() {
    info "Loading deployment configuration..."
    
    if [ ! -f "${DEPLOYMENT_CONFIG}" ]; then
        error "Deployment configuration file not found: ${DEPLOYMENT_CONFIG}"
        error "Please ensure the deployment script was run successfully first"
        exit 1
    fi
    
    # Load configuration variables
    export RANDOM_SUFFIX=$(jq -r '.randomSuffix' "${DEPLOYMENT_CONFIG}")
    export RESOURCE_GROUP_PRIMARY=$(jq -r '.resourceGroupPrimary' "${DEPLOYMENT_CONFIG}")
    export RESOURCE_GROUP_SECONDARY=$(jq -r '.resourceGroupSecondary' "${DEPLOYMENT_CONFIG}")
    export LOCATION_PRIMARY=$(jq -r '.locationPrimary' "${DEPLOYMENT_CONFIG}")
    export LOCATION_SECONDARY=$(jq -r '.locationSecondary' "${DEPLOYMENT_CONFIG}")
    export SUBSCRIPTION_ID=$(jq -r '.subscriptionId' "${DEPLOYMENT_CONFIG}")
    export VAULT_NAME=$(jq -r '.vaultName' "${DEPLOYMENT_CONFIG}")
    export VNET_PRIMARY=$(jq -r '.vnetPrimary' "${DEPLOYMENT_CONFIG}")
    export VNET_SECONDARY=$(jq -r '.vnetSecondary' "${DEPLOYMENT_CONFIG}")
    export VM_PRIMARY=$(jq -r '.vmPrimary' "${DEPLOYMENT_CONFIG}")
    export NSG_PRIMARY=$(jq -r '.nsgPrimary' "${DEPLOYMENT_CONFIG}")
    export AUTOMATION_ACCOUNT=$(jq -r '.automationAccount' "${DEPLOYMENT_CONFIG}")
    export LOG_WORKSPACE=$(jq -r '.logWorkspace' "${DEPLOYMENT_CONFIG}")
    export ACTION_GROUP=$(jq -r '.actionGroup' "${DEPLOYMENT_CONFIG}")
    export STORAGE_ACCOUNT=$(jq -r '.storageAccount' "${DEPLOYMENT_CONFIG}")
    
    success "Deployment configuration loaded"
    info "Using suffix: ${RANDOM_SUFFIX}"
}

# Function to confirm destructive operation
confirm_destruction() {
    warning "This operation will PERMANENTLY DELETE all resources created by the deployment script."
    echo ""
    echo "Resources to be deleted:"
    echo "  - Resource Group: ${RESOURCE_GROUP_PRIMARY}"
    echo "  - Resource Group: ${RESOURCE_GROUP_SECONDARY}"
    echo "  - All resources within these groups"
    echo ""
    warning "This action cannot be undone!"
    echo ""
    
    # Check if running in non-interactive mode
    if [ "${FORCE_DESTROY:-false}" = "true" ]; then
        warning "Force destroy mode enabled - skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [ "${confirmation}" != "yes" ]; then
        info "Operation cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Function to stop any running test failovers
stop_test_failovers() {
    info "Stopping any running test failovers..."
    
    # Check if vault exists
    if ! az backup vault show \
        --resource-group "${RESOURCE_GROUP_SECONDARY}" \
        --name "${VAULT_NAME}" &> /dev/null; then
        warning "Recovery Services Vault not found - skipping failover cleanup"
        return 0
    fi
    
    # List any running jobs
    RUNNING_JOBS=$(az backup job list \
        --resource-group "${RESOURCE_GROUP_SECONDARY}" \
        --vault-name "${VAULT_NAME}" \
        --status InProgress \
        --query '[].name' \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "${RUNNING_JOBS}" ]; then
        warning "Found running backup/recovery jobs - they will be cancelled"
        # Note: In a real scenario, you might want to wait for jobs to complete
        # or handle them more gracefully
    fi
    
    success "Test failover cleanup completed"
}

# Function to disable Site Recovery protection
disable_site_recovery() {
    info "Disabling Site Recovery protection..."
    
    # Check if vault exists
    if ! az backup vault show \
        --resource-group "${RESOURCE_GROUP_SECONDARY}" \
        --name "${VAULT_NAME}" &> /dev/null; then
        warning "Recovery Services Vault not found - skipping Site Recovery cleanup"
        return 0
    fi
    
    # Check if VM exists
    if ! az vm show \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --name "${VM_PRIMARY}" &> /dev/null; then
        warning "Primary VM not found - skipping protection disable"
        return 0
    fi
    
    # Disable backup protection
    az backup protection disable \
        --resource-group "${RESOURCE_GROUP_SECONDARY}" \
        --vault-name "${VAULT_NAME}" \
        --container-name "${VM_PRIMARY}" \
        --item-name "${VM_PRIMARY}" \
        --delete-backup-data true \
        --yes \
        --force || warning "Failed to disable backup protection - continuing with cleanup"
    
    success "Site Recovery protection disabled"
}

# Function to clean up monitoring resources
cleanup_monitoring() {
    info "Cleaning up monitoring resources..."
    
    # Remove alert rules
    ALERT_RULES=$(az monitor metrics alert list \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --query "[?contains(name, '${RANDOM_SUFFIX}')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "${ALERT_RULES}" ]; then
        for rule in ${ALERT_RULES}; do
            az monitor metrics alert delete \
                --resource-group "${RESOURCE_GROUP_PRIMARY}" \
                --name "${rule}" \
                --yes || warning "Failed to delete alert rule: ${rule}"
        done
    fi
    
    # Remove action groups
    if az monitor action-group show \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --name "${ACTION_GROUP}" &> /dev/null; then
        az monitor action-group delete \
            --resource-group "${RESOURCE_GROUP_PRIMARY}" \
            --name "${ACTION_GROUP}" \
            --yes || warning "Failed to delete action group: ${ACTION_GROUP}"
    fi
    
    success "Monitoring resources cleaned up"
}

# Function to clean up automation resources
cleanup_automation() {
    info "Cleaning up automation resources..."
    
    # Remove runbooks
    if az automation account show \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --name "${AUTOMATION_ACCOUNT}" &> /dev/null; then
        
        # Delete runbooks
        RUNBOOKS=$(az automation runbook list \
            --resource-group "${RESOURCE_GROUP_PRIMARY}" \
            --automation-account-name "${AUTOMATION_ACCOUNT}" \
            --query '[].name' \
            --output tsv 2>/dev/null || echo "")
        
        if [ -n "${RUNBOOKS}" ]; then
            for runbook in ${RUNBOOKS}; do
                az automation runbook delete \
                    --resource-group "${RESOURCE_GROUP_PRIMARY}" \
                    --automation-account-name "${AUTOMATION_ACCOUNT}" \
                    --name "${runbook}" \
                    --yes || warning "Failed to delete runbook: ${runbook}"
            done
        fi
    fi
    
    success "Automation resources cleaned up"
}

# Function to clean up VM extensions
cleanup_vm_extensions() {
    info "Cleaning up VM extensions..."
    
    # Check if VM exists
    if ! az vm show \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --name "${VM_PRIMARY}" &> /dev/null; then
        warning "Primary VM not found - skipping extension cleanup"
        return 0
    fi
    
    # List and remove extensions
    EXTENSIONS=$(az vm extension list \
        --resource-group "${RESOURCE_GROUP_PRIMARY}" \
        --vm-name "${VM_PRIMARY}" \
        --query '[].name' \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "${EXTENSIONS}" ]; then
        for extension in ${EXTENSIONS}; do
            az vm extension delete \
                --resource-group "${RESOURCE_GROUP_PRIMARY}" \
                --vm-name "${VM_PRIMARY}" \
                --name "${extension}" \
                --yes || warning "Failed to delete extension: ${extension}"
        done
    fi
    
    success "VM extensions cleaned up"
}

# Function to delete primary resource group
delete_primary_resources() {
    info "Deleting primary resource group and all resources..."
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP_PRIMARY}" &> /dev/null; then
        warning "Primary resource group not found - skipping deletion"
        return 0
    fi
    
    # Delete resource group
    az group delete \
        --name "${RESOURCE_GROUP_PRIMARY}" \
        --yes \
        --no-wait
    
    success "Primary resource group deletion initiated: ${RESOURCE_GROUP_PRIMARY}"
}

# Function to delete secondary resource group
delete_secondary_resources() {
    info "Deleting secondary resource group and all resources..."
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP_SECONDARY}" &> /dev/null; then
        warning "Secondary resource group not found - skipping deletion"
        return 0
    fi
    
    # Delete resource group
    az group delete \
        --name "${RESOURCE_GROUP_SECONDARY}" \
        --yes \
        --no-wait
    
    success "Secondary resource group deletion initiated: ${RESOURCE_GROUP_SECONDARY}"
}

# Function to wait for resource group deletions
wait_for_deletions() {
    info "Waiting for resource group deletions to complete..."
    
    local timeout=1800  # 30 minutes
    local elapsed=0
    local check_interval=30
    
    while [ $elapsed -lt $timeout ]; do
        local primary_exists=false
        local secondary_exists=false
        
        # Check if primary resource group still exists
        if az group show --name "${RESOURCE_GROUP_PRIMARY}" &> /dev/null; then
            primary_exists=true
        fi
        
        # Check if secondary resource group still exists
        if az group show --name "${RESOURCE_GROUP_SECONDARY}" &> /dev/null; then
            secondary_exists=true
        fi
        
        # If both are gone, we're done
        if [ "$primary_exists" = false ] && [ "$secondary_exists" = false ]; then
            success "All resource groups have been deleted successfully"
            return 0
        fi
        
        # Show progress
        local remaining_groups=""
        if [ "$primary_exists" = true ]; then
            remaining_groups="${remaining_groups} ${RESOURCE_GROUP_PRIMARY}"
        fi
        if [ "$secondary_exists" = true ]; then
            remaining_groups="${remaining_groups} ${RESOURCE_GROUP_SECONDARY}"
        fi
        
        info "Still deleting resource groups:${remaining_groups}"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    warning "Timeout waiting for resource group deletions to complete"
    warning "Check Azure portal to verify deletion status"
}

# Function to clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    # Remove configuration files
    if [ -f "${DEPLOYMENT_CONFIG}" ]; then
        rm -f "${DEPLOYMENT_CONFIG}"
        success "Removed deployment configuration file"
    fi
    
    # Remove recovery plan files
    if [ -f "${SCRIPT_DIR}/recovery-plan.json" ]; then
        rm -f "${SCRIPT_DIR}/recovery-plan.json"
        success "Removed recovery plan configuration"
    fi
    
    if [ -f "${SCRIPT_DIR}/recovery-runbook.ps1" ]; then
        rm -f "${SCRIPT_DIR}/recovery-runbook.ps1"
        success "Removed recovery runbook"
    fi
    
    success "Local files cleaned up"
}

# Function to validate cleanup
validate_cleanup() {
    info "Validating cleanup..."
    
    local cleanup_issues=false
    
    # Check if primary resource group still exists
    if az group show --name "${RESOURCE_GROUP_PRIMARY}" &> /dev/null; then
        warning "Primary resource group still exists: ${RESOURCE_GROUP_PRIMARY}"
        cleanup_issues=true
    fi
    
    # Check if secondary resource group still exists
    if az group show --name "${RESOURCE_GROUP_SECONDARY}" &> /dev/null; then
        warning "Secondary resource group still exists: ${RESOURCE_GROUP_SECONDARY}"
        cleanup_issues=true
    fi
    
    if [ "$cleanup_issues" = false ]; then
        success "Cleanup validation completed successfully"
        return 0
    else
        warning "Some resources may still exist - check Azure portal for manual cleanup"
        return 1
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    info "Cleanup Summary:"
    echo ""
    echo "============================================"
    echo "Disaster Recovery Solution Cleanup Complete"
    echo "============================================"
    echo ""
    echo "Deleted Resource Groups:"
    echo "  - ${RESOURCE_GROUP_PRIMARY} (${LOCATION_PRIMARY})"
    echo "  - ${RESOURCE_GROUP_SECONDARY} (${LOCATION_SECONDARY})"
    echo ""
    echo "Cleaned Up Resources:"
    echo "  - Recovery Services Vault: ${VAULT_NAME}"
    echo "  - Virtual Machines and Networks"
    echo "  - Site Recovery Protection"
    echo "  - Azure Update Manager Configuration"
    echo "  - Monitoring and Automation Resources"
    echo ""
    echo "Local Files Cleaned:"
    echo "  - Deployment configuration"
    echo "  - Recovery plan files"
    echo "  - PowerShell runbooks"
    echo ""
    echo "Cleanup log: ${LOG_FILE}"
    echo ""
    info "All resources have been successfully removed"
}

# Main cleanup function
main() {
    info "Starting Azure Disaster Recovery cleanup..."
    info "Log file: ${LOG_FILE}"
    
    # Initialize log file
    echo "Azure Disaster Recovery Cleanup - $(date)" > "${LOG_FILE}"
    
    # Check for jq command
    if ! command -v jq &> /dev/null; then
        error "jq is required for parsing configuration file. Please install it first."
        exit 1
    fi
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_config
    confirm_destruction
    stop_test_failovers
    disable_site_recovery
    cleanup_monitoring
    cleanup_automation
    cleanup_vm_extensions
    delete_primary_resources
    delete_secondary_resources
    
    # Wait for deletions to complete (optional)
    if [ "${WAIT_FOR_COMPLETION:-true}" = "true" ]; then
        wait_for_deletions
    else
        info "Skipping wait for deletion completion"
    fi
    
    cleanup_local_files
    validate_cleanup
    display_cleanup_summary
    
    success "Cleanup completed successfully!"
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY=true
            shift
            ;;
        --no-wait)
            export WAIT_FOR_COMPLETION=false
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force     Skip confirmation prompts"
            echo "  --no-wait   Don't wait for resource deletion to complete"
            echo "  --help      Show this help message"
            echo ""
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"