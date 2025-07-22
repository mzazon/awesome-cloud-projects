#!/bin/bash

# Deploy script for Fleet Tracking with Geospatial Analytics
# This script deploys the complete infrastructure for fleet management geospatial analytics

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    info "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please log in to Azure CLI using 'az login'"
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Some output parsing may be limited."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random values"
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Resource configuration
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-geospatial-analytics}"
    export LOCATION="${LOCATION:-eastus}"
    export RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
    
    # Service-specific names
    export EVENTHUB_NAMESPACE="ehns-fleet-${RANDOM_SUFFIX}"
    export EVENTHUB_NAME="vehicle-locations"
    export STORAGE_ACCOUNT="stfleet${RANDOM_SUFFIX}"
    export ASA_JOB="asa-geospatial-${RANDOM_SUFFIX}"
    export COSMOS_ACCOUNT="cosmos-fleet-${RANDOM_SUFFIX}"
    export MAPS_ACCOUNT="maps-fleet-${RANDOM_SUFFIX}"
    
    info "Resource Group: $RESOURCE_GROUP"
    info "Location: $LOCATION"
    info "Random Suffix: $RANDOM_SUFFIX"
    info "Event Hub Namespace: $EVENTHUB_NAMESPACE"
    info "Storage Account: $STORAGE_ACCOUNT"
    info "Stream Analytics Job: $ASA_JOB"
    info "Cosmos Account: $COSMOS_ACCOUNT"
    info "Maps Account: $MAPS_ACCOUNT"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=geospatial-analytics environment=demo \
            --output none
        
        log "✅ Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account..."
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Storage account $STORAGE_ACCOUNT already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --output none
        
        log "✅ Storage account created: $STORAGE_ACCOUNT"
    fi
    
    # Create containers
    log "Creating storage containers..."
    
    # Get storage account key
    local storage_key=$(az storage account keys list \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].value" \
        --output tsv)
    
    # Create geofences container
    az storage container create \
        --name geofences \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" \
        --public-access off \
        --output none 2>/dev/null || true
    
    # Create telemetry archive container
    az storage container create \
        --name telemetry-archive \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" \
        --public-access off \
        --output none 2>/dev/null || true
    
    log "✅ Storage containers created"
}

# Function to create Event Hub
create_event_hub() {
    log "Creating Event Hub namespace and hub..."
    
    if az eventhubs namespace show --name "$EVENTHUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Event Hub namespace $EVENTHUB_NAMESPACE already exists"
    else
        az eventhubs namespace create \
            --name "$EVENTHUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard \
            --capacity 2 \
            --output none
        
        log "✅ Event Hub namespace created: $EVENTHUB_NAMESPACE"
    fi
    
    # Create event hub
    if az eventhubs eventhub show --name "$EVENTHUB_NAME" --namespace-name "$EVENTHUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Event Hub $EVENTHUB_NAME already exists"
    else
        az eventhubs eventhub create \
            --name "$EVENTHUB_NAME" \
            --namespace-name "$EVENTHUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --partition-count 4 \
            --retention-time 24 \
            --output none
        
        log "✅ Event Hub created: $EVENTHUB_NAME"
    fi
    
    # Get connection string
    export EVENTHUB_CONNECTION=$(az eventhubs namespace authorization-rule keys list \
        --resource-group "$RESOURCE_GROUP" \
        --namespace-name "$EVENTHUB_NAMESPACE" \
        --name RootManageSharedAccessKey \
        --query primaryConnectionString \
        --output tsv)
    
    log "✅ Event Hub connection string retrieved"
}

# Function to create Cosmos DB
create_cosmos_db() {
    log "Creating Cosmos DB account..."
    
    if az cosmosdb show --name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Cosmos DB account $COSMOS_ACCOUNT already exists"
    else
        az cosmosdb create \
            --name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --locations regionName="$LOCATION" \
            --default-consistency-level Eventual \
            --enable-automatic-failover false \
            --output none
        
        log "✅ Cosmos DB account created: $COSMOS_ACCOUNT"
    fi
    
    # Create database
    if az cosmosdb sql database show --account-name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --name FleetAnalytics &> /dev/null; then
        warn "Cosmos DB database FleetAnalytics already exists"
    else
        az cosmosdb sql database create \
            --account-name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --name FleetAnalytics \
            --output none
        
        log "✅ Cosmos DB database created: FleetAnalytics"
    fi
    
    # Create container
    if az cosmosdb sql container show --account-name "$COSMOS_ACCOUNT" --resource-group "$RESOURCE_GROUP" --database-name FleetAnalytics --name LocationEvents &> /dev/null; then
        warn "Cosmos DB container LocationEvents already exists"
    else
        az cosmosdb sql container create \
            --account-name "$COSMOS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --database-name FleetAnalytics \
            --name LocationEvents \
            --partition-key-path /vehicleId \
            --throughput 400 \
            --output none
        
        log "✅ Cosmos DB container created: LocationEvents"
    fi
    
    # Get connection key
    export COSMOS_KEY=$(az cosmosdb keys list \
        --name "$COSMOS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryKey \
        --output tsv)
    
    log "✅ Cosmos DB key retrieved"
}

# Function to create Azure Maps
create_azure_maps() {
    log "Creating Azure Maps account..."
    
    if az maps account show --name "$MAPS_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Azure Maps account $MAPS_ACCOUNT already exists"
    else
        az maps account create \
            --name "$MAPS_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --sku G2 \
            --kind Gen2 \
            --output none
        
        log "✅ Azure Maps account created: $MAPS_ACCOUNT"
    fi
    
    # Get Maps primary key
    export MAPS_KEY=$(az maps account keys list \
        --name "$MAPS_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryKey \
        --output tsv)
    
    log "✅ Azure Maps key retrieved"
}

# Function to create Stream Analytics job
create_stream_analytics_job() {
    log "Creating Stream Analytics job..."
    
    if az stream-analytics job show --name "$ASA_JOB" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Stream Analytics job $ASA_JOB already exists"
    else
        az stream-analytics job create \
            --name "$ASA_JOB" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard \
            --output-error-policy Drop \
            --events-outoforder-policy Adjust \
            --events-late-arrival-max-delay 5 \
            --output none
        
        log "✅ Stream Analytics job created: $ASA_JOB"
    fi
}

# Function to configure Stream Analytics input
configure_stream_analytics_input() {
    log "Configuring Stream Analytics input..."
    
    # Extract shared access key from connection string
    local shared_access_key=$(echo "$EVENTHUB_CONNECTION" | sed -n 's/.*SharedAccessKey=\([^;]*\).*/\1/p')
    
    # Create input configuration
    cat > /tmp/input_config.json << EOF
{
    "type": "Microsoft.EventHub/EventHub",
    "properties": {
        "serviceBusNamespace": "$EVENTHUB_NAMESPACE",
        "eventHubName": "$EVENTHUB_NAME",
        "consumerGroupName": "\$Default",
        "sharedAccessPolicyName": "RootManageSharedAccessKey",
        "sharedAccessPolicyKey": "$shared_access_key"
    }
}
EOF
    
    # Create or update input
    if az stream-analytics input show --job-name "$ASA_JOB" --resource-group "$RESOURCE_GROUP" --name VehicleInput &> /dev/null; then
        warn "Stream Analytics input VehicleInput already exists"
    else
        az stream-analytics input create \
            --job-name "$ASA_JOB" \
            --resource-group "$RESOURCE_GROUP" \
            --name VehicleInput \
            --type Stream \
            --datasource @/tmp/input_config.json \
            --output none
        
        log "✅ Stream Analytics input configured: VehicleInput"
    fi
    
    # Cleanup temporary file
    rm -f /tmp/input_config.json
}

# Function to configure Stream Analytics query
configure_stream_analytics_query() {
    log "Configuring Stream Analytics query..."
    
    # Create geospatial query
    cat > /tmp/query.sql << 'EOF'
WITH GeofencedData AS (
    SELECT
        vehicleId,
        location,
        speed,
        timestamp,
        ST_WITHIN(
            CreatePoint(CAST(location.longitude AS float), 
                      CAST(location.latitude AS float)),
            CreatePolygon(
                CreatePoint(-122.135, 47.642),
                CreatePoint(-122.135, 47.658),
                CreatePoint(-122.112, 47.658),
                CreatePoint(-122.112, 47.642),
                CreatePoint(-122.135, 47.642)
            )
        ) AS isInZone,
        ST_DISTANCE(
            CreatePoint(CAST(location.longitude AS float), 
                      CAST(location.latitude AS float)),
            CreatePoint(-122.123, 47.650)
        ) AS distanceFromDepot
    FROM VehicleInput
)
SELECT
    vehicleId,
    location,
    speed,
    timestamp,
    isInZone,
    distanceFromDepot,
    CASE 
        WHEN speed > 80 THEN 'Speeding Alert'
        WHEN isInZone = 0 THEN 'Outside Geofence'
        ELSE 'Normal'
    END AS alertType
INTO VehicleOutput
FROM GeofencedData;

SELECT
    vehicleId,
    location,
    speed,
    timestamp,
    isInZone,
    distanceFromDepot,
    alertType
INTO ArchiveOutput
FROM GeofencedData;
EOF
    
    # Update job with query
    local query_content=$(cat /tmp/query.sql)
    az stream-analytics job update \
        --name "$ASA_JOB" \
        --resource-group "$RESOURCE_GROUP" \
        --transformation-query "$query_content" \
        --output none
    
    log "✅ Stream Analytics query configured"
    
    # Cleanup temporary file
    rm -f /tmp/query.sql
}

# Function to configure Stream Analytics outputs
configure_stream_analytics_outputs() {
    log "Configuring Stream Analytics outputs..."
    
    # Configure Cosmos DB output
    cat > /tmp/cosmos_output.json << EOF
{
    "type": "Microsoft.Storage/DocumentDB",
    "properties": {
        "accountId": "$COSMOS_ACCOUNT",
        "accountKey": "$COSMOS_KEY",
        "database": "FleetAnalytics",
        "collectionNamePattern": "LocationEvents"
    }
}
EOF
    
    if az stream-analytics output show --job-name "$ASA_JOB" --resource-group "$RESOURCE_GROUP" --name VehicleOutput &> /dev/null; then
        warn "Stream Analytics output VehicleOutput already exists"
    else
        az stream-analytics output create \
            --job-name "$ASA_JOB" \
            --resource-group "$RESOURCE_GROUP" \
            --name VehicleOutput \
            --datasource @/tmp/cosmos_output.json \
            --output none
        
        log "✅ Cosmos DB output configured: VehicleOutput"
    fi
    
    # Configure blob storage output
    local storage_key=$(az storage account keys list \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].value" \
        --output tsv)
    
    cat > /tmp/blob_output.json << EOF
{
    "type": "Microsoft.Storage/Blob",
    "properties": {
        "storageAccounts": [{
            "accountName": "$STORAGE_ACCOUNT",
            "accountKey": "$storage_key"
        }],
        "container": "telemetry-archive",
        "pathPattern": "vehicles/{date}/{time}",
        "dateFormat": "yyyy/MM/dd",
        "timeFormat": "HH"
    }
}
EOF
    
    if az stream-analytics output show --job-name "$ASA_JOB" --resource-group "$RESOURCE_GROUP" --name ArchiveOutput &> /dev/null; then
        warn "Stream Analytics output ArchiveOutput already exists"
    else
        az stream-analytics output create \
            --job-name "$ASA_JOB" \
            --resource-group "$RESOURCE_GROUP" \
            --name ArchiveOutput \
            --datasource @/tmp/blob_output.json \
            --output none
        
        log "✅ Blob storage output configured: ArchiveOutput"
    fi
    
    # Cleanup temporary files
    rm -f /tmp/cosmos_output.json /tmp/blob_output.json
}

# Function to start Stream Analytics job
start_stream_analytics_job() {
    log "Starting Stream Analytics job..."
    
    # Check current job state
    local job_state=$(az stream-analytics job show \
        --name "$ASA_JOB" \
        --resource-group "$RESOURCE_GROUP" \
        --query jobState \
        --output tsv)
    
    if [[ "$job_state" == "Running" ]]; then
        warn "Stream Analytics job is already running"
    else
        az stream-analytics job start \
            --name "$ASA_JOB" \
            --resource-group "$RESOURCE_GROUP" \
            --output-start-mode JobStartTime \
            --output none
        
        log "✅ Stream Analytics job started: $ASA_JOB"
        
        # Wait for job to start
        info "Waiting for job to start..."
        local max_attempts=30
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            local current_state=$(az stream-analytics job show \
                --name "$ASA_JOB" \
                --resource-group "$RESOURCE_GROUP" \
                --query jobState \
                --output tsv)
            
            if [[ "$current_state" == "Running" ]]; then
                log "✅ Stream Analytics job is now running"
                break
            elif [[ "$current_state" == "Failed" ]]; then
                error "Stream Analytics job failed to start"
            fi
            
            info "Job state: $current_state (attempt $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            warn "Job start verification timed out, but deployment may still be successful"
        fi
    fi
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring monitoring and alerts..."
    
    # Create action group
    if az monitor action-group show --name fleet-alerts --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Action group fleet-alerts already exists"
    else
        az monitor action-group create \
            --name fleet-alerts \
            --resource-group "$RESOURCE_GROUP" \
            --short-name FleetOps \
            --output none
        
        log "✅ Action group created: fleet-alerts"
    fi
    
    # Get Stream Analytics job resource ID
    local asa_resource_id=$(az stream-analytics job show \
        --name "$ASA_JOB" \
        --resource-group "$RESOURCE_GROUP" \
        --query id \
        --output tsv)
    
    # Create metric alert for high latency
    if az monitor metrics alert show --name high-processing-latency --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Metric alert high-processing-latency already exists"
    else
        az monitor metrics alert create \
            --name high-processing-latency \
            --resource-group "$RESOURCE_GROUP" \
            --scopes "$asa_resource_id" \
            --condition "avg OutputWatermarkDelaySeconds > 10" \
            --description "Alert when processing latency exceeds 10 seconds" \
            --evaluation-frequency 1m \
            --window-size 5m \
            --severity 2 \
            --output none 2>/dev/null || warn "Failed to create metric alert (may not be supported in this region)"
    fi
    
    # Enable diagnostic logging
    az monitor diagnostic-settings create \
        --name asa-diagnostics \
        --resource "$asa_resource_id" \
        --logs '[{"category": "Execution", "enabled": true}]' \
        --metrics '[{"category": "AllMetrics", "enabled": true}]' \
        --storage-account "$STORAGE_ACCOUNT" \
        --output none 2>/dev/null || warn "Failed to create diagnostic settings"
    
    log "✅ Monitoring configured"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Created Resources:"
    echo "- Event Hub Namespace: $EVENTHUB_NAMESPACE"
    echo "- Event Hub: $EVENTHUB_NAME"
    echo "- Storage Account: $STORAGE_ACCOUNT"
    echo "- Cosmos DB Account: $COSMOS_ACCOUNT"
    echo "- Azure Maps Account: $MAPS_ACCOUNT"
    echo "- Stream Analytics Job: $ASA_JOB"
    echo ""
    echo "Important Keys and Connections:"
    echo "- Event Hub Connection: ${EVENTHUB_CONNECTION:0:50}..."
    echo "- Cosmos DB Key: ${COSMOS_KEY:0:20}..."
    echo "- Azure Maps Key: ${MAPS_KEY:0:20}..."
    echo ""
    echo "Next Steps:"
    echo "1. Test the deployment using the validation commands"
    echo "2. Send sample events to the Event Hub"
    echo "3. Monitor the Stream Analytics job in Azure portal"
    echo "4. Check processed data in Cosmos DB"
    echo ""
    echo "Cleanup: Run ./destroy.sh to remove all resources"
    echo "=================================="
}

# Function to create sample event file
create_sample_event() {
    log "Creating sample event file..."
    
    cat > sample-event.json << EOF
{
    "vehicleId": "VEHICLE-001",
    "location": {
        "latitude": 47.645,
        "longitude": -122.120
    },
    "speed": 65,
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log "✅ Sample event file created: sample-event.json"
}

# Main deployment function
main() {
    log "Starting deployment of Real-Time Geospatial Analytics solution..."
    
    # Check if running in interactive mode
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        # Script is being executed directly
        check_prerequisites
        set_environment_variables
        
        # Confirmation prompt
        if [[ "${SKIP_CONFIRMATION:-false}" != "true" ]]; then
            echo "This will create the following resources in Azure:"
            echo "- Resource Group: $RESOURCE_GROUP"
            echo "- Location: $LOCATION"
            echo "- Estimated monthly cost: ~$150 for moderate workload"
            echo ""
            read -p "Do you want to continue? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Deployment cancelled by user"
                exit 0
            fi
        fi
    fi
    
    # Execute deployment steps
    create_resource_group
    create_storage_account
    create_event_hub
    create_cosmos_db
    create_azure_maps
    create_stream_analytics_job
    configure_stream_analytics_input
    configure_stream_analytics_query
    configure_stream_analytics_outputs
    start_stream_analytics_job
    configure_monitoring
    create_sample_event
    
    log "🎉 Deployment completed successfully!"
    display_summary
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi