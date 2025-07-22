# Data Locality Optimization Infrastructure
# This Terraform configuration creates a complete data locality optimization system
# using Cloud Storage, Cloud Monitoring, Cloud Functions, and Cloud Scheduler

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent resource naming and labeling
locals {
  resource_suffix = random_id.suffix.hex
  bucket_name     = "${var.resource_prefix}-demo-${local.resource_suffix}"
  function_name   = "${var.resource_prefix}-relocator-${local.resource_suffix}"
  scheduler_job   = "${var.resource_prefix}-analyzer-${local.resource_suffix}"
  pubsub_topic    = "${var.resource_prefix}-alerts-${local.resource_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge({
    environment   = var.environment
    purpose      = "data-locality-optimization"
    managed-by   = "terraform"
    created-by   = "cloud-recipe"
  }, var.labels)
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "storage.googleapis.com",
    "monitoring.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "pubsub.googleapis.com",
    "storagetransfer.googleapis.com",
    "cloudbuild.googleapis.com"
  ])
  
  service = each.key
  
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create the primary Cloud Storage bucket for data locality optimization
resource "google_storage_bucket" "data_locality_bucket" {
  name     = local.bucket_name
  location = var.primary_region
  
  # Storage configuration
  storage_class = var.bucket_storage_class
  
  # Enable uniform bucket-level access for enhanced security
  uniform_bucket_level_access = var.enable_uniform_bucket_access
  
  # Versioning configuration for data protection
  versioning {
    enabled = true
  }
  
  # Lifecycle rules for cost optimization
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
  
  # Apply labels for monitoring and cost tracking
  labels = merge(local.common_labels, {
    component = "storage"
    purpose   = "data-locality-optimization"
  })
  
  # Prevent accidental deletion
  lifecycle {
    prevent_destroy = false
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub topic for relocation notifications
resource "google_pubsub_topic" "relocation_alerts" {
  name = local.pubsub_topic
  
  # Message retention policy
  message_retention_duration = "${var.pubsub_message_retention}h"
  
  labels = merge(local.common_labels, {
    component = "messaging"
    purpose   = "relocation-notifications"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create subscription for monitoring relocation events
resource "google_pubsub_subscription" "relocation_monitor" {
  name  = "${local.pubsub_topic}-monitor"
  topic = google_pubsub_topic.relocation_alerts.name
  
  # Acknowledgment deadline
  ack_deadline_seconds = 60
  
  # Message retention policy
  message_retention_duration = "604800s"  # 7 days
  
  # Dead letter policy for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.relocation_alerts.id
    max_delivery_attempts = 5
  }
  
  labels = merge(local.common_labels, {
    component = "messaging"
    purpose   = "event-monitoring"
  })
}

# Create custom metric descriptor for access pattern analysis
resource "google_monitoring_metric_descriptor" "regional_access_latency" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  type         = "custom.googleapis.com/storage/regional_access_latency"
  metric_kind  = "GAUGE"
  value_type   = "DOUBLE"
  unit         = "ms"
  description  = "Average access latency by region for storage optimization"
  display_name = "Storage Regional Access Latency"
  
  labels {
    key         = "bucket_name"
    value_type  = "STRING"
    description = "Name of the Cloud Storage bucket"
  }
  
  labels {
    key         = "source_region"
    value_type  = "STRING"
    description = "Region from which the bucket is accessed"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_prefix}-function-sa-${local.resource_suffix}"
  display_name = "Data Locality Optimization Function Service Account"
  description  = "Service account for bucket relocation Cloud Function"
}

# Grant necessary permissions to the function service account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/storage.admin",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/pubsub.publisher",
    "roles/storagetransfer.admin",
    "roles/logging.logWriter"
  ])
  
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create the Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/bucket-relocator-function.zip"
  
  source_dir = "${path.module}/function"
}

# Upload function source to Cloud Storage bucket for deployment
resource "google_storage_bucket_object" "function_source" {
  name   = "bucket-relocator-function-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.data_locality_bucket.name
  source = data.archive_file.function_source.output_path
}

# Deploy the Cloud Function for bucket relocation logic
resource "google_cloudfunctions_function" "bucket_relocator" {
  name        = local.function_name
  description = "Intelligent bucket relocation function for data locality optimization"
  region      = var.primary_region
  
  # Function configuration
  runtime               = "python39"
  available_memory_mb   = var.function_memory
  timeout               = var.function_timeout
  entry_point          = "bucket_relocator"
  service_account_email = google_service_account.function_sa.email
  
  # Source code configuration
  source_archive_bucket = google_storage_bucket.data_locality_bucket.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  # HTTP trigger configuration
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  # Environment variables
  environment_variables = {
    GCP_PROJECT   = var.project_id
    BUCKET_NAME   = google_storage_bucket.data_locality_bucket.name
    PUBSUB_TOPIC  = google_pubsub_topic.relocation_alerts.name
    PRIMARY_REGION = var.primary_region
    SECONDARY_REGION = var.secondary_region
  }
  
  # Labels for organization and monitoring
  labels = merge(local.common_labels, {
    component = "compute"
    purpose   = "bucket-relocation"
  })
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_permissions
  ]
}

# Create IAM policy to allow unauthenticated access to the function
resource "google_cloudfunctions_function_iam_member" "invoker" {
  project        = google_cloudfunctions_function.bucket_relocator.project
  region         = google_cloudfunctions_function.bucket_relocator.region
  cloud_function = google_cloudfunctions_function.bucket_relocator.name
  
  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}

# Create service account for Cloud Scheduler
resource "google_service_account" "scheduler_sa" {
  account_id   = "${var.resource_prefix}-scheduler-sa-${local.resource_suffix}"
  display_name = "Data Locality Scheduler Service Account"
  description  = "Service account for periodic data locality analysis scheduler"
}

# Grant Cloud Functions invoker permission to scheduler service account
resource "google_project_iam_member" "scheduler_function_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

# Create Cloud Scheduler job for periodic analysis
resource "google_cloud_scheduler_job" "locality_analyzer" {
  name        = local.scheduler_job
  description = "Daily data locality analysis and optimization trigger"
  schedule    = var.scheduler_cron
  time_zone   = var.scheduler_timezone
  region      = var.primary_region
  
  # HTTP target configuration
  http_target {
    http_method = "GET"
    uri         = google_cloudfunctions_function.bucket_relocator.https_trigger_url
    
    # Authentication configuration
    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
    }
  }
  
  # Retry configuration
  retry_config {
    retry_count          = 3
    max_retry_duration   = "300s"
    max_backoff_duration = "60s"
    min_backoff_duration = "10s"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.bucket_relocator
  ]
}

# Create alert policy for high latency detection
resource "google_monitoring_alert_policy" "storage_latency_alert" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  display_name = "Storage Access Latency Alert - ${local.bucket_name}"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "High storage access latency"
    
    condition_threshold {
      filter          = "resource.type=\"gcs_bucket\" AND resource.label.bucket_name=\"${google_storage_bucket.data_locality_bucket.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.alert_threshold_ms
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  # Alert strategy configuration
  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
    
    auto_close = "1800s"  # Auto-close alerts after 30 minutes
  }
  
  # Documentation for alert responders
  documentation {
    content = "Storage access latency for bucket ${google_storage_bucket.data_locality_bucket.name} has exceeded ${var.alert_threshold_ms}ms threshold. Consider triggering bucket relocation analysis."
    mime_type = "text/markdown"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create email notification channel if email is provided
resource "google_monitoring_notification_channel" "email_notification" {
  count = var.notification_email != "" ? 1 : 0
  
  display_name = "Data Locality Email Notifications"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  description = "Email notifications for data locality optimization alerts"
  enabled     = true
}

# Update alert policy with notification channel if email is configured
resource "google_monitoring_alert_policy" "storage_latency_alert_with_notifications" {
  count = var.enable_detailed_monitoring && var.notification_email != "" ? 1 : 0
  
  display_name = "Storage Access Latency Alert with Notifications - ${local.bucket_name}"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "High storage access latency"
    
    condition_threshold {
      filter          = "resource.type=\"gcs_bucket\" AND resource.label.bucket_name=\"${google_storage_bucket.data_locality_bucket.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.alert_threshold_ms
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  # Notification configuration
  notification_channels = [google_monitoring_notification_channel.email_notification[0].id]
  
  # Alert strategy configuration
  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
    
    auto_close = "1800s"
  }
  
  # Documentation for alert responders
  documentation {
    content = "Storage access latency for bucket ${google_storage_bucket.data_locality_bucket.name} has exceeded ${var.alert_threshold_ms}ms threshold. The bucket relocation function will be automatically triggered."
    mime_type = "text/markdown"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_monitoring_notification_channel.email_notification
  ]
}