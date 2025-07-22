# Project Information
output "project_id" {
  description = "Google Cloud Project ID"
  value       = var.project_id
}

output "region" {
  description = "Google Cloud region used for deployment"
  value       = var.region
}

output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

# Service Account Information
output "service_account_email" {
  description = "Email of the translation service account"
  value       = google_service_account.translation_service.email
}

output "service_account_id" {
  description = "ID of the translation service account"
  value       = google_service_account.translation_service.account_id
}

# Cloud Run Service Information
output "cloud_run_service_name" {
  description = "Name of the Cloud Run translation service"
  value       = google_cloud_run_v2_service.translation_service.name
}

output "cloud_run_service_url" {
  description = "URL of the Cloud Run translation service"
  value       = google_cloud_run_v2_service.translation_service.uri
}

output "cloud_run_service_location" {
  description = "Location of the Cloud Run service"
  value       = google_cloud_run_v2_service.translation_service.location
}

output "websocket_url" {
  description = "WebSocket URL for real-time translation connections"
  value       = replace(google_cloud_run_v2_service.translation_service.uri, "https://", "wss://")
}

# Firestore Database Information
output "firestore_database_name" {
  description = "Name of the Firestore database"
  value       = google_firestore_database.translation_conversations.name
}

output "firestore_location" {
  description = "Location of the Firestore database"
  value       = google_firestore_database.translation_conversations.location_id
}

# Cloud Storage Information
output "audio_storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for audio files"
  value       = google_storage_bucket.audio_files.name
}

output "audio_storage_bucket_url" {
  description = "URL of the Cloud Storage bucket for audio files"
  value       = google_storage_bucket.audio_files.url
}

output "audio_storage_bucket_location" {
  description = "Location of the Cloud Storage bucket"
  value       = google_storage_bucket.audio_files.location
}

# Pub/Sub Information
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for translation events"
  value       = google_pubsub_topic.translation_events.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.translation_events.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for translation processing"
  value       = google_pubsub_subscription.translation_processor.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.translation_processor.id
}

output "pubsub_dlq_topic_name" {
  description = "Name of the dead letter queue topic"
  value       = google_pubsub_topic.translation_dlq.name
}

# Configuration Information
output "default_source_language" {
  description = "Default source language for translation"
  value       = var.default_source_language
}

output "default_target_languages" {
  description = "Default target languages for translation"
  value       = var.default_target_languages
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# Service Configuration
output "service_configuration" {
  description = "Key service configuration parameters"
  value = {
    cpu_limit            = var.cpu_limit
    memory_limit         = var.memory_limit
    max_instances        = var.max_instances
    concurrency_limit    = var.concurrency_limit
    timeout_seconds      = var.timeout_seconds
    allow_unauthenticated = var.allow_unauthenticated
  }
  sensitive = false
}

# Monitoring Information
output "monitoring_enabled" {
  description = "Whether monitoring and alerting is enabled"
  value       = var.enable_monitoring
}

output "uptime_check_id" {
  description = "ID of the uptime check for the translation service"
  value       = var.enable_monitoring ? google_monitoring_uptime_check_config.translation_service_check[0].uptime_check_id : null
}

output "alert_policy_name" {
  description = "Name of the alert policy for service monitoring"
  value       = var.enable_monitoring ? google_monitoring_alert_policy.translation_service_down[0].display_name : null
}

# API Endpoints and Connection Information
output "api_endpoints" {
  description = "Important API endpoints and connection information"
  value = {
    health_check_url = "${google_cloud_run_v2_service.translation_service.uri}/health"
    websocket_url    = replace(google_cloud_run_v2_service.translation_service.uri, "https://", "wss://")
    rest_api_url     = google_cloud_run_v2_service.translation_service.uri
  }
}

# Resource Names for Client Applications
output "resource_names" {
  description = "Resource names for use in client applications"
  value = {
    project_id           = var.project_id
    service_account      = google_service_account.translation_service.email
    firestore_database   = google_firestore_database.translation_conversations.name
    storage_bucket       = google_storage_bucket.audio_files.name
    pubsub_topic         = google_pubsub_topic.translation_events.name
    pubsub_subscription  = google_pubsub_subscription.translation_processor.name
    cloud_run_service    = google_cloud_run_v2_service.translation_service.name
  }
}

# Deployment Commands
output "deployment_commands" {
  description = "Commands for deploying application code to Cloud Run"
  value = {
    build_and_deploy = "gcloud run deploy ${google_cloud_run_v2_service.translation_service.name} --source . --region ${var.region} --project ${var.project_id}"
    service_url      = "gcloud run services describe ${google_cloud_run_v2_service.translation_service.name} --region ${var.region} --format='value(status.url)'"
    logs             = "gcloud run services logs read ${google_cloud_run_v2_service.translation_service.name} --region ${var.region} --project ${var.project_id}"
  }
}

# Test and Validation Information
output "test_commands" {
  description = "Commands for testing the deployed infrastructure"
  value = {
    health_check      = "curl -f ${google_cloud_run_v2_service.translation_service.uri}/health"
    websocket_test    = "wscat -c ${replace(google_cloud_run_v2_service.translation_service.uri, "https://", "wss://")}"
    firestore_query   = "gcloud firestore collections list --database=${google_firestore_database.translation_conversations.name}"
    pubsub_test       = "gcloud pubsub topics publish ${google_pubsub_topic.translation_events.name} --message='test message'"
    storage_test      = "gsutil ls gs://${google_storage_bucket.audio_files.name}/"
  }
}

# Security and Access Information
output "security_configuration" {
  description = "Security and access configuration details"
  value = {
    service_account_email    = google_service_account.translation_service.email
    allow_unauthenticated   = var.allow_unauthenticated
    audit_logs_enabled      = var.enable_audit_logs
    firestore_security      = "Native mode with optimistic concurrency"
    storage_security        = "Uniform bucket-level access enabled"
    pubsub_security         = "IAM-based access control"
  }
  sensitive = false
}

# Cost Optimization Information
output "cost_optimization" {
  description = "Cost optimization features enabled"
  value = {
    cloud_run_min_instances    = 0
    cloud_run_max_instances    = var.max_instances
    storage_lifecycle_enabled  = true
    audio_retention_days       = var.audio_retention_days
    pubsub_message_retention   = var.message_retention_duration
    firestore_pitr_enabled     = true
  }
}