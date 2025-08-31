#!/bin/bash

# Intelligent Business Process Automation with ADK and Workflows - Deployment Script
# This script deploys a complete business process automation system using
# Vertex AI Agent Development Kit, Cloud Workflows, Cloud SQL, and Cloud Functions

set -euo pipefail

# Colors for output
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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_LOG="${SCRIPT_DIR}/deploy.log"
RESOURCE_TRACKER="${SCRIPT_DIR}/.deployed_resources"

# Initialize logging
exec 1> >(tee -a "$DEPLOY_LOG")
exec 2> >(tee -a "$DEPLOY_LOG" >&2)

log_info "Starting deployment at $(date)"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_error "Please install gcloud CLI: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "No active Google Cloud authentication found"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check required tools
    local required_tools=("openssl" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool '$tool' is not installed"
            exit 1
        fi
    done
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID="${PROJECT_ID:-bpa-automation-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export DB_INSTANCE="${DB_INSTANCE:-business-process-db}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export WORKFLOW_NAME="${WORKFLOW_NAME:-business-process-workflow-${RANDOM_SUFFIX}}"
    export AGENT_APP="${AGENT_APP:-bpa-agent-${RANDOM_SUFFIX}}"
    export FUNCTION_APPROVAL="${FUNCTION_APPROVAL:-process-approval-${RANDOM_SUFFIX}}"
    export FUNCTION_NOTIFY="${FUNCTION_NOTIFY:-process-notification-${RANDOM_SUFFIX}}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" 2>/dev/null || true
    gcloud config set compute/region "${REGION}" 2>/dev/null || true
    gcloud config set compute/zone "${ZONE}" 2>/dev/null || true
    
    log_success "Environment configured for project: ${PROJECT_ID}"
}

# Function to track deployed resources
track_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_location="${3:-global}"
    
    echo "${resource_type}:${resource_name}:${resource_location}" >> "$RESOURCE_TRACKER"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "workflows.googleapis.com"
        "sqladmin.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "eventarc.googleapis.com"
        "artifactregistry.googleapis.com"
        "run.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling API: $api"
        if gcloud services enable "$api" --quiet; then
            log_success "Enabled API: $api"
        else
            log_error "Failed to enable API: $api"
            exit 1
        fi
    done
    
    log_info "Waiting for APIs to be fully activated (30 seconds)..."
    sleep 30
    log_success "All required APIs enabled"
}

# Function to create Cloud SQL database
create_database() {
    log_info "Creating Cloud SQL PostgreSQL instance..."
    
    # Check if instance already exists
    if gcloud sql instances describe "$DB_INSTANCE" --quiet 2>/dev/null; then
        log_warning "Cloud SQL instance $DB_INSTANCE already exists"
    else
        log_info "Creating new Cloud SQL instance: $DB_INSTANCE"
        if gcloud sql instances create "$DB_INSTANCE" \
            --database-version=POSTGRES_15 \
            --tier=db-f1-micro \
            --region="$REGION" \
            --backup-start-time=03:00 \
            --storage-auto-increase \
            --quiet; then
            
            track_resource "sql_instance" "$DB_INSTANCE" "$REGION"
            log_success "Cloud SQL instance created successfully"
        else
            log_error "Failed to create Cloud SQL instance"
            exit 1
        fi
    fi
    
    # Set database password
    export DB_PASSWORD=$(openssl rand -base64 32)
    log_info "Setting database password..."
    if gcloud sql users set-password postgres \
        --instance="$DB_INSTANCE" \
        --password="$DB_PASSWORD" \
        --quiet; then
        log_success "Database password set"
    else
        log_error "Failed to set database password"
        exit 1
    fi
    
    # Create application database
    log_info "Creating application database..."
    if gcloud sql databases create business_processes \
        --instance="$DB_INSTANCE" \
        --quiet; then
        log_success "Application database created"
    else
        log_warning "Application database may already exist"
    fi
    
    # Wait for instance to be ready
    log_info "Waiting for Cloud SQL instance to be ready..."
    while true; do
        local state=$(gcloud sql instances describe "$DB_INSTANCE" \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        if [[ "$state" == "RUNNABLE" ]]; then
            log_success "Cloud SQL instance is ready"
            break
        else
            log_info "Waiting for instance to be ready (current state: $state)..."
            sleep 30
        fi
    done
}

# Function to initialize database schema
initialize_schema() {
    log_info "Initializing database schema..."
    
    # Create schema file
    cat > "${SCRIPT_DIR}/schema.sql" << 'EOF'
CREATE TABLE IF NOT EXISTS process_requests (
    id SERIAL PRIMARY KEY,
    request_id VARCHAR(50) UNIQUE NOT NULL,
    requester_email VARCHAR(255) NOT NULL,
    process_type VARCHAR(100) NOT NULL,
    request_data JSONB NOT NULL,
    status VARCHAR(50) DEFAULT 'pending',
    priority INTEGER DEFAULT 3,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS process_approvals (
    id SERIAL PRIMARY KEY,
    request_id VARCHAR(50) REFERENCES process_requests(request_id),
    approver_email VARCHAR(255) NOT NULL,
    decision VARCHAR(20) NOT NULL,
    comments TEXT,
    approved_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS process_audit (
    id SERIAL PRIMARY KEY,
    request_id VARCHAR(50) REFERENCES process_requests(request_id),
    action VARCHAR(100) NOT NULL,
    actor VARCHAR(255) NOT NULL,
    details JSONB,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_requests_status ON process_requests(status);
CREATE INDEX IF NOT EXISTS idx_requests_type ON process_requests(process_type);
CREATE INDEX IF NOT EXISTS idx_audit_request ON process_audit(request_id);
EOF
    
    # Execute schema creation with retry logic
    local max_retries=3
    local retry_count=0
    
    while [[ $retry_count -lt $max_retries ]]; do
        if echo "$(cat "${SCRIPT_DIR}/schema.sql")" | \
           gcloud sql connect "$DB_INSTANCE" --user=postgres \
           --database=business_processes --quiet; then
            log_success "Database schema initialized successfully"
            break
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                log_warning "Schema initialization failed, retrying ($retry_count/$max_retries)..."
                sleep 10
            else
                log_error "Failed to initialize database schema after $max_retries attempts"
                exit 1
            fi
        fi
    done
    
    # Clean up schema file
    rm -f "${SCRIPT_DIR}/schema.sql"
}

# Function to deploy Cloud Functions
deploy_functions() {
    log_info "Deploying Cloud Functions..."
    
    local temp_dir="${SCRIPT_DIR}/temp_functions"
    mkdir -p "$temp_dir"
    
    # Deploy approval function
    log_info "Creating approval function..."
    mkdir -p "${temp_dir}/approval-function"
    
    cat > "${temp_dir}/approval-function/main.py" << 'EOF'
import functions_framework
import json
import os
import pg8000
from datetime import datetime

@functions_framework.http
def approve_process(request):
    """Process approval function with business logic"""
    try:
        request_json = request.get_json()
        request_id = request_json.get('request_id')
        decision = request_json.get('decision')
        approver = request_json.get('approver_email')
        comments = request_json.get('comments', '')
        
        # Connect to Cloud SQL using Unix socket
        db_socket_path = "/cloudsql"
        instance_connection_name = f"{os.environ['PROJECT_ID']}:{os.environ['REGION']}:{os.environ['DB_INSTANCE']}"
        
        conn = pg8000.connect(
            user='postgres',
            password=os.environ['DB_PASSWORD'],
            unix_sock=f"{db_socket_path}/{instance_connection_name}/.s.PGSQL.5432",
            database='business_processes'
        )
        
        cursor = conn.cursor()
        
        # Record approval decision
        cursor.execute("""
            INSERT INTO process_approvals 
            (request_id, approver_email, decision, comments)
            VALUES (%s, %s, %s, %s)
        """, (request_id, approver, decision, comments))
        
        # Update process status
        new_status = 'approved' if decision == 'approve' else 'rejected'
        cursor.execute("""
            UPDATE process_requests 
            SET status = %s, updated_at = CURRENT_TIMESTAMP
            WHERE request_id = %s
        """, (new_status, request_id))
        
        # Add audit entry
        cursor.execute("""
            INSERT INTO process_audit 
            (request_id, action, actor, details)
            VALUES (%s, %s, %s, %s)
        """, (request_id, f'Process {decision}d', approver, 
             json.dumps({'decision': decision, 'comments': comments})))
        
        conn.commit()
        conn.close()
        
        return {'status': 'success', 'new_status': new_status}
        
    except Exception as e:
        return {'status': 'error', 'message': str(e)}, 500
EOF
    
    cat > "${temp_dir}/approval-function/requirements.txt" << 'EOF'
functions-framework==3.*
pg8000==1.30.*
EOF
    
    log_info "Deploying approval function: $FUNCTION_APPROVAL"
    if (cd "${temp_dir}/approval-function" && \
        gcloud functions deploy "$FUNCTION_APPROVAL" \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --memory 256Mi \
        --timeout 60s \
        --region "$REGION" \
        --set-env-vars "DB_PASSWORD=${DB_PASSWORD},PROJECT_ID=${PROJECT_ID},REGION=${REGION},DB_INSTANCE=${DB_INSTANCE}" \
        --set-cloudsql-instances "${PROJECT_ID}:${REGION}:${DB_INSTANCE}" \
        --quiet); then
        
        track_resource "function" "$FUNCTION_APPROVAL" "$REGION"
        log_success "Approval function deployed successfully"
    else
        log_error "Failed to deploy approval function"
        exit 1
    fi
    
    # Deploy notification function
    log_info "Creating notification function..."
    mkdir -p "${temp_dir}/notification-function"
    
    cat > "${temp_dir}/notification-function/main.py" << 'EOF'
import functions_framework
import json
import os
import pg8000
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

@functions_framework.http
def send_notification(request):
    """Send process notifications to stakeholders"""
    try:
        request_json = request.get_json()
        request_id = request_json.get('request_id')
        notification_type = request_json.get('type')
        recipient = request_json.get('recipient_email')
        
        # Connect to database using Unix socket
        db_socket_path = "/cloudsql"
        instance_connection_name = f"{os.environ['PROJECT_ID']}:{os.environ['REGION']}:{os.environ['DB_INSTANCE']}"
        
        conn = pg8000.connect(
            user='postgres',
            password=os.environ['DB_PASSWORD'],
            unix_sock=f"{db_socket_path}/{instance_connection_name}/.s.PGSQL.5432",
            database='business_processes'
        )
        
        cursor = conn.cursor()
        cursor.execute("""
            SELECT process_type, status, requester_email, created_at
            FROM process_requests WHERE request_id = %s
        """, (request_id,))
        
        process_data = cursor.fetchone()
        if not process_data:
            return {'status': 'error', 'message': 'Process not found'}, 404
        
        process_type, status, requester, created_at = process_data
        
        # Create notification content
        subject = f"Process Update: {process_type} - {status.title()}"
        body = f"""
        Process ID: {request_id}
        Type: {process_type}
        Status: {status.title()}
        Requester: {requester}
        Created: {created_at}
        
        This is an automated notification from the Business Process Automation system.
        """
        
        # Log notification in audit trail
        cursor.execute("""
            INSERT INTO process_audit 
            (request_id, action, actor, details)
            VALUES (%s, %s, %s, %s)
        """, (request_id, 'Notification sent', 'system', 
             json.dumps({'type': notification_type, 'recipient': recipient})))
        
        conn.commit()
        conn.close()
        
        # In production, integrate with actual email service
        print(f"Notification sent to {recipient}: {subject}")
        
        return {'status': 'success', 'notification_sent': True}
        
    except Exception as e:
        return {'status': 'error', 'message': str(e)}, 500
EOF
    
    cat > "${temp_dir}/notification-function/requirements.txt" << 'EOF'
functions-framework==3.*
pg8000==1.30.*
EOF
    
    log_info "Deploying notification function: $FUNCTION_NOTIFY"
    if (cd "${temp_dir}/notification-function" && \
        gcloud functions deploy "$FUNCTION_NOTIFY" \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --memory 256Mi \
        --timeout 60s \
        --region "$REGION" \
        --set-env-vars "DB_PASSWORD=${DB_PASSWORD},PROJECT_ID=${PROJECT_ID},REGION=${REGION},DB_INSTANCE=${DB_INSTANCE}" \
        --set-cloudsql-instances "${PROJECT_ID}:${REGION}:${DB_INSTANCE}" \
        --quiet); then
        
        track_resource "function" "$FUNCTION_NOTIFY" "$REGION"
        log_success "Notification function deployed successfully"
    else
        log_error "Failed to deploy notification function"
        exit 1
    fi
    
    # Deploy agent function
    log_info "Creating AI agent function..."
    mkdir -p "${temp_dir}/agent-function"
    
    cat > "${temp_dir}/agent-function/main.py" << 'EOF'
import functions_framework
import json
import re
import uuid
import os
import pg8000
from datetime import datetime

@functions_framework.http
def process_natural_language(request):
    """Process natural language business requests"""
    try:
        request_json = request.get_json()
        user_input = request_json.get('message', '')
        user_email = request_json.get('user_email', '')
        
        # Simple NLP processing (in production, use Vertex AI ADK)
        processed_request = analyze_request(user_input)
        
        # Generate unique request ID
        request_id = str(uuid.uuid4())[:8]
        
        # Store initial request in database
        db_socket_path = "/cloudsql"
        instance_connection_name = f"{os.environ['PROJECT_ID']}:{os.environ['REGION']}:{os.environ['DB_INSTANCE']}"
        
        conn = pg8000.connect(
            user='postgres',
            password=os.environ['DB_PASSWORD'],
            unix_sock=f"{db_socket_path}/{instance_connection_name}/.s.PGSQL.5432",
            database='business_processes'
        )
        
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO process_requests 
            (request_id, requester_email, process_type, request_data, priority)
            VALUES (%s, %s, %s, %s, %s)
        """, (request_id, user_email, processed_request['intent'], 
             json.dumps(processed_request['entities']), processed_request['priority']))
        
        # Add audit entry
        cursor.execute("""
            INSERT INTO process_audit 
            (request_id, action, actor, details)
            VALUES (%s, %s, %s, %s)
        """, (request_id, 'Request created', user_email, 
             json.dumps({'original_message': user_input, 'interpretation': processed_request})))
        
        conn.commit()
        conn.close()
        
        # Prepare workflow input
        workflow_input = {
            'request_id': request_id,
            'process_type': processed_request['intent'],
            'requester_email': user_email,
            'request_data': processed_request['entities'],
            'priority': processed_request['priority']
        }
        
        return {
            'status': 'success',
            'request_id': request_id,
            'workflow_input': workflow_input,
            'interpretation': processed_request
        }
        
    except Exception as e:
        return {'status': 'error', 'message': str(e)}, 500

def analyze_request(text):
    """Simple intent and entity extraction"""
    text_lower = text.lower()
    
    # Intent classification
    if any(word in text_lower for word in ['expense', 'cost', 'money', 'receipt']):
        intent = 'expense_approval'
        priority = 2 if any(word in text_lower for word in ['urgent', 'asap']) else 3
    elif any(word in text_lower for word in ['leave', 'vacation', 'time off', 'sick']):
        intent = 'leave_request'
        priority = 1 if 'sick' in text_lower else 3
    elif any(word in text_lower for word in ['access', 'permission', 'account']):
        intent = 'access_request'
        priority = 2
    else:
        intent = 'general_request'
        priority = 3
        
    # Entity extraction (simplified)
    entities = {}
    
    # Extract monetary amounts
    money_pattern = r'\$?(\d+(?:,\d{3})*(?:\.\d{2})?)'
    money_matches = re.findall(money_pattern, text)
    if money_matches:
        entities['amount'] = money_matches[0]
        
    # Extract dates (simplified)
    date_patterns = [
        r'(\d{1,2}/\d{1,2}/\d{4})',
        r'(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2}',
        r'(tomorrow|today|next week|next month)'
    ]
    
    for pattern in date_patterns:
        dates = re.findall(pattern, text, re.IGNORECASE)
        if dates:
            entities['date'] = dates[0]
            break
            
    return {
        'intent': intent,
        'entities': entities,
        'priority': priority,
        'confidence': 0.85
    }
EOF
    
    cat > "${temp_dir}/agent-function/requirements.txt" << 'EOF'
functions-framework==3.*
pg8000==1.30.*
EOF
    
    log_info "Deploying AI agent function: $AGENT_APP"
    if (cd "${temp_dir}/agent-function" && \
        gcloud functions deploy "$AGENT_APP" \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --memory 256Mi \
        --timeout 60s \
        --region "$REGION" \
        --set-env-vars "DB_PASSWORD=${DB_PASSWORD},PROJECT_ID=${PROJECT_ID},REGION=${REGION},DB_INSTANCE=${DB_INSTANCE}" \
        --set-cloudsql-instances "${PROJECT_ID}:${REGION}:${DB_INSTANCE}" \
        --quiet); then
        
        track_resource "function" "$AGENT_APP" "$REGION"
        log_success "AI agent function deployed successfully"
    else
        log_error "Failed to deploy AI agent function"
        exit 1
    fi
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
}

# Function to deploy workflow
deploy_workflow() {
    log_info "Deploying Cloud Workflow..."
    
    # Get function URLs
    local approval_url notification_url
    approval_url=$(gcloud functions describe "$FUNCTION_APPROVAL" \
        --gen2 \
        --region="$REGION" \
        --format="value(serviceConfig.uri)")
    
    notification_url=$(gcloud functions describe "$FUNCTION_NOTIFY" \
        --gen2 \
        --region="$REGION" \
        --format="value(serviceConfig.uri)")
    
    if [[ -z "$approval_url" || -z "$notification_url" ]]; then
        log_error "Failed to retrieve function URLs"
        exit 1
    fi
    
    log_info "Function URLs retrieved successfully"
    
    # Create workflow definition
    cat > "${SCRIPT_DIR}/business-process-workflow.yaml" << EOF
main:
  params: [input]
  steps:
    - init:
        assign:
          - request_id: \${input.request_id}
          - process_type: \${input.process_type}
          - requester_email: \${input.requester_email}
          - request_data: \${input.request_data}
          - priority: \${default(input.priority, 3)}
          - approval_url: "${approval_url}"
          - notification_url: "${notification_url}"
          
    - log_start:
        call: sys.log
        args:
          text: \${"Starting process automation for request: " + request_id}
          severity: INFO
          
    - analyze_request:
        call: classify_process_type
        args:
          process_type: \${process_type}
          priority: \${priority}
        result: classification
        
    - route_process:
        switch:
          - condition: \${classification.requires_approval}
            steps:
              - request_approval:
                  call: http.post
                  args:
                    url: \${approval_url}
                    body:
                      request_id: \${request_id}
                      decision: \${"approve" if classification.auto_approve else "pending"}
                      approver_email: \${classification.approver_email}
                      comments: "Auto-approved based on business rules"
                  result: approval_result
                  
              - notify_stakeholders:
                  call: http.post
                  args:
                    url: \${notification_url}
                    body:
                      request_id: \${request_id}
                      type: "approval_requested"
                      recipient_email: \${classification.approver_email}
                  result: notification_result
                  
          - condition: \${classification.auto_process}
            steps:
              - auto_process:
                  call: sys.log
                  args:
                    text: \${"Auto-processing request: " + request_id}
                    severity: INFO
                    
              - complete_auto_process:
                  call: http.post
                  args:
                    url: \${approval_url}
                    body:
                      request_id: \${request_id}
                      decision: "approve"
                      approver_email: "system@automation"
                      comments: "Auto-approved based on business rules"
                  result: auto_approval
                  
    - final_notification:
        call: http.post
        args:
          url: \${notification_url}
          body:
            request_id: \${request_id}
            type: "process_completed"
            recipient_email: \${requester_email}
        result: final_notify
        
    - return_result:
        return:
          status: "completed"
          request_id: \${request_id}
          classification: \${classification}

classify_process_type:
  params: [process_type, priority]
  steps:
    - determine_routing:
        switch:
          - condition: \${process_type == "expense_approval"}
            assign:
              - requires_approval: true
              - auto_approve: \${priority <= 2}
              - approver_email: "finance@company.com"
              - auto_process: false
          - condition: \${process_type == "leave_request"}
            assign:
              - requires_approval: true
              - auto_approve: false
              - approver_email: "hr@company.com"
              - auto_process: false
          - condition: \${process_type == "access_request"}
            assign:
              - requires_approval: true
              - auto_approve: \${priority >= 4}
              - approver_email: "security@company.com"
              - auto_process: false
          - condition: true
            assign:
              - requires_approval: false
              - auto_approve: false
              - approver_email: ""
              - auto_process: true
              
    - return_classification:
        return:
          requires_approval: \${requires_approval}
          auto_approve: \${auto_approve}
          approver_email: \${approver_email}
          auto_process: \${auto_process}
EOF
    
    # Deploy workflow
    log_info "Deploying workflow: $WORKFLOW_NAME"
    if gcloud workflows deploy "$WORKFLOW_NAME" \
        --source="${SCRIPT_DIR}/business-process-workflow.yaml" \
        --location="$REGION" \
        --quiet; then
        
        track_resource "workflow" "$WORKFLOW_NAME" "$REGION"
        log_success "Workflow deployed successfully"
    else
        log_error "Failed to deploy workflow"
        exit 1
    fi
    
    # Clean up workflow file
    rm -f "${SCRIPT_DIR}/business-process-workflow.yaml"
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check Cloud SQL instance
    local sql_state
    sql_state=$(gcloud sql instances describe "$DB_INSTANCE" \
        --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$sql_state" != "RUNNABLE" ]]; then
        log_error "Cloud SQL instance is not in RUNNABLE state: $sql_state"
        return 1
    fi
    log_success "Cloud SQL instance is running"
    
    # Check functions
    local functions=("$FUNCTION_APPROVAL" "$FUNCTION_NOTIFY" "$AGENT_APP")
    for func in "${functions[@]}"; do
        local func_state
        func_state=$(gcloud functions describe "$func" \
            --gen2 \
            --region="$REGION" \
            --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "$func_state" != "ACTIVE" ]]; then
            log_error "Function $func is not in ACTIVE state: $func_state"
            return 1
        fi
    done
    log_success "All Cloud Functions are active"
    
    # Check workflow
    local workflow_state
    workflow_state=$(gcloud workflows describe "$WORKFLOW_NAME" \
        --location="$REGION" \
        --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$workflow_state" != "ACTIVE" ]]; then
        log_error "Workflow is not in ACTIVE state: $workflow_state"
        return 1
    fi
    log_success "Workflow is active"
    
    log_success "All components deployed and verified successfully"
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local info_file="${SCRIPT_DIR}/deployment_info.json"
    cat > "$info_file" << EOF
{
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "resources": {
    "sql_instance": "$DB_INSTANCE",
    "workflow": "$WORKFLOW_NAME",
    "functions": {
      "approval": "$FUNCTION_APPROVAL",
      "notification": "$FUNCTION_NOTIFY",
      "agent": "$AGENT_APP"
    }
  },
  "endpoints": {
    "approval_function": "$(gcloud functions describe "$FUNCTION_APPROVAL" --gen2 --region="$REGION" --format="value(serviceConfig.uri)" 2>/dev/null)",
    "notification_function": "$(gcloud functions describe "$FUNCTION_NOTIFY" --gen2 --region="$REGION" --format="value(serviceConfig.uri)" 2>/dev/null)",
    "agent_function": "$(gcloud functions describe "$AGENT_APP" --gen2 --region="$REGION" --format="value(serviceConfig.uri)" 2>/dev/null)"
  }
}
EOF
    
    log_success "Deployment information saved to: $info_file"
}

# Function to display next steps
display_next_steps() {
    log_info "Deployment completed successfully!"
    echo ""
    echo "==================== DEPLOYMENT SUMMARY ===================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Cloud SQL Instance: $DB_INSTANCE"
    echo "Workflow: $WORKFLOW_NAME"
    echo "Functions:"
    echo "  - Approval: $FUNCTION_APPROVAL"
    echo "  - Notification: $FUNCTION_NOTIFY"
    echo "  - AI Agent: $AGENT_APP"
    echo ""
    echo "==================== NEXT STEPS ===================="
    echo "1. Test the AI agent function:"
    echo "   curl -X POST $(gcloud functions describe "$AGENT_APP" --gen2 --region="$REGION" --format="value(serviceConfig.uri)") \\"
    echo "     -H \"Content-Type: application/json\" \\"
    echo "     -d '{\"message\": \"I need approval for a \$500 expense\", \"user_email\": \"test@company.com\"}'"
    echo ""
    echo "2. Execute a workflow:"
    echo "   gcloud workflows execute $WORKFLOW_NAME \\"
    echo "     --location=$REGION \\"
    echo "     --data='{\"request_id\": \"test-001\", \"process_type\": \"expense_approval\", \"requester_email\": \"test@company.com\", \"request_data\": {\"amount\": \"250\"}, \"priority\": 3}'"
    echo ""
    echo "3. Monitor logs:"
    echo "   gcloud logging read \"resource.type=cloud_function\" --limit=10"
    echo ""
    echo "4. To clean up resources, run:"
    echo "   ./destroy.sh"
    echo "============================================================="
}

# Main execution
main() {
    log_info "Starting Intelligent Business Process Automation deployment"
    
    # Initialize resource tracker
    > "$RESOURCE_TRACKER"
    
    check_prerequisites
    setup_environment
    enable_apis
    create_database
    initialize_schema
    deploy_functions
    deploy_workflow
    verify_deployment
    save_deployment_info
    display_next_steps
    
    log_success "Deployment completed successfully at $(date)"
}

# Error handling
trap 'log_error "Script failed at line $LINENO. Check the log file: $DEPLOY_LOG"' ERR

# Run main function
main "$@"