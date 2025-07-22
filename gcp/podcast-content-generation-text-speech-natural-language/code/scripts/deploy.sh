#!/bin/bash

# Podcast Content Generation with Text-to-Speech and Natural Language - Deployment Script
# This script deploys the complete infrastructure for automated podcast generation

set -euo pipefail

# Color codes for output formatting
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

# Print usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy podcast generation infrastructure on Google Cloud Platform

OPTIONS:
    -p, --project-id        GCP Project ID (required)
    -r, --region           GCP region (default: us-central1)
    -b, --bucket-suffix    Custom bucket suffix (default: auto-generated)
    -d, --dry-run          Show what would be deployed without making changes
    -h, --help             Show this help message
    --skip-billing-check   Skip billing account verification
    --use-existing-project Use existing project instead of creating new one

EXAMPLES:
    $0 --project-id my-podcast-project
    $0 --project-id my-project --region us-east1 --bucket-suffix demo
    $0 --dry-run --project-id test-project

EOF
}

# Default values
REGION="us-central1"
BUCKET_SUFFIX=""
DRY_RUN=false
SKIP_BILLING_CHECK=false
USE_EXISTING_PROJECT=false
PROJECT_ID=""

# Parse command line arguments
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
        -b|--bucket-suffix)
            BUCKET_SUFFIX="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-billing-check)
            SKIP_BILLING_CHECK=true
            shift
            ;;
        --use-existing-project)
            USE_EXISTING_PROJECT=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    log_error "Project ID is required. Use --project-id or -p"
    usage
    exit 1
fi

# Generate unique suffix if not provided
if [[ -z "$BUCKET_SUFFIX" ]]; then
    BUCKET_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s)")
fi

# Set derived variables
BUCKET_NAME="podcast-content-${BUCKET_SUFFIX}"
FUNCTION_NAME="podcast-processor"
SERVICE_ACCOUNT_NAME="podcast-generator"

log_info "Starting podcast generation infrastructure deployment"
log_info "Project ID: ${PROJECT_ID}"
log_info "Region: ${REGION}"
log_info "Bucket Name: ${BUCKET_NAME}"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        log_info "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed."
        exit 1
    fi
    
    # Check if openssl is available for generating random values
    if ! command -v openssl &> /dev/null; then
        log_warning "openssl not found. Using date-based suffix generation."
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "No active gcloud authentication found."
        log_info "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Create or configure project
setup_project() {
    log_info "Setting up project: ${PROJECT_ID}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure project ${PROJECT_ID}"
        return 0
    fi
    
    if [[ "$USE_EXISTING_PROJECT" == "false" ]]; then
        # Check if project exists
        if gcloud projects describe "$PROJECT_ID" &> /dev/null; then
            log_warning "Project ${PROJECT_ID} already exists. Using existing project."
        else
            log_info "Creating new project: ${PROJECT_ID}"
            gcloud projects create "$PROJECT_ID" \
                --name="Podcast Generation System" || {
                log_error "Failed to create project. It may already exist or name may be taken."
                exit 1
            }
            log_success "Project created successfully"
        fi
        
        # Check billing configuration if not skipped
        if [[ "$SKIP_BILLING_CHECK" == "false" ]]; then
            log_info "Checking billing configuration..."
            if ! gcloud billing projects describe "$PROJECT_ID" &> /dev/null; then
                log_warning "No billing account linked to project."
                log_info "Please link a billing account:"
                log_info "gcloud billing projects link ${PROJECT_ID} --billing-account=YOUR_BILLING_ACCOUNT_ID"
                log_info "Or re-run with --skip-billing-check flag"
                exit 1
            fi
            log_success "Billing account is configured"
        fi
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    
    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "texttospeech.googleapis.com"
        "language.googleapis.com"
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: ${apis[*]}"
        return 0
    fi
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "$api" --quiet; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All APIs enabled successfully"
}

# Create service account
create_service_account() {
    log_info "Creating service account: ${SERVICE_ACCOUNT_NAME}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create service account ${SERVICE_ACCOUNT_NAME}"
        return 0
    fi
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" &> /dev/null; then
        log_warning "Service account already exists. Using existing account."
    else
        gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
            --display-name="Podcast Content Generator" \
            --description="Service account for TTS and NL API access"
        log_success "Service account created"
    fi
    
    # Assign required roles
    local roles=(
        "roles/storage.admin"
        "roles/ml.developer"
        "roles/cloudfunctions.developer"
        "roles/logging.logWriter"
    )
    
    for role in "${roles[@]}"; do
        log_info "Assigning role: ${role}"
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="$role" \
            --quiet
    done
    
    # Generate service account key
    log_info "Generating service account key..."
    gcloud iam service-accounts keys create "${HOME}/podcast-key.json" \
        --iam-account="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Set environment variable
    export GOOGLE_APPLICATION_CREDENTIALS="${HOME}/podcast-key.json"
    
    log_success "Service account configured with required permissions"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: ${BUCKET_NAME}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create bucket ${BUCKET_NAME}"
        return 0
    fi
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        log_warning "Bucket already exists. Using existing bucket."
    else
        gsutil mb -p "$PROJECT_ID" \
            -c STANDARD \
            -l "$REGION" \
            "gs://${BUCKET_NAME}"
        log_success "Storage bucket created"
    fi
    
    # Enable versioning for content protection
    gsutil versioning set on "gs://${BUCKET_NAME}"
    
    # Create directory structure
    echo "Creating directory structure..." | gsutil cp - "gs://${BUCKET_NAME}/input/.keep"
    echo "Creating directory structure..." | gsutil cp - "gs://${BUCKET_NAME}/processed/.keep"
    echo "Creating directory structure..." | gsutil cp - "gs://${BUCKET_NAME}/audio/.keep"
    
    log_success "Storage bucket configured with directory structure"
}

# Create and deploy Cloud Function
deploy_cloud_function() {
    log_info "Creating and deploying Cloud Function: ${FUNCTION_NAME}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy Cloud Function ${FUNCTION_NAME}"
        return 0
    fi
    
    # Create temporary directory for function code
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-language==2.13.0
google-cloud-texttospeech==2.16.3
google-cloud-storage==2.10.0
functions-framework==3.5.0
EOF
    
    # Create main.py with the podcast processing function
    cat > main.py << 'EOF'
import json
import os
import re
import base64
from google.cloud import language_v1
from google.cloud import texttospeech
from google.cloud import storage
from flask import Flask, request

def analyze_and_generate(request):
    """Cloud Function to analyze text and generate podcast audio"""
    
    try:
        # Initialize clients
        language_client = language_v1.LanguageServiceClient()
        tts_client = texttospeech.TextToSpeechClient()
        storage_client = storage.Client()
        
        # Get request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return {"error": "No JSON data provided"}, 400
            
        bucket_name = request_json.get('bucket_name')
        file_name = request_json.get('file_name')
        
        if not bucket_name or not file_name:
            return {"error": "bucket_name and file_name are required"}, 400
        
        # Download text content
        bucket = storage_client.bucket(bucket_name)
        try:
            blob = bucket.blob(f"input/{file_name}")
            text_content = blob.download_as_text()
        except Exception as e:
            return {"error": f"Failed to download file: {str(e)}"}, 404
        
        # Analyze sentiment and entities
        document = language_v1.Document(
            content=text_content,
            type_=language_v1.Document.Type.PLAIN_TEXT
        )
        
        # Perform sentiment analysis
        sentiment_response = language_client.analyze_sentiment(
            request={"document": document}
        )
        
        # Extract entities
        entities_response = language_client.analyze_entities(
            request={"document": document}
        )
        
        # Generate SSML based on analysis
        ssml_content = create_ssml_from_analysis(
            text_content, 
            sentiment_response.document_sentiment,
            entities_response.entities
        )
        
        # Configure voice based on sentiment
        voice_config = configure_voice_for_sentiment(
            sentiment_response.document_sentiment.score
        )
        
        # Generate speech
        synthesis_input = texttospeech.SynthesisInput(ssml=ssml_content)
        response = tts_client.synthesize_speech(
            input=synthesis_input,
            voice=voice_config,
            audio_config=texttospeech.AudioConfig(
                audio_encoding=texttospeech.AudioEncoding.MP3,
                speaking_rate=1.0,
                pitch=0.0
            )
        )
        
        # Save audio file
        audio_blob = bucket.blob(f"audio/{file_name.replace('.txt', '.mp3')}")
        audio_blob.upload_from_string(response.audio_content)
        
        # Save analysis metadata
        metadata = {
            "sentiment_score": sentiment_response.document_sentiment.score,
            "sentiment_magnitude": sentiment_response.document_sentiment.magnitude,
            "entities": [{"name": entity.name, "type": entity.type_.name, "salience": entity.salience} 
                        for entity in entities_response.entities[:5]],
            "processing_timestamp": os.environ.get('TIMESTAMP', 'unknown'),
            "audio_file": f"audio/{file_name.replace('.txt', '.mp3')}"
        }
        
        metadata_blob = bucket.blob(f"processed/{file_name.replace('.txt', '_analysis.json')}")
        metadata_blob.upload_from_string(json.dumps(metadata, indent=2))
        
        # Save SSML for review
        ssml_blob = bucket.blob(f"processed/{file_name.replace('.txt', '_enhanced.ssml')}")
        ssml_blob.upload_from_string(ssml_content)
        
        return {"status": "success", "metadata": metadata}
        
    except Exception as e:
        print(f"Error processing request: {str(e)}")
        return {"error": f"Processing failed: {str(e)}"}, 500

def create_ssml_from_analysis(text, sentiment, entities):
    """Create SSML markup based on content analysis"""
    
    # Base SSML structure
    ssml = '<speak>'
    
    # Add intro pause for podcast-style delivery
    ssml += '<break time="1s"/>'
    
    # Adjust speaking rate and emphasis based on sentiment
    if sentiment.score > 0.25:
        ssml += '<prosody rate="105%" pitch="+2st" volume="medium">'
    elif sentiment.score < -0.25:
        ssml += '<prosody rate="95%" pitch="-1st" volume="soft">'
    else:
        ssml += '<prosody rate="100%" volume="medium">'
    
    # Add pauses and emphasis for entities
    processed_text = text
    for entity in entities:
        if entity.type_.name in ['PERSON', 'ORGANIZATION', 'LOCATION'] and entity.salience > 0.1:
            emphasis_level = "strong" if entity.salience > 0.3 else "moderate"
            processed_text = processed_text.replace(
                entity.name, 
                f'<emphasis level="{emphasis_level}">{entity.name}</emphasis>'
            )
    
    # Add breathing pauses at sentence boundaries
    processed_text = re.sub(r'\.(\s+)', r'.<break time="0.5s"/>\1', processed_text)
    processed_text = re.sub(r'!(\s+)', r'!<break time="0.7s"/>\1', processed_text)
    processed_text = re.sub(r'\?(\s+)', r'?<break time="0.7s"/>\1', processed_text)
    
    # Add paragraph-level breathing
    processed_text = re.sub(r'\n\n+', '<break time="1.5s"/>', processed_text)
    
    # Enhanced transition words
    transition_words = ['however', 'therefore', 'furthermore', 'meanwhile', 'consequently']
    for word in transition_words:
        pattern = r'\b' + word + r'\b'
        replacement = f'<break time="0.4s"/>{word}'
        processed_text = re.sub(pattern, replacement, processed_text, flags=re.IGNORECASE)
    
    ssml += processed_text + '</prosody><break time="1s"/></speak>'
    return ssml

def configure_voice_for_sentiment(sentiment_score):
    """Configure voice characteristics based on sentiment"""
    
    if sentiment_score > 0.25:
        # Positive content - use more energetic voice
        return texttospeech.VoiceSelectionParams(
            language_code="en-US",
            name="en-US-Neural2-C",
            ssml_gender=texttospeech.SsmlVoiceGender.FEMALE
        )
    elif sentiment_score < -0.25:
        # Negative content - use more serious voice
        return texttospeech.VoiceSelectionParams(
            language_code="en-US",
            name="en-US-Neural2-D",
            ssml_gender=texttospeech.SsmlVoiceGender.MALE
        )
    else:
        # Neutral content - use balanced voice
        return texttospeech.VoiceSelectionParams(
            language_code="en-US",
            name="en-US-Neural2-A",
            ssml_gender=texttospeech.SsmlVoiceGender.FEMALE
        )
EOF
    
    # Deploy the function
    log_info "Deploying Cloud Function..."
    gcloud functions deploy "$FUNCTION_NAME" \
        --runtime=python311 \
        --trigger=http \
        --allow-unauthenticated \
        --memory=1024MB \
        --timeout=540s \
        --region="$REGION" \
        --entry-point=analyze_and_generate \
        --service-account="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --quiet
    
    # Clean up temporary directory
    cd - &> /dev/null
    rm -rf "$temp_dir"
    
    # Get function URL
    FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    log_success "Cloud Function deployed successfully"
    log_info "Function URL: ${FUNCTION_URL}"
    
    # Save function URL for future use
    echo "$FUNCTION_URL" > "${HOME}/podcast-function-url.txt"
}

# Upload sample content
upload_sample_content() {
    log_info "Uploading sample content for testing..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would upload sample content"
        return 0
    fi
    
    # Create local content directory
    mkdir -p "${HOME}/podcast-content/input"
    
    # Create sample article
    cat > "${HOME}/podcast-content/input/sample-article.txt" << 'EOF'
Welcome to today's technology podcast. We're exploring the fascinating world of artificial intelligence and its impact on creative industries.

Artificial intelligence has revolutionized content creation in remarkable ways. From automated writing assistants to voice synthesis, AI tools are empowering creators to produce high-quality content more efficiently than ever before.

However, this technological advancement also raises important questions about authenticity and human creativity. Many artists worry that AI might replace human ingenuity, but experts suggest that AI serves as a powerful collaborative tool rather than a replacement.

The future of creative AI lies in human-machine collaboration, where technology amplifies human creativity rather than replacing it. This partnership approach has already shown promising results in various creative fields.

Thank you for listening to today's episode. We'll continue exploring these exciting developments in our next session.
EOF
    
    # Create additional sample content
    cat > "${HOME}/podcast-content/input/tech-news.txt" << 'EOF'
Breaking news in the technology sector today! Major cloud providers are announcing significant improvements to their AI services.

Google Cloud has enhanced its Natural Language processing capabilities, while competitors are focusing on speech synthesis improvements. This competitive landscape is driving rapid innovation.

Industry experts are excited about these developments, predicting that AI-powered content creation will become mainstream within the next two years.
EOF
    
    # Upload to Cloud Storage
    gsutil cp "${HOME}/podcast-content/input/"*.txt "gs://${BUCKET_NAME}/input/"
    
    log_success "Sample content uploaded successfully"
}

# Setup monitoring
setup_monitoring() {
    log_info "Setting up monitoring and logging..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would setup monitoring"
        return 0
    fi
    
    # Create log-based metric for podcast generation
    gcloud logging metrics create podcast_generation_count \
        --description="Count of podcast generation requests" \
        --log-filter="resource.type=\"cloud_function\" AND resource.labels.function_name=\"${FUNCTION_NAME}\" AND textPayload:\"podcast generation\"" \
        --quiet || log_warning "Metric might already exist"
    
    log_success "Monitoring setup completed"
}

# Test the deployment
test_deployment() {
    log_info "Testing the deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would test deployment"
        return 0
    fi
    
    # Get function URL
    if [[ -f "${HOME}/podcast-function-url.txt" ]]; then
        FUNCTION_URL=$(cat "${HOME}/podcast-function-url.txt")
    else
        FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
            --region="$REGION" \
            --format="value(httpsTrigger.url)")
    fi
    
    # Test function with sample content
    log_info "Testing with sample content..."
    response=$(curl -s -X POST "$FUNCTION_URL" \
        -H "Content-Type: application/json" \
        -d "{\"bucket_name\": \"${BUCKET_NAME}\", \"file_name\": \"sample-article.txt\"}")
    
    if echo "$response" | grep -q "success"; then
        log_success "Function test completed successfully"
    else
        log_warning "Function test returned: $response"
    fi
    
    # Wait for processing
    sleep 15
    
    # Check for generated files
    log_info "Checking generated files..."
    audio_files=$(gsutil ls "gs://${BUCKET_NAME}/audio/" 2>/dev/null | wc -l)
    processed_files=$(gsutil ls "gs://${BUCKET_NAME}/processed/" 2>/dev/null | wc -l)
    
    if [[ $audio_files -gt 0 ]] && [[ $processed_files -gt 0 ]]; then
        log_success "Audio and metadata files generated successfully"
    else
        log_warning "Some files may not have been generated yet. Check later."
    fi
    
    log_success "Deployment test completed"
}

# Create batch processing script
create_batch_script() {
    log_info "Creating batch processing script..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create batch processing script"
        return 0
    fi
    
    # Get function URL for the script
    if [[ -f "${HOME}/podcast-function-url.txt" ]]; then
        FUNCTION_URL=$(cat "${HOME}/podcast-function-url.txt")
    else
        FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
            --region="$REGION" \
            --format="value(httpsTrigger.url)")
    fi
    
    cat > "${HOME}/batch-podcast-generator.sh" << EOF
#!/bin/bash

# Batch Podcast Generator Script
# Generated by deployment script for project: ${PROJECT_ID}

set -euo pipefail

FUNCTION_URL="${FUNCTION_URL}"
BUCKET_NAME="${BUCKET_NAME}"
BATCH_SIZE=3

echo "Starting batch podcast generation..."
echo "Function URL: \${FUNCTION_URL}"
echo "Bucket: \${BUCKET_NAME}"

# Get list of input files
FILES=\$(gsutil ls gs://\${BUCKET_NAME}/input/*.txt 2>/dev/null | sed 's|.*\/||' || echo "")

if [[ -z "\$FILES" ]]; then
    echo "No input files found in gs://\${BUCKET_NAME}/input/"
    exit 1
fi

# Process files in batches
for file in \$FILES; do
    echo "Processing: \$file"
    
    # Trigger function
    response=\$(curl -s -X POST "\$FUNCTION_URL" \\
        -H "Content-Type: application/json" \\
        -d "{\\"bucket_name\\": \\"\${BUCKET_NAME}\\", \\"file_name\\": \\"\$file\\"}")
    
    echo "Response: \$response"
    
    # Add delay to avoid rate limiting
    sleep 5
done

echo "Batch processing initiated for all files"
echo "Monitor progress with: gsutil ls gs://\${BUCKET_NAME}/audio/"
echo "View analysis results: gsutil ls gs://\${BUCKET_NAME}/processed/"
EOF
    
    chmod +x "${HOME}/batch-podcast-generator.sh"
    
    log_success "Batch processing script created at ${HOME}/batch-podcast-generator.sh"
}

# Print deployment summary
print_summary() {
    log_success "Podcast Generation Infrastructure Deployment Complete!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo "Cloud Function: ${FUNCTION_NAME}"
    echo "Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo
    echo "=== QUICK START ==="
    echo "1. Upload text files to: gs://${BUCKET_NAME}/input/"
    echo "2. Run batch processing: ${HOME}/batch-podcast-generator.sh"
    echo "3. Download audio: gsutil cp gs://${BUCKET_NAME}/audio/* ./"
    echo "4. View analysis: gsutil cat gs://${BUCKET_NAME}/processed/*_analysis.json"
    echo
    echo "=== URLS AND FILES ==="
    if [[ -f "${HOME}/podcast-function-url.txt" ]]; then
        echo "Function URL: $(cat "${HOME}/podcast-function-url.txt")"
    fi
    echo "Service Account Key: ${HOME}/podcast-key.json"
    echo "Batch Script: ${HOME}/batch-podcast-generator.sh"
    echo
    echo "=== MONITORING ==="
    echo "Cloud Console: https://console.cloud.google.com/functions/list?project=${PROJECT_ID}"
    echo "Storage Browser: https://console.cloud.google.com/storage/browser/${BUCKET_NAME}?project=${PROJECT_ID}"
    echo "Logs: https://console.cloud.google.com/logs?project=${PROJECT_ID}"
    echo
    echo "=== ESTIMATED COSTS ==="
    echo "- Text-to-Speech: ~\$4 per 1M characters"
    echo "- Natural Language API: ~\$1 per 1K units"
    echo "- Cloud Functions: ~\$0.40 per 1M invocations"
    echo "- Cloud Storage: ~\$0.02 per GB per month"
    echo
    log_warning "Remember to run ./destroy.sh when finished to avoid ongoing charges"
}

# Main execution
main() {
    log_info "Starting deployment process..."
    
    check_prerequisites
    setup_project
    enable_apis
    create_service_account
    create_storage_bucket
    deploy_cloud_function
    upload_sample_content
    setup_monitoring
    test_deployment
    create_batch_script
    print_summary
    
    log_success "Deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "This was a dry run. No resources were actually created."
    fi
}

# Handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code: $exit_code"
        log_info "You may need to clean up partially created resources manually"
        log_info "Or re-run the script to complete the deployment"
    fi
    exit $exit_code
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"