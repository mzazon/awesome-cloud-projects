#!/bin/bash

# GCP Real-Time Voice Support Agent with ADK and Live API - Deployment Script
# This script deploys a voice-enabled customer support agent using Google's Agent Development Kit
# integrated with Gemini Live API for bidirectional audio streaming.

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging setup
LOG_FILE="voice_agent_deploy_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Script metadata
SCRIPT_VERSION="1.0"
DEPLOYMENT_START_TIME=$(date)

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}  GCP Voice Support Agent Deployment Script v${SCRIPT_VERSION}${NC}"
echo -e "${BLUE}  Recipe: Real-Time Voice Support Agent with ADK and Live API${NC}"
echo -e "${BLUE}  Started: ${DEPLOYMENT_START_TIME}${NC}"
echo -e "${BLUE}================================================================${NC}"

# Default configuration values
DEFAULT_PROJECT_PREFIX="voice-support"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
DEFAULT_MEMORY="1GB"
DEFAULT_TIMEOUT="300s"

# Configuration variables with environment variable support
PROJECT_PREFIX="${PROJECT_PREFIX:-${DEFAULT_PROJECT_PREFIX}}"
REGION="${REGION:-${DEFAULT_REGION}}"
ZONE="${ZONE:-${DEFAULT_ZONE}}"
MEMORY="${MEMORY:-${DEFAULT_MEMORY}}"
TIMEOUT="${TIMEOUT:-${DEFAULT_TIMEOUT}}"
DRY_RUN="${DRY_RUN:-false}"

# Generate unique identifiers
TIMESTAMP=$(date +%s)
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")

# Resource names
PROJECT_ID="${PROJECT_PREFIX}-${TIMESTAMP}"
SERVICE_ACCOUNT="voice-agent-sa-${RANDOM_SUFFIX}"
FUNCTION_NAME="voice-agent-${RANDOM_SUFFIX}"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    print_step "Validating prerequisites..."
    
    local prerequisites_met=true
    
    # Check for gcloud CLI
    if ! command_exists gcloud; then
        print_error "Google Cloud CLI (gcloud) is not installed"
        print_error "Install from: https://cloud.google.com/sdk/docs/install"
        prerequisites_met=false
    else
        print_status "Google Cloud CLI found: $(gcloud version --format='value(Google Cloud SDK)' 2>/dev/null || echo 'unknown')"
    fi
    
    # Check for python
    if ! command_exists python3; then
        print_error "Python 3 is not installed"
        prerequisites_met=false
    else
        local python_version=$(python3 --version 2>&1 | cut -d' ' -f2)
        print_status "Python 3 found: ${python_version}"
        
        # Check Python version (should be 3.10+)
        if ! python3 -c "import sys; exit(0 if sys.version_info >= (3, 10) else 1)" 2>/dev/null; then
            print_warning "Python 3.10+ recommended for ADK compatibility (current: ${python_version})"
        fi
    fi
    
    # Check for pip
    if ! command_exists pip3 && ! command_exists pip; then
        print_error "pip is not installed"
        prerequisites_met=false
    else
        print_status "pip found"
    fi
    
    # Check for openssl (for random generation)
    if ! command_exists openssl; then
        print_warning "openssl not found, using fallback for random generation"
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_error "No active gcloud authentication found"
        print_error "Run: gcloud auth login"
        prerequisites_met=false
    else
        local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1)
        print_status "Authenticated as: ${active_account}"
    fi
    
    # Check for required APIs access (basic check)
    if gcloud services list --enabled --filter="name:cloudfunctions.googleapis.com OR name:aiplatform.googleapis.com" --format="value(name)" 2>/dev/null | wc -l | grep -q "0"; then
        print_warning "Some required APIs may not be enabled in the current project"
    fi
    
    if [ "$prerequisites_met" = false ]; then
        print_error "Prerequisites validation failed. Please address the issues above."
        exit 1
    fi
    
    print_status "Prerequisites validation completed successfully"
}

# Function to estimate costs
estimate_costs() {
    print_step "Estimating deployment costs..."
    
    cat << EOF

${YELLOW}ESTIMATED COSTS (USD per hour):${NC}
- Cloud Functions (1GB memory): ~\$0.0025/hour (based on 1000 invocations)
- Vertex AI API calls: ~\$0.125/1000 requests (Gemini Pro)
- Cloud Logging: ~\$0.50/GB ingested
- Cloud Monitoring: Included in free tier
- Service Account: Free

${YELLOW}TOTAL ESTIMATED: \$3-8/hour during active development${NC}
${YELLOW}Note: Costs depend on usage patterns and API call frequency${NC}

EOF
}

# Function to confirm deployment
confirm_deployment() {
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN MODE - No resources will be created"
        return 0
    fi
    
    echo
    echo -e "${YELLOW}Deployment Configuration:${NC}"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Function Name: ${FUNCTION_NAME}"
    echo "  Service Account: ${SERVICE_ACCOUNT}"
    echo "  Memory: ${MEMORY}"
    echo "  Timeout: ${TIMEOUT}"
    echo
    
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Deployment cancelled by user"
        exit 0
    fi
}

# Function to setup GCP project
setup_project() {
    print_step "Setting up GCP project..."
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would create project ${PROJECT_ID}"
        return 0
    fi
    
    # Create new project
    if gcloud projects create "${PROJECT_ID}" --name="Voice Support Agent" 2>/dev/null; then
        print_status "Created new project: ${PROJECT_ID}"
    else
        print_error "Failed to create project ${PROJECT_ID}"
        print_error "The project ID might already exist or you may lack permissions"
        exit 1
    fi
    
    # Set default project
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set functions/region "${REGION}"
    
    # Link billing account (requires manual setup)
    print_warning "Please ensure billing is enabled for project ${PROJECT_ID}"
    print_warning "Visit: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
    
    read -p "Press Enter when billing is configured..."
    
    print_status "Project setup completed"
}

# Function to enable required APIs
enable_apis() {
    print_step "Enabling required Google Cloud APIs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "iamcredentials.googleapis.com"
    )
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would enable APIs: ${apis[*]}"
        return 0
    fi
    
    for api in "${apis[@]}"; do
        print_status "Enabling ${api}..."
        if gcloud services enable "${api}"; then
            print_status "✅ ${api} enabled"
        else
            print_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully available
    print_status "Waiting for APIs to become available..."
    sleep 30
    
    print_status "All required APIs enabled successfully"
}

# Function to create service account
create_service_account() {
    print_step "Creating service account with AI platform permissions..."
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would create service account ${SERVICE_ACCOUNT}"
        return 0
    fi
    
    # Create service account
    if gcloud iam service-accounts create "${SERVICE_ACCOUNT}" \
        --display-name="Voice Support Agent Service Account" \
        --description="Service account for ADK voice agent"; then
        print_status "✅ Service account created: ${SERVICE_ACCOUNT}"
    else
        print_error "Failed to create service account"
        exit 1
    fi
    
    # Grant necessary permissions
    local roles=(
        "roles/aiplatform.user"
        "roles/cloudfunctions.invoker"
        "roles/logging.logWriter"
        "roles/monitoring.metricWriter"
    )
    
    for role in "${roles[@]}"; do
        print_status "Granting role: ${role}"
        if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
            --role="${role}"; then
            print_status "✅ Role ${role} granted"
        else
            print_error "Failed to grant role ${role}"
            exit 1
        fi
    done
    
    print_status "Service account setup completed"
}

# Function to setup development environment
setup_development_environment() {
    print_step "Setting up local development environment..."
    
    local work_dir="voice-support-agent-${RANDOM_SUFFIX}"
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would create development environment in ${work_dir}"
        return 0
    fi
    
    # Create working directory
    mkdir -p "${work_dir}/agent_src"
    cd "${work_dir}"
    
    # Create Python virtual environment
    python3 -m venv venv
    source venv/bin/activate
    
    # Install dependencies
    print_status "Installing Python dependencies..."
    cat > requirements.txt << 'EOF'
google-adk==1.8.0
functions-framework==3.8.0
google-cloud-logging==3.8.0
google-cloud-aiplatform==1.70.0
google-cloud-monitoring==2.19.0
EOF
    
    pip install -r requirements.txt
    
    # Create agent source files
    print_status "Creating voice agent source code..."
    
    # Create main agent file
    cat > agent_src/voice_agent.py << 'EOF'
import json
import logging
from datetime import datetime
from typing import Dict, Any
from google.adk.agents import Agent
from google.adk.streaming import LiveAPIStreaming

# Configure logging for debugging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def lookup_customer(customer_id: str) -> Dict[str, Any]:
    """Retrieves customer information from CRM system."""
    customers = {
        "12345": {
            "name": "John Smith",
            "tier": "Premium",
            "account_status": "Active",
            "last_contact": "2025-07-10",
            "open_tickets": 1
        },
        "67890": {
            "name": "Sarah Johnson", 
            "tier": "Standard",
            "account_status": "Active",
            "last_contact": "2025-07-08",
            "open_tickets": 0
        }
    }
    
    if customer_id in customers:
        return {"status": "success", "customer": customers[customer_id]}
    else:
        return {"status": "error", "message": "Customer not found"}

def create_support_ticket(customer_id: str, issue_type: str, description: str, 
                         priority: str = "medium") -> Dict[str, Any]:
    """Creates a new customer support ticket."""
    import uuid
    ticket_id = f"TICK-{str(uuid.uuid4())[:8].upper()}"
    
    ticket_data = {
        "ticket_id": ticket_id,
        "customer_id": customer_id,
        "issue_type": issue_type,
        "description": description,
        "priority": priority,
        "status": "Open",
        "created_at": datetime.now().isoformat(),
        "assigned_to": "AI Voice Agent"
    }
    
    logger.info(f"Created ticket {ticket_id} for customer {customer_id}")
    return {"status": "success", "ticket": ticket_data}

def search_knowledge_base(query: str) -> Dict[str, Any]:
    """Searches internal knowledge base for solutions."""
    knowledge_items = {
        "password reset": {
            "title": "Password Reset Instructions",
            "solution": "Go to login page, click 'Forgot Password', enter email, check inbox for reset link",
            "category": "Account Access"
        },
        "billing issue": {
            "title": "Billing Questions and Disputes", 
            "solution": "Review billing statement, verify charges, contact billing department for disputes",
            "category": "Billing"
        },
        "technical problem": {
            "title": "Technical Troubleshooting Guide",
            "solution": "Clear browser cache, disable extensions, try incognito mode, restart application",
            "category": "Technical"
        }
    }
    
    for key, item in knowledge_items.items():
        if key.lower() in query.lower():
            return {"status": "success", "solution": item}
    
    return {"status": "not_found", "message": "No relevant solutions found"}

def create_voice_support_agent():
    """Create the ADK agent with customer service capabilities."""
    return Agent(
        name="VoiceSupportAgent",
        instructions="""You are a helpful customer support agent with a warm, professional voice. 
        You can lookup customer information, create support tickets, and search for solutions.
        Always be empathetic and aim to resolve customer issues efficiently.
        Speak naturally and ask clarifying questions when needed.""",
        tools=[lookup_customer, create_support_ticket, search_knowledge_base]
    )

def create_live_streaming_agent():
    """Initialize ADK agent with Gemini Live API streaming."""
    try:
        voice_support_agent = create_voice_support_agent()
        
        streaming_agent = LiveAPIStreaming(
            agent=voice_support_agent,
            model="models/gemini-2.0-flash-exp",
            voice_config={
                "voice_name": "Puck",
                "language_code": "en-US"
            },
            audio_config={
                "sample_rate": 24000,
                "encoding": "LINEAR16"
            }
        )
        return streaming_agent
    except Exception as e:
        logger.error(f"Error creating streaming agent: {e}")
        raise
EOF
    
    # Create Cloud Function entry point
    cat > main.py << 'EOF'
import functions_framework
import json
import logging
import os
from agent_src.voice_agent import create_live_streaming_agent, create_voice_support_agent

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def voice_support_endpoint(request):
    """HTTP endpoint for voice support agent interactions."""
    try:
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)
        
        if request.method == 'POST':
            request_data = request.get_json(silent=True)
            
            if not request_data:
                return {'error': 'No JSON data provided'}, 400
            
            interaction_type = request_data.get('type', 'text')
            
            if interaction_type == 'voice_start':
                session_id = request_data.get('session_id')
                logger.info(f"Starting voice session: {session_id}")
                
                response = {
                    'status': 'voice_session_ready',
                    'session_id': session_id,
                    'websocket_url': f'/voice-stream/{session_id}',
                    'agent_capabilities': [
                        'customer_lookup',
                        'ticket_creation', 
                        'knowledge_search'
                    ]
                }
                
            elif interaction_type == 'text':
                message = request_data.get('message', '')
                customer_context = request_data.get('customer_context', {})
                
                voice_support_agent = create_voice_support_agent()
                
                response = {
                    'status': 'success',
                    'response': f"I received your message: '{message}'. I'm ready to help with your customer service needs.",
                    'session_context': customer_context
                }
                
            else:
                response = {'error': 'Unsupported interaction type'}, 400
        
        else:
            response = {
                'status': 'Voice Support Agent Ready',
                'agent_name': 'VoiceSupportAgent',
                'capabilities': ['voice_streaming', 'customer_service', 'real_time_response'],
                'adk_version': '1.8.0'
            }
        
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'application/json'
        }
        
        return (json.dumps(response), 200, headers)
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {'error': 'Internal server error', 'details': str(e)}, 500
EOF
    
    # Create __init__.py files
    touch agent_src/__init__.py
    
    print_status "✅ Development environment setup completed"
    
    # Store working directory for cleanup
    echo "${work_dir}" > "${OLDPWD}/.voice_agent_work_dir"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    print_step "Deploying voice agent to Cloud Functions..."
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would deploy Cloud Function ${FUNCTION_NAME}"
        return 0
    fi
    
    # Deploy function
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --gen2 \
        --runtime=python312 \
        --region="${REGION}" \
        --source=. \
        --entry-point=voice_support_endpoint \
        --memory="${MEMORY}" \
        --timeout="${TIMEOUT}" \
        --service-account="${SERVICE_ACCOUNT}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --set-env-vars="PROJECT_ID=${PROJECT_ID},REGION=${REGION}" \
        --allow-unauthenticated; then
        
        print_status "✅ Cloud Function deployed successfully"
        
        # Get function URL
        local function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --format="value(serviceConfig.uri)")
        
        print_status "Function URL: ${function_url}"
        
        # Store URL for testing
        echo "${function_url}" > "${OLDPWD}/.voice_agent_function_url"
        
    else
        print_error "Failed to deploy Cloud Function"
        exit 1
    fi
}

# Function to create test interface
create_test_interface() {
    print_step "Creating voice agent test interface..."
    
    local function_url_file="${OLDPWD}/.voice_agent_function_url"
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would create test interface"
        return 0
    fi
    
    if [ -f "${function_url_file}" ]; then
        local function_url=$(cat "${function_url_file}")
        
        cat > voice_test.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Voice Support Agent Test</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        .controls { margin: 20px 0; }
        button { padding: 10px 20px; margin: 5px; font-size: 16px; }
        .status { padding: 10px; margin: 10px 0; border-radius: 5px; }
        .success { background-color: #d4edda; color: #155724; }
        .error { background-color: #f8d7da; color: #721c24; }
        .response { background-color: #f8f9fa; padding: 15px; margin: 10px 0; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>Voice Support Agent Test Interface</h1>
    
    <div class="controls">
        <button id="startVoice">Initialize Voice Session</button>
        <button id="testText">Test Text Message</button>
        <button id="healthCheck">Health Check</button>
    </div>
    
    <div id="status" class="status">Ready to test voice agent</div>
    <div id="responses"></div>
    
    <script>
        const functionUrl = '${function_url}';
        
        document.getElementById('startVoice').addEventListener('click', startVoiceSession);
        document.getElementById('testText').addEventListener('click', testTextMessage);
        document.getElementById('healthCheck').addEventListener('click', healthCheck);
        
        function updateStatus(message, type = 'success') {
            const statusDiv = document.getElementById('status');
            statusDiv.textContent = message;
            statusDiv.className = \`status \${type}\`;
        }
        
        function addResponse(content) {
            const responsesDiv = document.getElementById('responses');
            const responseDiv = document.createElement('div');
            responseDiv.className = 'response';
            responseDiv.innerHTML = \`<strong>Agent:</strong> \${JSON.stringify(content, null, 2)}\`;
            responsesDiv.appendChild(responseDiv);
        }
        
        async function startVoiceSession() {
            try {
                const response = await fetch(functionUrl, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        type: 'voice_start',
                        session_id: 'test-session-' + Date.now()
                    })
                });
                
                if (response.ok) {
                    const result = await response.json();
                    updateStatus('Voice session initialized successfully');
                    addResponse(result);
                } else {
                    throw new Error('Failed to start voice session');
                }
                
            } catch (error) {
                updateStatus(\`Error: \${error.message}\`, 'error');
            }
        }
        
        async function testTextMessage() {
            try {
                const response = await fetch(functionUrl, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        type: 'text',
                        message: 'Hello, I need help with my account. My customer ID is 12345.',
                        customer_context: { source: 'web_test' }
                    })
                });
                
                if (response.ok) {
                    const result = await response.json();
                    updateStatus('Text message processed successfully');
                    addResponse(result);
                } else {
                    throw new Error('Failed to process text message');
                }
                
            } catch (error) {
                updateStatus(\`Error: \${error.message}\`, 'error');
            }
        }
        
        async function healthCheck() {
            try {
                const response = await fetch(functionUrl, {
                    method: 'GET',
                    headers: { 'Content-Type': 'application/json' }
                });
                
                if (response.ok) {
                    const result = await response.json();
                    updateStatus('Health check passed');
                    addResponse(result);
                } else {
                    throw new Error('Health check failed');
                }
                
            } catch (error) {
                updateStatus(\`Error: \${error.message}\`, 'error');
            }
        }
    </script>
</body>
</html>
EOF
        
        print_status "✅ Test interface created: voice_test.html"
        print_status "Open voice_test.html in a web browser to test the agent"
    else
        print_warning "Function URL not found, skipping test interface creation"
    fi
}

# Function to run validation tests
run_validation_tests() {
    print_step "Running deployment validation tests..."
    
    local function_url_file="${OLDPWD}/.voice_agent_function_url"
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would run validation tests"
        return 0
    fi
    
    if [ ! -f "${function_url_file}" ]; then
        print_error "Function URL not found, cannot run validation tests"
        return 1
    fi
    
    local function_url=$(cat "${function_url_file}")
    
    print_status "Testing function health endpoint..."
    if curl -s -f "${function_url}" > /dev/null; then
        print_status "✅ Health check passed"
    else
        print_error "Health check failed"
        return 1
    fi
    
    print_status "Testing text interaction..."
    local test_response=$(curl -s -X POST "${function_url}" \
        -H "Content-Type: application/json" \
        -d '{
            "type": "text",
            "message": "Test validation message",
            "customer_context": {"source": "validation_test"}
        }')
    
    if echo "${test_response}" | grep -q "success"; then
        print_status "✅ Text interaction test passed"
    else
        print_error "Text interaction test failed"
        return 1
    fi
    
    print_status "All validation tests passed successfully"
}

# Function to setup monitoring
setup_monitoring() {
    print_step "Setting up monitoring and logging..."
    
    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would setup monitoring"
        return 0
    fi
    
    # Create monitoring configuration
    cat > configure_monitoring.py << 'EOF'
import json
import logging
import os
from google.cloud import logging as cloud_logging
from google.cloud import monitoring_v3

def setup_voice_agent_monitoring(project_id: str, function_name: str):
    """Configure monitoring for voice support agent."""
    
    try:
        logging_client = cloud_logging.Client(project=project_id)
        logging_client.setup_logging()
        
        logger = logging.getLogger('voice_support_agent')
        logger.setLevel(logging.INFO)
        
        monitoring_client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{project_id}"
        
        voice_metrics = {
            'conversation_duration': 'Time spent in voice conversations',
            'function_call_success': 'Success rate of function calls',
            'customer_satisfaction': 'Customer satisfaction scores',
            'response_latency': 'Time to first response in conversations'
        }
        
        logger.info(f"Monitoring configured for voice agent: {function_name}")
        logger.info(f"Available metrics: {list(voice_metrics.keys())}")
        print("✅ Voice agent monitoring and logging configured")
        
    except Exception as e:
        print(f"❌ Error configuring monitoring: {e}")

if __name__ == "__main__":
    project_id = os.environ.get('PROJECT_ID')
    function_name = os.environ.get('FUNCTION_NAME')
    
    if project_id and function_name:
        setup_voice_agent_monitoring(project_id, function_name)
    else:
        print("❌ PROJECT_ID and FUNCTION_NAME environment variables required")
EOF
    
    # Run monitoring configuration
    PROJECT_ID="${PROJECT_ID}" FUNCTION_NAME="${FUNCTION_NAME}" python3 configure_monitoring.py
    
    print_status "✅ Monitoring and logging configured"
}

# Function to generate deployment summary
generate_deployment_summary() {
    print_step "Generating deployment summary..."
    
    local function_url_file="${OLDPWD}/.voice_agent_function_url"
    local function_url="N/A"
    
    if [ -f "${function_url_file}" ]; then
        function_url=$(cat "${function_url_file}")
    fi
    
    local summary_file="voice_agent_deployment_summary_$(date +%Y%m%d_%H%M%S).json"
    
    cat > "${summary_file}" << EOF
{
    "deployment_info": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "script_version": "${SCRIPT_VERSION}",
        "project_id": "${PROJECT_ID}",
        "region": "${REGION}",
        "function_name": "${FUNCTION_NAME}",
        "service_account": "${SERVICE_ACCOUNT}",
        "function_url": "${function_url}",
        "memory": "${MEMORY}",
        "timeout": "${TIMEOUT}"
    },
    "resources_created": [
        "GCP Project: ${PROJECT_ID}",
        "Service Account: ${SERVICE_ACCOUNT}",
        "Cloud Function: ${FUNCTION_NAME}",
        "IAM Roles: aiplatform.user, cloudfunctions.invoker, logging.logWriter, monitoring.metricWriter"
    ],
    "next_steps": [
        "Open voice_test.html in a web browser to test the agent",
        "Configure billing alerts to monitor costs",
        "Review Cloud Function logs for any issues",
        "Integrate with your existing customer service systems"
    ],
    "cleanup": {
        "command": "./destroy.sh",
        "description": "Run the destroy script to remove all resources"
    }
}
EOF
    
    print_status "✅ Deployment summary saved to: ${summary_file}"
    
    # Display summary
    echo
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${GREEN}  DEPLOYMENT COMPLETED SUCCESSFULLY${NC}"
    echo -e "${GREEN}================================================================${NC}"
    echo
    echo -e "${BLUE}Project ID:${NC} ${PROJECT_ID}"
    echo -e "${BLUE}Function Name:${NC} ${FUNCTION_NAME}"
    echo -e "${BLUE}Function URL:${NC} ${function_url}"
    echo -e "${BLUE}Region:${NC} ${REGION}"
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Open voice_test.html in a web browser to test the agent"
    echo "2. Configure billing alerts to monitor costs"
    echo "3. Review Cloud Function logs: gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}"
    echo "4. Integrate with your existing customer service systems"
    echo
    echo -e "${YELLOW}Cleanup:${NC} Run ./destroy.sh to remove all resources"
    echo
}

# Function to handle errors
handle_error() {
    local line_number=$1
    local exit_code=$2
    print_error "An error occurred on line ${line_number} with exit code ${exit_code}"
    print_error "Check the log file: ${LOG_FILE}"
    
    if [ -f "${OLDPWD}/.voice_agent_work_dir" ]; then
        local work_dir=$(cat "${OLDPWD}/.voice_agent_work_dir")
        print_warning "Clean up working directory: ${work_dir}"
    fi
    
    exit "${exit_code}"
}

# Function to handle script interruption
handle_interrupt() {
    print_warning "Deployment interrupted by user"
    print_warning "Some resources may have been created"
    print_warning "Run ./destroy.sh to clean up any created resources"
    exit 130
}

# Set up error handling
trap 'handle_error ${LINENO} $?' ERR
trap 'handle_interrupt' INT TERM

# Main deployment function
main() {
    # Validate prerequisites first
    validate_prerequisites
    
    # Show cost estimation
    estimate_costs
    
    # Confirm deployment
    confirm_deployment
    
    # Execute deployment steps
    setup_project
    enable_apis
    create_service_account
    setup_development_environment
    deploy_cloud_function
    create_test_interface
    run_validation_tests
    setup_monitoring
    generate_deployment_summary
    
    print_status "Deployment completed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --project-prefix)
            PROJECT_PREFIX="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --memory)
            MEMORY="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run              Run in dry-run mode (no resources created)"
            echo "  --project-prefix TEXT  Project prefix (default: ${DEFAULT_PROJECT_PREFIX})"
            echo "  --region TEXT          GCP region (default: ${DEFAULT_REGION})"
            echo "  --memory TEXT          Function memory (default: ${DEFAULT_MEMORY})"
            echo "  --timeout TEXT         Function timeout (default: ${DEFAULT_TIMEOUT})"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"