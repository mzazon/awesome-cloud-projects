#!/bin/bash

###################################################################################
# Azure Smart Factory Carbon Footprint Monitoring - Cleanup Script
#
# This script safely removes all Azure resources created by the deployment script
# for the smart factory carbon footprint monitoring solution.
#
# Resources to be removed:
# - Azure Data Explorer cluster
# - Azure Functions App
# - Azure Event Grid topic and subscriptions
# - Azure IoT Hub and devices
# - Event Hub namespace and hubs
# - Azure Storage Account
# - Resource Group (optional)
#
# Prerequisites:
# - Azure CLI v2.57.0 or later
# - Appropriate Azure subscription permissions
# - deployment_info.txt file (created by deploy.sh)
#
# Usage: ./destroy.sh [--force] [--keep-resource-group] [--resource-group <name>]
###################################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment_info.txt"
FORCE_DELETE=false
KEEP_RESOURCE_GROUP=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###################################################################################
# Utility Functions
###################################################################################

log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} - ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

error_exit() {
    log_error "$1"
    exit 1
}

confirm_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [ "${FORCE_DELETE}" = true ]; then
        return 0
    fi
    
    echo
    echo -e "${YELLOW}⚠️  WARNING: About to delete ${resource_type}: ${resource_name}${NC}"
    echo -e "${RED}This action cannot be undone!${NC}"
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deletion cancelled by user"
        return 1
    fi
    
    return 0
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI installation
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI v2.57.0 or later."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    log_info "Using Azure subscription: ${subscription_name} (${subscription_id})"
    
    log_success "Prerequisites check completed"
}

load_deployment_info() {
    local resource_group="$1"
    
    if [[ -n "${resource_group}" ]]; then
        log_info "Using provided resource group: ${resource_group}"
        RESOURCE_GROUP="${resource_group}"
        return 0
    fi
    
    if [[ ! -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        log_warning "Deployment info file not found: ${DEPLOYMENT_INFO_FILE}"
        log_warning "You can specify --resource-group to proceed with manual cleanup"
        return 1
    fi
    
    log_info "Loading deployment information from ${DEPLOYMENT_INFO_FILE}"
    source "${DEPLOYMENT_INFO_FILE}"
    
    log_info "Loaded deployment information:"
    log_info "  Resource Group: ${RESOURCE_GROUP:-unknown}"
    log_info "  IoT Hub: ${IOT_HUB_NAME:-unknown}"
    log_info "  Function App: ${FUNCTION_APP_NAME:-unknown}"
    log_info "  Data Explorer Cluster: ${DATA_EXPLORER_CLUSTER:-unknown}"
    log_info "  Event Grid Topic: ${EVENT_GRID_TOPIC:-unknown}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME:-unknown}"
    log_info "  Event Hub Namespace: ${EVENTHUB_NAMESPACE:-unknown}"
    log_info "  Deployment Date: ${DEPLOYMENT_DATE:-unknown}"
    
    return 0
}

wait_for_deletion() {
    local resource_type="$1"
    local check_command="$2"
    local max_wait_minutes="${3:-10}"
    
    log_info "Waiting for ${resource_type} deletion to complete..."
    
    local max_attempts=$((max_wait_minutes * 6))  # 10 second intervals
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if ! eval "${check_command}" &> /dev/null; then
            log_success "${resource_type} deletion completed"
            return 0
        fi
        
        attempt=$((attempt + 1))
        log_info "Still deleting ${resource_type}... (${attempt}/${max_attempts})"
        sleep 10
    done
    
    log_warning "${resource_type} deletion is taking longer than expected"
    return 1
}

###################################################################################
# Resource Deletion Functions
###################################################################################

delete_function_app() {
    local function_app_name="$1"
    local resource_group="$2"
    
    log_info "Checking for Function App: ${function_app_name}"
    
    if ! az functionapp show --name "${function_app_name}" --resource-group "${resource_group}" &> /dev/null; then
        log_warning "Function App ${function_app_name} not found or already deleted"
        return 0
    fi
    
    if ! confirm_deletion "Function App" "${function_app_name}"; then
        return 0
    fi
    
    log_info "Deleting Function App: ${function_app_name}"
    az functionapp delete \
        --name "${function_app_name}" \
        --resource-group "${resource_group}" || log_error "Failed to delete Function App ${function_app_name}"
    
    log_success "Function App deletion initiated: ${function_app_name}"
}

delete_iot_hub() {
    local iot_hub_name="$1"
    local resource_group="$2"
    
    log_info "Checking for IoT Hub: ${iot_hub_name}"
    
    if ! az iot hub show --name "${iot_hub_name}" --resource-group "${resource_group}" &> /dev/null; then
        log_warning "IoT Hub ${iot_hub_name} not found or already deleted"
        return 0
    fi
    
    if ! confirm_deletion "IoT Hub" "${iot_hub_name}"; then
        return 0
    fi
    
    # List and delete IoT devices first
    log_info "Listing IoT devices in hub ${iot_hub_name}..."
    local devices=$(az iot hub device-identity list --hub-name "${iot_hub_name}" --resource-group "${resource_group}" --query "[].deviceId" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${devices}" ]]; then
        log_info "Found IoT devices, deleting them first..."
        while IFS= read -r device_id; do
            if [[ -n "${device_id}" ]]; then
                log_info "Deleting IoT device: ${device_id}"
                az iot hub device-identity delete \
                    --hub-name "${iot_hub_name}" \
                    --device-id "${device_id}" \
                    --resource-group "${resource_group}" || log_warning "Failed to delete device ${device_id}"
            fi
        done <<< "${devices}"
    fi
    
    log_info "Deleting IoT Hub: ${iot_hub_name}"
    az iot hub delete \
        --name "${iot_hub_name}" \
        --resource-group "${resource_group}" || log_error "Failed to delete IoT Hub ${iot_hub_name}"
    
    log_success "IoT Hub deletion initiated: ${iot_hub_name}"
}

delete_event_grid() {
    local topic_name="$1"
    local resource_group="$2"
    
    log_info "Checking for Event Grid topic: ${topic_name}"
    
    if ! az eventgrid topic show --name "${topic_name}" --resource-group "${resource_group}" &> /dev/null; then
        log_warning "Event Grid topic ${topic_name} not found or already deleted"
        return 0
    fi
    
    if ! confirm_deletion "Event Grid Topic" "${topic_name}"; then
        return 0
    fi
    
    # List and delete event subscriptions first
    log_info "Checking for Event Grid subscriptions..."
    local subscriptions=$(az eventgrid event-subscription list --source-resource-id "/subscriptions/$(az account show --query id --output tsv)/resourceGroups/${resource_group}/providers/Microsoft.EventGrid/topics/${topic_name}" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${subscriptions}" ]]; then
        log_info "Found Event Grid subscriptions, deleting them first..."
        while IFS= read -r subscription_name; do
            if [[ -n "${subscription_name}" ]]; then
                log_info "Deleting Event Grid subscription: ${subscription_name}"
                az eventgrid event-subscription delete \
                    --name "${subscription_name}" \
                    --source-resource-id "/subscriptions/$(az account show --query id --output tsv)/resourceGroups/${resource_group}/providers/Microsoft.EventGrid/topics/${topic_name}" || log_warning "Failed to delete subscription ${subscription_name}"
            fi
        done <<< "${subscriptions}"
    fi
    
    log_info "Deleting Event Grid topic: ${topic_name}"
    az eventgrid topic delete \
        --name "${topic_name}" \
        --resource-group "${resource_group}" || log_error "Failed to delete Event Grid topic ${topic_name}"
    
    log_success "Event Grid topic deleted: ${topic_name}"
}

delete_data_explorer() {
    local cluster_name="$1"
    local resource_group="$2"
    
    log_info "Checking for Data Explorer cluster: ${cluster_name}"
    
    if ! az kusto cluster show --cluster-name "${cluster_name}" --resource-group "${resource_group}" &> /dev/null; then
        log_warning "Data Explorer cluster ${cluster_name} not found or already deleted"
        return 0
    fi
    
    if ! confirm_deletion "Data Explorer Cluster" "${cluster_name}"; then
        return 0
    fi
    
    log_warning "Data Explorer cluster deletion may take 10-15 minutes..."
    log_info "Deleting Data Explorer cluster: ${cluster_name}"
    az kusto cluster delete \
        --cluster-name "${cluster_name}" \
        --resource-group "${resource_group}" \
        --yes || log_error "Failed to delete Data Explorer cluster ${cluster_name}"
    
    log_success "Data Explorer cluster deletion initiated: ${cluster_name}"
    
    # Wait for deletion to complete
    wait_for_deletion "Data Explorer cluster" "az kusto cluster show --cluster-name ${cluster_name} --resource-group ${resource_group}" 15
}

delete_event_hub() {
    local namespace_name="$1"
    local resource_group="$2"
    
    log_info "Checking for Event Hub namespace: ${namespace_name}"
    
    if ! az eventhubs namespace show --name "${namespace_name}" --resource-group "${resource_group}" &> /dev/null; then
        log_warning "Event Hub namespace ${namespace_name} not found or already deleted"
        return 0
    fi
    
    if ! confirm_deletion "Event Hub Namespace" "${namespace_name}"; then
        return 0
    fi
    
    # List and delete event hubs first
    log_info "Checking for Event Hubs in namespace ${namespace_name}..."
    local event_hubs=$(az eventhubs eventhub list --namespace-name "${namespace_name}" --resource-group "${resource_group}" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "${event_hubs}" ]]; then
        log_info "Found Event Hubs, deleting them first..."
        while IFS= read -r hub_name; do
            if [[ -n "${hub_name}" ]]; then
                log_info "Deleting Event Hub: ${hub_name}"
                az eventhubs eventhub delete \
                    --name "${hub_name}" \
                    --namespace-name "${namespace_name}" \
                    --resource-group "${resource_group}" || log_warning "Failed to delete Event Hub ${hub_name}"
            fi
        done <<< "${event_hubs}"
    fi
    
    log_info "Deleting Event Hub namespace: ${namespace_name}"
    az eventhubs namespace delete \
        --name "${namespace_name}" \
        --resource-group "${resource_group}" || log_error "Failed to delete Event Hub namespace ${namespace_name}"
    
    log_success "Event Hub namespace deletion initiated: ${namespace_name}"
}

delete_storage_account() {
    local storage_account_name="$1"
    local resource_group="$2"
    
    log_info "Checking for Storage Account: ${storage_account_name}"
    
    if ! az storage account show --name "${storage_account_name}" --resource-group "${resource_group}" &> /dev/null; then
        log_warning "Storage Account ${storage_account_name} not found or already deleted"
        return 0
    fi
    
    if ! confirm_deletion "Storage Account" "${storage_account_name}"; then
        return 0
    fi
    
    log_info "Deleting Storage Account: ${storage_account_name}"
    az storage account delete \
        --name "${storage_account_name}" \
        --resource-group "${resource_group}" \
        --yes || log_error "Failed to delete Storage Account ${storage_account_name}"
    
    log_success "Storage Account deleted: ${storage_account_name}"
}

delete_resource_group() {
    local resource_group="$1"
    
    log_info "Checking for Resource Group: ${resource_group}"
    
    if ! az group show --name "${resource_group}" &> /dev/null; then
        log_warning "Resource Group ${resource_group} not found or already deleted"
        return 0
    fi
    
    if ! confirm_deletion "Resource Group" "${resource_group}"; then
        return 0
    fi
    
    log_warning "This will delete ALL resources in the resource group!"
    log_warning "Resource group deletion may take 10-20 minutes..."
    
    if [ "${FORCE_DELETE}" = false ]; then
        echo
        echo -e "${RED}FINAL CONFIRMATION:${NC}"
        echo -e "${RED}This will permanently delete the entire resource group and all its contents!${NC}"
        read -p "Type 'DELETE' to confirm: " -r
        echo
        
        if [[ "${REPLY}" != "DELETE" ]]; then
            log_info "Resource group deletion cancelled by user"
            return 0
        fi
    fi
    
    log_info "Deleting Resource Group: ${resource_group}"
    az group delete \
        --name "${resource_group}" \
        --yes \
        --no-wait || log_error "Failed to initiate Resource Group deletion ${resource_group}"
    
    log_success "Resource Group deletion initiated: ${resource_group}"
    log_info "Note: Complete deletion may take 10-20 minutes"
}

list_remaining_resources() {
    local resource_group="$1"
    
    log_info "Checking for remaining resources in ${resource_group}..."
    
    if ! az group show --name "${resource_group}" &> /dev/null; then
        log_info "Resource group ${resource_group} no longer exists"
        return 0
    fi
    
    local remaining_resources=$(az resource list --resource-group "${resource_group}" --query "[].{Name:name,Type:type}" -o table)
    
    if [[ -n "${remaining_resources}" ]]; then
        log_warning "Remaining resources found in ${resource_group}:"
        echo "${remaining_resources}"
    else
        log_success "No remaining resources found in ${resource_group}"
    fi
}

###################################################################################
# Main Cleanup Function
###################################################################################

main() {
    local resource_group_override="$1"
    
    log_info "Starting Azure Smart Factory Carbon Footprint Monitoring cleanup"
    log_info "Force delete: ${FORCE_DELETE}"
    log_info "Keep resource group: ${KEEP_RESOURCE_GROUP}"
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment information
    if ! load_deployment_info "${resource_group_override}"; then
        if [[ -z "${resource_group_override}" ]]; then
            error_exit "Cannot proceed without deployment information or resource group override"
        fi
        log_warning "Proceeding with manual cleanup for resource group: ${resource_group_override}"
        RESOURCE_GROUP="${resource_group_override}"
    fi
    
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        error_exit "Resource group not specified"
    fi
    
    # Verify resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        error_exit "Resource group ${RESOURCE_GROUP} not found"
    fi
    
    log_info "Proceeding with cleanup of resource group: ${RESOURCE_GROUP}"
    
    # Show resources that will be deleted
    log_info "Resources in ${RESOURCE_GROUP}:"
    az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name,Type:type}" -o table || log_warning "Could not list resources"
    
    # Delete resources in reverse order of dependencies
    # 1. Function App (depends on storage)
    if [[ -n "${FUNCTION_APP_NAME:-}" ]]; then
        delete_function_app "${FUNCTION_APP_NAME}" "${RESOURCE_GROUP}"
    else
        log_info "Skipping Function App deletion - name not available"
    fi
    
    # 2. Event Grid (has subscriptions that might reference other resources)
    if [[ -n "${EVENT_GRID_TOPIC:-}" ]]; then
        delete_event_grid "${EVENT_GRID_TOPIC}" "${RESOURCE_GROUP}"
    else
        log_info "Skipping Event Grid deletion - name not available"
    fi
    
    # 3. Data Explorer (independent, but takes time)
    if [[ -n "${DATA_EXPLORER_CLUSTER:-}" ]]; then
        delete_data_explorer "${DATA_EXPLORER_CLUSTER}" "${RESOURCE_GROUP}"
    else
        log_info "Skipping Data Explorer deletion - name not available"
    fi
    
    # 4. IoT Hub (has devices)
    if [[ -n "${IOT_HUB_NAME:-}" ]]; then
        delete_iot_hub "${IOT_HUB_NAME}" "${RESOURCE_GROUP}"
    else
        log_info "Skipping IoT Hub deletion - name not available"
    fi
    
    # 5. Event Hub namespace
    if [[ -n "${EVENTHUB_NAMESPACE:-}" ]]; then
        delete_event_hub "${EVENTHUB_NAMESPACE}" "${RESOURCE_GROUP}"
    else
        log_info "Skipping Event Hub deletion - name not available"
    fi
    
    # 6. Storage Account (should be last before resource group)
    if [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]]; then
        delete_storage_account "${STORAGE_ACCOUNT_NAME}" "${RESOURCE_GROUP}"
    else
        log_info "Skipping Storage Account deletion - name not available"
    fi
    
    # Wait a bit for deletions to propagate
    log_info "Waiting for resource deletions to propagate..."
    sleep 30
    
    # Check for remaining resources
    list_remaining_resources "${RESOURCE_GROUP}"
    
    # 7. Resource Group (if requested)
    if [ "${KEEP_RESOURCE_GROUP}" = false ]; then
        delete_resource_group "${RESOURCE_GROUP}"
    else
        log_info "Keeping resource group as requested: ${RESOURCE_GROUP}"
    fi
    
    # Clean up deployment info file
    if [[ -f "${DEPLOYMENT_INFO_FILE}" ]] && [ "${FORCE_DELETE}" = true ]; then
        log_info "Removing deployment info file"
        rm -f "${DEPLOYMENT_INFO_FILE}"
    fi
    
    # Display cleanup summary
    log_success "Cleanup process completed!"
    echo
    echo "==================================================================="
    echo "                    CLEANUP SUMMARY"
    echo "==================================================================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo
    if [ "${KEEP_RESOURCE_GROUP}" = false ]; then
        echo "Status: Resource group deletion initiated"
        echo "Note: Complete cleanup may take 10-20 minutes"
    else
        echo "Status: Individual resources deleted, resource group preserved"
    fi
    echo
    echo "Cleanup Actions Performed:"
    echo "  ✅ Function App deleted"
    echo "  ✅ Event Grid topic deleted"
    echo "  ✅ Data Explorer cluster deletion initiated"
    echo "  ✅ IoT Hub and devices deleted"
    echo "  ✅ Event Hub namespace deleted"
    echo "  ✅ Storage Account deleted"
    if [ "${KEEP_RESOURCE_GROUP}" = false ]; then
        echo "  ✅ Resource Group deletion initiated"
    else
        echo "  ⏭️  Resource Group preserved"
    fi
    echo
    echo "Important Notes:"
    echo "  ⚠️  Some deletions may still be in progress"
    echo "  ⚠️  Monitor Azure portal for completion status"
    echo "  ⚠️  Verify no unexpected charges continue to accrue"
    echo "==================================================================="
}

###################################################################################
# Script Entry Point
###################################################################################

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Clean up Azure Smart Factory Carbon Footprint Monitoring infrastructure"
    echo
    echo "Options:"
    echo "  --force                    Skip confirmation prompts"
    echo "  --keep-resource-group      Delete resources but keep the resource group"
    echo "  --resource-group NAME      Override resource group from deployment info"
    echo "  --help                     Show this help message"
    echo
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup using deployment info"
    echo "  $0 --force                           # Automatic cleanup with no prompts"
    echo "  $0 --keep-resource-group             # Delete resources but keep resource group"
    echo "  $0 --resource-group my-rg            # Clean up specific resource group"
    echo "  $0 --force --resource-group my-rg    # Force cleanup of specific resource group"
    echo
    echo "Notes:"
    echo "  - This script looks for deployment_info.txt created by deploy.sh"
    echo "  - Use --resource-group to specify a different resource group"
    echo "  - Resource group deletion can take 10-20 minutes to complete"
    echo "  - Some resources may take additional time to fully delete"
}

# Initialize log file
echo "==================================================================" > "${LOG_FILE}"
echo "Azure Smart Factory Carbon Footprint Monitoring - Cleanup Log" >> "${LOG_FILE}"
echo "Start Time: $(date '+%Y-%m-%d %H:%M:%S')" >> "${LOG_FILE}"
echo "==================================================================" >> "${LOG_FILE}"

# Parse command line arguments
RESOURCE_GROUP_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --keep-resource-group)
            KEEP_RESOURCE_GROUP=true
            shift
            ;;
        --resource-group)
            RESOURCE_GROUP_OVERRIDE="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Show warning about destructive action
if [ "${FORCE_DELETE}" = false ]; then
    echo
    echo -e "${RED}⚠️  WARNING: This script will delete Azure resources!${NC}"
    echo -e "${YELLOW}This action cannot be undone and may result in data loss.${NC}"
    echo
    echo "Resources that will be deleted:"
    echo "  • Function Apps and their code"
    echo "  • IoT Hub and all connected devices"
    echo "  • Event Grid topics and subscriptions"
    echo "  • Data Explorer clusters and databases"
    echo "  • Event Hub namespaces and hubs"
    echo "  • Storage Accounts and all data"
    if [ "${KEEP_RESOURCE_GROUP}" = false ]; then
        echo "  • Resource Group and ALL contained resources"
    fi
    echo
    read -p "Do you want to continue? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
fi

# Run main cleanup
main "${RESOURCE_GROUP_OVERRIDE}"