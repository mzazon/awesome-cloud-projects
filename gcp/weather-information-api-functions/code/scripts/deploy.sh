#!/bin/bash
#
# Weather Information API with Cloud Functions - Deployment Script
# 
# This script deploys a serverless HTTP API using Google Cloud Functions
# that fetches current weather information for any city.
#
# Usage: ./deploy.sh [OPTIONS]
# Options:
#   --project-id <id>    Override default project ID
#   --region <region>    Override default region (default: us-central1)
#   --function-name <name> Override default function name (default: weather-api)
#   --weather-api-key <key> Set OpenWeatherMap API key
#   --dry-run           Show what would be deployed without executing
#   --help              Show this help message
#

set -e
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_FUNCTION_NAME="weather-api"
DRY_RUN=false
WEATHER_API_KEY=""

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

# Help function
show_help() {
    cat << EOF
Weather Information API with Cloud Functions - Deployment Script

This script deploys a serverless HTTP API using Google Cloud Functions
that fetches current weather information for any city.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --project-id <id>        Override default project ID
    --region <region>        Override default region (default: us-central1)
    --function-name <name>   Override default function name (default: weather-api)
    --weather-api-key <key>  Set OpenWeatherMap API key for real weather data
    --dry-run               Show what would be deployed without executing
    --help                  Show this help message

EXAMPLES:
    # Deploy with default settings
    $0

    # Deploy with custom project and region
    $0 --project-id my-weather-project --region us-east1

    # Deploy with real weather API key
    $0 --weather-api-key your-openweathermap-api-key

    # Dry run to see what would be deployed
    $0 --dry-run

PREREQUISITES:
    - Google Cloud CLI (gcloud) installed and configured
    - Google Cloud account with billing enabled
    - Cloud Functions API access
    - OpenWeatherMap API key (optional, demo data used otherwise)

For more information, visit: https://cloud.google.com/functions/docs
EOF
}

# Parse command line arguments
parse_args() {
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
            --function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            --weather-api-key)
                WEATHER_API_KEY="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_error "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 > /dev/null; then
        log_error "No active Google Cloud authentication found"
        log_error "Please run: gcloud auth login"
        exit 1
    fi

    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_warning "OpenSSL not found. Using date for random suffix generation."
        RANDOM_SUFFIX=$(date +%s | tail -c 7)
    else
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi

    log_success "Prerequisites check completed"
}

# Set default values and environment variables
setup_environment() {
    log_info "Setting up environment variables..."

    # Set defaults if not provided
    REGION=${REGION:-$DEFAULT_REGION}
    FUNCTION_NAME=${FUNCTION_NAME:-$DEFAULT_FUNCTION_NAME}
    
    # Generate unique project ID if not provided
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID="weather-api-$(date +%s)"
        log_info "Generated project ID: $PROJECT_ID"
    fi

    # Export environment variables
    export PROJECT_ID
    export REGION
    export FUNCTION_NAME

    log_success "Environment configured - Project: $PROJECT_ID, Region: $REGION"
}

# Configure gcloud
configure_gcloud() {
    log_info "Configuring Google Cloud CLI..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would set project to: $PROJECT_ID"
        log_info "[DRY RUN] Would set functions region to: $REGION"
        return 0
    fi

    # Set default project and region
    gcloud config set project "$PROJECT_ID" || {
        log_error "Failed to set project. Please ensure the project exists and you have access."
        exit 1
    }
    
    gcloud config set functions/region "$REGION" || {
        log_error "Failed to set functions region"
        exit 1
    }

    log_success "Google Cloud CLI configured"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: cloudfunctions.googleapis.com, cloudbuild.googleapis.com, run.googleapis.com"
        return 0
    fi

    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
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

    log_success "All required APIs enabled"
}

# Create function source code
create_function_code() {
    log_info "Creating Cloud Function source code..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create function directory and source files"
        return 0
    fi

    # Create project directory
    local work_dir="weather-function-${RANDOM_SUFFIX}"
    mkdir -p "$work_dir"
    cd "$work_dir"

    # Create main.py
    cat > main.py << 'EOF'
import functions_framework
import requests
import json
import os
from flask import jsonify

@functions_framework.http
def get_weather(request):
    """HTTP Cloud Function to get weather information for a city.
    
    Args:
        request (flask.Request): The request object containing city parameter
        
    Returns:
        flask.Response: JSON response with weather data or error message
    """
    
    # Set CORS headers for cross-origin requests
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Get city parameter from request
        city = request.args.get('city', '').strip()
        
        if not city:
            return jsonify({
                'error': 'City parameter is required',
                'example': '?city=London'
            }), 400, headers
        
        # Use demo API key for testing (replace with your own)
        api_key = os.environ.get('WEATHER_API_KEY', 'demo_key_please_replace')
        
        if api_key == 'demo_key_please_replace':
            # Return mock data for demo purposes
            return jsonify({
                'city': city,
                'temperature': 22,
                'description': 'Demo weather data',
                'humidity': 65,
                'wind_speed': 5.2,
                'note': 'This is demo data. Set WEATHER_API_KEY environment variable for real data.'
            }), 200, headers
        
        # Make request to OpenWeatherMap API
        weather_url = f"https://api.openweathermap.org/data/2.5/weather"
        params = {
            'q': city,
            'appid': api_key,
            'units': 'metric'
        }
        
        response = requests.get(weather_url, params=params, timeout=10)
        
        if response.status_code == 404:
            return jsonify({
                'error': f'City "{city}" not found',
                'suggestion': 'Please check the spelling or try a different city name'
            }), 404, headers
        
        if response.status_code != 200:
            return jsonify({
                'error': 'Weather service temporarily unavailable',
                'status_code': response.status_code
            }), 502, headers
        
        weather_data = response.json()
        
        # Extract and format relevant weather information
        formatted_response = {
            'city': weather_data['name'],
            'country': weather_data['sys']['country'],
            'temperature': round(weather_data['main']['temp'], 1),
            'feels_like': round(weather_data['main']['feels_like'], 1),
            'description': weather_data['weather'][0]['description'].title(),
            'humidity': weather_data['main']['humidity'],
            'wind_speed': weather_data.get('wind', {}).get('speed', 0),
            'timestamp': weather_data['dt']
        }
        
        return jsonify(formatted_response), 200, headers
        
    except requests.exceptions.Timeout:
        return jsonify({
            'error': 'Weather service request timed out',
            'retry': 'Please try again in a few moments'
        }), 504, headers
        
    except requests.exceptions.RequestException as e:
        return jsonify({
            'error': 'Failed to fetch weather data',
            'details': str(e)
        }), 502, headers
        
    except Exception as e:
        return jsonify({
            'error': 'Internal server error',
            'message': 'An unexpected error occurred'
        }), 500, headers
EOF

    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.*
requests==2.32.3
flask==3.0.3
EOF

    log_success "Function source code created in directory: $work_dir"
}

# Deploy Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function: $FUNCTION_NAME..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy function with the following configuration:"
        log_info "  Name: $FUNCTION_NAME"
        log_info "  Runtime: python312"
        log_info "  Trigger: HTTP"
        log_info "  Memory: 256MB"
        log_info "  Timeout: 60s"
        log_info "  Region: $REGION"
        log_info "  Authentication: Allow unauthenticated"
        if [[ -n "$WEATHER_API_KEY" ]]; then
            log_info "  Environment variable: WEATHER_API_KEY=***"
        fi
        return 0
    fi

    # Build deployment command
    local deploy_cmd=(
        gcloud functions deploy "$FUNCTION_NAME"
        --runtime python312
        --trigger-http
        --allow-unauthenticated
        --source .
        --entry-point get_weather
        --memory 256MB
        --timeout 60s
        --region "$REGION"
        --quiet
    )

    # Add environment variables if weather API key is provided
    if [[ -n "$WEATHER_API_KEY" ]]; then
        deploy_cmd+=(--update-env-vars "WEATHER_API_KEY=$WEATHER_API_KEY")
        log_info "Including weather API key in deployment"
    fi

    # Execute deployment
    log_info "Executing deployment... (this may take 2-3 minutes)"
    if "${deploy_cmd[@]}"; then
        log_success "Function deployed successfully"
    else
        log_error "Function deployment failed"
        exit 1
    fi

    # Get function URL
    log_info "Retrieving function URL..."
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region "$REGION" \
        --format "value(httpsTrigger.url)" 2>/dev/null)
    
    if [[ -n "$function_url" ]]; then
        log_success "Function URL: $function_url"
        echo
        echo "🌐 Test your weather API:"
        echo "   curl \"${function_url}?city=London\""
        echo
    else
        log_warning "Could not retrieve function URL"
    fi
}

# Test function deployment
test_function() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would test function deployment"
        return 0
    fi

    log_info "Testing function deployment..."

    # Get function URL for testing
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region "$REGION" \
        --format "value(httpsTrigger.url)" 2>/dev/null)

    if [[ -z "$function_url" ]]; then
        log_warning "Cannot test function - URL not available"
        return 0
    fi

    # Test basic functionality
    if command -v curl &> /dev/null; then
        log_info "Testing function with sample request..."
        local test_response
        test_response=$(curl -s -w "\n%{http_code}" "${function_url}?city=London" 2>/dev/null | tail -1)
        
        if [[ "$test_response" == "200" ]]; then
            log_success "Function test successful - API is responding"
        else
            log_warning "Function test returned HTTP status: $test_response"
        fi
    else
        log_info "curl not available - skipping function test"
    fi
}

# Main deployment function
main() {
    echo "========================================"
    echo "Weather Information API Deployment"
    echo "========================================"
    echo

    parse_args "$@"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY RUN mode - no resources will be created"
        echo
    fi

    check_prerequisites
    setup_environment
    configure_gcloud
    enable_apis
    create_function_code
    deploy_function
    test_function

    echo
    echo "========================================"
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN COMPLETED"
        echo "No resources were created. Run without --dry-run to deploy."
    else
        log_success "DEPLOYMENT COMPLETED SUCCESSFULLY"
        echo
        echo "📋 Deployment Summary:"
        echo "   Project ID: $PROJECT_ID"
        echo "   Function: $FUNCTION_NAME"
        echo "   Region: $REGION"
        if [[ -n "$WEATHER_API_KEY" ]]; then
            echo "   Weather API: Configured with real API key"
        else
            echo "   Weather API: Using demo data (set --weather-api-key for real data)"
        fi
        echo
        echo "💡 Next Steps:"
        echo "   1. Test your API with different cities"
        echo "   2. Monitor usage in Cloud Console"
        echo "   3. Consider setting up a real OpenWeatherMap API key"
        echo "   4. Review Cloud Functions logs for debugging"
        echo
        echo "🧹 To clean up resources, run: ./destroy.sh"
    fi
    echo "========================================"
}

# Run main function with all arguments
main "$@"