# Output values for session management infrastructure
# These outputs provide essential information for integration and monitoring

output "redis_instance_name" {
  description = "Name of the Cloud Memorystore Redis instance"
  value       = google_redis_instance.session_store.name
}

output "redis_host" {
  description = "Host address of the Redis instance"
  value       = google_redis_instance.session_store.host
}

output "redis_port" {
  description = "Port number of the Redis instance"
  value       = google_redis_instance.session_store.port
}

output "redis_connection_string" {
  description = "Redis connection string for applications"
  value       = "redis://${google_redis_instance.session_store.host}:${google_redis_instance.session_store.port}"
  sensitive   = false
}

output "redis_auth_string" {
  description = "Redis authentication string"
  value       = google_redis_instance.session_store.auth_string
  sensitive   = true
}

output "redis_region" {
  description = "Region where Redis instance is deployed"
  value       = google_redis_instance.session_store.region
}

output "redis_memory_size_gb" {
  description = "Memory size of the Redis instance in GB"
  value       = google_redis_instance.session_store.memory_size_gb
}

output "redis_tier" {
  description = "Service tier of the Redis instance"
  value       = google_redis_instance.session_store.tier
}

output "session_manager_function_name" {
  description = "Name of the session manager Cloud Function"
  value       = google_cloudfunctions2_function.session_manager.name
}

output "session_manager_function_url" {
  description = "URL of the session manager Cloud Function"
  value       = google_cloudfunctions2_function.session_manager.service_config[0].uri
}

output "session_cleanup_function_name" {
  description = "Name of the session cleanup Cloud Function"
  value       = google_cloudfunctions2_function.session_cleanup.name
}

output "session_cleanup_function_url" {
  description = "URL of the session cleanup Cloud Function"
  value       = google_cloudfunctions2_function.session_cleanup.service_config[0].uri
}

output "secret_manager_secret_name" {
  description = "Name of the Secret Manager secret containing Redis connection details"
  value       = google_secret_manager_secret.redis_connection.secret_id
}

output "secret_manager_secret_id" {
  description = "Full ID of the Secret Manager secret"
  value       = google_secret_manager_secret.redis_connection.id
}

output "function_service_account_email" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.email
}

output "function_source_bucket" {
  description = "Name of the Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "scheduler_job_name" {
  description = "Name of the Cloud Scheduler job for session cleanup"
  value       = google_cloud_scheduler_job.session_cleanup.name
}

output "monitoring_alert_policy_name" {
  description = "Name of the monitoring alert policy for Redis memory usage"
  value       = google_monitoring_alert_policy.redis_memory_alert.display_name
}

output "project_id" {
  description = "Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone"
  value       = var.zone
}

# Session management configuration outputs
output "session_configuration" {
  description = "Complete session management configuration for application integration"
  value = {
    redis = {
      host     = google_redis_instance.session_store.host
      port     = google_redis_instance.session_store.port
      instance = google_redis_instance.session_store.name
    }
    functions = {
      session_manager = {
        name = google_cloudfunctions2_function.session_manager.name
        url  = google_cloudfunctions2_function.session_manager.service_config[0].uri
      }
      session_cleanup = {
        name = google_cloudfunctions2_function.session_cleanup.name
        url  = google_cloudfunctions2_function.session_cleanup.service_config[0].uri
      }
    }
    security = {
      secret_name        = google_secret_manager_secret.redis_connection.secret_id
      service_account    = google_service_account.function_sa.email
    }
    automation = {
      cleanup_schedule   = var.cleanup_schedule
      session_ttl_hours  = var.session_ttl_hours
      scheduler_job      = google_cloud_scheduler_job.session_cleanup.name
    }
  }
  sensitive = false
}

# Integration endpoints for client applications
output "api_endpoints" {
  description = "API endpoints for client application integration"
  value = {
    session_create   = "${google_cloudfunctions2_function.session_manager.service_config[0].uri}"
    session_validate = "${google_cloudfunctions2_function.session_manager.service_config[0].uri}"
    session_destroy  = "${google_cloudfunctions2_function.session_manager.service_config[0].uri}"
  }
}

# Monitoring and logging information
output "monitoring_resources" {
  description = "Monitoring and logging resource information"
  value = {
    alert_policy        = google_monitoring_alert_policy.redis_memory_alert.name
    log_sink           = google_logging_project_sink.session_analytics.name
    log_destination    = google_logging_project_sink.session_analytics.destination
  }
}

# Cost optimization information
output "cost_optimization" {
  description = "Information for cost optimization and resource management"
  value = {
    redis_memory_gb     = google_redis_instance.session_store.memory_size_gb
    redis_tier         = google_redis_instance.session_store.tier
    cleanup_frequency  = var.cleanup_schedule
    deletion_protection = var.deletion_protection
  }
}

# Security and compliance information
output "security_information" {
  description = "Security and compliance configuration details"
  value = {
    redis_auth_enabled       = google_redis_instance.session_store.auth_enabled
    redis_encryption_transit = google_redis_instance.session_store.transit_encryption_mode
    secret_manager_enabled   = true
    service_account_principle = google_service_account.function_sa.email
    iam_roles = [
      "roles/secretmanager.secretAccessor",
      "roles/logging.logWriter", 
      "roles/monitoring.metricWriter"
    ]
  }
  sensitive = false
}