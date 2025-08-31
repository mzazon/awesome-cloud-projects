#!/bin/bash

# Weather API with Cloud Functions and Firestore - Deployment Script
# This script deploys the complete infrastructure for a serverless weather API
# using Google Cloud Functions and Firestore with intelligent caching

set -euo pipefail

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

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate gcloud authentication
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found"
        log_info "Please run: gcloud auth login"
        return 1
    fi
    return 0
}

# Function to check if billing is enabled for the project
check_billing_enabled() {
    local project_id="$1"
    
    log_info "Checking if billing is enabled for project ${project_id}..."
    
    # Get billing account ID
    local billing_account
    billing_account=$(gcloud billing projects describe "${project_id}" \
        --format="value(billingAccountName)" 2>/dev/null || echo "")
    
    if [[ -z "${billing_account}" ]]; then
        log_error "No billing account is linked to project ${project_id}"
        log_info "Please link a billing account to continue"
        return 1
    fi
    
    log_success "Billing is enabled for project ${project_id}"
    return 0
}

# Function to wait for operation completion
wait_for_operation() {
    local operation_name="$1"
    local max_attempts=30
    local attempt=1
    
    log_info "Waiting for operation ${operation_name} to complete..."
    
    while [[ $attempt -le $max_attempts ]]; do
        local status
        status=$(gcloud operations describe "${operation_name}" \
            --format="value(done)" 2>/dev/null || echo "false")
        
        if [[ "${status}" == "True" ]]; then
            log_success "Operation ${operation_name} completed successfully"
            return 0
        fi
        
        log_info "Attempt ${attempt}/${max_attempts}: Operation still in progress..."
        sleep 10
        ((attempt++))
    done
    
    log_error "Operation ${operation_name} timed out after ${max_attempts} attempts"
    return 1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Please install it from: https://cloud.google.com/sdk/docs/install"
        return 1
    fi
    
    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "")
    log_info "Google Cloud CLI version: ${gcloud_version}"
    
    # Check authentication
    if ! check_gcloud_auth; then
        return 1
    fi
    
    # Check if jq is available for JSON processing
    if ! command_exists jq; then
        log_warning "jq is not installed. Some output formatting may be limited"
        log_info "Install jq for better JSON processing: apt-get install jq (Ubuntu) or brew install jq (macOS)"
    fi
    
    # Check if curl is available
    if ! command_exists curl; then
        log_error "curl is required but not installed"
        return 1
    fi
    
    # Check if openssl is available for random generation
    if ! command_exists openssl; then
        log_error "openssl is required but not installed"
        return 1
    fi
    
    log_success "All prerequisites met"
    return 0
}

# Function to prompt for Weather API key
get_weather_api_key() {
    local weather_api_key="$1"
    
    if [[ -z "${weather_api_key}" ]]; then
        log_warning "WEATHER_API_KEY environment variable not set"
        log_info "You can get a free API key from: https://openweathermap.org/api"
        
        echo -n "Please enter your OpenWeatherMap API key: "
        read -r weather_api_key
        
        if [[ -z "${weather_api_key}" ]]; then
            log_error "Weather API key is required"
            return 1
        fi
    fi
    
    # Validate API key format (basic check)
    if [[ ${#weather_api_key} -lt 32 ]]; then
        log_warning "API key seems too short. Please verify it's correct"
    fi
    
    echo "${weather_api_key}"
    return 0
}

# Function to create and configure project
setup_project() {
    local project_id="$1"
    local region="$2"
    
    log_info "Setting up project ${project_id}..."
    
    # Check if project exists
    if gcloud projects describe "${project_id}" >/dev/null 2>&1; then
        log_info "Project ${project_id} already exists"
    else
        log_info "Creating project ${project_id}..."
        if ! gcloud projects create "${project_id}"; then
            log_error "Failed to create project ${project_id}"
            return 1
        fi
        log_success "Project ${project_id} created successfully"
    fi
    
    # Set project and region configuration
    gcloud config set project "${project_id}"
    gcloud config set compute/region "${region}"
    
    # Check billing
    if ! check_billing_enabled "${project_id}"; then
        return 1
    fi
    
    return 0
}

# Function to enable required APIs
enable_apis() {
    local project_id="$1"
    
    log_info "Enabling required APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com" 
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --project="${project_id}"; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            return 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    return 0
}

# Function to initialize Firestore
initialize_firestore() {
    local project_id="$1"
    local region="$2"
    
    log_info "Initializing Firestore database..."
    
    # Check if Firestore is already initialized
    if gcloud firestore databases describe --database="(default)" --project="${project_id}" >/dev/null 2>&1; then
        log_info "Firestore database already exists"
        return 0
    fi
    
    # Create Firestore database in Native mode
    log_info "Creating Firestore database in Native mode..."
    if gcloud firestore databases create --region="${region}" --project="${project_id}"; then
        log_success "Firestore database created successfully"
    else
        log_error "Failed to create Firestore database"
        return 1
    fi
    
    return 0
}

# Function to create function source code
create_function_source() {
    local source_dir="$1"
    local weather_api_key="$2"
    
    log_info "Creating Cloud Function source code..."
    
    # Create source directory
    mkdir -p "${source_dir}"
    
    # Create requirements.txt
    cat > "${source_dir}/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-firestore==2.*
requests==2.*
EOF
    
    # Create main.py with the weather API function
    cat > "${source_dir}/main.py" << 'EOF'
import os
import json
import requests
from datetime import datetime, timedelta
from google.cloud import firestore
import functions_framework

# Initialize Firestore client
db = firestore.Client()

@functions_framework.http
def weather_api(request):
    """HTTP Cloud Function to fetch and cache weather data."""
    
    # Handle CORS for web applications
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for the main request
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        city = request.args.get('city', 'London')
        weather_api_key = os.environ.get('WEATHER_API_KEY')
        
        if not weather_api_key:
            return json.dumps({'error': 'Weather API key not configured'}), 500, headers
        
        # Check cache first (data valid for 10 minutes)
        doc_ref = db.collection('weather_cache').document(city.lower())
        doc = doc_ref.get()
        
        if doc.exists:
            data = doc.to_dict()
            cache_time = data.get('timestamp')
            
            # Use cached data if less than 10 minutes old
            if cache_time and datetime.now() - cache_time < timedelta(minutes=10):
                return json.dumps(data['weather_data']), 200, headers
        
        # Fetch fresh data from OpenWeatherMap API
        weather_url = f"https://api.openweathermap.org/data/2.5/weather?q={city}&appid={weather_api_key}&units=metric"
        response = requests.get(weather_url, timeout=10)
        
        if response.status_code != 200:
            return json.dumps({'error': 'Failed to fetch weather data'}), 500, headers
        
        weather_data = response.json()
        
        # Cache the data in Firestore
        cache_data = {
            'weather_data': weather_data,
            'timestamp': datetime.now(),
            'city': city.lower()
        }
        doc_ref.set(cache_data)
        
        return json.dumps(weather_data), 200, headers
        
    except Exception as e:
        return json.dumps({'error': str(e)}), 500, headers
EOF
    
    log_success "Function source code created in ${source_dir}"
    return 0
}

# Function to deploy Cloud Function
deploy_function() {
    local function_name="$1"
    local source_dir="$2"
    local region="$3"
    local weather_api_key="$4"
    local project_id="$5"
    
    log_info "Deploying Cloud Function ${function_name}..."
    
    # Deploy the function with environment variables
    if gcloud functions deploy "${function_name}" \
        --gen2 \
        --runtime python311 \
        --region "${region}" \
        --source "${source_dir}" \
        --entry-point weather_api \
        --trigger-http \
        --allow-unauthenticated \
        --memory 256Mi \
        --timeout 60s \
        --set-env-vars "WEATHER_API_KEY=${weather_api_key}" \
        --project="${project_id}"; then
        
        log_success "Cloud Function ${function_name} deployed successfully"
        return 0
    else
        log_error "Failed to deploy Cloud Function ${function_name}"
        return 1
    fi
}

# Function to get function URL
get_function_url() {
    local function_name="$1"
    local region="$2"
    local project_id="$3"
    
    log_info "Retrieving function URL..."
    
    local function_url
    function_url=$(gcloud functions describe "${function_name}" \
        --region "${region}" \
        --project="${project_id}" \
        --format "value(serviceConfig.uri)" 2>/dev/null || echo "")
    
    if [[ -n "${function_url}" ]]; then
        log_success "Function URL: ${function_url}"
        echo "${function_url}"
        return 0
    else
        log_error "Failed to retrieve function URL"
        return 1
    fi
}

# Function to test the deployed function
test_function() {
    local function_url="$1"
    
    log_info "Testing the deployed function..."
    
    # Test with London weather
    log_info "Testing with London weather data..."
    local response
    if response=$(curl -s -w "\n%{http_code}" "${function_url}?city=London" 2>/dev/null); then
        local http_code
        http_code=$(echo "${response}" | tail -n1)
        local body
        body=$(echo "${response}" | head -n -1)
        
        if [[ "${http_code}" == "200" ]]; then
            log_success "Function test successful"
            
            # Extract city name from response if jq is available
            if command_exists jq; then
                local city_name
                city_name=$(echo "${body}" | jq -r '.name' 2>/dev/null || echo "Unknown")
                log_info "Weather data retrieved for: ${city_name}"
            fi
            
            return 0
        else
            log_error "Function test failed with HTTP code: ${http_code}"
            log_error "Response: ${body}"
            return 1
        fi
    else
        log_error "Failed to test function - curl request failed"
        return 1
    fi
}

# Function to display deployment summary
display_summary() {
    local project_id="$1"
    local region="$2"
    local function_name="$3"
    local function_url="$4"
    
    echo
    log_success "=== DEPLOYMENT SUMMARY ==="
    echo -e "${GREEN}Project ID:${NC} ${project_id}"
    echo -e "${GREEN}Region:${NC} ${region}"
    echo -e "${GREEN}Function Name:${NC} ${function_name}"
    echo -e "${GREEN}Function URL:${NC} ${function_url}"
    echo
    log_info "=== USAGE EXAMPLES ==="
    echo "Test with London weather:"
    echo "  curl \"${function_url}?city=London\""
    echo
    echo "Test with Paris weather:"
    echo "  curl \"${function_url}?city=Paris\""
    echo
    echo "Test with Tokyo weather:"
    echo "  curl \"${function_url}?city=Tokyo\""
    echo
    log_info "=== MONITORING ==="
    echo "View function logs:"
    echo "  gcloud functions logs read ${function_name} --region=${region}"
    echo
    echo "View function metrics in Cloud Console:"
    echo "  https://console.cloud.google.com/functions/details/${region}/${function_name}?project=${project_id}"
    echo
    log_info "=== CLEANUP ==="
    echo "To remove all resources:"
    echo "  ./destroy.sh"
    echo
}

# Main deployment function
main() {
    log_info "Starting Weather API deployment..."
    
    # Set default values
    local project_id="${PROJECT_ID:-weather-api-$(date +%s)}"
    local region="${REGION:-us-central1}"
    local function_name="${FUNCTION_NAME:-weather-api}"
    local weather_api_key="${WEATHER_API_KEY:-}"
    
    # Override with command line arguments if provided
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                project_id="$2"
                shift 2
                ;;
            --region)
                region="$2"
                shift 2
                ;;
            --function-name)
                function_name="$2"
                shift 2
                ;;
            --weather-api-key)
                weather_api_key="$2"
                shift 2
                ;;
            --dry-run)
                log_info "Dry run mode - would deploy with the following configuration:"
                echo "  Project ID: ${project_id}"
                echo "  Region: ${region}"
                echo "  Function Name: ${function_name}"
                echo "  Weather API Key: ${weather_api_key:+***provided***}"
                exit 0
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --project-id PROJECT_ID       GCP project ID (default: weather-api-TIMESTAMP)"
                echo "  --region REGION               GCP region (default: us-central1)"
                echo "  --function-name NAME          Function name (default: weather-api)"
                echo "  --weather-api-key KEY         OpenWeatherMap API key"
                echo "  --dry-run                     Show configuration without deploying"
                echo "  -h, --help                    Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Check prerequisites
    if ! check_prerequisites; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    
    # Get weather API key
    if ! weather_api_key=$(get_weather_api_key "${weather_api_key}"); then
        exit 1
    fi
    
    # Create temporary directory for function source
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf ${temp_dir}" EXIT
    
    local source_dir="${temp_dir}/weather-function"
    
    # Execute deployment steps
    {
        setup_project "${project_id}" "${region}" &&
        enable_apis "${project_id}" &&
        initialize_firestore "${project_id}" "${region}" &&
        create_function_source "${source_dir}" "${weather_api_key}" &&
        deploy_function "${function_name}" "${source_dir}" "${region}" "${weather_api_key}" "${project_id}"
    } || {
        log_error "Deployment failed"
        exit 1
    }
    
    # Get function URL
    local function_url
    if ! function_url=$(get_function_url "${function_name}" "${region}" "${project_id}"); then
        log_error "Failed to get function URL"
        exit 1
    fi
    
    # Test the function
    if ! test_function "${function_url}"; then
        log_warning "Function deployment completed but testing failed"
        log_info "Please check the function manually"
    fi
    
    # Display summary
    display_summary "${project_id}" "${region}" "${function_name}" "${function_url}"
    
    log_success "Weather API deployment completed successfully!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi