# Generate random suffix for globally unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent naming and configuration
locals {
  bucket_name = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    terraform-managed = "true"
    created-by       = "terraform"
    timestamp        = formatdate("YYYY-MM-DD", timestamp())
  })
  
  # Function source code path
  function_source_dir = "${path.module}/function-source"
  
  # Archive file path
  function_archive = "${path.module}/function-source.zip"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com", 
    "storage.googleapis.com",
    "logging.googleapis.com",
    "run.googleapis.com" # Required for 2nd gen Cloud Functions
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Cloud Storage bucket for validation logs
resource "google_storage_bucket" "validation_logs" {
  name                        = local.bucket_name
  location                    = var.region
  storage_class              = var.storage_class
  uniform_bucket_level_access = var.enable_uniform_bucket_access
  force_destroy              = true # Allow destruction even with objects
  
  labels = local.common_labels
  
  # Enable versioning for data protection
  versioning {
    enabled = var.enable_versioning
  }
  
  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.enable_cost_optimization ? [1] : []
    
    content {
      condition {
        age = var.lifecycle_age_nearline
      }
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    }
  }
  
  dynamic "lifecycle_rule" {
    for_each = var.enable_cost_optimization ? [1] : []
    
    content {
      condition {
        age = var.lifecycle_age_delete
      }
      action {
        type = "Delete"
      }
    }
  }
  
  # Enable soft delete policy for accidental deletion protection
  soft_delete_policy {
    retention_duration_seconds = 604800 # 7 days
  }
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name                        = "${local.bucket_name}-source"
  location                    = var.region
  storage_class              = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy              = true
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Create function source code directory and files
resource "local_file" "function_main" {
  filename = "${local.function_source_dir}/main.py"
  content = <<-EOF
import functions_framework
import json
import re
import socket
from datetime import datetime
from google.cloud import storage
import os

# Initialize Cloud Storage client
storage_client = storage.Client()
BUCKET_NAME = os.environ.get('BUCKET_NAME')

def validate_email_format(email):
    """Validate email format using regex pattern"""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return bool(re.match(pattern, email))

def validate_domain(domain):
    """Validate domain exists using DNS lookup"""
    try:
        socket.gethostbyname(domain)
        return True
    except socket.gaierror:
        return False

def log_validation(email, is_valid, validation_details):
    """Store validation results in Cloud Storage"""
    try:
        bucket = storage_client.bucket(BUCKET_NAME)
        timestamp = datetime.utcnow()
        filename = f"validations/{timestamp.strftime('%Y/%m/%d')}/{timestamp.isoformat()}.json"
        
        log_data = {
            'timestamp': timestamp.isoformat(),
            'email': email,
            'is_valid': is_valid,
            'validation_details': validation_details
        }
        
        blob = bucket.blob(filename)
        blob.upload_from_string(json.dumps(log_data))
        return True
    except Exception as e:
        print(f"Logging error: {e}")
        return False

@functions_framework.http
def validate_email(request):
    """Main email validation function"""
    # Handle CORS for web requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json or 'email' not in request_json:
            return json.dumps({'error': 'Email parameter required'}), 400, headers
        
        email = request_json['email'].strip().lower()
        validation_details = {}
        
        # Format validation
        format_valid = validate_email_format(email)
        validation_details['format_valid'] = format_valid
        
        # Domain validation
        domain_valid = False
        if format_valid:
            domain = email.split('@')[1]
            domain_valid = validate_domain(domain)
            validation_details['domain_valid'] = domain_valid
        
        # Overall validation result
        is_valid = format_valid and domain_valid
        validation_details['overall_valid'] = is_valid
        
        # Log validation attempt
        log_validation(email, is_valid, validation_details)
        
        # Return result
        response = {
            'email': email,
            'is_valid': is_valid,
            'validation_details': validation_details
        }
        
        return json.dumps(response), 200, headers
        
    except Exception as e:
        error_response = {'error': f'Validation failed: {str(e)}'}
        return json.dumps(error_response), 500, headers
EOF
  
  depends_on = [
    google_storage_bucket.validation_logs
  ]
}

# Function requirements file
resource "local_file" "function_requirements" {
  filename = "${local.function_source_dir}/requirements.txt"
  content = <<-EOF
functions-framework==3.*
google-cloud-storage==2.*
dnspython==2.*
EOF
}

# Create archive of function source
data "archive_file" "function_source_zip" {
  type        = "zip"
  output_path = local.function_archive
  source_dir  = local.function_source_dir
  
  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source_archive" {
  name   = "function-source-${data.archive_file.function_source_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source_zip.output_path
  
  depends_on = [
    data.archive_file.function_source_zip
  ]
}

# Service account for the Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa"
  display_name = "Service Account for ${var.function_name} Cloud Function"
  description  = "Service account used by the email validation Cloud Function"
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# IAM binding to grant Cloud Storage object creation permissions
resource "google_storage_bucket_iam_member" "function_storage_access" {
  bucket = google_storage_bucket.validation_logs.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Logging
resource "google_project_iam_member" "function_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Monitoring (metrics)
resource "google_project_iam_member" "function_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Cloud Function (2nd generation)
resource "google_cloudfunctions2_function" "email_validator" {
  name        = var.function_name
  location    = var.region
  description = "Email validation API with comprehensive format and domain validation"
  
  labels = local.common_labels
  
  build_config {
    runtime     = var.python_runtime
    entry_point = var.entry_point
    
    environment_variables = {
      BUILD_CONFIG_ENV = "production"
    }
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source_archive.name
      }
    }
  }
  
  service_config {
    max_instance_count = var.max_instances
    min_instance_count = var.min_instances
    available_memory   = var.function_memory
    timeout_seconds    = var.function_timeout
    
    # Environment variables for the function
    environment_variables = {
      BUCKET_NAME = google_storage_bucket.validation_logs.name
      PROJECT_ID  = var.project_id
      REGION      = var.region
    }
    
    # Use custom service account
    service_account_email = google_service_account.function_sa.email
    
    # Allow all traffic on latest revision
    all_traffic_on_latest_revision = true
    
    # Set ingress to allow all traffic (can be restricted as needed)
    ingress_settings = "ALLOW_ALL"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source_archive,
    google_storage_bucket_iam_member.function_storage_access,
    google_project_iam_member.function_logging,
    google_project_iam_member.function_monitoring
  ]
}

# IAM policy to allow unauthenticated invocations (if enabled)
resource "google_cloudfunctions2_function_iam_member" "allow_unauthenticated" {
  count = var.allow_unauthenticated_invocations ? 1 : 0
  
  project        = google_cloudfunctions2_function.email_validator.project
  location       = google_cloudfunctions2_function.email_validator.location
  cloud_function = google_cloudfunctions2_function.email_validator.name
  role           = "roles/cloudfunctions.invoker"
  
  member = "allUsers"
}

# Cloud Run service IAM for unauthenticated access (2nd gen functions use Cloud Run)
resource "google_cloud_run_service_iam_member" "allow_unauthenticated_run" {
  count = var.allow_unauthenticated_invocations ? 1 : 0
  
  project  = google_cloudfunctions2_function.email_validator.project
  location = google_cloudfunctions2_function.email_validator.location
  service  = google_cloudfunctions2_function.email_validator.name
  role     = "roles/run.invoker"
  
  member = "allUsers"
}

# Cloud Logging retention policy (if supported in the region)
resource "google_logging_project_sink" "function_logs" {
  count = var.log_retention_days < 30 ? 0 : 1
  
  name        = "${var.function_name}-logs-sink"
  description = "Log sink for email validation function"
  
  # Log filter for the specific function
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${var.function_name}\""
  
  # Send logs to the validation logs bucket for long-term storage
  destination = "storage.googleapis.com/${google_storage_bucket.validation_logs.name}"
  
  # Use unique writer identity
  unique_writer_identity = true
}

# Grant the log sink service account permission to write to the bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.log_retention_days < 30 ? 0 : 1
  
  bucket = google_storage_bucket.validation_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity
}