#!/bin/bash

# Customer Service Automation with Contact Center AI and Vertex AI Search
# Deployment Script for GCP Recipe
# 
# This script deploys an intelligent customer service system that leverages:
# - Contact Center AI for conversation analytics
# - Vertex AI Search for enterprise knowledge base search
# - Cloud Run for scalable API processing
# - Cloud Storage for document management

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly REQUIRED_APIS=(
    "contactcenteraiplatform.googleapis.com"
    "discoveryengine.googleapis.com"
    "run.googleapis.com"
    "storage.googleapis.com"
    "aiplatform.googleapis.com"
    "cloudbuild.googleapis.com"
)

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO: $*"
}

log_warn() {
    log "WARN: $*"
}

log_error() {
    log "ERROR: $*"
}

log_success() {
    log "SUCCESS: $*"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code ${exit_code}"
    log_error "Check the log file: ${LOG_FILE}"
    log_error "To clean up any partially created resources, run: ${SCRIPT_DIR}/destroy.sh"
    exit $exit_code
}

trap cleanup_on_error ERR

# Helper functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active gcloud authentication found. Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if project is set
    if ! gcloud config get-value project > /dev/null 2>&1; then
        log_error "No default project set. Please run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    # Check if required tools are available
    for tool in curl openssl; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool '$tool' is not installed"
            exit 1
        fi
    done
    
    log_success "Prerequisites check completed"
}

check_billing() {
    log_info "Checking billing account..."
    
    local project_id
    project_id=$(gcloud config get-value project)
    
    if ! gcloud beta billing projects describe "$project_id" --format="value(billingEnabled)" 2>/dev/null | grep -q "True"; then
        log_error "Billing is not enabled for project $project_id"
        log_error "Please enable billing: https://console.cloud.google.com/billing/linkedaccount?project=$project_id"
        exit 1
    fi
    
    log_success "Billing is enabled"
}

enable_apis() {
    log_info "Enabling required APIs..."
    
    for api in "${REQUIRED_APIS[@]}"; do
        log_info "Enabling API: $api"
        if gcloud services enable "$api" --quiet; then
            log_success "API enabled: $api"
        else
            log_error "Failed to enable API: $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Get project ID and set basic variables
    export PROJECT_ID
    PROJECT_ID=$(gcloud config get-value project)
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    local random_suffix
    random_suffix=$(openssl rand -hex 3)
    export BUCKET_NAME="customer-service-kb-${random_suffix}"
    export SEARCH_ENGINE_ID="customer-service-search-${random_suffix}"
    export CLOUD_RUN_SERVICE="customer-service-api-${random_suffix}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log_success "Environment variables configured:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  REGION: ${REGION}"
    log_info "  ZONE: ${ZONE}"
    log_info "  BUCKET_NAME: ${BUCKET_NAME}"
    log_info "  SEARCH_ENGINE_ID: ${SEARCH_ENGINE_ID}"
    log_info "  CLOUD_RUN_SERVICE: ${CLOUD_RUN_SERVICE}"
}

create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for knowledge base documents..."
    
    # Create storage bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        log_success "Storage bucket created: gs://${BUCKET_NAME}"
    else
        log_error "Failed to create storage bucket"
        exit 1
    fi
    
    # Enable versioning for document protection
    if gsutil versioning set on "gs://${BUCKET_NAME}"; then
        log_success "Versioning enabled for bucket"
    else
        log_warn "Failed to enable versioning"
    fi
    
    # Set lifecycle policy for cost optimization
    cat > /tmp/lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 30}
      }
    ]
  }
}
EOF
    
    if gsutil lifecycle set /tmp/lifecycle.json "gs://${BUCKET_NAME}"; then
        log_success "Lifecycle policy applied to bucket"
    else
        log_warn "Failed to apply lifecycle policy"
    fi
    
    rm -f /tmp/lifecycle.json
}

upload_knowledge_base_documents() {
    log_info "Creating and uploading sample knowledge base documents..."
    
    # Create temporary directory for knowledge base documents
    local kb_dir="/tmp/knowledge-base-$$"
    mkdir -p "$kb_dir"
    
    # Create FAQ document
    cat > "$kb_dir/customer-faq.txt" <<EOF
Frequently Asked Questions

Q: How do I reset my password?
A: To reset your password, click on the "Forgot Password" link on the login page and follow the instructions sent to your email.

Q: What are your business hours?
A: Our customer service is available Monday through Friday, 9 AM to 6 PM EST.

Q: How do I cancel my subscription?
A: You can cancel your subscription by logging into your account and navigating to the billing section.

Q: What payment methods do you accept?
A: We accept all major credit cards, PayPal, and bank transfers.

Q: How can I contact customer support?
A: You can reach our support team via email at support@company.com or through our live chat feature.

Q: What is your refund policy?
A: We offer full refunds within 30 days of purchase. Please see our refund policy page for details.
EOF
    
    # Create troubleshooting guide
    cat > "$kb_dir/troubleshooting-guide.txt" <<EOF
Technical Troubleshooting Guide

Issue: Login Problems
Solution: Clear browser cache and cookies, ensure JavaScript is enabled, try incognito mode.

Issue: Payment Processing Errors
Solution: Verify card details, check with bank for international transaction blocks, try alternative payment method.

Issue: Account Access Issues
Solution: Confirm email address, check spam folder for verification emails, contact support if account is locked.

Issue: Performance Issues
Solution: Check internet connection, try different browser, clear application cache.

Issue: Mobile App Not Working
Solution: Update the app to the latest version, restart your device, check app permissions.

Issue: Email Notifications Not Received
Solution: Check spam folder, verify email address in account settings, add our domain to safe senders list.
EOF
    
    # Create policy document
    cat > "$kb_dir/policies.txt" <<EOF
Company Policies and Procedures

Refund Policy: Full refunds available within 30 days of purchase with proof of purchase.

Privacy Policy: We protect customer data according to GDPR and CCPA regulations.

Return Policy: Items must be returned in original condition within 14 days.

Shipping Policy: Standard shipping takes 3-5 business days, expedited shipping available.

Terms of Service: By using our service, you agree to our terms and conditions.

Data Protection: We use industry-standard encryption to protect your personal information.
EOF
    
    # Upload documents to Cloud Storage
    if gsutil -m cp "$kb_dir"/*.txt "gs://${BUCKET_NAME}/knowledge-base/"; then
        log_success "Knowledge base documents uploaded"
    else
        log_error "Failed to upload knowledge base documents"
        rm -rf "$kb_dir"
        exit 1
    fi
    
    # Clean up temporary directory
    rm -rf "$kb_dir"
}

create_vertex_ai_search_engine() {
    log_info "Creating Vertex AI Search engine..."
    
    # Create Vertex AI Search data store
    local create_response
    create_response=$(curl -s -X POST \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d '{
          "displayName": "Customer Service Knowledge Base",
          "industryVertical": "GENERIC",
          "solutionTypes": ["SOLUTION_TYPE_SEARCH"],
          "contentConfig": "CONTENT_REQUIRED",
          "documentProcessingConfig": {
            "defaultParsingConfig": {
              "digitalParsingConfig": {}
            }
          }
        }' \
        "https://discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/collections/default_collection/dataStores?dataStoreId=${SEARCH_ENGINE_ID}")
    
    if echo "$create_response" | grep -q "error"; then
        log_error "Failed to create Vertex AI Search data store"
        log_error "Response: $create_response"
        exit 1
    fi
    
    log_success "Vertex AI Search data store created"
    
    # Wait for data store creation
    log_info "Waiting for data store to be ready..."
    sleep 45
    
    # Import documents from Cloud Storage
    log_info "Importing documents into search engine..."
    local import_response
    import_response=$(curl -s -X POST \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d '{
          "gcsSource": {
            "inputUris": ["gs://'${BUCKET_NAME}'/knowledge-base/*"],
            "dataSchema": "content"
          },
          "idField": "id",
          "errorConfig": {
            "gcsPrefix": "gs://'${BUCKET_NAME}'/import-errors/"
          }
        }' \
        "https://discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/collections/default_collection/dataStores/${SEARCH_ENGINE_ID}/branches/0/documents:import")
    
    if echo "$import_response" | grep -q "error"; then
        log_error "Failed to import documents"
        log_error "Response: $import_response"
        exit 1
    fi
    
    log_success "Document import initiated"
}

create_search_application() {
    log_info "Creating search application..."
    
    # Wait a bit more for the data store to be fully ready
    sleep 30
    
    # Create search application (engine)
    local app_response
    app_response=$(curl -s -X POST \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        -H "Content-Type: application/json" \
        -d '{
          "displayName": "Customer Service Search App",
          "dataStoreIds": ["'${SEARCH_ENGINE_ID}'"],
          "solutionType": "SOLUTION_TYPE_SEARCH",
          "searchEngineConfig": {
            "searchTier": "SEARCH_TIER_STANDARD",
            "searchAddOns": ["SEARCH_ADD_ON_LLM"]
          }
        }' \
        "https://discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/collections/default_collection/engines?engineId=${SEARCH_ENGINE_ID}-app")
    
    if echo "$app_response" | grep -q "error"; then
        log_error "Failed to create search application"
        log_error "Response: $app_response"
        exit 1
    fi
    
    log_success "Search application created with LLM capabilities"
    sleep 15
}

deploy_cloud_run_service() {
    log_info "Creating Cloud Run API service..."
    
    # Create temporary directory for API service code
    local api_dir="/tmp/customer-service-api-$$"
    mkdir -p "$api_dir"
    
    # Create main.py
    cat > "$api_dir/main.py" <<'EOF'
import os
import json
import logging
from flask import Flask, request, jsonify
from google.cloud import discoveryengine
from google.oauth2 import service_account

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Initialize Vertex AI Search client
PROJECT_ID = os.environ.get('PROJECT_ID')
SEARCH_ENGINE_ID = os.environ.get('SEARCH_ENGINE_ID')
client = discoveryengine.SearchServiceClient()

@app.route('/search', methods=['POST'])
def search_knowledge_base():
    """Search knowledge base using customer inquiry"""
    try:
        data = request.get_json()
        query = data.get('query', '')
        
        if not query:
            return jsonify({'error': 'Query is required'}), 400
        
        # Configure search request
        serving_config = f"projects/{PROJECT_ID}/locations/global/collections/default_collection/engines/{SEARCH_ENGINE_ID}-app/servingConfigs/default_config"
        
        search_request = discoveryengine.SearchRequest(
            serving_config=serving_config,
            query=query,
            page_size=5,
            content_search_spec=discoveryengine.SearchRequest.ContentSearchSpec(
                snippet_spec=discoveryengine.SearchRequest.ContentSearchSpec.SnippetSpec(
                    return_snippet=True
                ),
                summary_spec=discoveryengine.SearchRequest.ContentSearchSpec.SummarySpec(
                    summary_result_count=3,
                    include_citations=True
                )
            )
        )
        
        # Execute search
        response = client.search(search_request)
        
        # Format results
        results = {
            'query': query,
            'summary': response.summary.summary_text if response.summary else '',
            'results': []
        }
        
        for result in response.results:
            doc_data = {
                'title': result.document.derived_struct_data.get('title', 'Document'),
                'snippet': result.document.derived_struct_data.get('snippets', [''])[0].get('snippet', ''),
                'uri': result.document.derived_struct_data.get('link', ''),
                'relevance_score': result.relevance_score
            }
            results['results'].append(doc_data)
        
        return jsonify(results)
        
    except Exception as e:
        logging.error(f"Search error: {str(e)}")
        return jsonify({'error': 'Search failed', 'details': str(e)}), 500

@app.route('/analyze-conversation', methods=['POST'])
def analyze_conversation():
    """Analyze conversation data and provide recommendations"""
    try:
        data = request.get_json()
        conversation_text = data.get('conversation', '')
        
        if not conversation_text:
            return jsonify({'error': 'Conversation text is required'}), 400
        
        # Simple intent detection (in production, use Contact Center AI)
        intents = {
            'password_reset': ['password', 'reset', 'login', 'access'],
            'billing_inquiry': ['bill', 'charge', 'payment', 'subscription'],
            'technical_support': ['error', 'problem', 'issue', 'bug', 'not working'],
            'cancellation': ['cancel', 'unsubscribe', 'stop', 'end']
        }
        
        detected_intent = 'general_inquiry'
        for intent, keywords in intents.items():
            if any(keyword in conversation_text.lower() for keyword in keywords):
                detected_intent = intent
                break
        
        # Search for relevant information
        search_query = f"{detected_intent} {conversation_text}"
        serving_config = f"projects/{PROJECT_ID}/locations/global/collections/default_collection/engines/{SEARCH_ENGINE_ID}-app/servingConfigs/default_config"
        
        search_request = discoveryengine.SearchRequest(
            serving_config=serving_config,
            query=search_query,
            page_size=3
        )
        
        search_response = client.search(search_request)
        
        recommendations = {
            'detected_intent': detected_intent,
            'confidence': 0.85,  # Mock confidence score
            'suggested_responses': [],
            'relevant_documents': []
        }
        
        for result in search_response.results:
            doc_info = {
                'title': result.document.derived_struct_data.get('title', 'Document'),
                'snippet': result.document.derived_struct_data.get('snippets', [''])[0].get('snippet', '')
            }
            recommendations['relevant_documents'].append(doc_info)
        
        return jsonify(recommendations)
        
    except Exception as e:
        logging.error(f"Analysis error: {str(e)}")
        return jsonify({'error': 'Analysis failed', 'details': str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'service': 'customer-service-api'})

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=int(os.environ.get('PORT', 8080)))
EOF
    
    # Create requirements.txt
    cat > "$api_dir/requirements.txt" <<EOF
Flask==2.3.3
google-cloud-discoveryengine==0.11.11
google-auth==2.23.3
gunicorn==21.2.0
EOF
    
    # Create Dockerfile
    cat > "$api_dir/Dockerfile" <<EOF
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD exec gunicorn --bind :\$PORT --workers 1 --threads 8 --timeout 0 main:app
EOF
    
    # Deploy to Cloud Run
    log_info "Building and deploying Cloud Run service..."
    cd "$api_dir"
    
    if gcloud run deploy "${CLOUD_RUN_SERVICE}" \
        --source . \
        --platform managed \
        --region "${REGION}" \
        --allow-unauthenticated \
        --set-env-vars "PROJECT_ID=${PROJECT_ID},SEARCH_ENGINE_ID=${SEARCH_ENGINE_ID}" \
        --memory 1Gi \
        --cpu 1 \
        --max-instances 10 \
        --quiet; then
        log_success "Cloud Run service deployed"
    else
        log_error "Failed to deploy Cloud Run service"
        cd - > /dev/null
        rm -rf "$api_dir"
        exit 1
    fi
    
    cd - > /dev/null
    rm -rf "$api_dir"
}

setup_iam_permissions() {
    log_info "Setting up IAM permissions..."
    
    # Get the default compute service account
    local service_account
    service_account="${PROJECT_ID}-compute@developer.gserviceaccount.com"
    
    # Grant necessary permissions
    local roles=(
        "roles/contactcenteraiplatform.admin"
        "roles/discoveryengine.admin"
        "roles/storage.objectViewer"
    )
    
    for role in "${roles[@]}"; do
        if gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account}" \
            --role="$role" \
            --quiet; then
            log_success "IAM role granted: $role"
        else
            log_warn "Failed to grant IAM role: $role"
        fi
    done
}

create_agent_dashboard() {
    log_info "Creating agent dashboard interface..."
    
    # Create dashboard HTML file
    local dashboard_dir="/tmp/agent-dashboard-$$"
    mkdir -p "$dashboard_dir"
    
    # Get Cloud Run service URL
    local service_url
    service_url=$(gcloud run services describe "${CLOUD_RUN_SERVICE}" \
        --region="${REGION}" \
        --format="value(status.url)")
    
    cat > "$dashboard_dir/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Customer Service AI Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { background: #4285f4; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .card { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .input-group { margin-bottom: 15px; }
        .input-group label { display: block; margin-bottom: 5px; font-weight: bold; }
        .input-group input, .input-group textarea { width: 100%; padding: 10px; border: 1px solid #ddd; border-radius: 4px; box-sizing: border-box; }
        .btn { background: #4285f4; color: white; padding: 10px 20px; border: none; border-radius: 4px; cursor: pointer; }
        .btn:hover { background: #3367d6; }
        .results { margin-top: 20px; }
        .result-item { background: #f8f9fa; padding: 15px; border-left: 4px solid #4285f4; margin-bottom: 10px; }
        .loading { color: #666; font-style: italic; }
        .error { color: #d93025; }
        .success { color: #137333; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Customer Service AI Assistant</h1>
            <p>Intelligent search and conversation analysis for customer support</p>
            <p>Service URL: ${service_url}</p>
        </div>
        
        <div class="card">
            <h3>Knowledge Base Search</h3>
            <div class="input-group">
                <label for="searchQuery">Customer Inquiry:</label>
                <input type="text" id="searchQuery" placeholder="Enter customer question or issue...">
            </div>
            <button class="btn" onclick="searchKnowledgeBase()">Search Knowledge Base</button>
            <div id="searchResults" class="results"></div>
        </div>
        
        <div class="card">
            <h3>Conversation Analysis</h3>
            <div class="input-group">
                <label for="conversationText">Conversation Text:</label>
                <textarea id="conversationText" rows="5" placeholder="Paste conversation text here..."></textarea>
            </div>
            <button class="btn" onclick="analyzeConversation()">Analyze Conversation</button>
            <div id="analysisResults" class="results"></div>
        </div>
    </div>

    <script>
        const API_BASE_URL = '${service_url}';
        
        async function searchKnowledgeBase() {
            const query = document.getElementById('searchQuery').value;
            if (!query) {
                alert('Please enter a search query');
                return;
            }
            
            const container = document.getElementById('searchResults');
            container.innerHTML = '<div class="loading">Searching...</div>';
            
            try {
                const response = await fetch(\`\${API_BASE_URL}/search\`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ query })
                });
                
                const data = await response.json();
                
                if (response.ok) {
                    displaySearchResults(data);
                } else {
                    container.innerHTML = \`<div class="error">Error: \${data.error}</div>\`;
                }
            } catch (error) {
                container.innerHTML = \`<div class="error">Network error: \${error.message}</div>\`;
            }
        }
        
        function displaySearchResults(data) {
            const container = document.getElementById('searchResults');
            let html = '';
            
            if (data.summary) {
                html += \`<div class="result-item"><strong>AI Summary:</strong> \${data.summary}</div>\`;
            }
            
            if (data.results && data.results.length > 0) {
                data.results.forEach(result => {
                    html += \`
                        <div class="result-item">
                            <strong>\${result.title}</strong><br>
                            \${result.snippet}<br>
                            <small>Relevance: \${(result.relevance_score * 100).toFixed(1)}%</small>
                        </div>
                    \`;
                });
            } else {
                html += '<div class="result-item">No results found</div>';
            }
            
            container.innerHTML = html;
        }
        
        async function analyzeConversation() {
            const conversation = document.getElementById('conversationText').value;
            if (!conversation) {
                alert('Please enter conversation text');
                return;
            }
            
            const container = document.getElementById('analysisResults');
            container.innerHTML = '<div class="loading">Analyzing...</div>';
            
            try {
                const response = await fetch(\`\${API_BASE_URL}/analyze-conversation\`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ conversation })
                });
                
                const data = await response.json();
                
                if (response.ok) {
                    displayAnalysisResults(data);
                } else {
                    container.innerHTML = \`<div class="error">Error: \${data.error}</div>\`;
                }
            } catch (error) {
                container.innerHTML = \`<div class="error">Network error: \${error.message}</div>\`;
            }
        }
        
        function displayAnalysisResults(data) {
            const container = document.getElementById('analysisResults');
            let html = \`
                <div class="result-item">
                    <strong>Detected Intent:</strong> \${data.detected_intent}<br>
                    <strong>Confidence:</strong> \${(data.confidence * 100).toFixed(1)}%
                </div>
            \`;
            
            if (data.relevant_documents && data.relevant_documents.length > 0) {
                data.relevant_documents.forEach(doc => {
                    html += \`
                        <div class="result-item">
                            <strong>\${doc.title}</strong><br>
                            \${doc.snippet}
                        </div>
                    \`;
                });
            }
            
            container.innerHTML = html;
        }
    </script>
</body>
</html>
EOF
    
    # Upload dashboard to Cloud Storage
    if gsutil cp "$dashboard_dir/index.html" "gs://${BUCKET_NAME}/dashboard/"; then
        log_success "Agent dashboard uploaded"
    else
        log_warn "Failed to upload agent dashboard"
    fi
    
    # Make bucket web-accessible for the dashboard
    if gsutil web set -m index.html -e 404.html "gs://${BUCKET_NAME}"; then
        log_success "Bucket configured for web hosting"
    fi
    
    if gsutil iam ch allUsers:objectViewer "gs://${BUCKET_NAME}"; then
        log_success "Public access granted for dashboard"
    fi
    
    rm -rf "$dashboard_dir"
}

validate_deployment() {
    log_info "Validating deployment..."
    
    # Get Cloud Run service URL
    local service_url
    service_url=$(gcloud run services describe "${CLOUD_RUN_SERVICE}" \
        --region="${REGION}" \
        --format="value(status.url)")
    
    if [[ -z "$service_url" ]]; then
        log_error "Failed to get Cloud Run service URL"
        return 1
    fi
    
    # Test health endpoint
    log_info "Testing health endpoint..."
    if curl -s "${service_url}/health" | grep -q "healthy"; then
        log_success "Health check passed"
    else
        log_warn "Health check failed"
    fi
    
    # Test search endpoint with a simple query
    log_info "Testing search functionality..."
    local search_response
    search_response=$(curl -s -X POST "${service_url}/search" \
        -H "Content-Type: application/json" \
        -d '{"query": "How do I reset my password?"}')
    
    if echo "$search_response" | grep -q "results"; then
        log_success "Search functionality working"
    else
        log_warn "Search test may have failed, check logs"
    fi
    
    log_success "Deployment validation completed"
}

print_deployment_summary() {
    log_info "Deployment Summary"
    log_info "=================="
    
    local service_url
    service_url=$(gcloud run services describe "${CLOUD_RUN_SERVICE}" \
        --region="${REGION}" \
        --format="value(status.url)" 2>/dev/null || echo "Not available")
    
    echo ""
    echo "🎉 Customer Service Automation System Deployed Successfully!"
    echo ""
    echo "Resources Created:"
    echo "  📦 Storage Bucket: gs://${BUCKET_NAME}"
    echo "  🔍 Vertex AI Search Engine: ${SEARCH_ENGINE_ID}"
    echo "  🚀 Cloud Run Service: ${CLOUD_RUN_SERVICE}"
    echo "  🌐 Service URL: ${service_url}"
    echo "  📊 Dashboard URL: https://storage.googleapis.com/${BUCKET_NAME}/dashboard/index.html"
    echo ""
    echo "API Endpoints:"
    echo "  Health Check: ${service_url}/health"
    echo "  Search: ${service_url}/search"
    echo "  Conversation Analysis: ${service_url}/analyze-conversation"
    echo ""
    echo "Next Steps:"
    echo "  1. Test the API endpoints using the dashboard or curl commands"
    echo "  2. Upload additional knowledge base documents to gs://${BUCKET_NAME}/knowledge-base/"
    echo "  3. Configure Contact Center AI for advanced conversation analytics"
    echo "  4. Integrate with your existing customer service tools"
    echo ""
    echo "For cleanup, run: ${SCRIPT_DIR}/destroy.sh"
    echo ""
    
    # Save deployment info to file
    cat > "${SCRIPT_DIR}/deployment-info.txt" <<EOF
Customer Service Automation - Deployment Information
Generated: $(date)

Environment Variables:
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
BUCKET_NAME=${BUCKET_NAME}
SEARCH_ENGINE_ID=${SEARCH_ENGINE_ID}
CLOUD_RUN_SERVICE=${CLOUD_RUN_SERVICE}

Service URL: ${service_url}
Dashboard URL: https://storage.googleapis.com/${BUCKET_NAME}/dashboard/index.html

Resources:
- Storage Bucket: gs://${BUCKET_NAME}
- Vertex AI Search Engine: ${SEARCH_ENGINE_ID}
- Cloud Run Service: ${CLOUD_RUN_SERVICE}
EOF
    
    log_success "Deployment information saved to: ${SCRIPT_DIR}/deployment-info.txt"
}

# Main deployment function
main() {
    log_info "Starting Customer Service Automation deployment..."
    log_info "Script: $0"
    log_info "Working directory: $(pwd)"
    log_info "Log file: ${LOG_FILE}"
    
    # Check if dry run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        export DRY_RUN=true
    fi
    
    # Initialize log file
    echo "Customer Service Automation Deployment Log" > "${LOG_FILE}"
    echo "Started: $(date)" >> "${LOG_FILE}"
    echo "=========================================" >> "${LOG_FILE}"
    
    # Execute deployment steps
    check_prerequisites
    check_billing
    set_environment_variables
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        enable_apis
        create_storage_bucket
        upload_knowledge_base_documents
        create_vertex_ai_search_engine
        create_search_application
        deploy_cloud_run_service
        setup_iam_permissions
        create_agent_dashboard
        validate_deployment
        print_deployment_summary
    else
        log_info "Dry run completed - no resources were created"
    fi
    
    log_success "Deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"