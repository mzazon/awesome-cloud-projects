#!/bin/bash

# Workforce Analytics with Workspace Events API and Cloud Run Worker Pools - Deployment Script
# This script deploys the complete infrastructure for workforce analytics processing

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/workforce-analytics-deploy-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=${DRY_RUN:-false}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        DEBUG)
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handler
error_exit() {
    log ERROR "Deployment failed: $1"
    log ERROR "Check log file: $LOG_FILE"
    exit 1
}

# Cleanup on exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log ERROR "Deployment failed with exit code: $exit_code"
        log INFO "Log file available at: $LOG_FILE"
    fi
}
trap cleanup EXIT

# Display banner
echo -e "${BLUE}"
echo "=================================================="
echo "   Workforce Analytics Deployment Script"
echo "   Google Cloud Platform Infrastructure"
echo "=================================================="
echo -e "${NC}"

# Check if dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
    log INFO "Running in DRY RUN mode - no resources will be created"
fi

# Prerequisites check function
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi
    
    # Check gcloud version
    local gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log INFO "gcloud CLI version: $gcloud_version"
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 > /dev/null; then
        error_exit "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi
    
    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1)
    log INFO "Active account: $active_account"
    
    # Check other required tools
    for tool in bq gsutil openssl; do
        if ! command -v "$tool" &> /dev/null; then
            error_exit "$tool is not installed or not in PATH"
        fi
    done
    
    # Check if project is set
    local current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$current_project" ]]; then
        error_exit "No active GCP project set. Run 'gcloud config set project PROJECT_ID' first."
    fi
    
    log INFO "Prerequisites check completed successfully"
}

# Set environment variables
set_environment_variables() {
    log INFO "Setting up environment variables..."
    
    # Set project variables
    export PROJECT_ID="${PROJECT_ID:-workforce-analytics-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export DATASET_NAME="workforce_analytics_${RANDOM_SUFFIX}"
    export WORKER_POOL_NAME="analytics-processor-${RANDOM_SUFFIX}"
    export TOPIC_NAME="workspace-events-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_NAME="events-processor-${RANDOM_SUFFIX}"
    export BUCKET_NAME="workforce-data-${PROJECT_ID}-${RANDOM_SUFFIX}"
    
    # Save environment to file for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
DATASET_NAME=${DATASET_NAME}
WORKER_POOL_NAME=${WORKER_POOL_NAME}
TOPIC_NAME=${TOPIC_NAME}
SUBSCRIPTION_NAME=${SUBSCRIPTION_NAME}
BUCKET_NAME=${BUCKET_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log INFO "Environment variables configured:"
    log INFO "  PROJECT_ID: $PROJECT_ID"
    log INFO "  REGION: $REGION"
    log INFO "  DATASET_NAME: $DATASET_NAME"
    log INFO "  WORKER_POOL_NAME: $WORKER_POOL_NAME"
    log INFO "  Environment saved to: ${SCRIPT_DIR}/.env"
}

# Configure GCP project
configure_project() {
    log INFO "Configuring GCP project settings..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Set default project and region
        gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
        gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
        gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"
        
        log INFO "Project configuration completed"
    else
        log INFO "[DRY RUN] Would configure project: $PROJECT_ID"
    fi
}

# Enable required APIs
enable_apis() {
    log INFO "Enabling required Google Cloud APIs..."
    
    local apis=(
        "run.googleapis.com"
        "pubsub.googleapis.com"
        "bigquery.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
        "workspaceevents.googleapis.com"
        "storage.googleapis.com"
    )
    
    if [[ "$DRY_RUN" != "true" ]]; then
        for api in "${apis[@]}"; do
            log INFO "Enabling API: $api"
            if ! gcloud services enable "$api" --quiet; then
                error_exit "Failed to enable API: $api"
            fi
        done
        
        # Wait for APIs to be fully enabled
        log INFO "Waiting for APIs to be fully enabled..."
        sleep 30
        
        log INFO "All required APIs enabled successfully"
    else
        log INFO "[DRY RUN] Would enable APIs: ${apis[*]}"
    fi
}

# Create BigQuery dataset and tables
create_bigquery_resources() {
    log INFO "Creating BigQuery dataset and tables..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Create BigQuery dataset
        if ! bq mk --location="${REGION}" \
            --description="Workforce Analytics Data Warehouse" \
            "${PROJECT_ID}:${DATASET_NAME}"; then
            error_exit "Failed to create BigQuery dataset"
        fi
        
        # Create meeting events table
        if ! bq mk --table \
            "${PROJECT_ID}:${DATASET_NAME}.meeting_events" \
            event_id:STRING,event_type:STRING,meeting_id:STRING,organizer_email:STRING,participant_count:INTEGER,start_time:TIMESTAMP,end_time:TIMESTAMP,duration_minutes:INTEGER,meeting_title:STRING,calendar_id:STRING,created_time:TIMESTAMP; then
            error_exit "Failed to create meeting_events table"
        fi
        
        # Create file events table
        if ! bq mk --table \
            "${PROJECT_ID}:${DATASET_NAME}.file_events" \
            event_id:STRING,event_type:STRING,file_id:STRING,user_email:STRING,file_name:STRING,file_type:STRING,action:STRING,shared_with_count:INTEGER,folder_id:STRING,drive_id:STRING,created_time:TIMESTAMP; then
            error_exit "Failed to create file_events table"
        fi
        
        log INFO "BigQuery dataset and tables created successfully"
    else
        log INFO "[DRY RUN] Would create BigQuery dataset: $DATASET_NAME"
        log INFO "[DRY RUN] Would create tables: meeting_events, file_events"
    fi
}

# Create Pub/Sub resources
create_pubsub_resources() {
    log INFO "Creating Cloud Pub/Sub topic and subscription..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Create Pub/Sub topic
        if ! gcloud pubsub topics create "${TOPIC_NAME}" \
            --message-retention-duration=7d \
            --message-storage-policy-allowed-regions="${REGION}"; then
            error_exit "Failed to create Pub/Sub topic"
        fi
        
        # Create subscription
        if ! gcloud pubsub subscriptions create "${SUBSCRIPTION_NAME}" \
            --topic="${TOPIC_NAME}" \
            --ack-deadline=600 \
            --message-retention-duration=7d \
            --enable-message-ordering; then
            error_exit "Failed to create Pub/Sub subscription"
        fi
        
        # Set IAM permissions
        local service_account="${PROJECT_ID}@appspot.gserviceaccount.com"
        if ! gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account}" \
            --role="roles/pubsub.subscriber"; then
            error_exit "Failed to set Pub/Sub IAM permissions"
        fi
        
        log INFO "Pub/Sub resources created successfully"
    else
        log INFO "[DRY RUN] Would create Pub/Sub topic: $TOPIC_NAME"
        log INFO "[DRY RUN] Would create subscription: $SUBSCRIPTION_NAME"
    fi
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log INFO "Creating Cloud Storage bucket..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Create bucket
        if ! gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}"; then
            error_exit "Failed to create Cloud Storage bucket"
        fi
        
        # Enable versioning
        if ! gsutil versioning set on "gs://${BUCKET_NAME}"; then
            error_exit "Failed to enable bucket versioning"
        fi
        
        # Create directory structure
        echo "Creating storage structure..." | gsutil cp - "gs://${BUCKET_NAME}/code/"
        echo "Creating temp directory..." | gsutil cp - "gs://${BUCKET_NAME}/temp/"
        echo "Creating archive directory..." | gsutil cp - "gs://${BUCKET_NAME}/archive/"
        
        log INFO "Cloud Storage bucket created successfully"
    else
        log INFO "[DRY RUN] Would create storage bucket: $BUCKET_NAME"
    fi
}

# Create application code
create_application_code() {
    log INFO "Creating event processing application code..."
    
    local app_dir="${SCRIPT_DIR}/../workspace-analytics-app"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Create application directory
        mkdir -p "$app_dir"
        cd "$app_dir"
        
        # Create main application file
        cat > main.py << 'EOF'
import json
import os
import logging
from datetime import datetime, timezone
from google.cloud import pubsub_v1
from google.cloud import bigquery
from google.cloud import monitoring_v3
from concurrent.futures import ThreadPoolExecutor
import time

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class WorkspaceEventProcessor:
    def __init__(self):
        self.project_id = os.environ['PROJECT_ID']
        self.subscription_name = os.environ['SUBSCRIPTION_NAME']
        self.dataset_name = os.environ['DATASET_NAME']
        
        # Initialize clients
        self.subscriber = pubsub_v1.SubscriberClient()
        self.bigquery_client = bigquery.Client()
        self.monitoring_client = monitoring_v3.MetricServiceClient()
        
        # Set up subscription path
        self.subscription_path = self.subscriber.subscription_path(
            self.project_id, self.subscription_name
        )
        
    def process_meeting_event(self, event_data):
        """Process Google Meet/Calendar events"""
        try:
            # Extract meeting information
            meeting_data = {
                'event_id': event_data.get('eventId'),
                'event_type': event_data.get('eventType'),
                'meeting_id': event_data.get('meetingId'),
                'organizer_email': event_data.get('organizerEmail'),
                'participant_count': len(event_data.get('participants', [])),
                'start_time': event_data.get('startTime'),
                'end_time': event_data.get('endTime'),
                'duration_minutes': self.calculate_duration(
                    event_data.get('startTime'), 
                    event_data.get('endTime')
                ),
                'meeting_title': event_data.get('title', ''),
                'calendar_id': event_data.get('calendarId'),
                'created_time': datetime.now(timezone.utc).isoformat()
            }
            
            # Insert into BigQuery
            table_ref = self.bigquery_client.dataset(self.dataset_name).table('meeting_events')
            errors = self.bigquery_client.insert_rows_json(table_ref, [meeting_data])
            
            if errors:
                logger.error(f"BigQuery insertion errors: {errors}")
            else:
                logger.info(f"Meeting event processed: {meeting_data['event_id']}")
                
        except Exception as e:
            logger.error(f"Error processing meeting event: {e}")
    
    def process_file_event(self, event_data):
        """Process Google Drive/Docs file events"""
        try:
            # Extract file information
            file_data = {
                'event_id': event_data.get('eventId'),
                'event_type': event_data.get('eventType'),
                'file_id': event_data.get('fileId'),
                'user_email': event_data.get('userEmail'),
                'file_name': event_data.get('fileName'),
                'file_type': event_data.get('fileType'),
                'action': event_data.get('action'),
                'shared_with_count': len(event_data.get('sharedWith', [])),
                'folder_id': event_data.get('folderId'),
                'drive_id': event_data.get('driveId'),
                'created_time': datetime.now(timezone.utc).isoformat()
            }
            
            # Insert into BigQuery
            table_ref = self.bigquery_client.dataset(self.dataset_name).table('file_events')
            errors = self.bigquery_client.insert_rows_json(table_ref, [file_data])
            
            if errors:
                logger.error(f"BigQuery insertion errors: {errors}")
            else:
                logger.info(f"File event processed: {file_data['event_id']}")
                
        except Exception as e:
            logger.error(f"Error processing file event: {e}")
    
    def calculate_duration(self, start_time, end_time):
        """Calculate meeting duration in minutes"""
        try:
            if start_time and end_time:
                start = datetime.fromisoformat(start_time.replace('Z', '+00:00'))
                end = datetime.fromisoformat(end_time.replace('Z', '+00:00'))
                return int((end - start).total_seconds() / 60)
        except:
            pass
        return 0
    
    def callback(self, message):
        """Process individual Pub/Sub messages"""
        try:
            # Parse message data
            event_data = json.loads(message.data.decode('utf-8'))
            event_type = event_data.get('eventType', '')
            
            # Route to appropriate processor
            if 'meeting' in event_type.lower() or 'calendar' in event_type.lower():
                self.process_meeting_event(event_data)
            elif 'drive' in event_type.lower() or 'file' in event_type.lower():
                self.process_file_event(event_data)
            else:
                logger.warning(f"Unknown event type: {event_type}")
            
            # Acknowledge message
            message.ack()
            logger.info(f"Message processed and acknowledged: {message.message_id}")
            
        except Exception as e:
            logger.error(f"Error processing message: {e}")
            message.nack()
    
    def run(self):
        """Start processing messages"""
        logger.info("Starting workspace event processor...")
        
        # Configure flow control
        flow_control = pubsub_v1.types.FlowControl(max_messages=100)
        
        # Start pulling messages
        streaming_pull_future = self.subscriber.pull(
            request={"subscription": self.subscription_path, "max_messages": 10},
            callback=self.callback,
            flow_control=flow_control
        )
        
        logger.info(f"Listening for messages on {self.subscription_path}...")
        
        try:
            streaming_pull_future.result()
        except KeyboardInterrupt:
            streaming_pull_future.cancel()
            logger.info("Event processor stopped")

if __name__ == '__main__':
    processor = WorkspaceEventProcessor()
    processor.run()
EOF

        # Create requirements file
        cat > requirements.txt << 'EOF'
google-cloud-pubsub==2.18.4
google-cloud-bigquery==3.11.4
google-cloud-monitoring==2.15.1
google-apps-events-subscriptions==0.1.0
EOF

        # Create Dockerfile
        cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Set environment variables
ENV PORT=8080
ENV PYTHONUNBUFFERED=1

# Run the application
CMD ["python", "main.py"]
EOF

        log INFO "Application code created successfully"
        cd "$SCRIPT_DIR"
    else
        log INFO "[DRY RUN] Would create application code in: $app_dir"
    fi
}

# Deploy Cloud Run Worker Pool
deploy_worker_pool() {
    log INFO "Deploying Cloud Run Worker Pool..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        local app_dir="${SCRIPT_DIR}/../workspace-analytics-app"
        cd "$app_dir"
        
        # Build container image
        log INFO "Building container image..."
        if ! gcloud builds submit --tag "gcr.io/${PROJECT_ID}/workspace-analytics" .; then
            error_exit "Failed to build container image"
        fi
        
        # Deploy worker pool
        log INFO "Creating Cloud Run Worker Pool..."
        if ! gcloud beta run worker-pools create "${WORKER_POOL_NAME}" \
            --image="gcr.io/${PROJECT_ID}/workspace-analytics" \
            --region="${REGION}" \
            --min-instances=1 \
            --max-instances=10 \
            --memory=1Gi \
            --cpu=1 \
            --env-vars="PROJECT_ID=${PROJECT_ID},SUBSCRIPTION_NAME=${SUBSCRIPTION_NAME},DATASET_NAME=${DATASET_NAME}"; then
            error_exit "Failed to create worker pool"
        fi
        
        # Get service account for worker pool
        local worker_sa
        worker_sa=$(gcloud beta run worker-pools describe "${WORKER_POOL_NAME}" \
            --region="${REGION}" \
            --format='value(spec.template.spec.serviceAccountName)' 2>/dev/null || echo "${PROJECT_ID}@appspot.gserviceaccount.com")
        
        # Set IAM permissions
        log INFO "Setting IAM permissions for worker pool..."
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${worker_sa}" \
            --role="roles/bigquery.dataEditor" || log WARN "Failed to set BigQuery IAM"
        
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${worker_sa}" \
            --role="roles/pubsub.subscriber" || log WARN "Failed to set Pub/Sub IAM"
        
        log INFO "Cloud Run Worker Pool deployed successfully"
        cd "$SCRIPT_DIR"
    else
        log INFO "[DRY RUN] Would deploy worker pool: $WORKER_POOL_NAME"
    fi
}

# Create BigQuery analytics views
create_analytics_views() {
    log INFO "Creating BigQuery analytics views..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Create meeting analytics view
        cat > /tmp/meeting_analytics_view.sql << EOF
CREATE VIEW \`${PROJECT_ID}.${DATASET_NAME}.meeting_analytics\` AS
SELECT 
  DATE(start_time) as meeting_date,
  organizer_email,
  COUNT(*) as total_meetings,
  AVG(duration_minutes) as avg_duration,
  AVG(participant_count) as avg_participants,
  SUM(duration_minutes * participant_count) as total_person_minutes
FROM \`${PROJECT_ID}.${DATASET_NAME}.meeting_events\`
WHERE start_time >= DATETIME_SUB(CURRENT_DATETIME(), INTERVAL 30 DAY)
GROUP BY meeting_date, organizer_email
ORDER BY meeting_date DESC;
EOF

        if ! bq query --use_legacy_sql=false < /tmp/meeting_analytics_view.sql; then
            error_exit "Failed to create meeting analytics view"
        fi
        
        # Create collaboration analytics view
        cat > /tmp/collaboration_analytics_view.sql << EOF
CREATE VIEW \`${PROJECT_ID}.${DATASET_NAME}.collaboration_analytics\` AS
SELECT 
  DATE(created_time) as activity_date,
  user_email,
  file_type,
  action,
  COUNT(*) as action_count,
  COUNT(DISTINCT file_id) as unique_files,
  AVG(shared_with_count) as avg_sharing
FROM \`${PROJECT_ID}.${DATASET_NAME}.file_events\`
WHERE created_time >= DATETIME_SUB(CURRENT_DATETIME(), INTERVAL 30 DAY)
GROUP BY activity_date, user_email, file_type, action
ORDER BY activity_date DESC;
EOF

        if ! bq query --use_legacy_sql=false < /tmp/collaboration_analytics_view.sql; then
            error_exit "Failed to create collaboration analytics view"
        fi
        
        # Create productivity insights view
        cat > /tmp/productivity_insights_view.sql << EOF
CREATE VIEW \`${PROJECT_ID}.${DATASET_NAME}.productivity_insights\` AS
WITH meeting_stats AS (
  SELECT 
    organizer_email as email,
    COUNT(*) as meetings_organized,
    SUM(duration_minutes) as total_meeting_time
  FROM \`${PROJECT_ID}.${DATASET_NAME}.meeting_events\`
  WHERE start_time >= DATETIME_SUB(CURRENT_DATETIME(), INTERVAL 7 DAY)
  GROUP BY organizer_email
),
collaboration_stats AS (
  SELECT 
    user_email as email,
    COUNT(*) as file_actions,
    COUNT(DISTINCT file_id) as files_touched
  FROM \`${PROJECT_ID}.${DATASET_NAME}.file_events\`
  WHERE created_time >= DATETIME_SUB(CURRENT_DATETIME(), INTERVAL 7 DAY)
  GROUP BY user_email
)
SELECT 
  COALESCE(m.email, c.email) as user_email,
  COALESCE(meetings_organized, 0) as meetings_organized,
  COALESCE(total_meeting_time, 0) as total_meeting_time,
  COALESCE(file_actions, 0) as file_actions,
  COALESCE(files_touched, 0) as files_touched,
  ROUND((COALESCE(file_actions, 0) + COALESCE(meetings_organized, 0) * 2) / 7, 2) as activity_score
FROM meeting_stats m
FULL OUTER JOIN collaboration_stats c ON m.email = c.email
ORDER BY activity_score DESC;
EOF

        if ! bq query --use_legacy_sql=false < /tmp/productivity_insights_view.sql; then
            error_exit "Failed to create productivity insights view"
        fi
        
        # Clean up temporary files
        rm -f /tmp/*_view.sql
        
        log INFO "BigQuery analytics views created successfully"
    else
        log INFO "[DRY RUN] Would create analytics views: meeting_analytics, collaboration_analytics, productivity_insights"
    fi
}

# Configure monitoring dashboard
configure_monitoring() {
    log INFO "Configuring Cloud Monitoring dashboard and alerts..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Create dashboard configuration
        cat > /tmp/dashboard-config.json << EOF
{
  "displayName": "Workforce Analytics Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Event Processing Rate",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\"",
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
        "xPos": 6,
        "widget": {
          "title": "Worker Pool Instances",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/container/instance_count\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
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

        # Create dashboard
        if ! gcloud monitoring dashboards create --config-from-file=/tmp/dashboard-config.json; then
            log WARN "Failed to create monitoring dashboard"
        fi
        
        # Create alerting policy
        cat > /tmp/alert-policy.yaml << EOF
displayName: "High Event Processing Latency"
conditions:
  - displayName: "Processing latency too high"
    conditionThreshold:
      filter: 'resource.type="cloud_run_revision"'
      comparison: COMPARISON_GREATER_THAN
      thresholdValue: 5000
      duration: 300s
      aggregations:
        - alignmentPeriod: 60s
          perSeriesAligner: ALIGN_MEAN
notificationChannels: []
alertStrategy:
  autoClose: 86400s
EOF

        if ! gcloud alpha monitoring policies create --policy-from-file=/tmp/alert-policy.yaml; then
            log WARN "Failed to create alerting policy"
        fi
        
        # Clean up temporary files
        rm -f /tmp/dashboard-config.json /tmp/alert-policy.yaml
        
        log INFO "Cloud Monitoring dashboard and alerts configured"
    else
        log INFO "[DRY RUN] Would configure monitoring dashboard and alerts"
    fi
}

# Generate workspace events configuration
generate_workspace_config() {
    log INFO "Generating Workspace Events API configuration..."
    
    local config_file="${SCRIPT_DIR}/../workspace-events-config.json"
    
    cat > "$config_file" << EOF
{
  "name": "projects/${PROJECT_ID}/subscriptions/workforce-analytics",
  "targetResource": "//workspace.googleapis.com/users/*",
  "eventTypes": [
    "google.workspace.calendar.event.v1.created",
    "google.workspace.calendar.event.v1.updated",
    "google.workspace.drive.file.v1.created",
    "google.workspace.drive.file.v1.updated",
    "google.workspace.meet.participant.v1.joined",
    "google.workspace.meet.participant.v1.left",
    "google.workspace.meet.recording.v1.fileGenerated"
  ],
  "notificationEndpoint": {
    "pubsubTopic": "projects/${PROJECT_ID}/topics/${TOPIC_NAME}"
  },
  "payloadOptions": {
    "includeResource": true,
    "fieldMask": "eventType,eventTime,resource"
  }
}
EOF

    log INFO "Workspace Events API configuration saved to: $config_file"
    log INFO "📋 Manual Configuration Required:"
    log INFO "1. Visit Google Workspace Admin Console"
    log INFO "2. Navigate to Security > API Reference > Events API"
    log INFO "3. Create subscription using the configuration file"
    log INFO "4. Verify webhook endpoint and authentication"
}

# Deployment summary
deployment_summary() {
    log INFO ""
    log INFO "=================================================="
    log INFO "         Deployment Summary"
    log INFO "=================================================="
    log INFO "Project ID: $PROJECT_ID"
    log INFO "Region: $REGION"
    log INFO "BigQuery Dataset: $DATASET_NAME"
    log INFO "Worker Pool: $WORKER_POOL_NAME"
    log INFO "Pub/Sub Topic: $TOPIC_NAME"
    log INFO "Storage Bucket: $BUCKET_NAME"
    log INFO ""
    log INFO "📋 Next Steps:"
    log INFO "1. Configure Workspace Events API using the generated configuration"
    log INFO "2. Test the system by sending sample events"
    log INFO "3. Monitor the dashboard for processing metrics"
    log INFO "4. Query BigQuery views for workforce insights"
    log INFO ""
    log INFO "📊 Access Points:"
    log INFO "- BigQuery Console: https://console.cloud.google.com/bigquery?project=$PROJECT_ID"
    log INFO "- Cloud Run: https://console.cloud.google.com/run?project=$PROJECT_ID"
    log INFO "- Monitoring: https://console.cloud.google.com/monitoring?project=$PROJECT_ID"
    log INFO ""
    log INFO "🧹 Cleanup:"
    log INFO "Run ./destroy.sh to remove all resources when finished"
    log INFO ""
    log INFO "✅ Deployment completed successfully!"
    log INFO "Log file: $LOG_FILE"
}

# Main deployment function
main() {
    local start_time=$(date +%s)
    
    log INFO "Starting workforce analytics deployment..."
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    configure_project
    enable_apis
    create_bigquery_resources
    create_pubsub_resources
    create_storage_bucket
    create_application_code
    deploy_worker_pool
    create_analytics_views
    configure_monitoring
    generate_workspace_config
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    deployment_summary
    log INFO "Total deployment time: ${duration} seconds"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi