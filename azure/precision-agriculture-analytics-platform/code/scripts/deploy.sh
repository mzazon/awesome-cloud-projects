#!/bin/bash

# ==============================================================================
# Azure Precision Agriculture Analytics Deployment Script
# ==============================================================================
# This script deploys a comprehensive precision agriculture platform using:
# - Azure Data Manager for Agriculture
# - Azure AI Services
# - Azure Maps
# - Azure Stream Analytics
# - Azure IoT Hub
# - Azure Storage
# - Azure Functions
# ==============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/../deploy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/../deploy_errors.log"

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
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial deployment..."
    if [[ -n "${RESOURCE_GROUP:-}" ]] && az group exists --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} exists. Run destroy.sh to clean up manually."
    fi
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: ${az_version}"
    
    # Check if logged in
    if ! az account show &>/dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required extensions are available
    log_info "Checking Azure CLI extensions..."
    
    # Note: Azure Data Manager for Agriculture may require preview extension
    if ! az extension list --query "[?name=='datamgr-for-agriculture']" -o tsv | grep -q datamgr-for-agriculture; then
        log_warning "Azure Data Manager for Agriculture extension not installed. Installing..."
        az extension add --name datamgr-for-agriculture --allow-preview || {
            log_error "Failed to install Azure Data Manager for Agriculture extension. This may be a preview service requiring registration."
            log_error "Please visit https://aka.ms/agridatamanager to register for preview access."
            exit 1
        }
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random strings. Please install openssl."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Configuration setup
setup_configuration() {
    log_info "Setting up configuration..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-precision-ag-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names with agriculture-specific prefixes
    export ADMA_INSTANCE="adma-farm-${RANDOM_SUFFIX}"
    export IOT_HUB_NAME="iothub-farm-${RANDOM_SUFFIX}"
    export STREAM_JOB_NAME="stream-farm-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stfarm${RANDOM_SUFFIX}"
    export AI_SERVICES_NAME="ai-farm-${RANDOM_SUFFIX}"
    export MAPS_ACCOUNT="maps-farm-${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="func-crop-analysis-${RANDOM_SUFFIX}"
    
    # Generate farm and field IDs
    export FARM_ID="demo-farm-$(date +%s)"
    export FIELD_ID="field-north-40-$(date +%s)"
    
    log_info "Configuration setup completed"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=precision-agriculture environment=demo \
               industry=agriculture workload=analytics \
        || {
            log_error "Failed to create resource group"
            exit 1
        }
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

# Create storage account
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT}"
    
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --tags purpose=agricultural-data \
        || {
            log_error "Failed to create storage account"
            exit 1
        }
    
    # Get storage account key
    export STORAGE_KEY=$(az storage account keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --account-name "${STORAGE_ACCOUNT}" \
        --query '[0].value' --output tsv)
    
    log_success "Storage account created: ${STORAGE_ACCOUNT}"
}

# Create storage containers
create_storage_containers() {
    log_info "Creating storage containers for agricultural data..."
    
    local containers=("crop-imagery" "field-boundaries" "weather-data" "analytics-results")
    
    for container in "${containers[@]}"; do
        az storage container create \
            --name "${container}" \
            --account-name "${STORAGE_ACCOUNT}" \
            --account-key "${STORAGE_KEY}" \
            --public-access off \
            || {
                log_error "Failed to create storage container: ${container}"
                exit 1
            }
        log_info "Created container: ${container}"
    done
    
    log_success "Storage containers created"
}

# Deploy Azure Data Manager for Agriculture
deploy_data_manager() {
    log_info "Deploying Azure Data Manager for Agriculture: ${ADMA_INSTANCE}"
    
    # Create Azure Data Manager for Agriculture instance
    az datamgr-for-agriculture create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${ADMA_INSTANCE}" \
        --location "${LOCATION}" \
        --sku Standard \
        --tags farm-type=mixed-crop season=2025 \
        || {
            log_error "Failed to create Azure Data Manager for Agriculture instance"
            log_error "This may be due to preview access requirements. Please ensure you have registered for preview access."
            exit 1
        }
    
    # Wait for deployment to complete
    log_info "Waiting for Data Manager deployment to complete..."
    local max_attempts=30
    local attempt=0
    
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        local state=$(az datamgr-for-agriculture show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${ADMA_INSTANCE}" \
            --query "properties.provisioningState" --output tsv 2>/dev/null || echo "NotFound")
        
        if [[ "${state}" == "Succeeded" ]]; then
            break
        elif [[ "${state}" == "Failed" ]]; then
            log_error "Data Manager deployment failed"
            exit 1
        fi
        
        log_info "Data Manager provisioning state: ${state}. Waiting..."
        sleep 30
        ((attempt++))
    done
    
    if [[ ${attempt} -eq ${max_attempts} ]]; then
        log_error "Data Manager deployment timed out"
        exit 1
    fi
    
    # Get the service endpoint
    export ADMA_ENDPOINT=$(az datamgr-for-agriculture show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${ADMA_INSTANCE}" \
        --query properties.instanceUri --output tsv)
    
    log_success "Azure Data Manager for Agriculture deployed: ${ADMA_ENDPOINT}"
}

# Deploy IoT Hub
deploy_iot_hub() {
    log_info "Creating IoT Hub: ${IOT_HUB_NAME}"
    
    az iot hub create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${IOT_HUB_NAME}" \
        --location "${LOCATION}" \
        --sku S1 \
        --partition-count 4 \
        --tags purpose=farm-sensors data-type=telemetry \
        || {
            log_error "Failed to create IoT Hub"
            exit 1
        }
    
    # Get IoT Hub connection string
    export IOT_CONNECTION_STRING=$(az iot hub connection-string show \
        --hub-name "${IOT_HUB_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString --output tsv)
    
    # Create a sample IoT device
    az iot hub device-identity create \
        --hub-name "${IOT_HUB_NAME}" \
        --device-id soil-sensor-field-01 \
        --edge-enabled false \
        || {
            log_error "Failed to create IoT device"
            exit 1
        }
    
    log_success "IoT Hub configured: ${IOT_HUB_NAME}"
}

# Deploy Azure AI Services
deploy_ai_services() {
    log_info "Creating Azure AI Services: ${AI_SERVICES_NAME}"
    
    az cognitiveservices account create \
        --name "${AI_SERVICES_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --kind CognitiveServices \
        --sku S0 \
        --custom-domain "${AI_SERVICES_NAME}" \
        --tags purpose=crop-analysis service=computer-vision \
        || {
            log_error "Failed to create Azure AI Services"
            exit 1
        }
    
    # Get the AI Services key and endpoint
    export AI_SERVICES_KEY=$(az cognitiveservices account keys list \
        --name "${AI_SERVICES_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 --output tsv)
    
    export AI_SERVICES_ENDPOINT=$(az cognitiveservices account show \
        --name "${AI_SERVICES_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.endpoint --output tsv)
    
    log_success "Azure AI Services deployed: ${AI_SERVICES_ENDPOINT}"
}

# Deploy Azure Maps
deploy_azure_maps() {
    log_info "Creating Azure Maps account: ${MAPS_ACCOUNT}"
    
    az maps account create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${MAPS_ACCOUNT}" \
        --location "${LOCATION}" \
        --sku S1 \
        --tags purpose=field-mapping service=geospatial \
        || {
            log_error "Failed to create Azure Maps account"
            exit 1
        }
    
    # Get Azure Maps primary key
    export MAPS_KEY=$(az maps account keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${MAPS_ACCOUNT}" \
        --query primaryKey --output tsv)
    
    log_success "Azure Maps account created: ${MAPS_ACCOUNT}"
}

# Deploy Stream Analytics
deploy_stream_analytics() {
    log_info "Creating Stream Analytics job: ${STREAM_JOB_NAME}"
    
    az stream-analytics job create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${STREAM_JOB_NAME}" \
        --location "${LOCATION}" \
        --output-error-policy stop \
        --events-out-of-order-policy adjust \
        --events-out-of-order-max-delay 10 \
        --events-late-arrival-max-delay 5 \
        || {
            log_error "Failed to create Stream Analytics job"
            exit 1
        }
    
    # Get IoT Hub policy key for Stream Analytics input
    local iot_policy_key=$(az iot hub policy show \
        --hub-name "${IOT_HUB_NAME}" \
        --name iothubowner \
        --query primaryKey -o tsv)
    
    # Configure IoT Hub as input source
    az stream-analytics input create \
        --resource-group "${RESOURCE_GROUP}" \
        --job-name "${STREAM_JOB_NAME}" \
        --name SensorInput \
        --type Stream \
        --datasource "{
            \"type\": \"Microsoft.Devices/IotHubs\",
            \"properties\": {
                \"iotHubNamespace\": \"${IOT_HUB_NAME}\",
                \"sharedAccessPolicyName\": \"iothubowner\",
                \"sharedAccessPolicyKey\": \"${iot_policy_key}\",
                \"endpoint\": \"messages/events\"
            }
        }" \
        --serialization "{
            \"type\": \"Json\",
            \"properties\": {\"encoding\": \"UTF8\"}
        }" \
        || {
            log_error "Failed to configure Stream Analytics input"
            exit 1
        }
    
    log_success "Stream Analytics job configured: ${STREAM_JOB_NAME}"
}

# Deploy Azure Functions
deploy_azure_functions() {
    log_info "Creating Azure Function App: ${FUNCTION_APP_NAME}"
    
    az functionapp create \
        --resource-group "${RESOURCE_GROUP}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime python \
        --runtime-version 3.9 \
        --functions-version 4 \
        --name "${FUNCTION_APP_NAME}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --tags purpose=image-analysis automation=crop-health \
        || {
            log_error "Failed to create Azure Function App"
            exit 1
        }
    
    # Configure function app settings
    az functionapp config appsettings set \
        --name "${FUNCTION_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
            "AI_SERVICES_ENDPOINT=${AI_SERVICES_ENDPOINT}" \
            "AI_SERVICES_KEY=${AI_SERVICES_KEY}" \
            "STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT};AccountKey=${STORAGE_KEY};EndpointSuffix=core.windows.net" \
            "ADMA_ENDPOINT=${ADMA_ENDPOINT}" \
        || {
            log_error "Failed to configure Function App settings"
            exit 1
        }
    
    log_success "Azure Function App configured: ${FUNCTION_APP_NAME}"
}

# Configure farm entities
configure_farm_entities() {
    log_info "Configuring farm and field entities in Data Manager..."
    
    # Get access token for API calls
    local access_token=$(az account get-access-token --query accessToken -o tsv)
    
    # Create farm entity
    local farm_response
    farm_response=$(curl -s -w "%{http_code}" -X POST "${ADMA_ENDPOINT}/farmers/${FARM_ID}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${access_token}" \
        -d "{
            \"name\": \"Demo Precision Farm\",
            \"description\": \"Sample farm for precision agriculture analytics\",
            \"status\": \"Active\",
            \"properties\": {
                \"totalArea\": 1000,
                \"cropTypes\": [\"corn\", \"soybeans\"],
                \"farmingMethod\": \"precision\"
            }
        }")
    
    local farm_http_code="${farm_response: -3}"
    if [[ "${farm_http_code}" =~ ^20[0-9]$ ]]; then
        log_success "Farm entity created: ${FARM_ID}"
    else
        log_warning "Farm entity creation returned HTTP ${farm_http_code}. This may be expected for demo purposes."
    fi
    
    # Create field entity
    local field_response
    field_response=$(curl -s -w "%{http_code}" -X POST "${ADMA_ENDPOINT}/farmers/${FARM_ID}/fields/${FIELD_ID}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${access_token}" \
        -d "{
            \"name\": \"North 40 Field\",
            \"farmerId\": \"${FARM_ID}\",
            \"area\": 40,
            \"cropType\": \"corn\",
            \"properties\": {
                \"soilType\": \"loam\",
                \"drainageClass\": \"well-drained\",
                \"slope\": \"gentle\"
            }
        }")
    
    local field_http_code="${field_response: -3}"
    if [[ "${field_http_code}" =~ ^20[0-9]$ ]]; then
        log_success "Field entity created: ${FIELD_ID}"
    else
        log_warning "Field entity creation returned HTTP ${field_http_code}. This may be expected for demo purposes."
    fi
}

# Save deployment configuration
save_deployment_config() {
    log_info "Saving deployment configuration..."
    
    local config_file="${SCRIPT_DIR}/../deployment_config.env"
    
    cat > "${config_file}" << EOF
# Azure Precision Agriculture Analytics Deployment Configuration
# Generated on $(date)

RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}

# Service Names
ADMA_INSTANCE=${ADMA_INSTANCE}
IOT_HUB_NAME=${IOT_HUB_NAME}
STREAM_JOB_NAME=${STREAM_JOB_NAME}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
AI_SERVICES_NAME=${AI_SERVICES_NAME}
MAPS_ACCOUNT=${MAPS_ACCOUNT}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}

# Service Endpoints and Keys
ADMA_ENDPOINT=${ADMA_ENDPOINT}
AI_SERVICES_ENDPOINT=${AI_SERVICES_ENDPOINT}
AI_SERVICES_KEY=${AI_SERVICES_KEY}
MAPS_KEY=${MAPS_KEY}
STORAGE_KEY=${STORAGE_KEY}

# Demo Entities
FARM_ID=${FARM_ID}
FIELD_ID=${FIELD_ID}
EOF
    
    log_success "Deployment configuration saved to: ${config_file}"
}

# Validation function
validate_deployment() {
    log_info "Validating deployment..."
    
    local validation_errors=0
    
    # Check resource group
    if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_error "Resource group validation failed: ${RESOURCE_GROUP}"
        ((validation_errors++))
    fi
    
    # Check Data Manager
    local adma_state=$(az datamgr-for-agriculture show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${ADMA_INSTANCE}" \
        --query "properties.provisioningState" --output tsv 2>/dev/null || echo "NotFound")
    
    if [[ "${adma_state}" != "Succeeded" ]]; then
        log_error "Data Manager validation failed. State: ${adma_state}"
        ((validation_errors++))
    fi
    
    # Check IoT Hub
    if ! az iot hub show --name "${IOT_HUB_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_error "IoT Hub validation failed: ${IOT_HUB_NAME}"
        ((validation_errors++))
    fi
    
    # Check AI Services
    if ! az cognitiveservices account show --name "${AI_SERVICES_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_error "AI Services validation failed: ${AI_SERVICES_NAME}"
        ((validation_errors++))
    fi
    
    # Check Storage Account
    if ! az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_error "Storage Account validation failed: ${STORAGE_ACCOUNT}"
        ((validation_errors++))
    fi
    
    # Check Stream Analytics
    if ! az stream-analytics job show --name "${STREAM_JOB_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_error "Stream Analytics validation failed: ${STREAM_JOB_NAME}"
        ((validation_errors++))
    fi
    
    # Check Azure Maps
    if ! az maps account show --name "${MAPS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_error "Azure Maps validation failed: ${MAPS_ACCOUNT}"
        ((validation_errors++))
    fi
    
    # Check Function App
    if ! az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_error "Function App validation failed: ${FUNCTION_APP_NAME}"
        ((validation_errors++))
    fi
    
    if [[ ${validation_errors} -eq 0 ]]; then
        log_success "All resources validated successfully"
        return 0
    else
        log_error "Validation failed with ${validation_errors} errors"
        return 1
    fi
}

# Display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "===========================================" | tee -a "${LOG_FILE}"
    echo "Azure Precision Agriculture Analytics Platform" | tee -a "${LOG_FILE}"
    echo "===========================================" | tee -a "${LOG_FILE}"
    echo "Resource Group: ${RESOURCE_GROUP}" | tee -a "${LOG_FILE}"
    echo "Location: ${LOCATION}" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "Deployed Services:" | tee -a "${LOG_FILE}"
    echo "- Azure Data Manager for Agriculture: ${ADMA_INSTANCE}" | tee -a "${LOG_FILE}"
    echo "- IoT Hub: ${IOT_HUB_NAME}" | tee -a "${LOG_FILE}"
    echo "- AI Services: ${AI_SERVICES_NAME}" | tee -a "${LOG_FILE}"
    echo "- Azure Maps: ${MAPS_ACCOUNT}" | tee -a "${LOG_FILE}"
    echo "- Stream Analytics: ${STREAM_JOB_NAME}" | tee -a "${LOG_FILE}"
    echo "- Storage Account: ${STORAGE_ACCOUNT}" | tee -a "${LOG_FILE}"
    echo "- Function App: ${FUNCTION_APP_NAME}" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "Important URLs and Information:" | tee -a "${LOG_FILE}"
    echo "- Data Manager Endpoint: ${ADMA_ENDPOINT}" | tee -a "${LOG_FILE}"
    echo "- AI Services Endpoint: ${AI_SERVICES_ENDPOINT}" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "Configuration saved to: ${SCRIPT_DIR}/../deployment_config.env" | tee -a "${LOG_FILE}"
    echo "===========================================" | tee -a "${LOG_FILE}"
}

# Main deployment function
main() {
    log_info "Starting Azure Precision Agriculture Analytics deployment..."
    
    # Clear previous logs
    > "${LOG_FILE}"
    > "${ERROR_LOG}"
    
    check_prerequisites
    setup_configuration
    create_resource_group
    create_storage_account
    create_storage_containers
    deploy_data_manager
    deploy_iot_hub
    deploy_ai_services
    deploy_azure_maps
    deploy_stream_analytics
    deploy_azure_functions
    configure_farm_entities
    save_deployment_config
    
    if validate_deployment; then
        display_summary
        log_success "Deployment completed successfully!"
        echo ""
        echo -e "${GREEN}Next steps:${NC}"
        echo "1. Review the deployment configuration in deployment_config.env"
        echo "2. Start the Stream Analytics job when ready to process IoT data"
        echo "3. Upload sample agricultural imagery to test the computer vision pipeline"
        echo "4. Use the Azure portal to monitor resource usage and costs"
        echo ""
        echo -e "${YELLOW}Cost Management:${NC}"
        echo "- Monitor costs regularly through Azure Cost Management"
        echo "- Consider stopping Stream Analytics when not actively testing"
        echo "- Review and optimize SKUs based on actual usage patterns"
        echo ""
        echo -e "${BLUE}To clean up resources, run: ./destroy.sh${NC}"
    else
        log_error "Deployment validation failed. Please check the error log for details."
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi