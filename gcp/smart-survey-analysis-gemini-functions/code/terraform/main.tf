# Smart Survey Analysis Infrastructure with Gemini and Cloud Functions
# This Terraform configuration deploys a complete survey analysis system using:
# - Cloud Functions for serverless processing
# - Vertex AI Gemini for AI-powered analysis
# - Firestore for data storage
# - Cloud Build for function deployment

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Construct resource names with environment and random suffix
  function_name    = "${var.function_name}-${var.environment}-${random_id.suffix.hex}"
  database_name    = "${var.firestore_database_name}-${var.environment}"
  bucket_name      = "${var.project_id}-survey-function-source-${random_id.suffix.hex}"
  service_account_name = "survey-analyzer-sa-${random_id.suffix.hex}"
  
  # Merge default labels with user-provided labels
  common_labels = merge(var.labels, {
    environment = var.environment
    component   = "survey-analysis"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "aiplatform.googleapis.com",
    "firestore.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  service = each.value
  project = var.project_id
  
  # Don't disable APIs when destroying to avoid dependency issues
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service account for Cloud Function with least privilege permissions
resource "google_service_account" "function_service_account" {
  account_id   = local.service_account_name
  display_name = "Survey Analyzer Function Service Account"
  description  = "Service account for survey analysis Cloud Function with Vertex AI and Firestore access"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant Vertex AI User role for Gemini API access
resource "google_project_iam_member" "vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
  
  depends_on = [google_service_account.function_service_account]
}

# Grant Firestore User role for database operations
resource "google_project_iam_member" "firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
  
  depends_on = [google_service_account.function_service_account]
}

# Grant Cloud Functions Developer role for function management
resource "google_project_iam_member" "functions_developer" {
  project = var.project_id
  role    = "roles/cloudfunctions.developer"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
  
  depends_on = [google_service_account.function_service_account]
}

# Grant Logging Writer role for Cloud Logging
resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
  
  depends_on = [google_service_account.function_service_account]
}

# Grant Monitoring Metric Writer role for Cloud Monitoring
resource "google_project_iam_member" "monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_service_account.email}"
  
  depends_on = [google_service_account.function_service_account]
}

# Create Firestore database for storing survey responses and analysis results
resource "google_firestore_database" "survey_database" {
  provider    = google-beta
  project     = var.project_id
  name        = local.database_name
  location_id = var.firestore_location
  type        = "FIRESTORE_NATIVE"
  
  # Enable point-in-time recovery for data protection
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  
  # Enable delete protection for production environments
  delete_protection_state = var.environment == "prod" ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  
  depends_on = [google_project_service.required_apis]
  
  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

# Create Firestore index for efficient querying of survey analyses
resource "google_firestore_index" "survey_analyses_index" {
  provider   = google-beta
  project    = var.project_id
  database   = google_firestore_database.survey_database.name
  collection = "survey_analyses"
  
  fields {
    field_path = "survey_id"
    order      = "ASCENDING"
  }
  
  fields {
    field_path = "timestamp"
    order      = "DESCENDING"
  }
  
  depends_on = [google_firestore_database.survey_database]
}

# Create Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id
  
  # Enable versioning for source code management
  versioning {
    enabled = true
  }
  
  # Lifecycle management to clean up old versions
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  # Security settings
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create the Cloud Function source code as a local file
resource "local_file" "function_main" {
  filename = "${path.module}/function_source/main.py"
  content = <<-EOF
import json
import logging
import os
from typing import Dict, Any
import vertexai
from vertexai.generative_models import GenerativeModel
from google.cloud import firestore
import functions_framework
from flask import Request

# Initialize clients with project ID from environment
project_id = os.environ.get('GCP_PROJECT', os.environ.get('GOOGLE_CLOUD_PROJECT'))
vertexai.init(project=project_id)
model = GenerativeModel("${var.gemini_model}")
db = firestore.Client(database="${local.database_name}")

@functions_framework.http
def analyze_survey(request: Request) -> str:
    """Analyze survey responses using Gemini AI."""
    try:
        # Enable CORS for web requests
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)
        
        request_json = request.get_json()
        if not request_json or 'responses' not in request_json:
            return json.dumps({'error': 'Missing survey responses'}), 400
        
        survey_data = request_json['responses']
        survey_id = request_json.get('survey_id', 'default')
        
        # Create structured analysis prompt
        prompt = f"""
        Analyze the following survey responses and provide a comprehensive analysis in JSON format.
        
        Required JSON structure:
        {{
          "sentiment_score": <number 1-10>,
          "overall_sentiment": "<positive/neutral/negative>",
          "key_themes": ["theme1", "theme2", "theme3"],
          "insights": ["insight1", "insight2", "insight3"],
          "recommendations": [
            {{"action": "action1", "priority": "high/medium/low", "impact": "impact description"}},
            {{"action": "action2", "priority": "high/medium/low", "impact": "impact description"}},
            {{"action": "action3", "priority": "high/medium/low", "impact": "impact description"}}
          ],
          "urgency_level": "<high/medium/low>",
          "confidence_score": <number 0.0-1.0>
        }}
        
        Survey Responses:
        {json.dumps(survey_data, indent=2)}
        
        Provide only the JSON response, no additional text.
        """
        
        # Generate analysis with Gemini
        response = model.generate_content(prompt)
        analysis_text = response.text.strip()
        
        # Clean and parse AI response
        if analysis_text.startswith('```json'):
            analysis_text = analysis_text[7:]
        if analysis_text.endswith('```'):
            analysis_text = analysis_text[:-3]
        
        try:
            analysis_data = json.loads(analysis_text)
        except json.JSONDecodeError as e:
            logging.warning(f"JSON parse error: {e}, using fallback structure")
            analysis_data = {
                'raw_analysis': analysis_text,
                'sentiment_score': 5,
                'overall_sentiment': 'neutral',
                'error': 'Failed to parse structured response'
            }
        
        # Store in Firestore with enhanced metadata
        doc_ref = db.collection('survey_analyses').document()
        doc_data = {
            'survey_id': survey_id,
            'original_responses': survey_data,
            'analysis': analysis_data,
            'timestamp': firestore.SERVER_TIMESTAMP,
            'model_version': '${var.gemini_model}',
            'processing_status': 'completed'
        }
        doc_ref.set(doc_data)
        
        headers = {'Access-Control-Allow-Origin': '*'}
        return json.dumps({
            'status': 'success',
            'document_id': doc_ref.id,
            'analysis': analysis_data
        }), 200, headers
        
    except Exception as e:
        logging.error(f"Analysis error: {str(e)}")
        headers = {'Access-Control-Allow-Origin': '*'}
        return json.dumps({'error': str(e)}), 500, headers
EOF
  
  depends_on = [google_firestore_database.survey_database]
}

# Create requirements.txt for Cloud Function dependencies
resource "local_file" "function_requirements" {
  filename = "${path.module}/function_source/requirements.txt"
  content = <<-EOF
functions-framework==3.8.1
google-cloud-aiplatform==1.67.1
google-cloud-firestore==2.18.0
vertexai==1.67.1
flask==3.0.3
EOF
}

# Create ZIP archive of function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function_source.zip"
  source_dir  = "${path.module}/function_source"
  
  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "survey-analyzer-${random_id.suffix.hex}-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [
    google_storage_bucket.function_source,
    data.archive_file.function_source
  ]
}

# Deploy Cloud Function for survey analysis
resource "google_cloudfunctions2_function" "survey_analyzer" {
  provider    = google-beta
  name        = local.function_name
  location    = var.region
  description = "AI-powered survey analysis using Vertex AI Gemini"
  project     = var.project_id
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "analyze_survey"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.max_instances
    min_instance_count    = var.min_instances
    available_memory      = "${var.function_memory}Mi"
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.function_service_account.email
    
    ingress_settings = var.ingress_settings
    
    # Environment variables for function configuration
    environment_variables = {
      GCP_PROJECT     = var.project_id
      GEMINI_MODEL    = var.gemini_model
      FIRESTORE_DB    = local.database_name
      ENVIRONMENT     = var.environment
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_service_account.function_service_account,
    google_project_iam_member.vertex_ai_user,
    google_project_iam_member.firestore_user
  ]
  
  timeouts {
    create = "15m"
    update = "15m"
    delete = "10m"
  }
}

# Configure IAM for public access to Cloud Function (if enabled)
resource "google_cloudfunctions2_function_iam_member" "public_access" {
  count = var.enable_public_access ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.survey_analyzer.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
  
  depends_on = [google_cloudfunctions2_function.survey_analyzer]
}

# Create Cloud Monitoring alert policy for function errors (if monitoring enabled)
resource "google_monitoring_alert_policy" "function_error_rate" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Survey Analyzer Function Error Rate"
  project      = var.project_id
  
  combiner     = "OR"
  
  conditions {
    display_name = "Function error rate high"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 0.05  # 5% error rate threshold
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"  # Auto-close after 30 minutes
  }
  
  depends_on = [
    google_cloudfunctions2_function.survey_analyzer,
    google_project_service.required_apis
  ]
}

# Create Cloud Monitoring alert policy for function latency (if monitoring enabled)
resource "google_monitoring_alert_policy" "function_latency" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Survey Analyzer Function High Latency"
  project      = var.project_id
  
  combiner     = "OR"
  
  conditions {
    display_name = "Function latency high"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 30000  # 30 seconds threshold
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"  # Auto-close after 30 minutes
  }
  
  depends_on = [
    google_cloudfunctions2_function.survey_analyzer,
    google_project_service.required_apis
  ]
}