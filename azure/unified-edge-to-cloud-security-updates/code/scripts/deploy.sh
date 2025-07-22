#!/bin/bash

# Azure IoT Device Update and Update Manager Deployment Script
# Recipe: Unified Edge-to-Cloud Security Updates with IoT Device Update and Update Manager
# Version: 1.0
# Last Updated: 2025-07-12

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if Azure CLI is installed and user is logged in
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --output tsv --query '"azure-cli"')
    log "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    local account_name=$(az account show --query name --output tsv)
    local subscription_id=$(az account show --query id --output tsv)
    log "Logged in to Azure account: $account_name"
    log "Using subscription: $subscription_id"
    
    # Check if required extensions are installed
    info "Checking Azure CLI extensions..."
    
    # Install IoT extension if not present
    if ! az extension list --query "[?name=='azure-iot'].name" --output tsv | grep -q azure-iot; then
        log "Installing Azure IoT extension..."
        az extension add --name azure-iot --yes
    fi
    
    # Install Device Update extension if not present
    if ! az extension list --query "[?name=='deviceupdate'].name" --output tsv | grep -q deviceupdate; then
        log "Installing Device Update extension..."
        az extension add --name deviceupdate --yes
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    # Set default values if not provided
    export LOCATION="${LOCATION:-eastus}"
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-iot-updates-${RANDOM_SUFFIX}}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Resource names
    export IOT_HUB_NAME="${IOT_HUB_NAME:-iothub-${RANDOM_SUFFIX}}"
    export DEVICE_UPDATE_ACCOUNT="${DEVICE_UPDATE_ACCOUNT:-deviceupdate-${RANDOM_SUFFIX}}"
    export DEVICE_UPDATE_INSTANCE="${DEVICE_UPDATE_INSTANCE:-deviceupdate-instance-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stdevupdate${RANDOM_SUFFIX}}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-iot-updates-${RANDOM_SUFFIX}}"
    export VM_NAME="${VM_NAME:-vm-update-test-${RANDOM_SUFFIX}}"
    
    log "Environment variables configured:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  IoT Hub: $IOT_HUB_NAME"
    log "  Device Update Account: $DEVICE_UPDATE_ACCOUNT"
    log "  Storage Account: $STORAGE_ACCOUNT"
    log "  Random Suffix: $RANDOM_SUFFIX"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP already exists, skipping creation"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=iot-updates environment=demo \
            --output none
        log "✅ Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create Log Analytics workspace
create_log_analytics_workspace() {
    log "Creating Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"
    
    if az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" &> /dev/null; then
        warn "Log Analytics workspace $LOG_ANALYTICS_WORKSPACE already exists, skipping creation"
    else
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --location "$LOCATION" \
            --output none
        log "✅ Log Analytics workspace created: $LOG_ANALYTICS_WORKSPACE"
    fi
}

# Function to create IoT Hub
create_iot_hub() {
    log "Creating IoT Hub: $IOT_HUB_NAME"
    
    if az iot hub show --name "$IOT_HUB_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "IoT Hub $IOT_HUB_NAME already exists, skipping creation"
    else
        az iot hub create \
            --name "$IOT_HUB_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku S1 \
            --unit 1 \
            --tags purpose=device-updates \
            --output none
        
        # Wait for IoT Hub to be ready
        log "Waiting for IoT Hub to be ready..."
        local retries=0
        local max_retries=30
        while [[ $retries -lt $max_retries ]]; do
            if az iot hub show --name "$IOT_HUB_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.state" --output tsv | grep -q "Active"; then
                break
            fi
            sleep 10
            ((retries++))
        done
        
        if [[ $retries -eq $max_retries ]]; then
            error "IoT Hub did not become active within expected time"
            exit 1
        fi
        
        log "✅ IoT Hub created: $IOT_HUB_NAME"
    fi
    
    # Get IoT Hub connection string
    export IOT_HUB_CONNECTION_STRING=$(az iot hub connection-string show \
        --hub-name "$IOT_HUB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account: $STORAGE_ACCOUNT"
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Storage account $STORAGE_ACCOUNT already exists, skipping creation"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --https-only true \
            --min-tls-version TLS1_2 \
            --output none
        log "✅ Storage account created: $STORAGE_ACCOUNT"
    fi
    
    # Get storage account connection string
    export STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
}

# Function to create Device Update account and instance
create_device_update_service() {
    log "Creating Device Update account: $DEVICE_UPDATE_ACCOUNT"
    
    if az iot du account show \
        --account "$DEVICE_UPDATE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Device Update account $DEVICE_UPDATE_ACCOUNT already exists, skipping creation"
    else
        az iot du account create \
            --account "$DEVICE_UPDATE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=firmware-updates \
            --output none
        log "✅ Device Update account created: $DEVICE_UPDATE_ACCOUNT"
    fi
    
    log "Creating Device Update instance: $DEVICE_UPDATE_INSTANCE"
    
    if az iot du instance show \
        --account "$DEVICE_UPDATE_ACCOUNT" \
        --instance "$DEVICE_UPDATE_INSTANCE" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Device Update instance $DEVICE_UPDATE_INSTANCE already exists, skipping creation"
    else
        az iot du instance create \
            --account "$DEVICE_UPDATE_ACCOUNT" \
            --instance "$DEVICE_UPDATE_INSTANCE" \
            --resource-group "$RESOURCE_GROUP" \
            --iothub-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Devices/IotHubs/$IOT_HUB_NAME" \
            --output none
        log "✅ Device Update instance created: $DEVICE_UPDATE_INSTANCE"
    fi
}

# Function to create and configure test VM
create_test_vm() {
    log "Creating test VM: $VM_NAME"
    
    if az vm show --name "$VM_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "VM $VM_NAME already exists, skipping creation"
    else
        az vm create \
            --name "$VM_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --image Ubuntu2204 \
            --size Standard_B2s \
            --admin-username azureuser \
            --generate-ssh-keys \
            --location "$LOCATION" \
            --output none
        
        # Enable Update Manager for the VM
        az vm update \
            --name "$VM_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --set "osProfile.linuxConfiguration.patchSettings.patchMode=AutomaticByPlatform" \
            --output none
        
        log "✅ Test VM created and Update Manager configured: $VM_NAME"
    fi
}

# Function to set up device simulation
setup_device_simulation() {
    log "Setting up device simulation..."
    
    local device_id="sim-device-001"
    
    # Create simulated device identity
    if az iot hub device-identity show \
        --hub-name "$IOT_HUB_NAME" \
        --device-id "$device_id" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Device $device_id already exists, skipping creation"
    else
        az iot hub device-identity create \
            --hub-name "$IOT_HUB_NAME" \
            --device-id "$device_id" \
            --resource-group "$RESOURCE_GROUP" \
            --output none
        log "✅ Simulated device created: $device_id"
    fi
    
    # Get device connection string
    export DEVICE_CONNECTION_STRING=$(az iot hub device-identity connection-string show \
        --hub-name "$IOT_HUB_NAME" \
        --device-id "$device_id" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    # Configure device for Device Update
    az iot hub device-twin update \
        --hub-name "$IOT_HUB_NAME" \
        --device-id "$device_id" \
        --desired '{
          "deviceUpdate": {
            "service": {
              "workflow": {
                "action": 255,
                "id": "workflow-001"
              }
            }
          }
        }' \
        --output none
    
    log "✅ Device Update simulation configured"
}

# Function to create sample update package
create_sample_update_package() {
    log "Creating sample update package..."
    
    local update_dir="$HOME/device-updates"
    mkdir -p "$update_dir"
    
    # Create sample update manifest
    cat > "$update_dir/sample-update-manifest.json" << 'EOF'
{
  "updateId": {
    "provider": "Contoso",
    "name": "SecurityPatch",
    "version": "1.0.0"
  },
  "description": "Security patch update for IoT devices",
  "compatibility": [
    {
      "deviceManufacturer": "Contoso",
      "deviceModel": "IoTDevice"
    }
  ],
  "instructions": {
    "steps": [
      {
        "handler": "microsoft/script:1",
        "files": ["install-security-patch.sh"],
        "handlerProperties": {
          "scriptFileName": "install-security-patch.sh",
          "arguments": "--security-patch"
        }
      }
    ]
  },
  "files": [
    {
      "filename": "install-security-patch.sh",
      "sizeInBytes": 1024,
      "hashes": {
        "sha256": "sample-hash-value"
      }
    }
  ]
}
EOF
    
    # Create sample installation script
    cat > "$update_dir/install-security-patch.sh" << 'EOF'
#!/bin/bash
echo "Installing security patch..."
echo "Security patch installed successfully"
exit 0
EOF
    
    chmod +x "$update_dir/install-security-patch.sh"
    
    log "✅ Sample update package created in $update_dir"
}

# Function to configure monitoring and alerting
configure_monitoring() {
    log "Configuring monitoring and alerting..."
    
    # Create monitoring dashboard
    local dashboard_name="IoT-Updates-Dashboard"
    
    if az monitor dashboard show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$dashboard_name" &> /dev/null; then
        warn "Dashboard $dashboard_name already exists, skipping creation"
    else
        az monitor dashboard create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$dashboard_name" \
            --location "$LOCATION" \
            --dashboard-metadata '{
              "title": "IoT Edge to Cloud Updates",
              "description": "Monitoring dashboard for Device Update and Update Manager operations"
            }' \
            --output none
        log "✅ Monitoring dashboard created: $dashboard_name"
    fi
    
    # Configure alert rule for failed updates
    local alert_name="DeviceUpdateFailures"
    
    if az monitor metrics alert show \
        --name "$alert_name" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Alert rule $alert_name already exists, skipping creation"
    else
        az monitor metrics alert create \
            --name "$alert_name" \
            --resource-group "$RESOURCE_GROUP" \
            --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DeviceUpdate/accounts/$DEVICE_UPDATE_ACCOUNT" \
            --condition "count static > 0" \
            --description "Alert when device updates fail" \
            --evaluation-frequency 5m \
            --window-size 15m \
            --severity 2 \
            --output none
        log "✅ Alert rule created: $alert_name"
    fi
}

# Function to set up update orchestration workflow
setup_orchestration_workflow() {
    log "Setting up update orchestration workflow..."
    
    local workflow_name="update-orchestration-workflow"
    
    if az logic workflow show \
        --name "$workflow_name" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Logic App workflow $workflow_name already exists, skipping creation"
    else
        az logic workflow create \
            --name "$workflow_name" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --definition '{
              "triggers": {
                "manual": {
                  "type": "Request",
                  "kind": "Http"
                }
              },
              "actions": {
                "checkInfrastructure": {
                  "type": "Http",
                  "inputs": {
                    "method": "GET",
                    "uri": "https://management.azure.com/subscriptions/'$SUBSCRIPTION_ID'/resourceGroups/'$RESOURCE_GROUP'/providers/Microsoft.Maintenance/updates"
                  }
                },
                "deployDeviceUpdates": {
                  "type": "Http",
                  "inputs": {
                    "method": "POST",
                    "uri": "https://management.azure.com/subscriptions/'$SUBSCRIPTION_ID'/resourceGroups/'$RESOURCE_GROUP'/providers/Microsoft.DeviceUpdate/accounts/'$DEVICE_UPDATE_ACCOUNT'/instances/'$DEVICE_UPDATE_INSTANCE'/deployments"
                  },
                  "runAfter": {
                    "checkInfrastructure": ["Succeeded"]
                  }
                }
              }
            }' \
            --output none
        log "✅ Update orchestration workflow created: $workflow_name"
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment completed successfully!"
    echo ""
    echo "=========================================="
    echo "         DEPLOYMENT SUMMARY"
    echo "=========================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "IoT Hub: $IOT_HUB_NAME"
    echo "Device Update Account: $DEVICE_UPDATE_ACCOUNT"
    echo "Device Update Instance: $DEVICE_UPDATE_INSTANCE"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    echo "Test VM: $VM_NAME"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Next Steps:"
    echo "1. Review the created resources in the Azure portal"
    echo "2. Test device update functionality with the simulated device"
    echo "3. Configure Update Manager policies for your infrastructure"
    echo "4. Monitor update operations through Azure Monitor dashboards"
    echo ""
    echo "To clean up resources, run:"
    echo "  ./destroy.sh"
    echo "=========================================="
}

# Main deployment function
main() {
    log "Starting Azure IoT Device Update and Update Manager deployment..."
    
    check_prerequisites
    setup_environment
    create_resource_group
    create_log_analytics_workspace
    create_iot_hub
    create_storage_account
    create_device_update_service
    create_test_vm
    setup_device_simulation
    create_sample_update_package
    configure_monitoring
    setup_orchestration_workflow
    display_summary
    
    log "Deployment completed successfully!"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi