#!/bin/bash

# Timestamp Converter API with Cloud Functions - Deployment Script
# This script deploys a serverless timestamp conversion API using Google Cloud Functions

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

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Command '$1' is required but not installed."
        return 1
    fi
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    local current_account
    current_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)
    if [[ -z "$current_account" ]]; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login'"
        return 1
    fi
    log_info "Authenticated as: $current_account"
}

# Function to check if billing is enabled
check_billing() {
    local project_id="$1"
    local billing_enabled
    billing_enabled=$(gcloud beta billing projects describe "$project_id" --format="value(billingEnabled)" 2>/dev/null || echo "false")
    if [[ "$billing_enabled" != "True" ]]; then
        log_warning "Billing may not be enabled for project $project_id. Some services may not work."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Deployment cancelled by user"
            exit 1
        fi
    fi
}

# Function to enable required APIs with retry logic
enable_apis() {
    local project_id="$1"
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
        "logging.googleapis.com"
        "storage.googleapis.com"
    )
    
    log_info "Enabling required APIs..."
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if ! gcloud services enable "$api" --project="$project_id"; then
            log_error "Failed to enable $api"
            return 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled (30 seconds)..."
    sleep 30
}

# Function to create project with retry logic
create_project() {
    local project_id="$1"
    local project_name="$2"
    
    log_info "Checking if project $project_id exists..."
    if gcloud projects describe "$project_id" &>/dev/null; then
        log_info "Project $project_id already exists, skipping creation"
        return 0
    fi
    
    log_info "Creating project: $project_id"
    if ! gcloud projects create "$project_id" --name="$project_name"; then
        log_error "Failed to create project $project_id"
        return 1
    fi
    
    log_success "Project $project_id created successfully"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    local bucket_name="$1"
    local region="$2"
    local project_id="$3"
    
    log_info "Creating Cloud Storage bucket: $bucket_name"
    
    # Check if bucket already exists
    if gsutil ls -b "gs://$bucket_name" &>/dev/null; then
        log_info "Bucket gs://$bucket_name already exists, skipping creation"
        return 0
    fi
    
    # Create bucket
    if ! gsutil mb -p "$project_id" -c STANDARD -l "$region" "gs://$bucket_name"; then
        log_error "Failed to create bucket gs://$bucket_name"
        return 1
    fi
    
    # Enable versioning
    if ! gsutil versioning set on "gs://$bucket_name"; then
        log_error "Failed to enable versioning on gs://$bucket_name"
        return 1
    fi
    
    log_success "Storage bucket gs://$bucket_name created with versioning enabled"
}

# Function to create function source code
create_function_code() {
    local function_dir="$1"
    
    log_info "Creating function source code in $function_dir"
    
    mkdir -p "$function_dir"
    cd "$function_dir"
    
    # Create main.py
    cat > main.py << 'EOF'
import functions_framework
from datetime import datetime
import pytz
import json
from flask import jsonify

@functions_framework.http
def timestamp_converter(request):
    """HTTP Cloud Function for timestamp conversion.
    
    Supports conversion between Unix timestamps and human-readable dates
    with timezone support and multiple output formats.
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
        if request.method == 'GET':
            timestamp = request.args.get('timestamp')
            timezone = request.args.get('timezone', 'UTC')
            format_type = request.args.get('format', 'iso')
        else:
            request_json = request.get_json(silent=True)
            timestamp = request_json.get('timestamp') if request_json else None
            timezone = request_json.get('timezone', 'UTC') if request_json else 'UTC'
            format_type = request_json.get('format', 'iso') if request_json else 'iso'
        
        if not timestamp:
            return jsonify({
                'error': 'Missing timestamp parameter',
                'usage': 'GET /?timestamp=1609459200&timezone=UTC&format=iso'
            }), 400, headers
        
        # Convert timestamp
        if timestamp == 'now':
            dt = datetime.now(pytz.UTC)
            unix_timestamp = int(dt.timestamp())
        else:
            try:
                unix_timestamp = int(timestamp)
                dt = datetime.fromtimestamp(unix_timestamp, pytz.UTC)
            except ValueError:
                return jsonify({
                    'error': 'Invalid timestamp format',
                    'expected': 'Unix timestamp (seconds since epoch) or "now"'
                }), 400, headers
        
        # Apply timezone conversion
        try:
            target_tz = pytz.timezone(timezone)
            dt_local = dt.astimezone(target_tz)
        except pytz.exceptions.UnknownTimeZoneError:
            return jsonify({
                'error': f'Invalid timezone: {timezone}',
                'suggestion': 'Use timezone names like UTC, US/Eastern, Europe/London'
            }), 400, headers
        
        # Format output
        formats = {
            'iso': dt_local.isoformat(),
            'rfc': dt_local.strftime('%a, %d %b %Y %H:%M:%S %z'),
            'human': dt_local.strftime('%Y-%m-%d %H:%M:%S %Z'),
            'date': dt_local.strftime('%Y-%m-%d'),
            'time': dt_local.strftime('%H:%M:%S %Z')
        }
        
        response = {
            'unix_timestamp': unix_timestamp,
            'timezone': timezone,
            'formatted': {
                'iso': formats['iso'],
                'rfc': formats['rfc'],
                'human': formats['human'],
                'date': formats['date'],
                'time': formats['time']
            },
            'requested_format': formats.get(format_type, formats['iso'])
        }
        
        return jsonify(response), 200, headers
        
    except Exception as e:
        return jsonify({
            'error': 'Internal server error',
            'message': str(e)
        }), 500, headers
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.*
pytz==2024.*
EOF
    
    log_success "Function source code created successfully"
}

# Function to deploy Cloud Function
deploy_function() {
    local function_name="$1"
    local region="$2"
    local function_dir="$3"
    
    log_info "Deploying Cloud Function: $function_name"
    
    cd "$function_dir"
    
    # Deploy function using Cloud Run (2nd generation)
    if ! gcloud run deploy "$function_name" \
        --source . \
        --function timestamp_converter \
        --base-image python312 \
        --region "$region" \
        --allow-unauthenticated \
        --memory 256Mi \
        --timeout 60s \
        --max-instances 10 \
        --set-env-vars "FUNCTION_TARGET=timestamp_converter"; then
        log_error "Failed to deploy Cloud Function"
        return 1
    fi
    
    # Get function URL
    local function_url
    function_url=$(gcloud run services describe "$function_name" \
        --region="$region" \
        --format="value(status.url)")
    
    log_success "Cloud Function deployed successfully"
    log_info "Function URL: $function_url"
    
    # Save URL to file for reference
    echo "$function_url" > "${function_dir}/../function_url.txt"
}

# Function to backup source code
backup_source_code() {
    local bucket_name="$1"
    local function_dir="$2"
    
    log_info "Backing up source code to Cloud Storage"
    
    cd "$function_dir"
    
    # Create source archive
    tar -czf function-source.tar.gz *.py *.txt
    
    # Upload to Cloud Storage
    if ! gsutil cp function-source.tar.gz "gs://$bucket_name/"; then
        log_error "Failed to backup source code"
        return 1
    fi
    
    # Clean up local archive
    rm -f function-source.tar.gz
    
    log_success "Source code backed up to gs://$bucket_name/"
}

# Function to test deployed function
test_function() {
    local function_url="$1"
    
    log_info "Testing deployed function..."
    
    # Test basic functionality
    log_info "Testing current timestamp conversion..."
    if curl -s -f "${function_url}/?timestamp=now&timezone=UTC&format=human" > /dev/null; then
        log_success "Basic timestamp conversion test passed"
    else
        log_warning "Basic timestamp conversion test failed"
    fi
    
    # Test specific timestamp
    log_info "Testing specific timestamp conversion..."
    if curl -s -f "${function_url}/?timestamp=1609459200&timezone=US/Eastern&format=iso" > /dev/null; then
        log_success "Specific timestamp conversion test passed"
    else
        log_warning "Specific timestamp conversion test failed"
    fi
    
    log_info "Function testing completed"
}

# Main deployment function
main() {
    log_info "Starting Timestamp Converter API deployment..."
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    check_command "gcloud" || exit 1
    check_command "gsutil" || exit 1
    check_command "curl" || exit 1
    check_command "openssl" || exit 1
    check_gcloud_auth || exit 1
    
    # Set default values or read from environment
    local project_id="${PROJECT_ID:-timestamp-converter-$(date +%s)}"
    local region="${REGION:-us-central1}"
    local function_name="${FUNCTION_NAME:-timestamp-converter}"
    local random_suffix="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
    local bucket_name="${BUCKET_NAME:-timestamp-converter-source-${random_suffix}}"
    local function_dir="${FUNCTION_DIR:-timestamp-converter-function}"
    
    # Export variables for potential use by other scripts
    export PROJECT_ID="$project_id"
    export REGION="$region"
    export FUNCTION_NAME="$function_name"
    export BUCKET_NAME="$bucket_name"
    
    log_info "Deployment configuration:"
    log_info "  Project ID: $project_id"
    log_info "  Region: $region"
    log_info "  Function Name: $function_name"
    log_info "  Bucket Name: $bucket_name"
    
    # Confirm deployment
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
    
    # Create or verify project
    create_project "$project_id" "Timestamp Converter API" || exit 1
    
    # Set default project
    gcloud config set project "$project_id"
    gcloud config set compute/region "$region"
    
    # Check billing
    check_billing "$project_id"
    
    # Enable APIs
    enable_apis "$project_id" || exit 1
    
    # Create storage bucket
    create_storage_bucket "$bucket_name" "$region" "$project_id" || exit 1
    
    # Create function source code
    create_function_code "$function_dir" || exit 1
    
    # Deploy function
    deploy_function "$function_name" "$region" "$function_dir" || exit 1
    
    # Backup source code
    backup_source_code "$bucket_name" "$function_dir" || exit 1
    
    # Get function URL for testing
    local function_url
    function_url=$(gcloud run services describe "$function_name" \
        --region="$region" \
        --format="value(status.url)")
    
    # Test function
    test_function "$function_url"
    
    # Save deployment info
    cat > deployment_info.txt << EOF
Timestamp Converter API Deployment Information
==============================================

Project ID: $project_id
Region: $region
Function Name: $function_name
Function URL: $function_url
Storage Bucket: gs://$bucket_name

Deployment completed at: $(date)

Test your API:
curl "${function_url}/?timestamp=now&timezone=UTC&format=human"
curl "${function_url}/?timestamp=1609459200&timezone=US/Eastern&format=iso"

To clean up resources, run: ./destroy.sh
EOF
    
    log_success "Deployment completed successfully!"
    log_info "Function URL: $function_url"
    log_info "Deployment information saved to: deployment_info.txt"
    log_info ""
    log_info "Test your API with:"
    log_info "  curl \"${function_url}/?timestamp=now&timezone=UTC&format=human\""
    log_info ""
    log_info "To clean up all resources, run: ./destroy.sh"
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"