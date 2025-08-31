#!/bin/bash

#######################################################################
# Weather API Cloud Functions Deployment Script
# 
# This script deploys a serverless weather API using Google Cloud Functions.
# It creates all necessary resources including the function deployment,
# IAM permissions, and provides the HTTP endpoint URL.
#
# Prerequisites:
# - Google Cloud CLI (gcloud) installed and authenticated
# - Billing enabled on the Google Cloud project
# - Appropriate IAM permissions for Cloud Functions deployment
#
# Usage: ./deploy.sh [PROJECT_ID] [REGION]
#######################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CODE_DIR="$(dirname "${SCRIPT_DIR}")"
readonly FUNCTION_SOURCE_DIR="${CODE_DIR}/terraform/function_source"
readonly LOG_FILE="/tmp/weather-api-deploy-$(date +%Y%m%d-%H%M%S).log"

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_TIMEOUT="60s"
DEFAULT_MEMORY="256MB"

# Colors for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#######################################################################
# Utility Functions
#######################################################################

log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

show_usage() {
    cat << EOF
Usage: $0 [PROJECT_ID] [REGION]

Deploy Weather API Cloud Functions

Arguments:
    PROJECT_ID    Google Cloud Project ID (optional, will use current project if not specified)
    REGION        Google Cloud region for deployment (default: ${DEFAULT_REGION})

Options:
    -h, --help    Show this help message

Examples:
    $0                                    # Use current project and default region
    $0 my-project-id                      # Use specified project, default region
    $0 my-project-id us-east1            # Use specified project and region

Prerequisites:
    - gcloud CLI installed and authenticated
    - Billing enabled on the target project
    - Cloud Functions API enabled
    - Appropriate IAM permissions

EOF
}

cleanup_on_exit() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Deployment failed with exit code ${exit_code}"
        log_info "Check log file: ${LOG_FILE}"
        log_info "To clean up partial deployment, run: ./destroy.sh"
    fi
    exit ${exit_code}
}

#######################################################################
# Validation Functions
#######################################################################

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud >&/dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud CLI."
        log_info "Installation guide: https://cloud.google.com/sdk/docs/install"
        return 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
        log_error "Not authenticated with gcloud. Run: gcloud auth login"
        return 1
    fi
    
    log_success "Prerequisites check passed"
    return 0
}

validate_project() {
    local project_id="${1}"
    
    log_info "Validating project: ${project_id}"
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "${project_id}" >&/dev/null; then
        log_error "Project '${project_id}' not found or not accessible"
        log_info "Available projects:"
        gcloud projects list --filter="lifecycleState:ACTIVE" --format="table(projectId,name)"
        return 1
    fi
    
    # Check if billing is enabled
    local billing_account
    billing_account=$(gcloud billing projects describe "${project_id}" \
        --format="value(billingAccountName)" 2>/dev/null || echo "")
    
    if [[ -z "${billing_account}" ]]; then
        log_error "Billing is not enabled for project '${project_id}'"
        log_info "Enable billing: https://console.cloud.google.com/billing/linkedaccount?project=${project_id}"
        return 1
    fi
    
    log_success "Project validation passed"
    return 0
}

validate_region() {
    local region="${1}"
    
    log_info "Validating region: ${region}"
    
    # Check if region exists and supports Cloud Functions
    if ! gcloud functions regions list --format="value(locationId)" 2>/dev/null | grep -q "^${region}$"; then
        log_error "Region '${region}' is not available for Cloud Functions"
        log_info "Available regions:"
        gcloud functions regions list --format="table(locationId)"
        return 1
    fi
    
    log_success "Region validation passed"
    return 0
}

#######################################################################
# Deployment Functions
#######################################################################

setup_environment() {
    local project_id="${1}"
    local region="${2}"
    
    log_info "Setting up environment..."
    
    # Set default project
    gcloud config set project "${project_id}"
    
    # Set default region for functions
    gcloud config set functions/region "${region}"
    
    # Generate unique function name with timestamp
    readonly FUNCTION_NAME="weather-api-$(date +%s)"
    readonly DEPLOYMENT_TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
    
    log_success "Environment setup completed"
    log_info "Function name: ${FUNCTION_NAME}"
    log_info "Deployment timestamp: ${DEPLOYMENT_TIMESTAMP}"
}

enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling API: ${api}"
        if gcloud services enable "${api}" 2>>"${LOG_FILE}"; then
            log_success "Enabled: ${api}"
        else
            log_error "Failed to enable: ${api}"
            return 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All APIs enabled successfully"
}

prepare_function_source() {
    log_info "Preparing function source code..."
    
    # Create temporary deployment directory
    readonly TEMP_DEPLOY_DIR="/tmp/weather-api-deploy-${DEPLOYMENT_TIMESTAMP}"
    mkdir -p "${TEMP_DEPLOY_DIR}"
    
    # Copy source files
    if [[ -d "${FUNCTION_SOURCE_DIR}" ]]; then
        cp -r "${FUNCTION_SOURCE_DIR}"/* "${TEMP_DEPLOY_DIR}/"
        log_info "Using existing function source from: ${FUNCTION_SOURCE_DIR}"
    else
        # Create source files if they don't exist
        create_function_source "${TEMP_DEPLOY_DIR}"
        log_info "Created function source in: ${TEMP_DEPLOY_DIR}"
    fi
    
    # Validate source files
    if [[ ! -f "${TEMP_DEPLOY_DIR}/main.py" ]] || [[ ! -f "${TEMP_DEPLOY_DIR}/requirements.txt" ]]; then
        log_error "Missing required source files (main.py or requirements.txt)"
        return 1
    fi
    
    log_success "Function source prepared"
}

create_function_source() {
    local target_dir="${1}"
    
    log_info "Creating function source files..."
    
    # Create main.py
    cat > "${target_dir}/main.py" << 'EOF'
import functions_framework
import json
import os
from datetime import datetime, timezone
from flask import jsonify

@functions_framework.http
def weather_api(request):
    """HTTP Cloud Function for weather data retrieval."""
    
    # Enable CORS for web applications
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for actual request
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Get city parameter from request
        city = request.args.get('city', 'London')
        
        # Mock weather data for demonstration
        # In production, replace with actual weather API call
        mock_weather_data = {
            "city": city,
            "temperature": 22,
            "condition": "Partly Cloudy",
            "humidity": 65,
            "wind_speed": 12,
            "description": f"Current weather for {city}",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "api_version": "1.0",
            "deployment_timestamp": os.environ.get('DEPLOYMENT_TIMESTAMP', 'unknown')
        }
        
        return (jsonify(mock_weather_data), 200, headers)
        
    except Exception as e:
        error_response = {
            "error": "Failed to fetch weather data",
            "message": str(e),
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        return (jsonify(error_response), 500, headers)
EOF

    # Create requirements.txt
    cat > "${target_dir}/requirements.txt" << 'EOF'
functions-framework==3.*
Flask==2.*
EOF

    log_success "Function source files created"
}

deploy_function() {
    local project_id="${1}"
    local region="${2}"
    
    log_info "Deploying Cloud Function..."
    log_info "Function name: ${FUNCTION_NAME}"
    log_info "Source directory: ${TEMP_DEPLOY_DIR}"
    
    # Deploy function with comprehensive configuration
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime=python313 \
        --region="${region}" \
        --source="${TEMP_DEPLOY_DIR}" \
        --entry-point=weather_api \
        --trigger-http \
        --allow-unauthenticated \
        --memory="${DEFAULT_MEMORY}" \
        --timeout="${DEFAULT_TIMEOUT}" \
        --set-env-vars="DEPLOYMENT_TIMESTAMP=${DEPLOYMENT_TIMESTAMP}" \
        --max-instances=10 \
        --min-instances=0 \
        --concurrency=80 \
        --format="text" 2>>"${LOG_FILE}"; then
        
        log_success "Cloud Function deployed successfully"
        return 0
    else
        log_error "Failed to deploy Cloud Function"
        log_info "Check deployment logs for details"
        return 1
    fi
}

get_function_info() {
    local project_id="${1}"
    local region="${2}"
    
    log_info "Retrieving function information..."
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${region}" \
        --gen2 \
        --format="value(serviceConfig.uri)" 2>/dev/null)
    
    if [[ -n "${function_url}" ]]; then
        log_success "Function URL retrieved: ${function_url}"
        
        # Store deployment info
        cat > "${CODE_DIR}/deployment-info.txt" << EOF
# Weather API Cloud Functions Deployment Information
# Generated: $(date -Iseconds)

FUNCTION_NAME="${FUNCTION_NAME}"
PROJECT_ID="${project_id}"
REGION="${region}"
FUNCTION_URL="${function_url}"
DEPLOYMENT_TIMESTAMP="${DEPLOYMENT_TIMESTAMP}"

# Test the API:
curl "${function_url}"
curl "${function_url}?city=Paris"

# View logs:
gcloud functions logs read ${FUNCTION_NAME} --region=${region} --gen2 --limit=50

# Delete function:
gcloud functions delete ${FUNCTION_NAME} --region=${region} --gen2 --quiet
EOF
        
        log_info "Deployment info saved to: ${CODE_DIR}/deployment-info.txt"
        return 0
    else
        log_error "Failed to retrieve function URL"
        return 1
    fi
}

test_deployment() {
    local function_url="${1}"
    
    log_info "Testing deployed function..."
    
    # Test basic functionality
    log_info "Testing default city (London)..."
    if curl -sf --max-time 30 "${function_url}" >/dev/null 2>&1; then
        log_success "Default city test passed"
    else
        log_warning "Default city test failed - function may still be initializing"
    fi
    
    # Test with parameter
    log_info "Testing with city parameter..."
    if curl -sf --max-time 30 "${function_url}?city=Tokyo" >/dev/null 2>&1; then
        log_success "City parameter test passed"
    else
        log_warning "City parameter test failed - function may still be initializing"
    fi
    
    log_info "Function testing completed"
    log_info "Note: It may take a few minutes for the function to be fully available"
}

cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    if [[ -d "${TEMP_DEPLOY_DIR}" ]]; then
        rm -rf "${TEMP_DEPLOY_DIR}"
        log_success "Temporary deployment directory cleaned up"
    fi
}

show_deployment_summary() {
    local project_id="${1}"
    local region="${2}"
    local function_url="${3}"
    
    cat << EOF

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
${GREEN}🎉 WEATHER API DEPLOYMENT SUCCESSFUL! 🎉${NC}
${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${BLUE}Deployment Details:${NC}
  Function Name:    ${YELLOW}${FUNCTION_NAME}${NC}
  Project ID:       ${YELLOW}${project_id}${NC}
  Region:           ${YELLOW}${region}${NC}
  Runtime:          ${YELLOW}Python 3.13${NC}
  Memory:           ${YELLOW}${DEFAULT_MEMORY}${NC}
  Timeout:          ${YELLOW}${DEFAULT_TIMEOUT}${NC}

${BLUE}API Endpoint:${NC}
  ${GREEN}${function_url}${NC}

${BLUE}Test Commands:${NC}
  # Test default city (London)
  ${YELLOW}curl "${function_url}"${NC}
  
  # Test specific city
  ${YELLOW}curl "${function_url}?city=Paris"${NC}
  
  # Pretty JSON output
  ${YELLOW}curl "${function_url}?city=Tokyo" | jq .${NC}

${BLUE}Management Commands:${NC}
  # View function logs
  ${YELLOW}gcloud functions logs read ${FUNCTION_NAME} --region=${region} --gen2 --limit=50${NC}
  
  # Update function
  ${YELLOW}gcloud functions deploy ${FUNCTION_NAME} --source=. --region=${region} --gen2${NC}
  
  # Delete function
  ${YELLOW}gcloud functions delete ${FUNCTION_NAME} --region=${region} --gen2${NC}

${BLUE}Monitoring:${NC}
  Google Cloud Console: ${YELLOW}https://console.cloud.google.com/functions/details/${region}/${FUNCTION_NAME}?project=${project_id}${NC}

${BLUE}Next Steps:${NC}
  1. Test the API endpoints using the curl commands above
  2. Integrate the API endpoint into your applications
  3. Consider adding authentication for production use
  4. Monitor function performance and logs in the Cloud Console
  5. Set up alerting for errors and performance issues

${BLUE}Clean Up:${NC}
  To remove all deployed resources: ${YELLOW}./destroy.sh${NC}

${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

EOF
}

#######################################################################
# Main Deployment Function
#######################################################################

main() {
    # Handle help option
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    # Set up exit trap
    trap cleanup_on_exit EXIT
    
    # Initialize logging
    log_info "Starting Weather API Cloud Functions deployment..."
    log_info "Log file: ${LOG_FILE}"
    
    # Parse arguments
    local project_id="${1:-}"
    local region="${2:-${DEFAULT_REGION}}"
    
    # Get current project if not specified
    if [[ -z "${project_id}" ]]; then
        project_id=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${project_id}" ]]; then
            log_error "No project specified and no default project configured"
            log_info "Usage: $0 PROJECT_ID [REGION]"
            log_info "Or set default project: gcloud config set project PROJECT_ID"
            exit 1
        fi
        log_info "Using current project: ${project_id}"
    fi
    
    # Validation phase
    check_prerequisites || exit 1
    validate_project "${project_id}" || exit 1
    validate_region "${region}" || exit 1
    
    # Deployment phase
    setup_environment "${project_id}" "${region}"
    enable_apis || exit 1
    prepare_function_source || exit 1
    deploy_function "${project_id}" "${region}" || exit 1
    
    # Get function information
    local function_url
    get_function_info "${project_id}" "${region}" || exit 1
    function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${region}" \
        --gen2 \
        --format="value(serviceConfig.uri)" 2>/dev/null)
    
    # Test deployment
    test_deployment "${function_url}"
    
    # Cleanup
    cleanup_temp_files
    
    # Show summary
    show_deployment_summary "${project_id}" "${region}" "${function_url}"
    
    log_success "Weather API deployment completed successfully!"
    
    # Remove exit trap since we succeeded
    trap - EXIT
}

#######################################################################
# Script Entry Point
#######################################################################

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi