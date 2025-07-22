#!/bin/bash

# =============================================================================
# Deploy Script for Intelligent Energy Grid Analytics
# Azure Data Manager for Energy + Azure Digital Twins
# =============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warn() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

cleanup_on_error() {
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    log_warn "You may need to manually clean up partially created resources."
    exit 1
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --output tsv --query '."azure-cli"' 2>/dev/null || echo "unknown")
    log_info "Azure CLI version: ${az_version}"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Please install it first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

wait_for_deployment() {
    local resource_type="$1"
    local resource_name="$2"
    local timeout_minutes="${3:-30}"
    
    log_info "Waiting for ${resource_type} '${resource_name}' to be ready (timeout: ${timeout_minutes} minutes)..."
    
    local end_time=$(($(date +%s) + timeout_minutes * 60))
    while [ $(date +%s) -lt $end_time ]; do
        sleep 30
        echo -n "."
    done
    echo ""
    
    log_success "${resource_type} '${resource_name}' deployment completed"
}

# =============================================================================
# CONFIGURATION
# =============================================================================

setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-energy-grid-analytics}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    local RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names with unique suffix
    export ENERGY_DATA_MANAGER="adm-energy-${RANDOM_SUFFIX}"
    export DIGITAL_TWINS_INSTANCE="adt-grid-${RANDOM_SUFFIX}"
    export TIME_SERIES_INSIGHTS="tsi-energy-${RANDOM_SUFFIX}"
    export AI_SERVICES_ACCOUNT="ai-energy-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stenergy${RANDOM_SUFFIX}"
    export IOT_HUB="iot-energy-${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="func-energy-integration-${RANDOM_SUFFIX}"
    export EVENTGRID_TOPIC="egt-energy-alerts-${RANDOM_SUFFIX}"
    export LOG_WORKSPACE="law-energy-${RANDOM_SUFFIX}"
    
    # Save configuration for cleanup script
    cat > "${SCRIPT_DIR}/deployment-config.env" << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
ENERGY_DATA_MANAGER=${ENERGY_DATA_MANAGER}
DIGITAL_TWINS_INSTANCE=${DIGITAL_TWINS_INSTANCE}
TIME_SERIES_INSIGHTS=${TIME_SERIES_INSIGHTS}
AI_SERVICES_ACCOUNT=${AI_SERVICES_ACCOUNT}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
IOT_HUB=${IOT_HUB}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
EVENTGRID_TOPIC=${EVENTGRID_TOPIC}
LOG_WORKSPACE=${LOG_WORKSPACE}
EOF
    
    log_success "Environment variables configured"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Subscription ID: ${SUBSCRIPTION_ID}"
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================

create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warn "Resource group '${RESOURCE_GROUP}' already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=energy-analytics environment=demo project=smart-grid \
            --output none
        
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

register_providers() {
    log_info "Registering required resource providers..."
    
    local providers=(
        "Microsoft.DigitalTwins"
        "Microsoft.TimeSeriesInsights"
        "Microsoft.CognitiveServices"
        "Microsoft.Devices"
        "Microsoft.Web"
        "Microsoft.EventGrid"
        "Microsoft.OperationalInsights"
    )
    
    for provider in "${providers[@]}"; do
        log_info "Registering provider: ${provider}"
        az provider register --namespace "${provider}" --output none
    done
    
    log_success "Resource providers registered"
}

deploy_energy_data_manager() {
    log_info "Deploying Azure Data Manager for Energy: ${ENERGY_DATA_MANAGER}"
    
    # Check if extension is installed
    if ! az extension show --name energy-data-services &> /dev/null; then
        log_info "Installing energy-data-services extension..."
        az extension add --name energy-data-services --output none
    fi
    
    # Create Azure Data Manager for Energy instance
    az energy-data-service create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${ENERGY_DATA_MANAGER}" \
        --location "${LOCATION}" \
        --partition-count 1 \
        --sku S1 \
        --tags environment=demo purpose=grid-analytics \
        --output none
    
    # Get the service endpoint
    local energy_endpoint=$(az energy-data-service show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${ENERGY_DATA_MANAGER}" \
        --query properties.endpoint \
        --output tsv)
    
    log_success "Azure Data Manager for Energy deployed successfully"
    log_info "Energy Data Manager endpoint: ${energy_endpoint}"
}

deploy_digital_twins() {
    log_info "Deploying Azure Digital Twins: ${DIGITAL_TWINS_INSTANCE}"
    
    # Create Azure Digital Twins instance
    az dt create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${DIGITAL_TWINS_INSTANCE}" \
        --location "${LOCATION}" \
        --assign-identity \
        --tags environment=demo purpose=grid-modeling \
        --output none
    
    # Get the Digital Twins endpoint
    local dt_endpoint=$(az dt show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${DIGITAL_TWINS_INSTANCE}" \
        --query hostName \
        --output tsv)
    
    log_success "Azure Digital Twins instance created"
    log_info "Digital Twins endpoint: ${dt_endpoint}"
    
    # Set up role assignment for data access
    local user_principal=$(az account show --query user.name --output tsv)
    az dt role-assignment create \
        --assignee "${user_principal}" \
        --role "Azure Digital Twins Data Owner" \
        --dt-name "${DIGITAL_TWINS_INSTANCE}" \
        --output none
    
    log_success "Digital Twins access configured"
}

create_dtdl_models() {
    log_info "Creating DTDL models for energy grid components..."
    
    # Create directory for DTDL models
    mkdir -p "${SCRIPT_DIR}/../dtdl-models"
    
    # Create Power Generator model
    cat > "${SCRIPT_DIR}/../dtdl-models/PowerGenerator.json" << 'EOF'
{
  "@context": "dtmi:dtdl:context;3",
  "@id": "dtmi:energygrid:PowerGenerator;1",
  "@type": "Interface",
  "displayName": "Power Generator",
  "description": "Digital twin model for power generation facilities",
  "contents": [
    {
      "@type": "Property",
      "name": "generatorType",
      "schema": "string",
      "description": "Type of power generator (solar, wind, hydro, nuclear, gas)"
    },
    {
      "@type": "Telemetry",
      "name": "currentOutput",
      "schema": "double",
      "description": "Current power output in MW"
    },
    {
      "@type": "Telemetry",
      "name": "capacity",
      "schema": "double",
      "description": "Maximum generation capacity in MW"
    },
    {
      "@type": "Telemetry",
      "name": "efficiency",
      "schema": "double",
      "description": "Current operational efficiency percentage"
    },
    {
      "@type": "Property",
      "name": "location",
      "schema": {
        "@type": "Object",
        "fields": [
          {"name": "latitude", "schema": "double"},
          {"name": "longitude", "schema": "double"}
        ]
      }
    }
  ]
}
EOF
    
    # Create Grid Node model
    cat > "${SCRIPT_DIR}/../dtdl-models/GridNode.json" << 'EOF'
{
  "@context": "dtmi:dtdl:context;3",
  "@id": "dtmi:energygrid:GridNode;1",
  "@type": "Interface",
  "displayName": "Grid Node",
  "description": "Digital twin model for grid distribution nodes",
  "contents": [
    {
      "@type": "Telemetry",
      "name": "voltage",
      "schema": "double",
      "description": "Current voltage level in kV"
    },
    {
      "@type": "Telemetry",
      "name": "frequency",
      "schema": "double",
      "description": "Grid frequency in Hz"
    },
    {
      "@type": "Telemetry",
      "name": "powerFlow",
      "schema": "double",
      "description": "Power flow through node in MW"
    },
    {
      "@type": "Property",
      "name": "nodeType",
      "schema": "string",
      "description": "Type of grid node (transmission, distribution, substation)"
    },
    {
      "@type": "Relationship",
      "name": "connectedTo",
      "target": "dtmi:energygrid:GridNode;1",
      "description": "Connected grid nodes"
    }
  ]
}
EOF
    
    # Upload models to Digital Twins
    az dt model create \
        --dt-name "${DIGITAL_TWINS_INSTANCE}" \
        --models "${SCRIPT_DIR}/../dtdl-models/PowerGenerator.json" \
        --output none
    
    az dt model create \
        --dt-name "${DIGITAL_TWINS_INSTANCE}" \
        --models "${SCRIPT_DIR}/../dtdl-models/GridNode.json" \
        --output none
    
    log_success "DTDL models created and uploaded"
}

deploy_time_series_insights() {
    log_info "Deploying Azure Time Series Insights: ${TIME_SERIES_INSIGHTS}"
    
    # Create Time Series Insights environment
    az tsi environment create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${TIME_SERIES_INSIGHTS}" \
        --location "${LOCATION}" \
        --sku name=S1 capacity=1 \
        --time-series-id-properties deviceId \
        --warm-store-configuration data-retention=P7D \
        --tags purpose=time-series-analytics environment=demo \
        --output none
    
    log_success "Time Series Insights environment created"
    
    # Create IoT Hub for data ingestion
    log_info "Creating IoT Hub: ${IOT_HUB}"
    az iot hub create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${IOT_HUB}" \
        --location "${LOCATION}" \
        --sku S1 \
        --partition-count 4 \
        --tags purpose=iot-data-ingestion \
        --output none
    
    log_success "IoT Hub created for data ingestion"
    
    # Get IoT Hub connection string
    local iot_key=$(az iot hub policy show \
        --hub-name "${IOT_HUB}" \
        --name iothubowner \
        --query primaryKey \
        --output tsv)
    
    # Create TSI event source
    az tsi event-source iothub create \
        --resource-group "${RESOURCE_GROUP}" \
        --environment-name "${TIME_SERIES_INSIGHTS}" \
        --name "grid-data-source" \
        --location "${LOCATION}" \
        --iot-hub-name "${IOT_HUB}" \
        --shared-access-key-name iothubowner \
        --shared-access-key "${iot_key}" \
        --consumer-group-name '$Default' \
        --timestamp-property-name timestamp \
        --output none
    
    log_success "Time Series Insights event source configured"
}

deploy_ai_services() {
    log_info "Deploying Azure AI Services: ${AI_SERVICES_ACCOUNT}"
    
    # Create Azure AI Services multi-service account
    az cognitiveservices account create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AI_SERVICES_ACCOUNT}" \
        --location "${LOCATION}" \
        --kind CognitiveServices \
        --sku S0 \
        --tags purpose=ai-analytics environment=demo \
        --output none
    
    log_success "Azure AI Services account created"
    
    # Get AI Services endpoint and key
    local ai_endpoint=$(az cognitiveservices account show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AI_SERVICES_ACCOUNT}" \
        --query properties.endpoint \
        --output tsv)
    
    log_info "AI Services endpoint: ${ai_endpoint}"
    
    # Create storage account for ML model artifacts
    log_info "Creating storage account: ${STORAGE_ACCOUNT}"
    az storage account create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${STORAGE_ACCOUNT}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --tags purpose=ml-storage \
        --output none
    
    log_success "Storage account created for ML artifacts"
}

configure_data_integration() {
    log_info "Configuring data integration and digital twin population..."
    
    # Create sample digital twin instances
    az dt twin create \
        --dt-name "${DIGITAL_TWINS_INSTANCE}" \
        --dtmi "dtmi:energygrid:PowerGenerator;1" \
        --twin-id "solar-farm-01" \
        --properties '{"generatorType": "solar", "location": {"latitude": 40.7589, "longitude": -73.9851}}' \
        --output none
    
    az dt twin create \
        --dt-name "${DIGITAL_TWINS_INSTANCE}" \
        --dtmi "dtmi:energygrid:GridNode;1" \
        --twin-id "substation-central" \
        --properties '{"nodeType": "substation"}' \
        --output none
    
    log_success "Sample digital twins created"
    
    # Create relationships between twins
    az dt twin relationship create \
        --dt-name "${DIGITAL_TWINS_INSTANCE}" \
        --twin-id "solar-farm-01" \
        --relationship-id "feeds-to-substation" \
        --relationship "connectedTo" \
        --target "substation-central" \
        --output none
    
    log_success "Digital twin relationships established"
    
    # Create Function App for data integration
    log_info "Creating Function App: ${FUNCTION_APP_NAME}"
    az functionapp create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FUNCTION_APP_NAME}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime node \
        --runtime-version 18 \
        --functions-version 4 \
        --tags purpose=data-integration \
        --output none
    
    log_success "Integration function app created"
}

deploy_analytics_monitoring() {
    log_info "Deploying AI-powered analytics and monitoring..."
    
    # Create sample analytics configuration
    cat > "${SCRIPT_DIR}/../analytics-config.json" << 'EOF'
{
  "predictionModels": {
    "demandForecast": {
      "type": "time-series-regression",
      "inputFeatures": ["historical_consumption", "weather_data", "day_of_week"],
      "predictionHorizon": "24h",
      "updateFrequency": "1h"
    },
    "renewableGeneration": {
      "type": "weather-correlation",
      "inputFeatures": ["solar_irradiance", "wind_speed", "cloud_cover"],
      "predictionHorizon": "6h",
      "updateFrequency": "15m"
    }
  },
  "anomalyDetection": {
    "gridStability": {
      "metrics": ["voltage", "frequency", "power_factor"],
      "threshold": "3_sigma",
      "alerting": true
    },
    "equipmentHealth": {
      "metrics": ["temperature", "vibration", "efficiency"],
      "threshold": "statistical",
      "predictiveMaintenance": true
    }
  }
}
EOF
    
    # Upload analytics configuration to storage
    az storage container create \
        --account-name "${STORAGE_ACCOUNT}" \
        --name analytics-config \
        --public-access off \
        --output none
    
    az storage blob upload \
        --account-name "${STORAGE_ACCOUNT}" \
        --container-name analytics-config \
        --name analytics-config.json \
        --file "${SCRIPT_DIR}/../analytics-config.json" \
        --output none
    
    log_success "Analytics configuration deployed"
    
    # Set up Event Grid for real-time alerting
    log_info "Creating Event Grid topic: ${EVENTGRID_TOPIC}"
    az eventgrid topic create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${EVENTGRID_TOPIC}" \
        --location "${LOCATION}" \
        --tags purpose=alerting \
        --output none
    
    log_success "Event Grid topic created for alerting"
}

configure_monitoring() {
    log_info "Configuring monitoring and visualization dashboard..."
    
    # Create Log Analytics workspace for monitoring
    log_info "Creating Log Analytics workspace: ${LOG_WORKSPACE}"
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_WORKSPACE}" \
        --location "${LOCATION}" \
        --sku PerGB2018 \
        --tags purpose=monitoring \
        --output none
    
    log_success "Log Analytics workspace created"
    
    # Configure diagnostic settings for Digital Twins
    az monitor diagnostic-settings create \
        --resource "${DIGITAL_TWINS_INSTANCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --resource-type Microsoft.DigitalTwins/digitalTwinsInstances \
        --name "dt-diagnostics" \
        --workspace "${LOG_WORKSPACE}" \
        --logs '[{"category": "DigitalTwinsOperation", "enabled": true, "retentionPolicy": {"enabled": false, "days": 0}}, {"category": "EventRoutesOperation", "enabled": true, "retentionPolicy": {"enabled": false, "days": 0}}]' \
        --metrics '[{"category": "AllMetrics", "enabled": true, "retentionPolicy": {"enabled": false, "days": 0}}]' \
        --output none
    
    log_success "Diagnostic monitoring configured"
    
    # Create dashboard configuration
    cat > "${SCRIPT_DIR}/../dashboard-config.json" << 'EOF'
{
  "dashboards": {
    "gridOverview": {
      "widgets": [
        "real_time_generation",
        "current_demand", 
        "renewable_percentage",
        "grid_stability_metrics"
      ]
    },
    "predictiveAnalytics": {
      "widgets": [
        "demand_forecast_24h",
        "renewable_generation_forecast",
        "optimization_recommendations",
        "cost_savings_tracker"
      ]
    },
    "operationalHealth": {
      "widgets": [
        "equipment_status",
        "maintenance_alerts",
        "performance_trends",
        "carbon_footprint_tracking"
      ]
    }
  }
}
EOF
    
    log_success "Dashboard configuration created"
}

# =============================================================================
# MAIN DEPLOYMENT FLOW
# =============================================================================

main() {
    log_info "Starting deployment of Intelligent Energy Grid Analytics platform..."
    log_info "Timestamp: ${TIMESTAMP}"
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_resource_group
    register_providers
    
    # Deploy core services
    deploy_energy_data_manager
    deploy_digital_twins
    create_dtdl_models
    deploy_time_series_insights
    deploy_ai_services
    
    # Configure integrations
    configure_data_integration
    deploy_analytics_monitoring
    configure_monitoring
    
    log_success "✅ Deployment completed successfully!"
    log_info "Deployment configuration saved to: ${SCRIPT_DIR}/deployment-config.env"
    log_info "DTDL models saved to: ${SCRIPT_DIR}/../dtdl-models/"
    log_info "Analytics configuration saved to: ${SCRIPT_DIR}/../analytics-config.json"
    log_info "Dashboard configuration saved to: ${SCRIPT_DIR}/../dashboard-config.json"
    
    # Display resource information
    echo ""
    log_info "=== DEPLOYMENT SUMMARY ==="
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Energy Data Manager: ${ENERGY_DATA_MANAGER}"
    log_info "Digital Twins Instance: ${DIGITAL_TWINS_INSTANCE}"
    log_info "Time Series Insights: ${TIME_SERIES_INSIGHTS}"
    log_info "AI Services Account: ${AI_SERVICES_ACCOUNT}"
    log_info "Storage Account: ${STORAGE_ACCOUNT}"
    log_info "IoT Hub: ${IOT_HUB}"
    log_info "Function App: ${FUNCTION_APP_NAME}"
    log_info "Event Grid Topic: ${EVENTGRID_TOPIC}"
    log_info "Log Analytics Workspace: ${LOG_WORKSPACE}"
    echo ""
    
    log_warn "⚠️  Remember to run the destroy.sh script to clean up resources when done!"
    log_info "📋 Full deployment log available at: ${LOG_FILE}"
}

# Run main function
main "$@"