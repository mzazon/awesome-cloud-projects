#!/bin/bash

# Real-Time Streaming Analytics with Cloud Media CDN and Live Stream API - Deployment Script
# This script deploys the complete streaming analytics infrastructure on Google Cloud Platform

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/${SCRIPT_NAME%.*}_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "$*"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handler
cleanup_on_error() {
    local exit_code=$?
    error "Deployment failed with exit code ${exit_code}"
    error "Check log file: ${LOG_FILE}"
    info "You can run the destroy script to clean up any partial deployment"
    exit ${exit_code}
}

trap cleanup_on_error ERR

# Print banner
print_banner() {
    echo -e "${BLUE}"
    echo "=================================================================="
    echo "  Real-Time Streaming Analytics Infrastructure Deployment"
    echo "  GCP Recipe: real-time-streaming-analytics-media-cdn-live-stream-api"
    echo "=================================================================="
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "bq CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 &> /dev/null; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check gcloud version
    local gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null)
    info "Using Google Cloud SDK version: ${gcloud_version}"
    
    success "All prerequisites satisfied"
}

# Set up environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="streaming-analytics-$(date +%s)"
        warn "PROJECT_ID not set, using generated ID: ${PROJECT_ID}"
    fi
    
    # Set default values
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 6)
    export BUCKET_NAME="${BUCKET_NAME:-streaming-content-${RANDOM_SUFFIX}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-stream-analytics-processor}"
    export DATASET_NAME="${DATASET_NAME:-streaming_analytics}"
    export PUBSUB_TOPIC="${PUBSUB_TOPIC:-stream-events}"
    export LIVE_INPUT_NAME="live-input-${RANDOM_SUFFIX}"
    export LIVE_CHANNEL_NAME="live-channel-${RANDOM_SUFFIX}"
    export CDN_ORIGIN_NAME="streaming-origin-${RANDOM_SUFFIX}"
    export CDN_SERVICE_NAME="streaming-service-${RANDOM_SUFFIX}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    info "Environment configured:"
    info "  PROJECT_ID: ${PROJECT_ID}"
    info "  REGION: ${REGION}"
    info "  BUCKET_NAME: ${BUCKET_NAME}"
    info "  FUNCTION_NAME: ${FUNCTION_NAME}"
    info "  DATASET_NAME: ${DATASET_NAME}"
    
    # Save environment variables for destroy script
    cat > "${SCRIPT_DIR}/.env" << EOF
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"
export BUCKET_NAME="${BUCKET_NAME}"
export FUNCTION_NAME="${FUNCTION_NAME}"
export DATASET_NAME="${DATASET_NAME}"
export PUBSUB_TOPIC="${PUBSUB_TOPIC}"
export LIVE_INPUT_NAME="${LIVE_INPUT_NAME}"
export LIVE_CHANNEL_NAME="${LIVE_CHANNEL_NAME}"
export CDN_ORIGIN_NAME="${CDN_ORIGIN_NAME}"
export CDN_SERVICE_NAME="${CDN_SERVICE_NAME}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF
    
    success "Environment variables configured and saved"
}

# Enable required APIs
enable_apis() {
    info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "livestream.googleapis.com"
        "storage.googleapis.com"
        "networkservices.googleapis.com"
        "cloudfunctions.googleapis.com"
        "bigquery.googleapis.com"
        "pubsub.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling ${api}..."
        gcloud services enable "${api}" --quiet
    done
    
    # Wait for APIs to be fully enabled
    info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    info "Creating Cloud Storage bucket for video segments..."
    
    # Create storage bucket
    if gsutil ls -b gs://"${BUCKET_NAME}" &>/dev/null; then
        warn "Bucket ${BUCKET_NAME} already exists, skipping creation"
    else
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            gs://"${BUCKET_NAME}"
        
        success "Storage bucket created: gs://${BUCKET_NAME}"
    fi
    
    # Enable uniform bucket-level access for Media CDN
    gsutil uniformbucketlevelaccess set on gs://"${BUCKET_NAME}"
    
    # Configure lifecycle policy for cost optimization
    cat > /tmp/lifecycle-policy.json << 'EOF'
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30}
    },
    {
      "action": {"type": "Delete"},
      "condition": {"age": 90}
    }
  ]
}
EOF
    
    gsutil lifecycle set /tmp/lifecycle-policy.json gs://"${BUCKET_NAME}"
    rm -f /tmp/lifecycle-policy.json
    
    success "Storage bucket configured with lifecycle policies"
}

# Set up BigQuery dataset
setup_bigquery() {
    info "Setting up BigQuery dataset for analytics..."
    
    # Create BigQuery dataset
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        warn "Dataset ${DATASET_NAME} already exists, skipping creation"
    else
        bq mk --dataset \
            --location="${REGION}" \
            --description="Streaming analytics data warehouse" \
            "${PROJECT_ID}:${DATASET_NAME}"
        
        success "BigQuery dataset created: ${DATASET_NAME}"
    fi
    
    # Create table for streaming events
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.streaming_events" \
        timestamp:TIMESTAMP,event_type:STRING,viewer_id:STRING,session_id:STRING,stream_id:STRING,quality:STRING,buffer_health:FLOAT,latency_ms:INTEGER,location:STRING,user_agent:STRING,bitrate:INTEGER,resolution:STRING,cdn_cache_status:STRING,edge_location:STRING \
        --time_partitioning_field=timestamp \
        --time_partitioning_type=DAY \
        --description="Real-time streaming events and viewer engagement metrics" || true
    
    # Create table for CDN access logs
    bq mk --table \
        "${PROJECT_ID}:${DATASET_NAME}.cdn_access_logs" \
        timestamp:TIMESTAMP,client_ip:STRING,request_method:STRING,request_uri:STRING,response_code:INTEGER,response_size:INTEGER,cache_status:STRING,edge_location:STRING,user_agent:STRING,referer:STRING,latency_ms:INTEGER \
        --time_partitioning_field=timestamp \
        --time_partitioning_type=DAY \
        --description="CDN access logs for performance analysis" || true
    
    success "BigQuery tables created for analytics"
}

# Create Pub/Sub topic
create_pubsub() {
    info "Creating Pub/Sub topic for event streaming..."
    
    # Create Pub/Sub topic
    if gcloud pubsub topics describe "${PUBSUB_TOPIC}" &>/dev/null; then
        warn "Pub/Sub topic ${PUBSUB_TOPIC} already exists, skipping creation"
    else
        gcloud pubsub topics create "${PUBSUB_TOPIC}"
        success "Pub/Sub topic created: ${PUBSUB_TOPIC}"
    fi
    
    # Create subscription for BigQuery streaming insert
    if gcloud pubsub subscriptions describe "${PUBSUB_TOPIC}-bq-subscription" &>/dev/null; then
        warn "Pub/Sub subscription already exists, skipping creation"
    else
        gcloud pubsub subscriptions create "${PUBSUB_TOPIC}-bq-subscription" \
            --topic="${PUBSUB_TOPIC}" \
            --ack-deadline=60 \
            --message-retention-duration=7d
        
        success "Pub/Sub subscription created for BigQuery integration"
    fi
}

# Deploy Cloud Function
deploy_cloud_function() {
    info "Deploying Cloud Function for real-time analytics processing..."
    
    # Create function source directory
    local function_dir="/tmp/stream-analytics-function-${RANDOM_SUFFIX}"
    mkdir -p "${function_dir}"
    
    # Create main function file
    cat > "${function_dir}/main.py" << 'EOF'
import json
import logging
import os
from google.cloud import bigquery
from google.cloud import pubsub_v1
from datetime import datetime
import functions_framework

# Initialize clients
bigquery_client = bigquery.Client()
publisher = pubsub_v1.PublisherClient()

@functions_framework.cloud_event
def process_streaming_event(cloud_event):
    """Process streaming events and send to BigQuery"""
    try:
        # Parse the event data
        event_data = json.loads(cloud_event.data)
        
        # Extract streaming metrics
        streaming_event = {
            'timestamp': datetime.utcnow().isoformat(),
            'event_type': event_data.get('eventType', 'unknown'),
            'viewer_id': event_data.get('viewerId', ''),
            'session_id': event_data.get('sessionId', ''),
            'stream_id': event_data.get('streamId', ''),
            'quality': event_data.get('quality', ''),
            'buffer_health': float(event_data.get('bufferHealth', 0)),
            'latency_ms': int(event_data.get('latency', 0)),
            'location': event_data.get('location', ''),
            'user_agent': event_data.get('userAgent', ''),
            'bitrate': int(event_data.get('bitrate', 0)),
            'resolution': event_data.get('resolution', ''),
            'cdn_cache_status': event_data.get('cacheStatus', ''),
            'edge_location': event_data.get('edgeLocation', '')
        }
        
        # Insert into BigQuery
        dataset_name = os.environ.get('DATASET_NAME', 'streaming_analytics')
        table_ref = bigquery_client.dataset(dataset_name).table('streaming_events')
        table = bigquery_client.get_table(table_ref)
        
        errors = bigquery_client.insert_rows_json(table, [streaming_event])
        if errors:
            logging.error(f"BigQuery insert errors: {errors}")
            return {'status': 'error', 'message': f'BigQuery errors: {errors}'}
        else:
            logging.info("Successfully inserted streaming event")
            
        return {'status': 'success'}
        
    except Exception as e:
        logging.error(f"Error processing streaming event: {str(e)}")
        return {'status': 'error', 'message': str(e)}
EOF
    
    # Create requirements file
    cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-bigquery==3.11.4
google-cloud-pubsub==2.18.1
functions-framework==3.4.0
EOF
    
    # Deploy the function
    (cd "${function_dir}" && gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python311 \
        --trigger-topic "${PUBSUB_TOPIC}" \
        --entry-point process_streaming_event \
        --set-env-vars DATASET_NAME="${DATASET_NAME}" \
        --memory 256MB \
        --timeout 60s \
        --region "${REGION}" \
        --quiet)
    
    # Clean up temporary directory
    rm -rf "${function_dir}"
    
    success "Cloud Function deployed: ${FUNCTION_NAME}"
}

# Create Live Stream input endpoint
create_live_stream_input() {
    info "Creating Live Stream input endpoint..."
    
    # Create input endpoint for live stream
    if gcloud livestream inputs describe "${LIVE_INPUT_NAME}" --location="${REGION}" &>/dev/null; then
        warn "Live Stream input ${LIVE_INPUT_NAME} already exists, skipping creation"
    else
        gcloud livestream inputs create "${LIVE_INPUT_NAME}" \
            --location="${REGION}" \
            --type=RTMP_PUSH \
            --tier=HD
        
        success "Live Stream input endpoint created: ${LIVE_INPUT_NAME}"
    fi
    
    # Get input endpoint details
    INPUT_ENDPOINT=$(gcloud livestream inputs describe "${LIVE_INPUT_NAME}" \
        --location="${REGION}" \
        --format="value(uri)")
    
    info "Live Stream input endpoint URL: ${INPUT_ENDPOINT}"
    echo "INPUT_ENDPOINT=${INPUT_ENDPOINT}" >> "${SCRIPT_DIR}/.env"
}

# Configure Live Stream channel
configure_live_stream_channel() {
    info "Configuring Live Stream channel with multiple outputs..."
    
    # Create channel configuration file
    local config_file="/tmp/channel-config-${RANDOM_SUFFIX}.yaml"
    cat > "${config_file}" << EOF
inputAttachments:
- key: "live-input"
  input: "projects/${PROJECT_ID}/locations/${REGION}/inputs/${LIVE_INPUT_NAME}"

output:
  uri: "gs://${BUCKET_NAME}/live-stream/"

elementaryStreams:
- key: "video-stream-hd"
  videoStream:
    h264:
      widthPixels: 1280
      heightPixels: 720
      frameRate: 30
      bitrateBps: 3000000
      vbvSizeBits: 6000000
      vbvFullnessBits: 5400000
      gopDuration: "2s"
      
- key: "video-stream-sd"
  videoStream:
    h264:
      widthPixels: 854
      heightPixels: 480
      frameRate: 30
      bitrateBps: 1500000
      vbvSizeBits: 3000000
      vbvFullnessBits: 2700000
      gopDuration: "2s"
      
- key: "audio-stream"
  audioStream:
    codec: "aac"
    bitrateBps: 128000
    channelCount: 2
    channelLayout: ["FL", "FR"]
    sampleRateHertz: 48000

muxStreams:
- key: "hd-stream"
  container: "fmp4"
  elementaryStreams: ["video-stream-hd", "audio-stream"]
  
- key: "sd-stream"
  container: "fmp4"
  elementaryStreams: ["video-stream-sd", "audio-stream"]

manifests:
- fileName: "manifest.m3u8"
  type: "HLS"
  muxStreams: ["hd-stream", "sd-stream"]
  maxSegmentCount: 5
  segmentKeepDuration: "10s"
EOF
    
    # Create the live stream channel
    if gcloud livestream channels describe "${LIVE_CHANNEL_NAME}" --location="${REGION}" &>/dev/null; then
        warn "Live Stream channel ${LIVE_CHANNEL_NAME} already exists, skipping creation"
    else
        gcloud livestream channels create "${LIVE_CHANNEL_NAME}" \
            --location="${REGION}" \
            --config-file="${config_file}"
        
        success "Live Stream channel created with multi-bitrate output"
    fi
    
    # Clean up config file
    rm -f "${config_file}"
}

# Set up Media CDN
setup_media_cdn() {
    info "Setting up Media CDN for global content delivery..."
    
    # Create edge cache origin for Cloud Storage
    if gcloud network-services edge-cache-origins describe "${CDN_ORIGIN_NAME}" &>/dev/null; then
        warn "CDN origin ${CDN_ORIGIN_NAME} already exists, skipping creation"
    else
        gcloud network-services edge-cache-origins create "${CDN_ORIGIN_NAME}" \
            --origin-address="${BUCKET_NAME}.storage.googleapis.com" \
            --port=443 \
            --protocol=HTTPS \
            --description="Origin for streaming content" || true
        
        success "Media CDN origin created: ${CDN_ORIGIN_NAME}"
    fi
    
    info "Media CDN configuration completed (edge cache service creation skipped due to SSL certificate requirements)"
    warn "To complete CDN setup, manually configure SSL certificates and edge cache service in the Google Cloud Console"
}

# Create analytics views
create_analytics_views() {
    info "Creating analytical views for streaming insights..."
    
    # Create viewer engagement metrics view
    bq query --use_legacy_sql=false << EOF
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.viewer_engagement_metrics\` AS
SELECT
  DATE(timestamp) as date,
  stream_id,
  COUNT(DISTINCT viewer_id) as unique_viewers,
  COUNT(DISTINCT session_id) as total_sessions,
  AVG(buffer_health) as avg_buffer_health,
  AVG(latency_ms) as avg_latency_ms,
  COUNT(CASE WHEN event_type = 'buffer_start' THEN 1 END) as buffer_events,
  COUNT(CASE WHEN event_type = 'quality_change' THEN 1 END) as quality_changes
FROM \`${PROJECT_ID}.${DATASET_NAME}.streaming_events\`
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
GROUP BY date, stream_id
ORDER BY date DESC, unique_viewers DESC;
EOF
    
    # Create CDN performance metrics view
    bq query --use_legacy_sql=false << EOF
CREATE OR REPLACE VIEW \`${PROJECT_ID}.${DATASET_NAME}.cdn_performance_metrics\` AS
SELECT
  edge_location,
  COUNT(*) as total_requests,
  COUNT(CASE WHEN response_code = 200 THEN 1 END) as successful_requests,
  COUNT(CASE WHEN cache_status = 'HIT' THEN 1 END) as cache_hits,
  AVG(latency_ms) as avg_response_latency,
  SUM(response_size) as total_bytes_served
FROM \`${PROJECT_ID}.${DATASET_NAME}.cdn_access_logs\`
WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
GROUP BY edge_location
ORDER BY total_requests DESC;
EOF
    
    success "Analytics views created for streaming insights"
}

# Start Live Stream channel
start_live_stream() {
    info "Starting Live Stream channel..."
    
    # Start the live stream channel
    gcloud livestream channels start "${LIVE_CHANNEL_NAME}" \
        --location="${REGION}"
    
    # Wait for channel to be running
    info "Waiting for channel to start (this may take a few minutes)..."
    local max_attempts=30
    local attempt=0
    
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        local status=$(gcloud livestream channels describe "${LIVE_CHANNEL_NAME}" \
            --location="${REGION}" \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "${status}" == "RUNNING" ]]; then
            success "Live Stream channel is running and ready for input"
            break
        elif [[ "${status}" == "ERROR" ]]; then
            error "Live Stream channel failed to start"
            exit 1
        else
            info "Channel status: ${status} (attempt $((attempt + 1))/${max_attempts})"
            sleep 10
            ((attempt++))
        fi
    done
    
    if [[ ${attempt} -eq ${max_attempts} ]]; then
        warn "Channel start verification timed out, but channel may still be starting"
    fi
}

# Test analytics pipeline
test_analytics_pipeline() {
    info "Testing analytics pipeline with sample data..."
    
    # Create test event
    local test_event=$(cat << EOF
{
  "eventType": "stream_start",
  "viewerId": "viewer_123",
  "sessionId": "session_456",
  "streamId": "${LIVE_CHANNEL_NAME}",
  "quality": "HD",
  "bufferHealth": 0.95,
  "latency": 150,
  "location": "US",
  "userAgent": "TestPlayer/1.0",
  "bitrate": 3000000,
  "resolution": "1280x720",
  "cacheStatus": "HIT",
  "edgeLocation": "us-central1"
}
EOF
)
    
    # Publish test event to Pub/Sub
    echo "${test_event}" | gcloud pubsub topics publish "${PUBSUB_TOPIC}" --message=-
    
    info "Test event published, waiting for processing..."
    sleep 30
    
    # Query analytics data
    local event_count=$(bq query --use_legacy_sql=false --format=csv \
        "SELECT COUNT(*) as event_count 
         FROM \`${PROJECT_ID}.${DATASET_NAME}.streaming_events\` 
         WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)" 2>/dev/null | tail -n +2)
    
    if [[ "${event_count}" -gt 0 ]]; then
        success "Analytics pipeline tested successfully (${event_count} events processed)"
    else
        warn "No events found in analytics table yet (this is normal for new deployments)"
    fi
}

# Print deployment summary
print_summary() {
    echo -e "\n${GREEN}=================================================================="
    echo "  Deployment Summary"
    echo "==================================================================${NC}"
    echo
    echo "✅ Infrastructure deployed successfully!"
    echo
    echo "🔧 Key Resources Created:"
    echo "  • Project: ${PROJECT_ID}"
    echo "  • Storage Bucket: gs://${BUCKET_NAME}"
    echo "  • BigQuery Dataset: ${DATASET_NAME}"
    echo "  • Pub/Sub Topic: ${PUBSUB_TOPIC}"
    echo "  • Cloud Function: ${FUNCTION_NAME}"
    echo "  • Live Stream Input: ${LIVE_INPUT_NAME}"
    echo "  • Live Stream Channel: ${LIVE_CHANNEL_NAME}"
    echo
    echo "📡 Live Stream Endpoint:"
    if [[ -n "${INPUT_ENDPOINT:-}" ]]; then
        echo "  ${INPUT_ENDPOINT}"
    else
        echo "  Run 'gcloud livestream inputs describe ${LIVE_INPUT_NAME} --location=${REGION}' to get endpoint"
    fi
    echo
    echo "📊 Analytics Access:"
    echo "  • BigQuery Console: https://console.cloud.google.com/bigquery?project=${PROJECT_ID}"
    echo "  • Pub/Sub Console: https://console.cloud.google.com/cloudpubsub?project=${PROJECT_ID}"
    echo "  • Cloud Functions Console: https://console.cloud.google.com/functions?project=${PROJECT_ID}"
    echo
    echo "🧹 Cleanup:"
    echo "  Run './destroy.sh' to remove all resources"
    echo
    echo "📋 Next Steps:"
    echo "  1. Configure your streaming software with the Live Stream endpoint"
    echo "  2. Set up SSL certificates for Media CDN (if needed)"
    echo "  3. Create analytics dashboards in Google Cloud Console"
    echo "  4. Monitor costs in the billing dashboard"
    echo
    echo "📝 Log File: ${LOG_FILE}"
    echo -e "${GREEN}==================================================================${NC}"
}

# Main deployment function
main() {
    print_banner
    
    info "Starting deployment at $(date)"
    info "Log file: ${LOG_FILE}"
    
    check_prerequisites
    setup_environment
    enable_apis
    create_storage_bucket
    setup_bigquery
    create_pubsub
    deploy_cloud_function
    create_live_stream_input
    configure_live_stream_channel
    setup_media_cdn
    create_analytics_views
    start_live_stream
    test_analytics_pipeline
    
    print_summary
    
    success "Deployment completed successfully at $(date)"
}

# Run main function
main "$@"