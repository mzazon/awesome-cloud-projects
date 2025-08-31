#!/bin/bash

# Content Quality Scoring with Vertex AI and Functions - Deployment Script
# This script deploys the complete infrastructure for automated content quality scoring

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if user is authenticated
check_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        error "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check gcloud version
    local gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log "Google Cloud SDK version: $gcloud_version"
    
    # Check authentication
    check_auth
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    success "Prerequisites validated"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-content-quality-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        if command_exists openssl; then
            export RANDOM_SUFFIX=$(openssl rand -hex 3)
        else
            export RANDOM_SUFFIX=$(date +%s | tail -c 6)
        fi
    fi
    
    # Set additional environment variables
    export BUCKET_NAME="content-analysis-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="analyze-content-quality"
    export RESULTS_BUCKET="quality-results-${RANDOM_SUFFIX}"
    
    # Configure gcloud defaults
    gcloud config set project "${PROJECT_ID}" || true
    gcloud config set compute/region "${REGION}" || true
    gcloud config set compute/zone "${ZONE}" || true
    
    log "Environment configured:"
    log "  Project ID: ${PROJECT_ID}"
    log "  Region: ${REGION}"
    log "  Content Bucket: ${BUCKET_NAME}"
    log "  Results Bucket: ${RESULTS_BUCKET}"
    log "  Function Name: ${FUNCTION_NAME}"
}

# Function to create project
create_project() {
    log "Creating or verifying project..."
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log "Project ${PROJECT_ID} already exists"
    else
        log "Creating project ${PROJECT_ID}..."
        if ! gcloud projects create "${PROJECT_ID}" --name="Content Quality Scoring"; then
            error "Failed to create project. You may need billing enabled or organization permissions."
            exit 1
        fi
        success "Project created: ${PROJECT_ID}"
    fi
    
    # Set project as default
    gcloud config set project "${PROJECT_ID}"
}

# Function to enable APIs
enable_apis() {
    log "Enabling required APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        if ! gcloud services enable "$api"; then
            error "Failed to enable $api"
            exit 1
        fi
    done
    
    success "All APIs enabled"
    
    # Wait for API propagation
    log "Waiting for API propagation..."
    sleep 30
}

# Function to create storage buckets
create_storage_buckets() {
    log "Creating Cloud Storage buckets..."
    
    # Create content bucket
    log "Creating content bucket: ${BUCKET_NAME}"
    if ! gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        error "Failed to create content bucket"
        exit 1
    fi
    
    # Create results bucket
    log "Creating results bucket: ${RESULTS_BUCKET}"
    if ! gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${RESULTS_BUCKET}"; then
        error "Failed to create results bucket"
        exit 1
    fi
    
    # Enable versioning
    log "Enabling versioning on buckets..."
    gsutil versioning set on "gs://${BUCKET_NAME}"
    gsutil versioning set on "gs://${RESULTS_BUCKET}"
    
    success "Storage buckets created and configured"
}

# Function to create function source code
create_function_code() {
    log "Creating Cloud Function source code..."
    
    local function_dir="./content-quality-function"
    
    # Create function directory
    mkdir -p "$function_dir"
    cd "$function_dir"
    
    # Create main.py
    cat > main.py << 'EOF'
import functions_framework
import json
import time
import logging
import os
from google.cloud import storage
from google.cloud import aiplatform
from vertexai.generative_models import GenerativeModel

# Initialize logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Vertex AI
PROJECT_ID = os.environ.get("PROJECT_ID")
REGION = "us-central1"
RESULTS_BUCKET = os.environ.get("RESULTS_BUCKET")

aiplatform.init(project=PROJECT_ID, location=REGION)

@functions_framework.cloud_event
def analyze_content_quality(cloud_event):
    """Triggered by Cloud Storage upload - analyzes content quality."""
    
    try:
        # Extract file information from event
        data = cloud_event.data
        bucket_name = data["bucket"]
        file_name = data["name"]
        
        logger.info(f"Processing file: {file_name} from bucket: {bucket_name}")
        
        # Read content from Cloud Storage
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        # Download and decode content
        content_text = blob.download_as_text()
        
        # Analyze content quality using Vertex AI
        quality_scores = analyze_with_vertex_ai(content_text)
        
        # Store results in results bucket
        store_analysis_results(file_name, quality_scores)
        
        logger.info(f"Analysis complete for {file_name}")
        
    except Exception as e:
        logger.error(f"Error processing {file_name}: {str(e)}")
        raise

def analyze_with_vertex_ai(content):
    """Analyze content quality using Vertex AI Gemini."""
    
    # Create comprehensive quality analysis prompt
    prompt = f"""
    Analyze the following content for quality across multiple dimensions. 
    Provide scores (1-10) and specific feedback for each category:
    
    CONTENT TO ANALYZE:
    {content}
    
    Please evaluate and provide JSON output with the following structure:
    {{
        "overall_score": <1-10>,
        "readability": {{
            "score": <1-10>,
            "feedback": "specific feedback on readability"
        }},
        "engagement": {{
            "score": <1-10>,
            "feedback": "feedback on engagement potential"
        }},
        "clarity": {{
            "score": <1-10>,
            "feedback": "feedback on clarity and comprehension"
        }},
        "structure": {{
            "score": <1-10>,
            "feedback": "feedback on content organization"
        }},
        "tone": {{
            "score": <1-10>,
            "feedback": "feedback on tone appropriateness"
        }},
        "actionability": {{
            "score": <1-10>,
            "feedback": "feedback on actionable insights"
        }},
        "improvement_suggestions": [
            "specific suggestion 1",
            "specific suggestion 2",
            "specific suggestion 3"
        ]
    }}
    
    Focus on providing constructive, specific feedback that content creators can act upon.
    """
    
    try:
        # Initialize Gemini model
        model = GenerativeModel("gemini-1.5-flash")
        
        # Generate response with appropriate parameters
        response = model.generate_content(
            prompt,
            generation_config={
                "temperature": 0.2,
                "max_output_tokens": 2048,
                "top_p": 0.8,
                "top_k": 40
            }
        )
        
        # Parse JSON response
        quality_analysis = json.loads(response.text.strip())
        
        return quality_analysis
        
    except Exception as e:
        logger.error(f"Vertex AI analysis failed: {str(e)}")
        # Return default scores if analysis fails
        return {
            "overall_score": 5,
            "error": f"Analysis failed: {str(e)}",
            "readability": {"score": 5, "feedback": "Analysis unavailable"},
            "engagement": {"score": 5, "feedback": "Analysis unavailable"},
            "clarity": {"score": 5, "feedback": "Analysis unavailable"},
            "structure": {"score": 5, "feedback": "Analysis unavailable"},
            "tone": {"score": 5, "feedback": "Analysis unavailable"},
            "actionability": {"score": 5, "feedback": "Analysis unavailable"},
            "improvement_suggestions": ["Retry analysis when service is available"]
        }

def store_analysis_results(original_filename, analysis_results):
    """Store analysis results in Cloud Storage."""
    
    try:
        storage_client = storage.Client()
        results_bucket = storage_client.bucket(RESULTS_BUCKET)
        
        # Create results filename
        results_filename = f"analysis_{original_filename}_{int(time.time())}.json"
        
        # Prepare results data
        results_data = {
            "original_file": original_filename,
            "timestamp": time.time(),
            "analysis": analysis_results
        }
        
        # Upload results
        blob = results_bucket.blob(results_filename)
        blob.upload_from_string(
            json.dumps(results_data, indent=2),
            content_type='application/json'
        )
        
        logger.info(f"Results stored: {results_filename}")
        
    except Exception as e:
        logger.error(f"Failed to store results: {str(e)}")
        raise
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.8.2
google-cloud-storage==2.18.0
google-cloud-aiplatform==1.60.0
google-cloud-logging==3.11.0
EOF
    
    success "Function source code created"
    cd ..
}

# Function to deploy Cloud Function
deploy_function() {
    log "Deploying Cloud Function..."
    
    cd "./content-quality-function"
    
    # Deploy function with Cloud Storage trigger
    if ! gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python311 \
        --region "${REGION}" \
        --source . \
        --entry-point analyze_content_quality \
        --trigger-bucket "${BUCKET_NAME}" \
        --memory 512MiB \
        --timeout 540s \
        --max-instances 10 \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},RESULTS_BUCKET=${RESULTS_BUCKET}"; then
        error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    success "Function deployed: ${FUNCTION_NAME}"
    log "Trigger configured for bucket: ${BUCKET_NAME}"
    
    cd ..
}

# Function to create sample content
create_sample_content() {
    log "Creating sample content for testing..."
    
    mkdir -p sample-content
    
    # Create high-quality content sample
    cat > sample-content/high-quality-article.txt << 'EOF'
# Effective Remote Team Communication Strategies

Remote work has fundamentally transformed how teams collaborate and communicate. Success in distributed teams requires intentional communication practices that bridge physical distances and time zones.

## Key Communication Principles

**Clarity First**: Every message should have a clear purpose and actionable outcomes. Avoid ambiguous language that can lead to misinterpretation across different cultural contexts.

**Asynchronous by Default**: Design communication workflows that don't require immediate responses. This approach respects different working hours and allows for thoughtful, well-considered responses.

**Documentation Culture**: Create searchable, accessible records of decisions and discussions. This practice ensures knowledge preservation and enables team members to stay informed regardless of meeting attendance.

## Implementation Strategies

1. **Establish Communication Protocols**: Define which channels to use for different types of communication - urgent matters, project updates, casual conversation.

2. **Regular Check-ins**: Schedule consistent one-on-one and team meetings that focus on both work progress and team well-being.

3. **Use Visual Communication**: Leverage screen sharing, diagrams, and video when explaining complex concepts to reduce misunderstanding.

Remote communication excellence requires practice, patience, and continuous refinement based on team feedback and evolving needs.
EOF
    
    # Create medium-quality content sample
    cat > sample-content/medium-quality-post.txt << 'EOF'
Social Media Marketing Tips

Social media is important for business today. Here are some tips that can help your business grow online.

Post regularly - You should post content on a regular basis to keep your audience engaged. Try to post at least once a day.

Use hashtags - Hashtags help people find your content. Research popular hashtags in your industry and use them in your posts.

Engage with followers - Respond to comments and messages. This helps build relationships with your customers.

Share quality content - Don't just promote your products. Share useful information that your audience will find valuable.

Analyze your results - Look at your analytics to see what content performs best. Use this information to improve your strategy.

Social media marketing takes time and effort, but it can really help your business reach more customers and increase sales.
EOF
    
    # Create low-quality content sample
    cat > sample-content/low-quality-draft.txt << 'EOF'
productivity tips

here are some ways to be more productive at work:

- make lists
- dont procrastinate
- take breaks
- organize workspace
- minimize distractions

these tips will help you get more done. productivity is important for success in any job. try implementing these strategies and see if they work for you.
EOF
    
    success "Sample content created for testing"
}

# Function to test deployment
test_deployment() {
    log "Testing deployment with sample content..."
    
    # Upload sample content to trigger analysis
    log "Uploading sample content..."
    gsutil cp sample-content/high-quality-article.txt "gs://${BUCKET_NAME}/"
    gsutil cp sample-content/medium-quality-post.txt "gs://${BUCKET_NAME}/"
    gsutil cp sample-content/low-quality-draft.txt "gs://${BUCKET_NAME}/"
    
    success "Content uploaded and analysis triggered"
    
    # Wait for function execution
    log "Waiting for function execution (30 seconds)..."
    sleep 30
    
    # Check function logs
    log "Checking function execution logs..."
    gcloud functions logs read "${FUNCTION_NAME}" \
        --gen2 \
        --region "${REGION}" \
        --limit 10 || warn "Could not retrieve function logs"
    
    # Check for results
    log "Checking for analysis results..."
    if gsutil ls "gs://${RESULTS_BUCKET}/" 2>/dev/null | grep -q "analysis_"; then
        success "Analysis results found in bucket"
        gsutil ls "gs://${RESULTS_BUCKET}/"
    else
        warn "No analysis results found yet. Results may take a few minutes to appear."
    fi
}

# Function to display deployment information
display_deployment_info() {
    log "Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT INFORMATION ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Content Bucket: gs://${BUCKET_NAME}"
    echo "Results Bucket: gs://${RESULTS_BUCKET}"
    echo "Function Name: ${FUNCTION_NAME}"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Upload content files to: gs://${BUCKET_NAME}"
    echo "2. View analysis results in: gs://${RESULTS_BUCKET}"
    echo "3. Monitor function logs: gcloud functions logs read ${FUNCTION_NAME} --gen2 --region ${REGION}"
    echo "4. View function details: gcloud functions describe ${FUNCTION_NAME} --gen2 --region ${REGION}"
    echo
    echo "=== SAMPLE USAGE ==="
    echo "# Upload a text file for analysis"
    echo "echo 'Your content here' | gsutil cp - gs://${BUCKET_NAME}/my-content.txt"
    echo
    echo "# View analysis results"
    echo "gsutil ls gs://${RESULTS_BUCKET}/"
    echo "gsutil cp gs://${RESULTS_BUCKET}/analysis_my-content.txt_*.json - | jq ."
    echo
    success "Content Quality Scoring system is ready to use!"
}

# Function to save deployment state
save_deployment_state() {
    local state_file="./.deployment_state"
    cat > "$state_file" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
BUCKET_NAME=${BUCKET_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
RESULTS_BUCKET=${RESULTS_BUCKET}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    log "Deployment state saved to $state_file"
}

# Main deployment function
main() {
    log "Starting Content Quality Scoring deployment..."
    
    validate_prerequisites
    setup_environment
    create_project
    enable_apis
    create_storage_buckets
    create_function_code
    deploy_function
    create_sample_content
    test_deployment
    save_deployment_state
    display_deployment_info
}

# Error handling
trap 'error "Deployment failed at line $LINENO. Exit code: $?"' ERR

# Check for help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Content Quality Scoring Deployment Script"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID     - GCP Project ID (default: content-quality-\$(date +%s))"
    echo "  REGION         - GCP Region (default: us-central1)"
    echo "  ZONE           - GCP Zone (default: us-central1-a)"
    echo "  RANDOM_SUFFIX  - Random suffix for resource names (auto-generated)"
    echo
    echo "Examples:"
    echo "  # Deploy with default settings"
    echo "  $0"
    echo
    echo "  # Deploy with custom project ID"
    echo "  PROJECT_ID=my-content-project $0"
    echo
    echo "  # Deploy with custom region"
    echo "  REGION=us-west1 ZONE=us-west1-a $0"
    exit 0
fi

# Run main function
main "$@"