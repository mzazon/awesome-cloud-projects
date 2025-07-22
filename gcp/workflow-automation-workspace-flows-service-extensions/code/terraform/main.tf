# Main Terraform Configuration for Workflow Automation with Google Workspace Flows
# This file defines the complete infrastructure for intelligent document processing workflows

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common resource naming
  resource_suffix = random_id.suffix.hex
  function_name   = "${var.resource_name_prefix}-processor-${local.resource_suffix}"
  topic_name      = "${var.resource_name_prefix}-events-${local.resource_suffix}"
  subscription_name = "${var.resource_name_prefix}-processing-sub-${local.resource_suffix}"
  bucket_name     = "${var.resource_name_prefix}-docs-${local.resource_suffix}"
  
  # Merge default and user-provided labels
  common_labels = merge(var.labels, {
    environment = var.environment
    suffix      = local.resource_suffix
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset(var.enable_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling services on destroy to avoid dependency issues
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create service account for Cloud Functions and workflow operations
resource "google_service_account" "workflow_service_account" {
  account_id   = "${var.resource_name_prefix}-sa-${local.resource_suffix}"
  display_name = "Workflow Automation Service Account"
  description  = "Service account for workflow automation functions and services"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Assign IAM roles to the service account
resource "google_project_iam_member" "service_account_roles" {
  for_each = toset(var.service_account_roles)
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.workflow_service_account.email}"
  
  depends_on = [google_service_account.workflow_service_account]
}

# Create Cloud Storage bucket for document processing
resource "google_storage_bucket" "workflow_documents" {
  name          = local.bucket_name
  project       = var.project_id
  location      = var.storage_bucket_location
  storage_class = var.storage_bucket_class
  
  # Enable versioning for document protection
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Configure uniform bucket-level access
  uniform_bucket_level_access = true
  
  # Apply labels
  labels = local.common_labels
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false
  }
  
  depends_on = [google_project_service.required_apis]
}

# Grant storage permissions to service account
resource "google_storage_bucket_iam_member" "workflow_bucket_access" {
  bucket = google_storage_bucket.workflow_documents.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.workflow_service_account.email}"
  
  depends_on = [google_storage_bucket.workflow_documents]
}

# Create Pub/Sub topic for document events
resource "google_pubsub_topic" "document_events" {
  name    = local.topic_name
  project = var.project_id
  
  labels = local.common_labels
  
  # Configure message storage policy
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create dead letter topic for failed processing
resource "google_pubsub_topic" "dead_letter" {
  count = var.enable_dead_letter ? 1 : 0
  
  name    = "${local.topic_name}-deadletter"
  project = var.project_id
  
  labels = merge(local.common_labels, {
    purpose = "dead-letter"
  })
  
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create subscription for Cloud Functions processing
resource "google_pubsub_subscription" "document_processing" {
  name    = local.subscription_name
  project = var.project_id
  topic   = google_pubsub_topic.document_events.name
  
  # Configure acknowledgment deadline
  ack_deadline_seconds = var.pubsub_ack_deadline_seconds
  
  # Configure message retention
  message_retention_duration = var.pubsub_message_retention_duration
  
  # Configure dead letter policy if enabled
  dynamic "dead_letter_policy" {
    for_each = var.enable_dead_letter ? [1] : []
    content {
      dead_letter_topic     = google_pubsub_topic.dead_letter[0].id
      max_delivery_attempts = var.max_delivery_attempts
    }
  }
  
  # Configure retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  labels = local.common_labels
  
  depends_on = [google_pubsub_topic.document_events]
}

# Create dead letter subscription if enabled
resource "google_pubsub_subscription" "dead_letter_subscription" {
  count = var.enable_dead_letter ? 1 : 0
  
  name    = "${local.subscription_name}-deadletter"
  project = var.project_id
  topic   = google_pubsub_topic.dead_letter[0].name
  
  ack_deadline_seconds       = 60
  message_retention_duration = "604800s" # 7 days
  
  labels = merge(local.common_labels, {
    purpose = "dead-letter"
  })
  
  depends_on = [google_pubsub_topic.dead_letter]
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name          = "${local.bucket_name}-functions"
  project       = var.project_id
  location      = var.region
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  
  labels = merge(local.common_labels, {
    purpose = "function-source"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create source code archives for Cloud Functions
data "archive_file" "document_processor_source" {
  type        = "zip"
  output_path = "${path.module}/document_processor.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/document_processor.js", {
      topic_name   = local.topic_name
      bucket_name  = local.bucket_name
      project_id   = var.project_id
    })
    filename = "index.js"
  }
  
  source {
    content = jsonencode({
      name = "document-processor"
      version = "1.0.0"
      dependencies = {
        "@google-cloud/functions-framework" = "^3.0.0"
        "@google-cloud/pubsub" = "^4.0.0"
        "@google-cloud/storage" = "^7.0.0"
        "googleapis" = "^126.0.0"
      }
    })
    filename = "package.json"
  }
}

data "archive_file" "approval_webhook_source" {
  type        = "zip"
  output_path = "${path.module}/approval_webhook.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/approval_webhook.js", {
      topic_name = local.topic_name
      project_id = var.project_id
    })
    filename = "index.js"
  }
  
  source {
    content = jsonencode({
      name = "approval-webhook"
      version = "1.0.0"
      dependencies = {
        "@google-cloud/functions-framework" = "^3.0.0"
        "@google-cloud/pubsub" = "^4.0.0"
        "googleapis" = "^126.0.0"
      }
    })
    filename = "package.json"
  }
}

data "archive_file" "chat_notifications_source" {
  type        = "zip"
  output_path = "${path.module}/chat_notifications.zip"
  
  source {
    content = file("${path.module}/function_templates/chat_notifications.js")
    filename = "index.js"
  }
  
  source {
    content = jsonencode({
      name = "chat-notifications"
      version = "1.0.0"
      dependencies = {
        "@google-cloud/functions-framework" = "^3.0.0"
        "googleapis" = "^126.0.0"
      }
    })
    filename = "package.json"
  }
}

data "archive_file" "analytics_collector_source" {
  type        = "zip"
  output_path = "${path.module}/analytics_collector.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/analytics_collector.js", {
      project_id = var.project_id
    })
    filename = "index.js"
  }
  
  source {
    content = jsonencode({
      name = "workflow-analytics"
      version = "1.0.0"
      dependencies = {
        "@google-cloud/functions-framework" = "^3.0.0"
        "@google-cloud/monitoring" = "^3.0.0"
        "@google-cloud/pubsub" = "^4.0.0"
      }
    })
    filename = "package.json"
  }
}

# Upload function source code to storage
resource "google_storage_bucket_object" "document_processor_source" {
  name   = "document_processor_${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.document_processor_source.output_path
  
  depends_on = [data.archive_file.document_processor_source]
}

resource "google_storage_bucket_object" "approval_webhook_source" {
  name   = "approval_webhook_${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.approval_webhook_source.output_path
  
  depends_on = [data.archive_file.approval_webhook_source]
}

resource "google_storage_bucket_object" "chat_notifications_source" {
  name   = "chat_notifications_${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.chat_notifications_source.output_path
  
  depends_on = [data.archive_file.chat_notifications_source]
}

resource "google_storage_bucket_object" "analytics_collector_source" {
  name   = "analytics_collector_${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.analytics_collector_source.output_path
  
  depends_on = [data.archive_file.analytics_collector_source]
}

# Deploy document processing Cloud Function
resource "google_cloudfunctions_function" "document_processor" {
  name        = local.function_name
  project     = var.project_id
  region      = var.region
  description = "Processes documents and initiates workflow automation"
  
  runtime     = "nodejs20"
  entry_point = "processDocument"
  
  available_memory_mb = var.function_memory
  timeout             = var.function_timeout
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.document_processor_source.name
  
  service_account_email = google_service_account.workflow_service_account.email
  
  environment_variables = {
    TOPIC_NAME   = local.topic_name
    BUCKET_NAME  = local.bucket_name
    PROJECT_ID   = var.project_id
    ENVIRONMENT  = var.environment
  }
  
  trigger {
    https_trigger {}
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.document_processor_source,
    google_project_iam_member.service_account_roles
  ]
}

# Deploy approval webhook Cloud Function
resource "google_cloudfunctions_function" "approval_webhook" {
  name        = "approval-webhook-${local.resource_suffix}"
  project     = var.project_id
  region      = var.region
  description = "Handles approval decisions and workflow state updates"
  
  runtime     = "nodejs20"
  entry_point = "handleApproval"
  
  available_memory_mb = 256
  timeout             = 300
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.approval_webhook_source.name
  
  service_account_email = google_service_account.workflow_service_account.email
  
  environment_variables = {
    TOPIC_NAME  = local.topic_name
    PROJECT_ID  = var.project_id
    ENVIRONMENT = var.environment
  }
  
  trigger {
    https_trigger {}
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.approval_webhook_source,
    google_project_iam_member.service_account_roles
  ]
}

# Deploy chat notifications Cloud Function
resource "google_cloudfunctions_function" "chat_notifications" {
  name        = "chat-notifications-${local.resource_suffix}"
  project     = var.project_id
  region      = var.region
  description = "Sends real-time notifications via Google Chat"
  
  runtime     = "nodejs20"
  entry_point = "sendChatNotification"
  
  available_memory_mb = 256
  timeout             = 180
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.chat_notifications_source.name
  
  service_account_email = google_service_account.workflow_service_account.email
  
  environment_variables = {
    PROJECT_ID  = var.project_id
    ENVIRONMENT = var.environment
  }
  
  trigger {
    https_trigger {}
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.chat_notifications_source,
    google_project_iam_member.service_account_roles
  ]
}

# Deploy analytics collector Cloud Function with Pub/Sub trigger
resource "google_cloudfunctions_function" "analytics_collector" {
  name        = "analytics-collector-${local.resource_suffix}"
  project     = var.project_id
  region      = var.region
  description = "Collects workflow analytics and custom metrics"
  
  runtime     = "nodejs20"
  entry_point = "collectAnalytics"
  
  available_memory_mb = 256
  timeout             = 180
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.analytics_collector_source.name
  
  service_account_email = google_service_account.workflow_service_account.email
  
  environment_variables = {
    GCP_PROJECT = var.project_id
    ENVIRONMENT = var.environment
  }
  
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.document_events.name
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.analytics_collector_source,
    google_project_iam_member.service_account_roles,
    google_pubsub_topic.document_events
  ]
}

# Grant public access to HTTP-triggered functions (configurable)
resource "google_cloudfunctions_function_iam_member" "document_processor_invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.document_processor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
  
  depends_on = [google_cloudfunctions_function.document_processor]
}

resource "google_cloudfunctions_function_iam_member" "approval_webhook_invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.approval_webhook.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
  
  depends_on = [google_cloudfunctions_function.approval_webhook]
}

resource "google_cloudfunctions_function_iam_member" "chat_notifications_invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.chat_notifications.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
  
  depends_on = [google_cloudfunctions_function.chat_notifications]
}

# Create monitoring dashboard configuration (optional)
resource "google_monitoring_dashboard" "workflow_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Intelligent Workflow Analytics"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Document Processing Volume"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""
                    aggregation = {
                      alignmentPeriod    = "300s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Pub/Sub Message Processing"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"pubsub_topic\" AND resource.labels.topic_id=\"${local.topic_name}\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }]
            }
          }
        }
      ]
    }
  })
  
  project = var.project_id
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.document_processor,
    google_pubsub_topic.document_events
  ]
}

# Create log sink for workflow analytics (optional)
resource "google_logging_project_sink" "workflow_logs" {
  count = var.enable_logging ? 1 : 0
  
  name        = "workflow-logs-${local.resource_suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.workflow_documents.name}"
  
  filter = "resource.type=\"cloud_function\" AND (resource.labels.function_name=\"${local.function_name}\" OR resource.labels.function_name=\"approval-webhook-${local.resource_suffix}\" OR resource.labels.function_name=\"chat-notifications-${local.resource_suffix}\" OR resource.labels.function_name=\"analytics-collector-${local.resource_suffix}\")"
  
  unique_writer_identity = true
  
  depends_on = [
    google_cloudfunctions_function.document_processor,
    google_cloudfunctions_function.approval_webhook,
    google_cloudfunctions_function.chat_notifications,
    google_cloudfunctions_function.analytics_collector
  ]
}

# Grant log sink write access to storage bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  count = var.enable_logging ? 1 : 0
  
  bucket = google_storage_bucket.workflow_documents.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.workflow_logs[0].writer_identity
  
  depends_on = [google_logging_project_sink.workflow_logs]
}