# Infrastructure identifiers and connection information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were deployed"
  value       = var.region
}

output "environment" {
  description = "The environment name for this deployment"
  value       = var.environment
}

output "random_suffix" {
  description = "Random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Cloud Run service outputs
output "cloud_run_service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.route_optimizer.name
}

output "cloud_run_service_url" {
  description = "URL of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.route_optimizer.uri
  sensitive   = false
}

output "cloud_run_service_id" {
  description = "Full resource ID of the Cloud Run service"
  value       = google_cloud_run_v2_service.route_optimizer.id
}

output "cloud_run_service_location" {
  description = "Location of the Cloud Run service"
  value       = google_cloud_run_v2_service.route_optimizer.location
}

# API endpoints for external access
output "route_optimization_endpoint" {
  description = "Full URL for the route optimization API endpoint"
  value       = "${google_cloud_run_v2_service.route_optimizer.uri}/optimize-route"
}

output "analytics_endpoint" {
  description = "Full URL for the analytics API endpoint"
  value       = "${google_cloud_run_v2_service.route_optimizer.uri}/analytics"
}

output "health_check_endpoint" {
  description = "Full URL for the health check endpoint"
  value       = "${google_cloud_run_v2_service.route_optimizer.uri}/health"
}

# Cloud SQL database outputs
output "sql_instance_name" {
  description = "Name of the Cloud SQL instance"
  value       = google_sql_database_instance.route_analytics.name
}

output "sql_instance_connection_name" {
  description = "Connection name for the Cloud SQL instance"
  value       = google_sql_database_instance.route_analytics.connection_name
}

output "sql_instance_ip_address" {
  description = "IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.route_analytics.ip_address
  sensitive   = false
}

output "sql_instance_private_ip_address" {
  description = "Private IP address of the Cloud SQL instance (if private networking enabled)"
  value       = google_sql_database_instance.route_analytics.private_ip_address
  sensitive   = false
}

output "database_name" {
  description = "Name of the route analytics database"
  value       = google_sql_database.route_analytics_db.name
}

output "database_user" {
  description = "Database username for application access"
  value       = google_sql_user.postgres_user.name
}

# Pub/Sub messaging outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for route events"
  value       = google_pubsub_topic.route_events.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.route_events.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription"
  value       = google_pubsub_subscription.route_events_sub.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.route_events_sub.id
}

output "pubsub_dlq_topic_name" {
  description = "Name of the dead letter queue topic"
  value       = google_pubsub_topic.route_events_dlq.name
}

# Cloud Function outputs
output "cloud_function_name" {
  description = "Name of the Cloud Function for route processing"
  value       = google_cloudfunctions2_function.route_processor.name
}

output "cloud_function_id" {
  description = "Full resource ID of the Cloud Function"
  value       = google_cloudfunctions2_function.route_processor.id
}

output "cloud_function_uri" {
  description = "URI of the Cloud Function"
  value       = google_cloudfunctions2_function.route_processor.service_config[0].uri
}

# Service accounts for identity and access management
output "cloud_run_service_account_email" {
  description = "Email of the Cloud Run service account"
  value       = google_service_account.cloud_run_sa.email
}

output "cloud_function_service_account_email" {
  description = "Email of the Cloud Function service account"
  value       = google_service_account.cloud_function_sa.email
}

# Secret Manager outputs
output "db_password_secret_name" {
  description = "Name of the Secret Manager secret for database password"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "maps_api_key_secret_name" {
  description = "Name of the Secret Manager secret for Maps API key"
  value       = google_secret_manager_secret.maps_api_key.secret_id
}

# Storage outputs
output "function_source_bucket_name" {
  description = "Name of the storage bucket for Cloud Function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the storage bucket for Cloud Function source code"
  value       = google_storage_bucket.function_source.url
}

output "logs_bucket_name" {
  description = "Name of the storage bucket for log archival (if monitoring enabled)"
  value       = var.enable_monitoring ? google_storage_bucket.logs_bucket[0].name : null
}

# Networking outputs (conditional on private networking)
output "vpc_network_name" {
  description = "Name of the VPC network (if private networking enabled)"
  value       = var.enable_private_ip ? google_compute_network.vpc_network[0].name : null
}

output "vpc_network_id" {
  description = "Full resource ID of the VPC network (if private networking enabled)"
  value       = var.enable_private_ip ? google_compute_network.vpc_network[0].id : null
}

output "vpc_connector_name" {
  description = "Name of the VPC Access Connector (if private networking enabled)"
  value       = var.enable_private_ip ? google_vpc_access_connector.connector[0].name : null
}

output "private_ip_address_name" {
  description = "Name of the private IP address allocation (if private networking enabled)"
  value       = var.enable_private_ip ? google_compute_global_address.private_ip_address[0].name : null
}

# Monitoring and alerting outputs
output "monitoring_alert_policy_id" {
  description = "ID of the monitoring alert policy (if monitoring enabled)"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.high_error_rate[0].name : null
}

output "log_sink_name" {
  description = "Name of the log sink (if monitoring enabled)"
  value       = var.enable_monitoring ? google_logging_project_sink.route_optimizer_sink[0].name : null
}

# Configuration and deployment information
output "deployment_timestamp" {
  description = "Timestamp when the infrastructure was deployed"
  value       = timestamp()
}

output "terraform_version" {
  description = "Version of Terraform used for deployment"
  value       = "~> 1.0"
}

output "resource_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
  sensitive   = false
}

# Connection strings and configuration for applications
output "database_connection_config" {
  description = "Database connection configuration for applications"
  value = {
    host         = google_sql_database_instance.route_analytics.connection_name
    database     = google_sql_database.route_analytics_db.name
    user         = google_sql_user.postgres_user.name
    ssl_mode     = "require"
    timeout      = "30s"
    max_conns    = "25"
  }
  sensitive = false
}

output "pubsub_config" {
  description = "Pub/Sub configuration for event publishing"
  value = {
    topic_name           = google_pubsub_topic.route_events.name
    subscription_name    = google_pubsub_subscription.route_events_sub.name
    dlq_topic_name      = google_pubsub_topic.route_events_dlq.name
    ack_deadline_seconds = var.pubsub_ack_deadline
    retention_duration   = var.pubsub_message_retention_duration
  }
  sensitive = false
}

# Summary output for deployment verification
output "deployment_summary" {
  description = "Summary of deployed infrastructure components"
  value = {
    cloud_run_service    = google_cloud_run_v2_service.route_optimizer.name
    sql_instance        = google_sql_database_instance.route_analytics.name
    database            = google_sql_database.route_analytics_db.name
    pubsub_topic        = google_pubsub_topic.route_events.name
    cloud_function      = google_cloudfunctions2_function.route_processor.name
    service_url         = google_cloud_run_v2_service.route_optimizer.uri
    private_networking  = var.enable_private_ip
    monitoring_enabled  = var.enable_monitoring
    ha_enabled         = var.sql_ha_enabled
    backup_enabled     = var.sql_backup_enabled
  }
  sensitive = false
}

# Instructions for next steps
output "next_steps" {
  description = "Instructions for completing the deployment"
  value = [
    "1. Upload application source code to Cloud Run service: ${google_cloud_run_v2_service.route_optimizer.name}",
    "2. Upload Cloud Function source code to bucket: ${google_storage_bucket.function_source.name}",
    "3. Initialize database schema using the Cloud SQL connection: ${google_sql_database_instance.route_analytics.connection_name}",
    "4. Test the route optimization API at: ${google_cloud_run_v2_service.route_optimizer.uri}/optimize-route",
    "5. Monitor service health at: ${google_cloud_run_v2_service.route_optimizer.uri}/health",
    "6. View analytics dashboard at: ${google_cloud_run_v2_service.route_optimizer.uri}/analytics"
  ]
}