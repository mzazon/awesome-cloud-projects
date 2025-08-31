# Main Terraform configuration for Word Count API with Cloud Functions
# This file creates all the necessary GCP resources for a serverless text analysis API
# including Cloud Storage bucket, Cloud Function, and required IAM permissions

# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Enable required Google Cloud APIs for the project
# These APIs must be enabled before creating the dependent resources
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com", # Cloud Functions API for serverless compute
    "storage.googleapis.com",        # Cloud Storage API for file storage
    "cloudbuild.googleapis.com",     # Cloud Build API for function deployment
    "run.googleapis.com",            # Cloud Run API (required for Gen2 functions)
    "artifactregistry.googleapis.com" # Artifact Registry for storing function images
  ])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false

  # Prevent accidental deletion of critical APIs
  lifecycle {
    prevent_destroy = true
  }
}

# Create Cloud Storage bucket for file processing and function source code
# The bucket uses uniform bucket-level access for simplified IAM management
resource "google_storage_bucket" "word_count_files" {
  name                        = "${var.bucket_prefix}-${random_id.suffix.hex}"
  location                    = var.region
  force_destroy              = true
  uniform_bucket_level_access = true
  storage_class              = var.storage_class

  # Configure public access prevention for security
  public_access_prevention = "enforced"

  # Enable versioning for file recovery capabilities
  versioning {
    enabled = true
  }

  # Configure lifecycle management to optimize costs
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Apply labels for resource organization
  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

# Create function source code archive from local files
# This creates a ZIP file containing the Python function code and dependencies
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  source_dir  = "${path.module}/function-source"
}

# Upload function source code to Cloud Storage
# The function source is stored in the same bucket created above
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.word_count_files.name
  source = data.archive_file.function_source.output_path

  # Update function when source code changes
  content_type = "application/zip"
}

# Create the Cloud Function (Gen2) for text analysis
# Gen2 functions provide better performance, scaling, and integration with Cloud Run
resource "google_cloudfunctions2_function" "word_count_api" {
  name     = var.function_name
  location = var.region
  project  = var.project_id

  description = "Serverless API for text analysis including word count, character count, and reading time estimation"

  build_config {
    runtime     = "python312"
    entry_point = "word_count_api"

    source {
      storage_source {
        bucket = google_storage_bucket.word_count_files.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    # Resource allocation and scaling configuration
    available_memory               = var.function_memory
    timeout_seconds               = var.function_timeout
    max_instance_request_concurrency = 1000
    max_instance_count            = var.max_instances
    min_instance_count            = var.min_instances

    # Environment variables for function configuration
    environment_variables = {
      STORAGE_BUCKET = google_storage_bucket.word_count_files.name
      LOG_LEVEL      = "INFO"
    }

    # Security configuration
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true

    # Service account for function execution
    service_account_email = google_service_account.function_sa.email
  }

  # Apply labels for resource organization
  labels = var.labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# Create dedicated service account for the Cloud Function
# This follows security best practices by using a dedicated service account
# with minimal required permissions instead of the default Compute Engine service account
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa"
  display_name = "Service Account for ${var.function_name} Cloud Function"
  description  = "Dedicated service account for word count API function with minimal required permissions"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Grant Cloud Storage Object Viewer permissions to the function service account
# This allows the function to read files from the storage bucket for text analysis
resource "google_storage_bucket_iam_member" "function_storage_access" {
  bucket = google_storage_bucket.word_count_files.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.function_sa.email}"

  depends_on = [google_service_account.function_sa]
}

# Grant Cloud Functions Invoker role for public access (if enabled)
# This allows unauthenticated users to call the function via HTTP
resource "google_cloudfunctions2_function_iam_member" "public_access" {
  count = var.enable_public_access ? 1 : 0

  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.word_count_api.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"

  depends_on = [google_cloudfunctions2_function.word_count_api]
}

# Create function source directory and files locally
# This ensures the function code exists before creating the archive
resource "local_file" "function_main" {
  content = <<-EOT
import json
import re
from google.cloud import storage
from flask import Request
import functions_framework

def analyze_text(text):
    """Analyze text and return comprehensive statistics."""
    if not text or not text.strip():
        return {
            'word_count': 0,
            'character_count': 0,
            'character_count_no_spaces': 0,
            'paragraph_count': 0,
            'estimated_reading_time_minutes': 0
        }
    
    # Word count (split by whitespace, filter empty strings)
    words = [word for word in re.findall(r'\b\w+\b', text.lower())]
    word_count = len(words)
    
    # Character counts
    character_count = len(text)
    character_count_no_spaces = len(text.replace(' ', '').replace('\t', '').replace('\n', ''))
    
    # Paragraph count (split by double newlines or single newlines)
    paragraphs = [p.strip() for p in text.split('\n') if p.strip()]
    paragraph_count = len(paragraphs)
    
    # Estimated reading time (200 words per minute average)
    estimated_reading_time_minutes = max(1, round(word_count / 200)) if word_count > 0 else 0
    
    return {
        'word_count': word_count,
        'character_count': character_count,
        'character_count_no_spaces': character_count_no_spaces,
        'paragraph_count': paragraph_count,
        'estimated_reading_time_minutes': estimated_reading_time_minutes
    }

@functions_framework.http
def word_count_api(request: Request):
    """HTTP Cloud Function for text analysis."""
    # Set CORS headers
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    if request.method == 'GET':
        return ({
            'message': 'Word Count API is running',
            'usage': {
                'POST /': 'Analyze text from request body',
                'POST / with file_path': 'Analyze text from Cloud Storage file'
            }
        }, 200, headers)
    
    if request.method != 'POST':
        return ({'error': 'Method not allowed'}, 405, headers)
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        
        if not request_json:
            return ({'error': 'Invalid JSON in request body'}, 400, headers)
        
        # Check if analyzing text from Cloud Storage file
        if 'file_path' in request_json:
            bucket_name = request_json.get('bucket_name')
            file_path = request_json['file_path']
            
            if not bucket_name:
                return ({'error': 'bucket_name required when using file_path'}, 400, headers)
            
            # Download file from Cloud Storage
            storage_client = storage.Client()
            bucket = storage_client.bucket(bucket_name)
            blob = bucket.blob(file_path)
            
            if not blob.exists():
                return ({'error': f'File not found: {file_path}'}, 404, headers)
            
            text_content = blob.download_as_text()
        
        # Check if analyzing direct text input
        elif 'text' in request_json:
            text_content = request_json['text']
        
        else:
            return ({'error': 'Either "text" or "file_path" required in request body'}, 400, headers)
        
        # Analyze the text
        analysis_result = analyze_text(text_content)
        
        # Add metadata to response
        response_data = {
            'analysis': analysis_result,
            'input_source': 'file' if 'file_path' in request_json else 'direct_text',
            'api_version': '1.0'
        }
        
        return (response_data, 200, headers)
    
    except Exception as e:
        return ({'error': f'Internal server error: {str(e)}'}, 500, headers)
EOT

  filename = "${path.module}/function-source/main.py"
}

# Create requirements.txt file for function dependencies
resource "local_file" "function_requirements" {
  content = <<-EOT
google-cloud-storage==2.17.0
functions-framework==3.8.1
EOT

  filename = "${path.module}/function-source/requirements.txt"
}