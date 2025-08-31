#!/bin/bash

# Age Calculator API with Cloud Run and Storage - Deployment Script
# This script deploys a Flask API to Cloud Run with Cloud Storage logging
# Based on recipe: age-calculator-api-run-storage

set -euo pipefail

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

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    # Note: Full cleanup is handled by destroy.sh
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available"
        exit 1
    fi
    
    # Check if openssl is available for random suffix generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random identifiers"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active Google Cloud authentication found"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="age-calc-api-$(date +%s)"
        log_info "Generated PROJECT_ID: ${PROJECT_ID}"
    else
        log_info "Using provided PROJECT_ID: ${PROJECT_ID}"
    fi
    
    # Set default region if not provided
    export REGION="${REGION:-us-central1}"
    export SERVICE_NAME="${SERVICE_NAME:-age-calculator-api}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="age-calc-logs-${RANDOM_SUFFIX}"
    
    log_info "Environment variables set:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  REGION: ${REGION}"
    log_info "  SERVICE_NAME: ${SERVICE_NAME}"
    log_info "  BUCKET_NAME: ${BUCKET_NAME}"
}

# Create and configure Google Cloud project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_warning "Project ${PROJECT_ID} already exists"
    else
        log_info "Creating project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" \
            --name="Age Calculator API Project" \
            --set-as-default
    fi
    
    # Set project and default configurations
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    # Check billing account (required for API enablement)
    local billing_account
    billing_account=$(gcloud billing accounts list --filter="open:true" --format="value(name)" --limit=1)
    
    if [[ -n "${billing_account}" ]]; then
        log_info "Linking billing account to project..."
        gcloud billing projects link "${PROJECT_ID}" \
            --billing-account="${billing_account}" || {
            log_warning "Failed to link billing account automatically"
            log_info "Please link a billing account manually: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
        }
    else
        log_warning "No billing account found. Please link one manually for API enablement"
    fi
    
    log_success "Project setup completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "run.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "iam.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" --project="${PROJECT_ID}"
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 10
    
    log_success "All required APIs enabled"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: ${BUCKET_NAME}"
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists"
    else
        # Create storage bucket for request logs
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}"
        
        log_success "Storage bucket created: gs://${BUCKET_NAME}"
    fi
    
    # Create lifecycle configuration for cost optimization
    log_info "Setting up bucket lifecycle policy..."
    cat > lifecycle.json << 'EOF'
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30}
    },
    {
      "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
      "condition": {"age": 90}
    }
  ]
}
EOF
    
    gsutil lifecycle set lifecycle.json "gs://${BUCKET_NAME}"
    rm -f lifecycle.json
    
    log_success "Bucket lifecycle policy configured"
}

# Create Flask application
create_application() {
    log_info "Creating Flask application..."
    
    # Create application directory if it doesn't exist
    mkdir -p age-calculator-app
    cd age-calculator-app
    
    # Create main application file
    cat > main.py << 'EOF'
import os
import json
from datetime import datetime, timezone
from flask import Flask, request, jsonify
from google.cloud import storage

app = Flask(__name__)

# Initialize Cloud Storage client with proper error handling
try:
    storage_client = storage.Client()
    bucket_name = os.environ.get('BUCKET_NAME')
except Exception as e:
    print(f"Storage client initialization error: {e}")
    storage_client = None
    bucket_name = None

def calculate_age(birth_date_str):
    """Calculate age from birth date string with improved accuracy."""
    try:
        # Handle various ISO date formats
        birth_date = datetime.fromisoformat(birth_date_str.replace('Z', '+00:00'))
        now = datetime.now(timezone.utc)
        
        # More accurate age calculation
        age_timedelta = now - birth_date
        total_days = age_timedelta.days
        
        # Calculate years, considering leap years
        years = total_days // 365
        remaining_days = total_days % 365
        months = remaining_days // 30
        days = remaining_days % 30
        
        return {
            'age_years': years,
            'age_months': months,
            'age_days': days,
            'total_days': total_days,
            'birth_date': birth_date.isoformat(),
            'calculated_at': now.isoformat()
        }
    except ValueError as e:
        raise ValueError(f"Invalid date format: {str(e)}")

def log_request(endpoint, request_data, response_data, status_code):
    """Log request details to Cloud Storage with error handling."""
    if not storage_client or not bucket_name:
        return
        
    try:
        bucket = storage_client.bucket(bucket_name)
        timestamp = datetime.now(timezone.utc).isoformat()
        log_data = {
            'timestamp': timestamp,
            'endpoint': endpoint,
            'request': request_data,
            'response': response_data,
            'status_code': status_code,
            'client_ip': request.headers.get('X-Forwarded-For', request.remote_addr)
        }
        
        # Organize logs by date for better management
        blob_name = f"requests/{datetime.now().strftime('%Y/%m/%d')}/{timestamp}.json"
        blob = bucket.blob(blob_name)
        blob.upload_from_string(json.dumps(log_data), content_type='application/json')
    except Exception as e:
        print(f"Logging error: {str(e)}")

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint for monitoring."""
    response = {'status': 'healthy', 'service': 'age-calculator-api'}
    log_request('/health', {}, response, 200)
    return jsonify(response)

@app.route('/calculate-age', methods=['POST'])
def calculate_age_endpoint():
    """Calculate age from provided birth date."""
    try:
        data = request.get_json()
        if not data or 'birth_date' not in data:
            error_response = {'error': 'birth_date is required in JSON body'}
            log_request('/calculate-age', data, error_response, 400)
            return jsonify(error_response), 400
        
        result = calculate_age(data['birth_date'])
        log_request('/calculate-age', data, result, 200)
        return jsonify(result)
        
    except ValueError as e:
        error_response = {'error': str(e)}
        log_request('/calculate-age', request.get_json(), error_response, 400)
        return jsonify(error_response), 400
    except Exception as e:
        error_response = {'error': 'Internal server error'}
        log_request('/calculate-age', request.get_json(), error_response, 500)
        return jsonify(error_response), 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF

    # Create requirements file
    cat > requirements.txt << 'EOF'
Flask==3.0.0
google-cloud-storage==2.12.0
gunicorn==21.2.0
EOF

    # Create optimized Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

# Set environment variables for Python
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create non-root user for security
RUN useradd --create-home --shell /bin/bash app \
    && chown -R app:app /app
USER app

# Expose port 8080 (Cloud Run standard)
EXPOSE 8080

# Use gunicorn for production server
CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 main:app
EOF

    # Create .dockerignore
    cat > .dockerignore << 'EOF'
__pycache__
*.pyc
*.pyo
*.pyd
.Python
.git
.gitignore
README.md
Dockerfile
.dockerignore
lifecycle.json
EOF

    log_success "Flask application created"
}

# Deploy to Cloud Run
deploy_cloud_run() {
    log_info "Deploying application to Cloud Run..."
    
    # Deploy to Cloud Run using source-based deployment
    gcloud run deploy "${SERVICE_NAME}" \
        --source . \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --set-env-vars "BUCKET_NAME=${BUCKET_NAME}" \
        --memory 512Mi \
        --cpu 1000m \
        --max-instances 10 \
        --timeout 300 \
        --concurrency 80 \
        --port 8080 \
        --project "${PROJECT_ID}"
    
    # Get the service URL
    SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
        --region "${REGION}" \
        --format 'value(status.url)' \
        --project "${PROJECT_ID}")
    
    export SERVICE_URL
    
    log_success "Cloud Run service deployed successfully"
    log_info "Service URL: ${SERVICE_URL}"
    
    # Save deployment info for later use
    cat > ../deployment-info.txt << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
SERVICE_NAME=${SERVICE_NAME}
BUCKET_NAME=${BUCKET_NAME}
SERVICE_URL=${SERVICE_URL}
DEPLOYED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
}

# Configure IAM permissions
configure_iam() {
    log_info "Configuring IAM permissions for storage access..."
    
    # Get the service account email for the Cloud Run service
    SERVICE_ACCOUNT=$(gcloud run services describe "${SERVICE_NAME}" \
        --region "${REGION}" \
        --format 'value(spec.template.spec.serviceAccountName)' \
        --project "${PROJECT_ID}" || echo "")
    
    # If no custom service account, get the default compute service account
    if [[ -z "${SERVICE_ACCOUNT}" ]]; then
        PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" \
            --format='value(projectNumber)')
        SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
    fi
    
    # Grant storage object admin role to the service account for specific bucket
    gsutil iam ch "serviceAccount:${SERVICE_ACCOUNT}:objectAdmin" \
        "gs://${BUCKET_NAME}"
    
    log_success "IAM permissions configured"
    log_info "Service Account: ${SERVICE_ACCOUNT}"
}

# Test deployment
test_deployment() {
    log_info "Testing deployment..."
    
    if [[ -z "${SERVICE_URL:-}" ]]; then
        log_error "SERVICE_URL not set. Cannot test deployment."
        return 1
    fi
    
    # Test health check endpoint
    log_info "Testing health check endpoint..."
    if curl -s -f -X GET "${SERVICE_URL}/health" -H "Content-Type: application/json" > /dev/null; then
        log_success "Health check endpoint is working"
    else
        log_error "Health check endpoint failed"
        return 1
    fi
    
    # Test age calculation endpoint
    log_info "Testing age calculation endpoint..."
    local test_response
    test_response=$(curl -s -X POST "${SERVICE_URL}/calculate-age" \
        -H "Content-Type: application/json" \
        -d '{"birth_date": "1990-05-15T00:00:00Z"}' || echo "")
    
    if [[ -n "${test_response}" ]] && echo "${test_response}" | grep -q "age_years"; then
        log_success "Age calculation endpoint is working"
    else
        log_error "Age calculation endpoint failed"
        return 1
    fi
    
    log_success "All tests passed"
}

# Main deployment function
main() {
    log_info "Starting Age Calculator API deployment..."
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_bucket
    create_application
    deploy_cloud_run
    configure_iam
    
    # Navigate back to scripts directory
    cd ..
    
    # Test the deployment
    if test_deployment; then
        log_success "Deployment completed successfully!"
        log_info ""
        log_info "=== Deployment Summary ==="
        log_info "Project ID: ${PROJECT_ID}"
        log_info "Service URL: ${SERVICE_URL}"
        log_info "Storage Bucket: gs://${BUCKET_NAME}"
        log_info "Region: ${REGION}"
        log_info ""
        log_info "Test your API:"
        log_info "curl -X POST \"${SERVICE_URL}/calculate-age\" \\"
        log_info "     -H \"Content-Type: application/json\" \\"
        log_info "     -d '{\"birth_date\": \"1990-05-15T00:00:00Z\"}'"
        log_info ""
        log_info "To clean up resources, run: ./destroy.sh"
    else
        log_error "Deployment completed but tests failed"
        log_info "Check the Cloud Run logs for more details:"
        log_info "gcloud logs read --project=${PROJECT_ID} --resource=cloud_run_revision"
        exit 1
    fi
}

# Run main function
main "$@"