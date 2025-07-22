# Project and basic configuration outputs
output "project_id" {
  description = "The GCP project ID where resources were created"
  value       = var.project_id
}

output "region" {
  description = "The GCP region where resources were created"
  value       = var.region
}

output "resource_suffix" {
  description = "The random suffix used for resource naming"
  value       = local.resource_suffix
}

# Pub/Sub resource outputs
output "pubsub_topic_name" {
  description = "Name of the main Pub/Sub topic for data synchronization events"
  value       = google_pubsub_topic.data_sync_events.name
}

output "pubsub_topic_id" {
  description = "Full resource ID of the main Pub/Sub topic"
  value       = google_pubsub_topic.data_sync_events.id
}

output "sync_subscription_name" {
  description = "Name of the sync processing subscription"
  value       = google_pubsub_subscription.sync_subscription.name
}

output "sync_subscription_id" {
  description = "Full resource ID of the sync processing subscription"
  value       = google_pubsub_subscription.sync_subscription.id
}

output "audit_subscription_name" {
  description = "Name of the audit logging subscription"
  value       = google_pubsub_subscription.audit_subscription.name
}

output "audit_subscription_id" {
  description = "Full resource ID of the audit logging subscription"
  value       = google_pubsub_subscription.audit_subscription.id
}

output "dead_letter_queue_topic_name" {
  description = "Name of the dead letter queue topic (if enabled)"
  value       = var.enable_dead_letter_queue ? google_pubsub_topic.dead_letter_queue[0].name : null
}

output "dead_letter_queue_subscription_name" {
  description = "Name of the dead letter queue subscription (if enabled)"
  value       = var.enable_dead_letter_queue ? google_pubsub_subscription.dlq_subscription[0].name : null
}

# Cloud Functions outputs
output "sync_function_name" {
  description = "Name of the data synchronization Cloud Function"
  value       = google_cloudfunctions_function.sync_processor.name
}

output "sync_function_url" {
  description = "HTTPS trigger URL for the sync function"
  value       = google_cloudfunctions_function.sync_processor.https_trigger_url
}

output "audit_function_name" {
  description = "Name of the audit logging Cloud Function"
  value       = google_cloudfunctions_function.audit_logger.name
}

output "audit_function_url" {
  description = "HTTPS trigger URL for the audit function"
  value       = google_cloudfunctions_function.audit_logger.https_trigger_url
}

# Datastore outputs
output "datastore_database_id" {
  description = "ID of the Cloud Datastore database"
  value       = google_datastore_database.default.id
}

output "datastore_location" {
  description = "Location of the Cloud Datastore database"
  value       = google_datastore_database.default.location_id
}

# Service account outputs
output "service_account_email" {
  description = "Email address of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.email
}

output "service_account_name" {
  description = "Name of the service account used by Cloud Functions"
  value       = google_service_account.function_sa.name
}

# Storage outputs
output "function_source_bucket" {
  description = "Name of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.name
}

output "function_source_bucket_url" {
  description = "URL of the Cloud Storage bucket containing function source code"
  value       = google_storage_bucket.function_source.url
}

# External sync topic outputs (if enabled)
output "external_sync_topic_names" {
  description = "Names of external sync topics (if enabled)"
  value       = var.enable_external_sync ? { for k, v in google_pubsub_topic.external_sync_topics : k => v.name } : {}
}

output "external_sync_topic_ids" {
  description = "Full resource IDs of external sync topics (if enabled)"
  value       = var.enable_external_sync ? { for k, v in google_pubsub_topic.external_sync_topics : k => v.id } : {}
}

# Monitoring outputs
output "monitoring_dashboard_id" {
  description = "ID of the monitoring dashboard (if created)"
  value       = var.create_monitoring_dashboard ? google_monitoring_dashboard.sync_dashboard[0].id : null
}

output "monitoring_dashboard_url" {
  description = "URL to access the monitoring dashboard"
  value       = var.create_monitoring_dashboard ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.sync_dashboard[0].id}?project=${var.project_id}" : null
}

# Logging outputs
output "audit_log_sink_name" {
  description = "Name of the audit log sink (if enabled)"
  value       = var.enable_audit_logging ? google_logging_project_sink.audit_sink[0].name : null
}

output "audit_log_sink_writer_identity" {
  description = "Writer identity of the audit log sink (if enabled)"
  value       = var.enable_audit_logging ? google_logging_project_sink.audit_sink[0].writer_identity : null
}

# Notification outputs
output "notification_channel_id" {
  description = "ID of the email notification channel (if created)"
  value       = var.notification_email != null ? google_monitoring_notification_channel.email[0].id : null
}

output "notification_email" {
  description = "Email address configured for notifications"
  value       = var.notification_email
}

# Alert policy outputs
output "function_failure_alert_id" {
  description = "ID of the function failure alert policy (if created)"
  value       = var.notification_email != null ? google_monitoring_alert_policy.function_failure_alert[0].id : null
}

output "message_age_alert_id" {
  description = "ID of the message age alert policy (if created)"
  value       = var.notification_email != null ? google_monitoring_alert_policy.message_age_alert[0].id : null
}

# Configuration summary outputs
output "configuration_summary" {
  description = "Summary of key configuration settings"
  value = {
    project_id              = var.project_id
    region                  = var.region
    environment             = var.environment
    resource_prefix         = var.resource_prefix
    resource_suffix         = local.resource_suffix
    dead_letter_queue_enabled = var.enable_dead_letter_queue
    external_sync_enabled   = var.enable_external_sync
    monitoring_enabled      = var.enable_monitoring
    audit_logging_enabled   = var.enable_audit_logging
    notifications_enabled   = var.notification_email != null
  }
}

# Command-line helpers
output "publisher_command" {
  description = "Example command to publish a test message to the sync topic"
  value = "gcloud pubsub topics publish ${google_pubsub_topic.data_sync_events.name} --message='{\"entity_id\":\"test-001\",\"operation\":\"create\",\"data\":{\"name\":\"Test Entity\",\"status\":\"active\"}}' --project=${var.project_id}"
}

output "subscription_pull_command" {
  description = "Example command to pull messages from the sync subscription"
  value = "gcloud pubsub subscriptions pull ${google_pubsub_subscription.sync_subscription.name} --limit=10 --project=${var.project_id}"
}

output "function_logs_command" {
  description = "Command to view sync function logs"
  value = "gcloud functions logs read ${google_cloudfunctions_function.sync_processor.name} --region=${var.region} --project=${var.project_id}"
}

output "datastore_query_command" {
  description = "Example command to query Datastore entities"
  value = "gcloud datastore query --kind=SyncEntity --project=${var.project_id}"
}

# Resource URLs for console access
output "console_urls" {
  description = "URLs to access resources in the Google Cloud Console"
  value = {
    pubsub_topic = "https://console.cloud.google.com/cloudpubsub/topic/detail/${google_pubsub_topic.data_sync_events.name}?project=${var.project_id}"
    sync_function = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.sync_processor.name}?project=${var.project_id}"
    audit_function = "https://console.cloud.google.com/functions/details/${var.region}/${google_cloudfunctions_function.audit_logger.name}?project=${var.project_id}"
    datastore = "https://console.cloud.google.com/datastore/entities/query?project=${var.project_id}"
    monitoring = var.create_monitoring_dashboard ? "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.sync_dashboard[0].id}?project=${var.project_id}" : null
    logging = "https://console.cloud.google.com/logs/query?project=${var.project_id}"
  }
}

# Testing and validation outputs
output "test_entity_creation" {
  description = "Python code snippet to create a test entity in Datastore"
  value = <<-EOT
from google.cloud import datastore
client = datastore.Client(project='${var.project_id}')
key = client.key('SyncEntity', 'test-entity-001')
entity = datastore.Entity(key=key)
entity.update({
    'name': 'Test Entity',
    'status': 'active',
    'created_at': datastore.helpers.utcnow(),
    'version': 1
})
client.put(entity)
print(f'Created entity: {key.name}')
EOT
}

output "test_message_publish" {
  description = "Python code snippet to publish a test message"
  value = <<-EOT
from google.cloud import pubsub_v1
import json
publisher = pubsub_v1.PublisherClient()
topic_path = publisher.topic_path('${var.project_id}', '${google_pubsub_topic.data_sync_events.name}')
message_data = json.dumps({
    'entity_id': 'test-entity-001',
    'operation': 'create',
    'data': {'name': 'Test Entity', 'status': 'active'}
}).encode('utf-8')
future = publisher.publish(topic_path, message_data)
print(f'Published message: {future.result()}')
EOT
}