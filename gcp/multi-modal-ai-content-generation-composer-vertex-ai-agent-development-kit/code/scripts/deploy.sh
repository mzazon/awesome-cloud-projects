#!/bin/bash

# Multi-Modal AI Content Generation Pipeline Deployment Script
# This script deploys a complete content generation pipeline using Cloud Composer, 
# Vertex AI Agent Development Kit, and Cloud Run for enterprise-scale content automation.

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.env"

# Default values
DEFAULT_PROJECT_ID="content-pipeline-$(date +%s)"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DEFAULT_COMPOSER_ENV_NAME="multi-modal-content-pipeline"

# Functions for logging and output
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO] $*${NC}" | tee -a "${LOG_FILE}"
}

log_warn() {
    echo -e "${YELLOW}[WARN] $*${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR] $*${NC}" | tee -a "${LOG_FILE}"
}

# Error handling function
handle_error() {
    local line_no=$1
    local error_code=$2
    log_error "An error occurred on line ${line_no}: exit code ${error_code}"
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    exit "${error_code}"
}

trap 'handle_error ${LINENO} $?' ERR

# Display banner
show_banner() {
    echo -e "${BLUE}"
    echo "=================================================================="
    echo "  Multi-Modal AI Content Generation Pipeline Deployment"
    echo "  Google Cloud Platform - Enterprise Scale"
    echo "=================================================================="
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log_info "gcloud SDK version: ${gcloud_version}"
    
    # Check if curl is available for API calls
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required but not installed."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Load or create configuration
setup_configuration() {
    log_info "Setting up configuration..."
    
    if [[ -f "${CONFIG_FILE}" ]]; then
        log_info "Loading existing configuration from ${CONFIG_FILE}"
        # shellcheck source=/dev/null
        source "${CONFIG_FILE}"
    else
        log_info "Creating new configuration..."
        
        # Set default values or prompt for input
        PROJECT_ID="${PROJECT_ID:-$DEFAULT_PROJECT_ID}"
        REGION="${REGION:-$DEFAULT_REGION}"
        ZONE="${ZONE:-$DEFAULT_ZONE}"
        COMPOSER_ENV_NAME="${COMPOSER_ENV_NAME:-$DEFAULT_COMPOSER_ENV_NAME}"
        
        # Generate unique suffix for resource names
        RANDOM_SUFFIX=$(openssl rand -hex 4)
        STORAGE_BUCKET="content-pipeline-${RANDOM_SUFFIX}"
        CLOUD_RUN_SERVICE="content-api-${RANDOM_SUFFIX}"
        
        # Save configuration
        cat > "${CONFIG_FILE}" << EOF
# Multi-Modal AI Content Generation Pipeline Configuration
PROJECT_ID="${PROJECT_ID}"
REGION="${REGION}"
ZONE="${ZONE}"
COMPOSER_ENV_NAME="${COMPOSER_ENV_NAME}"
STORAGE_BUCKET="${STORAGE_BUCKET}"
CLOUD_RUN_SERVICE="${CLOUD_RUN_SERVICE}"
RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF
        
        log "Configuration saved to ${CONFIG_FILE}"
    fi
    
    # Display configuration
    log_info "Current configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Zone: ${ZONE}"
    log_info "  Composer Environment: ${COMPOSER_ENV_NAME}"
    log_info "  Storage Bucket: ${STORAGE_BUCKET}"
    log_info "  Cloud Run Service: ${CLOUD_RUN_SERVICE}"
}

# Set gcloud configuration
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log "gcloud configuration updated"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "composer.googleapis.com"
        "aiplatform.googleapis.com"
        "storage.googleapis.com"
        "run.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log "Successfully enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled (30 seconds)..."
    sleep 30
    
    log "All required APIs enabled successfully"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${STORAGE_BUCKET}" &> /dev/null; then
        log_warn "Storage bucket gs://${STORAGE_BUCKET} already exists"
        return 0
    fi
    
    # Create bucket with standard storage class
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${STORAGE_BUCKET}"; then
        log "Storage bucket gs://${STORAGE_BUCKET} created successfully"
    else
        log_error "Failed to create storage bucket"
        exit 1
    fi
    
    # Enable versioning for content version control
    if gsutil versioning set on "gs://${STORAGE_BUCKET}"; then
        log "Versioning enabled for storage bucket"
    else
        log_warn "Failed to enable versioning for storage bucket"
    fi
    
    # Create directory structure
    echo "Content pipeline initialized" | gsutil cp - "gs://${STORAGE_BUCKET}/content/.gitkeep"
    echo "Brief storage initialized" | gsutil cp - "gs://${STORAGE_BUCKET}/briefs/.gitkeep"
    echo "DAG storage initialized" | gsutil cp - "gs://${STORAGE_BUCKET}/dags/.gitkeep"
    
    log "Storage bucket structure created"
}

# Create Cloud Composer environment
create_composer_environment() {
    log_info "Creating Cloud Composer environment..."
    
    # Check if environment already exists
    if gcloud composer environments describe "${COMPOSER_ENV_NAME}" \
        --location "${REGION}" &> /dev/null; then
        log_warn "Composer environment ${COMPOSER_ENV_NAME} already exists"
        return 0
    fi
    
    log_info "Creating Composer environment (this may take 15-20 minutes)..."
    
    # Create Composer 2 environment with optimized configuration
    if gcloud composer environments create "${COMPOSER_ENV_NAME}" \
        --location "${REGION}" \
        --image-version "composer-2.9.1-airflow-2.9.3" \
        --node-count 3 \
        --machine-type "n1-standard-2" \
        --disk-size "50GB" \
        --python-version 3 \
        --env-variables "PROJECT_ID=${PROJECT_ID},REGION=${REGION},STORAGE_BUCKET=${STORAGE_BUCKET}" \
        --quiet; then
        log "Composer environment created successfully"
    else
        log_error "Failed to create Composer environment"
        exit 1
    fi
    
    # Wait for environment to be fully ready
    log_info "Waiting for Composer environment to be ready..."
    if gcloud composer environments wait "${COMPOSER_ENV_NAME}" \
        --location "${REGION}" \
        --timeout 1200; then
        log "Composer environment is ready"
    else
        log_error "Composer environment creation timed out"
        exit 1
    fi
}

# Install dependencies in Composer environment
install_composer_dependencies() {
    log_info "Installing dependencies in Composer environment..."
    
    # Get Composer environment bucket
    local composer_bucket
    composer_bucket=$(gcloud composer environments describe \
        "${COMPOSER_ENV_NAME}" --location "${REGION}" \
        --format="value(config.dagGcsPrefix)" | sed 's|/dags||')
    
    if [[ -z "${composer_bucket}" ]]; then
        log_error "Failed to get Composer bucket path"
        exit 1
    fi
    
    # Create requirements.txt for ADK and dependencies
    cat > "${SCRIPT_DIR}/requirements.txt" << 'EOF'
google-cloud-adk>=1.5.0
google-cloud-aiplatform>=1.48.0
google-cloud-storage>=2.13.0
google-cloud-run>=0.10.0
apache-airflow-providers-google>=10.12.0
pillow>=10.2.0
moviepy>=1.0.3
google-generativeai>=0.5.0
flask>=2.3.0
gunicorn>=20.1.0
EOF
    
    # Upload requirements to Composer environment
    if gsutil cp "${SCRIPT_DIR}/requirements.txt" "${composer_bucket}/requirements.txt"; then
        log "Dependencies uploaded to Composer environment"
    else
        log_error "Failed to upload dependencies"
        exit 1
    fi
    
    # Clean up local requirements file
    rm -f "${SCRIPT_DIR}/requirements.txt"
    
    log "Composer dependencies configured successfully"
}

# Deploy DAG files
deploy_dags() {
    log_info "Deploying Airflow DAGs..."
    
    # Get Composer environment DAG bucket
    local dag_bucket
    dag_bucket=$(gcloud composer environments describe \
        "${COMPOSER_ENV_NAME}" --location "${REGION}" \
        --format="value(config.dagGcsPrefix)")
    
    if [[ -z "${dag_bucket}" ]]; then
        log_error "Failed to get DAG bucket path"
        exit 1
    fi
    
    # Create the content generation DAG
    cat > "${SCRIPT_DIR}/content_generation_dag.py" << 'EOF'
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python_operator import PythonOperator
from airflow.providers.google.cloud.operators.vertex_ai import VertexAIModelDeployOperator
from google.cloud import storage, aiplatform
import os
import json

# DAG configuration for multi-modal content pipeline
default_args = {
    'owner': 'content-team',
    'depends_on_past': False,
    'start_date': datetime(2025, 7, 12),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'multi_modal_content_generation',
    default_args=default_args,
    description='Orchestrate AI agents for content generation',
    schedule_interval='@daily',
    max_active_runs=1,
    catchup=False,
    tags=['content', 'ai', 'multi-modal', 'adk']
)

def initialize_content_strategy(**context):
    """Content Strategy Agent initialization and brief processing"""
    try:
        # Simulate content strategy processing
        content_brief = context['dag_run'].conf.get('content_brief', {})
        
        strategy_response = {
            'strategy': f"Content strategy for {content_brief.get('topic', 'general content')}",
            'target_audience': content_brief.get('target_audience', 'general'),
            'brand_guidelines': content_brief.get('brand_guidelines', {}),
            'content_type': content_brief.get('content_type', 'multi-modal')
        }
        
        # Store strategy in Cloud Storage
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ['STORAGE_BUCKET'])
        
        strategy_blob = bucket.blob(f"content/{context['ds']}/strategy.json")
        strategy_blob.upload_from_string(json.dumps(strategy_response, indent=2))
        
        return strategy_response
        
    except Exception as e:
        print(f"Error in strategy initialization: {str(e)}")
        raise

def generate_text_content(**context):
    """Text Generation Agent for creating written content"""
    try:
        # Retrieve strategy from upstream task
        strategy_data = context['task_instance'].xcom_pull(task_ids='initialize_strategy')
        
        # Simulate text content generation
        text_content = f"Generated text content for {strategy_data['content_type']}"
        
        # Store generated content in Cloud Storage
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ['STORAGE_BUCKET'])
        
        text_blob = bucket.blob(f"content/{context['ds']}/text_content.txt")
        text_blob.upload_from_string(text_content)
        
        return {
            'text_content_path': f"gs://{os.environ['STORAGE_BUCKET']}/content/{context['ds']}/text_content.txt",
            'word_count': len(text_content.split()),
            'content_type': 'text'
        }
        
    except Exception as e:
        print(f"Error in text generation: {str(e)}")
        raise

def generate_image_content(**context):
    """Image Generation Agent for creating visual content"""
    try:
        strategy_data = context['task_instance'].xcom_pull(task_ids='initialize_strategy')
        
        # Simulate image content generation
        image_metadata = {
            'image_prompts': f"Generated image prompts for {strategy_data['content_type']}",
            'generated_images': [],
            'style_guidelines': strategy_data.get('brand_guidelines', {})
        }
        
        # Store image metadata
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ['STORAGE_BUCKET'])
        
        metadata_blob = bucket.blob(f"content/{context['ds']}/image_metadata.json")
        metadata_blob.upload_from_string(json.dumps(image_metadata, indent=2))
        
        return {
            'image_metadata_path': f"gs://{os.environ['STORAGE_BUCKET']}/content/{context['ds']}/image_metadata.json",
            'content_type': 'image'
        }
        
    except Exception as e:
        print(f"Error in image generation: {str(e)}")
        raise

def quality_review_content(**context):
    """Quality Review Agent for content validation and optimization"""
    try:
        # Retrieve content from all generation tasks
        text_data = context['task_instance'].xcom_pull(task_ids='generate_text')
        image_data = context['task_instance'].xcom_pull(task_ids='generate_images')
        strategy_data = context['task_instance'].xcom_pull(task_ids='initialize_strategy')
        
        # Simulate quality review
        review_results = {
            'review_status': 'completed',
            'quality_score': 85,
            'recommendations': 'Content meets quality standards',
            'approved_for_publishing': True,
            'review_timestamp': context['ts']
        }
        
        # Store review results
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ['STORAGE_BUCKET'])
        
        review_blob = bucket.blob(f"content/{context['ds']}/quality_review.json")
        review_blob.upload_from_string(json.dumps(review_results, indent=2))
        
        return review_results
        
    except Exception as e:
        print(f"Error in quality review: {str(e)}")
        raise

# Define task dependencies
strategy_task = PythonOperator(
    task_id='initialize_strategy',
    python_callable=initialize_content_strategy,
    dag=dag
)

text_task = PythonOperator(
    task_id='generate_text',
    python_callable=generate_text_content,
    dag=dag
)

image_task = PythonOperator(
    task_id='generate_images',
    python_callable=generate_image_content,
    dag=dag
)

review_task = PythonOperator(
    task_id='quality_review',
    python_callable=quality_review_content,
    dag=dag
)

# Set task dependencies for orchestrated execution
strategy_task >> [text_task, image_task] >> review_task
EOF
    
    # Upload DAG to Composer environment
    if gsutil cp "${SCRIPT_DIR}/content_generation_dag.py" "${dag_bucket}/"; then
        log "DAG uploaded successfully"
    else
        log_error "Failed to upload DAG"
        exit 1
    fi
    
    # Clean up local DAG file
    rm -f "${SCRIPT_DIR}/content_generation_dag.py"
    
    log "DAGs deployed successfully"
}

# Build and deploy Cloud Run service
deploy_cloud_run_service() {
    log_info "Building and deploying Cloud Run service..."
    
    # Create content API application
    cat > "${SCRIPT_DIR}/content_api.py" << 'EOF'
from flask import Flask, request, jsonify
from google.cloud import storage
import os
import json
import uuid
from datetime import datetime

app = Flask(__name__)

@app.route('/generate-content', methods=['POST'])
def generate_content():
    """Trigger multi-modal content generation pipeline"""
    try:
        content_brief = request.get_json()
        
        # Validate content brief
        required_fields = ['target_audience', 'content_type', 'brand_guidelines']
        if not all(field in content_brief for field in required_fields):
            return jsonify({'error': 'Missing required fields'}), 400
        
        # Generate unique content ID
        content_id = str(uuid.uuid4())
        
        # Store content brief for DAG access
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ['STORAGE_BUCKET'])
        brief_blob = bucket.blob(f"briefs/{content_id}/content_brief.json")
        brief_blob.upload_from_string(json.dumps(content_brief, indent=2))
        
        response_data = {
            'content_id': content_id,
            'status': 'initiated',
            'pipeline_status': 'ready_to_run',
            'estimated_completion': '15-20 minutes',
            'brief_location': f"gs://{os.environ['STORAGE_BUCKET']}/briefs/{content_id}/content_brief.json"
        }
        
        return jsonify(response_data), 202
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/content-status/<content_id>', methods=['GET'])
def get_content_status(content_id):
    """Check content generation status"""
    try:
        storage_client = storage.Client()
        bucket = storage_client.bucket(os.environ['STORAGE_BUCKET'])
        
        # Check for completed content
        review_blob = bucket.blob(f"content/{content_id}/quality_review.json")
        
        if review_blob.exists():
            review_data = json.loads(review_blob.download_as_text())
            return jsonify({
                'content_id': content_id,
                'status': 'completed',
                'quality_score': review_data.get('quality_score', 0),
                'approved': review_data.get('approved_for_publishing', False),
                'content_location': f"gs://{os.environ['STORAGE_BUCKET']}/content/{content_id}/"
            })
        else:
            return jsonify({
                'content_id': content_id,
                'status': 'processing',
                'message': 'Content generation in progress'
            })
            
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': datetime.utcnow().isoformat()})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF
    
    # Create Dockerfile
    cat > "${SCRIPT_DIR}/Dockerfile" << 'EOF'
FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY content_api.py .

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 content_api:app
EOF
    
    # Create requirements.txt for Cloud Run
    cat > "${SCRIPT_DIR}/requirements.txt" << 'EOF'
flask>=2.3.0
google-cloud-storage>=2.13.0
gunicorn>=20.1.0
EOF
    
    # Build and submit container
    log_info "Building container image..."
    if gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${CLOUD_RUN_SERVICE}" "${SCRIPT_DIR}"; then
        log "Container image built successfully"
    else
        log_error "Failed to build container image"
        exit 1
    fi
    
    # Deploy to Cloud Run
    log_info "Deploying to Cloud Run..."
    if gcloud run deploy "${CLOUD_RUN_SERVICE}" \
        --image "gcr.io/${PROJECT_ID}/${CLOUD_RUN_SERVICE}" \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION},STORAGE_BUCKET=${STORAGE_BUCKET},COMPOSER_ENV_NAME=${COMPOSER_ENV_NAME}" \
        --memory 2Gi \
        --cpu 2 \
        --max-instances 10 \
        --quiet; then
        log "Cloud Run service deployed successfully"
    else
        log_error "Failed to deploy Cloud Run service"
        exit 1
    fi
    
    # Get service URL
    local service_url
    service_url=$(gcloud run services describe "${CLOUD_RUN_SERVICE}" \
        --region "${REGION}" \
        --format="value(status.url)")
    
    echo "CONTENT_API_URL=${service_url}" >> "${CONFIG_FILE}"
    
    # Clean up build files
    rm -f "${SCRIPT_DIR}/content_api.py" "${SCRIPT_DIR}/Dockerfile" "${SCRIPT_DIR}/requirements.txt"
    
    log "Cloud Run service deployed at: ${service_url}"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Source configuration for validation
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
    
    # Check Composer environment
    local composer_status
    composer_status=$(gcloud composer environments describe "${COMPOSER_ENV_NAME}" \
        --location "${REGION}" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    
    if [[ "${composer_status}" == "RUNNING" ]]; then
        log "✅ Composer environment is running"
    else
        log_warn "⚠️  Composer environment status: ${composer_status}"
    fi
    
    # Check storage bucket
    if gsutil ls -b "gs://${STORAGE_BUCKET}" &> /dev/null; then
        log "✅ Storage bucket is accessible"
    else
        log_warn "⚠️  Storage bucket is not accessible"
    fi
    
    # Check Cloud Run service
    local run_status
    run_status=$(gcloud run services describe "${CLOUD_RUN_SERVICE}" \
        --region "${REGION}" --format="value(status.conditions[0].status)" 2>/dev/null || echo "UNKNOWN")
    
    if [[ "${run_status}" == "True" ]]; then
        log "✅ Cloud Run service is healthy"
    else
        log_warn "⚠️  Cloud Run service status: ${run_status}"
    fi
    
    # Test API endpoint if available
    if [[ -n "${CONTENT_API_URL:-}" ]]; then
        if curl -s -f "${CONTENT_API_URL}/health" > /dev/null; then
            log "✅ Content API is responding"
        else
            log_warn "⚠️  Content API health check failed"
        fi
    fi
    
    log "Deployment validation completed"
}

# Display deployment summary
show_deployment_summary() {
    log_info "Deployment Summary"
    echo -e "${BLUE}=================================================================="
    echo "  Multi-Modal AI Content Generation Pipeline"
    echo "  Deployment completed successfully!"
    echo "=================================================================="
    echo -e "${NC}"
    
    # Source configuration for summary
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
    
    echo "📋 Configuration:"
    echo "   Project ID: ${PROJECT_ID}"
    echo "   Region: ${REGION}"
    echo "   Composer Environment: ${COMPOSER_ENV_NAME}"
    echo "   Storage Bucket: gs://${STORAGE_BUCKET}"
    echo "   Cloud Run Service: ${CLOUD_RUN_SERVICE}"
    
    if [[ -n "${CONTENT_API_URL:-}" ]]; then
        echo ""
        echo "🌐 API Endpoints:"
        echo "   Content API: ${CONTENT_API_URL}"
        echo "   Health Check: ${CONTENT_API_URL}/health"
        echo "   Generate Content: ${CONTENT_API_URL}/generate-content"
    fi
    
    # Get Airflow UI URL
    local airflow_uri
    airflow_uri=$(gcloud composer environments describe \
        "${COMPOSER_ENV_NAME}" --location "${REGION}" \
        --format="value(config.airflowUri)" 2>/dev/null || echo "Not available")
    
    if [[ "${airflow_uri}" != "Not available" ]]; then
        echo "   Airflow UI: ${airflow_uri}"
    fi
    
    echo ""
    echo "📚 Next Steps:"
    echo "   1. Access the Airflow UI to monitor DAG execution"
    echo "   2. Test the Content API using the provided endpoints"
    echo "   3. Review the configuration file: ${CONFIG_FILE}"
    echo "   4. Check deployment logs: ${LOG_FILE}"
    echo ""
    echo "⚠️  Remember to run ./destroy.sh when you're done to avoid charges!"
    echo ""
}

# Main deployment function
main() {
    show_banner
    
    log "Starting deployment of Multi-Modal AI Content Generation Pipeline"
    log "Deployment started at $(date)"
    
    # Pre-deployment checks and setup
    check_prerequisites
    setup_configuration
    configure_gcloud
    
    # Core infrastructure deployment
    enable_apis
    create_storage_bucket
    create_composer_environment
    install_composer_dependencies
    deploy_dags
    deploy_cloud_run_service
    
    # Post-deployment validation
    validate_deployment
    show_deployment_summary
    
    log "Deployment completed successfully at $(date)"
    log "Total deployment time: $SECONDS seconds"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi