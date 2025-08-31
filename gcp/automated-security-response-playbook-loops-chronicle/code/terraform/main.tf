# Main Terraform configuration for automated security response with Chronicle SOAR

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common resource naming and labeling
  resource_suffix = random_id.suffix.hex
  security_topic  = "${var.resource_prefix}-security-events-${local.resource_suffix}"
  response_topic  = "${var.resource_prefix}-response-actions-${local.resource_suffix}"
  
  # Merge common labels with environment-specific labels
  common_labels = merge(var.common_labels, {
    environment = var.environment
    created-by  = "terraform"
    timestamp   = formatdate("YYYY-MM-DD", timestamp())
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "securitycenter.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudbuild.googleapis.com",
    "compute.googleapis.com"
  ])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false

  timeouts {
    create = "30m"
    update = "40m"
  }
}

# Create service account for security automation
resource "google_service_account" "security_automation" {
  account_id   = "${var.resource_prefix}-automation-sa"
  display_name = "Security Automation Service Account"
  description  = "Service account for automated security response functions and Chronicle SOAR integration"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM roles for the security automation service account
resource "google_project_iam_member" "security_automation_roles" {
  for_each = toset([
    "roles/securitycenter.findingsEditor",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber",
    "roles/cloudfunctions.invoker",
    "roles/compute.instanceAdmin.v1",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/secretmanager.secretAccessor"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.security_automation.email}"

  depends_on = [google_service_account.security_automation]
}

# Pub/Sub topic for security events from Security Command Center
resource "google_pubsub_topic" "security_events" {
  name    = local.security_topic
  project = var.project_id
  labels  = local.common_labels

  message_retention_duration = var.pubsub_message_retention_duration

  # Enable message ordering for security event processing
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub topic for automated response actions
resource "google_pubsub_topic" "response_actions" {
  name    = local.response_topic
  project = var.project_id
  labels  = local.common_labels

  message_retention_duration = var.pubsub_message_retention_duration

  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub subscriptions for Cloud Functions
resource "google_pubsub_subscription" "security_events_subscription" {
  name    = "${local.security_topic}-subscription"
  topic   = google_pubsub_topic.security_events.name
  project = var.project_id
  labels  = local.common_labels

  # Configure subscription for reliable processing
  ack_deadline_seconds = 600
  retain_acked_messages = true
  message_retention_duration = "604800s"

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }

  expiration_policy {
    ttl = "86400s"  # 24 hours
  }
}

resource "google_pubsub_subscription" "response_actions_subscription" {
  name    = "${local.response_topic}-subscription"
  topic   = google_pubsub_topic.response_actions.name
  project = var.project_id
  labels  = local.common_labels

  ack_deadline_seconds = 600
  retain_acked_messages = true
  message_retention_duration = "604800s"

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }

  expiration_policy {
    ttl = "86400s"
  }
}

# Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name          = "${var.project_id}-${var.resource_prefix}-functions-${local.resource_suffix}"
  location      = var.region
  project       = var.project_id
  force_destroy = true

  labels = local.common_labels

  # Enable versioning for function code management
  versioning {
    enabled = true
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  # Security settings
  uniform_bucket_level_access = true

  depends_on = [google_project_service.required_apis]
}

# Create source code archive for threat enrichment function
data "archive_file" "threat_enrichment_source" {
  type        = "zip"
  output_path = "/tmp/threat-enrichment-${local.resource_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/functions/threat_enrichment.py", {
      project_id     = var.project_id
      response_topic = local.response_topic
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/functions/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload threat enrichment function source to Cloud Storage
resource "google_storage_bucket_object" "threat_enrichment_source" {
  name   = "threat-enrichment-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.threat_enrichment_source.output_path

  depends_on = [data.archive_file.threat_enrichment_source]
}

# Create source code archive for automated response function
data "archive_file" "automated_response_source" {
  type        = "zip"
  output_path = "/tmp/automated-response-${local.resource_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/functions/automated_response.py", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/functions/requirements_response.txt")
    filename = "requirements.txt"
  }
}

# Upload automated response function source to Cloud Storage
resource "google_storage_bucket_object" "automated_response_source" {
  name   = "automated-response-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.automated_response_source.output_path

  depends_on = [data.archive_file.automated_response_source]
}

# Cloud Function for threat intelligence enrichment
resource "google_cloudfunctions_function" "threat_enrichment" {
  name        = "${var.resource_prefix}-threat-enrichment-${local.resource_suffix}"
  description = "Enriches security alerts with threat intelligence for Chronicle SOAR processing"
  project     = var.project_id
  region      = var.region

  runtime               = var.threat_enrichment_function_config.runtime
  available_memory_mb   = var.threat_enrichment_function_config.memory_mb
  timeout               = var.threat_enrichment_function_config.timeout_seconds
  entry_point          = var.threat_enrichment_function_config.entry_point
  max_instances        = var.threat_enrichment_function_config.max_instances
  service_account_email = google_service_account.security_automation.email

  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.threat_enrichment_source.name

  # Pub/Sub trigger for security events
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.security_events.id
  }

  # Environment variables for function configuration
  environment_variables = {
    GCP_PROJECT     = var.project_id
    RESPONSE_TOPIC  = local.response_topic
    ENVIRONMENT     = var.environment
    LOG_LEVEL       = "INFO"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.threat_enrichment_source
  ]
}

# Cloud Function for automated security response
resource "google_cloudfunctions_function" "automated_response" {
  name        = "${var.resource_prefix}-automated-response-${local.resource_suffix}"
  description = "Executes automated security response actions based on Chronicle SOAR playbook decisions"
  project     = var.project_id
  region      = var.region

  runtime               = var.automated_response_function_config.runtime
  available_memory_mb   = var.automated_response_function_config.memory_mb
  timeout               = var.automated_response_function_config.timeout_seconds
  entry_point          = var.automated_response_function_config.entry_point
  max_instances        = var.automated_response_function_config.max_instances
  service_account_email = google_service_account.security_automation.email

  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.automated_response_source.name

  # Pub/Sub trigger for response actions
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.response_actions.id
  }

  # Environment variables for function configuration
  environment_variables = {
    GCP_PROJECT = var.project_id
    ENVIRONMENT = var.environment
    LOG_LEVEL   = "INFO"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.automated_response_source
  ]
}

# Security Command Center notification configuration
resource "google_scc_notification_config" "security_automation" {
  count = var.organization_id != "" ? 1 : 0

  config_id    = "${var.resource_prefix}-automation-${local.resource_suffix}"
  organization = var.organization_id
  description  = "Automated security response notification channel for Chronicle SOAR integration"

  pubsub_topic = google_pubsub_topic.security_events.id

  streaming_config {
    filter = var.security_notification_filter
  }

  depends_on = [
    google_project_service.required_apis,
    google_pubsub_topic.security_events
  ]
}

# Secret Manager secrets for Chronicle SOAR configuration
resource "google_secret_manager_secret" "chronicle_config" {
  count = var.enable_secret_manager ? 1 : 0

  secret_id = "${var.resource_prefix}-chronicle-config-${local.resource_suffix}"
  project   = var.project_id

  labels = local.common_labels

  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Chronicle SOAR playbook configuration as a secret
resource "google_secret_manager_secret_version" "chronicle_config" {
  count = var.enable_secret_manager ? 1 : 0

  secret = google_secret_manager_secret.chronicle_config[0].id

  secret_data = jsonencode({
    playbook_name = var.chronicle_soar_config.playbook_name
    playbook_loops = {
      entity_processing_loop = {
        loop_type       = "entities"
        max_iterations  = var.chronicle_soar_config.max_loop_iterations
        scope_lock      = var.chronicle_soar_config.enable_scope_lock
        actions = [
          {
            action_type = "threat_intelligence_lookup"
            parameters = {
              entity_placeholder   = "Loop.Entity"
              reputation_sources  = ["VirusTotal", "URLVoid", "AbuseIPDB"]
            }
          },
          {
            action_type = "conditional_block"
            condition   = "reputation_score > ${var.chronicle_soar_config.reputation_score_threshold}"
            true_actions = [
              {
                action_type   = "cloud_function_invoke"
                function_name = google_cloudfunctions_function.automated_response.name
                parameters = {
                  action      = "block_entity"
                  entity      = "Loop.Entity.value"
                  entity_type = "Loop.Entity.type"
                }
              }
            ]
          }
        ]
      }
      response_coordination_loop = {
        loop_type   = "list"
        list_source = "recommended_actions"
        delimiter   = ","
        actions = [
          {
            action_type   = "cloud_function_invoke"
            function_name = google_cloudfunctions_function.automated_response.name
            parameters = {
              action  = "Loop.item"
              context = "Entity.alert_context"
            }
          }
        ]
      }
    }
    notification_settings = {
      pubsub_topic             = google_pubsub_topic.response_actions.id
      notification_conditions = ["loop_completion", "high_severity_match"]
    }
  })
}

# Cloud Monitoring alert policies for security automation
resource "google_monitoring_alert_policy" "function_errors" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "${var.resource_prefix} Security Function Errors"
  project      = var.project_id

  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "High Error Rate - Threat Enrichment Function"

    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions_function.threat_enrichment.name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 5

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  conditions {
    display_name = "High Error Rate - Automated Response Function"

    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions_function.automated_response.name}\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = 5

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  # Notification channels for alerting
  dynamic "notification_channels" {
    for_each = var.notification_channels
    content {
      channel = notification_channels.value
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.threat_enrichment,
    google_cloudfunctions_function.automated_response
  ]
}

# Log sink for security automation audit trail
resource "google_logging_project_sink" "security_audit" {
  count = var.enable_audit_logging ? 1 : 0

  name = "${var.resource_prefix}-security-audit-${local.resource_suffix}"

  # Filter for security-related logs
  filter = <<-EOT
    (resource.type="cloud_function" AND 
     (resource.labels.function_name="${google_cloudfunctions_function.threat_enrichment.name}" OR
      resource.labels.function_name="${google_cloudfunctions_function.automated_response.name}")) OR
    (resource.type="pubsub_topic" AND 
     (resource.labels.topic_id="${local.security_topic}" OR
      resource.labels.topic_id="${local.response_topic}"))
  EOT

  # Export to Cloud Storage for long-term retention
  destination = "storage.googleapis.com/${google_storage_bucket.audit_logs[0].name}"

  # Use a unique writer identity
  unique_writer_identity = true

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for audit logs
resource "google_storage_bucket" "audit_logs" {
  count = var.enable_audit_logging ? 1 : 0

  name          = "${var.project_id}-${var.resource_prefix}-audit-logs-${local.resource_suffix}"
  location      = var.region
  project       = var.project_id
  force_destroy = true

  labels = local.common_labels

  # Lifecycle management for audit log retention
  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }

  # Security settings for audit logs
  uniform_bucket_level_access = true

  depends_on = [google_project_service.required_apis]
}

# IAM binding for log sink writer
resource "google_storage_bucket_iam_member" "audit_log_writer" {
  count = var.enable_audit_logging ? 1 : 0

  bucket = google_storage_bucket.audit_logs[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.security_audit[0].writer_identity

  depends_on = [google_logging_project_sink.security_audit]
}