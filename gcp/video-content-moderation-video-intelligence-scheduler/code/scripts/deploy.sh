#!/bin/bash

# Video Content Moderation Deployment Script
# Deploys Video Intelligence API with Cloud Scheduler for automated content moderation

set -euo pipefail  # Exit on error, undefined vars, pipe failures

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

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of partially created resources..."
    
    # Attempt to clean up any resources that may have been created
    if [[ -n "${SCHEDULER_JOB:-}" ]] && gcloud scheduler jobs describe "${SCHEDULER_JOB}" --location="${REGION}" &>/dev/null; then
        log_info "Cleaning up scheduler job: ${SCHEDULER_JOB}"
        gcloud scheduler jobs delete "${SCHEDULER_JOB}" --location="${REGION}" --quiet || true
    fi
    
    if [[ -n "${FUNCTION_NAME:-}" ]] && gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        log_info "Cleaning up function: ${FUNCTION_NAME}"
        gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet || true
    fi
    
    if [[ -n "${PUBSUB_TOPIC:-}" ]] && gcloud pubsub topics describe "${PUBSUB_TOPIC}" &>/dev/null; then
        log_info "Cleaning up Pub/Sub resources"
        gcloud pubsub subscriptions delete "${PUBSUB_TOPIC}-sub" --quiet || true
        gcloud pubsub topics delete "${PUBSUB_TOPIC}" --quiet || true
    fi
    
    if [[ -n "${BUCKET_NAME:-}" ]] && gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_info "Cleaning up storage bucket: ${BUCKET_NAME}"
        gsutil -m rm -r "gs://${BUCKET_NAME}" || true
    fi
    
    log_error "Cleanup completed. Please review any remaining resources manually."
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Prerequisites checking function
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please install Google Cloud SDK"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found. Run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not available for generating random strings"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Configuration validation function
validate_configuration() {
    log_info "Validating configuration..."
    
    # Check if PROJECT_ID is set and valid
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID environment variable is not set"
        exit 1
    fi
    
    # Verify project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Project ${PROJECT_ID} does not exist or is not accessible"
        exit 1
    fi
    
    # Check if region is set
    if [[ -z "${REGION:-}" ]]; then
        log_error "REGION environment variable is not set"
        exit 1
    fi
    
    log_success "Configuration validation passed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "videointelligence.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "pubsub.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if ! gcloud services enable "${api}" --project="${PROJECT_ID}"; then
            log_error "Failed to enable API: ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled successfully"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: ${BUCKET_NAME}"
    
    # Check if bucket already exists
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists, skipping creation"
    else
        # Create bucket with appropriate configuration
        gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"
        
        # Enable versioning for data protection
        gsutil versioning set on "gs://${BUCKET_NAME}"
        
        log_success "Storage bucket created: gs://${BUCKET_NAME}"
    fi
    
    # Create folder structure
    log_info "Creating folder structure..."
    echo "Processing videos..." | gsutil cp - "gs://${BUCKET_NAME}/processing/.keep"
    echo "Approved videos..." | gsutil cp - "gs://${BUCKET_NAME}/approved/.keep"
    echo "Flagged videos..." | gsutil cp - "gs://${BUCKET_NAME}/flagged/.keep"
    
    log_success "Folder structure created successfully"
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topic: ${PUBSUB_TOPIC}"
    
    # Check if topic already exists
    if gcloud pubsub topics describe "${PUBSUB_TOPIC}" &>/dev/null; then
        log_warning "Pub/Sub topic ${PUBSUB_TOPIC} already exists, skipping creation"
    else
        # Create topic
        gcloud pubsub topics create "${PUBSUB_TOPIC}"
        
        # Configure message retention
        gcloud pubsub topics update "${PUBSUB_TOPIC}" \
            --message-retention-duration=24h
        
        log_success "Pub/Sub topic created: ${PUBSUB_TOPIC}"
    fi
    
    # Create subscription
    log_info "Creating Pub/Sub subscription: ${PUBSUB_TOPIC}-sub"
    
    if gcloud pubsub subscriptions describe "${PUBSUB_TOPIC}-sub" &>/dev/null; then
        log_warning "Subscription ${PUBSUB_TOPIC}-sub already exists, skipping creation"
    else
        gcloud pubsub subscriptions create "${PUBSUB_TOPIC}-sub" \
            --topic="${PUBSUB_TOPIC}" \
            --ack-deadline=600 \
            --message-retention-duration=24h
        
        log_success "Pub/Sub subscription created: ${PUBSUB_TOPIC}-sub"
    fi
}

# Function to create and deploy Cloud Function
deploy_cloud_function() {
    log_info "Preparing Cloud Function deployment..."
    
    # Create temporary directory for function code
    local function_dir=$(mktemp -d)
    
    # Create main.py with video moderation logic
    cat > "${function_dir}/main.py" << 'EOF'
import json
import os
import logging
from google.cloud import videointelligence
from google.cloud import storage
from google.cloud import logging as cloud_logging
import functions_framework

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

@functions_framework.cloud_event
def video_moderation_handler(cloud_event):
    """
    Process video moderation requests triggered by Cloud Scheduler.
    Analyzes videos for explicit content using Video Intelligence API.
    """
    try:
        # Initialize clients
        video_client = videointelligence.VideoIntelligenceServiceClient()
        storage_client = storage.Client()
        
        # Parse message data
        message_data = json.loads(cloud_event.data.get('message', {}).get('data', '{}'))
        bucket_name = message_data.get('bucket', os.environ['BUCKET_NAME'])
        
        logger.info(f"Processing moderation for bucket: {bucket_name}")
        
        # List videos in processing folder
        bucket = storage_client.bucket(bucket_name)
        blobs = list(bucket.list_blobs(prefix='processing/'))
        
        for blob in blobs:
            if blob.name.endswith(('.mp4', '.avi', '.mov', '.mkv')):
                process_video(video_client, storage_client, bucket_name, blob.name)
        
        logger.info("Video moderation batch processing completed")
        
    except Exception as e:
        logger.error(f"Error in video moderation: {str(e)}")
        raise

def process_video(video_client, storage_client, bucket_name, video_path):
    """
    Analyze individual video for explicit content and take moderation action.
    """
    try:
        # Configure video analysis request
        gcs_uri = f"gs://{bucket_name}/{video_path}"
        features = [videointelligence.Feature.EXPLICIT_CONTENT_DETECTION]
        
        logger.info(f"Analyzing video: {gcs_uri}")
        
        # Submit video for analysis
        operation = video_client.annotate_video(
            request={
                "input_uri": gcs_uri,
                "features": features,
            }
        )
        
        # Wait for analysis completion
        result = operation.result(timeout=300)
        
        # Process explicit content detection results
        moderation_result = analyze_explicit_content(result)
        
        # Take moderation action based on analysis
        take_moderation_action(storage_client, bucket_name, video_path, moderation_result)
        
        logger.info(f"Video analysis completed: {video_path}")
        
    except Exception as e:
        logger.error(f"Error processing video {video_path}: {str(e)}")

def analyze_explicit_content(result):
    """
    Analyze explicit content detection results and determine moderation action.
    """
    explicit_annotation = result.annotation_results[0].explicit_annotation
    
    # Calculate overall confidence score
    total_frames = len(explicit_annotation.frames)
    if total_frames == 0:
        return {"action": "approve", "confidence": 0.0, "reason": "No frames analyzed"}
    
    high_confidence_count = 0
    total_confidence = 0
    
    for frame in explicit_annotation.frames:
        confidence = frame.pornography_likelihood.value
        total_confidence += confidence
        
        # Count high-confidence explicit content frames
        if confidence >= 3:  # POSSIBLE or higher
            high_confidence_count += 1
    
    average_confidence = total_confidence / total_frames
    explicit_ratio = high_confidence_count / total_frames
    
    # Determine moderation action
    if explicit_ratio > 0.1 or average_confidence > 3:
        return {
            "action": "flag",
            "confidence": average_confidence,
            "explicit_ratio": explicit_ratio,
            "reason": f"High explicit content ratio: {explicit_ratio:.2%}"
        }
    else:
        return {
            "action": "approve",
            "confidence": average_confidence,
            "explicit_ratio": explicit_ratio,
            "reason": "Content within acceptable thresholds"
        }

def take_moderation_action(storage_client, bucket_name, video_path, moderation_result):
    """
    Move video to appropriate folder based on moderation result.
    """
    bucket = storage_client.bucket(bucket_name)
    source_blob = bucket.blob(video_path)
    
    # Determine target folder based on moderation action
    if moderation_result["action"] == "flag":
        target_path = video_path.replace("processing/", "flagged/")
    else:
        target_path = video_path.replace("processing/", "approved/")
    
    # Copy video to target folder
    target_blob = bucket.copy_blob(source_blob, bucket, target_path)
    
    # Delete original video from processing folder
    source_blob.delete()
    
    # Log moderation decision
    logger.info(f"Video moderation completed - Action: {moderation_result['action']}, "
                f"Confidence: {moderation_result['confidence']:.2f}, "
                f"Target: {target_path}")
EOF
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-videointelligence==2.13.3
google-cloud-storage==2.10.0
google-cloud-logging==3.8.0
functions-framework==3.4.0
EOF
    
    log_info "Deploying Cloud Function: ${FUNCTION_NAME}"
    
    # Deploy the function
    gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --region="${REGION}" \
        --runtime=python311 \
        --source="${function_dir}" \
        --entry-point=video_moderation_handler \
        --trigger-topic="${PUBSUB_TOPIC}" \
        --timeout=540 \
        --memory=1024Mi \
        --max-instances=10 \
        --set-env-vars=BUCKET_NAME="${BUCKET_NAME}"
    
    # Clean up temporary directory
    rm -rf "${function_dir}"
    
    # Verify deployment
    local status=$(gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --format="value(status)")
    if [[ "${status}" == "ACTIVE" ]]; then
        log_success "Cloud Function deployed successfully: ${FUNCTION_NAME}"
    else
        log_error "Cloud Function deployment failed. Status: ${status}"
        exit 1
    fi
}

# Function to create service account and configure IAM
setup_service_account_and_iam() {
    log_info "Setting up service account and IAM permissions..."
    
    # Create service account for scheduler
    local sa_email="video-moderation-scheduler@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "${sa_email}" &>/dev/null; then
        log_warning "Service account video-moderation-scheduler already exists, skipping creation"
    else
        gcloud iam service-accounts create video-moderation-scheduler \
            --display-name="Video Moderation Scheduler" \
            --description="Service account for automated video moderation scheduling"
        
        log_success "Service account created: video-moderation-scheduler"
    fi
    
    # Grant necessary permissions for Pub/Sub publishing
    log_info "Configuring IAM permissions..."
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${sa_email}" \
        --role="roles/pubsub.publisher"
    
    # Grant permissions for Cloud Scheduler operations
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${sa_email}" \
        --role="roles/cloudscheduler.jobRunner"
    
    # Grant Video Intelligence API access to function
    local app_sa="${PROJECT_ID}@appspot.gserviceaccount.com"
    
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${app_sa}" \
        --role="roles/videointelligence.editor"
    
    # Grant Storage access for video file management
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${app_sa}" \
        --role="roles/storage.objectAdmin"
    
    # Grant logging permissions for audit trail
    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${app_sa}" \
        --role="roles/logging.logWriter"
    
    log_success "IAM permissions configured successfully"
}

# Function to create Cloud Scheduler job
create_scheduler_job() {
    log_info "Creating Cloud Scheduler job: ${SCHEDULER_JOB}"
    
    # Check if job already exists
    if gcloud scheduler jobs describe "${SCHEDULER_JOB}" --location="${REGION}" &>/dev/null; then
        log_warning "Scheduler job ${SCHEDULER_JOB} already exists, skipping creation"
    else
        # Create scheduled job for video moderation
        gcloud scheduler jobs create pubsub "${SCHEDULER_JOB}" \
            --schedule="0 */4 * * *" \
            --topic="${PUBSUB_TOPIC}" \
            --message-body="{\"bucket\":\"${BUCKET_NAME}\",\"trigger\":\"scheduled\"}" \
            --time-zone="America/New_York" \
            --location="${REGION}"
        
        log_success "Cloud Scheduler job created: ${SCHEDULER_JOB}"
        log_info "Schedule: Every 4 hours for batch video processing"
    fi
    
    # Verify job state
    local job_state=$(gcloud scheduler jobs describe "${SCHEDULER_JOB}" --location="${REGION}" --format="value(state)")
    if [[ "${job_state}" == "ENABLED" ]]; then
        log_success "Scheduler job is enabled and ready"
    else
        log_warning "Scheduler job state: ${job_state}"
    fi
}

# Function to upload sample content for testing
upload_test_content() {
    log_info "Uploading sample content for testing..."
    
    # Create sample video placeholder for testing
    local temp_file=$(mktemp)
    echo "This is a sample video file for testing video moderation workflow" > "${temp_file}"
    
    # Upload sample to processing folder
    gsutil cp "${temp_file}" "gs://${BUCKET_NAME}/processing/sample-video.mp4"
    
    # Clean up temporary file
    rm -f "${temp_file}"
    
    # Verify upload
    if gsutil ls "gs://${BUCKET_NAME}/processing/sample-video.mp4" &>/dev/null; then
        log_success "Sample video uploaded for testing"
    else
        log_error "Failed to upload sample video"
        exit 1
    fi
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check Cloud Scheduler job
    local job_status=$(gcloud scheduler jobs describe "${SCHEDULER_JOB}" --location="${REGION}" --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    if [[ "${job_status}" == "ENABLED" ]]; then
        log_success "✓ Cloud Scheduler job is active"
    else
        log_error "✗ Cloud Scheduler job verification failed: ${job_status}"
        return 1
    fi
    
    # Check Cloud Function
    local function_status=$(gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
    if [[ "${function_status}" == "ACTIVE" ]]; then
        log_success "✓ Cloud Function is active"
    else
        log_error "✗ Cloud Function verification failed: ${function_status}"
        return 1
    fi
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe "${PUBSUB_TOPIC}" &>/dev/null; then
        log_success "✓ Pub/Sub topic exists"
    else
        log_error "✗ Pub/Sub topic verification failed"
        return 1
    fi
    
    # Check Storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_success "✓ Storage bucket is accessible"
    else
        log_error "✗ Storage bucket verification failed"
        return 1
    fi
    
    log_success "All components verified successfully"
}

# Function to display deployment summary
display_deployment_summary() {
    log_success "🎉 Video Content Moderation Workflow Deployed Successfully!"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                           DEPLOYMENT SUMMARY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "📁 Project ID:           ${PROJECT_ID}"
    echo "🌍 Region:              ${REGION}"
    echo "🪣 Storage Bucket:       gs://${BUCKET_NAME}"
    echo "⚡ Cloud Function:       ${FUNCTION_NAME}"
    echo "📡 Pub/Sub Topic:        ${PUBSUB_TOPIC}"
    echo "⏰ Scheduler Job:        ${SCHEDULER_JOB}"
    echo "📅 Schedule:             Every 4 hours (0 */4 * * *)"
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "                              NEXT STEPS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    echo "1. Upload videos to:     gs://${BUCKET_NAME}/processing/"
    echo "2. Monitor function logs: gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}"
    echo "3. Check approved videos: gs://${BUCKET_NAME}/approved/"
    echo "4. Check flagged videos:  gs://${BUCKET_NAME}/flagged/"
    echo "5. Manual trigger:       gcloud scheduler jobs run ${SCHEDULER_JOB} --location=${REGION}"
    echo
    echo "📖 For more information, refer to the README.md file"
    echo "🧹 To clean up resources, run: ./scripts/destroy.sh"
    echo
}

# Main deployment function
main() {
    echo
    log_info "Starting Video Content Moderation Workflow Deployment"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-video-moderation-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    local random_suffix=$(openssl rand -hex 3)
    export BUCKET_NAME="${BUCKET_NAME:-video-moderation-${random_suffix}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-video-moderator-${random_suffix}}"
    export SCHEDULER_JOB="${SCHEDULER_JOB:-moderation-job-${random_suffix}}"
    export PUBSUB_TOPIC="${PUBSUB_TOPIC:-video-moderation-${random_suffix}}"
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Execute deployment steps
    check_prerequisites
    validate_configuration
    enable_apis
    create_storage_bucket
    create_pubsub_resources
    deploy_cloud_function
    setup_service_account_and_iam
    create_scheduler_job
    upload_test_content
    verify_deployment
    display_deployment_summary
    
    log_success "Deployment completed successfully! 🚀"
}

# Handle script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi