#!/bin/bash

# Destroy Private 5G Networks with Azure Operator Nexus and Azure Private 5G Core
# This script safely removes all resources created by the deploy.sh script
# Author: Generated with Claude Code
# Version: 1.0

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.env"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "$@"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
cleanup_on_error() {
    error "Cleanup failed. Check log file: ${LOG_FILE}"
    error "Some resources may need manual cleanup"
    exit 1
}

trap cleanup_on_error ERR

# Load configuration
load_configuration() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        error "Configuration file not found: ${CONFIG_FILE}"
        error "Please ensure deploy.sh has been run or manually create the configuration file"
        exit 1
    fi
    
    info "Loading configuration from ${CONFIG_FILE}"
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
    
    # Verify required variables
    local required_vars=(
        "RESOURCE_GROUP"
        "SUBSCRIPTION_ID"
        "MOBILE_NETWORK_NAME"
        "SITE_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable ${var} not found in configuration"
            exit 1
        fi
    done
    
    info "Configuration loaded successfully"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  Mobile Network: ${MOBILE_NETWORK_NAME}"
    info "  Site: ${SITE_NAME}"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Verify subscription
    local current_subscription=$(az account show --query id --output tsv)
    if [[ "${current_subscription}" != "${SUBSCRIPTION_ID}" ]]; then
        warn "Current subscription (${current_subscription}) differs from deployment subscription (${SUBSCRIPTION_ID})"
        read -p "Continue with current subscription? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Please switch to the correct subscription and try again"
            exit 1
        fi
    fi
    
    success "Prerequisites check completed"
}

# Confirmation prompt
confirm_destruction() {
    warn "This will permanently delete all Private 5G Network resources!"
    warn "Resource Group: ${RESOURCE_GROUP}"
    warn "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " confirmation
    if [[ "${confirmation}" != "yes" ]]; then
        info "Destruction cancelled"
        exit 0
    fi
    
    info "Destruction confirmed. Starting cleanup..."
}

# Remove edge workloads
remove_edge_workloads() {
    info "Removing edge computing workloads..."
    
    # Check if edge workload manifest exists
    local workload_file="${SCRIPT_DIR}/edge-workload.yaml"
    if [[ -f "${workload_file}" ]]; then
        info "Found edge workload manifest: ${workload_file}"
        
        # Check if kubectl is available
        if command -v kubectl &> /dev/null; then
            # Attempt to delete workload (may fail if cluster not accessible)
            if kubectl delete -f "${workload_file}" --ignore-not-found=true 2>/dev/null; then
                success "Edge workload deleted successfully"
            else
                warn "Could not delete edge workload - cluster may not be accessible"
            fi
        else
            warn "kubectl not available - skipping edge workload deletion"
        fi
        
        # Remove manifest file
        rm -f "${workload_file}"
        success "Edge workload manifest removed"
    else
        info "No edge workload manifest found"
    fi
    
    # Remove container registry if it exists
    if [[ -n "${ACR_NAME:-}" ]]; then
        info "Removing Azure Container Registry: ${ACR_NAME}"
        if az acr delete \
            --name "${ACR_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes 2>/dev/null; then
            success "Azure Container Registry deleted: ${ACR_NAME}"
        else
            warn "Failed to delete Azure Container Registry (may not exist): ${ACR_NAME}"
        fi
    fi
    
    success "Edge workload cleanup completed"
}

# Remove IoT services
remove_iot_services() {
    info "Removing Azure IoT services..."
    
    # Remove Device Provisioning Service
    if [[ -n "${DPS_NAME:-}" ]]; then
        info "Removing Device Provisioning Service: ${DPS_NAME}"
        if az iot dps delete \
            --name "${DPS_NAME}" \
            --resource-group "${RESOURCE_GROUP}" 2>/dev/null; then
            success "Device Provisioning Service deleted: ${DPS_NAME}"
        else
            warn "Failed to delete Device Provisioning Service (may not exist): ${DPS_NAME}"
        fi
    fi
    
    # Remove IoT Hub
    if [[ -n "${IOTHUB_NAME:-}" ]]; then
        info "Removing IoT Hub: ${IOTHUB_NAME}"
        if az iot hub delete \
            --name "${IOTHUB_NAME}" \
            --resource-group "${RESOURCE_GROUP}" 2>/dev/null; then
            success "IoT Hub deleted: ${IOTHUB_NAME}"
        else
            warn "Failed to delete IoT Hub (may not exist): ${IOTHUB_NAME}"
        fi
    fi
    
    success "IoT services cleanup completed"
}

# Remove monitoring and analytics
remove_monitoring() {
    info "Removing monitoring and analytics resources..."
    
    # Remove diagnostic settings for packet core (if they exist)
    if az mobile-network pccp show --name "${SITE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "Removing diagnostic settings for packet core"
        if az monitor diagnostic-settings delete \
            --name "diag-packet-core" \
            --resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MobileNetwork/packetCoreControlPlanes/${SITE_NAME}" 2>/dev/null; then
            success "Diagnostic settings removed"
        else
            warn "Failed to remove diagnostic settings (may not exist)"
        fi
    fi
    
    # Remove Log Analytics workspace
    if [[ -n "${LAW_NAME:-}" ]]; then
        info "Removing Log Analytics workspace: ${LAW_NAME}"
        if az monitor log-analytics workspace delete \
            --name "${LAW_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes 2>/dev/null; then
            success "Log Analytics workspace deleted: ${LAW_NAME}"
        else
            warn "Failed to delete Log Analytics workspace (may not exist): ${LAW_NAME}"
        fi
    fi
    
    success "Monitoring cleanup completed"
}

# Remove SIM policies
remove_sim_policies() {
    info "Removing SIM policies..."
    
    # List and remove all SIM policies for the mobile network
    local sim_policies
    if sim_policies=$(az mobile-network sim-policy list \
        --mobile-network-name "${MOBILE_NETWORK_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[].name" --output tsv 2>/dev/null); then
        
        if [[ -n "${sim_policies}" ]]; then
            while IFS= read -r policy_name; do
                info "Removing SIM policy: ${policy_name}"
                if az mobile-network sim-policy delete \
                    --mobile-network-name "${MOBILE_NETWORK_NAME}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --sim-policy-name "${policy_name}" \
                    --yes 2>/dev/null; then
                    success "SIM policy deleted: ${policy_name}"
                else
                    warn "Failed to delete SIM policy: ${policy_name}"
                fi
            done <<< "${sim_policies}"
        else
            info "No SIM policies found"
        fi
    else
        warn "Could not list SIM policies (mobile network may not exist)"
    fi
    
    success "SIM policies cleanup completed"
}

# Remove service policies
remove_service_policies() {
    info "Removing service policies..."
    
    local services=("svc-realtime-control" "svc-video-surveillance")
    
    for service_name in "${services[@]}"; do
        info "Removing service: ${service_name}"
        if az mobile-network service delete \
            --mobile-network-name "${MOBILE_NETWORK_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --service-name "${service_name}" \
            --yes 2>/dev/null; then
            success "Service deleted: ${service_name}"
        else
            warn "Failed to delete service (may not exist): ${service_name}"
        fi
    done
    
    success "Service policies cleanup completed"
}

# Remove packet core and site
remove_packet_core() {
    info "Removing packet core and site..."
    
    # Remove packet core control plane
    info "Removing packet core control plane: ${SITE_NAME}"
    if az mobile-network pccp delete \
        --name "${SITE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes --no-wait 2>/dev/null; then
        success "Packet core control plane deletion initiated"
        
        # Wait for deletion to complete
        info "Waiting for packet core deletion to complete..."
        local max_attempts=30
        local attempt=0
        
        while [[ ${attempt} -lt ${max_attempts} ]]; do
            if ! az mobile-network pccp show \
                --name "${SITE_NAME}" \
                --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
                success "Packet core control plane deleted successfully"
                break
            fi
            
            attempt=$((attempt + 1))
            info "Waiting... (${attempt}/${max_attempts})"
            sleep 10
        done
        
        if [[ ${attempt} -eq ${max_attempts} ]]; then
            warn "Packet core deletion timeout - continuing with cleanup"
        fi
    else
        warn "Failed to delete packet core control plane (may not exist)"
    fi
    
    # Remove site
    info "Removing site: ${SITE_NAME}"
    if az mobile-network site delete \
        --mobile-network-name "${MOBILE_NETWORK_NAME}" \
        --name "${SITE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes --no-wait 2>/dev/null; then
        success "Site deletion initiated: ${SITE_NAME}"
    else
        warn "Failed to delete site (may not exist): ${SITE_NAME}"
    fi
    
    success "Packet core and site cleanup completed"
}

# Remove Azure Stack Edge integration
remove_ase_integration() {
    info "Removing Azure Stack Edge integration..."
    
    # Remove custom location
    if [[ -n "${CUSTOM_LOCATION_NAME:-}" ]]; then
        info "Removing custom location: ${CUSTOM_LOCATION_NAME}"
        if az customlocation delete \
            --name "${CUSTOM_LOCATION_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes 2>/dev/null; then
            success "Custom location deleted: ${CUSTOM_LOCATION_NAME}"
        else
            warn "Failed to delete custom location (may not exist): ${CUSTOM_LOCATION_NAME}"
        fi
    fi
    
    warn "Note: Azure Stack Edge device and connected cluster require manual cleanup"
    warn "Please disconnect and deregister the ASE device from Azure Arc manually"
    
    success "ASE integration cleanup completed"
}

# Remove data networks
remove_data_networks() {
    info "Removing data networks..."
    
    local data_networks=("dn-ot-systems" "dn-it-systems")
    
    for dn_name in "${data_networks[@]}"; do
        info "Removing data network: ${dn_name}"
        if az mobile-network attached-data-network delete \
            --mobile-network-name "${MOBILE_NETWORK_NAME}" \
            --data-network-name "${dn_name}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes 2>/dev/null; then
            success "Data network deleted: ${dn_name}"
        else
            warn "Failed to delete data network (may not exist): ${dn_name}"
        fi
    done
    
    success "Data networks cleanup completed"
}

# Remove network slices
remove_network_slices() {
    info "Removing network slices..."
    
    local slices=("slice-critical-iot" "slice-massive-iot" "slice-video")
    
    for slice_name in "${slices[@]}"; do
        info "Removing network slice: ${slice_name}"
        if az mobile-network slice delete \
            --mobile-network-name "${MOBILE_NETWORK_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --slice-name "${slice_name}" \
            --yes 2>/dev/null; then
            success "Network slice deleted: ${slice_name}"
        else
            warn "Failed to delete network slice (may not exist): ${slice_name}"
        fi
    done
    
    success "Network slices cleanup completed"
}

# Remove mobile network
remove_mobile_network() {
    info "Removing mobile network: ${MOBILE_NETWORK_NAME}"
    
    if az mobile-network delete \
        --name "${MOBILE_NETWORK_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes 2>/dev/null; then
        success "Mobile network deleted: ${MOBILE_NETWORK_NAME}"
    else
        warn "Failed to delete mobile network (may not exist): ${MOBILE_NETWORK_NAME}"
    fi
    
    success "Mobile network cleanup completed"
}

# Remove resource group
remove_resource_group() {
    info "Removing resource group: ${RESOURCE_GROUP}"
    
    # Final confirmation for resource group deletion
    warn "About to delete the entire resource group: ${RESOURCE_GROUP}"
    read -p "This will delete ALL remaining resources. Continue? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Deleting resource group: ${RESOURCE_GROUP}"
        if az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes --no-wait; then
            success "Resource group deletion initiated: ${RESOURCE_GROUP}"
            info "Note: Complete deletion may take 10-15 minutes"
        else
            error "Failed to delete resource group: ${RESOURCE_GROUP}"
            return 1
        fi
    else
        info "Resource group deletion cancelled"
        warn "Some resources may remain. Please clean up manually if needed"
    fi
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local configuration files..."
    
    # Remove configuration file
    if [[ -f "${CONFIG_FILE}" ]]; then
        rm -f "${CONFIG_FILE}"
        success "Configuration file removed: ${CONFIG_FILE}"
    fi
    
    # Remove any edge workload manifests
    rm -f "${SCRIPT_DIR}/edge-workload.yaml"
    
    success "Local cleanup completed"
}

# Display cleanup summary
display_summary() {
    info ""
    info "Private 5G Network destruction completed!"
    info "Cleanup log: ${LOG_FILE}"
    info ""
    info "Manual cleanup may be required for:"
    info "1. Azure Stack Edge device disconnection from Azure Arc"
    info "2. Physical 5G radio equipment (gNodeB) configuration reset"
    info "3. SIM card deprovisioning from carrier"
    info "4. Any remaining Azure resources not managed by this script"
    info ""
    success "Destruction process finished"
}

# Main destruction function
main() {
    info "Starting Private 5G Network destruction..."
    info "Log file: ${LOG_FILE}"
    
    # Load configuration and verify prerequisites
    load_configuration
    check_prerequisites
    confirm_destruction
    
    # Run cleanup steps in reverse order of creation
    remove_edge_workloads
    remove_iot_services
    remove_monitoring
    remove_sim_policies
    remove_service_policies
    remove_packet_core
    remove_ase_integration
    remove_data_networks
    remove_network_slices
    remove_mobile_network
    remove_resource_group
    cleanup_local_files
    
    display_summary
}

# Show help if requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Private 5G Network Destruction Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "This script removes all resources created by deploy.sh"
    echo ""
    echo "Options:"
    echo "  --help, -h    Show this help message"
    echo ""
    echo "Configuration:"
    echo "  Reads deployment configuration from: ${CONFIG_FILE}"
    echo ""
    echo "Requirements:"
    echo "  - Azure CLI installed and authenticated"
    echo "  - Access to the subscription used for deployment"
    echo "  - Appropriate permissions to delete resources"
    echo ""
    exit 0
fi

# Run main function
main "$@"