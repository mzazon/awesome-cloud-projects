# =============================================================================
# Database Maintenance Automation with Cloud SQL and Cloud Scheduler
# =============================================================================
# This Terraform configuration deploys a complete database maintenance
# automation solution using:
# - Cloud SQL MySQL instance with performance monitoring
# - Cloud Functions for automated maintenance tasks
# - Cloud Scheduler for precise timing control
# - Cloud Storage for maintenance logs and artifacts
# - Cloud Monitoring for comprehensive observability
# =============================================================================

# Random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  name_suffix     = random_id.suffix.hex
  region         = var.region
  zone          = var.zone
  
  # Resource names with unique suffix
  db_instance_name     = "maintenance-db-${local.name_suffix}"
  function_name        = "db-maintenance-${local.name_suffix}"
  scheduler_job_name   = "db-scheduler-${local.name_suffix}"
  bucket_name         = "db-maintenance-logs-${var.project_id}-${local.name_suffix}"
  
  # Database configuration
  db_user_name    = "maintenance_user"
  db_name         = "maintenance_app"
  
  # Common labels for resource organization
  common_labels = {
    environment = var.environment
    project     = "database-maintenance-automation"
    managed_by  = "terraform"
  }
}

# =============================================================================
# DATA SOURCES
# =============================================================================

# Get current project information
data "google_project" "current" {}

# Get current client configuration
data "google_client_config" "current" {}

# =============================================================================
# CLOUD STORAGE BUCKET FOR MAINTENANCE LOGS
# =============================================================================

# Storage bucket for maintenance logs, artifacts, and automation scripts
resource "google_storage_bucket" "maintenance_logs" {
  name                        = local.bucket_name
  location                   = local.region
  project                    = var.project_id
  storage_class              = "STANDARD"
  uniform_bucket_level_access = true
  force_destroy              = true

  # Lifecycle policy for cost optimization
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
      age = 365
    }
    action {
      type = "Delete"
    }
  }

  # Versioning for audit trail
  versioning {
    enabled = true
  }

  labels = local.common_labels
}

# =============================================================================
# CLOUD SQL INSTANCE CONFIGURATION
# =============================================================================

# Cloud SQL MySQL instance with performance monitoring and automated backups
resource "google_sql_database_instance" "maintenance_db" {
  name             = local.db_instance_name
  project          = var.project_id
  region           = local.region
  database_version = "MYSQL_8_0"
  deletion_protection = false

  settings {
    tier              = var.db_tier
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.db_disk_size
    disk_autoresize   = true

    # Backup configuration
    backup_configuration {
      enabled                        = true
      start_time                    = "02:00"
      point_in_time_recovery_enabled = true
      binary_log_enabled            = true
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    # Maintenance window configuration
    maintenance_window {
      day  = 7  # Sunday
      hour = 3  # 3 AM
    }

    # Database flags for performance monitoring
    database_flags {
      name  = "slow_query_log"
      value = "on"
    }

    database_flags {
      name  = "long_query_time"
      value = "2"
    }

    database_flags {
      name  = "log_output"
      value = "TABLE"
    }

    # IP configuration
    ip_configuration {
      ipv4_enabled = true
      authorized_networks {
        name  = "allow-all"
        value = "0.0.0.0/0"
      }
    }

    # Enable insights for performance monitoring
    insights_config {
      query_insights_enabled  = true
      record_application_tags = true
      record_client_address  = true
    }
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Database for application data
resource "google_sql_database" "app_database" {
  name     = local.db_name
  instance = google_sql_database_instance.maintenance_db.name
  project  = var.project_id
}

# Database user with appropriate permissions
resource "google_sql_user" "maintenance_user" {
  name     = local.db_user_name
  instance = google_sql_database_instance.maintenance_db.name
  project  = var.project_id
  password = var.db_password
}

# =============================================================================
# SERVICE ACCOUNT FOR CLOUD FUNCTION
# =============================================================================

# Service account for Cloud Function with least privilege permissions
resource "google_service_account" "function_sa" {
  account_id   = "db-maintenance-function-${local.name_suffix}"
  display_name = "Database Maintenance Function Service Account"
  description  = "Service account for database maintenance Cloud Function"
  project      = var.project_id
}

# IAM bindings for function service account
resource "google_project_iam_member" "function_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_storage_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

resource "google_project_iam_member" "function_logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# =============================================================================
# CLOUD FUNCTION FOR DATABASE MAINTENANCE
# =============================================================================

# Archive the function source code
data "archive_file" "function_zip" {
  type        = "zip"
  output_path = "${path.module}/function-source.zip"
  source_dir  = "${path.module}/function-source"
}

# Storage bucket object for function source code
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.maintenance_logs.name
  source = data.archive_file.function_zip.output_path

  depends_on = [data.archive_file.function_zip]
}

# Cloud Function for database maintenance tasks
resource "google_cloudfunctions_function" "maintenance_function" {
  name                  = local.function_name
  project               = var.project_id
  region                = local.region
  runtime              = "python39"
  available_memory_mb  = 256
  timeout              = 540
  entry_point          = "database_maintenance"
  service_account_email = google_service_account.function_sa.email

  source_archive_bucket = google_storage_bucket.maintenance_logs.name
  source_archive_object = google_storage_bucket_object.function_source.name

  trigger {
    http_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }

  environment_variables = {
    DB_USER        = local.db_user_name
    DB_NAME        = local.db_name
    DB_PASSWORD    = var.db_password
    BUCKET_NAME    = google_storage_bucket.maintenance_logs.name
    CONNECTION_NAME = "${var.project_id}:${local.region}:${google_sql_database_instance.maintenance_db.name}"
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source,
    google_sql_database_instance.maintenance_db
  ]
}

# =============================================================================
# SERVICE ACCOUNT FOR CLOUD SCHEDULER
# =============================================================================

# Service account for Cloud Scheduler
resource "google_service_account" "scheduler_sa" {
  account_id   = "db-scheduler-${local.name_suffix}"
  display_name = "Database Maintenance Scheduler Service Account"
  description  = "Service account for database maintenance Cloud Scheduler jobs"
  project      = var.project_id
}

# IAM binding for scheduler to invoke Cloud Function
resource "google_cloudfunctions_function_iam_member" "scheduler_invoker" {
  project        = var.project_id
  region         = local.region
  cloud_function = google_cloudfunctions_function.maintenance_function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.scheduler_sa.email}"
}

# =============================================================================
# CLOUD SCHEDULER JOBS
# =============================================================================

# Main daily maintenance job at 2 AM EST
resource "google_cloud_scheduler_job" "daily_maintenance" {
  name        = local.scheduler_job_name
  project     = var.project_id
  region      = local.region
  description = "Daily database maintenance automation"
  schedule    = var.maintenance_schedule
  time_zone   = var.timezone

  retry_config {
    retry_count          = 3
    max_retry_duration   = "600s"
    min_backoff_duration = "60s"
    max_backoff_duration = "300s"
  }

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.maintenance_function.https_trigger_url

    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
    }

    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      action = "daily_maintenance"
    }))
  }

  depends_on = [google_project_service.required_apis]
}

# Performance monitoring job every 6 hours (conditional)
resource "google_cloud_scheduler_job" "performance_monitoring" {
  count       = var.enable_performance_monitoring ? 1 : 0
  name        = "${local.scheduler_job_name}-monitor"
  project     = var.project_id
  region      = local.region
  description = "Database performance monitoring"
  schedule    = var.monitoring_schedule
  time_zone   = var.timezone

  retry_config {
    retry_count          = 2
    max_retry_duration   = "300s"
    min_backoff_duration = "60s"
    max_backoff_duration = "180s"
  }

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions_function.maintenance_function.https_trigger_url

    oidc_token {
      service_account_email = google_service_account.scheduler_sa.email
    }

    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      action = "performance_monitoring"
    }))
  }

  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# CLOUD MONITORING ALERTING POLICIES
# =============================================================================

# Notification channel for alerts (email)
resource "google_monitoring_notification_channel" "email" {
  count        = var.alert_email != "" && var.enable_alerting_policies ? 1 : 0
  display_name = "Database Maintenance Email Alerts"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.alert_email
  }
}

# Alerting policy for high CPU usage
resource "google_monitoring_alert_policy" "high_cpu" {
  count                 = var.enable_alerting_policies ? 1 : 0
  display_name          = "Cloud SQL High CPU Usage - ${local.db_instance_name}"
  project              = var.project_id
  combiner             = "OR"
  enabled              = true
  notification_channels = var.alert_email != "" && var.enable_alerting_policies ? [google_monitoring_notification_channel.email[0].id] : []

  conditions {
    display_name = "Cloud SQL CPU > 80%"

    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND resource.labels.database_id=\"${var.project_id}:${google_sql_database_instance.maintenance_db.name}\" AND metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.8

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "Alert when Cloud SQL CPU usage exceeds 80% for 5 minutes"
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.required_apis]
}

# Alerting policy for high connection count
resource "google_monitoring_alert_policy" "high_connections" {
  count                 = var.enable_alerting_policies ? 1 : 0
  display_name          = "Cloud SQL High Connection Count - ${local.db_instance_name}"
  project              = var.project_id
  combiner             = "OR"
  enabled              = true
  notification_channels = var.alert_email != "" && var.enable_alerting_policies ? [google_monitoring_notification_channel.email[0].id] : []

  conditions {
    display_name = "High Connection Count"

    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND resource.labels.database_id=\"${var.project_id}:${google_sql_database_instance.maintenance_db.name}\" AND metric.type=\"cloudsql.googleapis.com/database/mysql/connections\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 80

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "Alert when active connections exceed 80"
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# CLOUD MONITORING DASHBOARD
# =============================================================================

# Custom monitoring dashboard for database insights
resource "google_monitoring_dashboard" "database_maintenance" {
  count          = var.enable_monitoring_dashboard ? 1 : 0
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "Database Maintenance Dashboard - ${local.db_instance_name}"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Database CPU Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudsql_database\" AND resource.labels.database_id=\"${var.project_id}:${google_sql_database_instance.maintenance_db.name}\" AND metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                      }
                    }
                  }
                }
              ]
              yAxis = {
                label = "CPU Utilization (%)"
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
            title = "Active Connections"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudsql_database\" AND resource.labels.database_id=\"${var.project_id}:${google_sql_database_instance.maintenance_db.name}\" AND metric.type=\"cloudsql.googleapis.com/database/mysql/connections\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                      }
                    }
                  }
                }
              ]
              yAxis = {
                label = "Connection Count"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "Database Memory Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudsql_database\" AND resource.labels.database_id=\"${var.project_id}:${google_sql_database_instance.maintenance_db.name}\" AND metric.type=\"cloudsql.googleapis.com/database/memory/utilization\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                      }
                    }
                  }
                }
              ]
              yAxis = {
                label = "Memory Utilization (%)"
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

# =============================================================================
# REQUIRED APIS
# =============================================================================

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "sqladmin.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com"
  ])

  project = var.project_id
  service = each.value

  disable_dependent_services = false
  disable_on_destroy        = false
}