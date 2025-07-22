#!/bin/bash

# Conversational AI Backends with Agent Development Kit and Firestore - Deployment Script
# This script deploys the complete conversational AI backend infrastructure on Google Cloud Platform

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# Color codes for output formatting
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command_exists gsutil; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if python3 is installed
    if ! command_exists python3; then
        error "Python 3 is not installed. Please install Python 3.10 or later."
        exit 1
    fi
    
    # Check if pip3 is installed
    if ! command_exists pip3; then
        error "pip3 is not installed. Please install pip for Python 3."
        exit 1
    fi
    
    # Check if openssl is installed (for random generation)
    if ! command_exists openssl; then
        error "openssl is not installed. Please install openssl."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Please authenticate with Google Cloud: gcloud auth login"
        exit 1
    fi
    
    success "All prerequisites check passed"
}

# Function to validate environment variables
validate_environment() {
    log "Validating environment configuration..."
    
    # Set default values if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="conversational-ai-$(date +%s)"
        warning "PROJECT_ID not set. Using default: ${PROJECT_ID}"
    fi
    
    if [[ -z "${REGION:-}" ]]; then
        export REGION="us-central1"
        warning "REGION not set. Using default: ${REGION}"
    fi
    
    if [[ -z "${ZONE:-}" ]]; then
        export ZONE="${REGION}-a"
        warning "ZONE not set. Using default: ${ZONE}"
    fi
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    export FUNCTION_NAME="chat-processor-${RANDOM_SUFFIX}"
    export BUCKET_NAME="${PROJECT_ID}-conversations-${RANDOM_SUFFIX}"
    export FIRESTORE_DATABASE="chat-conversations"
    
    log "Environment configuration:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  ZONE: ${ZONE}"
    log "  FUNCTION_NAME: ${FUNCTION_NAME}"
    log "  BUCKET_NAME: ${BUCKET_NAME}"
    log "  FIRESTORE_DATABASE: ${FIRESTORE_DATABASE}"
}

# Function to set up Google Cloud project
setup_project() {
    log "Setting up Google Cloud project..."
    
    # Check if project exists
    if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log "Project ${PROJECT_ID} already exists"
    else
        log "Creating project ${PROJECT_ID}..."
        gcloud projects create "${PROJECT_ID}" --name="Conversational AI Backend" || {
            error "Failed to create project. You may need billing permissions."
            exit 1
        }
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    success "Project configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log "Enabling ${api}..."
        gcloud services enable "${api}" || {
            error "Failed to enable API: ${api}"
            exit 1
        }
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All required APIs enabled"
}

# Function to create Firestore database
setup_firestore() {
    log "Setting up Firestore database..."
    
    # Check if Firestore database already exists
    if gcloud firestore databases describe --database="${FIRESTORE_DATABASE}" >/dev/null 2>&1; then
        log "Firestore database ${FIRESTORE_DATABASE} already exists"
    else
        log "Creating Firestore database..."
        gcloud firestore databases create \
            --database="${FIRESTORE_DATABASE}" \
            --location="${REGION}" \
            --type=firestore-native || {
            error "Failed to create Firestore database"
            exit 1
        }
    fi
    
    # Set default database
    gcloud config set firestore/database "${FIRESTORE_DATABASE}"
    
    # Create composite indexes for efficient conversation queries
    log "Creating Firestore indexes..."
    gcloud firestore indexes composite create \
        --collection-group=conversations \
        --field-config=field-path=userId,order=ascending \
        --field-config=field-path=timestamp,order=descending \
        --quiet || warning "Index creation failed or already exists"
    
    success "Firestore database setup completed"
}

# Function to create Cloud Storage bucket
setup_storage() {
    log "Setting up Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log "Bucket gs://${BUCKET_NAME} already exists"
    else
        log "Creating Cloud Storage bucket..."
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}" || {
            error "Failed to create Cloud Storage bucket"
            exit 1
        }
    fi
    
    # Enable versioning for conversation artifact protection
    log "Enabling versioning on bucket..."
    gsutil versioning set on "gs://${BUCKET_NAME}"
    
    # Set lifecycle policy for automated cleanup
    log "Setting lifecycle policy..."
    cat > /tmp/lifecycle.json << 'EOF'
{
  "rule": [
    {
      "action": {"type": "Delete"},
      "condition": {
        "age": 90,
        "matchesPrefix": ["conversations/archived/"]
      }
    }
  ]
}
EOF
    
    gsutil lifecycle set /tmp/lifecycle.json "gs://${BUCKET_NAME}"
    rm -f /tmp/lifecycle.json
    
    success "Cloud Storage bucket setup completed"
}

# Function to install Python dependencies
install_dependencies() {
    log "Installing Python dependencies..."
    
    # Create temporary directory for agent development
    mkdir -p /tmp/conversation-agent/{src,config,functions}
    cd /tmp/conversation-agent
    
    # Install required Python packages
    pip3 install --user google-cloud-aiplatform
    pip3 install --user google-cloud-firestore
    pip3 install --user google-cloud-storage
    pip3 install --user google-cloud-functions-framework
    pip3 install --user functions-framework
    pip3 install --user Flask
    
    # Note: google-adk-agents is currently in preview and may not be available
    warning "Agent Development Kit (google-adk-agents) is in preview. Using basic implementation."
    
    success "Python dependencies installed"
}

# Function to create agent configuration
create_agent_config() {
    log "Creating conversation agent configuration..."
    
    # Create main agent configuration
    cat > /tmp/conversation-agent/config/agent_config.py << 'EOF'
from google.cloud import firestore
from google.cloud import storage
from google.cloud import aiplatform
import json
import datetime
import uuid

class ConversationAgent:
    def __init__(self, project_id, region, database_id):
        self.project_id = project_id
        self.region = region
        self.firestore_client = firestore.Client(
            project=project_id, 
            database=database_id
        )
        self.storage_client = storage.Client(project=project_id)
        
        # Initialize Vertex AI
        aiplatform.init(project=project_id, location=region)

    def process_conversation(self, user_id, message, session_id=None):
        """Process user message and generate intelligent response"""
        try:
            # Retrieve conversation history
            conversation_ref = self.firestore_client.collection('conversations').document(user_id)
            conversation_doc = conversation_ref.get()
            
            conversation_history = []
            if conversation_doc.exists:
                conversation_history = conversation_doc.to_dict().get('messages', [])
            
            # Add user message to history
            user_message = {
                'role': 'user',
                'content': message,
                'timestamp': datetime.datetime.now().isoformat(),
                'session_id': session_id or str(uuid.uuid4())
            }
            conversation_history.append(user_message)
            
            # Generate response (simplified implementation)
            response = self._generate_response(message, conversation_history[-10:])
            
            # Add assistant response to history
            assistant_message = {
                'role': 'assistant',
                'content': response,
                'timestamp': datetime.datetime.now().isoformat(),
                'session_id': session_id or user_message['session_id']
            }
            conversation_history.append(assistant_message)
            
            # Store updated conversation
            conversation_ref.set({
                'messages': conversation_history,
                'last_updated': datetime.datetime.now(),
                'user_id': user_id
            })
            
            return response
        except Exception as e:
            print(f"Error processing conversation: {str(e)}")
            return "I apologize, but I'm having trouble processing your request right now. Please try again."
    
    def _generate_response(self, message, history):
        """Generate response using Vertex AI (simplified implementation)"""
        # In a real implementation, this would use Vertex AI models
        # For now, return a simple contextual response
        if "hello" in message.lower():
            return "Hello! I'm your AI assistant. How can I help you today?"
        elif "help" in message.lower():
            return "I'm here to assist you. You can ask me questions about various topics, and I'll do my best to provide helpful responses."
        elif "project" in message.lower():
            return "I'd be happy to help with your project! Could you provide more details about what you're working on?"
        else:
            return f"I understand you're asking about: {message}. Let me help you with that. Could you provide more specific details?"
EOF
    
    success "Agent configuration created"
}

# Function to create Cloud Functions
create_cloud_functions() {
    log "Creating Cloud Functions..."
    
    # Create main Cloud Function for conversation processing
    cat > /tmp/conversation-agent/functions/main.py << 'EOF'
import os
import json
from flask import Flask, request, jsonify
from google.cloud import firestore
from google.cloud import storage
import functions_framework
from datetime import datetime
import uuid
import sys

# Add config path
sys.path.append('../config')

class SimpleConversationAgent:
    def __init__(self, project_id, region, database_id):
        self.project_id = project_id
        self.region = region
        self.firestore_client = firestore.Client(
            project=project_id, 
            database=database_id
        )
        self.storage_client = storage.Client(project=project_id)

    def process_conversation(self, user_id, message, session_id=None):
        """Process user message and generate intelligent response"""
        try:
            # Retrieve conversation history
            conversation_ref = self.firestore_client.collection('conversations').document(user_id)
            conversation_doc = conversation_ref.get()
            
            conversation_history = []
            if conversation_doc.exists:
                conversation_history = conversation_doc.to_dict().get('messages', [])
            
            # Add user message to history
            user_message = {
                'role': 'user',
                'content': message,
                'timestamp': datetime.now().isoformat(),
                'session_id': session_id or str(uuid.uuid4())
            }
            conversation_history.append(user_message)
            
            # Generate response
            response = self._generate_response(message, conversation_history[-10:])
            
            # Add assistant response to history
            assistant_message = {
                'role': 'assistant',
                'content': response,
                'timestamp': datetime.now().isoformat(),
                'session_id': session_id or user_message['session_id']
            }
            conversation_history.append(assistant_message)
            
            # Store updated conversation
            conversation_ref.set({
                'messages': conversation_history,
                'last_updated': datetime.now(),
                'user_id': user_id
            })
            
            return response
        except Exception as e:
            print(f"Error processing conversation: {str(e)}")
            return "I apologize, but I'm having trouble processing your request right now. Please try again."
    
    def _generate_response(self, message, history):
        """Generate response using simple logic"""
        if "hello" in message.lower():
            return "Hello! I'm your AI assistant. How can I help you today?"
        elif "help" in message.lower():
            return "I'm here to assist you. You can ask me questions about various topics, and I'll do my best to provide helpful responses."
        elif "project" in message.lower():
            return "I'd be happy to help with your project! Could you provide more details about what you're working on?"
        else:
            return f"I understand you're asking about: {message}. Let me help you with that. Could you provide more specific details?"

# Initialize agent
PROJECT_ID = os.environ.get('PROJECT_ID')
REGION = os.environ.get('REGION', 'us-central1')
DATABASE_ID = os.environ.get('FIRESTORE_DATABASE', 'chat-conversations')

agent = SimpleConversationAgent(PROJECT_ID, REGION, DATABASE_ID)

@functions_framework.http
def chat_processor(request):
    """HTTP Cloud Function for processing chat messages"""
    # Handle CORS
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Validate request
        if request.method != 'POST':
            return jsonify({'error': 'Method not allowed'}), 405
        
        data = request.get_json()
        if not data or 'message' not in data or 'user_id' not in data:
            return jsonify({'error': 'Missing required fields'}), 400
        
        user_id = data['user_id']
        message = data['message']
        session_id = data.get('session_id', str(uuid.uuid4()))
        
        # Process conversation
        response = agent.process_conversation(user_id, message, session_id)
        
        return jsonify({
            'response': response,
            'session_id': session_id,
            'timestamp': datetime.now().isoformat(),
            'status': 'success'
        }), 200, headers
        
    except Exception as e:
        return jsonify({
            'error': str(e),
            'status': 'error'
        }), 500, headers

@functions_framework.http
def get_conversation_history(request):
    """HTTP Cloud Function for retrieving conversation history"""
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        user_id = request.args.get('user_id')
        if not user_id:
            return jsonify({'error': 'user_id parameter required'}), 400
        
        # Retrieve conversation from Firestore
        firestore_client = firestore.Client(project=PROJECT_ID, database=DATABASE_ID)
        conversation_ref = firestore_client.collection('conversations').document(user_id)
        conversation_doc = conversation_ref.get()
        
        if not conversation_doc.exists:
            return jsonify({'messages': [], 'status': 'success'}), 200, headers
        
        conversation_data = conversation_doc.to_dict()
        messages = conversation_data.get('messages', [])
        
        return jsonify({
            'messages': messages,
            'last_updated': conversation_data.get('last_updated').isoformat() if conversation_data.get('last_updated') else None,
            'status': 'success'
        }), 200, headers
        
    except Exception as e:
        return jsonify({
            'error': str(e),
            'status': 'error'
        }), 500, headers
EOF
    
    # Create requirements.txt for Cloud Functions
    cat > /tmp/conversation-agent/functions/requirements.txt << 'EOF'
functions-framework==3.5.0
google-cloud-firestore==2.13.1
google-cloud-storage==2.10.0
google-cloud-aiplatform==1.38.1
Flask==3.0.0
EOF
    
    success "Cloud Functions code created"
}

# Function to deploy Cloud Functions
deploy_functions() {
    log "Deploying Cloud Functions..."
    
    # Deploy main conversation processing function
    log "Deploying chat processor function..."
    gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime=python310 \
        --region="${REGION}" \
        --source=/tmp/conversation-agent/functions \
        --entry-point=chat_processor \
        --trigger=http \
        --allow-unauthenticated \
        --memory=1GB \
        --timeout=60s \
        --set-env-vars=PROJECT_ID="${PROJECT_ID}",REGION="${REGION}",FIRESTORE_DATABASE="${FIRESTORE_DATABASE}" || {
        error "Failed to deploy chat processor function"
        exit 1
    }
    
    # Deploy conversation history function
    log "Deploying conversation history function..."
    gcloud functions deploy "${FUNCTION_NAME}-history" \
        --gen2 \
        --runtime=python310 \
        --region="${REGION}" \
        --source=/tmp/conversation-agent/functions \
        --entry-point=get_conversation_history \
        --trigger=http \
        --allow-unauthenticated \
        --memory=512MB \
        --timeout=30s \
        --set-env-vars=PROJECT_ID="${PROJECT_ID}",REGION="${REGION}",FIRESTORE_DATABASE="${FIRESTORE_DATABASE}" || {
        error "Failed to deploy conversation history function"
        exit 1
    }
    
    success "Cloud Functions deployed successfully"
}

# Function to get deployment information
get_deployment_info() {
    log "Retrieving deployment information..."
    
    # Get function URLs
    local chat_url
    local history_url
    
    chat_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)" 2>/dev/null || echo "Not available")
    
    history_url=$(gcloud functions describe "${FUNCTION_NAME}-history" \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)" 2>/dev/null || echo "Not available")
    
    success "Deployment completed successfully!"
    echo
    echo "=== Deployment Information ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Firestore Database: ${FIRESTORE_DATABASE}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    echo "Chat API URL: ${chat_url}"
    echo "History API URL: ${history_url}"
    echo
    echo "=== Testing Commands ==="
    echo "Test chat endpoint:"
    echo "curl -X POST ${chat_url} \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -d '{\"user_id\": \"test_user_123\", \"message\": \"Hello!\"}'"
    echo
    echo "Test history endpoint:"
    echo "curl -X GET \"${history_url}?user_id=test_user_123\""
    echo
}

# Function to perform health checks
health_check() {
    log "Performing health checks..."
    
    # Check if Firestore database is accessible
    if gcloud firestore databases describe --database="${FIRESTORE_DATABASE}" >/dev/null 2>&1; then
        success "Firestore database is accessible"
    else
        warning "Firestore database health check failed"
    fi
    
    # Check if storage bucket is accessible
    if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        success "Cloud Storage bucket is accessible"
    else
        warning "Cloud Storage bucket health check failed"
    fi
    
    # Check if functions are deployed
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        success "Chat processor function is deployed"
    else
        warning "Chat processor function health check failed"
    fi
    
    if gcloud functions describe "${FUNCTION_NAME}-history" --region="${REGION}" >/dev/null 2>&1; then
        success "History function is deployed"
    else
        warning "History function health check failed"
    fi
}

# Function to cleanup temporary files
cleanup_temp() {
    log "Cleaning up temporary files..."
    rm -rf /tmp/conversation-agent
    rm -f /tmp/lifecycle.json
    success "Temporary files cleaned up"
}

# Main deployment function
main() {
    echo "================================================================"
    echo "   Conversational AI Backends Deployment Script"
    echo "   Google Cloud Platform - Agent Development Kit & Firestore"
    echo "================================================================"
    echo
    
    # Check if running in dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "Running in DRY-RUN mode - no resources will be created"
        validate_environment
        exit 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    validate_environment
    setup_project
    enable_apis
    setup_firestore
    setup_storage
    install_dependencies
    create_agent_config
    create_cloud_functions
    deploy_functions
    get_deployment_info
    health_check
    cleanup_temp
    
    echo
    success "Deployment completed successfully!"
    echo "Your conversational AI backend is now ready for use."
    echo
    warning "Remember to run the destroy.sh script when you're done to avoid ongoing charges."
}

# Handle script interruption
trap 'error "Deployment interrupted"; cleanup_temp; exit 1' INT TERM

# Run main function
main "$@"