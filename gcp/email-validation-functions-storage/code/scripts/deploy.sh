#!/bin/bash

# =============================================================================
# GCP Email Validation with Cloud Functions - Deployment Script
# =============================================================================
# This script deploys a complete email validation solution using:
# - Cloud Functions for serverless email processing
# - Cloud Storage for validation logs and analytics
# - IAM for secure service-to-service communication
# =============================================================================

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_PREFIX="email-validation"
readonly FUNCTION_NAME="email-validator"
readonly DEFAULT_REGION="us-central1"
readonly DEFAULT_ZONE="us-central1-a"
readonly PYTHON_RUNTIME="python311"
readonly FUNCTION_MEMORY="256MiB"
readonly FUNCTION_TIMEOUT="60s"

# Global variables
PROJECT_ID=""
REGION=""
ZONE=""
BUCKET_NAME=""
FUNCTION_URL=""
DEPLOYMENT_LOG="${SCRIPT_DIR}/deployment.log"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}]${NC} ${message}"
    echo "[${timestamp}] ${message}" >> "${DEPLOYMENT_LOG}"
}

log_warning() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[${timestamp}] WARNING:${NC} ${message}"
    echo "[${timestamp}] WARNING: ${message}" >> "${DEPLOYMENT_LOG}"
}

log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[${timestamp}] ERROR:${NC} ${message}" >&2
    echo "[${timestamp}] ERROR: ${message}" >> "${DEPLOYMENT_LOG}"
}

log_info() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[${timestamp}] INFO:${NC} ${message}"
    echo "[${timestamp}] INFO: ${message}" >> "${DEPLOYMENT_LOG}"
}

cleanup_on_error() {
    log_error "Deployment failed. Initiating cleanup..."
    
    # Attempt to clean up any partially created resources
    if [[ -n "${FUNCTION_NAME:-}" && -n "${PROJECT_ID:-}" && -n "${REGION:-}" ]]; then
        gcloud functions delete "${FUNCTION_NAME}" \
            --gen2 \
            --region="${REGION}" \
            --project="${PROJECT_ID}" \
            --quiet 2>/dev/null || true
    fi
    
    if [[ -n "${BUCKET_NAME:-}" && -n "${PROJECT_ID:-}" ]]; then
        gsutil -m rm -r "gs://${BUCKET_NAME}" 2>/dev/null || true
    fi
    
    log_error "Cleanup completed. Check logs for details: ${DEPLOYMENT_LOG}"
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy GCP Email Validation with Cloud Functions

OPTIONS:
    -p, --project PROJECT_ID    GCP Project ID (default: auto-generated)
    -r, --region REGION         GCP region (default: ${DEFAULT_REGION})
    -z, --zone ZONE            GCP zone (default: ${DEFAULT_ZONE})
    -b, --bucket BUCKET_NAME   Storage bucket name (default: auto-generated)
    -h, --help                 Show this help message
    --dry-run                  Show what would be deployed without executing
    --skip-project-creation    Skip project creation step
    --verbose                  Enable verbose logging

EXAMPLES:
    $0                                      # Deploy with defaults
    $0 -p my-project -r us-west1           # Deploy to specific project and region
    $0 --dry-run                           # Preview deployment
    $0 --skip-project-creation -p existing-project  # Use existing project

EOF
}

# =============================================================================
# Prerequisites Validation
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        log_info "Installation guide: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if required APIs can be enabled (billing account check)
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -n "${current_project}" ]]; then
        if ! gcloud services list --enabled --filter="name:cloudfunctions.googleapis.com" --format="value(name)" &> /dev/null; then
            log_warning "Current project may not have billing enabled. Some operations may fail."
        fi
    fi
    
    log "✅ Prerequisites check completed successfully"
}

# =============================================================================
# Project Setup
# =============================================================================

setup_project() {
    local should_create_project="$1"
    
    if [[ "${should_create_project}" == "true" ]]; then
        log "Creating new GCP project..."
        
        # Generate unique project ID if not provided
        if [[ -z "${PROJECT_ID}" ]]; then
            local timestamp=$(date +%s)
            PROJECT_ID="${PROJECT_PREFIX}-${timestamp}"
        fi
        
        # Create project
        if gcloud projects create "${PROJECT_ID}" --quiet; then
            log "✅ Created project: ${PROJECT_ID}"
        else
            log_error "Failed to create project: ${PROJECT_ID}"
            log_info "The project ID might already exist. Try with a different name."
            exit 1
        fi
        
        # Set as active project
        gcloud config set project "${PROJECT_ID}"
        
        # Link billing account (if available)
        local billing_account
        billing_account=$(gcloud billing accounts list --format="value(name)" --limit=1 2>/dev/null || echo "")
        if [[ -n "${billing_account}" ]]; then
            if gcloud billing projects link "${PROJECT_ID}" --billing-account="${billing_account}"; then
                log "✅ Linked billing account to project"
            else
                log_warning "Could not link billing account. You may need to do this manually."
            fi
        else
            log_warning "No billing account found. Please link one manually to enable APIs."
        fi
    else
        if [[ -z "${PROJECT_ID}" ]]; then
            PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
            if [[ -z "${PROJECT_ID}" ]]; then
                log_error "No project specified and no default project configured"
                log_info "Use -p/--project to specify a project or run 'gcloud config set project PROJECT_ID'"
                exit 1
            fi
        fi
        
        # Set as active project
        gcloud config set project "${PROJECT_ID}"
        log "✅ Using existing project: ${PROJECT_ID}"
    fi
    
    # Set region and zone
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log "✅ Project configuration completed"
}

# =============================================================================
# API Enablement
# =============================================================================

enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
        "run.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log "✅ Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully activated
    log_info "Waiting for APIs to be fully activated..."
    sleep 10
    
    log "✅ All required APIs enabled successfully"
}

# =============================================================================
# Storage Setup
# =============================================================================

setup_storage() {
    log "Setting up Cloud Storage bucket..."
    
    # Generate unique bucket name if not provided
    if [[ -z "${BUCKET_NAME}" ]]; then
        local random_suffix
        random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s)")
        BUCKET_NAME="${PROJECT_PREFIX}-logs-${random_suffix}"
    fi
    
    # Create bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        log "✅ Created Cloud Storage bucket: gs://${BUCKET_NAME}"
    else
        log_error "Failed to create bucket: gs://${BUCKET_NAME}"
        log_info "The bucket name might already exist globally. Try with a different name."
        exit 1
    fi
    
    # Enable versioning
    if gsutil versioning set on "gs://${BUCKET_NAME}"; then
        log "✅ Enabled versioning for bucket"
    else
        log_warning "Could not enable versioning for bucket"
    fi
    
    # Set up lifecycle management
    local lifecycle_config
    lifecycle_config=$(cat << EOF
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30}
    },
    {
      "action": {"type": "Delete"},
      "condition": {"age": 365}
    }
  ]
}
EOF
)
    
    echo "${lifecycle_config}" > "${SCRIPT_DIR}/lifecycle.json"
    
    if gsutil lifecycle set "${SCRIPT_DIR}/lifecycle.json" "gs://${BUCKET_NAME}"; then
        log "✅ Applied lifecycle management to bucket"
        rm -f "${SCRIPT_DIR}/lifecycle.json"
    else
        log_warning "Could not apply lifecycle management to bucket"
    fi
    
    log "✅ Storage setup completed"
}

# =============================================================================
# Function Code Preparation
# =============================================================================

prepare_function_code() {
    log "Preparing Cloud Function code..."
    
    local function_dir="${SCRIPT_DIR}/../function-source"
    mkdir -p "${function_dir}"
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-storage==2.*
dnspython==2.*
EOF
    
    # Create main.py with the email validation logic
    cat > "${function_dir}/main.py" << 'EOF'
import functions_framework
import json
import re
import socket
from datetime import datetime
from google.cloud import storage
import os

# Initialize Cloud Storage client
storage_client = storage.Client()
BUCKET_NAME = os.environ.get('BUCKET_NAME')

def validate_email_format(email):
    """Validate email format using regex pattern"""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return bool(re.match(pattern, email))

def validate_domain(domain):
    """Validate domain exists using DNS lookup"""
    try:
        socket.gethostbyname(domain)
        return True
    except socket.gaierror:
        return False

def log_validation(email, is_valid, validation_details):
    """Store validation results in Cloud Storage"""
    try:
        bucket = storage_client.bucket(BUCKET_NAME)
        timestamp = datetime.utcnow()
        filename = f"validations/{timestamp.strftime('%Y/%m/%d')}/{timestamp.isoformat()}.json"
        
        log_data = {
            'timestamp': timestamp.isoformat(),
            'email': email,
            'is_valid': is_valid,
            'validation_details': validation_details
        }
        
        blob = bucket.blob(filename)
        blob.upload_from_string(json.dumps(log_data))
        return True
    except Exception as e:
        print(f"Logging error: {e}")
        return False

@functions_framework.http
def validate_email(request):
    """Main email validation function"""
    # Handle CORS for web requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json or 'email' not in request_json:
            return json.dumps({'error': 'Email parameter required'}), 400, headers
        
        email = request_json['email'].strip().lower()
        validation_details = {}
        
        # Format validation
        format_valid = validate_email_format(email)
        validation_details['format_valid'] = format_valid
        
        # Domain validation
        domain_valid = False
        if format_valid:
            domain = email.split('@')[1]
            domain_valid = validate_domain(domain)
            validation_details['domain_valid'] = domain_valid
        
        # Overall validation result
        is_valid = format_valid and domain_valid
        validation_details['overall_valid'] = is_valid
        
        # Log validation attempt
        log_validation(email, is_valid, validation_details)
        
        # Return result
        response = {
            'email': email,
            'is_valid': is_valid,
            'validation_details': validation_details
        }
        
        return json.dumps(response), 200, headers
        
    except Exception as e:
        error_response = {'error': f'Validation failed: {str(e)}'}
        return json.dumps(error_response), 500, headers
EOF
    
    log "✅ Function code prepared in ${function_dir}"
}

# =============================================================================
# Function Deployment
# =============================================================================

deploy_function() {
    log "Deploying Cloud Function..."
    
    local function_dir="${SCRIPT_DIR}/../function-source"
    
    # Deploy the function
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime "${PYTHON_RUNTIME}" \
        --source "${function_dir}" \
        --entry-point validate_email \
        --trigger-http \
        --allow-unauthenticated \
        --memory "${FUNCTION_MEMORY}" \
        --timeout "${FUNCTION_TIMEOUT}" \
        --set-env-vars "BUCKET_NAME=${BUCKET_NAME}" \
        --region "${REGION}" \
        --quiet; then
        
        log "✅ Cloud Function deployed successfully"
        
        # Get function URL
        FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
            --gen2 \
            --region "${REGION}" \
            --format="value(serviceConfig.uri)" 2>/dev/null || echo "")
        
        if [[ -n "${FUNCTION_URL}" ]]; then
            log "✅ Function URL: ${FUNCTION_URL}"
        else
            log_warning "Could not retrieve function URL"
        fi
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
}

# =============================================================================
# IAM Configuration
# =============================================================================

configure_iam() {
    log "Configuring IAM permissions..."
    
    # Get Cloud Function service account
    local function_sa
    function_sa=$(gcloud functions describe "${FUNCTION_NAME}" \
        --gen2 \
        --region "${REGION}" \
        --format="value(serviceConfig.serviceAccountEmail)" 2>/dev/null || echo "")
    
    if [[ -n "${function_sa}" ]]; then
        log_info "Function service account: ${function_sa}"
        
        # Grant Cloud Storage permissions
        if gsutil iam ch "serviceAccount:${function_sa}:objectCreator" "gs://${BUCKET_NAME}"; then
            log "✅ Granted Cloud Storage permissions to function"
        else
            log_warning "Could not grant Cloud Storage permissions"
        fi
    else
        log_warning "Could not retrieve function service account"
    fi
}

# =============================================================================
# Testing and Validation
# =============================================================================

test_deployment() {
    log "Testing deployed solution..."
    
    if [[ -z "${FUNCTION_URL}" ]]; then
        log_warning "Function URL not available, skipping tests"
        return
    fi
    
    # Test CORS preflight
    log_info "Testing CORS preflight..."
    if curl -s -X OPTIONS "${FUNCTION_URL}" -o /dev/null; then
        log "✅ CORS preflight test passed"
    else
        log_warning "CORS preflight test failed"
    fi
    
    # Test valid email
    log_info "Testing valid email validation..."
    local test_response
    test_response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{"email":"test@gmail.com"}' \
        "${FUNCTION_URL}" 2>/dev/null || echo "")
    
    if [[ -n "${test_response}" ]] && echo "${test_response}" | grep -q '"is_valid"'; then
        log "✅ Email validation test passed"
        log_info "Response: ${test_response}"
    else
        log_warning "Email validation test failed or gave unexpected response"
    fi
    
    # Test invalid email
    log_info "Testing invalid email validation..."
    test_response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{"email":"invalid-email"}' \
        "${FUNCTION_URL}" 2>/dev/null || echo "")
    
    if [[ -n "${test_response}" ]] && echo "${test_response}" | grep -q '"is_valid"'; then
        log "✅ Invalid email test passed"
        log_info "Response: ${test_response}"
    else
        log_warning "Invalid email test failed or gave unexpected response"
    fi
    
    # Wait a moment and check for log files
    log_info "Checking if validation logs are being created..."
    sleep 5
    
    local log_count
    log_count=$(gsutil ls -r "gs://${BUCKET_NAME}/validations/" 2>/dev/null | wc -l || echo "0")
    
    if [[ "${log_count}" -gt 0 ]]; then
        log "✅ Validation logs are being created in Cloud Storage"
        log_info "Found ${log_count} log entries"
    else
        log_warning "No validation logs found yet (may take a few moments)"
    fi
}

# =============================================================================
# Deployment Summary
# =============================================================================

show_deployment_summary() {
    log "📋 Deployment Summary"
    echo "===========================================" | tee -a "${DEPLOYMENT_LOG}"
    echo "Project ID: ${PROJECT_ID}" | tee -a "${DEPLOYMENT_LOG}"
    echo "Region: ${REGION}" | tee -a "${DEPLOYMENT_LOG}"
    echo "Function Name: ${FUNCTION_NAME}" | tee -a "${DEPLOYMENT_LOG}"
    echo "Storage Bucket: gs://${BUCKET_NAME}" | tee -a "${DEPLOYMENT_LOG}"
    echo "Function URL: ${FUNCTION_URL}" | tee -a "${DEPLOYMENT_LOG}"
    echo "===========================================" | tee -a "${DEPLOYMENT_LOG}"
    
    echo "" | tee -a "${DEPLOYMENT_LOG}"
    echo "🧪 Test Commands:" | tee -a "${DEPLOYMENT_LOG}"
    echo "Test valid email:" | tee -a "${DEPLOYMENT_LOG}"
    echo "curl -X POST -H 'Content-Type: application/json' \\" | tee -a "${DEPLOYMENT_LOG}"
    echo "     -d '{\"email\":\"test@gmail.com\"}' \\" | tee -a "${DEPLOYMENT_LOG}"
    echo "     '${FUNCTION_URL}'" | tee -a "${DEPLOYMENT_LOG}"
    
    echo "" | tee -a "${DEPLOYMENT_LOG}"
    echo "Test invalid email:" | tee -a "${DEPLOYMENT_LOG}"
    echo "curl -X POST -H 'Content-Type: application/json' \\" | tee -a "${DEPLOYMENT_LOG}"
    echo "     -d '{\"email\":\"invalid-email\"}' \\" | tee -a "${DEPLOYMENT_LOG}"
    echo "     '${FUNCTION_URL}'" | tee -a "${DEPLOYMENT_LOG}"
    
    echo "" | tee -a "${DEPLOYMENT_LOG}"
    echo "📊 View logs:" | tee -a "${DEPLOYMENT_LOG}"
    echo "gsutil ls -r gs://${BUCKET_NAME}/validations/" | tee -a "${DEPLOYMENT_LOG}"
    
    echo "" | tee -a "${DEPLOYMENT_LOG}"
    echo "🗑️  Cleanup:" | tee -a "${DEPLOYMENT_LOG}"
    echo "Run: ${SCRIPT_DIR}/destroy.sh -p ${PROJECT_ID}" | tee -a "${DEPLOYMENT_LOG}"
    
    echo "" | tee -a "${DEPLOYMENT_LOG}"
    echo "📝 Deployment log: ${DEPLOYMENT_LOG}" | tee -a "${DEPLOYMENT_LOG}"
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    local dry_run=false
    local skip_project_creation=false
    local verbose=false
    
    # Set defaults
    REGION="${DEFAULT_REGION}"
    ZONE="${DEFAULT_ZONE}"
    
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
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -b|--bucket)
                BUCKET_NAME="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --skip-project-creation)
                skip_project_creation=true
                shift
                ;;
            --verbose)
                verbose=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Enable verbose logging if requested
    if [[ "${verbose}" == "true" ]]; then
        set -x
    fi
    
    # Initialize deployment log
    echo "=== GCP Email Validation Deployment Log ===" > "${DEPLOYMENT_LOG}"
    echo "Started at: $(date)" >> "${DEPLOYMENT_LOG}"
    echo "" >> "${DEPLOYMENT_LOG}"
    
    log "🚀 Starting GCP Email Validation deployment..."
    log_info "Deployment log: ${DEPLOYMENT_LOG}"
    
    if [[ "${dry_run}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        
        echo "Would deploy:"
        echo "  - Project: ${PROJECT_ID:-"auto-generated"}"
        echo "  - Region: ${REGION}"
        echo "  - Function: ${FUNCTION_NAME}"
        echo "  - Bucket: ${BUCKET_NAME:-"auto-generated"}"
        echo "  - Runtime: ${PYTHON_RUNTIME}"
        
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_project "${skip_project_creation}"
    enable_apis
    setup_storage
    prepare_function_code
    deploy_function
    configure_iam
    test_deployment
    show_deployment_summary
    
    log "🎉 Deployment completed successfully!"
    log_info "Total deployment time: $((SECONDS / 60)) minutes $((SECONDS % 60)) seconds"
    
    # Store deployment info for destroy script
    cat > "${SCRIPT_DIR}/.deployment_info" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
FUNCTION_NAME=${FUNCTION_NAME}
BUCKET_NAME=${BUCKET_NAME}
DEPLOYMENT_DATE=$(date -Iseconds)
EOF
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi