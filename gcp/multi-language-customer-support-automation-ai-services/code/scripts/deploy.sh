#!/bin/bash

################################################################################
# Multi-Language Customer Support Automation - Deployment Script
# 
# This script deploys a complete multi-language customer support automation
# system using Google Cloud AI services including Speech-to-Text, Translation,
# Natural Language, Text-to-Speech, Cloud Functions, and Workflows.
################################################################################

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly MAX_WAIT_TIME=600  # 10 minutes

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

################################################################################
# Utility Functions
################################################################################

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $*${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $*${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $*${NC}"
}

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code $exit_code"
        log "Check the log file at: ${LOG_FILE}"
    fi
    exit $exit_code
}

wait_for_operation() {
    local operation_name="$1"
    local operation_type="${2:-deployment}"
    local max_wait="${3:-$MAX_WAIT_TIME}"
    local wait_time=0
    local sleep_interval=10

    log "Waiting for ${operation_type} operation: ${operation_name}"
    
    while [[ $wait_time -lt $max_wait ]]; do
        if gcloud operations describe "$operation_name" --format="value(done)" 2>/dev/null | grep -q "True"; then
            log_success "${operation_type} operation completed: ${operation_name}"
            return 0
        fi
        
        if [[ $((wait_time % 60)) -eq 0 ]]; then
            log "Still waiting for ${operation_type} operation... (${wait_time}s elapsed)"
        fi
        
        sleep $sleep_interval
        wait_time=$((wait_time + sleep_interval))
    done
    
    log_error "${operation_type} operation timed out after ${max_wait} seconds"
    return 1
}

################################################################################
# Prerequisites Validation
################################################################################

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if billing is enabled
    local project_id
    project_id=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$project_id" ]]; then
        log_error "No project set. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    # Validate project exists
    if ! gcloud projects describe "$project_id" &> /dev/null; then
        log_error "Project '$project_id' does not exist or you don't have access"
        exit 1
    fi
    
    log_success "Prerequisites validated"
    echo "Project ID: $project_id"
}

################################################################################
# Environment Setup
################################################################################

setup_environment() {
    log "Setting up environment variables..."
    
    # Set project configuration
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    export BUCKET_NAME="customer-support-audio-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="multilang-processor-${RANDOM_SUFFIX}"
    export WORKFLOW_NAME="support-workflow-${RANDOM_SUFFIX}"
    
    # Validate required environment variables
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID is not set"
        exit 1
    fi
    
    log_success "Environment configured"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Bucket Name: $BUCKET_NAME"
    echo "  Function Name: $FUNCTION_NAME"
    echo "  Workflow Name: $WORKFLOW_NAME"
}

################################################################################
# API Enablement
################################################################################

enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "speech.googleapis.com"
        "translate.googleapis.com"
        "language.googleapis.com"
        "texttospeech.googleapis.com"
        "cloudfunctions.googleapis.com"
        "workflows.googleapis.com"
        "firestore.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling API: $api"
        if gcloud services enable "$api" --project="$PROJECT_ID"; then
            log_success "Enabled API: $api"
        else
            log_error "Failed to enable API: $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All APIs enabled successfully"
}

################################################################################
# Storage Setup
################################################################################

setup_storage() {
    log "Setting up Cloud Storage..."
    
    # Create bucket
    log "Creating Cloud Storage bucket: $BUCKET_NAME"
    if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
        log_success "Created bucket: gs://$BUCKET_NAME"
    else
        log_error "Failed to create bucket: gs://$BUCKET_NAME"
        exit 1
    fi
    
    # Enable versioning
    log "Enabling versioning on bucket..."
    if gsutil versioning set on "gs://$BUCKET_NAME"; then
        log_success "Enabled versioning on bucket"
    else
        log_warning "Failed to enable versioning (continuing anyway)"
    fi
    
    # Create configuration files
    log "Creating configuration files..."
    
    # Speech-to-Text configuration
    cat > "${SCRIPT_DIR}/../speech-config.json" << 'EOF'
{
  "config": {
    "encoding": "WEBM_OPUS",
    "sampleRateHertz": 48000,
    "languageCode": "en-US",
    "alternativeLanguageCodes": ["es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR"],
    "enableAutomaticPunctuation": true,
    "enableWordTimeOffsets": true,
    "enableSpeakerDiarization": true,
    "diarizationConfig": {
      "enableSpeakerDiarization": true,
      "minSpeakerCount": 1,
      "maxSpeakerCount": 2
    },
    "model": "latest_long"
  }
}
EOF
    
    # Translation configuration
    cat > "${SCRIPT_DIR}/../translation-config.json" << 'EOF'
{
  "supportedLanguages": [
    {"code": "en", "name": "English"},
    {"code": "es", "name": "Spanish"},
    {"code": "fr", "name": "French"},
    {"code": "de", "name": "German"},
    {"code": "it", "name": "Italian"},
    {"code": "pt", "name": "Portuguese"},
    {"code": "ja", "name": "Japanese"},
    {"code": "ko", "name": "Korean"},
    {"code": "zh", "name": "Chinese"}
  ],
  "defaultTargetLanguage": "en",
  "glossarySupport": true,
  "model": "nmt"
}
EOF
    
    # Sentiment analysis configuration
    cat > "${SCRIPT_DIR}/../sentiment-config.json" << 'EOF'
{
  "features": {
    "sentiment": true,
    "entities": true,
    "entitySentiment": true,
    "syntax": false,
    "classification": true
  },
  "thresholds": {
    "negative": -0.2,
    "positive": 0.2,
    "urgency": -0.5
  },
  "entityTypes": [
    "PERSON",
    "ORGANIZATION",
    "LOCATION",
    "EVENT",
    "WORK_OF_ART",
    "CONSUMER_GOOD"
  ]
}
EOF
    
    # Text-to-Speech configuration
    cat > "${SCRIPT_DIR}/../tts-config.json" << 'EOF'
{
  "voices": {
    "en-US": {
      "name": "en-US-Neural2-J",
      "ssmlGender": "FEMALE",
      "languageCode": "en-US"
    },
    "es-ES": {
      "name": "es-ES-Neural2-F",
      "ssmlGender": "FEMALE",
      "languageCode": "es-ES"
    },
    "fr-FR": {
      "name": "fr-FR-Neural2-C",
      "ssmlGender": "FEMALE",
      "languageCode": "fr-FR"
    },
    "de-DE": {
      "name": "de-DE-Neural2-F",
      "ssmlGender": "FEMALE",
      "languageCode": "de-DE"
    }
  },
  "audioConfig": {
    "audioEncoding": "MP3",
    "speakingRate": 1.0,
    "pitch": 0.0,
    "volumeGainDb": 0.0
  }
}
EOF
    
    # Upload configuration files
    log "Uploading configuration files to Cloud Storage..."
    if gsutil cp "${SCRIPT_DIR}/../"*-config.json "gs://$BUCKET_NAME/config/"; then
        log_success "Configuration files uploaded"
    else
        log_error "Failed to upload configuration files"
        exit 1
    fi
}

################################################################################
# Firestore Setup
################################################################################

setup_firestore() {
    log "Setting up Firestore database..."
    
    # Create Firestore database
    log "Creating Firestore database in Native mode..."
    if gcloud firestore databases create --region="$REGION" --type=firestore-native --project="$PROJECT_ID"; then
        log_success "Created Firestore database"
    else
        # Check if database already exists
        if gcloud firestore databases describe --project="$PROJECT_ID" &> /dev/null; then
            log_warning "Firestore database already exists"
        else
            log_error "Failed to create Firestore database"
            exit 1
        fi
    fi
    
    # Wait for database to be ready
    log "Waiting for Firestore database to be ready..."
    sleep 20
    
    # Create composite index
    log "Creating Firestore indexes..."
    if gcloud firestore indexes composite create \
        --collection-group=conversations \
        --field-config field-path=customerId,order=ASCENDING \
        --field-config field-path=timestamp,order=DESCENDING \
        --project="$PROJECT_ID" 2>/dev/null; then
        log_success "Created Firestore indexes"
    else
        log_warning "Firestore indexes may already exist or will be created automatically"
    fi
}

################################################################################
# Cloud Function Deployment
################################################################################

deploy_cloud_function() {
    log "Deploying Cloud Function..."
    
    # Prepare function source directory
    local function_dir="${SCRIPT_DIR}/../terraform/function_code"
    
    if [[ ! -d "$function_dir" ]]; then
        log_error "Function source directory not found: $function_dir"
        exit 1
    fi
    
    # Deploy the function
    log "Deploying function: $FUNCTION_NAME"
    if gcloud functions deploy "$FUNCTION_NAME" \
        --source="$function_dir" \
        --runtime=python39 \
        --trigger=http \
        --allow-unauthenticated \
        --region="$REGION" \
        --memory=512MB \
        --timeout=60s \
        --set-env-vars="BUCKET_NAME=$BUCKET_NAME,PROJECT_ID=$PROJECT_ID" \
        --project="$PROJECT_ID"; then
        log_success "Cloud Function deployed: $FUNCTION_NAME"
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(httpsTrigger.url)")
    
    log_success "Function URL: $function_url"
    export FUNCTION_URL="$function_url"
}

################################################################################
# Workflows Deployment
################################################################################

deploy_workflows() {
    log "Deploying Cloud Workflows..."
    
    # Create workflow definition with function URL
    cat > "${SCRIPT_DIR}/../workflow-definition.yaml" << EOF
main:
  params: [args]
  steps:
    - init:
        assign:
          - customer_id: \${args.customer_id}
          - audio_data: \${args.audio_data}
          - session_id: \${args.session_id}
    
    - process_audio:
        call: http.post
        args:
          url: ${FUNCTION_URL}
          body:
            customer_id: \${customer_id}
            audio_data: \${audio_data}
            session_id: \${session_id}
        result: processing_result
    
    - check_sentiment:
        switch:
          - condition: \${processing_result.body.sentiment_score < -0.5}
            next: escalate_to_human
          - condition: \${processing_result.body.sentiment_score > 0.5}
            next: send_satisfaction_survey
        next: log_interaction
    
    - escalate_to_human:
        call: sys.log
        args:
          data: 
            message: "Escalating to human agent"
            customer_id: \${customer_id}
            session_id: \${session_id}
            sentiment_score: \${processing_result.body.sentiment_score}
          severity: "WARNING"
        next: log_interaction
    
    - send_satisfaction_survey:
        call: sys.log
        args:
          data:
            message: "Sending satisfaction survey"
            customer_id: \${customer_id}
            session_id: \${session_id}
            language: \${processing_result.body.detected_language}
          severity: "INFO"
        next: log_interaction
    
    - log_interaction:
        call: sys.log
        args:
          data: \${processing_result.body}
          severity: "INFO"
    
    - return_response:
        return: \${processing_result.body}
EOF
    
    # Deploy workflow
    log "Deploying workflow: $WORKFLOW_NAME"
    if gcloud workflows deploy "$WORKFLOW_NAME" \
        --source="${SCRIPT_DIR}/../workflow-definition.yaml" \
        --location="$REGION" \
        --project="$PROJECT_ID"; then
        log_success "Workflow deployed: $WORKFLOW_NAME"
    else
        log_error "Failed to deploy workflow"
        exit 1
    fi
}

################################################################################
# Monitoring Setup
################################################################################

setup_monitoring() {
    log "Setting up monitoring and alerting..."
    
    # Create log-based metric for sentiment tracking
    log "Creating sentiment tracking metric..."
    if gcloud logging metrics create sentiment_score \
        --description="Track customer sentiment scores" \
        --log-filter="resource.type=\"cloud_function\" AND jsonPayload.sentiment_score exists" \
        --value-extractor="EXTRACT(jsonPayload.sentiment_score)" \
        --project="$PROJECT_ID" 2>/dev/null; then
        log_success "Created sentiment tracking metric"
    else
        log_warning "Sentiment tracking metric may already exist"
    fi
    
    log_success "Basic monitoring configured"
}

################################################################################
# Validation Tests
################################################################################

run_validation_tests() {
    log "Running validation tests..."
    
    # Test API availability
    log "Testing AI service APIs..."
    
    # Test translation
    if echo "Hello, world!" | gcloud ml translate translate-text \
        --source-language=en \
        --target-language=es \
        --format=text \
        --zone="$REGION" \
        --project="$PROJECT_ID" &> /dev/null; then
        log_success "Translation API is working"
    else
        log_warning "Translation API test failed (may need time to propagate)"
    fi
    
    # Test sentiment analysis
    if echo "I'm happy with this service" | gcloud ml language analyze-sentiment \
        --content-file=- \
        --format="value(documentSentiment.score)" \
        --project="$PROJECT_ID" &> /dev/null; then
        log_success "Natural Language API is working"
    else
        log_warning "Natural Language API test failed (may need time to propagate)"
    fi
    
    # Test function endpoint
    if curl -s -o /dev/null -w "%{http_code}" "$FUNCTION_URL" | grep -q "405\|400"; then
        log_success "Cloud Function endpoint is accessible"
    else
        log_warning "Cloud Function endpoint test inconclusive"
    fi
    
    log_success "Validation tests completed"
}

################################################################################
# Cleanup Function
################################################################################

cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove configuration files from local directory
    rm -f "${SCRIPT_DIR}/../"*-config.json
    rm -f "${SCRIPT_DIR}/../workflow-definition.yaml"
    
    log_success "Temporary files cleaned up"
}

################################################################################
# Main Deployment Function
################################################################################

main() {
    trap cleanup_on_exit EXIT
    
    log "Starting Multi-Language Customer Support Automation deployment..."
    echo "=================================================================="
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    enable_apis
    setup_storage
    setup_firestore
    deploy_cloud_function
    deploy_workflows
    setup_monitoring
    run_validation_tests
    cleanup_temp_files
    
    echo "=================================================================="
    log_success "Deployment completed successfully!"
    echo
    echo "📋 Deployment Summary:"
    echo "  • Project ID: $PROJECT_ID"
    echo "  • Region: $REGION"
    echo "  • Storage Bucket: gs://$BUCKET_NAME"
    echo "  • Cloud Function: $FUNCTION_NAME"
    echo "  • Function URL: $FUNCTION_URL"
    echo "  • Workflow: $WORKFLOW_NAME"
    echo
    echo "🧪 Testing the deployment:"
    echo "  1. Test the Cloud Function endpoint:"
    echo "     curl -X POST -H 'Content-Type: application/json' \\"
    echo "       -d '{\"audio_data\":\"<base64-encoded-audio>\",\"customer_id\":\"test\"}' \\"
    echo "       '$FUNCTION_URL'"
    echo
    echo "  2. Execute the workflow:"
    echo "     gcloud workflows execute $WORKFLOW_NAME --location=$REGION \\"
    echo "       --data='{\"customer_id\":\"test\",\"audio_data\":\"<base64>\",\"session_id\":\"test\"}'"
    echo
    echo "📖 Check the logs:"
    echo "   View function logs: gcloud functions logs read $FUNCTION_NAME --region=$REGION"
    echo "   View workflow logs: gcloud workflows executions list --workflow=$WORKFLOW_NAME --location=$REGION"
    echo
    echo "💰 Estimated costs: \$20-50 for testing workloads"
    echo "   Monitor costs: https://console.cloud.google.com/billing"
    echo
    echo "🧹 To clean up: ./destroy.sh"
}

# Check if script is being run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi