#!/bin/bash

# Password Generator Cloud Function - Deployment Script
# This script deploys a serverless password generator using Google Cloud Functions
# Created for recipe: Simple Password Generator with Cloud Functions

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check gcloud authentication
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        log_error "No active gcloud authentication found"
        log_info "Please run 'gcloud auth login' to authenticate"
        return 1
    fi
    return 0
}

# Function to check if billing is enabled for project
check_billing_enabled() {
    local project_id=$1
    local billing_account
    
    billing_account=$(gcloud beta billing projects describe "$project_id" \
        --format="value(billingAccountName)" 2>/dev/null || echo "")
    
    if [[ -z "$billing_account" ]]; then
        log_warning "Billing is not enabled for project $project_id"
        log_info "Please enable billing at: https://console.cloud.google.com/billing/linkedaccount?project=$project_id"
        return 1
    fi
    return 0
}

# Function to check if APIs are enabled
check_apis_enabled() {
    local project_id=$1
    local required_apis=("cloudfunctions.googleapis.com" "cloudbuild.googleapis.com" "run.googleapis.com")
    local disabled_apis=()
    
    for api in "${required_apis[@]}"; do
        if ! gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
            disabled_apis+=("$api")
        fi
    done
    
    if [[ ${#disabled_apis[@]} -gt 0 ]]; then
        log_info "The following APIs need to be enabled: ${disabled_apis[*]}"
        return 1
    fi
    return 0
}

# Function to enable required APIs
enable_apis() {
    local project_id=$1
    local required_apis=("cloudfunctions.googleapis.com" "cloudbuild.googleapis.com" "run.googleapis.com")
    
    log_info "Enabling required APIs..."
    for api in "${required_apis[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --project="$project_id"; then
            log_success "$api enabled"
        else
            log_error "Failed to enable $api"
            return 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    return 0
}

# Function to create function source code
create_function_source() {
    local source_dir=$1
    
    log_info "Creating function source code..."
    
    # Create source directory
    mkdir -p "$source_dir"
    
    # Create main.py
    cat > "$source_dir/main.py" << 'EOF'
import json
import secrets
import string
from flask import Request
import functions_framework

@functions_framework.http
def generate_password(request: Request):
    """HTTP Cloud Function that generates secure passwords.
    
    Args:
        request (flask.Request): The request object with optional parameters:
            - length: Password length (default: 12, min: 4, max: 128)
            - include_symbols: Include special characters (default: true)
            - include_numbers: Include numbers (default: true)
            - include_uppercase: Include uppercase letters (default: true)
            - include_lowercase: Include lowercase letters (default: true)
    
    Returns:
        JSON response with generated password and metadata
    """
    
    # Set CORS headers for web browser compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Parse request parameters
        request_json = request.get_json(silent=True)
        request_args = request.args
        
        # Get parameters from JSON body or query parameters
        if request_json:
            length = request_json.get('length', 12)
            include_symbols = request_json.get('include_symbols', True)
            include_numbers = request_json.get('include_numbers', True)
            include_uppercase = request_json.get('include_uppercase', True)
            include_lowercase = request_json.get('include_lowercase', True)
        else:
            length = int(request_args.get('length', 12))
            include_symbols = request_args.get('include_symbols', 'true').lower() == 'true'
            include_numbers = request_args.get('include_numbers', 'true').lower() == 'true'
            include_uppercase = request_args.get('include_uppercase', 'true').lower() == 'true'
            include_lowercase = request_args.get('include_lowercase', 'true').lower() == 'true'
        
        # Validate length parameter
        if length < 4 or length > 128:
            return (json.dumps({
                'error': 'Password length must be between 4 and 128 characters',
                'provided_length': length
            }), 400, headers)
        
        # Build character set based on requirements
        charset = ''
        if include_lowercase:
            charset += string.ascii_lowercase
        if include_uppercase:
            charset += string.ascii_uppercase
        if include_numbers:
            charset += string.digits
        if include_symbols:
            charset += '!@#$%^&*()_+-=[]{}|;:,.<>?'
        
        # Ensure at least one character type is selected
        if not charset:
            return (json.dumps({
                'error': 'At least one character type must be enabled'
            }), 400, headers)
        
        # Generate cryptographically secure password
        password = ''.join(secrets.choice(charset) for _ in range(length))
        
        # Calculate entropy bits using correct formula: log2(N^L) = L * log2(N)
        import math
        entropy_bits = length * math.log2(len(charset))
        
        # Prepare response with password and metadata
        response_data = {
            'password': password,
            'length': length,
            'character_types': {
                'lowercase': include_lowercase,
                'uppercase': include_uppercase,
                'numbers': include_numbers,
                'symbols': include_symbols
            },
            'entropy_bits': round(entropy_bits, 2),
            'charset_size': len(charset)
        }
        
        return (json.dumps(response_data), 200, headers)
        
    except ValueError as e:
        return (json.dumps({
            'error': f'Invalid parameter value: {str(e)}'
        }), 400, headers)
    except Exception as e:
        return (json.dumps({
            'error': f'Internal server error: {str(e)}'
        }), 500, headers)
EOF
    
    # Create requirements.txt
    cat > "$source_dir/requirements.txt" << 'EOF'
functions-framework==3.*
flask==2.*
EOF
    
    log_success "Function source code created in $source_dir"
}

# Function to deploy Cloud Function
deploy_function() {
    local project_id=$1
    local region=$2
    local function_name=$3
    local source_dir=$4
    
    log_info "Deploying Cloud Function '$function_name'..."
    
    # Change to source directory for deployment
    cd "$source_dir"
    
    # Deploy the function
    if gcloud functions deploy "$function_name" \
        --gen2 \
        --runtime=python311 \
        --region="$region" \
        --source=. \
        --entry-point=generate_password \
        --trigger-http \
        --allow-unauthenticated \
        --memory=256Mi \
        --timeout=60s \
        --max-instances=10 \
        --project="$project_id"; then
        
        log_success "Cloud Function '$function_name' deployed successfully"
        return 0
    else
        log_error "Failed to deploy Cloud Function '$function_name'"
        return 1
    fi
}

# Function to get function URL
get_function_url() {
    local project_id=$1
    local region=$2
    local function_name=$3
    
    local function_url
    function_url=$(gcloud functions describe "$function_name" \
        --gen2 \
        --region="$region" \
        --project="$project_id" \
        --format="value(serviceConfig.uri)" 2>/dev/null)
    
    if [[ -n "$function_url" ]]; then
        echo "$function_url"
        return 0
    else
        return 1
    fi
}

# Function to test the deployed function
test_function() {
    local function_url=$1
    
    log_info "Testing deployed function..."
    
    # Test basic functionality
    if command_exists curl; then
        log_info "Testing basic password generation..."
        if curl -s -f -X GET "${function_url}?length=12" > /dev/null; then
            log_success "Function is responding to requests"
        else
            log_warning "Function test failed - but this might be due to cold start delay"
            log_info "You can manually test the function at: $function_url"
        fi
    else
        log_warning "curl not found - skipping automatic function test"
        log_info "You can manually test the function at: $function_url"
    fi
}

# Main deployment function
main() {
    log_info "Starting Password Generator Cloud Function deployment..."
    
    # Set default values
    local project_id="${PROJECT_ID:-}"
    local region="${REGION:-us-central1}"
    local function_name="${FUNCTION_NAME:-password-generator}"
    local source_dir="${SOURCE_DIR:-./cloud-function-source}"
    local create_project="${CREATE_PROJECT:-false}"
    
    # Parse command line arguments
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
            --source-dir)
                source_dir="$2"
                shift 2
                ;;
            --create-project)
                create_project="true"
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --project-id PROJECT_ID    GCP Project ID (required)"
                echo "  --region REGION           GCP Region (default: us-central1)"
                echo "  --function-name NAME      Function name (default: password-generator)"
                echo "  --source-dir DIR          Source directory (default: ./cloud-function-source)"
                echo "  --create-project          Create a new project"
                echo "  --help                    Show this help message"
                echo ""
                echo "Environment variables:"
                echo "  PROJECT_ID                GCP Project ID"
                echo "  REGION                    GCP Region"
                echo "  FUNCTION_NAME             Function name"
                echo "  SOURCE_DIR                Source directory"
                echo "  CREATE_PROJECT            Create new project (true/false)"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Generate project ID if creating new project
    if [[ "$create_project" == "true" && -z "$project_id" ]]; then
        project_id="password-gen-$(date +%s)"
        log_info "Generated project ID: $project_id"
    fi
    
    # Validate required parameters
    if [[ -z "$project_id" ]]; then
        log_error "Project ID is required. Use --project-id or set PROJECT_ID environment variable"
        exit 1
    fi
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    if ! check_gcloud_auth; then
        exit 1
    fi
    
    log_success "Prerequisites check passed"
    
    # Create project if requested
    if [[ "$create_project" == "true" ]]; then
        log_info "Creating new project: $project_id"
        if gcloud projects create "$project_id" --name="Password Generator Demo"; then
            log_success "Project created: $project_id"
        else
            log_error "Failed to create project: $project_id"
            exit 1
        fi
    fi
    
    # Set project configuration
    log_info "Setting project configuration..."
    gcloud config set project "$project_id"
    gcloud config set compute/region "$region"
    gcloud config set functions/region "$region"
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$project_id" > /dev/null 2>&1; then
        log_error "Project '$project_id' does not exist or is not accessible"
        exit 1
    fi
    
    # Check billing (only for new projects or if explicitly requested)
    if [[ "$create_project" == "true" ]]; then
        log_info "Checking billing status..."
        if ! check_billing_enabled "$project_id"; then
            log_warning "Billing is not enabled. Some operations may fail."
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
    
    # Check and enable APIs
    log_info "Checking required APIs..."
    if ! check_apis_enabled "$project_id"; then
        if ! enable_apis "$project_id"; then
            exit 1
        fi
    else
        log_success "All required APIs are enabled"
    fi
    
    # Create function source code
    if ! create_function_source "$source_dir"; then
        exit 1
    fi
    
    # Deploy the function
    if ! deploy_function "$project_id" "$region" "$function_name" "$source_dir"; then
        exit 1
    fi
    
    # Get function URL
    log_info "Retrieving function URL..."
    local function_url
    function_url=$(get_function_url "$project_id" "$region" "$function_name")
    
    if [[ -n "$function_url" ]]; then
        log_success "Function URL: $function_url"
        
        # Test the function
        test_function "$function_url"
        
        # Save deployment info
        cat > deployment-info.txt << EOF
Password Generator Cloud Function Deployment Information
======================================================

Project ID: $project_id
Region: $region
Function Name: $function_name
Function URL: $function_url
Deployment Time: $(date)

Test the function:
curl -X GET "${function_url}?length=16"

Or with JSON:
curl -X POST "$function_url" \\
    -H "Content-Type: application/json" \\
    -d '{"length": 14, "include_symbols": false}'
EOF
        
        log_success "Deployment information saved to deployment-info.txt"
        
    else
        log_error "Failed to retrieve function URL"
        exit 1
    fi
    
    # Return to original directory
    cd - > /dev/null
    
    log_success "Password Generator Cloud Function deployment completed successfully!"
    log_info "Function URL: $function_url"
    log_info "You can now test the function using the URL above"
}

# Handle script interruption
trap 'log_error "Deployment interrupted"; exit 1' INT TERM

# Run main function with all arguments
main "$@"