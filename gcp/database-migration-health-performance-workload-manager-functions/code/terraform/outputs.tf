# =============================================================================
# Core Infrastructure Outputs
# =============================================================================

output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "resource_suffix" {
  description = "The random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# =============================================================================
# Cloud Storage Outputs
# =============================================================================

output "monitoring_bucket_name" {
  description = "Name of the Cloud Storage bucket for monitoring data"
  value       = google_storage_bucket.monitoring_bucket.name
}

output "monitoring_bucket_url" {
  description = "URL of the Cloud Storage bucket for monitoring data"
  value       = google_storage_bucket.monitoring_bucket.url
}

# =============================================================================
# Database Outputs
# =============================================================================

output "cloud_sql_instance_name" {
  description = "Name of the Cloud SQL instance"
  value       = google_sql_database_instance.migration_target.name
}

output "cloud_sql_connection_name" {
  description = "Connection name for the Cloud SQL instance"
  value       = google_sql_database_instance.migration_target.connection_name
}

output "cloud_sql_private_ip" {
  description = "Private IP address of the Cloud SQL instance"
  value       = length(google_sql_database_instance.migration_target.private_ip_address) > 0 ? google_sql_database_instance.migration_target.private_ip_address : null
}

output "cloud_sql_public_ip" {
  description = "Public IP address of the Cloud SQL instance"
  value       = length(google_sql_database_instance.migration_target.public_ip_address) > 0 ? google_sql_database_instance.migration_target.public_ip_address : null
}

output "database_name" {
  description = "Name of the application database"
  value       = google_sql_database.application_db.name
}

output "database_self_link" {
  description = "Self link of the application database"
  value       = google_sql_database.application_db.self_link
}

# =============================================================================
# Pub/Sub Outputs
# =============================================================================

output "pubsub_topics" {
  description = "Names of the created Pub/Sub topics"
  value = {
    migration_events      = google_pubsub_topic.migration_events.name
    validation_results    = google_pubsub_topic.validation_results.name
    alert_notifications   = google_pubsub_topic.alert_notifications.name
  }
}

output "pubsub_subscriptions" {
  description = "Names of the created Pub/Sub subscriptions"
  value = {
    migration_monitor_sub     = google_pubsub_subscription.migration_monitor_sub.name
    validation_processor_sub  = google_pubsub_subscription.validation_processor_sub.name
    alert_manager_sub         = google_pubsub_subscription.alert_manager_sub.name
  }
}

# =============================================================================
# Cloud Functions Outputs
# =============================================================================

output "cloud_functions" {
  description = "Information about the deployed Cloud Functions"
  value = {
    migration_monitor = {
      name        = google_cloudfunctions_function.migration_monitor.name
      trigger_url = google_cloudfunctions_function.migration_monitor.https_trigger_url
      status      = google_cloudfunctions_function.migration_monitor.status
    }
    data_validator = {
      name   = google_cloudfunctions_function.data_validator.name
      status = google_cloudfunctions_function.data_validator.status
    }
    alert_manager = {
      name   = google_cloudfunctions_function.alert_manager.name
      status = google_cloudfunctions_function.alert_manager.status
    }
  }
}

output "migration_monitor_url" {
  description = "HTTPS trigger URL for the migration monitor function"
  value       = google_cloudfunctions_function.migration_monitor.https_trigger_url
}

output "function_service_account" {
  description = "Email of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.email
}

# =============================================================================
# Workload Manager Outputs
# =============================================================================

output "workload_manager_evaluation_name" {
  description = "Name of the Cloud Workload Manager evaluation"
  value       = local.workload_name
}

output "workload_manager_command" {
  description = "Command to check the Workload Manager evaluation status"
  value       = "gcloud workload-manager evaluations describe ${local.workload_name} --location=${var.region} --project=${var.project_id}"
}

# =============================================================================
# Monitoring Outputs
# =============================================================================

output "monitoring_dashboard_url" {
  description = "URL to access the custom monitoring dashboard"
  value       = var.enable_monitoring_dashboard ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.migration_dashboard[0].id}?project=${var.project_id}" : null
}

output "alert_policies" {
  description = "Names of the created alert policies"
  value = {
    high_cpu_alert           = google_monitoring_alert_policy.high_cpu_alert.name
    validation_failure_alert = google_monitoring_alert_policy.validation_failure_alert.name
  }
}

# =============================================================================
# Validation and Testing Outputs
# =============================================================================

output "validation_commands" {
  description = "Commands to validate the deployment"
  value = {
    list_functions = "gcloud functions list --filter=\"name~migration\" --project=${var.project_id}"
    test_migration_monitor = "curl -X POST -H \"Content-Type: application/json\" -d '{\"project_id\":\"${var.project_id}\",\"migration_job_id\":\"test-job\",\"location\":\"${var.region}\"}' ${google_cloudfunctions_function.migration_monitor.https_trigger_url}"
    list_pubsub_topics = "gcloud pubsub topics list --project=${var.project_id}"
    check_sql_instance = "gcloud sql instances describe ${google_sql_database_instance.migration_target.name} --project=${var.project_id}"
  }
}

output "cleanup_commands" {
  description = "Commands to clean up resources (for reference)"
  value = {
    delete_functions = "gcloud functions delete migration-monitor data-validator alert-manager --region=${var.region} --project=${var.project_id} --quiet"
    delete_sql_instance = "gcloud sql instances delete ${google_sql_database_instance.migration_target.name} --project=${var.project_id} --quiet"
    delete_pubsub_topics = "gcloud pubsub topics delete migration-events validation-results alert-notifications --project=${var.project_id} --quiet"
    delete_storage_bucket = "gsutil -m rm -r gs://${google_storage_bucket.monitoring_bucket.name}"
  }
}

# =============================================================================
# Configuration Outputs
# =============================================================================

output "environment_variables" {
  description = "Environment variables for manual testing"
  value = {
    PROJECT_ID     = var.project_id
    REGION         = var.region
    ZONE           = var.zone
    BUCKET_NAME    = google_storage_bucket.monitoring_bucket.name
    MIGRATION_NAME = local.migration_name
    WORKLOAD_NAME  = local.workload_name
  }
}

output "sample_migration_job_config" {
  description = "Sample configuration for testing migration monitoring"
  value = {
    project_id        = var.project_id
    migration_job_id  = "test-migration-job"
    location          = var.region
    source_database = {
      host     = "source-db-host"
      user     = "source-user"
      password = "source-password"
      database = "source-db"
      port     = 3306
    }
    target_database = {
      host     = google_sql_database_instance.migration_target.public_ip_address
      user     = "root"
      password = "SecurePassword123!"
      database = google_sql_database.application_db.name
      port     = 3306
    }
    validation_queries = [
      {
        name  = "Row Count Check"
        query = "SELECT COUNT(*) FROM sample_table"
      }
    ]
  }
}

# =============================================================================
# Cost and Resource Information
# =============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost in USD (rough estimate)"
  value = {
    cloud_sql_instance = "~$25-50 (depends on usage)"
    cloud_functions    = "~$5-20 (depends on invocations)"
    cloud_storage      = "~$1-5 (depends on storage size)"
    pubsub            = "~$1-10 (depends on message volume)"
    monitoring        = "~$5-15 (depends on metrics volume)"
    total_estimate    = "~$37-100 per month"
    note              = "Costs depend on actual usage patterns and data volume"
  }
}

output "resource_summary" {
  description = "Summary of created resources"
  value = {
    cloud_sql_instances = 1
    cloud_functions     = 3
    pubsub_topics       = 3
    pubsub_subscriptions = 3
    storage_buckets     = 1
    service_accounts    = 1
    alert_policies      = 2
    monitoring_dashboards = var.enable_monitoring_dashboard ? 1 : 0
    workload_evaluations = 1
  }
}

# =============================================================================
# Security Information
# =============================================================================

output "security_notes" {
  description = "Important security considerations"
  value = {
    database_password = "Default password set - change in production!"
    function_access   = "Migration monitor function allows public access - restrict in production"
    network_access    = "Cloud SQL instance uses public IP - consider private IP for production"
    service_account   = "Functions use dedicated service account with minimal permissions"
  }
}

# =============================================================================
# Next Steps
# =============================================================================

output "next_steps" {
  description = "Recommended next steps after deployment"
  value = [
    "1. Access the monitoring dashboard using the provided URL",
    "2. Test the migration monitor function with the provided curl command",
    "3. Configure actual migration job using Database Migration Service",
    "4. Set up notification channels for alert policies",
    "5. Review and adjust alert thresholds based on your requirements",
    "6. Configure proper authentication and network security for production use"
  ]
}