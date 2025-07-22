#!/bin/bash

# Azure Chaos Studio and Application Insights Cleanup Script
# Safely removes all resources created by the deployment script
# Version: 1.0

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup.log"
readonly ENV_FILE="${SCRIPT_DIR}/.env"

# Logging functions
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Cleanup failed. Check ${LOG_FILE} for details."
    exit 1
}

# Load environment variables
load_environment() {
    if [[ -f "${ENV_FILE}" ]]; then
        log_info "Loading environment variables from ${ENV_FILE}"
        source "${ENV_FILE}"
        log_success "Environment variables loaded"
    else
        log_warning "Environment file not found: ${ENV_FILE}"
        log_warning "You may need to provide resource names manually"
        
        # Prompt for critical variables if not found
        if [[ -z "${RESOURCE_GROUP:-}" ]]; then
            read -p "Enter Resource Group name: " RESOURCE_GROUP
            export RESOURCE_GROUP
        fi
    fi
}

# Prerequisite checks
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az >/dev/null 2>&1; then
        error_exit "Azure CLI is not installed. Please install Azure CLI first."
    fi
    
    # Check if logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if resource group exists
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if ! az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
            log_warning "Resource group ${RESOURCE_GROUP} not found. It may have already been deleted."
        fi
    fi
    
    log_success "Prerequisites check completed"
}

# Confirmation prompt
confirm_deletion() {
    echo ""
    echo "========================== CLEANUP WARNING =========================="
    echo "This script will DELETE the following resources:"
    echo ""
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        echo "Resource Group:          ${RESOURCE_GROUP}"
    fi
    if [[ -n "${EXPERIMENT_NAME:-}" ]]; then
        echo "Chaos Experiment:       ${EXPERIMENT_NAME}"
    fi
    if [[ -n "${VM_NAME:-}" ]]; then
        echo "Virtual Machine:        ${VM_NAME}"
    fi
    if [[ -n "${APP_INSIGHTS_NAME:-}" ]]; then
        echo "Application Insights:   ${APP_INSIGHTS_NAME}"
    fi
    if [[ -n "${WORKSPACE_NAME:-}" ]]; then
        echo "Log Analytics:          ${WORKSPACE_NAME}"
    fi
    if [[ -n "${IDENTITY_NAME:-}" ]]; then
        echo "Managed Identity:       ${IDENTITY_NAME}"
    fi
    echo ""
    echo "⚠️  This action is IRREVERSIBLE and will delete all data!"
    echo "================================================================="
    echo ""
    
    # Skip confirmation if --force flag is provided
    if [[ "${1:-}" == "--force" ]]; then
        log_warning "Force flag detected. Skipping confirmation prompt."
        return 0
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Cleanup confirmed by user"
}

# Stop running experiments
stop_chaos_experiments() {
    if [[ -n "${EXPERIMENT_NAME:-}" ]] && [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_info "Stopping chaos experiment: ${EXPERIMENT_NAME}"
        
        local subscription_id=$(az account show --query id -o tsv)
        local experiment_url="https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Chaos/experiments/${EXPERIMENT_NAME}/stop?api-version=2024-01-01"
        
        if az rest --method post --url "${experiment_url}" >/dev/null 2>&1; then
            log_success "Chaos experiment stopped: ${EXPERIMENT_NAME}"
        else
            log_warning "Could not stop experiment ${EXPERIMENT_NAME} (may not be running)"
        fi
        
        # Wait a moment for experiment to stop
        sleep 5
    else
        log_warning "Experiment name not found. Skipping experiment stop."
    fi
}

# Delete chaos experiment
delete_chaos_experiment() {
    if [[ -n "${EXPERIMENT_NAME:-}" ]] && [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_info "Deleting chaos experiment: ${EXPERIMENT_NAME}"
        
        local subscription_id=$(az account show --query id -o tsv)
        local experiment_url="https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Chaos/experiments/${EXPERIMENT_NAME}?api-version=2024-01-01"
        
        if az rest --method delete --url "${experiment_url}" >/dev/null 2>&1; then
            log_success "Chaos experiment deleted: ${EXPERIMENT_NAME}"
        else
            log_warning "Could not delete experiment ${EXPERIMENT_NAME} (may not exist)"
        fi
    else
        log_warning "Experiment name not found. Skipping experiment deletion."
    fi
}

# Remove role assignments
remove_role_assignments() {
    if [[ -n "${EXPERIMENT_PRINCIPAL_ID:-}" ]] && [[ -n "${VM_RESOURCE_ID:-}" ]]; then
        log_info "Removing role assignments for experiment principal"
        
        if az role assignment delete \
            --assignee "${EXPERIMENT_PRINCIPAL_ID}" \
            --role "Virtual Machine Contributor" \
            --scope "${VM_RESOURCE_ID}" >/dev/null 2>&1; then
            log_success "Role assignment removed for experiment principal"
        else
            log_warning "Could not remove role assignment (may not exist)"
        fi
    else
        log_warning "Experiment principal ID or VM resource ID not found. Skipping role assignment cleanup."
    fi
}

# Delete specific resources (if resource group deletion fails)
delete_individual_resources() {
    local resource_group="${1:-${RESOURCE_GROUP}}"
    
    if [[ -z "${resource_group}" ]]; then
        log_warning "No resource group specified for individual resource deletion"
        return 1
    fi
    
    log_info "Attempting to delete individual resources..."
    
    # Delete VM extensions first
    if [[ -n "${VM_NAME:-}" ]]; then
        log_info "Removing Chaos Agent extension from VM: ${VM_NAME}"
        if az vm extension delete \
            --resource-group "${resource_group}" \
            --vm-name "${VM_NAME}" \
            --name ChaosAgent >/dev/null 2>&1; then
            log_success "Chaos Agent extension removed"
        else
            log_warning "Could not remove Chaos Agent extension (may not exist)"
        fi
    fi
    
    # Delete alert rules
    if az monitor metrics alert delete \
        --name "Chaos Experiment Active" \
        --resource-group "${resource_group}" >/dev/null 2>&1; then
        log_success "Alert rule deleted"
    else
        log_warning "Could not delete alert rule (may not exist)"
    fi
    
    # Delete action group
    if [[ -n "${ACTION_GROUP_NAME:-}" ]]; then
        if az monitor action-group delete \
            --name "${ACTION_GROUP_NAME}" \
            --resource-group "${resource_group}" >/dev/null 2>&1; then
            log_success "Action group deleted: ${ACTION_GROUP_NAME}"
        else
            log_warning "Could not delete action group (may not exist)"
        fi
    fi
    
    # Delete virtual machine
    if [[ -n "${VM_NAME:-}" ]]; then
        log_info "Deleting virtual machine: ${VM_NAME}"
        if az vm delete \
            --name "${VM_NAME}" \
            --resource-group "${resource_group}" \
            --yes >/dev/null 2>&1; then
            log_success "Virtual machine deleted: ${VM_NAME}"
        else
            log_warning "Could not delete virtual machine (may not exist)"
        fi
    fi
    
    # Delete managed identity
    if [[ -n "${IDENTITY_NAME:-}" ]]; then
        log_info "Deleting managed identity: ${IDENTITY_NAME}"
        if az identity delete \
            --name "${IDENTITY_NAME}" \
            --resource-group "${resource_group}" >/dev/null 2>&1; then
            log_success "Managed identity deleted: ${IDENTITY_NAME}"
        else
            log_warning "Could not delete managed identity (may not exist)"
        fi
    fi
    
    # Delete Application Insights
    if [[ -n "${APP_INSIGHTS_NAME:-}" ]]; then
        log_info "Deleting Application Insights: ${APP_INSIGHTS_NAME}"
        if az monitor app-insights component delete \
            --app "${APP_INSIGHTS_NAME}" \
            --resource-group "${resource_group}" >/dev/null 2>&1; then
            log_success "Application Insights deleted: ${APP_INSIGHTS_NAME}"
        else
            log_warning "Could not delete Application Insights (may not exist)"
        fi
    fi
    
    # Delete Log Analytics workspace
    if [[ -n "${WORKSPACE_NAME:-}" ]]; then
        log_info "Deleting Log Analytics workspace: ${WORKSPACE_NAME}"
        if az monitor log-analytics workspace delete \
            --resource-group "${resource_group}" \
            --workspace-name "${WORKSPACE_NAME}" \
            --yes >/dev/null 2>&1; then
            log_success "Log Analytics workspace deleted: ${WORKSPACE_NAME}"
        else
            log_warning "Could not delete Log Analytics workspace (may not exist)"
        fi
    fi
}

# Delete resource group and all resources
delete_resource_group() {
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        log_error "Resource group name not found. Cannot proceed with deletion."
        return 1
    fi
    
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        log_warning "Resource group ${RESOURCE_GROUP} does not exist"
        return 0
    fi
    
    # Try to delete the entire resource group
    if az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait; then
        log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        log_info "Note: Resource group deletion may take several minutes to complete"
        
        # Optional: Wait for deletion to complete
        read -p "Wait for resource group deletion to complete? (y/n): " wait_choice
        if [[ "${wait_choice}" =~ ^[Yy]$ ]]; then
            log_info "Waiting for resource group deletion to complete..."
            
            local timeout=300  # 5 minutes timeout
            local elapsed=0
            
            while az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; do
                if [[ ${elapsed} -ge ${timeout} ]]; then
                    log_warning "Timeout waiting for resource group deletion. Check Azure portal for status."
                    break
                fi
                
                sleep 10
                elapsed=$((elapsed + 10))
                log_info "Still waiting... (${elapsed}s elapsed)"
            done
            
            if ! az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
                log_success "Resource group deletion completed: ${RESOURCE_GROUP}"
            fi
        fi
    else
        log_error "Failed to delete resource group. Attempting individual resource deletion..."
        delete_individual_resources "${RESOURCE_GROUP}"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f "${ENV_FILE}" ]]; then
        rm -f "${ENV_FILE}"
        log_success "Environment file removed: ${ENV_FILE}"
    fi
    
    # Remove any temporary files
    local temp_files=(
        "${SCRIPT_DIR}/experiment.json"
        "${SCRIPT_DIR}/chaos-agent-settings.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_success "Temporary file removed: ${file}"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
            log_warning "Resource group ${RESOURCE_GROUP} still exists"
            log_info "You may need to check the Azure portal for cleanup status"
        else
            log_success "Resource group ${RESOURCE_GROUP} has been deleted"
        fi
    fi
    
    log_success "Cleanup verification completed"
}

# Display cleanup summary
display_summary() {
    echo ""
    echo "========================== CLEANUP SUMMARY =========================="
    echo "Cleanup operations completed."
    echo ""
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        echo "Resource Group:          ${RESOURCE_GROUP} (deletion initiated)"
    fi
    echo "Local files:            Cleaned up"
    echo ""
    echo "Notes:"
    echo "- Resource group deletion may take several minutes to complete"
    echo "- Check the Azure portal to verify all resources have been removed"
    echo "- Review your Azure bill to ensure no unexpected charges"
    echo ""
    echo "Cleanup log: ${LOG_FILE}"
    echo "================================================================="
}

# Main cleanup function
main() {
    local start_time=$(date +%s)
    
    log_info "Starting Azure Chaos Studio and Application Insights cleanup..."
    log_info "Script directory: ${SCRIPT_DIR}"
    log_info "Log file: ${LOG_FILE}"
    
    # Load environment and check prerequisites
    load_environment
    check_prerequisites
    
    # Confirm deletion with user
    confirm_deletion "$@"
    
    # Execute cleanup steps in reverse order of creation
    stop_chaos_experiments
    delete_chaos_experiment
    remove_role_assignments
    delete_resource_group
    cleanup_local_files
    verify_cleanup
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    display_summary
    log_success "Cleanup completed in ${duration} seconds"
}

# Show help information
show_help() {
    echo "Azure Chaos Studio and Application Insights Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force     Skip confirmation prompt and delete immediately"
    echo "  --help      Show this help message"
    echo ""
    echo "This script will:"
    echo "1. Stop any running chaos experiments"
    echo "2. Delete the chaos experiment"
    echo "3. Remove role assignments"
    echo "4. Delete the entire resource group and all contained resources"
    echo "5. Clean up local configuration files"
    echo ""
    echo "Prerequisites:"
    echo "- Azure CLI installed and logged in"
    echo "- Access to the resource group created by deploy.sh"
    echo "- .env file from deploy.sh (for automatic resource discovery)"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac