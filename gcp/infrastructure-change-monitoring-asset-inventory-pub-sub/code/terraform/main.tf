# ==============================================================================
# Infrastructure Change Monitoring with Cloud Asset Inventory and Pub/Sub
# ==============================================================================
# This Terraform configuration creates a comprehensive infrastructure change 
# monitoring solution using Google Cloud Asset Inventory, Pub/Sub messaging,
# Cloud Functions for event processing, and BigQuery for audit data storage.

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming and configuration
locals {
  # Generate unique resource names to avoid conflicts
  topic_name        = "infrastructure-changes-${random_id.suffix.hex}"
  subscription_name = "infrastructure-changes-sub-${random_id.suffix.hex}"
  function_name     = "process-asset-changes-${random_id.suffix.hex}"
  dataset_name      = "infrastructure_audit_${random_id.suffix.hex}"
  feed_name         = "infrastructure-feed-${random_id.suffix.hex}"
  bucket_name       = "asset-change-functions-${random_id.suffix.hex}"
  
  # Common tags for resource organization and cost tracking
  common_labels = {
    project     = "infrastructure-monitoring"
    environment = var.environment
    managed_by  = "terraform"
    component   = "asset-monitoring"
  }
}

# ==============================================================================
# Data Sources
# ==============================================================================

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Get current client configuration
data "google_client_config" "current" {}

# ==============================================================================
# Pub/Sub Resources for Event Messaging
# ==============================================================================

# Pub/Sub topic for receiving asset change notifications
resource "google_pubsub_topic" "asset_changes" {
  name    = local.topic_name
  project = var.project_id
  
  labels = local.common_labels
  
  # Configure message retention for compliance requirements
  message_retention_duration = "86400s" # 24 hours
  
  # Enable message ordering for consistent processing
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

# Pub/Sub subscription for Cloud Functions processing
resource "google_pubsub_subscription" "asset_changes" {
  name    = local.subscription_name
  topic   = google_pubsub_topic.asset_changes.name
  project = var.project_id
  
  labels = local.common_labels
  
  # Configure acknowledgment deadline for function processing
  ack_deadline_seconds = 60
  
  # Enable message retention for debugging and replay capabilities
  message_retention_duration = "604800s" # 7 days
  retain_acked_messages      = true
  
  # Configure retry policy for failed message processing
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Dead letter queue configuration for unprocessable messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  # Push configuration for Cloud Functions trigger
  push_config {
    push_endpoint = "https://${var.region}-${var.project_id}.cloudfunctions.net/${local.function_name}"
    
    # Configure authentication for secure function invocation
    oidc_token {
      service_account_email = google_service_account.function_sa.email
    }
    
    attributes = {
      x-goog-version = "v1"
    }
  }
  
  depends_on = [google_pubsub_topic.asset_changes]
}

# Dead letter topic for failed message processing
resource "google_pubsub_topic" "dead_letter" {
  name    = "${local.topic_name}-dead-letter"
  project = var.project_id
  
  labels = local.common_labels
  
  message_retention_duration = "2592000s" # 30 days
}

# ==============================================================================
# BigQuery Resources for Audit Data Storage
# ==============================================================================

# BigQuery dataset for storing infrastructure audit data
resource "google_bigquery_dataset" "infrastructure_audit" {
  dataset_id  = local.dataset_name
  project     = var.project_id
  location    = var.region
  description = "Dataset for storing infrastructure change audit logs"
  
  labels = local.common_labels
  
  # Configure access controls and data governance
  access {
    role          = "OWNER"
    user_by_email = data.google_client_config.current.client_email
  }
  
  access {
    role           = "WRITER"
    special_group  = "projectWriters"
  }
  
  access {
    role           = "READER"
    special_group  = "projectReaders"
  }
  
  # Enable default table expiration for cost control
  default_table_expiration_ms = var.audit_data_retention_days * 24 * 60 * 60 * 1000
  
  # Configure data location for compliance requirements
  location = var.region
}

# BigQuery table for asset change records
resource "google_bigquery_table" "asset_changes" {
  dataset_id = google_bigquery_dataset.infrastructure_audit.dataset_id
  table_id   = "asset_changes"
  project    = var.project_id
  
  description = "Table storing infrastructure asset change events for compliance and audit"
  
  labels = local.common_labels
  
  # Define schema for comprehensive audit trail
  schema = jsonencode([
    {
      name        = "timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Timestamp when the change was processed"
    },
    {
      name        = "asset_name"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Full resource name of the changed asset"
    },
    {
      name        = "asset_type"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Type of the asset (e.g., compute.googleapis.com/Instance)"
    },
    {
      name        = "change_type"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Type of change: CREATED, UPDATED, or DELETED"
    },
    {
      name        = "prior_state"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "JSON representation of the asset state before change"
    },
    {
      name        = "current_state"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "JSON representation of the asset state after change"
    },
    {
      name        = "project_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Project ID where the asset change occurred"
    },
    {
      name        = "location"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Geographic location of the asset"
    },
    {
      name        = "change_time"
      type        = "TIMESTAMP"
      mode        = "NULLABLE"
      description = "Timestamp when the actual change occurred"
    },
    {
      name        = "ancestors"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Comma-separated list of asset ancestors (folders, organization)"
    }
  ])
  
  # Configure partitioning for query performance
  time_partitioning {
    type          = "DAY"
    field         = "timestamp"
    expiration_ms = var.audit_data_retention_days * 24 * 60 * 60 * 1000
  }
  
  # Configure clustering for efficient queries
  clustering = ["project_id", "asset_type", "change_type"]
  
  depends_on = [google_bigquery_dataset.infrastructure_audit]
}

# ==============================================================================
# Service Account and IAM for Cloud Functions
# ==============================================================================

# Service account for Cloud Functions with least privilege access
resource "google_service_account" "function_sa" {
  account_id   = "asset-change-processor-${random_id.suffix.hex}"
  display_name = "Asset Change Processor Service Account"
  description  = "Service account for processing infrastructure change events"
  project      = var.project_id
}

# IAM binding for BigQuery data editing
resource "google_project_iam_member" "function_bigquery_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Monitoring metric writing
resource "google_project_iam_member" "function_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Pub/Sub subscription access
resource "google_project_iam_member" "function_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Functions invoker (for Pub/Sub push)
resource "google_cloudfunctions_function_iam_member" "function_invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.asset_processor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.function_sa.email}"
  
  depends_on = [google_cloudfunctions_function.asset_processor]
}

# ==============================================================================
# Cloud Storage for Function Source Code
# ==============================================================================

# Storage bucket for Cloud Functions source code
resource "google_storage_bucket" "function_source" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id
  
  labels = local.common_labels
  
  # Configure bucket for function deployment
  uniform_bucket_level_access = true
  
  # Enable versioning for source code management
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

# Archive the function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content  = file("${path.module}/function_code/main.py")
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# ==============================================================================
# Cloud Functions for Event Processing
# ==============================================================================

# Cloud Function to process asset change events
resource "google_cloudfunctions_function" "asset_processor" {
  name    = local.function_name
  project = var.project_id
  region  = var.region
  
  description = "Processes infrastructure change events from Cloud Asset Inventory"
  
  # Configure function runtime and resources
  runtime               = "python39"
  available_memory_mb   = 256
  timeout               = 60
  entry_point          = "process_asset_change"
  service_account_email = google_service_account.function_sa.email
  
  # Configure function source code
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  # Configure Pub/Sub trigger
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.asset_changes.name
  }
  
  # Set environment variables for function configuration
  environment_variables = {
    PROJECT_ID   = var.project_id
    DATASET_NAME = local.dataset_name
    REGION       = var.region
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_storage_bucket_object.function_source,
    google_service_account.function_sa
  ]
}

# ==============================================================================
# Cloud Asset Inventory Feed
# ==============================================================================

# Cloud Asset Inventory feed for real-time infrastructure monitoring
resource "google_cloud_asset_project_feed" "infrastructure_feed" {
  project  = var.project_id
  feed_id  = local.feed_name
  
  # Configure comprehensive asset monitoring
  content_type = "RESOURCE"
  asset_types  = var.monitored_asset_types
  
  # Configure Pub/Sub destination
  feed_output_config {
    pubsub_destination {
      topic = google_pubsub_topic.asset_changes.id
    }
  }
  
  # Optional: Configure feed condition for selective monitoring
  # Uncomment and modify based on specific requirements
  # condition {
  #   expression = <<-EOT
  #     !temporal_asset.deleted &&
  #     temporal_asset.prior_asset_state == google.cloud.asset.v1.TemporalAsset.PriorAssetState.DOES_NOT_EXIST
  #   EOT
  #   title       = "created"
  #   description = "Send notifications on creation events"
  # }
  
  depends_on = [
    google_pubsub_topic.asset_changes,
    google_cloudfunctions_function.asset_processor
  ]
}

# ==============================================================================
# Cloud Monitoring Alert Policies
# ==============================================================================

# Monitoring notification channel for alerts (email)
resource "google_monitoring_notification_channel" "email" {
  count = length(var.alert_email_addresses) > 0 ? length(var.alert_email_addresses) : 0
  
  display_name = "Infrastructure Change Alert - ${var.alert_email_addresses[count.index]}"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = var.alert_email_addresses[count.index]
  }
  
  enabled = true
}

# Alert policy for high infrastructure change rate
resource "google_monitoring_alert_policy" "high_change_rate" {
  count = var.enable_alerting ? 1 : 0
  
  display_name = "Critical Infrastructure Changes - High Rate"
  project      = var.project_id
  
  documentation {
    content   = "Alert triggered when infrastructure change rate exceeds threshold, indicating potential security incident or deployment issue."
    mime_type = "text/markdown"
  }
  
  conditions {
    display_name = "High Change Rate"
    
    condition_threshold {
      filter          = "resource.type=\"global\" AND metric.type=\"custom.googleapis.com/infrastructure/changes\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.change_rate_threshold
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  # Configure alert strategy
  alert_strategy {
    auto_close = "1800s"
  }
  
  combiner = "OR"
  enabled  = true
  
  # Configure notification channels
  notification_channels = google_monitoring_notification_channel.email[*].name
  
  depends_on = [google_monitoring_notification_channel.email]
}

# Alert policy for function errors
resource "google_monitoring_alert_policy" "function_errors" {
  count = var.enable_alerting ? 1 : 0
  
  display_name = "Asset Change Processing Errors"
  project      = var.project_id
  
  documentation {
    content   = "Alert triggered when Cloud Function processing asset changes encounters errors."
    mime_type = "text/markdown"
  }
  
  conditions {
    display_name = "Function Error Rate"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\" AND metric.labels.status=\"error\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  alert_strategy {
    auto_close = "900s"
  }
  
  combiner = "OR"
  enabled  = true
  
  notification_channels = google_monitoring_notification_channel.email[*].name
  
  depends_on = [
    google_monitoring_notification_channel.email,
    google_cloudfunctions_function.asset_processor
  ]
}