#!/bin/bash

# BMI Calculator API with Cloud Functions - Deployment Script
# This script deploys a serverless BMI calculator using Google Cloud Functions and Cloud Storage
# Generated for recipe: bmi-calculator-functions-storage

set -euo pipefail

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

# Error handling
handle_error() {
    log_error "Deployment failed at line $1"
    log_error "Rolling back any created resources..."
    cleanup_partial_deployment
    exit 1
}

trap 'handle_error $LINENO' ERR

# Configuration variables
PROJECT_ID="${PROJECT_ID:-bmi-calculator-$(date +%s)}"
REGION="${REGION:-us-central1}"
FUNCTION_NAME="${FUNCTION_NAME:-bmi-calculator}"
RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
BUCKET_NAME="${BUCKET_NAME:-bmi-history-${RANDOM_SUFFIX}}"

# Script directory and function source
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNCTION_SOURCE_DIR="${SCRIPT_DIR}/../function"

# Deployment state tracking
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not available. Please install openssl for random string generation."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active Google Cloud authentication found. Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Project setup and configuration
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_warning "Project ${PROJECT_ID} already exists. Using existing project."
    else
        log_info "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" --name="BMI Calculator API" || {
            log_error "Failed to create project. You may need to specify a different PROJECT_ID or check billing permissions."
            exit 1
        }
        
        # Note about billing account linking
        log_warning "Don't forget to link a billing account to your project:"
        log_warning "gcloud billing projects link ${PROJECT_ID} --billing-account=YOUR_BILLING_ACCOUNT_ID"
    fi
    
    # Set default project and region configuration
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set functions/region "${REGION}"
    
    echo "PROJECT_ID=${PROJECT_ID}" > "${DEPLOYMENT_STATE_FILE}"
    echo "REGION=${REGION}" >> "${DEPLOYMENT_STATE_FILE}"
    echo "FUNCTION_NAME=${FUNCTION_NAME}" >> "${DEPLOYMENT_STATE_FILE}"
    echo "BUCKET_NAME=${BUCKET_NAME}" >> "${DEPLOYMENT_STATE_FILE}"
    
    log_success "Project configured: ${PROJECT_ID}"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
        "artifactregistry.googleapis.com"
        "run.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" || {
            log_error "Failed to enable ${api}"
            exit 1
        }
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled successfully"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for calculation history..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists. Using existing bucket."
    else
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}" || {
            log_error "Failed to create Cloud Storage bucket"
            exit 1
        }
        log_success "Cloud Storage bucket created: gs://${BUCKET_NAME}"
    fi
}

# Create function source code
create_function_source() {
    log_info "Creating Cloud Functions source code..."
    
    # Create function directory if it doesn't exist
    mkdir -p "${FUNCTION_SOURCE_DIR}"
    
    # Create main.py with BMI calculation logic
    cat > "${FUNCTION_SOURCE_DIR}/main.py" << 'EOF'
import functions_framework
import json
from datetime import datetime
from google.cloud import storage
import os

@functions_framework.http
def calculate_bmi(request):
    """HTTP Cloud Function that calculates BMI and stores history."""
    
    # Set CORS headers for web browser compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight OPTIONS request for CORS
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    # Parse JSON request body
    try:
        request_json = request.get_json(silent=True)
        if not request_json:
            return json.dumps({
                'error': 'Request must contain JSON data'
            }), 400, headers
        
        height = float(request_json.get('height', 0))
        weight = float(request_json.get('weight', 0))
        
        if height <= 0 or weight <= 0:
            return json.dumps({
                'error': 'Height and weight must be positive numbers'
            }), 400, headers
        
    except (ValueError, TypeError):
        return json.dumps({
            'error': 'Height and weight must be valid numbers'
        }), 400, headers
    
    # Calculate BMI using standard formula
    bmi = weight / (height ** 2)
    
    # Determine BMI category based on WHO standards
    if bmi < 18.5:
        category = 'Underweight'
    elif bmi < 25:
        category = 'Normal weight'
    elif bmi < 30:
        category = 'Overweight'
    else:
        category = 'Obese'
    
    # Create calculation record
    calculation = {
        'timestamp': datetime.utcnow().isoformat(),
        'height': height,
        'weight': weight,
        'bmi': round(bmi, 2),
        'category': category
    }
    
    # Store calculation in Cloud Storage
    try:
        bucket_name = os.environ.get('BUCKET_NAME')
        if bucket_name:
            client = storage.Client()
            bucket = client.bucket(bucket_name)
            
            # Create unique filename with timestamp
            filename = f"calculations/{datetime.utcnow().strftime('%Y%m%d_%H%M%S_%f')}.json"
            blob = bucket.blob(filename)
            blob.upload_from_string(json.dumps(calculation))
            
    except Exception as e:
        # Log error but don't fail the request
        print(f"Error storing calculation: {str(e)}")
    
    # Return BMI calculation result
    return json.dumps(calculation), 200, headers
EOF
    
    # Create requirements.txt with necessary dependencies
    cat > "${FUNCTION_SOURCE_DIR}/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-storage==2.*
EOF
    
    log_success "Function source code created successfully"
}

# Deploy Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function..."
    
    cd "${FUNCTION_SOURCE_DIR}"
    
    # Deploy Cloud Function with HTTP trigger and environment variables
    gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point calculate_bmi \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars "BUCKET_NAME=${BUCKET_NAME}" \
        --region "${REGION}" || {
        log_error "Failed to deploy Cloud Function"
        exit 1
    }
    
    # Get the function URL for testing
    FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
        --gen2 \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    
    echo "FUNCTION_URL=${FUNCTION_URL}" >> "${DEPLOYMENT_STATE_FILE}"
    
    log_success "Cloud Function deployed successfully"
    log_info "Function URL: ${FUNCTION_URL}"
    
    cd - > /dev/null
}

# Configure IAM permissions
configure_iam() {
    log_info "Configuring IAM permissions..."
    
    # Get the Cloud Functions service account for 2nd gen functions
    local function_sa
    function_sa=$(gcloud functions describe "${FUNCTION_NAME}" \
        --gen2 \
        --region="${REGION}" \
        --format="value(serviceConfig.serviceAccountEmail)")
    
    # Grant Storage Object Creator role to the function
    gsutil iam ch "serviceAccount:${function_sa}:objectCreator" \
        "gs://${BUCKET_NAME}" || {
        log_error "Failed to configure IAM permissions"
        exit 1
    }
    
    log_success "IAM permissions configured for Cloud Storage access"
}

# Test the deployed function
test_function() {
    log_info "Testing deployed BMI Calculator API..."
    
    # Load function URL from deployment state
    local function_url
    function_url=$(grep "FUNCTION_URL=" "${DEPLOYMENT_STATE_FILE}" | cut -d'=' -f2)
    
    if [[ -z "${function_url}" ]]; then
        log_error "Function URL not found in deployment state"
        exit 1
    fi
    
    # Test with normal weight calculation
    log_info "Testing with normal weight calculation..."
    local test_result
    test_result=$(curl -s -X POST "${function_url}" \
        -H "Content-Type: application/json" \
        -d '{"height": 1.75, "weight": 70}' || true)
    
    if [[ -n "${test_result}" ]]; then
        log_success "API test completed successfully"
        log_info "Test result: ${test_result}"
    else
        log_warning "API test returned empty response, but deployment completed"
    fi
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment status..."
    
    # Check function deployment status
    local function_state
    function_state=$(gcloud functions describe "${FUNCTION_NAME}" \
        --gen2 \
        --region="${REGION}" \
        --format="value(state)")
    
    if [[ "${function_state}" == "ACTIVE" ]]; then
        log_success "Cloud Function is active and ready"
    else
        log_warning "Cloud Function state: ${function_state}"
    fi
    
    # Check bucket existence
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        log_success "Cloud Storage bucket is accessible"
    else
        log_error "Cloud Storage bucket is not accessible"
        exit 1
    fi
}

# Cleanup partial deployment on error
cleanup_partial_deployment() {
    log_warning "Cleaning up partially deployed resources..."
    
    # Try to delete function if it exists
    if gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" &> /dev/null; then
        gcloud functions delete "${FUNCTION_NAME}" --gen2 --region="${REGION}" --quiet || true
    fi
    
    # Try to delete bucket if it exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        gsutil -m rm -r "gs://${BUCKET_NAME}" || true
    fi
    
    # Remove deployment state file
    rm -f "${DEPLOYMENT_STATE_FILE}"
}

# Main deployment function
main() {
    log_info "Starting BMI Calculator API deployment..."
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Function Name: ${FUNCTION_NAME}"
    log_info "Bucket Name: ${BUCKET_NAME}"
    
    check_prerequisites
    setup_project
    enable_apis
    create_storage_bucket
    create_function_source
    deploy_function
    configure_iam
    test_function
    verify_deployment
    
    log_success "BMI Calculator API deployment completed successfully!"
    log_info "Function URL: $(grep "FUNCTION_URL=" "${DEPLOYMENT_STATE_FILE}" | cut -d'=' -f2)"
    log_info "Storage Bucket: gs://${BUCKET_NAME}"
    log_info ""
    log_info "You can test the API with:"
    log_info "curl -X POST \$(grep 'FUNCTION_URL=' '${DEPLOYMENT_STATE_FILE}' | cut -d'=' -f2) \\"
    log_info "  -H 'Content-Type: application/json' \\"
    log_info "  -d '{\"height\": 1.75, \"weight\": 70}'"
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi