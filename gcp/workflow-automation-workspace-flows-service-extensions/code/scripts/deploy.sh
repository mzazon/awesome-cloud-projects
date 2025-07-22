#!/bin/bash

# Workflow Automation with Google Workspace Flows and Service Extensions - Deployment Script
# This script deploys the complete intelligent document processing workflow infrastructure

set -euo pipefail

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

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    # Attempt cleanup of partially created resources
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        gcloud functions delete "${FUNCTION_NAME}" --quiet --region="${REGION}" 2>/dev/null || true
    fi
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        gcloud pubsub topics delete "${TOPIC_NAME}" --quiet 2>/dev/null || true
    fi
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        gsutil rm -rf "gs://${BUCKET_NAME}" 2>/dev/null || true
    fi
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check if required APIs can be enabled (basic permission check)
    if ! gcloud services list --enabled --filter="name:serviceusage.googleapis.com" --format="value(name)" | grep -q "serviceusage"; then
        log_error "Insufficient permissions to manage APIs. Please ensure you have Editor/Owner role."
        exit 1
    fi
    
    # Check if curl is available for testing
    if ! command -v curl &> /dev/null; then
        log_warning "curl is not installed. Function testing will be skipped."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random suffixes."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default project ID or prompt user
    if [[ -z "${PROJECT_ID:-}" ]]; then
        DEFAULT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -n "$DEFAULT_PROJECT" ]]; then
            log_info "Using current project: $DEFAULT_PROJECT"
            export PROJECT_ID="$DEFAULT_PROJECT"
        else
            read -p "Enter your Google Cloud Project ID: " PROJECT_ID
            export PROJECT_ID
        fi
    fi
    
    # Set region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export FUNCTION_NAME="doc-processor-${RANDOM_SUFFIX}"
    export TOPIC_NAME="document-events-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_NAME="doc-processing-sub-${RANDOM_SUFFIX}"
    export BUCKET_NAME="workflow-docs-${RANDOM_SUFFIX}"
    
    # Set project configuration
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Environment configured for project: ${PROJECT_ID}"
    log_info "Resources will be created with suffix: ${RANDOM_SUFFIX}"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "pubsub.googleapis.com"
        "storage.googleapis.com"
        "serviceextensions.googleapis.com"
        "admin.googleapis.com"
        "monitoring.googleapis.com"
        "chat.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
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

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: ${BUCKET_NAME}..."
    
    # Create storage bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        log_success "Created storage bucket: gs://${BUCKET_NAME}"
    else
        log_error "Failed to create storage bucket"
        exit 1
    fi
    
    # Enable versioning
    gsutil versioning set on "gs://${BUCKET_NAME}"
    log_success "Enabled versioning on bucket"
    
    # Set up lifecycle policy
    cat > lifecycle-policy.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 30}
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 90}
      }
    ]
  }
}
EOF
    
    gsutil lifecycle set lifecycle-policy.json "gs://${BUCKET_NAME}"
    log_success "Applied lifecycle policy to bucket"
    
    # Clean up temporary file
    rm -f lifecycle-policy.json
}

# Create Pub/Sub infrastructure
create_pubsub_infrastructure() {
    log_info "Creating Pub/Sub topics and subscriptions..."
    
    # Create main topic
    if gcloud pubsub topics create "${TOPIC_NAME}"; then
        log_success "Created Pub/Sub topic: ${TOPIC_NAME}"
    else
        log_error "Failed to create Pub/Sub topic"
        exit 1
    fi
    
    # Create subscription
    if gcloud pubsub subscriptions create "${SUBSCRIPTION_NAME}" \
        --topic="${TOPIC_NAME}" \
        --ack-deadline=600 \
        --message-retention-duration=7d; then
        log_success "Created subscription: ${SUBSCRIPTION_NAME}"
    else
        log_error "Failed to create subscription"
        exit 1
    fi
    
    # Create dead letter topic
    gcloud pubsub topics create "${TOPIC_NAME}-deadletter"
    gcloud pubsub subscriptions create "${SUBSCRIPTION_NAME}-deadletter" \
        --topic="${TOPIC_NAME}-deadletter"
    
    # Update subscription with dead letter policy
    gcloud pubsub subscriptions update "${SUBSCRIPTION_NAME}" \
        --dead-letter-topic="projects/${PROJECT_ID}/topics/${TOPIC_NAME}-deadletter" \
        --max-delivery-attempts=5
    
    log_success "Pub/Sub infrastructure created with dead letter handling"
}

# Deploy Cloud Functions
deploy_cloud_functions() {
    log_info "Deploying Cloud Functions..."
    
    # Create function directories
    mkdir -p cloud-functions/doc-processor
    mkdir -p cloud-functions/approval-webhook
    mkdir -p cloud-functions/chat-notifications
    mkdir -p cloud-functions/analytics
    
    # Deploy document processor function
    log_info "Deploying document processor function..."
    cd cloud-functions/doc-processor
    
    cat > package.json << 'EOF'
{
  "name": "document-processor",
  "version": "1.0.0",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0",
    "@google-cloud/pubsub": "^4.0.0",
    "@google-cloud/storage": "^7.0.0",
    "googleapis": "^126.0.0"
  }
}
EOF
    
    cat > index.js << EOF
const {GoogleAuth} = require('google-auth-library');
const {PubSub} = require('@google-cloud/pubsub');
const {Storage} = require('@google-cloud/storage');
const {google} = require('googleapis');

const pubsub = new PubSub();
const storage = new Storage();

exports.processDocument = async (req, res) => {
  try {
    const {fileName, bucketName, metadata} = req.body;
    
    // Extract document metadata
    const bucket = storage.bucket(bucketName);
    const file = bucket.file(fileName);
    const [fileMetadata] = await file.getMetadata();
    
    // Prepare processing event
    const processingEvent = {
      documentId: fileName,
      timestamp: new Date().toISOString(),
      metadata: {
        size: fileMetadata.size,
        contentType: fileMetadata.contentType,
        created: fileMetadata.timeCreated,
        ...metadata
      },
      processingStage: 'analysis',
      workflowId: \`workflow-\${Date.now()}\`
    };
    
    // Publish to Pub/Sub for workflow processing
    const topicName = '${TOPIC_NAME}';
    const dataBuffer = Buffer.from(JSON.stringify(processingEvent));
    
    await pubsub.topic(topicName).publish(dataBuffer);
    
    res.status(200).json({
      success: true,
      workflowId: processingEvent.workflowId,
      message: 'Document processing initiated'
    });
    
  } catch (error) {
    console.error('Processing error:', error);
    res.status(500).json({error: error.message});
  }
};
EOF
    
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime=nodejs20 \
        --trigger=http \
        --entry-point=processDocument \
        --memory=512MB \
        --timeout=540s \
        --set-env-vars="TOPIC_NAME=${TOPIC_NAME}" \
        --allow-unauthenticated \
        --region="${REGION}"; then
        log_success "Deployed document processor function"
    else
        log_error "Failed to deploy document processor function"
        exit 1
    fi
    
    cd ../..
    
    # Deploy approval webhook
    log_info "Deploying approval webhook function..."
    cd cloud-functions/approval-webhook
    
    cat > package.json << 'EOF'
{
  "name": "approval-webhook",
  "version": "1.0.0",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0",
    "@google-cloud/pubsub": "^4.0.0",
    "@google-cloud/storage": "^7.0.0",
    "googleapis": "^126.0.0"
  }
}
EOF
    
    cat > index.js << EOF
const {PubSub} = require('@google-cloud/pubsub');
const {google} = require('googleapis');

const pubsub = new PubSub();

exports.handleApproval = async (req, res) => {
  try {
    const {workflowId, approverEmail, decision, comments} = req.body;
    
    // Validate approval decision
    if (!['approved', 'rejected', 'needs_revision'].includes(decision)) {
      return res.status(400).json({error: 'Invalid decision value'});
    }
    
    // Create approval event
    const approvalEvent = {
      workflowId,
      approver: approverEmail,
      decision,
      comments: comments || '',
      timestamp: new Date().toISOString(),
      processingStage: 'approval_decision'
    };
    
    // Publish approval decision to Pub/Sub
    const topicName = '${TOPIC_NAME}';
    const dataBuffer = Buffer.from(JSON.stringify(approvalEvent));
    await pubsub.topic(topicName).publish(dataBuffer);
    
    res.status(200).json({
      success: true,
      workflowId,
      message: \`Approval \${decision} recorded successfully\`
    });
    
  } catch (error) {
    console.error('Approval processing error:', error);
    res.status(500).json({error: error.message});
  }
};
EOF
    
    gcloud functions deploy "approval-webhook-${RANDOM_SUFFIX}" \
        --runtime=nodejs20 \
        --trigger=http \
        --entry-point=handleApproval \
        --memory=256MB \
        --timeout=300s \
        --set-env-vars="TOPIC_NAME=${TOPIC_NAME}" \
        --allow-unauthenticated \
        --region="${REGION}"
    
    cd ../..
    
    # Deploy chat notifications function
    log_info "Deploying chat notifications function..."
    cd cloud-functions/chat-notifications
    
    cat > package.json << 'EOF'
{
  "name": "chat-notifications",
  "version": "1.0.0",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0",
    "googleapis": "^126.0.0"
  }
}
EOF
    
    cat > index.js << 'EOF'
const {google} = require('googleapis');

exports.sendChatNotification = async (req, res) => {
  try {
    const {message, spaceId, threadKey} = req.body;
    
    const auth = new google.auth.GoogleAuth({
      scopes: ['https://www.googleapis.com/auth/chat.bot']
    });
    
    const chat = google.chat({version: 'v1', auth});
    
    const chatMessage = {
      text: message,
      cards: [{
        header: {
          title: 'Document Workflow Update',
          subtitle: 'Intelligent Processing System',
          imageUrl: 'https://developers.google.com/chat/images/chat-product-icon.png'
        },
        sections: [{
          widgets: [{
            textParagraph: {
              text: message
            }
          }]
        }]
      }]
    };
    
    const response = await chat.spaces.messages.create({
      parent: `spaces/${spaceId}`,
      requestBody: chatMessage,
      threadKey: threadKey
    });
    
    res.status(200).json({
      success: true,
      messageId: response.data.name
    });
    
  } catch (error) {
    console.error('Chat notification error:', error);
    res.status(500).json({error: error.message});
  }
};
EOF
    
    gcloud functions deploy "chat-notifications-${RANDOM_SUFFIX}" \
        --runtime=nodejs20 \
        --trigger=http \
        --entry-point=sendChatNotification \
        --memory=256MB \
        --timeout=180s \
        --allow-unauthenticated \
        --region="${REGION}"
    
    cd ../..
    
    # Deploy analytics function
    log_info "Deploying analytics collection function..."
    cd cloud-functions/analytics
    
    cat > package.json << 'EOF'
{
  "name": "workflow-analytics",
  "version": "1.0.0",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.0.0",
    "@google-cloud/monitoring": "^3.0.0",
    "@google-cloud/pubsub": "^4.0.0"
  }
}
EOF
    
    cat > index.js << EOF
const {PubSub} = require('@google-cloud/pubsub');
const monitoring = require('@google-cloud/monitoring');

const client = new monitoring.MetricServiceClient();
const pubsub = new PubSub();

exports.collectAnalytics = async (pubsubMessage, context) => {
  try {
    const messageData = JSON.parse(
      Buffer.from(pubsubMessage.data, 'base64').toString()
    );
    
    // Create custom metrics for workflow analysis
    const projectId = process.env.GCP_PROJECT || '${PROJECT_ID}';
    const projectPath = client.projectPath(projectId);
    
    const timeSeriesData = {
      metric: {
        type: 'custom.googleapis.com/workflow/processing_time',
        labels: {
          document_type: messageData.metadata?.document_type || 'unknown',
          processing_stage: messageData.processingStage || 'unknown'
        }
      },
      resource: {
        type: 'global',
        labels: {
          project_id: projectId
        }
      },
      points: [{
        interval: {
          endTime: {
            seconds: Math.floor(Date.now() / 1000)
          }
        },
        value: {
          doubleValue: Date.now() - new Date(messageData.timestamp).getTime()
        }
      }]
    };
    
    await client.createTimeSeries({
      name: projectPath,
      timeSeries: [timeSeriesData]
    });
    
    console.log('Analytics data recorded for workflow:', messageData.workflowId);
    
  } catch (error) {
    console.error('Analytics collection error:', error);
  }
};
EOF
    
    gcloud functions deploy "analytics-collector-${RANDOM_SUFFIX}" \
        --runtime=nodejs20 \
        --trigger-topic="${TOPIC_NAME}" \
        --entry-point=collectAnalytics \
        --memory=256MB \
        --timeout=180s \
        --region="${REGION}"
    
    cd ../..
    
    log_success "All Cloud Functions deployed successfully"
}

# Create service extensions structure
create_service_extensions() {
    log_info "Creating Service Extensions structure..."
    
    mkdir -p service-extensions/business-rules/src
    
    # Create Rust project structure
    cat > service-extensions/business-rules/Cargo.toml << 'EOF'
[package]
name = "document-rules"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
proxy-wasm = "0.2"
log = "0.4"

[dependencies.web-sys]
version = "0.3"
features = [
  "console",
]
EOF
    
    # Create the business rules implementation
    cat > service-extensions/business-rules/src/lib.rs << 'EOF'
use proxy_wasm::traits::*;
use proxy_wasm::types::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Serialize, Deserialize, Debug)]
struct DocumentMetadata {
    document_type: String,
    department: String,
    priority: String,
    estimated_value: Option<f64>,
}

#[derive(Serialize, Deserialize, Debug)]
struct ApprovalRule {
    approvers: Vec<String>,
    max_processing_time: u32,
    requires_legal_review: bool,
}

proxy_wasm::main! {{
    proxy_wasm::set_log_level(LogLevel::Trace);
    proxy_wasm::set_http_context(|_, _| -> Box<dyn HttpContext> {
        Box::new(DocumentProcessor)
    });
}}

struct DocumentProcessor;

impl Context for DocumentProcessor {}

impl HttpContext for DocumentProcessor {
    fn on_http_request_headers(&mut self, _: usize, _: bool) -> Action {
        Action::Continue
    }

    fn on_http_request_body(&mut self, body_size: usize, end_of_stream: bool) -> Action {
        if !end_of_stream {
            return Action::Pause;
        }

        if let Some(body) = self.get_http_request_body(0, body_size) {
            if let Ok(metadata) = serde_json::from_slice::<DocumentMetadata>(&body) {
                let approval_rule = self.determine_approval_workflow(&metadata);
                
                if let Ok(rule_json) = serde_json::to_string(&approval_rule) {
                    self.set_http_request_header("x-approval-rule", Some(&rule_json));
                }
            }
        }

        Action::Continue
    }
}

impl DocumentProcessor {
    fn determine_approval_workflow(&self, metadata: &DocumentMetadata) -> ApprovalRule {
        match metadata.document_type.as_str() {
            "contract" => ApprovalRule {
                approvers: vec!["legal@company.com".to_string(), "finance@company.com".to_string()],
                max_processing_time: 72,
                requires_legal_review: true,
            },
            "invoice" => {
                if let Some(value) = metadata.estimated_value {
                    if value > 10000.0 {
                        ApprovalRule {
                            approvers: vec!["finance@company.com".to_string(), "cfo@company.com".to_string()],
                            max_processing_time: 48,
                            requires_legal_review: false,
                        }
                    } else {
                        ApprovalRule {
                            approvers: vec!["manager@company.com".to_string()],
                            max_processing_time: 24,
                            requires_legal_review: false,
                        }
                    }
                } else {
                    ApprovalRule {
                        approvers: vec!["manager@company.com".to_string()],
                        max_processing_time: 24,
                        requires_legal_review: false,
                    }
                }
            },
            _ => ApprovalRule {
                approvers: vec!["admin@company.com".to_string()],
                max_processing_time: 24,
                requires_legal_review: false,
            },
        }
    }
}
EOF
    
    log_success "Service Extensions structure created"
    log_warning "Note: WebAssembly compilation requires Rust toolchain installation"
}

# Create workspace flows configuration
create_workspace_flows_config() {
    log_info "Creating Google Workspace Flows configuration..."
    
    mkdir -p workspace-flows
    
    cat > workspace-flows/document-approval-flow.json << EOF
{
  "flowName": "Intelligent Document Approval",
  "description": "Automated document processing with AI-powered routing",
  "trigger": {
    "type": "drive_file_upload",
    "watchedFolders": ["Shared drives/Document Processing"],
    "fileTypes": ["pdf", "docx", "xlsx"]
  },
  "steps": [
    {
      "id": "extract_metadata",
      "type": "gemini_analysis",
      "prompt": "Analyze this document and extract: document type, department, priority level, estimated value if applicable. Return as JSON.",
      "model": "gemini-2.5-pro"
    },
    {
      "id": "call_cloud_function",
      "type": "http_request",
      "url": "https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}",
      "method": "POST",
      "headers": {
        "Content-Type": "application/json"
      },
      "body": {
        "fileName": "{{trigger.file.name}}",
        "bucketName": "${BUCKET_NAME}",
        "metadata": "{{steps.extract_metadata.output}}"
      }
    },
    {
      "id": "determine_approvers",
      "type": "gemini_decision",
      "prompt": "Based on the document analysis: {{steps.extract_metadata.output}}, determine the approval workflow. Consider document type, value, and department policies.",
      "model": "gemini-2.5-pro"
    },
    {
      "id": "create_approval_task",
      "type": "gmail_send",
      "to": "{{steps.determine_approvers.approvers}}",
      "subject": "Document Approval Required: {{trigger.file.name}}",
      "body": "Please review and approve the document: {{trigger.file.url}}\n\nDocument Type: {{steps.extract_metadata.document_type}}\nPriority: {{steps.extract_metadata.priority}}\nDeadline: {{steps.determine_approvers.deadline}}"
    },
    {
      "id": "log_to_sheets",
      "type": "sheets_append",
      "spreadsheetId": "WORKFLOW_TRACKING_SHEET_ID",
      "range": "Tracking!A:F",
      "values": [
        [
          "{{steps.call_cloud_function.workflowId}}",
          "{{trigger.file.name}}",
          "{{steps.extract_metadata.document_type}}",
          "{{steps.extract_metadata.priority}}",
          "{{now}}",
          "pending_approval"
        ]
      ]
    }
  ],
  "errorHandling": {
    "onFailure": "notify_admin",
    "retryAttempts": 3,
    "adminEmail": "admin@company.com"
  }
}
EOF
    
    log_success "Workspace Flows configuration created"
    log_warning "Manual configuration required in Google Workspace Flows admin panel"
}

# Create monitoring configuration
create_monitoring_config() {
    log_info "Creating monitoring configuration..."
    
    mkdir -p monitoring
    
    cat > monitoring/workflow-dashboard.json << EOF
{
  "displayName": "Intelligent Workflow Analytics",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Document Processing Volume",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${FUNCTION_NAME}\"",
                  "aggregation": {
                    "alignmentPeriod": "300s",
                    "perSeriesAligner": "ALIGN_RATE",
                    "crossSeriesReducer": "REDUCE_SUM"
                  }
                }
              }
            }]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Approval Response Times",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"pubsub_topic\" AND resource.labels.topic_id=\"${TOPIC_NAME}\"",
                  "aggregation": {
                    "alignmentPeriod": "300s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        }
      }
    ]
  }
}
EOF
    
    log_success "Monitoring configuration created"
}

# Perform validation tests
run_validation_tests() {
    log_info "Running validation tests..."
    
    # Test Cloud Functions deployment
    local functions=(
        "${FUNCTION_NAME}"
        "approval-webhook-${RANDOM_SUFFIX}"
        "chat-notifications-${RANDOM_SUFFIX}"
        "analytics-collector-${RANDOM_SUFFIX}"
    )
    
    for func in "${functions[@]}"; do
        if gcloud functions describe "${func}" --region="${REGION}" &>/dev/null; then
            log_success "Function ${func} is deployed and accessible"
        else
            log_error "Function ${func} is not accessible"
        fi
    done
    
    # Test Pub/Sub infrastructure
    if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
        log_success "Pub/Sub topic ${TOPIC_NAME} is accessible"
    else
        log_error "Pub/Sub topic ${TOPIC_NAME} is not accessible"
    fi
    
    # Test storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_success "Storage bucket ${BUCKET_NAME} is accessible"
    else
        log_error "Storage bucket ${BUCKET_NAME} is not accessible"
    fi
    
    # Test function endpoint (if curl is available)
    if command -v curl &> /dev/null; then
        log_info "Testing document processor function endpoint..."
        local function_url="https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}"
        local test_payload='{"fileName":"test-document.pdf","bucketName":"'${BUCKET_NAME}'","metadata":{"document_type":"invoice","department":"finance","priority":"high"}}'
        
        if curl -s -X POST "${function_url}" \
            -H "Content-Type: application/json" \
            -d "${test_payload}" | grep -q "success"; then
            log_success "Document processor function is responding correctly"
        else
            log_warning "Document processor function test failed or returned unexpected response"
        fi
    fi
    
    log_success "Validation tests completed"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > deployment-info.txt << EOF
Workflow Automation Deployment Information
==========================================

Project ID: ${PROJECT_ID}
Region: ${REGION}
Zone: ${ZONE}
Deployment Date: $(date)

Resources Created:
- Storage Bucket: gs://${BUCKET_NAME}
- Pub/Sub Topic: ${TOPIC_NAME}
- Pub/Sub Subscription: ${SUBSCRIPTION_NAME}
- Cloud Functions:
  * Document Processor: ${FUNCTION_NAME}
  * Approval Webhook: approval-webhook-${RANDOM_SUFFIX}
  * Chat Notifications: chat-notifications-${RANDOM_SUFFIX}
  * Analytics Collector: analytics-collector-${RANDOM_SUFFIX}

Function URLs:
- Document Processor: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/${FUNCTION_NAME}
- Approval Webhook: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/approval-webhook-${RANDOM_SUFFIX}
- Chat Notifications: https://${REGION}-${PROJECT_ID}.cloudfunctions.net/chat-notifications-${RANDOM_SUFFIX}

Next Steps:
1. Configure Google Workspace Flows using the template in workspace-flows/document-approval-flow.json
2. Set up Google Sheets tracking spreadsheet
3. Configure Google Chat spaces for notifications
4. Test the complete workflow with sample documents

For cleanup, run: ./destroy.sh
EOF
    
    log_success "Deployment information saved to deployment-info.txt"
}

# Main deployment function
main() {
    log_info "Starting Workflow Automation deployment..."
    
    check_prerequisites
    setup_environment
    enable_apis
    create_storage_bucket
    create_pubsub_infrastructure
    deploy_cloud_functions
    create_service_extensions
    create_workspace_flows_config
    create_monitoring_config
    run_validation_tests
    save_deployment_info
    
    log_success "🎉 Deployment completed successfully!"
    log_info "📋 Check deployment-info.txt for resource details and next steps"
    log_warning "⚠️  Remember to configure Google Workspace Flows manually in the admin panel"
    log_info "💰 Estimated monthly cost: \$50-150 (varies by usage)"
    log_info "🧹 To clean up resources, run: ./destroy.sh"
}

# Run main function
main "$@"