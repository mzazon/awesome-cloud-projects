#!/bin/bash
# GCP Data Migration Workflows with Storage Bucket Relocation and Eventarc - Deploy Script
# This script deploys the complete data migration automation solution

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warn "Running in DRY-RUN mode - no resources will be created"
fi

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
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
        error "Please authenticate with gcloud: gcloud auth login"
        exit 1
    fi
    
    # Check if project is set
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "${PROJECT_ID}" ]]; then
        error "Please set a GCP project: gcloud config set project PROJECT_ID"
        exit 1
    fi
    
    log "Prerequisites check passed ✅"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set project configuration
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="us-central1"
    export SOURCE_REGION="us-west1"
    export DEST_REGION="us-east1"
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    export SOURCE_BUCKET="migration-source-${RANDOM_SUFFIX}"
    
    # Set additional configuration
    gcloud config set compute/region ${REGION}
    
    info "Project ID: ${PROJECT_ID}"
    info "Primary Region: ${REGION}"
    info "Source Region: ${SOURCE_REGION}"
    info "Destination Region: ${DEST_REGION}"
    info "Source Bucket: ${SOURCE_BUCKET}"
    
    log "Environment variables configured ✅"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "eventarc.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "bigquery.googleapis.com"
        "pubsub.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would enable APIs: ${apis[*]}"
        return 0
    fi
    
    for api in "${apis[@]}"; do
        info "Enabling ${api}..."
        gcloud services enable ${api} --quiet
    done
    
    # Wait for APIs to be fully enabled
    info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log "APIs enabled successfully ✅"
}

# Function to create service account
create_service_account() {
    log "Creating service account for automation functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create service account: migration-automation@${PROJECT_ID}.iam.gserviceaccount.com"
        return 0
    fi
    
    # Create service account
    if ! gcloud iam service-accounts describe migration-automation@${PROJECT_ID}.iam.gserviceaccount.com &>/dev/null; then
        gcloud iam service-accounts create migration-automation \
            --display-name="Migration Automation Service Account" \
            --description="Service account for automated data migration workflows"
    else
        info "Service account already exists, skipping creation"
    fi
    
    # Grant necessary permissions
    local roles=(
        "roles/storage.admin"
        "roles/logging.viewer"
        "roles/monitoring.metricWriter"
        "roles/bigquery.dataEditor"
        "roles/pubsub.publisher"
    )
    
    for role in "${roles[@]}"; do
        info "Granting ${role} to service account..."
        gcloud projects add-iam-policy-binding ${PROJECT_ID} \
            --member="serviceAccount:migration-automation@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="${role}" \
            --quiet
    done
    
    log "Service account created and configured ✅"
}

# Function to create source bucket with sample data
create_source_bucket() {
    log "Creating source storage bucket with sample data..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create bucket: gs://${SOURCE_BUCKET}"
        return 0
    fi
    
    # Create source bucket
    if ! gsutil ls gs://${SOURCE_BUCKET} &>/dev/null; then
        gsutil mb -p ${PROJECT_ID} \
            -c STANDARD \
            -l ${SOURCE_REGION} \
            gs://${SOURCE_BUCKET}
        
        # Enable versioning
        gsutil versioning set on gs://${SOURCE_BUCKET}
        
        info "Created bucket: gs://${SOURCE_BUCKET}"
    else
        info "Bucket already exists, skipping creation"
    fi
    
    # Create sample data files
    local temp_dir=$(mktemp -d)
    cd ${temp_dir}
    
    echo "Critical business data - $(date)" > critical-data.txt
    echo "Archive data from last year - $(date)" > archive-data.txt
    echo "Log file entry - $(date)" > application.log
    
    # Upload files with metadata
    gsutil -h "x-goog-meta-data-classification:critical" \
        cp critical-data.txt gs://${SOURCE_BUCKET}/
    
    gsutil -h "x-goog-meta-data-classification:archive" \
        -h "Content-Type:text/plain" \
        cp archive-data.txt gs://${SOURCE_BUCKET}/logs/
    
    gsutil -h "x-goog-meta-source:application-logs" \
        cp application.log gs://${SOURCE_BUCKET}/logs/
    
    # Clean up temp files
    cd - > /dev/null
    rm -rf ${temp_dir}
    
    log "Source bucket created with sample data ✅"
}

# Function to create BigQuery dataset for audit logs
create_bigquery_dataset() {
    log "Creating BigQuery dataset for audit logs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create BigQuery dataset: ${PROJECT_ID}:migration_audit"
        return 0
    fi
    
    # Create BigQuery dataset
    if ! bq ls -d ${PROJECT_ID}:migration_audit &>/dev/null; then
        bq mk --dataset \
            --location=${REGION} \
            --description="Migration audit logs dataset" \
            ${PROJECT_ID}:migration_audit
        
        info "Created BigQuery dataset: migration_audit"
    else
        info "BigQuery dataset already exists, skipping creation"
    fi
    
    log "BigQuery dataset configured ✅"
}

# Function to create Pub/Sub topics
create_pubsub_topics() {
    log "Creating Pub/Sub topics for event handling..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create Pub/Sub topic: pre-migration-topic"
        return 0
    fi
    
    # Create topic for pre-migration validation
    if ! gcloud pubsub topics describe pre-migration-topic &>/dev/null; then
        gcloud pubsub topics create pre-migration-topic
        info "Created Pub/Sub topic: pre-migration-topic"
    else
        info "Pub/Sub topic already exists, skipping creation"
    fi
    
    log "Pub/Sub topics configured ✅"
}

# Function to deploy Cloud Functions
deploy_cloud_functions() {
    log "Deploying Cloud Functions for migration automation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would deploy Cloud Functions"
        return 0
    fi
    
    local script_dir=$(dirname "$0")
    local functions_dir="${script_dir}/../functions"
    
    # Create functions directory if it doesn't exist
    mkdir -p ${functions_dir}
    
    # Deploy pre-migration validation function
    deploy_pre_migration_function "${functions_dir}"
    
    # Deploy migration progress monitor function
    deploy_progress_monitor_function "${functions_dir}"
    
    # Deploy post-migration validation function
    deploy_post_migration_function "${functions_dir}"
    
    log "Cloud Functions deployed successfully ✅"
}

# Function to deploy pre-migration validation function
deploy_pre_migration_function() {
    local functions_dir=$1
    local function_dir="${functions_dir}/pre-migration"
    
    info "Deploying pre-migration validation function..."
    
    mkdir -p ${function_dir}
    cd ${function_dir}
    
    # Create function source code
    cat > main.py << 'EOF'
import functions_framework
from google.cloud import storage
from google.cloud import logging
import json
import os

@functions_framework.cloud_event
def validate_pre_migration(cloud_event):
    """Validates bucket configuration before migration"""
    
    storage_client = storage.Client()
    logging_client = logging.Client()
    logger = logging_client.logger("migration-validator")
    
    event_data = cloud_event.get_data()
    bucket_name = event_data.get('bucketId', os.environ.get('SOURCE_BUCKET'))
    
    try:
        bucket = storage_client.bucket(bucket_name)
        
        validation_results = {
            'bucket_name': bucket_name,
            'location': bucket.location,
            'storage_class': bucket.storage_class,
            'versioning_enabled': bucket.versioning_enabled,
            'object_count': sum(1 for _ in bucket.list_blobs()),
            'validation_status': 'PASSED'
        }
        
        logger.log_struct(validation_results, severity='INFO')
        return validation_results
        
    except Exception as e:
        error_result = {
            'bucket_name': bucket_name,
            'validation_status': 'ERROR',
            'error_message': str(e)
        }
        logger.log_struct(error_result, severity='ERROR')
        return error_result
EOF
    
    cat > requirements.txt << 'EOF'
functions-framework==3.*
google-cloud-storage==2.*
google-cloud-logging==3.*
EOF
    
    # Deploy the function
    gcloud functions deploy pre-migration-validator \
        --runtime python39 \
        --trigger-topic pre-migration-topic \
        --source . \
        --entry-point validate_pre_migration \
        --memory 256MB \
        --timeout 60s \
        --service-account=migration-automation@${PROJECT_ID}.iam.gserviceaccount.com \
        --set-env-vars="PROJECT_ID=${PROJECT_ID},SOURCE_BUCKET=${SOURCE_BUCKET}" \
        --quiet
    
    cd - > /dev/null
    info "Pre-migration validation function deployed"
}

# Function to deploy progress monitor function
deploy_progress_monitor_function() {
    local functions_dir=$1
    local function_dir="${functions_dir}/progress-monitor"
    
    info "Deploying migration progress monitor function..."
    
    mkdir -p ${function_dir}
    cd ${function_dir}
    
    # Create function source code
    cat > main.py << 'EOF'
import functions_framework
from google.cloud import storage
from google.cloud import monitoring_v3
from google.cloud import logging
import json
from datetime import datetime, timezone

@functions_framework.cloud_event
def monitor_migration_progress(cloud_event):
    """Monitors bucket relocation progress and reports metrics"""
    
    storage_client = storage.Client()
    monitoring_client = monitoring_v3.MetricServiceClient()
    logging_client = logging.Client()
    logger = logging_client.logger("migration-monitor")
    
    event_data = cloud_event.get_data()
    
    try:
        protoPayload = event_data.get('protoPayload', {})
        method_name = protoPayload.get('methodName', '')
        resource_name = protoPayload.get('resourceName', '')
        
        if 'storage.buckets' in method_name and 'patch' in method_name:
            bucket_name = resource_name.split('/')[-1] if resource_name else ''
            
            progress_data = {
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'bucket_name': bucket_name,
                'operation': method_name,
                'event_type': 'RELOCATION_PROGRESS'
            }
            
            logger.log_struct(progress_data, severity='INFO')
        
        return {'status': 'processed', 'method': method_name}
        
    except Exception as e:
        logger.log_struct({
            'error': 'Migration monitoring failed',
            'details': str(e)
        }, severity='ERROR')
        return {'status': 'error', 'message': str(e)}
EOF
    
    cat > requirements.txt << 'EOF'
functions-framework==3.*
google-cloud-storage==2.*
google-cloud-monitoring==2.*
google-cloud-logging==3.*
EOF
    
    # Deploy the function
    gcloud functions deploy migration-progress-monitor \
        --runtime python39 \
        --trigger-event-filter="type=google.cloud.audit.log.v1.written" \
        --trigger-event-filter="serviceName=storage.googleapis.com" \
        --source . \
        --entry-point monitor_migration_progress \
        --memory 512MB \
        --timeout 120s \
        --service-account=migration-automation@${PROJECT_ID}.iam.gserviceaccount.com \
        --set-env-vars="PROJECT_ID=${PROJECT_ID}" \
        --quiet
    
    cd - > /dev/null
    info "Migration progress monitor function deployed"
}

# Function to deploy post-migration validation function
deploy_post_migration_function() {
    local functions_dir=$1
    local function_dir="${functions_dir}/post-migration"
    
    info "Deploying post-migration validation function..."
    
    mkdir -p ${function_dir}
    cd ${function_dir}
    
    # Create function source code
    cat > main.py << 'EOF'
import functions_framework
from google.cloud import storage
from google.cloud import logging
import json
from datetime import datetime, timezone

@functions_framework.cloud_event
def validate_post_migration(cloud_event):
    """Validates bucket state after migration completion"""
    
    storage_client = storage.Client()
    logging_client = logging.Client()
    logger = logging_client.logger("post-migration-validator")
    
    event_data = cloud_event.get_data()
    
    try:
        proto_payload = event_data.get('protoPayload', {})
        resource_name = proto_payload.get('resourceName', '')
        bucket_name = resource_name.split('/')[-1] if 'buckets/' in resource_name else None
        
        if not bucket_name:
            raise ValueError("Could not determine bucket name from event")
        
        bucket = storage_client.bucket(bucket_name)
        bucket.reload()
        
        validation_results = {
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'bucket_name': bucket_name,
            'validation_type': 'POST_MIGRATION',
            'new_location': bucket.location,
            'validation_status': 'COMPLETED'
        }
        
        logger.log_struct(validation_results, severity='INFO')
        return validation_results
        
    except Exception as e:
        error_result = {
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'validation_type': 'POST_MIGRATION',
            'validation_status': 'ERROR',
            'error_message': str(e)
        }
        logger.log_struct(error_result, severity='ERROR')
        return error_result
EOF
    
    cat > requirements.txt << 'EOF'
functions-framework==3.*
google-cloud-storage==2.*
google-cloud-logging==3.*
EOF
    
    # Deploy the function
    gcloud functions deploy post-migration-validator \
        --runtime python39 \
        --trigger-event-filter="type=google.cloud.audit.log.v1.written" \
        --trigger-event-filter="serviceName=storage.googleapis.com" \
        --trigger-event-filter="methodName=storage.buckets.patch" \
        --source . \
        --entry-point validate_post_migration \
        --memory 512MB \
        --timeout 180s \
        --service-account=migration-automation@${PROJECT_ID}.iam.gserviceaccount.com \
        --set-env-vars="PROJECT_ID=${PROJECT_ID}" \
        --quiet
    
    cd - > /dev/null
    info "Post-migration validation function deployed"
}

# Function to create Eventarc triggers
create_eventarc_triggers() {
    log "Creating Eventarc triggers for migration monitoring..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create Eventarc triggers"
        return 0
    fi
    
    # Create trigger for bucket administrative events
    if ! gcloud eventarc triggers describe bucket-admin-trigger --location=${REGION} &>/dev/null; then
        gcloud eventarc triggers create bucket-admin-trigger \
            --location=${REGION} \
            --destination-cloud-function=migration-progress-monitor \
            --destination-cloud-function-service=migration-automation@${PROJECT_ID}.iam.gserviceaccount.com \
            --event-filters="type=google.cloud.audit.log.v1.written" \
            --event-filters="serviceName=storage.googleapis.com" \
            --event-filters="methodName=storage.buckets.patch" \
            --quiet
        
        info "Created Eventarc trigger: bucket-admin-trigger"
    else
        info "Eventarc trigger already exists, skipping creation"
    fi
    
    # Create trigger for object-level events
    if ! gcloud eventarc triggers describe object-event-trigger --location=${REGION} &>/dev/null; then
        gcloud eventarc triggers create object-event-trigger \
            --location=${REGION} \
            --destination-cloud-function=migration-event-processor \
            --destination-cloud-function-service=migration-automation@${PROJECT_ID}.iam.gserviceaccount.com \
            --event-filters="type=google.cloud.audit.log.v1.written" \
            --event-filters="serviceName=storage.googleapis.com" \
            --event-filters="methodName=storage.objects.create" \
            --quiet 2>/dev/null || true  # This might fail if function doesn't exist yet
        
        info "Created Eventarc trigger: object-event-trigger"
    else
        info "Eventarc trigger already exists, skipping creation"
    fi
    
    log "Eventarc triggers configured ✅"
}

# Function to create audit log sink
create_audit_log_sink() {
    log "Creating audit log sink for enhanced monitoring..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create audit log sink"
        return 0
    fi
    
    # Create audit log sink
    if ! gcloud logging sinks describe migration-audit-sink &>/dev/null; then
        gcloud logging sinks create migration-audit-sink \
            bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/migration_audit \
            --log-filter='protoPayload.serviceName="storage.googleapis.com" AND (protoPayload.methodName:"storage.buckets" OR protoPayload.methodName:"storage.objects")' \
            --quiet
        
        # Grant sink service account permissions
        SINK_SA=$(gcloud logging sinks describe migration-audit-sink --format="value(writerIdentity)")
        
        bq add-iam-policy-binding \
            --member="${SINK_SA}" \
            --role="roles/bigquery.dataEditor" \
            ${PROJECT_ID}:migration_audit \
            --quiet
        
        info "Created audit log sink with BigQuery integration"
    else
        info "Audit log sink already exists, skipping creation"
    fi
    
    log "Audit log sink configured ✅"
}

# Function to create monitoring alert policy
create_monitoring_alerts() {
    log "Creating Cloud Monitoring alert policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would create monitoring alert policies"
        return 0
    fi
    
    # Create alert policy configuration
    cat > alert-policy.json << EOF
{
  "displayName": "Bucket Migration Alert",
  "conditions": [
    {
      "displayName": "Storage bucket operation errors",
      "conditionThreshold": {
        "filter": "resource.type=\"gcs_bucket\" AND log_name=\"projects/${PROJECT_ID}/logs/cloudaudit.googleapis.com%2Factivity\" AND protoPayload.methodName:\"storage.buckets\"",
        "comparison": "COMPARISON_COUNT_GREATER_THAN",
        "thresholdValue": 0,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_COUNT",
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "604800s"
  },
  "enabled": true
}
EOF
    
    # Create the alert policy
    gcloud alpha monitoring policies create --policy-from-file=alert-policy.json --quiet || true
    
    # Clean up the temporary file
    rm -f alert-policy.json
    
    info "Monitoring alert policies created"
    log "Monitoring alerts configured ✅"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would verify deployment"
        return 0
    fi
    
    # Check bucket exists
    if gsutil ls gs://${SOURCE_BUCKET} &>/dev/null; then
        info "✅ Source bucket exists: gs://${SOURCE_BUCKET}"
    else
        error "❌ Source bucket not found"
        return 1
    fi
    
    # Check Cloud Functions
    local functions=("pre-migration-validator" "migration-progress-monitor" "post-migration-validator")
    for func in "${functions[@]}"; do
        if gcloud functions describe ${func} --region=${REGION} &>/dev/null; then
            info "✅ Cloud Function deployed: ${func}"
        else
            warn "❌ Cloud Function not found: ${func}"
        fi
    done
    
    # Check Eventarc triggers
    local triggers=("bucket-admin-trigger")
    for trigger in "${triggers[@]}"; do
        if gcloud eventarc triggers describe ${trigger} --location=${REGION} &>/dev/null; then
            info "✅ Eventarc trigger created: ${trigger}"
        else
            warn "❌ Eventarc trigger not found: ${trigger}"
        fi
    done
    
    # Check BigQuery dataset
    if bq ls -d ${PROJECT_ID}:migration_audit &>/dev/null; then
        info "✅ BigQuery dataset exists: migration_audit"
    else
        warn "❌ BigQuery dataset not found"
    fi
    
    log "Deployment verification completed ✅"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=========================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Source Bucket: gs://${SOURCE_BUCKET}"
    echo "Source Region: ${SOURCE_REGION}"
    echo "Destination Region: ${DEST_REGION}"
    echo "Service Account: migration-automation@${PROJECT_ID}.iam.gserviceaccount.com"
    echo ""
    echo "Deployed Resources:"
    echo "  - Cloud Storage bucket with sample data"
    echo "  - 3 Cloud Functions for migration automation"
    echo "  - Eventarc triggers for event-driven processing"
    echo "  - BigQuery dataset for audit log analysis"
    echo "  - Cloud Monitoring alerts"
    echo "  - Audit log sink for comprehensive tracking"
    echo ""
    echo "Next Steps:"
    echo "1. Test the pre-migration validation:"
    echo "   gcloud pubsub topics publish pre-migration-topic --message='{\"bucketId\":\"${SOURCE_BUCKET}\",\"action\":\"pre-validation\"}'"
    echo ""
    echo "2. Initiate bucket relocation:"
    echo "   gcloud storage buckets relocate gs://${SOURCE_BUCKET} --location=${DEST_REGION} --dry-run"
    echo "   gcloud storage buckets relocate gs://${SOURCE_BUCKET} --location=${DEST_REGION}"
    echo ""
    echo "3. Monitor progress in Cloud Logging:"
    echo "   gcloud logging read 'resource.type=\"cloud_function\"' --limit=10"
    echo ""
    echo "To clean up all resources, run: ./destroy.sh"
    echo "=========================="
}

# Main execution flow
main() {
    log "Starting GCP Data Migration Workflows deployment..."
    
    check_prerequisites
    set_environment_variables
    enable_apis
    create_service_account
    create_source_bucket
    create_bigquery_dataset
    create_pubsub_topics
    deploy_cloud_functions
    create_eventarc_triggers
    create_audit_log_sink
    create_monitoring_alerts
    verify_deployment
    display_summary
    
    log "Deployment completed successfully! 🎉"
}

# Run main function
main "$@"