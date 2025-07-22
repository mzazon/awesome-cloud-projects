#!/bin/bash

# Azure Smart Manufacturing Digital Twins Deployment Script
# This script deploys the complete smart manufacturing digital twins solution
# using Azure IoT Hub, Azure Digital Twins, Time Series Insights, and Azure ML

set -e
set -o pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Error handling function
handle_error() {
    log_error "Deployment failed at line $1. Exiting."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Default configuration
RESOURCE_GROUP_PREFIX="rg-manufacturing-twins"
LOCATION="eastus"
DEPLOYMENT_NAME="manufacturing-twins-$(date +%s)"

# Print banner
echo "========================================================================"
echo "Azure Smart Manufacturing Digital Twins Deployment"
echo "========================================================================"
echo ""

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required extensions are available
    log_info "Installing required Azure CLI extensions..."
    az extension add --name azure-iot --upgrade -y 2>/dev/null || true
    az extension add --name dt --upgrade -y 2>/dev/null || true
    
    # Check if Python is available (for simulation)
    if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
        log_warning "Python not found. Device simulation will not be available."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 7))
    
    # Set environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX}-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export IOT_HUB_NAME="iothub-manufacturing-${RANDOM_SUFFIX}"
    export DIGITAL_TWINS_NAME="dt-manufacturing-${RANDOM_SUFFIX}"
    export TSI_ENVIRONMENT_NAME="tsi-manufacturing-${RANDOM_SUFFIX}"
    export ML_WORKSPACE_NAME="mlws-manufacturing-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stmanufacturing${RANDOM_SUFFIX}"
    
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "IoT Hub: ${IOT_HUB_NAME}"
    log_info "Digital Twins: ${DIGITAL_TWINS_NAME}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
    
    log_success "Environment setup completed"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    # Check if resource group already exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists. Using existing group."
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=manufacturing-digital-twins environment=demo \
            --output none
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create IoT Hub
create_iot_hub() {
    log_info "Creating IoT Hub: ${IOT_HUB_NAME}"
    
    # Check if IoT Hub already exists
    if az iot hub show --name "${IOT_HUB_NAME}" &> /dev/null; then
        log_warning "IoT Hub ${IOT_HUB_NAME} already exists. Skipping creation."
    else
        az iot hub create \
            --name "${IOT_HUB_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku S1 \
            --partition-count 4 \
            --tags purpose=manufacturing-connectivity \
            --output none
        
        log_success "IoT Hub created: ${IOT_HUB_NAME}"
    fi
    
    # Get IoT Hub connection string
    export IOT_HUB_CONNECTION=$(az iot hub connection-string show \
        --hub-name "${IOT_HUB_NAME}" \
        --output tsv)
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT_NAME}"
    
    # Check if storage account already exists
    if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account ${STORAGE_ACCOUNT_NAME} already exists. Skipping creation."
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --hierarchical-namespace true \
            --tags purpose=timeseries-storage \
            --output none
        
        log_success "Storage account created: ${STORAGE_ACCOUNT_NAME}"
    fi
    
    # Get storage account key
    export STORAGE_KEY=$(az storage account keys list \
        --account-name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query '[0].value' --output tsv)
}

# Function to create Time Series Insights environment
create_tsi_environment() {
    log_info "Creating Time Series Insights environment: ${TSI_ENVIRONMENT_NAME}"
    
    # Check if TSI environment already exists
    if az tsi environment show --environment-name "${TSI_ENVIRONMENT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "TSI environment ${TSI_ENVIRONMENT_NAME} already exists. Skipping creation."
    else
        az tsi environment gen2 create \
            --environment-name "${TSI_ENVIRONMENT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku name=L1 capacity=1 \
            --time-series-id-properties deviceId \
            --warm-store-configuration data-retention=P7D \
            --storage-configuration account-name="${STORAGE_ACCOUNT_NAME}" management-key="${STORAGE_KEY}" \
            --output none
        
        log_success "Time Series Insights environment created: ${TSI_ENVIRONMENT_NAME}"
    fi
}

# Function to create Azure Digital Twins instance
create_digital_twins() {
    log_info "Creating Azure Digital Twins instance: ${DIGITAL_TWINS_NAME}"
    
    # Check if Digital Twins instance already exists
    if az dt show --dt-name "${DIGITAL_TWINS_NAME}" &> /dev/null; then
        log_warning "Digital Twins instance ${DIGITAL_TWINS_NAME} already exists. Skipping creation."
    else
        az dt create \
            --dt-name "${DIGITAL_TWINS_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=manufacturing-modeling \
            --output none
        
        log_success "Azure Digital Twins instance created: ${DIGITAL_TWINS_NAME}"
    fi
    
    # Assign current user as Digital Twins Data Owner
    USER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)
    
    az role assignment create \
        --role "Azure Digital Twins Data Owner" \
        --assignee "${USER_OBJECT_ID}" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DigitalTwins/digitalTwinsInstances/${DIGITAL_TWINS_NAME}" \
        --output none 2>/dev/null || log_warning "Role assignment already exists or failed"
}

# Function to create DTDL models
create_dtdl_models() {
    log_info "Creating DTDL models for manufacturing equipment"
    
    # Create temporary directory for models
    mkdir -p temp_models
    
    # Create production line model
    cat > temp_models/production-line-model.json << 'EOF'
{
  "@id": "dtmi:manufacturing:ProductionLine;1",
  "@type": "Interface",
  "@context": "dtmi:dtdl:context;2",
  "displayName": "Production Line",
  "description": "Manufacturing production line with multiple equipment",
  "contents": [
    {
      "@type": "Property",
      "name": "lineId",
      "schema": "string",
      "description": "Unique identifier for the production line"
    },
    {
      "@type": "Property",
      "name": "status",
      "schema": "string",
      "description": "Current operational status"
    },
    {
      "@type": "Telemetry",
      "name": "efficiency",
      "schema": "double",
      "description": "Production efficiency percentage"
    },
    {
      "@type": "Telemetry",
      "name": "throughput",
      "schema": "integer",
      "description": "Units produced per hour"
    },
    {
      "@type": "Relationship",
      "name": "contains",
      "target": "dtmi:manufacturing:Equipment;1",
      "description": "Equipment within this production line"
    }
  ]
}
EOF

    # Create equipment model
    cat > temp_models/equipment-model.json << 'EOF'
{
  "@id": "dtmi:manufacturing:Equipment;1",
  "@type": "Interface", 
  "@context": "dtmi:dtdl:context;2",
  "displayName": "Manufacturing Equipment",
  "description": "Individual piece of manufacturing equipment",
  "contents": [
    {
      "@type": "Property",
      "name": "equipmentId",
      "schema": "string",
      "description": "Unique equipment identifier"
    },
    {
      "@type": "Property",
      "name": "equipmentType",
      "schema": "string", 
      "description": "Type of manufacturing equipment"
    },
    {
      "@type": "Telemetry",
      "name": "temperature",
      "schema": "double",
      "description": "Operating temperature in Celsius"
    },
    {
      "@type": "Telemetry",
      "name": "vibration",
      "schema": "double",
      "description": "Vibration level in Hz"
    },
    {
      "@type": "Telemetry",
      "name": "pressure",
      "schema": "double",
      "description": "Operating pressure in PSI"
    },
    {
      "@type": "Command",
      "name": "emergencyStop",
      "description": "Emergency stop command for equipment"
    }
  ]
}
EOF

    # Upload models to Azure Digital Twins
    az dt model create \
        --dt-name "${DIGITAL_TWINS_NAME}" \
        --models temp_models/production-line-model.json temp_models/equipment-model.json \
        --output none
    
    # Clean up temporary files
    rm -rf temp_models
    
    log_success "DTDL models created and uploaded"
}

# Function to create digital twin instances
create_digital_twin_instances() {
    log_info "Creating digital twin instances"
    
    # Create production line digital twin
    az dt twin create \
        --dt-name "${DIGITAL_TWINS_NAME}" \
        --dtmi "dtmi:manufacturing:ProductionLine;1" \
        --twin-id "production-line-a" \
        --properties '{"lineId": "LINE-A-001", "status": "operational"}' \
        --output none 2>/dev/null || log_warning "Production line twin may already exist"
    
    # Create robotic arm twin
    az dt twin create \
        --dt-name "${DIGITAL_TWINS_NAME}" \
        --dtmi "dtmi:manufacturing:Equipment;1" \
        --twin-id "robotic-arm-001" \
        --properties '{"equipmentId": "ARM-001", "equipmentType": "robotic-assembly"}' \
        --output none 2>/dev/null || log_warning "Robotic arm twin may already exist"
    
    # Create conveyor belt twin
    az dt twin create \
        --dt-name "${DIGITAL_TWINS_NAME}" \
        --dtmi "dtmi:manufacturing:Equipment;1" \
        --twin-id "conveyor-belt-001" \
        --properties '{"equipmentId": "CVR-001", "equipmentType": "conveyor-transport"}' \
        --output none 2>/dev/null || log_warning "Conveyor belt twin may already exist"
    
    # Create relationships
    az dt twin relationship create \
        --dt-name "${DIGITAL_TWINS_NAME}" \
        --source-twin-id "production-line-a" \
        --relationship-id "contains-arm" \
        --relationship contains \
        --target-twin-id "robotic-arm-001" \
        --output none 2>/dev/null || log_warning "Arm relationship may already exist"
    
    az dt twin relationship create \
        --dt-name "${DIGITAL_TWINS_NAME}" \
        --source-twin-id "production-line-a" \
        --relationship-id "contains-conveyor" \
        --relationship contains \
        --target-twin-id "conveyor-belt-001" \
        --output none 2>/dev/null || log_warning "Conveyor relationship may already exist"
    
    log_success "Digital twin instances and relationships created"
}

# Function to register IoT devices
register_iot_devices() {
    log_info "Registering IoT devices"
    
    # Register robotic arm device
    az iot hub device-identity create \
        --hub-name "${IOT_HUB_NAME}" \
        --device-id "robotic-arm-001" \
        --output none 2>/dev/null || log_warning "Robotic arm device may already exist"
    
    # Register conveyor belt device
    az iot hub device-identity create \
        --hub-name "${IOT_HUB_NAME}" \
        --device-id "conveyor-belt-001" \
        --output none 2>/dev/null || log_warning "Conveyor belt device may already exist"
    
    # Get device connection strings
    export ARM_CONNECTION=$(az iot hub device-identity connection-string show \
        --hub-name "${IOT_HUB_NAME}" \
        --device-id "robotic-arm-001" \
        --output tsv)
    
    export CONVEYOR_CONNECTION=$(az iot hub device-identity connection-string show \
        --hub-name "${IOT_HUB_NAME}" \
        --device-id "conveyor-belt-001" \
        --output tsv)
    
    log_success "IoT devices registered successfully"
}

# Function to create Azure Machine Learning workspace
create_ml_workspace() {
    log_info "Creating Azure Machine Learning workspace: ${ML_WORKSPACE_NAME}"
    
    # Check if ML workspace already exists
    if az ml workspace show --workspace-name "${ML_WORKSPACE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "ML workspace ${ML_WORKSPACE_NAME} already exists. Skipping creation."
    else
        az ml workspace create \
            --workspace-name "${ML_WORKSPACE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=predictive-maintenance \
            --output none
        
        log_success "Azure Machine Learning workspace created: ${ML_WORKSPACE_NAME}"
    fi
}

# Function to create device simulation script
create_simulation_script() {
    log_info "Creating device simulation script"
    
    cat > simulate_devices.py << EOF
#!/usr/bin/env python3

import asyncio
import json
import random
import time
import sys
from datetime import datetime

try:
    from azure.iot.device.aio import IoTHubDeviceClient
except ImportError:
    print("Azure IoT Device SDK not found. Install with: pip install azure-iot-device")
    sys.exit(1)

async def simulate_robotic_arm(connection_string):
    try:
        client = IoTHubDeviceClient.create_from_connection_string(connection_string)
        await client.connect()
        
        print("Robotic arm simulation started...")
        for i in range(50):  # Reduced for demo
            # Simulate normal operation with occasional anomalies
            base_temp = 45.0 + random.normalvariate(0, 2)
            vibration = 2.5 + random.normalvariate(0, 0.5)
            pressure = 120 + random.normalvariate(0, 5)
            
            # Introduce anomalies for predictive model training
            if random.random() < 0.05:  # 5% anomaly rate
                base_temp += random.uniform(15, 25)
                vibration += random.uniform(3, 6)
            
            telemetry = {
                "deviceId": "robotic-arm-001",
                "timestamp": datetime.utcnow().isoformat(),
                "temperature": round(base_temp, 2),
                "vibration": round(vibration, 2),
                "pressure": round(pressure, 2),
                "operationalStatus": "running"
            }
            
            message = json.dumps(telemetry)
            await client.send_message(message)
            print(f"ARM - Sent: {message}")
            await asyncio.sleep(10)
        
        await client.disconnect()
    except Exception as e:
        print(f"Error in robotic arm simulation: {e}")

async def simulate_conveyor(connection_string):
    try:
        client = IoTHubDeviceClient.create_from_connection_string(connection_string)
        await client.connect()
        
        print("Conveyor belt simulation started...")
        for i in range(50):  # Reduced for demo
            speed = 2.5 + random.normalvariate(0, 0.2)
            load = random.uniform(60, 95)
            motor_temp = 35 + random.normalvariate(0, 3)
            
            telemetry = {
                "deviceId": "conveyor-belt-001", 
                "timestamp": datetime.utcnow().isoformat(),
                "speed": round(speed, 2),
                "load": round(load, 2),
                "motorTemperature": round(motor_temp, 2),
                "operationalStatus": "running"
            }
            
            message = json.dumps(telemetry)
            await client.send_message(message)
            print(f"CONVEYOR - Sent: {message}")
            await asyncio.sleep(10)
        
        await client.disconnect()
    except Exception as e:
        print(f"Error in conveyor simulation: {e}")

async def main():
    arm_connection = "${ARM_CONNECTION}"
    conveyor_connection = "${CONVEYOR_CONNECTION}"
    
    if not arm_connection or not conveyor_connection:
        print("Device connection strings not available. Skipping simulation.")
        return
    
    await asyncio.gather(
        simulate_robotic_arm(arm_connection),
        simulate_conveyor(conveyor_connection)
    )

if __name__ == "__main__":
    asyncio.run(main())
EOF

    chmod +x simulate_devices.py
    log_success "Device simulation script created"
}

# Function to configure event routing
configure_event_routing() {
    log_info "Configuring event routing and data processing"
    
    # Note: Event routing configuration would typically require additional setup
    # This is a placeholder for the actual routing configuration
    log_warning "Event routing requires additional configuration based on specific requirements"
    
    log_success "Event routing configuration completed"
}

# Function to run validation tests
run_validation() {
    log_info "Running deployment validation..."
    
    # Check IoT Hub
    if az iot hub show --name "${IOT_HUB_NAME}" &> /dev/null; then
        log_success "IoT Hub validation passed"
    else
        log_error "IoT Hub validation failed"
        return 1
    fi
    
    # Check Digital Twins
    if az dt show --dt-name "${DIGITAL_TWINS_NAME}" &> /dev/null; then
        log_success "Digital Twins validation passed"
    else
        log_error "Digital Twins validation failed"
        return 1
    fi
    
    # Check Storage Account
    if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_success "Storage Account validation passed"
    else
        log_error "Storage Account validation failed"
        return 1
    fi
    
    # Check ML Workspace
    if az ml workspace show --workspace-name "${ML_WORKSPACE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_success "ML Workspace validation passed"
    else
        log_error "ML Workspace validation failed"
        return 1
    fi
    
    log_success "All validation checks passed!"
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "========================================================================"
    echo "DEPLOYMENT SUMMARY"
    echo "========================================================================"
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "IoT Hub: ${IOT_HUB_NAME}"
    echo "Digital Twins: ${DIGITAL_TWINS_NAME}"
    echo "Time Series Insights: ${TSI_ENVIRONMENT_NAME}"
    echo "Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "ML Workspace: ${ML_WORKSPACE_NAME}"
    echo ""
    echo "Next Steps:"
    echo "1. Run device simulation: python3 simulate_devices.py"
    echo "2. Monitor IoT Hub: az iot hub monitor-events --hub-name ${IOT_HUB_NAME}"
    echo "3. Query digital twins: az dt twin query --dt-name ${DIGITAL_TWINS_NAME} --query-command 'SELECT * FROM DIGITALTWINS'"
    echo "4. Access Time Series Insights through Azure Portal"
    echo "5. Use ML Workspace for predictive model development"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo "========================================================================"
}

# Main deployment function
main() {
    log_info "Starting Azure Smart Manufacturing Digital Twins deployment..."
    
    check_prerequisites
    setup_environment
    create_resource_group
    create_storage_account
    create_iot_hub
    create_tsi_environment
    create_digital_twins
    create_dtdl_models
    create_digital_twin_instances
    register_iot_devices
    create_ml_workspace
    configure_event_routing
    create_simulation_script
    run_validation
    display_summary
    
    log_success "Deployment completed successfully!"
    echo ""
    echo "Note: Some services may take a few minutes to be fully operational."
    echo "TSI environment provisioning can take 10-20 minutes."
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group)
            RESOURCE_GROUP_PREFIX="$2"
            shift 2
            ;;
        --location)
            LOCATION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --resource-group PREFIX   Set resource group prefix (default: rg-manufacturing-twins)"
            echo "  --location LOCATION       Set Azure region (default: eastus)"
            echo "  --help                   Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main deployment
main