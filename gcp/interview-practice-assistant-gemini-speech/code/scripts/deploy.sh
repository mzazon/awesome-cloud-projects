#!/bin/bash

# Interview Practice Assistant using Gemini and Speech-to-Text - Deployment Script
# This script deploys the complete infrastructure for the interview practice assistant
# on Google Cloud Platform using Cloud Functions, Vertex AI, and Speech-to-Text API

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Default configuration
DEFAULT_PROJECT_PREFIX="interview-practice"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Configuration variables (can be overridden by environment variables)
PROJECT_PREFIX="${PROJECT_PREFIX:-$DEFAULT_PROJECT_PREFIX}"
REGION="${REGION:-$DEFAULT_REGION}"
ZONE="${ZONE:-$DEFAULT_ZONE}"
DRY_RUN="${DRY_RUN:-false}"
FORCE_DEPLOY="${FORCE_DEPLOY:-false}"

# Generate unique suffix if not provided
if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
fi

# Resource names
PROJECT_ID="${PROJECT_PREFIX}-$(date +%s)"
BUCKET_NAME="interview-audio-${RANDOM_SUFFIX}"
FUNCTION_PREFIX="interview-assistant"
SERVICE_ACCOUNT_NAME="interview-assistant"

# Function to display help
show_help() {
    cat << EOF
Interview Practice Assistant Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run           Show what would be deployed without making changes
    -f, --force             Force deployment even if resources exist
    -p, --project-prefix    Project name prefix (default: interview-practice)
    -r, --region            GCP region (default: us-central1)
    -s, --suffix            Random suffix for resource names

ENVIRONMENT VARIABLES:
    PROJECT_PREFIX          Override project prefix
    REGION                  Override deployment region
    ZONE                    Override deployment zone
    RANDOM_SUFFIX           Override random suffix
    DRY_RUN                 Set to 'true' for dry run
    FORCE_DEPLOY            Set to 'true' to force deployment

EXAMPLES:
    $0                                          # Deploy with defaults
    $0 --dry-run                               # Show what would be deployed
    $0 --project-prefix my-interview --region us-west1
    REGION=europe-west1 $0                     # Deploy to Europe

EOF
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        error "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if openssl is installed (for random generation)
    if ! command -v openssl &> /dev/null; then
        warn "OpenSSL not found. Using date-based random suffix."
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check for active project (if not creating new one)
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$current_project" ]]; then
        warn "No active project set. A new project will be created."
    else
        info "Current active project: $current_project"
    fi
    
    # Check billing account availability
    local billing_accounts
    billing_accounts=$(gcloud billing accounts list --format="value(name)" 2>/dev/null | wc -l)
    if [[ $billing_accounts -eq 0 ]]; then
        error "No billing accounts found. Please ensure you have access to a billing account."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to validate configuration
validate_config() {
    log "Validating configuration..."
    
    # Validate region
    if ! gcloud compute regions describe "$REGION" &> /dev/null; then
        error "Invalid region: $REGION"
        exit 1
    fi
    
    # Validate zone
    if ! gcloud compute zones describe "$ZONE" &> /dev/null; then
        error "Invalid zone: $ZONE"
        exit 1
    fi
    
    # Validate project ID format
    if [[ ! "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        error "Invalid project ID format: $PROJECT_ID"
        error "Project ID must be 6-30 characters, start with lowercase letter, and contain only lowercase letters, numbers, and hyphens"
        exit 1
    fi
    
    log "Configuration validation completed successfully"
}

# Function to create and configure project
setup_project() {
    log "Setting up Google Cloud project..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create project: $PROJECT_ID"
        info "[DRY RUN] Would enable required APIs"
        info "[DRY RUN] Would set up billing"
        return
    fi
    
    # Create project
    if gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        if [[ "$FORCE_DEPLOY" == "true" ]]; then
            warn "Project $PROJECT_ID already exists. Continuing due to --force flag."
        else
            error "Project $PROJECT_ID already exists. Use --force to proceed anyway."
            exit 1
        fi
    else
        log "Creating project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" --name="Interview Practice Assistant"
        
        # Link billing account
        local billing_account
        billing_account=$(gcloud billing accounts list --format="value(name)" | head -1)
        if [[ -n "$billing_account" ]]; then
            gcloud billing projects link "$PROJECT_ID" --billing-account="$billing_account"
            log "Linked billing account to project"
        else
            warn "No billing account found. Please link manually: gcloud billing projects link $PROJECT_ID --billing-account=ACCOUNT_ID"
        fi
    fi
    
    # Set as active project
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set functions/region "$REGION"
    
    log "Project setup completed: $PROJECT_ID"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "speech.googleapis.com"
        "aiplatform.googleapis.com"
        "storage.googleapis.com"
        "run.googleapis.com"
        "cloudbuild.googleapis.com"
        "iam.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would enable APIs: ${apis[*]}"
        return
    fi
    
    for api in "${apis[@]}"; do
        log "Enabling API: $api"
        gcloud services enable "$api"
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log "All required APIs enabled successfully"
}

# Function to create Cloud Storage bucket
create_storage() {
    log "Creating Cloud Storage bucket for audio files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create bucket: gs://$BUCKET_NAME"
        info "[DRY RUN] Would set lifecycle policy for 30-day cleanup"
        return
    fi
    
    # Create bucket
    if gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
        if [[ "$FORCE_DEPLOY" == "true" ]]; then
            warn "Bucket gs://$BUCKET_NAME already exists. Continuing due to --force flag."
        else
            error "Bucket gs://$BUCKET_NAME already exists. Use --force to proceed anyway."
            exit 1
        fi
    else
        gsutil mb -p "$PROJECT_ID" \
            -c STANDARD \
            -l "$REGION" \
            "gs://$BUCKET_NAME"
        
        # Set lifecycle policy for cost optimization
        cat > /tmp/lifecycle.json << EOF
{
  "rule": [
    {
      "condition": {"age": 30},
      "action": {"type": "Delete"}
    }
  ]
}
EOF
        
        gsutil lifecycle set /tmp/lifecycle.json "gs://$BUCKET_NAME"
        rm -f /tmp/lifecycle.json
        
        log "Storage bucket created: gs://$BUCKET_NAME"
    fi
}

# Function to create service account and set IAM permissions
setup_iam() {
    log "Setting up IAM service account and permissions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create service account: $SERVICE_ACCOUNT_NAME"
        info "[DRY RUN] Would grant Speech API, Vertex AI, and Storage permissions"
        return
    fi
    
    local service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Create service account if it doesn't exist
    if ! gcloud iam service-accounts describe "$service_account_email" &> /dev/null; then
        gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
            --display-name="Interview Assistant Service Account" \
            --description="Service account for interview practice functions"
        
        log "Created service account: $service_account_email"
    else
        warn "Service account already exists: $service_account_email"
    fi
    
    # Grant necessary permissions with least privilege principle
    local roles=(
        "roles/speech.client"
        "roles/aiplatform.user"
        "roles/storage.objectAdmin"
    )
    
    for role in "${roles[@]}"; do
        log "Granting role: $role"
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$service_account_email" \
            --role="$role"
    done
    
    log "IAM setup completed successfully"
}

# Function to deploy Cloud Functions
deploy_functions() {
    log "Deploying Cloud Functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would deploy 3 Cloud Functions:"
        info "[DRY RUN]   - ${FUNCTION_PREFIX}-speech (Speech-to-Text processing)"
        info "[DRY RUN]   - ${FUNCTION_PREFIX}-analysis (Gemini analysis)"
        info "[DRY RUN]   - ${FUNCTION_PREFIX}-orchestrate (Workflow orchestration)"
        return
    fi
    
    local service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    local temp_dir="/tmp/interview-functions-$$"
    
    # Create temporary directory for function code
    mkdir -p "$temp_dir"
    
    # Deploy Speech-to-Text function
    log "Deploying Speech-to-Text function..."
    mkdir -p "$temp_dir/speech-function"
    
    cat > "$temp_dir/speech-function/requirements.txt" << 'EOF'
google-cloud-speech==2.23.0
google-cloud-storage==2.12.0
functions-framework==3.5.0
EOF
    
    cat > "$temp_dir/speech-function/main.py" << 'EOF'
import json
from google.cloud import speech
from google.cloud import storage
import functions_framework

@functions_framework.http
def transcribe_audio(request):
    """Transcribe audio file using Speech-to-Text API."""
    try:
        request_json = request.get_json()
        bucket_name = request_json['bucket']
        file_name = request_json['file']
        
        # Initialize clients
        speech_client = speech.SpeechClient()
        storage_client = storage.Client()
        
        # Get audio file from Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        audio_content = blob.download_as_bytes()
        
        # Configure speech recognition with optimized settings
        audio = speech.RecognitionAudio(content=audio_content)
        config = speech.RecognitionConfig(
            encoding=speech.RecognitionConfig.AudioEncoding.WEBM_OPUS,
            sample_rate_hertz=48000,
            language_code="en-US",
            enable_automatic_punctuation=True,
            enable_spoken_punctuation=True,
            enable_word_confidence=True,
            enable_word_time_offsets=True,
            model="latest_long",
            use_enhanced=True
        )
        
        # Perform transcription
        response = speech_client.recognize(config=config, audio=audio)
        
        # Process results with detailed confidence tracking
        transcription = ""
        confidence_scores = []
        word_details = []
        
        for result in response.results:
            transcription += result.alternatives[0].transcript + " "
            confidence_scores.append(result.alternatives[0].confidence)
            
            # Extract word-level details for analysis
            for word in result.alternatives[0].words:
                word_details.append({
                    'word': word.word,
                    'confidence': word.confidence,
                    'start_time': word.start_time.total_seconds(),
                    'end_time': word.end_time.total_seconds()
                })
        
        return {
            'transcription': transcription.strip(),
            'confidence': sum(confidence_scores) / len(confidence_scores) if confidence_scores else 0,
            'word_details': word_details,
            'status': 'success'
        }
        
    except Exception as e:
        return {'error': str(e), 'status': 'error'}
EOF
    
    (cd "$temp_dir/speech-function" && \
     gcloud functions deploy "${FUNCTION_PREFIX}-speech" \
         --runtime python311 \
         --trigger-http \
         --allow-unauthenticated \
         --source . \
         --entry-point transcribe_audio \
         --memory 512MB \
         --timeout 120s \
         --service-account="$service_account_email")
    
    # Deploy Gemini analysis function
    log "Deploying Gemini analysis function..."
    mkdir -p "$temp_dir/analysis-function"
    
    cat > "$temp_dir/analysis-function/requirements.txt" << 'EOF'
google-cloud-aiplatform==1.42.0
functions-framework==3.5.0
EOF
    
    cat > "$temp_dir/analysis-function/main.py" << 'EOF'
import json
import vertexai
from vertexai.generative_models import GenerativeModel
import functions_framework
import os

@functions_framework.http
def analyze_interview_response(request):
    """Analyze interview response using Gemini."""
    try:
        request_json = request.get_json()
        transcription = request_json['transcription']
        question = request_json.get('question', 'Tell me about yourself')
        confidence = request_json.get('confidence', 0.0)
        
        # Initialize Vertex AI with project context
        project_id = os.environ.get('GCP_PROJECT')
        location = os.environ.get('REGION', 'us-central1')
        vertexai.init(project=project_id, location=location)
        
        # Configure Gemini model with safety settings
        model = GenerativeModel("gemini-1.5-pro")
        
        # Create comprehensive analysis prompt
        prompt = f"""
        You are an expert interview coach with 15+ years of experience. 
        Analyze this interview response and provide detailed, actionable feedback.
        
        Interview Question: {question}
        
        Candidate Response: {transcription}
        Speech Confidence Score: {confidence:.2f}/1.0
        
        Please provide analysis in this structured format:
        
        **Content Analysis (Weight: 40%)**
        - Content Quality Score: X/10
        - Key Strengths: [List 2-3 specific strengths]
        - Areas for Improvement: [List 2-3 specific areas]
        - Relevance to Question: [How well the response addressed the question]
        
        **Communication Skills (Weight: 30%)**
        - Clarity and Articulation: [Based on confidence score and content]
        - Structure and Organization: [Logical flow assessment]
        - Professional Language: [Word choice and tone evaluation]
        - Confidence Indicators: [Verbal confidence markers]
        
        **Interview Best Practices (Weight: 30%)**
        - STAR Method Usage: [Situation, Task, Action, Result framework]
        - Quantifiable Results: [Use of metrics and specific examples]
        - Company/Role Alignment: [Relevance to typical job requirements]
        - Follow-up Potential: [Opens discussion for next questions]
        
        **Specific Recommendations**
        1. [Most important improvement with example]
        2. [Communication enhancement with technique]
        3. [Content strengthening with framework]
        
        **Sample Improved Response**
        [Provide a 2-3 sentence example of how to enhance the response]
        
        **Overall Interview Score: X/10**
        
        Keep feedback constructive, specific, and encouraging. Focus on actionable improvements.
        """
        
        # Generate analysis with safety settings
        response = model.generate_content(
            prompt,
            generation_config={
                "temperature": 0.3,
                "top_p": 0.8,
                "max_output_tokens": 2048
            }
        )
        
        return {
            'analysis': response.text,
            'question': question,
            'transcription': transcription,
            'confidence_score': confidence,
            'status': 'success'
        }
        
    except Exception as e:
        return {'error': str(e), 'status': 'error'}
EOF
    
    (cd "$temp_dir/analysis-function" && \
     gcloud functions deploy "${FUNCTION_PREFIX}-analysis" \
         --runtime python311 \
         --trigger-http \
         --allow-unauthenticated \
         --source . \
         --entry-point analyze_interview_response \
         --memory 1GB \
         --timeout 120s \
         --set-env-vars "GCP_PROJECT=$PROJECT_ID,REGION=$REGION" \
         --service-account="$service_account_email")
    
    # Deploy orchestration function
    log "Deploying orchestration function..."
    mkdir -p "$temp_dir/orchestration-function"
    
    cat > "$temp_dir/orchestration-function/requirements.txt" << 'EOF'
google-cloud-storage==2.12.0
requests==2.31.0
functions-framework==3.5.0
EOF
    
    cat > "$temp_dir/orchestration-function/main.py" << 'EOF'
import json
import requests
from google.cloud import storage
import functions_framework
import os
import time

@functions_framework.http
def orchestrate_interview_analysis(request):
    """Orchestrate the complete interview analysis workflow."""
    try:
        request_json = request.get_json()
        bucket_name = request_json['bucket']
        file_name = request_json['file']
        question = request_json.get('question', 'Tell me about yourself')
        
        # Validate inputs
        if not bucket_name or not file_name:
            return {'error': 'Missing required fields: bucket and file', 'status': 'error'}
        
        # Get function URLs dynamically
        region = os.environ.get('GCLOUD_REGION', 'us-central1')
        project = os.environ.get('GCLOUD_PROJECT')
        
        speech_url = f"https://{region}-{project}.cloudfunctions.net/interview-assistant-speech"
        analysis_url = f"https://{region}-{project}.cloudfunctions.net/interview-assistant-analysis"
        
        # Step 1: Transcribe audio with retry logic
        speech_payload = {
            'bucket': bucket_name,
            'file': file_name
        }
        
        max_retries = 3
        for attempt in range(max_retries):
            try:
                speech_response = requests.post(
                    speech_url, 
                    json=speech_payload,
                    timeout=120
                )
                speech_result = speech_response.json()
                
                if speech_result.get('status') == 'success':
                    break
                elif attempt == max_retries - 1:
                    return {
                        'error': 'Transcription failed after retries', 
                        'details': speech_result
                    }
                time.sleep(2 ** attempt)  # Exponential backoff
                
            except requests.exceptions.RequestException as e:
                if attempt == max_retries - 1:
                    return {'error': f'Network error in transcription: {str(e)}'}
                time.sleep(2 ** attempt)
        
        # Step 2: Analyze with Gemini
        analysis_payload = {
            'transcription': speech_result['transcription'],
            'question': question,
            'confidence': speech_result.get('confidence', 0.0)
        }
        
        try:
            analysis_response = requests.post(
                analysis_url, 
                json=analysis_payload,
                timeout=120
            )
            analysis_result = analysis_response.json()
            
            if analysis_result.get('status') != 'success':
                return {
                    'error': 'Analysis failed', 
                    'details': analysis_result
                }
            
        except requests.exceptions.RequestException as e:
            return {'error': f'Network error in analysis: {str(e)}'}
        
        # Return complete results with metadata
        return {
            'transcription': speech_result['transcription'],
            'confidence': speech_result['confidence'],
            'analysis': analysis_result['analysis'],
            'question': question,
            'processing_time': time.time(),
            'status': 'complete'
        }
        
    except Exception as e:
        return {'error': f'Orchestration error: {str(e)}', 'status': 'error'}
EOF
    
    (cd "$temp_dir/orchestration-function" && \
     gcloud functions deploy "${FUNCTION_PREFIX}-orchestrate" \
         --runtime python311 \
         --trigger-http \
         --allow-unauthenticated \
         --source . \
         --entry-point orchestrate_interview_analysis \
         --memory 256MB \
         --timeout 300s \
         --set-env-vars "GCLOUD_REGION=$REGION,GCLOUD_PROJECT=$PROJECT_ID" \
         --service-account="$service_account_email")
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    log "All Cloud Functions deployed successfully"
}

# Function to create sample data
create_sample_data() {
    log "Creating sample interview questions dataset..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would upload sample interview questions to gs://$BUCKET_NAME/"
        return
    fi
    
    # Create comprehensive questions file
    cat > /tmp/interview_questions.json << 'EOF'
{
  "behavioral": [
    "Tell me about a time when you faced a significant challenge at work. How did you handle it?",
    "Describe a situation where you had to work with a difficult team member.",
    "Give me an example of when you went above and beyond in your role.",
    "Tell me about a time when you made a mistake. How did you handle it?",
    "Describe a situation where you had to learn something quickly.",
    "Tell me about a time when you had to convince someone to see your point of view."
  ],
  "technical": [
    "Walk me through your approach to solving a complex technical problem.",
    "How do you stay current with new technologies in your field?",
    "Describe your experience with [relevant technology/framework].",
    "What's your process for debugging a challenging issue?",
    "How do you handle code reviews and feedback?",
    "Explain a technical concept to someone without a technical background."
  ],
  "general": [
    "Tell me about yourself.",
    "Why are you interested in this position?",
    "What are your greatest strengths and weaknesses?",
    "Where do you see yourself in five years?",
    "Why are you leaving your current position?",
    "What motivates you in your work?"
  ],
  "leadership": [
    "Describe your leadership style.",
    "Tell me about a time when you had to lead a project.",
    "How do you handle conflict within your team?",
    "Describe a time when you had to make a difficult decision.",
    "How do you motivate team members?",
    "Tell me about a time when you received criticism from your manager."
  ]
}
EOF
    
    # Upload questions to Cloud Storage
    gsutil cp /tmp/interview_questions.json "gs://$BUCKET_NAME/"
    rm -f /tmp/interview_questions.json
    
    log "Sample interview questions uploaded successfully"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would verify all functions are deployed and accessible"
        return
    fi
    
    # Check functions are deployed
    local functions_count
    functions_count=$(gcloud functions list --filter="name:${FUNCTION_PREFIX}" --format="value(name)" | wc -l)
    
    if [[ $functions_count -ne 3 ]]; then
        error "Expected 3 functions, found $functions_count. Deployment may have failed."
        return 1
    fi
    
    # Check bucket exists
    if ! gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
        error "Storage bucket not found. Deployment may have failed."
        return 1
    fi
    
    # Check service account exists
    local service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    if ! gcloud iam service-accounts describe "$service_account_email" &> /dev/null; then
        error "Service account not found. Deployment may have failed."
        return 1
    fi
    
    log "Deployment verification completed successfully"
    return 0
}

# Function to display deployment summary
show_summary() {
    log "Deployment Summary"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "Project ID: $PROJECT_ID"
    info "Region: $REGION"
    info "Storage Bucket: gs://$BUCKET_NAME"
    info "Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo ""
    info "Deployed Functions:"
    info "  • Speech-to-Text: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_PREFIX}-speech"
    info "  • Gemini Analysis: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_PREFIX}-analysis"
    info "  • Orchestration: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_PREFIX}-orchestrate"
    echo ""
    info "Next Steps:"
    info "  1. Upload audio files to gs://$BUCKET_NAME for testing"
    info "  2. Use the orchestration endpoint for complete interview analysis"
    info "  3. Review the detailed feedback and recommendations"
    echo ""
    info "Estimated Monthly Cost: \$8-15 for moderate usage"
    info "Resources will auto-cleanup after 30 days to optimize costs"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info ""
        info "This was a DRY RUN - no actual resources were created"
        info "Run without --dry-run to deploy the infrastructure"
    fi
}

# Function to handle script interruption
cleanup_on_interrupt() {
    error "Deployment interrupted by user"
    warn "Some resources may have been partially created"
    warn "Run the destroy script to clean up any created resources"
    exit 130
}

# Main deployment function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -f|--force)
                FORCE_DEPLOY="true"
                shift
                ;;
            -p|--project-prefix)
                PROJECT_PREFIX="$2"
                PROJECT_ID="${PROJECT_PREFIX}-$(date +%s)"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                ZONE="${REGION}-a"
                shift 2
                ;;
            -s|--suffix)
                RANDOM_SUFFIX="$2"
                BUCKET_NAME="interview-audio-${RANDOM_SUFFIX}"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Set up interrupt handler
    trap cleanup_on_interrupt SIGINT SIGTERM
    
    # Display banner
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│                     Interview Practice Assistant Deployment                 │"
    echo "│                           Google Cloud Platform                             │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN MODE - No resources will be created"
        echo ""
    fi
    
    # Display configuration
    info "Configuration:"
    info "  Project ID: $PROJECT_ID"
    info "  Region: $REGION"
    info "  Zone: $ZONE"
    info "  Bucket Name: $BUCKET_NAME"
    info "  Random Suffix: $RANDOM_SUFFIX"
    echo ""
    
    # Execute deployment steps
    check_prerequisites
    validate_config
    setup_project
    enable_apis
    create_storage
    setup_iam
    deploy_functions
    create_sample_data
    
    if verify_deployment; then
        show_summary
        log "🎉 Interview Practice Assistant deployed successfully!"
    else
        error "Deployment verification failed. Please check the logs above."
        exit 1
    fi
}

# Run main function
main "$@"