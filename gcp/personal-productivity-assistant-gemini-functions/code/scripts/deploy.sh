#!/bin/bash

# GCP Personal Productivity Assistant with Gemini and Functions - Deployment Script
# This script deploys a complete personal productivity assistant using Gemini 2.5 Flash,
# Cloud Functions, Pub/Sub, and Firestore for intelligent email processing and automation.

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
readonly FUNCTION_SOURCE_DIR="$PROJECT_ROOT/code/terraform/function-source"

# Default values (can be overridden via environment variables)
PROJECT_ID="${PROJECT_ID:-productivity-assistant-$(date +%s)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
ENVIRONMENT="${ENVIRONMENT:-development}"

# Function deployment settings
EMAIL_PROCESSOR_MEMORY="${EMAIL_PROCESSOR_MEMORY:-1GB}"
EMAIL_PROCESSOR_TIMEOUT="${EMAIL_PROCESSOR_TIMEOUT:-300s}"
SCHEDULED_PROCESSOR_MEMORY="${SCHEDULED_PROCESSOR_MEMORY:-512MB}"
SCHEDULED_PROCESSOR_TIMEOUT="${SCHEDULED_PROCESSOR_TIMEOUT:-180s}"

# Pub/Sub and scheduling settings
SCHEDULE_CRON="${SCHEDULE_CRON:-*/15 8-18 * * 1-5}"
SCHEDULE_TIMEZONE="${SCHEDULE_TIMEZONE:-America/New_York}"

# Security settings
ALLOW_UNAUTHENTICATED="${ALLOW_UNAUTHENTICATED:-false}"

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

# Function to check if required commands exist
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_commands=()
    
    # Check for required CLI tools
    for cmd in gcloud openssl curl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_error "Please install the missing commands and run this script again."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found."
        log_error "Please run 'gcloud auth login' to authenticate."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to validate input parameters
validate_inputs() {
    log_info "Validating input parameters..."
    
    # Validate project ID format
    if [[ ! "$PROJECT_ID" =~ ^[a-z][-a-z0-9]{4,28}[a-z0-9]$ ]]; then
        log_error "Invalid project ID format: $PROJECT_ID"
        log_error "Project ID must be 6-30 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
        exit 1
    fi
    
    # Validate region format
    if [[ ! "$REGION" =~ ^[a-z0-9-]+$ ]]; then
        log_error "Invalid region format: $REGION"
        exit 1
    fi
    
    # Validate environment
    if [[ ! "$ENVIRONMENT" =~ ^(development|staging|production)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT. Must be one of: development, staging, production"
        exit 1
    fi
    
    log_success "Input parameters validated"
}

# Function to create and configure the GCP project
setup_project() {
    log_info "Setting up GCP project: $PROJECT_ID"
    
    # Check if project already exists
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_warning "Project $PROJECT_ID already exists, skipping creation"
    else
        # Create new project
        gcloud projects create "$PROJECT_ID" \
            --name="Personal Productivity Assistant - $ENVIRONMENT" \
            --labels="environment=$ENVIRONMENT,application=productivity-assistant"
        log_success "Created project: $PROJECT_ID"
    fi
    
    # Set as default project
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "Project configuration completed"
}

# Function to link billing account (optional)
setup_billing() {
    log_info "Checking billing account configuration..."
    
    # Check if billing is already enabled
    if gcloud billing projects describe "$PROJECT_ID" &>/dev/null; then
        log_success "Billing is already configured for project $PROJECT_ID"
        return 0
    fi
    
    # Get available billing accounts
    local billing_accounts
    billing_accounts=$(gcloud billing accounts list --filter="open=true" --format="value(name)" 2>/dev/null || true)
    
    if [ -z "$billing_accounts" ]; then
        log_warning "No active billing accounts found."
        log_warning "Please set up billing manually at: https://console.cloud.google.com/billing"
        log_warning "This deployment will continue but some services may not work without billing."
        return 0
    fi
    
    # Use the first available billing account
    local billing_account
    billing_account=$(echo "$billing_accounts" | head -n1)
    
    if [ -n "$billing_account" ]; then
        gcloud billing projects link "$PROJECT_ID" --billing-account="$billing_account"
        log_success "Linked billing account: $billing_account"
    fi
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "aiplatform.googleapis.com"
        "firestore.googleapis.com"
        "pubsub.googleapis.com"
        "cloudscheduler.googleapis.com"
        "gmail.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "iam.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api"
    done
    
    # Wait for APIs to be fully enabled
    sleep 10
    
    log_success "All required APIs enabled"
}

# Function to create Firestore database
setup_firestore() {
    log_info "Setting up Firestore database..."
    
    # Check if Firestore database already exists
    if gcloud firestore databases describe --database="(default)" &>/dev/null; then
        log_warning "Firestore database already exists, skipping creation"
        return 0
    fi
    
    # Create Firestore database in native mode
    gcloud firestore databases create \
        --region="$REGION" \
        --type=firestore-native \
        --database="(default)"
    
    log_success "Firestore database created successfully"
}

# Function to create Pub/Sub resources
setup_pubsub() {
    log_info "Setting up Pub/Sub topic and subscription..."
    
    local topic_name="email-processing-topic"
    local subscription_name="email-processing-sub"
    
    # Create Pub/Sub topic
    if gcloud pubsub topics describe "$topic_name" &>/dev/null; then
        log_warning "Pub/Sub topic $topic_name already exists, skipping creation"
    else
        gcloud pubsub topics create "$topic_name" \
            --labels="environment=$ENVIRONMENT,application=productivity-assistant"
        log_success "Created Pub/Sub topic: $topic_name"
    fi
    
    # Create subscription
    if gcloud pubsub subscriptions describe "$subscription_name" &>/dev/null; then
        log_warning "Pub/Sub subscription $subscription_name already exists, skipping creation"
    else
        gcloud pubsub subscriptions create "$subscription_name" \
            --topic="$topic_name" \
            --ack-deadline=300 \
            --max-delivery-attempts=5 \
            --labels="environment=$ENVIRONMENT,application=productivity-assistant"
        log_success "Created Pub/Sub subscription: $subscription_name"
    fi
}

# Function to create source directory structure
setup_function_source() {
    log_info "Setting up Cloud Function source code..."
    
    # Create temporary function directory
    local temp_function_dir
    temp_function_dir=$(mktemp -d)
    
    # Copy function source files
    if [ -d "$FUNCTION_SOURCE_DIR" ]; then
        cp -r "$FUNCTION_SOURCE_DIR"/* "$temp_function_dir/"
    else
        log_warning "Function source directory not found at $FUNCTION_SOURCE_DIR"
        log_info "Creating basic function source files..."
        
        # Create requirements.txt
        cat > "$temp_function_dir/requirements.txt" << 'EOF'
google-cloud-aiplatform==1.71.0
google-cloud-firestore==2.20.0
google-cloud-pubsub==2.26.0
google-api-python-client==2.155.0
google-auth-httplib2==0.2.0
google-auth-oauthlib==1.2.1
functions-framework==3.8.1
vertexai>=1.71.0
EOF
        
        # Create basic main.py
        cat > "$temp_function_dir/main.py" << 'EOF'
import os
import json
import logging
from datetime import datetime
from typing import List, Dict, Any
import functions_framework
from google.cloud import aiplatform
from google.cloud import firestore
from google.cloud import pubsub_v1
import vertexai
from vertexai.generative_models import GenerativeModel, Tool, FunctionDeclaration

# Initialize Vertex AI
PROJECT_ID = os.environ.get('GCP_PROJECT')
REGION = 'us-central1'
vertexai.init(project=PROJECT_ID, location=REGION)

# Initialize clients
db = firestore.Client()
publisher = pubsub_v1.PublisherClient()

# Define function declarations for Gemini
extract_action_items_func = FunctionDeclaration(
    name="extract_action_items",
    description="Extract action items and tasks from email content",
    parameters={
        "type": "object",
        "properties": {
            "action_items": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "task": {"type": "string", "description": "The action item or task"},
                        "priority": {"type": "string", "enum": ["high", "medium", "low"]},
                        "due_date": {"type": "string", "description": "Estimated due date if mentioned"},
                        "assignee": {"type": "string", "description": "Person responsible"}
                    }
                }
            },
            "summary": {"type": "string", "description": "Brief summary of email content"}
        },
        "required": ["action_items", "summary"]
    }
)

generate_reply_func = FunctionDeclaration(
    name="generate_reply",
    description="Generate appropriate email reply based on content and context",
    parameters={
        "type": "object",
        "properties": {
            "reply_text": {"type": "string", "description": "Generated reply content"},
            "tone": {"type": "string", "enum": ["professional", "friendly", "formal"]},
            "action_required": {"type": "boolean", "description": "Whether reply requires action"}
        },
        "required": ["reply_text", "tone", "action_required"]
    }
)

# Initialize Gemini model with function calling
productivity_tool = Tool(
    function_declarations=[extract_action_items_func, generate_reply_func]
)

model = GenerativeModel(
    "gemini-2.5-flash-002",
    tools=[productivity_tool],
    generation_config={
        "temperature": 0.3,
        "top_p": 0.8,
        "max_output_tokens": 2048
    }
)

def process_email_content(email_data: Dict[str, Any]) -> Dict[str, Any]:
    """Process email content using Gemini 2.5 Flash."""
    try:
        subject = email_data.get('subject', '')
        body = email_data.get('body', '')
        sender = email_data.get('sender', '')
        
        # Create comprehensive prompt for email analysis
        prompt = f"""
        Analyze this email and extract action items, then generate an appropriate reply:
        
        From: {sender}
        Subject: {subject}
        Body: {body}
        
        Please:
        1. Call extract_action_items to identify all tasks with priorities and due dates
        2. Call generate_reply to create a professional and helpful response
        3. Determine if immediate action is required
        
        Use the provided functions to structure your response.
        """
        
        # Generate response with function calling
        response = model.generate_content(prompt)
        
        # Process function calls
        result = {
            "analysis_complete": True,
            "timestamp": datetime.utcnow().isoformat()
        }
        
        for part in response.parts:
            if part.function_call:
                func_name = part.function_call.name
                func_args = dict(part.function_call.args)
                
                if func_name == "extract_action_items":
                    result["action_items"] = func_args.get("action_items", [])
                    result["summary"] = func_args.get("summary", "")
                elif func_name == "generate_reply":
                    result["reply"] = {
                        "text": func_args.get("reply_text", ""),
                        "tone": func_args.get("tone", "professional"),
                        "action_required": func_args.get("action_required", False)
                    }
        
        return result
        
    except Exception as e:
        logging.error(f"Error processing email: {str(e)}")
        return {"error": str(e), "analysis_complete": False}

def store_analysis_results(email_id: str, analysis: Dict[str, Any]) -> None:
    """Store email analysis results in Firestore."""
    try:
        doc_ref = db.collection('email_analysis').document(email_id)
        doc_ref.set({
            **analysis,
            "email_id": email_id,
            "processed_at": firestore.SERVER_TIMESTAMP
        })
        logging.info(f"Analysis stored for email {email_id}")
    except Exception as e:
        logging.error(f"Error storing analysis: {str(e)}")

@functions_framework.http
def process_email(request):
    """Main HTTP function for processing emails."""
    try:
        # Parse request data
        email_data = request.get_json()
        if not email_data:
            return {"error": "No email data provided"}, 400
        
        email_id = email_data.get('email_id')
        if not email_id:
            return {"error": "Email ID required"}, 400
        
        # Process email with Gemini
        logging.info(f"Processing email {email_id}")
        analysis = process_email_content(email_data)
        
        # Store results
        store_analysis_results(email_id, analysis)
        
        # Publish to Pub/Sub for further processing if needed
        topic_path = publisher.topic_path(PROJECT_ID, 'email-processing-topic')
        message_data = json.dumps({
            "email_id": email_id,
            "analysis": analysis
        }).encode('utf-8')
        
        publisher.publish(topic_path, message_data)
        
        return {
            "status": "success",
            "email_id": email_id,
            "analysis": analysis
        }
        
    except Exception as e:
        logging.error(f"Function error: {str(e)}")
        return {"error": str(e)}, 500
EOF
        
        # Create scheduled function
        cat > "$temp_function_dir/scheduled_main.py" << 'EOF'
import os
import json
import logging
from datetime import datetime
from typing import Dict, Any
import functions_framework
from google.cloud import firestore

# Initialize clients
db = firestore.Client()

@functions_framework.cloud_event
def process_scheduled_emails(cloud_event):
    """Scheduled function to process emails periodically."""
    try:
        logging.info("Running scheduled email processing")
        
        # This would integrate with Gmail API to fetch new emails
        # For demo purposes, we'll log the scheduled execution
        
        timestamp = datetime.utcnow().isoformat()
        doc_ref = db.collection('scheduled_runs').document()
        doc_ref.set({
            "timestamp": timestamp,
            "status": "completed",
            "processed_at": firestore.SERVER_TIMESTAMP
        })
        
        logging.info(f"Scheduled processing completed at {timestamp}")
        return {"status": "success"}
        
    except Exception as e:
        logging.error(f"Scheduled processing error: {str(e)}")
        return {"error": str(e)}
EOF
    fi
    
    echo "$temp_function_dir"
}

# Function to deploy Cloud Functions
deploy_functions() {
    log_info "Deploying Cloud Functions..."
    
    # Setup function source code
    local function_dir
    function_dir=$(setup_function_source)
    
    local auth_flag=""
    if [ "$ALLOW_UNAUTHENTICATED" = "true" ]; then
        auth_flag="--allow-unauthenticated"
    fi
    
    # Deploy email processing function
    log_info "Deploying email processing function..."
    (
        cd "$function_dir"
        gcloud functions deploy email-processor \
            --runtime python312 \
            --trigger-http \
            --entry-point process_email \
            --memory "$EMAIL_PROCESSOR_MEMORY" \
            --timeout "$EMAIL_PROCESSOR_TIMEOUT" \
            --region "$REGION" \
            --set-env-vars "GCP_PROJECT=$PROJECT_ID,ENVIRONMENT=$ENVIRONMENT" \
            --max-instances 100 \
            --min-instances 0 \
            --labels "environment=$ENVIRONMENT,application=productivity-assistant" \
            $auth_flag
    )
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe email-processor \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    log_success "Email processing function deployed: $function_url"
    
    # Deploy scheduled processing function
    log_info "Deploying scheduled processing function..."
    (
        cd "$function_dir"
        gcloud functions deploy scheduled-email-processor \
            --runtime python312 \
            --trigger-topic email-processing-topic \
            --entry-point process_scheduled_emails \
            --source scheduled_main.py \
            --memory "$SCHEDULED_PROCESSOR_MEMORY" \
            --timeout "$SCHEDULED_PROCESSOR_TIMEOUT" \
            --region "$REGION" \
            --set-env-vars "GCP_PROJECT=$PROJECT_ID,ENVIRONMENT=$ENVIRONMENT" \
            --max-instances 50 \
            --min-instances 0 \
            --labels "environment=$ENVIRONMENT,application=productivity-assistant"
    )
    
    log_success "Scheduled processing function deployed"
    
    # Clean up temporary directory
    rm -rf "$function_dir"
}

# Function to create Cloud Scheduler job
setup_scheduler() {
    log_info "Setting up Cloud Scheduler job..."
    
    local job_name="email-processing-schedule"
    
    # Check if scheduler job already exists
    if gcloud scheduler jobs describe "$job_name" --location="$REGION" &>/dev/null; then
        log_warning "Scheduler job $job_name already exists, updating..."
        gcloud scheduler jobs update pubsub "$job_name" \
            --schedule="$SCHEDULE_CRON" \
            --topic=email-processing-topic \
            --message-body='{"trigger":"scheduled"}' \
            --time-zone="$SCHEDULE_TIMEZONE" \
            --location="$REGION"
    else
        gcloud scheduler jobs create pubsub "$job_name" \
            --schedule="$SCHEDULE_CRON" \
            --topic=email-processing-topic \
            --message-body='{"trigger":"scheduled"}' \
            --time-zone="$SCHEDULE_TIMEZONE" \
            --location="$REGION" \
            --description="Automated email processing for productivity assistant"
    fi
    
    log_success "Cloud Scheduler job configured"
}

# Function to setup OAuth credentials
setup_oauth_credentials() {
    log_info "Setting up OAuth credentials directory..."
    
    local credentials_dir="$HOME/productivity-assistant/credentials"
    mkdir -p "$credentials_dir"
    
    log_info "OAuth 2.0 credentials setup required for Gmail API access:"
    log_info "1. Go to: https://console.cloud.google.com/apis/credentials?project=$PROJECT_ID"
    log_info "2. Click 'Create Credentials' > 'OAuth client ID'"
    log_info "3. Choose 'Desktop application'"
    log_info "4. Download credentials.json to: $credentials_dir/"
    log_warning "Note: OAuth setup is manual and required for Gmail integration"
    
    log_success "OAuth credentials directory created: $credentials_dir"
}

# Function to perform deployment validation
validate_deployment() {
    log_info "Validating deployment..."
    
    local validation_errors=()
    
    # Check Firestore database
    if ! gcloud firestore databases describe --database="(default)" &>/dev/null; then
        validation_errors+=("Firestore database not found")
    fi
    
    # Check Pub/Sub topic
    if ! gcloud pubsub topics describe email-processing-topic &>/dev/null; then
        validation_errors+=("Pub/Sub topic not found")
    fi
    
    # Check Cloud Functions
    if ! gcloud functions describe email-processor --region="$REGION" &>/dev/null; then
        validation_errors+=("Email processor function not found")
    fi
    
    if ! gcloud functions describe scheduled-email-processor --region="$REGION" &>/dev/null; then
        validation_errors+=("Scheduled processor function not found")
    fi
    
    # Check Cloud Scheduler job
    if ! gcloud scheduler jobs describe email-processing-schedule --location="$REGION" &>/dev/null; then
        validation_errors+=("Cloud Scheduler job not found")
    fi
    
    if [ ${#validation_errors[@]} -ne 0 ]; then
        log_error "Deployment validation failed:"
        for error in "${validation_errors[@]}"; do
            log_error "  - $error"
        done
        exit 1
    fi
    
    log_success "Deployment validation passed"
}

# Function to display deployment summary
display_deployment_summary() {
    log_success "🎉 GCP Personal Productivity Assistant deployed successfully!"
    echo
    echo "Deployment Summary:"
    echo "==================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Environment: $ENVIRONMENT"
    echo
    echo "Deployed Resources:"
    echo "- Firestore Database: (default)"
    echo "- Pub/Sub Topic: email-processing-topic"
    echo "- Pub/Sub Subscription: email-processing-sub"
    echo "- Cloud Function (HTTP): email-processor"
    echo "- Cloud Function (Pub/Sub): scheduled-email-processor"
    echo "- Cloud Scheduler Job: email-processing-schedule ($SCHEDULE_CRON)"
    echo
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe email-processor \
        --region="$REGION" \
        --format="value(httpsTrigger.url)" 2>/dev/null || echo "Not available")
    
    echo "Function URL: $function_url"
    echo
    echo "Next Steps:"
    echo "1. Complete OAuth 2.0 setup for Gmail API access"
    echo "2. Test email processing with sample data"
    echo "3. Configure Gmail integration using the helper scripts"
    echo "4. Monitor function logs: gcloud functions logs read email-processor --region=$REGION"
    echo
    echo "Documentation: https://cloud.google.com/vertex-ai/docs/generative-ai/start/quickstarts/quickstart-multimodal"
    echo
    log_warning "Remember to set up billing and OAuth credentials for full functionality"
}

# Main deployment function
main() {
    log_info "Starting GCP Personal Productivity Assistant deployment..."
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Environment: $ENVIRONMENT"
    echo
    
    # Run deployment steps
    check_prerequisites
    validate_inputs
    setup_project
    setup_billing
    enable_apis
    setup_firestore
    setup_pubsub
    deploy_functions
    setup_scheduler
    setup_oauth_credentials
    validate_deployment
    display_deployment_summary
    
    log_success "Deployment completed successfully! 🚀"
}

# Handle script interruption
trap 'log_error "Deployment interrupted"; exit 1' INT TERM

# Parse command line arguments
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
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --allow-unauthenticated)
            ALLOW_UNAUTHENTICATED="true"
            shift
            ;;
        --schedule)
            SCHEDULE_CRON="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --project-id ID          GCP Project ID (default: auto-generated)"
            echo "  --region REGION          GCP Region (default: us-central1)"
            echo "  --environment ENV        Environment (default: development)"
            echo "  --allow-unauthenticated  Allow unauthenticated function access"
            echo "  --schedule CRON          Custom cron schedule (default: */15 8-18 * * 1-5)"
            echo "  --help                   Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main deployment
main "$@"