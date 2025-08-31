#!/bin/bash

# Deployment script for Persistent AI Customer Support with Agent Engine Memory
# This script deploys the complete infrastructure including Firestore, Cloud Functions, and AI services

set -e
set -u
set -o pipefail

# Color codes for output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "You are not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if Python 3 is installed
    if ! command_exists python3; then
        log_error "Python 3 is not installed. Please install Python 3 first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-support-agent-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export FUNCTION_NAME="${FUNCTION_NAME:-support-chat-${RANDOM_SUFFIX}}"
    export MEMORY_FUNCTION_NAME="${MEMORY_FUNCTION_NAME:-retrieve-memory-${RANDOM_SUFFIX}}"
    export FIRESTORE_DATABASE="${FIRESTORE_DATABASE:-support-memory-${RANDOM_SUFFIX}}"
    
    # Create project if specified and doesn't exist
    if [[ "${CREATE_PROJECT:-false}" == "true" ]]; then
        log_info "Creating new project: ${PROJECT_ID}"
        if ! gcloud projects create "${PROJECT_ID}" --quiet 2>/dev/null; then
            log_warning "Project ${PROJECT_ID} might already exist or creation failed"
        fi
        
        # Set billing account if provided
        if [[ -n "${BILLING_ACCOUNT_ID:-}" ]]; then
            log_info "Linking billing account to project..."
            gcloud billing projects link "${PROJECT_ID}" \
                --billing-account="${BILLING_ACCOUNT_ID}" \
                --quiet || log_warning "Failed to link billing account"
        fi
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set functions/region "${REGION}" --quiet
    
    log_success "Environment variables configured"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Function names: ${FUNCTION_NAME}, ${MEMORY_FUNCTION_NAME}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com"
        "aiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "${api} enabled"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create Firestore database
create_firestore() {
    log_info "Creating Firestore database..."
    
    # Check if Firestore database already exists
    if gcloud firestore databases list --filter="name:projects/${PROJECT_ID}/databases/(default)" --format="value(name)" | grep -q .; then
        log_warning "Firestore database already exists"
        return 0
    fi
    
    # Create Firestore database in Native mode
    if gcloud firestore databases create \
        --location="${REGION}" \
        --type=firestore-native \
        --quiet; then
        log_success "Firestore database created successfully"
    else
        log_error "Failed to create Firestore database"
        exit 1
    fi
    
    # Wait for database to be ready
    log_info "Waiting for Firestore database to be ready..."
    sleep 30
}

# Function to prepare function source code
prepare_function_code() {
    log_info "Preparing Cloud Function source code..."
    
    # Create temporary directories for function code
    export TEMP_DIR=$(mktemp -d)
    mkdir -p "${TEMP_DIR}/memory-retrieval"
    mkdir -p "${TEMP_DIR}/chat-function"
    
    # Memory retrieval function
    cat > "${TEMP_DIR}/memory-retrieval/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-firestore==2.*
google-cloud-aiplatform==1.*
flask==2.*
EOF
    
    cat > "${TEMP_DIR}/memory-retrieval/main.py" << 'EOF'
import functions_framework
from google.cloud import firestore
import json
from flask import Request
from datetime import datetime, timedelta

@functions_framework.http
def retrieve_memory(request: Request):
    """Retrieve conversation memory for customer context."""
    
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    try:
        request_json = request.get_json()
        customer_id = request_json.get('customer_id')
        
        if not customer_id:
            return {'error': 'customer_id required'}, 400
        
        # Initialize Firestore client
        db = firestore.Client()
        
        # Retrieve recent conversations (last 30 days)
        thirty_days_ago = datetime.now() - timedelta(days=30)
        
        conversations_ref = db.collection('conversations')
        query = conversations_ref.where('customer_id', '==', customer_id) \
                               .where('timestamp', '>=', thirty_days_ago) \
                               .order_by('timestamp', direction=firestore.Query.DESCENDING) \
                               .limit(10)
        
        conversations = []
        for doc in query.stream():
            conversation = doc.to_dict()
            conversations.append({
                'id': doc.id,
                'message': conversation.get('message', ''),
                'response': conversation.get('response', ''),
                'timestamp': conversation.get('timestamp'),
                'sentiment': conversation.get('sentiment', 'neutral'),
                'resolved': conversation.get('resolved', False)
            })
        
        # Extract customer context
        customer_context = {
            'total_conversations': len(conversations),
            'recent_topics': [],
            'satisfaction_trend': 'neutral',
            'common_issues': []
        }
        
        if conversations:
            # Analyze conversation patterns
            unresolved_count = sum(1 for c in conversations if not c['resolved'])
            customer_context['unresolved_issues'] = unresolved_count
            
            # Extract recent topics (simplified)
            recent_messages = [c['message'][:100] for c in conversations[:3]]
            customer_context['recent_topics'] = recent_messages
        
        response = {
            'customer_id': customer_id,
            'conversations': conversations,
            'context': customer_context,
            'retrieved_at': datetime.now().isoformat()
        }
        
        headers = {'Access-Control-Allow-Origin': '*'}
        return (response, 200, headers)
        
    except Exception as e:
        return {'error': str(e)}, 500
EOF
    
    # Chat function
    cat > "${TEMP_DIR}/chat-function/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-firestore==2.*
google-cloud-aiplatform==1.*
flask==2.*
requests==2.*
EOF
    
    cat > "${TEMP_DIR}/chat-function/main.py" << 'EOF'
import functions_framework
from google.cloud import firestore
import vertexai
from vertexai.generative_models import GenerativeModel
import json
import requests
from flask import Request
from datetime import datetime
import os

# Initialize Vertex AI
PROJECT_ID = os.environ.get('GCP_PROJECT')
REGION = 'us-central1'

vertexai.init(project=PROJECT_ID, location=REGION)

@functions_framework.http
def support_chat(request: Request):
    """Main support chat function with memory integration."""
    
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    try:
        request_json = request.get_json()
        customer_id = request_json.get('customer_id')
        message = request_json.get('message')
        
        if not customer_id or not message:
            return {'error': 'customer_id and message required'}, 400
        
        # Retrieve conversation memory
        memory_response = requests.post(
            os.environ.get('RETRIEVE_MEMORY_URL'),
            json={'customer_id': customer_id},
            timeout=30
        )
        
        memory_data = {}
        if memory_response.status_code == 200:
            memory_data = memory_response.json()
        
        # Build context-aware prompt
        system_prompt = build_system_prompt(memory_data)
        user_prompt = f"Customer message: {message}"
        
        # Generate AI response using Vertex AI
        ai_response = generate_ai_response(system_prompt, user_prompt)
        
        # Store conversation in Firestore
        conversation_id = store_conversation(
            customer_id, message, ai_response, memory_data.get('context', {})
        )
        
        response = {
            'conversation_id': conversation_id,
            'customer_id': customer_id,
            'message': message,
            'ai_response': ai_response,
            'memory_context_used': bool(memory_data),
            'timestamp': datetime.now().isoformat()
        }
        
        headers = {'Access-Control-Allow-Origin': '*'}
        return (response, 200, headers)
        
    except Exception as e:
        return {'error': str(e)}, 500

def build_system_prompt(memory_data):
    """Build context-aware system prompt using memory data."""
    base_prompt = """You are a helpful customer support agent. You provide 
    professional, empathetic, and solution-focused responses to customer 
    inquiries.
    
    """
    
    if memory_data and memory_data.get('conversations'):
        context = memory_data.get('context', {})
        conversations = memory_data.get('conversations', [])
        
        base_prompt += f"""
Customer Context:
- Total previous conversations: {context.get('total_conversations', 0)}
- Unresolved issues: {context.get('unresolved_issues', 0)}
- Recent topics: {', '.join(context.get('recent_topics', [])[:2])}

Recent conversation history:
"""
        
        for conv in conversations[:3]:
            base_prompt += f"- Customer: {conv.get('message', '')[:100]}...\n"
            base_prompt += f"  Agent: {conv.get('response', '')[:100]}...\n"
        
        base_prompt += "\nUse this context to provide personalized, relevant responses."
    
    return base_prompt

def generate_ai_response(system_prompt, user_prompt):
    """Generate AI response using Vertex AI Gemini."""
    try:
        model = GenerativeModel("gemini-1.5-flash")
        
        full_prompt = f"{system_prompt}\n\n{user_prompt}"
        
        response = model.generate_content(
            full_prompt,
            generation_config={
                "max_output_tokens": 1024,
                "temperature": 0.7,
                "top_p": 0.8
            }
        )
        return response.text
        
    except Exception as e:
        return f"I apologize, but I'm experiencing technical difficulties. Please try again or contact our support team directly. Error: {str(e)}"

def store_conversation(customer_id, message, response, context):
    """Store conversation in Firestore."""
    try:
        db = firestore.Client()
        
        conversation_data = {
            'customer_id': customer_id,
            'message': message,
            'response': response,
            'timestamp': datetime.now(),
            'context_used': context,
            'resolved': False,  # Can be updated later
            'sentiment': 'neutral'  # Can be enhanced with sentiment analysis
        }
        
        doc_ref = db.collection('conversations').add(conversation_data)
        return doc_ref[1].id
        
    except Exception as e:
        print(f"Error storing conversation: {e}")
        return None
EOF
    
    log_success "Function source code prepared"
}

# Function to deploy Cloud Functions
deploy_functions() {
    log_info "Deploying Cloud Functions..."
    
    # Deploy memory retrieval function
    log_info "Deploying memory retrieval function..."
    cd "${TEMP_DIR}/memory-retrieval"
    
    if gcloud functions deploy "${MEMORY_FUNCTION_NAME}" \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point retrieve_memory \
        --memory 256MB \
        --timeout 60s \
        --quiet; then
        log_success "Memory retrieval function deployed"
    else
        log_error "Failed to deploy memory retrieval function"
        exit 1
    fi
    
    # Get memory function URL
    export RETRIEVE_MEMORY_URL=$(gcloud functions describe "${MEMORY_FUNCTION_NAME}" \
        --format="value(httpsTrigger.url)")
    
    log_info "Memory function URL: ${RETRIEVE_MEMORY_URL}"
    
    # Deploy main chat function
    log_info "Deploying main chat function..."
    cd "${TEMP_DIR}/chat-function"
    
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point support_chat \
        --memory 512MB \
        --timeout 300s \
        --set-env-vars="RETRIEVE_MEMORY_URL=${RETRIEVE_MEMORY_URL}" \
        --quiet; then
        log_success "Main chat function deployed"
    else
        log_error "Failed to deploy main chat function"
        exit 1
    fi
    
    # Get chat function URL
    export CHAT_FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
        --format="value(httpsTrigger.url)")
    
    log_info "Chat function URL: ${CHAT_FUNCTION_URL}"
}

# Function to create web interface
create_web_interface() {
    log_info "Creating web interface for testing..."
    
    mkdir -p "${TEMP_DIR}/web-interface"
    
    cat > "${TEMP_DIR}/web-interface/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Customer Support with Memory</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            max-width: 800px; 
            margin: 0 auto; 
            padding: 20px; 
        }
        .chat-container { 
            border: 1px solid #ddd; 
            height: 400px; 
            overflow-y: auto; 
            padding: 10px; 
            margin: 10px 0; 
        }
        .message { 
            margin: 10px 0; 
            padding: 10px; 
            border-radius: 5px; 
        }
        .customer { 
            background-color: #e3f2fd; 
            text-align: right; 
        }
        .agent { 
            background-color: #f3e5f5; 
        }
        input[type="text"] { 
            width: 70%; 
            padding: 10px; 
        }
        button { 
            padding: 10px 20px; 
            background-color: #4285f4; 
            color: white; 
            border: none; 
            border-radius: 5px; 
            cursor: pointer; 
        }
        .customer-id { 
            margin: 10px 0; 
        }
    </style>
</head>
<body>
    <h1>AI Customer Support with Memory</h1>
    
    <div class="customer-id">
        <label for="customerId">Customer ID:</label>
        <input type="text" id="customerId" value="customer-123" placeholder="Enter customer ID">
    </div>
    
    <div class="chat-container" id="chatContainer"></div>
    
    <div>
        <input type="text" id="messageInput" placeholder="Type your message here..." onkeypress="handleKeyPress(event)">
        <button onclick="sendMessage()">Send</button>
    </div>
    
    <script>
        const CHAT_FUNCTION_URL = '${CHAT_FUNCTION_URL}';
        
        function handleKeyPress(event) {
            if (event.key === 'Enter') {
                sendMessage();
            }
        }
        
        async function sendMessage() {
            const customerId = document.getElementById('customerId').value;
            const messageInput = document.getElementById('messageInput');
            const message = messageInput.value.trim();
            
            if (!message || !customerId) {
                alert('Please enter both customer ID and message');
                return;
            }
            
            // Add customer message to chat
            addMessageToChat('customer', message);
            messageInput.value = '';
            
            try {
                const response = await fetch(CHAT_FUNCTION_URL, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({
                        customer_id: customerId,
                        message: message
                    })
                });
                
                const data = await response.json();
                
                if (data.ai_response) {
                    addMessageToChat('agent', data.ai_response);
                    if (data.memory_context_used) {
                        addMessageToChat('system', '🧠 Memory context used for personalized response');
                    }
                } else {
                    addMessageToChat('agent', 'Sorry, I encountered an error. Please try again.');
                }
            } catch (error) {
                addMessageToChat('agent', 'Sorry, I encountered a technical error. Please try again.');
                console.error('Error:', error);
            }
        }
        
        function addMessageToChat(sender, message) {
            const chatContainer = document.getElementById('chatContainer');
            const messageDiv = document.createElement('div');
            messageDiv.className = \`message \${sender}\`;
            
            if (sender === 'system') {
                messageDiv.style.backgroundColor = '#fff3e0';
                messageDiv.style.fontStyle = 'italic';
                messageDiv.style.textAlign = 'center';
            }
            
            messageDiv.textContent = message;
            chatContainer.appendChild(messageDiv);
            chatContainer.scrollTop = chatContainer.scrollHeight;
        }
    </script>
</body>
</html>
EOF
    
    log_success "Web interface created at ${TEMP_DIR}/web-interface/index.html"
}

# Function to run validation tests
run_validation() {
    log_info "Running validation tests..."
    
    # Test memory retrieval function
    log_info "Testing memory retrieval function..."
    local memory_test_result=$(curl -s -X POST "${RETRIEVE_MEMORY_URL}" \
        -H "Content-Type: application/json" \
        -d '{"customer_id": "test-customer-001"}' \
        -w "%{http_code}")
    
    if [[ "${memory_test_result: -3}" == "200" ]]; then
        log_success "Memory retrieval function test passed"
    else
        log_warning "Memory retrieval function test failed with HTTP ${memory_test_result: -3}"
    fi
    
    # Test chat function
    log_info "Testing chat function..."
    local chat_test_result=$(curl -s -X POST "${CHAT_FUNCTION_URL}" \
        -H "Content-Type: application/json" \
        -d '{"customer_id": "test-customer-001", "message": "Hello, I need help with my order"}' \
        -w "%{http_code}")
    
    if [[ "${chat_test_result: -3}" == "200" ]]; then
        log_success "Chat function test passed"
    else
        log_warning "Chat function test failed with HTTP ${chat_test_result: -3}"
    fi
    
    # Check Firestore
    log_info "Checking Firestore database..."
    if gcloud firestore databases list --filter="name:projects/${PROJECT_ID}/databases/(default)" --format="value(name)" | grep -q .; then
        log_success "Firestore database verification passed"
    else
        log_warning "Firestore database verification failed"
    fi
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local deployment_file="${PWD}/deployment-info.txt"
    
    cat > "${deployment_file}" << EOF
# Persistent AI Customer Support Deployment Information
# Generated on: $(date)

PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
FUNCTION_NAME=${FUNCTION_NAME}
MEMORY_FUNCTION_NAME=${MEMORY_FUNCTION_NAME}
FIRESTORE_DATABASE=${FIRESTORE_DATABASE}

# Function URLs
RETRIEVE_MEMORY_URL=${RETRIEVE_MEMORY_URL}
CHAT_FUNCTION_URL=${CHAT_FUNCTION_URL}

# Web Interface Location
WEB_INTERFACE_PATH=${TEMP_DIR}/web-interface/index.html

# Cleanup Command
# To clean up all resources, run: ./destroy.sh

# Test Commands
# Test memory function:
# curl -X POST "${RETRIEVE_MEMORY_URL}" -H "Content-Type: application/json" -d '{"customer_id": "test-customer-001"}'

# Test chat function:
# curl -X POST "${CHAT_FUNCTION_URL}" -H "Content-Type: application/json" -d '{"customer_id": "test-customer-001", "message": "Hello, I need help"}'
EOF
    
    log_success "Deployment information saved to ${deployment_file}"
}

# Function to display final instructions
display_final_instructions() {
    log_success "Deployment completed successfully!"
    echo
    echo "=================================================================="
    echo "🚀 Persistent AI Customer Support Deployment Complete"
    echo "=================================================================="
    echo
    echo "📊 Project Information:"
    echo "   Project ID: ${PROJECT_ID}"
    echo "   Region: ${REGION}"
    echo
    echo "🔗 Function URLs:"
    echo "   Memory Retrieval: ${RETRIEVE_MEMORY_URL}"
    echo "   Chat Function: ${CHAT_FUNCTION_URL}"
    echo
    echo "🌐 Web Interface:"
    echo "   File: ${TEMP_DIR}/web-interface/index.html"
    echo "   Open this file in your browser to test the system"
    echo
    echo "🧪 Test Commands:"
    echo "   Test memory function:"
    echo "   curl -X POST \"${RETRIEVE_MEMORY_URL}\" \\"
    echo "        -H \"Content-Type: application/json\" \\"
    echo "        -d '{\"customer_id\": \"test-customer-001\"}'"
    echo
    echo "   Test chat function:"
    echo "   curl -X POST \"${CHAT_FUNCTION_URL}\" \\"
    echo "        -H \"Content-Type: application/json\" \\"
    echo "        -d '{\"customer_id\": \"test-customer-001\", \"message\": \"Hello, I need help\"}'"
    echo
    echo "🗑️  Cleanup:"
    echo "   To remove all resources: ./destroy.sh"
    echo
    echo "=================================================================="
}

# Function to cleanup temporary files
cleanup_temp() {
    if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR}" ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf "${TEMP_DIR}"
        log_success "Temporary files cleaned up"
    fi
}

# Trap to ensure cleanup on script exit
trap cleanup_temp EXIT

# Main deployment function
main() {
    log_info "Starting deployment of Persistent AI Customer Support with Agent Engine Memory..."
    
    # Check if running in dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "Running in dry-run mode - no resources will be created"
        check_prerequisites
        setup_environment
        log_success "Dry-run completed successfully"
        return 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    enable_apis
    create_firestore
    prepare_function_code
    deploy_functions
    create_web_interface
    run_validation
    save_deployment_info
    display_final_instructions
    
    log_success "Deployment completed successfully!"
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --create-project)
            CREATE_PROJECT="true"
            shift
            ;;
        --billing-account)
            BILLING_ACCOUNT_ID="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --project-id PROJECT_ID      Specify GCP project ID"
            echo "  --region REGION              Specify GCP region (default: us-central1)"
            echo "  --create-project             Create new project"
            echo "  --billing-account ACCOUNT    Billing account ID for new project"
            echo "  --dry-run                    Run without creating resources"
            echo "  --help                       Show this help message"
            echo
            echo "Environment variables:"
            echo "  PROJECT_ID                   GCP project ID"
            echo "  REGION                       GCP region"
            echo "  CREATE_PROJECT               Set to 'true' to create new project"
            echo "  BILLING_ACCOUNT_ID           Billing account for new project"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"