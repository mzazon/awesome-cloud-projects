# Log-Driven Automation Infrastructure with Cloud Logging and Pub/Sub
# This Terraform configuration creates a comprehensive log-driven automation system
# that monitors application logs, detects patterns, and triggers automated responses

# Generate random suffix for resource names to ensure uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with environment and random suffix
  resource_suffix = "${var.environment}-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    region      = var.region
    created-by  = "terraform"
  })
  
  # Full resource names
  topic_name                    = "${var.resource_prefix}-${var.topic_name}-${local.resource_suffix}"
  alert_subscription_name       = "${var.resource_prefix}-${var.alert_subscription_name}-${local.resource_suffix}"
  remediation_subscription_name = "${var.resource_prefix}-${var.remediation_subscription_name}-${local.resource_suffix}"
  log_sink_name                = "${var.resource_prefix}-${var.log_sink_name}-${local.resource_suffix}"
  alert_function_name          = "${var.resource_prefix}-${var.alert_function_name}-${local.resource_suffix}"
  remediation_function_name    = "${var.resource_prefix}-${var.remediation_function_name}-${local.resource_suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com",
    "monitoring.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudbuild.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create Pub/Sub topic for incident automation
resource "google_pubsub_topic" "incident_automation" {
  name    = local.topic_name
  project = var.project_id
  labels  = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create alert subscription for general alerting
resource "google_pubsub_subscription" "alert_subscription" {
  name    = local.alert_subscription_name
  topic   = google_pubsub_topic.incident_automation.name
  project = var.project_id
  labels  = local.common_labels
  
  # Subscription configuration
  ack_deadline_seconds       = var.ack_deadline_seconds
  message_retention_duration = var.message_retention_duration
  retain_acked_messages      = false
  
  # Dead letter policy for failed message processing
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  # Retry policy for message delivery
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
  
  # Enable message ordering if needed
  enable_message_ordering = false
}

# Create remediation subscription with severity filtering
resource "google_pubsub_subscription" "remediation_subscription" {
  name    = local.remediation_subscription_name
  topic   = google_pubsub_topic.incident_automation.name
  project = var.project_id
  labels  = local.common_labels
  
  # Subscription configuration with longer ack deadline for remediation
  ack_deadline_seconds       = var.remediation_ack_deadline_seconds
  message_retention_duration = var.message_retention_duration
  retain_acked_messages      = false
  
  # Filter for high-severity incidents only
  filter = "attributes.severity=\"HIGH\" OR attributes.severity=\"CRITICAL\" OR attributes.type=\"ERROR\""
  
  # Dead letter policy for failed remediation attempts
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 3
  }
  
  # Retry policy with exponential backoff
  retry_policy {
    minimum_backoff = "30s"
    maximum_backoff = "600s"
  }
}

# Create dead letter topic for failed message processing
resource "google_pubsub_topic" "dead_letter" {
  name    = "${local.topic_name}-dead-letter"
  project = var.project_id
  labels  = merge(local.common_labels, { purpose = "dead-letter" })
}

# Create dead letter subscription for monitoring failed messages
resource "google_pubsub_subscription" "dead_letter_subscription" {
  name    = "${local.topic_name}-dead-letter-sub"
  topic   = google_pubsub_topic.dead_letter.name
  project = var.project_id
  labels  = merge(local.common_labels, { purpose = "dead-letter-monitoring" })
  
  ack_deadline_seconds       = 60
  message_retention_duration = "604800s" # 7 days
}

# Create log sink to forward critical logs to Pub/Sub
resource "google_logging_project_sink" "automation_sink" {
  name        = local.log_sink_name
  project     = var.project_id
  destination = "pubsub.googleapis.com/projects/${var.project_id}/topics/${google_pubsub_topic.incident_automation.name}"
  
  # Log filter for capturing error logs and exceptions
  filter = var.log_filter
  
  # Include children logs
  include_children = true
  
  # Enable unique writer identity for IAM binding
  unique_writer_identity = true
}

# Grant Pub/Sub publisher permissions to the log sink
resource "google_pubsub_topic_iam_binding" "sink_publisher" {
  topic   = google_pubsub_topic.incident_automation.name
  role    = "roles/pubsub.publisher"
  members = [google_logging_project_sink.automation_sink.writer_identity]
  
  project = var.project_id
}

# Create log-based metrics if enabled
resource "google_logging_metric" "error_rate_metric" {
  count = var.create_log_metrics ? 1 : 0
  
  name    = var.error_rate_metric_name
  project = var.project_id
  
  filter      = "severity>=ERROR"
  description = "Tracks application error rates over time for automated monitoring"
  
  # Metric descriptor for counting errors
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    unit        = "1"
    display_name = "Error Rate Metric"
  }
  
  # Label extractors for service identification
  label_extractors = {
    service = "EXTRACT(jsonPayload.service)"
  }
}

resource "google_logging_metric" "exception_pattern_metric" {
  count = var.create_log_metrics ? 1 : 0
  
  name    = var.exception_pattern_metric_name
  project = var.project_id
  
  filter      = "textPayload:\"Exception\" OR jsonPayload.exception_type!=\"\""
  description = "Counts specific exception patterns for trend analysis"
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
    unit        = "1"
    display_name = "Exception Pattern Metric"
  }
  
  label_extractors = {
    exception_type = "EXTRACT(jsonPayload.exception_type)"
  }
}

resource "google_logging_metric" "latency_anomaly_metric" {
  count = var.create_log_metrics ? 1 : 0
  
  name    = var.latency_anomaly_metric_name
  project = var.project_id
  
  filter      = "jsonPayload.response_time>5000"
  description = "Tracks request latency spikes for performance monitoring"
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    unit        = "ms"
    display_name = "Latency Anomaly Metric"
  }
  
  # Value extractor for response time
  value_extractor = "EXTRACT(jsonPayload.response_time)"
}

# Create service accounts for Cloud Functions if enabled
resource "google_service_account" "alert_function_sa" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = "${var.alert_function_name}-sa"
  display_name = "Service Account for Alert Processing Function"
  description  = "Service account used by the alert processing Cloud Function"
  project      = var.project_id
}

resource "google_service_account" "remediation_function_sa" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = "${var.remediation_function_name}-sa"
  display_name = "Service Account for Remediation Function"
  description  = "Service account used by the auto-remediation Cloud Function"
  project      = var.project_id
}

# IAM bindings for alert function service account
resource "google_project_iam_member" "alert_function_permissions" {
  for_each = var.create_service_accounts ? toset([
    "roles/logging.viewer",
    "roles/monitoring.metricWriter",
    "roles/pubsub.publisher"
  ]) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.alert_function_sa[0].email}"
}

# IAM bindings for remediation function service account
resource "google_project_iam_member" "remediation_function_permissions" {
  for_each = var.create_service_accounts ? toset([
    "roles/logging.viewer",
    "roles/monitoring.metricWriter",
    "roles/compute.instanceAdmin",
    "roles/pubsub.publisher"
  ]) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.remediation_function_sa[0].email}"
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-function-source-${local.resource_suffix}"
  location = var.region
  project  = var.project_id
  
  labels = merge(local.common_labels, { purpose = "function-source" })
  
  # Versioning for source code management
  versioning {
    enabled = true
  }
  
  # Lifecycle management for old versions
  lifecycle_rule {
    condition {
      num_newer_versions = 3
    }
    action {
      type = "Delete"
    }
  }
  
  # Uniform bucket-level access
  uniform_bucket_level_access = true
}

# Create archive for alert processing function source code
data "archive_file" "alert_function_source" {
  type        = "zip"
  output_path = "/tmp/alert-function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/alert-function/index.js", {
      project_id = var.project_id
      topic_name = google_pubsub_topic.incident_automation.name
    })
    filename = "index.js"
  }
  
  source {
    content  = file("${path.module}/function_code/alert-function/package.json")
    filename = "package.json"
  }
}

# Upload alert function source to Cloud Storage
resource "google_storage_bucket_object" "alert_function_source" {
  name   = "alert-function-source-${data.archive_file.alert_function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.alert_function_source.output_path
  
  depends_on = [data.archive_file.alert_function_source]
}

# Create archive for remediation function source code
data "archive_file" "remediation_function_source" {
  type        = "zip"
  output_path = "/tmp/remediation-function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/remediation-function/index.js", {
      project_id = var.project_id
      zone       = var.zone
      topic_name = google_pubsub_topic.incident_automation.name
    })
    filename = "index.js"
  }
  
  source {
    content  = file("${path.module}/function_code/remediation-function/package.json")
    filename = "package.json"
  }
}

# Upload remediation function source to Cloud Storage
resource "google_storage_bucket_object" "remediation_function_source" {
  name   = "remediation-function-source-${data.archive_file.remediation_function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.remediation_function_source.output_path
  
  depends_on = [data.archive_file.remediation_function_source]
}

# Deploy alert processing Cloud Function
resource "google_cloudfunctions2_function" "alert_processor" {
  name     = local.alert_function_name
  location = var.region
  project  = var.project_id
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "processAlert"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.alert_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 100
    min_instance_count    = 0
    available_memory      = "${var.alert_function_memory}Mi"
    timeout_seconds       = var.function_timeout_seconds
    max_instance_request_concurrency = 1
    
    # Service account configuration
    service_account_email = var.create_service_accounts ? google_service_account.alert_function_sa[0].email : null
    
    # Environment variables
    environment_variables = {
      PROJECT_ID         = var.project_id
      TOPIC_NAME         = google_pubsub_topic.incident_automation.name
      SLACK_WEBHOOK_URL  = var.slack_webhook_url
      NOTIFICATION_EMAIL = var.notification_email
    }
    
    # VPC connector if enabled
    dynamic "vpc_connector" {
      for_each = var.enable_vpc_connector ? [1] : []
      content {
        name = var.vpc_connector_name
      }
    }
  }
  
  # Event trigger configuration
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.incident_automation.id
    
    retry_policy = "RETRY_POLICY_RETRY"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.alert_function_source
  ]
}

# Deploy auto-remediation Cloud Function
resource "google_cloudfunctions2_function" "auto_remediation" {
  name     = local.remediation_function_name
  location = var.region
  project  = var.project_id
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "autoRemediate"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.remediation_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 50
    min_instance_count    = 0
    available_memory      = "${var.remediation_function_memory}Mi"
    timeout_seconds       = var.remediation_function_timeout_seconds
    max_instance_request_concurrency = 1
    
    # Service account configuration
    service_account_email = var.create_service_accounts ? google_service_account.remediation_function_sa[0].email : null
    
    # Environment variables
    environment_variables = {
      PROJECT_ID = var.project_id
      ZONE       = var.zone
      TOPIC_NAME = google_pubsub_topic.incident_automation.name
    }
    
    # VPC connector if enabled
    dynamic "vpc_connector" {
      for_each = var.enable_vpc_connector ? [1] : []
      content {
        name = var.vpc_connector_name
      }
    }
  }
  
  # Event trigger configuration for remediation subscription
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.incident_automation.id
    
    retry_policy = "RETRY_POLICY_RETRY"
    
    # Event filters for high-severity incidents
    event_filters {
      attribute = "attributes.severity"
      value     = "HIGH"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.remediation_function_source
  ]
}

# Create Cloud Monitoring alerting policies if enabled
resource "google_monitoring_alert_policy" "error_rate_alert" {
  count = var.create_alerting_policies && var.create_log_metrics ? 1 : 0
  
  display_name = "High Error Rate Alert - ${var.environment}"
  project      = var.project_id
  
  documentation {
    content   = "Alert when error rate exceeds normal thresholds indicating application issues"
    mime_type = "text/markdown"
  }
  
  conditions {
    display_name = "Error rate condition"
    
    condition_threshold {
      filter          = "resource.type=\"global\" AND metric.type=\"logging.googleapis.com/user/${var.error_rate_metric_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.error_rate_threshold
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  alert_strategy {
    auto_close = var.alert_auto_close_duration
  }
  
  enabled = true
}

resource "google_monitoring_alert_policy" "latency_alert" {
  count = var.create_alerting_policies && var.create_log_metrics ? 1 : 0
  
  display_name = "High Latency Alert - ${var.environment}"
  project      = var.project_id
  
  documentation {
    content   = "Alert when response times indicate performance degradation"
    mime_type = "text/markdown"
  }
  
  conditions {
    display_name = "Latency anomaly condition"
    
    condition_threshold {
      filter          = "resource.type=\"global\" AND metric.type=\"logging.googleapis.com/user/${var.latency_anomaly_metric_name}\""
      duration        = "180s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.latency_threshold_ms
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MEAN"
      }
    }
  }
  
  alert_strategy {
    auto_close = "1200s" # 20 minutes
  }
  
  enabled = true
}

# Create log-based alerting policy for immediate response
resource "google_monitoring_alert_policy" "critical_log_pattern_alert" {
  count = var.create_alerting_policies ? 1 : 0
  
  display_name = "Critical Log Pattern Alert - ${var.environment}"
  project      = var.project_id
  
  documentation {
    content   = "Immediate alert for critical log patterns requiring urgent attention"
    mime_type = "text/markdown"
  }
  
  conditions {
    display_name = "Critical error pattern"
    
    condition_matched_log {
      filter = "severity=CRITICAL OR textPayload:(\"FATAL\" OR \"OutOfMemoryError\" OR \"StackOverflowError\")"
      
      label_extractors = {
        service  = "EXTRACT(jsonPayload.service)"
        instance = "EXTRACT(resource.labels.instance_id)"
      }
    }
  }
  
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
  
  enabled = true
}