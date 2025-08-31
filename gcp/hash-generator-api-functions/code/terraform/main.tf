# main.tf - Main Terraform configuration for Hash Generator API with Cloud Functions

# Generate a random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Enable required Google Cloud APIs
resource "google_project_service" "cloudfunctions_api" {
  project = var.project_id
  service = "cloudfunctions.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_project_service" "cloudbuild_api" {
  project = var.project_id
  service = "cloudbuild.googleapis.com"

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

# Create a Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_bucket" {
  name                        = "${var.project_id}-${var.function_name}-source-${random_id.suffix.hex}"
  location                    = var.region
  uniform_bucket_level_access = true
  
  labels = var.labels

  # Enable versioning for source code tracking
  versioning {
    enabled = true
  }

  # Lifecycle rule to manage old versions
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.cloudfunctions_api]
}

# Create the function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/function-source.zip"
  excludes    = ["__pycache__", "*.pyc", ".git", ".gitignore"]
}

# Upload the function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# Create the Cloud Function (2nd Generation)
resource "google_cloudfunctions2_function" "hash_generator" {
  name        = "${var.function_name}-${random_id.suffix.hex}"
  location    = var.region
  description = "Serverless HTTP API for generating MD5, SHA256, and SHA512 hashes from input text"

  labels = var.labels

  build_config {
    runtime     = var.runtime
    entry_point = "hash_generator"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count               = var.max_instances
    min_instance_count               = var.min_instances
    available_memory                 = "${var.memory_mb}Mi"
    timeout_seconds                  = var.timeout_seconds
    max_instance_request_concurrency = 1000
    available_cpu                    = "1"
    
    environment_variables = merge(var.environment_variables, {
      FUNCTION_TARGET = "hash_generator"
    })

    ingress_settings               = var.ingress_settings
    all_traffic_on_latest_revision = true

    # Service account for the function
    service_account_email = google_service_account.function_sa.email
  }

  depends_on = [
    google_project_service.cloudfunctions_api,
    google_project_service.cloudbuild_api,
    google_storage_bucket_object.function_source
  ]
}

# Create a dedicated service account for the Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa-${random_id.suffix.hex}"
  display_name = "Service Account for ${var.function_name} Cloud Function"
  description  = "Service account used by the hash generator Cloud Function"
}

# Grant necessary permissions to the service account
resource "google_project_iam_member" "function_sa_logs_writer" {
  count   = var.enable_logging ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_sa_monitoring_writer" {
  count   = var.enable_monitoring ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Allow public access to the function if enabled
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  count          = var.allow_unauthenticated ? 1 : 0
  project        = google_cloudfunctions2_function.hash_generator.project
  location       = google_cloudfunctions2_function.hash_generator.location
  cloud_function = google_cloudfunctions2_function.hash_generator.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create Cloud Monitoring alert policy for function errors (optional)
resource "google_monitoring_alert_policy" "function_error_rate" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "${var.function_name} Error Rate Alert"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Cloud Function error rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.label.function_name=\"${google_cloudfunctions2_function.hash_generator.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.1

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "86400s"
  }

  depends_on = [google_project_service.monitoring_api]
}

# Create a Cloud Logging sink for function logs (optional)
resource "google_logging_project_sink" "function_logs" {
  count       = var.enable_logging ? 1 : 0
  name        = "${var.function_name}-logs-sink-${random_id.suffix.hex}"
  destination = "logging.googleapis.com/projects/${var.project_id}/logs/${var.function_name}"

  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.hash_generator.name}\""

  unique_writer_identity = true

  depends_on = [google_project_service.logging_api]
}