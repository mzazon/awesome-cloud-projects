# Weather API Service with Cloud Functions - Main Terraform Configuration
# This file creates all the necessary GCP resources for a serverless weather API
# including Cloud Functions, Cloud Storage, and IAM configurations

# Local values for resource naming and configuration
locals {
  # Generate a random suffix for unique resource names
  name_suffix = random_id.resource_suffix.hex
  
  # Construct full resource names with suffix
  bucket_name    = "${var.bucket_name_prefix}-${local.name_suffix}"
  function_name  = var.function_name
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    created-by = "terraform"
    recipe     = "weather-api-service-functions"
  })
}

# Generate random suffix for unique resource naming
resource "random_id" "resource_suffix" {
  byte_length = 4
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])

  service = each.value
  
  # Prevent automatic disabling of APIs when resource is destroyed
  disable_on_destroy = false
  
  # Disable dependent services when this API is disabled
  disable_dependent_services = false
}

# Cloud Storage bucket for weather data caching
resource "google_storage_bucket" "weather_cache" {
  name          = local.bucket_name
  location      = var.region
  storage_class = var.bucket_storage_class
  
  # Prevent accidental deletion of the bucket
  force_destroy = true
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Apply labels for resource management
  labels = local.common_labels
  
  # Lifecycle management for automatic cleanup of old cache files
  lifecycle_rule {
    condition {
      age = var.cache_lifecycle_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Enable versioning for better data protection (optional)
  versioning {
    enabled = false
  }
  
  # Encryption configuration (Google-managed encryption keys)
  encryption {
    default_kms_key_name = null
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create source code archive for Cloud Function deployment
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      # Template variables can be injected here if needed
    })
    filename = "main.py"
  }
  
  source {
    content = templatefile("${path.module}/function_code/requirements.txt", {
      # Template variables can be injected here if needed
    })
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.resource_suffix.hex}.zip"
  bucket = google_storage_bucket.weather_cache.name
  source = data.archive_file.function_source.output_path
  
  # Detect changes in source code and trigger redeployment
  detect_md5hash = true
}

# Cloud Function for weather API
resource "google_cloudfunctions2_function" "weather_api" {
  name     = local.function_name
  location = var.region
  
  description = "Serverless weather API with caching functionality"
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "weather_api"
    
    source {
      storage_source {
        bucket = google_storage_bucket.weather_cache.name
        object = google_storage_bucket_object.function_source.name
      }
    }
    
    # Environment variables for build process
    environment_variables = {
      BUILD_CONFIG_TEST = "build_test"
    }
  }
  
  service_config {
    # Performance and scaling configuration
    max_instance_count               = 100
    min_instance_count               = 0
    available_memory                 = "${var.function_memory}M"
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 80
    available_cpu                    = "1"
    
    # Environment variables for runtime
    environment_variables = {
      WEATHER_CACHE_BUCKET   = google_storage_bucket.weather_cache.name
      OPENWEATHER_API_KEY    = var.openweather_api_key != "" ? var.openweather_api_key : "demo_key"
      LOG_LEVEL              = var.log_level
      ENABLE_CORS            = var.enable_cors ? "true" : "false"
      GCP_PROJECT            = var.project_id
      FUNCTION_REGION        = var.region
    }
    
    # Service account for the function
    service_account_email = google_service_account.function_sa.email
    
    # Ingress settings - allow all traffic for public API
    ingress_settings = "ALLOW_ALL"
    
    # Security settings
    all_traffic_on_latest_revision = true
  }
  
  # Apply labels for resource management
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# IAM binding to allow public access to the function (if enabled)
resource "google_cloudfunctions2_function_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.weather_api.name
  role           = "roles/run.invoker"
  member         = "allUsers"
}

# Service account for the Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa"
  display_name = "Service Account for Weather API Function"
  description  = "Service account used by the weather API Cloud Function"
}

# Grant storage admin permissions to the function's service account
resource "google_storage_bucket_iam_member" "function_storage_access" {
  bucket = google_storage_bucket.weather_cache.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant logging permissions to the function's service account
resource "google_project_iam_member" "function_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Grant monitoring permissions to the function's service account
resource "google_project_iam_member" "function_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Cloud Monitoring alert policy for function errors (optional)
resource "google_monitoring_alert_policy" "function_error_rate" {
  count = var.enable_function_logs ? 1 : 0
  
  display_name = "Weather API Function Error Rate"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud Function Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" resource.labels.function_name=\"${google_cloudfunctions2_function.weather_api.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = []
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Log sink for function logs (optional)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_function_logs ? 1 : 0
  
  name        = "weather-api-function-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.weather_cache.name}"
  
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${google_cloudfunctions2_function.weather_api.name}"
  EOT
  
  unique_writer_identity = true
}

# Grant the log sink permission to write to the bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_function_logs ? 1 : 0
  
  bucket = google_storage_bucket.weather_cache.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity
}