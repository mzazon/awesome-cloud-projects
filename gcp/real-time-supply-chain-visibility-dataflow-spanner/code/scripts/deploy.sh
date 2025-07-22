#!/bin/bash

# Real-Time Supply Chain Visibility with Cloud Dataflow and Cloud Spanner - Deployment Script
# This script deploys the complete infrastructure for supply chain visibility platform

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log_info "Running in dry-run mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    log_info "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would execute: $cmd"
        return 0
    fi
    
    if eval "$cmd"; then
        log_success "$description completed"
        return 0
    else
        log_error "$description failed"
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if bq CLI is available
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install it first."
        exit 1
    fi
    
    # Check if python3 is available
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install it first."
        exit 1
    fi
    
    # Check if pip is available
    if ! command -v pip &> /dev/null; then
        log_error "pip is not installed. Please install it first."
        exit 1
    fi
    
    log_success "All prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="supply-chain-visibility-$(date +%s)"
        log_info "Generated PROJECT_ID: $PROJECT_ID"
    fi
    
    # Set default region if not provided
    if [[ -z "${REGION:-}" ]]; then
        export REGION="us-central1"
    fi
    
    # Set default zone if not provided
    if [[ -z "${ZONE:-}" ]]; then
        export ZONE="us-central1-a"
    fi
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export SPANNER_INSTANCE="supply-chain-instance-${RANDOM_SUFFIX}"
    export SPANNER_DATABASE="supply-chain-db"
    export PUBSUB_TOPIC="logistics-events"
    export PUBSUB_SUBSCRIPTION="logistics-events-sub"
    export BIGQUERY_DATASET="supply_chain_analytics"
    export DATAFLOW_JOB="supply-chain-streaming-${RANDOM_SUFFIX}"
    export STORAGE_BUCKET="supply-chain-dataflow-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured"
    log_info "PROJECT_ID: $PROJECT_ID"
    log_info "REGION: $REGION"
    log_info "SPANNER_INSTANCE: $SPANNER_INSTANCE"
    log_info "STORAGE_BUCKET: $STORAGE_BUCKET"
}

# Function to create or select project
setup_project() {
    log_info "Setting up GCP project..."
    
    # Check if project exists
    if gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_info "Project $PROJECT_ID already exists, using existing project"
    else
        if [[ "$DRY_RUN" == "false" ]]; then
            log_info "Creating new project: $PROJECT_ID"
            gcloud projects create "$PROJECT_ID" --name="Supply Chain Visibility"
        fi
    fi
    
    # Set default project and region
    execute_cmd "gcloud config set project ${PROJECT_ID}" "Setting default project"
    execute_cmd "gcloud config set compute/region ${REGION}" "Setting default region"
    execute_cmd "gcloud config set compute/zone ${ZONE}" "Setting default zone"
    
    log_success "Project setup completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "dataflow.googleapis.com"
        "spanner.googleapis.com"
        "pubsub.googleapis.com"
        "bigquery.googleapis.com"
        "storage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_cmd "gcloud services enable $api" "Enabling $api"
    done
    
    log_success "All required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for Dataflow staging..."
    
    execute_cmd "gsutil mb -p ${PROJECT_ID} -c STANDARD -l ${REGION} gs://${STORAGE_BUCKET}" \
        "Creating storage bucket gs://${STORAGE_BUCKET}"
    
    log_success "Storage bucket created"
}

# Function to create Spanner instance and database
create_spanner_resources() {
    log_info "Creating Cloud Spanner instance and database..."
    
    execute_cmd "gcloud spanner instances create ${SPANNER_INSTANCE} \
        --config=regional-${REGION} \
        --description=\"Supply Chain Visibility Database\" \
        --nodes=1" \
        "Creating Spanner instance"
    
    execute_cmd "gcloud spanner databases create ${SPANNER_DATABASE} \
        --instance=${SPANNER_INSTANCE}" \
        "Creating Spanner database"
    
    log_success "Spanner resources created"
}

# Function to create database schema
create_database_schema() {
    log_info "Creating database schema..."
    
    # Create shipments table
    execute_cmd "gcloud spanner databases ddl update ${SPANNER_DATABASE} \
        --instance=${SPANNER_INSTANCE} \
        --ddl='CREATE TABLE Shipments (
            ShipmentId STRING(50) NOT NULL,
            OrderId STRING(50) NOT NULL,
            CarrierId STRING(50),
            TrackingNumber STRING(100),
            Status STRING(20) NOT NULL,
            OriginLocation STRING(100),
            DestinationLocation STRING(100),
            EstimatedDelivery TIMESTAMP,
            ActualDelivery TIMESTAMP,
            LastUpdated TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true),
            CreatedAt TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true)
        ) PRIMARY KEY (ShipmentId)'" \
        "Creating Shipments table"
    
    # Create inventory table
    execute_cmd "gcloud spanner databases ddl update ${SPANNER_DATABASE} \
        --instance=${SPANNER_INSTANCE} \
        --ddl='CREATE TABLE Inventory (
            ItemId STRING(50) NOT NULL,
            LocationId STRING(50) NOT NULL,
            Quantity INT64 NOT NULL,
            AvailableQuantity INT64 NOT NULL,
            ReservedQuantity INT64 NOT NULL,
            LastUpdated TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true)
        ) PRIMARY KEY (ItemId, LocationId)'" \
        "Creating Inventory table"
    
    # Create events log table
    execute_cmd "gcloud spanner databases ddl update ${SPANNER_DATABASE} \
        --instance=${SPANNER_INSTANCE} \
        --ddl='CREATE TABLE Events (
            EventId STRING(50) NOT NULL,
            ShipmentId STRING(50),
            EventType STRING(50) NOT NULL,
            EventData JSON,
            Location STRING(100),
            Timestamp TIMESTAMP NOT NULL,
            ProcessedAt TIMESTAMP NOT NULL OPTIONS (allow_commit_timestamp=true)
        ) PRIMARY KEY (EventId)'" \
        "Creating Events table"
    
    log_success "Database schema created"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topic and subscription..."
    
    execute_cmd "gcloud pubsub topics create ${PUBSUB_TOPIC}" \
        "Creating Pub/Sub topic"
    
    execute_cmd "gcloud pubsub subscriptions create ${PUBSUB_SUBSCRIPTION} \
        --topic=${PUBSUB_TOPIC} \
        --ack-deadline=60" \
        "Creating Pub/Sub subscription"
    
    log_success "Pub/Sub resources created"
}

# Function to create BigQuery resources
create_bigquery_resources() {
    log_info "Creating BigQuery dataset and tables..."
    
    execute_cmd "bq mk --location=${REGION} ${PROJECT_ID}:${BIGQUERY_DATASET}" \
        "Creating BigQuery dataset"
    
    execute_cmd "bq mk --table \
        ${PROJECT_ID}:${BIGQUERY_DATASET}.shipment_analytics \
        shipment_id:STRING,order_id:STRING,carrier_id:STRING,status:STRING,origin:STRING,destination:STRING,estimated_delivery:TIMESTAMP,actual_delivery:TIMESTAMP,transit_time_hours:FLOAT,created_date:DATE" \
        "Creating shipment analytics table"
    
    execute_cmd "bq mk --table \
        --time_partitioning_field=event_timestamp \
        --time_partitioning_type=DAY \
        ${PROJECT_ID}:${BIGQUERY_DATASET}.event_analytics \
        event_id:STRING,shipment_id:STRING,event_type:STRING,location:STRING,event_timestamp:TIMESTAMP,processing_delay_seconds:FLOAT" \
        "Creating event analytics table"
    
    log_success "BigQuery resources created"
}

# Function to create Dataflow pipeline code
create_dataflow_pipeline() {
    log_info "Creating Dataflow pipeline code..."
    
    # Create directory for pipeline code
    mkdir -p dataflow-pipeline
    
    # Create requirements file
    cat > dataflow-pipeline/requirements.txt << 'EOF'
apache-beam[gcp]==2.52.0
google-cloud-spanner==3.40.1
google-cloud-bigquery==3.13.0
EOF
    
    # Create main pipeline file
    cat > dataflow-pipeline/supply_chain_pipeline.py << 'EOF'
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.transforms import window
import json
import logging
import os
from datetime import datetime
from google.cloud import spanner
from google.cloud import bigquery

class ParseLogisticsEvent(beam.DoFn):
    def process(self, element):
        try:
            # Parse JSON event from Pub/Sub
            event_data = json.loads(element.decode('utf-8'))
            
            # Extract and validate required fields
            event = {
                'event_id': event_data.get('event_id'),
                'shipment_id': event_data.get('shipment_id'),
                'event_type': event_data.get('event_type'),
                'location': event_data.get('location'),
                'timestamp': event_data.get('timestamp'),
                'event_data': event_data
            }
            
            # Validate required fields
            if all(event[field] for field in ['event_id', 'shipment_id', 'event_type']):
                yield event
            else:
                logging.warning(f"Incomplete event data: {event_data}")
                
        except json.JSONDecodeError as e:
            logging.error(f"Failed to parse JSON: {e}")
        except Exception as e:
            logging.error(f"Error processing event: {e}")

class UpdateSpannerData(beam.DoFn):
    def __init__(self, project_id, instance_id, database_id):
        self.project_id = project_id
        self.instance_id = instance_id
        self.database_id = database_id
        self.spanner_client = None
        
    def setup(self):
        self.spanner_client = spanner.Client(project=self.project_id)
        self.instance = self.spanner_client.instance(self.instance_id)
        self.database = self.instance.database(self.database_id)
    
    def process(self, element):
        try:
            with self.database.batch() as batch:
                # Insert event record
                batch.insert(
                    table='Events',
                    columns=['EventId', 'ShipmentId', 'EventType', 'EventData', 'Location', 'Timestamp', 'ProcessedAt'],
                    values=[(
                        element['event_id'],
                        element['shipment_id'],
                        element['event_type'],
                        json.dumps(element['event_data']),
                        element.get('location'),
                        element['timestamp'],
                        spanner.COMMIT_TIMESTAMP
                    )]
                )
                
                # Update shipment status based on event type
                if element['event_type'] in ['shipped', 'in_transit', 'delivered', 'exception']:
                    batch.update(
                        table='Shipments',
                        columns=['ShipmentId', 'Status', 'LastUpdated'],
                        values=[(
                            element['shipment_id'],
                            element['event_type'],
                            spanner.COMMIT_TIMESTAMP
                        )]
                    )
            
            yield element
            
        except Exception as e:
            logging.error(f"Failed to update Spanner: {e}")

class PrepareForBigQuery(beam.DoFn):
    def process(self, element):
        try:
            # Transform for BigQuery analytics table
            bq_record = {
                'event_id': element['event_id'],
                'shipment_id': element['shipment_id'],
                'event_type': element['event_type'],
                'location': element.get('location'),
                'event_timestamp': element['timestamp'],
                'processing_delay_seconds': (
                    datetime.utcnow() - datetime.fromisoformat(element['timestamp'].replace('Z', '+00:00'))
                ).total_seconds()
            }
            
            yield bq_record
            
        except Exception as e:
            logging.error(f"Failed to prepare BigQuery record: {e}")

def run_pipeline(argv=None):
    pipeline_options = PipelineOptions(argv)
    
    # Get environment variables
    project_id = os.environ.get('PROJECT_ID')
    spanner_instance = os.environ.get('SPANNER_INSTANCE')
    spanner_database = os.environ.get('SPANNER_DATABASE')
    pubsub_subscription = os.environ.get('PUBSUB_SUBSCRIPTION')
    bigquery_dataset = os.environ.get('BIGQUERY_DATASET')
    
    with beam.Pipeline(options=pipeline_options) as pipeline:
        # Read from Pub/Sub
        events = (pipeline
                 | 'Read from Pub/Sub' >> beam.io.ReadFromPubSub(subscription=f'projects/{project_id}/subscriptions/{pubsub_subscription}')
                 | 'Parse Events' >> beam.ParDo(ParseLogisticsEvent())
                 | 'Window Events' >> beam.WindowInto(window.FixedWindows(60)))  # 1-minute windows
        
        # Update Spanner database
        (events
         | 'Update Spanner' >> beam.ParDo(UpdateSpannerData(project_id, spanner_instance, spanner_database)))
        
        # Send to BigQuery for analytics
        (events
         | 'Prepare for BigQuery' >> beam.ParDo(PrepareForBigQuery())
         | 'Write to BigQuery' >> beam.io.WriteToBigQuery(
             table=f'{project_id}:{bigquery_dataset}.event_analytics',
             write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
             create_disposition=beam.io.BigQueryDisposition.CREATE_NEVER))

if __name__ == '__main__':
    logging.getLogger().setLevel(logging.INFO)
    run_pipeline()
EOF
    
    log_success "Dataflow pipeline code created"
}

# Function to deploy Dataflow pipeline
deploy_dataflow_pipeline() {
    log_info "Deploying Dataflow streaming pipeline..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cd dataflow-pipeline
        
        # Install Python dependencies
        pip install -r requirements.txt
        
        # Deploy streaming pipeline
        python supply_chain_pipeline.py \
            --project=${PROJECT_ID} \
            --region=${REGION} \
            --job_name=${DATAFLOW_JOB} \
            --temp_location=gs://${STORAGE_BUCKET}/temp \
            --staging_location=gs://${STORAGE_BUCKET}/staging \
            --runner=DataflowRunner \
            --streaming \
            --max_num_workers=5 \
            --num_workers=2
        
        cd ..
    else
        log_info "Would deploy Dataflow pipeline with job name: $DATAFLOW_JOB"
    fi
    
    log_success "Dataflow pipeline deployed"
}

# Function to create event generator
create_event_generator() {
    log_info "Creating sample event generator..."
    
    cat > generate_sample_events.py << 'EOF'
import json
import random
import time
import os
from datetime import datetime, timedelta
from google.cloud import pubsub_v1
import uuid

def generate_logistics_event():
    event_types = ['shipped', 'in_transit', 'out_for_delivery', 'delivered', 'exception', 'delayed']
    locations = ['New York, NY', 'Los Angeles, CA', 'Chicago, IL', 'Houston, TX', 'Phoenix, AZ', 'Philadelphia, PA']
    carriers = ['UPS', 'FedEx', 'DHL', 'USPS', 'Amazon Logistics']
    
    event = {
        'event_id': str(uuid.uuid4()),
        'shipment_id': f'SH{random.randint(100000, 999999)}',
        'order_id': f'ORD{random.randint(10000, 99999)}',
        'event_type': random.choice(event_types),
        'carrier_id': random.choice(carriers),
        'location': random.choice(locations),
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'tracking_number': f'1Z{random.randint(100000000000, 999999999999)}',
        'metadata': {
            'temperature': random.randint(-10, 40) if random.random() > 0.7 else None,
            'humidity': random.randint(30, 90) if random.random() > 0.8 else None,
            'weight_kg': round(random.uniform(0.1, 50.0), 2)
        }
    }
    
    return event

def publish_events(project_id, topic_name, num_events=50):
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic_name)
    
    print(f"Publishing {num_events} events to {topic_path}")
    
    for i in range(num_events):
        event = generate_logistics_event()
        message_data = json.dumps(event).encode('utf-8')
        
        future = publisher.publish(topic_path, message_data)
        print(f"Published event {i+1}: {event['event_id']} - {event['event_type']}")
        
        # Add small delay to simulate real-time flow
        time.sleep(random.uniform(0.1, 2.0))
    
    print(f"✅ Published {num_events} logistics events")

if __name__ == '__main__':
    project_id = os.environ['PROJECT_ID']
    topic_name = os.environ['PUBSUB_TOPIC']
    
    publish_events(project_id, topic_name, 50)
EOF
    
    log_success "Event generator created"
}

# Function to generate sample events
generate_sample_events() {
    log_info "Generating sample logistics events..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Install required Python packages
        pip install google-cloud-pubsub
        
        # Generate sample events
        python generate_sample_events.py
        
        # Wait for processing
        log_info "Waiting 30 seconds for event processing..."
        sleep 30
    else
        log_info "Would generate sample events and wait for processing"
    fi
    
    log_success "Sample events generated and processed"
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Check Spanner data
        log_info "Checking Spanner data..."
        gcloud spanner databases execute-sql ${SPANNER_DATABASE} \
            --instance=${SPANNER_INSTANCE} \
            --sql="SELECT EventType, COUNT(*) as EventCount FROM Events GROUP BY EventType ORDER BY EventCount DESC" || true
        
        # Check BigQuery data
        log_info "Checking BigQuery data..."
        bq query --use_legacy_sql=false \
            "SELECT event_type, COUNT(*) as event_count FROM \`${PROJECT_ID}.${BIGQUERY_DATASET}.event_analytics\` GROUP BY event_type ORDER BY event_count DESC LIMIT 10" || true
        
        # Check Dataflow job status
        log_info "Checking Dataflow job status..."
        gcloud dataflow jobs list --region=${REGION} --filter="name:${DATAFLOW_JOB}" || true
    else
        log_info "Would validate Spanner data, BigQuery data, and Dataflow job status"
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Spanner Instance: $SPANNER_INSTANCE"
    echo "Spanner Database: $SPANNER_DATABASE"
    echo "Pub/Sub Topic: $PUBSUB_TOPIC"
    echo "BigQuery Dataset: $BIGQUERY_DATASET"
    echo "Dataflow Job: $DATAFLOW_JOB"
    echo "Storage Bucket: gs://$STORAGE_BUCKET"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Monitor the Dataflow job in the GCP Console"
    echo "2. Check BigQuery for analytics data"
    echo "3. Query Spanner for operational data"
    echo "4. Generate more events using generate_sample_events.py"
    echo
    echo "=== CLEANUP ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo
}

# Main deployment function
main() {
    echo "=== Real-Time Supply Chain Visibility - Deployment Script ==="
    echo
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_bucket
    create_spanner_resources
    create_database_schema
    create_pubsub_resources
    create_bigquery_resources
    create_dataflow_pipeline
    deploy_dataflow_pipeline
    create_event_generator
    generate_sample_events
    validate_deployment
    display_summary
}

# Run main function
main "$@"