#!/bin/bash

# QR Code Generator with Cloud Run and Storage - Deployment Script
# This script deploys a containerized QR code generator API using Google Cloud Run
# and Cloud Storage following the recipe implementation.

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Script configuration with defaults
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEPLOYMENT_TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Default values (can be overridden by environment variables)
PROJECT_ID="${PROJECT_ID:-qr-generator-$(date +%s)}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-qr-code-api}"
BUCKET_NAME="${BUCKET_NAME:-qr-codes-$(openssl rand -hex 3 2>/dev/null || echo "fallback$(date +%s)")}"
DRY_RUN="${DRY_RUN:-false}"

# Application source files
readonly APP_DIR="${SCRIPT_DIR}/../app"
readonly DOCKERFILE_PATH="${APP_DIR}/Dockerfile"
readonly MAIN_PY_PATH="${APP_DIR}/main.py"
readonly REQUIREMENTS_PATH="${APP_DIR}/requirements.txt"

# Deployment log file
readonly LOG_FILE="${SCRIPT_DIR}/deploy-${DEPLOYMENT_TIMESTAMP}.log"

# Cleanup function for script exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed. Check logs at: ${LOG_FILE}"
        log_info "To clean up partial resources, run: ./destroy.sh"
    fi
    return $exit_code
}

trap cleanup EXIT

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_deps=()
    
    # Check required commands
    if ! command_exists gcloud; then
        missing_deps+=("Google Cloud CLI (gcloud)")
    fi
    
    if ! command_exists gsutil; then
        missing_deps+=("Google Cloud Storage utilities (gsutil)")
    fi
    
    if ! command_exists openssl; then
        missing_deps+=("OpenSSL")
    fi
    
    if ! command_exists jq; then
        log_warn "jq not found - JSON output will not be formatted"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth application-default print-access-token &>/dev/null; then
        missing_deps+=("Google Cloud authentication - run 'gcloud auth application-default login'")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing prerequisites:"
        printf '%s\n' "${missing_deps[@]}" | sed 's/^/  - /'
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to validate environment variables and inputs
validate_inputs() {
    log_info "Validating inputs..."
    
    # Validate project ID format
    if [[ ! $PROJECT_ID =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        log_error "Invalid PROJECT_ID format. Must be 6-30 characters, lowercase letters, digits, and hyphens only."
        exit 1
    fi
    
    # Validate region format
    if [[ ! $REGION =~ ^[a-z]+-[a-z]+[0-9]+$ ]]; then
        log_error "Invalid REGION format. Example: us-central1"
        exit 1
    fi
    
    # Validate service name
    if [[ ! $SERVICE_NAME =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
        log_error "Invalid SERVICE_NAME. Must start with lowercase letter, contain only lowercase letters, digits, and hyphens."
        exit 1
    fi
    
    log_success "Input validation passed"
}

# Function to check if project exists, create if needed
setup_project() {
    log_info "Setting up Google Cloud project: ${PROJECT_ID}"
    
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_info "Project ${PROJECT_ID} already exists"
    else
        log_info "Creating new project: ${PROJECT_ID}"
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create project: ${PROJECT_ID}"
        else
            gcloud projects create "${PROJECT_ID}" \
                --name="QR Code Generator Project - ${DEPLOYMENT_TIMESTAMP}" \
                --labels="environment=development,created-by=recipe-script,deployment-time=${DEPLOYMENT_TIMESTAMP}" 2>&1 | tee -a "${LOG_FILE}"
        fi
    fi
    
    # Set default project and region
    if [[ "$DRY_RUN" == "false" ]]; then
        gcloud config set project "${PROJECT_ID}" 2>&1 | tee -a "${LOG_FILE}"
        gcloud config set compute/region "${REGION}" 2>&1 | tee -a "${LOG_FILE}"
    fi
    
    log_success "Project setup completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "run.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: ${apis[*]}"
    else
        for api in "${apis[@]}"; do
            log_info "Enabling ${api}..."
            gcloud services enable "${api}" 2>&1 | tee -a "${LOG_FILE}"
        done
        
        # Wait for APIs to be fully enabled
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    log_success "APIs enabled successfully"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: ${BUCKET_NAME}"
    
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warn "Bucket ${BUCKET_NAME} already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create bucket: gs://${BUCKET_NAME}"
        log_info "[DRY RUN] Would set public read access on bucket"
    else
        # Create bucket with appropriate configuration
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            -b on \
            "gs://${BUCKET_NAME}" 2>&1 | tee -a "${LOG_FILE}"
        
        # Enable public read access for generated QR codes
        gsutil iam ch allUsers:objectViewer "gs://${BUCKET_NAME}" 2>&1 | tee -a "${LOG_FILE}"
        
        # Set lifecycle policy to auto-delete old objects (optional)
        cat > /tmp/lifecycle.json << 'EOF'
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {"age": 30}
    }
  ]
}
EOF
        gsutil lifecycle set /tmp/lifecycle.json "gs://${BUCKET_NAME}" 2>&1 | tee -a "${LOG_FILE}"
        rm -f /tmp/lifecycle.json
    fi
    
    log_success "Storage bucket created: gs://${BUCKET_NAME}"
}

# Function to create application files
create_application_files() {
    log_info "Creating application files..."
    
    # Create app directory
    mkdir -p "${APP_DIR}"
    
    # Create requirements.txt
    cat > "${REQUIREMENTS_PATH}" << 'EOF'
Flask==3.0.3
gunicorn==22.0.0
qrcode[pil]==7.4.2
google-cloud-storage==2.18.0
Pillow==10.4.0
EOF
    
    # Create main.py (QR Code API application)
    cat > "${MAIN_PY_PATH}" << 'EOF'
import os
import io
import uuid
from datetime import datetime
from flask import Flask, request, jsonify
from google.cloud import storage
import qrcode
from PIL import Image

app = Flask(__name__)

# Initialize Cloud Storage client
storage_client = storage.Client()
bucket_name = os.environ.get('BUCKET_NAME')
if not bucket_name:
    raise ValueError("BUCKET_NAME environment variable is required")
bucket = storage_client.bucket(bucket_name)

@app.route('/')
def health_check():
    """Health check endpoint for Cloud Run"""
    return jsonify({
        'status': 'healthy',
        'service': 'QR Code Generator',
        'timestamp': datetime.utcnow().isoformat(),
        'bucket': bucket_name
    })

@app.route('/generate', methods=['POST'])
def generate_qr_code():
    """Generate QR code and store in Cloud Storage"""
    try:
        # Get data from request
        data = request.get_json()
        if not data or 'text' not in data:
            return jsonify({'error': 'Missing text parameter'}), 400
        
        text_to_encode = data['text']
        if len(text_to_encode) > 2000:
            return jsonify({'error': 'Text too long (max 2000 characters)'}), 400
        
        # Generate unique filename
        file_id = str(uuid.uuid4())
        filename = f"qr-{file_id}.png"
        
        # Create QR code with optimal settings
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(text_to_encode)
        qr.make(fit=True)
        
        # Create image
        img = qr.make_image(fill_color="black", back_color="white")
        
        # Convert to bytes
        img_bytes = io.BytesIO()
        img.save(img_bytes, format='PNG', optimize=True)
        img_bytes.seek(0)
        
        # Upload to Cloud Storage with metadata
        blob = bucket.blob(filename)
        blob.metadata = {
            'created_at': datetime.utcnow().isoformat(),
            'text_length': str(len(text_to_encode)),
            'generated_by': 'qr-code-api'
        }
        blob.upload_from_file(img_bytes, content_type='image/png')
        
        # Make the blob publicly accessible
        blob.make_public()
        
        # Return response with public URL
        public_url = blob.public_url
        
        return jsonify({
            'success': True,
            'qr_code_url': public_url,
            'filename': filename,
            'text_encoded': text_to_encode,
            'created_at': datetime.utcnow().isoformat()
        })
        
    except Exception as e:
        app.logger.error(f"Error generating QR code: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/list', methods=['GET'])
def list_qr_codes():
    """List all QR codes in the bucket"""
    try:
        blobs = bucket.list_blobs(prefix='qr-', max_results=100)
        qr_codes = []
        
        for blob in blobs:
            if blob.name.startswith('qr-') and blob.name.endswith('.png'):
                qr_codes.append({
                    'filename': blob.name,
                    'url': blob.public_url,
                    'created': blob.time_created.isoformat() if blob.time_created else None,
                    'size': blob.size,
                    'metadata': blob.metadata or {}
                })
        
        return jsonify({
            'qr_codes': qr_codes,
            'count': len(qr_codes),
            'bucket': bucket_name
        })
        
    except Exception as e:
        app.logger.error(f"Error listing QR codes: {str(e)}")
        return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(debug=False, host='0.0.0.0', port=port)
EOF
    
    # Create Dockerfile
    cat > "${DOCKERFILE_PATH}" << 'EOF'
# Use the official Python runtime as base image
FROM python:3.12-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Set work directory
WORKDIR /app

# Install system dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gcc \
        libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash app \
    && chown -R app:app /app
USER app

# Expose port 8080 (Cloud Run requirement)
EXPOSE 8080

# Command to run the application
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 \
    --timeout 30 --keep-alive 2 main:app
EOF
    
    log_success "Application files created in ${APP_DIR}"
}

# Function to deploy to Cloud Run
deploy_to_cloud_run() {
    log_info "Deploying application to Cloud Run..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy service: ${SERVICE_NAME}"
        log_info "[DRY RUN] Would set environment variables: BUCKET_NAME=${BUCKET_NAME}"
        return 0
    fi
    
    # Change to app directory for deployment
    cd "${APP_DIR}"
    
    # Deploy to Cloud Run from source code
    gcloud run deploy "${SERVICE_NAME}" \
        --source . \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --set-env-vars "BUCKET_NAME=${BUCKET_NAME}" \
        --memory 512Mi \
        --cpu 1 \
        --concurrency 100 \
        --max-instances 10 \
        --min-instances 0 \
        --port 8080 \
        --timeout 300 \
        --labels "environment=development,created-by=recipe-script,deployment-time=${DEPLOYMENT_TIMESTAMP}" \
        --quiet 2>&1 | tee -a "${LOG_FILE}"
    
    # Get the service URL
    SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
        --platform managed \
        --region "${REGION}" \
        --format 'value(status.url)' 2>/dev/null)
    
    if [[ -n "$SERVICE_URL" ]]; then
        log_success "Cloud Run service deployed successfully"
        log_info "Service URL: ${SERVICE_URL}"
        echo "SERVICE_URL=${SERVICE_URL}" >> "${LOG_FILE}"
    else
        log_error "Failed to retrieve service URL"
        return 1
    fi
    
    # Return to script directory
    cd "${SCRIPT_DIR}"
}

# Function to configure IAM permissions
configure_iam_permissions() {
    log_info "Configuring IAM permissions for Cloud Storage access..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure IAM permissions for service account"
        return 0
    fi
    
    # Get the Cloud Run service account
    SERVICE_ACCOUNT=$(gcloud run services describe "${SERVICE_NAME}" \
        --platform managed \
        --region "${REGION}" \
        --format 'value(spec.template.spec.serviceAccountName)' 2>/dev/null)
    
    # If no custom service account, use the default Compute Engine service account
    if [[ -z "$SERVICE_ACCOUNT" ]]; then
        PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" \
            --format='value(projectNumber)' 2>/dev/null)
        SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
    fi
    
    # Grant Storage Object Admin role to the service account
    gsutil iam ch "serviceAccount:${SERVICE_ACCOUNT}:objectAdmin" \
        "gs://${BUCKET_NAME}" 2>&1 | tee -a "${LOG_FILE}"
    
    log_success "IAM permissions configured for Cloud Storage access"
    log_info "Service Account: ${SERVICE_ACCOUNT}"
}

# Function to run validation tests
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    # Get service URL if not already set
    if [[ -z "${SERVICE_URL:-}" ]]; then
        SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
            --platform managed \
            --region "${REGION}" \
            --format 'value(status.url)' 2>/dev/null)
    fi
    
    if [[ -z "$SERVICE_URL" ]]; then
        log_error "Could not retrieve service URL for validation"
        return 1
    fi
    
    log_info "Testing service health check..."
    local health_response
    health_response=$(curl -s -f "${SERVICE_URL}/" 2>/dev/null) || {
        log_error "Health check failed"
        return 1
    }
    
    if echo "$health_response" | grep -q '"status": "healthy"'; then
        log_success "Health check passed"
    else
        log_error "Health check returned unexpected response"
        return 1
    fi
    
    log_info "Testing QR code generation..."
    local test_response
    test_response=$(curl -s -f -X POST "${SERVICE_URL}/generate" \
        -H "Content-Type: application/json" \
        -d '{"text": "https://cloud.google.com/run"}' 2>/dev/null) || {
        log_error "QR code generation test failed"
        return 1
    }
    
    if echo "$test_response" | grep -q '"success": true'; then
        log_success "QR code generation test passed"
        local qr_url
        qr_url=$(echo "$test_response" | grep -o '"qr_code_url": "[^"]*"' | cut -d'"' -f4)
        if [[ -n "$qr_url" ]]; then
            log_info "Test QR code available at: ${qr_url}"
        fi
    else
        log_error "QR code generation test failed"
        return 1
    fi
    
    log_success "Deployment validation completed successfully"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=========================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Service Name: ${SERVICE_NAME}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        local service_url
        service_url=$(gcloud run services describe "${SERVICE_NAME}" \
            --platform managed \
            --region "${REGION}" \
            --format 'value(status.url)' 2>/dev/null)
        
        if [[ -n "$service_url" ]]; then
            echo "Service URL: ${service_url}"
            echo ""
            echo "API Endpoints:"
            echo "  Health Check: ${service_url}/"
            echo "  Generate QR:  ${service_url}/generate (POST)"
            echo "  List QR Codes: ${service_url}/list (GET)"
            echo ""
            echo "Example usage:"
            echo "  curl -X POST ${service_url}/generate \\"
            echo "    -H 'Content-Type: application/json' \\"
            echo "    -d '{\"text\": \"Your text here\"}'"
        fi
    fi
    
    echo "=========================="
    echo "Logs saved to: ${LOG_FILE}"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "To clean up resources, run: ./destroy.sh"
        echo "To monitor the service: gcloud run services logs tail ${SERVICE_NAME} --region=${REGION}"
    fi
}

# Function to display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy QR Code Generator with Cloud Run and Storage

OPTIONS:
    -p, --project       Google Cloud Project ID (default: qr-generator-\$(date +%s))
    -r, --region        GCP region (default: us-central1)
    -s, --service       Cloud Run service name (default: qr-code-api)
    -b, --bucket        Storage bucket name (default: qr-codes-\$(random))
    -d, --dry-run       Show what would be done without making changes
    -h, --help          Show this help message
    
ENVIRONMENT VARIABLES:
    PROJECT_ID          Override default project ID
    REGION              Override default region
    SERVICE_NAME        Override default service name
    BUCKET_NAME         Override default bucket name
    DRY_RUN             Set to 'true' for dry run mode

EXAMPLES:
    $0                                  # Deploy with default settings
    $0 -p my-project -r us-west1        # Deploy to specific project and region
    $0 --dry-run                        # Show what would be deployed
    DRY_RUN=true $0                     # Dry run using environment variable

EOF
}

# Main deployment function
main() {
    log_info "Starting QR Code Generator deployment..."
    log_info "Deployment ID: ${DEPLOYMENT_TIMESTAMP}"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -s|--service)
                SERVICE_NAME="$2"
                shift 2
                ;;
            -b|--bucket)
                BUCKET_NAME="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN="true"
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
    
    # Start logging
    {
        echo "Deployment started at: $(date)"
        echo "Script: $0"
        echo "Arguments: $*"
        echo "PROJECT_ID=${PROJECT_ID}"
        echo "REGION=${REGION}"
        echo "SERVICE_NAME=${SERVICE_NAME}"
        echo "BUCKET_NAME=${BUCKET_NAME}"
        echo "DRY_RUN=${DRY_RUN}"
        echo "=========================="
    } > "${LOG_FILE}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE - No resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    validate_inputs
    setup_project
    enable_apis
    create_storage_bucket
    create_application_files
    deploy_to_cloud_run
    configure_iam_permissions
    validate_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo ""
        echo "Next steps:"
        echo "1. Test your QR code API using the endpoints shown above"
        echo "2. Monitor your service with Cloud Run logs"
        echo "3. Set up monitoring and alerting as needed"
        echo "4. Consider implementing authentication for production use"
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi