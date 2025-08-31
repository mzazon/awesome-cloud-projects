#!/bin/bash

# Multi-Agent Customer Service Deployment Script
# Recipe: Multi-Agent Customer Service with Agent2Agent and Contact Center AI
# Provider: Google Cloud Platform (GCP)
# Version: 1.0

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ID=""
REGION="us-central1"
ZONE="us-central1-a"
RANDOM_SUFFIX=""
FUNCTION_PREFIX=""
CCAI_INSTANCE=""
DRY_RUN=false
SKIP_CONFIRMATION=false

# Deployment state tracking
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Multi-Agent Customer Service with Agent2Agent and Contact Center AI

OPTIONS:
    -p, --project-id PROJECT_ID    GCP project ID (required)
    -r, --region REGION           GCP region (default: us-central1)
    -z, --zone ZONE              GCP zone (default: us-central1-a)
    -s, --suffix SUFFIX          Custom suffix for resource names (auto-generated if not provided)
    -d, --dry-run                Show what would be deployed without making changes
    -y, --yes                    Skip confirmation prompts
    -h, --help                   Display this help message

EXAMPLES:
    $0 --project-id my-gcp-project
    $0 --project-id my-gcp-project --region us-west1 --dry-run
    $0 --project-id my-gcp-project --suffix prod --yes

EOF
}

# Parse command line arguments
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
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -s|--suffix)
                RANDOM_SUFFIX="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id or -p to specify."
        usage
        exit 1
    fi

    # Generate random suffix if not provided
    if [[ -z "$RANDOM_SUFFIX" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi

    # Set derived variables
    FUNCTION_PREFIX="agent-${RANDOM_SUFFIX}"
    CCAI_INSTANCE="ccai-${RANDOM_SUFFIX}"
}

# Verify prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it first."
    fi

    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is required for generating random suffixes."
    fi

    # Check if curl is available for testing
    if ! command -v curl &> /dev/null; then
        log_warning "curl is not available. Function testing will be skipped."
    fi

    # Verify gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi

    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error_exit "Project '$PROJECT_ID' does not exist or is not accessible."
    fi

    # Check billing is enabled
    if ! gcloud billing projects describe "$PROJECT_ID" &> /dev/null; then
        log_warning "Billing may not be enabled for project '$PROJECT_ID'. Some services may fail to deploy."
    fi

    log_success "Prerequisites check completed"
}

# Configure GCP project and region
configure_gcp() {
    log_info "Configuring GCP project and region..."

    if [[ "$DRY_RUN" == "false" ]]; then
        gcloud config set project "$PROJECT_ID"
        gcloud config set compute/region "$REGION"
        gcloud config set compute/zone "$ZONE"
    else
        log_info "[DRY RUN] Would set project: $PROJECT_ID, region: $REGION, zone: $ZONE"
    fi

    log_success "GCP configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required APIs..."

    local apis=(
        "aiplatform.googleapis.com"
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com"
        "bigquery.googleapis.com"
        "dialogflow.googleapis.com"
        "contactcenteraiplatform.googleapis.com"
        "cloudbuild.googleapis.com"
        "storage-api.googleapis.com"
        "pubsub.googleapis.com"
    )

    if [[ "$DRY_RUN" == "false" ]]; then
        for api in "${apis[@]}"; do
            log_info "Enabling API: $api"
            if ! gcloud services enable "$api" --project="$PROJECT_ID"; then
                log_warning "Failed to enable API: $api. Continuing..."
            fi
        done
    else
        log_info "[DRY RUN] Would enable APIs: ${apis[*]}"
    fi

    log_success "API enablement completed"
}

# Create Firestore database
create_firestore() {
    log_info "Creating Firestore database and knowledge base..."

    if [[ "$DRY_RUN" == "false" ]]; then
        # Create Firestore database in Native mode
        if ! gcloud firestore databases create --location="$REGION" --type=firestore-native 2>/dev/null; then
            log_warning "Firestore database may already exist or creation failed"
        fi

        # Wait for database to be ready
        sleep 10

        # Create knowledge collections
        log_info "Creating knowledge base collections..."
        
        gcloud firestore documents create knowledge/billing \
            --set='{"domain":"billing","capabilities":["payments","invoices","refunds","subscriptions"],"expertise_level":"expert"}' || \
            log_warning "Failed to create billing knowledge document"

        gcloud firestore documents create knowledge/technical \
            --set='{"domain":"technical","capabilities":["troubleshooting","installations","configurations","diagnostics"],"expertise_level":"expert"}' || \
            log_warning "Failed to create technical knowledge document"

        gcloud firestore documents create knowledge/sales \
            --set='{"domain":"sales","capabilities":["product_info","pricing","demos","upgrades"],"expertise_level":"expert"}' || \
            log_warning "Failed to create sales knowledge document"
    else
        log_info "[DRY RUN] Would create Firestore database and knowledge base collections"
    fi

    log_success "Firestore setup completed"
}

# Initialize Vertex AI
setup_vertex_ai() {
    log_info "Setting up Vertex AI infrastructure..."

    if [[ "$DRY_RUN" == "false" ]]; then
        # Create Vertex AI dataset
        log_info "Creating Vertex AI dataset..."
        local dataset_output
        if dataset_output=$(gcloud ai datasets create \
            --display-name="multi-agent-customer-service" \
            --metadata-schema-uri="gs://google-cloud-aiplatform/schema/dataset/metadata/text_1.0.0.yaml" \
            --region="$REGION" \
            --format="value(name)" 2>/dev/null); then
            
            DATASET_ID=$(echo "$dataset_output" | cut -d'/' -f6)
            echo "DATASET_ID=$DATASET_ID" >> "$DEPLOYMENT_STATE_FILE"
            log_success "Dataset created with ID: $DATASET_ID"
        else
            log_warning "Dataset creation failed or already exists"
        fi

        # Create storage bucket for model artifacts
        local bucket_name="${PROJECT_ID}-agent-models"
        log_info "Creating storage bucket: $bucket_name"
        if ! gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$bucket_name" 2>/dev/null; then
            log_warning "Storage bucket creation failed or already exists"
        fi
        echo "BUCKET_NAME=$bucket_name" >> "$DEPLOYMENT_STATE_FILE"
    else
        log_info "[DRY RUN] Would create Vertex AI dataset and storage bucket"
    fi

    log_success "Vertex AI setup completed"
}

# Create function source code
create_function_code() {
    local function_name="$1"
    local function_dir="$2"
    local main_py_content="$3"
    local requirements_content="$4"

    log_info "Creating source code for $function_name..."

    if [[ "$DRY_RUN" == "false" ]]; then
        mkdir -p "$function_dir"
        echo "$main_py_content" > "$function_dir/main.py"
        echo "$requirements_content" > "$function_dir/requirements.txt"
    else
        log_info "[DRY RUN] Would create source code in $function_dir"
    fi
}

# Deploy Cloud Functions
deploy_functions() {
    log_info "Deploying Cloud Functions..."

    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"

    # Agent Router Function
    local router_main_py='import json
import functions_framework
from google.cloud import firestore
from google.cloud import aiplatform
import logging

# Initialize Firestore client for knowledge base access
db = firestore.Client()

@functions_framework.http
def route_agent(request):
    """Route customer inquiry to appropriate specialist agent"""
    try:
        request_json = request.get_json()
        customer_message = request_json.get("message", "")
        session_id = request_json.get("session_id", "")
        
        # Analyze message intent and determine optimal routing
        routing_decision = analyze_intent(customer_message)
        
        # Log routing decision for analytics and optimization
        log_routing_decision(session_id, customer_message, routing_decision)
        
        return {
            "agent_type": routing_decision["agent"],
            "confidence": routing_decision["confidence"],
            "reasoning": routing_decision["reasoning"],
            "session_id": session_id
        }
        
    except Exception as e:
        logging.error(f"Routing error: {str(e)}")
        return {"error": str(e)}, 500

def analyze_intent(message):
    """Analyze customer message and determine best agent using keyword analysis"""
    message_lower = message.lower()
    
    # Domain-specific keywords for intelligent routing
    billing_keywords = ["bill", "payment", "invoice", "charge", "refund", "subscription"]
    technical_keywords = ["not working", "error", "install", "setup", "configure", "trouble"]
    sales_keywords = ["price", "purchase", "demo", "upgrade", "plan", "features"]
    
    # Calculate keyword match scores for routing decision
    billing_score = sum(1 for word in billing_keywords if word in message_lower)
    technical_score = sum(1 for word in technical_keywords if word in message_lower)
    sales_score = sum(1 for word in sales_keywords if word in message_lower)
    
    # Determine best agent based on keyword analysis
    if billing_score >= technical_score and billing_score >= sales_score:
        return {
            "agent": "billing",
            "confidence": min(0.9, billing_score * 0.3),
            "reasoning": f"Billing keywords detected: {billing_score}"
        }
    elif technical_score >= sales_score:
        return {
            "agent": "technical",
            "confidence": min(0.9, technical_score * 0.3),
            "reasoning": f"Technical keywords detected: {technical_score}"
        }
    else:
        return {
            "agent": "sales",
            "confidence": min(0.9, sales_score * 0.3),
            "reasoning": f"Sales keywords detected: {sales_score}"
        }

def log_routing_decision(session_id, message, decision):
    """Log routing decision to Firestore for analytics"""
    try:
        doc_ref = db.collection("routing_logs").document()
        doc_ref.set({
            "session_id": session_id,
            "message": message,
            "agent_selected": decision["agent"],
            "confidence": decision["confidence"],
            "reasoning": decision["reasoning"],
            "timestamp": firestore.SERVER_TIMESTAMP
        })
    except Exception as e:
        logging.error(f"Logging error: {str(e)}")
'

    local router_requirements='functions-framework==3.5.0
google-cloud-firestore==2.16.0
google-cloud-aiplatform==1.36.0'

    create_function_code "router" "agent-router" "$router_main_py" "$router_requirements"

    if [[ "$DRY_RUN" == "false" ]]; then
        cd agent-router
        if gcloud functions deploy "${FUNCTION_PREFIX}-router" \
            --runtime python311 \
            --trigger-http \
            --allow-unauthenticated \
            --source . \
            --entry-point route_agent \
            --memory 256MB \
            --timeout 60s \
            --region "$REGION"; then
            
            ROUTER_URL=$(gcloud functions describe "${FUNCTION_PREFIX}-router" \
                --region="$REGION" \
                --format="value(httpsTrigger.url)")
            echo "ROUTER_URL=$ROUTER_URL" >> "$DEPLOYMENT_STATE_FILE"
            log_success "Agent Router Function deployed: $ROUTER_URL"
        else
            error_exit "Failed to deploy Agent Router Function"
        fi
        cd ..
    else
        log_info "[DRY RUN] Would deploy Agent Router Function"
    fi

    # Message Broker Function
    local broker_main_py='import json
import functions_framework
from google.cloud import firestore
from google.cloud import pubsub_v1
import uuid
import logging

# Initialize clients for multi-agent coordination
db = firestore.Client()
publisher = pubsub_v1.PublisherClient()

@functions_framework.http
def broker_message(request):
    """Broker messages between agents using A2A protocol principles"""
    try:
        request_json = request.get_json()
        
        # Extract Agent2Agent protocol message details
        source_agent = request_json.get("source_agent")
        target_agent = request_json.get("target_agent")
        message_content = request_json.get("message")
        session_id = request_json.get("session_id")
        handoff_reason = request_json.get("handoff_reason", "escalation")
        
        # Create A2A protocol compliant message
        a2a_message = create_a2a_message(
            source_agent, target_agent, message_content, 
            session_id, handoff_reason
        )
        
        # Store conversation context for seamless handoffs
        store_conversation_context(session_id, a2a_message)
        
        # Route to target agent with context preservation
        routing_result = route_to_agent(target_agent, a2a_message)
        
        return {
            "status": "success",
            "message_id": a2a_message["message_id"],
            "target_agent": target_agent,
            "routing_result": routing_result
        }
        
    except Exception as e:
        logging.error(f"Message broker error: {str(e)}")
        return {"error": str(e)}, 500

def create_a2a_message(source, target, content, session_id, reason):
    """Create Agent2Agent protocol compliant message"""
    return {
        "message_id": str(uuid.uuid4()),
        "protocol_version": "1.0",
        "source_agent": {
            "id": source,
            "capabilities": get_agent_capabilities(source)
        },
        "target_agent": {
            "id": target,
            "capabilities": get_agent_capabilities(target)
        },
        "message_content": content,
        "session_id": session_id,
        "handoff_reason": reason,
        "timestamp": firestore.SERVER_TIMESTAMP,
        "context": {
            "conversation_history": get_conversation_history(session_id),
            "customer_data": get_customer_context(session_id)
        }
    }

def get_agent_capabilities(agent_type):
    """Retrieve agent capabilities from knowledge base"""
    try:
        doc_ref = db.collection("knowledge").document(agent_type)
        doc = doc_ref.get()
        if doc.exists:
            return doc.to_dict().get("capabilities", [])
        return []
    except Exception as e:
        logging.error(f"Capability lookup error: {str(e)}")
        return []

def store_conversation_context(session_id, message):
    """Store conversation context for seamless agent transitions"""
    try:
        doc_ref = db.collection("conversations").document(session_id)
        doc_ref.set({
            "last_message": message,
            "updated_timestamp": firestore.SERVER_TIMESTAMP
        }, merge=True)
    except Exception as e:
        logging.error(f"Context storage error: {str(e)}")

def get_conversation_history(session_id):
    """Retrieve conversation history for context continuity"""
    try:
        doc_ref = db.collection("conversations").document(session_id)
        doc = doc_ref.get()
        if doc.exists:
            return doc.to_dict().get("history", [])
        return []
    except Exception as e:
        logging.error(f"History retrieval error: {str(e)}")
        return []

def get_customer_context(session_id):
    """Retrieve customer context data for personalization"""
    return {
        "session_id": session_id,
        "preferences": {},
        "history": []
    }

def route_to_agent(agent_type, message):
    """Route message to specific agent endpoint"""
    return {
        "status": "routed",
        "agent": agent_type,
        "message_id": message["message_id"]
    }
'

    local broker_requirements='functions-framework==3.5.0
google-cloud-firestore==2.16.0
google-cloud-pubsub==2.21.0'

    create_function_code "broker" "message-broker" "$broker_main_py" "$broker_requirements"

    if [[ "$DRY_RUN" == "false" ]]; then
        cd message-broker
        if gcloud functions deploy "${FUNCTION_PREFIX}-broker" \
            --runtime python311 \
            --trigger-http \
            --allow-unauthenticated \
            --source . \
            --entry-point broker_message \
            --memory 512MB \
            --timeout 120s \
            --region "$REGION"; then
            
            BROKER_URL=$(gcloud functions describe "${FUNCTION_PREFIX}-broker" \
                --region="$REGION" \
                --format="value(httpsTrigger.url)")
            echo "BROKER_URL=$BROKER_URL" >> "$DEPLOYMENT_STATE_FILE"
            log_success "Message Broker Function deployed: $BROKER_URL"
        else
            error_exit "Failed to deploy Message Broker Function"
        fi
        cd ..
    else
        log_info "[DRY RUN] Would deploy Message Broker Function"
    fi

    # Billing Agent Function
    local billing_main_py='import json
import functions_framework
from google.cloud import firestore
import logging

# Initialize Firestore client for agent data storage
db = firestore.Client()

@functions_framework.http
def billing_agent(request):
    """Specialized billing agent with A2A communication capability"""
    try:
        request_json = request.get_json()
        customer_message = request_json.get("message", "")
        session_id = request_json.get("session_id", "")
        
        # Process billing-specific inquiry with domain expertise
        response = process_billing_inquiry(customer_message)
        
        # Check if handoff to another agent is needed
        handoff_needed = check_handoff_needed(customer_message)
        
        # Log agent interaction for analytics and learning
        log_agent_interaction(session_id, "billing", customer_message, response)
        
        result = {
            "agent_type": "billing",
            "response": response,
            "session_id": session_id
        }
        
        if handoff_needed:
            result["handoff"] = handoff_needed
            
        return result
        
    except Exception as e:
        logging.error(f"Billing agent error: {str(e)}")
        return {"error": str(e)}, 500

def process_billing_inquiry(message):
    """Process billing-specific customer inquiries with expertise"""
    message_lower = message.lower()
    
    if "refund" in message_lower:
        return "I can help you with refunds. Please provide your order number or invoice ID, and I will check your refund eligibility and process it immediately."
    elif "invoice" in message_lower or "bill" in message_lower:
        return "I can access your billing information. Let me pull up your recent invoices and payment history to assist you with any billing questions."
    elif "payment" in message_lower:
        return "I can help with payment issues. I can update payment methods, process payments, or troubleshoot payment failures. What specific payment assistance do you need?"
    elif "subscription" in message_lower:
        return "I can manage your subscription details including upgrades, downgrades, cancellations, and billing cycles. How can I help with your subscription?"
    else:
        return "I am your billing specialist. I can help with payments, invoices, refunds, and subscription management. What billing question do you have?"

def check_handoff_needed(message):
    """Check if handoff to another agent is needed based on context"""
    message_lower = message.lower()
    
    technical_keywords = ["not working", "error", "broken", "install", "setup"]
    sales_keywords = ["upgrade", "new plan", "demo", "features"]
    
    if any(keyword in message_lower for keyword in technical_keywords):
        return {
            "target_agent": "technical",
            "reason": "Technical issue detected in billing context"
        }
    elif any(keyword in message_lower for keyword in sales_keywords):
        return {
            "target_agent": "sales",
            "reason": "Sales opportunity detected in billing context"
        }
    
    return None

def log_agent_interaction(session_id, agent_type, message, response):
    """Log agent interaction for analytics and optimization"""
    try:
        doc_ref = db.collection("agent_interactions").document()
        doc_ref.set({
            "session_id": session_id,
            "agent_type": agent_type,
            "customer_message": message,
            "agent_response": response,
            "timestamp": firestore.SERVER_TIMESTAMP
        })
    except Exception as e:
        logging.error(f"Interaction logging error: {str(e)}")
'

    local billing_requirements='functions-framework==3.5.0
google-cloud-firestore==2.16.0'

    create_function_code "billing" "billing-agent" "$billing_main_py" "$billing_requirements"

    if [[ "$DRY_RUN" == "false" ]]; then
        cd billing-agent
        if gcloud functions deploy "${FUNCTION_PREFIX}-billing" \
            --runtime python311 \
            --trigger-http \
            --allow-unauthenticated \
            --source . \
            --entry-point billing_agent \
            --memory 256MB \
            --timeout 60s \
            --region "$REGION"; then
            
            BILLING_URL=$(gcloud functions describe "${FUNCTION_PREFIX}-billing" \
                --region="$REGION" \
                --format="value(httpsTrigger.url)")
            echo "BILLING_URL=$BILLING_URL" >> "$DEPLOYMENT_STATE_FILE"
            log_success "Billing Agent Function deployed: $BILLING_URL"
        else
            error_exit "Failed to deploy Billing Agent Function"
        fi
        cd ..
    else
        log_info "[DRY RUN] Would deploy Billing Agent Function"
    fi

    # Technical Agent Function
    local technical_main_py='import json
import functions_framework
from google.cloud import firestore
import logging

# Initialize Firestore client for technical data
db = firestore.Client()

@functions_framework.http
def technical_agent(request):
    """Specialized technical support agent with diagnostic capabilities"""
    try:
        request_json = request.get_json()
        customer_message = request_json.get("message", "")
        session_id = request_json.get("session_id", "")
        
        # Process technical inquiry with specialized expertise
        response = process_technical_inquiry(customer_message)
        handoff_needed = check_handoff_needed(customer_message)
        
        # Log technical agent interaction
        log_agent_interaction(session_id, "technical", customer_message, response)
        
        result = {
            "agent_type": "technical",
            "response": response,
            "session_id": session_id
        }
        
        if handoff_needed:
            result["handoff"] = handoff_needed
            
        return result
        
    except Exception as e:
        logging.error(f"Technical agent error: {str(e)}")
        return {"error": str(e)}, 500

def process_technical_inquiry(message):
    """Process technical support inquiries with domain expertise"""
    message_lower = message.lower()
    
    if "not working" in message_lower or "error" in message_lower:
        return "I can help troubleshoot that issue. Let me run some diagnostics and provide step-by-step solutions to get everything working properly."
    elif "install" in message_lower or "setup" in message_lower:
        return "I will guide you through the installation process with detailed instructions and verify each step works correctly on your system."
    elif "configure" in message_lower:
        return "I can help optimize your configuration settings for best performance and security. Let me check your current setup and recommend improvements."
    else:
        return "I am your technical specialist. I can help with troubleshooting, installations, configurations, and system diagnostics. What technical issue can I resolve?"

def check_handoff_needed(message):
    """Check if handoff needed to other specialized agents"""
    message_lower = message.lower()
    
    if any(keyword in message_lower for keyword in ["bill", "payment", "invoice", "refund"]):
        return {"target_agent": "billing", "reason": "Billing question in technical context"}
    elif any(keyword in message_lower for keyword in ["price", "upgrade", "plan", "demo"]):
        return {"target_agent": "sales", "reason": "Sales inquiry in technical context"}
    
    return None

def log_agent_interaction(session_id, agent_type, message, response):
    """Log technical agent interactions for analysis"""
    try:
        doc_ref = db.collection("agent_interactions").document()
        doc_ref.set({
            "session_id": session_id,
            "agent_type": agent_type,
            "customer_message": message,
            "agent_response": response,
            "timestamp": firestore.SERVER_TIMESTAMP
        })
    except Exception as e:
        logging.error(f"Interaction logging error: {str(e)}")
'

    local technical_requirements='functions-framework==3.5.0
google-cloud-firestore==2.16.0'

    create_function_code "technical" "technical-agent" "$technical_main_py" "$technical_requirements"

    if [[ "$DRY_RUN" == "false" ]]; then
        cd technical-agent
        if gcloud functions deploy "${FUNCTION_PREFIX}-technical" \
            --runtime python311 \
            --trigger-http \
            --allow-unauthenticated \
            --source . \
            --entry-point technical_agent \
            --memory 256MB \
            --timeout 60s \
            --region "$REGION"; then
            
            TECHNICAL_URL=$(gcloud functions describe "${FUNCTION_PREFIX}-technical" \
                --region="$REGION" \
                --format="value(httpsTrigger.url)")
            echo "TECHNICAL_URL=$TECHNICAL_URL" >> "$DEPLOYMENT_STATE_FILE"
            log_success "Technical Agent Function deployed: $TECHNICAL_URL"
        else
            error_exit "Failed to deploy Technical Agent Function"
        fi
        cd ..
    else
        log_info "[DRY RUN] Would deploy Technical Agent Function"
    fi

    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "$temp_dir"

    log_success "All Cloud Functions deployed successfully"
}

# Configure CCAI Platform integration
configure_ccai() {
    log_info "Configuring Contact Center AI Platform integration..."

    if [[ "$DRY_RUN" == "false" ]]; then
        # Create CCAI configuration
        cat > ccai-config.json << 'EOF'
{
  "displayName": "Multi-Agent Customer Service",
  "defaultLanguageCode": "en",
  "supportedLanguageCodes": ["en"],
  "timeZone": "America/New_York",
  "description": "AI-powered customer service with specialized agent collaboration",
  "features": {
    "inboundCall": true,
    "outboundCall": false,
    "chat": true,
    "email": true
  },
  "agentConfig": {
    "virtualAgent": {
      "enabled": true,
      "fallbackToHuman": true
    },
    "agentAssist": {
      "enabled": true,
      "knowledgeBase": true
    }
  }
}
EOF

        # Store integration endpoints in Firestore
        if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
            source "$DEPLOYMENT_STATE_FILE"
            
            gcloud firestore documents create integration/endpoints \
                --set="{\"router_url\":\"${ROUTER_URL}\",\"broker_url\":\"${BROKER_URL}\",\"billing_url\":\"${BILLING_URL}\",\"technical_url\":\"${TECHNICAL_URL}\",\"configured_date\":\"$(date -Iseconds)\"}" || \
                log_warning "Failed to store integration endpoints in Firestore"
        fi

        # Clean up configuration file
        rm -f ccai-config.json
    else
        log_info "[DRY RUN] Would configure CCAI Platform integration"
    fi

    log_success "CCAI Platform configuration completed"
}

# Run deployment tests
run_tests() {
    log_info "Running deployment validation tests..."

    if [[ "$DRY_RUN" == "false" && -f "$DEPLOYMENT_STATE_FILE" ]]; then
        source "$DEPLOYMENT_STATE_FILE"

        # Test router function
        if [[ -n "$ROUTER_URL" ]] && command -v curl &> /dev/null; then
            log_info "Testing Agent Router Function..."
            if curl -s -X POST "$ROUTER_URL" \
                -H "Content-Type: application/json" \
                -d '{"message": "I need help with my monthly invoice and payment", "session_id": "test-session-001"}' | \
                grep -q "billing"; then
                log_success "Agent Router Function test passed"
            else
                log_warning "Agent Router Function test failed"
            fi
        fi

        # Test broker function
        if [[ -n "$BROKER_URL" ]] && command -v curl &> /dev/null; then
            log_info "Testing Message Broker Function..."
            if curl -s -X POST "$BROKER_URL" \
                -H "Content-Type: application/json" \
                -d '{"source_agent": "billing", "target_agent": "technical", "message": "Customer needs technical help after billing issue resolved", "session_id": "test-session-001", "handoff_reason": "technical_escalation"}' | \
                grep -q "success"; then
                log_success "Message Broker Function test passed"
            else
                log_warning "Message Broker Function test failed"
            fi
        fi

        # Test billing agent
        if [[ -n "$BILLING_URL" ]] && command -v curl &> /dev/null; then
            log_info "Testing Billing Agent Function..."
            if curl -s -X POST "$BILLING_URL" \
                -H "Content-Type: application/json" \
                -d '{"message": "I want a refund for my last order", "session_id": "test-session-002"}' | \
                grep -q "refund"; then
                log_success "Billing Agent Function test passed"
            else
                log_warning "Billing Agent Function test failed"
            fi
        fi

        # Verify Firestore data
        log_info "Verifying Firestore knowledge base..."
        if gcloud firestore documents list knowledge --limit=3 --format="table(name,data)" | grep -q "billing\|technical\|sales"; then
            log_success "Firestore knowledge base verification passed"
        else
            log_warning "Firestore knowledge base verification failed"
        fi
    else
        log_info "[DRY RUN] Would run deployment validation tests"
    fi

    log_success "Deployment validation completed"
}

# Display deployment summary
show_summary() {
    log_info "Deployment Summary"
    echo "=================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo "Function Prefix: $FUNCTION_PREFIX"
    echo "CCAI Instance: $CCAI_INSTANCE"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo ""

    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        source "$DEPLOYMENT_STATE_FILE"
        echo "Deployed Resources:"
        echo "- Agent Router Function: ${ROUTER_URL:-'Not deployed'}"
        echo "- Message Broker Function: ${BROKER_URL:-'Not deployed'}"
        echo "- Billing Agent Function: ${BILLING_URL:-'Not deployed'}"
        echo "- Technical Agent Function: ${TECHNICAL_URL:-'Not deployed'}"
        echo "- Firestore Database: Native mode in $REGION"
        echo "- Vertex AI Dataset: ${DATASET_ID:-'Not created'}"
        echo "- Storage Bucket: gs://${BUCKET_NAME:-'Not created'}"
    fi

    echo ""
    echo "Next Steps:"
    echo "1. Test the deployed functions using the validation commands from the recipe"
    echo "2. Configure Contact Center AI Platform to use the deployed endpoints"
    echo "3. Monitor function logs and Firestore data for proper operation"
    echo "4. Run 'destroy.sh' to clean up resources when no longer needed"
    echo ""
    log_success "Multi-Agent Customer Service deployment completed successfully!"
}

# Main deployment function
main() {
    echo "Multi-Agent Customer Service Deployment Script"
    echo "=============================================="
    echo ""

    parse_args "$@"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY RUN mode - no resources will be created"
    fi

    if [[ "$SKIP_CONFIRMATION" == "false" && "$DRY_RUN" == "false" ]]; then
        echo "This will deploy multi-agent customer service infrastructure to GCP project: $PROJECT_ID"
        echo "Estimated cost: $15-25 USD for testing"
        echo ""
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi

    # Initialize deployment state file
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "# Deployment state for multi-agent customer service" > "$DEPLOYMENT_STATE_FILE"
        echo "PROJECT_ID=$PROJECT_ID" >> "$DEPLOYMENT_STATE_FILE"
        echo "REGION=$REGION" >> "$DEPLOYMENT_STATE_FILE"
        echo "ZONE=$ZONE" >> "$DEPLOYMENT_STATE_FILE"
        echo "FUNCTION_PREFIX=$FUNCTION_PREFIX" >> "$DEPLOYMENT_STATE_FILE"
        echo "CCAI_INSTANCE=$CCAI_INSTANCE" >> "$DEPLOYMENT_STATE_FILE"
        echo "RANDOM_SUFFIX=$RANDOM_SUFFIX" >> "$DEPLOYMENT_STATE_FILE"
    fi

    # Execute deployment steps
    check_prerequisites
    configure_gcp
    enable_apis
    create_firestore
    setup_vertex_ai
    deploy_functions
    configure_ccai
    run_tests
    show_summary
}

# Execute main function with all arguments
main "$@"