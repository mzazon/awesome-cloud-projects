#!/bin/bash

# Text-to-Speech Converter Deployment Script
# GCP Text-to-Speech with Cloud Storage Integration
# This script deploys the infrastructure and application for the text-to-speech converter

set -euo pipefail

# Configuration and environment variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" | tee -a "${LOG_FILE}"
}

# Error handling
handle_error() {
    log_error "Deployment failed on line $1"
    log_error "Check ${LOG_FILE} for detailed error information"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Text-to-Speech Converter with Cloud Storage

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           GCP Region (default: us-central1)
    -b, --bucket-name BUCKET      Storage bucket name (auto-generated if not provided)
    -d, --dry-run                 Show what would be deployed without executing
    -f, --force                   Force deployment even if resources exist
    -h, --help                    Show this help message

EXAMPLES:
    $0 --project-id my-tts-project
    $0 --project-id my-project --region us-east1 --bucket-name my-audio-bucket
    $0 --project-id my-project --dry-run

EOF
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -b|--bucket-name)
                BUCKET_NAME="$2"
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
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Set defaults
    REGION="${REGION:-us-central1}"
    DRY_RUN="${DRY_RUN:-false}"
    FORCE_DEPLOY="${FORCE_DEPLOY:-false}"
    
    # Generate unique bucket name if not provided
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        BUCKET_NAME="tts-audio-${PROJECT_ID}-$(date +%s)"
    fi

    # Validate required parameters
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "Project ID is required. Use --project-id option."
        usage
    fi
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."

    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi

    # Check if Python is installed
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install Python 3.8+ first."
        exit 1
    fi

    # Check if pip is installed
    if ! command -v pip3 &> /dev/null; then
        log_error "pip3 is not installed. Please install pip first."
        exit 1
    fi

    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi

    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project '${PROJECT_ID}' does not exist or you don't have access to it."
        exit 1
    fi

    log_success "Prerequisites check completed"
}

# Save deployment configuration
save_config() {
    cat > "${CONFIG_FILE}" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
BUCKET_NAME=${BUCKET_NAME}
DEPLOYMENT_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    log_success "Configuration saved to ${CONFIG_FILE}"
}

# Configure GCP project and region
configure_gcp() {
    log "Configuring Google Cloud Project..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would set project to: ${PROJECT_ID}"
        log "[DRY RUN] Would set region to: ${REGION}"
        return
    fi

    # Set active project
    gcloud config set project "${PROJECT_ID}" >> "${LOG_FILE}" 2>&1
    gcloud config set compute/region "${REGION}" >> "${LOG_FILE}" 2>&1

    log_success "Project configured: ${PROJECT_ID}"
    log_success "Region set to: ${REGION}"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."

    local apis=(
        "texttospeech.googleapis.com"
        "storage.googleapis.com"
    )

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would enable APIs: ${apis[*]}"
        return
    fi

    for api in "${apis[@]}"; do
        log "Enabling API: ${api}"
        if gcloud services enable "${api}" >> "${LOG_FILE}" 2>&1; then
            log_success "API enabled: ${api}"
        else
            log_error "Failed to enable API: ${api}"
            exit 1
        fi
    done

    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30

    log_success "All required APIs enabled"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket for audio files..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create bucket: gs://${BUCKET_NAME}"
        log "[DRY RUN] Would set location to: ${REGION}"
        log "[DRY RUN] Would enable uniform bucket-level access"
        log "[DRY RUN] Would set public read permissions"
        return
    fi

    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        if [[ "${FORCE_DEPLOY}" == "true" ]]; then
            log_warning "Bucket gs://${BUCKET_NAME} already exists, but continuing due to --force flag"
        else
            log_error "Bucket gs://${BUCKET_NAME} already exists. Use --force to continue or choose a different bucket name."
            exit 1
        fi
    else
        # Create the bucket
        if gcloud storage buckets create "gs://${BUCKET_NAME}" \
            --location="${REGION}" \
            --storage-class=STANDARD \
            --uniform-bucket-level-access >> "${LOG_FILE}" 2>&1; then
            log_success "Storage bucket created: gs://${BUCKET_NAME}"
        else
            log_error "Failed to create storage bucket"
            exit 1
        fi
    fi

    # Set bucket permissions for public read access
    log "Setting bucket permissions for public read access..."
    if gcloud storage buckets add-iam-policy-binding \
        "gs://${BUCKET_NAME}" \
        --member="allUsers" \
        --role="roles/storage.objectViewer" >> "${LOG_FILE}" 2>&1; then
        log_success "Bucket permissions configured for public access"
    else
        log_warning "Failed to set public read permissions. Files may not be publicly accessible."
    fi
}

# Setup authentication
setup_authentication() {
    log "Setting up Application Default Credentials..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would configure Application Default Credentials"
        return
    fi

    # Check if ADC is already configured
    if gcloud auth application-default print-access-token &> /dev/null; then
        log_success "Application Default Credentials already configured"
    else
        log "Configuring Application Default Credentials..."
        log "You may be prompted to authenticate in your browser..."
        
        if gcloud auth application-default login >> "${LOG_FILE}" 2>&1; then
            log_success "Application Default Credentials configured"
        else
            log_error "Failed to configure Application Default Credentials"
            exit 1
        fi
    fi
}

# Install Python dependencies
install_python_dependencies() {
    log "Installing Python client libraries..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would install: google-cloud-texttospeech google-cloud-storage"
        return
    fi

    # Create a virtual environment (optional but recommended)
    if [[ ! -d "${SCRIPT_DIR}/venv" ]]; then
        log "Creating Python virtual environment..."
        python3 -m venv "${SCRIPT_DIR}/venv" >> "${LOG_FILE}" 2>&1
    fi

    # Activate virtual environment
    source "${SCRIPT_DIR}/venv/bin/activate"

    # Install required packages
    local packages=(
        "google-cloud-texttospeech"
        "google-cloud-storage"
    )

    for package in "${packages[@]}"; do
        log "Installing Python package: ${package}"
        if pip install "${package}" >> "${LOG_FILE}" 2>&1; then
            log_success "Package installed: ${package}"
        else
            log_error "Failed to install package: ${package}"
            exit 1
        fi
    done

    # Verify installations
    log "Verifying Python library installations..."
    if python3 -c "import google.cloud.texttospeech; print('Text-to-Speech library verified')" >> "${LOG_FILE}" 2>&1; then
        log_success "Text-to-Speech library verified"
    else
        log_error "Text-to-Speech library verification failed"
        exit 1
    fi

    if python3 -c "import google.cloud.storage; print('Storage library verified')" >> "${LOG_FILE}" 2>&1; then
        log_success "Storage library verified"
    else
        log_error "Storage library verification failed"
        exit 1
    fi
}

# Create the text-to-speech converter script
create_converter_script() {
    log "Creating text-to-speech converter script..."

    local script_path="${SCRIPT_DIR}/text_to_speech_converter.py"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create converter script at: ${script_path}"
        return
    fi

    cat > "${script_path}" << 'EOF'
#!/usr/bin/env python3
"""
Text-to-Speech Converter with Cloud Storage Integration
Converts text input to natural-sounding audio using Google Cloud Text-to-Speech API
and stores the result in Cloud Storage.
"""

import os
from google.cloud import texttospeech
from google.cloud import storage
import argparse

def synthesize_text_to_speech(text_input, output_filename, voice_name="en-US-Wavenet-D"):
    """
    Synthesizes speech from text using Google Cloud Text-to-Speech API.
    
    Args:
        text_input (str): Text to convert to speech
        output_filename (str): Name for the output audio file
        voice_name (str): Voice model to use for synthesis
    
    Returns:
        bytes: Audio content as bytes
    """
    # Initialize the Text-to-Speech client
    client = texttospeech.TextToSpeechClient()
    
    # Configure the text input
    synthesis_input = texttospeech.SynthesisInput(text=text_input)
    
    # Configure voice parameters based on the voice name
    language_code = voice_name.split('-')[0] + '-' + voice_name.split('-')[1]
    voice = texttospeech.VoiceSelectionParams(
        language_code=language_code,
        name=voice_name,
        ssml_gender=texttospeech.SsmlVoiceGender.NEUTRAL
    )
    
    # Configure audio output format
    audio_config = texttospeech.AudioConfig(
        audio_encoding=texttospeech.AudioEncoding.MP3
    )
    
    # Perform the text-to-speech request
    response = client.synthesize_speech(
        input=synthesis_input,
        voice=voice,
        audio_config=audio_config
    )
    
    print(f"✅ Audio synthesized successfully using voice: {voice_name}")
    return response.audio_content

def upload_to_cloud_storage(audio_content, bucket_name, filename):
    """
    Uploads audio content to Google Cloud Storage.
    
    Args:
        audio_content (bytes): Audio data to upload
        bucket_name (str): Name of the Cloud Storage bucket
        filename (str): Name for the stored file
    
    Returns:
        str: Public URL of the uploaded file
    """
    # Initialize the Storage client
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    blob = bucket.blob(filename)
    
    # Upload the audio content
    blob.upload_from_string(audio_content, content_type='audio/mpeg')
    
    # Make the blob publicly readable (optional)
    blob.make_public()
    
    public_url = blob.public_url
    print(f"✅ Audio uploaded to Cloud Storage: {public_url}")
    return public_url

def main():
    parser = argparse.ArgumentParser(description='Convert text to speech and store in Cloud Storage')
    parser.add_argument('--text', required=True, help='Text to convert to speech')
    parser.add_argument('--output', default='output.mp3', help='Output filename')
    parser.add_argument('--bucket', required=True, help='Cloud Storage bucket name')
    parser.add_argument('--voice', default='en-US-Wavenet-D', help='Voice to use for synthesis')
    
    args = parser.parse_args()
    
    try:
        # Synthesize text to speech
        audio_content = synthesize_text_to_speech(args.text, args.output, args.voice)
        
        # Upload to Cloud Storage
        public_url = upload_to_cloud_storage(audio_content, args.bucket, args.output)
        
        print(f"\n🎉 Text-to-Speech conversion completed successfully!")
        print(f"📁 File: {args.output}")
        print(f"🔗 URL: {public_url}")
        print(f"📊 Audio length: ~{len(args.text) * 0.1:.1f} seconds (estimated)")
        
    except Exception as e:
        print(f"❌ Error during conversion: {str(e)}")
        return 1
    
    return 0

if __name__ == "__main__":
    exit(main())
EOF

    chmod +x "${script_path}"
    log_success "Text-to-Speech converter script created at: ${script_path}"
}

# Test the deployment
test_deployment() {
    log "Testing the text-to-speech conversion..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would test text-to-speech conversion with demo text"
        return
    fi

    local test_text="Hello! Welcome to Google Cloud Text-to-Speech. This is a demonstration of converting text into natural-sounding speech using advanced AI models."
    local test_output="deployment-test-$(date +%s).mp3"

    # Activate virtual environment if it exists
    if [[ -d "${SCRIPT_DIR}/venv" ]]; then
        source "${SCRIPT_DIR}/venv/bin/activate"
    fi

    log "Running text-to-speech test conversion..."
    if python3 "${SCRIPT_DIR}/text_to_speech_converter.py" \
        --text "${test_text}" \
        --output "${test_output}" \
        --bucket "${BUCKET_NAME}" \
        --voice "en-US-Wavenet-D" >> "${LOG_FILE}" 2>&1; then
        log_success "Test conversion completed successfully!"
        log_success "Test audio file: ${test_output}"
    else
        log_error "Test conversion failed. Check the log for details."
        exit 1
    fi
}

# Display deployment summary
show_deployment_summary() {
    log_success "=== Deployment Summary ==="
    log_success "Project ID: ${PROJECT_ID}"
    log_success "Region: ${REGION}"
    log_success "Storage Bucket: gs://${BUCKET_NAME}"
    log_success "Converter Script: ${SCRIPT_DIR}/text_to_speech_converter.py"
    
    if [[ -f "${CONFIG_FILE}" ]]; then
        log_success "Configuration File: ${CONFIG_FILE}"
    fi
    
    if [[ -d "${SCRIPT_DIR}/venv" ]]; then
        log_success "Python Virtual Environment: ${SCRIPT_DIR}/venv"
    fi

    echo
    log_success "=== Next Steps ==="
    echo "1. Test the converter with custom text:"
    echo "   python3 ${SCRIPT_DIR}/text_to_speech_converter.py \\"
    echo "     --text 'Your text here' \\"
    echo "     --output 'my-audio.mp3' \\"
    echo "     --bucket '${BUCKET_NAME}' \\"
    echo "     --voice 'en-US-Wavenet-D'"
    echo
    echo "2. Try different voices:"
    echo "   --voice 'en-US-Studio-M' (Studio quality)"
    echo "   --voice 'fr-FR-Wavenet-A' (French)"
    echo
    echo "3. View generated audio files:"
    echo "   gcloud storage ls gs://${BUCKET_NAME}/"
    echo
    echo "4. Clean up resources when done:"
    echo "   ${SCRIPT_DIR}/destroy.sh --project-id ${PROJECT_ID}"
}

# Main deployment function
main() {
    echo "🚀 Text-to-Speech Converter Deployment Script"
    echo "=============================================="
    echo

    # Initialize log file
    echo "Deployment started at $(date)" > "${LOG_FILE}"

    # Parse command line arguments
    parse_args "$@"

    # Show what will be deployed
    log "Deployment Configuration:"
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Bucket Name: ${BUCKET_NAME}"
    log "Dry Run: ${DRY_RUN}"
    log "Force Deploy: ${FORCE_DEPLOY}"
    echo

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No actual resources will be created"
        echo
    fi

    # Execute deployment steps
    check_prerequisites
    save_config
    configure_gcp
    enable_apis
    create_storage_bucket
    setup_authentication
    install_python_dependencies
    create_converter_script
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        test_deployment
    fi
    
    show_deployment_summary

    log_success "Deployment completed successfully!"
}

# Handle script interruption
cleanup_on_interrupt() {
    log_warning "Deployment interrupted by user"
    exit 130
}

trap cleanup_on_interrupt SIGINT SIGTERM

# Execute main function with all arguments
main "$@"