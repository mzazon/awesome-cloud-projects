# Session Management Infrastructure with Cloud Memorystore and Firebase Auth
# This configuration creates a high-performance session management system

# Generate random suffix for unique resource names
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # Common naming convention
  name_suffix = random_id.suffix.hex
  
  # Function source code directory
  function_source_dir = "${path.module}/function_code"
  
  # Labels applied to all resources
  common_labels = merge(var.labels, {
    component = "session-management"
  })
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "redis.googleapis.com",
    "cloudfunctions.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudscheduler.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "firebase.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "run.googleapis.com"
  ]) : toset([])

  service                    = each.value
  project                    = var.project_id
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Data sources for project information
data "google_project" "project" {
  project_id = var.project_id
}

# Create Cloud Memorystore Redis instance for session storage
resource "google_redis_instance" "session_store" {
  name           = "${var.redis_instance_name}-${local.name_suffix}"
  memory_size_gb = var.redis_memory_size_gb
  region         = var.region
  tier           = var.redis_tier
  redis_version  = var.redis_version
  
  display_name = "Session Store Redis Instance"
  
  # Security and maintenance configuration
  auth_enabled                = true
  transit_encryption_mode     = "SERVER_AUTHENTICATION"
  
  # Maintenance window during low-traffic hours
  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 2
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }
  
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
  
  lifecycle {
    prevent_destroy = var.deletion_protection
  }
}

# Create Secret Manager secret for Redis connection details
resource "google_secret_manager_secret" "redis_connection" {
  secret_id = "${var.secret_name_prefix}-${local.name_suffix}"
  
  labels = local.common_labels
  
  replication {
    auto {}
  }
  
  depends_on = [google_project_service.required_apis]
}

# Store Redis connection string in Secret Manager
resource "google_secret_manager_secret_version" "redis_connection" {
  secret = google_secret_manager_secret.redis_connection.id
  
  secret_data = jsonencode({
    host            = google_redis_instance.session_store.host
    port            = google_redis_instance.session_store.port
    auth_string     = google_redis_instance.session_store.auth_string
    connection_url  = "redis://:${google_redis_instance.session_store.auth_string}@${google_redis_instance.session_store.host}:${google_redis_instance.session_store.port}"
  })
  
  lifecycle {
    create_before_destroy = true
  }
}

# Service account for Cloud Functions
resource "google_service_account" "function_sa" {
  account_id   = "session-functions-${local.name_suffix}"
  display_name = "Session Management Functions Service Account"
  description  = "Service account for session management Cloud Functions"
}

# IAM binding for Secret Manager access
resource "google_secret_manager_secret_iam_binding" "function_secret_access" {
  secret_id = google_secret_manager_secret.redis_connection.id
  role      = "roles/secretmanager.secretAccessor"
  
  members = [
    "serviceAccount:${google_service_account.function_sa.email}"
  ]
}

# IAM bindings for function service account
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

# Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-session-functions-${local.name_suffix}"
  location = var.region
  
  labels = local.common_labels
  
  uniform_bucket_level_access = true
  
  # Auto-delete objects after 30 days for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create function source code directory and files
resource "local_file" "session_function_package_json" {
  content = jsonencode({
    name = "session-manager"
    version = "1.0.0"
    main = "index.js"
    dependencies = {
      "redis" = "^4.6.0"
      "firebase-admin" = "^11.11.0"
      "express" = "^4.18.0"
      "@google-cloud/secret-manager" = "^5.0.0"
      "@google-cloud/logging" = "^10.0.0"
      "@google-cloud/functions-framework" = "^3.3.0"
    }
  })
  filename = "${local.function_source_dir}/session-manager/package.json"
}

resource "local_file" "session_function_code" {
  content = templatefile("${path.module}/templates/session-manager.js.tpl", {
    secret_name = google_secret_manager_secret.redis_connection.id
    project_id  = var.project_id
  })
  filename = "${local.function_source_dir}/session-manager/index.js"
}

resource "local_file" "cleanup_function_package_json" {
  content = jsonencode({
    name = "session-cleanup"
    version = "1.0.0"
    main = "index.js"
    dependencies = {
      "redis" = "^4.6.0"
      "@google-cloud/secret-manager" = "^5.0.0"
      "@google-cloud/logging" = "^10.0.0"
      "@google-cloud/functions-framework" = "^3.3.0"
    }
  })
  filename = "${local.function_source_dir}/session-cleanup/package.json"
}

resource "local_file" "cleanup_function_code" {
  content = templatefile("${path.module}/templates/session-cleanup.js.tpl", {
    secret_name    = google_secret_manager_secret.redis_connection.id
    project_id     = var.project_id
    session_ttl_hours = var.session_ttl_hours
  })
  filename = "${local.function_source_dir}/session-cleanup/index.js"
}

# Create ZIP archives for function deployment
data "archive_file" "session_function_zip" {
  type        = "zip"
  source_dir  = "${local.function_source_dir}/session-manager"
  output_path = "${local.function_source_dir}/session-manager.zip"
  
  depends_on = [
    local_file.session_function_package_json,
    local_file.session_function_code
  ]
}

data "archive_file" "cleanup_function_zip" {
  type        = "zip"
  source_dir  = "${local.function_source_dir}/session-cleanup"
  output_path = "${local.function_source_dir}/session-cleanup.zip"
  
  depends_on = [
    local_file.cleanup_function_package_json,
    local_file.cleanup_function_code
  ]
}

# Upload function source code to Storage
resource "google_storage_bucket_object" "session_function_source" {
  name   = "session-manager-${local.name_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.session_function_zip.output_path
  
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_storage_bucket_object" "cleanup_function_source" {
  name   = "session-cleanup-${local.name_suffix}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.cleanup_function_zip.output_path
  
  lifecycle {
    create_before_destroy = true
  }
}

# Session Management Cloud Function
resource "google_cloudfunctions2_function" "session_manager" {
  name        = "${var.function_name_prefix}-${local.name_suffix}"
  location    = var.region
  description = "Session management function with Redis and Firebase Auth integration"
  
  labels = local.common_labels
  
  build_config {
    runtime     = "nodejs20"
    entry_point = "sessionManager"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.session_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 100
    min_instance_count    = 0
    available_memory      = var.function_memory
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.function_sa.email
    
    environment_variables = {
      SECRET_NAME = google_secret_manager_secret.redis_connection.id
      PROJECT_ID  = var.project_id
    }
    
    ingress_settings                 = "ALLOW_ALL"
    all_traffic_on_latest_revision   = true
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_secret_manager_secret_version.redis_connection
  ]
}

# Session Cleanup Cloud Function
resource "google_cloudfunctions2_function" "session_cleanup" {
  name        = "session-cleanup-${local.name_suffix}"
  location    = var.region
  description = "Automated session cleanup function for Redis maintenance"
  
  labels = local.common_labels
  
  build_config {
    runtime     = "nodejs20"
    entry_point = "sessionCleanup"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.cleanup_function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count    = 1
    min_instance_count    = 0
    available_memory      = "256M"
    timeout_seconds       = 300
    service_account_email = google_service_account.function_sa.email
    
    environment_variables = {
      SECRET_NAME       = google_secret_manager_secret.redis_connection.id
      PROJECT_ID        = var.project_id
      SESSION_TTL_HOURS = tostring(var.session_ttl_hours)
    }
    
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_secret_manager_secret_version.redis_connection
  ]
}

# Cloud Scheduler job for automated cleanup
resource "google_cloud_scheduler_job" "session_cleanup" {
  name        = "session-cleanup-${local.name_suffix}"
  region      = var.region
  description = "Automated session cleanup every 6 hours"
  schedule    = var.cleanup_schedule
  time_zone   = "UTC"
  
  http_target {
    uri         = google_cloudfunctions2_function.session_cleanup.service_config[0].uri
    http_method = "POST"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      trigger = "scheduled"
    }))
    
    oidc_token {
      service_account_email = google_service_account.function_sa.email
      audience             = google_cloudfunctions2_function.session_cleanup.service_config[0].uri
    }
  }
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Run invoker permission for scheduler
resource "google_cloud_run_service_iam_member" "cleanup_invoker" {
  project  = var.project_id
  location = var.region
  service  = google_cloudfunctions2_function.session_cleanup.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.function_sa.email}"
}

# Log sink for session analytics (optional)
resource "google_logging_project_sink" "session_analytics" {
  name        = "session-analytics-${local.name_suffix}"
  description = "Session management analytics log sink"
  
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/session_analytics"
  
  filter = "resource.type=\"cloud_function\" AND (resource.labels.function_name=\"${google_cloudfunctions2_function.session_manager.name}\" OR resource.labels.function_name=\"${google_cloudfunctions2_function.session_cleanup.name}\")"
  
  unique_writer_identity = true
  
  depends_on = [google_project_service.required_apis]
}

# Monitoring alert policy for Redis memory usage
resource "google_monitoring_alert_policy" "redis_memory_alert" {
  display_name = "Redis Memory Usage High - ${local.name_suffix}"
  
  conditions {
    display_name = "Redis memory usage above 80%"
    
    condition_threshold {
      filter          = "resource.type=\"redis_instance\" AND resource.labels.instance_id=\"${google_redis_instance.session_store.name}\""
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.8
      duration        = "300s"
      
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
    content = "Redis instance memory usage is above 80%. Consider scaling up or implementing additional cleanup policies."
  }
  
  depends_on = [google_project_service.required_apis]
}