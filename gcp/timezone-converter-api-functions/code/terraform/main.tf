# Main Terraform configuration for Timezone Converter API using Google Cloud Functions
# This configuration deploys a serverless HTTP API for converting timestamps between timezones

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for resource naming and configuration
locals {
  function_name_unique = "${var.function_name}-${random_id.suffix.hex}"
  source_dir          = "${path.module}/../function-source"
  
  # Default labels merged with user-provided labels
  common_labels = merge(var.labels, {
    terraform-managed = "true"
    function-name     = var.function_name
    deployment-id     = random_id.suffix.hex
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ]) : toset([])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false

  # Add a delay to ensure APIs are fully enabled before creating dependent resources
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

# Create the function source code files
resource "local_file" "function_main" {
  filename = "${local.source_dir}/main.py"
  content = <<-EOF
import json
from datetime import datetime
from zoneinfo import ZoneInfo, available_timezones
import functions_framework

@functions_framework.http
def convert_timezone(request):
    """Convert time between timezones via HTTP request."""
    
    # Handle CORS for web browsers
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Get request parameters
        if request.method == 'POST':
            request_json = request.get_json(silent=True)
            if not request_json:
                return json.dumps({'error': 'Invalid JSON'}), 400, headers
            
            timestamp = request_json.get('timestamp')
            from_tz = request_json.get('from_timezone', 'UTC')
            to_tz = request_json.get('to_timezone', 'UTC')
        else:  # GET request
            timestamp = request.args.get('timestamp')
            from_tz = request.args.get('from_timezone', 'UTC')
            to_tz = request.args.get('to_timezone', 'UTC')
        
        # Validate timezone names
        available_zones = available_timezones()
        if from_tz not in available_zones:
            return json.dumps({'error': f'Invalid from_timezone: {from_tz}'}), 400, headers
        if to_tz not in available_zones:
            return json.dumps({'error': f'Invalid to_timezone: {to_tz}'}), 400, headers
        
        # Parse timestamp (support multiple formats)
        if timestamp:
            try:
                # Try ISO format first
                dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=ZoneInfo(from_tz))
            except ValueError:
                try:
                    # Try Unix timestamp
                    dt = datetime.fromtimestamp(float(timestamp), tz=ZoneInfo(from_tz))
                except (ValueError, OSError):
                    return json.dumps({'error': 'Invalid timestamp format'}), 400, headers
        else:
            # Use current time if no timestamp provided
            dt = datetime.now(tz=ZoneInfo(from_tz))
        
        # Convert timezone
        converted_dt = dt.astimezone(ZoneInfo(to_tz))
        
        # Prepare response
        response = {
            'original': {
                'timestamp': dt.isoformat(),
                'timezone': from_tz,
                'timezone_name': dt.tzname()
            },
            'converted': {
                'timestamp': converted_dt.isoformat(),
                'timezone': to_tz,
                'timezone_name': converted_dt.tzname()
            },
            'offset_hours': (converted_dt.utcoffset() - dt.utcoffset()).total_seconds() / 3600
        }
        
        return json.dumps(response, indent=2), 200, headers
        
    except Exception as e:
        return json.dumps({'error': str(e)}), 500, headers
EOF

  depends_on = [google_project_service.required_apis]
}

# Create the requirements.txt file
resource "local_file" "function_requirements" {
  filename = "${local.source_dir}/requirements.txt"
  content  = "functions-framework==3.*\n"

  depends_on = [google_project_service.required_apis]
}

# Create a ZIP archive of the function source code
data "archive_file" "function_source_zip" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  source_dir  = local.source_dir

  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Create a Cloud Storage bucket for storing the function source code
resource "google_storage_bucket" "function_source" {
  name          = "${var.project_id}-${local.function_name_unique}-source"
  location      = var.region
  force_destroy = true

  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true

  # Lifecycle policy to automatically delete old versions
  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Upload the function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source_zip" {
  name   = "function-source-${data.archive_file.function_source_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source_zip.output_path

  depends_on = [data.archive_file.function_source_zip]
}

# Create the Cloud Function (Generation 2)
resource "google_cloudfunctions2_function" "timezone_converter" {
  name        = local.function_name_unique
  location    = var.region
  description = "Serverless API for converting timestamps between different timezones"

  build_config {
    runtime     = var.runtime
    entry_point = var.entry_point

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source_zip.name
      }
    }
  }

  service_config {
    # Performance and scaling configuration
    max_instance_count               = var.service_config.max_instance_count
    min_instance_count               = var.service_config.min_instance_count
    available_memory                 = var.service_config.available_memory != null ? var.service_config.available_memory : var.function_memory
    timeout_seconds                  = var.service_config.timeout_seconds != null ? var.service_config.timeout_seconds : var.function_timeout
    max_instance_request_concurrency = var.service_config.max_instance_request_concurrency
    available_cpu                    = var.service_config.available_cpu
    
    # Network and access configuration
    ingress_settings                 = var.service_config.ingress_settings
    all_traffic_on_latest_revision   = var.service_config.all_traffic_on_latest_revision
    
    # Environment variables
    dynamic "environment_variables" {
      for_each = var.environment_variables
      content {
        key   = environment_variables.key
        value = environment_variables.value
      }
    }

    # Service account for the function (uses default compute service account)
    service_account_email = "${var.project_id}-compute@developer.gserviceaccount.com"
  }

  labels = local.common_labels

  depends_on = [
    google_storage_bucket_object.function_source_zip,
    google_project_service.required_apis
  ]
}

# IAM binding to allow unauthenticated access (if enabled)
resource "google_cloudfunctions2_function_iam_binding" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0

  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.timezone_converter.name
  role           = "roles/cloudfunctions.invoker"
  members        = ["allUsers"]

  depends_on = [google_cloudfunctions2_function.timezone_converter]
}

# Cloud Logging configuration (automatic for Cloud Functions)
# Logs are automatically sent to Cloud Logging with the function name as the log source

# Optional: Create a log-based metric for monitoring function usage
resource "google_logging_metric" "function_requests" {
  name   = "${local.function_name_unique}-requests"
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name_unique}\""

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "Timezone Converter API Requests"
  }

  depends_on = [google_cloudfunctions2_function.timezone_converter]
}

# Optional: Create alerting policy for function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  display_name = "${local.function_name_unique} Error Rate Alert"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "High error rate"

    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.label.function_name=\"${local.function_name_unique}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 5

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []

  documentation {
    content   = "The Timezone Converter API function is experiencing a high error rate."
    mime_type = "text/markdown"
  }

  depends_on = [google_cloudfunctions2_function.timezone_converter]
}