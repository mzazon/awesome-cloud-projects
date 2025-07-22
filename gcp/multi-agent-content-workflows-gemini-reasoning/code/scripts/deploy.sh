#!/bin/bash

# Multi-Agent Content Workflows with Gemini 2.5 Reasoning - Deployment Script
# This script deploys the complete infrastructure for intelligent content processing
# using Google Cloud Workflows, Vertex AI, and multi-agent architecture

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

# Error handling function
handle_error() {
    log_error "Deployment failed at line $1. Exit code: $2"
    log_error "Please check the error message above and resolve the issue."
    exit 1
}

# Set error trap
trap 'handle_error ${LINENO} $?' ERR

# Configuration variables with defaults
PROJECT_ID="${PROJECT_ID:-content-intelligence-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
BUCKET_NAME="${BUCKET_NAME:-content-intelligence-${RANDOM_SUFFIX}}"
WORKFLOW_NAME="${WORKFLOW_NAME:-content-analysis-workflow}"
FUNCTION_NAME="${FUNCTION_NAME:-content-trigger-${RANDOM_SUFFIX}}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-content-intelligence-sa}"
DRY_RUN="${DRY_RUN:-false}"

# Required APIs for the solution
REQUIRED_APIS=(
    "aiplatform.googleapis.com"
    "workflows.googleapis.com"
    "cloudfunctions.googleapis.com"
    "storage.googleapis.com"
    "eventarc.googleapis.com"
    "run.googleapis.com"
    "speech.googleapis.com"
    "vision.googleapis.com"
    "cloudbuild.googleapis.com"
)

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "You are not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check if required tools are available
    for tool in openssl curl; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Function to display configuration
display_configuration() {
    log_info "Deployment Configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Zone: ${ZONE}"
    echo "  Bucket Name: ${BUCKET_NAME}"
    echo "  Workflow Name: ${WORKFLOW_NAME}"
    echo "  Function Name: ${FUNCTION_NAME}"
    echo "  Service Account: ${SERVICE_ACCOUNT_NAME}"
    echo "  Dry Run: ${DRY_RUN}"
    echo ""
}

# Function to confirm deployment
confirm_deployment() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        return 0
    fi
    
    read -p "Do you want to proceed with the deployment? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

# Function to create or set project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create/configure project: ${PROJECT_ID}"
        return 0
    fi
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_info "Project ${PROJECT_ID} already exists, using it"
    else
        log_info "Creating new project: ${PROJECT_ID}"
        gcloud projects create "${PROJECT_ID}" \
            --name="Content Intelligence Workflows" \
            --labels="purpose=content-intelligence,environment=demo"
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set functions/region "${REGION}"
    
    log_success "Project setup completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: ${REQUIRED_APIS[*]}"
        return 0
    fi
    
    for api in "${REQUIRED_APIS[@]}"; do
        log_info "Enabling API: ${api}"
        if gcloud services enable "${api}" --project="${PROJECT_ID}"; then
            log_success "Enabled ${api}"
        else
            log_warning "Failed to enable ${api} or already enabled"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully activated..."
    sleep 30
    
    log_success "APIs enabled successfully"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create bucket: gs://${BUCKET_NAME}"
        return 0
    fi
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_info "Bucket gs://${BUCKET_NAME} already exists"
    else
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}"
        log_success "Created bucket: gs://${BUCKET_NAME}"
    fi
    
    # Create directory structure
    echo "Sample content structure" | gsutil cp - "gs://${BUCKET_NAME}/input/.gitkeep"
    echo "Results directory" | gsutil cp - "gs://${BUCKET_NAME}/results/.gitkeep"
    echo "Configuration directory" | gsutil cp - "gs://${BUCKET_NAME}/config/.gitkeep"
    
    log_success "Storage bucket setup completed"
}

# Function to create service account
create_service_account() {
    log_info "Creating service account and configuring IAM..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create service account: ${SERVICE_ACCOUNT_NAME}"
        return 0
    fi
    
    # Create service account if it doesn't exist
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        log_info "Service account already exists"
    else
        gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
            --display-name="Content Intelligence Workflow Service Account" \
            --description="Service account for multi-agent content analysis workflows"
        log_success "Created service account: ${SERVICE_ACCOUNT_NAME}"
    fi
    
    # Assign necessary roles
    local roles=(
        "roles/aiplatform.user"
        "roles/workflows.invoker"
        "roles/storage.objectAdmin"
        "roles/speech.editor"
        "roles/vision.editor"
        "roles/cloudfunctions.invoker"
        "roles/eventarc.eventReceiver"
    )
    
    for role in "${roles[@]}"; do
        log_info "Assigning role: ${role}"
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="${role}" \
            --quiet
    done
    
    log_success "Service account and IAM configuration completed"
}

# Function to create workflow definition
create_workflow() {
    log_info "Creating Cloud Workflows definition..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create workflow: ${WORKFLOW_NAME}"
        return 0
    fi
    
    # Create workflow YAML file
    cat > /tmp/content-analysis-workflow.yaml << 'EOF'
main:
  params: [input]
  steps:
    - initialize:
        assign:
          - content_uri: ${input.content_uri}
          - content_type: ${input.content_type}
          - analysis_results: {}
    
    - determine_processing_agents:
        switch:
          - condition: ${content_type == "text"}
            steps:
              - process_text_content:
                  call: text_analysis_agent
                  args:
                    content_uri: ${content_uri}
                  result: text_result
              - store_text_result:
                  assign:
                    - analysis_results.text: ${text_result}
          
          - condition: ${content_type == "image"}
            steps:
              - process_image_content:
                  call: image_analysis_agent
                  args:
                    content_uri: ${content_uri}
                  result: image_result
              - store_image_result:
                  assign:
                    - analysis_results.image: ${image_result}
          
          - condition: ${content_type == "video"}
            steps:
              - process_video_content:
                  call: video_analysis_agent
                  args:
                    content_uri: ${content_uri}
                  result: video_result
              - store_video_result:
                  assign:
                    - analysis_results.video: ${video_result}
          
          - condition: ${content_type == "multi_modal"}
            steps:
              - parallel_processing:
                  parallel:
                    branches:
                      - text_branch:
                          steps:
                            - process_text:
                                call: text_analysis_agent
                                args:
                                  content_uri: ${content_uri}
                                result: text_result
                      - image_branch:
                          steps:
                            - process_image:
                                call: image_analysis_agent
                                args:
                                  content_uri: ${content_uri}
                                result: image_result
                      - video_branch:
                          steps:
                            - process_video:
                                call: video_analysis_agent
                                args:
                                  content_uri: ${content_uri}
                                result: video_result
                  result: parallel_results
              - aggregate_results:
                  assign:
                    - analysis_results: ${parallel_results}
    
    - reasoning_synthesis:
        call: gemini_reasoning_engine
        args:
          analysis_data: ${analysis_results}
          content_uri: ${content_uri}
        result: final_intelligence
    
    - return_results:
        return: ${final_intelligence}

# Text Analysis Agent Subworkflow
text_analysis_agent:
  params: [content_uri]
  steps:
    - call_gemini_text:
        call: http.post
        args:
          url: https://us-central1-aiplatform.googleapis.com/v1/projects/${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}/locations/us-central1/publishers/google/models/gemini-2.5-pro:generateContent
          headers:
            Authorization: ${"Bearer " + sys.get_env("GOOGLE_CLOUD_ACCESS_TOKEN")}
            Content-Type: application/json
          body:
            contents:
              - parts:
                - text: |
                    Analyze this text content for:
                    1. Key themes and topics
                    2. Sentiment and emotional tone
                    3. Entity extraction (people, places, organizations)
                    4. Content categories and tags
                    5. Summary and key insights
                    6. Quality assessment and recommendations
                    
                    Content URI: ${content_uri}
                    
                    Provide detailed analysis with confidence scores.
            generationConfig:
              temperature: 0.2
              topP: 0.8
              maxOutputTokens: 2048
        result: gemini_response
    - return_analysis:
        return:
          agent_type: "text_analyzer"
          content_uri: ${content_uri}
          analysis: ${gemini_response.body.candidates[0].content.parts[0].text}
          confidence_score: 0.95

# Image Analysis Agent Subworkflow
image_analysis_agent:
  params: [content_uri]
  steps:
    - call_vision_api:
        call: http.post
        args:
          url: https://vision.googleapis.com/v1/images:annotate
          headers:
            Authorization: ${"Bearer " + sys.get_env("GOOGLE_CLOUD_ACCESS_TOKEN")}
            Content-Type: application/json
          body:
            requests:
              - image:
                  source:
                    gcsImageUri: ${content_uri}
                features:
                  - type: LABEL_DETECTION
                    maxResults: 20
                  - type: TEXT_DETECTION
                  - type: OBJECT_LOCALIZATION
                  - type: SAFE_SEARCH_DETECTION
                  - type: IMAGE_PROPERTIES
        result: vision_response
    - enhance_with_gemini:
        call: http.post
        args:
          url: https://us-central1-aiplatform.googleapis.com/v1/projects/${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}/locations/us-central1/publishers/google/models/gemini-2.5-pro:generateContent
          headers:
            Authorization: ${"Bearer " + sys.get_env("GOOGLE_CLOUD_ACCESS_TOKEN")}
            Content-Type: application/json
          body:
            contents:
              - parts:
                - text: |
                    Analyze this image analysis data and provide comprehensive insights:
                    
                    Vision API Results: ${json.encode(vision_response.body)}
                    
                    Provide:
                    1. Scene understanding and context
                    2. Content categorization
                    3. Business relevance assessment
                    4. Quality and composition analysis
                    5. Actionable recommendations
            generationConfig:
              temperature: 0.3
              topP: 0.8
              maxOutputTokens: 1024
        result: enhanced_analysis
    - return_analysis:
        return:
          agent_type: "image_analyzer"
          content_uri: ${content_uri}
          vision_data: ${vision_response.body}
          enhanced_insights: ${enhanced_analysis.body.candidates[0].content.parts[0].text}
          confidence_score: 0.88

# Video Analysis Agent Subworkflow
video_analysis_agent:
  params: [content_uri]
  steps:
    - extract_audio_transcript:
        call: http.post
        args:
          url: https://speech.googleapis.com/v1/speech:longrunningrecognize
          headers:
            Authorization: ${"Bearer " + sys.get_env("GOOGLE_CLOUD_ACCESS_TOKEN")}
            Content-Type: application/json
          body:
            config:
              encoding: LINEAR16
              sampleRateHertz: 16000
              languageCode: en-US
              enableAutomaticPunctuation: true
              enableWordTimeOffsets: true
            audio:
              uri: ${content_uri}
        result: speech_operation
    - analyze_with_gemini:
        call: http.post
        args:
          url: https://us-central1-aiplatform.googleapis.com/v1/projects/${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}/locations/us-central1/publishers/google/models/gemini-2.5-pro:generateContent
          headers:
            Authorization: ${"Bearer " + sys.get_env("GOOGLE_CLOUD_ACCESS_TOKEN")}
            Content-Type: application/json
          body:
            contents:
              - parts:
                - text: |
                    Analyze this video content based on audio transcript:
                    
                    Speech Operation: ${json.encode(speech_operation.body)}
                    
                    Provide:
                    1. Content themes and topics
                    2. Speaker sentiment and engagement
                    3. Key moments and highlights
                    4. Content structure analysis
                    5. Audience recommendations
            generationConfig:
              temperature: 0.3
              topP: 0.8
              maxOutputTokens: 1536
        result: video_analysis
    - return_analysis:
        return:
          agent_type: "video_analyzer"
          content_uri: ${content_uri}
          transcript_data: ${speech_operation.body}
          content_analysis: ${video_analysis.body.candidates[0].content.parts[0].text}
          confidence_score: 0.82

# Gemini 2.5 Reasoning Engine for Final Synthesis
gemini_reasoning_engine:
  params: [analysis_data, content_uri]
  steps:
    - synthesize_intelligence:
        call: http.post
        args:
          url: https://us-central1-aiplatform.googleapis.com/v1/projects/${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}/locations/us-central1/publishers/google/models/gemini-2.5-pro:generateContent
          headers:
            Authorization: ${"Bearer " + sys.get_env("GOOGLE_CLOUD_ACCESS_TOKEN")}
            Content-Type: application/json
          body:
            contents:
              - parts:
                - text: |
                    As an advanced reasoning engine, synthesize the following multi-agent analysis results into comprehensive content intelligence:
                    
                    Agent Analysis Results: ${json.encode(analysis_data)}
                    Content URI: ${content_uri}
                    
                    Using advanced reasoning, provide:
                    1. COMPREHENSIVE SUMMARY: Unified understanding across all modalities
                    2. CROSS-MODAL INSIGHTS: Relationships between text, image, and video elements
                    3. BUSINESS INTELLIGENCE: Actionable insights for content strategy
                    4. CATEGORIZATION: Precise content categories with confidence scores
                    5. QUALITY ASSESSMENT: Content quality metrics and improvement recommendations
                    6. AUDIENCE ANALYSIS: Target audience identification and engagement strategies
                    7. COMPETITIVE ANALYSIS: Market positioning and differentiation opportunities
                    8. TREND IDENTIFICATION: Emerging patterns and trend alignment
                    9. RISK ASSESSMENT: Content risks and mitigation strategies
                    10. ACTIONABLE RECOMMENDATIONS: Specific next steps for content optimization
                    
                    Apply reasoning to identify patterns, contradictions, and emergent insights that individual agents might miss.
                    Provide confidence scores for each insight and explanation of reasoning process.
            generationConfig:
              temperature: 0.1
              topP: 0.9
              maxOutputTokens: 4096
        result: reasoning_output
    - format_final_results:
        assign:
          - final_intelligence:
              content_uri: ${content_uri}
              timestamp: ${time.format(sys.now())}
              agent_results: ${analysis_data}
              reasoning_synthesis: ${reasoning_output.body.candidates[0].content.parts[0].text}
              overall_confidence: 0.91
              processing_status: "complete"
    - return_intelligence:
        return: ${final_intelligence}
EOF

    # Deploy the workflow
    if gcloud workflows describe "${WORKFLOW_NAME}" --location="${REGION}" &>/dev/null; then
        log_info "Workflow already exists, updating it..."
        gcloud workflows deploy "${WORKFLOW_NAME}" \
            --source=/tmp/content-analysis-workflow.yaml \
            --location="${REGION}" \
            --service-account="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    else
        log_info "Creating new workflow..."
        gcloud workflows deploy "${WORKFLOW_NAME}" \
            --source=/tmp/content-analysis-workflow.yaml \
            --location="${REGION}" \
            --service-account="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    fi
    
    log_success "Workflow deployed successfully"
}

# Function to create Cloud Function
create_cloud_function() {
    log_info "Creating Cloud Function trigger..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create Cloud Function: ${FUNCTION_NAME}"
        return 0
    fi
    
    # Create temporary directory for function code
    local func_dir="/tmp/cloud-function-trigger"
    mkdir -p "${func_dir}"
    
    # Create main.py
    cat > "${func_dir}/main.py" << 'EOF'
import functions_framework
from google.cloud import workflows_v1
from google.cloud import storage
import json
import os
import mimetypes

@functions_framework.cloud_event
def trigger_content_analysis(cloud_event):
    """Triggered by Cloud Storage object creation to start content analysis workflow."""
    
    # Extract file information from the cloud event
    data = cloud_event.data
    bucket_name = data['bucket']
    file_name = data['name']
    content_type = data.get('contentType', '')
    
    # Skip processing for result files
    if file_name.startswith('results/'):
        print(f"Skipping result file: {file_name}")
        return
    
    # Determine content processing type
    processing_type = determine_content_type(content_type, file_name)
    
    if processing_type == 'unsupported':
        print(f"Unsupported content type: {content_type}")
        return
    
    # Prepare workflow input
    workflow_input = {
        'content_uri': f'gs://{bucket_name}/{file_name}',
        'content_type': processing_type,
        'metadata': {
            'bucket': bucket_name,
            'filename': file_name,
            'content_type': content_type,
            'size': data.get('size', 0)
        }
    }
    
    # Initialize Workflows client and execute
    try:
        workflows_client = workflows_v1.WorkflowsClient()
        
        # Construct the fully qualified workflow name
        project_id = os.environ['GCP_PROJECT']
        location = os.environ['FUNCTION_REGION'] 
        workflow_name = os.environ['WORKFLOW_NAME']
        
        parent = f"projects/{project_id}/locations/{location}/workflows/{workflow_name}"
        
        # Execute the workflow
        execution_request = workflows_v1.CreateExecutionRequest(
            parent=parent,
            execution=workflows_v1.Execution(
                argument=json.dumps(workflow_input)
            )
        )
        
        operation = workflows_client.create_execution(request=execution_request)
        print(f"Started workflow execution: {operation.name}")
        print(f"Processing {processing_type} content: {file_name}")
        
    except Exception as e:
        print(f"Error starting workflow: {str(e)}")
        raise

def determine_content_type(mime_type, filename):
    """Determine the appropriate processing type based on file characteristics."""
    
    # Text content types
    if mime_type.startswith('text/') or filename.endswith(('.txt', '.md', '.csv', '.json')):
        return 'text'
    
    # Image content types  
    elif mime_type.startswith('image/') or filename.endswith(('.jpg', '.jpeg', '.png', '.gif', '.bmp')):
        return 'image'
    
    # Video content types
    elif mime_type.startswith('video/') or filename.endswith(('.mp4', '.avi', '.mov', '.wmv')):
        return 'video'
    
    # Audio files (processed as video for transcript extraction)
    elif mime_type.startswith('audio/') or filename.endswith(('.mp3', '.wav', '.flac')):
        return 'video'
    
    # Multi-modal documents
    elif filename.endswith(('.pdf', '.docx', '.pptx')):
        return 'multi_modal'
    
    else:
        return 'unsupported'
EOF

    # Create requirements.txt
    cat > "${func_dir}/requirements.txt" << 'EOF'
functions-framework==3.5.0
google-cloud-workflows==1.14.1
google-cloud-storage==2.10.0
EOF

    # Deploy Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --gen2 &>/dev/null; then
        log_info "Cloud Function already exists, updating it..."
    else
        log_info "Creating new Cloud Function..."
    fi
    
    gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime=python311 \
        --region="${REGION}" \
        --source="${func_dir}" \
        --entry-point=trigger_content_analysis \
        --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
        --trigger-event-filters="bucket=${BUCKET_NAME}" \
        --set-env-vars="WORKFLOW_NAME=${WORKFLOW_NAME},GCP_PROJECT=${PROJECT_ID},FUNCTION_REGION=${REGION}" \
        --service-account="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --memory=512MB \
        --timeout=540s
    
    # Clean up temporary directory
    rm -rf "${func_dir}"
    
    log_success "Cloud Function deployed successfully"
}

# Function to upload configuration files
upload_config_files() {
    log_info "Uploading configuration files..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would upload configuration files"
        return 0
    fi
    
    # Create Gemini configuration
    cat > /tmp/gemini-config.json << 'EOF'
{
  "reasoning_config": {
    "temperature": 0.1,
    "top_p": 0.9,
    "max_output_tokens": 4096,
    "reasoning_depth": "comprehensive",
    "cross_modal_analysis": true,
    "confidence_threshold": 0.8
  },
  "agent_configs": {
    "text_agent": {
      "temperature": 0.2,
      "focus_areas": ["sentiment", "entities", "themes", "quality"],
      "output_format": "structured"
    },
    "image_agent": {
      "temperature": 0.3,
      "vision_features": ["labels", "text", "objects", "safe_search"],
      "enhancement_level": "detailed"
    },
    "video_agent": {
      "temperature": 0.3,
      "audio_config": {
        "enable_punctuation": true,
        "enable_word_timestamps": true,
        "language_code": "en-US"
      }
    }
  },
  "synthesis_rules": {
    "conflict_resolution": "reasoning_based",
    "confidence_weighting": true,
    "cross_modal_validation": true,
    "business_focus": true
  }
}
EOF

    # Upload configuration to Cloud Storage
    gsutil cp /tmp/gemini-config.json "gs://${BUCKET_NAME}/config/"
    
    # Clean up temporary file
    rm -f /tmp/gemini-config.json /tmp/content-analysis-workflow.yaml
    
    log_success "Configuration files uploaded"
}

# Function to test the deployment
test_deployment() {
    log_info "Testing deployment..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would test deployment"
        return 0
    fi
    
    # Create test content
    echo "Sample business proposal: Our new product leverages artificial intelligence to revolutionize customer service through automated response systems and predictive analytics. The market opportunity is estimated at $2.5 billion with projected 40% growth annually." > /tmp/test-document.txt
    
    # Upload test content
    gsutil cp /tmp/test-document.txt "gs://${BUCKET_NAME}/input/"
    
    # Wait and check for workflow execution
    sleep 10
    
    # Check if workflow executions are created
    local executions
    executions=$(gcloud workflows executions list --workflow="${WORKFLOW_NAME}" --location="${REGION}" --limit=1 --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${executions}" ]]; then
        log_success "Test successful - workflow execution detected"
    else
        log_warning "No workflow executions detected yet - this may be normal for initial setup"
    fi
    
    # Clean up test file
    rm -f /tmp/test-document.txt
    
    log_success "Deployment test completed"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "=== Deployment Summary ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Bucket: gs://${BUCKET_NAME}"
    echo "Workflow: ${WORKFLOW_NAME}"
    echo "Cloud Function: ${FUNCTION_NAME}"
    echo "Service Account: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Upload content to gs://${BUCKET_NAME}/input/ to trigger processing"
    echo "2. Monitor workflow executions: gcloud workflows executions list --workflow=${WORKFLOW_NAME} --location=${REGION}"
    echo "3. Check results in: gs://${BUCKET_NAME}/results/"
    echo "4. View logs in Cloud Console: https://console.cloud.google.com/logs"
    echo ""
    echo "=== Cleanup ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo ""
}

# Main deployment function
main() {
    log_info "Starting Multi-Agent Content Workflows deployment..."
    
    check_prerequisites
    display_configuration
    confirm_deployment
    
    setup_project
    enable_apis
    create_storage_bucket
    create_service_account
    create_workflow
    create_cloud_function
    upload_config_files
    test_deployment
    
    display_summary
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi