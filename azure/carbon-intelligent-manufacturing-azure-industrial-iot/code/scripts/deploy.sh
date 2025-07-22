#!/bin/bash

###################################################################################
# Azure Smart Factory Carbon Footprint Monitoring - Deployment Script
#
# This script deploys the complete Azure infrastructure for smart factory carbon
# footprint monitoring using Azure Industrial IoT and Azure Sustainability Manager.
#
# Resources deployed:
# - Azure IoT Hub for industrial device management
# - Azure Event Grid for event-driven architecture  
# - Azure Data Explorer cluster for real-time analytics
# - Azure Functions for carbon calculation logic
# - Azure Storage Account for function app storage
# - Event Hub for high-volume data ingestion
# - Sample IoT device for testing
#
# Prerequisites:
# - Azure CLI v2.57.0 or later
# - Appropriate Azure subscription permissions
# - Access to Azure Sustainability Manager preview program
#
# Usage: ./deploy.sh [--dry-run] [--resource-group <name>] [--location <location>]
###################################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_RESOURCE_GROUP="rg-smart-factory-carbon"
DEFAULT_LOCATION="eastus"

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

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI installation
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI v2.57.0 or later."
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: ${az_version}"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check subscription access
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    log_info "Using Azure subscription: ${subscription_name} (${subscription_id})"
    
    # Check required permissions (basic check)
    log_info "Verifying subscription permissions..."
    if ! az group list --query "[0].name" -o tsv &> /dev/null; then
        error_exit "Insufficient permissions to list resource groups. Please verify your Azure permissions."
    fi
    
    # Check for required resource providers
    log_info "Checking required Azure resource providers..."
    local required_providers=("Microsoft.Devices" "Microsoft.EventGrid" "Microsoft.Kusto" "Microsoft.Web" "Microsoft.Storage" "Microsoft.EventHub")
    
    for provider in "${required_providers[@]}"; do
        local provider_state=$(az provider show --namespace "${provider}" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
        if [ "${provider_state}" != "Registered" ]; then
            log_warning "Resource provider ${provider} is not registered. Attempting to register..."
            if [ "${DRY_RUN}" = false ]; then
                az provider register --namespace "${provider}" --wait || log_warning "Failed to register ${provider}"
            fi
        else
            log_info "Resource provider ${provider} is registered"
        fi
    done
    
    log_success "Prerequisites check completed"
}

generate_unique_suffix() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 3
    else
        echo $(date +%s | tail -c 7 | tr -d '\n')
    fi
}

###################################################################################
# Resource Deployment Functions
###################################################################################

deploy_resource_group() {
    local resource_group="$1"
    local location="$2"
    
    log_info "Creating resource group: ${resource_group}"
    
    if [ "${DRY_RUN}" = true ]; then
        log_info "[DRY RUN] Would create resource group ${resource_group} in ${location}"
        return 0
    fi
    
    if az group show --name "${resource_group}" &> /dev/null; then
        log_warning "Resource group ${resource_group} already exists"
    else
        az group create \
            --name "${resource_group}" \
            --location "${location}" \
            --tags purpose=carbon-monitoring environment=production || error_exit "Failed to create resource group"
        
        log_success "Resource group created: ${resource_group}"
    fi
}

deploy_storage_account() {
    local storage_account="$1"
    local resource_group="$2"
    local location="$3"
    
    log_info "Creating storage account: ${storage_account}"
    
    if [ "${DRY_RUN}" = true ]; then
        log_info "[DRY RUN] Would create storage account ${storage_account}"
        return 0
    fi
    
    if az storage account show --name "${storage_account}" --resource-group "${resource_group}" &> /dev/null; then
        log_warning "Storage account ${storage_account} already exists"
    else
        az storage account create \
            --name "${storage_account}" \
            --resource-group "${resource_group}" \
            --location "${location}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --allow-blob-public-access false \
            --min-tls-version TLS1_2 || error_exit "Failed to create storage account"
        
        log_success "Storage account created: ${storage_account}"
    fi
}

deploy_iot_hub() {
    local iot_hub_name="$1"
    local resource_group="$2"
    local location="$3"
    
    log_info "Creating IoT Hub: ${iot_hub_name}"
    
    if [ "${DRY_RUN}" = true ]; then
        log_info "[DRY RUN] Would create IoT Hub ${iot_hub_name}"
        return 0
    fi
    
    if az iot hub show --name "${iot_hub_name}" --resource-group "${resource_group}" &> /dev/null; then
        log_warning "IoT Hub ${iot_hub_name} already exists"
    else
        az iot hub create \
            --name "${iot_hub_name}" \
            --resource-group "${resource_group}" \
            --location "${location}" \
            --sku S1 \
            --unit 1 \
            --partition-count 4 || error_exit "Failed to create IoT Hub"
        
        log_success "IoT Hub created: ${iot_hub_name}"
    fi
    
    # Wait for IoT Hub to be fully provisioned
    log_info "Waiting for IoT Hub to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local hub_state=$(az iot hub show --name "${iot_hub_name}" --resource-group "${resource_group}" --query "properties.state" -o tsv 2>/dev/null || echo "Unknown")
        if [ "${hub_state}" = "Active" ]; then
            log_success "IoT Hub is active and ready"
            break
        fi
        
        attempt=$((attempt + 1))
        log_info "IoT Hub state: ${hub_state}. Waiting... (${attempt}/${max_attempts})"
        sleep 10
    done
    
    if [ $attempt -eq $max_attempts ]; then
        error_exit "IoT Hub did not become active within expected time"
    fi
}

deploy_event_grid() {
    local topic_name="$1"
    local resource_group="$2"
    local location="$3"
    
    log_info "Creating Event Grid topic: ${topic_name}"
    
    if [ "${DRY_RUN}" = true ]; then
        log_info "[DRY RUN] Would create Event Grid topic ${topic_name}"
        return 0
    fi
    
    if az eventgrid topic show --name "${topic_name}" --resource-group "${resource_group}" &> /dev/null; then
        log_warning "Event Grid topic ${topic_name} already exists"
    else
        az eventgrid topic create \
            --name "${topic_name}" \
            --resource-group "${resource_group}" \
            --location "${location}" \
            --input-schema eventgridschema || error_exit "Failed to create Event Grid topic"
        
        log_success "Event Grid topic created: ${topic_name}"
    fi
}

deploy_data_explorer() {
    local cluster_name="$1"
    local resource_group="$2"
    local location="$3"
    
    log_info "Creating Data Explorer cluster: ${cluster_name}"
    log_warning "Data Explorer cluster creation may take 10-15 minutes..."
    
    if [ "${DRY_RUN}" = true ]; then
        log_info "[DRY RUN] Would create Data Explorer cluster ${cluster_name}"
        return 0
    fi
    
    if az kusto cluster show --cluster-name "${cluster_name}" --resource-group "${resource_group}" &> /dev/null; then
        log_warning "Data Explorer cluster ${cluster_name} already exists"
    else
        az kusto cluster create \
            --cluster-name "${cluster_name}" \
            --resource-group "${resource_group}" \
            --location "${location}" \
            --sku name="Standard_D11_v2" tier="Standard" \
            --capacity 2 || error_exit "Failed to create Data Explorer cluster"
        
        log_success "Data Explorer cluster creation initiated: ${cluster_name}"
    fi
    
    # Wait for cluster to be running
    log_info "Waiting for Data Explorer cluster to be ready..."
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local cluster_state=$(az kusto cluster show --cluster-name "${cluster_name}" --resource-group "${resource_group}" --query "state" -o tsv 2>/dev/null || echo "Unknown")
        if [ "${cluster_state}" = "Running" ]; then
            log_success "Data Explorer cluster is running"
            break
        fi
        
        attempt=$((attempt + 1))
        log_info "Cluster state: ${cluster_state}. Waiting... (${attempt}/${max_attempts})"
        sleep 30
    done
    
    if [ $attempt -eq $max_attempts ]; then
        log_warning "Data Explorer cluster creation is taking longer than expected. It may still be provisioning."
    fi
    
    # Create database
    log_info "Creating Data Explorer database: CarbonMonitoring"
    if ! az kusto database show --cluster-name "${cluster_name}" --database-name "CarbonMonitoring" --resource-group "${resource_group}" &> /dev/null; then
        az kusto database create \
            --cluster-name "${cluster_name}" \
            --database-name "CarbonMonitoring" \
            --resource-group "${resource_group}" \
            --soft-delete-period P365D \
            --hot-cache-period P30D || error_exit "Failed to create Data Explorer database"
        
        log_success "Data Explorer database created: CarbonMonitoring"
    else
        log_warning "Data Explorer database CarbonMonitoring already exists"
    fi
}

deploy_event_hub() {
    local namespace_name="$1"
    local hub_name="$2"
    local resource_group="$3"
    local location="$4"
    
    log_info "Creating Event Hub namespace: ${namespace_name}"
    
    if [ "${DRY_RUN}" = true ]; then
        log_info "[DRY RUN] Would create Event Hub namespace ${namespace_name}"
        return 0
    fi
    
    # Create Event Hub namespace
    if az eventhubs namespace show --name "${namespace_name}" --resource-group "${resource_group}" &> /dev/null; then
        log_warning "Event Hub namespace ${namespace_name} already exists"
    else
        az eventhubs namespace create \
            --name "${namespace_name}" \
            --resource-group "${resource_group}" \
            --location "${location}" \
            --sku Standard || error_exit "Failed to create Event Hub namespace"
        
        log_success "Event Hub namespace created: ${namespace_name}"
    fi
    
    # Create Event Hub
    log_info "Creating Event Hub: ${hub_name}"
    if az eventhubs eventhub show --name "${hub_name}" --namespace-name "${namespace_name}" --resource-group "${resource_group}" &> /dev/null; then
        log_warning "Event Hub ${hub_name} already exists"
    else
        az eventhubs eventhub create \
            --name "${hub_name}" \
            --namespace-name "${namespace_name}" \
            --resource-group "${resource_group}" \
            --partition-count 4 \
            --message-retention 7 || error_exit "Failed to create Event Hub"
        
        log_success "Event Hub created: ${hub_name}"
    fi
}

deploy_function_app() {
    local function_app_name="$1"
    local storage_account="$2"
    local resource_group="$3"
    local location="$4"
    
    log_info "Creating Function App: ${function_app_name}"
    
    if [ "${DRY_RUN}" = true ]; then
        log_info "[DRY RUN] Would create Function App ${function_app_name}"
        return 0
    fi
    
    if az functionapp show --name "${function_app_name}" --resource-group "${resource_group}" &> /dev/null; then
        log_warning "Function App ${function_app_name} already exists"
    else
        az functionapp create \
            --name "${function_app_name}" \
            --resource-group "${resource_group}" \
            --storage-account "${storage_account}" \
            --consumption-plan-location "${location}" \
            --runtime python \
            --runtime-version 3.9 \
            --functions-version 4 \
            --disable-app-insights false || error_exit "Failed to create Function App"
        
        log_success "Function App created: ${function_app_name}"
    fi
}

configure_function_app() {
    local function_app_name="$1"
    local resource_group="$2"
    local iot_hub_name="$3"
    local event_grid_topic="$4"
    local data_explorer_cluster="$5"
    
    log_info "Configuring Function App settings..."
    
    if [ "${DRY_RUN}" = true ]; then
        log_info "[DRY RUN] Would configure Function App settings"
        return 0
    fi
    
    # Get connection strings and keys
    local iot_connection_string=$(az iot hub connection-string show \
        --hub-name "${iot_hub_name}" \
        --resource-group "${resource_group}" \
        --query connectionString --output tsv)
    
    local event_grid_endpoint=$(az eventgrid topic show \
        --name "${event_grid_topic}" \
        --resource-group "${resource_group}" \
        --query endpoint --output tsv)
    
    local event_grid_key=$(az eventgrid topic key list \
        --name "${event_grid_topic}" \
        --resource-group "${resource_group}" \
        --query key1 --output tsv)
    
    # Configure application settings
    az functionapp config appsettings set \
        --name "${function_app_name}" \
        --resource-group "${resource_group}" \
        --settings "IoTHubConnectionString=${iot_connection_string}" \
                   "EventGridEndpoint=${event_grid_endpoint}" \
                   "EventGridKey=${event_grid_key}" \
                   "DataExplorerCluster=${data_explorer_cluster}" || error_exit "Failed to configure Function App settings"
    
    log_success "Function App settings configured"
}

deploy_sample_function() {
    local function_app_name="$1"
    local resource_group="$2"
    
    log_info "Deploying carbon calculation function code..."
    
    if [ "${DRY_RUN}" = true ]; then
        log_info "[DRY RUN] Would deploy function code"
        return 0
    fi
    
    # Create temporary directory for function code
    local temp_dir=$(mktemp -d)
    local function_dir="${temp_dir}/ProcessCarbonData"
    mkdir -p "${function_dir}"
    
    # Create function code
    cat > "${function_dir}/__init__.py" << 'EOF'
import azure.functions as func
import json
import logging
from datetime import datetime

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Carbon footprint calculation triggered')
    
    try:
        # Parse IoT telemetry data
        req_body = req.get_json()
        device_id = req_body.get('deviceId', 'unknown')
        timestamp = req_body.get('timestamp', datetime.utcnow().isoformat())
        telemetry = req_body.get('telemetry', {})
        
        # Carbon calculation logic
        energy_consumption = telemetry.get('energyKwh', 0)
        production_units = telemetry.get('productionUnits', 0)
        temperature = telemetry.get('temperature', 0)
        humidity = telemetry.get('humidity', 0)
        
        # Calculate carbon footprint (simplified calculation)
        carbon_factor = 0.4  # kg CO2 per kWh (grid average)
        total_emissions = energy_consumption * carbon_factor
        emissions_per_unit = total_emissions / max(production_units, 1)
        
        # Environmental efficiency factor
        temp_efficiency = max(0.8, min(1.2, 1 - abs(temperature - 22) * 0.01))
        humidity_efficiency = max(0.9, min(1.1, 1 - abs(humidity - 45) * 0.002))
        
        adjusted_emissions = total_emissions * temp_efficiency * humidity_efficiency
        
        # Prepare sustainability metrics
        carbon_data = {
            'deviceId': device_id,
            'timestamp': timestamp,
            'energyConsumption': energy_consumption,
            'productionUnits': production_units,
            'totalEmissions': round(total_emissions, 4),
            'adjustedEmissions': round(adjusted_emissions, 4),
            'emissionsPerUnit': round(emissions_per_unit, 4),
            'temperatureEfficiency': round(temp_efficiency, 3),
            'humidityEfficiency': round(humidity_efficiency, 3),
            'calculationMethod': 'grid-average-factor-with-environmental-adjustment',
            'carbonFactor': carbon_factor
        }
        
        logging.info(f'Carbon calculation completed for device {device_id}: {adjusted_emissions:.4f} kg CO2')
        return func.HttpResponse(
            json.dumps(carbon_data),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logging.error(f'Error in carbon calculation: {str(e)}')
        return func.HttpResponse(
            json.dumps({'error': str(e), 'timestamp': datetime.utcnow().isoformat()}),
            status_code=500,
            mimetype="application/json"
        )
EOF
    
    # Create function.json
    cat > "${function_dir}/function.json" << 'EOF'
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["post", "get"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "$return"
    }
  ]
}
EOF
    
    # Create host.json
    cat > "${temp_dir}/host.json" << 'EOF'
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "excludedTypes": "Request"
      }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[2.*, 3.0.0)"
  }
}
EOF
    
    # Create requirements.txt
    cat > "${temp_dir}/requirements.txt" << 'EOF'
azure-functions>=1.11.0
azure-eventgrid>=4.9.0
azure-kusto-data>=3.0.0
EOF
    
    # Create deployment package
    cd "${temp_dir}"
    zip -r function-deployment.zip . > /dev/null
    
    # Deploy function
    az functionapp deployment source config-zip \
        --name "${function_app_name}" \
        --resource-group "${resource_group}" \
        --src function-deployment.zip || error_exit "Failed to deploy function code"
    
    # Cleanup
    rm -rf "${temp_dir}"
    
    log_success "Carbon calculation function deployed successfully"
}

create_iot_device() {
    local iot_hub_name="$1"
    local resource_group="$2"
    local device_id="$3"
    
    log_info "Creating IoT device: ${device_id}"
    
    if [ "${DRY_RUN}" = true ]; then
        log_info "[DRY RUN] Would create IoT device ${device_id}"
        return 0
    fi
    
    if az iot hub device-identity show --hub-name "${iot_hub_name}" --device-id "${device_id}" --resource-group "${resource_group}" &> /dev/null; then
        log_warning "IoT device ${device_id} already exists"
    else
        az iot hub device-identity create \
            --hub-name "${iot_hub_name}" \
            --device-id "${device_id}" \
            --resource-group "${resource_group}" || error_exit "Failed to create IoT device"
        
        log_success "IoT device created: ${device_id}"
    fi
}

send_sample_telemetry() {
    local iot_hub_name="$1"
    local device_id="$2"
    
    log_info "Sending sample telemetry data..."
    
    if [ "${DRY_RUN}" = true ]; then
        log_info "[DRY RUN] Would send sample telemetry data"
        return 0
    fi
    
    # Send sample telemetry data
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local sample_data="{\"deviceId\":\"${device_id}\",\"timestamp\":\"${timestamp}\",\"telemetry\":{\"energyKwh\":15.5,\"productionUnits\":100,\"temperature\":22.5,\"humidity\":45}}"
    
    az iot device send-d2c-message \
        --hub-name "${iot_hub_name}" \
        --device-id "${device_id}" \
        --data "${sample_data}" || log_warning "Failed to send sample telemetry data"
    
    log_success "Sample telemetry data sent"
}

###################################################################################
# Main Deployment Function
###################################################################################

main() {
    local resource_group="${1:-$DEFAULT_RESOURCE_GROUP}"
    local location="${2:-$DEFAULT_LOCATION}"
    
    log_info "Starting Azure Smart Factory Carbon Footprint Monitoring deployment"
    log_info "Resource Group: ${resource_group}"
    log_info "Location: ${location}"
    log_info "Dry Run: ${DRY_RUN}"
    
    # Generate unique suffix for resources
    local random_suffix=$(generate_unique_suffix)
    log_info "Using random suffix: ${random_suffix}"
    
    # Set resource names
    local storage_account_name="stfactory${random_suffix}"
    local iot_hub_name="iothub-factory-${random_suffix}"
    local event_grid_topic="evtgrid-carbon-${random_suffix}"
    local data_explorer_cluster="adx-carbon-${random_suffix}"
    local function_app_name="func-carbon-calc-${random_suffix}"
    local eventhub_namespace="ehns-carbon-${random_suffix}"
    local eventhub_name="carbon-telemetry"
    local device_id="factory-sensor-001"
    
    # Log resource names
    log_info "Resource names:"
    log_info "  Storage Account: ${storage_account_name}"
    log_info "  IoT Hub: ${iot_hub_name}"
    log_info "  Event Grid Topic: ${event_grid_topic}"
    log_info "  Data Explorer Cluster: ${data_explorer_cluster}"
    log_info "  Function App: ${function_app_name}"
    log_info "  Event Hub Namespace: ${eventhub_namespace}"
    log_info "  Device ID: ${device_id}"
    
    # Check prerequisites
    check_prerequisites
    
    # Deploy resources in order
    deploy_resource_group "${resource_group}" "${location}"
    deploy_storage_account "${storage_account_name}" "${resource_group}" "${location}"
    deploy_iot_hub "${iot_hub_name}" "${resource_group}" "${location}"
    deploy_event_grid "${event_grid_topic}" "${resource_group}" "${location}"
    deploy_event_hub "${eventhub_namespace}" "${eventhub_name}" "${resource_group}" "${location}"
    deploy_function_app "${function_app_name}" "${storage_account_name}" "${resource_group}" "${location}"
    configure_function_app "${function_app_name}" "${resource_group}" "${iot_hub_name}" "${event_grid_topic}" "${data_explorer_cluster}"
    deploy_sample_function "${function_app_name}" "${resource_group}"
    deploy_data_explorer "${data_explorer_cluster}" "${resource_group}" "${location}"
    create_iot_device "${iot_hub_name}" "${resource_group}" "${device_id}"
    send_sample_telemetry "${iot_hub_name}" "${device_id}"
    
    # Display deployment summary
    log_success "Deployment completed successfully!"
    echo
    echo "==================================================================="
    echo "              DEPLOYMENT SUMMARY"
    echo "==================================================================="
    echo "Resource Group: ${resource_group}"
    echo "Location: ${location}"
    echo
    echo "Deployed Resources:"
    echo "  ✅ Storage Account: ${storage_account_name}"
    echo "  ✅ IoT Hub: ${iot_hub_name}"
    echo "  ✅ Event Grid Topic: ${event_grid_topic}"
    echo "  ✅ Data Explorer Cluster: ${data_explorer_cluster}"
    echo "  ✅ Function App: ${function_app_name}"
    echo "  ✅ Event Hub Namespace: ${eventhub_namespace}"
    echo "  ✅ IoT Device: ${device_id}"
    echo
    echo "Next Steps:"
    echo "  1. Configure your industrial sensors to connect to IoT Hub"
    echo "  2. Set up carbon emission factors for your specific region"
    echo "  3. Configure sustainability reporting dashboards"
    echo "  4. Enable Azure Sustainability Manager integration"
    echo
    echo "Important Notes:"
    echo "  ⚠️  Data Explorer cluster may take additional time to be fully ready"
    echo "  ⚠️  Azure Sustainability Manager requires preview program enrollment"
    echo "  ⚠️  Remember to configure appropriate access controls for production use"
    echo "==================================================================="
    
    if [ "${DRY_RUN}" = false ]; then
        # Save deployment info for cleanup script
        cat > "${SCRIPT_DIR}/deployment_info.txt" << EOF
RESOURCE_GROUP=${resource_group}
STORAGE_ACCOUNT_NAME=${storage_account_name}
IOT_HUB_NAME=${iot_hub_name}
EVENT_GRID_TOPIC=${event_grid_topic}
DATA_EXPLORER_CLUSTER=${data_explorer_cluster}
FUNCTION_APP_NAME=${function_app_name}
EVENTHUB_NAMESPACE=${eventhub_namespace}
EVENTHUB_NAME=${eventhub_name}
DEVICE_ID=${device_id}
DEPLOYMENT_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
        log_info "Deployment information saved to ${SCRIPT_DIR}/deployment_info.txt"
    fi
}

###################################################################################
# Script Entry Point
###################################################################################

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Deploy Azure Smart Factory Carbon Footprint Monitoring infrastructure"
    echo
    echo "Options:"
    echo "  --dry-run                  Show what would be deployed without making changes"
    echo "  --resource-group NAME      Resource group name (default: ${DEFAULT_RESOURCE_GROUP})"
    echo "  --location LOCATION        Azure region (default: ${DEFAULT_LOCATION})"
    echo "  --help                     Show this help message"
    echo
    echo "Examples:"
    echo "  $0                                    # Deploy with defaults"
    echo "  $0 --dry-run                         # Preview deployment"
    echo "  $0 --resource-group my-rg            # Use custom resource group"
    echo "  $0 --location westus2                # Use different region"
}

# Initialize log file
echo "==================================================================" > "${LOG_FILE}"
echo "Azure Smart Factory Carbon Footprint Monitoring - Deployment Log" >> "${LOG_FILE}"
echo "Start Time: $(date '+%Y-%m-%d %H:%M:%S')" >> "${LOG_FILE}"
echo "==================================================================" >> "${LOG_FILE}"

# Parse command line arguments
RESOURCE_GROUP="${DEFAULT_RESOURCE_GROUP}"
LOCATION="${DEFAULT_LOCATION}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --location)
            LOCATION="$2"
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

# Validate inputs
if [[ -z "${RESOURCE_GROUP}" ]]; then
    error_exit "Resource group name cannot be empty"
fi

if [[ -z "${LOCATION}" ]]; then
    error_exit "Location cannot be empty"
fi

# Run main deployment
main "${RESOURCE_GROUP}" "${LOCATION}"