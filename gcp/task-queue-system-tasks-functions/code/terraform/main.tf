# Data sources for project information
data "google_project" "current" {
  project_id = var.project_id
}

data "google_client_config" "current" {}

# Generate unique suffix for resource names
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  # Generate unique resource names
  bucket_name = var.bucket_name_prefix != "" ? "${var.bucket_name_prefix}-task-results" : "${var.project_id}-task-results-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    recipe = "task-queue-system-tasks-functions"
  })
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudtasks.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])

  project = var.project_id
  service = each.key

  disable_dependent_services = false
  disable_on_destroy        = false
}

# Create Cloud Storage bucket for processed files and function source
resource "google_storage_bucket" "task_results" {
  name          = local.bucket_name
  location      = var.region
  storage_class = var.bucket_storage_class
  
  # Prevent accidental deletion
  force_destroy = true
  
  labels = local.common_labels

  # Enable versioning for better data protection
  versioning {
    enabled = true
  }

  # Configure lifecycle management
  dynamic "lifecycle_rule" {
    for_each = var.bucket_lifecycle_age > 0 ? [1] : []
    content {
      condition {
        age = var.bucket_lifecycle_age
      }
      action {
        type = "Delete"
      }
    }
  }

  # Enable uniform bucket-level access for better security
  uniform_bucket_level_access = true

  depends_on = [google_project_service.required_apis]
}

# Create local function code files from templates
resource "local_file" "function_main_py" {
  content = templatefile("${path.module}/function_code_template/main.py", {
    storage_bucket = local.bucket_name
  })
  filename = "${path.module}/function_code/main.py"
}

resource "local_file" "function_requirements_txt" {
  content  = file("${path.module}/function_code_template/requirements.txt")
  filename = "${path.module}/function_code/requirements.txt"
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  source_dir  = "${path.module}/function_code"
  
  depends_on = [
    local_file.function_main_py,
    local_file.function_requirements_txt
  ]
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.task_results.name
  source = data.archive_file.function_source.output_path

  depends_on = [google_storage_bucket.task_results]
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.function_name}-sa"
  display_name = "Service Account for ${var.function_name} Cloud Function"
  description  = "Service account used by the task processor Cloud Function"
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary permissions to the function service account
resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create Cloud Function for task processing
resource "google_cloudfunctions2_function" "task_processor" {
  name        = var.function_name
  location    = var.region
  description = "Cloud Function that processes tasks from Cloud Tasks queue"
  
  labels = local.common_labels

  build_config {
    runtime     = var.function_runtime
    entry_point = "task_processor"
    
    source {
      storage_source {
        bucket = google_storage_bucket.task_results.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count               = 100
    min_instance_count              = 0
    available_memory                = var.function_memory
    timeout_seconds                 = var.function_timeout
    max_instance_request_concurrency = 1000
    available_cpu                   = "1"
    
    environment_variables = {
      STORAGE_BUCKET = google_storage_bucket.task_results.name
      PROJECT_ID     = var.project_id
      REGION         = var.region
    }
    
    ingress_settings               = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.function_sa.email
  }

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_project_iam_member.function_storage_admin,
    google_project_iam_member.function_logging,
    google_project_iam_member.function_monitoring
  ]
}

# Allow unauthenticated invocation of the Cloud Function (if enabled)
resource "google_cloudfunctions2_function_iam_member" "invoker" {
  count = var.allow_unauthenticated_function_invocation ? 1 : 0
  
  project        = var.project_id
  location       = google_cloudfunctions2_function.task_processor.location
  cloud_function = google_cloudfunctions2_function.task_processor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create Cloud Tasks queue
resource "google_cloud_tasks_queue" "background_tasks" {
  name     = var.queue_name
  location = var.region
  
  # Configure retry settings for failed tasks
  retry_config {
    max_attempts       = var.queue_max_attempts
    max_retry_duration = var.queue_max_retry_duration
    max_doublings      = var.queue_max_doublings
    max_backoff        = "3600s"
    min_backoff        = "0.100s"
  }

  # Configure rate limits to prevent overwhelming the function
  rate_limits {
    max_dispatches_per_second = 10
    max_burst_size           = 100
    max_concurrent_dispatches = 50
  }

  depends_on = [google_project_service.required_apis]
}

# Optional: Create dead letter queue for failed tasks
resource "google_cloud_tasks_queue" "dead_letter_queue" {
  count = var.enable_dead_letter_queue ? 1 : 0
  
  name     = "${var.queue_name}-dlq"
  location = var.region
  
  # Minimal retry configuration for dead letter queue
  retry_config {
    max_attempts       = 1
    max_retry_duration = "60s"
    max_doublings      = 0
  }

  rate_limits {
    max_dispatches_per_second = 1
    max_burst_size           = 10
    max_concurrent_dispatches = 5
  }

  depends_on = [google_project_service.required_apis]
}


# Create IAM role for Cloud Tasks to invoke the function
resource "google_project_iam_member" "tasks_invoker" {
  project = var.project_id
  role    = "roles/cloudfunctions.invoker"
  member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloudtasks.iam.gserviceaccount.com"
}

# Optional: Create sample task creation script
resource "local_file" "task_creation_script" {
  count = var.create_sample_tasks ? 1 : 0
  
  content = templatefile("${path.module}/scripts_template/create_task.py", {
    project_id    = var.project_id
    region        = var.region
    queue_name    = var.queue_name
    function_url  = google_cloudfunctions2_function.task_processor.service_config[0].uri
  })
  filename = "${path.module}/create_task.py"
  
  depends_on = [google_cloudfunctions2_function.task_processor]
}

# Optional: Create monitoring resources
resource "google_monitoring_notification_channel" "email" {
  count = var.enable_monitoring && var.notification_email != "" ? 1 : 0
  
  display_name = "Task Queue Email Notifications"
  type         = "email"
  
  labels = {
    email_address = var.notification_email
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create alerting policy for queue depth
resource "google_monitoring_alert_policy" "queue_depth" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "High Task Queue Depth"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Queue depth too high"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_tasks_queue\" AND resource.label.queue_id=\"${var.queue_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 100
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  alert_strategy {
    auto_close = "86400s"  # 24 hours
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create alerting policy for function errors
resource "google_monitoring_alert_policy" "function_errors" {
  count = var.enable_monitoring ? 1 : 0
  
  display_name = "Cloud Function Error Rate"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Function error rate too high"
    
    condition_threshold {
      filter          = "resource.type=\"cloud_function\" AND resource.label.function_name=\"${var.function_name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 5
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }
  
  dynamic "notification_channels" {
    for_each = var.notification_email != "" ? [google_monitoring_notification_channel.email[0].id] : []
    content {
      notification_channels = [notification_channels.value]
    }
  }
  
  alert_strategy {
    auto_close = "86400s"  # 24 hours
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create custom dashboard for monitoring
resource "google_monitoring_dashboard" "task_queue_dashboard" {
  count = var.enable_monitoring ? 1 : 0
  
  dashboard_json = jsonencode({
    displayName = "Task Queue System Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Queue Depth"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_tasks_queue\" AND resource.label.queue_id=\"${var.queue_name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Queue Depth"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Function Invocations"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.label.function_name=\"${var.function_name}\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Invocations/sec"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          yPos   = 4
          widget = {
            title = "Function Execution Time"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.label.function_name=\"${var.function_name}\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_time\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Execution Time (ms)"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          yPos   = 4
          widget = {
            title = "Storage Bucket Objects"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gcs_bucket\" AND resource.label.bucket_name=\"${local.bucket_name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Object Count"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
  
  depends_on = [google_project_service.required_apis]
}