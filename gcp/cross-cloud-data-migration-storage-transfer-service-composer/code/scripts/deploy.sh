#!/bin/bash

# Cross-Cloud Data Migration with Storage Transfer Service and Cloud Composer - Deployment Script
# This script deploys the complete infrastructure for orchestrated cross-cloud data migration

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    warn "Running in DRY-RUN mode - no resources will be created"
    GCLOUD_CMD="echo [DRY-RUN] gcloud"
    GSUTIL_CMD="echo [DRY-RUN] gsutil"
else
    GCLOUD_CMD="gcloud"
    GSUTIL_CMD="gsutil"
fi

# Default configuration
DEFAULT_PROJECT_ID="migration-project-$(date +%s)"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DEFAULT_COMPOSER_ENV_NAME="data-migration-env"

# Check for prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is required but not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is required but not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "Please authenticate with gcloud: gcloud auth login"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random suffixes"
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Load configuration from environment or use defaults
load_configuration() {
    log "Loading configuration..."
    
    # Set environment variables for the project
    export PROJECT_ID=${PROJECT_ID:-$DEFAULT_PROJECT_ID}
    export REGION=${REGION:-$DEFAULT_REGION}
    export ZONE=${ZONE:-$DEFAULT_ZONE}
    export COMPOSER_ENV_NAME=${COMPOSER_ENV_NAME:-$DEFAULT_COMPOSER_ENV_NAME}
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export STAGING_BUCKET=${STAGING_BUCKET:-"migration-staging-${RANDOM_SUFFIX}"}
    export TARGET_BUCKET=${TARGET_BUCKET:-"migration-target-${RANDOM_SUFFIX}"}
    export TRANSFER_JOB_NAME=${TRANSFER_JOB_NAME:-"cross-cloud-migration-${RANDOM_SUFFIX}"}
    
    info "Configuration loaded:"
    info "  PROJECT_ID: $PROJECT_ID"
    info "  REGION: $REGION"
    info "  ZONE: $ZONE"
    info "  COMPOSER_ENV_NAME: $COMPOSER_ENV_NAME"
    info "  STAGING_BUCKET: $STAGING_BUCKET"
    info "  TARGET_BUCKET: $TARGET_BUCKET"
    info "  TRANSFER_JOB_NAME: $TRANSFER_JOB_NAME"
}

# Configure gcloud settings
configure_gcloud() {
    log "Configuring gcloud settings..."
    
    # Set default project and region
    $GCLOUD_CMD config set project ${PROJECT_ID}
    $GCLOUD_CMD config set compute/region ${REGION}
    $GCLOUD_CMD config set compute/zone ${ZONE}
    
    log "gcloud configuration updated"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "composer.googleapis.com"
        "storagetransfer.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "compute.googleapis.com"
        "container.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling $api..."
        $GCLOUD_CMD services enable $api
    done
    
    log "Required APIs enabled"
}

# Create Cloud Storage buckets
create_storage_buckets() {
    log "Creating Cloud Storage buckets..."
    
    # Create staging bucket for temporary data processing
    info "Creating staging bucket: $STAGING_BUCKET"
    $GSUTIL_CMD mb -p ${PROJECT_ID} \
        -c STANDARD \
        -l ${REGION} \
        gs://${STAGING_BUCKET}
    
    # Create target bucket for final migrated data
    info "Creating target bucket: $TARGET_BUCKET"
    $GSUTIL_CMD mb -p ${PROJECT_ID} \
        -c STANDARD \
        -l ${REGION} \
        gs://${TARGET_BUCKET}
    
    # Enable versioning for data protection
    info "Enabling versioning on buckets..."
    $GSUTIL_CMD versioning set on gs://${STAGING_BUCKET}
    $GSUTIL_CMD versioning set on gs://${TARGET_BUCKET}
    
    # Set lifecycle policy for staging bucket
    info "Setting lifecycle policy for staging bucket..."
    cat > /tmp/lifecycle-policy.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {
          "type": "Delete"
        },
        "condition": {
          "age": 30
        }
      }
    ]
  }
}
EOF
    
    if [ "$DRY_RUN" != "true" ]; then
        $GSUTIL_CMD lifecycle set /tmp/lifecycle-policy.json gs://${STAGING_BUCKET}
        rm -f /tmp/lifecycle-policy.json
    fi
    
    log "Storage buckets created and configured"
}

# Create service account for Storage Transfer Service
create_service_account() {
    log "Creating service account for Storage Transfer Service..."
    
    # Create service account for transfer operations
    info "Creating storage-transfer-sa service account..."
    $GCLOUD_CMD iam service-accounts create storage-transfer-sa \
        --display-name="Storage Transfer Service Account" \
        --description="Service account for cross-cloud data migration" \
        --quiet || true
    
    # Get the service account email
    if [ "$DRY_RUN" != "true" ]; then
        export TRANSFER_SA_EMAIL=$(gcloud iam service-accounts list \
            --filter="displayName:Storage Transfer Service Account" \
            --format="value(email)")
    else
        export TRANSFER_SA_EMAIL="storage-transfer-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    fi
    
    # Grant necessary roles for transfer operations
    info "Granting IAM roles to service account..."
    $GCLOUD_CMD projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${TRANSFER_SA_EMAIL}" \
        --role="roles/storagetransfer.admin" \
        --quiet
    
    $GCLOUD_CMD projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${TRANSFER_SA_EMAIL}" \
        --role="roles/storage.admin" \
        --quiet
    
    log "Service account created and configured: ${TRANSFER_SA_EMAIL}"
}

# Create Cloud Composer environment
create_composer_environment() {
    log "Creating Cloud Composer environment..."
    
    info "This will take 15-20 minutes to complete..."
    
    # Create Cloud Composer environment
    $GCLOUD_CMD composer environments create ${COMPOSER_ENV_NAME} \
        --location ${REGION} \
        --node-count 3 \
        --disk-size 30GB \
        --machine-type n1-standard-1 \
        --python-version 3 \
        --airflow-version 2.8.1 \
        --env-variables STAGING_BUCKET=${STAGING_BUCKET},TARGET_BUCKET=${TARGET_BUCKET},PROJECT_ID=${PROJECT_ID} \
        --async
    
    if [ "$DRY_RUN" != "true" ]; then
        # Wait for environment to be ready
        info "Waiting for Composer environment to become ready..."
        while true; do
            STATE=$(gcloud composer environments describe ${COMPOSER_ENV_NAME} \
                --location ${REGION} \
                --format="value(state)" 2>/dev/null || echo "PENDING")
            
            if [ "$STATE" = "RUNNING" ]; then
                log "Composer environment is ready"
                break
            elif [ "$STATE" = "ERROR" ]; then
                error "Composer environment creation failed"
                exit 1
            else
                info "Composer environment state: $STATE - waiting 60 seconds..."
                sleep 60
            fi
        done
    fi
    
    log "Cloud Composer environment created successfully"
}

# Create Storage Transfer Job configuration
create_transfer_job_config() {
    log "Creating Storage Transfer Job configuration..."
    
    # Create transfer job configuration file
    cat > transfer-job-config.json <<EOF
{
  "description": "Cross-cloud data migration job",
  "projectId": "${PROJECT_ID}",
  "transferSpec": {
    "awsS3DataSource": {
      "bucketName": "your-source-bucket",
      "awsAccessKey": {
        "accessKeyId": "YOUR_AWS_ACCESS_KEY",
        "secretAccessKey": "YOUR_AWS_SECRET_KEY"
      }
    },
    "gcsDataSink": {
      "bucketName": "${STAGING_BUCKET}"
    },
    "transferOptions": {
      "overwriteObjectsAlreadyExistingInSink": false,
      "deleteObjectsUniqueInSink": false,
      "deleteObjectsFromSourceAfterTransfer": false
    }
  },
  "schedule": {
    "scheduleStartDate": {
      "year": $(date +%Y),
      "month": $(date +%m),
      "day": $(date +%d)
    }
  },
  "status": "ENABLED"
}
EOF
    
    log "Transfer job configuration created"
    warn "Please update source bucket and credentials in transfer-job-config.json"
}

# Deploy Airflow DAG
deploy_airflow_dag() {
    log "Deploying Airflow DAG for migration orchestration..."
    
    # Get Composer environment bucket
    if [ "$DRY_RUN" != "true" ]; then
        COMPOSER_BUCKET=$(gcloud composer environments describe ${COMPOSER_ENV_NAME} \
            --location ${REGION} \
            --format="get(config.dagGcsPrefix)" | sed 's|/dags||')
    else
        COMPOSER_BUCKET="gs://composer-bucket-${RANDOM_SUFFIX}"
    fi
    
    # Create the migration DAG
    info "Creating migration orchestrator DAG..."
    cat > migration_orchestrator.py <<'EOF'
from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.google.cloud.operators.storage_transfer import (
    CloudDataTransferServiceCreateJobOperator,
    CloudDataTransferServiceGetOperationOperator
)
from airflow.providers.google.cloud.operators.gcs import (
    GCSListObjectsOperator,
    GCSDeleteObjectsOperator
)
from airflow.providers.google.cloud.sensors.storage_transfer import (
    CloudDataTransferServiceJobStatusSensor
)
from airflow.operators.python import PythonOperator
import os

# Default arguments for the DAG
default_args = {
    'owner': 'data-engineering',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5)
}

# Create the DAG
dag = DAG(
    'cross_cloud_data_migration',
    default_args=default_args,
    description='Orchestrate cross-cloud data migration',
    schedule_interval='@daily',
    catchup=False,
    max_active_runs=1
)

# Environment variables from Composer
STAGING_BUCKET = os.environ.get('STAGING_BUCKET')
TARGET_BUCKET = os.environ.get('TARGET_BUCKET')
PROJECT_ID = os.environ.get('PROJECT_ID')

def validate_migration_data(**context):
    """Validate migrated data integrity"""
    print(f"Validating data in {STAGING_BUCKET}")
    # Add your data validation logic here
    return "validation_passed"

def move_to_production(**context):
    """Move validated data to production bucket"""
    print(f"Moving data from {STAGING_BUCKET} to {TARGET_BUCKET}")
    # Add your data movement logic here
    return "move_completed"

# Create transfer job
create_transfer_job = CloudDataTransferServiceCreateJobOperator(
    task_id='create_transfer_job',
    body={
        'description': 'Daily cross-cloud migration',
        'transferSpec': {
            'gcsDataSource': {'bucketName': 'source-bucket'},
            'gcsDataSink': {'bucketName': STAGING_BUCKET}
        },
        'schedule': {
            'scheduleStartDate': {'year': 2024, 'month': 1, 'day': 1}
        }
    },
    dag=dag
)

# Monitor transfer job
wait_for_transfer = CloudDataTransferServiceJobStatusSensor(
    task_id='wait_for_transfer_completion',
    job_name="{{ task_instance.xcom_pull('create_transfer_job') }}",
    expected_statuses=['SUCCESS'],
    timeout=3600,
    poke_interval=300,
    dag=dag
)

# Validate migrated data
validate_data = PythonOperator(
    task_id='validate_migration_data',
    python_callable=validate_migration_data,
    dag=dag
)

# Move to production
move_to_prod = PythonOperator(
    task_id='move_to_production',
    python_callable=move_to_production,
    dag=dag
)

# Define task dependencies
create_transfer_job >> wait_for_transfer >> validate_data >> move_to_prod
EOF
    
    # Upload DAG to Composer environment
    info "Uploading DAG to Composer environment..."
    $GSUTIL_CMD cp migration_orchestrator.py ${COMPOSER_BUCKET}/dags/
    
    # Clean up local DAG file
    if [ "$DRY_RUN" != "true" ]; then
        rm -f migration_orchestrator.py
    fi
    
    log "Migration DAG deployed to Cloud Composer"
}

# Configure Cloud Logging
configure_logging() {
    log "Configuring Cloud Logging for migration monitoring..."
    
    # Create log sink for Storage Transfer Service
    info "Creating log sink for Storage Transfer Service..."
    $GCLOUD_CMD logging sinks create storage-transfer-sink \
        storage.googleapis.com/${TARGET_BUCKET}/logs \
        --log-filter='resource.type="storage_transfer_job"' \
        --quiet || true
    
    # Create log sink for Cloud Composer
    info "Creating log sink for Cloud Composer..."
    $GCLOUD_CMD logging sinks create composer-migration-sink \
        storage.googleapis.com/${TARGET_BUCKET}/composer-logs \
        --log-filter='resource.type="gce_instance" AND resource.labels.instance_name:"composer"' \
        --quiet || true
    
    # Grant sink permissions
    if [ "$DRY_RUN" != "true" ]; then
        SINK_SA=$(gcloud logging sinks describe storage-transfer-sink \
            --format="value(writerIdentity)" 2>/dev/null || echo "serviceAccount:dummy@example.com")
        
        $GSUTIL_CMD iam ch ${SINK_SA}:roles/storage.objectCreator \
            gs://${TARGET_BUCKET} || true
    fi
    
    log "Cloud Logging configured for migration monitoring"
}

# Create monitoring alerts
create_monitoring_alerts() {
    log "Creating monitoring alerts..."
    
    # Create monitoring policy for transfer failures
    info "Creating alert policy for transfer failures..."
    cat > alert-policy.json <<EOF
{
  "displayName": "Storage Transfer Job Failures",
  "conditions": [
    {
      "displayName": "Transfer job failure rate",
      "conditionThreshold": {
        "filter": "resource.type=\"storage_transfer_job\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_RATE",
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ]
      }
    }
  ],
  "enabled": true,
  "alertStrategy": {
    "autoClose": "86400s"
  }
}
EOF
    
    # Create the alert policy
    $GCLOUD_CMD alpha monitoring policies create --policy-from-file=alert-policy.json --quiet || true
    
    # Clean up policy file
    if [ "$DRY_RUN" != "true" ]; then
        rm -f alert-policy.json
    fi
    
    log "Monitoring alerts configured for migration pipeline"
}

# Main deployment function
main() {
    log "Starting deployment of Cross-Cloud Data Migration infrastructure..."
    
    # Check prerequisites
    check_prerequisites
    
    # Load configuration
    load_configuration
    
    # Configure gcloud
    configure_gcloud
    
    # Enable APIs
    enable_apis
    
    # Create storage buckets
    create_storage_buckets
    
    # Create service account
    create_service_account
    
    # Create Composer environment
    create_composer_environment
    
    # Create transfer job configuration
    create_transfer_job_config
    
    # Deploy Airflow DAG
    deploy_airflow_dag
    
    # Configure logging
    configure_logging
    
    # Create monitoring alerts
    create_monitoring_alerts
    
    log "Deployment completed successfully!"
    
    # Print summary
    info "=== DEPLOYMENT SUMMARY ==="
    info "Project ID: $PROJECT_ID"
    info "Region: $REGION"
    info "Composer Environment: $COMPOSER_ENV_NAME"
    info "Staging Bucket: gs://$STAGING_BUCKET"
    info "Target Bucket: gs://$TARGET_BUCKET"
    info "Service Account: $TRANSFER_SA_EMAIL"
    info ""
    info "Next steps:"
    info "1. Update transfer-job-config.json with your source bucket credentials"
    info "2. Access the Airflow UI to monitor DAG execution"
    info "3. Configure your source system for data migration"
    info ""
    warn "Remember to run destroy.sh when you're done to avoid ongoing charges"
}

# Run main function
main "$@"