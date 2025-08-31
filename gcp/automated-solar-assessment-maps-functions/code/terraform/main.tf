# Main Terraform configuration for Solar Assessment with Maps Platform Solar API and Cloud Functions
# This file creates the complete infrastructure for automated solar potential assessment

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention with random suffix
  name_suffix = random_id.suffix.hex
  common_labels = merge(var.labels, {
    environment = var.environment
    solution    = var.solution_name
  })

  # Resource names using consistent naming pattern
  input_bucket_name  = "${var.solution_name}-input-${local.name_suffix}"
  output_bucket_name = "${var.solution_name}-results-${local.name_suffix}"
  function_name      = "${var.solution_name}-processor-${local.name_suffix}"
  service_account_name = "${var.solution_name}-function-sa-${local.name_suffix}"

  # API services required for the solution
  required_apis = [
    "cloudfunctions.googleapis.com",  # Cloud Functions API
    "storage.googleapis.com",         # Cloud Storage API
    "solar.googleapis.com",          # Maps Platform Solar API
    "cloudbuild.googleapis.com",     # Cloud Build for function deployment
    "eventarc.googleapis.com",       # Eventarc for Cloud Storage triggers
    "run.googleapis.com",            # Cloud Run (required for 2nd gen functions)
    "pubsub.googleapis.com",         # Pub/Sub (required for event handling)
    "logging.googleapis.com",        # Cloud Logging
    "monitoring.googleapis.com"      # Cloud Monitoring
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)
  
  project = var.project_id
  service = each.value

  # Prevent accidental deletion of critical APIs
  disable_dependent_services = true
  disable_on_destroy        = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service account for Cloud Function execution
resource "google_service_account" "function_sa" {
  count = var.function_service_account_email == "" ? 1 : 0

  account_id   = local.service_account_name
  display_name = "Service Account for Solar Assessment Function"
  description  = "Service account used by the Cloud Function for solar assessment processing"
  project      = var.project_id

  depends_on = [google_project_service.apis]
}

# Grant necessary IAM roles to the service account
resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${local.function_service_account_email}"

  depends_on = [google_service_account.function_sa]
}

resource "google_project_iam_member" "function_maps_user" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageConsumer"
  member  = "serviceAccount:${local.function_service_account_email}"

  depends_on = [google_service_account.function_sa]
}

resource "google_project_iam_member" "function_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.function_service_account_email}"

  depends_on = [google_service_account.function_sa]
}

resource "google_project_iam_member" "function_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${local.function_service_account_email}"

  depends_on = [google_service_account.function_sa]
}

# Local value for service account email
locals {
  function_service_account_email = var.function_service_account_email != "" ? var.function_service_account_email : google_service_account.function_sa[0].email
}

# Create Google Maps Platform API key for Solar API access
resource "google_apikeys_key" "solar_api_key" {
  name         = "${var.solution_name}-api-key-${local.name_suffix}"
  display_name = "Solar Assessment API Key"
  project      = var.project_id

  restrictions {
    api_targets {
      service = "solar.googleapis.com"
    }
  }

  depends_on = [google_project_service.apis]
}

# Create Cloud Storage bucket for input CSV files
resource "google_storage_bucket" "input_bucket" {
  name     = local.input_bucket_name
  location = var.region
  project  = var.project_id

  # Storage class configuration
  storage_class = var.storage_class

  # Versioning configuration
  versioning {
    enabled = var.enable_versioning
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age                   = var.bucket_lifecycle_age_days
      with_state           = "NONCURRENT_VERSION"
      num_newer_versions   = 5
    }
    action {
      type = "Delete"
    }
  }

  # Lifecycle rule for cleaning up incomplete multipart uploads
  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }

  # Security and access configuration
  uniform_bucket_level_access = true
  
  # Enable logging if monitoring is enabled
  dynamic "logging" {
    for_each = var.enable_monitoring ? [1] : []
    content {
      log_bucket = google_storage_bucket.input_bucket.name
    }
  }

  # Labels for resource management
  labels = local.common_labels

  # Force deletion protection
  force_destroy = !var.deletion_protection

  depends_on = [google_project_service.apis]
}

# Create Cloud Storage bucket for assessment results
resource "google_storage_bucket" "output_bucket" {
  name     = local.output_bucket_name
  location = var.region
  project  = var.project_id

  # Storage class configuration
  storage_class = var.storage_class

  # Versioning configuration
  versioning {
    enabled = var.enable_versioning
  }

  # Lifecycle management for long-term storage
  lifecycle_rule {
    condition {
      age                   = var.bucket_lifecycle_age_days * 2  # Keep results longer than inputs
      with_state           = "NONCURRENT_VERSION"
      num_newer_versions   = 10  # Keep more versions of results
    }
    action {
      type = "Delete"
    }
  }

  # Lifecycle rule for cleaning up incomplete multipart uploads
  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }

  # Security and access configuration
  uniform_bucket_level_access = true

  # Labels for resource management
  labels = local.common_labels

  # Force deletion protection
  force_destroy = !var.deletion_protection

  depends_on = [google_project_service.apis]
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source_bucket" {
  name     = "${var.solution_name}-function-source-${local.name_suffix}"
  location = var.region
  project  = var.project_id

  # Standard storage for function source
  storage_class = "STANDARD"

  # No versioning needed for source code
  versioning {
    enabled = false
  }

  # Lifecycle rule for cleaning up old function versions
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Security configuration
  uniform_bucket_level_access = true

  # Labels for resource management
  labels = local.common_labels

  # Allow force destruction for source bucket
  force_destroy = true

  depends_on = [google_project_service.apis]
}

# Create archive for Cloud Function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/solar-function-source.zip"
  
  source {
    content = templatefile("${path.module}/function-source/main.py", {
      solar_api_required_quality = var.solar_api_required_quality
    })
    filename = "main.py"
  }

  source {
    content = file("${path.module}/function-source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "solar-function-source-${local.name_suffix}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.function_source.output_path

  # Content hash for change detection
  metadata = {
    content_hash = data.archive_file.function_source.output_md5
  }
}

# Deploy Cloud Function for solar assessment processing
resource "google_cloudfunctions2_function" "solar_processor" {
  name     = local.function_name
  location = var.region
  project  = var.project_id

  description = "Serverless function for automated solar potential assessment using Maps Platform Solar API"

  build_config {
    runtime     = "python311"
    entry_point = "process_solar_assessment"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    # Resource allocation
    max_instance_count = var.function_max_instances
    min_instance_count = 0
    available_memory   = "${var.function_memory_mb}Mi"
    timeout_seconds    = var.function_timeout_seconds

    # Environment variables for function configuration
    environment_variables = {
      SOLAR_API_KEY        = google_apikeys_key.solar_api_key.key_string
      OUTPUT_BUCKET        = google_storage_bucket.output_bucket.name
      SOLAR_API_QUALITY    = var.solar_api_required_quality
      GCP_PROJECT          = var.project_id
      FUNCTION_REGION      = var.region
    }

    # Service account for secure API access
    service_account_email = local.function_service_account_email

    # Network and security configuration
    ingress_settings = var.ingress_settings
    
    # VPC connector if specified
    dynamic "vpc_connector" {
      for_each = var.vpc_connector_name != "" ? [1] : []
      content {
        name = var.vpc_connector_name
      }
    }

    # Security settings
    all_traffic_on_latest_revision = true
  }

  # Event trigger configuration for Cloud Storage
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.input_bucket.name
    }

    # Optional: Filter for CSV files only
    event_filters {
      attribute = "eventType"
      value     = "google.cloud.storage.object.v1.finalized"
    }

    service_account_email = local.function_service_account_email
  }

  # Labels for resource management
  labels = local.common_labels

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.function_storage_admin,
    google_project_iam_member.function_maps_user,
    google_project_iam_member.function_logging,
    google_project_iam_member.function_monitoring
  ]

  # Lifecycle management
  lifecycle {
    replace_triggered_by = [
      google_storage_bucket_object.function_source
    ]
  }
}

# Create Cloud Storage notification for enhanced monitoring (optional)
resource "google_storage_notification" "input_bucket_notification" {
  count = var.enable_monitoring ? 1 : 0

  bucket         = google_storage_bucket.input_bucket.name
  payload_format = "JSON_API_V1"
  topic          = google_pubsub_topic.storage_notifications[0].id
  event_types    = ["OBJECT_FINALIZE", "OBJECT_DELETE"]

  depends_on = [google_pubsub_topic_iam_member.storage_publisher]
}

# Create Pub/Sub topic for storage notifications
resource "google_pubsub_topic" "storage_notifications" {
  count = var.enable_monitoring ? 1 : 0
  
  name    = "${var.solution_name}-storage-notifications-${local.name_suffix}"
  project = var.project_id

  labels = local.common_labels

  depends_on = [google_project_service.apis]
}

# Grant Cloud Storage service the publisher role on the topic
resource "google_pubsub_topic_iam_member" "storage_publisher" {
  count = var.enable_monitoring ? 1 : 0

  topic  = google_pubsub_topic.storage_notifications[0].name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"

  depends_on = [google_pubsub_topic.storage_notifications]
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Optional: Create log sink for centralized logging
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_monitoring ? 1 : 0

  name        = "${var.solution_name}-function-logs-${local.name_suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.output_bucket.name}/logs"
  
  # Filter for function logs only
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""

  # Use a unique writer identity
  unique_writer_identity = true

  depends_on = [google_cloudfunctions2_function.solar_processor]
}

# Grant the log sink writer access to the storage bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_monitoring ? 1 : 0

  bucket = google_storage_bucket.output_bucket.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity

  depends_on = [google_logging_project_sink.function_logs]
}

# Optional: Create monitoring alert policy for function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "Solar Assessment Function Error Rate"
  project      = var.project_id
  
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Function error rate too high"

    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.label.function_name=\"${local.function_name}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 5

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields    = ["resource.label.function_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [
    google_project_service.apis,
    google_cloudfunctions2_function.solar_processor
  ]
}