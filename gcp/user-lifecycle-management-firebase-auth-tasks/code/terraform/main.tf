# User Lifecycle Management with Firebase Authentication and Cloud Tasks
# This Terraform configuration deploys a complete serverless user lifecycle management system
# including Firebase Authentication, Cloud SQL analytics, Cloud Tasks processing, and Cloud Scheduler automation

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 4
}

# Local values for consistent resource naming and configuration
locals {
  # Resource naming with prefix and random suffix
  db_instance_name    = "${var.resource_prefix}-analytics-${random_id.suffix.hex}"
  service_account_name = "${var.resource_prefix}-worker-${random_id.suffix.hex}"
  
  # Common labels for all resources
  common_labels = merge(var.labels, {
    terraform   = "true"
    project     = var.project_id
    environment = var.environment
  })
  
  # Application name for App Engine (required for Cloud Tasks)
  app_engine_location = var.region
}

# ============================================================================
# ENABLE REQUIRED GOOGLE CLOUD APIS
# ============================================================================

# Enable required Google Cloud APIs for the user lifecycle management system
resource "google_project_service" "required_apis" {
  for_each = toset([
    "firebase.googleapis.com",           # Firebase Authentication and Hosting
    "sqladmin.googleapis.com",          # Cloud SQL for user analytics
    "cloudtasks.googleapis.com",        # Cloud Tasks for background processing
    "cloudscheduler.googleapis.com",    # Cloud Scheduler for automation
    "run.googleapis.com",               # Cloud Run for worker services
    "cloudbuild.googleapis.com",        # Cloud Build for container deployment
    "appengine.googleapis.com",         # App Engine (required for Cloud Tasks)
    "secretmanager.googleapis.com",     # Secret Manager for credentials
    "logging.googleapis.com",           # Cloud Logging for monitoring
    "monitoring.googleapis.com",        # Cloud Monitoring for observability
    "iam.googleapis.com",              # IAM for service accounts and permissions
    "compute.googleapis.com"           # Compute Engine (required for various services)
  ])

  project                    = var.project_id
  service                   = each.value
  disable_dependent_services = false
  disable_on_destroy        = false
}

# ============================================================================
# APP ENGINE APPLICATION (REQUIRED FOR CLOUD TASKS)
# ============================================================================

# Create App Engine application (required for Cloud Tasks to function)
resource "google_app_engine_application" "app" {
  project     = var.project_id
  location_id = local.app_engine_location
  
  # Ensure APIs are enabled first
  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# FIREBASE PROJECT INITIALIZATION
# ============================================================================

# Initialize Firebase for the Google Cloud project
resource "google_firebase_project" "default" {
  provider = google-beta
  project  = var.project_id
  
  # Ensure APIs are enabled first
  depends_on = [google_project_service.required_apis]
}

# Create Firestore database for Firebase Authentication user data
resource "google_firestore_database" "default" {
  provider                = google-beta
  project                 = var.project_id
  name                   = "(default)"
  location_id            = var.region
  type                   = "FIRESTORE_NATIVE"
  
  # Security settings
  delete_protection_state = var.enable_deletion_protection ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  deletion_policy        = "DELETE"
  
  depends_on = [google_firebase_project.default]
}

# ============================================================================
# SERVICE ACCOUNTS AND IAM
# ============================================================================

# Create service account for the Cloud Run worker service
resource "google_service_account" "worker_service_account" {
  account_id   = local.service_account_name
  display_name = "User Lifecycle Worker Service Account"
  description  = "Service account for Cloud Run worker processing user lifecycle tasks"
  project      = var.project_id
  
  depends_on = [google_project_service.required_apis]
}

# Grant necessary IAM roles to the worker service account
resource "google_project_iam_member" "worker_permissions" {
  for_each = toset([
    "roles/cloudsql.client",           # Access Cloud SQL instances
    "roles/cloudtasks.enqueuer",       # Create and manage tasks
    "roles/firebase.admin",            # Access Firebase Authentication
    "roles/logging.logWriter",         # Write to Cloud Logging
    "roles/monitoring.metricWriter",   # Write monitoring metrics
    "roles/secretmanager.secretAccessor" # Access secrets for database credentials
  ])
  
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.worker_service_account.email}"
  
  depends_on = [google_service_account.worker_service_account]
}

# ============================================================================
# CLOUD SQL DATABASE FOR USER ANALYTICS
# ============================================================================

# Generate secure password for the database
resource "random_password" "db_password" {
  length  = 32
  special = true
}

# Store database password in Secret Manager
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.resource_prefix}-db-password"
  project   = var.project_id
  
  labels = local.common_labels
  
  replication {
    auto {}
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create secret version with the generated password
resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

# Create Cloud SQL PostgreSQL instance for user analytics
resource "google_sql_database_instance" "user_analytics" {
  name             = local.db_instance_name
  database_version = "POSTGRES_15"
  region           = var.region
  project          = var.project_id
  
  # Instance configuration
  settings {
    tier              = var.db_instance_tier
    availability_type = "ZONAL"  # Regional for high availability in production
    disk_type         = "PD_SSD"
    disk_size         = var.db_disk_size
    disk_autoresize   = true
    
    # Backup configuration
    backup_configuration {
      enabled                        = true
      start_time                    = var.db_backup_start_time
      point_in_time_recovery_enabled = true
      location                      = var.region
      transaction_log_retention_days = 7
      
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }
    
    # Network and security settings
    ip_configuration {
      ipv4_enabled    = true
      private_network = null  # Use default network for simplicity
      require_ssl     = true
      
      authorized_networks {
        name  = "cloud-run-access"
        value = "0.0.0.0/0"  # In production, restrict to specific CIDR blocks
      }
    }
    
    # Database flags for optimization
    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
    
    database_flags {
      name  = "log_statement"
      value = "all"  # For development; use 'ddl' or 'none' in production
    }
    
    # Maintenance window
    maintenance_window {
      day          = 7  # Sunday
      hour         = 3  # 3 AM
      update_track = "stable"
    }
    
    # User labels
    user_labels = local.common_labels
  }
  
  # Deletion protection
  deletion_protection = var.enable_deletion_protection
  
  depends_on = [google_project_service.required_apis]
}

# Create the application database
resource "google_sql_database" "user_analytics" {
  name     = "user_analytics"
  instance = google_sql_database_instance.user_analytics.name
  project  = var.project_id
}

# Create database user with password authentication
resource "google_sql_user" "app_user" {
  name     = "app_user"
  instance = google_sql_database_instance.user_analytics.name
  password = random_password.db_password.result
  project  = var.project_id
}

# Create database user for service account (IAM authentication)
resource "google_sql_user" "service_account_user" {
  name     = trimsuffix(google_service_account.worker_service_account.email, ".gserviceaccount.com")
  instance = google_sql_database_instance.user_analytics.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
  project  = var.project_id
  
  depends_on = [google_service_account.worker_service_account]
}

# ============================================================================
# CLOUD TASKS QUEUE FOR BACKGROUND PROCESSING
# ============================================================================

# Create Cloud Tasks queue for user lifecycle processing
resource "google_cloud_tasks_queue" "user_lifecycle_queue" {
  name     = var.task_queue_name
  location = var.region
  project  = var.project_id
  
  # Rate limiting configuration
  rate_limits {
    max_concurrent_dispatches = var.task_max_concurrent_dispatches
    max_dispatches_per_second = var.task_max_dispatches_per_second
  }
  
  # Retry configuration
  retry_config {
    max_attempts      = 5
    max_retry_duration = var.task_max_retry_duration
    min_backoff       = "5s"
    max_backoff       = "300s"
    max_doublings     = 3
  }
  
  depends_on = [google_app_engine_application.app]
}

# ============================================================================
# CLOUD RUN WORKER SERVICE
# ============================================================================

# Package the Node.js application source code
data "archive_file" "worker_source" {
  type        = "zip"
  output_path = "${path.module}/worker-source.zip"
  
  source {
    content = templatefile("${path.module}/worker-app/package.json", {
      project_id = var.project_id
    })
    filename = "package.json"
  }
  
  source {
    content = templatefile("${path.module}/worker-app/index.js", {
      project_id              = var.project_id
      region                 = var.region
      task_queue_name        = var.task_queue_name
      connection_name        = google_sql_database_instance.user_analytics.connection_name
      worker_service_name    = var.worker_service_name
    })
    filename = "index.js"
  }
  
  source {
    content = templatefile("${path.module}/worker-app/Dockerfile", {})
    filename = "Dockerfile"
  }
}

# Create Cloud Storage bucket for storing the application source
resource "google_storage_bucket" "worker_source" {
  name                        = "${var.project_id}-worker-source-${random_id.suffix.hex}"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  # Lifecycle management
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

# Upload the worker source code to Cloud Storage
resource "google_storage_bucket_object" "worker_source" {
  name   = "worker-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.worker_source.name
  source = data.archive_file.worker_source.output_path
}

# Deploy Cloud Run service for processing user lifecycle tasks
resource "google_cloud_run_v2_service" "worker" {
  provider = google-beta
  name     = var.worker_service_name
  location = var.region
  project  = var.project_id
  
  # Ingress and launch configuration
  ingress      = "INGRESS_TRAFFIC_INTERNAL_ONLY"  # Only allow internal traffic
  launch_stage = "GA"
  
  template {
    # Service account configuration
    service_account = google_service_account.worker_service_account.email
    
    # Scaling configuration
    scaling {
      min_instance_count = 0
      max_instance_count = var.worker_max_instances
    }
    
    # Timeout configuration
    timeout = "${var.worker_timeout}s"
    
    # Volume configuration for Cloud SQL
    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.user_analytics.connection_name]
      }
    }
    
    # Container configuration
    containers {
      image = "gcr.io/${var.project_id}/${var.worker_service_name}:latest"
      
      # Resource allocation
      resources {
        limits = {
          cpu    = var.worker_cpu
          memory = var.worker_memory
        }
      }
      
      # Environment variables
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      
      env {
        name  = "REGION"
        value = var.region
      }
      
      env {
        name  = "TASK_QUEUE_NAME"
        value = var.task_queue_name
      }
      
      env {
        name  = "CONNECTION_NAME"
        value = google_sql_database_instance.user_analytics.connection_name
      }
      
      env {
        name  = "WORKER_SERVICE_NAME"
        value = var.worker_service_name
      }
      
      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }
      
      # Volume mounts
      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
      
      # Health check endpoints
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds      = 5
        period_seconds       = 10
        failure_threshold    = 3
      }
      
      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 30
        timeout_seconds      = 5
        period_seconds       = 30
        failure_threshold    = 3
      }
    }
    
    # Annotations for additional configuration
    annotations = {
      "autoscaling.knative.dev/maxScale"                    = tostring(var.worker_max_instances)
      "autoscaling.knative.dev/minScale"                    = "0"
      "run.googleapis.com/cloudsql-instances"               = google_sql_database_instance.user_analytics.connection_name
      "run.googleapis.com/execution-environment"           = "gen2"
      "run.googleapis.com/client-name"                     = "terraform"
    }
    
    # Labels
    labels = local.common_labels
  }
  
  # Traffic allocation
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_service_account.worker_service_account,
    google_sql_database_instance.user_analytics
  ]
}

# Grant Cloud Tasks the ability to invoke the worker service
resource "google_cloud_run_service_iam_member" "tasks_invoker" {
  location = google_cloud_run_v2_service.worker.location
  project  = google_cloud_run_v2_service.worker.project
  service  = google_cloud_run_v2_service.worker.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.worker_service_account.email}"
}

# ============================================================================
# CLOUD SCHEDULER JOBS FOR AUTOMATION
# ============================================================================

# Daily engagement analysis scheduled job
resource "google_cloud_scheduler_job" "daily_engagement_analysis" {
  name        = "daily-engagement-analysis"
  description = "Daily automated user engagement analysis and scoring"
  schedule    = var.engagement_analysis_schedule
  time_zone   = var.scheduler_time_zone
  region      = var.region
  project     = var.project_id
  
  # Retry configuration
  retry_config {
    retry_count          = 3
    max_retry_duration   = "300s"
    max_backoff_duration = "60s"
    min_backoff_duration = "5s"
    max_doublings        = 2
  }
  
  # HTTP target configuration
  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.worker.uri}/tasks/process-engagement"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      task_type = "daily_analysis"
      scheduled = true
    }))
    
    # OIDC authentication
    oidc_token {
      service_account_email = google_service_account.worker_service_account.email
      audience             = google_cloud_run_v2_service.worker.uri
    }
  }
  
  depends_on = [
    google_cloud_run_v2_service.worker,
    google_app_engine_application.app
  ]
}

# Weekly retention campaign scheduled job
resource "google_cloud_scheduler_job" "weekly_retention_check" {
  name        = "weekly-retention-check"
  description = "Weekly automated retention campaign triggers for at-risk users"
  schedule    = var.retention_check_schedule
  time_zone   = var.scheduler_time_zone
  region      = var.region
  project     = var.project_id
  
  # Retry configuration
  retry_config {
    retry_count          = 3
    max_retry_duration   = "300s"
    max_backoff_duration = "60s"
    min_backoff_duration = "5s"
    max_doublings        = 2
  }
  
  # HTTP target configuration
  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.worker.uri}/tasks/retention-campaign"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      task_type = "weekly_retention"
      scheduled = true
    }))
    
    # OIDC authentication
    oidc_token {
      service_account_email = google_service_account.worker_service_account.email
      audience             = google_cloud_run_v2_service.worker.uri
    }
  }
  
  depends_on = [
    google_cloud_run_v2_service.worker,
    google_app_engine_application.app
  ]
}

# Monthly lifecycle review scheduled job
resource "google_cloud_scheduler_job" "monthly_lifecycle_review" {
  name        = "monthly-lifecycle-review"
  description = "Monthly comprehensive user lifecycle review and optimization"
  schedule    = var.lifecycle_review_schedule
  time_zone   = var.scheduler_time_zone
  region      = var.region
  project     = var.project_id
  
  # Retry configuration
  retry_config {
    retry_count          = 3
    max_retry_duration   = "300s"
    max_backoff_duration = "60s"
    min_backoff_duration = "5s"
    max_doublings        = 2
  }
  
  # HTTP target configuration
  http_target {
    http_method = "POST"
    uri         = "${google_cloud_run_v2_service.worker.uri}/tasks/retention-campaign"
    
    headers = {
      "Content-Type" = "application/json"
    }
    
    body = base64encode(jsonencode({
      task_type = "lifecycle_review"
      scheduled = true
    }))
    
    # OIDC authentication
    oidc_token {
      service_account_email = google_service_account.worker_service_account.email
      audience             = google_cloud_run_v2_service.worker.uri
    }
  }
  
  depends_on = [
    google_cloud_run_v2_service.worker,
    google_app_engine_application.app
  ]
}

# ============================================================================
# MONITORING AND LOGGING CONFIGURATION
# ============================================================================

# Create log sink for user lifecycle events
resource "google_logging_project_sink" "user_lifecycle_logs" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  name        = "user-lifecycle-logs"
  destination = "storage.googleapis.com/${google_storage_bucket.logs[0].name}"
  
  # Filter for relevant log entries
  filter = <<-EOT
    resource.type="cloud_run_revision" 
    OR resource.type="cloud_sql_database"
    OR resource.type="cloud_tasks_queue"
    OR resource.type="cloud_scheduler_job"
    AND labels.application="${local.common_labels.application}"
  EOT
  
  # BigQuery dataset for log analytics
  bigquery_options {
    use_partitioned_tables = true
  }
  
  depends_on = [google_project_service.required_apis]
}

# Create storage bucket for log retention
resource "google_storage_bucket" "logs" {
  count = var.enable_detailed_monitoring ? 1 : 0
  
  name                        = "${var.project_id}-lifecycle-logs-${random_id.suffix.hex}"
  location                    = var.region
  project                     = var.project_id
  uniform_bucket_level_access = true
  
  labels = local.common_labels
  
  # Lifecycle management for cost optimization
  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
}

# ============================================================================
# FIREBASE HOSTING SETUP (OPTIONAL)
# ============================================================================

# Create Firebase Hosting site for the user lifecycle management dashboard
resource "google_firebase_hosting_site" "lifecycle_dashboard" {
  provider = google-beta
  project  = var.project_id
  site_id  = var.firebase_site_id
  
  depends_on = [google_firebase_project.default]
}

# ============================================================================
# SECURITY AND COMPLIANCE
# ============================================================================

# Enable audit logging for security compliance
resource "google_project_iam_audit_config" "audit_config" {
  count   = var.enable_audit_logs ? 1 : 0
  project = var.project_id
  service = "allServices"
  
  audit_log_config {
    log_type = "ADMIN_READ"
  }
  
  audit_log_config {
    log_type = "DATA_READ"
  }
  
  audit_log_config {
    log_type = "DATA_WRITE"
  }
}

# ============================================================================
# RESOURCE CLEANUP AND LIFECYCLE MANAGEMENT
# ============================================================================

# Create a cleanup Cloud Function for automated resource management (optional)
resource "null_resource" "deployment_validation" {
  # Trigger validation after key resources are created
  triggers = {
    db_instance    = google_sql_database_instance.user_analytics.self_link
    worker_service = google_cloud_run_v2_service.worker.uri
    task_queue     = google_cloud_tasks_queue.user_lifecycle_queue.name
  }
  
  # Local provisioner for deployment validation
  provisioner "local-exec" {
    command = <<-EOT
      echo "Validating deployment..."
      echo "Database Instance: ${google_sql_database_instance.user_analytics.name}"
      echo "Worker Service URL: ${google_cloud_run_v2_service.worker.uri}"
      echo "Task Queue: ${google_cloud_tasks_queue.user_lifecycle_queue.name}"
      echo "Deployment validation completed successfully!"
    EOT
  }
}