#!/bin/bash

# Infrastructure Cost Optimization with Cloud Batch and Cloud Monitoring - Deployment Script
# This script deploys a complete cost optimization automation system using GCP services

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "gcloud is not authenticated. Please run 'gcloud auth login'."
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        error "bq CLI is not available. Please ensure Google Cloud SDK is properly installed."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is not available. Please install openssl for random string generation."
    fi
    
    success "All prerequisites satisfied"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Use existing project if PROJECT_ID is set, otherwise create new one
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="cost-opt-$(date +%s)"
        warn "PROJECT_ID not set. Using generated project ID: ${PROJECT_ID}"
        warn "Make sure this project exists or create it manually."
    fi
    
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="cost-optimization-${RANDOM_SUFFIX}"
    export DATASET_NAME="cost_analytics_${RANDOM_SUFFIX//-/_}"
    export BATCH_JOB_NAME="infra-analysis-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="cost-optimizer-${RANDOM_SUFFIX}"
    
    # Create environment file for cleanup
    cat > .env << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
BUCKET_NAME=${BUCKET_NAME}
DATASET_NAME=${DATASET_NAME}
BATCH_JOB_NAME=${BATCH_JOB_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log "Environment variables configured:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  BUCKET_NAME: ${BUCKET_NAME}"
    log "  DATASET_NAME: ${DATASET_NAME}"
}

# Configure gcloud settings
configure_gcloud() {
    log "Configuring gcloud settings..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" || error "Failed to set project ${PROJECT_ID}"
    gcloud config set compute/region "${REGION}" || error "Failed to set region ${REGION}"
    gcloud config set compute/zone "${ZONE}" || error "Failed to set zone ${ZONE}"
    
    success "gcloud configured successfully"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "batch.googleapis.com"
        "monitoring.googleapis.com"
        "cloudfunctions.googleapis.com"
        "bigquery.googleapis.com"
        "storage.googleapis.com"
        "compute.googleapis.com"
        "pubsub.googleapis.com"
        "run.googleapis.com"
        "cloudscheduler.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            success "Enabled ${api}"
        else
            error "Failed to enable ${api}"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All APIs enabled successfully"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..."
    
    # Create storage bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        success "Storage bucket created: gs://${BUCKET_NAME}"
    else
        error "Failed to create storage bucket"
    fi
    
    # Create lifecycle policy
    cat > lifecycle.json << EOF
{
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
EOF
    
    # Apply lifecycle policy
    if gsutil lifecycle set lifecycle.json "gs://${BUCKET_NAME}"; then
        success "Lifecycle policy applied to bucket"
    else
        error "Failed to apply lifecycle policy"
    fi
    
    # Clean up temporary file
    rm -f lifecycle.json
}

# Create BigQuery dataset
create_bigquery_dataset() {
    log "Creating BigQuery dataset..."
    
    # Create dataset
    if bq mk --dataset --location="${REGION}" \
        --description="Infrastructure cost optimization analytics" \
        "${PROJECT_ID}:${DATASET_NAME}"; then
        success "BigQuery dataset created: ${DATASET_NAME}"
    else
        error "Failed to create BigQuery dataset"
    fi
    
    # Create resource utilization table
    log "Creating resource utilization table..."
    if bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.resource_utilization" \
        timestamp:TIMESTAMP,resource_id:STRING,resource_type:STRING,cpu_utilization:FLOAT,memory_utilization:FLOAT,cost_per_hour:FLOAT,recommendation:STRING; then
        success "Resource utilization table created"
    else
        error "Failed to create resource utilization table"
    fi
    
    # Create optimization actions table
    log "Creating optimization actions table..."
    if bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.optimization_actions" \
        timestamp:TIMESTAMP,resource_id:STRING,action_type:STRING,estimated_savings:FLOAT,status:STRING; then
        success "Optimization actions table created"
    else
        error "Failed to create optimization actions table"
    fi
}

# Create Pub/Sub topics and subscriptions
create_pubsub_resources() {
    log "Creating Pub/Sub resources..."
    
    # Create cost optimization events topic
    if gcloud pubsub topics create cost-optimization-events; then
        success "Cost optimization events topic created"
    else
        error "Failed to create cost optimization events topic"
    fi
    
    # Create subscription for cost optimization processor
    if gcloud pubsub subscriptions create cost-optimization-processor \
        --topic=cost-optimization-events; then
        success "Cost optimization processor subscription created"
    else
        error "Failed to create cost optimization processor subscription"
    fi
    
    # Create batch job notifications topic
    if gcloud pubsub topics create batch-job-notifications; then
        success "Batch job notifications topic created"
    else
        error "Failed to create batch job notifications topic"
    fi
    
    # Create subscription for batch completion handler
    if gcloud pubsub subscriptions create batch-completion-handler \
        --topic=batch-job-notifications; then
        success "Batch completion handler subscription created"
    else
        error "Failed to create batch completion handler subscription"
    fi
}

# Create Cloud Function
create_cloud_function() {
    log "Creating Cloud Function for cost optimization..."
    
    # Create directory for function code
    mkdir -p cost-optimizer-function
    cd cost-optimizer-function
    
    # Create the optimization function
    cat > main.py << 'EOF'
import json
import logging
from google.cloud import compute_v1
from google.cloud import monitoring_v3
from google.cloud import bigquery
import functions_framework
import os
from datetime import datetime, timezone

@functions_framework.http
def optimize_infrastructure(request):
    """HTTP Cloud Function to process cost optimization recommendations."""
    
    project_id = os.environ.get('PROJECT_ID')
    dataset_name = os.environ.get('DATASET_NAME')
    
    try:
        # Initialize Google Cloud clients
        compute_client = compute_v1.InstancesClient()
        monitoring_client = monitoring_v3.MetricServiceClient()
        bq_client = bigquery.Client()
        
        logging.info(f"Starting cost optimization analysis for project: {project_id}")
        
        # Get resource utilization data
        instances = list_compute_instances(compute_client, project_id)
        
        # Generate optimization recommendations
        recommendations = generate_recommendations(instances)
        
        # Log recommendations to BigQuery if dataset exists
        if dataset_name:
            log_recommendations(bq_client, project_id, dataset_name, recommendations)
        
        response_data = {
            'status': 'success',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'processed_instances': len(instances),
            'recommendations': len(recommendations),
            'project_id': project_id
        }
        
        logging.info(f"Cost optimization completed: {response_data}")
        return response_data, 200
        
    except Exception as e:
        logging.error(f"Error in cost optimization: {str(e)}")
        return {
            'status': 'error', 
            'message': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }, 500

def list_compute_instances(compute_client, project_id):
    """List all compute instances in the project."""
    instances = []
    try:
        # List instances across all zones
        zones_client = compute_v1.ZonesClient()
        zones = zones_client.list(project=project_id)
        
        for zone in zones:
            zone_instances = compute_client.list(project=project_id, zone=zone.name)
            for instance in zone_instances:
                instances.append({
                    'name': instance.name,
                    'zone': zone.name,
                    'machine_type': instance.machine_type.split('/')[-1],
                    'status': instance.status
                })
    except Exception as e:
        logging.warning(f"Error listing instances: {str(e)}")
    
    return instances

def generate_recommendations(instances):
    """Generate cost optimization recommendations based on instance data."""
    recommendations = []
    
    for instance in instances:
        # Simple heuristic: recommend downsizing for running instances
        if instance.get('status') == 'RUNNING':
            recommendations.append({
                'resource_id': instance.get('name'),
                'resource_type': 'compute_instance',
                'action_type': 'rightsize',
                'estimated_savings': 25.0,  # Placeholder savings
                'recommendation': f"Consider rightsizing instance {instance.get('name')} based on utilization patterns"
            })
    
    return recommendations

def log_recommendations(bq_client, project_id, dataset_name, recommendations):
    """Log recommendations to BigQuery for tracking and analysis."""
    try:
        table_id = f"{project_id}.{dataset_name}.optimization_actions"
        table = bq_client.get_table(table_id)
        
        rows_to_insert = []
        for rec in recommendations:
            rows_to_insert.append({
                'timestamp': datetime.now(timezone.utc),
                'resource_id': rec.get('resource_id', ''),
                'action_type': rec.get('action_type', ''),
                'estimated_savings': rec.get('estimated_savings', 0.0),
                'status': 'pending'
            })
        
        if rows_to_insert:
            errors = bq_client.insert_rows_json(table, rows_to_insert)
            if errors:
                logging.error(f"BigQuery insert errors: {errors}")
            else:
                logging.info(f"Successfully logged {len(rows_to_insert)} recommendations to BigQuery")
    
    except Exception as e:
        logging.error(f"Error logging to BigQuery: {str(e)}")
EOF
    
    # Create requirements.txt
    cat > requirements.txt << EOF
google-cloud-compute>=1.15.0
google-cloud-monitoring>=2.15.0
google-cloud-bigquery>=3.11.0
functions-framework>=3.4.0
EOF
    
    # Deploy the Cloud Function
    log "Deploying Cloud Function..."
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime=python311 \
        --region="${REGION}" \
        --source=. \
        --entry-point=optimize_infrastructure \
        --trigger=http \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},DATASET_NAME=${DATASET_NAME}" \
        --allow-unauthenticated \
        --timeout=540s \
        --memory=256Mi; then
        success "Cloud Function deployed: ${FUNCTION_NAME}"
    else
        error "Failed to deploy Cloud Function"
    fi
    
    cd ..
}

# Create batch job configuration
create_batch_job_config() {
    log "Creating Cloud Batch job configuration..."
    
    # Create directory for batch job configuration
    mkdir -p batch-configs
    
    # Create batch job definition
    cat > batch-configs/cost-analysis-job.json << EOF
{
  "taskGroups": [
    {
      "taskSpec": {
        "runnables": [
          {
            "container": {
              "imageUri": "gcr.io/google-containers/toolbox",
              "commands": [
                "/bin/bash",
                "-c",
                "echo 'Starting infrastructure cost analysis...' && gcloud compute instances list --format=json > /tmp/instances.json && gsutil cp /tmp/instances.json gs://${BUCKET_NAME}/analysis/instances-\$(date +%Y%m%d-%H%M%S).json && echo 'Analysis completed successfully'"
              ]
            }
          }
        ],
        "computeResource": {
          "cpuMilli": 1000,
          "memoryMib": 2048
        },
        "environment": {
          "variables": {
            "PROJECT_ID": "${PROJECT_ID}",
            "BUCKET_NAME": "${BUCKET_NAME}"
          }
        }
      },
      "taskCount": 1,
      "parallelism": 1
    }
  ],
  "allocationPolicy": {
    "instances": [
      {
        "policy": {
          "machineType": "e2-standard-2",
          "provisioningModel": "PREEMPTIBLE"
        }
      }
    ]
  },
  "logsPolicy": {
    "destination": "CLOUD_LOGGING"
  }
}
EOF
    
    success "Batch job configuration created"
}

# Create monitoring alert policy
create_monitoring_alerts() {
    log "Creating Cloud Monitoring alert policies..."
    
    # Create alert policy configuration
    cat > alert-policy.json << EOF
{
  "displayName": "High Infrastructure Costs Alert - ${RANDOM_SUFFIX}",
  "conditions": [
    {
      "displayName": "CPU utilization below 10%",
      "conditionThreshold": {
        "filter": "resource.type=\"gce_instance\"",
        "comparison": "COMPARISON_LESS_THAN",
        "thresholdValue": 0.1,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ]
      }
    }
  ],
  "notificationChannels": [],
  "enabled": true,
  "documentation": {
    "content": "Alert for identifying underutilized compute instances for cost optimization"
  }
}
EOF
    
    # Create the alerting policy
    if gcloud alpha monitoring policies create --policy-from-file=alert-policy.json; then
        success "Monitoring alert policy created"
    else
        warn "Failed to create monitoring alert policy (may require alpha API access)"
    fi
    
    # Clean up temporary file
    rm -f alert-policy.json
}

# Create Cloud Scheduler jobs
create_scheduler_jobs() {
    log "Creating Cloud Scheduler jobs..."
    
    # Get Cloud Function URL
    local function_url
    function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)" 2>/dev/null) || {
        warn "Could not retrieve function URL for scheduler"
        return 0
    }
    
    # Create daily cost optimization schedule
    if gcloud scheduler jobs create http "cost-optimization-schedule-${RANDOM_SUFFIX}" \
        --location="${REGION}" \
        --schedule="0 2 * * *" \
        --uri="${function_url}" \
        --http-method=GET \
        --description="Daily infrastructure cost optimization analysis"; then
        success "Daily optimization scheduler created"
    else
        warn "Failed to create daily optimization scheduler"
    fi
}

# Submit test batch job
submit_test_batch_job() {
    log "Submitting test batch job..."
    
    # Submit the batch job
    if gcloud batch jobs submit "${BATCH_JOB_NAME}" \
        --location="${REGION}" \
        --config=batch-configs/cost-analysis-job.json; then
        success "Test batch job submitted: ${BATCH_JOB_NAME}"
        
        # Monitor job briefly
        log "Monitoring batch job status (will timeout after 60 seconds)..."
        local timeout=60
        local elapsed=0
        
        while [[ $elapsed -lt $timeout ]]; do
            local status
            status=$(gcloud batch jobs describe "${BATCH_JOB_NAME}" \
                --location="${REGION}" \
                --format="value(status.state)" 2>/dev/null) || break
            
            log "Job status: ${status}"
            
            if [[ "${status}" == "SUCCEEDED" ]]; then
                success "Batch job completed successfully"
                break
            elif [[ "${status}" == "FAILED" ]]; then
                warn "Batch job failed - check logs for details"
                break
            fi
            
            sleep 10
            elapsed=$((elapsed + 10))
        done
        
        if [[ $elapsed -ge $timeout ]]; then
            log "Batch job monitoring timed out - job may still be running"
        fi
    else
        warn "Failed to submit test batch job"
    fi
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        success "Storage bucket is accessible"
    else
        warn "Storage bucket verification failed"
    fi
    
    # Check BigQuery dataset
    if bq ls "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        success "BigQuery dataset is accessible"
    else
        warn "BigQuery dataset verification failed"
    fi
    
    # Check Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        success "Cloud Function is deployed"
    else
        warn "Cloud Function verification failed"
    fi
    
    # Check Pub/Sub topics
    if gcloud pubsub topics describe cost-optimization-events &>/dev/null; then
        success "Pub/Sub topics are created"
    else
        warn "Pub/Sub topics verification failed"
    fi
    
    success "Deployment verification completed"
}

# Main deployment function
main() {
    log "Starting Infrastructure Cost Optimization deployment..."
    
    check_prerequisites
    setup_environment
    configure_gcloud
    enable_apis
    create_storage_bucket
    create_bigquery_dataset
    create_pubsub_resources
    create_cloud_function
    create_batch_job_config
    create_monitoring_alerts
    create_scheduler_jobs
    submit_test_batch_job
    verify_deployment
    
    success "Infrastructure Cost Optimization system deployed successfully!"
    
    log "Deployment Summary:"
    log "  Project ID: ${PROJECT_ID}"
    log "  Region: ${REGION}"
    log "  Storage Bucket: gs://${BUCKET_NAME}"
    log "  BigQuery Dataset: ${DATASET_NAME}"
    log "  Cloud Function: ${FUNCTION_NAME}"
    log "  Batch Job: ${BATCH_JOB_NAME}"
    
    log "To test the system:"
    log "  1. Trigger the cost optimizer function manually"
    log "  2. Check BigQuery tables for optimization data"
    log "  3. Monitor batch job execution in Cloud Console"
    
    log "Environment variables saved to .env file for cleanup"
    
    warn "Remember to run destroy.sh when you're done to avoid ongoing charges"
}

# Handle script interruption
trap 'error "Script interrupted. Run destroy.sh to clean up resources."' INT TERM

# Run main function
main "$@"