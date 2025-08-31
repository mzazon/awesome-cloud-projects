#!/bin/bash

# Deploy script for Lorem Ipsum Generator Cloud Functions API
# This script deploys a serverless HTTP API using Google Cloud Functions
# and Cloud Storage for text caching

set -e  # Exit on any error

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud CLI."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check if required tools exist
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random strings."
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        log_error "python3 is required for JSON formatting and validation."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get current project if not set
    if [ -z "$PROJECT_ID" ]; then
        export PROJECT_ID=$(gcloud config get-value project)
        if [ -z "$PROJECT_ID" ]; then
            log_error "No GCP project configured. Please set PROJECT_ID or run 'gcloud config set project PROJECT_ID'"
            exit 1
        fi
    fi
    
    # Set default region if not specified
    if [ -z "$REGION" ]; then
        export REGION="us-central1"
    fi
    
    # Set default zone if not specified
    if [ -z "$ZONE" ]; then
        export ZONE="us-central1-a"
    fi
    
    # Generate unique suffix for resource names
    if [ -z "$RANDOM_SUFFIX" ]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    # Set resource names
    export BUCKET_NAME="lorem-cache-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="lorem-generator-${RANDOM_SUFFIX}"
    
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Zone: $ZONE"
    log_info "Random Suffix: $RANDOM_SUFFIX"
    log_info "Bucket Name: $BUCKET_NAME"
    log_info "Function Name: $FUNCTION_NAME"
}

# Function to configure gcloud settings
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "gcloud configuration updated"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log_success "$api enabled"
        else
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: $BUCKET_NAME"
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists"
        return 0
    fi
    
    # Create storage bucket with regional location
    if gsutil mb -p "${PROJECT_ID}" \
        -c STANDARD \
        -l "${REGION}" \
        "gs://${BUCKET_NAME}"; then
        log_success "Storage bucket created: $BUCKET_NAME"
    else
        log_error "Failed to create storage bucket"
        exit 1
    fi
    
    # Enable versioning for data protection
    if gsutil versioning set on "gs://${BUCKET_NAME}"; then
        log_success "Versioning enabled for bucket"
    else
        log_warning "Failed to enable versioning (non-critical)"
    fi
}

# Function to create function source code
create_function_source() {
    log_info "Creating function source code..."
    
    # Create temporary function directory
    export FUNCTION_DIR=$(mktemp -d)
    cd "$FUNCTION_DIR"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.8.*
google-cloud-storage==2.17.*
EOF
    
    # Create main.py with the lorem ipsum generator function
    cat > main.py << 'EOF'
import json
import random
import hashlib
from google.cloud import storage
import functions_framework

# Lorem ipsum word bank for text generation
LOREM_WORDS = [
    "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit",
    "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore",
    "magna", "aliqua", "enim", "ad", "minim", "veniam", "quis", "nostrud",
    "exercitation", "ullamco", "laboris", "nisi", "aliquip", "ex", "ea", "commodo",
    "consequat", "duis", "aute", "irure", "in", "reprehenderit", "voluptate",
    "velit", "esse", "cillum", "fugiat", "nulla", "pariatur", "excepteur", "sint",
    "occaecat", "cupidatat", "non", "proident", "sunt", "culpa", "qui", "officia",
    "deserunt", "mollit", "anim", "id", "est", "laborum"
]

def get_cached_text(cache_key, bucket_name):
    """Retrieve cached lorem ipsum text from Cloud Storage"""
    try:
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(f"cache/{cache_key}.txt")
        
        if blob.exists():
            return blob.download_as_text()
    except Exception as e:
        print(f"Cache retrieval error: {e}")
    return None

def cache_text(cache_key, text, bucket_name):
    """Store generated lorem ipsum text in Cloud Storage cache"""
    try:
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(f"cache/{cache_key}.txt")
        blob.upload_from_string(text)
    except Exception as e:
        print(f"Cache storage error: {e}")

def generate_lorem_text(paragraphs=3, words_per_paragraph=50):
    """Generate lorem ipsum text with specified parameters"""
    result_paragraphs = []
    
    for _ in range(paragraphs):
        # Generate words for this paragraph
        paragraph_words = []
        for i in range(words_per_paragraph):
            word = random.choice(LOREM_WORDS)
            # Capitalize first word of paragraph
            if i == 0:
                word = word.capitalize()
            paragraph_words.append(word)
        
        # Join words and add period at end
        paragraph = " ".join(paragraph_words) + "."
        result_paragraphs.append(paragraph)
    
    return "\n\n".join(result_paragraphs)

@functions_framework.http
def lorem_generator(request):
    """HTTP Cloud Function entry point for lorem ipsum generation"""
    # Set CORS headers for web browser access
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Content-Type': 'application/json'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Parse query parameters with defaults
        paragraphs = int(request.args.get('paragraphs', 3))
        words_per_paragraph = int(request.args.get('words', 50))
        
        # Validate parameters
        paragraphs = max(1, min(paragraphs, 10))  # Limit 1-10 paragraphs
        words_per_paragraph = max(10, min(words_per_paragraph, 200))  # Limit 10-200 words
        
        # Generate cache key from parameters
        cache_key = hashlib.md5(f"{paragraphs}-{words_per_paragraph}".encode()).hexdigest()
        bucket_name = "BUCKET_NAME_PLACEHOLDER"  # Will be replaced during deployment
        
        # Try to get cached text first
        cached_text = get_cached_text(cache_key, bucket_name)
        if cached_text:
            response_data = {
                "text": cached_text,
                "paragraphs": paragraphs,
                "words_per_paragraph": words_per_paragraph,
                "cached": True
            }
        else:
            # Generate new text
            lorem_text = generate_lorem_text(paragraphs, words_per_paragraph)
            
            # Cache the generated text
            cache_text(cache_key, lorem_text, bucket_name)
            
            response_data = {
                "text": lorem_text,
                "paragraphs": paragraphs,
                "words_per_paragraph": words_per_paragraph,
                "cached": False
            }
        
        return (json.dumps(response_data), 200, headers)
    
    except Exception as e:
        error_response = {
            "error": "Failed to generate lorem ipsum text",
            "message": str(e)
        }
        return (json.dumps(error_response), 500, headers)
EOF
    
    # Replace placeholder with actual bucket name
    sed -i "s/BUCKET_NAME_PLACEHOLDER/${BUCKET_NAME}/g" main.py
    
    log_success "Function source code created in $FUNCTION_DIR"
}

# Function to deploy Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function: $FUNCTION_NAME"
    
    # Deploy function with HTTP trigger
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime python312 \
        --trigger-http \
        --source . \
        --entry-point lorem_generator \
        --memory 256MB \
        --timeout 60s \
        --allow-unauthenticated \
        --region "${REGION}" \
        --quiet; then
        log_success "Cloud Function deployed: $FUNCTION_NAME"
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
}

# Function to get function URL and test
test_function() {
    log_info "Retrieving function URL and testing..."
    
    # Get the function URL
    export FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    
    if [ -z "$FUNCTION_URL" ]; then
        log_error "Failed to retrieve function URL"
        exit 1
    fi
    
    log_success "Function URL: $FUNCTION_URL"
    
    # Test basic functionality
    log_info "Testing function with basic parameters..."
    if curl -s "${FUNCTION_URL}?paragraphs=2&words=30" | python3 -m json.tool > /dev/null; then
        log_success "Function test passed"
    else
        log_warning "Function test failed, but deployment completed"
    fi
    
    # Save deployment info
    cat > deployment-info.txt << EOF
Deployment Information:
PROJECT_ID: $PROJECT_ID
REGION: $REGION
BUCKET_NAME: $BUCKET_NAME
FUNCTION_NAME: $FUNCTION_NAME
FUNCTION_URL: $FUNCTION_URL
RANDOM_SUFFIX: $RANDOM_SUFFIX
DEPLOYMENT_TIME: $(date)
EOF
    
    log_success "Deployment information saved to deployment-info.txt"
}

# Function to clean up temporary files
cleanup_temp() {
    if [ -n "$FUNCTION_DIR" ] && [ -d "$FUNCTION_DIR" ]; then
        cd /
        rm -rf "$FUNCTION_DIR"
        log_info "Temporary files cleaned up"
    fi
}

# Main deployment function
main() {
    log_info "Starting Lorem Ipsum Generator deployment..."
    
    # Set trap to cleanup on exit
    trap cleanup_temp EXIT
    
    check_prerequisites
    setup_environment
    configure_gcloud
    enable_apis
    create_storage_bucket
    create_function_source
    deploy_function
    test_function
    
    log_success "🎉 Deployment completed successfully!"
    echo ""
    echo "📝 Usage Examples:"
    echo "  curl '${FUNCTION_URL}?paragraphs=3&words=50'"
    echo "  curl '${FUNCTION_URL}?paragraphs=1&words=25'"
    echo ""
    echo "🔗 Function URL: ${FUNCTION_URL}"
    echo "💾 Storage Bucket: gs://${BUCKET_NAME}"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Run main function
main "$@"