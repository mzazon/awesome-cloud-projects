#!/bin/bash

# Email Automation with Agent Builder and MCP - Deployment Script
# This script deploys the complete email automation infrastructure on Google Cloud Platform

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Configuration variables
PROJECT_ID=""
REGION="us-central1"
ZONE="us-central1-a"
RANDOM_SUFFIX=""
SERVICE_ACCOUNT_EMAIL=""
DRY_RUN=false
FORCE_DEPLOY=false

# Function definitions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() {
    log "INFO" "${BLUE}$*${NC}"
}

success() {
    log "SUCCESS" "${GREEN}✅ $*${NC}"
}

warning() {
    log "WARNING" "${YELLOW}⚠️  $*${NC}"
}

error() {
    log "ERROR" "${RED}❌ $*${NC}"
}

fatal() {
    error "$*"
    exit 1
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Email Automation with Agent Builder and MCP on Google Cloud Platform

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           GCP region (default: us-central1)
    -z, --zone ZONE               GCP zone (default: us-central1-a)
    -d, --dry-run                 Show what would be deployed without making changes
    -f, --force                   Force deployment even if resources exist
    -h, --help                    Show this help message

EXAMPLES:
    $0 --project-id my-project-123
    $0 --project-id my-project-123 --region us-west1 --dry-run
    $0 --project-id my-project-123 --force

EOF
}

parse_arguments() {
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
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_DEPLOY=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                fatal "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        fatal "Project ID is required. Use --project-id or see --help for usage."
    fi
}

check_prerequisites() {
    info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        fatal "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi

    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        fatal "curl is not installed. Please install curl."
    fi

    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        fatal "openssl is not installed. Please install openssl."
    fi

    # Check if python3 is installed
    if ! command -v python3 &> /dev/null; then
        fatal "python3 is not installed. Please install Python 3.11 or later."
    fi

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 &> /dev/null; then
        fatal "No active gcloud authentication found. Please run 'gcloud auth login'"
    fi

    # Verify project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        fatal "Project '$PROJECT_ID' not found or not accessible. Please check project ID and permissions."
    fi

    success "All prerequisites check passed"
}

save_state() {
    local key="$1"
    local value="$2"
    
    # Create state file if it doesn't exist
    touch "$STATE_FILE"
    
    # Remove existing key and add new value
    grep -v "^${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
    echo "${key}=${value}" >> "${STATE_FILE}.tmp"
    mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

load_state() {
    local key="$1"
    
    if [[ -f "$STATE_FILE" ]]; then
        grep "^${key}=" "$STATE_FILE" | cut -d'=' -f2- || true
    fi
}

execute_command() {
    local cmd="$*"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would execute: $cmd"
        return 0
    fi
    
    info "Executing: $cmd"
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        return 0
    else
        local exit_code=$?
        error "Command failed with exit code $exit_code: $cmd"
        return $exit_code
    fi
}

setup_environment() {
    info "Setting up environment variables..."
    
    # Generate unique suffix if not already set
    if [[ -z "$RANDOM_SUFFIX" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
        save_state "RANDOM_SUFFIX" "$RANDOM_SUFFIX"
    fi
    
    SERVICE_ACCOUNT_EMAIL="email-automation-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Set gcloud defaults
    execute_command "gcloud config set project ${PROJECT_ID}"
    execute_command "gcloud config set compute/region ${REGION}"
    execute_command "gcloud config set compute/zone ${ZONE}"
    
    # Save configuration to state
    save_state "PROJECT_ID" "$PROJECT_ID"
    save_state "REGION" "$REGION"
    save_state "ZONE" "$ZONE"
    save_state "SERVICE_ACCOUNT_EMAIL" "$SERVICE_ACCOUNT_EMAIL"
    
    success "Environment configured: Project=${PROJECT_ID}, Region=${REGION}"
}

enable_apis() {
    info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "gmail.googleapis.com"
        "secretmanager.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "pubsub.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        info "Enabling API: $api"
        execute_command "gcloud services enable $api"
    done
    
    success "All required APIs enabled"
}

create_service_account() {
    info "Creating service account for email automation..."
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" &> /dev/null; then
        if [[ "$FORCE_DEPLOY" != "true" ]]; then
            warning "Service account already exists. Use --force to recreate."
            return 0
        else
            info "Force deploy enabled. Recreating service account..."
            execute_command "gcloud iam service-accounts delete ${SERVICE_ACCOUNT_EMAIL} --quiet"
        fi
    fi
    
    execute_command "gcloud iam service-accounts create email-automation-sa \
        --description='Service account for email automation' \
        --display-name='Email Automation'"
    
    # Grant necessary permissions
    local roles=(
        "roles/aiplatform.user"
        "roles/secretmanager.secretAccessor"
        "roles/pubsub.publisher"
        "roles/pubsub.subscriber"
        "roles/cloudfunctions.invoker"
        "roles/logging.logWriter"
    )
    
    for role in "${roles[@]}"; do
        info "Granting role: $role"
        execute_command "gcloud projects add-iam-policy-binding ${PROJECT_ID} \
            --member='serviceAccount:${SERVICE_ACCOUNT_EMAIL}' \
            --role='$role'"
    done
    
    success "Service account created and configured: $SERVICE_ACCOUNT_EMAIL"
}

create_pubsub_resources() {
    info "Creating Pub/Sub resources for Gmail notifications..."
    
    # Create Pub/Sub topic
    if gcloud pubsub topics describe gmail-notifications &> /dev/null; then
        if [[ "$FORCE_DEPLOY" != "true" ]]; then
            warning "Pub/Sub topic already exists. Use --force to recreate."
        else
            info "Recreating Pub/Sub topic..."
            execute_command "gcloud pubsub topics delete gmail-notifications --quiet"
            execute_command "gcloud pubsub topics create gmail-notifications"
        fi
    else
        execute_command "gcloud pubsub topics create gmail-notifications"
    fi
    
    # Create webhook URL placeholder (will be updated after function deployment)
    local webhook_url="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/gmail-webhook"
    
    # Create subscription (will be updated after function deployment)
    if gcloud pubsub subscriptions describe gmail-webhook-sub &> /dev/null; then
        if [[ "$FORCE_DEPLOY" == "true" ]]; then
            execute_command "gcloud pubsub subscriptions delete gmail-webhook-sub --quiet"
        else
            warning "Pub/Sub subscription already exists. Use --force to recreate."
            success "Pub/Sub resources configured"
            return 0
        fi
    fi
    
    # Grant Pub/Sub publisher role to Gmail API service account
    execute_command "gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member='serviceAccount:gmail-api-push@system.gserviceaccount.com' \
        --role='roles/pubsub.publisher'"
    
    save_state "WEBHOOK_URL" "$webhook_url"
    success "Pub/Sub resources created: gmail-notifications topic"
}

deploy_cloud_functions() {
    info "Deploying Cloud Functions..."
    
    local functions_dir="${SCRIPT_DIR}/../functions"
    
    # Create functions directory structure if it doesn't exist
    mkdir -p "$functions_dir"
    
    # Deploy Gmail webhook function
    deploy_gmail_webhook_function
    
    # Deploy MCP integration function
    deploy_mcp_integration_function
    
    # Deploy response generator function
    deploy_response_generator_function
    
    # Deploy workflow orchestration function
    deploy_workflow_function
    
    # Update Pub/Sub subscription with actual webhook URL
    update_pubsub_subscription
    
    success "All Cloud Functions deployed successfully"
}

deploy_gmail_webhook_function() {
    info "Deploying Gmail webhook function..."
    
    local function_dir="${SCRIPT_DIR}/../functions/gmail-webhook"
    mkdir -p "$function_dir"
    
    # Create requirements.txt
    cat > "$function_dir/requirements.txt" << 'EOF'
functions-framework==3.*
google-auth==2.*
google-api-python-client==2.*
google-cloud-aiplatform==1.*
google-cloud-secretmanager==2.*
google-cloud-logging==3.*
EOF

    # Create main.py
    cat > "$function_dir/main.py" << 'EOF'
import base64
import json
import os
import logging
from typing import Dict, Any
from google.cloud import aiplatform
from google.cloud import logging as cloud_logging
from google.oauth2 import service_account
from googleapiclient.discovery import build
import functions_framework

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

@functions_framework.http
def gmail_webhook(request):
    """Process Gmail webhook notifications"""
    try:
        # Verify request is from Pub/Sub
        if request.headers.get('Content-Type') != 'application/json':
            return {'status': 'error', 'message': 'Invalid content type'}, 400
        
        # Parse Pub/Sub message
        envelope = request.get_json()
        if not envelope:
            return {'status': 'error', 'message': 'No Pub/Sub message'}, 400
        
        # Decode the message data
        pubsub_message = envelope.get('message', {})
        data = pubsub_message.get('data', '')
        
        if data:
            decoded_data = base64.b64decode(data).decode('utf-8')
            email_notification = json.loads(decoded_data)
            
            # Extract email details
            email_address = email_notification.get('emailAddress')
            history_id = email_notification.get('historyId')
            
            logger.info(f"Processing email notification for {email_address}")
            
            # Trigger email workflow processing
            result = trigger_email_workflow(email_address, history_id)
            
            return {'status': 'success', 'result': result}
        else:
            return {'status': 'error', 'message': 'No message data'}, 400
            
    except Exception as e:
        logger.error(f"Error processing webhook: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500

def trigger_email_workflow(email_address: str, history_id: str) -> Dict[str, Any]:
    """Trigger the email processing workflow"""
    try:
        # For now, return success - will be connected to workflow in production
        logger.info(f"Triggered workflow for email: {email_address}, history: {history_id}")
        return {
            "message": "Email workflow triggered successfully",
            "email_address": email_address,
            "history_id": history_id
        }
    except Exception as e:
        logger.error(f"Error triggering workflow: {str(e)}")
        return {"error": str(e)}
EOF

    # Deploy function
    execute_command "gcloud functions deploy gmail-webhook \
        --gen2 \
        --runtime=python311 \
        --region=${REGION} \
        --source=${function_dir} \
        --entry-point=gmail_webhook \
        --trigger-http \
        --allow-unauthenticated \
        --service-account=${SERVICE_ACCOUNT_EMAIL} \
        --set-env-vars PROJECT_ID=${PROJECT_ID},REGION=${REGION} \
        --memory=512Mi \
        --timeout=60s"
    
    success "Gmail webhook function deployed"
}

deploy_mcp_integration_function() {
    info "Deploying MCP integration function..."
    
    local function_dir="${SCRIPT_DIR}/../functions/mcp-integration"
    mkdir -p "$function_dir"
    
    # Create requirements.txt
    cat > "$function_dir/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-secretmanager==2.*
google-cloud-logging==3.*
EOF

    # Create main.py (abbreviated for deployment script)
    cat > "$function_dir/main.py" << 'EOF'
import json
import os
import logging
from typing import Dict, Any
import functions_framework
from google.cloud import secretmanager
from google.cloud import logging as cloud_logging

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

class MCPClient:
    """Model Context Protocol client for enterprise data access"""
    
    def __init__(self, project_id: str):
        self.project_id = project_id
        self.secret_client = secretmanager.SecretManagerServiceClient()
    
    def get_customer_info(self, email: str, customer_id: str = None) -> Dict[str, Any]:
        """Retrieve customer information from CRM system"""
        try:
            logger.info(f"Retrieving customer info for email: {email}")
            
            # Simulate CRM lookup with realistic data structure
            customer_data = {
                "customer_id": customer_id or f"cust_{abs(hash(email)) % 10000}",
                "email": email,
                "name": self._generate_customer_name(email),
                "status": "active",
                "tier": "premium" if "enterprise" in email else "standard",
                "last_interaction": "2025-07-20",
                "open_tickets": 1 if "support" in email else 0,
                "account_created": "2023-06-15",
                "total_orders": 12,
                "preferred_language": "en"
            }
            
            return {"success": True, "data": customer_data}
            
        except Exception as e:
            logger.error(f"Error retrieving customer info: {str(e)}")
            return {"success": False, "error": str(e)}
    
    def search_knowledge_base(self, query: str, category: str = "general") -> Dict[str, Any]:
        """Search internal knowledge base for relevant information"""
        try:
            logger.info(f"Searching knowledge base for query: {query}, category: {category}")
            
            knowledge_articles = self._get_knowledge_articles(query, category)
            
            return {"success": True, "data": knowledge_articles}
            
        except Exception as e:
            logger.error(f"Error searching knowledge base: {str(e)}")
            return {"success": False, "error": str(e)}
    
    def _generate_customer_name(self, email: str) -> str:
        """Generate realistic customer name from email"""
        username = email.split('@')[0]
        if '.' in username:
            parts = username.split('.')
            return f"{parts[0].title()} {parts[1].title()}"
        return username.title()
    
    def _get_knowledge_articles(self, query: str, category: str) -> list:
        """Get relevant knowledge base articles"""
        base_articles = {
            "billing": [
                {
                    "title": "Payment Processing Guide",
                    "content": "To process payments, customers can use credit cards, bank transfers, or digital wallets...",
                    "category": "billing",
                    "relevance_score": 0.95,
                    "article_id": "kb-001"
                }
            ],
            "technical": [
                {
                    "title": "Login Troubleshooting Steps",
                    "content": "If experiencing login issues, first check password strength and try password reset...",
                    "category": "technical",
                    "relevance_score": 0.92,
                    "article_id": "kb-101"
                }
            ],
            "support": [
                {
                    "title": "Email Response Best Practices",
                    "content": "Always acknowledge receipt within 24 hours. Use professional tone and provide specific solutions...",
                    "category": "support",
                    "relevance_score": 0.90,
                    "article_id": "kb-201"
                }
            ]
        }
        
        return base_articles.get(category, base_articles["support"])

@functions_framework.http
def mcp_handler(request):
    """Handle MCP tool requests from AI agent"""
    try:
        if request.method != 'POST':
            return {"success": False, "error": "Only POST method allowed"}, 405
        
        data = request.get_json()
        if not data:
            return {"success": False, "error": "No JSON data provided"}, 400
        
        tool_name = data.get('tool')
        params = data.get('parameters', {})
        
        if not tool_name:
            return {"success": False, "error": "Tool name required"}, 400
        
        project_id = os.environ.get('PROJECT_ID')
        mcp_client = MCPClient(project_id)
        
        if tool_name == 'get_customer_info':
            email = params.get('email')
            if not email:
                return {"success": False, "error": "Email parameter required"}, 400
            
            result = mcp_client.get_customer_info(
                email=email,
                customer_id=params.get('customer_id')
            )
        elif tool_name == 'search_knowledge_base':
            query = params.get('query')
            if not query:
                return {"success": False, "error": "Query parameter required"}, 400
            
            result = mcp_client.search_knowledge_base(
                query=query,
                category=params.get('category', 'general')
            )
        else:
            return {"success": False, "error": f"Unknown tool: {tool_name}"}, 400
        
        return result
        
    except Exception as e:
        logger.error(f"Error in MCP handler: {str(e)}")
        return {"success": False, "error": str(e)}, 500
EOF

    # Deploy function
    execute_command "gcloud functions deploy mcp-integration \
        --gen2 \
        --runtime=python311 \
        --region=${REGION} \
        --source=${function_dir} \
        --entry-point=mcp_handler \
        --trigger-http \
        --allow-unauthenticated \
        --service-account=${SERVICE_ACCOUNT_EMAIL} \
        --set-env-vars PROJECT_ID=${PROJECT_ID} \
        --memory=512Mi \
        --timeout=30s"
    
    success "MCP integration function deployed"
}

deploy_response_generator_function() {
    info "Deploying response generator function..."
    
    local function_dir="${SCRIPT_DIR}/../functions/response-generator"
    mkdir -p "$function_dir"
    
    # Create requirements.txt
    cat > "$function_dir/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-aiplatform==1.*
google-auth==2.*
google-cloud-logging==3.*
EOF

    # Create simplified main.py for deployment
    cat > "$function_dir/main.py" << 'EOF'
import json
import os
import logging
from datetime import datetime
from typing import Dict, Any
import functions_framework
from google.cloud import logging as cloud_logging

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

@functions_framework.http
def generate_response(request):
    """Generate email responses using AI agent and MCP context"""
    try:
        if request.method != 'POST':
            return {"success": False, "error": "Only POST method allowed"}, 405
        
        data = request.get_json()
        if not data:
            return {"success": False, "error": "No JSON data provided"}, 400
        
        email_content = data.get('email_content', '')
        customer_context = data.get('customer_context', {})
        knowledge_context = data.get('knowledge_context', {})
        
        logger.info("Generating email response with provided context")
        
        # Generate response using context and templates
        response = create_email_response(
            email_content, customer_context, knowledge_context
        )
        
        return {"success": True, "response": response}
        
    except Exception as e:
        logger.error(f"Error generating response: {str(e)}")
        return {"success": False, "error": str(e)}, 500

def create_email_response(email_content: str, customer_context: dict, knowledge_context: dict) -> Dict[str, Any]:
    """Create contextual email response"""
    
    customer_name = customer_context.get('name', 'Valued Customer')
    customer_tier = customer_context.get('tier', 'standard')
    customer_id = customer_context.get('customer_id', 'N/A')
    
    # Simple email analysis
    email_analysis = {
        "category": "support",
        "urgency": "normal"
    }
    
    # Generate response
    response_data = {
        "subject": f"Re: Support Request",
        "body": f"""Dear {customer_name},

Thank you for contacting our support team. We have received your inquiry and are ready to assist you.

Customer ID: {customer_id}
Request processed at: {datetime.now().strftime("%Y-%m-%d %H:%M UTC")}

We will respond to your request within 24 hours during business days.

Best regards,
Customer Support Team""",
        "metadata": {
            "category": email_analysis['category'],
            "urgency": email_analysis['urgency'],
            "customer_tier": customer_tier,
            "generated_at": datetime.now().isoformat()
        }
    }
    
    return response_data
EOF

    # Deploy function
    execute_command "gcloud functions deploy response-generator \
        --gen2 \
        --runtime=python311 \
        --region=${REGION} \
        --source=${function_dir} \
        --entry-point=generate_response \
        --trigger-http \
        --allow-unauthenticated \
        --service-account=${SERVICE_ACCOUNT_EMAIL} \
        --set-env-vars PROJECT_ID=${PROJECT_ID} \
        --memory=512Mi \
        --timeout=60s"
    
    success "Response generator function deployed"
}

deploy_workflow_function() {
    info "Deploying workflow orchestration function..."
    
    local function_dir="${SCRIPT_DIR}/../functions/email-workflow"
    mkdir -p "$function_dir"
    
    # Create requirements.txt
    cat > "$function_dir/requirements.txt" << 'EOF'
functions-framework==3.*
google-cloud-logging==3.*
requests==2.*
EOF

    # Create simplified main.py for deployment
    cat > "$function_dir/main.py" << 'EOF'
import json
import os
import logging
from typing import Dict, Any
import functions_framework
import requests
from google.cloud import logging as cloud_logging

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

@functions_framework.http
def email_workflow(request):
    """Orchestrate complete email processing workflow"""
    try:
        if request.method != 'POST':
            return {"success": False, "error": "Only POST method allowed"}, 405
        
        data = request.get_json()
        if not data:
            return {"success": False, "error": "No JSON data provided"}, 400
        
        email_data = data.get('email_data', {})
        if not email_data:
            return {"success": False, "error": "Email data required"}, 400
        
        logger.info(f"Starting email workflow for {email_data.get('sender_email', 'unknown')}")
        
        # Simplified workflow processing
        workflow_result = {
            "workflow_id": f"wf_{abs(hash(str(email_data))) % 100000}",
            "status": "processed",
            "message": "Email workflow completed successfully"
        }
        
        return {"success": True, "result": workflow_result}
        
    except Exception as e:
        logger.error(f"Workflow error: {str(e)}")
        return {"success": False, "error": str(e)}, 500
EOF

    # Deploy function
    execute_command "gcloud functions deploy email-workflow \
        --gen2 \
        --runtime=python311 \
        --region=${REGION} \
        --source=${function_dir} \
        --entry-point=email_workflow \
        --trigger-http \
        --allow-unauthenticated \
        --service-account=${SERVICE_ACCOUNT_EMAIL} \
        --set-env-vars PROJECT_ID=${PROJECT_ID},REGION=${REGION} \
        --memory=1Gi \
        --timeout=120s"
    
    success "Workflow orchestration function deployed"
}

update_pubsub_subscription() {
    info "Updating Pub/Sub subscription with webhook URL..."
    
    local webhook_url="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/gmail-webhook"
    
    # Create subscription if it doesn't exist
    if ! gcloud pubsub subscriptions describe gmail-webhook-sub &> /dev/null; then
        execute_command "gcloud pubsub subscriptions create gmail-webhook-sub \
            --topic=gmail-notifications \
            --push-endpoint=${webhook_url}"
    else
        execute_command "gcloud pubsub subscriptions modify-push-config gmail-webhook-sub \
            --push-endpoint=${webhook_url}"
    fi
    
    save_state "WEBHOOK_URL" "$webhook_url"
    success "Pub/Sub subscription configured with webhook URL: $webhook_url"
}

create_mcp_configuration() {
    info "Creating MCP server configuration..."
    
    local mcp_config_dir="${SCRIPT_DIR}/../mcp-config"
    mkdir -p "$mcp_config_dir"
    
    cat > "$mcp_config_dir/mcp-server.json" << 'EOF'
{
  "name": "email-automation-mcp",
  "version": "1.0.0",
  "description": "MCP server for email automation context",
  "capabilities": {
    "resources": true,
    "tools": true
  },
  "tools": [
    {
      "name": "get_customer_info",
      "description": "Retrieve customer information from CRM",
      "inputSchema": {
        "type": "object",
        "properties": {
          "email": {"type": "string"},
          "customer_id": {"type": "string"}
        }
      }
    },
    {
      "name": "search_knowledge_base",
      "description": "Search internal knowledge base",
      "inputSchema": {
        "type": "object",
        "properties": {
          "query": {"type": "string"},
          "category": {"type": "string"}
        }
      }
    }
  ]
}
EOF

    success "MCP configuration created"
}

verify_deployment() {
    info "Verifying deployment..."
    
    # Check Cloud Functions
    local functions=("gmail-webhook" "mcp-integration" "response-generator" "email-workflow")
    for func in "${functions[@]}"; do
        if gcloud functions describe "$func" --region="$REGION" &> /dev/null; then
            success "Function verified: $func"
        else
            error "Function not found: $func"
        fi
    done
    
    # Check Pub/Sub resources
    if gcloud pubsub topics describe gmail-notifications &> /dev/null; then
        success "Pub/Sub topic verified: gmail-notifications"
    else
        error "Pub/Sub topic not found: gmail-notifications"
    fi
    
    if gcloud pubsub subscriptions describe gmail-webhook-sub &> /dev/null; then
        success "Pub/Sub subscription verified: gmail-webhook-sub"
    else
        error "Pub/Sub subscription not found: gmail-webhook-sub"
    fi
    
    # Check service account
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" &> /dev/null; then
        success "Service account verified: $SERVICE_ACCOUNT_EMAIL"
    else
        error "Service account not found: $SERVICE_ACCOUNT_EMAIL"
    fi
}

display_deployment_info() {
    info "Deployment Summary"
    echo
    echo "=========================================="
    echo "  Email Automation Deployment Complete"
    echo "=========================================="
    echo
    echo "Project ID:       $PROJECT_ID"
    echo "Region:           $REGION"
    echo "Service Account:  $SERVICE_ACCOUNT_EMAIL"
    echo "Random Suffix:    $RANDOM_SUFFIX"
    echo
    echo "Deployed Functions:"
    echo "  • gmail-webhook"
    echo "  • mcp-integration"
    echo "  • response-generator"
    echo "  • email-workflow"
    echo
    echo "Pub/Sub Resources:"
    echo "  • Topic: gmail-notifications"
    echo "  • Subscription: gmail-webhook-sub"
    echo
    echo "Webhook URL:"
    echo "  $(load_state "WEBHOOK_URL")"
    echo
    echo "Next Steps:"
    echo "  1. Configure Gmail API push notifications"
    echo "  2. Test the workflow with sample emails"
    echo "  3. Integrate with your enterprise data sources"
    echo "  4. Monitor Cloud Functions logs for debugging"
    echo
    echo "Log file: $LOG_FILE"
    echo "State file: $STATE_FILE"
    echo
}

cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Deployment failed with exit code $exit_code"
        echo "Check the log file for details: $LOG_FILE"
    fi
}

main() {
    # Set up error handling
    trap cleanup_on_exit EXIT
    
    info "Starting Email Automation deployment..."
    echo "Log file: $LOG_FILE"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Load existing state if available
    if [[ -f "$STATE_FILE" ]]; then
        RANDOM_SUFFIX=$(load_state "RANDOM_SUFFIX")
        info "Loaded existing state. Random suffix: $RANDOM_SUFFIX"
    fi
    
    # Execute deployment steps
    setup_environment
    enable_apis
    create_service_account
    create_pubsub_resources
    create_mcp_configuration
    deploy_cloud_functions
    
    # Verify deployment
    verify_deployment
    
    # Display summary
    display_deployment_info
    
    success "Email Automation deployment completed successfully!"
}

# Run main function with all arguments
main "$@"