#!/bin/bash

# Destroy script for Healthcare Edge Analytics with SQL Edge and FHIR Compliance
# This script safely removes all resources created by the deployment script

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup.log"
readonly ERROR_LOG="${SCRIPT_DIR}/cleanup_errors.log"
readonly DEPLOYMENT_INFO="${SCRIPT_DIR}/deployment_info.txt"

# Logging functions
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $*" | tee -a "${LOG_FILE}"
}

error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] ERROR: $*" | tee -a "${ERROR_LOG}" >&2
}

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${ERROR_LOG}")

log "=== Starting Healthcare Edge Analytics Cleanup ==="

# Function to extract deployment info
extract_deployment_info() {
    if [[ -f "${DEPLOYMENT_INFO}" ]]; then
        log "Reading deployment information from ${DEPLOYMENT_INFO}"
        
        # Extract resource group from deployment info
        RESOURCE_GROUP=$(grep "Resource Group:" "${DEPLOYMENT_INFO}" | cut -d' ' -f3 || echo "")
        LOCATION=$(grep "Location:" "${DEPLOYMENT_INFO}" | cut -d' ' -f2 || echo "")
        IOT_HUB_NAME=$(grep "IoT Hub:" "${DEPLOYMENT_INFO}" | cut -d' ' -f3 || echo "")
        WORKSPACE_NAME=$(grep "- Workspace:" "${DEPLOYMENT_INFO}" | cut -d' ' -f3 || echo "")
        FHIR_SERVICE_NAME=$(grep "- FHIR Service:" "${DEPLOYMENT_INFO}" | cut -d' ' -f4 || echo "")
        FUNCTION_APP_NAME=$(grep "Function App:" "${DEPLOYMENT_INFO}" | cut -d' ' -f3 || echo "")
        STORAGE_ACCOUNT=$(grep "Storage Account:" "${DEPLOYMENT_INFO}" | cut -d' ' -f3 || echo "")
        LOG_ANALYTICS_WORKSPACE=$(grep "Log Analytics Workspace:" "${DEPLOYMENT_INFO}" | cut -d' ' -f4 || echo "")
        
        log "Found deployment info:"
        log "  Resource Group: ${RESOURCE_GROUP}"
        log "  Location: ${LOCATION}"
        log "  IoT Hub: ${IOT_HUB_NAME}"
        log "  Function App: ${FUNCTION_APP_NAME}"
    else
        log "No deployment info file found. Will prompt for resource group name."
    fi
}

# Function to prompt for resource group if not found
prompt_for_resource_group() {
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        echo
        echo "No deployment info found. Please provide the resource group name to clean up."
        echo "You can find this in the Azure portal or by running: az group list --query '[].name' -o table"
        echo
        read -p "Enter the resource group name: " RESOURCE_GROUP
        
        if [[ -z "${RESOURCE_GROUP}" ]]; then
            error "Resource group name is required"
            exit 1
        fi
        
        # Verify the resource group exists
        if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            error "Resource group '${RESOURCE_GROUP}' does not exist or is not accessible"
            exit 1
        fi
        
        log "Using resource group: ${RESOURCE_GROUP}"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log "✅ Prerequisites check completed successfully"
}

# Function to list resources in the resource group
list_resources() {
    log "Listing resources in resource group: ${RESOURCE_GROUP}"
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log "Resource group '${RESOURCE_GROUP}' does not exist. Nothing to clean up."
        return 0
    fi
    
    # List all resources
    local resources
    resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query '[].{Name:name, Type:type}' -o table 2>/dev/null || echo "")
    
    if [[ -n "${resources}" ]]; then
        log "Resources found in ${RESOURCE_GROUP}:"
        echo "${resources}" | tee -a "${LOG_FILE}"
    else
        log "No resources found in resource group ${RESOURCE_GROUP}"
    fi
}

# Function to safely delete individual resources with dependencies
delete_individual_resources() {
    log "Deleting individual resources to handle dependencies..."
    
    # Delete diagnostic settings first (they depend on resources)
    log "Removing diagnostic settings..."
    if [[ -n "${IOT_HUB_NAME:-}" ]]; then
        az monitor diagnostic-settings delete \
            --name "iot-diagnostics" \
            --resource-id "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Devices/IotHubs/${IOT_HUB_NAME}" \
            2>/dev/null || log "Diagnostic settings not found or already deleted"
    fi
    
    # Delete Function App (and associated app service plan)
    if [[ -n "${FUNCTION_APP_NAME:-}" ]]; then
        log "Deleting Function App: ${FUNCTION_APP_NAME}"
        if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az functionapp delete \
                --name "${FUNCTION_APP_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || log "Warning: Failed to delete Function App"
            log "✅ Function App deleted"
        else
            log "Function App not found, skipping"
        fi
    fi
    
    # Delete Application Insights
    if [[ -n "${FUNCTION_APP_NAME:-}" ]]; then
        log "Deleting Application Insights for Function App..."
        if az monitor app-insights component show --app "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az monitor app-insights component delete \
                --app "${FUNCTION_APP_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || log "Warning: Failed to delete Application Insights"
            log "✅ Application Insights deleted"
        else
            log "Application Insights not found, skipping"
        fi
    fi
    
    # Delete FHIR service (must be deleted before workspace)
    if [[ -n "${FHIR_SERVICE_NAME:-}" ]] && [[ -n "${WORKSPACE_NAME:-}" ]]; then
        log "Deleting FHIR service: ${FHIR_SERVICE_NAME}"
        if az healthcareapis service fhir show \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${WORKSPACE_NAME}" \
            --fhir-service-name "${FHIR_SERVICE_NAME}" &> /dev/null; then
            az healthcareapis service fhir delete \
                --resource-group "${RESOURCE_GROUP}" \
                --workspace-name "${WORKSPACE_NAME}" \
                --fhir-service-name "${FHIR_SERVICE_NAME}" \
                --yes || log "Warning: Failed to delete FHIR service"
            log "✅ FHIR service deleted"
            sleep 15  # Wait for FHIR service deletion to complete
        else
            log "FHIR service not found, skipping"
        fi
    fi
    
    # Delete Health Data Services workspace
    if [[ -n "${WORKSPACE_NAME:-}" ]]; then
        log "Deleting Health Data Services workspace: ${WORKSPACE_NAME}"
        if az healthcareapis workspace show --name "${WORKSPACE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az healthcareapis workspace delete \
                --name "${WORKSPACE_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || log "Warning: Failed to delete Health Data Services workspace"
            log "✅ Health Data Services workspace deleted"
        else
            log "Health Data Services workspace not found, skipping"
        fi
    fi
    
    # Delete IoT Edge device first, then IoT Hub
    if [[ -n "${IOT_HUB_NAME:-}" ]]; then
        # Delete IoT Edge device
        if [[ -n "${EDGE_DEVICE_ID:-medical-edge-device-01}" ]]; then
            log "Deleting IoT Edge device: ${EDGE_DEVICE_ID:-medical-edge-device-01}"
            if az iot hub device-identity show \
                --hub-name "${IOT_HUB_NAME}" \
                --device-id "${EDGE_DEVICE_ID:-medical-edge-device-01}" &> /dev/null; then
                az iot hub device-identity delete \
                    --hub-name "${IOT_HUB_NAME}" \
                    --device-id "${EDGE_DEVICE_ID:-medical-edge-device-01}" || log "Warning: Failed to delete IoT Edge device"
                log "✅ IoT Edge device deleted"
            else
                log "IoT Edge device not found, skipping"
            fi
        fi
        
        # Delete IoT Hub
        log "Deleting IoT Hub: ${IOT_HUB_NAME}"
        if az iot hub show --name "${IOT_HUB_NAME}" &> /dev/null; then
            az iot hub delete \
                --name "${IOT_HUB_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || log "Warning: Failed to delete IoT Hub"
            log "✅ IoT Hub deleted"
        else
            log "IoT Hub not found, skipping"
        fi
    fi
    
    # Delete Log Analytics workspace
    if [[ -n "${LOG_ANALYTICS_WORKSPACE:-}" ]]; then
        log "Deleting Log Analytics workspace: ${LOG_ANALYTICS_WORKSPACE}"
        if az monitor log-analytics workspace show \
            --name "${LOG_ANALYTICS_WORKSPACE}" \
            --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az monitor log-analytics workspace delete \
                --name "${LOG_ANALYTICS_WORKSPACE}" \
                --resource-group "${RESOURCE_GROUP}" \
                --force true \
                --yes || log "Warning: Failed to delete Log Analytics workspace"
            log "✅ Log Analytics workspace deleted"
        else
            log "Log Analytics workspace not found, skipping"
        fi
    fi
    
    # Delete Storage Account (should be last as Function App depends on it)
    if [[ -n "${STORAGE_ACCOUNT:-}" ]]; then
        log "Deleting Storage Account: ${STORAGE_ACCOUNT}"
        if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            az storage account delete \
                --name "${STORAGE_ACCOUNT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes || log "Warning: Failed to delete Storage Account"
            log "✅ Storage Account deleted"
        else
            log "Storage Account not found, skipping"
        fi
    fi
}

# Function to delete the entire resource group
delete_resource_group() {
    log "Deleting resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        # First try to delete individual resources to handle dependencies
        delete_individual_resources
        
        # Wait a bit for deletions to propagate
        log "Waiting for resource deletions to complete..."
        sleep 30
        
        # Check if there are any remaining resources
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query '[].name' -o tsv 2>/dev/null || echo "")
        
        if [[ -n "${remaining_resources}" ]]; then
            log "Remaining resources found:"
            echo "${remaining_resources}" | tee -a "${LOG_FILE}"
            log "Proceeding with resource group deletion to clean up remaining resources..."
        fi
        
        # Delete the resource group
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait || {
            error "Failed to initiate resource group deletion"
            exit 1
        }
        
        log "✅ Resource group deletion initiated: ${RESOURCE_GROUP}"
        log "Note: Complete deletion may take 5-10 minutes"
        
        # Optionally wait for completion
        if [[ "${WAIT_FOR_COMPLETION:-false}" == "true" ]]; then
            log "Waiting for resource group deletion to complete..."
            while az group show --name "${RESOURCE_GROUP}" &> /dev/null; do
                log "Resource group still exists, waiting..."
                sleep 30
            done
            log "✅ Resource group deletion completed"
        fi
    else
        log "Resource group '${RESOURCE_GROUP}' does not exist, nothing to delete"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment.json"
        "edge-analytics-query.sql"
        "fhir-transform.cs"
        "edge_connection_string.txt"
        "fhir_service_url.txt"
        "workspace_id.txt"
        "workspace_key.txt"
        "deployment_info.txt"
    )
    
    for file in "${files_to_remove[@]}"; do
        local file_path="${SCRIPT_DIR}/${file}"
        if [[ -f "${file_path}" ]]; then
            rm -f "${file_path}"
            log "Removed: ${file}"
        fi
    done
    
    log "✅ Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log "Resource group still exists (deletion may be in progress)"
        
        # List any remaining resources
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "${RESOURCE_GROUP}" --query '[].{Name:name, Type:type}' -o table 2>/dev/null || echo "")
        
        if [[ -n "${remaining_resources}" ]]; then
            log "Remaining resources in ${RESOURCE_GROUP}:"
            echo "${remaining_resources}" | tee -a "${LOG_FILE}"
        else
            log "No resources found in resource group (cleanup successful)"
        fi
    else
        log "✅ Resource group successfully deleted"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "=== Cleanup Summary ==="
    log ""
    log "Resources cleaned up:"
    log "  - Resource Group: ${RESOURCE_GROUP}"
    log "  - IoT Hub and Edge Device"
    log "  - Azure Health Data Services (Workspace and FHIR Service)"
    log "  - Azure Functions and Application Insights"
    log "  - Log Analytics Workspace"
    log "  - Storage Account"
    log "  - Local configuration files"
    log ""
    log "Logs saved to:"
    log "  - ${LOG_FILE}"
    log "  - ${ERROR_LOG}"
    log ""
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log "Note: Resource group deletion may still be in progress."
        log "You can check the status in the Azure portal or run:"
        log "  az group show --name ${RESOURCE_GROUP}"
    else
        log "✅ All resources have been successfully removed."
    fi
}

# Main cleanup function
main() {
    log "Starting cleanup process..."
    
    # Extract deployment information
    extract_deployment_info
    
    # Prompt for resource group if not found
    prompt_for_resource_group
    
    # Check if running in non-interactive mode
    if [[ "${CI:-false}" == "true" ]] || [[ "${AUTOMATED:-false}" == "true" ]]; then
        log "Running in automated mode, skipping confirmations"
        CONFIRMED="y"
    else
        # Safety confirmation
        echo
        echo "⚠️  WARNING: This will permanently delete all resources in the resource group!"
        echo "Resource Group: ${RESOURCE_GROUP}"
        echo
        echo "This action cannot be undone. All data will be lost."
        echo
        read -p "Are you sure you want to continue? Type 'yes' to confirm: " CONFIRMATION
        
        if [[ "${CONFIRMATION}" != "yes" ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
        
        echo
        read -p "Last chance! Type 'DELETE' to proceed with resource deletion: " FINAL_CONFIRMATION
        
        if [[ "${FINAL_CONFIRMATION}" != "DELETE" ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
        
        CONFIRMED="y"
    fi
    
    if [[ "${CONFIRMED}" == "y" ]]; then
        check_prerequisites
        list_resources
        delete_resource_group
        cleanup_local_files
        verify_cleanup
        display_cleanup_summary
        
        log "=== Healthcare Edge Analytics Cleanup Completed ==="
    fi
}

# Handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Cleanup failed with exit code: $exit_code"
        log "Check the error log for details: ${ERROR_LOG}"
        log "You may need to manually clean up remaining resources in the Azure portal"
    fi
}

trap cleanup_on_exit EXIT

# Execute main function
main "$@"