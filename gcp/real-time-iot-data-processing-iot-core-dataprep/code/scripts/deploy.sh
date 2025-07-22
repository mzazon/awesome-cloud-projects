#!/bin/bash

# Real-Time IoT Data Processing Pipeline - Deployment Script
# This script deploys the complete IoT data processing pipeline using:
# - Cloud IoT Core for device management
# - Cloud Pub/Sub for message queuing
# - Cloud Dataprep for data cleansing
# - BigQuery for analytics
# - Cloud Monitoring for observability

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

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    # Stop any running processes
    if [[ -n "${SIMULATOR_PID:-}" ]]; then
        kill "$SIMULATOR_PID" 2>/dev/null || true
    fi
    exit 1
}

trap cleanup_on_error ERR

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_BASE_NAME="iot-pipeline"
REGION="us-central1"
ZONE="us-central1-a"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if python3 is installed
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install it first."
        exit 1
    fi
    
    # Check if pip3 is installed
    if ! command -v pip3 &> /dev/null; then
        log_error "pip3 is not installed. Please install it first."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Installing it for JSON processing..."
        # Try to install jq based on the OS
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get update && sudo apt-get install -y jq
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install jq
        else
            log_error "Please install jq manually for JSON processing."
            exit 1
        fi
    fi
    
    log_success "All prerequisites are met"
}

# Function to set up project environment
setup_project() {
    log_info "Setting up project environment..."
    
    # Generate unique project ID
    export PROJECT_ID="${PROJECT_BASE_NAME}-$(date +%s)"
    export REGION="$REGION"
    export ZONE="$ZONE"
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export IOT_REGISTRY_ID="sensor-registry-${RANDOM_SUFFIX}"
    export DEVICE_ID="temperature-sensor-${RANDOM_SUFFIX}"
    export PUBSUB_TOPIC="iot-telemetry-${RANDOM_SUFFIX}"
    export PUBSUB_SUBSCRIPTION="iot-data-subscription-${RANDOM_SUFFIX}"
    export BIGQUERY_DATASET="iot_analytics_${RANDOM_SUFFIX//-/_}"
    export BIGQUERY_TABLE="sensor_readings"
    export STORAGE_BUCKET="${PROJECT_ID}-dataprep-staging"
    
    # Save configuration to file for later use
    cat > "${SCRIPT_DIR}/deployment_config.env" << EOF
PROJECT_ID=$PROJECT_ID
REGION=$REGION
ZONE=$ZONE
IOT_REGISTRY_ID=$IOT_REGISTRY_ID
DEVICE_ID=$DEVICE_ID
PUBSUB_TOPIC=$PUBSUB_TOPIC
PUBSUB_SUBSCRIPTION=$PUBSUB_SUBSCRIPTION
BIGQUERY_DATASET=$BIGQUERY_DATASET
BIGQUERY_TABLE=$BIGQUERY_TABLE
STORAGE_BUCKET=$STORAGE_BUCKET
EOF
    
    log_success "Project environment configured: $PROJECT_ID"
}

# Function to create and configure Google Cloud project
create_project() {
    log_info "Creating Google Cloud project..."
    
    # Create new project
    if gcloud projects create "$PROJECT_ID" --name="IoT Data Processing Pipeline" --quiet; then
        log_success "Project created successfully"
    else
        log_error "Failed to create project. Please check permissions and try again."
        exit 1
    fi
    
    # Set active project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_info "Please link a billing account to continue..."
    echo "Run: gcloud billing projects link $PROJECT_ID --billing-account=YOUR-BILLING-ACCOUNT-ID"
    echo "Press Enter to continue after linking billing account..."
    read -r
    
    # Enable required APIs
    log_info "Enabling required APIs (this may take a few minutes)..."
    gcloud services enable \
        cloudiot.googleapis.com \
        pubsub.googleapis.com \
        bigquery.googleapis.com \
        dataprep.googleapis.com \
        dataflow.googleapis.com \
        monitoring.googleapis.com \
        storage.googleapis.com
    
    log_success "Google Cloud project configured successfully"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topic and subscription..."
    
    # Create Pub/Sub topic
    gcloud pubsub topics create "$PUBSUB_TOPIC" \
        --message-retention-duration=7d \
        --message-storage-policy-allowed-regions="$REGION"
    
    # Create subscription
    gcloud pubsub subscriptions create "$PUBSUB_SUBSCRIPTION" \
        --topic="$PUBSUB_TOPIC" \
        --ack-deadline=60 \
        --retain-acked-messages \
        --message-retention-duration=7d
    
    log_success "Pub/Sub resources created successfully"
}

# Function to create IoT Core resources
create_iot_core_resources() {
    log_info "Creating IoT Core registry and device..."
    
    # Create IoT Core device registry
    gcloud iot registries create "$IOT_REGISTRY_ID" \
        --region="$REGION" \
        --event-notification-config=topic="$PUBSUB_TOPIC"
    
    # Generate device key pair
    openssl req -x509 -newkey rsa:2048 -keyout "${SCRIPT_DIR}/device-private.pem" \
        -out "${SCRIPT_DIR}/device-cert.pem" -nodes -days 365 \
        -subj "/CN=$DEVICE_ID"
    
    # Create IoT device
    gcloud iot devices create "$DEVICE_ID" \
        --region="$REGION" \
        --registry="$IOT_REGISTRY_ID" \
        --public-key="path=${SCRIPT_DIR}/device-cert.pem,type=rsa-x509-pem"
    
    log_success "IoT Core resources created successfully"
}

# Function to create BigQuery resources
create_bigquery_resources() {
    log_info "Creating BigQuery dataset and table..."
    
    # Create BigQuery dataset
    bq mk --dataset \
        --location="$REGION" \
        --description="IoT sensor data analytics" \
        "${PROJECT_ID}:${BIGQUERY_DATASET}"
    
    # Create table with schema
    bq mk --table \
        "${PROJECT_ID}:${BIGQUERY_DATASET}.${BIGQUERY_TABLE}" \
        device_id:STRING,timestamp:TIMESTAMP,temperature:FLOAT,humidity:FLOAT,pressure:FLOAT,location:STRING,data_quality_score:FLOAT
    
    # Configure table partitioning
    bq update --time_partitioning_field=timestamp \
        --time_partitioning_type=DAY \
        "${PROJECT_ID}:${BIGQUERY_DATASET}.${BIGQUERY_TABLE}"
    
    log_success "BigQuery resources created successfully"
}

# Function to configure Cloud Storage for Dataprep
create_storage_resources() {
    log_info "Creating Cloud Storage bucket for Dataprep..."
    
    # Create storage bucket
    gsutil mb -p "$PROJECT_ID" \
        -c STANDARD \
        -l "$REGION" \
        "gs://${STORAGE_BUCKET}"
    
    # Create sample data file
    cat > "${SCRIPT_DIR}/sample_iot_data.json" << 'EOF'
{"device_id": "sensor-001", "timestamp": "2025-07-12T10:00:00Z", "temperature": 23.5, "humidity": 45.2, "pressure": 1013.25, "location": "warehouse_a", "data_quality_score": 0.95}
{"device_id": "sensor-001", "timestamp": "2025-07-12T10:01:00Z", "temperature": null, "humidity": 47.8, "pressure": 1012.80, "location": "warehouse_a", "data_quality_score": 0.70}
{"device_id": "sensor-001", "timestamp": "2025-07-12T10:02:00Z", "temperature": 85.5, "humidity": 46.1, "pressure": 1013.10, "location": "warehouse_a", "data_quality_score": 0.60}
EOF
    
    # Upload sample data
    gsutil cp "${SCRIPT_DIR}/sample_iot_data.json" "gs://${STORAGE_BUCKET}/"
    
    log_success "Cloud Storage resources created successfully"
}

# Function to configure Dataprep service account
configure_dataprep() {
    log_info "Configuring Dataprep service account..."
    
    # Create service account
    gcloud iam service-accounts create dataprep-pipeline \
        --display-name="Dataprep Pipeline Service Account"
    
    # Grant permissions
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:dataprep-pipeline@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/dataprep.serviceAgent"
    
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:dataprep-pipeline@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/bigquery.dataEditor"
    
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:dataprep-pipeline@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/pubsub.subscriber"
    
    log_success "Dataprep service account configured successfully"
}

# Function to create IoT simulator
create_iot_simulator() {
    log_info "Creating IoT device simulator..."
    
    # Install required Python packages
    pip3 install google-cloud-iot paho-mqtt PyJWT cryptography
    
    # Create IoT simulator script
    cat > "${SCRIPT_DIR}/iot_simulator.py" << EOF
import json
import time
import random
import ssl
import jwt
import datetime
import os
from google.cloud import iot_v1
import paho.mqtt.client as mqtt

# Device configuration
project_id = "${PROJECT_ID}"
registry_id = "${IOT_REGISTRY_ID}"
device_id = "${DEVICE_ID}"
region = "${REGION}"
private_key_file = "${SCRIPT_DIR}/device-private.pem"

def create_jwt_token():
    """Generate JWT token for device authentication"""
    with open(private_key_file, 'r') as f:
        private_key = f.read()
    
    token = {
        'iat': datetime.datetime.utcnow(),
        'exp': datetime.datetime.utcnow() + datetime.timedelta(minutes=60),
        'aud': project_id
    }
    
    return jwt.encode(token, private_key, algorithm='RS256')

def generate_sensor_data():
    """Generate realistic sensor data with quality issues"""
    base_temp = 22.0 + random.gauss(0, 2)
    base_humidity = 45.0 + random.gauss(0, 5)
    base_pressure = 1013.25 + random.gauss(0, 10)
    
    # Introduce data quality issues (10% chance)
    if random.random() < 0.1:
        # Missing values
        temp = None if random.random() < 0.3 else base_temp
        humidity = None if random.random() < 0.3 else base_humidity
        pressure = None if random.random() < 0.3 else base_pressure
    else:
        temp = base_temp
        humidity = base_humidity
        pressure = base_pressure
    
    # Add occasional outliers (2% chance)
    if random.random() < 0.02:
        temp = temp * random.uniform(3, 5) if temp else temp
    
    return {
        'device_id': device_id,
        'timestamp': datetime.datetime.utcnow().isoformat() + 'Z',
        'temperature': temp,
        'humidity': humidity,
        'pressure': pressure,
        'location': random.choice(['warehouse_a', 'warehouse_b', 'office']),
        'data_quality_score': random.uniform(0.7, 1.0)
    }

def publish_telemetry():
    """Publish sensor data to Cloud IoT Core"""
    client = mqtt.Client(client_id=f'projects/{project_id}/locations/{region}/registries/{registry_id}/devices/{device_id}')
    
    # Configure SSL/TLS
    context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    client.tls_set_context(context)
    
    # Set credentials
    client.username_pw_set(username='unused', password=create_jwt_token())
    
    # Connect to Cloud IoT Core MQTT bridge
    client.connect('mqtt.googleapis.com', 8883, 60)
    
    # Publish telemetry data
    for i in range(100):  # Send 100 readings
        data = generate_sensor_data()
        payload = json.dumps(data)
        
        topic = f'/devices/{device_id}/events'
        client.publish(topic, payload, qos=1)
        
        print(f"Published reading {i+1}: {payload}")
        time.sleep(2)  # Send every 2 seconds
    
    client.disconnect()

if __name__ == '__main__':
    publish_telemetry()
EOF
    
    log_success "IoT simulator created successfully"
}

# Function to set up monitoring
setup_monitoring() {
    log_info "Setting up monitoring dashboard..."
    
    # Create monitoring dashboard configuration
    cat > "${SCRIPT_DIR}/iot_dashboard.json" << 'EOF'
{
  "displayName": "IoT Data Pipeline Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Pub/Sub Message Rate",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"pubsub_topic\"",
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
    
    # Create monitoring dashboard
    gcloud monitoring dashboards create --config-from-file="${SCRIPT_DIR}/iot_dashboard.json"
    
    log_success "Monitoring dashboard created successfully"
}

# Function to run deployment validation
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check IoT Core registry
    if gcloud iot registries describe "$IOT_REGISTRY_ID" --region="$REGION" --quiet > /dev/null 2>&1; then
        log_success "IoT Core registry is active"
    else
        log_error "IoT Core registry validation failed"
        return 1
    fi
    
    # Check Pub/Sub resources
    if gcloud pubsub topics describe "$PUBSUB_TOPIC" --quiet > /dev/null 2>&1; then
        log_success "Pub/Sub topic is active"
    else
        log_error "Pub/Sub topic validation failed"
        return 1
    fi
    
    # Check BigQuery dataset
    if bq show "${PROJECT_ID}:${BIGQUERY_DATASET}" > /dev/null 2>&1; then
        log_success "BigQuery dataset is active"
    else
        log_error "BigQuery dataset validation failed"
        return 1
    fi
    
    # Check Cloud Storage bucket
    if gsutil ls "gs://${STORAGE_BUCKET}" > /dev/null 2>&1; then
        log_success "Cloud Storage bucket is active"
    else
        log_error "Cloud Storage bucket validation failed"
        return 1
    fi
    
    log_success "Deployment validation completed successfully"
}

# Function to display next steps
display_next_steps() {
    log_info "Deployment completed successfully!"
    echo ""
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo ""
    echo "Next steps:"
    echo "1. Configure Cloud Dataprep flow:"
    echo "   - Go to https://console.cloud.google.com/dataprep"
    echo "   - Create new flow and import sample_iot_data.json"
    echo "   - Configure output to BigQuery: ${BIGQUERY_DATASET}.${BIGQUERY_TABLE}"
    echo ""
    echo "2. Start IoT data simulation:"
    echo "   cd ${SCRIPT_DIR}"
    echo "   python3 iot_simulator.py"
    echo ""
    echo "3. Monitor data flow:"
    echo "   gcloud pubsub subscriptions pull ${PUBSUB_SUBSCRIPTION} --limit=5"
    echo ""
    echo "4. View monitoring dashboard:"
    echo "   https://console.cloud.google.com/monitoring/dashboards"
    echo ""
    echo "Configuration saved to: ${SCRIPT_DIR}/deployment_config.env"
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log_info "Starting IoT Data Processing Pipeline deployment..."
    
    check_prerequisites
    setup_project
    create_project
    create_pubsub_resources
    create_iot_core_resources
    create_bigquery_resources
    create_storage_resources
    configure_dataprep
    create_iot_simulator
    setup_monitoring
    validate_deployment
    display_next_steps
    
    log_success "Deployment completed successfully!"
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi