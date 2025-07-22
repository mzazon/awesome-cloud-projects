# Generate random suffix for resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for resource naming
locals {
  # Generate unique resource names
  topic_name       = var.pubsub_topic_name != "" ? var.pubsub_topic_name : "${var.resource_prefix}-findings-${random_id.suffix.hex}"
  function_name    = var.function_name != "" ? var.function_name : "${var.resource_prefix}-processor-${random_id.suffix.hex}"
  scc_notification = var.scc_notification_name != "" ? var.scc_notification_name : "${var.resource_prefix}-notification-${random_id.suffix.hex}"
  dashboard_name   = var.dashboard_name != "" ? var.dashboard_name : "${var.resource_prefix} Compliance Dashboard"
  
  # Workflow names
  high_severity_workflow   = var.workflow_names.high_severity != "" ? var.workflow_names.high_severity : "${var.resource_prefix}-high-severity-${random_id.suffix.hex}"
  medium_severity_workflow = var.workflow_names.medium_severity != "" ? var.workflow_names.medium_severity : "${var.resource_prefix}-medium-severity-${random_id.suffix.hex}"
  low_severity_workflow    = var.workflow_names.low_severity != "" ? var.workflow_names.low_severity : "${var.resource_prefix}-low-severity-${random_id.suffix.hex}"
  
  # Service account names
  function_sa_name = var.service_account_names.function_sa != "" ? var.service_account_names.function_sa : "${var.resource_prefix}-function-sa-${random_id.suffix.hex}"
  workflow_sa_name = var.service_account_names.workflow_sa != "" ? var.service_account_names.workflow_sa : "${var.resource_prefix}-workflow-sa-${random_id.suffix.hex}"
  
  # Common labels
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    managed-by  = "terraform"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(var.required_apis) : []
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create service account for Cloud Functions
resource "google_service_account" "function_sa" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = local.function_sa_name
  display_name = "Security Compliance Function Service Account"
  description  = "Service account for security findings processing function"
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Workflows
resource "google_service_account" "workflow_sa" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = local.workflow_sa_name
  display_name = "Security Compliance Workflow Service Account"
  description  = "Service account for security compliance workflows"
  
  depends_on = [google_project_service.required_apis]
}

# IAM roles for function service account
resource "google_project_iam_member" "function_sa_roles" {
  for_each = var.create_service_accounts ? toset([
    "roles/logging.logWriter",
    "roles/workflows.invoker",
    "roles/pubsub.subscriber"
  ]) : []
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa[0].email}"
  
  depends_on = [google_service_account.function_sa]
}

# IAM roles for workflow service account
resource "google_project_iam_member" "workflow_sa_roles" {
  for_each = var.create_service_accounts ? toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/pubsub.publisher"
  ]) : []
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.workflow_sa[0].email}"
  
  depends_on = [google_service_account.workflow_sa]
}

# Create Pub/Sub topic for security findings
resource "google_pubsub_topic" "security_findings" {
  name = local.topic_name
  
  message_retention_duration = var.pubsub_message_retention_duration
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for the Cloud Function
resource "google_pubsub_subscription" "security_findings_subscription" {
  name  = "${local.topic_name}-sub"
  topic = google_pubsub_topic.security_findings.name
  
  # Configure acknowledgment deadline
  ack_deadline_seconds = 20
  
  # Configure message retention
  message_retention_duration = "86400s"
  
  # Configure retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Configure dead letter policy
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  labels = local.common_labels
}

# Create dead letter topic for failed messages
resource "google_pubsub_topic" "dead_letter" {
  name = "${local.topic_name}-dead-letter"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Security Command Center notification configuration
resource "google_scc_notification_config" "security_findings_notification" {
  count = var.organization_id != "" ? 1 : 0
  
  config_id    = local.scc_notification
  organization = var.organization_id
  description  = "Automated security findings notification for compliance monitoring"
  
  pubsub_topic = google_pubsub_topic.security_findings.id
  
  streaming_config {
    filter = var.scc_notification_filter
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_pubsub_topic_iam_member.scc_publisher
  ]
}

# Grant Security Command Center permission to publish to the topic
resource "google_pubsub_topic_iam_member" "scc_publisher" {
  topic  = google_pubsub_topic.security_findings.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:security-center-api@system.gserviceaccount.com"
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source_bucket" {
  name     = "${var.project_id}-function-source-${random_id.suffix.hex}"
  location = var.region
  
  labels = local.common_labels
  
  # Configure lifecycle to clean up old versions
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

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source_object" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source_bucket.name
  source = data.archive_file.function_source.output_path
}

# Deploy Cloud Function for processing security findings
resource "google_cloudfunctions2_function" "security_processor" {
  name     = local.function_name
  location = var.region
  
  build_config {
    runtime     = var.function_runtime
    entry_point = "process_security_finding"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source_bucket.name
        object = google_storage_bucket_object.function_source_object.name
      }
    }
  }
  
  service_config {
    max_instance_count = 100
    min_instance_count = 0
    
    available_memory   = var.function_memory
    timeout_seconds    = var.function_timeout
    
    environment_variables = {
      PROJECT_ID = var.project_id
      REGION     = var.region
    }
    
    service_account_email = var.create_service_accounts ? google_service_account.function_sa[0].email : null
  }
  
  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.security_findings.id
    
    retry_policy = "RETRY_POLICY_RETRY"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.function_sa_roles
  ]
}

# High-severity security workflow
resource "google_workflows_workflow" "high_severity" {
  name            = local.high_severity_workflow
  region          = var.region
  description     = "High-severity security findings workflow with immediate remediation"
  
  service_account = var.create_service_accounts ? google_service_account.workflow_sa[0].id : null
  
  source_contents = templatefile("${path.module}/workflows/high_severity.yaml", {
    project_id = var.project_id
  })
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.workflow_sa_roles
  ]
}

# Medium-severity security workflow
resource "google_workflows_workflow" "medium_severity" {
  name            = local.medium_severity_workflow
  region          = var.region
  description     = "Medium-severity security findings workflow with notification and tracking"
  
  service_account = var.create_service_accounts ? google_service_account.workflow_sa[0].id : null
  
  source_contents = templatefile("${path.module}/workflows/medium_severity.yaml", {
    project_id = var.project_id
  })
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.workflow_sa_roles
  ]
}

# Low-severity security workflow
resource "google_workflows_workflow" "low_severity" {
  name            = local.low_severity_workflow
  region          = var.region
  description     = "Low-severity security findings workflow with aggregation and trend monitoring"
  
  service_account = var.create_service_accounts ? google_service_account.workflow_sa[0].id : null
  
  source_contents = templatefile("${path.module}/workflows/low_severity.yaml", {
    project_id = var.project_id
  })
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.workflow_sa_roles
  ]
}

# Log-based metric for security findings processed
resource "google_logging_metric" "security_findings_processed" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "security_findings_processed"
  filter = "resource.type=\"cloud_function\" AND textPayload:\"Processing finding\""
  
  metric_descriptor {
    metric_kind = "CUMULATIVE"
    value_type  = "INT64"
    display_name = "Security Findings Processed"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Log-based metric for workflow executions
resource "google_logging_metric" "workflow_executions" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "workflow_executions"
  filter = "resource.type=\"workflows.googleapis.com/Workflow\""
  
  metric_descriptor {
    metric_kind = "CUMULATIVE"
    value_type  = "INT64"
    display_name = "Workflow Executions"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Notification channel for alerts (if email provided)
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  display_name = "Security Team Email"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alert policy for high-severity findings
resource "google_monitoring_alert_policy" "high_severity_findings" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "High Severity Security Findings Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "High severity findings rate"
    
    condition_threshold {
      filter         = "resource.type=\"cloud_function\" AND textPayload:\"high-severity-workflow\""
      duration       = "300s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = var.alert_threshold_high_severity
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
  
  alert_strategy {
    auto_close = "86400s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Monitoring dashboard for security compliance
resource "google_monitoring_dashboard" "compliance_dashboard" {
  count = var.enable_monitoring && var.create_dashboard ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = local.dashboard_name
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Security Findings by Severity"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_function\""
                  aggregation = {
                    alignmentPeriod    = "3600s"
                    perSeriesAligner   = "ALIGN_RATE"
                  }
                }
              }
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          widget = {
            title = "Workflow Execution Success Rate"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"workflows.googleapis.com/Workflow\""
                  aggregation = {
                    alignmentPeriod    = "3600s"
                    perSeriesAligner   = "ALIGN_RATE"
                  }
                }
              }
            }
          }
        },
        {
          width = 12
          height = 4
          yPos = 4
          widget = {
            title = "Security Findings Timeline"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\""
                      aggregation = {
                        alignmentPeriod    = "3600s"
                        perSeriesAligner   = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}