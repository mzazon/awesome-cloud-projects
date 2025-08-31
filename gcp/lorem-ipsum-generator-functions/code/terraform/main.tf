# Main Terraform configuration for Lorem Ipsum Generator Cloud Functions
# This configuration deploys a serverless lorem ipsum API with Cloud Storage caching

# Generate a random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  # Resource naming with consistent suffixes
  function_name_full = var.bucket_name_suffix != "" ? "${var.function_name}-${var.bucket_name_suffix}" : "${var.function_name}-${random_id.suffix.hex}"
  bucket_name = var.bucket_name_suffix != "" ? "lorem-cache-${var.bucket_name_suffix}" : "lorem-cache-${random_id.suffix.hex}"
  
  # Common labels applied to all resources
  common_labels = merge({
    environment = var.environment
    project     = "lorem-ipsum-generator"
    managed-by  = "terraform"
    recipe-id   = "f7e9c5a2"
  }, var.labels)
  
  # Function source code configuration
  function_source_dir = "${path.module}/../function-source"
  zip_file_path      = "${path.module}/function-source.zip"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying Terraform resources
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Cloud Storage bucket for caching lorem ipsum text
resource "google_storage_bucket" "cache_bucket" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id
  
  # Storage configuration
  storage_class               = var.storage_class
  force_destroy              = true
  uniform_bucket_level_access = true
  
  # Enable versioning for data protection
  dynamic "versioning" {
    for_each = var.enable_versioning ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30 # Delete cached files older than 30 days
    }
    action {
      type = "Delete"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }
  
  # CORS configuration for web browser access
  dynamic "cors" {
    for_each = var.enable_cors ? [1] : []
    content {
      origin          = var.cors_origins
      method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
      response_header = ["*"]
      max_age_seconds = 3600
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create the function source code as a zip archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = local.zip_file_path
  
  # Create source from template with bucket name injection
  source {
    content = templatefile("${path.module}/function_template.py", {
      bucket_name = google_storage_bucket.cache_bucket.name
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.cache_bucket.name
  source = data.archive_file.function_source.output_path
  
  # Ensure new versions are uploaded when source changes
  content_type = "application/zip"
  
  depends_on = [google_storage_bucket.cache_bucket]
}

# Service account for the Cloud Function with minimal required permissions
resource "google_service_account" "function_sa" {
  account_id   = substr("lorem-gen-${random_id.suffix.hex}", 0, 30)
  display_name = "Lorem Generator Function Service Account"
  description  = "Service account for the Lorem Ipsum Generator Cloud Function"
  project      = var.project_id
}

# Grant Cloud Storage object admin permissions for caching
resource "google_storage_bucket_iam_member" "function_storage_access" {
  bucket = google_storage_bucket.cache_bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant logging permissions for function monitoring
resource "google_project_iam_member" "function_logs_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Deploy the Cloud Function (2nd generation)
resource "google_cloudfunctions2_function" "lorem_generator" {
  name        = local.function_name_full
  location    = var.region
  project     = var.project_id
  description = "Serverless lorem ipsum text generator with Cloud Storage caching"
  
  # Build configuration
  build_config {
    runtime     = "python312"
    entry_point = "lorem_generator"
    
    # Source code configuration
    source {
      storage_source {
        bucket = google_storage_bucket.cache_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
    
    # Build environment variables
    environment_variables = {
      GOOGLE_BUILDABLE = "main.py"
    }
    
    # Use custom service account for build process
    service_account = google_service_account.function_sa.id
  }
  
  # Service configuration
  service_config {
    max_instance_count = var.max_instance_count
    min_instance_count = 0
    available_memory   = var.function_memory
    timeout_seconds    = var.function_timeout
    
    # Enable concurrent request handling for better performance
    max_instance_request_concurrency = 10
    
    # Environment variables available to the function
    environment_variables = {
      CACHE_BUCKET_NAME = google_storage_bucket.cache_bucket.name
      FUNCTION_REGION   = var.region
      PROJECT_ID        = var.project_id
      ENVIRONMENT       = var.environment
    }
    
    # Security configuration
    ingress_settings                 = "ALLOW_ALL"
    all_traffic_on_latest_revision  = true
    service_account_email           = google_service_account.function_sa.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_iam_member.function_storage_access,
    google_project_iam_member.function_logs_writer,
    google_storage_bucket_object.function_source
  ]
}

# Allow unauthenticated access to the function for public API usage
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = var.project_id
  location       = google_cloudfunctions2_function.lorem_generator.location
  cloud_function = google_cloudfunctions2_function.lorem_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Allow unauthenticated access to the underlying Cloud Run service
resource "google_cloud_run_service_iam_member" "public_access" {
  project  = var.project_id
  location = google_cloudfunctions2_function.lorem_generator.location
  service  = google_cloudfunctions2_function.lorem_generator.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Create the Python requirements file for the function
resource "local_file" "requirements_txt" {
  content = <<EOF
functions-framework==3.8.*
google-cloud-storage==2.17.*
EOF
  filename = "${path.module}/requirements.txt"
}

# Create the function source code template
resource "local_file" "function_template" {
  content = <<EOF
import json
import random
import hashlib
from google.cloud import storage
import functions_framework

# Lorem ipsum word bank for text generation
LOREM_WORDS = [
    "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit",
    "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore",
    "magna", "aliqua", "enim", "ad", "minim", "veniam", "quis", "nostrud",
    "exercitation", "ullamco", "laboris", "nisi", "aliquip", "ex", "ea", "commodo",
    "consequat", "duis", "aute", "irure", "in", "reprehenderit", "voluptate",
    "velit", "esse", "cillum", "fugiat", "nulla", "pariatur", "excepteur", "sint",
    "occaecat", "cupidatat", "non", "proident", "sunt", "culpa", "qui", "officia",
    "deserunt", "mollit", "anim", "id", "est", "laborum"
]

def get_cached_text(cache_key, bucket_name):
    """Retrieve cached lorem ipsum text from Cloud Storage"""
    try:
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(f"cache/{cache_key}.txt")
        
        if blob.exists():
            return blob.download_as_text()
    except Exception as e:
        print(f"Cache retrieval error: {e}")
    return None

def cache_text(cache_key, text, bucket_name):
    """Store generated lorem ipsum text in Cloud Storage cache"""
    try:
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        blob = bucket.blob(f"cache/{cache_key}.txt")
        blob.upload_from_string(text)
    except Exception as e:
        print(f"Cache storage error: {e}")

def generate_lorem_text(paragraphs=3, words_per_paragraph=50):
    """Generate lorem ipsum text with specified parameters"""
    result_paragraphs = []
    
    for _ in range(paragraphs):
        # Generate words for this paragraph
        paragraph_words = []
        for i in range(words_per_paragraph):
            word = random.choice(LOREM_WORDS)
            # Capitalize first word of paragraph
            if i == 0:
                word = word.capitalize()
            paragraph_words.append(word)
        
        # Join words and add period at end
        paragraph = " ".join(paragraph_words) + "."
        result_paragraphs.append(paragraph)
    
    return "\\n\\n".join(result_paragraphs)

@functions_framework.http
def lorem_generator(request):
    """HTTP Cloud Function entry point for lorem ipsum generation"""
    # Set CORS headers for web browser access
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Content-Type': 'application/json'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Parse query parameters with defaults
        paragraphs = int(request.args.get('paragraphs', 3))
        words_per_paragraph = int(request.args.get('words', 50))
        
        # Validate parameters
        paragraphs = max(1, min(paragraphs, 10))  # Limit 1-10 paragraphs
        words_per_paragraph = max(10, min(words_per_paragraph, 200))  # Limit 10-200 words
        
        # Generate cache key from parameters
        cache_key = hashlib.md5(f"{paragraphs}-{words_per_paragraph}".encode()).hexdigest()
        bucket_name = "${bucket_name}"
        
        # Try to get cached text first
        cached_text = get_cached_text(cache_key, bucket_name)
        if cached_text:
            response_data = {
                "text": cached_text,
                "paragraphs": paragraphs,
                "words_per_paragraph": words_per_paragraph,
                "cached": True
            }
        else:
            # Generate new text
            lorem_text = generate_lorem_text(paragraphs, words_per_paragraph)
            
            # Cache the generated text
            cache_text(cache_key, lorem_text, bucket_name)
            
            response_data = {
                "text": lorem_text,
                "paragraphs": paragraphs,
                "words_per_paragraph": words_per_paragraph,
                "cached": False
            }
        
        return (json.dumps(response_data), 200, headers)
    
    except Exception as e:
        error_response = {
            "error": "Failed to generate lorem ipsum text",
            "message": str(e)
        }
        return (json.dumps(error_response), 500, headers)
EOF
  filename = "${path.module}/function_template.py"
}