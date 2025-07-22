#!/bin/bash

# Azure Infrastructure Provisioning with Azure Automation and ARM Templates
# Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "Prerequisites check passed ✅"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set default values (same as deploy script)
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-automation-demo}"
    export LOCATION="${LOCATION:-eastus}"
    export AUTOMATION_ACCOUNT="${AUTOMATION_ACCOUNT:-aa-infra-provisioning}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stautoarmtemplates$(openssl rand -hex 3)}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-automation-monitoring}"
    export TARGET_RESOURCE_GROUP="${TARGET_RESOURCE_GROUP:-rg-deployed-infrastructure}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    info "Environment variables set:"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  Automation Account: ${AUTOMATION_ACCOUNT}"
    info "  Storage Account: ${STORAGE_ACCOUNT}"
    info "  Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}"
    info "  Target Resource Group: ${TARGET_RESOURCE_GROUP}"
    info "  Subscription ID: ${SUBSCRIPTION_ID}"
}

# Function to confirm destructive action
confirm_destruction() {
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        log "Force destroy mode enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    warn "⚠️  This will permanently delete the following resources:"
    echo "  - Resource Group: ${RESOURCE_GROUP}"
    echo "  - Target Resource Group: ${TARGET_RESOURCE_GROUP}"
    echo "  - All contained resources (Automation Account, Storage Account, Log Analytics, etc.)"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed by user"
}

# Function to stop running automation jobs
stop_automation_jobs() {
    log "Stopping any running automation jobs..."
    
    # Check if automation account exists
    if ! az automation account show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AUTOMATION_ACCOUNT}" >/dev/null 2>&1; then
        info "Automation account ${AUTOMATION_ACCOUNT} does not exist. Skipping job cleanup."
        return 0
    fi
    
    # Get list of running jobs
    local running_jobs=$(az automation job list \
        --resource-group "${RESOURCE_GROUP}" \
        --automation-account-name "${AUTOMATION_ACCOUNT}" \
        --query "[?status=='Running'].jobId" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${running_jobs}" ]]; then
        info "Found running automation jobs. Stopping them..."
        
        while IFS= read -r job_id; do
            if [[ -n "${job_id}" ]]; then
                info "Stopping job: ${job_id}"
                az automation job stop \
                    --resource-group "${RESOURCE_GROUP}" \
                    --automation-account-name "${AUTOMATION_ACCOUNT}" \
                    --job-id "${job_id}" \
                    --output none 2>/dev/null || warn "Failed to stop job ${job_id}"
            fi
        done <<< "${running_jobs}"
        
        log "Automation jobs stopped ✅"
    else
        info "No running automation jobs found"
    fi
}

# Function to remove deployed infrastructure
remove_deployed_infrastructure() {
    log "Removing deployed infrastructure from target resource group..."
    
    # Check if target resource group exists
    if az group show --name "${TARGET_RESOURCE_GROUP}" >/dev/null 2>&1; then
        info "Deleting target resource group: ${TARGET_RESOURCE_GROUP}"
        
        # List resources in target resource group for informational purposes
        local resources=$(az resource list \
            --resource-group "${TARGET_RESOURCE_GROUP}" \
            --query "[].{name:name,type:type}" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "${resources}" ]]; then
            info "Resources to be deleted:"
            echo "${resources}" | while IFS=$'\t' read -r name type; do
                info "  - ${name} (${type})"
            done
        fi
        
        # Delete target resource group
        az group delete \
            --name "${TARGET_RESOURCE_GROUP}" \
            --yes \
            --no-wait \
            --output none
        
        log "Target resource group deletion initiated ✅"
    else
        info "Target resource group ${TARGET_RESOURCE_GROUP} does not exist. Skipping."
    fi
}

# Function to remove automation account
remove_automation_account() {
    log "Removing Azure Automation Account..."
    
    # Check if automation account exists
    if az automation account show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AUTOMATION_ACCOUNT}" >/dev/null 2>&1; then
        
        info "Deleting automation account: ${AUTOMATION_ACCOUNT}"
        
        # Delete automation account
        az automation account delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${AUTOMATION_ACCOUNT}" \
            --yes \
            --output none
        
        log "Automation account deleted ✅"
    else
        info "Automation account ${AUTOMATION_ACCOUNT} does not exist. Skipping."
    fi
}

# Function to remove storage account
remove_storage_account() {
    log "Removing storage account..."
    
    # Check if storage account exists
    if az storage account show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${STORAGE_ACCOUNT}" >/dev/null 2>&1; then
        
        info "Deleting storage account: ${STORAGE_ACCOUNT}"
        
        # Delete storage account
        az storage account delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${STORAGE_ACCOUNT}" \
            --yes \
            --output none
        
        log "Storage account deleted ✅"
    else
        info "Storage account ${STORAGE_ACCOUNT} does not exist. Skipping."
    fi
}

# Function to remove Log Analytics workspace
remove_log_analytics_workspace() {
    log "Removing Log Analytics workspace..."
    
    # Check if Log Analytics workspace exists
    if az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" >/dev/null 2>&1; then
        
        info "Deleting Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE}"
        
        # Delete Log Analytics workspace
        az monitor log-analytics workspace delete \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
            --yes \
            --output none
        
        log "Log Analytics workspace deleted ✅"
    else
        info "Log Analytics workspace ${LOG_ANALYTICS_WORKSPACE} does not exist. Skipping."
    fi
}

# Function to remove main resource group
remove_main_resource_group() {
    log "Removing main resource group..."
    
    # Check if main resource group exists
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        info "Deleting main resource group: ${RESOURCE_GROUP}"
        
        # List remaining resources in main resource group
        local resources=$(az resource list \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[].{name:name,type:type}" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "${resources}" ]]; then
            info "Remaining resources to be deleted:"
            echo "${resources}" | while IFS=$'\t' read -r name type; do
                info "  - ${name} (${type})"
            done
        fi
        
        # Delete main resource group
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait \
            --output none
        
        log "Main resource group deletion initiated ✅"
    else
        info "Main resource group ${RESOURCE_GROUP} does not exist. Skipping."
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_complete=true
    
    # Check if main resource group still exists
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Main resource group ${RESOURCE_GROUP} still exists (deletion may still be in progress)"
        cleanup_complete=false
    else
        log "Main resource group ${RESOURCE_GROUP} successfully deleted ✅"
    fi
    
    # Check if target resource group still exists
    if az group show --name "${TARGET_RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Target resource group ${TARGET_RESOURCE_GROUP} still exists (deletion may still be in progress)"
        cleanup_complete=false
    else
        log "Target resource group ${TARGET_RESOURCE_GROUP} successfully deleted ✅"
    fi
    
    if [[ "${cleanup_complete}" == "true" ]]; then
        log "Cleanup verification completed successfully ✅"
    else
        warn "Some resources may still be in the process of being deleted. Check the Azure portal for status."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "===================="
    echo "The following resources have been deleted or are being deleted:"
    echo "  - Resource Group: ${RESOURCE_GROUP}"
    echo "  - Target Resource Group: ${TARGET_RESOURCE_GROUP}"
    echo "  - Automation Account: ${AUTOMATION_ACCOUNT}"
    echo "  - Storage Account: ${STORAGE_ACCOUNT}"
    echo "  - Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}"
    echo "  - All ARM template deployed resources"
    echo "  - All RBAC role assignments"
    echo "===================="
    echo ""
    echo "Note: Resource group deletions may take several minutes to complete."
    echo "You can monitor the progress in the Azure portal."
}

# Function to handle cleanup errors
handle_cleanup_errors() {
    local exit_code=$?
    
    if [[ ${exit_code} -ne 0 ]]; then
        error "Cleanup encountered errors (exit code: ${exit_code})"
        warn "Some resources may not have been deleted. Please check the Azure portal and clean up manually if needed."
        
        echo ""
        echo "Manual cleanup commands:"
        echo "  az group delete --name ${RESOURCE_GROUP} --yes --no-wait"
        echo "  az group delete --name ${TARGET_RESOURCE_GROUP} --yes --no-wait"
        
        exit ${exit_code}
    fi
}

# Function to handle partial cleanup
handle_partial_cleanup() {
    log "Performing partial cleanup..."
    
    # Allow user to choose what to clean up
    echo ""
    echo "Choose what to clean up:"
    echo "1. Only deployed infrastructure (target resource group)"
    echo "2. Only automation infrastructure (main resource group)"
    echo "3. Everything (both resource groups)"
    echo "4. Cancel"
    
    read -p "Enter your choice (1-4): " choice
    
    case ${choice} in
        1)
            info "Cleaning up only deployed infrastructure..."
            stop_automation_jobs
            remove_deployed_infrastructure
            ;;
        2)
            info "Cleaning up only automation infrastructure..."
            stop_automation_jobs
            remove_automation_account
            remove_storage_account
            remove_log_analytics_workspace
            remove_main_resource_group
            ;;
        3)
            info "Cleaning up everything..."
            return 1  # Continue with full cleanup
            ;;
        4)
            log "Cleanup cancelled by user"
            exit 0
            ;;
        *)
            error "Invalid choice. Please run the script again."
            exit 1
            ;;
    esac
    
    log "Partial cleanup completed ✅"
    exit 0
}

# Main execution
main() {
    log "Starting Azure Infrastructure Provisioning cleanup..."
    
    # Set trap for error handling
    trap 'handle_cleanup_errors' ERR
    
    # Check for force mode
    if [[ "${1:-}" == "--force" ]]; then
        export FORCE_DESTROY=true
        log "Force destroy mode enabled"
    fi
    
    # Check for partial cleanup mode
    if [[ "${1:-}" == "--partial" ]]; then
        handle_partial_cleanup
    fi
    
    # Check for dry run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        info "Running in dry-run mode - no resources will be deleted"
        export DRY_RUN=true
    fi
    
    check_prerequisites
    set_environment_variables
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "Dry run completed - no resources were deleted"
        echo ""
        echo "Resources that would be deleted:"
        echo "  - Resource Group: ${RESOURCE_GROUP}"
        echo "  - Target Resource Group: ${TARGET_RESOURCE_GROUP}"
        echo "  - All contained resources"
        exit 0
    fi
    
    confirm_destruction
    
    # Perform cleanup in logical order
    stop_automation_jobs
    remove_deployed_infrastructure
    remove_automation_account
    remove_storage_account
    remove_log_analytics_workspace
    remove_main_resource_group
    
    # Wait a bit for deletions to propagate
    info "Waiting for deletions to propagate..."
    sleep 10
    
    verify_cleanup
    
    log "Cleanup completed successfully! 🎉"
    display_cleanup_summary
}

# Run main function with all arguments
main "$@"