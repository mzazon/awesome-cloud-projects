# Terraform configuration for GCP Compliance Violation Detection
# This configuration creates a complete compliance monitoring system using
# Cloud Audit Logs, Eventarc, Cloud Functions, and supporting services

# Local values for consistent naming and configuration
locals {
  project_id = var.project_id != "" ? var.project_id : data.google_project.current.project_id
  
  # Generate unique suffix for resource names to avoid conflicts
  random_suffix = random_id.suffix.hex
  
  # Resource names with consistent naming convention
  function_name           = "compliance-detector-${local.random_suffix}"
  trigger_name           = "audit-log-trigger-${local.random_suffix}"
  topic_name             = "compliance-alerts-${local.random_suffix}"
  subscription_name      = "${local.topic_name}-subscription"
  dataset_name           = "compliance_logs_${local.random_suffix}"
  sink_name              = "compliance-audit-sink"
  metric_name            = "compliance_violations"
  alert_policy_name      = "High Severity Compliance Violations"
  dashboard_name         = "Compliance Monitoring Dashboard"
  
  # Labels for resource organization and billing tracking
  common_labels = {
    project     = "compliance-monitoring"
    environment = var.environment
    recipe      = "compliance-violation-detection"
    managed_by  = "terraform"
  }
}

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current project information
data "google_project" "current" {}

# Data source to get current client configuration
data "google_client_config" "current" {}

# Enable required Google Cloud APIs for the compliance monitoring system
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "eventarc.googleapis.com",
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "monitoring.googleapis.com",
    "run.googleapis.com",        # Required for Cloud Functions 2nd gen
    "artifactregistry.googleapis.com",  # Required for storing function code
    "cloudbuild.googleapis.com"  # Required for building functions
  ])

  project = local.project_id
  service = each.key

  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create Pub/Sub topic for compliance alert distribution
resource "google_pubsub_topic" "compliance_alerts" {
  name    = local.topic_name
  project = local.project_id
  labels  = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for alert processing
resource "google_pubsub_subscription" "compliance_alerts" {
  name    = local.subscription_name
  topic   = google_pubsub_topic.compliance_alerts.name
  project = local.project_id
  labels  = local.common_labels

  # Configure message retention and acknowledgement
  message_retention_duration = "1200s"  # 20 minutes
  retain_acked_messages     = false
  ack_deadline_seconds      = 20

  # Dead letter policy for unprocessable messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.compliance_alerts_dlq.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# Dead letter queue for failed message processing
resource "google_pubsub_topic" "compliance_alerts_dlq" {
  name    = "${local.topic_name}-dlq"
  project = local.project_id
  labels  = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create BigQuery dataset for compliance violation storage and analysis
resource "google_bigquery_dataset" "compliance_logs" {
  dataset_id  = local.dataset_name
  project     = local.project_id
  location    = var.region
  description = "Compliance violation logs and analysis data warehouse"

  labels = local.common_labels

  # Configure access control and data governance
  access {
    role          = "OWNER"
    user_by_email = data.google_client_config.current.access_token != null ? null : var.dataset_owner_email
  }

  access {
    role          = "READER"
    special_group = "projectReaders"
  }

  access {
    role          = "WRITER"
    special_group = "projectWriters"
  }

  # Configure deletion protection and lifecycle
  delete_contents_on_destroy = var.environment != "production"

  depends_on = [google_project_service.required_apis]
}

# Create BigQuery table for storing violation records
resource "google_bigquery_table" "violations" {
  dataset_id          = google_bigquery_dataset.compliance_logs.dataset_id
  table_id            = "violations"
  project             = local.project_id
  description         = "Table storing detailed compliance violation records"
  deletion_protection = var.environment == "production"

  labels = local.common_labels

  # Define table schema for violation data
  schema = jsonencode([
    {
      name        = "timestamp"
      type        = "TIMESTAMP"
      mode        = "REQUIRED"
      description = "When the violation occurred"
    },
    {
      name        = "violation_type"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Type of compliance violation detected"
    },
    {
      name        = "severity"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Severity level: LOW, MEDIUM, HIGH, CRITICAL"
    },
    {
      name        = "resource"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Affected cloud resource identifier"
    },
    {
      name        = "principal"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "User or service account that triggered the violation"
    },
    {
      name        = "details"
      type        = "STRING"
      mode        = "NULLABLE"
      description = "Detailed description of the violation"
    },
    {
      name        = "remediation_status"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Current remediation status: PENDING, IN_PROGRESS, RESOLVED, IGNORED"
    },
    {
      name        = "project_id"
      type        = "STRING"
      mode        = "REQUIRED"
      description = "Google Cloud project where violation occurred"
    }
  ])

  # Configure table partitioning for performance
  time_partitioning {
    type                     = "DAY"
    field                    = "timestamp"
    require_partition_filter = false
    expiration_ms           = var.log_retention_days * 24 * 60 * 60 * 1000
  }

  # Configure table clustering for query optimization
  clustering = ["violation_type", "severity", "project_id"]
}

# Create Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = "${local.function_name}-source-${local.random_suffix}"
  location = var.region
  project  = local.project_id

  labels = local.common_labels

  # Configure bucket for function storage requirements
  uniform_bucket_level_access = true
  force_destroy              = true

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

# Create zip archive of Cloud Function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/compliance-function-${local.random_suffix}.zip"
  
  source {
    content = templatefile("${path.module}/function_code/index.js", {
      topic_name   = local.topic_name
      dataset_name = local.dataset_name
      project_id   = local.project_id
    })
    filename = "index.js"
  }

  source {
    content = templatefile("${path.module}/function_code/package.json", {})
    filename = "package.json"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "compliance-function-${local.random_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# Service account for Cloud Function with minimal required permissions
resource "google_service_account" "function_sa" {
  account_id   = "compliance-function-${local.random_suffix}"
  display_name = "Compliance Detection Function Service Account"
  description  = "Service account for compliance violation detection Cloud Function"
  project      = local.project_id
}

# Grant necessary IAM permissions to function service account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/bigquery.dataEditor",      # Write to BigQuery tables
    "roles/pubsub.publisher",         # Publish to Pub/Sub topics
    "roles/monitoring.metricWriter",  # Write custom metrics
    "roles/logging.logWriter"         # Write to Cloud Logging
  ])

  project = local.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Deploy Cloud Function for compliance violation detection
resource "google_cloudfunctions2_function" "compliance_detector" {
  name        = local.function_name
  location    = var.region
  project     = local.project_id
  description = "Analyzes Cloud Audit Logs for compliance violations"

  labels = local.common_labels

  build_config {
    runtime     = "nodejs20"
    entry_point = "analyzeAuditLog"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count               = var.function_max_instances
    min_instance_count               = var.function_min_instances
    available_memory                 = "512Mi"
    timeout_seconds                  = 540
    max_instance_request_concurrency = 100
    available_cpu                    = "1"
    
    environment_variables = {
      TOPIC_NAME   = local.topic_name
      DATASET_NAME = local.dataset_name
      PROJECT_ID   = local.project_id
      ENVIRONMENT  = var.environment
    }

    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_sa.email
  }

  # Configure event trigger for Cloud Audit Logs
  event_trigger {
    trigger_region        = var.region
    event_type           = "google.cloud.audit.log.v1.written"
    retry_policy         = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.function_sa.email
  }

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_project_iam_member.function_permissions
  ]
}

# Create log sink for routing audit logs to BigQuery
resource "google_logging_project_sink" "compliance_audit_sink" {
  name        = local.sink_name
  project     = local.project_id
  destination = "bigquery.googleapis.com/projects/${local.project_id}/datasets/${local.dataset_name}"

  # Filter for compliance-relevant audit logs
  filter = <<-EOT
    protoPayload.@type="type.googleapis.com/google.cloud.audit.AuditLog" AND
    (
      protoPayload.serviceName="iam.googleapis.com" OR
      protoPayload.serviceName="cloudresourcemanager.googleapis.com" OR
      protoPayload.serviceName="compute.googleapis.com" OR
      protoPayload.serviceName="storage.googleapis.com" OR
      protoPayload.serviceName="bigquery.googleapis.com"
    )
  EOT

  # Configure sink options
  unique_writer_identity = true
  bigquery_options {
    use_partitioned_tables = true
  }

  depends_on = [google_bigquery_dataset.compliance_logs]
}

# Grant BigQuery Data Editor permission to log sink service account
resource "google_bigquery_dataset_iam_member" "sink_writer" {
  dataset_id = google_bigquery_dataset.compliance_logs.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.compliance_audit_sink.writer_identity
  project    = local.project_id
}

# Create log-based metric for compliance violation monitoring
resource "google_logging_metric" "compliance_violations" {
  name    = local.metric_name
  project = local.project_id

  filter = <<-EOT
    resource.type="cloud_function" AND
    resource.labels.function_name="${local.function_name}" AND
    textPayload:"violation"
  EOT

  description = "Count of compliance violations detected by the monitoring system"

  metric_descriptor {
    metric_kind = "COUNTER"
    value_type  = "INT64"
    unit        = "1"
    
    labels {
      key         = "violation_type"
      value_type  = "STRING"
      description = "Type of compliance violation"
    }
    
    labels {
      key         = "severity"
      value_type  = "STRING"
      description = "Severity level of the violation"
    }
  }

  label_extractors = {
    "violation_type" = "EXTRACT(textPayload)"
    "severity"       = "EXTRACT(textPayload)"
  }

  depends_on = [google_project_service.required_apis]
}

# Create Cloud Monitoring alert policy for high-severity violations
resource "google_monitoring_alert_policy" "high_severity_violations" {
  display_name = local.alert_policy_name
  project      = local.project_id
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "High severity compliance violations detected"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${local.metric_name}\" AND resource.type=\"cloud_function\""
      duration        = "60s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["metric.labels.violation_type"]
      }

      trigger {
        count = 1
      }
    }
  }

  # Configure alert strategy
  alert_strategy {
    auto_close = "1800s"  # Auto-close after 30 minutes
    
    notification_rate_limit {
      period = "300s"  # Limit notifications to once every 5 minutes
    }
  }

  # Documentation for alert responders
  documentation {
    content = <<-EOT
      ## Compliance Violation Alert

      This alert indicates that high-severity compliance violations have been detected in your Google Cloud environment.

      ### Immediate Actions:
      1. Review the violation details in the BigQuery dataset: ${local.dataset_name}
      2. Check the Cloud Function logs for detailed violation information
      3. Investigate the affected resources and principals
      4. Implement appropriate remediation measures

      ### Resources:
      - Violations Table: `${local.project_id}.${local.dataset_name}.violations`
      - Function Logs: Cloud Functions > ${local.function_name} > Logs
      - Pub/Sub Topic: ${local.topic_name}

      Contact your security team if you need assistance with violation remediation.
    EOT
    mime_type = "text/markdown"
  }

  depends_on = [
    google_logging_metric.compliance_violations,
    google_cloudfunctions2_function.compliance_detector
  ]
}

# Create Cloud Monitoring dashboard for compliance visibility
resource "google_monitoring_dashboard" "compliance_monitoring" {
  dashboard_json = jsonencode({
    displayName = local.dashboard_name
    
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Compliance Violations by Type"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"logging.googleapis.com/user/${local.metric_name}\""
                      aggregation = {
                        alignmentPeriod     = "300s"
                        perSeriesAligner    = "ALIGN_RATE"
                        crossSeriesReducer  = "REDUCE_SUM"
                        groupByFields       = ["metric.labels.violation_type"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Violations per minute"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Violations by Severity"
            pieChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"logging.googleapis.com/user/${local.metric_name}\""
                      aggregation = {
                        alignmentPeriod     = "3600s"
                        perSeriesAligner    = "ALIGN_SUM"
                        crossSeriesReducer  = "REDUCE_SUM"
                        groupByFields       = ["metric.labels.severity"]
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width  = 12
          height = 4
          widget = {
            title = "Function Execution Metrics"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"cloudfunctions.googleapis.com/function/execution_count\" AND resource.labels.function_name=\"${local.function_name}\""
                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Executions per minute"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })

  project = local.project_id

  depends_on = [
    google_logging_metric.compliance_violations,
    google_cloudfunctions2_function.compliance_detector
  ]
}