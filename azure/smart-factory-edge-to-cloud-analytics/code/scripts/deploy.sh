#!/bin/bash
set -euo pipefail

# =============================================================================
# Azure Manufacturing Analytics Deployment Script
# Recipe: Orchestrating Edge-to-Cloud Manufacturing Analytics
# Services: Azure IoT Operations, Azure Event Hubs, Azure Stream Analytics, Azure Monitor
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a deployment.log
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a deployment.log
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a deployment.log
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a deployment.log
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Python and pip are available for telemetry simulator
    if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
        warn "Python is not installed. Telemetry simulator will not be available."
    fi
    
    # Check if required Azure CLI extensions are available
    local extensions=("stream-analytics" "eventhubs")
    for ext in "${extensions[@]}"; do
        if ! az extension list --query "[?name=='$ext']" -o tsv | grep -q "$ext"; then
            info "Installing Azure CLI extension: $ext"
            az extension add --name "$ext" --yes || warn "Failed to install extension $ext"
        fi
    done
    
    log "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-manufacturing-analytics-$(openssl rand -hex 3)}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
        export RANDOM_SUFFIX
    fi
    
    # Define manufacturing analytics component names
    export IOT_OPERATIONS_NAME="manufacturing-iot-ops-${RANDOM_SUFFIX}"
    export EVENT_HUBS_NAMESPACE="eh-manufacturing-${RANDOM_SUFFIX}"
    export EVENT_HUB_NAME="telemetry-hub"
    export STREAM_ANALYTICS_JOB="sa-equipment-analytics-${RANDOM_SUFFIX}"
    export ARC_CLUSTER_NAME="arc-edge-cluster-${RANDOM_SUFFIX}"
    export MONITOR_WORKSPACE="law-manufacturing-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
IOT_OPERATIONS_NAME=${IOT_OPERATIONS_NAME}
EVENT_HUBS_NAMESPACE=${EVENT_HUBS_NAMESPACE}
EVENT_HUB_NAME=${EVENT_HUB_NAME}
STREAM_ANALYTICS_JOB=${STREAM_ANALYTICS_JOB}
ARC_CLUSTER_NAME=${ARC_CLUSTER_NAME}
MONITOR_WORKSPACE=${MONITOR_WORKSPACE}
EOF
    
    info "Environment variables configured:"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  Location: ${LOCATION}"
    info "  Random Suffix: ${RANDOM_SUFFIX}"
    
    log "Environment setup completed"
}

# Function to create resource group and base infrastructure
create_base_infrastructure() {
    log "Creating base infrastructure..."
    
    # Create resource group for manufacturing analytics solution
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warn "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=manufacturing-analytics environment=demo solution=iot-operations
        log "Resource group created: ${RESOURCE_GROUP}"
    fi
    
    # Create Log Analytics workspace for monitoring
    if az monitor log-analytics workspace show --resource-group "${RESOURCE_GROUP}" --workspace-name "${MONITOR_WORKSPACE}" &> /dev/null; then
        warn "Log Analytics workspace ${MONITOR_WORKSPACE} already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${MONITOR_WORKSPACE}" \
            --location "${LOCATION}" \
            --sku pergb2018
        log "Log Analytics workspace ready for IoT telemetry monitoring"
    fi
}

# Function to deploy Event Hubs
deploy_event_hubs() {
    log "Deploying Azure Event Hubs for manufacturing telemetry ingestion..."
    
    # Create Event Hubs namespace with auto-scaling capabilities
    if az eventhubs namespace show --resource-group "${RESOURCE_GROUP}" --name "${EVENT_HUBS_NAMESPACE}" &> /dev/null; then
        warn "Event Hubs namespace ${EVENT_HUBS_NAMESPACE} already exists"
    else
        az eventhubs namespace create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${EVENT_HUBS_NAMESPACE}" \
            --location "${LOCATION}" \
            --sku Standard \
            --enable-auto-inflate \
            --maximum-throughput-units 10 \
            --tags solution=manufacturing-analytics
        log "Event Hubs namespace created with auto-scaling"
    fi
    
    # Create event hub for manufacturing telemetry with partitions for parallel processing
    if az eventhubs eventhub show --resource-group "${RESOURCE_GROUP}" --namespace-name "${EVENT_HUBS_NAMESPACE}" --name "${EVENT_HUB_NAME}" &> /dev/null; then
        warn "Event Hub ${EVENT_HUB_NAME} already exists"
    else
        az eventhubs eventhub create \
            --resource-group "${RESOURCE_GROUP}" \
            --namespace-name "${EVENT_HUBS_NAMESPACE}" \
            --name "${EVENT_HUB_NAME}" \
            --partition-count 4 \
            --message-retention 3 \
            --cleanup-policy Delete
        log "Event Hub created with 4 partitions for parallel processing"
    fi
    
    # Create shared access policy for IoT Operations integration
    if az eventhubs eventhub authorization-rule show --resource-group "${RESOURCE_GROUP}" --namespace-name "${EVENT_HUBS_NAMESPACE}" --eventhub-name "${EVENT_HUB_NAME}" --name IoTOperationsPolicy &> /dev/null; then
        warn "Authorization rule IoTOperationsPolicy already exists"
    else
        az eventhubs eventhub authorization-rule create \
            --resource-group "${RESOURCE_GROUP}" \
            --namespace-name "${EVENT_HUBS_NAMESPACE}" \
            --eventhub-name "${EVENT_HUB_NAME}" \
            --name IoTOperationsPolicy \
            --rights Send Listen
        log "IoT Operations authorization policy created"
    fi
    
    # Get and store Event Hubs connection string
    export EVENT_HUB_CONNECTION=$(az eventhubs eventhub authorization-rule keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${EVENT_HUBS_NAMESPACE}" \
        --eventhub-name "${EVENT_HUB_NAME}" \
        --name IoTOperationsPolicy \
        --query primaryConnectionString --output tsv)
    
    echo "EVENT_HUB_CONNECTION=${EVENT_HUB_CONNECTION}" >> .env
    
    log "Event Hubs telemetry ingestion layer configured successfully"
}

# Function to deploy Stream Analytics
deploy_stream_analytics() {
    log "Configuring Azure Stream Analytics for real-time manufacturing insights..."
    
    # Create Stream Analytics job for manufacturing analytics
    if az stream-analytics job show --resource-group "${RESOURCE_GROUP}" --name "${STREAM_ANALYTICS_JOB}" &> /dev/null; then
        warn "Stream Analytics job ${STREAM_ANALYTICS_JOB} already exists"
    else
        az stream-analytics job create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${STREAM_ANALYTICS_JOB}" \
            --location "${LOCATION}" \
            --output-error-policy Stop \
            --events-out-of-order-policy Adjust \
            --events-out-of-order-max-delay 5 \
            --events-late-arrival-max-delay 10 \
            --data-locale en-US \
            --compatibility-level 1.2 \
            --sku Standard
        log "Stream Analytics job created for real-time manufacturing insights"
    fi
    
    # Get Event Hubs authorization key for Stream Analytics input
    local event_hub_key=$(az eventhubs eventhub authorization-rule keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --namespace-name "${EVENT_HUBS_NAMESPACE}" \
        --eventhub-name "${EVENT_HUB_NAME}" \
        --name IoTOperationsPolicy \
        --query primaryKey --output tsv)
    
    # Create Stream Analytics input for Event Hubs telemetry
    if az stream-analytics input show --resource-group "${RESOURCE_GROUP}" --job-name "${STREAM_ANALYTICS_JOB}" --name ManufacturingTelemetryInput &> /dev/null; then
        warn "Stream Analytics input ManufacturingTelemetryInput already exists"
    else
        local input_config=$(cat <<EOF
{
  "type": "Stream",
  "datasource": {
    "type": "Microsoft.ServiceBus/EventHub",
    "properties": {
      "eventHubName": "${EVENT_HUB_NAME}",
      "serviceBusNamespace": "${EVENT_HUBS_NAMESPACE}",
      "sharedAccessPolicyName": "IoTOperationsPolicy",
      "sharedAccessPolicyKey": "${event_hub_key}"
    }
  },
  "serialization": {
    "type": "Json",
    "properties": {
      "encoding": "UTF8"
    }
  }
}
EOF
        )
        
        echo "${input_config}" > stream_analytics_input.json
        az stream-analytics input create \
            --resource-group "${RESOURCE_GROUP}" \
            --job-name "${STREAM_ANALYTICS_JOB}" \
            --name ManufacturingTelemetryInput \
            --properties @stream_analytics_input.json
        
        rm stream_analytics_input.json
        log "Stream Analytics input configured for Event Hubs telemetry"
    fi
}

# Function to prepare Azure Arc and IoT Operations
prepare_iot_operations() {
    log "Preparing Azure Arc and IoT Operations configuration..."
    
    # Register required resource providers for Arc-enabled services
    local providers=("Microsoft.Kubernetes" "Microsoft.KubernetesConfiguration" "Microsoft.ExtendedLocation" "Microsoft.IoTOperations")
    for provider in "${providers[@]}"; do
        if az provider show --namespace "$provider" --query "registrationState" -o tsv | grep -q "Registered"; then
            info "Provider $provider already registered"
        else
            info "Registering provider $provider"
            az provider register --namespace "$provider"
        fi
    done
    
    # Install Azure Arc CLI extensions
    local extensions=("k8s-extension" "connectedk8s" "aziot-ops")
    for ext in "${extensions[@]}"; do
        if az extension list --query "[?name=='$ext']" -o tsv | grep -q "$ext"; then
            info "Extension $ext already installed"
        else
            info "Installing Azure CLI extension: $ext"
            az extension add --name "$ext" --yes || warn "Failed to install extension $ext"
        fi
    done
    
    # Create IoT Operations configuration files
    cat > iot-operations-config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: manufacturing-iot-config
  namespace: azure-iot-operations
data:
  mqtt-broker-config: |
    listener:
      name: manufacturing-listener
      port: 1883
      protocol: mqtt
    authentication:
      method: x509
    topics:
      - name: "manufacturing/+/telemetry"
        qos: 1
      - name: "manufacturing/+/alerts"
        qos: 2
  dataflow-config: |
    sources:
      - name: opc-ua-source
        type: opcua
        endpoint: "opc.tcp://manufacturing-server:4840"
      - name: mqtt-source
        type: mqtt
        topic: "manufacturing/+/telemetry"
    transforms:
      - name: anomaly-detection
        type: function
        function: "detectAnomalies"
      - name: oee-calculation
        type: aggregate
        window: "5m"
    destinations:
      - name: cloud-eventhub
        type: eventhub
        connectionString: "${EVENT_HUB_CONNECTION}"
EOF
    
    export ARC_CLUSTER_RESOURCE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Kubernetes/connectedClusters/${ARC_CLUSTER_NAME}"
    echo "ARC_CLUSTER_RESOURCE_ID=${ARC_CLUSTER_RESOURCE_ID}" >> .env
    
    log "Azure Arc configuration prepared for edge Kubernetes deployment"
}

# Function to create telemetry simulator
create_telemetry_simulator() {
    log "Creating manufacturing telemetry simulation..."
    
    # Create telemetry simulation script for manufacturing equipment
    cat > manufacturing-telemetry-simulator.py << 'EOF'
import json
import time
import random
import datetime
import sys
import os

try:
    from azure.eventhub import EventHubProducerClient, EventData
except ImportError:
    print("Azure Event Hubs SDK not installed. Run: pip install azure-eventhub azure-identity")
    sys.exit(1)

# Manufacturing equipment simulation parameters
EQUIPMENT_TYPES = ['conveyor', 'press', 'welder', 'inspector', 'packager']
PRODUCTION_LINES = ['line-a', 'line-b', 'line-c']

def generate_telemetry():
    equipment_id = f"{random.choice(PRODUCTION_LINES)}-{random.choice(EQUIPMENT_TYPES)}-{random.randint(1,5):02d}"
    
    # Simulate normal operations with occasional anomalies
    is_anomaly = random.random() < 0.05  # 5% chance of anomaly
    
    telemetry = {
        "deviceId": equipment_id,
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
        "temperature": round(random.normalvariate(75 if not is_anomaly else 95, 5), 2),
        "vibration": round(random.normalvariate(0.3 if not is_anomaly else 1.2, 0.1), 3),
        "pressure": round(random.normalvariate(150 if not is_anomaly else 200, 10), 1),
        "operationalStatus": "running" if not is_anomaly else "warning",
        "productionCount": random.randint(100, 150),
        "qualityScore": round(random.normalvariate(0.95 if not is_anomaly else 0.75, 0.05), 3),
        "energyConsumption": round(random.normalvariate(85, 10), 2)
    }
    
    return json.dumps(telemetry)

def send_telemetry():
    connection_str = os.getenv('EVENT_HUB_CONNECTION')
    event_hub_name = os.getenv('EVENT_HUB_NAME', 'telemetry-hub')
    
    if not connection_str:
        print("ERROR: EVENT_HUB_CONNECTION environment variable not set")
        sys.exit(1)
    
    producer = EventHubProducerClient.from_connection_string(
        conn_str=connection_str,
        eventhub_name=event_hub_name
    )
    
    try:
        print(f"Starting manufacturing telemetry simulation...")
        print(f"Sending to Event Hub: {event_hub_name}")
        
        while True:
            # Send batch of telemetry events
            event_data_batch = producer.create_batch()
            
            for _ in range(10):  # Send 10 events per batch
                telemetry_json = generate_telemetry()
                event_data_batch.add(EventData(telemetry_json))
            
            producer.send_batch(event_data_batch)
            print(f"Sent batch of manufacturing telemetry at {datetime.datetime.now()}")
            time.sleep(5)  # Send batch every 5 seconds
            
    except KeyboardInterrupt:
        print("Telemetry simulation stopped")
    except Exception as e:
        print(f"Error sending telemetry: {e}")
    finally:
        producer.close()

if __name__ == "__main__":
    send_telemetry()
EOF
    
    # Create requirements file for Python dependencies
    cat > requirements.txt << 'EOF'
azure-eventhub>=5.11.0
azure-identity>=1.13.0
EOF
    
    # Try to install Python dependencies if Python is available
    if command -v python3 &> /dev/null; then
        info "Installing Python dependencies for telemetry simulator..."
        python3 -m pip install -r requirements.txt || warn "Failed to install Python dependencies"
    elif command -v python &> /dev/null; then
        info "Installing Python dependencies for telemetry simulator..."
        python -m pip install -r requirements.txt || warn "Failed to install Python dependencies"
    else
        warn "Python not found. Telemetry simulator dependencies not installed."
    fi
    
    log "Manufacturing telemetry simulator configured and ready for deployment"
}

# Function to deploy monitoring and alerts
deploy_monitoring() {
    log "Deploying Azure Monitor dashboards and alerts..."
    
    # Create action group for manufacturing alerts
    if az monitor action-group show --resource-group "${RESOURCE_GROUP}" --name "ManufacturingMaintenanceTeam" &> /dev/null; then
        warn "Action group ManufacturingMaintenanceTeam already exists"
    else
        az monitor action-group create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "ManufacturingMaintenanceTeam" \
            --short-name "MaintTeam"
        log "Manufacturing maintenance action group created"
    fi
    
    # Create alert rule for critical equipment conditions
    local event_hub_resource_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventHub/namespaces/${EVENT_HUBS_NAMESPACE}"
    local action_group_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Insights/actionGroups/ManufacturingMaintenanceTeam"
    
    if az monitor metrics alert show --resource-group "${RESOURCE_GROUP}" --name "CriticalEquipmentAlert" &> /dev/null; then
        warn "Alert rule CriticalEquipmentAlert already exists"
    else
        az monitor metrics alert create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "CriticalEquipmentAlert" \
            --description "Alert when manufacturing equipment requires immediate attention" \
            --severity 1 \
            --target-resource-id "${event_hub_resource_id}" \
            --condition "avg IncomingMessages > 1000" \
            --window-size 5m \
            --evaluation-frequency 1m \
            --action-groups "${action_group_id}" || warn "Failed to create alert rule"
        log "Predictive maintenance alerts configured"
    fi
}

# Function to create manufacturing analytics query
create_analytics_query() {
    log "Creating manufacturing analytics query for Stream Analytics..."
    
    # Create manufacturing analytics query for anomaly detection and OEE calculation
    cat > manufacturing-analytics-query.sql << 'EOF'
-- Equipment Anomaly Detection
WITH AnomalyDetection AS (
    SELECT
        deviceId,
        timestamp,
        temperature,
        vibration,
        pressure,
        operationalStatus,
        CASE 
            WHEN temperature > 90 OR vibration > 1.0 OR pressure > 180 THEN 'CRITICAL'
            WHEN temperature > 80 OR vibration > 0.8 OR pressure > 170 THEN 'WARNING'
            ELSE 'NORMAL'
        END AS alertLevel,
        System.Timestamp() AS processingTime
    FROM ManufacturingTelemetryInput
    WHERE operationalStatus = 'running'
),

-- Operational Equipment Effectiveness (OEE) Calculation
OEEMetrics AS (
    SELECT
        deviceId,
        System.Timestamp() AS windowEnd,
        AVG(CAST(productionCount AS float)) AS avgProduction,
        AVG(CAST(qualityScore AS float)) AS avgQuality,
        COUNT(*) AS totalReadings,
        SUM(CASE WHEN operationalStatus = 'running' THEN 1 ELSE 0 END) AS runningReadings
    FROM ManufacturingTelemetryInput
    GROUP BY deviceId, TumblingWindow(minute, 5)
)

-- Output critical alerts to monitoring system
SELECT
    deviceId,
    timestamp,
    alertLevel,
    temperature,
    vibration,
    pressure,
    'Equipment requires immediate attention' AS message
INTO AlertsOutput
FROM AnomalyDetection
WHERE alertLevel IN ('CRITICAL', 'WARNING');

-- Output OEE metrics for dashboard visualization
SELECT
    deviceId,
    windowEnd,
    avgProduction,
    avgQuality,
    (CAST(runningReadings AS float) / CAST(totalReadings AS float)) * 100 AS availabilityPercent,
    avgProduction * avgQuality * ((CAST(runningReadings AS float) / CAST(totalReadings AS float))) AS oeeScore
INTO OEEOutput
FROM OEEMetrics;
EOF
    
    log "Manufacturing analytics queries configured for real-time processing"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check Event Hubs namespace status
    local eh_status=$(az eventhubs namespace show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${EVENT_HUBS_NAMESPACE}" \
        --query status --output tsv 2>/dev/null || echo "NotFound")
    
    if [ "$eh_status" = "Active" ]; then
        log "✅ Event Hubs namespace is active"
    else
        warn "❌ Event Hubs namespace status: $eh_status"
    fi
    
    # Check Stream Analytics job status
    local sa_status=$(az stream-analytics job show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${STREAM_ANALYTICS_JOB}" \
        --query jobState --output tsv 2>/dev/null || echo "NotFound")
    
    if [ "$sa_status" = "Created" ] || [ "$sa_status" = "Running" ]; then
        log "✅ Stream Analytics job is ready"
    else
        warn "❌ Stream Analytics job status: $sa_status"
    fi
    
    # Check Log Analytics workspace
    local law_status=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${MONITOR_WORKSPACE}" \
        --query provisioningState --output tsv 2>/dev/null || echo "NotFound")
    
    if [ "$law_status" = "Succeeded" ]; then
        log "✅ Log Analytics workspace is ready"
    else
        warn "❌ Log Analytics workspace status: $law_status"
    fi
    
    log "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "=== DEPLOYMENT SUMMARY ==="
    info "Resource Group: ${RESOURCE_GROUP}"
    info "Location: ${LOCATION}"
    info "Event Hubs Namespace: ${EVENT_HUBS_NAMESPACE}"
    info "Event Hub Name: ${EVENT_HUB_NAME}"
    info "Stream Analytics Job: ${STREAM_ANALYTICS_JOB}"
    info "Log Analytics Workspace: ${MONITOR_WORKSPACE}"
    echo ""
    info "Next Steps:"
    info "1. Start the telemetry simulator: python3 manufacturing-telemetry-simulator.py"
    info "2. Start the Stream Analytics job: az stream-analytics job start --resource-group ${RESOURCE_GROUP} --name ${STREAM_ANALYTICS_JOB}"
    info "3. Monitor telemetry in Azure Portal"
    echo ""
    info "To clean up resources, run: ./destroy.sh"
    echo ""
    log "Deployment completed successfully!"
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Cleaning up partial resources..."
    if [ -f ".env" ]; then
        source .env
        ./destroy.sh || true
    fi
}

# Main deployment function
main() {
    log "Starting Azure Manufacturing Analytics deployment..."
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_base_infrastructure
    deploy_event_hubs
    deploy_stream_analytics
    prepare_iot_operations
    create_telemetry_simulator
    deploy_monitoring
    create_analytics_query
    validate_deployment
    display_summary
    
    log "Deployment completed successfully!"
}

# Parse command line arguments
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
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run                Validate configuration without deploying"
            echo "  --resource-group NAME    Specify resource group name"
            echo "  --location LOCATION      Specify Azure region"
            echo "  --help                   Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function if not in dry-run mode
if [ "${DRY_RUN:-false}" = "true" ]; then
    log "Dry run mode - validating configuration only"
    check_prerequisites
    setup_environment
    log "Dry run completed successfully"
else
    main "$@"
fi