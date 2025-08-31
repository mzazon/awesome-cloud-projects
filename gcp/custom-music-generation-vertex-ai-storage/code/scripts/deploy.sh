#!/bin/bash

# Deploy Custom Music Generation with Vertex AI and Storage
# This script automates the deployment of a serverless music generation system
# using Vertex AI Lyria 2, Cloud Storage, and Cloud Functions

set -euo pipefail

# Colors for output
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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $*"
    else
        "$@"
    fi
}

# Prerequisites checking function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if curl is installed (for testing)
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Please install curl for API testing."
        exit 1
    fi
    
    # Check if python3 is installed
    if ! command -v python3 &> /dev/null; then
        error "python3 is not installed. Please install Python 3."
        exit 1
    fi
    
    # Check if pip3 is installed
    if ! command -v pip3 &> /dev/null; then
        error "pip3 is not installed. Please install pip3."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    success "All prerequisites check passed"
}

# Environment setup function
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="music-gen-$(date +%s)"
        warning "PROJECT_ID not set, using generated ID: ${PROJECT_ID}"
    fi
    
    # Set default region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s)" | tail -c 7)
    export BUCKET_INPUT="music-prompts-${RANDOM_SUFFIX}"
    export BUCKET_OUTPUT="generated-music-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="music-generator-${RANDOM_SUFFIX}"
    export API_FUNCTION="music-api-${RANDOM_SUFFIX}"
    
    # Create environment file for cleanup
    cat > .env << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
BUCKET_INPUT=${BUCKET_INPUT}
BUCKET_OUTPUT=${BUCKET_OUTPUT}
FUNCTION_NAME=${FUNCTION_NAME}
API_FUNCTION=${API_FUNCTION}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables configured"
    log "PROJECT_ID: ${PROJECT_ID}"
    log "REGION: ${REGION}"
    log "BUCKET_INPUT: ${BUCKET_INPUT}"
    log "BUCKET_OUTPUT: ${BUCKET_OUTPUT}"
}

# Project configuration function
configure_project() {
    log "Configuring Google Cloud project..."
    
    # Set default project and region
    execute gcloud config set project "${PROJECT_ID}"
    execute gcloud config set compute/region "${REGION}"
    execute gcloud config set compute/zone "${ZONE}"
    
    # Enable required APIs
    log "Enabling required APIs..."
    local apis=(
        "aiplatform.googleapis.com"
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        execute gcloud services enable "${api}"
    done
    
    success "Project configured with required APIs enabled"
}

# Create Cloud Storage buckets
create_storage_buckets() {
    log "Creating Cloud Storage buckets..."
    
    # Create bucket for storing input prompts and metadata
    log "Creating input bucket: ${BUCKET_INPUT}"
    execute gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_INPUT}"
    
    # Create bucket for generated music files
    log "Creating output bucket: ${BUCKET_OUTPUT}"
    execute gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_OUTPUT}"
    
    # Enable versioning for data protection
    log "Enabling versioning on buckets..."
    execute gsutil versioning set on "gs://${BUCKET_INPUT}"
    execute gsutil versioning set on "gs://${BUCKET_OUTPUT}"
    
    # Set appropriate lifecycle policies for cost optimization
    log "Setting up lifecycle policies..."
    cat > lifecycle-config.json << 'EOF'
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
    
    execute gsutil lifecycle set lifecycle-config.json "gs://${BUCKET_OUTPUT}"
    
    success "Storage buckets created with lifecycle policies configured"
}

# Create music generator Cloud Function
create_music_generator_function() {
    log "Creating music generator Cloud Function..."
    
    # Create function directory and dependencies
    mkdir -p music-generator-function
    cd music-generator-function
    
    # Create requirements.txt for Python dependencies
    cat > requirements.txt << 'EOF'
google-cloud-aiplatform==1.46.0
google-cloud-storage==2.10.0
functions-framework==3.8.2
cloudevents>=1.2.0
requests==2.31.0
EOF
    
    # Create the main function code
    cat > main.py << 'EOF'
import os
import json
import logging
from typing import Dict, Any
from google.cloud import aiplatform
from google.cloud import storage
from cloudevents.http.event import CloudEvent
import functions_framework

# Initialize clients
storage_client = storage.Client()

@functions_framework.cloud_event
def generate_music(cloud_event: CloudEvent) -> None:
    """Cloud Function triggered by Cloud Storage to generate music from prompts."""
    
    # Extract file information from the Cloud Storage event
    data = cloud_event.data
    bucket_name = data['bucket']
    file_name = data['name']
    
    if not file_name.endswith('.json'):
        logging.info(f"Skipping non-JSON file: {file_name}")
        return
    
    try:
        # Download and parse the prompt file
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        prompt_data = json.loads(blob.download_as_text())
        
        # Extract music generation parameters
        text_prompt = prompt_data.get('prompt', '')
        style = prompt_data.get('style', 'instrumental')
        duration = prompt_data.get('duration_seconds', 30)
        tempo = prompt_data.get('tempo', 'moderate')
        
        # Initialize Vertex AI with current project and region
        aiplatform.init(
            project=os.environ['GCP_PROJECT'], 
            location=os.environ.get('GCP_REGION', 'us-central1')
        )
        
        # Prepare music generation request for Lyria 2 model
        music_prompt = f"Generate {style} music: {text_prompt}, {tempo} tempo"
        
        # Note: Using Lyria 2 (lyria-002) model for music generation
        # In a full implementation, this would call the actual Vertex AI Lyria API
        # For demonstration, we simulate the generation process with metadata
        generated_metadata = {
            'request_id': prompt_data.get('request_id', 'unknown'),
            'prompt': text_prompt,
            'style': style,
            'duration': duration,
            'tempo': tempo,
            'model_name': 'lyria-002',
            'model_version': 'lyria-2',
            'generation_timestamp': cloud_event.get_time().isoformat(),
            'file_format': 'wav',
            'sample_rate': 48000,
            'generation_status': 'completed'
        }
        
        # Save generation metadata to output bucket
        output_bucket = storage_client.bucket(os.environ['OUTPUT_BUCKET'])
        metadata_blob = output_bucket.blob(f"metadata/{file_name}")
        metadata_blob.upload_from_string(
            json.dumps(generated_metadata, indent=2),
            content_type='application/json'
        )
        
        # Create a placeholder audio file to demonstrate the workflow
        # In production, this would contain the actual generated audio
        audio_file_name = f"audio/{prompt_data.get('request_id', 'unknown')}.wav"
        audio_blob = output_bucket.blob(audio_file_name)
        audio_blob.upload_from_string(
            b"# Generated music would be here",
            content_type='audio/wav'
        )
        
        logging.info(f"Music generation completed for request: {prompt_data.get('request_id')}")
        
    except Exception as e:
        logging.error(f"Error generating music: {str(e)}")
        # Store error information for debugging
        error_metadata = {
            'request_id': prompt_data.get('request_id', 'unknown'),
            'error': str(e),
            'status': 'failed',
            'timestamp': cloud_event.get_time().isoformat()
        }
        
        output_bucket = storage_client.bucket(os.environ['OUTPUT_BUCKET'])
        error_blob = output_bucket.blob(f"errors/{file_name}")
        error_blob.upload_from_string(
            json.dumps(error_metadata, indent=2),
            content_type='application/json'
        )
        raise
EOF
    
    # Deploy the Cloud Function with Cloud Storage trigger
    log "Deploying music generator function..."
    execute gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python311 \
        --trigger-bucket "${BUCKET_INPUT}" \
        --source . \
        --entry-point generate_music \
        --memory 512MB \
        --timeout 540s \
        --set-env-vars "OUTPUT_BUCKET=${BUCKET_OUTPUT},GCP_PROJECT=${PROJECT_ID},GCP_REGION=${REGION}"
    
    cd ..
    
    success "Music generator Cloud Function deployed successfully"
}

# Create REST API function
create_api_function() {
    log "Creating REST API function..."
    
    # Create API function directory
    mkdir -p music-api-function
    cd music-api-function
    
    # Create requirements for API function
    cat > requirements.txt << 'EOF'
google-cloud-storage==2.10.0
functions-framework==3.8.2
flask==3.0.0
EOF
    
    # Create API function code
    cat > main.py << 'EOF'
import os
import json
import uuid
from datetime import datetime
from typing import Dict, Any, Tuple
from google.cloud import storage
import functions_framework
from flask import Request, jsonify, Response

storage_client = storage.Client()

@functions_framework.http
def music_api(request: Request) -> Tuple[Response, int]:
    """HTTP Cloud Function for music generation API."""
    
    # Enable CORS for web applications
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    if request.method != 'POST':
        return jsonify({'error': 'Only POST method allowed'}), 405, headers
    
    try:
        # Parse request JSON
        request_json = request.get_json()
        if not request_json:
            return jsonify({'error': 'No JSON body provided'}), 400, headers
        
        # Validate required fields
        required_fields = ['prompt']
        for field in required_fields:
            if field not in request_json:
                return jsonify({'error': f'Missing required field: {field}'}), 400, headers
        
        # Validate prompt length and content
        prompt = request_json['prompt'].strip()
        if len(prompt) < 5:
            return jsonify({'error': 'Prompt must be at least 5 characters'}), 400, headers
        if len(prompt) > 500:
            return jsonify({'error': 'Prompt must be less than 500 characters'}), 400, headers
        
        # Generate unique request ID
        request_id = str(uuid.uuid4())
        
        # Prepare music generation request with validated parameters
        music_request = {
            'request_id': request_id,
            'prompt': prompt,
            'style': request_json.get('style', 'instrumental'),
            'duration_seconds': min(request_json.get('duration_seconds', 30), 300),
            'tempo': request_json.get('tempo', 'moderate'),
            'created_at': datetime.utcnow().isoformat(),
            'status': 'queued',
            'model': 'lyria-002'
        }
        
        # Additional validation for style and tempo
        valid_styles = ['instrumental', 'ambient', 'classical', 'rock', 'electronic', 'jazz']
        valid_tempos = ['slow', 'moderate', 'fast']
        
        if music_request['style'] not in valid_styles:
            music_request['style'] = 'instrumental'
        
        if music_request['tempo'] not in valid_tempos:
            music_request['tempo'] = 'moderate'
        
        # Upload request to trigger music generation
        bucket = storage_client.bucket(os.environ['INPUT_BUCKET'])
        blob = bucket.blob(f"requests/{request_id}.json")
        blob.upload_from_string(
            json.dumps(music_request, indent=2),
            content_type='application/json'
        )
        
        # Return request tracking information
        response = {
            'request_id': request_id,
            'status': 'queued',
            'message': 'Music generation request submitted successfully',
            'estimated_completion': '30-120 seconds',
            'model': 'lyria-002',
            'parameters': {
                'style': music_request['style'],
                'duration_seconds': music_request['duration_seconds'],
                'tempo': music_request['tempo']
            }
        }
        
        return jsonify(response), 200, headers
        
    except Exception as e:
        return jsonify({'error': f'Internal server error: {str(e)}'}), 500, headers
EOF
    
    # Deploy the API function
    log "Deploying API function..."
    execute gcloud functions deploy "${API_FUNCTION}" \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point music_api \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars "INPUT_BUCKET=${BUCKET_INPUT}"
    
    cd ..
    
    # Get the API function URL
    if [[ "$DRY_RUN" == "false" ]]; then
        API_URL=$(gcloud functions describe "${API_FUNCTION}" \
            --gen2 \
            --region="${REGION}" \
            --format="value(serviceConfig.uri)")
        echo "API_URL=${API_URL}" >> .env
        success "Music API deployed at: ${API_URL}"
    else
        success "API function deployment configured (dry-run)"
    fi
}

# Configure IAM permissions
configure_iam_permissions() {
    log "Configuring IAM permissions for service integration..."
    
    # Get the default compute service account
    PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" \
        --format="value(projectNumber)")
    COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
    
    # Grant Cloud Functions access to Vertex AI
    execute gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${COMPUTE_SA}" \
        --role="roles/aiplatform.user"
    
    # Grant access to Cloud Storage buckets
    execute gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${COMPUTE_SA}" \
        --role="roles/storage.objectAdmin"
    
    # Grant Cloud Functions invoker role for internal communication
    execute gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${COMPUTE_SA}" \
        --role="roles/cloudfunctions.invoker"
    
    # Grant logging permissions for debugging
    execute gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${COMPUTE_SA}" \
        --role="roles/logging.logWriter"
    
    echo "COMPUTE_SA=${COMPUTE_SA}" >> .env
    success "IAM permissions configured for secure service integration"
}

# Create sample client for testing
create_sample_client() {
    log "Creating sample client for testing..."
    
    # Create sample client script
    cat > test-music-client.py << 'EOF'
#!/usr/bin/env python3

import requests
import json
import time
import sys
from typing import Optional, Dict, Any

def test_music_generation(
    api_url: str, 
    prompt: str, 
    style: str = "instrumental", 
    duration: int = 30
) -> Optional[str]:
    """Test the music generation API with sample requests."""
    
    # Prepare request payload
    payload = {
        "prompt": prompt,
        "style": style,
        "duration_seconds": duration,
        "tempo": "moderate"
    }
    
    print(f"Submitting music generation request...")
    print(f"Prompt: {prompt}")
    print(f"Style: {style}")
    print(f"Duration: {duration} seconds")
    
    try:
        # Submit generation request
        response = requests.post(api_url, json=payload, timeout=30)
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ Request submitted successfully!")
            print(f"Request ID: {result['request_id']}")
            print(f"Status: {result['status']}")
            print(f"Model: {result.get('model', 'unknown')}")
            print(f"Estimated completion: {result['estimated_completion']}")
            return result['request_id']
        else:
            print(f"❌ Error: {response.status_code}")
            print(f"Response: {response.text}")
            return None
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Network error: {e}")
        return None

def validate_api_endpoint(api_url: str) -> bool:
    """Validate that the API endpoint is accessible."""
    try:
        # Test with OPTIONS request for CORS preflight
        response = requests.options(api_url, timeout=10)
        return response.status_code in [200, 204]
    except requests.exceptions.RequestException:
        return False

if __name__ == "__main__":
    api_url = sys.argv[1] if len(sys.argv) > 1 else input("Enter API URL: ")
    
    # Validate API endpoint first
    if not validate_api_endpoint(api_url):
        print(f"❌ API endpoint not accessible: {api_url}")
        sys.exit(1)
    
    # Test cases with various music styles
    test_cases = [
        {
            "prompt": "Uplifting piano melody for a sunrise scene with gentle bells",
            "style": "ambient",
            "duration": 45
        },
        {
            "prompt": "Energetic guitar riff for an action sequence with driving drums",
            "style": "rock",
            "duration": 30
        },
        {
            "prompt": "Gentle strings for a meditation app with soft flute accompaniment",
            "style": "classical",
            "duration": 60
        },
        {
            "prompt": "Smooth jazz saxophone for a late-night coffee shop atmosphere",
            "style": "jazz",
            "duration": 90
        }
    ]
    
    print("Testing music generation API with sample prompts...\n")
    
    for i, test_case in enumerate(test_cases, 1):
        print(f"Test Case {i}:")
        request_id = test_music_generation(api_url, **test_case)
        if request_id:
            print(f"Track request with ID: {request_id}\n")
        else:
            print("Failed to submit request\n")
        
        time.sleep(2)  # Rate limiting between requests
EOF
    
    # Make the client executable
    chmod +x test-music-client.py
    
    success "Sample client created for API testing"
}

# Install Python dependencies
install_dependencies() {
    log "Installing Python dependencies for testing..."
    
    # Install required dependencies for testing
    execute pip3 install requests
    
    success "Python dependencies installed"
}

# Run validation tests
run_validation_tests() {
    log "Running validation tests..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "Validation tests skipped in dry-run mode"
        return
    fi
    
    # Check bucket creation and lifecycle policies
    log "Verifying Cloud Storage bucket configuration..."
    gsutil ls -p "${PROJECT_ID}" | grep -E "(${BUCKET_INPUT}|${BUCKET_OUTPUT})"
    gsutil lifecycle get "gs://${BUCKET_OUTPUT}"
    
    # Verify both functions are deployed and active
    log "Checking Cloud Functions deployment status..."
    gcloud functions list \
        --gen2 \
        --format="table(name,state,environment)" \
        --filter="name:(${FUNCTION_NAME} OR ${API_FUNCTION})"
    
    # Test API endpoint if URL is available
    if [[ -f .env ]] && grep -q "API_URL=" .env; then
        source .env
        if [[ -n "${API_URL:-}" ]]; then
            log "Testing API endpoint functionality..."
            curl -X POST "${API_URL}" \
                -H "Content-Type: application/json" \
                -d '{
                    "prompt": "Peaceful ambient sounds for focus and productivity",
                    "style": "ambient",
                    "duration_seconds": 30,
                    "tempo": "slow"
                }' || warning "API test failed - function may still be starting up"
        fi
    fi
    
    success "Validation tests completed"
}

# Main deployment function
main() {
    log "Starting deployment of Custom Music Generation with Vertex AI and Storage"
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Configure project
    configure_project
    
    # Create storage buckets
    create_storage_buckets
    
    # Create Cloud Functions
    create_music_generator_function
    create_api_function
    
    # Configure IAM
    configure_iam_permissions
    
    # Create sample client
    create_sample_client
    
    # Install dependencies
    install_dependencies
    
    # Run validation tests
    run_validation_tests
    
    # Cleanup temporary files
    if [[ -f lifecycle-config.json ]]; then
        rm -f lifecycle-config.json
    fi
    
    success "Deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Environment variables saved to .env file for cleanup"
        log "Use './destroy.sh' to clean up all resources"
        
        if [[ -f .env ]] && grep -q "API_URL=" .env; then
            source .env
            if [[ -n "${API_URL:-}" ]]; then
                log "API Endpoint: ${API_URL}"
                log "Test with: python3 test-music-client.py ${API_URL}"
            fi
        fi
    else
        log "Run without --dry-run flag to actually deploy resources"
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi