#!/bin/bash

# deploy.sh - Azure IoT Edge Real-Time Anomaly Detection Deployment Script
# This script deploys the complete infrastructure for real-time anomaly detection
# using Azure IoT Edge and Azure Machine Learning

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
error_exit() {
    log_error "Deployment failed: $1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Cleaning up partial deployment..."
    # This will be called if script fails
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log "Attempting to delete resource group: ${RESOURCE_GROUP}"
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait || true
    fi
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --output json | jq -r '.["azure-cli"]')
    log "Azure CLI version: $az_version"
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        error_exit "Not logged into Azure. Please run 'az login' first"
    fi
    
    # Check required tools
    local required_tools=("jq" "openssl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error_exit "$tool is not installed. Please install it first"
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Function to validate Azure subscription
validate_subscription() {
    log "Validating Azure subscription..."
    
    local subscription_id=$(az account show --query id --output tsv)
    local subscription_name=$(az account show --query name --output tsv)
    
    log "Current subscription: $subscription_name ($subscription_id)"
    
    # Check if subscription supports required services
    local required_providers=("Microsoft.Devices" "Microsoft.MachineLearningServices" "Microsoft.Storage" "Microsoft.StreamAnalytics")
    
    for provider in "${required_providers[@]}"; do
        local status=$(az provider show --namespace "$provider" --query registrationState --output tsv)
        if [[ "$status" != "Registered" ]]; then
            log "Registering provider: $provider"
            az provider register --namespace "$provider" --wait
        fi
    done
    
    log_success "Subscription validation completed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resources
    local unique_suffix=$(openssl rand -hex 3)
    
    # Set required environment variables
    export RESOURCE_GROUP="rg-anomaly-detection-${unique_suffix}"
    export LOCATION="${LOCATION:-eastus}"
    export IOT_HUB_NAME="iot-hub-anomaly-${unique_suffix}"
    export STORAGE_ACCOUNT="stanomalydata${unique_suffix}"
    export ML_WORKSPACE="ml-anomaly-detection-${unique_suffix}"
    export EDGE_DEVICE_ID="factory-edge-device-01"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export ASA_JOB_NAME="asa-edge-anomaly-job-${unique_suffix}"
    export LOG_WORKSPACE="log-anomaly-detection-${unique_suffix}"
    
    # Create deployment log file
    export DEPLOYMENT_LOG="deployment_$(date +%Y%m%d_%H%M%S).log"
    
    log_success "Environment variables set"
    log "Resource Group: $RESOURCE_GROUP"
    log "Location: $LOCATION"
    log "IoT Hub: $IOT_HUB_NAME"
    log "Storage Account: $STORAGE_ACCOUNT"
    log "ML Workspace: $ML_WORKSPACE"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=anomaly-detection environment=demo created-by=deploy-script \
        --output none
    
    log_success "Resource group created: $RESOURCE_GROUP"
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account..."
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Storage account $STORAGE_ACCOUNT already exists"
        return 0
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --hierarchical-namespace true \
        --output none
    
    # Wait for storage account to be ready
    local max_attempts=30
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query "provisioningState" --output tsv | grep -q "Succeeded"; then
            break
        fi
        log "Waiting for storage account to be ready... ($((attempt + 1))/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    # Create containers
    az storage container create \
        --name "ml-models" \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login \
        --output none
    
    az storage container create \
        --name "anomaly-data" \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login \
        --output none
    
    log_success "Storage account and containers created"
}

# Function to create IoT Hub
create_iot_hub() {
    log "Creating IoT Hub..."
    
    if az iot hub show --name "$IOT_HUB_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "IoT Hub $IOT_HUB_NAME already exists"
        return 0
    fi
    
    az iot hub create \
        --name "$IOT_HUB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku S1 \
        --partition-count 2 \
        --output none
    
    # Wait for IoT Hub to be ready
    local max_attempts=60
    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if az iot hub show --name "$IOT_HUB_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.state" --output tsv | grep -q "Active"; then
            break
        fi
        log "Waiting for IoT Hub to be ready... ($((attempt + 1))/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    log_success "IoT Hub created: $IOT_HUB_NAME"
}

# Function to create ML workspace
create_ml_workspace() {
    log "Creating Machine Learning workspace..."
    
    if az ml workspace show --name "$ML_WORKSPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "ML workspace $ML_WORKSPACE already exists"
        return 0
    fi
    
    az ml workspace create \
        --name "$ML_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --storage-account "$STORAGE_ACCOUNT" \
        --output none
    
    # Create compute instance for model training
    az ml compute create \
        --name cpu-cluster \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$ML_WORKSPACE" \
        --type amlcompute \
        --size Standard_DS3_v2 \
        --min-instances 0 \
        --max-instances 4 \
        --output none || log_warning "Compute cluster creation failed or already exists"
    
    log_success "ML workspace and compute cluster configured"
}

# Function to register IoT Edge device
register_edge_device() {
    log "Registering IoT Edge device..."
    
    # Check if device already exists
    if az iot hub device-identity show --device-id "$EDGE_DEVICE_ID" --hub-name "$IOT_HUB_NAME" &> /dev/null; then
        log_warning "IoT Edge device $EDGE_DEVICE_ID already exists"
    else
        az iot hub device-identity create \
            --device-id "$EDGE_DEVICE_ID" \
            --hub-name "$IOT_HUB_NAME" \
            --edge-enabled \
            --output none
    fi
    
    # Get connection string
    local connection_string=$(az iot hub device-identity connection-string show \
        --device-id "$EDGE_DEVICE_ID" \
        --hub-name "$IOT_HUB_NAME" \
        --query connectionString \
        --output tsv)
    
    log_success "IoT Edge device registered: $EDGE_DEVICE_ID"
    log "Connection string: $connection_string"
    
    # Save connection string to file for later use
    echo "$connection_string" > "edge_device_connection_string.txt"
    log "Connection string saved to: edge_device_connection_string.txt"
}

# Function to create Stream Analytics job
create_stream_analytics_job() {
    log "Creating Stream Analytics job..."
    
    if az stream-analytics job show --name "$ASA_JOB_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Stream Analytics job $ASA_JOB_NAME already exists"
        return 0
    fi
    
    az stream-analytics job create \
        --name "$ASA_JOB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --compatibility-level "1.2" \
        --sku "Standard" \
        --output none
    
    # Create input configuration
    cat > input_config.json << EOF
{
  "type": "Microsoft.Devices/IotHubs",
  "properties": {
    "iotHubNamespace": "${IOT_HUB_NAME}",
    "sharedAccessPolicyName": "iothubowner",
    "endpoint": "messages/events",
    "consumerGroupName": "\$Default"
  }
}
EOF
    
    az stream-analytics input create \
        --resource-group "$RESOURCE_GROUP" \
        --job-name "$ASA_JOB_NAME" \
        --name "sensorInput" \
        --type "Stream" \
        --datasource @input_config.json \
        --output none
    
    # Create output configuration
    cat > output_config.json << EOF
{
  "type": "Microsoft.Devices/IotHubs",
  "properties": {
    "iotHubNamespace": "${IOT_HUB_NAME}",
    "sharedAccessPolicyName": "iothubowner"
  }
}
EOF
    
    az stream-analytics output create \
        --resource-group "$RESOURCE_GROUP" \
        --job-name "$ASA_JOB_NAME" \
        --name "output" \
        --datasource @output_config.json \
        --output none
    
    # Create anomaly detection query
    local query='WITH AnomalyDetectionStep AS
(
    SELECT
        deviceId,
        temperature,
        pressure,
        vibration,
        ANOMALYDETECTION(temperature) OVER (PARTITION BY deviceId LIMIT DURATION(minute, 5)) AS temp_scores,
        ANOMALYDETECTION(pressure) OVER (PARTITION BY deviceId LIMIT DURATION(minute, 5)) AS pressure_scores,
        System.Timestamp() AS eventTime
    FROM sensorInput
)
SELECT
    deviceId,
    temperature,
    pressure,
    vibration,
    temp_scores,
    pressure_scores,
    eventTime
INTO output
FROM AnomalyDetectionStep
WHERE
    CAST(GetRecordPropertyValue(temp_scores, "BiLevelChangeScore") AS FLOAT) > 3.5
    OR CAST(GetRecordPropertyValue(pressure_scores, "BiLevelChangeScore") AS FLOAT) > 3.5'
    
    az stream-analytics transformation create \
        --resource-group "$RESOURCE_GROUP" \
        --job-name "$ASA_JOB_NAME" \
        --name "anomalyQuery" \
        --streaming-units 1 \
        --query "$query" \
        --output none
    
    # Clean up temporary files
    rm -f input_config.json output_config.json
    
    log_success "Stream Analytics job created with anomaly detection query"
}

# Function to deploy ML model to edge
deploy_ml_model_to_edge() {
    log "Deploying ML model to IoT Edge..."
    
    # Create deployment manifest
    cat > deployment.json << EOF
{
  "modulesContent": {
    "\$edgeAgent": {
      "properties.desired": {
        "schemaVersion": "1.0",
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
              "image": "mcr.microsoft.com/azureiotedge-agent:1.5",
              "createOptions": {}
            }
          },
          "edgeHub": {
            "type": "docker",
            "status": "running",
            "restartPolicy": "always",
            "settings": {
              "image": "mcr.microsoft.com/azureiotedge-hub:1.5",
              "createOptions": {
                "HostConfig": {
                  "PortBindings": {
                    "5671/tcp": [{"HostPort": "5671"}],
                    "8883/tcp": [{"HostPort": "8883"}]
                  }
                }
              }
            }
          }
        },
        "modules": {
          "anomalyDetector": {
            "version": "1.0",
            "type": "docker",
            "status": "running",
            "restartPolicy": "always",
            "settings": {
              "image": "mcr.microsoft.com/azure-cognitive-services/anomaly-detector:latest",
              "createOptions": {
                "ExposedPorts": {
                  "5000/tcp": {}
                },
                "HostConfig": {
                  "PortBindings": {
                    "5000/tcp": [{"HostPort": "5000"}]
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
EOF
    
    # Apply deployment to edge device
    az iot edge deployment create \
        --deployment-id "anomaly-detection-deployment-$(date +%s)" \
        --hub-name "$IOT_HUB_NAME" \
        --content deployment.json \
        --target-condition "deviceId='$EDGE_DEVICE_ID'" \
        --priority 10 \
        --output none
    
    log_success "ML model deployment initiated to edge device"
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring monitoring and diagnostics..."
    
    # Create Log Analytics workspace
    if az monitor log-analytics workspace show --workspace-name "$LOG_WORKSPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Log Analytics workspace $LOG_WORKSPACE already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_WORKSPACE" \
            --location "$LOCATION" \
            --output none
    fi
    
    local workspace_id=$(az monitor log-analytics workspace show \
        --workspace-name "$LOG_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query id \
        --output tsv)
    
    # Enable monitoring for IoT Hub
    az monitor diagnostic-settings create \
        --resource "$IOT_HUB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type "Microsoft.Devices/IotHubs" \
        --name "iot-diagnostics" \
        --workspace "$workspace_id" \
        --logs '[{"category": "DeviceTelemetry", "enabled": true},
                 {"category": "Routes", "enabled": true},
                 {"category": "Connections", "enabled": true}]' \
        --metrics '[{"category": "AllMetrics", "enabled": true}]' \
        --output none || log_warning "Diagnostic settings may already exist"
    
    log_success "Monitoring and diagnostics configured"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check resource group
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error_exit "Resource group $RESOURCE_GROUP not found"
    fi
    
    # Check IoT Hub
    local iot_hub_state=$(az iot hub show --name "$IOT_HUB_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.state" --output tsv)
    if [[ "$iot_hub_state" != "Active" ]]; then
        error_exit "IoT Hub is not active. Current state: $iot_hub_state"
    fi
    
    # Check IoT Edge device
    local device_status=$(az iot hub device-identity show --device-id "$EDGE_DEVICE_ID" --hub-name "$IOT_HUB_NAME" --query "status" --output tsv)
    if [[ "$device_status" != "enabled" ]]; then
        error_exit "IoT Edge device is not enabled. Current status: $device_status"
    fi
    
    # Check ML workspace
    if ! az ml workspace show --name "$ML_WORKSPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        error_exit "ML workspace $ML_WORKSPACE not found"
    fi
    
    # Check Stream Analytics job
    local asa_job_state=$(az stream-analytics job show --name "$ASA_JOB_NAME" --resource-group "$RESOURCE_GROUP" --query "jobState" --output tsv)
    log "Stream Analytics job state: $asa_job_state"
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_deployment_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "IoT Hub: $IOT_HUB_NAME"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "ML Workspace: $ML_WORKSPACE"
    echo "Edge Device ID: $EDGE_DEVICE_ID"
    echo "Stream Analytics Job: $ASA_JOB_NAME"
    echo "Log Analytics Workspace: $LOG_WORKSPACE"
    echo "===================="
    echo ""
    echo "Next Steps:"
    echo "1. Configure your physical IoT Edge device using the connection string in: edge_device_connection_string.txt"
    echo "2. Start the Stream Analytics job: az stream-analytics job start --name $ASA_JOB_NAME --resource-group $RESOURCE_GROUP"
    echo "3. Monitor your deployment through Azure Portal"
    echo "4. Send test telemetry data to validate the anomaly detection pipeline"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting Azure IoT Edge Real-Time Anomaly Detection deployment..."
    
    # Check if running in dry-run mode
    if [[ "${DRY_RUN:-}" == "true" ]]; then
        log "Running in DRY-RUN mode - no resources will be created"
        return 0
    fi
    
    check_prerequisites
    validate_subscription
    set_environment_variables
    create_resource_group
    create_storage_account
    create_iot_hub
    create_ml_workspace
    register_edge_device
    create_stream_analytics_job
    deploy_ml_model_to_edge
    configure_monitoring
    validate_deployment
    display_deployment_summary
    
    log_success "Deployment completed successfully!"
    log "Total deployment time: $SECONDS seconds"
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            export DRY_RUN=true
            shift
            ;;
        --location)
            export LOCATION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run         Run in dry-run mode (no resources created)"
            echo "  --location LOCATION  Set Azure region (default: eastus)"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# Run main function
main "$@"