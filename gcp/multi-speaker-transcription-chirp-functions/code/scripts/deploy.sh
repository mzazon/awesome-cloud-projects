#!/bin/bash

# Multi-Speaker Transcription with Chirp and Cloud Functions - Deployment Script
# This script deploys the complete infrastructure for speech transcription with speaker diarization

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "Google Cloud Storage utility (gsutil) is not installed."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if Python 3 is installed
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install Python 3.8 or later."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [ -z "${PROJECT_ID:-}" ]; then
        export PROJECT_ID="speech-transcription-$(date +%s)"
        log "Generated PROJECT_ID: ${PROJECT_ID}"
    fi
    
    # Set default values
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export INPUT_BUCKET="${PROJECT_ID}-audio-input-${RANDOM_SUFFIX}"
    export OUTPUT_BUCKET="${PROJECT_ID}-transcripts-output-${RANDOM_SUFFIX}"
    
    log "Environment variables configured:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  ZONE: ${ZONE}"
    log "  INPUT_BUCKET: ${INPUT_BUCKET}"
    log "  OUTPUT_BUCKET: ${OUTPUT_BUCKET}"
}

# Create and configure GCP project
setup_project() {
    log "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe ${PROJECT_ID} &> /dev/null; then
        log_warning "Project ${PROJECT_ID} already exists. Using existing project."
    else
        # Create new project
        log "Creating new project: ${PROJECT_ID}"
        gcloud projects create ${PROJECT_ID} --name="Speech Transcription Project"
        
        # Check if billing account is available
        BILLING_ACCOUNT=$(gcloud billing accounts list --filter="open:true" --format="value(name)" | head -n1)
        if [ -n "${BILLING_ACCOUNT}" ]; then
            gcloud billing projects link ${PROJECT_ID} --billing-account=${BILLING_ACCOUNT}
            log_success "Billing account linked to project"
        else
            log_warning "No billing account found. Please link a billing account manually."
        fi
    fi
    
    # Set default project and region
    gcloud config set project ${PROJECT_ID}
    gcloud config set compute/region ${REGION}
    gcloud config set compute/zone ${ZONE}
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "speech.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        gcloud services enable ${api}
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create Cloud Storage buckets
create_storage_buckets() {
    log "Creating Cloud Storage buckets..."
    
    # Create input bucket
    if gsutil ls gs://${INPUT_BUCKET} &> /dev/null; then
        log_warning "Input bucket ${INPUT_BUCKET} already exists"
    else
        gsutil mb -p ${PROJECT_ID} -c STANDARD -l ${REGION} gs://${INPUT_BUCKET}
        log_success "Input bucket created: ${INPUT_BUCKET}"
    fi
    
    # Create output bucket
    if gsutil ls gs://${OUTPUT_BUCKET} &> /dev/null; then
        log_warning "Output bucket ${OUTPUT_BUCKET} already exists"
    else
        gsutil mb -p ${PROJECT_ID} -c STANDARD -l ${REGION} gs://${OUTPUT_BUCKET}
        log_success "Output bucket created: ${OUTPUT_BUCKET}"
    fi
    
    # Create transcripts folder in output bucket
    echo "" | gsutil cp - gs://${OUTPUT_BUCKET}/transcripts/.gitkeep
    
    log_success "Storage buckets setup completed"
}

# Create Cloud Function source code
create_function_code() {
    log "Creating Cloud Function source code..."
    
    # Create function directory
    FUNCTION_DIR="transcription-function"
    mkdir -p ${FUNCTION_DIR}
    cd ${FUNCTION_DIR}
    
    # Create requirements.txt
    cat << 'EOF' > requirements.txt
google-cloud-speech>=2.27.0
google-cloud-storage>=2.18.0
functions-framework>=3.8.0
EOF
    
    # Create main.py with comprehensive error handling and logging
    cat << 'EOF' > main.py
import json
import os
import logging
from google.cloud import speech_v2 as speech
from google.cloud import storage
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def transcribe_audio_with_diarization(audio_uri, output_bucket, filename):
    """Transcribe audio with speaker diarization using Chirp 3 model."""
    
    try:
        # Initialize Speech-to-Text v2 client
        client = speech.SpeechClient()
        
        # Create recognizer with Chirp 3 model configuration
        recognizer_config = speech.Recognizer(
            default_recognition_config=speech.RecognitionConfig(
                auto_decoding_config=speech.AutoDetectDecodingConfig(),
                language_codes=["en-US"],
                model="chirp_3",  # Use Chirp 3 model with diarization support
                features=speech.RecognitionFeatures(
                    enable_speaker_diarization=True,
                    diarization_speaker_count_min=2,
                    diarization_speaker_count_max=6,
                    enable_automatic_punctuation=True,
                    enable_word_time_offsets=True,
                ),
            )
        )
        
        # Create recognizer
        project_id = os.environ.get('GCP_PROJECT')
        recognizer_name = f"projects/{project_id}/locations/global/recognizers/_"
        
        # Configure batch recognition request
        request = speech.BatchRecognizeRequest(
            recognizer=recognizer_name,
            config=recognizer_config.default_recognition_config,
            files=[
                speech.BatchRecognizeFileMetadata(
                    uri=audio_uri,
                )
            ],
        )
        
        # Perform batch recognition operation
        logger.info(f"Starting transcription for: {filename}")
        operation = client.batch_recognize(request=request)
        
        response = operation.result(timeout=600)  # 10 minute timeout
        
        # Process results with speaker labels
        transcript_data = {
            "filename": filename,
            "speakers": {},
            "full_transcript": "",
            "word_details": []
        }
        
        for result in response.results.values():
            for alternative in result.alternatives:
                transcript_data["full_transcript"] += alternative.transcript + " "
                
                # Process speaker-labeled words
                for word in alternative.words:
                    speaker_tag = word.speaker_tag if hasattr(word, 'speaker_tag') else 1
                    word_text = word.word
                    start_time = word.start_offset.total_seconds() if word.start_offset else 0
                    end_time = word.end_offset.total_seconds() if word.end_offset else 0
                    
                    # Group words by speaker
                    if speaker_tag not in transcript_data["speakers"]:
                        transcript_data["speakers"][speaker_tag] = []
                    
                    transcript_data["speakers"][speaker_tag].append({
                        "word": word_text,
                        "start_time": start_time,
                        "end_time": end_time
                    })
                    
                    transcript_data["word_details"].append({
                        "word": word_text,
                        "speaker": speaker_tag,
                        "start_time": start_time,
                        "end_time": end_time
                    })
        
        # Save results to output bucket
        storage_client = storage.Client()
        bucket = storage_client.bucket(output_bucket)
        
        # Save JSON transcript
        json_filename = f"transcripts/{filename}_transcript.json"
        blob = bucket.blob(json_filename)
        blob.upload_from_string(
            json.dumps(transcript_data, indent=2),
            content_type="application/json"
        )
        
        # Save readable transcript
        readable_transcript = generate_readable_transcript(transcript_data)
        txt_filename = f"transcripts/{filename}_readable.txt"
        blob = bucket.blob(txt_filename)
        blob.upload_from_string(readable_transcript, content_type="text/plain")
        
        logger.info(f"Transcription completed for: {filename}")
        return transcript_data
        
    except Exception as e:
        logger.error(f"Error in transcription: {str(e)}")
        raise

def generate_readable_transcript(transcript_data):
    """Generate human-readable transcript with speaker labels."""
    output = f"Transcription Results\n"
    output += f"==================\n\n"
    output += f"File: {transcript_data['filename']}\n"
    output += f"Speakers detected: {len(transcript_data['speakers'])}\n\n"
    
    # Group consecutive words by speaker
    current_speaker = None
    current_segment = []
    
    for word_detail in transcript_data["word_details"]:
        if word_detail["speaker"] != current_speaker:
            if current_segment:
                output += f"Speaker {current_speaker}: {' '.join(current_segment)}\n\n"
            current_speaker = word_detail["speaker"]
            current_segment = [word_detail["word"]]
        else:
            current_segment.append(word_detail["word"])
    
    # Add final segment
    if current_segment:
        output += f"Speaker {current_speaker}: {' '.join(current_segment)}\n\n"
    
    return output

@functions_framework.cloud_event
def process_audio_upload(cloud_event):
    """Cloud Function triggered by Cloud Storage uploads."""
    
    try:
        # Extract event data
        data = cloud_event.data
        bucket_name = data["bucket"]
        file_name = data["name"]
        
        logger.info(f"Processing file: {file_name} from bucket: {bucket_name}")
        
        # Only process audio files
        audio_extensions = ['.wav', '.mp3', '.flac', '.m4a', '.ogg']
        if not any(file_name.lower().endswith(ext) for ext in audio_extensions):
            logger.info(f"Skipping non-audio file: {file_name}")
            return
        
        # Construct audio URI
        audio_uri = f"gs://{bucket_name}/{file_name}"
        output_bucket = os.environ.get('OUTPUT_BUCKET')
        
        if not output_bucket:
            logger.error("OUTPUT_BUCKET environment variable not set")
            return
        
        # Process transcription
        result = transcribe_audio_with_diarization(
            audio_uri, output_bucket, file_name
        )
        
        logger.info(f"Successfully processed: {file_name}")
        logger.info(f"Speakers detected: {len(result['speakers'])}")
        
    except Exception as e:
        logger.error(f"Error processing {file_name}: {str(e)}")
        raise e
EOF
    
    cd ..
    log_success "Cloud Function source code created"
}

# Deploy Cloud Function
deploy_function() {
    log "Deploying Cloud Function..."
    
    cd transcription-function
    
    # Deploy function with Cloud Storage trigger
    gcloud functions deploy process-audio-transcription \
        --gen2 \
        --runtime python312 \
        --trigger-bucket ${INPUT_BUCKET} \
        --source . \
        --entry-point process_audio_upload \
        --memory 2GB \
        --timeout 540s \
        --set-env-vars OUTPUT_BUCKET=${OUTPUT_BUCKET} \
        --max-instances 5 \
        --region ${REGION} \
        --quiet
    
    cd ..
    
    # Wait for deployment to complete
    log "Waiting for function deployment to complete..."
    sleep 30
    
    # Verify deployment
    local function_state=$(gcloud functions describe process-audio-transcription \
        --region ${REGION} \
        --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    
    if [ "${function_state}" = "ACTIVE" ]; then
        log_success "Cloud Function deployed successfully"
    else
        log_error "Cloud Function deployment failed. State: ${function_state}"
        exit 1
    fi
}

# Test the deployment with sample audio
test_deployment() {
    log "Testing deployment with sample audio..."
    
    # Create a simple test audio file (if curl is available)
    if command -v curl &> /dev/null; then
        log "Downloading sample audio file..."
        curl -L "https://storage.googleapis.com/cloud-samples-tests/speech/multi-speaker-sample.wav" \
            -o sample_meeting.wav 2>/dev/null || {
            log_warning "Could not download sample file. Manual testing required."
            return 0
        }
        
        # Upload to input bucket to trigger function
        gsutil cp sample_meeting.wav gs://${INPUT_BUCKET}/
        log "Sample audio uploaded. Processing will begin automatically."
        
        # Wait for processing
        log "Waiting for transcription processing (60 seconds)..."
        sleep 60
        
        # Check for output files
        if gsutil ls gs://${OUTPUT_BUCKET}/transcripts/ &> /dev/null; then
            log_success "Test transcription completed successfully"
            gsutil ls gs://${OUTPUT_BUCKET}/transcripts/
        else
            log_warning "No transcription output found yet. Check function logs for details."
        fi
        
        # Clean up test file
        rm -f sample_meeting.wav
    else
        log_warning "curl not available. Skipping automatic test."
    fi
}

# Save deployment configuration
save_config() {
    log "Saving deployment configuration..."
    
    cat << EOF > deployment-config.env
# Multi-Speaker Transcription Deployment Configuration
# Generated on: $(date)

export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"
export INPUT_BUCKET="${INPUT_BUCKET}"
export OUTPUT_BUCKET="${OUTPUT_BUCKET}"
export FUNCTION_NAME="process-audio-transcription"

# Usage:
# Source this file to restore environment variables:
# source deployment-config.env
EOF
    
    log_success "Configuration saved to deployment-config.env"
}

# Main deployment function
main() {
    echo "🚀 Starting Multi-Speaker Transcription with Chirp and Cloud Functions Deployment"
    echo "============================================================================="
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_buckets
    create_function_code
    deploy_function
    test_deployment
    save_config
    
    echo ""
    echo "============================================================================="
    log_success "Deployment completed successfully!"
    echo ""
    log "📋 Deployment Summary:"
    log "  Project ID: ${PROJECT_ID}"
    log "  Region: ${REGION}"
    log "  Input Bucket: gs://${INPUT_BUCKET}"
    log "  Output Bucket: gs://${OUTPUT_BUCKET}"
    log "  Function Name: process-audio-transcription"
    echo ""
    log "📖 Next Steps:"
    log "  1. Upload audio files to: gs://${INPUT_BUCKET}"
    log "  2. Transcripts will be saved to: gs://${OUTPUT_BUCKET}/transcripts/"
    log "  3. Monitor function logs with: gcloud functions logs read process-audio-transcription --region ${REGION}"
    echo ""
    log "💡 To restore environment variables later:"
    log "  source deployment-config.env"
    echo ""
}

# Handle script interruption
trap 'log_error "Deployment interrupted. Some resources may have been created."; exit 1' INT TERM

# Run main function
main "$@"