# Main Terraform Configuration for API Governance and Compliance Monitoring
# This file defines the complete infrastructure for automated API governance
# using Apigee X, Cloud Logging, Eventarc, and Cloud Functions

# Data sources for current project information
data "google_client_config" "current" {}

data "google_project" "current" {
  project_id = var.project_id
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Common resource naming
  resource_suffix = random_id.suffix.hex
  common_labels = merge(var.labels, {
    resource-suffix = local.resource_suffix
  })
  
  # Function source code directory
  function_source_dir = "${path.module}/function_code"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "apigee.googleapis.com",
    "logging.googleapis.com",
    "bigquery.googleapis.com",
    "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  # Prevent accidental deletion of critical APIs
  disable_on_destroy = false
}

# ============================================================================
# APIGEE X ORGANIZATION AND ENVIRONMENT
# ============================================================================

# Apigee X Organization - Main API management platform
resource "google_apigee_organization" "main" {
  count = var.enable_apigee_organization ? 1 : 0

  project_id                           = var.project_id
  analytics_region                     = var.apigee_analytics_region
  display_name                         = "API Governance Organization"
  description                          = "Apigee X organization for API governance and compliance monitoring"
  billing_type                         = var.apigee_billing_type
  disable_vpc_peering                  = true
  retention                           = "MINIMUM"
  
  # Properties for enhanced security and governance
  properties {
    property {
      name  = "features.hybrid.enabled"
      value = "false"
    }
    property {
      name  = "features.mart.connect.enabled"
      value = "true"
    }
  }

  depends_on = [
    google_project_service.required_apis["apigee.googleapis.com"],
    google_project_service.required_apis["cloudresourcemanager.googleapis.com"]
  ]
}

# Apigee Environment for API governance
resource "google_apigee_environment" "governance" {
  count = var.enable_apigee_organization ? 1 : 0

  name         = var.apigee_environment_name
  display_name = var.apigee_environment_display_name
  description  = "Environment for API governance and compliance monitoring"
  org_id       = google_apigee_organization.main[0].id
  type         = "COMPREHENSIVE"

  depends_on = [google_apigee_organization.main]
}

# ============================================================================
# CLOUD STORAGE FOR FUNCTION SOURCE CODE
# ============================================================================

# Storage bucket for Cloud Functions source code
resource "google_storage_bucket" "function_source" {
  name          = "${var.project_id}-${var.resource_prefix}-functions-${local.resource_suffix}"
  location      = var.bigquery_location
  force_destroy = var.storage_force_destroy

  # Enable uniform bucket-level access for security
  uniform_bucket_level_access = true

  # Versioning for source code management
  versioning {
    enabled = var.storage_versioning_enabled
  }

  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_days
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis["storage.googleapis.com"]]
}

# Storage bucket for API configuration files
resource "google_storage_bucket" "api_configs" {
  name          = "${var.project_id}-${var.resource_prefix}-configs-${local.resource_suffix}"
  location      = var.bigquery_location
  force_destroy = var.storage_force_destroy

  uniform_bucket_level_access = true

  versioning {
    enabled = var.storage_versioning_enabled
  }

  # Lifecycle management for configuration files
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_days * 2  # Keep configs longer
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis["storage.googleapis.com"]]
}

# ============================================================================
# BIGQUERY FOR LOG ANALYTICS
# ============================================================================

# BigQuery dataset for API governance logs
resource "google_bigquery_dataset" "api_logs" {
  count = var.enable_bigquery_export ? 1 : 0

  dataset_id                 = var.bigquery_dataset_id
  friendly_name              = "API Governance Logs"
  description                = "Dataset for storing API governance and compliance logs"
  location                   = var.bigquery_location
  delete_contents_on_destroy = var.storage_force_destroy

  # Default table expiration for cost management
  default_table_expiration_ms = var.bigquery_table_expiration_days * 24 * 60 * 60 * 1000

  # Access control
  access {
    role          = "OWNER"
    user_by_email = data.google_client_config.current.access_token != null ? data.google_project.current.number : null
  }

  access {
    role   = "READER"
    domain = "google.com"
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis["bigquery.googleapis.com"]]
}

# BigQuery table for structured API event logs
resource "google_bigquery_table" "api_events" {
  count = var.enable_bigquery_export ? 1 : 0

  dataset_id = google_bigquery_dataset.api_logs[0].dataset_id
  table_id   = "api_events"

  # Time-partitioned table for efficient queries
  time_partitioning {
    type          = "DAY"
    field         = "timestamp"
    expiration_ms = var.bigquery_table_expiration_days * 24 * 60 * 60 * 1000
  }

  # Clustering for query optimization
  clustering = ["api_proxy", "response_code", "severity"]

  schema = jsonencode([
    {
      name        = "timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "Event timestamp"
    },
    {
      name        = "api_proxy"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "API proxy name"
    },
    {
      name        = "response_code"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "HTTP response code"
    },
    {
      name        = "request_size"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Request size in bytes"
    },
    {
      name        = "response_size"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Response size in bytes"
    },
    {
      name        = "latency_ms"
      type        = "INTEGER"
      mode        = "NULLABLE"
      description = "Request latency in milliseconds"
    },
    {
      name        = "client_ip"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Client IP address"
    },
    {
      name        = "user_agent"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "User agent string"
    },
    {
      name        = "api_key"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "API key used (hashed)"
    },
    {
      name        = "policy_violations"
      type        = "STRING"
      mode        = "REPEATED"
      description = "List of policy violations"
    },
    {
      name        = "severity"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Log severity level"
    },
    {
      name        = "compliance_status"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Compliance status (PASS/FAIL/WARNING)"
    }
  ])

  labels = local.common_labels

  depends_on = [google_bigquery_dataset.api_logs]
}

# ============================================================================
# CLOUD LOGGING SINKS
# ============================================================================

# Log sink for Apigee audit logs to BigQuery
resource "google_logging_project_sink" "apigee_audit_logs" {
  count = var.enable_bigquery_export ? 1 : 0

  name        = "${var.resource_prefix}-apigee-audit-sink"
  description = "Sink for Apigee audit logs to BigQuery"
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.api_logs[0].dataset_id}"

  # Filter for Apigee-related audit logs
  filter = <<-EOF
    resource.type="apigee_organization" OR
    resource.type="apigee_environment" OR
    (protoPayload.serviceName="apigee.googleapis.com" AND
     protoPayload.methodName!="google.cloud.location.Locations.ListLocations")
  EOF

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }

  depends_on = [
    google_bigquery_dataset.api_logs,
    google_project_service.required_apis["logging.googleapis.com"]
  ]
}

# Log sink for real-time compliance monitoring
resource "google_logging_project_sink" "compliance_events" {
  name        = "${var.resource_prefix}-compliance-events"
  description = "Sink for real-time compliance monitoring events"
  destination = "pubsub.googleapis.com/projects/${var.project_id}/topics/${google_pubsub_topic.api_governance_events.name}"

  # Filter for high-severity events and policy violations
  filter = <<-EOF
    (resource.type="apigee_organization" OR resource.type="apigee_environment") AND
    (severity>=WARNING OR
     protoPayload.authenticationInfo.principalEmail="" OR
     protoPayload.resourceName:("/policies/") OR
     protoPayload.methodName:("CreatePolicy" OR "UpdatePolicy" OR "DeletePolicy"))
  EOF

  unique_writer_identity = true

  depends_on = [
    google_pubsub_topic.api_governance_events,
    google_project_service.required_apis["logging.googleapis.com"]
  ]
}

# ============================================================================
# PUB/SUB FOR EVENT PROCESSING
# ============================================================================

# Pub/Sub topic for API governance events
resource "google_pubsub_topic" "api_governance_events" {
  name = "${var.resource_prefix}-events-${local.resource_suffix}"

  # Message retention for event replay
  message_retention_duration = var.pubsub_message_retention_duration

  # Schema for message validation
  schema_settings {
    schema   = google_pubsub_schema.api_event_schema.id
    encoding = "JSON"
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis["pubsub.googleapis.com"]]
}

# Pub/Sub schema for API events
resource "google_pubsub_schema" "api_event_schema" {
  name = "${var.resource_prefix}-event-schema"
  type = "AVRO"

  definition = jsonencode({
    type = "record"
    name = "ApiEvent"
    fields = [
      {
        name = "timestamp"
        type = "string"
      },
      {
        name = "severity"
        type = "string"
      },
      {
        name = "api_proxy"
        type = ["null", "string"]
        default = null
      },
      {
        name = "violation_type"
        type = ["null", "string"]
        default = null
      },
      {
        name = "compliance_status"
        type = ["null", "string"]
        default = null
      }
    ]
  })

  depends_on = [google_project_service.required_apis["pubsub.googleapis.com"]]
}

# Pub/Sub subscription for compliance monitoring function
resource "google_pubsub_subscription" "compliance_monitoring" {
  name  = "${var.resource_prefix}-compliance-monitoring"
  topic = google_pubsub_topic.api_governance_events.id

  # Acknowledgment deadline
  ack_deadline_seconds = var.pubsub_ack_deadline_seconds

  # Message retention
  message_retention_duration = var.pubsub_message_retention_duration

  # Retry policy for failed messages
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Dead letter policy for unprocessable messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }

  # Exponential backoff for retries
  expiration_policy {
    ttl = "300000s"  # 83 hours
  }

  labels = local.common_labels

  depends_on = [google_pubsub_topic.api_governance_events]
}

# Dead letter topic for failed messages
resource "google_pubsub_topic" "dead_letter" {
  name = "${var.resource_prefix}-dead-letter-${local.resource_suffix}"

  message_retention_duration = "604800s"  # 7 days

  labels = local.common_labels

  depends_on = [google_project_service.required_apis["pubsub.googleapis.com"]]
}

# ============================================================================
# SERVICE ACCOUNTS FOR CLOUD FUNCTIONS
# ============================================================================

# Service account for compliance monitoring function
resource "google_service_account" "compliance_monitor_sa" {
  account_id   = "${var.resource_prefix}-compliance-monitor"
  display_name = "API Compliance Monitor Service Account"
  description  = "Service account for API compliance monitoring Cloud Function"
}

# Service account for policy enforcement function
resource "google_service_account" "policy_enforcer_sa" {
  account_id   = "${var.resource_prefix}-policy-enforcer"
  display_name = "API Policy Enforcer Service Account"
  description  = "Service account for API policy enforcement Cloud Function"
}

# IAM bindings for compliance monitor service account
resource "google_project_iam_member" "compliance_monitor_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/bigquery.dataEditor",
    "roles/pubsub.subscriber",
    "roles/apigee.readOnlyAdmin"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.compliance_monitor_sa.email}"
}

# IAM bindings for policy enforcer service account
resource "google_project_iam_member" "policy_enforcer_roles" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/pubsub.subscriber",
    "roles/apigee.admin"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.policy_enforcer_sa.email}"
}

# ============================================================================
# CLOUD FUNCTIONS FOR COMPLIANCE PROCESSING
# ============================================================================

# Archive source code for compliance monitoring function
data "archive_file" "compliance_monitor_source" {
  type        = "zip"
  output_path = "${path.module}/compliance-monitor-source.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/compliance_monitor.py.tpl", {
      project_id = var.project_id
      dataset_id = var.enable_bigquery_export ? google_bigquery_dataset.api_logs[0].dataset_id : ""
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_templates/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload compliance monitor source to Cloud Storage
resource "google_storage_bucket_object" "compliance_monitor_source" {
  name   = "compliance-monitor-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.compliance_monitor_source.output_path

  depends_on = [data.archive_file.compliance_monitor_source]
}

# Cloud Function for API compliance monitoring
resource "google_cloudfunctions2_function" "compliance_monitor" {
  name        = "${var.resource_prefix}-compliance-monitor"
  location    = var.region
  description = "Monitors API compliance and processes governance events"

  build_config {
    runtime     = var.function_runtime
    entry_point = "monitor_api_compliance"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.compliance_monitor_source.name
      }
    }
  }

  service_config {
    max_instance_count = var.function_max_instances
    min_instance_count = var.function_min_instances
    available_memory   = var.function_memory
    timeout_seconds    = var.function_timeout

    environment_variables = {
      PROJECT_ID                    = var.project_id
      DATASET_ID                   = var.enable_bigquery_export ? google_bigquery_dataset.api_logs[0].dataset_id : ""
      GOVERNANCE_TOPIC             = google_pubsub_topic.api_governance_events.name
      ERROR_RATE_THRESHOLD         = var.monitoring_error_rate_threshold
      ENABLE_BIGQUERY_EXPORT       = var.enable_bigquery_export
    }

    service_account_email = google_service_account.compliance_monitor_sa.email
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.api_governance_events.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis["cloudfunctions.googleapis.com"],
    google_project_service.required_apis["cloudbuild.googleapis.com"],
    google_storage_bucket_object.compliance_monitor_source
  ]
}

# Archive source code for policy enforcement function
data "archive_file" "policy_enforcer_source" {
  type        = "zip"
  output_path = "${path.module}/policy-enforcer-source.zip"
  
  source {
    content = templatefile("${path.module}/function_templates/policy_enforcer.py.tpl", {
      project_id = var.project_id
      apigee_org = var.enable_apigee_organization ? google_apigee_organization.main[0].name : ""
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_templates/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload policy enforcer source to Cloud Storage
resource "google_storage_bucket_object" "policy_enforcer_source" {
  name   = "policy-enforcer-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.policy_enforcer_source.output_path

  depends_on = [data.archive_file.policy_enforcer_source]
}

# Cloud Function for automated policy enforcement
resource "google_cloudfunctions2_function" "policy_enforcer" {
  name        = "${var.resource_prefix}-policy-enforcer"
  location    = var.region
  description = "Enforces API governance policies and implements automated responses"

  build_config {
    runtime     = var.function_runtime
    entry_point = "enforce_api_policies"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.policy_enforcer_source.name
      }
    }
  }

  service_config {
    max_instance_count = var.function_max_instances
    min_instance_count = var.function_min_instances
    available_memory   = var.function_memory
    timeout_seconds    = var.function_timeout * 2  # Policy enforcement may take longer

    environment_variables = {
      PROJECT_ID           = var.project_id
      APIGEE_ORG          = var.enable_apigee_organization ? google_apigee_organization.main[0].name : ""
      APIGEE_ENV          = var.enable_apigee_organization ? google_apigee_environment.governance[0].name : ""
      GOVERNANCE_TOPIC    = google_pubsub_topic.api_governance_events.name
    }

    service_account_email = google_service_account.policy_enforcer_sa.email
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.api_governance_events.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis["cloudfunctions.googleapis.com"],
    google_project_service.required_apis["cloudbuild.googleapis.com"],
    google_storage_bucket_object.policy_enforcer_source
  ]
}

# ============================================================================
# EVENTARC TRIGGERS FOR AUTOMATED RESPONSE
# ============================================================================

# Service account for Eventarc triggers
resource "google_service_account" "eventarc_sa" {
  count = var.enable_eventarc_triggers ? 1 : 0

  account_id   = "${var.resource_prefix}-eventarc"
  display_name = "Eventarc Service Account"
  description  = "Service account for Eventarc triggers in API governance"
}

# IAM bindings for Eventarc service account
resource "google_project_iam_member" "eventarc_roles" {
  for_each = var.enable_eventarc_triggers ? toset([
    "roles/eventarc.eventReceiver",
    "roles/run.invoker",
    "roles/cloudfunctions.invoker"
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.eventarc_sa[0].email}"
}

# Eventarc trigger for API configuration changes
resource "google_eventarc_trigger" "api_config_changes" {
  count = var.enable_eventarc_triggers ? 1 : 0

  name     = "${var.resource_prefix}-config-changes"
  location = var.region

  # Trigger on Cloud Storage object finalization (new config files)
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.storage.object.v1.finalized"
  }

  matching_criteria {
    attribute = "bucket"
    value     = google_storage_bucket.api_configs.name
  }

  destination {
    cloud_run_service {
      service = google_cloudfunctions2_function.policy_enforcer.name
      region  = var.region
    }
  }

  service_account = google_service_account.eventarc_sa[0].email

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis["eventarc.googleapis.com"],
    google_service_account.eventarc_sa
  ]
}

# Eventarc trigger for critical security violations
resource "google_eventarc_trigger" "security_violations" {
  count = var.enable_eventarc_triggers ? 1 : 0

  name     = "${var.resource_prefix}-security-violations"
  location = var.region

  # Trigger on Cloud Audit Log events
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.audit.log.v1.written"
  }

  matching_criteria {
    attribute = "serviceName"
    value     = "apigee.googleapis.com"
  }

  matching_criteria {
    attribute = "methodName"
    value     = "google.cloud.apigee.v1.SecurityReportsService.CreateSecurityReport"
  }

  destination {
    cloud_run_service {
      service = google_cloudfunctions2_function.compliance_monitor.name
      region  = var.region
    }
  }

  service_account = google_service_account.eventarc_sa[0].email

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis["eventarc.googleapis.com"],
    google_service_account.eventarc_sa
  ]
}

# ============================================================================
# MONITORING AND ALERTING
# ============================================================================

# Notification channel for email alerts
resource "google_monitoring_notification_channel" "email_alerts" {
  count = var.enable_monitoring_alerts ? 1 : 0

  display_name = "API Governance Email Alerts"
  type         = "email"
  
  labels = {
    email_address = var.monitoring_notification_email
  }
  
  user_labels = local.common_labels

  depends_on = [google_project_service.required_apis["monitoring.googleapis.com"]]
}

# Alert policy for API compliance violations
resource "google_monitoring_alert_policy" "compliance_violations" {
  count = var.enable_monitoring_alerts ? 1 : 0

  display_name = "API Compliance Violations"
  combiner     = "OR"

  conditions {
    display_name = "High API Error Rate"
    
    condition_threshold {
      filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.compliance_monitor.name}\""
      duration = "300s"
      comparison = "COMPARISON_GT"
      threshold_value = var.monitoring_error_rate_threshold
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.label.function_name"]
      }
    }
  }

  conditions {
    display_name = "Function Execution Failures"
    
    condition_threshold {
      filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\""
      duration = "300s"
      comparison = "COMPARISON_GT"
      threshold_value = 5
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.function_name"]
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email_alerts[0].name
  ]

  alert_strategy {
    auto_close = var.monitoring_alert_auto_close
    
    notification_rate_limit {
      period = "300s"
    }
  }

  documentation {
    content = "API compliance violations detected. Check the governance dashboard for details."
    mime_type = "text/markdown"
  }

  labels = local.common_labels

  depends_on = [
    google_cloudfunctions2_function.compliance_monitor,
    google_monitoring_notification_channel.email_alerts
  ]
}

# Alert policy for Apigee X infrastructure issues
resource "google_monitoring_alert_policy" "apigee_infrastructure" {
  count = var.enable_monitoring_alerts && var.enable_apigee_organization ? 1 : 0

  display_name = "Apigee X Infrastructure Issues"
  combiner     = "OR"

  conditions {
    display_name = "Apigee Organization Unavailable"
    
    condition_threshold {
      filter = "resource.type=\"apigee_organization\""
      duration = "300s"
      comparison = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email_alerts[0].name
  ]

  alert_strategy {
    auto_close = var.monitoring_alert_auto_close
  }

  documentation {
    content = "Apigee X infrastructure issues detected. Check the Apigee console for details."
    mime_type = "text/markdown"
  }

  labels = local.common_labels

  depends_on = [
    google_apigee_organization.main,
    google_monitoring_notification_channel.email_alerts
  ]
}

# ============================================================================
# IAM PERMISSIONS FOR LOG SINK WRITERS
# ============================================================================

# Grant BigQuery Data Editor role to log sink writer
resource "google_project_iam_member" "log_sink_bigquery" {
  count = var.enable_bigquery_export ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.apigee_audit_logs[0].writer_identity
}

# Grant Pub/Sub Publisher role to log sink writer
resource "google_project_iam_member" "log_sink_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.compliance_events.writer_identity
}