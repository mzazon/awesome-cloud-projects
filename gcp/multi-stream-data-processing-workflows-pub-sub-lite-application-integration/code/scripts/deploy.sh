#!/bin/bash

# Multi-Stream Data Processing Workflows with Pub/Sub Lite and Application Integration
# Deployment Script for GCP
# This script deploys the complete infrastructure for cost-optimized data streaming

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
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "gcloud is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
}

# Function to check if required APIs are enabled
check_api_enabled() {
    local api=$1
    if ! gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
        return 1
    fi
    return 0
}

# Function to wait for operation to complete
wait_for_operation() {
    local operation_name=$1
    local max_wait=${2:-300}
    local counter=0
    
    while [ $counter -lt $max_wait ]; do
        if gcloud operations describe "$operation_name" --format="value(done)" 2>/dev/null | grep -q "True"; then
            return 0
        fi
        sleep 10
        counter=$((counter + 10))
        info "Waiting for operation $operation_name to complete... (${counter}s)"
    done
    
    error "Operation $operation_name did not complete within ${max_wait} seconds"
    return 1
}

# Function to validate BigQuery dataset exists
validate_bigquery_dataset() {
    local dataset=$1
    if ! bq ls -d "$dataset" >/dev/null 2>&1; then
        error "BigQuery dataset $dataset does not exist"
        return 1
    fi
    return 0
}

# Function to validate Cloud Storage bucket exists
validate_storage_bucket() {
    local bucket=$1
    if ! gsutil ls "gs://$bucket" >/dev/null 2>&1; then
        error "Cloud Storage bucket gs://$bucket does not exist"
        return 1
    fi
    return 0
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if required commands exist
    local required_commands=("gcloud" "bq" "gsutil" "python3" "pip3" "openssl")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            error "Required command '$cmd' not found. Please install it first."
            exit 1
        fi
    done
    
    # Check gcloud authentication
    check_gcloud_auth
    
    # Check if project is set
    if [ -z "${PROJECT_ID:-}" ]; then
        error "PROJECT_ID environment variable is not set"
        exit 1
    fi
    
    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        error "Project $PROJECT_ID does not exist or is not accessible"
        exit 1
    fi
    
    # Check billing is enabled
    if ! gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" 2>/dev/null | grep -q "True"; then
        warn "Billing may not be enabled for project $PROJECT_ID. Some services may not work."
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to enable required APIs
enable_apis() {
    info "Enabling required Google Cloud APIs..."
    
    local required_apis=(
        "pubsublite.googleapis.com"
        "integrations.googleapis.com"
        "dataflow.googleapis.com"
        "bigquery.googleapis.com"
        "storage.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "iam.googleapis.com"
    )
    
    local apis_to_enable=()
    for api in "${required_apis[@]}"; do
        if ! check_api_enabled "$api"; then
            apis_to_enable+=("$api")
        fi
    done
    
    if [ ${#apis_to_enable[@]} -gt 0 ]; then
        info "Enabling APIs: ${apis_to_enable[*]}"
        gcloud services enable "${apis_to_enable[@]}"
        
        # Wait for APIs to be fully enabled
        sleep 30
        
        # Verify APIs are enabled
        for api in "${apis_to_enable[@]}"; do
            if ! check_api_enabled "$api"; then
                error "Failed to enable API: $api"
                exit 1
            fi
        done
    fi
    
    log "All required APIs are enabled"
}

# Function to set up environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # Set default values if not provided
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    # Set resource names
    export LITE_TOPIC_1="iot-data-stream-${RANDOM_SUFFIX}"
    export LITE_TOPIC_2="app-events-stream-${RANDOM_SUFFIX}"
    export LITE_TOPIC_3="system-logs-stream-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_PREFIX="analytics-sub-${RANDOM_SUFFIX}"
    export DATASET_NAME="streaming_analytics_${RANDOM_SUFFIX}"
    export BUCKET_NAME="data-lake-${PROJECT_ID}-${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT_NAME="app-integration-sa-${RANDOM_SUFFIX}"
    
    # Set gcloud defaults
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    # Save environment variables to file for later use
    cat > .env << EOF
PROJECT_ID=$PROJECT_ID
REGION=$REGION
ZONE=$ZONE
RANDOM_SUFFIX=$RANDOM_SUFFIX
LITE_TOPIC_1=$LITE_TOPIC_1
LITE_TOPIC_2=$LITE_TOPIC_2
LITE_TOPIC_3=$LITE_TOPIC_3
SUBSCRIPTION_PREFIX=$SUBSCRIPTION_PREFIX
DATASET_NAME=$DATASET_NAME
BUCKET_NAME=$BUCKET_NAME
SERVICE_ACCOUNT_NAME=$SERVICE_ACCOUNT_NAME
EOF
    
    info "Environment variables configured:"
    info "  PROJECT_ID: $PROJECT_ID"
    info "  REGION: $REGION"
    info "  RANDOM_SUFFIX: $RANDOM_SUFFIX"
    info "  DATASET_NAME: $DATASET_NAME"
    info "  BUCKET_NAME: $BUCKET_NAME"
    
    log "Environment setup completed"
}

# Function to create foundational resources
create_foundational_resources() {
    info "Creating foundational resources..."
    
    # Create BigQuery dataset
    info "Creating BigQuery dataset: $DATASET_NAME"
    if ! bq mk --dataset --location="$REGION" "${PROJECT_ID}:${DATASET_NAME}"; then
        if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" >/dev/null 2>&1; then
            warn "BigQuery dataset $DATASET_NAME already exists, skipping creation"
        else
            error "Failed to create BigQuery dataset $DATASET_NAME"
            exit 1
        fi
    fi
    
    # Create Cloud Storage bucket
    info "Creating Cloud Storage bucket: $BUCKET_NAME"
    if ! gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
        if gsutil ls "gs://$BUCKET_NAME" >/dev/null 2>&1; then
            warn "Cloud Storage bucket $BUCKET_NAME already exists, skipping creation"
        else
            error "Failed to create Cloud Storage bucket $BUCKET_NAME"
            exit 1
        fi
    fi
    
    # Create required subdirectories in bucket
    info "Creating bucket subdirectories..."
    gsutil mkdir -p "gs://$BUCKET_NAME/dataflow-temp" || true
    gsutil mkdir -p "gs://$BUCKET_NAME/dataflow-staging" || true
    gsutil mkdir -p "gs://$BUCKET_NAME/templates" || true
    
    log "Foundational resources created successfully"
}

# Function to create Pub/Sub Lite topics
create_pubsub_lite_topics() {
    info "Creating Pub/Sub Lite topics..."
    
    # Topic 1: IoT data stream
    info "Creating Pub/Sub Lite topic: $LITE_TOPIC_1"
    if ! gcloud pubsub lite-topics create "$LITE_TOPIC_1" \
        --location="$REGION" \
        --partitions=4 \
        --publish-throughput-capacity=4 \
        --subscribe-throughput-capacity=8 \
        --per-partition-bytes=30GiB \
        --message-retention-duration=7d; then
        
        if gcloud pubsub lite-topics describe "$LITE_TOPIC_1" --location="$REGION" >/dev/null 2>&1; then
            warn "Pub/Sub Lite topic $LITE_TOPIC_1 already exists, skipping creation"
        else
            error "Failed to create Pub/Sub Lite topic $LITE_TOPIC_1"
            exit 1
        fi
    fi
    
    # Topic 2: Application events
    info "Creating Pub/Sub Lite topic: $LITE_TOPIC_2"
    if ! gcloud pubsub lite-topics create "$LITE_TOPIC_2" \
        --location="$REGION" \
        --partitions=2 \
        --publish-throughput-capacity=2 \
        --subscribe-throughput-capacity=4 \
        --per-partition-bytes=50GiB \
        --message-retention-duration=14d; then
        
        if gcloud pubsub lite-topics describe "$LITE_TOPIC_2" --location="$REGION" >/dev/null 2>&1; then
            warn "Pub/Sub Lite topic $LITE_TOPIC_2 already exists, skipping creation"
        else
            error "Failed to create Pub/Sub Lite topic $LITE_TOPIC_2"
            exit 1
        fi
    fi
    
    # Topic 3: System logs
    info "Creating Pub/Sub Lite topic: $LITE_TOPIC_3"
    if ! gcloud pubsub lite-topics create "$LITE_TOPIC_3" \
        --location="$REGION" \
        --partitions=3 \
        --publish-throughput-capacity=3 \
        --subscribe-throughput-capacity=6 \
        --per-partition-bytes=40GiB \
        --message-retention-duration=30d; then
        
        if gcloud pubsub lite-topics describe "$LITE_TOPIC_3" --location="$REGION" >/dev/null 2>&1; then
            warn "Pub/Sub Lite topic $LITE_TOPIC_3 already exists, skipping creation"
        else
            error "Failed to create Pub/Sub Lite topic $LITE_TOPIC_3"
            exit 1
        fi
    fi
    
    log "Pub/Sub Lite topics created successfully"
}

# Function to create Pub/Sub Lite subscriptions
create_pubsub_lite_subscriptions() {
    info "Creating Pub/Sub Lite subscriptions..."
    
    # Analytics subscriptions
    local subscriptions=(
        "${SUBSCRIPTION_PREFIX}-analytics-1:${LITE_TOPIC_1}:deliver-immediately"
        "${SUBSCRIPTION_PREFIX}-analytics-2:${LITE_TOPIC_2}:deliver-immediately"
        "${SUBSCRIPTION_PREFIX}-analytics-3:${LITE_TOPIC_3}:deliver-immediately"
        "${SUBSCRIPTION_PREFIX}-workflow-1:${LITE_TOPIC_1}:deliver-after-stored"
        "${SUBSCRIPTION_PREFIX}-workflow-2:${LITE_TOPIC_2}:deliver-after-stored"
    )
    
    for sub_info in "${subscriptions[@]}"; do
        IFS=':' read -r sub_name topic_name delivery_req <<< "$sub_info"
        
        info "Creating subscription: $sub_name"
        if ! gcloud pubsub lite-subscriptions create "$sub_name" \
            --location="$REGION" \
            --topic="$topic_name" \
            --delivery-requirement="$delivery_req"; then
            
            if gcloud pubsub lite-subscriptions describe "$sub_name" --location="$REGION" >/dev/null 2>&1; then
                warn "Subscription $sub_name already exists, skipping creation"
            else
                error "Failed to create subscription $sub_name"
                exit 1
            fi
        fi
    done
    
    log "Pub/Sub Lite subscriptions created successfully"
}

# Function to create BigQuery tables
create_bigquery_tables() {
    info "Creating BigQuery tables..."
    
    # IoT sensor data table
    info "Creating table: iot_sensor_data"
    if ! bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.iot_sensor_data" \
        timestamp:TIMESTAMP,device_id:STRING,sensor_type:STRING,value:FLOAT64,location:GEOGRAPHY,metadata:JSON; then
        
        if bq ls "${PROJECT_ID}:${DATASET_NAME}" | grep -q "iot_sensor_data"; then
            warn "Table iot_sensor_data already exists, skipping creation"
        else
            error "Failed to create table iot_sensor_data"
            exit 1
        fi
    fi
    
    # Configure partitioning and clustering for IoT table
    info "Configuring partitioning and clustering for iot_sensor_data..."
    bq query --use_legacy_sql=false \
    "ALTER TABLE \`${PROJECT_ID}.${DATASET_NAME}.iot_sensor_data\`
    SET OPTIONS (
      partition_expiration_days = 365,
      clustering_fields = ['device_id', 'sensor_type']
    )" || warn "Failed to configure partitioning for iot_sensor_data"
    
    # Application events table
    info "Creating table: application_events"
    if ! bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.application_events" \
        event_timestamp:TIMESTAMP,user_id:STRING,event_type:STRING,session_id:STRING,properties:JSON,revenue:FLOAT64; then
        
        if bq ls "${PROJECT_ID}:${DATASET_NAME}" | grep -q "application_events"; then
            warn "Table application_events already exists, skipping creation"
        else
            error "Failed to create table application_events"
            exit 1
        fi
    fi
    
    # Configure partitioning and clustering for application events table
    info "Configuring partitioning and clustering for application_events..."
    bq query --use_legacy_sql=false \
    "ALTER TABLE \`${PROJECT_ID}.${DATASET_NAME}.application_events\`
    SET OPTIONS (
      partition_expiration_days = 730,
      clustering_fields = ['user_id', 'event_type']
    )" || warn "Failed to configure partitioning for application_events"
    
    # System logs summary table
    info "Creating table: system_logs_summary"
    if ! bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.system_logs_summary" \
        log_timestamp:TIMESTAMP,service_name:STRING,log_level:STRING,error_count:INT64,response_time_ms:FLOAT64,request_count:INT64; then
        
        if bq ls "${PROJECT_ID}:${DATASET_NAME}" | grep -q "system_logs_summary"; then
            warn "Table system_logs_summary already exists, skipping creation"
        else
            error "Failed to create table system_logs_summary"
            exit 1
        fi
    fi
    
    log "BigQuery tables created successfully"
}

# Function to create service account and configure IAM
create_service_account() {
    info "Creating service account for Application Integration..."
    
    # Create service account
    if ! gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
        --display-name="Application Integration Service Account" \
        --description="Service account for data processing workflows"; then
        
        if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" >/dev/null 2>&1; then
            warn "Service account $SERVICE_ACCOUNT_NAME already exists, skipping creation"
        else
            error "Failed to create service account $SERVICE_ACCOUNT_NAME"
            exit 1
        fi
    fi
    
    # Grant necessary IAM permissions
    info "Granting IAM permissions to service account..."
    local roles=(
        "roles/pubsublite.editor"
        "roles/bigquery.dataEditor"
        "roles/storage.objectAdmin"
        "roles/dataflow.developer"
        "roles/monitoring.metricWriter"
        "roles/logging.logWriter"
    )
    
    for role in "${roles[@]}"; do
        info "Granting role: $role"
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="$role" || warn "Failed to grant role $role"
    done
    
    log "Service account created and configured successfully"
}

# Function to configure Application Integration
configure_application_integration() {
    info "Configuring Application Integration..."
    
    # Enable Application Integration in the region
    info "Provisioning Application Integration in region: $REGION"
    if ! gcloud alpha integration regions provision \
        --location="$REGION" \
        --kms-config-project-id="$PROJECT_ID"; then
        
        warn "Application Integration may already be provisioned or command failed"
    fi
    
    # Wait for provisioning to complete
    sleep 60
    
    log "Application Integration configured successfully"
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    info "Creating monitoring dashboard..."
    
    # Create dashboard configuration
    cat > monitoring-dashboard.json << EOF
{
  "displayName": "Multi-Stream Data Processing Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Pub/Sub Lite Message Rate",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\\"pubsub_lite_topic\\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                }
              }
            ]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "BigQuery Insert Rates",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\\"bigquery_table\\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
EOF
    
    # Create the dashboard
    if ! gcloud monitoring dashboards create --config-from-file=monitoring-dashboard.json; then
        warn "Failed to create monitoring dashboard"
    else
        log "Monitoring dashboard created successfully"
    fi
    
    # Clean up temporary file
    rm -f monitoring-dashboard.json
}

# Function to create alerting policies
create_alerting_policies() {
    info "Creating alerting policies..."
    
    # Create alerting policy for high message backlog
    cat > alerting-policy.json << EOF
{
  "displayName": "High Pub/Sub Lite Message Backlog",
  "conditions": [
    {
      "displayName": "Message backlog too high",
      "conditionThreshold": {
        "filter": "resource.type=\\"pubsub_lite_subscription\\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 10000,
        "duration": "300s"
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "604800s"
  },
  "enabled": true
}
EOF
    
    # Create the alerting policy
    if ! gcloud alpha monitoring policies create --policy-from-file=alerting-policy.json; then
        warn "Failed to create alerting policy"
    else
        log "Alerting policy created successfully"
    fi
    
    # Clean up temporary file
    rm -f alerting-policy.json
}

# Function to create test data generator
create_test_data_generator() {
    info "Creating test data generator..."
    
    cat > generate-test-data.py << 'EOF'
import json
import time
import random
from google.cloud import pubsublite
from concurrent.futures import ThreadPoolExecutor
import os

def publish_iot_data(project_id, region, topic_name, num_messages=100):
    """Publish test IoT data to Pub/Sub Lite topic"""
    topic_path = pubsublite.TopicPath(project_id, region, topic_name)
    
    # Create publisher client
    publisher = pubsublite.PublisherClient()
    
    print(f"Publishing {num_messages} messages to {topic_name}...")
    
    for i in range(num_messages):
        data = {
            "timestamp": int(time.time() * 1000),
            "device_id": f"device_{random.randint(1, 100)}",
            "sensor_type": random.choice(["temperature", "humidity", "pressure"]),
            "value": round(random.uniform(10.0, 50.0), 2),
            "location": "POINT(-122.4194 37.7749)",
            "metadata": {
                "firmware_version": "1.2.3",
                "battery_level": random.randint(20, 100)
            }
        }
        
        message = pubsublite.PubsubMessage(data=json.dumps(data).encode())
        future = publisher.publish(topic_path, message)
        
        # Wait for publish to complete
        try:
            future.result()
            if i % 10 == 0:
                print(f"Published {i+1}/{num_messages} messages")
        except Exception as e:
            print(f"Error publishing message {i}: {e}")
        
        time.sleep(0.1)
    
    print(f"Finished publishing {num_messages} messages")

def publish_app_events(project_id, region, topic_name, num_messages=50):
    """Publish test application events to Pub/Sub Lite topic"""
    topic_path = pubsublite.TopicPath(project_id, region, topic_name)
    
    # Create publisher client
    publisher = pubsublite.PublisherClient()
    
    print(f"Publishing {num_messages} application events to {topic_name}...")
    
    for i in range(num_messages):
        data = {
            "event_timestamp": int(time.time() * 1000),
            "user_id": f"user_{random.randint(1, 1000)}",
            "event_type": random.choice(["page_view", "click", "purchase", "signup"]),
            "session_id": f"session_{random.randint(1, 10000)}",
            "properties": {
                "page_url": f"/page_{random.randint(1, 50)}",
                "user_agent": "Mozilla/5.0 (Test Browser)"
            },
            "revenue": round(random.uniform(0, 100), 2) if random.random() < 0.1 else 0
        }
        
        message = pubsublite.PubsubMessage(data=json.dumps(data).encode())
        future = publisher.publish(topic_path, message)
        
        # Wait for publish to complete
        try:
            future.result()
            if i % 10 == 0:
                print(f"Published {i+1}/{num_messages} application events")
        except Exception as e:
            print(f"Error publishing application event {i}: {e}")
        
        time.sleep(0.2)
    
    print(f"Finished publishing {num_messages} application events")

if __name__ == "__main__":
    # Get environment variables
    project_id = os.getenv("PROJECT_ID")
    region = os.getenv("REGION")
    topic_1 = os.getenv("LITE_TOPIC_1")
    topic_2 = os.getenv("LITE_TOPIC_2")
    
    if not all([project_id, region, topic_1, topic_2]):
        print("Error: Missing required environment variables")
        print("Required: PROJECT_ID, REGION, LITE_TOPIC_1, LITE_TOPIC_2")
        exit(1)
    
    print(f"Starting test data generation for project: {project_id}")
    print(f"Region: {region}")
    print(f"Topics: {topic_1}, {topic_2}")
    
    try:
        # Publish IoT data
        publish_iot_data(project_id, region, topic_1, 100)
        
        # Publish application events
        publish_app_events(project_id, region, topic_2, 50)
        
        print("Test data generation completed successfully!")
        
    except Exception as e:
        print(f"Error during test data generation: {e}")
        exit(1)
EOF
    
    log "Test data generator created successfully"
}

# Function to install Python dependencies
install_python_dependencies() {
    info "Installing Python dependencies..."
    
    # Check if pip3 is available
    if ! command_exists pip3; then
        error "pip3 is not available. Please install Python 3 and pip3"
        exit 1
    fi
    
    # Install required packages
    pip3 install --user google-cloud-pubsublite google-cloud-bigquery google-cloud-storage
    
    log "Python dependencies installed successfully"
}

# Function to run deployment validation
run_deployment_validation() {
    info "Running deployment validation..."
    
    # Validate Pub/Sub Lite topics
    info "Validating Pub/Sub Lite topics..."
    for topic in "$LITE_TOPIC_1" "$LITE_TOPIC_2" "$LITE_TOPIC_3"; do
        if ! gcloud pubsub lite-topics describe "$topic" --location="$REGION" >/dev/null 2>&1; then
            error "Pub/Sub Lite topic $topic not found"
            exit 1
        fi
    done
    
    # Validate subscriptions
    info "Validating Pub/Sub Lite subscriptions..."
    local subscriptions=(
        "${SUBSCRIPTION_PREFIX}-analytics-1"
        "${SUBSCRIPTION_PREFIX}-analytics-2"
        "${SUBSCRIPTION_PREFIX}-analytics-3"
        "${SUBSCRIPTION_PREFIX}-workflow-1"
        "${SUBSCRIPTION_PREFIX}-workflow-2"
    )
    
    for sub in "${subscriptions[@]}"; do
        if ! gcloud pubsub lite-subscriptions describe "$sub" --location="$REGION" >/dev/null 2>&1; then
            error "Subscription $sub not found"
            exit 1
        fi
    done
    
    # Validate BigQuery dataset and tables
    info "Validating BigQuery resources..."
    if ! validate_bigquery_dataset "${PROJECT_ID}:${DATASET_NAME}"; then
        exit 1
    fi
    
    local tables=("iot_sensor_data" "application_events" "system_logs_summary")
    for table in "${tables[@]}"; do
        if ! bq ls "${PROJECT_ID}:${DATASET_NAME}" | grep -q "$table"; then
            error "BigQuery table $table not found"
            exit 1
        fi
    done
    
    # Validate Cloud Storage bucket
    info "Validating Cloud Storage bucket..."
    if ! validate_storage_bucket "$BUCKET_NAME"; then
        exit 1
    fi
    
    # Validate service account
    info "Validating service account..."
    if ! gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" >/dev/null 2>&1; then
        error "Service account $SERVICE_ACCOUNT_NAME not found"
        exit 1
    fi
    
    log "All deployment validation checks passed"
}

# Function to display deployment summary
display_deployment_summary() {
    info "Deployment Summary:"
    echo "===========================================" 
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Pub/Sub Lite Topics:"
    echo "  - $LITE_TOPIC_1 (4 partitions, IoT data)"
    echo "  - $LITE_TOPIC_2 (2 partitions, App events)"
    echo "  - $LITE_TOPIC_3 (3 partitions, System logs)"
    echo ""
    echo "BigQuery Dataset: $DATASET_NAME"
    echo "  - Tables: iot_sensor_data, application_events, system_logs_summary"
    echo ""
    echo "Cloud Storage Bucket: $BUCKET_NAME"
    echo "Service Account: $SERVICE_ACCOUNT_NAME"
    echo ""
    echo "To test the pipeline, run:"
    echo "  source .env && python3 generate-test-data.py"
    echo ""
    echo "To clean up resources, run:"
    echo "  ./destroy.sh"
    echo "==========================================="
}

# Main deployment function
main() {
    log "Starting Multi-Stream Data Processing Workflows deployment..."
    
    # Check if PROJECT_ID is provided
    if [ -z "${PROJECT_ID:-}" ]; then
        error "PROJECT_ID environment variable must be set"
        echo "Usage: PROJECT_ID=your-project-id ./deploy.sh"
        exit 1
    fi
    
    # Run deployment steps
    check_prerequisites
    enable_apis
    setup_environment
    create_foundational_resources
    create_pubsub_lite_topics
    create_pubsub_lite_subscriptions
    create_bigquery_tables
    create_service_account
    configure_application_integration
    create_monitoring_dashboard
    create_alerting_policies
    install_python_dependencies
    create_test_data_generator
    run_deployment_validation
    
    log "Deployment completed successfully!"
    display_deployment_summary
}

# Handle script termination
trap 'error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"