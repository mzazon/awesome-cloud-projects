# AI Content Validation Infrastructure with Vertex AI and Cloud Functions
# This configuration creates a complete serverless content validation system
# using Vertex AI's Gemini models for safety scoring and Cloud Functions for processing

# Configure the Google Cloud Provider
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = var.random_suffix_length / 2
}

locals {
  # Common resource naming convention
  resource_suffix = random_id.suffix.hex
  
  # Combine user-provided labels with standard labels
  common_labels = merge(var.labels, {
    environment     = var.environment
    resource-suffix = local.resource_suffix
    created-by      = "terraform"
    recipe-id       = "ai-content-validation"
  })

  # Required APIs for the content validation system
  required_apis = [
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com", 
    "aiplatform.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com"
  ]

  # Combine required APIs with user-specified additional APIs
  all_apis = distinct(concat(local.required_apis, var.enable_apis))
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(local.all_apis)
  
  project = var.project_id
  service = each.value

  # Prevent disabling services when destroying unless explicitly requested
  disable_dependent_services = var.disable_dependent_services
  disable_on_destroy         = var.disable_dependent_services
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Create Cloud Storage bucket for content input
resource "google_storage_bucket" "content_input" {
  name          = "content-input-${local.resource_suffix}"
  project       = var.project_id
  location      = var.region
  storage_class = var.content_bucket_location
  
  # Enable uniform bucket-level access for enhanced security
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Prevent public access to bucket contents
  public_access_prevention = var.enable_public_access_prevention ? "enforced" : "inherited"

  # Enable versioning for data protection
  versioning {
    enabled = var.bucket_versioning_enabled
  }

  # Lifecycle management for cost optimization
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_enabled ? [1] : []
    content {
      condition {
        age = var.bucket_lifecycle_age_days
      }
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
    }
  }

  # CORS configuration for web uploads
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis
  ]
}

# Create Cloud Storage bucket for validation results
resource "google_storage_bucket" "validation_results" {
  name          = "validation-results-${local.resource_suffix}"
  project       = var.project_id
  location      = var.region
  storage_class = var.results_bucket_location
  
  # Security configurations
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  public_access_prevention    = var.enable_public_access_prevention ? "enforced" : "inherited"

  # Versioning for audit trail
  versioning {
    enabled = var.bucket_versioning_enabled
  }

  # Lifecycle management for automatic cleanup
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_enabled ? [1] : []
    content {
      condition {
        age = var.bucket_retention_days
      }
      action {
        type = "Delete"
      }
    }
  }

  # Retention policy for compliance
  retention_policy {
    retention_period = var.bucket_retention_days * 24 * 3600 # Convert days to seconds
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis
  ]
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "content-validator-${local.resource_suffix}"
  display_name = "Content Validation Function Service Account"
  description  = "Service account for AI content validation Cloud Function"
  project      = var.project_id

  depends_on = [
    google_project_service.required_apis
  ]
}

# Grant necessary IAM permissions to function service account
resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_aiplatform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_eventarc_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create the Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/content-validator-${local.resource_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_source/main.py", {
      project_id           = var.project_id
      region              = var.vertex_ai_location
      results_bucket      = google_storage_bucket.validation_results.name
      gemini_model        = var.gemini_model_name
      safety_threshold    = var.safety_threshold
      log_level          = var.log_level
    })
    filename = "main.py"
  }

  source {
    content  = file("${path.module}/function_source/requirements.txt")
    filename = "requirements.txt"
  }

  depends_on = [
    google_storage_bucket.validation_results
  ]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "content-validator-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.validation_results.name
  source = data.archive_file.function_source.output_path

  depends_on = [
    data.archive_file.function_source
  ]
}

# Create Cloud Function for content validation
resource "google_cloudfunctions2_function" "content_validator" {
  name     = "content-validator-${local.resource_suffix}"
  project  = var.project_id
  location = var.region

  build_config {
    runtime     = var.function_runtime
    entry_point = "validate_content"
    
    source {
      storage_source {
        bucket = google_storage_bucket.validation_results.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = var.function_min_instances
    available_memory                 = var.function_memory
    timeout_seconds                  = var.function_timeout
    max_instance_request_concurrency = var.function_concurrency
    available_cpu                    = var.enable_function_cpu_boost ? "2" : "1"
    
    # Service account configuration
    service_account_email = google_service_account.function_sa.email

    # Environment variables for function configuration
    environment_variables = {
      GCP_PROJECT          = var.project_id
      FUNCTION_REGION      = var.vertex_ai_location
      RESULTS_BUCKET       = google_storage_bucket.validation_results.name
      GEMINI_MODEL         = var.gemini_model_name
      SAFETY_THRESHOLD     = var.safety_threshold
      LOG_LEVEL           = var.log_level
      ENVIRONMENT         = var.environment
    }

    # VPC connector configuration (if enabled)
    dynamic "vpc_connector" {
      for_each = var.enable_vpc_connector ? [1] : []
      content {
        name = var.vpc_connector_name
      }
    }

    # Ingress settings - restrict to internal and Cloud Load Balancing
    ingress_settings = "ALLOW_INTERNAL_AND_GCLB"
    
    # Security settings
    all_traffic_on_latest_revision = true
  }

  # Event trigger for Cloud Storage
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.storage.object.v1.finalized"
    retry_policy   = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.content_input.name
    }
    
    service_account_email = google_service_account.function_sa.email
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_project_iam_member.function_storage_admin,
    google_project_iam_member.function_aiplatform_user,
    google_project_iam_member.function_logging_writer,
    google_project_iam_member.function_monitoring_writer,
    google_project_iam_member.function_eventarc_receiver
  ]
}

# Create function IAM policy for allowed principals
resource "google_cloudfunctions2_function_iam_binding" "function_invoker" {
  count = length(var.allowed_principals) > 0 ? 1 : 0
  
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.content_validator.name
  role           = "roles/cloudfunctions.invoker"
  members        = var.allowed_principals
}

# Cloud Monitoring - Create alerting policy for function errors
resource "google_monitoring_alert_policy" "function_error_rate" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Content Validator Error Rate - ${local.resource_suffix}"
  project      = var.project_id
  
  conditions {
    display_name = "Function error rate too high"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.content_validator.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.1

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields    = ["resource.label.function_name"]
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  # Notification channels (if provided)
  dynamic "notification_channels" {
    for_each = var.monitoring_notification_channels
    content {
      notification_channels = [notification_channels.value]
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.content_validator
  ]
}

# Cloud Monitoring - Create alerting policy for function latency
resource "google_monitoring_alert_policy" "function_latency" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Content Validator High Latency - ${local.resource_suffix}"
  project      = var.project_id
  
  conditions {
    display_name = "Function execution time too high"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.content_validator.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 30000 # 30 seconds in milliseconds

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_PERCENTILE_95"
        group_by_fields      = ["resource.label.function_name"]
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  # Notification channels (if provided)
  dynamic "notification_channels" {
    for_each = var.monitoring_notification_channels
    content {
      notification_channels = [notification_channels.value]
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.content_validator
  ]
}

# Create a log sink for function logs (if enhanced logging is enabled)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_cloud_logging ? 1 : 0
  
  name        = "content-validator-logs-${local.resource_suffix}"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.validation_results.name}/logs"
  
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.content_validator.name}\""

  unique_writer_identity = true

  depends_on = [
    google_cloudfunctions2_function.content_validator
  ]
}

# Grant log writer permissions to the log sink service account
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_cloud_logging ? 1 : 0
  
  bucket = google_storage_bucket.validation_results.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity

  depends_on = [
    google_logging_project_sink.function_logs
  ]
}