# Main Terraform configuration for Security Posture Assessment
# This file creates the complete infrastructure for automated security posture assessment
# using Google Cloud Security Command Center, Workload Manager, and supporting services

# Local values for resource naming and configuration
locals {
  # Generate unique suffix if not provided
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : random_id.suffix.hex
  
  # Common resource naming
  base_name = "${var.resource_prefix}-${local.resource_suffix}"
  
  # Merge common labels with environment-specific labels
  common_labels = merge(var.common_labels, {
    environment = var.environment
    project     = var.project_id
    region      = var.region
  })
  
  # Service account email
  service_account_email = var.create_custom_service_account ? google_service_account.security_automation[0].email : null
}

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "securitycenter.googleapis.com",
    "workloadmanager.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "compute.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ])
  
  service = each.value
  project = var.project_id
  
  # Don't disable services on destroy to avoid breaking other resources
  disable_on_destroy = false
}

# Create IAM Service Account for Security Automation
resource "google_service_account" "security_automation" {
  count = var.create_custom_service_account ? 1 : 0
  
  account_id   = "${var.resource_prefix}-automation"
  display_name = "Security Automation Service Account"
  description  = "Service account for automated security posture assessment and remediation"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Assign IAM roles to the service account
resource "google_project_iam_member" "security_automation_roles" {
  for_each = var.create_custom_service_account ? toset(var.service_account_roles) : []
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.security_automation[0].email}"
}

# Create Cloud Storage bucket for security logs and function source code
resource "google_storage_bucket" "security_logs" {
  name          = "${local.base_name}-logs"
  location      = var.storage_location
  project       = var.project_id
  force_destroy = var.storage_force_destroy
  
  # Enable versioning for audit trail
  versioning {
    enabled = true
  }
  
  # Configure lifecycle management
  lifecycle_rule {
    condition {
      age = 90
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
  
  # Enable uniform bucket-level access
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub topic for security events
resource "google_pubsub_topic" "security_events" {
  name    = "${local.base_name}-events"
  project = var.project_id
  
  # Configure message retention
  message_retention_duration = var.pubsub_message_retention_duration
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for Cloud Function
resource "google_pubsub_subscription" "security_events_subscription" {
  name  = "${local.base_name}-events-subscription"
  topic = google_pubsub_topic.security_events.name
  
  # Configure acknowledgment deadline
  ack_deadline_seconds = var.pubsub_ack_deadline_seconds
  
  # Configure retry policy
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Configure dead letter policy
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.security_events_dlq.id
    max_delivery_attempts = 5
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create dead letter queue for failed message processing
resource "google_pubsub_topic" "security_events_dlq" {
  name    = "${local.base_name}-events-dlq"
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Function source code archive
data "archive_file" "security_function_source" {
  type        = "zip"
  output_path = "${path.module}/security-remediation-function.zip"
  
  source {
    content = templatefile("${path.module}/function_source/main.py", {
      project_id = var.project_id
      region     = var.region
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "security_function_source" {
  name   = "security-remediation-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.security_logs.name
  source = data.archive_file.security_function_source.output_path
  
  # Update function when source code changes
  depends_on = [data.archive_file.security_function_source]
}

# Create Cloud Function for automated remediation
resource "google_cloudfunctions_function" "security_remediation" {
  count = var.enable_automated_remediation ? 1 : 0
  
  name        = "${local.base_name}-remediation"
  project     = var.project_id
  region      = var.region
  description = "Automated security remediation function"
  
  runtime     = var.function_runtime
  entry_point = "process_security_event"
  
  # Configure function resources
  available_memory_mb = var.function_memory_mb
  timeout             = var.function_timeout_seconds
  
  # Configure source code
  source_archive_bucket = google_storage_bucket.security_logs.name
  source_archive_object = google_storage_bucket_object.security_function_source.name
  
  # Configure Pub/Sub trigger
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.security_events.name
  }
  
  # Configure service account
  service_account_email = local.service_account_email
  
  # Configure environment variables
  environment_variables = {
    PROJECT_ID           = var.project_id
    REGION              = var.region
    ENVIRONMENT         = var.environment
    STORAGE_BUCKET      = google_storage_bucket.security_logs.name
    ENABLE_REMEDIATION  = "true"
    LOG_LEVEL          = "INFO"
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.security_function_source
  ]
}

# Configure Security Command Center notification
resource "google_scc_notification_config" "security_findings" {
  config_id    = "${var.resource_prefix}-findings"
  organization = var.organization_id
  description  = "Security findings notification for automated processing"
  
  pubsub_topic = google_pubsub_topic.security_events.id
  
  streaming_config {
    filter = "state=\"ACTIVE\""
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Security Command Center custom detector (using beta provider)
resource "google_scc_source" "custom_detector" {
  display_name = "${local.base_name}-custom-detector"
  organization = var.organization_id
  description  = "Custom security detector for organization-specific rules"
  
  depends_on = [google_project_service.required_apis]
}

# Create Workload Manager evaluation template
resource "google_workload_manager_evaluation" "security_compliance" {
  count = var.enable_workload_manager ? 1 : 0
  
  evaluation_id = "${var.resource_prefix}-security-compliance"
  location      = var.region
  project       = var.project_id
  
  description = "Automated security compliance evaluation"
  
  # Configure custom rules
  custom_rules = [
    for rule_name, rule_config in var.workload_manager_rules : {
      name        = rule_name
      description = rule_config.description
      type        = rule_config.type
      severity    = rule_config.severity
    }
  ]
  
  # Configure schedule
  schedule = var.security_evaluation_schedule
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Scheduler job for periodic security evaluations
resource "google_cloud_scheduler_job" "security_evaluation_trigger" {
  name     = "${local.base_name}-evaluation-trigger"
  project  = var.project_id
  region   = var.region
  schedule = var.security_evaluation_schedule
  
  description = "Trigger security posture evaluation"
  
  pubsub_target {
    topic_name = google_pubsub_topic.security_events.id
    data       = base64encode(jsonencode({
      event_type = "scheduled_evaluation"
      source     = "automation"
      timestamp  = timestamp()
    }))
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Monitoring dashboard for security metrics
resource "google_monitoring_dashboard" "security_posture" {
  count = var.create_monitoring_dashboard ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Security Posture Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Security Findings by Severity"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_instance\""
                      aggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Findings Count"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Function Execution Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.base_name}-remediation\""
                      aggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
            }
          }
        },
        {
          width  = 12
          height = 4
          widget = {
            title = "Security Events Timeline"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"pubsub_topic\" AND resource.labels.topic_id=\"${local.base_name}-events\""
                      aggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                      }
                    }
                  }
                  plotType = "STACKED_BAR"
                }
              ]
            }
          }
        }
      ]
    }
  })
  
  project = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Create alerting policy for critical security findings
resource "google_monitoring_alert_policy" "critical_security_findings" {
  count = var.enable_critical_alert_notifications ? 1 : 0
  
  display_name = "Critical Security Findings"
  project      = var.project_id
  
  conditions {
    display_name = "Critical Security Finding Detected"
    
    condition_threshold {
      filter          = "resource.type=\"pubsub_topic\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  # Configure notification channels
  dynamic "notification_channels" {
    for_each = var.alert_notification_channels
    content {
      channel = notification_channels.value
    }
  }
  
  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create budget for cost monitoring
resource "google_billing_budget" "security_posture_budget" {
  count = var.budget_amount > 0 ? 1 : 0
  
  billing_account = data.google_billing_account.account.id
  display_name    = "${local.base_name}-budget"
  
  budget_filter {
    projects = ["projects/${var.project_id}"]
    
    labels = {
      component = "security-posture"
    }
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount)
    }
  }
  
  threshold_rules {
    threshold_percent = var.budget_threshold_percent / 100
    spend_basis       = "CURRENT_SPEND"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Get billing account information
data "google_billing_account" "account" {
  billing_account = data.google_project.current.billing_account
}

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}