# Main Terraform configuration for password generator Cloud Function
# This file contains all the infrastructure resources needed to deploy
# a serverless password generator API using Google Cloud Functions

# Local values for resource naming and configuration
locals {
  # Generate resource names with optional prefix and suffix
  function_name = var.resource_prefix != "" || var.resource_suffix != "" ? format("%s%s%s", 
    var.resource_prefix != "" ? "${var.resource_prefix}-" : "",
    var.function_name,
    var.resource_suffix != "" ? "-${var.resource_suffix}" : ""
  ) : var.function_name

  bucket_name = var.bucket_name != null ? var.bucket_name : format("%s-function-source-%s", 
    var.project_id, 
    random_id.bucket_suffix.hex
  )

  # Merge default and user-provided labels
  common_labels = merge(
    {
      environment = var.environment
      managed-by  = "terraform"
      recipe      = "password-generator-cloud-functions"
      function    = local.function_name
    },
    var.labels
  )

  # Set zone based on region if not specified
  zone = var.zone != null ? var.zone : "${var.region}-a"
}

# Generate random suffix for unique resource names
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(var.apis_to_enable) : toset([])

  project = var.project_id
  service = each.value

  # Prevent disabling APIs on destroy to avoid dependency issues
  disable_on_destroy = false

  # Allow time for APIs to be fully enabled
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Google Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = local.bucket_name
  location = var.bucket_location
  project  = var.project_id

  # Configure bucket settings for function source storage
  storage_class                   = var.bucket_storage_class
  uniform_bucket_level_access     = true
  public_access_prevention        = "enforced"
  force_destroy                   = true

  # Versioning for source code management
  versioning {
    enabled = true
  }

  # Lifecycle management to control costs
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Lifecycle rule for non-current versions
  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create the function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = var.source_code_path
  output_path = "${path.module}/function-source.zip"
  excludes    = ["__pycache__", "*.pyc", ".git", ".gitignore", "README.md"]
}

# Upload function source code to Google Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "${var.source_archive_bucket_prefix}/source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  # Ensure the source code is re-uploaded when changed
  detect_md5hash = data.archive_file.function_source.output_md5

  depends_on = [google_storage_bucket.function_source]
}

# Create the Cloud Function (Gen 2)
resource "google_cloudfunctions2_function" "password_generator" {
  name        = local.function_name
  location    = var.region
  description = var.function_description
  project     = var.project_id

  build_config {
    runtime     = var.function_runtime
    entry_point = "generate_password"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }

    # Environment variables for build process
    environment_variables = {
      BUILD_CONFIG_TEST = "true"
    }
  }

  service_config {
    # Resource allocation
    max_instance_count               = var.function_max_instances
    min_instance_count               = var.function_min_instances
    available_memory                 = var.function_memory
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = 1000

    # Environment variables for runtime
    environment_variables = {
      LOG_LEVEL       = var.log_level
      ENVIRONMENT     = var.environment
      FUNCTION_TARGET = "generate_password"
    }

    # Ingress and security settings
    ingress_settings               = var.ingress_settings
    all_traffic_on_latest_revision = true

    # Service account (uses default Compute Engine service account)
    service_account_email = "${data.google_project.current.number}-compute@developer.gserviceaccount.com"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Create IAM binding to allow unauthenticated access (if enabled)
resource "google_cloudfunctions2_function_iam_binding" "allow_unauthenticated" {
  count = var.allow_unauthenticated ? 1 : 0

  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.password_generator.name
  role           = "roles/run.invoker"
  members        = ["allUsers"]

  depends_on = [google_cloudfunctions2_function.password_generator]
}

# Create a service account for the function (optional, for enhanced security)
resource "google_service_account" "function_sa" {
  account_id   = "${local.function_name}-sa"
  display_name = "Service Account for ${local.function_name} Cloud Function"
  description  = "Service account used by the password generator Cloud Function"
  project      = var.project_id
}

# Grant necessary permissions to the function service account
resource "google_project_iam_member" "function_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create Cloud Logging sink for function logs (optional)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_logging ? 1 : 0

  name        = "${local.function_name}-logs"
  destination = "logging.googleapis.com/projects/${var.project_id}/logs/${local.function_name}"
  filter      = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""

  # Use a unique writer identity
  unique_writer_identity = true

  depends_on = [google_cloudfunctions2_function.password_generator]
}

# Create monitoring alert policy for function errors (optional)
resource "google_monitoring_alert_policy" "function_error_rate" {
  display_name = "${local.function_name} Error Rate Alert"
  combiner     = "OR"
  enabled      = true
  project      = var.project_id

  conditions {
    display_name = "Cloud Function Error Rate"

    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.label.function_name=\"${local.function_name}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 10

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [
    google_cloudfunctions2_function.password_generator,
    google_project_service.required_apis
  ]
}

# Create a URL map for custom domain (optional, commented out by default)
/*
resource "google_compute_url_map" "function_url_map" {
  name            = "${local.function_name}-url-map"
  default_service = google_cloudfunctions2_function.password_generator.service_config[0].uri
  project         = var.project_id

  depends_on = [google_cloudfunctions2_function.password_generator]
}
*/

# Create firewall rule for function access (if using VPC)
/*
resource "google_compute_firewall" "allow_function_ingress" {
  name    = "${local.function_name}-allow-ingress"
  network = "default"
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["443", "80"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${local.function_name}-function"]

  depends_on = [google_cloudfunctions2_function.password_generator]
}
*/