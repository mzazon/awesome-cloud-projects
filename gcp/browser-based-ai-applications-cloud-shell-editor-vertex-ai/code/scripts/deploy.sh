#!/bin/bash

#######################################
# Browser-Based AI Applications with Cloud Shell Editor and Vertex AI
# Deployment Script for GCP
# 
# This script deploys the complete infrastructure for developing
# browser-based AI applications using Cloud Shell Editor and Vertex AI
#######################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/ai-app-deploy-$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=false
FORCE=false

#######################################
# Print colored output
#######################################
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

#######################################
# Display usage information
#######################################
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy browser-based AI application infrastructure on Google Cloud Platform

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           GCP Region (default: us-central1)
    -s, --service-name NAME       Cloud Run service name (default: ai-chat-assistant)
    -d, --dry-run                 Show what would be deployed without executing
    -f, --force                   Force deployment without confirmation
    -h, --help                    Display this help message

EXAMPLES:
    $0 --project-id my-ai-project
    $0 --project-id my-ai-project --region us-east1 --service-name my-ai-app
    $0 --project-id my-ai-project --dry-run

EOF
}

#######################################
# Parse command line arguments
#######################################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -s|--service-name)
                SERVICE_NAME="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Set defaults
    REGION="${REGION:-us-central1}"
    SERVICE_NAME="${SERVICE_NAME:-ai-chat-assistant}"

    # Validate required parameters
    if [[ -z "${PROJECT_ID:-}" ]]; then
        print_error "Project ID is required. Use --project-id option."
        usage
        exit 1
    fi
}

#######################################
# Check prerequisites
#######################################
check_prerequisites() {
    print_status "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "Google Cloud CLI (gcloud) is not installed"
        print_error "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        print_error "Install from: https://docs.docker.com/get-docker/"
        exit 1
    fi

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_error "No active gcloud authentication found"
        print_error "Run: gcloud auth login"
        exit 1
    fi

    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        print_error "Project '$PROJECT_ID' not found or not accessible"
        print_error "Verify project ID and permissions"
        exit 1
    fi

    print_success "Prerequisites check completed"
}

#######################################
# Set up environment variables
#######################################
setup_environment() {
    print_status "Setting up environment variables..."

    # Generate unique identifiers
    export RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 6)
    export REPO_NAME="ai-app-repo-${RANDOM_SUFFIX}"
    export BUILD_CONFIG="cloudbuild-${RANDOM_SUFFIX}.yaml"
    
    # Core configuration
    export PROJECT_ID="$PROJECT_ID"
    export REGION="$REGION"
    export SERVICE_NAME="$SERVICE_NAME"
    
    print_status "Environment configured:"
    print_status "  Project ID: $PROJECT_ID"
    print_status "  Region: $REGION"
    print_status "  Service Name: $SERVICE_NAME"
    print_status "  Repository: $REPO_NAME"
}

#######################################
# Configure GCP project
#######################################
configure_project() {
    print_status "Configuring GCP project..."

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY RUN] Would configure project $PROJECT_ID"
        return 0
    fi

    # Set project as default
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"

    print_success "Project configuration completed"
}

#######################################
# Enable required APIs
#######################################
enable_apis() {
    print_status "Enabling required Google Cloud APIs..."

    local apis=(
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
        "aiplatform.googleapis.com"
        "artifactregistry.googleapis.com"
        "secretmanager.googleapis.com"
        "containerregistry.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY RUN] Would enable APIs: ${apis[*]}"
        return 0
    fi

    for api in "${apis[@]}"; do
        print_status "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            print_success "Enabled $api"
        else
            print_error "Failed to enable $api"
            exit 1
        fi
    done

    # Wait for APIs to be fully available
    print_status "Waiting for APIs to be fully available..."
    sleep 30

    print_success "All required APIs enabled"
}

#######################################
# Create application directory structure
#######################################
create_app_structure() {
    print_status "Creating application directory structure..."

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY RUN] Would create application directory structure"
        return 0
    fi

    # Create project directory structure
    local app_dir="/tmp/$SERVICE_NAME"
    rm -rf "$app_dir" 2>/dev/null || true
    mkdir -p "$app_dir"/{app,tests,config,app/templates}
    
    cd "$app_dir"

    # Create requirements.txt
    cat > requirements.txt << 'EOF'
flask==3.0.0
google-cloud-aiplatform==1.45.0
google-cloud-secretmanager==2.18.1
gunicorn==21.2.0
requests==2.31.0
python-dotenv==1.0.0
vertexai==1.38.1
EOF

    # Create main application file
    cat > app/main.py << 'EOF'
from flask import Flask, request, jsonify, render_template
import os
import logging
from ai_config import VertexAIClient

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Initialize Vertex AI client
ai_client = VertexAIClient()

@app.route('/')
def home():
    return render_template('index.html')

@app.route('/api/chat', methods=['POST'])
def chat():
    try:
        data = request.get_json()
        user_message = data.get('message', '')
        
        if not user_message:
            return jsonify({'error': 'Message is required', 'status': 'error'}), 400
        
        # Generate AI response
        ai_response = ai_client.generate_response(user_message)
        
        # Analyze sentiment for additional insights
        sentiment = ai_client.analyze_sentiment(user_message)
        
        return jsonify({
            'response': ai_response,
            'sentiment': sentiment,
            'status': 'success'
        })
        
    except Exception as e:
        logger.error(f"Chat API error: {str(e)}")
        return jsonify({
            'error': 'Failed to process message',
            'status': 'error'
        }), 500

@app.route('/health')
def health():
    return jsonify({'status': 'healthy', 'service': 'ai-chat-assistant'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)
EOF

    # Create AI configuration file
    cat > app/ai_config.py << 'EOF'
import os
import vertexai
from vertexai.generative_models import GenerativeModel
import logging

logger = logging.getLogger(__name__)

class VertexAIClient:
    def __init__(self):
        self.project_id = os.getenv('GOOGLE_CLOUD_PROJECT')
        self.region = os.getenv('GOOGLE_CLOUD_REGION', 'us-central1')
        
        # Initialize Vertex AI
        vertexai.init(project=self.project_id, location=self.region)
        
        # Initialize Gemini model
        self.model = GenerativeModel('gemini-1.5-flash')
        
        logger.info(f"Vertex AI initialized for project: {self.project_id}")

    def generate_response(self, prompt, max_tokens=1000):
        """Generate AI response with error handling and optimization"""
        try:
            # Configure generation parameters for optimal performance
            generation_config = {
                "max_output_tokens": max_tokens,
                "temperature": 0.7,
                "top_p": 0.8,
            }
            
            response = self.model.generate_content(
                prompt,
                generation_config=generation_config
            )
            
            return response.text
            
        except Exception as e:
            logger.error(f"Vertex AI generation error: {str(e)}")
            return "I apologize, but I'm having trouble processing your request right now. Please try again."

    def analyze_sentiment(self, text):
        """Analyze sentiment using Vertex AI"""
        try:
            prompt = f"Analyze the sentiment of this text and respond with just: positive, negative, or neutral: {text}"
            response = self.generate_response(prompt, max_tokens=10)
            return response.strip().lower()
        except Exception as e:
            logger.error(f"Sentiment analysis error: {str(e)}")
            return "neutral"
EOF

    # Create HTML template
    cat > app/templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Chat Assistant</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            height: 100vh; display: flex; align-items: center; justify-content: center;
        }
        .chat-container {
            background: white; border-radius: 15px; box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            width: 90%; max-width: 600px; height: 80vh; display: flex; flex-direction: column;
        }
        .chat-header {
            background: #4285f4; color: white; padding: 20px; border-radius: 15px 15px 0 0;
            text-align: center; font-size: 1.2em; font-weight: bold;
        }
        .chat-messages {
            flex: 1; padding: 20px; overflow-y: auto; background: #f8f9fa;
        }
        .message {
            margin: 10px 0; padding: 12px 16px; border-radius: 18px; max-width: 80%;
        }
        .user-message {
            background: #e3f2fd; margin-left: auto; text-align: right;
        }
        .ai-message {
            background: #f1f3f4; margin-right: auto;
        }
        .chat-input {
            display: flex; padding: 20px; border-top: 1px solid #e0e0e0;
        }
        .chat-input input {
            flex: 1; padding: 12px; border: 1px solid #ddd; border-radius: 25px;
            outline: none; font-size: 16px;
        }
        .chat-input button {
            margin-left: 10px; padding: 12px 24px; background: #4285f4;
            color: white; border: none; border-radius: 25px; cursor: pointer;
        }
        .loading { opacity: 0.7; pointer-events: none; }
    </style>
</head>
<body>
    <div class="chat-container">
        <div class="chat-header">
            🤖 AI Chat Assistant - Powered by Vertex AI
        </div>
        <div id="chat-messages" class="chat-messages">
            <div class="message ai-message">
                Hello! I'm your AI assistant powered by Google's Vertex AI. How can I help you today?
            </div>
        </div>
        <div class="chat-input">
            <input type="text" id="user-input" placeholder="Type your message here..." />
            <button onclick="sendMessage()">Send</button>
        </div>
    </div>

    <script>
        async function sendMessage() {
            const input = document.getElementById('user-input');
            const message = input.value.trim();
            if (!message) return;

            // Add user message to chat
            addMessage(message, 'user');
            input.value = '';

            // Show loading state
            const chatContainer = document.querySelector('.chat-container');
            chatContainer.classList.add('loading');

            try {
                const response = await fetch('/api/chat', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ message: message })
                });

                const data = await response.json();
                
                if (data.status === 'success') {
                    addMessage(data.response, 'ai');
                } else {
                    addMessage('Sorry, I encountered an error. Please try again.', 'ai');
                }
            } catch (error) {
                addMessage('Connection error. Please check your internet connection.', 'ai');
            }

            chatContainer.classList.remove('loading');
        }

        function addMessage(text, sender) {
            const messagesDiv = document.getElementById('chat-messages');
            const messageDiv = document.createElement('div');
            messageDiv.className = `message ${sender}-message`;
            messageDiv.textContent = text;
            messagesDiv.appendChild(messageDiv);
            messagesDiv.scrollTop = messagesDiv.scrollHeight;
        }

        // Enable Enter key to send messages
        document.getElementById('user-input').addEventListener('keypress', function(e) {
            if (e.key === 'Enter') sendMessage();
        });
    </script>
</body>
</html>
EOF

    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ ./app/

# Set environment variables
ENV FLASK_APP=app.main:app
ENV PYTHONPATH=/app

# Expose port
EXPOSE 8080

# Run application with Gunicorn for production
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "120", "app.main:app"]
EOF

    # Create Cloud Build configuration
    cat > cloudbuild.yaml << EOF
steps:
  # Build the container image
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'gcr.io/\$PROJECT_ID/${SERVICE_NAME}:\$COMMIT_SHA', '.']

  # Push the container image to Container Registry
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'gcr.io/\$PROJECT_ID/${SERVICE_NAME}:\$COMMIT_SHA']

  # Deploy to Cloud Run
  - name: 'gcr.io/cloud-builders/gcloud'
    args:
      - 'run'
      - 'deploy'
      - '${SERVICE_NAME}'
      - '--image=gcr.io/\$PROJECT_ID/${SERVICE_NAME}:\$COMMIT_SHA'
      - '--region=${REGION}'
      - '--platform=managed'
      - '--allow-unauthenticated'
      - '--memory=1Gi'
      - '--cpu=1'
      - '--max-instances=10'
      - '--set-env-vars=GOOGLE_CLOUD_PROJECT=\$PROJECT_ID,GOOGLE_CLOUD_REGION=${REGION}'

substitutions:
  _SERVICE_NAME: '${SERVICE_NAME}'
  _REGION: '${REGION}'

options:
  logging: CLOUD_LOGGING_ONLY
EOF

    export APP_DIR="$app_dir"
    print_success "Application structure created in $app_dir"
}

#######################################
# Build and deploy the application
#######################################
deploy_application() {
    print_status "Building and deploying AI application..."

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY RUN] Would build and deploy application to Cloud Run"
        return 0
    fi

    cd "$APP_DIR"

    # Submit build to Cloud Build
    print_status "Submitting build to Cloud Build..."
    if gcloud builds submit \
        --config cloudbuild.yaml \
        --substitutions _SERVICE_NAME="$SERVICE_NAME",_REGION="$REGION" \
        --timeout=20m; then
        print_success "Application built and deployed successfully"
    else
        print_error "Build and deployment failed"
        exit 1
    fi

    # Get service URL
    local service_url
    service_url=$(gcloud run services describe "$SERVICE_NAME" \
        --region="$REGION" \
        --format="value(status.url)")
    
    export SERVICE_URL="$service_url"
    print_success "Service deployed at: $SERVICE_URL"
}

#######################################
# Validate deployment
#######################################
validate_deployment() {
    print_status "Validating deployment..."

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY RUN] Would validate deployment"
        return 0
    fi

    # Check service status
    print_status "Checking Cloud Run service status..."
    local status
    status=$(gcloud run services describe "$SERVICE_NAME" \
        --region="$REGION" \
        --format="value(status.conditions[0].type)")
    
    if [[ "$status" != "Ready" ]]; then
        print_error "Service is not ready. Status: $status"
        exit 1
    fi

    # Test health endpoint
    print_status "Testing health endpoint..."
    if curl -s -f "$SERVICE_URL/health" > /dev/null; then
        print_success "Health check passed"
    else
        print_warning "Health check failed - service may still be starting"
    fi

    # Test AI functionality
    print_status "Testing AI chat functionality..."
    local response
    response=$(curl -s -X POST "$SERVICE_URL/api/chat" \
        -H "Content-Type: application/json" \
        -d '{"message": "Hello, can you help me with Google Cloud?"}' \
        --max-time 30)
    
    if echo "$response" | grep -q '"status":"success"'; then
        print_success "AI functionality test passed"
    else
        print_warning "AI functionality test failed - check logs for details"
    fi

    print_success "Deployment validation completed"
}

#######################################
# Display deployment summary
#######################################
display_summary() {
    print_status "Deployment Summary"
    echo "================================"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Service Name: $SERVICE_NAME"
    if [[ "$DRY_RUN" == "false" && -n "${SERVICE_URL:-}" ]]; then
        echo "Service URL: $SERVICE_URL"
        echo ""
        echo "Next Steps:"
        echo "1. Open $SERVICE_URL in your browser"
        echo "2. Test the AI chat functionality"
        echo "3. Check Cloud Run logs: gcloud run logs read $SERVICE_NAME --region=$REGION"
        echo "4. Monitor costs in Cloud Console billing section"
    fi
    echo "================================"
}

#######################################
# Cleanup function for error handling
#######################################
cleanup_on_error() {
    print_error "Deployment failed. Cleaning up..."
    
    # Remove temporary files
    if [[ -n "${APP_DIR:-}" && -d "$APP_DIR" ]]; then
        rm -rf "$APP_DIR"
    fi
    
    exit 1
}

#######################################
# Main deployment function
#######################################
main() {
    print_status "Starting AI application deployment on Google Cloud Platform"
    print_status "Log file: $LOG_FILE"

    # Set up error handling
    trap cleanup_on_error ERR

    # Parse command line arguments
    parse_args "$@"

    # Show deployment confirmation
    if [[ "$FORCE" == "false" && "$DRY_RUN" == "false" ]]; then
        echo
        print_warning "This will deploy AI application infrastructure to Google Cloud Platform"
        print_warning "Project: $PROJECT_ID"
        print_warning "Region: $REGION"
        print_warning "Service: $SERVICE_NAME"
        echo
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deployment cancelled by user"
            exit 0
        fi
    fi

    # Execute deployment steps
    check_prerequisites
    setup_environment
    configure_project
    enable_apis
    create_app_structure
    deploy_application
    validate_deployment
    display_summary

    if [[ "$DRY_RUN" == "false" ]]; then
        print_success "AI application deployment completed successfully!"
        print_status "Access your application at: $SERVICE_URL"
    else
        print_success "Dry run completed - no resources were created"
    fi
}

# Execute main function with all arguments
main "$@"