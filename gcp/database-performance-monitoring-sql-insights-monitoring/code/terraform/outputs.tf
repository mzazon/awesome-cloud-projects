# Outputs for GCP Database Performance Monitoring Infrastructure
# These outputs provide essential information for connecting to and managing the deployed resources

# Database Connection Information
output "database_instance_name" {
  description = "Name of the Cloud SQL database instance"
  value       = google_sql_database_instance.performance_monitoring_db.name
}

output "database_connection_name" {
  description = "Connection name for the Cloud SQL instance (project:region:instance)"
  value       = google_sql_database_instance.performance_monitoring_db.connection_name
}

output "database_public_ip" {
  description = "Public IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.performance_monitoring_db.public_ip_address
}

output "database_private_ip" {
  description = "Private IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.performance_monitoring_db.private_ip_address
}

output "database_self_link" {
  description = "Self-link URL of the Cloud SQL instance"
  value       = google_sql_database_instance.performance_monitoring_db.self_link
}

# Database Configuration Details
output "database_version" {
  description = "PostgreSQL version of the Cloud SQL instance"
  value       = google_sql_database_instance.performance_monitoring_db.database_version
}

output "database_tier" {
  description = "Machine type/tier of the Cloud SQL instance"
  value       = google_sql_database_instance.performance_monitoring_db.settings[0].tier
}

output "database_edition" {
  description = "Edition of the Cloud SQL instance (Enterprise Plus for Query Insights)"
  value       = google_sql_database_instance.performance_monitoring_db.edition
}

# Query Insights Configuration
output "query_insights_enabled" {
  description = "Whether Query Insights is enabled for advanced performance monitoring"
  value       = google_sql_database_instance.performance_monitoring_db.settings[0].insights_config[0].query_insights_enabled
}

output "query_string_length" {
  description = "Maximum length of query strings captured by Query Insights"
  value       = google_sql_database_instance.performance_monitoring_db.settings[0].insights_config[0].query_string_length
}

# Authentication Information
output "database_root_user" {
  description = "Root username for database connection"
  value       = google_sql_user.postgres_user.name
}

output "database_root_password" {
  description = "Root password for database connection (sensitive)"
  value       = local.db_password
  sensitive   = true
}

output "test_database_name" {
  description = "Name of the test database for performance monitoring validation"
  value       = google_sql_database.performance_test_db.name
}

# Monitoring and Alerting Resources
output "monitoring_dashboard_url" {
  description = "URL to access the custom Cloud Monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${basename(google_monitoring_dashboard.db_performance_dashboard.id)}?project=${var.project_id}"
}

output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for database alerts"
  value       = google_pubsub_topic.db_alerts.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.db_alerts.id
}

# Cloud Function Information
output "alert_function_name" {
  description = "Name of the Cloud Function for processing database alerts"
  value       = google_cloudfunctions_function.db_alert_handler.name
}

output "alert_function_url" {
  description = "HTTP trigger URL for the alert processing function"
  value       = google_cloudfunctions_function.db_alert_handler.https_trigger_url
}

output "function_service_account" {
  description = "Service account email used by the alert processing function"
  value       = google_service_account.function_sa.email
}

# Storage Resources
output "performance_reports_bucket" {
  description = "Name of the Cloud Storage bucket for performance reports"
  value       = google_storage_bucket.performance_reports.name
}

output "performance_reports_bucket_url" {
  description = "URL of the Cloud Storage bucket for performance reports"
  value       = google_storage_bucket.performance_reports.url
}

output "function_source_bucket" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

# Alerting Policies
output "cpu_alert_policy_name" {
  description = "Name of the CPU utilization alerting policy"
  value       = google_monitoring_alert_policy.high_cpu_usage.display_name
}

output "slow_query_alert_policy_name" {
  description = "Name of the slow query detection alerting policy"
  value       = google_monitoring_alert_policy.slow_query_detection.display_name
}

output "notification_channel_id" {
  description = "ID of the Pub/Sub notification channel for alerts"
  value       = google_monitoring_notification_channel.pubsub_channel.id
}

# Connection Commands and Instructions
output "psql_connection_command" {
  description = "Command to connect to the database using psql"
  value       = "gcloud sql connect ${google_sql_database_instance.performance_monitoring_db.name} --user=postgres --database=${google_sql_database.performance_test_db.name}"
}

output "gcloud_sql_proxy_command" {
  description = "Command to start Cloud SQL Proxy for secure connections"
  value       = "gcloud sql proxy ${google_sql_database_instance.performance_monitoring_db.connection_name} --port=5432"
}

# Resource URLs for Quick Access
output "cloud_sql_console_url" {
  description = "URL to view the Cloud SQL instance in Google Cloud Console"
  value       = "https://console.cloud.google.com/sql/instances/${google_sql_database_instance.performance_monitoring_db.name}/overview?project=${var.project_id}"
}

output "query_insights_url" {
  description = "URL to access Query Insights for the database instance"
  value       = "https://console.cloud.google.com/sql/instances/${google_sql_database_instance.performance_monitoring_db.name}/insights?project=${var.project_id}"
}

output "monitoring_console_url" {
  description = "URL to access Cloud Monitoring for the project"
  value       = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
}

output "cloud_functions_console_url" {
  description = "URL to view the Cloud Function in Google Cloud Console"
  value       = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.db_alert_handler.name}?project=${var.project_id}"
}

# Performance Testing Information
output "performance_test_setup_commands" {
  description = "Commands to set up performance testing on the database"
  value = [
    "# Connect to the database",
    "gcloud sql connect ${google_sql_database_instance.performance_monitoring_db.name} --user=postgres --database=${google_sql_database.performance_test_db.name}",
    "",
    "# Create test table and data",
    "CREATE TABLE performance_test (id SERIAL PRIMARY KEY, name VARCHAR(100), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, data TEXT);",
    "INSERT INTO performance_test (name, data) SELECT 'Test User ' || generate_series(1, 1000), 'Sample data for performance testing';",
    "",
    "# Generate test queries for monitoring",
    "SELECT COUNT(*) FROM performance_test WHERE name LIKE '%User 5%';",
    "SELECT * FROM performance_test ORDER BY created_at DESC LIMIT 100;"
  ]
}

# Cost and Resource Information
output "estimated_monthly_cost_usd" {
  description = "Estimated monthly cost in USD for the deployed resources"
  value       = "Approximately $200-300 USD per month for Cloud SQL Enterprise Plus, monitoring, and associated services"
}

output "resource_summary" {
  description = "Summary of deployed resources for inventory tracking"
  value = {
    cloud_sql_instance = google_sql_database_instance.performance_monitoring_db.name
    databases          = [google_sql_database.performance_test_db.name]
    storage_buckets    = [google_storage_bucket.performance_reports.name, google_storage_bucket.function_source.name]
    cloud_function     = google_cloudfunctions_function.db_alert_handler.name
    pubsub_topic       = google_pubsub_topic.db_alerts.name
    alert_policies     = [google_monitoring_alert_policy.high_cpu_usage.display_name, google_monitoring_alert_policy.slow_query_detection.display_name]
    dashboard          = google_monitoring_dashboard.db_performance_dashboard.id
  }
}

# Cleanup Information
output "cleanup_order" {
  description = "Recommended order for manual resource cleanup if needed"
  value = [
    "1. Delete alerting policies and notification channels",
    "2. Delete Cloud Function",
    "3. Delete Pub/Sub topic",
    "4. Delete monitoring dashboard",
    "5. Delete Cloud Storage buckets (after ensuring no important data)",
    "6. Delete Cloud SQL database and instance",
    "7. Delete service accounts",
    "8. Disable APIs if no longer needed"
  ]
}