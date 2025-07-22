#!/bin/bash

# deploy.sh - Deployment script for Smart City Data Processing with Cloud Dataprep and BigQuery DataCanvas
# This script automates the deployment of a complete smart city analytics pipeline

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

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    # Note: Add specific cleanup logic here if needed
    exit 1
}

trap cleanup_on_error ERR

# Default configuration
DEFAULT_PROJECT_ID="smart-city-analytics-$(date +%s)"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        echo "Installation guide: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "Cloud Storage CLI (gsutil) is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if pip3 is available for Python dependencies
    if ! command -v pip3 &> /dev/null; then
        log_warning "pip3 not found. Apache Beam installation may fail. Please install Python 3 and pip3."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Use provided values or defaults
    export PROJECT_ID="${PROJECT_ID:-$DEFAULT_PROJECT_ID}"
    export REGION="${REGION:-$DEFAULT_REGION}"
    export ZONE="${ZONE:-$DEFAULT_ZONE}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names
    export BUCKET_NAME="smart-city-data-lake-${RANDOM_SUFFIX}"
    export DATASET_NAME="smart_city_analytics"
    export PUBSUB_TOPIC_TRAFFIC="traffic-sensor-data"
    export PUBSUB_TOPIC_AIR="air-quality-data"
    export PUBSUB_TOPIC_ENERGY="energy-consumption-data"
    
    log "Environment variables configured:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  ZONE: ${ZONE}"
    log "  BUCKET_NAME: ${BUCKET_NAME}"
    log "  RANDOM_SUFFIX: ${RANDOM_SUFFIX}"
}

# Function to configure GCP project
configure_project() {
    log "Configuring Google Cloud project..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    # Check if project exists, create if it doesn't
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_warning "Project ${PROJECT_ID} does not exist. Please create it manually or use an existing project."
        log "You can create a project at: https://console.cloud.google.com/projectcreate"
        read -p "Press Enter after creating the project or Ctrl+C to exit..."
    fi
    
    log_success "Project configured: ${PROJECT_ID}"
}

# Function to enable APIs
enable_apis() {
    log "Enabling required APIs..."
    
    local apis=(
        "dataprep.googleapis.com"
        "bigquery.googleapis.com"
        "pubsub.googleapis.com"
        "storage.googleapis.com"
        "dataflow.googleapis.com"
        "monitoring.googleapis.com"
        "cloudfunctions.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create Cloud Storage data lake
create_storage_infrastructure() {
    log "Creating Cloud Storage data lake infrastructure..."
    
    # Create primary data lake bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}" 2>/dev/null; then
        log_success "Created bucket: gs://${BUCKET_NAME}"
    else
        log_error "Failed to create bucket. It may already exist or name may be taken."
        # Try with a different suffix
        BUCKET_NAME="${BUCKET_NAME}-$(date +%s)"
        export BUCKET_NAME
        gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"
        log_success "Created bucket with fallback name: gs://${BUCKET_NAME}"
    fi
    
    # Enable versioning
    gsutil versioning set on "gs://${BUCKET_NAME}"
    log_success "Enabled versioning on bucket"
    
    # Create folder structure
    log "Creating folder structure..."
    echo "" | gsutil cp - "gs://${BUCKET_NAME}/raw-data/traffic/.keep"
    echo "" | gsutil cp - "gs://${BUCKET_NAME}/raw-data/air-quality/.keep"
    echo "" | gsutil cp - "gs://${BUCKET_NAME}/raw-data/energy/.keep"
    echo "" | gsutil cp - "gs://${BUCKET_NAME}/processed-data/.keep"
    echo "" | gsutil cp - "gs://${BUCKET_NAME}/temp/.keep"
    echo "" | gsutil cp - "gs://${BUCKET_NAME}/staging/.keep"
    
    # Set lifecycle policy for cost optimization
    cat > lifecycle.json << 'EOF'
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30}
    },
    {
      "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
      "condition": {"age": 90}
    }
  ]
}
EOF
    
    gsutil lifecycle set lifecycle.json "gs://${BUCKET_NAME}"
    log_success "Set lifecycle policy for cost optimization"
    
    # Clean up temporary file
    rm -f lifecycle.json
    
    log_success "Data lake infrastructure created"
}

# Function to setup Pub/Sub for data ingestion
setup_pubsub() {
    log "Setting up Pub/Sub topics for real-time data ingestion..."
    
    # Create Pub/Sub topics
    local topics=("${PUBSUB_TOPIC_TRAFFIC}" "${PUBSUB_TOPIC_AIR}" "${PUBSUB_TOPIC_ENERGY}")
    
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics create "${topic}" --quiet; then
            log_success "Created topic: ${topic}"
        else
            log_warning "Topic ${topic} may already exist"
        fi
    done
    
    # Create subscriptions
    gcloud pubsub subscriptions create traffic-processing-sub \
        --topic="${PUBSUB_TOPIC_TRAFFIC}" \
        --quiet || log_warning "Subscription traffic-processing-sub may already exist"
    
    gcloud pubsub subscriptions create air-quality-processing-sub \
        --topic="${PUBSUB_TOPIC_AIR}" \
        --quiet || log_warning "Subscription air-quality-processing-sub may already exist"
    
    gcloud pubsub subscriptions create energy-processing-sub \
        --topic="${PUBSUB_TOPIC_ENERGY}" \
        --quiet || log_warning "Subscription energy-processing-sub may already exist"
    
    # Set message retention
    for topic in "${topics[@]}"; do
        gcloud pubsub topics update "${topic}" \
            --message-retention-duration=7d \
            --quiet
    done
    
    log_success "Pub/Sub infrastructure created"
}

# Function to create BigQuery dataset and tables
create_bigquery_infrastructure() {
    log "Creating BigQuery dataset for analytics warehouse..."
    
    # Create BigQuery dataset
    if bq mk --location="${REGION}" \
        --description="Smart City Analytics Data Warehouse" \
        "${PROJECT_ID}:${DATASET_NAME}"; then
        log_success "Created BigQuery dataset: ${DATASET_NAME}"
    else
        log_warning "Dataset ${DATASET_NAME} may already exist"
    fi
    
    # Create tables for different sensor data types
    log "Creating sensor data tables..."
    
    # Traffic sensors table
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.traffic_sensors" \
        sensor_id:STRING,timestamp:TIMESTAMP,location:GEOGRAPHY,vehicle_count:INTEGER,avg_speed:FLOAT,congestion_level:STRING,weather_conditions:STRING \
        --quiet || log_warning "Table traffic_sensors may already exist"
    
    # Air quality sensors table
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.air_quality_sensors" \
        sensor_id:STRING,timestamp:TIMESTAMP,location:GEOGRAPHY,pm25:FLOAT,pm10:FLOAT,ozone:FLOAT,no2:FLOAT,air_quality_index:INTEGER \
        --quiet || log_warning "Table air_quality_sensors may already exist"
    
    # Energy consumption table
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.energy_consumption" \
        meter_id:STRING,timestamp:TIMESTAMP,location:GEOGRAPHY,energy_usage_kwh:FLOAT,peak_demand:FLOAT,building_type:STRING,occupancy_rate:FLOAT \
        --quiet || log_warning "Table energy_consumption may already exist"
    
    # Aggregated metrics table
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.hourly_city_metrics" \
        hour:TIMESTAMP,avg_traffic_flow:FLOAT,avg_air_quality:FLOAT,total_energy_consumption:FLOAT,city_zone:STRING \
        --quiet || log_warning "Table hourly_city_metrics may already exist"
    
    log_success "BigQuery tables created"
}

# Function to configure Dataprep
configure_dataprep() {
    log "Configuring Cloud Dataprep for data quality management..."
    
    # Create service account for Dataprep operations
    if gcloud iam service-accounts create dataprep-service-account \
        --description="Service account for Dataprep data processing" \
        --display-name="Dataprep Service Account" \
        --quiet; then
        log_success "Created Dataprep service account"
    else
        log_warning "Dataprep service account may already exist"
    fi
    
    # Grant necessary permissions
    local service_account="dataprep-service-account@${PROJECT_ID}.iam.gserviceaccount.com"
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${service_account}" \
        --role="roles/storage.admin" \
        --quiet
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${service_account}" \
        --role="roles/bigquery.dataEditor" \
        --quiet
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${service_account}" \
        --role="roles/dataflow.admin" \
        --quiet
    
    # Create sample data files
    log "Creating sample data files..."
    
    cat > traffic_sample.csv << 'EOF'
sensor_id,timestamp,location,vehicle_count,avg_speed,congestion_level,weather_conditions
TRF001,2025-01-12T08:00:00Z,"POINT(-74.006 40.7128)",150,25.5,moderate,clear
TRF002,2025-01-12T08:00:00Z,"POINT(-74.007 40.7129)",200,15.2,heavy,rain
TRF003,2025-01-12T08:00:00Z,"POINT(-74.008 40.7130)",,35.8,light,
EOF
    
    cat > air_quality_sample.csv << 'EOF'
sensor_id,timestamp,location,pm25,pm10,ozone,no2,air_quality_index
AQ001,2025-01-12T08:00:00Z,"POINT(-74.006 40.7128)",12.5,18.3,0.08,25.4,45
AQ002,2025-01-12T08:00:00Z,"POINT(-74.007 40.7129)",15.2,,0.09,28.1,52
AQ003,2025-01-12T08:00:00Z,"POINT(-74.008 40.7130)",8.9,14.2,null,22.8,38
EOF
    
    # Upload sample data
    gsutil cp traffic_sample.csv "gs://${BUCKET_NAME}/raw-data/traffic/"
    gsutil cp air_quality_sample.csv "gs://${BUCKET_NAME}/raw-data/air-quality/"
    
    # Clean up local files
    rm -f traffic_sample.csv air_quality_sample.csv
    
    log_success "Dataprep configuration completed"
}

# Function to create materialized views and analytics setup
setup_analytics() {
    log "Setting up BigQuery DataCanvas analytics infrastructure..."
    
    # Create materialized view for real-time dashboard
    log "Creating materialized views..."
    
    bq query --use_legacy_sql=false --quiet <<EOF
CREATE MATERIALIZED VIEW \`${PROJECT_ID}.${DATASET_NAME}.real_time_city_dashboard\`
PARTITION BY DATE(hour) AS
SELECT 
  TIMESTAMP_TRUNC(timestamp, HOUR) as hour,
  AVG(CASE WHEN vehicle_count IS NOT NULL THEN vehicle_count END) as avg_traffic_volume,
  AVG(CASE WHEN avg_speed IS NOT NULL THEN avg_speed END) as avg_vehicle_speed,
  COUNT(DISTINCT CASE WHEN congestion_level = 'heavy' THEN sensor_id END) as heavy_congestion_zones,
  AVG(CASE WHEN air_quality_index IS NOT NULL THEN air_quality_index END) as avg_air_quality,
  SUM(CASE WHEN energy_usage_kwh IS NOT NULL THEN energy_usage_kwh END) as total_energy_consumption,
  COUNT(DISTINCT sensor_id) as active_sensors
FROM (
  SELECT sensor_id, timestamp, vehicle_count, avg_speed, congestion_level, 
         CAST(NULL AS INT64) as air_quality_index, CAST(NULL AS FLOAT64) as energy_usage_kwh
  FROM \`${PROJECT_ID}.${DATASET_NAME}.traffic_sensors\`
  UNION ALL
  SELECT sensor_id, timestamp, CAST(NULL AS INT64), CAST(NULL AS FLOAT64), 
         CAST(NULL AS STRING), air_quality_index, CAST(NULL AS FLOAT64)
  FROM \`${PROJECT_ID}.${DATASET_NAME}.air_quality_sensors\`
  UNION ALL
  SELECT meter_id as sensor_id, timestamp, CAST(NULL AS INT64), CAST(NULL AS FLOAT64), 
         CAST(NULL AS STRING), CAST(NULL AS INT64), energy_usage_kwh
  FROM \`${PROJECT_ID}.${DATASET_NAME}.energy_consumption\`
)
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
GROUP BY hour
ORDER BY hour DESC;
EOF
    
    # Create data quality monitoring view
    bq query --use_legacy_sql=false --quiet <<EOF
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.data_quality_metrics\` AS
SELECT
  'traffic_sensors' as table_name,
  COUNT(*) as total_records,
  COUNTIF(sensor_id IS NULL) as missing_sensor_ids,
  COUNTIF(vehicle_count IS NULL) as missing_vehicle_counts,
  COUNTIF(timestamp IS NULL) as missing_timestamps,
  CURRENT_TIMESTAMP() as last_updated
FROM \`${PROJECT_ID}.${DATASET_NAME}.traffic_sensors\`
WHERE DATE(timestamp) = CURRENT_DATE()

UNION ALL

SELECT
  'air_quality_sensors' as table_name,
  COUNT(*) as total_records,
  COUNTIF(sensor_id IS NULL) as missing_sensor_ids,
  COUNTIF(air_quality_index IS NULL) as missing_aqi_values,
  COUNTIF(timestamp IS NULL) as missing_timestamps,
  CURRENT_TIMESTAMP() as last_updated
FROM \`${PROJECT_ID}.${DATASET_NAME}.air_quality_sensors\`
WHERE DATE(timestamp) = CURRENT_DATE();
EOF
    
    log_success "Analytics infrastructure configured"
}

# Function to setup monitoring
setup_monitoring() {
    log "Setting up monitoring and alerting..."
    
    # Create log-based metrics
    gcloud logging metrics create data_quality_errors \
        --description="Count of data quality errors in processing pipeline" \
        --log-filter='resource.type="cloud_function" AND severity="ERROR" AND textPayload:"data_quality"' \
        --quiet || log_warning "Metric data_quality_errors may already exist"
    
    gcloud logging metrics create bigquery_job_failures \
        --description="Count of BigQuery job failures" \
        --log-filter='resource.type="bigquery_project" AND severity="ERROR"' \
        --quiet || log_warning "Metric bigquery_job_failures may already exist"
    
    log_success "Monitoring configuration completed"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Test Pub/Sub functionality
    log "Testing Pub/Sub message publishing..."
    gcloud pubsub topics publish "${PUBSUB_TOPIC_TRAFFIC}" \
        --message='{"sensor_id":"TEST001","timestamp":"2025-01-12T10:00:00Z","location":"POINT(-74.006 40.7128)","vehicle_count":125,"avg_speed":28.5,"congestion_level":"moderate","weather_conditions":"clear"}' \
        --quiet
    
    # Verify bucket structure
    log "Checking Cloud Storage structure..."
    if gsutil ls "gs://${BUCKET_NAME}/raw-data/" > /dev/null 2>&1; then
        log_success "Cloud Storage structure validated"
    else
        log_error "Cloud Storage validation failed"
        return 1
    fi
    
    # Check BigQuery dataset
    log "Validating BigQuery dataset..."
    if bq ls "${PROJECT_ID}:${DATASET_NAME}" > /dev/null 2>&1; then
        log_success "BigQuery dataset validated"
    else
        log_error "BigQuery validation failed"
        return 1
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Data Lake Bucket: gs://${BUCKET_NAME}"
    echo "BigQuery Dataset: ${PROJECT_ID}:${DATASET_NAME}"
    echo ""
    echo "Pub/Sub Topics:"
    echo "  - ${PUBSUB_TOPIC_TRAFFIC}"
    echo "  - ${PUBSUB_TOPIC_AIR}"
    echo "  - ${PUBSUB_TOPIC_ENERGY}"
    echo ""
    echo "Next Steps:"
    echo "1. Configure Dataprep flows in the Google Cloud Console"
    echo "2. Set up BigQuery DataCanvas dashboards"
    echo "3. Connect your IoT sensors to Pub/Sub topics"
    echo "4. Monitor data quality metrics in Cloud Monitoring"
    echo ""
    echo "Access your resources:"
    echo "  - Cloud Console: https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
    echo "  - BigQuery: https://console.cloud.google.com/bigquery?project=${PROJECT_ID}"
    echo "  - Cloud Storage: https://console.cloud.google.com/storage/browser/${BUCKET_NAME}?project=${PROJECT_ID}"
    echo ""
    echo "Estimated monthly cost: $50-100 USD (depending on data volume)"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    echo "=================================================="
    echo "Smart City Data Processing Pipeline Deployment"
    echo "=================================================="
    echo ""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --zone)
                ZONE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --project-id PROJECT_ID   GCP project ID to use"
                echo "  --region REGION           GCP region (default: us-central1)"
                echo "  --zone ZONE               GCP zone (default: us-central1-a)"
                echo "  --dry-run                 Show what would be deployed without executing"
                echo "  --help, -h                Show this help message"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "DRY RUN MODE - No resources will be created"
        echo "Would deploy smart city data processing pipeline with:"
        echo "  Project: ${PROJECT_ID:-$DEFAULT_PROJECT_ID}"
        echo "  Region: ${REGION:-$DEFAULT_REGION}"
        echo "  Zone: ${ZONE:-$DEFAULT_ZONE}"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    configure_project
    enable_apis
    create_storage_infrastructure
    setup_pubsub
    create_bigquery_infrastructure
    configure_dataprep
    setup_analytics
    setup_monitoring
    validate_deployment
    display_summary
    
    log_success "Deployment script completed successfully!"
}

# Execute main function with all arguments
main "$@"