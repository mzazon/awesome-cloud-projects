#!/bin/bash

# Educational Content Generation with Gemini and Text-to-Speech - Deployment Script
# This script deploys the complete infrastructure for automated educational content generation
# using Vertex AI Gemini, Cloud Text-to-Speech, Cloud Functions, and Firestore

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/edu-content-deploy-$(date +%Y%m%d_%H%M%S).log"
readonly MAX_WAIT_TIME=600  # 10 minutes maximum wait time

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO: $*"
}

log_warn() {
    log "WARNING: $*"
}

log_error() {
    log "ERROR: $*"
}

log_success() {
    log "SUCCESS: $*"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Script failed with exit code ${exit_code}. Check log file: ${LOG_FILE}"
    log_error "To clean up partial deployment, run: ./destroy.sh"
    exit ${exit_code}
}

trap cleanup_on_error ERR

# Validation functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud SDK (gcloud) is not installed"
        log_error "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_error "Run: gcloud auth login"
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warn "jq is not installed. JSON output parsing may be limited"
    fi
    
    log_success "Prerequisites check completed"
}

validate_project_config() {
    log_info "Validating project configuration..."
    
    # Check if PROJECT_ID is set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID environment variable is not set"
        log_error "Set it with: export PROJECT_ID=your-project-id"
        exit 1
    fi
    
    # Verify project exists and user has access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Cannot access project '${PROJECT_ID}' or project does not exist"
        exit 1
    fi
    
    # Set default project
    gcloud config set project "${PROJECT_ID}" &> /dev/null
    
    log_success "Project configuration validated: ${PROJECT_ID}"
}

check_billing() {
    log_info "Checking billing configuration..."
    
    local billing_account
    billing_account=$(gcloud billing projects describe "${PROJECT_ID}" \
        --format="value(billingAccountName)" 2>/dev/null || echo "")
    
    if [[ -z "${billing_account}" ]]; then
        log_error "Project '${PROJECT_ID}' does not have billing enabled"
        log_error "Enable billing at: https://console.cloud.google.com/billing"
        exit 1
    fi
    
    log_success "Billing is enabled for project"
}

# Configuration setup
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Export default values if not already set
    export PROJECT_ID="${PROJECT_ID:-edu-content-gen-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    local random_suffix
    random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s)")
    export FUNCTION_NAME="${FUNCTION_NAME:-content-generator-${random_suffix}}"
    export BUCKET_NAME="${BUCKET_NAME:-edu-audio-content-${random_suffix}}"
    export FIRESTORE_COLLECTION="${FIRESTORE_COLLECTION:-educational_content}"
    
    # Set gcloud defaults
    gcloud config set compute/region "${REGION}" &> /dev/null
    gcloud config set compute/zone "${ZONE}" &> /dev/null
    gcloud config set functions/region "${REGION}" &> /dev/null
    
    log_info "Environment configured:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Function Name: ${FUNCTION_NAME}"
    log_info "  Bucket Name: ${BUCKET_NAME}"
    log_info "  Firestore Collection: ${FIRESTORE_COLLECTION}"
}

# API enablement
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "aiplatform.googleapis.com"
        "texttospeech.googleapis.com"
        "firestore.googleapis.com"
        "storage-api.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if ! gcloud services enable "${api}" &> /dev/null; then
            log_error "Failed to enable API: ${api}"
            exit 1
        fi
    done
    
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Infrastructure deployment
create_firestore_database() {
    log_info "Creating Firestore database..."
    
    # Check if Firestore database already exists
    if gcloud firestore databases describe --database="(default)" &> /dev/null; then
        log_info "Firestore database already exists"
        return 0
    fi
    
    # Create Firestore database in Native mode
    if ! gcloud firestore databases create \
        --location="${REGION}" \
        --type=firestore-native \
        --database="(default)" &> /dev/null; then
        log_error "Failed to create Firestore database"
        exit 1
    fi
    
    log_success "Firestore database created successfully"
}

create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        log_info "Storage bucket already exists: ${BUCKET_NAME}"
        return 0
    fi
    
    # Create storage bucket
    if ! gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}" &> /dev/null; then
        log_error "Failed to create storage bucket: ${BUCKET_NAME}"
        exit 1
    fi
    
    # Configure bucket for public read access
    if ! gsutil iam ch allUsers:objectViewer "gs://${BUCKET_NAME}" &> /dev/null; then
        log_warn "Failed to set public read access on bucket"
    fi
    
    log_success "Storage bucket created: ${BUCKET_NAME}"
}

deploy_cloud_function() {
    log_info "Deploying Cloud Function..."
    
    local function_dir="${SCRIPT_DIR}/../function"
    
    # Create function directory if it doesn't exist
    mkdir -p "${function_dir}"
    
    # Create main.py with the function code
    cat > "${function_dir}/main.py" << 'EOF'
import functions_framework
import json
import os
from google.cloud import aiplatform
from google.cloud import texttospeech
from google.cloud import firestore
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel

# Initialize clients
db = firestore.Client()
tts_client = texttospeech.TextToSpeechClient()
storage_client = storage.Client()

@functions_framework.http
def generate_content(request):
    """Generate educational content from curriculum outline."""
    
    # Parse request
    request_json = request.get_json()
    outline = request_json.get('outline', '')
    topic = request_json.get('topic', 'Educational Content')
    voice_name = request_json.get('voice_name', 'en-US-Studio-M')
    
    if not outline:
        return {'error': 'Curriculum outline is required'}, 400
    
    try:
        # Initialize Vertex AI
        vertexai.init(project=os.environ.get('GCP_PROJECT'))
        model = GenerativeModel('gemini-2.5-flash')
        
        # Generate educational content using Gemini
        prompt = f"""
        Create comprehensive educational content based on this curriculum outline:
        
        {outline}
        
        Generate:
        1. A detailed lesson plan (200-300 words)
        2. Key learning objectives (3-5 bullet points)
        3. Explanatory content suitable for audio narration (400-500 words)
        4. Practice questions (3-5 questions)
        
        Format the response as structured, educational content that flows naturally when read aloud.
        Focus on clarity, engagement, and pedagogical best practices.
        """
        
        response = model.generate_content(prompt)
        generated_content = response.text
        
        # Store content in Firestore
        doc_ref = db.collection('educational_content').add({
            'topic': topic,
            'outline': outline,
            'generated_content': generated_content,
            'timestamp': firestore.SERVER_TIMESTAMP,
            'status': 'content_generated'
        })[1]
        
        # Generate audio using Text-to-Speech
        synthesis_input = texttospeech.SynthesisInput(text=generated_content)
        voice = texttospeech.VoiceSelectionParams(
            language_code='en-US',
            name=voice_name
        )
        audio_config = texttospeech.AudioConfig(
            audio_encoding=texttospeech.AudioEncoding.MP3,
            speaking_rate=0.9,
            pitch=0.0
        )
        
        tts_response = tts_client.synthesize_speech(
            input=synthesis_input,
            voice=voice,
            audio_config=audio_config
        )
        
        # Upload audio to Cloud Storage
        bucket_name = os.environ.get('BUCKET_NAME')
        bucket = storage_client.bucket(bucket_name)
        audio_filename = f"lessons/{doc_ref.id}.mp3"
        blob = bucket.blob(audio_filename)
        blob.upload_from_string(tts_response.audio_content, content_type='audio/mpeg')
        
        # Update Firestore with audio URL
        doc_ref.update({
            'audio_url': f"gs://{bucket_name}/{audio_filename}",
            'status': 'completed'
        })
        
        return {
            'status': 'success',
            'document_id': doc_ref.id,
            'content_preview': generated_content[:200] + '...',
            'audio_url': f"gs://{bucket_name}/{audio_filename}"
        }
        
    except Exception as e:
        return {'error': str(e)}, 500
EOF
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
functions-framework==3.9.1
google-cloud-aiplatform==1.105.0
google-cloud-texttospeech==2.27.0
google-cloud-firestore==2.18.0
google-cloud-storage==2.18.2
EOF
    
    # Deploy the function
    log_info "Deploying Cloud Function with source code..."
    if ! gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python311 \
        --trigger-http \
        --source "${function_dir}" \
        --entry-point generate_content \
        --memory 1024MB \
        --timeout 540s \
        --set-env-vars "GCP_PROJECT=${PROJECT_ID},BUCKET_NAME=${BUCKET_NAME}" \
        --allow-unauthenticated \
        --region="${REGION}" &> /dev/null; then
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(httpsTrigger.url)" 2>/dev/null)
    
    if [[ -n "${function_url}" ]]; then
        log_success "Cloud Function deployed successfully"
        log_info "Function URL: ${function_url}"
        
        # Save function URL to file for later use
        echo "${function_url}" > "${SCRIPT_DIR}/../function_url.txt"
    else
        log_error "Could not retrieve function URL"
        exit 1
    fi
}

# Testing and validation
test_deployment() {
    log_info "Testing deployment..."
    
    local function_url
    if [[ -f "${SCRIPT_DIR}/../function_url.txt" ]]; then
        function_url=$(cat "${SCRIPT_DIR}/../function_url.txt")
    else
        function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --format="value(httpsTrigger.url)" 2>/dev/null)
    fi
    
    if [[ -z "${function_url}" ]]; then
        log_error "Could not retrieve function URL for testing"
        return 1
    fi
    
    # Create test request
    local test_request='{"topic": "Introduction to Climate Science", "outline": "1. What is climate vs weather? 2. Greenhouse effect basics 3. Human impact on climate 4. Climate change evidence 5. Mitigation strategies", "voice_name": "en-US-Studio-M"}'
    
    log_info "Sending test request to function..."
    local response
    if command -v curl &> /dev/null; then
        response=$(curl -s -X POST "${function_url}" \
            -H "Content-Type: application/json" \
            -d "${test_request}" \
            --max-time 60 2>/dev/null || echo "")
    else
        log_warn "curl not available, skipping function test"
        return 0
    fi
    
    if [[ -n "${response}" ]] && echo "${response}" | grep -q "success"; then
        log_success "Function test completed successfully"
        if command -v jq &> /dev/null; then
            echo "${response}" | jq '.' 2>/dev/null || echo "${response}"
        else
            echo "${response}"
        fi
    else
        log_warn "Function test did not return expected success response"
        log_warn "Response: ${response}"
    fi
}

# Cost estimation
show_cost_estimation() {
    log_info "Cost estimation for deployed resources:"
    log_info "  • Cloud Functions (per invocation): $0.0000004"
    log_info "  • Vertex AI Gemini 2.5 Flash (per 1K tokens): $0.00015"
    log_info "  • Text-to-Speech (per 1M characters): $16.00"
    log_info "  • Firestore (per document operation): $0.00000018"
    log_info "  • Cloud Storage (per GB/month): $0.020"
    log_info "  Estimated monthly cost for 100 content generations: $5-15"
}

# Main deployment flow
main() {
    log_info "Starting Educational Content Generation deployment..."
    log_info "Log file: ${LOG_FILE}"
    
    # Prerequisites and validation
    check_prerequisites
    validate_project_config
    check_billing
    
    # Environment setup
    setup_environment
    
    # Deploy infrastructure
    enable_apis
    create_firestore_database
    create_storage_bucket
    deploy_cloud_function
    
    # Test and validate
    test_deployment
    
    # Show summary
    log_success "Deployment completed successfully!"
    log_info "Resources created:"
    log_info "  • Project: ${PROJECT_ID}"
    log_info "  • Cloud Function: ${FUNCTION_NAME}"
    log_info "  • Storage Bucket: ${BUCKET_NAME}"
    log_info "  • Firestore Database: (default)"
    
    if [[ -f "${SCRIPT_DIR}/../function_url.txt" ]]; then
        local function_url
        function_url=$(cat "${SCRIPT_DIR}/../function_url.txt")
        log_info "  • Function URL: ${function_url}"
    fi
    
    show_cost_estimation
    
    log_info "To test the deployment:"
    log_info "  1. Use the function URL shown above"
    log_info "  2. Send POST requests with curriculum outlines"
    log_info "  3. Check Firestore for generated content"
    log_info "  4. Check Cloud Storage for audio files"
    
    log_info "To clean up resources, run: ./destroy.sh"
    log_success "Deployment script completed successfully"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi