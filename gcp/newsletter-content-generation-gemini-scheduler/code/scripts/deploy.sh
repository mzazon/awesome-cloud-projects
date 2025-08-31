#!/bin/bash

# Deploy script for Newsletter Content Generation with Gemini and Scheduler
# This script deploys the complete serverless newsletter automation solution

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly LOG_FILE="/tmp/newsletter-deploy-$(date +%Y%m%d_%H%M%S).log"
readonly CONFIG_FILE="${SCRIPT_DIR}/../.deployment-config"

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Utility functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Newsletter Content Generation with Gemini and Scheduler

OPTIONS:
    -p, --project PROJECT_ID    Google Cloud project ID
    -r, --region REGION         Deployment region (default: us-central1)
    -y, --yes                   Skip confirmation prompts
    -d, --dry-run              Show what would be deployed without making changes
    -h, --help                 Show this help message

EXAMPLES:
    $0 --project my-project-123
    $0 --project my-project-123 --region us-east1
    $0 --project my-project-123 --yes

EOF
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_error "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed or not in PATH"
        log_error "Please ensure Google Cloud CLI is properly installed"
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Installing via package manager..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v brew &> /dev/null; then
            brew install jq
        else
            log_error "Could not install jq automatically. Please install it manually."
            exit 1
        fi
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random strings"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -n1 &> /dev/null; then
        log_error "No active gcloud authentication found"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate project and setup environment
setup_environment() {
    log_info "Setting up environment..."
    
    # Validate project exists and user has access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project '${PROJECT_ID}' does not exist or you don't have access"
        exit 1
    fi
    
    # Set project configuration
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${REGION}-a"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names with unique suffixes
    export FUNCTION_NAME="newsletter-generator-${RANDOM_SUFFIX}"
    export BUCKET_NAME="newsletter-content-${PROJECT_ID}-${RANDOM_SUFFIX}"
    export JOB_NAME="newsletter-schedule-${RANDOM_SUFFIX}"
    
    # Save configuration for cleanup script
    cat > "${CONFIG_FILE}" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
FUNCTION_NAME=${FUNCTION_NAME}
BUCKET_NAME=${BUCKET_NAME}
JOB_NAME=${JOB_NAME}
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    log_success "Environment configured for project: ${PROJECT_ID}"
    log_info "Deployment configuration saved to: ${CONFIG_FILE}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "aiplatform.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
        "run.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling API: ${api}"
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would enable API: ${api}"
        else
            if gcloud services enable "${api}" --quiet; then
                log_success "Enabled API: ${api}"
            else
                log_error "Failed to enable API: ${api}"
                exit 1
            fi
        fi
    done
    
    # Wait for APIs to be fully enabled
    if [[ "${DRY_RUN}" != "true" ]]; then
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    log_success "All required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: ${BUCKET_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create bucket: gs://${BUCKET_NAME}"
        return 0
    fi
    
    # Check if bucket already exists
    if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists"
        return 0
    fi
    
    # Create bucket with standard storage class and regional location
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        log_success "Created bucket: gs://${BUCKET_NAME}"
    else
        log_error "Failed to create bucket: gs://${BUCKET_NAME}"
        exit 1
    fi
    
    # Enable versioning for content history
    if gsutil versioning set on "gs://${BUCKET_NAME}"; then
        log_success "Enabled versioning on bucket"
    else
        log_warning "Failed to enable versioning on bucket"
    fi
    
    # Create directory structure
    echo "# Newsletter Content Directory" | gsutil cp - "gs://${BUCKET_NAME}/generated-content/README.txt"
    echo "# Content Templates Directory" | gsutil cp - "gs://${BUCKET_NAME}/templates/README.txt"
    
    log_success "Storage bucket configured successfully"
}

# Function to prepare function source code
prepare_function_code() {
    log_info "Preparing Cloud Function source code..."
    
    local temp_dir="/tmp/newsletter-function-${RANDOM_SUFFIX}"
    mkdir -p "${temp_dir}"
    
    # Create main.py
    cat > "${temp_dir}/main.py" << 'EOF'
import json
import os
from datetime import datetime
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel
import functions_framework

def initialize_services():
    """Initialize Google Cloud services"""
    project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
    bucket_name = os.environ.get('BUCKET_NAME')
    
    # Initialize Vertex AI
    vertexai.init(project=project_id, location="us-central1")
    
    # Initialize storage client
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    
    return bucket, project_id

def generate_newsletter_content(topic, template):
    """Generate newsletter content using Gemini"""
    try:
        model = GenerativeModel("gemini-1.5-flash")
        
        prompt = f"""
        Create newsletter content based on this template and topic:
        Topic: {topic}
        
        Template Requirements:
        - Subject Line: {template['subject_line'].replace('{topic}', topic)}
        - Introduction: {template['intro'].replace('{topic}', topic)}
        - Main Content: {template['main_content'].replace('{topic}', topic)}
        - Call to Action: {template['call_to_action'].replace('{topic}', topic)}
        
        Additional Guidelines:
        - Tone: {template['tone']}
        - Target Audience: {template['target_audience']}
        - Word Limit: {template['word_limit']} words
        
        Please provide the content in JSON format with keys: subject_line, intro, main_content, call_to_action
        """
        
        response = model.generate_content(prompt)
        return response.text
    except Exception as e:
        print(f"Error generating content: {str(e)}")
        raise

@functions_framework.http
def generate_newsletter(request):
    """HTTP Cloud Function to generate newsletter content"""
    try:
        # Initialize services
        bucket, project_id = initialize_services()
        
        # Get request data
        request_json = request.get_json(silent=True)
        topic = request_json.get('topic', 'Digital Marketing Trends') if request_json else 'Digital Marketing Trends'
        
        # Load template (in production, could load from Cloud Storage)
        template = {
            "subject_line": "Generate an engaging subject line about {topic}",
            "intro": "Write a brief introduction paragraph about {topic} in a professional yet friendly tone",
            "main_content": "Create 2-3 paragraphs of informative content about {topic}, including practical tips or insights",
            "call_to_action": "Write a compelling call-to-action related to {topic}",
            "tone": "professional, engaging, informative",
            "target_audience": "business professionals and marketing teams",
            "word_limit": 300
        }
        
        # Generate content
        generated_content = generate_newsletter_content(topic, template)
        
        # Create timestamp for filename
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"newsletter_{topic.replace(' ', '_').lower()}_{timestamp}.json"
        
        # Store result in Cloud Storage
        blob = bucket.blob(f"generated-content/{filename}")
        result_data = {
            "topic": topic,
            "generated_at": timestamp,
            "content": generated_content,
            "template_used": template,
            "project_id": project_id
        }
        blob.upload_from_string(json.dumps(result_data, indent=2))
        
        return {
            "status": "success",
            "message": f"Newsletter content generated for topic: {topic}",
            "filename": filename,
            "storage_path": f"gs://{bucket.name}/generated-content/{filename}",
            "timestamp": timestamp
        }, 200
        
    except Exception as e:
        error_msg = f"Error generating newsletter: {str(e)}"
        print(error_msg)
        return {"status": "error", "message": error_msg}, 500
EOF
    
    # Create requirements.txt
    cat > "${temp_dir}/requirements.txt" << 'EOF'
google-cloud-storage==2.18.0
google-cloud-aiplatform==1.102.0
functions-framework==3.8.1
vertexai==1.92.0
EOF
    
    # Store temp directory path for deployment
    FUNCTION_SOURCE_DIR="${temp_dir}"
    
    log_success "Function source code prepared in: ${temp_dir}"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying Cloud Function: ${FUNCTION_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would deploy function: ${FUNCTION_NAME}"
        return 0
    fi
    
    # Deploy function with comprehensive configuration
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python312 \
        --trigger-http \
        --source "${FUNCTION_SOURCE_DIR}" \
        --entry-point generate_newsletter \
        --memory 512MB \
        --timeout 300s \
        --max-instances 10 \
        --set-env-vars BUCKET_NAME="${BUCKET_NAME}" \
        --allow-unauthenticated \
        --region="${REGION}" \
        --quiet; then
        log_success "Cloud Function deployed successfully"
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    # Get function URL for scheduling
    FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(httpsTrigger.url)")
    
    if [[ -z "${FUNCTION_URL}" ]]; then
        log_error "Failed to retrieve function URL"
        exit 1
    fi
    
    # Update config file with function URL
    echo "FUNCTION_URL=${FUNCTION_URL}" >> "${CONFIG_FILE}"
    
    log_success "Function URL: ${FUNCTION_URL}"
}

# Function to create Cloud Scheduler job
create_scheduler_job() {
    log_info "Creating Cloud Scheduler job: ${JOB_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create scheduler job: ${JOB_NAME}"
        return 0
    fi
    
    # Create scheduler job for weekly newsletter generation
    local job_description="Weekly newsletter content generation using Gemini AI"
    local schedule="0 9 * * 1"  # Every Monday at 9:00 AM
    local message_body='{"topic":"Weekly Marketing Insights"}'
    
    if gcloud scheduler jobs create http "${JOB_NAME}" \
        --location="${REGION}" \
        --schedule="${schedule}" \
        --uri="${FUNCTION_URL}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body="${message_body}" \
        --description="${job_description}" \
        --time-zone="America/New_York" \
        --max-retry-attempts=3 \
        --max-retry-duration=600s \
        --quiet; then
        log_success "Scheduler job created successfully"
        log_info "Schedule: Every Monday at 9:00 AM (EST)"
    else
        log_error "Failed to create scheduler job"
        exit 1
    fi
}

# Function to test the deployment
test_deployment() {
    log_info "Testing the deployment..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would test deployment"
        return 0
    fi
    
    # Test function directly
    log_info "Testing Cloud Function directly..."
    local test_payload='{"topic":"Deployment Test"}'
    
    if curl -s -X POST "${FUNCTION_URL}" \
        -H "Content-Type: application/json" \
        -d "${test_payload}" > /tmp/test_response.json; then
        
        if jq -e '.status == "success"' /tmp/test_response.json > /dev/null; then
            log_success "Function test passed"
            local filename=$(jq -r '.filename' /tmp/test_response.json)
            log_info "Generated test content: ${filename}"
        else
            log_error "Function test failed"
            cat /tmp/test_response.json
            exit 1
        fi
    else
        log_error "Failed to test function"
        exit 1
    fi
    
    # Test scheduler job
    log_info "Testing scheduler job..."
    if gcloud scheduler jobs run "${JOB_NAME}" --location="${REGION}" --quiet; then
        log_success "Scheduler job test triggered successfully"
        log_info "Check Cloud Functions logs for execution details"
    else
        log_warning "Failed to trigger scheduler job test"
    fi
    
    # Wait for processing and check results
    log_info "Waiting for content generation..."
    sleep 15
    
    # List generated content
    log_info "Checking generated content..."
    if gsutil ls "gs://${BUCKET_NAME}/generated-content/" | head -5; then
        log_success "Content generation verified"
    else
        log_warning "No content found yet - this may be normal for initial deployment"
    fi
    
    # Clean up test files
    rm -f /tmp/test_response.json
}

# Function to display deployment summary
show_deployment_summary() {
    log_success "=== Deployment Summary ==="
    echo
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Cloud Function: ${FUNCTION_NAME}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo "Scheduler Job: ${JOB_NAME}"
    echo "Function URL: ${FUNCTION_URL:-'Not available'}"
    echo
    echo "Configuration saved to: ${CONFIG_FILE}"
    echo "Deployment log: ${LOG_FILE}"
    echo
    echo "Next steps:"
    echo "1. Monitor function execution in Cloud Console"
    echo "2. Check generated content in Cloud Storage"
    echo "3. Customize scheduler frequency if needed"
    echo "4. Review Cloud Functions logs for any issues"
    echo
    log_success "Deployment completed successfully!"
}

# Function to cleanup on error
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    
    # Only cleanup if not in dry-run mode
    if [[ "${DRY_RUN}" != "true" ]]; then
        # Remove function source directory
        if [[ -n "${FUNCTION_SOURCE_DIR:-}" ]] && [[ -d "${FUNCTION_SOURCE_DIR}" ]]; then
            rm -rf "${FUNCTION_SOURCE_DIR}"
        fi
        
        # Note: We don't automatically delete cloud resources on error
        # as user might want to investigate the issue
        log_info "Cloud resources left intact for investigation"
        log_info "Run the destroy script to clean up cloud resources"
    fi
    
    exit 1
}

# Main deployment function
main() {
    # Default values
    PROJECT_ID=""
    REGION="us-central1"
    SKIP_CONFIRMATION="false"
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
            -y|--yes)
                SKIP_CONFIRMATION="true"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN="true"
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
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "Project ID is required"
        usage
        exit 1
    fi
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Display banner
    echo -e "${BLUE}"
    echo "=============================================="
    echo "  Newsletter Content Generation Deployment"
    echo "  Gemini AI + Cloud Scheduler + Functions"
    echo "=============================================="
    echo -e "${NC}"
    
    # Show deployment configuration
    log_info "Deployment Configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Dry Run: ${DRY_RUN}"
    echo
    
    # Confirmation prompt
    if [[ "${SKIP_CONFIRMATION}" != "true" ]] && [[ "${DRY_RUN}" != "true" ]]; then
        echo -n "Do you want to proceed with deployment? (y/N): "
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    enable_apis
    create_storage_bucket
    prepare_function_code
    deploy_cloud_function
    create_scheduler_job
    test_deployment
    show_deployment_summary
    
    # Clean up temporary files
    if [[ -n "${FUNCTION_SOURCE_DIR:-}" ]] && [[ -d "${FUNCTION_SOURCE_DIR}" ]]; then
        rm -rf "${FUNCTION_SOURCE_DIR}"
    fi
    
    log_success "All deployment steps completed successfully!"
}

# Run main function with all arguments
main "$@"