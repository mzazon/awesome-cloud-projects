#!/bin/bash

# Deploy script for Data Locality Optimization with Cloud Storage Bucket Relocation and Cloud Monitoring
# This script deploys the complete infrastructure for automated data locality optimization

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check gcloud version
    GCLOUD_VERSION=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "0.0.0")
    REQUIRED_VERSION="400.0.0"
    if [[ "$(printf '%s\n' "$REQUIRED_VERSION" "$GCLOUD_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]]; then
        warning "gcloud CLI version $GCLOUD_VERSION detected. Version $REQUIRED_VERSION or later is recommended."
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available. Please ensure it's installed with gcloud CLI."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$PROJECT_ID" ]]; then
        error "No default project set. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "$PROJECT_ID" &> /dev/null; then
        warning "Unable to verify billing status. Please ensure billing is enabled for project $PROJECT_ID"
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set project and region configurations
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="us-central1"
    export SECONDARY_REGION="europe-west1"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 4)
    export BUCKET_NAME="data-locality-demo-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="bucket-relocator-${RANDOM_SUFFIX}"
    export SCHEDULER_JOB="locality-analyzer-${RANDOM_SUFFIX}"
    export PUBSUB_TOPIC="relocation-alerts-${RANDOM_SUFFIX}"
    
    # Create deployment metadata file
    cat > deployment-metadata.json << EOF
{
    "project_id": "$PROJECT_ID",
    "region": "$REGION",
    "secondary_region": "$SECONDARY_REGION",
    "bucket_name": "$BUCKET_NAME",
    "function_name": "$FUNCTION_NAME",
    "scheduler_job": "$SCHEDULER_JOB",
    "pubsub_topic": "$PUBSUB_TOPIC",
    "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log "Environment variables configured:"
    log "  Project ID: $PROJECT_ID"
    log "  Primary region: $REGION"
    log "  Secondary region: $SECONDARY_REGION"
    log "  Bucket name: $BUCKET_NAME"
    log "  Function name: $FUNCTION_NAME"
    
    success "Environment setup completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "storage.googleapis.com"
        "monitoring.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "pubsub.googleapis.com"
        "storagetransfer.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            success "Enabled $api"
        else
            error "Failed to enable $api"
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
    log "Creating Cloud Storage bucket..."
    
    # Create the primary storage bucket
    if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
        success "Created bucket: gs://$BUCKET_NAME"
    else
        error "Failed to create bucket"
        exit 1
    fi
    
    # Enable uniform bucket-level access
    if gsutil uniformbucketlevelaccess set on "gs://$BUCKET_NAME"; then
        success "Enabled uniform bucket-level access"
    else
        warning "Failed to enable uniform bucket-level access"
    fi
    
    # Add labels for monitoring and cost tracking
    gsutil label ch -l environment:production \
        -l purpose:data-locality-optimization \
        -l managed-by:cloud-functions \
        "gs://$BUCKET_NAME"
    
    success "Cloud Storage bucket configured with monitoring labels"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log "Creating Pub/Sub resources..."
    
    # Create the Pub/Sub topic
    if gcloud pubsub topics create "$PUBSUB_TOPIC"; then
        success "Created Pub/Sub topic: $PUBSUB_TOPIC"
    else
        error "Failed to create Pub/Sub topic"
        exit 1
    fi
    
    # Create subscription for monitoring relocation events
    if gcloud pubsub subscriptions create "${PUBSUB_TOPIC}-monitor" \
        --topic="$PUBSUB_TOPIC" \
        --ack-deadline=60; then
        success "Created Pub/Sub subscription: ${PUBSUB_TOPIC}-monitor"
    else
        error "Failed to create Pub/Sub subscription"
        exit 1
    fi
    
    success "Pub/Sub resources created"
}

# Function to set up Cloud Monitoring custom metrics
setup_monitoring_metrics() {
    log "Setting up Cloud Monitoring custom metrics..."
    
    # Create custom metric descriptor
    cat > metric_descriptor.json << 'EOF'
{
  "type": "custom.googleapis.com/storage/regional_access_latency",
  "labels": [
    {
      "key": "bucket_name",
      "valueType": "STRING"
    },
    {
      "key": "source_region",
      "valueType": "STRING"
    }
  ],
  "metricKind": "GAUGE",
  "valueType": "DOUBLE",
  "unit": "ms",
  "description": "Average access latency by region for storage optimization"
}
EOF
    
    # Create the custom metric
    if gcloud logging metrics create storage-regional-latency \
        --description="Regional access latency metric for bucket optimization" \
        --log-filter='resource.type="gcs_bucket"' \
        --value-extractor='EXTRACT(jsonPayload.latency)'; then
        success "Created custom monitoring metric"
    else
        warning "Custom metric may already exist or creation failed"
    fi
    
    success "Monitoring metrics configured"
}

# Function to create Cloud Function
create_cloud_function() {
    log "Creating Cloud Function for bucket relocation logic..."
    
    # Create function source directory
    mkdir -p bucket-relocator-function
    cd bucket-relocator-function
    
    # Create the main function file
    cat > main.py << 'EOF'
import json
import logging
from google.cloud import storage
from google.cloud import monitoring_v3
from google.cloud import pubsub_v1
import os
from datetime import datetime, timedelta

# Initialize clients
storage_client = storage.Client()
monitoring_client = monitoring_v3.MetricServiceClient()
publisher = pubsub_v1.PublisherClient()

def analyze_access_patterns(bucket_name, project_id):
    """Analyze storage access patterns using monitoring data"""
    
    try:
        # Query monitoring metrics for access patterns
        project_name = f"projects/{project_id}"
        interval = monitoring_v3.TimeInterval({
            "end_time": {"seconds": int(datetime.now().timestamp())},
            "start_time": {"seconds": int((datetime.now() - timedelta(hours=24)).timestamp())},
        })
        
        # Build query for storage access metrics
        results = monitoring_client.list_time_series(
            request={
                "name": project_name,
                "filter": f'resource.type="gcs_bucket" AND resource.label.bucket_name="{bucket_name}"',
                "interval": interval,
            }
        )
        
        access_patterns = {}
        for result in results:
            if result.resource.labels.get('location'):
                location = result.resource.labels['location']
                access_patterns[location] = access_patterns.get(location, 0) + 1
        
        return access_patterns
    except Exception as e:
        logging.error(f"Failed to analyze access patterns: {str(e)}")
        return {}

def determine_optimal_location(access_patterns):
    """Determine optimal bucket location based on access patterns"""
    
    if not access_patterns:
        return None
    
    # Find region with highest access frequency
    optimal_region = max(access_patterns, key=access_patterns.get)
    
    # Calculate access concentration (>70% from single region = relocate)
    total_access = sum(access_patterns.values())
    concentration = access_patterns[optimal_region] / total_access
    
    return optimal_region if concentration > 0.7 else None

def initiate_bucket_relocation(bucket_name, target_location, project_id):
    """Initiate bucket relocation using Cloud Storage relocation service"""
    
    try:
        bucket = storage_client.bucket(bucket_name)
        
        # Check if relocation is needed
        if bucket.location.lower() == target_location.lower():
            return {"status": "no_action", "message": "Bucket already in optimal location"}
        
        # Note: Bucket relocation would be initiated here
        # For demo purposes, we'll simulate the relocation process
        
        relocation_info = {
            "source_location": bucket.location,
            "target_location": target_location,
            "bucket_name": bucket_name,
            "status": "initiated",
            "timestamp": datetime.now().isoformat()
        }
        
        # Publish notification
        topic_path = publisher.topic_path(project_id, os.environ['PUBSUB_TOPIC'])
        message_data = json.dumps(relocation_info).encode('utf-8')
        publisher.publish(topic_path, message_data)
        
        return relocation_info
        
    except Exception as e:
        logging.error(f"Relocation failed: {str(e)}")
        return {"status": "error", "message": str(e)}

def bucket_relocator(request):
    """Main Cloud Function entry point"""
    
    project_id = os.environ['GCP_PROJECT']
    bucket_name = os.environ['BUCKET_NAME']
    
    try:
        # Analyze current access patterns
        access_patterns = analyze_access_patterns(bucket_name, project_id)
        
        # Determine optimal location
        optimal_location = determine_optimal_location(access_patterns)
        
        if optimal_location:
            # Initiate relocation
            result = initiate_bucket_relocation(bucket_name, optimal_location, project_id)
            return json.dumps(result)
        else:
            return json.dumps({"status": "no_action", "message": "Current location is optimal"})
            
    except Exception as e:
        logging.error(f"Function execution failed: {str(e)}")
        return json.dumps({"status": "error", "message": str(e)})
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-storage==2.10.0
google-cloud-monitoring==2.16.0
google-cloud-pubsub==2.18.4
functions-framework==3.4.0
EOF
    
    cd ..
    
    # Deploy the Cloud Function
    log "Deploying Cloud Function..."
    if gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python39 \
        --trigger-http \
        --entry-point bucket_relocator \
        --source ./bucket-relocator-function \
        --set-env-vars "GCP_PROJECT=$PROJECT_ID,BUCKET_NAME=$BUCKET_NAME,PUBSUB_TOPIC=$PUBSUB_TOPIC" \
        --memory 512MB \
        --timeout 300s \
        --allow-unauthenticated \
        --region="$REGION"; then
        success "Cloud Function deployed successfully"
    else
        error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    # Get the function URL
    export FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    log "Function URL: $FUNCTION_URL"
    
    # Update deployment metadata with function URL
    jq --arg url "$FUNCTION_URL" '.function_url = $url' deployment-metadata.json > temp.json && mv temp.json deployment-metadata.json
    
    success "Cloud Function deployment completed"
}

# Function to create monitoring alert policy
create_alert_policy() {
    log "Creating Cloud Monitoring alert policy..."
    
    # Create alert policy for high latency detection
    cat > alert_policy.json << EOF
{
  "displayName": "Storage Access Latency Alert - $BUCKET_NAME",
  "conditions": [
    {
      "displayName": "High storage access latency",
      "conditionThreshold": {
        "filter": "resource.type=\"gcs_bucket\" AND resource.label.bucket_name=\"$BUCKET_NAME\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 100,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ]
      }
    }
  ],
  "notificationChannels": [],
  "alertStrategy": {
    "notificationRateLimit": {
      "period": "300s"
    }
  },
  "enabled": true
}
EOF
    
    # Create the alert policy
    if gcloud alpha monitoring policies create --policy-from-file=alert_policy.json; then
        success "Monitoring alert policy created"
    else
        warning "Failed to create alert policy or policy already exists"
    fi
    
    success "Alert policy configuration completed"
}

# Function to create Cloud Scheduler job
create_scheduler_job() {
    log "Creating Cloud Scheduler job..."
    
    # Create Cloud Scheduler job for periodic analysis
    if gcloud scheduler jobs create http "$SCHEDULER_JOB" \
        --schedule="0 2 * * *" \
        --uri="$FUNCTION_URL" \
        --http-method=GET \
        --time-zone="America/New_York" \
        --description="Daily data locality analysis and optimization" \
        --location="$REGION"; then
        success "Cloud Scheduler job created: $SCHEDULER_JOB"
    else
        error "Failed to create Cloud Scheduler job"
        exit 1
    fi
    
    success "Scheduler configuration completed"
}

# Function to create sample data and test the system
create_sample_data() {
    log "Creating sample data and testing the system..."
    
    # Create sample data files
    for i in {1..10}; do
        echo "Sample data file $i - $(date)" > "sample-data-$i.txt"
        if gsutil cp "sample-data-$i.txt" "gs://$BUCKET_NAME/"; then
            log "Uploaded sample-data-$i.txt"
        else
            warning "Failed to upload sample-data-$i.txt"
        fi
    done
    
    # Simulate access patterns
    log "Simulating access patterns..."
    for i in {1..5}; do
        if gsutil cp "gs://$BUCKET_NAME/sample-data-$i.txt" "./downloaded-$i.txt"; then
            log "Downloaded sample-data-$i.txt"
        else
            warning "Failed to download sample-data-$i.txt"
        fi
    done
    
    # Test the Cloud Function
    log "Testing Cloud Function..."
    if curl -s -X GET "$FUNCTION_URL" -w "\nHTTP Status: %{http_code}\n"; then
        success "Cloud Function test completed"
    else
        warning "Cloud Function test failed"
    fi
    
    # Clean up local sample files
    rm -f sample-data-*.txt downloaded-*.txt
    
    success "Sample data creation and testing completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "Project ID: $PROJECT_ID"
    echo "Primary Region: $REGION"
    echo "Secondary Region: $SECONDARY_REGION"
    echo "Storage Bucket: gs://$BUCKET_NAME"
    echo "Cloud Function: $FUNCTION_NAME"
    echo "Function URL: $FUNCTION_URL"
    echo "Scheduler Job: $SCHEDULER_JOB"
    echo "Pub/Sub Topic: $PUBSUB_TOPIC"
    echo ""
    echo "Resources have been deployed successfully!"
    echo "You can monitor the system through the Google Cloud Console."
    echo ""
    echo "To test the function manually:"
    echo "curl -X GET $FUNCTION_URL"
    echo ""
    echo "Deployment metadata saved to: deployment-metadata.json"
    success "Deployment completed successfully!"
}

# Function to handle cleanup on failure
cleanup_on_failure() {
    error "Deployment failed. Cleaning up partial resources..."
    
    # Clean up any created resources
    gcloud scheduler jobs delete "$SCHEDULER_JOB" --location="$REGION" --quiet 2>/dev/null || true
    gcloud functions delete "$FUNCTION_NAME" --region="$REGION" --quiet 2>/dev/null || true
    gcloud pubsub subscriptions delete "${PUBSUB_TOPIC}-monitor" --quiet 2>/dev/null || true
    gcloud pubsub topics delete "$PUBSUB_TOPIC" --quiet 2>/dev/null || true
    gsutil rm -r "gs://$BUCKET_NAME" 2>/dev/null || true
    
    # Clean up local files
    rm -f metric_descriptor.json alert_policy.json deployment-metadata.json
    rm -rf bucket-relocator-function/
    rm -f sample-data-*.txt downloaded-*.txt
    
    error "Cleanup completed. Please review any remaining resources manually."
    exit 1
}

# Main deployment function
main() {
    log "Starting deployment of Data Locality Optimization solution..."
    
    # Set up error handling
    trap cleanup_on_failure ERR
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    enable_apis
    create_storage_bucket
    create_pubsub_resources
    setup_monitoring_metrics
    create_cloud_function
    create_alert_policy
    create_scheduler_job
    create_sample_data
    display_summary
    
    success "All deployment steps completed successfully!"
}

# Run main function
main "$@"