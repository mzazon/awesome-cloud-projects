# Multi-Tenant Resource Scheduling with Cloud Scheduler and Cloud Filestore
# This Terraform configuration deploys a complete multi-tenant resource scheduling system

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  resource_suffix = var.resource_suffix != "" ? var.resource_suffix : "mt-${random_id.suffix.hex}"
  common_labels = merge(var.labels, {
    environment = var.environment
    managed_by  = "terraform"
    component   = "multi-tenant-scheduler"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "file.googleapis.com",
    "monitoring.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "logging.googleapis.com",
    "iam.googleapis.com"
  ]) : toset([])

  project                    = var.project_id
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy        = false
}

# Service account for Cloud Function with minimal required permissions
resource "google_service_account" "function_sa" {
  account_id   = "scheduler-function-${local.resource_suffix}"
  display_name = "Multi-Tenant Scheduler Function Service Account"
  description  = "Service account for the multi-tenant resource scheduler Cloud Function"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# IAM roles for the function service account
resource "google_project_iam_member" "function_sa_roles" {
  for_each = toset([
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/file.editor"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"

  depends_on = [google_service_account.function_sa]
}

# Cloud Filestore instance for shared tenant storage
resource "google_filestore_instance" "tenant_storage" {
  name     = "tenant-data-${local.resource_suffix}"
  location = var.zone
  tier     = var.filestore_tier
  project  = var.project_id

  file_shares {
    name        = var.filestore_share_name
    capacity_gb = var.filestore_capacity_gb
  }

  networks {
    network = "projects/${var.project_id}/global/networks/${var.network_name}"
    modes   = ["MODE_IPV4"]
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "function-source-${local.resource_suffix}-${var.project_id}"
  location = var.region
  project  = var.project_id

  uniform_bucket_level_access = true
  force_destroy              = true

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Create the Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      filestore_ip = google_filestore_instance.tenant_storage.networks[0].ip_addresses[0]
      project_id   = var.project_id
      tenant_quotas = jsonencode(var.tenant_quotas)
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/function_code/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path

  depends_on = [data.archive_file.function_source]
}

# Cloud Function for resource orchestration
resource "google_cloudfunctions_function" "resource_scheduler" {
  name                  = "resource-scheduler-${local.resource_suffix}"
  project               = var.project_id
  region                = var.region
  runtime               = var.function_runtime
  available_memory_mb   = var.function_memory_mb
  timeout               = var.function_timeout_seconds
  entry_point          = "schedule_tenant_resources"
  service_account_email = var.function_service_account_email != "" ? var.function_service_account_email : google_service_account.function_sa.email

  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name

  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  environment_variables = {
    FILESTORE_IP = google_filestore_instance.tenant_storage.networks[0].ip_addresses[0]
    GCP_PROJECT  = var.project_id
    TENANT_QUOTAS = jsonencode(var.tenant_quotas)
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_project_iam_member.function_sa_roles
  ]
}

# IAM binding to allow unauthenticated access to function (if enabled)
resource "google_cloudfunctions_function_iam_member" "invoker" {
  count = var.allow_unauthenticated_function ? 1 : 0

  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.resource_scheduler.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"

  depends_on = [google_cloudfunctions_function.resource_scheduler]
}

# Cloud Scheduler jobs for automated tenant management
resource "google_cloud_scheduler_job" "tenant_cleanup" {
  count = var.enable_scheduled_jobs ? 1 : 0

  name             = "tenant-cleanup-${local.resource_suffix}"
  project          = var.project_id
  region           = var.region
  description      = "Daily cleanup of expired tenant resources"
  schedule         = "0 2 * * *"
  time_zone        = var.scheduler_timezone
  attempt_deadline = "300s"

  retry_config {
    retry_count = 3
  }

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.resource_scheduler.https_trigger_url
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      action    = "cleanup"
      tenant_id = "all"
    }))

    oidc_token {
      service_account_email = google_service_account.function_sa.email
    }
  }

  depends_on = [
    google_cloudfunctions_function.resource_scheduler,
    google_project_service.required_apis
  ]
}

resource "google_cloud_scheduler_job" "quota_monitor" {
  count = var.enable_scheduled_jobs ? 1 : 0

  name             = "quota-monitor-${local.resource_suffix}"
  project          = var.project_id
  region           = var.region
  description      = "Monitor tenant quota usage every 6 hours"
  schedule         = "0 */6 * * *"
  time_zone        = var.scheduler_timezone
  attempt_deadline = "300s"

  retry_config {
    retry_count = 3
  }

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.resource_scheduler.https_trigger_url
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      action    = "monitor_quotas"
      tenant_id = "all"
    }))

    oidc_token {
      service_account_email = google_service_account.function_sa.email
    }
  }

  depends_on = [
    google_cloudfunctions_function.resource_scheduler,
    google_project_service.required_apis
  ]
}

resource "google_cloud_scheduler_job" "tenant_a_processing" {
  count = var.enable_scheduled_jobs ? 1 : 0

  name             = "tenant-a-processing-${local.resource_suffix}"
  project          = var.project_id
  region           = var.region
  description      = "Weekday resource allocation for Tenant A"
  schedule         = "0 9 * * 1-5"
  time_zone        = var.scheduler_timezone
  attempt_deadline = "300s"

  retry_config {
    retry_count = 3
  }

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.resource_scheduler.https_trigger_url
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      tenant_id     = "tenant_a"
      resource_type = "compute"
      capacity      = 5
      duration      = 8
    }))

    oidc_token {
      service_account_email = google_service_account.function_sa.email
    }
  }

  depends_on = [
    google_cloudfunctions_function.resource_scheduler,
    google_project_service.required_apis
  ]
}

# Cloud Monitoring alert policy for tenant quota violations
resource "google_monitoring_alert_policy" "quota_violation" {
  count = var.enable_monitoring ? 1 : 0

  display_name = "Tenant Quota Violation Alert - ${local.resource_suffix}"
  project      = var.project_id
  combiner     = "OR"
  enabled      = true

  documentation {
    content = "Alert when tenant exceeds ${var.quota_alert_threshold}% of allocated quota"
  }

  conditions {
    display_name = "Quota usage high"
    
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/tenant/resource_allocations\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.quota_alert_threshold / 100 * max(values(var.tenant_quotas)...)

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.resource_scheduler
  ]
}

# Cloud Monitoring dashboard for tenant resource monitoring
resource "google_monitoring_dashboard" "tenant_dashboard" {
  count = var.enable_monitoring ? 1 : 0

  dashboard_json = jsonencode({
    displayName = "Multi-Tenant Resource Dashboard - ${local.resource_suffix}"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Tenant Resource Allocations"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"custom.googleapis.com/tenant/resource_allocations\""
                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = ["metric.label.tenant_id"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Resource Units"
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
            title = "Function Execution Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "metric.type=\"cloudfunctions.googleapis.com/function/executions\" AND resource.label.function_name=\"${google_cloudfunctions_function.resource_scheduler.name}\""
                      aggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Executions per Second"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })

  project = var.project_id

  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions_function.resource_scheduler
  ]
}

# Cloud Logging sink for function logs (optional)
resource "google_logging_project_sink" "function_logs" {
  count = var.enable_monitoring ? 1 : 0

  name        = "function-logs-${local.resource_suffix}"
  destination = "storage.googleapis.com/${google_storage_bucket.function_source.name}/logs"
  project     = var.project_id

  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions_function.resource_scheduler.name}\""

  unique_writer_identity = true

  depends_on = [
    google_cloudfunctions_function.resource_scheduler,
    google_storage_bucket.function_source
  ]
}

# Grant the logging sink permission to write to the bucket
resource "google_storage_bucket_iam_member" "log_writer" {
  count = var.enable_monitoring ? 1 : 0

  bucket = google_storage_bucket.function_source.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.function_logs[0].writer_identity

  depends_on = [google_logging_project_sink.function_logs]
}