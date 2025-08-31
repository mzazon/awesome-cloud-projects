#!/bin/bash

#
# Deploy script for Unit Converter API with Cloud Functions and Storage
# This script creates a serverless unit conversion API with audit history storage
# Recipe: unit-converter-api-functions-storage
#

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
readonly FUNCTION_SOURCE_DIR="${PROJECT_ROOT}/function-source"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Configuration
FUNCTION_NAME="unit-converter"
REGION="us-central1"
PYTHON_VERSION="python312"
MEMORY="256MB"
TIMEOUT="60s"
DRY_RUN=false

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    log "You may need to manually clean up partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Deploy Unit Converter API with Cloud Functions and Storage

Usage: $0 [OPTIONS]

Options:
    -p, --project PROJECT_ID    GCP project ID (required)
    -r, --region REGION         Deployment region (default: us-central1)
    -f, --function-name NAME    Cloud Function name (default: unit-converter)
    -m, --memory MEMORY         Function memory allocation (default: 256MB)
    -t, --timeout TIMEOUT       Function timeout (default: 60s)
    -d, --dry-run               Show what would be deployed without executing
    -h, --help                  Show this help message

Examples:
    $0 --project my-gcp-project
    $0 --project my-project --region us-east1 --memory 512MB
    $0 --project my-project --dry-run

Environment Variables:
    GOOGLE_CLOUD_PROJECT        GCP project ID (overridden by --project)
    GOOGLE_CLOUD_REGION         Deployment region (overridden by --region)

EOF
}

# Parse command line arguments
parse_args() {
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
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Set project from environment if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-}"
    fi

    # Set region from environment if not provided
    if [[ -n "${GOOGLE_CLOUD_REGION:-}" && "${REGION}" == "us-central1" ]]; then
        REGION="${GOOGLE_CLOUD_REGION}"
    fi

    # Validate required parameters
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "Project ID is required. Use --project or set GOOGLE_CLOUD_PROJECT environment variable."
        show_help
        exit 1
    fi
}

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."

    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi

    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi

    # Validate project access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Cannot access project '${PROJECT_ID}'. Check project ID and permissions."
        exit 1
    fi

    # Validate region
    if ! gcloud compute regions describe "${REGION}" &> /dev/null; then
        log_error "Invalid region '${REGION}'. Use 'gcloud compute regions list' to see available regions."
        exit 1
    fi

    # Check billing
    local billing_account
    billing_account=$(gcloud beta billing projects describe "${PROJECT_ID}" --format="value(billingAccountName)" 2>/dev/null || true)
    if [[ -z "${billing_account}" ]]; then
        log_warning "Billing is not enabled for project '${PROJECT_ID}'. Some services may not work."
    fi

    log_success "Prerequisites validated"
}

# Set project configuration
configure_project() {
    log "Configuring gcloud for project ${PROJECT_ID}..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would set project to: ${PROJECT_ID}"
        log "[DRY RUN] Would set region to: ${REGION}"
        return 0
    fi

    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set functions/region "${REGION}"

    log_success "Project configuration complete"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."

    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would enable APIs: ${apis[*]}"
        return 0
    fi

    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done

    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30

    log_success "All APIs enabled successfully"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket for conversion history..."

    # Generate unique bucket name
    local timestamp
    timestamp=$(date +%s)
    local random_suffix
    random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(shuf -i 100000-999999 -n 1)")
    BUCKET_NAME="${PROJECT_ID}-conversion-history-${random_suffix}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create bucket: gs://${BUCKET_NAME}"
        log "[DRY RUN] Bucket location: ${REGION}"
        log "[DRY RUN] Bucket class: STANDARD"
        return 0
    fi

    # Create bucket with uniform bucket-level access
    if gcloud storage buckets create "gs://${BUCKET_NAME}" \
        --location="${REGION}" \
        --uniform-bucket-level-access \
        --storage-class=STANDARD; then
        log_success "Created bucket: gs://${BUCKET_NAME}"
    else
        log_error "Failed to create storage bucket"
        exit 1
    fi

    # Set bucket labels for better resource management
    gcloud storage buckets update "gs://${BUCKET_NAME}" \
        --update-labels=purpose=unit-converter,environment=production,recipe=unit-converter-api-functions-storage

    log_success "Storage bucket configured successfully"
}

# Create function source code
create_function_source() {
    log "Creating Cloud Function source code..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would create function source in: ${FUNCTION_SOURCE_DIR}"
        return 0
    fi

    # Create source directory
    mkdir -p "${FUNCTION_SOURCE_DIR}"
    cd "${FUNCTION_SOURCE_DIR}"

    # Create main.py with unit conversion logic
    cat > main.py << 'EOF'
import json
import datetime
from google.cloud import storage
import os

# Initialize Cloud Storage client with automatic authentication
storage_client = storage.Client()
BUCKET_NAME = os.environ.get('BUCKET_NAME')

def convert_units(request):
    """
    HTTP Cloud Function for unit conversion with history storage.
    Supports temperature, weight, and length conversions.
    """
    
    # Set CORS headers for web browser compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight CORS requests
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Parse JSON request data
        request_json = request.get_json(silent=True)
        
        if not request_json:
            return ({'error': 'Invalid JSON in request body'}, 400, headers)
        
        # Extract conversion parameters
        value = float(request_json.get('value', 0))
        from_unit = request_json.get('from_unit', '').lower()
        to_unit = request_json.get('to_unit', '').lower()
        
        # Perform unit conversion using business logic
        result = perform_conversion(value, from_unit, to_unit)
        
        if result is None:
            return ({'error': 'Unsupported unit conversion'}, 400, headers)
        
        # Create conversion record for audit trail
        conversion_record = {
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'input_value': value,
            'from_unit': from_unit,
            'to_unit': to_unit,
            'result': result,
            'conversion_type': get_conversion_type(from_unit, to_unit)
        }
        
        # Store conversion history in Cloud Storage
        store_conversion_history(conversion_record)
        
        # Return successful conversion result
        response = {
            'original_value': value,
            'original_unit': from_unit,
            'converted_value': round(result, 4),
            'converted_unit': to_unit,
            'timestamp': conversion_record['timestamp']
        }
        
        return (response, 200, headers)
        
    except Exception as e:
        return ({'error': f'Conversion failed: {str(e)}'}, 500, headers)

def perform_conversion(value, from_unit, to_unit):
    """Convert between different unit types with precise calculations."""
    
    # Temperature conversions
    if from_unit == 'celsius' and to_unit == 'fahrenheit':
        return (value * 9/5) + 32
    elif from_unit == 'fahrenheit' and to_unit == 'celsius':
        return (value - 32) * 5/9
    elif from_unit == 'celsius' and to_unit == 'kelvin':
        return value + 273.15
    elif from_unit == 'kelvin' and to_unit == 'celsius':
        return value - 273.15
    
    # Length conversions
    elif from_unit == 'meters' and to_unit == 'feet':
        return value * 3.28084
    elif from_unit == 'feet' and to_unit == 'meters':
        return value * 0.3048
    elif from_unit == 'kilometers' and to_unit == 'miles':
        return value * 0.621371
    elif from_unit == 'miles' and to_unit == 'kilometers':
        return value * 1.60934
    
    # Weight conversions
    elif from_unit == 'kilograms' and to_unit == 'pounds':
        return value * 2.20462
    elif from_unit == 'pounds' and to_unit == 'kilograms':
        return value * 0.453592
    elif from_unit == 'grams' and to_unit == 'ounces':
        return value * 0.035274
    elif from_unit == 'ounces' and to_unit == 'grams':
        return value * 28.3495
    
    # Same unit conversions
    elif from_unit == to_unit:
        return value
    
    return None

def get_conversion_type(from_unit, to_unit):
    """Categorize conversion type for analytics purposes."""
    temp_units = ['celsius', 'fahrenheit', 'kelvin']
    length_units = ['meters', 'feet', 'kilometers', 'miles']
    weight_units = ['kilograms', 'pounds', 'grams', 'ounces']
    
    if from_unit in temp_units and to_unit in temp_units:
        return 'temperature'
    elif from_unit in length_units and to_unit in length_units:
        return 'length'
    elif from_unit in weight_units and to_unit in weight_units:
        return 'weight'
    
    return 'unknown'

def store_conversion_history(record):
    """Store conversion record in Cloud Storage for audit trail."""
    try:
        bucket = storage_client.bucket(BUCKET_NAME)
        
        # Create filename with timestamp for easy sorting
        filename = f"conversions/{record['timestamp']}-{record['conversion_type']}.json"
        blob = bucket.blob(filename)
        
        # Upload JSON record to Cloud Storage
        blob.upload_from_string(
            json.dumps(record, indent=2),
            content_type='application/json'
        )
        
    except Exception as e:
        print(f"Failed to store conversion history: {e}")
        # Continue processing even if storage fails
EOF

    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-storage==2.18.0
EOF

    log_success "Function source code created"
}

# Deploy Cloud Function
deploy_function() {
    log "Deploying Cloud Function..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would deploy function: ${FUNCTION_NAME}"
        log "[DRY RUN] Runtime: ${PYTHON_VERSION}"
        log "[DRY RUN] Memory: ${MEMORY}"
        log "[DRY RUN] Timeout: ${TIMEOUT}"
        log "[DRY RUN] Environment variables: BUCKET_NAME=${BUCKET_NAME}"
        return 0
    fi

    cd "${FUNCTION_SOURCE_DIR}"

    if gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime="${PYTHON_VERSION}" \
        --trigger-http \
        --allow-unauthenticated \
        --source=. \
        --entry-point=convert_units \
        --memory="${MEMORY}" \
        --timeout="${TIMEOUT}" \
        --set-env-vars="BUCKET_NAME=${BUCKET_NAME}" \
        --region="${REGION}" \
        --max-instances=100 \
        --quiet; then
        log_success "Cloud Function deployed successfully"
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi

    # Get function URL
    FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(httpsTrigger.url)")

    log_success "Function URL: ${FUNCTION_URL}"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would verify function deployment and storage bucket"
        return 0
    fi

    # Test function with a sample conversion
    log "Testing function with sample conversion..."
    
    local test_response
    test_response=$(curl -s -X POST "${FUNCTION_URL}" \
        -H "Content-Type: application/json" \
        -d '{"value": 25, "from_unit": "celsius", "to_unit": "fahrenheit"}' \
        2>/dev/null || echo "ERROR")

    if [[ "${test_response}" == "ERROR" ]]; then
        log_error "Function test failed - function may not be responding"
        return 1
    elif echo "${test_response}" | grep -q "converted_value"; then
        log_success "Function test passed"
        log "Test response: ${test_response}"
    else
        log_warning "Function responded but may have issues: ${test_response}"
    fi

    # Verify storage bucket exists
    if gcloud storage buckets describe "gs://${BUCKET_NAME}" &> /dev/null; then
        log_success "Storage bucket verified"
    else
        log_error "Storage bucket verification failed"
        return 1
    fi

    # Check for conversion history (may not exist yet)
    local history_count
    history_count=$(gcloud storage ls "gs://${BUCKET_NAME}/conversions/" 2>/dev/null | wc -l || echo "0")
    log "Conversion history files: ${history_count}"

    log_success "Deployment verification complete"
}

# Generate deployment summary
generate_summary() {
    log "Generating deployment summary..."

    cat << EOF | tee -a "${LOG_FILE}"

================================================================================
DEPLOYMENT SUMMARY
================================================================================

Project ID:       ${PROJECT_ID}
Region:           ${REGION}
Function Name:    ${FUNCTION_NAME}
Function URL:     ${FUNCTION_URL:-"Not available in dry-run mode"}
Storage Bucket:   gs://${BUCKET_NAME}
Runtime:          ${PYTHON_VERSION}
Memory:           ${MEMORY}
Timeout:          ${TIMEOUT}

API Endpoints:
- POST ${FUNCTION_URL:-"<FUNCTION_URL>"}
  Content-Type: application/json
  Body: {"value": <number>, "from_unit": "<unit>", "to_unit": "<unit>"}

Supported Units:
- Temperature: celsius, fahrenheit, kelvin
- Length: meters, feet, kilometers, miles  
- Weight: kilograms, pounds, grams, ounces

Example Usage:
curl -X POST ${FUNCTION_URL:-"<FUNCTION_URL>"} \\
  -H "Content-Type: application/json" \\
  -d '{"value": 25, "from_unit": "celsius", "to_unit": "fahrenheit"}'

Storage:
- Conversion history stored in: gs://${BUCKET_NAME}/conversions/
- Files are automatically organized by timestamp and conversion type

Cost Estimate (per month):
- Cloud Functions: ~\$0.01 for 10K invocations
- Cloud Storage: ~\$0.02 for 1GB of history data
- Network egress: ~\$0.10 per GB

To clean up resources, run: ./destroy.sh --project ${PROJECT_ID}

================================================================================
EOF

    if [[ "${DRY_RUN}" == "false" ]]; then
        log_success "Deployment completed successfully!"
        log "Function is ready to handle unit conversion requests."
        log "Check conversion history in Cloud Storage bucket: gs://${BUCKET_NAME}"
    else
        log_success "Dry-run completed successfully!"
        log "No resources were actually created."
    fi
}

# Main execution
main() {
    log "Starting Unit Converter API deployment..."
    log "Log file: ${LOG_FILE}"

    parse_args "$@"
    validate_prerequisites
    configure_project
    enable_apis
    create_storage_bucket
    create_function_source
    deploy_function
    verify_deployment
    generate_summary

    log_success "Deployment script completed successfully!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi