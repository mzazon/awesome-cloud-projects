#!/bin/bash

# Deploy Private 5G Networks with Azure Operator Nexus and Azure Private 5G Core
# This script automates the deployment of a private 5G network infrastructure
# Author: Generated with Claude Code
# Version: 1.0

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
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
    error "Deployment failed. Check log file: ${LOG_FILE}"
    error "Run destroy.sh to clean up any partially created resources"
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI v2.40.0 or later."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    info "Azure CLI version: ${az_version}"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if kubectl is installed (for edge workloads)
    if ! command -v kubectl &> /dev/null; then
        warn "kubectl is not installed. Edge workload deployment will be skipped."
        SKIP_EDGE_WORKLOADS=true
    else
        SKIP_EDGE_WORKLOADS=false
    fi
    
    # Check if openssl is available for random suffix generation
    if ! command -v openssl &> /dev/null; then
        warn "openssl not found. Using bash random for suffix generation."
        USE_OPENSSL=false
    else
        USE_OPENSSL=true
    fi
    
    success "Prerequisites check completed"
}

# Load or create configuration
setup_configuration() {
    info "Setting up configuration..."
    
    if [[ -f "${CONFIG_FILE}" ]]; then
        info "Loading existing configuration from ${CONFIG_FILE}"
        # shellcheck source=/dev/null
        source "${CONFIG_FILE}"
    else
        info "Creating new configuration..."
        
        # Generate unique identifiers
        if [[ "${USE_OPENSSL}" == "true" ]]; then
            RANDOM_SUFFIX=$(openssl rand -hex 3)
        else
            RANDOM_SUFFIX=$(printf "%06x" $((RANDOM * RANDOM)))
        fi
        
        # Set environment variables
        export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-private5g-$(date +%s)}"
        export LOCATION="${LOCATION:-eastus}"
        export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        export MOBILE_NETWORK_NAME="${MOBILE_NETWORK_NAME:-mn-manufacturing}"
        export SITE_NAME="${SITE_NAME:-site-factory01}"
        export ASE_DEVICE_NAME="ase-${RANDOM_SUFFIX}"
        export CUSTOM_LOCATION_NAME="cl-${SITE_NAME}"
        
        # Save configuration
        cat > "${CONFIG_FILE}" << EOF
# Private 5G Network Deployment Configuration
# Generated on $(date)

export RESOURCE_GROUP="${RESOURCE_GROUP}"
export LOCATION="${LOCATION}"
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
export MOBILE_NETWORK_NAME="${MOBILE_NETWORK_NAME}"
export SITE_NAME="${SITE_NAME}"
export ASE_DEVICE_NAME="${ASE_DEVICE_NAME}"
export CUSTOM_LOCATION_NAME="${CUSTOM_LOCATION_NAME}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export SKIP_EDGE_WORKLOADS="${SKIP_EDGE_WORKLOADS}"
EOF
        
        info "Configuration saved to ${CONFIG_FILE}"
    fi
    
    # Display configuration
    info "Deployment configuration:"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  Location: ${LOCATION}"
    info "  Mobile Network: ${MOBILE_NETWORK_NAME}"
    info "  Site Name: ${SITE_NAME}"
    info "  Random Suffix: ${RANDOM_SUFFIX}"
}

# Register required resource providers
register_providers() {
    info "Registering required Azure resource providers..."
    
    local providers=(
        "Microsoft.MobileNetwork"
        "Microsoft.ExtendedLocation"
        "Microsoft.Kubernetes"
        "Microsoft.KubernetesConfiguration"
    )
    
    for provider in "${providers[@]}"; do
        info "Registering provider: ${provider}"
        if az provider register --namespace "${provider}" --wait; then
            success "Provider ${provider} registered successfully"
        else
            error "Failed to register provider: ${provider}"
            return 1
        fi
    done
    
    success "All resource providers registered"
}

# Create resource group
create_resource_group() {
    info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=private5g environment=production; then
        success "Resource group created: ${RESOURCE_GROUP}"
    else
        error "Failed to create resource group"
        return 1
    fi
}

# Create mobile network
create_mobile_network() {
    info "Creating mobile network: ${MOBILE_NETWORK_NAME}"
    
    if az mobile-network create \
        --name "${MOBILE_NETWORK_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --public-land-mobile-network-identifier "{mcc:310,mnc:950}"; then
        
        # Store the mobile network ID
        MOBILE_NETWORK_ID=$(az mobile-network show \
            --name "${MOBILE_NETWORK_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query id --output tsv)
        
        echo "export MOBILE_NETWORK_ID=\"${MOBILE_NETWORK_ID}\"" >> "${CONFIG_FILE}"
        success "Mobile network created with ID: ${MOBILE_NETWORK_ID}"
    else
        error "Failed to create mobile network"
        return 1
    fi
}

# Configure network slices
configure_network_slices() {
    info "Configuring network slices..."
    
    local slices=(
        "slice-critical-iot:1:000001"
        "slice-massive-iot:2:000002"
        "slice-video:3:000003"
    )
    
    for slice_config in "${slices[@]}"; do
        IFS=':' read -r slice_name sst sd <<< "${slice_config}"
        
        info "Creating network slice: ${slice_name} (SST: ${sst}, SD: ${sd})"
        
        if az mobile-network slice create \
            --mobile-network-name "${MOBILE_NETWORK_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --slice-name "${slice_name}" \
            --location "${LOCATION}" \
            --snssai "{sst:${sst},sd:${sd}}"; then
            success "Network slice created: ${slice_name}"
        else
            error "Failed to create network slice: ${slice_name}"
            return 1
        fi
    done
    
    success "All network slices configured"
}

# Create data networks
create_data_networks() {
    info "Creating data networks..."
    
    # Create data network for OT systems
    info "Creating data network for OT systems"
    if az mobile-network attached-data-network create \
        --mobile-network-name "${MOBILE_NETWORK_NAME}" \
        --data-network-name "dn-ot-systems" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --dns-addresses "['10.1.0.10','10.1.0.11']" \
        --user-plane-data-interface "{name:N6,ipv4Address:10.1.0.100}"; then
        success "OT systems data network created"
    else
        error "Failed to create OT systems data network"
        return 1
    fi
    
    # Create data network for IT systems
    info "Creating data network for IT systems"
    if az mobile-network attached-data-network create \
        --mobile-network-name "${MOBILE_NETWORK_NAME}" \
        --data-network-name "dn-it-systems" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --dns-addresses "['10.2.0.10','10.2.0.11']" \
        --user-plane-data-interface "{name:N6,ipv4Address:10.2.0.100}"; then
        success "IT systems data network created"
    else
        error "Failed to create IT systems data network"
        return 1
    fi
    
    success "Data networks created for traffic segmentation"
}

# Deploy Azure Stack Edge integration
deploy_ase_integration() {
    info "Deploying Azure Stack Edge integration..."
    
    # Note: This is a placeholder as actual ASE device registration
    # requires physical hardware and manual configuration
    warn "Azure Stack Edge device must be manually configured and registered"
    warn "Assuming connected cluster '${ASE_DEVICE_NAME}' exists"
    
    # Create custom location for the site
    info "Creating custom location: ${CUSTOM_LOCATION_NAME}"
    if az customlocation create \
        --name "${CUSTOM_LOCATION_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --namespace "Microsoft.ExtendedLocation" \
        --host-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Kubernetes/connectedClusters/${ASE_DEVICE_NAME}" \
        --cluster-extension-ids "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Kubernetes/connectedClusters/${ASE_DEVICE_NAME}/providers/Microsoft.KubernetesConfiguration/extensions/azure-private-5g-core"; then
        
        # Get custom location ID
        CUSTOM_LOCATION_ID=$(az customlocation show \
            --name "${CUSTOM_LOCATION_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query id --output tsv)
        
        echo "export CUSTOM_LOCATION_ID=\"${CUSTOM_LOCATION_ID}\"" >> "${CONFIG_FILE}"
        success "Custom location created for edge deployment"
    else
        warn "Failed to create custom location - may require manual ASE setup"
        # Continue with deployment as this might be expected in some scenarios
    fi
}

# Create site and deploy packet core
deploy_packet_core() {
    info "Creating site and deploying packet core..."
    
    # Create site resource
    info "Creating site: ${SITE_NAME}"
    if az mobile-network site create \
        --mobile-network-name "${MOBILE_NETWORK_NAME}" \
        --name "${SITE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}"; then
        success "Site created: ${SITE_NAME}"
    else
        error "Failed to create site"
        return 1
    fi
    
    # Deploy packet core control plane
    info "Deploying packet core control plane"
    if [[ -n "${CUSTOM_LOCATION_ID:-}" ]]; then
        if az mobile-network pccp create \
            --name "${SITE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --access-interface "{name:N2,ipv4Address:192.168.1.10,ipv4Subnet:192.168.1.0/24,ipv4Gateway:192.168.1.1}" \
            --local-diagnostics "{authentication-type:AAD}" \
            --platform "{type:AKS-HCI,custom-location:${CUSTOM_LOCATION_ID}}" \
            --sku "G0" \
            --mobile-network "{id:${MOBILE_NETWORK_ID}}" \
            --control-plane-access-interface "{name:N2}"; then
            success "Packet core control plane deployed"
        else
            error "Failed to deploy packet core control plane"
            return 1
        fi
    else
        warn "Skipping packet core deployment - custom location not available"
    fi
}

# Configure service policies
configure_service_policies() {
    info "Configuring service policies..."
    
    # Create service for real-time control
    info "Creating service for real-time control"
    if az mobile-network service create \
        --mobile-network-name "${MOBILE_NETWORK_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --service-name "svc-realtime-control" \
        --location "${LOCATION}" \
        --service-qos "{5qi:82,arp:{priority-level:1,preemption-capability:MayPreempt,preemption-vulnerability:NotPreemptable}}" \
        --pcc-rules "[{rule-name:rule-control,rule-precedence:100,service-data-flow-templates:[{template-name:control-traffic,direction:Bidirectional,protocol:[TCP],remote-ip-list:[10.1.0.0/16]}]}]"; then
        success "Real-time control service created"
    else
        error "Failed to create real-time control service"
        return 1
    fi
    
    # Create service for video surveillance
    info "Creating service for video surveillance"
    if az mobile-network service create \
        --mobile-network-name "${MOBILE_NETWORK_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --service-name "svc-video-surveillance" \
        --location "${LOCATION}" \
        --service-qos "{5qi:4,arp:{priority-level:5,preemption-capability:MayPreempt,preemption-vulnerability:Preemptable}}" \
        --pcc-rules "[{rule-name:rule-video,rule-precedence:200,service-data-flow-templates:[{template-name:video-streams,direction:Uplink,protocol:[UDP],remote-ip-list:[10.2.0.0/16],port-list:[{port:554,protocol:TCP}]}]}]"; then
        success "Video surveillance service created"
    else
        error "Failed to create video surveillance service"
        return 1
    fi
    
    success "Service policies configured for different traffic types"
}

# Create SIM policies
create_sim_policies() {
    info "Creating SIM policies..."
    
    # Create SIM policy for industrial IoT devices
    info "Creating SIM policy for industrial IoT devices"
    if az mobile-network sim-policy create \
        --mobile-network-name "${MOBILE_NETWORK_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --sim-policy-name "policy-industrial-iot" \
        --location "${LOCATION}" \
        --default-slice "{id:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MobileNetwork/mobileNetworks/${MOBILE_NETWORK_NAME}/slices/slice-critical-iot}" \
        --ue-ambr "{uplink:10 Mbps,downlink:10 Mbps}" \
        --slice-configurations "[{slice:{id:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MobileNetwork/mobileNetworks/${MOBILE_NETWORK_NAME}/slices/slice-critical-iot},default-data-network:{id:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MobileNetwork/mobileNetworks/${MOBILE_NETWORK_NAME}/dataNetworks/dn-ot-systems},data-network-configurations:[{data-network:{id:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MobileNetwork/mobileNetworks/${MOBILE_NETWORK_NAME}/dataNetworks/dn-ot-systems},session-ambr:{uplink:10 Mbps,downlink:10 Mbps},5qi:82,arp:{priority-level:1}}]}]"; then
        success "SIM policy created for industrial IoT devices"
    else
        error "Failed to create SIM policy"
        return 1
    fi
    
    success "SIM policies created for device provisioning"
}

# Configure monitoring and analytics
configure_monitoring() {
    info "Configuring monitoring and analytics..."
    
    # Create Log Analytics workspace
    local law_name="law-private5g-${RANDOM_SUFFIX}"
    info "Creating Log Analytics workspace: ${law_name}"
    if az monitor log-analytics workspace create \
        --name "${law_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}"; then
        
        # Get workspace ID
        LAW_ID=$(az monitor log-analytics workspace show \
            --name "${law_name}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query id --output tsv)
        
        echo "export LAW_ID=\"${LAW_ID}\"" >> "${CONFIG_FILE}"
        echo "export LAW_NAME=\"${law_name}\"" >> "${CONFIG_FILE}"
        success "Log Analytics workspace created: ${law_name}"
        
        # Configure diagnostic settings for packet core (if deployed)
        if az mobile-network pccp show --name "${SITE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
            info "Configuring diagnostic settings for packet core"
            if az monitor diagnostic-settings create \
                --name "diag-packet-core" \
                --resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MobileNetwork/packetCoreControlPlanes/${SITE_NAME}" \
                --logs '[{"category":"DeviceEvents","enabled":true},{"category":"SMFEvents","enabled":true}]' \
                --metrics '[{"category":"AllMetrics","enabled":true}]' \
                --workspace "${LAW_ID}"; then
                success "Diagnostic settings configured for packet core"
            else
                warn "Failed to configure diagnostic settings - packet core may not be fully deployed"
            fi
        else
            warn "Packet core not found - skipping diagnostic settings"
        fi
    else
        error "Failed to create Log Analytics workspace"
        return 1
    fi
    
    success "Monitoring and analytics configured"
}

# Integrate with Azure IoT services
integrate_iot_services() {
    info "Integrating with Azure IoT services..."
    
    # Create IoT Hub
    local iothub_name="iothub-5g-${RANDOM_SUFFIX}"
    info "Creating IoT Hub: ${iothub_name}"
    if az iot hub create \
        --name "${iothub_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku S1; then
        
        echo "export IOTHUB_NAME=\"${iothub_name}\"" >> "${CONFIG_FILE}"
        success "IoT Hub created: ${iothub_name}"
    else
        error "Failed to create IoT Hub"
        return 1
    fi
    
    # Create device provisioning service
    local dps_name="dps-5g-${RANDOM_SUFFIX}"
    info "Creating Device Provisioning Service: ${dps_name}"
    if az iot dps create \
        --name "${dps_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}"; then
        
        echo "export DPS_NAME=\"${dps_name}\"" >> "${CONFIG_FILE}"
        success "Device Provisioning Service created: ${dps_name}"
    else
        error "Failed to create Device Provisioning Service"
        return 1
    fi
    
    # Link DPS to IoT Hub
    info "Linking DPS to IoT Hub"
    IOT_HUB_CONNECTION=$(az iot hub connection-string show \
        --hub-name "${iothub_name}" \
        --key primary --query connectionString --output tsv)
    
    if az iot dps linked-hub create \
        --dps-name "${dps_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --connection-string "${IOT_HUB_CONNECTION}" \
        --location "${LOCATION}"; then
        success "DPS linked to IoT Hub"
    else
        error "Failed to link DPS to IoT Hub"
        return 1
    fi
    
    success "IoT services integrated with 5G network"
}

# Deploy edge computing workloads
deploy_edge_workloads() {
    if [[ "${SKIP_EDGE_WORKLOADS}" == "true" ]]; then
        warn "Skipping edge workloads deployment - kubectl not available"
        return 0
    fi
    
    info "Deploying edge computing workloads..."
    
    # Create container registry
    local acr_name="acr5g${RANDOM_SUFFIX}"
    info "Creating Azure Container Registry: ${acr_name}"
    if az acr create \
        --name "${acr_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard; then
        
        echo "export ACR_NAME=\"${acr_name}\"" >> "${CONFIG_FILE}"
        success "Azure Container Registry created: ${acr_name}"
    else
        error "Failed to create Azure Container Registry"
        return 1
    fi
    
    # Create edge workload manifest
    local workload_file="${SCRIPT_DIR}/edge-workload.yaml"
    info "Creating edge workload manifest: ${workload_file}"
    cat > "${workload_file}" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: realtime-analytics
  namespace: edge-workloads
spec:
  replicas: 3
  selector:
    matchLabels:
      app: analytics
  template:
    metadata:
      labels:
        app: analytics
    spec:
      containers:
      - name: analytics-engine
        image: ${acr_name}.azurecr.io/analytics:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
EOF
    
    # Note: Actual kubectl deployment would require kubeconfig
    warn "Edge workload manifest created but not deployed"
    warn "Manual kubectl configuration required for edge cluster deployment"
    
    success "Edge computing workload configuration completed"
}

# Main deployment function
main() {
    info "Starting Private 5G Network deployment..."
    info "Log file: ${LOG_FILE}"
    
    # Run deployment steps
    check_prerequisites
    setup_configuration
    register_providers
    create_resource_group
    create_mobile_network
    configure_network_slices
    create_data_networks
    deploy_ase_integration
    deploy_packet_core
    configure_service_policies
    create_sim_policies
    configure_monitoring
    integrate_iot_services
    deploy_edge_workloads
    
    success "Private 5G Network deployment completed successfully!"
    info "Configuration saved in: ${CONFIG_FILE}"
    info "Deployment log: ${LOG_FILE}"
    
    # Display next steps
    info ""
    info "Next steps:"
    info "1. Configure Azure Stack Edge device and connect to Azure Arc"
    info "2. Install 5G radio equipment (gNodeB) and configure"
    info "3. Provision SIM cards using the created SIM policies"
    info "4. Test device connectivity to the private 5G network"
    info "5. Deploy edge applications using kubectl (if available)"
    info ""
    info "To clean up resources, run: ./destroy.sh"
}

# Run main function
main "$@"