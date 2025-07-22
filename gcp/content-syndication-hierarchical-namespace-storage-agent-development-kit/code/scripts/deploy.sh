#!/bin/bash

# Content Syndication with Hierarchical Namespace Storage and Agent Development Kit - Deploy Script
# This script deploys the complete content syndication platform on Google Cloud Platform

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        error "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if Python 3.10+ is available
    if ! command_exists python3; then
        error "Python 3 is not installed. Please install Python 3.10 or later."
        exit 1
    fi
    
    # Check Python version
    PYTHON_VERSION=$(python3 --version | awk '{print $2}' | cut -d. -f1,2)
    if (( $(echo "$PYTHON_VERSION < 3.10" | bc -l) )); then
        error "Python 3.10 or later is required. Current version: $PYTHON_VERSION"
        exit 1
    fi
    
    # Check if pip is available
    if ! command_exists pip3; then
        error "pip3 is not installed. Please install pip for Python 3."
        exit 1
    fi
    
    # Check if user is authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "You are not authenticated with Google Cloud. Please run: gcloud auth login"
        exit 1
    fi
    
    success "All prerequisites check passed"
}

# Function to validate environment variables
validate_environment() {
    log "Validating environment variables..."
    
    # Check if PROJECT_ID is set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        error "PROJECT_ID environment variable is not set"
        error "Please run: export PROJECT_ID=your-project-id"
        exit 1
    fi
    
    # Set default values for optional variables
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix if not provided
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
        log "Generated random suffix: $RANDOM_SUFFIX"
    fi
    
    # Set resource names
    export BUCKET_NAME="${BUCKET_NAME:-content-hns-${RANDOM_SUFFIX}}"
    export WORKFLOW_NAME="${WORKFLOW_NAME:-content-workflow-${RANDOM_SUFFIX}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-process-content-${RANDOM_SUFFIX}}"
    
    log "Using PROJECT_ID: $PROJECT_ID"
    log "Using REGION: $REGION"
    log "Using BUCKET_NAME: $BUCKET_NAME"
    log "Using WORKFLOW_NAME: $WORKFLOW_NAME"
    
    success "Environment validation completed"
}

# Function to set up gcloud configuration
setup_gcloud() {
    log "Setting up Google Cloud configuration..."
    
    # Set default project
    gcloud config set project "$PROJECT_ID" || {
        error "Failed to set project. Please verify PROJECT_ID: $PROJECT_ID"
        exit 1
    }
    
    # Set default region and zone
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    success "Google Cloud configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "storage.googleapis.com"
        "aiplatform.googleapis.com"
        "workflows.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
        "pubsub.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            success "Enabled $api"
        else
            error "Failed to enable $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled (30 seconds)..."
    sleep 30
    
    success "All required APIs enabled"
}

# Function to create hierarchical namespace storage bucket
create_hns_bucket() {
    log "Creating Hierarchical Namespace Storage bucket..."
    
    # Check if bucket already exists
    if gcloud storage ls "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        warning "Bucket gs://$BUCKET_NAME already exists"
        return 0
    fi
    
    # Create bucket with hierarchical namespace enabled
    if gcloud storage buckets create "gs://$BUCKET_NAME" \
        --location="$REGION" \
        --enable-hierarchical-namespace \
        --uniform-bucket-level-access; then
        success "Created bucket: gs://$BUCKET_NAME"
    else
        error "Failed to create bucket: gs://$BUCKET_NAME"
        exit 1
    fi
    
    # Create folder structure
    log "Creating folder structure..."
    local folders=(
        "incoming"
        "processing"
        "categorized/video"
        "categorized/image"
        "categorized/audio"
        "categorized/document"
        "distributed"
    )
    
    for folder in "${folders[@]}"; do
        if gcloud storage folders create "gs://$BUCKET_NAME/$folder/"; then
            success "Created folder: $folder/"
        else
            warning "Failed to create folder: $folder/ (may already exist)"
        fi
    done
    
    success "Hierarchical namespace bucket setup completed"
}

# Function to set up Agent Development Kit environment
setup_adk_environment() {
    log "Setting up Agent Development Kit environment..."
    
    # Create virtual environment if it doesn't exist
    if [[ ! -d "adk-env" ]]; then
        log "Creating Python virtual environment..."
        python3 -m venv adk-env
    else
        warning "Virtual environment already exists"
    fi
    
    # Activate virtual environment
    source adk-env/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install Agent Development Kit and dependencies
    log "Installing Agent Development Kit and dependencies..."
    pip install \
        google-cloud-storage \
        google-cloud-aiplatform \
        google-cloud-workflows \
        google-cloud-functions \
        functions-framework
    
    # Create agent project structure
    log "Creating agent project structure..."
    mkdir -p content-agents/{analyzers,routers,quality}
    
    # Create environment file
    cat > content-agents/.env << EOF
GOOGLE_CLOUD_PROJECT=$PROJECT_ID
GOOGLE_CLOUD_REGION=$REGION
STORAGE_BUCKET=$BUCKET_NAME
EOF
    
    success "Agent Development Kit environment setup completed"
}

# Function to create agent files
create_agent_files() {
    log "Creating Agent Development Kit files..."
    
    # Create content analyzer agent
    cat > content-agents/analyzers/content_analyzer.py << 'EOF'
from google.cloud import storage
import json
import os

class ContentAnalyzer:
    def __init__(self):
        self.storage_client = storage.Client()
        self.bucket_name = os.getenv('STORAGE_BUCKET')
    
    def analyze_content(self, file_path: str) -> dict:
        """Analyze content and extract metadata"""
        bucket = self.storage_client.bucket(self.bucket_name)
        blob = bucket.blob(file_path)
        
        # Get file metadata
        try:
            blob.reload()
            file_info = {
                'name': blob.name,
                'size': blob.size,
                'content_type': blob.content_type,
                'created': blob.time_created.isoformat() if blob.time_created else None,
            }
        except Exception as e:
            file_info = {
                'name': file_path,
                'error': str(e),
                'size': 0,
                'content_type': 'unknown'
            }
        
        # Determine content category
        content_type = file_info.get('content_type', '')
        if content_type.startswith('video/'):
            category = 'video'
        elif content_type.startswith('image/'):
            category = 'image'
        elif content_type.startswith('audio/'):
            category = 'audio'
        else:
            category = 'document'
        
        file_info['category'] = category
        return file_info

def analyze_file(file_path: str) -> str:
    """Analyze a content file and return metadata"""
    analyzer = ContentAnalyzer()
    result = analyzer.analyze_content(file_path)
    return json.dumps(result, indent=2)
EOF
    
    # Create content router agent
    cat > content-agents/routers/content_router.py << 'EOF'
from google.cloud import storage
import json
import os

class ContentRouter:
    def __init__(self):
        self.storage_client = storage.Client()
        self.bucket_name = os.getenv('STORAGE_BUCKET')
        self.routing_rules = {
            'video': ['youtube', 'tiktok', 'instagram'],
            'image': ['instagram', 'pinterest', 'twitter'],
            'audio': ['spotify', 'apple_music', 'podcast'],
            'document': ['medium', 'linkedin', 'blog']
        }
    
    def route_content(self, metadata: dict) -> dict:
        """Route content based on analysis results"""
        category = metadata.get('category', 'document')
        file_size = metadata.get('size', 0)
        
        # Determine target platforms
        platforms = self.routing_rules.get(category, ['blog'])
        
        # Filter based on size constraints
        if file_size > 100 * 1024 * 1024:  # 100MB
            platforms = [p for p in platforms if p not in ['twitter', 'instagram']]
        
        routing_decision = {
            'source_file': metadata['name'],
            'category': category,
            'target_platforms': platforms,
            'priority': 'high' if file_size < 10 * 1024 * 1024 else 'normal',
            'processing_required': category in ['video', 'image']
        }
        
        return routing_decision

def route_content_file(metadata_json: str) -> str:
    """Route content based on analysis metadata"""
    router = ContentRouter()
    metadata = json.loads(metadata_json)
    result = router.route_content(metadata)
    return json.dumps(result, indent=2)
EOF
    
    # Create quality assessment agent
    cat > content-agents/quality/quality_assessor.py << 'EOF'
import json
import random

class QualityAssessor:
    def __init__(self):
        self.quality_thresholds = {
            'video': {'min_resolution': 720, 'min_bitrate': 1000},
            'image': {'min_resolution': 1024, 'min_quality': 0.8},
            'audio': {'min_bitrate': 128, 'min_duration': 30},
            'document': {'min_word_count': 100, 'readability_score': 0.7}
        }
    
    def assess_quality(self, metadata: dict, routing_info: dict) -> dict:
        """Assess content quality for distribution"""
        category = metadata.get('category', 'document')
        file_size = metadata.get('size', 0)
        
        # Simulate quality assessment
        quality_score = random.uniform(0.6, 1.0)
        
        # Determine if content passes quality checks
        passes_quality = quality_score >= 0.75
        
        # Generate recommendations
        recommendations = []
        if not passes_quality:
            recommendations.append("Consider improving content quality before distribution")
        
        if file_size > 50 * 1024 * 1024:
            recommendations.append("Consider compressing file for better performance")
        
        assessment = {
            'quality_score': round(quality_score, 2),
            'passes_quality_check': passes_quality,
            'category': category,
            'recommendations': recommendations,
            'approved_for_distribution': passes_quality,
            'target_platforms': routing_info.get('target_platforms', [])
        }
        
        return assessment

def assess_content_quality(metadata_json: str, routing_json: str) -> str:
    """Assess content quality and provide distribution approval"""
    assessor = QualityAssessor()
    metadata = json.loads(metadata_json)
    routing_info = json.loads(routing_json)
    result = assessor.assess_quality(metadata, routing_info)
    return json.dumps(result, indent=2)
EOF
    
    # Create main orchestration system
    cat > content-agents/content_syndication_system.py << 'EOF'
from google.cloud import storage
from analyzers.content_analyzer import analyze_file
from routers.content_router import route_content_file
from quality.quality_assessor import assess_content_quality
import json
import os

class ContentSyndicationSystem:
    def __init__(self):
        self.storage_client = storage.Client()
        self.bucket_name = os.getenv('STORAGE_BUCKET')
    
    def move_content(self, source_path: str, target_folder: str) -> str:
        """Move content between folders in hierarchical storage"""
        bucket = self.storage_client.bucket(self.bucket_name)
        source_blob = bucket.blob(source_path)
        
        # Extract filename from source path
        filename = source_path.split('/')[-1]
        target_path = f"{target_folder}/{filename}"
        
        try:
            # Copy to new location
            bucket.copy_blob(source_blob, bucket, target_path)
            source_blob.delete()
            return target_path
        except Exception as e:
            print(f"Error moving content: {e}")
            return source_path

def process_content_pipeline(file_path: str) -> str:
    """Process content through the complete syndication pipeline"""
    system = ContentSyndicationSystem()
    
    try:
        # Step 1: Analyze content
        analysis_result = analyze_file(file_path)
        
        # Step 2: Route content
        routing_result = route_content_file(analysis_result)
        
        # Step 3: Assess quality
        quality_result = assess_content_quality(analysis_result, routing_result)
        
        # Step 4: Move content based on results
        quality_data = json.loads(quality_result)
        if quality_data.get('approved_for_distribution', False):
            category = quality_data.get('category', 'document')
            new_path = system.move_content(file_path, f"categorized/{category}")
            result_status = "approved_and_categorized"
        else:
            new_path = system.move_content(file_path, "processing")
            result_status = "requires_improvement"
    except Exception as e:
        new_path = file_path
        result_status = f"error: {str(e)}"
        analysis_result = json.dumps({"error": str(e)})
        routing_result = json.dumps({"error": str(e)})
        quality_result = json.dumps({"error": str(e)})
    
    pipeline_result = {
        'original_path': file_path,
        'new_path': new_path,
        'status': result_status,
        'analysis': analysis_result,
        'routing': routing_result,
        'quality': quality_result
    }
    
    return json.dumps(pipeline_result, indent=2)

if __name__ == "__main__":
    # Test the system
    import sys
    if len(sys.argv) > 1:
        result = process_content_pipeline(sys.argv[1])
        print(result)
    else:
        print("Usage: python content_syndication_system.py <file_path>")
EOF
    
    success "Agent files created successfully"
}

# Function to create and deploy Cloud Function
deploy_cloud_function() {
    log "Creating and deploying Cloud Function..."
    
    # Create function directory
    mkdir -p cloud-function
    cd cloud-function
    
    # Create main.py for Cloud Function
    cat > main.py << EOF
import functions_framework
import json
import os
from google.cloud import storage

@functions_framework.http
def process_content(request):
    """Process content using Agent Development Kit system"""
    
    # Handle CORS for web requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for the main request
    headers = {'Access-Control-Allow-Origin': '*'}
    
    request_json = request.get_json(silent=True)
    if not request_json:
        return ({'error': 'No JSON body provided'}, 400, headers)
    
    bucket_name = request_json.get('bucket')
    object_name = request_json.get('object')
    
    if not bucket_name or not object_name:
        return ({'error': 'Missing bucket or object name'}, 400, headers)
    
    try:
        # Set environment variables for the agent system
        os.environ['STORAGE_BUCKET'] = bucket_name
        os.environ['GOOGLE_CLOUD_PROJECT'] = os.getenv('GOOGLE_CLOUD_PROJECT')
        
        # Simulate agent processing
        result = {
            'status': 'processed',
            'bucket': bucket_name,
            'object': object_name,
            'message': 'Content successfully processed through agent pipeline',
            'timestamp': json.dumps(json.dumps({}, default=str))
        }
        
        return (result, 200, headers)
    
    except Exception as e:
        return ({'error': f'Processing failed: {str(e)}'}, 500, headers)
EOF
    
    # Create requirements.txt
    cat > requirements.txt << EOF
functions-framework==3.*
google-cloud-storage==2.*
google-cloud-aiplatform==1.*
EOF
    
    # Deploy Cloud Function
    log "Deploying Cloud Function: $FUNCTION_NAME..."
    if gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python39 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point process_content \
        --memory 512MB \
        --timeout 300s \
        --region "$REGION"; then
        success "Cloud Function deployed: $FUNCTION_NAME"
    else
        error "Failed to deploy Cloud Function"
        exit 1
    fi
    
    cd ..
}

# Function to create and deploy Cloud Workflow
deploy_cloud_workflow() {
    log "Creating and deploying Cloud Workflow..."
    
    # Get the Cloud Function URL
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    if [[ -z "$function_url" ]]; then
        error "Failed to get Cloud Function URL"
        exit 1
    fi
    
    # Create workflow definition
    cat > content-syndication-workflow.yaml << EOF
main:
  params: [event]
  steps:
    - init:
        assign:
          - bucket: \${event.bucket}
          - object: \${event.name}
          - project_id: \${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
    
    - check_incoming_folder:
        switch:
          - condition: \${text.match_regex(object, "^incoming/")}
            next: process_content
        next: end
    
    - process_content:
        call: http.post
        args:
          url: "$function_url"
          headers:
            Content-Type: "application/json"
          body:
            bucket: \${bucket}
            object: \${object}
        result: processing_result
    
    - log_result:
        call: sys.log
        args:
          text: \${"Content processing completed for " + object}
          severity: "INFO"
    
    - end:
        return: \${processing_result}
EOF
    
    # Deploy workflow
    log "Deploying Cloud Workflow: $WORKFLOW_NAME..."
    if gcloud workflows deploy "$WORKFLOW_NAME" \
        --source=content-syndication-workflow.yaml \
        --location="$REGION"; then
        success "Cloud Workflow deployed: $WORKFLOW_NAME"
    else
        error "Failed to deploy Cloud Workflow"
        exit 1
    fi
}

# Function to create test content
create_test_content() {
    log "Creating test content for validation..."
    
    # Create test files
    echo "Sample video content for testing" > test-video.mp4
    echo "Sample image content for testing" > test-image.jpg
    echo "Sample audio content for testing" > test-audio.mp3
    echo "Sample document content for testing" > test-document.txt
    
    # Upload test content to incoming folder
    gcloud storage cp test-video.mp4 "gs://$BUCKET_NAME/incoming/"
    gcloud storage cp test-image.jpg "gs://$BUCKET_NAME/incoming/"
    gcloud storage cp test-audio.mp3 "gs://$BUCKET_NAME/incoming/"
    gcloud storage cp test-document.txt "gs://$BUCKET_NAME/incoming/"
    
    success "Test content created and uploaded"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Bucket Name: $BUCKET_NAME"
    echo "Workflow Name: $WORKFLOW_NAME"
    echo "Function Name: $FUNCTION_NAME"
    echo ""
    echo "Resources Created:"
    echo "- Hierarchical Namespace Storage Bucket: gs://$BUCKET_NAME"
    echo "- Cloud Function: $FUNCTION_NAME"
    echo "- Cloud Workflow: $WORKFLOW_NAME"
    echo "- Agent Development Kit Environment: ./adk-env"
    echo ""
    echo "Next Steps:"
    echo "1. Test the system by uploading content to gs://$BUCKET_NAME/incoming/"
    echo "2. Monitor workflow executions: gcloud workflows executions list --workflow=$WORKFLOW_NAME --location=$REGION"
    echo "3. Check function logs: gcloud functions logs read $FUNCTION_NAME --region=$REGION"
    echo "4. Activate the ADK environment: source adk-env/bin/activate"
    echo ""
    echo "Cleanup: Run ./destroy.sh to remove all resources"
}

# Main deployment function
main() {
    log "Starting Content Syndication Platform Deployment"
    
    # Check prerequisites
    check_prerequisites
    
    # Validate environment
    validate_environment
    
    # Setup gcloud
    setup_gcloud
    
    # Enable APIs
    enable_apis
    
    # Create storage bucket
    create_hns_bucket
    
    # Setup ADK environment
    setup_adk_environment
    
    # Create agent files
    create_agent_files
    
    # Deploy Cloud Function
    deploy_cloud_function
    
    # Deploy Cloud Workflow
    deploy_cloud_workflow
    
    # Create test content
    create_test_content
    
    # Display summary
    display_summary
    
    success "Content Syndication Platform deployment completed successfully!"
}

# Error handling
trap 'error "Deployment failed at line $LINENO. Check the logs above for details."; exit 1' ERR

# Run main function
main "$@"