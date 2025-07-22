# GCP Data Privacy Compliance Infrastructure
# This Terraform configuration deploys a comprehensive data privacy compliance system
# using Cloud Data Loss Prevention, Security Command Center, and automated response mechanisms

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent naming and configuration
locals {
  resource_name = "${var.resource_prefix}-${random_id.suffix.hex}"
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    region      = var.region
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "dlp.googleapis.com",
    "securitycenter.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudscheduler.googleapis.com",
    "iam.googleapis.com",
    "cloudbuild.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
}

# Service account for DLP function with least privilege permissions
resource "google_service_account" "dlp_function_sa" {
  account_id   = "${var.resource_prefix}-function-sa"
  display_name = "DLP Function Service Account"
  description  = "Service account for DLP processing Cloud Function with minimal required permissions"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM bindings for the DLP function service account
resource "google_project_iam_member" "dlp_function_permissions" {
  for_each = toset([
    "roles/dlp.user",
    "roles/securitycenter.findingsEditor",
    "roles/pubsub.subscriber",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/storage.objectViewer"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.dlp_function_sa.email}"

  depends_on = [google_service_account.dlp_function_sa]
}

# Cloud Storage bucket for test data with security best practices
resource "google_storage_bucket" "dlp_test_data" {
  name                        = "${local.resource_name}-test-data"
  location                    = var.region
  project                     = var.project_id
  force_destroy               = true
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Upload sample sensitive data for testing DLP
resource "google_storage_bucket_object" "sample_data" {
  name   = "sample_data.txt"
  bucket = google_storage_bucket.dlp_test_data.name
  content = <<-EOT
    Customer: John Doe, SSN: 123-45-6789, Email: john.doe@example.com
    Credit Card: 4111-1111-1111-1111, Phone: (555) 123-4567
    Medical Record: Patient ID 12345, DOB: 1985-03-15
    Employee: Jane Smith, ID: EMP-654321, Department: HR
  EOT

  depends_on = [google_storage_bucket.dlp_test_data]
}

# Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name                        = "${local.resource_name}-function-source"
  location                    = var.region
  project                     = var.project_id
  force_destroy               = true
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Archive the function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/function-source.zip"
  source {
    content = templatefile("${path.module}/function/main.py.tpl", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  source {
    content  = file("${path.module}/function/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  depends_on = [google_storage_bucket.function_source]
}

# DLP inspection template for comprehensive PII detection
resource "google_data_loss_prevention_inspect_template" "privacy_compliance" {
  parent       = "projects/${var.project_id}"
  display_name = "Privacy Compliance Template"
  description  = "Detects PII, PHI, and financial data for compliance monitoring"

  inspect_config {
    # Configure standard sensitive information types
    dynamic "info_types" {
      for_each = var.sensitive_info_types
      content {
        name = info_types.value
      }
    }

    min_likelihood = var.dlp_min_likelihood

    limits {
      max_findings_per_request = var.dlp_max_findings_per_request
      max_findings_per_info_type {
        info_type {
          name = "US_SOCIAL_SECURITY_NUMBER"
        }
        max_findings = 10
      }
    }

    include_quote = true

    # Custom information type for employee IDs
    custom_info_types {
      info_type {
        name = "EMPLOYEE_ID"
      }
      likelihood = "LIKELY"
      regex {
        pattern = "EMP-[0-9]{6}"
      }
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub topic for DLP findings
resource "google_pubsub_topic" "dlp_findings" {
  name    = "${local.resource_name}-dlp-findings"
  project = var.project_id

  message_retention_duration = var.pubsub_message_retention_duration

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Dead letter topic for failed message processing
resource "google_pubsub_topic" "dlp_dead_letter" {
  name    = "${local.resource_name}-dlp-dead-letter"
  project = var.project_id

  message_retention_duration = var.pubsub_message_retention_duration

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscription for processing DLP findings
resource "google_pubsub_subscription" "dlp_processor" {
  name                 = "${local.resource_name}-dlp-processor"
  topic                = google_pubsub_topic.dlp_findings.name
  project              = var.project_id
  ack_deadline_seconds = var.pubsub_ack_deadline

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlp_dead_letter.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  labels = local.common_labels

  depends_on = [google_pubsub_topic.dlp_findings, google_pubsub_topic.dlp_dead_letter]
}

# Grant DLP service permission to publish to Pub/Sub topic
resource "google_pubsub_topic_iam_member" "dlp_publisher" {
  topic   = google_pubsub_topic.dlp_findings.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:service-${data.google_project.current.number}@dlp-api.iam.gserviceaccount.com"
  project = var.project_id

  depends_on = [google_pubsub_topic.dlp_findings]
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Cloud Function for processing DLP findings (Gen2)
resource "google_cloudfunctions2_function" "dlp_processor" {
  name        = "${local.resource_name}-dlp-processor"
  location    = var.region
  project     = var.project_id
  description = "Process DLP findings and create Security Command Center findings"

  build_config {
    runtime     = "python311"
    entry_point = "process_dlp_findings"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }

    environment_variables = {
      BUILD_ENV = var.environment
    }

    automatic_update_policy {}
  }

  service_config {
    max_instance_count               = 100
    min_instance_count              = 0
    available_memory                = var.function_memory
    available_cpu                   = "1"
    timeout_seconds                 = var.function_timeout
    max_instance_request_concurrency = 1000

    environment_variables = {
      PROJECT_ID  = var.project_id
      REGION      = var.region
      LOG_LEVEL   = "INFO"
      ENVIRONMENT = var.environment
    }

    service_account_email = google_service_account.dlp_function_sa.email
    ingress_settings      = "ALLOW_INTERNAL_ONLY"
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.dlp_findings.id
    retry_policy   = "RETRY_POLICY_RETRY"

    service_account_email = google_service_account.dlp_function_sa.email
  }

  labels = local.common_labels

  depends_on = [
    google_storage_bucket_object.function_source,
    google_service_account.dlp_function_sa,
    google_pubsub_topic.dlp_findings
  ]
}

# Pub/Sub topic for triggering scheduled DLP scans
resource "google_pubsub_topic" "dlp_scan_trigger" {
  name    = "${local.resource_name}-dlp-scan-trigger"
  project = var.project_id

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Scheduler job for periodic DLP scans
resource "google_cloud_scheduler_job" "dlp_scan_scheduler" {
  name             = "${local.resource_name}-dlp-scan-scheduler"
  project          = var.project_id
  region           = var.region
  description      = "Trigger DLP scans on schedule for continuous compliance monitoring"
  schedule         = var.dlp_scan_schedule
  time_zone        = "UTC"
  attempt_deadline = "320s"

  retry_config {
    retry_count          = 3
    max_retry_duration   = "300s"
    min_backoff_duration = "5s"
    max_backoff_duration = "60s"
    max_doublings        = 3
  }

  pubsub_target {
    topic_name = google_pubsub_topic.dlp_scan_trigger.id
    data = base64encode(jsonencode({
      scan_type    = "scheduled"
      priority     = "normal"
      bucket_name  = google_storage_bucket.dlp_test_data.name
      template_id  = google_data_loss_prevention_inspect_template.privacy_compliance.id
    }))

    attributes = {
      source      = "scheduler"
      environment = var.environment
    }
  }

  depends_on = [
    google_pubsub_topic.dlp_scan_trigger,
    google_data_loss_prevention_inspect_template.privacy_compliance
  ]
}

# Monitoring notification channel for email alerts (if email provided)
resource "google_monitoring_notification_channel" "email" {
  count        = var.notification_email != "" ? 1 : 0
  display_name = "Privacy Compliance Email Alerts"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.notification_email
  }

  depends_on = [google_project_service.required_apis]
}

# Alert policy for high-severity DLP findings
resource "google_monitoring_alert_policy" "dlp_findings_alert" {
  count        = var.enable_monitoring_alerts ? 1 : 0
  display_name = "DLP High Severity Findings"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "High severity DLP findings detected"

    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND metric.type=\"logging.googleapis.com/user/dlp_findings_count\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.dlp_processor.name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = var.monitoring_alert_threshold

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.function_name"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].name] : []

  alert_strategy {
    auto_close = "1800s" # 30 minutes

    notification_rate_limit {
      period = "300s" # No more than one notification per 5 minutes
    }
  }

  documentation {
    content   = "High severity DLP findings detected. Review the Security Command Center for details and take immediate action to secure sensitive data."
    mime_type = "text/markdown"
    subject   = "DLP Alert: High Severity Privacy Violations Detected"
  }

  user_labels = merge(local.common_labels, {
    severity = "high"
    type     = "security"
  })

  depends_on = [
    google_cloudfunctions2_function.dlp_processor,
    google_project_service.required_apis
  ]
}

# Log-based metric for DLP findings count
resource "google_logging_metric" "dlp_findings_count" {
  name    = "${local.resource_name}-dlp-findings-count"
  project = var.project_id
  filter  = <<-EOT
    resource.type="cloud_function"
    resource.labels.function_name="${google_cloudfunctions2_function.dlp_processor.name}"
    jsonPayload.message="DLP finding processed"
  EOT

  label_extractors = {
    severity  = "EXTRACT(jsonPayload.severity)"
    info_type = "EXTRACT(jsonPayload.info_type)"
  }

  metric_descriptor {
    metric_kind = "COUNTER"
    value_type  = "INT64"
    unit        = "1"
    display_name = "DLP Findings Count"
  }

  depends_on = [google_cloudfunctions2_function.dlp_processor]
}

# IAM policy for Security Command Center (if enabled)
resource "google_project_iam_member" "scc_findings_editor" {
  count   = var.enable_security_command_center ? 1 : 0
  project = var.project_id
  role    = "roles/securitycenter.findingsEditor"
  member  = "serviceAccount:${google_service_account.dlp_function_sa.email}"

  depends_on = [google_service_account.dlp_function_sa]
}