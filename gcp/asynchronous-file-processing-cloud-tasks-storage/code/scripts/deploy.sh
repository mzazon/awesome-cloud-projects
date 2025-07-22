#!/bin/bash

# Asynchronous File Processing with Cloud Tasks and Cloud Storage - Deployment Script
# This script deploys the complete asynchronous file processing system on Google Cloud Platform

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Color codes for output
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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Parse command line arguments
REGION="${1:-$DEFAULT_REGION}"
ZONE="${2:-$DEFAULT_ZONE}"
DRY_RUN="${3:-false}"

# Display usage information
usage() {
    echo "Usage: $0 [REGION] [ZONE] [DRY_RUN]"
    echo "  REGION   : Google Cloud region (default: us-central1)"
    echo "  ZONE     : Google Cloud zone (default: us-central1-a)"
    echo "  DRY_RUN  : Set to 'true' to validate prerequisites only (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with default settings"
    echo "  $0 us-east1 us-east1-b              # Deploy to specific region/zone"
    echo "  $0 us-central1 us-central1-a true   # Dry run validation"
    exit 1
}

# Check if help was requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
fi

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "Google Cloud SDK (gsutil) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    # Check if python3 is installed
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Please install it first."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Google Cloud CLI is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Get project ID
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "No Google Cloud project is configured. Please run 'gcloud config set project PROJECT_ID' first."
        exit 1
    fi
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "$PROJECT_ID" &>/dev/null; then
        log_warning "Cannot verify billing status. Please ensure billing is enabled for project $PROJECT_ID."
    fi
    
    log_success "Prerequisites check passed"
    echo "  - Project ID: $PROJECT_ID"
    echo "  - Region: $REGION"
    echo "  - Zone: $ZONE"
    echo "  - Docker: $(docker --version | head -1)"
    echo "  - Python: $(python3 --version)"
    echo "  - gcloud: $(gcloud --version | head -1)"
}

# Set environment variables
set_environment_variables() {
    log_info "Setting environment variables..."
    
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="$REGION"
    export ZONE="$ZONE"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export UPLOAD_BUCKET="file-upload-${RANDOM_SUFFIX}"
    export RESULTS_BUCKET="file-results-${RANDOM_SUFFIX}"
    export PUBSUB_TOPIC="file-processing-${RANDOM_SUFFIX}"
    export TASK_QUEUE="file-processing-queue-${RANDOM_SUFFIX}"
    
    # Configure gcloud defaults
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "Environment variables configured"
    echo "  - Upload Bucket: $UPLOAD_BUCKET"
    echo "  - Results Bucket: $RESULTS_BUCKET"
    echo "  - Pub/Sub Topic: $PUBSUB_TOPIC"
    echo "  - Task Queue: $TASK_QUEUE"
    
    # Save configuration to file for cleanup script
    cat > "${SCRIPT_DIR}/deployment_config.env" << EOF
PROJECT_ID=$PROJECT_ID
REGION=$REGION
ZONE=$ZONE
UPLOAD_BUCKET=$UPLOAD_BUCKET
RESULTS_BUCKET=$RESULTS_BUCKET
PUBSUB_TOPIC=$PUBSUB_TOPIC
TASK_QUEUE=$TASK_QUEUE
EOF
    
    log_success "Configuration saved to deployment_config.env"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudtasks.googleapis.com"
        "storage.googleapis.com"
        "pubsub.googleapis.com"
        "run.googleapis.com"
        "cloudbuild.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log_success "Enabled $api"
        else
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create Cloud Storage buckets
create_storage_buckets() {
    log_info "Creating Cloud Storage buckets..."
    
    # Create bucket for file uploads
    log_info "Creating upload bucket: $UPLOAD_BUCKET"
    if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://${UPLOAD_BUCKET}"; then
        log_success "Created upload bucket: $UPLOAD_BUCKET"
    else
        log_error "Failed to create upload bucket"
        exit 1
    fi
    
    # Create bucket for processed results
    log_info "Creating results bucket: $RESULTS_BUCKET"
    if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://${RESULTS_BUCKET}"; then
        log_success "Created results bucket: $RESULTS_BUCKET"
    else
        log_error "Failed to create results bucket"
        exit 1
    fi
    
    # Enable versioning for data protection
    log_info "Enabling versioning on buckets..."
    gsutil versioning set on "gs://${UPLOAD_BUCKET}"
    gsutil versioning set on "gs://${RESULTS_BUCKET}"
    
    log_success "Cloud Storage buckets created and configured"
}

# Create Pub/Sub resources
create_pubsub_resources() {
    log_info "Creating Cloud Pub/Sub resources..."
    
    # Create Pub/Sub topic
    log_info "Creating Pub/Sub topic: $PUBSUB_TOPIC"
    if gcloud pubsub topics create "$PUBSUB_TOPIC"; then
        log_success "Created Pub/Sub topic: $PUBSUB_TOPIC"
    else
        log_error "Failed to create Pub/Sub topic"
        exit 1
    fi
    
    # Create subscription
    log_info "Creating Pub/Sub subscription: ${PUBSUB_TOPIC}-subscription"
    if gcloud pubsub subscriptions create "${PUBSUB_TOPIC}-subscription" \
        --topic="$PUBSUB_TOPIC" \
        --ack-deadline=60 \
        --message-retention-duration=7d; then
        log_success "Created Pub/Sub subscription: ${PUBSUB_TOPIC}-subscription"
    else
        log_error "Failed to create Pub/Sub subscription"
        exit 1
    fi
    
    log_success "Cloud Pub/Sub resources created"
}

# Create Cloud Tasks queue
create_task_queue() {
    log_info "Creating Cloud Tasks queue..."
    
    log_info "Creating task queue: $TASK_QUEUE"
    if gcloud tasks queues create "$TASK_QUEUE" \
        --location="$REGION" \
        --max-dispatches-per-second=10 \
        --max-concurrent-dispatches=100 \
        --max-attempts=3 \
        --min-backoff=2s \
        --max-backoff=300s; then
        log_success "Created task queue: $TASK_QUEUE"
    else
        log_error "Failed to create task queue"
        exit 1
    fi
    
    log_success "Cloud Tasks queue created with retry configuration"
}

# Create service containers
create_service_containers() {
    log_info "Creating service containers..."
    
    # Create upload service
    log_info "Creating upload service container..."
    local upload_service_dir="${PROJECT_ROOT}/upload-service"
    mkdir -p "$upload_service_dir"
    
    # Create upload service main.py
    cat > "${upload_service_dir}/main.py" << 'EOF'
import os
import tempfile
from flask import Flask, request, jsonify
from google.cloud import storage, tasks_v2
from google.cloud.tasks_v2 import Task
from google.protobuf import timestamp_pb2
import json

app = Flask(__name__)

# Initialize clients
storage_client = storage.Client()
tasks_client = tasks_v2.CloudTasksClient()

PROJECT_ID = os.environ.get('PROJECT_ID')
REGION = os.environ.get('REGION')
UPLOAD_BUCKET = os.environ.get('UPLOAD_BUCKET')
TASK_QUEUE = os.environ.get('TASK_QUEUE')
PROCESSOR_URL = os.environ.get('PROCESSOR_URL')

@app.route('/upload', methods=['POST'])
def upload_file():
    """Handle file upload and queue processing task"""
    try:
        if 'file' not in request.files:
            return jsonify({'error': 'No file provided'}), 400
        
        file = request.files['file']
        if file.filename == '':
            return jsonify({'error': 'No file selected'}), 400
        
        # Upload file to Cloud Storage
        bucket = storage_client.bucket(UPLOAD_BUCKET)
        blob = bucket.blob(file.filename)
        blob.upload_from_file(file.stream)
        
        # Create task for processing
        parent = tasks_client.queue_path(PROJECT_ID, REGION, TASK_QUEUE)
        
        task_payload = {
            'bucket': UPLOAD_BUCKET,
            'filename': file.filename,
            'content_type': file.content_type or 'application/octet-stream'
        }
        
        task = Task(
            http_request={
                'http_method': tasks_v2.HttpMethod.POST,
                'url': PROCESSOR_URL,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(task_payload).encode('utf-8')
            }
        )
        
        # Queue the task
        response = tasks_client.create_task(parent=parent, task=task)
        
        return jsonify({
            'message': 'File uploaded and queued for processing',
            'filename': file.filename,
            'task_name': response.name
        }), 200
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF
    
    # Create upload service requirements.txt
    cat > "${upload_service_dir}/requirements.txt" << 'EOF'
Flask==2.3.3
google-cloud-storage==2.10.0
google-cloud-tasks==2.14.0
gunicorn==21.2.0
EOF
    
    # Create upload service Dockerfile
    cat > "${upload_service_dir}/Dockerfile" << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--threads", "4", "--timeout", "0", "main:app"]
EOF
    
    # Create processing service
    log_info "Creating processing service container..."
    local processing_service_dir="${PROJECT_ROOT}/processing-service"
    mkdir -p "$processing_service_dir"
    
    # Create processing service main.py
    cat > "${processing_service_dir}/main.py" << 'EOF'
import os
import json
import tempfile
import time
from flask import Flask, request, jsonify
from google.cloud import storage
from PIL import Image
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Initialize clients
storage_client = storage.Client()

PROJECT_ID = os.environ.get('PROJECT_ID')
RESULTS_BUCKET = os.environ.get('RESULTS_BUCKET')

@app.route('/process', methods=['POST'])
def process_file():
    """Process uploaded file based on task payload"""
    try:
        # Parse task payload
        task_data = request.get_json()
        bucket_name = task_data.get('bucket')
        filename = task_data.get('filename')
        content_type = task_data.get('content_type', 'application/octet-stream')
        
        logging.info(f"Processing file: {filename} from bucket: {bucket_name}")
        
        # Download file from Cloud Storage
        source_bucket = storage_client.bucket(bucket_name)
        source_blob = source_bucket.blob(filename)
        
        with tempfile.NamedTemporaryFile() as temp_file:
            source_blob.download_to_filename(temp_file.name)
            
            # Perform processing based on content type
            if content_type.startswith('image/'):
                processed_filename = process_image(temp_file.name, filename)
            else:
                processed_filename = process_generic_file(temp_file.name, filename)
            
            # Upload processed file to results bucket
            results_bucket = storage_client.bucket(RESULTS_BUCKET)
            results_blob = results_bucket.blob(processed_filename)
            results_blob.upload_from_filename(temp_file.name)
            
            # Create processing metadata
            metadata = {
                'original_filename': filename,
                'processed_filename': processed_filename,
                'processing_time': time.time(),
                'content_type': content_type,
                'status': 'completed'
            }
            
            # Upload metadata file
            metadata_blob = results_bucket.blob(f"{processed_filename}.metadata.json")
            metadata_blob.upload_from_string(json.dumps(metadata, indent=2))
            
            logging.info(f"File processed successfully: {processed_filename}")
            
            return jsonify({
                'message': 'File processed successfully',
                'original_filename': filename,
                'processed_filename': processed_filename,
                'metadata': metadata
            }), 200
            
    except Exception as e:
        logging.error(f"Error processing file: {str(e)}")
        return jsonify({'error': str(e)}), 500

def process_image(file_path, original_filename):
    """Process image files - resize and optimize"""
    try:
        with Image.open(file_path) as img:
            # Resize image to thumbnail
            img.thumbnail((300, 300), Image.Resampling.LANCZOS)
            
            # Convert to RGB if necessary
            if img.mode != 'RGB':
                img = img.convert('RGB')
            
            # Save optimized image
            processed_name = f"thumb_{original_filename}"
            img.save(file_path, 'JPEG', quality=85, optimize=True)
            
            return processed_name
            
    except Exception as e:
        logging.error(f"Error processing image: {str(e)}")
        raise

def process_generic_file(file_path, original_filename):
    """Process generic files - add processing timestamp"""
    processed_name = f"processed_{int(time.time())}_{original_filename}"
    
    # In a real implementation, you would perform actual file processing here
    # This is a placeholder that demonstrates the workflow
    
    return processed_name

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy'}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF
    
    # Create processing service requirements.txt
    cat > "${processing_service_dir}/requirements.txt" << 'EOF'
Flask==2.3.3
google-cloud-storage==2.10.0
Pillow==10.0.0
gunicorn==21.2.0
EOF
    
    # Create processing service Dockerfile
    cat > "${processing_service_dir}/Dockerfile" << 'EOF'
FROM python:3.11-slim

# Install system dependencies for image processing
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--threads", "4", "--timeout", "0", "main:app"]
EOF
    
    log_success "Service containers created"
}

# Build and deploy Cloud Run services
deploy_cloud_run_services() {
    log_info "Building and deploying Cloud Run services..."
    
    # Build and deploy upload service
    log_info "Building upload service..."
    cd "${PROJECT_ROOT}/upload-service"
    
    if gcloud builds submit --tag "gcr.io/${PROJECT_ID}/upload-service" . --quiet; then
        log_success "Upload service container built"
    else
        log_error "Failed to build upload service container"
        exit 1
    fi
    
    log_info "Deploying upload service..."
    if gcloud run deploy upload-service \
        --image "gcr.io/${PROJECT_ID}/upload-service" \
        --region "$REGION" \
        --platform managed \
        --allow-unauthenticated \
        --memory 1Gi \
        --cpu 1 \
        --concurrency 100 \
        --max-instances 10 \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION},UPLOAD_BUCKET=${UPLOAD_BUCKET},TASK_QUEUE=${TASK_QUEUE}" \
        --quiet; then
        log_success "Upload service deployed"
    else
        log_error "Failed to deploy upload service"
        exit 1
    fi
    
    # Get upload service URL
    UPLOAD_SERVICE_URL=$(gcloud run services describe upload-service \
        --region "$REGION" \
        --format "value(status.url)")
    
    log_info "Upload Service URL: $UPLOAD_SERVICE_URL"
    
    # Build and deploy processing service
    log_info "Building processing service..."
    cd "${PROJECT_ROOT}/processing-service"
    
    if gcloud builds submit --tag "gcr.io/${PROJECT_ID}/processing-service" . --quiet; then
        log_success "Processing service container built"
    else
        log_error "Failed to build processing service container"
        exit 1
    fi
    
    log_info "Deploying processing service..."
    if gcloud run deploy processing-service \
        --image "gcr.io/${PROJECT_ID}/processing-service" \
        --region "$REGION" \
        --platform managed \
        --no-allow-unauthenticated \
        --memory 2Gi \
        --cpu 2 \
        --concurrency 50 \
        --max-instances 20 \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},RESULTS_BUCKET=${RESULTS_BUCKET}" \
        --quiet; then
        log_success "Processing service deployed"
    else
        log_error "Failed to deploy processing service"
        exit 1
    fi
    
    # Get processing service URL
    PROCESSING_SERVICE_URL=$(gcloud run services describe processing-service \
        --region "$REGION" \
        --format "value(status.url)")
    
    log_info "Processing Service URL: $PROCESSING_SERVICE_URL"
    
    # Update configuration file with service URLs
    cat >> "${SCRIPT_DIR}/deployment_config.env" << EOF
UPLOAD_SERVICE_URL=$UPLOAD_SERVICE_URL
PROCESSING_SERVICE_URL=$PROCESSING_SERVICE_URL
EOF
    
    cd "$PROJECT_ROOT"
    
    log_success "Cloud Run services deployed successfully"
}

# Configure Cloud Storage event notifications
configure_storage_notifications() {
    log_info "Configuring Cloud Storage event notifications..."
    
    # Create Cloud Storage notification configuration
    log_info "Creating storage notification for bucket: $UPLOAD_BUCKET"
    if gsutil notification create \
        -t "$PUBSUB_TOPIC" \
        -f json \
        -e OBJECT_FINALIZE \
        "gs://${UPLOAD_BUCKET}"; then
        log_success "Storage notification created"
    else
        log_error "Failed to create storage notification"
        exit 1
    fi
    
    # Grant Cloud Storage service account permissions to publish to Pub/Sub
    log_info "Granting Cloud Storage service account permissions..."
    GCS_SERVICE_ACCOUNT=$(gsutil kms serviceaccount -p "$PROJECT_ID")
    
    if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${GCS_SERVICE_ACCOUNT}" \
        --role="roles/pubsub.publisher" \
        --quiet; then
        log_success "IAM permissions granted to Cloud Storage service account"
    else
        log_error "Failed to grant IAM permissions"
        exit 1
    fi
    
    log_success "Cloud Storage notifications configured"
}

# Update upload service with processing service URL
update_upload_service() {
    log_info "Updating upload service with processing service URL..."
    
    # Get processing service URL
    PROCESSING_SERVICE_URL=$(gcloud run services describe processing-service \
        --region "$REGION" \
        --format "value(status.url)")
    
    # Update upload service environment variables
    if gcloud run services update upload-service \
        --region "$REGION" \
        --update-env-vars "PROCESSOR_URL=${PROCESSING_SERVICE_URL}/process" \
        --quiet; then
        log_success "Upload service updated with processing service URL"
    else
        log_error "Failed to update upload service"
        exit 1
    fi
    
    log_success "Service interconnection completed"
}

# Create service accounts and configure IAM
configure_iam() {
    log_info "Creating service accounts and configuring IAM..."
    
    # Create service account for upload service
    log_info "Creating upload service account..."
    if gcloud iam service-accounts create upload-service-sa \
        --display-name="Upload Service Account" \
        --quiet; then
        log_success "Upload service account created"
    else
        log_warning "Upload service account may already exist"
    fi
    
    # Create service account for processing service
    log_info "Creating processing service account..."
    if gcloud iam service-accounts create processing-service-sa \
        --display-name="Processing Service Account" \
        --quiet; then
        log_success "Processing service account created"
    else
        log_warning "Processing service account may already exist"
    fi
    
    # Grant permissions for upload service
    log_info "Granting permissions for upload service..."
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:upload-service-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/storage.objectAdmin" \
        --quiet
    
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:upload-service-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/cloudtasks.enqueuer" \
        --quiet
    
    # Grant permissions for processing service
    log_info "Granting permissions for processing service..."
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:processing-service-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --role="roles/storage.objectAdmin" \
        --quiet
    
    # Update Cloud Run services to use service accounts
    log_info "Updating Cloud Run services with service accounts..."
    gcloud run services update upload-service \
        --region "$REGION" \
        --service-account "upload-service-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --quiet
    
    gcloud run services update processing-service \
        --region "$REGION" \
        --service-account "processing-service-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --quiet
    
    log_success "Service accounts and IAM permissions configured"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Cloud Run services
    log_info "Checking Cloud Run services status..."
    
    UPLOAD_STATUS=$(gcloud run services describe upload-service \
        --region "$REGION" \
        --format "value(status.conditions[0].status)")
    
    PROCESSING_STATUS=$(gcloud run services describe processing-service \
        --region "$REGION" \
        --format "value(status.conditions[0].status)")
    
    if [[ "$UPLOAD_STATUS" == "True" && "$PROCESSING_STATUS" == "True" ]]; then
        log_success "Cloud Run services are running"
    else
        log_error "Cloud Run services are not ready"
        exit 1
    fi
    
    # Check Cloud Tasks queue
    log_info "Checking Cloud Tasks queue..."
    QUEUE_STATE=$(gcloud tasks queues describe "$TASK_QUEUE" \
        --location "$REGION" \
        --format "value(state)")
    
    if [[ "$QUEUE_STATE" == "RUNNING" ]]; then
        log_success "Cloud Tasks queue is running"
    else
        log_error "Cloud Tasks queue is not ready"
        exit 1
    fi
    
    # Check Cloud Storage buckets
    log_info "Checking Cloud Storage buckets..."
    if gsutil ls -b "gs://${UPLOAD_BUCKET}" &>/dev/null && \
       gsutil ls -b "gs://${RESULTS_BUCKET}" &>/dev/null; then
        log_success "Cloud Storage buckets are accessible"
    else
        log_error "Cloud Storage buckets are not accessible"
        exit 1
    fi
    
    # Check Pub/Sub topic
    log_info "Checking Pub/Sub topic..."
    if gcloud pubsub topics describe "$PUBSUB_TOPIC" &>/dev/null; then
        log_success "Pub/Sub topic exists"
    else
        log_error "Pub/Sub topic is not accessible"
        exit 1
    fi
    
    log_success "Deployment validation completed successfully"
}

# Display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "=================================================="
    echo "DEPLOYMENT SUMMARY"
    echo "=================================================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo ""
    echo "Resources Created:"
    echo "  ✅ Upload Bucket: $UPLOAD_BUCKET"
    echo "  ✅ Results Bucket: $RESULTS_BUCKET"
    echo "  ✅ Pub/Sub Topic: $PUBSUB_TOPIC"
    echo "  ✅ Task Queue: $TASK_QUEUE"
    echo "  ✅ Upload Service: $(gcloud run services describe upload-service --region "$REGION" --format "value(status.url)")"
    echo "  ✅ Processing Service: $(gcloud run services describe processing-service --region "$REGION" --format "value(status.url)")"
    echo ""
    echo "Service Accounts:"
    echo "  ✅ upload-service-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "  ✅ processing-service-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    echo ""
    echo "Next Steps:"
    echo "1. Test the upload service:"
    echo "   curl -X POST -F 'file=@your-file.jpg' $(gcloud run services describe upload-service --region "$REGION" --format "value(status.url)")/upload"
    echo ""
    echo "2. Monitor processing:"
    echo "   gcloud tasks list --queue $TASK_QUEUE --location $REGION"
    echo "   gsutil ls gs://${RESULTS_BUCKET}/"
    echo ""
    echo "3. Clean up resources when done:"
    echo "   ./destroy.sh"
    echo "=================================================="
}

# Main deployment function
main() {
    log_info "Starting deployment of Asynchronous File Processing system..."
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo "Dry Run: $DRY_RUN"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Exit if dry run
    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "Dry run completed successfully - prerequisites check passed"
        exit 0
    fi
    
    # Execute deployment steps
    set_environment_variables
    enable_apis
    create_storage_buckets
    create_pubsub_resources
    create_task_queue
    create_service_containers
    deploy_cloud_run_services
    configure_storage_notifications
    update_upload_service
    configure_iam
    validate_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Error handling
trap 'log_error "An error occurred during deployment. Check the logs above for details."; exit 1' ERR

# Run main function
main "$@"