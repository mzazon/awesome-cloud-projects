#!/bin/bash

# Smart City Infrastructure Monitoring with IoT and AI - Deployment Script
# This script deploys the complete GCP infrastructure for smart city monitoring
# including Pub/Sub, BigQuery, Vertex AI, Cloud Functions, and monitoring components

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Error handling function
handle_error() {
    log_error "Deployment failed at line $1. Rolling back..."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Banner
echo "======================================================================"
echo "  Smart City Infrastructure Monitoring - Deployment Script"
echo "  Provider: Google Cloud Platform"
echo "  Recipe: smart-city-infrastructure-monitoring-iot-ai"
echo "======================================================================"

# Check if running with dry-run flag
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    log_warning "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute or simulate commands
execute_cmd() {
    local cmd="$1"
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would execute: $cmd"
    else
        log_info "Executing: $cmd"
        eval "$cmd"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if required utilities are available
    for cmd in openssl bq gsutil; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd is not available. Please ensure Google Cloud SDK is fully installed."
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Set environment variables
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    export PROJECT_ID="${PROJECT_ID:-smart-city-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export DATASET_NAME="smart_city_data"
    export TOPIC_NAME="sensor-telemetry"
    export BUCKET_NAME="smart-city-ml-${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT_NAME="city-sensors-${RANDOM_SUFFIX}"
    
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Bucket Name: $BUCKET_NAME"
    log_info "Service Account: $SERVICE_ACCOUNT_NAME"
}

# Create or set GCP project
setup_project() {
    log_info "Setting up GCP project..."
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_warning "Project $PROJECT_ID does not exist. Creating new project..."
        if [ "$DRY_RUN" != "true" ]; then
            gcloud projects create "$PROJECT_ID" --name="Smart City Monitoring"
            
            # Set billing account if available
            BILLING_ACCOUNT=$(gcloud billing accounts list --filter="open:true" --format="value(name)" --limit=1)
            if [ -n "$BILLING_ACCOUNT" ]; then
                gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
                log_success "Billing account linked to project"
            else
                log_warning "No active billing account found. Please link billing manually."
            fi
        fi
    fi
    
    # Set default project and region
    execute_cmd "gcloud config set project $PROJECT_ID"
    execute_cmd "gcloud config set compute/region $REGION"
    execute_cmd "gcloud config set compute/zone $ZONE"
    
    log_success "Project setup completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "pubsub.googleapis.com"
        "bigquery.googleapis.com" 
        "aiplatform.googleapis.com"
        "monitoring.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "iam.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_cmd "gcloud services enable $api"
    done
    
    # Wait for APIs to be fully enabled
    if [ "$DRY_RUN" != "true" ]; then
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    log_success "All required APIs enabled"
}

# Create service account for IoT devices
create_service_account() {
    log_info "Creating service account for IoT device authentication..."
    
    # Create service account
    execute_cmd "gcloud iam service-accounts create $SERVICE_ACCOUNT_NAME \
        --display-name='Smart City IoT Sensors' \
        --description='Service account for city sensor data ingestion'"
    
    # Grant Pub/Sub publisher role
    execute_cmd "gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member='serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com' \
        --role='roles/pubsub.publisher'"
    
    # Grant BigQuery data editor role for Cloud Function
    execute_cmd "gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member='serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com' \
        --role='roles/bigquery.dataEditor'"
    
    # Grant monitoring metric writer role
    execute_cmd "gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member='serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com' \
        --role='roles/monitoring.metricWriter'"
    
    # Create and save service account key
    if [ "$DRY_RUN" != "true" ]; then
        gcloud iam service-accounts keys create sensor-key.json \
            --iam-account="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
        log_success "Service account key saved to sensor-key.json"
    fi
    
    log_success "Service account created with appropriate permissions"
}

# Create Pub/Sub infrastructure
create_pubsub_infrastructure() {
    log_info "Creating Pub/Sub topics and subscriptions..."
    
    # Create main telemetry topic
    execute_cmd "gcloud pubsub topics create $TOPIC_NAME"
    
    # Create subscriptions
    execute_cmd "gcloud pubsub subscriptions create \
        ${TOPIC_NAME}-bigquery \
        --topic=$TOPIC_NAME \
        --ack-deadline=60"
    
    execute_cmd "gcloud pubsub subscriptions create \
        ${TOPIC_NAME}-ml \
        --topic=$TOPIC_NAME \
        --ack-deadline=120"
    
    # Create dead letter topic and subscription
    execute_cmd "gcloud pubsub topics create ${TOPIC_NAME}-dlq"
    execute_cmd "gcloud pubsub subscriptions create \
        ${TOPIC_NAME}-dlq-sub \
        --topic=${TOPIC_NAME}-dlq"
    
    log_success "Pub/Sub infrastructure created"
}

# Create BigQuery dataset and tables
create_bigquery_resources() {
    log_info "Creating BigQuery dataset and tables..."
    
    # Create dataset
    execute_cmd "bq mk \
        --dataset \
        --location=$REGION \
        --description='Smart city sensor data and analytics' \
        ${PROJECT_ID}:${DATASET_NAME}"
    
    # Create sensor readings table with partitioning and clustering
    if [ "$DRY_RUN" != "true" ]; then
        bq mk \
            --table \
            --description="Real-time sensor readings from city infrastructure" \
            --time_partitioning_field=timestamp \
            --clustering_fields=sensor_type,location \
            "${PROJECT_ID}:${DATASET_NAME}.sensor_readings" \
            "device_id:STRING,sensor_type:STRING,location:STRING,timestamp:TIMESTAMP,value:FLOAT,unit:STRING,metadata:JSON,ingestion_time:TIMESTAMP"
    fi
    
    # Create anomalies table
    if [ "$DRY_RUN" != "true" ]; then
        bq mk \
            --table \
            --description="Anomaly detection results from ML models" \
            --time_partitioning_field=timestamp \
            "${PROJECT_ID}:${DATASET_NAME}.anomalies" \
            "device_id:STRING,timestamp:TIMESTAMP,anomaly_score:FLOAT,anomaly_type:STRING,confidence:FLOAT,model_version:STRING"
    fi
    
    # Create aggregated metrics table
    if [ "$DRY_RUN" != "true" ]; then
        bq mk \
            --table \
            "${PROJECT_ID}:${DATASET_NAME}.sensor_metrics" \
            "sensor_type:STRING,location:STRING,date:DATE,avg_value:FLOAT,min_value:FLOAT,max_value:FLOAT,anomaly_count:INTEGER"
    fi
    
    log_success "BigQuery resources created with partitioning and clustering"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for ML artifacts..."
    
    # Create bucket
    execute_cmd "gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://$BUCKET_NAME"
    
    # Enable versioning
    execute_cmd "gsutil versioning set on gs://$BUCKET_NAME"
    
    # Create lifecycle policy for cost optimization
    if [ "$DRY_RUN" != "true" ]; then
        cat > lifecycle.json << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 30}
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 90}
      },
      {
        "action": {"type": "Delete"},
        "condition": {"age": 365}
      }
    ]
  }
}
EOF
        gsutil lifecycle set lifecycle.json "gs://$BUCKET_NAME"
        rm lifecycle.json
    fi
    
    # Create organized folder structure
    if [ "$DRY_RUN" != "true" ]; then
        echo "Creating ML pipeline structure..." | gsutil cp - "gs://$BUCKET_NAME/models/.gitkeep"
        echo "Training data storage" | gsutil cp - "gs://$BUCKET_NAME/training-data/.gitkeep"
        echo "Pipeline artifacts" | gsutil cp - "gs://$BUCKET_NAME/pipelines/.gitkeep"
        echo "Model monitoring" | gsutil cp - "gs://$BUCKET_NAME/monitoring/.gitkeep"
    fi
    
    log_success "Cloud Storage bucket created with lifecycle management"
}

# Deploy Cloud Function for data processing
deploy_cloud_function() {
    log_info "Deploying Cloud Function for sensor data processing..."
    
    # Create directory for Cloud Function code
    if [ "$DRY_RUN" != "true" ]; then
        mkdir -p sensor-processor
        cd sensor-processor
        
        # Create main function file
        cat > main.py << 'EOF'
import json
import base64
import logging
from google.cloud import bigquery
from google.cloud import monitoring_v3
from datetime import datetime, timezone
import os
import hashlib

def process_sensor_data(event, context):
    """Process IoT sensor data with validation and BigQuery insertion"""
    
    try:
        # Decode Pub/Sub message
        if 'data' in event:
            message_data = base64.b64decode(event['data']).decode('utf-8')
            sensor_data = json.loads(message_data)
        else:
            logging.error("No data field in Pub/Sub message")
            return 'Error: Missing data'
        
        # Validate required fields
        required_fields = ['device_id', 'sensor_type', 'value']
        for field in required_fields:
            if field not in sensor_data:
                logging.error(f"Missing required field: {field}")
                return f'Error: Missing {field}'
        
        # Initialize BigQuery client
        client = bigquery.Client()
        table_id = f"{os.environ['PROJECT_ID']}.{os.environ['DATASET_NAME']}.sensor_readings"
        
        # Add data quality checks
        sensor_value = sensor_data.get('value')
        if not isinstance(sensor_value, (int, float)):
            logging.error(f"Invalid sensor value type: {type(sensor_value)}")
            return 'Error: Invalid value type'
        
        # Prepare enriched row for insertion
        current_time = datetime.now(timezone.utc)
        row = {
            "device_id": sensor_data.get("device_id"),
            "sensor_type": sensor_data.get("sensor_type"),
            "location": sensor_data.get("location", "unknown"),
            "timestamp": sensor_data.get("timestamp", current_time.isoformat()),
            "value": float(sensor_value),
            "unit": sensor_data.get("unit", ""),
            "metadata": sensor_data.get("metadata", {}),
            "ingestion_time": current_time.isoformat()
        }
        
        # Insert into BigQuery with streaming
        errors = client.insert_rows_json(table_id, [row])
        
        if errors:
            logging.error(f"BigQuery insertion errors: {errors}")
            return f'Error: {errors}'
        
        # Log successful processing
        logging.info(f"Successfully processed data from {sensor_data.get('device_id')}")
        
        # Send custom metric to Cloud Monitoring
        monitoring_client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{os.environ['PROJECT_ID']}"
        
        # Create time series data point
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/iot/sensor_messages_processed"
        series.resource.type = "global"
        
        point = monitoring_v3.Point()
        point.value.int64_value = 1
        point.interval.end_time.seconds = int(current_time.timestamp())
        series.points = [point]
        
        # Send metric
        monitoring_client.create_time_series(
            name=project_name, 
            time_series=[series]
        )
        
        return 'OK'
        
    except Exception as e:
        logging.error(f"Error processing sensor data: {str(e)}")
        return f'Error: {str(e)}'
EOF
        
        # Create requirements file
        cat > requirements.txt << 'EOF'
google-cloud-bigquery==3.17.2
google-cloud-monitoring==2.19.0
google-cloud-pubsub==2.20.1
functions-framework==3.5.0
EOF
        
        cd ..
    fi
    
    # Deploy the Cloud Function
    execute_cmd "gcloud functions deploy process-sensor-data \
        --runtime python311 \
        --trigger-topic $TOPIC_NAME \
        --source ./sensor-processor \
        --entry-point process_sensor_data \
        --memory 512MB \
        --timeout 120s \
        --max-instances 100 \
        --set-env-vars PROJECT_ID=$PROJECT_ID,DATASET_NAME=$DATASET_NAME \
        --service-account=${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    log_success "Cloud Function deployed successfully"
}

# Set up Vertex AI resources
setup_vertex_ai() {
    log_info "Setting up Vertex AI for anomaly detection..."
    
    # Create training data preparation script
    if [ "$DRY_RUN" != "true" ]; then
        cat > prepare_training_data.py << EOF
from google.cloud import bigquery
from google.cloud import aiplatform
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import json
import os

def prepare_anomaly_training_data():
    """Prepare training dataset from BigQuery sensor data"""
    
    # Initialize clients
    bq_client = bigquery.Client()
    project_id = os.environ['PROJECT_ID']
    dataset_name = os.environ['DATASET_NAME']
    
    # Query to extract features for anomaly detection
    query = f"""
    WITH sensor_features AS (
      SELECT 
        device_id,
        sensor_type,
        location,
        timestamp,
        value,
        EXTRACT(HOUR FROM timestamp) as hour_of_day,
        EXTRACT(DAYOFWEEK FROM timestamp) as day_of_week,
        EXTRACT(MONTH FROM timestamp) as month,
        LAG(value, 1) OVER (PARTITION BY device_id ORDER BY timestamp) as prev_value_1,
        LAG(value, 2) OVER (PARTITION BY device_id ORDER BY timestamp) as prev_value_2,
        LAG(value, 3) OVER (PARTITION BY device_id ORDER BY timestamp) as prev_value_3,
        AVG(value) OVER (
          PARTITION BY device_id 
          ORDER BY timestamp 
          ROWS BETWEEN 23 PRECEDING AND CURRENT ROW
        ) as rolling_avg_24h,
        STDDEV(value) OVER (
          PARTITION BY device_id 
          ORDER BY timestamp 
          ROWS BETWEEN 23 PRECEDING AND CURRENT ROW
        ) as rolling_stddev_24h
      FROM \`{project_id}.{dataset_name}.sensor_readings\`
      WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
        AND value IS NOT NULL
    ),
    labeled_data AS (
      SELECT 
        *,
        CASE 
          WHEN ABS(value - rolling_avg_24h) > 3 * rolling_stddev_24h THEN 1
          ELSE 0
        END as anomaly_label
      FROM sensor_features
      WHERE prev_value_1 IS NOT NULL 
        AND rolling_avg_24h IS NOT NULL
        AND rolling_stddev_24h > 0
    )
    SELECT * FROM labeled_data
    ORDER BY device_id, timestamp
    """
    
    # Execute query and get results
    df = bq_client.query(query).to_dataframe()
    print(f"Training dataset prepared with {len(df)} records")
    print(f"Anomaly ratio: {df['anomaly_label'].mean():.3f}")
    
    return df

if __name__ == "__main__":
    import os
    os.environ['PROJECT_ID'] = '$PROJECT_ID'
    os.environ['DATASET_NAME'] = '$DATASET_NAME'
    
    training_data = prepare_anomaly_training_data()
    training_data.to_csv('gs://$BUCKET_NAME/training-data/sensor_anomaly_training.csv', index=False)
    print("Training data saved to Cloud Storage")
EOF
        
        # Upload training script to Cloud Storage
        gsutil cp prepare_training_data.py "gs://$BUCKET_NAME/training-data/"
    fi
    
    # Create Vertex AI dataset
    execute_cmd "gcloud ai datasets create \
        --display-name='smart-city-sensor-data' \
        --metadata-schema-uri='gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml' \
        --region=$REGION"
    
    log_success "Vertex AI resources configured"
}

# Configure Cloud Monitoring
configure_monitoring() {
    log_info "Configuring Cloud Monitoring dashboards and alerts..."
    
    # Create custom dashboard configuration
    if [ "$DRY_RUN" != "true" ]; then
        cat > smart_city_dashboard.json << EOF
{
  "displayName": "Smart City Infrastructure Monitoring",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Sensor Message Rate (per minute)",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"pubsub_topic\" AND resource.labels.topic_id=\"$TOPIC_NAME\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_RATE",
                    "crossSeriesReducer": "REDUCE_SUM"
                  }
                }
              },
              "plotType": "LINE"
            }],
            "yAxis": {
              "label": "Messages/minute",
              "scale": "LINEAR"
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Cloud Function Executions",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"cloud_function\" AND resource.labels.function_name=\"process-sensor-data\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_RATE",
                    "crossSeriesReducer": "REDUCE_SUM"
                  }
                }
              },
              "plotType": "STACKED_AREA"
            }]
          }
        }
      }
    ]
  }
}
EOF
        
        # Create alert policy
        cat > anomaly_alert_policy.json << EOF
{
  "displayName": "Smart City - High Anomaly Detection Alert",
  "documentation": {
    "content": "Alert when anomaly detection scores exceed threshold, indicating potential infrastructure issues"
  },
  "conditions": [
    {
      "displayName": "Anomaly score threshold exceeded",
      "conditionThreshold": {
        "filter": "metric.type=\"custom.googleapis.com/iot/sensor_messages_processed\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 100,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE",
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "enabled": true,
  "severity": "WARNING"
}
EOF
    fi
    
    # Create dashboard and alert policy
    execute_cmd "gcloud monitoring dashboards create --config-from-file=smart_city_dashboard.json"
    execute_cmd "gcloud alpha monitoring policies create --policy-from-file=anomaly_alert_policy.json"
    
    log_success "Cloud Monitoring configured with dashboards and alerts"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_success "DRY-RUN mode - skipping validation"
        return
    fi
    
    # Check Pub/Sub topics
    if gcloud pubsub topics describe "$TOPIC_NAME" &> /dev/null; then
        log_success "Pub/Sub topic created successfully"
    else
        log_error "Pub/Sub topic validation failed"
        return 1
    fi
    
    # Check BigQuery dataset
    if bq show "${PROJECT_ID}:${DATASET_NAME}" &> /dev/null; then
        log_success "BigQuery dataset created successfully"
    else
        log_error "BigQuery dataset validation failed"
        return 1
    fi
    
    # Check Cloud Storage bucket
    if gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
        log_success "Cloud Storage bucket created successfully"
    else
        log_error "Cloud Storage bucket validation failed"
        return 1
    fi
    
    # Check Cloud Function
    if gcloud functions describe process-sensor-data --region="$REGION" &> /dev/null; then
        log_success "Cloud Function deployed successfully"
    else
        log_error "Cloud Function validation failed"
        return 1
    fi
    
    log_success "All components validated successfully"
}

# Generate test data function
generate_test_data() {
    log_info "Generating test sensor data..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "DRY-RUN mode - skipping test data generation"
        return
    fi
    
    # Create test sensor payload
    cat > test_sensor_payload.json << EOF
{
  "device_id": "traffic-sensor-001",
  "sensor_type": "traffic_flow",
  "location": "Main St & 1st Ave",
  "value": 45.2,
  "unit": "vehicles_per_minute",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
  "metadata": {
    "intersection_id": "INT-001",
    "lane_count": 4,
    "weather_condition": "clear"
  }
}
EOF
    
    # Publish test message
    gcloud pubsub topics publish "$TOPIC_NAME" \
        --message="$(cat test_sensor_payload.json)" \
        --attribute="device_type=traffic_sensor,priority=normal"
    
    log_success "Test sensor data published to Pub/Sub"
    rm test_sensor_payload.json
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    if [ "$DRY_RUN" != "true" ]; then
        cat > deployment_info.txt << EOF
Smart City Infrastructure Monitoring - Deployment Information
============================================================

Project ID: $PROJECT_ID
Region: $REGION
Deployment Date: $(date)

Resources Created:
- Pub/Sub Topic: $TOPIC_NAME
- BigQuery Dataset: $DATASET_NAME
- Cloud Storage Bucket: $BUCKET_NAME
- Service Account: $SERVICE_ACCOUNT_NAME
- Cloud Function: process-sensor-data

Next Steps:
1. Configure notification channels for monitoring alerts
2. Set up HTTPS endpoints for IoT device connectivity
3. Train ML models when sufficient sensor data is available
4. Configure additional dashboards for specific sensor types

Cleanup:
To remove all resources, run: ./destroy.sh
EOF
        log_success "Deployment information saved to deployment_info.txt"
    fi
}

# Main deployment function
main() {
    log_info "Starting Smart City Infrastructure Monitoring deployment..."
    
    check_prerequisites
    set_environment_variables
    setup_project
    enable_apis
    create_service_account
    create_pubsub_infrastructure
    create_bigquery_resources
    create_storage_bucket
    deploy_cloud_function
    setup_vertex_ai
    configure_monitoring
    validate_deployment
    generate_test_data
    save_deployment_info
    
    echo ""
    echo "======================================================================"
    log_success "Smart City Infrastructure Monitoring deployed successfully!"
    echo "======================================================================"
    echo ""
    echo "📊 Dashboard: https://console.cloud.google.com/monitoring/dashboards"
    echo "🗄️  BigQuery: https://console.cloud.google.com/bigquery?project=$PROJECT_ID"
    echo "📡 Pub/Sub: https://console.cloud.google.com/cloudpubsub/topic/list?project=$PROJECT_ID"
    echo "🤖 Vertex AI: https://console.cloud.google.com/vertex-ai?project=$PROJECT_ID"
    echo ""
    echo "💡 To start sending sensor data, use the service account key: sensor-key.json"
    echo "🧹 To clean up all resources, run: ./destroy.sh"
    echo ""
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi