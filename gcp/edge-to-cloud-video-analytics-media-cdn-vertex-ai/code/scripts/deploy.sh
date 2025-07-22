#!/bin/bash

# Edge-to-Cloud Video Analytics with Media CDN and Vertex AI - Deployment Script
# This script deploys the complete video analytics pipeline infrastructure

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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        warn "openssl not found. Using date-based random suffix instead."
        USE_OPENSSL=false
    else
        USE_OPENSSL=true
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error "No active Google Cloud authentication found. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get or create project ID
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="video-analytics-$(date +%s)"
        info "No PROJECT_ID provided, using: ${PROJECT_ID}"
    fi
    
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    if [[ "${USE_OPENSSL}" == "true" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    else
        RANDOM_SUFFIX=$(date +%s | tail -c 7)
    fi
    
    # Set resource names with unique suffixes
    export BUCKET_NAME="video-content-${RANDOM_SUFFIX}"
    export RESULTS_BUCKET="analytics-results-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="video-processor-${RANDOM_SUFFIX}"
    export CDN_SERVICE_NAME="media-cdn-${RANDOM_SUFFIX}"
    
    # Store configuration for cleanup script
    cat > .deployment_config << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
BUCKET_NAME=${BUCKET_NAME}
RESULTS_BUCKET=${RESULTS_BUCKET}
FUNCTION_NAME=${FUNCTION_NAME}
CDN_SERVICE_NAME=${CDN_SERVICE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_TIMESTAMP=$(date +%s)
EOF
    
    log "Environment variables configured:"
    info "  Project ID: ${PROJECT_ID}"
    info "  Region: ${REGION}"
    info "  Zone: ${ZONE}"
    info "  Random Suffix: ${RANDOM_SUFFIX}"
}

# Configure GCP project
configure_project() {
    log "Configuring Google Cloud project..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    # Enable required APIs
    log "Enabling required Google Cloud APIs..."
    gcloud services enable storage.googleapis.com --quiet
    gcloud services enable cloudfunctions.googleapis.com --quiet
    gcloud services enable aiplatform.googleapis.com --quiet
    gcloud services enable networkconnectivity.googleapis.com --quiet
    gcloud services enable eventarc.googleapis.com --quiet
    gcloud services enable videointelligence.googleapis.com --quiet
    
    # Wait for APIs to be fully enabled
    sleep 10
    
    log "Google Cloud project configured successfully"
}

# Create Cloud Storage buckets
create_storage_buckets() {
    log "Creating Cloud Storage buckets..."
    
    # Create primary video content bucket
    if gsutil ls -p "${PROJECT_ID}" "gs://${BUCKET_NAME}" 2>/dev/null; then
        warn "Bucket gs://${BUCKET_NAME} already exists"
    else
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}"
        log "Created video content bucket: gs://${BUCKET_NAME}"
    fi
    
    # Create analytics results bucket
    if gsutil ls -p "${PROJECT_ID}" "gs://${RESULTS_BUCKET}" 2>/dev/null; then
        warn "Bucket gs://${RESULTS_BUCKET} already exists"
    else
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${RESULTS_BUCKET}"
        log "Created analytics results bucket: gs://${RESULTS_BUCKET}"
    fi
    
    # Enable versioning for data protection
    gsutil versioning set on "gs://${BUCKET_NAME}"
    gsutil versioning set on "gs://${RESULTS_BUCKET}"
    
    # Set appropriate bucket policies
    gsutil iam ch allUsers:objectViewer "gs://${BUCKET_NAME}" || warn "Could not set public read access on video bucket"
    
    log "Storage buckets created and configured successfully"
}

# Configure Media CDN
configure_media_cdn() {
    log "Configuring Media CDN edge cache service..."
    
    # Create EdgeCacheOrigin for Cloud Storage
    if gcloud compute network-edge-security-services describe "${CDN_SERVICE_NAME}-origin" --region="${REGION}" 2>/dev/null; then
        warn "EdgeCacheOrigin ${CDN_SERVICE_NAME}-origin already exists"
    else
        gcloud compute network-edge-security-services create "${CDN_SERVICE_NAME}-origin" \
            --description="Origin for video content storage" \
            --region="${REGION}" \
            --quiet || warn "Could not create EdgeCacheOrigin (may require special permissions)"
    fi
    
    # Create cache policy configuration file
    cat > media-cdn-config.yaml << EOF
# Media CDN Configuration for Video Streaming
name: ${CDN_SERVICE_NAME}
description: "Intelligent edge caching for video analytics pipeline"
cache_policies:
  - name: "video-content-policy"
    default_ttl: "86400s"  # 24 hours
    max_ttl: "604800s"     # 7 days
    cache_key_policy:
      include_query_string: true
      query_string_blacklist: ["utm_source", "utm_medium"]
  - name: "analytics-results-policy"
    default_ttl: "3600s"   # 1 hour
    max_ttl: "86400s"      # 24 hours
origin_config:
  origin_uri: "gs://${BUCKET_NAME}"
  protocol: "HTTPS"
EOF
    
    info "Media CDN configuration created in media-cdn-config.yaml"
    warn "Complete Media CDN setup requires additional configuration in Google Cloud Console"
    
    log "Media CDN configuration prepared successfully"
}

# Deploy Cloud Functions
deploy_cloud_functions() {
    log "Deploying Cloud Functions..."
    
    # Create basic video processor function
    create_basic_function
    
    # Create advanced video analytics function
    create_advanced_function
    
    # Create results processor function
    create_results_function
    
    log "All Cloud Functions deployed successfully"
}

# Create basic video processor function
create_basic_function() {
    log "Creating basic video processor function..."
    
    mkdir -p video-processor-function
    cd video-processor-function
    
    cat > main.py << 'EOF'
import os
import json
from google.cloud import aiplatform
from google.cloud import storage
import base64

def process_video(cloud_event):
    """Triggered by Cloud Storage object upload."""
    
    # Parse the Cloud Storage event
    file_name = cloud_event.data["name"]
    bucket_name = cloud_event.data["bucket"]
    
    # Skip if not a video file
    if not file_name.lower().endswith(('.mp4', '.mov', '.avi', '.mkv')):
        print(f"Skipping non-video file: {file_name}")
        return
    
    print(f"Processing video: {file_name} from bucket: {bucket_name}")
    
    # Initialize Vertex AI client
    project_id = os.environ.get('PROJECT_ID')
    region = os.environ.get('REGION', 'us-central1')
    
    try:
        aiplatform.init(project=project_id, location=region)
        
        # Trigger video analysis workflow
        video_uri = f"gs://{bucket_name}/{file_name}"
        
        # Create analytics job metadata
        analytics_metadata = {
            "video_uri": video_uri,
            "file_name": file_name,
            "bucket_name": bucket_name,
            "processing_status": "initiated",
            "timestamp": cloud_event.time
        }
        
        # Store metadata in results bucket
        results_bucket = os.environ.get('RESULTS_BUCKET')
        storage_client = storage.Client()
        results_bucket_obj = storage_client.bucket(results_bucket)
        
        metadata_blob = results_bucket_obj.blob(f"metadata/{file_name}.json")
        metadata_blob.upload_from_string(json.dumps(analytics_metadata))
        
        print(f"✅ Video processing initiated for: {file_name}")
        
        return {"status": "success", "video_uri": video_uri}
        
    except Exception as e:
        print(f"Error processing video: {str(e)}")
        return {"status": "error", "error": str(e)}
EOF
    
    cat > requirements.txt << 'EOF'
google-cloud-aiplatform==1.38.0
google-cloud-storage==2.10.0
google-cloud-functions==1.8.3
EOF
    
    # Deploy the Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" 2>/dev/null; then
        warn "Function ${FUNCTION_NAME} already exists, updating..."
        gcloud functions deploy "${FUNCTION_NAME}" \
            --runtime python39 \
            --trigger-bucket "${BUCKET_NAME}" \
            --entry-point process_video \
            --memory 512MB \
            --timeout 540s \
            --region="${REGION}" \
            --set-env-vars PROJECT_ID="${PROJECT_ID}",REGION="${REGION}",RESULTS_BUCKET="${RESULTS_BUCKET}" \
            --quiet
    else
        gcloud functions deploy "${FUNCTION_NAME}" \
            --runtime python39 \
            --trigger-bucket "${BUCKET_NAME}" \
            --entry-point process_video \
            --memory 512MB \
            --timeout 540s \
            --region="${REGION}" \
            --set-env-vars PROJECT_ID="${PROJECT_ID}",REGION="${REGION}",RESULTS_BUCKET="${RESULTS_BUCKET}" \
            --quiet
    fi
    
    cd ..
    log "Basic video processor function deployed: ${FUNCTION_NAME}"
}

# Create advanced video analytics function
create_advanced_function() {
    log "Creating advanced video analytics function..."
    
    mkdir -p advanced-video-analytics
    cd advanced-video-analytics
    
    cat > main.py << 'EOF'
import os
import json
import asyncio
from google.cloud import videointelligence
from google.cloud import storage
from google.cloud import aiplatform
import logging

def analyze_video_content(cloud_event):
    """Advanced video analysis using Vertex AI Video Intelligence."""
    
    file_name = cloud_event.data["name"]
    bucket_name = cloud_event.data["bucket"]
    
    # Skip non-video files
    video_extensions = ('.mp4', '.mov', '.avi', '.mkv', '.webm')
    if not file_name.lower().endswith(video_extensions):
        return {"status": "skipped", "reason": "not a video file"}
    
    video_uri = f"gs://{bucket_name}/{file_name}"
    logging.info(f"Starting analysis for: {video_uri}")
    
    try:
        # Initialize Video Intelligence client
        video_client = videointelligence.VideoIntelligenceServiceClient()
        
        # Configure analysis features
        features = [
            videointelligence.Feature.OBJECT_TRACKING,
            videointelligence.Feature.LABEL_DETECTION,
            videointelligence.Feature.SHOT_CHANGE_DETECTION,
            videointelligence.Feature.TEXT_DETECTION
        ]
        
        # Configure analysis settings
        config = videointelligence.VideoContext(
            object_tracking_config=videointelligence.ObjectTrackingConfig(
                model="builtin/latest"
            ),
            label_detection_config=videointelligence.LabelDetectionConfig(
                model="builtin/latest",
                label_detection_mode=videointelligence.LabelDetectionMode.SHOT_AND_FRAME_MODE
            )
        )
        
        # Start video analysis operation
        operation = video_client.annotate_video(
            request={
                "features": features,
                "input_uri": video_uri,
                "video_context": config,
                "output_uri": f"gs://{os.environ.get('RESULTS_BUCKET')}/analysis/{file_name}_analysis.json"
            }
        )
        
        # Process results asynchronously
        print(f"Analysis started for {file_name}. Operation: {operation.operation.name}")
        
        # Store analysis metadata
        storage_client = storage.Client()
        results_bucket = storage_client.bucket(os.environ.get('RESULTS_BUCKET'))
        
        analysis_metadata = {
            "video_uri": video_uri,
            "file_name": file_name,
            "operation_name": operation.operation.name,
            "features_analyzed": [feature.name for feature in features],
            "status": "processing",
            "timestamp": cloud_event.time
        }
        
        metadata_blob = results_bucket.blob(f"operations/{file_name}_metadata.json")
        metadata_blob.upload_from_string(json.dumps(analysis_metadata, indent=2))
        
        return {
            "status": "analysis_started",
            "operation_name": operation.operation.name,
            "video_uri": video_uri
        }
        
    except Exception as e:
        logging.error(f"Error analyzing video: {str(e)}")
        return {"status": "error", "error": str(e)}
EOF
    
    cat > requirements.txt << 'EOF'
google-cloud-videointelligence==2.11.3
google-cloud-storage==2.10.0
google-cloud-aiplatform==1.38.0
EOF
    
    # Deploy advanced analytics function
    ADVANCED_FUNCTION_NAME="advanced-video-analytics-${RANDOM_SUFFIX}"
    if gcloud functions describe "${ADVANCED_FUNCTION_NAME}" --region="${REGION}" 2>/dev/null; then
        warn "Function ${ADVANCED_FUNCTION_NAME} already exists, updating..."
    fi
    
    gcloud functions deploy "${ADVANCED_FUNCTION_NAME}" \
        --runtime python39 \
        --trigger-bucket "${BUCKET_NAME}" \
        --entry-point analyze_video_content \
        --memory 1024MB \
        --timeout 540s \
        --region="${REGION}" \
        --set-env-vars PROJECT_ID="${PROJECT_ID}",REGION="${REGION}",RESULTS_BUCKET="${RESULTS_BUCKET}" \
        --quiet
    
    # Store function name for cleanup
    echo "ADVANCED_FUNCTION_NAME=${ADVANCED_FUNCTION_NAME}" >> ../.deployment_config
    
    cd ..
    log "Advanced video analytics function deployed: ${ADVANCED_FUNCTION_NAME}"
}

# Create results processor function
create_results_function() {
    log "Creating results processor function..."
    
    mkdir -p results-processor
    cd results-processor
    
    cat > main.py << 'EOF'
import json
import os
from google.cloud import storage
from google.cloud import videointelligence
import logging

def process_analytics_results(cloud_event):
    """Process completed video analytics results."""
    
    file_name = cloud_event.data["name"]
    bucket_name = cloud_event.data["bucket"]
    
    # Only process analysis result files
    if not file_name.endswith('_analysis.json'):
        return {"status": "skipped", "reason": "not an analysis result"}
    
    logging.info(f"Processing analytics results: {file_name}")
    
    try:
        # Download and parse analysis results
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        analysis_data = json.loads(blob.download_as_text())
        
        # Extract key insights
        insights = {
            "video_file": file_name.replace('_analysis.json', ''),
            "processing_timestamp": cloud_event.time,
            "objects_detected": [],
            "labels_detected": [],
            "text_detected": [],
            "shots_detected": 0
        }
        
        # Process object tracking results
        if 'object_annotations' in analysis_data:
            for obj in analysis_data['object_annotations']:
                insights['objects_detected'].append({
                    "entity": obj.get('entity', {}).get('description', 'Unknown'),
                    "confidence": obj.get('confidence', 0),
                    "track_count": len(obj.get('frames', []))
                })
        
        # Process label detection results
        if 'label_annotations' in analysis_data:
            for label in analysis_data['label_annotations']:
                insights['labels_detected'].append({
                    "description": label.get('entity', {}).get('description', 'Unknown'),
                    "confidence": label.get('category_entities', [{}])[0].get('description', 'N/A') if label.get('category_entities') else 'N/A'
                })
        
        # Process shot detection
        if 'shot_annotations' in analysis_data:
            insights['shots_detected'] = len(analysis_data['shot_annotations'])
        
        # Store processed insights
        insights_blob = bucket.blob(f"insights/{insights['video_file']}_insights.json")
        insights_blob.upload_from_string(json.dumps(insights, indent=2))
        
        # Create summary report
        summary = {
            "total_objects": len(insights['objects_detected']),
            "total_labels": len(insights['labels_detected']),
            "total_shots": insights['shots_detected'],
            "top_objects": sorted(insights['objects_detected'], 
                                key=lambda x: x['confidence'], reverse=True)[:5],
            "top_labels": sorted(insights['labels_detected'], 
                               key=lambda x: len(x['description']), reverse=True)[:5]
        }
        
        summary_blob = bucket.blob(f"summaries/{insights['video_file']}_summary.json")
        summary_blob.upload_from_string(json.dumps(summary, indent=2))
        
        print(f"✅ Processed analytics for: {insights['video_file']}")
        print(f"   Objects detected: {summary['total_objects']}")
        print(f"   Labels detected: {summary['total_labels']}")
        print(f"   Shots detected: {summary['total_shots']}")
        
        return {"status": "success", "insights": summary}
        
    except Exception as e:
        logging.error(f"Error processing analytics results: {str(e)}")
        return {"status": "error", "error": str(e)}
EOF
    
    cat > requirements.txt << 'EOF'
google-cloud-storage==2.10.0
google-cloud-videointelligence==2.11.3
EOF
    
    # Deploy results processing function
    RESULTS_FUNCTION_NAME="results-processor-${RANDOM_SUFFIX}"
    if gcloud functions describe "${RESULTS_FUNCTION_NAME}" --region="${REGION}" 2>/dev/null; then
        warn "Function ${RESULTS_FUNCTION_NAME} already exists, updating..."
    fi
    
    gcloud functions deploy "${RESULTS_FUNCTION_NAME}" \
        --runtime python39 \
        --trigger-bucket "${RESULTS_BUCKET}" \
        --entry-point process_analytics_results \
        --memory 512MB \
        --timeout 300s \
        --region="${REGION}" \
        --set-env-vars PROJECT_ID="${PROJECT_ID}",REGION="${REGION}" \
        --quiet
    
    # Store function name for cleanup
    echo "RESULTS_FUNCTION_NAME=${RESULTS_FUNCTION_NAME}" >> ../.deployment_config
    
    cd ..
    log "Results processor function deployed: ${RESULTS_FUNCTION_NAME}"
}

# Configure Vertex AI
configure_vertex_ai() {
    log "Configuring Vertex AI for video analytics..."
    
    # Create Vertex AI dataset for video analytics
    DATASET_DISPLAY_NAME="video-analytics-dataset-${RANDOM_SUFFIX}"
    
    # Check if dataset already exists
    EXISTING_DATASET=$(gcloud ai datasets list \
        --region="${REGION}" \
        --filter="displayName:${DATASET_DISPLAY_NAME}" \
        --format="value(name)" | head -n1 || echo "")
    
    if [[ -n "${EXISTING_DATASET}" ]]; then
        warn "Dataset ${DATASET_DISPLAY_NAME} already exists"
        DATASET_ID=$(echo "${EXISTING_DATASET}" | cut -d'/' -f6)
    else
        gcloud ai datasets create \
            --display-name="${DATASET_DISPLAY_NAME}" \
            --metadata-schema-uri="gs://google-cloud-aiplatform/schema/dataset/metadata/video_1.0.0.yaml" \
            --region="${REGION}" \
            --quiet
        
        # Get the created dataset ID
        DATASET_ID=$(gcloud ai datasets list \
            --region="${REGION}" \
            --filter="displayName:${DATASET_DISPLAY_NAME}" \
            --format="value(name)" | cut -d'/' -f6)
    fi
    
    # Store dataset ID for cleanup
    echo "DATASET_ID=${DATASET_ID}" >> .deployment_config
    
    # Create video analysis pipeline configuration
    cat > video-analysis-config.json << EOF
{
  "displayName": "video-analytics-pipeline-${RANDOM_SUFFIX}",
  "description": "Automated video analytics for object detection and classification",
  "inputDataConfig": {
    "gcsSource": {
      "uris": ["gs://${BUCKET_NAME}/*"]
    }
  },
  "outputDataConfig": {
    "gcsDestination": {
      "outputUriPrefix": "gs://${RESULTS_BUCKET}/analysis-results/"
    }
  }
}
EOF
    
    log "Vertex AI configuration completed successfully"
    info "Dataset ID: ${DATASET_ID}"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check buckets
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        info "✅ Video content bucket accessible: gs://${BUCKET_NAME}"
    else
        error "❌ Video content bucket not accessible"
    fi
    
    if gsutil ls "gs://${RESULTS_BUCKET}" >/dev/null 2>&1; then
        info "✅ Results bucket accessible: gs://${RESULTS_BUCKET}"
    else
        error "❌ Results bucket not accessible"
    fi
    
    # Check functions
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        info "✅ Basic video processor function deployed"
    else
        error "❌ Basic video processor function not found"
    fi
    
    # Check for advanced function
    if [[ -f .deployment_config ]]; then
        source .deployment_config
        if [[ -n "${ADVANCED_FUNCTION_NAME:-}" ]] && gcloud functions describe "${ADVANCED_FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
            info "✅ Advanced video analytics function deployed"
        fi
        
        if [[ -n "${RESULTS_FUNCTION_NAME:-}" ]] && gcloud functions describe "${RESULTS_FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
            info "✅ Results processor function deployed"
        fi
    fi
    
    log "Deployment verification completed"
}

# Display deployment summary
display_summary() {
    log "Deployment Summary"
    echo ""
    info "🎥 Edge-to-Cloud Video Analytics Pipeline Deployed Successfully!"
    echo ""
    info "Resources Created:"
    info "  📦 Video Content Bucket: gs://${BUCKET_NAME}"
    info "  📊 Analytics Results Bucket: gs://${RESULTS_BUCKET}"
    info "  ⚡ Video Processor Function: ${FUNCTION_NAME}"
    if [[ -f .deployment_config ]]; then
        source .deployment_config
        [[ -n "${ADVANCED_FUNCTION_NAME:-}" ]] && info "  🧠 Advanced Analytics Function: ${ADVANCED_FUNCTION_NAME}"
        [[ -n "${RESULTS_FUNCTION_NAME:-}" ]] && info "  📈 Results Processor Function: ${RESULTS_FUNCTION_NAME}"
        [[ -n "${DATASET_ID:-}" ]] && info "  🤖 Vertex AI Dataset ID: ${DATASET_ID}"
    fi
    echo ""
    info "Next Steps:"
    info "  1. Upload test videos to: gs://${BUCKET_NAME}/"
    info "  2. Monitor function logs for processing status"
    info "  3. Check analytics results in: gs://${RESULTS_BUCKET}/"
    info "  4. Complete Media CDN setup in Google Cloud Console"
    echo ""
    info "Configuration saved to .deployment_config for cleanup"
    echo ""
    warn "💰 Remember: This deployment may incur charges. Use ./destroy.sh to clean up when done."
}

# Cleanup on error
cleanup_on_error() {
    error "Deployment failed. Cleaning up partial deployment..."
    if [[ -f .deployment_config ]]; then
        source .deployment_config
        warn "Running cleanup script..."
        chmod +x destroy.sh 2>/dev/null || true
        ./destroy.sh 2>/dev/null || true
    fi
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Main deployment flow
main() {
    log "Starting Edge-to-Cloud Video Analytics Pipeline Deployment"
    
    check_prerequisites
    setup_environment
    configure_project
    create_storage_buckets
    configure_media_cdn
    deploy_cloud_functions
    configure_vertex_ai
    verify_deployment
    display_summary
    
    log "Deployment completed successfully! 🎉"
}

# Run main function
main "$@"