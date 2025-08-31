# Project and deployment information
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where regional resources were created"
  value       = var.region
}

output "random_suffix" {
  description = "The random suffix added to resource names for uniqueness"
  value       = random_id.suffix.hex
}

output "deployment_labels" {
  description = "Labels applied to all resources for organization and cost tracking"
  value       = var.labels
}

# Pub/Sub resources
output "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic receiving file notifications"
  value       = google_pubsub_topic.file_notifications.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the Pub/Sub topic"
  value       = google_pubsub_topic.file_notifications.id
}

output "pubsub_subscription_name" {
  description = "Name of the Pub/Sub subscription for consuming messages"
  value       = google_pubsub_subscription.file_processor.name
}

output "pubsub_subscription_id" {
  description = "Full resource ID of the Pub/Sub subscription"
  value       = google_pubsub_subscription.file_processor.id
}

output "subscription_pull_endpoint" {
  description = "Endpoint for pulling messages from the subscription"
  value       = "projects/${var.project_id}/subscriptions/${google_pubsub_subscription.file_processor.name}"
}

# Cloud Storage resources
output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for file uploads"
  value       = google_storage_bucket.file_uploads.name
}

output "storage_bucket_url" {
  description = "URL of the Cloud Storage bucket"
  value       = google_storage_bucket.file_uploads.url
}

output "storage_bucket_location" {
  description = "Location/region of the Cloud Storage bucket"
  value       = google_storage_bucket.file_uploads.location
}

output "storage_bucket_storage_class" {
  description = "Default storage class of the bucket"
  value       = google_storage_bucket.file_uploads.storage_class
}

# Notification configuration
output "notification_id" {
  description = "ID of the Cloud Storage notification configuration"
  value       = google_storage_notification.file_upload_notification.id
}

output "notification_event_types" {
  description = "Event types that trigger notifications"
  value       = var.notification_event_types
}

output "notification_payload_format" {
  description = "Format of the notification payload"
  value       = var.notification_payload_format
}

# Service account information
output "storage_service_account" {
  description = "Service account used by Cloud Storage to publish notifications"
  value       = "service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
}

# Testing and verification commands
output "test_upload_command" {
  description = "Command to test file upload and trigger notification"
  value       = "echo 'Test file content' | gcloud storage cp - gs://${google_storage_bucket.file_uploads.name}/test-file.txt"
}

output "pull_messages_command" {
  description = "Command to pull and view messages from the subscription"
  value       = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.file_processor.name} --limit=5 --auto-ack --project=${var.project_id}"
}

output "list_notifications_command" {
  description = "Command to list notification configurations for the bucket"
  value       = "gcloud storage buckets notifications list gs://${google_storage_bucket.file_uploads.name}"
}

# Monitoring and operational information
output "topic_monitoring_url" {
  description = "Google Cloud Console URL for monitoring the Pub/Sub topic"
  value       = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.file_notifications.name}?project=${var.project_id}"
}

output "subscription_monitoring_url" {
  description = "Google Cloud Console URL for monitoring the subscription"
  value       = "https://console.cloud.google.com/cloudpubsub/subscription/detail/${google_pubsub_subscription.file_processor.name}?project=${var.project_id}"
}

output "bucket_monitoring_url" {
  description = "Google Cloud Console URL for monitoring the storage bucket"
  value       = "https://console.cloud.google.com/storage/browser/${google_storage_bucket.file_uploads.name}?project=${var.project_id}"
}

# Resource summary for documentation
output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    pubsub = {
      topic_name        = google_pubsub_topic.file_notifications.name
      subscription_name = google_pubsub_subscription.file_processor.name
      ack_deadline      = "${var.ack_deadline_seconds}s"
      retention_period  = var.message_retention_duration
    }
    storage = {
      bucket_name     = google_storage_bucket.file_uploads.name
      location        = google_storage_bucket.file_uploads.location
      storage_class   = google_storage_bucket.file_uploads.storage_class
      versioning      = google_storage_bucket.file_uploads.versioning[0].enabled
      uniform_access  = google_storage_bucket.file_uploads.uniform_bucket_level_access
    }
    notification = {
      id             = google_storage_notification.file_upload_notification.id
      event_types    = var.notification_event_types
      payload_format = var.notification_payload_format
    }
  }
}

# Cost estimation information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown (USD) for typical usage patterns"
  value = {
    disclaimer = "Costs are estimates based on us-central1 pricing and typical usage patterns. Actual costs may vary."
    pubsub = {
      topic_operations     = "$0.40 per million operations"
      message_throughput   = "$0.40 per million messages"
      subscription_storage = "$0.27 per GB-month for retained messages"
    }
    storage = {
      standard_storage = "$0.020 per GB-month for STANDARD class"
      nearline_storage = "$0.010 per GB-month for NEARLINE class (after 30 days)"
      coldline_storage = "$0.004 per GB-month for COLDLINE class (after 90 days)"
      operations       = "$0.05 per 10,000 Class A operations, $0.004 per 10,000 Class B operations"
    }
    total_estimate = "~$1-10/month for small to medium workloads (1-100GB storage, <1M messages/month)"
  }
}