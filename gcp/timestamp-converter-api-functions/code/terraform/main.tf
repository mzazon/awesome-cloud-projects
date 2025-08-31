# Timestamp Converter API with Cloud Functions - Main Terraform Configuration
# This configuration deploys a serverless timestamp conversion API using Google Cloud Functions

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique names with random suffix
  bucket_name = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.resource_labels, {
    deployment-id = random_id.suffix.hex
  })
  
  # Function source code content
  function_main_py = <<-EOF
import functions_framework
from datetime import datetime
import pytz
import json
from flask import jsonify

@functions_framework.http
def ${var.function_entry_point}(request):
    """HTTP Cloud Function for timestamp conversion.
    
    Supports conversion between Unix timestamps and human-readable dates
    with timezone support and multiple output formats.
    """
    
    # Set CORS headers for web browser compatibility
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Parse request parameters
        if request.method == 'GET':
            timestamp = request.args.get('timestamp')
            timezone = request.args.get('timezone', 'UTC')
            format_type = request.args.get('format', 'iso')
        else:
            request_json = request.get_json(silent=True)
            timestamp = request_json.get('timestamp') if request_json else None
            timezone = request_json.get('timezone', 'UTC') if request_json else 'UTC'
            format_type = request_json.get('format', 'iso') if request_json else 'iso'
        
        if not timestamp:
            return jsonify({
                'error': 'Missing timestamp parameter',
                'usage': 'GET /?timestamp=1609459200&timezone=UTC&format=iso'
            }), 400, headers
        
        # Convert timestamp
        if timestamp == 'now':
            dt = datetime.now(pytz.UTC)
            unix_timestamp = int(dt.timestamp())
        else:
            try:
                unix_timestamp = int(timestamp)
                dt = datetime.fromtimestamp(unix_timestamp, pytz.UTC)
            except ValueError:
                return jsonify({
                    'error': 'Invalid timestamp format',
                    'expected': 'Unix timestamp (seconds since epoch) or "now"'
                }), 400, headers
        
        # Apply timezone conversion
        try:
            target_tz = pytz.timezone(timezone)
            dt_local = dt.astimezone(target_tz)
        except pytz.exceptions.UnknownTimeZoneError:
            return jsonify({
                'error': f'Invalid timezone: {timezone}',
                'suggestion': 'Use timezone names like UTC, US/Eastern, Europe/London'
            }), 400, headers
        
        # Format output
        formats = {
            'iso': dt_local.isoformat(),
            'rfc': dt_local.strftime('%a, %d %b %Y %H:%M:%S %z'),
            'human': dt_local.strftime('%Y-%m-%d %H:%M:%S %Z'),
            'date': dt_local.strftime('%Y-%m-%d'),
            'time': dt_local.strftime('%H:%M:%S %Z')
        }
        
        response = {
            'unix_timestamp': unix_timestamp,
            'timezone': timezone,
            'formatted': {
                'iso': formats['iso'],
                'rfc': formats['rfc'],
                'human': formats['human'],
                'date': formats['date'],
                'time': formats['time']
            },
            'requested_format': formats.get(format_type, formats['iso'])
        }
        
        return jsonify(response), 200, headers
        
    except Exception as e:
        return jsonify({
            'error': 'Internal server error',
            'message': str(e)
        }), 500, headers
EOF

  function_requirements_txt = <<-EOF
functions-framework==3.*
pytz==2024.*
EOF
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_required_apis ? toset(var.required_apis) : toset([])
  
  project = var.project_id
  service = each.key
  
  # Keep services enabled even if this resource is destroyed
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = local.bucket_name
  location = var.bucket_location
  project  = var.project_id
  
  # Storage configuration
  storage_class               = var.bucket_storage_class
  uniform_bucket_level_access = true
  
  # Enable versioning for source code history
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  # Lifecycle management to clean up old versions
  lifecycle_rule {
    condition {
      age                   = 30
      num_newer_versions    = 5
      with_state           = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }
  
  # Labels for organization
  labels = local.common_labels
  
  # Prevent accidental deletion in production
  lifecycle {
    prevent_destroy = false
  }
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Create function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = var.source_archive_output_path
  
  # Check if external source code exists, otherwise use inline
  source_dir = fileexists("${var.source_code_path}/main.py") ? var.source_code_path : null
  
  # Create inline function code if external source doesn't exist
  dynamic "source" {
    for_each = fileexists("${var.source_code_path}/main.py") ? [] : [1]
    content {
      content  = local.function_main_py
      filename = "main.py"
    }
  }
  
  dynamic "source" {
    for_each = fileexists("${var.source_code_path}/main.py") ? [] : [1]
    content {
      content  = local.function_requirements_txt
      filename = "requirements.txt"
    }
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  # Metadata for tracking
  metadata = {
    timestamp     = timestamp()
    terraform     = "true"
    function-name = var.function_name
  }
}

# Create service account for Cloud Function execution
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa"
  display_name = "Service Account for ${var.function_name} Cloud Function"
  description  = "Service account used by the timestamp converter Cloud Function"
  project      = var.project_id
  
  depends_on = [
    google_project_service.required_apis
  ]
}

# Grant necessary IAM roles to the function service account
resource "google_project_iam_member" "function_sa_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Deploy Cloud Function (2nd generation using Cloud Run)
resource "google_cloudfunctions2_function" "timestamp_converter" {
  name     = var.function_name
  location = var.region
  project  = var.project_id
  
  description = var.function_description
  
  # Build configuration
  build_config {
    runtime     = var.function_runtime
    entry_point = var.function_entry_point
    
    # Source code from Cloud Storage
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
    
    # Environment variables for build process
    environment_variables = {
      BUILD_CONFIG_TEST = "BUILD_CONFIG_TEST"
    }
  }
  
  # Service configuration for HTTP function
  service_config {
    max_instance_count                    = var.function_max_instances
    min_instance_count                    = var.function_min_instances
    max_instance_request_concurrency      = var.function_max_instance_request_concurrency
    available_memory                      = "${var.function_memory}Mi"
    timeout_seconds                       = var.function_timeout
    ingress_settings                      = var.ingress_settings
    all_traffic_on_latest_revision        = true
    
    # Environment variables for the function runtime
    environment_variables = var.function_environment_variables
    
    # Service account for function execution
    service_account_email = google_service_account.function_sa.email
  }
  
  # Labels for organization and billing
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_service_account.function_sa
  ]
}

# Allow public access to the Cloud Function if configured
resource "google_cloudfunctions2_function_iam_member" "public_access" {
  count = var.allow_unauthenticated_invocations ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.timestamp_converter.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Cloud Run service IAM for public access (2nd gen functions use Cloud Run)
resource "google_cloud_run_service_iam_member" "public_access" {
  count = var.allow_unauthenticated_invocations ? 1 : 0
  
  project  = var.project_id
  location = var.region
  service  = google_cloudfunctions2_function.timestamp_converter.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}