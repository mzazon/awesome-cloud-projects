# Main Terraform configuration for GCP Privilege Escalation Monitoring
# This configuration deploys a complete real-time privilege escalation monitoring solution
# using Cloud Audit Logs, Pub/Sub, Cloud Functions, and Cloud Storage

# Generate random suffix for resource uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Resource naming with prefix and random suffix
  resource_suffix = random_id.suffix.hex
  topic_name     = "${var.resource_prefix}-${var.pubsub_topic_name}-${local.resource_suffix}"
  subscription_name = "${var.resource_prefix}-${var.pubsub_subscription_name}-${local.resource_suffix}"
  function_name  = "${var.resource_prefix}-${var.function_name}-${local.resource_suffix}"
  sink_name      = "${var.resource_prefix}-${var.log_sink_name}-${local.resource_suffix}"
  bucket_name    = "${var.project_id}-${var.resource_prefix}-${var.storage_bucket_name}-${local.resource_suffix}"
  
  # Merge default labels with user-provided labels
  common_labels = merge(var.labels, {
    environment = var.environment
    component   = "privilege-escalation-monitoring"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(var.required_apis) : []
  
  service            = each.value
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Pub/Sub topic for privilege escalation alerts
resource "google_pubsub_topic" "privilege_escalation_alerts" {
  name   = local.topic_name
  labels = local.common_labels
  
  # Configure topic settings for security event processing
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for Cloud Function processing
resource "google_pubsub_subscription" "privilege_monitor_subscription" {
  name  = local.subscription_name
  topic = google_pubsub_topic.privilege_escalation_alerts.name
  labels = local.common_labels
  
  # Configure subscription for reliable message processing
  ack_deadline_seconds         = var.pubsub_ack_deadline_seconds
  message_retention_duration   = var.pubsub_message_retention_duration
  retain_acked_messages        = false
  enable_message_ordering      = false
  
  # Configure dead letter policy for failed message handling
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter_topic.id
    max_delivery_attempts = 5
  }
  
  # Configure retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Configure expiration to prevent resource leaks
  expiration_policy {
    ttl = "2678400s" # 31 days
  }
}

# Create dead letter topic for failed message handling
resource "google_pubsub_topic" "dead_letter_topic" {
  name   = "${local.topic_name}-dlq"
  labels = merge(local.common_labels, { purpose = "dead-letter-queue" })
  
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

# Create Cloud Storage bucket for alert archival with lifecycle management
resource "google_storage_bucket" "privilege_audit_logs" {
  name     = local.bucket_name
  location = var.storage_location
  labels   = local.common_labels
  
  # Configure bucket settings for security and compliance
  storage_class                = var.storage_class
  uniform_bucket_level_access  = true
  public_access_prevention     = "enforced"
  
  # Enable versioning for audit trail integrity
  versioning {
    enabled = var.enable_bucket_versioning
  }
  
  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.coldline_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = var.archive_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }
  
  # Configure encryption
  encryption {
    default_kms_key_name = google_kms_crypto_key.bucket_key.id
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_kms_crypto_key_iam_binding.bucket_key_binding
  ]
}

# Create KMS key for bucket encryption
resource "google_kms_key_ring" "privilege_monitoring_keyring" {
  name     = "${var.resource_prefix}-keyring-${local.resource_suffix}"
  location = var.region
}

resource "google_kms_crypto_key" "bucket_key" {
  name     = "${var.resource_prefix}-bucket-key-${local.resource_suffix}"
  key_ring = google_kms_key_ring.privilege_monitoring_keyring.id
  
  purpose = "ENCRYPT_DECRYPT"
  
  lifecycle {
    prevent_destroy = true
  }
  
  labels = local.common_labels
}

# Grant Cloud Storage service agent access to KMS key
data "google_storage_project_service_account" "gcs_account" {}

resource "google_kms_crypto_key_iam_binding" "bucket_key_binding" {
  crypto_key_id = google_kms_crypto_key.bucket_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  
  members = [
    "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
  ]
}

# Create service account for Cloud Function
resource "google_service_account" "function_service_account" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = "${var.resource_prefix}-func-sa-${local.resource_suffix}"
  display_name = "Privilege Alert Processor Service Account"
  description  = "Service account for processing privilege escalation alerts"
}

# Grant necessary permissions to function service account
resource "google_project_iam_member" "function_storage_admin" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_service_account[0].email}"
  
  condition {
    title       = "Storage access for audit bucket only"
    description = "Allow storage access only for the audit logs bucket"
    expression  = "resource.name.startsWith(\"projects/_/buckets/${google_storage_bucket.privilege_audit_logs.name}\")"
  }
}

resource "google_project_iam_member" "function_monitoring_writer" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_service_account[0].email}"
}

resource "google_project_iam_member" "function_logging_writer" {
  count = var.create_service_accounts ? 1 : 0
  
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_service_account[0].email}"
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      bucket_name = google_storage_bucket.privilege_audit_logs.name
      project_id  = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage for deployment
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.privilege_audit_logs.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Deploy Cloud Function for alert processing
resource "google_cloudfunctions_function" "privilege_alert_processor" {
  name        = local.function_name
  description = "Processes privilege escalation alerts from Pub/Sub"
  region      = var.region
  
  runtime             = var.function_runtime
  available_memory_mb = var.function_memory
  timeout             = var.function_timeout
  max_instances       = var.function_max_instances
  
  source_archive_bucket = google_storage_bucket.privilege_audit_logs.name
  source_archive_object = google_storage_bucket_object.function_source.name
  entry_point          = "process_privilege_alert"
  
  # Configure Pub/Sub trigger
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.privilege_escalation_alerts.name
  }
  
  # Configure environment variables
  environment_variables = {
    BUCKET_NAME = google_storage_bucket.privilege_audit_logs.name
    GCP_PROJECT = var.project_id
    ENVIRONMENT = var.environment
  }
  
  # Use dedicated service account if created
  service_account_email = var.create_service_accounts ? google_service_account.function_service_account[0].email : null
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# Create log sink to route audit logs to Pub/Sub
resource "google_logging_project_sink" "privilege_escalation_sink" {
  name        = local.sink_name
  description = "Routes IAM and PAM audit logs to Pub/Sub for real-time monitoring"
  
  # Destination is the Pub/Sub topic
  destination = "pubsub.googleapis.com/projects/${var.project_id}/topics/${google_pubsub_topic.privilege_escalation_alerts.name}"
  
  # Filter for privilege escalation events
  filter = var.log_sink_filter
  
  # Include all log entries that match the filter
  unique_writer_identity = true
  
  depends_on = [google_project_service.required_apis]
}

# Grant Pub/Sub Publisher permissions to log sink service account
resource "google_pubsub_topic_iam_member" "sink_publisher" {
  topic  = google_pubsub_topic.privilege_escalation_alerts.name
  role   = "roles/pubsub.publisher"
  member = google_logging_project_sink.privilege_escalation_sink.writer_identity
}

# Create Cloud Monitoring alert policy for privilege escalation detection
resource "google_monitoring_alert_policy" "privilege_escalation_alert" {
  count = var.enable_monitoring_alerts ? 1 : 0
  
  display_name = "Privilege Escalation Detection - ${var.environment}"
  enabled      = true
  
  documentation {
    content = "Alert triggered when privilege escalation events exceed ${var.alert_threshold_value} per ${var.alert_duration} window"
  }
  
  conditions {
    display_name = "High privilege escalation rate"
    
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/security/privilege_escalation\""
      duration        = var.alert_duration
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.alert_threshold_value
      
      aggregations {
        alignment_period   = var.alert_duration
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  combiner = "OR"
  
  # Configure notification channels (can be extended)
  notification_channels = []
  
  # Add severity labels
  user_labels = merge(local.common_labels, {
    severity = "high"
    type     = "security"
  })
  
  depends_on = [google_project_service.required_apis]
}

# Create notification channel for Slack (example)
resource "google_monitoring_notification_channel" "slack_channel" {
  count = 0 # Disabled by default - enable and configure as needed
  
  display_name = "Slack Security Alerts"
  type         = "slack"
  
  labels = {
    url = "YOUR_SLACK_WEBHOOK_URL" # Replace with actual webhook URL
  }
  
  user_labels = local.common_labels
}

# Create function code files
resource "local_file" "main_py" {
  content = templatefile("${path.module}/templates/main.py.tpl", {
    bucket_name = google_storage_bucket.privilege_audit_logs.name
    project_id  = var.project_id
  })
  filename = "${path.module}/function_code/main.py"
  
  lifecycle {
    ignore_changes = [content]
  }
}

resource "local_file" "requirements_txt" {
  content = file("${path.module}/templates/requirements.txt")
  filename = "${path.module}/function_code/requirements.txt"
  
  lifecycle {
    ignore_changes = [content]
  }
}