# App Engine application outputs
output "app_engine_url" {
  description = "The URL of the deployed App Engine application"
  value       = "https://${google_app_engine_application.expense_app.default_hostname}"
}

output "app_engine_service_account" {
  description = "The email of the service account used by App Engine"
  value       = google_service_account.app_engine_sa.email
}

output "app_engine_version" {
  description = "The version ID of the deployed App Engine application"
  value       = google_app_engine_standard_app_version.expense_app_v1.version_id
}

# Cloud SQL database outputs
output "database_instance_name" {
  description = "The name of the Cloud SQL instance"
  value       = google_sql_database_instance.expense_db.name
}

output "database_connection_name" {
  description = "The connection name for the Cloud SQL instance (used for App Engine connections)"
  value       = google_sql_database_instance.expense_db.connection_name
}

output "database_public_ip" {
  description = "The public IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.expense_db.public_ip_address
}

output "database_private_ip" {
  description = "The private IP address of the Cloud SQL instance (if applicable)"
  value       = google_sql_database_instance.expense_db.private_ip_address
}

output "database_self_link" {
  description = "The self-link of the Cloud SQL instance"
  value       = google_sql_database_instance.expense_db.self_link
}

# Database configuration outputs
output "database_name" {
  description = "The name of the application database"
  value       = google_sql_database.expense_database.name
}

output "database_user" {
  description = "The username for database access"
  value       = google_sql_user.expense_user.name
}

output "database_password" {
  description = "The password for database access (sensitive)"
  value       = local.db_password
  sensitive   = true
}

# Project and region information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were created"
  value       = var.region
}

output "app_engine_location" {
  description = "The location where the App Engine application was created"
  value       = google_app_engine_application.expense_app.location_id
}

# Storage outputs
output "source_bucket_name" {
  description = "The name of the Cloud Storage bucket containing application source code"
  value       = google_storage_bucket.app_source.name
}

output "source_bucket_url" {
  description = "The URL of the Cloud Storage bucket containing application source code"
  value       = google_storage_bucket.app_source.url
}

# Resource naming outputs
output "resource_suffix" {
  description = "The random suffix used for resource naming"
  value       = random_id.suffix.hex
}

output "common_labels" {
  description = "The common labels applied to all resources"
  value       = local.common_labels
}

# Security outputs
output "app_secret_key" {
  description = "The Flask application secret key (sensitive)"
  value       = random_password.app_secret_key.result
  sensitive   = true
}

# Connection information
output "database_connection_string" {
  description = "Example connection string for local development (sensitive)"
  value       = "postgresql://${google_sql_user.expense_user.name}:${local.db_password}@${google_sql_database_instance.expense_db.public_ip_address}/${google_sql_database.expense_database.name}"
  sensitive   = true
}

# Cloud SQL proxy command
output "cloud_sql_proxy_command" {
  description = "Command to connect to Cloud SQL instance using cloud_sql_proxy"
  value       = "cloud_sql_proxy -instances=${google_sql_database_instance.expense_db.connection_name}=tcp:5432"
}

# Useful gcloud commands
output "gcloud_app_logs_command" {
  description = "Command to view App Engine application logs"
  value       = "gcloud app logs tail -s default --project=${var.project_id}"
}

output "gcloud_sql_connect_command" {
  description = "Command to connect to Cloud SQL instance using gcloud"
  value       = "gcloud sql connect ${google_sql_database_instance.expense_db.name} --user=${google_sql_user.expense_user.name} --database=${google_sql_database.expense_database.name} --project=${var.project_id}"
}

# Cost estimation information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost for the deployed resources (USD)"
  value = {
    app_engine_f1_instances = "Free tier: $0.00 for F1 instances under quota"
    cloud_sql_db_f1_micro  = "~$7.35/month for db-f1-micro instance"
    cloud_storage_standard = "~$0.02/GB/month for storage"
    total_estimate         = "~$7.50-$10.00/month for typical usage"
    note                   = "Costs may vary based on actual usage, data transfer, and storage"
  }
}

# Monitoring and management URLs
output "cloud_console_urls" {
  description = "Useful Cloud Console URLs for managing the application"
  value = {
    app_engine      = "https://console.cloud.google.com/appengine?project=${var.project_id}"
    cloud_sql       = "https://console.cloud.google.com/sql/instances/${google_sql_database_instance.expense_db.name}/overview?project=${var.project_id}"
    cloud_storage   = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.app_source.name}?project=${var.project_id}"
    iam_service_accounts = "https://console.cloud.google.com/iam-admin/serviceaccounts?project=${var.project_id}"
    logging         = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
    monitoring      = "https://console.cloud.google.com/monitoring?project=${var.project_id}"
  }
}

# Deployment verification
output "deployment_verification" {
  description = "Steps to verify the deployment"
  value = {
    step_1 = "Visit the application URL: https://${google_app_engine_application.expense_app.default_hostname}"
    step_2 = "Check App Engine logs: gcloud app logs tail -s default --project=${var.project_id}"
    step_3 = "Verify database connection: ${self.cloud_sql_proxy_command}"
    step_4 = "Monitor resources in Cloud Console"
  }
}