# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  # Resource naming
  resource_suffix         = random_id.suffix.hex
  bucket_name            = "${var.resource_prefix}-kb-${local.resource_suffix}"
  search_engine_id       = "${var.resource_prefix}-search-${local.resource_suffix}"
  cloud_run_service_name = "${var.resource_prefix}-api-${local.resource_suffix}"
  
  # Common labels
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
  })
  
  # API endpoints
  discovery_engine_api = "https://discoveryengine.googleapis.com/v1"
  data_store_parent    = "projects/${var.project_id}/locations/global/collections/default_collection"
  
  # Knowledge base documents path
  kb_documents_path = "knowledge-base"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_required_apis ? toset(var.apis_to_enable) : []
  
  project = var.project_id
  service = each.key
  
  # Don't disable on destroy to avoid breaking dependencies
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Cloud Storage bucket for knowledge base documents
resource "google_storage_bucket" "knowledge_base" {
  name          = local.bucket_name
  location      = var.bucket_location
  storage_class = var.storage_class
  
  # Enable versioning for document protection
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.lifecycle_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Prevent accidental deletion in production
  lifecycle {
    prevent_destroy = false # Set to true in production
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create sample knowledge base documents if enabled
resource "google_storage_bucket_object" "knowledge_base_documents" {
  for_each = var.upload_sample_documents ? {
    for doc in var.knowledge_base_documents : doc.name => doc
  } : {}
  
  name         = "${local.kb_documents_path}/${each.value.name}"
  bucket       = google_storage_bucket.knowledge_base.name
  content      = each.value.content
  content_type = "text/plain"
  
  # Add metadata for better document management
  metadata = {
    uploaded_by = "terraform"
    purpose     = "customer-service-knowledge-base"
  }
}

# Create Vertex AI Search data store
resource "google_discovery_engine_data_store" "knowledge_base" {
  location         = "global"
  data_store_id    = local.search_engine_id
  display_name     = "Customer Service Knowledge Base"
  industry_vertical = var.industry_vertical
  solution_types    = ["SOLUTION_TYPE_SEARCH"]
  content_config    = "CONTENT_REQUIRED"
  
  # Configure document processing for text files
  document_processing_config {
    default_parsing_config {
      digital_parsing_config {}
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket.knowledge_base
  ]
}

# Wait for data store to be ready before importing documents
resource "time_sleep" "wait_for_data_store" {
  depends_on = [google_discovery_engine_data_store.knowledge_base]
  
  create_duration = "30s"
}

# Import documents from Cloud Storage to Vertex AI Search
resource "null_resource" "import_documents" {
  count = var.upload_sample_documents ? 1 : 0
  
  # Trigger re-import when documents change
  triggers = {
    documents_hash = md5(jsonencode(var.knowledge_base_documents))
    data_store_id  = google_discovery_engine_data_store.knowledge_base.data_store_id
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      gcloud auth application-default print-access-token > /tmp/token
      curl -X POST \
        -H "Authorization: Bearer $(cat /tmp/token)" \
        -H "Content-Type: application/json" \
        -d '{
          "gcsSource": {
            "inputUris": ["gs://${google_storage_bucket.knowledge_base.name}/${local.kb_documents_path}/*"],
            "dataSchema": "content"
          },
          "idField": "id",
          "errorConfig": {
            "gcsPrefix": "gs://${google_storage_bucket.knowledge_base.name}/import-errors/"
          }
        }' \
        "${local.discovery_engine_api}/${local.data_store_parent}/dataStores/${local.search_engine_id}/branches/0/documents:import"
      rm -f /tmp/token
    EOT
  }
  
  depends_on = [
    time_sleep.wait_for_data_store,
    google_storage_bucket_object.knowledge_base_documents
  ]
}

# Create Vertex AI Search application (engine)
resource "google_discovery_engine_search_engine" "customer_service_app" {
  engine_id    = "${local.search_engine_id}-app"
  location     = "global"
  collection_id = "default_collection"
  display_name = "Customer Service Search App"
  
  data_store_ids = [google_discovery_engine_data_store.knowledge_base.data_store_id]
  
  search_engine_config {
    search_tier    = var.search_tier
    search_add_ons = ["SEARCH_ADD_ON_LLM"]
  }
  
  depends_on = [
    google_discovery_engine_data_store.knowledge_base,
    time_sleep.wait_for_data_store
  ]
}

# Create service account for Cloud Run
resource "google_service_account" "cloud_run_sa" {
  account_id   = "${var.resource_prefix}-run-sa-${local.resource_suffix}"
  display_name = "Customer Service API Cloud Run Service Account"
  description  = "Service account for Customer Service Automation Cloud Run service"
}

# Grant necessary permissions to the service account
resource "google_project_iam_member" "cloud_run_permissions" {
  for_each = toset([
    "roles/discoveryengine.editor",
    "roles/storage.objectViewer",
    "roles/contactcenteraiplatform.viewer",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Create the application source code as a local file
resource "local_file" "cloud_run_app" {
  filename = "${path.module}/app/main.py"
  content = templatefile("${path.module}/templates/main.py.tpl", {
    project_id        = var.project_id
    search_engine_id  = local.search_engine_id
  })
}

resource "local_file" "cloud_run_requirements" {
  filename = "${path.module}/app/requirements.txt"
  content  = file("${path.module}/templates/requirements.txt")
}

resource "local_file" "cloud_run_dockerfile" {
  filename = "${path.module}/app/Dockerfile"
  content  = file("${path.module}/templates/Dockerfile")
}

# Build and deploy Cloud Run service
resource "null_resource" "build_and_deploy_cloud_run" {
  # Trigger rebuild when source code changes
  triggers = {
    source_hash = md5(join("", [
      local_file.cloud_run_app.content,
      local_file.cloud_run_requirements.content,
      local_file.cloud_run_dockerfile.content
    ]))
    search_engine = google_discovery_engine_search_engine.customer_service_app.name
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.module}
      
      # Create application files if they don't exist
      mkdir -p app/templates
      
      # Create main.py
      cat > app/main.py << 'EOF'
import os
import json
from flask import Flask, request, jsonify
from google.cloud import discoveryengine
from google.oauth2 import service_account
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Initialize Vertex AI Search client
PROJECT_ID = os.environ.get('PROJECT_ID', '${var.project_id}')
SEARCH_ENGINE_ID = os.environ.get('SEARCH_ENGINE_ID', '${local.search_engine_id}')
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
                'snippet': result.document.derived_struct_data.get('snippets', [''])[0].get('snippet', '') if result.document.derived_struct_data.get('snippets') else '',
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
                'snippet': result.document.derived_struct_data.get('snippets', [''])[0].get('snippet', '') if result.document.derived_struct_data.get('snippets') else ''
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
      cat > app/requirements.txt << 'EOF'
Flask==2.3.3
google-cloud-discoveryengine==0.11.11
google-auth==2.23.3
gunicorn==21.2.0
EOF

      # Create Dockerfile
      cat > app/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 main:app
EOF

      # Deploy to Cloud Run
      gcloud run deploy ${local.cloud_run_service_name} \
        --source ./app \
        --platform managed \
        --region ${var.region} \
        --allow-unauthenticated \
        --service-account ${google_service_account.cloud_run_sa.email} \
        --set-env-vars PROJECT_ID=${var.project_id},SEARCH_ENGINE_ID=${local.search_engine_id} \
        --memory ${var.cloud_run_memory} \
        --cpu ${var.cloud_run_cpu} \
        --max-instances ${var.cloud_run_max_instances} \
        --min-instances ${var.cloud_run_min_instances} \
        --timeout ${var.cloud_run_timeout} \
        --port 8080 \
        --project ${var.project_id}
    EOT
  }
  
  depends_on = [
    google_discovery_engine_search_engine.customer_service_app,
    google_service_account.cloud_run_sa,
    google_project_iam_member.cloud_run_permissions,
    null_resource.import_documents
  ]
}

# Get Cloud Run service details after deployment
data "google_cloud_run_service" "customer_service_api" {
  name     = local.cloud_run_service_name
  location = var.region
  
  depends_on = [null_resource.build_and_deploy_cloud_run]
}

# Configure Contact Center AI insights (if enabled)
resource "google_project_iam_member" "contact_center_ai_permissions" {
  for_each = var.enable_contact_center_ai ? toset([
    "roles/contactcenteraiplatform.admin",
    "roles/discoveryengine.admin"
  ]) : []
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${var.project_id}@appspot.gserviceaccount.com"
}

# Create agent dashboard as a static website in Cloud Storage
resource "google_storage_bucket" "dashboard" {
  name          = "${local.bucket_name}-dashboard"
  location      = var.bucket_location
  storage_class = "STANDARD"
  
  # Configure for static website hosting
  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Make dashboard bucket publicly readable
resource "google_storage_bucket_iam_member" "dashboard_public_read" {
  bucket = google_storage_bucket.dashboard.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Create dashboard HTML file
resource "google_storage_bucket_object" "dashboard_html" {
  name   = "index.html"
  bucket = google_storage_bucket.dashboard.name
  content = templatefile("${path.module}/templates/dashboard.html.tpl", {
    api_url = data.google_cloud_run_service.customer_service_api.status[0].url
  })
  content_type = "text/html"
  
  depends_on = [data.google_cloud_run_service.customer_service_api]
}

# Create templates directory and files for the dashboard
resource "local_file" "dashboard_template" {
  filename = "${path.module}/templates/dashboard.html.tpl"
  content = <<-EOF
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
        .error { color: #d93025; background: #fce8e6; padding: 10px; border-radius: 4px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Customer Service AI Assistant</h1>
            <p>Intelligent search and conversation analysis for customer support</p>
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
        const API_BASE_URL = '${api_url}';
        
        async function searchKnowledgeBase() {
            const query = document.getElementById('searchQuery').value;
            if (!query) {
                alert('Please enter a search query');
                return;
            }
            
            const resultsContainer = document.getElementById('searchResults');
            resultsContainer.innerHTML = '<div class="loading">Searching knowledge base...</div>';
            
            try {
                const response = await fetch(`$${API_BASE_URL}/search`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ query })
                });
                
                if (!response.ok) {
                    throw new Error(`HTTP error! status: $${response.status}`);
                }
                
                const data = await response.json();
                displaySearchResults(data);
            } catch (error) {
                console.error('Search failed:', error);
                resultsContainer.innerHTML = `<div class="error">Search failed: $${error.message}</div>`;
            }
        }
        
        function displaySearchResults(data) {
            const container = document.getElementById('searchResults');
            let html = '';
            
            if (data.summary) {
                html += `<div class="result-item"><strong>AI Summary:</strong><br>$${data.summary}</div>`;
            }
            
            if (data.results && data.results.length > 0) {
                data.results.forEach(result => {
                    html += `
                        <div class="result-item">
                            <strong>$${result.title}</strong><br>
                            $${result.snippet}<br>
                            <small>Relevance: $${(result.relevance_score * 100).toFixed(1)}%</small>
                        </div>
                    `;
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
            
            const resultsContainer = document.getElementById('analysisResults');
            resultsContainer.innerHTML = '<div class="loading">Analyzing conversation...</div>';
            
            try {
                const response = await fetch(`$${API_BASE_URL}/analyze-conversation`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ conversation })
                });
                
                if (!response.ok) {
                    throw new Error(`HTTP error! status: $${response.status}`);
                }
                
                const data = await response.json();
                displayAnalysisResults(data);
            } catch (error) {
                console.error('Analysis failed:', error);
                resultsContainer.innerHTML = `<div class="error">Analysis failed: $${error.message}</div>`;
            }
        }
        
        function displayAnalysisResults(data) {
            const container = document.getElementById('analysisResults');
            let html = `
                <div class="result-item">
                    <strong>Detected Intent:</strong> $${data.detected_intent}<br>
                    <strong>Confidence:</strong> $${(data.confidence * 100).toFixed(1)}%
                </div>
            `;
            
            if (data.relevant_documents && data.relevant_documents.length > 0) {
                data.relevant_documents.forEach(doc => {
                    html += `
                        <div class="result-item">
                            <strong>$${doc.title}</strong><br>
                            $${doc.snippet}
                        </div>
                    `;
                });
            }
            
            container.innerHTML = html;
        }
    </script>
</body>
</html>
EOF
}

# Enable audit logging for security monitoring
resource "google_logging_project_sink" "audit_logs" {
  count = var.enable_audit_logs ? 1 : 0
  
  name        = "${var.resource_prefix}-audit-logs-${local.resource_suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.knowledge_base.name}"
  filter      = "protoPayload.serviceName=~\"(discoveryengine|run|contactcenteraiplatform)\""
  
  unique_writer_identity = true
}

# Grant Cloud Storage write permissions for audit logs
resource "google_storage_bucket_iam_member" "audit_logs_writer" {
  count = var.enable_audit_logs ? 1 : 0
  
  bucket = google_storage_bucket.knowledge_base.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.audit_logs[0].writer_identity
}