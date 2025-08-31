#!/bin/bash

# Timezone Converter API with Cloud Functions - Deployment Script
# This script deploys a timezone conversion API using Google Cloud Functions

set -euo pipefail

# Colors for output
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

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_FUNCTION_NAME="timezone-converter"
DEFAULT_MEMORY="256MB"
DEFAULT_TIMEOUT="60s"

# Configuration variables (can be overridden by environment variables)
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-$DEFAULT_REGION}"
FUNCTION_NAME="${FUNCTION_NAME:-$DEFAULT_FUNCTION_NAME}"
MEMORY="${MEMORY:-$DEFAULT_MEMORY}"
TIMEOUT="${TIMEOUT:-$DEFAULT_TIMEOUT}"
CREATE_PROJECT="${CREATE_PROJECT:-false}"
SKIP_TESTS="${SKIP_TESTS:-false}"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy a timezone converter API using Google Cloud Functions.

OPTIONS:
    -p, --project-id PROJECT_ID     GCP Project ID (required if not set in env)
    -r, --region REGION            Deployment region (default: $DEFAULT_REGION)
    -f, --function-name NAME       Function name (default: $DEFAULT_FUNCTION_NAME)
    -m, --memory MEMORY            Memory allocation (default: $DEFAULT_MEMORY)
    -t, --timeout TIMEOUT          Function timeout (default: $DEFAULT_TIMEOUT)
    -c, --create-project           Create a new GCP project
    -s, --skip-tests               Skip function testing after deployment
    -h, --help                     Display this help message

ENVIRONMENT VARIABLES:
    PROJECT_ID                     GCP Project ID
    REGION                         Deployment region
    FUNCTION_NAME                  Cloud Function name
    MEMORY                         Memory allocation for function
    TIMEOUT                        Function timeout
    CREATE_PROJECT                 Set to 'true' to create new project
    SKIP_TESTS                     Set to 'true' to skip post-deployment tests

EXAMPLES:
    # Deploy with existing project
    $0 --project-id my-project-123

    # Deploy with custom configuration
    $0 --project-id my-project-123 --region europe-west1 --memory 512MB

    # Create new project and deploy
    $0 --create-project --project-id timezone-api-\$(date +%s)

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -f|--function-name)
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
            -c|--create-project)
                CREATE_PROJECT="true"
                shift
                ;;
            -s|--skip-tests)
                SKIP_TESTS="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
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
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        log_info "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi

    # Check required tools
    local required_tools=("curl" "python3" "pip3")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed."
            exit 1
        fi
    done

    # Validate PROJECT_ID
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID is required. Set it via environment variable or --project-id flag."
        exit 1
    fi

    # Validate PROJECT_ID format
    if [[ ! "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        log_error "Invalid PROJECT_ID format. Must be 6-30 characters, lowercase letters, digits, and hyphens only."
        exit 1
    fi

    log_success "Prerequisites check completed"
}

# Create or configure GCP project
setup_project() {
    log_info "Setting up GCP project: $PROJECT_ID"

    if [[ "$CREATE_PROJECT" == "true" ]]; then
        log_info "Creating new project: $PROJECT_ID"
        
        # Check if project already exists
        if gcloud projects describe "$PROJECT_ID" &> /dev/null; then
            log_warning "Project $PROJECT_ID already exists. Skipping creation."
        else
            if ! gcloud projects create "$PROJECT_ID" --name="Timezone Converter API"; then
                log_error "Failed to create project $PROJECT_ID"
                exit 1
            fi
            log_success "Project $PROJECT_ID created successfully"
        fi

        # Link billing account (if available)
        local billing_account
        billing_account=$(gcloud billing accounts list --filter="open:true" --format="value(name)" | head -n1)
        if [[ -n "$billing_account" ]]; then
            log_info "Linking billing account to project..."
            gcloud billing projects link "$PROJECT_ID" --billing-account="$billing_account" || {
                log_warning "Failed to link billing account. You may need to do this manually."
            }
        else
            log_warning "No active billing account found. Please link billing manually."
        fi
    fi

    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"

    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."

    local required_apis=(
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )

    for api in "${required_apis[@]}"; do
        log_info "Enabling $api..."
        if ! gcloud services enable "$api"; then
            log_error "Failed to enable $api"
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

    # Create temporary directory for function code
    local function_dir
    function_dir=$(mktemp -d)
    
    # Store directory path for cleanup
    echo "$function_dir" > /tmp/timezone_function_dir

    cd "$function_dir"

    # Create main.py
    cat > main.py << 'EOF'
import json
from datetime import datetime
from zoneinfo import ZoneInfo, available_timezones
import functions_framework

@functions_framework.http
def convert_timezone(request):
    """Convert time between timezones via HTTP request."""
    
    # Handle CORS for web browsers
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Get request parameters
        if request.method == 'POST':
            request_json = request.get_json(silent=True)
            if not request_json:
                return json.dumps({'error': 'Invalid JSON'}), 400, headers
            
            timestamp = request_json.get('timestamp')
            from_tz = request_json.get('from_timezone', 'UTC')
            to_tz = request_json.get('to_timezone', 'UTC')
        else:  # GET request
            timestamp = request.args.get('timestamp')
            from_tz = request.args.get('from_timezone', 'UTC')
            to_tz = request.args.get('to_timezone', 'UTC')
        
        # Validate timezone names
        available_zones = available_timezones()
        if from_tz not in available_zones:
            return json.dumps({'error': f'Invalid from_timezone: {from_tz}'}), 400, headers
        if to_tz not in available_zones:
            return json.dumps({'error': f'Invalid to_timezone: {to_tz}'}), 400, headers
        
        # Parse timestamp (support multiple formats)
        if timestamp:
            try:
                # Try ISO format first
                dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=ZoneInfo(from_tz))
            except ValueError:
                try:
                    # Try Unix timestamp
                    dt = datetime.fromtimestamp(float(timestamp), tz=ZoneInfo(from_tz))
                except (ValueError, OSError):
                    return json.dumps({'error': 'Invalid timestamp format'}), 400, headers
        else:
            # Use current time if no timestamp provided
            dt = datetime.now(tz=ZoneInfo(from_tz))
        
        # Convert timezone
        converted_dt = dt.astimezone(ZoneInfo(to_tz))
        
        # Prepare response
        response = {
            'original': {
                'timestamp': dt.isoformat(),
                'timezone': from_tz,
                'timezone_name': dt.tzname()
            },
            'converted': {
                'timestamp': converted_dt.isoformat(),
                'timezone': to_tz,
                'timezone_name': converted_dt.tzname()
            },
            'offset_hours': (converted_dt.utcoffset() - dt.utcoffset()).total_seconds() / 3600
        }
        
        return json.dumps(response, indent=2), 200, headers
        
    except Exception as e:
        return json.dumps({'error': str(e)}), 500, headers
EOF

    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.*
EOF

    log_success "Function source code created in $function_dir"
}

# Deploy Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function: $FUNCTION_NAME"
    
    # Get current directory from temp file
    local function_dir
    function_dir=$(cat /tmp/timezone_function_dir)
    cd "$function_dir"

    # Deploy function with retries
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        log_info "Deployment attempt $((retry_count + 1))/$max_retries"
        
        if gcloud functions deploy "$FUNCTION_NAME" \
            --gen2 \
            --runtime python312 \
            --trigger-http \
            --entry-point convert_timezone \
            --source . \
            --region "$REGION" \
            --memory "$MEMORY" \
            --timeout "$TIMEOUT" \
            --allow-unauthenticated \
            --quiet; then
            
            log_success "Function deployed successfully"
            break
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                log_warning "Deployment failed. Retrying in 30 seconds..."
                sleep 30
            else
                log_error "Function deployment failed after $max_retries attempts"
                exit 1
            fi
        fi
    done

    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --gen2 \
        --region "$REGION" \
        --format="value(serviceConfig.uri)")
    
    if [[ -z "$function_url" ]]; then
        log_error "Failed to retrieve function URL"
        exit 1
    fi

    # Store function URL for testing
    echo "$function_url" > /tmp/timezone_function_url
    
    log_success "Function URL: $function_url"
}

# Test deployed function
test_function() {
    if [[ "$SKIP_TESTS" == "true" ]]; then
        log_info "Skipping function tests as requested"
        return 0
    fi

    log_info "Testing deployed function..."
    
    local function_url
    function_url=$(cat /tmp/timezone_function_url)
    
    # Test 1: Basic GET request
    log_info "Test 1: Basic GET request"
    local test1_response
    test1_response=$(curl -s -w "%{http_code}" \
        "${function_url}?timestamp=2024-06-15T14:30:00&from_timezone=America/Los_Angeles&to_timezone=Asia/Tokyo")
    
    local test1_http_code="${test1_response: -3}"
    local test1_body="${test1_response%???}"
    
    if [[ "$test1_http_code" == "200" ]]; then
        log_success "Test 1 passed: GET request successful"
    else
        log_error "Test 1 failed: Expected HTTP 200, got $test1_http_code"
        log_error "Response: $test1_body"
        return 1
    fi

    # Test 2: POST request with JSON
    log_info "Test 2: POST request with JSON payload"
    local test2_response
    test2_response=$(curl -s -w "%{http_code}" -X POST "$function_url" \
        -H "Content-Type: application/json" \
        -d '{"timestamp": "2024-12-25T12:00:00", "from_timezone": "UTC", "to_timezone": "Australia/Sydney"}')
    
    local test2_http_code="${test2_response: -3}"
    local test2_body="${test2_response%???}"
    
    if [[ "$test2_http_code" == "200" ]]; then
        log_success "Test 2 passed: POST request successful"
    else
        log_error "Test 2 failed: Expected HTTP 200, got $test2_http_code"
        log_error "Response: $test2_body"
        return 1
    fi

    # Test 3: Current time conversion
    log_info "Test 3: Current time conversion"
    local test3_response
    test3_response=$(curl -s -w "%{http_code}" \
        "${function_url}?from_timezone=UTC&to_timezone=America/New_York")
    
    local test3_http_code="${test3_response: -3}"
    local test3_body="${test3_response%???}"
    
    if [[ "$test3_http_code" == "200" ]]; then
        log_success "Test 3 passed: Current time conversion successful"
    else
        log_error "Test 3 failed: Expected HTTP 200, got $test3_http_code"
        log_error "Response: $test3_body"
        return 1
    fi

    # Test 4: Error handling
    log_info "Test 4: Error handling with invalid timezone"
    local test4_response
    test4_response=$(curl -s -w "%{http_code}" \
        "${function_url}?from_timezone=Invalid/Zone&to_timezone=UTC")
    
    local test4_http_code="${test4_response: -3}"
    local test4_body="${test4_response%???}"
    
    if [[ "$test4_http_code" == "400" ]]; then
        log_success "Test 4 passed: Error handling working correctly"
    else
        log_warning "Test 4 unexpected result: Expected HTTP 400, got $test4_http_code"
    fi

    log_success "All function tests completed successfully"
}

# Cleanup temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove temporary function directory
    if [[ -f /tmp/timezone_function_dir ]]; then
        local function_dir
        function_dir=$(cat /tmp/timezone_function_dir)
        if [[ -d "$function_dir" ]]; then
            rm -rf "$function_dir"
        fi
        rm -f /tmp/timezone_function_dir
    fi
    
    # Remove temporary URL file
    rm -f /tmp/timezone_function_url
    
    log_success "Temporary files cleaned up"
}

# Display deployment summary
display_summary() {
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --gen2 \
        --region "$REGION" \
        --format="value(serviceConfig.uri)" 2>/dev/null || echo "Error retrieving URL")

    cat << EOF

${GREEN}================================${NC}
${GREEN}  DEPLOYMENT SUMMARY${NC}
${GREEN}================================${NC}

${BLUE}Project ID:${NC}     $PROJECT_ID
${BLUE}Region:${NC}        $REGION
${BLUE}Function Name:${NC} $FUNCTION_NAME
${BLUE}Memory:${NC}        $MEMORY
${BLUE}Timeout:${NC}       $TIMEOUT
${BLUE}Function URL:${NC}  $function_url

${GREEN}Example Usage:${NC}

# GET request with query parameters
curl "${function_url}?timestamp=2024-06-15T14:30:00&from_timezone=America/Los_Angeles&to_timezone=Asia/Tokyo"

# POST request with JSON payload
curl -X POST "$function_url" \\
  -H "Content-Type: application/json" \\
  -d '{"timestamp": "2024-12-25T12:00:00", "from_timezone": "UTC", "to_timezone": "Australia/Sydney"}'

# Current time conversion
curl "${function_url}?from_timezone=UTC&to_timezone=America/New_York"

${GREEN}Management Commands:${NC}

# View function logs
gcloud functions logs read $FUNCTION_NAME --gen2 --region $REGION

# View function details
gcloud functions describe $FUNCTION_NAME --gen2 --region $REGION

# Delete function (use destroy.sh script)
./destroy.sh --project-id $PROJECT_ID --function-name $FUNCTION_NAME

${GREEN}================================${NC}

EOF
}

# Main deployment function
main() {
    log_info "Starting Timezone Converter API deployment..."
    
    # Parse command line arguments
    parse_args "$@"
    
    # Setup trap for cleanup
    trap cleanup_temp_files EXIT
    
    # Execute deployment steps
    check_prerequisites
    setup_project
    enable_apis
    create_function_code
    deploy_function
    test_function
    
    # Display summary
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function with all arguments
main "$@"