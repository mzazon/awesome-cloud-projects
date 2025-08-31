#!/bin/bash

# Hash Generator API with Cloud Functions - Deployment Script
# This script deploys a serverless HTTP API using Google Cloud Functions
# that generates MD5, SHA256, and SHA512 hashes from input text.

set -euo pipefail  # Exit on errors, undefined variables, and pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_PREFIX="hash-api"
readonly REGION_DEFAULT="us-central1"
readonly FUNCTION_NAME="hash-generator"
readonly FUNCTION_RUNTIME="python312"
readonly FUNCTION_MEMORY="256MB"
readonly FUNCTION_TIMEOUT="60s"

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
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code ${exit_code}"
    log_info "Cleaning up partial deployment..."
    
    # Attempt to delete the function if it was created
    if [[ -n "${PROJECT_ID:-}" ]] && [[ -n "${REGION:-}" ]]; then
        gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --project="${PROJECT_ID}" \
            --quiet 2>/dev/null || true
    fi
    
    exit ${exit_code}
}

# Set up error trap
trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not available for random string generation"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Validate and set project configuration
configure_project() {
    log_info "Configuring project settings..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        readonly PROJECT_ID="${PROJECT_PREFIX}-$(date +%s | tail -c 6)"
        log_info "Generated project ID: ${PROJECT_ID}"
    fi
    
    # Set default region if not provided
    if [[ -z "${REGION:-}" ]]; then
        readonly REGION="${REGION_DEFAULT}"
        log_info "Using default region: ${REGION}"
    fi
    
    # Validate region format
    if [[ ! "${REGION}" =~ ^[a-z0-9-]+$ ]]; then
        log_error "Invalid region format: ${REGION}"
        exit 1
    fi
    
    export PROJECT_ID REGION
}

# Create and configure GCP project
setup_project() {
    log_info "Setting up Google Cloud project: ${PROJECT_ID}"
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_warning "Project ${PROJECT_ID} already exists"
        read -p "Do you want to continue with existing project? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    else
        # Create new project
        log_info "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" \
            --name="Hash Generator API Project" \
            --set-as-default
        
        log_success "Project created successfully"
    fi
    
    # Set active project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    log_success "Project configuration completed"
}

# Enable required Google Cloud APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com" 
        "logging.googleapis.com"
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
    
    log_success "All required APIs enabled"
}

# Create function source code
create_function_code() {
    log_info "Creating Cloud Function source code..."
    
    local temp_dir
    temp_dir=$(mktemp -d)
    readonly FUNCTION_DIR="${temp_dir}/hash-generator-function"
    
    # Create function directory
    mkdir -p "${FUNCTION_DIR}"
    
    # Create requirements.txt
    cat > "${FUNCTION_DIR}/requirements.txt" << 'EOF'
functions-framework==3.*
EOF
    
    # Create main.py with hash generator function
    cat > "${FUNCTION_DIR}/main.py" << 'EOF'
import hashlib
import json
from flask import Request
import functions_framework

@functions_framework.http
def hash_generator(request: Request):
    """
    HTTP Cloud Function that generates MD5, SHA256, and SHA512 hashes
    from input text for security and data integrity use cases.
    """
    
    # Set CORS headers for web browser compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    # Only accept POST requests for hash generation
    if request.method != 'POST':
        return json.dumps({
            'error': 'Method not allowed. Use POST with JSON payload.'
        }), 405, headers
    
    try:
        # Parse JSON request body
        request_json = request.get_json(silent=True)
        
        if not request_json or 'text' not in request_json:
            return json.dumps({
                'error': 'Missing required field: text'
            }), 400, headers
        
        input_text = request_json['text']
        
        # Validate input is not empty
        if not input_text or not isinstance(input_text, str):
            return json.dumps({
                'error': 'Text field must be a non-empty string'
            }), 400, headers
        
        # Generate hashes using secure algorithms
        text_bytes = input_text.encode('utf-8')
        
        md5_hash = hashlib.md5(text_bytes).hexdigest()
        sha256_hash = hashlib.sha256(text_bytes).hexdigest()
        sha512_hash = hashlib.sha512(text_bytes).hexdigest()
        
        # Return structured response with all hash types
        response_data = {
            'input': input_text,
            'hashes': {
                'md5': md5_hash,
                'sha256': sha256_hash,
                'sha512': sha512_hash
            },
            'input_length': len(input_text),
            'timestamp': request.headers.get('X-Cloud-Trace-Context', 'unknown')
        }
        
        return json.dumps(response_data, indent=2), 200, headers
        
    except Exception as e:
        # Log error and return generic error message
        print(f"Error processing request: {str(e)}")
        return json.dumps({
            'error': 'Internal server error occurred'
        }), 500, headers
EOF
    
    log_success "Function source code created in: ${FUNCTION_DIR}"
    export FUNCTION_DIR
}

# Deploy the Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function: ${FUNCTION_NAME}"
    
    # Validate function directory exists
    if [[ ! -d "${FUNCTION_DIR}" ]]; then
        log_error "Function directory not found: ${FUNCTION_DIR}"
        exit 1
    fi
    
    # Deploy function with comprehensive configuration
    local deploy_cmd=(
        gcloud functions deploy "${FUNCTION_NAME}"
        --runtime "${FUNCTION_RUNTIME}"
        --trigger-http
        --allow-unauthenticated
        --source "${FUNCTION_DIR}"
        --entry-point hash_generator
        --memory "${FUNCTION_MEMORY}"
        --timeout "${FUNCTION_TIMEOUT}"
        --region "${REGION}"
        --project "${PROJECT_ID}"
        --max-instances 100
        --set-env-vars "FUNCTION_TARGET=hash_generator"
    )
    
    log_info "Executing deployment command..."
    if "${deploy_cmd[@]}"; then
        log_success "Function deployed successfully"
    else
        log_error "Function deployment failed"
        exit 1
    fi
    
    # Wait for deployment to complete
    log_info "Waiting for deployment to stabilize..."
    sleep 10
}

# Get function details and test
validate_deployment() {
    log_info "Validating deployment..."
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" \
        --format="value(httpsTrigger.url)")
    
    if [[ -z "${function_url}" ]]; then
        log_error "Could not retrieve function URL"
        exit 1
    fi
    
    log_success "Function URL: ${function_url}"
    export FUNCTION_URL="${function_url}"
    
    # Create test data
    local test_data='{"text": "Hello, World!"}'
    
    # Test the function
    log_info "Testing function with sample data..."
    
    local response
    if response=$(curl -s -X POST "${function_url}" \
        -H "Content-Type: application/json" \
        -d "${test_data}" \
        --max-time 30); then
        
        # Validate response contains expected fields
        if echo "${response}" | grep -q '"hashes"' && \
           echo "${response}" | grep -q '"md5"' && \
           echo "${response}" | grep -q '"sha256"' && \
           echo "${response}" | grep -q '"sha512"'; then
            log_success "Function test passed"
            log_info "Sample response:"
            echo "${response}" | python3 -m json.tool 2>/dev/null || echo "${response}"
        else
            log_error "Function test failed - invalid response format"
            log_info "Response: ${response}"
            exit 1
        fi
    else
        log_error "Function test failed - could not reach endpoint"
        exit 1
    fi
}

# Display deployment summary
show_deployment_summary() {
    log_success "=== DEPLOYMENT COMPLETE ==="
    echo
    log_info "Project Details:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Function Name: ${FUNCTION_NAME}"
    echo
    log_info "Function Endpoint:"
    echo "  URL: ${FUNCTION_URL}"
    echo
    log_info "Test the API:"
    echo "  curl -X POST ${FUNCTION_URL} \\"
    echo "    -H \"Content-Type: application/json\" \\"
    echo "    -d '{\"text\": \"your-text-here\"}'"
    echo
    log_info "Cost Information:"
    echo "  • First 2 million invocations per month are free"
    echo "  • Additional invocations: \$0.40 per million"
    echo "  • Memory usage: \$0.0000025 per GB-second"
    echo
    log_info "Management Commands:"
    echo "  • View logs: gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}"
    echo "  • Delete function: gcloud functions delete ${FUNCTION_NAME} --region=${REGION}"
    echo
    log_warning "Remember to clean up resources when no longer needed to avoid charges!"
}

# Main deployment workflow
main() {
    log_info "Starting Hash Generator API deployment..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --dry-run)
                log_info "Dry run mode - showing what would be deployed"
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --project-id ID    Use specific project ID"
                echo "  --region REGION    Deploy to specific region (default: us-central1)"
                echo "  --dry-run          Show deployment plan without executing"
                echo "  --help, -h         Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    configure_project
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "DRY RUN - Would deploy:"
        echo "  Project: ${PROJECT_ID}"
        echo "  Region: ${REGION}"
        echo "  Function: ${FUNCTION_NAME}"
        echo "  Runtime: ${FUNCTION_RUNTIME}"
        exit 0
    fi
    
    setup_project
    enable_apis
    create_function_code
    deploy_function
    validate_deployment
    show_deployment_summary
    
    log_success "Deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"