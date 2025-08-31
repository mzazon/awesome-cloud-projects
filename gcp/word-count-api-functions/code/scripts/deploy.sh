#!/bin/bash

# Deploy Word Count API with Cloud Functions
# This script deploys a serverless HTTP API for text analysis using Google Cloud Functions
# 
# Prerequisites:
# - Google Cloud CLI (gcloud) installed and configured
# - Active Google Cloud project with billing enabled
# - Required APIs enabled (Cloud Functions, Cloud Storage, Cloud Build, Cloud Run)
# - Appropriate IAM permissions for resource creation
#
# Usage: ./deploy.sh [--project PROJECT_ID] [--region REGION] [--dry-run]

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration values
DEFAULT_PROJECT_ID=""
DEFAULT_REGION="us-central1"
DEFAULT_FUNCTION_NAME="word-count-api"
DRY_RUN=false

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TEMP_DIR=$(mktemp -d)

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed. Check ${LOG_FILE} for details."
    fi
    exit $exit_code
}

trap cleanup EXIT

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Word Count API with Cloud Functions

OPTIONS:
    --project PROJECT_ID    Google Cloud Project ID (required if not set in gcloud config)
    --region REGION         Deployment region (default: us-central1)
    --function-name NAME    Cloud Function name (default: word-count-api)
    --dry-run              Show what would be deployed without making changes
    --help                 Show this help message

EXAMPLES:
    $0 --project my-project-123
    $0 --project my-project-123 --region us-east1 --dry-run
    $0 --help

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project)
                DEFAULT_PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                DEFAULT_REGION="$2"
                shift 2
                ;;
            --function-name)
                DEFAULT_FUNCTION_NAME="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
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
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_error "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated with gcloud
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -n1 > /dev/null 2>&1; then
        log_error "Not authenticated with Google Cloud"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    # Get current project if not specified
    if [[ -z "$DEFAULT_PROJECT_ID" ]]; then
        DEFAULT_PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$DEFAULT_PROJECT_ID" ]]; then
            log_error "No project specified and no default project configured"
            log_error "Please specify --project PROJECT_ID or run: gcloud config set project PROJECT_ID"
            exit 1
        fi
    fi
    
    # Validate project exists and is accessible
    if ! gcloud projects describe "$DEFAULT_PROJECT_ID" > /dev/null 2>&1; then
        log_error "Cannot access project: $DEFAULT_PROJECT_ID"
        log_error "Please check that the project exists and you have access"
        exit 1
    fi
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "$DEFAULT_PROJECT_ID" > /dev/null 2>&1; then
        log_warn "Cannot verify billing status for project: $DEFAULT_PROJECT_ID"
        log_warn "Ensure billing is enabled to avoid deployment failures"
    fi
    
    log_success "Prerequisites check completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
        "logging.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: ${apis[*]}"
        return 0
    fi
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --project="$DEFAULT_PROJECT_ID" >> "$LOG_FILE" 2>&1; then
            log_success "Enabled $api"
        else
            log_error "Failed to enable $api"
            return 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 10
}

# Generate unique resource names
generate_names() {
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 6)
    export PROJECT_ID="$DEFAULT_PROJECT_ID"
    export REGION="$DEFAULT_REGION"
    export FUNCTION_NAME="$DEFAULT_FUNCTION_NAME"
    export BUCKET_NAME="word-count-files-${RANDOM_SUFFIX}"
    
    log_info "Generated resource names:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Function Name: $FUNCTION_NAME"
    log_info "  Bucket Name: $BUCKET_NAME"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: $BUCKET_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create bucket: gs://$BUCKET_NAME"
        return 0
    fi
    
    # Check if bucket already exists
    if gcloud storage buckets describe "gs://$BUCKET_NAME" > /dev/null 2>&1; then
        log_warn "Bucket gs://$BUCKET_NAME already exists, skipping creation"
        return 0
    fi
    
    # Create bucket with uniform bucket-level access
    if gcloud storage buckets create "gs://$BUCKET_NAME" \
        --location="$REGION" \
        --uniform-bucket-level-access \
        --project="$PROJECT_ID" >> "$LOG_FILE" 2>&1; then
        log_success "Created bucket: gs://$BUCKET_NAME"
    else
        log_error "Failed to create bucket: gs://$BUCKET_NAME"
        return 1
    fi
    
    # Set IAM permissions for function access
    local service_account="${PROJECT_ID}@appspot.gserviceaccount.com"
    
    if gcloud storage buckets add-iam-policy-binding "gs://$BUCKET_NAME" \
        --member="serviceAccount:$service_account" \
        --role="roles/storage.objectViewer" \
        --project="$PROJECT_ID" >> "$LOG_FILE" 2>&1; then
        log_success "Set IAM permissions for bucket access"
    else
        log_error "Failed to set IAM permissions for bucket"
        return 1
    fi
}

# Create function source code
create_function_source() {
    log_info "Creating Cloud Function source code..."
    
    local function_dir="$TEMP_DIR/word-count-function"
    mkdir -p "$function_dir"
    
    # Create main.py
    cat > "$function_dir/main.py" << 'EOF'
import json
import re
from google.cloud import storage
from flask import Request
import functions_framework

def analyze_text(text):
    """Analyze text and return comprehensive statistics."""
    if not text or not text.strip():
        return {
            'word_count': 0,
            'character_count': 0,
            'character_count_no_spaces': 0,
            'paragraph_count': 0,
            'estimated_reading_time_minutes': 0
        }
    
    # Word count (split by whitespace, filter empty strings)
    words = [word for word in re.findall(r'\b\w+\b', text.lower())]
    word_count = len(words)
    
    # Character counts
    character_count = len(text)
    character_count_no_spaces = len(text.replace(' ', '').replace('\t', '').replace('\n', ''))
    
    # Paragraph count (split by double newlines or single newlines)
    paragraphs = [p.strip() for p in text.split('\n') if p.strip()]
    paragraph_count = len(paragraphs)
    
    # Estimated reading time (200 words per minute average)
    estimated_reading_time_minutes = max(1, round(word_count / 200)) if word_count > 0 else 0
    
    return {
        'word_count': word_count,
        'character_count': character_count,
        'character_count_no_spaces': character_count_no_spaces,
        'paragraph_count': paragraph_count,
        'estimated_reading_time_minutes': estimated_reading_time_minutes
    }

@functions_framework.http
def word_count_api(request: Request):
    """HTTP Cloud Function for text analysis."""
    # Set CORS headers
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    if request.method == 'GET':
        return ({
            'message': 'Word Count API is running',
            'usage': {
                'POST /': 'Analyze text from request body',
                'POST / with file_path': 'Analyze text from Cloud Storage file'
            }
        }, 200, headers)
    
    if request.method != 'POST':
        return ({'error': 'Method not allowed'}, 405, headers)
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        
        if not request_json:
            return ({'error': 'Invalid JSON in request body'}, 400, headers)
        
        # Check if analyzing text from Cloud Storage file
        if 'file_path' in request_json:
            bucket_name = request_json.get('bucket_name')
            file_path = request_json['file_path']
            
            if not bucket_name:
                return ({'error': 'bucket_name required when using file_path'}, 400, headers)
            
            # Download file from Cloud Storage
            storage_client = storage.Client()
            bucket = storage_client.bucket(bucket_name)
            blob = bucket.blob(file_path)
            
            if not blob.exists():
                return ({'error': f'File not found: {file_path}'}, 404, headers)
            
            text_content = blob.download_as_text()
        
        # Check if analyzing direct text input
        elif 'text' in request_json:
            text_content = request_json['text']
        
        else:
            return ({'error': 'Either "text" or "file_path" required in request body'}, 400, headers)
        
        # Analyze the text
        analysis_result = analyze_text(text_content)
        
        # Add metadata to response
        response_data = {
            'analysis': analysis_result,
            'input_source': 'file' if 'file_path' in request_json else 'direct_text',
            'api_version': '1.0'
        }
        
        return (response_data, 200, headers)
    
    except Exception as e:
        return ({'error': f'Internal server error: {str(e)}'}, 500, headers)
EOF
    
    # Create requirements.txt
    cat > "$function_dir/requirements.txt" << 'EOF'
google-cloud-storage==2.17.0
functions-framework==3.8.1
EOF
    
    log_success "Created function source code in: $function_dir"
    echo "$function_dir"
}

# Deploy Cloud Function
deploy_function() {
    local function_dir="$1"
    log_info "Deploying Cloud Function: $FUNCTION_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy function: $FUNCTION_NAME"
        log_info "[DRY RUN] Source directory: $function_dir"
        log_info "[DRY RUN] Configuration:"
        log_info "[DRY RUN]   Runtime: python312"
        log_info "[DRY RUN]   Memory: 256Mi"
        log_info "[DRY RUN]   Timeout: 60s"
        log_info "[DRY RUN]   Max instances: 10"
        return 0
    fi
    
    # Deploy the function
    if gcloud functions deploy "$FUNCTION_NAME" \
        --gen2 \
        --runtime=python312 \
        --source="$function_dir" \
        --entry-point=word_count_api \
        --trigger=http \
        --allow-unauthenticated \
        --memory=256Mi \
        --timeout=60s \
        --max-instances=10 \
        --region="$REGION" \
        --project="$PROJECT_ID" >> "$LOG_FILE" 2>&1; then
        
        log_success "Successfully deployed Cloud Function: $FUNCTION_NAME"
        
        # Get function URL
        local function_url
        function_url=$(gcloud functions describe "$FUNCTION_NAME" \
            --gen2 \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --format="value(serviceConfig.uri)" 2>/dev/null)
        
        if [[ -n "$function_url" ]]; then
            log_success "Function URL: $function_url"
            echo "$function_url" > "${SCRIPT_DIR}/.function_url"
        fi
        
        return 0
    else
        log_error "Failed to deploy Cloud Function: $FUNCTION_NAME"
        return 1
    fi
}

# Test the deployed function
test_function() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would test the deployed function"
        return 0
    fi
    
    log_info "Testing deployed function..."
    
    # Get function URL
    local function_url
    if [[ -f "${SCRIPT_DIR}/.function_url" ]]; then
        function_url=$(cat "${SCRIPT_DIR}/.function_url")
    else
        function_url=$(gcloud functions describe "$FUNCTION_NAME" \
            --gen2 \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --format="value(serviceConfig.uri)" 2>/dev/null)
    fi
    
    if [[ -z "$function_url" ]]; then
        log_warn "Could not retrieve function URL for testing"
        return 0
    fi
    
    # Test GET endpoint (health check)
    log_info "Testing GET endpoint..."
    if curl -s -f -X GET "$function_url" > /dev/null 2>&1; then
        log_success "GET endpoint responding correctly"
    else
        log_warn "GET endpoint test failed"
    fi
    
    # Test POST endpoint with sample text
    log_info "Testing POST endpoint with sample text..."
    local test_response
    test_response=$(curl -s -X POST "$function_url" \
        -H "Content-Type: application/json" \
        -d '{"text": "Hello world! This is a test."}' 2>/dev/null)
    
    if [[ -n "$test_response" ]] && echo "$test_response" | grep -q "word_count"; then
        log_success "POST endpoint responding correctly"
        log_info "Sample response: $test_response"
    else
        log_warn "POST endpoint test failed or returned unexpected response"
    fi
}

# Create deployment summary
create_summary() {
    local summary_file="${SCRIPT_DIR}/deployment-summary.txt"
    
    log_info "Creating deployment summary..."
    
    cat > "$summary_file" << EOF
Word Count API Deployment Summary
=================================

Deployment Date: $(date)
Project ID: $PROJECT_ID
Region: $REGION

Resources Created:
- Cloud Function: $FUNCTION_NAME
- Storage Bucket: gs://$BUCKET_NAME

Function Details:
- Runtime: Python 3.12
- Memory: 256Mi
- Timeout: 60s
- Max Instances: 10
- Trigger: HTTP
- Authentication: Unauthenticated (public)

EOF
    
    # Add function URL if available
    if [[ -f "${SCRIPT_DIR}/.function_url" ]]; then
        local function_url
        function_url=$(cat "${SCRIPT_DIR}/.function_url")
        echo "Function URL: $function_url" >> "$summary_file"
        echo "" >> "$summary_file"
    fi
    
    cat >> "$summary_file" << EOF
Usage Examples:
1. Health check:
   curl -X GET [FUNCTION_URL]

2. Analyze text directly:
   curl -X POST [FUNCTION_URL] \\
     -H "Content-Type: application/json" \\
     -d '{"text": "Your text here"}'

3. Analyze file from Cloud Storage:
   curl -X POST [FUNCTION_URL] \\
     -H "Content-Type: application/json" \\
     -d '{"bucket_name": "$BUCKET_NAME", "file_path": "your-file.txt"}'

Cleanup:
To remove all resources, run: ./destroy.sh --project $PROJECT_ID

Log File: $LOG_FILE
EOF
    
    log_success "Deployment summary created: $summary_file"
}

# Main deployment function
main() {
    # Initialize log file
    echo "=== Word Count API Deployment Started at $(date) ===" > "$LOG_FILE"
    
    log_info "Starting Word Count API deployment..."
    
    # Parse command line arguments
    parse_args "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Generate resource names
    generate_names
    
    # Enable required APIs
    enable_apis
    
    # Create Cloud Storage bucket
    create_storage_bucket
    
    # Create function source code
    local function_dir
    function_dir=$(create_function_source)
    
    # Deploy Cloud Function
    deploy_function "$function_dir"
    
    # Test the function
    test_function
    
    # Create deployment summary
    create_summary
    
    log_success "Word Count API deployment completed successfully!"
    log_info "Check deployment-summary.txt for details and usage examples"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] No actual resources were created"
    fi
}

# Execute main function with all arguments
main "$@"