#!/bin/bash

# Multi-Agent AI Orchestration with Azure AI Foundry Agent Service and Container Apps
# Cleanup Script - Safely removes all resources created by the deployment
# Author: Generated from Azure Recipe
# Version: 1.0

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
CONFIG_FILE="${SCRIPT_DIR}/deployment_config.env"

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "${ERROR_LOG}" >&2
}

# Error handling
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "Script failed at line ${line_number} with exit code ${exit_code}"
    log_error "Check ${ERROR_LOG} for details"
    exit "${exit_code}"
}

trap 'handle_error $? $LINENO' ERR

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Please log in to Azure CLI first using 'az login'"
        exit 1
    fi
    
    # Check if configuration file exists
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
        log_error "Please ensure the deployment was successful or provide resource group name manually"
        exit 1
    fi
    
    log "✅ Prerequisites check passed"
}

# Load configuration
load_configuration() {
    log "Loading deployment configuration..."
    
    # Source the configuration file
    source "${CONFIG_FILE}"
    
    # Validate required variables
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        log_error "RESOURCE_GROUP not found in configuration"
        exit 1
    fi
    
    if [[ -z "${SUBSCRIPTION_ID}" ]]; then
        export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    fi
    
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Subscription ID: ${SUBSCRIPTION_ID}"
    
    # Check if resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Resource group ${RESOURCE_GROUP} does not exist"
        exit 1
    fi
    
    log "✅ Configuration loaded successfully"
}

# Confirmation prompt
confirm_destruction() {
    log "=============================================="
    log "WARNING: This will permanently delete all resources"
    log "=============================================="
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Location: ${LOCATION:-Unknown}"
    log "Container Apps Environment: ${CONTAINER_ENVIRONMENT:-Unknown}"
    log "Event Grid Topic: ${EVENT_GRID_TOPIC:-Unknown}"
    log "AI Foundry Resource: ${AI_FOUNDRY_RESOURCE:-Unknown}"
    log "Storage Account: ${STORAGE_ACCOUNT:-Unknown}"
    log "Cosmos DB Account: ${COSMOS_ACCOUNT:-Unknown}"
    log "=============================================="
    log ""
    
    if [[ "${FORCE_DESTROY:-false}" != "true" ]]; then
        read -p "Are you sure you want to delete all resources? (Type 'yes' to confirm): " confirmation
        if [[ "${confirmation}" != "yes" ]]; then
            log "Destruction cancelled by user"
            exit 0
        fi
    fi
    
    log "Proceeding with resource destruction..."
}

# Stop Container Apps
stop_container_apps() {
    log "Stopping all container apps..."
    
    # Get list of container apps in the resource group
    local container_apps=$(az containerapp list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${container_apps}" ]]; then
        log "Found container apps: ${container_apps}"
        
        # Stop each container app by setting replicas to 0
        for app in ${container_apps}; do
            log "Stopping container app: ${app}"
            az containerapp update \
                --name "${app}" \
                --resource-group "${RESOURCE_GROUP}" \
                --min-replicas 0 \
                --max-replicas 0 \
                --output none 2>/dev/null || log_error "Failed to stop ${app}"
        done
        
        log "Waiting for container apps to scale down..."
        sleep 30
    else
        log "No container apps found in resource group"
    fi
    
    log "✅ Container apps stopped successfully"
}

# Delete Event Grid subscriptions
delete_event_subscriptions() {
    log "Deleting Event Grid subscriptions..."
    
    if [[ -n "${EVENT_GRID_TOPIC}" ]]; then
        local topic_resource_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventGrid/topics/${EVENT_GRID_TOPIC}"
        
        # List of subscriptions to delete
        local subscriptions=(
            "document-agent-subscription"
            "data-analysis-subscription"
            "customer-service-subscription"
            "workflow-orchestration"
            "agent-health-monitoring"
        )
        
        for subscription in "${subscriptions[@]}"; do
            log "Deleting Event Grid subscription: ${subscription}"
            az eventgrid event-subscription delete \
                --name "${subscription}" \
                --source-resource-id "${topic_resource_id}" \
                --output none 2>/dev/null || log "Event Grid subscription ${subscription} not found or already deleted"
        done
    else
        log "No Event Grid topic configuration found"
    fi
    
    log "✅ Event Grid subscriptions deleted"
}

# Delete Container Apps
delete_container_apps() {
    log "Deleting container apps..."
    
    local container_apps=$(az containerapp list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "${container_apps}" ]]; then
        for app in ${container_apps}; do
            log "Deleting container app: ${app}"
            az containerapp delete \
                --name "${app}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none 2>/dev/null || log_error "Failed to delete ${app}"
        done
    else
        log "No container apps found to delete"
    fi
    
    log "✅ Container apps deleted"
}

# Delete Container Apps Environment
delete_container_environment() {
    log "Deleting Container Apps Environment..."
    
    if [[ -n "${CONTAINER_ENVIRONMENT}" ]]; then
        log "Deleting Container Apps Environment: ${CONTAINER_ENVIRONMENT}"
        az containerapp env delete \
            --name "${CONTAINER_ENVIRONMENT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none 2>/dev/null || log "Container Apps Environment ${CONTAINER_ENVIRONMENT} not found or already deleted"
    else
        log "No Container Apps Environment configuration found"
    fi
    
    log "✅ Container Apps Environment deleted"
}

# Delete AI model deployments
delete_ai_deployments() {
    log "Deleting AI model deployments..."
    
    if [[ -n "${AI_FOUNDRY_RESOURCE}" ]]; then
        # List and delete all deployments
        local deployments=$(az cognitiveservices account deployment list \
            --name "${AI_FOUNDRY_RESOURCE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[].name" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "${deployments}" ]]; then
            for deployment in ${deployments}; do
                log "Deleting AI model deployment: ${deployment}"
                az cognitiveservices account deployment delete \
                    --name "${AI_FOUNDRY_RESOURCE}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --deployment-name "${deployment}" \
                    --output none 2>/dev/null || log_error "Failed to delete deployment ${deployment}"
            done
        else
            log "No AI model deployments found"
        fi
    else
        log "No AI Foundry resource configuration found"
    fi
    
    log "✅ AI model deployments deleted"
}

# Delete individual resources (if full resource group deletion is not desired)
delete_individual_resources() {
    log "Deleting individual resources..."
    
    # Delete Application Insights alerts
    if [[ -n "${RESOURCE_GROUP}" ]]; then
        log "Deleting metric alerts..."
        local alerts=$(az monitor metrics alert list \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[].name" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "${alerts}" ]]; then
            for alert in ${alerts}; do
                log "Deleting metric alert: ${alert}"
                az monitor metrics alert delete \
                    --name "${alert}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --output none 2>/dev/null || log_error "Failed to delete alert ${alert}"
            done
        fi
    fi
    
    # Delete Log Analytics workspace
    log "Deleting Log Analytics workspace..."
    az monitor log-analytics workspace delete \
        --workspace-name "multi-agent-logs" \
        --resource-group "${RESOURCE_GROUP}" \
        --force true \
        --yes \
        --output none 2>/dev/null || log "Log Analytics workspace not found or already deleted"
    
    # Delete storage containers
    if [[ -n "${STORAGE_ACCOUNT}" ]]; then
        log "Deleting storage containers..."
        az storage container delete \
            --name "deadletter-events" \
            --account-name "${STORAGE_ACCOUNT}" \
            --output none 2>/dev/null || log "Storage container not found or already deleted"
    fi
    
    # Delete Machine Learning workspace
    if [[ -n "${ML_WORKSPACE_NAME}" ]]; then
        log "Deleting Machine Learning workspace..."
        az ml workspace delete \
            --name "${ML_WORKSPACE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none 2>/dev/null || log "ML workspace not found or already deleted"
    fi
    
    log "✅ Individual resources deleted"
}

# Delete entire resource group
delete_resource_group() {
    log "Deleting entire resource group: ${RESOURCE_GROUP}"
    
    # Final confirmation for resource group deletion
    if [[ "${FORCE_DESTROY:-false}" != "true" ]]; then
        read -p "This will delete the entire resource group and ALL resources within it. Continue? (Type 'DELETE' to confirm): " final_confirmation
        if [[ "${final_confirmation}" != "DELETE" ]]; then
            log "Resource group deletion cancelled by user"
            log "Resources may still be running and incurring charges"
            return 0
        fi
    fi
    
    # Delete the resource group (this will delete all resources within it)
    log "Initiating resource group deletion..."
    az group delete \
        --name "${RESOURCE_GROUP}" \
        --yes \
        --no-wait \
        --output none
    
    log "✅ Resource group deletion initiated"
    log "Note: Complete deletion may take 10-15 minutes"
    
    # Wait briefly and check if deletion started
    sleep 5
    local exists=$(az group exists --name "${RESOURCE_GROUP}")
    if [[ "${exists}" == "false" ]]; then
        log "✅ Resource group deleted successfully"
    else
        log "Resource group deletion is in progress..."
        log "You can check status with: az group show --name ${RESOURCE_GROUP}"
    fi
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check if resource group still exists
    if az group exists --name "${RESOURCE_GROUP}"; then
        log "Resource group still exists (deletion may be in progress)"
        
        # List remaining resources
        local remaining_resources=$(az resource list \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[].{Name:name,Type:type}" \
            --output table 2>/dev/null || echo "")
        
        if [[ -n "${remaining_resources}" ]]; then
            log "Remaining resources:"
            log "${remaining_resources}"
        else
            log "No remaining resources found"
        fi
    else
        log "✅ Resource group has been deleted"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove configuration file
    if [[ -f "${CONFIG_FILE}" ]]; then
        rm -f "${CONFIG_FILE}"
        log "Removed configuration file: ${CONFIG_FILE}"
    fi
    
    # Remove any temporary files
    if [[ -f "${SCRIPT_DIR}/.deploy_temp" ]]; then
        rm -f "${SCRIPT_DIR}/.deploy_temp"
        log "Removed temporary files"
    fi
    
    log "✅ Local files cleaned up"
}

# Show cleanup summary
show_cleanup_summary() {
    log "=============================================="
    log "Multi-Agent AI Orchestration Cleanup Complete"
    log "=============================================="
    log ""
    log "Cleanup completed at: $(date)"
    log "Total cleanup time: $SECONDS seconds"
    log ""
    log "Actions performed:"
    log "  ✅ Stopped all container apps"
    log "  ✅ Deleted Event Grid subscriptions"
    log "  ✅ Deleted container apps"
    log "  ✅ Deleted Container Apps Environment"
    log "  ✅ Deleted AI model deployments"
    log "  ✅ Deleted individual resources"
    log "  ✅ Deleted resource group: ${RESOURCE_GROUP}"
    log "  ✅ Cleaned up local configuration files"
    log ""
    log "If resource group deletion is still in progress, you can check status with:"
    log "  az group show --name ${RESOURCE_GROUP}"
    log ""
    log "All resources should be deleted and no further charges should be incurred."
    log "=============================================="
}

# Main execution flow
main() {
    log "Starting Multi-Agent AI Orchestration cleanup..."
    log "Cleanup started at: $(date)"
    
    # Check for command line arguments
    if [[ "$1" == "--force" ]]; then
        export FORCE_DESTROY=true
        log "Running in force mode - skipping confirmations"
    fi
    
    if [[ "$1" == "--individual-only" ]]; then
        export INDIVIDUAL_ONLY=true
        log "Running in individual-only mode - will not delete resource group"
    fi
    
    check_prerequisites
    load_configuration
    confirm_destruction
    
    # If individual-only mode, just delete specific resources
    if [[ "${INDIVIDUAL_ONLY:-false}" == "true" ]]; then
        stop_container_apps
        delete_event_subscriptions
        delete_container_apps
        delete_container_environment
        delete_ai_deployments
        delete_individual_resources
        verify_cleanup
    else
        # Full cleanup including resource group deletion
        stop_container_apps
        delete_event_subscriptions
        delete_ai_deployments
        delete_resource_group
        verify_cleanup
    fi
    
    cleanup_local_files
    show_cleanup_summary
    
    log "Cleanup completed successfully at: $(date)"
}

# Display usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "OPTIONS:"
    echo "  --force           Skip confirmation prompts"
    echo "  --individual-only Delete individual resources but keep resource group"
    echo "  --help           Show this help message"
    echo ""
    echo "This script will delete all resources created by the deployment script."
    echo "Make sure you have the deployment_config.env file in the same directory."
}

# Handle command line arguments
if [[ "$1" == "--help" ]]; then
    usage
    exit 0
fi

# Run main function
main "$@"