#!/bin/bash

# Form Data Validation with Cloud Functions and Firestore - Deployment Script
# This script deploys the complete infrastructure for the form validation solution
# including Cloud Functions, Firestore database, and required APIs

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE" >&2
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check $ERROR_LOG for details."
    log_info "To clean up resources, run: ./destroy.sh"
    exit 1
}

trap cleanup_on_error ERR

# Initialize logging
exec 2> >(tee -a "$ERROR_LOG")
log_info "Starting deployment at $(date)"

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --format="value(account)" --filter="status:ACTIVE" | head -1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values or use existing environment variables
    export PROJECT_ID="${PROJECT_ID:-form-validation-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export FUNCTION_NAME="${FUNCTION_NAME:-validate-form-data}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Function Name: $FUNCTION_NAME"
    log_info "Random Suffix: $RANDOM_SUFFIX"
    
    # Save environment variables for destroy script
    cat > "${SCRIPT_DIR}/.env" << EOF
PROJECT_ID=$PROJECT_ID
REGION=$REGION
FUNCTION_NAME=$FUNCTION_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    log_success "Environment variables configured"
}

# Create and configure GCP project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_warning "Project $PROJECT_ID already exists. Using existing project."
    else
        log_info "Creating new project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" --name="Form Validation Tutorial" || {
            log_error "Failed to create project. You may need billing permissions."
            exit 1
        }
    fi
    
    # Set current project
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    
    log_success "Project configured: $PROJECT_ID"
}

# Enable required Google Cloud APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com"
        "logging.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "APIs enabled successfully"
}

# Initialize Firestore database
setup_firestore() {
    log_info "Setting up Firestore database..."
    
    # Check if Firestore database already exists
    if gcloud firestore databases describe --database="(default)" &> /dev/null; then
        log_warning "Firestore database already exists. Skipping creation."
    else
        log_info "Creating Firestore database in native mode..."
        gcloud firestore databases create \
            --location="$REGION" \
            --type=firestore-native \
            --quiet
        
        # Wait for database to be ready
        log_info "Waiting for Firestore to be ready..."
        sleep 20
    fi
    
    log_success "Firestore database configured"
}

# Create Cloud Function source code
create_function_source() {
    log_info "Creating Cloud Function source code..."
    
    local function_dir="${SCRIPT_DIR}/../function-source"
    mkdir -p "$function_dir"
    
    # Create requirements.txt
    cat > "$function_dir/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-firestore>=2.0.0
google-cloud-logging>=3.0.0
EOF
    
    # Create main.py with the function code
    cat > "$function_dir/main.py" << 'EOF'
import functions_framework
import json
import re
from google.cloud import firestore
from google.cloud import logging as cloud_logging
import logging
from datetime import datetime

# Initialize Firestore client
db = firestore.Client()

# Initialize Cloud Logging
logging_client = cloud_logging.Client()
logging_client.setup_logging()

def validate_email(email):
    """Validate email format using regex pattern"""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return re.match(pattern, email) is not None

def validate_phone(phone):
    """Validate phone number (basic US format)"""
    # Remove all non-digits
    clean_phone = re.sub(r'\D', '', phone)
    return len(clean_phone) == 10

def sanitize_string(value, max_length=100):
    """Sanitize string input by trimming and limiting length"""
    if not isinstance(value, str):
        return ""
    return value.strip()[:max_length]

@functions_framework.http
def validate_form_data(request):
    """
    HTTP Cloud Function for form data validation and storage
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
    
    # Only accept POST requests for form submission
    if request.method != 'POST':
        return (json.dumps({'error': 'Method not allowed'}), 405, headers)
    
    try:
        # Parse JSON request body
        request_json = request.get_json(silent=True)
        if not request_json:
            return (json.dumps({'error': 'Invalid JSON payload'}), 400, headers)
        
        # Extract and validate form fields
        errors = []
        
        # Validate required name field
        name = sanitize_string(request_json.get('name', ''))
        if not name:
            errors.append('Name is required')
        elif len(name) < 2:
            errors.append('Name must be at least 2 characters')
        
        # Validate email field
        email = sanitize_string(request_json.get('email', ''))
        if not email:
            errors.append('Email is required')
        elif not validate_email(email):
            errors.append('Invalid email format')
        
        # Validate phone field (optional)
        phone = sanitize_string(request_json.get('phone', ''))
        if phone and not validate_phone(phone):
            errors.append('Invalid phone number format')
        
        # Validate message field
        message = sanitize_string(request_json.get('message', ''), 500)
        if not message:
            errors.append('Message is required')
        elif len(message) < 10:
            errors.append('Message must be at least 10 characters')
        
        # Return validation errors if any
        if errors:
            logging.warning(f'Form validation failed: {errors}')
            return (json.dumps({
                'success': False,
                'errors': errors
            }), 400, headers)
        
        # Create document data for Firestore
        form_data = {
            'name': name,
            'email': email.lower(),  # Normalize email to lowercase
            'phone': re.sub(r'\D', '', phone) if phone else None,
            'message': message,
            'submitted_at': datetime.utcnow(),
            'source': 'web_form'
        }
        
        # Store validated data in Firestore
        doc_ref = db.collection('form_submissions').add(form_data)
        document_id = doc_ref[1].id
        
        # Log successful submission
        logging.info(f'Form submitted successfully: {document_id}')
        
        # Return success response
        return (json.dumps({
            'success': True,
            'message': 'Form submitted successfully',
            'id': document_id
        }), 200, headers)
        
    except Exception as e:
        # Log error and return generic error response
        logging.error(f'Function error: {str(e)}')
        return (json.dumps({
            'success': False,
            'error': 'Internal server error'
        }), 500, headers)
EOF
    
    log_success "Function source code created at $function_dir"
}

# Deploy Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function..."
    
    local function_dir="${SCRIPT_DIR}/../function-source"
    
    # Deploy function with HTTP trigger
    gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --region "$REGION" \
        --source "$function_dir" \
        --entry-point validate_form_data \
        --memory 256MB \
        --timeout 60s \
        --gen2 \
        --quiet
    
    # Get function URL for testing
    FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    # Save function URL to environment
    echo "FUNCTION_URL=$FUNCTION_URL" >> "${SCRIPT_DIR}/.env"
    
    log_success "Function deployed successfully"
    log_info "Function URL: $FUNCTION_URL"
}

# Test the deployed function
test_function() {
    log_info "Testing deployed function..."
    
    # Source environment to get function URL
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/.env"
    
    if [[ -z "${FUNCTION_URL:-}" ]]; then
        log_error "Function URL not found. Deployment may have failed."
        return 1
    fi
    
    # Test with valid data
    log_info "Testing with valid form data..."
    local test_response
    test_response=$(curl -s -X POST "$FUNCTION_URL" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Test User",
            "email": "test@example.com",
            "phone": "555-123-4567",
            "message": "This is a test message for the form validation system."
        }')
    
    if echo "$test_response" | grep -q '"success": true'; then
        log_success "Valid data test passed"
    else
        log_warning "Valid data test failed: $test_response"
    fi
    
    # Test with invalid data
    log_info "Testing with invalid form data..."
    local invalid_response
    invalid_response=$(curl -s -X POST "$FUNCTION_URL" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "A",
            "email": "invalid-email",
            "phone": "123",
            "message": "Short"
        }')
    
    if echo "$invalid_response" | grep -q '"success": false'; then
        log_success "Invalid data test passed"
    else
        log_warning "Invalid data test failed: $invalid_response"
    fi
    
    log_success "Function testing completed"
}

# Display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "======================================"
    
    # Source environment variables
    # shellcheck source=/dev/null
    source "${SCRIPT_DIR}/.env"
    
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Function Name: $FUNCTION_NAME"
    echo "Function URL: ${FUNCTION_URL:-Not available}"
    echo ""
    echo "Resources Created:"
    echo "- Google Cloud Project: $PROJECT_ID"
    echo "- Firestore Database: Native mode in $REGION"
    echo "- Cloud Function: $FUNCTION_NAME"
    echo "- Enabled APIs: Cloud Functions, Firestore, Cloud Logging"
    echo ""
    echo "Next Steps:"
    echo "1. Test the function using the provided URL"
    echo "2. View Firestore data at: https://console.cloud.google.com/firestore/data?project=$PROJECT_ID"
    echo "3. Monitor logs at: https://console.cloud.google.com/functions/details/$REGION/$FUNCTION_NAME?project=$PROJECT_ID"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo "======================================"
}

# Main deployment function
main() {
    log_info "Starting Form Data Validation deployment..."
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    setup_firestore
    create_function_source
    deploy_function
    test_function
    display_summary
    
    log_success "Deployment completed successfully at $(date)"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi