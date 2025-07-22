# Main Terraform configuration for GCP Domain Health Monitoring
# This infrastructure deploys a comprehensive domain health monitoring solution
# using Cloud Functions, Cloud Monitoring, Cloud Storage, and Pub/Sub

# Generate random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Local values for consistent resource naming and configuration
locals {
  resource_suffix = random_string.suffix.result
  
  # Standardized naming convention
  function_name = "domain-health-monitor-${local.resource_suffix}"
  bucket_name   = "domain-monitor-storage-${local.resource_suffix}"
  topic_name    = "domain-alerts-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    component = "domain-health-monitoring"
    version   = "1.0"
  })
  
  # Domains configuration for function environment
  domains_json = jsonencode(var.domains_to_monitor)
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "monitoring.googleapis.com",
    "domains.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com"
  ])

  service                    = each.value
  project                    = var.project_id
  disable_dependent_services = false
  disable_on_destroy         = false

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Cloud Storage bucket for function source code and monitoring data
resource "google_storage_bucket" "function_storage" {
  name                        = local.bucket_name
  location                    = var.region
  project                     = var.project_id
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  force_destroy               = true

  # Enable versioning for code deployment tracking
  versioning {
    enabled = true
  }

  # Lifecycle management for monitoring data retention
  lifecycle_rule {
    condition {
      age = var.retention_days
    }
    action {
      type = "Delete"
    }
  }

  # Lifecycle rule for versioned objects
  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }

  # Security configurations
  public_access_prevention = "enforced"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub topic for domain health alerts
resource "google_pubsub_topic" "domain_alerts" {
  name    = local.topic_name
  project = var.project_id

  # Message retention for 7 days
  message_retention_duration = "604800s"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for alert processing
resource "google_pubsub_subscription" "domain_alerts_sub" {
  name    = "${local.topic_name}-sub"
  topic   = google_pubsub_topic.domain_alerts.name
  project = var.project_id

  # Message retention for 7 days
  message_retention_duration = "604800s"
  
  # Acknowledgment deadline
  ack_deadline_seconds = 300

  # Dead letter policy for failed messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.domain_alerts_dlq.id
    max_delivery_attempts = 5
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Dead letter queue for failed alert messages
resource "google_pubsub_topic" "domain_alerts_dlq" {
  name    = "${local.topic_name}-dlq"
  project = var.project_id

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "domain-monitor-sa-${local.resource_suffix}"
  display_name = "Domain Health Monitor Service Account"
  description  = "Service account for domain health monitoring Cloud Function"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM roles for the function service account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/monitoring.metricWriter",
    "roles/pubsub.publisher",
    "roles/storage.objectAdmin",
    "roles/domains.viewer",
    "roles/logging.logWriter"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"

  depends_on = [google_service_account.function_sa]
}

# Create function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      domains_to_monitor     = var.domains_to_monitor
      ssl_expiry_warning_days = var.ssl_expiry_warning_days
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_storage.name
  source = data.archive_file.function_source.output_path

  depends_on = [google_storage_bucket.function_storage]
}

# Cloud Function for domain health monitoring
resource "google_cloudfunctions2_function" "domain_monitor" {
  name        = local.function_name
  location    = var.region
  project     = var.project_id
  description = "Automated domain health monitoring with SSL certificate and DNS checking"

  build_config {
    runtime     = "python39"
    entry_point = "domain_health_check"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_storage.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = var.function_memory
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.function_sa.email

    environment_variables = {
      GCP_PROJECT             = var.project_id
      TOPIC_NAME              = google_pubsub_topic.domain_alerts.name
      BUCKET_NAME             = google_storage_bucket.function_storage.name
      DOMAINS_TO_MONITOR      = local.domains_json
      SSL_EXPIRY_WARNING_DAYS = var.ssl_expiry_warning_days
      REGION                  = var.region
    }

    # Configure VPC access if private network is enabled
    dynamic "vpc_access" {
      for_each = var.enable_private_network ? [1] : []
      content {
        network_interfaces {
          network    = var.vpc_network_name
          subnetwork = var.vpc_subnet_name
        }
      }
    }
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_service_account.function_sa,
    google_storage_bucket_object.function_source
  ]
}

# Cloud Scheduler job for automated monitoring
resource "google_cloud_scheduler_job" "domain_monitor_schedule" {
  count = var.enable_cloud_scheduler ? 1 : 0

  name             = "domain-monitor-schedule-${local.resource_suffix}"
  description      = "Scheduled domain health monitoring job"
  schedule         = var.monitoring_schedule
  time_zone        = "UTC"
  region           = var.region
  project          = var.project_id
  attempt_deadline = "${var.function_timeout}s"

  retry_config {
    retry_count = 3
  }

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.domain_monitor.service_config[0].uri

    oidc_token {
      service_account_email = google_service_account.function_sa.email
    }

    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      trigger = "scheduler"
    }))
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.domain_monitor
  ]
}

# Cloud Monitoring notification channel for email alerts
resource "google_monitoring_notification_channel" "email_alerts" {
  count = var.notification_email != "" ? 1 : 0

  display_name = "Domain Health Email Alerts"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.notification_email
  }

  user_labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring alert policy for SSL certificate expiration
resource "google_monitoring_alert_policy" "ssl_expiry_alert" {
  display_name = "Domain SSL Certificate Expiring Soon"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "SSL Certificate Expiring"

    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/domain/ssl_valid\" AND resource.type=\"global\""
      duration        = "300s"
      comparison      = "COMPARISON_LESS_THAN"
      threshold_value = 1.0

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  # Add notification channels if email is provided
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email_alerts[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "SSL certificate for one or more monitored domains is expiring soon or has already expired."
    mime_type = "text/markdown"
  }

  user_labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring alert policy for DNS resolution failures
resource "google_monitoring_alert_policy" "dns_failure_alert" {
  display_name = "Domain DNS Resolution Failure"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "DNS Resolution Failed"

    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/domain/dns_resolves\" AND resource.type=\"global\""
      duration        = "300s"
      comparison      = "COMPARISON_LESS_THAN"
      threshold_value = 1.0

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  # Add notification channels if email is provided
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email_alerts[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "DNS resolution failed for one or more monitored domains."
    mime_type = "text/markdown"
  }

  user_labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Monitoring alert policy for HTTP response failures
resource "google_monitoring_alert_policy" "http_failure_alert" {
  display_name = "Domain HTTP Response Failure"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "HTTP Response Failed"

    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/domain/http_responds\" AND resource.type=\"global\""
      duration        = "300s"
      comparison      = "COMPARISON_LESS_THAN"
      threshold_value = 1.0

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  # Add notification channels if email is provided
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email_alerts[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "HTTP response check failed for one or more monitored domains."
    mime_type = "text/markdown"
  }

  user_labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Logging log sink for function logs (optional)
resource "google_logging_project_sink" "function_logs" {
  name        = "domain-monitor-logs-${local.resource_suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.function_storage.name}"
  project     = var.project_id

  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.function_name}\""

  unique_writer_identity = true

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket.function_storage
  ]
}

# Grant the log sink writer permission to the storage bucket
resource "google_storage_bucket_iam_member" "log_sink_writer" {
  bucket = google_storage_bucket.function_storage.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs.writer_identity

  depends_on = [google_logging_project_sink.function_logs]
}