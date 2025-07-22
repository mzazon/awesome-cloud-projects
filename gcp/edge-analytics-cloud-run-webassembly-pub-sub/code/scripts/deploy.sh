#!/bin/bash

# Edge Analytics with Cloud Run WebAssembly and Pub/Sub - Deployment Script
# This script deploys the complete edge analytics platform on Google Cloud Platform

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if required tools are installed
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Please install curl."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Please install openssl."
        exit 1
    fi
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        warning "Docker is not installed. Some features may not work locally."
    fi
    
    # Check if cargo is installed for WebAssembly compilation
    if ! command -v cargo &> /dev/null; then
        warning "Rust/Cargo is not installed. WebAssembly module compilation may fail."
    fi
    
    # Check if pip3 is installed
    if ! command -v pip3 &> /dev/null; then
        warning "pip3 is not installed. IoT simulator may not work."
    fi
    
    success "Prerequisites check completed"
}

# Function to check gcloud authentication and project setup
check_gcloud_auth() {
    log "Checking gcloud authentication and project setup..."
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    if ! gcloud config get-value project &> /dev/null; then
        error "No default project set. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    success "gcloud authentication and project setup verified"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="edge-analytics-$(date +%s)"
        warning "PROJECT_ID not set, using generated ID: ${PROJECT_ID}"
    fi
    
    # Set default region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export TOPIC_NAME="iot-sensor-data-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_NAME="analytics-subscription-${RANDOM_SUFFIX}"
    export SERVICE_NAME="edge-analytics-${RANDOM_SUFFIX}"
    export BUCKET_NAME="edge-analytics-data-${RANDOM_SUFFIX}"
    
    # Set gcloud configuration
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    # Get project number for later use
    export PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
    
    success "Environment variables configured"
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Zone: ${ZONE}"
    log "Topic Name: ${TOPIC_NAME}"
    log "Service Name: ${SERVICE_NAME}"
    log "Bucket Name: ${BUCKET_NAME}"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "run.googleapis.com"
        "pubsub.googleapis.com"
        "storage.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "firestore.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            success "Enabled ${api}"
        else
            error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket for analytics data lake..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        warning "Bucket gs://${BUCKET_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create storage bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        success "Created storage bucket: gs://${BUCKET_NAME}"
    else
        error "Failed to create storage bucket"
        exit 1
    fi
    
    # Enable versioning for data protection
    gsutil versioning set on "gs://${BUCKET_NAME}"
    success "Enabled versioning on bucket"
    
    # Set lifecycle policy to optimize costs
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
      }
    ]
  }
}
EOF
    
    gsutil lifecycle set lifecycle.json "gs://${BUCKET_NAME}"
    rm lifecycle.json
    success "Applied lifecycle policy to bucket"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log "Creating Pub/Sub topic and subscription..."
    
    # Create Pub/Sub topic
    if gcloud pubsub topics create "${TOPIC_NAME}" --message-retention-duration=7d --quiet; then
        success "Created Pub/Sub topic: ${TOPIC_NAME}"
    else
        warning "Topic ${TOPIC_NAME} might already exist"
    fi
    
    # Note: Subscription will be created after Cloud Run service is deployed
    # to use the correct service URL
    
    success "Pub/Sub topic created"
}

# Function to build WebAssembly analytics module
build_wasm_module() {
    log "Building WebAssembly analytics module..."
    
    # Create Rust project directory
    mkdir -p wasm-analytics
    cd wasm-analytics
    
    # Initialize Rust project if not exists
    if [[ ! -f Cargo.toml ]]; then
        cargo init --name analytics_engine --lib
    fi
    
    # Configure Cargo.toml for WebAssembly compilation
    cat > Cargo.toml << 'EOF'
[package]
name = "analytics_engine"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
wasm-bindgen = "0.2"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
js-sys = "0.3"

[dependencies.web-sys]
version = "0.3"
features = [
  "console",
]
EOF
    
    # Create analytics module with anomaly detection
    cat > src/lib.rs << 'EOF'
use wasm_bindgen::prelude::*;
use serde::{Deserialize, Serialize};

#[derive(Deserialize, Serialize)]
pub struct SensorData {
    sensor_id: String,
    temperature: f64,
    pressure: f64,
    vibration: f64,
    timestamp: u64,
}

#[derive(Serialize)]
pub struct AnalyticsResult {
    sensor_id: String,
    anomaly_score: f64,
    is_anomaly: bool,
    recommendations: Vec<String>,
    timestamp: u64,
}

#[wasm_bindgen]
pub fn process_sensor_data(data_json: &str) -> String {
    let sensor_data: SensorData = serde_json::from_str(data_json).unwrap();
    
    // Perform anomaly detection using statistical analysis
    let anomaly_score = calculate_anomaly_score(&sensor_data);
    let is_anomaly = anomaly_score > 0.7;
    
    let mut recommendations = Vec::new();
    if is_anomaly {
        recommendations.push("Schedule immediate maintenance check".to_string());
        if sensor_data.temperature > 80.0 {
            recommendations.push("Check cooling system".to_string());
        }
        if sensor_data.vibration > 5.0 {
            recommendations.push("Inspect bearing alignment".to_string());
        }
    }
    
    let result = AnalyticsResult {
        sensor_id: sensor_data.sensor_id,
        anomaly_score,
        is_anomaly,
        recommendations,
        timestamp: sensor_data.timestamp,
    };
    
    serde_json::to_string(&result).unwrap()
}

fn calculate_anomaly_score(data: &SensorData) -> f64 {
    // Simple anomaly detection using threshold-based scoring
    let temp_score = if data.temperature > 75.0 { 0.3 } else { 0.0 };
    let pressure_score = if data.pressure > 2.5 { 0.2 } else { 0.0 };
    let vibration_score = if data.vibration > 4.0 { 0.5 } else { 0.0 };
    
    (temp_score + pressure_score + vibration_score).min(1.0)
}
EOF
    
    # Install wasm-pack if not already installed
    if ! command -v wasm-pack &> /dev/null; then
        log "Installing wasm-pack..."
        curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh
        export PATH="$HOME/.cargo/bin:$PATH"
    fi
    
    # Build WebAssembly module
    if wasm-pack build --target nodejs --scope analytics; then
        success "WebAssembly module compiled successfully"
    else
        error "Failed to compile WebAssembly module"
        exit 1
    fi
    
    cd ..
}

# Function to create Cloud Run service
create_cloud_run_service() {
    log "Creating Cloud Run service with WebAssembly runtime..."
    
    # Create Cloud Run service directory
    mkdir -p cloud-run-service
    cd cloud-run-service
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "edge-analytics-service",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.0",
    "@google-cloud/storage": "^7.0.0",
    "@google-cloud/firestore": "^7.0.0",
    "@google-cloud/monitoring": "^4.0.0"
  }
}
EOF
    
    # Create Express server with WebAssembly integration
    cat > server.js << 'EOF'
const express = require('express');
const { Storage } = require('@google-cloud/storage');
const { Firestore } = require('@google-cloud/firestore');
const { MetricServiceClient } = require('@google-cloud/monitoring');

// Load WebAssembly module
const wasm = require('./pkg/analytics_engine');

const app = express();
const port = process.env.PORT || 8080;

// Initialize Google Cloud clients
const storage = new Storage();
const firestore = new Firestore();
const monitoring = new MetricServiceClient();

const bucketName = process.env.BUCKET_NAME;

app.use(express.json());

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.post('/process', async (req, res) => {
  try {
    const pubsubMessage = req.body;
    const sensorData = JSON.parse(
      Buffer.from(pubsubMessage.message.data, 'base64').toString()
    );
    
    // Process data using WebAssembly module
    const result = wasm.process_sensor_data(JSON.stringify(sensorData));
    const analyticsResult = JSON.parse(result);
    
    // Store results in Cloud Storage
    const fileName = `analytics/${analyticsResult.sensor_id}/${Date.now()}.json`;
    await storage.bucket(bucketName).file(fileName).save(result);
    
    // Store metadata in Firestore
    await firestore.collection('sensor_analytics').add({
      ...analyticsResult,
      processed_at: new Date(),
      storage_path: fileName
    });
    
    // Send custom metrics to Cloud Monitoring
    if (analyticsResult.is_anomaly) {
      await sendCustomMetric('anomaly_detected', 1, analyticsResult.sensor_id);
    }
    
    await sendCustomMetric('data_processed', 1, analyticsResult.sensor_id);
    
    console.log(`Processed data for sensor ${analyticsResult.sensor_id}`);
    res.status(200).send('OK');
    
  } catch (error) {
    console.error('Error processing data:', error);
    res.status(500).send('Error processing data');
  }
});

async function sendCustomMetric(metricType, value, sensorId) {
  const projectId = process.env.GOOGLE_CLOUD_PROJECT;
  const request = {
    name: monitoring.projectPath(projectId),
    timeSeries: [{
      metric: {
        type: `custom.googleapis.com/iot/${metricType}`,
        labels: { sensor_id: sensorId }
      },
      resource: {
        type: 'generic_node',
        labels: {
          project_id: projectId,
          location: 'us-central1',
          namespace: 'edge-analytics',
          node_id: sensorId
        }
      },
      points: [{
        interval: { endTime: { seconds: Math.floor(Date.now() / 1000) } },
        value: { doubleValue: value }
      }]
    }]
  };
  
  try {
    await monitoring.createTimeSeries(request);
  } catch (error) {
    console.error('Error sending metric:', error);
  }
}

app.listen(port, () => {
  console.log(`Edge analytics service listening on port ${port}`);
});
EOF
    
    # Copy WebAssembly module to service directory
    cp -r ../wasm-analytics/pkg .
    
    # Create Dockerfile for Cloud Run
    cat > Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy WebAssembly module and application code
COPY pkg/ ./pkg/
COPY server.js ./

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Start the service
CMD ["node", "server.js"]
EOF
    
    # Build container image using Cloud Build
    log "Building container image..."
    if gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" .; then
        success "Container image built successfully"
    else
        error "Failed to build container image"
        exit 1
    fi
    
    # Deploy to Cloud Run
    log "Deploying to Cloud Run..."
    if gcloud run deploy "${SERVICE_NAME}" \
        --image "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --memory 1Gi \
        --cpu 2 \
        --concurrency 80 \
        --max-instances 100 \
        --set-env-vars="BUCKET_NAME=${BUCKET_NAME}" \
        --set-env-vars="GOOGLE_CLOUD_PROJECT=${PROJECT_ID}" \
        --quiet; then
        success "Cloud Run service deployed successfully"
    else
        error "Failed to deploy Cloud Run service"
        exit 1
    fi
    
    # Get the service URL
    export SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
        --platform managed \
        --region "${REGION}" \
        --format 'value(status.url)')
    
    success "Cloud Run service deployed at: ${SERVICE_URL}"
    
    cd ..
}

# Function to configure Pub/Sub subscription
configure_pubsub_subscription() {
    log "Configuring Pub/Sub subscription with Cloud Run endpoint..."
    
    # Create push subscription
    if gcloud pubsub subscriptions create "${SUBSCRIPTION_NAME}" \
        --topic="${TOPIC_NAME}" \
        --push-endpoint="${SERVICE_URL}/process" \
        --ack-deadline=60 \
        --message-retention-duration=7d \
        --max-retry-delay=600s \
        --min-retry-delay=10s \
        --quiet; then
        success "Created Pub/Sub subscription: ${SUBSCRIPTION_NAME}"
    else
        warning "Subscription ${SUBSCRIPTION_NAME} might already exist"
    fi
    
    # Grant Pub/Sub permission to invoke Cloud Run service
    if gcloud run services add-iam-policy-binding "${SERVICE_NAME}" \
        --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com" \
        --role="roles/run.invoker" \
        --region="${REGION}" \
        --quiet; then
        success "Granted Pub/Sub permissions to invoke Cloud Run service"
    else
        error "Failed to grant Pub/Sub permissions"
        exit 1
    fi
}

# Function to configure monitoring and alerting
configure_monitoring() {
    log "Configuring Cloud Monitoring and alerting..."
    
    # Create alert policy for anomaly detection
    cat > anomaly-alert-policy.json << EOF
{
  "displayName": "IoT Anomaly Detection Alert",
  "conditions": [
    {
      "displayName": "Anomaly Rate High",
      "conditionThreshold": {
        "filter": "metric.type=\"custom.googleapis.com/iot/anomaly_detected\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 5,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": []
}
EOF
    
    # Create the alert policy
    if gcloud alpha monitoring policies create --policy-from-file=anomaly-alert-policy.json --quiet; then
        success "Created anomaly detection alert policy"
    else
        warning "Alert policy creation failed - continuing deployment"
    fi
    
    # Create dashboard for monitoring edge analytics
    cat > dashboard-config.json << EOF
{
  "displayName": "Edge Analytics Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Data Processing Rate",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"custom.googleapis.com/iot/data_processed\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
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
    
    if gcloud monitoring dashboards create --config-from-file=dashboard-config.json --quiet; then
        success "Created monitoring dashboard"
    else
        warning "Dashboard creation failed - continuing deployment"
    fi
    
    # Clean up temporary files
    rm -f anomaly-alert-policy.json dashboard-config.json
}

# Function to create IoT data simulator
create_iot_simulator() {
    log "Creating IoT data simulator..."
    
    # Create IoT data simulator
    cat > iot-simulator.py << 'EOF'
#!/usr/bin/env python3
import json
import time
import random
import os
import sys

try:
    from google.cloud import pubsub_v1
except ImportError:
    print("Error: google-cloud-pubsub not installed. Run: pip3 install google-cloud-pubsub")
    sys.exit(1)

# Initialize Pub/Sub publisher
project_id = os.environ.get('PROJECT_ID')
topic_name = os.environ.get('TOPIC_NAME')

if not project_id or not topic_name:
    print("Error: PROJECT_ID and TOPIC_NAME environment variables must be set")
    sys.exit(1)

publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path(project_id, topic_name)

def generate_sensor_data(sensor_id):
    """Generate realistic IoT sensor data with occasional anomalies"""
    base_temp = 65.0
    base_pressure = 2.0
    base_vibration = 2.5
    
    # Introduce anomalies 10% of the time
    if random.random() < 0.1:
        # Generate anomalous data
        temperature = base_temp + random.uniform(15, 25)
        pressure = base_pressure + random.uniform(1, 2)
        vibration = base_vibration + random.uniform(3, 5)
    else:
        # Generate normal data with small variations
        temperature = base_temp + random.uniform(-5, 5)
        pressure = base_pressure + random.uniform(-0.3, 0.3)
        vibration = base_vibration + random.uniform(-1, 1)
    
    return {
        'sensor_id': sensor_id,
        'temperature': round(temperature, 2),
        'pressure': round(pressure, 2),
        'vibration': round(vibration, 2),
        'timestamp': int(time.time() * 1000)
    }

def publish_sensor_data():
    """Simulate multiple IoT sensors sending data"""
    sensors = ['pump-001', 'pump-002', 'compressor-001', 'motor-001', 'motor-002']
    
    for sensor_id in sensors:
        data = generate_sensor_data(sensor_id)
        message_json = json.dumps(data)
        message_bytes = message_json.encode('utf-8')
        
        # Publish to Pub/Sub
        try:
            future = publisher.publish(topic_path, message_bytes)
            print(f"Published data for {sensor_id}: {data}")
        except Exception as e:
            print(f"Error publishing data for {sensor_id}: {e}")
    
    print(f"Published {len(sensors)} sensor readings")

if __name__ == '__main__':
    print("Starting IoT data simulation...")
    print(f"Project ID: {project_id}")
    print(f"Topic: {topic_name}")
    
    try:
        while True:
            publish_sensor_data()
            time.sleep(10)  # Send data every 10 seconds
    except KeyboardInterrupt:
        print("\nStopping IoT simulation")
EOF
    
    # Make simulator executable
    chmod +x iot-simulator.py
    
    success "IoT data simulator created"
}

# Function to run deployment tests
run_deployment_tests() {
    log "Running deployment validation tests..."
    
    # Test Cloud Run service health
    log "Testing Cloud Run service health..."
    if curl -s -f "${SERVICE_URL}/health" > /dev/null; then
        success "Cloud Run service is healthy"
    else
        error "Cloud Run service health check failed"
        exit 1
    fi
    
    # Test direct service endpoint with sample data
    log "Testing service endpoint with sample data..."
    test_response=$(curl -s -X POST "${SERVICE_URL}/process" \
        -H "Content-Type: application/json" \
        -d '{
          "message": {
            "data": "'$(echo '{"sensor_id":"test-001","temperature":85.5,"pressure":3.2,"vibration":6.1,"timestamp":1640995200000}' | base64)'"
          }
        }')
    
    if [[ "$test_response" == "OK" ]]; then
        success "Service endpoint test passed"
    else
        warning "Service endpoint test returned: $test_response"
    fi
    
    # Verify Cloud Storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" > /dev/null 2>&1; then
        success "Cloud Storage bucket is accessible"
    else
        error "Cloud Storage bucket is not accessible"
        exit 1
    fi
    
    # Verify Pub/Sub resources
    if gcloud pubsub topics describe "${TOPIC_NAME}" > /dev/null 2>&1; then
        success "Pub/Sub topic is accessible"
    else
        error "Pub/Sub topic is not accessible"
        exit 1
    fi
    
    if gcloud pubsub subscriptions describe "${SUBSCRIPTION_NAME}" > /dev/null 2>&1; then
        success "Pub/Sub subscription is accessible"
    else
        error "Pub/Sub subscription is not accessible"
        exit 1
    fi
    
    success "All deployment validation tests passed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo ""
    echo "Resources Created:"
    echo "- Cloud Run Service: ${SERVICE_NAME}"
    echo "- Service URL: ${SERVICE_URL}"
    echo "- Pub/Sub Topic: ${TOPIC_NAME}"
    echo "- Pub/Sub Subscription: ${SUBSCRIPTION_NAME}"
    echo "- Cloud Storage Bucket: gs://${BUCKET_NAME}"
    echo ""
    echo "To test the deployment:"
    echo "1. Run the IoT simulator:"
    echo "   export PROJECT_ID=${PROJECT_ID}"
    echo "   export TOPIC_NAME=${TOPIC_NAME}"
    echo "   python3 iot-simulator.py"
    echo ""
    echo "2. Monitor logs:"
    echo "   gcloud logs tail --follow --format=\"table(timestamp,severity,textPayload)\" \\"
    echo "     --filter=\"resource.type=cloud_run_revision AND resource.labels.service_name=${SERVICE_NAME}\""
    echo ""
    echo "3. View processed data:"
    echo "   gsutil ls -r gs://${BUCKET_NAME}/analytics/"
    echo ""
    echo "4. Monitor in Cloud Console:"
    echo "   https://console.cloud.google.com/run/detail/${REGION}/${SERVICE_NAME}"
    echo ""
    success "Edge Analytics platform deployed successfully!"
}

# Main deployment function
main() {
    log "Starting Edge Analytics with Cloud Run WebAssembly and Pub/Sub deployment..."
    
    # Run all deployment steps
    check_prerequisites
    check_gcloud_auth
    setup_environment
    enable_apis
    create_storage_bucket
    create_pubsub_resources
    build_wasm_module
    create_cloud_run_service
    configure_pubsub_subscription
    configure_monitoring
    create_iot_simulator
    run_deployment_tests
    display_summary
    
    success "Deployment completed successfully!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi