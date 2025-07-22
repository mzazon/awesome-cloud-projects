# Multi-Cloud Resource Discovery Infrastructure
# This Terraform configuration deploys a complete multi-cloud resource discovery system
# using Google Cloud Location Finder, Pub/Sub, Cloud Functions, and Cloud Storage

# Generate random suffix for resource names to ensure uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with unique suffix
  resource_suffix = random_id.suffix.hex
  
  # Standardized resource names
  topic_name         = "${var.resource_prefix}-topic-${local.resource_suffix}"
  subscription_name  = "${var.resource_prefix}-sub-${local.resource_suffix}"
  function_name      = "${var.resource_prefix}-function-${local.resource_suffix}"
  bucket_name        = "${var.resource_prefix}-reports-${local.resource_suffix}"
  scheduler_job_name = "${var.resource_prefix}-scheduler-${local.resource_suffix}"
  service_account_id = "${var.resource_prefix}-sa-${local.resource_suffix}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    terraform   = "true"
    suffix      = local.resource_suffix
  })
  
  # Required Google Cloud APIs
  required_apis = [
    "cloudlocationfinder.googleapis.com",
    "pubsub.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com"
  ]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(local.required_apis) : toset([])
  
  project = var.project_id
  service = each.value
  
  # Prevent disabling APIs when destroying this configuration
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create service account for Cloud Function with minimal required permissions
resource "google_service_account" "function_sa" {
  account_id   = local.service_account_id
  display_name = "Multi-Cloud Discovery Function Service Account"
  description  = "Service account for multi-cloud resource discovery Cloud Function"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# IAM binding for Pub/Sub subscription access
resource "google_pubsub_subscription_iam_member" "function_subscriber" {
  subscription = google_pubsub_subscription.location_discovery_sub.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${google_service_account.function_sa.email}"
  project      = var.project_id
}

# IAM binding for Cloud Storage access
resource "google_storage_bucket_iam_member" "function_storage_admin" {
  bucket = google_storage_bucket.location_reports.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Monitoring metrics writing
resource "google_project_iam_member" "function_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# IAM binding for Cloud Location Finder API access
resource "google_project_iam_member" "function_location_finder" {
  project = var.project_id
  role    = "roles/cloudlocationfinder.viewer"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create Pub/Sub topic for location discovery messages
resource "google_pubsub_topic" "location_discovery" {
  name    = local.topic_name
  project = var.project_id
  labels  = local.common_labels
  
  # Enable message ordering for consistent processing
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create Pub/Sub subscription for Cloud Function processing
resource "google_pubsub_subscription" "location_discovery_sub" {
  name    = local.subscription_name
  topic   = google_pubsub_topic.location_discovery.name
  project = var.project_id
  labels  = local.common_labels
  
  # Configure message acknowledgment settings
  ack_deadline_seconds       = var.pubsub_ack_deadline
  message_retention_duration = var.pubsub_message_retention
  
  # Configure retry policy for failed message processing
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "300s"
  }
  
  # Configure dead letter topic for unprocessable messages
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dead_letter.id
    max_delivery_attempts = 5
  }
  
  # Enable exactly once delivery for reliable processing
  enable_exactly_once_delivery = true
}

# Create dead letter topic for failed message processing
resource "google_pubsub_topic" "dead_letter" {
  name    = "${local.topic_name}-dead-letter"
  project = var.project_id
  labels  = local.common_labels
  
  message_storage_policy {
    allowed_persistence_regions = [var.region]
  }
}

# Create Cloud Storage bucket for location reports and data
resource "google_storage_bucket" "location_reports" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id
  labels   = local.common_labels
  
  # Configure storage class for cost optimization
  storage_class = var.storage_class
  
  # Enable versioning for report history tracking
  versioning {
    enabled = var.enable_versioning
  }
  
  # Configure uniform bucket-level access for security
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Configure lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }
  
  # Prevent accidental deletion of bucket
  force_destroy = false
  
  depends_on = [google_project_service.required_apis]
}

# Create folder structure in Cloud Storage bucket
resource "google_storage_bucket_object" "reports_folder" {
  name   = "reports/.gitkeep"
  bucket = google_storage_bucket.location_reports.name
  source = "/dev/null"
}

resource "google_storage_bucket_object" "raw_data_folder" {
  name   = "raw-data/.gitkeep"
  bucket = google_storage_bucket.location_reports.name
  source = "/dev/null"
}

resource "google_storage_bucket_object" "recommendations_folder" {
  name   = "recommendations/.gitkeep"
  bucket = google_storage_bucket.location_reports.name
  source = "/dev/null"
}

# Create archive of Cloud Function source code
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/function-source-${local.resource_suffix}.zip"
  
  source {
    content = file("${path.module}/function/main.py")
    filename = "main.py"
  }
  
  source {
    content = file("${path.module}/function/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_archive" {
  name   = "function-source-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.location_reports.name
  source = data.archive_file.function_source.output_path
}

# Deploy Cloud Function for location data processing
resource "google_cloudfunctions_function" "location_processor" {
  name        = local.function_name
  description = "Processes multi-cloud location data from Cloud Location Finder API"
  project     = var.project_id
  region      = var.region
  
  # Configure runtime and resource allocation
  runtime              = "python39"
  available_memory_mb  = var.function_memory
  timeout              = var.function_timeout
  entry_point          = "process_location_data"
  service_account_email = google_service_account.function_sa.email
  
  # Configure function source code
  source_archive_bucket = google_storage_bucket.location_reports.name
  source_archive_object = google_storage_bucket_object.function_archive.name
  
  # Configure Pub/Sub trigger
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.location_discovery.id
  }
  
  # Configure environment variables for function execution
  environment_variables = {
    BUCKET_NAME = google_storage_bucket.location_reports.name
    PROJECT_ID  = var.project_id
    REGION      = var.region
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_archive
  ]
}

# Create Cloud Scheduler job for automated location discovery
resource "google_cloud_scheduler_job" "location_discovery_scheduler" {
  name        = local.scheduler_job_name
  description = "Automated multi-cloud location discovery trigger"
  schedule    = var.scheduler_frequency
  time_zone   = var.scheduler_timezone
  project     = var.project_id
  region      = var.region
  
  # Configure Pub/Sub target
  pubsub_target {
    topic_name = google_pubsub_topic.location_discovery.id
    data = base64encode(jsonencode({
      trigger   = "scheduled_discovery"
      timestamp = timestamp()
      source    = "cloud-scheduler"
    }))
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create custom monitoring dashboard for location discovery metrics
resource "google_monitoring_dashboard" "location_discovery_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Multi-Cloud Location Discovery Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Total Locations Discovered"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"custom.googleapis.com/multicloud/total_locations\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                }
              ]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Function Execution Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/executions\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
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
          yPos   = 4
          widget = {
            title = "Pub/Sub Message Processing Rate"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"pubsub_subscription\" AND metric.type=\"pubsub.googleapis.com/subscription/num_delivered_messages\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
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

# Create alert policy for function execution failures
resource "google_monitoring_alert_policy" "function_failure_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Location Discovery Function Failures"
  combiner     = "OR"
  project      = var.project_id
  
  conditions {
    display_name = "Function execution failures"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions_function.location_processor.name}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      duration        = "300s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  # Configure notification channels if provided
  dynamic "notification_channels" {
    for_each = var.alert_notification_channels
    content {
      name = notification_channels.value
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  enabled = true
  
  depends_on = [google_project_service.required_apis]
}

# Create alert policy for Pub/Sub message processing delays
resource "google_monitoring_alert_policy" "pubsub_delay_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Pub/Sub Message Processing Delays"
  combiner     = "OR"
  project      = var.project_id
  
  conditions {
    display_name = "High message age in subscription"
    
    condition_threshold {
      filter          = "resource.type=\"pubsub_subscription\" AND resource.labels.subscription_id=\"${google_pubsub_subscription.location_discovery_sub.name}\" AND metric.type=\"pubsub.googleapis.com/subscription/oldest_unacked_message_age\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 600 # 10 minutes
      duration        = "300s"
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  # Configure notification channels if provided
  dynamic "notification_channels" {
    for_each = var.alert_notification_channels
    content {
      name = notification_channels.value
    }
  }
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  enabled = true
  
  depends_on = [google_project_service.required_apis]
}