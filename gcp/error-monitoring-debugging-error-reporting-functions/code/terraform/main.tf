# Generate a random deployment ID for unique resource naming
resource "random_string" "deployment_id" {
  length  = 6
  special = false
  upper   = false
}

# Local values for consistent naming and configuration
locals {
  deployment_id = random_string.deployment_id.result
  
  # Resource naming convention
  name_prefix = "${var.resource_prefix}-${var.environment}-${local.deployment_id}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment   = var.environment
    deployment-id = local.deployment_id
    created-by    = "terraform"
  })
  
  # Function source code paths
  function_source_path = "${path.module}/function_source"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "clouderrorreporting.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudmonitoring.googleapis.com",
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "firestore.googleapis.com",
    "cloudbuild.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy         = false
  disable_dependent_services = false
}

# Create Firestore database for error tracking
resource "google_firestore_database" "error_tracking" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.firestore_location
  type        = "FIRESTORE_NATIVE"

  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "${local.name_prefix}-function-source"
  location = var.storage_bucket_location
  project  = var.project_id

  uniform_bucket_level_access = var.enable_uniform_bucket_level_access

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for debug data storage
resource "google_storage_bucket" "debug_data" {
  name     = "${local.name_prefix}-debug-data"
  location = var.storage_bucket_location
  project  = var.project_id

  uniform_bucket_level_access = var.enable_uniform_bucket_level_access

  versioning {
    enabled = true
  }

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
      age                = 30
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub topic for error notifications
resource "google_pubsub_topic" "error_notifications" {
  name    = "${local.name_prefix}-error-notifications"
  project = var.project_id

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub topic for alert notifications
resource "google_pubsub_topic" "alert_notifications" {
  name    = "${local.name_prefix}-alert-notifications"
  project = var.project_id

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub topic for debug automation
resource "google_pubsub_topic" "debug_automation" {
  name    = "${local.name_prefix}-debug-automation"
  project = var.project_id

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Service accounts for Cloud Functions (if enabled)
resource "google_service_account" "error_processor" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = "${var.resource_prefix}-error-processor-${local.deployment_id}"
  display_name = "Error Processor Function Service Account"
  description  = "Service account for the error processor Cloud Function"
  project      = var.project_id
}

resource "google_service_account" "alert_router" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = "${var.resource_prefix}-alert-router-${local.deployment_id}"
  display_name = "Alert Router Function Service Account"
  description  = "Service account for the alert router Cloud Function"
  project      = var.project_id
}

resource "google_service_account" "debug_automation" {
  count = var.create_service_accounts ? 1 : 0
  
  account_id   = "${var.resource_prefix}-debug-automation-${local.deployment_id}"
  display_name = "Debug Automation Function Service Account"
  description  = "Service account for the debug automation Cloud Function"
  project      = var.project_id
}

# IAM bindings for service accounts
resource "google_project_iam_member" "error_processor_permissions" {
  for_each = var.create_service_accounts ? toset([
    "roles/errorreporting.writer",
    "roles/monitoring.metricWriter",
    "roles/datastore.user",
    "roles/pubsub.publisher",
    "roles/logging.logWriter"
  ]) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.error_processor[0].email}"
}

resource "google_project_iam_member" "alert_router_permissions" {
  for_each = var.create_service_accounts ? toset([
    "roles/monitoring.alertPolicyEditor",
    "roles/datastore.user",
    "roles/pubsub.publisher",
    "roles/logging.logWriter"
  ]) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.alert_router[0].email}"
}

resource "google_project_iam_member" "debug_automation_permissions" {
  for_each = var.create_service_accounts ? toset([
    "roles/logging.viewer",
    "roles/monitoring.viewer",
    "roles/datastore.user",
    "roles/storage.objectCreator",
    "roles/logging.logWriter"
  ]) : toset([])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.debug_automation[0].email}"
}

# Create function source code archives
data "archive_file" "error_processor_source" {
  type        = "zip"
  output_path = "${path.module}/error_processor_source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/error_processor.py", {
      project_id    = var.project_id
      alert_topic   = google_pubsub_topic.alert_notifications.name
      debug_topic   = google_pubsub_topic.debug_automation.name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements_error_processor.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "alert_router_source" {
  type        = "zip"
  output_path = "${path.module}/alert_router_source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/alert_router.py", {
      project_id        = var.project_id
      slack_webhook_url = var.slack_webhook_url
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements_alert_router.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "debug_automation_source" {
  type        = "zip"
  output_path = "${path.module}/debug_automation_source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/debug_automation.py", {
      project_id    = var.project_id
      debug_bucket  = google_storage_bucket.debug_data.name
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements_debug_automation.txt")
    filename = "requirements.txt"
  }
}

data "archive_file" "sample_app_source" {
  count = var.deploy_sample_app ? 1 : 0
  
  type        = "zip"
  output_path = "${path.module}/sample_app_source.zip"
  
  source {
    content = file("${path.module}/function_code/sample_app.py")
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_code/requirements_sample_app.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "error_processor_source" {
  name   = "error_processor_source_${data.archive_file.error_processor_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.error_processor_source.output_path
}

resource "google_storage_bucket_object" "alert_router_source" {
  name   = "alert_router_source_${data.archive_file.alert_router_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.alert_router_source.output_path
}

resource "google_storage_bucket_object" "debug_automation_source" {
  name   = "debug_automation_source_${data.archive_file.debug_automation_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.debug_automation_source.output_path
}

resource "google_storage_bucket_object" "sample_app_source" {
  count = var.deploy_sample_app ? 1 : 0
  
  name   = "sample_app_source_${data.archive_file.sample_app_source[0].output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.sample_app_source[0].output_path
}

# Error Processor Cloud Function
resource "google_cloudfunctions_function" "error_processor" {
  name    = "${local.name_prefix}-error-processor"
  project = var.project_id
  region  = var.region

  runtime = "python39"

  available_memory_mb   = var.error_processor_memory
  timeout               = var.error_processor_timeout
  entry_point          = "process_error"
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.error_processor_source.name

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.error_notifications.id
  }

  environment_variables = {
    GCP_PROJECT  = var.project_id
    ALERT_TOPIC  = google_pubsub_topic.alert_notifications.name
    DEBUG_TOPIC  = google_pubsub_topic.debug_automation.name
  }

  service_account_email = var.create_service_accounts ? google_service_account.error_processor[0].email : null

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.error_processor_source
  ]
}

# Alert Router Cloud Function
resource "google_cloudfunctions_function" "alert_router" {
  name    = "${local.name_prefix}-alert-router"
  project = var.project_id
  region  = var.region

  runtime = "python39"

  available_memory_mb   = var.alert_router_memory
  timeout               = 60
  entry_point          = "route_alerts"
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.alert_router_source.name

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.alert_notifications.id
  }

  environment_variables = merge({
    GCP_PROJECT = var.project_id
  }, var.slack_webhook_url != "" ? {
    SLACK_WEBHOOK = var.slack_webhook_url
  } : {})

  service_account_email = var.create_service_accounts ? google_service_account.alert_router[0].email : null

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.alert_router_source
  ]
}

# Debug Automation Cloud Function
resource "google_cloudfunctions_function" "debug_automation" {
  name    = "${local.name_prefix}-debug-automation"
  project = var.project_id
  region  = var.region

  runtime = "python39"

  available_memory_mb   = var.debug_automation_memory
  timeout               = var.debug_automation_timeout
  entry_point          = "automate_debugging"
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.debug_automation_source.name

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.debug_automation.id
  }

  environment_variables = {
    GCP_PROJECT   = var.project_id
    DEBUG_BUCKET  = google_storage_bucket.debug_data.name
  }

  service_account_email = var.create_service_accounts ? google_service_account.debug_automation[0].email : null

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.debug_automation_source
  ]
}

# Sample Application Cloud Function (optional)
resource "google_cloudfunctions_function" "sample_app" {
  count = var.deploy_sample_app ? 1 : 0
  
  name    = "${local.name_prefix}-sample-app"
  project = var.project_id
  region  = var.region

  runtime = "python39"

  available_memory_mb   = var.sample_app_memory
  timeout               = 60
  entry_point          = "sample_app"
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.sample_app_source[0].name

  https_trigger {
    url = "https://${var.region}-${var.project_id}.cloudfunctions.net/${local.name_prefix}-sample-app"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.sample_app_source[0]
  ]
}

# Make sample app publicly accessible (for testing only)
resource "google_cloudfunctions_function_iam_member" "sample_app_invoker" {
  count = var.deploy_sample_app ? 1 : 0
  
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.sample_app[0].name

  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}

# Create log sink for error events (optional)
resource "google_logging_project_sink" "error_sink" {
  count = var.enable_error_log_sink ? 1 : 0
  
  name        = "${local.name_prefix}-error-sink"
  destination = "pubsub.googleapis.com/projects/${var.project_id}/topics/${google_pubsub_topic.error_notifications.name}"

  filter = var.log_sink_filter

  unique_writer_identity = true

  depends_on = [google_project_service.required_apis]
}

# Grant log sink permission to publish to Pub/Sub
resource "google_pubsub_topic_iam_member" "log_sink_publisher" {
  count = var.enable_error_log_sink ? 1 : 0
  
  project = var.project_id
  topic   = google_pubsub_topic.error_notifications.name
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.error_sink[0].writer_identity
}

# Create Cloud Monitoring dashboard (optional)
resource "google_monitoring_dashboard" "error_monitoring" {
  count = var.enable_monitoring_dashboard ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Error Monitoring Dashboard - ${local.name_prefix}"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Error Rate by Service"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gae_app\""
                    aggregation = {
                      alignmentPeriod     = "60s"
                      perSeriesAligner    = "ALIGN_RATE"
                      crossSeriesReducer  = "REDUCE_SUM"
                      groupByFields       = ["resource.label.module_id"]
                    }
                  }
                }
              }]
              yAxis = {
                label = "Errors per minute"
                scale = "LINEAR"
              }
            }
          }
        }
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Error Processing Functions"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.label.function_name=~\"${local.name_prefix}-.*\""
                    aggregation = {
                      alignmentPeriod     = "60s"
                      perSeriesAligner    = "ALIGN_RATE"
                      crossSeriesReducer  = "REDUCE_SUM"
                      groupByFields       = ["resource.label.function_name"]
                    }
                  }
                }
              }]
              yAxis = {
                label = "Executions per minute"
                scale = "LINEAR"
              }
            }
          }
        }
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "Function Execution Errors"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_function\" AND resource.label.function_name=~\"${local.name_prefix}-.*\" AND metric.type=\"cloudfunctions.googleapis.com/function/executions\" AND metric.label.status!=\"ok\""
                  aggregation = {
                    alignmentPeriod    = "300s"
                    perSeriesAligner   = "ALIGN_SUM"
                    crossSeriesReducer = "REDUCE_SUM"
                  }
                }
              }
              sparkChartView = {
                sparkChartType = "SPARK_LINE"
              }
            }
          }
        }
      ]
    }
  })

  depends_on = [google_project_service.required_apis]
}

# Create monitoring alert policy for critical errors (optional)
resource "google_monitoring_alert_policy" "critical_error_alert" {
  count = var.enable_monitoring_dashboard && var.notification_email != "" ? 1 : 0
  
  display_name = "Critical Error Alert - ${local.name_prefix}"
  
  conditions {
    display_name = "Error rate too high"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.label.function_name=~\"${local.name_prefix}-.*\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.error_rate_threshold
      duration        = "300s"
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.function_name"]
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  enabled = true

  notification_channels = var.notification_email != "" ? [
    google_monitoring_notification_channel.email[0].id
  ] : []

  depends_on = [google_project_service.required_apis]
}

# Create email notification channel (optional)
resource "google_monitoring_notification_channel" "email" {
  count = var.notification_email != "" ? 1 : 0
  
  display_name = "Email Notification - ${local.name_prefix}"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }

  depends_on = [google_project_service.required_apis]
}