#!/bin/bash

# Deploy script for Social Media Video Creation with Veo 3 and Vertex AI
# This script creates a serverless video generation pipeline using Google's Veo 3 model

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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

if [[ "$DRY_RUN" == "true" ]]; then
    warning "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    log "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
        return 0
    else
        eval "$cmd"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random strings. Please install it first."
    fi
    
    # Check if curl is available for testing
    if ! command -v curl &> /dev/null; then
        warning "curl is not available. Some testing features may not work."
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set default project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="video-creation-$(date +%s)"
        warning "PROJECT_ID not set, using generated value: $PROJECT_ID"
    fi
    
    # Set default region
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="social-videos-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="video-generator-${RANDOM_SUFFIX}"
    
    # Create deployment state file
    DEPLOYMENT_STATE_FILE="deployment_state_${RANDOM_SUFFIX}.env"
    cat > "$DEPLOYMENT_STATE_FILE" << EOF
PROJECT_ID=$PROJECT_ID
REGION=$REGION
ZONE=$ZONE
BUCKET_NAME=$BUCKET_NAME
FUNCTION_NAME=$FUNCTION_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
DEPLOYMENT_DATE=$(date -Iseconds)
EOF
    
    success "Environment configured - Resources will use suffix: $RANDOM_SUFFIX"
    success "Deployment state saved to: $DEPLOYMENT_STATE_FILE"
}

# Function to configure GCP project
configure_project() {
    log "Configuring GCP project..."
    
    # Set default project and region
    execute_cmd "gcloud config set project ${PROJECT_ID}" "Setting default project"
    execute_cmd "gcloud config set compute/region ${REGION}" "Setting default region"
    execute_cmd "gcloud config set functions/region ${REGION}" "Setting default functions region"
    
    success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_cmd "gcloud services enable $api" "Enabling $api"
    done
    
    # Wait for APIs to be fully enabled
    if [[ "$DRY_RUN" != "true" ]]; then
        log "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    success "All required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket for video output..."
    
    # Create storage bucket with appropriate settings
    execute_cmd "gsutil mb -p ${PROJECT_ID} -c STANDARD -l ${REGION} gs://${BUCKET_NAME}" \
        "Creating storage bucket gs://${BUCKET_NAME}"
    
    # Enable versioning for video management
    execute_cmd "gsutil versioning set on gs://${BUCKET_NAME}" \
        "Enabling versioning on bucket"
    
    # Create organized folder structure for videos
    execute_cmd "echo '' | gsutil cp - gs://${BUCKET_NAME}/raw-videos/.keep" \
        "Creating raw-videos folder"
    execute_cmd "echo '' | gsutil cp - gs://${BUCKET_NAME}/processed-videos/.keep" \
        "Creating processed-videos folder"
    execute_cmd "echo '' | gsutil cp - gs://${BUCKET_NAME}/metadata/.keep" \
        "Creating metadata folder"
    
    success "Cloud Storage bucket created: gs://${BUCKET_NAME}"
}

# Function to create video generation Cloud Function
create_video_generator_function() {
    log "Creating video generation Cloud Function..."
    
    # Create function directory and dependencies
    local func_dir="video-functions/generator"
    mkdir -p "$func_dir"
    cd "$func_dir"
    
    # Create requirements.txt for Python dependencies
    cat > requirements.txt << 'EOF'
google-genai==0.12.0
google-cloud-storage==2.18.0
google-cloud-logging==3.11.0
flask==3.0.3
requests==2.32.3
EOF
    
    # Create main function file
    cat > main.py << 'EOF'
import json
import logging
import os
import time
from datetime import datetime
from google import genai
from google.genai import types
from google.cloud import storage
from google.cloud import logging as cloud_logging

# Initialize logging
cloud_logging.Client().setup_logging()
logging.basicConfig(level=logging.INFO)

def generate_video(request):
    """Cloud Function to generate videos using Veo 3"""
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json or 'prompt' not in request_json:
            return {'error': 'Missing prompt in request'}, 400
        
        prompt = request_json['prompt']
        duration = request_json.get('duration', 8)  # Default 8 seconds
        aspect_ratio = request_json.get('aspect_ratio', '9:16')  # Vertical for social media
        
        # Initialize Vertex AI client
        project_id = os.environ.get('GCP_PROJECT')
        location = "us-central1"
        
        client = genai.Client(vertexai=True, 
                             project=project_id, 
                             location=location)
        
        # Optimize prompt for social media content
        optimized_prompt = f"Create a {duration}-second engaging social media video: {prompt}. High quality, vibrant colors, smooth motion, professional lighting."
        
        # Configure video generation request
        operation = client.models.generate_videos(
            model="veo-3.0-generate-preview",
            prompt=optimized_prompt,
            config=types.GenerateVideosConfig(
                aspect_ratio=aspect_ratio,
                output_gcs_uri=f"gs://{os.environ.get('BUCKET_NAME')}/raw-videos/",
                number_of_videos=1,
                duration_seconds=duration,
                person_generation="allow_adult",
                resolution="720p"
            ),
        )
        
        # Store operation metadata
        metadata = {
            'operation_name': operation.name,
            'prompt': prompt,
            'timestamp': datetime.now().isoformat(),
            'status': 'processing',
            'duration': duration,
            'aspect_ratio': aspect_ratio
        }
        
        # Save metadata to Cloud Storage
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ.get('BUCKET_NAME'))
        operation_id = operation.name.split('/')[-1]
        blob = bucket.blob(f"metadata/{operation_id}.json")
        blob.upload_from_string(json.dumps(metadata))
        
        logging.info(f"Video generation started: {operation.name}")
        
        return {
            'status': 'success',
            'operation_name': operation.name,
            'estimated_completion': '60-120 seconds'
        }
            
    except Exception as e:
        logging.error(f"Function error: {str(e)}")
        return {'error': str(e)}, 500
EOF
    
    # Deploy function with appropriate settings
    execute_cmd "gcloud functions deploy ${FUNCTION_NAME} \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point generate_video \
        --memory 512MB \
        --timeout 540s \
        --set-env-vars BUCKET_NAME=${BUCKET_NAME}" \
        "Deploying video generator function"
    
    cd ../..
    
    success "Video generator function deployed"
}

# Function to create quality validation function
create_quality_validator_function() {
    log "Creating quality validation Cloud Function..."
    
    # Create quality validation function
    local func_dir="video-functions/validator"
    mkdir -p "$func_dir"
    cd "$func_dir"
    
    # Create requirements for validator
    cat > requirements.txt << 'EOF'
google-genai==0.12.0
google-cloud-storage==2.18.0
flask==3.0.3
opencv-python-headless==4.10.0.84
Pillow==10.4.0
EOF
    
    # Create quality validation logic
    cat > main.py << 'EOF'
import json
import logging
import os
import cv2
import base64
from datetime import datetime
from google import genai
from google.genai import types
from google.cloud import storage
import tempfile

def validate_content(request):
    """Validate video content quality using Gemini"""
    try:
        request_json = request.get_json(silent=True)
        if not request_json or 'video_uri' not in request_json:
            return {'error': 'Missing video_uri in request'}, 400
        
        video_uri = request_json['video_uri']
        
        # Initialize Vertex AI client
        project_id = os.environ.get('GCP_PROJECT')
        client = genai.Client(vertexai=True, 
                             project=project_id, 
                             location="us-central1")
        
        # Download video for analysis
        storage_client = storage.Client()
        bucket_name = video_uri.replace('gs://', '').split('/')[0]
        blob_path = '/'.join(video_uri.replace('gs://', '').split('/')[1:])
        
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_path)
        
        # Create temporary file for video processing
        with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as temp_video:
            blob.download_to_filename(temp_video.name)
            
            # Extract frames for analysis
            cap = cv2.VideoCapture(temp_video.name)
            frames = []
            frame_count = 0
            
            while frame_count < 3:  # Analyze first 3 frames
                ret, frame = cap.read()
                if not ret:
                    break
                
                # Convert frame to base64
                _, buffer = cv2.imencode('.jpg', frame)
                frame_b64 = base64.b64encode(buffer).decode()
                frames.append(frame_b64)
                frame_count += 1
            
            cap.release()
            os.unlink(temp_video.name)
        
        # Analyze content with Gemini
        analysis_prompt = """
        Analyze this video frame for social media content quality. Evaluate:
        1. Visual appeal and engagement potential (1-10)
        2. Technical quality (resolution, clarity, composition) (1-10)
        3. Brand safety and appropriateness (1-10)
        4. Social media optimization (vertical format, attention-grabbing) (1-10)
        5. Overall recommendation (approve/review/reject)
        
        Provide JSON response with scores and brief explanations.
        """
        
        # Analyze first frame
        if frames:
            image_part = types.Part.from_data(
                data=base64.b64decode(frames[0]),
                mime_type="image/jpeg"
            )
            
            response = client.models.generate_content(
                model="gemini-2.0-flash-exp",
                contents=[analysis_prompt, image_part]
            )
            
            # Parse response and create quality report
            quality_report = {
                'video_uri': video_uri,
                'analysis_timestamp': datetime.now().isoformat(),
                'gemini_analysis': response.text,
                'frame_count': len(frames),
                'status': 'analyzed'
            }
            
            # Store quality report
            report_blob = bucket.blob(f"metadata/quality_{blob_path.split('/')[-1]}.json")
            report_blob.upload_from_string(json.dumps(quality_report))
            
            return {
                'status': 'success',
                'quality_report': quality_report,
                'recommendation': 'Content analyzed successfully'
            }
        else:
            return {'error': 'No frames could be extracted from video'}, 400
            
    except Exception as e:
        logging.error(f"Validation error: {str(e)}")
        return {'error': str(e)}, 500
EOF
    
    # Deploy validation function
    execute_cmd "gcloud functions deploy validator-${RANDOM_SUFFIX} \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point validate_content \
        --memory 1GB \
        --timeout 300s \
        --set-env-vars BUCKET_NAME=${BUCKET_NAME}" \
        "Deploying quality validation function"
    
    cd ../..
    
    success "Quality validation function deployed"
}

# Function to create operation monitor function
create_monitor_function() {
    log "Creating operation status monitor Cloud Function..."
    
    # Create status monitoring function
    local func_dir="video-functions/monitor"
    mkdir -p "$func_dir"
    cd "$func_dir"
    
    cat > requirements.txt << 'EOF'
google-genai==0.12.0
google-cloud-storage==2.18.0
flask==3.0.3
EOF
    
    # Create monitor logic
    cat > main.py << 'EOF'
import json
import logging
import os
from datetime import datetime
from google import genai
from google.cloud import storage

def monitor_operations(request):
    """Monitor video generation operations"""
    try:
        # Get operation name from request
        request_json = request.get_json(silent=True)
        operation_name = request_json.get('operation_name') if request_json else None
        
        if not operation_name:
            return {'error': 'Missing operation_name'}, 400
        
        # Initialize Vertex AI client
        project_id = os.environ.get('GCP_PROJECT')
        client = genai.Client(vertexai=True, 
                             project=project_id, 
                             location="us-central1")
        
        # Check operation status
        operation = client.operations.get(operation_name)
        
        if operation.done:
            # Operation completed, extract video URI
            if operation.result and hasattr(operation.result, 'generated_videos'):
                videos = operation.result.generated_videos
                
                if videos:
                    video_uri = videos[0].video.uri
                    
                    # Update metadata
                    storage_client = storage.Client()
                    bucket = storage_client.bucket(os.environ.get('BUCKET_NAME'))
                    
                    operation_id = operation_name.split('/')[-1]
                    metadata_blob = bucket.blob(f"metadata/{operation_id}.json")
                    
                    if metadata_blob.exists():
                        metadata = json.loads(metadata_blob.download_as_text())
                        metadata.update({
                            'status': 'completed',
                            'video_uri': video_uri,
                            'completion_time': datetime.now().isoformat()
                        })
                        metadata_blob.upload_from_string(json.dumps(metadata))
                    
                    return {
                        'status': 'completed',
                        'video_uri': video_uri,
                        'operation_name': operation_name
                    }
                else:
                    return {'status': 'completed', 'error': 'No videos generated'}
            else:
                return {'status': 'completed', 'error': 'Operation failed'}
        else:
            return {'status': 'processing', 'operation_name': operation_name}
            
    except Exception as e:
        logging.error(f"Monitor error: {str(e)}")
        return {'error': str(e)}, 500
EOF
    
    # Deploy monitor function
    execute_cmd "gcloud functions deploy monitor-${RANDOM_SUFFIX} \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point monitor_operations \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars BUCKET_NAME=${BUCKET_NAME}" \
        "Deploying operation monitor function"
    
    cd ../..
    
    success "Operation monitor function deployed"
}

# Function to perform deployment validation
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Skipping validation in dry-run mode"
        return 0
    fi
    
    # Check if bucket exists
    if gsutil ls -b gs://"${BUCKET_NAME}" &> /dev/null; then
        success "Storage bucket validation passed"
    else
        error "Storage bucket validation failed"
    fi
    
    # Check if functions are deployed
    local functions=("${FUNCTION_NAME}" "validator-${RANDOM_SUFFIX}" "monitor-${RANDOM_SUFFIX}")
    
    for func in "${functions[@]}"; do
        if gcloud functions describe "$func" &> /dev/null; then
            success "Function $func validation passed"
        else
            error "Function $func validation failed"
        fi
    done
    
    # Get function URLs for testing
    local function_url
    function_url=$(gcloud functions describe "${FUNCTION_NAME}" --format="value(httpsTrigger.url)")
    
    local monitor_url
    monitor_url=$(gcloud functions describe "monitor-${RANDOM_SUFFIX}" --format="value(httpsTrigger.url)")
    
    local validator_url
    validator_url=$(gcloud functions describe "validator-${RANDOM_SUFFIX}" --format="value(httpsTrigger.url)")
    
    # Save URLs to deployment state
    cat >> "$DEPLOYMENT_STATE_FILE" << EOF
FUNCTION_URL=$function_url
MONITOR_URL=$monitor_url
VALIDATOR_URL=$validator_url
EOF
    
    success "All deployment validations passed"
}

# Function to display deployment summary
show_deployment_summary() {
    log "Deployment Summary"
    echo ""
    echo "=============================================="
    echo "Social Media Video Creation Pipeline Deployed"
    echo "=============================================="
    echo ""
    echo "📦 Resources Created:"
    echo "  • Project: $PROJECT_ID"
    echo "  • Region: $REGION"
    echo "  • Storage Bucket: gs://$BUCKET_NAME"
    echo "  • Video Generator Function: $FUNCTION_NAME"
    echo "  • Quality Validator Function: validator-$RANDOM_SUFFIX"
    echo "  • Operation Monitor Function: monitor-$RANDOM_SUFFIX"
    echo ""
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo "🔗 Endpoint URLs:"
        echo "  • Video Generator: $(gcloud functions describe "${FUNCTION_NAME}" --format="value(httpsTrigger.url)" 2>/dev/null || echo "Not available")"
        echo "  • Quality Validator: $(gcloud functions describe "validator-${RANDOM_SUFFIX}" --format="value(httpsTrigger.url)" 2>/dev/null || echo "Not available")"
        echo "  • Operation Monitor: $(gcloud functions describe "monitor-${RANDOM_SUFFIX}" --format="value(httpsTrigger.url)" 2>/dev/null || echo "Not available")"
        echo ""
    fi
    
    echo "📋 Test the deployment:"
    echo '  curl -X POST [FUNCTION_URL] \'
    echo '    -H "Content-Type: application/json" \'
    echo '    -d '"'"'{"prompt": "A colorful sunset over mountains", "duration": 8, "aspect_ratio": "9:16"}'"'"
    echo ""
    echo "🧹 To cleanup resources:"
    echo "  ./destroy.sh"
    echo ""
    echo "📄 Deployment state saved to: $DEPLOYMENT_STATE_FILE"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "This was a DRY-RUN - no actual resources were created"
    else
        success "Deployment completed successfully!"
    fi
}

# Function to handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Deployment failed with exit code $exit_code"
        log "You may need to manually clean up any partially created resources"
        if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
            log "Check deployment state file: $DEPLOYMENT_STATE_FILE"
        fi
    fi
}

# Set trap for cleanup on exit
trap cleanup_on_exit EXIT

# Main deployment function
main() {
    log "Starting Social Media Video Creation Pipeline deployment..."
    log "Target Provider: Google Cloud Platform (GCP)"
    log "Solution: Serverless video generation with Veo 3 and Vertex AI"
    echo ""
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    configure_project
    enable_apis
    create_storage_bucket
    create_video_generator_function
    create_quality_validator_function
    create_monitor_function
    validate_deployment
    show_deployment_summary
}

# Show help information
show_help() {
    echo "Social Media Video Creation Pipeline - Deploy Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --dry-run      Preview deployment without creating resources"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID     GCP Project ID (auto-generated if not set)"
    echo "  REGION         GCP Region (default: us-central1)"
    echo "  ZONE           GCP Zone (default: us-central1-a)"
    echo ""
    echo "Example:"
    echo "  PROJECT_ID=my-project ./deploy.sh"
    echo "  DRY_RUN=true ./deploy.sh"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Execute main function
main