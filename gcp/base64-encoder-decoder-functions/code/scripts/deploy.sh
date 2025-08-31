#!/bin/bash

# Base64 Encoder Decoder Functions - Deployment Script
# This script deploys Cloud Functions for Base64 encoding/decoding operations
# Recipe: Base64 Encoder Decoder with Cloud Functions

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_error "Install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        log_error "Not authenticated with Google Cloud"
        log_error "Run: gcloud auth login"
        exit 1
    fi
    
    # Check if Python 3 is available for JSON processing
    if ! command_exists python3; then
        log_error "Python 3 is required for JSON processing"
        exit 1
    fi
    
    # Check if curl is available for testing
    if ! command_exists curl; then
        log_error "curl is required for API testing"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Function to prompt for configuration
prompt_configuration() {
    log_info "Configuration setup..."
    
    # Get current project if set
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    
    # Prompt for project ID if not set or user wants to change
    if [ -z "$CURRENT_PROJECT" ]; then
        read -p "Enter your Google Cloud Project ID: " PROJECT_ID
    else
        read -p "Current project is '$CURRENT_PROJECT'. Use this project? (y/n): " use_current
        if [[ $use_current =~ ^[Yy]$ ]]; then
            PROJECT_ID="$CURRENT_PROJECT"
        else
            read -p "Enter your Google Cloud Project ID: " PROJECT_ID
        fi
    fi
    
    # Validate project ID format
    if [[ ! "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        log_error "Invalid project ID format. Must be 6-30 characters, start with lowercase letter, contain only lowercase letters, numbers, and hyphens"
        exit 1
    fi
    
    # Set default region
    read -p "Enter deployment region (default: us-central1): " REGION
    REGION=${REGION:-us-central1}
    
    # Validate region format
    if [[ ! "$REGION" =~ ^[a-z]+-[a-z]+[0-9]+$ ]]; then
        log_error "Invalid region format. Example: us-central1, europe-west1"
        exit 1
    fi
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 7)
    
    # Set resource names
    BUCKET_NAME="base64-files-${RANDOM_SUFFIX}"
    ENCODER_FUNCTION="base64-encoder"
    DECODER_FUNCTION="base64-decoder"
    
    log_info "Configuration:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Bucket Name: $BUCKET_NAME"
    log_info "  Encoder Function: $ENCODER_FUNCTION"
    log_info "  Decoder Function: $DECODER_FUNCTION"
    
    # Confirm deployment
    read -p "Proceed with deployment? (y/n): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi
}

# Function to set up GCP configuration
setup_gcp_config() {
    log_info "Setting up Google Cloud configuration..."
    
    # Set project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set functions/region "$REGION"
    
    # Verify project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log_error "Project '$PROJECT_ID' does not exist or is not accessible"
        exit 1
    fi
    
    # Check billing is enabled
    if ! gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" 2>/dev/null | grep -q "True"; then
        log_warning "Billing may not be enabled for project '$PROJECT_ID'"
        log_warning "Some services may not be available without billing enabled"
    fi
    
    log_success "Google Cloud configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
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
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 10
    
    log_success "All required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls -p "$PROJECT_ID" "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        log_warning "Bucket gs://$BUCKET_NAME already exists, skipping creation"
        return 0
    fi
    
    # Create bucket
    if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
        log_success "Created Cloud Storage bucket: gs://$BUCKET_NAME"
    else
        log_error "Failed to create Cloud Storage bucket"
        exit 1
    fi
    
    # Set bucket permissions for Cloud Functions service account
    local service_account="${PROJECT_ID}@appspot.gserviceaccount.com"
    if gsutil iam ch "serviceAccount:${service_account}:objectAdmin" "gs://$BUCKET_NAME"; then
        log_success "Set bucket permissions for Cloud Functions service account"
    else
        log_warning "Failed to set bucket permissions, functions may not have storage access"
    fi
}

# Function to create function source code
create_function_source() {
    local function_name="$1"
    local function_dir="$2"
    
    log_info "Creating source code for $function_name..."
    
    # Create function directory
    mkdir -p "$function_dir"
    
    if [ "$function_name" = "encoder" ]; then
        # Create encoder function source
        cat > "$function_dir/main.py" << 'EOF'
import base64
import json
import logging
from google.cloud import storage
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def encode_base64(request):
    """HTTP Cloud Function to encode text or files to Base64."""
    
    # Set CORS headers for browser compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Content-Type': 'application/json'
    }
    
    # Handle preflight requests
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        if request.method == 'POST':
            # Handle JSON input for text encoding
            if request.is_json:
                data = request.get_json()
                text_input = data.get('text', '')
                
                if not text_input:
                    return (json.dumps({'error': 'Text input required'}), 400, headers)
                
                # Encode text to Base64
                encoded = base64.b64encode(text_input.encode('utf-8')).decode('utf-8')
                
                response = {
                    'encoded': encoded,
                    'original_length': len(text_input),
                    'encoded_length': len(encoded)
                }
                
                logger.info(f"Successfully encoded {len(text_input)} characters")
                return (json.dumps(response), 200, headers)
            
            # Handle form data for file uploads
            elif 'file' in request.files:
                file = request.files['file']
                file_content = file.read()
                
                # Encode file content to Base64
                encoded = base64.b64encode(file_content).decode('utf-8')
                
                response = {
                    'encoded': encoded,
                    'filename': file.filename,
                    'original_size': len(file_content),
                    'encoded_size': len(encoded)
                }
                
                logger.info(f"Successfully encoded file: {file.filename}")
                return (json.dumps(response), 200, headers)
            
        # Handle GET requests with query parameters
        elif request.method == 'GET':
            query_text = request.args.get('text', '')
            
            if not query_text:
                return (json.dumps({'error': 'Text parameter required'}), 400, headers)
            
            encoded = base64.b64encode(query_text.encode('utf-8')).decode('utf-8')
            
            response = {
                'encoded': encoded,
                'original_length': len(query_text),
                'encoded_length': len(encoded)
            }
            
            return (json.dumps(response), 200, headers)
        
        return (json.dumps({'error': 'Invalid request method'}), 405, headers)
        
    except Exception as e:
        logger.error(f"Encoding error: {str(e)}")
        return (json.dumps({'error': 'Internal server error'}), 500, headers)
EOF
    else
        # Create decoder function source
        cat > "$function_dir/main.py" << 'EOF'
import base64
import json
import logging
from google.cloud import storage
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def decode_base64(request):
    """HTTP Cloud Function to decode Base64 text back to original format."""
    
    # Set CORS headers for browser compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Content-Type': 'application/json'
    }
    
    # Handle preflight requests
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        base64_input = ''
        
        if request.method == 'POST' and request.is_json:
            data = request.get_json()
            base64_input = data.get('encoded', '')
        elif request.method == 'GET':
            base64_input = request.args.get('encoded', '')
        
        if not base64_input:
            return (json.dumps({'error': 'Base64 encoded input required'}), 400, headers)
        
        # Validate and decode Base64 input
        try:
            # Remove any whitespace and validate Base64 format
            base64_input = base64_input.strip()
            decoded_bytes = base64.b64decode(base64_input, validate=True)
            
            # Attempt to decode as UTF-8 text
            try:
                decoded_text = decoded_bytes.decode('utf-8')
                is_text = True
            except UnicodeDecodeError:
                decoded_text = None
                is_text = False
            
            response = {
                'decoded': decoded_text if is_text else None,
                'is_text': is_text,
                'decoded_length': len(decoded_bytes),
                'original_length': len(base64_input)
            }
            
            if not is_text:
                response['message'] = 'Content appears to be binary data'
                response['size_bytes'] = len(decoded_bytes)
            
            logger.info(f"Successfully decoded {len(base64_input)} characters")
            return (json.dumps(response), 200, headers)
            
        except Exception as decode_error:
            logger.warning(f"Base64 decode error: {str(decode_error)}")
            return (json.dumps({
                'error': 'Invalid Base64 input',
                'details': 'Input must be valid Base64 encoded data'
            }), 400, headers)
        
    except Exception as e:
        logger.error(f"Decoder error: {str(e)}")
        return (json.dumps({'error': 'Internal server error'}), 500, headers)
EOF
    fi
    
    # Create requirements.txt
    cat > "$function_dir/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-storage==2.*
EOF
    
    log_success "Created source code for $function_name"
}

# Function to deploy Cloud Function
deploy_function() {
    local function_name="$1"
    local function_dir="$2"
    local entry_point="$3"
    
    log_info "Deploying $function_name Cloud Function..."
    
    # Change to function directory
    pushd "$function_dir" > /dev/null
    
    # Deploy function
    if gcloud functions deploy "$function_name" \
        --runtime python312 \
        --trigger-http \
        --source . \
        --entry-point "$entry_point" \
        --memory 256MB \
        --timeout 60s \
        --allow-unauthenticated \
        --max-instances 10 \
        --quiet; then
        log_success "Deployed $function_name successfully"
    else
        log_error "Failed to deploy $function_name"
        popd > /dev/null
        exit 1
    fi
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "$function_name" \
        --format="value(httpsTrigger.url)" 2>/dev/null)
    
    if [ -n "$function_url" ]; then
        log_success "$function_name URL: $function_url"
        
        # Store URL in environment variable for later use
        if [ "$function_name" = "$ENCODER_FUNCTION" ]; then
            export ENCODER_URL="$function_url"
        else
            export DECODER_URL="$function_url"
        fi
    else
        log_warning "Could not retrieve $function_name URL"
    fi
    
    popd > /dev/null
}

# Function to test deployed functions
test_functions() {
    log_info "Testing deployed functions..."
    
    if [ -z "${ENCODER_URL:-}" ] || [ -z "${DECODER_URL:-}" ]; then
        log_warning "Function URLs not available, skipping tests"
        return 0
    fi
    
    # Test encoder function
    log_info "Testing encoder function..."
    local test_text="Hello World"
    local encoded_result
    
    if encoded_result=$(curl -s -X GET "${ENCODER_URL}?text=${test_text}" | \
        python3 -c "import sys, json; print(json.load(sys.stdin)['encoded'])" 2>/dev/null); then
        log_success "Encoder test passed: '$test_text' -> '$encoded_result'"
        
        # Test decoder function
        log_info "Testing decoder function..."
        local decoded_result
        
        if decoded_result=$(curl -s -X GET "${DECODER_URL}?encoded=${encoded_result}" | \
            python3 -c "import sys, json; print(json.load(sys.stdin)['decoded'])" 2>/dev/null); then
            
            if [ "$test_text" = "$decoded_result" ]; then
                log_success "Decoder test passed: '$encoded_result' -> '$decoded_result'"
                log_success "Round-trip test successful!"
            else
                log_warning "Round-trip test failed: '$test_text' != '$decoded_result'"
            fi
        else
            log_warning "Decoder test failed"
        fi
    else
        log_warning "Encoder test failed"
    fi
}

# Function to save deployment information
save_deployment_info() {
    local info_file="deployment-info.json"
    
    log_info "Saving deployment information to $info_file..."
    
    # Get function URLs
    local encoder_url decoder_url
    encoder_url=$(gcloud functions describe "$ENCODER_FUNCTION" \
        --format="value(httpsTrigger.url)" 2>/dev/null || echo "")
    decoder_url=$(gcloud functions describe "$DECODER_FUNCTION" \
        --format="value(httpsTrigger.url)" 2>/dev/null || echo "")
    
    # Create deployment info JSON
    cat > "$info_file" << EOF
{
  "deployment_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "bucket_name": "$BUCKET_NAME",
  "encoder_function": {
    "name": "$ENCODER_FUNCTION",
    "url": "$encoder_url"
  },
  "decoder_function": {
    "name": "$DECODER_FUNCTION",
    "url": "$decoder_url"
  },
  "resources": [
    "gs://$BUCKET_NAME",
    "projects/$PROJECT_ID/locations/$REGION/functions/$ENCODER_FUNCTION",
    "projects/$PROJECT_ID/locations/$REGION/functions/$DECODER_FUNCTION"
  ]
}
EOF
    
    log_success "Deployment information saved to $info_file"
}

# Function to display deployment summary
display_summary() {
    log_info "=== DEPLOYMENT SUMMARY ==="
    log_success "✅ Cloud Storage bucket: gs://$BUCKET_NAME"
    log_success "✅ Encoder function: $ENCODER_FUNCTION"
    log_success "✅ Decoder function: $DECODER_FUNCTION"
    
    if [ -n "${ENCODER_URL:-}" ]; then
        log_info "🔗 Encoder URL: $ENCODER_URL"
    fi
    
    if [ -n "${DECODER_URL:-}" ]; then
        log_info "🔗 Decoder URL: $DECODER_URL"
    fi
    
    log_info ""
    log_info "Example usage:"
    log_info "  # Encode text:"
    log_info "  curl -X GET \"${ENCODER_URL:-YOUR_ENCODER_URL}?text=Hello%20World\""
    log_info ""
    log_info "  # Decode Base64:"
    log_info "  curl -X GET \"${DECODER_URL:-YOUR_DECODER_URL}?encoded=SGVsbG8gV29ybGQ=\""
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
    log_info "=========================="
}

# Main deployment function
main() {
    log_info "Starting Base64 Encoder Decoder Functions deployment..."
    
    # Validate prerequisites
    validate_prerequisites
    
    # Prompt for configuration
    prompt_configuration
    
    # Set up GCP configuration
    setup_gcp_config
    
    # Enable required APIs
    enable_apis
    
    # Create Cloud Storage bucket
    create_storage_bucket
    
    # Create and deploy encoder function
    create_function_source "encoder" "encoder-function"
    deploy_function "$ENCODER_FUNCTION" "encoder-function" "encode_base64"
    
    # Create and deploy decoder function
    create_function_source "decoder" "decoder-function"
    deploy_function "$DECODER_FUNCTION" "decoder-function" "decode_base64"
    
    # Test functions
    test_functions
    
    # Save deployment information
    save_deployment_info
    
    # Display summary
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Cleanup function for script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed with exit code $exit_code"
        log_info "Check the logs above for error details"
        log_info "You may need to clean up partially created resources"
    fi
}

# Set trap for cleanup
trap cleanup_on_exit EXIT

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi