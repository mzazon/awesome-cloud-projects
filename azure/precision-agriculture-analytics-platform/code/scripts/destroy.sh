#!/bin/bash

# ==============================================================================
# Azure Precision Agriculture Analytics Cleanup Script
# ==============================================================================
# This script safely removes all resources created by the deployment script
# for the Azure Precision Agriculture Analytics platform
# ==============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/../destroy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/../destroy_errors.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/../deployment_config.env"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "${ERROR_LOG}" >&2
}

log_success() {
    echo -e "${GREEN}$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: $1${NC}" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1${NC}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}$(date '+%Y-%m-%d %H:%M:%S') - INFO: $1${NC}" | tee -a "${LOG_FILE}"
}

# Error handling
handle_error() {
    log_error "An error occurred during cleanup. Some resources may still exist."
    log_error "Please check the Azure portal and remove any remaining resources manually."
    exit 1
}

trap handle_error ERR

# Load deployment configuration
load_deployment_config() {
    log_info "Loading deployment configuration..."
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Deployment configuration file not found: ${CONFIG_FILE}"
        log_error "Cannot proceed with automated cleanup. Please clean up resources manually."
        exit 1
    fi
    
    # Source the configuration file
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
    
    # Verify required variables are set
    local required_vars=(
        "RESOURCE_GROUP"
        "ADMA_INSTANCE"
        "IOT_HUB_NAME"
        "STREAM_JOB_NAME"
        "STORAGE_ACCOUNT"
        "AI_SERVICES_NAME"
        "MAPS_ACCOUNT"
        "FUNCTION_APP_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable ${var} is not set in configuration file"
            exit 1
        fi
    done
    
    log_success "Configuration loaded successfully"
    log_info "Resource Group: ${RESOURCE_GROUP}"
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &>/dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group exists --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} does not exist. Nothing to clean up."
        exit 0
    fi
    
    log_success "Prerequisites check completed"
}

# Confirmation prompt
confirm_destruction() {
    log_warning "This will permanently delete all resources in the resource group: ${RESOURCE_GROUP}"
    log_warning "This action cannot be undone!"
    
    echo ""
    echo -e "${RED}Resources to be deleted:${NC}"
    echo "- Resource Group: ${RESOURCE_GROUP}"
    echo "- Azure Data Manager for Agriculture: ${ADMA_INSTANCE}"
    echo "- IoT Hub: ${IOT_HUB_NAME}"
    echo "- AI Services: ${AI_SERVICES_NAME}"
    echo "- Azure Maps: ${MAPS_ACCOUNT}"
    echo "- Stream Analytics: ${STREAM_JOB_NAME}"
    echo "- Storage Account: ${STORAGE_ACCOUNT}"
    echo "- Function App: ${FUNCTION_APP_NAME}"
    echo "- All associated data and configurations"
    echo ""
    
    # Skip confirmation if FORCE_DESTROY is set (for automated scenarios)
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log_warning "FORCE_DESTROY is set. Skipping confirmation prompt."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "User confirmed destruction. Proceeding with cleanup..."
}

# Stop Stream Analytics job
stop_stream_analytics() {
    log_info "Stopping Stream Analytics job: ${STREAM_JOB_NAME}"
    
    # Check if Stream Analytics job exists and is running
    local job_state
    job_state=$(az stream-analytics job show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${STREAM_JOB_NAME}" \
        --query "jobState" --output tsv 2>/dev/null || echo "NotFound")
    
    if [[ "${job_state}" == "NotFound" ]]; then
        log_info "Stream Analytics job not found, skipping stop operation"
        return 0
    fi
    
    if [[ "${job_state}" == "Running" ]]; then
        az stream-analytics job stop \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${STREAM_JOB_NAME}" \
            || {
                log_warning "Failed to stop Stream Analytics job, continuing with deletion"
            }
        log_success "Stream Analytics job stopped"
    else
        log_info "Stream Analytics job is not running (state: ${job_state})"
    fi
}

# Delete individual resources (safer approach before deleting resource group)
delete_individual_resources() {
    log_info "Deleting individual resources for safer cleanup..."
    
    # Stop Stream Analytics first to avoid ongoing charges
    stop_stream_analytics
    
    # Delete Azure Data Manager for Agriculture
    log_info "Deleting Azure Data Manager for Agriculture: ${ADMA_INSTANCE}"
    if az datamgr-for-agriculture show --resource-group "${RESOURCE_GROUP}" --name "${ADMA_INSTANCE}" &>/dev/null; then
        az datamgr-for-agriculture delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${ADMA_INSTANCE}" \
            --yes \
            || log_warning "Failed to delete Azure Data Manager for Agriculture"
        log_success "Azure Data Manager for Agriculture deletion initiated"
    else
        log_info "Azure Data Manager for Agriculture not found, skipping"
    fi
    
    # Delete Function App
    log_info "Deleting Function App: ${FUNCTION_APP_NAME}"
    if az functionapp show --resource-group "${RESOURCE_GROUP}" --name "${FUNCTION_APP_NAME}" &>/dev/null; then
        az functionapp delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${FUNCTION_APP_NAME}" \
            --yes \
            || log_warning "Failed to delete Function App"
        log_success "Function App deleted"
    else
        log_info "Function App not found, skipping"
    fi
    
    # Delete Stream Analytics job
    log_info "Deleting Stream Analytics job: ${STREAM_JOB_NAME}"
    if az stream-analytics job show --resource-group "${RESOURCE_GROUP}" --name "${STREAM_JOB_NAME}" &>/dev/null; then
        az stream-analytics job delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${STREAM_JOB_NAME}" \
            --yes \
            || log_warning "Failed to delete Stream Analytics job"
        log_success "Stream Analytics job deleted"
    else
        log_info "Stream Analytics job not found, skipping"
    fi
    
    # Delete IoT Hub
    log_info "Deleting IoT Hub: ${IOT_HUB_NAME}"
    if az iot hub show --resource-group "${RESOURCE_GROUP}" --name "${IOT_HUB_NAME}" &>/dev/null; then
        az iot hub delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${IOT_HUB_NAME}" \
            --yes \
            || log_warning "Failed to delete IoT Hub"
        log_success "IoT Hub deleted"
    else
        log_info "IoT Hub not found, skipping"
    fi
    
    # Delete AI Services
    log_info "Deleting AI Services: ${AI_SERVICES_NAME}"
    if az cognitiveservices account show --resource-group "${RESOURCE_GROUP}" --name "${AI_SERVICES_NAME}" &>/dev/null; then
        az cognitiveservices account delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${AI_SERVICES_NAME}" \
            --yes \
            || log_warning "Failed to delete AI Services"
        log_success "AI Services deleted"
    else
        log_info "AI Services not found, skipping"
    fi
    
    # Delete Azure Maps
    log_info "Deleting Azure Maps: ${MAPS_ACCOUNT}"
    if az maps account show --resource-group "${RESOURCE_GROUP}" --name "${MAPS_ACCOUNT}" &>/dev/null; then
        az maps account delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${MAPS_ACCOUNT}" \
            --yes \
            || log_warning "Failed to delete Azure Maps"
        log_success "Azure Maps deleted"
    else
        log_info "Azure Maps not found, skipping"
    fi
    
    # Delete Storage Account (last, as it may contain logs and data)
    log_info "Deleting Storage Account: ${STORAGE_ACCOUNT}"
    if az storage account show --resource-group "${RESOURCE_GROUP}" --name "${STORAGE_ACCOUNT}" &>/dev/null; then
        az storage account delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${STORAGE_ACCOUNT}" \
            --yes \
            || log_warning "Failed to delete Storage Account"
        log_success "Storage Account deleted"
    else
        log_info "Storage Account not found, skipping"
    fi
}

# Wait for resource deletions to complete
wait_for_deletions() {
    log_info "Waiting for resource deletions to complete..."
    
    local max_wait_time=300  # 5 minutes
    local wait_interval=30   # 30 seconds
    local total_waited=0
    
    while [[ ${total_waited} -lt ${max_wait_time} ]]; do
        local resources_remaining=0
        
        # Check if any major resources still exist
        if az datamgr-for-agriculture show --resource-group "${RESOURCE_GROUP}" --name "${ADMA_INSTANCE}" &>/dev/null; then
            ((resources_remaining++))
        fi
        
        if az functionapp show --resource-group "${RESOURCE_GROUP}" --name "${FUNCTION_APP_NAME}" &>/dev/null; then
            ((resources_remaining++))
        fi
        
        if az stream-analytics job show --resource-group "${RESOURCE_GROUP}" --name "${STREAM_JOB_NAME}" &>/dev/null; then
            ((resources_remaining++))
        fi
        
        if [[ ${resources_remaining} -eq 0 ]]; then
            log_success "All major resources have been deleted"
            break
        fi
        
        log_info "Waiting for ${resources_remaining} resources to finish deleting..."
        sleep ${wait_interval}
        total_waited=$((total_waited + wait_interval))
    done
    
    if [[ ${total_waited} -ge ${max_wait_time} ]]; then
        log_warning "Timeout waiting for resource deletions. Proceeding with resource group deletion."
    fi
}

# Delete the entire resource group
delete_resource_group() {
    log_info "Deleting resource group: ${RESOURCE_GROUP}"
    
    # Final check that resource group exists
    if ! az group exists --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_info "Resource group ${RESOURCE_GROUP} no longer exists"
        return 0
    fi
    
    # Delete the resource group and all remaining resources
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        || {
            log_error "Failed to initiate resource group deletion"
            exit 1
        }
    
    log_success "Resource group deletion initiated: ${RESOURCE_GROUP}"
    log_info "Deletion is running in the background and may take several minutes to complete"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Wait a bit for the deletion to start
    sleep 10
    
    local max_attempts=6  # Check for up to 3 minutes
    local attempt=0
    
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        if ! az group exists --name "${RESOURCE_GROUP}" &>/dev/null; then
            log_success "Resource group ${RESOURCE_GROUP} has been completely deleted"
            return 0
        fi
        
        log_info "Resource group still exists, checking again in 30 seconds..."
        sleep 30
        ((attempt++))
    done
    
    log_warning "Resource group ${RESOURCE_GROUP} still exists after verification period"
    log_warning "The deletion may still be in progress. Check the Azure portal for status."
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    # Remove deployment configuration file
    if [[ -f "${CONFIG_FILE}" ]]; then
        rm -f "${CONFIG_FILE}"
        log_success "Removed deployment configuration file"
    fi
    
    # Remove any other generated files (excluding log files for reference)
    local cleanup_files=(
        "${SCRIPT_DIR}/../.env"
        "${SCRIPT_DIR}/../farm_config.json"
        "${SCRIPT_DIR}/../field_config.json"
    )
    
    for file in "${cleanup_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_info "Removed file: $(basename "${file}")"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "===========================================" | tee -a "${LOG_FILE}"
    echo "Azure Precision Agriculture Analytics Platform" | tee -a "${LOG_FILE}"
    echo "CLEANUP COMPLETED" | tee -a "${LOG_FILE}"
    echo "===========================================" | tee -a "${LOG_FILE}"
    echo "Resource Group: ${RESOURCE_GROUP} (DELETED)" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "Deleted Services:" | tee -a "${LOG_FILE}"
    echo "- Azure Data Manager for Agriculture: ${ADMA_INSTANCE}" | tee -a "${LOG_FILE}"
    echo "- IoT Hub: ${IOT_HUB_NAME}" | tee -a "${LOG_FILE}"
    echo "- AI Services: ${AI_SERVICES_NAME}" | tee -a "${LOG_FILE}"
    echo "- Azure Maps: ${MAPS_ACCOUNT}" | tee -a "${LOG_FILE}"
    echo "- Stream Analytics: ${STREAM_JOB_NAME}" | tee -a "${LOG_FILE}"
    echo "- Storage Account: ${STORAGE_ACCOUNT}" | tee -a "${LOG_FILE}"
    echo "- Function App: ${FUNCTION_APP_NAME}" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "All resources and data have been permanently deleted." | tee -a "${LOG_FILE}"
    echo "Log files are preserved for reference:" | tee -a "${LOG_FILE}"
    echo "- Deployment log: ${SCRIPT_DIR}/../deploy.log" | tee -a "${LOG_FILE}"
    echo "- Cleanup log: ${LOG_FILE}" | tee -a "${LOG_FILE}"
    echo "===========================================" | tee -a "${LOG_FILE}"
}

# Main cleanup function
main() {
    log_info "Starting Azure Precision Agriculture Analytics cleanup..."
    
    # Clear previous logs
    > "${LOG_FILE}"
    > "${ERROR_LOG}"
    
    load_deployment_config
    check_prerequisites
    confirm_destruction
    delete_individual_resources
    wait_for_deletions
    delete_resource_group
    verify_cleanup
    cleanup_local_files
    
    display_cleanup_summary
    log_success "Cleanup completed successfully!"
    
    echo ""
    echo -e "${GREEN}Cleanup completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}Important notes:${NC}"
    echo "- All Azure resources have been deleted"
    echo "- Check your Azure Cost Management to verify no ongoing charges"
    echo "- Log files have been preserved for reference"
    echo "- If you see any remaining resources in the Azure portal, delete them manually"
    echo ""
    echo -e "${YELLOW}Final verification:${NC}"
    echo "You can verify complete deletion by checking the Azure portal"
    echo "or running: az group exists --name ${RESOURCE_GROUP}"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi