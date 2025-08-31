#!/bin/bash

# Conversational AI Training Data Generation - Deployment Script
# This script deploys Gemini-powered conversation generation infrastructure on GCP
# including Cloud Storage, Cloud Functions, and monitoring components

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration variables with defaults
DEFAULT_PROJECT_PREFIX="conv-ai-training"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Function to log messages with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

# Function to log errors
log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $*" | tee -a "${ERROR_LOG}" >&2
}

# Function to print colored output
print_status() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Function to print section headers
print_header() {
    echo ""
    print_status "${BLUE}" "============================================"
    print_status "${BLUE}" "$*"
    print_status "${BLUE}" "============================================"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check required CLI tools
    if ! command_exists gcloud; then
        missing_tools+=("gcloud CLI")
    fi
    
    if ! command_exists gsutil; then
        missing_tools+=("gsutil (Google Cloud Storage CLI)")
    fi
    
    if ! command_exists curl; then
        missing_tools+=("curl")
    fi
    
    if ! command_exists jq; then
        missing_tools+=("jq (JSON processor)")
    fi
    
    if ! command_exists openssl; then
        missing_tools+=("openssl")
    fi
    
    # Report missing tools
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools:"
        for tool in "${missing_tools[@]}"; do
            log_error "  - ${tool}"
        done
        print_status "${RED}" "Please install missing tools and retry."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" >/dev/null 2>&1; then
        log_error "gcloud is not authenticated"
        print_status "${RED}" "Please run 'gcloud auth login' and retry."
        exit 1
    fi
    
    print_status "${GREEN}" "✅ All prerequisites satisfied"
}

# Function to prompt for user input with default
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    
    read -p "${prompt} [${default}]: " input
    if [ -z "${input}" ]; then
        eval "${varname}='${default}'"
    else
        eval "${varname}='${input}'"
    fi
}

# Function to generate unique resource names
generate_unique_suffix() {
    openssl rand -hex 3
}

# Function to set up environment variables
setup_environment() {
    print_header "Environment Configuration"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(generate_unique_suffix)
    log "Generated random suffix: ${RANDOM_SUFFIX}"
    
    # Prompt for configuration or use defaults
    if [ "${INTERACTIVE:-true}" = "true" ]; then
        prompt_with_default "Enter project prefix" "${DEFAULT_PROJECT_PREFIX}" "PROJECT_PREFIX"
        prompt_with_default "Enter GCP region" "${DEFAULT_REGION}" "REGION"
        prompt_with_default "Enter GCP zone" "${DEFAULT_ZONE}" "ZONE"
    else
        PROJECT_PREFIX="${PROJECT_PREFIX:-${DEFAULT_PROJECT_PREFIX}}"
        REGION="${REGION:-${DEFAULT_REGION}}"
        ZONE="${ZONE:-${DEFAULT_ZONE}}"
    fi
    
    # Set derived variables
    export PROJECT_ID="${PROJECT_PREFIX}-$(date +%s)"
    export REGION
    export ZONE
    export BUCKET_NAME="training-data-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="conversation-generator-${RANDOM_SUFFIX}"
    export PROCESSOR_NAME="data-processor-${RANDOM_SUFFIX}"
    
    # Log configuration
    log "Configuration:"
    log "  Project ID: ${PROJECT_ID}"
    log "  Region: ${REGION}"
    log "  Zone: ${ZONE}"
    log "  Bucket Name: ${BUCKET_NAME}"
    log "  Generator Function: ${FUNCTION_NAME}"
    log "  Processor Function: ${PROCESSOR_NAME}"
    
    print_status "${GREEN}" "✅ Environment configured"
}

# Function to create and configure GCP project
setup_project() {
    print_header "Setting Up GCP Project"
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log "Project ${PROJECT_ID} already exists"
    else
        log "Creating new project: ${PROJECT_ID}"
        if ! gcloud projects create "${PROJECT_ID}" --name="Conversational AI Training"; then
            log_error "Failed to create project ${PROJECT_ID}"
            exit 1
        fi
    fi
    
    # Set active project and region
    log "Configuring gcloud settings"
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    # Check billing account (informational)
    if ! gcloud billing accounts list --format="value(name)" >/dev/null 2>&1; then
        print_status "${YELLOW}" "⚠️ No billing accounts found. You may need to enable billing manually."
    else
        log "Billing accounts available - manual billing setup may be required"
    fi
    
    print_status "${GREEN}" "✅ Project setup complete"
}

# Function to enable required APIs
enable_apis() {
    print_header "Enabling Required APIs"
    
    local apis=(
        "compute.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    log "Enabling APIs: ${apis[*]}"
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}"
        if ! gcloud services enable "${api}"; then
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully available
    log "Waiting for APIs to be fully available..."
    sleep 30
    
    print_status "${GREEN}" "✅ All APIs enabled successfully"
}

# Function to create Cloud Storage bucket
create_storage() {
    print_header "Creating Cloud Storage Infrastructure"
    
    log "Creating bucket: ${BUCKET_NAME}"
    if ! gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        log_error "Failed to create bucket ${BUCKET_NAME}"
        exit 1
    fi
    
    log "Enabling versioning on bucket"
    gsutil versioning set on "gs://${BUCKET_NAME}"
    
    log "Creating folder structure"
    echo "" | gsutil cp - "gs://${BUCKET_NAME}/raw-conversations/.keep"
    echo "" | gsutil cp - "gs://${BUCKET_NAME}/processed-conversations/.keep"
    echo "" | gsutil cp - "gs://${BUCKET_NAME}/formatted-training/.keep"
    echo "" | gsutil cp - "gs://${BUCKET_NAME}/templates/.keep"
    
    print_status "${GREEN}" "✅ Storage infrastructure created"
}

# Function to upload conversation templates
upload_templates() {
    print_header "Uploading Conversation Templates"
    
    local template_file="${SCRIPT_DIR}/conversation_templates.json"
    
    log "Creating conversation templates"
    cat > "${template_file}" << 'EOF'
{
  "templates": [
    {
      "scenario": "customer_support",
      "context": "Technical support for a software application",
      "user_intents": ["bug_report", "feature_request", "account_issue"],
      "conversation_length": "3-5 exchanges",
      "tone": "professional, helpful"
    },
    {
      "scenario": "e_commerce",
      "context": "Online shopping assistance and product inquiries",
      "user_intents": ["product_search", "order_status", "return_request"],
      "conversation_length": "2-4 exchanges",
      "tone": "friendly, sales-oriented"
    },
    {
      "scenario": "healthcare",
      "context": "General health information and appointment scheduling",
      "user_intents": ["symptom_inquiry", "appointment_booking", "medication_info"],
      "conversation_length": "4-6 exchanges",
      "tone": "empathetic, professional"
    }
  ]
}
EOF
    
    log "Uploading templates to Cloud Storage"
    if ! gsutil cp "${template_file}" "gs://${BUCKET_NAME}/templates/"; then
        log_error "Failed to upload conversation templates"
        exit 1
    fi
    
    rm -f "${template_file}"
    print_status "${GREEN}" "✅ Conversation templates uploaded"
}

# Function to deploy Cloud Functions
deploy_functions() {
    print_header "Deploying Cloud Functions"
    
    local temp_dir="${SCRIPT_DIR}/temp_functions"
    mkdir -p "${temp_dir}"
    
    # Create conversation generator function
    log "Creating conversation generator function"
    local generator_dir="${temp_dir}/conversation-generator"
    mkdir -p "${generator_dir}"
    
    # Copy function code from terraform templates
    if [ -f "${PROJECT_ROOT}/code/terraform/function_templates/generator_main.py.tpl" ]; then
        # Remove template placeholders and copy
        sed 's/\${bucket_name}/'"${BUCKET_NAME}"'/g' \
            "${PROJECT_ROOT}/code/terraform/function_templates/generator_main.py.tpl" \
            > "${generator_dir}/main.py"
        
        cp "${PROJECT_ROOT}/code/terraform/function_templates/generator_requirements.txt" \
           "${generator_dir}/requirements.txt"
    else
        # Fallback to inline function code
        cat > "${generator_dir}/main.py" << 'EOF'
import json
import os
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel
import logging
import uuid
from typing import Dict, List
import random
import functions_framework

# Initialize logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def generate_conversations(request):
    """Cloud Function to generate conversational training data using Gemini."""
    
    try:
        # Set CORS headers for browser compatibility
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
        }
        
        # Handle preflight request
        if request.method == 'OPTIONS':
            return ('', 204, headers)
            
        # Initialize Vertex AI
        project_id = os.getenv('GCP_PROJECT', os.getenv('GOOGLE_CLOUD_PROJECT'))
        region = os.getenv('FUNCTION_REGION', 'us-central1')
        vertexai.init(project=project_id, location=region)
        
        # Initialize storage client
        storage_client = storage.Client()
        bucket_name = os.getenv('BUCKET_NAME')
        bucket = storage_client.bucket(bucket_name)
        
        # Load conversation templates
        template_blob = bucket.blob('templates/conversation_templates.json')
        templates = json.loads(template_blob.download_as_text())
        
        # Initialize Gemini model
        model = GenerativeModel("gemini-1.5-flash-001")
        
        # Parse request parameters
        request_json = request.get_json(silent=True) or {}
        num_conversations = request_json.get('num_conversations', 10)
        scenario = request_json.get('scenario', 'customer_support')
        
        # Find matching template
        template = next((t for t in templates['templates'] 
                        if t['scenario'] == scenario), templates['templates'][0])
        
        conversations = []
        
        for i in range(num_conversations):
            # Generate conversation prompt
            intent = random.choice(template['user_intents'])
            prompt = f"""
            Generate a realistic conversation between a user and an AI assistant for the following scenario:
            
            Context: {template['context']}
            User Intent: {intent}
            Conversation Length: {template['conversation_length']}
            Tone: {template['tone']}
            
            Format the conversation as a JSON object with the following structure:
            {{
                "conversation_id": "unique_id",
                "scenario": "{scenario}",
                "intent": "{intent}",
                "messages": [
                    {{"role": "user", "content": "user message"}},
                    {{"role": "assistant", "content": "assistant response"}},
                    ...
                ]
            }}
            
            Make the conversation natural, diverse, and realistic. Vary the language, 
            specific details, and conversation flow while maintaining the core intent and tone.
            """
            
            # Generate conversation using Gemini
            response = model.generate_content(
                prompt,
                generation_config={
                    "temperature": 0.8,
                    "top_p": 0.9,
                    "max_output_tokens": 1024
                }
            )
            
            # Parse and store conversation
            try:
                # Clean response text and extract JSON
                response_text = response.text.strip()
                if response_text.startswith('```json'):
                    response_text = response_text[7:]
                if response_text.endswith('```'):
                    response_text = response_text[:-3]
                    
                conversation = json.loads(response_text.strip())
                conversation['conversation_id'] = str(uuid.uuid4())
                conversation['generated_timestamp'] = str(uuid.uuid1().time)
                conversations.append(conversation)
                
                logger.info(f"Generated conversation {i+1}/{num_conversations}")
                
            except json.JSONDecodeError as e:
                logger.warning(f"Failed to parse conversation {i+1}: {e}, skipping...")
                continue
        
        # Save conversations to Cloud Storage
        output_file = f"raw-conversations/{scenario}_{uuid.uuid4()}.json"
        blob = bucket.blob(output_file)
        blob.upload_from_string(
            json.dumps({"conversations": conversations}, indent=2),
            content_type='application/json'
        )
        
        result = {
            'status': 'success',
            'conversations_generated': len(conversations),
            'output_file': f"gs://{bucket_name}/{output_file}",
            'scenario': scenario
        }
        
        return (json.dumps(result), 200, headers)
        
    except Exception as e:
        logger.error(f"Error generating conversations: {str(e)}")
        error_result = {'status': 'error', 'message': str(e)}
        return (json.dumps(error_result), 500, headers)
EOF

        cat > "${generator_dir}/requirements.txt" << 'EOF'
google-cloud-storage==2.18.0
google-cloud-aiplatform==1.60.0
vertexai==1.60.0
functions-framework==3.8.1
EOF
    fi
    
    # Deploy generator function
    log "Deploying conversation generator function"
    (
        cd "${generator_dir}"
        if ! gcloud functions deploy "${FUNCTION_NAME}" \
            --runtime python312 \
            --trigger-http \
            --allow-unauthenticated \
            --source . \
            --entry-point generate_conversations \
            --memory 1024MB \
            --timeout 540s \
            --set-env-vars "BUCKET_NAME=${BUCKET_NAME}"; then
            log_error "Failed to deploy conversation generator function"
            exit 1
        fi
    )
    
    # Create data processor function
    log "Creating data processor function"
    local processor_dir="${temp_dir}/data-processor"
    mkdir -p "${processor_dir}"
    
    # Copy processor code if available, otherwise use inline
    if [ -f "${PROJECT_ROOT}/code/terraform/function_templates/processor_main.py" ]; then
        cp "${PROJECT_ROOT}/code/terraform/function_templates/processor_main.py" \
           "${processor_dir}/main.py"
        cp "${PROJECT_ROOT}/code/terraform/function_templates/processor_requirements.txt" \
           "${processor_dir}/requirements.txt"
    else
        # Fallback to inline processor code (truncated for brevity)
        cat > "${processor_dir}/main.py" << 'EOF'
import json
from google.cloud import storage
import pandas as pd
from typing import List, Dict
import logging
import functions_framework

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def process_conversations(request):
    """Process raw conversations into training-ready formats."""
    
    try:
        # Set CORS headers
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
        }
        
        if request.method == 'OPTIONS':
            return ('', 204, headers)
            
        storage_client = storage.Client()
        request_json = request.get_json(silent=True) or {}
        bucket_name = request_json.get('bucket_name')
        
        if not bucket_name:
            return (json.dumps({'status': 'error', 'message': 'bucket_name required'}), 400, headers)
            
        bucket = storage_client.bucket(bucket_name)
        
        # List all raw conversation files
        raw_blobs = list(bucket.list_blobs(prefix='raw-conversations/'))
        
        all_conversations = []
        training_pairs = []
        
        # Process each file
        for blob in raw_blobs:
            if blob.name.endswith('.json') and not blob.name.endswith('.keep'):
                try:
                    content = json.loads(blob.download_as_text())
                    conversations = content.get('conversations', [])
                    
                    for conv in conversations:
                        all_conversations.append(conv)
                        
                        # Create training pairs from conversation messages
                        messages = conv.get('messages', [])
                        conversation_history = []
                        
                        for i, message in enumerate(messages):
                            if message['role'] == 'user':
                                # Find corresponding assistant response
                                if i + 1 < len(messages) and messages[i + 1]['role'] == 'assistant':
                                    training_pairs.append({
                                        'conversation_id': conv['conversation_id'],
                                        'scenario': conv['scenario'],
                                        'intent': conv['intent'],
                                        'conversation_history': conversation_history.copy(),
                                        'user_input': message['content'],
                                        'assistant_response': messages[i + 1]['content'],
                                        'turn_number': len(conversation_history) // 2 + 1
                                    })
                            
                            conversation_history.append({
                                'role': message['role'],
                                'content': message['content']
                            })
                except Exception as e:
                    logger.warning(f"Failed to process {blob.name}: {e}")
                    continue
        
        # Create different output formats
        formats = {
            'jsonl': create_jsonl_format(training_pairs),
            'csv': create_csv_format(training_pairs)
        }
        
        # Save processed data in multiple formats
        for format_name, format_data in formats.items():
            blob_name = f"formatted-training/training_data.{format_name}"
            blob = bucket.blob(blob_name)
            blob.upload_from_string(format_data)
        
        # Create summary statistics
        stats = {
            'total_conversations': len(all_conversations),
            'total_training_pairs': len(training_pairs),
            'scenarios': list(set(conv['scenario'] for conv in all_conversations)),
            'intents': list(set(conv['intent'] for conv in all_conversations))
        }
        
        # Save statistics
        stats_blob = bucket.blob('processed-conversations/processing_stats.json')
        stats_blob.upload_from_string(json.dumps(stats, indent=2))
        
        result = {
            'status': 'success',
            'processed_conversations': len(all_conversations),
            'training_pairs_created': len(training_pairs),
            'output_formats': list(formats.keys()),
            'statistics': stats
        }
        
        return (json.dumps(result), 200, headers)
        
    except Exception as e:
        logger.error(f"Processing error: {str(e)}")
        error_result = {'status': 'error', 'message': str(e)}
        return (json.dumps(error_result), 500, headers)

def create_jsonl_format(training_pairs: List[Dict]) -> str:
    """Create JSONL format for training."""
    lines = []
    for pair in training_pairs:
        jsonl_record = {
            'messages': pair['conversation_history'] + [
                {'role': 'user', 'content': pair['user_input']},
                {'role': 'assistant', 'content': pair['assistant_response']}
            ],
            'metadata': {
                'scenario': pair['scenario'],
                'intent': pair['intent'],
                'turn_number': pair['turn_number']
            }
        }
        lines.append(json.dumps(jsonl_record))
    return '\n'.join(lines)

def create_csv_format(training_pairs: List[Dict]) -> str:
    """Create CSV format for training."""
    df_data = []
    for pair in training_pairs:
        history_text = ' '.join([f"{msg['role']}: {msg['content']}" 
                               for msg in pair['conversation_history']])
        df_data.append({
            'conversation_id': pair['conversation_id'],
            'scenario': pair['scenario'],
            'intent': pair['intent'],
            'conversation_history': history_text,
            'user_input': pair['user_input'],
            'assistant_response': pair['assistant_response'],
            'turn_number': pair['turn_number']
        })
    
    df = pd.DataFrame(df_data)
    return df.to_csv(index=False)
EOF

        cat > "${processor_dir}/requirements.txt" << 'EOF'
google-cloud-storage==2.18.0
pandas==2.2.0
functions-framework==3.8.1
EOF
    fi
    
    # Deploy processor function
    log "Deploying data processor function"
    (
        cd "${processor_dir}"
        if ! gcloud functions deploy "${PROCESSOR_NAME}" \
            --runtime python312 \
            --trigger-http \
            --allow-unauthenticated \
            --source . \
            --entry-point process_conversations \
            --memory 1024MB \
            --timeout 540s; then
            log_error "Failed to deploy data processor function"
            exit 1
        fi
    )
    
    # Clean up temporary directory
    rm -rf "${temp_dir}"
    
    print_status "${GREEN}" "✅ Cloud Functions deployed successfully"
}

# Function to set up monitoring and logging
setup_monitoring() {
    print_header "Setting Up Monitoring and Logging"
    
    log "Creating log-based metrics for conversation generation"
    
    # Create success metric
    if ! gcloud logging metrics create conversation_generation_success \
        --description="Successful conversation generation events" \
        --log-filter="resource.type=\"cloud_function\" 
                     resource.labels.function_name=\"${FUNCTION_NAME}\"
                     jsonPayload.status=\"success\"" 2>/dev/null; then
        log "Success metric already exists or creation failed"
    fi
    
    # Create error metric
    if ! gcloud logging metrics create conversation_generation_errors \
        --description="Failed conversation generation events" \
        --log-filter="resource.type=\"cloud_function\" 
                     resource.labels.function_name=\"${FUNCTION_NAME}\"
                     severity=\"ERROR\"" 2>/dev/null; then
        log "Error metric already exists or creation failed"
    fi
    
    print_status "${GREEN}" "✅ Monitoring and logging configured"
}

# Function to test the deployment
test_deployment() {
    print_header "Testing Deployment"
    
    log "Getting Cloud Function URLs"
    FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
        --format="value(httpsTrigger.url)" 2>/dev/null || echo "")
    PROCESSOR_URL=$(gcloud functions describe "${PROCESSOR_NAME}" \
        --format="value(httpsTrigger.url)" 2>/dev/null || echo "")
    
    if [ -z "${FUNCTION_URL}" ] || [ -z "${PROCESSOR_URL}" ]; then
        log_error "Failed to get function URLs"
        return 1
    fi
    
    log "Generator Function URL: ${FUNCTION_URL}"
    log "Processor Function URL: ${PROCESSOR_URL}"
    
    # Test conversation generation
    log "Testing conversation generation"
    local test_response
    test_response=$(curl -s -X POST "${FUNCTION_URL}" \
        -H "Content-Type: application/json" \
        -d '{"num_conversations": 3, "scenario": "customer_support"}' || echo '{"error": "request failed"}')
    
    if echo "${test_response}" | jq -e '.status == "success"' >/dev/null 2>&1; then
        log "✅ Conversation generation test successful"
    else
        log "⚠️ Conversation generation test may have failed: ${test_response}"
    fi
    
    # Test data processing
    log "Testing data processing"
    local processor_response
    processor_response=$(curl -s -X POST "${PROCESSOR_URL}" \
        -H "Content-Type: application/json" \
        -d "{\"bucket_name\": \"${BUCKET_NAME}\"}" || echo '{"error": "request failed"}')
    
    if echo "${processor_response}" | jq -e '.status == "success"' >/dev/null 2>&1; then
        log "✅ Data processing test successful"
    else
        log "⚠️ Data processing test may have failed: ${processor_response}"
    fi
    
    print_status "${GREEN}" "✅ Deployment testing complete"
}

# Function to display deployment summary
show_summary() {
    print_header "Deployment Summary"
    
    log "Deployment completed successfully!"
    log ""
    log "Resources created:"
    log "  Project ID: ${PROJECT_ID}"
    log "  Storage Bucket: gs://${BUCKET_NAME}"
    log "  Generator Function: ${FUNCTION_NAME}"
    log "  Processor Function: ${PROCESSOR_NAME}"
    log ""
    
    # Get function URLs
    local generator_url processor_url
    generator_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --format="value(httpsTrigger.url)" 2>/dev/null || echo "Not available")
    processor_url=$(gcloud functions describe "${PROCESSOR_NAME}" \
        --format="value(httpsTrigger.url)" 2>/dev/null || echo "Not available")
    
    log "Service URLs:"
    log "  Generator: ${generator_url}"
    log "  Processor: ${processor_url}"
    log ""
    log "Next steps:"
    log "  1. Use the generator URL to create conversational training data"
    log "  2. Use the processor URL to format data for model training"
    log "  3. Monitor usage in the GCP Console"
    log "  4. Run destroy.sh when finished to clean up resources"
    log ""
    log "Estimated monthly cost: $10-50 depending on usage"
    
    print_status "${GREEN}" "🎉 Deployment successful!"
}

# Function to handle script errors
handle_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code ${exit_code}"
    print_status "${RED}" "❌ Deployment failed. Check ${ERROR_LOG} for details."
    exit "${exit_code}"
}

# Function to handle script interruption
handle_interrupt() {
    log "Deployment interrupted by user"
    print_status "${YELLOW}" "⚠️ Deployment interrupted. Some resources may have been created."
    print_status "${YELLOW}" "Run destroy.sh to clean up any partial deployment."
    exit 130
}

# Main deployment function
main() {
    # Set up error handling
    trap handle_error ERR
    trap handle_interrupt SIGINT SIGTERM
    
    # Initialize logging
    log "Starting Conversational AI Training Data Generation deployment"
    log "Script version: 1.0"
    log "Timestamp: $(date)"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage
    upload_templates
    deploy_functions
    setup_monitoring
    test_deployment
    show_summary
    
    log "Deployment completed successfully at $(date)"
}

# Script usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Conversational AI Training Data Generation infrastructure on GCP

OPTIONS:
    -h, --help              Show this help message
    -n, --non-interactive   Run in non-interactive mode (use environment variables)
    -p, --project-prefix    Project prefix (default: ${DEFAULT_PROJECT_PREFIX})
    -r, --region           GCP region (default: ${DEFAULT_REGION})
    -z, --zone             GCP zone (default: ${DEFAULT_ZONE})
    --dry-run              Show what would be deployed without creating resources

ENVIRONMENT VARIABLES:
    PROJECT_PREFIX         Project prefix for resource naming
    REGION                 GCP region for resource deployment
    ZONE                   GCP zone for compute resources
    INTERACTIVE           Set to 'false' for non-interactive mode

EXAMPLES:
    $0                                          # Interactive deployment
    $0 --non-interactive                        # Non-interactive with defaults
    $0 --project-prefix my-ai-project           # Custom project prefix
    REGION=us-west1 $0 --non-interactive        # Custom region

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -n|--non-interactive)
            INTERACTIVE=false
            ;;
        -p|--project-prefix)
            PROJECT_PREFIX="$2"
            shift
            ;;
        -r|--region)
            REGION="$2"
            shift
            ;;
        -z|--zone)
            ZONE="$2"
            shift
            ;;
        --dry-run)
            print_status "${BLUE}" "Dry run mode - would deploy:"
            print_status "${BLUE}" "  Project: ${DEFAULT_PROJECT_PREFIX}-$(date +%s)"
            print_status "${BLUE}" "  Region: ${REGION:-${DEFAULT_REGION}}"
            print_status "${BLUE}" "  Zone: ${ZONE:-${DEFAULT_ZONE}}"
            print_status "${BLUE}" "  Resources: Storage bucket, 2 Cloud Functions, monitoring"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi