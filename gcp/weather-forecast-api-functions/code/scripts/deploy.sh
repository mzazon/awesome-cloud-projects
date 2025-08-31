#!/bin/bash

#######################################################################
# Weather Forecast API with Cloud Functions - Deployment Script
# 
# This script deploys a serverless weather forecast API using Google 
# Cloud Functions that fetches current weather data from OpenWeatherMap
# and returns formatted JSON responses.
#
# Prerequisites:
# - Google Cloud account with billing enabled
# - gcloud CLI installed and configured
# - OpenWeatherMap API key (optional, uses demo key by default)
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh [PROJECT_ID] [OPENWEATHER_API_KEY]
#
# Examples:
#   ./deploy.sh                                    # Use generated project ID and demo API key
#   ./deploy.sh my-weather-project                 # Use custom project ID and demo API key
#   ./deploy.sh my-weather-project abc123def456    # Use custom project ID and API key
#######################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code $exit_code"
    log_info "You may need to manually clean up any partially created resources"
    exit $exit_code
}

trap cleanup_on_error ERR

# Configuration variables
readonly DEFAULT_REGION="us-central1"
readonly FUNCTION_NAME="weather-forecast"
readonly OPENWEATHER_DEFAULT_KEY="demo_key"
readonly TEMP_DIR="weather-function-deployment"

# Parse command line arguments
PROJECT_ID=${1:-"weather-api-$(date +%s)"}
OPENWEATHER_API_KEY=${2:-$OPENWEATHER_DEFAULT_KEY}
REGION=${REGION:-$DEFAULT_REGION}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "gcloud is not authenticated. Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if curl is available for testing
    if ! command -v curl &> /dev/null; then
        log_warning "curl is not available. API testing will be skipped."
    fi
    
    # Check if OpenSSL is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_warning "openssl is not available. Using basic random generation."
    fi
    
    log_success "Prerequisites check completed"
}

# Create or verify GCP project
setup_project() {
    log_info "Setting up GCP project: $PROJECT_ID"
    
    # Check if project already exists
    if gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_info "Project $PROJECT_ID already exists, using existing project"
    else
        log_info "Creating new project: $PROJECT_ID"
        
        # Create new project
        if ! gcloud projects create "$PROJECT_ID" --name="Weather API Project"; then
            log_error "Failed to create project $PROJECT_ID. It may already exist or you may lack permissions."
            exit 1
        fi
        
        log_success "Project $PROJECT_ID created successfully"
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set functions/region "$REGION"
    
    log_success "Project configuration updated"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "artifactregistry.googleapis.com"
        "cloudbuild.googleapis.com" 
        "run.googleapis.com"
        "logging.googleapis.com"
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

# Create function source code
create_function_code() {
    log_info "Creating function source code..."
    
    # Clean up any existing temp directory
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
requests==2.31.0
functions-framework==3.4.0
EOF
    
    # Create main.py with weather API logic
    cat > main.py << 'EOF'
import json
import os
import requests
from flask import Request
import functions_framework

@functions_framework.http
def weather_forecast(request: Request):
    """HTTP Cloud Function for weather forecasts."""
    
    # Enable CORS for web browsers
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for actual request
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Get city parameter from query string
        city = request.args.get('city', 'London')
        
        # OpenWeatherMap API configuration
        api_key = os.environ.get('OPENWEATHER_API_KEY', 'demo_key')
        base_url = "http://api.openweathermap.org/data/2.5/weather"
        
        # Make API request
        params = {
            'q': city,
            'appid': api_key,
            'units': 'metric'
        }
        
        response = requests.get(base_url, params=params, timeout=10)
        
        if response.status_code == 200:
            data = response.json()
            
            # Format response
            forecast = {
                'city': data['name'],
                'country': data['sys']['country'],
                'temperature': data['main']['temp'],
                'feels_like': data['main']['feels_like'],
                'humidity': data['main']['humidity'],
                'description': data['weather'][0]['description'],
                'wind_speed': data['wind']['speed'],
                'timestamp': data['dt']
            }
            
            return (json.dumps(forecast), 200, headers)
        
        elif response.status_code == 401:
            return (json.dumps({'error': 'Invalid API key'}), 401, headers)
        
        elif response.status_code == 404:
            return (json.dumps({'error': 'City not found'}), 404, headers)
        
        else:
            return (json.dumps({'error': 'Weather service unavailable'}), 503, headers)
            
    except requests.RequestException as e:
        return (json.dumps({'error': 'Network error occurred'}), 500, headers)
    
    except Exception as e:
        return (json.dumps({'error': 'Internal server error'}), 500, headers)
EOF
    
    log_success "Function source code created in $TEMP_DIR"
}

# Deploy the Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function..."
    
    # Deploy function as Cloud Run service (Gen 2)
    if gcloud run deploy "$FUNCTION_NAME" \
        --source . \
        --function weather_forecast \
        --region "$REGION" \
        --allow-unauthenticated \
        --memory 512Mi \
        --timeout 60s \
        --set-env-vars "OPENWEATHER_API_KEY=$OPENWEATHER_API_KEY" \
        --quiet; then
        
        log_success "Function deployed successfully"
    else
        log_error "Function deployment failed"
        exit 1
    fi
    
    # Get function URL
    local function_url
    function_url=$(gcloud run services describe "$FUNCTION_NAME" \
        --region "$REGION" \
        --format="value(status.url)")
    
    if [[ -n "$function_url" ]]; then
        echo "FUNCTION_URL=$function_url" > ../function_url.env
        log_success "Function URL: $function_url"
        log_info "Function URL saved to function_url.env"
    else
        log_error "Failed to retrieve function URL"
        exit 1
    fi
}

# Test the deployed function
test_function() {
    log_info "Testing deployed function..."
    
    # Source the function URL
    source ../function_url.env
    
    if command -v curl &> /dev/null; then
        log_info "Testing with default city (London)..."
        local response
        response=$(curl -s "$FUNCTION_URL" || echo "curl_failed")
        
        if [[ "$response" != "curl_failed" ]]; then
            echo "Response: $response"
            
            # Test with a specific city
            log_info "Testing with specific city (Tokyo)..."
            response=$(curl -s "$FUNCTION_URL?city=Tokyo" || echo "curl_failed")
            echo "Response: $response"
            
            log_success "Function testing completed"
        else
            log_warning "Function testing failed - network issues or function not responding"
        fi
    else
        log_warning "curl not available, skipping function testing"
        log_info "You can manually test the function at: $FUNCTION_URL"
    fi
}

# Display deployment summary
show_deployment_summary() {
    log_info "=== Deployment Summary ==="
    echo
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Function Name: $FUNCTION_NAME"
    echo "OpenWeather API Key: ${OPENWEATHER_API_KEY:0:8}..." # Show only first 8 chars
    
    if [[ -f "../function_url.env" ]]; then
        source ../function_url.env
        echo "Function URL: $FUNCTION_URL"
        echo
        echo "Test the API:"
        echo "  curl \"$FUNCTION_URL\""
        echo "  curl \"$FUNCTION_URL?city=Paris\""
    fi
    
    echo
    echo "View function logs:"
    echo "  gcloud logging read \"resource.type=cloud_run_revision AND resource.labels.service_name=$FUNCTION_NAME\" --limit=10"
    
    echo
    echo "Monitor function metrics:"
    echo "  https://console.cloud.google.com/run/detail/$REGION/$FUNCTION_NAME/metrics?project=$PROJECT_ID"
    
    echo
    log_success "Weather Forecast API deployment completed successfully!"
    
    if [[ "$OPENWEATHER_API_KEY" == "$OPENWEATHER_DEFAULT_KEY" ]]; then
        log_warning "Using demo API key. For production use, get a free API key from: https://openweathermap.org/api"
        log_info "To update with a real API key, run:"
        echo "  gcloud run deploy $FUNCTION_NAME --source . --function weather_forecast --region $REGION --allow-unauthenticated --memory 512Mi --timeout 60s --set-env-vars OPENWEATHER_API_KEY=your-real-api-key"
    fi
}

# Cleanup function for temp directory
cleanup_temp_dir() {
    cd ..
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_info "Cleaned up temporary directory"
    fi
}

# Main deployment flow
main() {
    log_info "Starting Weather Forecast API deployment..."
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "OpenWeather API Key: ${OPENWEATHER_API_KEY:0:8}..."
    echo
    
    check_prerequisites
    setup_project
    enable_apis
    create_function_code
    deploy_function
    test_function
    cleanup_temp_dir
    show_deployment_summary
}

# Run main function
main "$@"