#!/bin/bash

# AI Content Validation with Vertex AI and Functions - Deployment Script
# This script deploys the complete infrastructure for automated content validation
# using Vertex AI's safety scoring and Cloud Functions for serverless processing

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is not available. Please install openssl for random string generation."
    fi
    
    # Check if authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="content-validation-$(date +%s)"
        warning "PROJECT_ID not set. Generated: ${PROJECT_ID}"
    fi
    
    # Set default region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set bucket names
    export CONTENT_BUCKET="content-input-${RANDOM_SUFFIX}"
    export RESULTS_BUCKET="validation-results-${RANDOM_SUFFIX}"
    
    # Set function name
    export FUNCTION_NAME="content-validator"
    
    info "Environment configured:"
    info "  Project ID: ${PROJECT_ID}"
    info "  Region: ${REGION}"
    info "  Zone: ${ZONE}"
    info "  Content Bucket: ${CONTENT_BUCKET}"
    info "  Results Bucket: ${RESULTS_BUCKET}"
    info "  Function Name: ${FUNCTION_NAME}"
}

# Configure gcloud project
configure_gcloud() {
    info "Configuring gcloud project settings..."
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        warning "Project ${PROJECT_ID} does not exist."
        read -p "Do you want to create it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            info "Creating project ${PROJECT_ID}..."
            gcloud projects create "${PROJECT_ID}" --name="Content Validation Project" || \
                error_exit "Failed to create project ${PROJECT_ID}. You may need billing setup."
        else
            error_exit "Project ${PROJECT_ID} is required. Please create it or set an existing project."
        fi
    fi
    
    # Set project configuration
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"
    
    success "gcloud project configured"
}

# Enable required APIs
enable_apis() {
    info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
        "run.googleapis.com"
        "pubsub.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling ${api}..."
        if gcloud services enable "${api}" 2>/dev/null; then
            success "Enabled ${api}"
        else
            error_exit "Failed to enable ${api}"
        fi
    done
    
    # Wait for APIs to be fully enabled
    info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Create Cloud Storage buckets
create_storage_buckets() {
    info "Creating Cloud Storage buckets..."
    
    # Create content input bucket
    if gsutil ls -b "gs://${CONTENT_BUCKET}" &> /dev/null; then
        warning "Bucket ${CONTENT_BUCKET} already exists"
    else
        info "Creating content input bucket: ${CONTENT_BUCKET}"
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${CONTENT_BUCKET}" || error_exit "Failed to create content bucket"
        success "Created content input bucket"
    fi
    
    # Create results bucket
    if gsutil ls -b "gs://${RESULTS_BUCKET}" &> /dev/null; then
        warning "Bucket ${RESULTS_BUCKET} already exists"
    else
        info "Creating validation results bucket: ${RESULTS_BUCKET}"
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${RESULTS_BUCKET}" || error_exit "Failed to create results bucket"
        success "Created validation results bucket"
    fi
    
    # Set bucket permissions for Cloud Functions
    info "Setting bucket permissions..."
    
    # Get the Compute Engine default service account
    local compute_sa="${PROJECT_ID}-compute@developer.gserviceaccount.com"
    
    # Grant access to buckets (will be used by Cloud Function)
    gsutil iam ch "serviceAccount:${compute_sa}:objectViewer" "gs://${CONTENT_BUCKET}" || \
        warning "Could not set bucket permissions for ${CONTENT_BUCKET}"
    gsutil iam ch "serviceAccount:${compute_sa}:objectAdmin" "gs://${RESULTS_BUCKET}" || \
        warning "Could not set bucket permissions for ${RESULTS_BUCKET}"
    
    success "Storage buckets created and configured"
}

# Create function source code
create_function_code() {
    info "Creating Cloud Function source code..."
    
    local function_dir="${SCRIPT_DIR}/../function"
    mkdir -p "${function_dir}"
    
    # Create main.py
    cat > "${function_dir}/main.py" << 'EOF'
import functions_framework
import json
import logging
import os
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel, SafetySetting, HarmCategory, HarmBlockThreshold

# Initialize logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Vertex AI
PROJECT_ID = os.environ.get('GCP_PROJECT')
REGION = os.environ.get('FUNCTION_REGION', 'us-central1')
vertexai.init(project=PROJECT_ID, location=REGION)

@functions_framework.cloud_event
def validate_content(cloud_event):
    """Cloud Function triggered by Cloud Storage uploads for content validation."""
    
    try:
        # Extract file information from Cloud Event
        bucket_name = cloud_event.data['bucket']
        file_name = cloud_event.data['name']
        
        logger.info(f"Processing file: {file_name} from bucket: {bucket_name}")
        
        # Skip processing of result files
        if file_name.startswith('validation_results/'):
            logger.info(f"Skipping result file: {file_name}")
            return
        
        # Download content from Cloud Storage
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        try:
            content = blob.download_as_text()
        except Exception as e:
            logger.error(f"Failed to download {file_name} as text: {str(e)}")
            return
        
        # Perform content validation using Vertex AI
        validation_result = analyze_content_safety(content, file_name)
        
        # Store validation results
        results_bucket_name = os.environ.get('RESULTS_BUCKET')
        store_validation_results(validation_result, file_name, results_bucket_name)
        
        logger.info(f"Validation completed for {file_name}")
        
    except Exception as e:
        logger.error(f"Error processing {file_name}: {str(e)}")
        raise

def analyze_content_safety(content, file_name):
    """Analyze content using Vertex AI Gemini safety filters."""
    
    try:
        # Configure safety settings with custom thresholds
        safety_settings = [
            SafetySetting(
                category=HarmCategory.HARM_CATEGORY_HATE_SPEECH,
                threshold=HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE
            ),
            SafetySetting(
                category=HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
                threshold=HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE
            ),
            SafetySetting(
                category=HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
                threshold=HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE
            ),
            SafetySetting(
                category=HarmCategory.HARM_CATEGORY_HARASSMENT,
                threshold=HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE
            )
        ]
        
        # Initialize Gemini model with safety settings
        model = GenerativeModel(
            "gemini-1.5-flash",
            safety_settings=safety_settings
        )
        
        # Analyze content for safety
        prompt = f"Analyze this content for safety and quality: {content}"
        response = model.generate_content(prompt)
        
        # Extract safety ratings and scores
        safety_ratings = response.candidates[0].safety_ratings if response.candidates else []
        
        # Build validation result
        validation_result = {
            "file_name": file_name,
            "content_length": len(content),
            "safety_analysis": {
                "overall_safe": not any(rating.blocked for rating in safety_ratings),
                "safety_ratings": [
                    {
                        "category": rating.category.name,
                        "probability": rating.probability.name,
                        "blocked": rating.blocked
                    }
                    for rating in safety_ratings
                ]
            },
            "recommendation": "approved" if not any(rating.blocked for rating in safety_ratings) else "rejected",
            "generated_response": response.text if response.text else "Content blocked by safety filters"
        }
        
        return validation_result
        
    except Exception as e:
        logger.error(f"Error in safety analysis: {str(e)}")
        return {
            "file_name": file_name,
            "error": str(e),
            "recommendation": "review_required"
        }

def store_validation_results(validation_result, file_name, results_bucket_name):
    """Store validation results in Cloud Storage."""
    
    if not results_bucket_name:
        logger.warning("No results bucket configured")
        return
    
    try:
        storage_client = storage.Client()
        results_bucket = storage_client.bucket(results_bucket_name)
        
        # Create results file name
        results_file_name = f"validation_results/{file_name.replace('.txt', '_results.json')}"
        
        # Upload results
        results_blob = results_bucket.blob(results_file_name)
        results_blob.upload_from_string(
            json.dumps(validation_result, indent=2),
            content_type='application/json'
        )
        
        logger.info(f"Results stored: {results_file_name}")
        
    except Exception as e:
        logger.error(f"Error storing results: {str(e)}")
EOF
    
    # Create requirements.txt
    cat > "${function_dir}/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-storage==2.17.0
google-cloud-logging==3.11.0
google-cloud-aiplatform==1.70.0
vertexai==1.70.0
EOF
    
    success "Function source code created"
}

# Deploy Cloud Function
deploy_function() {
    info "Deploying Cloud Function..."
    
    local function_dir="${SCRIPT_DIR}/../function"
    
    # Check if function already exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
        warning "Function ${FUNCTION_NAME} already exists. Updating..."
    fi
    
    # Deploy function with Cloud Storage trigger
    info "Deploying function with Storage trigger..."
    cd "${function_dir}"
    
    gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python312 \
        --trigger-bucket "${CONTENT_BUCKET}" \
        --source . \
        --entry-point validate_content \
        --memory 512Mi \
        --timeout 60s \
        --set-env-vars "RESULTS_BUCKET=${RESULTS_BUCKET}" \
        --region "${REGION}" \
        --quiet || error_exit "Failed to deploy Cloud Function"
    
    cd "${SCRIPT_DIR}"
    
    # Wait for deployment to complete
    info "Waiting for function deployment to complete..."
    sleep 30
    
    # Verify function is active
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --format="value(status)" | grep -q "ACTIVE"; then
        success "Cloud Function deployed and active"
    else
        error_exit "Function deployment completed but status is not ACTIVE"
    fi
}

# Create test content
create_test_content() {
    info "Creating test content files..."
    
    local test_dir="${SCRIPT_DIR}/../test-content"
    mkdir -p "${test_dir}"
    
    # Create safe content sample
    cat > "${test_dir}/safe_content.txt" << 'EOF'
Welcome to our innovative technology platform! We're excited to share 
how our AI-powered solutions help businesses achieve their goals through 
intelligent automation and data-driven insights. Our commitment to 
excellence drives us to continuously improve and deliver value.
EOF
    
    # Create content requiring review
    cat > "${test_dir}/review_content.txt" << 'EOF'
This content contains some challenging language that might trigger 
safety filters due to its aggressive tone and potentially inflammatory 
statements about certain groups of people.
EOF
    
    # Create multilingual content
    cat > "${test_dir}/multilingual_content.txt" << 'EOF'
Hello! Bonjour! Hola! Our global platform supports multiple languages 
and cultures. We celebrate diversity and inclusion in all our content 
creation processes while maintaining safety and quality standards.
EOF
    
    success "Test content files created in ${test_dir}"
}

# Test deployment
test_deployment() {
    info "Testing deployment with sample content..."
    
    local test_dir="${SCRIPT_DIR}/../test-content"
    
    # Upload test content to trigger validation
    info "Uploading test content to trigger validation..."
    gsutil cp "${test_dir}"/safe_content.txt "gs://${CONTENT_BUCKET}/" || warning "Failed to upload safe_content.txt"
    gsutil cp "${test_dir}"/multilingual_content.txt "gs://${CONTENT_BUCKET}/" || warning "Failed to upload multilingual_content.txt"
    
    # Wait for processing
    info "Waiting for content validation processing..."
    sleep 45
    
    # Check for results
    info "Checking for validation results..."
    if gsutil ls "gs://${RESULTS_BUCKET}/validation_results/" &> /dev/null; then
        success "Validation results found - deployment test successful"
        gsutil ls "gs://${RESULTS_BUCKET}/validation_results/"
    else
        warning "No validation results found yet. Check function logs for details."
    fi
}

# Print deployment summary
print_summary() {
    echo
    echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo
    echo "Resource Summary:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Content Bucket: gs://${CONTENT_BUCKET}"
    echo "  Results Bucket: gs://${RESULTS_BUCKET}"
    echo "  Cloud Function: ${FUNCTION_NAME}"
    echo
    echo "Test the deployment:"
    echo "  1. Upload text files to gs://${CONTENT_BUCKET}"
    echo "  2. Check validation results in gs://${RESULTS_BUCKET}/validation_results/"
    echo "  3. Monitor function logs:"
    echo "     gcloud functions logs read ${FUNCTION_NAME} --region ${REGION}"
    echo
    echo "Next steps:"
    echo "  - Upload your own content files for validation"
    echo "  - Monitor function performance and costs"
    echo "  - Customize safety thresholds as needed"
    echo
    echo "Cleanup when done:"
    echo "  ./destroy.sh"
    echo
}

# Main deployment function
main() {
    echo -e "${BLUE}🚀 Starting AI Content Validation Deployment${NC}"
    echo "Log file: ${LOG_FILE}"
    echo
    
    log "Starting deployment at $(date)"
    
    check_prerequisites
    setup_environment
    configure_gcloud
    enable_apis
    create_storage_buckets
    create_function_code
    deploy_function
    create_test_content
    test_deployment
    print_summary
    
    log "Deployment completed successfully at $(date)"
}

# Run main function
main "$@"