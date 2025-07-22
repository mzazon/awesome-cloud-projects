# =============================================================================
# OUTPUTS - Database Maintenance Automation with Cloud SQL and Cloud Scheduler
# =============================================================================
# This file defines all output values that provide important information
# about the deployed infrastructure. These outputs can be used for
# integration with other systems or for verification purposes.
# =============================================================================

# =============================================================================
# PROJECT INFORMATION
# =============================================================================

output "project_id" {
  description = "The Google Cloud Project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The Google Cloud region where resources were deployed"
  value       = var.region
}

output "zone" {
  description = "The Google Cloud zone where zonal resources were deployed"
  value       = var.zone
}

output "environment" {
  description = "Environment name used for resource labeling"
  value       = var.environment
}

# =============================================================================
# CLOUD SQL DATABASE OUTPUTS
# =============================================================================

output "sql_instance_name" {
  description = "Name of the Cloud SQL instance"
  value       = google_sql_database_instance.maintenance_db.name
}

output "sql_instance_connection_name" {
  description = "Connection name for the Cloud SQL instance (project:region:instance)"
  value       = google_sql_database_instance.maintenance_db.connection_name
}

output "sql_instance_public_ip" {
  description = "Public IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.maintenance_db.public_ip_address
  sensitive   = true
}

output "sql_instance_private_ip" {
  description = "Private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.maintenance_db.private_ip_address
  sensitive   = true
}

output "sql_instance_self_link" {
  description = "Self-link of the Cloud SQL instance"
  value       = google_sql_database_instance.maintenance_db.self_link
}

output "database_name" {
  description = "Name of the application database"
  value       = google_sql_database.app_database.name
}

output "database_user" {
  description = "Name of the maintenance database user"
  value       = google_sql_user.maintenance_user.name
}

output "database_version" {
  description = "Database version of the Cloud SQL instance"
  value       = google_sql_database_instance.maintenance_db.database_version
}

output "database_tier" {
  description = "Machine tier of the Cloud SQL instance"
  value       = google_sql_database_instance.maintenance_db.settings[0].tier
}

# =============================================================================
# CLOUD FUNCTION OUTPUTS
# =============================================================================

output "function_name" {
  description = "Name of the database maintenance Cloud Function"
  value       = google_cloudfunctions_function.maintenance_function.name
}

output "function_url" {
  description = "HTTPS trigger URL for the maintenance function"
  value       = google_cloudfunctions_function.maintenance_function.https_trigger_url
  sensitive   = true
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

output "function_runtime" {
  description = "Runtime environment of the Cloud Function"
  value       = google_cloudfunctions_function.maintenance_function.runtime
}

output "function_memory" {
  description = "Memory allocation for the Cloud Function in MB"
  value       = google_cloudfunctions_function.maintenance_function.available_memory_mb
}

output "function_timeout" {
  description = "Timeout setting for the Cloud Function in seconds"
  value       = google_cloudfunctions_function.maintenance_function.timeout
}

# =============================================================================
# CLOUD SCHEDULER OUTPUTS
# =============================================================================

output "scheduler_job_name" {
  description = "Name of the main maintenance scheduler job"
  value       = google_cloud_scheduler_job.daily_maintenance.name
}

output "scheduler_job_schedule" {
  description = "Cron schedule for the main maintenance job"
  value       = google_cloud_scheduler_job.daily_maintenance.schedule
}

output "scheduler_monitoring_job_name" {
  description = "Name of the performance monitoring scheduler job"
  value       = var.enable_performance_monitoring ? google_cloud_scheduler_job.performance_monitoring[0].name : null
}

output "scheduler_monitoring_schedule" {
  description = "Cron schedule for the performance monitoring job"
  value       = var.enable_performance_monitoring ? google_cloud_scheduler_job.performance_monitoring[0].schedule : null
}

output "scheduler_service_account_email" {
  description = "Email of the service account used by Cloud Scheduler"
  value       = google_service_account.scheduler_sa.email
}

output "scheduler_timezone" {
  description = "Timezone used for scheduler jobs"
  value       = google_cloud_scheduler_job.daily_maintenance.time_zone
}

# =============================================================================
# CLOUD STORAGE OUTPUTS
# =============================================================================

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for maintenance logs"
  value       = google_storage_bucket.maintenance_logs.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.maintenance_logs.url
}

output "storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.maintenance_logs.location
}

output "storage_bucket_storage_class" {
  description = "Storage class of the Cloud Storage bucket"
  value       = google_storage_bucket.maintenance_logs.storage_class
}

# =============================================================================
# MONITORING OUTPUTS
# =============================================================================

output "monitoring_dashboard_url" {
  description = "URL to access the Cloud Monitoring dashboard"
  value       = var.enable_monitoring_dashboard ? "https://console.cloud.google.com/monitoring/dashboards/custom/${basename(google_monitoring_dashboard.database_maintenance[0].id)}?project=${var.project_id}" : null
}

output "cpu_alert_policy_name" {
  description = "Name of the CPU utilization alert policy"
  value       = var.enable_alerting_policies ? google_monitoring_alert_policy.high_cpu[0].display_name : null
}

output "connection_alert_policy_name" {
  description = "Name of the connection count alert policy"
  value       = var.enable_alerting_policies ? google_monitoring_alert_policy.high_connections[0].display_name : null
}

output "notification_channel_email" {
  description = "Email address configured for monitoring notifications"
  value       = var.alert_email != "" && var.enable_alerting_policies ? var.alert_email : null
  sensitive   = true
}

# =============================================================================
# SECURITY OUTPUTS
# =============================================================================

output "authorized_networks" {
  description = "List of authorized networks for database access"
  value = [
    for network in var.authorized_networks : {
      name  = network.name
      value = network.value
    }
  ]
  sensitive = true
}

output "ssl_required" {
  description = "Whether SSL is required for database connections"
  value       = var.require_ssl
}

output "deletion_protection_enabled" {
  description = "Whether deletion protection is enabled for the database"
  value       = var.enable_deletion_protection
}

# =============================================================================
# OPERATIONAL OUTPUTS
# =============================================================================

output "maintenance_window" {
  description = "Configured maintenance window for the database"
  value = {
    day  = google_sql_database_instance.maintenance_db.settings[0].maintenance_window[0].day
    hour = google_sql_database_instance.maintenance_db.settings[0].maintenance_window[0].hour
  }
}

output "backup_configuration" {
  description = "Backup configuration for the database"
  value = {
    enabled                = google_sql_database_instance.maintenance_db.settings[0].backup_configuration[0].enabled
    start_time            = google_sql_database_instance.maintenance_db.settings[0].backup_configuration[0].start_time
    point_in_time_recovery = google_sql_database_instance.maintenance_db.settings[0].backup_configuration[0].point_in_time_recovery_enabled
    binary_log_enabled    = google_sql_database_instance.maintenance_db.settings[0].backup_configuration[0].binary_log_enabled
    retention_count       = google_sql_database_instance.maintenance_db.settings[0].backup_configuration[0].backup_retention_settings[0].retained_backups
  }
}

output "query_insights_enabled" {
  description = "Whether Query Insights is enabled for performance monitoring"
  value       = google_sql_database_instance.maintenance_db.settings[0].insights_config[0].query_insights_enabled
}

# =============================================================================
# COST AND RESOURCE INFORMATION
# =============================================================================

output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (informational only)"
  value = {
    note                = "Costs are estimates and may vary based on actual usage"
    cloud_sql_instance  = "~$7-15/month for db-f1-micro tier"
    cloud_functions     = "~$0-5/month for maintenance tasks (2 executions/day)"
    cloud_scheduler     = "~$0.10/month for 2 jobs"
    cloud_storage       = "~$0.50/month for 10GB of logs"
    cloud_monitoring    = "~$0-8/month for metrics and alerts"
    total_estimate      = "~$8-28/month depending on usage"
  }
}

output "resource_count" {
  description = "Count of resources created by this configuration"
  value = {
    sql_instances        = 1
    sql_databases       = 1
    sql_users          = 1
    cloud_functions    = 1
    scheduler_jobs     = var.enable_performance_monitoring ? 2 : 1
    storage_buckets    = 1
    service_accounts   = 2
    alert_policies     = var.enable_alerting_policies ? 2 : 0
    dashboards         = var.enable_monitoring_dashboard ? 1 : 0
    notification_channels = var.alert_email != "" && var.enable_alerting_policies ? 1 : 0
  }
}

# =============================================================================
# CONNECTION INFORMATION
# =============================================================================

output "connection_examples" {
  description = "Examples of how to connect to the database"
  value = {
    gcloud_sql_connect = "gcloud sql connect ${google_sql_database_instance.maintenance_db.name} --user=${google_sql_user.maintenance_user.name} --database=${google_sql_database.app_database.name}"
    mysql_client      = "mysql -h ${google_sql_database_instance.maintenance_db.public_ip_address} -u ${google_sql_user.maintenance_user.name} -p ${google_sql_database.app_database.name}"
    connection_string = "mysql://${google_sql_user.maintenance_user.name}:[PASSWORD]@${google_sql_database_instance.maintenance_db.public_ip_address}:3306/${google_sql_database.app_database.name}"
  }
  sensitive = true
}

# =============================================================================
# VERIFICATION COMMANDS
# =============================================================================

output "verification_commands" {
  description = "Commands to verify the deployment"
  value = {
    check_sql_instance = "gcloud sql instances describe ${google_sql_database_instance.maintenance_db.name}"
    check_function     = "gcloud functions describe ${google_cloudfunctions_function.maintenance_function.name} --region=${var.region}"
    check_scheduler    = "gcloud scheduler jobs describe ${google_cloud_scheduler_job.daily_maintenance.name} --location=${var.region}"
    check_bucket       = "gsutil ls -b gs://${google_storage_bucket.maintenance_logs.name}"
    test_function      = "curl -X POST ${google_cloudfunctions_function.maintenance_function.https_trigger_url} -H 'Content-Type: application/json' -d '{\"test\":\"manual_trigger\"}'"
  }
  sensitive = true
}

# =============================================================================
# LOGS AND MONITORING LINKS
# =============================================================================

output "console_links" {
  description = "Direct links to Google Cloud Console for monitoring and management"
  value = {
    sql_instance = "https://console.cloud.google.com/sql/instances/${google_sql_database_instance.maintenance_db.name}/overview?project=${var.project_id}"
    cloud_function = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.maintenance_function.name}?project=${var.project_id}"
    scheduler_jobs = "https://console.cloud.google.com/cloudscheduler?project=${var.project_id}"
    storage_bucket = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.maintenance_logs.name}?project=${var.project_id}"
    monitoring_overview = "https://console.cloud.google.com/monitoring/overview?project=${var.project_id}"
    logs_explorer = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
  }
}