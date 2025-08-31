# Cloud SQL instance outputs
output "sql_instance_name" {
  description = "Name of the Cloud SQL PostgreSQL instance"
  value       = google_sql_database_instance.postgres_instance.name
}

output "sql_instance_connection_name" {
  description = "Connection name for the Cloud SQL instance"
  value       = google_sql_database_instance.postgres_instance.connection_name
}

output "sql_instance_ip_address" {
  description = "Public IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.postgres_instance.public_ip_address
}

output "sql_instance_private_ip_address" {
  description = "Private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.postgres_instance.private_ip_address
}

output "sql_instance_self_link" {
  description = "Self link of the Cloud SQL instance"
  value       = google_sql_database_instance.postgres_instance.self_link
}

# Database configuration outputs
output "database_name" {
  description = "Name of the performance test database"
  value       = google_sql_database.performance_test_db.name
}

output "postgres_username" {
  description = "Username for the postgres root user"
  value       = google_sql_user.postgres_user.name
}

output "monitor_username" {
  description = "Username for the monitoring user"
  value       = google_sql_user.monitor_user.name
}

# Cloud Function outputs
output "function_name" {
  description = "Name of the Cloud Function for alert processing"
  value       = google_cloudfunctions2_function.alert_processor.name
}

output "function_url" {
  description = "HTTP trigger URL for the Cloud Function"
  value       = google_cloudfunctions2_function.alert_processor.service_config[0].uri
  sensitive   = false
}

output "function_service_account_email" {
  description = "Email of the service account used by the Cloud Function"
  value       = google_service_account.function_sa.email
}

# Monitoring outputs
output "alert_policy_name" {
  description = "Name of the Cloud Monitoring alert policy"
  value       = google_monitoring_alert_policy.slow_query_alert.display_name
}

output "alert_policy_id" {
  description = "ID of the Cloud Monitoring alert policy"
  value       = google_monitoring_alert_policy.slow_query_alert.name
}

output "notification_channel_name" {
  description = "Name of the notification channel"
  value       = google_monitoring_notification_channel.webhook_channel.name
}

output "notification_channel_id" {
  description = "ID of the notification channel"
  value       = google_monitoring_notification_channel.webhook_channel.id
}

# Storage outputs
output "function_source_bucket" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.function_source.url
}

# Logging outputs
output "logging_sink_name" {
  description = "Name of the Cloud Logging sink for alert logs"
  value       = google_logging_project_sink.alert_logs.name
}

output "logging_sink_writer_identity" {
  description = "Writer identity for the logging sink"
  value       = google_logging_project_sink.alert_logs.writer_identity
}

# Connection information for testing
output "query_insights_dashboard_url" {
  description = "URL to access Query Insights dashboard"
  value       = "https://console.cloud.google.com/sql/instances/${google_sql_database_instance.postgres_instance.name}/insights?project=${var.project_id}"
}

output "monitoring_dashboard_url" {
  description = "URL to access Cloud Monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/alerting/policies?project=${var.project_id}"
}

output "function_logs_url" {
  description = "URL to access Cloud Function logs"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions2_function.alert_processor.name}?project=${var.project_id}&tab=logs"
}

# Database connection instructions
output "database_connection_command" {
  description = "Command to connect to the database using gcloud"
  value       = "gcloud sql connect ${google_sql_database_instance.postgres_instance.name} --user=postgres --database=${google_sql_database.performance_test_db.name}"
}

output "psql_connection_string" {
  description = "PostgreSQL connection string for external clients"
  value       = "postgresql://postgres:${var.db_root_password}@${google_sql_database_instance.postgres_instance.public_ip_address}:5432/${google_sql_database.performance_test_db.name}"
  sensitive   = true
}

# Resource summary
output "created_resources_summary" {
  description = "Summary of all created resources"
  value = {
    sql_instance = {
      name           = google_sql_database_instance.postgres_instance.name
      version        = google_sql_database_instance.postgres_instance.database_version
      tier           = google_sql_database_instance.postgres_instance.settings[0].tier
      edition        = google_sql_database_instance.postgres_instance.settings[0].edition
      region         = google_sql_database_instance.postgres_instance.region
      query_insights = google_sql_database_instance.postgres_instance.settings[0].insights_config[0].query_insights_enabled
    }
    cloud_function = {
      name    = google_cloudfunctions2_function.alert_processor.name
      runtime = google_cloudfunctions2_function.alert_processor.build_config[0].runtime
      memory  = google_cloudfunctions2_function.alert_processor.service_config[0].available_memory
      url     = google_cloudfunctions2_function.alert_processor.service_config[0].uri
    }
    monitoring = {
      alert_policy_name        = google_monitoring_alert_policy.slow_query_alert.display_name
      notification_channel_id  = google_monitoring_notification_channel.webhook_channel.id
      query_threshold_seconds  = var.query_threshold_seconds
      auto_close_duration     = var.alert_auto_close_duration
    }
    storage = {
      bucket_name = google_storage_bucket.function_source.name
      bucket_url  = google_storage_bucket.function_source.url
    }
  }
}

# Cost estimation information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD (approximate)"
  value = {
    cloud_sql_instance = "~$25-35 (Enterprise edition with 2 vCPU, 7.5GB RAM)"
    cloud_function     = "~$0.01-1 (depends on invocations and execution time)"
    cloud_monitoring   = "~$0.50-2 (depends on metrics volume)"
    cloud_storage      = "~$0.10-0.50 (function source and logs)"
    total_estimated    = "~$26-39 per month"
    note              = "Costs vary based on usage patterns and data transfer"
  }
}

# Security and best practices
output "security_notes" {
  description = "Important security considerations"
  value = {
    database_access = "Database is configured with public IP for demonstration. Use private IP and VPC peering in production."
    function_auth   = "Cloud Function is publicly accessible for webhook. Consider implementing authentication in production."
    passwords       = "Database passwords are stored in Terraform state. Use Secret Manager in production."
    monitoring      = "Alert policy sends notifications to webhook. Configure additional channels for critical alerts."
    backup          = "Automated backups are enabled with 7-day retention. Adjust retention period based on requirements."
  }
}

# Testing information
output "testing_instructions" {
  description = "Instructions for testing the alerting system"
  value = {
    step_1 = "Connect to database: ${output.database_connection_command.value}"
    step_2 = "Execute slow queries to trigger alerts (see sample_data.sql for examples)"
    step_3 = "Monitor function logs: ${output.function_logs_url.value}"
    step_4 = "Check Query Insights: ${output.query_insights_dashboard_url.value}"
    step_5 = "View alert policies: ${output.monitoring_dashboard_url.value}"
  }
}