#!/bin/bash

# Batch Processing Workflows with Cloud Run Jobs and Cloud Scheduler - Deployment Script
# This script deploys the complete batch processing solution including:
# - Artifact Registry repository for container images
# - Cloud Run Job for batch processing
# - Cloud Scheduler for automated execution
# - Cloud Storage bucket for data processing
# - Sample data files for testing

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Command '$1' not found. Please install it first."
        exit 1
    fi
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
}

# Function to check if required APIs are enabled
check_apis() {
    log_info "Checking required APIs..."
    
    local required_apis=(
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
        "run.googleapis.com"
        "cloudscheduler.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${required_apis[@]}"; do
        if ! gcloud services list --enabled --format="value(name)" | grep -q "$api"; then
            log_info "Enabling API: $api"
            gcloud services enable "$api"
        fi
    done
    
    log_success "All required APIs are enabled"
}

# Function to create unique resource names
generate_resource_names() {
    local timestamp=$(date +%s)
    local random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 7)")
    
    export PROJECT_ID="${PROJECT_ID:-batch-processing-${timestamp}}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export JOB_NAME="${JOB_NAME:-data-processor-${random_suffix}}"
    export REGISTRY_NAME="${REGISTRY_NAME:-batch-registry-${random_suffix}}"
    export BUCKET_NAME="${BUCKET_NAME:-${PROJECT_ID}-batch-data}"
    export SCHEDULER_JOB_NAME="${SCHEDULER_JOB_NAME:-batch-schedule-${random_suffix}}"
    export IMAGE_URL="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REGISTRY_NAME}/batch-processor:latest"
    
    log_info "Generated resource names:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Job Name: ${JOB_NAME}"
    log_info "  Registry Name: ${REGISTRY_NAME}"
    log_info "  Bucket Name: ${BUCKET_NAME}"
    log_info "  Scheduler Job Name: ${SCHEDULER_JOB_NAME}"
}

# Function to set up project configuration
setup_project() {
    log_info "Setting up project configuration..."
    
    # Check if project exists or create it
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_info "Creating project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}"
        
        # Wait for project to be created
        sleep 10
        
        # Enable billing if required (user needs to set up billing manually)
        log_warning "Please ensure billing is enabled for project: ${PROJECT_ID}"
        log_warning "Visit: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
        read -p "Press Enter after enabling billing..."
    fi
    
    # Set project configuration
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Project configuration completed"
}

# Function to create Artifact Registry repository
create_artifact_registry() {
    log_info "Creating Artifact Registry repository..."
    
    # Check if repository already exists
    if gcloud artifacts repositories describe "${REGISTRY_NAME}" --location="${REGION}" &>/dev/null; then
        log_warning "Artifact Registry repository '${REGISTRY_NAME}' already exists"
        return 0
    fi
    
    # Create repository
    gcloud artifacts repositories create "${REGISTRY_NAME}" \
        --repository-format=docker \
        --location="${REGION}" \
        --description="Container registry for batch processing jobs"
    
    # Configure Docker authentication
    gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
    
    log_success "Artifact Registry repository created: ${REGISTRY_NAME}"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warning "Cloud Storage bucket '${BUCKET_NAME}' already exists"
        return 0
    fi
    
    # Create bucket
    gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}"
    
    log_success "Cloud Storage bucket created: ${BUCKET_NAME}"
}

# Function to create batch processing application
create_batch_application() {
    log_info "Creating batch processing application..."
    
    # Create application directory
    local app_dir="batch-app"
    mkdir -p "${app_dir}/src"
    
    # Create Python batch processing application
    cat > "${app_dir}/src/batch_processor.py" << 'EOF'
import os
import sys
import json
import time
from google.cloud import storage
from google.cloud import logging
from datetime import datetime

def setup_logging():
    """Configure Cloud Logging for batch job monitoring"""
    client = logging.Client()
    client.setup_logging()
    return client

def process_data_files(bucket_name, input_prefix="input/", output_prefix="output/"):
    """Process data files from Cloud Storage"""
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    
    processed_files = []
    
    # List and process input files
    blobs = bucket.list_blobs(prefix=input_prefix)
    
    for blob in blobs:
        if blob.name.endswith('.txt') or blob.name.endswith('.csv'):
            print(f"Processing file: {blob.name}")
            
            # Download file content
            content = blob.download_as_text()
            
            # Simulate data processing (add timestamp)
            processed_content = f"Processed at {datetime.now()}\n{content}"
            
            # Upload processed file to output prefix
            output_name = blob.name.replace(input_prefix, output_prefix)
            output_blob = bucket.blob(output_name)
            output_blob.upload_from_string(processed_content)
            
            processed_files.append(output_name)
            print(f"✅ Processed and saved: {output_name}")
    
    return processed_files

def main():
    """Main batch processing function"""
    print("Starting batch processing job...")
    
    # Setup logging
    setup_logging()
    
    # Get configuration from environment variables
    bucket_name = os.environ.get('BUCKET_NAME')
    batch_size = int(os.environ.get('BATCH_SIZE', '10'))
    
    if not bucket_name:
        print("ERROR: BUCKET_NAME environment variable not set")
        sys.exit(1)
    
    try:
        # Process data files
        processed_files = process_data_files(bucket_name)
        
        # Create processing summary
        summary = {
            'timestamp': datetime.now().isoformat(),
            'processed_files_count': len(processed_files),
            'processed_files': processed_files,
            'status': 'success'
        }
        
        print(f"Batch processing completed successfully: {json.dumps(summary, indent=2)}")
        
    except Exception as e:
        print(f"ERROR in batch processing: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    # Create requirements.txt
    cat > "${app_dir}/requirements.txt" << 'EOF'
google-cloud-storage==2.18.0
google-cloud-logging==3.11.0
google-cloud-core==2.4.1
EOF

    # Create Dockerfile
    cat > "${app_dir}/Dockerfile" << 'EOF'
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source code
COPY src/ ./src/

# Set environment variables
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1

# Run the batch processing application
CMD ["python", "src/batch_processor.py"]
EOF

    # Create Cloud Build configuration
    cat > "${app_dir}/cloudbuild.yaml" << EOF
steps:
  # Build the container image
  - name: 'gcr.io/cloud-builders/docker'
    args: [
      'build',
      '-t', '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REGISTRY_NAME}/batch-processor:\${SHORT_SHA}',
      '-t', '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REGISTRY_NAME}/batch-processor:latest',
      '.'
    ]
  
  # Push the container image to Artifact Registry
  - name: 'gcr.io/cloud-builders/docker'
    args: [
      'push',
      '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REGISTRY_NAME}/batch-processor:\${SHORT_SHA}'
    ]
  
  - name: 'gcr.io/cloud-builders/docker'
    args: [
      'push',
      '${REGION}-docker.pkg.dev/${PROJECT_ID}/${REGISTRY_NAME}/batch-processor:latest'
    ]

# Specify build timeout and machine type for complex builds
timeout: '600s'
options:
  machineType: 'E2_STANDARD_2'
EOF

    log_success "Batch processing application created in ${app_dir}/"
    echo "${app_dir}"
}

# Function to build and deploy container image
build_container_image() {
    log_info "Building and deploying container image..."
    
    local app_dir="$1"
    cd "${app_dir}"
    
    # Submit build to Cloud Build
    gcloud builds submit \
        --config cloudbuild.yaml \
        --substitutions "_REGISTRY_NAME=${REGISTRY_NAME},_REGION=${REGION}" \
        .
    
    # Verify image was pushed
    if gcloud artifacts docker images list "${REGION}-docker.pkg.dev/${PROJECT_ID}/${REGISTRY_NAME}/batch-processor" &>/dev/null; then
        log_success "Container image built and deployed: ${IMAGE_URL}"
    else
        log_error "Failed to build or deploy container image"
        exit 1
    fi
    
    cd ..
}

# Function to create Cloud Run Job
create_cloud_run_job() {
    log_info "Creating Cloud Run Job..."
    
    # Check if job already exists
    if gcloud run jobs describe "${JOB_NAME}" --region="${REGION}" &>/dev/null; then
        log_warning "Cloud Run Job '${JOB_NAME}' already exists"
        return 0
    fi
    
    # Create Cloud Run Job
    gcloud run jobs create "${JOB_NAME}" \
        --image="${IMAGE_URL}" \
        --region="${REGION}" \
        --task-timeout=3600 \
        --parallelism=1 \
        --tasks=1 \
        --max-retries=3 \
        --cpu=1 \
        --memory=2Gi \
        --set-env-vars="BUCKET_NAME=${BUCKET_NAME},BATCH_SIZE=10" \
        --service-account="${PROJECT_ID}@appspot.gserviceaccount.com"
    
    log_success "Cloud Run Job created: ${JOB_NAME}"
}

# Function to create sample data files
create_sample_data() {
    log_info "Creating sample data files..."
    
    # Create sample data files
    cat > sample1.txt << 'EOF'
Sample data for batch processing - File 1
Transaction,Amount,Date
TXN001,150.00,2025-01-01
TXN002,75.50,2025-01-02
EOF

    cat > sample2.csv << 'EOF'
Sample data for batch processing - File 2
Customer,Revenue,Quarter
CUST001,25000,Q1
CUST002,18500,Q1
EOF

    # Upload sample files to Cloud Storage
    gsutil cp sample1.txt "gs://${BUCKET_NAME}/input/"
    gsutil cp sample2.csv "gs://${BUCKET_NAME}/input/"
    
    # Clean up local files
    rm -f sample1.txt sample2.csv
    
    log_success "Sample data files uploaded to gs://${BUCKET_NAME}/input/"
}

# Function to test Cloud Run Job
test_cloud_run_job() {
    log_info "Testing Cloud Run Job..."
    
    # Execute job and wait for completion
    local execution_name
    execution_name=$(gcloud run jobs execute "${JOB_NAME}" \
        --region="${REGION}" \
        --format="value(name)" \
        --wait 2>/dev/null || echo "")
    
    if [ -n "${execution_name}" ]; then
        log_success "Cloud Run Job executed successfully: ${execution_name}"
        
        # Check for processed files
        if gsutil ls "gs://${BUCKET_NAME}/output/" &>/dev/null; then
            log_success "Processed files found in output directory"
        else
            log_warning "No processed files found in output directory"
        fi
    else
        log_error "Failed to execute Cloud Run Job"
        exit 1
    fi
}

# Function to create Cloud Scheduler job
create_scheduler_job() {
    log_info "Creating Cloud Scheduler job..."
    
    # Check if scheduler job already exists
    if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" --location="${REGION}" &>/dev/null; then
        log_warning "Cloud Scheduler job '${SCHEDULER_JOB_NAME}' already exists"
        return 0
    fi
    
    # Create scheduled job
    gcloud scheduler jobs create http "${SCHEDULER_JOB_NAME}" \
        --location="${REGION}" \
        --schedule="0 * * * *" \
        --time-zone="America/New_York" \
        --uri="https://run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${PROJECT_ID}/jobs/${JOB_NAME}:run" \
        --http-method=POST \
        --oauth-service-account-email="${PROJECT_ID}@appspot.gserviceaccount.com" \
        --headers="Content-Type=application/json" \
        --message-body='{}' \
        --description="Automated batch processing job execution"
    
    log_success "Cloud Scheduler job created: ${SCHEDULER_JOB_NAME}"
    log_info "Schedule: Every hour on the hour (0 * * * *)"
}

# Function to setup monitoring
setup_monitoring() {
    log_info "Setting up monitoring and alerting..."
    
    # Create log-based metric
    if ! gcloud logging metrics describe batch_job_executions &>/dev/null; then
        gcloud logging metrics create batch_job_executions \
            --description="Count of batch job executions" \
            --log-filter="resource.type=\"cloud_run_job\" AND resource.labels.job_name=\"${JOB_NAME}\""
        
        log_success "Log-based metric created: batch_job_executions"
    else
        log_warning "Log-based metric 'batch_job_executions' already exists"
    fi
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== Deployment Summary ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Cloud Run Job: ${JOB_NAME}"
    echo "Artifact Registry: ${REGISTRY_NAME}"
    echo "Storage Bucket: ${BUCKET_NAME}"
    echo "Scheduler Job: ${SCHEDULER_JOB_NAME}"
    echo "Container Image: ${IMAGE_URL}"
    echo
    echo "=== Next Steps ==="
    echo "1. Check job logs: gcloud logging read \"resource.type=cloud_run_job AND resource.labels.job_name=${JOB_NAME}\" --limit=20"
    echo "2. View scheduler status: gcloud scheduler jobs describe ${SCHEDULER_JOB_NAME} --location=${REGION}"
    echo "3. Check processed files: gsutil ls gs://${BUCKET_NAME}/output/"
    echo "4. Monitor job executions: gcloud run jobs executions list --job=${JOB_NAME} --region=${REGION}"
    echo
    echo "=== Cleanup ==="
    echo "To clean up resources, run: ./destroy.sh"
    echo
}

# Main deployment function
main() {
    log_info "Starting batch processing deployment..."
    
    # Check prerequisites
    check_command "gcloud"
    check_command "gsutil"
    check_command "docker"
    check_command "openssl"
    check_gcloud_auth
    
    # Generate resource names
    generate_resource_names
    
    # Setup project and enable APIs
    setup_project
    check_apis
    
    # Create infrastructure components
    create_artifact_registry
    create_storage_bucket
    
    # Create and deploy application
    local app_dir
    app_dir=$(create_batch_application)
    build_container_image "${app_dir}"
    
    # Create Cloud Run Job and test
    create_cloud_run_job
    create_sample_data
    test_cloud_run_job
    
    # Create scheduler and monitoring
    create_scheduler_job
    setup_monitoring
    
    # Clean up temporary files
    rm -rf "${app_dir}"
    
    # Display summary
    display_summary
    
    log_success "Batch processing deployment completed successfully!"
}

# Run main function
main "$@"