# Automated Threat Response Infrastructure
# This Terraform configuration creates a comprehensive security automation system
# using Security Command Center, Cloud Functions, Pub/Sub, and Cloud Logging

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  resource_suffix = random_id.suffix.hex
  common_labels = merge(var.labels, {
    deployment-id = local.resource_suffix
    created-by    = "terraform"
    created-at    = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "securitycenter.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  count    = var.create_source_bucket ? 1 : 0
  name     = var.function_source_archive_bucket != "" ? var.function_source_archive_bucket : "${var.resource_prefix}-function-source-${local.resource_suffix}"
  location = var.region
  project  = var.project_id

  labels = local.common_labels

  # Security and lifecycle configuration
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub topics for event-driven security automation
resource "google_pubsub_topic" "threat_response_main" {
  name    = "${var.topic_names.main_topic}-${local.resource_suffix}"
  project = var.project_id
  labels  = local.common_labels

  depends_on = [google_project_service.required_apis]
}

resource "google_pubsub_topic" "threat_remediation" {
  name    = "${var.topic_names.remediation_topic}-${local.resource_suffix}"
  project = var.project_id
  labels  = local.common_labels

  depends_on = [google_project_service.required_apis]
}

resource "google_pubsub_topic" "threat_notification" {
  name    = "${var.topic_names.notification_topic}-${local.resource_suffix}"
  project = var.project_id
  labels  = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscriptions for reliable message delivery
resource "google_pubsub_subscription" "threat_response_main" {
  name    = "${var.subscription_names.main_subscription}-${local.resource_suffix}"
  topic   = google_pubsub_topic.threat_response_main.name
  project = var.project_id
  labels  = local.common_labels

  # Configure message retention and acknowledgment
  message_retention_duration = var.message_retention_duration
  ack_deadline_seconds      = var.ack_deadline_seconds

  # Dead letter policy for failed message processing
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_pubsub_subscription" "threat_remediation" {
  name    = "${var.subscription_names.remediation_subscription}-${local.resource_suffix}"
  topic   = google_pubsub_topic.threat_remediation.name
  project = var.project_id
  labels  = local.common_labels

  message_retention_duration = var.message_retention_duration
  ack_deadline_seconds      = 120 # Longer timeout for remediation actions

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 3 # Fewer retries for remediation to avoid duplicate actions
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_pubsub_subscription" "threat_notification" {
  name    = "${var.subscription_names.notification_subscription}-${local.resource_suffix}"
  topic   = google_pubsub_topic.threat_notification.name
  project = var.project_id
  labels  = local.common_labels

  message_retention_duration = var.message_retention_duration
  ack_deadline_seconds      = var.ack_deadline_seconds

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }

  depends_on = [google_project_service.required_apis]
}

# Dead letter topic for failed message processing
resource "google_pubsub_topic" "dead_letter" {
  name    = "security-dead-letter-${local.resource_suffix}"
  project = var.project_id
  labels  = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Logging sink to export Security Command Center findings to Pub/Sub
resource "google_logging_project_sink" "security_findings" {
  name        = "${var.log_sink_name}-${local.resource_suffix}"
  project     = var.project_id
  destination = "pubsub.googleapis.com/${google_pubsub_topic.threat_response_main.id}"

  # Advanced log filter for Security Command Center findings
  filter = var.security_findings_log_filter

  # Use a unique writer identity for the sink
  unique_writer_identity = true

  depends_on = [google_project_service.required_apis]
}

# Grant Pub/Sub publisher permissions to the log sink service account
resource "google_pubsub_topic_iam_member" "log_sink_publisher" {
  topic   = google_pubsub_topic.threat_response_main.name
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.security_findings.writer_identity
  project = var.project_id
}

# Service accounts for Cloud Functions with least privilege access
resource "google_service_account" "triage_function" {
  count        = var.create_service_accounts ? 1 : 0
  account_id   = "security-triage-${local.resource_suffix}"
  display_name = "Security Triage Function Service Account"
  description  = "Service account for the security triage Cloud Function"
  project      = var.project_id
}

resource "google_service_account" "remediation_function" {
  count        = var.create_service_accounts ? 1 : 0
  account_id   = "remediation-${local.resource_suffix}"
  display_name = "Automated Remediation Function Service Account"
  description  = "Service account for the automated remediation Cloud Function"
  project      = var.project_id
}

resource "google_service_account" "notification_function" {
  count        = var.create_service_accounts ? 1 : 0
  account_id   = "notification-${local.resource_suffix}"
  display_name = "Security Notification Function Service Account"
  description  = "Service account for the security notification Cloud Function"
  project      = var.project_id
}

# IAM bindings for service accounts
resource "google_project_iam_member" "triage_function_permissions" {
  for_each = var.create_service_accounts ? toset([
    "roles/pubsub.publisher",
    "roles/monitoring.metricWriter",
    "roles/securitycenter.findingsViewer",
    "roles/logging.logWriter"
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.triage_function[0].email}"
}

resource "google_project_iam_member" "remediation_function_permissions" {
  for_each = var.create_service_accounts ? toset([
    "roles/compute.instanceAdmin.v1",
    "roles/iam.securityAdmin",
    "roles/compute.securityAdmin",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/securitycenter.findingsEditor"
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.remediation_function[0].email}"
}

resource "google_project_iam_member" "notification_function_permissions" {
  for_each = var.create_service_accounts ? toset([
    "roles/monitoring.alertPolicyEditor",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter"
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.notification_function[0].email}"
}

# Create function source code archives
data "archive_file" "triage_function_source" {
  type        = "zip"
  output_path = "${path.module}/triage-function-source.zip"
  
  source {
    content = templatefile("${path.module}/functions/triage_function.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "remediation_function_source" {
  type        = "zip"
  output_path = "${path.module}/remediation-function-source.zip"
  
  source {
    content = templatefile("${path.module}/functions/remediation_function.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "notification_function_source" {
  type        = "zip"
  output_path = "${path.module}/notification-function-source.zip"
  
  source {
    content = templatefile("${path.module}/functions/notification_function.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "triage_function_source" {
  name   = "triage-function-source-${local.resource_suffix}.zip"
  bucket = var.create_source_bucket ? google_storage_bucket.function_source[0].name : var.function_source_archive_bucket
  source = data.archive_file.triage_function_source.output_path

  depends_on = [google_storage_bucket.function_source]
}

resource "google_storage_bucket_object" "remediation_function_source" {
  name   = "remediation-function-source-${local.resource_suffix}.zip"
  bucket = var.create_source_bucket ? google_storage_bucket.function_source[0].name : var.function_source_archive_bucket
  source = data.archive_file.remediation_function_source.output_path

  depends_on = [google_storage_bucket.function_source]
}

resource "google_storage_bucket_object" "notification_function_source" {
  name   = "notification-function-source-${local.resource_suffix}.zip"
  bucket = var.create_source_bucket ? google_storage_bucket.function_source[0].name : var.function_source_archive_bucket
  source = data.archive_file.notification_function_source.output_path

  depends_on = [google_storage_bucket.function_source]
}

# Security Triage Cloud Function
resource "google_cloudfunctions_function" "security_triage" {
  name        = "${var.function_names.triage_function}-${local.resource_suffix}"
  description = "Automated security triage function for threat analysis and routing"
  runtime     = var.function_runtime
  region      = var.region
  project     = var.project_id

  available_memory_mb   = var.triage_function_config.memory_mb
  timeout               = var.triage_function_config.timeout_s
  max_instances         = var.triage_function_config.max_instances
  entry_point          = "main"
  service_account_email = var.create_service_accounts ? google_service_account.triage_function[0].email : null

  source_archive_bucket = var.create_source_bucket ? google_storage_bucket.function_source[0].name : var.function_source_archive_bucket
  source_archive_object = google_storage_bucket_object.triage_function_source.name

  # Pub/Sub trigger for security findings
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.threat_response_main.name
  }

  # Environment variables for function configuration
  environment_variables = {
    GCP_PROJECT              = var.project_id
    REMEDIATION_TOPIC        = google_pubsub_topic.threat_remediation.name
    NOTIFICATION_TOPIC       = google_pubsub_topic.threat_notification.name
    DEBUG_LOGGING           = var.enable_debug_logging
    DEPLOYMENT_ID           = local.resource_suffix
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.triage_function_source
  ]
}

# Automated Remediation Cloud Function
resource "google_cloudfunctions_function" "automated_remediation" {
  name        = "${var.function_names.remediation_function}-${local.resource_suffix}"
  description = "Automated remediation function for critical security threats"
  runtime     = var.function_runtime
  region      = var.region
  project     = var.project_id

  available_memory_mb   = var.remediation_function_config.memory_mb
  timeout               = var.remediation_function_config.timeout_s
  max_instances         = var.remediation_function_config.max_instances
  entry_point          = "main"
  service_account_email = var.create_service_accounts ? google_service_account.remediation_function[0].email : null

  source_archive_bucket = var.create_source_bucket ? google_storage_bucket.function_source[0].name : var.function_source_archive_bucket
  source_archive_object = google_storage_bucket_object.remediation_function_source.name

  # Pub/Sub trigger for remediation actions
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.threat_remediation.name
  }

  environment_variables = {
    GCP_PROJECT    = var.project_id
    DEBUG_LOGGING  = var.enable_debug_logging
    DEPLOYMENT_ID  = local.resource_suffix
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.remediation_function_source
  ]
}

# Security Notification Cloud Function
resource "google_cloudfunctions_function" "security_notification" {
  name        = "${var.function_names.notification_function}-${local.resource_suffix}"
  description = "Security notification function for alerts and human review"
  runtime     = var.function_runtime
  region      = var.region
  project     = var.project_id

  available_memory_mb   = var.notification_function_config.memory_mb
  timeout               = var.notification_function_config.timeout_s
  max_instances         = var.notification_function_config.max_instances
  entry_point          = "main"
  service_account_email = var.create_service_accounts ? google_service_account.notification_function[0].email : null

  source_archive_bucket = var.create_source_bucket ? google_storage_bucket.function_source[0].name : var.function_source_archive_bucket
  source_archive_object = google_storage_bucket_object.notification_function_source.name

  # Pub/Sub trigger for notifications
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.threat_notification.name
  }

  environment_variables = {
    GCP_PROJECT           = var.project_id
    DEBUG_LOGGING         = var.enable_debug_logging
    DEPLOYMENT_ID         = local.resource_suffix
    SLACK_WEBHOOK_URL     = var.slack_webhook_url
    PAGERDUTY_INTEGRATION = var.pagerduty_integration_key
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.notification_function_source
  ]
}

# Custom metric descriptors for security monitoring
resource "google_monitoring_metric_descriptor" "security_findings_processed" {
  count        = var.enable_monitoring_alerts ? 1 : 0
  display_name = "Security Findings Processed"
  description  = "Number of security findings processed by automated system"
  type         = "custom.googleapis.com/security/findings_processed"
  metric_kind  = "CUMULATIVE"
  value_type   = "INT64"
  project      = var.project_id

  labels {
    key         = "severity"
    value_type  = "STRING"
    description = "Security finding severity level"
  }

  labels {
    key         = "category"
    value_type  = "STRING"
    description = "Security finding category"
  }

  labels {
    key         = "deployment_id"
    value_type  = "STRING"
    description = "Deployment identifier"
  }

  depends_on = [google_project_service.required_apis]
}

# Alert policy for critical security findings
resource "google_monitoring_alert_policy" "critical_security_findings" {
  count        = var.enable_monitoring_alerts ? 1 : 0
  display_name = "High Priority Security Findings - ${local.resource_suffix}"
  project      = var.project_id

  combiner = "OR"
  
  conditions {
    display_name = "Critical security findings rate"
    
    condition_threshold {
      filter         = "metric.type=\"custom.googleapis.com/security/findings_processed\" AND metric.label.severity=\"CRITICAL\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = var.critical_findings_threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.alert_notification_channels

  alert_strategy {
    auto_close = "86400s"
  }

  enabled = true

  depends_on = [
    google_monitoring_metric_descriptor.security_findings_processed,
    google_project_service.required_apis
  ]
}

# Alert policy for function errors
resource "google_monitoring_alert_policy" "function_errors" {
  count        = var.enable_monitoring_alerts ? 1 : 0
  display_name = "Security Function Errors - ${local.resource_suffix}"
  project      = var.project_id

  combiner = "OR"

  conditions {
    display_name = "Cloud Function execution errors"
    
    condition_threshold {
      filter = join(" OR ", [
        "resource.type=\"cloud_function\" AND resource.label.function_name=\"${google_cloudfunctions_function.security_triage.name}\"",
        "resource.type=\"cloud_function\" AND resource.label.function_name=\"${google_cloudfunctions_function.automated_remediation.name}\"",
        "resource.type=\"cloud_function\" AND resource.label.function_name=\"${google_cloudfunctions_function.security_notification.name}\""
      ])
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.alert_notification_channels

  alert_strategy {
    auto_close = "3600s"
  }

  enabled = true

  depends_on = [google_project_service.required_apis]
}