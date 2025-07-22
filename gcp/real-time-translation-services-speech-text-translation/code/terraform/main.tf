# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming
locals {
  resource_suffix = random_id.suffix.hex
  common_labels = merge(var.labels, {
    environment = var.environment
    terraform   = "true"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "speech.googleapis.com",
    "translate.googleapis.com",
    "run.googleapis.com",
    "firestore.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent accidental deletion of APIs
  disable_dependent_services = false
  disable_on_destroy         = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service account for translation services
resource "google_service_account" "translation_service" {
  account_id   = "${var.service_account_name}-${local.resource_suffix}"
  display_name = "Real-time Translation Service"
  description  = "Service account for speech recognition and translation APIs"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM roles for the translation service account
resource "google_project_iam_member" "translation_service_roles" {
  for_each = toset([
    "roles/speech.client",
    "roles/translate.user",
    "roles/datastore.user",
    "roles/pubsub.publisher",
    "roles/storage.objectCreator",
    "roles/storage.objectViewer",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.translation_service.email}"

  depends_on = [google_service_account.translation_service]
}

# Create Firestore database for conversation storage
resource "google_firestore_database" "translation_conversations" {
  project                           = var.project_id
  name                             = "(default)"
  location_id                      = var.firestore_location
  type                             = "FIRESTORE_NATIVE"
  concurrency_mode                 = "OPTIMISTIC"
  app_engine_integration_mode      = "DISABLED"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  delete_protection_state          = "DELETE_PROTECTION_ENABLED"

  depends_on = [google_project_service.required_apis]
}

# Create Firestore index for conversation queries
resource "google_firestore_field" "conversation_index" {
  project    = var.project_id
  database   = google_firestore_database.translation_conversations.name
  collection = "conversations"
  field      = "userId"

  index_config {
    indexes {
      fields {
        field_path = "userId"
        order      = "ASCENDING"
      }
      fields {
        field_path = "timestamp"
        order      = "DESCENDING"
      }
      query_scope = "COLLECTION"
    }
  }

  depends_on = [google_firestore_database.translation_conversations]
}

# Create Cloud Storage bucket for audio files
resource "google_storage_bucket" "audio_files" {
  name                        = "${var.project_id}-audio-files-${local.resource_suffix}"
  location                    = var.region
  project                     = var.project_id
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  force_destroy               = true # For development environments

  # Enable versioning for data protection
  versioning {
    enabled = true
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.audio_retention_days
    }
    action {
      type = "Delete"
    }
  }

  # Lifecycle rule for versioned objects
  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 7
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# IAM binding for service account to access storage bucket
resource "google_storage_bucket_iam_member" "audio_files_access" {
  bucket = google_storage_bucket.audio_files.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.translation_service.email}"

  depends_on = [google_storage_bucket.audio_files]
}

# Create Pub/Sub topic for translation events
resource "google_pubsub_topic" "translation_events" {
  name    = "translation-events-${local.resource_suffix}"
  project = var.project_id

  # Enable message ordering for better event sequencing
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for translation event processing
resource "google_pubsub_subscription" "translation_processor" {
  name    = "translation-processor-${local.resource_suffix}"
  topic   = google_pubsub_topic.translation_events.name
  project = var.project_id

  # Configure message retention
  message_retention_duration = var.message_retention_duration

  # Configure acknowledgment deadline
  ack_deadline_seconds = 20

  # Configure retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Configure dead letter policy
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.translation_dlq.id
    max_delivery_attempts = 5
  }

  labels = local.common_labels

  depends_on = [google_pubsub_topic.translation_events]
}

# Create dead letter topic for failed message processing
resource "google_pubsub_topic" "translation_dlq" {
  name    = "translation-dlq-${local.resource_suffix}"
  project = var.project_id

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }

  labels = merge(local.common_labels, {
    purpose = "dead-letter-queue"
  })

  depends_on = [google_project_service.required_apis]
}

# Create Cloud Run service for real-time translation
resource "google_cloud_run_v2_service" "translation_service" {
  name     = "${var.service_name}-${local.resource_suffix}"
  location = var.region
  project  = var.project_id

  template {
    # Service account configuration
    service_account = google_service_account.translation_service.email

    # Container configuration
    containers {
      image = "gcr.io/cloudrun/hello" # Placeholder image - will be replaced during deployment

      # Resource limits
      resources {
        limits = {
          cpu    = var.cpu_limit
          memory = var.memory_limit
        }
      }

      # Environment variables
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }

      env {
        name  = "FIRESTORE_DATABASE"
        value = google_firestore_database.translation_conversations.name
      }

      env {
        name  = "PUBSUB_TOPIC"
        value = google_pubsub_topic.translation_events.name
      }

      env {
        name  = "STORAGE_BUCKET"
        value = google_storage_bucket.audio_files.name
      }

      env {
        name  = "DEFAULT_SOURCE_LANGUAGE"
        value = var.default_source_language
      }

      env {
        name  = "DEFAULT_TARGET_LANGUAGES"
        value = join(",", var.default_target_languages)
      }

      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }

      # Health check port
      ports {
        container_port = 8080
      }

      # Startup probe
      startup_probe {
        http_get {
          path = "/health"
        }
        initial_delay_seconds = 10
        timeout_seconds       = 3
        period_seconds        = 3
        failure_threshold     = 3
      }

      # Liveness probe
      liveness_probe {
        http_get {
          path = "/health"
        }
        initial_delay_seconds = 30
        timeout_seconds       = 3
        period_seconds        = 30
        failure_threshold     = 3
      }
    }

    # Scaling configuration
    scaling {
      min_instance_count = 0
      max_instance_count = var.max_instances
    }

    # Performance settings
    max_instance_request_concurrency = var.concurrency_limit
    timeout                         = "${var.timeout_seconds}s"

    # Annotations for additional configuration
    annotations = {
      "autoscaling.knative.dev/maxScale"         = tostring(var.max_instances)
      "run.googleapis.com/execution-environment" = "gen2"
      "run.googleapis.com/cpu-throttling"        = "false"
    }

    labels = local.common_labels
  }

  # Traffic configuration
  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  depends_on = [
    google_service_account.translation_service,
    google_project_iam_member.translation_service_roles,
    google_firestore_database.translation_conversations,
    google_storage_bucket.audio_files,
    google_pubsub_topic.translation_events
  ]

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image
    ]
  }
}

# IAM policy for Cloud Run service (allow public access if configured)
resource "google_cloud_run_service_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = google_cloud_run_v2_service.translation_service.location
  service  = google_cloud_run_v2_service.translation_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [google_cloud_run_v2_service.translation_service]
}

# Create monitoring notification channel (optional)
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "Translation Service Email Notifications"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = "admin@${var.project_id}.com" # Update with actual email
  }

  depends_on = [google_project_service.required_apis]
}

# Create uptime check for Cloud Run service
resource "google_monitoring_uptime_check_config" "translation_service_check" {
  count = var.enable_monitoring ? 1 : 0

  display_name     = "Translation Service Health Check"
  timeout          = "10s"
  period           = "60s"
  project          = var.project_id
  selected_regions = ["USA"]

  http_check {
    port         = 443
    use_ssl      = true
    path         = "/health"
    request_method = "GET"
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = replace(google_cloud_run_v2_service.translation_service.uri, "https://", "")
    }
  }

  depends_on = [google_cloud_run_v2_service.translation_service]
}

# Create alert policy for service health
resource "google_monitoring_alert_policy" "translation_service_down" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "Translation Service Down"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Uptime check failed"

    condition_threshold {
      filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\""
      duration        = "300s"
      comparison      = "COMPARISON_LESS_THAN"
      threshold_value = 1

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_FRACTION_TRUE"
      }
    }
  }

  dynamic "notification_channels" {
    for_each = var.enable_monitoring ? google_monitoring_notification_channel.email : []
    content {
      notification_channels = [notification_channels.value.id]
    }
  }

  depends_on = [google_monitoring_uptime_check_config.translation_service_check]
}

# Create log-based metric for error tracking
resource "google_logging_metric" "translation_errors" {
  name    = "translation_service_errors"
  project = var.project_id

  filter = <<-EOT
    resource.type="cloud_run_revision"
    resource.labels.service_name="${google_cloud_run_v2_service.translation_service.name}"
    severity>=ERROR
  EOT

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    display_name = "Translation Service Errors"
  }

  depends_on = [google_cloud_run_v2_service.translation_service]
}

# Create audit logging configuration
resource "google_project_iam_audit_config" "translation_audit" {
  count = var.enable_audit_logs ? 1 : 0

  project = var.project_id
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}