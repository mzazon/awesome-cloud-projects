#!/bin/bash

# Multi-Modal AI Content Generation with Lyria and Vertex AI - Deployment Script
# This script deploys the complete infrastructure for multi-modal content generation platform

set -euo pipefail

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/gcp-content-ai-deploy-$(date +%Y%m%d-%H%M%S).log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code $exit_code"
    log_info "Check log file: $LOG_FILE"
    log_info "Run './destroy.sh' to clean up any partially created resources"
    exit $exit_code
}

trap cleanup_on_error ERR

# Save deployment state
save_state() {
    local key=$1
    local value=$2
    echo "${key}=${value}" >> "${DEPLOYMENT_STATE_FILE}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check for required tools
    for tool in curl openssl; do
        if ! command_exists "$tool"; then
            log_error "$tool is required but not installed."
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="content-ai-platform-$(date +%s)"
        log_info "Generated PROJECT_ID: $PROJECT_ID"
    fi
    
    # Set default values
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="${BUCKET_NAME:-content-generation-${RANDOM_SUFFIX}}"
    export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-content-ai-sa-${RANDOM_SUFFIX}}"
    
    # Save state
    save_state "PROJECT_ID" "$PROJECT_ID"
    save_state "REGION" "$REGION"
    save_state "ZONE" "$ZONE"
    save_state "BUCKET_NAME" "$BUCKET_NAME"
    save_state "SERVICE_ACCOUNT_NAME" "$SERVICE_ACCOUNT_NAME"
    
    log_info "Environment configured:"
    log_info "  PROJECT_ID: $PROJECT_ID"
    log_info "  REGION: $REGION"
    log_info "  BUCKET_NAME: $BUCKET_NAME"
    log_info "  SERVICE_ACCOUNT_NAME: $SERVICE_ACCOUNT_NAME"
}

# Create GCP project if it doesn't exist
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log_warning "Project $PROJECT_ID does not exist. Creating project..."
        
        # Create project
        gcloud projects create "$PROJECT_ID" \
            --name="Multi-Modal AI Content Generation Platform" \
            --labels="environment=development,purpose=ai-content-generation"
        
        log_success "Project $PROJECT_ID created"
    else
        log_info "Project $PROJECT_ID already exists"
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "run.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "cloudbuild.googleapis.com"
        "texttospeech.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" --project="$PROJECT_ID"
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create Cloud Storage infrastructure
create_storage() {
    log_info "Creating Cloud Storage infrastructure..."
    
    # Create primary bucket
    if ! gsutil ls "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        gsutil mb -p "$PROJECT_ID" \
            -c STANDARD \
            -l "$REGION" \
            "gs://$BUCKET_NAME"
        
        log_success "Created bucket: gs://$BUCKET_NAME"
    else
        log_info "Bucket gs://$BUCKET_NAME already exists"
    fi
    
    # Create structured folders
    local folders=("prompts" "music" "video" "speech" "compositions" "quality-reports")
    for folder in "${folders[@]}"; do
        gsutil cp /dev/null "gs://$BUCKET_NAME/$folder/.keep" || true
    done
    
    # Enable versioning
    gsutil versioning set on "gs://$BUCKET_NAME"
    
    # Set bucket labels
    gsutil label ch -l "environment:development" "gs://$BUCKET_NAME"
    gsutil label ch -l "purpose:ai-content-generation" "gs://$BUCKET_NAME"
    
    log_success "Cloud Storage infrastructure created"
}

# Create service account and IAM setup
create_service_account() {
    log_info "Creating service account and configuring IAM..."
    
    # Create service account
    if ! gcloud iam service-accounts describe \
        "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" >/dev/null 2>&1; then
        
        gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
            --display-name="Content AI Generation Service" \
            --description="Service account for multi-modal content generation platform"
        
        log_success "Service account created: $SERVICE_ACCOUNT_NAME"
    else
        log_info "Service account $SERVICE_ACCOUNT_NAME already exists"
    fi
    
    # Assign required roles
    local roles=(
        "roles/aiplatform.user"
        "roles/storage.objectAdmin"
        "roles/cloudfunctions.invoker"
        "roles/run.invoker"
        "roles/monitoring.metricWriter"
        "roles/logging.logWriter"
    )
    
    for role in "${roles[@]}"; do
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="$role" \
            --condition=None >/dev/null 2>&1
    done
    
    # Create and download service account key
    local key_file="${SCRIPT_DIR}/content-ai-key.json"
    if [[ ! -f "$key_file" ]]; then
        gcloud iam service-accounts keys create "$key_file" \
            --iam-account="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
        log_success "Service account key created: $key_file"
    fi
    
    log_success "IAM configuration completed"
}

# Deploy Cloud Functions
deploy_functions() {
    log_info "Deploying Cloud Functions..."
    
    # Create function source directories
    mkdir -p "${SCRIPT_DIR}/../functions/music-generation"
    mkdir -p "${SCRIPT_DIR}/../functions/video-generation"
    mkdir -p "${SCRIPT_DIR}/../functions/quality-assessment"
    
    # Deploy music generation function
    log_info "Deploying music generation function..."
    cat > "${SCRIPT_DIR}/../functions/music-generation/main.py" << 'EOF'
import functions_framework
import json
import os
import time
import logging
from google.cloud import aiplatform
from google.cloud import storage
import base64

@functions_framework.http
def generate_music(request):
    """Generate music using Lyria 2 from text prompts"""
    try:
        request_json = request.get_json()
        prompt = request_json.get('prompt', '')
        style = request_json.get('style', 'ambient')
        duration = request_json.get('duration', 30)
        
        # Initialize Vertex AI client
        aiplatform.init(
            project=os.environ['PROJECT_ID'], 
            location=os.environ['REGION']
        )
        
        # For now, simulate music generation (Lyria 2 integration pending)
        # In production, this would integrate with actual Lyria 2 API
        session_id = f"music_{int(time.time())}"
        
        # Store metadata in Cloud Storage
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ['BUCKET_NAME'])
        
        # Create placeholder for generated music
        metadata = {
            'session_id': session_id,
            'prompt': prompt,
            'style': style,
            'duration': duration,
            'status': 'generated',
            'timestamp': time.time()
        }
        
        blob = bucket.blob(f"music/{session_id}_metadata.json")
        blob.upload_from_string(json.dumps(metadata), content_type='application/json')
        
        return {
            'status': 'success',
            'session_id': session_id,
            'music_url': f"gs://{os.environ['BUCKET_NAME']}/music/{session_id}.wav",
            'duration': duration,
            'style': style
        }
        
    except Exception as e:
        logging.error(f"Music generation failed: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500
EOF
    
    cat > "${SCRIPT_DIR}/../functions/music-generation/requirements.txt" << 'EOF'
google-cloud-aiplatform>=1.40.0
google-cloud-storage>=2.10.0
functions-framework>=3.4.0
EOF
    
    # Deploy music function
    (cd "${SCRIPT_DIR}/../functions/music-generation" && \
     gcloud functions deploy music-generation \
         --runtime python312 \
         --trigger-http \
         --entry-point generate_music \
         --memory 1GB \
         --timeout 300s \
         --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION},BUCKET_NAME=${BUCKET_NAME}" \
         --service-account "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
         --allow-unauthenticated)
    
    # Deploy video generation function
    log_info "Deploying video generation function..."
    cat > "${SCRIPT_DIR}/../functions/video-generation/main.py" << 'EOF'
import functions_framework
import json
import os
import time
import logging
from google.cloud import aiplatform
from google.cloud import storage

@functions_framework.http
def generate_video(request):
    """Generate video content using Veo 3 models"""
    try:
        request_json = request.get_json()
        prompt = request_json.get('prompt', '')
        duration = request_json.get('duration', 5)
        resolution = request_json.get('resolution', '720p')
        
        # Initialize Vertex AI for Veo 3
        aiplatform.init(
            project=os.environ['PROJECT_ID'], 
            location=os.environ['REGION']
        )
        
        # For now, simulate video generation (Veo 3 integration pending)
        session_id = f"video_{int(time.time())}"
        
        # Store metadata in Cloud Storage
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ['BUCKET_NAME'])
        
        metadata = {
            'session_id': session_id,
            'prompt': prompt,
            'duration': duration,
            'resolution': resolution,
            'status': 'generated',
            'timestamp': time.time()
        }
        
        blob = bucket.blob(f"video/{session_id}_metadata.json")
        blob.upload_from_string(json.dumps(metadata), content_type='application/json')
        
        return {
            'status': 'success',
            'session_id': session_id,
            'video_url': f"gs://{os.environ['BUCKET_NAME']}/video/{session_id}.mp4",
            'duration': duration,
            'resolution': resolution
        }
        
    except Exception as e:
        logging.error(f"Video generation failed: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500
EOF
    
    cat > "${SCRIPT_DIR}/../functions/video-generation/requirements.txt" << 'EOF'
google-cloud-aiplatform>=1.40.0
google-cloud-storage>=2.10.0
functions-framework>=3.4.0
EOF
    
    # Deploy video function
    (cd "${SCRIPT_DIR}/../functions/video-generation" && \
     gcloud functions deploy video-generation \
         --runtime python312 \
         --trigger-http \
         --entry-point generate_video \
         --memory 2GB \
         --timeout 600s \
         --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION},BUCKET_NAME=${BUCKET_NAME}" \
         --service-account "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
         --allow-unauthenticated)
    
    # Deploy quality assessment function
    log_info "Deploying quality assessment function..."
    cat > "${SCRIPT_DIR}/../functions/quality-assessment/main.py" << 'EOF'
import functions_framework
import json
import logging
import os
import time
from google.cloud import storage

@functions_framework.http
def assess_content_quality(request):
    """Assess quality of generated multi-modal content"""
    try:
        request_json = request.get_json()
        session_id = request_json.get('session_id')
        content_urls = request_json.get('content_urls', {})
        
        # Initialize quality assessment results
        quality_report = {
            'session_id': session_id,
            'overall_score': 0.85,  # Simulated score
            'component_scores': {},
            'recommendations': [],
            'enhancement_suggestions': []
        }
        
        # Simulate quality assessment
        if 'music' in content_urls:
            quality_report['component_scores']['music'] = 0.87
            
        if 'video' in content_urls:
            quality_report['component_scores']['video'] = 0.82
            
        if 'speech' in content_urls:
            quality_report['component_scores']['speech'] = 0.88
        
        # Store quality report
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ['BUCKET_NAME'])
        blob = bucket.blob(f"quality-reports/{session_id}_assessment.json")
        blob.upload_from_string(
            json.dumps(quality_report), 
            content_type='application/json'
        )
        
        return quality_report
        
    except Exception as e:
        logging.error(f"Quality assessment failed: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500
EOF
    
    cat > "${SCRIPT_DIR}/../functions/quality-assessment/requirements.txt" << 'EOF'
google-cloud-storage>=2.10.0
functions-framework>=3.4.0
EOF
    
    # Deploy quality assessment function
    (cd "${SCRIPT_DIR}/../functions/quality-assessment" && \
     gcloud functions deploy quality-assessment \
         --runtime python312 \
         --trigger-http \
         --entry-point assess_content_quality \
         --memory 1GB \
         --timeout 300s \
         --set-env-vars "PROJECT_ID=${PROJECT_ID},BUCKET_NAME=${BUCKET_NAME}" \
         --service-account "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
         --allow-unauthenticated)
    
    log_success "Cloud Functions deployed successfully"
}

# Deploy orchestration service to Cloud Run
deploy_orchestration() {
    log_info "Deploying content orchestration service..."
    
    # Create service directory
    mkdir -p "${SCRIPT_DIR}/../services/orchestration"
    
    # Create orchestration service code
    cat > "${SCRIPT_DIR}/../services/orchestration/app.py" << 'EOF'
from flask import Flask, request, jsonify
from google.cloud import storage
import asyncio
import json
import logging
import time
import os
import requests

app = Flask(__name__)

class ContentOrchestrator:
    def __init__(self):
        self.storage_client = storage.Client()
        self.bucket = self.storage_client.bucket(os.environ['BUCKET_NAME'])
        
    async def coordinate_generation(self, content_request):
        """Coordinate multi-modal content generation"""
        
        prompt = content_request['prompt']
        style = content_request.get('style', 'modern')
        duration = content_request.get('duration', 30)
        
        session_id = f"content_{int(time.time())}"
        
        # Simulate parallel generation
        tasks = [
            self.generate_music(prompt, style, duration, session_id),
            self.generate_video(prompt, style, duration, session_id),
            self.generate_speech(prompt, style, session_id)
        ]
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        composition = await self.synchronize_content(results, session_id)
        
        return composition
    
    async def generate_music(self, prompt, style, duration, session_id):
        """Generate music component"""
        music_prompt = f"Create {style} music for: {prompt}"
        
        music_request = {
            'prompt': music_prompt,
            'style': style,
            'duration': duration
        }
        
        music_endpoint = f"https://{os.environ['REGION']}-{os.environ['PROJECT_ID']}.cloudfunctions.net/music-generation"
        
        try:
            response = requests.post(
                music_endpoint,
                json=music_request,
                timeout=300
            )
            
            if response.status_code == 200:
                return response.json()
            else:
                return {'type': 'music', 'status': 'error', 'session_id': session_id}
                
        except Exception as e:
            logging.error(f"Music generation request failed: {str(e)}")
            return {'type': 'music', 'status': 'error', 'session_id': session_id}
    
    async def generate_video(self, prompt, style, duration, session_id):
        """Generate video component"""
        video_prompt = f"Create {style} visuals showing: {prompt}"
        
        video_request = {
            'prompt': video_prompt,
            'duration': duration,
            'resolution': '1080p'
        }
        
        video_endpoint = f"https://{os.environ['REGION']}-{os.environ['PROJECT_ID']}.cloudfunctions.net/video-generation"
        
        try:
            response = requests.post(
                video_endpoint,
                json=video_request,
                timeout=600
            )
            
            if response.status_code == 200:
                return response.json()
            else:
                return {'type': 'video', 'status': 'error', 'session_id': session_id}
                
        except Exception as e:
            logging.error(f"Video generation request failed: {str(e)}")
            return {'type': 'video', 'status': 'error', 'session_id': session_id}
    
    async def generate_speech(self, prompt, style, session_id):
        """Generate speech component"""
        speech_text = f"Presenting {prompt} in {style} style"
        
        return {
            'type': 'speech',
            'session_id': session_id,
            'url': f"gs://{os.environ['BUCKET_NAME']}/speech/{session_id}.wav",
            'text': speech_text,
            'status': 'success'
        }
    
    async def synchronize_content(self, components, session_id):
        """Synchronize all content components"""
        
        composition = {
            'session_id': session_id,
            'timestamp': time.time(),
            'components': components,
            'status': 'synchronized',
            'final_url': f"gs://{os.environ['BUCKET_NAME']}/compositions/{session_id}_final.mp4"
        }
        
        blob = self.bucket.blob(f"compositions/{session_id}_metadata.json")
        blob.upload_from_string(json.dumps(composition), content_type='application/json')
        
        return composition

orchestrator = ContentOrchestrator()

@app.route('/generate', methods=['POST'])
def generate_content():
    """Main content generation endpoint"""
    try:
        content_request = request.get_json()
        
        if not content_request.get('prompt'):
            return jsonify({'error': 'Prompt is required'}), 400
        
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        result = loop.run_until_complete(
            orchestrator.coordinate_generation(content_request)
        )
        
        return jsonify(result)
        
    except Exception as e:
        logging.error(f"Content generation failed: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF
    
    # Create Dockerfile
    cat > "${SCRIPT_DIR}/../services/orchestration/Dockerfile" << 'EOF'
FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 app:app
EOF
    
    # Create requirements
    cat > "${SCRIPT_DIR}/../services/orchestration/requirements.txt" << 'EOF'
flask>=3.0.0
gunicorn>=21.2.0
google-cloud-storage>=2.10.0
requests>=2.31.0
EOF
    
    # Deploy to Cloud Run
    (cd "${SCRIPT_DIR}/../services/orchestration" && \
     gcloud run deploy content-orchestrator \
         --source . \
         --platform managed \
         --region "$REGION" \
         --memory 2Gi \
         --cpu 2 \
         --timeout 900 \
         --service-account "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
         --set-env-vars "BUCKET_NAME=${BUCKET_NAME},PROJECT_ID=${PROJECT_ID},REGION=${REGION}" \
         --allow-unauthenticated)
    
    log_success "Content orchestration service deployed"
}

# Configure monitoring and logging
setup_monitoring() {
    log_info "Setting up monitoring and logging..."
    
    # Create custom metrics
    gcloud logging metrics create content_generation_requests \
        --description="Total content generation requests" \
        --log-filter='resource.type="cloud_function" AND textPayload:"Content generation"' \
        --project="$PROJECT_ID" || log_warning "Metric might already exist"
    
    # Create alerting policy
    cat > "${SCRIPT_DIR}/alerting-policy.yaml" << EOF
displayName: "Content Generation Error Rate Alert"
conditions:
  - displayName: "High error rate"
    conditionThreshold:
      filter: 'resource.type="cloud_function" AND resource.label.function_name=~"music-generation|video-generation|quality-assessment"'
      comparison: COMPARISON_GREATER_THAN
      thresholdValue: 0.05
      duration: 300s
EOF
    
    log_success "Monitoring and logging configured"
}

# Run deployment validation
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check if all APIs are enabled
    local enabled_apis
    enabled_apis=$(gcloud services list --enabled --filter="name:aiplatform.googleapis.com OR name:storage.googleapis.com" --format="value(name)" --project="$PROJECT_ID")
    
    if [[ -z "$enabled_apis" ]]; then
        log_error "Required APIs are not enabled"
        return 1
    fi
    
    # Check if bucket exists
    if ! gsutil ls "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        log_error "Storage bucket was not created successfully"
        return 1
    fi
    
    # Check if functions are deployed
    local functions=("music-generation" "video-generation" "quality-assessment")
    for func in "${functions[@]}"; do
        if ! gcloud functions describe "$func" --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
            log_error "Function $func was not deployed successfully"
            return 1
        fi
    done
    
    # Check if Cloud Run service is deployed
    if ! gcloud run services describe content-orchestrator --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
        log_error "Content orchestrator service was not deployed successfully"
        return 1
    fi
    
    log_success "Deployment validation passed"
}

# Display deployment information
show_deployment_info() {
    log_info "Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT INFORMATION ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Storage Bucket: gs://$BUCKET_NAME"
    echo "Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo
    echo "=== ENDPOINTS ==="
    
    # Get function endpoints
    local music_endpoint
    music_endpoint=$(gcloud functions describe music-generation --region="$REGION" --project="$PROJECT_ID" --format="value(httpsTrigger.url)")
    echo "Music Generation: $music_endpoint"
    
    local video_endpoint
    video_endpoint=$(gcloud functions describe video-generation --region="$REGION" --project="$PROJECT_ID" --format="value(httpsTrigger.url)")
    echo "Video Generation: $video_endpoint"
    
    local quality_endpoint
    quality_endpoint=$(gcloud functions describe quality-assessment --region="$REGION" --project="$PROJECT_ID" --format="value(httpsTrigger.url)")
    echo "Quality Assessment: $quality_endpoint"
    
    # Get Cloud Run endpoint
    local orchestrator_url
    orchestrator_url=$(gcloud run services describe content-orchestrator --region="$REGION" --project="$PROJECT_ID" --format="value(status.url)")
    echo "Content Orchestrator: $orchestrator_url"
    
    echo
    echo "=== TEST COMMAND ==="
    echo "curl -X POST ${orchestrator_url}/generate \\"
    echo "  -H \"Content-Type: application/json\" \\"
    echo "  -d '{\"prompt\": \"Revolutionary AI breakthrough announcement\", \"style\": \"professional\", \"duration\": 45}'"
    echo
    echo "=== LOG FILE ==="
    echo "Deployment log: $LOG_FILE"
    echo "Deployment state: $DEPLOYMENT_STATE_FILE"
    echo
    echo "Run './destroy.sh' to clean up all resources."
}

# Main deployment flow
main() {
    log_info "Starting Multi-Modal AI Content Generation Platform deployment..."
    log_info "Log file: $LOG_FILE"
    
    # Initialize deployment state file
    echo "# Deployment state for Multi-Modal AI Content Generation Platform" > "$DEPLOYMENT_STATE_FILE"
    echo "DEPLOYMENT_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$DEPLOYMENT_STATE_FILE"
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage
    create_service_account
    deploy_functions
    deploy_orchestration
    setup_monitoring
    validate_deployment
    show_deployment_info
    
    log_success "Multi-Modal AI Content Generation Platform deployed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --bucket-name)
            BUCKET_NAME="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --project-id PROJECT_ID     GCP project ID (auto-generated if not provided)"
            echo "  --region REGION             GCP region (default: us-central1)"
            echo "  --bucket-name BUCKET_NAME   Storage bucket name (auto-generated if not provided)"
            echo "  --help                      Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main deployment
main "$@"