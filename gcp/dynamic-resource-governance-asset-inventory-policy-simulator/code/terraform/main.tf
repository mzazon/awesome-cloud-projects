# Main Terraform Configuration for Dynamic Resource Governance
# This file creates the complete governance infrastructure using Google Cloud services

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for computed resource names
locals {
  # Resource naming with environment and random suffix
  resource_suffix = "${var.environment}-${random_id.suffix.hex}"
  
  # Full resource names
  pubsub_topic_name         = "${var.resource_prefix}-${var.pubsub_topic_name}-${local.resource_suffix}"
  pubsub_subscription_name  = "${var.resource_prefix}-${var.pubsub_subscription_name}-${local.resource_suffix}"
  asset_feed_name          = "${var.resource_prefix}-${var.asset_feed_name}-${local.resource_suffix}"
  service_account_name     = "${var.resource_prefix}-${var.service_account_name}-${local.resource_suffix}"
  
  # Function names
  asset_analyzer_name   = "${var.resource_prefix}-asset-analyzer-${local.resource_suffix}"
  policy_validator_name = "${var.resource_prefix}-policy-validator-${local.resource_suffix}"
  compliance_engine_name = "${var.resource_prefix}-compliance-engine-${local.resource_suffix}"
  
  # Storage bucket for Cloud Functions source code
  functions_bucket_name = "${var.resource_prefix}-functions-${local.resource_suffix}"
  
  # Combined labels
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    region      = var.region
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "apis" {
  for_each = toset(var.required_apis)
  
  project = var.project_id
  service = each.value
  
  # Prevent accidental deletion of APIs
  disable_on_destroy = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create service account for governance automation
resource "google_service_account" "governance_sa" {
  account_id   = local.service_account_name
  display_name = var.service_account_display_name
  description  = "Service account for automated governance and compliance operations"
  project      = var.project_id
  
  depends_on = [google_project_service.apis]
}

# Assign IAM roles to the governance service account
resource "google_project_iam_member" "governance_roles" {
  for_each = toset(var.governance_roles)
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.governance_sa.email}"
  
  depends_on = [google_service_account.governance_sa]
}

# Create Pub/Sub topic for asset change notifications
resource "google_pubsub_topic" "asset_changes" {
  name    = local.pubsub_topic_name
  project = var.project_id
  labels  = local.common_labels
  
  # Message retention configuration
  message_retention_duration = var.pubsub_message_retention
  
  depends_on = [google_project_service.apis]
}

# Create Pub/Sub subscription for compliance processing
resource "google_pubsub_subscription" "compliance_subscription" {
  name    = local.pubsub_subscription_name
  project = var.project_id
  topic   = google_pubsub_topic.asset_changes.name
  labels  = local.common_labels
  
  # Acknowledgment deadline
  ack_deadline_seconds = var.pubsub_ack_deadline
  
  # Message retention configuration
  message_retention_duration = var.pubsub_message_retention
  retain_acked_messages      = false
  
  # Exponential backoff configuration
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Dead letter configuration
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letters.id
    max_delivery_attempts = 5
  }
  
  depends_on = [google_pubsub_topic.asset_changes]
}

# Create dead letter topic for failed messages
resource "google_pubsub_topic" "dead_letters" {
  name    = "${local.pubsub_topic_name}-dead-letters"
  project = var.project_id
  labels  = local.common_labels
  
  depends_on = [google_project_service.apis]
}

# Create Cloud Asset Inventory feed
resource "google_cloud_asset_folder_feed" "governance_feed" {
  # Note: This creates a project-level feed. For organization-level feeds,
  # use google_cloud_asset_organization_feed instead
  billing_project = var.project_id
  folder          = "folders/${var.project_id}" # Adjust for actual folder structure
  feed_id         = local.asset_feed_name
  content_type    = var.asset_content_type
  
  asset_types = var.asset_types
  
  feed_output_config {
    pubsub_destination {
      topic = google_pubsub_topic.asset_changes.id
    }
  }
  
  depends_on = [
    google_pubsub_topic.asset_changes,
    google_project_service.apis
  ]
}

# Alternative: Project-level asset feed (more common for single-project deployments)
resource "google_cloud_asset_project_feed" "governance_project_feed" {
  project      = var.project_id
  feed_id      = "${local.asset_feed_name}-project"
  content_type = var.asset_content_type
  
  asset_types = var.asset_types
  
  feed_output_config {
    pubsub_destination {
      topic = google_pubsub_topic.asset_changes.id
    }
  }
  
  depends_on = [
    google_pubsub_topic.asset_changes,
    google_project_service.apis
  ]
}

# Create Cloud Storage bucket for Cloud Functions source code
resource "google_storage_bucket" "functions_bucket" {
  name          = local.functions_bucket_name
  project       = var.project_id
  location      = var.region
  force_destroy = true
  
  labels = local.common_labels
  
  # Enable versioning for function source code
  versioning {
    enabled = true
  }
  
  # Lifecycle management
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  depends_on = [google_project_service.apis]
}

# Create ZIP archive for Asset Analyzer function
data "archive_file" "asset_analyzer_zip" {
  type        = "zip"
  output_path = "${path.module}/asset_analyzer.zip"
  
  source {
    content = templatefile("${path.module}/functions/asset_analyzer.py", {
      project_id = var.project_id
      high_risk_types = jsonencode(var.high_risk_asset_types)
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload Asset Analyzer function source to Cloud Storage
resource "google_storage_bucket_object" "asset_analyzer_source" {
  name   = "asset_analyzer_${data.archive_file.asset_analyzer_zip.output_md5}.zip"
  bucket = google_storage_bucket.functions_bucket.name
  source = data.archive_file.asset_analyzer_zip.output_path
  
  depends_on = [google_storage_bucket.functions_bucket]
}

# Create Asset Analyzer Cloud Function
resource "google_cloudfunctions2_function" "asset_analyzer" {
  name        = local.asset_analyzer_name
  location    = var.region
  project     = var.project_id
  description = "Analyzes asset changes and assesses risk levels for governance"
  
  labels = local.common_labels
  
  build_config {
    runtime     = var.functions_runtime
    entry_point = "analyze_asset_change"
    
    source {
      storage_source {
        bucket = google_storage_bucket.functions_bucket.name
        object = google_storage_bucket_object.asset_analyzer_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.asset_analyzer_config.max_instances
    min_instance_count    = var.asset_analyzer_config.min_instances
    available_memory      = "${var.asset_analyzer_config.memory_mb}M"
    timeout_seconds       = var.asset_analyzer_config.timeout_seconds
    available_cpu         = var.asset_analyzer_config.cpu
    ingress_settings      = var.asset_analyzer_config.ingress_settings
    all_traffic_on_latest_revision = true
    
    service_account_email = google_service_account.governance_sa.email
    
    environment_variables = {
      PROJECT_ID = var.project_id
      REGION     = var.region
      HIGH_RISK_TYPES = jsonencode(var.high_risk_asset_types)
    }
  }
  
  event_trigger {
    event_type   = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic = google_pubsub_topic.asset_changes.id
    retry_policy = "RETRY_POLICY_RETRY"
  }
  
  depends_on = [
    google_service_account.governance_sa,
    google_project_iam_member.governance_roles,
    google_storage_bucket_object.asset_analyzer_source
  ]
}

# Create ZIP archive for Policy Validator function
data "archive_file" "policy_validator_zip" {
  type        = "zip"
  output_path = "${path.module}/policy_validator.zip"
  
  source {
    content = templatefile("${path.module}/functions/policy_validator.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload Policy Validator function source to Cloud Storage
resource "google_storage_bucket_object" "policy_validator_source" {
  name   = "policy_validator_${data.archive_file.policy_validator_zip.output_md5}.zip"
  bucket = google_storage_bucket.functions_bucket.name
  source = data.archive_file.policy_validator_zip.output_path
  
  depends_on = [google_storage_bucket.functions_bucket]
}

# Create Policy Validator Cloud Function
resource "google_cloudfunctions2_function" "policy_validator" {
  name        = local.policy_validator_name
  location    = var.region
  project     = var.project_id
  description = "Validates policy changes using Policy Simulator"
  
  labels = local.common_labels
  
  build_config {
    runtime     = var.functions_runtime
    entry_point = "validate_policy_changes"
    
    source {
      storage_source {
        bucket = google_storage_bucket.functions_bucket.name
        object = google_storage_bucket_object.policy_validator_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.policy_validator_config.max_instances
    min_instance_count    = var.policy_validator_config.min_instances
    available_memory      = "${var.policy_validator_config.memory_mb}M"
    timeout_seconds       = var.policy_validator_config.timeout_seconds
    available_cpu         = var.policy_validator_config.cpu
    ingress_settings      = var.policy_validator_config.ingress_settings
    all_traffic_on_latest_revision = true
    
    service_account_email = google_service_account.governance_sa.email
    
    environment_variables = {
      PROJECT_ID = var.project_id
      REGION     = var.region
    }
  }
  
  depends_on = [
    google_service_account.governance_sa,
    google_project_iam_member.governance_roles,
    google_storage_bucket_object.policy_validator_source
  ]
}

# Create ZIP archive for Compliance Engine function
data "archive_file" "compliance_engine_zip" {
  type        = "zip"
  output_path = "${path.module}/compliance_engine.zip"
  
  source {
    content = templatefile("${path.module}/functions/compliance_engine.py", {
      project_id = var.project_id
      compliance_policies = jsonencode(var.compliance_policies)
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload Compliance Engine function source to Cloud Storage
resource "google_storage_bucket_object" "compliance_engine_source" {
  name   = "compliance_engine_${data.archive_file.compliance_engine_zip.output_md5}.zip"
  bucket = google_storage_bucket.functions_bucket.name
  source = data.archive_file.compliance_engine_zip.output_path
  
  depends_on = [google_storage_bucket.functions_bucket]
}

# Create Compliance Engine Cloud Function
resource "google_cloudfunctions2_function" "compliance_engine" {
  name        = local.compliance_engine_name
  location    = var.region
  project     = var.project_id
  description = "Central compliance engine for governance automation and enforcement"
  
  labels = local.common_labels
  
  build_config {
    runtime     = var.functions_runtime
    entry_point = "enforce_compliance"
    
    source {
      storage_source {
        bucket = google_storage_bucket.functions_bucket.name
        object = google_storage_bucket_object.compliance_engine_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = var.compliance_engine_config.max_instances
    min_instance_count    = var.compliance_engine_config.min_instances
    available_memory      = "${var.compliance_engine_config.memory_mb}M"
    timeout_seconds       = var.compliance_engine_config.timeout_seconds
    available_cpu         = var.compliance_engine_config.cpu
    ingress_settings      = var.compliance_engine_config.ingress_settings
    all_traffic_on_latest_revision = true
    
    service_account_email = google_service_account.governance_sa.email
    
    environment_variables = {
      PROJECT_ID = var.project_id
      REGION     = var.region
      COMPLIANCE_POLICIES = jsonencode(var.compliance_policies)
      POLICY_VALIDATOR_URL = google_cloudfunctions2_function.policy_validator.service_config[0].uri
    }
  }
  
  event_trigger {
    event_type   = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic = google_pubsub_topic.asset_changes.id
    retry_policy = "RETRY_POLICY_RETRY"
  }
  
  depends_on = [
    google_service_account.governance_sa,
    google_project_iam_member.governance_roles,
    google_storage_bucket_object.compliance_engine_source,
    google_cloudfunctions2_function.policy_validator
  ]
}

# Create Cloud Monitoring alerts for governance system (optional)
resource "google_monitoring_alert_policy" "governance_alerts" {
  count        = var.enable_monitoring ? 1 : 0
  display_name = "Governance System Alerts"
  project      = var.project_id
  
  documentation {
    content = "Alerts for the dynamic resource governance system"
  }
  
  conditions {
    display_name = "Cloud Function Errors"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=~\"${var.resource_prefix}-.*-${local.resource_suffix}\""
      duration       = "300s"
      comparison     = "COMPARISON_GT"
      threshold_value = 5
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  # Add notification channels if provided
  dynamic "notification_channels" {
    for_each = var.alert_notification_channels
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [
    google_cloudfunctions2_function.asset_analyzer,
    google_cloudfunctions2_function.policy_validator,
    google_cloudfunctions2_function.compliance_engine
  ]
}

# Create Cloud Logging sinks for governance events (optional)
resource "google_logging_project_sink" "governance_sink" {
  name        = "${var.resource_prefix}-governance-sink-${local.resource_suffix}"
  project     = var.project_id
  destination = "storage.googleapis.com/${google_storage_bucket.governance_logs.name}"
  
  # Filter for governance-related logs
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=~\"${var.resource_prefix}-.*-${local.resource_suffix}\""
  
  # Create a unique writer identity for this sink
  unique_writer_identity = true
  
  depends_on = [google_storage_bucket.governance_logs]
}

# Create Cloud Storage bucket for governance logs
resource "google_storage_bucket" "governance_logs" {
  name          = "${var.resource_prefix}-governance-logs-${local.resource_suffix}"
  project       = var.project_id
  location      = var.region
  force_destroy = true
  
  labels = local.common_labels
  
  # Lifecycle management for logs
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
  
  depends_on = [google_project_service.apis]
}

# Grant the logging sink writer permission to the logs bucket
resource "google_storage_bucket_iam_member" "logs_writer" {
  bucket = google_storage_bucket.governance_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.governance_sink.writer_identity
  
  depends_on = [google_logging_project_sink.governance_sink]
}