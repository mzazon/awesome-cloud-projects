#!/bin/bash

# JSON Validator API with Cloud Functions - Deployment Script
# This script deploys a serverless JSON validation API using Google Cloud Functions and Cloud Storage
# Recipe: json-validator-api-functions-storage

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output formatting
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed (for JSON processing)
    if ! command_exists jq; then
        log_warning "jq is not installed. Installing via package manager..."
        if command_exists apt-get; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command_exists yum; then
            sudo yum install -y jq
        elif command_exists brew; then
            brew install jq
        else
            log_error "Unable to install jq. Please install it manually."
            exit 1
        fi
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if openssl is available (for random string generation)
    if ! command_exists openssl; then
        log_error "openssl is not available. Please install it for random string generation."
        exit 1
    fi
    
    # Check if user is authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "All prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-json-validator-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export FUNCTION_NAME="${FUNCTION_NAME:-json-validator-${RANDOM_SUFFIX}}"
    export BUCKET_NAME="${BUCKET_NAME:-json-files-${PROJECT_ID}-${RANDOM_SUFFIX}}"
    
    log_info "Configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Zone: ${ZONE}"
    log_info "  Function Name: ${FUNCTION_NAME}"
    log_info "  Bucket Name: ${BUCKET_NAME}"
    
    # Save environment variables to file for cleanup script
    cat > .env << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
FUNCTION_NAME=${FUNCTION_NAME}
BUCKET_NAME=${BUCKET_NAME}
EOF
    
    log_success "Environment variables configured"
}

# Function to create and configure GCP project
setup_project() {
    log_info "Setting up GCP project..."
    
    # Check if project already exists
    if gcloud projects list --filter="projectId:${PROJECT_ID}" --format="value(projectId)" | grep -q "${PROJECT_ID}"; then
        log_warning "Project ${PROJECT_ID} already exists. Using existing project."
    else
        log_info "Creating new project: ${PROJECT_ID}"
        gcloud projects create ${PROJECT_ID} --name="JSON Validator API" || {
            log_error "Failed to create project. You may need billing account setup or different project ID."
            exit 1
        }
    fi
    
    # Set active project
    gcloud config set project ${PROJECT_ID}
    gcloud config set compute/region ${REGION}
    gcloud config set compute/zone ${ZONE}
    
    log_success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable ${api} || {
            log_error "Failed to enable ${api}"
            exit 1
        }
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls -b gs://${BUCKET_NAME} >/dev/null 2>&1; then
        log_warning "Bucket ${BUCKET_NAME} already exists. Using existing bucket."
    else
        # Create the storage bucket
        gsutil mb -p ${PROJECT_ID} \
            -c STANDARD \
            -l ${REGION} \
            gs://${BUCKET_NAME} || {
            log_error "Failed to create storage bucket"
            exit 1
        }
        
        # Enable versioning for data protection
        gsutil versioning set on gs://${BUCKET_NAME}
        
        # Set bucket permissions for function access
        gsutil iam ch allUsers:objectViewer gs://${BUCKET_NAME}
        
        log_success "Cloud Storage bucket created: gs://${BUCKET_NAME}"
    fi
}

# Function to create function directory and dependencies
prepare_function_code() {
    log_info "Preparing Cloud Function code..."
    
    # Create function directory if it doesn't exist
    mkdir -p json-validator-function
    cd json-validator-function
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.8.1
google-cloud-storage==2.18.0
google-cloud-logging==3.11.2
EOF
    
    # Create the main function file
    cat > main.py << 'EOF'
import json
import logging
from flask import Request, jsonify
from google.cloud import storage
from google.cloud import logging as cloud_logging
import functions_framework
import traceback
from typing import Dict, Any, Union

# Configure logging
cloud_logging.Client().setup_logging()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Cloud Storage client
storage_client = storage.Client()

def validate_json_content(content: str) -> Dict[str, Any]:
    """
    Validate and format JSON content.
    
    Args:
        content: String containing JSON data
        
    Returns:
        Dictionary with validation results
    """
    try:
        # Parse JSON to validate syntax
        parsed_json = json.loads(content)
        
        # Format with proper indentation
        formatted_json = json.dumps(parsed_json, indent=2, sort_keys=True)
        
        # Calculate basic statistics
        stats = {
            'size_bytes': len(content),
            'formatted_size_bytes': len(formatted_json),
            'keys_count': len(parsed_json) if isinstance(parsed_json, dict) else 0,
            'type': type(parsed_json).__name__
        }
        
        return {
            'valid': True,
            'formatted_json': formatted_json,
            'original_json': parsed_json,
            'statistics': stats,
            'message': 'JSON is valid and properly formatted'
        }
        
    except json.JSONDecodeError as e:
        return {
            'valid': False,
            'error': str(e),
            'error_type': 'JSONDecodeError',
            'line': getattr(e, 'lineno', None),
            'column': getattr(e, 'colno', None),
            'message': f'Invalid JSON syntax: {str(e)}'
        }
    except Exception as e:
        logger.error(f"Unexpected error during JSON validation: {str(e)}")
        return {
            'valid': False,
            'error': str(e),
            'error_type': type(e).__name__,
            'message': 'Unexpected error occurred during validation'
        }

def process_storage_file(bucket_name: str, file_name: str) -> Dict[str, Any]:
    """
    Process JSON file from Cloud Storage.
    
    Args:
        bucket_name: Name of the storage bucket
        file_name: Name of the file to process
        
    Returns:
        Dictionary with validation results
    """
    try:
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        if not blob.exists():
            return {
                'valid': False,
                'error': f'File {file_name} not found in bucket {bucket_name}',
                'message': 'File not found in storage'
            }
        
        # Download and validate the file content
        content = blob.download_as_text()
        result = validate_json_content(content)
        
        # Add storage metadata
        result['storage_info'] = {
            'bucket': bucket_name,
            'file': file_name,
            'size': blob.size,
            'content_type': blob.content_type,
            'updated': blob.updated.isoformat() if blob.updated else None
        }
        
        return result
        
    except Exception as e:
        logger.error(f"Error processing storage file: {str(e)}")
        return {
            'valid': False,
            'error': str(e),
            'message': 'Error accessing or processing storage file'
        }

@functions_framework.http
def json_validator_api(request: Request) -> Union[str, tuple]:
    """
    HTTP Cloud Function for JSON validation and formatting.
    
    Accepts JSON data via POST request body or processes files from Cloud Storage
    via query parameters.
    """
    try:
        # Set CORS headers for web applications
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Content-Type': 'application/json'
        }
        
        # Handle preflight OPTIONS request
        if request.method == 'OPTIONS':
            return ('', 200, headers)
        
        # Handle GET request for health check
        if request.method == 'GET':
            return jsonify({
                'status': 'healthy',
                'service': 'JSON Validator API',
                'version': '1.0',
                'endpoints': {
                    'POST /': 'Validate JSON in request body',
                    'GET /?bucket=BUCKET&file=FILE': 'Validate JSON file from storage'
                }
            }), 200, headers
        
        # Handle storage file processing
        bucket_name = request.args.get('bucket')
        file_name = request.args.get('file')
        
        if bucket_name and file_name:
            logger.info(f"Processing file {file_name} from bucket {bucket_name}")
            result = process_storage_file(bucket_name, file_name)
            return jsonify(result), 200, headers
        
        # Handle POST request with JSON in body
        if request.method == 'POST':
            if not request.data:
                return jsonify({
                    'valid': False,
                    'error': 'No data provided',
                    'message': 'Please provide JSON data in the request body'
                }), 400, headers
            
            # Get content as string for validation
            content = request.get_data(as_text=True)
            logger.info(f"Validating JSON content, size: {len(content)} bytes")
            
            result = validate_json_content(content)
            
            # Return appropriate HTTP status code
            status_code = 200 if result['valid'] else 400
            return jsonify(result), status_code, headers
        
        # Method not allowed
        return jsonify({
            'valid': False,
            'error': 'Method not allowed',
            'message': 'Only GET and POST methods are supported'
        }), 405, headers
        
    except Exception as e:
        logger.error(f"Unexpected error in function: {str(e)}")
        logger.error(traceback.format_exc())
        
        return jsonify({
            'valid': False,
            'error': str(e),
            'message': 'Internal server error occurred'
        }), 500, {'Content-Type': 'application/json'}
EOF
    
    log_success "Function code prepared"
}

# Function to deploy Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function..."
    
    # Deploy the function with optimized settings
    gcloud functions deploy ${FUNCTION_NAME} \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point json_validator_api \
        --memory 256MB \
        --timeout 60s \
        --max-instances 10 \
        --region ${REGION} || {
        log_error "Failed to deploy Cloud Function"
        exit 1
    }
    
    # Get the function URL
    FUNCTION_URL=$(gcloud functions describe ${FUNCTION_NAME} \
        --region=${REGION} \
        --format="value(httpsTrigger.url)")
    
    # Save function URL to environment file
    echo "FUNCTION_URL=${FUNCTION_URL}" >> ../.env
    
    log_success "Function deployed successfully"
    log_info "Function URL: ${FUNCTION_URL}"
    
    cd ..
}

# Function to create and upload test files
create_test_files() {
    log_info "Creating and uploading test files..."
    
    # Create sample valid JSON file
    cat > sample-valid.json << 'EOF'
{
  "users": [
    {
      "id": 1,
      "name": "John Doe",
      "email": "john@example.com",
      "active": true,
      "roles": ["admin", "user"]
    },
    {
      "id": 2,
      "name": "Jane Smith",
      "email": "jane@example.com",
      "active": false,
      "roles": ["user"]
    }
  ],
  "metadata": {
    "total": 2,
    "created": "2025-01-15T10:00:00Z"
  }
}
EOF
    
    # Create sample invalid JSON file (missing closing brace and has comments)
    cat > sample-invalid.json << 'EOF'
{
  "users": [
    {
      "id": 1,
      "name": "John Doe",
      "email": "john@example.com",
      "active": true,
      "roles": ["admin", "user"]
    },
    {
      "id": 2,
      "name": "Jane Smith",
      "email": "jane@example.com",
      "active": false,
      "roles": ["user"]
    }
  ],
  "metadata": {
    "total": 2,
    "created": "2025-01-15T10:00:00Z"
  }
  // Missing closing brace and invalid comment
EOF
    
    # Upload test files to Cloud Storage
    gsutil cp sample-valid.json gs://${BUCKET_NAME}/ || {
        log_error "Failed to upload valid test file"
        exit 1
    }
    
    gsutil cp sample-invalid.json gs://${BUCKET_NAME}/ || {
        log_error "Failed to upload invalid test file"
        exit 1
    }
    
    # Clean up local test files
    rm -f sample-valid.json sample-invalid.json
    
    log_success "Test files created and uploaded to storage"
}

# Function to run validation tests
run_validation_tests() {
    log_info "Running validation tests..."
    
    # Source the environment file to get FUNCTION_URL
    source .env
    
    log_info "Testing health check endpoint..."
    if curl -s -X GET "${FUNCTION_URL}" | jq '.' > /dev/null; then
        log_success "Health check endpoint working"
    else
        log_warning "Health check endpoint test failed"
    fi
    
    log_info "Testing valid JSON validation..."
    if curl -s -X POST "${FUNCTION_URL}" \
         -H "Content-Type: application/json" \
         -d '{"name": "test", "value": 123}' | jq '.valid' | grep -q true; then
        log_success "Valid JSON validation working"
    else
        log_warning "Valid JSON validation test failed"
    fi
    
    log_info "Testing invalid JSON validation..."
    if curl -s -X POST "${FUNCTION_URL}" \
         -H "Content-Type: application/json" \
         -d '{"name": "test", "value": 123' | jq '.valid' | grep -q false; then
        log_success "Invalid JSON validation working"
    else
        log_warning "Invalid JSON validation test failed"
    fi
    
    log_info "Testing Cloud Storage file processing..."
    if curl -s -X GET "${FUNCTION_URL}?bucket=${BUCKET_NAME}&file=sample-valid.json" | jq '.valid' | grep -q true; then
        log_success "Storage file processing working"
    else
        log_warning "Storage file processing test failed"
    fi
    
    log_success "Validation tests completed"
}

# Function to display deployment summary
display_summary() {
    source .env
    
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    log_info "Deployment Summary:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Function Name: ${FUNCTION_NAME}"
    log_info "  Function URL: ${FUNCTION_URL}"
    log_info "  Storage Bucket: gs://${BUCKET_NAME}"
    echo
    log_info "Test the API:"
    log_info "  Health Check: curl -X GET '${FUNCTION_URL}'"
    log_info "  Validate JSON: curl -X POST '${FUNCTION_URL}' -H 'Content-Type: application/json' -d '{\"test\": \"data\"}'"
    log_info "  Process File: curl -X GET '${FUNCTION_URL}?bucket=${BUCKET_NAME}&file=sample-valid.json'"
    echo
    log_info "Environment variables saved to .env file"
    log_warning "Run ./destroy.sh to clean up resources and avoid charges"
    echo
}

# Main deployment function
main() {
    log_info "Starting JSON Validator API deployment..."
    
    # Check if dry run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        export DRY_RUN=true
        return 0
    fi
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_bucket
    prepare_function_code
    deploy_function
    create_test_files
    
    # Run validation tests if not in CI environment
    if [[ "${CI:-false}" != "true" ]]; then
        run_validation_tests
    fi
    
    display_summary
}

# Handle script interruption
trap 'log_error "Deployment interrupted. Run ./destroy.sh to clean up any created resources."; exit 1' INT TERM

# Run main function with all arguments
main "$@"