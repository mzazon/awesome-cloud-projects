#!/bin/bash

# Meeting Summary Generation with Speech-to-Text and Gemini - Deployment Script
# This script deploys the complete infrastructure for automated meeting processing

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
FUNCTION_SOURCE_DIR="${SCRIPT_DIR}/../meeting-processor"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${2:-$NC}$(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1" "$RED"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..." "$BLUE"
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        error_exit "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is required for generating random values."
    fi
    
    log "Prerequisites check completed ✅" "$GREEN"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..." "$BLUE"
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-meeting-summary-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="${BUCKET_NAME:-meeting-recordings-${RANDOM_SUFFIX}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-process-meeting-${RANDOM_SUFFIX}}"
    
    # Store variables for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
BUCKET_NAME=${BUCKET_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log "Environment variables configured:" "$GREEN"
    log "  Project ID: ${PROJECT_ID}" "$GREEN"
    log "  Region: ${REGION}" "$GREEN"
    log "  Bucket Name: ${BUCKET_NAME}" "$GREEN"
    log "  Function Name: ${FUNCTION_NAME}" "$GREEN"
}

# Check if project exists and create if needed
setup_project() {
    log "Setting up GCP project..." "$BLUE"
    
    # Check if project exists
    if gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log "Project $PROJECT_ID already exists" "$YELLOW"
    else
        log "Creating new project: $PROJECT_ID" "$BLUE"
        if ! gcloud projects create "$PROJECT_ID" 2>> "$LOG_FILE"; then
            error_exit "Failed to create project $PROJECT_ID"
        fi
        log "Project created successfully ✅" "$GREEN"
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID" || error_exit "Failed to set project"
    gcloud config set compute/region "$REGION" || error_exit "Failed to set region"
    
    log "Project configuration completed ✅" "$GREEN"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..." "$BLUE"
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "speech.googleapis.com"
        "aiplatform.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling $api..." "$BLUE"
        if gcloud services enable "$api" 2>> "$LOG_FILE"; then
            log "  $api enabled ✅" "$GREEN"
        else
            error_exit "Failed to enable $api"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..." "$BLUE"
    sleep 30
    
    log "All APIs enabled successfully ✅" "$GREEN"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket..." "$BLUE"
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        log "Bucket gs://${BUCKET_NAME} already exists" "$YELLOW"
    else
        # Create Cloud Storage bucket
        if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://${BUCKET_NAME}" 2>> "$LOG_FILE"; then
            log "Cloud Storage bucket created ✅" "$GREEN"
        else
            error_exit "Failed to create Cloud Storage bucket"
        fi
    fi
    
    # Enable uniform bucket-level access
    if gsutil uniformbucketlevelaccess set on "gs://${BUCKET_NAME}" 2>> "$LOG_FILE"; then
        log "Uniform bucket-level access enabled ✅" "$GREEN"
    else
        log "Warning: Failed to enable uniform bucket-level access" "$YELLOW"
    fi
    
    # Set lifecycle policy
    cat > "${SCRIPT_DIR}/lifecycle.json" << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"age": 30}
      }
    ]
  }
}
EOF
    
    if gsutil lifecycle set "${SCRIPT_DIR}/lifecycle.json" "gs://${BUCKET_NAME}" 2>> "$LOG_FILE"; then
        log "Lifecycle policy applied ✅" "$GREEN"
    else
        log "Warning: Failed to apply lifecycle policy" "$YELLOW"
    fi
    
    # Clean up temporary file
    rm -f "${SCRIPT_DIR}/lifecycle.json"
}

# Create Cloud Function source code
create_function_source() {
    log "Creating Cloud Function source code..." "$BLUE"
    
    # Create function directory
    mkdir -p "$FUNCTION_SOURCE_DIR"
    
    # Create main function file
    cat > "${FUNCTION_SOURCE_DIR}/main.py" << 'EOF'
import functions_framework
import json
import os
from google.cloud import speech
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel
import logging

# Initialize clients
storage_client = storage.Client()
speech_client = speech.SpeechClient()

# Initialize Vertex AI
vertexai.init(project=os.environ.get('GCP_PROJECT'), 
              location='us-central1')
model = GenerativeModel('gemini-1.5-pro')

@functions_framework.cloud_event
def process_meeting(cloud_event):
    """Process uploaded meeting audio file"""
    try:
        # Get file information from Cloud Storage event
        bucket_name = cloud_event.data['bucket']
        file_name = cloud_event.data['name']
        
        if not file_name.lower().endswith(('.wav', '.mp3', '.flac', '.m4a')):
            logging.info(f"Skipping non-audio file: {file_name}")
            return
        
        logging.info(f"Processing audio file: {file_name}")
        
        # Step 1: Transcribe audio using Speech-to-Text
        transcript = transcribe_audio(bucket_name, file_name)
        
        if not transcript:
            logging.error("Transcription failed or empty")
            return
        
        # Step 2: Generate summary using Gemini
        summary = generate_meeting_summary(transcript, file_name)
        
        # Step 3: Save results to Cloud Storage
        save_results(bucket_name, file_name, transcript, summary)
        
        logging.info(f"Successfully processed meeting: {file_name}")
        
    except Exception as e:
        logging.error(f"Error processing meeting: {str(e)}")
        raise

def transcribe_audio(bucket_name, file_name):
    """Transcribe audio file using Speech-to-Text API"""
    try:
        # Configure audio and recognition settings
        audio = speech.RecognitionAudio(
            uri=f"gs://{bucket_name}/{file_name}"
        )
        
        config = speech.RecognitionConfig(
            encoding=speech.RecognitionConfig.AudioEncoding.ENCODING_UNSPECIFIED,
            sample_rate_hertz=16000,
            language_code="en-US",
            enable_automatic_punctuation=True,
            enable_speaker_diarization=True,
            diarization_speaker_count_min=2,
            diarization_speaker_count_max=6,
            model="latest_long",
        )
        
        # Perform transcription
        operation = speech_client.long_running_recognize(
            config=config, audio=audio
        )
        
        logging.info("Waiting for Speech-to-Text operation to complete...")
        response = operation.result(timeout=300)
        
        # Extract transcript with speaker labels
        transcript_parts = []
        for result in response.results:
            alternative = result.alternatives[0]
            # For files with speaker diarization, extract speaker info
            if hasattr(alternative, 'words') and alternative.words:
                current_speaker = None
                speaker_words = []
                
                for word in alternative.words:
                    if word.speaker_tag != current_speaker:
                        if speaker_words:
                            transcript_parts.append(
                                f"Speaker {current_speaker}: {' '.join(speaker_words)}"
                            )
                        current_speaker = word.speaker_tag
                        speaker_words = [word.word]
                    else:
                        speaker_words.append(word.word)
                
                # Add final speaker segment
                if speaker_words:
                    transcript_parts.append(
                        f"Speaker {current_speaker}: {' '.join(speaker_words)}"
                    )
            else:
                # Fallback for files without speaker diarization
                transcript_parts.append(alternative.transcript)
        
        full_transcript = '\n'.join(transcript_parts)
        
        logging.info(f"Transcription completed: {len(full_transcript)} characters")
        return full_transcript
        
    except Exception as e:
        logging.error(f"Transcription error: {str(e)}")
        return None

def generate_meeting_summary(transcript, file_name):
    """Generate structured meeting summary using Gemini"""
    try:
        prompt = f"""
        Please analyze this meeting transcript and create a structured summary with the following sections:

        **Meeting Summary for: {file_name}**

        **Key Topics Discussed:**
        - List the main topics covered in the meeting

        **Important Decisions:**
        - List any decisions that were made during the meeting

        **Action Items:**
        - List specific action items with responsible parties (if mentioned)
        - Include deadlines if specified

        **Key Insights:**
        - Important insights, concerns, or notable discussions

        **Next Steps:**
        - What should happen following this meeting

        Transcript:
        {transcript}

        Please format your response in clear markdown with the exact section headers shown above.
        """
        
        response = model.generate_content(prompt)
        summary = response.text
        
        logging.info(f"Summary generated: {len(summary)} characters")
        return summary
        
    except Exception as e:
        logging.error(f"Summary generation error: {str(e)}")
        return f"Error generating summary: {str(e)}"

def save_results(bucket_name, audio_file, transcript, summary):
    """Save transcription and summary results to Cloud Storage"""
    try:
        bucket = storage_client.bucket(bucket_name)
        
        # Save full transcript
        transcript_blob = bucket.blob(f"transcripts/{audio_file}.txt")
        transcript_blob.upload_from_string(transcript)
        
        # Save meeting summary
        summary_blob = bucket.blob(f"summaries/{audio_file}_summary.md")
        summary_blob.upload_from_string(summary)
        
        logging.info("Results saved to Cloud Storage")
        
    except Exception as e:
        logging.error(f"Error saving results: {str(e)}")
EOF
    
    # Create requirements file
    cat > "${FUNCTION_SOURCE_DIR}/requirements.txt" << 'EOF'
functions-framework==3.5.0
google-cloud-speech==2.24.0
google-cloud-storage==2.13.0
google-cloud-aiplatform==1.42.0
vertexai==1.42.0
EOF
    
    log "Cloud Function source code created ✅" "$GREEN"
}

# Deploy Cloud Function
deploy_function() {
    log "Deploying Cloud Function..." "$BLUE"
    
    # Change to function source directory
    cd "$FUNCTION_SOURCE_DIR"
    
    # Deploy Cloud Function with retry logic
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log "Deployment attempt $attempt of $max_attempts..." "$BLUE"
        
        if gcloud functions deploy "$FUNCTION_NAME" \
            --gen2 \
            --runtime python311 \
            --trigger-bucket "$BUCKET_NAME" \
            --entry-point process_meeting \
            --memory 1GB \
            --timeout 540s \
            --max-instances 10 \
            --region "$REGION" \
            --set-env-vars "GCP_PROJECT=${PROJECT_ID}" \
            --quiet 2>> "$LOG_FILE"; then
            
            log "Cloud Function deployed successfully ✅" "$GREEN"
            break
        else
            if [ $attempt -eq $max_attempts ]; then
                error_exit "Failed to deploy Cloud Function after $max_attempts attempts"
            else
                log "Deployment attempt $attempt failed, retrying in 30 seconds..." "$YELLOW"
                sleep 30
                ((attempt++))
            fi
        fi
    done
    
    # Return to script directory
    cd "$SCRIPT_DIR"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..." "$BLUE"
    
    # Check function status
    if gcloud functions describe "$FUNCTION_NAME" --region "$REGION" --format="value(status)" 2>> "$LOG_FILE" | grep -q "ACTIVE"; then
        log "Cloud Function is active ✅" "$GREEN"
    else
        error_exit "Cloud Function is not active"
    fi
    
    # Check bucket exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        log "Cloud Storage bucket is accessible ✅" "$GREEN"
    else
        error_exit "Cloud Storage bucket is not accessible"
    fi
    
    log "Deployment verification completed ✅" "$GREEN"
}

# Create test file for validation
create_test_file() {
    log "Creating test file for validation..." "$BLUE"
    
    # Create a simple test file
    echo "This is a test audio file for meeting processing validation" > "${SCRIPT_DIR}/test_meeting.txt"
    
    # Upload test file to trigger the function
    if gsutil cp "${SCRIPT_DIR}/test_meeting.txt" "gs://${BUCKET_NAME}/test_meeting.wav" 2>> "$LOG_FILE"; then
        log "Test file uploaded ✅" "$GREEN"
    else
        log "Warning: Failed to upload test file" "$YELLOW"
    fi
    
    # Clean up local test file
    rm -f "${SCRIPT_DIR}/test_meeting.txt"
}

# Display deployment summary
display_summary() {
    log "Deployment Summary:" "$GREEN"
    log "==================" "$GREEN"
    log "Project ID: ${PROJECT_ID}" "$GREEN"
    log "Region: ${REGION}" "$GREEN"
    log "Cloud Storage Bucket: gs://${BUCKET_NAME}" "$GREEN"
    log "Cloud Function: ${FUNCTION_NAME}" "$GREEN"
    log "" "$GREEN"
    log "Next Steps:" "$BLUE"
    log "1. Upload audio files (.wav, .mp3, .flac, .m4a) to: gs://${BUCKET_NAME}" "$BLUE"
    log "2. Monitor function logs: gcloud functions logs read ${FUNCTION_NAME} --region ${REGION}" "$BLUE"
    log "3. Check generated outputs in: gs://${BUCKET_NAME}/transcripts/ and gs://${BUCKET_NAME}/summaries/" "$BLUE"
    log "4. Run destroy.sh to clean up resources when done" "$BLUE"
    log "" "$GREEN"
    log "Environment variables saved to: ${SCRIPT_DIR}/.env" "$GREEN"
}

# Main deployment function
main() {
    log "Starting Meeting Summary Generation deployment..." "$GREEN"
    log "================================================" "$GREEN"
    
    # Create log file
    touch "$LOG_FILE"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_bucket
    create_function_source
    deploy_function
    verify_deployment
    create_test_file
    display_summary
    
    log "Deployment completed successfully! 🎉" "$GREEN"
}

# Handle script interruption
trap 'log "Deployment interrupted" "$RED"; exit 1' INT TERM

# Run main function
main "$@"