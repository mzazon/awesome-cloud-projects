# Main Terraform configuration for GCP Smart Invoice Processing
# This configuration creates a complete serverless invoice processing system using
# Document AI, Cloud Workflows, Cloud Tasks, and Cloud Functions

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with environment and random suffix
  resource_suffix = "${var.environment}-${random_id.suffix.hex}"
  bucket_name     = "${var.resource_prefix}-${local.resource_suffix}"
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    region      = var.region
  })
  
  # Service account email for the invoice processor
  service_account_email = google_service_account.invoice_processor.email
  
  # Processor name for Document AI
  processor_display_name = "${var.resource_prefix}-processor-${local.resource_suffix}"
  
  # Workflow configuration
  workflow_name = "${var.resource_prefix}-workflow-${local.resource_suffix}"
  
  # Cloud Tasks queue configuration
  task_queue_name = "${var.resource_prefix}-queue-${local.resource_suffix}"
  
  # Cloud Function configuration
  function_name = "${var.resource_prefix}-notifications-${local.resource_suffix}"
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "documentai.googleapis.com",
    "workflows.googleapis.com",
    "cloudtasks.googleapis.com",
    "gmail.googleapis.com",
    "storage.googleapis.com",
    "cloudfunctions.googleapis.com",
    "eventarc.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying resources
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create Cloud Storage bucket for invoice document storage
resource "google_storage_bucket" "invoice_storage" {
  name          = local.bucket_name
  location      = var.bucket_location
  storage_class = var.bucket_storage_class
  
  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true
  
  # Enable versioning for audit trail if specified
  dynamic "versioning" {
    for_each = var.enable_bucket_versioning ? [1] : []
    content {
      enabled = true
    }
  }
  
  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_age_days
    }
    action {
      type = "Delete"
    }
  }
  
  # Configure lifecycle rule for failed processing folder
  lifecycle_rule {
    condition {
      age                   = 90
      matches_prefix        = ["failed/"]
    }
    action {
      type = "Delete"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create bucket folders for organized document processing
resource "google_storage_bucket_object" "incoming_folder" {
  name   = "incoming/"
  bucket = google_storage_bucket.invoice_storage.name
  content = " "
}

resource "google_storage_bucket_object" "processed_folder" {
  name   = "processed/"
  bucket = google_storage_bucket.invoice_storage.name
  content = " "
}

resource "google_storage_bucket_object" "failed_folder" {
  name   = "failed/"
  bucket = google_storage_bucket.invoice_storage.name
  content = " "
}

# Create service account for invoice processing workflow
resource "google_service_account" "invoice_processor" {
  account_id   = "${var.resource_prefix}-processor-${random_id.suffix.hex}"
  display_name = "Invoice Processing Service Account"
  description  = "Service account for automated invoice processing with Document AI and Workflows"
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary IAM permissions to the service account
resource "google_project_iam_member" "service_account_permissions" {
  for_each = toset([
    "roles/documentai.apiUser",
    "roles/storage.objectAdmin",
    "roles/cloudtasks.enqueuer",
    "roles/workflows.invoker",
    "roles/cloudfunctions.invoker",
    "roles/pubsub.publisher",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.invoice_processor.email}"
}

# Create Document AI processor for invoice parsing
resource "google_document_ai_processor" "invoice_parser" {
  location     = var.region
  display_name = local.processor_display_name
  type         = var.document_ai_processor_type
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.invoice_processor
  ]
}

# Create Pub/Sub topic for Cloud Storage notifications
resource "google_pubsub_topic" "invoice_uploads" {
  name = "${var.resource_prefix}-uploads-${local.resource_suffix}"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for workflow triggering
resource "google_pubsub_subscription" "invoice_processing" {
  name  = "${var.resource_prefix}-processing-${local.resource_suffix}"
  topic = google_pubsub_topic.invoice_uploads.name
  
  # Configure message retention and acknowledgment
  message_retention_duration = "86400s" # 24 hours
  ack_deadline_seconds       = 600      # 10 minutes
  
  # Configure retry policy for failed message processing
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  # Configure dead letter policy for persistent failures
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.invoice_uploads_dead_letter.id
    max_delivery_attempts = 5
  }
  
  labels = local.common_labels
}

# Create dead letter topic for failed message processing
resource "google_pubsub_topic" "invoice_uploads_dead_letter" {
  name = "${var.resource_prefix}-uploads-dl-${local.resource_suffix}"
  
  labels = local.common_labels
}

# Configure Cloud Storage bucket notification to Pub/Sub
resource "google_storage_notification" "invoice_upload_notification" {
  bucket         = google_storage_bucket.invoice_storage.name
  topic          = google_pubsub_topic.invoice_uploads.id
  payload_format = "JSON_API_V1"
  
  # Trigger on object creation in the incoming folder
  event_types            = ["OBJECT_FINALIZE"]
  object_name_prefix     = "incoming/"
  
  depends_on = [google_pubsub_topic_iam_member.storage_publisher]
}

# Grant Cloud Storage permission to publish to Pub/Sub topic
resource "google_pubsub_topic_iam_member" "storage_publisher" {
  topic  = google_pubsub_topic.invoice_uploads.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
}

# Get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Create Cloud Tasks queue for approval workflow management
resource "google_cloud_tasks_queue" "approval_queue" {
  name     = local.task_queue_name
  location = var.region
  
  # Configure queue rate limiting and retry behavior
  rate_limits {
    max_dispatches_per_second = var.cloud_tasks_max_dispatches_per_second
    max_concurrent_dispatches = var.cloud_tasks_max_concurrent_dispatches
  }
  
  retry_config {
    max_attempts       = var.cloud_tasks_max_retry_attempts
    max_retry_duration = "600s"
    max_backoff        = "300s"
    min_backoff        = "1s"
    max_doublings      = 5
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create ZIP archive for Cloud Function source code
data "archive_file" "notification_function_source" {
  type        = "zip"
  output_path = "/tmp/notification_function.zip"
  
  source {
    content = templatefile("${path.module}/function_source/main.py", {
      manager_email    = var.notification_emails[0]
      director_email   = var.notification_emails[1]
      executive_email  = var.notification_emails[2]
      manager_threshold   = var.approval_amount_thresholds.manager_threshold
      director_threshold  = var.approval_amount_thresholds.director_threshold
      executive_threshold = var.approval_amount_thresholds.executive_threshold
    })
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function_source/requirements.txt")
    filename = "requirements.txt"
  }
}

# Create Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name          = "${local.bucket_name}-function-source"
  location      = var.bucket_location
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Upload Cloud Function source code to Cloud Storage
resource "google_storage_bucket_object" "notification_function_zip" {
  name   = "notification-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.notification_function_source.output_path
  
  depends_on = [data.archive_file.notification_function_source]
}

# Create Cloud Function for email notifications
resource "google_cloudfunctions_function" "notification_function" {
  name        = local.function_name
  description = "Send invoice approval notifications via email"
  region      = var.region
  
  # Function configuration
  runtime               = var.cloud_function_runtime
  available_memory_mb   = var.cloud_function_memory_mb
  timeout               = var.cloud_function_timeout_seconds
  entry_point          = "send_approval_notification"
  service_account_email = google_service_account.invoice_processor.email
  
  # Source code configuration
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.notification_function_zip.name
  
  # Trigger configuration (HTTP trigger)
  trigger {
    http_trigger {}
  }
  
  # Environment variables for function configuration
  environment_variables = {
    PROJECT_ID             = var.project_id
    TASK_QUEUE_NAME       = local.task_queue_name
    TASK_QUEUE_LOCATION   = var.region
    MANAGER_EMAIL         = var.notification_emails[0]
    DIRECTOR_EMAIL        = var.notification_emails[1]
    EXECUTIVE_EMAIL       = var.notification_emails[2]
    MANAGER_THRESHOLD     = var.approval_amount_thresholds.manager_threshold
    DIRECTOR_THRESHOLD    = var.approval_amount_thresholds.director_threshold
    EXECUTIVE_THRESHOLD   = var.approval_amount_thresholds.executive_threshold
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.notification_function_zip
  ]
}

# Allow Cloud Tasks to invoke the notification function
resource "google_cloudfunctions_function_iam_member" "task_invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.notification_function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.invoice_processor.email}"
}

# Create Cloud Workflow for invoice processing orchestration
resource "google_workflows_workflow" "invoice_processing" {
  name            = local.workflow_name
  region          = var.region
  description     = "Orchestrates intelligent invoice processing with Document AI and approval routing"
  service_account = google_service_account.invoice_processor.email
  
  # Workflow definition using templatefile for dynamic values
  source_contents = templatefile("${path.module}/workflow_source/invoice_workflow.yaml", {
    project_id          = var.project_id
    region              = var.region
    processor_id        = google_document_ai_processor.invoice_parser.name
    bucket_name         = google_storage_bucket.invoice_storage.name
    task_queue_name     = local.task_queue_name
    function_url        = google_cloudfunctions_function.notification_function.https_trigger_url
    manager_threshold   = var.approval_amount_thresholds.manager_threshold
    director_threshold  = var.approval_amount_thresholds.director_threshold
    executive_threshold = var.approval_amount_thresholds.executive_threshold
  })
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_document_ai_processor.invoice_parser,
    google_storage_bucket.invoice_storage,
    google_cloud_tasks_queue.approval_queue,
    google_cloudfunctions_function.notification_function
  ]
}

# Create Eventarc trigger to start workflow on Pub/Sub message
resource "google_eventarc_trigger" "invoice_upload_trigger" {
  name            = "${var.resource_prefix}-trigger-${local.resource_suffix}"
  location        = var.region
  service_account = google_service_account.invoice_processor.email
  
  # Configure trigger to respond to Pub/Sub messages
  matching_criteria {
    attribute = "type"
    value     = "google.cloud.pubsub.topic.v1.messagePublished"
  }
  
  # Configure destination workflow
  destination {
    workflow = google_workflows_workflow.invoice_processing.id
  }
  
  # Configure transport (Pub/Sub)
  transport {
    pubsub {
      topic = google_pubsub_topic.invoice_uploads.id
    }
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_workflows_workflow.invoice_processing,
    google_pubsub_topic.invoice_uploads
  ]
}

# Optional: Create monitoring dashboard for invoice processing
resource "google_monitoring_dashboard" "invoice_processing_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Invoice Processing System - ${var.environment}"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Workflow Executions"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"workflows.googleapis.com/Workflow\" AND resource.labels.workflow_id=\"${local.workflow_name}\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Document AI Processing"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"documentai.googleapis.com/Processor\" AND resource.labels.processor_id=\"${google_document_ai_processor.invoice_parser.name}\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        }
      ]
    }
  })
  
  depends_on = [
    google_project_service.required_apis,
    google_workflows_workflow.invoice_processing,
    google_document_ai_processor.invoice_parser
  ]
}

# Optional: Create log-based alerts for system monitoring
resource "google_logging_metric" "workflow_failures" {
  count = var.enable_monitoring ? 1 : 0
  
  name   = "${var.resource_prefix}-workflow-failures-${local.resource_suffix}"
  filter = <<-EOT
    resource.type="workflows.googleapis.com/Workflow"
    resource.labels.workflow_id="${local.workflow_name}"
    severity="ERROR"
  EOT
  
  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "INT64"
  }
  
  depends_on = [google_workflows_workflow.invoice_processing]
}

# Create alert policy for workflow failures
resource "google_monitoring_alert_policy" "workflow_failure_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Invoice Processing Workflow Failures - ${var.environment}"
  combiner     = "OR"
  
  conditions {
    display_name = "Workflow execution failures"
    
    condition_threshold {
      filter          = "resource.type=\"logging.googleapis.com/LogMetric\" AND resource.labels.name=\"${google_logging_metric.workflow_failures[0].name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  # Configure notification channels (requires manual setup)
  notification_channels = []
  
  alert_strategy {
    auto_close = "86400s" # 24 hours
  }
  
  depends_on = [google_logging_metric.workflow_failures]
}