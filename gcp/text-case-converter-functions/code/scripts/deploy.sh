#!/bin/bash

# deploy.sh - Deployment script for Text Case Converter Cloud Function
# This script deploys a serverless text case conversion API using Google Cloud Functions

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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

# Configuration variables with defaults
PROJECT_ID="${PROJECT_ID:-text-converter-$(date +%s)}"
REGION="${REGION:-us-central1}"
FUNCTION_NAME="${FUNCTION_NAME:-text-case-converter}"
RUNTIME="${RUNTIME:-python311}"
MEMORY="${MEMORY:-128MB}"
TIMEOUT="${TIMEOUT:-60s}"
DRY_RUN="${DRY_RUN:-false}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        log_error "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "No active gcloud authentication found."
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if Python is available for local testing
    if ! command -v python3 &> /dev/null; then
        log_warning "Python3 not found. Local testing will be limited."
    fi
    
    # Check if curl is available for testing
    if ! command -v curl &> /dev/null; then
        log_warning "curl not found. API testing will be limited."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to create or set project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project exists
    if gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_info "Project $PROJECT_ID already exists"
    else
        log_info "Creating new project: $PROJECT_ID"
        if [ "$DRY_RUN" = "false" ]; then
            gcloud projects create "$PROJECT_ID" \
                --name="Text Case Converter API" \
                --quiet
        else
            log_info "[DRY RUN] Would create project: $PROJECT_ID"
        fi
    fi
    
    # Set the project
    if [ "$DRY_RUN" = "false" ]; then
        gcloud config set project "$PROJECT_ID"
        gcloud config set compute/region "$REGION"
    else
        log_info "[DRY RUN] Would set project to: $PROJECT_ID"
    fi
    
    log_success "Project setup completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if [ "$DRY_RUN" = "false" ]; then
            gcloud services enable "$api" --quiet
        else
            log_info "[DRY RUN] Would enable API: $api"
        fi
    done
    
    # Wait for APIs to be fully enabled
    if [ "$DRY_RUN" = "false" ]; then
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    log_success "APIs enabled successfully"
}

# Function to create function source code
create_source_code() {
    log_info "Creating Cloud Function source code..."
    
    # Create temporary directory for function source
    local temp_dir="/tmp/${FUNCTION_NAME}-source"
    
    if [ -d "$temp_dir" ]; then
        rm -rf "$temp_dir"
    fi
    
    mkdir -p "$temp_dir"
    
    # Create main.py
    cat > "$temp_dir/main.py" << 'EOF'
import functions_framework
import json
import re

@functions_framework.http
def text_case_converter(request):
    """HTTP Cloud Function for text case conversion.
    
    Accepts POST requests with JSON payload containing:
    - text: string to convert
    - case_type: target case format
    
    Returns JSON response with converted text.
    """
    
    # Set CORS headers for cross-origin requests
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Content-Type': 'application/json'
    }
    
    # Handle preflight OPTIONS requests
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    # Only accept POST requests
    if request.method != 'POST':
        return (json.dumps({'error': 'Method not allowed'}), 405, headers)
    
    try:
        # Parse JSON request body
        request_json = request.get_json(silent=True)
        
        if not request_json:
            return (json.dumps({'error': 'Invalid JSON'}), 400, headers)
        
        text = request_json.get('text', '')
        case_type = request_json.get('case_type', '').lower()
        
        if not text:
            return (json.dumps({'error': 'Text field is required'}), 400, headers)
        
        if not case_type:
            return (json.dumps({'error': 'case_type field is required'}), 400, headers)
        
        # Perform case conversion
        converted_text = convert_case(text, case_type)
        
        if converted_text is None:
            return (json.dumps({'error': f'Unsupported case type: {case_type}'}), 400, headers)
        
        # Return successful response
        response = {
            'original': text,
            'case_type': case_type,
            'converted': converted_text
        }
        
        return (json.dumps(response), 200, headers)
        
    except Exception as e:
        # Log error and return generic error message
        print(f"Error processing request: {str(e)}")
        return (json.dumps({'error': 'Internal server error'}), 500, headers)

def convert_case(text, case_type):
    """Convert text to specified case format."""
    
    case_handlers = {
        'upper': lambda t: t.upper(),
        'uppercase': lambda t: t.upper(),
        'lower': lambda t: t.lower(),
        'lowercase': lambda t: t.lower(),
        'title': lambda t: t.title(),
        'titlecase': lambda t: t.title(),
        'capitalize': lambda t: t.capitalize(),
        'camel': lambda t: to_camel_case(t),
        'camelcase': lambda t: to_camel_case(t),
        'pascal': lambda t: to_pascal_case(t),
        'pascalcase': lambda t: to_pascal_case(t),
        'snake': lambda t: to_snake_case(t),
        'snakecase': lambda t: to_snake_case(t),
        'kebab': lambda t: to_kebab_case(t),
        'kebabcase': lambda t: to_kebab_case(t)
    }
    
    return case_handlers.get(case_type, lambda t: None)(text)

def to_camel_case(text):
    """Convert text to camelCase."""
    # Split on whitespace and non-alphanumeric characters
    words = re.split(r'[^a-zA-Z0-9]', text)
    # Filter empty strings and convert
    words = [word for word in words if word]
    if not words:
        return text
    
    result = words[0].lower()
    for word in words[1:]:
        result += word.capitalize()
    return result

def to_pascal_case(text):
    """Convert text to PascalCase."""
    words = re.split(r'[^a-zA-Z0-9]', text)
    words = [word for word in words if word]
    return ''.join(word.capitalize() for word in words)

def to_snake_case(text):
    """Convert text to snake_case."""
    # Handle camelCase and PascalCase
    s1 = re.sub('(.)([A-Z][a-z]+)', r'\1_\2', text)
    # Handle sequences of uppercase letters
    s2 = re.sub('([a-z0-9])([A-Z])', r'\1_\2', s1)
    # Replace whitespace and non-alphanumeric with underscores
    s3 = re.sub(r'[^a-zA-Z0-9]', '_', s2)
    # Remove duplicate underscores and convert to lowercase
    return re.sub(r'_+', '_', s3).strip('_').lower()

def to_kebab_case(text):
    """Convert text to kebab-case."""
    # Similar to snake_case but with hyphens
    s1 = re.sub('(.)([A-Z][a-z]+)', r'\1-\2', text)
    s2 = re.sub('([a-z0-9])([A-Z])', r'\1-\2', s1)
    s3 = re.sub(r'[^a-zA-Z0-9]', '-', s2)
    return re.sub(r'-+', '-', s3).strip('-').lower()
EOF
    
    # Create requirements.txt
    cat > "$temp_dir/requirements.txt" << 'EOF'
functions-framework>=3.0.0
EOF
    
    log_success "Source code created at $temp_dir"
    echo "$temp_dir"
}

# Function to deploy the Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function..."
    
    local source_dir="$1"
    
    if [ "$DRY_RUN" = "false" ]; then
        # Deploy the function
        gcloud functions deploy "$FUNCTION_NAME" \
            --runtime "$RUNTIME" \
            --trigger-http \
            --allow-unauthenticated \
            --source "$source_dir" \
            --entry-point text_case_converter \
            --memory "$MEMORY" \
            --timeout "$TIMEOUT" \
            --region "$REGION" \
            --quiet
        
        # Get the function URL
        local function_url
        function_url=$(gcloud functions describe "$FUNCTION_NAME" \
            --region="$REGION" \
            --format="value(httpsTrigger.url)")
        
        echo "FUNCTION_URL=$function_url" > /tmp/function_deployment_info.env
        
        log_success "Function deployed successfully"
        log_info "Function URL: $function_url"
        
    else
        log_info "[DRY RUN] Would deploy function with following configuration:"
        log_info "  Name: $FUNCTION_NAME"
        log_info "  Runtime: $RUNTIME"
        log_info "  Memory: $MEMORY"
        log_info "  Timeout: $TIMEOUT"
        log_info "  Region: $REGION"
        log_info "  Source: $source_dir"
    fi
}

# Function to test the deployed function
test_function() {
    log_info "Testing deployed function..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would test function with sample requests"
        return 0
    fi
    
    # Source the function URL
    if [ -f /tmp/function_deployment_info.env ]; then
        source /tmp/function_deployment_info.env
    else
        local function_url
        function_url=$(gcloud functions describe "$FUNCTION_NAME" \
            --region="$REGION" \
            --format="value(httpsTrigger.url)" 2>/dev/null || echo "")
        
        if [ -z "$function_url" ]; then
            log_error "Could not retrieve function URL for testing"
            return 1
        fi
        FUNCTION_URL="$function_url"
    fi
    
    log_info "Testing uppercase conversion..."
    local response
    response=$(curl -s -X POST "$FUNCTION_URL" \
        -H "Content-Type: application/json" \
        -d '{"text": "hello world", "case_type": "upper"}' || echo "")
    
    if echo "$response" | grep -q "HELLO WORLD"; then
        log_success "Uppercase conversion test passed"
    else
        log_warning "Uppercase conversion test may have failed"
        log_info "Response: $response"
    fi
    
    log_info "Testing camelCase conversion..."
    response=$(curl -s -X POST "$FUNCTION_URL" \
        -H "Content-Type: application/json" \
        -d '{"text": "hello world example", "case_type": "camel"}' || echo "")
    
    if echo "$response" | grep -q "helloWorldExample"; then
        log_success "CamelCase conversion test passed"
    else
        log_warning "CamelCase conversion test may have failed"
        log_info "Response: $response"
    fi
    
    log_info "Testing error handling..."
    response=$(curl -s -X POST "$FUNCTION_URL" \
        -H "Content-Type: application/json" \
        -d '{"case_type": "upper"}' || echo "")
    
    if echo "$response" | grep -q "Text field is required"; then
        log_success "Error handling test passed"
    else
        log_warning "Error handling test may have failed"
        log_info "Response: $response"
    fi
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "===================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Function Name: $FUNCTION_NAME"
    echo "Runtime: $RUNTIME"
    echo "Memory: $MEMORY"
    echo "Timeout: $TIMEOUT"
    
    if [ "$DRY_RUN" = "false" ] && [ -f /tmp/function_deployment_info.env ]; then
        source /tmp/function_deployment_info.env
        echo "Function URL: $FUNCTION_URL"
        echo ""
        echo "Test the function with:"
        echo "curl -X POST $FUNCTION_URL \\"
        echo "  -H \"Content-Type: application/json\" \\"
        echo "  -d '{\"text\": \"hello world\", \"case_type\": \"upper\"}'"
    fi
    echo "===================="
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    if [ -d "/tmp/${FUNCTION_NAME}-source" ]; then
        rm -rf "/tmp/${FUNCTION_NAME}-source"
    fi
    if [ -f "/tmp/function_deployment_info.env" ]; then
        rm -f "/tmp/function_deployment_info.env"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy a Text Case Converter Cloud Function to Google Cloud Platform"
    echo ""
    echo "Options:"
    echo "  --project-id PROJECT_ID    Set the GCP project ID (default: text-converter-TIMESTAMP)"
    echo "  --region REGION            Set the deployment region (default: us-central1)"
    echo "  --function-name NAME       Set the function name (default: text-case-converter)"
    echo "  --runtime RUNTIME          Set the runtime version (default: python311)"
    echo "  --memory MEMORY            Set memory allocation (default: 128MB)"  
    echo "  --timeout TIMEOUT          Set timeout (default: 60s)"
    echo "  --dry-run                  Show what would be deployed without making changes"
    echo "  --help                     Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID                 GCP project ID"
    echo "  REGION                     GCP region"
    echo "  FUNCTION_NAME              Cloud Function name"
    echo "  RUNTIME                    Python runtime version"
    echo "  MEMORY                     Memory allocation"
    echo "  TIMEOUT                    Function timeout"
    echo "  DRY_RUN                    Set to 'true' for dry run mode"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with defaults"
    echo "  $0 --project-id my-project           # Deploy to specific project"
    echo "  $0 --dry-run                         # Preview deployment"
    echo "  $0 --region europe-west1             # Deploy to different region"
}

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
        --function-name)
            FUNCTION_NAME="$2"
            shift 2
            ;;
        --runtime)
            RUNTIME="$2"
            shift 2
            ;;
        --memory)
            MEMORY="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --help)
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

# Main deployment flow
main() {
    log_info "Starting Text Case Converter Cloud Function deployment..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "Running in DRY RUN mode - no resources will be created"
    fi
    
    # Set trap to cleanup on exit
    trap cleanup_temp_files EXIT
    
    # Execute deployment steps
    check_prerequisites
    setup_project
    enable_apis
    
    local source_dir
    source_dir=$(create_source_code)
    
    deploy_function "$source_dir"
    
    if [ "$DRY_RUN" = "false" ]; then
        # Wait for function to be fully ready
        log_info "Waiting for function to be fully ready..."
        sleep 10
        test_function
    fi
    
    display_summary
    
    log_success "Deployment completed successfully!"
    
    if [ "$DRY_RUN" = "false" ]; then
        log_info "To clean up resources, run: ./destroy.sh --project-id $PROJECT_ID"
    fi
}

# Execute main function
main "$@"