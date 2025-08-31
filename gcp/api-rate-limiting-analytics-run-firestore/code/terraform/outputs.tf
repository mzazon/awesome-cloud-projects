# Output values for the GCP API Rate Limiting and Analytics infrastructure
# These outputs provide important information for integration and verification

# Project and region information
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

# Cloud Run service outputs
output "service_name" {
  description = "The name of the deployed Cloud Run service"
  value       = google_cloud_run_service.api_gateway.name
}

output "service_url" {
  description = "The URL of the deployed API gateway service"
  value       = google_cloud_run_service.api_gateway.status[0].url
  sensitive   = false
}

output "service_id" {
  description = "The unique identifier of the Cloud Run service"
  value       = google_cloud_run_service.api_gateway.id
}

output "service_location" {
  description = "The location where the Cloud Run service is deployed"
  value       = google_cloud_run_service.api_gateway.location
}

# Service account information
output "service_account_email" {
  description = "Email address of the service account used by the API gateway"
  value       = google_service_account.api_gateway.email
}

output "service_account_id" {
  description = "The unique ID of the service account"
  value       = google_service_account.api_gateway.unique_id
}

# Firestore database information
output "firestore_database_name" {
  description = "The name of the Firestore database"
  value       = google_firestore_database.api_analytics.name
}

output "firestore_database_id" {
  description = "The ID of the Firestore database"
  value       = google_firestore_database.api_analytics.id
}

output "firestore_location" {
  description = "The location of the Firestore database"
  value       = google_firestore_database.api_analytics.location_id
}

# Storage bucket information
output "source_bucket_name" {
  description = "The name of the Cloud Storage bucket for source code"
  value       = google_storage_bucket.source_code.name
}

output "source_bucket_url" {
  description = "The URL of the Cloud Storage bucket for source code"
  value       = google_storage_bucket.source_code.url
}

# Monitoring outputs
output "monitoring_dashboard_id" {
  description = "The ID of the Cloud Monitoring dashboard (if created)"
  value       = var.monitoring_config.enable_dashboard ? google_monitoring_dashboard.api_analytics[0].id : null
}

output "alert_policy_ids" {
  description = "The IDs of the created alert policies"
  value = {
    high_error_rate = var.monitoring_config.enable_alerts ? google_monitoring_alert_policy.high_error_rate[0].id : null
    high_latency    = var.monitoring_config.enable_alerts ? google_monitoring_alert_policy.high_latency[0].id : null
  }
}

output "notification_channel_id" {
  description = "The ID of the email notification channel (if created)"
  value       = var.monitoring_config.enable_alerts && var.monitoring_config.alert_email != "" ? google_monitoring_notification_channel.email[0].id : null
  sensitive   = true
}

# Configuration outputs for reference
output "rate_limiting_config" {
  description = "The rate limiting configuration applied to the service"
  value = {
    default_requests_per_hour = var.rate_limiting_config.default_requests_per_hour
    rate_window_seconds      = var.rate_limiting_config.rate_window_seconds
    burst_capacity          = var.rate_limiting_config.burst_capacity
  }
}

output "cloud_run_config" {
  description = "The Cloud Run service configuration"
  value = {
    cpu_limit       = var.cloud_run_config.cpu_limit
    memory_limit    = var.cloud_run_config.memory_limit
    max_instances   = var.cloud_run_config.max_instances
    min_instances   = var.cloud_run_config.min_instances
    concurrency     = var.cloud_run_config.concurrency
    timeout_seconds = var.cloud_run_config.timeout_seconds
  }
}

# API endpoints for testing and integration
output "api_endpoints" {
  description = "API endpoints available for testing"
  value = {
    health        = "${google_cloud_run_service.api_gateway.status[0].url}/health"
    data_api      = "${google_cloud_run_service.api_gateway.status[0].url}/api/v1/data"
    analytics_api = "${google_cloud_run_service.api_gateway.status[0].url}/api/v1/analytics"
  }
}

# Container image information
output "container_image" {
  description = "The container image used for the Cloud Run service"
  value       = local.container_image
}

# Random suffix for resource naming
output "resource_suffix" {
  description = "The random suffix used for resource naming"
  value       = random_id.suffix.hex
}

# Environment variables for the Cloud Run service
output "environment_variables" {
  description = "Environment variables configured for the Cloud Run service"
  value = {
    PROJECT_ID           = var.project_id
    FIRESTORE_DATABASE   = google_firestore_database.api_analytics.name
    DEFAULT_RATE_LIMIT   = var.rate_limiting_config.default_requests_per_hour
    RATE_WINDOW_SECONDS  = var.rate_limiting_config.rate_window_seconds
    ENVIRONMENT          = var.environment
  }
  sensitive = false
}

# Labels applied to resources
output "resource_labels" {
  description = "Labels applied to all resources"
  value       = local.common_labels
}

# Security and access information
output "security_info" {
  description = "Security configuration and access information"
  value = {
    allow_unauthenticated_access = var.cloud_run_config.allow_unauthenticated
    firestore_rules_file        = "${path.module}/firestore.rules"
    iam_roles_granted = [
      "roles/datastore.user",
      "roles/monitoring.metricWriter",
      "roles/logging.logWriter"
    ]
  }
}

# Cost optimization information
output "cost_optimization" {
  description = "Cost optimization features enabled"
  value = {
    min_instances_zero = var.cloud_run_config.min_instances == 0
    auto_scaling      = true
    storage_lifecycle = true
    monitoring_free_tier = true
  }
}

# Next steps and integration guidance
output "next_steps" {
  description = "Next steps for completing the deployment"
  value = {
    build_and_deploy = "Build your application container and deploy to gcr.io/${var.project_id}/${var.service_name}:latest"
    firestore_rules  = "Deploy Firestore security rules using: gcloud firestore rules update ${path.module}/firestore.rules"
    test_endpoints   = "Test the API using the service_url with X-API-Key header"
    monitoring      = var.monitoring_config.enable_dashboard ? "View monitoring dashboard in Google Cloud Console" : "Enable monitoring by setting monitoring_config.enable_dashboard = true"
  }
}