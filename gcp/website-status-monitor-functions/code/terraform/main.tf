# Website Status Monitor Cloud Function Infrastructure
# This Terraform configuration deploys a serverless website monitoring solution using Google Cloud Functions

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Enable required Google Cloud APIs
resource "google_project_service" "cloud_functions_api" {
  project = var.project_id
  service = "cloudfunctions.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "cloud_build_api" {
  project = var.project_id
  service = "cloudbuild.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "cloud_run_api" {
  project = var.project_id
  service = "run.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "logging_api" {
  project = var.project_id
  service = "logging.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "monitoring_api" {
  project = var.project_id
  service = "monitoring.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create a Cloud Storage bucket for storing function source code
resource "google_storage_bucket" "function_source" {
  name                        = "${var.project_id}-${var.function_name}-source-${random_id.suffix.hex}"
  location                    = var.region
  uniform_bucket_level_access = true
  
  # Enable versioning for source code management
  versioning {
    enabled = true
  }

  # Lifecycle management to clean up old versions
  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  labels = var.labels

  depends_on = [google_project_service.cloud_functions_api]
}

# Create the function source code files locally
resource "local_file" "main_py" {
  filename = "${path.module}/function-source/main.py"
  content  = <<-EOT
import functions_framework
import requests
import json
import time
from datetime import datetime, timezone
from urllib.parse import urlparse

@functions_framework.http
def website_status_monitor(request):
    """HTTP Cloud Function to monitor website status and performance."""
    
    # Set CORS headers for web requests
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
        # Parse request data
        if request.method == 'GET':
            url = request.args.get('url')
        else:
            request_json = request.get_json(silent=True)
            url = request_json.get('url') if request_json else None
        
        if not url:
            return (json.dumps({
                'error': 'URL parameter is required',
                'usage': 'GET /?url=https://example.com or POST with {"url": "https://example.com"}'
            }), 400, headers)
        
        # Validate URL format
        parsed_url = urlparse(url)
        if not parsed_url.scheme or not parsed_url.netloc:
            return (json.dumps({
                'error': 'Invalid URL format. Must include protocol (http:// or https://)'
            }), 400, headers)
        
        # Perform website health check
        start_time = time.time()
        
        try:
            response = requests.get(
                url,
                timeout=10,
                allow_redirects=True,
                headers={'User-Agent': 'GCP-Website-Monitor/1.0'}
            )
            
            end_time = time.time()
            response_time = round((end_time - start_time) * 1000, 2)  # Convert to milliseconds
            
            # Determine status
            is_healthy = 200 <= response.status_code < 400
            
            # Build response data
            result = {
                'url': url,
                'status': 'healthy' if is_healthy else 'unhealthy',
                'status_code': response.status_code,
                'response_time_ms': response_time,
                'content_length': len(response.content),
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'redirected': response.url != url,
                'final_url': response.url,
                'server': response.headers.get('server', 'Unknown'),
                'content_type': response.headers.get('content-type', 'Unknown')
            }
            
            print(f"Monitored {url}: {response.status_code} ({response_time}ms)")
            return (json.dumps(result), 200, headers)
            
        except requests.exceptions.Timeout:
            return (json.dumps({
                'url': url,
                'status': 'timeout',
                'error': 'Request timeout after 10 seconds',
                'timestamp': datetime.now(timezone.utc).isoformat()
            }), 200, headers)
            
        except requests.exceptions.ConnectionError:
            return (json.dumps({
                'url': url,
                'status': 'connection_error',
                'error': 'Unable to connect to the website',
                'timestamp': datetime.now(timezone.utc).isoformat()
            }), 200, headers)
            
        except Exception as e:
            return (json.dumps({
                'url': url,
                'status': 'error',
                'error': str(e),
                'timestamp': datetime.now(timezone.utc).isoformat()
            }), 200, headers)
    
    except Exception as e:
        print(f"Function error: {str(e)}")
        return (json.dumps({
            'error': 'Internal server error',
            'message': str(e)
        }), 500, headers)
  EOT
}

resource "local_file" "requirements_txt" {
  filename = "${path.module}/function-source/requirements.txt"
  content  = <<-EOT
requests==2.32.4
functions-framework==3.8.3
  EOT
}

# Create an archive of the function source code
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "${path.module}/function-source"
  output_path = "${path.module}/function-source.zip"
  
  depends_on = [
    local_file.main_py,
    local_file.requirements_txt
  ]
}

# Upload the function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# Create the Cloud Function (Gen 2)
resource "google_cloudfunctions2_function" "website_monitor" {
  name        = "${var.function_name}-${random_id.suffix.hex}"
  location    = var.region
  description = var.function_description

  build_config {
    runtime     = var.python_runtime
    entry_point = "website_status_monitor"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count = var.max_instances
    min_instance_count = var.min_instances
    
    available_memory   = "${var.function_memory}M"
    timeout_seconds    = var.function_timeout
    ingress_settings   = var.ingress_settings
    
    environment_variables = var.environment_variables
    
    # Service account for the function (uses default compute service account)
    service_account_email = "${data.google_project.current.number}-compute@developer.gserviceaccount.com"
  }

  labels = var.labels

  depends_on = [
    google_project_service.cloud_functions_api,
    google_project_service.cloud_build_api,
    google_project_service.cloud_run_api,
    google_storage_bucket_object.function_source
  ]
}

# Create IAM policy to allow unauthenticated access (if enabled)
resource "google_cloudfunctions2_function_iam_member" "public_access" {
  count = var.enable_unauthenticated_access ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.website_monitor.name
  role           = "roles/run.invoker"
  member         = "allUsers"

  depends_on = [google_cloudfunctions2_function.website_monitor]
}

# Create a log sink for monitoring function execution (optional)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_logging ? 1 : 0
  
  name        = "${var.function_name}-logs-${random_id.suffix.hex}"
  destination = "storage.googleapis.com/${google_storage_bucket.function_source.name}"
  
  # Filter to capture only logs from our Cloud Function
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.website_monitor.name}\""
  
  # Use a unique writer identity
  unique_writer_identity = true

  depends_on = [google_cloudfunctions2_function.website_monitor]
}

# Grant the log sink service account permission to write to the bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_logging ? 1 : 0
  
  bucket = google_storage_bucket.function_source.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity

  depends_on = [google_logging_project_sink.function_logs]
}

# Create a monitoring alert policy for function errors (optional)
resource "google_monitoring_alert_policy" "function_error_rate" {
  count = var.enable_logging ? 1 : 0
  
  display_name = "${var.function_name} Error Rate Alert"
  
  conditions {
    display_name = "Function error rate is high"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.website_monitor.name}\""
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1  # 10% error rate
      duration       = "300s" # 5 minutes
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s" # 30 minutes
  }

  depends_on = [
    google_project_service.monitoring_api,
    google_cloudfunctions2_function.website_monitor
  ]
}