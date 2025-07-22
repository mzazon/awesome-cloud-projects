# Output Values for Edge Analytics Infrastructure
# Outputs provide important resource information for integration and verification

# Project and Location Information
output "project_id" {
  description = "Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region where resources are deployed"
  value       = var.region
}

output "zone" {
  description = "Google Cloud zone where resources are deployed"
  value       = var.zone
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# Cloud Storage Outputs
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for analytics data"
  value       = google_storage_bucket.analytics_data_lake.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.analytics_data_lake.url
}

output "storage_bucket_self_link" {
  description = "Self-link of the Cloud Storage bucket"
  value       = google_storage_bucket.analytics_data_lake.self_link
}

# Pub/Sub Outputs
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for IoT sensor data"
  value       = google_pubsub_topic.iot_sensor_data.name
}

output "pubsub_topic_id" {
  description = "Full ID of the Pub/Sub topic"
  value       = google_pubsub_topic.iot_sensor_data.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription"
  value       = google_pubsub_subscription.analytics_subscription.name
}

output "pubsub_subscription_id" {
  description = "Full ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.analytics_subscription.id
}

# Cloud Run Outputs
output "cloud_run_service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.edge_analytics.name
}

output "cloud_run_service_uri" {
  description = "URI of the deployed Cloud Run service"
  value       = google_cloud_run_v2_service.edge_analytics.uri
}

output "cloud_run_service_url" {
  description = "URL of the Cloud Run service endpoint"
  value       = "https://${google_cloud_run_v2_service.edge_analytics.uri}"
}

output "cloud_run_location" {
  description = "Location where the Cloud Run service is deployed"
  value       = google_cloud_run_v2_service.edge_analytics.location
}

# Firestore Outputs
output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.analytics_metadata.name
}

output "firestore_database_id" {
  description = "ID of the Firestore database"
  value       = google_firestore_database.analytics_metadata.database_id
}

output "firestore_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.analytics_metadata.location_id
}

# Service Account Outputs
output "cloud_run_service_account_email" {
  description = "Email of the Cloud Run service account"
  value       = google_service_account.cloud_run_sa.email
}

output "cloud_run_service_account_id" {
  description = "ID of the Cloud Run service account"
  value       = google_service_account.cloud_run_sa.account_id
}

# IAM Outputs
output "pubsub_publisher_email" {
  description = "Email of the Pub/Sub publisher service account"
  value       = google_service_account.pubsub_publisher.email
}

# Monitoring Outputs
output "monitoring_dashboard_url" {
  description = "URL to view the Cloud Monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.edge_analytics.id}?project=${var.project_id}"
}

output "alert_policy_ids" {
  description = "IDs of the created alert policies"
  value = var.enable_monitoring_alerts ? {
    anomaly_detection = google_monitoring_alert_policy.anomaly_detection[0].name
    data_processing   = google_monitoring_alert_policy.data_processing_rate[0].name
    service_errors    = google_monitoring_alert_policy.service_errors[0].name
  } : {}
}

# API Endpoints
output "process_endpoint" {
  description = "Full URL for the data processing endpoint"
  value       = "${google_cloud_run_v2_service.edge_analytics.uri}/process"
}

output "health_check_endpoint" {
  description = "Full URL for the health check endpoint"
  value       = "${google_cloud_run_v2_service.edge_analytics.uri}/health"
}

# Resource Names with Random Suffix
output "resource_suffix" {
  description = "Random suffix used for resource names"
  value       = var.use_random_suffix ? random_id.suffix[0].hex : ""
}

output "all_resource_names" {
  description = "Map of all created resource names for reference"
  value = {
    storage_bucket        = google_storage_bucket.analytics_data_lake.name
    pubsub_topic         = google_pubsub_topic.iot_sensor_data.name
    pubsub_subscription  = google_pubsub_subscription.analytics_subscription.name
    cloud_run_service    = google_cloud_run_v2_service.edge_analytics.name
    firestore_database   = google_firestore_database.analytics_metadata.name
    service_account      = google_service_account.cloud_run_sa.email
    publisher_account    = google_service_account.pubsub_publisher.email
  }
}

# Environment Information
output "deployment_info" {
  description = "Deployment information for verification and documentation"
  value = {
    project_id          = var.project_id
    region             = var.region
    environment        = var.environment
    terraform_version  = ">= 1.8"
    provider_version   = "~> 6.0"
    deployment_time    = timestamp()
    resource_prefix    = var.resource_prefix
    random_suffix      = var.use_random_suffix ? random_id.suffix[0].hex : "none"
  }
}

# Security Information
output "security_configuration" {
  description = "Security configuration details"
  value = {
    binary_authorization_enabled = var.enable_binary_authorization
    ingress_configuration       = var.ingress
    unauthenticated_access      = var.enable_cloud_run_all_users
    storage_versioning_enabled  = var.enable_versioning
  }
  sensitive = false
}

# Cost Management Information
output "cost_optimization_features" {
  description = "Enabled cost optimization features"
  value = {
    storage_lifecycle_enabled = var.enable_lifecycle_management
    storage_versioning       = var.enable_versioning
    nearline_transition_days = var.lifecycle_age_nearline
    coldline_transition_days = var.lifecycle_age_coldline
    cloud_run_min_instances  = var.cloud_run_min_instances
    cloud_run_max_instances  = var.cloud_run_max_instances
  }
}

# Connection Information for Client Applications
output "connection_info" {
  description = "Connection information for client applications and testing"
  value = {
    pubsub_topic_path     = "projects/${var.project_id}/topics/${google_pubsub_topic.iot_sensor_data.name}"
    storage_bucket_path   = "gs://${google_storage_bucket.analytics_data_lake.name}"
    firestore_path        = "(default)"
    cloud_run_endpoint    = google_cloud_run_v2_service.edge_analytics.uri
    processing_endpoint   = "${google_cloud_run_v2_service.edge_analytics.uri}/process"
  }
  sensitive = false
}