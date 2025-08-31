#!/bin/bash

##############################################################################
# GCP Smart Survey Analysis with Gemini and Cloud Functions - Deployment Script
# 
# This script deploys the complete infrastructure for automated survey analysis
# using Vertex AI Gemini, Cloud Functions, and Firestore.
##############################################################################

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

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_MEMORY="1GB"
DEFAULT_TIMEOUT="300s"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy GCP Smart Survey Analysis infrastructure

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           Deployment region (default: ${DEFAULT_REGION})
    -n, --function-name NAME      Cloud Function name (auto-generated if not provided)
    -d, --database-name NAME      Firestore database name (auto-generated if not provided)
    --dry-run                     Show what would be deployed without executing
    --skip-apis                   Skip API enablement (useful for existing projects)
    --force                       Force deployment even if resources exist
    -h, --help                    Show this help message

EXAMPLES:
    $0 -p my-survey-project
    $0 -p my-project -r europe-west1 -n my-analyzer
    $0 --project-id my-project --dry-run

PREREQUISITES:
    - Google Cloud CLI installed and authenticated
    - Billing enabled on the GCP project
    - Appropriate IAM permissions for creating resources

EOF
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    # Check if Python is available for local testing
    if ! command -v python3 &> /dev/null; then
        log_warning "Python 3 not found - some validation features will be skipped"
    fi
    
    # Check if curl is available for testing
    if ! command -v curl &> /dev/null; then
        log_warning "curl not found - function testing will be skipped"
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate project
validate_project() {
    local project_id="$1"
    
    log_info "Validating project: ${project_id}"
    
    if ! gcloud projects describe "${project_id}" &> /dev/null; then
        log_error "Project '${project_id}' not found or not accessible"
        log_info "Create the project or check your permissions"
        exit 1
    fi
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "${project_id}" &> /dev/null; then
        log_error "Billing is not enabled for project '${project_id}'"
        log_info "Enable billing at: https://console.cloud.google.com/billing"
        exit 1
    fi
    
    log_success "Project validation completed"
}

# Function to enable required APIs
enable_apis() {
    local project_id="$1"
    local skip_apis="$2"
    
    if [[ "${skip_apis}" == "true" ]]; then
        log_info "Skipping API enablement as requested"
        return 0
    fi
    
    log_info "Enabling required APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "aiplatform.googleapis.com"
        "firestore.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --project="${project_id}"; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create Firestore database
create_firestore() {
    local project_id="$1"
    local region="$2"
    local database_name="$3"
    local force="$4"
    
    log_info "Creating Firestore database: ${database_name}"
    
    # Check if database already exists
    if gcloud firestore databases describe "${database_name}" --project="${project_id}" &> /dev/null; then
        if [[ "${force}" == "true" ]]; then
            log_warning "Database ${database_name} already exists, continuing due to --force flag"
        else
            log_warning "Database ${database_name} already exists, skipping creation"
            return 0
        fi
    else
        # Create Firestore database
        if gcloud firestore databases create \
            --region="${region}" \
            --database="${database_name}" \
            --project="${project_id}"; then
            log_success "Firestore database created: ${database_name}"
        else
            log_error "Failed to create Firestore database"
            exit 1
        fi
    fi
    
    # Set default database for subsequent operations
    gcloud config set firestore/database "${database_name}"
    log_success "Default Firestore database set to: ${database_name}"
}

# Function to create Cloud Function source
create_function_source() {
    local temp_dir="$1"
    
    log_info "Creating Cloud Function source code..."
    
    # Create function directory
    local function_dir="${temp_dir}/survey-function"
    mkdir -p "${function_dir}"
    
    # Create main.py
    cat > "${function_dir}/main.py" << 'EOF'
import json
import logging
import os
from typing import Dict, Any
import vertexai
from vertexai.generative_models import GenerativeModel
from google.cloud import firestore
import functions_framework
from flask import Request

# Initialize clients with project ID from environment
project_id = os.environ.get('GCP_PROJECT', os.environ.get('GOOGLE_CLOUD_PROJECT'))
vertexai.init(project=project_id)
model = GenerativeModel("gemini-1.5-flash")
db = firestore.Client()

@functions_framework.http
def analyze_survey(request: Request) -> str:
    """Analyze survey responses using Gemini AI."""
    try:
        # Enable CORS for web requests
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)
        
        request_json = request.get_json()
        if not request_json or 'responses' not in request_json:
            return json.dumps({'error': 'Missing survey responses'}), 400
        
        survey_data = request_json['responses']
        survey_id = request_json.get('survey_id', 'default')
        
        # Create structured analysis prompt
        prompt = f"""
        Analyze the following survey responses and provide a comprehensive analysis in JSON format.
        
        Required JSON structure:
        {{
          "sentiment_score": <number 1-10>,
          "overall_sentiment": "<positive/neutral/negative>",
          "key_themes": ["theme1", "theme2", "theme3"],
          "insights": ["insight1", "insight2", "insight3"],
          "recommendations": [
            {{"action": "action1", "priority": "high/medium/low", "impact": "impact description"}},
            {{"action": "action2", "priority": "high/medium/low", "impact": "impact description"}},
            {{"action": "action3", "priority": "high/medium/low", "impact": "impact description"}}
          ],
          "urgency_level": "<high/medium/low>",
          "confidence_score": <number 0.0-1.0>
        }}
        
        Survey Responses:
        {json.dumps(survey_data, indent=2)}
        
        Provide only the JSON response, no additional text.
        """
        
        # Generate analysis with Gemini
        response = model.generate_content(prompt)
        analysis_text = response.text.strip()
        
        # Clean and parse AI response
        if analysis_text.startswith('```json'):
            analysis_text = analysis_text[7:]
        if analysis_text.endswith('```'):
            analysis_text = analysis_text[:-3]
        
        try:
            analysis_data = json.loads(analysis_text)
        except json.JSONDecodeError as e:
            logging.warning(f"JSON parse error: {e}, using fallback structure")
            analysis_data = {
                'raw_analysis': analysis_text,
                'sentiment_score': 5,
                'overall_sentiment': 'neutral',
                'error': 'Failed to parse structured response'
            }
        
        # Store in Firestore with enhanced metadata
        doc_ref = db.collection('survey_analyses').document()
        doc_data = {
            'survey_id': survey_id,
            'original_responses': survey_data,
            'analysis': analysis_data,
            'timestamp': firestore.SERVER_TIMESTAMP,
            'model_version': 'gemini-1.5-flash',
            'processing_status': 'completed'
        }
        doc_ref.set(doc_data)
        
        headers = {'Access-Control-Allow-Origin': '*'}
        return json.dumps({
            'status': 'success',
            'document_id': doc_ref.id,
            'analysis': analysis_data
        }), 200, headers
        
    except Exception as e:
        logging.error(f"Analysis error: {str(e)}")
        headers = {'Access-Control-Allow-Origin': '*'}
        return json.dumps({'error': str(e)}), 500, headers
EOF
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
functions-framework==3.8.1
google-cloud-aiplatform==1.67.1
google-cloud-firestore==2.18.0
vertexai==1.67.1
flask==3.0.3
EOF
    
    log_success "Cloud Function source code created in ${function_dir}"
    echo "${function_dir}"
}

# Function to deploy Cloud Function
deploy_function() {
    local project_id="$1"
    local region="$2"
    local function_name="$3"
    local memory="$4"
    local timeout="$5"
    local source_dir="$6"
    local force="$7"
    
    log_info "Deploying Cloud Function: ${function_name}"
    
    # Check if function already exists
    if gcloud functions describe "${function_name}" --region="${region}" --project="${project_id}" &> /dev/null; then
        if [[ "${force}" == "true" ]]; then
            log_warning "Function ${function_name} already exists, updating due to --force flag"
        else
            log_warning "Function ${function_name} already exists, updating existing function"
        fi
    fi
    
    # Deploy function
    if gcloud functions deploy "${function_name}" \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --memory "${memory}" \
        --timeout "${timeout}" \
        --source "${source_dir}" \
        --entry-point analyze_survey \
        --region "${region}" \
        --project "${project_id}" \
        --set-env-vars "GCP_PROJECT=${project_id}"; then
        log_success "Cloud Function deployed successfully"
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "${function_name}" \
        --region="${region}" \
        --project="${project_id}" \
        --format="value(httpsTrigger.url)")
    
    echo "${function_url}"
}

# Function to create sample data
create_sample_data() {
    local temp_dir="$1"
    
    log_info "Creating sample survey data..."
    
    cat > "${temp_dir}/sample_survey.json" << 'EOF'
{
  "survey_id": "customer_satisfaction_2024",
  "responses": [
    {
      "question": "How satisfied are you with our customer service?",
      "answer": "Extremely satisfied! The support team was quick to respond and resolved my issue within minutes. The representative was knowledgeable and friendly."
    },
    {
      "question": "What improvements would you suggest?",
      "answer": "The mobile app could be more intuitive. Sometimes I struggle to find basic features, and the loading times are quite slow on older devices."
    },
    {
      "question": "Would you recommend our service to others?",
      "answer": "Absolutely! Despite minor app issues, the overall experience has been fantastic. The product quality is excellent and customer support is top-notch."
    },
    {
      "question": "Additional comments",
      "answer": "I've been a customer for 3 years and have seen consistent improvements. Keep up the great work, but please focus on mobile experience optimization."
    }
  ]
}
EOF
    
    log_success "Sample survey data created"
    echo "${temp_dir}/sample_survey.json"
}

# Function to test the deployment
test_deployment() {
    local function_url="$1"
    local sample_data_file="$2"
    
    log_info "Testing deployed function..."
    
    if ! command -v curl &> /dev/null; then
        log_warning "curl not available, skipping function test"
        return 0
    fi
    
    # Test the function with sample data
    local response_file="/tmp/test_response.json"
    if curl -X POST "${function_url}" \
        -H "Content-Type: application/json" \
        -d @"${sample_data_file}" \
        -o "${response_file}" \
        -s -w "%{http_code}" | grep -q "200"; then
        log_success "Function test completed successfully"
        
        # Display results if jq is available
        if command -v jq &> /dev/null; then
            log_info "Sample analysis result:"
            jq . "${response_file}" 2>/dev/null || cat "${response_file}"
        else
            log_info "Sample analysis result (install jq for formatted output):"
            cat "${response_file}"
        fi
        
        rm -f "${response_file}"
    else
        log_warning "Function test failed - this may be normal during initial deployment"
        log_info "The function may need a few minutes to be fully ready"
    fi
}

# Function to display deployment summary
show_deployment_summary() {
    local project_id="$1"
    local region="$2"
    local function_name="$3"
    local database_name="$4"
    local function_url="$5"
    
    echo
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    echo "Project ID:       ${project_id}"
    echo "Region:           ${region}"
    echo "Function Name:    ${function_name}"
    echo "Database Name:    ${database_name}"
    echo "Function URL:     ${function_url}"
    echo
    echo "Next Steps:"
    echo "1. Test the function using the provided sample data"
    echo "2. Monitor function logs: gcloud functions logs read ${function_name} --region=${region}"
    echo "3. View Firestore data in the Google Cloud Console"
    echo "4. Integrate the function URL into your applications"
    echo
    echo "Cleanup:"
    echo "Run './destroy.sh -p ${project_id}' to remove all resources"
    echo
}

# Function to save deployment state
save_deployment_state() {
    local project_id="$1"
    local region="$2"
    local function_name="$3"
    local database_name="$4"
    local function_url="$5"
    
    local state_file="${SCRIPT_DIR}/.deploy_state"
    cat > "${state_file}" << EOF
PROJECT_ID="${project_id}"
REGION="${region}"
FUNCTION_NAME="${function_name}"
DATABASE_NAME="${database_name}"
FUNCTION_URL="${function_url}"
DEPLOYMENT_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EOF
    
    log_info "Deployment state saved to ${state_file}"
}

# Main deployment function
main() {
    local project_id=""
    local region="${DEFAULT_REGION}"
    local function_name=""
    local database_name=""
    local dry_run="false"
    local skip_apis="false"
    local force="false"
    local memory="${DEFAULT_MEMORY}"
    local timeout="${DEFAULT_TIMEOUT}"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                project_id="$2"
                shift 2
                ;;
            -r|--region)
                region="$2"
                shift 2
                ;;
            -n|--function-name)
                function_name="$2"
                shift 2
                ;;
            -d|--database-name)
                database_name="$2"
                shift 2
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            --skip-apis)
                skip_apis="true"
                shift
                ;;
            --force)
                force="true"
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
    
    # Validate required parameters
    if [[ -z "${project_id}" ]]; then
        log_error "Project ID is required"
        usage
        exit 1
    fi
    
    # Generate default names if not provided
    if [[ -z "${function_name}" ]]; then
        local random_suffix
        random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
        function_name="survey-analyzer-${random_suffix}"
    fi
    
    if [[ -z "${database_name}" ]]; then
        database_name="survey-db"
    fi
    
    # Display configuration
    log_info "=== DEPLOYMENT CONFIGURATION ==="
    echo "Project ID:       ${project_id}"
    echo "Region:           ${region}"
    echo "Function Name:    ${function_name}"
    echo "Database Name:    ${database_name}"
    echo "Memory:           ${memory}"
    echo "Timeout:          ${timeout}"
    echo "Dry Run:          ${dry_run}"
    echo "Skip APIs:        ${skip_apis}"
    echo "Force:            ${force}"
    echo
    
    if [[ "${dry_run}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        return 0
    fi
    
    # Confirm deployment
    if [[ "${force}" != "true" ]]; then
        echo -n "Do you want to proceed with the deployment? (y/N): "
        read -r confirmation
        if [[ ! "${confirmation}" =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Start deployment
    log_info "Starting deployment..."
    
    # Set up temporary directory for deployment files
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf ${temp_dir}" EXIT
    
    # Execute deployment steps
    check_prerequisites
    validate_project "${project_id}"
    
    # Set project context
    gcloud config set project "${project_id}"
    gcloud config set compute/region "${region}"
    
    enable_apis "${project_id}" "${skip_apis}"
    create_firestore "${project_id}" "${region}" "${database_name}" "${force}"
    
    local source_dir
    source_dir=$(create_function_source "${temp_dir}")
    
    local function_url
    function_url=$(deploy_function "${project_id}" "${region}" "${function_name}" "${memory}" "${timeout}" "${source_dir}" "${force}")
    
    local sample_data_file
    sample_data_file=$(create_sample_data "${temp_dir}")
    
    # Wait a moment for function to be fully ready
    log_info "Waiting for function to be fully ready..."
    sleep 30
    
    test_deployment "${function_url}" "${sample_data_file}"
    save_deployment_state "${project_id}" "${region}" "${function_name}" "${database_name}" "${function_url}"
    show_deployment_summary "${project_id}" "${region}" "${function_name}" "${database_name}" "${function_url}"
}

# Execute main function with all arguments
main "$@"