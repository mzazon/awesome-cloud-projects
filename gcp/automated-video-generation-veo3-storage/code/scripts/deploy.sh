#!/bin/bash

# Automated Video Generation with Veo 3 and Storage - Deployment Script
# This script deploys the complete automated video generation system on GCP
# Version: 1.0
# Last Updated: 2025-07-12

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_PREFIX="video-gen"
readonly DEFAULT_REGION="us-central1"
readonly DEFAULT_ZONE="us-central1-a"
readonly DEPLOYMENT_LOG="${SCRIPT_DIR}/deployment.log"
readonly RESOURCE_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NC}  ${message}" | tee -a "$DEPLOYMENT_LOG" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC}  ${message}" | tee -a "$DEPLOYMENT_LOG" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "$DEPLOYMENT_LOG" ;;
        "DEBUG") echo -e "${BLUE}[DEBUG]${NC} ${message}" | tee -a "$DEPLOYMENT_LOG" ;;
    esac
}

# Error handler
error_exit() {
    local line_number="$1"
    local error_code="$2"
    log "ERROR" "Script failed at line ${line_number} with exit code ${error_code}"
    log "ERROR" "Check deployment log: ${DEPLOYMENT_LOG}"
    exit "${error_code}"
}

trap 'error_exit ${LINENO} $?' ERR

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy the Automated Video Generation system with Veo 3 and Cloud Storage.

OPTIONS:
    -p, --project PROJECT_ID    GCP Project ID (required)
    -r, --region REGION         GCP region (default: ${DEFAULT_REGION})
    -z, --zone ZONE             GCP zone (default: ${DEFAULT_ZONE})
    -e, --email EMAIL           Notification email for alerts
    -d, --dry-run               Perform a dry run without creating resources
    -f, --force                 Force deployment even if resources exist
    -v, --verbose               Enable verbose logging
    -h, --help                  Show this help message

EXAMPLES:
    $0 --project my-video-project --email admin@example.com
    $0 -p my-project -r us-west1 -z us-west1-a --dry-run
    $0 --project video-gen-prod --force --verbose

PREREQUISITES:
    - Google Cloud CLI installed and authenticated
    - Billing enabled on the GCP project
    - Required APIs enabled (or script will enable them)
    - Appropriate IAM permissions

ESTIMATED COST:
    - Setup: $0-2 (API calls, Cloud Functions cold starts)
    - Video generation: $0.75 per second of video content
    - Storage: $0.02 per GB per month
    - Scheduler: $0.10 per job per month

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -e|--email)
                NOTIFICATION_EMAIL="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_DEPLOY=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Initialize default values
PROJECT_ID=""
REGION="${DEFAULT_REGION}"
ZONE="${DEFAULT_ZONE}"
NOTIFICATION_EMAIL=""
DRY_RUN=false
FORCE_DEPLOY=false
VERBOSE=false

# Validate prerequisites
validate_prerequisites() {
    log "INFO" "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log "ERROR" "Google Cloud CLI is not installed. Please install it first."
        log "INFO" "Installation guide: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 > /dev/null; then
        log "ERROR" "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Validate project ID
    if [[ -z "$PROJECT_ID" ]]; then
        log "ERROR" "Project ID is required. Use -p or --project option."
        usage
        exit 1
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log "ERROR" "Project '$PROJECT_ID' does not exist or is not accessible"
        exit 1
    fi
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" | grep -q "True"; then
        log "ERROR" "Billing is not enabled for project '$PROJECT_ID'"
        log "INFO" "Enable billing: https://console.cloud.google.com/billing"
        exit 1
    fi
    
    log "INFO" "Prerequisites validation completed successfully"
}

# Configure GCP project settings
configure_project() {
    log "INFO" "Configuring GCP project settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would configure project: $PROJECT_ID"
        log "INFO" "[DRY RUN] Would set region: $REGION"
        log "INFO" "[DRY RUN] Would set zone: $ZONE"
        return 0
    fi
    
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log "INFO" "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log "INFO" "Enabling required APIs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would enable APIs: ${apis[*]}"
        return 0
    fi
    
    for api in "${apis[@]}"; do
        log "INFO" "Enabling $api..."
        if ! gcloud services enable "$api" --quiet; then
            log "ERROR" "Failed to enable $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "INFO" "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log "INFO" "All required APIs enabled successfully"
}

# Generate unique resource names
generate_resource_names() {
    log "INFO" "Generating unique resource names..."
    
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    TIMESTAMP=$(date +%s)
    
    # Storage buckets
    INPUT_BUCKET="${PROJECT_ID}-video-briefs-${RANDOM_SUFFIX}"
    OUTPUT_BUCKET="${PROJECT_ID}-generated-videos-${RANDOM_SUFFIX}"
    
    # Service account
    SERVICE_ACCOUNT="video-gen-sa-${RANDOM_SUFFIX}"
    
    # Cloud Functions
    VIDEO_FUNCTION_NAME="video-generation-${RANDOM_SUFFIX}"
    ORCHESTRATOR_FUNCTION_NAME="video-orchestrator-${RANDOM_SUFFIX}"
    
    # Scheduler jobs
    SCHEDULED_JOB_NAME="automated-video-generation-${RANDOM_SUFFIX}"
    ONDEMAND_JOB_NAME="on-demand-video-generation-${RANDOM_SUFFIX}"
    
    # Save resource names to state file
    cat > "$RESOURCE_STATE_FILE" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
INPUT_BUCKET=${INPUT_BUCKET}
OUTPUT_BUCKET=${OUTPUT_BUCKET}
SERVICE_ACCOUNT=${SERVICE_ACCOUNT}
VIDEO_FUNCTION_NAME=${VIDEO_FUNCTION_NAME}
ORCHESTRATOR_FUNCTION_NAME=${ORCHESTRATOR_FUNCTION_NAME}
SCHEDULED_JOB_NAME=${SCHEDULED_JOB_NAME}
ONDEMAND_JOB_NAME=${ONDEMAND_JOB_NAME}
DEPLOYMENT_TIMESTAMP=${TIMESTAMP}
EOF
    
    log "INFO" "Resource names generated and saved to state file"
    [[ "$VERBOSE" == "true" ]] && log "DEBUG" "State file: $RESOURCE_STATE_FILE"
}

# Create Cloud Storage buckets
create_storage_buckets() {
    log "INFO" "Creating Cloud Storage buckets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create input bucket: gs://${INPUT_BUCKET}"
        log "INFO" "[DRY RUN] Would create output bucket: gs://${OUTPUT_BUCKET}"
        return 0
    fi
    
    # Create input bucket for creative briefs
    log "INFO" "Creating input bucket: ${INPUT_BUCKET}"
    if ! gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://${INPUT_BUCKET}"; then
        log "ERROR" "Failed to create input bucket"
        exit 1
    fi
    
    # Create output bucket for generated videos
    log "INFO" "Creating output bucket: ${OUTPUT_BUCKET}"
    if ! gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://${OUTPUT_BUCKET}"; then
        log "ERROR" "Failed to create output bucket"
        exit 1
    fi
    
    # Enable versioning for content protection
    log "INFO" "Enabling versioning on buckets..."
    gsutil versioning set on "gs://${INPUT_BUCKET}"
    gsutil versioning set on "gs://${OUTPUT_BUCKET}"
    
    # Set up bucket folder structure
    log "INFO" "Creating bucket folder structure..."
    echo "" | gsutil cp - "gs://${INPUT_BUCKET}/briefs/.keep"
    echo "" | gsutil cp - "gs://${OUTPUT_BUCKET}/videos/.keep"
    echo "" | gsutil cp - "gs://${OUTPUT_BUCKET}/metadata/.keep"
    echo "" | gsutil cp - "gs://${OUTPUT_BUCKET}/reports/.keep"
    
    log "INFO" "Storage buckets created successfully"
}

# Create service account with appropriate permissions
create_service_account() {
    log "INFO" "Creating service account..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create service account: ${SERVICE_ACCOUNT}"
        log "INFO" "[DRY RUN] Would assign IAM roles for Vertex AI and Storage access"
        return 0
    fi
    
    # Create service account
    log "INFO" "Creating service account: ${SERVICE_ACCOUNT}"
    if ! gcloud iam service-accounts create "$SERVICE_ACCOUNT" \
        --display-name="Video Generation Service Account" \
        --description="Service account for automated Veo 3 video generation"; then
        log "ERROR" "Failed to create service account"
        exit 1
    fi
    
    # Grant necessary permissions
    local roles=(
        "roles/aiplatform.user"
        "roles/storage.admin"
        "roles/logging.logWriter"
        "roles/monitoring.metricWriter"
    )
    
    for role in "${roles[@]}"; do
        log "INFO" "Granting role: $role"
        if ! gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="$role" --quiet; then
            log "ERROR" "Failed to grant role: $role"
            exit 1
        fi
    done
    
    log "INFO" "Service account created with appropriate permissions"
}

# Deploy Cloud Functions
deploy_cloud_functions() {
    log "INFO" "Deploying Cloud Functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would deploy video generation function: ${VIDEO_FUNCTION_NAME}"
        log "INFO" "[DRY RUN] Would deploy orchestrator function: ${ORCHESTRATOR_FUNCTION_NAME}"
        return 0
    fi
    
    # Create temporary directories for function source
    local video_function_dir
    local orchestrator_function_dir
    video_function_dir=$(mktemp -d)
    orchestrator_function_dir=$(mktemp -d)
    
    # Copy function templates if they exist, otherwise create them
    if [[ -f "${SCRIPT_DIR}/../terraform/function_templates/video_generation.py" ]]; then
        cp "${SCRIPT_DIR}/../terraform/function_templates/video_generation.py" "${video_function_dir}/main.py"
        cp "${SCRIPT_DIR}/../terraform/function_templates/requirements.txt" "${video_function_dir}/"
    else
        # Create video generation function
        create_video_generation_function "$video_function_dir"
    fi
    
    if [[ -f "${SCRIPT_DIR}/../terraform/function_templates/orchestrator.py" ]]; then
        cp "${SCRIPT_DIR}/../terraform/function_templates/orchestrator.py" "${orchestrator_function_dir}/main.py"
        cp "${SCRIPT_DIR}/../terraform/function_templates/orchestrator_requirements.txt" "${orchestrator_function_dir}/requirements.txt"
    else
        # Create orchestrator function
        create_orchestrator_function "$orchestrator_function_dir"
    fi
    
    # Deploy video generation function
    log "INFO" "Deploying video generation function..."
    (cd "$video_function_dir" && \
        gcloud functions deploy "$VIDEO_FUNCTION_NAME" \
            --gen2 \
            --runtime python312 \
            --trigger-http \
            --source . \
            --entry-point generate_video \
            --memory 1024MB \
            --timeout 540s \
            --service-account "${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --set-env-vars "GCP_PROJECT=${PROJECT_ID},FUNCTION_REGION=${REGION}" \
            --allow-unauthenticated \
            --region="$REGION" \
            --quiet)
    
    # Get video function URL
    VIDEO_FUNCTION_URL=$(gcloud functions describe "$VIDEO_FUNCTION_NAME" \
        --region="$REGION" \
        --gen2 \
        --format="value(serviceConfig.uri)")
    
    # Deploy orchestrator function
    log "INFO" "Deploying orchestrator function..."
    (cd "$orchestrator_function_dir" && \
        gcloud functions deploy "$ORCHESTRATOR_FUNCTION_NAME" \
            --gen2 \
            --runtime python312 \
            --trigger-http \
            --source . \
            --entry-point orchestrate_video_generation \
            --memory 512MB \
            --timeout 900s \
            --service-account "${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --set-env-vars "INPUT_BUCKET=${INPUT_BUCKET},OUTPUT_BUCKET=${OUTPUT_BUCKET},VIDEO_FUNCTION_URL=${VIDEO_FUNCTION_URL}" \
            --allow-unauthenticated \
            --region="$REGION" \
            --quiet)
    
    # Get orchestrator function URL
    ORCHESTRATOR_URL=$(gcloud functions describe "$ORCHESTRATOR_FUNCTION_NAME" \
        --region="$REGION" \
        --gen2 \
        --format="value(serviceConfig.uri)")
    
    # Clean up temporary directories
    rm -rf "$video_function_dir" "$orchestrator_function_dir"
    
    # Update state file with function URLs
    cat >> "$RESOURCE_STATE_FILE" << EOF
VIDEO_FUNCTION_URL=${VIDEO_FUNCTION_URL}
ORCHESTRATOR_URL=${ORCHESTRATOR_URL}
EOF
    
    log "INFO" "Cloud Functions deployed successfully"
}

# Create video generation function source
create_video_generation_function() {
    local function_dir="$1"
    
    cat > "${function_dir}/main.py" << 'EOF'
import json
import os
import logging
import time
import uuid
from google.cloud import storage
from google import genai
from google.genai import types
import functions_framework

# Initialize Google Gen AI client for Vertex AI
PROJECT_ID = os.environ.get('GCP_PROJECT')
REGION = os.environ.get('FUNCTION_REGION', 'us-central1')

@functions_framework.http
def generate_video(request):
    """Cloud Function to generate videos using Veo 3"""
    try:
        # Initialize client with Vertex AI
        client = genai.Client(vertexai=True, project=PROJECT_ID, location=REGION)
        
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'No JSON data provided'}, 400
        
        prompt = request_json.get('prompt')
        output_bucket = request_json.get('output_bucket')
        resolution = request_json.get('resolution', '1080p')
        
        if not prompt or not output_bucket:
            return {'error': 'Missing required parameters'}, 400
        
        # Generate unique filename and GCS path
        video_id = str(uuid.uuid4())
        filename = f"generated_video_{video_id}.mp4"
        output_gcs_uri = f"gs://{output_bucket}/videos/{filename}"
        
        logging.info(f"Generating video for prompt: {prompt[:100]}...")
        
        # Generate video using Veo 3
        operation = client.models.generate_videos(
            model="veo-3.0-generate-preview",
            prompt=prompt,
            config=types.GenerateVideosConfig(
                aspect_ratio="16:9",
                output_gcs_uri=output_gcs_uri,
                number_of_videos=1,
                duration_seconds=8,
                person_generation="allow_adult",
            ),
        )
        
        # Poll for completion
        max_wait_time = 300  # 5 minutes
        start_time = time.time()
        
        while not operation.done and (time.time() - start_time) < max_wait_time:
            time.sleep(15)
            operation = client.operations.get(operation)
        
        if not operation.done:
            return {'error': 'Video generation timed out'}, 500
        
        if operation.response and operation.result.generated_videos:
            video_uri = operation.result.generated_videos[0].video.uri
            
            # Save metadata
            video_metadata = {
                "video_id": video_id,
                "prompt": prompt,
                "resolution": resolution,
                "video_uri": video_uri,
                "generated_at": time.time(),
                "status": "completed",
                "duration_seconds": 8
            }
            
            storage_client = storage.Client()
            bucket = storage_client.bucket(output_bucket)
            metadata_blob = bucket.blob(f"metadata/{video_id}.json")
            metadata_blob.upload_from_string(
                json.dumps(video_metadata, indent=2),
                content_type='application/json'
            )
            
            logging.info(f"Video generation completed: {filename}")
            
            return {
                'status': 'success',
                'video_id': video_id,
                'filename': filename,
                'video_uri': video_uri,
                'metadata': video_metadata
            }
        else:
            return {'error': 'Video generation failed'}, 500
        
    except Exception as e:
        logging.error(f"Error generating video: {str(e)}")
        return {'error': str(e)}, 500
EOF

    cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-storage==2.16.0
google-genai==0.3.0
functions-framework==3.5.0
EOF
}

# Create orchestrator function source
create_orchestrator_function() {
    local function_dir="$1"
    
    cat > "${function_dir}/main.py" << 'EOF'
import json
import os
import logging
import time
import requests
from google.cloud import storage
import functions_framework

@functions_framework.http
def orchestrate_video_generation(request):
    """Orchestrate batch video generation from creative briefs"""
    try:
        # Get environment variables
        input_bucket = os.environ.get('INPUT_BUCKET')
        output_bucket = os.environ.get('OUTPUT_BUCKET')
        video_function_url = os.environ.get('VIDEO_FUNCTION_URL')
        
        if not all([input_bucket, output_bucket, video_function_url]):
            return {'error': 'Missing required environment variables'}, 500
        
        # List creative brief files
        storage_client = storage.Client()
        bucket = storage_client.bucket(input_bucket)
        
        briefs = []
        for blob in bucket.list_blobs(prefix='briefs/'):
            if blob.name.endswith('.json'):
                briefs.append(blob.name)
        
        logging.info(f"Found {len(briefs)} creative briefs to process")
        
        # Process each brief
        results = []
        for brief_file in briefs:
            try:
                # Download and parse brief
                blob = bucket.blob(brief_file)
                brief_content = json.loads(blob.download_as_text())
                
                # Prepare generation request
                generation_request = {
                    'prompt': brief_content.get('video_prompt'),
                    'output_bucket': output_bucket,
                    'resolution': brief_content.get('resolution', '1080p'),
                    'brief_id': brief_content.get('id', brief_file)
                }
                
                # Call video generation function
                response = requests.post(
                    video_function_url,
                    json=generation_request,
                    headers={'Content-Type': 'application/json'},
                    timeout=600
                )
                
                if response.status_code == 200:
                    result = response.json()
                    results.append({
                        'brief': brief_file,
                        'status': 'success',
                        'video_id': result.get('video_id'),
                        'filename': result.get('filename'),
                        'video_uri': result.get('video_uri')
                    })
                    logging.info(f"Successfully processed brief: {brief_file}")
                else:
                    logging.error(f"Failed to process brief {brief_file}: {response.text}")
                    results.append({
                        'brief': brief_file,
                        'status': 'failed',
                        'error': response.text
                    })
                
                # Add delay between requests to avoid rate limits
                time.sleep(5)
                
            except Exception as e:
                logging.error(f"Error processing brief {brief_file}: {str(e)}")
                results.append({
                    'brief': brief_file,
                    'status': 'error',
                    'error': str(e)
                })
        
        # Generate summary report
        successful = len([r for r in results if r['status'] == 'success'])
        failed = len(results) - successful
        
        summary = {
            'total_briefs': len(briefs),
            'successful_generations': successful,
            'failed_generations': failed,
            'results': results,
            'processed_at': time.time()
        }
        
        # Save batch processing report
        output_bucket_obj = storage_client.bucket(output_bucket)
        report_blob = output_bucket_obj.blob(f"reports/batch_report_{int(time.time())}.json")
        report_blob.upload_from_string(
            json.dumps(summary, indent=2),
            content_type='application/json'
        )
        
        logging.info(f"Batch processing completed: {successful}/{len(briefs)} successful")
        
        return summary
        
    except Exception as e:
        logging.error(f"Error in orchestration: {str(e)}")
        return {'error': str(e)}, 500
EOF

    cat > "${function_dir}/requirements.txt" << 'EOF'
google-cloud-storage==2.16.0
requests==2.31.0
functions-framework==3.5.0
EOF
}

# Create Cloud Scheduler jobs
create_scheduler_jobs() {
    log "INFO" "Creating Cloud Scheduler jobs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would create scheduled job: ${SCHEDULED_JOB_NAME}"
        log "INFO" "[DRY RUN] Would create on-demand job: ${ONDEMAND_JOB_NAME}"
        return 0
    fi
    
    # Create scheduled job for automated video generation
    log "INFO" "Creating automated scheduling job..."
    if ! gcloud scheduler jobs create http "$SCHEDULED_JOB_NAME" \
        --location="$REGION" \
        --schedule="0 9 * * MON,WED,FRI" \
        --uri="$ORCHESTRATOR_URL" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"trigger":"scheduled","batch_size":10}' \
        --time-zone="America/New_York" \
        --quiet; then
        log "ERROR" "Failed to create scheduled job"
        exit 1
    fi
    
    # Create on-demand job for immediate processing
    log "INFO" "Creating on-demand processing job..."
    if ! gcloud scheduler jobs create http "$ONDEMAND_JOB_NAME" \
        --location="$REGION" \
        --schedule="0 0 31 2 *" \
        --uri="$ORCHESTRATOR_URL" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body='{"trigger":"manual","batch_size":5}' \
        --time-zone="America/New_York" \
        --quiet; then
        log "ERROR" "Failed to create on-demand job"
        exit 1
    fi
    
    log "INFO" "Cloud Scheduler jobs created successfully"
}

# Upload sample creative briefs
upload_sample_briefs() {
    log "INFO" "Uploading sample creative briefs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would upload sample creative briefs"
        return 0
    fi
    
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Create sample product launch brief
    cat > "${temp_dir}/sample_brief.json" << 'EOF'
{
  "id": "brief_001",
  "title": "Product Launch Video",
  "video_prompt": "A sleek modern smartphone floating in a minimalist white environment with soft lighting, slowly rotating to show all angles, with subtle particle effects and elegant typography appearing to highlight key features",
  "resolution": "1080p",
  "duration": "8s",
  "style": "modern, clean, professional",
  "target_audience": "tech enthusiasts",
  "brand_guidelines": {
    "colors": ["#1a73e8", "#ffffff", "#f8f9fa"],
    "tone": "innovative, premium"
  },
  "created_at": "2025-07-12T10:00:00Z",
  "created_by": "marketing_team"
}
EOF
    
    # Create sample lifestyle brief
    cat > "${temp_dir}/lifestyle_brief.json" << 'EOF'
{
  "id": "brief_002",
  "title": "Lifestyle Brand Video",
  "video_prompt": "A serene morning scene with golden sunlight streaming through a window, a steaming coffee cup on a wooden table, plants in the background, creating a warm and inviting atmosphere for wellness and mindfulness",
  "resolution": "1080p",
  "duration": "8s",
  "style": "warm, natural, lifestyle",
  "target_audience": "wellness enthusiasts",
  "brand_guidelines": {
    "colors": ["#8bc34a", "#ff9800", "#795548"],
    "tone": "calming, authentic"
  },
  "created_at": "2025-07-12T10:15:00Z",
  "created_by": "content_team"
}
EOF
    
    # Upload sample briefs
    gsutil cp "${temp_dir}/sample_brief.json" "gs://${INPUT_BUCKET}/briefs/"
    gsutil cp "${temp_dir}/lifestyle_brief.json" "gs://${INPUT_BUCKET}/briefs/"
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    log "INFO" "Sample creative briefs uploaded successfully"
}

# Configure monitoring and alerting
configure_monitoring() {
    log "INFO" "Configuring monitoring and alerting..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would configure monitoring and alerting"
        return 0
    fi
    
    # Create notification channel if email is provided
    if [[ -n "$NOTIFICATION_EMAIL" ]]; then
        log "INFO" "Creating email notification channel..."
        
        local notification_channel_config
        notification_channel_config=$(mktemp)
        
        cat > "$notification_channel_config" << EOF
{
  "type": "email",
  "displayName": "Video Generation Alerts",
  "description": "Email notifications for video generation system alerts",
  "labels": {
    "email_address": "${NOTIFICATION_EMAIL}"
  }
}
EOF
        
        local notification_channel_name
        if notification_channel_name=$(gcloud alpha monitoring channels create \
            --channel-content-from-file="$notification_channel_config" \
            --format="value(name)" 2>/dev/null); then
            
            log "INFO" "Email notification channel created: $notification_channel_name"
            
            # Create alert policy for function failures
            local alert_policy_config
            alert_policy_config=$(mktemp)
            
            cat > "$alert_policy_config" << EOF
{
  "displayName": "Video Generation Function Failures",
  "conditions": [
    {
      "displayName": "Cloud Function error rate",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\" AND metric.label.status!=\"ok\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 5,
        "duration": "300s"
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "documentation": {
    "content": "Video generation functions are experiencing high error rates"
  },
  "notificationChannels": ["${notification_channel_name}"]
}
EOF
            
            if gcloud alpha monitoring policies create \
                --policy-from-file="$alert_policy_config" &>/dev/null; then
                log "INFO" "Alert policy created for function failures"
            else
                log "WARN" "Failed to create alert policy (may not be critical)"
            fi
            
            rm -f "$alert_policy_config"
        else
            log "WARN" "Failed to create notification channel (continuing without alerts)"
        fi
        
        rm -f "$notification_channel_config"
    else
        log "INFO" "No notification email provided, skipping alert configuration"
    fi
    
    log "INFO" "Monitoring configuration completed"
}

# Perform deployment validation
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    local validation_failed=false
    
    # Check storage buckets
    log "INFO" "Checking storage buckets..."
    if ! gsutil ls -L "gs://${INPUT_BUCKET}" &>/dev/null; then
        log "ERROR" "Input bucket validation failed"
        validation_failed=true
    fi
    
    if ! gsutil ls -L "gs://${OUTPUT_BUCKET}" &>/dev/null; then
        log "ERROR" "Output bucket validation failed"
        validation_failed=true
    fi
    
    # Check Cloud Functions
    log "INFO" "Checking Cloud Functions..."
    if ! gcloud functions describe "$VIDEO_FUNCTION_NAME" --region="$REGION" --gen2 &>/dev/null; then
        log "ERROR" "Video generation function validation failed"
        validation_failed=true
    fi
    
    if ! gcloud functions describe "$ORCHESTRATOR_FUNCTION_NAME" --region="$REGION" --gen2 &>/dev/null; then
        log "ERROR" "Orchestrator function validation failed"
        validation_failed=true
    fi
    
    # Check Cloud Scheduler jobs
    log "INFO" "Checking Cloud Scheduler jobs..."
    if ! gcloud scheduler jobs describe "$SCHEDULED_JOB_NAME" --location="$REGION" &>/dev/null; then
        log "ERROR" "Scheduled job validation failed"
        validation_failed=true
    fi
    
    if ! gcloud scheduler jobs describe "$ONDEMAND_JOB_NAME" --location="$REGION" &>/dev/null; then
        log "ERROR" "On-demand job validation failed"
        validation_failed=true
    fi
    
    if [[ "$validation_failed" == "true" ]]; then
        log "ERROR" "Deployment validation failed"
        exit 1
    fi
    
    log "INFO" "Deployment validation completed successfully"
}

# Display deployment summary
display_summary() {
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat << EOF

${GREEN}================================================================================
✅ DEPLOYMENT COMPLETED SUCCESSFULLY
================================================================================${NC}

📋 DEPLOYMENT SUMMARY:
   Project ID:       ${PROJECT_ID}
   Region:           ${REGION}
   Deployment Time:  ${end_time}
   
📁 STORAGE BUCKETS:
   Input Bucket:     gs://${INPUT_BUCKET}
   Output Bucket:    gs://${OUTPUT_BUCKET}
   
🔧 CLOUD FUNCTIONS:
   Video Generation: ${VIDEO_FUNCTION_NAME}
   Orchestrator:     ${ORCHESTRATOR_FUNCTION_NAME}
   
⏰ SCHEDULER JOBS:
   Automated:        ${SCHEDULED_JOB_NAME} (Mon/Wed/Fri 9 AM)
   On-Demand:        ${ONDEMAND_JOB_NAME} (Manual trigger)

🔗 FUNCTION URLS:
   Video Generation: ${VIDEO_FUNCTION_URL}
   Orchestrator:     ${ORCHESTRATOR_URL}

📊 MONITORING:
   Function logs available in Cloud Logging
   Metrics available in Cloud Monitoring
EOF

    if [[ -n "$NOTIFICATION_EMAIL" ]]; then
        echo "   Alert notifications: ${NOTIFICATION_EMAIL}"
    fi
    
    cat << EOF

💡 NEXT STEPS:
   1. Upload creative briefs to: gs://${INPUT_BUCKET}/briefs/
   2. Trigger manual processing: gcloud scheduler jobs run ${ONDEMAND_JOB_NAME} --location=${REGION}
   3. Check generated videos in: gs://${OUTPUT_BUCKET}/videos/
   4. Monitor function logs: gcloud logs read "resource.type=cloud_function"

💰 COST ESTIMATION:
   - Setup costs: $0-2 (API calls, function cold starts)
   - Video generation: $0.75 per second of video content
   - Storage: $0.02 per GB per month
   - Scheduler: $0.10 per job per month

📄 DEPLOYMENT STATE: ${RESOURCE_STATE_FILE}
📋 DEPLOYMENT LOG:   ${DEPLOYMENT_LOG}

EOF
}

# Cleanup function for partial deployments
cleanup_on_failure() {
    log "WARN" "Deployment failed, attempting cleanup of partial resources..."
    
    if [[ -f "$RESOURCE_STATE_FILE" ]]; then
        source "$RESOURCE_STATE_FILE"
        
        # Run destroy script if it exists
        if [[ -f "${SCRIPT_DIR}/destroy.sh" ]]; then
            log "INFO" "Running destroy script for cleanup..."
            bash "${SCRIPT_DIR}/destroy.sh" --project="$PROJECT_ID" --force --quiet
        fi
    fi
}

# Main deployment function
main() {
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log "INFO" "Starting Automated Video Generation deployment at ${start_time}"
    log "INFO" "Script version: 1.0"
    log "INFO" "Deployment log: ${DEPLOYMENT_LOG}"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate prerequisites
    validate_prerequisites
    
    # Configure project
    configure_project
    
    # Enable required APIs
    enable_apis
    
    # Generate unique resource names
    generate_resource_names
    
    # Deploy infrastructure components
    create_storage_buckets
    create_service_account
    deploy_cloud_functions
    create_scheduler_jobs
    upload_sample_briefs
    configure_monitoring
    
    # Validate deployment
    validate_deployment
    
    # Display summary
    if [[ "$DRY_RUN" == "false" ]]; then
        display_summary
    else
        log "INFO" "Dry run completed successfully. No resources were created."
    fi
    
    log "INFO" "Deployment completed successfully"
}

# Set trap for cleanup on failure
trap cleanup_on_failure EXIT

# Run main function
main "$@"

# Disable trap on successful completion
trap - EXIT

exit 0