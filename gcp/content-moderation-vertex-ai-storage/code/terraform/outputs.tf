# Output Values for Content Moderation Infrastructure
# This file defines outputs that provide information about created resources

# Project Information
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

# Cloud Storage Buckets
output "incoming_bucket_name" {
  description = "Name of the Cloud Storage bucket for incoming content"
  value       = google_storage_bucket.incoming.name
}

output "incoming_bucket_url" {
  description = "URL of the Cloud Storage bucket for incoming content"
  value       = google_storage_bucket.incoming.url
}

output "quarantine_bucket_name" {
  description = "Name of the Cloud Storage bucket for quarantined content"
  value       = google_storage_bucket.quarantine.name
}

output "quarantine_bucket_url" {
  description = "URL of the Cloud Storage bucket for quarantined content"
  value       = google_storage_bucket.quarantine.url
}

output "approved_bucket_name" {
  description = "Name of the Cloud Storage bucket for approved content"
  value       = google_storage_bucket.approved.name
}

output "approved_bucket_url" {
  description = "URL of the Cloud Storage bucket for approved content"
  value       = google_storage_bucket.approved.url
}

output "function_source_bucket_name" {
  description = "Name of the Cloud Storage bucket for function source code"
  value       = google_storage_bucket.function_source.name
}

# Service Account
output "service_account_email" {
  description = "Email address of the service account used by the functions"
  value       = var.custom_service_account_email != null ? var.custom_service_account_email : (length(google_service_account.content_moderator) > 0 ? google_service_account.content_moderator[0].email : "")
}

output "service_account_name" {
  description = "Name of the service account used by the functions"
  value       = var.custom_service_account_email != null ? var.custom_service_account_email : (length(google_service_account.content_moderator) > 0 ? google_service_account.content_moderator[0].name : "")
}

# Pub/Sub Resources
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for content moderation events"
  value       = google_pubsub_topic.content_moderation.name
}

output "pubsub_topic_id" {
  description = "ID of the Pub/Sub topic for content moderation events"
  value       = google_pubsub_topic.content_moderation.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for content moderation"
  value       = google_pubsub_subscription.content_moderation.name
}

output "pubsub_subscription_id" {
  description = "ID of the Pub/Sub subscription for content moderation"
  value       = google_pubsub_subscription.content_moderation.id
}

# Cloud Functions
output "content_moderation_function_name" {
  description = "Name of the content moderation Cloud Function"
  value       = google_cloudfunctions2_function.content_moderator.name
}

output "content_moderation_function_id" {
  description = "ID of the content moderation Cloud Function"
  value       = google_cloudfunctions2_function.content_moderator.id
}

output "content_moderation_function_url" {
  description = "URL of the content moderation Cloud Function"
  value       = google_cloudfunctions2_function.content_moderator.service_config[0].uri
}

output "notification_function_name" {
  description = "Name of the notification Cloud Function"
  value       = var.create_notification_function ? google_cloudfunctions2_function.notification_handler[0].name : ""
}

output "notification_function_id" {
  description = "ID of the notification Cloud Function"
  value       = var.create_notification_function ? google_cloudfunctions2_function.notification_handler[0].id : ""
}

output "notification_function_url" {
  description = "URL of the notification Cloud Function"
  value       = var.create_notification_function ? google_cloudfunctions2_function.notification_handler[0].service_config[0].uri : ""
}

# Monitoring
output "monitoring_alert_policy_name" {
  description = "Name of the monitoring alert policy for quarantined content"
  value       = google_monitoring_alert_policy.quarantine_alert.name
}

output "monitoring_alert_policy_id" {
  description = "ID of the monitoring alert policy for quarantined content"
  value       = google_monitoring_alert_policy.quarantine_alert.id
}

# Logging
output "logging_sink_name" {
  description = "Name of the logging sink for content moderation logs"
  value       = google_logging_project_sink.content_moderation_logs.name
}

output "logging_sink_destination" {
  description = "Destination of the logging sink for content moderation logs"
  value       = google_logging_project_sink.content_moderation_logs.destination
}

output "logging_sink_writer_identity" {
  description = "Writer identity of the logging sink"
  value       = google_logging_project_sink.content_moderation_logs.writer_identity
}

# Resource Identifiers
output "resource_suffix" {
  description = "Random suffix used for resource naming"
  value       = local.resource_suffix
}

output "resource_prefix" {
  description = "Prefix used for resource naming"
  value       = var.resource_prefix
}

# Configuration Values
output "vertex_ai_location" {
  description = "Location configured for Vertex AI resources"
  value       = var.vertex_ai_location
}

output "storage_class" {
  description = "Storage class configured for Cloud Storage buckets"
  value       = var.storage_class
}

output "bucket_location" {
  description = "Location configured for Cloud Storage buckets"
  value       = local.bucket_location
}

# Function Configuration
output "function_memory_mb" {
  description = "Memory allocation for the content moderation function"
  value       = var.function_memory_mb
}

output "function_timeout" {
  description = "Timeout configured for the content moderation function"
  value       = var.function_timeout
}

output "function_max_instances" {
  description = "Maximum instances configured for the content moderation function"
  value       = var.function_max_instances
}

# Security Configuration
output "uniform_bucket_level_access" {
  description = "Whether uniform bucket-level access is enabled"
  value       = var.enable_uniform_bucket_level_access
}

output "public_access_prevention" {
  description = "Whether public access prevention is enabled"
  value       = var.enable_bucket_public_access_prevention
}

output "bucket_versioning" {
  description = "Whether bucket versioning is enabled"
  value       = var.enable_bucket_versioning
}

# Cost Management
output "lifecycle_age_days" {
  description = "Number of days for lifecycle management transition"
  value       = var.bucket_lifecycle_age_days
}

output "pubsub_retention_duration" {
  description = "Message retention duration for Pub/Sub topics"
  value       = var.pubsub_message_retention_duration
}

# Usage Instructions
output "upload_command" {
  description = "Command to upload content for testing"
  value       = "gsutil cp [local-file] gs://${google_storage_bucket.incoming.name}/"
}

output "list_quarantine_command" {
  description = "Command to list quarantined content"
  value       = "gsutil ls gs://${google_storage_bucket.quarantine.name}/"
}

output "list_approved_command" {
  description = "Command to list approved content"
  value       = "gsutil ls gs://${google_storage_bucket.approved.name}/"
}

output "function_logs_command" {
  description = "Command to view function logs"
  value       = "gcloud functions logs read ${google_cloudfunctions2_function.content_moderator.name} --region=${var.region}"
}

# API Endpoints
output "enabled_apis" {
  description = "List of APIs enabled for this project"
  value       = var.enable_apis
}

# Labels
output "common_labels" {
  description = "Common labels applied to all resources"
  value       = local.common_labels
}

# Deployment Status
output "deployment_complete" {
  description = "Indicates that the deployment is complete"
  value       = "Content moderation infrastructure has been successfully deployed"
}

output "next_steps" {
  description = "Next steps after deployment"
  value = <<-EOT
    1. Test the system by uploading content to: gs://${google_storage_bucket.incoming.name}/
    2. Monitor quarantined content in: gs://${google_storage_bucket.quarantine.name}/
    3. Check approved content in: gs://${google_storage_bucket.approved.name}/
    4. View function logs: gcloud functions logs read ${google_cloudfunctions2_function.content_moderator.name} --region=${var.region}
    5. Set up monitoring alerts and notifications as needed
  EOT
}