# Outputs for User Lifecycle Management with Firebase Authentication and Cloud Tasks
# These outputs provide essential information about the deployed infrastructure

# ============================================================================
# PROJECT AND BASIC CONFIGURATION OUTPUTS
# ============================================================================

output "project_id" {
  description = "The Google Cloud project ID where resources were deployed"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "deployment_timestamp" {
  description = "Timestamp of when the infrastructure was deployed"
  value       = timestamp()
}

# ============================================================================
# FIREBASE AUTHENTICATION OUTPUTS
# ============================================================================

output "firebase_project_number" {
  description = "The Firebase project number for integration"
  value       = google_firebase_project.default.project_number
}

output "firebase_hosting_site_id" {
  description = "The Firebase Hosting site ID for the lifecycle dashboard"
  value       = google_firebase_hosting_site.lifecycle_dashboard.site_id
}

output "firebase_hosting_default_url" {
  description = "The default URL for the Firebase Hosting site"
  value       = "https://${google_firebase_hosting_site.lifecycle_dashboard.site_id}.web.app"
}

output "firestore_database_name" {
  description = "The name of the Firestore database for user data"
  value       = google_firestore_database.default.name
}

# ============================================================================
# CLOUD SQL DATABASE OUTPUTS
# ============================================================================

output "database_instance_name" {
  description = "The name of the Cloud SQL instance for user analytics"
  value       = google_sql_database_instance.user_analytics.name
}

output "database_instance_connection_name" {
  description = "The connection name for the Cloud SQL instance"
  value       = google_sql_database_instance.user_analytics.connection_name
}

output "database_instance_ip_address" {
  description = "The IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.user_analytics.ip_address[0].ip_address
  sensitive   = true
}

output "database_instance_self_link" {
  description = "The self-link of the Cloud SQL instance"
  value       = google_sql_database_instance.user_analytics.self_link
}

output "database_name" {
  description = "The name of the user analytics database"
  value       = google_sql_database.user_analytics.name
}

output "database_username" {
  description = "The username for database access"
  value       = google_sql_user.app_user.name
}

output "database_password_secret_name" {
  description = "The name of the Secret Manager secret containing the database password"
  value       = google_secret_manager_secret.db_password.secret_id
}

# ============================================================================
# CLOUD RUN WORKER SERVICE OUTPUTS
# ============================================================================

output "worker_service_name" {
  description = "The name of the Cloud Run worker service"
  value       = google_cloud_run_v2_service.worker.name
}

output "worker_service_url" {
  description = "The URL of the Cloud Run worker service"
  value       = google_cloud_run_v2_service.worker.uri
}

output "worker_service_location" {
  description = "The location of the Cloud Run worker service"
  value       = google_cloud_run_v2_service.worker.location
}

output "worker_service_latest_ready_revision" {
  description = "The latest ready revision of the worker service"
  value       = google_cloud_run_v2_service.worker.latest_ready_revision
}

output "worker_service_account_email" {
  description = "The email of the service account used by the worker service"
  value       = google_service_account.worker_service_account.email
}

# ============================================================================
# CLOUD TASKS QUEUE OUTPUTS
# ============================================================================

output "task_queue_name" {
  description = "The name of the Cloud Tasks queue for user lifecycle processing"
  value       = google_cloud_tasks_queue.user_lifecycle_queue.name
}

output "task_queue_id" {
  description = "The full resource ID of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.user_lifecycle_queue.id
}

output "task_queue_location" {
  description = "The location of the Cloud Tasks queue"
  value       = google_cloud_tasks_queue.user_lifecycle_queue.location
}

# ============================================================================
# CLOUD SCHEDULER JOBS OUTPUTS
# ============================================================================

output "scheduler_jobs" {
  description = "Information about the Cloud Scheduler jobs for automation"
  value = {
    daily_engagement_analysis = {
      name     = google_cloud_scheduler_job.daily_engagement_analysis.name
      schedule = google_cloud_scheduler_job.daily_engagement_analysis.schedule
      uri      = google_cloud_scheduler_job.daily_engagement_analysis.http_target[0].uri
    }
    weekly_retention_check = {
      name     = google_cloud_scheduler_job.weekly_retention_check.name
      schedule = google_cloud_scheduler_job.weekly_retention_check.schedule
      uri      = google_cloud_scheduler_job.weekly_retention_check.http_target[0].uri
    }
    monthly_lifecycle_review = {
      name     = google_cloud_scheduler_job.monthly_lifecycle_review.name
      schedule = google_cloud_scheduler_job.monthly_lifecycle_review.schedule
      uri      = google_cloud_scheduler_job.monthly_lifecycle_review.http_target[0].uri
    }
  }
}

# ============================================================================
# MONITORING AND LOGGING OUTPUTS
# ============================================================================

output "log_sink_name" {
  description = "The name of the log sink for user lifecycle events"
  value       = var.enable_detailed_monitoring ? google_logging_project_sink.user_lifecycle_logs[0].name : null
}

output "logs_storage_bucket" {
  description = "The storage bucket for log retention"
  value       = var.enable_detailed_monitoring ? google_storage_bucket.logs[0].name : null
}

# ============================================================================
# STORAGE OUTPUTS
# ============================================================================

output "worker_source_bucket" {
  description = "The storage bucket containing the worker application source code"
  value       = google_storage_bucket.worker_source.name
}

# ============================================================================
# SECURITY AND COMPLIANCE OUTPUTS
# ============================================================================

output "service_account_details" {
  description = "Details about the worker service account"
  value = {
    account_id    = google_service_account.worker_service_account.account_id
    email         = google_service_account.worker_service_account.email
    display_name  = google_service_account.worker_service_account.display_name
    unique_id     = google_service_account.worker_service_account.unique_id
  }
}

output "iam_roles_granted" {
  description = "IAM roles granted to the worker service account"
  value = [
    "roles/cloudsql.client",
    "roles/cloudtasks.enqueuer",
    "roles/firebase.admin",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/secretmanager.secretAccessor"
  ]
}

# ============================================================================
# CONFIGURATION GUIDANCE OUTPUTS
# ============================================================================

output "next_steps" {
  description = "Next steps for completing the user lifecycle management setup"
  value = {
    1 = "Configure Firebase Authentication providers in the Firebase Console"
    2 = "Set up client applications to use Firebase Auth with project ID: ${var.project_id}"
    3 = "Deploy the worker application container to Cloud Run using the provided source bucket"
    4 = "Initialize the database schema using the Cloud SQL connection: ${google_sql_database_instance.user_analytics.connection_name}"
    5 = "Test the system by triggering user authentication events"
    6 = "Monitor performance using Cloud Monitoring and the worker service logs"
  }
}

output "database_connection_info" {
  description = "Database connection information for application configuration"
  value = {
    connection_name  = google_sql_database_instance.user_analytics.connection_name
    database_name    = google_sql_database.user_analytics.name
    username         = google_sql_user.app_user.name
    password_secret  = google_secret_manager_secret.db_password.secret_id
    ssl_required     = true
  }
  sensitive = true
}

output "worker_endpoints" {
  description = "Available endpoints on the worker service for task processing"
  value = {
    health_check          = "${google_cloud_run_v2_service.worker.uri}/health"
    process_engagement    = "${google_cloud_run_v2_service.worker.uri}/tasks/process-engagement"
    retention_campaign    = "${google_cloud_run_v2_service.worker.uri}/tasks/retention-campaign"
  }
}

# ============================================================================
# COST OPTIMIZATION OUTPUTS
# ============================================================================

output "cost_optimization_notes" {
  description = "Notes about cost optimization for the deployed resources"
  value = {
    cloud_sql    = "Using ${var.db_instance_tier} tier - consider upgrading for production workloads"
    cloud_run    = "Configured with min 0 instances for cost efficiency - may have cold start delays"
    cloud_tasks  = "Limited to ${var.task_max_dispatches_per_second} dispatches/second - adjust as needed"
    storage      = "Lifecycle policies enabled for automated cleanup of old logs and source files"
    monitoring   = var.enable_detailed_monitoring ? "Detailed monitoring enabled - generates additional costs" : "Basic monitoring only"
  }
}

# ============================================================================
# TROUBLESHOOTING OUTPUTS
# ============================================================================

output "troubleshooting_info" {
  description = "Useful information for troubleshooting deployment issues"
  value = {
    enabled_apis = [
      "firebase.googleapis.com",
      "sqladmin.googleapis.com", 
      "cloudtasks.googleapis.com",
      "cloudscheduler.googleapis.com",
      "run.googleapis.com",
      "cloudbuild.googleapis.com",
      "appengine.googleapis.com",
      "secretmanager.googleapis.com"
    ]
    app_engine_location = google_app_engine_application.app.location_id
    worker_service_sa   = google_service_account.worker_service_account.email
    random_suffix       = random_id.suffix.hex
  }
}