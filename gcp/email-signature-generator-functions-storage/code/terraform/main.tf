# Email Signature Generator Infrastructure
# This Terraform configuration deploys a complete serverless email signature generation solution
# using Google Cloud Functions and Cloud Storage

# Random suffix for ensuring globally unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Enable required Google Cloud APIs
# Cloud Functions API for serverless function deployment
resource "google_project_service" "cloudfunctions" {
  project                        = var.project_id
  service                        = "cloudfunctions.googleapis.com"
  disable_on_destroy            = false
  disable_dependent_services    = false
}

# Cloud Storage API for object storage
resource "google_project_service" "storage" {
  project                        = var.project_id
  service                        = "storage.googleapis.com"
  disable_on_destroy            = false
  disable_dependent_services    = false
}

# Cloud Build API for function deployment and container building
resource "google_project_service" "cloudbuild" {
  project                        = var.project_id
  service                        = "cloudbuild.googleapis.com"
  disable_on_destroy            = false
  disable_dependent_services    = false
}

# Cloud Run API for Cloud Functions Gen2 runtime
resource "google_project_service" "run" {
  project                        = var.project_id
  service                        = "run.googleapis.com"
  disable_on_destroy            = false
  disable_dependent_services    = false
}

# Service Account for Cloud Function execution
# This service account follows the principle of least privilege
resource "google_service_account" "function_sa" {
  project      = var.project_id
  account_id   = "signature-generator-sa"
  display_name = "Email Signature Generator Service Account"
  description  = "Service account for Cloud Function with minimal required permissions"

  depends_on = [google_project_service.storage]
}

# IAM role binding: Storage Object Creator for writing signatures to bucket
resource "google_project_iam_member" "function_storage_creator" {
  project = var.project_id
  role    = "roles/storage.objectCreator"
  member  = "serviceAccount:${google_service_account.function_sa.email}"

  depends_on = [google_service_account.function_sa]
}

# IAM role binding: Storage Object Viewer for reading existing objects if needed
resource "google_project_iam_member" "function_storage_viewer" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"

  depends_on = [google_service_account.function_sa]
}

# Cloud Storage bucket for storing generated email signatures
# Configured with public read access for direct URL access
resource "google_storage_bucket" "signature_storage" {
  name                        = "${var.bucket_name_suffix}-${random_id.suffix.hex}"
  location                    = var.bucket_location
  project                     = var.project_id
  storage_class              = var.storage_class
  uniform_bucket_level_access = true
  force_destroy              = true

  labels = var.labels

  # Enable object versioning if requested
  dynamic "versioning" {
    for_each = var.enable_versioning ? [1] : []
    content {
      enabled = true
    }
  }

  # Lifecycle management for automatic cleanup of old signatures
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_delete_age_days > 0 ? [1] : []
    content {
      condition {
        age = var.lifecycle_delete_age_days
      }
      action {
        type = "Delete"
      }
    }
  }

  # CORS configuration for web browser access
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "OPTIONS"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  depends_on = [google_project_service.storage]
}

# IAM policy to allow public read access to signature files
resource "google_storage_bucket_iam_member" "signature_storage_public_viewer" {
  bucket = google_storage_bucket.signature_storage.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"

  depends_on = [google_storage_bucket.signature_storage]
}

# Cloud Storage bucket for storing Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name                        = "function-source-${random_id.suffix.hex}"
  location                    = var.bucket_location
  project                     = var.project_id
  storage_class              = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy              = true

  labels = var.labels

  # Lifecycle rule to clean up old function versions
  lifecycle_rule {
    condition {
      age = 30  # Keep source files for 30 days
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.storage]
}

# Create function source code files locally
resource "local_file" "function_main" {
  filename = "${path.module}/function_source/main.py"
  content = <<-EOT
import json
import os
from datetime import datetime
from google.cloud import storage

def generate_signature(request):
    """HTTP Cloud Function to generate HTML email signatures."""
    
    # Handle CORS preflight requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for actual request
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        request_args = request.args
        
        # Extract signature parameters with defaults
        name = request_json.get('name') if request_json else request_args.get('name', 'John Doe')
        title = request_json.get('title') if request_json else request_args.get('title', 'Software Engineer')
        company = request_json.get('company') if request_json else request_args.get('company', 'Your Company')
        email = request_json.get('email') if request_json else request_args.get('email', 'john@company.com')
        phone = request_json.get('phone') if request_json else request_args.get('phone', '+1 (555) 123-4567')
        website = request_json.get('website') if request_json else request_args.get('website', 'https://company.com')
        
        # Generate professional HTML signature
        html_signature = f'''<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        .signature-container {{
            font-family: Arial, Helvetica, sans-serif;
            font-size: 14px;
            line-height: 1.4;
            color: #333333;
            max-width: 500px;
        }}
        .name {{
            font-size: 18px;
            font-weight: bold;
            color: #2E7EBF;
            margin-bottom: 5px;
        }}
        .title {{
            font-size: 14px;
            color: #666666;
            margin-bottom: 10px;
        }}
        .company {{
            font-size: 16px;
            font-weight: bold;
            color: #333333;
            margin-bottom: 10px;
        }}
        .contact-info {{
            border-top: 2px solid #2E7EBF;
            padding-top: 10px;
        }}
        .contact-item {{
            margin-bottom: 5px;
        }}
        .contact-item a {{
            color: #2E7EBF;
            text-decoration: none;
        }}
        .contact-item a:hover {{
            text-decoration: underline;
        }}
    </style>
</head>
<body>
    <div class="signature-container">
        <div class="name">{name}</div>
        <div class="title">{title}</div>
        <div class="company">{company}</div>
        <div class="contact-info">
            <div class="contact-item">Email: <a href="mailto:{email}">{email}</a></div>
            <div class="contact-item">Phone: <a href="tel:{phone}">{phone}</a></div>
            <div class="contact-item">Website: <a href="{website}">{website}</a></div>
        </div>
    </div>
</body>
</html>'''
        
        # Store signature in Cloud Storage
        bucket_name = os.environ.get('BUCKET_NAME')
        if bucket_name:
            storage_client = storage.Client()
            bucket = storage_client.bucket(bucket_name)
            
            # Create filename from name and timestamp
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            safe_name = name.lower().replace(' ', '_').replace('-', '_')
            filename = f"signatures/{safe_name}_{timestamp}.html"
            
            # Upload HTML signature to bucket
            blob = bucket.blob(filename)
            blob.upload_from_string(html_signature, content_type='text/html')
            
            # Make blob publicly readable
            blob.make_public()
            
            signature_url = f"https://storage.googleapis.com/{bucket_name}/{filename}"
        else:
            signature_url = "Storage not configured"
        
        # Return response with signature and URL
        response_data = {
            'success': True,
            'signature_html': html_signature,
            'storage_url': signature_url,
            'generated_at': datetime.now().isoformat()
        }
        
        return (json.dumps(response_data), 200, headers)
        
    except Exception as e:
        error_response = {
            'success': False,
            'error': str(e),
            'generated_at': datetime.now().isoformat()
        }
        return (json.dumps(error_response), 500, headers)
EOT
}

resource "local_file" "function_requirements" {
  filename = "${path.module}/function_source/requirements.txt"
  content = <<-EOT
google-cloud-storage==2.18.0
EOT
}

# Create ZIP archive of function source code
data "archive_file" "function_source_zip" {
  type        = "zip"
  output_path = "${path.module}/function_source.zip"
  source_dir  = "${path.module}/function_source"
  
  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source_archive" {
  name       = "function-source-${random_id.suffix.hex}.zip"
  bucket     = google_storage_bucket.function_source.name
  source     = data.archive_file.function_source_zip.output_path
  depends_on = [data.archive_file.function_source_zip]
}

# Cloud Function (Generation 2) for signature generation
resource "google_cloudfunctions2_function" "signature_generator" {
  name        = var.function_name
  location    = var.region
  project     = var.project_id
  description = "Serverless API for generating professional HTML email signatures"

  labels = var.labels

  # Build configuration specifying runtime and source location
  build_config {
    runtime     = "python312"
    entry_point = "generate_signature"

    # Source code configuration pointing to Cloud Storage
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source_archive.name
      }
    }

    # Environment variables available during build
    environment_variables = {
      BUILD_CONFIG_ENV = "production"
    }
  }

  # Service configuration for runtime behavior
  service_config {
    max_instance_count               = var.max_instance_count
    min_instance_count               = var.min_instance_count
    available_memory                 = var.function_memory
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 80
    available_cpu                    = "1"

    # Runtime environment variables
    environment_variables = {
      BUCKET_NAME      = google_storage_bucket.signature_storage.name
      PROJECT_ID       = var.project_id
      ENVIRONMENT      = "production"
    }

    # Use custom service account
    service_account_email = google_service_account.function_sa.email

    # Allow all traffic on latest revision
    all_traffic_on_latest_revision = true

    # Ingress settings for security
    ingress_settings = "ALLOW_ALL"
  }

  depends_on = [
    google_project_service.cloudfunctions,
    google_project_service.cloudbuild,
    google_project_service.run,
    google_storage_bucket_object.function_source_archive,
    google_project_iam_member.function_storage_creator,
    google_project_iam_member.function_storage_viewer
  ]
}

# IAM policy to allow public access to the Cloud Function (if enabled)
resource "google_cloudfunctions2_function_iam_member" "public_invoker" {
  count = var.allow_unauthenticated ? 1 : 0

  project        = var.project_id
  location       = google_cloudfunctions2_function.signature_generator.location
  cloud_function = google_cloudfunctions2_function.signature_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"

  depends_on = [google_cloudfunctions2_function.signature_generator]
}

# Cloud Run IAM policy for public access (required for Cloud Functions Gen2)
resource "google_cloud_run_service_iam_member" "public_invoker" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = google_cloudfunctions2_function.signature_generator.location
  service  = google_cloudfunctions2_function.signature_generator.name
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [google_cloudfunctions2_function.signature_generator]
}