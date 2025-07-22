#!/bin/bash

# Document Processing Workflows with Document AI and Cloud Run - Deployment Script
# This script deploys the complete infrastructure for automated document processing
# using Google Cloud Document AI, Cloud Run, Pub/Sub, and Cloud Storage

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

# Script metadata
SCRIPT_NAME="GCP Document Processing Deployment"
SCRIPT_VERSION="1.0"
DEPLOYMENT_START_TIME=$(date)

log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"
log_info "Deployment started at: ${DEPLOYMENT_START_TIME}"

# Configuration with defaults that can be overridden
PROJECT_ID="${PROJECT_ID:-doc-processing-$(date +%s)}"
REGION="${REGION:-us-central1}"
BUCKET_NAME="${BUCKET_NAME:-document-uploads-${PROJECT_ID}}"
PUBSUB_TOPIC="${PUBSUB_TOPIC:-document-processing}"
PUBSUB_SUBSCRIPTION="${PUBSUB_SUBSCRIPTION:-document-worker}"
CLOUDRUN_SERVICE="${CLOUDRUN_SERVICE:-document-processor}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-document-processor-sa}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
PROCESSOR_DISPLAY_NAME="${PROCESSOR_DISPLAY_NAME:-form-parser-${RANDOM_SUFFIX}}"

# Deployment state tracking
DEPLOYMENT_STATE_FILE="/tmp/gcp-docai-deployment-${PROJECT_ID}.state"
CREATED_RESOURCES=""

# Function to add resource to tracking
track_resource() {
    local resource_type="$1"
    local resource_name="$2"
    echo "${resource_type}:${resource_name}" >> "${DEPLOYMENT_STATE_FILE}"
    CREATED_RESOURCES="${CREATED_RESOURCES}\n- ${resource_type}: ${resource_name}"
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up created resources..."
    if [[ -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        while IFS=':' read -r resource_type resource_name; do
            case "${resource_type}" in
                "cloudrun")
                    gcloud run services delete "${resource_name}" --region="${REGION}" --quiet 2>/dev/null || true
                    ;;
                "pubsub_subscription")
                    gcloud pubsub subscriptions delete "${resource_name}" --quiet 2>/dev/null || true
                    ;;
                "pubsub_topic")
                    gcloud pubsub topics delete "${resource_name}" --quiet 2>/dev/null || true
                    ;;
                "storage_bucket")
                    gsutil -m rm -r "gs://${resource_name}" 2>/dev/null || true
                    ;;
                "documentai_processor")
                    gcloud documentai processors delete "${resource_name}" --location="${REGION}" --quiet 2>/dev/null || true
                    ;;
                "service_account")
                    gcloud iam service-accounts delete "${resource_name}@${PROJECT_ID}.iam.gserviceaccount.com" --quiet 2>/dev/null || true
                    ;;
            esac
        done < "${DEPLOYMENT_STATE_FILE}"
    fi
    rm -f "${DEPLOYMENT_STATE_FILE}"
    exit 1
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Required for generating random suffixes."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check if billing is enabled for the project
    if ! gcloud billing projects describe "${PROJECT_ID}" &>/dev/null; then
        log_warning "Unable to verify billing status for project ${PROJECT_ID}"
        log_warning "Please ensure billing is enabled for this project"
    fi
    
    log_success "Prerequisites check completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "documentai.googleapis.com"
        "run.googleapis.com"
        "pubsub.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
        "iam.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --project="${PROJECT_ID}"; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
}

# Function to create Document AI processor
create_documentai_processor() {
    log_info "Creating Document AI processor..."
    
    # Create Form Parser processor
    if gcloud documentai processors create \
        --location="${REGION}" \
        --display-name="${PROCESSOR_DISPLAY_NAME}" \
        --type=FORM_PARSER_PROCESSOR \
        --project="${PROJECT_ID}"; then
        
        # Wait for processor to be created
        sleep 10
        
        # Get processor ID
        PROCESSOR_ID=$(gcloud documentai processors list \
            --location="${REGION}" \
            --filter="displayName:${PROCESSOR_DISPLAY_NAME}" \
            --format="value(name)" \
            --project="${PROJECT_ID}" | cut -d'/' -f6)
        
        if [[ -z "${PROCESSOR_ID}" ]]; then
            log_error "Failed to retrieve processor ID"
            exit 1
        fi
        
        track_resource "documentai_processor" "${PROCESSOR_ID}"
        export PROCESSOR_ID
        log_success "Document AI processor created with ID: ${PROCESSOR_ID}"
    else
        log_error "Failed to create Document AI processor"
        exit 1
    fi
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists"
        return 0
    fi
    
    # Create regional storage bucket
    if gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}"; then
        
        # Enable object versioning
        gsutil versioning set on "gs://${BUCKET_NAME}"
        
        # Set appropriate permissions
        gsutil iam ch allUsers:objectViewer "gs://${BUCKET_NAME}" 2>/dev/null || true
        
        track_resource "storage_bucket" "${BUCKET_NAME}"
        log_success "Storage bucket created: gs://${BUCKET_NAME}"
    else
        log_error "Failed to create storage bucket"
        exit 1
    fi
}

# Function to create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Pub/Sub topic and subscription..."
    
    # Create Pub/Sub topic
    if gcloud pubsub topics create "${PUBSUB_TOPIC}" --project="${PROJECT_ID}"; then
        track_resource "pubsub_topic" "${PUBSUB_TOPIC}"
        log_success "Created Pub/Sub topic: ${PUBSUB_TOPIC}"
    else
        log_error "Failed to create Pub/Sub topic"
        exit 1
    fi
    
    # Create subscription
    if gcloud pubsub subscriptions create "${PUBSUB_SUBSCRIPTION}" \
        --topic="${PUBSUB_TOPIC}" \
        --ack-deadline=600 \
        --message-retention-duration=7d \
        --project="${PROJECT_ID}"; then
        
        track_resource "pubsub_subscription" "${PUBSUB_SUBSCRIPTION}"
        log_success "Created Pub/Sub subscription: ${PUBSUB_SUBSCRIPTION}"
    else
        log_error "Failed to create Pub/Sub subscription"
        exit 1
    fi
}

# Function to configure storage notification
configure_storage_notification() {
    log_info "Configuring storage bucket notification..."
    
    # Create notification configuration
    if gsutil notification create -t "${PUBSUB_TOPIC}" \
        -e OBJECT_FINALIZE \
        "gs://${BUCKET_NAME}"; then
        
        log_success "Storage notification configured"
    else
        log_error "Failed to configure storage notification"
        exit 1
    fi
}

# Function to create service account
create_service_account() {
    log_info "Creating service account..."
    
    # Create service account
    if gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
        --description="Service account for document processing" \
        --display-name="Document Processor Service Account" \
        --project="${PROJECT_ID}"; then
        
        track_resource "service_account" "${SERVICE_ACCOUNT_NAME}"
        log_success "Created service account: ${SERVICE_ACCOUNT_NAME}"
    else
        log_error "Failed to create service account"
        exit 1
    fi
    
    # Grant necessary permissions
    local permissions=(
        "roles/documentai.apiUser"
        "roles/storage.objectAdmin"
        "roles/pubsub.subscriber"
        "roles/logging.logWriter"
        "roles/monitoring.metricWriter"
    )
    
    for permission in "${permissions[@]}"; do
        log_info "Granting ${permission} to service account..."
        if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="${permission}"; then
            log_success "Granted ${permission}"
        else
            log_error "Failed to grant ${permission}"
            exit 1
        fi
    done
}

# Function to create Cloud Run application code
create_application_code() {
    log_info "Creating Cloud Run application code..."
    
    # Create temporary directory for source code
    local app_dir="/tmp/document-processor-${RANDOM_SUFFIX}"
    mkdir -p "${app_dir}"
    cd "${app_dir}"
    
    # Create main.py
    cat > main.py << 'EOF'
import os
import json
import base64
import logging
from google.cloud import documentai_v1 as documentai
from google.cloud import storage
from flask import Flask, request

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

@app.route('/', methods=['POST'])
def process_document():
    """Process documents triggered by Pub/Sub messages."""
    try:
        # Parse Pub/Sub message
        envelope = request.get_json()
        if not envelope:
            logger.error('No JSON data received')
            return 'Bad Request: No JSON data', 400
        
        pubsub_message = envelope.get('message', {})
        data = pubsub_message.get('data', '')
        
        if not data:
            logger.error('No data in Pub/Sub message')
            return 'Bad Request: No data', 400
        
        # Decode the message data
        try:
            message_data = json.loads(base64.b64decode(data).decode('utf-8'))
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            logger.error(f'Failed to decode message data: {e}')
            return f'Bad Request: Invalid message data - {e}', 400
        
        bucket_name = message_data.get('bucketId')
        object_name = message_data.get('objectId')
        
        if not bucket_name or not object_name:
            logger.error('Missing bucket or object info in message')
            return 'Bad Request: Missing bucket or object info', 400
        
        # Skip processing of result files
        if object_name.startswith('processed/'):
            logger.info(f'Skipping processing of result file: {object_name}')
            return 'OK: Skipped result file', 200
        
        # Process document with Document AI
        result = process_with_documentai(bucket_name, object_name)
        
        # Log successful processing
        logger.info(f'Successfully processed: {object_name}')
        logger.info(f'Extracted {len(result.get("entities", []))} entities')
        
        return 'OK', 200
    
    except Exception as e:
        logger.error(f'Error processing document: {str(e)}', exc_info=True)
        return f'Internal Server Error: {str(e)}', 500

def process_with_documentai(bucket_name, object_name):
    """Process document using Document AI."""
    try:
        # Initialize Document AI client
        client = documentai.DocumentProcessorServiceClient()
        
        # Configure processor
        project_id = os.environ.get('PROJECT_ID')
        location = os.environ.get('REGION', 'us-central1')
        processor_id = os.environ.get('PROCESSOR_ID')
        
        if not all([project_id, processor_id]):
            raise ValueError('Missing required environment variables: PROJECT_ID, PROCESSOR_ID')
        
        processor_name = f"projects/{project_id}/locations/{location}/processors/{processor_id}"
        
        # Download document from Cloud Storage
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(object_name)
        
        if not blob.exists():
            raise FileNotFoundError(f'Object {object_name} not found in bucket {bucket_name}')
        
        document_content = blob.download_as_bytes()
        
        # Determine MIME type based on file extension
        file_extension = object_name.lower().split('.')[-1]
        mime_type_map = {
            'pdf': 'application/pdf',
            'png': 'image/png',
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'tiff': 'image/tiff',
            'tif': 'image/tiff',
            'gif': 'image/gif',
            'bmp': 'image/bmp'
        }
        mime_type = mime_type_map.get(file_extension, 'application/pdf')
        
        # Process document
        raw_document = documentai.RawDocument(content=document_content, mime_type=mime_type)
        request_obj = documentai.ProcessRequest(name=processor_name, raw_document=raw_document)
        
        result = client.process_document(request=request_obj)
        
        # Extract structured data
        extracted_data = {
            'source_file': object_name,
            'processor_id': processor_id,
            'text': result.document.text,
            'entities': [],
            'tables': [],
            'confidence_scores': {
                'overall': getattr(result.document, 'confidence', 0.0)
            },
            'processing_timestamp': str(datetime.utcnow()),
            'pages_processed': len(result.document.pages)
        }
        
        # Process form fields if available
        if result.document.pages:
            for page in result.document.pages:
                if hasattr(page, 'form_fields'):
                    for form_field in page.form_fields:
                        if form_field.field_name and form_field.field_value:
                            field_name = ""
                            field_value = ""
                            field_confidence = 0.0
                            
                            # Extract field name
                            if form_field.field_name.text_anchor:
                                field_name = get_text_from_anchor(result.document.text, form_field.field_name.text_anchor)
                            
                            # Extract field value
                            if form_field.field_value.text_anchor:
                                field_value = get_text_from_anchor(result.document.text, form_field.field_value.text_anchor)
                            
                            # Get confidence score
                            if hasattr(form_field.field_value, 'confidence'):
                                field_confidence = form_field.field_value.confidence
                            
                            if field_name and field_value:
                                extracted_data['entities'].append({
                                    'name': field_name.strip(),
                                    'value': field_value.strip(),
                                    'confidence': field_confidence
                                })
        
        # Process tables if available
        if result.document.pages:
            for page in result.document.pages:
                if hasattr(page, 'tables'):
                    for table in page.tables:
                        table_data = extract_table_data(result.document.text, table)
                        if table_data:
                            extracted_data['tables'].append(table_data)
        
        # Save results to Cloud Storage
        results_blob = bucket.blob(f"processed/{object_name}.json")
        results_blob.upload_from_string(
            json.dumps(extracted_data, indent=2, ensure_ascii=False),
            content_type='application/json'
        )
        
        logger.info(f'Results saved to gs://{bucket_name}/processed/{object_name}.json')
        
        return extracted_data
    
    except Exception as e:
        logger.error(f'Error in Document AI processing: {str(e)}', exc_info=True)
        raise

def get_text_from_anchor(document_text, text_anchor):
    """Extract text from a text anchor."""
    if not text_anchor.text_segments:
        return ""
    
    text_segments = []
    for segment in text_anchor.text_segments:
        start_index = int(segment.start_index) if segment.start_index else 0
        end_index = int(segment.end_index) if segment.end_index else len(document_text)
        text_segments.append(document_text[start_index:end_index])
    
    return "".join(text_segments)

def extract_table_data(document_text, table):
    """Extract structured data from a table."""
    try:
        table_data = {
            'rows': [],
            'headers': []
        }
        
        if not hasattr(table, 'header_rows') or not hasattr(table, 'body_rows'):
            return None
        
        # Extract headers
        for header_row in table.header_rows:
            header_cells = []
            for cell in header_row.cells:
                cell_text = get_text_from_anchor(document_text, cell.layout.text_anchor)
                header_cells.append(cell_text.strip())
            table_data['headers'].append(header_cells)
        
        # Extract body rows
        for body_row in table.body_rows:
            row_cells = []
            for cell in body_row.cells:
                cell_text = get_text_from_anchor(document_text, cell.layout.text_anchor)
                row_cells.append(cell_text.strip())
            table_data['rows'].append(row_cells)
        
        return table_data if table_data['headers'] or table_data['rows'] else None
    
    except Exception as e:
        logger.error(f'Error extracting table data: {str(e)}')
        return None

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint."""
    return {'status': 'healthy', 'service': 'document-processor'}, 200

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-documentai==2.20.1
google-cloud-storage==2.10.0
google-cloud-pubsub==2.18.0
flask==2.3.3
gunicorn==21.2.0
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

# Create non-root user
RUN useradd --create-home --shell /bin/bash app \
    && chown -R app:app /app
USER app

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:$PORT/health || exit 1

# Run the application
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 600 --worker-class sync main:app
EOF
    
    log_success "Application code created in ${app_dir}"
    echo "${app_dir}"
}

# Function to deploy Cloud Run service
deploy_cloudrun_service() {
    log_info "Deploying Cloud Run service..."
    
    # Create application code
    local app_dir
    app_dir=$(create_application_code)
    cd "${app_dir}"
    
    # Deploy the Cloud Run service
    if gcloud run deploy "${CLOUDRUN_SERVICE}" \
        --source . \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --set-env-vars "PROJECT_ID=${PROJECT_ID}" \
        --set-env-vars "REGION=${REGION}" \
        --set-env-vars "PROCESSOR_ID=${PROCESSOR_ID}" \
        --memory 1Gi \
        --cpu 1 \
        --timeout 600 \
        --max-instances 10 \
        --min-instances 0 \
        --concurrency 10 \
        --service-account="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --project="${PROJECT_ID}"; then
        
        # Get the service URL
        SERVICE_URL=$(gcloud run services describe "${CLOUDRUN_SERVICE}" \
            --region="${REGION}" \
            --format="value(status.url)" \
            --project="${PROJECT_ID}")
        
        if [[ -z "${SERVICE_URL}" ]]; then
            log_error "Failed to retrieve service URL"
            exit 1
        fi
        
        track_resource "cloudrun" "${CLOUDRUN_SERVICE}"
        export SERVICE_URL
        log_success "Cloud Run service deployed at: ${SERVICE_URL}"
    else
        log_error "Failed to deploy Cloud Run service"
        exit 1
    fi
    
    # Clean up temporary directory
    cd /
    rm -rf "${app_dir}"
}

# Function to configure Pub/Sub push subscription
configure_push_subscription() {
    log_info "Configuring Pub/Sub push subscription..."
    
    # Update subscription to push messages to Cloud Run
    if gcloud pubsub subscriptions modify-push-config "${PUBSUB_SUBSCRIPTION}" \
        --push-endpoint="${SERVICE_URL}" \
        --project="${PROJECT_ID}"; then
        
        log_success "Pub/Sub subscription configured to push to Cloud Run"
    else
        log_error "Failed to configure push subscription"
        exit 1
    fi
}

# Function to run deployment validation
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Document AI processor
    log_info "Verifying Document AI processor..."
    if gcloud documentai processors describe "${PROCESSOR_ID}" \
        --location="${REGION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        log_success "Document AI processor is active"
    else
        log_error "Document AI processor validation failed"
        return 1
    fi
    
    # Check Cloud Storage bucket
    log_info "Verifying Cloud Storage bucket..."
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_success "Cloud Storage bucket is accessible"
    else
        log_error "Cloud Storage bucket validation failed"
        return 1
    fi
    
    # Check Pub/Sub resources
    log_info "Verifying Pub/Sub resources..."
    if gcloud pubsub topics describe "${PUBSUB_TOPIC}" --project="${PROJECT_ID}" &>/dev/null && \
       gcloud pubsub subscriptions describe "${PUBSUB_SUBSCRIPTION}" --project="${PROJECT_ID}" &>/dev/null; then
        log_success "Pub/Sub resources are active"
    else
        log_error "Pub/Sub resources validation failed"
        return 1
    fi
    
    # Check Cloud Run service
    log_info "Verifying Cloud Run service..."
    if gcloud run services describe "${CLOUDRUN_SERVICE}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        log_success "Cloud Run service is running"
    else
        log_error "Cloud Run service validation failed"
        return 1
    fi
    
    # Test service health endpoint
    log_info "Testing service health endpoint..."
    if curl -s -o /dev/null -w "%{http_code}" "${SERVICE_URL}/health" | grep -q "200"; then
        log_success "Service health check passed"
    else
        log_warning "Service health check failed (this might be expected during initial deployment)"
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    local deployment_end_time=$(date)
    local duration=$(($(date +%s) - $(date -d "${DEPLOYMENT_START_TIME}" +%s)))
    
    log_success "Deployment completed successfully!"
    echo ""
    echo "============================================="
    echo "         DEPLOYMENT SUMMARY"
    echo "============================================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Start Time: ${DEPLOYMENT_START_TIME}"
    echo "End Time: ${deployment_end_time}"
    echo "Duration: ${duration} seconds"
    echo ""
    echo "Created Resources:"
    echo -e "${CREATED_RESOURCES}"
    echo ""
    echo "Service URLs:"
    echo "- Cloud Run Service: ${SERVICE_URL}"
    echo "- Health Check: ${SERVICE_URL}/health"
    echo ""
    echo "Storage:"
    echo "- Upload Bucket: gs://${BUCKET_NAME}"
    echo "- Results Path: gs://${BUCKET_NAME}/processed/"
    echo ""
    echo "Document AI:"
    echo "- Processor ID: ${PROCESSOR_ID}"
    echo "- Processor Type: FORM_PARSER_PROCESSOR"
    echo ""
    echo "Next Steps:"
    echo "1. Upload test documents to: gs://${BUCKET_NAME}"
    echo "2. Check processing results in: gs://${BUCKET_NAME}/processed/"
    echo "3. Monitor logs: gcloud logging read 'resource.type=cloud_run_revision'"
    echo "4. View metrics in Cloud Console"
    echo ""
    echo "To test the deployment:"
    echo "  gsutil cp your-document.pdf gs://${BUCKET_NAME}/"
    echo ""
    echo "============================================="
}

# Main deployment function
main() {
    log_info "Configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Bucket Name: ${BUCKET_NAME}"
    echo "  Cloud Run Service: ${CLOUDRUN_SERVICE}"
    echo "  Service Account: ${SERVICE_ACCOUNT_NAME}"
    echo ""
    
    # Initialize deployment state file
    echo "# GCP Document Processing Deployment State" > "${DEPLOYMENT_STATE_FILE}"
    echo "# Generated at: $(date)" >> "${DEPLOYMENT_STATE_FILE}"
    
    # Set gcloud project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    # Execute deployment steps
    check_prerequisites
    enable_apis
    create_documentai_processor
    create_storage_bucket
    create_pubsub_resources
    configure_storage_notification
    create_service_account
    deploy_cloudrun_service
    configure_push_subscription
    validate_deployment
    display_summary
    
    # Save final configuration
    cat > "/tmp/gcp-docai-config-${PROJECT_ID}.env" << EOF
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export BUCKET_NAME="${BUCKET_NAME}"
export PUBSUB_TOPIC="${PUBSUB_TOPIC}"
export PUBSUB_SUBSCRIPTION="${PUBSUB_SUBSCRIPTION}"
export CLOUDRUN_SERVICE="${CLOUDRUN_SERVICE}"
export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME}"
export PROCESSOR_ID="${PROCESSOR_ID}"
export SERVICE_URL="${SERVICE_URL}"
EOF
    
    log_success "Configuration saved to: /tmp/gcp-docai-config-${PROJECT_ID}.env"
    log_success "Source this file to reload environment variables"
    
    # Clean up state file on successful completion
    rm -f "${DEPLOYMENT_STATE_FILE}"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--dry-run] [--force]"
        echo ""
        echo "Environment Variables (optional):"
        echo "  PROJECT_ID - GCP Project ID (default: doc-processing-<timestamp>)"
        echo "  REGION - GCP Region (default: us-central1)"
        echo "  BUCKET_NAME - Storage bucket name (default: document-uploads-<project-id>)"
        echo "  CLOUDRUN_SERVICE - Cloud Run service name (default: document-processor)"
        echo ""
        echo "Options:"
        echo "  --dry-run    Show what would be deployed without making changes"
        echo "  --force      Skip confirmation prompts"
        echo "  --help, -h   Show this help message"
        exit 0
        ;;
    --dry-run)
        log_info "DRY RUN MODE - No resources will be created"
        log_info "Would deploy document processing pipeline with:"
        echo "  Project: ${PROJECT_ID}"
        echo "  Region: ${REGION}"
        echo "  Bucket: ${BUCKET_NAME}"
        echo "  Service: ${CLOUDRUN_SERVICE}"
        exit 0
        ;;
    --force)
        log_info "Force mode enabled - skipping confirmations"
        ;;
    "")
        # Interactive confirmation
        echo "This script will deploy the GCP Document Processing pipeline."
        echo "Project: ${PROJECT_ID}"
        echo "Region: ${REGION}"
        echo ""
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main deployment
main