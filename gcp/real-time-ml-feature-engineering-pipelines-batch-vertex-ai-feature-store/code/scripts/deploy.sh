#!/bin/bash

# Real-Time ML Feature Engineering Pipelines with Cloud Batch and Vertex AI Feature Store
# Deployment Script for GCP Infrastructure
# Version: 1.0

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

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for failed deployments
cleanup_on_error() {
    log_warning "Deployment failed. Starting cleanup of partial resources..."
    ./destroy.sh --force || true
}

# Trap errors
trap cleanup_on_error ERR

# Configuration variables with defaults
PROJECT_ID="${PROJECT_ID:-ml-features-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"

# Resource names
DATASET_NAME="feature_dataset_${RANDOM_SUFFIX}"
FEATURE_TABLE="user_features"
BATCH_JOB_NAME="feature-pipeline-${RANDOM_SUFFIX}"
PUBSUB_TOPIC="feature-updates-${RANDOM_SUFFIX}"
FEATURE_GROUP_NAME="user-feature-group-${RANDOM_SUFFIX}"
BUCKET_NAME="ml-features-bucket-${RANDOM_SUFFIX}"

# Display banner
echo -e "${BLUE}"
echo "=============================================="
echo "  ML Feature Engineering Pipeline Deployment"
echo "=============================================="
echo -e "${NC}"

# Parse command line arguments
DRY_RUN=false
SKIP_PREREQUISITES=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log_warning "Running in dry-run mode - no resources will be created"
            shift
            ;;
        --skip-prerequisites)
            SKIP_PREREQUISITES=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run              Run without creating resources"
            echo "  --skip-prerequisites   Skip prerequisite checks"
            echo "  --verbose              Enable verbose logging"
            echo "  --project-id ID        Specify GCP project ID"
            echo "  --region REGION        Specify GCP region"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Display configuration
log "Deployment Configuration:"
echo "  Project ID: $PROJECT_ID"
echo "  Region: $REGION"
echo "  Zone: $ZONE"
echo "  Random Suffix: $RANDOM_SUFFIX"
echo ""

# Prerequisite checks
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error_exit "bq CLI is not installed. Please install BigQuery CLI."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not installed. Please install Google Cloud SDK."
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error_exit "Not authenticated with gcloud. Run 'gcloud auth login'."
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_warning "Project $PROJECT_ID does not exist. Creating it..."
        if [[ "$DRY_RUN" == "false" ]]; then
            gcloud projects create "$PROJECT_ID" --name="ML Features Pipeline"
        fi
    fi
    
    log_success "Prerequisites check completed"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "batch.googleapis.com"
        "pubsub.googleapis.com"
        "bigquery.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "false" ]]; then
        for api in "${apis[@]}"; do
            log "Enabling $api..."
            gcloud services enable "$api" --project="$PROJECT_ID"
        done
        
        # Wait for APIs to be fully enabled
        log "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    log_success "APIs enabled successfully"
}

# Set default project and region
configure_defaults() {
    log "Configuring gcloud defaults..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        gcloud config set project "$PROJECT_ID"
        gcloud config set compute/region "$REGION"
        gcloud config set compute/zone "$ZONE"
    fi
    
    log_success "Defaults configured"
}

# Create BigQuery resources
create_bigquery_resources() {
    log "Creating BigQuery dataset and tables..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create BigQuery dataset
        bq mk --dataset \
            --location="$REGION" \
            --description="Feature dataset for ML pipeline" \
            "$PROJECT_ID:$DATASET_NAME"
        
        # Create feature table
        bq mk --table \
            --description="Computed user features for ML models" \
            "$PROJECT_ID:$DATASET_NAME.$FEATURE_TABLE" \
            user_id:STRING,feature_timestamp:TIMESTAMP,avg_session_duration:FLOAT,total_purchases:INTEGER,days_since_last_login:INTEGER,purchase_frequency:FLOAT,preferred_category:STRING
        
        # Create source data table for demonstration
        bq mk --table \
            --description="Raw user events for feature computation" \
            "$PROJECT_ID:$DATASET_NAME.raw_user_events" \
            user_id:STRING,event_timestamp:TIMESTAMP,event_type:STRING,session_duration:FLOAT,purchase_amount:FLOAT,category:STRING
        
        # Insert sample data for testing
        bq query --use_legacy_sql=false \
            "INSERT INTO \`$PROJECT_ID.$DATASET_NAME.raw_user_events\` 
             (user_id, event_timestamp, event_type, session_duration, purchase_amount, category)
             VALUES 
             ('user1', CURRENT_TIMESTAMP(), 'login', 15.5, NULL, NULL),
             ('user1', CURRENT_TIMESTAMP(), 'purchase', 25.0, 99.99, 'electronics'),
             ('user2', CURRENT_TIMESTAMP(), 'login', 8.2, NULL, NULL),
             ('user2', CURRENT_TIMESTAMP(), 'purchase', 12.0, 49.99, 'books'),
             ('user3', CURRENT_TIMESTAMP(), 'login', 22.1, NULL, NULL)"
    fi
    
    log_success "BigQuery resources created"
    echo "  Dataset: $DATASET_NAME"
    echo "  Feature Table: $FEATURE_TABLE"
    echo "  Source Table: raw_user_events"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create bucket with appropriate configuration
        gsutil mb -p "$PROJECT_ID" \
            -c STANDARD \
            -l "$REGION" \
            -b on \
            "gs://$BUCKET_NAME"
        
        # Enable versioning
        gsutil versioning set on "gs://$BUCKET_NAME"
        
        # Set lifecycle policy to clean up old versions
        cat > lifecycle.json << EOF
{
  "lifecycle": {
    "rule": [
      {
        "condition": {
          "numNewerVersions": 3
        },
        "action": {
          "type": "Delete"
        }
      }
    ]
  }
}
EOF
        gsutil lifecycle set lifecycle.json "gs://$BUCKET_NAME"
        rm lifecycle.json
    fi
    
    log_success "Cloud Storage bucket created: gs://$BUCKET_NAME"
}

# Create feature engineering script
create_feature_script() {
    log "Creating and uploading feature engineering script..."
    
    cat > feature_engineering.py << 'EOF'
import pandas as pd
from google.cloud import bigquery
import os
from datetime import datetime, timedelta
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def compute_user_features():
    """Compute user features from raw events data."""
    try:
        client = bigquery.Client()
        project_id = os.environ['PROJECT_ID']
        dataset_name = os.environ['DATASET_NAME']
        feature_table = os.environ['FEATURE_TABLE']
        
        logger.info(f"Starting feature computation for project: {project_id}")
        
        # SQL query for feature engineering with improved error handling
        query = f"""
        WITH user_stats AS (
          SELECT 
            user_id,
            AVG(CASE WHEN session_duration > 0 THEN session_duration END) as avg_session_duration,
            COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) as total_purchases,
            DATE_DIFF(CURRENT_DATE(), MAX(DATE(event_timestamp)), DAY) as days_since_last_login,
            SAFE_DIVIDE(
              COUNT(CASE WHEN event_type = 'purchase' THEN 1 END),
              GREATEST(DATE_DIFF(CURRENT_DATE(), MIN(DATE(event_timestamp)), DAY), 1)
            ) as purchase_frequency,
            (
              SELECT category 
              FROM (
                SELECT category, COUNT(*) as cnt
                FROM `{project_id}.{dataset_name}.raw_user_events` e2
                WHERE e2.user_id = e1.user_id AND category IS NOT NULL
                GROUP BY category
                ORDER BY cnt DESC
                LIMIT 1
              )
            ) as preferred_category
          FROM `{project_id}.{dataset_name}.raw_user_events` e1
          WHERE event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
          GROUP BY user_id
        )
        SELECT 
          user_id,
          CURRENT_TIMESTAMP() as feature_timestamp,
          COALESCE(avg_session_duration, 0.0) as avg_session_duration,
          COALESCE(total_purchases, 0) as total_purchases,
          COALESCE(days_since_last_login, 999) as days_since_last_login,
          COALESCE(purchase_frequency, 0.0) as purchase_frequency,
          COALESCE(preferred_category, 'unknown') as preferred_category
        FROM user_stats
        """
        
        # Execute feature computation
        job_config = bigquery.QueryJobConfig(
            destination=f"{project_id}.{dataset_name}.{feature_table}",
            write_disposition="WRITE_TRUNCATE",
            use_query_cache=False
        )
        
        logger.info("Executing feature computation query...")
        query_job = client.query(query, job_config=job_config)
        result = query_job.result()
        
        # Log results
        row_count = result.total_rows if hasattr(result, 'total_rows') else 0
        logger.info(f"✅ Features computed and loaded to BigQuery. Processed {row_count} rows.")
        
        # Verify the results
        verify_query = f"""
        SELECT COUNT(*) as feature_count, 
               MIN(feature_timestamp) as min_timestamp,
               MAX(feature_timestamp) as max_timestamp
        FROM `{project_id}.{dataset_name}.{feature_table}`
        """
        
        verify_job = client.query(verify_query)
        verify_result = verify_job.result()
        
        for row in verify_result:
            logger.info(f"Feature table verification: {row.feature_count} features, "
                       f"timestamp range: {row.min_timestamp} to {row.max_timestamp}")
        
    except Exception as e:
        logger.error(f"Error computing features: {str(e)}")
        raise

if __name__ == "__main__":
    compute_user_features()
EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Upload script to Cloud Storage
        gsutil cp feature_engineering.py "gs://$BUCKET_NAME/scripts/"
    fi
    
    log_success "Feature engineering script created and uploaded"
}

# Create Pub/Sub resources
create_pubsub_resources() {
    log "Creating Pub/Sub topic and subscription..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create topic
        gcloud pubsub topics create "$PUBSUB_TOPIC" \
            --project="$PROJECT_ID"
        
        # Create subscription with appropriate configuration
        gcloud pubsub subscriptions create "feature-pipeline-sub" \
            --topic="$PUBSUB_TOPIC" \
            --ack-deadline=600 \
            --message-retention-duration=7d \
            --project="$PROJECT_ID"
    fi
    
    log_success "Pub/Sub resources created"
    echo "  Topic: $PUBSUB_TOPIC"
    echo "  Subscription: feature-pipeline-sub"
}

# Create and submit Cloud Batch job
create_batch_job() {
    log "Creating and submitting Cloud Batch job..."
    
    # Create batch job configuration
    cat > batch_job_config.json << EOF
{
  "taskGroups": [
    {
      "taskSpec": {
        "runnables": [
          {
            "container": {
              "imageUri": "gcr.io/google.com/cloudsdktool/cloud-sdk:latest",
              "commands": [
                "/bin/bash"
              ],
              "args": [
                "-c",
                "apt-get update && apt-get install -y python3-pip && pip3 install google-cloud-bigquery pandas && gsutil cp gs://$BUCKET_NAME/scripts/feature_engineering.py . && python3 feature_engineering.py"
              ]
            },
            "environment": {
              "variables": {
                "PROJECT_ID": "$PROJECT_ID",
                "DATASET_NAME": "$DATASET_NAME",
                "FEATURE_TABLE": "$FEATURE_TABLE"
              }
            }
          }
        ],
        "computeResource": {
          "cpuMilli": 2000,
          "memoryMib": 4096
        },
        "maxRetryCount": 3,
        "maxRunDuration": "3600s"
      },
      "taskCount": 1
    }
  ],
  "allocationPolicy": {
    "instances": [
      {
        "policy": {
          "machineType": "e2-standard-2",
          "provisioningModel": "STANDARD"
        }
      }
    ]
  },
  "logsPolicy": {
    "destination": "CLOUD_LOGGING"
  }
}
EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Submit batch job
        gcloud batch jobs submit "$BATCH_JOB_NAME" \
            --location="$REGION" \
            --config=batch_job_config.json \
            --project="$PROJECT_ID"
        
        # Wait for job to start
        log "Waiting for batch job to start..."
        sleep 30
        
        # Check initial job status
        JOB_STATE=$(gcloud batch jobs describe "$BATCH_JOB_NAME" \
            --location="$REGION" \
            --project="$PROJECT_ID" \
            --format="value(status.state)")
        
        log "Batch job state: $JOB_STATE"
    fi
    
    log_success "Cloud Batch job created and submitted: $BATCH_JOB_NAME"
    
    # Clean up config file
    rm -f batch_job_config.json
}

# Create Vertex AI Feature Store resources
create_vertex_ai_resources() {
    log "Creating Vertex AI Feature Store resources..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Wait for batch job to complete before creating feature store
        log "Waiting for batch job to complete before creating feature store..."
        local max_wait=1800  # 30 minutes
        local wait_time=0
        local check_interval=60
        
        while [[ $wait_time -lt $max_wait ]]; do
            JOB_STATE=$(gcloud batch jobs describe "$BATCH_JOB_NAME" \
                --location="$REGION" \
                --project="$PROJECT_ID" \
                --format="value(status.state)" 2>/dev/null || echo "UNKNOWN")
            
            if [[ "$JOB_STATE" == "SUCCEEDED" ]]; then
                log_success "Batch job completed successfully"
                break
            elif [[ "$JOB_STATE" == "FAILED" ]]; then
                error_exit "Batch job failed. Check logs for details."
            fi
            
            log "Batch job still running (state: $JOB_STATE). Waiting..."
            sleep $check_interval
            wait_time=$((wait_time + check_interval))
        done
        
        if [[ $wait_time -ge $max_wait ]]; then
            log_warning "Batch job taking longer than expected. Proceeding with feature store creation..."
        fi
        
        # Create feature group
        gcloud ai feature-groups create "$FEATURE_GROUP_NAME" \
            --location="$REGION" \
            --source-bigquery-uri="bq://$PROJECT_ID.$DATASET_NAME.$FEATURE_TABLE" \
            --entity-id-columns=user_id \
            --description="User behavior features for ML models" \
            --project="$PROJECT_ID"
        
        # Wait for feature group creation
        log "Waiting for feature group creation to complete..."
        sleep 60
        
        # Create individual features
        local features=(
            "avg_session_duration:DOUBLE:Average session duration in minutes"
            "total_purchases:INT64:Total number of purchases"
            "purchase_frequency:DOUBLE:Purchase frequency per day"
            "days_since_last_login:INT64:Days since last login"
            "preferred_category:STRING:Most preferred purchase category"
        )
        
        for feature_def in "${features[@]}"; do
            IFS=':' read -r feature_name feature_type feature_desc <<< "$feature_def"
            
            log "Creating feature: $feature_name"
            gcloud ai features create "$feature_name" \
                --feature-group="$FEATURE_GROUP_NAME" \
                --location="$REGION" \
                --value-type="$feature_type" \
                --description="$feature_desc" \
                --project="$PROJECT_ID"
        done
    fi
    
    log_success "Vertex AI Feature Store resources created"
    echo "  Feature Group: $FEATURE_GROUP_NAME"
}

# Create online feature serving
create_online_serving() {
    log "Setting up online feature serving..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create online store
        gcloud ai online-stores create "user-features-store-$RANDOM_SUFFIX" \
            --location="$REGION" \
            --description="Online store for user features" \
            --project="$PROJECT_ID"
        
        # Wait for online store creation
        log "Waiting for online store creation..."
        sleep 90
        
        # Create feature view for online serving
        gcloud ai feature-views create "user-feature-view-$RANDOM_SUFFIX" \
            --online-store="user-features-store-$RANDOM_SUFFIX" \
            --location="$REGION" \
            --source-feature-group="$FEATURE_GROUP_NAME" \
            --feature-view-sync-config-cron="0 */6 * * *" \
            --project="$PROJECT_ID"
    fi
    
    log_success "Online feature serving configured"
}

# Create Cloud Function for event processing
create_cloud_function() {
    log "Creating Cloud Function for event processing..."
    
    # Create function source code
    cat > main.py << 'EOF'
import base64
import json
import os
import logging
from google.cloud import batch_v1
from google.cloud import bigquery

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def trigger_feature_pipeline(cloud_event):
    """Trigger feature pipeline when Pub/Sub message is received."""
    try:
        # Decode Pub/Sub message
        if 'data' in cloud_event.data and 'message' in cloud_event.data:
            message_data = base64.b64decode(cloud_event.data['message']['data']).decode('utf-8')
            logger.info(f"Processing message: {message_data}")
        else:
            logger.info("Triggered by Pub/Sub event (no message data)")
        
        project_id = os.environ.get('PROJECT_ID')
        region = os.environ.get('REGION')
        
        if not project_id or not region:
            logger.error("PROJECT_ID and REGION environment variables must be set")
            return {'status': 'error', 'message': 'Missing environment variables'}
        
        # For demonstration, we'll just log the trigger
        # In production, this could trigger a new batch job or update features directly
        logger.info(f"Feature pipeline triggered for project {project_id} in region {region}")
        
        # You could add logic here to:
        # 1. Validate the incoming data
        # 2. Trigger a new batch job
        # 3. Update features directly in BigQuery
        # 4. Send notifications
        
        return {'status': 'success', 'message': 'Feature pipeline triggered successfully'}
        
    except Exception as e:
        logger.error(f"Error processing Pub/Sub message: {str(e)}")
        return {'status': 'error', 'message': str(e)}
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-batch==0.17.0
google-cloud-storage==2.10.0
google-cloud-bigquery==3.11.0
google-cloud-pubsub==2.18.0
functions-framework==3.4.0
EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Deploy Cloud Function
        gcloud functions deploy trigger-feature-pipeline \
            --runtime python39 \
            --trigger-topic "$PUBSUB_TOPIC" \
            --source . \
            --entry-point trigger_feature_pipeline \
            --memory 512MB \
            --timeout 300s \
            --max-instances 10 \
            --set-env-vars "PROJECT_ID=$PROJECT_ID,REGION=$REGION" \
            --project="$PROJECT_ID"
    fi
    
    # Clean up temporary files
    rm -f main.py requirements.txt
    
    log_success "Cloud Function deployed for event processing"
}

# Validation and testing
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Check BigQuery feature table
        log "Checking BigQuery feature table..."
        FEATURE_COUNT=$(bq query --use_legacy_sql=false \
            --format=csv \
            "SELECT COUNT(*) FROM \`$PROJECT_ID.$DATASET_NAME.$FEATURE_TABLE\`" | tail -n1)
        
        if [[ "$FEATURE_COUNT" -gt 0 ]]; then
            log_success "BigQuery feature table contains $FEATURE_COUNT rows"
        else
            log_warning "BigQuery feature table is empty"
        fi
        
        # Check Vertex AI Feature Store
        log "Checking Vertex AI Feature Store..."
        if gcloud ai feature-groups describe "$FEATURE_GROUP_NAME" \
            --location="$REGION" \
            --project="$PROJECT_ID" &> /dev/null; then
            log_success "Vertex AI Feature Group created successfully"
        else
            log_warning "Vertex AI Feature Group not found"
        fi
        
        # Check Cloud Function
        log "Checking Cloud Function..."
        if gcloud functions describe trigger-feature-pipeline \
            --project="$PROJECT_ID" &> /dev/null; then
            log_success "Cloud Function deployed successfully"
        else
            log_warning "Cloud Function not found"
        fi
        
        # Test Pub/Sub message
        log "Testing Pub/Sub message processing..."
        gcloud pubsub topics publish "$PUBSUB_TOPIC" \
            --message='{"event": "feature_update_request", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
            --project="$PROJECT_ID"
        
        log_success "Test message sent to Pub/Sub topic"
    fi
    
    log_success "Deployment validation completed"
}

# Main deployment function
main() {
    log "Starting ML Feature Engineering Pipeline deployment..."
    
    if [[ "$SKIP_PREREQUISITES" == "false" ]]; then
        check_prerequisites
    fi
    
    configure_defaults
    enable_apis
    create_bigquery_resources
    create_storage_bucket
    create_feature_script
    create_pubsub_resources
    create_batch_job
    create_vertex_ai_resources
    create_online_serving
    create_cloud_function
    validate_deployment
    
    # Display summary
    echo ""
    log_success "🎉 ML Feature Engineering Pipeline deployed successfully!"
    echo ""
    echo "📋 Deployment Summary:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  BigQuery Dataset: $DATASET_NAME"
    echo "  Feature Group: $FEATURE_GROUP_NAME"
    echo "  Batch Job: $BATCH_JOB_NAME"
    echo "  Pub/Sub Topic: $PUBSUB_TOPIC"
    echo "  Storage Bucket: gs://$BUCKET_NAME"
    echo ""
    echo "🔧 Next Steps:"
    echo "  1. Monitor batch job execution: gcloud batch jobs describe $BATCH_JOB_NAME --location=$REGION"
    echo "  2. Check feature data: bq query 'SELECT * FROM \`$PROJECT_ID.$DATASET_NAME.$FEATURE_TABLE\` LIMIT 10'"
    echo "  3. Test Pub/Sub trigger: gcloud pubsub topics publish $PUBSUB_TOPIC --message='{\"test\": \"message\"}'"
    echo "  4. View logs: gcloud logging read 'resource.type=cloud_function AND resource.labels.function_name=trigger-feature-pipeline'"
    echo ""
    echo "💰 Cost Management:"
    echo "  - Remember to run ./destroy.sh when testing is complete"
    echo "  - Monitor costs in the GCP Console billing section"
    echo ""
    
    # Save deployment info
    cat > deployment_info.txt << EOF
ML Feature Engineering Pipeline Deployment
==========================================
Deployment Date: $(date)
Project ID: $PROJECT_ID
Region: $REGION
Random Suffix: $RANDOM_SUFFIX

Resource Names:
- BigQuery Dataset: $DATASET_NAME
- Feature Table: $FEATURE_TABLE
- Batch Job: $BATCH_JOB_NAME
- Pub/Sub Topic: $PUBSUB_TOPIC
- Feature Group: $FEATURE_GROUP_NAME
- Storage Bucket: $BUCKET_NAME
- Online Store: user-features-store-$RANDOM_SUFFIX
- Feature View: user-feature-view-$RANDOM_SUFFIX
EOF
    
    log_success "Deployment info saved to deployment_info.txt"
}

# Execute main function
main "$@"