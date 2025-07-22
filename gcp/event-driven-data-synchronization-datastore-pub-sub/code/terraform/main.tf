# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming
locals {
  resource_suffix = random_id.suffix.hex
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
  })
  
  # Resource names with unique suffixes
  topic_name              = "${var.resource_prefix}-${var.pubsub_topic_name}-${local.resource_suffix}"
  sync_subscription_name  = "${var.resource_prefix}-${var.sync_subscription_name}-${local.resource_suffix}"
  audit_subscription_name = "${var.resource_prefix}-${var.audit_subscription_name}-${local.resource_suffix}"
  dlq_topic_name         = "${var.resource_prefix}-${var.dlq_topic_name}-${local.resource_suffix}"
  dlq_subscription_name  = "${var.resource_prefix}-dlq-processor-${local.resource_suffix}"
  
  # Function names
  sync_function_name     = "${var.resource_prefix}-${var.sync_function_name}-${local.resource_suffix}"
  audit_function_name    = "${var.resource_prefix}-${var.audit_function_name}-${local.resource_suffix}"
  conflict_function_name = "${var.resource_prefix}-${var.conflict_function_name}-${local.resource_suffix}"
  
  # Service account name
  service_account_name = "${var.resource_prefix}-sa-${local.resource_suffix}"
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "datastore.googleapis.com",
    "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com"
  ])
  
  service            = each.value
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Initialize Datastore database
resource "google_datastore_database" "default" {
  location_id     = var.datastore_location
  type            = "DATASTORE_MODE"
  delete_protection_state = "DELETE_PROTECTION_DISABLED"
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = local.service_account_name
  display_name = "Service Account for Event-Driven Sync Functions"
  description  = "Service account for data synchronization Cloud Functions with minimal required permissions"
}

# IAM roles for the service account
resource "google_project_iam_member" "function_sa_roles" {
  for_each = toset([
    "roles/datastore.user",           # Read/write Datastore entities
    "roles/pubsub.publisher",         # Publish messages to Pub/Sub
    "roles/pubsub.subscriber",        # Subscribe to Pub/Sub messages
    "roles/logging.logWriter",        # Write to Cloud Logging
    "roles/monitoring.metricWriter",  # Write monitoring metrics
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Main Pub/Sub topic for data synchronization events
resource "google_pubsub_topic" "data_sync_events" {
  name = local.topic_name
  labels = local.common_labels
  
  # Configure message ordering if needed
  message_retention_duration = var.message_retention_duration
  
  depends_on = [google_project_service.required_apis]
}

# Dead letter queue topic (if enabled)
resource "google_pubsub_topic" "dead_letter_queue" {
  count = var.enable_dead_letter_queue ? 1 : 0
  
  name   = local.dlq_topic_name
  labels = local.common_labels
  
  message_retention_duration = var.dlq_retention_duration
  
  depends_on = [google_project_service.required_apis]
}

# Dead letter queue subscription
resource "google_pubsub_subscription" "dlq_subscription" {
  count = var.enable_dead_letter_queue ? 1 : 0
  
  name  = local.dlq_subscription_name
  topic = google_pubsub_topic.dead_letter_queue[0].name
  labels = local.common_labels
  
  ack_deadline_seconds       = 60
  message_retention_duration = var.dlq_retention_duration
  retain_acked_messages      = false
  
  expiration_policy {
    ttl = "300000s" # 30 days
  }
}

# Subscription for data synchronization processing
resource "google_pubsub_subscription" "sync_subscription" {
  name  = local.sync_subscription_name
  topic = google_pubsub_topic.data_sync_events.name
  labels = local.common_labels
  
  ack_deadline_seconds       = var.ack_deadline_seconds
  message_retention_duration = var.message_retention_duration
  retain_acked_messages      = false
  
  # Configure dead letter policy if enabled
  dynamic "dead_letter_policy" {
    for_each = var.enable_dead_letter_queue ? [1] : []
    content {
      dead_letter_topic     = google_pubsub_topic.dead_letter_queue[0].id
      max_delivery_attempts = var.max_delivery_attempts
    }
  }
  
  # Configure retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  expiration_policy {
    ttl = "300000s" # 30 days
  }
  
  depends_on = [google_project_service.required_apis]
}

# Subscription for audit logging
resource "google_pubsub_subscription" "audit_subscription" {
  name  = local.audit_subscription_name
  topic = google_pubsub_topic.data_sync_events.name
  labels = local.common_labels
  
  ack_deadline_seconds       = var.audit_ack_deadline_seconds
  message_retention_duration = var.audit_retention_duration
  retain_acked_messages      = false
  
  # Configure dead letter policy if enabled
  dynamic "dead_letter_policy" {
    for_each = var.enable_dead_letter_queue ? [1] : []
    content {
      dead_letter_topic     = google_pubsub_topic.dead_letter_queue[0].id
      max_delivery_attempts = var.max_delivery_attempts
    }
  }
  
  # Configure retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
  
  expiration_policy {
    ttl = "300000s" # 30 days
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name          = "${var.project_id}-function-source-${local.resource_suffix}"
  location      = var.region
  force_destroy = true
  
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
}

# Create sync function source code archive
data "archive_file" "sync_function_source" {
  type        = "zip"
  output_path = "${path.module}/sync_function.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/sync_processor.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_templates/sync_requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload sync function source to Storage
resource "google_storage_bucket_object" "sync_function_source" {
  name   = "sync_function_${data.archive_file.sync_function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.sync_function_source.output_path
  
  depends_on = [data.archive_file.sync_function_source]
}

# Create audit function source code archive
data "archive_file" "audit_function_source" {
  type        = "zip"
  output_path = "${path.module}/audit_function.zip"
  
  source {
    content = file("${path.module}/function_templates/audit_logger.py")
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_templates/audit_requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload audit function source to Storage
resource "google_storage_bucket_object" "audit_function_source" {
  name   = "audit_function_${data.archive_file.audit_function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.audit_function_source.output_path
  
  depends_on = [data.archive_file.audit_function_source]
}

# Data Synchronization Cloud Function
resource "google_cloudfunctions_function" "sync_processor" {
  name        = local.sync_function_name
  description = "Process data synchronization events with conflict resolution"
  runtime     = var.function_runtime
  region      = var.region
  
  available_memory_mb   = var.sync_function_memory
  timeout              = var.function_timeout
  max_instances        = var.max_instances
  entry_point          = "sync_processor"
  service_account_email = google_service_account.function_sa.email
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.sync_function_source.name
  
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.data_sync_events.name
  }
  
  environment_variables = {
    PROJECT_ID    = var.project_id
    REGION        = var.region
    DATASTORE_DB  = google_datastore_database.default.name
    ENABLE_LOGGING = var.enable_audit_logging
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_sa_roles
  ]
}

# Audit Logging Cloud Function
resource "google_cloudfunctions_function" "audit_logger" {
  name        = local.audit_function_name
  description = "Log all synchronization events for audit and compliance"
  runtime     = var.function_runtime
  region      = var.region
  
  available_memory_mb   = var.audit_function_memory
  timeout              = var.audit_function_timeout
  max_instances        = var.audit_max_instances
  entry_point          = "audit_logger_func"
  service_account_email = google_service_account.function_sa.email
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.audit_function_source.name
  
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.data_sync_events.name
  }
  
  environment_variables = {
    PROJECT_ID = var.project_id
    REGION     = var.region
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_sa_roles
  ]
}

# External sync topics (optional)
resource "google_pubsub_topic" "external_sync_topics" {
  for_each = var.enable_external_sync ? toset(["create", "update", "delete"]) : toset([])
  
  name   = "${var.resource_prefix}-external-sync-${each.value}-${local.resource_suffix}"
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Log sink for comprehensive audit logging
resource "google_logging_project_sink" "audit_sink" {
  count = var.enable_audit_logging ? 1 : 0
  
  name        = "${var.resource_prefix}-audit-sink-${local.resource_suffix}"
  description = "Audit log sink for data synchronization system"
  
  destination = "pubsub.googleapis.com/projects/${var.project_id}/topics/${google_pubsub_topic.data_sync_events.name}"
  
  filter = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name=~"${var.resource_prefix}-.*-${local.resource_suffix}"
    severity>=INFO
  EOT
  
  unique_writer_identity = true
}

# Grant log sink permission to publish to Pub/Sub
resource "google_pubsub_topic_iam_member" "audit_sink_publisher" {
  count = var.enable_audit_logging ? 1 : 0
  
  topic  = google_pubsub_topic.data_sync_events.name
  role   = "roles/pubsub.publisher"
  member = google_logging_project_sink.audit_sink[0].writer_identity
}

# Create monitoring dashboard
resource "google_monitoring_dashboard" "sync_dashboard" {
  count = var.create_monitoring_dashboard ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = var.dashboard_display_name
    mosaicLayout = {
      tiles = [
        {
          width = 6
          height = 4
          widget = {
            title = "Pub/Sub Message Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"pubsub_topic\" AND resource.labels.topic_id=\"${google_pubsub_topic.data_sync_events.name}\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          widget = {
            title = "Function Execution Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=~\"${var.resource_prefix}-.*-${local.resource_suffix}\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width = 6
          height = 4
          yPos = 4
          widget = {
            title = "Function Execution Time"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_time\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          yPos = 4
          widget = {
            title = "Datastore Operations"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"datastore_database\" AND metric.type=\"datastore.googleapis.com/api/request_count\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}

# Notification channel for alerts (if email provided)
resource "google_monitoring_notification_channel" "email" {
  count = var.notification_email != null ? 1 : 0
  
  display_name = "Email Notifications"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
}

# Alert policy for function failures
resource "google_monitoring_alert_policy" "function_failure_alert" {
  count = var.notification_email != null ? 1 : 0
  
  display_name = "Function Failure Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Function execution failures"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=~\"${var.resource_prefix}-.*-${local.resource_suffix}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\" AND metric.labels.status!=\"ok\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email[0].id]
  
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
}

# Alert policy for high message age
resource "google_monitoring_alert_policy" "message_age_alert" {
  count = var.notification_email != null ? 1 : 0
  
  display_name = "High Message Age Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Messages aging in subscription"
    
    condition_threshold {
      filter         = "resource.type=\"pubsub_subscription\" AND resource.labels.subscription_id=~\"${var.resource_prefix}-.*-${local.resource_suffix}\" AND metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 300 # 5 minutes
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email[0].id]
  
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
}