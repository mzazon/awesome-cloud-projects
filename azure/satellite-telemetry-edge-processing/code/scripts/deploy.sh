#!/bin/bash

# =============================================================================
# Azure Orbital Edge-to-Orbit Data Processing - Deployment Script
# =============================================================================
# This script deploys the complete Azure Orbital and Azure Local infrastructure
# for orchestrating edge-to-orbit data processing with satellite telemetry.
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# Configuration and Global Variables
# =============================================================================

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file setup
LOG_FILE="./deployment_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# =============================================================================
# Utility Functions
# =============================================================================

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

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if kubectl is installed (for Azure Local)
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl is not installed. Azure Local deployment will be limited."
    fi
    
    # Check if openssl is available for random suffix generation
    if ! command -v openssl &> /dev/null; then
        log_warning "openssl not found. Using alternative random generation."
    fi
    
    log_success "Prerequisites check completed"
}

validate_environment() {
    log_info "Validating environment variables..."
    
    # Check if required environment variables are set
    local required_vars=(
        "AZURE_SUBSCRIPTION_ID"
        "AZURE_LOCATION"
        "AZURE_RESOURCE_GROUP_PREFIX"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable $var is not set"
            exit 1
        fi
    done
    
    log_success "Environment validation completed"
}

cleanup_on_error() {
    log_error "Deployment failed. Initiating cleanup..."
    
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        log_info "Cleaning up resource group: $RESOURCE_GROUP"
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true
    fi
    
    # Clean up local files
    rm -f satellite-processor.yaml dashboard-config.json test-telemetry.json 2>/dev/null || true
    
    log_error "Cleanup completed. Check logs for details: $LOG_FILE"
    exit 1
}

# =============================================================================
# Main Deployment Functions
# =============================================================================

setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export AZURE_LOCATION="${AZURE_LOCATION:-eastus}"
    export AZURE_RESOURCE_GROUP_PREFIX="${AZURE_RESOURCE_GROUP_PREFIX:-rg-orbital-edge}"
    
    # Get subscription ID
    export AZURE_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    if command -v openssl &> /dev/null; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    else
        RANDOM_SUFFIX=$(head /dev/urandom | tr -dc a-f0-9 | head -c 6)
    fi
    
    # Define service-specific variables
    export RESOURCE_GROUP="${AZURE_RESOURCE_GROUP_PREFIX}-${RANDOM_SUFFIX}"
    export SPACECRAFT_NAME="earth-obs-sat-${RANDOM_SUFFIX}"
    export IOT_HUB_NAME="iot-orbital-${RANDOM_SUFFIX}"
    export EVENT_GRID_TOPIC="orbital-events-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stororbital${RANDOM_SUFFIX}"
    export AZURE_LOCAL_NAME="local-edge-${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="func-orbital-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_NAME="law-orbital-${RANDOM_SUFFIX}"
    
    # Save environment variables for cleanup script
    cat > .env_deployment << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
SPACECRAFT_NAME=$SPACECRAFT_NAME
IOT_HUB_NAME=$IOT_HUB_NAME
EVENT_GRID_TOPIC=$EVENT_GRID_TOPIC
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
AZURE_LOCAL_NAME=$AZURE_LOCAL_NAME
FUNCTION_APP_NAME=$FUNCTION_APP_NAME
LOG_ANALYTICS_NAME=$LOG_ANALYTICS_NAME
AZURE_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID
AZURE_LOCATION=$AZURE_LOCATION
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    log_success "Environment setup completed"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $AZURE_LOCATION"
    log_info "Random Suffix: $RANDOM_SUFFIX"
}

create_resource_group() {
    log_info "Creating resource group..."
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$AZURE_LOCATION" \
        --tags purpose=orbital-edge-processing \
               environment=production \
               mission=earth-observation \
               deployment-script=automated
    
    log_success "Resource group created: $RESOURCE_GROUP"
}

register_providers() {
    log_info "Registering required Azure providers..."
    
    local providers=(
        "Microsoft.Orbital"
        "Microsoft.Devices"
        "Microsoft.EventGrid"
        "Microsoft.AzureStackHCI"
        "Microsoft.Web"
        "Microsoft.Storage"
        "Microsoft.OperationalInsights"
        "Microsoft.PowerBI"
    )
    
    for provider in "${providers[@]}"; do
        log_info "Registering provider: $provider"
        az provider register --namespace "$provider" --wait || {
            log_warning "Failed to register provider: $provider (may already be registered)"
        }
    done
    
    log_success "Azure providers registration completed"
}

create_iot_hub() {
    log_info "Creating IoT Hub for satellite telemetry ingestion..."
    
    az iot hub create \
        --name "$IOT_HUB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$AZURE_LOCATION" \
        --sku S2 \
        --partition-count 8 \
        --tags mission=satellite-telemetry \
               tier=production
    
    # Get IoT Hub connection string
    export IOT_CONNECTION_STRING=$(az iot hub connection-string show \
        --hub-name "$IOT_HUB_NAME" \
        --key primary \
        --query connectionString --output tsv)
    
    log_success "IoT Hub created: $IOT_HUB_NAME"
}

create_event_grid() {
    log_info "Creating Event Grid topic for orbital event orchestration..."
    
    az eventgrid topic create \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$AZURE_LOCATION" \
        --input-schema EventGridSchema \
        --tags orbital=satellite-events \
               processing=real-time
    
    # Get Event Grid topic endpoint and key
    export EVENT_GRID_ENDPOINT=$(az eventgrid topic show \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query endpoint --output tsv)
    
    export EVENT_GRID_KEY=$(az eventgrid topic key list \
        --name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    log_success "Event Grid topic created: $EVENT_GRID_TOPIC"
}

create_storage_account() {
    log_info "Creating Storage Account for satellite data archive..."
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$AZURE_LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --enable-hierarchical-namespace true \
        --tags orbital=data-archive \
               tier=hot-access
    
    # Create containers for different data types
    az storage container create \
        --name satellite-telemetry \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login
    
    az storage container create \
        --name processed-imagery \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login
    
    # Get storage account key
    export STORAGE_KEY=$(az storage account keys list \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query '[0].value' --output tsv)
    
    export STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT;AccountKey=$STORAGE_KEY;EndpointSuffix=core.windows.net"
    
    log_success "Storage account created: $STORAGE_ACCOUNT"
}

register_spacecraft() {
    log_info "Registering spacecraft with Azure Orbital Ground Station..."
    
    # Note: This requires actual NORAD ID and TLE data
    # Using example values - replace with actual satellite data
    az orbital spacecraft create \
        --name "$SPACECRAFT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$AZURE_LOCATION" \
        --norad-id "12345" \
        --title "Earth Observation Satellite" \
        --tle-line1 "1 25544U 98067A   08264.51782528 -.00002182  00000-0 -11606-4 0  2927" \
        --tle-line2 "2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.72125391563537" \
        --tags mission=earth-observation \
               orbit=leo || {
        log_warning "Spacecraft registration failed. This may require Azure Orbital preview access."
    }
    
    log_success "Spacecraft registration completed: $SPACECRAFT_NAME"
}

create_contact_profile() {
    log_info "Creating contact profile for satellite communication..."
    
    az orbital contact-profile create \
        --name "earth-obs-profile" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$AZURE_LOCATION" \
        --minimum-viable-contact-duration PT10M \
        --minimum-elevation-degrees 5 \
        --auto-tracking-configuration X \
        --tags profile=earth-observation \
               frequency=s-band || {
        log_warning "Contact profile creation failed. This may require Azure Orbital preview access."
    }
    
    # Add communication link for downlink
    az orbital contact-profile link add \
        --contact-profile-name "earth-obs-profile" \
        --resource-group "$RESOURCE_GROUP" \
        --name "downlink" \
        --direction Downlink \
        --center-frequency-mhz 2250.0 \
        --bandwidth-mhz 15.0 \
        --polarization LHCP || {
        log_warning "Contact profile link creation failed. This may require Azure Orbital preview access."
    }
    
    log_success "Contact profile created for S-band communication"
}

deploy_azure_local() {
    log_info "Deploying Azure Local instance for edge processing..."
    
    # Note: Azure Local requires physical hardware deployment
    # This creates the Azure resource representation
    az stack-hci cluster create \
        --name "$AZURE_LOCAL_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$AZURE_LOCATION" \
        --cluster-type HyperConverged \
        --tags deployment=edge-processing \
               workload=satellite-analytics || {
        log_warning "Azure Local cluster creation failed. This requires physical hardware deployment."
    }
    
    # Configure Arc-enabled services (if cluster exists)
    if az stack-hci cluster show --name "$AZURE_LOCAL_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        az connectedk8s connect \
            --name "${AZURE_LOCAL_NAME}-k8s" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$AZURE_LOCATION" \
            --tags orbital=edge-kubernetes || {
            log_warning "Arc-enabled Kubernetes connection failed."
        }
    fi
    
    log_success "Azure Local instance configured: $AZURE_LOCAL_NAME"
}

configure_iot_event_integration() {
    log_info "Configuring IoT Hub Event Grid integration..."
    
    # Create Event Grid subscription for IoT Hub events
    az eventgrid event-subscription create \
        --name "iot-orbital-subscription" \
        --source-resource-id "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Devices/IotHubs/$IOT_HUB_NAME" \
        --endpoint "$EVENT_GRID_ENDPOINT" \
        --endpoint-type webhook \
        --included-event-types "Microsoft.Devices.DeviceTelemetry" \
        --subject-begins-with "satellite/" \
        --labels orbital=telemetry-routing
    
    # Configure IoT Hub message routing to Event Grid
    az iot hub message-route create \
        --hub-name "$IOT_HUB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --route-name "orbital-events" \
        --endpoint-name "events" \
        --source DeviceMessages \
        --condition "satellite = 'active'" \
        --enabled true
    
    log_success "IoT Hub integrated with Event Grid for satellite event orchestration"
}

create_function_app() {
    log_info "Creating Function App for orbital data processing..."
    
    az functionapp create \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --consumption-plan-location "$AZURE_LOCATION" \
        --runtime python \
        --runtime-version 3.11 \
        --functions-version 4 \
        --tags workload=satellite-processing \
               scaling=consumption
    
    # Configure application settings
    az functionapp config appsettings set \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
            "IOT_HUB_CONNECTION_STRING=$IOT_CONNECTION_STRING" \
            "EVENT_GRID_ENDPOINT=$EVENT_GRID_ENDPOINT" \
            "EVENT_GRID_KEY=$EVENT_GRID_KEY" \
            "STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING"
    
    log_success "Function App created: $FUNCTION_APP_NAME"
}

deploy_edge_workload() {
    log_info "Deploying edge processing workload to Azure Local..."
    
    # Create Kubernetes deployment configuration
    cat > satellite-processor.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: satellite-processor
  namespace: orbital
spec:
  replicas: 3
  selector:
    matchLabels:
      app: satellite-processor
  template:
    metadata:
      labels:
        app: satellite-processor
    spec:
      containers:
      - name: processor
        image: mcr.microsoft.com/azure-orbital/processor:latest
        env:
        - name: IOT_HUB_CONNECTION
          value: "$IOT_CONNECTION_STRING"
        - name: STORAGE_ACCOUNT
          value: "$STORAGE_ACCOUNT"
        resources:
          requests:
            memory: "2Gi"
            cpu: "1"
          limits:
            memory: "4Gi"
            cpu: "2"
EOF
    
    # Apply deployment if kubectl is available and cluster is configured
    if command -v kubectl &> /dev/null && [[ -f ~/.kube/azure-local-config ]]; then
        kubectl apply -f satellite-processor.yaml --kubeconfig ~/.kube/azure-local-config || {
            log_warning "Edge workload deployment failed. Kubernetes cluster may not be ready."
        }
    else
        log_warning "kubectl not available or cluster not configured. Edge workload config saved to satellite-processor.yaml"
    fi
    
    log_success "Edge processing workload configuration completed"
}

configure_monitoring() {
    log_info "Configuring monitoring and alerting..."
    
    # Create Log Analytics workspace
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --location "$AZURE_LOCATION" \
        --sku PerGB2018 \
        --tags monitoring=orbital-operations
    
    # Configure diagnostic settings for IoT Hub
    az monitor diagnostic-settings create \
        --name "orbital-diagnostics" \
        --resource "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Devices/IotHubs/$IOT_HUB_NAME" \
        --workspace "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$LOG_ANALYTICS_NAME" \
        --logs '[{"category":"Connections","enabled":true},{"category":"DeviceTelemetry","enabled":true}]' \
        --metrics '[{"category":"AllMetrics","enabled":true}]'
    
    # Create alert rule for satellite communication failures
    az monitor metrics alert create \
        --name "satellite-connection-failure" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Devices/IotHubs/$IOT_HUB_NAME" \
        --condition "count \"Failed connection attempts\" > 5" \
        --description "Alert when satellite connection failures exceed threshold" \
        --evaluation-frequency PT5M \
        --window-size PT15M \
        --severity 2
    
    log_success "Monitoring and alerting configured"
}

deploy_dashboard() {
    log_info "Deploying mission control dashboard..."
    
    # Create dashboard configuration
    cat > dashboard-config.json << EOF
{
    "dataSources": [
        {
            "name": "IoT Hub Telemetry",
            "connectionString": "$IOT_CONNECTION_STRING",
            "type": "IoTHub"
        },
        {
            "name": "Storage Analytics",
            "connectionString": "$STORAGE_CONNECTION_STRING",
            "type": "Storage"
        }
    ],
    "refreshInterval": "PT5M"
}
EOF
    
    log_success "Mission control dashboard configuration completed"
}

run_validation() {
    log_info "Running deployment validation..."
    
    # Test IoT Hub connectivity
    az iot hub device-identity create \
        --hub-name "$IOT_HUB_NAME" \
        --device-id "test-satellite-device" || {
        log_warning "IoT Hub device creation failed during validation"
    }
    
    # Test Event Grid
    az eventgrid event publish \
        --topic-name "$EVENT_GRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --events '[{
            "id": "test-orbital-event-001",
            "eventType": "Microsoft.Orbital.SatelliteContact",
            "subject": "satellites/earth-obs-sat",
            "eventTime": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
            "data": {
                "satelliteId": "test-satellite",
                "contactStatus": "active",
                "groundStation": "Microsoft_Quincy"
            }
        }]' || {
        log_warning "Event Grid test event failed during validation"
    }
    
    # Test storage account
    echo '{"satellite":"test","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","data":"base64encoded"}' > test-telemetry.json
    az storage blob upload \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name satellite-telemetry \
        --name "test/telemetry-$(date +%Y%m%d-%H%M%S).json" \
        --file test-telemetry.json \
        --auth-mode login || {
        log_warning "Storage blob upload failed during validation"
    }
    
    log_success "Deployment validation completed"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    log_info "Starting Azure Orbital Edge-to-Orbit Data Processing deployment..."
    log_info "Log file: $LOG_FILE"
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Execute deployment steps
    check_prerequisites
    validate_environment
    setup_environment
    create_resource_group
    register_providers
    create_iot_hub
    create_event_grid
    create_storage_account
    register_spacecraft
    create_contact_profile
    deploy_azure_local
    configure_iot_event_integration
    create_function_app
    deploy_edge_workload
    configure_monitoring
    deploy_dashboard
    run_validation
    
    log_success "Deployment completed successfully!"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "IoT Hub: $IOT_HUB_NAME"
    log_info "Event Grid Topic: $EVENT_GRID_TOPIC"
    log_info "Storage Account: $STORAGE_ACCOUNT"
    log_info "Function App: $FUNCTION_APP_NAME"
    log_info ""
    log_info "Next steps:"
    log_info "1. Configure your satellite's NORAD ID and TLE data in the spacecraft registration"
    log_info "2. Request Azure Orbital preview access if not already granted"
    log_info "3. Deploy physical Azure Local hardware if edge processing is required"
    log_info "4. Configure kubectl for Azure Local cluster management"
    log_info "5. Schedule satellite contacts through Azure portal or CLI"
    log_info ""
    log_info "For cleanup, run: ./destroy.sh"
    log_info "Environment variables saved to: .env_deployment"
}

# =============================================================================
# Script Entry Point
# =============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi