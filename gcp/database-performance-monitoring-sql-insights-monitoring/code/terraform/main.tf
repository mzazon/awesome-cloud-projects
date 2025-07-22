# GCP Database Performance Monitoring Infrastructure
# This Terraform configuration deploys a comprehensive database monitoring solution
# using Cloud SQL with Query Insights, Cloud Monitoring, and automated alerting

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent naming and configuration
locals {
  name_prefix = "${var.database_name}-${var.environment}"
  name_suffix = random_id.suffix.hex
  
  # Common labels applied to all resources
  common_labels = merge(var.labels, {
    environment = var.environment
    component   = "database-monitoring"
    terraform   = "true"
  })
  
  # Generated database password if not provided
  db_password = var.database_root_password != "" ? var.database_root_password : random_password.db_password[0].result
}

# Generate secure random password for database if not provided
resource "random_password" "db_password" {
  count   = var.database_root_password == "" ? 1 : 0
  length  = 16
  special = true
}

# Enable required Google Cloud APIs for the monitoring solution
resource "google_project_service" "required_apis" {
  for_each = toset([
    "sqladmin.googleapis.com",
    "monitoring.googleapis.com",
    "cloudfunctions.googleapis.com",
    "pubsub.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
}

# Create Cloud SQL instance with Enterprise Plus edition and Query Insights
resource "google_sql_database_instance" "performance_monitoring_db" {
  name             = "${local.name_prefix}-${local.name_suffix}"
  database_version = var.database_version
  region          = var.region
  
  # Enterprise Plus edition for advanced Query Insights features
  edition = "ENTERPRISE_PLUS"
  
  settings {
    tier              = var.database_tier
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.storage_size_gb
    disk_autoresize   = true
    
    # Enable Query Insights for comprehensive performance monitoring
    insights_config {
      query_insights_enabled              = var.enable_query_insights
      query_string_length                = var.query_string_length
      record_application_tags            = var.record_application_tags
      record_client_address              = var.record_client_address
      query_plans_per_minute             = 5
    }
    
    # Backup configuration for data protection
    backup_configuration {
      enabled                        = var.enable_backup
      start_time                    = var.backup_start_time
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 30
        retention_unit   = "COUNT"
      }
    }
    
    # IP configuration and security settings
    ip_configuration {
      ipv4_enabled = true
      
      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          name  = authorized_networks.value.name
          value = authorized_networks.value.value
        }
      }
    }
    
    # Maintenance window configuration
    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = "stable"
    }
    
    # Performance and monitoring flags
    database_flags {
      name  = "log_statement"
      value = "all"
    }
    
    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"
    }
    
    database_flags {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements"
    }
    
    user_labels = local.common_labels
  }
  
  deletion_protection = var.deletion_protection
  
  depends_on = [google_project_service.required_apis]
}

# Set password for the default postgres user
resource "google_sql_user" "postgres_user" {
  name     = "postgres"
  instance = google_sql_database_instance.performance_monitoring_db.name
  password = local.db_password
}

# Create test database for performance monitoring validation
resource "google_sql_database" "performance_test_db" {
  name     = "performance_test"
  instance = google_sql_database_instance.performance_monitoring_db.name
}

# Create Pub/Sub topic for alert notifications
resource "google_pubsub_topic" "db_alerts" {
  name = "${local.name_prefix}-alerts-${local.name_suffix}"
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create Cloud Storage bucket for performance reports
resource "google_storage_bucket" "performance_reports" {
  name     = "${local.name_prefix}-reports-${local.name_suffix}"
  location = var.storage_location
  
  storage_class = var.storage_class
  
  # Enable versioning for report history
  versioning {
    enabled = true
  }
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = 90
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
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "${local.name_prefix}-func-sa-${local.name_suffix}"
  display_name = "Database Alert Function Service Account"
  description  = "Service account for database performance alert processing function"
}

# Grant necessary permissions to the function service account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/storage.admin",
    "roles/monitoring.viewer",
    "roles/logging.writer",
    "roles/pubsub.subscriber"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Create Cloud Function for automated alert processing
resource "google_cloudfunctions_function" "db_alert_handler" {
  name        = "${local.name_prefix}-alert-handler-${local.name_suffix}"
  description = "Processes database performance alerts and generates insights"
  runtime     = "python39"
  region      = var.region
  
  available_memory_mb   = var.function_memory_mb
  timeout              = var.function_timeout_seconds
  entry_point          = "process_db_alert"
  service_account_email = google_service_account.function_sa.email
  
  source_archive_bucket = google_storage_bucket.function_source.name
  source_archive_object = google_storage_bucket_object.function_source.name
  
  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.db_alerts.name
  }
  
  environment_variables = {
    BUCKET_NAME = google_storage_bucket.performance_reports.name
    PROJECT_ID  = var.project_id
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = "${local.name_prefix}-function-source-${local.name_suffix}"
  location = var.region
  
  labels = local.common_labels
}

# Create the function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/function-source.zip"
  
  source {
    content = templatefile("${path.module}/function_code/main.py", {
      bucket_name = google_storage_bucket.performance_reports.name
      project_id  = var.project_id
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
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# Create notification channel for Pub/Sub integration
resource "google_monitoring_notification_channel" "pubsub_channel" {
  display_name = "Database Alert Processing Channel"
  type         = "pubsub"
  
  labels = {
    topic = google_pubsub_topic.db_alerts.id
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create alerting policy for high CPU usage
resource "google_monitoring_alert_policy" "high_cpu_usage" {
  display_name = "Cloud SQL High CPU Usage - ${local.name_prefix}"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "CPU utilization is high"
    
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${var.project_id}:${google_sql_database_instance.performance_monitoring_db.name}\" AND metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\""
      duration        = "${var.alert_duration}s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.cpu_threshold
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.pubsub_channel.id]
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create alerting policy for slow query detection
resource "google_monitoring_alert_policy" "slow_query_detection" {
  display_name = "Cloud SQL Slow Query Detection - ${local.name_prefix}"
  combiner     = "OR"
  enabled      = true
  
  conditions {
    display_name = "Query execution time is high"
    
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${var.project_id}:${google_sql_database_instance.performance_monitoring_db.name}\" AND metric.type=\"cloudsql.googleapis.com/insights/aggregate/execution_time\""
      duration        = "180s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.slow_query_threshold_ms
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.pubsub_channel.id]
  
  alert_strategy {
    auto_close = "1800s"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create custom monitoring dashboard for database performance
resource "google_monitoring_dashboard" "db_performance_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Cloud SQL Performance Monitoring Dashboard - ${local.name_prefix}"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Database Connections"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${var.project_id}:${google_sql_database_instance.performance_monitoring_db.name}\" AND metric.type=\"cloudsql.googleapis.com/database/network/connections\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                }
              ]
              yAxis = {
                label = "Connections"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "CPU Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${var.project_id}:${google_sql_database_instance.performance_monitoring_db.name}\" AND metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                }
              ]
              yAxis = {
                label = "Utilization"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 12
          height = 4
          widget = {
            title = "Query Insights - Top Queries by Execution Time"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${var.project_id}:${google_sql_database_instance.performance_monitoring_db.name}\" AND metric.type=\"cloudsql.googleapis.com/insights/aggregate/execution_time\""
                      aggregation = {
                        alignmentPeriod     = "300s"
                        perSeriesAligner    = "ALIGN_MEAN"
                        crossSeriesReducer  = "REDUCE_SUM"
                        groupByFields       = ["metric.label.query_hash"]
                      }
                    }
                  }
                }
              ]
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
          widget = {
            title = "Memory Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${var.project_id}:${google_sql_database_instance.performance_monitoring_db.name}\" AND metric.type=\"cloudsql.googleapis.com/database/memory/utilization\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                }
              ]
              yAxis = {
                label = "Utilization"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          widget = {
            title = "Disk I/O Operations"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${var.project_id}:${google_sql_database_instance.performance_monitoring_db.name}\" AND metric.type=\"cloudsql.googleapis.com/database/disk/read_ops_count\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                }
              ]
              yAxis = {
                label = "Operations/sec"
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