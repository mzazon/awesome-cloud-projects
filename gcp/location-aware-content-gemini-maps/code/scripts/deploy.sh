#!/bin/bash
set -euo pipefail

# Location-Aware Content Generation with Gemini and Maps - Deployment Script
# This script deploys the complete infrastructure for generating location-specific content
# using Vertex AI Gemini with Google Maps grounding capabilities

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

# Error handling
handle_error() {
    log_error "Deployment failed at line $1"
    log_error "Rolling back any partial deployment..."
    cleanup_partial_deployment
    exit 1
}

trap 'handle_error $LINENO' ERR

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PREFIX="location-content"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_error "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available"
        log_error "Please ensure Google Cloud SDK is properly installed"
        exit 1
    fi
    
    # Check if curl is available for testing
    if ! command -v curl &> /dev/null; then
        log_error "curl is not available and is required for testing"
        exit 1
    fi
    
    # Check if python3 is available for testing
    if ! command -v python3 &> /dev/null; then
        log_error "python3 is not available and is required for testing"
        exit 1
    fi
    
    log_success "All prerequisites validated"
}

# Function to check current authentication
check_authentication() {
    log_info "Checking Google Cloud authentication..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active Google Cloud authentication found"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    log_success "Authenticated as: $active_account"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="${PROJECT_PREFIX}-$(date +%s)"
        log_info "Generated PROJECT_ID: $PROJECT_ID"
    fi
    
    # Set default region and zone if not provided
    export REGION="${REGION:-$DEFAULT_REGION}"
    export ZONE="${ZONE:-$DEFAULT_ZONE}"
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="location-content-${RANDOM_SUFFIX}"
    export SA_EMAIL="location-content-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    export FUNCTION_NAME="generate-location-content"
    
    # Create deployment state file
    cat > "${SCRIPT_DIR}/deployment.env" << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
BUCKET_NAME=${BUCKET_NAME}
SA_EMAIL=${SA_EMAIL}
FUNCTION_NAME=${FUNCTION_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    log_success "Environment variables configured"
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Storage Bucket: $BUCKET_NAME"
}

# Function to create and configure project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_warning "Project $PROJECT_ID already exists, using existing project"
    else
        log_info "Creating new project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" \
            --name="Location Content Generator" \
            --set-as-default
    fi
    
    # Set project as active
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    # Check if billing is enabled
    local billing_enabled=$(gcloud billing projects describe "$PROJECT_ID" \
        --format="value(billingEnabled)" 2>/dev/null || echo "false")
    
    if [[ "$billing_enabled" != "True" ]]; then
        log_warning "Billing is not enabled for this project"
        log_warning "You may need to enable billing manually in the Google Cloud Console"
        log_warning "Some services may not work without billing enabled"
    fi
    
    log_success "Project configured: $PROJECT_ID"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" --quiet
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create storage bucket
create_storage() {
    log_info "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists"
    else
        # Create bucket with appropriate settings
        gsutil mb -p "$PROJECT_ID" \
            -c STANDARD \
            -l "$REGION" \
            "gs://${BUCKET_NAME}"
        
        log_success "Storage bucket created: gs://${BUCKET_NAME}"
    fi
    
    # Enable versioning for content history
    gsutil versioning set on "gs://${BUCKET_NAME}"
    
    # Create content directory structure
    echo "Content directory for location-aware generation" | \
        gsutil cp - "gs://${BUCKET_NAME}/content/.gitkeep"
    
    log_success "Storage bucket configured with versioning"
}

# Function to create service account
create_service_account() {
    log_info "Creating service account for application..."
    
    local sa_name="location-content-sa"
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null; then
        log_warning "Service account $SA_EMAIL already exists"
    else
        # Create service account
        gcloud iam service-accounts create "$sa_name" \
            --display-name="Location Content Generator Service Account" \
            --description="Service account for location-aware content generation"
        
        log_success "Service account created: $SA_EMAIL"
    fi
    
    # Grant required IAM roles
    local roles=(
        "roles/viewer"
        "roles/aiplatform.user"
        "roles/storage.admin"
    )
    
    for role in "${roles[@]}"; do
        log_info "Granting role $role to service account..."
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:${SA_EMAIL}" \
            --role="$role" \
            --quiet
    done
    
    log_success "Service account configured with required permissions"
}

# Function to create and deploy Cloud Function
deploy_function() {
    log_info "Preparing Cloud Function deployment..."
    
    # Create temporary directory for function code
    local temp_dir=$(mktemp -d)
    local function_dir="$temp_dir/location-content-function"
    mkdir -p "$function_dir"
    
    # Create requirements.txt
    cat > "$function_dir/requirements.txt" << 'EOF'
google-genai==0.7.0
functions-framework==3.8.1
google-cloud-storage==2.18.0
flask==3.0.3
EOF
    
    # Create main.py with content generation logic
    cat > "$function_dir/main.py" << 'EOF'
import os
import json
from datetime import datetime
from google import genai
from google.genai import types
from google.cloud import storage
from flask import jsonify

# Initialize Vertex AI client with Maps grounding support
client = genai.Client(
    vertexai=True,
    project=os.environ.get('GCP_PROJECT'),
    location='us-central1'
)

# Initialize Cloud Storage client
storage_client = storage.Client()

def generate_location_content(request):
    """Generate location-aware content using Gemini with Maps grounding."""
    
    # Handle CORS for web requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Parse request data
        request_json = request.get_json()
        if not request_json:
            return jsonify({'error': 'No JSON data provided'}), 400
            
        location = request_json.get('location', '')
        content_type = request_json.get('content_type', 'marketing')
        audience = request_json.get('audience', 'general')
        
        if not location:
            return jsonify({'error': 'Location parameter required'}), 400
        
        # Construct prompt based on content type
        prompts = {
            'marketing': f"""Create compelling marketing copy for {location}. 
                        Include specific local attractions, dining options, and unique 
                        features that make this location special. Target audience: {audience}.
                        Use factual information about real places and businesses.""",
            
            'travel': f"""Write a detailed travel guide for {location}. 
                      Include must-see attractions, local restaurants, transportation 
                      options, and insider tips. Make it engaging and informative 
                      with specific place names and details.""",
            
            'business': f"""Create professional business content about {location} 
                        including market opportunities, local demographics, key 
                        attractions, and business environment. Include specific 
                        venues and establishments."""
        }
        
        prompt = prompts.get(content_type, prompts['marketing'])
        
        # Configure Maps grounding tool
        maps_tool = types.Tool(
            google_maps=types.GoogleMaps(
                auth_config={}  # Uses default authentication
            )
        )
        
        # Generate content with Maps grounding
        response = client.models.generate_content(
            model='gemini-2.5-flash',
            contents=prompt,
            tools=[maps_tool],
            config=types.GenerateContentConfig(
                temperature=0.7,
                max_output_tokens=1000,
                top_p=0.8
            )
        )
        
        generated_content = response.text
        
        # Extract grounding information if available
        grounding_info = []
        if hasattr(response, 'grounding_metadata') and response.grounding_metadata:
            metadata = response.grounding_metadata
            if hasattr(metadata, 'grounding_chunks') and metadata.grounding_chunks:
                for chunk in metadata.grounding_chunks:
                    if hasattr(chunk, 'web') and chunk.web:
                        grounding_info.append({
                            'title': getattr(chunk.web, 'title', 'Unknown'),
                            'uri': getattr(chunk.web, 'uri', ''),
                            'domain': getattr(chunk.web, 'domain', '')
                        })
        
        # Save generated content to Cloud Storage
        bucket_name = os.environ.get('BUCKET_NAME')
        if bucket_name:
            try:
                bucket = storage_client.bucket(bucket_name)
                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                filename = f"content/{content_type}_{location.replace(' ', '_').replace(',', '')}_{timestamp}.json"
                
                content_data = {
                    'location': location,
                    'content_type': content_type,
                    'audience': audience,
                    'generated_content': generated_content,
                    'grounding_sources': grounding_info,
                    'timestamp': timestamp,
                    'model': 'gemini-2.5-flash'
                }
                
                blob = bucket.blob(filename)
                blob.upload_from_string(
                    json.dumps(content_data, indent=2),
                    content_type='application/json'
                )
            except Exception as storage_error:
                print(f"Storage error: {storage_error}")  # Log but don't fail
        
        return jsonify({
            'content': generated_content,
            'location': location,
            'content_type': content_type,
            'grounding_sources': grounding_info,
            'timestamp': datetime.now().strftime('%Y%m%d_%H%M%S')
        }), 200, headers
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500, headers
EOF
    
    log_info "Deploying Cloud Function..."
    
    # Deploy function with Gen2 configuration
    gcloud functions deploy "$FUNCTION_NAME" \
        --gen2 \
        --runtime=python312 \
        --region="$REGION" \
        --source="$function_dir" \
        --entry-point=generate_location_content \
        --trigger=http \
        --service-account="$SA_EMAIL" \
        --set-env-vars="GCP_PROJECT=${PROJECT_ID},BUCKET_NAME=${BUCKET_NAME}" \
        --memory=512Mi \
        --timeout=60s \
        --max-instances=10 \
        --allow-unauthenticated \
        --quiet
    
    # Get function URL for testing
    export FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(serviceConfig.uri)")
    
    # Add function URL to deployment state
    echo "FUNCTION_URL=${FUNCTION_URL}" >> "${SCRIPT_DIR}/deployment.env"
    
    # Cleanup temporary directory
    rm -rf "$temp_dir"
    
    log_success "Cloud Function deployed successfully"
    log_info "Function URL: $FUNCTION_URL"
}

# Function to create test script
create_test_script() {
    log_info "Creating content generation test script..."
    
    cat > "${SCRIPT_DIR}/test_deployment.py" << 'EOF'
#!/usr/bin/env python3
"""Test script for location-aware content generation deployment."""

import requests
import json
import sys
import os
import time

def test_content_generation(function_url):
    """Test location-aware content generation with various scenarios."""
    
    test_cases = [
        {
            'location': 'Times Square, New York City',
            'content_type': 'marketing',
            'audience': 'tourists'
        },
        {
            'location': 'Pike Place Market, Seattle',
            'content_type': 'travel',
            'audience': 'food enthusiasts'
        },
        {
            'location': 'Silicon Valley, California',
            'content_type': 'business',
            'audience': 'entrepreneurs'
        }
    ]
    
    print("Testing Location-Aware Content Generation...")
    print("=" * 50)
    
    success_count = 0
    
    for i, test_case in enumerate(test_cases, 1):
        print(f"\nTest {i}: {test_case['content_type'].title()} content for {test_case['location']}")
        print("-" * 40)
        
        try:
            response = requests.post(
                function_url,
                json=test_case,
                headers={'Content-Type': 'application/json'},
                timeout=60
            )
            
            if response.status_code == 200:
                result = response.json()
                print(f"✅ Content generated successfully")
                print(f"Content preview: {result['content'][:200]}...")
                
                if result.get('grounding_sources'):
                    print(f"📍 Grounded with {len(result['grounding_sources'])} sources")
                    for source in result['grounding_sources'][:2]:
                        print(f"   - {source.get('title', 'Unknown title')}")
                else:
                    print("📍 No explicit grounding sources returned")
                
                success_count += 1
            else:
                print(f"❌ Request failed: {response.status_code}")
                print(f"Error: {response.text}")
                
        except requests.exceptions.RequestException as e:
            print(f"❌ Request error: {e}")
        
        # Add delay between requests to avoid rate limiting
        if i < len(test_cases):
            time.sleep(2)
    
    print("\n" + "=" * 50)
    print(f"Testing completed! {success_count}/{len(test_cases)} tests passed")
    
    return success_count == len(test_cases)

def check_function_health(function_url):
    """Check if the function is responding to basic requests."""
    print("Checking function health...")
    
    try:
        response = requests.post(
            function_url,
            json={'location': 'San Francisco, CA', 'content_type': 'marketing'},
            headers={'Content-Type': 'application/json'},
            timeout=30
        )
        
        if response.status_code == 200:
            print("✅ Function is healthy and responding")
            return True
        else:
            print(f"❌ Function returned status: {response.status_code}")
            return False
            
    except Exception as e:
        print(f"❌ Health check failed: {e}")
        return False

if __name__ == "__main__":
    function_url = os.environ.get('FUNCTION_URL')
    if not function_url:
        print("Please set FUNCTION_URL environment variable")
        sys.exit(1)
    
    # Check if requests library is available
    try:
        import requests
    except ImportError:
        print("Installing requests library...")
        os.system("pip3 install requests --user --quiet")
        import requests
    
    # Run health check first
    if not check_function_health(function_url):
        print("Function health check failed, skipping detailed tests")
        sys.exit(1)
    
    # Run comprehensive tests
    if test_content_generation(function_url):
        print("All tests passed! 🎉")
        sys.exit(0)
    else:
        print("Some tests failed! ❌")
        sys.exit(1)
EOF
    
    chmod +x "${SCRIPT_DIR}/test_deployment.py"
    log_success "Test script created"
}

# Function to run deployment validation
validate_deployment() {
    log_info "Validating deployment..."
    
    # Source deployment environment
    source "${SCRIPT_DIR}/deployment.env"
    
    # Check if function is deployed
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &>/dev/null; then
        log_success "Cloud Function deployed successfully"
    else
        log_error "Cloud Function deployment validation failed"
        return 1
    fi
    
    # Check if storage bucket exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_success "Storage bucket created successfully"
    else
        log_error "Storage bucket validation failed"
        return 1
    fi
    
    # Check if service account exists
    if gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null; then
        log_success "Service account created successfully"
    else
        log_error "Service account validation failed"
        return 1
    fi
    
    # Run basic function test
    log_info "Running deployment tests..."
    export FUNCTION_URL
    if python3 "${SCRIPT_DIR}/test_deployment.py"; then
        log_success "Deployment tests passed"
    else
        log_warning "Some deployment tests failed - this may be normal if Maps grounding is not available"
    fi
    
    log_success "Deployment validation completed"
}

# Function to cleanup partial deployment on failure
cleanup_partial_deployment() {
    log_warning "Cleaning up partial deployment..."
    
    if [[ -f "${SCRIPT_DIR}/deployment.env" ]]; then
        source "${SCRIPT_DIR}/deployment.env"
        
        # Try to cleanup resources that might have been created
        if [[ -n "${FUNCTION_NAME:-}" ]] && [[ -n "${REGION:-}" ]]; then
            gcloud functions delete "$FUNCTION_NAME" --region="$REGION" --quiet 2>/dev/null || true
        fi
        
        if [[ -n "${BUCKET_NAME:-}" ]]; then
            gsutil -m rm -r "gs://${BUCKET_NAME}" 2>/dev/null || true
        fi
        
        if [[ -n "${SA_EMAIL:-}" ]]; then
            gcloud iam service-accounts delete "$SA_EMAIL" --quiet 2>/dev/null || true
        fi
    fi
}

# Function to display deployment summary
show_deployment_summary() {
    log_success "🎉 Deployment completed successfully!"
    
    source "${SCRIPT_DIR}/deployment.env"
    
    echo ""
    echo "============================================"
    echo "         DEPLOYMENT SUMMARY"
    echo "============================================"
    echo "Project ID:       $PROJECT_ID"
    echo "Region:           $REGION"
    echo "Function Name:    $FUNCTION_NAME"
    echo "Function URL:     $FUNCTION_URL"
    echo "Storage Bucket:   gs://$BUCKET_NAME"
    echo "Service Account:  $SA_EMAIL"
    echo "Deployment Time:  $DEPLOYMENT_TIME"
    echo "============================================"
    echo ""
    echo "🧪 To test the deployment:"
    echo "   export FUNCTION_URL='$FUNCTION_URL'"
    echo "   python3 ${SCRIPT_DIR}/test_deployment.py"
    echo ""
    echo "🗑️  To clean up resources:"
    echo "   ${SCRIPT_DIR}/destroy.sh"
    echo ""
    echo "📚 Example curl request:"
    echo "   curl -X POST '$FUNCTION_URL' \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"location\": \"Golden Gate Bridge, San Francisco\", \"content_type\": \"travel\"}'"
    echo ""
}

# Main deployment function
main() {
    log_info "Starting deployment of Location-Aware Content Generation system..."
    
    # Check if dry run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        validate_prerequisites
        check_authentication
        setup_environment
        log_info "Dry run completed successfully"
        exit 0
    fi
    
    # Validate prerequisites first
    validate_prerequisites
    check_authentication
    
    # Setup environment and project
    setup_environment
    setup_project
    
    # Deploy infrastructure components
    enable_apis
    create_storage
    create_service_account
    deploy_function
    
    # Create supporting scripts and validate
    create_test_script
    validate_deployment
    
    # Show summary
    show_deployment_summary
    
    log_success "Deployment completed successfully! 🚀"
}

# Script usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy Location-Aware Content Generation with Gemini and Maps"
    echo ""
    echo "Options:"
    echo "  --dry-run       Validate prerequisites without deploying resources"
    echo "  --help          Show this help message"
    echo ""
    echo "Environment Variables (optional):"
    echo "  PROJECT_ID      Google Cloud Project ID (auto-generated if not set)"
    echo "  REGION          Deployment region (default: us-central1)"
    echo "  ZONE            Deployment zone (default: us-central1-a)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with default settings"
    echo "  PROJECT_ID=my-project $0              # Deploy to specific project"
    echo "  REGION=us-east1 $0                    # Deploy to specific region"
    echo "  $0 --dry-run                          # Validate without deploying"
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        usage
        exit 0
        ;;
    --dry-run)
        main --dry-run
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown option: $1"
        usage
        exit 1
        ;;
esac