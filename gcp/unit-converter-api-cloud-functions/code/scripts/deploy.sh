#!/bin/bash

#===============================================================================
# Unit Converter API Cloud Functions - Deployment Script
#===============================================================================
# This script deploys a serverless REST API using Google Cloud Functions
# for unit conversion operations with comprehensive error handling and logging.
#
# Features:
# - Temperature, distance, and weight conversions
# - HTTP trigger with GET/POST support
# - CORS enabled for web browser compatibility
# - Comprehensive error handling and validation
# - Production-ready configuration
#===============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit if any command in a pipeline fails

#===============================================================================
# Configuration and Constants
#===============================================================================

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly FUNCTION_SOURCE_DIR="${PROJECT_DIR}/function-source"

# Default configuration
readonly DEFAULT_REGION="us-central1"
readonly DEFAULT_FUNCTION_NAME="unit-converter-api"
readonly DEFAULT_MEMORY="256MB"
readonly DEFAULT_TIMEOUT="60s"
readonly DEFAULT_RUNTIME="python312"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#===============================================================================
# Utility Functions
#===============================================================================

# Print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Print usage information
print_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Deploy a Unit Converter API using Google Cloud Functions

OPTIONS:
    -p, --project PROJECT_ID     Google Cloud Project ID (required)
    -r, --region REGION          Deployment region (default: $DEFAULT_REGION)
    -n, --name FUNCTION_NAME     Function name (default: $DEFAULT_FUNCTION_NAME)
    -m, --memory MEMORY          Memory allocation (default: $DEFAULT_MEMORY)
    -t, --timeout TIMEOUT        Function timeout (default: $DEFAULT_TIMEOUT)
    --runtime RUNTIME            Python runtime version (default: $DEFAULT_RUNTIME)
    --dry-run                    Show what would be deployed without executing
    -h, --help                   Display this help message

EXAMPLES:
    $SCRIPT_NAME --project my-gcp-project
    $SCRIPT_NAME --project my-project --region us-west1 --name my-converter-api
    $SCRIPT_NAME --project my-project --dry-run

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT         Default project ID if not specified
    GOOGLE_CLOUD_REGION          Default region if not specified

EOF
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate Google Cloud CLI authentication and project access
validate_gcloud_setup() {
    print_info "Validating Google Cloud CLI setup..."
    
    if ! command_exists gcloud; then
        print_error "Google Cloud CLI (gcloud) is not installed"
        print_error "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        print_error "Not authenticated with Google Cloud CLI"
        print_error "Please run: gcloud auth login"
        exit 1
    fi
    
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    print_success "Authenticated as: $active_account"
    
    # Validate project access
    if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        print_error "Cannot access project '$PROJECT_ID'"
        print_error "Please ensure the project exists and you have appropriate permissions"
        exit 1
    fi
    
    print_success "Project '$PROJECT_ID' is accessible"
}

# Enable required Google Cloud APIs
enable_required_apis() {
    print_info "Enabling required Google Cloud APIs..."
    
    local required_apis=(
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "artifactregistry.googleapis.com"
    )
    
    for api in "${required_apis[@]}"; do
        print_info "Enabling $api..."
        if ! gcloud services enable "$api" --project="$PROJECT_ID"; then
            print_error "Failed to enable API: $api"
            exit 1
        fi
    done
    
    print_success "All required APIs enabled"
    
    # Wait for APIs to be fully enabled
    print_info "Waiting for APIs to be fully enabled..."
    sleep 10
}

# Create the Cloud Function source code
create_function_source() {
    print_info "Creating Cloud Function source code..."
    
    # Create source directory
    mkdir -p "$FUNCTION_SOURCE_DIR"
    
    # Create main.py with the unit converter function
    cat > "$FUNCTION_SOURCE_DIR/main.py" << 'EOF'
import functions_framework
import json

# Unit conversion formulas
CONVERSIONS = {
    'temperature': {
        'celsius_to_fahrenheit': lambda c: (c * 9/5) + 32,
        'fahrenheit_to_celsius': lambda f: (f - 32) * 5/9,
        'celsius_to_kelvin': lambda c: c + 273.15,
        'kelvin_to_celsius': lambda k: k - 273.15,
        'fahrenheit_to_kelvin': lambda f: (f - 32) * 5/9 + 273.15,
        'kelvin_to_fahrenheit': lambda k: (k - 273.15) * 9/5 + 32
    },
    'distance': {
        'meters_to_feet': lambda m: m * 3.28084,
        'feet_to_meters': lambda f: f / 3.28084,
        'kilometers_to_miles': lambda km: km * 0.621371,
        'miles_to_kilometers': lambda mi: mi / 0.621371,
        'inches_to_centimeters': lambda i: i * 2.54,
        'centimeters_to_inches': lambda cm: cm / 2.54
    },
    'weight': {
        'kilograms_to_pounds': lambda kg: kg * 2.20462,
        'pounds_to_kilograms': lambda lb: lb / 2.20462,
        'grams_to_ounces': lambda g: g * 0.035274,
        'ounces_to_grams': lambda oz: oz / 0.035274,
        'tons_to_pounds': lambda t: t * 2000,
        'pounds_to_tons': lambda lb: lb / 2000
    }
}

@functions_framework.http
def convert_units(request):
    """HTTP Cloud Function for unit conversion.
    Args:
        request (flask.Request): The request object.
    Returns:
        The response text, or any set of values that can be turned into a
        Response object using `make_response`.
    """
    
    # Set CORS headers for web browser compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight requests
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Parse request data
        if request.method == 'GET':
            # Handle GET requests with query parameters
            category = request.args.get('category', '').lower()
            conversion_type = request.args.get('type', '').lower()
            value = float(request.args.get('value', 0))
        elif request.method == 'POST':
            # Handle POST requests with JSON body
            request_json = request.get_json(silent=True)
            if not request_json:
                return (json.dumps({'error': 'Invalid JSON in request body'}), 400, headers)
            
            category = request_json.get('category', '').lower()
            conversion_type = request_json.get('type', '').lower()
            value = float(request_json.get('value', 0))
        else:
            return (json.dumps({'error': 'Method not allowed'}), 405, headers)
        
        # Validate input parameters
        if not category or not conversion_type:
            return (json.dumps({
                'error': 'Missing required parameters: category and type',
                'available_categories': list(CONVERSIONS.keys()),
                'example': {
                    'category': 'temperature',
                    'type': 'celsius_to_fahrenheit',
                    'value': 25
                }
            }), 400, headers)
        
        # Check if category exists
        if category not in CONVERSIONS:
            return (json.dumps({
                'error': f'Unknown category: {category}',
                'available_categories': list(CONVERSIONS.keys())
            }), 400, headers)
        
        # Check if conversion type exists
        if conversion_type not in CONVERSIONS[category]:
            return (json.dumps({
                'error': f'Unknown conversion type: {conversion_type}',
                'available_types': list(CONVERSIONS[category].keys())
            }), 400, headers)
        
        # Perform conversion
        conversion_func = CONVERSIONS[category][conversion_type]
        result = conversion_func(value)
        
        # Return successful response
        response_data = {
            'input': {
                'category': category,
                'type': conversion_type,
                'value': value
            },
            'result': round(result, 6),
            'success': True
        }
        
        return (json.dumps(response_data), 200, headers)
        
    except ValueError as e:
        return (json.dumps({'error': f'Invalid value: {str(e)}'}), 400, headers)
    except Exception as e:
        return (json.dumps({'error': f'Internal server error: {str(e)}'}), 500, headers)
EOF
    
    # Create requirements.txt
    cat > "$FUNCTION_SOURCE_DIR/requirements.txt" << 'EOF'
functions-framework==3.*
EOF
    
    print_success "Cloud Function source code created in: $FUNCTION_SOURCE_DIR"
}

# Deploy the Cloud Function
deploy_function() {
    print_info "Deploying Cloud Function: $FUNCTION_NAME"
    print_info "Region: $REGION"
    print_info "Runtime: $RUNTIME"
    print_info "Memory: $MEMORY"
    print_info "Timeout: $TIMEOUT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Would deploy function with the following configuration:"
        echo "  Function Name: $FUNCTION_NAME"
        echo "  Region: $REGION"
        echo "  Runtime: $RUNTIME"
        echo "  Memory: $MEMORY"
        echo "  Timeout: $TIMEOUT"
        echo "  Source: $FUNCTION_SOURCE_DIR"
        return 0
    fi
    
    # Change to source directory for deployment
    cd "$FUNCTION_SOURCE_DIR"
    
    # Deploy the function
    if ! gcloud functions deploy "$FUNCTION_NAME" \
        --runtime "$RUNTIME" \
        --trigger-http \
        --entry-point convert_units \
        --source . \
        --allow-unauthenticated \
        --memory "$MEMORY" \
        --timeout "$TIMEOUT" \
        --region "$REGION" \
        --project "$PROJECT_ID"; then
        print_error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    print_success "Cloud Function deployed successfully"
}

# Get and display the function URL
get_function_url() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would retrieve function URL"
        return 0
    fi
    
    print_info "Retrieving function URL..."
    
    local function_url
    if ! function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(httpsTrigger.url)"); then
        print_error "Failed to retrieve function URL"
        exit 1
    fi
    
    print_success "Function URL: $function_url"
    
    # Store URL in a file for easy access
    echo "$function_url" > "$PROJECT_DIR/function-url.txt"
    print_info "Function URL saved to: $PROJECT_DIR/function-url.txt"
}

# Test the deployed function
test_function() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would test the deployed function"
        return 0
    fi
    
    if [[ ! -f "$PROJECT_DIR/function-url.txt" ]]; then
        print_warning "Function URL not found, skipping tests"
        return 0
    fi
    
    local function_url
    function_url=$(cat "$PROJECT_DIR/function-url.txt")
    
    print_info "Testing deployed function..."
    
    # Test temperature conversion (GET request)
    print_info "Testing temperature conversion (GET)..."
    if curl -f -s -X GET "${function_url}?category=temperature&type=celsius_to_fahrenheit&value=25" \
        -H "Content-Type: application/json" > /dev/null; then
        print_success "Temperature conversion (GET) test passed"
    else
        print_warning "Temperature conversion (GET) test failed"
    fi
    
    # Test weight conversion (POST request)
    print_info "Testing weight conversion (POST)..."
    if curl -f -s -X POST "$function_url" \
        -H "Content-Type: application/json" \
        -d '{"category": "weight", "type": "kilograms_to_pounds", "value": 70}' > /dev/null; then
        print_success "Weight conversion (POST) test passed"
    else
        print_warning "Weight conversion (POST) test failed"
    fi
    
    print_success "Basic function tests completed"
}

# Display deployment summary
display_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Deployment summary would be displayed here"
        return 0
    fi
    
    print_success "======================================"
    print_success "DEPLOYMENT COMPLETED SUCCESSFULLY"
    print_success "======================================"
    echo
    print_info "Function Details:"
    echo "  Name: $FUNCTION_NAME"
    echo "  Region: $REGION"
    echo "  Runtime: $RUNTIME"
    echo "  Memory: $MEMORY"
    echo "  Timeout: $TIMEOUT"
    echo "  Project: $PROJECT_ID"
    echo
    
    if [[ -f "$PROJECT_DIR/function-url.txt" ]]; then
        local function_url
        function_url=$(cat "$PROJECT_DIR/function-url.txt")
        print_info "Function URL: $function_url"
        echo
        print_info "Example Usage:"
        echo "  # GET request"
        echo "  curl \"${function_url}?category=temperature&type=celsius_to_fahrenheit&value=25\""
        echo
        echo "  # POST request"
        echo "  curl -X POST \"$function_url\" \\"
        echo "    -H \"Content-Type: application/json\" \\"
        echo "    -d '{\"category\": \"distance\", \"type\": \"meters_to_feet\", \"value\": 100}'"
        echo
        print_info "Available conversions:"
        echo "  Temperature: celsius_to_fahrenheit, fahrenheit_to_celsius, celsius_to_kelvin, etc."
        echo "  Distance: meters_to_feet, kilometers_to_miles, inches_to_centimeters, etc."
        echo "  Weight: kilograms_to_pounds, grams_to_ounces, tons_to_pounds, etc."
    fi
    
    echo
    print_info "To clean up resources, run: ./destroy.sh --project $PROJECT_ID"
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
    # Initialize variables
    PROJECT_ID=""
    REGION="$DEFAULT_REGION"
    FUNCTION_NAME="$DEFAULT_FUNCTION_NAME"
    MEMORY="$DEFAULT_MEMORY"
    TIMEOUT="$DEFAULT_TIMEOUT"
    RUNTIME="$DEFAULT_RUNTIME"
    DRY_RUN="false"
    
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
            -n|--name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            -m|--memory)
                MEMORY="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --runtime)
                RUNTIME="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Use environment variables as fallbacks
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-}"
    fi
    
    if [[ -z "$PROJECT_ID" ]]; then
        print_error "Project ID is required"
        print_error "Use --project flag or set GOOGLE_CLOUD_PROJECT environment variable"
        print_usage
        exit 1
    fi
    
    # Update region from environment if not set
    if [[ "$REGION" == "$DEFAULT_REGION" && -n "${GOOGLE_CLOUD_REGION:-}" ]]; then
        REGION="$GOOGLE_CLOUD_REGION"
    fi
    
    print_info "Starting Unit Converter API deployment..."
    print_info "Project: $PROJECT_ID"
    print_info "Region: $REGION"
    print_info "Function: $FUNCTION_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN MODE - No resources will be created"
    fi
    
    # Set gcloud configuration
    if [[ "$DRY_RUN" != "true" ]]; then
        gcloud config set project "$PROJECT_ID"
        gcloud config set compute/region "$REGION"
        gcloud config set functions/region "$REGION"
    fi
    
    # Execute deployment steps
    validate_gcloud_setup
    enable_required_apis
    create_function_source
    deploy_function
    get_function_url
    test_function
    display_summary
    
    print_success "Deployment completed successfully!"
}

# Handle script interruption
trap 'print_error "Script interrupted"; exit 130' INT TERM

# Run main function with all arguments
main "$@"