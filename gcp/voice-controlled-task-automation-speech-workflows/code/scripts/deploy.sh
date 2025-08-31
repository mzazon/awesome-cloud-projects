#!/bin/bash

# Voice-Controlled Task Automation Deployment Script
# This script deploys a complete voice automation system using GCP services:
# - Speech-to-Text API for voice recognition
# - Cloud Workflows for orchestration
# - Cloud Functions for processing
# - Cloud Tasks for async execution
# - Cloud Storage for audio files

set -e  # Exit on any error

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        warning "openssl not found. Using alternative method for random generation."
        USE_OPENSSL=false
    else
        USE_OPENSSL=true
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set default project ID or use existing one
    if [ -z "$PROJECT_ID" ]; then
        export PROJECT_ID="voice-automation-$(date +%s)"
        warning "PROJECT_ID not set. Using: $PROJECT_ID"
        warning "To use an existing project, set PROJECT_ID environment variable before running this script"
    fi
    
    # Set default region
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    if [ "$USE_OPENSSL" = true ]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    else
        RANDOM_SUFFIX=$(head /dev/urandom | tr -dc a-f0-9 | head -c 6)
    fi
    
    export FUNCTION_NAME="voice-processor-${RANDOM_SUFFIX}"
    export WORKFLOW_NAME="task-automation-${RANDOM_SUFFIX}"
    export BUCKET_NAME="voice-audio-${PROJECT_ID}-${RANDOM_SUFFIX}"
    export QUEUE_NAME="task-queue-${RANDOM_SUFFIX}"
    export TASK_PROCESSOR_NAME="task-processor-${RANDOM_SUFFIX}"
    
    # Store variables for cleanup script
    cat > .env << EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
FUNCTION_NAME=${FUNCTION_NAME}
WORKFLOW_NAME=${WORKFLOW_NAME}
BUCKET_NAME=${BUCKET_NAME}
QUEUE_NAME=${QUEUE_NAME}
TASK_PROCESSOR_NAME=${TASK_PROCESSOR_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables configured"
    log "Project ID: $PROJECT_ID"
    log "Region: $REGION"
    log "Resource suffix: $RANDOM_SUFFIX"
}

# Function to configure gcloud and enable APIs
configure_gcloud() {
    log "Configuring gcloud and enabling APIs..."
    
    # Set default project and region
    gcloud config set project ${PROJECT_ID}
    gcloud config set compute/region ${REGION}
    gcloud config set compute/zone ${ZONE}
    
    # Enable required APIs
    log "Enabling required Google Cloud APIs..."
    gcloud services enable speech.googleapis.com \
        workflows.googleapis.com \
        cloudfunctions.googleapis.com \
        cloudtasks.googleapis.com \
        storage.googleapis.com \
        logging.googleapis.com \
        --quiet
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "Google Cloud APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log "Creating Cloud Storage bucket for audio files..."
    
    # Create storage bucket
    if gsutil mb -p ${PROJECT_ID} -c STANDARD -l ${REGION} gs://${BUCKET_NAME}; then
        success "Storage bucket created: gs://${BUCKET_NAME}"
    else
        error "Failed to create storage bucket"
        exit 1
    fi
    
    # Set bucket lifecycle for cost optimization
    cat > lifecycle.json << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"age": 7}
      }
    ]
  }
}
EOF
    
    if gsutil lifecycle set lifecycle.json gs://${BUCKET_NAME}; then
        log "Bucket lifecycle policy configured (7-day retention)"
    else
        warning "Failed to set bucket lifecycle policy"
    fi
    
    # Clean up temporary file
    rm -f lifecycle.json
}

# Function to create Cloud Tasks queue
create_task_queue() {
    log "Creating Cloud Tasks queue..."
    
    if gcloud tasks queues create ${QUEUE_NAME} \
        --location=${REGION} \
        --max-dispatches-per-second=10 \
        --max-concurrent-dispatches=5 \
        --quiet; then
        success "Cloud Tasks queue created: ${QUEUE_NAME}"
    else
        error "Failed to create Cloud Tasks queue"
        exit 1
    fi
}

# Function to create function directories and code
prepare_function_code() {
    log "Preparing Cloud Function code..."
    
    # Create voice processing function directory
    mkdir -p voice-function
    cd voice-function
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-speech==2.31.0
google-cloud-workflows==1.14.3
google-cloud-tasks==2.16.4
google-cloud-storage==2.14.0
functions-framework==3.5.0
EOF
    
    # Create main function code
    cat > main.py << 'EOF'
import json
import os
import time
from google.cloud import speech
from google.cloud import workflows_v1
from google.cloud import tasks_v2
from google.cloud import storage
import functions_framework

@functions_framework.http
def process_voice_command(request):
    """Process uploaded audio file and trigger workflows"""
    try:
        # Get audio file from request
        data = request.get_json()
        if not data or 'audio_uri' not in data:
            return {'error': 'Missing audio_uri parameter'}, 400
        
        audio_uri = data['audio_uri']
        
        # Initialize Speech-to-Text client
        speech_client = speech.SpeechClient()
        
        # Configure speech recognition
        config = speech.RecognitionConfig(
            encoding=speech.RecognitionConfig.AudioEncoding.LINEAR16,
            sample_rate_hertz=16000,
            language_code="en-US",
            enable_automatic_punctuation=True,
            model="latest_long"
        )
        
        audio = speech.RecognitionAudio(uri=audio_uri)
        
        # Perform speech recognition
        response = speech_client.recognize(config=config, audio=audio)
        
        if not response.results:
            return {'error': 'No speech detected'}, 400
        
        # Extract transcript
        transcript = response.results[0].alternatives[0].transcript.lower()
        confidence = response.results[0].alternatives[0].confidence
        
        # Simple intent recognition
        intent_data = analyze_intent(transcript)
        
        # Trigger appropriate workflow
        if intent_data['intent'] != 'unknown':
            workflow_result = trigger_workflow(intent_data)
            return {
                'transcript': transcript,
                'confidence': confidence,
                'intent': intent_data,
                'workflow_triggered': workflow_result
            }
        else:
            return {
                'transcript': transcript,
                'confidence': confidence,
                'error': 'Intent not recognized'
            }, 400
            
    except Exception as e:
        return {'error': str(e)}, 500

def analyze_intent(transcript):
    """Simple intent recognition from transcript"""
    intent_data = {
        'intent': 'unknown',
        'action': None,
        'parameters': {}
    }
    
    # Simple keyword-based intent detection
    if 'create task' in transcript or 'new task' in transcript:
        intent_data['intent'] = 'create_task'
        intent_data['action'] = 'task_creation'
        # Extract task details (simplified)
        if 'urgent' in transcript:
            intent_data['parameters']['priority'] = 'high'
        if 'meeting' in transcript:
            intent_data['parameters']['category'] = 'meeting'
        
    elif 'schedule' in transcript:
        intent_data['intent'] = 'schedule_task'
        intent_data['action'] = 'task_scheduling'
        
    elif 'report' in transcript or 'status' in transcript:
        intent_data['intent'] = 'generate_report'
        intent_data['action'] = 'report_generation'
    
    return intent_data

def trigger_workflow(intent_data):
    """Trigger Cloud Workflow based on intent"""
    try:
        project_id = os.environ.get('GCP_PROJECT')
        location = os.environ.get('REGION', 'us-central1')
        workflow_name = os.environ.get('WORKFLOW_NAME')
        
        # Initialize Workflows client
        workflows_client = workflows_v1.ExecutionsClient()
        
        # Prepare workflow execution
        parent = f"projects/{project_id}/locations/{location}/workflows/{workflow_name}"
        execution = {
            "argument": json.dumps(intent_data)
        }
        
        # Execute workflow
        operation = workflows_client.create_execution(
            parent=parent,
            execution=execution
        )
        
        return {
            'status': 'triggered',
            'execution_name': operation.name
        }
        
    except Exception as e:
        return {
            'status': 'failed',
            'error': str(e)
        }
EOF
    
    cd ..
    success "Voice processing function code prepared"
}

# Function to deploy voice processing function
deploy_voice_function() {
    log "Deploying voice processing Cloud Function..."
    
    cd voice-function
    
    if gcloud functions deploy ${FUNCTION_NAME} \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point process_voice_command \
        --memory 512MB \
        --timeout 60s \
        --set-env-vars "GCP_PROJECT=${PROJECT_ID},REGION=${REGION},WORKFLOW_NAME=${WORKFLOW_NAME}" \
        --quiet; then
        success "Voice processing function deployed: ${FUNCTION_NAME}"
    else
        error "Failed to deploy voice processing function"
        cd ..
        exit 1
    fi
    
    cd ..
}

# Function to create and deploy workflow
deploy_workflow() {
    log "Creating and deploying Cloud Workflow..."
    
    # Create workflow definition with proper variable substitution
    cat > task-automation-workflow.yaml << EOF
main:
  params: [args]
  steps:
  - init:
      assign:
      - intent: \${args.intent}
      - action: \${args.action}
      - parameters: \${args.parameters}
      - project_id: \${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
      
  - validate_intent:
      switch:
      - condition: \${intent == "create_task"}
        next: create_task_process
      - condition: \${intent == "schedule_task"}
        next: schedule_task_process
      - condition: \${intent == "generate_report"}
        next: generate_report_process
      default:
        next: unknown_intent_error

  - create_task_process:
      steps:
      - log_task_creation:
          call: sys.log
          args:
            text: \${"Creating task with parameters: " + string(parameters)}
            severity: INFO
            
      - enqueue_task:
          call: http.post
          args:
            url: \${"https://cloudtasks.googleapis.com/v2/projects/" + project_id + "/locations/${REGION}/queues/${QUEUE_NAME}/tasks"}
            auth:
              type: OAuth2
            headers:
              Content-Type: application/json
            body:
              task:
                httpRequest:
                  url: \${"https://${REGION}-" + project_id + ".cloudfunctions.net/${TASK_PROCESSOR_NAME}"}
                  httpMethod: POST
                  headers:
                    Content-Type: application/json
                  body: \${base64.encode(json.encode({
                    "action": "create_task",
                    "parameters": parameters
                  }))}
                scheduleTime: \${time.format(time.now())}
          result: task_result
          
      - return_success:
          return:
            status: "success"
            message: "Task creation initiated"
            task_id: \${task_result.body.name}

  - schedule_task_process:
      steps:
      - log_scheduling:
          call: sys.log
          args:
            text: \${"Scheduling task with parameters: " + string(parameters)}
            severity: INFO
            
      - calculate_schedule_time:
          assign:
          - schedule_time: \${time.format(time.add(time.now(), 3600))}  # 1 hour from now
          
      - enqueue_scheduled_task:
          call: http.post
          args:
            url: \${"https://cloudtasks.googleapis.com/v2/projects/" + project_id + "/locations/${REGION}/queues/${QUEUE_NAME}/tasks"}
            auth:
              type: OAuth2
            headers:
              Content-Type: application/json
            body:
              task:
                httpRequest:
                  url: \${"https://${REGION}-" + project_id + ".cloudfunctions.net/${TASK_PROCESSOR_NAME}"}
                  httpMethod: POST
                  headers:
                    Content-Type: application/json
                  body: \${base64.encode(json.encode({
                    "action": "scheduled_task",
                    "parameters": parameters
                  }))}
                scheduleTime: \${schedule_time}
          result: scheduled_result
          
      - return_scheduled:
          return:
            status: "success"
            message: "Task scheduled successfully"
            scheduled_time: \${schedule_time}
            task_id: \${scheduled_result.body.name}

  - generate_report_process:
      steps:
      - log_report:
          call: sys.log
          args:
            text: "Generating report based on voice command"
            severity: INFO
            
      - create_report_task:
          call: http.post
          args:
            url: \${"https://cloudtasks.googleapis.com/v2/projects/" + project_id + "/locations/${REGION}/queues/${QUEUE_NAME}/tasks"}
            auth:
              type: OAuth2
            headers:
              Content-Type: application/json
            body:
              task:
                httpRequest:
                  url: \${"https://${REGION}-" + project_id + ".cloudfunctions.net/${TASK_PROCESSOR_NAME}"}
                  httpMethod: POST
                  headers:
                    Content-Type: application/json
                  body: \${base64.encode(json.encode({
                    "action": "generate_report",
                    "parameters": parameters
                  }))}
          result: report_result
          
      - return_report:
          return:
            status: "success"
            message: "Report generation initiated"
            task_id: \${report_result.body.name}

  - unknown_intent_error:
      raise:
        message: \${"Unknown intent: " + intent}
EOF
    
    # Deploy workflow
    if gcloud workflows deploy ${WORKFLOW_NAME} \
        --source=task-automation-workflow.yaml \
        --location=${REGION} \
        --quiet; then
        success "Cloud Workflow deployed: ${WORKFLOW_NAME}"
    else
        error "Failed to deploy Cloud Workflow"
        exit 1
    fi
}

# Function to prepare and deploy task processor function
deploy_task_processor() {
    log "Preparing and deploying task processor function..."
    
    # Create task processor function directory
    mkdir -p task-processor
    cd task-processor
    
    # Create requirements for task processor
    cat > requirements.txt << 'EOF'
google-cloud-logging==3.8.0
google-cloud-storage==2.14.0
functions-framework==3.5.0
EOF
    
    # Create task processor function
    cat > main.py << 'EOF'
import json
import base64
import time
from google.cloud import logging
from google.cloud import storage
import functions_framework

# Initialize logging
logging_client = logging.Client()
logger = logging_client.logger("task-processor")

@functions_framework.http
def process_task(request):
    """Process tasks created by voice commands"""
    try:
        # Parse request data
        if request.content_type == 'application/json':
            data = request.get_json()
        else:
            # Handle Cloud Tasks payload
            data = json.loads(base64.b64decode(request.data).decode())
        
        action = data.get('action')
        parameters = data.get('parameters', {})
        
        # Log task processing
        logger.log_struct({
            'message': 'Processing voice-triggered task',
            'action': action,
            'parameters': parameters
        })
        
        # Execute based on action type
        if action == 'create_task':
            result = handle_task_creation(parameters)
        elif action == 'scheduled_task':
            result = handle_scheduled_task(parameters)
        elif action == 'generate_report':
            result = handle_report_generation(parameters)
        else:
            return {'error': f'Unknown action: {action}'}, 400
        
        return {
            'status': 'completed',
            'action': action,
            'result': result
        }
        
    except Exception as e:
        logger.error(f'Task processing failed: {str(e)}')
        return {'error': str(e)}, 500

def handle_task_creation(parameters):
    """Handle task creation logic"""
    priority = parameters.get('priority', 'normal')
    category = parameters.get('category', 'general')
    
    # Simulate task creation (replace with actual business logic)
    task_data = {
        'id': f'task-{int(time.time())}',
        'priority': priority,
        'category': category,
        'status': 'created',
        'created_by': 'voice-command'
    }
    
    logger.log_struct({
        'message': 'Task created successfully',
        'task_data': task_data
    })
    
    return task_data

def handle_scheduled_task(parameters):
    """Handle scheduled task logic"""
    # Simulate scheduled task processing
    scheduled_data = {
        'type': 'scheduled',
        'parameters': parameters,
        'executed_at': time.time()
    }
    
    logger.log_struct({
        'message': 'Scheduled task executed',
        'scheduled_data': scheduled_data
    })
    
    return scheduled_data

def handle_report_generation(parameters):
    """Handle report generation logic"""
    # Simulate report generation
    report_data = {
        'report_id': f'report-{int(time.time())}',
        'type': 'voice_triggered',
        'generated_at': time.time(),
        'parameters': parameters
    }
    
    logger.log_struct({
        'message': 'Report generated successfully',
        'report_data': report_data
    })
    
    return report_data
EOF
    
    # Deploy task processing function
    if gcloud functions deploy ${TASK_PROCESSOR_NAME} \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point process_task \
        --memory 256MB \
        --timeout 30s \
        --quiet; then
        success "Task processing function deployed: ${TASK_PROCESSOR_NAME}"
    else
        error "Failed to deploy task processing function"
        cd ..
        exit 1
    fi
    
    cd ..
}

# Function to configure IAM permissions
configure_iam() {
    log "Configuring IAM permissions for service integration..."
    
    # Get function service account
    FUNCTION_SA=$(gcloud functions describe ${FUNCTION_NAME} \
        --region=${REGION} \
        --format="value(serviceAccountEmail)")
    
    if [ -z "$FUNCTION_SA" ]; then
        error "Failed to get function service account"
        exit 1
    fi
    
    # Grant Workflows Invoker role to function
    if gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${FUNCTION_SA}" \
        --role="roles/workflows.invoker" \
        --quiet; then
        log "Granted Workflows Invoker role to function service account"
    else
        warning "Failed to grant Workflows Invoker role"
    fi
    
    # Grant Speech-to-Text User role to function
    if gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${FUNCTION_SA}" \
        --role="roles/speech.client" \
        --quiet; then
        log "Granted Speech-to-Text Client role to function service account"
    else
        warning "Failed to grant Speech-to-Text Client role"
    fi
    
    # Grant Cloud Tasks Admin role to Workflows service account
    WORKFLOWS_SA="${PROJECT_ID}@appspot.gserviceaccount.com"
    if gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member="serviceAccount:${WORKFLOWS_SA}" \
        --role="roles/cloudtasks.admin" \
        --quiet; then
        log "Granted Cloud Tasks Admin role to Workflows service account"
    else
        warning "Failed to grant Cloud Tasks Admin role"
    fi
    
    success "IAM permissions configured"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check if function exists and is active
    if gcloud functions describe ${FUNCTION_NAME} --region=${REGION} &>/dev/null; then
        log "✓ Voice processing function is deployed"
    else
        error "Voice processing function deployment failed"
        return 1
    fi
    
    # Check if task processor function exists
    if gcloud functions describe ${TASK_PROCESSOR_NAME} --region=${REGION} &>/dev/null; then
        log "✓ Task processor function is deployed"
    else
        error "Task processor function deployment failed"
        return 1
    fi
    
    # Check if workflow exists
    if gcloud workflows describe ${WORKFLOW_NAME} --location=${REGION} &>/dev/null; then
        log "✓ Cloud Workflow is deployed"
    else
        error "Cloud Workflow deployment failed"
        return 1
    fi
    
    # Check if task queue exists
    if gcloud tasks queues describe ${QUEUE_NAME} --location=${REGION} &>/dev/null; then
        log "✓ Cloud Tasks queue is created"
    else
        error "Cloud Tasks queue creation failed"
        return 1
    fi
    
    # Check if storage bucket exists
    if gsutil ls -b gs://${BUCKET_NAME} &>/dev/null; then
        log "✓ Cloud Storage bucket is created"
    else
        error "Cloud Storage bucket creation failed"
        return 1
    fi
    
    success "All components deployed successfully"
}

# Function to display deployment information
display_deployment_info() {
    log "Deployment completed successfully!"
    echo ""
    echo "=== Voice-Controlled Task Automation System ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "=== Deployed Resources ==="
    echo "Voice Processing Function: ${FUNCTION_NAME}"
    echo "Task Processor Function: ${TASK_PROCESSOR_NAME}"
    echo "Cloud Workflow: ${WORKFLOW_NAME}"
    echo "Cloud Tasks Queue: ${QUEUE_NAME}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo ""
    echo "=== Function URLs ==="
    FUNCTION_URL=$(gcloud functions describe ${FUNCTION_NAME} \
        --region=${REGION} \
        --format="value(httpsTrigger.url)" 2>/dev/null)
    TASK_PROCESSOR_URL=$(gcloud functions describe ${TASK_PROCESSOR_NAME} \
        --region=${REGION} \
        --format="value(httpsTrigger.url)" 2>/dev/null)
    echo "Voice Processor: ${FUNCTION_URL}"
    echo "Task Processor: ${TASK_PROCESSOR_URL}"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Test the voice processing by sending POST requests to the function URL"
    echo "2. Upload audio files to the storage bucket for processing"
    echo "3. Monitor workflow executions in the Cloud Console"
    echo "4. Check Cloud Tasks queue for task processing status"
    echo ""
    echo "=== Cleanup ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo ""
    success "Voice-controlled task automation system is ready!"
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -f task-automation-workflow.yaml
    rm -rf voice-function task-processor
}

# Main deployment function
main() {
    echo "================================================================"
    echo "  GCP Voice-Controlled Task Automation Deployment Script"
    echo "================================================================"
    echo ""
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    configure_gcloud
    create_storage_bucket
    create_task_queue
    prepare_function_code
    deploy_voice_function
    deploy_workflow
    deploy_task_processor
    configure_iam
    
    # Validate deployment
    if validate_deployment; then
        display_deployment_info
        cleanup_temp_files
        success "Deployment completed successfully!"
        exit 0
    else
        error "Deployment validation failed. Please check the logs above."
        exit 1
    fi
}

# Handle script interruption
trap 'error "Deployment interrupted"; cleanup_temp_files; exit 1' INT TERM

# Run main function
main "$@"