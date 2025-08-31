# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent naming and configuration
locals {
  resource_suffix = random_id.suffix.hex
  bucket_name     = var.source_archive_bucket != "" ? var.source_archive_bucket : "${var.function_name}-source-${local.resource_suffix}"
  archive_name    = var.source_archive_object != "" ? var.source_archive_object : "weather-function-source.zip"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    function-name = var.function_name
    deployment    = "terraform"
    created-by    = "terraform"
  })

  # Required APIs for the weather forecast function
  required_apis = [
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value

  # Prevent deletion of essential services
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Google Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name          = local.bucket_name
  location      = var.region
  project       = var.project_id
  force_destroy = true

  # Security and versioning configuration
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create the function source code files
resource "local_file" "main_py" {
  filename = "${path.module}/function_source/main.py"
  content = <<-EOF
import json
import os
import requests
from flask import Request
import functions_framework

@functions_framework.http
def weather_forecast(request: Request):
    """HTTP Cloud Function for weather forecasts."""
    
    # Enable CORS for web browsers
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for actual request
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Get city parameter from query string
        city = request.args.get('city', 'London')
        
        # OpenWeatherMap API configuration
        api_key = os.environ.get('OPENWEATHER_API_KEY', 'demo_key')
        base_url = "http://api.openweathermap.org/data/2.5/weather"
        
        # Make API request
        params = {
            'q': city,
            'appid': api_key,
            'units': 'metric'
        }
        
        response = requests.get(base_url, params=params, timeout=10)
        
        if response.status_code == 200:
            data = response.json()
            
            # Format response
            forecast = {
                'city': data['name'],
                'country': data['sys']['country'],
                'temperature': data['main']['temp'],
                'feels_like': data['main']['feels_like'],
                'humidity': data['main']['humidity'],
                'description': data['weather'][0]['description'],
                'wind_speed': data['wind']['speed'],
                'timestamp': data['dt']
            }
            
            return (json.dumps(forecast), 200, headers)
        
        elif response.status_code == 401:
            return (json.dumps({'error': 'Invalid API key'}), 401, headers)
        
        elif response.status_code == 404:
            return (json.dumps({'error': 'City not found'}), 404, headers)
        
        else:
            return (json.dumps({'error': 'Weather service unavailable'}), 503, headers)
            
    except requests.RequestException as e:
        return (json.dumps({'error': 'Network error occurred'}), 500, headers)
    
    except Exception as e:
        return (json.dumps({'error': 'Internal server error'}), 500, headers)
EOF
}

# Create requirements.txt for Python dependencies
resource "local_file" "requirements_txt" {
  filename = "${path.module}/function_source/requirements.txt"
  content = <<-EOF
requests==2.31.0
functions-framework==3.4.0
EOF
}

# Create source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/weather-function-source.zip"
  source_dir  = "${path.module}/function_source"
  
  depends_on = [
    local_file.main_py,
    local_file.requirements_txt
  ]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_archive" {
  name   = local.archive_name
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  # Force re-upload when source code changes
  detect_md5hash = data.archive_file.function_source.output_md5
}

# Create Cloud Run service (Gen 2 Cloud Functions)
resource "google_cloud_run_v2_service" "weather_function" {
  name     = var.function_name
  location = var.region
  project  = var.project_id

  # Ingress configuration
  ingress = var.ingress

  template {
    # Scaling configuration
    scaling {
      max_instance_count = var.max_instances
      min_instance_count = var.min_instances
    }

    # Container configuration
    containers {
      # Use Google Cloud Functions buildpack
      image = "gcr.io/buildpacks/builder:v1"

      # Resource limits
      resources {
        limits = {
          cpu    = var.cpu_limit
          memory = var.memory_limit
        }
        # CPU is always allocated in Cloud Run Gen 2
        cpu_idle = false
      }

      # Environment variables
      env {
        name  = "OPENWEATHER_API_KEY"
        value = var.openweather_api_key
      }

      env {
        name  = "LOG_LEVEL"
        value = var.log_level
      }

      # Function configuration
      env {
        name  = "FUNCTION_TARGET"
        value = "weather_forecast"
      }

      env {
        name  = "FUNCTION_SOURCE"
        value = "gs://${google_storage_bucket.function_source.name}/${google_storage_bucket_object.function_archive.name}"
      }

      # Port configuration
      ports {
        container_port = 8080
        name          = "http1"
      }

      # Startup and liveness probes
      startup_probe {
        initial_delay_seconds = 0
        timeout_seconds       = 240
        period_seconds       = 240
        failure_threshold    = 1
        tcp_socket {
          port = 8080
        }
      }

      liveness_probe {
        initial_delay_seconds = 0
        timeout_seconds       = 1
        period_seconds       = 3
        failure_threshold    = 3
        http_get {
          path = "/"
          port = 8080
        }
      }
    }

    # Request timeout configuration
    timeout = "${var.timeout_seconds}s"

    # Container concurrency
    max_instance_request_concurrency = var.concurrency

    # Execution environment
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"

    # Service account (uses default compute service account)
    service_account = google_service_account.function_sa.email

    # Labels for the service template
    labels = local.common_labels
  }

  # Labels for the service itself
  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_archive
  ]
}

# Create a dedicated service account for the function
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa"
  display_name = "Service Account for ${var.function_name} Cloud Function"
  description  = "Service account used by the weather forecast Cloud Function"
  project      = var.project_id
}

# Grant necessary IAM roles to the service account
resource "google_project_iam_member" "function_sa_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Allow public access to the Cloud Run service if configured
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.weather_function.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Create a Cloud Monitoring alert policy for function errors (optional)
resource "google_monitoring_alert_policy" "function_error_rate" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "${var.function_name} Error Rate Alert"
  project      = var.project_id
  
  conditions {
    display_name = "Error rate too high"
    
    condition_threshold {
      filter = join(" AND ", [
        "resource.type=\"cloud_run_revision\"",
        "resource.label.service_name=\"${var.function_name}\"",
        "metric.type=\"run.googleapis.com/request_count\""
      ])
      
      comparison = "COMPARISON_GREATER_THAN"
      
      threshold_value = 10
      duration        = "300s"
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields = [
          "resource.label.service_name"
        ]
      }
      
      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  combiner = "OR"

  enabled = true
}

# Create a log-based metric for monitoring function invocations
resource "google_logging_metric" "function_invocations" {
  count = var.enable_logging ? 1 : 0

  name    = "${var.function_name}-invocations"
  project = var.project_id
  
  filter = join(" AND ", [
    "resource.type=\"cloud_run_revision\"",
    "resource.labels.service_name=\"${var.function_name}\"",
    "textPayload=~\"Function execution\""
  ])

  metric_descriptor {
    metric_kind = "COUNTER"
    value_type  = "INT64"
    display_name = "${var.function_name} Invocations"
  }
}

# Create a log sink for function logs (optional, for long-term storage)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_logging ? 1 : 0

  name        = "${var.function_name}-logs-sink"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.function_logs[0].name}"

  filter = join(" AND ", [
    "resource.type=\"cloud_run_revision\"",
    "resource.labels.service_name=\"${var.function_name}\""
  ])

  unique_writer_identity = true
}

# Create a storage bucket for long-term log storage (optional)
resource "google_storage_bucket" "function_logs" {
  count = var.enable_logging ? 1 : 0

  name          = "${var.function_name}-logs-${local.resource_suffix}"
  location      = var.region
  project       = var.project_id
  force_destroy = true

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  labels = merge(local.common_labels, {
    purpose = "log-storage"
  })
}

# Grant log sink permission to write to the storage bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_logging ? 1 : 0

  bucket = google_storage_bucket.function_logs[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity
}