# Multi-Language Content Localization with Cloud Translation and Scheduler
# This configuration creates a complete automated content localization pipeline
# using Cloud Translation API, Cloud Scheduler, Cloud Storage, Pub/Sub, and Cloud Functions

# Random ID for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent naming and configuration
locals {
  resource_suffix     = random_id.suffix.hex
  source_bucket_name  = "${var.project_id}-source-content-${local.resource_suffix}"
  target_bucket_name  = "${var.project_id}-translated-content-${local.resource_suffix}"
  function_name       = "translation-processor-${local.resource_suffix}"
  topic_name          = "translation-workflow-${local.resource_suffix}"
  scheduler_job_name  = "batch-translation-${local.resource_suffix}"
  
  # Target languages for translation
  target_languages = ["es", "fr", "de", "it", "pt", "ja", "zh"]
  
  # Common labels for all resources
  common_labels = {
    environment = var.environment
    project     = "content-localization"
    managed_by  = "terraform"
  }
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "translate.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com"
  ])

  service = each.value

  # Don't disable services when destroying
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Service account for the translation pipeline
resource "google_service_account" "translation_pipeline" {
  account_id   = "translation-pipeline-${local.resource_suffix}"
  display_name = "Translation Pipeline Service Account"
  description  = "Service account for automated content localization pipeline"

  depends_on = [google_project_service.required_apis]
}

# IAM roles for the translation pipeline service account
resource "google_project_iam_member" "translation_permissions" {
  for_each = toset([
    "roles/translate.user",
    "roles/storage.objectAdmin",
    "roles/pubsub.editor",
    "roles/cloudfunctions.invoker",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/secretmanager.secretAccessor"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.translation_pipeline.email}"
}

# Source content bucket for original documents
resource "google_storage_bucket" "source_content" {
  name          = local.source_bucket_name
  location      = var.region
  force_destroy = var.force_destroy

  # Security configurations
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }

  # Versioning for content tracking
  versioning {
    enabled = true
  }

  # Labels for resource management
  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Translated content bucket with language-specific folders
resource "google_storage_bucket" "translated_content" {
  name          = local.target_bucket_name
  location      = var.region
  force_destroy = var.force_destroy

  # Security configurations
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 180
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  # Versioning for translation history
  versioning {
    enabled = true
  }

  # CORS configuration for web access
  cors {
    origin          = ["*"]
    method          = ["GET"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub topic for translation workflow events
resource "google_pubsub_topic" "translation_workflow" {
  name = local.topic_name

  # Message retention for processing delays
  message_retention_duration = "604800s" # 7 days

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for the Cloud Function
resource "google_pubsub_subscription" "translation_processor" {
  name  = "${local.topic_name}-subscription"
  topic = google_pubsub_topic.translation_workflow.name

  # Acknowledgment deadline for processing
  ack_deadline_seconds = 600

  # Dead letter queue for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.translation_dlq.id
    max_delivery_attempts = 5
  }

  # Retry policy configuration
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }

  # Message ordering for consistency
  enable_message_ordering = false

  labels = local.common_labels
}

# Dead letter queue for failed translation requests
resource "google_pubsub_topic" "translation_dlq" {
  name = "${local.topic_name}-dlq"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name          = "${var.project_id}-function-source-${local.resource_suffix}"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create the Cloud Function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/translation-function-${local.resource_suffix}.zip"
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      target_languages = jsonencode(local.target_languages)
      source_bucket    = google_storage_bucket.source_content.name
      target_bucket    = google_storage_bucket.translated_content.name
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload Cloud Function source code
resource "google_storage_bucket_object" "function_source" {
  name   = "translation-function-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# Cloud Function for processing translation requests
resource "google_cloudfunctions2_function" "translation_processor" {
  name        = local.function_name
  location    = var.region
  description = "Processes content translation requests using Cloud Translation API"

  build_config {
    runtime     = "python311"
    entry_point = "translate_document"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = var.function_min_instances
    available_memory                 = "512M"
    timeout_seconds                  = 540
    max_instance_request_concurrency = 10
    available_cpu                    = "1"
    service_account_email            = google_service_account.translation_pipeline.email

    # Environment variables for function configuration
    environment_variables = {
      PROJECT_ID      = var.project_id
      SOURCE_BUCKET   = google_storage_bucket.source_content.name
      TARGET_BUCKET   = google_storage_bucket.translated_content.name
      TARGET_LANGUAGES = jsonencode(local.target_languages)
      LOG_LEVEL       = var.log_level
    }

    # VPC configuration for enhanced security
    dynamic "vpc_connector" {
      for_each = var.vpc_connector != null ? [1] : []
      content {
        name = var.vpc_connector
      }
    }
  }

  # Event trigger for Pub/Sub messages
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.translation_workflow.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.translation_permissions
  ]
}

# Storage notification for automatic processing
resource "google_storage_notification" "translation_trigger" {
  bucket         = google_storage_bucket.source_content.name
  topic          = google_pubsub_topic.translation_workflow.id
  event_types    = ["OBJECT_FINALIZE"]
  payload_format = "JSON_API_V1"

  # Filter for specific file types
  object_name_prefix = var.source_file_prefix

  depends_on = [
    google_pubsub_topic_iam_member.storage_notification_publisher
  ]
}

# IAM permission for Cloud Storage to publish to Pub/Sub
resource "google_pubsub_topic_iam_member" "storage_notification_publisher" {
  topic  = google_pubsub_topic.translation_workflow.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
}

# Data source for current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Cloud Scheduler job for batch processing
resource "google_cloud_scheduler_job" "batch_translation" {
  name             = local.scheduler_job_name
  description      = "Scheduled batch translation processing job"
  schedule         = var.batch_schedule
  time_zone        = var.time_zone
  attempt_deadline = "600s"

  pubsub_target {
    topic_name = google_pubsub_topic.translation_workflow.id
    data = base64encode(jsonencode({
      type           = "batch"
      action         = "process_pending"
      source_bucket  = google_storage_bucket.source_content.name
      target_bucket  = google_storage_bucket.translated_content.name
      target_languages = local.target_languages
    }))
  }

  retry_config {
    retry_count          = 3
    max_retry_duration   = "300s"
    min_backoff_duration = "5s"
    max_backoff_duration = "60s"
  }

  depends_on = [google_project_service.required_apis]
}

# Health monitoring scheduler job
resource "google_cloud_scheduler_job" "health_monitor" {
  name             = "${local.scheduler_job_name}-monitor"
  description      = "Translation pipeline health monitoring job"
  schedule         = "*/30 * * * *" # Every 30 minutes
  time_zone        = var.time_zone
  attempt_deadline = "180s"

  pubsub_target {
    topic_name = google_pubsub_topic.translation_workflow.id
    data = base64encode(jsonencode({
      type   = "monitor"
      action = "health_check"
    }))
  }

  retry_config {
    retry_count          = 2
    max_retry_duration   = "120s"
    min_backoff_duration = "10s"
    max_backoff_duration = "30s"
  }

  depends_on = [google_project_service.required_apis]
}

# Logging sink for translation workflow audit trail
resource "google_logging_project_sink" "translation_audit" {
  name        = "translation-audit-${local.resource_suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.translated_content.name}/logs"
  
  # Filter for translation-related logs
  filter = <<-EOT
    (resource.type="cloud_function" AND resource.labels.function_name="${local.function_name}") OR
    (resource.type="pubsub_topic" AND resource.labels.topic_id="${local.topic_name}") OR
    (resource.type="cloud_scheduler_job" AND (
      resource.labels.job_id="${local.scheduler_job_name}" OR
      resource.labels.job_id="${local.scheduler_job_name}-monitor"
    ))
  EOT

  unique_writer_identity = true

  depends_on = [google_project_service.required_apis]
}

# Grant write permissions to the logging sink
resource "google_storage_bucket_iam_member" "logging_sink_writer" {
  bucket = google_storage_bucket.translated_content.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.translation_audit.writer_identity
}

# Monitoring dashboard for translation pipeline (optional)
resource "google_monitoring_dashboard" "translation_pipeline" {
  count          = var.enable_monitoring_dashboard ? 1 : 0
  dashboard_json = templatefile("${path.module}/monitoring_dashboard.json", {
    project_id    = var.project_id
    function_name = local.function_name
    topic_name    = local.topic_name
  })

  depends_on = [google_project_service.required_apis]
}