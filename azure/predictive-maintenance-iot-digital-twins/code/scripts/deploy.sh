#!/bin/bash

# Azure IoT Digital Twins with Azure Data Explorer - Deployment Script
# This script deploys a comprehensive IoT solution using Azure Digital Twins,
# Azure Data Explorer, IoT Central, and supporting services for digital twin
# orchestration and time-series analytics.

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handler
error_exit() {
    log_error "Script failed at line $1"
    log_error "Command that failed: $2"
    exit 1
}

# Set up error handling
trap 'error_exit $LINENO "$BASH_COMMAND"' ERR

# Script metadata
readonly SCRIPT_NAME="Azure IoT Digital Twins Deployment"
readonly SCRIPT_VERSION="1.0"
readonly ESTIMATED_TIME="15-20 minutes"

# Print script header
print_header() {
    echo "=================================================="
    echo "   $SCRIPT_NAME"
    echo "   Version: $SCRIPT_VERSION"
    echo "   Estimated deployment time: $ESTIMATED_TIME"
    echo "=================================================="
    echo
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        log_error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not available. Required for generating random suffixes."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Get user confirmation
get_user_confirmation() {
    echo
    log_warning "This script will create Azure resources that may incur costs."
    log_warning "Estimated monthly cost for demo workload: \$150-200"
    echo
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

# Set environment variables
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for globally unique resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    log_info "Using random suffix: $RANDOM_SUFFIX"
    
    # Core configuration
    export RESOURCE_GROUP="rg-iot-digital-twins-${RANDOM_SUFFIX}"
    export LOCATION="eastus"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Service-specific names
    export ADT_NAME="adt-iot-${RANDOM_SUFFIX}"
    export ADX_CLUSTER="adxiot${RANDOM_SUFFIX}"
    export ADX_DATABASE="iottelemetry"
    export IOTC_APP="iotc-${RANDOM_SUFFIX}"
    export FUNC_APP="func-iot-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stiotfunc${RANDOM_SUFFIX}"
    export EVENT_HUB_NS="ehns-iot-${RANDOM_SUFFIX}"
    export EVENT_HUB_NAME="telemetry-hub"
    export TSI_ENV="tsi-iot-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > .env.deploy << EOF
RANDOM_SUFFIX=${RANDOM_SUFFIX}
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
ADT_NAME=${ADT_NAME}
ADX_CLUSTER=${ADX_CLUSTER}
ADX_DATABASE=${ADX_DATABASE}
IOTC_APP=${IOTC_APP}
FUNC_APP=${FUNC_APP}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
EVENT_HUB_NS=${EVENT_HUB_NS}
EVENT_HUB_NAME=${EVENT_HUB_NAME}
TSI_ENV=${TSI_ENV}
EOF
    
    log_success "Environment variables configured"
}

# Create resource group and foundational resources
create_foundation() {
    log_info "Creating foundational resources..."
    
    # Create resource group
    log_info "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=recipe environment=demo \
        --output none
    
    log_success "Resource group created: $RESOURCE_GROUP"
    
    # Create storage account for Function App
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --output none
    
    log_success "Storage account created: $STORAGE_ACCOUNT"
}

# Create Azure Digital Twins instance
create_digital_twins() {
    log_info "Creating Azure Digital Twins instance..."
    
    # Create Azure Digital Twins instance
    log_info "Creating ADT instance: $ADT_NAME"
    az dt create \
        --name "${ADT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --output none
    
    # Assign Azure Digital Twins Data Owner role to current user
    local user_object_id=$(az ad signed-in-user show --query id --output tsv)
    log_info "Assigning ADT Data Owner role to current user"
    
    az dt role-assignment create \
        --dt-name "${ADT_NAME}" \
        --assignee "${user_object_id}" \
        --role "Azure Digital Twins Data Owner" \
        --output none
    
    log_success "Azure Digital Twins instance created: $ADT_NAME"
}

# Create IoT Central application
create_iot_central() {
    log_info "Creating IoT Central application..."
    
    az iot central app create \
        --name "${IOTC_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --subdomain "${IOTC_APP}" \
        --sku ST2 \
        --template "iotc-pnp-preview" \
        --output none
    
    # Get IoT Central application ID scope
    local iotc_id_scope=$(az iot central app show \
        --name "${IOTC_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query applicationId --output tsv)
    
    log_success "IoT Central application created: $IOTC_APP"
    log_info "Application URL: https://${IOTC_APP}.azureiotcentral.com"
    log_info "Application ID Scope: $iotc_id_scope"
}

# Create Event Hub for data streaming
create_event_hub() {
    log_info "Creating Event Hub for telemetry streaming..."
    
    # Create Event Hub namespace
    log_info "Creating Event Hub namespace: $EVENT_HUB_NS"
    az eventhubs namespace create \
        --name "${EVENT_HUB_NS}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard \
        --capacity 1 \
        --output none
    
    # Create Event Hub for telemetry data
    log_info "Creating Event Hub: $EVENT_HUB_NAME"
    az eventhubs eventhub create \
        --name "${EVENT_HUB_NAME}" \
        --namespace-name "${EVENT_HUB_NS}" \
        --resource-group "${RESOURCE_GROUP}" \
        --partition-count 4 \
        --retention-time-in-hours 24 \
        --output none
    
    # Get Event Hub connection string
    export EH_CONNECTION=$(az eventhubs namespace authorization-rule keys list \
        --name RootManageSharedAccessKey \
        --namespace-name "${EVENT_HUB_NS}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query primaryConnectionString --output tsv)
    
    # Save connection string for later use
    echo "EH_CONNECTION=${EH_CONNECTION}" >> .env.deploy
    
    log_success "Event Hub created for telemetry streaming"
}

# Deploy Azure Data Explorer cluster
deploy_data_explorer() {
    log_info "Deploying Azure Data Explorer cluster..."
    log_warning "This operation takes 10-15 minutes. Please be patient..."
    
    # Create Azure Data Explorer cluster
    az kusto cluster create \
        --name "${ADX_CLUSTER}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku name="Dev(No SLA)_Standard_E2a_v4" tier="Basic" \
        --capacity 1 \
        --output none
    
    log_info "Waiting for ADX cluster deployment..."
    
    # Wait for cluster to be ready
    az kusto cluster wait \
        --name "${ADX_CLUSTER}" \
        --resource-group "${RESOURCE_GROUP}" \
        --created
    
    # Create database for IoT telemetry
    log_info "Creating ADX database: $ADX_DATABASE"
    az kusto database create \
        --cluster-name "${ADX_CLUSTER}" \
        --database-name "${ADX_DATABASE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --read-write-database soft-delete-period="P30D" \
            hot-cache-period="P7D" \
        --output none
    
    log_success "Azure Data Explorer cluster deployed: $ADX_CLUSTER"
}

# Configure Digital Twin models and event routes
configure_digital_twins() {
    log_info "Configuring Digital Twin models and event routes..."
    
    # Create DTDL model for industrial equipment
    log_info "Creating DTDL model file"
    cat > equipment-model.json << 'EOF'
{
  "@id": "dtmi:com:example:IndustrialEquipment;1",
  "@type": "Interface",
  "@context": "dtmi:dtdl:context;2",
  "displayName": "Industrial Equipment",
  "contents": [
    {
      "@type": "Property",
      "name": "temperature",
      "schema": "double"
    },
    {
      "@type": "Property",
      "name": "vibration",
      "schema": "double"
    },
    {
      "@type": "Property",
      "name": "operatingHours",
      "schema": "integer"
    },
    {
      "@type": "Property",
      "name": "maintenanceStatus",
      "schema": "string"
    }
  ]
}
EOF
    
    # Upload model to Azure Digital Twins
    log_info "Uploading DTDL model to ADT"
    az dt model create \
        --dt-name "${ADT_NAME}" \
        --models @equipment-model.json \
        --output none
    
    # Create event route to Event Hub
    log_info "Creating Event Hub endpoint"
    az dt endpoint create eventhub \
        --dt-name "${ADT_NAME}" \
        --endpoint-name telemetry-endpoint \
        --eventhub "${EVENT_HUB_NAME}" \
        --eventhub-namespace "${EVENT_HUB_NS}" \
        --resource-group "${RESOURCE_GROUP}" \
        --output none
    
    # Create route for all telemetry updates
    log_info "Creating telemetry route"
    az dt route create \
        --dt-name "${ADT_NAME}" \
        --endpoint-name telemetry-endpoint \
        --route-name telemetry-route \
        --filter "type = 'Microsoft.DigitalTwins.Twin.Update'" \
        --output none
    
    log_success "Digital Twin models and routes configured"
}

# Create Function Apps for data processing
create_function_apps() {
    log_info "Creating Function Apps for data processing..."
    
    # Create Function App for twin updates
    log_info "Creating Function App: $FUNC_APP"
    az functionapp create \
        --name "${FUNC_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --storage-account "${STORAGE_ACCOUNT}" \
        --consumption-plan-location "${LOCATION}" \
        --runtime dotnet \
        --functions-version 4 \
        --output none
    
    # Get storage account key for configuration
    local storage_key=$(az storage account keys list \
        --account-name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query '[0].value' -o tsv)
    
    # Configure Function App settings
    log_info "Configuring Function App settings"
    az functionapp config appsettings set \
        --name "${FUNC_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "ADT_SERVICE_URL=https://${ADT_NAME}.api.${LOCATION}.digitaltwins.azure.net" \
            "EventHubConnection=${EH_CONNECTION}" \
            "AzureWebJobsStorage=DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT};EndpointSuffix=core.windows.net;AccountKey=${storage_key}" \
        --output none
    
    # Enable managed identity for Function App
    log_info "Enabling managed identity for Function App"
    az functionapp identity assign \
        --name "${FUNC_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --output none
    
    # Grant Function App access to Digital Twins
    local func_identity=$(az functionapp identity show \
        --name "${FUNC_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query principalId --output tsv)
    
    log_info "Granting Function App access to Digital Twins"
    az dt role-assignment create \
        --dt-name "${ADT_NAME}" \
        --assignee "${func_identity}" \
        --role "Azure Digital Twins Data Owner" \
        --output none
    
    log_success "Function App created and configured"
}

# Configure data ingestion pipeline
configure_data_ingestion() {
    log_info "Configuring data ingestion pipeline..."
    
    # Create data connection from Event Hub to ADX
    log_info "Creating Event Hub to ADX data connection"
    az kusto data-connection event-hub create \
        --cluster-name "${ADX_CLUSTER}" \
        --data-connection-name iot-telemetry-connection \
        --database-name "${ADX_DATABASE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --consumer-group '$Default' \
        --event-hub-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.EventHub/namespaces/${EVENT_HUB_NS}/eventhubs/${EVENT_HUB_NAME}" \
        --location "${LOCATION}" \
        --table-name TelemetryData \
        --data-format JSON \
        --mapping-rule-name TelemetryMapping \
        --output none
    
    # Create table and mapping in ADX
    log_info "Creating ADX table and JSON mapping"
    local adx_query="
.create table TelemetryData (
    Timestamp: datetime,
    DeviceId: string,
    Temperature: real,
    Vibration: real,
    OperatingHours: int,
    MaintenanceStatus: string
)

.create table TelemetryData ingestion json mapping 'TelemetryMapping' '[{\"column\":\"Timestamp\",\"path\":\"$.timestamp\"},{\"column\":\"DeviceId\",\"path\":\"$.deviceId\"},{\"column\":\"Temperature\",\"path\":\"$.temperature\"},{\"column\":\"Vibration\",\"path\":\"$.vibration\"},{\"column\":\"OperatingHours\",\"path\":\"$.operatingHours\"},{\"column\":\"MaintenanceStatus\",\"path\":\"$.maintenanceStatus\"}]'
"
    
    # Execute query to create table and mapping
    echo "${adx_query}" | az kusto query \
        --cluster-name "${ADX_CLUSTER}" \
        --database-name "${ADX_DATABASE}" \
        --query-input stdin \
        --output none
    
    log_success "Data ingestion pipeline configured"
}

# Set up Time Series Insights environment
setup_time_series_insights() {
    log_info "Setting up Time Series Insights environment..."
    
    # Get storage account key
    local storage_key=$(az storage account keys list \
        --account-name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query '[0].value' -o tsv)
    
    # Create Time Series Insights Gen2 environment
    log_info "Creating TSI Gen2 environment: $TSI_ENV"
    az tsi environment gen2 create \
        --name "${TSI_ENV}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku name="L1" capacity=1 \
        --time-series-id-properties name=deviceId type=String \
        --storage-configuration account-name="${STORAGE_ACCOUNT}" \
            management-key="${storage_key}" \
        --output none
    
    log_success "Time Series Insights environment created"
    log_info "TSI environment will need additional configuration for IoT Central data export"
}

# Implement anomaly detection queries
implement_anomaly_detection() {
    log_info "Implementing anomaly detection queries in ADX..."
    
    local anomaly_query="
.create-or-alter function DetectAnomalies() {
    TelemetryData
    | where Timestamp > ago(1h)
    | make-series Temperature=avg(Temperature) default=0 on Timestamp step 1m by DeviceId
    | extend (anomalies, score, baseline) = series_decompose_anomalies(Temperature, 1.5, -1, 'linefit')
    | mv-expand Timestamp, Temperature, anomalies, score, baseline
    | where anomalies == 1
    | project DeviceId, Timestamp, Temperature, score, baseline
}

.create-or-alter function PredictMaintenance() {
    TelemetryData
    | where Timestamp > ago(7d)
    | summarize AvgVibration=avg(Vibration), MaxVibration=max(Vibration), OperatingHours=max(OperatingHours) by DeviceId
    | extend MaintenanceRisk = case(
        MaxVibration > 50 and OperatingHours > 1000, 'High',
        MaxVibration > 30 and OperatingHours > 500, 'Medium',
        'Low'
    )
    | project DeviceId, MaintenanceRisk, AvgVibration, OperatingHours
}
"
    
    # Execute query to create functions
    echo "${anomaly_query}" | az kusto query \
        --cluster-name "${ADX_CLUSTER}" \
        --database-name "${ADX_DATABASE}" \
        --query-input stdin \
        --output none
    
    log_success "Anomaly detection queries configured"
}

# Create sample digital twin instances
create_sample_twins() {
    log_info "Creating sample digital twin instances..."
    
    for i in {1..3}; do
        local twin_id="equipment-${i}"
        local twin_init="{
            \"\$metadata\": {
                \"\$model\": \"dtmi:com:example:IndustrialEquipment;1\"
            },
            \"temperature\": 25.0,
            \"vibration\": 5.0,
            \"operatingHours\": 100,
            \"maintenanceStatus\": \"Normal\"
        }"
        
        log_info "Creating digital twin: $twin_id"
        echo "${twin_init}" | az dt twin create \
            --dt-name "${ADT_NAME}" \
            --twin-id "${twin_id}" \
            --twin-init stdin \
            --output none
        
        log_success "Created digital twin: $twin_id"
    done
    
    log_info "Querying all created twins"
    az dt twin query \
        --dt-name "${ADT_NAME}" \
        --query-command "SELECT * FROM digitaltwins" \
        --output table
}

# Perform validation checks
validate_deployment() {
    log_info "Performing deployment validation..."
    
    # Check ADT instance status
    log_info "Validating Azure Digital Twins deployment"
    local adt_status=$(az dt show \
        --name "${ADT_NAME}" \
        --query provisioningState \
        --output tsv)
    
    if [[ "$adt_status" == "Succeeded" ]]; then
        log_success "Azure Digital Twins instance is active"
    else
        log_warning "Azure Digital Twins status: $adt_status"
    fi
    
    # Check ADX cluster status
    log_info "Validating Azure Data Explorer deployment"
    local adx_status=$(az kusto cluster show \
        --name "${ADX_CLUSTER}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query state \
        --output tsv)
    
    if [[ "$adx_status" == "Running" ]]; then
        log_success "Azure Data Explorer cluster is running"
    else
        log_warning "Azure Data Explorer status: $adx_status"
    fi
    
    # List uploaded models
    log_info "Listing Digital Twin models"
    az dt model list \
        --dt-name "${ADT_NAME}" \
        --query '[].{Model:id, DisplayName:displayName}' \
        --output table
    
    log_success "Deployment validation completed"
}

# Print deployment summary
print_deployment_summary() {
    echo
    echo "=================================================="
    echo "   DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=================================================="
    echo
    log_success "Azure IoT Digital Twins solution deployed successfully!"
    echo
    echo "Resource Details:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Random Suffix: $RANDOM_SUFFIX"
    echo
    echo "Key Services:"
    echo "  Azure Digital Twins: $ADT_NAME"
    echo "  Azure Data Explorer: $ADX_CLUSTER"
    echo "  IoT Central: $IOTC_APP"
    echo "  Function App: $FUNC_APP"
    echo "  Event Hub: $EVENT_HUB_NS/$EVENT_HUB_NAME"
    echo "  Time Series Insights: $TSI_ENV"
    echo
    echo "Access URLs:"
    echo "  IoT Central: https://${IOTC_APP}.azureiotcentral.com"
    echo "  Digital Twins Explorer: https://${ADT_NAME}.api.${LOCATION}.digitaltwins.azure.net/explorer"
    echo "  Azure Data Explorer: https://${ADX_CLUSTER}.${LOCATION}.kusto.windows.net"
    echo
    log_warning "Important: This deployment creates billable resources."
    log_warning "Estimated monthly cost: \$150-200 for demo workload"
    log_warning "Run ./destroy.sh when you're done testing to avoid charges."
    echo
    log_info "Environment variables saved to .env.deploy for cleanup script"
    echo "=================================================="
}

# Main deployment function
main() {
    print_header
    check_prerequisites
    get_user_confirmation
    
    log_info "Starting deployment process..."
    
    set_environment_variables
    create_foundation
    create_digital_twins
    create_iot_central
    create_event_hub
    deploy_data_explorer
    configure_digital_twins
    create_function_apps
    configure_data_ingestion
    setup_time_series_insights
    implement_anomaly_detection
    create_sample_twins
    validate_deployment
    
    # Clean up temporary files
    rm -f equipment-model.json
    
    print_deployment_summary
    
    log_success "Deployment completed in approximately $(date)"
}

# Run main function
main "$@"