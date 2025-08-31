# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Generate unique names for resources
  sql_instance_name = var.sql_instance_name != "" ? var.sql_instance_name : "${var.resource_prefix}-db-${random_id.suffix.hex}"
  function_name     = var.function_name != "" ? var.function_name : "${var.resource_prefix}-alert-handler-${random_id.suffix.hex}"
  alert_policy_name = var.alert_policy_name != "" ? var.alert_policy_name : "${var.resource_prefix}-slow-query-alerts-${random_id.suffix.hex}"
  bucket_name       = "${var.resource_prefix}-function-source-${random_id.suffix.hex}"
  
  # Merge default labels with user-provided labels
  common_labels = merge(var.labels, {
    terraform-managed = "true"
    recipe           = "automated-query-alerts-sql-functions"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset(var.required_apis) : []
  
  project = var.project_id
  service = each.key
  
  disable_dependent_services = false
  disable_on_destroy        = false
  
  timeouts {
    create = "10m"
    update = "10m"
  }
}

# Create Cloud Storage bucket for Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = local.bucket_name
  location = var.region
  
  # Prevent accidental deletion
  force_destroy = true
  
  # Enable versioning for function source code
  versioning {
    enabled = true
  }
  
  # Lifecycle management for old versions
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

# Create Cloud SQL PostgreSQL instance with Query Insights
resource "google_sql_database_instance" "postgres_instance" {
  name                = local.sql_instance_name
  database_version    = var.sql_database_version
  region              = var.region
  deletion_protection = false
  
  settings {
    tier              = var.sql_tier
    edition           = var.sql_edition
    availability_type = "ZONAL"
    
    # Disk configuration
    disk_size         = var.sql_disk_size
    disk_type         = "PD_SSD"
    disk_autoresize   = true
    
    # Backup configuration
    backup_configuration {
      enabled                        = true
      start_time                    = "02:00"
      point_in_time_recovery_enabled = true
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }
    
    # Query Insights configuration (Enterprise edition required)
    insights_config {
      query_insights_enabled  = true
      query_string_length     = 4500
      record_application_tags = true
      record_client_address   = true
    }
    
    # Maintenance window
    maintenance_window {
      day          = 6  # Saturday
      hour         = 2  # 2 AM
      update_track = "stable"
    }
    
    # Database flags for performance monitoring
    database_flags {
      name  = "log_statement"
      value = "all"
    }
    
    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"  # Log queries taking more than 1 second
    }
    
    database_flags {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements"
    }
    
    # IP configuration
    ip_configuration {
      # Enable public IP for demonstration purposes
      # In production, use private IP and authorized networks
      ipv4_enabled = true
      
      authorized_networks {
        name  = "all-networks"
        value = "0.0.0.0/0"
      }
    }
    
    user_labels = local.common_labels
  }
  
  depends_on = [google_project_service.required_apis]
}

# Set password for default postgres user
resource "google_sql_user" "postgres_user" {
  name     = "postgres"
  instance = google_sql_database_instance.postgres_instance.name
  password = var.db_root_password
}

# Create monitoring user
resource "google_sql_user" "monitor_user" {
  name     = "monitor_user"
  instance = google_sql_database_instance.postgres_instance.name
  password = var.db_monitor_password
}

# Create performance test database
resource "google_sql_database" "performance_test_db" {
  name     = var.database_name
  instance = google_sql_database_instance.postgres_instance.name
  
  depends_on = [google_sql_user.postgres_user]
}

# Create sample data using Cloud Function trigger (if enabled)
resource "google_storage_bucket_object" "sample_data_sql" {
  count = var.enable_sample_data ? 1 : 0
  
  name   = "sample_data.sql"
  bucket = google_storage_bucket.function_source.name
  content = templatefile("${path.module}/templates/sample_data.sql.tpl", {
    users_count  = var.sample_users_count
    orders_count = var.sample_orders_count
  })
  
  content_type = "text/plain"
}

# Create Cloud Function source code archive
data "archive_file" "function_source" {
  type        = "zip"
  output_path = "/tmp/query-alert-function-${random_id.suffix.hex}.zip"
  
  source {
    content = templatefile("${path.module}/templates/main.py.tpl", {
      project_id = var.project_id
    })
    filename = "main.py"
  }
  
  source {
    content  = file("${path.module}/templates/requirements.txt")
    filename = "requirements.txt"
  }
}

# Upload function source to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "query-alert-function-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  depends_on = [data.archive_file.function_source]
}

# Create Cloud Function for alert processing
resource "google_cloudfunctions2_function" "alert_processor" {
  name     = local.function_name
  location = var.region
  
  build_config {
    runtime     = "python311"
    entry_point = "process_query_alert"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "${var.function_memory}Mi"
    timeout_seconds       = var.function_timeout
    available_cpu         = "1"
    ingress_settings      = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
    
    environment_variables = {
      PROJECT_ID      = var.project_id
      SQL_INSTANCE    = google_sql_database_instance.postgres_instance.name
      DATABASE_NAME   = var.database_name
      ALERT_THRESHOLD = tostring(var.query_threshold_seconds)
    }
    
    service_account_email = google_service_account.function_sa.email
  }
  
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket_object.function_source
  ]
}

# Create service account for Cloud Function
resource "google_service_account" "function_sa" {
  account_id   = "${var.resource_prefix}-function-sa-${random_id.suffix.hex}"
  display_name = "Cloud Function Service Account for Query Alerts"
  description  = "Service account for processing database query performance alerts"
}

# Grant necessary permissions to function service account
resource "google_project_iam_member" "function_permissions" {
  for_each = toset([
    "roles/cloudsql.client",
    "roles/monitoring.metricWriter",
    "roles/logging.logWriter",
    "roles/storage.objectViewer"
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.function_sa.email}"
}

# Make Cloud Function publicly accessible for webhook
resource "google_cloudfunctions2_function_iam_member" "function_invoker" {
  project        = var.project_id
  location       = var.region
  cloud_function = google_cloudfunctions2_function.alert_processor.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create notification channel for webhook
resource "google_monitoring_notification_channel" "webhook_channel" {
  display_name = "Query Alert Webhook Channel"
  type         = "webhook_tokenauth"
  description  = "Webhook notification channel for database query performance alerts"
  
  labels = {
    url = google_cloudfunctions2_function.alert_processor.service_config[0].uri
  }
  
  enabled = true
  
  depends_on = [
    google_project_service.required_apis,
    google_cloudfunctions2_function.alert_processor
  ]
}

# Create alert policy for slow database queries
resource "google_monitoring_alert_policy" "slow_query_alert" {
  display_name = local.alert_policy_name
  combiner     = "OR"
  enabled      = true
  
  documentation {
    content   = "Alert triggered when database queries exceed ${var.query_threshold_seconds} seconds execution time. Review Query Insights dashboard for detailed analysis at https://console.cloud.google.com/sql/instances/${google_sql_database_instance.postgres_instance.name}/insights?project=${var.project_id}"
    mime_type = "text/markdown"
  }
  
  conditions {
    display_name = "Query execution time > ${var.query_threshold_seconds} seconds"
    
    condition_threshold {
      filter         = "resource.type=\"cloudsql_database\" AND resource.labels.database_id=\"${var.project_id}:${google_sql_database_instance.postgres_instance.name}\" AND metric.type=\"cloudsql.googleapis.com/database/query_insights/execution_time\""
      duration       = "60s"
      comparison     = "COMPARISON_GREATER_THAN"
      threshold_value = var.query_threshold_seconds
      
      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.label.database_id"]
      }
      
      trigger {
        count = 1
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.webhook_channel.name]
  
  alert_strategy {
    auto_close = var.alert_auto_close_duration
  }
  
  user_labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_sql_database_instance.postgres_instance,
    google_monitoring_notification_channel.webhook_channel
  ]
}

# Create Cloud Logging sink for structured alert logs
resource "google_logging_project_sink" "alert_logs" {
  name        = "${var.resource_prefix}-query-alert-logs-${random_id.suffix.hex}"
  description = "Logging sink for database query performance alerts"
  
  # Export to Cloud Storage for long-term retention
  destination = "storage.googleapis.com/${google_storage_bucket.function_source.name}/alert-logs"
  
  # Filter for function logs and alert events
  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${google_cloudfunctions2_function.alert_processor.name}\" AND (textPayload:\"QUERY_PERFORMANCE_ALERT\" OR jsonPayload.alert_type=\"Database Query Performance\")"
  
  # Create unique writer identity for this sink
  unique_writer_identity = true
  
  depends_on = [google_cloudfunctions2_function.alert_processor]
}

# Grant storage permissions to logging sink
resource "google_storage_bucket_iam_member" "logging_sink_writer" {
  bucket = google_storage_bucket.function_source.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.alert_logs.writer_identity
}