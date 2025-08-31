#!/bin/bash

# Deploy script for Background Task Processing with Cloud Run Worker Pools
# This script deploys the complete serverless background processing solution
# using Cloud Run Jobs, Pub/Sub, and Cloud Storage

set -euo pipefail

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

# Error handling function
handle_error() {
    log_error "Deployment failed at line $1. Exit code: $2"
    log_info "Check the logs above for details"
    exit $2
}

# Set error trap
trap 'handle_error $LINENO $?' ERR

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_BASE_NAME="background-tasks"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        echo "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 > /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if Docker is available (for Cloud Build)
    if ! command -v docker &> /dev/null; then
        log_warning "Docker not found. Cloud Build will be used for container builds."
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        TIMESTAMP=$(date +%s)
        export PROJECT_ID="${PROJECT_BASE_NAME}-${TIMESTAMP}"
        log_info "Generated PROJECT_ID: ${PROJECT_ID}"
    fi
    
    # Set default region and zone
    export REGION="${REGION:-${DEFAULT_REGION}}"
    export ZONE="${ZONE:-${DEFAULT_ZONE}}"
    
    # Generate unique suffix for resources
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names
    export TOPIC_NAME="task-queue-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_NAME="worker-sub-${RANDOM_SUFFIX}"
    export BUCKET_NAME="task-files-${PROJECT_ID}-${RANDOM_SUFFIX}"
    export JOB_NAME="background-worker-${RANDOM_SUFFIX}"
    export API_SERVICE_NAME="task-api-${RANDOM_SUFFIX}"
    
    # Save environment to file for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
TOPIC_NAME=${TOPIC_NAME}
SUBSCRIPTION_NAME=${SUBSCRIPTION_NAME}
BUCKET_NAME=${BUCKET_NAME}
JOB_NAME=${JOB_NAME}
API_SERVICE_NAME=${API_SERVICE_NAME}
EOF
    
    log_success "Environment variables configured"
}

# Function to create or select project
setup_project() {
    log_info "Setting up Google Cloud project: ${PROJECT_ID}"
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_info "Project ${PROJECT_ID} already exists"
    else
        log_info "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" \
            --name="Background Task Processing Demo"
        
        # Wait for project creation to complete
        sleep 5
    fi
    
    # Set project configuration
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "run.googleapis.com"
        "pubsub.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create foundational resources
create_foundation() {
    log_info "Creating foundational resources..."
    
    # Create Pub/Sub topic
    log_info "Creating Pub/Sub topic: ${TOPIC_NAME}"
    if ! gcloud pubsub topics describe "${TOPIC_NAME}" &> /dev/null; then
        gcloud pubsub topics create "${TOPIC_NAME}"
        log_success "Pub/Sub topic created"
    else
        log_info "Pub/Sub topic already exists"
    fi
    
    # Create Cloud Storage bucket
    log_info "Creating Cloud Storage bucket: ${BUCKET_NAME}"
    if ! gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}"
        
        # Create subdirectories
        echo "Bucket created $(date)" | gsutil cp - "gs://${BUCKET_NAME}/processed/.keep"
        echo "Bucket created $(date)" | gsutil cp - "gs://${BUCKET_NAME}/results/.keep"
        
        log_success "Cloud Storage bucket created with subdirectories"
    else
        log_info "Cloud Storage bucket already exists"
    fi
    
    # Create Artifact Registry repository for container images
    log_info "Creating Artifact Registry repository..."
    if ! gcloud artifacts repositories describe cloud-run-source-deploy \
         --location="${REGION}" &> /dev/null; then
        gcloud artifacts repositories create cloud-run-source-deploy \
            --repository-format=docker \
            --location="${REGION}" \
            --description="Repository for background worker containers"
        log_success "Artifact Registry repository created"
    else
        log_info "Artifact Registry repository already exists"
    fi
}

# Function to create worker application
create_worker_app() {
    log_info "Creating worker application..."
    
    local worker_dir="${SCRIPT_DIR}/../worker"
    mkdir -p "${worker_dir}"
    cd "${worker_dir}"
    
    # Create main.py
    cat > main.py << 'EOF'
import os
import json
import time
import logging
from google.cloud import storage, pubsub_v1
from concurrent.futures import ThreadPoolExecutor
import signal
import sys

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class BackgroundWorker:
    def __init__(self):
        self.project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
        self.subscription_name = os.environ.get('SUBSCRIPTION_NAME')
        self.bucket_name = os.environ.get('BUCKET_NAME')
        self.max_messages = int(os.environ.get('MAX_MESSAGES', '10'))
        
        self.subscriber = pubsub_v1.SubscriberClient()
        self.storage_client = storage.Client()
        
        self.subscription_path = self.subscriber.subscription_path(
            self.project_id, self.subscription_name)
        
        self.running = True
        signal.signal(signal.SIGTERM, self.shutdown)
        signal.signal(signal.SIGINT, self.shutdown)
    
    def shutdown(self, signum, frame):
        logger.info("Received shutdown signal")
        self.running = False
    
    def process_message(self, message):
        """Process individual Pub/Sub message"""
        try:
            # Parse message data
            data = json.loads(message.data.decode('utf-8'))
            task_type = data.get('task_type', 'unknown')
            
            logger.info(f"Processing task: {task_type}")
            
            if task_type == 'file_processing':
                self.process_file_task(data)
            elif task_type == 'data_transformation':
                self.process_data_task(data)
            else:
                logger.warning(f"Unknown task type: {task_type}")
            
            # Acknowledge message after successful processing
            message.ack()
            logger.info(f"Task {task_type} completed successfully")
            
        except Exception as e:
            logger.error(f"Error processing message: {e}")
            message.nack()
    
    def process_file_task(self, data):
        """Simulate file processing task"""
        filename = data.get('filename', 'default.txt')
        processing_time = data.get('processing_time', 2)
        
        # Create sample processed file
        bucket = self.storage_client.bucket(self.bucket_name)
        blob = bucket.blob(f"processed/{filename}")
        
        # Simulate processing work
        time.sleep(processing_time)
        
        processed_content = f"Processed at {time.strftime('%Y-%m-%d %H:%M:%S')}\n"
        processed_content += f"Original file: {filename}\n"
        processed_content += f"Processing time: {processing_time}s\n"
        
        blob.upload_from_string(processed_content)
        logger.info(f"File {filename} processed and saved")
    
    def process_data_task(self, data):
        """Simulate data transformation task"""
        dataset_size = data.get('dataset_size', 100)
        transformation_type = data.get('transformation', 'normalize')
        
        # Simulate data processing
        time.sleep(1)
        
        result = {
            'transformation': transformation_type,
            'records_processed': dataset_size,
            'timestamp': time.strftime('%Y-%m-%d %H:%M:%S')
        }
        
        # Save result to Cloud Storage
        bucket = self.storage_client.bucket(self.bucket_name)
        blob = bucket.blob(f"results/data_transform_{int(time.time())}.json")
        blob.upload_from_string(json.dumps(result, indent=2))
        
        logger.info(f"Data transformation completed: {transformation_type}")
    
    def run(self):
        """Main worker loop"""
        logger.info("Starting background worker")
        
        with ThreadPoolExecutor(max_workers=4) as executor:
            while self.running:
                try:
                    # Pull messages from subscription
                    response = self.subscriber.pull(
                        request={
                            "subscription": self.subscription_path,
                            "max_messages": self.max_messages,
                        },
                        timeout=30.0
                    )
                    
                    if response.received_messages:
                        logger.info(f"Received {len(response.received_messages)} messages")
                        
                        # Process messages concurrently
                        futures = []
                        for message in response.received_messages:
                            future = executor.submit(self.process_message, message)
                            futures.append(future)
                        
                        # Wait for all tasks to complete
                        for future in futures:
                            future.result()
                    
                    else:
                        logger.info("No messages received, waiting...")
                        time.sleep(5)
                        
                except Exception as e:
                    logger.error(f"Error in worker loop: {e}")
                    time.sleep(10)
        
        logger.info("Background worker shutdown complete")

if __name__ == "__main__":
    worker = BackgroundWorker()
    worker.run()
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-pubsub==2.23.1
google-cloud-storage==2.17.0
google-cloud-logging==3.11.0
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

ENV PYTHONUNBUFFERED=1

CMD ["python", "main.py"]
EOF
    
    log_success "Worker application created"
}

# Function to build and deploy worker container
deploy_worker() {
    log_info "Building and deploying worker container..."
    
    local worker_dir="${SCRIPT_DIR}/../worker"
    cd "${worker_dir}"
    
    # Build container image
    log_info "Building container image..."
    gcloud builds submit \
        --tag "${REGION}-docker.pkg.dev/${PROJECT_ID}/cloud-run-source-deploy/${JOB_NAME}" \
        --timeout=10m
    
    # Create Pub/Sub subscription
    log_info "Creating Pub/Sub subscription: ${SUBSCRIPTION_NAME}"
    if ! gcloud pubsub subscriptions describe "${SUBSCRIPTION_NAME}" &> /dev/null; then
        gcloud pubsub subscriptions create "${SUBSCRIPTION_NAME}" \
            --topic="${TOPIC_NAME}" \
            --ack-deadline=600 \
            --message-retention-duration=7d \
            --max-delivery-attempts=5
        log_success "Pub/Sub subscription created"
    else
        log_info "Pub/Sub subscription already exists"
    fi
    
    # Deploy Cloud Run Job
    log_info "Deploying Cloud Run Job: ${JOB_NAME}"
    gcloud run jobs create "${JOB_NAME}" \
        --image="${REGION}-docker.pkg.dev/${PROJECT_ID}/cloud-run-source-deploy/${JOB_NAME}" \
        --region="${REGION}" \
        --set-env-vars="SUBSCRIPTION_NAME=${SUBSCRIPTION_NAME},BUCKET_NAME=${BUCKET_NAME}" \
        --memory=1Gi \
        --cpu=1 \
        --max-retries=3 \
        --parallelism=1 \
        --task-count=1 \
        --quiet
    
    log_success "Worker deployed successfully"
}

# Function to create and deploy API service
deploy_api() {
    log_info "Creating and deploying API service..."
    
    local api_dir="${SCRIPT_DIR}/../api"
    mkdir -p "${api_dir}"
    cd "${api_dir}"
    
    # Create app.py
    cat > app.py << 'EOF'
import os
import json
import time
from flask import Flask, request, jsonify
from google.cloud import pubsub_v1
import uuid
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Initialize Pub/Sub client
publisher = pubsub_v1.PublisherClient()
project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
topic_name = os.environ.get('TOPIC_NAME')
topic_path = publisher.topic_path(project_id, topic_name)

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy'}), 200

@app.route('/submit-task', methods=['POST'])
def submit_task():
    try:
        data = request.get_json()
        
        # Validate required fields
        if not data or 'task_type' not in data:
            return jsonify({'error': 'task_type is required'}), 400
        
        # Add task metadata
        task_data = {
            'task_id': str(uuid.uuid4()),
            'task_type': data['task_type'],
            'submitted_at': str(int(time.time())),
            **data
        }
        
        # Publish message to Pub/Sub
        message_data = json.dumps(task_data).encode('utf-8')
        future = publisher.publish(topic_path, message_data)
        message_id = future.result()
        
        logging.info(f"Task submitted: {task_data['task_id']}")
        
        return jsonify({
            'task_id': task_data['task_id'],
            'message_id': message_id,
            'status': 'submitted'
        }), 200
        
    except Exception as e:
        logging.error(f"Error submitting task: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/submit-file-task', methods=['POST'])
def submit_file_task():
    data = {
        'task_type': 'file_processing',
        'filename': request.json.get('filename', 'sample.txt'),
        'processing_time': request.json.get('processing_time', 2)
    }
    request._cached_json = data
    return submit_task()

@app.route('/submit-data-task', methods=['POST'])
def submit_data_task():
    data = {
        'task_type': 'data_transformation',
        'dataset_size': request.json.get('dataset_size', 100),
        'transformation': request.json.get('transformation', 'normalize')
    }
    request._cached_json = data
    return submit_task()

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port)
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
Flask==3.0.3
google-cloud-pubsub==2.23.1
gunicorn==22.0.0
EOF
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

ENV PORT=8080
EXPOSE 8080

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "0", "app:app"]
EOF
    
    # Deploy API service
    log_info "Deploying API service..."
    gcloud run deploy "${API_SERVICE_NAME}" \
        --source . \
        --region="${REGION}" \
        --set-env-vars="TOPIC_NAME=${TOPIC_NAME}" \
        --allow-unauthenticated \
        --memory=512Mi \
        --cpu=1 \
        --min-instances=0 \
        --max-instances=10 \
        --quiet
    
    # Get API service URL
    export API_URL=$(gcloud run services describe "${API_SERVICE_NAME}" \
        --region="${REGION}" \
        --format='value(status.url)')
    
    # Save API URL to environment file
    echo "API_URL=${API_URL}" >> "${SCRIPT_DIR}/.env"
    
    log_success "API service deployed at: ${API_URL}"
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Source environment file to get API_URL
    source "${SCRIPT_DIR}/.env"
    
    # Test health endpoint
    log_info "Testing API health endpoint..."
    if curl -s "${API_URL}/health" | grep -q "healthy"; then
        log_success "API health check passed"
    else
        log_warning "API health check failed, but deployment may still be successful"
    fi
    
    # Check Cloud Run Job
    if gcloud run jobs describe "${JOB_NAME}" --region="${REGION}" &> /dev/null; then
        log_success "Cloud Run Job is deployed"
    else
        log_error "Cloud Run Job deployment verification failed"
    fi
    
    # Check Pub/Sub resources
    if gcloud pubsub topics describe "${TOPIC_NAME}" &> /dev/null; then
        log_success "Pub/Sub topic is available"
    else
        log_error "Pub/Sub topic verification failed"
    fi
    
    # Check Cloud Storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        log_success "Cloud Storage bucket is available"
    else
        log_error "Cloud Storage bucket verification failed"
    fi
    
    log_success "Deployment verification completed"
}

# Function to display deployment summary
show_summary() {
    source "${SCRIPT_DIR}/.env"
    
    log_success "Deployment completed successfully!"
    echo
    echo "==============================================="
    echo "         DEPLOYMENT SUMMARY"
    echo "==============================================="
    echo "Project ID:        ${PROJECT_ID}"
    echo "Region:           ${REGION}"
    echo "API Service URL:  ${API_URL}"
    echo "Job Name:         ${JOB_NAME}"
    echo "Topic Name:       ${TOPIC_NAME}"
    echo "Bucket Name:      ${BUCKET_NAME}"
    echo
    echo "Testing Commands:"
    echo "  # Test file processing task:"
    echo "  curl -X POST \"${API_URL}/submit-file-task\" \\"
    echo "       -H \"Content-Type: application/json\" \\"
    echo "       -d '{\"filename\": \"test.pdf\", \"processing_time\": 3}'"
    echo
    echo "  # Execute background job manually:"
    echo "  gcloud run jobs execute ${JOB_NAME} --region=${REGION}"
    echo
    echo "  # Check processed files:"
    echo "  gsutil ls -r gs://${BUCKET_NAME}/"
    echo
    echo "Environment file saved to: ${SCRIPT_DIR}/.env"
    echo "Run ./destroy.sh to clean up all resources"
    echo "==============================================="
}

# Main deployment function
main() {
    log_info "Starting deployment of Background Task Processing system"
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_foundation
    create_worker_app
    deploy_worker
    deploy_api
    verify_deployment
    show_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"