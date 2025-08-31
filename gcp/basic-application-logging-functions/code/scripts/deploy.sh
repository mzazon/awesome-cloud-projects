#!/bin/bash

# ==============================================================================
# GCP Basic Application Logging with Cloud Functions - Deployment Script
# ==============================================================================
# This script deploys a Cloud Function with structured logging capabilities
# using Google Cloud Logging client library for comprehensive observability.
#
# Prerequisites:
# - Google Cloud CLI installed and authenticated
# - Required APIs enabled (Cloud Functions, Cloud Logging, Cloud Build)
# - Appropriate IAM permissions for resource creation
# ==============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
readonly TEMP_DIR="${SCRIPT_DIR}/tmp"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Default configuration (can be overridden by environment variables)
PROJECT_ID="${PROJECT_ID:-logging-demo-$(date +%s)}"
REGION="${REGION:-us-central1}"
FUNCTION_NAME="${FUNCTION_NAME:-logging-demo-function}"
RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up temporary resources..."
    
    # Clean up temporary directory
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_info "Removed temporary directory: $TEMP_DIR"
    fi
    
    # Optionally clean up partially created resources
    if [[ "${CLEANUP_ON_ERROR:-true}" == "true" ]]; then
        log_warning "Attempting to clean up any partially created resources..."
        ./destroy.sh --force 2>/dev/null || true
    fi
    
    exit 1
}

trap cleanup_on_error ERR

# Validation functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_info "Please install gcloud: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_info "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_warning "OpenSSL not found, using alternative random generation"
        RANDOM_SUFFIX="$(python3 -c "import random; print(''.join([hex(random.randint(0,15))[2:] for _ in range(6)]))")"
    fi
    
    log_success "Prerequisites check completed"
}

validate_environment() {
    log_info "Validating environment configuration..."
    
    # Validate region
    if ! gcloud compute regions list --format="value(name)" | grep -q "^${REGION}$"; then
        log_error "Invalid region: $REGION"
        log_info "Available regions: $(gcloud compute regions list --format="value(name)" | tr '\n' ' ')"
        exit 1
    fi
    
    # Validate project ID format
    if [[ ! "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        log_error "Invalid project ID format: $PROJECT_ID"
        log_info "Project ID must be 6-30 characters, start with lowercase letter, contain only lowercase letters, digits, and hyphens"
        exit 1
    fi
    
    log_success "Environment validation completed"
}

create_project() {
    log_info "Creating Google Cloud project: $PROJECT_ID"
    
    # Check if project already exists
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_warning "Project $PROJECT_ID already exists, using existing project"
    else
        # Create new project
        if ! gcloud projects create "$PROJECT_ID" --name="Cloud Functions Logging Demo"; then
            log_error "Failed to create project: $PROJECT_ID"
            exit 1
        fi
        log_success "Created project: $PROJECT_ID"
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    
    log_success "Set default project and region"
}

enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "logging.googleapis.com" 
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if ! gcloud services enable "$api"; then
            log_error "Failed to enable API: $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

create_function_code() {
    log_info "Creating Cloud Function source code..."
    
    mkdir -p "$TEMP_DIR"
    
    # Create requirements.txt
    cat > "$TEMP_DIR/requirements.txt" << 'EOF'
functions-framework==3.8.0
google-cloud-logging==3.11.0
EOF
    
    # Create main.py with structured logging function
    cat > "$TEMP_DIR/main.py" << 'EOF'
import logging
import functions_framework
from google.cloud.logging import Client


@functions_framework.http
def log_demo(request):
    """Cloud Function demonstrating structured logging capabilities."""
    
    # Initialize Cloud Logging client and setup integration
    logging_client = Client()
    logging_client.setup_logging()
    
    # Extract request information for logging context
    method = request.method
    path = request.path
    user_agent = request.headers.get('User-Agent', 'Unknown')
    
    # Create structured log entries with different severity levels
    logging.info("Function invocation started", extra={
        "json_fields": {
            "component": "log-demo-function",
            "request_method": method,
            "request_path": path,
            "event_type": "function_start"
        }
    })
    
    # Simulate application logic with informational logging
    logging.info("Processing user request", extra={
        "json_fields": {
            "component": "log-demo-function",
            "user_agent": user_agent,
            "processing_stage": "validation",
            "event_type": "request_processing"
        }
    })
    
    # Example warning log for demonstration
    if "test" in request.args.get('mode', '').lower():
        logging.warning("Running in test mode", extra={
            "json_fields": {
                "component": "log-demo-function",
                "mode": "test",
                "event_type": "configuration_warning"
            }
        })
    
    # Success completion log
    logging.info("Function execution completed successfully", extra={
        "json_fields": {
            "component": "log-demo-function",
            "status": "success",
            "event_type": "function_complete"
        }
    })
    
    return {
        "message": "Logging demonstration completed",
        "status": "success",
        "logs_generated": 4
    }
EOF
    
    log_success "Created function source code in: $TEMP_DIR"
}

deploy_function() {
    log_info "Deploying Cloud Function: $FUNCTION_NAME"
    
    # Deploy function with logging configuration
    if ! gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --region "$REGION" \
        --memory 256MB \
        --timeout 60s \
        --source "$TEMP_DIR" \
        --set-env-vars "FUNCTION_TARGET=log_demo"; then
        log_error "Failed to deploy Cloud Function: $FUNCTION_NAME"
        exit 1
    fi
    
    # Get function URL for testing
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region "$REGION" \
        --format="value(httpsTrigger.url)")
    
    # Store function URL in deployment info file
    echo "FUNCTION_URL=$function_url" > "$SCRIPT_DIR/deployment_info.env"
    echo "PROJECT_ID=$PROJECT_ID" >> "$SCRIPT_DIR/deployment_info.env"
    echo "REGION=$REGION" >> "$SCRIPT_DIR/deployment_info.env"
    echo "FUNCTION_NAME=$FUNCTION_NAME" >> "$SCRIPT_DIR/deployment_info.env"
    
    log_success "Cloud Function deployed successfully"
    log_info "Function URL: $function_url"
}

test_function() {
    log_info "Testing deployed function..."
    
    # Source deployment info
    source "$SCRIPT_DIR/deployment_info.env" 2>/dev/null || {
        log_error "Deployment info not found. Function may not be deployed."
        exit 1
    }
    
    # Test function with normal request
    log_info "Testing normal request..."
    if curl -s "$FUNCTION_URL" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin), indent=2))" 2>/dev/null; then
        log_success "Normal request test passed"
    else
        log_warning "Normal request test failed or returned non-JSON response"
    fi
    
    # Test function with test mode parameter
    log_info "Testing with test mode parameter..."
    if curl -s "${FUNCTION_URL}?mode=test" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin), indent=2))" 2>/dev/null; then
        log_success "Test mode request passed"
    else
        log_warning "Test mode request failed or returned non-JSON response"
    fi
    
    # Generate additional log entries
    log_info "Generating additional log entries for demonstration..."
    curl -s "${FUNCTION_URL}?user=demo" >/dev/null 2>&1 || true
    
    log_success "Function testing completed"
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    # Verify function is deployed and active
    local function_status
    function_status=$(gcloud functions describe "$FUNCTION_NAME" \
        --region "$REGION" \
        --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$function_status" == "ACTIVE" ]]; then
        log_success "Function is active and ready"
    else
        log_error "Function is not active. Status: $function_status"
        exit 1
    fi
    
    # Wait for logs to propagate
    log_info "Waiting for logs to propagate..."
    sleep 30
    
    # Check for structured logs
    log_info "Checking for structured logs..."
    local log_count
    log_count=$(gcloud logging read "resource.type=\"cloud_function\" AND \
        resource.labels.function_name=\"$FUNCTION_NAME\"" \
        --limit 10 \
        --format="value(jsonPayload.component)" 2>/dev/null | wc -l)
    
    if [[ "$log_count" -gt 0 ]]; then
        log_success "Found $log_count structured log entries"
    else
        log_warning "No structured logs found yet (may need more time to propagate)"
    fi
    
    log_success "Deployment verification completed"
}

cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_success "Removed temporary directory: $TEMP_DIR"
    fi
}

display_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy a GCP Cloud Function with structured logging capabilities.

OPTIONS:
    -p, --project PROJECT_ID    Set the Google Cloud project ID
    -r, --region REGION         Set the deployment region (default: us-central1)
    -f, --function FUNCTION     Set the function name (default: logging-demo-function)
    -h, --help                  Display this help message
    --skip-test                Skip function testing after deployment
    --cleanup-on-error         Clean up resources if deployment fails (default: true)
    --dry-run                  Show what would be deployed without executing

ENVIRONMENT VARIABLES:
    PROJECT_ID                  Google Cloud project ID
    REGION                      Deployment region
    FUNCTION_NAME              Cloud Function name
    CLEANUP_ON_ERROR           Clean up on deployment failure (true/false)

EXAMPLES:
    $0                                        # Deploy with default settings
    $0 --project my-project --region us-west1 # Deploy to specific project and region
    $0 --skip-test                           # Deploy without testing
    $0 --dry-run                             # Show deployment plan

EOF
}

# Main deployment function
main() {
    local skip_test=false
    local dry_run=false
    
    # Initialize log file
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
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
            -f|--function)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            --skip-test)
                skip_test=true
                shift
                ;;
            --cleanup-on-error)
                CLEANUP_ON_ERROR="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                display_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                display_usage
                exit 1
                ;;
        esac
    done
    
    log_info "=== GCP Cloud Functions Logging Demo Deployment ==="
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Function Name: $FUNCTION_NAME"
    log_info "Skip Test: $skip_test"
    log_info "Dry Run: $dry_run"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "DRY RUN: Would deploy the following resources:"
        log_info "  - Google Cloud Project: $PROJECT_ID"
        log_info "  - Cloud Function: $FUNCTION_NAME in $REGION"
        log_info "  - Required APIs: Cloud Functions, Cloud Logging, Cloud Build"
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    validate_environment
    create_project
    enable_apis
    create_function_code
    deploy_function
    
    if [[ "$skip_test" != "true" ]]; then
        test_function
    fi
    
    verify_deployment
    cleanup_temp_files
    
    log_success "=== Deployment completed successfully! ==="
    log_info "Next steps:"
    log_info "1. View logs in Cloud Console: https://console.cloud.google.com/logs/query"
    log_info "2. Test the function: curl \$(cat $SCRIPT_DIR/deployment_info.env | grep FUNCTION_URL | cut -d= -f2)"
    log_info "3. Clean up resources: $SCRIPT_DIR/destroy.sh"
    log_info ""
    log_info "Deployment details saved to: $SCRIPT_DIR/deployment_info.env"
    log_info "Full deployment log: $LOG_FILE"
}

# Execute main function with all arguments
main "$@"