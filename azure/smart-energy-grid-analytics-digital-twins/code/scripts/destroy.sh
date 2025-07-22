#!/bin/bash

# =============================================================================
# Destroy Script for Intelligent Energy Grid Analytics
# Azure Data Manager for Energy + Azure Digital Twins
# =============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
readonly CONFIG_FILE="${SCRIPT_DIR}/deployment-config.env"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warn() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

cleanup_on_error() {
    log_error "Destruction failed. Check ${LOG_FILE} for details."
    log_warn "Some resources may still exist and require manual cleanup."
    exit 1
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if configuration file exists
    if [ ! -f "${CONFIG_FILE}" ]; then
        log_error "Deployment configuration file not found: ${CONFIG_FILE}"
        log_error "Please ensure you have run the deploy.sh script first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

load_configuration() {
    log_info "Loading deployment configuration..."
    
    # Source the configuration file
    source "${CONFIG_FILE}"
    
    # Validate required variables
    local required_vars=(
        "RESOURCE_GROUP"
        "ENERGY_DATA_MANAGER"
        "DIGITAL_TWINS_INSTANCE"
        "TIME_SERIES_INSIGHTS"
        "AI_SERVICES_ACCOUNT"
        "STORAGE_ACCOUNT"
        "IOT_HUB"
        "FUNCTION_APP_NAME"
        "EVENTGRID_TOPIC"
        "LOG_WORKSPACE"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_error "Required variable ${var} is not set in configuration file."
            exit 1
        fi
    done
    
    log_success "Configuration loaded successfully"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Subscription ID: ${SUBSCRIPTION_ID}"
}

confirm_destruction() {
    log_warn "⚠️  WARNING: This will permanently delete all resources in the following resource group:"
    log_warn "Resource Group: ${RESOURCE_GROUP}"
    log_warn "Location: ${LOCATION}"
    echo ""
    log_warn "The following resources will be deleted:"
    log_warn "- Azure Data Manager for Energy: ${ENERGY_DATA_MANAGER}"
    log_warn "- Azure Digital Twins: ${DIGITAL_TWINS_INSTANCE}"
    log_warn "- Time Series Insights: ${TIME_SERIES_INSIGHTS}"
    log_warn "- AI Services Account: ${AI_SERVICES_ACCOUNT}"
    log_warn "- Storage Account: ${STORAGE_ACCOUNT}"
    log_warn "- IoT Hub: ${IOT_HUB}"
    log_warn "- Function App: ${FUNCTION_APP_NAME}"
    log_warn "- Event Grid Topic: ${EVENTGRID_TOPIC}"
    log_warn "- Log Analytics Workspace: ${LOG_WORKSPACE}"
    echo ""
    
    if [ "${FORCE_DESTROY:-false}" == "true" ]; then
        log_info "Force destroy mode enabled, skipping confirmation."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
    
    log_info "Destruction confirmed. Proceeding with cleanup..."
}

wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    local timeout_minutes="${4:-10}"
    
    log_info "Waiting for ${resource_type} '${resource_name}' to be deleted (timeout: ${timeout_minutes} minutes)..."
    
    local end_time=$(($(date +%s) + timeout_minutes * 60))
    while [ $(date +%s) -lt $end_time ]; do
        if ! az resource show --name "${resource_name}" --resource-group "${resource_group}" &> /dev/null; then
            log_success "${resource_type} '${resource_name}' successfully deleted"
            return 0
        fi
        sleep 30
        echo -n "."
    done
    echo ""
    
    log_warn "${resource_type} '${resource_name}' deletion timed out"
    return 1
}

# =============================================================================
# DESTRUCTION FUNCTIONS
# =============================================================================

delete_event_grid_and_function_app() {
    log_info "Removing Event Grid and Function App resources..."
    
    # Delete Function App
    if az functionapp show --resource-group "${RESOURCE_GROUP}" --name "${FUNCTION_APP_NAME}" &> /dev/null; then
        log_info "Deleting Function App: ${FUNCTION_APP_NAME}"
        az functionapp delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${FUNCTION_APP_NAME}" \
            --yes \
            --output none
        log_success "Function App deleted"
    else
        log_warn "Function App '${FUNCTION_APP_NAME}' not found, skipping"
    fi
    
    # Delete Event Grid topic
    if az eventgrid topic show --resource-group "${RESOURCE_GROUP}" --name "${EVENTGRID_TOPIC}" &> /dev/null; then
        log_info "Deleting Event Grid topic: ${EVENTGRID_TOPIC}"
        az eventgrid topic delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${EVENTGRID_TOPIC}" \
            --yes \
            --output none
        log_success "Event Grid topic deleted"
    else
        log_warn "Event Grid topic '${EVENTGRID_TOPIC}' not found, skipping"
    fi
    
    log_success "Integration components cleaned up"
}

delete_ai_services_and_storage() {
    log_info "Removing AI Services and storage resources..."
    
    # Delete AI Services account
    if az cognitiveservices account show --resource-group "${RESOURCE_GROUP}" --name "${AI_SERVICES_ACCOUNT}" &> /dev/null; then
        log_info "Deleting AI Services account: ${AI_SERVICES_ACCOUNT}"
        az cognitiveservices account delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${AI_SERVICES_ACCOUNT}" \
            --yes \
            --output none
        log_success "AI Services account deleted"
    else
        log_warn "AI Services account '${AI_SERVICES_ACCOUNT}' not found, skipping"
    fi
    
    # Delete storage account
    if az storage account show --resource-group "${RESOURCE_GROUP}" --name "${STORAGE_ACCOUNT}" &> /dev/null; then
        log_info "Deleting storage account: ${STORAGE_ACCOUNT}"
        az storage account delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${STORAGE_ACCOUNT}" \
            --yes \
            --output none
        log_success "Storage account deleted"
    else
        log_warn "Storage account '${STORAGE_ACCOUNT}' not found, skipping"
    fi
    
    log_success "AI and storage resources cleaned up"
}

delete_time_series_insights_and_iot_hub() {
    log_info "Removing Time Series Insights and IoT Hub..."
    
    # Delete Time Series Insights environment
    if az tsi environment show --resource-group "${RESOURCE_GROUP}" --name "${TIME_SERIES_INSIGHTS}" &> /dev/null; then
        log_info "Deleting Time Series Insights environment: ${TIME_SERIES_INSIGHTS}"
        az tsi environment delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${TIME_SERIES_INSIGHTS}" \
            --yes \
            --output none
        log_success "Time Series Insights environment deleted"
    else
        log_warn "Time Series Insights environment '${TIME_SERIES_INSIGHTS}' not found, skipping"
    fi
    
    # Delete IoT Hub
    if az iot hub show --resource-group "${RESOURCE_GROUP}" --name "${IOT_HUB}" &> /dev/null; then
        log_info "Deleting IoT Hub: ${IOT_HUB}"
        az iot hub delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${IOT_HUB}" \
            --output none
        log_success "IoT Hub deleted"
    else
        log_warn "IoT Hub '${IOT_HUB}' not found, skipping"
    fi
    
    log_success "Time Series and IoT resources cleaned up"
}

delete_digital_twins() {
    log_info "Removing Digital Twins instance..."
    
    if az dt show --resource-group "${RESOURCE_GROUP}" --name "${DIGITAL_TWINS_INSTANCE}" &> /dev/null; then
        # Delete all digital twins first
        log_info "Deleting all digital twins from instance: ${DIGITAL_TWINS_INSTANCE}"
        az dt twin delete-all \
            --dt-name "${DIGITAL_TWINS_INSTANCE}" \
            --yes \
            --output none
        
        # Delete models
        log_info "Deleting all models from Digital Twins instance"
        local models=$(az dt model list --dt-name "${DIGITAL_TWINS_INSTANCE}" --query "[].id" --output tsv 2>/dev/null || echo "")
        if [ -n "${models}" ]; then
            for model in ${models}; do
                log_info "Deleting model: ${model}"
                az dt model delete --dt-name "${DIGITAL_TWINS_INSTANCE}" --dtmi "${model}" --output none 2>/dev/null || true
            done
        fi
        
        # Delete Digital Twins instance
        log_info "Deleting Digital Twins instance: ${DIGITAL_TWINS_INSTANCE}"
        az dt delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${DIGITAL_TWINS_INSTANCE}" \
            --yes \
            --output none
        
        log_success "Digital Twins instance deleted"
    else
        log_warn "Digital Twins instance '${DIGITAL_TWINS_INSTANCE}' not found, skipping"
    fi
    
    log_success "Digital Twins resources cleaned up"
}

delete_energy_data_manager() {
    log_info "Removing Azure Data Manager for Energy..."
    
    if az energy-data-service show --resource-group "${RESOURCE_GROUP}" --name "${ENERGY_DATA_MANAGER}" &> /dev/null; then
        log_info "Deleting Azure Data Manager for Energy: ${ENERGY_DATA_MANAGER}"
        az energy-data-service delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${ENERGY_DATA_MANAGER}" \
            --yes \
            --output none
        
        log_success "Azure Data Manager for Energy deleted"
    else
        log_warn "Azure Data Manager for Energy '${ENERGY_DATA_MANAGER}' not found, skipping"
    fi
    
    log_success "Energy Data Manager cleaned up"
}

delete_log_analytics_workspace() {
    log_info "Removing Log Analytics workspace..."
    
    if az monitor log-analytics workspace show --resource-group "${RESOURCE_GROUP}" --workspace-name "${LOG_WORKSPACE}" &> /dev/null; then
        log_info "Deleting Log Analytics workspace: ${LOG_WORKSPACE}"
        az monitor log-analytics workspace delete \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_WORKSPACE}" \
            --force true \
            --yes \
            --output none
        
        log_success "Log Analytics workspace deleted"
    else
        log_warn "Log Analytics workspace '${LOG_WORKSPACE}' not found, skipping"
    fi
    
    log_success "Monitoring resources cleaned up"
}

delete_resource_group() {
    log_info "Removing resource group and all remaining resources..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_info "Deleting resource group: ${RESOURCE_GROUP}"
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait \
            --output none
        
        log_success "Resource group deletion initiated"
        log_info "Note: Complete deletion may take several minutes"
    else
        log_warn "Resource group '${RESOURCE_GROUP}' not found, skipping"
    fi
}

cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment configuration
    if [ -f "${CONFIG_FILE}" ]; then
        rm -f "${CONFIG_FILE}"
        log_success "Deployment configuration file removed"
    fi
    
    # Remove DTDL models directory
    if [ -d "${SCRIPT_DIR}/../dtdl-models" ]; then
        rm -rf "${SCRIPT_DIR}/../dtdl-models"
        log_success "DTDL models directory removed"
    fi
    
    # Remove configuration files
    local config_files=(
        "${SCRIPT_DIR}/../analytics-config.json"
        "${SCRIPT_DIR}/../dashboard-config.json"
    )
    
    for file in "${config_files[@]}"; do
        if [ -f "${file}" ]; then
            rm -f "${file}"
            log_success "Configuration file removed: $(basename "${file}")"
        fi
    done
    
    log_success "Local files cleaned up"
}

# =============================================================================
# MAIN DESTRUCTION FLOW
# =============================================================================

main() {
    log_info "Starting destruction of Intelligent Energy Grid Analytics platform..."
    log_info "Timestamp: ${TIMESTAMP}"
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Run prerequisite checks
    check_prerequisites
    load_configuration
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_event_grid_and_function_app
    delete_ai_services_and_storage
    delete_time_series_insights_and_iot_hub
    delete_digital_twins
    delete_energy_data_manager
    delete_log_analytics_workspace
    delete_resource_group
    
    # Clean up local files
    cleanup_local_files
    
    log_success "✅ Destruction completed successfully!"
    log_info "All resources have been deleted or scheduled for deletion."
    log_info "Note: Some resources may take additional time to be fully removed."
    echo ""
    
    log_info "=== DESTRUCTION SUMMARY ==="
    log_info "Resource Group: ${RESOURCE_GROUP} (deletion in progress)"
    log_info "All associated resources have been removed"
    log_info "Local configuration files have been cleaned up"
    echo ""
    
    log_info "📋 Full destruction log available at: ${LOG_FILE}"
    log_success "🎉 Cleanup completed! All resources have been removed."
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force    Skip confirmation prompts"
            echo "  --help     Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"