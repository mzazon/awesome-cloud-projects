#!/bin/bash

# deploy.sh - Deploy Azure IoT Edge Analytics with Azure Percept and Sphere
# This script deploys the complete IoT edge analytics solution including:
# - Azure IoT Hub for device management
# - Azure Sphere device security configuration
# - Azure Percept edge AI processing
# - Azure Stream Analytics for real-time processing
# - Azure Storage for data lake
# - Azure Monitor for alerting

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly LOCK_FILE="${SCRIPT_DIR}/deploy.lock"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default values
DEFAULT_RESOURCE_GROUP="rg-iot-edge-analytics"
DEFAULT_LOCATION="eastus"
DEFAULT_ADMIN_EMAIL="admin@company.com"

# Environment variables with defaults
RESOURCE_GROUP="${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"
LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
ADMIN_EMAIL="${ADMIN_EMAIL:-$DEFAULT_ADMIN_EMAIL}"

# Function to log messages
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to log error messages
error() {
    echo -e "${RED}ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to log success messages
success() {
    echo -e "${GREEN}SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to log warning messages
warning() {
    echo -e "${YELLOW}WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to log info messages
info() {
    echo -e "${BLUE}INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to generate random suffix
generate_suffix() {
    if command_exists openssl; then
        openssl rand -hex 3
    else
        echo "$(date +%s | tail -c 6)"
    fi
}

# Function to validate email format
validate_email() {
    local email="$1"
    if [[ ! $email =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        error "Invalid email format: $email"
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it first."
        error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        return 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv)
    info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        error "Not logged in to Azure. Please run 'az login' first."
        return 1
    fi
    
    # Get current subscription
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    info "Using Azure subscription: $subscription_id"
    
    # Validate email
    validate_email "$ADMIN_EMAIL"
    
    # Check if IoT extension is available
    if ! az extension show --name azure-iot >/dev/null 2>&1; then
        info "Installing Azure IoT extension..."
        az extension add --name azure-iot --yes
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    info "Setting environment variables..."
    
    # Generate unique suffix for resources
    local random_suffix
    random_suffix=$(generate_suffix)
    
    # Export environment variables
    export RESOURCE_GROUP="$RESOURCE_GROUP"
    export LOCATION="$LOCATION"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export IOT_HUB_NAME="${IOT_HUB_NAME:-iot-hub-$random_suffix}"
    export STREAM_JOB_NAME="${STREAM_JOB_NAME:-stream-analytics-$random_suffix}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stiot$random_suffix}"
    export DEVICE_ID="${DEVICE_ID:-percept-device-01}"
    export SPHERE_DEVICE_ID="${SPHERE_DEVICE_ID:-sphere-device-01}"
    export RANDOM_SUFFIX="$random_suffix"
    
    info "Environment variables configured:"
    info "  RESOURCE_GROUP: $RESOURCE_GROUP"
    info "  LOCATION: $LOCATION"
    info "  IOT_HUB_NAME: $IOT_HUB_NAME"
    info "  STORAGE_ACCOUNT: $STORAGE_ACCOUNT"
    info "  RANDOM_SUFFIX: $RANDOM_SUFFIX"
    
    success "Environment variables set"
}

# Function to create resource group
create_resource_group() {
    info "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warning "Resource group '$RESOURCE_GROUP' already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=iot-edge-analytics environment=production \
            --output none
        success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create storage account
create_storage_account() {
    info "Creating storage account with Data Lake capabilities..."
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warning "Storage account '$STORAGE_ACCOUNT' already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --hierarchical-namespace true \
            --output none
        success "Storage account created with Data Lake capabilities"
    fi
}

# Function to create IoT Hub
create_iot_hub() {
    info "Creating IoT Hub for device management: $IOT_HUB_NAME"
    
    if az iot hub show --name "$IOT_HUB_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warning "IoT Hub '$IOT_HUB_NAME' already exists"
    else
        az iot hub create \
            --name "$IOT_HUB_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku S1 \
            --partition-count 4 \
            --retention-days 7 \
            --output none
        success "IoT Hub created with connection string configured"
    fi
    
    # Get IoT Hub connection string
    export IOT_HUB_CONNECTION_STRING=$(az iot hub connection-string show \
        --hub-name "$IOT_HUB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    info "IoT Hub connection string configured"
}

# Function to configure Azure Sphere device
configure_sphere_device() {
    info "Configuring Azure Sphere device security: $SPHERE_DEVICE_ID"
    
    # Create Azure Sphere device identity
    if az iot hub device-identity show --hub-name "$IOT_HUB_NAME" --device-id "$SPHERE_DEVICE_ID" >/dev/null 2>&1; then
        warning "Azure Sphere device '$SPHERE_DEVICE_ID' already exists"
    else
        az iot hub device-identity create \
            --hub-name "$IOT_HUB_NAME" \
            --device-id "$SPHERE_DEVICE_ID" \
            --auth-method x509_thumbprint \
            --output none
        success "Azure Sphere device identity created"
    fi
    
    # Generate device certificate for secure authentication
    az iot hub device-identity export \
        --hub-name "$IOT_HUB_NAME" \
        --device-id "$SPHERE_DEVICE_ID" \
        --output json > "${SCRIPT_DIR}/sphere-device-cert.json"
    
    # Configure device twin for Azure Sphere
    az iot hub device-twin update \
        --hub-name "$IOT_HUB_NAME" \
        --device-id "$SPHERE_DEVICE_ID" \
        --set properties.desired.telemetryConfig.sendFrequency=30s \
        --output none
    
    success "Azure Sphere device configured with X.509 certificate authentication"
}

# Function to deploy Azure Percept for edge AI processing
deploy_percept_edge_ai() {
    info "Deploying Azure Percept for edge AI processing: $DEVICE_ID"
    
    # Create Azure Percept device identity
    if az iot hub device-identity show --hub-name "$IOT_HUB_NAME" --device-id "$DEVICE_ID" >/dev/null 2>&1; then
        warning "Azure Percept device '$DEVICE_ID' already exists"
    else
        az iot hub device-identity create \
            --hub-name "$IOT_HUB_NAME" \
            --device-id "$DEVICE_ID" \
            --auth-method shared_private_key \
            --output none
        success "Azure Percept device identity created"
    fi
    
    # Get device connection string
    export DEVICE_CONNECTION_STRING=$(az iot hub device-identity connection-string show \
        --hub-name "$IOT_HUB_NAME" \
        --device-id "$DEVICE_ID" \
        --query connectionString --output tsv)
    
    # Configure edge modules for Percept
    local edge_config='{
        "modulesContent": {
            "$edgeAgent": {
                "properties.desired": {
                    "schemaVersion": "1.1",
                    "runtime": {
                        "type": "docker",
                        "settings": {
                            "minDockerVersion": "v1.25"
                        }
                    },
                    "systemModules": {
                        "edgeAgent": {
                            "type": "docker",
                            "settings": {
                                "image": "mcr.microsoft.com/azureiotedge-agent:1.4",
                                "createOptions": "{}"
                            }
                        },
                        "edgeHub": {
                            "type": "docker",
                            "status": "running",
                            "restartPolicy": "always",
                            "settings": {
                                "image": "mcr.microsoft.com/azureiotedge-hub:1.4",
                                "createOptions": "{\"HostConfig\":{\"PortBindings\":{\"5671/tcp\":[{\"HostPort\":\"5671\"}],\"8883/tcp\":[{\"HostPort\":\"8883\"}],\"443/tcp\":[{\"HostPort\":\"443\"}]}}}"
                            }
                        }
                    }
                }
            }
        }
    }'
    
    echo "$edge_config" > "${SCRIPT_DIR}/edge-config.json"
    
    az iot edge set-modules \
        --hub-name "$IOT_HUB_NAME" \
        --device-id "$DEVICE_ID" \
        --content "${SCRIPT_DIR}/edge-config.json" \
        --output none
    
    success "Azure Percept configured for edge AI processing"
}

# Function to create Stream Analytics job
create_stream_analytics_job() {
    info "Creating Stream Analytics job for real-time processing: $STREAM_JOB_NAME"
    
    if az stream-analytics job show --resource-group "$RESOURCE_GROUP" --name "$STREAM_JOB_NAME" >/dev/null 2>&1; then
        warning "Stream Analytics job '$STREAM_JOB_NAME' already exists"
    else
        az stream-analytics job create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$STREAM_JOB_NAME" \
            --location "$LOCATION" \
            --output-error-policy "Stop" \
            --out-of-order-policy "Adjust" \
            --output-start-mode "JobStartTime" \
            --compatibility-level "1.2" \
            --data-locale "en-US" \
            --events-late-arrival-max-delay 5 \
            --events-out-of-order-max-delay 0 \
            --output none
        success "Stream Analytics job created"
    fi
    
    # Configure IoT Hub input for Stream Analytics
    local iot_hub_key
    iot_hub_key=$(az iot hub policy show --hub-name "$IOT_HUB_NAME" --name iothubowner --query primaryKey --output tsv)
    
    local input_config='{
        "type": "Microsoft.Devices/IotHubs",
        "properties": {
            "iotHubNamespace": "'$IOT_HUB_NAME'",
            "sharedAccessPolicyName": "iothubowner",
            "sharedAccessPolicyKey": "'$iot_hub_key'",
            "endpoint": "messages/events",
            "consumerGroupName": "$Default"
        }
    }'
    
    local serialization_config='{
        "type": "Json",
        "properties": {
            "encoding": "UTF8"
        }
    }'
    
    az stream-analytics input create \
        --resource-group "$RESOURCE_GROUP" \
        --job-name "$STREAM_JOB_NAME" \
        --name "IoTHubInput" \
        --type "Stream" \
        --datasource "$input_config" \
        --serialization "$serialization_config" \
        --output none
    
    success "Stream Analytics job created with IoT Hub input"
}

# Function to configure storage output for data lake
configure_storage_output() {
    info "Configuring storage output for data lake integration"
    
    # Get storage account key
    local storage_key
    storage_key=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT" \
        --query '[0].value' --output tsv)
    
    # Create container for processed data
    az storage container create \
        --name "processed-telemetry" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" \
        --output none
    
    # Configure storage output for Stream Analytics
    local output_config='{
        "type": "Microsoft.Storage/Blob",
        "properties": {
            "storageAccounts": [{
                "accountName": "'$STORAGE_ACCOUNT'",
                "accountKey": "'$storage_key'"
            }],
            "container": "processed-telemetry",
            "pathPattern": "year={datetime:yyyy}/month={datetime:MM}/day={datetime:dd}/hour={datetime:HH}",
            "dateFormat": "yyyy/MM/dd",
            "timeFormat": "HH"
        }
    }'
    
    local serialization_config='{
        "type": "Json",
        "properties": {
            "encoding": "UTF8",
            "format": "LineSeparated"
        }
    }'
    
    az stream-analytics output create \
        --resource-group "$RESOURCE_GROUP" \
        --job-name "$STREAM_JOB_NAME" \
        --name "StorageOutput" \
        --datasource "$output_config" \
        --serialization "$serialization_config" \
        --output none
    
    success "Storage output configured for data lake integration"
}

# Function to deploy Stream Analytics query
deploy_stream_analytics_query() {
    info "Deploying Stream Analytics query for edge analytics"
    
    local query="
    WITH AnomalyDetection AS (
        SELECT
            deviceId,
            timestamp,
            temperature,
            humidity,
            vibration,
            AnomalyDetection_SpikeAndDip(temperature, 95, 120, 'spikesanddips')
                OVER(LIMIT DURATION(minute, 2)) AS temperatureAnomaly,
            AnomalyDetection_SpikeAndDip(vibration, 95, 120, 'spikesanddips')
                OVER(LIMIT DURATION(minute, 2)) AS vibrationAnomaly
        FROM IoTHubInput
        WHERE deviceId IN ('$DEVICE_ID', '$SPHERE_DEVICE_ID')
    ),
    AggregatedData AS (
        SELECT
            deviceId,
            System.Timestamp AS windowEnd,
            AVG(temperature) AS avgTemperature,
            MAX(temperature) AS maxTemperature,
            AVG(humidity) AS avgHumidity,
            AVG(vibration) AS avgVibration,
            COUNT(*) AS messageCount
        FROM IoTHubInput
        WHERE deviceId IN ('$DEVICE_ID', '$SPHERE_DEVICE_ID')
        GROUP BY deviceId, TumblingWindow(minute, 5)
    )
    SELECT
        ad.deviceId,
        ad.timestamp,
        ad.temperature,
        ad.humidity,
        ad.vibration,
        ad.temperatureAnomaly,
        ad.vibrationAnomaly,
        ag.avgTemperature,
        ag.maxTemperature,
        ag.avgHumidity,
        ag.avgVibration,
        ag.messageCount
    INTO StorageOutput
    FROM AnomalyDetection ad
    JOIN AggregatedData ag ON ad.deviceId = ag.deviceId
    WHERE ad.temperatureAnomaly.IsAnomaly = 1 OR ad.vibrationAnomaly.IsAnomaly = 1
    "
    
    az stream-analytics transformation create \
        --resource-group "$RESOURCE_GROUP" \
        --job-name "$STREAM_JOB_NAME" \
        --name "ProcessTelemetry" \
        --saql "$query" \
        --output none
    
    success "Stream Analytics query deployed for anomaly detection"
}

# Function to start Stream Analytics job
start_stream_analytics_job() {
    info "Starting Stream Analytics job for real-time processing"
    
    az stream-analytics job start \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STREAM_JOB_NAME" \
        --output-start-mode "JobStartTime" \
        --output none
    
    # Monitor job status
    az stream-analytics job show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STREAM_JOB_NAME" \
        --query '{name:name, state:jobState, createdDate:createdDate}' \
        --output table
    
    success "Stream Analytics job started and processing telemetry data"
}

# Function to configure Azure Monitor
configure_azure_monitor() {
    info "Configuring Azure Monitor for alerting"
    
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    
    # Create action group for notifications
    az monitor action-group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "IoTAlertsActionGroup" \
        --short-name "IoTAlerts" \
        --email-receiver name="AdminEmail" email="$ADMIN_EMAIL" \
        --output none
    
    # Create alert rule for Stream Analytics failures
    az monitor metrics alert create \
        --resource-group "$RESOURCE_GROUP" \
        --name "StreamAnalyticsFailureAlert" \
        --scopes "/subscriptions/$subscription_id/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.StreamAnalytics/streamingjobs/$STREAM_JOB_NAME" \
        --condition "count Microsoft.StreamAnalytics/streamingjobs RuntimeErrors > 0" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --action-group "IoTAlertsActionGroup" \
        --description "Alert when Stream Analytics job encounters runtime errors" \
        --output none
    
    # Create alert rule for device connectivity
    az monitor metrics alert create \
        --resource-group "$RESOURCE_GROUP" \
        --name "DeviceConnectivityAlert" \
        --scopes "/subscriptions/$subscription_id/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Devices/IotHubs/$IOT_HUB_NAME" \
        --condition "count Microsoft.Devices/IotHubs ConnectedDeviceCount < 2" \
        --window-size 10m \
        --evaluation-frequency 5m \
        --action-group "IoTAlertsActionGroup" \
        --description "Alert when device count drops below expected threshold" \
        --output none
    
    success "Azure Monitor alerts configured for proactive monitoring"
}

# Function to display deployment summary
display_deployment_summary() {
    success "Deployment completed successfully!"
    echo ""
    echo "=================== DEPLOYMENT SUMMARY ==================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "IoT Hub: $IOT_HUB_NAME"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Stream Analytics Job: $STREAM_JOB_NAME"
    echo "Azure Sphere Device: $SPHERE_DEVICE_ID"
    echo "Azure Percept Device: $DEVICE_ID"
    echo "Admin Email: $ADMIN_EMAIL"
    echo "==========================================================="
    echo ""
    echo "Next Steps:"
    echo "1. Connect your Azure Sphere device using the certificate:"
    echo "   ${SCRIPT_DIR}/sphere-device-cert.json"
    echo "2. Configure your Azure Percept device with the connection string"
    echo "3. Deploy AI models to Azure Percept for edge inference"
    echo "4. Monitor telemetry data in Azure IoT Hub"
    echo "5. View processed data in Storage Account: $STORAGE_ACCOUNT"
    echo ""
    echo "Documentation:"
    echo "- Azure Sphere: https://docs.microsoft.com/azure-sphere/"
    echo "- Azure Percept: https://docs.microsoft.com/azure-percept/"
    echo "- IoT Hub: https://docs.microsoft.com/azure/iot-hub/"
    echo "==========================================================="
}

# Function to cleanup on exit
cleanup() {
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
    fi
    if [[ -f "${SCRIPT_DIR}/edge-config.json" ]]; then
        rm -f "${SCRIPT_DIR}/edge-config.json"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy Azure IoT Edge Analytics with Azure Percept and Sphere"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group NAME    Resource group name (default: $DEFAULT_RESOURCE_GROUP)"
    echo "  -l, --location LOCATION      Azure region (default: $DEFAULT_LOCATION)"
    echo "  -e, --email EMAIL           Admin email for alerts (default: $DEFAULT_ADMIN_EMAIL)"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  RESOURCE_GROUP              Override resource group name"
    echo "  LOCATION                    Override Azure region"
    echo "  ADMIN_EMAIL                 Override admin email"
    echo "  IOT_HUB_NAME               Override IoT Hub name"
    echo "  STORAGE_ACCOUNT            Override storage account name"
    echo "  STREAM_JOB_NAME            Override Stream Analytics job name"
    echo ""
    echo "Examples:"
    echo "  $0 -g my-iot-rg -l westus2 -e admin@mycompany.com"
    echo "  RESOURCE_GROUP=my-iot-rg $0"
    echo "  $0 --help"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -e|--email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    # Check for lock file
    if [[ -f "$LOCK_FILE" ]]; then
        error "Another deployment is already in progress. Remove $LOCK_FILE if this is not the case."
        exit 1
    fi
    
    # Create lock file
    touch "$LOCK_FILE"
    
    # Set trap to cleanup on exit
    trap cleanup EXIT
    
    # Start deployment
    info "Starting deployment of Azure IoT Edge Analytics solution"
    info "Log file: $LOG_FILE"
    
    # Execute deployment steps following the recipe
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_storage_account
    create_iot_hub
    configure_sphere_device
    deploy_percept_edge_ai
    create_stream_analytics_job
    configure_storage_output
    deploy_stream_analytics_query
    start_stream_analytics_job
    configure_azure_monitor
    display_deployment_summary
    
    # Remove lock file
    rm -f "$LOCK_FILE"
    
    success "Deployment completed successfully!"
    info "You can now connect your Azure Sphere and Azure Percept devices to start processing IoT data"
}

# Execute main function
main "$@"