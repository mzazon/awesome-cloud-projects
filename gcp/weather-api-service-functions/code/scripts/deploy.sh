#!/bin/bash

# deploy.sh - Deploy Weather API Service with Cloud Functions
# This script deploys a serverless weather API using Google Cloud Functions and Storage
# Based on recipe: Weather API Service with Cloud Functions

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
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    if [[ -n "${BUCKET_NAME:-}" ]] && gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warning "Removing storage bucket: ${BUCKET_NAME}"
        gsutil -m rm -r "gs://${BUCKET_NAME}" 2>/dev/null || true
    fi
    if [[ -n "${FUNCTION_NAME:-}" ]] && gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        log_warning "Removing cloud function: ${FUNCTION_NAME}"
        gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet 2>/dev/null || true
    fi
    exit 1
}

trap cleanup_on_error ERR

# Configuration validation
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_error "Please install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please install Google Cloud SDK"
        exit 1
    fi
    
    # Check if jq is installed (for JSON parsing)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Installing jq for JSON parsing..."
        # Attempt to install jq based on OS
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install jq
            else
                log_error "Please install jq manually: brew install jq"
                exit 1
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y jq
            elif command -v yum &> /dev/null; then
                sudo yum install -y jq
            else
                log_error "Please install jq manually for your Linux distribution"
                exit 1
            fi
        else
            log_error "Please install jq manually for your operating system"
            exit 1
        fi
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &>/dev/null; then
        log_error "No active Google Cloud authentication found"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Project configuration
configure_project() {
    log_info "Configuring Google Cloud project..."
    
    # Set default project if not already set or if PROJECT_ID is provided
    if [[ -n "${PROJECT_ID:-}" ]]; then
        log_info "Using provided PROJECT_ID: ${PROJECT_ID}"
        gcloud config set project "${PROJECT_ID}"
    else
        # Get current project or prompt user
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "No project ID specified. Please set PROJECT_ID environment variable or run:"
            log_error "gcloud config set project YOUR_PROJECT_ID"
            exit 1
        fi
    fi
    
    # Verify project exists and billing is enabled
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Project ${PROJECT_ID} does not exist or you don't have access"
        exit 1
    fi
    
    # Check billing account (warning only)
    if ! gcloud billing projects describe "${PROJECT_ID}" --format="value(billingEnabled)" 2>/dev/null | grep -q "True"; then
        log_warning "Billing may not be enabled for project ${PROJECT_ID}"
        log_warning "Some services may not work without billing enabled"
    fi
    
    log_success "Project configured: ${PROJECT_ID}"
}

# Environment setup
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set defaults if not provided
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
    export REGION="${REGION:-us-central1}"
    export FUNCTION_NAME="${FUNCTION_NAME:-weather-api}"
    
    # Generate unique suffix for resources
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        if command -v openssl &> /dev/null; then
            RANDOM_SUFFIX=$(openssl rand -hex 3)
        else
            RANDOM_SUFFIX=$(date +%s | tail -c 7)
        fi
    fi
    export BUCKET_NAME="${BUCKET_NAME:-weather-cache-${RANDOM_SUFFIX}}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set functions/region "${REGION}"
    
    log_success "Environment configured:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Function Name: ${FUNCTION_NAME}"
    log_info "  Bucket Name: ${BUCKET_NAME}"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 10
    
    log_success "All required APIs enabled"
}

# Create storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for caching..."
    
    # Check if bucket already exists
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists"
        return 0
    fi
    
    # Create bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        log_success "Storage bucket created: gs://${BUCKET_NAME}"
    else
        log_error "Failed to create storage bucket"
        exit 1
    fi
    
    # Create lifecycle policy
    log_info "Setting up lifecycle policy for cache expiration..."
    cat > /tmp/lifecycle.json << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"age": 1}
      }
    ]
  }
}
EOF
    
    if gsutil lifecycle set /tmp/lifecycle.json "gs://${BUCKET_NAME}"; then
        log_success "Lifecycle policy applied (24-hour cache expiration)"
    else
        log_error "Failed to apply lifecycle policy"
        exit 1
    fi
    
    # Clean up temporary file
    rm -f /tmp/lifecycle.json
}

# Create function source code
create_function_code() {
    log_info "Creating Cloud Function source code..."
    
    # Create function directory
    local function_dir="/tmp/weather-function-$$"
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.8.1
requests==2.32.3
google-cloud-storage==2.18.0
EOF
    
    # Create main.py with the function code
    cat > main.py << 'EOF'
import json
import requests
import os
from datetime import datetime, timedelta
from google.cloud import storage
from functions_framework import http

# Initialize storage client
storage_client = storage.Client()
BUCKET_NAME = os.environ.get('WEATHER_CACHE_BUCKET')
API_KEY = os.environ.get('OPENWEATHER_API_KEY', 'demo_key')

@http
def weather_api(request):
    """HTTP Cloud Function to provide weather data with caching."""
    
    # Enable CORS for web applications
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Extract city parameter from request
    city = request.args.get('city', 'London')
    
    # Validate city parameter
    if not city or len(city.strip()) == 0:
        headers = {'Access-Control-Allow-Origin': '*'}
        return (json.dumps({'error': 'City parameter is required'}), 400, headers)
    
    try:
        # Check cache first
        cache_key = f"weather_{city.lower().replace(' ', '_')}.json"
        weather_data = get_cached_weather(cache_key)
        
        if not weather_data:
            # Fetch from external API if not cached
            weather_data = fetch_weather_data(city)
            if weather_data:
                cache_weather_data(cache_key, weather_data)
        
        if weather_data:
            response_data = {
                'city': city,
                'temperature': weather_data.get('main', {}).get('temp'),
                'description': weather_data.get('weather', [{}])[0].get('description'),
                'humidity': weather_data.get('main', {}).get('humidity'),
                'pressure': weather_data.get('main', {}).get('pressure'),
                'wind_speed': weather_data.get('wind', {}).get('speed'),
                'cached': 'cached' in weather_data,
                'timestamp': datetime.now().isoformat()
            }
            
            headers = {'Access-Control-Allow-Origin': '*'}
            return (json.dumps(response_data), 200, headers)
        else:
            headers = {'Access-Control-Allow-Origin': '*'}
            return (json.dumps({'error': 'Weather data not available'}), 503, headers)
            
    except Exception as e:
        print(f"Error processing weather request: {str(e)}")
        headers = {'Access-Control-Allow-Origin': '*'}
        return (json.dumps({'error': 'Internal server error'}), 500, headers)

def get_cached_weather(cache_key):
    """Retrieve weather data from Cloud Storage cache."""
    try:
        if not BUCKET_NAME:
            return None
        
        bucket = storage_client.bucket(BUCKET_NAME)
        blob = bucket.blob(cache_key)
        
        if blob.exists():
            data = json.loads(blob.download_as_text())
            data['cached'] = True
            return data
    except Exception as e:
        print(f"Cache retrieval error: {str(e)}")
    return None

def cache_weather_data(cache_key, data):
    """Store weather data in Cloud Storage cache."""
    try:
        if not BUCKET_NAME:
            return
        
        bucket = storage_client.bucket(BUCKET_NAME)
        blob = bucket.blob(cache_key)
        blob.upload_from_string(json.dumps(data))
        print(f"Weather data cached for key: {cache_key}")
    except Exception as e:
        print(f"Cache storage error: {str(e)}")

def fetch_weather_data(city):
    """Fetch weather data from OpenWeatherMap API."""
    if API_KEY == 'demo_key':
        # Return demo data when no API key is provided
        return {
            'main': {'temp': 20, 'humidity': 65, 'pressure': 1013},
            'weather': [{'description': 'clear sky'}],
            'wind': {'speed': 3.5}
        }
    
    url = "https://api.openweathermap.org/data/2.5/weather"
    params = {
        'q': city,
        'appid': API_KEY,
        'units': 'metric'
    }
    
    try:
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Weather API request error: {str(e)}")
        return None
    except Exception as e:
        print(f"Unexpected error fetching weather data: {str(e)}")
        return None
EOF
    
    log_success "Function source code created in ${function_dir}"
    export FUNCTION_SOURCE_DIR="${function_dir}"
}

# Deploy Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function..."
    
    cd "${FUNCTION_SOURCE_DIR}"
    
    # Deploy function with proper configuration
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python312 \
        --trigger-http \
        --source . \
        --entry-point weather_api \
        --memory 256MB \
        --timeout 60s \
        --set-env-vars "WEATHER_CACHE_BUCKET=${BUCKET_NAME}" \
        --allow-unauthenticated \
        --region "${REGION}" \
        --quiet; then
        log_success "Cloud Function deployed successfully"
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region "${REGION}" \
        --format="value(serviceConfig.uri)")
    
    if [[ -n "${function_url}" ]]; then
        export FUNCTION_URL="${function_url}"
        log_success "Function URL: ${FUNCTION_URL}"
    else
        log_error "Failed to retrieve function URL"
        exit 1
    fi
}

# Configure IAM permissions
configure_permissions() {
    log_info "Configuring IAM permissions..."
    
    # Get the default compute service account
    local compute_sa="${PROJECT_ID}-compute@developer.gserviceaccount.com"
    
    # Grant storage access to the function's service account
    if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
        --member="serviceAccount:${compute_sa}" \
        --role="roles/storage.objectAdmin" \
        --condition="expression=resource.name.startsWith('projects/_/buckets/${BUCKET_NAME}')" \
        --quiet; then
        log_success "Storage permissions configured for function service account"
    else
        log_warning "Failed to configure storage permissions (function may still work with demo data)"
    fi
}

# Test deployment
test_deployment() {
    log_info "Testing deployment..."
    
    # Wait for function to be fully ready
    log_info "Waiting for function to be fully ready..."
    sleep 15
    
    # Test basic functionality
    log_info "Testing weather API with default city (London)..."
    local response
    if response=$(curl -s -w "HTTP_CODE:%{http_code}" "${FUNCTION_URL}?city=London"); then
        local http_code="${response##*HTTP_CODE:}"
        local body="${response%HTTP_CODE:*}"
        
        if [[ "${http_code}" == "200" ]]; then
            log_success "API test successful!"
            log_info "Response: ${body}"
            
            # Validate JSON response
            if echo "${body}" | jq -e '.city' &>/dev/null; then
                log_success "JSON response format validated"
            else
                log_warning "Response is not valid JSON, but HTTP status is OK"
            fi
        else
            log_warning "API returned HTTP ${http_code}: ${body}"
        fi
    else
        log_warning "Failed to test API endpoint"
    fi
    
    # Test caching by making a second request
    log_info "Testing caching mechanism..."
    if response=$(curl -s "${FUNCTION_URL}?city=London" | jq -r '.cached // "false"' 2>/dev/null); then
        if [[ "${response}" == "true" ]]; then
            log_success "Caching mechanism working correctly"
        else
            log_info "Cache not yet populated (expected on first deployment)"
        fi
    fi
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local deployment_file="./weather-api-deployment.json"
    cat > "${deployment_file}" << EOF
{
  "project_id": "${PROJECT_ID}",
  "region": "${REGION}",
  "function_name": "${FUNCTION_NAME}",
  "bucket_name": "${BUCKET_NAME}",
  "function_url": "${FUNCTION_URL}",
  "deployed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "deployment_script": "deploy.sh"
}
EOF
    
    log_success "Deployment information saved to ${deployment_file}"
}

# Cleanup temporary files
cleanup_temp_files() {
    if [[ -n "${FUNCTION_SOURCE_DIR:-}" ]] && [[ -d "${FUNCTION_SOURCE_DIR}" ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf "${FUNCTION_SOURCE_DIR}"
        log_success "Temporary files cleaned up"
    fi
}

# Main execution
main() {
    log_info "Starting Weather API Service deployment..."
    log_info "========================================"
    
    validate_prerequisites
    configure_project
    setup_environment
    enable_apis
    create_storage_bucket
    create_function_code
    deploy_function
    configure_permissions
    test_deployment
    save_deployment_info
    cleanup_temp_files
    
    log_success "========================================"
    log_success "Weather API Service deployed successfully!"
    log_success "========================================"
    log_info "Deployment Summary:"
    log_info "  Project: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Function: ${FUNCTION_NAME}"
    log_info "  Storage Bucket: ${BUCKET_NAME}"
    log_info "  API Endpoint: ${FUNCTION_URL}"
    log_info ""
    log_info "Test your API:"
    log_info "  curl '${FUNCTION_URL}?city=London'"
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
}

# Run main function
main "$@"