# =============================================================================
# Local Values and Data Sources
# =============================================================================

locals {
  # Generate unique suffix for resource names
  resource_suffix = random_id.suffix.hex
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_id
    region      = var.region
  })
  
  # Resource names
  bucket_name        = "${var.project_id}-${var.resource_prefix}-${local.resource_suffix}"
  migration_name     = "${var.resource_prefix}-${local.resource_suffix}"
  workload_name      = "${var.resource_prefix}-workload-${local.resource_suffix}"
  
  # Function source code paths
  function_source_dir = "${path.module}/functions"
}

# Generate random suffix for resource uniqueness
resource "random_id" "suffix" {
  byte_length = 3
}

# Get current project information
data "google_project" "current" {}

# =============================================================================
# Enable Required APIs
# =============================================================================

resource "google_project_service" "required_apis" {
  for_each = toset([
    "workloadmanager.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "datamigration.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])
  
  service = each.value
  project = var.project_id
  
  disable_dependent_services = false
  disable_on_destroy         = false
}

# =============================================================================
# Cloud Storage Bucket for Function Source and Monitoring Data
# =============================================================================

resource "google_storage_bucket" "monitoring_bucket" {
  name     = local.bucket_name
  location = var.region
  project  = var.project_id
  
  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  
  versioning {
    enabled = var.storage_versioning
  }
  
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

# =============================================================================
# Pub/Sub Topics and Subscriptions for Event-Driven Architecture
# =============================================================================

# Migration events topic
resource "google_pubsub_topic" "migration_events" {
  name    = "migration-events"
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Validation results topic
resource "google_pubsub_topic" "validation_results" {
  name    = "validation-results"
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Alert notifications topic
resource "google_pubsub_topic" "alert_notifications" {
  name    = "alert-notifications"
  project = var.project_id
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Subscriptions for Cloud Functions
resource "google_pubsub_subscription" "migration_monitor_sub" {
  name    = "migration-monitor-sub"
  topic   = google_pubsub_topic.migration_events.name
  project = var.project_id
  
  ack_deadline_seconds = 20
  
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  labels = local.common_labels
}

resource "google_pubsub_subscription" "validation_processor_sub" {
  name    = "validation-processor-sub"
  topic   = google_pubsub_topic.validation_results.name
  project = var.project_id
  
  ack_deadline_seconds = 600
  
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  labels = local.common_labels
}

resource "google_pubsub_subscription" "alert_manager_sub" {
  name    = "alert-manager-sub"
  topic   = google_pubsub_topic.alert_notifications.name
  project = var.project_id
  
  ack_deadline_seconds = 60
  
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  
  labels = local.common_labels
}

# =============================================================================
# Cloud SQL Instance for Migration Target
# =============================================================================

resource "google_sql_database_instance" "migration_target" {
  name             = "${local.migration_name}-target"
  database_version = var.database_version
  region           = var.region
  project          = var.project_id
  
  deletion_protection = var.enable_deletion_protection
  
  settings {
    tier              = var.database_tier
    availability_type = "ZONAL"
    disk_size         = var.database_storage_size
    disk_type         = "PD_SSD"
    disk_autoresize   = var.auto_scaling_enabled
    
    backup_configuration {
      enabled                        = true
      start_time                     = var.database_backup_time
      location                       = var.region
      binary_log_enabled             = true
      transaction_log_retention_days = 7
    }
    
    maintenance_window {
      day  = var.maintenance_window_day
      hour = var.maintenance_window_hour
    }
    
    ip_configuration {
      ipv4_enabled = !var.enable_private_ip
      
      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
    }
    
    database_flags {
      name  = "slow_query_log"
      value = "on"
    }
    
    database_flags {
      name  = "long_query_time"
      value = "2"
    }
    
    user_labels = local.common_labels
  }
  
  depends_on = [google_project_service.required_apis]
}

# Set root password for Cloud SQL instance
resource "google_sql_user" "root_user" {
  name     = "root"
  instance = google_sql_database_instance.migration_target.name
  host     = "%"
  password = "SecurePassword123!"
  project  = var.project_id
}

# Create application database
resource "google_sql_database" "application_db" {
  name     = var.database_name
  instance = google_sql_database_instance.migration_target.name
  project  = var.project_id
}

# =============================================================================
# Cloud Function Source Code Archives
# =============================================================================

# Create function source code locally
resource "local_file" "migration_monitor_source" {
  content = templatefile("${path.module}/function-templates/migration-monitor.py.tpl", {
    project_id = var.project_id
  })
  filename = "${local.function_source_dir}/migration-monitor/main.py"
}

resource "local_file" "migration_monitor_requirements" {
  content = file("${path.module}/function-templates/migration-monitor-requirements.txt")
  filename = "${local.function_source_dir}/migration-monitor/requirements.txt"
}

resource "local_file" "data_validator_source" {
  content = templatefile("${path.module}/function-templates/data-validator.py.tpl", {
    project_id = var.project_id
  })
  filename = "${local.function_source_dir}/data-validator/main.py"
}

resource "local_file" "data_validator_requirements" {
  content = file("${path.module}/function-templates/data-validator-requirements.txt")
  filename = "${local.function_source_dir}/data-validator/requirements.txt"
}

resource "local_file" "alert_manager_source" {
  content = templatefile("${path.module}/function-templates/alert-manager.py.tpl", {
    project_id = var.project_id
    notification_email = var.notification_email
    slack_webhook_url = var.slack_webhook_url
  })
  filename = "${local.function_source_dir}/alert-manager/main.py"
}

resource "local_file" "alert_manager_requirements" {
  content = file("${path.module}/function-templates/alert-manager-requirements.txt")
  filename = "${local.function_source_dir}/alert-manager/requirements.txt"
}

# Create ZIP archives for function deployment
data "archive_file" "migration_monitor_zip" {
  type        = "zip"
  source_dir  = "${local.function_source_dir}/migration-monitor"
  output_path = "${local.function_source_dir}/migration-monitor.zip"
  
  depends_on = [
    local_file.migration_monitor_source,
    local_file.migration_monitor_requirements
  ]
}

data "archive_file" "data_validator_zip" {
  type        = "zip"
  source_dir  = "${local.function_source_dir}/data-validator"
  output_path = "${local.function_source_dir}/data-validator.zip"
  
  depends_on = [
    local_file.data_validator_source,
    local_file.data_validator_requirements
  ]
}

data "archive_file" "alert_manager_zip" {
  type        = "zip"
  source_dir  = "${local.function_source_dir}/alert-manager"
  output_path = "${local.function_source_dir}/alert-manager.zip"
  
  depends_on = [
    local_file.alert_manager_source,
    local_file.alert_manager_requirements
  ]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "migration_monitor_source" {
  name   = "functions/migration-monitor-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.monitoring_bucket.name
  source = data.archive_file.migration_monitor_zip.output_path
}

resource "google_storage_bucket_object" "data_validator_source" {
  name   = "functions/data-validator-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.monitoring_bucket.name
  source = data.archive_file.data_validator_zip.output_path
}

resource "google_storage_bucket_object" "alert_manager_source" {
  name   = "functions/alert-manager-${local.resource_suffix}.zip"
  bucket = google_storage_bucket.monitoring_bucket.name
  source = data.archive_file.alert_manager_zip.output_path
}

# =============================================================================
# Cloud Functions for Migration Monitoring
# =============================================================================

# Migration monitoring function
resource "google_cloudfunctions_function" "migration_monitor" {
  name    = "migration-monitor"
  region  = var.region
  project = var.project_id
  
  runtime     = var.function_runtime
  entry_point = "monitor_migration"
  
  available_memory_mb = var.function_memory
  timeout             = var.function_timeout
  
  source_archive_bucket = google_storage_bucket.monitoring_bucket.name
  source_archive_object = google_storage_bucket_object.migration_monitor_source.name
  
  trigger {
    https_trigger {
      security_level = "SECURE_ALWAYS"
    }
  }
  
  environment_variables = {
    PROJECT_ID = var.project_id
    REGION     = var.region
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Data validation function
resource "google_cloudfunctions_function" "data_validator" {
  name    = "data-validator"
  region  = var.region
  project = var.project_id
  
  runtime     = var.function_runtime
  entry_point = "validate_migration_data"
  
  available_memory_mb = var.validation_function_memory
  timeout             = var.validation_function_timeout
  
  source_archive_bucket = google_storage_bucket.monitoring_bucket.name
  source_archive_object = google_storage_bucket_object.data_validator_source.name
  
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.validation_results.name
  }
  
  environment_variables = {
    PROJECT_ID = var.project_id
    REGION     = var.region
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Alert management function
resource "google_cloudfunctions_function" "alert_manager" {
  name    = "alert-manager"
  region  = var.region
  project = var.project_id
  
  runtime     = var.function_runtime
  entry_point = "manage_alerts"
  
  available_memory_mb = var.function_memory
  timeout             = var.function_timeout
  
  source_archive_bucket = google_storage_bucket.monitoring_bucket.name
  source_archive_object = google_storage_bucket_object.alert_manager_source.name
  
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.alert_notifications.name
  }
  
  environment_variables = {
    PROJECT_ID            = var.project_id
    REGION                = var.region
    NOTIFICATION_EMAIL    = var.notification_email
    SLACK_WEBHOOK_URL     = var.slack_webhook_url
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# =============================================================================
# Cloud Function IAM Permissions
# =============================================================================

# Allow public access to migration monitor function
resource "google_cloudfunctions_function_iam_member" "migration_monitor_invoker" {
  project        = var.project_id
  region         = var.region
  cloud_function = google_cloudfunctions_function.migration_monitor.name
  
  role   = "roles/cloudfunctions.invoker"
  member = "allUsers"
}

# Service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_prefix}-functions-sa"
  display_name = "Cloud Functions Service Account for Migration Monitoring"
  description  = "Service account for Cloud Functions to access monitoring resources"
  project      = var.project_id
}

# Grant necessary permissions to function service account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber",
    "roles/cloudsql.client",
    "roles/datamigration.viewer",
    "roles/workloadmanager.viewer"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# =============================================================================
# Cloud Workload Manager Evaluation
# =============================================================================

# Note: Cloud Workload Manager evaluation is created using gcloud CLI
# as Terraform provider support is limited. This resource serves as a placeholder
# and documents the configuration that would be applied via gcloud.

resource "null_resource" "workload_manager_evaluation" {
  triggers = {
    project_id     = var.project_id
    region         = var.region
    workload_name  = local.workload_name
    database_name  = google_sql_database_instance.migration_target.name
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      gcloud workload-manager evaluations create ${local.workload_name} \
        --location=${var.region} \
        --project=${var.project_id} \
        --workload-type=${var.workload_type} \
        --workload-uri="projects/${var.project_id}/locations/${var.region}/instances/${google_sql_database_instance.migration_target.name}" \
        --labels=environment=${var.environment},purpose=health-monitoring,managed-by=terraform
    EOT
  }
  
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      gcloud workload-manager evaluations delete ${self.triggers.workload_name} \
        --location=${self.triggers.region} \
        --project=${self.triggers.project_id} \
        --quiet
    EOT
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_sql_database_instance.migration_target
  ]
}

# =============================================================================
# Custom Monitoring Dashboard
# =============================================================================

resource "google_monitoring_dashboard" "migration_dashboard" {
  count = var.enable_monitoring_dashboard ? 1 : 0
  
  display_name = "Database Migration Monitoring"
  project      = var.project_id
  
  dashboard_json = jsonencode({
    displayName = "Database Migration Monitoring"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Migration Progress"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"custom.googleapis.com/migration/duration_seconds\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
              sparkChartView = {
                sparkChartType = "SPARK_LINE"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Data Validation Score"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"custom.googleapis.com/migration/validation_score\""
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
              sparkChartView = {
                sparkChartType = "SPARK_BAR"
              }
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 4
          widget = {
            title = "Cloud SQL Performance"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration = "0s"
              yAxis = {
                label = "CPU Utilization"
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
# Monitoring Alerts
# =============================================================================

# Alert policy for high CPU usage
resource "google_monitoring_alert_policy" "high_cpu_alert" {
  display_name = "High CPU Usage - Migration Target Database"
  project      = var.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "High CPU Usage"
    
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${var.project_id}:${google_sql_database_instance.migration_target.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.8
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  documentation {
    content = "CPU usage is high on the migration target database. This may indicate performance issues during migration."
  }
  
  depends_on = [google_project_service.required_apis]
}

# Alert policy for migration validation failures
resource "google_monitoring_alert_policy" "validation_failure_alert" {
  display_name = "Migration Validation Failures"
  project      = var.project_id
  combiner     = "OR"
  
  conditions {
    display_name = "Low Validation Score"
    
    condition_threshold {
      filter          = "metric.type=\"custom.googleapis.com/migration/validation_score\""
      duration        = "60s"
      comparison      = "COMPARISON_LESS_THAN"
      threshold_value = 95.0
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  documentation {
    content = "Migration validation score has dropped below 95%. This indicates potential data integrity issues."
  }
  
  depends_on = [google_project_service.required_apis]
}