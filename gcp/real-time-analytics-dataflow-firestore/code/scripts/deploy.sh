#!/bin/bash

# Real-Time Analytics with Cloud Dataflow and Firestore - Deployment Script
# This script deploys the complete streaming analytics platform including:
# - Pub/Sub topic and subscription for event ingestion
# - Firestore database for real-time queries
# - Cloud Storage bucket for data archival
# - Service account with appropriate permissions
# - Apache Beam streaming pipeline on Dataflow

set -euo pipefail

# Color codes for output
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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install the Google Cloud SDK."
        exit 1
    fi
    
    # Check if python3 is installed
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed. Please install Python 3."
        exit 1
    fi
    
    # Check if pip is installed
    if ! command -v pip &> /dev/null; then
        error "pip is not installed. Please install pip."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set project ID (try to get from gcloud config, otherwise prompt user)
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            read -p "Enter your Google Cloud Project ID: " PROJECT_ID
            if [[ -z "$PROJECT_ID" ]]; then
                error "Project ID is required"
                exit 1
            fi
        fi
    fi
    
    # Set default region if not provided
    if [[ -z "${REGION:-}" ]]; then
        REGION="us-central1"
    fi
    
    if [[ -z "${ZONE:-}" ]]; then
        ZONE="us-central1-a"
    fi
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export PROJECT_ID
    export REGION
    export ZONE
    export PUBSUB_TOPIC="events-topic-${RANDOM_SUFFIX}"
    export SUBSCRIPTION="events-subscription-${RANDOM_SUFFIX}"
    export DATAFLOW_JOB="streaming-analytics-${RANDOM_SUFFIX}"
    export STORAGE_BUCKET="${PROJECT_ID}-analytics-archive-${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT_NAME="dataflow-analytics"
    export SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Create deployment state file
    cat > deployment_state.env << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
PUBSUB_TOPIC=${PUBSUB_TOPIC}
SUBSCRIPTION=${SUBSCRIPTION}
DATAFLOW_JOB=${DATAFLOW_JOB}
STORAGE_BUCKET=${STORAGE_BUCKET}
SERVICE_ACCOUNT_NAME=${SERVICE_ACCOUNT_NAME}
SERVICE_ACCOUNT_EMAIL=${SERVICE_ACCOUNT_EMAIL}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    info "Environment variables configured:"
    info "  Project ID: ${PROJECT_ID}"
    info "  Region: ${REGION}"
    info "  Zone: ${ZONE}"
    info "  Random Suffix: ${RANDOM_SUFFIX}"
}

# Function to configure gcloud
configure_gcloud() {
    log "Configuring gcloud settings..."
    
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log "gcloud configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "dataflow.googleapis.com"
        "pubsub.googleapis.com"
        "firestore.googleapis.com"
        "storage.googleapis.com"
        "appengine.googleapis.com"
        "compute.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log "Successfully enabled ${api}"
        else
            error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    info "Waiting 60 seconds for APIs to be fully enabled..."
    sleep 60
    
    log "All required APIs enabled successfully"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log "Creating Pub/Sub topic and subscription..."
    
    # Create Pub/Sub topic
    if gcloud pubsub topics create "${PUBSUB_TOPIC}" \
        --message-retention-duration=7d \
        --message-storage-policy-allowed-regions="${REGION}" \
        --quiet; then
        log "Pub/Sub topic '${PUBSUB_TOPIC}' created successfully"
    else
        error "Failed to create Pub/Sub topic"
        exit 1
    fi
    
    # Create subscription
    if gcloud pubsub subscriptions create "${SUBSCRIPTION}" \
        --topic="${PUBSUB_TOPIC}" \
        --ack-deadline=60 \
        --message-retention-duration=7d \
        --enable-exactly-once-delivery \
        --quiet; then
        log "Pub/Sub subscription '${SUBSCRIPTION}' created successfully"
    else
        error "Failed to create Pub/Sub subscription"
        exit 1
    fi
}

# Function to initialize Firestore
initialize_firestore() {
    log "Initializing Firestore database..."
    
    # Check if App Engine app already exists
    if ! gcloud app describe --quiet &>/dev/null; then
        info "Creating App Engine application (required for Firestore)..."
        if gcloud app create --region="${REGION}" --quiet; then
            log "App Engine application created successfully"
        else
            error "Failed to create App Engine application"
            exit 1
        fi
    else
        info "App Engine application already exists"
    fi
    
    # Initialize Firestore in Native mode
    if gcloud firestore databases create \
        --location="${REGION}" \
        --type=firestore-native \
        --quiet 2>/dev/null; then
        log "Firestore database initialized successfully"
    else
        info "Firestore database may already exist, continuing..."
    fi
    
    # Create composite indexes for analytics queries
    cat > index.yaml << 'EOF'
indexes:
- collectionGroup: analytics_metrics
  fields:
  - fieldPath: timestamp
    order: DESCENDING
  - fieldPath: metric_type
  - fieldPath: value
    order: DESCENDING

- collectionGroup: user_sessions
  fields:
  - fieldPath: user_id
  - fieldPath: session_start
    order: DESCENDING
EOF
    
    if gcloud firestore indexes composite create --file=index.yaml --quiet; then
        log "Firestore indexes created successfully"
    else
        warn "Firestore indexes creation failed, may already exist"
    fi
    
    # Clean up temporary file
    rm -f index.yaml
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..."
    
    # Create storage bucket
    if gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${STORAGE_BUCKET}"; then
        log "Storage bucket 'gs://${STORAGE_BUCKET}' created successfully"
    else
        error "Failed to create storage bucket"
        exit 1
    fi
    
    # Enable versioning
    if gsutil versioning set on "gs://${STORAGE_BUCKET}"; then
        log "Versioning enabled for storage bucket"
    else
        warn "Failed to enable versioning"
    fi
    
    # Configure lifecycle policy
    cat > lifecycle.json << 'EOF'
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
        "action": {"type": "SetStorageClass", "storageClass": "ARCHIVE"},
        "condition": {"age": 365}
      }
    ]
  }
}
EOF
    
    if gsutil lifecycle set lifecycle.json "gs://${STORAGE_BUCKET}"; then
        log "Lifecycle policy configured for storage bucket"
    else
        warn "Failed to configure lifecycle policy"
    fi
    
    # Clean up temporary file
    rm -f lifecycle.json
}

# Function to create service account
create_service_account() {
    log "Creating service account for Dataflow pipeline..."
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" --quiet &>/dev/null; then
        info "Service account already exists"
    else
        # Create service account
        if gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
            --display-name="Dataflow Analytics Pipeline" \
            --description="Service account for streaming analytics pipeline" \
            --quiet; then
            log "Service account created successfully"
        else
            error "Failed to create service account"
            exit 1
        fi
    fi
    
    # Grant necessary permissions
    local roles=(
        "roles/dataflow.worker"
        "roles/pubsub.subscriber"
        "roles/datastore.user"
        "roles/storage.admin"
        "roles/compute.instanceAdmin.v1"
    )
    
    for role in "${roles[@]}"; do
        info "Granting role ${role}..."
        if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
            --role="${role}" \
            --quiet; then
            log "Role ${role} granted successfully"
        else
            warn "Failed to grant role ${role}"
        fi
    done
}

# Function to create Apache Beam pipeline
create_beam_pipeline() {
    log "Creating Apache Beam pipeline for stream processing..."
    
    # Create directory for pipeline code
    mkdir -p dataflow-pipeline
    cd dataflow-pipeline
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
apache-beam[gcp]==2.52.0
google-cloud-firestore==2.13.1
google-cloud-storage==2.10.0
google-cloud-pubsub==3.8.0
EOF
    
    # Create streaming pipeline
    cat > streaming_analytics.py << 'EOF'
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.transforms import window
import json
import logging
from datetime import datetime
from google.cloud import firestore

class ParseEventsFn(beam.DoFn):
    def process(self, element):
        try:
            data = json.loads(element.decode('utf-8'))
            # Add processing timestamp
            data['processed_at'] = datetime.utcnow().isoformat()
            yield data
        except Exception as e:
            logging.error(f"Error parsing event: {e}")

class AggregateMetrics(beam.DoFn):
    def process(self, element):
        window_start = element[1].start.to_utc_datetime()
        window_end = element[1].end.to_utc_datetime()
        events = element[0]
        
        # Calculate metrics
        total_events = len(events)
        event_types = {}
        user_sessions = {}
        
        for event in events:
            event_type = event.get('event_type', 'unknown')
            event_types[event_type] = event_types.get(event_type, 0) + 1
            
            user_id = event.get('user_id')
            if user_id:
                if user_id not in user_sessions:
                    user_sessions[user_id] = {
                        'events': 0,
                        'first_event': event.get('timestamp'),
                        'last_event': event.get('timestamp')
                    }
                user_sessions[user_id]['events'] += 1
                user_sessions[user_id]['last_event'] = event.get('timestamp')
        
        yield {
            'window_start': window_start.isoformat(),
            'window_end': window_end.isoformat(),
            'total_events': total_events,
            'event_types': event_types,
            'unique_users': len(user_sessions),
            'user_sessions': user_sessions
        }

class WriteToFirestore(beam.DoFn):
    def __init__(self, project_id):
        self.project_id = project_id
        self.db = None
    
    def setup(self):
        self.db = firestore.Client(project=self.project_id)
    
    def process(self, element):
        try:
            # Write aggregated metrics
            doc_ref = self.db.collection('analytics_metrics').document()
            doc_ref.set({
                'timestamp': element['window_start'],
                'metric_type': 'window_summary',
                'value': element['total_events'],
                'details': element
            })
            
            # Write user session data
            for user_id, session_data in element['user_sessions'].items():
                session_ref = self.db.collection('user_sessions').document()
                session_ref.set({
                    'user_id': user_id,
                    'session_start': element['window_start'],
                    'session_events': session_data['events'],
                    'first_event_time': session_data['first_event'],
                    'last_event_time': session_data['last_event']
                })
            
            logging.info(f"Written analytics data for window: {element['window_start']}")
        except Exception as e:
            logging.error(f"Error writing to Firestore: {e}")

def run_pipeline(argv=None):
    pipeline_options = PipelineOptions(argv)
    
    with beam.Pipeline(options=pipeline_options) as pipeline:
        # Read from Pub/Sub
        events = (pipeline 
                 | 'Read from Pub/Sub' >> beam.io.ReadFromPubSub(
                     subscription=f'projects/{pipeline_options.get_all_options()["project"]}/subscriptions/{pipeline_options.get_all_options()["subscription"]}')
                 | 'Parse Events' >> beam.ParDo(ParseEventsFn()))
        
        # Process streaming events
        windowed_events = (events
                         | 'Window Events' >> beam.WindowInto(window.FixedWindows(60))  # 1-minute windows
                         | 'Group Events' >> beam.GroupBy(lambda x: 1).aggregate_field(lambda x: x, beam.combiners.ToListCombineFn(), 'events'))
        
        # Aggregate metrics
        aggregated = (windowed_events
                     | 'Aggregate Metrics' >> beam.ParDo(AggregateMetrics()))
        
        # Write to Firestore
        (aggregated
         | 'Write to Firestore' >> beam.ParDo(WriteToFirestore(pipeline_options.get_all_options()["project"])))
        
        # Archive raw events to Cloud Storage
        (events
         | 'Format for Storage' >> beam.Map(lambda x: json.dumps(x))
         | 'Write to Storage' >> beam.io.WriteToText(
             f'gs://{pipeline_options.get_all_options()["bucket"]}/raw-events/',
             file_name_suffix='.json',
             num_shards=0))

if __name__ == '__main__':
    logging.getLogger().setLevel(logging.INFO)
    run_pipeline()
EOF
    
    log "Apache Beam streaming pipeline created successfully"
    cd ..
}

# Function to install dependencies and deploy pipeline
deploy_dataflow_pipeline() {
    log "Installing dependencies and deploying Dataflow pipeline..."
    
    cd dataflow-pipeline
    
    # Install Python dependencies
    info "Installing Python dependencies..."
    if python3 -m pip install -r requirements.txt --quiet; then
        log "Dependencies installed successfully"
    else
        error "Failed to install dependencies"
        exit 1
    fi
    
    # Deploy streaming pipeline to Dataflow
    info "Deploying streaming pipeline to Dataflow..."
    if python3 streaming_analytics.py \
        --runner=DataflowRunner \
        --project="${PROJECT_ID}" \
        --region="${REGION}" \
        --temp_location="gs://${STORAGE_BUCKET}/temp" \
        --staging_location="gs://${STORAGE_BUCKET}/staging" \
        --job_name="${DATAFLOW_JOB}" \
        --subscription="${SUBSCRIPTION}" \
        --bucket="${STORAGE_BUCKET}" \
        --service_account_email="${SERVICE_ACCOUNT_EMAIL}" \
        --use_public_ips=false \
        --max_num_workers=10 \
        --streaming; then
        log "Dataflow streaming pipeline deployed successfully"
    else
        error "Failed to deploy Dataflow pipeline"
        exit 1
    fi
    
    cd ..
}

# Function to create test data generator
create_test_data_generator() {
    log "Creating test data generator..."
    
    cat > generate_events.py << 'EOF'
import json
import random
import time
from datetime import datetime
from google.cloud import pubsub_v1
import sys

def generate_event():
    event_types = ['page_view', 'click', 'purchase', 'signup', 'login']
    user_ids = [f'user_{i:04d}' for i in range(1, 1001)]
    
    return {
        'event_id': f'evt_{int(time.time() * 1000)}_{random.randint(1000, 9999)}',
        'event_type': random.choice(event_types),
        'user_id': random.choice(user_ids),
        'timestamp': datetime.utcnow().isoformat(),
        'properties': {
            'page': random.choice(['/home', '/products', '/checkout', '/profile']),
            'device': random.choice(['mobile', 'desktop', 'tablet']),
            'value': random.uniform(10, 1000) if random.random() > 0.7 else None
        }
    }

def publish_events(project_id, topic_name, num_events=100):
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(project_id, topic_name)
    
    for i in range(num_events):
        event = generate_event()
        data = json.dumps(event).encode('utf-8')
        
        future = publisher.publish(topic_path, data)
        print(f'Published event {i+1}: {future.result()}')
        
        # Add some randomness to timing
        time.sleep(random.uniform(0.1, 0.5))

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print('Usage: python generate_events.py PROJECT_ID TOPIC_NAME NUM_EVENTS')
        sys.exit(1)
    
    project_id = sys.argv[1]
    topic_name = sys.argv[2]
    num_events = int(sys.argv[3])
    
    publish_events(project_id, topic_name, num_events)
EOF
    
    log "Test data generator created successfully"
}

# Function to generate sample events
generate_sample_events() {
    log "Generating sample events for testing..."
    
    # Install required library
    python3 -m pip install google-cloud-pubsub --quiet
    
    # Generate test events
    if python3 generate_events.py "${PROJECT_ID}" "${PUBSUB_TOPIC}" 50; then
        log "Sample events generated and published successfully"
    else
        warn "Failed to generate sample events, but deployment continues"
    fi
}

# Function to create dashboard query examples
create_dashboard_queries() {
    log "Creating dashboard query examples..."
    
    cat > dashboard_queries.py << 'EOF'
from google.cloud import firestore
from datetime import datetime, timedelta
import json

def setup_firestore_client(project_id):
    return firestore.Client(project=project_id)

def get_recent_metrics(db, hours=1):
    """Get metrics from the last N hours"""
    cutoff_time = datetime.utcnow() - timedelta(hours=hours)
    
    metrics_ref = db.collection('analytics_metrics')
    query = metrics_ref.where('timestamp', '>=', cutoff_time.isoformat()).order_by('timestamp', direction=firestore.Query.DESCENDING)
    
    metrics = []
    for doc in query.stream():
        metrics.append(doc.to_dict())
    
    return metrics

def get_top_users_by_activity(db, limit=10):
    """Get most active users by session count"""
    sessions_ref = db.collection('user_sessions')
    query = sessions_ref.order_by('session_events', direction=firestore.Query.DESCENDING).limit(limit)
    
    top_users = []
    for doc in query.stream():
        top_users.append(doc.to_dict())
    
    return top_users

def get_real_time_summary(db):
    """Get current analytics summary"""
    metrics_ref = db.collection('analytics_metrics')
    recent_query = metrics_ref.order_by('timestamp', direction=firestore.Query.DESCENDING).limit(5)
    
    total_events = 0
    unique_users = 0
    
    for doc in recent_query.stream():
        data = doc.to_dict()
        if 'details' in data:
            total_events += data['details'].get('total_events', 0)
            unique_users += data['details'].get('unique_users', 0)
    
    return {
        'total_events_last_5_windows': total_events,
        'unique_users_last_5_windows': unique_users,
        'last_updated': datetime.utcnow().isoformat()
    }

if __name__ == '__main__':
    import sys
    if len(sys.argv) != 2:
        print('Usage: python dashboard_queries.py PROJECT_ID')
        sys.exit(1)
    
    project_id = sys.argv[1]
    db = setup_firestore_client(project_id)
    
    print("=== Recent Metrics ===")
    metrics = get_recent_metrics(db)
    print(json.dumps(metrics[:3], indent=2, default=str))
    
    print("\n=== Real-time Summary ===")
    summary = get_real_time_summary(db)
    print(json.dumps(summary, indent=2))
    
    print("\n=== Top Active Users ===")
    top_users = get_top_users_by_activity(db, 5)
    print(json.dumps(top_users, indent=2, default=str))
EOF
    
    log "Dashboard query examples created successfully"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check Dataflow pipeline status
    info "Checking Dataflow pipeline status..."
    if gcloud dataflow jobs list \
        --filter="name:${DATAFLOW_JOB}" \
        --format="table(name,state,createTime)" \
        --limit=1; then
        log "Dataflow pipeline status retrieved"
    else
        warn "Could not retrieve Dataflow pipeline status"
    fi
    
    # Check Pub/Sub resources
    info "Checking Pub/Sub resources..."
    if gcloud pubsub topics describe "${PUBSUB_TOPIC}" --quiet; then
        log "Pub/Sub topic verified"
    else
        warn "Pub/Sub topic verification failed"
    fi
    
    if gcloud pubsub subscriptions describe "${SUBSCRIPTION}" --quiet; then
        log "Pub/Sub subscription verified"
    else
        warn "Pub/Sub subscription verification failed"
    fi
    
    # Check Cloud Storage bucket
    info "Checking Cloud Storage bucket..."
    if gsutil ls -b "gs://${STORAGE_BUCKET}" &>/dev/null; then
        log "Cloud Storage bucket verified"
    else
        warn "Cloud Storage bucket verification failed"
    fi
    
    # Check service account
    info "Checking service account..."
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" --quiet &>/dev/null; then
        log "Service account verified"
    else
        warn "Service account verification failed"
    fi
    
    log "Deployment verification completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Pub/Sub Topic: ${PUBSUB_TOPIC}"
    echo "Pub/Sub Subscription: ${SUBSCRIPTION}"
    echo "Dataflow Job: ${DATAFLOW_JOB}"
    echo "Storage Bucket: gs://${STORAGE_BUCKET}"
    echo "Service Account: ${SERVICE_ACCOUNT_EMAIL}"
    echo ""
    echo "Files created:"
    echo "- deployment_state.env (contains all resource names)"
    echo "- dataflow-pipeline/ (Apache Beam pipeline code)"
    echo "- generate_events.py (test data generator)"
    echo "- dashboard_queries.py (query examples)"
    echo ""
    echo "Next steps:"
    echo "1. Wait 2-3 minutes for the Dataflow pipeline to start processing"
    echo "2. Generate test events: python3 generate_events.py ${PROJECT_ID} ${PUBSUB_TOPIC} 100"
    echo "3. Query analytics data: python3 dashboard_queries.py ${PROJECT_ID}"
    echo "4. Monitor the pipeline in the Google Cloud Console"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting deployment of Real-Time Analytics with Cloud Dataflow and Firestore"
    
    check_prerequisites
    setup_environment
    configure_gcloud
    enable_apis
    create_pubsub_resources
    initialize_firestore
    create_storage_bucket
    create_service_account
    create_beam_pipeline
    deploy_dataflow_pipeline
    create_test_data_generator
    generate_sample_events
    create_dashboard_queries
    verify_deployment
    display_summary
    
    log "Deployment completed successfully!"
    log "Check the Google Cloud Console to monitor your streaming analytics pipeline."
}

# Error handling
trap 'error "Deployment failed. Check the logs above for details."; exit 1' ERR

# Run main function
main "$@"