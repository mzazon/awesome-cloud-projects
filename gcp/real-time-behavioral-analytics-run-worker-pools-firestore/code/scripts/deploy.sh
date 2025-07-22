#!/bin/bash

# Real-Time Behavioral Analytics with Cloud Run Worker Pools and Cloud Firestore
# Deployment Script for GCP
# 
# This script deploys a complete behavioral analytics solution using:
# - Cloud Run Worker Pools for continuous background processing
# - Cloud Firestore for fast analytics queries
# - Pub/Sub for reliable event ingestion
# - Cloud Monitoring for observability

set -euo pipefail

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        echo "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command_exists docker; then
        log_error "Docker is not installed. Please install Docker first."
        echo "Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found."
        echo "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if Python 3 is available
    if ! command_exists python3; then
        log_error "Python 3 is not installed. Please install Python 3 first."
        exit 1
    fi
    
    log_success "All prerequisites met!"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get current project ID or prompt user
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [[ -z "$CURRENT_PROJECT" ]]; then
        read -p "Enter your Google Cloud Project ID: " PROJECT_ID
        gcloud config set project "$PROJECT_ID"
    else
        PROJECT_ID="$CURRENT_PROJECT"
        log_info "Using current project: $PROJECT_ID"
    fi
    
    # Set default region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names with unique suffixes
    export PUBSUB_TOPIC="user-events-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_NAME="analytics-processor-${RANDOM_SUFFIX}"
    export WORKER_POOL_NAME="behavioral-processor-${RANDOM_SUFFIX}"
    export FIRESTORE_DATABASE="behavioral-analytics"
    export SERVICE_ACCOUNT_NAME="analytics-processor-${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    export ARTIFACT_REPO="behavioral-analytics"
    export IMAGE_TAG="latest"
    export IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REPO}/processor:${IMAGE_TAG}"
    
    # Configure gcloud defaults
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "Environment configured for project: $PROJECT_ID"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "run.googleapis.com"
        "firestore.googleapis.com"
        "pubsub.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
        "iam.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log_success "✓ $api enabled"
        else
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    log_info "Waiting for APIs to be fully available..."
    sleep 30
    
    log_success "All APIs enabled successfully!"
}

# Function to create Firestore database
create_firestore_database() {
    log_info "Creating Firestore database..."
    
    # Check if database already exists
    if gcloud firestore databases list --format="value(name)" | grep -q "$FIRESTORE_DATABASE"; then
        log_warning "Firestore database '$FIRESTORE_DATABASE' already exists"
        return 0
    fi
    
    # Create Firestore database in Native mode
    if gcloud firestore databases create \
        --database="$FIRESTORE_DATABASE" \
        --location="$REGION" \
        --type=firestore-native \
        --quiet; then
        log_success "✓ Firestore database '$FIRESTORE_DATABASE' created"
    else
        log_error "Failed to create Firestore database"
        exit 1
    fi
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topic and subscription..."
    
    # Create Pub/Sub topic
    if gcloud pubsub topics describe "$PUBSUB_TOPIC" >/dev/null 2>&1; then
        log_warning "Pub/Sub topic '$PUBSUB_TOPIC' already exists"
    else
        if gcloud pubsub topics create "$PUBSUB_TOPIC"; then
            log_success "✓ Pub/Sub topic '$PUBSUB_TOPIC' created"
        else
            log_error "Failed to create Pub/Sub topic"
            exit 1
        fi
    fi
    
    # Create Pub/Sub subscription
    if gcloud pubsub subscriptions describe "$SUBSCRIPTION_NAME" >/dev/null 2>&1; then
        log_warning "Pub/Sub subscription '$SUBSCRIPTION_NAME' already exists"
    else
        if gcloud pubsub subscriptions create "$SUBSCRIPTION_NAME" \
            --topic="$PUBSUB_TOPIC" \
            --ack-deadline=60 \
            --message-retention-duration=7d \
            --enable-message-ordering; then
            log_success "✓ Pub/Sub subscription '$SUBSCRIPTION_NAME' created"
        else
            log_error "Failed to create Pub/Sub subscription"
            exit 1
        fi
    fi
}

# Function to create service account
create_service_account() {
    log_info "Creating service account and setting permissions..."
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT" >/dev/null 2>&1; then
        log_warning "Service account '$SERVICE_ACCOUNT' already exists"
    else
        # Create service account
        if gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
            --display-name="Behavioral Analytics Processor" \
            --description="Service account for Cloud Run worker pool processing behavioral events"; then
            log_success "✓ Service account '$SERVICE_ACCOUNT' created"
        else
            log_error "Failed to create service account"
            exit 1
        fi
    fi
    
    # Grant necessary IAM roles
    local roles=(
        "roles/pubsub.subscriber"
        "roles/datastore.user"
        "roles/monitoring.metricWriter"
    )
    
    for role in "${roles[@]}"; do
        log_info "Granting role $role to service account..."
        if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$SERVICE_ACCOUNT" \
            --role="$role" \
            --quiet; then
            log_success "✓ Role $role granted"
        else
            log_error "Failed to grant role $role"
            exit 1
        fi
    done
}

# Function to create Artifact Registry repository
create_artifact_registry() {
    log_info "Creating Artifact Registry repository..."
    
    # Check if repository already exists
    if gcloud artifacts repositories describe "$ARTIFACT_REPO" \
        --location="$REGION" >/dev/null 2>&1; then
        log_warning "Artifact Registry repository '$ARTIFACT_REPO' already exists"
    else
        if gcloud artifacts repositories create "$ARTIFACT_REPO" \
            --repository-format=docker \
            --location="$REGION" \
            --description="Container images for behavioral analytics system"; then
            log_success "✓ Artifact Registry repository '$ARTIFACT_REPO' created"
        else
            log_error "Failed to create Artifact Registry repository"
            exit 1
        fi
    fi
    
    # Configure Docker authentication
    log_info "Configuring Docker authentication..."
    if gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet; then
        log_success "✓ Docker authentication configured"
    else
        log_error "Failed to configure Docker authentication"
        exit 1
    fi
}

# Function to build and push container image
build_and_push_image() {
    log_info "Building and pushing container image..."
    
    # Create temporary directory for application code
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    log_info "Creating application code in temporary directory: $temp_dir"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-pubsub==2.18.4
google-cloud-firestore==2.13.1
google-cloud-monitoring==2.16.0
python-json-logger==2.0.7
gunicorn==21.2.0
EOF

    # Create main application file
    cat > main.py << 'EOF'
import json
import logging
import os
import time
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor
from google.cloud import pubsub_v1, firestore, monitoring_v3
from pythonjsonlogger import jsonlogger

# Configure structured logging
logHandler = logging.StreamHandler()
formatter = jsonlogger.JsonFormatter()
logHandler.setFormatter(formatter)
logger = logging.getLogger()
logger.addHandler(logHandler)
logger.setLevel(logging.INFO)

class BehavioralAnalyticsProcessor:
    def __init__(self):
        self.project_id = os.environ['GOOGLE_CLOUD_PROJECT']
        self.subscription_path = os.environ['PUBSUB_SUBSCRIPTION']
        self.firestore_client = firestore.Client(database=os.environ.get('FIRESTORE_DATABASE', '(default)'))
        self.monitoring_client = monitoring_v3.MetricServiceClient()
        self.subscriber = pubsub_v1.SubscriberClient()
        
        # Initialize collections
        self.events_collection = self.firestore_client.collection('user_events')
        self.analytics_collection = self.firestore_client.collection('analytics_aggregates')
        
        logger.info("Behavioral Analytics Processor initialized")
    
    def process_event(self, message):
        """Process individual user behavioral event"""
        try:
            # Parse event data
            event_data = json.loads(message.data.decode('utf-8'))
            
            # Enrich event with processing timestamp
            event_data['processed_at'] = firestore.SERVER_TIMESTAMP
            event_data['processing_latency'] = time.time() - event_data.get('timestamp', time.time())
            
            # Store raw event for detailed analysis
            event_doc_ref = self.events_collection.document()
            event_doc_ref.set(event_data)
            
            # Update real-time aggregates
            self.update_analytics_aggregates(event_data)
            
            # Send custom metrics
            self.send_metrics(event_data)
            
            message.ack()
            logger.info(f"Successfully processed event: {event_data.get('event_type', 'unknown')}")
            
        except Exception as e:
            logger.error(f"Error processing event: {str(e)}")
            message.nack()
    
    def update_analytics_aggregates(self, event_data):
        """Update real-time analytics aggregates in Firestore"""
        user_id = event_data.get('user_id')
        event_type = event_data.get('event_type')
        timestamp = datetime.fromtimestamp(event_data.get('timestamp', time.time()))
        
        # Create time-based aggregation keys
        hourly_key = timestamp.strftime('%Y-%m-%d-%H')
        daily_key = timestamp.strftime('%Y-%m-%d')
        
        # Update user-specific aggregates
        if user_id:
            user_doc_ref = self.analytics_collection.document(f"user_{user_id}")
            user_doc_ref.set({
                'last_activity': firestore.SERVER_TIMESTAMP,
                'total_events': firestore.Increment(1),
                f'events_by_type.{event_type}': firestore.Increment(1)
            }, merge=True)
        
        # Update global hourly aggregates
        hourly_doc_ref = self.analytics_collection.document(f"hourly_{hourly_key}")
        hourly_doc_ref.set({
            'period': hourly_key,
            'total_events': firestore.Increment(1),
            f'events_by_type.{event_type}': firestore.Increment(1),
            'last_updated': firestore.SERVER_TIMESTAMP
        }, merge=True)
        
        # Update global daily aggregates
        daily_doc_ref = self.analytics_collection.document(f"daily_{daily_key}")
        daily_doc_ref.set({
            'period': daily_key,
            'total_events': firestore.Increment(1),
            f'events_by_type.{event_type}': firestore.Increment(1),
            'last_updated': firestore.SERVER_TIMESTAMP
        }, merge=True)
    
    def send_metrics(self, event_data):
        """Send custom metrics to Cloud Monitoring"""
        try:
            series = monitoring_v3.TimeSeries()
            series.metric.type = 'custom.googleapis.com/behavioral_analytics/events_processed'
            series.metric.labels['event_type'] = event_data.get('event_type', 'unknown')
            series.resource.type = 'cloud_run_revision'
            series.resource.labels['service_name'] = os.environ.get('K_SERVICE', 'behavioral-processor')
            series.resource.labels['revision_name'] = os.environ.get('K_REVISION', 'unknown')
            series.resource.labels['location'] = os.environ.get('GOOGLE_CLOUD_REGION', 'us-central1')
            
            point = monitoring_v3.Point()
            point.value.int64_value = 1
            point.interval.end_time.seconds = int(time.time())
            series.points = [point]
            
            project_name = f"projects/{self.project_id}"
            self.monitoring_client.create_time_series(name=project_name, time_series=[series])
            
        except Exception as e:
            logger.warning(f"Failed to send metrics: {str(e)}")
    
    def run(self):
        """Main processing loop for the worker pool"""
        logger.info("Starting behavioral analytics processing...")
        
        # Configure subscriber settings for optimal performance
        flow_control = pubsub_v1.types.FlowControl(max_messages=100, max_bytes=10*1024*1024)
        
        # Use ThreadPoolExecutor for concurrent message processing
        with ThreadPoolExecutor(max_workers=10) as executor:
            streaming_pull_future = self.subscriber.subscribe(
                self.subscription_path,
                callback=self.process_event,
                flow_control=flow_control
            )
            
            logger.info(f"Listening for messages on {self.subscription_path}")
            
            try:
                streaming_pull_future.result()
            except KeyboardInterrupt:
                streaming_pull_future.cancel()
                logger.info("Processing stopped")

if __name__ == '__main__':
    processor = BehavioralAnalyticsProcessor()
    processor.run()
EOF

    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# Run the application
CMD ["python", "main.py"]
EOF

    # Build and push the image using Cloud Build
    log_info "Building container image with Cloud Build..."
    if gcloud builds submit . --tag="$IMAGE_URI" --quiet; then
        log_success "✓ Container image built and pushed: $IMAGE_URI"
    else
        log_error "Failed to build and push container image"
        cd - >/dev/null
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Clean up temporary directory
    cd - >/dev/null
    rm -rf "$temp_dir"
}

# Function to deploy Cloud Run Worker Pool
deploy_worker_pool() {
    log_info "Deploying Cloud Run Worker Pool..."
    
    # Check if worker pool already exists
    if gcloud run workers describe "$WORKER_POOL_NAME" --region="$REGION" >/dev/null 2>&1; then
        log_warning "Cloud Run Worker Pool '$WORKER_POOL_NAME' already exists, updating..."
        action="replace"
    else
        action="deploy"
    fi
    
    # Deploy or update the worker pool
    if gcloud run workers "$action" "$WORKER_POOL_NAME" \
        --image="$IMAGE_URI" \
        --region="$REGION" \
        --service-account="$SERVICE_ACCOUNT" \
        --set-env-vars="PUBSUB_SUBSCRIPTION=projects/${PROJECT_ID}/subscriptions/${SUBSCRIPTION_NAME}" \
        --set-env-vars="FIRESTORE_DATABASE=${FIRESTORE_DATABASE}" \
        --memory=1Gi \
        --cpu=1 \
        --min-instances=1 \
        --max-instances=10 \
        --concurrency=1000 \
        --quiet; then
        log_success "✓ Cloud Run Worker Pool '$WORKER_POOL_NAME' deployed successfully"
    else
        log_error "Failed to deploy Cloud Run Worker Pool"
        exit 1
    fi
    
    # Wait for deployment to be ready
    log_info "Waiting for worker pool to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        local status
        status=$(gcloud run workers describe "$WORKER_POOL_NAME" \
            --region="$REGION" \
            --format="value(status.conditions[0].status)" 2>/dev/null || echo "Unknown")
        
        if [[ "$status" == "True" ]]; then
            log_success "✓ Worker pool is ready and running"
            break
        else
            log_info "Worker pool status: $status (attempt $((attempt + 1))/$max_attempts)"
            sleep 10
            ((attempt++))
        fi
    done
    
    if [[ $attempt -ge $max_attempts ]]; then
        log_error "Worker pool failed to become ready within expected time"
        exit 1
    fi
}

# Function to create Firestore indexes
create_firestore_indexes() {
    log_info "Creating Firestore composite indexes..."
    
    # Create index for user_events by user_id and timestamp
    log_info "Creating index for user events by user_id and timestamp..."
    if gcloud firestore indexes composite create \
        --collection-group=user_events \
        --field-config=field-path=user_id,order=ascending \
        --field-config=field-path=timestamp,order=descending \
        --database="$FIRESTORE_DATABASE" \
        --quiet 2>/dev/null; then
        log_success "✓ User events index created"
    else
        log_warning "User events index may already exist or failed to create"
    fi
    
    # Create index for user_events by event_type and timestamp
    log_info "Creating index for user events by event_type and timestamp..."
    if gcloud firestore indexes composite create \
        --collection-group=user_events \
        --field-config=field-path=event_type,order=ascending \
        --field-config=field-path=timestamp,order=descending \
        --database="$FIRESTORE_DATABASE" \
        --quiet 2>/dev/null; then
        log_success "✓ Event type index created"
    else
        log_warning "Event type index may already exist or failed to create"
    fi
    
    log_info "Firestore indexes are being built in the background..."
    log_info "It may take several minutes for indexes to become available for queries."
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    log_info "Creating Cloud Monitoring dashboard..."
    
    # Create dashboard configuration
    local dashboard_config
    dashboard_config=$(mktemp)
    
    cat > "$dashboard_config" << EOF
{
  "displayName": "Behavioral Analytics Dashboard - ${WORKER_POOL_NAME}",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Events Processed Per Minute",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\\"custom.googleapis.com/behavioral_analytics/events_processed\\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Worker Pool Instance Count",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\\"cloud_run_revision\\" AND metric.type=\\"run.googleapis.com/container/instance_count\\" AND resource.labels.service_name=\\"${WORKER_POOL_NAME}\\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        }
      },
      {
        "width": 12,
        "height": 4,
        "yPos": 4,
        "widget": {
          "title": "Pub/Sub Subscription Metrics",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\\"pubsub_subscription\\" AND resource.labels.subscription_id=\\"${SUBSCRIPTION_NAME}\\" AND metric.type=\\"pubsub.googleapis.com/subscription/num_undelivered_messages\\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        }
      }
    ]
  }
}
EOF
    
    # Create the dashboard
    if gcloud monitoring dashboards create --config-from-file="$dashboard_config" >/dev/null 2>&1; then
        log_success "✓ Monitoring dashboard created"
    else
        log_warning "Failed to create monitoring dashboard (may already exist)"
    fi
    
    rm -f "$dashboard_config"
}

# Function to create sample event generator
create_event_generator() {
    log_info "Creating sample event generator..."
    
    local generator_file="generate_events.py"
    
    cat > "$generator_file" << EOF
#!/usr/bin/env python3
"""
Sample Event Generator for Behavioral Analytics System
This script generates realistic user behavioral events for testing.
"""

import json
import random
import time
import sys
from datetime import datetime
from google.cloud import pubsub_v1

class EventGenerator:
    def __init__(self, project_id, topic_name):
        self.publisher = pubsub_v1.PublisherClient()
        self.topic_path = self.publisher.topic_path(project_id, topic_name)
        
        self.event_types = ['page_view', 'button_click', 'purchase', 'search', 'signup', 'login']
        self.user_ids = [f"user_{i}" for i in range(1, 101)]  # 100 test users
        
    def generate_event(self):
        """Generate a realistic user behavioral event"""
        event = {
            'event_id': f"evt_{random.randint(100000, 999999)}",
            'user_id': random.choice(self.user_ids),
            'event_type': random.choice(self.event_types),
            'timestamp': time.time(),
            'session_id': f"sess_{random.randint(1000, 9999)}",
            'properties': {
                'page_url': f"/page/{random.randint(1, 50)}",
                'referrer': random.choice(['google.com', 'direct', 'facebook.com', 'twitter.com']),
                'device_type': random.choice(['desktop', 'mobile', 'tablet']),
                'user_agent': 'BehavioralAnalytics/1.0'
            }
        }
        
        # Add event-specific properties
        if event['event_type'] == 'purchase':
            event['properties']['amount'] = round(random.uniform(10.0, 500.0), 2)
            event['properties']['currency'] = 'USD'
        elif event['event_type'] == 'search':
            event['properties']['query'] = f"search_term_{random.randint(1, 100)}"
        
        return event
    
    def send_events(self, count=50, interval=0.5):
        """Send multiple events to Pub/Sub topic"""
        print(f"Generating {count} events to topic: {self.topic_path}")
        
        try:
            for i in range(count):
                event = self.generate_event()
                event_json = json.dumps(event)
                
                # Publish event to Pub/Sub
                future = self.publisher.publish(self.topic_path, event_json.encode('utf-8'))
                
                if i % 10 == 0:
                    print(f"Sent {i+1}/{count} events")
                
                time.sleep(interval)
            
            print(f"✅ Successfully sent {count} events")
            
        except Exception as e:
            print(f"❌ Error sending events: {str(e)}")
            sys.exit(1)

if __name__ == '__main__':
    import os
    
    project_id = "${PROJECT_ID}"
    topic_name = "${PUBSUB_TOPIC}"
    
    if len(sys.argv) > 1:
        try:
            event_count = int(sys.argv[1])
        except ValueError:
            print("Usage: python3 generate_events.py [event_count]")
            sys.exit(1)
    else:
        event_count = 50
    
    generator = EventGenerator(project_id, topic_name)
    generator.send_events(count=event_count, interval=0.5)
EOF
    
    chmod +x "$generator_file"
    log_success "✓ Event generator created: $generator_file"
}

# Function to run deployment validation
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check worker pool status
    local worker_status
    worker_status=$(gcloud run workers describe "$WORKER_POOL_NAME" \
        --region="$REGION" \
        --format="value(status.conditions[0].status)" 2>/dev/null || echo "Unknown")
    
    if [[ "$worker_status" == "True" ]]; then
        log_success "✓ Worker pool is running"
    else
        log_error "✗ Worker pool is not running properly (status: $worker_status)"
        return 1
    fi
    
    # Check Pub/Sub resources
    if gcloud pubsub topics describe "$PUBSUB_TOPIC" >/dev/null 2>&1; then
        log_success "✓ Pub/Sub topic exists"
    else
        log_error "✗ Pub/Sub topic not found"
        return 1
    fi
    
    if gcloud pubsub subscriptions describe "$SUBSCRIPTION_NAME" >/dev/null 2>&1; then
        log_success "✓ Pub/Sub subscription exists"
    else
        log_error "✗ Pub/Sub subscription not found"
        return 1
    fi
    
    # Check Firestore database
    if gcloud firestore databases list --format="value(name)" | grep -q "$FIRESTORE_DATABASE"; then
        log_success "✓ Firestore database exists"
    else
        log_error "✗ Firestore database not found"
        return 1
    fi
    
    # Check service account
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT" >/dev/null 2>&1; then
        log_success "✓ Service account exists"
    else
        log_error "✗ Service account not found"
        return 1
    fi
    
    log_success "All validation checks passed!"
}

# Function to display deployment summary
display_summary() {
    log_info "=== DEPLOYMENT SUMMARY ==="
    echo ""
    echo "🚀 Behavioral Analytics System Deployed Successfully!"
    echo ""
    echo "📋 Resource Details:"
    echo "   Project ID: $PROJECT_ID"
    echo "   Region: $REGION"
    echo "   Worker Pool: $WORKER_POOL_NAME"
    echo "   Pub/Sub Topic: $PUBSUB_TOPIC"
    echo "   Pub/Sub Subscription: $SUBSCRIPTION_NAME"
    echo "   Firestore Database: $FIRESTORE_DATABASE"
    echo "   Service Account: $SERVICE_ACCOUNT"
    echo "   Container Image: $IMAGE_URI"
    echo ""
    echo "🔧 Next Steps:"
    echo "   1. Generate test events: python3 generate_events.py [event_count]"
    echo "   2. View worker logs: gcloud logs read 'resource.type=cloud_run_revision AND resource.labels.service_name=$WORKER_POOL_NAME' --limit=20"
    echo "   3. Monitor in Console: https://console.cloud.google.com/run/detail/$REGION/$WORKER_POOL_NAME"
    echo "   4. View Firestore data: https://console.cloud.google.com/firestore/databases/$FIRESTORE_DATABASE/data"
    echo ""
    echo "📊 Monitoring:"
    echo "   Cloud Monitoring: https://console.cloud.google.com/monitoring"
    echo "   Custom metrics: custom.googleapis.com/behavioral_analytics/events_processed"
    echo ""
    echo "🧹 Cleanup:"
    echo "   Run: ./destroy.sh to remove all resources"
    echo ""
}

# Main execution function
main() {
    log_info "Starting deployment of Real-Time Behavioral Analytics System..."
    echo ""
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    enable_apis
    create_firestore_database
    create_pubsub_resources
    create_service_account
    create_artifact_registry
    build_and_push_image
    deploy_worker_pool
    create_firestore_indexes
    create_monitoring_dashboard
    create_event_generator
    validate_deployment
    
    echo ""
    display_summary
    
    log_success "Deployment completed successfully! 🎉"
}

# Run main function
main "$@"