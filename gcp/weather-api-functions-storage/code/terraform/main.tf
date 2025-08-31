# Weather API Infrastructure with Cloud Functions and Cloud Storage
# This configuration creates a serverless weather API with intelligent caching capabilities

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Generate bucket name if not provided
locals {
  # Use provided bucket name or generate one with random suffix
  bucket_name = var.bucket_name != "" ? var.bucket_name : "weather-cache-${random_id.suffix.hex}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    terraform-managed = "true"
    recipe           = "weather-api-functions-storage"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "eventarc.googleapis.com"
  ]) : toset([])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Cloud Storage bucket for caching weather data
resource "google_storage_bucket" "weather_cache" {
  name                        = local.bucket_name
  location                    = var.bucket_location
  storage_class               = var.bucket_storage_class
  uniform_bucket_level_access = true
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false
  }

  # Enable versioning for data protection
  versioning {
    enabled = true
  }

  # Lifecycle management to control costs
  lifecycle_rule {
    condition {
      age = 7 # Delete objects older than 7 days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age                   = 1
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  # CORS configuration for web applications
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  # Labels for resource management
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Service account for Cloud Function with least privilege permissions
resource "google_service_account" "function_sa" {
  account_id   = "weather-api-function-sa"
  display_name = "Weather API Cloud Function Service Account"
  description  = "Service account for weather API Cloud Function with minimal required permissions"
  project      = var.project_id
}

# IAM binding for function service account to access storage bucket
resource "google_storage_bucket_iam_member" "function_storage_access" {
  bucket = google_storage_bucket.weather_cache.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.function_sa.email}"

  depends_on = [google_service_account.function_sa]
}

# IAM binding for function service account to write logs
resource "google_project_iam_member" "function_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"

  depends_on = [google_service_account.function_sa]
}

# Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/weather-function-source.zip"
  
  source {
    content = templatefile("${path.module}/function-source/main.py", {
      cache_duration_minutes = var.cache_duration_minutes
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function-source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name                        = "${local.bucket_name}-source"
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Upload function source code to storage
resource "google_storage_bucket_object" "function_source" {
  name   = "weather-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# Cloud Function for weather API
resource "google_cloudfunctions2_function" "weather_api" {
  name     = var.function_name
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "python312"
    entry_point = "weather_api"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
    
    environment_variables = {
      BUILD_CONFIG_TEST = "true"
    }
  }

  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = var.function_min_instances
    available_memory                 = "${var.function_memory}Mi"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 80
    available_cpu                    = "1"
    
    environment_variables = {
      CACHE_BUCKET       = google_storage_bucket.weather_cache.name
      WEATHER_API_KEY    = var.weather_api_key
      CACHE_DURATION     = var.cache_duration_minutes
      FUNCTION_REGION    = var.region
      PROJECT_ID         = var.project_id
    }

    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_sa.email
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_service_account.function_sa,
    google_storage_bucket_iam_member.function_storage_access
  ]
}

# IAM policy to allow unauthenticated invocation
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = var.project_id
  location       = google_cloudfunctions2_function.weather_api.location
  cloud_function = google_cloudfunctions2_function.weather_api.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"

  depends_on = [google_cloudfunctions2_function.weather_api]
}

# Cloud Monitoring alert policy for function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  display_name = "Weather API Function Error Rate"
  combiner     = "OR"
  enabled      = true
  project      = var.project_id

  conditions {
    display_name = "Function error rate too high"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${var.function_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1 # 10% error rate threshold
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields    = ["resource.labels.function_name"]
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s" # 30 minutes
  }

  depends_on = [google_cloudfunctions2_function.weather_api]
}

# Cloud Logging sink for structured logging
resource "google_logging_project_sink" "function_logs" {
  name        = "weather-api-logs-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.weather_cache.name}"
  filter      = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${var.function_name}\""
  
  unique_writer_identity = true
  
  depends_on = [
    google_cloudfunctions2_function.weather_api,
    google_storage_bucket.weather_cache
  ]
}

# Grant the logging sink write access to the bucket
resource "google_storage_bucket_iam_member" "logging_sink_writer" {
  bucket = google_storage_bucket.weather_cache.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs.writer_identity

  depends_on = [google_logging_project_sink.function_logs]
}