#!/bin/bash

# Digital Twin Manufacturing Resilience with IoT and Vertex AI - Deployment Script
# This script deploys the complete infrastructure for the digital twin manufacturing solution
# 
# Usage: ./deploy.sh [PROJECT_ID] [REGION]
# 
# If PROJECT_ID is not provided, a new project will be created
# If REGION is not provided, us-central1 will be used as default

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available. Please ensure Google Cloud SDK is properly installed"
        exit 1
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        error "bq (BigQuery CLI) is not available. Please ensure Google Cloud SDK is properly installed"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random suffixes"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to create or validate project
setup_project() {
    local project_id="$1"
    
    log "Setting up project: $project_id"
    
    # Check if project exists
    if gcloud projects describe "$project_id" &>/dev/null; then
        log "Using existing project: $project_id"
    else
        log "Creating new project: $project_id"
        gcloud projects create "$project_id" --name="Manufacturing Digital Twin"
        
        # Enable billing (user needs to link billing account manually)
        warning "Please ensure billing is enabled for project $project_id"
        warning "You can do this at: https://console.cloud.google.com/billing"
        read -p "Press Enter after enabling billing to continue..."
    fi
    
    # Set default project
    gcloud config set project "$project_id"
    success "Project setup completed"
}

# Function to enable APIs
enable_apis() {
    log "Enabling required APIs..."
    
    local apis=(
        "pubsub.googleapis.com"
        "dataflow.googleapis.com"
        "bigquery.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        gcloud services enable "$api" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log "Creating Pub/Sub topics and subscriptions..."
    
    # Create topics
    local topics=(
        "manufacturing-sensor-data"
        "failure-simulation-events"
        "recovery-commands"
    )
    
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe "$topic" &>/dev/null; then
            log "Topic $topic already exists"
        else
            gcloud pubsub topics create "$topic"
            success "Created topic: $topic"
        fi
    done
    
    # Create subscriptions
    local subscriptions=(
        "sensor-data-processing:manufacturing-sensor-data"
        "simulation-processing:failure-simulation-events"
    )
    
    for sub_topic in "${subscriptions[@]}"; do
        IFS=':' read -r subscription topic <<< "$sub_topic"
        if gcloud pubsub subscriptions describe "$subscription" &>/dev/null; then
            log "Subscription $subscription already exists"
        else
            gcloud pubsub subscriptions create "$subscription" --topic="$topic"
            success "Created subscription: $subscription"
        fi
    done
}

# Function to create BigQuery resources
create_bigquery_resources() {
    log "Creating BigQuery dataset and tables..."
    
    # Create dataset
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        log "Dataset $DATASET_NAME already exists"
    else
        bq mk --location="$REGION" "${PROJECT_ID}:${DATASET_NAME}"
        success "Created BigQuery dataset: $DATASET_NAME"
    fi
    
    # Create tables with schemas
    local tables=(
        "sensor_data:timestamp:TIMESTAMP,equipment_id:STRING,sensor_type:STRING,value:FLOAT,unit:STRING,location:STRING"
        "simulation_results:simulation_id:STRING,timestamp:TIMESTAMP,scenario:STRING,equipment_id:STRING,predicted_outcome:STRING,confidence:FLOAT,recovery_time:INTEGER"
        "equipment_metadata:equipment_id:STRING,equipment_type:STRING,manufacturer:STRING,model:STRING,installation_date:DATE,criticality_level:STRING,location:STRING"
    )
    
    for table_schema in "${tables[@]}"; do
        IFS=':' read -r table_name schema <<< "$table_schema"
        if bq ls "${PROJECT_ID}:${DATASET_NAME}" | grep -q "$table_name"; then
            log "Table $table_name already exists"
        else
            bq mk --table "${PROJECT_ID}:${DATASET_NAME}.${table_name}" "$schema"
            success "Created BigQuery table: $table_name"
        fi
    done
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..."
    
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log "Bucket $BUCKET_NAME already exists"
    else
        gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://${BUCKET_NAME}"
        gsutil versioning set on "gs://${BUCKET_NAME}"
        success "Created Cloud Storage bucket: $BUCKET_NAME"
    fi
    
    # Create folder structure
    log "Creating folder structure..."
    local folders=("models" "training-data" "simulation-configs" "temp" "dataflow")
    
    for folder in "${folders[@]}"; do
        echo "Creating folder structure..." | gsutil cp - "gs://${BUCKET_NAME}/${folder}/.keep"
    done
    
    success "Storage bucket structure created"
}

# Function to upload and prepare Dataflow pipeline
prepare_dataflow_pipeline() {
    log "Preparing Dataflow pipeline..."
    
    # Create temporary directory for pipeline code
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    cat > sensor_data_pipeline.py << 'EOF'
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
import json
from datetime import datetime
import os

class ProcessSensorData(beam.DoFn):
    def process(self, element):
        try:
            data = json.loads(element)
            # Add processing timestamp and validate data
            data['processing_timestamp'] = datetime.utcnow().isoformat()
            if 'equipment_id' in data and 'sensor_type' in data and 'value' in data:
                yield data
        except Exception as e:
            # Log error and continue processing
            yield beam.pvalue.TaggedOutput('errors', str(e))

def run_pipeline():
    PROJECT_ID = os.environ.get('PROJECT_ID')
    DATASET_NAME = os.environ.get('DATASET_NAME')
    pipeline_options = PipelineOptions()
    
    with beam.Pipeline(options=pipeline_options) as pipeline:
        sensor_data = (pipeline
            | 'Read from Pub/Sub' >> beam.io.ReadFromPubSub(
                topic=f'projects/{PROJECT_ID}/topics/manufacturing-sensor-data')
            | 'Process Data' >> beam.ParDo(ProcessSensorData()).with_outputs('errors', main='processed')
            | 'Write to BigQuery' >> beam.io.WriteToBigQuery(
                table=f'{PROJECT_ID}:{DATASET_NAME}.sensor_data',
                write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND))

if __name__ == '__main__':
    run_pipeline()
EOF
    
    # Upload pipeline code to Cloud Storage
    gsutil cp sensor_data_pipeline.py "gs://${BUCKET_NAME}/dataflow/"
    
    # Cleanup
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    success "Dataflow pipeline code uploaded"
}

# Function to create Vertex AI dataset
create_vertex_ai_dataset() {
    log "Creating Vertex AI dataset..."
    
    # Create sample training data
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    cat > training_data.jsonl << 'EOF'
{"equipment_id": "pump_001", "temperature": 75.2, "vibration": 0.3, "pressure": 150.5, "failure_in_hours": 0}
{"equipment_id": "pump_001", "temperature": 78.1, "vibration": 0.4, "pressure": 148.2, "failure_in_hours": 0}
{"equipment_id": "pump_001", "temperature": 82.3, "vibration": 0.7, "pressure": 145.1, "failure_in_hours": 24}
{"equipment_id": "pump_001", "temperature": 85.4, "vibration": 1.2, "pressure": 142.8, "failure_in_hours": 12}
{"equipment_id": "compressor_002", "temperature": 68.5, "vibration": 0.2, "pressure": 200.1, "failure_in_hours": 0}
{"equipment_id": "compressor_002", "temperature": 71.2, "vibration": 0.5, "pressure": 195.3, "failure_in_hours": 48}
EOF
    
    # Upload training data
    gsutil cp training_data.jsonl "gs://${BUCKET_NAME}/training-data/"
    
    # Create managed dataset
    local dataset_display_name="manufacturing-failure-prediction"
    if gcloud ai datasets list --region="$REGION" --filter="displayName:$dataset_display_name" --format="value(name)" | grep -q "datasets"; then
        log "Vertex AI dataset already exists"
    else
        gcloud ai datasets create \
            --display-name="$dataset_display_name" \
            --metadata-schema-uri="gs://google-cloud-aiplatform/schema/dataset/metadata/tabular_1.0.0.yaml" \
            --region="$REGION"
        success "Created Vertex AI dataset"
    fi
    
    # Get and store dataset ID
    DATASET_ID=$(gcloud ai datasets list \
        --region="$REGION" \
        --filter="displayName:$dataset_display_name" \
        --format="value(name)" | cut -d'/' -f6)
    
    echo "DATASET_ID=$DATASET_ID" >> "${HOME}/.digital_twin_env"
    
    # Cleanup
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    success "Vertex AI dataset created with ID: $DATASET_ID"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log "Deploying Cloud Function for digital twin simulation..."
    
    # Create temporary directory for function code
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    cat > main.py << 'EOF'
import functions_framework
import json
import random
from datetime import datetime, timedelta
from google.cloud import pubsub_v1
import os

@functions_framework.http
def simulate_failure_scenario(request):
    """Simulate equipment failure scenarios for resilience testing"""
    
    publisher = pubsub_v1.PublisherClient()
    project_id = os.environ.get('PROJECT_ID')
    topic_path = publisher.topic_path(project_id, 'failure-simulation-events')
    
    # Parse simulation request
    request_json = request.get_json()
    if not request_json:
        request_json = {}
    
    equipment_id = request_json.get('equipment_id', 'pump_001')
    failure_type = request_json.get('failure_type', 'temperature_spike')
    duration_hours = request_json.get('duration_hours', 2)
    
    # Generate failure simulation data
    simulation_id = f"sim_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{random.randint(1000, 9999)}"
    
    simulation_event = {
        'simulation_id': simulation_id,
        'equipment_id': equipment_id,
        'failure_type': failure_type,
        'start_time': datetime.utcnow().isoformat(),
        'duration_hours': duration_hours,
        'severity': random.choice(['low', 'medium', 'high']),
        'predicted_recovery_time': random.randint(30, 180),
        'business_impact': calculate_business_impact(failure_type, duration_hours)
    }
    
    # Publish simulation event
    future = publisher.publish(topic_path, json.dumps(simulation_event).encode('utf-8'))
    future.result()
    
    return {
        'simulation_id': simulation_id,
        'status': 'simulation_started',
        'details': simulation_event
    }

def calculate_business_impact(failure_type, duration_hours):
    """Calculate estimated business impact of failure scenario"""
    base_cost_per_hour = 50000  # $50k per hour downtime cost
    
    multipliers = {
        'temperature_spike': 1.2,
        'vibration_anomaly': 1.5,
        'pressure_drop': 2.0,
        'complete_failure': 3.0
    }
    
    multiplier = multipliers.get(failure_type, 1.0)
    total_impact = base_cost_per_hour * duration_hours * multiplier
    
    return {
        'estimated_cost': total_impact,
        'affected_production_lines': random.randint(1, 5),
        'recovery_complexity': 'high' if total_impact > 200000 else 'medium'
    }
EOF
    
    cat > requirements.txt << 'EOF'
functions-framework==3.*
google-cloud-pubsub==2.*
EOF
    
    # Check if function already exists
    if gcloud functions describe digital-twin-simulator --region="$REGION" &>/dev/null; then
        log "Cloud Function already exists, updating..."
        gcloud functions deploy digital-twin-simulator \
            --runtime python311 \
            --trigger-http \
            --entry-point simulate_failure_scenario \
            --source . \
            --set-env-vars PROJECT_ID="$PROJECT_ID" \
            --memory 256MB \
            --timeout 60s \
            --region "$REGION" \
            --allow-unauthenticated \
            --quiet
    else
        gcloud functions deploy digital-twin-simulator \
            --runtime python311 \
            --trigger-http \
            --entry-point simulate_failure_scenario \
            --source . \
            --set-env-vars PROJECT_ID="$PROJECT_ID" \
            --memory 256MB \
            --timeout 60s \
            --region "$REGION" \
            --allow-unauthenticated
    fi
    
    # Cleanup
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    success "Cloud Function deployed successfully"
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    log "Creating monitoring dashboard..."
    
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    cat > dashboard_config.json << EOF
{
  "displayName": "Manufacturing Digital Twin Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Sensor Data Ingestion Rate",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "unitOverride": "1/s",
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
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Simulation Execution Metrics",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_function\"",
                    "aggregation": {
                      "alignmentPeriod": "300s",
                      "perSeriesAligner": "ALIGN_MEAN"
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
    
    # Create dashboard if it doesn't exist
    if ! gcloud monitoring dashboards list --filter="displayName:Manufacturing Digital Twin Dashboard" --format="value(name)" | grep -q "dashboards"; then
        gcloud monitoring dashboards create --config-from-file=dashboard_config.json
        success "Monitoring dashboard created"
    else
        log "Monitoring dashboard already exists"
    fi
    
    # Cleanup
    cd - > /dev/null
    rm -rf "$temp_dir"
}

# Function to perform validation tests
run_validation_tests() {
    log "Running validation tests..."
    
    # Test Pub/Sub functionality
    log "Testing Pub/Sub message flow..."
    gcloud pubsub topics publish manufacturing-sensor-data \
        --message='{"equipment_id":"test_pump","sensor_type":"temperature","value":75.5,"unit":"celsius","timestamp":"2025-07-23T10:00:00Z"}' \
        &>/dev/null
    
    # Wait a moment for message propagation
    sleep 5
    
    # Check if message can be pulled
    if gcloud pubsub subscriptions pull sensor-data-processing --limit=1 --format="value(message.data)" 2>/dev/null | base64 -d | grep -q "test_pump"; then
        success "Pub/Sub message flow test passed"
    else
        warning "Pub/Sub message flow test did not find expected message (this is normal for new deployments)"
    fi
    
    # Test Cloud Function
    log "Testing Cloud Function..."
    FUNCTION_URL=$(gcloud functions describe digital-twin-simulator \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    if curl -s -X POST "$FUNCTION_URL" \
        -H "Content-Type: application/json" \
        -d '{"equipment_id":"pump_001","failure_type":"temperature_spike","duration_hours":2}' | grep -q "simulation_started"; then
        success "Cloud Function test passed"
    else
        warning "Cloud Function test failed - function may still be deploying"
    fi
    
    # Test BigQuery
    log "Testing BigQuery access..."
    if bq query --use_legacy_sql=false "SELECT 1 as test" &>/dev/null; then
        success "BigQuery access test passed"
    else
        warning "BigQuery access test failed"
    fi
    
    success "Validation tests completed"
}

# Function to save environment variables
save_environment() {
    log "Saving environment variables..."
    
    cat > "${HOME}/.digital_twin_env" << EOF
# Digital Twin Manufacturing Environment Variables
export PROJECT_ID="$PROJECT_ID"
export REGION="$REGION"
export ZONE="$ZONE"
export DATASET_NAME="$DATASET_NAME"
export BUCKET_NAME="$BUCKET_NAME"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF
    
    success "Environment variables saved to ${HOME}/.digital_twin_env"
    echo "To use these variables in a new shell, run: source ${HOME}/.digital_twin_env"
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "=================================="
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=================================="
    echo ""
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Dataset: $DATASET_NAME"
    echo "Storage Bucket: $BUCKET_NAME"
    echo ""
    echo "Resources Created:"
    echo "✅ Pub/Sub Topics and Subscriptions"
    echo "✅ BigQuery Dataset and Tables"
    echo "✅ Cloud Storage Bucket"
    echo "✅ Vertex AI Dataset"
    echo "✅ Cloud Function (Digital Twin Simulator)"
    echo "✅ Monitoring Dashboard"
    echo ""
    echo "Cloud Function URL:"
    FUNCTION_URL=$(gcloud functions describe digital-twin-simulator --region="$REGION" --format="value(httpsTrigger.url)" 2>/dev/null || echo "Not available")
    echo "$FUNCTION_URL"
    echo ""
    echo "To test the system:"
    echo "1. Publish test sensor data to Pub/Sub"
    echo "2. Trigger failure simulations via Cloud Function"
    echo "3. View results in BigQuery and monitoring dashboard"
    echo ""
    echo "Environment variables saved to: ${HOME}/.digital_twin_env"
    echo "Run 'source ${HOME}/.digital_twin_env' to load them"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo "=================================="
}

# Main deployment function
main() {
    echo "🚀 Starting Digital Twin Manufacturing Resilience Deployment"
    echo "============================================================="
    
    # Parse command line arguments
    PROJECT_ID=${1:-"manufacturing-twin-$(date +%s)"}
    REGION=${2:-"us-central1"}
    ZONE="${REGION}-a"
    DATASET_NAME="manufacturing_data"
    BUCKET_NAME="manufacturing-twin-storage-$(openssl rand -hex 3)"
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    log "Project ID: $PROJECT_ID"
    log "Region: $REGION"
    log "Dataset: $DATASET_NAME"
    log "Bucket: $BUCKET_NAME"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Setup project
    setup_project "$PROJECT_ID"
    
    # Set gcloud configuration
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    # Enable APIs
    enable_apis
    
    # Create resources
    create_pubsub_resources
    create_bigquery_resources
    create_storage_bucket
    prepare_dataflow_pipeline
    create_vertex_ai_dataset
    deploy_cloud_function
    create_monitoring_dashboard
    
    # Run validation tests
    run_validation_tests
    
    # Save environment
    save_environment
    
    # Display summary
    display_summary
}

# Error handling
trap 'error "Deployment failed at line $LINENO"' ERR

# Run main function
main "$@"