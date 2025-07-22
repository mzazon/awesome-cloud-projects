#!/bin/bash

# Multi-Language Content Localization Workflows Deployment Script
# This script deploys the complete infrastructure for automated content translation
# using Google Cloud Translation Advanced, Cloud Scheduler, and Cloud Storage

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# Error handler
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Cleaning up partial deployment..."
    # Note: This will be called if deployment fails
    if [[ -n "${PROJECT_ID:-}" ]]; then
        log_info "Run './destroy.sh' to clean up any created resources"
    fi
}

# Set cleanup trap
trap cleanup_on_error ERR

# Banner
cat << 'EOF'
╔══════════════════════════════════════════════════════════════════════════════╗
║                Multi-Language Content Localization Deployment               ║
║                                                                              ║
║   This script deploys automated content translation infrastructure using:   ║
║   • Google Cloud Translation Advanced API                                   ║
║   • Cloud Scheduler for batch processing                                    ║
║   • Cloud Storage for content management                                    ║
║   • Cloud Functions for serverless processing                               ║
║   • Pub/Sub for event-driven architecture                                   ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "No active gcloud authentication found. Run 'gcloud auth login'"
    fi
    
    # Check if curl is available for API calls
    if ! command -v curl &> /dev/null; then
        error_exit "curl is required but not installed"
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is required but not installed"
    fi
    
    log_success "Prerequisites check completed"
}

# Function to prompt for configuration
get_configuration() {
    log_info "Setting up deployment configuration..."
    
    # Get or create project ID
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_info "Current gcloud project: $(gcloud config get-value project 2>/dev/null || echo 'None set')"
        read -p "Enter Google Cloud Project ID (or press Enter to create new): " PROJECT_ID
        
        if [[ -z "$PROJECT_ID" ]]; then
            PROJECT_ID="translation-workflow-$(date +%s)"
            log_info "Creating new project: $PROJECT_ID"
            
            # Check if billing account is available
            BILLING_ACCOUNT=$(gcloud billing accounts list --filter="open:true" --format="value(name)" --limit=1 2>/dev/null || echo "")
            if [[ -z "$BILLING_ACCOUNT" ]]; then
                error_exit "No active billing account found. Please set up billing in Google Cloud Console"
            fi
            
            # Create project
            gcloud projects create "$PROJECT_ID" --name="Translation Workflow" || error_exit "Failed to create project"
            gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT" || error_exit "Failed to link billing account"
        fi
    fi
    
    # Set default region if not provided
    if [[ -z "${REGION:-}" ]]; then
        REGION="us-central1"
        log_info "Using default region: $REGION"
    fi
    
    # Set zone
    ZONE="${REGION}-a"
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Resource names
    export PROJECT_ID
    export REGION
    export ZONE
    export BUCKET_SOURCE="source-content-${RANDOM_SUFFIX}"
    export BUCKET_TRANSLATED="translated-content-${RANDOM_SUFFIX}"
    export TOPIC_NAME="translation-workflow-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="translation-processor-${RANDOM_SUFFIX}"
    export SCHEDULER_JOB="batch-translation-job"
    export MONITOR_JOB="translation-monitor"
    
    # Save configuration for destroy script
    cat > "${SCRIPT_DIR}/deployment.env" << EOF
# Deployment configuration - DO NOT EDIT
PROJECT_ID="$PROJECT_ID"
REGION="$REGION"
ZONE="$ZONE"
BUCKET_SOURCE="$BUCKET_SOURCE"
BUCKET_TRANSLATED="$BUCKET_TRANSLATED"
TOPIC_NAME="$TOPIC_NAME"
FUNCTION_NAME="$FUNCTION_NAME"
SCHEDULER_JOB="$SCHEDULER_JOB"
MONITOR_JOB="$MONITOR_JOB"
DEPLOYMENT_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    log_success "Configuration completed"
    log_info "Project: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Resources will be prefixed with: $RANDOM_SUFFIX"
}

# Function to set up Google Cloud project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Set project and region
    gcloud config set project "$PROJECT_ID" || error_exit "Failed to set project"
    gcloud config set compute/region "$REGION" || error_exit "Failed to set region"
    gcloud config set compute/zone "$ZONE" || error_exit "Failed to set zone"
    
    log_success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "translate.googleapis.com"
        "storage.googleapis.com"
        "pubsub.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" || error_exit "Failed to enable $api"
    done
    
    log_success "All APIs enabled successfully"
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
}

# Function to create Cloud Storage buckets
create_storage() {
    log_info "Creating Cloud Storage infrastructure..."
    
    # Create source content bucket
    log_info "Creating source content bucket..."
    gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_SOURCE" || error_exit "Failed to create source bucket"
    
    # Create translated content bucket
    log_info "Creating translated content bucket..."
    gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_TRANSLATED" || error_exit "Failed to create translated bucket"
    
    # Enable versioning for content tracking
    log_info "Enabling versioning on buckets..."
    gsutil versioning set on "gs://$BUCKET_SOURCE" || error_exit "Failed to enable versioning on source bucket"
    gsutil versioning set on "gs://$BUCKET_TRANSLATED" || error_exit "Failed to enable versioning on translated bucket"
    
    # Set up lifecycle policies for cost optimization
    cat > "${SCRIPT_DIR}/lifecycle.json" << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 30}
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 90}
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "ARCHIVE"},
        "condition": {"age": 365}
      }
    ]
  }
}
EOF
    
    gsutil lifecycle set "${SCRIPT_DIR}/lifecycle.json" "gs://$BUCKET_SOURCE" || log_warning "Failed to set lifecycle policy on source bucket"
    gsutil lifecycle set "${SCRIPT_DIR}/lifecycle.json" "gs://$BUCKET_TRANSLATED" || log_warning "Failed to set lifecycle policy on translated bucket"
    
    log_success "Cloud Storage infrastructure created"
}

# Function to set up Pub/Sub messaging
setup_pubsub() {
    log_info "Setting up Pub/Sub messaging infrastructure..."
    
    # Create Pub/Sub topic for translation events
    log_info "Creating Pub/Sub topic..."
    gcloud pubsub topics create "$TOPIC_NAME" || error_exit "Failed to create Pub/Sub topic"
    
    # Create subscription for the Cloud Function
    log_info "Creating Pub/Sub subscription..."
    gcloud pubsub subscriptions create "${TOPIC_NAME}-sub" \
        --topic="$TOPIC_NAME" \
        --ack-deadline=600 \
        --expiration-period=never || error_exit "Failed to create Pub/Sub subscription"
    
    # Verify topic and subscription
    if gcloud pubsub topics describe "$TOPIC_NAME" >/dev/null 2>&1; then
        log_success "Pub/Sub topic created successfully"
    else
        error_exit "Failed to verify Pub/Sub topic creation"
    fi
    
    if gcloud pubsub subscriptions describe "${TOPIC_NAME}-sub" >/dev/null 2>&1; then
        log_success "Pub/Sub subscription created successfully"
    else
        error_exit "Failed to verify Pub/Sub subscription creation"
    fi
}

# Function to deploy Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function for translation processing..."
    
    # Create function directory
    local function_dir="${SCRIPT_DIR}/function-source"
    mkdir -p "$function_dir"
    cd "$function_dir"
    
    # Create main function file
    cat > main.py << 'EOF'
import json
import base64
from google.cloud import translate_v3
from google.cloud import storage
from google.cloud import pubsub_v1
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def translate_document(event, context):
    """Cloud Function triggered by Pub/Sub to translate documents."""
    
    try:
        # Initialize clients
        translate_client = translate_v3.TranslationServiceClient()
        storage_client = storage.Client()
        
        # Parse Pub/Sub message
        if 'data' in event:
            pubsub_message = base64.b64decode(event['data']).decode('utf-8')
            message_data = json.loads(pubsub_message)
        else:
            logger.error("No data in Pub/Sub message")
            return "No data in message"
        
        # Handle different message types
        if message_data.get('type') == 'monitor':
            logger.info("Health check received")
            return "Health check OK"
        elif message_data.get('type') == 'batch':
            logger.info("Batch processing trigger received")
            return "Batch processing initiated"
        
        # Extract file information for file processing
        if 'bucketId' not in message_data or 'objectId' not in message_data:
            logger.warning("Missing bucket or object information in message")
            return "Missing file information"
        
        bucket_name = message_data['bucketId']
        file_name = message_data['objectId']
        
        # Skip processing for non-text files and system files
        if not file_name.endswith('.txt') or file_name.startswith('.'):
            logger.info(f"Skipping non-text file: {file_name}")
            return f"Skipped {file_name}"
        
        # Define target languages
        target_languages = ['es', 'fr', 'de', 'it', 'pt']
        project_id = os.environ['GCP_PROJECT']
        location = 'us-central1'
        
        # Download source file
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        if not blob.exists():
            logger.error(f"File {file_name} does not exist in bucket {bucket_name}")
            return f"File not found: {file_name}"
        
        content = blob.download_as_text()
        logger.info(f"Downloaded file {file_name}, size: {len(content)} characters")
        
        # Detect source language
        parent = f"projects/{project_id}/locations/{location}"
        response = translate_client.detect_language(
            parent=parent,
            content=content
        )
        
        source_language = response.languages[0].language_code
        logger.info(f"Detected language: {source_language}")
        
        # Translate to each target language
        translated_count = 0
        for target_lang in target_languages:
            if target_lang != source_language:
                try:
                    translation = translate_client.translate_text(
                        parent=parent,
                        contents=[content],
                        source_language_code=source_language,
                        target_language_code=target_lang
                    )
                    
                    # Save translated content
                    translated_bucket = storage_client.bucket(
                        os.environ['TRANSLATED_BUCKET']
                    )
                    translated_blob_name = f"{target_lang}/{file_name}"
                    translated_blob = translated_bucket.blob(translated_blob_name)
                    translated_blob.upload_from_string(
                        translation.translations[0].translated_text,
                        content_type='text/plain'
                    )
                    
                    translated_count += 1
                    logger.info(f"Translated {file_name} to {target_lang}")
                    
                except Exception as e:
                    logger.error(f"Failed to translate {file_name} to {target_lang}: {str(e)}")
        
        result = f"Successfully translated {file_name} to {translated_count} languages"
        logger.info(result)
        return result
        
    except Exception as e:
        error_msg = f"Error processing translation: {str(e)}"
        logger.error(error_msg)
        raise e
EOF
    
    # Create requirements file
    cat > requirements.txt << 'EOF'
google-cloud-translate==3.15.0
google-cloud-storage==2.10.0
google-cloud-pubsub==2.18.0
functions-framework==3.4.0
EOF
    
    # Deploy the Cloud Function
    log_info "Deploying Cloud Function..."
    gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python39 \
        --trigger-topic "$TOPIC_NAME" \
        --entry-point translate_document \
        --memory 512MB \
        --timeout 540s \
        --set-env-vars="TRANSLATED_BUCKET=$BUCKET_TRANSLATED" \
        --region="$REGION" || error_exit "Failed to deploy Cloud Function"
    
    cd "$SCRIPT_DIR"
    rm -rf "$function_dir"
    
    log_success "Cloud Function deployed successfully"
}

# Function to configure Cloud Storage notifications
setup_notifications() {
    log_info "Configuring Cloud Storage notifications..."
    
    # Create notification for source bucket
    gsutil notification create -t "$TOPIC_NAME" \
        -f json \
        -e OBJECT_FINALIZE \
        "gs://$BUCKET_SOURCE" || error_exit "Failed to create storage notification"
    
    # Verify notification
    local notifications
    notifications=$(gsutil notification list "gs://$BUCKET_SOURCE" | grep "$TOPIC_NAME" | wc -l)
    if [[ "$notifications" -gt 0 ]]; then
        log_success "Storage notifications configured successfully"
    else
        error_exit "Failed to verify storage notification"
    fi
}

# Function to set up Cloud Scheduler
setup_scheduler() {
    log_info "Setting up Cloud Scheduler for batch processing..."
    
    # Create batch translation job
    log_info "Creating batch translation job..."
    gcloud scheduler jobs create pubsub "$SCHEDULER_JOB" \
        --location="$REGION" \
        --schedule="0 2 * * *" \
        --topic="$TOPIC_NAME" \
        --message-body='{"type":"batch","action":"process_pending"}' \
        --description="Daily batch translation processing" || error_exit "Failed to create batch scheduler job"
    
    # Create monitoring job
    log_info "Creating monitoring job..."
    gcloud scheduler jobs create pubsub "$MONITOR_JOB" \
        --location="$REGION" \
        --schedule="*/30 * * * *" \
        --topic="$TOPIC_NAME" \
        --message-body='{"type":"monitor","action":"health_check"}' \
        --description="Translation system monitoring" || error_exit "Failed to create monitor scheduler job"
    
    # List configured jobs to verify
    local job_count
    job_count=$(gcloud scheduler jobs list --location="$REGION" --filter="name:($SCHEDULER_JOB OR $MONITOR_JOB)" --format="value(name)" | wc -l)
    if [[ "$job_count" -eq 2 ]]; then
        log_success "Cloud Scheduler jobs created successfully"
    else
        error_exit "Failed to verify Cloud Scheduler job creation"
    fi
}

# Function to create sample content
create_sample_content() {
    log_info "Creating sample content for testing..."
    
    # Create test document
    cat > "${SCRIPT_DIR}/test-document.txt" << 'EOF'
Welcome to our enterprise platform. Please complete user authentication to access advanced features.

Our system provides:
- Real-time data processing
- Advanced analytics capabilities
- Secure user management
- Multi-language support

For technical support, please contact our team through the support portal.
EOF
    
    # Upload to source bucket
    gsutil cp "${SCRIPT_DIR}/test-document.txt" "gs://$BUCKET_SOURCE/" || error_exit "Failed to upload test document"
    
    # Create sample translation dataset
    cat > "${SCRIPT_DIR}/sample-dataset.tsv" << 'EOF'
Welcome to our platform	Bienvenidos a nuestra plataforma
User authentication required	Autenticación de usuario requerida
Data processing completed	Procesamiento de datos completado
System maintenance scheduled	Mantenimiento del sistema programado
Performance metrics available	Métricas de rendimiento disponibles
EOF
    
    gsutil cp "${SCRIPT_DIR}/sample-dataset.tsv" "gs://$BUCKET_SOURCE/datasets/" || log_warning "Failed to upload sample dataset"
    
    log_success "Sample content created and uploaded"
}

# Function to set up monitoring and logging
setup_monitoring() {
    log_info "Setting up monitoring and logging..."
    
    # Create log sink for translation audit
    gcloud logging sinks create translation-audit \
        "storage.googleapis.com/$BUCKET_TRANSLATED/logs/" \
        --log-filter="resource.type=\"cloud_function\" AND resource.labels.function_name=\"$FUNCTION_NAME\"" || log_warning "Failed to create log sink"
    
    # Create monitoring dashboard configuration
    cat > "${SCRIPT_DIR}/monitoring-config.json" << EOF
{
  "displayName": "Translation Workflow Monitoring",
  "conditions": [
    {
      "displayName": "High Translation Error Rate",
      "conditionThreshold": {
        "filter": "resource.type=\"cloud_function\" AND resource.label.function_name=\"$FUNCTION_NAME\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0.1,
        "duration": "300s"
      }
    }
  ],
  "enabled": true
}
EOF
    
    log_success "Monitoring configuration created"
}

# Function to run deployment validation
validate_deployment() {
    log_info "Validating deployment..."
    
    # Wait for function to be ready
    log_info "Waiting for Cloud Function to be ready..."
    sleep 60
    
    # Check if buckets exist
    if gsutil ls -b "gs://$BUCKET_SOURCE" >/dev/null 2>&1 && gsutil ls -b "gs://$BUCKET_TRANSLATED" >/dev/null 2>&1; then
        log_success "Storage buckets are accessible"
    else
        error_exit "Storage buckets validation failed"
    fi
    
    # Check if Pub/Sub topic exists
    if gcloud pubsub topics describe "$TOPIC_NAME" >/dev/null 2>&1; then
        log_success "Pub/Sub topic is accessible"
    else
        error_exit "Pub/Sub topic validation failed"
    fi
    
    # Check if Cloud Function exists
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" >/dev/null 2>&1; then
        log_success "Cloud Function is deployed"
    else
        error_exit "Cloud Function validation failed"
    fi
    
    # Check if scheduler jobs exist
    local job_count
    job_count=$(gcloud scheduler jobs list --location="$REGION" --filter="name:($SCHEDULER_JOB OR $MONITOR_JOB)" --format="value(name)" | wc -l)
    if [[ "$job_count" -eq 2 ]]; then
        log_success "Scheduler jobs are configured"
    else
        error_exit "Scheduler jobs validation failed"
    fi
    
    # Wait for processing and check if translation occurred
    log_info "Waiting for automatic translation to complete..."
    sleep 90
    
    # Check for translated files
    local translated_files
    translated_files=$(gsutil ls "gs://$BUCKET_TRANSLATED/**" 2>/dev/null | wc -l || echo "0")
    if [[ "$translated_files" -gt 0 ]]; then
        log_success "Translation workflow is working (found $translated_files translated files)"
    else
        log_warning "No translated files found yet. The system may need more time to process."
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
show_summary() {
    log_success "Deployment completed successfully!"
    
    cat << EOF

╔══════════════════════════════════════════════════════════════════════════════╗
║                            DEPLOYMENT SUMMARY                               ║
╚══════════════════════════════════════════════════════════════════════════════╝

🚀 PROJECT DETAILS:
   Project ID: $PROJECT_ID
   Region: $REGION
   Zone: $ZONE

📦 CREATED RESOURCES:
   ✅ Source Storage Bucket: gs://$BUCKET_SOURCE
   ✅ Translated Storage Bucket: gs://$BUCKET_TRANSLATED
   ✅ Pub/Sub Topic: $TOPIC_NAME
   ✅ Cloud Function: $FUNCTION_NAME
   ✅ Batch Scheduler Job: $SCHEDULER_JOB (runs daily at 2 AM)
   ✅ Monitor Scheduler Job: $MONITOR_JOB (runs every 30 minutes)

🔧 NEXT STEPS:
   1. Upload text files to: gs://$BUCKET_SOURCE
   2. Check translations in: gs://$BUCKET_TRANSLATED
   3. Monitor logs: gcloud logging read 'resource.type="cloud_function"'
   4. View scheduler jobs: gcloud scheduler jobs list --location=$REGION

💡 TESTING:
   A sample test document has been uploaded and should be automatically translated.
   Check for results with: gsutil ls -la gs://$BUCKET_TRANSLATED/

🧹 CLEANUP:
   To remove all resources: ./destroy.sh

📊 ESTIMATED COSTS:
   - Cloud Storage: ~\$0.02/GB/month
   - Cloud Functions: ~\$0.40/million requests
   - Translation API: ~\$20/million characters
   - Cloud Scheduler: \$0.10/job/month

⚠️  NOTE: Translation API charges apply per character translated.
    Monitor usage in the Google Cloud Console billing section.

EOF

    # Save deployment info
    echo "Deployment completed: $(date)" >> "$LOG_FILE"
    echo "Project: $PROJECT_ID" >> "$LOG_FILE"
    echo "Source bucket: gs://$BUCKET_SOURCE" >> "$LOG_FILE"
    echo "Translated bucket: gs://$BUCKET_TRANSLATED" >> "$LOG_FILE"
}

# Main deployment function
main() {
    # Initialize log file
    echo "Deployment started: $(date)" > "$LOG_FILE"
    
    log_info "Starting Multi-Language Content Localization deployment..."
    
    # Run deployment steps
    check_prerequisites
    get_configuration
    setup_project
    enable_apis
    create_storage
    setup_pubsub
    deploy_function
    setup_notifications
    setup_scheduler
    create_sample_content
    setup_monitoring
    validate_deployment
    
    # Clean up temporary files
    rm -f "${SCRIPT_DIR}/lifecycle.json"
    rm -f "${SCRIPT_DIR}/test-document.txt"
    rm -f "${SCRIPT_DIR}/sample-dataset.tsv"
    
    show_summary
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"